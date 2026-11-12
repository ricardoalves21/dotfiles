#!/bin/bash
# Executado pelo hyprquickpaper ao selecionar um wallpaper.
# $1 = caminho absoluto da imagem escolhida.

set -u

# O quickshell é lançado pela keybind do Hyprland, que não tem ~/.local/bin no
# PATH (o display manager não lê ~/.profile). Sem isto o `command -v awww`
# falha e cai no hyprpaper, sem transição. Mesmo motivo do export em
# scripts/wallpaper.sh e scripts/lock.sh.
export PATH="$HOME/.local/bin:$PATH"

# Monitor alvo: o que estava em foco quando o seletor foi aberto.
# HQP_MONITOR vem da keybind no hyprland.conf; sem ela, usa o monitor
# focado agora. Nome vazio faria o hyprpaper aplicar em todos.
MONITOR="${HQP_MONITOR:-}"
[ -n "$MONITOR" ] || MONITOR="$(hyprctl activeworkspace -j | jq -r .monitor)"

# Se houver um wallpaper de vídeo rodando neste monitor, encerra para a imagem aparecer
"$HOME/.config/hypr/scripts/videowallpaper.sh" stop "$MONITOR" >/dev/null 2>&1 || true

# Backend: awww (transição animada), com hyprpaper como fallback.
# O awww é cliente puro — sem o daemon no ar o `img` falha, então checamos.
if command -v awww >/dev/null 2>&1 && awww query >/dev/null 2>&1; then
    awww img -o "$MONITOR" "$1" \
        --resize crop \
        --transition-type "${TRANSITION:-random}" \
        --transition-fps 60 \
        --transition-duration 1.2 \
        --transition-pos 0.9,0.9
else
    # hyprpaper: a partir do 0.8 / Hyprland 0.53 o IPC virou protocolo wire e
    # "preload" não existe mais — o próprio "wallpaper" carrega a imagem.
    # Modos de fit aceitos: cover (padrão), contain, fit/stretch, tile.
    hyprctl hyprpaper wallpaper "$MONITOR,$1,cover"
fi

# Mantém o estado do ~/.config/hypr/scripts/wallpaper.sh em sincronia,
# para o restore no boot e o módulo da waybar refletirem a escolha.
WALLPAPER_DIR="$HOME/Imagens/Wallpapers"
STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/wallpaper-index"

i=0
while IFS= read -r f; do
    if [ "$f" = "$1" ]; then
        echo "$i" > "$STATE_FILE"
        pkill -RTMIN+8 waybar 2>/dev/null
        break
    fi
    i=$((i + 1))
done < <(find -L "$WALLPAPER_DIR" -maxdepth 1 -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
       -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.gif' \) | sort)
