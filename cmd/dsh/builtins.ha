// Built-in functions, methods (.trim(), .push(...)) and properties (.len).
use bufio;
use bytes;
use fmt;
use fs;
use glob;
use io;
use math;
use os;
use os::exec;
use path;
use strconv;
use strings;
use time;

fn need(name: str, args: []value, n: size, line: int) (void | failed) = {
	if (len(args) != n) {
		return dief(line, "{}() vil have {} argumenter, fik {}", name, n, len(args));
	};
};

fn int_arg(name: str, v: value, line: int) (i64 | failed) = match (v) {
case let i: i64 => yield i;
case let f: f64 => yield f: i64;
case => yield dief(line, "{}() vil have et tal, fik {}", name, typename(v));
};

fn num_arg(name: str, v: value, line: int) (f64 | failed) = match (num(v)) {
case let f: f64 => yield f;
case void => yield dief(line, "{}() vil have et tal, fik {}", name, typename(v));
};

fn str_arg(name: str, v: value, line: int) (str | failed) = match (v) {
case let s: str => yield s;
case => yield dief(line, "{}() vil have en tekst, fik {}", name, typename(v));
};

// "~/x" -> "/home/tux/x"
fn expanduser(p: str) str = {
	if (p == "~") return home();
	if (strings::hasprefix(p, "~/")) return strings::concat(home(), strings::trimprefix(p, "~"))!;
	return p;
};

fn less(a: value, b: value) bool = {
	match (a) {
	case let x: str =>
		match (b) { case let y: str => return strings::compare(x, y) < 0; case => void; };
	case => void;
	};
	match (num(a)) {
	case let x: f64 =>
		match (num(b)) { case let y: f64 => return x < y; case void => void; };
	case void => void;
	};
	return false;
};

fn sorted(items: []value) []value = {
	let out: []value = [];
	append(out, items...)!;
	// insertion sort: lists in scripts are small, and it is stable
	for (let i = 1z; i < len(out); i += 1) {
		const v = out[i];
		let j = i;
		for (j > 0 && less(v, out[j - 1]); j -= 1) out[j] = out[j - 1];
		out[j] = v;
	};
	return out;
};

fn extreme(name: str, args: []value, want_max: bool, line: int) (value | failed) = {
	const items = if (len(args) == 1 && args[0] is *list) (args[0] as *list).items else args;
	if (len(items) == 0) return dief(line, "{}() af ingenting", name);
	let best = items[0];
	for (let v .. items[1..]) {
		if (if (want_max) less(best, v) else less(v, best)) best = v;
	};
	return best;
};

fn write_file(name: str, args: []value, flags: fs::flag, line: int) (value | failed) = {
	need(name, args, 2, line)?;
	const p = expanduser(str_arg(name, args[0], line)?);
	const f = match (os::create(p, 0o644, flags)) {
	case let f: io::file => yield f;
	case let err: fs::error => return dief(line, "{}(): kan ikke skrive '{}': {}", name, p, fs::strerror(err));
	};
	io_ok(io::writeall(f, strings::toutf8(tostr(args[1]))));
	close(f);
	return nilv;
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
		return attr(args[0], "len", line);
	case "str" =>
		need(name, args, 1, line)?;
		return tostr(args[0]);
	case "int" =>
		need(name, args, 1, line)?;
		match (args[0]) {
		case let i: i64 => return i;
		case let f: f64 => return f: i64;
		case let s: str =>
			match (strconv::stoi64(strings::trim(s))) {
			case let i: i64 => return i;
			case => return dief(line, "'{}' er ikke et heltal", s);
			};
		case => return dief(line, "int() virker ikke på en {}", typename(args[0]));
		};
	case "float" =>
		need(name, args, 1, line)?;
		match (args[0]) {
		case let s: str =>
			match (strconv::stof64(strings::trim(s))) {
			case let f: f64 => return f;
			case => return dief(line, "'{}' er ikke et tal", s);
			};
		case => return num_arg(name, args[0], line)?;
		};
	case "type" =>
		need(name, args, 1, line)?;
		return typename(args[0]);
	case "range" =>
		let a = 0i64, b = 0i64, step = 1i64;
		switch (len(args)) {
		case 1 => b = int_arg(name, args[0], line)?;
		case 2, 3 =>
			a = int_arg(name, args[0], line)?;
			b = int_arg(name, args[1], line)?;
			if (len(args) == 3) step = int_arg(name, args[2], line)?;
		case => return die(line, "range() vil have 1-3 argumenter");
		};
		if (step == 0) return die(line, "range() med skridt 0");
		let items: []value = [];
		for (let i = a; if (step > 0) i < b else i > b; i += step) append(items, i)!;
		return newlist(items);
	case "env" =>
		const key = tostr(args[0]);
		match (os::getenv(key)) {
		case let s: str => return s;
		case void => return if (len(args) > 1) args[1] else nilv;
		};
	case "exists" =>
		need(name, args, 1, line)?;
		return os::exists(expanduser(tostr(args[0])));
	case "is_dir", "is_file" =>
		need(name, args, 1, line)?;
		match (os::stat(expanduser(tostr(args[0])))) {
		case let st: fs::filestat =>
			return if (name == "is_dir") fs::isdir(st.mode) else fs::isfile(st.mode);
		case fs::error => return false;
		};
	case "which" =>
		need(name, args, 1, line)?;
		match (exec::lookup(tostr(args[0]))) {
		case let s: str => return strings::dup(s)!;
		case => return nilv;
		};
	case "read" =>
		need(name, args, 1, line)?;
		const p = expanduser(str_arg(name, args[0], line)?);
		const f = match (os::open(p)) {
		case let f: io::file => yield f;
		case let err: fs::error => return dief(line, "read(): kan ikke læse '{}': {}", p, fs::strerror(err));
		};
		const data = io::drain(f)!;
		close(f);
		return strings::fromutf8_unsafe(data);
	case "write" =>
		return write_file(name, args, fs::flag::WRONLY | fs::flag::TRUNC | fs::flag::CREATE, line);
	case "append" =>
		return write_file(name, args, fs::flag::WRONLY | fs::flag::APPEND | fs::flag::CREATE, line);
	case "glob" =>
		need(name, args, 1, line)?;
		let gen = glob::glob(expanduser(str_arg(name, args[0], line)?))!;
		defer glob::finish(&gen);
		let found: []value = [];
		for (true) {
			match (glob::next(&gen)) {
			case let s: str => append(found, strings::dup(s)!)!;
			case done => break;
			case glob::failure => continue;
			case nomem => abort("out of memory");
			};
		};
		return newlist(sorted(found));
	case "input" =>
		if (len(args) > 0) {
			fmt::print(tostr(args[0]))!;
		};
		flush_out();
		match (bufio::read_line(os::stdin_file)) {
		case let b: []u8 => return strings::fromutf8_unsafe(b);
		case => return nilv;
		};
	case "now" =>
		const t = time::now(time::clock::REALTIME);
		return t.sec: f64 + t.nsec: f64 / 1000000000.0;
	case "sleep" =>
		need(name, args, 1, line)?;
		const s = num_arg(name, args[0], line)?;
		time::sleep((s * 1000000000.0): i64: time::duration);
		return nilv;
	case "round" =>
		const x = num_arg(name, args[0], line)?;
		if (len(args) < 2) return math::roundf64(x): i64;
		const k = math::powf64(10.0, int_arg(name, args[1], line)?: f64);
		return math::roundf64(x * k) / k;
	case "abs" =>
		need(name, args, 1, line)?;
		match (args[0]) {
		case let i: i64 => return if (i < 0) -i else i;
		case => return math::absf64(num_arg(name, args[0], line)?);
		};
	case "min" => return extreme(name, args, false, line);
	case "max" => return extreme(name, args, true, line);
	case "cwd" => return strings::dup(os::getcwd())!;
	case =>
		dief(line, "ukendt funktion '{}()'", name): void;
		sethint(hint_from(name, BUILTIN_FNS));
		return failed;
	};
};

// --- properties: .len .name .first ... ---

fn attr(obj: value, name: str, line: int) (value | failed) = {
	match (obj) {
	case let l: *list =>
		switch (name) {
		case "len" => return len(l.items): i64;
		case "first" => return if (len(l.items) > 0) l.items[0] else nilv;
		case "last" => return if (len(l.items) > 0) l.items[len(l.items) - 1] else nilv;
		case => void;
		};
	case let s: str =>
		switch (name) {
		case "len" => return len(s): i64;
		case "name" => return path_name(s);
		case "dir" =>
			match (strings::rindex(s, '/')) {
			case let i: size => return strings::sub(s, 0, i);
			case void => return "";
			};
		case "stem" =>
			const n = path_name(s);
			match (strings::rindex(n, '.')) {
			case let i: size => return if (i == 0) n else strings::sub(n, 0, i);
			case void => return n;
			};
		case "ext" =>
			const n = path_name(s);
			match (strings::rindex(n, '.')) {
			case let i: size => return if (i == 0) "" else strings::sub(n, i, strings::end);
			case void => return "";
			};
		case => void;
		};
	case let m: *mapv =>
		switch (name) {
		case "len" => return len(m.keys): i64;
		case "keys" =>
			let k: []value = [];
			append(k, m.keys...)!;
			return newlist(k);
		case "values" =>
			let v: []value = [];
			append(v, m.vals...)!;
			return newlist(v);
		case =>
			match (map_find(m, name)) {
			case let i: size => return m.vals[i];
			case void => return nilv;
			};
		};
	case => void;
	};
	return dief(line, "en {} har ingen egenskab '.{}'", typename(obj), name);
};

// Splits on the whole separator text (like Python), keeping empty parts.
fn split_str(s: str, sep: str) []str = {
	let out: []str = [];
	let rest = strings::toutf8(s);
	const sb = strings::toutf8(sep);
	for (true) {
		match (bytes::index(rest, sb)) {
		case let i: size =>
			append(out, strings::fromutf8_unsafe(rest[..i]))!;
			rest = rest[i + len(sb)..];
		case void =>
			append(out, strings::fromutf8_unsafe(rest))!;
			return out;
		};
	};
};

// Upper/lower case for ASCII and Latin-1, so æøå work too.
fn casemap(s: str, up: bool) str = {
	let out: []rune = [];
	let it = strings::iter(s);
	for (let r => strings::next(&it)) {
		const c = r: u32;
		if (up && ((c >= 'a' && c <= 'z') || (c >= 0xe0 && c <= 0xfe && c != 0xf7))) {
			append(out, (c - 0x20): rune)!;
		} else if (!up && ((c >= 'A' && c <= 'Z') || (c >= 0xc0 && c <= 0xde && c != 0xd7))) {
			append(out, (c + 0x20): rune)!;
		} else {
			append(out, r)!;
		};
	};
	defer free(out);
	return strings::fromrunes(out)!;
};

fn path_name(s: str) str = match (strings::rindex(s, '/')) {
case let i: size => yield strings::sub(s, i + 1, strings::end);
case void => yield s;
};

// --- methods: .trim() .push(x) ... ---

fn margs(name: str, args: []value, n: size, line: int) (void | failed) = {
	if (len(args) != n) {
		return dief(line, ".{}() vil have {} argumenter, fik {}", name, n, len(args));
	};
};

fn method(obj: value, name: str, args: []value, line: int) (value | failed) = {
	match (obj) {
	case let s: str =>
		switch (name) {
		case "trim" => return strings::trim(s);
		case "upper" => return casemap(s, true);
		case "lower" => return casemap(s, false);
		case "replace" =>
			margs(name, args, 2, line)?;
			return strings::multireplace(s, (tostr(args[0]), tostr(args[1])))!;
		case "contains" =>
			margs(name, args, 1, line)?;
			return strings::contains(s, tostr(args[0]));
		case "starts_with" =>
			margs(name, args, 1, line)?;
			return strings::hasprefix(s, tostr(args[0]));
		case "ends_with" =>
			margs(name, args, 1, line)?;
			return strings::hassuffix(s, tostr(args[0]));
		case "repeat" =>
			margs(name, args, 1, line)?;
			const n = int_arg(name, args[0], line)?;
			let out: []u8 = [];
			for (let i = 0i64; i < n; i += 1) append(out, strings::toutf8(s)...)!;
			return strings::fromutf8_unsafe(out);
		case "split" =>
			let parts: []value = [];
			if (len(args) == 0) {
				// on any whitespace, no empty parts
				let tok = strings::tokenize(strings::trim(s), " ");
				for (let t => strings::next_token(&tok)) {
					let tok2 = strings::tokenize(t, "\t");
					for (let t2 => strings::next_token(&tok2)) {
						let tok3 = strings::tokenize(t2, "\n");
						for (let t3 => strings::next_token(&tok3)) {
							if (len(t3) > 0) append(parts, t3)!;
						};
					};
				};
			} else {
				const sep = tostr(args[0]);
				if (len(sep) == 0) return die(line, ".split() med tom separator");
				for (let p .. split_str(s, sep)) append(parts, p)!;
			};
			return newlist(parts);
		case "lines" =>
			let parts: []value = [];
			const t = strings::rtrim(s, '\n');
			if (len(t) > 0) {
				for (let p .. split_str(t, "\n")) append(parts, strings::rtrim(p, '\r'))!;
			};
			return newlist(parts);
		case => void;
		};
	case let l: *list =>
		switch (name) {
		case "push" =>
			margs(name, args, 1, line)?;
			append(l.items, args[0])!;
			return nilv;
		case "pop" =>
			if (len(l.items) == 0) return nilv;
			const v = l.items[len(l.items) - 1];
			delete(l.items[len(l.items) - 1]);
			return v;
		case "join" =>
			const sep = if (len(args) > 0) tostr(args[0]) else "";
			let out: []u8 = [];
			for (let i = 0z; i < len(l.items); i += 1) {
				if (i > 0) append(out, strings::toutf8(sep)...)!;
				append(out, strings::toutf8(tostr(l.items[i]))...)!;
			};
			return strings::fromutf8_unsafe(out);
		case "contains" =>
			margs(name, args, 1, line)?;
			for (let v .. l.items) if (equal(v, args[0])) return true;
			return false;
		case "sort" => return newlist(sorted(l.items));
		case "reverse" =>
			let out: []value = [];
			for (let i = len(l.items); i > 0; i -= 1) append(out, l.items[i - 1])!;
			return newlist(out);
		case "map", "filter" =>
			margs(name, args, 1, line)?;
			const f = match (args[0]) {
			case let f: *func => yield f;
			case => return dief(line, ".{}() vil have en fn, fik {}", name, typename(args[0]));
			};
			let out: []value = [];
			for (let v .. l.items) {
				const r = call_fn(f, [v], line)?;
				if (name == "map") append(out, r)! else if (truthy(r)) append(out, v)!;
			};
			return newlist(out);
		case => void;
		};
	case let m: *mapv =>
		switch (name) {
		case "get" =>
			if (len(args) < 1) return die(line, ".get() vil have en nøgle");
			match (map_find(m, args[0])) {
			case let i: size => return m.vals[i];
			case void => return if (len(args) > 1) args[1] else nilv;
			};
		case "has" =>
			margs(name, args, 1, line)?;
			return map_find(m, args[0]) is size;
		case => void;
		};
	case => void;
	};
	return dief(line, "en {} har ingen metode '.{}()'", typename(obj), name);
};
