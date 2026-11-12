#!/usr/bin/env bash
# Instalador leve de pacotes .deb no Kitty para Hyprland
# Uso: deb-installer.sh [/caminho/para/pacote.deb]
set -uo pipefail

export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# cores ANSI (paleta Slate / Catppuccin)
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_BLUE='\033[38;2;137;180;250m'
C_GREEN='\033[38;2;166;227;161m'
C_YELLOW='\033[38;2;249;226;175m'
C_RED='\033[38;2;243;139;168m'
C_SUB='\033[38;2;186;194;222m'

pick_deb_from_downloads() {
    local dl_dir="$HOME/Downloads"
    [ -d "$dl_dir" ] || dl_dir="$HOME"

    mapfile -t files < <(find "$dl_dir" -maxdepth 2 -type f -iname '*.deb' -printf '%T@\t%p\n' 2>/dev/null | sort -rn | cut -f2-)
    if [ "${#files[@]}" -eq 0 ]; then
        notify-send -a "Instalador .deb" "Nenhum arquivo .deb encontrado" "Não há pacotes .deb em $dl_dir." 2>/dev/null || true
        exit 0
    fi

    local chosen=""
    if command -v wofi >/dev/null 2>&1; then
        local wofi_args=(--dmenu --insensitive --prompt "Selecionar pacote .deb")
        [ -f "$HOME/.config/wofi/config" ] && wofi_args+=(--conf "$HOME/.config/wofi/config")
        [ -f "$HOME/.config/wofi/style.css" ] && wofi_args+=(--style "$HOME/.config/wofi/style.css")
        chosen="$(printf '%s\n' "${files[@]}" | wofi "${wofi_args[@]}")" || exit 0
    elif command -v rofi >/dev/null 2>&1; then
        chosen="$(printf '%s\n' "${files[@]}" | rofi -dmenu -i -p "󰏖  Pacote .deb")" || exit 0
    else
        chosen="${files[0]}"
    fi

    [ -n "$chosen" ] || exit 0
    printf '%s\n' "$chosen"
}

run_ui() {
    local deb_file="$1"

    if [ ! -f "$deb_file" ]; then
        printf "${C_RED}${C_BOLD}✖ Arquivo não encontrado:${C_RESET} %s\n\n" "$deb_file"
        read -rp "Pressione Enter para fechar..." _
        exit 1
    fi

    local pkg ver arch size_kb maintainer summary
    if ! pkg="$(dpkg-deb -f "$deb_file" Package 2>/dev/null)" || [ -z "$pkg" ]; then
        printf "${C_RED}${C_BOLD}✖ Arquivo .deb inválido ou corrompido:${C_RESET}\n  %s\n\n" "$deb_file"
        read -rp "Pressione Enter para fechar..." _
        exit 1
    fi

    ver="$(dpkg-deb -f "$deb_file" Version 2>/dev/null || echo "desconhecida")"
    arch="$(dpkg-deb -f "$deb_file" Architecture 2>/dev/null || echo "desconhecida")"
    size_kb="$(dpkg-deb -f "$deb_file" Installed-Size 2>/dev/null || echo "0")"
    maintainer="$(dpkg-deb -f "$deb_file" Maintainer 2>/dev/null || echo "-")"
    summary="$(dpkg-deb -f "$deb_file" Description 2>/dev/null | head -n 1 || echo "-")"

    local size_human="-"
    if [[ "$size_kb" =~ ^[0-9]+$ ]] && [ "$size_kb" -gt 0 ]; then
        size_human="$(awk -v kb="$size_kb" 'BEGIN { if (kb >= 1024) printf "%.1f MB", kb/1024; else printf "%d KB", kb }')"
    fi

    # Verifica se já existe uma versão instalada no sistema
    local current_ver="" action_label=""
    if dpkg-query -W -f='${db:Status-Status}' "$pkg" 2>/dev/null | grep -qx "installed"; then
        current_ver="$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || true)"
    fi

    if [ -z "$current_ver" ]; then
        action_label="${C_GREEN}Nova instalação${C_RESET}"
    elif [ "$current_ver" = "$ver" ]; then
        action_label="${C_YELLOW}Reinstalar mesma versão (${current_ver})${C_RESET}"
    elif dpkg --compare-versions "$ver" gt "$current_ver" 2>/dev/null; then
        action_label="${C_BLUE}Atualização (${current_ver} → ${ver})${C_RESET}"
    else
        action_label="${C_YELLOW}Downgrade (${current_ver} → ${ver})${C_RESET}"
    fi

    clear
    printf "${C_BLUE}${C_BOLD}╭──────────────────────────────────────────────────────────────╮${C_RESET}\n"
    printf "${C_BLUE}${C_BOLD}│  󰏖  Instalador de Pacotes Debian (.deb)                      │${C_RESET}\n"
    printf "${C_BLUE}${C_BOLD}╰──────────────────────────────────────────────────────────────╯${C_RESET}\n\n"
    printf "  ${C_BOLD}Pacote:${C_RESET}       %s\n" "$pkg"
    printf "  ${C_BOLD}Versão:${C_RESET}       %s\n" "$ver"
    printf "  ${C_BOLD}Ação:${C_RESET}         %b\n" "$action_label"
    printf "  ${C_BOLD}Arquitetura:${C_RESET}  %s\n" "$arch"
    printf "  ${C_BOLD}Tamanho:${C_RESET}      %s (instalado)\n" "$size_human"
    printf "  ${C_BOLD}Mantenedor:${C_RESET}   ${C_SUB}%s${C_RESET}\n" "$maintainer"
    printf "  ${C_BOLD}Descrição:${C_RESET}    ${C_SUB}%s${C_RESET}\n" "$summary"
    printf "  ${C_BOLD}Arquivo:${C_RESET}      ${C_DIM}%s${C_RESET}\n\n" "$deb_file"

    local reply=""
    printf "${C_BOLD}Deseja continuar com a instalação? [S/n]: ${C_RESET}"
    read -r reply || exit 0
    case "${reply:-S}" in
        [sSyY]|"") ;;
        *)
            printf "\n${C_YELLOW}Instalação cancelada pelo usuário.${C_RESET}\n"
            sleep 0.8
            exit 0
            ;;
    esac

    printf "\n${C_BLUE}${C_BOLD}▶ Autenticando e instalando via APT...${C_RESET}\n\n"

    # Copia temporária em /tmp evita o aviso de permissão do usuário _apt em /home (0700)
    local staged_deb="" rc=0
    staged_deb="$(mktemp --tmpdir "deb-installer-XXXXXX.deb")"
    trap 'rm -f -- "${staged_deb:-}"' EXIT INT TERM
    if cp -f -- "$deb_file" "$staged_deb" && chmod 644 "$staged_deb"; then
        sudo apt install -y "$staged_deb"
        rc=$?
        rm -f -- "$staged_deb"
    else
        rm -f -- "$staged_deb" 2>/dev/null || true
        sudo apt install -y "$deb_file"
        rc=$?
    fi

    echo ""
    if [ "$rc" -eq 0 ]; then
        printf "${C_GREEN}${C_BOLD}✔ Pacote '%s' (%s) instalado com sucesso!${C_RESET}\n\n" "$pkg" "$ver"
        notify-send -a "Instalador .deb" "✔ Instalação concluída" "$pkg ($ver) foi instalado com sucesso." 2>/dev/null || true
        [ -x "$HOME/.config/hypr/scripts/updates.sh" ] && "$HOME/.config/hypr/scripts/updates.sh" refresh >/dev/null 2>&1 &
    else
        printf "${C_RED}${C_BOLD}✖ A instalação falhou (código %d).${C_RESET}\n\n" "$rc"
        notify-send -u critical -a "Instalador .deb" "✖ Falha na instalação" "Não foi possível instalar $pkg ($ver)." 2>/dev/null || true
    fi

    read -rp "Pressione Enter para fechar..." _
    exit "$rc"
}

# Modo interno já dentro da janela do Kitty
if [ "${1:-}" = "--ui" ]; then
    shift
    run_ui "${1:-}"
fi

TARGET="${1:-}"

# Converte URI file:// caso algum aplicativo envie %u em vez de %f
if [[ "$TARGET" == file://* ]]; then
    TARGET="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(urllib.parse.urlparse(sys.argv[1]).path))' "$TARGET")"
fi

if [ -z "$TARGET" ]; then
    TARGET="$(pick_deb_from_downloads)"
    [ -n "$TARGET" ] || exit 0
fi

TARGET="$(realpath -m -- "$TARGET" 2>/dev/null || printf '%s' "$TARGET")"

exec kitty --class "deb-installer" --title "Instalador de Pacotes (.deb)" -e "$0" --ui "$TARGET"
