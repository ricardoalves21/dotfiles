#!/usr/bin/env bash
# ==============================================================================
# Script: toggle-tablet-monitor.sh
# Descrição: Alterna o mapeamento da mesa digitalizadora (Wacom / Tablet)
#            entre os monitores ativos no Hyprland.
# Atalho: SUPER + X
# ==============================================================================
set -euo pipefail

# 1. Identificar o dispositivo de mesa / caneta
DEFAULT_TABLET="wacom-intuos-s-pen"
DETECTED_TABLET=$(hyprctl devices -j 2>/dev/null | jq -r '.tablets[] | select(.name != null and .name != "") | .name' 2>/dev/null | head -n 1 || true)
TABLET_NAME="${DETECTED_TABLET:-$DEFAULT_TABLET}"

if [ -z "$TABLET_NAME" ]; then
    notify-send -u critical -a "Mesa Digitalizadora" -i dialog-warning \
        "Nenhuma mesa detectada" "Não foi possível encontrar a mesa digitalizadora no Hyprland."
    exit 1
fi

# 2. Obter lista de monitores ativos
mapfile -t MONITORS < <(hyprctl monitors -j 2>/dev/null | jq -r '.[].name' | sort)
TOTAL_MONITORS="${#MONITORS[@]}"

if [ "$TOTAL_MONITORS" -eq 0 ]; then
    notify-send -u critical -a "Mesa Digitalizadora" -i dialog-warning \
        "Erro" "Nenhum monitor ativo encontrado no Hyprland."
    exit 1
fi

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/hypr_tablet_monitor"
TARGET_MON=""

# 3. Determinar o monitor de destino
if [ -n "${1:-}" ]; then
    # Busca por argumento específico (nome da porta ou modelo, ex: DP-1, HDMI-A-1, samsung, lg)
    REQ="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
    for mon in "${MONITORS[@]}"; do
        mon_lower="$(echo "$mon" | tr '[:upper:]' '[:lower:]')"
        mon_desc="$(hyprctl monitors -j 2>/dev/null | jq -r --arg name "$mon" '.[] | select(.name == $name) | (.model // .description // .name)' | tr '[:upper:]' '[:lower:]')"
        if [[ "$mon_lower" == *"$REQ"* ]] || [[ "$mon_desc" == *"$REQ"* ]]; then
            TARGET_MON="$mon"
            break
        fi
    done

    if [ -z "$TARGET_MON" ]; then
        notify-send -u critical -a "Mesa Digitalizadora" -i dialog-warning \
            "Monitor não encontrado" "Não foi possível encontrar monitor correspondente a '$1'."
        exit 1
    fi
else
    # Se há apenas 1 monitor, mapeia para ele diretamente
    if [ "$TOTAL_MONITORS" -eq 1 ]; then
        TARGET_MON="${MONITORS[0]}"
    else
        # Alternância cíclica
        CURRENT_MON=""
        if [ -f "$STATE_FILE" ]; then
            CURRENT_MON=$(cat "$STATE_FILE" 2>/dev/null || true)
        fi

        CURRENT_IDX=-1
        for i in "${!MONITORS[@]}"; do
            if [ "${MONITORS[$i]}" = "$CURRENT_MON" ]; then
                CURRENT_IDX="$i"
                break
            fi
        done

        # Se não há estado anterior válido gravado, usa HDMI-A-1 como referência inicial
        if [ "$CURRENT_IDX" -eq -1 ]; then
            for i in "${!MONITORS[@]}"; do
                if [ "${MONITORS[$i]}" = "HDMI-A-1" ]; then
                    CURRENT_IDX="$i"
                    break
                fi
            done
            [ "$CURRENT_IDX" -eq -1 ] && CURRENT_IDX=0
        fi

        NEXT_IDX=$(( (CURRENT_IDX + 1) % TOTAL_MONITORS ))
        TARGET_MON="${MONITORS[$NEXT_IDX]}"
    fi
fi

# 4. Aplicar novo mapeamento de saída no Hyprland
hyprctl keyword "device[${TABLET_NAME}]:output" "$TARGET_MON" >/dev/null

# 5. Salvar estado atual
echo "$TARGET_MON" > "$STATE_FILE"

# 6. Identificar nome amigável do monitor para notificação
MON_LABEL=$(hyprctl monitors -j 2>/dev/null | jq -r --arg name "$TARGET_MON" '.[] | select(.name == $name) | .model // .description // .name' 2>/dev/null || echo "$TARGET_MON")

# 7. Exibir notificação
notify-send -a "Mesa Digitalizadora" -i input-tablet \
    "Mesa Digitalizadora" \
    "Caneta mapeada para:\n<b>${MON_LABEL}</b> (${TARGET_MON})"
