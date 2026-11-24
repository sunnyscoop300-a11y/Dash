// Running commands: pipes, redirects, built-ins and strict errors.
use ascii;
use bufio;
use fs;
use io;
use os;
use os::exec;
use strings;
use unix::signal;
use unix::tty;

fn is_tty(f: io::file) bool = tty::isatty(f);

// Like dash's hash table: remember where each program lives, so PATH is
// searched once per name instead of once per run.
let path_names: []str = [];
let path_found: []str = [];

fn resolve(name: str) str = {
	if (strings::contains(name, "/")) return name;
	for (let i = 0z; i < len(path_names); i += 1) {
		if (path_names[i] == name) return path_found[i];
	};
	match (exec::lookup(name)) {
	case let full: str =>
		append(path_names, strings::dup(name)!)!;
		append(path_found, strings::dup(full)!)!;
		return path_found[len(path_found) - 1];
	case => return name;    // let exec::cmd report "findes ikke"
	};
};

fn flush_out() void = {
	match (bufio::flush(os::stdout)) { case => void; };
};

// A word becomes one argument — or several, when it is a lone unquoted
// $list. Words are never split on spaces.
fn expand(w: *word, e: *env, line: int, out: *[]str) (void | failed) = {
	if (!w.quoted && len(w.parts) == 1 && !(w.parts[0] is p_lit)) {
		const v = eval_part(w.parts[0], e, line)?;
		match (v) {
		case let l: *list =>
			for (let it .. l.items) append(out, tostr(it))!;
			return;
		case => void;
		};
		append(out, tostr(v))!;
		return;
	};
	let b: []u8 = [];
	for (let p .. w.parts) append(b, strings::toutf8(tostr(eval_part(p, e, line)?))...)!;
	append(out, strings::fromutf8_unsafe(b))!;
};

fn one(w: *word, e: *env, line: int) (str | failed) = {
	let a: []str = [];
	expand(w, e, line, &a)?;
	return strings::join(" ", a...)!;
};

// $(try …): som try på en kommando — fejler den, fås outputtet alligevel
fn cap_try(raw: str) (str, bool) = {
	const t = strings::ltrim(raw);
	if (strings::hasprefix(t, "try ") || strings::hasprefix(t, "try\t")) {
		return (strings::ltrim(strings::sub(t, 4, strings::end)), true);
	};
	return (raw, false);
};

fn capture(raw: str, e: *env, line: int) (value | failed) = {
	const (raw, try_) = cap_try(raw);
	const stages = parse_command(strings::toutf8(raw), line)?;
	match (run_cmd(stages, e, line, true, try_)?) {
	case let s: str => return s;
	case => return "";
	};
};

fn open_out(path: str, app: bool, line: int) (io::file | failed) = {
	const flags = if (app) fs::flag::WRONLY | fs::flag::APPEND | fs::flag::CREATE
		else fs::flag::WRONLY | fs::flag::TRUNC | fs::flag::CREATE;
	match (os::create(path, 0o644, flags)) {
	case let f: io::file => return f;
	case let err: fs::error => return dief(line, "kan ikke skrive til '{}': {}", path, fs::strerror(err));
	};
};

// cmd & — starts the pipeline in its own session and goes on at once.
// Output goes to /dev/null unless it is redirected, so no noise in the
// terminal (no more setsid -f … > /dev/null 2> /dev/null).
fn run_bg(stages: []stage, e: *env, line: int) (void | failed) = {
	bg_begin(line)?;
	defer bg_end();
	run_cmd(stages, e, line, false, true)?;
};

fn run_bg_x(stages: []xstage, line: int) (void | failed) = {
	bg_begin(line)?;
	defer bg_end();
	run_x(stages, null, line, false, true)?;
};

fn bg_begin(line: int) (void | failed) = {
	const devnull = match (os::open("/dev/null", fs::flag::RDWR)) {
	case let f: io::file => yield f;
	case => return die(line, "kan ikke åbne /dev/null");
	};
	bg_null = devnull: int;
};

fn bg_end() void = {
	if (bg_null >= 0) close(bg_null: io::file);
	bg_null = -1;
};

let bg_null = -1;    // set while starting a background job
let bg_jobs: []exec::process = [];

// Collects background jobs (&) that have finished, so they don't linger as
// zombies — a zombie still answers "kill -0", so scripts would think it runs.
fn reap_bg() void = {
	let i = 0z;
	for (i < len(bg_jobs)) {
		match (exec::peek(&bg_jobs[i])) {
		case void => i += 1;               // still running
		case => delete(bg_jobs[i]);        // done (or already collected)
		};
	};
};

// &( … ): en kommando i baggrunden, som man kan vente på. Den dør sammen med
// scriptet (også ved Ctrl+C eller et nedbrud), så intet bliver hængende —
// i modsætning til "cmd &", der lever videre efter scriptet.
//   let job = &(curl -sS -o svar.json $url)
//   ... (lav noget andet imens, fx en animation)
//   if not running(job) { let kode = wait(job) }
type job = struct { procs: []exec::process, names: []str, codes: []int };
let jobs: []job = [];
let job_mode = false;
let last_job = 0i64;

fn job_start(raw: str, e: *env, line: int) (value | failed) = {
	const stages = parse_command(strings::toutf8(raw), line)?;
	job_mode = true;
	defer job_mode = false;
	run_bg(stages, e, line)?;
	return last_job;
};

fn job_x(stages: []xstage, line: int) (i64 | failed) = {
	job_mode = true;
	defer job_mode = false;
	run_bg_x(stages, line)?;
	return last_job;
};

fn job_get(name: str, v: value, line: int) (*job | failed) = {
	const n = match (v) {
	case let n: i64 => yield n;
	case => return dief(line, "{}() vil have et job fra &( … )", name);
	};
	if (n < 1 || n > len(jobs): i64) return dief(line, "{}(): der er intet job nummer {}", name, n);
	return &jobs[(n - 1): size];
};

fn exit_code(st: *exec::status) int = match (exec::exit(st)) {
case let c: exec::exited => yield c: int;
case let s: exec::signaled => yield 128 + s: int;
case => yield 1;
};

// pipefail som almindelige kommandoer: den sidste stage, der fejlede, bestemmer
fn job_rc(j: *job) int = {
	let rc = 0;
	for (let c .. j.codes) if (c != 0) rc = c;
	return rc;
};

// running(job): kører jobbet stadig?
fn job_running(v: value, line: int) (bool | failed) = {
	const j = job_get("running", v, line)?;
	let alive = false;
	for (let i = 0z; i < len(j.procs); i += 1) {
		if (j.codes[i] >= 0) continue;
		match (exec::peek(&j.procs[i])) {
		case let st: exec::status => j.codes[i] = exit_code(&st);
		case void => alive = true;
		case => j.codes[i] = 1;
		};
	};
	return alive;
};

// kill(job [, "STOP"]): sender et signal (standard TERM) til jobbets processer.
// STOP sætter på pause, CONT fortsætter, KILL stopper med det samme.
fn job_kill(v: value, signame: str, line: int) (void | failed) = {
	const j = job_get("kill", v, line)?;
	const s: signal::sig = switch (ascii::strupper(strings::trimprefix(signame, "SIG"))!) {
	case "TERM" => yield signal::sig::TERM;
	case "KILL" => yield signal::sig::KILL;
	case "STOP" => yield signal::sig::STOP;
	case "CONT" => yield signal::sig::CONT;
	case "INT" => yield signal::sig::INT;
	case "HUP" => yield signal::sig::HUP;
	case => return dief(line, "kill(): kender ikke signalet '{}' (brug TERM, KILL, STOP, CONT, INT eller HUP)", signame);
	};
	for (let i = 0z; i < len(j.procs); i += 1) {
		if (j.codes[i] >= 0) continue;
		match (exec::sig(j.procs[i], s)) { case => void; };
	};
};

// wait(job): venter, til jobbet er færdigt, og giver exitkoden
fn job_wait(v: value, line: int) (i64 | failed) = {
	const j = job_get("wait", v, line)?;
	for (let i = 0z; i < len(j.procs); i += 1) {
		if (j.codes[i] >= 0) continue;
		match (exec::wait(&j.procs[i])) {
		case let st: exec::status => j.codes[i] = exit_code(&st);
		case => j.codes[i] = 1;
		};
	};
	const rc = job_rc(j);
	define(root, "status", rc: i64);
	return rc: i64;
};

// A pipeline stage with every word already expanded to plain strings.
// The interpreter makes these from the syntax tree; Violet's compiled
// programs build them directly.
type xstage = struct {
	args: []str,
	out: (str | void),
	out_app: bool,
	err: (str | void),
	err_app: bool,
	err_out: bool,
	inp: (str | void),
};

fn opt_word(w: nullable *word, e: *env, line: int) ((str | void) | failed) = {
	match (w) {
	case let w: *word => return one(w, e, line)?;
	case null => return void;
	};
};

// Runs a pipeline. Returns the output when capturing, otherwise the exit code.
fn run_cmd(stages: []stage, e: *env, line: int, cap: bool, try_: bool) ((str | int) | failed) = {
	let xs: []xstage = [];
	defer free(xs);
	for (let st .. stages) {
		let a: []str = [];
		for (let w .. st.args) expand(&w, e, line, &a)?;
		if (len(a) == 0) return die(line, "tom kommando");
		let x = xstage { args = a, out = void, err = void, err_out = st.err_out, inp = opt_word(st.inp, e, line)?, ... };
		match (st.out) {
		case let r: *redir =>
			x.out = one(&r.target, e, line)?;
			x.out_app = r.app;
		case null => void;
		};
		match (st.err) {
		case let r: *redir =>
			x.err = one(&r.target, e, line)?;
			x.err_app = r.app;
		case null => void;
		};
		append(xs, x)!;
	};
	return run_x(xs, e, line, cap, try_);
};

// Runs expanded stages. `e` is only used for "mente du …?" hints.
fn run_x(stages: []xstage, e: nullable *env, line: int, cap: bool, try_: bool) ((str | int) | failed) = {
	reap_bg();
	if (len(stages) == 0 || len(stages[0].args) == 0) return die(line, "tom kommando");
	let argv: [][]str = [];
	defer free(argv);
	for (let st .. stages) {
		if (len(st.args) == 0) return die(line, "tom kommando");
		append(argv, st.args)!;
	};
	const name = argv[0][0];

	// built-ins (alone, not in a pipe)
	if (len(stages) == 1) {
		switch (name) {
		case "echo" =>
			define(root, "status", 0i64);
			const text = strings::concat(strings::join(" ", argv[0][1..]...)!, "\n")!;
			if (cap) return strings::rtrim(text, '\n');
			match (stages[0].out) {
			case let path: str =>
				const f = open_out(path, stages[0].out_app, line)?;
				io_ok(io::writeall(f, strings::toutf8(text)));
				close(f);
			case void =>
				io_ok(io::writeall(os::stdout, strings::toutf8(text)));
			};
			return 0;
		case "cd" =>
			const dir = if (len(argv[0]) > 1) argv[0][1] else home();
			match (os::chdir(dir)) {
			case void => void;
			case => return dief(line, "cd: kan ikke gå til '{}'", dir);
			};
			return 0;
		case "exit" =>
			flush_out();
			let code = 0;
			if (len(argv[0]) > 1) {
				code = int_arg("exit", call("int", [argv[0][1]], line)?, line)?: int;
			};
			prof_rapport();
			os::exit(code);
		case "fail" =>
			const msg = if (len(argv[0]) > 1) strings::join(" ", argv[0][1..]...)! else "fejl";
			flush_out();
			fail_and_exit(msg);
		case => void;
		};
	};

	flush_out();
	let input: (void | []u8) = void;
	let first = 0z;
	if (name == "echo") {
		input = strings::toutf8(strings::concat(strings::join(" ", argv[0][1..]...)!, "\n")!);
		first = 1;
	};

	let procs: []exec::process = [];
	let files: []io::file = [];
	let prev_read: (io::file | void) = void;
	let feed: (io::file | void) = void;
	let capread: (io::file | void) = void;

	for (let i = first; i < len(stages); i += 1) {
		const st = &stages[i];
		const args = argv[i];
		const last = i == len(stages) - 1;
		let sp = spawnspec { path = resolve(args[0]), args = args, fds = [-1, -1, -1], detach = bg_null >= 0,
			diewith = bg_null >= 0 && job_mode };
		if (bg_null >= 0) sp.fds = [bg_null, bg_null, bg_null];
		if (!strings::contains(sp.path, "/")) {
			if (try_) {
				// try: a missing program is just a failure (exit 127, like sh)
				for (let f .. files) close(f);
				define(root, "status", 127i64);
				return if (cap) "" else 127;
			};
			dief(line, "kommandoen '{}' findes ikke — selv med superfart", args[0]): void;
			const names: []str = match (e) {
			case let e: *env => yield visible_names(e);
			case null => yield [];
			};
			sethint(command_hint(args, names));
			return failed;
		};

		// stdin
		match (prev_read) {
		case let r: io::file =>
			sp.fds[0] = r: int;
		case void =>
			match (st.inp) {
			case let path: str =>
				const f = match (os::open(path)) {
				case let f: io::file => yield f;
				case => return dief(line, "kan ikke læse '{}'", path);
				};
				append(files, f)!;
				sp.fds[0] = f: int;
			case void =>
				if (input is []u8 && i == first) {
					const (r, w) = exec::pipe();
					sp.fds[0] = r: int;
					append(files, r)!;
					feed = w;
				};
			};
		};

		// stdout
		let next_read: (io::file | void) = void;
		let my_write: (io::file | void) = void;
		match (st.out) {
		case let path: str =>
			const f = open_out(path, st.out_app, line)?;
			append(files, f)!;
			sp.fds[1] = f: int;
		case void =>
			if (!last || cap) {
				const (r, w) = exec::pipe();
				sp.fds[1] = w: int;
				my_write = w;
				if (last) capread = r else next_read = r;
			};
		};

		// stderr
		match (st.err) {
		case let path: str =>
			const f = open_out(path, st.err_app, line)?;
			append(files, f)!;
			sp.fds[2] = f: int;
		case void => void;
		};
		// 2>&1 / &>: stderr samme sted som stdout (fil, rør eller terminalen)
		if (st.err_out) sp.fds[2] = if (sp.fds[1] >= 0) sp.fds[1] else 1;

		match (spawn(&sp)) {
		case let p: exec::process => append(procs, p)!;
		case let err: spawn_err =>
			return dief(line, "'{}' kan ikke køres: {}", args[0], spawn_strerror(err));
		};
		match (my_write) { case let w: io::file => close(w); case void => void; };
		match (prev_read) { case let r: io::file => close(r); case void => void; };
		prev_read = next_read;
	};

	for (let f .. files) close(f);
	match (feed) {
	case let w: io::file =>
		io_ok(io::writeall(w, input as []u8));
		close(w);
	case void => void;
	};

	let out = "";
	match (capread) {
	case let r: io::file =>
		const data = io::drain(r)!;
		close(r);
		out = strings::rtrim(strings::fromutf8_unsafe(data), '\n');
	case void => void;
	};

	if (bg_null >= 0) {
		// background: don't wait — the jobs live on in their own session
		if (job_mode) {
			// &( … ): husk processerne, så wait() og running() kan spørge til dem
			let names: []str = [];
			for (let i = 0z; i < len(procs); i += 1) append(names, argv[i + first][0])!;
			let codes: []int = [];
			for (let i = 0z; i < len(procs); i += 1) append(codes, -1)!;
			append(jobs, job { procs = procs, names = names, codes = codes })!;
			last_job = len(jobs): i64;
			define(root, "status", 0i64);
			return 0;
		};
		append(bg_jobs, procs...)!;
		define(root, "status", 0i64);
		return 0;
	};

	// pipefail: the rightmost failing stage decides
	let rc = 0, bad = "";
	for (let i = 0z; i < len(procs); i += 1) {
		let st = exec::wait(&procs[i])!;
		const code = match (exec::exit(&st)) {
		case let c: exec::exited => yield c: int;
		case let s: exec::signaled => yield 128 + s: int;
		case => yield 1;
		};
		if (code != 0) {
			rc = code;
			bad = argv[i + first][0];
		};
	};
	define(root, "status", rc: i64);
	if (rc != 0 && !try_) return dief(line, "'{}' snublede i svinget (exit {})", bad, rc);
	return if (cap) out else rc;
};
