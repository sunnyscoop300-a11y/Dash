// Tokens → syntax tree. Command lines are cut out of the source as raw
// text and split into words, so they keep shell-like freedom.
use fmt;
use strings;

type parser = struct {
	src: []u8,
	toks: []token,
	pos: size,
	prev: token,
};

fn peek(p: *parser, k: size = 0) token = {
	const i = p.pos + k;
	return if (i < len(p.toks)) p.toks[i] else p.toks[len(p.toks) - 1];
};

fn next(p: *parser) token = {
	const t = p.toks[p.pos];
	p.pos += 1;
	p.prev = t;
	return t;
};

fn at(p: *parser, v: str) bool = {
	const t = peek(p);
	return (t.kind == tkind::OP || t.kind == tkind::KW) && t.val == v;
};

fn desc(t: token) str = switch (t.kind) {
case tkind::NL => yield "linjeskift";
case tkind::EOF => yield "slutningen af filen";
case => yield strings::concat("'", t.val, "'")!;
};

fn expect(p: *parser, v: str) (token | failed) = {
	if (!at(p, v)) {
		const t = peek(p);
		dief(t.line, "forventede '{}', fik {}", v, desc(t)): void;
		if (v == "," && t.line > p.prev.line) {
			sethint(fmt::asprintf("mangler der et komma i slutningen af linje {}?", p.prev.line)!);
		};
		return failed;
	};
	return next(p);
};

fn expect_ident(p: *parser) (str | failed) = {
	const t = peek(p);
	if (t.kind != tkind::IDENT) return dief(t.line, "forventede et navn, fik {}", desc(t));
	return next(p).val;
};

fn skip_seps(p: *parser) void = {
	for (peek(p).kind == tkind::NL || at(p, ";")) next(p);
};

fn end_stmt(p: *parser) (void | failed) = {
	const t = peek(p);
	if (t.kind == tkind::NL || at(p, ";")) {
		skip_seps(p);
	} else if (t.kind == tkind::EOF || at(p, "}")) {
		void;
	} else if (t.line != p.prev.line) {
		void;
	} else {
		return dief(t.line, "uventet {}", desc(t));
	};
};

fn program(p: *parser) ([]stmt | failed) = {
	let out: []stmt = [];
	for (true) {
		skip_seps(p);
		if (peek(p).kind == tkind::EOF) return out;
		append(out, statement(p)?)!;
		end_stmt(p)?;
	};
};

fn block(p: *parser) ([]stmt | failed) = {
	expect(p, "{")?;
	let out: []stmt = [];
	for (true) {
		skip_seps(p);
		if (at(p, "}")) { next(p); return out; };
		if (peek(p).kind == tkind::EOF) return die(peek(p).line, "blok mangler '}'");
		append(out, statement(p)?)!;
		end_stmt(p)?;
	};
};

fn statement(p: *parser) (stmt | failed) = {
	const t = peek(p);
	const line = t.line;
	if (t.kind == tkind::KW) {
		switch (t.val) {
		case "let" =>
			next(p);
			const name = expect_ident(p)?;
			expect(p, "=")?;
			return s_let { name = name, val = pexpr(p)?, line = line };
		case "if" =>
			next(p);
			return if_rest(p, line)?;
		case "while" =>
			next(p);
			const cond = pexpr(p)?;
			return s_while { cond = cond, body = block(p)?, line = line };
		case "for" =>
			next(p);
			const v = expect_ident(p)?;
			expect(p, "in")?;
			const it = pexpr(p)?;
			let par: nullable *expr = null;
			if (at(p, "parallel")) {
				next(p);
				par = pexpr(p)?;
			};
			return s_for { var = v, it = it, par = par, body = block(p)?, line = line };
		case "fn" =>
			next(p);
			const name = expect_ident(p)?;
			if (peek(p).kind == tkind::IDENT && !at(p, "(")) {
				const joined = strings::concat(name, peek(p).val)!;
				return dieh(line, "mellemrum i funktionsnavnet", mente(joined));
			};
			expect(p, "(")?;
			let params: []str = [];
			for (!at(p, ")")) {
				append(params, expect_ident(p)?)!;
				if (!at(p, ")")) expect(p, ",")?;
			};
			expect(p, ")")?;
			return s_fn { name = name, params = params, body = block(p)?, line = line };
		case "return" =>
			next(p);
			const n = peek(p);
			if (n.kind == tkind::NL || n.kind == tkind::EOF || at(p, "}") || at(p, ";")) {
				return s_return { val = null, line = line };
			};
			return s_return { val = pexpr(p)?, line = line };
		case "break" =>
			next(p);
			return (line: s_break): stmt;
		case "continue" =>
			next(p);
			return (line: s_continue): stmt;
		case "echo", "fail" =>
			return command(p, t, false)?;
		case "try" =>
			next(p);
			return command(p, peek(p), true)?;
		case => void;
		};
	};
	if (t.kind == tkind::IDENT) {
		const nx = peek(p, 1);
		if (is_assign(nx)) {
			next(p);
			const op = next(p).val;
			const target = mk(e_var { name = t.val, line = line });
			return s_assign { target = target, op = op, val = pexpr(p)?, line = line };
		};
		if (nx.kind == tkind::OP && (nx.val == "(" || nx.val == "[" || nx.val == ".")
				&& !nx.space) {
			const e = pexpr(p)?;
			if (is_assign(peek(p))) {
				if (!(*e is e_var || *e is e_index || *e is e_attr)) {
					return die(line, "kan ikke tildele til det udtryk");
				};
				const op = next(p).val;
				return s_assign { target = e, op = op, val = pexpr(p)?, line = line };
			};
			return s_expr { e = e, line = line };
		};
	};
	if (t.kind == tkind::NUM || t.kind == tkind::STR || t.kind == tkind::RSTR
			|| t.kind == tkind::CAP || (t.kind == tkind::OP && t.val == "[")) {
		return s_expr { e = pexpr(p)?, line = line };
	};
	return command(p, t, false)?;
};

fn is_assign(t: token) bool = t.kind == tkind::OP && (t.val == "=" || t.val == "+="
	|| t.val == "-=" || t.val == "*=" || t.val == "/=");

fn if_rest(p: *parser, line: int) (s_if | failed) = {
	const cond = pexpr(p)?;
	const body = block(p)?;
	let els: []stmt = [];
	const save = p.pos;
	skip_seps(p);
	if (at(p, "else")) {
		next(p);
		if (at(p, "if")) {
			const l2 = next(p).line;
			append(els, if_rest(p, l2)?)!;
		} else {
			els = block(p)?;
		};
	} else {
		p.pos = save;
	};
	return s_if { cond = cond, body = body, els = els, line = line };
};

// --- command lines ---

// Where a command line ends: newline, ';', a comment or an unmatched '}'.
fn cmd_end(src: []u8, i: size, line: int) (size | failed) = {
	let depth = 0;
	for (i < len(src)) {
		const c = src[i];
		if (c == '\\') { i += 2; continue; };
		if (c == '"') { i = scan_string(src, i, line)?; continue; };
		if (c == '\'') {
			let k = i + 1;
			for (k < len(src) && src[k] != '\'') k += 1;
			i = if (k < len(src)) k + 1 else i + 1;
			continue;
		};
		if (c == '$' && i + 1 < len(src) && (src[i + 1] == '(' || src[i + 1] == '{')) {
			const close: u8 = if (src[i + 1] == '(') ')' else '}';
			i = scan_balanced(src, i + 1, src[i + 1], close, line)?;
			continue;
		};
		if (c == '{') {
			depth += 1;
		} else if (c == '}') {
			if (depth == 0) return i;
			depth -= 1;
		} else if ((c == '\n' || c == ';') && depth == 0) {
			return i;
		} else if (c == '#' && (i == 0 || src[i - 1] == ' ' || src[i - 1] == '\t')) {
			return i;
		};
		i += 1;
	};
	return len(src);
};

fn command(p: *parser, start: token, try_: bool) (s_cmd | failed) = {
	if (start.kind == tkind::EOF) return die(start.line, "forventede en kommando");
	const end = cmd_end(p.src, start.pos, start.line)?;
	for (peek(p).kind != tkind::EOF && peek(p).pos < end) next(p);
	// a trailing '&' runs the line in the background
	let text = p.src[start.pos..end];
	let n = len(text);
	for (n > 0 && (text[n - 1] == ' ' || text[n - 1] == '\t')) n -= 1;
	let bg = false;
	if (n > 0 && text[n - 1] == '&' && (n < 2 || text[n - 2] != '&')) {
		bg = true;
		text = text[..n - 1];
	};
	return s_cmd {
		stages = parse_command(text, start.line)?,
		try_ = try_,
		bg = bg,
		line = start.line,
	};
};

fn parse_command(text: []u8, line: int) ([]stage | failed) = {
	let stages: []stage = [];
	let cur = stage { ... };
	let i = 0z;
	let redirect = 0;    // 1 = >, 2 = >>, 3 = 2>, 4 = 2>>, 5 = <
	for (true) {
		for (i < len(text) && (text[i] == ' ' || text[i] == '\t'
				|| (text[i] == '\\' && i + 1 < len(text) && text[i + 1] == '\n'))) {
			i += if (text[i] == '\\') 2z else 1z;
		};
		if (i >= len(text)) break;
		const c = text[i];
		const rest = text[i..];
		if (c == '|') {
			if (len(cur.args) == 0) return die(line, "tom kommando før '|'");
			append(stages, cur)!;
			cur = stage { ... };
			i += 1;
			continue;
		};
		if (prefix(rest, "2>>")) { redirect = 4; i += 3; continue; };
		if (prefix(rest, "2>")) { redirect = 3; i += 2; continue; };
		if (prefix(rest, ">>")) { redirect = 2; i += 2; continue; };
		if (c == '>') { redirect = 1; i += 1; continue; };
		if (c == '<') { redirect = 5; i += 1; continue; };
		const (w, ni) = read_word(text, i, line)?;
		i = ni;
		switch (redirect) {
		case 0 => append(cur.args, w)!;
		case 1, 2 => cur.out = alloc(redir { target = w, app = redirect == 2 })!;
		case 3, 4 => cur.err = alloc(redir { target = w, app = redirect == 4 })!;
		case 5 => cur.inp = alloc(w)!;
		case => abort();
		};
		redirect = 0;
	};
	if (redirect != 0) return die(line, "redirect mangler et filnavn");
	if (len(cur.args) == 0) return die(line, "tom kommando");
	append(stages, cur)!;
	return stages;
};

fn prefix(b: []u8, s: str) bool = {
	const sb = strings::toutf8(s);
	if (len(b) < len(sb)) return false;
	for (let i = 0z; i < len(sb); i += 1) if (b[i] != sb[i]) return false;
	return true;
};

fn read_word(text: []u8, i: size, line: int) ((word, size) | failed) = {
	let w = word { ... };
	let buf: []u8 = [];
	for (i < len(text)) {
		const c = text[i];
		if (c == ' ' || c == '\t' || c == '\n' || c == '|' || c == '<' || c == '>') break;
		if (c == '\\') {
			if (i + 1 < len(text) && text[i + 1] == '\n') break;
			if (i + 1 < len(text)) append(buf, text[i + 1])!;
			w.quoted = true;
			i += 2;
			continue;
		};
		if (c == '"') {
			const end = scan_string(text, i, line)?;
			flush_lit(&w, &buf);
			append(w.parts, interp(text[i + 1..end - 1], line)?...)!;
			w.quoted = true;
			i = end;
			continue;
		};
		if (c == '\'') {
			let k = i + 1;
			for (k < len(text) && text[k] != '\'') k += 1;
			if (k >= len(text)) return die(line, "streng mangler afsluttende '");
			append(buf, text[i + 1..k]...)!;
			w.quoted = true;
			i = k + 1;
			continue;
		};
		if (c == '$' && i + 1 < len(text)) {
			const nx = text[i + 1];
			if (nx == '(') {
				const end = scan_balanced(text, i + 1, '(', ')', line)?;
				flush_lit(&w, &buf);
				append(w.parts, sub(text, i + 2, end - 1): p_cap)!;
				i = end;
				continue;
			};
			if (nx == '{') {
				const end = scan_balanced(text, i + 1, '{', '}', line)?;
				flush_lit(&w, &buf);
				append(w.parts, parse_expr_src(text[i + 2..end - 1], line)?: p_expr)!;
				i = end;
				continue;
			};
			if (ident_start(nx)) {
				let j = i + 1;
				for (j < len(text) && ident_char(text[j])) j += 1;
				flush_lit(&w, &buf);
				append(w.parts, sub(text, i + 1, j): p_var)!;
				i = j;
				continue;
			};
		};
		if (c == '~' && len(w.parts) == 0 && len(buf) == 0
				&& (i + 1 == len(text) || text[i + 1] == '/' || text[i + 1] == ' ')) {
			append(buf, strings::toutf8(home())...)!;
			i += 1;
			continue;
		};
		append(buf, c)!;
		i += 1;
	};
	flush_lit(&w, &buf);
	return (w, i);
};

fn flush_lit(w: *word, buf: *[]u8) void = {
	if (len(buf) == 0) return;
	append(w.parts, strings::dup(strings::fromutf8_unsafe(*buf))!: p_lit)!;
	*buf = [];
};

// The inside of a "string": text, $name and {expression}.
fn interp(raw: []u8, line: int) ([]part | failed) = {
	let parts: []part = [];
	let buf: []u8 = [];
	let i = 0z;
	for (i < len(raw)) {
		const c = raw[i];
		if (c == '\\' && i + 1 < len(raw)) {
			const e = raw[i + 1];
			append(buf, switch (e) {
			case 'n' => yield '\n';
			case 't' => yield '\t';
			case 'r' => yield '\r';
			case 'e' => yield 0x1b;
			case '0' => yield 0;
			case => yield e;
			})!;
			i += 2;
			continue;
		};
		if (c == '{') {
			const end = scan_balanced(raw, i, '{', '}', line)?;
			if (len(buf) > 0) {
				append(parts, strings::dup(strings::fromutf8_unsafe(buf))!: p_lit)!;
				buf = [];
			};
			append(parts, parse_expr_src(raw[i + 1..end - 1], line)?: p_expr)!;
			i = end;
			continue;
		};
		if (c == '$' && i + 1 < len(raw) && ident_start(raw[i + 1])) {
			let j = i + 1;
			for (j < len(raw) && ident_char(raw[j])) j += 1;
			if (len(buf) > 0) {
				append(parts, strings::dup(strings::fromutf8_unsafe(buf))!: p_lit)!;
				buf = [];
			};
			append(parts, sub(raw, i + 1, j): p_var)!;
			i = j;
			continue;
		};
		append(buf, c)!;
		i += 1;
	};
	if (len(buf) > 0) append(parts, strings::dup(strings::fromutf8_unsafe(buf))!: p_lit)!;
	return parts;
};

fn parse_expr_src(src: []u8, line: int) (*expr | failed) = {
	let p = parser { src = src, toks = lex(src, line)?, ... };
	const e = pexpr(&p)?;
	skip_seps(&p);
	if (peek(&p).kind != tkind::EOF) {
		return dief(line, "uventet {} i udtryk", desc(peek(&p)));
	};
	return e;
};

// --- expressions ---

fn mk(e: expr) *expr = alloc(e)!;

fn pexpr(p: *parser) (*expr | failed) = or_(p);

fn or_(p: *parser) (*expr | failed) = {
	let a = and_(p)?;
	for (at(p, "or") || at(p, "||")) {
		const l = next(p).line;
		a = mk(e_bin { op = "or", a = a, b = and_(p)?, line = l });
	};
	return a;
};

fn and_(p: *parser) (*expr | failed) = {
	let a = not_(p)?;
	for (at(p, "and") || at(p, "&&")) {
		const l = next(p).line;
		a = mk(e_bin { op = "and", a = a, b = not_(p)?, line = l });
	};
	return a;
};

fn not_(p: *parser) (*expr | failed) = {
	if (at(p, "not") || at(p, "!")) {
		const l = next(p).line;
		return mk(e_un { op = "not", a = not_(p)?, line = l });
	};
	return cmp(p);
};

fn isop(p: *parser, ops: str...) bool = {
	const t = peek(p);
	if (t.kind != tkind::OP) return false;
	for (let o .. ops) if (t.val == o) return true;
	return false;
};

fn cmp(p: *parser) (*expr | failed) = {
	let a = add(p)?;
	for (isop(p, "==", "!=", "<", ">", "<=", ">=")) {
		const t = next(p);
		a = mk(e_bin { op = t.val, a = a, b = add(p)?, line = t.line });
	};
	return a;
};

fn add(p: *parser) (*expr | failed) = {
	let a = mul(p)?;
	for (isop(p, "+", "-")) {
		const t = next(p);
		a = mk(e_bin { op = t.val, a = a, b = mul(p)?, line = t.line });
	};
	return a;
};

fn mul(p: *parser) (*expr | failed) = {
	let a = unary(p)?;
	for (isop(p, "*", "/", "%")) {
		const t = next(p);
		a = mk(e_bin { op = t.val, a = a, b = unary(p)?, line = t.line });
	};
	return a;
};

fn unary(p: *parser) (*expr | failed) = {
	if (at(p, "-")) {
		const l = next(p).line;
		return mk(e_un { op = "-", a = unary(p)?, line = l });
	};
	return postfix(p);
};

fn postfix(p: *parser) (*expr | failed) = {
	let e = primary(p)?;
	for (true) {
		const t = peek(p);
		if (t.kind != tkind::OP) break;
		if (t.val == ".") {
			next(p);
			const n = peek(p);
			if (n.kind != tkind::IDENT && n.kind != tkind::KW) {
				return dief(t.line, "forventede et navn efter '.', fik {}", desc(n));
			};
			next(p);
			const paren = peek(p);
			if (paren.kind == tkind::OP && paren.val == "(" && !paren.space) {
				e = mk(e_method { obj = e, name = n.val, args = call_args(p)?, line = t.line });
			} else {
				e = mk(e_attr { obj = e, name = n.val, line = t.line });
			};
		} else if (t.val == "[" && !t.space) {
			next(p);
			const idx = pexpr(p)?;
			expect(p, "]")?;
			e = mk(e_index { obj = e, idx = idx, line = t.line });
		} else {
			break;
		};
	};
	return e;
};

fn call_args(p: *parser) ([]*expr | failed) = {
	expect(p, "(")?;
	let args: []*expr = [];
	for (!at(p, ")")) {
		append(args, pexpr(p)?)!;
		if (!at(p, ")")) expect(p, ",")?;
	};
	expect(p, ")")?;
	return args;
};

fn primary(p: *parser) (*expr | failed) = {
	const t = next(p);
	switch (t.kind) {
	case tkind::NUM =>
		if (t.isf) return mk(t.fnum: e_fnum);
		return mk(t.num: e_num);
	case tkind::STR => return mk(e_str { parts = interp(strings::toutf8(t.val), t.line)?, line = t.line });
	case tkind::RSTR => return mk(e_const { v = t.val });
	case tkind::CAP => return mk(e_cap { raw = t.val, line = t.line });
	case tkind::IDENT =>
		const n = peek(p);
		if (n.kind == tkind::OP && n.val == "(" && !n.space) {
			return mk(e_call { name = t.val, args = call_args(p)?, line = t.line });
		};
		return mk(e_var { name = t.val, line = t.line });
	case tkind::KW =>
		switch (t.val) {
		case "true" => return mk(e_const { v = true });
		case "false" => return mk(e_const { v = false });
		case "nil" => return mk(e_const { v = nilv });
		case => void;
		};
	case tkind::OP =>
		if (t.val == "(") {
			const e = pexpr(p)?;
			expect(p, ")")?;
			return e;
		};
		if (t.val == "[") {
			let items: []*expr = [];
			for (!at(p, "]")) {
				append(items, pexpr(p)?)!;
				if (!at(p, "]")) expect(p, ",")?;
			};
			expect(p, "]")?;
			return mk(e_list { items = items });
		};
		if (t.val == "{") {
			let keys: []*expr = [], vals: []*expr = [];
			skip_seps(p);
			for (!at(p, "}")) {
				append(keys, pexpr(p)?)!;
				expect(p, ":")?;
				append(vals, pexpr(p)?)!;
				skip_seps(p);
				if (!at(p, "}")) {
					expect(p, ",")?;
					skip_seps(p);
				};
			};
			expect(p, "}")?;
			return mk(e_map { keys = keys, vals = vals });
		};
	case => void;
	};
	return dief(t.line, "uventet {}", desc(t));
};
