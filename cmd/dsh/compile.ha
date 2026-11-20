// Violet, trin 2: oversætter .Dash til Hare-kode. 💜
//
// Typerne fra types.ha bestemmer, hvordan hver variabel bliver gemt:
// en ✔ int bliver et rigtigt i64, en ✔ float et f64, en ✔ str en str og en
// ✔ bool en bool. Alt andet bliver en dynamisk `value`, præcis som i
// fortolkeren. Kommandoer, builtins og fejlbeskeder kører gennem dsh' egen
// kode (runtime), så det oversatte program opfører sig som `dsh`.
//
// Kodegeneratoren går syntakstræet igennem i præcis samme rækkefølge som
// type-analysen, så scope-numrene passer, og hver variabel kan slås op.
use fmt;
use os;
use strconv;
use strings;

type kind = enum { I, F, S, B, V };

// Et oversat udtryk: Hare-koden og hvilken slags værdi den giver.
type gx = struct { c: str, k: kind };

let cbuf: []u8 = [];          // den funktion, der skrives lige nu
let cglob: []u8 = [];         // globale variabler
let cfns: []u8 = [];          // færdige fn'er
let cdepth = 1;
let cfn = -1;                 // indeks i fns for den fn, vi er inde i
let cdeclared: []bool = [];
let cerrs: []str = [];
let cuniq = 0;
let cpar = false;             // vi skriver kroppen af en parallel-løkke
let cpar_scope = 0;           // første scope inde i den
let cpar_loops = 0;           // løkker inde i parallel-kroppen
let ccaps: []size = [];       // variabler udefra, som kroppen bruger

fn cerr(line: int, msg: str) void = {
	append(cerrs, fmt::asprintf("linje {}: {}", line, msg)!)!;
};

fn uniq() int = {
	cuniq += 1;
	return cuniq;
};

fn emit(s: str) void = {
	for (let i = 0; i < cdepth; i += 1) append(cbuf, '\t')!;
	append(cbuf, strings::toutf8(s)...)!;
	append(cbuf, '\n')!;
};

// Hare-navne er ASCII: æ ø å bliver ae oe aa, alt andet bliver _xNN.
fn mangle(name: str) str = {
	let out: []u8 = [];
	let it = strings::iter(name);
	for (let r => strings::next(&it)) {
		switch (r) {
		case 'æ' => append(out, strings::toutf8("ae")...)!;
		case 'ø' => append(out, strings::toutf8("oe")...)!;
		case 'å' => append(out, strings::toutf8("aa")...)!;
		case 'Æ' => append(out, strings::toutf8("AE")...)!;
		case 'Ø' => append(out, strings::toutf8("OE")...)!;
		case 'Å' => append(out, strings::toutf8("AA")...)!;
		case =>
			const u = r: u32;
			if ((u >= 'a': u32 && u <= 'z': u32) || (u >= 'A': u32 && u <= 'Z': u32)
					|| (u >= '0': u32 && u <= '9': u32) || r == '_') {
				append(out, r: u8)!;
			} else {
				append(out, strings::toutf8(fmt::asprintf("_x{:x}", r: u32)!)...)!;
			};
		};
	};
	return strings::fromutf8_unsafe(out);
};

// En Hare-strengkonstant.
fn hlit(s: str) str = {
	let out: []u8 = [];
	append(out, '"')!;
	for (let c .. strings::toutf8(s)) {
		switch (c) {
		case '\\' => append(out, ['\\', '\\']...)!;
		case '"' => append(out, ['\\', '"']...)!;
		case '\n' => append(out, ['\\', 'n']...)!;
		case '\t' => append(out, ['\\', 't']...)!;
		case '\r' => append(out, ['\\', 'r']...)!;
		case =>
			if (c < 0x20 || c == 0x7f) {
				const hex = strings::toutf8("0123456789abcdef");
				append(out, ['\\', 'x', hex[c >> 4], hex[c & 0xf]]...)!;
			} else {
				append(out, c)!;
			};
		};
	};
	append(out, '"')!;
	return strings::fromutf8_unsafe(out);
};

// --- typer

fn kind_of(x: ty) kind = {
	if (!is_static(x)) return kind::V;
	switch (x.b) {
	case T_INT => return kind::I;
	case T_FLOAT => return kind::F;
	case T_STR => return kind::S;
	case T_BOOL => return kind::B;
	case => return kind::V;
	};
};

fn hare_type(k: kind) str = {
	switch (k) {
	case kind::I => return "i64";
	case kind::F => return "f64";
	case kind::S => return "str";
	case kind::B => return "bool";
	case kind::V => return "value";
	};
};

fn hare_zero(k: kind) str = {
	switch (k) {
	case kind::I => return "0i64";
	case kind::F => return "0.0f64";
	case kind::S => return "\"\"";
	case kind::B => return "false";
	case kind::V => return "nilv";
	};
};

fn is_global(b: size) bool = binds[b].scope == 0;

fn var_name(b: size) str = fmt::asprintf("{}{}_{}",
	if (is_global(b)) "g" else "v", b, mangle(binds[b].name))!;

fn fn_name(f: size) str = fmt::asprintf("f{}_{}", f, mangle(fns[f].name))!;

// Laver x om til slags k.
fn conv(x: gx, k: kind, line: int) str = {
	if (x.k == k) return x.c;
	switch (k) {
	case kind::V =>
		return fmt::asprintf("(({}): value)", x.c)!;
	case kind::I =>
		if (x.k == kind::V) return fmt::asprintf("as_int({}, {})?", x.c, line)!;
		return fmt::asprintf("as_int((({}): value), {})?", x.c, line)!;
	case kind::F =>
		if (x.k == kind::I) return fmt::asprintf("(({}): f64)", x.c)!;
		if (x.k == kind::V) return fmt::asprintf("as_float({}, {})?", x.c, line)!;
		return fmt::asprintf("as_float((({}): value), {})?", x.c, line)!;
	case kind::S =>
		if (x.k == kind::V) return fmt::asprintf("as_str({}, {})?", x.c, line)!;
		return fmt::asprintf("as_str((({}): value), {})?", x.c, line)!;
	case kind::B =>
		if (x.k == kind::V) return fmt::asprintf("as_bool({}, {})?", x.c, line)!;
		return fmt::asprintf("truthy((({}): value))", x.c)!;
	};
};

fn cv(x: gx, line: int) str = conv(x, kind::V, line);

// Teksten for x, som når den sættes ind i en streng.
fn str_of(x: gx) str = {
	if (x.k == kind::S) return x.c;
	return fmt::asprintf("tostr((({}): value))", x.c)!;
};

fn cond(x: gx) str = {
	if (x.k == kind::B) return x.c;
	return fmt::asprintf("truthy({})", cv(x, 0))!;
};

// Et resultat fra runtime (en value), som typerne siger er en bestemt slags.
fn typed(code: str, e: *expr, line: int) gx = {
	const k = kind_of(texpr(e));
	return gx { c = conv(gx { c = code, k = kind::V }, k, line), k = k };
};

// --- udtryk

fn gvar(name: str, line: int) gx = {
	match (lookup(name)) {
	case let b: size =>
		if (cpar && !is_global(b) && binds[b].scope < cpar_scope) {
			// en løber får en kopi af variablen (den kører i sin egen proces)
			let have = false;
			for (let c .. ccaps) if (c == b) have = true;
			if (!have) append(ccaps, b)!;
			return gx { c = var_name(b), k = kind_of(binds[b].t) };
		};
		if (cfn >= 0 && binds[b].owner != cfn && !is_global(b)) {
			cerr(line, fmt::asprintf("fn {}() bruger '{}' fra en omgivende blok — det kan Violet ikke endnu",
				fns[cfn].name, name)!);
		};
		if (binds[b].t.b == T_FN && find_fn(name) is size) {
			cerr(line, fmt::asprintf("'{}' bruges som værdi — Violet kan kun kalde fn'er (og bruge dem i .map/.filter)", name)!);
		};
		return gx { c = var_name(b), k = kind_of(binds[b].t) };
	case void => void;
	};
	switch (name) {
	case "args" => return gx { c = "rt_args()", k = kind::V };
	case "status" => return gx { c = "as_int(get_status(), 0)?", k = kind::I };
	case "script" => return gx { c = "script_name", k = kind::S };
	case => void;
	};
	cerr(line, fmt::asprintf("ukendt variabel '{}'", name)!);
	return gx { c = "nilv", k = kind::V };
};

fn gconst(v: value) gx = {
	match (v) {
	case let i: i64 => return gx { c = fmt::asprintf("{}i64", i)!, k = kind::I };
	case let f: f64 => return gfloat(f, 0);
	case let s: str => return gx { c = hlit(s), k = kind::S };
	case let b: bool => return gx { c = if (b) "true" else "false", k = kind::B };
	case nilv => return gx { c = "nilv", k = kind::V };
	case => return gx { c = "nilv", k = kind::V };
	};
};

fn gfloat(f: f64, line: int) gx = {
	let s = fmt::asprintf("{}", f)!;
	if (strings::contains(s, "e") || strings::contains(s, "n") || strings::contains(s, "i")) {
		// meget store/små tal: lad Hare læse dem ved opstart
		s = fmt::asprintf("strconv::stof64({})!", hlit(s))!;
		return gx { c = s, k = kind::F };
	};
	if (!strings::contains(s, ".")) s = strings::concat(s, ".0")!;
	return gx { c = strings::concat(s, "f64")!, k = kind::F };
};

fn gpart(p: part, line: int) gx = {
	match (p) {
	case let s: p_lit => return gx { c = hlit(s), k = kind::S };
	case let n: p_var => return gvar(n, line);
	case let e: p_expr => return gex(e);
	case let c: p_cap => return gcap(c, line);
	};
};

fn gparts_str(parts: []part, line: int) gx = {
	if (len(parts) == 0) return gx { c = "\"\"", k = kind::S };
	if (len(parts) == 1) return gx { c = str_of(gpart(parts[0], line)), k = kind::S };
	let ps: []str = [];
	for (let p .. parts) append(ps, str_of(gpart(p, line)))!;
	return gx { c = fmt::asprintf("strings::concat({})!", strings::join(", ", ps...)!)!, k = kind::S };
};

fn gcap(raw: str, line: int) gx = {
	match (parse_command(strings::toutf8(raw), line)) {
	case let st: []stage =>
		return gx { c = fmt::asprintf("cap_x({}, {})?", gstages(st, line), line)!, k = kind::S };
	case failed =>
		cerr(line, fmt::asprintf("kan ikke læse kommandoen $({})", raw)!);
		return gx { c = "\"\"", k = kind::S };
	};
};

fn is_num(k: kind) bool = k == kind::I || k == kind::F;

fn fl(x: gx) str = if (x.k == kind::F) x.c else fmt::asprintf("(({}): f64)", x.c)!;

fn gbin(op: str, a: gx, b: gx, line: int) gx = {
	if (op == "+" && (a.k == kind::S || b.k == kind::S)) {
		return gx { c = fmt::asprintf("strings::concat({}, {})!", str_of(a), str_of(b))!, k = kind::S };
	};
	const cmp = op == "<" || op == ">" || op == "<=" || op == ">=";
	if (is_num(a.k) && is_num(b.k)) {
		const both_int = a.k == kind::I && b.k == kind::I;
		if (cmp || op == "==" || op == "!=") {
			if (both_int) return gx { c = fmt::asprintf("({} {} {})", a.c, op, b.c)!, k = kind::B };
			if (cmp) return gx { c = fmt::asprintf("({} {} {})", fl(a), op, fl(b))!, k = kind::B };
		};
		switch (op) {
		case "+", "-", "*" =>
			if (both_int) return gx { c = fmt::asprintf("({} {} {})", a.c, op, b.c)!, k = kind::I };
			return gx { c = fmt::asprintf("({} {} {})", fl(a), op, fl(b))!, k = kind::F };
		case "%" =>
			if (both_int) return gx { c = fmt::asprintf("imod({}, {}, {})?", a.c, b.c, line)!, k = kind::I };
		case "/" =>
			if (!both_int) return gx { c = fmt::asprintf("fdiv({}, {}, {})?", fl(a), fl(b), line)!, k = kind::F };
		case => void;
		};
	};
	if (a.k == kind::S && b.k == kind::S) {
		if (op == "==" || op == "!=") return gx { c = fmt::asprintf("({} {} {})", a.c, op, b.c)!, k = kind::B };
		if (cmp) return gx { c = fmt::asprintf("(strings::compare({}, {}) {} 0)", a.c, b.c, op)!, k = kind::B };
	};
	if (a.k == kind::B && b.k == kind::B && (op == "==" || op == "!=")) {
		return gx { c = fmt::asprintf("({} {} {})", a.c, op, b.c)!, k = kind::B };
	};
	if (op == "==") return gx { c = fmt::asprintf("equal({}, {})", cv(a, line), cv(b, line))!, k = kind::B };
	if (op == "!=") return gx { c = fmt::asprintf("!equal({}, {})", cv(a, line), cv(b, line))!, k = kind::B };
	const r = fmt::asprintf("binop({}, {}, {}, {})?", hlit(op), cv(a, line), cv(b, line), line)!;
	if (cmp) return gx { c = fmt::asprintf("as_bool({}, {})?", r, line)!, k = kind::B };
	return gx { c = r, k = kind::V };
};

fn gex(e: *expr) gx = {
	match (*e) {
	case let n: e_num => return gx { c = fmt::asprintf("{}i64", n: i64)!, k = kind::I };
	case let f: e_fnum => return gfloat(f: f64, 0);
	case let c: e_const => return gconst(c.v);
	case let s: e_str => return gparts_str(s.parts, s.line);
	case let c: e_cap => return gcap(c.raw, c.line);
	case let v: e_var => return gvar(v.name, v.line);
	case let l: e_list =>
		if (len(l.items) == 0) return gx { c = "vlist0()", k = kind::V };
		let xs: []str = [];
		for (let it .. l.items) append(xs, cv(gex(it), 0))!;
		return gx { c = fmt::asprintf("vlist([{}])", strings::join(", ", xs...)!)!, k = kind::V };
	case let m: e_map =>
		if (len(m.keys) == 0) return gx { c = "vmap0()", k = kind::V };
		let ks: []str = [], vs: []str = [];
		for (let k .. m.keys) append(ks, cv(gex(k), 0))!;
		for (let v .. m.vals) append(vs, cv(gex(v), 0))!;
		return gx { c = fmt::asprintf("vmap([{}], [{}])", strings::join(", ", ks...)!,
			strings::join(", ", vs...)!)!, k = kind::V };
	case let b: e_bin =>
		const x = gex(b.a), y = gex(b.b);
		if (b.op == "and" || b.op == "or") {
			if (x.k == kind::B && y.k == kind::B) {
				return gx { c = fmt::asprintf("({} {} {})", x.c,
					if (b.op == "and") "&&" else "||", y.c)!, k = kind::B };
			};
			const t = fmt::asprintf("t{}", uniq())!;
			return gx { c = fmt::asprintf("{{ const {}: value = {}; yield if ({}truthy({})) {} else {}; }}",
				t, cv(x, b.line), if (b.op == "and") "!" else "", t, t, cv(y, b.line))!, k = kind::V };
		};
		return gbin(b.op, x, y, b.line);
	case let u: e_un =>
		const x = gex(u.a);
		if (u.op == "not") return gx { c = fmt::asprintf("!{}", cond(x))!, k = kind::B };
		if (is_num(x.k)) return gx { c = fmt::asprintf("(-{})", x.c)!, k = x.k };
		return gx { c = fmt::asprintf("neg_v({}, {})?", cv(x, u.line), u.line)!, k = kind::V };
	case let c: e_call => return gcall(&c, e);
	case let m: e_method => return gmethod(&m, e);
	case let i: e_index =>
		return typed(fmt::asprintf("index_v({}, {}, {})?", cv(gex(i.obj), i.line),
			cv(gex(i.idx), i.line), i.line)!, e, i.line);
	case let a: e_attr =>
		const o = gex(a.obj);
		if (a.name == "len" && o.k == kind::S) {
			return gx { c = fmt::asprintf("(len({}): i64)", o.c)!, k = kind::I };
		};
		return typed(fmt::asprintf("attr({}, {}, {})?", cv(o, a.line), hlit(a.name), a.line)!, e, a.line);
	};
};

// Kald af en af scriptets egne fn'er.
fn gfncall(f: size, args: []gx, line: int) gx = {
	const fi = &fns[f];
	if (len(args) != len(fi.params)) {
		cerr(line, fmt::asprintf("{}() vil have {} argumenter, fik {}", fi.name, len(fi.params), len(args))!);
	};
	let cs: []str = [];
	for (let i = 0z; i < len(args) && i < len(fi.params); i += 1) {
		append(cs, conv(args[i], kind_of(binds[fi.params[i]].t), line))!;
	};
	return gx { c = fmt::asprintf("{}({})?", fn_name(f), strings::join(", ", cs...)!)!,
		k = kind_of(fi.ret) };
};

fn gcall(c: *e_call, e: *expr) gx = {
	let args: []gx = [];
	for (let a .. c.args) append(args, gex(a))!;
	match (find_fn(c.name)) {
	case let f: size =>
		// en fn defineret i scriptet (texpr holder parametertyperne ajour)
		texpr(e);
		return gfncall(f, args, c.line);
	case void => void;
	};
	if (c.name == "len" && len(args) == 1 && args[0].k == kind::S) {
		return gx { c = fmt::asprintf("(len({}): i64)", args[0].c)!, k = kind::I };
	};
	let vs: []str = [];
	for (let a .. args) append(vs, cv(a, c.line))!;
	return typed(fmt::asprintf("call({}, [{}], {})?", hlit(c.name),
		strings::join(", ", vs...)!, c.line)!, e, c.line);
};

fn gmethod(m: *e_method, e: *expr) gx = {
	const o = gex(m.obj);
	// .map(f) og .filter(f) med en af scriptets fn'er bliver en løkke
	if ((m.name == "map" || m.name == "filter") && len(m.args) == 1) {
		match (*m.args[0]) {
		case let v: e_var =>
			match (find_fn(v.name)) {
			case let f: size =>
				const n = uniq();
				const item = gx { c = fmt::asprintf("it{}", n)!, k = kind::V };
				const call = gfncall(f, [item], m.line);
				const body = if (m.name == "map")
					fmt::asprintf("append(out{}, {})!;", n, cv(call, m.line))!
					else fmt::asprintf("if ({}) append(out{}, it{})!;", cond(call), n, n)!;
				return gx { c = fmt::asprintf("{{ let out{}: []value = []; for (let it{} .. items_of({}, {})?) {{ {} }}; yield newlist(out{}); }}",
					n, n, cv(o, m.line), m.line, body, n)!, k = kind::V };
			case void => void;
			};
		case => void;
		};
	};
	let vs: []str = [];
	for (let a .. m.args) append(vs, cv(gex(a), m.line))!;
	return typed(fmt::asprintf("method({}, {}, [{}], {})?", cv(o, m.line), hlit(m.name),
		strings::join(", ", vs...)!, m.line)!, e, m.line);
};

// --- kommandoer: en []xstage bygget som et Hare-udtryk

fn gword_str(w: *word, line: int) str = {
	if (!w.quoted && len(w.parts) == 1 && !(w.parts[0] is p_lit)) {
		return fmt::asprintf("one_v({})", cv(gpart(w.parts[0], line), line))!;
	};
	return gparts_str(w.parts, line).c;
};

fn gstages(stages: []stage, line: int) str = {
	const n = uniq();
	let out: []u8 = [];
	const add = &out;
	ms(add, fmt::asprintf("{{ let xs{}: []xstage = []; ", n)!);
	for (let st .. stages) {
		ms(add, fmt::asprintf("{{ let a{}: []str = []; ", n)!);
		for (let w .. st.args) {
			if (!w.quoted && len(w.parts) == 1 && !(w.parts[0] is p_lit)) {
				ms(add, fmt::asprintf("expand_v(&a{}, {}); ", n, cv(gpart(w.parts[0], line), line))!);
			} else {
				ms(add, fmt::asprintf("append(a{}, {})!; ", n, gparts_str(w.parts, line).c)!);
			};
		};
		let x = fmt::asprintf("xstage {{ args = a{}", n)!;
		match (st.out) {
		case let r: *redir =>
			x = fmt::asprintf("{}, out = {}, out_app = {}", x, gword_str(&r.target, line),
				if (r.app) "true" else "false")!;
		case null => x = strings::concat(x, ", out = void")!;
		};
		match (st.err) {
		case let r: *redir =>
			x = fmt::asprintf("{}, err = {}, err_app = {}", x, gword_str(&r.target, line),
				if (r.app) "true" else "false")!;
		case null => x = strings::concat(x, ", err = void")!;
		};
		match (st.inp) {
		case let w: *word => x = fmt::asprintf("{}, inp = {}", x, gword_str(w, line))!;
		case null => x = strings::concat(x, ", inp = void")!;
		};
		ms(add, fmt::asprintf("append(xs{}, {}, ... }})!; }}; ", n, x)!);
	};
	ms(add, fmt::asprintf("yield xs{}; }}", n)!);
	return strings::fromutf8_unsafe(out);
};

fn ms(b: *[]u8, s: str) void = append(b, strings::toutf8(s)...)!;

// --- sætninger (samme rækkefølge af scopes som i types.ha)

fn gblock(stmts: []stmt) void = {
	push_scope();
	gstmts(stmts);
	if (len(stmts) == 0) emit("void;");    // Hare vil ikke have tomme blokke
	pop_scope();
};

fn gstmts(stmts: []stmt) void = {
	for (let s &.. stmts) gstmt(s);
};

fn gdeclare(b: size, val: str) void = {
	if (is_global(b)) {
		emit(fmt::asprintf("{} = {};", var_name(b), val)!);
	} else if (!cdeclared[b]) {
		emit(fmt::asprintf("let {}: {} = {};", var_name(b), hare_type(kind_of(binds[b].t)), val)!);
		cdeclared[b] = true;
	} else {
		emit(fmt::asprintf("{} = {};", var_name(b), val)!);
	};
};

fn gstmt(s: *stmt) void = {
	match (*s) {
	case let l: s_let =>
		const v = gex(l.val);
		const b = match (find_in(stack[len(stack) - 1], l.name)) {
		case let b: size => yield b;
		case void => abort("Violet: let uden binding");
		};
		gdeclare(b, conv(v, kind_of(binds[b].t), l.line));
	case let a: s_assign => gassign(&a);
	case let i: s_if =>
		const c = gex(i.cond);
		emit(fmt::asprintf("if ({}) {{", cond(c))!);
		cdepth += 1;
		gblock(i.body);
		cdepth -= 1;
		if (len(i.els) == 0) {
			// tom else: intet at skrive, men scope-numrene skal passe
			push_scope();
			pop_scope();
			emit("};");
		} else {
			emit("} else {");
			cdepth += 1;
			gblock(i.els);
			cdepth -= 1;
			emit("};");
		};
	case let w: s_while =>
		// for (true) med et break først: så tror Hare aldrig, at løkken er
		// uendelig, og betingelsen regnes ud igen før hver runde
		const c = gex(w.cond);
		if (cpar) cpar_loops += 1;
		defer if (cpar) cpar_loops -= 1;
		emit("for (true) {");
		cdepth += 1;
		emit(fmt::asprintf("if (!({})) break;", cond(c))!);
		gblock(w.body);
		cdepth -= 1;
		emit("};");
	case let f: s_for => gfor(&f);
	case let f: s_fn => gfn(&f);
	case let r: s_return =>
		if (cpar) {
			emit("return;");    // en løber er færdig med sit job
			return;
		};
		if (cfn < 0) {
			emit("return;");
			return;
		};
		const rk = kind_of(fns[cfn].ret);
		match (r.val) {
		case let e: *expr =>
			emit(fmt::asprintf("return {};", conv(gex(e), rk, r.line))!);
		case null =>
			emit(fmt::asprintf("return {};", conv(gx { c = "nilv", k = kind::V }, rk, r.line))!);
		};
	case let c: s_cmd =>
		const st = gstages(c.stages, c.line);
		if (c.bg) {
			emit(fmt::asprintf("run_bg_x({}, {})?;", st, c.line)!);
		} else {
			emit(fmt::asprintf("run_c({}, {}, {})?;", st, c.line, if (c.try_) "true" else "false")!);
		};
	case let x: s_expr =>
		emit(fmt::asprintf("drop({});", cv(gex(x.e), x.line))!);
	case let b: s_break =>
		if (cpar && cpar_loops == 0) {
			cerr(b: int, "'break' virker ikke i en parallel-løkke — man kan ikke stoppe alle løbere på én gang");
		};
		emit("break;");
	case s_continue =>
		emit(if (cpar && cpar_loops == 0) "return;" else "continue;");
	};
};

fn gassign(a: *s_assign) void = {
	const v = gex(a.val);
	match (*a.target) {
	case let x: e_var =>
		const cur = gvar(x.name, a.line);
		const b = match (lookup(x.name)) {
		case let b: size => yield b;
		case void =>
			cerr(a.line, fmt::asprintf("'{}' er ikke defineret — brug 'let {} = ...'", x.name, x.name)!);
			return;
		};
		const nv = if (a.op == "=") v else gbin(strings::sub(a.op, 0, 1), cur, v, a.line);
		emit(fmt::asprintf("{} = {};", var_name(b), conv(nv, kind_of(binds[b].t), a.line))!);
	case let i: e_index =>
		emit(fmt::asprintf("set_index({}, {}, {}, {})?;", cv(gex(i.obj), a.line),
			cv(gex(i.idx), a.line), cv(gop(a, gex(a.target), v), a.line), a.line)!);
	case let f: e_attr =>
		emit(fmt::asprintf("set_attr({}, {}, {}, {})?;", cv(gex(f.obj), a.line),
			hlit(f.name), cv(gop(a, gex(a.target), v), a.line), a.line)!);
	case => cerr(a.line, "kan ikke tildele til det her");
	};
};

fn gop(a: *s_assign, cur: gx, v: gx) gx = {
	if (a.op == "=") return v;
	return gbin(strings::sub(a.op, 0, 1), cur, v, a.line);
};

fn gfor(f: *s_for) void = {
	if (f.par != null) {
		gpar(f);
		return;
	};
	if (cpar) cpar_loops += 1;
	defer if (cpar) cpar_loops -= 1;
	const n = uniq();
	// for i in range(...) med en int-variabel: en rigtig maskinløkke
	let fast = false;
	let a = "0i64", b = "0i64", step = 1i64;
	match (*f.it) {
	case let c: e_call =>
		if (c.name == "range" && find_fn("range") is void
				&& len(c.args) >= 1 && len(c.args) <= 3) {
			fast = true;
			if (len(c.args) == 3) {
				match (*c.args[2]) {
				case let k: e_num => step = k: i64;
				case let u: e_un =>
					match (*u.a) {
					case let k: e_num => if (u.op == "-") step = -(k: i64) else fast = false;
					case => fast = false;
					};
				case => fast = false;
				};
				if (step == 0) fast = false;
			};
			if (fast) {
				let xs: []gx = [];
				append(xs, gex(c.args[0]))!;
				if (len(c.args) > 1) append(xs, gex(c.args[1]))!;
				for (let x .. xs) if (x.k != kind::I) fast = false;
				if (fast) {
					if (len(c.args) == 1) b = xs[0].c else {
						a = xs[0].c;
						b = xs[1].c;
					};
				};
			};
		};
	case => void;
	};
	const it = if (fast) gx { ... } else gex(f.it);
	emit("{");
	cdepth += 1;
	if (fast) {
		emit(fmt::asprintf("const lo{}: i64 = {}, hi{}: i64 = {};", n, a, n, b)!);
		emit(fmt::asprintf("for (let ix{} = lo{}; ix{} {} hi{}; ix{} += {}) {{", n, n, n,
			if (step > 0) "<" else ">", n, n, step)!);
	} else {
		emit(fmt::asprintf("for (let it{} .. items_of({}, {})?) {{", n, cv(it, f.line), f.line)!);
	};
	cdepth += 1;
	push_scope();
	const vb = match (find_in(stack[len(stack) - 1], f.var)) {
	case let b: size => yield b;
	case void => abort("Violet: for uden binding");
	};
	const item = if (fast) gx { c = fmt::asprintf("ix{}", n)!, k = kind::I }
		else gx { c = fmt::asprintf("it{}", n)!, k = kind::V };
	emit(fmt::asprintf("let {}: {} = {};", var_name(vb), hare_type(kind_of(binds[vb].t)),
		conv(item, kind_of(binds[vb].t), f.line))!);
	cdeclared[vb] = true;
	gstmts(f.body);
	pop_scope();
	cdepth -= 1;
	emit("};");
	cdepth -= 1;
	emit("};");
};

// for x in liste parallel N { ... }: kroppen bliver sin egen fn, som hver
// løber (en fork) kalder. Variabler udefra sendes med som kopier — en løber
// kører alligevel i sin egen proces, ligesom i dsh.
fn gpar(f: *s_for) void = {
	if (cpar) cerr(f.line, "parallel inde i parallel kan Violet ikke endnu");
	const n = uniq();
	const it = gex(f.it);
	const par = conv(gex(f.par as *expr), kind::I, f.line);

	const saved_buf = cbuf;
	const saved_depth = cdepth;
	cbuf = [];
	cdepth = 1;
	cpar = true;
	cpar_loops = 0;
	ccaps = [];
	push_scope();
	cpar_scope = stack[len(stack) - 1];
	const vb = match (find_in(stack[len(stack) - 1], f.var)) {
	case let b: size => yield b;
	case void => abort("Violet: parallel uden binding");
	};
	emit(fmt::asprintf("let {}: {} = {};", var_name(vb), hare_type(kind_of(binds[vb].t)),
		conv(gx { c = fmt::asprintf("item{}", n)!, k = kind::V }, kind_of(binds[vb].t), f.line))!);
	cdeclared[vb] = true;
	gstmts(f.body);
	pop_scope();
	cpar = false;

	let ps: []str = [];
	let cargs: []str = [];
	append(ps, fmt::asprintf("item{}: value", n)!)!;
	append(cargs, fmt::asprintf("it{}", n)!)!;
	for (let c .. ccaps) {
		append(ps, fmt::asprintf("{}: {}", var_name(c), hare_type(kind_of(binds[c].t)))!)!;
		append(cargs, var_name(c))!;
	};
	append(cfns, strings::toutf8(fmt::asprintf("fn par{}({}) (void | failed) = {{\n",
		n, strings::join(", ", ps...)!)!)...)!;
	append(cfns, cbuf...)!;
	append(cfns, strings::toutf8("};\n\n")...)!;
	cbuf = saved_buf;
	cdepth = saved_depth;

	emit("{");
	cdepth += 1;
	emit(fmt::asprintf("const items{}: []value = items_of({}, {})?;", n, cv(it, f.line), f.line)!);
	emit(fmt::asprintf("let p{}: par = par_begin({}, {})?;", n, par, f.line)!);
	emit(fmt::asprintf("for (let it{} .. items{}) {{", n, n)!);
	emit(fmt::asprintf("\tif (par_fork(&p{}, {})?) par_child(par{}({}));", n, f.line, n,
		strings::join(", ", cargs...)!)!);
	emit("};");
	emit(fmt::asprintf("par_end(&p{}, len(items{}), {})?;", n, n, f.line)!);
	cdepth -= 1;
	emit("};");
};

fn gfn(f: *s_fn) void = {
	const idx = match (find_fn(f.name)) {
	case let i: size => yield i;
	case void => abort("Violet: fn uden info");
	};
	if (cfn >= 0) {
		cerr(f.line, fmt::asprintf("fn {}() inde i fn {}() — det kan Violet ikke endnu", f.name, fns[cfn].name)!);
	};
	// gem den kode, vi er i gang med, og skriv fn'en for sig
	const saved_buf = cbuf;
	const saved_depth = cdepth;
	const saved_fn = cfn;
	cbuf = [];
	cdepth = 1;
	cfn = idx: int;
	push_scope();
	const fi = &fns[idx];
	let ps: []str = [];
	for (let p .. fi.params) {
		append(ps, fmt::asprintf("{}: {}", var_name(p), hare_type(kind_of(binds[p].t)))!)!;
		cdeclared[p] = true;
	};
	const rk = kind_of(fi.ret);
	gstmts(f.body);
	if (!ends_in_return(f.body)) {
		emit(if (rk == kind::V) "return nilv;" else "abort(\"Violet: fn uden return\");");
	};
	pop_scope();
	let head = fmt::asprintf("fn {}({}) ({} | failed) = {{\n", fn_name(idx),
		strings::join(", ", ps...)!, hare_type(rk))!;
	append(cfns, strings::toutf8(head)...)!;
	append(cfns, cbuf...)!;
	append(cfns, strings::toutf8("};\n\n")...)!;
	cbuf = saved_buf;
	cdepth = saved_depth;
	cfn = saved_fn;
};

// Kører type-analysen og laver hele Hare-programmet. Fejl lander i cerrs.
fn compile_program(prog: []stmt, name: str, src: []u8) str = {
	infer(prog);

	cdeclared = [];
	for (let i = 0z; i < len(binds); i += 1) append(cdeclared, false)!;
	stack = stack[..0];
	next_scope = 0;
	cur_fn = -1;
	cfn = -1;
	cbuf = [];
	push_scope();
	gstmts(prog);

	let out: []u8 = [];
	ms(&out, fmt::asprintf("// Lavet af Violet 💜 ud fra {} — ret i .Dash-filen, ikke her.\n", name)!);
	ms(&out, "use os;\nuse strconv;\nuse strings;\n\n");
	for (let i = 0z; i < len(binds); i += 1) {
		if (!is_global(i) || binds[i].t.b == T_FN) continue;
		const k = kind_of(binds[i].t);
		ms(&out, fmt::asprintf("let {}: {} = {};\n", var_name(i), hare_type(k), hare_zero(k))!);
	};
	ms(&out, "\n");
	append(out, cfns...)!;
	ms(&out, "fn prog() (void | failed) = {\n");
	append(out, cbuf...)!;
	ms(&out, "};\n\nexport fn main() void = {\n");
	// fuld sti, så `script.dir` peger rigtigt, uanset hvor programmet startes
	const fuld = if (strings::hasprefix(name, "/")) name
		else strings::concat(os::getcwd(), "/", strings::trimprefix(name, "./"))!;
	ms(&out, fmt::asprintf("\trt_start({}, {});\n", hlit(fuld), hlit(strings::fromutf8_unsafe(src)))!);
	ms(&out, "\trt_end(prog());\n};\n");
	return strings::fromutf8_unsafe(out);
};

// Type-analysen til fikspunkt (fælles for types og build).
fn infer(prog: []stmt) int = {
	let rounds = 0;
	for (true) {
		changed = false;
		stack = stack[..0];
		next_scope = 0;
		cur_fn = -1;
		push_scope();
		tstmts(prog);
		rounds += 1;
		if (!changed || rounds >= 100) break;
	};
	return rounds;
};
