#!/usr/bin/env python3
# Klipper BoxDog-grafikken ud af mockuppen (hunden og potefelterne kommer
# fra animationerne, se anim.py).
#   python3 klip.py mockup.png ud-mappe
import sys, os
from collections import deque
from PIL import Image

src, ud = sys.argv[1], sys.argv[2]
os.makedirs(ud, exist_ok=True)
im = Image.open(src).convert("RGBA")
S = 640 / im.size[1]          # spillet er 640 høj


def sc(img, f=S):
    w, h = img.size
    return img.resize((max(1, round(w * f)), max(1, round(h * f))), Image.LANCZOS)


def gulvagtig(p):
    r, g, b, a = p
    lys = (r + g + b) / 3
    return b >= r - 6 and b >= g and max(r, g, b) - min(r, g, b) < 75 and lys > 48


def friskær(box, behold_største=True, streg=False):
    """Fjerner gulvet rundt om en figur (fyldning fra kanten)."""
    c = im.crop(box)
    w, h = c.size
    px = c.load()
    set_ = set()
    q = deque()
    for x in range(w):
        q.append((x, 0)); q.append((x, h - 1))
    for y in range(h):
        q.append((0, y)); q.append((w - 1, y))
    while q:
        x, y = q.popleft()
        if (x, y) in set_ or not (0 <= x < w and 0 <= y < h):
            continue
        if not gulvagtig(px[x, y]):
            continue
        set_.add((x, y))
        q.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
    for (x, y) in set_:
        px[x, y] = (0, 0, 0, 0)
    if behold_største:
        # kun den største sammenhængende figur bliver
        set2 = set()
        bedst = []
        for y in range(h):
            for x in range(w):
                if px[x, y][3] and (x, y) not in set2:
                    komp = []
                    q = deque([(x, y)])
                    set2.add((x, y))
                    while q:
                        a, b = q.popleft()
                        komp.append((a, b))
                        for n in ((a + 1, b), (a - 1, b), (a, b + 1), (a, b - 1)):
                            if 0 <= n[0] < w and 0 <= n[1] < h and n not in set2 and px[n][3]:
                                set2.add(n)
                                q.append(n)
                    if len(komp) > len(bedst):
                        bedst = komp
        keep = set(bedst)
        for y in range(h):
            for x in range(w):
                if px[x, y][3] and (x, y) not in keep:
                    px[x, y] = (0, 0, 0, 0)
    # en tynd lodret streg i kanten (nabokassens kant) fjernes
    for side in ((range(w - 1, w - 8, -1), range(0, 7)) if streg else ()):
        for x in side:
            n = sum(1 for y in range(h) if px[x, y][3])
            if n > h * 0.5:
                for y in range(h):
                    px[x, y] = (0, 0, 0, 0)
    return c.crop(c.getbbox())


def gem(img, navn):
    img.save(os.path.join(ud, navn + ".png"), optimize=True)
    print(navn, img.size)


# ── sidebjælken (tallene i panelet males over, spillet skriver dem selv) ──
side = im.crop((0, 0, 402, 941)).copy()
d = side.load()
def mal(x0, y0, x1, y1, fra):
    for y in range(y0, y1):
        c = d[fra, y]
        for x in range(x0, x1):
            d[x, y] = c
mal(272, 522, 362, 566, 266)   # "1-5"
mal(238, 584, 290, 624, 232)   # "0"
mal(238, 636, 318, 670, 232)   # "---"
gem(sc(side), "side")

# ── bagvæggen (banens mure fra mockuppen males væk) ──
bag = im.crop((402, 0, 1672, 218)).copy()
d = bag.load()
w, h = bag.size
# nederste kant: gulv og mure bliver gennemsigtige, så spillets eget gulv ses
for y in range(184, h):
    for x in range(w):
        X = x + 402
        if 1016 <= X <= 1080 and y < 208:
            continue      # skabets bund
        if 1128 <= X <= 1392 and y < 212:
            continue      # porten
        mur = 538 <= X <= 806 or 1000 <= X <= 1128 or 1380 <= X <= 1428
        if mur or gulvagtig(d[x, y]):
            d[x, y] = (0, 0, 0, 0)
gem(sc(bag), "bag")

# ── figurerne ──
gem(friskær((779, 420, 884, 542)), "kasse")      # skaleres i spillet
gem(im.crop((1049, 679, 1137, 755)), "gulv")       # skaleres i spillet
gem(sc(friskær((400, 740, 497, 890))), "toende")
gem(sc(friskær((1505, 735, 1672, 941))), "kassestak")
gem(sc(friskær((1585, 370, 1672, 585))), "plante")
gem(sc(friskær((535, 805, 660, 941))), "kasse_lille")
