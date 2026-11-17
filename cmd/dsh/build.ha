// violet build: oversæt et .Dash-script til en native binær. 💜
//
// Programmet skrives som Hare-kode i en midlertidig mappe sammen med dsh'
// runtime (indlejret i rtsrc.ha af Makefile), og `hare build` laver
// binæren. Det kræver altså, at hare er installeret.
use fmt;
use fs;
use io;
use os;
use os::exec;
use strings;
use temp;

fn read_script(path: str) []u8 = {
	const f = match (os::open(path)) {
	case let f: io::file => yield f;
	case => fail_and_exit(strings::concat("kan ikke åbne ", path)!);
	};
	defer close(f);
	return io::drain(f)!;
};

fn parse_script(src: []u8) []stmt = {
	const toks = match (lex(src, 1)) {
	case let t: []token => yield t;
	case failed =>
		report_error();
		os::exit(1);
	};
	let p = parser { src = src, toks = toks, ... };
	match (program(&p)) {
	case let s: []stmt => return s;
	case failed =>
		report_error();
		os::exit(1);
	};
};

fn violet_compile(path: str) str = {
	script_name = path;
	script_src = read_script(path);
	const prog = parse_script(script_src);
	const code = compile_program(prog, path, script_src);
	if (len(cerrs) > 0) {
		fmt::errorfln("{}💜✘ violet{} {} kan ikke oversættes endnu:", red(), reset(), path)!;
		for (let e .. cerrs) fmt::errorfln("   {}", e)!;
		fmt::errorfln("{}   (scriptet kører stadig fint med dsh){}", dim(), reset())!;
		os::exit(1);
	};
	return code;
};

fn write_text(path: str, text: str) void = {
	const f = match (os::create(path, 0o644, fs::flag::WRONLY | fs::flag::TRUNC | fs::flag::CREATE)) {
	case let f: io::file => yield f;
	case let e: fs::error => fail_and_exit(fmt::asprintf("kan ikke skrive {}: {}", path, fs::strerror(e))!);
	};
	io::writeall(f, strings::toutf8(text))!;
	close(f);
};

// violet hare fil.Dash — viser den Hare-kode, Violet laver
fn hare_main(path: str) never = {
	fmt::print(violet_compile(path))!;
	os::exit(0);
};

fn build_main(path: str, out: str) never = {
	const code = violet_compile(path);
	const dir = temp::dir();
	const work = fmt::asprintf("{}/violet-{}", dir, exec::self(): int)!;
	match (os::mkdirs(work, 0o755)) {
	case void => void;
	case let e: fs::error => fail_and_exit(fmt::asprintf("kan ikke lave {}: {}", work, fs::strerror(e))!);
	};
	for (let i = 0z; i < len(RT_NAMES); i += 1) {
		write_text(strings::concat(work, "/", RT_NAMES[i])!, RT_SRCS[i]);
	};
	write_text(strings::concat(work, "/prog.ha")!, code);

	fmt::printfln("{}💜 violet{} {} → {}", col("\x1b[1;38;5;141m"), reset(), path, out)!;
	let cmd = match (exec::cmd("hare", "build", "-q", "-lc", "-o", out, work)) {
	case let c: exec::command => yield c;
	case => fail_and_exit("hare findes ikke — Violet skal bruge Hare for at bygge");
	};
	const ok = match (exec::start(&cmd)) {
	case let p: exec::process =>
		const st = exec::wait(&p)!;
		yield exec::check(&st) is void;
	case => yield false;
	};
	if (!ok) {
		fmt::errorfln("{}💜✘ hare build fejlede{} — koden ligger i {}", red(), reset(), work)!;
		os::exit(1);
	};
	match (os::rmdirall(work)) { case => void; };
	fmt::printfln("  {}✔ færdig:{} {}{}", col("\x1b[1;32m"), reset(),
		if (strings::contains(out, "/")) "" else "./", out)!;
	os::exit(0);
};
