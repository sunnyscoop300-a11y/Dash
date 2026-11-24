// Violet, trin 1: type-inferens. ⚡💜
//
// Finder ud af, hvilken type hver variabel og hver fn har, uden at køre
// scriptet. Det er grundlaget for Violet, der skal oversætte .Dash til
// native kode: en variabel med én fast type kan blive et rigtigt i64,
// f64 eller str i maskinkoden; en variabel der kan være flere ting, skal
// have en dynamisk værdi (og er langsommere).
//
// En type er et sæt af grundtyper (bits). Lister og maps husker også
// typen af deres elementer. Alle variabler starter tomme, og analysen
// kører hele scriptet igennem igen og igen og udvider typerne, indtil
// intet ændrer sig mere (et fikspunkt). Sættene kan kun vokse og er
// endelige, så det stopper altid.
use fmt;
use io;
use os;
use sort;
use strings;

def T_NIL: u16 = 1;
def T_BOOL: u16 = 2;
def T_INT: u16 = 4;
def T_FLOAT: u16 = 8;
def T_STR: u16 = 16;
def T_LIST: u16 = 32;
def T_MAP: u16 = 64;
def T_FN: u16 = 128;
def T_NUM: u16 = 12;      // int | float
def T_ANY: u16 = 255;

// b: hvad værdien kan være. le: hvad en listes elementer kan være.
// me: hvad et maps værdier kan være.
type ty = struct { b: u16, le: u16, me: u16 };

def NONE: ty = ty { b = 0, le = 0, me = 0 };
def ANY: ty = ty { b = T_ANY, le = T_ANY, me = T_ANY };

fn t(b: u16) ty = ty { b = b, le = 0, me = 0 };
fn tlist(le: u16) ty = ty { b = T_LIST, le = le, me = 0 };

fn join(a: ty, b: ty) ty = ty { b = a.b | b.b, le = a.le | b.le, me = a.me | b.me };

// --- bindinger: én pr. (scope, navn) ---

type binding = struct {
	scope: int,
	name: str,
	t: ty,
	line: int,
	owner: int,        // indeks i fns, -1 = globalt
	param: bool,
};

type fninfo = struct {
	name: str,
	line: int,
	params: []size,    // indeks i binds
	ret: ty,
	scope: int,
};

let binds: []binding = [];
let fns: []fninfo = [];
let changed = false;

// Scope-stak for den aktuelle gennemgang. Scope-numrene tildeles i samme
// rækkefølge hver gang, så de passer fra gennemgang til gennemgang.
let stack: []int = [];
let next_scope = 0;
let cur_fn = -1;

fn grow(dst: *ty, add: ty) void = {
	const n = join(*dst, add);
	if (n.b != dst.b || n.le != dst.le || n.me != dst.me) {
		*dst = n;
		changed = true;
	};
};

fn push_scope() void = {
	append(stack, next_scope)!;
	next_scope += 1;
};

fn pop_scope() void = {
	stack = stack[..len(stack) - 1];
};

fn find_in(scope: int, name: str) (size | void) = {
	for (let i = 0z; i < len(binds); i += 1) {
		if (binds[i].scope == scope && binds[i].name == name) return i;
	};
};

// Finder den nærmeste binding gennem scope-stakken. Rækkefølgen i et
// scope er ligegyldig: en fn kan bruge en global, der defineres længere
// nede, fordi den først slås op, når fn'en kaldes.
fn lookup(name: str) (size | void) = {
	for (let i = len(stack); i > 0; i -= 1) {
		match (find_in(stack[i - 1], name)) {
		case let b: size => return b;
		case void => void;
		};
	};
};

fn bind(name: str, line: int, param: bool) size = {
	const scope = stack[len(stack) - 1];
	match (find_in(scope, name)) {
	case let b: size => return b;
	case void => void;
	};
	append(binds, binding {
		scope = scope,
		name = name,
		t = NONE,
		line = line,
		owner = cur_fn,
		param = param,
	})!;
	changed = true;
	return len(binds) - 1;
};

fn find_fn(name: str) (size | void) = {
	for (let i = 0z; i < len(fns); i += 1) {
		if (fns[i].name == name) return i;
	};
};

// --- udtryk ---

fn tparts(parts: []part) void = {
	for (let p .. parts) {
		match (p) {
		case let e: p_expr => texpr(e);
		case => void;
		};
	};
};

fn tvalue(v: value) ty = {
	match (v) {
	case i64 => return t(T_INT);
	case f64 => return t(T_FLOAT);
	case str => return t(T_STR);
	case bool => return t(T_BOOL);
	case nilv => return t(T_NIL);
	case *list => return tlist(T_ANY);
	case *mapv => return ty { b = T_MAP, le = 0, me = T_ANY };
	case *func => return t(T_FN);
	};
};

// Typen af a <op> b for regnearterne.
fn tarith(op: str, a: ty, b: ty) ty = {
	let r = NONE;
	// & | ^ << >> // giver altid et heltal (eller en fejl)
	if (is_bitop(op)) return t(T_INT);
	if (op == "+") {
		if ((a.b | b.b) & T_STR != 0) r.b |= T_STR;
		if (a.b & T_LIST != 0 && b.b & T_LIST != 0) {
			r = join(r, tlist(a.le | b.le));
		};
	};
	const na = a.b & T_NUM, nb = b.b & T_NUM;
	if (na != 0 && nb != 0) {
		if (na & T_INT != 0 && nb & T_INT != 0) {
			r.b |= T_INT;
			// 7 / 2 giver 3.5, men 6 / 3 giver 2: det afgøres først når den kører
			if (op == "/") r.b |= T_FLOAT;
		};
		if (na & T_FLOAT != 0 || nb & T_FLOAT != 0) r.b |= T_FLOAT;
	};
	return r;
};

fn texpr(e: *expr) ty = {
	match (*e) {
	case e_num => return t(T_INT);
	case e_fnum => return t(T_FLOAT);
	case let c: e_const => return tvalue(c.v);
	case let s: e_str =>
		tparts(s.parts);
		return t(T_STR);
	case e_cap => return t(T_STR);
	case e_job => return t(T_INT);
	case let v: e_var => return tvar(v.name);
	case let l: e_list =>
		let le = 0u16;
		for (let it .. l.items) le |= texpr(it).b;
		return tlist(le);
	case let m: e_map =>
		let me = 0u16;
		for (let k .. m.keys) texpr(k);
		for (let v .. m.vals) me |= texpr(v).b;
		return ty { b = T_MAP, le = 0, me = me };
	case let b: e_bin =>
		const x = texpr(b.a), y = texpr(b.b);
		switch (b.op) {
		case "and", "or" => return join(x, y);
		case "==", "!=", "<", ">", "<=", ">=" => return t(T_BOOL);
		case => return tarith(b.op, x, y);
		};
	case let u: e_un =>
		const x = texpr(u.a);
		if (u.op == "not") return t(T_BOOL);
		if (u.op == "~") return t(T_INT);
		return t(x.b & T_NUM);
	case let c: e_call => return tcall(&c);
	case let m: e_method => return tmethod(&m);
	case let i: e_index =>
		const o = texpr(i.obj);
		texpr(i.idx);
		let r = 0u16;
		if (o.b & T_LIST != 0) r |= o.le;
		if (o.b & T_MAP != 0) r |= o.me | T_NIL;
		if (o.b & T_STR != 0) r |= T_STR;
		return t(r);
	case let a: e_attr => return tattr(texpr(a.obj), a.name);
	};
};

fn tvar(name: str) ty = {
	match (lookup(name)) {
	case let b: size => return binds[b].t;
	case void => void;
	};
	switch (name) {
	case "args" => return tlist(T_STR);
	case "script" => return t(T_STR);
	case "status" => return t(T_INT);
	case => void;
	};
	if (find_fn(name) is size) return t(T_FN);
	return NONE;
};

fn tattr(o: ty, name: str) ty = {
	let r = NONE;
	switch (name) {
	case "len" => return t(T_INT);
	case "first", "last" =>
		if (o.b & T_LIST != 0) r.b |= o.le | T_NIL;
	case "name", "dir", "stem", "ext" =>
		if (o.b & T_STR != 0) r.b |= T_STR;
	case "keys" =>
		if (o.b & T_MAP != 0) r = join(r, tlist(T_STR));
	case "chars" =>
		if (o.b & T_STR != 0) r = join(r, tlist(T_STR));
	case "values" =>
		if (o.b & T_MAP != 0) r = join(r, tlist(o.me));
	case => void;
	};
	// felter i et map: m.navn
	if (o.b & T_MAP != 0 && name != "len" && name != "keys" && name != "values" && name != "chars") {
		r.b |= o.me | T_NIL;
	};
	return r;
};

// Den variabel et udtryk peger direkte på (til .push() og x[i] = ...).
fn root_var(e: *expr) (size | void) = {
	match (*e) {
	case let v: e_var => return lookup(v.name);
	case => return;
	};
};

// .map(f) / .filter(f): listens elementer flyder ind i f's første parameter.
fn fn_arg_param(m: *e_method, elem: u16) (size | void) = {
	if (len(m.args) == 0) return;
	match (*m.args[0]) {
	case let v: e_var =>
		match (find_fn(v.name)) {
		case let f: size =>
			if (len(fns[f].params) > 0) grow(&binds[fns[f].params[0]].t, t(elem));
			return f;
		case void => void;
		};
	case => void;
	};
};

fn tmethod(m: *e_method) ty = {
	const o = texpr(m.obj);
	let at: []ty = [];
	defer free(at);
	for (let a .. m.args) append(at, texpr(a))!;
	switch (m.name) {
	case "trim", "upper", "lower", "replace", "repeat", "join" => return t(T_STR);
	case "contains", "starts_with", "ends_with", "has" => return t(T_BOOL);
	case "split", "lines" => return tlist(T_STR);
	case "push" =>
		if (len(at) > 0) {
			match (root_var(m.obj)) {
			case let b: size => grow(&binds[b].t, tlist(at[0].b));
			case void => void;
			};
		};
		return t(T_NIL);
	case "pop" => return t(o.le | T_NIL);
	case "sort", "reverse" => return tlist(o.le);
	case "filter" =>
		fn_arg_param(m, o.le);
		return tlist(o.le);
	case "map" =>
		// typen af det fn returnerer, hvis vi kender fn'en
		match (fn_arg_param(m, o.le)) {
		case let f: size => return tlist(fns[f].ret.b);
		case void => return tlist(T_ANY);
		};
	case "get" =>
		let r = o.me;
		r |= if (len(at) > 1) at[1].b else T_NIL;
		return t(r);
	case => return tattr(o, m.name);
	};
};

fn tcall(c: *e_call) ty = {
	let at: []ty = [];
	defer free(at);
	for (let a .. c.args) append(at, texpr(a))!;

	// en af scriptets egne fn: argumenterne flyder ind i parametrene
	match (find_fn(c.name)) {
	case let f: size =>
		for (let i = 0z; i < len(at) && i < len(fns[f].params); i += 1) {
			grow(&binds[fns[f].params[i]].t, at[i]);
		};
		// for få argumenter: de sidste parametre bliver nil
		for (let i = len(at); i < len(fns[f].params); i += 1) {
			grow(&binds[fns[f].params[i]].t, t(T_NIL));
		};
		return fns[f].ret;
	case void => void;
	};

	switch (c.name) {
	case "len", "int", "floor" => return t(T_INT);
	case "sin", "cos", "sqrt" => return t(T_FLOAT);
	case "random" => return t(if (len(at) == 0) T_FLOAT else T_INT);
	case "float", "now" => return t(T_FLOAT);
	case "str", "type", "read", "cwd", "parr.fmt" => return t(T_STR);
	case "exists", "is_dir", "is_file", "ask", "running" => return t(T_BOOL);
	case "wait" => return t(T_INT);
	case "bytes", "rd8", "rd16", "rd32", "bytes_len", "read_bytes", "read_into",
		"u32", "s32", "s16", "s8" => return t(T_INT);
	case "wr8", "wr16", "wr32", "copy_bytes", "fill_bytes", "free_bytes", "write_bytes" => return t(T_NIL);
	case "print", "write", "append", "sleep", "progress", "parr.ln", "parr.err", "parr.tabel" => return t(T_NIL);
	case "range" => return tlist(T_INT);
	case "glob" => return tlist(T_STR);
	case "which", "input" => return t(T_STR | T_NIL);
	case "env" =>
		return t(T_STR | (if (len(at) > 1) at[1].b else T_NIL));
	case "round" =>
		return t(if (len(at) > 1) T_FLOAT else T_INT);
	case "abs" =>
		return t(if (len(at) > 0) at[0].b & T_NUM else T_NUM);
	case "min", "max" =>
		let r = 0u16;
		for (let a .. at) r |= (a.b & T_NUM) | a.le;
		return t(r & T_NUM);
	case "menu" =>
		return t((if (len(at) > 0) at[0].le else T_ANY) | T_NIL);
	// JJGui
	case "pad_name" => return t(T_STR);
	case "pad_axis" => return t(T_INT);
	case "window", "frame", "button", "clicked", "right_clicked", "mouse_down", "key", "pressed",
		"fullscreen", "window_size", "pad_button" =>
		return t(T_BOOL);
	case "text_width", "wheel", "width", "height", "image", "sound", "sound_file" => return t(T_INT);
	case "delta" => return t(T_FLOAT);
	case "typed" => return t(T_STR);
	case "mouse", "image_size" => return tlist(T_INT);
	case "project" => return t(T_LIST | T_NIL);
	case "close_window", "clear", "rect", "outline", "round_rect", "circle", "line", "pixel",
		"polygon", "text", "draw", "play", "screenshot", "blit", "stream_pcm",
		"camera", "fog", "box3d", "floor3d", "circle3d", "render3d" => return t(T_NIL);
	case => return ANY;
	};
};

// --- sætninger ---

fn tblock(stmts: []stmt) void = {
	push_scope();
	tstmts(stmts);
	pop_scope();
};

fn tstmts(stmts: []stmt) void = {
	for (let s &.. stmts) tstmt(s);
};

fn ends_in_return(stmts: []stmt) bool = {
	if (len(stmts) == 0) return false;
	match (stmts[len(stmts) - 1]) {
	case s_return => return true;
	case let i: s_if =>
		return len(i.els) > 0 && ends_in_return(i.body) && ends_in_return(i.els);
	case let m: s_match =>
		// kun hvis der er en '_'-gren, og alle grene slutter med return
		if (len(m.arms) == 0) return false;
		const sidste = &m.arms[len(m.arms) - 1];
		if (!sidste.any || sidste.guard != null) return false;
		for (let a .. m.arms) if (!ends_in_return(a.body)) return false;
		return true;
	case => return false;
	};
};

fn tstmt(s: *stmt) void = {
	match (*s) {
	case let l: s_let =>
		const v = texpr(l.val);
		const b = bind(l.name, l.line, false);
		grow(&binds[b].t, v);
	case let a: s_assign =>
		const v = texpr(a.val);
		match (*a.target) {
		case let x: e_var =>
			match (lookup(x.name)) {
			case let b: size =>
				const nv = if (a.op == "=") v
					else tarith(strings::trimsuffix(a.op, "="), binds[b].t, v);
				grow(&binds[b].t, nv);
			case void => void;
			};
		case let i: e_index =>
			texpr(i.idx);
			match (root_var(i.obj)) {
			case let b: size =>
				const o = binds[b].t;
				if (o.b & T_LIST != 0) grow(&binds[b].t, tlist(v.b));
				if (o.b & T_MAP != 0) grow(&binds[b].t, ty { b = T_MAP, le = 0, me = v.b });
			case void => texpr(i.obj);
			};
		case let f: e_attr =>
			match (root_var(f.obj)) {
			case let b: size => grow(&binds[b].t, ty { b = T_MAP, le = 0, me = v.b });
			case void => texpr(f.obj);
			};
		case => texpr(a.target);
		};
	case let i: s_if =>
		texpr(i.cond);
		tblock(i.body);
		tblock(i.els);
	case let w: s_while =>
		texpr(w.cond);
		tblock(w.body);
	case let m: s_match =>
		texpr(m.subj);
		for (let a &.. m.arms) {
			for (let i = 0z; i < len(a.pats); i += 1) {
				texpr(a.pats[i]);
				match (a.his[i]) { case let h: *expr => texpr(h); case null => void; };
			};
			match (a.guard) { case let g: *expr => texpr(g); case null => void; };
			tblock(a.body);
		};
	case let f: s_for =>
		const it = texpr(f.it);
		match (f.par) {
		case let p: *expr => texpr(p);
		case null => void;
		};
		let el = 0u16;
		if (it.b & T_LIST != 0) el |= it.le;
		if (it.b & (T_STR | T_MAP) != 0) el |= T_STR;
		if (it.b & T_INT != 0) el |= T_INT;
		push_scope();
		const vb = bind(f.var, f.line, false);
		grow(&binds[vb].t, t(el));
		tstmts(f.body);
		pop_scope();
	case let f: s_fn =>
		const fb = bind(f.name, f.line, false);
		grow(&binds[fb].t, t(T_FN));
		push_scope();
		const scope = stack[len(stack) - 1];
		const idx = match (find_fn(f.name)) {
		case let i: size => yield i;
		case void =>
			append(fns, fninfo { name = f.name, line = f.line, scope = scope, ... })!;
			changed = true;
			yield len(fns) - 1;
		};
		const saved = cur_fn;
		cur_fn = idx: int;
		if (len(fns[idx].params) == 0) {
			for (let p .. f.params) {
				const pb = bind(p, f.line, true);
				append(fns[idx].params, pb)!;
			};
		};
		tstmts(f.body);
		if (!ends_in_return(f.body)) grow(&fns[idx].ret, t(T_NIL));
		cur_fn = saved;
		pop_scope();
	case let r: s_return =>
		const v = match (r.val) {
		case let e: *expr => yield texpr(e);
		case null => yield t(T_NIL);
		};
		if (cur_fn >= 0) grow(&fns[cur_fn].ret, v);
	case let c: s_cmd =>
		for (let st .. c.stages) {
			for (let w .. st.args) tparts(w.parts);
			match (st.out) {
			case let r: *redir => tparts(r.target.parts);
			case null => void;
			};
			match (st.err) {
			case let r: *redir => tparts(r.target.parts);
			case null => void;
			};
			match (st.inp) {
			case let w: *word => tparts(w.parts);
			case null => void;
			};
		};
	case let x: s_expr => texpr(x.e);
	case => void;
	};
};

// --- udskrift ---

// Farver kun når udskriften går til en terminal (ikke i en pipe).
fn vcol(code: str) str = if (is_tty(os::stdout_file)) code else "";
fn vreset() str = vcol("\x1b[0m");
fn vdim() str = vcol("\x1b[2m");

// "str", "int|nil", "num" (int|float), "list[str]" ...
fn bits_names(b: u16, out: *[]str) void = {
	if (b == T_ANY) {
		append(out, "any")!;
		return;
	};
	if (b & T_BOOL != 0) append(out, "bool")!;
	if (b & T_NUM == T_NUM) {
		append(out, "num")!;
	} else {
		if (b & T_INT != 0) append(out, "int")!;
		if (b & T_FLOAT != 0) append(out, "float")!;
	};
	if (b & T_STR != 0) append(out, "str")!;
	if (b & T_FN != 0) append(out, "fn")!;
};

fn elem_name(b: u16) str = {
	if (b == 0) return "?";
	let n: []str = [];
	bits_names(b & ~(T_LIST | T_MAP), &n);
	if (b != T_ANY) {
		if (b & T_LIST != 0) append(n, "list")!;
		if (b & T_MAP != 0) append(n, "map")!;
		if (b & T_NIL != 0) append(n, "nil")!;
	};
	return strings::join("|", n...)!;
};

fn tname(x: ty) str = {
	if (x.b == 0) return "?";
	let n: []str = [];
	bits_names(x.b & ~(T_LIST | T_MAP), &n);
	if (x.b != T_ANY) {
		if (x.b & T_LIST != 0) append(n, strings::concat("list[", elem_name(x.le), "]")!)!;
		if (x.b & T_MAP != 0) append(n, strings::concat("map[", elem_name(x.me), "]")!)!;
		if (x.b & T_NIL != 0) append(n, "nil")!;
	};
	return strings::join("|", n...)!;
};

// Én fast type = Violet kan bruge et rigtigt maskin-tal eller en ren
// streng. Lister/maps tæller som faste, hvis deres elementer er det.
fn one_bit(b: u16) bool = b != 0 && b & (b - 1) == 0;

fn is_static(x: ty) bool = {
	if (!one_bit(x.b)) return false;
	if (x.b == T_LIST) return one_bit(x.le);
	if (x.b == T_MAP) return one_bit(x.me);
	return true;
};

fn bind_cmp(a: const *opaque, b: const *opaque) int = {
	const x = a: const *size, y = b: const *size;
	return binds[*x].line - binds[*y].line;
};

fn print_bind(i: size, w: size) void = {
	const b = &binds[i];
	const mark = if (is_static(b.t)) strings::concat(vcol("\x1b[1;32m"), "✔")!
		else strings::concat(vcol("\x1b[1;38;5;208m"), "~")!;
	let pad: []u8 = [];
	defer free(pad);
	for (let k = utf8_width(b.name); k < w; k += 1) append(pad, ' ')!;
	fmt::printfln("    {}{} {}{}  {}", mark, vreset(), b.name,
		strings::fromutf8_unsafe(pad), tname(b.t))!;
};

fn utf8_width(s: str) size = {
	let n = 0z;
	for (let c .. strings::toutf8(s)) if (c & 0xc0 != 0x80) n += 1;
	return n;
};

fn types_main(src: []u8) never = {
	const toks = match (lex(src, 1)) {
	case let t: []token => yield t;
	case failed =>
		report_error();
		os::exit(1);
	};
	let p = parser { src = src, toks = toks, ... };
	const prog = match (program(&p)) {
	case let s: []stmt => yield s;
	case failed =>
		report_error();
		os::exit(1);
	};

	// kør analysen, indtil intet ændrer sig mere
	const rounds = infer(prog);

	fmt::printfln("{}💜 violet types{} {}  {}({} gennemløb){}", vcol("\x1b[1;38;5;141m"),
		vreset(), script_name, vdim(), rounds, vreset())!;

	// bredde til navnekolonnen
	let w = 4z;
	for (let b .. binds) if (utf8_width(b.name) > w) w = utf8_width(b.name);

	// globale variabler (ikke fn'er)
	let glob: []size = [];
	for (let i = 0z; i < len(binds); i += 1) {
		if (binds[i].owner == -1 && binds[i].t.b != T_FN) append(glob, i)!;
	};
	sort::sort(glob: []opaque, size(size), &bind_cmp)!;
	if (len(glob) > 0) {
		fmt::printfln("  {}globalt{}", vcol("\x1b[1m"), vreset())!;
		for (let i .. glob) print_bind(i, w);
	};

	let total = 0, fast = 0;
	for (let b .. binds) {
		if (b.t.b == T_FN) continue;
		total += 1;
		if (is_static(b.t)) fast += 1;
	};

	for (let f = 0z; f < len(fns); f += 1) {
		const fi = &fns[f];
		let ps: []str = [];
		for (let p .. fi.params) {
			append(ps, strings::concat(binds[p].name, ": ", tname(binds[p].t))!)!;
		};
		const retm = if (is_static(fi.ret)) vcol("\x1b[1;32m") else vcol("\x1b[1;38;5;208m");
		fmt::printfln("  {}fn {}{}({}) → {}{}{}", vcol("\x1b[1m"), fi.name, vreset(),
			strings::join(", ", ps...)!, retm, tname(fi.ret), vreset())!;
		let loc: []size = [];
		for (let i = 0z; i < len(binds); i += 1) {
			if (binds[i].owner == f: int && !binds[i].param && binds[i].t.b != T_FN) {
				append(loc, i)!;
			};
		};
		sort::sort(loc: []opaque, size(size), &bind_cmp)!;
		for (let i .. loc) print_bind(i, w);
	};

	const pct = if (total == 0) 100 else fast * 100 / total;
	fmt::println()!;
	fmt::printfln("  {}{} af {} variabler har én fast type ({}%){}",
		vcol("\x1b[1;38;5;141m"), fast, total, pct, vreset())!;
	fmt::printfln("  {}✔ = Violet kan bruge rene maskintyper   ~ = dynamisk værdi{}",
		vdim(), vreset())!;
	os::exit(0);
};
