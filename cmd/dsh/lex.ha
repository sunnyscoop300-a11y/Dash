// Turns .Dash source into tokens.
use ascii;
use strconv;
use strings;

type tkind = enum {
	NL,
	NUM,
	STR,      // "..." (raw contents, interpolated later)
	RSTR,     // '...'
	CAP,      // $( ... )
	JOB,      // &( ... ) — en kommando i baggrunden
	IDENT,
	KW,
	OP,
	EOF,
};

type token = struct {
	kind: tkind,
	val: str,
	num: i64,
	fnum: f64,
	isf: bool,
	line: int,
	pos: size,
	space: bool,    // whitespace before the token
};

const KEYWORDS: [_]str = ["let", "if", "else", "for", "in", "while", "echo",
	"fail", "try", "parallel", "true", "false", "nil", "and", "or", "not",
	"break", "continue", "fn", "return"];

fn iskw(s: str) bool = {
	for (let k .. KEYWORDS) if (k == s) return true;
	return false;
};

fn ident_start(c: u8) bool = ascii::isalpha(c: rune) || c == '_' || c >= 0x80;
fn ident_char(c: u8) bool = ident_start(c) || ascii::isdigit(c: rune);

fn sub(src: []u8, a: size, b: size) str = strings::fromutf8_unsafe(src[a..b]);

// src[i] == '"'. Returns the index after the closing quote. Handles {..}
// with strings inside.
fn scan_string(src: []u8, i: size, line: int) (size | failed) = {
	let j = i + 1;
	for (j < len(src)) {
		const c = src[j];
		if (c == '\\') { j += 2; continue; };
		if (c == '"') return j + 1;
		if (c == '{') { j = scan_balanced(src, j, '{', '}', line)?; continue; };
		if (c == '\n') break;
		j += 1;
	};
	return dieh(line, "streng mangler afsluttende \"", HINT_SPLIT);
};

// src[i] == open. Returns the index after the matching close.
fn scan_balanced(src: []u8, i: size, open: u8, close: u8, line: int) (size | failed) = {
	let depth = 0, j = i;
	for (j < len(src)) {
		const c = src[j];
		if (c == '\\') { j += 2; continue; };
		if (c == '"') { j = scan_string(src, j, line)?; continue; };
		if (c == '\'' && open != '{') {
			let k = j + 1;
			for (k < len(src) && src[k] != '\'') k += 1;
			if (k >= len(src)) return die(line, "streng mangler afsluttende '");
			j = k + 1;
			continue;
		};
		if (c == open) {
			depth += 1;
		} else if (c == close) {
			depth -= 1;
			if (depth == 0) return j + 1;
		};
		j += 1;
	};
	return dief(line, "mangler '{}'", close: rune);
};

const TWO: [_]str = ["==", "!=", "<=", ">=", "+=", "-=", "*=", "/=", "&&", "||", ">>"];

fn lex(src: []u8, line: int) ([]token | failed) = {
	let toks: []token = [];
	let i = 0z, depth = 0, space = true;
	for (i < len(src)) {
		const c = src[i];
		if (c == ' ' || c == '\t' || c == '\r') {
			i += 1; space = true; continue;
		};
		if (c == '\\' && i + 1 < len(src) && src[i + 1] == '\n') {
			i += 2; line += 1; space = true; continue;
		};
		if (c == '#' && space) {
			for (i < len(src) && src[i] != '\n') i += 1;
			continue;
		};
		if (c == '\n') {
			if (depth == 0) append(toks, token { kind = tkind::NL, val = "\n", line = line, pos = i, space = space, ... })!;
			line += 1; i += 1; space = true;
			continue;
		};
		const start = i;
		let t = token { line = line, pos = start, space = space, ... };
		if (ascii::isdigit(c: rune)) {
			for (i < len(src) && ascii::isdigit(src[i]: rune)) i += 1;
			t.kind = tkind::NUM;
			if (i + 1 < len(src) && src[i] == '.' && ascii::isdigit(src[i + 1]: rune)) {
				i += 1;
				for (i < len(src) && ascii::isdigit(src[i]: rune)) i += 1;
				t.val = sub(src, start, i);
				t.isf = true;
				t.fnum = match (strconv::stof64(t.val)) {
				case let f: f64 => yield f;
				case => return die(line, "ugyldigt kommatal");
				};
			} else {
				t.val = sub(src, start, i);
				t.num = match (strconv::stoi64(t.val)) {
				case let n: i64 => yield n;
				case => return die(line, "tallet er for stort");
				};
			};
		} else if (c == '"') {
			match (scan_string(src, i, line)) {
			case let end: size =>
				i = end;
				t.kind = tkind::STR;
				t.val = sub(src, start + 1, i - 1);
			case failed =>
				if (!checking) return failed;
				// dsh check: note it and carry on after the line
				record();
				for (i < len(src) && src[i] != '\n') i += 1;
				depth = 0;    // brackets opened on a broken line don't count
				t.kind = tkind::STR;
				t.val = "";
			};
		} else if (c == '\'') {
			let k = i + 1;
			for (k < len(src) && src[k] != '\'' && src[k] != '\n') k += 1;
			if (k < len(src) && src[k] == '\'') {
				t.kind = tkind::RSTR;
				t.val = sub(src, i + 1, k);
				i = k + 1;
			} else {
				t.kind = tkind::OP;
				t.val = "'";
				i += 1;
			};
		} else if (c == '$' && i + 1 < len(src) && src[i + 1] == '(') {
			const end = scan_balanced(src, i + 1, '(', ')', line)?;
			t.kind = tkind::CAP;
			t.val = sub(src, i + 2, end - 1);
			i = end;
		} else if (c == '&' && i + 1 < len(src) && src[i + 1] == '(') {
			const end = scan_balanced(src, i + 1, '(', ')', line)?;
			t.kind = tkind::JOB;
			t.val = sub(src, i + 2, end - 1);
			i = end;
		} else if (c == '$' && i + 1 < len(src) && ident_start(src[i + 1])) {
			let j = i + 1;
			for (j < len(src) && ident_char(src[j])) j += 1;
			t.kind = tkind::IDENT;
			t.val = sub(src, i + 1, j);
			i = j;
		} else if (ident_start(c)) {
			let j = i;
			for (j < len(src) && ident_char(src[j])) j += 1;
			t.val = sub(src, i, j);
			t.kind = if (iskw(t.val)) tkind::KW else tkind::IDENT;
			i = j;
		} else {
			t.kind = tkind::OP;
			let two = false;
			if (i + 1 < len(src)) {
				const s2 = sub(src, i, i + 2);
				for (let k .. TWO) if (k == s2) two = true;
			};
			if (two) {
				t.val = sub(src, i, i + 2);
				i += 2;
			} else {
				if (c == '(' || c == '[') depth += 1;
				if ((c == ')' || c == ']') && depth > 0) depth -= 1;
				t.val = sub(src, i, i + 1);
				i += 1;
			};
		};
		append(toks, t)!;
		space = false;
	};
	append(toks, token { kind = tkind::EOF, line = line, pos = len(src), space = true, ... })!;
	return toks;
};
