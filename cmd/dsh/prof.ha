// violet prof / dsh prof — en lille profiler: hvor mange gange hver Dash-fn
// kaldes, og hvor længe der gås i den (selv og inkl. de fn'er, den kalder).
//
// Violet sætter prof_ind(n) og defer prof_ud(n) ind øverst i hver fn, når der
// bygges med `violet prof`; fortolkeren gør det samme i call_fn. Rapporten
// skrives til stderr, når programmet slutter — også ved exit, en fejl eller
// Ctrl+C.
use fmt;
use os;
use sort;
use strings;
use time;
use unix::signal;

let prof_on = false;
let prof_navne: []str = [];
let prof_kald: []u64 = [];
let prof_selv: []i64 = [];     // ns i selve fn'en
let prof_inkl: []i64 = [];     // ns inkl. det, den kalder (yderste kald ved rekursion)
let prof_dybde: []int = [];
let prof_t0 = time::instant { ... };
let prof_skrevet = false;

type pramme = struct { id: size, t0: time::instant, born: i64 };
let prof_stak: []pramme = [];

fn prof_start(navne: []str) void = {
	prof_on = true;
	prof_t0 = time::now(time::clock::MONOTONIC);
	for (let n .. navne) prof_ny(n);
	signal::handle(signal::sig::INT, &prof_sigint);
};

fn prof_ny(navn: str) size = {
	append(prof_navne, navn)!;
	append(prof_kald, 0)!;
	append(prof_selv, 0)!;
	append(prof_inkl, 0)!;
	append(prof_dybde, 0)!;
	return len(prof_navne) - 1;
};

// fortolkeren: navn → nummer (huskes i func.pid, så det kun slås op én gang)
fn prof_id(navn: str) size = {
	for (let i = 0z; i < len(prof_navne); i += 1) if (prof_navne[i] == navn) return i;
	return prof_ny(navn);
};

fn prof_ind(id: size) void = {
	prof_kald[id] += 1;
	prof_dybde[id] += 1;
	append(prof_stak, pramme { id = id, t0 = time::now(time::clock::MONOTONIC), born = 0 })!;
};

fn prof_ud(id: size) void = {
	if (len(prof_stak) == 0) return;
	const p = prof_stak[len(prof_stak) - 1];
	delete(prof_stak[len(prof_stak) - 1]);
	const tot = time::diff(p.t0, time::now(time::clock::MONOTONIC)): i64;
	prof_selv[p.id] += tot - p.born;
	prof_dybde[p.id] -= 1;
	if (prof_dybde[p.id] == 0) prof_inkl[p.id] += tot;
	if (len(prof_stak) > 0) prof_stak[len(prof_stak) - 1].born += tot;
};

fn prof_sigint(sig: signal::sig, info: *signal::siginfo, uc: *opaque) void = {
	prof_rapport();
	os::exit(130);
};

fn sek(ns: i64) str = {
	if (ns >= 1000000000) return fmt::asprintf("{:.2f}s", ns: f64 / 1000000000.0)!;
	if (ns >= 1000000) return fmt::asprintf("{:.1f}ms", ns: f64 / 1000000.0)!;
	if (ns >= 1000) return fmt::asprintf("{:.1f}µs", ns: f64 / 1000.0)!;
	return fmt::asprintf("{}ns", ns)!;
};

fn tal(n: u64) str = {
	// 1234567 → 1.234.567
	const s = fmt::asprintf("{}", n)!;
	const b = strings::toutf8(s);
	let ud: []u8 = [];
	for (let i = 0z; i < len(b); i += 1) {
		if (i > 0 && (len(b) - i) % 3 == 0) append(ud, '.')!;
		append(ud, b[i])!;
	};
	return strings::fromutf8_unsafe(ud);
};

fn utf8_bredde(s: str) size = {
	let n = 0z;
	for (let c .. strings::toutf8(s)) if (c & 0xc0 != 0x80) n += 1;
	return n;
};

fn pad(s: str, w: size, hoejre: bool) str = {
	let mellem: []u8 = [];
	for (let i = utf8_bredde(s); i < w; i += 1) append(mellem, ' ')!;
	const m = strings::fromutf8_unsafe(mellem);
	return if (hoejre) strings::concat(m, s)! else strings::concat(s, m)!;
};

let prof_orden: []size = [];

fn prof_cmp(a: const *opaque, b: const *opaque) int = {
	const x = prof_selv[*(a: const *size)], y = prof_selv[*(b: const *size)];
	return if (x > y) -1 else if (x < y) 1 else 0;
};

fn prof_rapport() void = {
	if (!prof_on || prof_skrevet) return;
	prof_skrevet = true;
	flush_out();
	const alt = time::diff(prof_t0, time::now(time::clock::MONOTONIC)): i64;
	let fn_selv = 0i64;
	prof_orden = [];
	for (let i = 0z; i < len(prof_navne); i += 1) {
		fn_selv += prof_selv[i];
		if (prof_kald[i] > 0) append(prof_orden, i)!;
	};
	sort::sort(prof_orden, size(size), &prof_cmp)!;

	const tty = is_tty(os::stderr_file);
	const lilla = if (tty) "\x1b[1;38;5;141m" else "";
	const svag = if (tty) "\x1b[2m" else "";
	const nul = if (tty) "\x1b[0m" else "";
	fmt::errorfln("")!;
	fmt::errorfln("{}💜 violet prof{}  {}{} i alt{}", lilla, nul, svag, sek(alt), nul)!;
	let rk: [][]str = [];
	let hoved: []str = [];
	append(hoved, ["Funktion", "Kald", "Selv", "%", "Inkl.", "pr. kald"]...)!;
	append(rk, hoved)!;
	let vis = 0z;
	for (let i .. prof_orden) {
		if (vis == 25) break;
		vis += 1;
		const pct = if (alt > 0) prof_selv[i]: f64 * 100.0 / alt: f64 else 0.0;
		let r: []str = [];
		append(r, [fmt::asprintf("{}()", prof_navne[i])!, tal(prof_kald[i]), sek(prof_selv[i]),
			fmt::asprintf("{:.1f}%", pct)!, sek(prof_inkl[i]),
			sek(prof_selv[i] / prof_kald[i]: i64)]...)!;
		append(rk, r)!;
	};
	const top = alt - fn_selv;
	let r: []str = [];
	append(r, ["(hovedprogrammet)", "", sek(top),
		fmt::asprintf("{:.1f}%", if (alt > 0) top: f64 * 100.0 / alt: f64 else 0.0)!, "", ""]...)!;
	append(rk, r)!;
	let bredde: [6]size = [0...];
	for (let r .. rk) for (let k = 0z; k < 6; k += 1) {
		if (utf8_bredde(r[k]) > bredde[k]) bredde[k] = utf8_bredde(r[k]);
	};
	for (let j = 0z; j < len(rk); j += 1) {
		let l: []str = [];
		for (let k = 0z; k < 6; k += 1) append(l, pad(rk[j][k], bredde[k], k > 0))!;
		const linje = strings::join("  ", l...)!;
		if (j == 0) fmt::errorfln("  {}{}{}", svag, linje, nul)! else fmt::errorfln("  {}", linje)!;
	};
	if (len(prof_orden) > vis) {
		fmt::errorfln("  {}… og {} fn'er mere{}", svag, len(prof_orden) - vis, nul)!;
	};
	fmt::errorfln("  {}Selv = tid i fn'en selv · Inkl. = med de fn'er, den kalder{}", svag, nul)!;
};
