# install.ps1 - one-click installer for Claude Cursor on Windows 10/11.
# Copyright (c) 2026 Kanishk Thakar. MIT License - https://github.com/KanishkThakar/claude-cursor
#
# One line, no admin, nothing else to install (it uses the C# compiler built into Windows):
#   irm https://raw.githubusercontent.com/KanishkThakar/claude-cursor/main/windows/install.ps1 | iex
# Or double-click install.cmd in a downloaded copy of the repo.
#
# What it does:
#   1. copies the Windows files to %LOCALAPPDATA%\Programs\ClaudeCursor and builds claude-ghost.exe
#   2. adds that folder to your user PATH, so `claude-cursor` works in any new terminal
#   3. installs the Claude Code skills /claude-cursor and /computer-control
#   4. opens Notepad and runs a live demo inside it
# Options (when run as a file): -NoSkill  -NoDemo  -Uninstall
$NoSkill = ($args -contains '-NoSkill') -or $env:CLAUDE_CURSOR_NOSKILL
$NoDemo = ($args -contains '-NoDemo') -or $env:CLAUDE_CURSOR_NODEMO
$Uninstall = ($args -contains '-Uninstall')
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$Repo  = 'KanishkThakar/claude-cursor'
$Dest  = Join-Path $env:LOCALAPPDATA 'Programs\ClaudeCursor'
$Skills = Join-Path $env:USERPROFILE '.claude\skills'
$Files = 'ghost.cs', 'claude-cursor.ps1', 'claude-cursor.cmd', 'claude-cursor', 'claude-control.ps1', 'claude-control.cmd', 'claude-control'
$SkillNames = 'claude-cursor', 'computer-control'

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }
function Banner {
  $o = 'DarkYellow'
  Say ''
  Say '      /\        ____ _                 _         ____' $o
  Say '     /  \      / ___| | __ _ _   _  __| | ___   / ___|   _ _ __ ___  ___  _ __' $o
  Say '    / /\ \    | |   | |/ _` | | | |/ _` |/ _ \ | |  | | | | ''__/ __|/ _ \| ''__|' $o
  Say '   / /__\ \   | |___| | (_| | |_| | (_| |  __/ | |__| |_| | |  \__ \ (_) | |' $o
  Say '  /_/ /\ \_\   \____|_|\__,_|\__,_|\__,_|\___|  \____\__,_|_|  |___/\___/|_|' $o
  Say '       \/      see where your AI clicks, keep your own mouse' 'DarkGray'
  Say ''
}
function Step($n, $msg) { Write-Host "  [$n/4] " -ForegroundColor DarkYellow -NoNewline; Write-Host $msg }

function Path-Remove {
  $p = [Environment]::GetEnvironmentVariable('Path', 'User')
  if ($p) { [Environment]::SetEnvironmentVariable('Path', (($p -split ';') | Where-Object { $_ -and $_ -ne $Dest }) -join ';', 'User') }
}

Banner

if ($Uninstall) {
  if (Test-Path (Join-Path $Dest 'claude-cursor.ps1')) { & (Join-Path $Dest 'claude-cursor.ps1') stop | Out-Null }
  Path-Remove
  foreach ($n in $SkillNames) { $d = Join-Path $Skills $n; if (Test-Path (Join-Path $d '.installed-by-claude-cursor')) { Remove-Item -Recurse -Force $d } }
  if (Test-Path $Dest) { Remove-Item -Recurse -Force $Dest }
  Say '  Claude Cursor removed.' Green
  return
}

if ([Environment]::OSVersion.Platform -ne 'Win32NT') { Say '  This is the Windows installer. On macOS run mac/install.sh.' Red; return }

# 1. Get the files: next to this script if we have a local copy, else download from GitHub.
Step 1 'Getting Claude Cursor'
$Src = $null
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'ghost.cs'))) { $Src = $PSScriptRoot
  $SkillMd = Join-Path $PSScriptRoot 'skill\SKILL.md'
  if (-not (Test-Path $SkillMd)) { $SkillMd = Join-Path $PSScriptRoot '..\skill\SKILL.md' }
}
else {
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
  $tmp = Join-Path $env:TEMP ('claude-cursor-' + [Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force $tmp | Out-Null
  $zip = Join-Path $tmp 'repo.zip'
  Invoke-WebRequest -UseBasicParsing "https://github.com/$Repo/archive/refs/heads/main.zip" -OutFile $zip
  Expand-Archive -Force $zip $tmp
  $root = Get-ChildItem $tmp -Directory | Select-Object -First 1
  $Src = Join-Path $root.FullName 'windows'; $SkillSrc = Join-Path $root.FullName 'skills'
}
if (Test-Path (Join-Path $Dest 'claude-cursor.ps1')) { try { & (Join-Path $Dest 'claude-cursor.ps1') stop | Out-Null } catch { } }
New-Item -ItemType Directory -Force $Dest | Out-Null
foreach ($f in $Files) { Copy-Item -Force (Join-Path $Src $f) $Dest }
Say "        -> $Dest" DarkGray

# 2. Build with the compiler that ships with Windows.
Step 2 'Building the cursor (no Visual Studio needed)'
& (Join-Path $Dest 'claude-cursor.ps1') build | Out-Null
Say '        -> claude-ghost.exe ready' DarkGray
$p = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not (($p -split ';') -contains $Dest)) {
  [Environment]::SetEnvironmentVariable('Path', ((@($p, $Dest) | Where-Object { $_ }) -join ';'), 'User')
}
$env:Path = "$env:Path;$Dest"
Say '        -> added to your PATH: claude-cursor' DarkGray

# 3. Claude Code skills: /claude-cursor (the cursor) and /computer-control (background computer use).
Step 3 'Installing the Claude Code skills'
if ($NoSkill) { Say '        -> skipped (-NoSkill)' DarkGray }
else {
  foreach ($n in $SkillNames) {
    $d = Join-Path $Skills $n
    if ((Test-Path $d) -and -not (Test-Path (Join-Path $d '.installed-by-claude-cursor'))) {
      Say "        -> $d exists and wasn't made by this installer; leaving it alone" Yellow; continue
    }
    New-Item -ItemType Directory -Force (Join-Path $d 'scripts') | Out-Null
    Copy-Item -Recurse -Force (Join-Path (Join-Path $SkillSrc $n) '*') $d
    foreach ($f in $Files + 'claude-ghost.exe') { Copy-Item -Force (Join-Path $Dest $f) (Join-Path $d 'scripts') }
    New-Item -ItemType File -Force (Join-Path $d '.installed-by-claude-cursor') | Out-Null
    Say "        -> /$n is ready in Claude Code" DarkGray
  }
}

# 4. Live demo.
Step 4 'Live demo'
if ($NoDemo) { Say '        -> skipped (-NoDemo)' DarkGray }
else {
  $np = Start-Process notepad -PassThru
  Start-Sleep -Milliseconds 1500
  $cc = Join-Path $Dest 'claude-cursor.ps1'
  $out = & $cc start --app notepad
  Say "        -> $out" DarkGray
  if ($out -like 'running*') {
    & $cc demo | Out-Null
    & $cc say ('Claude ' + [char]0xB7 + ' hi there') | Out-Null
    Start-Sleep -Seconds 2
    & $cc stop | Out-Null
  }
}

Say ''
Say '  Done. Open a NEW terminal and try:' Green
Say '    claude-cursor start --app notepad'
Say '    claude-cursor demo'
Say '    claude-cursor stop'
Say ''
Say '    claude-control ui --app notepad' 
Say ''
Say '  In Claude Code:  /computer-control cursor open Notepad and type hello' DarkYellow
Say ''
