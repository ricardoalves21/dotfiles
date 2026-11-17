# 🚀 Guia Rápido de Instalação e Uso — Hyprland

Este pacote contém todas as configurações, scripts, atalhos e temas do desktop **Hyprland** (tema Matrix / Catppuccin Mocha), com Waybar personalizada, terminal Kitty, prompt Starship, seletor de wallpapers e muito mais.

---

## 1. 📦 Instalação das Dependências (Ubuntu / Debian)

Abra o seu terminal e execute os comandos abaixo para instalar todos os pacotes necessários:

```bash
sudo apt update && sudo apt install -y \
  hyprland waybar hyprpaper hyprlock \
  grim slurp wl-clipboard jq libnotify-bin \
  kitty wofi btop pavucontrol brightnessctl playerctl \
  imagemagick qml6-module-qt-labs-folderlistmodel python3-pil ffmpeg curl unzip
```

### Instalar o Starship (Prompt do Terminal):
```bash
curl -sS https://starship.rs/install.sh | sh
```

### Instalar a JetBrains Mono Nerd Font (Essencial!):
> **Atenção:** Sem a Nerd Font, os ícones da Waybar e os separadores do terminal aparecerão como quadrados vazios ou caracteres quebrados.

```bash
mkdir -p ~/.local/share/fonts/NerdFonts && cd /tmp \
  && curl -LO https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip \
  && unzip -o -q JetBrainsMono.zip 'JetBrainsMonoNerdFont-*.ttf' -d ~/.local/share/fonts/NerdFonts \
  && fc-cache -f
```

---

## 2. ⚡ Aplicando as Configurações

Depois de extrair este arquivo `.zip`, entre na pasta e execute o script de instalação:

```bash
cd ~/dotfiles   # ou o caminho onde descompactou
chmod +x install.sh
./install.sh
```

O script criará automaticamente os links em `~/.config/`, configurará o Starship no seu `~/.bashrc` e criará as pastas `~/Imagens/Wallpapers`, `~/Imagens/Screenshots` e `~/Vídeos/video_wallpaper`.

---

## 3. 🖥️ Ajuste de Monitores (MUITO IMPORTANTE!)

Como cada computador tem monitores e saídas de vídeo diferentes (`HDMI-A-1`, `DP-1`, `eDP-1`, etc.), você deve conferir os nomes das suas saídas:

1. Execute no terminal:
   ```bash
   hyprctl monitors
   ```
2. Veja o campo `Monitor ...` (ex: `HDMI-A-1`, `DP-1`, `eDP-1`).

### Se você tem 2 Monitores:
- Abra `~/.config/hypr/hyprland.conf`:
  - Nas linhas 26-29, ajuste os nomes dos monitores e resoluções/taxas de atualização para os seus:
    ```ini
    monitor=HDMI-A-1,1920x1080@60,0x0,1
    monitor=DP-1,1920x1080@60,1920x0,1
    ```
- Abra `~/.config/waybar/config`:
  - Na linha 6 (`waybar-side`): ajuste `"output": "SEU_MONITOR_1"`
  - Na linha 81 (`waybar-main`): ajuste `"output": "SEU_MONITOR_2"`

### Se você tem apenas 1 Monitor (ex: Notebook):
- Em `~/.config/hypr/hyprland.conf`:
  - Deixe a linha genérica ou o nome do seu monitor:
    ```ini
    monitor=,preferred,auto,1
    ```
- Em `~/.config/waybar/config`:
  - Se quiser apenas a barra horizontal superior, você pode apagar o bloco do `waybar-side` ou simplesmente ajustar o `"output"` de `waybar-main` para o seu monitor (ou remover o campo `"output"` para ela aparecer no monitor principal).

---

## 4. ⌨️ Guia de Atalhos (`SUPER` = Tecla Windows)

### Aplicativos e Janelas
| Atalho | Ação |
|---|---|
| `SUPER + Q` | Abrir Terminal (Kitty) |
| `SUPER + R` | Abrir Menu de Aplicativos (Wofi) |
| `SUPER + T` ou `SUPER + SHIFT + R` | Menu de Scripts Personalizados (`~/desktop/scripts` ou `~/scripts`) |
| `SUPER + E` | Abrir Gerenciador de Arquivos (Nautilus) |
| `SUPER + K` | Abrir Steam |
| `SUPER + C` | Fechar janela ativa |
| `SUPER + V` | Alternar janela flutuante (*floating*) / lado a lado (*tiled*) |
| `SUPER + G` | Maximizar janela (mantém gaps e waybar) |
| `SUPER + F` | Tela cheia total (*fullscreen*) |
| `SUPER + J` | Alternar divisão da tela (horizontal / vertical) |
| `SUPER + P` | Alternar modo pseudotile |
| `SUPER + Tab` | **Menu visual de janelas abertas (com títulos)** |
| `ALT + Tab` | **Alternar rapidamente entre janelas do workspace** |
| `SUPER + F1` ou `SUPER + H` | **Abrir / Fechar Menu Interativo de Atalhos (󰌌)** |
| `SUPER + N` | Painel de Notificações (SwayNC) |

### Navegação e Monitores
| Atalho | Ação |
|---|---|
| `SUPER + Setas` | Mover foco entre janelas abertas |
| `SUPER + SHIFT + Setas` | Mover posição física da janela na tela |
| `SUPER + Clique Esquerdo (arrastar)` | Mover qualquer janela livremente com o mouse |
| `SUPER + Clique Direito (arrastar)` | Redimensionar qualquer janela com o mouse |
| `SUPER + ALT + ← / →` | Mudar foco entre os monitores (HDMI-A-1 <-> DP-1) |
| `SUPER + SHIFT + ← / →` | Mover janela ativa para o outro monitor |
| `SUPER + X` | Alternar monitor da mesa digitalizadora (Wacom) |

### Áreas de Trabalho (Workspaces)
| Atalho | Ação |
|---|---|
| `SUPER + 1` até `0` | Workspaces 1 a 10 no Monitor Esquerdo (`HDMI-A-1`) |
| `SUPER + SHIFT + 1` até `0` | Mover janela para Workspaces 1 a 10 |
| `SUPER + Numpad 1` até `0` | Workspaces 11 a 20 no Monitor Direito (`DP-1`) |
| `SUPER + SHIFT + Numpad 1` até `0` | Mover janela para Workspaces 11 a 20 |
| `SUPER + [` / `]` | Workspace anterior / próximo no monitor atual |
| `SUPER + Scroll do Mouse` | Percorrer workspaces no monitor em foco |
| `SUPER + S` | Alternar workspace especial (*scratchpad*) |
| `SUPER + SHIFT + S` | Enviar janela para o *scratchpad* |

### Capturas de Tela (Screenshots)
| Atalho | Ação |
|---|---|
| `Print` ou `SUPER + SHIFT + P` | Selecionar região da tela com o mouse |
| `SHIFT + Print` | Capturar o monitor atual |
| `CTRL + Print` | Capturar a janela ativa |
| `SUPER + SHIFT + Print` | Seleção com o mouse (apenas área de transferência) |

*(Todas as capturas são salvas em `~/Imagens/Screenshots` e copiadas para a área de transferência)*

### Wallpapers e Multimídia
| Atalho | Ação |
|---|---|
| `SUPER + Y` | **Abrir / fechar YouTube Miniplayer flutuante ()** |
| `SUPER + W` | Abrir seletor visual de wallpapers (`hyprquickpaper`) |
| `SUPER + SHIFT + W` | Wallpaper anterior |
| `SUPER + ALT + W` | Wallpaper aleatório |
| `SUPER + O` | Menu de vídeo wallpaper para o monitor em foco |
| `SUPER + I` | Escolher vídeo de fundo da tela de bloqueio |
| `Teclas de Volume / Brilho` | Ajustam volume do som e brilho com feedback visual |

### Sessão e Energia
| Atalho | Ação |
|---|---|
| `SUPER + Esc` ou `SUPER + U` | Menu de Energia (Desligar, Reiniciar, Suspender, Bloquear, Sair) |
| `SUPER + L` | Bloquear a tela imediatamente (`hyprlock` com vídeo) |
| `SUPER + M` | Sair da sessão do Hyprland (Logout) |

---

## 5. 🖱️ Módulos Clicáveis da Waybar
- **Ícone de Teclado (󰌌)**: Clique para abrir/fechar o Menu Interativo de Atalhos pesquisável.
- **Ícone de Atualizações (󰚰 / 󰏖)**: Clique para abrir o atualizador do sistema no terminal.
- **Ícone de Bluetooth (󰂯)**: Clique para abrir o gerenciador gráfico de Bluetooth (`blueman-manager`).
- **Ícone de CPU (󰍛)**: Clique para abrir o monitor do sistema `btop`.
- **Ícone de Volume**: Clique com botão esquerdo para abrir o `pavucontrol`; botão direito muta/desmuta.
- **Ícone de Wallpaper (󰸉)**:
  - Clique esquerdo: Próximo wallpaper
  - Clique direito: Wallpaper anterior
  - Clique do meio: Wallpaper aleatório
  - Scroll do mouse: Percorre a lista
- **Ícone de Luz Noturna**: Clique para ligar/desligar filtro de luz azul; scroll ajusta a temperatura da cor.
- **Ícone de Rede (󰈀 Conectado / 󰤨)**: Clique para abrir as configurações de rede.
- **Ícone de Energia (󰐥)**: Clique para abrir o menu de desligar/reiniciar/suspender.

---

## 6. 📖 Dúvidas e Detalhes Técnicos
Para ver a documentação profunda com todos os detalhes da arquitetura, scripts auxiliares, compilação do `awww` (para animações de wallpaper), como gerar vídeos Matrix em Python e troubleshooting, consulte o arquivo **`GRIMORIO.md`**.
