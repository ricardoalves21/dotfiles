#!/usr/bin/env bash
# Gerenciador de Wallpaper de Vídeo para Hyprland via mpvpaper.
#
# Permite escolher um vídeo por monitor ou remover o vídeo para voltar ao wallpaper
# estático (awww / hyprpaper).
#
# Uso: videowallpaper.sh <menu|set <monitor> <arquivo>|stop [monitor|all]|restore|current [monitor]|list|preview <arquivo>>
set -uo pipefail

export PATH="$HOME/.local/bin:$PATH"

VIDEO_DIR="${VIDEO_WALLPAPER_DIR:-$HOME/Vídeos/video_wallpaper}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
PREVIEW_SECS="${PREVIEW_SECS:-6}"
OFF_LABEL="Sem vídeo (restaurar imagem)"
PREVIEW_LABEL="Prévia…"
# --auto-pause (-p) pausa a decodificação quando as janelas cobrem o wallpaper, economizando CPU/GPU
MPV_OPTS="--no-audio --loop-file=inf --really-quiet --no-osc --panscan=1.0 --hwdec=auto"

mkdir -p "$STATE_DIR"

list_videos() {
    find -L "$VIDEO_DIR" -maxdepth 1 -type f \
        \( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.webm' \
           -o -iname '*.mov' -o -iname '*.avi' \) -printf '%f\n' 2>/dev/null | sort
}

get_focused_monitor() {
    local mon=""
    mon="$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.monitor // empty' 2>/dev/null)"
    if [ -z "$mon" ]; then
        mon="$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | .name' 2>/dev/null | head -n1)"
    fi
    if [ -z "$mon" ]; then
        mon="$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].name // empty' 2>/dev/null)"
    fi
    echo "${mon:-HDMI-A-1}"
}

all_monitors() {
    hyprctl monitors -j 2>/dev/null | jq -r '.[].name' 2>/dev/null || echo "HDMI-A-1"
}

state_file_for() {
    local mon="$1"
    echo "$STATE_DIR/video-wallpaper-${mon}"
}

pid_file_for() {
    local mon="$1"
    echo "$STATE_DIR/mpvpaper-${mon}.pid"
}

current_video() {
    local mon="${1:-$(get_focused_monitor)}"
    local sfile; sfile="$(state_file_for "$mon")"
    if [ -f "$sfile" ]; then
        cat "$sfile"
    else
        echo "off"
    fi
}

stop_video() {
    local target="${1:-$(get_focused_monitor)}"
    if [ "$target" = "all" ]; then
        while read -r m; do
            [ -n "$m" ] && stop_video "$m"
        done < <(all_monitors)
        return 0
    fi

    local pfile; pfile="$(pid_file_for "$target")"
    local sfile; sfile="$(state_file_for "$target")"

    if [ -f "$pfile" ]; then
        local pid; pid="$(cat "$pfile" 2>/dev/null)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
        rm -f "$pfile"
    fi

    # Garante encerramento de qualquer mpvpaper associado àquele monitor
    pkill -f "mpvpaper.*[[:space:]]${target}[[:space:]]" 2>/dev/null || true
    rm -f "$sfile"
}

set_video() {
    local mon="$1"
    local name="$2"
    local path="$VIDEO_DIR/$name"

    if [ ! -f "$path" ]; then
        notify-send -u critical -a "Wallpaper de Vídeo" "Arquivo não encontrado" "$name"
        return 1
    fi

    command -v mpvpaper >/dev/null 2>&1 || {
        notify-send -u critical -a "Wallpaper de Vídeo" "mpvpaper não está instalado"
        return 1
    }

    # Interrompe qualquer vídeo anterior rodando neste monitor
    stop_video "$mon"

    # Inicia o mpvpaper no monitor especificado (camada background com auto-pause)
    mpvpaper -p -l background -o "$MPV_OPTS" "$mon" "$path" >/dev/null 2>&1 &
    local new_pid=$!
    echo "$new_pid" > "$(pid_file_for "$mon")"
    echo "$name" > "$(state_file_for "$mon")"

    notify-send -a "Wallpaper de Vídeo" -i video-x-generic \
        "Vídeo definido ($mon)" "$name"
}

restore() {
    while read -r mon; do
        [ -z "$mon" ] && continue
        local sfile; sfile="$(state_file_for "$mon")"
        if [ -f "$sfile" ]; then
            local vid; vid="$(cat "$sfile")"
            if [ -n "$vid" ] && [ "$vid" != "off" ] && [ -f "$VIDEO_DIR/$vid" ]; then
                set_video "$mon" "$vid"
            fi
        fi
    done < <(all_monitors)
}

preview() {
    local name="$1"
    local path="$VIDEO_DIR/$name"
    [ -f "$path" ] || return 1
    command -v mpvpaper >/dev/null 2>&1 || return 1
    pidof hyprlock >/dev/null && return 1

    local mon; mon="$(get_focused_monitor)"
    mpvpaper -l overlay -o "$MPV_OPTS" "$mon" "$path" >/dev/null 2>&1 &
    local pid=$!
    notify-send -a "Wallpaper de Vídeo" "Prévia · ${PREVIEW_SECS}s ($mon)" "$name"
    sleep "$PREVIEW_SECS"
    kill "$pid" 2>/dev/null || true
    pkill -f "mpvpaper -l overlay" 2>/dev/null || true
}

# Mesmo tema Catppuccin Mocha do lançador (SUPER + R). Os caminhos são
# explícitos porque o Hyprland pode subir sem XDG_CONFIG_HOME definido.
wofi_menu() {
    wofi --dmenu --insensitive --width 520 --height 400 --prompt "$1" \
        --conf "$HOME/.config/wofi/config" \
        --style "$HOME/.config/wofi/style.css"
}

menu() {
    mapfile -t videos < <(list_videos)
    if [ "${#videos[@]}" -eq 0 ]; then
        notify-send -u critical -a "Wallpaper de Vídeo" "Nenhum vídeo em $VIDEO_DIR"
        return 1
    fi

    local mon; mon="$(get_focused_monitor)"
    local cur choice name entries

    while true; do
        cur="$(current_video "$mon")"

        entries=()
        for name in "${videos[@]}"; do
            [ "$name" = "$cur" ] && entries+=("● $name") || entries+=("  $name")
        done
        [ "$cur" = "off" ] && entries+=("● $OFF_LABEL") || entries+=("  $OFF_LABEL")
        entries+=("  $PREVIEW_LABEL")

        choice="$(printf '%s\n' "${entries[@]}" | wofi_menu "Vídeo Wallpaper [$mon]")" || break
        [ -z "$choice" ] && break

        choice="${choice#● }"
        choice="${choice#  }"
        case "$choice" in
            "$OFF_LABEL")
                stop_video "$mon"
                notify-send -a "Wallpaper" "Vídeo desativado em $mon" "Restaurando wallpaper estático."
                break
                ;;
            "$PREVIEW_LABEL")
                name="$(printf '%s\n' "${videos[@]}" | wofi_menu "Pré-visualizar [$mon]")" || continue
                [ -n "$name" ] && preview "$name"
                ;;
            *)
                set_video "$mon" "$choice"
                break
                ;;
        esac
    done
}

case "${1:-menu}" in
    menu)     menu ;;
    set)      set_video "${2:?falta o monitor}" "${3:?falta o vídeo}" ;;
    stop)     stop_video "${2:-$(get_focused_monitor)}" ;;
    restore)  restore ;;
    current)  current_video "${2:-$(get_focused_monitor)}" ;;
    list)     list_videos ;;
    preview)  preview "${2:?falta o vídeo}" ;;
    *)
        echo "Uso: $0 <menu|set <monitor> <video>|stop [monitor|all]|restore|current [monitor]|list|preview <video>>" >&2
        exit 1
        ;;
esac
