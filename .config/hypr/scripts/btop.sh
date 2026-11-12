#!/usr/bin/env bash
# Abre o btop no primeiro workspace vazio do monitor.
# Se já houver um btop aberto, apenas foca a janela existente.
#
# Uso: btop.sh [MONITOR]   (sem argumento, usa o monitor focado)
set -euo pipefail

CLASS="btop"
LAUNCH=(kitty --class "$CLASS" -e btop)

MON="${1:-$(hyprctl activeworkspace -j | jq -r .monitor)}"

# ---------- já está aberto? só foca ----------
ADDR="$(hyprctl clients -j | jq -r --arg c "$CLASS" \
    'first(.[] | select(.class == $c) | .address) // empty')"

if [ -n "$ADDR" ]; then
    hyprctl dispatch focuswindow "address:$ADDR" >/dev/null
    exit 0
fi

# ---------- primeiro workspace vazio do monitor ----------
# Os ids de cada monitor saem das workspace rules do hyprland.conf,
# então isto acompanha automaticamente mudanças na divisão 1-5 / 6-10.
CANDIDATOS="$(hyprctl workspacerules -j \
    | jq -r --arg m "$MON" '.[] | select(.monitor == $m) | .workspaceString' \
    | grep -E '^[0-9]+$' | sort -n)"

OCUPADOS="$(hyprctl workspaces -j | jq -r '.[] | select(.windows > 0) | .id')"

WS=""
for id in $CANDIDATOS; do
    if ! grep -qx "$id" <<< "$OCUPADOS"; then
        WS="$id"
        break
    fi
done

# Nenhum vazio (ou monitor sem regras): usa o workspace atual mesmo.
[ -n "$WS" ] || WS="$(hyprctl activeworkspace -j | jq -r .id)"

hyprctl dispatch focusmonitor "$MON" >/dev/null
hyprctl dispatch workspace "$WS" >/dev/null
exec "${LAUNCH[@]}"
