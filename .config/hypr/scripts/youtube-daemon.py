#!/usr/bin/env python3
"""
Daemon de sincronização e controle do YouTube para Hyprland & Waybar.
Comunicação de alta velocidade sem bloqueio:
- Injeção direta de atalhos no Hyprland (sendshortcut)
- Monitoramento de metadados via MPRIS
- Preservação de duração para vídeos em playlists
"""

import sys
import os
import json
import time
import socket
import struct
import hashlib
import base64
import threading
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler

WS_HOST = "127.0.0.1"
WS_PORT = 9876
HTTP_HOST = "127.0.0.1"
HTTP_PORT = 9877

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

state = {
    "connected": False,
    "title": "",
    "author": "",
    "currentTime": 0.0,
    "duration": 0.0,
    "playbackRate": 1.0,
    "paused": True,
    "isLive": False,
    "source": "none",
    "lastUpdate": 0,
    "positionTimestamp": 0.0
}

last_seek_time = 0.0
last_mpris_raw_curr = -1.0

state_lock = threading.Lock()
active_clients = []
clients_lock = threading.Lock()

TARGET_WINDOW = "class:^(firefox_firefox)$"

def send_key_to_youtube(key, mods=""):
    """Envia tecla de atalho diretamente para o Firefox no Hyprland instantaneamente."""
    arg = f"{mods},{key},{TARGET_WINDOW}"
    try:
        subprocess.run(["hyprctl", "dispatch", "sendshortcut", arg], capture_output=True, timeout=0.2)
    except Exception:
        pass

def broadcast_ws(message_dict):
    """Envia mensagem JSON para clientes WebSocket se houver algum."""
    payload = json.dumps(message_dict).encode("utf-8")
    length = len(payload)
    if length < 126:
        header = struct.pack("!BB", 0x81, length)
    elif length <= 65535:
        header = struct.pack("!BBH", 0x81, 126, length)
    else:
        header = struct.pack("!BBQ", 0x81, 127, length)
    frame = header + payload

    with clients_lock:
        to_remove = []
        for client in active_clients:
            try:
                client.sendall(frame)
            except Exception:
                to_remove.append(client)
        for client in to_remove:
            if client in active_clients:
                active_clients.remove(client)

def check_mpris():
    """Consulta metadados do YouTube/Firefox via MPRIS de forma rápida."""
    global state, last_seek_time, last_mpris_raw_curr
    with state_lock:
        if state["source"] in ("extension", "http_sync") and (time.time() - state["lastUpdate"] < 2.0):
            return

    try:
        cmd = [
            "playerctl", "--player=firefox,%any", "metadata",
            "--format", "{{title}};;;{{artist}};;;{{position}};;;{{mpris:length}};;;{{status}}"
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=0.3)
        out = res.stdout.strip()
        if not out:
            return

        parts = out.split(";;;")
        if len(parts) >= 5 and parts[0]:
            raw_title = parts[0].strip()
            title = raw_title.replace(" - YouTube — Mozilla Firefox", "").replace(" - YouTube", "")
            if title.startswith("(") and ")" in title[:5]:
                title = title[title.index(")") + 1:].strip()

            artist = parts[1].strip()
            try:
                curr = float(parts[2]) / 1000000.0 if parts[2] else 0.0
            except ValueError:
                curr = 0.0
            try:
                dur = float(parts[3]) / 1000000.0 if parts[3] else 0.0
            except ValueError:
                dur = 0.0
            status = parts[4].strip().lower()
            paused = (status != "playing")

            # Detecta se é realmente ao vivo pelo título ou ausência definitiva
            is_live = any(w in title.lower() for w in ("🔴 ao vivo", "[ao vivo]", "live stream", "24/7 stream"))

            with state_lock:
                same_video = (state["title"] == title)
                skip_active = (time.time() - last_seek_time < 3.0)
                now = time.time()

                state["connected"] = True
                state["title"] = title
                state["author"] = artist if artist else state.get("author", "")

                # 1. Se trocou de vídeo, reseta posição e velocidade para o normal (1.0x)
                if not same_video:
                    state["currentTime"] = curr
                    state["positionTimestamp"] = now
                    state["playbackRate"] = 1.0
                    last_mpris_raw_curr = curr

                # 2. Se o estado de pausa mudou externamente (ex: usuário pausou/despausou no navegador)
                elif state["paused"] != paused:
                    if paused:
                        # No Firefox, a propriedade Position do MPRIS é 100% atualizada e exata no momento do pause
                        if curr > 0.5:
                            state["currentTime"] = curr
                        else:
                            pos_ts = state.get("positionTimestamp", 0.0)
                            if pos_ts > 0:
                                elapsed = now - pos_ts
                                state["currentTime"] += elapsed * state.get("playbackRate", 1.0)
                        last_mpris_raw_curr = curr
                    state["paused"] = paused
                    state["positionTimestamp"] = now

                # 3. Se estiver tocando (paused == False)
                elif not paused:
                    # No Firefox, Position NÃO se atualiza a cada segundo durante reprodução.
                    # Ele permanece com o valor antigo de quando começou/pausou.
                    # Portanto, SÓ aceitamos curr se ele tiver sofrido uma alteração REAL e DISTINTA (> 1.5s)
                    # em relação à última leitura conhecida do MPRIS (ex: usuário clicou na barra do YouTube no browser),
                    # E NUNCA quando houver skip recente via botões do miniplayer!
                    if curr > 0.5 and not skip_active:
                        if abs(curr - last_mpris_raw_curr) > 1.5:
                            state["currentTime"] = curr
                            state["positionTimestamp"] = now
                            last_mpris_raw_curr = curr

                # 4. Se estiver pausado e chegar uma posição válida diferente
                elif paused and curr > 0.5 and abs(curr - state["currentTime"]) > 1.0:
                    state["currentTime"] = curr
                    state["positionTimestamp"] = now
                    last_mpris_raw_curr = curr

                # Proteção de duração
                if dur > 0.0:
                    state["duration"] = dur
                elif not same_video:
                    state["duration"] = 0.0

                state["isLive"] = is_live
                state["source"] = "mpris"
                state["lastUpdate"] = now
    except Exception:
        pass

sync_timer = None
sync_timer_lock = threading.Lock()

def debounced_mpris_sync_worker():
    global last_mpris_raw_curr
    with state_lock:
        is_paused = state.get("paused", True)
        is_live = state.get("isLive", False)

    if is_live:
        return

    # Se estiver pausado, o playerctl retorna a posição real diretamente
    if is_paused:
        try:
            res = subprocess.run(["playerctl", "--player=firefox,%any", "position"], capture_output=True, text=True, timeout=0.3)
            out = res.stdout.strip()
            if out:
                real_pos = float(out)
                if real_pos > 0.5:
                    with state_lock:
                        state["currentTime"] = real_pos
                        state["positionTimestamp"] = time.time()
                        last_mpris_raw_curr = real_pos
        except Exception:
            pass
        return

    # Se estiver tocando, amostragem ultrarrápida (~30ms) para obter a posição real do YouTube
    try:
        subprocess.run(["playerctl", "--player=firefox,%any", "pause"], capture_output=True, timeout=0.3)
        res = subprocess.run(["playerctl", "--player=firefox,%any", "position"], capture_output=True, text=True, timeout=0.3)
        subprocess.run(["playerctl", "--player=firefox,%any", "play"], capture_output=True, timeout=0.3)
        out = res.stdout.strip()
        if out:
            real_pos = float(out)
            if real_pos > 0.5:
                with state_lock:
                    state["currentTime"] = real_pos
                    state["positionTimestamp"] = time.time()
                    last_mpris_raw_curr = real_pos
    except Exception:
        pass

def schedule_debounced_mpris_sync():
    global sync_timer
    with sync_timer_lock:
        if sync_timer is not None:
            sync_timer.cancel()
        sync_timer = threading.Timer(0.6, debounced_mpris_sync_worker)
        sync_timer.daemon = True
        sync_timer.start()

def execute_command(action, value=None):
    """Executa a ação usando atalhos nativos do YouTube no Hyprland."""
    global last_seek_time

    # 1. Envia via WebSocket se houver extensão conectada
    broadcast_ws({"action": action, "value": value})

    # 2. Executa controle de mídia
    if action in ("toggle", "play", "pause"):
        if action == "play":
            cmd = ["playerctl", "--player=firefox,%any", "play"]
        elif action == "pause":
            cmd = ["playerctl", "--player=firefox,%any", "pause"]
        else:
            cmd = ["playerctl", "--player=firefox,%any", "play-pause"]

        try:
            res = subprocess.run(cmd, capture_output=True, timeout=0.3)
            if res.returncode != 0:
                send_key_to_youtube("k")
        except Exception:
            send_key_to_youtube("k")

        with state_lock:
            now = time.time()
            if not state["paused"]:
                # Se estava tocando e agora vai pausar, consolida tempo decorrido
                pos_ts = state.get("positionTimestamp", 0.0)
                if pos_ts > 0:
                    elapsed = now - pos_ts
                    state["currentTime"] += elapsed * state.get("playbackRate", 1.0)
                    if state.get("duration", 0.0) > 0:
                        state["currentTime"] = min(state["duration"], state["currentTime"])

            if action == "toggle":
                state["paused"] = not state["paused"]
            elif action == "play":
                state["paused"] = False
            elif action == "pause":
                state["paused"] = True

            state["positionTimestamp"] = now
            state["lastUpdate"] = now

    elif action == "skip":
        last_seek_time = time.time()
        if value is not None:
            with state_lock:
                now = time.time()
                # Consolida tempo decorrido antes de aplicar o salto
                if not state["paused"]:
                    pos_ts = state.get("positionTimestamp", 0.0)
                    if pos_ts > 0:
                        elapsed = now - pos_ts
                        state["currentTime"] += elapsed * state.get("playbackRate", 1.0)
                dur = state.get("duration", 0.0)
                new_curr = max(0.0, state.get("currentTime", 0.0) + value)
                if dur > 0:
                    new_curr = min(dur, new_curr)
                state["currentTime"] = new_curr
                state["positionTimestamp"] = now
                state["lastUpdate"] = now

            # No YouTube: 'l' avança 10s, 'j' recua 10s
            if value > 0:
                times = max(1, int(round(value / 10.0)))
                for _ in range(times):
                    send_key_to_youtube("l")
                    time.sleep(0.02)
            elif value < 0:
                times = max(1, int(round(abs(value) / 10.0)))
                for _ in range(times):
                    send_key_to_youtube("j")
                    time.sleep(0.02)

            schedule_debounced_mpris_sync()

    elif action in ("setRate", "rate"):
        # No YouTube: SHIFT + . (>) aumenta 0.25x; SHIFT + , (<) diminui 0.25x
        if value is not None and value > 0:
            target_rate = round(float(value), 2)
            with state_lock:
                now = time.time()
                if not state["paused"]:
                    pos_ts = state.get("positionTimestamp", 0.0)
                    if pos_ts > 0:
                        elapsed = now - pos_ts
                        state["currentTime"] += elapsed * state.get("playbackRate", 1.0)
                        if state.get("duration", 0.0) > 0:
                            state["currentTime"] = min(state["duration"], state["currentTime"])
                current_rate = round(float(state.get("playbackRate", 1.0)), 2)
                state["playbackRate"] = target_rate
                state["positionTimestamp"] = now
                state["lastUpdate"] = now

            diff_steps = int(round((target_rate - current_rate) / 0.25))
            if diff_steps > 0:
                for _ in range(diff_steps):
                    send_key_to_youtube("period", "SHIFT")
                    time.sleep(0.03)
            elif diff_steps < 0:
                for _ in range(abs(diff_steps)):
                    send_key_to_youtube("comma", "SHIFT")
                    time.sleep(0.03)

    elif action == "resetRate":
        with state_lock:
            state["playbackRate"] = 1.0
            state["positionTimestamp"] = time.time()
            state["lastUpdate"] = time.time()

    elif action == "seek":
        last_seek_time = time.time()
        if value is not None:
            with state_lock:
                now = time.time()
                dur = state.get("duration", 0.0)
                val = float(value)
                if dur > 0:
                    val = min(dur, max(0.0, val))
                state["currentTime"] = val
                state["positionTimestamp"] = now
                state["lastUpdate"] = now
            if dur > 0:
                pct = int(min(9, max(0, round((val / dur) * 10))))
                send_key_to_youtube(str(pct))
                send_key_to_youtube(str(pct))

def handle_ws_client(client_sock, addr):
    global state
    try:
        data = client_sock.recv(4096).decode("utf-8", errors="ignore")
        headers = {}
        for line in data.split("\r\n")[1:]:
            if ":" in line:
                k, v = line.split(":", 1)
                headers[k.strip().lower()] = v.strip()

        key = headers.get("sec-websocket-key")
        if not key:
            client_sock.close()
            return

        accept_val = base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()
        response = (
            "HTTP/1.1 101 Switching Protocols\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Accept: {accept_val}\r\n\r\n"
        )
        client_sock.sendall(response.encode())

        with clients_lock:
            active_clients.append(client_sock)

        with state_lock:
            state["connected"] = True
            state["source"] = "extension"
            state["lastUpdate"] = time.time()

        while True:
            b1_b2 = client_sock.recv(2)
            if len(b1_b2) < 2:
                break
            b1, b2 = b1_b2[0], b1_b2[1]
            opcode = b1 & 0x0F
            if opcode == 0x8:
                break

            masked = (b2 & 0x80) != 0
            payload_len = b2 & 0x7F
            if payload_len == 126:
                ext = client_sock.recv(2)
                payload_len = struct.unpack("!H", ext)[0]
            elif payload_len == 127:
                ext = client_sock.recv(8)
                payload_len = struct.unpack("!Q", ext)[0]

            mask_key = b""
            if masked:
                mask_key = client_sock.recv(4)

            payload = b""
            while len(payload) < payload_len:
                chunk = client_sock.recv(payload_len - len(payload))
                if not chunk:
                    break
                payload += chunk

            if masked and mask_key:
                payload = bytes([b ^ mask_key[i % 4] for i, b in enumerate(payload)])

            if opcode == 0x1:
                try:
                    msg = json.loads(payload.decode("utf-8"))
                    if msg.get("type") == "status":
                        with state_lock:
                            state["connected"] = True
                            state["title"] = msg.get("title", state["title"])
                            state["author"] = msg.get("author", state["author"])
                            state["currentTime"] = float(msg.get("currentTime", 0.0))
                            dur = float(msg.get("duration", 0.0))
                            if dur > 0:
                                state["duration"] = dur
                            state["playbackRate"] = float(msg.get("playbackRate", 1.0))
                            state["paused"] = bool(msg.get("paused", True))
                            state["source"] = "extension"
                            state["lastUpdate"] = time.time()
                except Exception:
                    pass

    except Exception:
        pass
    finally:
        with clients_lock:
            if client_sock in active_clients:
                active_clients.remove(client_sock)
        try:
            client_sock.close()
        except Exception:
            pass

def start_ws_server():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((WS_HOST, WS_PORT))
    server.listen(5)
    while True:
        client_sock, addr = server.accept()
        t = threading.Thread(target=handle_ws_client, args=(client_sock, addr), daemon=True)
        t.start()

class RestHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def _set_cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def do_OPTIONS(self):
        self.send_response(204)
        self._set_cors_headers()
        self.end_headers()

    def do_GET(self):
        if self.path in ("/status", "/"):
            check_mpris()

            with state_lock:
                if state["lastUpdate"] > 0 and (time.time() - state["lastUpdate"] > 8):
                    state["connected"] = False

                resp_state = dict(state)
                # Interpolação precisa de tempo quando o vídeo está em reprodução
                if not resp_state["paused"] and resp_state["connected"] and not resp_state["isLive"]:
                    pos_ts = resp_state.get("positionTimestamp", 0.0)
                    if pos_ts > 0:
                        elapsed = time.time() - pos_ts
                        rate = resp_state.get("playbackRate", 1.0)
                        interp_curr = resp_state["currentTime"] + (elapsed * rate)
                        dur = resp_state.get("duration", 0.0)
                        if dur > 0:
                            interp_curr = min(dur, interp_curr)
                        resp_state["currentTime"] = interp_curr

                data = json.dumps(resp_state).encode("utf-8")

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self._set_cors_headers()
            self.end_headers()
            self.wfile.write(data)
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == "/cmd":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length).decode("utf-8", errors="ignore")
            try:
                cmd = json.loads(body)
                action = cmd.get("action", cmd.get("command"))
                value = cmd.get("value")

                execute_command(action, value)

                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(b'{"status":"ok"}')
            except Exception as e:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode())

        elif self.path == "/sync":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length).decode("utf-8", errors="ignore")
            try:
                msg = json.loads(body)
                with state_lock:
                    state["connected"] = True
                    state["title"] = msg.get("title", state["title"])
                    state["author"] = msg.get("author", state["author"])
                    state["currentTime"] = float(msg.get("currentTime", 0.0))
                    dur = float(msg.get("duration", 0.0))
                    if dur > 0:
                        state["duration"] = dur
                    state["playbackRate"] = float(msg.get("playbackRate", 1.0))
                    state["paused"] = bool(msg.get("paused", True))
                    state["source"] = "http_sync"
                    state["lastUpdate"] = time.time()

                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(b'{"status":"ok"}')
            except Exception as e:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode())
        else:
            self.send_response(404)
            self.end_headers()

def start_http_server():
    server = HTTPServer((HTTP_HOST, HTTP_PORT), RestHandler)
    server.serve_forever()

def bg_mpris_poller():
    while True:
        time.sleep(0.5)
        check_mpris()

def main():
    t_ws = threading.Thread(target=start_ws_server, daemon=True)
    t_ws.start()

    t_mpris = threading.Thread(target=bg_mpris_poller, daemon=True)
    t_mpris.start()

    start_http_server()

if __name__ == "__main__":
    main()
