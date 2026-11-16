// Runs the syntax tree.
use fmt;
use os;
use os::exec;
use strconv;
use strings;
use time;

type flow = enum { NORMAL, BREAK, CONTINUE };

let root: *env = null: *env;

fn home() str = os::tryenv("HOME", "/");

fn run_block(stmts: []stmt, e: *env) (flow | failed) = {
	for (let s .. stmts) {
		const f = exec_stmt(&s, e)?;
		if (f != flow::NORMAL) return f;
	};
	return flow::NORMAL;
};

fn exec_stmt(s: *stmt, e: *env) (flow | failed) = {
	match (*s) {
	case let l: s_let =>
		define(e, l.name, eval(l.val, e)?);
	case let a: s_assign =>
		const slot = match (env_find(e, a.name)) {
		case let p: *value => yield p;
		case void =>
			return dief(a.line, "'{}' er ikke defineret — brug 'let {} = ...'", a.name, a.name);
		};
		let v = eval(a.val, e)?;
		if (a.op != "=") {
			const op = strings::sub(a.op, 0, 1);
			v = binop(op, *slot, v, a.line)?;
		};
		*slot = v;
	case let x: s_expr =>
		eval(x.e, e)?;
	case let c: s_cmd =>
		run_cmd(c.stages, e, c.line, false, c.try_)?;
	case let i: s_if =>
		const inner = newenv(e);
		defer freeenv(inner);
		if (truthy(eval(i.cond, e)?)) return run_block(i.body, inner);
		return run_block(i.els, inner);
	case let w: s_while =>
		for (truthy(eval(w.cond, e)?)) {
			const inner = newenv(e);
			const f = run_block(w.body, inner);
			freeenv(inner);
			if (f? == flow::BREAK) break;
		};
	case let f: s_for =>
		return exec_for(&f, e);
	case let l: s_break =>
		return flow::BREAK;
	case let l: s_continue =>
		return flow::CONTINUE;
	};
	return flow::NORMAL;
};

fn items_of(v: value, line: int) ([]value | failed) = {
	match (v) {
	case let l: *list => return l.items;
	case let n: i64 =>
		let out: []value = [];
		for (let i = 0i64; i < n; i += 1) append(out, i)!;
		return out;
	case let s: str =>
		let out: []value = [];
		let it = strings::iter(s);
		for (let r => strings::next(&it)) {
			append(out, strings::fromrunes([r])!)!;
		};
		return out;
	case => return dief(line, "kan ikke løbe igennem en {}", typename(v));
	};
};

fn exec_for(f: *s_for, e: *env) (flow | failed) = {
	const items = items_of(eval(f.it, e)?, f.line)?;
	match (f.par) {
	case null =>
		for (let x .. items) {
			const inner = newenv(e);
			define(inner, f.var, x);
			const r = run_block(f.body, inner);
			freeenv(inner);
			if (r? == flow::BREAK) break;
		};
		return flow::NORMAL;
	case let pe: *expr =>
		const n = match (eval(pe, e)?) {
		case let n: i64 => yield n;
		case => return die(f.line, "'parallel' skal have et heltal ≥ 1");
		};
		if (n < 1) return die(f.line, "'parallel' skal have et heltal ≥ 1");
		return run_parallel(f, e, items, n: size);
	};
};

// Every runner is its own process (fork): real parallelism, and a crash in
// one runner cannot touch the others.
fn run_parallel(f: *s_for, e: *env, items: []value, n: size) (flow | failed) = {
	const t0 = time::now(time::clock::MONOTONIC);
	flush_out();
	let running = 0z, bad = 0z;
	for (let x .. items) {
		if (running >= n) {
			if (!wait_one()) bad += 1;
			running -= 1;
		};
		match (exec::fork()) {
		case void =>
			const inner = newenv(e);
			define(inner, f.var, x);
			match (run_block(f.body, inner)) {
			case flow =>
				flush_out();
				os::exit(0);
			case failed =>
				flush_out();
				report_error();
				os::exit(1);
			};
		case exec::process =>
			running += 1;
		case let err: exec::error =>
			return dief(f.line, "kunne ikke starte en løber: {}", exec::strerror(err));
		};
	};
	for (running > 0; running -= 1) {
		if (!wait_one()) bad += 1;
	};
	if (bad > 0) return dief(f.line, "{} af {} løbere snublede", bad, len(items));
	if (is_tty(os::stderr_file) && os::tryenv("DSH_QUIET", "") != "1") {
		const ms = time::diff(t0, time::now(time::clock::MONOTONIC)) / time::MILLISECOND;
		const cs = (ms % 1000) / 10;
		fmt::errorfln("{}⚡ {} job · {} løbere · {}.{}{}s{}", orange(), len(items), n,
			ms / 1000, if (cs < 10) "0" else "", cs, reset())!;
	};
	return flow::NORMAL;
};

fn wait_one() bool = {
	match (exec::waitany()) {
	case let r: (exec::process, exec::status) =>
		let st = r.1;
		return exec::check(&st) is void;
	case => return false;
	};
};

// --- expressions ---

fn eval(x: *expr, e: *env) (value | failed) = {
	match (*x) {
	case let n: e_num => return n: i64;
	case let c: e_const => return c.v;
	case let s: e_str => return eval_parts(s.parts, e)?;
	case let v: e_var =>
		match (env_find(e, v.name)) {
		case let p: *value => return *p;
		case void => return dief(v.line, "ukendt variabel '{}' — den er løbet sin vej", v.name);
		};
	case let l: e_list =>
		let items: []value = [];
		for (let it .. l.items) append(items, eval(it, e)?)!;
		return newlist(items);
	case let b: e_bin =>
		if (b.op == "and") {
			const a = eval(b.a, e)?;
			return if (!truthy(a)) a else eval(b.b, e)?;
		};
		if (b.op == "or") {
			const a = eval(b.a, e)?;
			return if (truthy(a)) a else eval(b.b, e)?;
		};
		return binop(b.op, eval(b.a, e)?, eval(b.b, e)?, b.line);
	case let u: e_un =>
		const a = eval(u.a, e)?;
		if (u.op == "not") return !truthy(a);
		match (a) {
		case let i: i64 => return -i;
		case => return dief(u.line, "kan ikke bruge '-' på en {}", typename(a));
		};
	case let c: e_call =>
		let args: []value = [];
		for (let a .. c.args) append(args, eval(a, e)?)!;
		return call(c.name, args, c.line);
	case let c: e_cap =>
		return capture(c.raw, e, c.line);
	case let ix: e_index =>
		const obj = eval(ix.obj, e)?;
		const i = match (eval(ix.idx, e)?) {
		case let i: i64 => yield i;
		case => return die(ix.line, "indeks skal være et heltal");
		};
		match (obj) {
		case let l: *list =>
			const k = if (i < 0) len(l.items): i64 + i else i;
			if (k < 0 || k >= len(l.items): i64) {
				return dief(ix.line, "indeks {} er udenfor (længde {})", i, len(l.items));
			};
			return l.items[k];
		case let s: str =>
			const b = strings::toutf8(s);
			const k = if (i < 0) len(b): i64 + i else i;
			if (k < 0 || k >= len(b): i64) {
				return dief(ix.line, "indeks {} er udenfor (længde {})", i, len(b));
			};
			return strings::dup(strings::fromutf8_unsafe(b[k..k + 1]))!;
		case => return dief(ix.line, "kan ikke slå op i en {}", typename(obj));
		};
	case let a: e_attr =>
		const obj = eval(a.obj, e)?;
		match (obj) {
		case let l: *list =>
			switch (a.name) {
			case "len" => return len(l.items): i64;
			case "first" => return if (len(l.items) > 0) l.items[0] else nilv;
			case "last" => return if (len(l.items) > 0) l.items[len(l.items) - 1] else nilv;
			case => void;
			};
		case let s: str =>
			if (a.name == "len") return len(s): i64;
		case => void;
		};
		return dief(a.line, "en {} har ingen egenskab '.{}'", typename(obj), a.name);
	};
};

fn eval_parts(parts: []part, e: *env) (str | failed) = {
	if (len(parts) == 1) return tostr(eval_part(parts[0], e, 0)?);
	let out: []u8 = [];
	for (let p .. parts) append(out, strings::toutf8(tostr(eval_part(p, e, 0)?))...)!;
	return strings::fromutf8_unsafe(out);
};

fn eval_part(p: part, e: *env, line: int) (value | failed) = {
	match (p) {
	case let s: p_lit => return s: str;
	case let n: p_var =>
		match (env_find(e, n)) {
		case let v: *value => return *v;
		case void => return dief(line, "ukendt variabel '{}' — den er løbet sin vej", n: str);
		};
	case let x: p_expr => return eval(x, e);
	case let c: p_cap => return capture(c, e, line);
	};
};

fn binop(op: str, a: value, b: value, line: int) (value | failed) = {
	if (op == "==") return equal(a, b);
	if (op == "!=") return !equal(a, b);
	if (op == "+") {
		if (a is str || b is str) return strings::concat(tostr(a), tostr(b))!;
		match (a) {
		case let x: *list =>
			match (b) {
			case let y: *list =>
				let items: []value = [];
				append(items, x.items...)!;
				append(items, y.items...)!;
				return newlist(items);
			case => void;
			};
		case => void;
		};
	};
	const x = match (a) {
	case let i: i64 => yield i;
	case => return dief(line, "kan ikke bruge '{}' på {} og {}", op, typename(a), typename(b));
	};
	const y = match (b) {
	case let i: i64 => yield i;
	case => return dief(line, "kan ikke bruge '{}' på {} og {}", op, typename(a), typename(b));
	};
	switch (op) {
	case "+" => return x + y;
	case "-" => return x - y;
	case "*" => return x * y;
	case "/" =>
		if (y == 0) return die(line, "division med nul — selv Dash kan ikke løbe uendeligt");
		return x / y;
	case "%" =>
		if (y == 0) return die(line, "division med nul — selv Dash kan ikke løbe uendeligt");
		return x % y;
	case "<" => return x < y;
	case ">" => return x > y;
	case "<=" => return x <= y;
	case ">=" => return x >= y;
	case => return dief(line, "ukendt operator '{}'", op);
	};
};

// --- built-in functions ---

fn need(name: str, args: []value, n: size, line: int) (void | failed) = {
	if (len(args) != n) {
		return dief(line, "{}() vil have {} argumenter, fik {}", name, n, len(args));
	};
};

fn int_arg(name: str, v: value, line: int) (i64 | failed) = match (v) {
case let i: i64 => yield i;
case => yield dief(line, "{}() vil have et heltal, fik {}", name, typename(v));
};

fn call(name: str, args: []value, line: int) (value | failed) = {
	switch (name) {
	case "print" =>
		for (let i = 0z; i < len(args); i += 1) {
			if (i > 0) fmt::print(" ")!;
			fmt::print(tostr(args[i]))!;
		};
		fmt::println()!;
		return nilv;
	case "len" =>
		need(name, args, 1, line)?;
		match (args[0]) {
		case let s: str => return len(s): i64;
		case let l: *list => return len(l.items): i64;
		case => return dief(line, "len() virker ikke på en {}", typename(args[0]));
		};
	case "str" =>
		need(name, args, 1, line)?;
		return tostr(args[0]);
	case "int" =>
		need(name, args, 1, line)?;
		match (args[0]) {
		case let i: i64 => return i;
		case let s: str =>
			match (strconv::stoi64(strings::trim(s))) {
			case let i: i64 => return i;
			case => return dief(line, "'{}' er ikke et heltal", s);
			};
		case => return dief(line, "int() virker ikke på en {}", typename(args[0]));
		};
	case "type" =>
		need(name, args, 1, line)?;
		return typename(args[0]);
	case "range" =>
		let a = 0i64, b = 0i64;
		if (len(args) == 1) {
			b = int_arg(name, args[0], line)?;
		} else {
			need(name, args, 2, line)?;
			a = int_arg(name, args[0], line)?;
			b = int_arg(name, args[1], line)?;
		};
		let items: []value = [];
		for (let i = a; i < b; i += 1) append(items, i)!;
		return newlist(items);
	case "env" =>
		const key = tostr(args[0]);
		match (os::getenv(key)) {
		case let s: str => return s;
		case void => return if (len(args) > 1) args[1] else nilv;
		};
	case "exists" =>
		need(name, args, 1, line)?;
		return os::exists(tostr(args[0]));
	case "which" =>
		need(name, args, 1, line)?;
		match (exec::lookup(tostr(args[0]))) {
		case let s: str => return strings::dup(s)!;
		case => return nilv;
		};
	case "now" =>
		const t = time::now(time::clock::MONOTONIC);
		return t.sec * 1000 + t.nsec / 1000000;
	case => return dief(line, "ukendt funktion '{}()'", name);
	};
};
