# Changelog

## 0.4.0 - 2026-11-24
- Windows version in `windows/`: layered, click-through, owner-bound overlay with the same effects and the same commands as macOS.
- One-click Windows install: `irm .../install.ps1 | iex` or double-click `install.cmd` (builds with the compiler built into Windows, adds to PATH, installs the skill, runs a demo).

## 0.3.0 - 2026-11-16
- The cursor is now bound to one target window: clipped to it, ordered directly above it, follows it, and hides with it.
- `start` and `attach` now take `--app` / `--title` / `--window`; added `find`.
- Windows on other Spaces can be targeted; the cursor appears when the window becomes visible.

## 0.2.0 - 2026-11-16
- Core Animation rewrite: spring glide, tilt, comet trail, sparks, breathing glow, double ripple, press squish, fade in and out, edge-aware label.
- New commands: `click`, `say`, `demo`.

## 0.1.0 - 2026-11-15
- First version: Windows overlay, then a macOS port of the same small arrow.
