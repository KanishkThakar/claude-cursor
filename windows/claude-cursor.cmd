@echo off
rem claude-cursor.cmd - run claude-cursor.ps1 from cmd, PowerShell or Claude Code (Git Bash).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claude-cursor.ps1" %*
