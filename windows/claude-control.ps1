# claude-control.ps1 - background computer use for Windows (UI Automation). Thin wrapper around
# claude-control.exe, which is built from control.cs by the C# compiler that ships with Windows.
# Copyright (c) 2026 Kanishk Thakar. MIT License - https://github.com/KanishkThakar/claude-cursor
#
#   claude-control windows | ui --app APP | find --app APP --name X | click REF | type REF TEXT [--append]
#   claude-control read [REF] | focus REF          (see control.cs for details)
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Exe = Join-Path $Here 'claude-control.exe'; $Src = Join-Path $Here 'control.cs'
if (-not (Test-Path $Exe) -or ((Test-Path $Src) -and (Get-Item $Src).LastWriteTime -gt (Get-Item $Exe).LastWriteTime)) {
  & (Join-Path $Here 'claude-cursor.ps1') build | Out-Null
}
[Console]::OutputEncoding = [Text.Encoding]::UTF8
& $Exe @args
exit $LASTEXITCODE
