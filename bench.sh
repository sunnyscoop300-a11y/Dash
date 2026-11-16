#!/bin/sh
# Måler dsh-hare mod sh (og Python-dsh hvis den findes). Median af flere kørsler.
cd "$(dirname "$0")" || exit 1
printf 'let s = 0\nfor i in range(0, 100000) { s += i }\n' > /tmp/loop.Dash
printf 's=0; i=0\nwhile [ $i -lt 100000 ]; do s=$((s+i)); i=$((i+1)); done\n' > /tmp/loop.sh
printf 'for i in range(0, 1000) { /bin/true }\n' > /tmp/k.Dash
printf 'i=0; while [ $i -lt 1000 ]; do /bin/true; i=$((i+1)); done\n' > /tmp/k.sh
printf 'for i in range(0, 8) parallel 8 { sleep 0.5 }\n' > /tmp/par.Dash
printf 'for i in 1 2 3 4 5 6 7 8; do sleep 0.5; done\n' > /tmp/par.sh
exec python3 - <<'PY'
import subprocess, time, statistics, os, shutil
os.environ["DSH_QUIET"] = "1"
sh = shutil.which("dash") or "/bin/sh"
bins = {"sh": None, "dsh-hare": "./dsh-hare"}
py = os.path.expanduser("~/dsh/dsh.py")
if os.path.exists(py): bins = {"sh": None, "dsh (python)": "py", "dsh-hare": "./dsh-hare"}
tests = [("opstart", [sh, "-c", ":"], ["-e", "let x = 1"]),
         ("100.000 regnestykker", [sh, "/tmp/loop.sh"], ["/tmp/loop.Dash"]),
         ("1000 kommandoer", [sh, "/tmp/k.sh"], ["/tmp/k.Dash"]),
         ("8 × sleep 0.5", [sh, "/tmp/par.sh"], ["/tmp/par.Dash"])]
print(f"{'':24}" + "".join(f"{k:>14}" for k in bins))
for name, shcmd, dargs in tests:
    n = 3 if "sleep" in name else 11
    res = {k: [] for k in bins}
    for _ in range(n):
        for k, b in bins.items():
            cmd = shcmd if b is None else (["python3", py] if b == "py" else [b]) + dargs
            t = time.perf_counter()
            subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            res[k].append(time.perf_counter() - t)
    med = {k: statistics.median(v) for k, v in res.items()}
    line = f"{name:24}"
    for k, v in med.items():
        mark = " ⚡" if k == "dsh-hare" and v < med["sh"] else "  "
        line += f"{v*1000:10.1f}ms{mark}"
    print(line)
print("\n⚡ = dsh-hare er hurtigere end sh")
PY
