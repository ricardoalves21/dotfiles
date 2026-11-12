#!/usr/bin/env bash
# Alternador de wallpapers para Hyprland.
# Backend: awww (padrão, com transição animada) ou hyprpaper (fallback sem
# animação). Detectado automaticamente.
#
# Uso: wallpaper.sh <next|prev|random|restore|current|json>
set -euo pipefail

# O Hyprland pode ser iniciado por um display manager que não lê ~/.profile,
# então ~/.local/bin (onde o awww foi instalado) falta no PATH de tudo que ele
# lança — keybinds, waybar e exec-once. Sem isto o `command -v awww` falha e o
# script cai no hyprpaper, que não tem transição nenhuma. Mesmo motivo do
# export em scripts/lock.sh.
export PATH="$HOME/.local/bin:$PATH"

WALLPAPER_DIR="${WALLPAPER_DIR:-$HOME/Imagens/Wallpapers}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
STATE_FILE="$STATE_DIR/wallpaper-index"
FIT_MODE="${FIT_MODE:-cover}"
# 1 = cada monitor mostra um wallpaper diferente; 0 = todos com o mesmo
MONITOR_OFFSET=0
WAYBAR_SIGNAL=8

# ---------- animação (só com awww) ----------
# Tipos: none simple fade left right top bottom center outer any random wipe
# wave grow. 'random' sorteia um efeito diferente a cada troca.
TRANSITION="${TRANSITION:-random}"
TRANSITION_DURATION="${TRANSITION_DURATION:-1.2}"
TRANSITION_FPS="${TRANSITION_FPS:-60}"
# Origem dos efeitos radiais (grow/outer/center), em fração da tela.
# Só vale se TRANSITION for fixado num desses tipos: o 'random' sorteia a
# própria posição (e o ângulo e a onda) e ignora este valor.
TRANSITION_POS="${TRANSITION_POS:-0.9,0.9}"

mkdir -p "$STATE_DIR"

# ---------- lista de wallpapers ----------
mapfile -t WALLS < <(
    find -L "$WALLPAPER_DIR" -maxdepth 1 -type f \
        \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
           -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.gif' \) | sort
)
COUNT=${#WALLS[@]}

if [ "$COUNT" -eq 0 ]; then
    notify-send -u critical "Wallpaper" "Nenhuma imagem em $WALLPAPER_DIR"
    exit 1
fi

# ---------- índice atual ----------
IDX=0
[ -f "$STATE_FILE" ] && IDX="$(cat "$STATE_FILE")"
[[ "$IDX" =~ ^[0-9]+$ ]] || IDX=0
IDX=$(( IDX % COUNT ))

# ---------- backend ----------
# swww foi renomeado para awww; aceita os dois nomes
AWWW=""
for c in awww swww; do
    if command -v "$c" >/dev/null 2>&1; then AWWW="$c"; break; fi
done

# O awww é cliente puro: sem o daemon no ar todo `img` falha. Subir aqui cobre
# o boot (antes do exec-once ter terminado) e o daemon morto no meio da sessão.
ensure_daemon() {
    "$AWWW" query >/dev/null 2>&1 && return 0
    command -v "${AWWW}-daemon" >/dev/null 2>&1 || return 1
    setsid "${AWWW}-daemon" >/dev/null 2>&1 &
    local i
    for i in $(seq 1 40); do
        "$AWWW" query >/dev/null 2>&1 && return 0
        sleep 0.25
    done
    return 1
}

# hyprpaper e awww nomeiam os modos de encaixe diferente
resize_mode() {
    case "$FIT_MODE" in
        contain)      echo fit ;;
        fit|stretch)  echo stretch ;;
        tile|cover|*) echo crop ;;
    esac
}

apply() {
    local mon="$1" file="$2"
    if [ -n "$AWWW" ]; then
        # Sem 2>/dev/null: falha de wallpaper que não avisa é pior que a falha
        if ! "$AWWW" img -o "$mon" "$file" \
                --resize "$(resize_mode)" \
                --transition-type "$TRANSITION" \
                --transition-fps "$TRANSITION_FPS" \
                --transition-duration "$TRANSITION_DURATION" \
                --transition-pos "$TRANSITION_POS"; then
            notify-send -u critical "Wallpaper" "$AWWW falhou em $mon"
            return 1
        fi
    else
        hyprctl hyprpaper wallpaper "$mon,$file,$FIT_MODE" >/dev/null
    fi
}

monitors() {
    hyprctl monitors -j | jq -r '.[].name' | sort
}

# ---------- aplica em todos os monitores ----------
set_all() {
    local base="$1" i=0
    if [ -n "$AWWW" ] && ! ensure_daemon; then
        notify-send -u critical "Wallpaper" "${AWWW}-daemon não subiu"
        exit 1
    fi
    while read -r mon; do
        local pick=$(( (base + i * MONITOR_OFFSET) % COUNT ))
        apply "$mon" "${WALLS[$pick]}"
        i=$(( i + 1 ))
    done < <(monitors)
    echo "$base" > "$STATE_FILE"
    pkill -RTMIN+$WAYBAR_SIGNAL waybar 2>/dev/null || true
}

# ---------- ações ----------
case "${1:-next}" in
    next|prev|random)
        "$HOME/.config/hypr/scripts/videowallpaper.sh" stop all >/dev/null 2>&1 || true
        ;&
    next)    set_all $(( (IDX + 1) % COUNT )) ;;
    prev)    set_all $(( (IDX - 1 + COUNT) % COUNT )) ;;
    random)  set_all $(( RANDOM % COUNT )) ;;
    restore) set_all "$IDX"; exit 0 ;;   # no boot: sem notificação
    current) basename "${WALLS[$IDX]}"; exit 0 ;;
    json)
        # saída para o módulo custom da waybar
        name="$(basename "${WALLS[$IDX]}")"
        printf '{"text":"󰸉","tooltip":"%s  (%d/%d)\\nClique: próximo · Direito: anterior · Meio: aleatório","class":"wallpaper"}\n' \
            "${name//\"/}" "$((IDX + 1))" "$COUNT"
        exit 0
        ;;
    *) echo "Uso: $0 <next|prev|random|restore|current|json>" >&2; exit 1 ;;
esac

NEW_IDX="$(cat "$STATE_FILE")"
notify-send -a "Wallpaper" -i "${WALLS[$NEW_IDX]}" \
    "Wallpaper $((NEW_IDX + 1))/$COUNT" "$(basename "${WALLS[$NEW_IDX]}")" 2>/dev/null || true
