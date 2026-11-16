#!/usr/bin/env bash
# ==============================================================================
# Script: youtube-player.sh
# Descrição: Gerenciador do YouTube Miniplayer e Daemon para Waybar e Hyprland
# Uso: youtube-player.sh [toggle|open|close|status|daemon]
# ==============================================================================
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
PID_FILE="$STATE_DIR/youtube-miniplayer.pid"
DAEMON_PID_FILE="$STATE_DIR/youtube-daemon.pid"

SCRIPT_DIR="$HOME/.config/hypr/scripts"
MINIPLAYER_SCRIPT="$SCRIPT_DIR/youtube-miniplayer.py"
DAEMON_SCRIPT="$SCRIPT_DIR/youtube-daemon.py"

mkdir -p "$STATE_DIR"

ensure_daemon() {
    if ! systemctl --user is-active --quiet youtube-daemon.service 2>/dev/null; then
        systemctl --user start youtube-daemon.service 2>/dev/null || true
    fi
}

is_player_open() {
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

close_player() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid="$(cat "$PID_FILE" 2>/dev/null || true)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null || true
            for _ in 1 2 3 4 5; do
                kill -0 "$pid" 2>/dev/null || break
                sleep 0.05
            done
        fi
        rm -f "$PID_FILE"
    fi
    pkill -9 -f "youtube-miniplayer\.py" 2>/dev/null || true
}

open_player() {
    close_player
    ensure_daemon
    hyprctl dispatch focusmonitor DP-1 >/dev/null 2>&1 || true
    hyprctl dispatch exec "python3 $MINIPLAYER_SCRIPT" >/dev/null 2>&1 || true
}

get_status_json() {
    ensure_daemon
    local resp
    resp="$(curl -s --max-time 0.5 http://127.0.0.1:9877/status 2>/dev/null || true)"

    if [ -z "$resp" ]; then
        echo '{"text":"","tooltip":"YouTube Desconectado","class":"disconnected"}'
        return
    fi

    local connected title paused rate
    connected="$(python3 -c "import sys, json; data=json.loads(sys.argv[1]); print('yes' if data.get('connected') else 'no')" "$resp" 2>/dev/null || echo "no")"

    if [ "$connected" != "yes" ]; then
        echo '{"text":"","tooltip":"YouTube: Nenhum vídeo conectado","class":"disconnected"}'
    else
        title="$(python3 -c "import sys, json; data=json.loads(sys.argv[1]); print(data.get('title','Sem título').replace('\"','\\\"'))" "$resp" 2>/dev/null || echo "YouTube")"
        paused="$(python3 -c "import sys, json; data=json.loads(sys.argv[1]); print('yes' if data.get('paused') else 'no')" "$resp" 2>/dev/null || echo "yes")"
        rate="$(python3 -c "import sys, json; data=json.loads(sys.argv[1]); print(f\"{data.get('playbackRate', 1.0)}x\")" "$resp" 2>/dev/null || echo "1.0x")"

        if [ "$paused" == "yes" ]; then
            echo "{\"text\":\"\",\"tooltip\":\"YouTube (Pausado - ${rate}): ${title}\",\"class\":\"paused\"}"
        else
            echo "{\"text\":\"\",\"tooltip\":\"YouTube (Tocando - ${rate}): ${title}\",\"class\":\"playing\"}"
        fi
    fi
}

MODE="${1:-toggle}"

case "$MODE" in
    toggle)
        if is_player_open; then
            close_player
        else
            open_player
        fi
        ;;
    open)
        open_player
        ;;
    close)
        close_player
        ;;
    status)
        get_status_json
        ;;
    daemon)
        ensure_daemon
        ;;
    *)
        echo "Uso: $0 [toggle|open|close|status|daemon]"
        exit 1
        ;;
esac
