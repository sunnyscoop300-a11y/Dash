// Fælles for dsh og Violets programmer: version, fejlbeskeder og farver.
use fmt;
use io;
use os;
use strings;

def VERSION: str = "0.15.0-hare";
// hver version får et navn fra Farming Life in Another World
def KODENAVN: str = "Flora";

let script_name = "dsh";
let script_src: []u8 = [];

fn col(code: str) str = if (is_tty(os::stderr_file)) code else "";
fn red() str = col("\x1b[1;38;5;196m");
fn orange() str = col("\x1b[1;38;5;208m");
fn dim() str = col("\x1b[2m");
fn reset() str = col("\x1b[0m");

fn source_line(line: int) str = {
	// importerede filer har deres linjer lagt oven i nr. × KILDE_LINJER
	const src = kilde_src(line);
	const (_, n) = kilde_sted(line);
	let cur = 1;
	for (let i = 0z; i < len(src); i += 1) {
		if (cur == n) {
			let j = i;
			for (j < len(src) && src[j] != '\n') j += 1;
			return strings::trim(strings::fromutf8_unsafe(src[i..j]));
		};
		if (src[i] == '\n') cur += 1;
	};
	return "";
};

fn report_error() void = {
	if (err_line > 0) {
		const (fil, n) = kilde_sted(err_line);
		fmt::errorfln("{}⚡✘ dsh{}{} {}:{}: {}{}", red(), reset(), orange(),
			fil, n, reset(), err_msg)!;
		const l = source_line(err_line);
		if (len(l) > 0) fmt::errorfln("{}   {:4} │ {}{}", dim(), n, l, reset())!;
		if (len(err_hint) > 0) fmt::errorfln("{}        ↳ {}{}", orange(), err_hint, reset())!;
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
		"     /___  /      dsh",
		"        / /       hurtigere end sh",
		"       / /",
		"      /_/",
	];
	const tty = is_tty(os::stdout_file);
	for (let i = 0z; i < len(lines); i += 1) {
		const c = if (!tty) "" else if (i < 4) "\x1b[1;38;5;196m" else "\x1b[1;38;5;208m";
		if (i == 3) {
			fmt::printfln("{}{} {} «{}»{}", c, lines[i], VERSION, KODENAVN,
				if (tty) "\x1b[0m" else "")!;
		} else {
			fmt::printfln("{}{}{}", c, lines[i], if (tty) "\x1b[0m" else "")!;
		};
	};
	fmt::printfln("{}  .Dash — et script-sprog med superfart ⚡{}",
		if (tty) "\x1b[2m" else "", if (tty) "\x1b[0m" else "")!;
};

