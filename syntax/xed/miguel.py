# Miguel 🎸 til xed — viser fejl og advarsler fra `dsh check` direkte i
# .Dash-filer: rød bølgestreg under fejl, orange under advarsler, et ikon i
# kanten og beskeden ("mente du …?") når musen står over linjen.
#
# Installér med:  make install-xed   — og slå den til i xed under
# Rediger → Indstillinger → Udvidelsesmoduler → Miguel (Dash).

import os
import re
import shutil
import subprocess
import tempfile
import threading

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import GLib, GObject, Gdk, Gtk

try:
    gi.require_version("Xed", "1.0")
    from gi.repository import Xed
except (ValueError, ImportError):  # uden for xed (test)
    Xed = None

ANSI = re.compile(r"\x1b\[[0-9;]*m")
LINJE = re.compile(r"^\s*(✘|⚠) linje (\d+):\s*(.*)$")
HINT = re.compile(r"^\s*↳\s*(.*)$")
VENT_MS = 700  # vent så længe efter sidste tastetryk, før der tjekkes


def find_dsh():
    for kandidat in (shutil.which("dsh"),
                     os.path.expanduser("~/.local/bin/dsh"),
                     "/usr/local/bin/dsh"):
        if kandidat and os.access(kandidat, os.X_OK):
            return kandidat
    return None


def tjek(dsh, tekst):
    """Kører dsh check på teksten og giver [(linje, slags, besked)]."""
    with tempfile.NamedTemporaryFile("w", suffix=".Dash", delete=False,
                                     encoding="utf-8") as f:
        f.write(tekst)
        sti = f.name
    try:
        ud = subprocess.run([dsh, "check", sti], capture_output=True,
                            text=True, timeout=10).stdout
    except (OSError, subprocess.TimeoutExpired):
        return []
    finally:
        try:
            os.unlink(sti)
        except OSError:
            pass
    fund = []
    for raa in ud.splitlines():
        l = ANSI.sub("", raa)
        m = LINJE.match(l)
        if m:
            slags = "fejl" if m.group(1) == "✘" else "advarsel"
            fund.append([int(m.group(2)), slags, m.group(3)])
            continue
        h = HINT.match(l)
        if h and fund:
            fund[-1][2] += "\n↳ " + h.group(1)
    return [tuple(x) for x in fund]


class Miguel:
    """Hjælperen til én tekstvisning (GtkSource.View)."""

    def __init__(self, view):
        self.view = view
        self.buf = view.get_buffer()
        self.dsh = find_dsh()
        self.fund = {}       # linje → [(slags, besked)]
        self.vent = 0
        self.nr = 0          # hvert tjek får et nummer; kun det nyeste gælder
        self.signaler = []
        tabel = self.buf.get_tag_table()
        self.tag_fejl = tabel.lookup("miguel-fejl") or self.buf.create_tag(
            "miguel-fejl", underline=4, underline_rgba=farve("#e01b24"))
        self.tag_adv = tabel.lookup("miguel-advarsel") or self.buf.create_tag(
            "miguel-advarsel", underline=4, underline_rgba=farve("#ff7800"))
        try:
            from gi.repository import GtkSource
            for kat, ikon in (("miguel-fejl", "dialog-error"),
                              ("miguel-advarsel", "dialog-warning")):
                a = GtkSource.MarkAttributes()
                a.set_icon_name(ikon)
                a.connect("query-tooltip-markup", self._mark_tooltip)
                view.set_mark_attributes(kat, a, 10)
            self.marks = True
        except Exception:
            self.marks = False
        view.set_has_tooltip(True)
        self.signaler.append((self.buf, self.buf.connect("changed", self._aendret)))
        self.signaler.append((view, view.connect("query-tooltip", self._tooltip)))
        # sproget sættes ofte først, når filen er indlæst
        self.signaler.append((self.buf, self.buf.connect("notify::language", self._aendret)))
        self._planlaeg()

    def slut(self):
        if self.vent:
            GLib.source_remove(self.vent)
            self.vent = 0
        for obj, sid in self.signaler:
            obj.disconnect(sid)
        self.signaler = []
        self.nr += 1
        self._ryd()

    def er_dash(self):
        try:
            sprog = self.buf.get_language()
            if sprog is not None and sprog.get_id() == "dash":
                return True
        except Exception:
            pass
        navn = ""
        try:
            navn = self.buf.get_short_name_for_display()
        except Exception:
            pass
        return navn.endswith(".Dash") or navn.endswith(".dash")

    def _aendret(self, *_):
        self._planlaeg()

    def _planlaeg(self):
        if self.vent:
            GLib.source_remove(self.vent)
        self.vent = GLib.timeout_add(VENT_MS, self._start)

    def _start(self):
        self.vent = 0
        if self.dsh is None or not self.er_dash():
            self._ryd()
            return False
        self.nr += 1
        nr = self.nr
        s, e = self.buf.get_bounds()
        tekst = self.buf.get_text(s, e, True)
        dsh = self.dsh

        def arbejd():
            fund = tjek(dsh, tekst)
            GLib.idle_add(self._vis, nr, fund)

        threading.Thread(target=arbejd, daemon=True).start()
        return False

    def _ryd(self):
        s, e = self.buf.get_bounds()
        self.buf.remove_tag(self.tag_fejl, s, e)
        self.buf.remove_tag(self.tag_adv, s, e)
        if self.marks:
            for kat in ("miguel-fejl", "miguel-advarsel"):
                self.buf.remove_source_marks(s, e, kat)
        self.fund = {}

    def _vis(self, nr, fund):
        if nr != self.nr:  # der er kommet et nyere tjek
            return False
        self._ryd()
        antal = self.buf.get_line_count()
        for linje, slags, besked in fund:
            i = min(max(linje, 1), antal) - 1
            start = self.buf.get_iter_at_line(i)
            # fra første tegn, der ikke er mellemrum, til linjens ende
            while not start.ends_line() and start.get_char() in " \t":
                start.forward_char()
            slut = start.copy()
            if not slut.ends_line():
                slut.forward_to_line_end()
            if start.equal(slut):  # tom linje: marker det hele
                start = self.buf.get_iter_at_line(i)
            tag = self.tag_fejl if slags == "fejl" else self.tag_adv
            self.buf.apply_tag(tag, start, slut)
            if self.marks:
                self.buf.create_source_mark(None, "miguel-" + slags, start)
            self.fund.setdefault(i, []).append((slags, besked))
        return False

    def tekst_for(self, linje):
        dele = []
        for slags, besked in self.fund.get(linje, []):
            tegn = "✘" if slags == "fejl" else "⚠"
            dele.append(f"🎸 {tegn} {besked}")
        return "\n".join(dele)

    def _tooltip(self, view, x, y, tastatur, tooltip):
        if not self.fund:
            return False
        if tastatur:
            it = self.buf.get_iter_at_mark(self.buf.get_insert())
        else:
            bx, by = view.window_to_buffer_coords(Gtk.TextWindowType.TEXT, x, y)
            res = view.get_iter_at_location(bx, by)
            it = res[1] if isinstance(res, tuple) else res
        t = self.tekst_for(it.get_line())
        if not t:
            return False
        tooltip.set_text(t)
        return True

    def _mark_tooltip(self, attrs, mark):
        it = self.buf.get_iter_at_mark(mark)
        return GLib.markup_escape_text(self.tekst_for(it.get_line()))


def farve(hex_):
    c = Gdk.RGBA()
    c.parse(hex_)
    return c


if Xed is not None:
    class MiguelPlugin(GObject.Object, Xed.ViewActivatable):
        __gtype_name__ = "MiguelDashPlugin"
        view = GObject.Property(type=Xed.View)

        def __init__(self):
            GObject.Object.__init__(self)
            self.miguel = None

        def do_activate(self):
            self.miguel = Miguel(self.view)

        def do_deactivate(self):
            if self.miguel is not None:
                self.miguel.slut()
                self.miguel = None
