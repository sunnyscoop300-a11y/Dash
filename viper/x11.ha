// ViperGui — X11 backend in pure Hare (no Xlib, no libc).
//
// Talks the X11 wire protocol over the server's unix socket: one window, a
// GC and PutImage for the frame, plus key, button, motion and close events.
// Used on X11 desktops without SDL2 and on Android with Termux:X11
// (DISPLAY=:0, socket in $TMPDIR/.X11-unix). Keycodes are evdev codes + 8,
// as on every modern X server, so the Wayland key tables are reused.
use endian;
use fmt;
use io;
use net;
use net::unix;
use os;
use strings;
use time;
use unix::poll;
use encoding::utf8;

export type x11_backend = struct {
	sock: net::socket,
	inbuf: [65536]u8,
	inlen: size,
	out: []u8,
	id_base: u32,
	id_mask: u32,
	next_id: u32,
	root: u32,
	depth: u8,
	maxreq: size,      // longest request in bytes
	win: u32,
	gc: u32,
	scale: f64,        // zoom (Termux:X11 fills the phone)
	ww: int,           // window size on screen
	wh: int,
	xmap: []u32,       // screen x -> frame x
	ymap: []u32,       // screen y -> frame y
	wm_protocols: u32,
	wm_delete: u32,
	closed: bool,
	failed: bool,
	shift: bool,
	caps: bool,
	ctrl: bool,
	altgr: bool,
	big: []u32,        // scaled frame when scale > 1
};

fn x11_socket(display: str) (str | error) = {
	// ":0", ":0.0", "unix:0" — only local displays
	let d = display;
	if (strings::hasprefix(d, "unix:")) d = strings::trimprefix(d, "unix");
	if (!strings::hasprefix(d, ":")) return "X11: kun lokale skærme (DISPLAY=:0) understøttes": error;
	d = strings::trimprefix(d, ":");
	match (strings::index(d, '.')) {
	case let i: size => d = strings::sub(d, 0, i);
	case void => void;
	};
	for (let dir .. [os::tryenv("TMPDIR", ""), "/tmp"]) {
		if (dir == "") continue;
		const p = fmt::asprintf("{}/.X11-unix/X{}", dir, d)!;
		if (os::exists(p)) return p;
		free(p);
	};
	return fmt::asprintf("X11: fandt ingen socket til DISPLAY={} (kører Termux:X11 / X-serveren?)", display)!: error;
};

// MIT-MAGIC-COOKIE-1 from ~/.Xauthority (or $XAUTHORITY), if there is one.
fn x11_cookie(display: str) ([]u8 | void) = {
	let path = os::tryenv("XAUTHORITY", "");
	if (path == "") {
		const home = os::tryenv("HOME", "");
		if (home == "") return;
		path = strings::concat(home, "/.Xauthority")!;
	};
	const f = match (os::open(path)) {
	case let f: io::file => yield f;
	case => return;
	};
	defer io::close(f)!;
	const data = match (io::drain(f)) {
	case let d: []u8 => yield d;
	case => return;
	};
	let num = strings::trimprefix(display, ":");
	match (strings::index(num, '.')) {
	case let i: size => num = strings::sub(num, 0, i);
	case void => void;
	};
	let i = 0z;
	for (i + 2 <= len(data)) {
		i += 2; // family
		let fields: [4][]u8 = [[]...];
		for (let k = 0z; k < 4; k += 1) {
			if (i + 2 > len(data)) return;
			const n = endian::begetu16(data[i..i + 2]): size;
			i += 2;
			if (i + n > len(data)) return;
			fields[k] = data[i..i + n];
			i += n;
		};
		const dnum = strings::fromutf8_unsafe(fields[1]);
		const name = strings::fromutf8_unsafe(fields[2]);
		if ((dnum == num || len(dnum) == 0) && name == "MIT-MAGIC-COOKIE-1") {
			return alloc(fields[3]...)!;
		};
	};
};

fn x11_log(msg: str) void = {
	if (os::getenv("VIPER_X11DEBUG") is str) fmt::errorfln("[x11] {}", msg)!;
};

fn x11_open(title: str, width: int, height: int) (*x11_backend | error | nomem) = {
	const display = match (os::getenv("DISPLAY")) {
	case let d: str => yield d;
	case void => return "X11: DISPLAY er ikke sat": error;
	};
	const path = x11_socket(display)?;
	x11_log(fmt::asprintf("forbinder til {}", path)!);
	const sock = match (unix::connect(path)) {
	case let s: net::socket => yield s;
	case let e: net::error =>
		return fmt::asprintf("X11: kan ikke forbinde til {}: {}", path, net::strerror(e))!: error;
	};
	let be = alloc(x11_backend { sock = sock, scale = 1.0, ... })?;
	x11_log("forbundet, sender opsætning");

	// --- forbindelsen ---
	let req: []u8 = [];
	defer free(req);
	const cookie = x11_cookie(display);
	const aname = if (cookie is []u8) "MIT-MAGIC-COOKIE-1" else "";
	const adata: []u8 = match (cookie) { case let c: []u8 => yield c; case void => yield []; };
	append(req, 0x6c: u8)!;
	append(req, 0u8)!;
	x_put16(&req, 11);
	x_put16(&req, 0);
	x_put16(&req, len(aname): u16);
	x_put16(&req, len(adata): u16);
	x_put16(&req, 0);
	append(req, strings::toutf8(aname)...)!;
	x_pad4(&req);
	append(req, adata...)!;
	x_pad4(&req);
	x11_write(be, req)?;

	let head: [8]u8 = [0...];
	x11_wait(be, 5000, "svar på opsætningen")?;
	x11_readall(be, head)?;
	x11_log(fmt::asprintf("svar: kode {}", head[0])!);
	const extra = endian::legetu16(head[6..8]): size * 4;
	let s: []u8 = alloc([0u8...], extra)?;
	defer free(s);
	x11_readall(be, s)?;
	if (head[0] != 1) {
		const n = head[1]: size;
		const why = if (n <= len(s)) strings::fromutf8_unsafe(s[..n]) else "";
		return fmt::asprintf("X11: serveren afviste forbindelsen ({})", why)!: error;
	};
	be.id_base = endian::legetu32(s[4..8]);
	be.id_mask = endian::legetu32(s[8..12]);
	const vlen = endian::legetu16(s[16..18]): size;
	be.maxreq = endian::legetu16(s[18..20]): size * 4;
	const nscreens = s[20];
	const nformats = s[21]: size;
	if (nscreens == 0) return "X11: ingen skærme": error;
	let o = 32 + (vlen + 3) / 4 * 4 + nformats * 8;
	be.root = endian::legetu32(s[o..o + 4]);
	const rw = endian::legetu16(s[o + 20..o + 22]): int;
	const rh = endian::legetu16(s[o + 22..o + 24]): int;
	be.depth = s[o + 38];
	x11_log(fmt::asprintf("skærm {}x{}, dybde {}, maxreq {} bytes, cookie: {}", rw, rh, be.depth, be.maxreq,
		cookie is []u8)!);
	if (be.depth != 24 && be.depth != 32) {
		return fmt::asprintf("X11: skærmen har {} bits farver (kun 24/32 understøttes)", be.depth)!: error;
	};

	// På telefonen fylder Termux:X11 hele skærmen: zoom op, så vinduet fylder den.
	let sc = match (os::getenv("VIPER_SCALE")) {
	case let v: str =>
		yield match (x_strconv_int(v)) { case let n: int => yield n: f64; case void => yield 1.0; };
	case void =>
		yield if (os::getenv("TERMUX_VERSION") is str) {
			const a = rw: f64 / width: f64, b = rh: f64 / height: f64;
			yield if (a < b) a else b;
		} else 1.0;
	};
	if (sc < 1.0) sc = 1.0;
	if (sc > 8.0) sc = 8.0;
	be.scale = sc;
	const ww = (width: f64 * sc): int, wh = (height: f64 * sc): int;
	be.ww = ww;
	be.wh = wh;
	if (sc > 1.0) {
		be.big = alloc([0u32...], (ww * wh): size)?;
		be.xmap = alloc([0u32...], ww: size)?;
		be.ymap = alloc([0u32...], wh: size)?;
		for (let x = 0; x < ww; x += 1) be.xmap[x] = (x: f64 / sc): u32;
		for (let y = 0; y < wh; y += 1) be.ymap[y] = (y: f64 / sc): u32;
	};

	x11_log(fmt::asprintf("zoom {}", sc)!);
	be.wm_protocols = x_intern(be, "WM_PROTOCOLS")?;
	x11_log("atomer hentet");
	be.wm_delete = x_intern(be, "WM_DELETE_WINDOW")?;
	const net_name = x_intern(be, "_NET_WM_NAME")?;
	const utf8_string = x_intern(be, "UTF8_STRING")?;

	// CreateWindow
	be.win = x_newid(be);
	let r: []u8 = [];
	defer free(r);
	const x = if (rw > ww) (rw - ww) / 2 else 0, y = if (rh > wh) (rh - wh) / 2 else 0;
	r = x_req_head(r, 1, 0, 10); // depth 0 = CopyFromParent
	x_put32(&r, be.win);
	x_put32(&r, be.root);
	x_put16(&r, x: u16);
	x_put16(&r, y: u16);
	x_put16(&r, ww: u16);
	x_put16(&r, wh: u16);
	x_put16(&r, 0);   // border
	x_put16(&r, 1);   // InputOutput
	x_put32(&r, 0);   // visual CopyFromParent
	x_put32(&r, 0x2 | 0x800); // background-pixel, event-mask
	x_put32(&r, 0);
	x_put32(&r, 0x1 | 0x2 | 0x4 | 0x8 | 0x40 | 0x8000 | 0x20000 | 0x200000);
	x11_send(be, r)?;

	// title (_NET_WM_NAME in UTF-8 and WM_NAME), close button, fixed size
	x_prop(be, net_name, utf8_string, 8, strings::toutf8(title))?;
	x_prop(be, 39, 31, 8, strings::toutf8(title))?;
	let atoms: [4]u8 = [0...];
	endian::leputu32(atoms, be.wm_delete);
	x_prop(be, be.wm_protocols, 4, 32, atoms)?;
	let hints: [72]u8 = [0...];
	endian::leputu32(hints[0..4], 16 | 32); // PMinSize | PMaxSize
	endian::leputu32(hints[20..24], ww: u32);
	endian::leputu32(hints[24..28], wh: u32);
	endian::leputu32(hints[28..32], ww: u32);
	endian::leputu32(hints[32..36], wh: u32);
	x_prop(be, 40, 41, 32, hints)?; // WM_NORMAL_HINTS, WM_SIZE_HINTS
	// WM_CLASS = app id, så proceslinjen finder den rigtige .desktop-fil (og ikonet)
	const id = strings::toutf8(app_id());
	let cls: []u8 = [];
	defer free(cls);
	append(cls, id...)!;
	append(cls, 0u8)!;
	append(cls, id...)!;
	append(cls, 0u8)!;
	x_prop(be, 67, 31, 8, cls)?; // WM_CLASS, STRING

	// CreateGC + MapWindow
	be.gc = x_newid(be);
	r = x_req_head(r, 55, 0, 4);
	x_put32(&r, be.gc);
	x_put32(&r, be.win);
	x_put32(&r, 0);
	x11_send(be, r)?;
	r = x_req_head(r, 8, 0, 2);
	x_put32(&r, be.win);
	x11_send(be, r)?;
	x11_flush(be)?;
	x11_log(fmt::asprintf("vindue {} oprettet ({}x{} ved {},{}) og vist", be.win, ww, wh, x, y)!);
	return be;
};

// Venter på data fra serveren (højst ms millisekunder).
fn x11_wait(be: *x11_backend, ms: i64, what: str) (void | error) = {
	let fds = [poll::pollfd { fd = be.sock, events = poll::event::POLLIN, ... }];
	match (poll::poll(fds, ms * time::MILLISECOND)) {
	case let n: uint =>
		if (n == 0) return fmt::asprintf("X11: serveren svarede ikke ({}) — er Termux:X11-appen åben?", what)!: error;
	case => void;
	};
};

fn x_strconv_int(s: str) (int | void) = {
	let n = 0;
	const b = strings::toutf8(strings::trim(s));
	if (len(b) == 0) return;
	for (let c .. b) {
		if (c < '0' || c > '9') return;
		n = n * 10 + (c - '0'): int;
	};
	return n;
};

fn x11_close(be: *x11_backend) void = {
	net::close(be.sock): void;
	free(be.out);
	free(be.big);
	free(be.xmap);
	free(be.ymap);
	free(be);
};

// ---- requests ----

fn x_put16(b: *[]u8, v: u16) void = {
	let x: [2]u8 = [0...];
	endian::leputu16(x, v);
	append(b, x...)!;
};

fn x_put32(b: *[]u8, v: u32) void = {
	let x: [4]u8 = [0...];
	endian::leputu32(x, v);
	append(b, x...)!;
};

fn x_pad4(b: *[]u8) void = {
	for (len(b) % 4 != 0) append(b, 0)!;
};

// Starts a request: opcode, the "data" byte, and the length in 4-byte units.
fn x_req_head(b: []u8, op: u8, data: u8, words: size) []u8 = {
	let b = b[..0];
	append(b, op)!;
	append(b, data)!;
	x_put16(&b, words: u16);
	return b;
};

fn x_newid(be: *x11_backend) u32 = {
	const id = be.id_base | (be.next_id & be.id_mask);
	be.next_id += 1;
	return id;
};

fn x_prop(be: *x11_backend, name: u32, kind: u32, format: u8, data: []u8) (void | error) = {
	const units = len(data) / (format: size / 8);
	let r: []u8 = [];
	defer free(r);
	r = x_req_head(r, 18, 0, 6 + (len(data) + 3) / 4); // ChangeProperty, Replace
	x_put32(&r, be.win);
	x_put32(&r, name);
	x_put32(&r, kind);
	append(r, format)!;
	for (let k = 0; k < 3; k += 1) append(r, 0u8)!;
	x_put32(&r, units: u32);
	append(r, data...)!;
	x_pad4(&r);
	x11_send(be, r)?;
};

fn x_intern(be: *x11_backend, name: str) (u32 | error) = {
	const b = strings::toutf8(name);
	let r: []u8 = [];
	defer free(r);
	r = x_req_head(r, 16, 0, 2 + (len(b) + 3) / 4); // InternAtom, only-if-exists = false
	x_put16(&r, len(b): u16);
	x_put16(&r, 0);
	append(r, b...)!;
	x_pad4(&r);
	x11_send(be, r)?;
	x11_flush(be)?;
	// wait for the reply (events arriving meanwhile are kept)
	for (let tries = 0; true; tries += 1) {
		if (tries > 25) return fmt::asprintf("X11: intet svar på InternAtom({})", name)!: error;
		x11_fill(be, 200)?;
		let i = 0z;
		for (i + 32 <= be.inlen) {
			const code = be.inbuf[i];
			const n = if (code == 1) 32 + endian::legetu32(be.inbuf[i + 4..i + 8]): size * 4 else 32z;
			if (i + n > be.inlen) break;
			if (code == 1) {
				const atom = endian::legetu32(be.inbuf[i + 8..i + 12]);
				be.inbuf[i..be.inlen - n] = be.inbuf[i + n..be.inlen];
				be.inlen -= n;
				return atom;
			};
			if (code == 0) return "X11: fejl ved InternAtom": error;
			i += n;
		};
	};
};

fn x11_send(be: *x11_backend, r: []u8) (void | error) = {
	append(be.out, r...)!;
	if (len(be.out) > 1 << 20) x11_flush(be)?;
};

fn x11_flush(be: *x11_backend) (void | error) = {
	if (len(be.out) == 0) return;
	x11_write(be, be.out)?;
	be.out = be.out[..0];
};

fn x11_write(be: *x11_backend, b: []u8) (void | error) = {
	let sendt = 0z;
	for (sendt < len(b)) {
		match (io::write(be.sock, b[sendt..])) {
		case let n: size => sendt += n;
		case let e: io::error =>
			be.failed = true;
			return fmt::asprintf("X11: skrivefejl: {}", io::strerror(e))!: error;
		};
	};
};

fn x11_readall(be: *x11_backend, buf: []u8) (void | error) = {
	let got = 0z;
	for (got < len(buf)) {
		match (io::read(be.sock, buf[got..])) {
		case let n: size => got += n;
		case io::EOF => return "X11: serveren lukkede forbindelsen": error;
		case let e: io::error => return fmt::asprintf("X11: læsefejl: {}", io::strerror(e))!: error;
		};
	};
};

// Reads what the server has sent, waiting at most ms milliseconds.
fn x11_fill(be: *x11_backend, ms: i64) (void | error) = {
	let fds = [poll::pollfd { fd = be.sock, events = poll::event::POLLIN, ... }];
	const n = match (poll::poll(fds, if (ms < 0) poll::NONBLOCK else ms * time::MILLISECOND)) {
	case let n: uint => yield n;
	case => return;
	};
	if (n == 0) return;
	if (be.inlen >= len(be.inbuf)) return;
	match (io::read(be.sock, be.inbuf[be.inlen..])) {
	case let k: size => be.inlen += k;
	case io::EOF =>
		be.closed = true;
		return "X11: serveren lukkede forbindelsen": error;
	case let e: io::error =>
		be.failed = true;
		return fmt::asprintf("X11: læsefejl: {}", io::strerror(e))!: error;
	};
};

// ---- frame ----

fn x11_present(win: *window, be: *x11_backend) void = {
	if (be.failed || be.closed) return;
	if (win.frames == 1) x11_log("første billede sendes");
	const w = be.ww, h = be.wh;
	let px = win.pixels;
	if (be.scale > 1.0) {
		let last = -1;
		for (let y = 0; y < h; y += 1) {
			const sy = be.ymap[y]: int;
			const row = (y * w): size;
			if (sy == last) {
				// same source row as the line above: copy it
				be.big[row..row + w: size] = be.big[row - w: size..row];
				continue;
			};
			last = sy;
			const src = win.pixels[(sy * win.width): size..((sy + 1) * win.width): size];
			for (let x = 0; x < w; x += 1) be.big[row + x: size] = src[be.xmap[x]];
		};
		px = be.big;
	};
	// PutImage in strips that fit the server's request limit
	const rowbytes = w: size * 4;
	let rows = (be.maxreq - 24) / rowbytes;
	if (rows < 1) rows = 1;
	let r: []u8 = [];
	defer free(r);
	for (let y = 0z; y < h: size; y += rows) {
		const n = if (y + rows > h: size) h: size - y else rows;
		r = x_req_head(r, 72, 2, 6 + n * rowbytes / 4); // PutImage, ZPixmap
		x_put32(&r, be.win);
		x_put32(&r, be.gc);
		x_put16(&r, w: u16);
		x_put16(&r, n: u16);
		x_put16(&r, 0);
		x_put16(&r, y: u16);
		append(r, 0u8)!;
		append(r, be.depth)!;
		append(r, 0u8)!;
		append(r, 0u8)!;
		const part = px[y * w: size..(y + n) * w: size];
		const bytes = (&part[0]: *[*]u8)[..n * rowbytes];
		append(r, bytes...)!;
		match (x11_send(be, r)) {
		case void => void;
		case error => return;
		};
	};
	match (x11_flush(be)) { case => void; };
};

// ---- events ----

fn x11_poll(win: *window, be: *x11_backend) bool = {
	match (x11_fill(be, -1)) {
	case void => void;
	case error => return false;
	};
	let i = 0z;
	for (i + 32 <= be.inlen) {
		const code = be.inbuf[i] & 0x7f;
		const n = if (code == 1) 32 + endian::legetu32(be.inbuf[i + 4..i + 8]): size * 4 else 32z;
		if (i + n > be.inlen) break;
		const ev = be.inbuf[i..i + 32];
		// key repeat: a KeyRelease directly followed by a KeyPress of the
		// same key at the same time is the server's auto-repeat
		if (code == 3 && i + 64 <= be.inlen && be.inbuf[i + 32] & 0x7f == 2
				&& be.inbuf[i + 33] == ev[1]
				&& endian::legetu32(be.inbuf[i + 36..i + 40]) == endian::legetu32(ev[4..8])) {
			x11_key(win, be, be.inbuf[i + 32..i + 64], true);
			i += 64;
			continue;
		};
		x11_event(win, be, code, ev);
		i += n;
	};
	be.inbuf[..be.inlen - i] = be.inbuf[i..be.inlen];
	be.inlen -= i;
	match (x11_flush(be)) {
	case void => void;
	case error => return false;
	};
	return !be.closed && !be.failed;
};

fn x11_event(win: *window, be: *x11_backend, code: u8, ev: []u8) void = {
	switch (code) {
	case 2 => x11_key(win, be, ev, false);   // KeyPress
	case 3 =>                                  // KeyRelease
		const hid = evdev_to_hid(ev[1]: u32 - 8);
		if (hid != 0) win.keys[hid] = 0;
		add_keyevent(win, keyevent { hid = hid: u16, ... });
	case 4, 5 =>                               // ButtonPress / ButtonRelease
		const down = code == 4;
		x11_pointer(win, be, ev);
		const b = ev[1];
		if (b == 4 || b == 5) {
			if (down) win.pend.wheel += if (b == 4) 1 else -1;
			return;
		};
		const bit: u8 = switch (b) {
		case 1 => yield LEFT_BUTTON;
		case 2 => yield MIDDLE_BUTTON;
		case 3 => yield RIGHT_BUTTON;
		case => yield 0;
		};
		if (down) {
			win.buttons |= bit;
			win.pend.clicks |= bit;
		} else {
			win.buttons &= ~bit;
		};
		if (b == 1) {
			if (down) {
				win.pend.mouse_pressed = true;
				win.mouse_down = true;
			} else {
				win.pend.mouse_released = true;
				win.mouse_down = false;
			};
		};
	case 6 => x11_pointer(win, be, ev);      // MotionNotify
	case 10 => win.keys = [0...];              // FocusOut
	case 33 =>                                 // ClientMessage
		if (endian::legetu32(ev[12..16]) == be.wm_delete) be.closed = true;
	case 0 =>                                  // error
		if (os::getenv("VIPER_X11DEBUG") is str) {
			fmt::errorfln("X11-fejl {} (request {})", ev[1], ev[10])!;
		};
	case => void;
	};
};

fn x11_pointer(win: *window, be: *x11_backend, ev: []u8) void = {
	const x = endian::legetu16(ev[24..26]): i16: int, y = endian::legetu16(ev[26..28]): i16: int;
	win.mouse_x = (x: f64 / be.scale): int;
	win.mouse_y = (y: f64 / be.scale): int;
};

fn x11_key(win: *window, be: *x11_backend, ev: []u8, repeat: bool) void = {
	const code = ev[1]: u32 - 8; // X keycode = evdev + 8
	const state = endian::legetu16(ev[28..30]);
	be.shift = state & 1 != 0;
	be.caps = state & 2 != 0;
	be.ctrl = state & 4 != 0;
	be.altgr = state & 0x80 != 0;
	const hid = evdev_to_hid(code);
	if (hid != 0) {
		if (!repeat) win.pend.keys_pressed[hid] = true;
		win.keys[hid] = 1;
		win.pend.keys_typed[hid] = true;
	};
	let r: (rune | void) = void;
	if (!be.ctrl) {
		const letter = (code >= 16 && code <= 26) || (code >= 30 && code <= 40)
			|| (code >= 44 && code <= 50);
		const shift = if (letter && be.caps) !be.shift else be.shift;
		r = layout_dk(code, shift, be.altgr);
		match (r) {
		case let c: rune => add_typed(win, utf8::encoderune(c));
		case void => void;
		};
	};
	add_keyevent(win, keyevent {
		hid = hid: u16,
		down = true,
		repeat = repeat,
		text = match (r) { case let c: rune => yield c; case void => yield '\0'; },
	});
};

// Vinduesikonet som _NET_WM_ICON: bredde, højde og pixels (0xAARRGGBB),
// skaleret ned til 48x48, så det passer i én forespørgsel.
fn x11_icon(be: *x11_backend, img: *image) void = {
	const small = match (resize(img, 48, 48)) {
	case let i: image => yield i;
	case => return;
	};
	defer image_free(&small);
	const atom = match (x_intern(be, "_NET_WM_ICON")) {
	case let a: u32 => yield a;
	case => return;
	};
	let data: []u8 = alloc([0u8...], 8 + len(small.pixels) * 4)!;
	defer free(data);
	endian::leputu32(data[0..4], 48);
	endian::leputu32(data[4..8], 48);
	for (let i = 0z; i < len(small.pixels); i += 1) {
		endian::leputu32(data[8 + i * 4..12 + i * 4], small.pixels[i]);
	};
	match (x_prop(be, atom, 6, 32, data)) { case => void; }; // CARDINAL
	match (x11_flush(be)) { case => void; };
};
