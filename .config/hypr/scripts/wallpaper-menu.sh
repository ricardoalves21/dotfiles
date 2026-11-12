#!/usr/bin/env bash
# ==============================================================================
# Script: wallpaper-menu.sh
# Descrição: Seletor de papéis de parede para o monitor em foco.
#            Usa o quickshell (hyprquickpaper) se instalado; caso contrário,
#            abre um menu visual elegante via Wofi (tema Catppuccin Mocha).
# ==============================================================================
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

MONITOR="$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.monitor // ""' 2>/dev/null || true)"
[ -n "$MONITOR" ] || MONITOR="DP-1"
export HQP_MONITOR="$MONITOR"

# Se o quickshell estiver disponível no sistema, usa a interface QML
if command -v quickshell >/dev/null 2>&1; then
    exec quickshell -c hyprquickpaper
fi

# Fallback: Menu interativo via Wofi
WALL_DIR="$HOME/Imagens/Wallpapers"
mkdir -p "$WALL_DIR"

mapfile -t files < <(
    find -L "$WALL_DIR" -maxdepth 1 -type f \
        \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
           -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.gif' \) \
        -printf "%f\n" | sort
)

if [ "${#files[@]}" -eq 0 ]; then
    notify-send -u critical "Wallpapers" "Nenhuma imagem em ~/Imagens/Wallpapers" 2>/dev/null || true
    exit 1
fi

entries=()
entries+=("🎲 Sorteio Aleatório")
entries+=("📁 Abrir Pasta Wallpapers")
for f in "${files[@]}"; do
    entries+=("󰸉  $f")
done

WOFI_ARGS=(
    --dmenu
    --insensitive
    --width 580
    --height 440
    --prompt "Wallpaper [$MONITOR]"
)
[ -f "$HOME/.config/wofi/config" ] && WOFI_ARGS+=(--conf "$HOME/.config/wofi/config")
[ -f "$HOME/.config/wofi/style.css" ] && WOFI_ARGS+=(--style "$HOME/.config/wofi/style.css")

set +e
chosen="$(printf '%s\n' "${entries[@]}" | wofi "${WOFI_ARGS[@]}")"
rc=$?
set -e

[ "$rc" -eq 0 ] && [ -n "$chosen" ] || exit 0

case "$chosen" in
    "🎲 Sorteio Aleatório")
        exec "$HOME/.config/hypr/scripts/wallpaper.sh" random
        ;;
    "📁 Abrir Pasta Wallpapers")
        exec nautilus "$WALL_DIR"
        ;;
    *)
        filename="${chosen#󰸉  }"
        filepath="$WALL_DIR/$filename"
        if [ -f "$filepath" ]; then
            exec "$HOME/.config/quickshell/hyprquickpaper/commands.sh" "$filepath"
        fi
        ;;
esac
