// Starting programs without libc (Violet's Android builds, --arch android):
// a plain fork + execve with raw Linux system calls. Android has no glibc,
// and its own libc (Bionic) is not linked in, so posix_spawn isn't there.
use errors;
use io;
use os;
use os::exec;
use rt;
use strings;
use types::c;

type spawnspec = struct {
	path: str,
	args: []str,
	fds: [3]int,
	detach: bool,    // background job: own session (setsid)
};

type spawn_err = !int;    // errno

// Android (Termux): programs in the app's own folders may not be started
// directly (W^X) — only through Android's loader, /system/bin/linker64.
// Termux does that with termux-exec, a libc trick our libc-free binaries
// don't have, so we do the same here: run "linker64 program args...", and
// for #! scripts run the interpreter (with /usr/bin → $PREFIX/bin).
def LINKER64: str = "/system/bin/linker64";

fn on_android() bool = os::exists(LINKER64);

fn app_file(path: str) bool = strings::hasprefix(path, "/data/");

// The interpreter of a #! script: ("/path/to/interp", optional argument).
fn shebang(path: str) ((str, str) | void) = {
	const f = match (os::open(path)) {
	case let f: io::file => yield f;
	case => return;
	};
	defer io::close(f)!;
	let buf: [256]u8 = [0...];
	const n = match (io::read(f, buf)) {
	case let n: size => yield n;
	case => return;
	};
	if (n < 3 || buf[0] != '#' || buf[1] != '!') return;
	let end = 2z;
	for (end < n && buf[end] != '\n') end += 1;
	const line = strings::trim(strings::fromutf8_unsafe(buf[2..end]));
	const (interp, arg) = strings::cut(line, " ");
	return (strings::dup(interp)!, strings::dup(strings::trim(arg))!);
};

// /usr/bin/env, /bin/sh … don't exist on Android: use Termux' own.
fn termux_path(p: str) str = {
	if (os::exists(p)) return p;
	const prefix = os::tryenv("PREFIX", "/data/data/com.termux/files/usr");
	if (strings::hasprefix(p, "/usr/")) return strings::concat(prefix, strings::sub(p, 4, strings::end))!;
	if (strings::hasprefix(p, "/bin/")) return strings::concat(prefix, p)!;
	return p;
};

// What to actually execve on Android: (path, argv).
fn android_cmd(path: str, args: []str) (str, []str) = {
	let out: []str = [];
	match (shebang(path)) {
	case let s: (str, str) =>
		const interp = termux_path(s.0);
		append(out, interp)!;
		if (len(s.1) > 0) append(out, s.1)!;
		append(out, path)!;
		if (len(args) > 1) append(out, args[1..]...)!;
		if (!app_file(interp)) return (interp, out);
		let v: []str = [];
		append(v, LINKER64)!;
		append(v, out...)!;
		free(out);
		return (LINKER64, v);
	case void =>
		append(out, LINKER64)!;
		append(out, path)!;
		if (len(args) > 1) append(out, args[1..]...)!;
		return (LINKER64, out);
	};
};

fn spawn(sp: *spawnspec) (exec::process | spawn_err) = {
	let path = sp.path;
	let args = sp.args;
	if (app_file(path) && on_android()) {
		const (p, a) = android_cmd(path, args);
		path = p;
		args = a;
	};
	// everything the child needs is prepared before the fork
	const cpath = c::fromstr(path)!;
	defer free(cpath);
	let argv: []nullable *const c::char = [];
	defer {
		for (let a .. argv) free(a: *c::char);
		free(argv);
	};
	for (let a .. args) append(argv, c::fromstr(a)!)!;
	append(argv, null)!;

	match (rt::fork()) {
	case let e: rt::errno => return e: int: spawn_err;
	case void =>
		// the child: wire up stdin/stdout/stderr and become the program
		for (let i = 0; i < 3; i += 1) {
			if (sp.fds[i] >= 0 && sp.fds[i] != i) {
				match (rt::dup2(sp.fds[i], i)) { case => void; };
			};
		};
		if (sp.detach) match (rt::setsid()) { case => void; };
		// execve kommer kun tilbage, hvis programmet ikke kunne startes
		let _ = rt::execve(cpath: *const u8, argv: *[*]nullable *const u8,
			rt::envp: *[*]nullable *const u8);
		rt::exit(127);
	case let pid: rt::pid_t => return pid: exec::process;
	};
};

fn spawn_strerror(e: spawn_err) const str = errors::strerror(errors::errno(e: rt::errno));
