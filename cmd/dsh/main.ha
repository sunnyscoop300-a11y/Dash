// dsh — fortolkeren til .Dash-scripts. ⚡ Hurtigere end sh.
use fmt;
use io;
use os;
use strings;

def VERSION: str = "0.3-hare";

let script_name = "dsh";
let script_src: []u8 = [];

fn col(code: str) str = if (is_tty(os::stderr_file)) code else "";
fn red() str = col("\x1b[1;38;5;196m");
fn orange() str = col("\x1b[1;38;5;208m");
fn dim() str = col("\x1b[2m");
fn reset() str = col("\x1b[0m");

fn source_line(n: int) str = {
	let cur = 1, start = 0z;
	for (let i = 0z; i < len(script_src); i += 1) {
		if (cur == n) {
			let j = i;
			for (j < len(script_src) && script_src[j] != '\n') j += 1;
			return strings::trim(strings::fromutf8_unsafe(script_src[i..j]));
		};
		if (script_src[i] == '\n') cur += 1;
	};
	return "";
};

fn report_error() void = {
	if (err_line > 0) {
		fmt::errorfln("{}⚡✘ dsh{}{} {}:{}: {}{}", red(), reset(), orange(),
			script_name, err_line, reset(), err_msg)!;
		const l = source_line(err_line);
		if (len(l) > 0) fmt::errorfln("{}   {:4} │ {}{}", dim(), err_line, l, reset())!;
	} else {
		fmt::errorfln("{}⚡✘ dsh{} {}", red(), reset(), err_msg)!;
	};
};

fn fail_and_exit(msg: str) never = {
	flush_out();
	fmt::errorfln("{}⚡✘ {}{}", red(), reset(), msg)!;
	os::exit(1);
};

fn version() void = {
	const lines = [
		"        __",
		"       / /",
		"      / /___",
		"     /___  /      dsh 0.3-hare",
		"        / /       hurtigere end sh",
		"       / /",
		"      /_/",
	];
	const tty = is_tty(os::stdout_file);
	for (let i = 0z; i < len(lines); i += 1) {
		const c = if (!tty) "" else if (i < 4) "\x1b[1;38;5;196m" else "\x1b[1;38;5;208m";
		fmt::printfln("{}{}{}", c, lines[i], if (tty) "\x1b[0m" else "")!;
	};
	fmt::printfln("{}  .Dash — et script-sprog med superfart ⚡{}",
		if (tty) "\x1b[2m" else "", if (tty) "\x1b[0m" else "")!;
};

export fn main() void = {
	const args = os::args;
	if (len(args) > 1 && (args[1] == "-v" || args[1] == "--version")) {
		version();
		return;
	};
	if (len(args) < 2) {
		fmt::errorln("⚡ dsh — hurtigere end sh\n")!;
		fmt::errorln("brug: dsh script.Dash [args...]\n      dsh -e 'kode'\n      dsh --version")!;
		os::exit(2);
	};

	let rest: []str = [];
	if (args[1] == "-e") {
		if (len(args) < 3) fail_and_exit("-e mangler kode");
		script_name = "<-e>";
		script_src = strings::toutf8(args[2]);
		rest = args[3..];
	} else {
		script_name = args[1];
		const f = match (os::open(args[1])) {
		case let f: io::file => yield f;
		case =>
			fmt::errorfln("{}⚡✘ dsh{} kan ikke åbne {}", red(), reset(), args[1])!;
			os::exit(2);
		};
		script_src = io::drain(f)!;
		close(f);
		rest = args[2..];
	};

	root = newenv(null);
	let argl: []value = [];
	for (let a .. rest) append(argl, a)!;
	define(root, "args", newlist(argl));
	define(root, "script", script_name);
	define(root, "status", 0i64);

	const toks = match (lex(script_src, 1)) {
	case let t: []token => yield t;
	case failed =>
		report_error();
		os::exit(1);
	};
	let p = parser { src = script_src, toks = toks, ... };
	const prog = match (program(&p)) {
	case let s: []stmt => yield s;
	case failed =>
		report_error();
		os::exit(1);
	};
	match (run_block(prog, root)) {
	case flow => void;
	case failed =>
		flush_out();
		report_error();
		os::exit(1);
	};
	flush_out();
};
