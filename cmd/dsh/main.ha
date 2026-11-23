// dsh — fortolkeren til .Dash-scripts. ⚡ Hurtigere end sh.
use fmt;
use io;
use os;
use strings;

export fn main() void = {
	let args = os::args;
	// Miguel 🎸: language server til editoren ("miguel" eller "dsh miguel")
	if (strings::hassuffix(args[0], "miguel") || (len(args) > 1 && args[1] == "miguel")) {
		miguel_main();
	};
	// startet som "violet-run" (til #!-linjen): samme som violet run
	if (strings::hassuffix(args[0], "violet-run")) {
		if (len(args) < 2) fail_and_exit("brug: violet-run fil.Dash [args...]");
		let a: []str = [];
		append(a, [args[0], "run"]...)!;
		append(a, args[1..]...)!;
		args = a;
	};
	// startet som "violet": violet fil.Dash bygger, violet types/hare/run fil.Dash
	if (strings::hassuffix(args[0], "violet")) {
		if (len(args) < 2) fail_and_exit("brug: violet fil.Dash [-o navn] [--strip] [--arch aarch64]\n      violet run fil.Dash [args...]   |   violet types fil.Dash   |   violet hare fil.Dash");
		let a: []str = [];
		append(a, args[0])!;
		if (args[1] != "types" && args[1] != "hare" && args[1] != "build" && args[1] != "run") {
			append(a, "build")!;
		};
		append(a, args[1..]...)!;
		args = a;
	};
	// violet run: kør den oversatte binær (bygges kun, når scriptet er ændret).
	// Kan scriptet ikke oversættes, kører fortolkeren det i stedet.
	if (len(args) > 1 && args[1] == "run") {
		if (len(args) < 3) fail_and_exit("brug: violet run fil.Dash [args...]");
		run_main(args[2], args[3..]);
		let a: []str = [];
		append(a, args[0])!;
		append(a, args[2..]...)!;
		args = a;
	};
	if (len(args) > 2 && args[1] == "hare") hare_main(args[2]);
	if (len(args) > 2 && args[1] == "build") {
		let out = "";
		let small = false;
		let arch = "";
		for (let i = 3z; i < len(args); i += 1) {
			if (args[i] == "-o" && i + 1 < len(args)) {
				i += 1;
				out = args[i];
			} else if (args[i] == "-s" || args[i] == "--strip") {
				small = true;
			} else if ((args[i] == "-a" || args[i] == "--arch") && i + 1 < len(args)) {
				i += 1;
				arch = args[i];
				check_arch(arch);
			} else {
				fail_and_exit(strings::concat("ukendt valg: ", args[i], " (brug -o navn, --strip, --arch aarch64)")!);
			};
		};
		if (out == "") {
			// fil.Dash → fil (bytevis, så æ ø å ikke forskubber noget)
			const b = strings::toutf8(args[2]);
			let start = 0z, end = 0z;
			for (let i = 0z; i < len(b); i += 1) if (b[i] == '/') start = i + 1;
			for (let i = start; i < len(b); i += 1) if (b[i] == '.') end = i;
			out = if (end > start) strings::fromutf8_unsafe(b[start..end])
				else strings::concat(strings::fromutf8_unsafe(b[start..]), ".bin")!;
		};
		// aldrig skrive oven i selve scriptet
		if (out == args[2]) out = strings::concat(out, ".bin")!;
		build_main(args[2], out, small, arch);
	};
	if (len(args) > 1 && (args[1] == "-v" || args[1] == "--version")) {
		version();
		return;
	};
	if (len(args) < 2) {
		fmt::errorln("⚡ dsh — hurtigere end sh\n")!;
		fmt::errorln("brug: dsh script.Dash [args...]\n      dsh check script.Dash\n      dsh types script.Dash   (Violet: typer)\n      dsh build script.Dash   (Violet: native binær)\n      dsh run script.Dash     (Violet: byg ved ændring og kør)\n      dsh -e 'kode'\n      dsh miguel              (Miguel: hjælp i editoren)\n      dsh --version")!;
		os::exit(2);
	};

	let rest: []str = [];
	if (args[1] == "types" || args[1] == "violet") {
		if (len(args) < 3) fail_and_exit("brug: dsh types fil.Dash");
		script_name = args[2];
		const f = match (os::open(args[2])) {
		case let f: io::file => yield f;
		case => fail_and_exit(strings::concat("kan ikke åbne ", args[2])!);
		};
		script_src = io::drain(f)!;
		close(f);
		types_main(script_src);
	};
	if (args[1] == "check" || args[1] == "--check") {
		if (len(args) < 3) fail_and_exit("brug: dsh check fil.Dash");
		script_name = args[2];
		const f = match (os::open(args[2])) {
		case let f: io::file => yield f;
		case => fail_and_exit(strings::concat("kan ikke åbne ", args[2])!);
		};
		script_src = io::drain(f)!;
		close(f);
		check_main(script_src);
	};
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
