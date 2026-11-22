#!/usr/bin/env python3
"""Laver grafikken til zuzubox.Dash.

    python3 klip.py mockup.png zuzu.gif maal.png kasse.png zuzubox

Klipper sidebjælken og baggrunden ud af mockuppet (skalerer til 1136×640),
fjerner det ternede "gennemsigtige" mønster fra Zuzu-GIF'en og målfeltet,
og laver gulv, gargoil og ikoner.
"""
import os, sys
import numpy as np
import cv2
from PIL import Image, ImageDraw, ImageFilter

mock_f, gif_f, maal_f, kasse_f, ud = sys.argv[1:6]
os.makedirs(ud, exist_ok=True)

FW, FH = 1672, 941          # mockuppets størrelse
W, H = 1136, 640            # spillets vindue
S = W / FW
SIDE_W = 279


def sk(v):
    return int(round(v * S))


mock = Image.open(mock_f).convert("RGB")
assert mock.size == (FW, FH), mock.size
A = np.array(mock).astype(np.float32)


def vandret(a, x0, x1, y0, y1):
    for y in range(y0, y1):
        l, r = a[y, x0 - 1].copy(), a[y, x1].copy()
        t = np.linspace(0, 1, x1 - x0)[:, None]
        a[y, x0:x1] = l * (1 - t) + r * t


def gem(a, navn):
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(f"{ud}/{navn}")


# ── tallene i panelet og skiltet fjernes i fuld størrelse ──
for (x0, x1, y0, y1) in [(266, 360, 518, 570), (240, 284, 588, 634), (238, 326, 640, 670)]:
    vandret(A, x0, x1, y0, y1)
vandret(A, 993, 1114, 25, 73)

# ── midten af kælderen bliver til mørke mursten ──
rng = np.random.default_rng(7)
mur = Image.new("RGB", (FW, FH), (58, 30, 98))
d = ImageDraw.Draw(mur)
BH, BB = 34, 76
for row in range(FH // BH + 2):
    y = row * BH
    ofs = (row % 2) * BB // 2
    for col in range(-1, FW // BB + 2):
        x = col * BB + ofs
        v = rng.integers(-10, 12)
        c = (62 + v, 33 + v // 2, 106 + v)
        d.rectangle([x + 3, y + 3, x + BB - 3, y + BH - 3], fill=c)
        d.line([x + 4, y + 3, x + BB - 4, y + 3], fill=(c[0] + 18, c[1] + 10, c[2] + 22), width=2)
        d.line([x + 4, y + BH - 3, x + BB - 4, y + BH - 3], fill=(c[0] - 18, c[1] - 10, c[2] - 22), width=2)
mur = mur.filter(ImageFilter.GaussianBlur(0.8))
M = np.array(mur).astype(np.float32)
maske = np.zeros((FH, FW), np.float32)
maske[178:888, 440:1588] = 1
# pynten i hjørnerne bliver stående
maske[690:, 410:705] = 0
maske[640:, 1478:] = 0
maske = cv2.GaussianBlur(maske, (0, 0), 7)
B = A * (1 - maske[..., None]) + M * maske[..., None]

full = Image.fromarray(np.clip(B, 0, 255).astype(np.uint8)).resize((W, H), Image.LANCZOS)
full.crop((0, 0, SIDE_W, H)).save(f"{ud}/side.png")
full.crop((SIDE_W, 0, W, H)).save(f"{ud}/bund.png")

# ── gulvflisen ──
Image.fromarray(A[352:441, 962:1059].astype(np.uint8)).save(f"{ud}/gulv.png")


# ── ternet baggrund væk: fyld fra kanten over lyse, grå pixels ──
def uden_tern(im):
    im = im.convert("RGB")
    a = np.array(im).astype(np.int32)
    lys = a.min(axis=2) > 175
    grå = (a.max(axis=2) - a.min(axis=2)) < 22
    bund = (lys & grå).astype(np.uint8)
    h, w = bund.shape
    ff = np.zeros((h + 2, w + 2), np.uint8)
    fyld = bund.copy()
    for (x, y) in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)] + [(x, 0) for x in range(0, w, 7)] + \
            [(x, h - 1) for x in range(0, w, 7)] + [(0, y) for y in range(0, h, 7)] + [(w - 1, y) for y in range(0, h, 7)]:
        if fyld[y, x] == 1:
            cv2.floodFill(fyld, ff, (x, y), 2)
    alfa = np.where(fyld == 2, 0, 255).astype(np.uint8)
    # en blød kant
    alfa = cv2.erode(alfa, np.ones((2, 2), np.uint8))
    alfa = cv2.GaussianBlur(alfa, (3, 3), 0)
    rgba = np.dstack([a.astype(np.uint8), alfa])
    return Image.fromarray(rgba, "RGBA")


def bbox(im):
    a = np.array(im.getchannel("A")) > 100
    ys, xs = np.nonzero(a)
    return (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)


def beskær(im):
    return im.crop(bbox(im))


# ── Zuzu: GIF'ens billeder ──
g = Image.open(gif_f)
rammer = []
for i in range(g.n_frames):
    g.seek(i)
    rammer.append(uden_tern(g.convert("RGBA")))
bb = None
for r in rammer:
    b = bbox(r)
    bb = b if bb is None else (min(bb[0], b[0]), min(bb[1], b[1]), max(bb[2], b[2]), max(bb[3], b[3]))
for i, r in enumerate(rammer):
    r = r.crop(bb)
    h = 160
    w = int(r.width * h / r.height)
    r = r.resize((w, h), Image.LANCZOS)
    r.save(f"{ud}/zuzu_{i}.png")
    r.transpose(Image.FLIP_LEFT_RIGHT).save(f"{ud}/zuzu_v_{i}.png")
print("zuzu:", len(rammer), "billeder", bb)

# ── kassen ──
k = beskær(Image.open(kasse_f).convert("RGBA"))
k = k.resize((200, int(k.height * 200 / k.width)), Image.LANCZOS)
k.save(f"{ud}/kasse.png")
k.resize((60, int(k.height * 60 / k.width)), Image.LANCZOS).save(f"{ud}/kasse_lille.png")

# ── kraniefeltet: 12 billeder hvor gløden pulserer ──
m = beskær(uden_tern(Image.open(maal_f)))
m = m.resize((200, int(m.height * 200 / m.width)), Image.LANCZOS)
ma = np.array(m).astype(np.float32)
grøn = (ma[..., 1] > 150) & (ma[..., 0] > 120) & (ma[..., 2] < 120)
for i in range(12):
    f = 0.82 + 0.18 * (0.5 + 0.5 * np.cos(i / 12 * 2 * np.pi))
    b = ma.copy()
    b[grøn, :3] = np.clip(b[grøn, :3] * f + (1 - f) * 40, 0, 255)
    Image.fromarray(b.astype(np.uint8), "RGBA").save(f"{ud}/maal_{i}.png")

# ── gargoilen (forhindring) ──
gx0, gy0, gx1, gy1 = 1488, 668, 1652, 808
crop = np.array(mock.crop((gx0 - 20, gy0 - 20, gx1 + 20, gy1 + 20)))[:, :, ::-1].copy()
mask = np.zeros(crop.shape[:2], np.uint8)
bgd, fgd = np.zeros((1, 65), np.float64), np.zeros((1, 65), np.float64)
cv2.grabCut(crop, mask, (20, 20, gx1 - gx0, gy1 - gy0 - 8), bgd, fgd, 6, cv2.GC_INIT_WITH_RECT)
fg = np.where((mask == 1) | (mask == 3), 255, 0).astype(np.uint8)
# kun den største klump, og huller lukkes
n, lab, st, _ = cv2.connectedComponentsWithStats(fg)
if n > 1:
    big = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
    fg = np.where(lab == big, 255, 0).astype(np.uint8)
fg = cv2.morphologyEx(fg, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
fg = cv2.GaussianBlur(fg, (3, 3), 0)
garg = Image.fromarray(np.dstack([crop[:, :, ::-1], fg]), "RGBA")
garg = beskær(garg)
garg.resize((200, int(garg.height * 200 / garg.width)), Image.LANCZOS).save(f"{ud}/gargoil.png")

# ── ikon til Bob og menuen: Zuzu fra logoet ──
ik = mock.crop((10, 0, 300, 290)).resize((256, 256), Image.LANCZOS)
ik.save(f"{ud}/ikon.png")
print("færdig")
