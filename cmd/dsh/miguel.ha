// Miguel 🎸 — Dash' language server (LSP). Han spiller med i editoren:
// fejl og advarsler fra dsh check mens du skriver, autoudfyldning af
// nøgleord, funktioner, metoder og dine egne navne, og en lille forklaring,
// når musen står over en funktion.
//
//   dsh miguel        (eller "miguel", et symlink til dsh)
//
// Taler JSON-RPC over stdin/stdout som alle LSP-servere.
use ascii;
use bufio;
use encoding::utf8;
use fmt;
use io;
use os;
use strconv;
use strings;

// ── en lille JSON-læser ──

type jnull = struct { z: u8 };
type jobj = struct { keys: []str, vals: []jval };
type jval = (jobj | []jval | str | f64 | bool | jnull);
type jerr = !void;

type jparser = struct { s: []u8, i: size };

fn jws(p: *jparser) void = {
	for (p.i < len(p.s) && (p.s[p.i] == ' ' || p.s[p.i] == '\n'
			|| p.s[p.i] == '\r' || p.s[p.i] == '\t')) p.i += 1;
};

fn jhex(p: *jparser) (u32 | jerr) = {
	if (p.i + 4 > len(p.s)) return jerr;
	let v = 0u32;
	for (let k = 0z; k < 4; k += 1) {
		const c = p.s[p.i + k];
		v <<= 4;
		if (c >= '0' && c <= '9') v |= (c - '0'): u32
		else if (c >= 'a' && c <= 'f') v |= (c - 'a' + 10): u32
		else if (c >= 'A' && c <= 'F') v |= (c - 'A' + 10): u32
		else return jerr;
	};
	p.i += 4;
	return v;
};

fn jstring(p: *jparser) (str | jerr) = {
	p.i += 1;    // "
	let out: []u8 = [];
	for (true) {
		if (p.i >= len(p.s)) return jerr;
		const c = p.s[p.i];
		p.i += 1;
		if (c == '"') break;
		if (c != '\\') {
			append(out, c)!;
			continue;
		};
		if (p.i >= len(p.s)) return jerr;
		const e = p.s[p.i];
		p.i += 1;
		switch (e) {
		case 'n' => append(out, '\n')!;
		case 't' => append(out, '\t')!;
		case 'r' => append(out, '\r')!;
		case 'b' => append(out, 8)!;
		case 'f' => append(out, 12)!;
		case 'u' =>
			let r = jhex(p)?;
			if (r >= 0xD800 && r <= 0xDBFF && p.i + 6 <= len(p.s)
					&& p.s[p.i] == '\\' && p.s[p.i + 1] == 'u') {
				p.i += 2;
				const lo = jhex(p)?;
				r = 0x10000 + ((r - 0xD800) << 10) + (lo - 0xDC00);
			};
			if (r >= 0xD800 && r <= 0xDFFF) r = 0xFFFD;
			append(out, utf8::encoderune(r: rune)...)!;
		case => append(out, e)!;
		};
	};
	return strings::fromutf8_unsafe(out);
};

fn jvalue(p: *jparser) (jval | jerr) = {
	jws(p);
	if (p.i >= len(p.s)) return jerr;
	const c = p.s[p.i];
	if (c == '{') {
		p.i += 1;
		let o = jobj { ... };
		jws(p);
		if (p.i < len(p.s) && p.s[p.i] == '}') {
			p.i += 1;
			return o;
		};
		for (true) {
			jws(p);
			if (p.i >= len(p.s) || p.s[p.i] != '"') return jerr;
			const k = jstring(p)?;
			jws(p);
			if (p.i >= len(p.s) || p.s[p.i] != ':') return jerr;
			p.i += 1;
			const v = jvalue(p)?;
			append(o.keys, k)!;
			append(o.vals, v)!;
			jws(p);
			if (p.i >= len(p.s)) return jerr;
			if (p.s[p.i] == ',') {
				p.i += 1;
				continue;
			};
			if (p.s[p.i] == '}') {
				p.i += 1;
				return o;
			};
			return jerr;
		};
	};
	if (c == '[') {
		p.i += 1;
		let a: []jval = [];
		jws(p);
		if (p.i < len(p.s) && p.s[p.i] == ']') {
			p.i += 1;
			return a;
		};
		for (true) {
			append(a, jvalue(p)?)!;
			jws(p);
			if (p.i >= len(p.s)) return jerr;
			if (p.s[p.i] == ',') {
				p.i += 1;
				continue;
			};
			if (p.s[p.i] == ']') {
				p.i += 1;
				return a;
			};
			return jerr;
		};
	};
	if (c == '"') return jstring(p)?;
	if (c == 't' && p.i + 4 <= len(p.s)) {
		p.i += 4;
		return true;
	};
	if (c == 'f' && p.i + 5 <= len(p.s)) {
		p.i += 5;
		return false;
	};
	if (c == 'n' && p.i + 4 <= len(p.s)) {
		p.i += 4;
		return jnull { ... };
	};
	const start = p.i;
	for (p.i < len(p.s) && (ascii::isdigit(p.s[p.i]: rune) || p.s[p.i] == '-'
			|| p.s[p.i] == '+' || p.s[p.i] == '.' || p.s[p.i] == 'e'
			|| p.s[p.i] == 'E')) p.i += 1;
	if (p.i == start) return jerr;
	match (strconv::stof64(strings::fromutf8_unsafe(p.s[start..p.i]))) {
	case let f: f64 => return f;
	case => return jerr;
	};
};

// felt i et objekt, eller nil
fn jget(v: jval, key: str) (jval | void) = {
	match (v) {
	case let o: jobj =>
		for (let i = 0z; i < len(o.keys); i += 1) {
			if (o.keys[i] == key) return o.vals[i];
		};
	case => void;
	};
};

fn jpath(v: jval, keys: str...) (jval | void) = {
	let cur = v;
	for (let k .. keys) {
		match (jget(cur, k)) {
		case let n: jval => cur = n;
		case void => return;
		};
	};
	return cur;
};

fn jstr(v: (jval | void)) str = match (v) {
case let s: str => yield s;
case => yield "";
};

fn jnum(v: (jval | void)) int = match (v) {
case let f: f64 => yield f: int;
case => yield -1;
};

// id'et skrives tilbage, som det kom (tal eller streng)
fn jid(v: (jval | void)) str = match (v) {
case let f: f64 => yield fmt::asprintf("{}", f: i64)!;
case let s: str => yield jq(s);
case => yield "null";
};

// ── JSON ud ──

fn jq(s: str) str = {
	let out: []u8 = [];
	append(out, '"')!;
	for (let c .. strings::toutf8(s)) {
		switch (c) {
		case '"' => append(out, ['\\', '"']...)!;
		case '\\' => append(out, ['\\', '\\']...)!;
		case '\n' => append(out, ['\\', 'n']...)!;
		case '\r' => append(out, ['\\', 'r']...)!;
		case '\t' => append(out, ['\\', 't']...)!;
		case =>
			if (c < 0x20) {
				append(out, strings::toutf8(fmt::asprintf("\\u{:04x}", c)!)...)!;
			} else {
				append(out, c)!;
			};
		};
	};
	append(out, '"')!;
	return strings::fromutf8_unsafe(out);
};

fn send(body: str) void = {
	const b = strings::toutf8(body);
	fmt::fprintf(os::stdout, "Content-Length: {}\r\n\r\n", len(b))!;
	io::writeall(os::stdout, b)!;
	match (bufio::flush(os::stdout)) { case => void; };
};

fn reply(id: str, result: str) void = {
	send(fmt::asprintf("{{\"jsonrpc\":\"2.0\",\"id\":{},\"result\":{}}}", id, result)!);
};

// ── beskeder ind: "Content-Length: N\r\n\r\n" + N bytes ──

let inbuf: []u8 = [];
let inpos: size = 0;

fn fill() bool = {
	if (inpos > 0) {
		delete(inbuf[..inpos]);
		inpos = 0;
	};
	let buf: [65536]u8 = [0...];
	match (io::read(os::stdin, buf)) {
	case let n: size =>
		append(inbuf, buf[..n]...)!;
		return true;
	case => return false;
	};
};

fn read_line() (str | void) = {
	for (true) {
		for (let i = inpos; i < len(inbuf); i += 1) {
			if (inbuf[i] == '\n') {
				let end = i;
				if (end > inpos && inbuf[end - 1] == '\r') end -= 1;
				const l = strings::dup(strings::fromutf8_unsafe(inbuf[inpos..end]))!;
				inpos = i + 1;
				return l;
			};
		};
		if (!fill()) return;
	};
};

fn read_msg() ([]u8 | void) = {
	let n = 0z;
	for (true) {
		const l = match (read_line()) {
		case let l: str => yield l;
		case void => return;
		};
		if (l == "") {
			if (n > 0) break;
			continue;
		};
		const low = ascii::strlower(l)!;
		if (strings::hasprefix(low, "content-length:")) {
			match (strconv::stoz(strings::trim(strings::sub(l, 15, strings::end)))) {
			case let z: size => n = z;
			case => void;
			};
		};
	};
	for (len(inbuf) - inpos < n) if (!fill()) return;
	let body: []u8 = [];
	append(body, inbuf[inpos..inpos + n]...)!;
	inpos += n;
	return body;
};

// ── dokumenterne, editoren har åbne ──

type dok = struct { uri: str, text: str };
let doks: []dok = [];

fn dok_set(uri: str, text: str) void = {
	for (let i = 0z; i < len(doks); i += 1) {
		if (doks[i].uri == uri) {
			doks[i].text = text;
			return;
		};
	};
	append(doks, dok { uri = uri, text = text })!;
};

fn dok_get(uri: str) str = {
	for (let d .. doks) if (d.uri == uri) return d.text;
	return "";
};

fn dok_close(uri: str) void = {
	for (let i = 0z; i < len(doks); i += 1) {
		if (doks[i].uri == uri) {
			delete(doks[i]);
			return;
		};
	};
};

// linje nr. n (1, 2, …) som bytes
fn linje(text: str, n: int) []u8 = {
	const b = strings::toutf8(text);
	let cur = 1, start = 0z;
	for (let i = 0z; i <= len(b); i += 1) {
		if (i == len(b) || b[i] == '\n') {
			if (cur == n) {
				let end = i;
				if (end > start && b[end - 1] == '\r') end -= 1;
				return b[start..end];
			};
			cur += 1;
			start = i + 1;
		};
	};
	return [];
};

// LSP tæller tegn i UTF-16; æ, ø og å er ét tegn, men to bytes
fn utf16_len(b: []u8) size = {
	let n = 0z;
	for (let c .. b) {
		if (c & 0xC0 == 0x80) continue;
		n += if (c >= 0xF0) 2 else 1;
	};
	return n;
};

fn byte_at(b: []u8, ch: size) size = {
	let n = 0z;
	for (let i = 0z; i < len(b); i += 1) {
		if (b[i] & 0xC0 == 0x80) continue;
		if (n >= ch) return i;
		n += if (b[i] >= 0xF0) 2 else 1;
	};
	return len(b);
};

// file:///home/x/a%20b.Dash → /home/x/a b.Dash
fn uri_sti(uri: str) str = {
	if (!strings::hasprefix(uri, "file://")) return uri;
	const b = strings::toutf8(strings::sub(uri, 7, strings::end));
	let out: []u8 = [];
	for (let i = 0z; i < len(b); i += 1) {
		if (b[i] == '%' && i + 2 < len(b)) {
			match (strconv::stou8(strings::fromutf8_unsafe(b[i + 1..i + 3]), strconv::base::HEX)) {
			case let v: u8 =>
				append(out, v)!;
				i += 2;
				continue;
			case => void;
			};
		};
		append(out, b[i])!;
	};
	return strings::fromutf8_unsafe(out);
};

// ── fejl og advarsler: dsh check på teksten i editoren ──

fn diagnose(uri: str) void = {
	const text = dok_get(uri);
	script_src = strings::toutf8(text);
	script_name = uri_sti(uri);    // så import "…" findes ved siden af filen
	check_collect(script_src);
	let items: []str = [];
	const lister = [problems, warnings];
	for (let k = 0z; k < 2; k += 1) {
		for (let pr .. lister[k]) {
			let pr = pr;
			// fejl i en importeret fil vises på import-linjen
			if (pr.line >= KILDE_LINJER) {
				const (fil, n) = kilde_sted(pr.line);
				const kn = pr.line / KILDE_LINJER;
				pr.msg = fmt::asprintf("i {} (linje {}): {}", fil, n, pr.msg)!;
				pr.line = kilder[kn - 1].linje;
				for (pr.line >= KILDE_LINJER) pr.line = kilder[pr.line / KILDE_LINJER - 1].linje;
			};
			const l = linje(text, pr.line);
			// fra første tegn, der ikke er mellemrum, til linjens ende
			let s = 0z;
			for (s < len(l) && (l[s] == ' ' || l[s] == '\t')) s += 1;
			let msg = pr.msg;
			if (len(pr.hint) > 0) msg = strings::concat(msg, "\n↳ ", pr.hint)!;
			const ln = if (pr.line > 0) pr.line - 1 else 0;
			append(items, fmt::asprintf("{{\"range\":{{\"start\":{{\"line\":{},\"character\":{}}},\"end\":{{\"line\":{},\"character\":{}}}}},\"severity\":{},\"source\":\"miguel\",\"message\":{}}}",
				ln, utf16_len(l[..s]), ln, utf16_len(l),
				if (k == 0) 1 else 2, jq(msg))!)!;
		};
	};
	send(fmt::asprintf("{{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{{\"uri\":{},\"diagnostics\":[{}]}}}}",
		jq(uri), strings::join(",", items...)!)!);
};

// ── autoudfyldning ──

const METODER: [_]str = ["replace", "split", "trim", "upper", "lower", "contains",
	"starts_with", "ends_with", "lines", "repeat", "push", "pop", "join", "sort",
	"reverse", "map", "filter", "get", "has", "remove"];
const EGENSKABER: [_]str = ["len", "first", "last", "name", "stem", "ext", "dir",
	"keys", "values", "chars"];
const PARR: [_]str = ["ln", "err", "fmt", "tabel"];

// kind: 3 funktion, 2 metode, 10 egenskab, 14 nøgleord, 6 variabel
fn item(label: str, kind: int, detail: str) str = {
	if (detail == "") {
		return fmt::asprintf("{{\"label\":{},\"kind\":{}}}", jq(label), kind)!;
	};
	return fmt::asprintf("{{\"label\":{},\"kind\":{},\"detail\":{}}}", jq(label), kind, jq(detail))!;
};

fn er_navn(c: u8) bool = ascii::isalnum(c: rune) || c == '_' || c >= 0x80;

// dine egne navne: let x, fn f(, for x in
fn egne_navne(text: str, vars: *[]str, fns: *[]str) void = {
	const b = strings::toutf8(text);
	let i = 0z;
	for (i < len(b)) {
		// ord-start
		if (!er_navn(b[i]) || (i > 0 && er_navn(b[i - 1]))) {
			i += 1;
			continue;
		};
		let j = i;
		for (j < len(b) && er_navn(b[j])) j += 1;
		const ord = strings::fromutf8_unsafe(b[i..j]);
		if (ord == "let" || ord == "fn" || ord == "for") {
			let k = j;
			for (k < len(b) && b[k] == ' ') k += 1;
			let m = k;
			for (m < len(b) && er_navn(b[m])) m += 1;
			if (m > k) {
				const navn = strings::fromutf8_unsafe(b[k..m]);
				const liste = if (ord == "fn") fns else vars;
				if (!has(*liste, navn)) append(liste, navn)!;
			};
		};
		i = j;
	};
};

fn complete(id: str, uri: str, line: int, ch: int) void = {
	const text = dok_get(uri);
	const l = linje(text, line + 1);
	const pos = byte_at(l, ch: size);
	// ordet lige foer markøren, og tegnet foer det
	let s = pos;
	for (s > 0 && er_navn(l[s - 1])) s -= 1;
	const foer = if (s > 0) l[s - 1] else ' ';
	let items: []str = [];
	if (foer == '.') {
		let o = s - 1;
		for (o > 0 && er_navn(l[o - 1])) o -= 1;
		if (strings::fromutf8_unsafe(l[o..s - 1]) == "parr") {
			for (let p .. PARR) append(items, item(p, 3, hover_tekst(strings::concat("parr.", p)!)))!;
		} else {
			for (let m .. METODER) append(items, item(m, 2, ""))!;
			for (let e .. EGENSKABER) append(items, item(e, 10, ""))!;
		};
	} else {
		for (let k .. KEYWORDS) append(items, item(k, 14, ""))!;
		append(items, item("match", 14, "match x { 1, 2 => … \n _ => … }"))!;
		append(items, item("import", 14, "import \"fil.Dash\" — fn'er fra en anden fil"))!;
		for (let f .. BUILTIN_FNS) {
			if (strings::hasprefix(f, "parr.")) continue;
			append(items, item(f, 3, hover_tekst(f)))!;
		};
		append(items, item("parr", 9, "Parr 🦸 — parr.ln, parr.err, parr.fmt, parr.tabel"))!;
		for (let f .. JJ_FNS) append(items, item(f, 3, hover_tekst(f)))!;
		let vars: []str = [], fns: []str = [];
		append(vars, ["args", "script", "status"]...)!;
		egne_navne(text, &vars, &fns);
		for (let v .. vars) append(items, item(v, 6, "variabel"))!;
		for (let f .. fns) append(items, item(f, 3, "din funktion"))!;
	};
	reply(id, fmt::asprintf("{{\"isIncomplete\":false,\"items\":[{}]}}",
		strings::join(",", items...)!)!);
};

// ── forklaringer, når musen står over et navn ──

const HJAELP: [_](str, str) = [
	("print", "print(a, b, …) — skriver værdierne med mellemrum"),
	("len", "len(x) — længden af en tekst, liste eller map"),
	("str", "str(x) — gør x til tekst"),
	("int", "int(x) — gør x til et heltal"),
	("float", "float(x) — gør x til et kommatal"),
	("type", "type(x) — typen som tekst: \"str\", \"int\", \"list\" …"),
	("range", "range(n) / range(a, b [, trin]) — tallene fra a til b-1"),
	("env", "env(navn [, standard]) — en miljøvariabel, eller nil/standard"),
	("exists", "exists(sti) — findes filen eller mappen?"),
	("is_dir", "is_dir(sti) — er det en mappe?"),
	("is_file", "is_file(sti) — er det en fil?"),
	("which", "which(navn) — stien til en kommando, eller nil"),
	("read", "read(sti) — hele filen som tekst"),
	("write", "write(sti, tekst) — skriver filen (overskriver)"),
	("append", "append(sti, tekst) — skriver i slutningen af filen"),
	("glob", "glob(\"*.flac\") — filerne der passer, som en liste"),
	("input", "input([spørgsmål]) — læser en linje fra tastaturet"),
	("now", "now() — sekunder siden 1970 (kommatal)"),
	("sleep", "sleep(sek) — vent"),
	("round", "round(x [, decimaler])"),
	("min", "min(a, b) / min(liste)"),
	("max", "max(a, b) / max(liste)"),
	("abs", "abs(x) — talværdien"),
	("cwd", "cwd() — mappen, scriptet står i lige nu"),
	("ask", "ask(spørgsmål [, standard]) → true/false (Enter = standard)"),
	("menu", "menu(liste [, titel]) → det valgte, eller nil"),
	("progress", "progress(pct [, tekst]) — en bjælke på samme linje"),
	("wait", "wait(job) — vent på et &( )-job; giver exitkoden"),
	("running", "running(job) — kører &( )-jobbet stadig?"),
	("kill", "kill(job [, \"STOP\"|\"CONT\"|\"TERM\"]) — stop eller pause et job"),
	("sin", "sin(x) — x i radianer"),
	("cos", "cos(x) — x i radianer"),
	("sqrt", "sqrt(x) — kvadratroden"),
	("floor", "floor(x) — rund ned"),
	("random", "random() 0-1, random(n) 0..n-1, random(a, b) a..b"),
	("parr.ln", "parr.ln(a, b, …) — skriver alle værdier med mellemrum"),
	("parr.err", "parr.err(a, b, …) — som parr.ln, men til stderr"),
	("parr.fmt", "parr.fmt(x, spec) — formaterer x, fx parr.fmt(3.14159, \".2\")"),
	("parr.tabel", "parr.tabel(rækker) — en pæn tabel; tal står til højre"),
	("window", "window(titel, bredde, højde) — åbner JJGui-vinduet"),
	("frame", "frame() — næste billede; false når vinduet lukkes"),
	("clear", "clear(farve) — fylder vinduet"),
	("rect", "rect(x, y, b, h, farve) — fyldt firkant"),
	("outline", "outline(x, y, b, h, farve) — firkant-kant"),
	("round_rect", "round_rect(x, y, b, h, r, farve) — runde hjørner"),
	("circle", "circle(x, y, r, farve)"),
	("line", "line(x0, y0, x1, y1, farve)"),
	("pixel", "pixel(x, y, farve)"),
	("polygon", "polygon([[x, y], …], farve) — fyldt mangekant"),
	("text", "text(x, y, tekst, farve, størrelse) — 8×16-skrift"),
	("text_width", "text_width(tekst, størrelse) — bredden i pixels"),
	("button", "button(tekst, x, y) — true når den klikkes"),
	("mouse", "mouse() → [x, y]"),
	("clicked", "clicked() — venstreklik i dette billede"),
	("right_clicked", "right_clicked() — højreklik i dette billede"),
	("mouse_down", "mouse_down() — holdes venstre knap nede?"),
	("wheel", "wheel() — scrollhjulet: +1 / -1 / 0"),
	("key", "key(navn) — holdes tasten nede? \"left\", \"space\", \"a\" …"),
	("pressed", "pressed(navn) — blev tasten lige trykket?"),
	("typed", "typed() — de tegn, der er skrevet i dette billede"),
	("delta", "delta() — sekunder siden sidste billede"),
	("width", "width() — vinduets bredde"),
	("height", "height() — vinduets højde"),
	("image", "image(sti [, b, h]) → billed-nr. (PNG)"),
	("draw", "draw(nr, x, y [, b, h]) — tegner et billede"),
	("image_size", "image_size(nr) → [b, h]"),
	("free_image", "free_image(nr) — giver billedets hukommelse tilbage"),
	("window_icon", "window_icon(sti.png) — vinduets ikon"),
	("textbox", "textbox(navn, x, y, bredde [, {valg}]) → teksten i feltet"),
	("focused", "focused(navn) — har tekstfeltet fokus?"),
	("submitted", "submitted(navn) — blev der trykket Enter i feltet?"),
	("textbox_set", "textbox_set(navn, tekst [, fokus])"),
	("clipboard", "clipboard() — teksten i udklipsholderen"),
	("set_clipboard", "set_clipboard(tekst)"),
	("sound", "sound(bølge, fra-Hz, til-Hz, sek [, styrke]) → lyd-nr."),
	("sound_file", "sound_file(sti.wav) → lyd-nr."),
	("play", "play(nr [, styrke, tonehøjde])"),
	("screenshot", "screenshot(sti.png) — gem billedet"),
	("close_window", "close_window() — lukker vinduet"),
	("camera", "camera(x, y, z, hældning° [, drejning°, synsvinkel°])"),
	("fog", "fog(farve, fra, til) — tåge; fog() slår den fra"),
	("box3d", "box3d(x, y, z, b, h, d, farve)"),
	("floor3d", "floor3d(x0, y, x1, z1, z0, farve [, lag])"),
	("circle3d", "circle3d(x, y, z, r, farve [, tekst])"),
	("project", "project(x, y, z) → [skærm-x, skærm-y, skala] eller nil"),
	("render3d", "render3d() — tegner 3D-scenen"),
	("let", "let navn = værdi — en ny variabel"),
	("fn", "fn navn(a, b) { … return … } — skal stå foer den bruges"),
	("for", "for x in liste [parallel N] { … }"),
	("try", "try kommando — må fejle; $status har exitkoden"),
	("fail", "fail \"besked\" — stop scriptet med en fejl"),
	("parallel", "for … in … parallel N — N løbere ad gangen"),
	("match", "match x { 1, 2 => … \n \"a\" => { … } \n _ => … } — vælg en gren efter værdien"),
	("import", "import \"fil.Dash\" — tag fn'er og variabler med fra en anden .Dash-fil"),
];

fn hover_tekst(navn: str) str = {
	for (let h .. HJAELP) if (h.0 == navn) return h.1;
	return "";
};

fn hover(id: str, uri: str, line: int, ch: int) void = {
	const l = linje(dok_get(uri), line + 1);
	const pos = byte_at(l, ch: size);
	let s = pos, e = pos;
	for (s > 0 && er_navn(l[s - 1])) s -= 1;
	for (e < len(l) && er_navn(l[e])) e += 1;
	let navn = strings::fromutf8_unsafe(l[s..e]);
	// parr.ln: tag "parr." med
	if (s >= 5 && strings::fromutf8_unsafe(l[s - 5..s]) == "parr.") {
		navn = strings::concat("parr.", navn)!;
	};
	const t = hover_tekst(navn);
	if (t == "") {
		reply(id, "null");
		return;
	};
	reply(id, fmt::asprintf("{{\"contents\":{{\"kind\":\"markdown\",\"value\":{}}}}}",
		jq(strings::concat("```\n", t, "\n```")!))!);
};

// ── hovedløkken ──

fn miguel_main() never = {
	let lukket = false;
	for (true) {
		const body = match (read_msg()) {
		case let b: []u8 => yield b;
		case void => os::exit(if (lukket) 0 else 1);
		};
		let p = jparser { s = body, ... };
		const msg = match (jvalue(&p)) {
		case let v: jval => yield v;
		case jerr => continue;
		};
		const method = jstr(jget(msg, "method"));
		const idv = jget(msg, "id");
		const id = jid(idv);
		const params = match (jget(msg, "params")) {
		case let v: jval => yield v;
		case void => yield jobj { ... }: jval;
		};
		const uri = jstr(jpath(params, "textDocument", "uri"));
		switch (method) {
		case "initialize" =>
			reply(id, "{\"capabilities\":{\"textDocumentSync\":{\"openClose\":true,\"change\":1,\"save\":true},\"completionProvider\":{\"triggerCharacters\":[\".\"]},\"hoverProvider\":true},\"serverInfo\":{\"name\":\"miguel\",\"version\":\"0.14.0\"}}");
		case "textDocument/didOpen" =>
			dok_set(uri, jstr(jpath(params, "textDocument", "text")));
			diagnose(uri);
		case "textDocument/didChange" =>
			match (jget(params, "contentChanges")) {
			case let v: jval =>
				match (v) {
				case let a: []jval =>
					if (len(a) > 0) dok_set(uri, jstr(jget(a[len(a) - 1], "text")));
				case => void;
				};
			case void => void;
			};
			diagnose(uri);
		case "textDocument/didSave" =>
			const t = jstr(jget(params, "text"));
			if (t != "") dok_set(uri, t);
			diagnose(uri);
		case "textDocument/didClose" =>
			dok_close(uri);
			send(fmt::asprintf("{{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{{\"uri\":{},\"diagnostics\":[]}}}}", jq(uri))!);
		case "textDocument/completion" =>
			complete(id, uri, jnum(jpath(params, "position", "line")),
				jnum(jpath(params, "position", "character")));
		case "textDocument/hover" =>
			hover(id, uri, jnum(jpath(params, "position", "line")),
				jnum(jpath(params, "position", "character")));
		case "shutdown" =>
			lukket = true;
			reply(id, "null");
		case "exit" =>
			os::exit(if (lukket) 0 else 1);
		case =>
			// ukendte forespørgsler (med id) skal have et svar
			if (idv is jval && method != "") {
				send(fmt::asprintf("{{\"jsonrpc\":\"2.0\",\"id\":{},\"error\":{{\"code\":-32601,\"message\":\"ukendt: {}\"}}}}", id, method)!);
			};
		};
	};
};
