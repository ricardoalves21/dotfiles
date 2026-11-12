#!/usr/bin/env bash
# Escolhe o vídeo que roda no fundo da tela de bloqueio (hyprlock).
#
# O lock.sh não tem mais caminho fixo: ele pergunta o vídeo atual para este
# script (`lockvideo.sh path`). A escolha vive num arquivo de estado, então
# sobrevive a reboot e não exige editar config nenhuma.
#
# Uso: lockvideo.sh <menu|path|current|list|set <arquivo>|preview <arquivo>|off>
set -uo pipefail

# O Hyprland pode ser iniciado por um display manager que não lê ~/.profile,
# então ~/.local/bin (onde o mpvpaper foi instalado) pode faltar no PATH.
# Mesmo motivo do export em scripts/lock.sh.
export PATH="$HOME/.local/bin:$PATH"

VIDEO_DIR="${LOCK_VIDEO_DIR:-$HOME/Vídeos/video_wallpaper}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
STATE_FILE="$STATE_DIR/lock-video"
# Preferido quando ainda não há escolha salva
DEFAULT_VIDEO="matrix-rain.mp4"
PREVIEW_SECS="${PREVIEW_SECS:-6}"
OFF_LABEL="Sem vídeo (fundo opaco)"
PREVIEW_LABEL="Prévia…"
MPV_OPTS="--no-audio --loop-file=inf --really-quiet --no-osc --panscan=1.0 --hwdec=auto"

mkdir -p "$STATE_DIR"

list_videos() {
    find -L "$VIDEO_DIR" -maxdepth 1 -type f \
        \( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.webm' \
           -o -iname '*.mov' -o -iname '*.avi' \) -printf '%f\n' 2>/dev/null | sort
}

read_state() { [ -f "$STATE_FILE" ] && cat "$STATE_FILE" || true; }

# Nome do vídeo em uso, "off" se desligado, vazio se não há vídeo nenhum.
# Um estado apontando para arquivo apagado não trava o lock: cai no padrão.
current_name() {
    local sel; sel="$(read_state)"
    [ "$sel" = "off" ] && { echo off; return 0; }
    [ -n "$sel" ] && [ -f "$VIDEO_DIR/$sel" ] && { echo "$sel"; return 0; }
    [ -f "$VIDEO_DIR/$DEFAULT_VIDEO" ] && { echo "$DEFAULT_VIDEO"; return 0; }
    list_videos | head -n1
}

# Caminho absoluto do vídeo atual. Sai 1 se não há vídeo a tocar — é esse
# código de saída que manda o lock.sh usar o fundo opaco.
resolve_path() {
    local name; name="$(current_name)"
    case "$name" in
        ""|off) return 1 ;;
    esac
    echo "$VIDEO_DIR/$name"
}

set_video() {
    local name="$1"
    [ -f "$VIDEO_DIR/$name" ] || {
        notify-send -u critical -a "Tela de bloqueio" "Vídeo não encontrado" "$name"
        return 1
    }
    echo "$name" > "$STATE_FILE"
    notify-send -a "Tela de bloqueio" "Vídeo de fundo definido" "$name"
}

set_off() {
    echo off > "$STATE_FILE"
    notify-send -a "Tela de bloqueio" "Vídeo desativado" \
        "O bloqueio vai usar o screenshot desfocado."
}

# Prévia ao vivo: mpvpaper na camada overlay, igual ao lock, por alguns
# segundos. Não roda com a tela bloqueada para não derrubar o vídeo do lock
# (o kill no fim é por nome de processo).
preview() {
    local name="$1"
    local path="$VIDEO_DIR/$name"
    [ -f "$path" ] || return 1
    command -v mpvpaper >/dev/null 2>&1 || {
        notify-send -u critical -a "Tela de bloqueio" "mpvpaper não está instalado"
        return 1
    }
    pidof hyprlock >/dev/null && return 1

    mpvpaper -l overlay -o "$MPV_OPTS" ALL "$path" >/dev/null 2>&1 &
    local pid=$!
    notify-send -a "Tela de bloqueio" "Prévia · ${PREVIEW_SECS}s" "$name"
    sleep "$PREVIEW_SECS"
    kill "$pid" >/dev/null 2>&1 || true
    pkill -f "mpvpaper -l overlay" >/dev/null 2>&1 || true
    return 0
}

# Mesmo tema Catppuccin Mocha do lançador (SUPER + R). Os caminhos são
# explícitos porque o Hyprland pode subir sem XDG_CONFIG_HOME definido.
wofi_menu() {
    wofi --dmenu --insensitive --width 520 --height 400 --prompt "$1" \
        --conf "$HOME/.config/wofi/config" \
        --style "$HOME/.config/wofi/style.css"
}

# O menu roda em loop: depois de uma prévia você volta para a lista em vez de
# ter que apertar SUPER + I de novo.
menu() {
    mapfile -t videos < <(list_videos)
    if [ "${#videos[@]}" -eq 0 ]; then
        notify-send -u critical -a "Tela de bloqueio" "Nenhum vídeo em $VIDEO_DIR"
        return 1
    fi

    local cur choice name entries
    while true; do
        cur="$(current_name)"

        # O "● " marca a opção em uso; as outras levam dois espaços para as
        # legendas ficarem alinhadas. O prefixo é removido depois da escolha.
        entries=()
        for name in "${videos[@]}"; do
            [ "$name" = "$cur" ] && entries+=("● $name") || entries+=("  $name")
        done
        [ "$cur" = off ] && entries+=("● $OFF_LABEL") || entries+=("  $OFF_LABEL")
        entries+=("  $PREVIEW_LABEL")

        choice="$(printf '%s\n' "${entries[@]}" | wofi_menu "Vídeo do bloqueio")" || break
        [ -z "$choice" ] && break

        choice="${choice#● }"
        choice="${choice#  }"
        case "$choice" in
            "$OFF_LABEL") set_off; break ;;
            "$PREVIEW_LABEL")
                name="$(printf '%s\n' "${videos[@]}" | wofi_menu "Pré-visualizar")" || continue
                [ -n "$name" ] && preview "$name"
                ;;
            *) set_video "$choice"; break ;;
        esac
    done
}

case "${1:-menu}" in
    menu)    menu ;;
    path)    resolve_path ;;
    current) current_name ;;
    list)    list_videos ;;
    set)     set_video "${2:?falta o nome do arquivo}" ;;
    preview) preview "${2:?falta o nome do arquivo}" ;;
    off)     set_off ;;
    *)
        echo "Uso: $0 <menu|path|current|list|set <arquivo>|preview <arquivo>|off>" >&2
        exit 1
        ;;
esac
