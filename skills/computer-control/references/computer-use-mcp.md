# Existing computer-use-mcp connector

These notes describe the installed `computer-use-mcp` 1.8.0 package inspected on 2026-10-18. Its upstream is https://github.com/domdomegg/computer-use-mcp. Re-read the live tool schema if the installed version changes.

The user-scoped server is named `computer-use-mcp` and exposes a tool named `computer`. Use the fully qualified tool name actually discovered in your session. Its arguments are `action`, optional `coordinate: [x, y]`, and optional `text`.

Relevant actions from the inspected schema:

| Action | Arguments | Purpose |
|---|---|---|
| `get_screenshot` | none | Capture the desktop |
| `get_cursor_position` | none | Read cursor position in API image coordinates |
| `mouse_move` | `coordinate` | Move the pointer without clicking |
| `left_click` | optional `coordinate` | Move if requested, then click |
| `key` | `text` | Send a supported key or key combination |
| `type` | `text` | Type into the currently focused field |
| `scroll` | `coordinate`, `text` | Move to the point and scroll; e.g. `down:300` |

This controller uses global desktop input. It does not bind clicks or keystrokes to a named app. A wrong foreground window can receive the action even when the MCP call returns success.

The package rescales its screenshots and converts API-image coordinates into logical screen coordinates internally. Use coordinates from its own current screenshot. Do not multiply coordinates by two for Retina. `get_cursor_position` uses the corresponding API-image coordinate space. Screenshots include a red cursor crosshair; compare that marker with the target after an action.

For a pointer-only test, the call sequence is `get_screenshot`, `get_cursor_position`, `mouse_move` to an observed neutral point, `get_cursor_position`, and `get_screenshot`. Select coordinates from the actual screenshot; this document intentionally supplies no fixed coordinates.

Connection, capture, movement and typing can fail independently. Diagnose the exact step. Respect app-access restrictions and organizational controls across all connectors. Never route a denied action through this global controller as a workaround.
