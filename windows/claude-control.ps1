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
  $csc = $null
  foreach ($fw in 'Framework64', 'Framework') { $c = Join-Path $env:WINDIR "Microsoft.NET\$fw\v4.0.30319\csc.exe"; if (Test-Path $c) { $csc = $c; break } }
  if (-not $csc) { throw 'csc.exe (.NET Framework 4) not found' }
  $out = & $csc /nologo /optimize+ /target:exe "/out:$Exe" $Src 2>&1
  if ($LASTEXITCODE -ne 0) { $out; throw 'build failed (claude-control)' }
}
[Console]::OutputEncoding = [Text.Encoding]::UTF8
& $Exe @args
exit $LASTEXITCODE
