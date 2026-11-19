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
```

(`dsh build`, `dsh types` og `dsh hare` gør det samme.)

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
| `key(navn)` (holdes nede), `pressed(navn)` (lige trykket), `typed()` | tastatur: `"left"`, `"space"`, `"enter"`, `"esc"`, `"a"` … |
| `delta()` | sekunder siden sidste billede |
| `width()`, `height()` | vinduets størrelse |
| `image(sti [, b, h])` → nr., `draw(nr, x, y)`, `image_size(nr)` | PNG-billeder |
| `sound(bølge, fra-Hz, til-Hz, sek [, styrke])` → nr., `sound_file(sti.wav)`, `play(nr [, styrke, tonehøjde])` | lyd: `sine`, `square`, `triangle`, `saw`, `noise` |
| `screenshot(sti.png)` | gem billedet |

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

**Eksempel:** `eksempler/sj-mini.Dash` — *SJ Mini*, de nyeste kapitler fra
MANGA Plus: klik på et cover for kapitlerne og læs dem som én lang stribe.
Hjælperen `eksempler/sj.py` (python3 + pillow) henter listen, kapitlerne og
siderne. Højreklik eller stjernen gør en serie til favorit.

**Eksempel:** `eksempler/bob.Dash` — *Bobs butik*, en lille app-butik til dine
egne Dash-programmer og spil. Bob finder `.Dash`-filerne i `~/Dash/eksempler`
(eller `BOB_KILDER`), bygger dem med Violet til `~/.local/bin` og laver en
genvej i menuen. Den kan også opdatere (når kildekoden er ændret) og fjerne.
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
