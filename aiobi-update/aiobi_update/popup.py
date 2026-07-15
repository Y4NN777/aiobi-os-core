# aiobi_update.popup — GTK4 + libadwaita interactive popups.
#
# Exactly three popup types, per the agreed scope — no more:
#   1. confirm(n)                     — before --apply (interactive only;
#                                        skipped by --apply -y)
#   2. run_with_progress(worker)      — during --apply, worker runs on a
#                                        background thread while a
#                                        Gtk.ProgressBar pulses
#   3. summary(succeeded, failed, ..) — after --apply completes
#
# Each popup is its own short-lived Adw.Application so the process
# exits as soon as the dialog is dismissed — aiobi-update is a CLI
# tool that occasionally raises a window, not a long-running GUI app.

from __future__ import annotations

import threading
from dataclasses import dataclass

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gtk, Gdk, GLib  # noqa: E402

APP_ID_PREFIX = "org.aiobi.Update"

CSS = b"""
.aiobi-accent { color: #7233CD; }
.aiobi-primary { background: #7233CD; color: #F8F8F9; }
"""


def _apply_aiobi_css() -> None:
    provider = Gtk.CssProvider()
    provider.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_display(
        Gdk.Display.get_default(),
        provider,
        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
    )


@dataclass
class ApplyResult:
    succeeded: list[str]
    failed: list[str]
    reboot_required: bool


def confirm(count: int) -> bool:
    """Blocking confirm dialog: 'N updates available — apply now?'.
    Returns True if the user chose Apply, False for Cancel/close."""
    answer = {"apply": False}

    def on_activate(app: Adw.Application) -> None:
        _apply_aiobi_css()
        window = Adw.ApplicationWindow(application=app, title="Aïobi OS Update")
        window.set_default_size(420, 180)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        toolbar.add_top_bar(header)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16,
                       margin_top=24, margin_bottom=24, margin_start=24, margin_end=24)
        label = Gtk.Label(
            label=f"{count} update{'s' if count != 1 else ''} available for Aïobi OS.\n"
                  "Apply them now?",
            justify=Gtk.Justification.CENTER,
            wrap=True,
        )
        label.add_css_class("aiobi-accent")
        box.append(label)

        button_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12,
                              halign=Gtk.Align.CENTER)
        cancel_btn = Gtk.Button(label="Cancel")
        apply_btn = Gtk.Button(label="Apply now")
        apply_btn.add_css_class("aiobi-primary")
        apply_btn.add_css_class("suggested-action")

        def do_cancel(_btn: Gtk.Button) -> None:
            answer["apply"] = False
            app.quit()

        def do_apply(_btn: Gtk.Button) -> None:
            answer["apply"] = True
            app.quit()

        cancel_btn.connect("clicked", do_cancel)
        apply_btn.connect("clicked", do_apply)
        button_box.append(cancel_btn)
        button_box.append(apply_btn)
        box.append(button_box)

        toolbar.set_content(box)
        window.set_content(toolbar)
        window.connect("close-request", lambda *_: (app.quit(), False)[1])
        window.present()

    app = Adw.Application(application_id=f"{APP_ID_PREFIX}.Confirm")
    app.connect("activate", on_activate)
    app.run(None)
    return answer["apply"]


def run_with_progress(worker) -> ApplyResult:
    """Show a progress window with a pulsing Gtk.ProgressBar while
    `worker()` runs on a background thread. `worker` must return an
    ApplyResult. GLib.idle_add marshals the pulse + the final quit
    back onto the GTK main thread, since GTK widgets are not
    thread-safe to touch directly from the worker thread."""
    result_holder: dict[str, ApplyResult] = {}

    def on_activate(app: Adw.Application) -> None:
        _apply_aiobi_css()
        window = Adw.ApplicationWindow(application=app, title="Aïobi OS Update")
        window.set_default_size(420, 140)
        window.set_deletable(False)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar(show_end_title_buttons=False, show_start_title_buttons=False)
        toolbar.add_top_bar(header)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16,
                       margin_top=24, margin_bottom=24, margin_start=24, margin_end=24)
        label = Gtk.Label(label="Applying updates…")
        label.add_css_class("aiobi-accent")
        box.append(label)

        progress = Gtk.ProgressBar(show_text=False)
        box.append(progress)

        toolbar.set_content(box)
        window.set_content(toolbar)
        window.present()

        def pulse() -> bool:
            progress.pulse()
            return True  # keep the GLib.timeout_add loop running

        pulse_id = GLib.timeout_add(150, pulse)

        def run_worker() -> None:
            outcome = worker()

            def finish() -> bool:
                GLib.source_remove(pulse_id)
                result_holder["result"] = outcome
                app.quit()
                return False

            GLib.idle_add(finish)

        threading.Thread(target=run_worker, daemon=True).start()

    app = Adw.Application(application_id=f"{APP_ID_PREFIX}.Progress")
    app.connect("activate", on_activate)
    app.run(None)
    return result_holder["result"]


def summary(succeeded: list[str], failed: list[str], reboot_required: bool) -> None:
    """Blocking summary dialog shown after --apply completes."""

    def on_activate(app: Adw.Application) -> None:
        _apply_aiobi_css()
        window = Adw.ApplicationWindow(application=app, title="Aïobi OS Update — summary")
        window.set_default_size(460, 240)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        toolbar.add_top_bar(header)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12,
                       margin_top=24, margin_bottom=24, margin_start=24, margin_end=24)

        title = Gtk.Label(
            label=f"{len(succeeded)} package(s) updated"
                  + (f", {len(failed)} failed" if failed else ""),
            justify=Gtk.Justification.CENTER,
        )
        title.add_css_class("aiobi-accent")
        box.append(title)

        if failed:
            failed_label = Gtk.Label(
                label="Failed: " + ", ".join(failed),
                wrap=True,
                justify=Gtk.Justification.CENTER,
            )
            box.append(failed_label)

        if reboot_required:
            reboot_label = Gtk.Label(
                label="A reboot is required to finish applying these updates.",
                wrap=True,
                justify=Gtk.Justification.CENTER,
            )
            box.append(reboot_label)

        close_btn = Gtk.Button(label="Close", halign=Gtk.Align.CENTER)
        close_btn.add_css_class("aiobi-primary")
        close_btn.connect("clicked", lambda _btn: app.quit())
        box.append(close_btn)

        toolbar.set_content(box)
        window.set_content(toolbar)
        window.connect("close-request", lambda *_: (app.quit(), False)[1])
        window.present()

    app = Adw.Application(application_id=f"{APP_ID_PREFIX}.Summary")
    app.connect("activate", on_activate)
    app.run(None)
