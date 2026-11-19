// JJGui — tekstfelter og udklipsholderen. ✂️📋
//
//   let s = textbox("søg", x, y, bredde)                 ét-linjes tekstfelt
//   let s = textbox("kode", x, y, 300, {"skjul": true})  med valg (se nedenfor)
//   focused("søg")          har feltet fokus?    textbox_set("søg", "tekst")
//   clipboard()             teksten i systemets udklipsholder
//   set_clipboard("hej")    læg tekst i udklipsholderen
//
// Feltet kan: klik for markøren, træk eller dobbeltklik for at markere,
// Shift+pile/Home/End, Delete, Ctrl+A/C/X/V og højreklik for en menu
// (Klip, Kopiér, Indsæt, Markér alt). Valg: "tom" (tekst når feltet er
// tomt), "skjul" (adgangskode), "h" (højde), "r" (runde hjørner), "bund",
// "tekst", "kant", "fokus", "markering", "dæmp" (farver), "maks" (tegn) og
// "aktiv" (false = feltet tegnes, men reagerer ikke, fx under en dialog) og
// "indryk" (plads til venstre for teksten, fx til et ikon).
use os;
use os::exec;
use io;
use strings;
use time;
use viper;

type jj_tb = struct {
	id: str,
	text: []rune,
	cur: size,
	anchor: size,
	focus: bool,
	drag: bool,
	scroll: int,
	last_click: time::instant,
	menu: bool,
	menu_x: int,
	menu_y: int,
	enter: bool,
	nyfokus: bool,          // fik fokus fra koden: se bort fra dette billedes klik
};

let jj_tbs: []jj_tb = [];
let jj_clip_intern: str = "";

def HID_CTRL_L: size = 224;
def HID_CTRL_R: size = 228;
def HID_SHIFT_L: size = 225;
def HID_SHIFT_R: size = 229;
def HID_HOME: size = 74;
def HID_END: size = 77;
def HID_DELETE: size = 76;

fn jj_tb_find(id: str) *jj_tb = {
	for (let i = 0z; i < len(jj_tbs); i += 1) {
		if (jj_tbs[i].id == id) return &jj_tbs[i];
	};
	append(jj_tbs, jj_tb { id = strings::dup(id)!, last_click = time::now(time::clock::MONOTONIC), ... })!;
	return &jj_tbs[len(jj_tbs) - 1];
};

fn jj_tb_str(tb: *jj_tb) str = strings::fromrunes(tb.text)!;

fn jj_tb_sel(tb: *jj_tb) (size, size) =
	if (tb.cur < tb.anchor) (tb.cur, tb.anchor) else (tb.anchor, tb.cur);

fn jj_tb_seltext(tb: *jj_tb) str = {
	const (a, b) = jj_tb_sel(tb);
	return strings::fromrunes(tb.text[a..b])!;
};

fn jj_tb_delsel(tb: *jj_tb) void = {
	const (a, b) = jj_tb_sel(tb);
	if (a == b) return;
	delete(tb.text[a..b]);
	tb.cur = a;
	tb.anchor = a;
};

fn jj_tb_insert(tb: *jj_tb, s: str, maks: size) void = {
	jj_tb_delsel(tb);
	let it = strings::iter(s);
	for (let r => strings::next(&it)) {
		if (r == '\n' || r == '\r' || r == '\t') continue;
		if (maks > 0 && len(tb.text) >= maks) break;
		insert(tb.text[tb.cur], r)!;
		tb.cur += 1;
	};
	tb.anchor = tb.cur;
};

// er r en del af et ord (til dobbeltklik)?
fn jj_ordtegn(r: rune) bool = !(r == ' ' || r == '.' || r == ',' || r == '/' ||
	r == '-' || r == '_' || r == ':' || r == ';' || r == '(' || r == ')');

// ── udklipsholderen ──────────────────────────────────────────────────

fn jj_har(prog: str) bool = {
	const path = match (os::getenv("PATH")) {
	case let p: str => yield p;
	case void => yield "/usr/bin:/bin";
	};
	for (let dir .. strings::split(path, ":")!) {
		const p = strings::concat(dir, "/", prog)!;
		defer free(p);
		if (os::exists(p)) return true;
	};
	return false;
};

// Det program, der læser (ud = true) eller skriver udklipsholderen.
fn jj_clip_cmd(ud: bool) ([]str | void) = {
	const wl = os::getenv("WAYLAND_DISPLAY") is str;
	const x = os::getenv("DISPLAY") is str;
	if (wl && jj_har("wl-paste")) {
		return if (ud) ["wl-paste", "--no-newline"] else ["wl-copy"];
	};
	if (x && jj_har("xclip")) {
		return if (ud) ["xclip", "-selection", "clipboard", "-o"]
			else ["xclip", "-selection", "clipboard", "-i"];
	};
	if (x && jj_har("xsel")) {
		return if (ud) ["xsel", "-b", "-o"] else ["xsel", "-b", "-i"];
	};
	if (jj_har("termux-clipboard-get")) {
		return if (ud) ["termux-clipboard-get"] else ["termux-clipboard-set"];
	};
};

// Læser udklipsholderen (eller den interne, hvis der intet program er).
fn jj_clip_get() str = {
	const argv = match (jj_clip_cmd(true)) {
	case let a: []str => yield a;
	case void => return strings::dup(jj_clip_intern)!;
	};
	let cmd = match (exec::cmd(argv[0], argv[1..]...)) {
	case let c: exec::command => yield c;
	case => return strings::dup(jj_clip_intern)!;
	};
	const (r, w) = exec::pipe();
	exec::addfile(&cmd, os::stdout_file, w)!;
	exec::addfile(&cmd, os::stderr_file, exec::nullfd)!;
	exec::addfile(&cmd, os::stdin_file, exec::nullfd)!;
	const p = match (exec::start(&cmd)) {
	case let p: exec::process => yield p;
	case =>
		io::close(r)!;
		io::close(w)!;
		return strings::dup(jj_clip_intern)!;
	};
	io::close(w)!;
	const data = match (io::drain(r)) {
	case let d: []u8 => yield d;
	case => yield []: []u8;
	};
	io::close(r)!;
	match (exec::wait(&p)) { case => void; };
	return match (strings::fromutf8(data)) {
	case let s: str => yield s;
	case => yield strings::dup(jj_clip_intern)!;
	};
};

fn jj_clip_set(s: str) bool = {
	free(jj_clip_intern);
	jj_clip_intern = strings::dup(s)!;
	const argv = match (jj_clip_cmd(false)) {
	case let a: []str => yield a;
	case void => return false;
	};
	let cmd = match (exec::cmd(argv[0], argv[1..]...)) {
	case let c: exec::command => yield c;
	case => return false;
	};
	const (r, w) = exec::pipe();
	exec::addfile(&cmd, os::stdin_file, r)!;
	exec::addfile(&cmd, os::stdout_file, exec::nullfd)!;
	exec::addfile(&cmd, os::stderr_file, exec::nullfd)!;
	const p = match (exec::start(&cmd)) {
	case let p: exec::process => yield p;
	case =>
		io::close(r)!;
		io::close(w)!;
		return false;
	};
	io::close(r)!;
	match (io::writeall(w, strings::toutf8(s))) { case => void; };
	io::close(w)!;
	match (exec::wait(&p)) { case => void; };
	return true;
};

// ── selve feltet ─────────────────────────────────────────────────────

fn jj_opt(m: nullable *mapv, key: str) (value | void) = {
	const mm = match (m) {
	case let p: *mapv => yield p;
	case null => return;
	};
	match (map_find(mm, key: value)) {
	case let i: size => return mm.vals[i];
	case void => return;
	};
};

fn jj_opt_col(m: nullable *mapv, key: str, def_: viper::color, line: int) (viper::color | failed) = {
	match (jj_opt(m, key)) {
	case let v: value => return jj_color("textbox", v, line);
	case void => return def_;
	};
};

fn jj_opt_int(m: nullable *mapv, key: str, def_: int) int = {
	match (jj_opt(m, key)) {
	case let v: value =>
		match (v) {
		case let i: i64 => return i: int;
		case let f: f64 => return f: int;
		case => return def_;
		};
	case void => return def_;
	};
};

fn jj_textbox(args: []value, line: int) (value | failed) = {
	const name = "textbox";
	if (len(args) < 4) return die(line, "textbox() vil have navn, x, y og bredde");
	const win = jj_window(name, line)?;
	const tb = jj_tb_find(tostr(args[0]));
	const x = jj_int(name, args, 1, line)?, y = jj_int(name, args, 2, line)?;
	const w = jj_int(name, args, 3, line)?;
	let opts: nullable *mapv = null;
	if (len(args) > 4) match (args[4]) {
	case let m: *mapv => opts = m;
	case => void;
	};
	const h = jj_opt_int(opts, "h", 36);
	const rr = jj_opt_int(opts, "r", 10);
	const maks = jj_opt_int(opts, "maks", 0): size;
	const skjul = match (jj_opt(opts, "skjul")) {
	case let v: value => yield truthy(v);
	case void => yield false;
	};
	const aktiv = match (jj_opt(opts, "aktiv")) {
	case let v: value => yield truthy(v);
	case void => yield true;
	};
	const tom = match (jj_opt(opts, "tom")) {
	case let v: value => yield tostr(v);
	case void => yield "";
	};
	const c_bund = jj_opt_col(opts, "bund", 0xffffffff, line)?;
	const c_tekst = jj_opt_col(opts, "tekst", 0xff202028, line)?;
	const c_kant = jj_opt_col(opts, "kant", 0xffc8c8d0, line)?;
	const c_fokus = jj_opt_col(opts, "fokus", 0xff4a8af0, line)?;
	const c_mark = jj_opt_col(opts, "markering", 0x604a8af0, line)?;
	const c_daemp = jj_opt_col(opts, "dæmp", 0xff9a9aa6, line)?;

	const (mx, my) = viper::mouse(win);
	const inde = mx >= x && mx < x + w && my >= y && my < y + h;
	const klik = aktiv && !tb.nyfokus && viper::mouse_pressed(win);
	const hojre = aktiv && !tb.nyfokus && viper::mouse_clicks(win) & viper::RIGHT_BUTTON != 0;
	tb.nyfokus = false;
	const holdt = aktiv && viper::mouse_buttons(win) & viper::LEFT_BUTTON != 0;
	if (!aktiv) tb.menu = false;
	const ind = jj_opt_int(opts, "indryk", 10);
	const tx = x + ind;
	const ty = y + (h - viper::FONT_H) / 2;
	const tw = w - ind - 10;
	tb.enter = false;

	// markør-position ud fra musens x
	const pos_fra_x = (mx - tx + tb.scroll + viper::FONT_W / 2) / viper::FONT_W;
	const musepos: size = if (pos_fra_x < 0) 0z
		else if (pos_fra_x: size > len(tb.text)) len(tb.text) else pos_fra_x: size;

	// højreklik-menuen
	const MW = 140, MH = 26;
	const punkter = ["Klip", "Kopiér", "Indsæt", "Markér alt"];
	let menu_klik = -1;
	if (tb.menu && klik) {
		if (mx >= tb.menu_x && mx < tb.menu_x + MW && my >= tb.menu_y && my < tb.menu_y + MH * 4) {
			menu_klik = (my - tb.menu_y) / MH;
		};
		tb.menu = false;
	};

	if (menu_klik >= 0) {
		const ctrl_s = jj_tb_seltext(tb);
		defer free(ctrl_s);
		switch (menu_klik) {
		case 0 =>
			if (!skjul && len(ctrl_s) > 0) jj_clip_set(ctrl_s);
			jj_tb_delsel(tb);
		case 1 =>
			if (!skjul && len(ctrl_s) > 0) jj_clip_set(ctrl_s);
		case 2 =>
			const c = jj_clip_get();
			defer free(c);
			jj_tb_insert(tb, c, maks);
		case =>
			tb.anchor = 0;
			tb.cur = len(tb.text);
		};
		tb.focus = true;
	} else if (hojre && inde) {
		tb.focus = true;
		tb.menu = true;
		tb.menu_x = mx;
		tb.menu_y = my;
		// højreklik uden for markeringen flytter markøren
		const (a, b) = jj_tb_sel(tb);
		if (musepos < a || musepos > b) {
			tb.cur = musepos;
			tb.anchor = musepos;
		};
	} else if (klik) {
		if (inde) {
			const nu = time::now(time::clock::MONOTONIC);
			const dobbelt = tb.focus && time::diff(tb.last_click, nu) < 400 * time::MILLISECOND;
			tb.last_click = nu;
			tb.focus = true;
			if (dobbelt) {
				// marker ordet
				let a = musepos, b = musepos;
				for (a > 0 && jj_ordtegn(tb.text[a - 1])) a -= 1;
				for (b < len(tb.text) && jj_ordtegn(tb.text[b])) b += 1;
				tb.anchor = a;
				tb.cur = b;
			} else {
				const shift = win.keys[HID_SHIFT_L] != 0 || win.keys[HID_SHIFT_R] != 0;
				tb.cur = musepos;
				if (!shift) tb.anchor = musepos;
				tb.drag = true;
			};
		} else {
			tb.focus = false;
			tb.menu = false;
		};
	};
	if (!holdt) tb.drag = false;
	if (tb.drag && holdt) tb.cur = musepos;

	// tastaturet
	if (tb.focus && aktiv) {
		const ctrl = win.keys[HID_CTRL_L] != 0 || win.keys[HID_CTRL_R] != 0;
		const shift = win.keys[HID_SHIFT_L] != 0 || win.keys[HID_SHIFT_R] != 0;
		if (ctrl) {
			if (viper::key_pressed(win, viper::key::A)) {
				tb.anchor = 0;
				tb.cur = len(tb.text);
			};
			if (viper::key_pressed(win, viper::key::C) || viper::key_pressed(win, viper::key::X)) {
				const s = jj_tb_seltext(tb);
				defer free(s);
				if (!skjul && len(s) > 0) jj_clip_set(s);
				if (viper::key_pressed(win, viper::key::X)) jj_tb_delsel(tb);
			};
			if (viper::key_pressed(win, viper::key::V)) {
				const c = jj_clip_get();
				defer free(c);
				jj_tb_insert(tb, c, maks);
			};
		} else {
			const t = viper::typed(win);
			if (len(t) > 0) jj_tb_insert(tb, t, maks);
		};
		if (viper::key_typed(win, viper::key::BACKSPACE)) {
			if (tb.cur != tb.anchor) {
				jj_tb_delsel(tb);
			} else if (tb.cur > 0) {
				delete(tb.text[tb.cur - 1]);
				tb.cur -= 1;
				tb.anchor = tb.cur;
			};
		};
		if (win.keys_typed[HID_DELETE]) {
			if (tb.cur != tb.anchor) {
				jj_tb_delsel(tb);
			} else if (tb.cur < len(tb.text)) {
				delete(tb.text[tb.cur]);
			};
		};
		let flyt = false;
		if (viper::key_typed(win, viper::key::LEFT)) {
			if (!shift && tb.cur != tb.anchor) {
				tb.cur = jj_tb_sel(tb).0;
			} else if (tb.cur > 0) tb.cur -= 1;
			flyt = true;
		};
		if (viper::key_typed(win, viper::key::RIGHT)) {
			if (!shift && tb.cur != tb.anchor) {
				tb.cur = jj_tb_sel(tb).1;
			} else if (tb.cur < len(tb.text)) tb.cur += 1;
			flyt = true;
		};
		if (win.keys_typed[HID_HOME]) {
			tb.cur = 0;
			flyt = true;
		};
		if (win.keys_typed[HID_END]) {
			tb.cur = len(tb.text);
			flyt = true;
		};
		if (flyt && !shift) tb.anchor = tb.cur;
		if (viper::key_pressed(win, viper::key::RETURN) || viper::key_pressed(win, viper::key::KP_ENTER)) {
			tb.enter = true;
		};
		if (viper::key_pressed(win, viper::key::ESCAPE)) tb.menu = false;
	};

	// rul, så markøren altid kan ses
	const cx = tb.cur: int * viper::FONT_W;
	if (cx - tb.scroll > tw - 2) tb.scroll = cx - tw + 2;
	if (cx - tb.scroll < 0) tb.scroll = cx;
	const fuld = len(tb.text): int * viper::FONT_W;
	if (tb.scroll > 0 && fuld - tb.scroll < tw) tb.scroll = if (fuld > tw) fuld - tw else 0;

	// tegn
	viper::round_rect(win, x, y, w, h, rr, if (tb.focus) c_fokus else c_kant);
	viper::round_rect(win, x + 2, y + 2, w - 4, h - 4, if (rr > 2) rr - 2 else 0, c_bund);
	viper::clip(win, tx, y + 2, tw, h - 4);
	if (len(tb.text) == 0 && !tb.focus && len(tom) > 0) {
		viper::text(win, tx, ty, tom, c_daemp);
	} else {
		const (a, b) = jj_tb_sel(tb);
		if (tb.focus && a != b) {
			viper::rect(win, tx + a: int * viper::FONT_W - tb.scroll, ty - 2,
				(b - a): int * viper::FONT_W, viper::FONT_H + 4, c_mark);
		};
		let vis: []rune = [];
		defer free(vis);
		for (let r .. tb.text) append(vis, if (skjul) '*' else r)!;
		const s = strings::fromrunes(vis)!;
		defer free(s);
		viper::text(win, tx - tb.scroll, ty, s, c_tekst);
		// blinkende markør
		const ms = time::now(time::clock::MONOTONIC).sec * 1000 + time::now(time::clock::MONOTONIC).nsec / 1000000;
		if (tb.focus && (ms / 530) % 2 == 0) {
			viper::rect(win, tx + cx - tb.scroll, ty - 2, 2, viper::FONT_H + 4, c_tekst);
		};
	};
	viper::noclip(win);

	// menuen tegnes til sidst, så den ligger ovenpå feltet
	if (tb.menu) {
		const harmark = tb.cur != tb.anchor && !skjul;
		viper::round_rect(win, tb.menu_x + 3, tb.menu_y + 4, MW, MH * 4 + 8, 8, 0x50000000);
		viper::round_rect(win, tb.menu_x, tb.menu_y, MW, MH * 4 + 8, 8, 0xffffffff);
		for (let i = 0; i < 4; i += 1) {
			const iy = tb.menu_y + 4 + i * MH;
			const over = mx >= tb.menu_x && mx < tb.menu_x + MW && my >= iy && my < iy + MH;
			const aktiv = (i != 0 && i != 1) || harmark;
			if (over && aktiv) viper::round_rect(win, tb.menu_x + 4, iy, MW - 8, MH, 6, 0xffe8eefc);
			viper::text(win, tb.menu_x + 14, iy + (MH - viper::FONT_H) / 2, punkter[i],
				if (aktiv) 0xff202028 else 0xffb0b0b8);
		};
	};
	return jj_tb_str(tb);
};

fn jj_text_call(name: str, args: []value, line: int) (value | failed | void) = {
	switch (name) {
	case "textbox" =>
		return jj_textbox(args, line);
	case "focused" =>
		// focused("navn") → har feltet fokus?  focused() → har noget felt fokus?
		if (len(args) == 0) {
			for (let tb &.. jj_tbs) if (tb.focus) return true;
			return false;
		};
		return jj_tb_find(tostr(args[0])).focus;
	case "submitted" =>
		// submitted("navn") → blev Enter trykket i feltet i dette billede?
		need(name, args, 1, line)?;
		return jj_tb_find(tostr(args[0])).enter;
	case "textbox_set" =>
		// textbox_set("navn", "tekst") — og textbox_set("navn", "", true) giver fokus
		if (len(args) < 2 || len(args) > 3) return die(line, "textbox_set() vil have navn, tekst og evt. fokus");
		const tb = jj_tb_find(tostr(args[0]));
		free(tb.text);
		tb.text = [];
		let it = strings::iter(tostr(args[1]));
		for (let r => strings::next(&it)) append(tb.text, r)!;
		tb.cur = len(tb.text);
		tb.anchor = tb.cur;
		tb.scroll = 0;
		if (len(args) > 2) {
			tb.focus = truthy(args[2]);
			tb.nyfokus = tb.focus;
		};
		return nilv: value;
	case "clipboard" =>
		return jj_clip_get();
	case "set_clipboard" =>
		need(name, args, 1, line)?;
		return jj_clip_set(tostr(args[0]));
	case => return;
	};
};
