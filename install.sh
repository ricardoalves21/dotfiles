#!/usr/bin/env bash
# Instala estes dotfiles criando symlinks em ~/.config
# Uso: ./install.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"

link() {
    local src="$REPO/.config/$1" dst="$HOME/.config/$1"
    if [ -L "$dst" ]; then
        rm "$dst"
    elif [ -e "$dst" ]; then
        echo "  backup: $dst -> $dst.bak-$TS"
        mv "$dst" "$dst.bak-$TS"
    fi
    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
    echo "  link:   ~/.config/$1"
}

echo "==> Garantindo permissões de execução nos scripts"
chmod +x "$REPO/.config/hypr/scripts/"*.sh "$REPO/.config/hypr/scripts/"*.py 2>/dev/null || true
chmod +x "$REPO/.config/quickshell/hyprquickpaper/commands.sh" 2>/dev/null || true
[ -f "$REPO/bin/mpvpaper" ] && chmod +x "$REPO/bin/mpvpaper"

echo "==> Instalando binários locais em ~/.local/bin"
mkdir -p "$HOME/.local/bin"
if [ -f "$REPO/bin/mpvpaper" ]; then
    cp -u "$REPO/bin/mpvpaper" "$HOME/.local/bin/mpvpaper"
    chmod +x "$HOME/.local/bin/mpvpaper"
    echo "  instalado: ~/.local/bin/mpvpaper"
fi

echo "==> Criando symlinks"
link hypr
link waybar
link kitty
link starship.toml
link wofi
link flameshot

echo "==> hyprquickpaper (seletor visual de wallpapers)"
# Upstream é um clone com .git próprio, então não dá para versioná-lo aqui
# dentro. Versionamos só os dois arquivos que customizamos e os symlinkamos
# por cima do clone — ele vai aparecer como "typechange" no git status dele.
HQP="$HOME/.config/quickshell/hyprquickpaper"
if [ ! -d "$HQP" ]; then
    echo "  clonando upstream em $HQP"
    mkdir -p "$(dirname "$HQP")"
    git clone -q https://github.com/iamsurjog/hyprquickpaper "$HQP"
fi
for f in config.json commands.sh; do
    [ -L "$HQP/$f" ] || [ ! -e "$HQP/$f" ] || mv "$HQP/$f" "$HQP/$f.bak-$TS"
    ln -sfn "$REPO/.config/quickshell/hyprquickpaper/$f" "$HQP/$f"
    echo "  link:   ~/.config/quickshell/hyprquickpaper/$f"
done

echo "==> Prompt (starship no bash)"
if grep -q 'starship init bash' "$HOME/.bashrc" 2>/dev/null; then
    echo "  ~/.bashrc já inicializa o starship"
else
    printf '\n# starship: prompt (config em ~/.config/starship.toml)\neval "$(starship init bash)"\n' >> "$HOME/.bashrc"
    echo "  adicionado ao ~/.bashrc"
fi

echo "==> Wallpaper: backend awww (transição animada)"
if command -v awww-daemon >/dev/null 2>&1; then
    echo "  awww $(awww --version 2>/dev/null | awk '{print $2}') presente"
else
    echo "  awww AUSENTE — o wallpaper.sh cai no hyprpaper, sem animação."
    echo "  Não existe pacote no Ubuntu nem binário pronto; compile do fonte:"
    echo "    sudo apt install cargo liblz4-dev libwayland-dev wayland-protocols"
    echo "    git clone --branch v0.12.1 https://codeberg.org/LGFae/awww ~/opt/awww"
    echo "    cd ~/opt/awww && cargo build --release"
    echo "    install -m755 target/release/awww target/release/awww-daemon ~/.local/bin/"
fi

echo "==> Verificando dependências"
missing=()
for c in hyprland waybar hyprpaper hyprlock grim slurp wl-copy jq notify-send kitty starship quickshell wofi; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
if [ ${#missing[@]} -gt 0 ]; then
    echo "  FALTANDO: ${missing[*]}"
    echo "  Ubuntu/Debian: sudo apt install hyprland waybar hyprpaper hyprlock hyprpolkitagent flameshot grim slurp wl-clipboard jq libnotify-bin kitty wofi btop pavucontrol brightnessctl playerctl imagemagick qml6-module-qt-labs-folderlistmodel python3-pil ffmpeg"
    echo "  starship:      curl -sS https://starship.rs/install.sh | sh"
else
    echo "  todas presentes"
fi

echo "==> Verificando Nerd Font (ícones da waybar e separadores do starship)"
if fc-list ':charset=F035B' 2>/dev/null | grep -q .; then
    echo "  Nerd Font OK"
else
    echo "  FALTANDO: sem Nerd Font os ícones da waybar aparecem como quadrados."
    echo "  Instale com:"
    echo "    mkdir -p ~/.local/share/fonts/NerdFonts && cd /tmp \\"
    echo "      && curl -LO https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip \\"
    echo "      && unzip -o -q JetBrainsMono.zip 'JetBrainsMonoNerdFont-*.ttf' -d ~/.local/share/fonts/NerdFonts \\"
    echo "      && fc-cache -f"
fi

echo "==> Criando pastas usadas pelos scripts"
mkdir -p "$HOME/Imagens/Wallpapers" "$HOME/Imagens/Screenshots" \
         "$HOME/Vídeos/video_wallpaper"
echo "  ~/Imagens/Wallpapers, ~/Imagens/Screenshots e ~/Vídeos/video_wallpaper"

echo
echo "================================================================="
echo " Instalação concluída com sucesso!"
echo "================================================================="
echo " IMPORTANTE - AJUSTE DE MONITORES:"
echo " 1. Rode 'hyprctl monitors' para ver o nome das suas telas."
echo " 2. Ajuste os nomes em ~/.config/hypr/hyprland.conf"
echo " 3. Se tiver 1 monitor só ou nomes diferentes, ajuste em ~/.config/waybar/config"
echo " Leia o GUIA_RAPIDO.md para o passo a passo completo e lista de atalhos!"
echo "================================================================="
