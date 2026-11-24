// JJGui — gamepads (PS5 DualSense, PS4, Xbox …) gennem Linux' joystick-API.
// Over Bluetooth gør kernen (hid-playstation, hid-sony, xpad) controlleren
// til /dev/input/jsN; vi læser den uden blokering hvert billede. Ingen SDL,
// så det virker med alle backends — også Termux:X11 på telefonen.
//
//   pad_name()      → "DualSense Wireless Controller" eller "" (ingen)
//   pad_button(n)   → true mens knap n holdes nede
//   pad_axis(n)     → -32767 … 32767 (pinde, L2/R2, d-pad)
use errors;
use fmt;
use fs;
use io;
use os;
use strings;

let pad_fd: (io::file | void) = void;
let pad_btn: [32]bool = [false...];
let pad_axes: [16]i16 = [0...];
let pad_name_s: str = "";
let pad_wait = 0;

fn pad_reset() void = {
	pad_btn = [false...];
	pad_axes = [0...];
};

fn pad_try_open() void = {
	// DASH_PAD=sti: læs en anden fil (til test, eller en bestemt controller)
	const fast = os::tryenv("DASH_PAD", "");
	for (let i = 0; i < 4; i += 1) {
		if (fast != "" && i > 0) return;
		const p = if (fast != "") strings::dup(fast)! else fmt::asprintf("/dev/input/js{}", i)!;
		defer free(p);
		match (os::open(p, fs::flag::RDONLY | fs::flag::NONBLOCK)) {
		case let f: io::file =>
			pad_fd = f;
			pad_reset();
			const np = fmt::asprintf("/sys/class/input/js{}/device/name", i)!;
			defer free(np);
			pad_name_s = match (os::open(np)) {
			case let nf: io::file =>
				defer close(nf);
				yield match (io::drain(nf)) {
				case let b: []u8 =>
					yield strings::dup(strings::trim(strings::fromutf8_unsafe(b)))!;
				case => yield strings::dup("gamepad")!;
				};
			case => yield strings::dup("gamepad")!;
			};
			return;
		case fs::error => void;
		};
	};
};

// Kaldes fra frame(): læs alle ventende hændelser; find controlleren igen,
// hvis den kobles til eller fra (hvert andet sekund).
fn pad_poll() void = {
	const f = match (pad_fd) {
	case let f: io::file => yield f;
	case void =>
		if (pad_wait > 0) {
			pad_wait -= 1;
			return;
		};
		pad_wait = 120;
		pad_try_open();
		return;
	};
	let buf: [512]u8 = [0...];
	for (true) {
		match (io::read(f, buf)) {
		case let n: size =>
			for (let o = 0z; o + 8 <= n; o += 8) {
				// struct js_event { u32 time; s16 value; u8 type; u8 number }
				const v = (buf[o + 4]: u16 | buf[o + 5]: u16 << 8): i16;
				const typ = buf[o + 6] & 0x7f;
				const nr = buf[o + 7]: size;
				if (typ == 1 && nr < len(pad_btn)) pad_btn[nr] = v != 0;
				if (typ == 2 && nr < len(pad_axes)) pad_axes[nr] = v;
			};
			if (n < len(buf)) return;
		case io::EOF =>
			return;
		case let e: io::error =>
			match (e) {
			case errors::again => return;
			case =>
				// koblet fra (fx Bluetooth slukket): prøv igen senere
				close(f);
				pad_fd = void;
				free(pad_name_s);
				pad_name_s = "";
				pad_reset();
				return;
			};
		};
	};
};

fn jj_pad_call(name: str, args: []value, line: int) (value | failed | void) = {
	switch (name) {
	case "pad_name" =>
		return strings::dup(pad_name_s)!;
	case "pad_button" =>
		need(name, args, 1, line)?;
		const n = int_arg(name, args[0], line)?;
		if (n < 0 || n >= len(pad_btn): i64) return false;
		return pad_btn[n: size];
	case "pad_axis" =>
		need(name, args, 1, line)?;
		const n = int_arg(name, args[0], line)?;
		if (n < 0 || n >= len(pad_axes): i64) return 0i64;
		return pad_axes[n: size]: i64;
	case => return;
	};
};
