# ⚡ Dash

A script language with super speed — inspired by Dash Parr. Files are called
`.Dash`, the interpreter is called `dsh`. Written in [Hare](https://harelang.org).

> 🇩🇰 Dash is made in Denmark. The keywords and functions are English, but
> error messages, comments and the example programs are mostly in Danish.
> The original README is [README.md](README.md) (Danish).


## New in 0.16 «Zabuton» 🕷️

Zabuton is the giant spider in Farming Life in Another World who weaves all the
village's clothes. The next version will be «Lulu».

- **match ranges and guards** — `0x20..0x3f =>` (inclusive) and `0x03 if not nodisc =>`.
- **violet prof / dsh prof** — calls, self time and inclusive time per fn; Ctrl+C prints it too.
- **violet run** rebuilds when an imported file or dsh itself changes.
- When Violet can't compile a script that uses `import`, dsh now loads the imports properly.
- **KATCHA** — a faster CPU loop and PS1 top-left fill rule for polygons (no edge streaks).

## New in 0.15 «Flora» 🦇

Flora is Lulu's cousin in Farming Life in Another World — the vampire with all
the experiments. The next version will be «Zabuton».

- **match** — pick a branch by value; Violet turns int/str matches into a Hare `switch`.
- **import** — bring in functions and variables from another `.Dash` file.
- **Bits and bytes** — `& | ^ << >> ~ //`, `0x`/`0b` numbers and `bytes()` buffers.
- **JJGui** — `blit()`, `stream_pcm()` and gamepads (`pad_name/button/axis`).
- **Miguel 🎸** — language server for Kate, VS Code and Neovim, plus a xed plugin.
- **KATCHA** — a PlayStation 1 emulator written in pure Dash.

```
#!/usr/bin/env dsh
let files = ["one song.flac", "two song.flac"]
for f in files parallel 4 {
    echo "processing {f}"
}
let count = $(ls | wc -l)
try ls /does/not/exist 2> /dev/null
if status != 0 { echo "try caught it" }
```

Every version gets a code name from *Farming Life in Another World*. The
current one is **0.16 «Zabuton»** 🕷️ (`dsh --version`); the next will be «Lulu».

## Build

Needs Hare 0.25+ and a C linker (`-lc`). JJGui (graphics) uses SDL2 or pure-Hare
Wayland/X11.

```
make                # builds ./dsh-hare
make test           # runs the tests
make bench          # compares with sh
make install-dsh    # installs as ~/.local/bin/dsh (+ violet, violet-run)
make install-syntax # syntax colours for nano, Kate and xed/gedit/Pluma
```

## Why it is fast

- **Compiled Hare**: arithmetic and loops are ~7× faster than sh.
- **vfork + execve in assembly** (x86_64), just like dash, so starting a
  command is as cheap as in sh. Other CPUs use `posix_spawn`.
- **`parallel`**: every runner is its own process — one word instead of `&` and `wait`.
- **Strict by default**: a failing command stops the script (use `try`).
- **No word splitting**: `$file` is always one argument, even with spaces.

## What it can do

- `let`, `=`, `+=` …, `if`/`else if`/`else`, `for … in … [parallel N]`, `while`,
  `break`, `continue`, `fn name(a, b) { … return … }`
- commands with `|`, `>`, `>>`, `<`, `2>`, `2>>`, `2>&1`, `&>`, `&>>`, `$(…)`,
  `&(…)`, `try`, `fail`, `echo`, `cd`, `exit`
- `"…{expression}…"`, `$name`, `${expression}`, integers, floats, lists `[…]`,
  maps `{"k": v}`, `l[i] = v`, `m["k"] = v`, `m.k`
- methods: `.replace .split .trim .upper .lower .contains .starts_with
  .ends_with .lines .repeat .push .pop .join .sort .reverse .map .filter
  .get .has .remove`
- properties: `.len .first .last .name .stem .ext .dir .keys .values .chars`
- functions: `print len str int float type range env exists is_dir is_file
  which read write append glob input now sleep round min max abs cwd ask menu
  progress wait running kill sin cos sqrt floor random`
- Parr: `parr.ln parr.err parr.fmt parr.tabel` and `"{expression:spec}"` (see below)
- bits and bytes: `0xff`, `0b1010`, `& | ^ << >> ~ //`, `bytes rd8..rd32 wr8..wr32 read_bytes`
  … (see below)

Note: functions are not hoisted — define a `fn` before you call it.

## No shell inside Dash

Dash should not hide `sh -c "…"` inside itself. Everything you used to call
the shell for, Dash can do on its own:

```
try curl -sS $url > answer.json 2> errors.txt   # stdout and stderr separately
try make > build.log 2>&1                       # both in one file (or &> build.log)
let out = $(ffmpeg -version 2>&1)               # also capture error output

let job = &(curl -sS -o answer.json $url)       # in the background, but remembered
while running(job) {
    progress(...)                               # do something meanwhile
    sleep(0.3)
}
let code = wait(job)                            # the exit code (also sets $status)
```

- `&(command)` starts the command in the background and returns a job number.
  `running(job)` tells whether it is still running; `wait(job)` waits and
  returns the exit code. Output is discarded unless you redirect it. Jobs die
  together with the script, so no orphan processes are left behind.
- `kill(job)` stops the job; `kill(job, "STOP")` and `kill(job, "CONT")`
  pause and resume it.
- `$(try command)` returns the output even when the command fails (`$status`
  has the exit code), just like `try` on a normal command.
- `cmd &` starts a command detached in its own session (like `setsid -f`).
- `dsh check` warns (⚠) about `sh -c`, `bash -c` and `zsh -c`. If a line
  really should run in the user's own shell, put `# sh-ok` on it.

## match and import (coming in 0.15 «Flora» 🦇)

**match** picks a branch by value — cleaner than a long `if`/`else if` chain:

```
match key {
    "q", "esc" => break
    "left" => x -= 1
    "right" => {
        x += 1
        play(step)
    }
    _ => echo "unknown key: {key}"
}
```

- Several values in one branch are separated by commas; a branch is one line
  or a `{ block }`.
- **Ranges**: `0x20..0x3f =>` (both ends included), negative numbers too.
- **Guards**: `0x03 if not nodisc =>` — the branch is only taken if the
  condition holds as well. `_ if x > 9 =>` guards the rest.
- `_` catches the rest and must come last. Without `_`, nothing happens when
  nothing matches.
- `break`, `continue` and `return` work inside the branches.
- **Violet** turns a match on a ✔ int or ✔ str with constant patterns into a
  real Hare `switch` (a jump table) instead of an if chain — ranges too.
  With guards it becomes an if chain.

**import** brings in the functions and variables of another `.Dash` file:

```
import "lib/colours"         # = lib/colours.Dash next to the script
import "~/dash-lib/text"
```

- Paths are relative to the importing file, then `~/.local/share/dash/lib/`.
- A file is only included once, even if several files import it.
- `import` goes at the top level of a file (not inside a fn or loop).
- Errors inside an imported file point to the right file and line — in `dsh`,
  `dsh check`, Miguel and Violet-built programs.

**sprint** 💨 is Dash Parr's way of fetching things and does the same as
`import` (coming in 0.17 «Lulu»). With `sprint` the name can go without quotes:

```
sprint colours               # = colours.Dash next to the script
                             #   or in ~/.local/share/dash/lib/
sprint "lib/colours"         # a path still needs "…"
```

`import` still works. Bare names are only for `sprint`, because
`import picture` may also be ImageMagick's command.

**Upgrade old scripts:** `tools/opgrader.Dash` rewrites old syntax into new.
Every time the language gets something new, it gets a rule (right now:
`import "x"` → `sprint x`). It only changes what it is sure about, so e.g.
`import "screen.png"` is left alone.

```
dsh tools/opgrader.Dash examples/            # show what would change
dsh tools/opgrader.Dash examples/ --skriv    # do it (old file → file.Dash.før)
```

## Parr 🦸 — formatting and printing

Hare has `fmt`, Nim has `echo` — Dash has the **Parr** family:

```
let name = "Bossun"
let price = 12.5
parr.ln("price", price, true)        # price 12.5 true   (any types, space separated)
parr.err("something went wrong")     # the same, but to stderr
echo "{name:<12}|{price:>8.2}|"      # Bossun      |   12.50|
echo "{255:x} {5:03} {7:b}"          # ff 005 111
echo "{1234567:,} {0.38:%}"          # 1,234,567 38%
let s = parr.fmt(3.14159, ".3")      # "3.142"
parr.tabel([["Name", "Price"],
            ["Hirdi", 12.5],
            ["Katcha", 3]])
# Name    Price
# Hirdi    12.5
# Katcha      3
```

A spec goes after `:` inside `{…}` (or as the 2nd argument to `parr.fmt`):

| spec | meaning |
|---|---|
| `<` `>` `^` | left, right, centre (numbers default right, text left) |
| `8` | at least 8 characters wide (æ, ø, å count as one) |
| `0` | pad with zeros: `{5:03}` → `005` |
| `+` | sign on positive numbers too |
| `,` | thousands separator: `1,234,567` |
| `.2` | two decimals — on text: at most 2 characters |
| `x` `X` `b` `o` | hex, HEX, binary, octal |
| `%` | percent: `{0.385:.1%}` → `38.5%` |

A `:` without a valid spec after it is plain text, so `"{name}: ok"` still
works. `parr.tabel` sizes the columns to the widest cell and right-aligns
number columns. It all works in Violet too.

## Terminal helpers

```
if ask("Delete the old files?") { rm -rf $old }
let game = menu(["jade", "bines", "gothecer"], "Pick a game")
progress(42, "downloading EnderOS...")
```

- `ask(question [, default])` → `true`/`false`. Enter = default (no).
- `menu(list [, title])` → the chosen element, or `nil` on Enter.
- `progress(pct [, text])` → a bar on the same line, new line at 100.

## Find errors before you run

```
dsh check my-script.Dash
```

Finds *all* errors at once without running anything — and suggests fixes
(messages are in Danish):

```
  ✘ linje 5: kommandoen 'kigger' findes ikke
        5 │ kigger selv efter filerne.
          ↳ ligner almindelig tekst — mangler der et # foran?
  ✘ linje 16: mellemrum i funktionsnavnet
       16 │ fn har _brave() {
          ↳ mente du 'har_brave'?
```

(*"the command 'kigger' does not exist — looks like plain text, is a # missing?"*,
*"space in the function name — did you mean 'har_brave'?"*). The same
"did you mean …?" hints also appear when a script fails while running.

## Miguel 🎸 — help in the editor

Miguel (from Coco) is Dash's language server. He plays along in your editor
while you type:

- **Errors and warnings right away** — everything `dsh check` finds, with the
  "did you mean …?" hint underneath (messages in Danish).
- **Completion** of keywords, functions (JJGui too), your own variables and
  functions, methods after `.` and `parr.ln/err/fmt/tabel` after `parr.`.
- **Hover** help for the built-in functions.

```
make install-miguel     # dsh + the "miguel" symlink + syntax colours + Kate setup
```

**Kate**: enable the LSP Client plugin. `make install-miguel` writes
`~/.config/kate/lspclient/settings.json`; if you already have one, paste the
contents of `syntax/miguel-kate.json` into it.

**Neovim** (0.11+):

```lua
vim.filetype.add({ extension = { Dash = "dash" } })
vim.lsp.config("miguel", { cmd = { "miguel" }, filetypes = { "dash" } })
vim.lsp.enable("miguel")
```

**xed** (no LSP support) gets a plugin instead, which shows the errors and
warnings from `dsh check` with squiggles, a gutter icon and the "did you mean
…?" hint on hover:

```
make install-xed        # enable it: Edit → Preferences → Plugins → Miguel (Dash)
```

Other editors: run `miguel` (or `dsh miguel`) as an LSP server over stdio.

## Violet 💜 — Dash to native code

Violet is Dash's little sister: she translates a `.Dash` script into a real
native binary. She rewrites the script as Hare code and builds it with
`hare build` (so Hare must be installed):

```
violet race.Dash                 # → ./race
violet race.Dash -o run          # choose the name
violet race.Dash --strip         # smaller file (release mode + strip)
violet run race.Dash             # build only if the script changed, then run
violet race.Dash --arch android  # for the phone: runs directly in Termux
violet race.Dash --arch aarch64  # for a Raspberry Pi or proot Linux on a phone
violet types race.Dash           # show the inferred types
violet hare race.Dash            # show the Hare code she generates
violet prof race.Dash            # run with a profiler: where does the time go? (dsh prof = interpreter)
```

(`dsh build`, `dsh types` and `dsh hare` do the same.)

**violet prof** builds the script with a probe in every fn and runs it. When the
program ends (or you press Ctrl+C) it prints where the time went:

```
💜 violet prof  1.18s total
  Funktion          Kald     Selv      %    Inkl.  pr. kald
  step()      12.345.678  712.4ms  60.3%    1.02s      58ns
```

*Selv* (self) is time inside the fn itself, *Inkl.* includes the fns it calls.
If the script can't be compiled, `dsh prof` measures in the interpreter instead.

**violet run** caches the binary in `~/.cache/violet/` with a fingerprint of
the script. The first run builds (a few seconds); after that the binary starts
directly — a script with a million calculations: 271 ms with dsh, 4 ms with
`violet run`. Change the script and she rebuilds by herself. If a script
cannot be translated, dsh simply runs it. Put it in the #! line and your
scripts become native without you thinking about it:

```
#!/usr/bin/env violet-run
```

**--arch android** builds for Termux on an Android phone. Android only runs
programs through its own loader (`/system/bin/linker64`), which cannot start
glibc programs. So Violet builds without a C library — Hare can live on plain
Linux syscalls — and links the binary herself as a PIE with linker64 as the
loader. Needs only `aarch64-linux-gnu-binutils`.

**--arch** builds for another CPU: `aarch64` (phones, Raspberry Pi) or
`riscv64`. The binary is static, so it needs nothing on the other machine.
Needs the cross compiler (e.g. `sudo pacman -S aarch64-linux-gnu-gcc`).

**Types** decide how fast the code gets. Violet infers the type of every
variable without running the script:

```
💜 violet types race.Dash  (2 passes)
  global
    ✔ rounds      int
    ~ new_dsh     str|nil
  fn run(who: str) → float
    ✔ times       list[float]
  13 of 15 variables have one fixed type (86%)
```

`✔` becomes a plain `i64`, `f64`, `str` or `bool` in machine code, and
`for i in range(…)` over an integer becomes a real machine loop. `~` becomes a
dynamic value, as in the interpreter.

Commands, pipes, builtins, `try`, `&`, `parallel` and the error messages run
through dsh's own code, which is embedded in the binary — so the program
behaves like `dsh`, only faster:

```
                         sh   dsh-hare     violet
100,000 calculations  133 ms     24 ms     1.5 ms
fib(24) (recursion)       –     63 ms     2.2 ms
1000 commands         973 ms    973 ms     951 ms
```

Not supported by Violet yet (use `dsh` for those scripts): a fn used as a value
(other than in `.map(f)`/`.filter(f)`), a fn inside a fn, and `parallel`
inside `parallel`.

## JJGui 👶⚡ — windows and graphics in Dash

JJGui (after Jack-Jack) gives Dash windows, drawing, mouse, keyboard and sound.
The engine is [ViperGui](https://github.com/sunnyscoop300-a11y/vipergui) (in
`viper/`): Wayland in pure Hare, X11 in pure Hare, or SDL2
(`VIPER_BACKEND=wayland|sdl|x11` forces a choice).

```
window("My game", 800, 600)
let ping = sound("sine", 880, 1320, 0.12)
while frame() {
    clear("#202030")
    let m = mouse()
    circle(m[0], m[1], 20, "gold")
    text(20, 20, "Hello from Dash!", "white", 2)
    if button("Click", 350, 280) { play(ping) }
    if key("esc") { break }
}
```

| Function | What it does |
|---|---|
| `window(title, w, h)` | opens the window (one per script) |
| `frame()` | next frame; `false` when the window closes |
| `clear(colour)` | fills the whole window |
| `rect`, `outline(x, y, w, h, colour)` | rectangle, filled / outline |
| `round_rect(x, y, w, h, r, colour)` | rectangle with rounded corners |
| `circle(x, y, r, colour)`, `line(x0, y0, x1, y1, colour)`, `pixel(x, y, colour)` | |
| `polygon([[x, y], …], colour)` | filled polygon |
| `text(x, y, text, colour, size)`, `text_width(text, size)` | 8×16 font, size 1, 2, 3 … |
| `button(text, x, y)` | button; `true` when clicked |
| `textbox(name, x, y, width, {options})` | real text field with selection, Ctrl+A/C/X/V and a right-click menu |
| `mouse()` → `[x, y]`, `clicked()`, `right_clicked()`, `mouse_down()`, `wheel()` | mouse |
| `key(name)` (held), `pressed(name)` (just pressed), `typed()` | keyboard: `"left"`, `"space"`, `"enter"`, `"esc"`, `"ctrl"`, `"a"`, `"1"`, `"f11"` … |
| `delta()` | seconds since the last frame |
| `width()`, `height()` | window size |
| `image(path [, w, h])` → nr, `draw(nr, x, y [, w, h])`, `image_size(nr)`, `free_image(nr)` | PNG images (scaled smoothly) |
| `sound(wave, from-Hz, to-Hz, sec [, volume])` → nr, `sound_file(path.wav)`, `play(nr [, volume, pitch])` | sound: `sine`, `square`, `triangle`, `saw`, `noise` |
| `clipboard()`, `set_clipboard(text)` | the system clipboard |
| `window_icon(path.png)`, `screenshot(path.png)` | window icon, save a screenshot |
| `blit(buf, addr, row_bytes, w, h, format, x, y [, w, h])` | pixels from a `bytes()` buffer (format 15, 24 or 32) |
| `stream_pcm(buf, addr, frames)` | sound from a `bytes()` buffer: 16-bit stereo, 44100 Hz (like CD audio) |
| `fullscreen(true/false)`, `window_size(w, h)` | full screen and the window's size; the canvas is scaled along (SDL2) |
| `pad_name()`, `pad_button(n)`, `pad_axis(n)` | gamepad (PS5 DualSense, PS4, Xbox) over Bluetooth/USB via `/dev/input/js*` |

Colours: `"#ff8800"`, `"#f80"`, `"#00000060"` (with alpha), `0xff8800` or a name (`"gold"`, `"red"` …).

### 3D

JJGui also has a small software 3D layer (no graphics card needed):

```
camera(0, 3.3, -6.5, 13)                 # x, y, z, tilt° [, turn°, field of view°]
fog("#8ccbff", 28, 95)                   # fog from 28 to 95 units away (fog() turns it off)
floor3d(-3.6, 0, 3.6, 100, 0, "#55555f") # horizontal plane
box3d(0, 0, 5, 1, 2, 1, "gold")          # box: x/z = centre, y = bottom, w/h/d — lit and shaded
circle3d(0, 1, 8, 0.35, "gold", "P")     # circle (with text) that always faces the camera
let s = project(0, 1, 8)                 # [screen-x, screen-y, scale] or nil
render3d()                               # draws it all, front to back
```

y points up and z into the screen. Draw the HUD (text, buttons) after `render3d()`.

### JJGui on the phone (Termux:X11)

Violet can build JJGui scripts for the phone. They use the pure-Hare X11 part
and open a real window in the **Termux:X11** app — touch works as mouse clicks,
and the window is scaled up to fill the screen (`VIPER_SCALE=2` picks the zoom):

```
# on the PC
violet game.Dash --arch android -o game
# in Termux (with the Termux:X11 app installed)
pkg install x11-repo && pkg install termux-x11
termux-x11 :0 &
DISPLAY=:0 ./game
```

## Bits and bytes 🧮 — for emulators and file formats

Integers can be written in hex and binary, and Dash has the bit operators:

```
let op = 0x8c42_0004
let rt = (op >> 16) & 0x1f              # & | ^ << >> ~
if op & 0x3f == 0x20 { echo "ADD" }     # & binds tighter than ==
let flag = 0b1010
flag |= 0b0001                          # &= |= ^=
echo "{7 // 2} {-7 // 2}"               # 3 -3: // cuts the decimals off
echo "{u32(-1):x} {s16(0x8000)}"        # ffffffff -32768
```

Precedence is `|` < `^` < `&` < `<<` `>>` < `+` `-`, and all of them bind tighter
than `==` and `<` (like Python). Shift counts are taken modulo 64.

**Byte buffers** are numbers, like images and sounds, so Violet can turn
`rd32`/`wr32` into direct machine code:

| Function | What it does |
|---|---|
| `bytes(n)` → nr | a buffer of n zero bytes |
| `rd8/rd16/rd32(buf, addr)` | read 1, 2 or 4 bytes (little-endian) |
| `wr8/wr16/wr32(buf, addr, v)` | write |
| `read_bytes(path [, addr, n])` → nr | a file (or a piece of it) |
| `read_into(buf, buf_addr, path, file_addr, n)` | read into a buffer, e.g. one CD sector; returns bytes read |
| `write_bytes(path, buf [, addr, n])` | save a buffer |
| `copy_bytes(dst, dst_addr, src, src_addr, n)`, `fill_bytes(buf, addr, n, v)` | copy and fill |
| `bytes_len(buf)`, `free_bytes(buf)` | size, give the memory back |
| `u32(x)`, `s32(x)`, `s16(x)`, `s8(x)` | clip a number to 32/16/8 bits |

In JJGui, `blit(buf, addr, row_bytes, width, height, format, x, y [, w, h])`
draws pixels straight from a buffer — format 15 (PS1 VRAM), 24 (RGB) or 32 —
scaled to `w`×`h`. That is how **KATCHA** (`eksempler/katcha.Dash`), the PS1
emulator in pure Dash, shows its screen.

## Examples

All in `eksempler/` ("examples"):

| Program | What it is |
|---|---|
| `katcha.Dash` | **KATCHA** 💜💀 — "Herkules, ich brauche Cheatcodes!!": a PlayStation 1 emulator in pure Dash (build it with Violet). R3000A CPU, GPU with gouraud/textured polygons, DMA, timers, joypad, SPU sound, CD and XA audio, MDEC video (cutscenes), a CD-ROM drive for `.cue`/`.bin`/`.iso` images (with fast boot via `SYSTEM.CNF`), a game list from `~/.katcha/spil/`, PS-EXE side-loading and Katcha's GameShark codebook. Bring your own BIOS dump. |
| `bob.Dash` | **Bob's shop** — an app store for your own Dash programs and games: builds them with Violet into `~/.local/bin`, adds menu shortcuts, updates and removes them. The **System** tab updates Linux itself (pacman, AUR, apt, dnf, zypper, xbps, flatpak, snap). |
| `zuzubox.Dash` | **ZuzuBox** 💀📦 — the zombie girl Zuzu (or the bat girl Harboiy) pushes crates onto glowing skulls in a purple crypt. 75 levels in 14 crypts, three themes (spooky, autumn, Christmas), a November countdown and an advent calendar with a new level every day. |
| `boxdog.Dash` | **BoxDog** 🐶📦 — a puppy pushes crates onto paw tiles in a warehouse. |
| `boxman.Dash` | **Boxman** — a classic crate-pusher with 20 levels + 25 Christmas levels. |
| `cube-runner.Dash` | **Cube Head Runners** — a 3D endless runner with three lanes, jumps, trains and a shop. |
| `nonbiri.Dash` | **Nonbiri** 🌾 — an MP3/FLAC player where the sun follows the song across the sky and the crops grow while it plays. |
| `sj-mini.Dash` | **SJ Mini** — read the newest MANGA Plus chapters (with the helper `sj.py`). |
| `serietracker.Dash` | an episode tracker for a TV series; the series data lives in your own file. |
| `jj-demo.Dash` | a small JJGui demo. |

A program describes itself to Bob with `# bob-navn:` (name), `# bob-kategori:`
(category), `# bob-farve:` (colour) and `# bob-om:` (about) at the top of the file.

All levels in the crate games are checked solvable by a solver.

## About

Made by [Bossun](https://github.com/sunnyscoop300-a11y) as a hobby project.
Issues and questions are welcome — in English or Danish.
