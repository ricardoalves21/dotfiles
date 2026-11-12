#!/usr/bin/env bash
# ==============================================================================
# Script: window-switcher.sh
# Descrição: Menu visual interativo (Wofi) para alternar entre janelas abertas
#            exibindo o Workspace, Aplicativo e Título exato da janela.
# ==============================================================================
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

# Pega informações das janelas abertas via hyprctl
raw_clients="$(hyprctl clients -j 2>/dev/null | jq -r '.[] | select(.mapped == true and .hidden == false) | "\(.address)|\(.workspace.name)|\(.class)|\(.title)"')"

if [ -z "$raw_clients" ]; then
    exit 0
fi

CURRENT_WS="$(hyprctl activeworkspace -j 2>/dev/null | jq -r .name // empty)"

entries=()
while IFS='|' read -r addr ws cls title; do
    [ -z "$addr" ] && continue
    # Se a janela for do workspace atual, marca com destaque
    if [ "$ws" = "$CURRENT_WS" ]; then
        prefix="● [Espaço $ws]"
    else
        prefix="  [Espaço $ws]"
    fi
    # Formato: Prefixo | Ícone/Classe: Título da Janela (Endereço oculto)
    entries+=("$prefix $cls: $title  ──  #$addr")
done <<< "$raw_clients"

WOFI_ARGS=(
    --dmenu
    --insensitive
    --width 720
    --height 400
    --prompt "Alternar para Janela"
)
[ -f "$HOME/.config/wofi/config" ] && WOFI_ARGS+=(--conf "$HOME/.config/wofi/config")
[ -f "$HOME/.config/wofi/style.css" ] && WOFI_ARGS+=(--style "$HOME/.config/wofi/style.css")

set +e
chosen="$(printf '%s\n' "${entries[@]}" | wofi "${WOFI_ARGS[@]}")"
rc=$?
set -e

[ "$rc" -eq 0 ] && [ -n "$chosen" ] || exit 0

# Extrai o endereço hexadecimal da janela
addr="${chosen##*#}"

if [ -n "$addr" ]; then
    hyprctl dispatch focuswindow "address:$addr"
fi
