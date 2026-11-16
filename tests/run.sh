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
echo "$ok ok, $bad fejl"
[ "$bad" -eq 0 ]
