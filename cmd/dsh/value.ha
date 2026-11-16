// Values, errors and the variable environment.
use fmt;
use io;
use memio;
use strconv;
use strings;

type nilv = void;
type list = struct { items: []value };
type value = (i64 | str | bool | nilv | *list);

// An error that stops the script. The message and line are kept globally,
// so every function can simply return `failed`.
type failed = !void;

let err_msg: str = "";
let err_line: int = 0;

fn die(line: int, msg: str) failed = {
	err_msg = msg;
	err_line = line;
	return failed;
};

fn dief(line: int, f: str, args: fmt::field...) failed =
	die(line, fmt::asprintf(f, args...)!);

fn typename(v: value) str = match (v) {
case i64 => yield "int";
case str => yield "str";
case bool => yield "bool";
case nilv => yield "nil";
case *list => yield "list";
};

fn truthy(v: value) bool = match (v) {
case let i: i64 => yield i != 0;
case let s: str => yield len(s) > 0;
case let b: bool => yield b;
case nilv => yield false;
case let l: *list => yield len(l.items) > 0;
};

fn tostr(v: value) str = tostr_in(v, false);

fn tostr_in(v: value, nested: bool) str = {
	match (v) {
	case let i: i64 => return strings::dup(strconv::i64tos(i))!;
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
	};
};

fn equal(a: value, b: value) bool = {
	match (a) {
	case let x: i64 =>
		match (b) { case let y: i64 => return x == y; case => return false; };
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
	};
};

fn newlist(items: []value) *list = alloc(list { items = items })!;

// --- environment ---

type env = struct {
	names: []str,
	vals: []value,
	parent: nullable *env,
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
