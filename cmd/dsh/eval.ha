// Runs the syntax tree.
use fmt;
use math;
use os;
use os::exec;
use strings;
use time;

type flow = enum { NORMAL, BREAK, CONTINUE, RETURN };

let root: *env = null: *env;
let ret_val: value = nilv;

fn home() str = os::tryenv("HOME", "/");

fn run_block(stmts: []stmt, e: *env) (flow | failed) = {
	for (let s &.. stmts) {
		const f = exec_stmt(s, e)?;
		if (f != flow::NORMAL) return f;
	};
	return flow::NORMAL;
};

fn exec_stmt(s: *stmt, e: *env) (flow | failed) = {
	match (*s) {
	case let l: s_let =>
		define(e, l.name, eval(l.val, e)?);
	case let a: s_assign =>
		assign(&a, e)?;
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
			switch (f?) {
			case flow::BREAK => break;
			case flow::RETURN => return flow::RETURN;
			case => void;
			};
		};
	case let f: s_for =>
		return exec_for(&f, e);
	case let f: s_fn =>
		e.captured = true;
		define(e, f.name, alloc(func {
			name = f.name,
			params = f.params,
			body = f.body,
			closure = e,
		})!);
	case let r: s_return =>
		ret_val = match (r.val) {
		case null => yield nilv;
		case let x: *expr => yield eval(x, e)?;
		};
		return flow::RETURN;
	case s_break =>
		return flow::BREAK;
	case s_continue =>
		return flow::CONTINUE;
	};
	return flow::NORMAL;
};

fn assign(a: *s_assign, e: *env) (void | failed) = {
	let v = eval(a.val, e)?;
	if (a.op != "=") {
		v = binop(strings::sub(a.op, 0, 1), eval(a.target, e)?, v, a.line)?;
	};
	match (*a.target) {
	case let t: e_var =>
		match (env_find(e, t.name)) {
		case let p: *value => *p = v;
		case void =>
			return dief(a.line, "'{}' er ikke defineret — brug 'let {} = ...'", t.name, t.name);
		};
	case let t: e_index =>
		const obj = eval(t.obj, e)?;
		const k = eval(t.idx, e)?;
		match (obj) {
		case let l: *list =>
			const i = list_index(l, k, a.line)?;
			l.items[i] = v;
		case let m: *mapv =>
			map_set(m, k, v);
		case => return dief(a.line, "kan ikke sætte [..] på en {}", typename(obj));
		};
	case let t: e_attr =>
		match (eval(t.obj, e)?) {
		case let m: *mapv => map_set(m, t.name, v);
		case => return dief(a.line, "kan kun sætte .{} på en map", t.name);
		};
	case => abort();
	};
};

fn list_index(l: *list, k: value, line: int) (size | failed) = {
	const i = match (k) {
	case let i: i64 => yield i;
	case => return die(line, "indeks skal være et heltal");
	};
	const n = len(l.items): i64;
	const j = if (i < 0) n + i else i;
	if (j < 0 || j >= n) return dief(line, "indeks {} er udenfor (længde {})", i, n);
	return j: size;
};

fn items_of(v: value, line: int) ([]value | failed) = {
	match (v) {
	case let l: *list => return l.items;
	case let m: *mapv => return m.keys;
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
			switch (r?) {
			case flow::BREAK => break;
			case flow::RETURN => return flow::RETURN;
			case => void;
			};
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
			case let fl: flow =>
				if (fl == flow::BREAK) {
					die(f.line, "'break' virker ikke i en parallel-løkke — man kan ikke stoppe alle løbere på én gang"): void;
					flush_out();
					report_error();
					os::exit(1);
				};
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
	case let n: e_fnum => return n: f64;
	case let c: e_const => return c.v;
	case let s: e_str => return eval_parts(s.parts, e)?;
	case let v: e_var =>
		match (env_find(e, v.name)) {
		case let p: *value => return *p;
		case void =>
			dief(v.line, "ukendt variabel '{}' — den er løbet sin vej", v.name): void;
			sethint(hint_from(v.name, visible_names(e)));
			return failed;
		};
	case let l: e_list =>
		let items: []value = [];
		for (let it .. l.items) append(items, eval(it, e)?)!;
		return newlist(items);
	case let m: e_map =>
		const mp = alloc(mapv { ... })!;
		for (let i = 0z; i < len(m.keys); i += 1) {
			map_set(mp, eval(m.keys[i], e)?, eval(m.vals[i], e)?);
		};
		return mp;
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
		case let f: f64 => return -f;
		case => return dief(u.line, "kan ikke bruge '-' på en {}", typename(a));
		};
	case let c: e_call =>
		let args: []value = [];
		for (let a .. c.args) append(args, eval(a, e)?)!;
		match (env_find(e, c.name)) {
		case let p: *value =>
			match (*p) {
			case let f: *func => return call_fn(f, args, c.line);
			case => return dief(c.line, "'{}' er en {}, ikke en funktion", c.name, typename(*p));
			};
		case void =>
			return call(c.name, args, c.line);
		};
	case let m: e_method =>
		const obj = eval(m.obj, e)?;
		let args: []value = [];
		for (let a .. m.args) append(args, eval(a, e)?)!;
		return method(obj, m.name, args, m.line);
	case let c: e_cap =>
		return capture(c.raw, e, c.line);
	case let ix: e_index =>
		const obj = eval(ix.obj, e)?;
		const k = eval(ix.idx, e)?;
		match (obj) {
		case let l: *list =>
			return l.items[list_index(l, k, ix.line)?];
		case let m: *mapv =>
			match (map_find(m, k)) {
			case let i: size => return m.vals[i];
			case void => return nilv;
			};
		case let s: str =>
			const i = match (k) {
			case let i: i64 => yield i;
			case => return die(ix.line, "indeks skal være et heltal");
			};
			const b = strings::toutf8(s);
			const j = if (i < 0) len(b): i64 + i else i;
			if (j < 0 || j >= len(b): i64) {
				return dief(ix.line, "indeks {} er udenfor (længde {})", i, len(b));
			};
			return strings::dup(strings::fromutf8_unsafe(b[j..j + 1]))!;
		case => return dief(ix.line, "kan ikke slå op i en {}", typename(obj));
		};
	case let a: e_attr =>
		return attr(eval(a.obj, e)?, a.name, a.line);
	};
};

// Every variable name the code can see here (for "mente du …?").
fn visible_names(e: *env) []str = {
	let out: []str = [];
	let cur: nullable *env = e;
	for (true) {
		const c = match (cur) {
		case null => return out;
		case let c: *env => yield c;
		};
		append(out, c.names...)!;
		cur = c.parent;
	};
};

fn call_fn(f: *func, args: []value, line: int) (value | failed) = {
	if (len(args) != len(f.params)) {
		return dief(line, "{}() vil have {} argumenter, fik {}", f.name, len(f.params), len(args));
	};
	const inner = newenv(f.closure);
	defer freeenv(inner);
	for (let i = 0z; i < len(args); i += 1) define(inner, f.params[i], args[i]);
	ret_val = nilv;
	switch (run_block(f.body, inner)?) {
	case flow::RETURN =>
		const r = ret_val;
		ret_val = nilv;
		return r;
	case flow::BREAK, flow::CONTINUE =>
		return dief(line, "'break'/'continue' uden for en løkke i {}()", f.name);
	case => return nilv;
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
		case void =>
			dief(line, "ukendt variabel '{}' — den er løbet sin vej", n: str): void;
			sethint(hint_from(n, visible_names(e)));
			return failed;
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
	// strings compare alphabetically
	match (a) {
	case let x: str =>
		match (b) {
		case let y: str =>
			const c = strings::compare(x, y);
			switch (op) {
			case "<" => return c < 0;
			case ">" => return c > 0;
			case "<=" => return c <= 0;
			case ">=" => return c >= 0;
			case => void;
			};
		case => void;
		};
	case => void;
	};
	if (!(a is i64 || a is f64) || !(b is i64 || b is f64)) return badop(op, a, b, line);

	// whole numbers stay whole
	if (a is i64 && b is i64) {
		const x = a as i64, y = b as i64;
		switch (op) {
		case "+" => return x + y;
		case "-" => return x - y;
		case "*" => return x * y;
		case "/" =>
			if (y == 0) return die(line, "division med nul — selv Dash kan ikke løbe uendeligt");
			if (x % y == 0) return x / y;
			return x: f64 / y: f64;
		case "%" =>
			if (y == 0) return die(line, "division med nul — selv Dash kan ikke løbe uendeligt");
			return x % y;
		case "<" => return x < y;
		case ">" => return x > y;
		case "<=" => return x <= y;
		case ">=" => return x >= y;
		case => return badop(op, a, b, line);
		};
	};
	const x = num(a) as f64, y = num(b) as f64;
	switch (op) {
	case "+" => return x + y;
	case "-" => return x - y;
	case "*" => return x * y;
	case "/" =>
		if (y == 0.0) return die(line, "division med nul — selv Dash kan ikke løbe uendeligt");
		return x / y;
	case "%" =>
		if (y == 0.0) return die(line, "division med nul — selv Dash kan ikke løbe uendeligt");
		return math::modf64(x, y);
	case "<" => return x < y;
	case ">" => return x > y;
	case "<=" => return x <= y;
	case ">=" => return x >= y;
	case => return badop(op, a, b, line);
	};
};

fn badop(op: str, a: value, b: value, line: int) failed =
	dief(line, "kan ikke bruge '{}' på {} og {}", op, typename(a), typename(b));
