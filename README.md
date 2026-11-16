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

## Hvad v0.2 kan

`let`, `=`, `+=`, `if`/`else if`/`else`, `for … in … [parallel N]`, `while`,
`break`, `continue`, `try`, `fail`, `echo`, `cd`, `exit`, kommandoer med
pipes `|` og `>`, `>>`, `<`, `2>`, `2>>`, `$(…)`, `"…{udtryk}…"`, `$navn`,
`${udtryk}`, lister `[…]`, `.len`/`.first`/`.last`, indeks `l[0]`, heltal,
`and`/`or`/`not`.

Indbygget: `print()`, `len()`, `str()`, `int()`, `type()`, `range()`,
`env()`, `exists()`, `which()`, `now()`.

**Mangler endnu** (findes i Python-prototypen): `fn`, metoder som
`.replace()`/`.split()`/`.push()`, `glob()`, `read()`/`write()`, `input()`,
kommatal og maps.
