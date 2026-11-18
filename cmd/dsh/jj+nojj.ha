// JJGui er ikke med i denne dsh (bygget med -T +nojj, fx til telefonen).
fn jj_call(name: str, args: []value, line: int) (value | failed | void) = {
	for (let n .. JJ_FNS) {
		if (n == name) return dief(line,
			"{}() er JJGui (vinduer og grafik), som ikke er med i denne dsh", name);
	};
};

fn jj_close() void = void;
