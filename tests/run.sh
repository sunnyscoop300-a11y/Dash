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
# 0.14: 2>&1, &> og jobs med &( ) / wait() / running()
check "$(./dsh-hare -e 'try ls /findesikke > /tmp/dsh-2.txt 2>&1
print(read("/tmp/dsh-2.txt").contains("findesikke"))')" "true" "2>&1"
check "$(./dsh-hare -e 'try ls /findesikke &> /tmp/dsh-2.txt
try ls /heller_ikke &>> /tmp/dsh-2.txt
print(read("/tmp/dsh-2.txt").lines().len)')" "2" "&> og &>>"
rm -f /tmp/dsh-2.txt
check "$(./dsh-hare -e 'let j = &(sleep 0.3)
let n = 0
while running(j) {
  n += 1
  sleep(0.05)
}
print(wait(j), n > 2)')" "0 true" "job: running() og wait()"
check "$(./dsh-hare -e 'let j = &(ls /findesikke)
print(wait(j), status)')" "2 2" "job: exitkode"
check "$(./dsh-hare -e 'let j = &(sleep 5)
kill(j)
print(wait(j))')" "143" "job: kill()"
check "$(./dsh-hare -e 'let u = $(try ls /findesikke 2>&1)
print(status, u.contains("findesikke"))')" "2 true" "\$(try …)"
check "$(printf 'sh -c "echo hej"\nsh -c "echo ok"  # sh-ok\n' > /tmp/dsh-w.Dash; ./dsh-hare check /tmp/dsh-w.Dash | grep -c "⚠")" "1" "check: advarsel ved sh -c"
rm -f /tmp/dsh-w.Dash
for c in 'false' 'findesikke' 'echo $nope' 'x = 1' 'fail "stop"' 'let a = 1 / 0'; do
	if ./dsh-hare -e "$c" >/dev/null 2>&1; then bad=$((bad+1)); echo "✘ skulle fejle: $c"; else ok=$((ok+1)); fi
done
if ./dsh-hare tests/basis.Dash >/dev/null 2>&1; then ok=$((ok+1)); else bad=$((bad+1)); echo "✘ tests/basis.Dash"; fi
rm -f /tmp/ap.txt
if [ "$(./dsh-hare tests/features.Dash 2>&1)" = "$(cat tests/features.forventet)" ]; then ok=$((ok+1)); else bad=$((bad+1)); echo "✘ tests/features.Dash (se diff med tests/features.forventet)"; fi
# 0.9.3: is_dir/is_file følger symlinks
rm -rf /tmp/dsh-st && mkdir -p /tmp/dsh-st/rigtig && ln -s rigtig /tmp/dsh-st/link && touch /tmp/dsh-st/fil && ln -s fil /tmp/dsh-st/fillink
check "$(./dsh-hare -e 'print(is_dir("/tmp/dsh-st/link"), is_file("/tmp/dsh-st/fillink"), is_dir("/tmp/dsh-st/fillink"))')" "true true false" "is_dir/is_file følger symlinks"
rm -rf /tmp/dsh-st
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
		# android: uden libc; i qemu bruges glibc's loader i stedet for linker64
		VIOLET_INTERP=/lib/ld-linux-aarch64.so.1 ./dsh-hare build /tmp/violet-a.Dash --arch android -o /tmp/violet-a > /dev/null 2>&1
		check "$(qemu-aarch64-static -L /usr/aarch64-linux-gnu /tmp/violet-a)" "arm: 4950" "violet --arch android (qemu)"
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

# Parr: formatering og udskrift
check "$(./dsh-hare -e 'parr.ln("a", 1, 2.5, true, [1, 2])')" "a 1 2.5 true [1, 2]" "parr.ln"
check "$(./dsh-hare -e 'parr.err("ups", 7)' 2>&1 >/dev/null)" "ups 7" "parr.err til stderr"
check "$(./dsh-hare -e 'let n = "Bo"
let p = 12.5
echo "[{n:<6}|{p:>8.2}|{n:^6}]"')" "[Bo    |   12.50|  Bo  ]" "{x:spec} justering og decimaler"
check "$(./dsh-hare -e 'echo "{255:x} {255:X} {5:03} {7:b} {8:o} {-5:05} {3:+}"')" "ff FF 005 111 10 -0005 +3" "{x:spec} hex/bin/oct/nuller/fortegn"
check "$(./dsh-hare -e 'echo "{1234567:,} {1234.5:,.2} {0.38:%} {0.3851:.1%} {"Katcha":.3}"')" "1,234,567 1,234.50 38% 38.5% Kat" "{x:spec} tusinder/procent/tekst"
check "$(./dsh-hare -e 'let m = {"a": 1}
echo "{m.a}: { {"b": 2}.b }"')" "1: 2" "kolon uden spec er bare tekst"
check "$(./dsh-hare -e 'print(parr.fmt(3.14159, ".3"))')" "3.142" "parr.fmt"
check "$(./dsh-hare -e 'parr.tabel([["Navn", "Pris"], ["Hirdi", 12.5], ["Ællingen", 1000]])')" "Navn      Pris
Hirdi     12.5
Ællingen  1000" "parr.tabel"
check "$(./dsh-hare -e 'parr.tabel([["a", "b"], ["ccc", ""]])' | cat -A | head -1)" 'a    b$' "parr.tabel uden mellemrum for enden"
case "$(./dsh-hare -e 'print(parr.fmt(1, "q"))' 2>&1)" in *"ugyldig format-spec"*) ok=$((ok+1));; *) bad=$((bad+1)); echo "✘ parr.fmt ugyldig spec";; esac

# match og import (0.15 «Flora»)
check "$(./dsh-hare -e 'for i in range(5) {
    match i {
        0 => continue
        1, 2 => echo "lille {i}"
        3 => { let x = i * 10
            echo "tre {x}" }
        _ => echo "stor {i}"
    }
}')" "lille 1
lille 2
tre 30
stor 4" "match med tal, flere mønstre, blok og _"
check "$(./dsh-hare -e 'let n = "zuzu"
match n {
    "harboiy" => echo "flagermus"
    "zuzu" => echo "zombie"
}
match 9 { 1 => echo "nej" }
echo "slut"')" "zombie
slut" "match med tekst og uden _"
case "$(./dsh-hare -e 'match 1 {
    _ => echo a
    1 => echo b
}' 2>&1)" in *"'_' skal være den sidste"*) ok=$((ok+1));; *) bad=$((bad+1)); echo "✘ match: _ midt i";; esac
tmpd=$(mktemp -d)
mkdir -p "$tmpd/lib"
printf 'let HILSEN = "hej"\nfn dobbelt(x) {\n    return x * 2\n}\nfn del(a, b) {\n    return a / b\n}\n' > "$tmpd/lib/mat.Dash"
printf 'import "lib/mat"\nimport "lib/mat.Dash"\necho "{HILSEN} {dobbelt(21)}"\n' > "$tmpd/hoved.Dash"
check "$(./dsh-hare "$tmpd/hoved.Dash")" "hej 42" "import (og kun én gang)"
printf 'import "lib/mat"\nprint(del(1, 0))\n' > "$tmpd/fejl.Dash"
case "$(./dsh-hare "$tmpd/fejl.Dash" 2>&1)" in *"lib/mat.Dash:6: division med nul"*) ok=$((ok+1));; *) bad=$((bad+1)); echo "✘ import: fejl i den importerede fil";; esac
printf 'import "lib/findes-ikke"\n' > "$tmpd/mangler.Dash"
case "$(./dsh-hare check "$tmpd/mangler.Dash" 2>&1)" in *"kan ikke finde 'lib/findes-ikke'"*) ok=$((ok+1));; *) bad=$((bad+1)); echo "✘ import: mangler";; esac
rm -rf "$tmpd"

# dsh check: den ødelagte fil skal give præcis disse fejl og forslag
out=$(./dsh-hare check tests/ødelagt.Dash 2>&1)
for want in "linje 3: kommandoen '⚡'" "mangler der et # foran" "mangler der et komma i slutningen af linje 11" \
	"mente du 'har_brave'" "er linjen blevet delt" "mente du 'echo'" "mente du 'urls'" "mente du 'len'"; do
	case "$out" in *"$want"*) ok=$((ok+1));; *) bad=$((bad+1)); echo "✘ check mangler: $want";; esac
done
if ./dsh-hare check tests/basis.Dash >/dev/null 2>&1; then ok=$((ok+1)); else bad=$((bad+1)); echo "✘ check fandt fejl i basis.Dash"; fi
# 0.15: bits og bytes
check "$(./dsh-hare -e 'print(0xff, 0b1010, 0xffff_ffff, 0xf0 & 0x3c, 5 ^ 3, 1 << 31, -16 >> 2, ~0, 7 // 2, -7 // 2)')" \
	"255 10 4294967295 48 6 2147483648 -4 -1 3 -3" "hex, bin og bit-operatorer"
check "$(./dsh-hare -e 'print(0x3f & 0x20 == 0x20, 1 + 2 << 3)')" "true 24" "bit-præcedens"
check "$(./dsh-hare -e 'let x = 0x0f
x |= 0x30
x &= 0x3c
x ^= 0xff
print(x, u32(-1), s32(0xffffffff), s16(0x8000), s8(0xff))')" "195 4294967295 -1 -32768 -1" "&= |= ^= og u32/s32/s16/s8"
check "$(./dsh-hare -e 'let m = bytes(16)
wr32(m, 4, 0xdeadbeef)
let n = bytes(8)
copy_bytes(n, 0, m, 4, 4)
fill_bytes(n, 4, 4, 0xaa)
write_bytes("/tmp/dsh-b.bin", n)
print(rd8(m, 4), rd16(m, 4), rd32(m, 4), rd32(read_bytes("/tmp/dsh-b.bin"), 4), read_into(m, 0, "/tmp/dsh-b.bin", 2, 6), rd32(m, 0))')" \
	"239 48879 3735928559 2863311530 6 2863324845" "byte-buffere"
rm -f /tmp/dsh-b.bin
check "$(./dsh-hare -e 'print(rd32(bytes(4), 2))' 2>&1 | head -1 | grep -o 'udenfor bufferen')" "udenfor bufferen" "rd32 udenfor bufferen"
# KATCHA: CPU-testen (load/branch delay, mult/div, lwl/lwr, syscall) kører som rå BIOS
out=$(./dsh-hare eksempler/katcha.Dash --test eksempler/katcha/test/cpu.bin 2>&1)
for want in r3=00000055 r12=00000007 r14=00000003 r15=0000000b r20=fffffffe r23=fffffffd r26=ffffff80 r31=55443322 epc=bfc000ec; do
	case "$out" in *"$want"*) ok=$((ok+1));; *) bad=$((bad+1)); echo "✘ katcha CPU: mangler $want";; esac
done
# KATCHA: GTE — RTPT (perspektiv med Sonys division), NCLIP, AVSZ3, FLAG og ORGB
out=$(./dsh-hare eksempler/katcha.Dash --test eksempler/katcha/test/gte.bin 2>&1)
for want in r4=008100b3 r5=0081008c r6=006e00a0 r7=000003e8 r8=000002e5 r9=000003e7 r10=00000000 r12=000007ff; do
	case "$out" in *"$want"*) ok=$((ok+1));; *) bad=$((bad+1)); echo "✘ katcha GTE: mangler $want";; esac
done
# KATCHA: timer 2 giver afbrydelse ved målet, også uden nulstilling dér
check "$(./dsh-hare eksempler/katcha.Dash --test eksempler/katcha/test/timer.bin 2000000 | grep -oE 'r3=[0-9a-f]+')" "r3=00000003" "katcha: timer-afbrydelse ved mål"
# KATCHA: MDEC melder klar/optaget/klar (så spil ikke venter forgæves)
check "$(./dsh-hare eksempler/katcha.Dash --test eksempler/katcha/test/mdec.bin | grep -oE 'r[456]=[0-9a-f]+' | tr '\n' ' ')" "r4=9000ffff r5=b000000f r6=9000ffff " "katcha: MDEC-status"
# KATCHA: hurtig boot finder \KATCHA\TEST.EXE via SYSTEM.CNF på test-skiven (.cue/.bin og .iso)
for d in cue iso; do
	check "$(./dsh-hare eksempler/katcha.Dash --test eksempler/katcha/test/boot.bin 1000 eksempler/katcha/test/test.$d --hurtig | grep -oE 'r2=[0-9a-f]+ r3=[0-9a-f]+')" "r2=ca7c4a00 r3=12345678" "katcha: hurtig boot fra test.$d"
done
# KATCHA bygget med Violet: VBlank-afbrydelser (i dsh tager det et halvt minut)
if command -v hare >/dev/null 2>&1; then
	ln -sf "$PWD/dsh-hare" /tmp/dsh-test-violet
	if /tmp/dsh-test-violet eksempler/katcha.Dash -o /tmp/dsh-test-katcha >/dev/null 2>&1; then
		check "$(/tmp/dsh-test-katcha --test eksempler/katcha/test/irq.bin 5000000 | grep -o 'r3=[0-9a-f]*')" "r3=00000005" "katcha: 5 VBlank-afbrydelser (Violet)"
		for d in cue iso; do
			check "$(/tmp/dsh-test-katcha --test eksempler/katcha/test/cdread.bin 3000000 eksempler/katcha/test/test.$d | grep -oE 'r4=[0-9a-f]+ r5=[0-9a-f]+ r6=[0-9a-f]+')" "r4=30304443 r5=80000000 r6=00000001" "katcha: CD-drev Setloc/ReadN/DMA3 ($d)"
		done
		check "$(/tmp/dsh-test-katcha --test eksempler/katcha/test/cdplay.bin 20000000 eksempler/katcha/test/lyd.cue | grep -oE 'r4=[0-9a-f]+|r6=[0-9a-f]+' | tr '\n' ' ')" "r4=00010282 r6=00000002 " "katcha: CD-lyd Play + rapport (Violet)"
		check "$(/tmp/dsh-test-katcha --test eksempler/katcha/test/spu.bin 3000000 | grep -oE 'r4=[0-9a-f]+|r5=[0-9a-f]+' | tr '\n' ' ')" "r4=00000001 r5=00000000 " "katcha: SPU spiller ADPCM til ende (ENDX)"
		check "$(/tmp/dsh-test-katcha --test eksempler/katcha/test/cpu.bin)" "$(./dsh-hare eksempler/katcha.Dash --test eksempler/katcha/test/cpu.bin)" "katcha: Violet = dsh"
	else
		bad=$((bad+1)); echo "✘ violet kunne ikke bygge katcha.Dash"
	fi
	rm -f /tmp/dsh-test-violet /tmp/dsh-test-katcha
fi
echo "$ok ok, $bad fejl"
[ "$bad" -eq 0 ]
