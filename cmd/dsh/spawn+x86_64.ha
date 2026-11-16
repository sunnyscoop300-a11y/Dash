// Starting programs on x86_64: vfork + execve, exactly like dash.
// The shell's memory is never copied, so it is as fast as sh.
// (Other CPUs use posix_spawn from libc, see spawn+aarch64.ha.)
use errors;
use os::exec;
use rt;
use types::c;

@symbol("dsh_vfork_exec") fn vfork_exec(
	path: *const c::char,
	argv: *[*]nullable *const c::char,
	envp: *[*]nullable *u8,
	fds: *[3]int,
) i64;

// One child: the program, its arguments, and where fd 0/1/2 come from
// (-1 = inherit from dsh).
type spawnspec = struct {
	path: str,
	args: []str,
	fds: [3]int,
};

type spawn_err = !int;    // errno

fn spawn(sp: *spawnspec) (exec::process | spawn_err) = {
	// everything the child needs is prepared here, before vfork
	const cpath = c::fromstr(sp.path)!;
	defer free(cpath);
	let argv: []nullable *const c::char = [];
	defer {
		for (let a .. argv) free(a);
		free(argv);
	};
	for (let a .. sp.args) append(argv, c::fromstr(a)!)!;
	append(argv, null)!;

	const r = vfork_exec(cpath, argv: *[*]nullable *const c::char, rt::envp, &sp.fds);
	if (r < 0) return (-r): int: spawn_err;
	return r: int: exec::process;
};

fn spawn_strerror(e: spawn_err) const str = errors::strerror(errors::errno(e: rt::errno));
