# ⚡ Dash

Et script-sprog med superfart — inspireret af Dash Parr. Filerne hedder
`.Dash`, fortolkeren hedder `dsh`. Skrevet i Hare.

```
#!/usr/bin/env dsh-hare
let filer = ["en sang.flac", "to sang.flac"]
for f in filer parallel 4 {
    echo "behandler {f}"
}
let antal = $(ls | wc -l)
try ls /findes/ikke 2> /dev/null
if status != 0 { echo "try fangede det" }
```

## Byg

Kræver Hare 0.25+ og en C-linker (`-lc`).

```
make            # bygger ./dsh-hare
make test       # kører testene
make bench      # måler mod sh
make install    # ~/.local/bin/dsh-hare
```

## Hvorfor hurtig

- **Kompileret Hare**: regning og løkker er ~7× hurtigere end sh.
- **vfork + execve i assembly** (x86_64), præcis som dash, så det er lige så
  billigt at starte en kommando som i sh. Andre CPU'er bruger `posix_spawn`.
- **`parallel`**: hver løber er sin egen proces, ét ord i stedet for `&` og `wait`.
- **Strict som standard**: en kommando der fejler stopper scriptet (brug `try`).
- **Ingen word-splitting**: `$fil` er altid ét argument, også med mellemrum.

## Hvad den kan (v0.3)

Alt fra Python-prototypen — de samme scripts giver det samme output:

- `let`, `=`, `+=` …, `if`/`else if`/`else`, `for … in … [parallel N]`, `while`,
  `break`, `continue`, `fn navn(a, b) { … return … }`
- kommandoer med `|`, `>`, `>>`, `<`, `2>`, `2>>`, `$(…)`, `try`, `fail`,
  `echo`, `cd`, `exit`
- `"…{udtryk}…"`, `$navn`, `${udtryk}`, heltal, kommatal, lister `[…]`,
  maps `{"k": v}`, `l[i] = v`, `m["k"] = v`, `m.k`
- metoder: `.replace .split .trim .upper .lower .contains .starts_with
  .ends_with .lines .repeat .push .pop .join .sort .reverse .map .filter
  .get .has`
- egenskaber: `.len .first .last .name .stem .ext .dir .keys .values`
- funktioner: `print len str int float type range env exists is_dir is_file
  which read write append glob input now sleep round min max abs cwd ask menu progress`

## Nyt i 0.5

```
flatpak run com.brave.Browser $urls &          # baggrund, uden støj i terminalen
if ask("Slet de gamle filer?") { rm -rf $gamle }
let spil = menu(["jade", "bines", "gothecer"], "Vælg et spil")
progress(42, "henter EnderOS...")
```

- `cmd &` starter i baggrunden i sin egen session (som `setsid -f`), og
  output forsvinder — med mindre du selv sender det til en fil.
- `ask(spørgsmål [, standard])` → `true`/`false`. Enter = standard (nej).
- `menu(liste [, titel])` → det valgte element, eller `nil` ved Enter.
- `progress(pct [, tekst])` → bjælken på samme linje, ny linje ved 100.

## Find fejl før du kører

```
dsh check mit-script.Dash
```

Finder *alle* fejl på én gang uden at køre noget — og foreslår rettelser:

```
  ✘ linje 5: kommandoen 'kigger' findes ikke
        5 │ kigger selv efter filerne.
          ↳ ligner almindelig tekst — mangler der et # foran?
  ✘ linje 16: mellemrum i funktionsnavnet
       16 │ fn har _brave() {
          ↳ mente du 'har_brave'?
```

De samme "mente du …?"-forslag kommer også når et script fejler undervejs.

## Violet 💜 — Dash til native kode (trin 1: typer)

Violet er Dash' lillesøster: hun skal oversætte `.Dash` til en rigtig native
binær. Første trin er **type-inferens** — at finde ud af, hvilken type hver
variabel og hver fn har, uden at køre scriptet:

```
dsh types kapløb.Dash      # eller bare: violet kapløb.Dash
💜 violet types kapløb.Dash  (2 gennemløb)
  globalt
    ✔ runder      int
    ✔ gammel      float
  fn løb(hvem: str) → float
    ✔ tider       list[float]
  13 af 15 variabler har én fast type (86%)
```

`✔` betyder én fast type: den kan blive et rent `i64`, `f64` eller en streng i
maskinkoden. `~` betyder at værdien kan være flere ting (fx `str|nil` fra
`env()` eller `num` fra `7 / 2`, der giver 3.5, mens `6 / 3` giver 2), og så
skal Violet bruge en dynamisk værdi dér.

`make install-dsh` laver også `violet` som et link til `dsh`.

## Farver i nano og Kate

```
make install-syntax
```

Nøgleord, strenge, `{udtryk}`, `$variabler` og kommentarer får hver deres
farve — og en linje med en streng der ikke er lukket lyser **rødt**.

## Skift Python-dsh ud

```
make install-dsh     # dsh = Hare-versionen, dsh-py = den gamle
```
