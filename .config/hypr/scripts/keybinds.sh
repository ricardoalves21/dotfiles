#!/usr/bin/env bash
# Menu interativo de atalhos do Hyprland (lê todos os binds ativos via hyprctl).
#
# Uso: keybinds.sh [menu|toggle|list|json]
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
PID_FILE="$STATE_DIR/keybinds-menu.pid"
ROFI_THEME="$HOME/.config/rofi/keybinds.rasi"

mkdir -p "$STATE_DIR"

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

MODE="${1:-menu}"

if [ "$MODE" = "toggle" ]; then
    if is_menu_open; then
        close_menu
        exit 0
    fi
    MODE="menu"
elif [ "$MODE" = "menu" ]; then
    if is_menu_open; then
        close_menu
    fi
fi

exec python3 - "$MODE" "$PID_FILE" "$ROFI_THEME" <<'PYEOF'
import html
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

MODE = sys.argv[1]
PID_FILE = Path(sys.argv[2])
ROFI_THEME = Path(sys.argv[3])
HYPR_CONF = Path.home() / ".config/hypr/hyprland.conf"

MOD_BITS = [
    (64, "SUPER"),
    (4, "CTRL"),
    (8, "ALT"),
    (1, "SHIFT"),
    (2, "CAPS"),
    (128, "ALTGR"),
]

KEYCODE_NAMES = {
    79: "Numpad 7",
    80: "Numpad 8",
    81: "Numpad 9",
    82: "Numpad -",
    83: "Numpad 4",
    84: "Numpad 5",
    85: "Numpad 6",
    86: "Numpad +",
    87: "Numpad 1",
    88: "Numpad 2",
    89: "Numpad 3",
    90: "Numpad 0",
    91: "Numpad .",
    63: "Numpad *",
    104: "Numpad Enter",
    106: "Numpad /",
}

KEY_NAMES = {
    "left": "←",
    "right": "→",
    "up": "↑",
    "down": "↓",
    "bracketleft": "[",
    "bracketright": "]",
    "return": "Enter",
    "kp_enter": "Numpad Enter",
    "space": "Espaço",
    "escape": "Esc",
    "backspace": "Backspace",
    "delete": "Delete",
    "tab": "Tab",
    "print": "Print",
    "slash": "/",
    "backslash": "\\",
    "period": ".",
    "comma": ",",
    "minus": "-",
    "equal": "=",
    "grave": "`",
    "semicolon": ";",
    "apostrophe": "'",
    "mouse:272": "Clique Esq",
    "mouse:273": "Clique Dir",
    "mouse:274": "Clique Meio",
    "mouse:275": "Mouse Lateral 1",
    "mouse:276": "Mouse Lateral 2",
    "mouse_up": "Scroll ↑",
    "mouse_down": "Scroll ↓",
    "mouse_left": "Scroll ←",
    "mouse_right": "Scroll →",
    "xf86audioraisevolume": "Volume +",
    "xf86audiolowervolume": "Volume -",
    "xf86audiomute": "Mute Áudio",
    "xf86audiomicmute": "Mute Mic",
    "xf86monbrightnessup": "Brilho +",
    "xf86monbrightnessdown": "Brilho -",
    "xf86audionext": "Mídia Próx",
    "xf86audioprev": "Mídia Ant",
    "xf86audioplay": "Mídia Play",
    "xf86audiopause": "Mídia Pause",
    "xf86audiostop": "Mídia Stop",
}

CATEGORIES = {
    "apps":      (1, "󰀻", "Apps",      "#89b4fa"),
    "janelas":   (2, "󰖯", "Janelas",   "#cba6f7"),
    "monitores": (3, "󰍹", "Monitores", "#94e2d5"),
    "wallpaper": (4, "󰸉", "Wallpaper", "#a6e3a1"),
    "captura":   (5, "󰄀", "Captura",   "#f9e2af"),
    "sessao":    (6, "󰌾", "Sessão",    "#f38ba8"),
    "midia":     (7, "󰕾", "Mídia",     "#fab387"),
    "workspace": (8, "󰓩", "Workspace", "#74c7ec"),
}

DIR_NAMES = {
    "l": "à esquerda",
    "r": "à direita",
    "u": "acima",
    "d": "abaixo",
}


def run_json(cmd: list[str]):
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=3, check=True)
        return json.loads(res.stdout)
    except Exception:
        return []


def parse_inline_comments(conf_path: Path) -> dict[tuple[str, str], str]:
    """Lê comentários inline úteis das linhas bind = ... do hyprland.conf."""
    comments: dict[tuple[str, str], str] = {}
    variables: dict[str, str] = {}
    visited: set[Path] = set()

    def expand_vars(text: str) -> str:
        out = text
        for k, v in sorted(variables.items(), key=lambda item: -len(item[0])):
            out = out.replace(k, v)
        return out

    def visit(path: Path):
        try:
            real = path.expanduser().resolve()
        except Exception:
            return
        if real in visited or not real.is_file():
            return
        visited.add(real)

        for raw in real.read_text(encoding="utf-8", errors="ignore").splitlines():
            stripped = raw.strip()
            if not stripped or stripped.startswith("#"):
                continue
            m_var = re.match(r"^(\$[A-Za-z0-9_]+)\s*=\s*(.+?)(?:\s+#.*)?$", stripped)
            if m_var:
                variables[m_var.group(1)] = expand_vars(m_var.group(2).strip())
                continue
            m_src = re.match(r"^source\s*=\s*(.+?)(?:\s+#.*)?$", stripped)
            if m_src:
                src_str = expand_vars(m_src.group(1).strip()).replace("$HOME", str(Path.home()))
                visit(Path(src_str))
                continue
            if re.match(r"^bind[a-z]*\s*=", stripped) and "#" in stripped:
                lhs, comment = stripped.split("#", 1)
                comment = comment.strip()
                if not comment or re.fullmatch(r"(dwindle|master|numpad\s+\d+)", comment, re.I):
                    continue
                body = expand_vars(lhs.split("=", 1)[1].strip())
                parts = [p.strip() for p in body.split(",", 3)]
                if len(parts) >= 3:
                    disp = parts[2].lower()
                    arg = parts[3].strip() if len(parts) == 4 else ""
                    comments[(disp, arg)] = comment[:1].upper() + comment[1:]

    visit(conf_path)
    return comments


def format_shortcut(bind: dict) -> str:
    modmask = int(bind.get("modmask", 0) or 0)
    mods = [name for bit, name in MOD_BITS if modmask & bit]

    key = (bind.get("key") or "").strip()
    keycode = int(bind.get("keycode", 0) or 0)

    if key:
        low = key.lower()
        if low in KEY_NAMES:
            key_label = KEY_NAMES[low]
        elif len(key) == 1:
            key_label = key.upper()
        else:
            key_label = key
    elif keycode:
        key_label = KEYCODE_NAMES.get(keycode, f"Keycode {keycode}")
    else:
        key_label = "?"

    return " + ".join(mods + [key_label]) if mods else key_label


def classify_and_describe(
    bind: dict,
    ws_monitors: dict[str, str],
    inline_comments: dict[tuple[str, str], str],
) -> tuple[str, int, str]:
    dispatcher = (bind.get("dispatcher") or "").strip()
    disp_low = dispatcher.lower()
    arg = (bind.get("arg") or "").strip()
    key_low = (bind.get("key") or "").strip().lower()

    # 1. Descrição nativa via bindd (se houver)
    explicit_desc = (bind.get("description") or "").strip() if bind.get("has_description") else ""

    # --- Dispatchers de janela ---
    if disp_low == "killactive":
        return ("janelas", 10, explicit_desc or "Fechar janela ativa")
    if disp_low == "forcekillactive":
        return ("janelas", 11, explicit_desc or "Forçar encerramento da janela ativa")
    if disp_low == "togglefloating":
        return ("janelas", 20, explicit_desc or "Alternar janela entre modo flutuante e tiling")
    if disp_low == "fullscreen":
        if arg == "1":
            return ("janelas", 31, explicit_desc or "Maximizar janela (respeitando barra e gaps)")
        return ("janelas", 30, explicit_desc or "Tela cheia real (ocupa o monitor inteiro)")
    if disp_low == "pseudo":
        return ("janelas", 40, explicit_desc or "Alternar modo pseudotile (Dwindle)")
    if disp_low == "togglesplit":
        return ("janelas", 41, explicit_desc or "Alternar divisão horizontal / vertical (Dwindle)")
    if disp_low == "pin":
        return ("janelas", 42, explicit_desc or "Fixar janela em todos os workspaces")
    if disp_low == "centerwindow":
        return ("janelas", 43, explicit_desc or "Centralizar janela flutuante")
    if disp_low == "cyclenext":
        if arg == "prev":
            return ("janelas", 6, explicit_desc or "Alternar para janela anterior (no mesmo workspace)")
        return ("janelas", 5, explicit_desc or "Alternar para próxima janela (no mesmo workspace)")
    if disp_low == "bringactivetotop":
        return ("janelas", 7, explicit_desc or "Trazer janela ativa para o topo")
    if disp_low == "mouse":
        if arg == "movewindow":
            return ("janelas", 50, explicit_desc or "Mover janela arrastando com o mouse")
        if arg == "resizewindow":
            return ("janelas", 51, explicit_desc or "Redimensionar janela arrastando com o mouse")
        return ("janelas", 59, explicit_desc or f"Ação com o mouse ({arg})")

    # --- Foco e monitores ---
    if disp_low == "movefocus":
        d = DIR_NAMES.get(arg.lower(), arg)
        return ("monitores", 10, explicit_desc or f"Mover foco para a janela {d}")
    if disp_low == "focusmonitor":
        d = DIR_NAMES.get(arg.lower(), arg)
        return ("monitores", 20, explicit_desc or f"Alternar foco para o monitor {d}")
    if disp_low == "movewindow":
        if arg.startswith("mon:"):
            m = arg.split(":", 1)[1]
            d = DIR_NAMES.get(m.lower(), m)
            return ("monitores", 30, explicit_desc or f"Enviar janela ativa para o monitor {d}")
        d = DIR_NAMES.get(arg.lower(), arg)
        return ("janelas", 45, explicit_desc or f"Mover janela ativa {d}")

    # --- Workspaces ---
    if disp_low == "togglespecialworkspace":
        name = arg or "especial"
        return ("workspace", 10, explicit_desc or f"Mostrar / ocultar Scratchpad ({name})")
    if disp_low in ("workspace", "movetoworkspace", "movetoworkspacesilent"):
        silent_suffix = " (silencioso)" if disp_low == "movetoworkspacesilent" else ""
        is_move = disp_low != "workspace"

        if arg in ("m-1", "r-1", "e-1", "-1"):
            return ("workspace", 1, explicit_desc or "Workspace anterior do monitor atual")
        if arg in ("m+1", "r+1", "e+1", "+1"):
            return ("workspace", 2, explicit_desc or "Próximo workspace do monitor atual")
        if arg.startswith("special"):
            sp = arg.split(":", 1)[1] if ":" in arg else "especial"
            return ("workspace", 11, explicit_desc or f"Mover janela ativa para o Scratchpad ({sp}){silent_suffix}")
        if arg.isdigit():
            ws_num = int(arg)
            mon = ws_monitors.get(arg, "")
            if ws_num > 10 and mon:
                mon_info = f" ({mon} · #{ws_num - 10})"
            elif mon:
                mon_info = f" ({mon})"
            else:
                mon_info = ""
            if is_move:
                return ("workspace", 200 + ws_num, explicit_desc or f"Mover janela p/ Workspace {ws_num}{mon_info}{silent_suffix}")
            return ("workspace", 100 + ws_num, explicit_desc or f"Ir para Workspace {ws_num}{mon_info}")

        action_lbl = "Mover janela p/ workspace" if is_move else "Ir para workspace"
        return ("workspace", 50, explicit_desc or f"{action_lbl} {arg}{silent_suffix}")

    # --- Exec / comandos externos ---
    if disp_low in ("exec", "execr"):
        if explicit_desc:
            return ("apps", 50, explicit_desc)

        cmd = arg
        # Apps & lançadores conhecidos
        if cmd == "kitty" or cmd.startswith("kitty "):
            return ("apps", 10, "Abrir terminal (Kitty)")
        if "wofi" in cmd and "drun" in cmd:
            return ("apps", 11, "Menu de aplicativos (Wofi)")
        if "rofi" in cmd and "drun" in cmd:
            return ("apps", 11, "Menu de aplicativos (Rofi)")
        if cmd == "nautilus" or cmd.startswith("nautilus "):
            return ("apps", 12, "Abrir gerenciador de arquivos (Nautilus)")
        if cmd == "firefox" or cmd.startswith("firefox "):
            return ("apps", 13, "Abrir navegador (Firefox)")
        if "scripts_menu.sh" in cmd or "scripts-menu.sh" in cmd:
            return ("apps", 14, "Menu de scripts personalizados (Wofi)")
        if "swaync-client" in cmd:
            return ("apps", 15, "Abrir / fechar central de notificações (SwayNC)")
        if "keybinds.sh" in cmd:
            return ("apps", 16, "Abrir / fechar este menu de atalhos")
        if "window-switcher.sh" in cmd:
            return ("janelas", 4, "Menu visual de janelas abertas (com títulos)")
        if "arrange-windows.py" in cmd:
            return ("janelas", 36, "Ajustar e redimensionar todas as janelas do workspace")
        if "steam" in cmd:
            return ("apps", 17, "Abrir Steam")
        if "deb-installer.sh" in cmd:
            return ("apps", 18, "Instalador de pacotes .deb (Kitty)")
        if "network-settings.sh" in cmd:
            return ("apps", 19, "Configurações de Wi-Fi e Rede")
        if "updates.sh" in cmd:
            return ("apps", 20, "Gerenciador de atualizações do sistema")
        if "toggle-tablet-monitor.sh" in cmd:
            return ("monitores", 40, "Alternar monitor da mesa digitalizadora (Wacom)")

        # Capturas de tela
        if "screenshot.sh" in cmd:
            if "--copy-only" in cmd:
                return ("captura", 13, "Capturar área selecionada (apenas área de transferência)")
            if re.search(r"\bregion\b", cmd):
                return ("captura", 10, "Capturar área selecionada (salva e copia)")
            if re.search(r"\bscreen\b", cmd):
                return ("captura", 11, "Capturar monitor atual (salva e copia)")
            if re.search(r"\bwindow\b", cmd):
                return ("captura", 12, "Capturar janela ativa (salva e copia)")
            return ("captura", 14, "Capturar todos os monitores (salva e copia)")

        # Wallpapers
        if "hyprquickpaper" in cmd or "wallpaper-menu.sh" in cmd:
            return ("wallpaper", 10, "Seletor de wallpaper (monitor em foco)")
        if "videowallpaper.sh" in cmd:
            return ("wallpaper", 11, "Menu de vídeo wallpaper (monitor em foco)")
        if "wallpaper.sh" in cmd:
            if re.search(r"\bnext\b", cmd):
                return ("wallpaper", 12, "Próximo wallpaper estático")
            if re.search(r"\bprev\b", cmd):
                return ("wallpaper", 13, "Wallpaper estático anterior")
            if re.search(r"\brandom\b", cmd):
                return ("wallpaper", 14, "Wallpaper estático aleatório")
            return ("wallpaper", 15, "Alternar wallpaper")
        if "nightlight.sh" in cmd:
            return ("wallpaper", 20, "Alternar filtro de luz noturna")

        # Sessão & bloqueio
        if "lock.sh" in cmd or cmd == "hyprlock":
            return ("sessao", 10, "Bloquear tela (Hyprlock + vídeo)")
        if "lockvideo.sh" in cmd:
            return ("sessao", 11, "Escolher vídeo da tela de bloqueio")
        if "powermenu.sh" in cmd:
            return ("sessao", 12, "Menu de Energia / Sessão")
        if "hyprshutdown" in cmd or "dispatch exit" in cmd:
            return ("sessao", 20, "Encerrar sessão do Hyprland (Logout)")

        # Multimídia & brilho
        if "wpctl set-volume" in cmd:
            if "+" in cmd:
                return ("midia", 10, "Aumentar volume do áudio (+5%)")
            return ("midia", 11, "Diminuir volume do áudio (-5%)")
        if "wpctl set-mute" in cmd:
            if "SOURCE" in cmd:
                return ("midia", 13, "Silenciar / ativar microfone")
            return ("midia", 12, "Silenciar / ativar saída de áudio")
        if "brightnessctl" in cmd:
            if "+" in cmd:
                return ("midia", 20, "Aumentar brilho da tela (+5%)")
            return ("midia", 21, "Diminuir brilho da tela (-5%)")
        if "playerctl" in cmd:
            if "next" in cmd:
                return ("midia", 30, "Próxima faixa de mídia")
            if "prev" in cmd:
                return ("midia", 31, "Faixa de mídia anterior")
            if "play-pause" in cmd:
                lbl = "Pausar / reproduzir mídia" if "pause" in key_low else "Reproduzir / pausar mídia"
                return ("midia", 32, lbl)
            return ("midia", 35, f"Controle de mídia ({cmd})")
        if "youtube-player.sh" in cmd or "youtube-miniplayer" in cmd:
            return ("midia", 33, "Abrir / fechar YouTube Miniplayer")

        # Comentário inline no hyprland.conf para novos atalhos customizados
        inline = inline_comments.get((disp_low, arg))
        if inline:
            return ("apps", 60, inline)

        short_cmd = cmd.replace(str(Path.home()), "~")
        return ("apps", 70, f"Executar: {short_cmd}")

    if disp_low == "exit":
        return ("sessao", 20, explicit_desc or "Encerrar sessão do Hyprland (Logout)")

    inline = inline_comments.get((disp_low, arg))
    desc = explicit_desc or inline or (f"{dispatcher} {arg}".strip())
    return ("janelas", 90, desc)


def load_entries() -> list[dict]:
    binds = run_json(["hyprctl", "binds", "-j"])
    ws_rules = run_json(["hyprctl", "workspacerules", "-j"])
    ws_monitors = {
        str(r.get("workspaceString")): str(r.get("monitor"))
        for r in ws_rules
        if r.get("workspaceString") and r.get("monitor")
    }
    inline_comments = parse_inline_comments(HYPR_CONF)

    entries = []
    for idx, b in enumerate(binds):
        if b.get("catch_all"):
            continue
        shortcut = format_shortcut(b)
        submap = (b.get("submap") or "").strip()
        if submap:
            shortcut = f"[{submap}] {shortcut}"

        cat_key, sub_order, desc = classify_and_describe(b, ws_monitors, inline_comments)
        cat_order, icon, cat_label, color = CATEGORIES[cat_key]

        entries.append(
            {
                "orig_idx": idx,
                "cat_order": cat_order,
                "sub_order": sub_order,
                "icon": icon,
                "cat_label": cat_label,
                "color": color,
                "shortcut": shortcut,
                "desc": desc,
                "dispatcher": (b.get("dispatcher") or "").strip(),
                "arg": (b.get("arg") or "").strip(),
                "mouse": bool(b.get("mouse")),
            }
        )

    entries.sort(key=lambda e: (e["cat_order"], e["sub_order"], e["orig_idx"]))
    return entries


def format_markup_row(e: dict) -> str:
    cat_col = f"{e['icon']} {e['cat_label']:<9}"
    key_col = f"{e['shortcut']:<25}"
    desc_col = html.escape(e["desc"])
    return (
        f"<span foreground='{e['color']}'>{html.escape(cat_col)}</span>"
        f"<span foreground='#585b70'>│</span> "
        f"<b><span foreground='#f5e0dc'>{html.escape(key_col)}</span></b>"
        f"<span foreground='#585b70'>│</span> "
        f"<span foreground='#cdd6f4'>{desc_col}</span>"
    )


def format_plain_row(e: dict) -> str:
    return f"{e['icon']} {e['cat_label']:<9} │ {e['shortcut']:<25} │ {e['desc']}"


def copy_to_clipboard(e: dict):
    text = f"{e['shortcut']} — {e['desc']}"
    if shutil.which("wl-copy"):
        subprocess.run(["wl-copy"], input=text, text=True, check=False)
    if shutil.which("notify-send"):
        subprocess.run(
            ["notify-send", "-a", "Atalhos do Hyprland", "Atalho copiado", text],
            check=False,
        )


def execute_entry(e: dict):
    if e["mouse"] or e["dispatcher"].lower() == "mouse":
        copy_to_clipboard(e)
        return
    # Pequena pausa para o foco retornar à janela anterior antes do dispatch
    time.sleep(0.08)
    cmd = ["hyprctl", "dispatch", e["dispatcher"]]
    if e["arg"] != "":
        cmd.append(e["arg"])
    subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def show_menu(entries: list[dict]):
    if not entries:
        if shutil.which("notify-send"):
            subprocess.run(
                ["notify-send", "-u", "critical", "Atalhos do Hyprland", "Nenhum atalho encontrado"],
                check=False,
            )
        return

    rows = "\n".join(format_markup_row(e) for e in entries)
    total = len(entries)

    if shutil.which("rofi"):
        mesg = (
            f"<b>{total} atalhos ativos</b>  ·  "
            "Digite para filtrar  ·  <b>Enter</b>: executar ação  ·  "
            "<b>Alt+C</b>: copiar atalho  ·  <b>Esc</b>: fechar"
        )
        cmd = [
            "rofi",
            "-dmenu",
            "-i",
            "-markup-rows",
            "-format",
            "i",
            "-p",
            "󰌌  Atalhos",
            "-mesg",
            mesg,
            "-kb-custom-1",
            "Alt+c",
        ]
        if ROFI_THEME.is_file():
            cmd.extend(["-theme", str(ROFI_THEME)])

        proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        try:
            PID_FILE.write_text(str(proc.pid), encoding="utf-8")
            out, _ = proc.communicate(input=rows)
            rc = proc.returncode
        finally:
            PID_FILE.unlink(missing_ok=True)

        sel = (out or "").strip()
        if not sel.isdigit():
            return
        idx = int(sel)
        if not (0 <= idx < len(entries)):
            return

        if rc == 0:
            execute_entry(entries[idx])
        elif rc == 10:  # kb-custom-1 (Alt+C)
            copy_to_clipboard(entries[idx])
        return

    # Fallback para Wofi caso Rofi não esteja instalado
    wofi_rows = "\n".join(
        f"{i:>2}. {format_markup_row(e)}" for i, e in enumerate(entries, start=1)
    )
    proc = subprocess.Popen(
        [
            "wofi",
            "--dmenu",
            "--allow-markup",
            "--insensitive",
            "--width",
            "860",
            "--height",
            "540",
            "--lines",
            "14",
            "--prompt",
            f"󰌌  Atalhos ({total})",
        ],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    try:
        PID_FILE.write_text(str(proc.pid), encoding="utf-8")
        out, _ = proc.communicate(input=wofi_rows)
        rc = proc.returncode
    finally:
        PID_FILE.unlink(missing_ok=True)

    if rc == 0 and out:
        m = re.match(r"^\s*(\d+)\.", out.strip())
        if m:
            idx = int(m.group(1)) - 1
            if 0 <= idx < len(entries):
                execute_entry(entries[idx])


def main():
    entries = load_entries()
    if MODE == "json":
        tooltip = (
            f"Atalhos do Hyprland · {len(entries)} configurados\n"
            "Clique: abrir / fechar menu de atalhos (SUPER + F1)"
        )
        print(
            json.dumps(
                {
                    "text": "󰌌",
                    "tooltip": tooltip,
                    "class": "keybinds",
                },
                ensure_ascii=False,
            )
        )
    elif MODE == "list":
        for e in entries:
            print(format_plain_row(e))
    else:
        show_menu(entries)


if __name__ == "__main__":
    main()
PYEOF
