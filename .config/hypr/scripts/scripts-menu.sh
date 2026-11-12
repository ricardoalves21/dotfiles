#!/usr/bin/env bash
# ==============================================================================
# Script: scripts-menu.sh
# Descrição: Exibe um menu Wofi (tema Catppuccin Mocha) com todos os scripts
#            (.sh e .py) em ~/desktop/scripts e ~/scripts.
#            Por padrão, abre no Kitty para acompanhar a execução; use a
#            anotação "# @background" (ou "# @silent") no topo do script para
#            rodá-lo em segundo plano com log em /tmp.
# Atalhos:   SUPER + T  |  SUPER + SHIFT + R
# ==============================================================================
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

SEARCH_DIRS=(
    "$HOME/desktop/scripts"
    "$HOME/scripts"
)

WOFI_ARGS=(
    --dmenu
    --insensitive
    --width 540
    --height 360
    --prompt "Executar script"
)
[ -f "$HOME/.config/wofi/config" ] && WOFI_ARGS+=(--conf "$HOME/.config/wofi/config")
[ -f "$HOME/.config/wofi/style.css" ] && WOFI_ARGS+=(--style "$HOME/.config/wofi/style.css")

declare -a raw_paths=()
for dir in "${SEARCH_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    while IFS= read -r path; do
        [ -n "$path" ] && raw_paths+=("$path")
    done < <(find "$dir" -maxdepth 1 \( -type f -o -type l \) \( -name "*.sh" -o -name "*.py" \) | sort)
done

if [ "${#raw_paths[@]}" -eq 0 ]; then
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a "Scripts" "Nenhum script encontrado" "Adicione arquivos .sh ou .py em ~/desktop/scripts ou ~/scripts"
    fi
    exit 0
fi

# Conta nomes repetidos para desambiguar apenas se necessário
declare -A name_counts=()
for path in "${raw_paths[@]}"; do
    base="$(basename "$path")"
    name_counts["$base"]=$(( ${name_counts["$base"]:-0} + 1 ))
done

declare -a labels=()
declare -A label_to_path=()
for path in "${raw_paths[@]}"; do
    base="$(basename "$path")"
    if [ "${name_counts["$base"]}" -gt 1 ]; then
        rel_dir="$(dirname "${path/#$HOME\//~/}")"
        label="${base}  (${rel_dir})"
    else
        label="$base"
    fi
    labels+=("$label")
    label_to_path["$label"]="$path"
done

selected="$(printf '%s\n' "${labels[@]}" | wofi "${WOFI_ARGS[@]}")" || exit 0
[ -z "$selected" ] && exit 0

script_path="${label_to_path["$selected"]:-}"
if [ -z "$script_path" ] || [ ! -f "$script_path" ]; then
    command -v notify-send >/dev/null 2>&1 && notify-send -u critical -a "Scripts" "Script não encontrado" "${selected}"
    exit 1
fi

script_name="$(basename "$script_path")"
chmod +x "$script_path" 2>/dev/null || true

# Define executor (.py sem shebang roda via python3)
first_line="$(head -n 1 "$script_path" 2>/dev/null || true)"
use_python=0
if [[ "$script_name" == *.py ]] && [[ "$first_line" != "#!"* ]]; then
    use_python=1
fi

# Se tiver anotação explícita de segundo plano (# @background / # @silent / # @nohup), roda sem terminal
if head -n 25 "$script_path" | grep -qiE "^#\s*@(background|silent|nohup)\b"; then
    if [ "$use_python" -eq 1 ]; then
        nohup python3 "$script_path" > "/tmp/${script_name}.log" 2>&1 &
    else
        nohup "$script_path" > "/tmp/${script_name}.log" 2>&1 &
    fi
else
    # Padrão (incluindo # @terminal / # @interactive): abre no Kitty mantendo a saída visível
    kitty --title "Script: ${script_name}" bash -c '
        if [ "$1" = "1" ]; then
            python3 "$2"
        else
            "$2"
        fi
        rc=$?
        echo
        printf "\033[2m[ Concluído (código %d) — pressione Enter para fechar... ]\033[0m" "$rc"
        read -r _
    ' _ "$use_python" "$script_path" &
fi
