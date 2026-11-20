// Starting programs without libc (Violet builds without libc):
// a plain fork + execve with raw Linux system calls. Android has no glibc,
// and its own libc (Bionic) is not linked in, so posix_spawn isn't there.
use errors;
use os::exec;
use rt;
use types::c;

type spawnspec = struct {
	path: str,
	args: []str,
	fds: [3]int,
	detach: bool,    // background job: own session (setsid)
	diewith: bool,   // &( )-job: dør, når dsh dør (PR_SET_PDEATHSIG)
};

type spawn_err = !int;    // errno

fn spawn(sp: *spawnspec) (exec::process | spawn_err) = {
	// everything the child needs is prepared before the fork
	const cpath = c::fromstr(sp.path)!;
	defer free(cpath);
	let argv: []nullable *const c::char = [];
	defer {
		for (let a .. argv) free(a: *c::char);
		free(argv);
	};
	for (let a .. sp.args) append(argv, c::fromstr(a)!)!;
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
		if (sp.diewith) match (rt::prctl(rt::PR_SET_PDEATHSIG, 9, 0, 0, 0)) { case => void; };
		// execve kommer kun tilbage, hvis programmet ikke kunne startes
		let _ = rt::execve(cpath: *const u8, argv: *[*]nullable *const u8,
			rt::envp: *[*]nullable *const u8);
		rt::exit(127);
	case let pid: rt::pid_t => return pid: exec::process;
	};
};

fn spawn_strerror(e: spawn_err) const str = errors::strerror(errors::errno(e: rt::errno));
