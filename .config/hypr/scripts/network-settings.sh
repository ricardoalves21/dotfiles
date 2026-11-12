#!/usr/bin/env bash
# ==============================================================================
# Script: network-settings.sh
# Descrição: Abre a janela de configurações de Wi-Fi e Rede do Ubuntu
#            (gnome-control-center) ou foca na janela se já estiver aberta.
# ==============================================================================
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"
export XDG_CURRENT_DESKTOP=GNOME

MODE="${1:-auto}"

# Se o usuário requisitou especificamente o editor de conexões clássico
if [ "$MODE" = "editor" ]; then
    exec nm-connection-editor
fi

# Verifica se já há uma janela do gnome-control-center aberta
ADDR="$(hyprctl clients -j 2>/dev/null | jq -r 'first(.[] | select(.class == "gnome-control-center" or .class == "org.gnome.Settings") | .address) // empty')"

if [ -n "$ADDR" ] && [ "$MODE" = "auto" ]; then
    # Janela já aberta: traz para o foco
    hyprctl dispatch focuswindow "address:$ADDR" >/dev/null
    exit 0
fi

# Determina o painel padrão
PANEL="$MODE"
if [ "$MODE" = "auto" ]; then
    # Se houver interface Wi-Fi disponível, abre direto na aba wifi, senão network
    if nmcli dev 2>/dev/null | grep -q "wifi"; then
        PANEL="wifi"
    else
        PANEL="network"
    fi
fi

# Abre a janela de configurações do Ubuntu
exec gnome-control-center "$PANEL"
