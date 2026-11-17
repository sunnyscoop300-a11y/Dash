// Hjælpere til Violets oversatte programmer. 💜
//
// Violet laver .Dash om til Hare-kode, der bygges sammen med resten af
// dsh' kode (værdier, builtins, kommandoer, fejlbeskeder). Det her er de
// små stykker, den oversatte kode kalder, hvor fortolkeren ellers ville
// have gjort det selv.
use fmt;
use os;
use os::exec;
use strings;
use time;

// --- fra dynamisk værdi til maskintype (Violets typer siger, at det passer)

fn as_int(v: value, line: int) (i64 | failed) = {
	match (v) {
	case let i: i64 => return i;
	case => return dief(line, "Violet ventede et heltal, men fik en {}", typename(v));
	};
};

fn as_float(v: value, line: int) (f64 | failed) = {
	match (v) {
	case let f: f64 => return f;
	case let i: i64 => return i: f64;
	case => return dief(line, "Violet ventede et kommatal, men fik en {}", typename(v));
	};
};

fn as_str(v: value, line: int) (str | failed) = {
	match (v) {
	case let s: str => return s;
	case => return dief(line, "Violet ventede tekst, men fik en {}", typename(v));
	};
};

fn as_bool(v: value, line: int) (bool | failed) = {
	match (v) {
	case let b: bool => return b;
	case => return truthy(v);
	};
};

// --- lister og maps

fn vlist(items: []value) value = {
	let c: []value = [];
	append(c, items...)!;
	return newlist(c);
};

fn vlist0() value = {
	let c: []value = [];
	return newlist(c);
};

fn vmap(keys: []value, vals: []value) value = {
	const m = alloc(mapv { ... })!;
	for (let i = 0z; i < len(keys); i += 1) map_set(m, keys[i], vals[i]);
	return m;
};

fn vmap0() value = alloc(mapv { ... })!;

fn index_v(obj: value, k: value, line: int) (value | failed) = {
	match (obj) {
	case let l: *list =>
		return l.items[list_index(l, k, line)?];
	case let m: *mapv =>
		match (map_find(m, k)) {
		case let i: size => return m.vals[i];
		case void => return nilv;
		};
	case let s: str =>
		const i = match (k) {
		case let i: i64 => yield i;
		case => return die(line, "indeks skal være et heltal");
		};
		const b = strings::toutf8(s);
		const j = if (i < 0) len(b): i64 + i else i;
		if (j < 0 || j >= len(b): i64) {
			return dief(line, "indeks {} er udenfor (længde {})", i, len(b));
		};
		return strings::dup(strings::fromutf8_unsafe(b[j..j + 1]))!;
	case => return dief(line, "kan ikke slå op i en {}", typename(obj));
	};
};

fn set_index(obj: value, k: value, v: value, line: int) (void | failed) = {
	match (obj) {
	case let l: *list =>
		l.items[list_index(l, k, line)?] = v;
	case let m: *mapv =>
		map_set(m, k, v);
	case => return dief(line, "kan ikke sætte [..] på en {}", typename(obj));
	};
};

fn set_attr(obj: value, name: str, v: value, line: int) (void | failed) = {
	match (obj) {
	case let m: *mapv => map_set(m, name, v);
	case => return dief(line, "kan kun sætte .{} på en map", name);
	};
};

// --- regning, der kan gå galt

fn imod(a: i64, b: i64, line: int) (i64 | failed) = {
	if (b == 0) return die(line, "division med nul — selv Dash kan ikke løbe uendeligt");
	return a % b;
};

fn fdiv(a: f64, b: f64, line: int) (f64 | failed) = {
	if (b == 0.0) return die(line, "division med nul — selv Dash kan ikke løbe uendeligt");
	return a / b;
};

fn neg_v(v: value, line: int) (value | failed) = {
	match (v) {
	case let i: i64 => return -i;
	case let f: f64 => return -f;
	case => return dief(line, "kan ikke bruge '-' på en {}", typename(v));
	};
};

// --- kommandoer

// Et ord, der kun er en $variabel uden anførselstegn: en liste bliver til
// flere argumenter.
fn expand_v(out: *[]str, v: value) void = {
	match (v) {
	case let l: *list =>
		for (let it .. l.items) append(out, tostr(it))!;
	case => append(out, tostr(v))!;
	};
};

fn one_v(v: value) str = {
	match (v) {
	case let l: *list =>
		let a: []str = [];
		defer free(a);
		for (let it .. l.items) append(a, tostr(it))!;
		return strings::join(" ", a...)!;
	case => return tostr(v);
	};
};

fn run_c(xs: []xstage, line: int, try_: bool) (void | failed) = {
	run_x(xs, null, line, false, try_)?;
	free(xs);
};

fn cap_x(xs: []xstage, line: int) (str | failed) = {
	defer free(xs);
	match (run_x(xs, null, line, true, false)?) {
	case let s: str => return s;
	case => return "";
	};
};

fn get_status() value = {
	match (env_find(root, "status")) {
	case let p: *value => return *p;
	case void => return 0i64;
	};
};

// Starter et oversat program: samme opsætning som dsh laver for et script.
fn rt_start(name: str, src: str) void = {
	root = newenv(null);
	let argl: []value = [];
	if (len(os::args) > 1) for (let a .. os::args[1..]) append(argl, a)!;
	define(root, "args", newlist(argl));
	define(root, "script", name);
	define(root, "status", 0i64);
	script_name = name;
	script_src = strings::toutf8(src);
};

fn rt_args() value = {
	match (env_find(root, "args")) {
	case let p: *value => return *p;
	case void => return vlist0();
	};
};

fn rt_end(r: (void | failed)) void = {
	match (r) {
	case void => flush_out();
	case failed =>
		flush_out();
		report_error();
		os::exit(1);
	};
};

// --- parallel-løkker (samme opførsel som run_parallel i eval.ha)

type par = struct {
	n: size,
	running: size,
	bad: size,
	runners: []exec::process,
	t0: time::instant,
};

fn par_begin(n: i64, line: int) (par | failed) = {
	if (n < 1) return die(line, "'parallel' skal have et heltal ≥ 1");
	flush_out();
	return par { n = n: size, t0 = time::now(time::clock::MONOTONIC), ... };
};

// true i løberen (barnet), false i hovedprogrammet
fn par_fork(p: *par, line: int) (bool | failed) = {
	if (p.running >= p.n) {
		if (!wait_one(&p.runners)) p.bad += 1;
		p.running -= 1;
	};
	match (exec::fork()) {
	case void => return true;
	case let pid: exec::process =>
		append(p.runners, pid)!;
		p.running += 1;
		return false;
	case let err: exec::error =>
		return dief(line, "kunne ikke starte en løber: {}", exec::strerror(err));
	};
};

fn par_child(r: (void | failed)) never = {
	flush_out();
	match (r) {
	case void => os::exit(0);
	case failed =>
		report_error();
		os::exit(1);
	};
};

fn par_end(p: *par, total: size, line: int) (void | failed) = {
	for (p.running > 0; p.running -= 1) {
		if (!wait_one(&p.runners)) p.bad += 1;
	};
	free(p.runners);
	if (p.bad > 0) return dief(line, "{} af {} løbere snublede", p.bad, total);
	if (is_tty(os::stderr_file) && os::tryenv("DSH_QUIET", "") != "1") {
		const ms = time::diff(p.t0, time::now(time::clock::MONOTONIC)) / time::MILLISECOND;
		const cs = (ms % 1000) / 10;
		fmt::errorfln("{}⚡ {} job · {} løbere · {}.{}{}s{}", orange(), total, p.n,
			ms / 1000, if (cs < 10) "0" else "", cs, reset())!;
	};
};

fn drop(v: value) void = void;
