#!/usr/bin/env bash
# ==============================================================================
# Script: updates.sh
# Descrição: Monitora atualizações pendentes do Ubuntu (APT/segurança, Snap e
#            Flatpak) para a Waybar, envia notificações via swaync/notify-send
#            e abre o Atualizador de Programas do Ubuntu (update-manager) ou
#            o menu de opções de atualização.
#
# Uso: updates.sh <json [main|side]|open|menu|refresh|upgrade-terminal|fix-repos|status>
# ==============================================================================
set -uo pipefail

export PATH="$HOME/.local/bin:/snap/bin:$PATH"
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-GNOME}"

SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
CACHE_FILE="$STATE_DIR/updates-cache.json"
NOTIFIED_FILE="$STATE_DIR/updates-notified"
LOCK_FILE="$STATE_DIR/updates.lock"
WAYBAR_SIGNAL=10
CACHE_TTL="${UPDATES_CACHE_TTL:-300}"

WOFI_CONFIG="$HOME/.config/wofi/config"
WOFI_STYLE="$HOME/.config/wofi/style.css"

mkdir -p "$STATE_DIR"

refresh_waybar() {
    pkill -RTMIN+$WAYBAR_SIGNAL waybar 2>/dev/null || true
}

# Retorna o maior timestamp (mtime) dentre os arquivos de estado de pacotes do
# sistema (dpkg, apt, snap, flatpak e reboot-required). Se qualquer um for mais
# novo que o cache, sabemos que houve atualização/instalação no sistema.
latest_system_state_mtime() {
    local max_mtime=0 m
    local watched_paths=(
        /var/lib/dpkg/status
        /var/log/dpkg.log
        /var/log/apt/history.log
        /var/cache/apt/pkgcache.bin
        /var/lib/apt/periodic/update-success-stamp
        /var/lib/snapd/state.json
        /var/lib/flatpak/repo
        /var/lib/flatpak/app
        /var/lib/flatpak/runtime
        "$HOME/.local/share/flatpak/repo"
        "$HOME/.local/share/flatpak/app"
        "$HOME/.local/share/flatpak/runtime"
        /var/run/reboot-required
    )
    for p in "${watched_paths[@]}"; do
        [ -e "$p" ] || continue
        m="$(stat -c %Y "$p" 2>/dev/null || echo 0)"
        if [[ "$m" =~ ^[0-9]+$ ]] && [ "$m" -gt "$max_mtime" ]; then
            max_mtime="$m"
        fi
    done
    echo "$max_mtime"
}

# Coleta contagens e listas de pacotes (APT, Snap, Flatpak e reboot pendente)
# e grava um JSON estruturado em $CACHE_FILE.
collect_updates() {
    local tmp_apt tmp_snap tmp_flatpak
    tmp_apt="$(mktemp)"
    tmp_snap="$(mktemp)"
    tmp_flatpak="$(mktemp)"

    # 1) APT (usa o apt_check oficial do Ubuntu + filtra apenas pacotes instalados)
    python3 - <<'PY' >"$tmp_apt" 2>/dev/null &
import io, json, sys
sys.path.insert(0, "/usr/lib/update-notifier")
try:
    import apt
    import apt_check
    apt_check.init()
    class Opts:
        show_package_names = True
        readable_output = False
        hide_esm_messages = True
        security_updates_unattended = False
    buf = io.StringIO()
    old_err = sys.stderr
    sys.stderr = buf
    upgrades, security = apt_check.run(Opts())
    sys.stderr = old_err
    raw_pkgs = {p.strip() for p in buf.getvalue().splitlines() if p.strip()}
    try:
        cache = apt.Cache()
        pkgs = sorted(p for p in raw_pkgs if p in cache and cache[p].is_installed)
    except Exception:
        pkgs = sorted(raw_pkgs)
    count = len(pkgs) if pkgs else int(upgrades)
    sec_count = min(int(security), count)
    print(json.dumps({"count": count, "security": sec_count, "packages": pkgs}))
except Exception:
    print(json.dumps({"count": 0, "security": 0, "packages": []}))
PY
    local pid_apt=$!

    # 2) Snap
    (
        if command -v snap >/dev/null 2>&1; then
            LC_ALL=C timeout 15 snap refresh --list 2>/dev/null \
                | awk 'NR>1 && NF>0 {print $1}' | sort -u
        fi
    ) >"$tmp_snap" &
    local pid_snap=$!

    # 3) Flatpak
    (
        if command -v flatpak >/dev/null 2>&1; then
            LC_ALL=C timeout 15 flatpak remote-ls --updates --columns=name 2>/dev/null \
                | sed '/^[[:space:]]*$/d' | sort -u
        fi
    ) >"$tmp_flatpak" &
    local pid_flatpak=$!

    wait "$pid_apt" "$pid_snap" "$pid_flatpak" 2>/dev/null || true

    local reboot_req=0
    [ -f /var/run/reboot-required ] && reboot_req=1

    python3 - "$tmp_apt" "$tmp_snap" "$tmp_flatpak" "$reboot_req" "$CACHE_FILE" <<'PY'
import json, os, sys, time

apt_file, snap_file, flatpak_file, reboot_str, out_file = sys.argv[1:6]

try:
    with open(apt_file, "r", encoding="utf-8") as f:
        apt_data = json.load(f)
except Exception:
    apt_data = {"count": 0, "security": 0, "packages": []}

def read_lines(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return [line.strip() for line in f if line.strip()]
    except Exception:
        return []

snaps = read_lines(snap_file)
flatpaks = read_lines(flatpak_file)

apt_count = int(apt_data.get("count", 0))
apt_sec = int(apt_data.get("security", 0))
apt_pkgs = apt_data.get("packages", [])
if apt_count == 0 and apt_pkgs:
    apt_count = len(apt_pkgs)

snap_count = len(snaps)
flatpak_count = len(flatpaks)
total = apt_count + snap_count + flatpak_count
reboot_req = bool(int(reboot_str))

data = {
    "timestamp": int(time.time()),
    "total": total,
    "apt": apt_count,
    "security": apt_sec,
    "apt_packages": apt_pkgs,
    "snap": snap_count,
    "snap_packages": snaps,
    "flatpak": flatpak_count,
    "flatpak_packages": flatpaks,
    "reboot_required": reboot_req,
}

tmp_out = out_file + ".tmp"
with open(tmp_out, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False)
os.replace(tmp_out, out_file)
PY
    rm -f "$tmp_apt" "$tmp_snap" "$tmp_flatpak"
}

ensure_cache() {
    local force="${1:-0}"
    exec 9>"$LOCK_FILE"
    flock 9

    local now mtime age sys_mtime
    now="$(date +%s)"
    mtime=0
    if [ -f "$CACHE_FILE" ]; then
        mtime="$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)"
    fi
    age=$(( now - mtime ))
    sys_mtime="$(latest_system_state_mtime)"

    # Recalcula se forçado, se o cache não existir, se expirou o TTL ou se
    # qualquer banco de pacotes (dpkg/apt/snap/flatpak) mudou após o cache!
    if [ "$force" = "1" ] || [ ! -f "$CACHE_FILE" ] || [ "$age" -ge "$CACHE_TTL" ] || [ "$sys_mtime" -gt "$mtime" ]; then
        collect_updates
        maybe_notify
    fi

    exec 9>&-
}

maybe_notify() {
    [ -f "$CACHE_FILE" ] || return 0
    command -v notify-send >/dev/null 2>&1 || return 0

    local sig prev_sig total apt sec snap flatpak reboot_req
    read -r total apt sec snap flatpak reboot_req < <(
        jq -r '[.total, .apt, .security, .snap, .flatpak, (if .reboot_required then 1 else 0 end)] | @tsv' "$CACHE_FILE" 2>/dev/null || echo "0 0 0 0 0 0"
    )

    sig="${total}:${apt}:${sec}:${snap}:${flatpak}:${reboot_req}"
    prev_sig=""
    [ -f "$NOTIFIED_FILE" ] && prev_sig="$(cat "$NOTIFIED_FILE" 2>/dev/null || true)"

    [ "$sig" = "$prev_sig" ] && return 0
    echo "$sig" > "$NOTIFIED_FILE"

    if [ "$total" -gt 0 ]; then
        local urgency="normal"
        [ "$sec" -gt 0 ] && urgency="critical"
        local body="Sistema (APT): ${apt}"
        [ "$sec" -gt 0 ] && body="${body} (${sec} de segurança)"
        body="${body} · Snap: ${snap} · Flatpak: ${flatpak}"
        [ "$reboot_req" -eq 1 ] && body="${body}\nReinicialização do sistema pendente."
        notify-send -u "$urgency" -a "Atualizações do Ubuntu" -i system-software-update \
            "󰚰  ${total} atualizações disponíveis" "$body"
    elif [ "$reboot_req" -eq 1 ]; then
        notify-send -u normal -a "Atualizações do Ubuntu" -i system-reboot \
            "Reinicialização necessária" "Conclua a aplicação das atualizações reiniciando o sistema."
    fi
}

output_waybar_json() {
    local layout="${1:-main}"
    ensure_cache 0

    python3 - "$CACHE_FILE" "$layout" <<'PY'
import json, sys

cache_file, layout = sys.argv[1:3]
try:
    with open(cache_file, "r", encoding="utf-8") as f:
        d = json.load(f)
except Exception:
    d = {
        "total": 0, "apt": 0, "security": 0, "apt_packages": [],
        "snap": 0, "snap_packages": [], "flatpak": 0, "flatpak_packages": [],
        "reboot_required": False
    }

total = d.get("total", 0)
apt_c = d.get("apt", 0)
sec_c = d.get("security", 0)
snap_c = d.get("snap", 0)
flat_c = d.get("flatpak", 0)
reboot_req = d.get("reboot_required", False)

def fmt_list(items, limit=12):
    if not items:
        return ""
    shown = items[:limit]
    extra = len(items) - len(shown)
    line = ", ".join(shown)
    if extra > 0:
        line += f" (+{extra})"
    return f"  <small>{line}</small>"

lines = []
if total > 0:
    lines.append(f"<b>󰚰  {total} atualizações disponíveis</b>")
    lines.append("")
    if apt_c > 0:
        sec_str = f" <i>({sec_c} de segurança)</i>" if sec_c > 0 else ""
        lines.append(f"• <b>Sistema / APT:</b> {apt_c}{sec_str}")
        pkg_line = fmt_list(d.get("apt_packages", []))
        if pkg_line:
            lines.append(pkg_line)
    if snap_c > 0:
        lines.append(f"• <b>Snap:</b> {snap_c}")
        pkg_line = fmt_list(d.get("snap_packages", []))
        if pkg_line:
            lines.append(pkg_line)
    if flat_c > 0:
        lines.append(f"• <b>Flatpak:</b> {flat_c}")
        pkg_line = fmt_list(d.get("flatpak_packages", []))
        if pkg_line:
            lines.append(pkg_line)
else:
    lines.append("<b>󰄬  Sistema e aplicativos atualizados</b>")

if reboot_req:
    lines.append("")
    lines.append("<b>⚠  Reinicialização necessária para concluir atualizações</b>")

lines.append("")
lines.append("<small>Clique: Atualizar sistema · Direito: menu de opções · Meio: verificar</small>")
tooltip = "\n".join(lines)

if total > 0:
    icon = "󰚰"
    text = f"{icon}\n{total}" if layout == "side" else f"{icon} {total}"
    css_class = "security" if (sec_c > 0 or reboot_req) else "has-updates"
    alt = "has-updates"
elif reboot_req:
    text = "󰜉"
    css_class = "reboot"
    alt = "reboot"
else:
    text = "󰄬"
    css_class = "up-to-date"
    alt = "up-to-date"

print(json.dumps({
    "text": text,
    "tooltip": tooltip,
    "class": css_class,
    "alt": alt
}, ensure_ascii=False))
PY
}

window_open() {
    local pattern="$1"
    local addr
    addr="$(hyprctl clients -j 2>/dev/null | jq -r --arg p "$pattern" \
        'first(.[] | select((.class // "") | test($p; "i")) | .address) // empty')"
    [ -n "$addr" ]
}

focus_if_open() {
    local pattern="$1"
    local addr
    addr="$(hyprctl clients -j 2>/dev/null | jq -r --arg p "$pattern" \
        'first(.[] | select((.class // "") | test($p; "i")) | .address) // empty')"
    if [ -n "$addr" ]; then
        hyprctl dispatch focuswindow "address:$addr" >/dev/null 2>&1 || true
        return 0
    fi
    return 1
}

# Aguarda o fechamento da janela GUI (mesmo em apps DBus single-instance como
# gnome-software / snap-store) e atualiza a Waybar em tempo real sempre que
# algum pacote terminar de ser instalado (mesmo com a janela ainda aberta).
wait_gui_and_refresh() {
    local win_pattern="$1"
    shift
    local last_sys_mtime
    last_sys_mtime="$(latest_system_state_mtime)"

    if [ "$#" -gt 0 ]; then
        "$@" >/dev/null 2>&1 &
        local pid=$!
        # Aguarda a janela abrir (até 8s) para podermos monitorar seu fechamento
        for _ in $(seq 1 16); do
            window_open "$win_pattern" && break
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.5
        done
    fi

    # Monitora enquanto a janela estiver aberta ou o processo vivo, atualizando
    # o contador da Waybar ao vivo assim que o dpkg/snap/flatpak modificar o sistema
    local cur_sys_mtime
    while window_open "$win_pattern" || { [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; }; do
        sleep 2
        cur_sys_mtime="$(latest_system_state_mtime)"
        if [ "$cur_sys_mtime" -gt "$last_sys_mtime" ]; then
            last_sys_mtime="$cur_sys_mtime"
            ensure_cache 1
            refresh_waybar
        fi
    done

    # Caso o update-manager/gnome-software tenha delegado ao aptdaemon/packagekit/dpkg, aguarda concluir
    while pgrep -x "dpkg|apt|apt-get" >/dev/null 2>&1; do
        sleep 1
    done

    ensure_cache 1
    refresh_waybar
}

open_ubuntu_updater() {
    if focus_if_open "^system-updater$"; then
        exit 0
    fi
    upgrade_in_terminal
}

# Verifica se existem listas de repositórios APT apontando para codinomes antigos
# do Ubuntu (ex: questing após upgrade para resolute) ou arquivos órfãos em
# /var/lib/apt/lists/ que causam erro 404 durante o download de pacotes.
needs_apt_repo_repair() {
    local codename
    codename="$(. /etc/os-release 2>/dev/null && printf '%s' "${VERSION_CODENAME:-resolute}")"
    [ -z "$codename" ] && codename="resolute"

    local old_suite
    for old_suite in questing plucky oracular mantic lunar kinetic impish hirsute groovy focal; do
        [ "$old_suite" = "$codename" ] && continue
        if grep -RqsE "^[[:space:]]*deb .*[[:space:]]${old_suite}([[:space:]]|$)" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
            return 0
        fi
        if grep -RqsE "^[[:space:]]*Suites:.*\\b${old_suite}\\b" /etc/apt/sources.list.d/*.sources 2>/dev/null; then
            return 0
        fi
        if compgen -G "/var/lib/apt/lists/*_dists_${old_suite}_*" >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

# Executa (via root/sudo/pkexec) o reparo automático de repositórios APT com
# codinome antigo do Ubuntu (como o Pritunl em 'questing' após upgrade para
# 'resolute') e remove índices órfãos em /var/lib/apt/lists/ que travam o
# apt full-upgrade e o update-manager com erro 404 Not Found.
run_apt_repo_repair() {
    needs_apt_repo_repair || return 0
    local auth_cmd="${1:-sudo}"
    printf "\033[38;2;137;180;250m\033[1m▶ Corrigindo repositórios APT de versões antigas do Ubuntu...\033[0m\n"
    "$auth_cmd" bash -c '
        set -u
        C_RESET="\033[0m"
        C_BOLD="\033[1m"
        C_BLUE="\033[38;2;137;180;250m"
        C_GREEN="\033[38;2;166;227;161m"
        C_YELLOW="\033[38;2;249;226;175m"

        codename="$(. /etc/os-release 2>/dev/null && printf "%s" "${VERSION_CODENAME:-resolute}")"
        [ -z "$codename" ] && codename="resolute"
        repaired=0

        for old_suite in questing plucky oracular mantic lunar kinetic impish hirsute groovy focal; do
            [ "$old_suite" = "$codename" ] && continue

            for list_file in /etc/apt/sources.list.d/*.list; do
                [ -f "$list_file" ] || continue
                if grep -qE "^[[:space:]]*deb .*[[:space:]]${old_suite}([[:space:]]|$)" "$list_file" 2>/dev/null; then
                    repo_url="$(awk "/^[[:space:]]*deb / {for(i=2;i<=NF;i++) if(\$i ~ /^https?:\\/\\//) {print \$i; exit}}" "$list_file")"
                    if [ -n "$repo_url" ]; then
                        repo_url="${repo_url%/}"
                        http_new="$(curl -sL --max-time 8 -o /dev/null -w "%{http_code}" "${repo_url}/dists/${codename}/Release" 2>/dev/null || echo 000)"
                        http_old="$(curl -sL --max-time 8 -o /dev/null -w "%{http_code}" "${repo_url}/dists/${old_suite}/Release" 2>/dev/null || echo 000)"
                        if [ "$http_new" = "200" ]; then
                            printf "${C_BLUE}🔧 Atualizando repositório em %s: ${old_suite} → ${codename}${C_RESET}\n" "$(basename "$list_file")"
                            cp -a "$list_file" "${list_file}.bak" 2>/dev/null || true
                            sed -i -E "s/([[:space:]])${old_suite}([[:space:]]|\$)/\\1${codename}\\2/g" "$list_file"
                            repaired=1
                        elif [ "$http_old" = "404" ]; then
                            printf "${C_YELLOW}⚠ Desativando repositório sem suporte a ${codename} (404) em %s${C_RESET}\n" "$(basename "$list_file")"
                            cp -a "$list_file" "${list_file}.bak" 2>/dev/null || true
                            sed -i -E "s/^([[:space:]]*deb .*[[:space:]]${old_suite}([[:space:]]|\$))/# [Desativado: sem Release para ${codename}] \\1/" "$list_file"
                            repaired=1
                        fi
                    fi
                fi
            done

            if compgen -G "/var/lib/apt/lists/*_dists_${old_suite}_*" >/dev/null 2>&1; then
                printf "${C_BLUE}🧹 Removendo índices APT órfãos da versão antiga (${old_suite})...${C_RESET}\n"
                rm -f /var/lib/apt/lists/*_dists_"${old_suite}"_*
                repaired=1
            fi
        done

        if [ "$repaired" -eq 1 ]; then
            printf "${C_GREEN}✔ Repositórios antigos/órfãos corrigidos com sucesso.${C_RESET}\n"
        fi
    '
}

upgrade_in_terminal() {
    if focus_if_open "^system-updater$"; then
        exit 0
    fi
    kitty --class "system-updater" --title "Atualizador do Sistema" bash -c '
        set -o pipefail
        SCRIPT_PATH="$1"
        C_RESET="\033[0m"
        C_BOLD="\033[1m"
        C_BLUE="\033[38;2;137;180;250m"
        C_GREEN="\033[38;2;166;227;161m"
        C_YELLOW="\033[38;2;249;226;175m"
        C_RED="\033[38;2;243;139;168m"

        printf "${C_BLUE}${C_BOLD}╭──────────────────────────────────────────────────────────────╮${C_RESET}\n"
        printf "${C_BLUE}${C_BOLD}│  󰚰  Atualizador do Sistema (APT · Snap · Flatpak)            │${C_RESET}\n"
        printf "${C_BLUE}${C_BOLD}╰──────────────────────────────────────────────────────────────╯${C_RESET}\n\n"

        # Verifica e repara automaticamente repositórios de versões antigas do Ubuntu
        # (ex: pritunl em questing -> resolute) e listas órfãs em /var/lib/apt/lists/
        "$SCRIPT_PATH" fix-repos-internal sudo || true

        printf "${C_BLUE}${C_BOLD}▶ [1/3] Atualizando listas de repositórios (APT)...${C_RESET}\n"
        apt_update_log="$(mktemp)"
        if ! sudo apt update 2>&1 | tee "$apt_update_log"; then
            printf "\n${C_YELLOW}⚠ Aviso: algum repositório retornou erro no apt update.${C_RESET}\n"
            # Se algum repositório retornou 404 (sem arquivo Release), remove a lista
            # antiga correspondente em /var/lib/apt/lists/ para não travar o upgrade
            dead_urls="$(sed -nE "s/.*'\''(https?:\/\/[^ ]+) ([^ ]+) Release'\''.*/\1|\2/p" "$apt_update_log" 2>/dev/null || true)"
            if [ -n "$dead_urls" ]; then
                while IFS="|" read -r d_url d_suite; do
                    [ -z "$d_url" ] && continue
                    d_host="${d_url#*://}"
                    d_host="${d_host%%/*}"
                    printf "${C_YELLOW}  Limpando cache órfão de repositório indisponível (${d_host} / ${d_suite})...${C_RESET}\n"
                    sudo rm -f /var/lib/apt/lists/*"${d_host}"*_"${d_suite}"_* 2>/dev/null || true
                done <<< "$dead_urls"
            fi
            printf "${C_YELLOW}  Prosseguindo com a atualização dos pacotes disponíveis...${C_RESET}\n"
        fi
        rm -f "$apt_update_log"

        printf "\n${C_BLUE}${C_BOLD}▶ [1/3] Instalando atualizações do sistema (APT full-upgrade)...${C_RESET}\n"
        sudo dpkg --configure -a || true
        apt_ok=1
        if ! sudo apt full-upgrade -y; then
            printf "\n${C_YELLOW}⚠ Falha ao baixar algum pacote; tentando novamente com --fix-missing...${C_RESET}\n"
            if ! sudo apt full-upgrade -y --fix-missing; then
                apt_ok=0
                printf "${C_RED}✖ Erro: alguns pacotes APT não puderam ser instalados.${C_RESET}\n"
            fi
        fi

        if command -v snap >/dev/null 2>&1; then
            printf "\n${C_BLUE}${C_BOLD}▶ [2/3] Atualizando pacotes Snap...${C_RESET}\n"
            if ! sudo snap refresh; then
                printf "${C_YELLOW}⚠ Aviso: se algum Snap (ex: Firefox) estiver aberto, feche-o para concluí-lo.${C_RESET}\n"
            fi
        fi

        if command -v flatpak >/dev/null 2>&1; then
            printf "\n${C_BLUE}${C_BOLD}▶ [3/3] Atualizando aplicativos Flatpak...${C_RESET}\n"
            flatpak update -y || true
        fi

        printf "\n${C_BLUE}⟳ Atualizando contador da Waybar...${C_RESET}\n"
        "$SCRIPT_PATH" refresh >/dev/null 2>&1 || true
        if [ "$apt_ok" -eq 1 ]; then
            printf "${C_GREEN}${C_BOLD}✔ Atualização concluída com sucesso!${C_RESET}\n\n"
        else
            printf "${C_YELLOW}${C_BOLD}⚠ Atualização finalizada com avisos (verifique as mensagens acima).${C_RESET}\n\n"
        fi
        read -rp "Pressione Enter para fechar..."
    ' _ "$SCRIPT_PATH"
    ensure_cache 1
    refresh_waybar
}

wofi_menu() {
    local args=(--dmenu --insensitive --width 580 --height 320 --prompt "$1")
    [ -f "$WOFI_CONFIG" ] && args+=(--conf "$WOFI_CONFIG")
    [ -f "$WOFI_STYLE" ] && args+=(--style "$WOFI_STYLE")
    wofi "${args[@]}"
}

menu() {
    ensure_cache 0
    local total apt_c sec_c snap_c flat_c
    read -r total apt_c sec_c snap_c flat_c < <(
        jq -r '[.total, .apt, .security, .snap, .flatpak] | @tsv' "$CACHE_FILE" 2>/dev/null || echo "0 0 0 0 0"
    )

    local opt_term="󰆍  Atualizar tudo agora (APT: ${apt_c} · Snap: ${snap_c} · Flatpak: ${flat_c})"
    local opt_gnome="󰏖  GNOME Software — Atualizações (Flatpak: ${flat_c} · Apps)"
    local opt_snap="󰀻  Ubuntu App Center — Atualizações (Snap: ${snap_c})"
    local opt_ubuntu="󰚰  Atualizador de Programas do Ubuntu (APT: ${apt_c})"
    local opt_repair="󰁨  Reparar repositórios APT com erro 404"
    local opt_check="󰑐  Verificar atualizações agora"

    local menu_items=(
        "$opt_term"
        "$opt_gnome"
        "$opt_snap"
        "$opt_ubuntu"
    )
    if needs_apt_repo_repair; then
        menu_items+=("$opt_repair")
    fi
    menu_items+=("$opt_check")

    local choice
    choice="$(printf '%s\n' "${menu_items[@]}" | wofi_menu "Atualizações (${total} pendentes)")" || exit 0

    [ -z "$choice" ] && exit 0

    case "$choice" in
        "$opt_ubuntu")
            if needs_apt_repo_repair && command -v pkexec >/dev/null 2>&1; then
                notify-send -u normal -a "Atualizações do Ubuntu" -i system-software-update \
                    "Reparando repositório APT..." "Corrigindo repositório antigo (404) antes de abrir o Atualizador." 2>/dev/null || true
                pkexec bash -c '"$1" fix-repos-internal root && apt-get update -qq' _ "$SCRIPT_PATH" >/dev/null 2>&1 || true
            fi
            if focus_if_open "^update-manager$"; then
                wait_gui_and_refresh "^update-manager$"
            else
                wait_gui_and_refresh "^update-manager$" update-manager
            fi
            ;;
        "$opt_gnome")
            if focus_if_open "^org\\.gnome\\.Software$"; then
                wait_gui_and_refresh "^org\\.gnome\\.Software$"
            else
                wait_gui_and_refresh "^org\\.gnome\\.Software$" gnome-software --mode=updates
            fi
            ;;
        "$opt_snap")
            if focus_if_open "^snap-store$"; then
                wait_gui_and_refresh "^snap-store$"
            elif [ -x /snap/bin/snap-store.show-updates ]; then
                wait_gui_and_refresh "^snap-store$" /snap/bin/snap-store.show-updates --updates
            else
                wait_gui_and_refresh "^snap-store$" snap-store
            fi
            ;;
        "$opt_term")
            upgrade_in_terminal
            ;;
        "$opt_repair")
            if command -v pkexec >/dev/null 2>&1; then
                pkexec bash -c '"$1" fix-repos-internal root && apt-get update' _ "$SCRIPT_PATH" || true
            else
                kitty --class "system-updater" --title "Reparar Repositórios APT" bash -c '"$1" fix-repos-internal sudo && sudo apt update; read -rp "Pressione Enter para fechar..."' _ "$SCRIPT_PATH"
            fi
            rm -f "$NOTIFIED_FILE"
            ensure_cache 1
            refresh_waybar
            ;;
        "$opt_check")
            rm -f "$NOTIFIED_FILE"
            ensure_cache 1
            refresh_waybar
            ;;
    esac
}

case "${1:-json}" in
    json)
        output_waybar_json "${2:-main}"
        ;;
    open)
        open_ubuntu_updater
        ;;
    menu)
        menu
        ;;
    refresh)
        rm -f "$NOTIFIED_FILE"
        ensure_cache 1
        refresh_waybar
        ;;
    upgrade-terminal)
        upgrade_in_terminal
        ;;
    fix-repos)
        run_apt_repo_repair sudo
        sudo apt update || true
        rm -f "$NOTIFIED_FILE"
        ensure_cache 1
        refresh_waybar
        ;;
    fix-repos-internal)
        if [ "${2:-sudo}" = "root" ]; then
            run_apt_repo_repair env
        else
            run_apt_repo_repair "${2:-sudo}"
        fi
        ;;
    status)
        ensure_cache 0
        cat "$CACHE_FILE"
        echo
        ;;
    *)
        echo "Uso: $0 <json [main|side]|open|menu|refresh|upgrade-terminal|fix-repos|status>" >&2
        exit 1
        ;;
esac
