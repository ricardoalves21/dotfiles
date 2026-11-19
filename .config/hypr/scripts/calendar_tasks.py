#!/usr/bin/env python3
"""
Módulo e Daemon de Gerenciamento de Tarefas do Calendário para Hyprland / Waybar.
Gerencia tarefas com prioridade, lembretes de antecedência, avisos sonoros e status no Waybar.
"""
import sys
import os
import json
import time
import subprocess
from datetime import datetime, timedelta

DATA_DIR = os.path.expanduser("~/.local/share/hypr")
TASKS_FILE = os.path.join(DATA_DIR, "calendar-tasks.json")
SOUND_BELL = "/usr/share/sounds/Yaru/stereo/bell.oga"
SOUND_MSG = "/usr/share/sounds/Yaru/stereo/message.oga"

REMINDER_OPTIONS = [
    (0, "Sem lembrete"),
    (10, "10 minutos antes"),
    (30, "30 minutos antes"),
    (60, "1 hora antes"),
    (120, "2 horas antes"),
    (180, "3 horas antes"),
    (1440, "1 dia antes"),
    (2880, "2 dias antes")
]

def ensure_storage():
    os.makedirs(DATA_DIR, exist_ok=True)
    if not os.path.exists(TASKS_FILE):
        with open(TASKS_FILE, "w", encoding="utf-8") as f:
            json.dump([], f, ensure_ascii=False, indent=2)

def load_tasks():
    ensure_storage()
    try:
        with open(TASKS_FILE, "r", encoding="utf-8") as f:
            tasks = json.load(f)
            if isinstance(tasks, list):
                return tasks
    except Exception:
        pass
    return []

def save_tasks(tasks):
    ensure_storage()
    tmp_path = TASKS_FILE + f".tmp.{os.getpid()}"
    try:
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(tasks, f, ensure_ascii=False, indent=2)
        os.replace(tmp_path, TASKS_FILE)
    except Exception as e:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except OSError:
                pass
        raise e

def notify_waybar():
    try:
        subprocess.run(["pkill", "-RTMIN+12", "waybar"], stderr=subprocess.DEVNULL)
    except Exception:
        pass

def play_sound(filepath):
    if os.path.exists(filepath):
        try:
            subprocess.Popen(["pw-play", filepath], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass

def show_popup_toast(title, message, urgency="normal"):
    # Dispara popup gráfico em processo desacoplado
    script = os.path.abspath(__file__)
    try:
        subprocess.Popen(["python3", script, "popup", title, message, urgency],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass

def send_notification(title, message, urgency="normal"):
    # Tenta notify-send padrão sem expirar (-t 0)
    try:
        subprocess.run(["notify-send", "-a", "Calendário", "-u", urgency, "-t", "0", title, message],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass
    # Também exibe popup GTK direto para garantir visibilidade
    show_popup_toast(title, message, urgency)

def add_task(date_str, time_str, description, priority=False, reminder_min=0):
    tasks = load_tasks()
    task_id = str(int(time.time() * 1000))
    new_task = {
        "id": task_id,
        "date": date_str.strip(),
        "time": time_str.strip(),
        "description": description.strip(),
        "priority": bool(priority),
        "reminder_min": int(reminder_min),
        "completed": False,
        "reminded": False,
        "due_alerted": False,
        "created_at": datetime.now().isoformat()
    }
    tasks.append(new_task)
    save_tasks(tasks)
    notify_waybar()
    return new_task

def delete_task(task_id):
    tasks = load_tasks()
    new_tasks = [t for t in tasks if str(t.get("id")) != str(task_id)]
    if len(new_tasks) != len(tasks):
        save_tasks(new_tasks)
        notify_waybar()
        return True
    return False

def edit_task(task_id, date_str, time_str, description, priority=False, reminder_min=0):
    tasks = load_tasks()
    updated = False
    for t in tasks:
        if str(t.get("id")) == str(task_id):
            old_time = t.get("time")
            old_date = t.get("date")
            t["date"] = date_str.strip()
            t["time"] = time_str.strip()
            t["description"] = description.strip()
            t["priority"] = bool(priority)
            t["reminder_min"] = int(reminder_min)
            if old_time != t["time"] or old_date != t["date"]:
                try:
                    new_dt = datetime.strptime(f"{t['date']} {t['time']}", "%Y-%m-%d %H:%M")
                    if new_dt > datetime.now():
                        t["reminded"] = False
                        t["due_alerted"] = False
                except ValueError:
                    pass
            updated = True
            break
    if updated:
        save_tasks(tasks)
        notify_waybar()
        return True
    return False

def toggle_task(task_id):
    tasks = load_tasks()
    updated = False
    for t in tasks:
        if str(t.get("id")) == str(task_id):
            t["completed"] = not t.get("completed", False)
            updated = True
            break
    if updated:
        save_tasks(tasks)
        notify_waybar()
        return True
    return False

def get_tasks_for_date(date_str):
    tasks = load_tasks()
    matched = [t for t in tasks if t.get("date") == date_str]
    matched.sort(key=lambda t: t.get("time", "00:00"))
    return matched

def get_month_task_indicators(year, month):
    tasks = load_tasks()
    prefix = f"{year:04d}-{month:02d}-"
    indicators = {}
    for t in tasks:
        d_str = t.get("date", "")
        if d_str.startswith(prefix) and not t.get("completed", False):
            try:
                day_num = int(d_str.split("-")[2])
                if day_num not in indicators:
                    indicators[day_num] = {"count": 0, "has_priority": False}
                indicators[day_num]["count"] += 1
                if t.get("priority"):
                    indicators[day_num]["has_priority"] = True
            except (ValueError, IndexError):
                pass
    return indicators

def format_reminder_label(minutes):
    if minutes == 10:
        return "10 minutos"
    elif minutes == 30:
        return "30 minutos"
    elif minutes == 60:
        return "1 hora"
    elif minutes == 120:
        return "2 horas"
    elif minutes == 180:
        return "3 horas"
    elif minutes == 1440:
        return "1 dia"
    elif minutes == 2880:
        return "2 dias"
    return f"{minutes} min"

def get_waybar_status():
    tasks = load_tasks()
    now = datetime.now()
    today_str = now.strftime("%Y-%m-%d")

    # 1. Verificar se há alguma tarefa com alerta ativo (no horário agora)
    due_priority_task = None
    due_tasks = []
    upcoming_priority_tasks = []

    for t in tasks:
        if t.get("completed"):
            continue
        try:
            task_dt = datetime.strptime(f"{t['date']} {t['time']}", "%Y-%m-%d %H:%M")
        except ValueError:
            continue

        # Janela de alerta: desde a hora marcada até 30 minutos depois
        if task_dt <= now <= (task_dt + timedelta(minutes=30)):
            if t.get("priority"):
                due_priority_task = t
                break
            else:
                due_tasks.append(t)
        elif t.get("priority") and task_dt > now:
            upcoming_priority_tasks.append((task_dt, t))

    # Se há tarefa prioritária na hora marcada agora:
    if due_priority_task:
        desc = due_priority_task.get("description", "")
        short_desc = desc if len(desc) <= 24 else desc[:21] + "..."
        time_str = due_priority_task.get("time", "")
        return {
            "text": f"󰀨 ALERTA: {time_str} {short_desc}",
            "tooltip": f"🚨 TAREFA NO HORÁRIO!\nHorário: {time_str}\nPrioridade: Alta\nDescrição: {desc}\n\nClique para abrir o calendário",
            "class": "due"
        }

    # Se não houver prioritária na hora, mas houver outra tarefa no horário:
    if due_tasks:
        dt = due_tasks[0]
        desc = dt.get("description", "")
        short_desc = desc if len(desc) <= 24 else desc[:21] + "..."
        time_str = dt.get("time", "")
        return {
            "text": f"󰀨 ALERTA: {time_str} {short_desc}",
            "tooltip": f"🚨 TAREFA NO HORÁRIO!\nHorário: {time_str}\nDescrição: {desc}\n\nClique para abrir o calendário",
            "class": "due"
        }

    # 2. Próxima tarefa prioritária (hoje ou próximos dias)
    upcoming_priority_tasks.sort(key=lambda x: x[0])
    if upcoming_priority_tasks:
        next_dt, next_task = upcoming_priority_tasks[0]
        desc = next_task.get("description", "")
        short_desc = desc if len(desc) <= 26 else desc[:23] + "..."
        time_str = next_task.get("time", "")
        date_str = next_task.get("date", "")

        is_today = (date_str == today_str)
        date_label = "" if is_today else f"{next_dt.strftime('%d/%m')} "

        return {
            "text": f"󰀨 {date_label}{time_str} {short_desc}",
            "tooltip": f"⭐ Próxima Tarefa Prioritária:\nData: {'Hoje' if is_today else date_str}\nHorário: {time_str}\nDescrição: {desc}\n\nClique para abrir o calendário",
            "class": "priority"
        }

    # Nenhuma tarefa prioritária ativa: Waybar fica vazio/oculto
    return {
        "text": "",
        "tooltip": "Nenhuma tarefa prioritária agendada\nClique para abrir o calendário",
        "class": "empty"
    }

def run_daemon():
    print("Iniciando Daemon de Tarefas do Calendário...")
    while True:
        try:
            tasks = load_tasks()
            now = datetime.now()
            today_str = now.strftime("%Y-%m-%d")
            changed = False

            for t in tasks:
                if t.get("completed"):
                    continue

                try:
                    task_dt = datetime.strptime(f"{t['date']} {t['time']}", "%Y-%m-%d %H:%M")
                except ValueError:
                    continue

                desc = t.get("description", "Sem descrição")
                is_priority = t.get("priority", False)
                prio_tag = "⭐ [PRIORIDADE] " if is_priority else ""

                # 1. Checar lembrete de antecedência (10m, 30m, 1h, 2h, 3h)
                remind_min = t.get("reminder_min", 0)
                if remind_min > 0 and not t.get("reminded"):
                    remind_dt = task_dt - timedelta(minutes=remind_min)
                    if remind_dt <= now < task_dt:
                        lbl = format_reminder_label(remind_min)
                        title = f"{prio_tag}Lembrete ({lbl} de antecedência)"
                        msg = f"{t['time']} - {desc}"
                        play_sound(SOUND_MSG)
                        send_notification(title, msg, urgency="normal")
                        t["reminded"] = True
                        changed = True

                # 2. Checar alarme no horário exato da tarefa
                if now >= task_dt and not t.get("due_alerted"):
                    # Só dispara se o atraso for de no máximo 2 horas (evita spam após reiniciar sistema)
                    if (now - task_dt) <= timedelta(hours=2):
                        title = f"🚨 {prio_tag}HORA DA TAREFA ({t['time']})"
                        msg = desc
                        play_sound(SOUND_BELL)
                        send_notification(title, msg, urgency="critical")
                        t["due_alerted"] = True
                        changed = True
                    else:
                        t["due_alerted"] = True
                        changed = True

            if changed:
                save_tasks(tasks)
                notify_waybar()

        except Exception as e:
            sys.stderr.write(f"Erro no daemon de tarefas: {e}\n")

        time.sleep(3)

def run_popup(title, message, urgency="normal"):
    import gi
    gi.require_version('Gtk', '3.0')
    from gi.repository import Gtk, Gdk, GLib

    class ToastWindow(Gtk.Window):
        def __init__(self):
            super().__init__(title="Notificação de Tarefa")
            self.set_name("task-toast-popup")
            self.set_role("task-toast-popup")
            self.set_decorated(False)
            self.set_resizable(False)
            self.set_keep_above(True)
            self.set_skip_taskbar_hint(True)
            self.set_skip_pager_hint(True)

            is_critical = (urgency == "critical")
            border_color = "#f38ba8" if is_critical else "#cba6f7"
            accent_color = "#f38ba8" if is_critical else "#cba6f7"

            css_provider = Gtk.CssProvider()
            css = f"""
            window {{
                background-color: #0b0b12;
                border: 2px solid {border_color};
                border-radius: 14px;
            }}
            .toast-title {{
                color: {accent_color};
                font-size: 14px;
                font-weight: bold;
            }}
            .toast-msg {{
                color: #cdd6f4;
                font-size: 13px;
            }}
            button.ok-btn {{
                background-image: none;
                background-color: {border_color};
                color: #000000;
                font-size: 12px;
                font-weight: bold;
                border-radius: 8px;
                padding: 4px 14px;
                border: none;
            }}
            button.ok-btn:hover {{
                background-color: #ffffff;
            }}
            """
            css_provider.load_from_data(css.encode())
            Gtk.StyleContext.add_provider_for_screen(
                Gdk.Screen.get_default(),
                css_provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            )

            vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
            vbox.set_margin_top(14)
            vbox.set_margin_bottom(14)
            vbox.set_margin_start(16)
            vbox.set_margin_end(16)
            self.add(vbox)

            # Cabeçalho
            lbl_title = Gtk.Label(label=title)
            lbl_title.set_xalign(0)
            lbl_title.get_style_context().add_class("toast-title")
            vbox.pack_start(lbl_title, False, False, 0)

            # Mensagem
            lbl_msg = Gtk.Label(label=message)
            lbl_msg.set_line_wrap(True)
            lbl_msg.set_max_width_chars(36)
            lbl_msg.set_xalign(0)
            lbl_msg.get_style_context().add_class("toast-msg")
            vbox.pack_start(lbl_msg, False, False, 0)

            # Botão fechar
            btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
            btn_box.pack_start(Gtk.Box(), True, True, 0)
            ok_btn = Gtk.Button(label="Entendido")
            ok_btn.get_style_context().add_class("ok-btn")
            ok_btn.connect("clicked", lambda b: Gtk.main_quit())
            
            # Cursor pointer
            def on_enter(w, event):
                win = w.get_window()
                if win:
                    cursor = Gdk.Cursor.new_from_name(win.get_display(), "pointer")
                    win.set_cursor(cursor)
                return False
            def on_leave(w, event):
                win = w.get_window()
                if win:
                    win.set_cursor(None)
                return False
            ok_btn.add_events(Gdk.EventMask.ENTER_NOTIFY_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK)
            ok_btn.connect("enter-notify-event", on_enter)
            ok_btn.connect("leave-notify-event", on_leave)

            btn_box.pack_start(ok_btn, False, False, 0)
            vbox.pack_start(btn_box, False, False, 0)

            # Posicionar no canto superior direito
            self.set_position(Gtk.WindowPosition.NONE)
            display = Gdk.Display.get_default()
            monitor = display.get_primary_monitor() or display.get_monitor(0)
            if monitor:
                geo = monitor.get_geometry()
                self.move(geo.x + geo.width - 360, geo.y + 48)

            # Teclado: Enter, Espaço ou Esc também fecham
            self.connect("key-press-event", self.on_key_press)

        def on_key_press(self, widget, event):
            if event.keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter, Gdk.KEY_Escape, Gdk.KEY_space):
                Gtk.main_quit()
                return True
            return False

    win = ToastWindow()
    win.show_all()
    Gtk.main()

def main():
    if len(sys.argv) > 1:
        cmd = sys.argv[1]
        if cmd == "status":
            st = get_waybar_status()
            print(json.dumps(st, ensure_ascii=False))
        elif cmd == "daemon":
            run_daemon()
        elif cmd == "popup":
            t = sys.argv[2] if len(sys.argv) > 2 else "Lembrete"
            m = sys.argv[3] if len(sys.argv) > 3 else "Mensagem"
            u = sys.argv[4] if len(sys.argv) > 4 else "normal"
            run_popup(t, m, u)
        elif cmd == "notify-waybar":
            notify_waybar()
        else:
            print(f"Comando desconhecido: {cmd}")
    else:
        st = get_waybar_status()
        print(json.dumps(st, ensure_ascii=False))

if __name__ == "__main__":
    main()
