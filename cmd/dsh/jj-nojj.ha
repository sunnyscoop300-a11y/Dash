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
use fmt;
use math;
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
	case => void;
	};
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
		match (viper::open(title, w, h)) {
		case let win: *viper::window =>
			jj_win = win;
			cam_focal(win);
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
		return viper::key_down(jj_window(name, line)?, jj_key(name, args[0], line)?);
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
		append(jj_imgs, img)!;
		return (len(jj_imgs) - 1): i64;
	case "draw" =>
		const win = jj_window(name, line)?;
		const id = jj_int(name, args, 0, line)?;
		if (id < 0 || id: size >= len(jj_imgs)) return dief(line, "draw(): intet billede nr. {}", id);
		viper::draw_image(win, &jj_imgs[id], jj_int(name, args, 1, line)?, jj_int(name, args, 2, line)?);
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
	case "screenshot" =>
		const win = jj_window(name, line)?;
		const p = expanduser(str_arg(name, if (len(args) > 0) args[0] else nilv, line)?);
		let img = viper::image { w = win.width, h = win.height, pixels = win.pixels };
		match (viper::save_png(&img, p)) {
		case void => return nilv: value;
		case => return dief(line, "screenshot(): kan ikke gemme '{}'", p);
		};
	case => return jj3_call(name, args, line);
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
