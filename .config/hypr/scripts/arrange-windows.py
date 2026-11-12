#!/usr/bin/env python3
"""
Ajusta e redimensiona automaticamente todas as janelas abertas no workspace atual
do Hyprland em uma grade equilibrada de tiling nativo (dwindle).

Por serem convertidas em janelas tiled nativas, todas as janelas que fazem fronteira
passam a se redimensionar juntas ao arrastar qualquer borda ou usar SUPER + Botão Direito.
"""
import json
import subprocess
import sys


def run_json(cmd):
    out = subprocess.check_output(cmd, text=True)
    return json.loads(out)


def build_bsp_commands(win_addrs, box_w, box_h, cmds):
    """
    Constrói uma árvore BSP equilibrada no layout dwindle usando preselect + settiled.
    win_addrs[0] já deve estar em tiling dentro da caixa (box_w x box_h).
    """
    n = len(win_addrs)
    if n <= 1:
        return

    anchor = win_addrs[0]
    mid = n // 2
    left_group = win_addrs[:mid]
    right_group = win_addrs[mid:]

    # Decide direção do corte conforme a proporção atual da sub-região
    if box_w >= box_h:
        direction = "r"
        left_w, left_h = box_w / 2.0, box_h
        right_w, right_h = box_w / 2.0, box_h
    else:
        direction = "d"
        left_w, left_h = box_w, box_h / 2.0
        right_w, right_h = box_w, box_h / 2.0

    pivot = right_group[0]
    cmds.append(f"dispatch focuswindow address:{anchor}")
    cmds.append(f"dispatch layoutmsg preselect {direction}")
    cmds.append(f"dispatch settiled address:{pivot}")

    build_bsp_commands(left_group, left_w, left_h, cmds)
    build_bsp_commands(right_group, right_w, right_h, cmds)


def main():
    active_ws = run_json(["hyprctl", "activeworkspace", "-j"])
    ws_id = active_ws.get("id")
    if ws_id is None:
        sys.exit(0)

    monitors = run_json(["hyprctl", "monitors", "-j"])
    clients = run_json(["hyprctl", "clients", "-j"])
    try:
        active_win = run_json(["hyprctl", "activewindow", "-j"])
        active_addr = active_win.get("address", "")
    except Exception:
        active_addr = ""

    windows = [
        c
        for c in clients
        if c.get("workspace", {}).get("id") == ws_id
        and c.get("mapped") is True
        and c.get("hidden") is False
        and not c.get("pinned", False)
    ]

    if not windows:
        sys.exit(0)

    target_mon = next(
        (
            m
            for m in monitors
            if m.get("id") == active_ws.get("monitorID")
            or m.get("name") == active_ws.get("monitor")
        ),
        monitors[0] if monitors else None,
    )
    if not target_mon:
        sys.exit(1)

    scale = float(target_mon.get("scale", 1.0) or 1.0)
    transform = int(target_mon.get("transform", 0) or 0)
    mon_w = target_mon["width"] / scale
    mon_h = target_mon["height"] / scale
    if transform % 2 == 1:
        mon_w, mon_h = mon_h, mon_w

    reserved = target_mon.get("reserved", [0, 0, 0, 0])
    uw = max(200.0, mon_w - int(reserved[0]) - int(reserved[2]))
    uh = max(200.0, mon_h - int(reserved[1]) - int(reserved[3]))

    # Ordenação estável: respeita posição aproximada e dá prioridade à janela focada
    windows.sort(
        key=lambda c: (
            c.get("at", [0, 0])[0] // 40,
            c.get("at", [0, 0])[1] // 40,
            c.get("focusHistoryID", 9999),
            c.get("address", ""),
        )
    )

    addrs = [w["address"] for w in windows]
    batch_cmds = []

    # 1. Sai de fullscreen/maximizado e reseta para floating para reconstruir a árvore limpa
    for w in windows:
        addr = w["address"]
        if w.get("fullscreen", 0) != 0:
            batch_cmds.append(f"dispatch focuswindow address:{addr}")
            batch_cmds.append("dispatch fullscreenstate 0 0")
        if not w.get("floating", False):
            batch_cmds.append(f"dispatch setfloating address:{addr}")

    # 2. Coloca a primeira janela em tiling e constrói a grade BSP equilibrada
    batch_cmds.append(f"dispatch settiled address:{addrs[0]}")
    build_bsp_commands(addrs, uw, uh, batch_cmds)

    # 3. Restaura foco na janela que estava ativa
    if active_addr and active_addr in addrs:
        batch_cmds.append(f"dispatch focuswindow address:{active_addr}")

    subprocess.run(
        ["hyprctl", "--batch", "; ".join(batch_cmds)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )


if __name__ == "__main__":
    main()
