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
