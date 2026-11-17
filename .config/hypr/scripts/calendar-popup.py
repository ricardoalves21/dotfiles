#!/usr/bin/env python3
"""
Calendário Interativo Personalizado em GTK3 para Hyprland / Waybar
Inclui Grid customizado do mês e Painel de Gerenciamento de Tarefas diárias com:
- Tarefas por data
- Marcação de Prioridade
- Lembretes de antecedência (10m, 30m, 1h, 2h, 3h)
- Sincronização em tempo real com Waybar e daemon de alertas
"""
import sys
import os
import signal
import calendar
from datetime import datetime, date, timedelta
import gi

gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GLib

# Adicionar caminho para importar calendar-tasks
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import calendar_tasks
except ImportError:
    calendar_tasks = None

MONTHS_PT = [
    "Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
    "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"
]
WEEKDAYS_PT = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"]
WEEKDAYS_FULL_PT = ["Segunda-feira", "Terça-feira", "Quarta-feira", "Quinta-feira", "Sexta-feira", "Sábado", "Domingo"]

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
        .header-title {
            color: #f5f5fa;
            font-size: 15px;
            font-weight: bold;
        }
        .view-label {
            color: #f5f5fa;
            font-size: 15px;
            font-weight: bold;
            min-width: 140px;
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
            border-radius: 12px;
            padding: 8px;
        }
        .weekday-label {
            color: #cba6f7;
            font-size: 12px;
            font-weight: bold;
            min-width: 36px;
            min-height: 26px;
        }
        button.day-btn {
            background-image: none;
            background-color: transparent;
            box-shadow: none;
            outline: none;
            color: #cdd6f4;
            border: none;
            border-radius: 8px;
            min-width: 38px;
            min-height: 38px;
            padding: 0;
            margin: 1px;
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
        .day-num {
            font-size: 13px;
        }
        .day-dot {
            font-size: 7px;
            margin-top: -2px;
        }
        .day-dot.priority {
            color: #fab387;
        }
        .day-dot.regular {
            color: #cba6f7;
        }
        button.day-btn.selected .day-dot {
            color: #000000;
        }

        /* PAINEL DE TAREFAS */
        .tasks-panel {
            background-color: #0a0a0f;
            border: 1px solid #1e1e2e;
            border-radius: 12px;
            padding: 12px;
            min-width: 330px;
        }
        .tasks-date-title {
            color: #ffffff;
            font-size: 14px;
            font-weight: bold;
        }
        .tasks-date-sub {
            color: #a6adc8;
            font-size: 12px;
        }
        button.new-task-btn {
            background-image: none;
            background-color: #cba6f7;
            color: #000000;
            font-size: 12px;
            font-weight: bold;
            border-radius: 8px;
            padding: 5px 12px;
            border: none;
            box-shadow: none;
        }
        button.new-task-btn:hover {
            background-image: none;
            background-color: #b4befe;
        }
        .task-card {
            background-color: #11111b;
            border: 1px solid #2a2a3c;
            border-radius: 8px;
            padding: 8px 10px;
            margin-bottom: 6px;
        }
        .task-card.priority {
            border-left: 3px solid #fab387;
            background-color: rgba(250, 179, 135, 0.06);
        }
        .task-card.completed {
            opacity: 0.50;
        }
        .task-time-badge {
            color: #cba6f7;
            font-size: 12px;
            font-weight: bold;
        }
        .task-prio-badge {
            background-color: rgba(250, 179, 135, 0.20);
            color: #fab387;
            border-radius: 4px;
            padding: 1px 6px;
            font-size: 10px;
            font-weight: bold;
        }
        .task-remind-badge {
            background-color: rgba(137, 180, 250, 0.18);
            color: #89b4fa;
            border-radius: 4px;
            padding: 1px 6px;
            font-size: 10px;
        }
        .task-desc {
            color: #cdd6f4;
            font-size: 13px;
        }
        .task-desc.completed {
            text-decoration: line-through;
            color: #6c7086;
        }
        button.task-btn {
            background-image: none;
            background-color: transparent;
            border: none;
            box-shadow: none;
            color: #a6adc8;
            padding: 2px 5px;
            border-radius: 4px;
        }
        button.task-btn:hover {
            background-image: none;
            background-color: #313244;
            color: #ffffff;
        }
        button.task-btn.check:hover {
            color: #a6e3a1;
        }
        button.task-btn.del:hover {
            color: #f38ba8;
        }

        /* FORMULÁRIO DE NOVA TAREFA */
        .form-card {
            background-color: #14141f;
            border: 1px solid #cba6f7;
            border-radius: 10px;
            padding: 10px;
            margin-bottom: 10px;
        }
        .form-label {
            color: #cdd6f4;
            font-size: 12px;
            font-weight: bold;
        }
        entry {
            background-color: #1e1e2e;
            color: #cdd6f4;
            border: 1px solid #313244;
            border-radius: 6px;
            padding: 4px 8px;
            font-size: 12px;
        }
        entry:focus {
            border-color: #cba6f7;
        }
        combobox button {
            background-image: none;
            background-color: #1e1e2e;
            color: #cdd6f4;
            border: 1px solid #313244;
            border-radius: 6px;
            font-size: 12px;
            padding: 2px 6px;
        }
        checkbutton {
            color: #cdd6f4;
        }
        checkbutton check {
            background-color: #1e1e2e;
            border: 1px solid #45475a;
            border-radius: 4px;
            color: #cba6f7;
        }
        checkbutton check:checked {
            background-color: #cba6f7;
            color: #000000;
            border-color: #cba6f7;
        }
        checkbutton label {
            color: #cdd6f4;
            font-size: 12px;
            font-weight: 500;
        }
        checkbutton:hover label {
            color: #ffffff;
        }
        button.save-btn {
            background-image: none;
            background-color: #cba6f7;
            color: #000000;
            font-size: 12px;
            font-weight: bold;
            border-radius: 8px;
            padding: 5px 14px;
            border: none;
            box-shadow: none;
        }
        button.save-btn:hover {
            background-image: none;
            background-color: #b4befe;
            color: #000000;
        }
        button.cancel-btn {
            background-image: none;
            background-color: #181825;
            color: #cdd6f4;
            font-size: 12px;
            font-weight: 500;
            border-radius: 8px;
            padding: 5px 12px;
            border: 1px solid #313244;
            box-shadow: none;
        }
        button.cancel-btn:hover {
            background-image: none;
            background-color: #313244;
            color: #ffffff;
            border-color: #45475a;
        }
        separator {
            background-color: #2a2a3c;
        }
        """
        css_provider.load_from_data(css.encode())
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        # Container principal com padding
        main_vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        main_vbox.set_margin_top(16)
        main_vbox.set_margin_bottom(16)
        main_vbox.set_margin_start(18)
        main_vbox.set_margin_end(18)
        self.add(main_vbox)

        # Barra Superior: Relógio na esquerda e Fechar na direita
        top_bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.clock_label = Gtk.Label()
        self.clock_label.get_style_context().add_class("current-clock")
        self.update_clock()
        top_bar.pack_start(self.clock_label, False, False, 0)

        # Título central
        top_title = Gtk.Label(label="Agenda & Calendário")
        top_title.get_style_context().add_class("header-title")
        top_bar.pack_start(top_title, True, True, 0)

        close_btn = Gtk.Button(label="✕")
        close_btn.get_style_context().add_class("close-btn")
        close_btn.set_tooltip_text("Fechar (Esc)")
        close_btn.connect("clicked", lambda b: Gtk.main_quit())
        self.set_hand_cursor(close_btn)
        top_bar.pack_start(close_btn, False, False, 0)
        main_vbox.pack_start(top_bar, False, False, 0)

        # Corpo com 2 colunas: Calendário na esquerda | Separador | Tarefas na direita
        body_hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
        main_vbox.pack_start(body_hbox, True, True, 0)

        # === COLUNA ESQUERDA: CALENDÁRIO ===
        cal_vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        body_hbox.pack_start(cal_vbox, False, False, 0)

        # Barra de Navegação do Calendário
        nav_bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)

        btn_prev_year = Gtk.Button(label="«")
        btn_prev_year.get_style_context().add_class("nav-btn")
        btn_prev_year.set_tooltip_text("Ano anterior")
        btn_prev_year.connect("clicked", lambda b: self.change_year(-1))
        self.set_hand_cursor(btn_prev_year)
        nav_bar.pack_start(btn_prev_year, False, False, 0)

        btn_prev_month = Gtk.Button(label="‹")
        btn_prev_month.get_style_context().add_class("nav-btn")
        btn_prev_month.set_tooltip_text("Mês anterior")
        btn_prev_month.connect("clicked", lambda b: self.change_month(-1))
        self.set_hand_cursor(btn_prev_month)
        nav_bar.pack_start(btn_prev_month, False, False, 0)

        self.view_label = Gtk.Label()
        self.view_label.get_style_context().add_class("view-label")
        nav_bar.pack_start(self.view_label, True, True, 0)

        btn_next_month = Gtk.Button(label="›")
        btn_next_month.get_style_context().add_class("nav-btn")
        btn_next_month.set_tooltip_text("Próximo mês")
        btn_next_month.connect("clicked", lambda b: self.change_month(1))
        self.set_hand_cursor(btn_next_month)
        nav_bar.pack_start(btn_next_month, False, False, 0)

        btn_next_year = Gtk.Button(label="»")
        btn_next_year.get_style_context().add_class("nav-btn")
        btn_next_year.set_tooltip_text("Próximo ano")
        btn_next_year.connect("clicked", lambda b: self.change_year(1))
        self.set_hand_cursor(btn_next_year)
        nav_bar.pack_start(btn_next_year, False, False, 0)

        cal_vbox.pack_start(nav_bar, False, False, 0)

        # Card do Calendário
        cal_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        cal_box.get_style_context().add_class("calendar-card")
        cal_vbox.pack_start(cal_box, True, True, 0)

        # Dias da semana
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

        # Barra inferior do calendário
        cal_bottom_bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        btn_today = Gtk.Button(label="Ir para Hoje")
        btn_today.get_style_context().add_class("today-btn")
        btn_today.connect("clicked", lambda b: self.go_today())
        self.set_hand_cursor(btn_today)
        cal_bottom_bar.pack_start(btn_today, False, False, 0)

        cal_bottom_bar.pack_start(Gtk.Box(), True, True, 0)
        hint_label = Gtk.Label(label="Scroll para navegar")
        hint_label.get_style_context().add_class("hint-label")
        cal_bottom_bar.pack_start(hint_label, False, False, 0)
        cal_vbox.pack_start(cal_bottom_bar, False, False, 0)

        # Separador Vertical
        sep = Gtk.Separator(orientation=Gtk.Orientation.VERTICAL)
        body_hbox.pack_start(sep, False, False, 0)

        # === COLUNA DIREITA: PAINEL DE TAREFAS ===
        self.tasks_panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.tasks_panel.get_style_context().add_class("tasks-panel")
        body_hbox.pack_start(self.tasks_panel, True, True, 0)

        # Cabeçalho do Painel de Tarefas
        tasks_header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        date_titles_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        self.task_date_title = Gtk.Label()
        self.task_date_title.set_xalign(0)
        self.task_date_title.get_style_context().add_class("tasks-date-title")
        date_titles_box.pack_start(self.task_date_title, False, False, 0)

        self.task_date_sub = Gtk.Label()
        self.task_date_sub.set_xalign(0)
        self.task_date_sub.get_style_context().add_class("tasks-date-sub")
        date_titles_box.pack_start(self.task_date_sub, False, False, 0)
        tasks_header.pack_start(date_titles_box, True, True, 0)

        self.btn_new_task = Gtk.Button(label="➕ Nova Tarefa")
        self.btn_new_task.get_style_context().add_class("new-task-btn")
        self.btn_new_task.connect("clicked", lambda b: self.show_task_form())
        self.set_hand_cursor(self.btn_new_task)
        tasks_header.pack_start(self.btn_new_task, False, False, 0)
        self.tasks_panel.pack_start(tasks_header, False, False, 0)

        # FORMULÁRIO DE NOVA TAREFA (inicialmente oculto)
        self.form_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.form_box.get_style_context().add_class("form-card")
        self.form_box.set_no_show_all(True)
        self.tasks_panel.pack_start(self.form_box, False, False, 0)

        form_grid = Gtk.Grid()
        form_grid.set_column_spacing(8)
        form_grid.set_row_spacing(6)
        self.form_box.pack_start(form_grid, False, False, 0)

        # Linha 1: Horário
        lbl_time = Gtk.Label(label="Horário (HH:MM):")
        lbl_time.set_xalign(0)
        lbl_time.get_style_context().add_class("form-label")
        form_grid.attach(lbl_time, 0, 0, 1, 1)

        self.entry_time = Gtk.Entry()
        self.entry_time.set_placeholder_text("Ex: 14:30")
        self.entry_time.set_max_length(5)
        self.entry_time.set_width_chars(7)
        form_grid.attach(self.entry_time, 1, 0, 1, 1)

        # Linha 2: Descrição
        lbl_desc = Gtk.Label(label="Descrição:")
        lbl_desc.set_xalign(0)
        lbl_desc.get_style_context().add_class("form-label")
        form_grid.attach(lbl_desc, 0, 1, 1, 1)

        self.entry_desc = Gtk.Entry()
        self.entry_desc.set_placeholder_text("Ex: Reunião com equipe")
        self.entry_desc.set_hexpand(True)
        form_grid.attach(self.entry_desc, 1, 1, 1, 1)

        self.entry_time.connect("activate", lambda e: self.entry_desc.grab_focus())
        self.entry_desc.connect("activate", lambda e: self.save_task_form())

        # Linha 3: Lembrete de antecedência
        lbl_remind = Gtk.Label(label="Lembrete:")
        lbl_remind.set_xalign(0)
        lbl_remind.get_style_context().add_class("form-label")
        form_grid.attach(lbl_remind, 0, 2, 1, 1)

        self.combo_remind = Gtk.ComboBoxText()
        self.combo_remind.append("0", "Sem lembrete")
        self.combo_remind.append("10", "10 minutos antes")
        self.combo_remind.append("30", "30 minutos antes")
        self.combo_remind.append("60", "1 hora antes")
        self.combo_remind.append("120", "2 horas antes")
        self.combo_remind.append("180", "3 horas antes")
        self.combo_remind.append("1440", "1 dia antes")
        self.combo_remind.append("2880", "2 dias antes")
        self.combo_remind.set_active(0)
        form_grid.attach(self.combo_remind, 1, 2, 1, 1)

        # Linha 4: Prioridade
        self.check_priority = Gtk.CheckButton(label="⭐ Marcar como Prioridade (Exibir na Waybar)")
        self.check_priority.set_active(True)
        form_grid.attach(self.check_priority, 0, 3, 2, 1)

        # Linha 5: Botões Salvar / Cancelar
        form_actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        form_actions.pack_start(Gtk.Box(), True, True, 0)

        btn_cancel = Gtk.Button(label="Cancelar")
        btn_cancel.get_style_context().add_class("cancel-btn")
        btn_cancel.connect("clicked", lambda b: self.hide_task_form())
        self.set_hand_cursor(btn_cancel)
        form_actions.pack_start(btn_cancel, False, False, 0)

        btn_save = Gtk.Button(label="Salvar Tarefa")
        btn_save.get_style_context().add_class("save-btn")
        btn_save.connect("clicked", lambda b: self.save_task_form())
        self.set_hand_cursor(btn_save)
        form_actions.pack_start(btn_save, False, False, 0)

        self.form_box.pack_start(form_actions, False, False, 0)

        # Área de rolagem para as tarefas
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_min_content_height(260)
        self.tasks_panel.pack_start(scroll, True, True, 0)

        self.tasks_list_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        scroll.add(self.tasks_list_box)

        # Conectar eventos de teclado e scroll
        self.connect("key-press-event", self.on_key_press)
        self.add_events(Gdk.EventMask.SCROLL_MASK)
        self.connect("scroll-event", self.on_scroll)

        # Renderizar dias iniciais e tarefas
        self.render_days()
        self.render_tasks()
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

    def show_task_form(self):
        now = datetime.now()
        # Sugerir horário arredondado para próximos minutos ou hora
        sug_time = (now + timedelta(minutes=15)).strftime("%H:%M")
        self.entry_time.set_text(sug_time)
        self.entry_desc.set_text("")
        self.check_priority.set_active(True)
        self.combo_remind.set_active(1) # 10 minutos padrão
        self.form_box.set_no_show_all(False)
        self.form_box.show_all()
        self.form_box.set_no_show_all(True)
        self.btn_new_task.set_sensitive(False)
        self.entry_desc.grab_focus()

    def hide_task_form(self):
        self.form_box.hide()
        self.btn_new_task.set_sensitive(True)

    def save_task_form(self):
        time_text = self.entry_time.get_text().strip()
        desc_text = self.entry_desc.get_text().strip()

        # Validação básica de horário
        parts = time_text.split(":")
        if len(parts) != 2 or not parts[0].isdigit() or not parts[1].isdigit():
            self.entry_time.grab_focus()
            return
        h, m = int(parts[0]), int(parts[1])
        if h < 0 or h > 23 or m < 0 or m > 59:
            self.entry_time.grab_focus()
            return

        valid_time = f"{h:02d}:{m:02d}"

        if not desc_text:
            self.entry_desc.grab_focus()
            return

        priority = self.check_priority.get_active()
        try:
            reminder_min = int(self.combo_remind.get_active_id() or 0)
        except ValueError:
            reminder_min = 0

        date_str = self.selected_date.strftime("%Y-%m-%d")

        if calendar_tasks:
            calendar_tasks.add_task(date_str, valid_time, desc_text, priority, reminder_min)

        self.hide_task_form()
        self.render_days()
        self.render_tasks()

    def render_tasks(self):
        # Atualizar cabeçalho da data
        d = self.selected_date
        weekday_name = WEEKDAYS_FULL_PT[d.weekday()]
        month_name = MONTHS_PT[d.month - 1]
        self.task_date_title.set_text(f"{d.day} de {month_name} de {d.year}")

        today = datetime.now().date()
        if d == today:
            sub = f"Hoje · {weekday_name}"
        elif d == today + timedelta(days=1):
            sub = f"Amanhã · {weekday_name}"
        elif d == today - timedelta(days=1):
            sub = f"Ontem · {weekday_name}"
        else:
            sub = weekday_name
        self.task_date_sub.set_text(sub)

        # Limpar lista anterior
        for child in self.tasks_list_box.get_children():
            self.tasks_list_box.remove(child)

        date_str = d.strftime("%Y-%m-%d")
        tasks = calendar_tasks.get_tasks_for_date(date_str) if calendar_tasks else []

        if not tasks:
            empty_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
            empty_box.set_margin_top(40)
            lbl_empty_icon = Gtk.Label(label="󰃭")
            lbl_empty_icon.set_markup("<span font='32'>󰃭</span>")
            lbl_empty_icon.get_style_context().add_class("hint-label")
            empty_box.pack_start(lbl_empty_icon, False, False, 0)

            lbl_empty = Gtk.Label(label="Nenhuma tarefa para este dia")
            lbl_empty.get_style_context().add_class("hint-label")
            empty_box.pack_start(lbl_empty, False, False, 0)

            lbl_sub = Gtk.Label(label="Clique em '➕ Nova Tarefa' para agendar")
            lbl_sub.get_style_context().add_class("hint-label")
            empty_box.pack_start(lbl_sub, False, False, 0)

            self.tasks_list_box.pack_start(empty_box, True, True, 0)
        else:
            for task in tasks:
                card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
                card.get_style_context().add_class("task-card")
                if task.get("priority"):
                    card.get_style_context().add_class("priority")
                if task.get("completed"):
                    card.get_style_context().add_class("completed")

                # Linha 1 do card: Horário, Badges e Botões
                row1 = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)

                lbl_time = Gtk.Label(label=f"󰥔 {task.get('time', '00:00')}")
                lbl_time.get_style_context().add_class("task-time-badge")
                row1.pack_start(lbl_time, False, False, 0)

                if task.get("priority"):
                    lbl_prio = Gtk.Label(label="⭐ PRIORIDADE")
                    lbl_prio.get_style_context().add_class("task-prio-badge")
                    row1.pack_start(lbl_prio, False, False, 0)

                remind_min = task.get("reminder_min", 0)
                if remind_min > 0:
                    remind_lbl = calendar_tasks.format_reminder_label(remind_min) if calendar_tasks else f"{remind_min}m"
                    lbl_rem = Gtk.Label(label=f"🔔 {remind_lbl}")
                    lbl_rem.get_style_context().add_class("task-remind-badge")
                    row1.pack_start(lbl_rem, False, False, 0)

                row1.pack_start(Gtk.Box(), True, True, 0)

                # Botão Concluir
                is_comp = task.get("completed", False)
                btn_check = Gtk.Button(label="✔" if is_comp else "○")
                btn_check.get_style_context().add_class("task-btn")
                btn_check.get_style_context().add_class("check")
                btn_check.set_tooltip_text("Marcar como concluída" if not is_comp else "Reabrir tarefa")
                btn_check.connect("clicked", self.on_toggle_task, task.get("id"))
                self.set_hand_cursor(btn_check)
                row1.pack_start(btn_check, False, False, 0)

                # Botão Excluir
                btn_del = Gtk.Button(label="🗑")
                btn_del.get_style_context().add_class("task-btn")
                btn_del.get_style_context().add_class("del")
                btn_del.set_tooltip_text("Excluir tarefa")
                btn_del.connect("clicked", self.on_delete_task, task.get("id"))
                self.set_hand_cursor(btn_del)
                row1.pack_start(btn_del, False, False, 0)

                card.pack_start(row1, False, False, 0)

                # Linha 2 do card: Descrição
                lbl_desc = Gtk.Label(label=task.get("description", ""))
                lbl_desc.set_xalign(0)
                lbl_desc.set_line_wrap(True)
                lbl_desc.get_style_context().add_class("task-desc")
                if is_comp:
                    lbl_desc.get_style_context().add_class("completed")
                card.pack_start(lbl_desc, False, False, 0)

                self.tasks_list_box.pack_start(card, False, False, 0)

        self.tasks_list_box.show_all()

    def on_toggle_task(self, button, task_id):
        if calendar_tasks:
            calendar_tasks.toggle_task(task_id)
        self.render_days()
        self.render_tasks()

    def on_delete_task(self, button, task_id):
        if calendar_tasks:
            calendar_tasks.delete_task(task_id)
        self.render_days()
        self.render_tasks()

    def render_days(self):
        # Limpar grid anterior
        for child in self.days_grid.get_children():
            self.days_grid.remove(child)

        month_name = MONTHS_PT[self.view_month - 1]
        self.view_label.set_text(f"{month_name} {self.view_year}")

        today = datetime.now().date()
        cal = calendar.Calendar(firstweekday=6) # Domingo = 6
        weeks = cal.monthdatescalendar(self.view_year, self.view_month)

        indicators = calendar_tasks.get_month_task_indicators(self.view_year, self.view_month) if calendar_tasks else {}

        for row, week in enumerate(weeks):
            for col, d in enumerate(week):
                btn = Gtk.Button()
                btn.get_style_context().add_class("day-btn")

                if d.month != self.view_month:
                    btn.get_style_context().add_class("other-month")

                if d == today:
                    btn.get_style_context().add_class("today")

                if d == self.selected_date:
                    btn.get_style_context().add_class("selected")

                # Layout interno do botão: número do dia + indicador de tarefas
                btn_vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
                lbl_num = Gtk.Label(label=str(d.day))
                lbl_num.get_style_context().add_class("day-num")
                btn_vbox.pack_start(lbl_num, True, True, 0)

                # Indicador de tarefa
                has_task_info = (d.month == self.view_month and d.day in indicators)
                lbl_dot = Gtk.Label()
                lbl_dot.get_style_context().add_class("day-dot")
                if has_task_info:
                    info = indicators[d.day]
                    lbl_dot.set_text("●")
                    if info.get("has_priority"):
                        lbl_dot.get_style_context().add_class("priority")
                    else:
                        lbl_dot.get_style_context().add_class("regular")
                else:
                    lbl_dot.set_text(" ")

                btn_vbox.pack_start(lbl_dot, False, False, 0)
                btn.add(btn_vbox)

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
        self.render_tasks()

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
        self.render_tasks()

    def on_scroll(self, widget, event):
        if event.direction == Gdk.ScrollDirection.UP:
            self.change_month(-1)
            return True
        elif event.direction == Gdk.ScrollDirection.DOWN:
            self.change_month(1)
            return True
        return False

    def on_key_press(self, widget, event):
        focus = self.get_focus()
        # Se estiver digitando em um campo de entrada, não interceptar teclas normais
        if isinstance(focus, Gtk.Entry):
            if event.keyval == Gdk.KEY_Escape:
                if self.form_box.is_visible():
                    self.hide_task_form()
                    return True
                else:
                    Gtk.main_quit()
                    return True
            return False

        keyval = event.keyval
        if keyval in (Gdk.KEY_Escape, Gdk.KEY_q):
            if self.form_box.is_visible():
                self.hide_task_form()
                return True
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
        elif keyval == Gdk.KEY_n:
            self.show_task_form()
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
