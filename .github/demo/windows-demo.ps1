# Scripted demo recorded by CI: Claude drives Notepad in the background while the
# Claude Cursor shows where. Nothing here touches the real mouse or keyboard.
$ErrorActionPreference = 'Stop'
$W = Join-Path $PSScriptRoot '..\..\windows'
$CC = Join-Path $W 'claude-cursor.ps1'; $CTL = Join-Path $W 'claude-control.ps1'
$dot = [char]0xB7
function Ref($lines, $types) {
  foreach ($l in $lines) { foreach ($t in $types) { if ($l -match "^(e\d+)\s+$t\s") { return $Matches[1] } } }
  return $null
}
& $CC start --app notepad | Write-Host
Start-Sleep -Milliseconds 800
& $CC say "Claude $dot looking around" | Out-Null
$rect = (Get-Content (Join-Path $env:LOCALAPPDATA 'claude-ghost\rect') -Raw).Trim() -split ' ' | ForEach-Object { [int]$_ }
$cx = $rect[0] + [int]($rect[2] / 2); $cy = $rect[1] + [int]($rect[3] / 2)
foreach ($p in @(@(-200, -80), @(180, -60), @(160, 120), @(-140, 100))) { & $CC move ($cx + $p[0]) ($cy + $p[1]) | Out-Null; Start-Sleep -Milliseconds 250 }

& $CTL ui --app notepad --all 2>&1 | Write-Host
& $CTL windows 2>&1 | Write-Host
$ui = & $CTL ui --app notepad 2>&1
$ui | Write-Host
$edit = Ref $ui @('Edit', 'Document')
if (-not $edit) { throw 'no text area found in Notepad' }
$first = $true
foreach ($w in 'Hello from Claude!', ' I am typing into Notepad', ' in the background,', ' through UI Automation.', "`r`nYour mouse and keyboard", ' are still yours.') {
  if ($first) { & $CTL type $edit $w | Write-Host; $first = $false } else { & $CTL type $edit $w --append | Write-Host }
  Start-Sleep -Milliseconds 350
}
Start-Sleep -Milliseconds 600
$menu = & $CTL find --app notepad --name File
$file = Ref $menu @('MenuItem')
if ($file) {
  & $CTL click $file | Write-Host; Start-Sleep -Milliseconds 1200
  $menu = & $CTL find --app notepad --name File; $file = Ref $menu @('MenuItem')
  if ($file) { & $CTL click $file | Write-Host }
  Start-Sleep -Milliseconds 500
}
$ui = & $CTL ui --app notepad; $edit = Ref $ui @('Edit', 'Document')
$text = & $CTL read $edit
"read back: $text" | Write-Host
if ($text -notlike 'Hello from Claude!*') { throw 'read-back did not match' }
& $CC say "Claude $dot done" | Out-Null; & $CC click $cx $cy | Out-Null
Start-Sleep -Milliseconds 1200
& $CC stop | Out-Null
