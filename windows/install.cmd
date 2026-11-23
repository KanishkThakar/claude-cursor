@echo off
rem Double-click me. Builds Claude Cursor, adds "claude-cursor" to your PATH,
rem installs the Claude Code skill and runs a live demo in Notepad.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
echo.
pause
