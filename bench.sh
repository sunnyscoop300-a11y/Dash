#!/bin/sh
# Måler dsh-hare mod sh (og Python-dsh hvis den findes). Median af flere kørsler.
cd "$(dirname "$0")" || exit 1
printf 'let s = 0\nfor i in range(0, 100000) { s += i }\n' > /tmp/loop.Dash
printf 's=0; i=0\nwhile [ $i -lt 100000 ]; do s=$((s+i)); i=$((i+1)); done\n' > /tmp/loop.sh
printf 'for i in range(0, 1000) { /bin/true }\n' > /tmp/k.Dash
printf 'i=0; while [ $i -lt 1000 ]; do /bin/true; i=$((i+1)); done\n' > /tmp/k.sh
printf 'for i in range(0, 8) parallel 8 { sleep 0.5 }\n' > /tmp/par.Dash
printf 'for i in 1 2 3 4 5 6 7 8; do sleep 0.5; done\n' > /tmp/par.sh
printf 'fn fib(n) {\n  if n < 2 { return n }\n  return fib(n - 1) + fib(n - 2)\n}\nlet x = fib(24)\n' > /tmp/fib.Dash
# Violet: de samme scripts som native binærer (kræver hare)
if command -v hare > /dev/null; then
	for f in loop k par fib; do ./dsh-hare build /tmp/$f.Dash -o /tmp/$f.violet > /dev/null || exit 1; done
	printf 'let x = 1\n' > /tmp/start.Dash
	./dsh-hare build /tmp/start.Dash -o /tmp/start.violet > /dev/null || exit 1
fi
exec python3 - <<'PY'
import subprocess, time, statistics, os, shutil
os.environ["DSH_QUIET"] = "1"
sh = shutil.which("dash") or "/bin/sh"
bins = {"sh": None, "dsh-hare": "./dsh-hare"}
if shutil.which("hare"): bins["violet"] = "violet"
py = os.path.expanduser("~/dsh/dsh.py")
if os.path.exists(py): bins = {"sh": None, "dsh (python)": "py", "dsh-hare": "./dsh-hare", **({"violet": "violet"} if "violet" in bins else {})}
tests = [("opstart", [sh, "-c", ":"], ["-e", "let x = 1"], "start"),
         ("100.000 regnestykker", [sh, "/tmp/loop.sh"], ["/tmp/loop.Dash"], "loop"),
         ("fib(24) (rekursion)", None, ["/tmp/fib.Dash"], "fib"),
         ("1000 kommandoer", [sh, "/tmp/k.sh"], ["/tmp/k.Dash"], "k"),
         ("8 × sleep 0.5", [sh, "/tmp/par.sh"], ["/tmp/par.Dash"], "par")]
print(f"{'':24}" + "".join(f"{k:>14}" for k in bins))
for name, shcmd, dargs, vname in tests:
    n = 3 if "sleep" in name else 11
    res = {k: [] for k in bins}
    for _ in range(n):
        for k, b in bins.items():
            if b is None and shcmd is None: continue
            if b == "violet": cmd = [f"/tmp/{vname}.violet"]
            else: cmd = shcmd if b is None else (["python3", py] if b == "py" else [b]) + dargs
            t = time.perf_counter()
            subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            res[k].append(time.perf_counter() - t)
    med = {k: (statistics.median(v) if v else None) for k, v in res.items()}
    line = f"{name:24}"
    for k, v in med.items():
        if v is None:
            line += f"{'–':>12}  "
            continue
        mark = " ⚡" if k != "sh" and med["sh"] is not None and v < med["sh"] else "  "
        line += f"{v*1000:10.1f}ms{mark}"
    print(line)
print("\n⚡ = hurtigere end sh   violet = samme script som native binær (dsh build)")
PY
