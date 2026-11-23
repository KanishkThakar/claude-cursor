# claude-cursor.ps1 - Claude's opt-in cursor for Windows, bound to ONE app window (v3).
# Copyright (c) 2026 Kanishk Thakar. MIT License - https://github.com/KanishkThakar/claude-cursor
#
#   claude-cursor build
#   claude-cursor start  --app "App" [--title TEXT] [X Y]   show it inside that app's window
#   claude-cursor start  --window HWND [X Y]                ...or inside an exact window handle
#   claude-cursor attach --app "App" [--title TEXT] [X Y]   move it into another window
#   claude-cursor move X Y [1]      glide to X,Y (global screen pixels, as UI Automation reports)
#   claude-cursor click X Y         same as: move X Y 1
#   claude-cursor say TEXT          change the label (e.g. "Claude · typing")
#   claude-cursor demo              short tour inside the bound window
#   claude-cursor find "App" [TITLE]  print "hwnd x y w h title"
#   claude-cursor stop | status
#   (start --screen [X Y] gives a whole-screen overlay; use only if the user asks for it)
#
# Same commands and behaviour as the macOS claude-cursor.sh. move/click/say/demo/attach do
# nothing unless the cursor was started, so it stays opt-in.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$Dir   = Join-Path $env:LOCALAPPDATA 'claude-ghost'
$State = Join-Path $Dir 'state.txt'; $PidF = Join-Path $Dir 'pid'; $LastF = Join-Path $Dir 'last'
$LabelF = Join-Path $Dir 'label'; $WidF = Join-Path $Dir 'wid'; $RectF = Join-Path $Dir 'rect'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Bin = Join-Path $Here 'claude-ghost.exe'; $Src = Join-Path $Here 'ghost.cs'
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
$Utf8 = New-Object Text.UTF8Encoding($false)

function Alive {
  if (-not (Test-Path $PidF)) { return $false }
  $p = Get-Process -Id ([int](Get-Content $PidF -Raw)) -ErrorAction SilentlyContinue
  return [bool]($p -and $p.ProcessName -eq 'claude-ghost')
}
function Label {
  if ($env:CLAUDE_CURSOR_LABEL) { return $env:CLAUDE_CURSOR_LABEL }
  if ((Test-Path $LabelF) -and (Get-Item $LabelF).Length -gt 0) { return [IO.File]::ReadAllText($LabelF, $Utf8) }
  return 'Claude'
}
function CurWid { if (Test-Path $WidF) { return (Get-Content $WidF -Raw).Trim() } else { return '0' } }
function WriteState($x, $y, $click, $wid) {
  if ($null -eq $wid) { $wid = CurWid }
  $l = (Label) -replace '[|\r\n]', ''
  [IO.File]::WriteAllText($LastF, "$x $y", $Utf8)
  $stamp = [Guid]::NewGuid().ToString('N')
  [IO.File]::WriteAllText("$State.tmp", "$x|$y|$l|$click|$stamp|$wid`n", $Utf8)
  Move-Item -Force "$State.tmp" $State
}
function NeedRunning { if (-not (Alive)) { 'not running (the cursor is opt-in; start it first)'; exit 0 } }

function Find-Csc {
  foreach ($fw in 'Framework64', 'Framework') {
    $c = Join-Path $env:WINDIR "Microsoft.NET\$fw\v4.0.30319\csc.exe"
    if (Test-Path $c) { return $c }
  }
  throw 'csc.exe (.NET Framework 4) not found. It ships with Windows 10/11; enable ".NET Framework 4.8" in Windows Features.'
}
function Build {
  $csc = Find-Csc
  $out = & $csc /nologo /optimize+ /target:winexe "/out:$Bin" /r:System.Drawing.dll /r:System.Windows.Forms.dll $Src 2>&1
  if ($LASTEXITCODE -ne 0) { $out; throw 'build failed' }
  "built $Bin"
}
function EnsureBuilt {
  if (-not (Test-Path $Bin)) { Build | Out-Null; return }
  if ((Test-Path $Src) -and (Get-Item $Src).LastWriteTime -gt (Get-Item $Bin).LastWriteTime) { Build | Out-Null }
}
function Ghost([string[]]$a) {
  # claude-ghost.exe is a GUI-subsystem exe; capture its stdout explicitly.
  $psi = New-Object Diagnostics.ProcessStartInfo $Bin
  $psi.Arguments = ($a | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '
  $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $true; $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
  $p = [Diagnostics.Process]::Start($psi); $o = $p.StandardOutput.ReadToEnd(); $p.WaitForExit()
  if ($p.ExitCode -ne 0) { return $null }
  return $o.Trim()
}

function ParseTarget([string[]]$a) {
  $app = ''; $title = ''; $wid = ''; $screen = $false; $pos = @()
  for ($i = 0; $i -lt $a.Count; $i++) {
    switch ($a[$i]) {
      '--app'    { $app = $a[++$i] }
      '--title'  { $title = $a[++$i] }
      '--window' { $wid = $a[++$i] }
      '--screen' { $screen = $true }
      default    { $pos += $a[$i] }
    }
  }
  if ($screen) {
    [IO.File]::WriteAllText($RectF, '', $Utf8)
    $x = 400; $y = 300; if ($pos.Count -ge 2) { $x = $pos[0]; $y = $pos[1] }
    return @{ Wid = '0'; X = $x; Y = $y; Desc = 'whole screen' }
  }
  EnsureBuilt
  if ($app) {
    $args2 = @('--find-window', $app); if ($title) { $args2 += $title }
    $info = Ghost $args2
    if (-not $info) { $tt = ''; if ($title) { $tt = ' titled "' + $title + '"' }; 'no visible window for app "' + $app + '"' + $tt + ' (open it first)'; exit 1 }
  } elseif ($wid) {
    $info = Ghost @('--window-info', $wid)
    if (-not $info) { "window $wid not found"; exit 1 }
  } else {
    'name the target: --app "App name" [--title TEXT] or --window HWND (the cursor is bound to one window)'; exit 2
  }
  $f = $info -split ' ', 6
  [IO.File]::WriteAllText($RectF, "$($f[1]) $($f[2]) $($f[3]) $($f[4])", $Utf8)
  $x = [int]$f[1] + [int]([int]$f[3] / 2); $y = [int]$f[2] + [int]([int]$f[4] / 2)
  if ($pos.Count -ge 2) { $x = $pos[0]; $y = $pos[1] }
  return @{ Wid = $f[0]; X = $x; Y = $y; Desc = $(if ($f.Count -gt 5) { $f[5] } else { 'window' }) }
}

$cmd = if ($args.Count -gt 0) { $args[0] } else { 'status' }
$rest = @(); if ($args.Count -gt 1) { $rest = @($args[1..($args.Count - 1)]) }

switch ($cmd) {
  'build' { Build }
  'find'  { EnsureBuilt; $r = Ghost (@('--find-window') + $rest); if ($r) { $r } else { 'not found'; exit 1 } }
  'start' {
    $t = ParseTarget $rest
    [IO.File]::WriteAllText($WidF, $t.Wid, $Utf8)
    if (-not (Alive)) {
      Remove-Item -Force -ErrorAction SilentlyContinue $LabelF
      WriteState $t.X $t.Y 0 $t.Wid
      $p = Start-Process -FilePath $Bin -ArgumentList "`"$State`" $($t.X) $($t.Y) $($t.Wid)" -PassThru
      [IO.File]::WriteAllText($PidF, "$($p.Id)", $Utf8)
      Start-Sleep -Milliseconds 600
      if (-not (Alive)) { 'failed to start'; Remove-Item -Force $PidF; exit 1 }
    } else { WriteState $t.X $t.Y 0 $t.Wid }
    "running in: $($t.Desc) (window $($t.Wid))"
  }
  'attach' {
    NeedRunning; $t = ParseTarget $rest
    [IO.File]::WriteAllText($WidF, $t.Wid, $Utf8)
    WriteState $t.X $t.Y 0 $t.Wid; Start-Sleep -Milliseconds 300
    "attached to: $($t.Desc) (window $($t.Wid))"
  }
  'move'  { NeedRunning; $c = 0; if ($rest.Count -gt 2) { $c = $rest[2] }; WriteState $rest[0] $rest[1] $c; Start-Sleep -Milliseconds 450; 'moved' }
  'click' { NeedRunning; WriteState $rest[0] $rest[1] 1; Start-Sleep -Milliseconds 500; 'clicked' }
  'say' {
    NeedRunning
    [IO.File]::WriteAllText($LabelF, ($rest -join ' '), $Utf8)
    $xy = @(400, 300); if (Test-Path $LastF) { $xy = (Get-Content $LastF -Raw).Trim() -split ' ' }
    WriteState $xy[0] $xy[1] 0
    "label: $($rest -join ' ')"
  }
  'demo' {
    NeedRunning
    $r = @(300, 200, 1100, 700)
    if ((Test-Path $RectF) -and (Get-Item $RectF).Length -gt 0) { $r = (Get-Content $RectF -Raw).Trim() -split ' ' | ForEach-Object { [int]$_ } }
    $cx = $r[0] + [int]($r[2] / 2); $cy = $r[1] + [int]($r[3] / 2); $rx = [int]($r[2] * 0.3); $ry = [int]($r[3] * 0.3)
    $self = $MyInvocation.MyCommand.Path
    & $self say 'Claude · warming up' | Out-Null
    foreach ($a in 0, 45, 90, 135, 180, 225, 270, 315, 360) {
      $rad = $a * [Math]::PI / 180
      WriteState ([int]($cx + $rx * [Math]::Cos($rad))) ([int]($cy + $ry * [Math]::Sin($rad))) 0
      Start-Sleep -Milliseconds 180
    }
    & $self say 'Claude · clicking' | Out-Null
    & $self click ($cx - $rx) ($cy - $ry) | Out-Null; Start-Sleep -Milliseconds 250
    & $self click ($cx + $rx) ($cy - $ry) | Out-Null; Start-Sleep -Milliseconds 250
    & $self click $cx ($cy + $ry) | Out-Null; Start-Sleep -Milliseconds 250
    & $self say 'Claude' | Out-Null
    & $self click $cx $cy | Out-Null
    'demo done'
  }
  'stop' {
    if (Test-Path $State) { [IO.File]::WriteAllText("$State.tmp", "quit`n", $Utf8); Move-Item -Force "$State.tmp" $State }
    Start-Sleep -Milliseconds 500
    if (Alive) { Stop-Process -Id ([int](Get-Content $PidF -Raw)) -Force -ErrorAction SilentlyContinue }
    Remove-Item -Force -ErrorAction SilentlyContinue $PidF, $LabelF, $WidF, $RectF
    'stopped'
  }
  'status' { if (Alive) { "running (window $(CurWid))" } else { 'not running' } }
  default {
    'usage: claude-cursor build|start --app APP [--title T] [X Y]|start --window HWND [X Y]|attach ...|move X Y [1]|click X Y|say TEXT|demo|find APP [TITLE]|stop|status'
    exit 2
  }
}
