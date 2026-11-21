// Parr — Dash' formatering og udskrift, ligesom Hares fmt og Nims echo.
// (Familien Parr: Bob, Helen, Violet, Dash og Jack-Jack.)
//
//   parr.ln(a, b, …)     skriver værdierne med mellemrum og ny linje
//   parr.err(a, b, …)    det samme, men til stderr
//   parr.fmt(v, spec)    formaterer én værdi → tekst
//   parr.tabel(rækker)   skriver en liste af lister som pæne kolonner
//
// En spec står også direkte i tekst: "{pris:>8.2}" er parr.fmt(pris, ">8.2").
//
//   spec = [<>^][+][0][bredde][,][.decimaler][x X b o % s]
//     <  >  ^   venstre, højre, midt (tal står til højre, tekst til venstre)
//     +         fortegn også på positive tal
//     0         fyld op med nuller (tal)
//     ,         tusindtalsskiller: 1,234,567
//     .2        to decimaler (tekst: højst 2 tegn)
//     x X b o   hex, HEX, binær, oktal (heltal)
//     %         procent: 0.38 → 38%
//     s         som tekst
use fmt;
use math;
use strconv;
use strings;

type pspec = struct {
	al: rune,     // 0, '<', '>', '^'
	plus: bool,
	zero: bool,
	width: size,
	comma: bool,
	prec: int,       // -1 = ingen
	kind: rune,      // 0 eller en af x X b o % s
};

// Er s en gyldig spec? (bruges også af parseren til at se, om ':' er en spec)
fn parse_pspec(s: str) (pspec | void) = {
	let p = pspec { prec = -1, ... };
	const b = strings::toutf8(s);
	if (len(b) == 0) return;
	let i = 0z;
	if (b[i] == '<' || b[i] == '>' || b[i] == '^') {
		p.al = b[i]: rune;
		i += 1;
	};
	if (i < len(b) && b[i] == '+') {
		p.plus = true;
		i += 1;
	};
	if (i < len(b) && b[i] == '0') {
		p.zero = true;
		i += 1;
	};
	for (i < len(b) && b[i] >= '0' && b[i] <= '9') {
		p.width = p.width * 10 + (b[i] - '0'): size;
		i += 1;
	};
	if (i < len(b) && b[i] == ',') {
		p.comma = true;
		i += 1;
	};
	if (i < len(b) && b[i] == '.') {
		i += 1;
		if (i >= len(b) || b[i] < '0' || b[i] > '9') return;
		p.prec = 0;
		for (i < len(b) && b[i] >= '0' && b[i] <= '9') {
			p.prec = p.prec * 10 + (b[i] - '0'): int;
			i += 1;
		};
	};
	if (i < len(b)) {
		switch (b[i]) {
		case 'x', 'X', 'b', 'o', '%', 's' =>
			p.kind = b[i]: rune;
			i += 1;
		case => return;
		};
	};
	if (i != len(b)) return;
	return p;
};

fn runes(s: str) size = len(strings::torunes(s)!);

fn tusinder(digits: str) str = {
	const b = strings::toutf8(digits);
	let out: []u8 = [];
	for (let i = 0z; i < len(b); i += 1) {
		if (i > 0 && (len(b) - i) % 3 == 0) append(out, ',')!;
		append(out, b[i])!;
	};
	return strings::fromutf8_unsafe(out);
};

fn parr_fmt(v: value, spec: str, line: int) (str | failed) = {
	const p = match (parse_pspec(spec)) {
	case let p: pspec => yield p;
	case void => return dief(line, "ugyldig format-spec ':{}' (fx :8  :<12  :>8.2  :05  :x  :%)", spec);
	};
	let num = false;
	let neg = false;
	let body = "";       // uden fortegn, når det er et tal
	switch (p.kind) {
	case 'x', 'X', 'b', 'o' =>
		const i = match (v) {
		case let i: i64 => yield i;
		case let f: f64 =>
			if (f != math::floorf64(f)) return dief(line, ":{} virker kun på heltal, fik {}", spec, tostr(v));
			yield f: i64;
		case => return dief(line, ":{} virker kun på heltal, fik en {}", spec, typename(v));
		};
		num = true;
		neg = i < 0;
		const a: u64 = if (neg) (-i): u64 else i: u64;
		body = strconv::u64tos(a, switch (p.kind) {
		case 'x' => yield strconv::base::HEX_LOWER;
		case 'X' => yield strconv::base::HEX_UPPER;
		case 'b' => yield strconv::base::BIN;
		case => yield strconv::base::OCT;
		});
		body = strings::dup(body)!;
	case '%' =>
		const f = match (v) {
		case let i: i64 => yield i: f64;
		case let f: f64 => yield f;
		case => return dief(line, ":% virker kun på tal, fik en {}", typename(v));
		};
		num = true;
		const x = f * 100.0;
		neg = x < 0.0;
		const pr = if (p.prec < 0) 0u else p.prec: uint;
		body = strconv::ftosf(math::absf64(x), strconv::ffmt::F, pr)!;
		if (p.comma) {
			const dot = strings::index(body, '.');
			match (dot) {
			case let d: size =>
				body = strings::concat(tusinder(strings::sub(body, 0, d)), strings::sub(body, d, strings::end))!;
			case void => body = tusinder(body);
			};
		};
		body = strings::concat(body, "%")!;
	case 's' =>
		body = tostr(v);
	case =>
		match (v) {
		case let i: i64 =>
			num = true;
			neg = i < 0;
			if (p.prec >= 0) {
				body = strconv::ftosf(math::absf64(i: f64), strconv::ffmt::F, p.prec: uint)!;
			} else {
				const a: u64 = if (neg) (-i): u64 else i: u64;
				body = strings::dup(strconv::u64tos(a))!;
			};
		case let f: f64 =>
			num = true;
			neg = f < 0.0;
			if (p.prec >= 0) {
				body = strconv::ftosf(math::absf64(f), strconv::ffmt::F, p.prec: uint)!;
			} else {
				body = tostr(math::absf64(f));
			};
		case =>
			body = tostr(v);
		};
	};
	if (num && p.comma && p.kind != '%') {
		match (strings::index(body, '.')) {
		case let d: size =>
			body = strings::concat(tusinder(strings::sub(body, 0, d)), strings::sub(body, d, strings::end))!;
		case void => body = tusinder(body);
		};
	};
	// tekst med .n bliver højst n tegn
	if (!num && p.prec >= 0) {
		const rs = strings::torunes(body)!;
		if (len(rs) > p.prec: size) body = strings::fromrunes(rs[..p.prec])!;
	};
	const sign = if (!num) "" else if (neg) "-" else if (p.plus) "+" else "";

	const n = runes(sign) + runes(body);
	if (n >= p.width) return strings::concat(sign, body)!;
	const fill = p.width - n;
	if (p.zero && num && p.al == '\0') {
		return strings::concat(sign, strings::rpad("", '0', fill)!, body)!;
	};
	const al = if (p.al != '\0') p.al else if (num) '>' else '<';
	const s = strings::concat(sign, body)!;
	switch (al) {
	case '<' => return strings::concat(s, strings::rpad("", ' ', fill)!)!;
	case '>' => return strings::concat(strings::rpad("", ' ', fill)!, s)!;
	case =>
		const l = fill / 2;
		return strings::concat(strings::rpad("", ' ', l)!, s, strings::rpad("", ' ', fill - l)!)!;
	};
};

fn parr_line(args: []value) str = {
	let parts: []str = [];
	for (let a .. args) append(parts, tostr(a))!;
	return strings::join(" ", parts...)!;
};

fn parr_tabel(args: []value, line: int) (value | failed) = {
	need("parr.tabel", args, 1, line)?;
	const rows = match (args[0]) {
	case let l: *list => yield l.items;
	case => return dief(line, "parr.tabel() vil have en liste af rækker, fik en {}", typename(args[0]));
	};
	let celler: [][]str = [];
	let tal: [][]bool = [];
	let bredder: []size = [];
	for (let r .. rows) {
		let cs: []str = [];
		let ts: []bool = [];
		const items: []value = match (r) {
		case let l: *list => yield l.items;
		case => yield [r];
		};
		for (let c .. items) {
			append(cs, tostr(c))!;
			append(ts, c is i64 || c is f64)!;
		};
		for (let i = 0z; i < len(cs); i += 1) {
			if (i >= len(bredder)) append(bredder, 0)!;
			const w = runes(cs[i]);
			if (w > bredder[i]) bredder[i] = w;
		};
		append(celler, cs)!;
		append(tal, ts)!;
	};
	// en kolonne med lutter tal (under overskriften) står helt til højre
	let talkol: []bool = [];
	for (let i = 0z; i < len(bredder); i += 1) {
		let alle = len(celler) > 1;
		for (let r = 1z; r < len(celler); r += 1) {
			if (i < len(tal[r]) && !tal[r][i]) alle = false;
		};
		append(talkol, alle)!;
	};
	for (let r = 0z; r < len(celler); r += 1) {
		let out: []str = [];
		for (let i = 0z; i < len(celler[r]); i += 1) {
			const s = celler[r][i];
			const fill = bredder[i] - runes(s);
			const pad = strings::rpad("", ' ', fill)!;
			const sidst = i + 1 == len(celler[r]);
			if (tal[r][i] || talkol[i]) {
				append(out, strings::concat(pad, s)!)!;
			} else if (sidst) {
				append(out, s)!;
			} else {
				append(out, strings::concat(s, pad)!)!;
			};
		};
		fmt::println(strings::join("  ", out...)!)!;
	};
	return nilv;
};

// parr.* — kaldes fra call() i builtins.ha
fn parr_call(name: str, args: []value, line: int) (value | failed) = {
	switch (name) {
	case "parr.ln" =>
		fmt::println(parr_line(args))!;
		return nilv;
	case "parr.err" =>
		fmt::errorln(parr_line(args))!;
		return nilv;
	case "parr.fmt" =>
		need(name, args, 2, line)?;
		return parr_fmt(args[0], str_arg(name, args[1], line)?, line)?;
	case "parr.tabel" =>
		return parr_tabel(args, line)?;
	case => return dief(line, "ukendt funktion '{}()' — Parr kan ln, err, fmt og tabel", name);
	};
};
