#!/usr/bin/env bash
# Script para alternar/abrir o calendário interativo no Hyprland
# Uso: calendar.sh [toggle|open|close]
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
PID_FILE="$STATE_DIR/calendar.pid"
CAL_SCRIPT="$HOME/.config/hypr/scripts/calendar-popup.py"

mkdir -p "$STATE_DIR"

is_open() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid="$(cat "$PID_FILE" 2>/dev/null || true)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
        rm -f "$PID_FILE"
    fi
    return 1
}

close_cal() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid="$(cat "$PID_FILE" 2>/dev/null || true)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
        rm -f "$PID_FILE"
    fi
    pkill -f "python3.*calendar-popup.py" 2>/dev/null || true
    pkill -f "python3.*calendar.py" 2>/dev/null || true
}

open_cal() {
    close_cal
    python3 "$CAL_SCRIPT" &
    echo $! > "$PID_FILE"
}

MODE="${1:-toggle}"

case "$MODE" in
    toggle)
        if is_open; then
            close_cal
        else
            open_cal
        fi
        ;;
    open)
        open_cal
        ;;
    close)
        close_cal
        ;;
    *)
        echo "Uso: $0 [toggle|open|close]" >&2
        exit 1
        ;;
esac
