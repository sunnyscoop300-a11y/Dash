// JJGui — vinduer, grafik, mus, tastatur og lyd til Dash. 👶⚡
// Opkaldt efter Jack-Jack, babyen med alle superkræfterne. Motoren er
// ViperGui (viper/), Dash-funktionerne ligger her. Bygges uden med -T +nojj
// (fx til telefonen); så bruges jj+nojj.ha i stedet.
//
//   window("Titel", 800, 600)
//   while frame() {
//       clear("#202030")
//       rect(10, 10, 100, 50, "gold")
//       text(20, 24, "Hej!", "white", 2)
//       if button("Klik", 300, 200) { echo "klik!" }
//   }
use ascii;
use fmt;
use math;
use os;
use strconv;
use strings;
use viper;

let jj_win: nullable *viper::window = null;
let jj_snd: nullable *viper::audio = null;
let jj_started = false;
let jj_imgs: []viper::image = [];
let jj_sounds: []viper::sound = [];

fn jj_window(name: str, line: int) (*viper::window | failed) = match (jj_win) {
case let w: *viper::window => yield w;
case null => yield dief(line, "{}(): åbn et vindue med window() først", name);
};

fn jj_int(name: str, args: []value, i: size, line: int) (int | failed) = {
	if (i >= len(args)) return dief(line, "{}() mangler argument nr. {}", name, i + 1);
	return math::roundf64(num_arg(name, args[i], line)?): int;
};

fn jj_num(name: str, args: []value, i: size, line: int) (f64 | failed) = {
	if (i >= len(args)) return dief(line, "{}() mangler argument nr. {}", name, i + 1);
	return num_arg(name, args[i], line)?;
};

fn hexval(c: u8) (u32 | void) = {
	if (c >= '0' && c <= '9') return (c - '0'): u32;
	if (c >= 'a' && c <= 'f') return (c - 'a' + 10): u32;
	if (c >= 'A' && c <= 'F') return (c - 'A' + 10): u32;
};

// "#ff8800", "#f80", "#ff8800cc" (med alpha ignoreret), et navn eller 0xff8800
fn jj_color(name: str, v: value, line: int) (viper::color | failed) = {
	match (v) {
	case let i: i64 =>
		const c = i: u32;
		return if (c <= 0xffffff) c | 0xff000000 else c;
	case let s: str =>
		switch (strings::trim(s)) {
		case "black", "sort" => return 0xff000000;
		case "white", "hvid" => return 0xffffffff;
		case "red", "rød" => return 0xffe04040;
		case "green", "grøn" => return 0xff40c060;
		case "blue", "blå" => return 0xff4080e0;
		case "yellow", "gul" => return 0xfff0d040;
		case "gold", "guld" => return 0xffffcf6a;
		case "orange" => return 0xffff9030;
		case "purple", "lilla" => return 0xffa060e0;
		case "pink", "lyserød" => return 0xffff7eb6;
		case "gray", "grey", "grå" => return 0xff808080;
		case "brown", "brun" => return 0xff7a5426;
		case => void;
		};
		const b = strings::toutf8(strings::trim(s));
		if (len(b) > 0 && b[0] == '#') {
			let digs: []u32 = [];
			defer free(digs);
			for (let k = 1z; k < len(b); k += 1) {
				match (hexval(b[k])) {
				case let d: u32 => append(digs, d)!;
				case void => return dief(line, "{}(): '{}' er ikke en farve", name, s);
				};
			};
			if (len(digs) == 3) {
				return 0xff000000 | (digs[0] * 17) << 16 | (digs[1] * 17) << 8 | digs[2] * 17;
			};
			if (len(digs) == 6 || len(digs) == 8) {
				let c = 0u32;
				for (let k = 0z; k < 6; k += 1) c = c << 4 | digs[k];
				// "#rrggbbaa": de sidste to cifre er gennemsigtighed
				const a = if (len(digs) == 8) digs[6] << 4 | digs[7] else 0xffu32;
				return a << 24 | c;
			};
		};
		return dief(line, "{}(): '{}' er ikke en farve (brug fx \"#ff8800\" eller \"gold\")", name, s);
	case => return dief(line, "{}() vil have en farve, fik {}", name, typename(v));
	};
};

fn jj_col_arg(name: str, args: []value, i: size, std: viper::color, line: int) (viper::color | failed) =
	if (i < len(args)) jj_color(name, args[i], line)? else std;

fn jj_key(name: str, v: value, line: int) (viper::key | failed) = {
	const s = strings::trim(str_arg(name, v, line)?);
	switch (s) {
	case "left", "venstre" => return viper::key::LEFT;
	case "right", "højre" => return viper::key::RIGHT;
	case "up", "op" => return viper::key::UP;
	case "down", "ned" => return viper::key::DOWN;
	case "space", "mellemrum" => return viper::key::SPACE;
	case "enter", "return" => return viper::key::RETURN;
	case "esc", "escape" => return viper::key::ESCAPE;
	case "tab" => return viper::key::TAB;
	case "backspace" => return viper::key::BACKSPACE;
	// tasterne efter USB-scancode (de har ingen navne i motoren)
	case "ctrl" => return 224: viper::key;
	case "shift" => return 225: viper::key;
	case "alt" => return 226: viper::key;
	case "home" => return 74: viper::key;
	case "end" => return 77: viper::key;
	case "delete", "del" => return 76: viper::key;
	case "pageup" => return 75: viper::key;
	case "pagedown" => return 78: viper::key;
	case => void;
	};
	// "f1" … "f12" og cifrene "0" … "9" (USB-scancodes)
	const fb = strings::toutf8(s);
	if (len(fb) >= 2 && len(fb) <= 3 && (fb[0] == 'f' || fb[0] == 'F')) {
		match (strconv::stoi(strings::sub(s, 1, strings::end))) {
		case let n: int =>
			if (n >= 1 && n <= 12) return (57 + n): viper::key;
		case => void;
		};
	};
	if (len(fb) == 1 && fb[0] >= '1' && fb[0] <= '9') return (30 + (fb[0] - '1'): int): viper::key;
	if (len(fb) == 1 && fb[0] == '0') return 39: viper::key;
	const b = strings::toutf8(s);
	if (len(b) == 1) {
		let c = b[0];
		if (c >= 'A' && c <= 'Z') c += 32;
		if (c >= 'a' && c <= 'z') return (viper::key::A: uint + (c - 'a'): uint): viper::key;
	};
	return dief(line, "{}(): kender ikke tasten '{}' (brug fx \"left\", \"space\", \"a\")", name, s);
};

fn jj_bool(b: bool) value = b;

fn jj_pair(a: int, b: int) value = {
	let items: []value = [];
	append(items, [a: i64, b: i64]...)!;
	return newlist(items);
};

// Kaldes fra call() for alle navne, dsh ellers ikke kender. void = ikke JJGui.
fn jj_call(name: str, args: []value, line: int) (value | failed | void) = {
	switch (name) {
	case "window" =>
		if (len(args) < 3) return die(line, "window() vil have titel, bredde og højde");
		if (jj_win != null) return die(line, "window(): der er allerede et vindue");
		const title = tostr(args[0]);
		const w = jj_int(name, args, 1, line)?, h = jj_int(name, args, 2, line)?;
		// app id "dash-<script>": så finder menuen og proceslinjen den
		// rigtige .desktop-fil og logoet (Bob installerer dem med det navn)
		const stem = jj_stem(script_name);
		if (os::getenv("VIPER_APP_ID") is void) {
			match (os::setenv("VIPER_APP_ID", strings::concat("dash-", stem)!)) {
			case => void;
			};
		};
		match (viper::open(title, w, h)) {
		case let win: *viper::window =>
			jj_win = win;
			cam_focal(win);
			jj_auto_icon(win, stem);
		case let e: viper::error =>
			return dief(line, "window(): kan ikke åbne et vindue: {}", viper::strerror(e));
		case nomem =>
			return die(line, "window(): ikke nok hukommelse");
		};
		jj_started = false;
		return true;
	case "frame" =>
		const win = jj_window(name, line)?;
		if (jj_started) {
			match (jj_snd) {
			case let a: *viper::audio => viper::audio_pump(a);
			case null => void;
			};
			viper::present(win);
		};
		jj_started = true;
		pad_poll();
		if (viper::frame(win)) return true;
		jj_close();
		return false;
	case "close_window" =>
		jj_close();
		return nilv: value;
	case "clear" =>
		viper::clear(jj_window(name, line)?, jj_col_arg(name, args, 0, 0xff000000, line)?);
		return nilv: value;
	case "rect" =>
		viper::rect(jj_window(name, line)?, jj_int(name, args, 0, line)?, jj_int(name, args, 1, line)?,
			jj_int(name, args, 2, line)?, jj_int(name, args, 3, line)?,
			jj_col_arg(name, args, 4, 0xffffffff, line)?);
		return nilv: value;
	case "outline" =>
		viper::outline(jj_window(name, line)?, jj_int(name, args, 0, line)?, jj_int(name, args, 1, line)?,
			jj_int(name, args, 2, line)?, jj_int(name, args, 3, line)?,
			jj_col_arg(name, args, 4, 0xffffffff, line)?);
		return nilv: value;
	case "round_rect" =>
		viper::round_rect(jj_window(name, line)?, jj_int(name, args, 0, line)?, jj_int(name, args, 1, line)?,
			jj_int(name, args, 2, line)?, jj_int(name, args, 3, line)?, jj_int(name, args, 4, line)?,
			jj_col_arg(name, args, 5, 0xffffffff, line)?);
		return nilv: value;
	case "circle" =>
		viper::circle(jj_window(name, line)?, jj_int(name, args, 0, line)?, jj_int(name, args, 1, line)?,
			jj_int(name, args, 2, line)?, jj_col_arg(name, args, 3, 0xffffffff, line)?);
		return nilv: value;
	case "line" =>
		viper::line(jj_window(name, line)?, jj_int(name, args, 0, line)?, jj_int(name, args, 1, line)?,
			jj_int(name, args, 2, line)?, jj_int(name, args, 3, line)?,
			jj_col_arg(name, args, 4, 0xffffffff, line)?);
		return nilv: value;
	case "pixel" =>
		viper::pixel(jj_window(name, line)?, jj_int(name, args, 0, line)?, jj_int(name, args, 1, line)?,
			jj_col_arg(name, args, 2, 0xffffffff, line)?);
		return nilv: value;
	case "polygon" =>
		const win = jj_window(name, line)?;
		if (len(args) < 1) return die(line, "polygon() vil have en liste af punkter [[x, y], …]");
		const l = match (args[0]) {
		case let l: *list => yield l;
		case => return die(line, "polygon() vil have en liste af punkter [[x, y], …]");
		};
		let pts: [](f64, f64) = [];
		defer free(pts);
		for (let p .. l.items) {
			const xy = match (p) {
			case let q: *list => yield q;
			case => return die(line, "polygon(): hvert punkt skal være [x, y]");
			};
			if (len(xy.items) < 2) return die(line, "polygon(): hvert punkt skal være [x, y]");
			append(pts, (num_arg(name, xy.items[0], line)?, num_arg(name, xy.items[1], line)?))!;
		};
		if (len(pts) >= 3) viper::polygon(win, pts, jj_col_arg(name, args, 1, 0xffffffff, line)?);
		return nilv: value;
	case "text" =>
		const win = jj_window(name, line)?;
		if (len(args) < 3) return die(line, "text() vil have x, y og teksten");
		const scale = if (len(args) > 4) jj_int(name, args, 4, line)? else 1;
		viper::text_scaled(win, jj_int(name, args, 0, line)?, jj_int(name, args, 1, line)?,
			tostr(args[2]), jj_col_arg(name, args, 3, 0xffffffff, line)?, if (scale < 1) 1 else scale);
		return nilv: value;
	case "text_width" =>
		if (len(args) < 1) return die(line, "text_width() vil have en tekst");
		const scale = if (len(args) > 1) jj_int(name, args, 1, line)? else 1;
		return viper::text_width(tostr(args[0]), scale): i64;
	case "button" =>
		if (len(args) < 3) return die(line, "button() vil have tekst, x og y");
		return viper::button(jj_window(name, line)?, tostr(args[0]),
			jj_int(name, args, 1, line)?, jj_int(name, args, 2, line)?);
	case "mouse" =>
		const (x, y) = viper::mouse(jj_window(name, line)?);
		return jj_pair(x, y);
	case "clicked" =>
		return viper::mouse_pressed(jj_window(name, line)?);
	case "right_clicked" =>
		return viper::mouse_clicks(jj_window(name, line)?) & viper::RIGHT_BUTTON != 0;
	case "mouse_down" =>
		return viper::mouse_buttons(jj_window(name, line)?) & viper::LEFT_BUTTON != 0;
	case "wheel" =>
		return viper::wheel(jj_window(name, line)?): i64;
	case "key" =>
		need(name, args, 1, line)?;
		const win = jj_window(name, line)?;
		const k = jj_key(name, args[0], line)?;
		// højre Ctrl/Shift/Alt tæller også
		if (k: uint >= 224 && k: uint <= 226 && win.keys[k: size + 4] != 0) return true;
		return viper::key_down(win, k);
	case "pressed" =>
		need(name, args, 1, line)?;
		return viper::key_typed(jj_window(name, line)?, jj_key(name, args[0], line)?);
	case "typed" =>
		return strings::dup(viper::typed(jj_window(name, line)?))!;
	case "delta" =>
		return viper::delta(jj_window(name, line)?);
	case "width" =>
		return jj_window(name, line)?.width: i64;
	case "height" =>
		return jj_window(name, line)?.height: i64;
	case "image" =>
		const p = expanduser(str_arg(name, if (len(args) > 0) args[0] else nilv, line)?);
		let img = match (viper::load_png(p)) {
		case let i: viper::image => yield i;
		case let e: viper::imgerror =>
			return dief(line, "image(): kan ikke læse '{}': {}", p, viper::imgstrerror(e));
		};
		if (len(args) >= 3) {
			const w = jj_int(name, args, 1, line)?, h = jj_int(name, args, 2, line)?;
			const r = viper::resize(&img, w, h)!;
			viper::image_free(&img);
			img = r;
		};
		// en plads, som free_image() har tømt, genbruges
		for (let k = 0z; k < len(jj_imgs); k += 1) {
			if (jj_imgs[k].w == 0 && len(jj_imgs[k].pixels) == 0) {
				jj_imgs[k] = img;
				return k: i64;
			};
		};
		append(jj_imgs, img)!;
		return (len(jj_imgs) - 1): i64;
	case "draw" =>
		const win = jj_window(name, line)?;
		const id = jj_int(name, args, 0, line)?;
		if (id < 0 || id: size >= len(jj_imgs)) return dief(line, "draw(): intet billede nr. {}", id);
		const dx = jj_int(name, args, 1, line)?, dy = jj_int(name, args, 2, line)?;
		if (len(args) >= 5) {
			// draw(nr, x, y, bredde, højde): tegnet i en anden størrelse (fx zoom)
			viper::draw_image_scaled(win, &jj_imgs[id], dx, dy,
				jj_int(name, args, 3, line)?, jj_int(name, args, 4, line)?);
		} else {
			viper::draw_image(win, &jj_imgs[id], dx, dy);
		};
		return nilv: value;
	case "window_icon" =>
		// window_icon("logo.png"): vinduets ikon (proceslinjen, alt-tab)
		const win = jj_window(name, line)?;
		const p = expanduser(str_arg(name, if (len(args) > 0) args[0] else nilv, line)?);
		let img = match (viper::load_png(p)) {
		case let i: viper::image => yield i;
		case let e: viper::imgerror =>
			return dief(line, "window_icon(): kan ikke læse '{}': {}", p, viper::imgstrerror(e));
		};
		viper::set_icon(win, &img);
		viper::image_free(&img);
		return nilv: value;
	case "free_image" =>
		// free_image(nr): giv billedets hukommelse tilbage (nummeret kan genbruges)
		const id = jj_int(name, args, 0, line)?;
		if (id >= 0 && id: size < len(jj_imgs)) {
			viper::image_free(&jj_imgs[id]);
			jj_imgs[id].w = 0;
			jj_imgs[id].h = 0;
		};
		return nilv: value;
	case "image_size" =>
		const id = jj_int(name, args, 0, line)?;
		if (id < 0 || id: size >= len(jj_imgs)) return dief(line, "image_size(): intet billede nr. {}", id);
		return jj_pair(jj_imgs[id].w, jj_imgs[id].h);
	case "sound" =>
		// sound("sine", 440, 220, 0.2, 0.5) → lyd nr.
		if (len(args) < 4) return die(line, "sound() vil have bølge, start-Hz, slut-Hz og sekunder");
		const w = switch (str_arg(name, args[0], line)?) {
		case "sine" => yield viper::wave::SINE;
		case "square" => yield viper::wave::SQUARE;
		case "triangle" => yield viper::wave::TRIANGLE;
		case "saw" => yield viper::wave::SAW;
		case "noise" => yield viper::wave::NOISE;
		case => return die(line, "sound(): bølgen skal være sine, square, triangle, saw eller noise");
		};
		const vol = if (len(args) > 4) jj_num(name, args, 4, line)? else 0.5;
		append(jj_sounds, viper::tone(w, jj_num(name, args, 1, line)?, jj_num(name, args, 2, line)?,
			jj_num(name, args, 3, line)?, vol, 0.003))!;
		return (len(jj_sounds) - 1): i64;
	case "sound_file" =>
		const p = expanduser(str_arg(name, if (len(args) > 0) args[0] else nilv, line)?);
		match (viper::load_wav(p)) {
		case let s: viper::sound => append(jj_sounds, s)!;
		case let e: viper::imgerror =>
			return dief(line, "sound_file(): kan ikke læse '{}': {}", p, viper::imgstrerror(e));
		};
		return (len(jj_sounds) - 1): i64;
	case "play" =>
		const id = jj_int(name, args, 0, line)?;
		if (id < 0 || id: size >= len(jj_sounds)) return dief(line, "play(): ingen lyd nr. {}", id);
		const a = match (jj_snd) {
		case let a: *viper::audio => yield a;
		case null =>
			const a = viper::audio_open();
			jj_snd = a;
			yield a;
		};
		const vol = if (len(args) > 1) jj_num(name, args, 1, line)? else 1.0;
		const pitch = if (len(args) > 2) jj_num(name, args, 2, line)? else 1.0;
		viper::play(a, &jj_sounds[id], vol, pitch);
		return nilv: value;
	case "blit" =>
		// blit(buf, adr, række_bytes, bredde, højde, format, x, y [, w, h])
		// tegner pixels direkte fra en bytes()-buffer: format 15 (PS1-VRAM,
		// 16 bit BGR555), 24 (RGB, 3 bytes) eller 32 (BGRA, som i vinduet)
		const win = jj_window(name, line)?;
		if (len(args) != 8 && len(args) != 10) {
			return die(line, "blit() vil have buf, adr, række_bytes, bredde, højde, format, x, y [, w, h]");
		};
		let a: [10]i64 = [0...];
		for (let k = 0z; k < len(args); k += 1) a[k] = int_arg(name, args[k], line)?;
		const sw = a[3], sh = a[4];
		const dw = if (len(args) == 10) a[8] else sw, dh = if (len(args) == 10) a[9] else sh;
		jj_blit(win, a[0], a[1], a[2], sw, sh, a[5], a[6], a[7], dw, dh, line)?;
		return nilv: value;
	case "stream_pcm" =>
		// stream_pcm(buf, adr, frames): 16-bit stereo-samples (little-endian,
		// 44100 Hz, som CD-lyd) fra en bytes()-buffer ud i højttalerne
		if (len(args) != 3) return die(line, "stream_pcm() vil have buf, adr og antal frames");
		const buf = mem_get(int_arg(name, args[0], line)?, name, line)?;
		const off = int_arg(name, args[1], line)?;
		const n = int_arg(name, args[2], line)?;
		if (n <= 0) return nilv: value;
		if (off < 0 || off + n * 4 > len(buf): i64) {
			return dief(line, "stream_pcm(): {} frames fra 0x{:x} går udenfor bufferen", n, off);
		};
		const a = match (jj_snd) {
		case let a: *viper::audio => yield a;
		case null =>
			const a = viper::audio_open();
			jj_snd = a;
			yield a;
		};
		let smp: []f32 = alloc([0.0f32...], n: size)!;
		defer free(smp);
		for (let k = 0z; k < n: size; k += 1) {
			const o = off: size + k * 4;
			const l = (buf[o]: u16 | buf[o + 1]: u16 << 8): i16;
			const r = (buf[o + 2]: u16 | buf[o + 3]: u16 << 8): i16;
			smp[k] = (l: f32 + r: f32) / 65536.0;
		};
		viper::audio_stream(a, smp);
		return nilv: value;
	case "fullscreen" =>
		// fullscreen(true/false) → true, hvis vinduet kunne (kun SDL2 endnu)
		need(name, args, 1, line)?;
		return viper::set_fullscreen(jj_window(name, line)?, truthy(args[0]));
	case "window_size" =>
		// window_size(b, h): vinduet på skærmen; tegnefladen skaleres med
		if (len(args) != 2) return die(line, "window_size() vil have bredde og højde");
		return viper::set_window_size(jj_window(name, line)?,
			jj_int(name, args, 0, line)?, jj_int(name, args, 1, line)?);
	case "screenshot" =>
		const win = jj_window(name, line)?;
		const p = expanduser(str_arg(name, if (len(args) > 0) args[0] else nilv, line)?);
		let img = viper::image { w = win.width, h = win.height, pixels = win.pixels };
		match (viper::save_png(&img, p)) {
		case void => return nilv: value;
		case => return dief(line, "screenshot(): kan ikke gemme '{}'", p);
		};
	case =>
		match (jj_pad_call(name, args, line)?) {
		case let v: value => return v;
		case void => void;
		};
		match (jj_text_call(name, args, line)?) {
		case let v: value => return v;
		case void => return jj3_call(name, args, line);
		};
	};
};

fn jj_close() void = {
	match (jj_snd) {
	case let a: *viper::audio =>
		viper::audio_close(a);
		jj_snd = null;
	case null => void;
	};
	match (jj_win) {
	case let w: *viper::window =>
		viper::close(w);
		jj_win = null;
	case null => void;
	};
};

// "eksempler/Boxman.Dash" → "boxman"
fn jj_stem(path: str) str = {
	const (_, base) = strings::rcut(path, "/");
	if (base == "") base = path;
	const (stem, _) = strings::rcut(base, ".");
	if (stem == "") stem = base;
	return ascii::strlower(stem)!;
};

// Finder appens logo selv: ikoner/<navn>.png ved siden af scriptet, eller
// det logo Bob har installeret i ~/.local/share/icons.
fn jj_auto_icon(win: *viper::window, stem: str) void = {
	const (dir, _) = strings::rcut(script_name, "/");
	const home = match (os::getenv("HOME")) {
	case let h: str => yield h;
	case void => yield "";
	};
	const steder = [
		if (strings::contains(script_name, "/")) fmt::asprintf("{}/ikoner/{}.png", dir, stem)!
			else fmt::asprintf("ikoner/{}.png", stem)!,
		fmt::asprintf("{}/.local/share/icons/hicolor/256x256/apps/dash-{}.png", home, stem)!,
	];
	defer for (let s .. steder) free(s);
	for (let s .. steder) {
		match (viper::load_png(s)) {
		case let img: viper::image =>
			viper::set_icon(win, &img);
			viper::image_free(&img);
			return;
		case viper::imgerror => void;
		};
	};
};

let jj_lut15: []u32 = [];

fn jj_blit(win: *viper::window, h: i64, off: i64, stride: i64, sw: i64, sh: i64,
		format: i64, x: i64, y: i64, w: i64, hh: i64, line: int) (void | failed) = {
	const buf = mem_get(h, "blit", line)?;
	const bpp: i64 = switch (format) {
	case 15, 16 => yield 2;
	case 24 => yield 3;
	case 32 => yield 4;
	case => return dief(line, "blit(): format skal være 15, 24 eller 32, ikke {}", format);
	};
	if (sw <= 0 || sh <= 0 || w <= 0 || hh <= 0) return;
	const last = off + (sh - 1) * stride + sw * bpp;
	if (off < 0 || stride < 0 || last > len(buf): i64) {
		return dief(line, "blit(): {}×{} pixels fra 0x{:x} går udenfor bufferen", sw, sh, off);
	};
	if (bpp == 2 && len(jj_lut15) == 0) {
		// 5 bit → 8 bit pr. farve, én gang for alle
		for (let c = 0u32; c < 32768; c += 1) {
			const r = c & 31, g = (c >> 5) & 31, b = (c >> 10) & 31;
			append(jj_lut15, 0xff000000 | (r << 3 | r >> 2) << 16
				| (g << 3 | g >> 2) << 8 | (b << 3 | b >> 2))!;
		};
	};
	const x0 = if (x < win.clip_x0: i64) win.clip_x0: i64 else x;
	const y0 = if (y < win.clip_y0: i64) win.clip_y0: i64 else y;
	const x1 = if (x + w > win.clip_x1: i64) win.clip_x1: i64 else x + w;
	const y1 = if (y + hh > win.clip_y1: i64) win.clip_y1: i64 else y + hh;
	if (x0 >= x1 || y0 >= y1) return;
	const ww = win.width: i64;
	for (let yy = y0; yy < y1; yy += 1) {
		const sy = (yy - y) * sh / hh;
		const row = off + sy * stride;
		const drow = yy * ww;
		for (let xx = x0; xx < x1; xx += 1) {
			const sx = (xx - x) * sw / w;
			const o = (row + sx * bpp): size;
			win.pixels[(drow + xx): size] = switch (bpp) {
			case 2 => yield jj_lut15[(buf[o]: u32 | (buf[o + 1]: u32 & 0x7f) << 8): size];
			case 3 => yield 0xff000000 | buf[o]: u32 << 16 | buf[o + 1]: u32 << 8 | buf[o + 2]: u32;
			case => yield buf[o]: u32 | buf[o + 1]: u32 << 8 | buf[o + 2]: u32 << 16 | 0xff000000;
			};
		};
	};
};
