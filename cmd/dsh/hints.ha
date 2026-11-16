// "Mente du …?" — hints under the error, so a typo or a broken line is
// easy to fix.
use fs;
use os;
use strings;

let err_hint: str = "";

const HINT_SPLIT: str = "er linjen blevet delt i to? en streng skal stå på én linje (nano: Alt+S slår ombrydning fra)";

const BUILTIN_FNS: [_]str = ["print", "len", "str", "int", "float", "type", "range",
	"env", "exists", "is_dir", "is_file", "which", "read", "write", "append",
	"glob", "input", "now", "sleep", "round", "abs", "min", "max", "cwd"];

const BUILTIN_CMDS: [_]str = ["echo", "cd", "exit", "fail"];

fn dieh(line: int, msg: str, hint: str) failed = {
	die(line, msg): void;
	err_hint = hint;
	return failed;
};

fn sethint(h: str) void = err_hint = h;

fn mente(name: str) str = strings::concat("mente du '", name, "'?")!;

// Levenshtein distance between two strings, counted in runes.
fn distance(a: str, b: str) size = {
	const x = strings::torunes(a)!, y = strings::torunes(b)!;
	defer free(x);
	defer free(y);
	let prev: []size = [], cur: []size = [];
	defer free(prev);
	defer free(cur);
	for (let j = 0z; j <= len(y); j += 1) {
		append(prev, j)!;
		append(cur, 0)!;
	};
	for (let i = 1z; i <= len(x); i += 1) {
		cur[0] = i;
		for (let j = 1z; j <= len(y); j += 1) {
			const cost = if (x[i - 1] == y[j - 1]) 0z else 1z;
			let best = prev[j] + 1;
			if (cur[j - 1] + 1 < best) best = cur[j - 1] + 1;
			if (prev[j - 1] + cost < best) best = prev[j - 1] + cost;
			cur[j] = best;
		};
		const t = prev;
		prev = cur;
		cur = t;
	};
	return prev[len(y)];
};

// The closest candidate, if it is close enough to be a typo.
fn suggest(name: str, cands: []str) (str | void) = {
	// "har _brave" → "har_brave": spaces that slipped in
	const joined = strings::multireplace(name, (" ", ""))!;
	let best = "", bestd = 99z;
	for (let c .. cands) {
		if (c == name) continue;
		if (c == joined) return c;
		const d = distance(name, c);
		if (d < bestd) {
			bestd = d;
			best = c;
		};
	};
	const n = len(strings::torunes(name)!);
	const limit = if (n <= 3) 1z else if (n <= 6) 2z else 3z;
	if (bestd <= limit && bestd < n) return best;
};

fn hint_from(name: str, cands: []str) str = match (suggest(name, cands)) {
case let s: str => yield mente(s);
case void => yield "";
};

// All programs in PATH (only used when something went wrong).
fn path_commands() []str = {
	let out: []str = [];
	let tok = strings::tokenize(os::tryenv("PATH", "/usr/bin:/bin"), ":");
	for (let dir => strings::next_token(&tok)) {
		const it = match (os::iter(dir)) {
		case let it: *fs::iterator => yield it;
		case fs::error => continue;
		};
		for (true) {
			match (fs::next(it)) {
			case let d: fs::dirent => append(out, strings::dup(d.name)!)!;
			case => break;
			};
		};
		fs::finish(it);
	};
	return out;
};

// "kigger selv efter filerne." is not a command — it is a comment that
// lost its '#'.
fn looks_like_text(words: []str) bool = {
	// "⚡" or "—" alone: no letters or digits at all
	if (len(words) == 1) {
		for (let c .. strings::toutf8(words[0])) {
			if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) return false;
		};
		return true;
	};
	for (let w .. words) {
		if (len(w) == 0) return false;
		const b = strings::toutf8(w);
		if (b[0] == '-' || b[0] == '/' || b[0] == '.' || b[0] == '~') return false;
		for (let c .. b) {
			const ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c >= 0x80
				|| c == ',' || c == '.' || c == '!' || c == '?' || c == ':'
				|| c == '(' || c == ')' || c == '-' || c == '\'';
			if (!ok) return false;
		};
	};
	return true;
};

fn command_hint(words: []str, extra: []str) str = {
	let cands: []str = [];
	append(cands, BUILTIN_CMDS...)!;
	append(cands, extra...)!;
	append(cands, path_commands()...)!;
	// one letter off a real command ("ecgo") is a typo, not a lost comment
	match (suggest(words[0], cands)) {
	case let s: str =>
		if (distance(words[0], s) <= 1) return mente(s);
	case void => void;
	};
	if (looks_like_text(words)) return "ligner almindelig tekst — mangler der et # foran?";
	return hint_from(words[0], cands);
};
