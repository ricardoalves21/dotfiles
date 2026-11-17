#!/usr/bin/env python3
"""
Miniplayer Flutuante do YouTube para Hyprland / Waybar
Interface moderna em GTK3 integrada com o daemon do YouTube.
Oferece controle de Play/Pause instantâneo, Barra de Progresso com Seek e Controle de Velocidade.
"""

import sys
import os
import time
import signal
import json
import threading
import urllib.request
import urllib.parse
import gi

gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GLib

HTTP_URL = "http://127.0.0.1:9877"

def format_time(seconds):
    if seconds is None or seconds < 0 or seconds != seconds:
        return "00:00"
    seconds = int(seconds)
    m, s = divmod(seconds, 60)
    h, m = divmod(m, 60)
    if h > 0:
        return f"{h:02d}:{m:02d}:{s:02d}"
    return f"{m:02d}:{s:02d}"

class YouTubeMiniplayer(Gtk.Window):
    def __init__(self):
        super().__init__(title="YouTube Miniplayer")
        self.set_name("youtube-miniplayer")
        self.set_role("youtube-miniplayer")
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_keep_above(True)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.set_default_size(360, 240)

        self.is_dragging_slider = False
        self.last_valid_time = 0.0
        self.last_video_title = ""
        self.display_time = 0.0
        self.total_duration = 0.0
        self.is_paused = True
        self.playback_rate = 1.0
        self.last_user_seek = 0.0
        self.last_user_action = 0.0
        self.last_tick_time = time.time()
        self.current_state = {
            "connected": False,
            "title": "",
            "author": "",
            "currentTime": 0.0,
            "duration": 0.0,
            "playbackRate": 1.0,
            "paused": True,
            "isLive": False
        }

        self.apply_css()
        self.build_ui()

        self.connect("key-press-event", self.on_key_press)

        # Relógio local de alta precisão (200ms) para animação contínua e fluida do contador de tempo
        GLib.timeout_add(200, self.on_ui_tick)

        # Atualização periódica do estado com o daemon a cada 500ms em thread separada
        GLib.timeout_add(500, self.schedule_poll)
        self.schedule_poll()

    def apply_css(self):
        css_provider = Gtk.CssProvider()
        css = """
        window {
            background-color: #000000;
            border: 2px solid #cba6f7;
            border-radius: 16px;
        }
        .yt-icon {
            color: #f38ba8;
            font-size: 20px;
            font-weight: bold;
            margin-right: 6px;
        }
        .video-title {
            color: #cdd6f4;
            font-size: 13px;
            font-weight: bold;
        }
        .video-channel {
            color: #a6adc8;
            font-size: 11px;
        }
        button.close-btn {
            background-image: none;
            background-color: transparent;
            color: #a6adc8;
            font-size: 14px;
            border: none;
            box-shadow: none;
            padding: 2px 6px;
            outline: none;
        }
        button.close-btn:hover {
            color: #f38ba8;
            background-color: transparent;
        }
        .time-label {
            color: #bac2de;
            font-size: 11px;
            font-family: monospace;
        }
        .live-badge {
            color: #f38ba8;
            font-size: 11px;
            font-weight: bold;
        }
        scale trough {
            background-color: #313244;
            border-radius: 4px;
            min-height: 6px;
            border: none;
        }
        scale highlight {
            background-color: #cba6f7;
            border-radius: 4px;
            min-height: 6px;
        }
        scale slider {
            background-color: #f5e0dc;
            border-radius: 50%;
            min-width: 14px;
            min-height: 14px;
            margin: -4px 0;
            box-shadow: 0 0 6px rgba(203, 166, 247, 0.6);
        }
        scale slider:hover {
            background-color: #ffffff;
            box-shadow: 0 0 10px rgba(203, 166, 247, 0.9);
        }
        button.ctrl-btn {
            background-image: none;
            background-color: #181825;
            color: #cdd6f4;
            border: 1px solid #313244;
            border-radius: 10px;
            padding: 6px 14px;
            font-size: 13px;
            box-shadow: none;
            outline: none;
        }
        button.ctrl-btn:hover {
            background-color: #313244;
            color: #ffffff;
            border-color: #cba6f7;
        }
        button.play-btn {
            background-image: none;
            background-color: #cba6f7;
            color: #000000;
            border: 1px solid #cba6f7;
            border-radius: 12px;
            padding: 8px 24px;
            font-size: 15px;
            font-weight: bold;
            box-shadow: 0 0 12px rgba(203, 166, 247, 0.4);
            outline: none;
        }
        button.play-btn:hover {
            background-color: #b4befe;
            border-color: #b4befe;
            color: #000000;
            box-shadow: 0 0 16px rgba(180, 190, 254, 0.7);
        }
        .speed-label {
            color: #a6adc8;
            font-size: 11px;
            font-weight: bold;
            margin-right: 4px;
        }
        button.rate-btn {
            background-image: none;
            background-color: #11111b;
            color: #a6adc8;
            border: 1px solid #313244;
            border-radius: 6px;
            padding: 2px 7px;
            font-size: 11px;
            box-shadow: none;
            outline: none;
        }
        button.rate-btn:hover {
            background-color: #1e1e2e;
            color: #cdd6f4;
            border-color: #585b70;
        }
        button.rate-btn.active {
            background-color: #cba6f7;
            color: #000000;
            border-color: #cba6f7;
            font-weight: bold;
        }
        """
        css_provider.load_from_data(css.encode())
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    def set_hand_cursor(self, widget):
        widget.connect(
            "enter-notify-event",
            lambda w, e: w.get_window().set_cursor(Gdk.Cursor.new_from_name(w.get_display(), "pointer")) if w.get_window() else None
        )

    def build_ui(self):
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        vbox.set_margin_top(14)
        vbox.set_margin_bottom(14)
        vbox.set_margin_start(16)
        vbox.set_margin_end(16)
        self.add(vbox)

        # Header: Ícone YouTube, Título/Canal e Botão Fechar
        header_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        
        icon_lbl = Gtk.Label(label="")
        icon_lbl.get_style_context().add_class("yt-icon")
        header_box.pack_start(icon_lbl, False, False, 0)

        titles_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        self.title_label = Gtk.Label(label="Carregando vídeo...")
        self.title_label.set_halign(Gtk.Align.START)
        self.title_label.set_ellipsize(3)
        self.title_label.set_max_width_chars(32)
        self.title_label.get_style_context().add_class("video-title")
        titles_box.pack_start(self.title_label, False, False, 0)

        self.channel_label = Gtk.Label(label="")
        self.channel_label.set_halign(Gtk.Align.START)
        self.channel_label.get_style_context().add_class("video-channel")
        titles_box.pack_start(self.channel_label, False, False, 0)

        header_box.pack_start(titles_box, True, True, 0)

        close_btn = Gtk.Button(label="✕")
        close_btn.get_style_context().add_class("close-btn")
        close_btn.set_tooltip_text("Fechar (Esc)")
        close_btn.connect("clicked", lambda b: cleanup_and_quit())
        self.set_hand_cursor(close_btn)
        header_box.pack_start(close_btn, False, False, 0)

        vbox.pack_start(header_box, False, False, 0)

        # Barra de Progresso
        progress_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        
        self.scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1)
        self.scale.set_draw_value(False)
        self.scale.set_hexpand(True)
        self.set_hand_cursor(self.scale)
        self.scale.connect("button-press-event", self.on_scale_press)
        self.scale.connect("button-release-event", self.on_scale_release)
        self.scale.connect("change-value", self.on_scale_change)
        progress_box.pack_start(self.scale, False, False, 0)

        times_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.curr_time_label = Gtk.Label(label="00:00")
        self.curr_time_label.get_style_context().add_class("time-label")
        times_box.pack_start(self.curr_time_label, False, False, 0)

        times_box.pack_start(Gtk.Box(), True, True, 0)

        self.total_time_label = Gtk.Label(label="00:00")
        self.total_time_label.get_style_context().add_class("time-label")
        times_box.pack_start(self.total_time_label, False, False, 0)

        progress_box.pack_start(times_box, False, False, 0)
        vbox.pack_start(progress_box, False, False, 0)

        # Controles Principais (Voltar 10s, Play/Pause, Avançar 10s)
        ctrl_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
        ctrl_box.set_halign(Gtk.Align.CENTER)

        btn_rewind = Gtk.Button(label="󰒮 10s")
        btn_rewind.get_style_context().add_class("ctrl-btn")
        btn_rewind.set_tooltip_text("Voltar 10s (Seta Esquerda / j)")
        btn_rewind.connect("clicked", lambda b: self.on_skip_click(-10))
        self.set_hand_cursor(btn_rewind)
        ctrl_box.pack_start(btn_rewind, False, False, 0)

        self.btn_play = Gtk.Button(label="󰏤 Pause")
        self.btn_play.get_style_context().add_class("play-btn")
        self.btn_play.set_tooltip_text("Play / Pause (Espaço / k)")
        self.btn_play.connect("clicked", lambda b: self.on_play_pause_click())
        self.set_hand_cursor(self.btn_play)
        ctrl_box.pack_start(self.btn_play, False, False, 0)

        btn_forward = Gtk.Button(label="10s 󰒭")
        btn_forward.get_style_context().add_class("ctrl-btn")
        btn_forward.set_tooltip_text("Avançar 10s (Seta Direita / l)")
        btn_forward.connect("clicked", lambda b: self.on_skip_click(10))
        self.set_hand_cursor(btn_forward)
        ctrl_box.pack_start(btn_forward, False, False, 0)

        vbox.pack_start(ctrl_box, False, False, 0)

        # Seletor de Velocidade (0.5x, 0.75x, 1x, 1.25x, 1.5x, 2x)
        speed_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=5)
        speed_box.set_halign(Gtk.Align.CENTER)
        
        lbl_speed = Gtk.Label(label="Velocidade:")
        lbl_speed.get_style_context().add_class("speed-label")
        speed_box.pack_start(lbl_speed, False, False, 0)

        self.rate_buttons = {}
        speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
        for sp in speeds:
            lbl = f"{sp}x" if sp != 1.0 else "1.0x"
            btn = Gtk.Button(label=lbl)
            btn.get_style_context().add_class("rate-btn")
            btn.connect("clicked", lambda b, rate=sp: self.on_rate_click(rate))
            self.set_hand_cursor(btn)
            speed_box.pack_start(btn, False, False, 0)
            self.rate_buttons[sp] = btn

        vbox.pack_start(speed_box, False, False, 0)

    def on_ui_tick(self):
        """Relógio local em tempo real: garante que o contador continue correndo suavemente."""
        now = time.time()
        dt = now - self.last_tick_time
        self.last_tick_time = now

        if not self.is_paused and not self.is_dragging_slider and not self.current_state.get("isLive", False):
            if self.total_duration > 0.0:
                self.display_time = min(self.total_duration, self.display_time + (dt * self.playback_rate))
                self.scale.set_value(self.display_time)
            else:
                self.display_time += dt * self.playback_rate
            self.curr_time_label.set_text(format_time(self.display_time))
        return True

    def on_play_pause_click(self):
        # 1. Resposta visual INSTANTÂNEA em 0ms
        self.last_user_action = time.time()
        self.is_paused = not self.is_paused
        self.current_state["paused"] = self.is_paused
        self.btn_play.set_label("󰐊 Play" if self.is_paused else "󰏤 Pause")
        self.last_tick_time = time.time()

        # 2. Envia comando explícito (play ou pause) ao daemon em thread secundária
        action = "pause" if self.is_paused else "play"
        self.send_cmd_async(action)

    def on_skip_click(self, seconds):
        # Registra o instante do salto e atualiza a posição local imediatamente
        now = time.time()
        self.last_user_seek = now
        self.last_user_action = now

        new_curr = max(0.0, self.display_time + seconds)
        if self.total_duration > 0.0:
            new_curr = min(self.total_duration, new_curr)

        self.display_time = new_curr
        self.current_state["currentTime"] = new_curr
        self.last_tick_time = now

        if not self.is_dragging_slider:
            self.scale.set_value(new_curr)
            self.curr_time_label.set_text(format_time(new_curr))

        self.send_cmd_async("skip", seconds)

    def on_rate_click(self, rate):
        self.playback_rate = rate
        self.current_state["playbackRate"] = rate
        self.last_user_action = time.time()

        for sp, btn in self.rate_buttons.items():
            ctx = btn.get_style_context()
            if abs(sp - rate) < 0.05:
                ctx.add_class("active")
            else:
                ctx.remove_class("active")

        self.send_cmd_async("setRate", rate)

    def on_scale_press(self, widget, event):
        self.is_dragging_slider = True

    def on_scale_release(self, widget, event):
        val = self.scale.get_value()
        now = time.time()
        self.display_time = val
        self.current_state["currentTime"] = val
        self.curr_time_label.set_text(format_time(val))
        self.last_user_seek = now
        self.last_user_action = now
        self.last_tick_time = now
        self.send_cmd_async("seek", val)
        self.is_dragging_slider = False

    def on_scale_change(self, widget, scroll_type, value):
        if self.is_dragging_slider:
            self.curr_time_label.set_text(format_time(value))

    def send_cmd_async(self, action, value=None):
        """Envia comando em thread de fundo para NUNCA travar a interface GTK."""
        def worker():
            payload = {"action": action}
            if value is not None:
                payload["value"] = value
            try:
                req = urllib.request.Request(
                    f"{HTTP_URL}/cmd",
                    data=json.dumps(payload).encode("utf-8"),
                    headers={"Content-Type": "application/json"}
                )
                with urllib.request.urlopen(req, timeout=0.4) as resp:
                    pass
            except Exception:
                pass
        threading.Thread(target=worker, daemon=True).start()

    def schedule_poll(self):
        """Dispara verificação periódica de status em thread para sincronizar com o YouTube."""
        def worker():
            try:
                with urllib.request.urlopen(f"{HTTP_URL}/status", timeout=0.4) as resp:
                    data = json.loads(resp.read().decode("utf-8"))
                    GLib.idle_add(self.update_ui_state, data)
            except Exception:
                pass
        threading.Thread(target=worker, daemon=True).start()
        return True

    def update_ui_state(self, data):
        self.current_state = data
        connected = data.get("connected", False)

        if not connected:
            self.title_label.set_text("Nenhum vídeo ativo")
            self.channel_label.set_text("Abra o YouTube no Firefox")
            self.btn_play.set_label("󰐊 Play")
            self.curr_time_label.set_text("00:00")
            self.total_time_label.set_text("00:00")
            self.scale.set_range(0, 100)
            self.scale.set_value(0)
            self.is_paused = True
            return

        title = data.get("title", "Sem título")
        author = data.get("author", "")
        self.title_label.set_text(title)
        self.title_label.set_tooltip_text(title)
        self.channel_label.set_text(author)

        now = time.time()
        new_video = (title != self.last_video_title)
        if new_video:
            self.last_video_title = title
            self.display_time = data.get("currentTime", 0.0)
            self.total_duration = data.get("duration", 0.0)
            self.last_user_seek = 0.0
            self.last_tick_time = now

        # Atualiza play/pause do servidor somente se não houve clique do usuário no último segundo
        server_paused = data.get("paused", True)
        if (now - self.last_user_action > 1.0):
            if self.is_paused != server_paused:
                self.is_paused = server_paused
                self.last_tick_time = now
            self.btn_play.set_label("󰐊 Play" if self.is_paused else "󰏤 Pause")

        dur = data.get("duration", 0.0)
        if dur > 0.0:
            self.total_duration = dur

        curr = data.get("currentTime", 0.0)
        skip_active = (now - self.last_user_seek < 0.75)

        # Filtro de estabilização contra leituras nulas/glitches momentâneos
        if curr <= 0.5 and self.last_valid_time > 2.0 and not new_video:
            curr = self.last_valid_time
        elif curr > 0.5:
            self.last_valid_time = curr

        # Ressincroniza o relógio apenas se:
        # 1. Vídeo novo
        # 2. Vídeo pausado (o pause fornece o tempo exato do YouTube)
        # 3. Ou quando o debounce de sincronização do daemon enviar a posição real exata do YouTube
        if not self.is_dragging_slider:
            if new_video:
                self.display_time = curr
                self.last_tick_time = now
            elif server_paused and curr > 0.5:
                self.display_time = curr
                self.last_tick_time = now
            elif not skip_active and abs(curr - self.display_time) > 0.5 and curr > 0.5:
                self.display_time = curr
                self.last_tick_time = now

        is_live = data.get("isLive", False)

        if is_live:
            self.total_time_label.set_text("🔴 Ao Vivo")
            self.curr_time_label.set_text(format_time(self.display_time) if self.display_time > 0 else "Ao Vivo")
            self.scale.set_sensitive(False)
            self.scale.set_range(0, 100)
            self.scale.set_value(100)
        else:
            self.scale.set_sensitive(True)
            if self.total_duration > 0.0:
                if not self.is_dragging_slider:
                    self.scale.set_range(0, max(self.total_duration, 1.0))
                    self.total_time_label.set_text(format_time(self.total_duration))
            else:
                if not self.is_dragging_slider:
                    self.total_time_label.set_text("--:--")

        current_rate = round(float(data.get("playbackRate", 1.0)), 2)
        if now - self.last_user_action > 1.0:
            self.playback_rate = current_rate
        for sp, btn in self.rate_buttons.items():
            ctx = btn.get_style_context()
            if abs(sp - current_rate) < 0.05:
                ctx.add_class("active")
            else:
                ctx.remove_class("active")

    def on_key_press(self, widget, event):
        key = event.keyval
        if key in (Gdk.KEY_Escape, Gdk.KEY_q):
            cleanup_and_quit()
            return True
        elif key in (Gdk.KEY_space, Gdk.KEY_k):
            self.on_play_pause_click()
            return True
        elif key in (Gdk.KEY_Left, Gdk.KEY_j):
            self.on_skip_click(-10)
            return True
        elif key in (Gdk.KEY_Right, Gdk.KEY_l):
            self.on_skip_click(10)
            return True
        elif key == Gdk.KEY_1:
            self.on_rate_click(1.0)
            return True
        elif key == Gdk.KEY_2:
            self.on_rate_click(1.25)
            return True
        elif key == Gdk.KEY_3:
            self.on_rate_click(1.5)
            return True
        elif key == Gdk.KEY_4:
            self.on_rate_click(2.0)
            return True
        return False

STATE_DIR = os.path.expanduser("~/.local/state/hypr")
PID_FILE = os.path.join(STATE_DIR, "youtube-miniplayer.pid")

def cleanup_and_quit():
    try:
        if os.path.exists(PID_FILE):
            os.remove(PID_FILE)
    except Exception:
        pass
    Gtk.main_quit()

def main():
    GLib.set_prgname("youtube-miniplayer")
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        with open(PID_FILE, "w") as f:
            f.write(str(os.getpid()))
    except Exception:
        pass
    signal.signal(signal.SIGINT, lambda s, f: cleanup_and_quit())
    signal.signal(signal.SIGTERM, lambda s, f: cleanup_and_quit())
    win = YouTubeMiniplayer()
    win.connect("destroy", lambda w: cleanup_and_quit())
    win.show_all()
    Gtk.main()

if __name__ == "__main__":
    main()
