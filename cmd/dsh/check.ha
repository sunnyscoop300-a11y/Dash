// dsh check fil.Dash — finds every error in a script without running it.
use fmt;
use os;
use sort;
use strings;

type problem = struct { line: int, msg: str, hint: str };

let checking = false;
let recovered: []str = [];    // names from let/fn lines that failed to parse
let problems: []problem = [];
let warnings: []problem = [];    // ⚠: virker, men er ikke god Dash

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
		if (er_import(p)) {
			match (import_fil(p)) {
			case let s: []stmt => append(out, s...)!;
			case failed =>
				record();
				skip_line(p);
			};
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
		case let m: s_match =>
			for (let a .. m.arms) collect(a.body, n);
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
		case let m: s_match =>
			walk_expr(m.subj, n);
			for (let a .. m.arms) {
				for (let pat .. a.pats) walk_expr(pat, n);
				for (let h .. a.his) match (h) { case let e: *expr => walk_expr(e, n); case null => void; };
				match (a.guard) { case let g: *expr => walk_expr(g, n); case null => void; };
				walk_stmts(a.body, n);
			};
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

// sh -c "…" inde i et Dash-script: Dash kan selv køre kommandoer med pipes,
// > >> < 2> 2>&1 &> & og $( ) / &( ), så skallen skal ikke med.
// En linje med "# sh-ok" springes over (fx når brugerens egne kommandoer
// med vilje skal køre i hans egen shell).
fn warn_shell(c: *s_cmd) void = {
	for (let st .. c.stages) {
		if (len(st.args) < 2) continue;
		const a = &st.args[0];
		const b = &st.args[1];
		if (len(a.parts) != 1 || !(a.parts[0] is p_lit)) continue;
		if (len(b.parts) != 1 || !(b.parts[0] is p_lit)) continue;
		const prog = (a.parts[0] as p_lit): str;
		const flag = (b.parts[0] as p_lit): str;
		const shells = ["sh", "bash", "zsh", "dash", "/bin/sh", "/bin/bash"];
		if (!has(shells, prog) || flag != "-c") continue;
		if (strings::contains(source_line(c.line), "sh-ok")) continue;
		append(warnings, problem { line = c.line,
			msg = fmt::asprintf("{} -c gemmer en shell inde i Dash", prog)!,
			hint = "skriv kommandoen direkte: Dash kan | > >> < 2> 2>&1 &> & $( ) og &( ) selv (# sh-ok på linjen, hvis det er med vilje)" })!;
	};
};

fn walk_cmd(c: *s_cmd, n: *names) void = {
	warn_shell(c);
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

// Finder alle fejl og advarsler i src og lægger dem i problems og warnings
// (bruges af dsh check og af Miguel i editoren).
fn check_collect(src: []u8) void = {
	checking = true;
	problems = [];
	warnings = [];
	recovered = [];
	err_hint = "";
	kilder = [];
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
	sort::sort(warnings: []opaque, size(problem), &cmp_problem)!;
};

fn check_main(src: []u8) never = {
	fmt::printfln("{}⚡ dsh check{} {}", orange(), reset(), script_name)!;
	check_collect(src);
	for (let pr .. problems) {
		const (fil, n) = kilde_sted(pr.line);
		const hvor = if (pr.line >= KILDE_LINJER) fmt::asprintf("{} linje", fil)! else "linje";
		fmt::printfln("  {}✘ {} {}:{} {}", red(), hvor, n, reset(), pr.msg)!;
		const l = source_line(pr.line);
		if (len(l) > 0) fmt::printfln("{}     {:4} │ {}{}", dim(), n, l, reset())!;
		if (len(pr.hint) > 0) fmt::printfln("{}          ↳ {}{}", orange(), pr.hint, reset())!;
	};
	for (let pr .. warnings) {
		const (fil, n) = kilde_sted(pr.line);
		const hvor = if (pr.line >= KILDE_LINJER) fmt::asprintf("{} linje", fil)! else "linje";
		fmt::printfln("  {}⚠ {} {}:{} {}", orange(), hvor, n, reset(), pr.msg)!;
		const l = source_line(pr.line);
		if (len(l) > 0) fmt::printfln("{}     {:4} │ {}{}", dim(), n, l, reset())!;
		if (len(pr.hint) > 0) fmt::printfln("{}          ↳ {}{}", orange(), pr.hint, reset())!;
	};
	if (len(problems) == 0) {
		if (len(warnings) > 0) {
			fmt::printfln("  {}✔ ingen fejl, men {} {} ⚡{}", col("\x1b[1;32m"), len(warnings),
				if (len(warnings) == 1) "advarsel" else "advarsler", reset())!;
			os::exit(0);
		};
		fmt::printfln("  {}✔ ingen fejl fundet — klar til at løbe ⚡{}", col("\x1b[1;32m"), reset())!;
		os::exit(0);
	};
	fmt::printfln("{}⚡✘ {} {} fundet{}", red(), len(problems),
		if (len(problems) == 1) "fejl" else "fejl", reset())!;
	os::exit(1);
};
