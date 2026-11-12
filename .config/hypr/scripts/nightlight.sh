#!/usr/bin/env bash
# Filtro de luz azul para Hyprland. Backend: wlsunset.
#
# O wlsunset foi feito para seguir o ciclo solar, mas aqui ele é usado em
# temperatura fixa: passamos -T e -t quase iguais, então o horário do dia deixa
# de importar e o filtro fica constante enquanto o daemon estiver no ar. O
# liga/desliga é o ciclo de vida do próprio processo.
#
# Uso: nightlight.sh <toggle|on|off|warmer|cooler|status|json>
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
TEMP_FILE="$STATE_DIR/nightlight-temp"
LOCK_FILE="$STATE_DIR/nightlight.lock"
WAYBAR_SIGNAL=9

TEMP_DEFAULT=4000
TEMP_MIN=2500
TEMP_MAX=6500
TEMP_STEP=250

mkdir -p "$STATE_DIR"

if ! command -v wlsunset >/dev/null 2>&1; then
    notify-send -u critical "Luz noturna" "wlsunset não está instalado"
    exit 1
fi

# O waybar chama este script de novo a cada tick de scroll: vários processos
# rodando ao mesmo tempo. Sem essa trava, cada um manda `stop` (SIGTERM, não
# espera morrer) e já sobe um `wlsunset` novo — por um instante ficam DOIS
# processos vivos disputando o controle de gama da mesma saída (o protocolo
# wlr-gamma-control só permite um cliente por saída). O perdedor recebe
# "gamma control failed" e nunca mais consegue ajustar nada, mas continua
# "vivo" pro pgrep — e é aí que o botão para de responder mesmo clicando.
# A trava serializa as chamadas, então nunca existem dois wlsunset disputando.
exec 9>"$LOCK_FILE"
flock 9

read_temp() {
    local t=$TEMP_DEFAULT
    [ -f "$TEMP_FILE" ] && t="$(cat "$TEMP_FILE")"
    [[ "$t" =~ ^[0-9]+$ ]] || t=$TEMP_DEFAULT
    (( t < TEMP_MIN )) && t=$TEMP_MIN
    (( t > TEMP_MAX )) && t=$TEMP_MAX
    echo "$t"
}

is_on() { pgrep -x wlsunset >/dev/null 2>&1; }

refresh_waybar() { pkill -RTMIN+$WAYBAR_SIGNAL waybar 2>/dev/null || true; }

stop() {
    pkill -x wlsunset 2>/dev/null || true
    # pkill só manda o sinal; espera o processo morrer de verdade antes de
    # devolver, senão quem chama start() logo depois sobe o wlsunset novo
    # antes do antigo soltar o controle de gama (ver comentário da trava).
    for _ in $(seq 1 20); do
        is_on || return 0
        sleep 0.05
    done
}

# -t precisa ser estritamente menor que -T, daí o -1: a diferença de 1 K é
# imperceptível e neutraliza a variação por horário.
start() {
    local temp="$1"
    stop
    # 9>&- fecha o fd da trava no filho: sem isso o wlsunset (que fica
    # rodando muito além do fim deste script) herdaria o fd e seguraria o
    # lock para sempre, travando toda chamada futura ao nightlight.sh.
    setsid wlsunset -T "$temp" -t $(( temp - 1 )) 9>&- >/dev/null 2>&1 &
    echo "$temp" > "$TEMP_FILE"
}

# Reaplica só se já estiver ligado — mexer na temperatura não deve acender o
# filtro sozinho.
retune() {
    local temp="$1"
    echo "$temp" > "$TEMP_FILE"
    is_on && start "$temp"
}

case "${1:-toggle}" in
    toggle)
        if is_on; then stop; else start "$(read_temp)"; fi
        ;;
    on)
        is_on || start "$(read_temp)"
        ;;
    off)
        stop
        ;;
    warmer)
        t=$(( $(read_temp) - TEMP_STEP ))
        (( t < TEMP_MIN )) && t=$TEMP_MIN
        retune "$t"
        ;;
    cooler)
        t=$(( $(read_temp) + TEMP_STEP ))
        (( t > TEMP_MAX )) && t=$TEMP_MAX
        retune "$t"
        ;;
    status)
        is_on && echo "on $(read_temp)K" || echo "off"
        exit 0
        ;;
    json)
        temp="$(read_temp)"
        if is_on; then
            printf '{"text":"󰖔","tooltip":"Luz noturna ligada · %dK\\nClique: desligar · Scroll: ajustar temperatura","class":"active","alt":"on"}\n' "$temp"
        else
            printf '{"text":"󰖔","tooltip":"Luz noturna desligada\\nClique: ligar (%dK) · Scroll: ajustar temperatura","class":"inactive","alt":"off"}\n' "$temp"
        fi
        exit 0
        ;;
    *)
        echo "Uso: $0 <toggle|on|off|warmer|cooler|status|json>" >&2
        exit 1
        ;;
esac

refresh_waybar
