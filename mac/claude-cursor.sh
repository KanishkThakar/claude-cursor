#!/bin/bash
# claude-cursor.sh - Claude's opt-in cursor, bound to ONE app window (v3).
# Copyright (c) 2026 Kanishk Thakar. MIT License - https://github.com/KanishkThakar/claude-cursor
#
#   claude-cursor.sh build
#   claude-cursor.sh start  --app "App" [--title TEXT] [X Y]   show it inside that app's window
#   claude-cursor.sh start  --window WID [X Y]                 ...or inside an exact CGWindowID
#   claude-cursor.sh attach --app "App" [--title TEXT] [X Y]   move it into another window
#   claude-cursor.sh attach --window WID [X Y]
#   claude-cursor.sh move X Y [click]      glide to X,Y (global top-left points, as AX reports)
#   claude-cursor.sh click X Y             same as: move X Y 1
#   claude-cursor.sh say TEXT              change the label (e.g. "Claude · typing")
#   claude-cursor.sh demo                  short tour inside the bound window
#   claude-cursor.sh find "App" [TITLE]    print "wid x y w h title" of that app's front window
#   claude-cursor.sh stop | status
#   (start --screen [X Y] gives the old whole-screen overlay; use only if the user asks for it)
#
# The cursor is drawn only inside the target window, ordered just above it: other windows cover
# it, it follows the window, and it hides when the window is minimised/closed/on another Space.
# It never moves the real pointer and never takes focus. move/click/say/demo/attach do nothing
# unless it was started, so the cursor stays opt-in.
set -euo pipefail

DIR="$HOME/Library/Caches/claude-ghost"
STATE="$DIR/state.txt"; PIDF="$DIR/pid"; LAST="$DIR/last"; LABELF="$DIR/label"; WIDF="$DIR/wid"; RECTF="$DIR/rect"
HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HERE/claude-ghost"; SRC="$HERE/ghost.swift"
mkdir -p "$DIR"

alive() { [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; }
label() { if [ -n "${CLAUDE_CURSOR_LABEL:-}" ]; then echo "$CLAUDE_CURSOR_LABEL"; elif [ -s "$LABELF" ]; then cat "$LABELF"; else echo Claude; fi; }
cur_wid() { [ -s "$WIDF" ] && cat "$WIDF" || echo 0; }
write_state() {   # x y click [wid]
  local l w; l="$(label | tr -d '|\n')"; w="${4:-$(cur_wid)}"
  printf '%s %s\n' "$1" "$2" > "$LAST"
  printf '%s|%s|%s|%s|%s|%s\n' "$1" "$2" "$l" "$3" "$RANDOM$RANDOM" "$w" > "$STATE.tmp" && mv -f "$STATE.tmp" "$STATE"
}
need_running() { alive || { echo "not running (the cursor is opt-in; start it first)"; exit 0; }; }
ensure_built() { if [ ! -x "$BIN" ] || [ "$SRC" -nt "$BIN" ]; then "$0" build >/dev/null; fi; }

# Parse target options; sets T_WID T_X T_Y (defaults to the window centre) and T_DESC.
parse_target() {
  local app="" title="" wid="" screen=0 pos=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --app) app="$2"; shift 2 ;;
      --title) title="$2"; shift 2 ;;
      --window) wid="$2"; shift 2 ;;
      --screen) screen=1; shift ;;
      *) pos+=("$1"); shift ;;
    esac
  done
  if [ $screen = 1 ]; then T_WID=0; T_DESC="whole screen"; T_X="${pos[0]:-400}"; T_Y="${pos[1]:-300}"; printf '' > "$RECTF"; return; fi
  ensure_built
  local info
  if [ -n "$app" ]; then
    info="$("$BIN" --find-window "$app" ${title:+"$title"})" || { echo "no visible window for app \"$app\"${title:+ titled \"$title\"} (open it first)"; exit 1; }
  elif [ -n "$wid" ]; then
    info="$("$BIN" --window-info "$wid")" || { echo "window $wid not found"; exit 1; }
  else
    echo "name the target: --app \"App name\" [--title TEXT] or --window WID (the cursor is bound to one window)"; exit 2
  fi
  read -r T_WID wx wy ww wh T_DESC <<< "$info"
  printf '%s %s %s %s\n' "$wx" "$wy" "$ww" "$wh" > "$RECTF"
  T_X="${pos[0]:-$((wx + ww / 2))}"; T_Y="${pos[1]:-$((wy + wh / 2))}"
}

case "${1:-status}" in
  build)
    xcode-select -p >/dev/null 2>&1 || { echo "Xcode Command Line Tools missing: the user must run 'xcode-select --install' and click Install."; exit 1; }
    swiftc -O -o "$BIN" "$SRC" -framework AppKit -framework QuartzCore
    echo "built $BIN"
    ;;
  find)
    ensure_built; shift; "$BIN" --find-window "$@"
    ;;
  start)
    shift; parse_target "$@"
    echo "$T_WID" > "$WIDF"
    if ! alive; then
      rm -f "$LABELF"
      write_state "$T_X" "$T_Y" 0 "$T_WID"
      nohup "$BIN" "$STATE" "$T_X" "$T_Y" "$T_WID" >/dev/null 2>&1 &
      echo $! > "$PIDF"
      sleep 0.6
      alive || { echo "failed to start"; rm -f "$PIDF"; exit 1; }
    else
      write_state "$T_X" "$T_Y" 0 "$T_WID"
    fi
    echo "running in: $T_DESC (window $T_WID)"
    ;;
  attach)
    need_running; shift; parse_target "$@"
    echo "$T_WID" > "$WIDF"
    write_state "$T_X" "$T_Y" 0 "$T_WID"; sleep 0.3
    echo "attached to: $T_DESC (window $T_WID)"
    ;;
  move)
    need_running
    write_state "${2:?x}" "${3:?y}" "${4:-0}"
    sleep 0.45
    echo moved
    ;;
  click)
    need_running
    write_state "${2:?x}" "${3:?y}" 1
    sleep 0.5
    echo clicked
    ;;
  say)
    need_running
    shift; printf '%s' "$*" > "$LABELF"
    read -r X Y < "$LAST" || { X=400; Y=300; }
    write_state "$X" "$Y" 0
    echo "label: $*"
    ;;
  demo)
    need_running
    if [ -s "$RECTF" ]; then read -r WX WY WW WH < "$RECTF"; else WX=300; WY=200; WW=1100; WH=700; fi
    CX=$((WX + WW / 2)); CY=$((WY + WH / 2)); RX=$((WW * 3 / 10)); RY=$((WH * 3 / 10))
    "$0" say "Claude · warming up" >/dev/null
    for a in 0 45 90 135 180 225 270 315 360; do
      read -r X Y < <(awk -v a="$a" -v cx="$CX" -v cy="$CY" -v rx="$RX" -v ry="$RY" 'BEGIN{r=a*3.14159265/180; printf "%d %d\n", cx+rx*cos(r), cy+ry*sin(r)}')
      write_state "$X" "$Y" 0; sleep 0.18
    done
    "$0" say "Claude · clicking" >/dev/null
    "$0" click $((CX - RX)) $((CY - RY)) >/dev/null; sleep 0.25
    "$0" click $((CX + RX)) $((CY - RY)) >/dev/null; sleep 0.25
    "$0" click "$CX" $((CY + RY)) >/dev/null; sleep 0.25
    "$0" say "Claude" >/dev/null
    "$0" click "$CX" "$CY" >/dev/null
    echo "demo done"
    ;;
  stop)
    if [ -f "$STATE" ]; then echo quit > "$STATE.tmp" && mv -f "$STATE.tmp" "$STATE"; fi
    sleep 0.5
    if alive; then kill "$(cat "$PIDF")" 2>/dev/null || true; fi
    rm -f "$PIDF" "$LABELF" "$WIDF" "$RECTF"
    echo stopped
    ;;
  status)
    if alive; then echo "running (window $(cur_wid))"; else echo "not running"; fi
    ;;
  *)
    echo "usage: $0 build|start --app APP [--title T] [X Y]|start --window WID [X Y]|attach ...|move X Y [click]|click X Y|say TEXT|demo|find APP [TITLE]|stop|status"; exit 2
    ;;
esac
