#!/usr/bin/env python3
"""
Calendário Interativo Personalizado em GTK3 para Hyprland / Waybar
Grid customizado com centralização perfeita do dia e navegação fluida por meses e anos.
"""
import sys
import os
import signal
import calendar
from datetime import datetime, date
import gi

gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GLib

MONTHS_PT = [
    "Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
    "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"
]
WEEKDAYS_PT = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"]

class CalendarWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="Calendário")
        self.set_name("calendar-popup")
        self.set_role("calendar-popup")
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_keep_above(True)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)

        now = datetime.now()
        self.view_year = now.year
        self.view_month = now.month
        self.selected_date = now.date()

        css_provider = Gtk.CssProvider()
        css = """
        window {
            background-color: #000000;
            border: 2px solid #cba6f7;
            border-radius: 16px;
        }
        .current-clock {
            color: #cba6f7;
            font-size: 14px;
            font-weight: bold;
        }
        .view-label {
            color: #f5f5fa;
            font-size: 15px;
            font-weight: bold;
            min-width: 150px;
        }
        button.nav-btn {
            background-image: none;
            background-color: #11111b;
            color: #cba6f7;
            border: 1px solid #313244;
            border-radius: 8px;
            padding: 4px 10px;
            font-size: 13px;
            font-weight: bold;
            box-shadow: none;
            outline: none;
        }
        button.nav-btn:hover {
            background-image: none;
            background-color: #cba6f7;
            color: #000000;
            border-color: #cba6f7;
        }
        button.today-btn {
            background-image: none;
            background-color: #181825;
            color: #cdd6f4;
            border: 1px solid #45475a;
            border-radius: 8px;
            padding: 4px 12px;
            font-size: 12px;
            font-weight: bold;
            box-shadow: none;
            outline: none;
        }
        button.today-btn:hover {
            background-image: none;
            background-color: #cba6f7;
            color: #000000;
            border-color: #cba6f7;
        }
        .hint-label {
            color: #6c7086;
            font-size: 11px;
        }
        button.close-btn {
            background-image: none;
            background-color: transparent;
            color: #a6adc8;
            font-size: 15px;
            border: none;
            box-shadow: none;
            outline: none;
            padding: 2px 6px;
        }
        button.close-btn:hover {
            background-image: none;
            background-color: transparent;
            color: #f38ba8;
        }
        .calendar-card {
            background-color: #0a0a0f;
            border: 1px solid #1e1e2e;
            border-radius: 10px;
            padding: 10px;
        }
        .weekday-label {
            color: #cba6f7;
            font-size: 13px;
            font-weight: bold;
            min-width: 38px;
            min-height: 28px;
        }
        button.day-btn {
            background-image: none;
            background-color: transparent;
            box-shadow: none;
            outline: none;
            color: #cdd6f4;
            border: none;
            border-radius: 8px;
            font-size: 13px;
            font-weight: 500;
            min-width: 38px;
            min-height: 38px;
            padding: 0;
            margin: 2px;
        }
        button.day-btn:hover {
            background-image: none;
            background-color: rgba(203, 166, 247, 0.20);
            color: #ffffff;
        }
        button.day-btn.other-month {
            color: #585b70;
        }
        button.day-btn.today:not(.selected) {
            border: 1px solid #cba6f7;
            color: #cba6f7;
            font-weight: bold;
        }
        button.day-btn.selected,
        button.day-btn.selected:focus,
        button.day-btn.selected:active {
            background-image: none;
            background-color: #cba6f7;
            color: #000000;
            font-weight: bold;
            box-shadow: none;
        }
        button.day-btn.selected:hover {
            background-image: none;
            background-color: #b4befe;
            color: #000000;
        }
        """
        css_provider.load_from_data(css.encode())
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        # Container principal com padding garantido em todas as bordas
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        vbox.set_margin_top(16)
        vbox.set_margin_bottom(16)
        vbox.set_margin_start(18)
        vbox.set_margin_end(18)
        self.add(vbox)

        # Barra Superior: Apenas Relógio na esquerda e Fechar na direita (Sem título "Calendário")
        top_bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        
        self.clock_label = Gtk.Label()
        self.clock_label.get_style_context().add_class("current-clock")
        self.update_clock()
        top_bar.pack_start(self.clock_label, False, False, 0)

        # Espaçador
        top_bar.pack_start(Gtk.Box(), True, True, 0)

        close_btn = Gtk.Button(label="✕")
        close_btn.get_style_context().add_class("close-btn")
        close_btn.set_tooltip_text("Fechar (Esc)")
        close_btn.connect("clicked", lambda b: Gtk.main_quit())
        self.set_hand_cursor(close_btn)
        top_bar.pack_start(close_btn, False, False, 0)

        vbox.pack_start(top_bar, False, False, 0)

        # Barra de Navegação: Ano Anterior, Mês Anterior, Rótulo, Próximo Mês, Próximo Ano
        nav_bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)

        btn_prev_year = Gtk.Button(label="«")
        btn_prev_year.get_style_context().add_class("nav-btn")
        btn_prev_year.set_tooltip_text("Ano anterior (PageDown / Seta Baixo)")
        btn_prev_year.connect("clicked", lambda b: self.change_year(-1))
        self.set_hand_cursor(btn_prev_year)
        nav_bar.pack_start(btn_prev_year, False, False, 0)

        btn_prev_month = Gtk.Button(label="‹")
        btn_prev_month.get_style_context().add_class("nav-btn")
        btn_prev_month.set_tooltip_text("Mês anterior (Seta Esquerda)")
        btn_prev_month.connect("clicked", lambda b: self.change_month(-1))
        self.set_hand_cursor(btn_prev_month)
        nav_bar.pack_start(btn_prev_month, False, False, 0)

        self.view_label = Gtk.Label()
        self.view_label.get_style_context().add_class("view-label")
        nav_bar.pack_start(self.view_label, True, True, 0)

        btn_next_month = Gtk.Button(label="›")
        btn_next_month.get_style_context().add_class("nav-btn")
        btn_next_month.set_tooltip_text("Próximo mês (Seta Direita)")
        btn_next_month.connect("clicked", lambda b: self.change_month(1))
        self.set_hand_cursor(btn_next_month)
        nav_bar.pack_start(btn_next_month, False, False, 0)

        btn_next_year = Gtk.Button(label="»")
        btn_next_year.get_style_context().add_class("nav-btn")
        btn_next_year.set_tooltip_text("Próximo ano (PageUp / Seta Cima)")
        btn_next_year.connect("clicked", lambda b: self.change_year(1))
        self.set_hand_cursor(btn_next_year)
        nav_bar.pack_start(btn_next_year, False, False, 0)

        vbox.pack_start(nav_bar, False, False, 0)

        # Container do Card do Calendário
        cal_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        cal_box.get_style_context().add_class("calendar-card")
        vbox.pack_start(cal_box, True, True, 0)

        # Grid dos dias da semana
        weekdays_grid = Gtk.Grid()
        weekdays_grid.set_column_homogeneous(True)
        for i, name in enumerate(WEEKDAYS_PT):
            lbl = Gtk.Label(label=name)
            lbl.get_style_context().add_class("weekday-label")
            weekdays_grid.attach(lbl, i, 0, 1, 1)
        cal_box.pack_start(weekdays_grid, False, False, 0)

        # Grid dos dias do mês
        self.days_grid = Gtk.Grid()
        self.days_grid.set_column_homogeneous(True)
        self.days_grid.set_row_homogeneous(True)
        cal_box.pack_start(self.days_grid, True, True, 0)

        # Barra Inferior: Botão Hoje e Dica
        bottom_bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        
        btn_today = Gtk.Button(label="Ir para Hoje")
        btn_today.get_style_context().add_class("today-btn")
        btn_today.set_tooltip_text("Voltar para a data de hoje (Home)")
        btn_today.connect("clicked", lambda b: self.go_today())
        self.set_hand_cursor(btn_today)
        bottom_bar.pack_start(btn_today, False, False, 0)

        bottom_bar.pack_start(Gtk.Box(), True, True, 0)

        hint_label = Gtk.Label(label="Navegue com setas ou scroll")
        hint_label.get_style_context().add_class("hint-label")
        bottom_bar.pack_start(hint_label, False, False, 0)

        vbox.pack_start(bottom_bar, False, False, 0)

        # Conectar eventos de teclado e scroll
        self.connect("key-press-event", self.on_key_press)
        self.add_events(Gdk.EventMask.SCROLL_MASK)
        self.connect("scroll-event", self.on_scroll)

        # Renderizar dias iniciais
        self.render_days()
        GLib.timeout_add_seconds(1, self.update_clock)

    def set_hand_cursor(self, widget):
        def on_enter(w, event):
            win = w.get_window()
            if win:
                display = win.get_display()
                cursor = Gdk.Cursor.new_from_name(display, "pointer")
                win.set_cursor(cursor)
            return False

        def on_leave(w, event):
            win = w.get_window()
            if win:
                win.set_cursor(None)
            return False

        def on_realize(w):
            win = w.get_window()
            if win:
                display = win.get_display()
                cursor = Gdk.Cursor.new_from_name(display, "pointer")
                win.set_cursor(cursor)

        widget.add_events(Gdk.EventMask.ENTER_NOTIFY_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK)
        widget.connect("enter-notify-event", on_enter)
        widget.connect("leave-notify-event", on_leave)
        widget.connect("realize", on_realize)
        if widget.get_realized():
            on_realize(widget)

    def update_clock(self):
        now = datetime.now()
        self.clock_label.set_text(now.strftime("%H:%M:%S"))
        return True

    def render_days(self):
        # Limpar grid anterior
        for child in self.days_grid.get_children():
            self.days_grid.remove(child)

        month_name = MONTHS_PT[self.view_month - 1]
        self.view_label.set_text(f"{month_name} {self.view_year}")

        today = datetime.now().date()
        cal = calendar.Calendar(firstweekday=6) # Domingo = 6
        weeks = cal.monthdatescalendar(self.view_year, self.view_month)

        for row, week in enumerate(weeks):
            for col, d in enumerate(week):
                btn = Gtk.Button(label=str(d.day))
                btn.get_style_context().add_class("day-btn")

                if d.month != self.view_month:
                    btn.get_style_context().add_class("other-month")

                if d == today:
                    btn.get_style_context().add_class("today")

                if d == self.selected_date:
                    btn.get_style_context().add_class("selected")

                self.set_hand_cursor(btn)
                btn.connect("clicked", self.on_day_clicked, d)
                self.days_grid.attach(btn, col, row, 1, 1)

        self.days_grid.show_all()

    def on_day_clicked(self, button, d):
        self.selected_date = d
        if d.month != self.view_month or d.year != self.view_year:
            self.view_month = d.month
            self.view_year = d.year
        self.render_days()

    def change_month(self, delta):
        month = self.view_month + delta
        year = self.view_year
        if month < 1:
            month = 12
            year -= 1
        elif month > 12:
            month = 1
            year += 1
        self.view_month = month
        self.view_year = year
        self.render_days()

    def change_year(self, delta):
        self.view_year += delta
        self.render_days()

    def go_today(self):
        today = datetime.now().date()
        self.view_year = today.year
        self.view_month = today.month
        self.selected_date = today
        self.render_days()

    def on_scroll(self, widget, event):
        if event.direction == Gdk.ScrollDirection.UP:
            self.change_month(-1)
            return True
        elif event.direction == Gdk.ScrollDirection.DOWN:
            self.change_month(1)
            return True
        return False

    def on_key_press(self, widget, event):
        keyval = event.keyval
        if keyval in (Gdk.KEY_Escape, Gdk.KEY_q):
            Gtk.main_quit()
            return True
        elif keyval in (Gdk.KEY_Left, Gdk.KEY_h):
            self.change_month(-1)
            return True
        elif keyval in (Gdk.KEY_Right, Gdk.KEY_l):
            self.change_month(1)
            return True
        elif keyval in (Gdk.KEY_Up, Gdk.KEY_k, Gdk.KEY_Page_Up):
            self.change_year(1)
            return True
        elif keyval in (Gdk.KEY_Down, Gdk.KEY_j, Gdk.KEY_Page_Down):
            self.change_year(-1)
            return True
        elif keyval == Gdk.KEY_Home:
            self.go_today()
            return True
        return False

def main():
    signal.signal(signal.SIGINT, lambda s, f: Gtk.main_quit())
    signal.signal(signal.SIGTERM, lambda s, f: Gtk.main_quit())
    win = CalendarWindow()
    win.show_all()
    Gtk.main()

if __name__ == "__main__":
    main()
