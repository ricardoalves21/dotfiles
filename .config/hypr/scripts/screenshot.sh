#!/usr/bin/env bash
# Screenshot helper para Hyprland (grim + slurp + wl-clipboard)
# Uso: screenshot.sh <region|screen|window|all> [--copy-only]
set -euo pipefail

MODE="${1:-region}"
COPY_ONLY="${2:-}"

DIR="${XDG_PICTURES_DIR:-$HOME/Imagens}/Screenshots"
mkdir -p "$DIR"
FILE="$DIR/$(date +%Y-%m-%d_%H-%M-%S)_${MODE}.png"

# Log de diagnóstico
echo "[$(date '+%Y-%m-%d %H:%M:%S')] screenshot.sh iniciado (MODE=${MODE}, COPY_ONLY=${COPY_ONLY})" >> /tmp/screenshot.log 2>&1 || true

for dep in grim wl-copy; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        notify-send -u critical "Screenshot" "Faltando: $dep\nInstale com: sudo apt install grim slurp wl-clipboard"
        exit 1
    fi
done

# Cor da seleção combinando com o tema matrix
SLURP_ARGS=(-d -b 04100Caa -c 00ff9cff -s 00ff9c11 -w 2)

case "$MODE" in
    region)
        command -v slurp >/dev/null 2>&1 || { notify-send -u critical "Screenshot" "Faltando: slurp"; exit 1; }
        # Pequeno delay para garantir liberação dos modificadores (Ctrl/Alt) antes do grab do slurp
        sleep 0.1
        GEOM="$(slurp "${SLURP_ARGS[@]}" 2>>/tmp/screenshot.log)" || {
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Seleção cancelada (ESC ou clique fora)" >> /tmp/screenshot.log 2>&1 || true
            exit 0
        }
        [ -z "$GEOM" ] && exit 0
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Região selecionada: $GEOM" >> /tmp/screenshot.log 2>&1 || true
        # Aguarda o compositor limpar o overlay do slurp antes da captura
        sleep 0.05
        grim -g "$GEOM" "$FILE"
        ;;
    screen)
        MON="$(hyprctl activeworkspace -j | jq -r '.monitor')"
        grim -o "$MON" "$FILE"
        ;;
    window)
        GEOM="$(hyprctl activewindow -j | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')"
        [ "$GEOM" = "null,null nullxnull" ] && { notify-send "Screenshot" "Nenhuma janela ativa"; exit 0; }
        grim -g "$GEOM" "$FILE"
        ;;
    all)
        grim "$FILE"
        ;;
    *)
        echo "Uso: $0 <region|screen|window|all> [--copy-only]" >&2
        exit 1
        ;;
esac

wl-copy < "$FILE"

if [ "$COPY_ONLY" = "--copy-only" ]; then
    rm -f "$FILE"
    notify-send -a "Screenshot" -i camera-photo "Screenshot copiado" "Apenas na área de transferência"
    exit 0
fi

notify-send -a "Screenshot" -i "$FILE" "Screenshot salvo" "$(basename "$FILE")\nCopiado para a área de transferência"
