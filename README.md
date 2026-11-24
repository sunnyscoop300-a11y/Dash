# ⚡ Dash

Et script-sprog med superfart — inspireret af Dash Parr. Filerne hedder
`.Dash`, fortolkeren hedder `dsh`. Skrevet i Hare.

🇬🇧 English: [README2.md](README2.md)

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
- kommandoer med `|`, `>`, `>>`, `<`, `2>`, `2>>`, `2>&1`, `&>`, `&>>`, `$(…)`, `&(…)`, `try`, `fail`,
  `echo`, `cd`, `exit`
- `"…{udtryk}…"`, `$navn`, `${udtryk}`, heltal, kommatal, lister `[…]`,
  maps `{"k": v}`, `l[i] = v`, `m["k"] = v`, `m.k`
- metoder: `.replace .split .trim .upper .lower .contains .starts_with
  .ends_with .lines .repeat .push .pop .join .sort .reverse .map .filter
  .get .has`
- egenskaber: `.len .first .last .name .stem .ext .dir .keys .values`
- funktioner: `print len str int float type range env exists is_dir is_file
  which read write append glob input now sleep round min max abs cwd ask menu progress
  wait running`
- Parr: `parr.ln parr.err parr.fmt parr.tabel` og `"{udtryk:spec}"` (se nedenfor)

## Ingen shell inde i Dash

Dash skal ikke have `sh -c "…"` gemt inde i sig. Alt det, man plejede at
hente skallen til, kan Dash selv:

```
try curl -sS $url > svar.json 2> fejl.txt    # stdout og stderr hver for sig
try make > byg.log 2>&1                      # begge i samme fil (eller &> byg.log)
let ud = $(ffmpeg -version 2>&1)             # fang også fejl-output

let job = &(curl -sS -o svar.json $url)      # i baggrunden, men husket
while running(job) {
    progress(...)                            # lav noget imens
    sleep(0.3)
}
let kode = wait(job)                         # exitkoden (sætter også $status)
```

- `&(kommando)` starter kommandoen i baggrunden og giver et job-nummer.
  `running(job)` siger, om den stadig kører; `wait(job)` venter og giver
  exitkoden. Output forsvinder, med mindre du sender det til en fil.
- `kill(job)` stopper jobbet; `kill(job, "STOP")` og `kill(job, "CONT")`
  sætter det på pause og fortsætter.
- `$(try kommando)` giver outputtet, også når kommandoen fejler (`$status`
  har exitkoden), ligesom `try` på en almindelig kommando.
- `dsh check` advarer (⚠) ved `sh -c`, `bash -c` og `zsh -c`. Skal en
  linje med vilje køre i brugerens egen shell, så skriv `# sh-ok` på den.

## match og import (kommer i 0.15 «Flora» 🦇)

**match** vælger en gren efter en værdi — renere end en lang kæde af
`if`/`else if`:

```
match tast {
    "q", "esc" => break
    "left" => x -= 1
    "right" => {
        x += 1
        spil_lyd(trin)
    }
    _ => echo "ukendt tast: {tast}"
}
```

- Flere værdier i én gren adskilles med komma, og en gren er enten én linje
  eller en `{ blok }`.
- **Intervaller**: `0x20..0x3f =>` (begge ender med), også negative tal.
- **Vagter**: `0x03 if not nodisc =>` — grenen bruges kun, hvis betingelsen
  også passer. `_ if x > 9 =>` er en vagt på resten.
- `_` fanger resten og skal stå sidst. Uden `_` sker der bare ingenting,
  hvis intet passer.
- `break`, `continue` og `return` virker inde i grenene.
- **Violet** laver en match på et ✔ heltal eller en ✔ tekst med konstanter
  (og intervaller) om til en rigtig Hare-`switch` (et hop-bord) i stedet for en
  if-kæde. Er der vagter, bliver det en if-kæde.

**import** tager fn'er og variabler med fra en anden `.Dash`-fil:

```
import "lib/farver"          # = lib/farver.Dash ved siden af scriptet
import "~/dash-lib/tekst"

print(farve(3))
```

- Stien regnes fra den fil, der importerer, ellers fra `~/.local/share/dash/lib/`.
- En fil kommer kun med én gang, også hvis flere filer importerer den.
- `import` står i yderste niveau af filen (ikke inde i en fn eller løkke).
- Fejl i en importeret fil peger på den rigtige fil og linje, både i `dsh`,
  `dsh check`, Miguel og programmer bygget med Violet.

**sprint** 💨 er Dash Parrs måde at hente noget på, og gør det samme som
`import` (kommer i 0.17 «Lulu»). Med `sprint` kan navnet stå uden anførselstegn:

```
sprint farver                # = farver.Dash ved siden af scriptet
                             #   eller i ~/.local/share/dash/lib/
sprint "lib/farver"          # en sti skal stadig i "…"
```

`import` virker stadig. Navne uden anførselstegn er kun til `sprint`, fordi
`import billede` også kan være ImageMagicks kommando.

**Edna 👓 — opgradér gamle scripts:** `tools/edna.Dash` syr nye dragter til
gamle scripts, ligesom Edna Mode syr Dashs dragt i De Utrolige: den skriver
gammel syntaks om til ny. Hver gang sproget får noget nyt, kommer der en regel i den (lige nu:
`import "x"` → `sprint x`). Den ændrer kun det, den er sikker på, så fx
`import "skærm.png"` bliver stående.

```
dsh tools/edna.Dash eksempler/            # vis hvad der ville blive ændret
dsh tools/edna.Dash eksempler/ --skriv    # gør det (gammel fil → fil.Dash.før)
```

## Parr 🦸 — formatering og udskrift

Hare har `fmt`, Nim har `echo` — Dash har familien **Parr**:

```
let navn = "Bossun"
let pris = 12.5
parr.ln("pris", pris, true)        # pris 12.5 true   (alle typer, med mellemrum)
parr.err("noget gik galt")         # samme, men til stderr
echo "{navn:<12}|{pris:>8.2}|"     # Bossun      |   12.50|
echo "{255:x} {5:03} {7:b}"        # ff 005 111
echo "{1234567:,} {0.38:%}"        # 1,234,567 38%
let s = parr.fmt(3.14159, ".3")    # "3.142"
parr.tabel([["Navn", "Pris"],
            ["Hirdi", 12.5],
            ["Katcha", 3]])
# Navn    Pris
# Hirdi   12.5
# Katcha     3
```

En spec skrives efter `:` inde i `{…}` (eller som 2. argument til `parr.fmt`):

| spec | betyder |
|---|---|
| `<` `>` `^` | venstre, højre, midt (tal står til højre, tekst til venstre) |
| `8` | mindst 8 tegn bred (æøå tæller som ét tegn) |
| `0` | fyld op med nuller: `{5:03}` → `005` |
| `+` | fortegn også på positive tal |
| `,` | tusindtalsskiller: `1,234,567` |
| `.2` | to decimaler — på tekst: højst 2 tegn |
| `x` `X` `b` `o` | hex, HEX, binær, oktal |
| `%` | procent: `{0.385:.1%}` → `38.5%` |

Et `:` uden en gyldig spec efter er bare almindelig tekst, så `"{navn}: ok"`
virker som før. `parr.tabel` sætter kolonnerne op efter den bredeste celle og
stiller talkolonner til højre. Det hele virker også i Violet.

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

## Miguel 🎸 — hjælp i editoren

Miguel (fra Coco) er Dash' language server. Han spiller med i editoren, mens du
skriver:

- **Fejl og advarsler med det samme** — alt det, `dsh check` finder, med
  "mente du …?" under. ✘ er fejl, ⚠ er advarsler (fx `sh -c`).
- **Autoudfyldning** af nøgleord, funktioner (også JJGui), dine egne variabler
  og funktioner, metoder efter `.` og `parr.ln/err/fmt/tabel` efter `parr.`.
- **Forklaringer**, når musen står over en funktion: `glob("*.flac") — filerne
  der passer, som en liste`.

```
make install-miguel     # dsh + symlinket "miguel" + farver + Kate-opsætning
```

I **Kate**: Indstillinger → LSP-klient skal være slået til (under
Plugins). `make install-miguel` skriver `~/.config/kate/lspclient/settings.json`;
har du den i forvejen, så sæt indholdet af `syntax/miguel-kate.json` ind selv.

I **Neovim** (0.11+):

```lua
vim.filetype.add({ extension = { Dash = "dash" } })
vim.lsp.config("miguel", { cmd = { "miguel" }, filetypes = { "dash" } })
vim.lsp.enable("miguel")
```

I **xed** (der ikke kan LSP) er der et plugin i stedet, som viser fejl og
advarsler fra `dsh check` med bølgestreg, et ikon i kanten og "mente du …?",
når musen står over linjen:

```
make install-xed        # slå det til: Rediger → Indstillinger → Udvidelsesmoduler → Miguel (Dash)
```

Andre editorer: start `miguel` (eller `dsh miguel`) som LSP-server over stdio.

## Violet 💜 — Dash til native kode

Violet er Dash' lillesøster: hun oversætter et `.Dash`-script til en rigtig
native binær. Hun skriver scriptet om til Hare-kode og bygger det med
`hare build` (så Hare skal være installeret):

```
violet kapløb.Dash            # → ./kapløb
violet kapløb.Dash -o løb     # vælg selv navnet
violet kapløb.Dash --strip    # mindre fil (release-tilstand + strip): 1275 → 747 KB
violet run kapløb.Dash        # byg kun hvis scriptet er ændret, og kør binæren
violet kapløb.Dash --arch android   # til telefonen: kører direkte i Termux
violet kapløb.Dash --arch aarch64   # til en Raspberry Pi eller proot-Linux på telefonen
violet types kapløb.Dash      # vis typerne (trin 1)
violet hare kapløb.Dash       # vis den Hare-kode, hun laver
violet prof kapløb.Dash       # kør med profiler: hvor går tiden? (dsh prof = i fortolkeren)
```

(`dsh build`, `dsh types` og `dsh hare` gør det samme.)

**violet prof** bygger scriptet med et målepunkt i hver fn og kører det. Når
programmet slutter (eller du trykker Ctrl+C), skriver den, hvor tiden gik:

```
💜 violet prof  1.18s i alt
  Funktion          Kald     Selv      %    Inkl.  pr. kald
  step()      12.345.678  712.4ms  60.3%    1.02s      58ns
  setr()         705.596   48.9ms   4.1%   48.9ms      69ns
```

*Selv* er tiden i fn'en selv, *Inkl.* med de fn'er, den kalder. Kan scriptet
ikke oversættes, måler `dsh prof` i fortolkeren i stedet.

**violet run** gemmer binæren i `~/.cache/violet/` med et fingeraftryk af
scriptet. Første gang bygger hun (et par sekunder), derefter starter
binæren direkte — et script med en million regnestykker: 271 ms med dsh,
4 ms med `violet run`. Ændrer du scriptet, bygger hun igen af sig selv.
Kan scriptet ikke oversættes, kører dsh det bare. Sæt det i #!-linjen, så
bliver dine scripts native uden at du tænker over det:

```
#!/usr/bin/env violet-run
```

**--arch android** bygger til Termux på en Android-telefon. Android kører
kun programmer gennem sin egen loader (`/system/bin/linker64`), og den kan
ikke starte glibc-programmer. Så Violet bygger uden C-bibliotek — Hare kan
klare sig med rene Linux-systemkald — og linker selv binæren som en PIE med
linker64 som loader. Kommandoer startes med fork + execve. Kræver kun
`aarch64-linux-gnu-binutils`.

**--arch** bygger til en anden processor: `aarch64` (telefoner, Raspberry
Pi) eller `riscv64`. Binæren bliver statisk, så den ikke skal bruge noget
på den anden maskine. Det kræver krydsoversætteren
(`sudo pacman -S aarch64-linux-gnu-gcc`).

**Typerne** bestemmer, hvor hurtig koden bliver. Violet finder typen af hver
variabel uden at køre scriptet:

```
💜 violet types kapløb.Dash  (2 gennemløb)
  globalt
    ✔ runder      int
    ~ ny_dsh      str|nil
  fn løb(hvem: str) → float
    ✔ tider       list[float]
  13 af 15 variabler har én fast type (86%)
```

`✔` bliver et rent `i64`, `f64`, `str` eller `bool` i maskinkoden, og
`for i in range(…)` med et heltal bliver en rigtig maskinløkke. `~` bliver
en dynamisk værdi, som i fortolkeren (fx `str|nil` fra `env()`, eller `num`
fra `7 / 2`, der giver 3.5, mens `6 / 3` giver 2).

Kommandoer, pipes, builtins, `try`, `&`, `parallel` og fejlbeskederne kører
gennem dsh' egen kode, der følger med ind i binæren — så programmet opfører
sig som `dsh`, bare hurtigere:

```
                         sh   dsh-hare     violet
100.000 regnestykker  133 ms     24 ms     1.5 ms
fib(24) (rekursion)       –     63 ms     2.2 ms
1000 kommandoer       973 ms    973 ms     951 ms
```

Det kan Violet ikke endnu (brug `dsh` til de scripts): en fn brugt som værdi
(andet end i `.map(f)`/`.filter(f)`), en fn inde i en fn og `parallel` inde
i `parallel`.

## JJGui 👶⚡ — vinduer og grafik i Dash

JJGui (efter Jack-Jack) giver Dash vinduer, tegning, mus, tastatur og lyd.
Motoren er [ViperGui](https://github.com/sunnyscoop300-a11y/vipergui) (i
`viper/`): Wayland i ren Hare og SDL2 til X11.

```
window("Mit spil", 800, 600)
let pling = sound("sine", 880, 1320, 0.12)
while frame() {
    clear("#202030")
    let m = mouse()
    circle(m[0], m[1], 20, "gold")
    text(20, 20, "Hej fra Dash!", "white", 2)
    if button("Klik", 350, 280) { play(pling) }
    if key("esc") { break }
}
```

| Funktion | Hvad den gør |
|---|---|
| `window(titel, b, h)` | åbner vinduet (ét pr. script) |
| `frame()` | næste billede; `false` når vinduet lukkes |
| `clear(farve)` | fylder hele vinduet |
| `rect`, `outline(x, y, b, h, farve)` | firkant, fyldt / kant |
| `round_rect(x, y, b, h, r, farve)` | firkant med runde hjørner |
| `circle(x, y, r, farve)`, `line(x0, y0, x1, y1, farve)`, `pixel(x, y, farve)` | |
| `polygon([[x, y], …], farve)` | fyldt mangekant |
| `text(x, y, tekst, farve, størrelse)`, `text_width(tekst, størrelse)` | 8×16-skrift, størrelse 1, 2, 3 … |
| `button(tekst, x, y)` | knap; `true` når den bliver klikket |
| `mouse()` → `[x, y]`, `clicked()`, `right_clicked()`, `mouse_down()`, `wheel()` | mus |
| `key(navn)` (holdes nede), `pressed(navn)` (lige trykket), `typed()` | tastatur: `"left"`, `"space"`, `"enter"`, `"esc"`, `"a"`, `"1"`, `"f11"` … |
| `delta()` | sekunder siden sidste billede |
| `width()`, `height()` | vinduets størrelse |
| `image(sti [, b, h])` → nr., `draw(nr, x, y)`, `image_size(nr)` | PNG-billeder |
| `sound(bølge, fra-Hz, til-Hz, sek [, styrke])` → nr., `sound_file(sti.wav)`, `play(nr [, styrke, tonehøjde])` | lyd: `sine`, `square`, `triangle`, `saw`, `noise` |
| `screenshot(sti.png)` | gem billedet |
| `blit(buf, adr, række_bytes, b, h, format, x, y [, w, h])` | pixels fra en `bytes()`-buffer (format 15, 24 eller 32) |
| `stream_pcm(buf, adr, frames)` | lyd fra en `bytes()`-buffer: 16-bit stereo, 44100 Hz (som CD-lyd) |
| `fullscreen(true/false)`, `window_size(b, h)` | fuld skærm og vinduets størrelse; tegnefladen skaleres med (SDL2) |
| `pad_name()`, `pad_button(n)`, `pad_axis(n)` | controller (PS5 DualSense, PS4, Xbox) over Bluetooth/USB via `/dev/input/js*` |

Farver: `"#ff8800"`, `"#f80"`, `0xff8800` eller et navn (`"gold"`, `"red"`, `"lilla"` …).

### 3D

JJGui har også et lille 3D-lag (software, ingen grafikkort nødvendigt):

```
camera(0, 3.3, -6.5, 13)                 # x, y, z, hældning° [, drejning°, synsvinkel°]
fog("#8ccbff", 28, 95)                   # tåge fra 28 til 95 enheder væk (fog() slår den fra)
floor3d(-3.6, 0, 3.6, 100, 0, "#55555f") # vandret flade; 7. argument = lag (striber oven på vejen)
box3d(0, 0, 5, 1, 2, 1, "gold")          # kasse: x/z = midten, y = bunden, b/h/d — med lys og skygge
circle3d(0, 1, 8, 0.35, "gold", "P")     # cirkel (med tekst), der altid vender mod kameraet
let s = project(0, 1, 8)                 # [skærm-x, skærm-y, skala] eller nil
render3d()                               # tegner det hele, forreste forrest
```

y peger op og z ind i skærmen. Tegn HUD (tekst, knapper) efter `render3d()`.

Nye matematik-funktioner: `sin`, `cos`, `sqrt`, `floor`, `random()` (0-1),
`random(n)` (0..n-1) og `random(a, b)` (a..b).

**Eksempel:** `eksempler/cube-runner.Dash` — *Cube Head Runners*, et 3D-løbespil
med tre baner, hop, glid, tog, bananskræller, P'er og en P STORE med outfits.
Kører med `dsh` (~50 fps) og hurtigere bygget med Violet.

**Eksempel:** `eksempler/boxman.Dash` — *Boxman*, et 2D-skubbespil: skub kasserne
hen på de gule mål. 20 baner (alle tjekket løsbare, 2-42 træk) + 25 julebaner, fortryd (Z),
rekorder pr. bane og touch-styring.

**Eksempel:** `eksempler/serietracker.Dash` — en tracker til en series afsnit:
set/ikke set, stjerner, næste afsnit og fremgang. Seriens data ligger i din
egen fil (`titel=…` og `S1E1|Titel|dato|beskrivelse`), ikke i koden.

**Eksempel:** `eksempler/nonbiri.Dash` — *Nonbiri* 🌾, en MP3/FLAC-afspiller i
stemningen fra Farming Life in Another World: solen følger sangen over himlen,
og afgrøderne på marken vokser, mens den spiller (klik på marken for at spole).
Søgning (`/`), bland, gentag, lydstyrke og cover fra filen eller `cover.jpg`.
Knappen **Mappe** (eller `o`) vælger musikmappen, og den huskes til næste gang.
Afspiller med `mpv` (eller `ffplay`), læser tags med `ffprobe`.

```
dsh eksempler/nonbiri.Dash ~/Musik
```

**Eksempel:** `eksempler/boxdog.Dash` — *BoxDog* 🐶📦, en hundehvalp med rødt
halstørklæde skubber kasser hen på pote-felterne på lageret. 16 baner i tre
lagerhaller (alle tjekket løsbare), fortryd, rekorder, lyd og touch.

**Eksempel:** `eksempler/fishout.Dash` — *FISH OUT* 🎣, et lille pixel-fiskespil:
sejl båden, sænk krogen og fang så mange fisk du kan på 60 sekunder. Guldfisk giver
100, støvler trækker fra. Det er også en test af det nye i Dash: modulerne i
`eksempler/fishout/` hentes med `sprint`, og fiskene vælges med `match`-intervaller
og en vagt for den sjældne guldfisk.

**Eksempel:** `eksempler/zuzubox.Dash` — *ZuzuBox* 💀📦, zombiepigen Zuzu
skubber kasser hen på de grønne kranier i en lilla krypt. 55 baner i ti krypter,
to af dem med gargoiler der står i vejen. Grafikken er klippet ud af mockuppen
med `eksempler/zuzubox/klip.py`.

**Eksempel:** `eksempler/wt-mini.Dash` — *WT Mini* 🟢, læs WEBTOON i Dash: ugedagens
serier som covers, klik for kapitlerne og læs dem som én lang stribe. Følg dine serier
under *Min liste*. Hjælperen `eksempler/wt-mini/hent.Dash` er også ren Dash: den henter
med `curl` og laver billederne om til PNG med ImageMagick i baggrunden.

**Eksempel:** `eksempler/sj-mini.Dash` — *SJ Mini*, de nyeste kapitler fra
MANGA Plus: klik på et cover for kapitlerne og læs dem som én lang stribe.
Hjælperen `eksempler/sj.py` (python3 + pillow) henter listen, kapitlerne og
siderne. Højreklik eller stjernen gør en serie til favorit.

**Eksempel:** `eksempler/bob.Dash` — *Bobs butik*, en lille app-butik til dine
egne Dash-programmer og spil. Bob finder `.Dash`-filerne i `~/Dash/eksempler`
(eller `BOB_KILDER`), bygger dem med Violet til `~/.local/bin` og laver en
genvej i menuen. Den kan også opdatere (når kildekoden er ændret) og fjerne.
Fanen **System** viser de opdateringer, der venter (pacman, AUR, apt, dnf,
zypper, xbps, flatpak og snap), og opdaterer Linux'en i terminalen.
Et program beskriver sig selv med `# bob-navn:`, `# bob-kategori:`,
`# bob-farve:` og `# bob-om:` øverst i filen.

Se `eksempler/jj-demo.Dash`. `make NOJJ=1` bygger dsh uden JJGui,
`make HARE_ONLY=1` uden SDL2.

Motoren finder selv en skærm: Wayland (ren Hare), ellers SDL2, ellers **X11 i ren
Hare** (`VIPER_BACKEND=wayland|sdl|x11` tvinger et valg).

### JJGui på telefonen (Termux:X11)

Violet kan bygge JJGui-scripts til telefonen. De bruger X11-delen i ren Hare og
åbner et rigtigt vindue i appen **Termux:X11** — touch virker som museklik, og
vinduet zoomes op, så det fylder skærmen (`VIPER_SCALE=2` vælger selv zoom):

```
# på pc'en
violet spil.Dash --arch android -o spil
# i Termux (med Termux:X11-appen installeret)
pkg install x11-repo && pkg install termux-x11
termux-x11 :0 &
DISPLAY=:0 ./spil
```

## Bits og bytes 🧮 — til emulatorer og filformater

Heltal kan skrives i hex og binært, og Dash har bit-operatorerne:

```
let op = 0x8c42_0004
let rt = (op >> 16) & 0x1f              # & | ^ << >> ~
if op & 0x3f == 0x20 { echo "ADD" }     # & binder stærkere end ==
let flag = 0b1010
flag |= 0b0001                          # &= |= ^=
echo "{7 // 2} {-7 // 2}"               # 3 -3: // skærer decimalerne væk
echo "{u32(-1):x} {s16(0x8000)}"        # ffffffff -32768
```

Rækkefølgen er `|` < `^` < `&` < `<<` `>>` < `+` `-`, og alle binder stærkere
end `==` og `<` (som i Python). Skiftet tager antallet modulo 64.

**Byte-buffere** er numre, ligesom billeder og lyde, så Violet kan gøre
`rd32`/`wr32` til direkte maskinkode:

| Funktion | Hvad den gør |
|---|---|
| `bytes(n)` → nr. | en buffer med n nul-bytes |
| `rd8/rd16/rd32(buf, adr)` | læs 1, 2 eller 4 bytes (little-endian) |
| `wr8/wr16/wr32(buf, adr, v)` | skriv |
| `read_bytes(sti [, adr, n])` → nr. | en fil (eller en bid af den) |
| `read_into(buf, buf_adr, sti, fil_adr, n)` | læs ind i en buffer, fx én CD-sektor; giver antal bytes |
| `write_bytes(sti, buf [, adr, n])` | gem en buffer |
| `copy_bytes(til, til_adr, fra, fra_adr, n)`, `fill_bytes(buf, adr, n, v)` | kopiér og fyld |
| `bytes_len(buf)`, `free_bytes(buf)` | størrelse, giv hukommelsen tilbage |
| `u32(x)`, `s32(x)`, `s16(x)`, `s8(x)` | klip et tal til 32/16/8 bit |

I JJGui tegner `blit(buf, adr, række_bytes, bredde, højde, format, x, y [, w, h])`
pixels direkte fra en buffer — format 15 (PS1-VRAM), 24 (RGB) eller 32 — og
skalerer dem til `w`×`h`. Det er sådan **KATCHA** (`eksempler/katcha.Dash`),
PS1-emulatoren i ren Dash, viser skærmen.
## Nyt i 0.16 «Zabuton» 🕷️

Zabuton er kæmpeedderkoppen i Farming Life in Another World, der væver alt
tøjet til landsbyen. Næste version bliver «Lulu».

- **match med intervaller og vagter**: `0x20..0x3f =>` (begge ender med) og
  `0x03 if not nodisc =>`. Violet laver stadig intervaller om til en `switch`.
- **violet prof / dsh prof**: kør et script og se, hvor tiden går — kald,
  *Selv*-tid og *Inkl.*-tid for hver fn. Ctrl+C viser også tabellen.
- **violet run** bygger om, når en importeret fil eller selve dsh er ændret.
- Kan Violet ikke oversætte et script med `import`, indlæser dsh nu de
  importerede filer rigtigt, når den tager over.
- **KATCHA** er blevet hurtigere (CPU-løkken uden små fn-kald) og tegner
  polygoner efter PS1'ens top-venstre-regel — ingen streger ved kanterne.

## Nyt i 0.15 «Flora» 🦇

Flora er Lulus kusine i Farming Life in Another World — vampyren med alle
eksperimenterne. Næste version bliver «Zabuton».

- **match**: vælg en gren efter en værdi (`1, 2 => …`, `"a" => { … }`, `_ => …`).
  Violet laver match på heltal og tekst om til en rigtig Hare-`switch`.
- **import**: tag fn'er og variabler med fra en anden `.Dash`-fil. Fejl peger
  på den rigtige fil og linje.
- **Bits og bytes**: `& | ^ << >> ~ //`, `0x`/`0b`-tal og `bytes()`-buffere
  med `rd8/16/32` og `wr8/16/32`, som Violet gør til direkte maskinkode.
- **JJGui**: `blit()` tegner pixels direkte fra en buffer, `stream_pcm()`
  spiller lyd fra en buffer, og gamepads (PS5 DualSense, PS4, Xbox) virker
  via `pad_name`, `pad_button` og `pad_axis`.
- **Miguel 🎸**: hjælp i editoren — language server til Kate, VS Code og
  Neovim, og et plugin til xed.
- **KATCHA** (`eksempler/katcha.Dash`): en PlayStation 1-emulator skrevet i
  ren Dash.

## Nyt i 0.14 «Kuro» 🐺

Kuro er Hirakus første ven i Farming Life in Another World, den sorte ulv.
Næste version bliver «Flora».

- **Ingen shell inde i Dash:** `2>&1` og `&>` virker direkte på kommandoer, og
  `dsh check` advarer, hvis et script kalder `sh -c` eller `bash -c`.
- **Jobs i baggrunden:** `let j = &( kommando )` starter et job, og
  `running(j)`, `wait(j)` og `kill(j)` styrer det. Jobs dør sammen med
  scriptet, så der ikke ligger forældreløse processer tilbage.
- **`$(try …)`** fanger output fra en kommando, der må fejle, og `status`
  fortæller bagefter, hvordan det gik.
- **Parr 🦸:** `parr.ln`, `parr.err`, `parr.fmt` og `parr.tabel` — formatering
  ligesom Hares `fmt` og Nims `echo`.
- **Format i strenge:** `"{x:spec}"` med `<`, `>`, `^`, `+`, `0`, bredde,
  `,` (tusindtal), `.præcision` og `x X b o % s`, fx `"{pris:>8.2}"`.
- **Nye spil og apps i Bob:** ZuzuBox (zombiepigen Zuzu og flagermuspigen
  Harboiy, med tre temaer — normal, efterår og jul — en november-nedtælling og
  en julekalender) og BoxDog.

## Nyt i 0.13 «Hiraku» 🌾

Fra nu af får hver version et navn fra Farming Life in Another World
(`dsh --version`). Næste bliver «Kuro».

- `"tekst".chars` → bogstaverne som en liste — æ, ø og å tæller som ét
  bogstav (`s[i]` og `.len` tæller bytes).
- JJGui-farver kan være gennemsigtige: `"#rrggbbaa"`, fx `"#00000060"` til en
  skygge.
- **Tekstfelter med kopiér og indsæt:** `textbox("navn", x, y, bredde, {valg})`
  giver et rigtigt tekstfelt: markør, markering med musen (træk eller
  dobbeltklik), Shift+pile, Home/End/Delete, Ctrl+A/C/X/V og en højreklik-menu
  (Klip, Kopiér, Indsæt, Markér alt). `focused("navn")`, `submitted("navn")`
  (Enter) og `textbox_set("navn", "tekst", fokus)`. Valg: `tom`, `skjul`
  (adgangskode), `h`, `r`, `maks`, `aktiv`, `indryk` og farverne `bund`, `tekst`, `kant`,
  `fokus`, `markering`, `dæmp`.
- `draw(nr, x, y, bredde, højde)` tegner et billede i en anden størrelse
  (bilineært, så det er glat), fx til zoom. `key()` kender nu også `"ctrl"`,
  `"shift"`, `"alt"`, `"home"`, `"end"`, `"delete"`, `"pageup"` og `"pagedown"`.
- **SJ Mini** kan zoome: Ctrl + scrollhjul (eller + / - / 0), og træk med
  musen flytter siden.
- **Udklipsholderen:** `clipboard()` og `set_clipboard("tekst")` bruger
  `wl-copy`/`wl-paste`, `xclip`, `xsel` eller Termux, så man kan kopiere
  mellem Dash-apps og alt andet.
- **Egne logoer:** hver app har sit logo i `eksempler/ikoner/<app>.png`
  (tegnet med JJGui af `ikoner/tegn-ikoner.Dash`). JJGui giver vinduet app id
  `dash-<app>` og finder selv logoet, og Bob lægger det i menuen.
  `window_icon("logo.png")` sætter et ikon i hånden.
- `free_image(nr)` giver et billedes hukommelse tilbage i JJGui (nummeret
  genbruges af næste `image()`), og maps har fået `.remove(nøgle)`.
- Boxman har fået 25 julebaner med snemand, og Nonbiri er kommet til.

## Farver i nano, Kate og xed

```
make install-syntax
```

Virker i nano, Kate/KWrite og xed/gedit/Pluma (GtkSourceView — genstart
xed bagefter). Nøgleord, strenge, `{udtryk}`, `$variabler` og kommentarer får hver deres
farve — og en linje med en streng der ikke er lukket lyser **rødt**.

## Skift Python-dsh ud

```
make install-dsh     # dsh = Hare-versionen, dsh-py = den gamle
```
