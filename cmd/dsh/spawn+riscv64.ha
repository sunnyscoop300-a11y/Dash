// Starting programs with posix_spawn (from libc). glibc implements it with
// clone(CLONE_VM | CLONE_VFORK) — like dash's vfork — so the shell's memory
// is never copied. That is what makes running commands as fast as sh.
use errors;
use io;
use os::exec;
use rt;
use types::c;

// posix_spawn_file_actions_t is 80 bytes on both glibc and musl (x86_64,
// aarch64, riscv64).
type fileactions = struct { _pad: [10]u64 };

@symbol("posix_spawn") fn c_posix_spawn(
	pid: *int,
	path: *const c::char,
	acts: *fileactions,
	attr: nullable *spawnattr,
	argv: *[*]nullable *const c::char,
	envp: *[*]nullable *u8,
) int;
@symbol("posix_spawn_file_actions_init") fn c_fa_init(a: *fileactions) int;
@symbol("posix_spawn_file_actions_destroy") fn c_fa_destroy(a: *fileactions) int;
@symbol("posix_spawn_file_actions_adddup2") fn c_fa_dup2(a: *fileactions, fd: int, newfd: int) int;

// posix_spawnattr_t: 336 bytes on glibc, less on musl — room to spare.
type spawnattr = struct { _pad: [64]u64 };
@symbol("posix_spawnattr_init") fn c_attr_init(a: *spawnattr) int;
@symbol("posix_spawnattr_destroy") fn c_attr_destroy(a: *spawnattr) int;
@symbol("posix_spawnattr_setflags") fn c_attr_setflags(a: *spawnattr, flags: i16) int;
def POSIX_SPAWN_SETSID: i16 = 0x80;

// One child: the program, its arguments, and where fd 0/1/2 come from
// (-1 = inherit from dsh).
type spawnspec = struct {
	path: str,
	args: []str,
	fds: [3]int,
	detach: bool,    // background job: own session (setsid)
};

type spawn_err = !int;    // errno

fn spawn(sp: *spawnspec) (exec::process | spawn_err) = {
	let acts = fileactions { ... };
	c_fa_init(&acts);
	defer c_fa_destroy(&acts);
	for (let i = 0; i < 3; i += 1) {
		if (sp.fds[i] >= 0) c_fa_dup2(&acts, sp.fds[i], i);
	};

	const cpath = c::fromstr(sp.path)!;
	defer free(cpath);
	let argv: []nullable *const c::char = [];
	defer {
		for (let a .. argv) free(a: *c::char);
		free(argv);
	};
	for (let a .. sp.args) append(argv, c::fromstr(a)!)!;
	append(argv, null)!;

	let attr = spawnattr { ... };
	c_attr_init(&attr);
	defer c_attr_destroy(&attr);
	if (sp.detach) c_attr_setflags(&attr, POSIX_SPAWN_SETSID);
	let pid = 0;
	const r = c_posix_spawn(&pid, cpath, &acts, &attr,
		argv: *[*]nullable *const c::char, rt::envp);
	if (r != 0) return r: spawn_err;
	return pid: exec::process;
};

fn spawn_strerror(e: spawn_err) const str = errors::strerror(errors::errno(e: rt::errno));
