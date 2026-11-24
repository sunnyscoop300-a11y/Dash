// Bits og bytes til Dash: heltalsoperatorerne (& | ^ << >> ~ //) og
// byte-buffere — det, en emulator (eller et filformat) har brug for.
//
//   let ram = bytes(2 * 1024 * 1024)       # 2 MB nuller → buffer nr.
//   wr32(ram, 0x100, 0xdeadbeef)           # little-endian, som PS1/x86
//   print(rd16(ram, 0x100))                # 48879 (0xbeef)
//   let bios = read_bytes("scph1001.bin")  # hele filen som buffer
//
// En buffer er et nummer (ligesom image() og sound()), så Violet kan holde
// den i et rigtigt i64, og rd32/wr32 bliver direkte maskinkode.
use fmt;
use fs;
use io;
use os;
use strings;

let mem_bufs: [][]u8 = [];
let mem_live: []bool = [];

fn is_bitop(op: str) bool = op == "&" || op == "|" || op == "^" || op == "<<"
	|| op == ">>" || op == "//";

fn bitop(op: str, x: i64, y: i64, line: int) (value | failed) = {
	switch (op) {
	case "&" => return x & y;
	case "|" => return x | y;
	case "^" => return x ^ y;
	case "<<" => return x << (y & 63);
	case ">>" => return x >> (y & 63);
	case "//" => return idiv(x, y, line)?;
	case => abort();
	};
};

// Heltalsdivision: decimalerne skæres væk (7 // 2 = 3, -7 // 2 = -3).
fn idiv(x: i64, y: i64, line: int) (i64 | failed) = {
	if (y == 0) return die(line, "division med nul — selv Dash kan ikke løbe uendeligt");
	if (y == -1) return -x;    // undgår SIGFPE ved det mindste i64
	return x / y;
};

fn bnot_v(a: value, line: int) (value | failed) = match (a) {
case let i: i64 => yield ~i;
case => yield dief(line, "kan ikke bruge '~' på en {}", typename(a));
};

// --- byte-buffere ---

fn mem_new(b: []u8) i64 = {
	// en plads, som free_bytes() har tømt, genbruges
	for (let k = 0z; k < len(mem_bufs); k += 1) {
		if (!mem_live[k]) {
			mem_bufs[k] = b;
			mem_live[k] = true;
			return k: i64;
		};
	};
	append(mem_bufs, b)!;
	append(mem_live, true)!;
	return (len(mem_bufs) - 1): i64;
};

fn mem_get(h: i64, name: str, line: int) ([]u8 | failed) = {
	if (h < 0 || h: u64 >= len(mem_bufs): u64 || !mem_live[h: size]) {
		return dief(line, "{}(): ingen buffer nr. {}", name, h);
	};
	return mem_bufs[h: size];
};

fn mem_oob(name: str, off: i64, n: i64, blen: size, line: int) failed =
	dief(line, "{}(): adresse 0x{:x} (+{}) er udenfor bufferen (0x{:x} bytes)",
		name, off, n, blen);

fn mem_bytes(n: i64, line: int) (i64 | failed) = {
	if (n < 0 || n > 1 << 32) return dief(line, "bytes(): {} er ikke en størrelse", n);
	if (n == 0) return mem_new([]);
	return mem_new(alloc([0u8...], n: size)!);
};

// Den hurtige vej: bufferen findes, og adressen er inden for. En frigjort
// buffer har længden 0, så den falder altid igennem til den langsomme vej,
// der giver den rigtige fejlbesked.
fn mem_fast(h: i64, off: i64, n: u64) ([]u8 | void) = {
	if (h: u64 < len(mem_bufs): u64) {
		const b = mem_bufs[h: size];
		if (off: u64 + n <= len(b): u64 && off >= 0) return b;
	};
};

fn mem_rd8(h: i64, off: i64, line: int) (i64 | failed) = {
	match (mem_fast(h, off, 1)) {
	case let b: []u8 => return b[off: size]: i64;
	case void => void;
	};
	const b = mem_get(h, "rd8", line)?;
	if (off < 0 || off: u64 >= len(b): u64) return mem_oob("rd8", off, 1, len(b), line);
	return b[off: size]: i64;
};

fn mem_rd16(h: i64, off: i64, line: int) (i64 | failed) = {
	match (mem_fast(h, off, 2)) {
	case let b: []u8 =>
		const o = off: size;
		return (b[o]: i64) | (b[o + 1]: i64) << 8;
	case void => void;
	};
	const b = mem_get(h, "rd16", line)?;
	if (off < 0 || off: u64 + 2 > len(b): u64) return mem_oob("rd16", off, 2, len(b), line);
	const o = off: size;
	return (b[o]: i64) | (b[o + 1]: i64) << 8;
};

fn mem_rd32(h: i64, off: i64, line: int) (i64 | failed) = {
	match (mem_fast(h, off, 4)) {
	case let b: []u8 =>
		const o = off: size;
		return (b[o]: i64) | (b[o + 1]: i64) << 8 | (b[o + 2]: i64) << 16 | (b[o + 3]: i64) << 24;
	case void => void;
	};
	const b = mem_get(h, "rd32", line)?;
	if (off < 0 || off: u64 + 4 > len(b): u64) return mem_oob("rd32", off, 4, len(b), line);
	const o = off: size;
	return (b[o]: i64) | (b[o + 1]: i64) << 8 | (b[o + 2]: i64) << 16 | (b[o + 3]: i64) << 24;
};

fn mem_wr8(h: i64, off: i64, v: i64, line: int) (void | failed) = {
	match (mem_fast(h, off, 1)) {
	case let b: []u8 =>
		b[off: size] = v: u8;
		return;
	case void => void;
	};
	const b = mem_get(h, "wr8", line)?;
	if (off < 0 || off: u64 >= len(b): u64) return mem_oob("wr8", off, 1, len(b), line);
	b[off: size] = v: u8;
};

fn mem_wr16(h: i64, off: i64, v: i64, line: int) (void | failed) = {
	match (mem_fast(h, off, 2)) {
	case let b: []u8 =>
		const o = off: size;
		b[o] = v: u8;
		b[o + 1] = (v >> 8): u8;
		return;
	case void => void;
	};
	const b = mem_get(h, "wr16", line)?;
	if (off < 0 || off: u64 + 2 > len(b): u64) return mem_oob("wr16", off, 2, len(b), line);
	const o = off: size;
	b[o] = v: u8;
	b[o + 1] = (v >> 8): u8;
};

fn mem_wr32(h: i64, off: i64, v: i64, line: int) (void | failed) = {
	match (mem_fast(h, off, 4)) {
	case let b: []u8 =>
		const o = off: size;
		b[o] = v: u8;
		b[o + 1] = (v >> 8): u8;
		b[o + 2] = (v >> 16): u8;
		b[o + 3] = (v >> 24): u8;
		return;
	case void => void;
	};
	const b = mem_get(h, "wr32", line)?;
	if (off < 0 || off: u64 + 4 > len(b): u64) return mem_oob("wr32", off, 4, len(b), line);
	const o = off: size;
	b[o] = v: u8;
	b[o + 1] = (v >> 8): u8;
	b[o + 2] = (v >> 16): u8;
	b[o + 3] = (v >> 24): u8;
};

fn mem_len(h: i64, line: int) (i64 | failed) = len(mem_get(h, "bytes_len", line)?): i64;

// copy_bytes(til, til_adr, fra, fra_adr, n) — som memmove (DMA, sektorer …)
fn mem_copy(dst: i64, doff: i64, src: i64, soff: i64, n: i64, line: int) (void | failed) = {
	const d = mem_get(dst, "copy_bytes", line)?;
	const s = mem_get(src, "copy_bytes", line)?;
	if (n < 0) return dief(line, "copy_bytes(): {} er ikke et antal bytes", n);
	if (n == 0) return;
	if (doff < 0 || doff: u64 + n: u64 > len(d): u64) return mem_oob("copy_bytes", doff, n, len(d), line);
	if (soff < 0 || soff: u64 + n: u64 > len(s): u64) return mem_oob("copy_bytes", soff, n, len(s), line);
	d[doff: size..(doff + n): size] = s[soff: size..(soff + n): size];
};

// fill_bytes(buf, adr, n, værdi)
fn mem_fill(h: i64, off: i64, n: i64, v: i64, line: int) (void | failed) = {
	const b = mem_get(h, "fill_bytes", line)?;
	if (n < 0 || off < 0 || off: u64 + n: u64 > len(b): u64) return mem_oob("fill_bytes", off, n, len(b), line);
	for (let i = off: size; i < (off + n): size; i += 1) b[i] = v: u8;
};

fn mem_free(h: i64, line: int) (void | failed) = {
	mem_get(h, "free_bytes", line)?;
	free(mem_bufs[h: size]);
	mem_bufs[h: size] = [];
	mem_live[h: size] = false;
};

// read_bytes(sti) → hele filen; read_bytes(sti, adr, n) → n bytes fra adr.
fn mem_read_file(path: str, off: i64, n: i64, line: int) (i64 | failed) = {
	const p = expanduser(path);
	const f = match (os::open(p)) {
	case let f: io::file => yield f;
	case let e: fs::error =>
		return dief(line, "read_bytes(): kan ikke åbne '{}': {}", p, fs::strerror(e));
	};
	defer close(f);
	if (n < 0) {
		match (io::drain(f)) {
		case let b: []u8 => return mem_new(b);
		case let e: io::error =>
			return dief(line, "read_bytes(): kan ikke læse '{}': {}", p, io::strerror(e));
		};
	};
	let b: []u8 = alloc([0u8...], n: size)!;
	const got = read_at(f, b, off, p, "read_bytes", line)?;
	b = b[..got];
	return mem_new(b);
};

// read_into(buf, buf_adr, sti, fil_adr, n) → antal bytes læst. Til at læse
// én CD-sektor ad gangen uden at lave en ny buffer hver gang.
fn mem_read_into(h: i64, boff: i64, path: str, foff: i64, n: i64, line: int) (i64 | failed) = {
	const b = mem_get(h, "read_into", line)?;
	if (n < 0 || boff < 0 || boff: u64 + n: u64 > len(b): u64) return mem_oob("read_into", boff, n, len(b), line);
	const p = expanduser(path);
	const f = match (os::open(p)) {
	case let f: io::file => yield f;
	case let e: fs::error =>
		return dief(line, "read_into(): kan ikke åbne '{}': {}", p, fs::strerror(e));
	};
	defer close(f);
	return read_at(f, b[boff: size..(boff + n): size], foff, p, "read_into", line)?: i64;
};

fn read_at(f: io::file, b: []u8, off: i64, p: str, name: str, line: int) (size | failed) = {
	if (off > 0) {
		match (io::seek(f, off: io::off, io::whence::SET)) {
		case io::off => void;
		case let e: io::error =>
			return dief(line, "{}(): kan ikke gå til 0x{:x} i '{}': {}", name, off, p, io::strerror(e));
		};
	};
	let got = 0z;
	for (got < len(b)) {
		match (io::read(f, b[got..])) {
		case let k: size => got += k;
		case io::EOF => break;
		case let e: io::error =>
			return dief(line, "{}(): kan ikke læse '{}': {}", name, p, io::strerror(e));
		};
	};
	return got;
};

// write_bytes(sti, buf [, adr, n]) — gem en buffer (hukommelseskort, savestate …)
fn mem_write_file(path: str, h: i64, off: i64, n: i64, line: int) (void | failed) = {
	const b = mem_get(h, "write_bytes", line)?;
	const n = if (n < 0) len(b): i64 - off else n;
	if (off < 0 || n < 0 || off: u64 + n: u64 > len(b): u64) return mem_oob("write_bytes", off, n, len(b), line);
	const p = expanduser(path);
	const f = match (os::create(p, 0o644, fs::flag::WRONLY | fs::flag::TRUNC)) {
	case let f: io::file => yield f;
	case let e: fs::error =>
		return dief(line, "write_bytes(): kan ikke skrive '{}': {}", p, fs::strerror(e));
	};
	defer close(f);
	match (io::writeall(f, b[off: size..(off + n): size])) {
	case size => void;
	case let e: io::error =>
		return dief(line, "write_bytes(): kan ikke skrive '{}': {}", p, io::strerror(e));
	};
};

// u32/s32/s16/s8: et tal klippet til 32/16/8 bit (med eller uden fortegn)
fn as_u32(x: i64) i64 = x & 0xffff_ffff;
fn as_s32(x: i64) i64 = x: i32: i64;
fn as_s16(x: i64) i64 = x: i16: i64;
fn as_s8(x: i64) i64 = x: i8: i64;

// Kaldes fra call(). void = ikke en af vores.
fn mem_call(name: str, args: []value, line: int) (value | failed | void) = {
	switch (name) {
	case "bytes" =>
		need(name, args, 1, line)?;
		return mem_bytes(int_arg(name, args[0], line)?, line)?;
	case "rd8", "rd16", "rd32" =>
		need(name, args, 2, line)?;
		const h = int_arg(name, args[0], line)?, a = int_arg(name, args[1], line)?;
		switch (name) {
		case "rd8" => return mem_rd8(h, a, line)?;
		case "rd16" => return mem_rd16(h, a, line)?;
		case => return mem_rd32(h, a, line)?;
		};
	case "wr8", "wr16", "wr32" =>
		need(name, args, 3, line)?;
		const h = int_arg(name, args[0], line)?, a = int_arg(name, args[1], line)?;
		const v = int_arg(name, args[2], line)?;
		switch (name) {
		case "wr8" => mem_wr8(h, a, v, line)?;
		case "wr16" => mem_wr16(h, a, v, line)?;
		case => mem_wr32(h, a, v, line)?;
		};
		return nilv: value;
	case "bytes_len" =>
		need(name, args, 1, line)?;
		return mem_len(int_arg(name, args[0], line)?, line)?;
	case "copy_bytes" =>
		need(name, args, 5, line)?;
		mem_copy(int_arg(name, args[0], line)?, int_arg(name, args[1], line)?,
			int_arg(name, args[2], line)?, int_arg(name, args[3], line)?,
			int_arg(name, args[4], line)?, line)?;
		return nilv: value;
	case "fill_bytes" =>
		need(name, args, 4, line)?;
		mem_fill(int_arg(name, args[0], line)?, int_arg(name, args[1], line)?,
			int_arg(name, args[2], line)?, int_arg(name, args[3], line)?, line)?;
		return nilv: value;
	case "free_bytes" =>
		need(name, args, 1, line)?;
		mem_free(int_arg(name, args[0], line)?, line)?;
		return nilv: value;
	case "read_bytes" =>
		if (len(args) != 1 && len(args) != 3) {
			return die(line, "read_bytes() vil have en sti, eller sti, adresse og antal");
		};
		const p = str_arg(name, args[0], line)?;
		if (len(args) == 1) return mem_read_file(p, 0, -1, line)?;
		return mem_read_file(p, int_arg(name, args[1], line)?, int_arg(name, args[2], line)?, line)?;
	case "read_into" =>
		need(name, args, 5, line)?;
		return mem_read_into(int_arg(name, args[0], line)?, int_arg(name, args[1], line)?,
			str_arg(name, args[2], line)?, int_arg(name, args[3], line)?,
			int_arg(name, args[4], line)?, line)?;
	case "write_bytes" =>
		if (len(args) != 2 && len(args) != 4) {
			return die(line, "write_bytes() vil have sti og buffer [, adresse, antal]");
		};
		const p = str_arg(name, args[0], line)?;
		const h = int_arg(name, args[1], line)?;
		if (len(args) == 2) mem_write_file(p, h, 0, -1, line)?
		else mem_write_file(p, h, int_arg(name, args[2], line)?, int_arg(name, args[3], line)?, line)?;
		return nilv: value;
	case "u32", "s32", "s16", "s8" =>
		need(name, args, 1, line)?;
		const x = match (args[0]) {
		case let i: i64 => yield i;
		case => return dief(line, "{}() vil have et heltal, fik {}", name, typename(args[0]));
		};
		switch (name) {
		case "u32" => return as_u32(x);
		case "s32" => return as_s32(x);
		case "s16" => return as_s16(x);
		case => return as_s8(x);
		};
	case => return;
	};
};
