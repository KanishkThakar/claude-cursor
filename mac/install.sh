#!/bin/bash
# install.sh - build Claude Cursor for macOS and (optionally) install it as a Claude Code skill.
# Copyright (c) 2026 Kanishk Thakar. MIT License - https://github.com/KanishkThakar/claude-cursor
#
#   ./install.sh            build the cursor binary next to this script
#   ./install.sh --skill    also install the "claude-cursor" skill into ~/.claude/skills/claude-cursor
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

[ "$(uname -s)" = "Darwin" ] || { echo "This is the macOS version. See windows/ for Windows."; exit 1; }
xcode-select -p >/dev/null 2>&1 || { echo "Xcode Command Line Tools are missing. Run: xcode-select --install"; exit 1; }

chmod +x "$HERE/claude-cursor.sh"
"$HERE/claude-cursor.sh" build

if [ "${1:-}" = "--skill" ]; then
  DEST="$HOME/.claude/skills/claude-cursor"
  if [ -e "$DEST" ] && [ ! -f "$DEST/.installed-by-claude-cursor" ]; then
    echo "$DEST already exists and was not created by this installer; leaving it alone."; exit 1
  fi
  mkdir -p "$DEST/scripts"
  cp "$ROOT/skill/SKILL.md" "$DEST/SKILL.md"
  cp "$HERE/ghost.swift" "$HERE/claude-cursor.sh" "$DEST/scripts/"
  chmod +x "$DEST/scripts/claude-cursor.sh"
  touch "$DEST/.installed-by-claude-cursor"
  "$DEST/scripts/claude-cursor.sh" build >/dev/null
  echo "Installed the skill to $DEST"
  echo "In Claude Code, try:  /claude-cursor open TextEdit and type hello"
fi

echo
echo "Try it:"
echo "  $HERE/claude-cursor.sh start --app Finder"
echo "  $HERE/claude-cursor.sh demo"
echo "  $HERE/claude-cursor.sh stop"
