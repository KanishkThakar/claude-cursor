# Changelog

## 0.5.0 - 2026-11-24
- `claude-control` for Windows: background computer use (windows, ui, find, click, type, read, focus) through the native IUIAutomation COM API, with the cursor gliding to every element. The managed .NET client sees classic Win32 controls as bare panes on Windows build 26100, so it isn't used.
- `/computer-control` skill (macOS + Windows): background browser work, app-bound desktop control, diagnosis, and the cursor. Installed by both installers next to `/claude-cursor`.
- Skills moved to `skills/`.
- Demo videos for macOS and Windows in `docs/`. The Windows one is recorded by CI on a real Windows machine.

## 0.4.0 - 2026-11-24
- Windows version in `windows/`: layered, click-through, owner-bound overlay with the same effects and the same commands as macOS.
- One-click Windows install: `irm .../install.ps1 | iex` or double-click `install.cmd` (builds with the compiler built into Windows, adds to PATH, installs the skill, runs a demo).
- CI builds and smoke-tests the Windows cursor and both installers on a real Windows runner, and attaches `ClaudeCursor-windows.zip` to releases.

## 0.3.0 - 2026-11-16
- The cursor is now bound to one target window: clipped to it, ordered directly above it, follows it, and hides with it.
- `start` and `attach` now take `--app` / `--title` / `--window`; added `find`.
- Windows on other Spaces can be targeted; the cursor appears when the window becomes visible.

## 0.2.0 - 2026-11-16
- Core Animation rewrite: spring glide, tilt, comet trail, sparks, breathing glow, double ripple, press squish, fade in and out, edge-aware label.
- New commands: `click`, `say`, `demo`.

## 0.1.0 - 2026-11-15
- First version: Windows overlay, then a macOS port of the same small arrow.
