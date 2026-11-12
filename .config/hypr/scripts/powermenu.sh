#!/usr/bin/env bash
# Power Menu com Rofi e Catppuccin Mocha para Hyprland
#
# Uso: powermenu.sh [menu|toggle|json|shutdown|reboot|suspend|hibernate|lock|logout]
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
PID_FILE="$STATE_DIR/powermenu.pid"
LOCK_SCRIPT="$HOME/.config/hypr/scripts/lock.sh"
THEME="$HOME/.config/rofi/powermenu.rasi"

mkdir -p "$STATE_DIR"

# Opções do menu com ícones Nerd Fonts
SHUTDOWN="󰐥  Desligar"
REBOOT="󰜉  Reiniciar"
SUSPEND="󰤄  Suspender"
HIBERNATE="󰒲  Hibernar"
LOCK="󰌾  Bloquear tela"
LOGOUT="󰍃  Sair da sessão"

is_menu_open() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid="$(cat "$PID_FILE" 2>/dev/null || true)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
        rm -f "$PID_FILE"
    fi
    return 1
}

close_menu() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid="$(cat "$PID_FILE" 2>/dev/null || true)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
        rm -f "$PID_FILE"
    fi
}

lock_before_sleep() {
    if [ -x "$LOCK_SCRIPT" ]; then
        "$LOCK_SCRIPT" &
        # Aguarda o hyprlock travar a sessão antes de suspender/hibernar
        for _ in $(seq 1 25); do
            pidof hyprlock >/dev/null 2>&1 && break
            sleep 0.1
        done
        sleep 0.15
    elif command -v hyprlock >/dev/null 2>&1; then
        hyprlock &
        sleep 0.4
    fi
}

can_hibernate() {
    grep -qw disk /sys/power/state 2>/dev/null && \
        ! grep -Fq "[disabled]" /sys/power/disk 2>/dev/null
}

confirm_action() {
    local label="$1"
    local question="$2"
    local yes="󰄬  Sim, ${label,,}"
    local no="󰅖  Cancelar"
    local ans=""
    if command -v rofi >/dev/null 2>&1; then
        ans="$(
            printf '%s\n%s\n' "$yes" "$no" | {
                exec 3<&0
                rofi -dmenu -i -theme "$THEME" -p "󰐥  Confirmar" -mesg "$question" <&3 3<&- &
                rpid=$!
                exec 3<&-
                echo "$rpid" > "$PID_FILE"
                wait "$rpid"
            }
        )" || { rm -f "$PID_FILE"; return 1; }
    else
        ans="$(printf '%s\n%s\n' "$yes" "$no" | wofi --dmenu -p "$label: $question")" || { rm -f "$PID_FILE"; return 1; }
    fi
    rm -f "$PID_FILE"
    [ "$ans" = "$yes" ]
}

do_lock() {
    if [ -x "$LOCK_SCRIPT" ]; then
        "$LOCK_SCRIPT"
    else
        hyprlock
    fi
}

do_suspend() {
    lock_before_sleep
    systemctl suspend
}

do_hibernate() {
    if can_hibernate; then
        lock_before_sleep
        systemctl hibernate
    else
        local opt_susp="󰤄  Suspender no lugar"
        local opt_cancel="󰅖  Cancelar"
        local ans=""
        ans="$(printf '%s\n%s\n' "$opt_susp" "$opt_cancel" | rofi -dmenu -i -theme "$THEME" -p "󰒲  Hibernar" \
            -mesg "A hibernação está <b>desativada no kernel</b> (<tt>/sys/power/disk = disabled</tt>, comum com Secure Boot ativo ou swap sem <tt>resume=</tt>).")" || exit 0
        if [ "$ans" = "$opt_susp" ]; then
            do_suspend
        fi
    fi
}

do_reboot() {
    systemctl reboot
}

do_shutdown() {
    systemctl poweroff
}

do_logout() {
    if command -v hyprshutdown >/dev/null 2>&1; then
        hyprshutdown
    else
        hyprctl dispatch exit
    fi
}

run_menu() {
    if is_menu_open; then
        close_menu
    fi

    local chosen=""
    set +e
    if command -v rofi >/dev/null 2>&1; then
        chosen="$(
            printf '%s\n' "$SHUTDOWN" "$REBOOT" "$SUSPEND" "$HIBERNATE" "$LOCK" "$LOGOUT" | {
                exec 3<&0
                rofi -dmenu -i -theme "$THEME" -p "󰐥  Energia" <&3 3<&- &
                rpid=$!
                exec 3<&-
                echo "$rpid" > "$PID_FILE"
                wait "$rpid"
            }
        )"
    else
        chosen="$(printf '%s\n' "$SHUTDOWN" "$REBOOT" "$SUSPEND" "$HIBERNATE" "$LOCK" "$LOGOUT" | wofi --dmenu -p "Energia")"
    fi
    local rc=$?
    set -e
    rm -f "$PID_FILE"

    [ "$rc" -eq 0 ] && [ -n "$chosen" ] || exit 0

    case "$chosen" in
        "$SHUTDOWN")
            confirm_action "Desligar" "Deseja realmente <b>desligar</b> o computador?" && do_shutdown
            ;;
        "$REBOOT")
            confirm_action "Reiniciar" "Deseja realmente <b>reiniciar</b> o computador?" && do_reboot
            ;;
        "$SUSPEND")
            do_suspend
            ;;
        "$HIBERNATE")
            do_hibernate
            ;;
        "$LOCK")
            do_lock
            ;;
        "$LOGOUT")
            confirm_action "Sair da sessão" "Deseja realmente <b>encerrar a sessão</b> do Hyprland?" && do_logout
            ;;
    esac
}

case "${1:-menu}" in
    toggle)
        if is_menu_open; then
            close_menu
            exit 0
        fi
        run_menu
        ;;
    menu)
        run_menu
        ;;
    json)
        printf '{"text":"󰐥","tooltip":"Menu de Energia (SUPER + Esc)\\nDesligar · Reiniciar · Suspender · Hibernar · Bloquear","class":"power"}\n'
        ;;
    shutdown)  do_shutdown ;;
    reboot)    do_reboot ;;
    suspend)   do_suspend ;;
    hibernate) do_hibernate ;;
    lock)      do_lock ;;
    logout)    do_logout ;;
    *)
        echo "Uso: $0 [menu|toggle|json|shutdown|reboot|suspend|hibernate|lock|logout]" >&2
        exit 1
        ;;
esac
