// Lægger dsh' runtime (og JJGui's motor, viper/) ind i cmd/dsh/rtsrc.ha, så
// Violet kan bygge programmer uden at kildekoden skal ligge ved siden af.
// Køres af Makefile:  hare run tools/embed/   (fra repoets rod)
//
// Før var det et sh-script — nu er det Hare, så Dash ikke har shell inde i sig.
use fmt;
use fs;
use io;
use os;
use sort;
use sort::cmp;
use strings;

// filer i cmd/dsh, der ikke hører til runtime
const UDEN: [_]str = ["main.ha", "build.ha", "rtsrc.ha", "compile.ha", "types.ha", "miguel.ha"];

fn filer(dir: str, endelser: []str, spring: *fn(navn: str) bool) []str = {
	let ud: []str = [];
	const it = os::iter(dir)!;
	defer fs::finish(it);
	for (const e => fs::next(it)!) {
		if (!fs::isfile(e.ftype)) continue;
		let ok = false;
		for (const s .. endelser) if (strings::hassuffix(e.name, s)) ok = true;
		if (ok && !spring(e.name)) append(ud, strings::dup(e.name)!)!;
	};
	sort::sort(ud, size(str), &cmp::strs)!;
	return ud;
};

fn ikke_rt(navn: str) bool = {
	for (const u .. UDEN) if (u == navn) return true;
	return false;
};

fn test_fil(navn: str) bool = strings::hassuffix(navn, "+test.ha");

fn laes(sti: str) []u8 = {
	const f = os::open(sti)!;
	defer io::close(f)!;
	return io::drain(f)!;
};

// én kildefil som Hare-strengkonstant, en linje ad gangen (som før: \t"…\n")
fn lit(ud: *[]u8, sti: str) void = {
	const b = laes(sti);
	defer free(b);
	let i = 0z;
	for (i < len(b)) {
		let j = i;
		for (j < len(b) && b[j] != '\n') j += 1;
		append(ud, ['\t', '"']...)!;
		for (const c .. b[i..j]) {
			switch (c) {
			case '\\' => append(ud, ['\\', '\\']...)!;
			case '"' => append(ud, ['\\', '"']...)!;
			case '\t' => append(ud, ['\\', 't']...)!;
			case => append(ud, c)!;
			};
		};
		append(ud, strings::toutf8("\\n\"\n")...)!;
		i = j + 1;
	};
	append(ud, strings::toutf8("\t,\n")...)!;
};

fn skriv(ud: *[]u8, s: str) void = append(ud, strings::toutf8(s)...)!;

export fn main() void = {
	const rtdir = "cmd/dsh", vdir = "viper";
	// .ha først og så .s, ligesom før
	let rtf = filer(rtdir, [".ha"], &ikke_rt);
	append(rtf, filer(rtdir, [".s"], &ikke_rt)...)!;
	const vf = filer(vdir, [".ha"], &test_fil);

	let ud: []u8 = [];
	skriv(&ud, "// Lavet af tools/embed — rediger ikke. dsh' runtime til Violet.\n");
	skriv(&ud, "const RT_NAMES: [_]str = [");
	for (const f .. rtf) skriv(&ud, fmt::asprintf("\"{}\", ", f)!);
	skriv(&ud, "];\nconst RT_SRCS: [_]str = [\n");
	for (const f .. rtf) lit(&ud, fmt::asprintf("{}/{}", rtdir, f)!);
	skriv(&ud, "];\nconst VIPER_NAMES: [_]str = [");
	for (const f .. vf) skriv(&ud, fmt::asprintf("\"{}\", ", f)!);
	skriv(&ud, "];\nconst VIPER_SRCS: [_]str = [\n");
	for (const f .. vf) lit(&ud, fmt::asprintf("{}/{}", vdir, f)!);
	skriv(&ud, "];\n");

	// skriv kun, hvis noget er ændret (så hare ikke bygger alt om)
	const maal = "cmd/dsh/rtsrc.ha";
	match (os::open(maal)) {
	case let f: io::file =>
		const gl = io::drain(f)!;
		io::close(f)!;
		if (len(gl) == len(ud)) {
			let ens = true;
			for (let i = 0z; i < len(ud); i += 1) if (gl[i] != ud[i]) ens = false;
			if (ens) return;
		};
	case => void;
	};
	const f = os::create(maal, 0o644, fs::flag::WRONLY | fs::flag::TRUNC)!;
	defer io::close(f)!;
	io::writeall(f, ud)!;
};
