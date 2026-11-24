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
use crypto::sha256;
use encoding::hex;
use hash;

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

// Oversætter et script. Kan det ikke oversættes, er resultatet void, og
// grundene ligger i cerrs.
fn try_compile(path: str) (str | void) = {
	script_name = path;
	script_src = read_script(path);
	const prog = parse_script(script_src);
	const code = compile_program(prog, path, script_src);
	// glem de importerede filer igen: går vi videre til fortolkeren, skal
	// den indlæse dem selv (ellers springer den dem over som "kendte")
	delete(kilder[..]);
	if (len(cerrs) > 0) return;
	return code;
};

fn violet_compile(path: str) str = {
	match (try_compile(path)) {
	case let code: str => return code;
	case void =>
		fmt::errorfln("{}💜✘ violet{} {} kan ikke oversættes endnu:", red(), reset(), path)!;
		for (let e .. cerrs) fmt::errorfln("   {}", e)!;
		fmt::errorfln("{}   (scriptet kører stadig fint med dsh){}", dim(), reset())!;
		os::exit(1);
	};
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

// Bygger Hare-koden til en binær. small: release-tilstand (-R) + strip.
// arch: "" for denne maskine, ellers fx "aarch64". Fejl skrives kun, når
// quiet er false; koden bliver så liggende til fejlsøgning.
fn hare_build(code: str, out: str, small: bool, arch: str, quiet: bool) bool = {
	const work = fmt::asprintf("{}/violet-{}", temp::dir(), exec::self(): int)!;
	match (os::mkdirs(work, 0o755)) {
	case void => void;
	case let e: fs::error =>
		if (!quiet) fmt::errorfln("kan ikke lave {}: {}", work, fs::strerror(e))!;
		return false;
	};
	// programmet i work/prog, JJGui's motor (viper) i work/viper
	const progdir = strings::concat(work, "/prog")!;
	os::mkdirs(progdir, 0o755)!;
	for (let i = 0z; i < len(RT_NAMES); i += 1) {
		write_text(strings::concat(progdir, "/", RT_NAMES[i])!, RT_SRCS[i]);
	};
	write_text(strings::concat(progdir, "/prog.ha")!, code);

	// android: aarch64 uden libc, linket som PIE til Android's linker64
	const android = arch == "android";
	const jj = uses_jj(code);
	// JJGui til en anden maskine (fx telefonen): uden SDL2, med X11/Wayland i ren Hare
	const cross = android || (arch != "" && arch != host_arch());
	if (jj) {
		const vdir = strings::concat(work, "/viper")!;
		os::mkdirs(vdir, 0o755)!;
		for (let i = 0z; i < len(VIPER_NAMES); i += 1) {
			write_text(strings::concat(vdir, "/", VIPER_NAMES[i])!, VIPER_SRCS[i]);
		};
	};
	const sdl = jj && !cross && have_sdl();
	let hargs: []str = [];
	append(hargs, ["build", "-q"]...)!;
	if (small || android) append(hargs, "-R")!;
	if (android) {
		append(hargs, ["-a", "aarch64"]...)!;
	} else if (arch != "") {
		append(hargs, ["-a", arch]...)!;
	};
	if (!jj) {
		append(hargs, ["-T", "+nojj"]...)!;
	} else if (!sdl) {
		append(hargs, ["-T", "+nosdl"]...)!;
	};
	if (!android) append(hargs, "-lc")!;
	if (sdl) append(hargs, "-lSDL2")!;
	const absout = if (strings::hasprefix(out, "/")) out
		else strings::concat(os::getcwd(), "/", out)!;
	append(hargs, ["-o", absout, "prog"]...)!;
	let cmd = match (exec::cmd("hare", hargs...)) {
	case let c: exec::command => yield c;
	case =>
		if (!quiet) fmt::errorln("hare findes ikke — Violet skal bruge Hare for at bygge")!;
		return false;
	};
	exec::chdir(&cmd, work);
	// uden HAREPATH bruger hare sin egen standardsti — den skal med,
	// ellers kan hare ikke finde rt og resten af standardbiblioteket
	const hp = match (os::getenv("HAREPATH")) {
	case let s: str => yield s;
	case void => yield hare_default_path();
	};
	exec::setenv(&cmd, "HAREPATH", if (hp == "") work else strings::concat(hp, ":", work)!)!;
	if (android) {
		match (android_env(&cmd, work)) {
		case void => void;
		case => return false;
		};
	} else {
		cross_env(&cmd, arch);
	};
	if (quiet) exec::nullstd(&cmd)!;
	const ok = match (exec::start(&cmd)) {
	case let p: exec::process =>
		const st = exec::wait(&p)!;
		yield exec::check(&st) is void;
	case => yield false;
	};
	if (!ok) {
		if (!quiet) fmt::errorfln("{}💜✘ hare build fejlede{} — koden ligger i {}", red(), reset(), work)!;
		return false;
	};
	match (os::rmdirall(work)) { case => void; };
	match (os::rmdirall(strings::concat(work, "-ld")!)) { case => void; };
	if (small || android) {
		const strip = if (arch == "" || arch == host_arch()) "strip"
			else if (arch == "android") "aarch64-linux-gnu-strip"
			else strings::concat(gnu_prefix(arch), "strip")!;
		match (exec::cmd(strip, out)) {
		case let c: exec::command =>
			exec::nullstd(&c)!;
			match (exec::start(&c)) {
			case let p: exec::process => match (exec::wait(&p)) { case => void; };
			case => void;
			};
		case =>
			if (!quiet) fmt::errorfln("  ({} findes ikke — binæren er bygget, men ikke gjort mindre)", strip)!;
		};
	};
	return true;
};

fn build_main(path: str, out: str, small: bool, arch: str) never = {
	const code = violet_compile(path);
	fmt::printfln("{}💜 violet{} {} → {}{}", col("\x1b[1;38;5;141m"), reset(), path, out,
		if (arch == "") "" else fmt::asprintf("  ({})", arch)!)!;
	if (!hare_build(code, out, small, arch, false)) os::exit(1);
	let kb = "";
	match (os::stat(out)) {
	case let st: fs::filestat => kb = fmt::asprintf(" ({} KB)", st.sz / 1024)!;
	case => void;
	};
	fmt::printfln("  {}✔ færdig:{} {}{}{}{}{}", col("\x1b[1;32m"), reset(),
		if (strings::contains(out, "/")) "" else "./", out, dim(), kb, reset())!;
	os::exit(0);
};

// Bruger programmet JJGui? (Violet kalder alle indbyggede funktioner via call())
fn uses_jj(code: str) bool = {
	for (let n .. JJ_FNS) {
		if (strings::contains(code, strings::concat("call(\"", n, "\"")!)) return true;
	};
	return false;
};

// SDL2 til X11; findes den ikke, bruges kun ViperGui's egen Wayland-del.
fn have_sdl() bool = {
	const dirs = ["/usr/lib", "/usr/lib64", "/usr/lib/x86_64-linux-gnu",
		"/usr/lib/aarch64-linux-gnu", "/usr/local/lib"];
	for (let d .. dirs) {
		if (os::exists(strings::concat(d, "/libSDL2.so")!)) return true;
	};
	return false;
};

// --- krydsoversættelse (violet fil.Dash --arch aarch64)

fn host_arch() str = os::arch_name(os::architecture());

fn gnu_prefix(arch: str) str = strings::concat(arch, "-linux-gnu-")!;

// Til en anden arkitektur bygges binæren statisk: så har den ingen
// afhængigheder og kører både i Termux på en telefon og på en Raspberry Pi.
// Den skal være static-pie: Android kører kun position-uafhængige programmer
// (en almindelig statisk binær giver "unexpected e_type: 2" i Termux).
// Hare finder selv aarch64-linux-gnu-gcc osv.
fn cross_env(cmd: *exec::command, arch: str) void = {
	if (arch == "" || arch == host_arch()) return;
	exec::setenv(cmd, "LDFLAGS", "-static-pie")!;
	// hare bruger $AS/$CC/$LD, hvis de er sat — også når de peger på
	// værktøjerne til denne maskine. Sæt dem til krydsværktøjerne.
	const pre = gnu_prefix(arch);
	exec::setenv(cmd, "AS", strings::concat(pre, "as")!)!;
	exec::setenv(cmd, "CC", strings::concat(pre, "gcc")!)!;
	exec::setenv(cmd, "LD", strings::concat(pre, "ld")!)!;
};

fn check_arch(arch: str) void = {
	if (arch == "android") {
		match (exec::lookup("aarch64-linux-gnu-ld")) {
		case str => return;
		case => fail_and_exit("aarch64-linux-gnu-ld mangler — på Arch: sudo pacman -S aarch64-linux-gnu-binutils");
		};
	};
	if (arch != "aarch64" && arch != "riscv64" && arch != "x86_64") {
		fail_and_exit(strings::concat("ukendt arkitektur '", arch,
			"' — brug android (Termux), aarch64 (Raspberry Pi), riscv64 eller x86_64")!);
	};
	if (arch == host_arch()) return;
	match (exec::lookup(strings::concat(gnu_prefix(arch), "gcc")!)) {
	case str => void;
	case => fail_and_exit(fmt::asprintf("krydsoversætteren {}gcc mangler — på Arch: sudo pacman -S {}-linux-gnu-gcc",
		gnu_prefix(arch), arch)!);
	};
};

// --- violet run: byg kun når scriptet er ændret, og kør så binæren

fn cache_dir() str = {
	match (os::getenv("XDG_CACHE_HOME")) {
	case let d: str => if (len(d) > 0) return strings::concat(d, "/violet")!;
	case void => void;
	};
	return strings::concat(os::tryenv("HOME", "/tmp"), "/.cache/violet")!;
};

// Filnavnet i cachen: scriptets navn + et fingeraftryk af indhold, sti,
// version, selve dsh-binæren og alle importerede filer — så en ny Violet, en
// genbygget dsh (fx med en rettet ViperGui) eller en ændring i et modul
// giver en ny binær.
fn cache_key(path: str, src: []u8) (str, str) = {
	let h = sha256::sha256();
	hash::write(&h, strings::toutf8(VERSION));
	hash::write(&h, [0]);
	// dsh selv: størrelse og ændringstid (billigere end at læse hele filen).
	// /proc/self/exe er et link; dets egen tid er processens starttid, så
	// vi slår den rigtige fil op først.
	match (os::realpath("/proc/self/exe")) {
	case let exe: str =>
		match (os::stat(exe)) {
		case let st: fs::filestat =>
			hash::write(&h, strings::toutf8(fmt::asprintf("{}:{}:{}",
				st.sz, st.mtime.sec, st.mtime.nsec)!));
		case => void;
		};
	case => void;
	};
	hash::write(&h, [0]);
	hash::write(&h, strings::toutf8(path));
	hash::write(&h, [0]);
	hash::write(&h, src);
	let set: []str = [];
	hash_imports(&h, src, path, &set);
	let sum: [sha256::SZ]u8 = [0...];
	hash::sum(&h, sum);
	const hex = hex::encodestr(sum[..8])!;
	// kun bogstaver og tal fra navnet
	let base: []u8 = [];
	const b = strings::toutf8(path);
	let start = 0z;
	for (let i = 0z; i < len(b); i += 1) if (b[i] == '/') start = i + 1;
	for (let c .. b[start..]) {
		if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
				|| c == '-' || c == '_' || c == '.') append(base, c)!;
	};
	const name = strings::fromutf8_unsafe(base);
	return (name, strings::concat(name, "-", hex)!);
};

// Følger `import "…"`-linjerne (rekursivt, hver fil én gang) og lægger de
// importerede filers sti og indhold i fingeraftrykket.
fn hash_imports(h: *sha256::state, src: []u8, fil: str, set: *[]str) void = {
	const tekst = strings::fromutf8_unsafe(src);
	const it = strings::tokenize(tekst, "\n");
	for (true) {
		const linje = match (strings::next_token(&it)) {
		case let l: str => yield strings::ltrim(l);
		case done => break;
		};
		if (!strings::hasprefix(linje, "import \"")) continue;
		const rest = strings::sub(linje, len("import \""), strings::end);
		const (navn, _) = strings::cut(rest, "\"");
		const sti = match (find_import(navn, fil)) {
		case let s: str => yield s;
		case void => continue;
		};
		let kendt = false;
		for (let s .. *set) if (s == sti) kendt = true;
		if (kendt) continue;
		append(set, sti)!;
		const isrc = match (os::open(sti)) {
		case let f: io::file =>
			defer io::close(f)!;
			yield match (io::drain(f)) {
			case let b: []u8 => yield b;
			case => continue;
			};
		case => continue;
		};
		hash::write(h, strings::toutf8(sti));
		hash::write(h, [0]);
		hash::write(h, isrc);
		hash_imports(h, isrc, sti, set);
	};
};

// Fjerner gamle binærer for samme script (andet fingeraftryk).
fn cache_clean(dir: str, name: str, keep: str) void = {
	const it = match (os::iter(dir)) {
	case let it: *fs::iterator => yield it;
	case => return;
	};
	defer fs::finish(it);
	const prefix = strings::concat(name, "-")!;
	for (true) {
		const ent = match (fs::next(it)) {
		case let e: fs::dirent => yield e;
		case => break;
		};
		if (!strings::hasprefix(ent.name, prefix)) continue;
		if (strings::hasprefix(ent.name, keep)) continue;
		// kun fingeraftryk med 16 hex-tegn efter navnet
		const rest = strings::sub(ent.name, len(prefix), strings::end);
		if (len(rest) < 16) continue;
		match (os::remove(strings::concat(dir, "/", ent.name)!)) { case => void; };
	};
};

fn exec_bin(bin: str, rest: []str) never = {
	flush_out();
	let cmd = match (exec::cmd(bin, rest...)) {
	case let c: exec::command => yield c;
	case => fail_and_exit(strings::concat("kan ikke starte ", bin)!);
	};
	const err = exec::exec(&cmd);
	fail_and_exit(fmt::asprintf("kan ikke starte {}: {}", bin, exec::strerror(err))!);
};

// Returnerer kun, hvis scriptet skal køres af fortolkeren i stedet.
fn run_main(path: str, rest: []str) void = {
	const src = read_script(path);
	const dir = cache_dir();
	const (name, key) = cache_key(path, src);
	const bin = strings::concat(dir, "/", key)!;
	const marker = strings::concat(bin, ".dsh")!;

	if (os::exists(bin)) exec_bin(bin, rest);
	if (os::exists(marker)) return;           // kendt: kan ikke oversættes
	if (!(exec::lookup("hare") is str)) return;  // ingen Hare: fortolk

	match (os::mkdirs(dir, 0o755)) { case => void; };
	const tty = is_tty(os::stderr_file);
	const code = match (try_compile(path)) {
	case let c: str => yield c;
	case void =>
		// husk det, så næste gang starter fortolkeren med det samme
		write_text(marker, strings::join("\n", cerrs...)!);
		if (tty) {
			fmt::errorfln("{}💜 violet: {} kan ikke oversættes endnu ({}) — kører med dsh{}",
				dim(), path, cerrs[0], reset())!;
		};
		return;
	};
	if (tty) fmt::errorfln("{}💜 violet bygger {} …{}", dim(), path, reset())!;
	const tmp = fmt::asprintf("{}.tmp-{}", bin, exec::self(): int)!;
	if (!hare_build(code, tmp, true, "", true)) {
		match (os::remove(tmp)) { case => void; };
		write_text(marker, "hare build fejlede");
		if (tty) fmt::errorfln("{}💜 violet: hare build fejlede — kører med dsh (prøv: violet {}){}",
			dim(), path, reset())!;
		return;
	};
	match (os::rename(tmp, bin)) {
	case void => void;
	case => return;
	};
	cache_clean(dir, name, key);
	exec_bin(bin, rest);
};

// --- Android (violet fil.Dash --arch android)
//
// Android kører kun programmer gennem sin egen loader, /system/bin/linker64,
// og den kan ikke starte glibc-programmer. Hare kan køre helt uden libc, kun
// med Linux-systemkald, så Violet bygger uden libc og linker selv: en PIE med
// linker64 som loader og kun relative relokeringer, som linker64 udfører,
// før Hares egen opstart tager over.
//
// .init_array omdøbes, så linker64 ikke også kører Hares @init-funktioner —
// det gør Hares opstart selv (via __init_array_start/_end).
def ANDROID_LD: str = `#!/bin/sh
# Lavet af Violet: linker et Hare-program som en PIE til Android's linker64.
ld=aarch64-linux-gnu-ld
sc="@DIR@/android.ld"
"$ld" -pie --verbose | sed -n '/^=======/,/^=======/p' | sed '1d;$d' \
	| sed 's/^  \.init_array    :/  .hare_init_array :/; s/^  \.fini_array    :/  .hare_fini_array :/' > "$sc"
interp="${VIOLET_INTERP:-/system/bin/linker64}"
skip=0
for a do
	shift
	if [ "$skip" = 1 ]; then skip=0; continue; fi
	if [ "$a" = "-T" ]; then skip=1; continue; fi
	set -- "$@" "$a"
done
exec "$ld" -pie -z text -z now -z noexecstack --hash-style=both \
	--dynamic-linker="$interp" -e _start -T "$sc" "$@"
`;

fn android_env(cmd: *exec::command, work: str) (void | fs::error) = {
	const dir = strings::concat(work, "-ld")!;
	os::mkdirs(dir, 0o755)?;
	const ld = strings::concat(dir, "/ld")!;
	write_text(ld, strings::replace(ANDROID_LD, "@DIR@", dir)!);
	os::chmod(ld, 0o755)?;
	exec::setenv(cmd, "AS", "aarch64-linux-gnu-as")!;
	exec::setenv(cmd, "LD", ld)!;
};

// Hares indbyggede HAREPATH, læst fra `hare version -v`:
//   HAREPATH:
//   	/usr/src/hare/stdlib
//   	/usr/src/hare/third-party
fn hare_default_path() str = {
	let cmd = match (exec::cmd("hare", "version", "-v")) {
	case let c: exec::command => yield c;
	case => return "";
	};
	const (r, w) = exec::pipe();
	exec::addfile(&cmd, os::stdout_file, w)!;
	exec::addfile(&cmd, os::stderr_file, exec::nullfd)!;
	const proc = match (exec::start(&cmd)) {
	case let p: exec::process => yield p;
	case =>
		io::close(r)!;
		io::close(w)!;
		return "";
	};
	io::close(w)!;
	const data = io::drain(r)!;
	io::close(r)!;
	match (exec::wait(&proc)) { case => void; };
	let paths: []str = [];
	let inside = false;
	for (let l .. strings::split(strings::fromutf8_unsafe(data), "\n")!) {
		if (l == "HAREPATH:") {
			inside = true;
		} else if (inside && strings::hasprefix(l, "\t")) {
			append(paths, strings::trim(l))!;
		} else if (inside) {
			break;
		};
	};
	return strings::join(":", paths...)!;
};

// violet prof: byg scriptet med målepunkter i hver fn og kør det. Returnerer
// kun, hvis det ikke kan oversættes — så måler fortolkeren i stedet.
fn prof_main(path: str, rest: []str) void = {
	if (!(exec::lookup("hare") is str)) return;
	cprof = true;
	const code = match (try_compile(path)) {
	case let c: str => yield c;
	case void =>
		cprof = false;
		fmt::errorfln("{}💜 violet prof: {} kan ikke oversættes endnu ({}) — måler med dsh{}",
			dim(), path, cerrs[0], reset())!;
		return;
	};
	const dir = cache_dir();
	match (os::mkdirs(dir, 0o755)) { case => void; };
	const (name, _) = cache_key(path, script_src);
	const bin = fmt::asprintf("{}/{}-prof", dir, name)!;
	fmt::errorfln("{}💜 violet prof bygger {} med målepunkter …{}", dim(), path, reset())!;
	if (!hare_build(code, bin, true, "", true)) {
		cprof = false;
		fmt::errorfln("{}💜 violet prof: hare build fejlede — måler med dsh{}", dim(), reset())!;
		return;
	};
	exec_bin(bin, rest);
};
