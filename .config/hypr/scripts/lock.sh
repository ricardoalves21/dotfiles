#!/usr/bin/env bash
# Bloqueia a sessão com o digital rain rodando atrás do hyprlock.
#
# Como funciona:
#   1. mpvpaper desenha o vídeo na camada `overlay`
#   2. misc:session_lock_xray deixa a superfície de bloqueio ver através
#   3. hyprlock roda com background alpha 0, então o vídeo aparece
#
# SEGURANÇA: o xray é ligado SÓ enquanto o vídeo está confirmado na tela,
# e desligado no fim. Se o vídeo não subir, bloqueamos com fundo opaco em
# vez de arriscar uma tela de bloqueio transparente mostrando o desktop.
set -uo pipefail

# O Hyprland pode ser iniciado por um display manager que não lê ~/.profile,
# então ~/.local/bin (onde o mpvpaper foi instalado) pode faltar no PATH.
export PATH="$HOME/.local/bin:$PATH"

SCRIPTS="$HOME/.config/hypr/scripts"
# Qual vídeo tocar é decisão do lockvideo.sh (menu em SUPER + I). Ele sai 1
# quando o vídeo está desligado ou a pasta está vazia, e aí caímos no fundo
# opaco. MATRIX_VIDEO ainda sobrescreve tudo, para teste pontual.
VIDEO="${MATRIX_VIDEO:-$("$SCRIPTS/lockvideo.sh" path 2>/dev/null)}"
CONFIG="$HOME/.config/hypr/hyprlock.conf"
FALLBACK="${XDG_RUNTIME_DIR:-/tmp}/hyprlock-solid.conf"
MPV_OPTS="--no-audio --loop-file=inf --really-quiet --no-osc --panscan=1.0 --hwdec=auto"

# Já bloqueado? Não empilhar.
pidof hyprlock >/dev/null && exit 0

LOCK_PID=""

xray_off() { hyprctl keyword misc:session_lock_xray false >/dev/null 2>&1; }
kill_paper() {
    [ -n "$LOCK_PID" ] && kill "$LOCK_PID" >/dev/null 2>&1 || true
    pkill -f "mpvpaper -l overlay" >/dev/null 2>&1 || true
}

cleanup() {
    xray_off
    kill_paper
}
trap cleanup EXIT INT TERM

# Gera a config de emergência: mesmo visual, mas com fundo opaco.
make_fallback() {
    python3 - "$CONFIG" "$FALLBACK" <<'PY'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
solid = """background {
    monitor =
    path = screenshot
    blur_passes = 4
    blur_size = 7
    noise = 0.012
    contrast = 0.90
    brightness = 0.60
    vibrancy = 0.25
    vibrancy_darkness = 0.15
}"""
out = re.sub(r"# @BG_START.*?# @BG_END", solid, text, flags=re.S)
open(dst, "w", encoding="utf-8").write(out)
PY
}

# O vídeo está mesmo desenhado?
video_is_up() {
    [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" >/dev/null 2>&1
}

start_video() {
    command -v mpvpaper >/dev/null 2>&1 || return 1
    [ -f "$VIDEO" ] || return 1

    mpvpaper -l overlay -o "$MPV_OPTS" ALL "$VIDEO" >/dev/null 2>&1 &
    LOCK_PID=$!

    # Espera até 3s pela camada aparecer
    for _ in $(seq 1 30); do
        video_is_up && return 0
        sleep 0.1
    done
    return 1
}

if start_video; then
    hyprctl keyword misc:session_lock_xray true >/dev/null
    hyprlock
else
    # Sem vídeo: NÃO ligar xray. Bloqueia com screenshot desfocado.
    kill_paper
    xray_off
    make_fallback
    # Vídeo desligado no menu é escolha do usuário: bloqueia calado. O aviso é
    # só para quando o vídeo deveria estar lá e não subiu.
    if [ "$("$SCRIPTS/lockvideo.sh" current 2>/dev/null)" != off ]; then
        notify-send -a "Lock" "Vídeo de fundo indisponível" \
            "Bloqueando com fundo opaco. Confira o menu em SUPER + I." 2>/dev/null
    fi
    hyprlock -c "$FALLBACK"
fi
