# 🧙‍♂️ Grimório — Hyprland

Navegação, atalhos e notas técnicas da configuração.

> **SUPER** = tecla Windows do teclado.

## Sumário

- [Aplicativos e janelas](#1-aplicativos-e-janelas)
- [Movimento e foco](#2-movimento-e-foco-entre-janelas)
- [Workspaces](#3-workspaces-áreas-de-trabalho)
- [Multi-monitor](#4-multi-monitor)
- [Áudio e mídia](#5-áudio-e-mídia)
- [Screenshots](#6-screenshots)
- [Módulos clicáveis da Waybar](#7-módulos-clicáveis-da-waybar)
- [Wallpapers (hyprquickpaper)](#wallpapers-hyprquickpaper)
- [Notas técnicas / solução de problemas](#notas-técnicas--solução-de-problemas)
- [Terminal (kitty + starship)](#terminal-kitty--starship)
- [Tela de bloqueio e o vídeo de fundo](#tela-de-bloqueio-e-o-vídeo-de-fundo)
- [Repositório dotfiles](#repositório-dotfiles)
- [Transições animadas (awww)](#transições-animadas-awww)
- [Configuração dos monitores](#configuração-dos-monitores)

---

## 1. Aplicativos e janelas

| Atalho | Ação |
| --- | --- |
| `SUPER` + `Q` | Abrir o terminal (Kitty) |
| `SUPER` + `R` | Abrir o menu de aplicativos (Wofi) |
| `SUPER` + `E` | Abrir o gerenciador de arquivos (Nautilus) |
| `SUPER` + `C` | Fechar a janela ativa |
| `SUPER` + `V` | Alternar janela para modo flutuante (floating) |
| `SUPER` + `G` | Maximizar a janela em foco (mantém gaps e barra) |
| `SUPER` + `F` | Tela cheia real (fullscreen total sem gaps/barra) |
| `SUPER` + `N` | Abrir/fechar painel de notificações (SwayNC) |
| `SUPER` + `M` | Sair do Hyprland (logout) |
| `SUPER` + `P` | Alternar modo pseudo (layout dwindle) |
| `SUPER` + `J` | Alternar divisão da tela (split horizontal/vertical) |
| `SUPER` + `L` | Tela de bloqueio (vídeo de fundo + hyprlock) |
| `SUPER` + `I` | Escolher o vídeo de fundo do bloqueio |

## 2. Movimento e foco entre janelas

| Atalho | Ação |
| --- | --- |
| `SUPER` + Setas (← ↓ ↑ →) | Mover o foco para a janela na direção desejada |
| `SUPER` + Botão esquerdo + arrastar | Mover janela |
| `SUPER` + Botão direito + arrastar | Redimensionar janela |

## 3. Workspaces (áreas de trabalho)

| Atalho | Ação |
| --- | --- |
| `SUPER` + `1`–`9`, `0` | Ir para o workspace 1 a 10 |
| `SUPER` + `SHIFT` + `1`–`9`, `0` | Mover a janela ativa para o workspace 1 a 10 |
| `SUPER` + `S` | Alternar o workspace especial (scratchpad/oculto) |
| `SUPER` + `SHIFT` + `S` | Mover a janela ativa para o workspace especial |
| `SUPER` + Roda do mouse | Navegar sequencialmente pelos workspaces |
| `SUPER` + `[` / `]` | Workspace anterior/próximo do monitor atual |

## 4. Multi-monitor

| Atalho | Ação |
| --- | --- |
| `SUPER` + `ALT` + `←` / `→` | Mover o foco para o monitor da esquerda/direita |
| `SUPER` + `SHIFT` + `←` / `→` | Enviar a janela ativa para o outro monitor |

## 5. Áudio e mídia

| Atalho | Ação |
| --- | --- |
| Teclas de volume (Fn) | Aumentar / diminuir / mutar áudio (`wpctl`) |
| Tecla de mute do microfone | Muta a entrada padrão |
| Teclas de brilho (Fn) | Aumentar / diminuir brilho (`brightnessctl`) |
| Teclas de mídia (Play/Pause/Next/Prev) | Controle de mídia (`playerctl`) |

## 6. Screenshots

`grim` + `slurp` + `wl-clipboard`. Salvam em `~/Imagens/Screenshots` e já copiam para a área de transferência.

| Atalho | Ação |
| --- | --- |
| `Print` | Selecionar região com o mouse |
| `SHIFT` + `Print` | Capturar o monitor atual |
| `CTRL` + `Print` | Capturar a janela ativa |
| `SUPER` + `SHIFT` + `Print` | Região, só para a área de transferência |

## 7. Módulos clicáveis da Waybar

**Ícone de CPU (󰍛)** — abre o btop no primeiro workspace **vazio** do monitor daquela barra. Se o btop já estiver aberto, apenas pula para a janela existente.

- Script: `~/.config/hypr/scripts/btop.sh [MONITOR]`
- A janela usa a classe `btop` (`kitty --class btop`); é assim que o script a encontra.

**Ícone de wallpaper (󰸉)**

| Interação | Ação |
| --- | --- |
| Clique | Próximo |
| Clique direito | Anterior |
| Clique do meio | Aleatório |
| Scroll | Navega |

**Ícone de volume** — clique abre o `pavucontrol`; clique direito muta.

---

# Wallpapers (hyprquickpaper)

## 8. Atalhos

| Atalho | Ação |
| --- | --- |
| `SUPER` + `W` | Abrir o seletor visual de wallpapers |
| `SUPER` + `SHIFT` + `W` | Wallpaper anterior (todos os monitores) |
| `SUPER` + `ALT` + `W` | Wallpaper aleatório (todos os monitores) |

Dentro do seletor (`SUPER` + `W`):

| Tecla | Ação |
| --- | --- |
| `→` / `←` ou `J` / `K` | Navegar 1 imagem para a direita/esquerda |
| `↓` / `↑`, `PgDn` / `PgUp` ou `D` / `U` | Navegar 1 tela inteira de imagens |
| `Espaço` ou `Enter` | Aplicar o wallpaper selecionado |
| `Esc` | Sair sem aplicar |
| Scroll / clique e arrastar | Navegar (clique simples também seleciona) |

## 9. Comportamento por monitor (refatorado)

O seletor abre no monitor que está em foco, e o wallpaper escolhido é aplicado **somente nesse monitor** (antes ia para os dois).

Como funciona:

1. A keybind `SUPER` + `W` grava o monitor focado no instante da abertura numa variável de ambiente `HQP_MONITOR`:

   ```ini
   bind = $mainMod, W, exec, HQP_MONITOR="$(hyprctl activeworkspace -j \
          | jq -r .monitor)" quickshell -c hyprquickpaper
   ```

2. O `~/.config/quickshell/hyprquickpaper/commands.sh` lê essa variável e aplica só nela (com fallback para o monitor focado no momento):

   ```bash
   awww img -o "$MONITOR" "$IMAGEM" --resize crop --transition-type random
   ```

Ou seja: o wallpaper vai para o monitor onde você **abriu** o seletor, mesmo que o mouse passeie para a outra tela antes de você apertar `Enter`.

Já o `SUPER` + `SHIFT` + `W` / `ALT` + `W` usam o `wallpaper.sh`, que continua mexendo nos dois monitores de uma vez (com `MONITOR_OFFSET=1`, cada tela pega uma imagem diferente da lista).

## 10. Arquivos envolvidos

O `~/.config/quickshell/hyprquickpaper/` é um **clone do upstream** (tem `.git` próprio). Só os dois arquivos customizados são versionados no repo dotfiles e symlinkados por cima do clone — veja [Repositório dotfiles](#repositório-dotfiles).

| Caminho | Papel |
| --- | --- |
| `~/Imagens/Wallpapers/` | Pasta das imagens |
| `~/.cache/quickshell/thumbs/` | Miniaturas geradas |
| `~/.config/quickshell/hyprquickpaper/config.json` | Caminhos, nº de imagens na tela, cor da borda, batch (**symlink → dotfiles**) |
| `~/.config/quickshell/hyprquickpaper/commands.sh` | O que rodar ao selecionar, aplica no monitor certo (**symlink → dotfiles**) |
| `~/.config/quickshell/hyprquickpaper/cache.sh` | Gera as miniaturas com ImageMagick |
| `~/.config/quickshell/hyprquickpaper/shell.qml` | A interface — **editado no clone** para aceitar as setas do teclado (não versionado nos dotfiles) |
| `~/.config/hypr/scripts/wallpaper.sh` | Troca sequencial/aleatória |
| `~/.config/hypr/hyprpaper.conf` | Wallpaper inicial do boot — **só no fallback**, o awww ignora |
| `~/.local/state/hypr/wallpaper-index` | Índice do wallpaper atual |

---

# Notas técnicas / solução de problemas

## 11. Dependências do hyprquickpaper (Ubuntu 26.04)

Sem estes dois pacotes o seletor não funciona:

```bash
sudo apt install qml6-module-qt-labs-folderlistmodel imagemagick
```

- **`qml6-module-qt-labs-folderlistmodel`** — o `shell.qml` importa `Qt.labs.folderlistmodel`. Sem ele o quickshell nem carrega a config e `SUPER` + `W` não abre nada. Erro típico:

  ```
  ERROR: module "Qt.labs.folderlistmodel" is not installed
  ```

- **`imagemagick`** — o `cache.sh` usa o comando `convert` para gerar as miniaturas. Sem ele todas as imagens ficam presas no texto "Caching" para sempre.

**Diagnóstico:** rode `quickshell -c hyprquickpaper` no terminal para ver o erro real; a keybind engole a saída.

## 12. O IPC do hyprpaper mudou (hyprpaper 0.8+ / Hyprland 0.53+)

> Só vale para o **fallback**: o backend padrão hoje é o awww. Veja [Transições animadas](#transições-animadas-awww).

O IPC virou protocolo "wire". O **único** request aceito hoje é `wallpaper`:

```bash
hyprctl hyprpaper wallpaper "MONITOR,/caminho/imagem.png,MODO"
```

- `preload`, `unload`, `listactive` e `listloaded` **não existem mais**. Se aparecer `error: Unknown hyprpaper request`, é isso — o próprio `wallpaper` já carrega a imagem sozinho.
- `MONITOR` vazio (`""`) aplica em **todos** os monitores.
- `MODO` aceito: `cover` (padrão), `contain`, `fit`/`stretch`, `tile`.
- Sucesso = saída vazia e código de retorno 0.

## 13. Conflitos de keybind (resolvidos)

Os atalhos foram ajustados para evitar sobreposições:

| Tecla | Função dedicada |
| --- | --- |
| `SUPER` + `N` | `swaync-client` (painel de notificações) exclusivo |
| `SUPER` + `SHIFT` + `S` | Mover janela para o workspace especial (Scratchpad) exclusivo |
| `Print` (PrtScn) | Captura de tela (`Print` = região, `Shift+Print` = tela, `Ctrl+Print` = janela) |
| `SUPER` + `G` | Maximizar janela em foco (mantém gaps e barra; `SUPER` + `F` para fullscreen total) |

Conferir com:

```bash
hyprctl binds -j | jq -r '.[] | "\(.modmask) \(.key) \(.arg)"'
```

## 14. Limitação conhecida: escolha por monitor não sobrevive ao reboot (wallpapers)

O `wallpaper.sh` guarda um índice global único (`wallpaper-index`) e no boot o `restore` recalcula as telas com `MONITOR_OFFSET=1`. Então wallpapers escolhidos individualmente por monitor voltam trocados/diferentes depois de reiniciar.

**Correção pendente:** estado por monitor em vez de índice único.

## 14.1. Bug corrigido: botão de luz noturna parava de responder

O waybar chama `nightlight.sh` de novo a cada tick de scroll — rolar rápido dispara vários processos do script em paralelo. Cada um mandava `stop()` (`pkill -x wlsunset`, que só envia o sinal e **não espera** o processo morrer) e já subia um `wlsunset` novo. Por um instante existiam **dois `wlsunset` vivos** disputando o controle de gama da mesma saída — o protocolo `wlr-gamma-control` só permite um cliente por saída (`hyprctl`/wlroots). O perdedor recebe `gamma control of output X failed`, mas continua rodando: o `pgrep -x wlsunset` ainda o via como "ligado", então clicar ou rolar o scroll de novo não adiantava — o botão parecia morto até o próximo reboot ou `pkill -x wlsunset` manual.

Correção: uma trava (`flock`) serializa as chamadas do script, e `stop()` agora espera (`pgrep` em loop, até 1s) o processo antigo morrer de verdade antes de qualquer `start()` subir um novo — nunca mais dois `wlsunset` disputando a mesma saída. **Cuidado ao tocar nesse script:** o `wlsunset` sobe em background e sobrevive ao script; se ele herdar o file descriptor da trava (`9`), o lock nunca é liberado e trava todas as chamadas futuras — por isso o `setsid wlsunset ... 9>&- &` fecha o fd explicitamente no filho.

---

# Terminal (kitty + starship)

## 15. Kitty

Arquivo: `~/.config/kitty/kitty.conf` (**symlink → dotfiles**), tema em `current-theme.conf`.

| Ajuste | Valor | Por quê |
| --- | --- | --- |
| `font_family` | `JetBrainsMono Nerd Font` | Era `monospace` (= DejaVu Sans Mono), que **não tem** os separadores powerline nem os ícones — o prompt do starship sairia todo em tofu (▯) |
| `font_size` | `11.0` | |
| Tema | Catppuccin Mocha (`include current-theme.conf`) | Mesma paleta do prompt |
| `background_opacity` | `0.40` (+ `dynamic_background_opacity yes`) | Transparência ajustável em runtime |
| `shell` | `/bin/bash` explícito | Sem isso o kitty segue `$SHELL`, que ficava apontando para um `/usr/bin/zsh` inexistente até o próximo login |
| `window_padding_width` | `8` | |

Recarregar a config sem fechar o terminal: **`Ctrl + Shift + F5`**.

## 16. Starship (prompt)

Config: `~/.config/starship.toml` (**symlink → dotfiles**).
Baseada na do [typecraft-dev/dotfiles](https://github.com/typecraft-dev/dotfiles/blob/master/starship/.config/starship.toml), paleta `catppuccin_mocha`.

Inicialização, no fim do `~/.bashrc`:

```bash
eval "$(starship init bash)"
```

O prompt mostra, em segmentos powerline: SO → usuário → diretório → git (branch + status) → linguagem detectada (c, rust, go, node, php, java, kotlin, haskell, python) → docker context → hora, e o `❯` na linha de baixo.

**Três desvios do upstream** (todos intencionais):

1. `vimcmd_symbol` tinha `fg:creen` — typo de `green`, cor inválida.
2. `[docker_context]` usa `bg:color_bg3`, que só existe na paleta `gruvbox_dark`; como a paleta ativa é `catppuccin_mocha`, a cor não resolvia. Foi adicionado `color_bg3 = "#585b70"` (o `surface2`) ao mocha, em vez de reescrever o formato.
3. `[directory.substitutions]` ganhou os nomes de pasta em português (Documentos, Imagens, Música, Vídeos, Área de trabalho) — as originais eram só em inglês.

**Requer Nerd Font**, igual à waybar. Sem ela os separadores `` e os ícones somem.

Diagnóstico do prompt:

```bash
starship timings          # quanto cada módulo custa e o que ele renderiza
starship explain          # por que cada segmento apareceu
starship prompt           # imprime o prompt uma vez, com erros no stderr
```

> **Atenção ao copiar configs de starship da web:** os separadores e ícones vivem na Private Use Area do Unicode (`U+E0B0`, `U+E718`, …). Muito visualizador/proxy de texto os remove silenciosamente — a config "funciona" e sai sem desenho nenhum. Baixe com `curl` direto do `raw.githubusercontent.com` e confira:
>
> ```bash
> python3 -c "d=open('starship.toml',encoding='utf-8').read(); print(sum(1 for c in d if 0xE000<=ord(c)<=0xF8FF))"
> ```

---

# Tela de bloqueio e o vídeo de fundo

## 17. Como funciona

`SUPER + L` chama `~/.config/hypr/scripts/lock.sh`, que põe um vídeo como fundo (via `mpvpaper`) e abre o `hyprlock` por cima.

| Caminho | Papel |
| --- | --- |
| `~/.config/hypr/scripts/lock.sh` | Orquestra mpvpaper + hyprlock |
| `~/.config/hypr/scripts/lockvideo.sh` | Menu de escolha do vídeo (`SUPER + I`) |
| `~/.config/hypr/hyprlock.conf` | Layout da tela de bloqueio |
| `~/Vídeos/video_wallpaper/` | Os vídeos disponíveis (não versionados) |
| `~/.local/state/hypr/lock-video` | Qual vídeo está escolhido |

O **blur está assado no vídeo** (`--blur`), não aplicado ao vivo: filtrar no player custaria CPU todo quadro, com a tela bloqueada.

## 17.1. Escolhendo o vídeo (`SUPER + I`)

O `lock.sh` não tem mais caminho fixo de vídeo: ele pergunta ao `lockvideo.sh` (`lockvideo.sh path`) qual usar. O menu é um `wofi --dmenu` que lista todo `.mp4`/`.mkv`/`.webm`/`.mov`/`.avi` de `~/Vídeos/video_wallpaper`, marcando o atual com `●`, mais duas entradas:

| Entrada | Efeito |
| --- | --- |
| `Sem vídeo (fundo opaco)` | Grava `off` no estado; o bloqueio passa a usar o screenshot desfocado |
| `Prévia…` | Submenu: roda o vídeo escolhido na camada `overlay` por 6s, sem salvar nada |

A escolha vive em `~/.local/state/hypr/lock-video` (só o nome do arquivo, ou `off`), então sobrevive a reboot e não exige editar config nenhuma. Estado apontando para arquivo apagado **não** trava o bloqueio: cai no `matrix-rain.mp4`, e se ele não existir, no primeiro vídeo da pasta.

Na linha de comando:

```bash
lockvideo.sh list                  # o que a pasta tem
lockvideo.sh current               # nome do vídeo em uso (ou "off")
lockvideo.sh path                  # caminho absoluto; sai 1 se não há vídeo
lockvideo.sh set matrix-rain.mp4   # escolhe sem abrir menu
lockvideo.sh preview <arquivo>     # prévia (PREVIEW_SECS ajusta a duração)
lockvideo.sh off                   # desliga o vídeo
```

Variáveis: `LOCK_VIDEO_DIR` muda a pasta, `PREVIEW_SECS` a duração da prévia, e `MATRIX_VIDEO` ainda sobrescreve o vídeo no `lock.sh` para teste pontual.

**A prévia não roda** com a tela já bloqueada nem se houver outro `mpvpaper` no ar — ela termina com `pkill -x mpvpaper`, que seria dano colateral no processo alheio.

Quando o vídeo está desligado de propósito, o bloqueio cai no fundo opaco **calado**; a notificação de aviso só aparece quando o vídeo deveria estar lá e não subiu.

## 18. Gerando e pré-visualizando o vídeo

Os fontes ficam em `~/Área de trabalho/video-matrix-studio/`:

| Arquivo | Papel |
| --- | --- |
| `matrix_engine.py` | A engine: fontes, cache de glifos, colunas, geração dos quadros |
| `make-matrix-video.py` | Manda os quadros pro ffmpeg e grava o `.mp4` |
| `preview-matrix.py` | Mostra o resultado em loop, ao vivo, sem gravar nada |

```bash
cd ~/"Área de trabalho"/video-matrix-studio
./preview-matrix.py                          # 1080p numa janela 960x540
./preview-matrix.py --font-size 16 --blur 4  # testando parâmetros
./make-matrix-video.py                       # assa o vídeo final
```

O destino padrão do `make-matrix-video.py` (nas duas cópias, studio e dotfiles) é `~/Vídeos/video_wallpaper/matrix-rain.mp4` — a mesma pasta que o menu do `SUPER + I` lista, então o vídeo recém-assado já aparece entre as opções. Use `-o` para gravar em outro lugar.

O preview manda quadros rgb24 crus direto pro `ffplay` pelo pipe; o player é que impõe o ritmo (não há `sleep`). Ao sair (`q` ou `Ctrl+C`) ele imprime o comando `make-matrix-video.py` equivalente aos parâmetros que você estava testando.

**O loop é exato:** a velocidade de cada coluna é escolhida para completar um número inteiro de ciclos no total de quadros, então o último quadro emenda no primeiro sem salto.

**A fonte precisa ter katakana.** JetBrains Mono e DejaVu não têm CJK e renderizariam tofu silenciosamente; por isso a engine testa a fonte antes de usar (compara o glifo de `ア` com um codepoint garantidamente ausente) e exige `fonts-noto-cjk`.

> A cópia em `~/.config/hypr/scripts/make-matrix-video.py` é a **versão antiga monolítica**, ainda no repo dotfiles. Funciona sozinha, mas está divergindo do studio. Se sincronizar a nova para lá, leve o `matrix_engine.py` junto, senão o import quebra.

Requer: `python3-pil`, `ffmpeg` (o preview usa `ffplay`, ou `mpv` com `--player mpv`).

---

# Repositório dotfiles

## 19. O que é versionado

Repo em `~/dotfiles` (`github.com/ericodex/dotfiles`). Ele **não copia** as configs: `~/.config/...` são symlinks apontando para dentro do repo, então editar o arquivo do dia a dia já é editar o repo.

| Symlink | Alvo no repo |
| --- | --- |
| `~/.config/hypr` | `.config/hypr` (dir) |
| `~/.config/waybar` | `.config/waybar` (dir) |
| `~/.config/kitty` | `.config/kitty` (dir) |
| `~/.config/starship.toml` | `.config/starship.toml` (arquivo) |
| `~/.config/quickshell/hyprquickpaper/{config.json,commands.sh}` | idem (**só esses dois arquivos**) |

O hyprquickpaper é a exceção porque é um clone do upstream com `.git` próprio — um repo dentro do outro viraria submódulo. Só os dois arquivos customizados entram, symlinkados por cima do clone. Efeito colateral esperado: `git status` **dentro do clone** mostra os dois como `typechange`.

Fora do repo de propósito: wallpapers e screenshots (grandes e pessoais), os vídeos de `~/Vídeos/video_wallpaper` e o estado em `~/.local/state/hypr/` (`wallpaper-index`, `lock-video`, `nightlight-temp`).

## 20. Instalando em outra máquina

```sh
git clone https://github.com/ericodex/dotfiles.git ~/dotfiles
cd ~/dotfiles && ./install.sh
```

O `install.sh` é idempotente: cria os symlinks (com backup `.bak-<timestamp>` do que já existia), clona o hyprquickpaper se faltar, adiciona o `starship init` ao `~/.bashrc` se ainda não estiver lá, checa as dependências e valida a Nerd Font.

Depois de clonar, ajuste os nomes dos monitores em `hyprland.conf` e o campo `output` no `waybar/config`.

---

# Transições animadas (awww)

## 21. Por que trocar o hyprpaper

O hyprpaper **não tem transição**: a troca de wallpaper é corte seco. Quem faz a animação é o `awww` — *An Answer to your Wayland Wallpaper Woes*, o antigo **`swww`**.

Atenção ao histórico do projeto, porque quase toda receita na internet está desatualizada:

- O repo `LGFae/swww` no GitHub está **arquivado** desde out/2025.
- O projeto virou **`awww`** e mudou para o Codeberg: <https://codeberg.org/LGFae/awww>.
- São **dois binários**: `awww` (cliente) e `awww-daemon`. Ambos precisam estar no PATH.
- O cache mudou de lugar (`$XDG_CACHE_HOME/awww/$VERSÃO`), e `awww init` está deprecado — use `awww-daemon`.

## 22. Instalação (compilando do fonte)

Não existe pacote no Ubuntu 26.04 e os releases do Codeberg **não publicam binários**, então é compilar. MSRV: rustc 1.87+.

```bash
sudo apt install cargo liblz4-dev libwayland-dev wayland-protocols
git clone --branch v0.12.1 https://codeberg.org/LGFae/awww ~/opt/awww
cd ~/opt/awww && cargo build --release
install -m755 target/release/awww target/release/awww-daemon ~/.local/bin/
```

> Sem `sudo` à mão, dá para instalar o toolchain só no seu usuário:
> `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal`
> (foi assim que esta máquina foi montada; o `rustc` fica em `~/.cargo/bin`).

**Atualizar** = `cd ~/opt/awww && git fetch --tags && git checkout <tag> && cargo build --release` e reinstalar os dois binários. Este é o preço de não haver pacote.

## 23. Como está configurado aqui

| Peça | Papel |
| --- | --- |
| `exec-once` do `hyprland.conf` | Sobe `awww-daemon`, ou `hyprpaper` se o awww não existir |
| `wallpaper.sh` | Detecta o backend, garante o daemon e aplica com transição |
| `hyprquickpaper/commands.sh` | Mesma coisa, no caminho do seletor (`SUPER + W`) |

Transição padrão: **`random`** — sorteia um efeito a cada troca. Ajuste por variável de ambiente, sem editar script:

```bash
TRANSITION=wipe TRANSITION_DURATION=0.6 ~/.config/hypr/scripts/wallpaper.sh next
```

| Variável | Padrão | O que faz |
| --- | --- | --- |
| `TRANSITION` | `random` | `none simple fade left right top bottom center outer any random wipe wave grow` |
| `TRANSITION_DURATION` | `1.2` | Segundos |
| `TRANSITION_FPS` | `60` | Quadros por segundo da animação |
| `TRANSITION_POS` | `0.9,0.9` | Origem dos efeitos radiais (`grow`, `outer`, `center`) |
| `FIT_MODE` | `cover` | Traduzido para o `--resize` do awww (`cover`→`crop`, `contain`→`fit`) |

Dois detalhes que o script resolve e que costumam morder quem migra:

1. **O awww é cliente puro.** Sem o daemon no ar, todo `awww img` falha. O `wallpaper.sh` chama `awww query` e sobe o daemon se preciso — por isso o `exec-once` do restore não precisa mais do `sleep 2` arbitrário que existia para esperar o hyprpaper.
2. **Falha silenciosa.** A versão anterior mandava `2>/dev/null` na chamada do backend: se a troca falhasse, nada aparecia. Agora o erro sobe e vira `notify-send`.

## 24. Limitação: monitor reconectado perde o wallpaper

O autor do awww **removeu de propósito** o cache que restaurava a imagem quando um monitor volta (religado, ou cabo reconectado). O hyprpaper não tinha esse problema.

Contorno manual:

```bash
~/.config/hypr/scripts/wallpaper.sh restore
```

Para automatizar, precisa de algo que reaja ao evento de output novo — `kanshi`, ou um listener no socket2 do Hyprland (`monitoradded`). Ainda não implementado aqui.

## 25. Diagnóstico

```bash
awww query                  # o que cada saída está exibindo agora
pgrep -a awww-daemon        # o daemon está no ar?
awww kill                   # derruba o daemon
awww img --help             # todos os flags de transição
```

- O socket fica em `$XDG_RUNTIME_DIR/${WAYLAND_DISPLAY}-awww-daemon.sock`.
- Na primeira execução aparece `failed to open cache dir` — é só o `~/.cache/awww` ainda não existir; ele é criado em seguida.
- Não funciona em compositor sem `wlr-layer-shell` (Gnome, por exemplo). Hyprland implementa.
- Gif grande consome CPU na fase de cache. Redimensione antes (`gifsicle`) se incomodar.

---

# Configuração dos monitores

| Monitor | Saída | Posição | Taxa |
| --- | --- | --- | --- |
| Esquerdo (LG UltraGear) | `HDMI-A-1` | `0x0` | 120 Hz |
| Direito (Samsung Odyssey) | `DP-1` | `1920x0` | 144 Hz |

- Workspaces 1–5 → `HDMI-A-1` (padrão: 1)
- Workspaces 6–10 → `DP-1` (padrão: 6)

Descobrir nomes/estado dos monitores:

```bash
hyprctl monitors -j | jq -r '.[] | "\(.name) focado=\(.focused)"'
```
