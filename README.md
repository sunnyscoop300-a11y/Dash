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
  which read write append glob input now sleep round min max abs cwd`

## Skift Python-dsh ud

```
make install-dsh     # dsh = Hare-versionen, dsh-py = den gamle
```
