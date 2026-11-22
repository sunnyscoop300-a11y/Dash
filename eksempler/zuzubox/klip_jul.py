#!/usr/bin/env python3
"""Laver juletemaet til zuzubox.Dash ud fra jule-mockuppen.

    python3 klip_jul.py jul-mockup.png zuzu-sprites/ zuzubox/jul

jul-mockup.png er "ZuzuBox Christmas Edition" (1536×864), og zuzu-sprites/
er de 8 gangbilleder af jule-Zuzu (zuzu_0.png … zuzu_7.png), skåret ud af
et sheet på grøn skærm med drejning.Dash --png.
"""
import os, sys, shutil
import numpy as np
import cv2
from PIL import Image, ImageDraw, ImageFilter

mock_f, sprites, ud = sys.argv[1:4]
os.makedirs(ud, exist_ok=True)

FW, FH = 1536, 864
W, H = 1136, 640
SIDE_W = 279
mock = Image.open(mock_f).convert("RGB")
assert mock.size == (FW, FH), mock.size
A = np.array(mock).astype(np.float32)


def vandret(a, x0, x1, y0, y1):
    for y in range(y0, y1):
        l, r = a[y, x0 - 1].copy(), a[y, x1].copy()
        t = np.linspace(0, 1, x1 - x0)[:, None]
        a[y, x0:x1] = l * (1 - t) + r * t


# ── LEVEL / MOVES / BEST har ingen tal i mockuppen, så panelet kan bruges som det er ──

# ── midten: puslebrættet erstattes af mørke mursten i krypten farve ──
væg = A[300:520, 400:540].reshape(-1, 3)
mørk = np.percentile(væg, 35, axis=0)
rng = np.random.default_rng(11)
mur = Image.new("RGB", (FW, FH), tuple(int(v * 0.8) for v in mørk))
d = ImageDraw.Draw(mur)
BH, BB = 31, 70
for row in range(FH // BH + 2):
    y = row * BH
    ofs = (row % 2) * BB // 2
    for col in range(-1, FW // BB + 2):
        x = col * BB + ofs
        v = int(rng.integers(-8, 10))
        c = tuple(int(min(255, max(0, m + v))) for m in mørk)
        d.rectangle([x + 3, y + 3, x + BB - 3, y + BH - 3], fill=c)
        d.line([x + 4, y + 3, x + BB - 4, y + 3], fill=tuple(min(255, k + 16) for k in c), width=2)
        d.line([x + 4, y + BH - 3, x + BB - 4, y + BH - 3], fill=tuple(max(0, k - 16) for k in c), width=2)
mur = mur.filter(ImageFilter.GaussianBlur(0.8))
M = np.array(mur).astype(np.float32)
maske = np.zeros((FH, FW), np.float32)
maske[222:778, 548:1352] = 1
maske = cv2.GaussianBlur(maske, (0, 0), 6)
B = A * (1 - maske[..., None]) + M * maske[..., None]

# skiltet på muren tømmes (spillet skriver banen på det)
full = Image.fromarray(np.clip(B, 0, 255).astype(np.uint8)).resize((W, H), Image.LANCZOS)
full.crop((0, 0, SIDE_W, H)).save(f"{ud}/side.png")
full.crop((SIDE_W, 0, W, H)).save(f"{ud}/bund.png")

# ── gulvflisen ──
mock.crop((1012, 340, 1123, 446)).save(f"{ud}/gulv.png")


def klip_ud(box, navn, bredde, indre=6):
    """Klipper en figur fri af baggrunden med GrabCut."""
    x0, y0, x1, y1 = box
    pad = 14
    crop = np.array(mock.crop((x0 - pad, y0 - pad, x1 + pad, y1 + pad)))[:, :, ::-1].copy()
    mask = np.zeros(crop.shape[:2], np.uint8)
    bgd, fgd = np.zeros((1, 65), np.float64), np.zeros((1, 65), np.float64)
    cv2.grabCut(crop, mask, (pad - indre, pad - indre, x1 - x0 + 2 * indre, y1 - y0 + 2 * indre),
                bgd, fgd, 8, cv2.GC_INIT_WITH_RECT)
    fg = np.where((mask == 1) | (mask == 3), 255, 0).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(fg)
    if n > 1:
        big = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
        fg = np.where(lab == big, 255, 0).astype(np.uint8)
    fg = cv2.morphologyEx(fg, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    fg = cv2.GaussianBlur(fg, (3, 3), 0)
    im = Image.fromarray(np.dstack([crop[:, :, ::-1], fg]), "RGBA")
    im = im.crop(im.getbbox())
    im = im.resize((bredde, int(im.height * bredde / im.width)), Image.LANCZOS)
    im.save(f"{ud}/{navn}.png")
    return im


k1 = klip_ud((598, 232, 696, 331), "kasse", 200)
k2 = klip_ud((802, 230, 901, 331), "kasse2", 200)
k1.resize((60, int(k1.height * 60 / k1.width)), Image.LANCZOS).save(f"{ud}/kasse_lille.png")
maal = klip_ud((706, 342, 792, 432), "maal", 200)
klip_ud((1372, 612, 1530, 725), "gargoil", 200)

# kraniet med nissehue: 12 billeder hvor det grønne gløder
ma = np.array(maal).astype(np.float32)
grøn = (ma[..., 1] > 150) & (ma[..., 0] > 110) & (ma[..., 2] < 120)
for i in range(12):
    f = 0.82 + 0.18 * (0.5 + 0.5 * np.cos(i / 12 * 2 * np.pi))
    b = ma.copy()
    b[grøn, :3] = np.clip(b[grøn, :3] * f + (1 - f) * 40, 0, 255)
    Image.fromarray(b.astype(np.uint8), "RGBA").save(f"{ud}/maal_{i}.png")
os.remove(f"{ud}/maal.png")

# ── jule-Zuzu ──
for i in range(8):
    shutil.copy(os.path.join(sprites, f"zuzu_{i}.png"), f"{ud}/zuzu_{i}.png")

# ikon
mock.crop((40, 0, 330, 260)).resize((256, 230), Image.LANCZOS).save(f"{ud}/ikon.png")
print("færdig")
