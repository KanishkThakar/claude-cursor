# Claude Cursor for Windows

Same idea, same commands as the Mac version: an orange **"Claude"** arrow that lives inside the one window Claude is working in, while you keep your own mouse and keyboard.

## One-click install

**Option A: one line** (PowerShell, no admin):

```powershell
irm https://raw.githubusercontent.com/KanishkThakar/claude-cursor/main/windows/install.ps1 | iex
```

**Option B: double-click.** Download the repo ([ZIP](https://github.com/KanishkThakar/claude-cursor/archive/refs/heads/main.zip)), unzip, open `windows\` and double-click **`install.cmd`**.

The installer:
1. copies the files to `%LOCALAPPDATA%\Programs\ClaudeCursor` and builds `claude-ghost.exe` with the C# compiler that already ships with Windows 10/11 (no Visual Studio, no .NET SDK);
2. adds `claude-cursor` to your user `PATH`;
3. installs the Claude Code skill to `%USERPROFILE%\.claude\skills\claude-cursor`;
4. opens Notepad and runs a live demo inside it.

Flags: `install.cmd -NoSkill`, `-NoDemo`, `-Uninstall`.

## Try it

```powershell
claude-cursor start --app notepad          # appears inside Notepad's window
claude-cursor say "Claude · reading"
claude-cursor click 600 400                # global screen pixels
claude-cursor demo
claude-cursor stop
```

`--app` matches the process name (`notepad`, `winword`, `chrome`) or the window title (`Calculator`). Works from cmd, PowerShell and Git Bash (the shell Claude Code uses on Windows).

## How it works

| File | Purpose |
|---|---|
| `ghost.cs` | The overlay: a per-pixel-alpha layered window (`WS_EX_LAYERED \| TRANSPARENT \| NOACTIVATE \| TOOLWINDOW`) drawn with GDI+ at 60 fps |
| `claude-cursor.ps1` | Controller: `start` / `attach` / `move` / `click` / `say` / `demo` / `find` / `stop` / `status` |
| `claude-cursor.cmd`, `claude-cursor` | Wrappers for cmd/PowerShell and Git Bash |
| `install.ps1`, `install.cmd` | One-click installer |

- **Window-bound:** the overlay is *owned* by the target window (`GWLP_HWNDPARENT`), so Windows keeps it directly above that window and nothing else. Other windows cover it; it follows moves and resizes (frame from `DWMWA_EXTENDED_FRAME_BOUNDS`); it hides when the target is minimised, closed or cloaked on another virtual desktop.
- **Never takes over:** click-through, never activated, no taskbar button. Your pointer is never moved.
- **DPI aware:** per-monitor v2, so coordinates are physical pixels, the same as UI Automation `BoundingRectangle`.
- **State:** `%LOCALAPPDATA%\claude-ghost\state.txt`, same `x|y|label|click|stamp|hwnd` format as macOS.
