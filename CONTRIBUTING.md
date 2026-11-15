# Contributing to Claude Cursor

Thanks for helping out!

- **Bugs:** open an issue with your OS version, chip (Apple silicon or Intel), the exact command you ran and what you saw.
- **Pull requests:** keep the cursor an *indicator only*. It must never move the real pointer, take focus or perform clicks.
- **Before you send a PR (macOS):**
  ```bash
  cd mac && ./claude-cursor.sh build      # must build with no errors
  ./claude-cursor.sh start --app Finder && ./claude-cursor.sh demo && ./claude-cursor.sh stop
  ```
- Keep the commands the same across platforms (`start`, `attach`, `move`, `click`, `say`, `demo`, `stop`, `status`).
