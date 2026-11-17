# dotfiles — Hyprland + Waybar

Configuração de desktop Hyprland com tema "Matrix" (ciano/esmeralda), setup de
dois monitores com workspaces independentes e duas waybars de estilos distintos.

O [**GRIMORIO.md**](GRIMORIO.md) é o manual completo: todos os atalhos, o
funcionamento de cada peça e as notas de solução de problemas.

## Estrutura

```
GRIMORIO.md                # manual: atalhos, funcionamento e troubleshooting
.config/
├── hypr/
│   ├── hyprland.conf      # compositor: monitores, workspaces, binds, animações
│   ├── hyprlock.conf      # tela de bloqueio
│   ├── hyprpaper.conf     # wallpaper inicial — só no fallback (o awww ignora)
│   └── scripts/
│       ├── btop.sh        # abre o btop no primeiro workspace vazio do monitor
│       ├── lock.sh        # bloqueio com vídeo de fundo (mpvpaper + hyprlock)
│       ├── lockvideo.sh   # menu do vídeo de fundo do bloqueio (Super + I)
│       ├── make-matrix-video.py  # gera o vídeo do digital rain
│       ├── screenshot.sh  # capturas via grim/slurp
│       └── wallpaper.sh   # alternador de wallpapers
├── kitty/
│   ├── kitty.conf         # JetBrainsMono Nerd Font, transparência, tema
│   └── current-theme.conf # Catppuccin Mocha
├── quickshell/
│   └── hyprquickpaper/    # SÓ os 2 arquivos customizados (veja abaixo)
│       ├── commands.sh    # aplica o wallpaper no monitor onde o seletor abriu
│       └── config.json    # caminhos, grid, cor da borda
├── starship.toml          # prompt (paleta Catppuccin Mocha)
└── waybar/
    ├── config             # duas barras: vertical + horizontal
    └── style.css          # tema Matrix com animações CSS
```

As configs **não são copiadas**: `~/.config/...` vira symlink para dentro deste
repo, então editar o arquivo do dia a dia já é editar o repo.

O `hyprquickpaper` é a exceção. Ele é um clone do
[upstream](https://github.com/iamsurjog/hyprquickpaper) com `.git` próprio — um
repo dentro do outro viraria submódulo. Por isso só os dois arquivos
customizados entram aqui, symlinkados por cima do clone; o `install.sh` clona o
upstream se ele não existir. Efeito colateral esperado: o `git status` **dentro
do clone** mostra esses dois arquivos como `typechange`.

## Instalação

```sh
git clone <url-deste-repo> ~/dotfiles
cd ~/dotfiles
./install.sh
```

O `install.sh` é idempotente: cria os symlinks em `~/.config` (com backup
`.bak-<timestamp>` do que já existia), clona o hyprquickpaper se faltar,
adiciona o `starship init` ao `~/.bashrc` se ainda não estiver lá, checa
dependências e valida a Nerd Font.

## Dependências

| Pacote | Para quê |
| --- | --- |
| `hyprland`, `waybar`, `hyprpaper` | base |
| `grim`, `slurp`, `wl-clipboard` | screenshots |
| `jq`, `libnotify-bin` | scripts e notificações |
| JetBrainsMono Nerd Font | ícones da waybar **e separadores do prompt** |
| `wofi`, `swaync`, `kitty`, `nautilus` | launcher, notificações, terminal, arquivos |
| `starship` | prompt |
| `quickshell`, `qml6-module-qt-labs-folderlistmodel`, `imagemagick` | seletor de wallpapers |
| `mpvpaper`, `hyprlock` | tela de bloqueio com vídeo de fundo |
| [`awww`](https://codeberg.org/LGFae/awww) | wallpaper com transição animada (compilado do fonte) |
| `python3-pil`, `ffmpeg` | gerar o vídeo do digital rain |

```sh
sudo apt install grim slurp wl-clipboard jq libnotify-bin kitty \
  qml6-module-qt-labs-folderlistmodel imagemagick python3-pil ffmpeg
curl -sS https://starship.rs/install.sh | sh
```

A Nerd Font **não existe nos repositórios do Ubuntu** — sem ela os ícones da
waybar viram quadrados vazios e o prompt do starship sai em tofu. O
`install.sh` mostra o comando de instalação.

## Monitores

Cada monitor tem seu **grupo independente de workspaces**, então nenhum "rouba"
a tela do outro:

| Monitor | Papel | Workspaces | Waybar |
| --- | --- | --- | --- |
| `HDMI-A-1` | maior (LG UltraGear) | 1–5 | vertical, à esquerda, esmeralda |
| `DP-1` | menor (Samsung Odyssey) | 6–10 | horizontal, no topo, ciano |

Ao clonar em outra máquina, ajuste os nomes dos monitores em `hyprland.conf`
(veja `hyprctl monitors`) e o campo `output` em `waybar/config`.

## Atalhos

`$mainMod` = tecla Super.

### Janelas e apps
| Atalho | Ação |
| --- | --- |
| `Super + Q` | terminal (kitty) |
| `Super + R` | launcher (wofi) |
| `Super + E` | gerenciador de arquivos |
| `Super + C` | fechar janela |
| `Super + V` | flutuar janela |
| `Super + G` | maximizar janela (mantém gaps e barra) |
| `Super + F` | tela cheia real (fullscreen total) |
| `Super + N` | painel de notificações (swaync) |
| `Super + M` | sair / desligar |
| `Super + L` | tela de bloqueio (vídeo de fundo + hyprlock) |
| `Super + I` | escolher o vídeo de fundo do bloqueio |
| `Super + Y` | abrir / fechar YouTube Miniplayer |
| `Super + P` | modo pseudo (dwindle) |
| `Super + J` | alternar divisão da tela |

### Navegação
| Atalho | Ação |
| --- | --- |
| `Super + setas` | mover foco |
| `Super + Alt + ←/→` | focar outro monitor |
| `Super + Shift + ←/→` | enviar janela para o outro monitor |
| `Super + 1..0` | ir para workspace |
| `Super + Shift + 1..0` | mover janela para workspace |
| `Super + [` / `]` | workspace anterior/próximo **do monitor atual** |
| `Super + scroll` | idem, com a roda do mouse |
| `Super + S` | scratchpad |

### Screenshots
| Atalho | Ação |
| --- | --- |
| `Print` | seleção com o mouse |
| `Shift + Print` | monitor atual |
| `Ctrl + Print` | janela ativa |
| `Super + Shift + Print` | seleção só para o clipboard |

Salvos em `~/Imagens/Screenshots` **e** copiados para o clipboard.

### Wallpapers
| Atalho | Ação |
| --- | --- |
| `Super + W` | abrir o **seletor visual** (hyprquickpaper) |
| `Super + Shift + W` | anterior |
| `Super + Alt + W` | aleatório |

O seletor aplica a imagem **só no monitor onde foi aberto**; os outros três
atalhos mudam os dois monitores de uma vez. Detalhes no
[GRIMORIO.md](GRIMORIO.md#9-comportamento-por-monitor-refatorado).

Também há um botão `󰸉` nas duas waybars: clique = próximo, direito = anterior,
meio = aleatório, scroll = percorre.

## Wallpapers

Não são versionados (grandes e pessoais). Coloque imagens em
`~/Imagens/Wallpapers` e o `wallpaper.sh` acha todas automaticamente
(`png`, `jpg`, `jpeg`, `webp`, `bmp`, `gif`).

Cada monitor recebe um wallpaper diferente. Para todos iguais, mude
`MONITOR_OFFSET=1` para `0` em `scripts/wallpaper.sh`.

O backend padrão é o [`awww`](https://codeberg.org/LGFae/awww) (antigo `swww`),
que dá **transição animada** na troca — o `hyprpaper` só faz corte seco. O
`wallpaper.sh` detecta qual dos dois está instalado e se adapta; se o awww não
existir, tudo continua funcionando sem animação.

A transição padrão é `random` (sorteia um efeito a cada troca) e é ajustável por
variável de ambiente:

```sh
TRANSITION=wipe TRANSITION_DURATION=0.6 ~/.config/hypr/scripts/wallpaper.sh next
```

O awww **não está empacotado no Ubuntu** e o projeto não publica binários, então
precisa ser compilado — o `install.sh` mostra os comandos, e o
[GRIMORIO.md](GRIMORIO.md#transições-animadas-awww) detalha o processo, as
variáveis e a limitação de monitor reconectado.

## Tela de bloqueio

`Super + L` bloqueia com um vídeo rodando no fundo (`mpvpaper` na camada
`overlay` + `hyprlock` transparente por cima). `Super + I` abre o menu que
escolhe esse vídeo entre os arquivos de `~/Vídeos/video_wallpaper` — os vídeos
**não são versionados** (grandes e pessoais), igual aos wallpapers.

O menu também permite desativar o vídeo (o bloqueio passa a usar um screenshot
desfocado) e pré-visualizar antes de escolher. A escolha fica em
`~/.local/state/hypr/lock-video`. Detalhes em
[GRIMORIO.md](GRIMORIO.md#171-escolhendo-o-vídeo-super--i).

## Notas

- A borda da janela focada é um gradiente que **gira continuamente**
  (`animation = borderangle, 1, 60, linear, loop`). Isso mantém a GPU
  repintando e desativa a economia de energia por VFR. Para desligar, troque o
  primeiro `1` por `0`.
- As janelas são 100% opacas de propósito (legibilidade em editor e terminal);
  o blur só afeta as barras e menus, via `layerrule`.
- O namespace da camada da waybar é o campo `name` de cada barra
  (`waybar-side`, `waybar-main`) — é por isso que as `layerrule` casam com
  `^waybar-.*` e o CSS usa `window#waybar.waybar-side`.
