// JJGui 3D — et lille software-3D-lag oven på JJGui's 2D-tegning.
//
//   camera(0, 3, -6, 15)                 x, y, z, hældning° [, drejning°, synsvinkel°]
//   fog("#87c4ff", 30, 90)               tåge fra 30 til 90 enheder væk
//   floor3d(-4, 0, 4, 100, 0, "gray")    vandret flade (tegnes altid under resten)
//   floor3d(-1, 0, 1, 2, 0, "white", 1)  … i lag 1: oven på lag 0 (striber o.l.)
//   box3d(0, 0, 5, 1, 2, 1, "gold")      kasse: x/z = midten, y = bunden
//   circle3d(0, 1, 8, 0.4, "gold", "P")  cirkel (med tekst) der vender mod kameraet
//   render3d()                           tegner det hele fra bagerst til forrest
//
// y peger op, z peger ind i skærmen. Alt bliver samlet i en kø og sorteret,
// så det forreste dækker det bagerste (malerens algoritme).
use math;
use sort;
use strings;
use viper;

def NEAR: f64 = 0.08;

type j3item = struct {
	layer: int,               // 0-99 = gulv-lag (altid først), 100 = resten
	depth: f64,
	pts: [12](f64, f64),
	n: size,
	col: viper::color,
	circle: bool,
	cx: int, cy: int, r: int,
	txt: str,
	tcol: viper::color,
};

let j3_queue: []j3item = [];
let cam_x = 0.0;
let cam_y = 2.0;
let cam_z = -6.0;
let cam_sp = 0.0;    // sin/cos af hældning
let cam_cp = 1.0;
let cam_sy = 0.0;    // sin/cos af drejning
let cam_cy = 1.0;
let cam_f = 1.0;                    // fokallængde i pixels (sættes af camera)
let cam_fov = 60.0;
let fog_col: viper::color = 0xff000000;
let fog_start = 0.0;
let fog_end = 0.0;

fn rad(deg: f64) f64 = deg * math::PI / 180.0;

fn cam_focal(win: *viper::window) void = {
	cam_f = (win.height: f64 / 2.0) / math::tanf64(rad(cam_fov) / 2.0);
};

// verden → kamera
fn xf(x: f64, y: f64, z: f64) (f64, f64, f64) = {
	const dx = x - cam_x, dy = y - cam_y, dz = z - cam_z;
	const x1 = dx * cam_cy - dz * cam_sy;
	const z1 = dx * cam_sy + dz * cam_cy;
	const y2 = dy * cam_cp + z1 * cam_sp;
	const z2 = -dy * cam_sp + z1 * cam_cp;
	return (x1, y2, z2);
};

fn proj(win: *viper::window, p: (f64, f64, f64)) (f64, f64) =
	(win.width: f64 / 2.0 + p.0 * cam_f / p.2, win.height: f64 / 2.0 - p.1 * cam_f / p.2);

fn shade(col: viper::color, b: f64) viper::color = viper::mix(0xff000000, col, if (b > 1.0) 1.0 else b);

fn fogged(col: viper::color, dist: f64) viper::color = {
	if (fog_end <= fog_start) return col;
	let t = (dist - fog_start) / (fog_end - fog_start);
	if (t <= 0.0) return col;
	if (t > 1.0) t = 1.0;
	return viper::mix(col, fog_col, t);
};

fn dist3(x: f64, y: f64, z: f64) f64 = {
	const dx = x - cam_x, dy = y - cam_y, dz = z - cam_z;
	return math::sqrtf64(dx * dx + dy * dy + dz * dz);
};

// Klipper en polygon (i kamera-rum) mod nærplanet og lægger den i køen.
fn j3_poly(win: *viper::window, cam: [](f64, f64, f64), col: viper::color, layer: int, depth: f64) void = {
	let out: [12](f64, f64, f64) = [(0.0, 0.0, 0.0)...];
	let n = 0z;
	for (let i = 0z; i < len(cam); i += 1) {
		const a = cam[i], b = cam[(i + 1) % len(cam)];
		const ain = a.2 >= NEAR, bin = b.2 >= NEAR;
		if (ain && n < len(out)) {
			out[n] = a;
			n += 1;
		};
		if (ain != bin && n < len(out)) {
			const t = (NEAR - a.2) / (b.2 - a.2);
			out[n] = (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, NEAR);
			n += 1;
		};
	};
	if (n < 3) return;
	let it = j3item { layer = layer, depth = depth, n = n, col = col, ... };
	for (let i = 0z; i < n; i += 1) it.pts[i] = proj(win, out[i]);
	append(j3_queue, it)!;
};

fn j3_light(nx: f64, ny: f64, nz: f64) f64 = {
	// lys oppefra, lidt fra venstre og bagfra kameraet
	const l = nx * 0.35 + ny * 0.85 - nz * 0.40;
	return 0.58 + 0.42 * (if (l > 0.0) l else 0.0);
};

fn j3_box(win: *viper::window, x: f64, y: f64, z: f64, w: f64, h: f64, d: f64, col: viper::color) void = {
	const x0 = x - w / 2.0, x1 = x + w / 2.0, y0 = y, y1 = y + h, z0 = z - d / 2.0, z1 = z + d / 2.0;
	const dist = dist3(x, y + h / 2.0, z);
	// [normal, 4 hjørner]
	const faces: [6]((f64, f64, f64), [4](f64, f64, f64)) = [
		((0.0, 1.0, 0.0), [(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)]),
		((0.0, -1.0, 0.0), [(x0, y0, z0), (x0, y0, z1), (x1, y0, z1), (x1, y0, z0)]),
		((0.0, 0.0, -1.0), [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0)]),
		((0.0, 0.0, 1.0), [(x1, y0, z1), (x0, y0, z1), (x0, y1, z1), (x1, y1, z1)]),
		((-1.0, 0.0, 0.0), [(x0, y0, z1), (x0, y0, z0), (x0, y1, z0), (x0, y1, z1)]),
		((1.0, 0.0, 0.0), [(x1, y0, z0), (x1, y0, z1), (x1, y1, z1), (x1, y1, z0)]),
	];
	for (let f .. faces) {
		const (n, q) = f;
		// midten af fladen; vender den væk fra kameraet, springes den over
		const mx = (q[0].0 + q[2].0) / 2.0, my = (q[0].1 + q[2].1) / 2.0, mz = (q[0].2 + q[2].2) / 2.0;
		if (n.0 * (mx - cam_x) + n.1 * (my - cam_y) + n.2 * (mz - cam_z) >= 0.0) continue;
		let cam: [4](f64, f64, f64) = [(0.0, 0.0, 0.0)...];
		for (let k = 0z; k < 4; k += 1) cam[k] = xf(q[k].0, q[k].1, q[k].2);
		const c = fogged(shade(col, j3_light(n.0, n.1, n.2)), dist);
		j3_poly(win, cam, c, 100, dist);
	};
};

fn j3_cmp(a: const *opaque, b: const *opaque) int = {
	const a = a: *const j3item, b = b: *const j3item;
	if (a.layer != b.layer) return a.layer - b.layer;
	if (a.depth > b.depth) return -1;
	if (a.depth < b.depth) return 1;
	return 0;
};

fn j3_render(win: *viper::window) void = {
	sort::sort(j3_queue, size(j3item), &j3_cmp)!;
	for (let it &.. j3_queue) {
		if (it.circle) {
			viper::circle(win, it.cx, it.cy, it.r, it.col);
			if (len(it.txt) > 0) {
				const sc = if (it.r >= 22) 2 else 1;
				const tw = viper::text_width(it.txt, sc);
				viper::text_scaled(win, it.cx - tw / 2, it.cy - 8 * sc, it.txt, it.tcol, sc);
				free(it.txt);
			};
			continue;
		};
		viper::polygon(win, it.pts[..it.n], it.col);
	};
	j3_queue = j3_queue[..0];
};

fn jj3_call(name: str, args: []value, line: int) (value | failed | void) = {
	switch (name) {
	case "camera" =>
		const win = jj_window(name, line)?;
		cam_x = jj_num(name, args, 0, line)?;
		cam_y = jj_num(name, args, 1, line)?;
		cam_z = jj_num(name, args, 2, line)?;
		const pitch = if (len(args) > 3) jj_num(name, args, 3, line)? else 0.0;
		const yaw = if (len(args) > 4) jj_num(name, args, 4, line)? else 0.0;
		cam_fov = if (len(args) > 5) jj_num(name, args, 5, line)? else 60.0;
		cam_sp = math::sinf64(rad(pitch));
		cam_cp = math::cosf64(rad(pitch));
		cam_sy = math::sinf64(rad(yaw));
		cam_cy = math::cosf64(rad(yaw));
		cam_focal(win);
		return nilv: value;
	case "fog" =>
		if (len(args) == 0) {
			fog_end = 0.0;
			return nilv: value;
		};
		fog_col = jj_color(name, args[0], line)?;
		fog_start = jj_num(name, args, 1, line)?;
		fog_end = jj_num(name, args, 2, line)?;
		return nilv: value;
	case "box3d" =>
		const win = jj_window(name, line)?;
		j3_box(win, jj_num(name, args, 0, line)?, jj_num(name, args, 1, line)?, jj_num(name, args, 2, line)?,
			jj_num(name, args, 3, line)?, jj_num(name, args, 4, line)?, jj_num(name, args, 5, line)?,
			jj_col_arg(name, args, 6, 0xffffffff, line)?);
		return nilv: value;
	case "floor3d" =>
		// floor3d(x0, z0, x1, z1, y, farve)
		const win = jj_window(name, line)?;
		const x0 = jj_num(name, args, 0, line)?, z0 = jj_num(name, args, 1, line)?;
		const x1 = jj_num(name, args, 2, line)?, z1 = jj_num(name, args, 3, line)?;
		const y = jj_num(name, args, 4, line)?;
		const col = jj_col_arg(name, args, 5, 0xff808080, line)?;
		let lag = if (len(args) > 6) jj_int(name, args, 6, line)? else 0;
		if (lag < 0) lag = 0;
		if (lag > 99) lag = 99;
		// lange flader deles i stykker, så tågen bliver jævn
		let n = math::ceilf64(math::absf64(z1 - z0) / 3.0): int;
		if (n < 1) n = 1;
		if (n > 60) n = 60;
		for (let k = 0; k < n; k += 1) {
			const za = z0 + (z1 - z0) * k: f64 / n: f64;
			const zb = z0 + (z1 - z0) * (k + 1): f64 / n: f64;
			const cam: [4](f64, f64, f64) = [xf(x0, y, za), xf(x1, y, za), xf(x1, y, zb), xf(x0, y, zb)];
			const zm = (za + zb) / 2.0;
			const dist = dist3(if (cam_x < x0) x0 else if (cam_x > x1) x1 else cam_x, y, zm);
			j3_poly(win, cam, fogged(col, dist), lag, dist);
		};
		return nilv: value;
	case "circle3d" =>
		const win = jj_window(name, line)?;
		const x = jj_num(name, args, 0, line)?, y = jj_num(name, args, 1, line)?, z = jj_num(name, args, 2, line)?;
		const r = jj_num(name, args, 3, line)?;
		const c = xf(x, y, z);
		if (c.2 < NEAR) return nilv: value;
		const (sx, sy) = proj(win, c);
		const dist = dist3(x, y, z);
		const col = fogged(jj_col_arg(name, args, 4, 0xffffffff, line)?, dist);
		let it = j3item { layer = 100, depth = dist, circle = true,
			cx = sx: int, cy = sy: int, r = (r * cam_f / c.2): int, col = col, ... };
		if (len(args) > 5) {
			it.txt = strings::dup(tostr(args[5]))!;
			it.tcol = fogged(jj_col_arg(name, args, 6, 0xff000000, line)?, dist);
		};
		append(j3_queue, it)!;
		return nilv: value;
	case "project" =>
		const win = jj_window(name, line)?;
		const c = xf(jj_num(name, args, 0, line)?, jj_num(name, args, 1, line)?, jj_num(name, args, 2, line)?);
		if (c.2 < NEAR) return nilv: value;
		const (sx, sy) = proj(win, c);
		let items: []value = [];
		append(items, [sx, sy, cam_f / c.2]...)!;
		return newlist(items);
	case "render3d" =>
		j3_render(jj_window(name, line)?);
		return nilv: value;
	case => return;
	};
};
