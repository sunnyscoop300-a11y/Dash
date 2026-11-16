// Values, errors and the variable environment.
use fmt;
use io;
use math;
use memio;
use strconv;
use strings;

type nilv = void;
type list = struct { items: []value };
type mapv = struct { keys: []value, vals: []value };
type func = struct {
	name: str,
	params: []str,
	body: []stmt,
	closure: *env,
};
type value = (i64 | f64 | str | bool | nilv | *list | *mapv | *func);

// An error that stops the script. The message and line are kept globally,
// so every function can simply return `failed`.
type failed = !void;

let err_msg: str = "";
let err_line: int = 0;

fn die(line: int, msg: str) failed = {
	err_msg = msg;
	err_line = line;
	err_hint = "";
	return failed;
};

fn dief(line: int, f: str, args: fmt::field...) failed =
	die(line, fmt::asprintf(f, args...)!);

fn typename(v: value) str = match (v) {
case i64 => yield "int";
case f64 => yield "float";
case str => yield "str";
case bool => yield "bool";
case nilv => yield "nil";
case *list => yield "list";
case *mapv => yield "map";
case *func => yield "fn";
};

fn truthy(v: value) bool = match (v) {
case let i: i64 => yield i != 0;
case let f: f64 => yield f != 0.0;
case let s: str => yield len(s) > 0;
case let b: bool => yield b;
case nilv => yield false;
case let l: *list => yield len(l.items) > 0;
case let m: *mapv => yield len(m.keys) > 0;
case *func => yield true;
};

fn ftostr(f: f64) str = {
	if (f == math::floorf64(f) && math::absf64(f) < 1000000000000000.0) {
		return strings::dup(strconv::i64tos(f: i64))!;
	};
	return strings::dup(strconv::f64tos(f))!;
};

fn tostr(v: value) str = tostr_in(v, false);

fn tostr_in(v: value, nested: bool) str = {
	match (v) {
	case let i: i64 => return strings::dup(strconv::i64tos(i))!;
	case let f: f64 => return ftostr(f);
	case let s: str =>
		if (nested) return strings::concat("\"", s, "\"")!;
		return s;
	case let b: bool => return if (b) "true" else "false";
	case nilv => return "nil";
	case let l: *list =>
		let m = memio::dynamic();
		memio::concat(&m, "[")!;
		for (let i = 0z; i < len(l.items); i += 1) {
			if (i > 0) memio::concat(&m, ", ")!;
			memio::concat(&m, tostr_in(l.items[i], true))!;
		};
		memio::concat(&m, "]")!;
		return memio::string(&m)!;
	case let mp: *mapv =>
		let m = memio::dynamic();
		memio::concat(&m, "{")!;
		for (let i = 0z; i < len(mp.keys); i += 1) {
			if (i > 0) memio::concat(&m, ", ")!;
			memio::concat(&m, tostr_in(mp.keys[i], true), ": ",
				tostr_in(mp.vals[i], true))!;
		};
		memio::concat(&m, "}")!;
		return memio::string(&m)!;
	case let f: *func => return strings::concat("<fn ", f.name, ">")!;
	};
};

// Numbers as f64, for mixing int and float.
fn num(v: value) (f64 | void) = match (v) {
case let i: i64 => yield i: f64;
case let f: f64 => yield f;
case => yield;
};

fn equal(a: value, b: value) bool = {
	if ((a is i64 || a is f64) && (b is i64 || b is f64)) {
		return num(a) as f64 == num(b) as f64;
	};
	match (a) {
	case let x: str =>
		match (b) { case let y: str => return x == y; case => return false; };
	case let x: bool =>
		match (b) { case let y: bool => return x == y; case => return false; };
	case nilv =>
		return b is nilv;
	case let x: *list =>
		const y = match (b) { case let y: *list => yield y; case => return false; };
		if (len(x.items) != len(y.items)) return false;
		for (let i = 0z; i < len(x.items); i += 1) {
			if (!equal(x.items[i], y.items[i])) return false;
		};
		return true;
	case let x: *mapv =>
		match (b) { case let y: *mapv => return x == y; case => return false; };
	case let x: *func =>
		match (b) { case let y: *func => return x == y; case => return false; };
	case => return false;
	};
};

fn newlist(items: []value) *list = alloc(list { items = items })!;

fn map_find(m: *mapv, k: value) (size | void) = {
	for (let i = 0z; i < len(m.keys); i += 1) {
		if (equal(m.keys[i], k)) return i;
	};
};

fn map_set(m: *mapv, k: value, v: value) void = {
	match (map_find(m, k)) {
	case let i: size => m.vals[i] = v;
	case void =>
		append(m.keys, k)!;
		append(m.vals, v)!;
	};
};

// --- environment ---

type env = struct {
	names: []str,
	vals: []value,
	parent: nullable *env,
	captured: bool,        // a fn was defined here: keep it alive
};

fn newenv(parent: nullable *env) *env = alloc(env { parent = parent, ... })!;

fn env_find(e: *env, name: str) (*value | void) = {
	let cur: nullable *env = e;
	for (true) {
		const c = match (cur) {
		case null => return;
		case let c: *env => yield c;
		};
		for (let i = 0z; i < len(c.names); i += 1) {
			if (c.names[i] == name) return &c.vals[i];
		};
		cur = c.parent;
	};
};

fn define(e: *env, name: str, v: value) void = {
	for (let i = 0z; i < len(e.names); i += 1) {
		if (e.names[i] == name) {
			e.vals[i] = v;
			return;
		};
	};
	append(e.names, name)!;
	append(e.vals, v)!;
};

fn freeenv(e: *env) void = {
	if (e.captured) return;
	free(e.names);
	free(e.vals);
	free(e);
};

fn io_ok(r: (size | io::error)) void = {
	match (r) { case => void; };
};

fn close(f: io::file) void = {
	match (io::close(f)) { case => void; };
};
