// Running commands: pipes, redirects, built-ins and strict errors.
use bufio;
use fs;
use io;
use os;
use os::exec;
use strings;
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

fn capture(raw: str, e: *env, line: int) (value | failed) = {
	const stages = parse_command(strings::toutf8(raw), line)?;
	match (run_cmd(stages, e, line, true, false)?) {
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
	const devnull = match (os::open("/dev/null", fs::flag::RDWR)) {
	case let f: io::file => yield f;
	case => return die(line, "kan ikke åbne /dev/null");
	};
	bg_null = devnull: int;
	defer {
		bg_null = -1;
		close(devnull);
	};
	run_cmd(stages, e, line, false, true)?;
};

let bg_null = -1;    // set while starting a background job

// Runs a pipeline. Returns the output when capturing, otherwise the exit code.
fn run_cmd(stages: []stage, e: *env, line: int, cap: bool, try_: bool) ((str | int) | failed) = {
	let argv: [][]str = [];
	for (let st .. stages) {
		let a: []str = [];
		for (let w .. st.args) expand(&w, e, line, &a)?;
		if (len(a) == 0) return die(line, "tom kommando");
		append(argv, a)!;
	};
	const name = argv[0][0];

	// built-ins (alone, not in a pipe)
	if (len(stages) == 1) {
		switch (name) {
		case "echo" =>
			const text = strings::concat(strings::join(" ", argv[0][1..]...)!, "\n")!;
			if (cap) return strings::rtrim(text, '\n');
			match (stages[0].out) {
			case let r: *redir =>
				const f = open_out(one(&r.target, e, line)?, r.app, line)?;
				io_ok(io::writeall(f, strings::toutf8(text)));
				close(f);
			case null =>
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
		let sp = spawnspec { path = resolve(args[0]), args = args, fds = [-1, -1, -1], detach = bg_null >= 0 };
		if (bg_null >= 0) sp.fds = [bg_null, bg_null, bg_null];
		if (!strings::contains(sp.path, "/")) {
			dief(line, "kommandoen '{}' findes ikke — selv med superfart", args[0]): void;
			sethint(command_hint(args, visible_names(e)));
			return failed;
		};

		// stdin
		match (prev_read) {
		case let r: io::file =>
			sp.fds[0] = r: int;
		case void =>
			match (st.inp) {
			case let w: *word =>
				const path = one(w, e, line)?;
				const f = match (os::open(path)) {
				case let f: io::file => yield f;
				case => return dief(line, "kan ikke læse '{}'", path);
				};
				append(files, f)!;
				sp.fds[0] = f: int;
			case null =>
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
		case let r: *redir =>
			const f = open_out(one(&r.target, e, line)?, r.app, line)?;
			append(files, f)!;
			sp.fds[1] = f: int;
		case null =>
			if (!last || cap) {
				const (r, w) = exec::pipe();
				sp.fds[1] = w: int;
				my_write = w;
				if (last) capread = r else next_read = r;
			};
		};

		// stderr
		match (st.err) {
		case let r: *redir =>
			const f = open_out(one(&r.target, e, line)?, r.app, line)?;
			append(files, f)!;
			sp.fds[2] = f: int;
		case null => void;
		};

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
