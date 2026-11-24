@echo off
rem claude-control.cmd - background computer use (UI Automation) from cmd or PowerShell.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claude-control.ps1" %*
