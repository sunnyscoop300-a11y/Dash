// dsh check fil.Dash — finds every error in a script without running it.
use fmt;
use os;
use sort;
use strings;

type problem = struct { line: int, msg: str, hint: str };

let checking = false;
let recovered: []str = [];    // names from let/fn lines that failed to parse
let problems: []problem = [];

fn record() void = {
	for (let p .. problems) {
		if (p.line == err_line && p.msg == err_msg) return;
		// a split string causes follow-up errors on the next line: skip them
		if (p.hint == HINT_SPLIT && err_hint != HINT_SPLIT
				&& (err_line == p.line || err_line == p.line + 1)) return;
	};
	append(problems, problem { line = err_line, msg = err_msg, hint = err_hint })!;
};

fn record_at(line: int, msg: str, hint: str) void = {
	die(line, msg): void;
	err_hint = hint;
	record();
};

// Parses as much as possible: after an error, skip to the next line.
fn program_check(p: *parser) []stmt = {
	let out: []stmt = [];
	for (true) {
		skip_seps(p);
		if (peek(p).kind == tkind::EOF) return out;
		if (at(p, "}")) {
			next(p);
			continue;
		};
		const start = p.pos;
		const t0 = peek(p), t1 = peek(p, 1);
		match (statement(p)) {
		case let s: stmt =>
			append(out, s)!;
			match (end_stmt(p)) {
			case void => void;
			case failed =>
				record();
				skip_line(p);
			};
		case failed =>
			record();
			if ((t0.val == "let" || t0.val == "fn") && t0.kind == tkind::KW
					&& t1.kind == tkind::IDENT) {
				append(recovered, t1.val)!;
			};
			if (p.pos == start) next(p);
			skip_line(p);
		};
	};
};

fn skip_line(p: *parser) void = {
	for (peek(p).kind != tkind::NL && peek(p).kind != tkind::EOF) next(p);
};

// --- static checks: names that are used but never defined ---

type names = struct { vars: []str, fns: []str };

fn has(list: []str, s: str) bool = {
	for (let x .. list) if (x == s) return true;
	return false;
};

fn collect(stmts: []stmt, n: *names) void = {
	for (let s .. stmts) {
		match (s) {
		case let l: s_let => append(n.vars, l.name)!;
		case let i: s_if =>
			collect(i.body, n);
			collect(i.els, n);
		case let w: s_while => collect(w.body, n);
		case let f: s_for =>
			append(n.vars, f.var)!;
			collect(f.body, n);
		case let f: s_fn =>
			append(n.fns, f.name)!;
			append(n.vars, f.name)!;
			append(n.vars, f.params...)!;
			collect(f.body, n);
		case => void;
		};
	};
};

fn walk_stmts(stmts: []stmt, n: *names) void = {
	for (let s .. stmts) {
		match (s) {
		case let l: s_let => walk_expr(l.val, n);
		case let a: s_assign =>
			match (*a.target) {
			case let v: e_var =>
				if (!has(n.vars, v.name)) {
					record_at(a.line, fmt::asprintf("'{}' er ikke defineret — brug 'let {} = ...'", v.name, v.name)!,
						hint_from(v.name, n.vars));
				};
			case => walk_expr(a.target, n);
			};
			walk_expr(a.val, n);
		case let i: s_if =>
			walk_expr(i.cond, n);
			walk_stmts(i.body, n);
			walk_stmts(i.els, n);
		case let w: s_while =>
			walk_expr(w.cond, n);
			walk_stmts(w.body, n);
		case let f: s_for =>
			walk_expr(f.it, n);
			match (f.par) { case let e: *expr => walk_expr(e, n); case null => void; };
			walk_stmts(f.body, n);
		case let f: s_fn => walk_stmts(f.body, n);
		case let r: s_return =>
			match (r.val) { case let e: *expr => walk_expr(e, n); case null => void; };
		case let x: s_expr => walk_expr(x.e, n);
		case let c: s_cmd => walk_cmd(&c, n);
		case => void;
		};
	};
};

fn walk_parts(parts: []part, n: *names, line: int) void = {
	for (let p .. parts) {
		match (p) {
		case let v: p_var =>
			if (!has(n.vars, v)) {
				record_at(line, fmt::asprintf("ukendt variabel '{}'", v: str)!, hint_from(v, n.vars));
			};
		case let e: p_expr => walk_expr(e, n);
		case => void;
		};
	};
};

fn walk_cmd(c: *s_cmd, n: *names) void = {
	for (let st .. c.stages) {
		for (let w .. st.args) walk_parts(w.parts, n, c.line);
		if (len(st.args) == 0 || c.try_) continue;    // try: may be missing
		const first = st.args[0];
		if (len(first.parts) != 1 || first.quoted) continue;
		const name = match (first.parts[0]) {
		case let l: p_lit => yield l: str;
		case => continue;
		};
		if (has(BUILTIN_CMDS, name) || strings::contains(resolve(name), "/")) continue;
		// the words as written, for the "missing #" check
		let words: []str = [];
		for (let w .. st.args) {
			if (len(w.parts) == 1 && w.parts[0] is p_lit && !w.quoted) {
				append(words, (w.parts[0] as p_lit): str)!;
			} else {
				append(words, "\"")!;    // quotes and $variables mean code
			};
		};
		record_at(c.line, fmt::asprintf("kommandoen '{}' findes ikke på denne maskine", name)!,
			command_hint(words, n.fns));
	};
};

fn walk_expr(x: *expr, n: *names) void = {
	match (*x) {
	case let v: e_var =>
		if (!has(n.vars, v.name)) {
			record_at(v.line, fmt::asprintf("ukendt variabel '{}'", v.name)!, hint_from(v.name, n.vars));
		};
	case let s: e_str => walk_parts(s.parts, n, s.line);
	case let l: e_list => for (let e .. l.items) walk_expr(e, n);
	case let m: e_map =>
		for (let e .. m.keys) walk_expr(e, n);
		for (let e .. m.vals) walk_expr(e, n);
	case let b: e_bin =>
		walk_expr(b.a, n);
		walk_expr(b.b, n);
	case let u: e_un => walk_expr(u.a, n);
	case let c: e_call =>
		if (!has(n.fns, c.name) && !has(BUILTIN_FNS, c.name) && !has(JJ_FNS, c.name)) {
			let cands: []str = [];
			append(cands, BUILTIN_FNS...)!;
			append(cands, JJ_FNS...)!;
			append(cands, n.fns...)!;
			record_at(c.line, fmt::asprintf("ukendt funktion '{}()'", c.name)!, hint_from(c.name, cands));
		};
		for (let e .. c.args) walk_expr(e, n);
	case let m: e_method =>
		walk_expr(m.obj, n);
		for (let e .. m.args) walk_expr(e, n);
	case let ix: e_index =>
		walk_expr(ix.obj, n);
		walk_expr(ix.idx, n);
	case let a: e_attr => walk_expr(a.obj, n);
	case => void;
	};
};

fn cmp_problem(a: const *opaque, b: const *opaque) int = {
	const x = a: const *problem, y = b: const *problem;
	return x.line - y.line;
};

fn check_main(src: []u8) never = {
	checking = true;
	fmt::printfln("{}⚡ dsh check{} {}", orange(), reset(), script_name)!;
	let toks: []token = [];
	match (lex(src, 1)) {
	case let t: []token => toks = t;
	case failed =>
		record();
		append(toks, token { kind = tkind::EOF, pos = len(src), line = 1, ... })!;
	};
	let p = parser { src = src, toks = toks, ... };
	const prog = program_check(&p);

	let n = names { ... };
	append(n.vars, ["args", "script", "status"]...)!;
	append(n.vars, recovered...)!;
	collect(prog, &n);
	walk_stmts(prog, &n);

	sort::sort(problems: []opaque, size(problem), &cmp_problem)!;
	for (let pr .. problems) {
		fmt::printfln("  {}✘ linje {}:{} {}", red(), pr.line, reset(), pr.msg)!;
		const l = source_line(pr.line);
		if (len(l) > 0) fmt::printfln("{}     {:4} │ {}{}", dim(), pr.line, l, reset())!;
		if (len(pr.hint) > 0) fmt::printfln("{}          ↳ {}{}", orange(), pr.hint, reset())!;
	};
	if (len(problems) == 0) {
		fmt::printfln("  {}✔ ingen fejl fundet — klar til at løbe ⚡{}", col("\x1b[1;32m"), reset())!;
		os::exit(0);
	};
	fmt::printfln("{}⚡✘ {} {} fundet{}", red(), len(problems),
		if (len(problems) == 1) "fejl" else "fejl", reset())!;
	os::exit(1);
};
