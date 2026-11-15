---
name: claude-cursor
description: Show Claude's own orange "Claude" cursor inside the one app window Claude is working in on macOS, while the user keeps their own mouse and keyboard. Opt-in only. Use when the user says "cursor", "show me where you're clicking", "show your cursor", or invokes /claude-cursor <task>.
---

# Claude Cursor

An orange arrow labelled "Claude" that shows where Claude is acting inside the target app window. It is an indicator only. It never moves the user's pointer, never takes focus, is click-through, and has no Dock icon. Real clicks and typing must go through a background, app-bound controller (for example an Accessibility-based computer-use tool). Never use the cursor to fake an action.

The cursor is drawn only inside the target window. It is clipped to it and sits directly above it in the window stack, so other windows cover it. It follows the window when it moves and hides when the window is minimised, closed or on another Space.

Script: `"${CLAUDE_SKILL_DIR}/scripts/claude-cursor.sh"`, called `CC` below. Coordinates are global top-left points, the same space as Accessibility `AXPosition`.

## Rules

- **Opt-in.** Start the cursor only when the user invokes `/claude-cursor <task>` or asks to see it. `/claude-cursor off` runs `CC stop`.
- **Bind to the window.** Open or locate the target app first, then run `CC start --app "<App>" [--title "<window title>"]` (or `--window <CGWindowID>`). When the task moves to another window, run `CC attach --app ...`. Use `--screen` (a whole-screen overlay) only if the user explicitly asks for it.
- **Point before acting.** Before each action on an element, move to the centre of its AX frame (`AXPosition` + `AXSize`/2):
  - for clicks, run `CC click X Y` (it ripples);
  - for focus, hover or reads, run `CC move X Y`.
- **Narrate.** Show the current step on the label, for example `CC say "Claude · typing"`, and reset it with `CC say Claude`.
- **Always stop.** Run `CC stop` at the end of the task, including after failures. The cursor also exits by itself after 20 minutes without updates.
- **Confirm consequential actions.** Messages, posts and purchases still need the user's explicit confirmation.

## Commands

| Command | What it does |
|---|---|
| `CC start --app "App" [--title T] [X Y]` | Show the cursor inside that app's window |
| `CC attach --app "App" [--title T]` | Move it into another window |
| `CC move X Y [1]` | Glide to a point (`1` adds the click ripple) |
| `CC click X Y` | Glide and ripple |
| `CC say TEXT` | Change the label |
| `CC find "App" [TITLE]` | Print `wid x y w h title` |
| `CC demo` | Short show-off tour inside the bound window |
| `CC status` / `CC stop` | Report status / fade out and quit |
