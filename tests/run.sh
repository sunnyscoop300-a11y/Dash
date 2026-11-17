#!/bin/sh
# Kører testene mod ./dsh-hare. Brug: make test
cd "$(dirname "$0")/.." || exit 1
ok=0; bad=0
check() { if [ "$1" = "$2" ]; then ok=$((ok+1)); else bad=$((bad+1)); printf '✘ %s\n   forventede: %s\n   fik:        %s\n' "$3" "$2" "$1"; fi; }

check "$(./dsh-hare -e 'echo "hej {1 + 2}"')" "hej 3" "interpolation"
check "$(./dsh-hare -e 'let s = 0
for i in range(1, 11) { s += i }
echo $s')" "55" "for + range"
check "$(./dsh-hare -e 'let x = $(echo hej | tr a-z A-Z)
echo $x')" "HEJ" "capture + pipe"
check "$(./dsh-hare -e 'let f = "/tmp/dsh test fil"
echo med mellemrum > $f
cat $f
rm $f')" "med mellemrum" "mellemrum i filnavne"
check "$(./dsh-hare -e 'try false
echo $status')" "1" "try + status"
check "$(./dsh-hare -e 'let l = ["a", "b"]
echo $l')" "a b" "liste bliver til argumenter"
check "$(./dsh-hare -e 'for i in range(4) parallel 4 { true }
echo ok' 2>/dev/null)" "ok" "parallel"
for c in 'false' 'findesikke' 'echo $nope' 'x = 1' 'fail "stop"' 'let a = 1 / 0'; do
	if ./dsh-hare -e "$c" >/dev/null 2>&1; then bad=$((bad+1)); echo "✘ skulle fejle: $c"; else ok=$((ok+1)); fi
done
if ./dsh-hare tests/basis.Dash >/dev/null 2>&1; then ok=$((ok+1)); else bad=$((bad+1)); echo "✘ tests/basis.Dash"; fi
rm -f /tmp/ap.txt
if [ "$(./dsh-hare tests/features.Dash 2>&1)" = "$(cat tests/features.forventet)" ]; then ok=$((ok+1)); else bad=$((bad+1)); echo "✘ tests/features.Dash (se diff med tests/features.forventet)"; fi
# 0.6: Violet trin 1 — type-inferens
printf 'let n = 0\nlet navn = "x"\nlet l = []\nl.push(1.5)\nfn dobbelt(x) { return x * 2 }\nlet d = dobbelt(n)\nlet h = 7 / 2\n' > /tmp/violet-test.Dash
vt=$(./dsh-hare types /tmp/violet-test.Dash)
check "$(echo "$vt" | grep -c '✔ n  *int$')" "1" "violet: int"
check "$(echo "$vt" | grep -c 'navn  *str$')" "1" "violet: str"
check "$(echo "$vt" | grep -c 'l  *list\[float\]$')" "1" "violet: list fra push"
check "$(echo "$vt" | grep -c 'fn dobbelt(x: int) → int')" "1" "violet: fn-typer fra kald"
check "$(echo "$vt" | grep -c '~ h  *num$')" "1" "violet: 7 / 2 er int eller float"
check "$(ln -sf "$PWD/dsh-hare" /tmp/violet && /tmp/violet types tests/basis.Dash | grep -c 'variabler har')" "1" "violet-navnet"
rm -f /tmp/violet-test.Dash /tmp/violet
# 0.7: Violet trin 2 — native binærer (kun hvis hare findes)
if command -v hare > /dev/null; then
	printf 'let s = 0\nfor i in range(1, 11) { s += i }\necho "sum: $s"\nfn fib(n) {\n  if n < 2 { return n }\n  return fib(n - 1) + fib(n - 2)\n}\nprint(fib(15), 7 / 2, 6 / 3)\nlet l = []\nfor x in ["a", "b"] { l.push(x.upper()) }\necho "{l.join("-")} $(echo hej | tr a-z A-Z)"\ntry false\necho "status {status}"\nlet m = {"a": 1}\nm.b = 2\nprint(m, m.len, args)\n' > /tmp/violet-b.Dash
	./dsh-hare build /tmp/violet-b.Dash -o /tmp/violet-b > /dev/null 2>&1
	check "$(/tmp/violet-b x y 2>&1)" "$(./dsh-hare /tmp/violet-b.Dash x y 2>&1)" "violet build: samme output som dsh"
	./dsh-hare build tests/basis.Dash -o /tmp/violet-basis > /dev/null 2>&1
	check "$(DSH_QUIET=1 /tmp/violet-basis 2>&1 | sort)" "$(DSH_QUIET=1 ./dsh-hare tests/basis.Dash 2>&1 | sort)" "violet build: basis.Dash"
	check "$(printf 'let x = 1 / 0\n' > /tmp/violet-f.Dash; ./dsh-hare build /tmp/violet-f.Dash -o /tmp/violet-f > /dev/null 2>&1; /tmp/violet-f 2>&1 | head -1 | grep -c 'division med nul')" "1" "violet build: fejlbesked"
	./dsh-hare build /tmp/violet-f.Dash -o /tmp/violet-s --strip > /dev/null 2>&1
	check "$(/tmp/violet-s 2>&1 | head -1 | grep -c 'division med nul')" "1" "violet build --strip"
	rm -f /tmp/violet-b /tmp/violet-b.Dash /tmp/violet-basis /tmp/violet-f /tmp/violet-f.Dash /tmp/violet-s
fi
# 0.8: violet run (cache) og --arch
if command -v hare > /dev/null; then
	export XDG_CACHE_HOME=/tmp/violet-cache-test
	rm -rf "$XDG_CACHE_HOME"
	printf 'let s = 0\nfor i in range(100) { s += i }\nprint(s, args)\n' > /tmp/violet-r.Dash
	ln -sf "$PWD/dsh-hare" /tmp/violet
	check "$(/tmp/violet run /tmp/violet-r.Dash a 2>/dev/null)" "4950 [\"a\"]" "violet run: første gang (bygger)"
	check "$(ls "$XDG_CACHE_HOME/violet" | grep -c 'violet-r.Dash-')" "1" "violet run: binær i cachen"
	check "$(/tmp/violet run /tmp/violet-r.Dash b)" "4950 [\"b\"]" "violet run: fra cachen"
	rm -f /tmp/ap.txt; a=$(/tmp/violet run tests/features.Dash 2>/dev/null)
	rm -f /tmp/ap.txt; b=$(./dsh-hare tests/features.Dash 2>/dev/null)
	rm -f /tmp/ap.txt
	check "$a" "$b" "violet run: falder tilbage til dsh"
	rm -rf "$XDG_CACHE_HOME" /tmp/violet-r.Dash /tmp/violet
	unset XDG_CACHE_HOME
	if command -v aarch64-linux-gnu-gcc > /dev/null && command -v qemu-aarch64-static > /dev/null; then
		printf 'let s = 0\nfor i in range(100) { s += i }\necho "arm: $s"\n' > /tmp/violet-a.Dash
		./dsh-hare build /tmp/violet-a.Dash --arch aarch64 -o /tmp/violet-a > /dev/null 2>&1
		check "$(qemu-aarch64-static /tmp/violet-a)" "arm: 4950" "violet --arch aarch64 (qemu)"
		rm -f /tmp/violet-a /tmp/violet-a.Dash
	fi
fi
# v0.5: & (baggrund), ask, menu, progress
s=$(date +%s%N); out=$(./dsh-hare -e 'sleep 2 &
echo straks'); e=$(date +%s%N)
check "$out" "straks" "& kører i baggrunden"
if [ $(( (e-s)/1000000 )) -lt 1000 ]; then ok=$((ok+1)); else bad=$((bad+1)); echo "✘ & ventede på sleep"; fi
check "$(./dsh-hare -e 'sh -c "echo støj; echo fejl >&2" &
sleep 0.2
echo stille' 2>&1)" "stille" "& skjuler output"
check "$(printf 'j\n' | ./dsh-hare -e 'print(ask("ok?"))' | tail -c 5)" "true" "ask ja"
check "$(printf '\n' | ./dsh-hare -e 'print(ask("ok?", true))' | tail -c 5)" "true" "ask standard ja"
check "$(printf '7\n2\n' | ./dsh-hare -e 'print(menu(["a", "b"]))' | tail -c 2)" "b" "menu"
check "$(./dsh-hare -e 'progress(50, "x")')" "  ██████████░░░░░░░░░░  50%  x" "progress"

check "$(./dsh-hare -e 'try findesikke
echo $status')" "127" "try fanger manglende kommando"

# dsh check: den ødelagte fil skal give præcis disse fejl og forslag
out=$(./dsh-hare check tests/ødelagt.Dash 2>&1)
for want in "linje 3: kommandoen '⚡'" "mangler der et # foran" "mangler der et komma i slutningen af linje 11" \
	"mente du 'har_brave'" "er linjen blevet delt" "mente du 'echo'" "mente du 'urls'" "mente du 'len'"; do
	case "$out" in *"$want"*) ok=$((ok+1));; *) bad=$((bad+1)); echo "✘ check mangler: $want";; esac
done
if ./dsh-hare check tests/basis.Dash >/dev/null 2>&1; then ok=$((ok+1)); else bad=$((bad+1)); echo "✘ check fandt fejl i basis.Dash"; fi
echo "$ok ok, $bad fejl"
[ "$bad" -eq 0 ]
