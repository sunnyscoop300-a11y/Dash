#!/usr/bin/env python3
# Klipper jule-BoxDog ud af julemockuppen og julehunden (GIF med 16 billeder:
# 0-3 nedad, 4-7 højre, 8-11 opad, 12-15 venstre).
#   python3 julklip.py julmockup.png julhund.gif boxdog/jul
import sys, os
from collections import deque
from PIL import Image

src, gif, ud = sys.argv[1], sys.argv[2], sys.argv[3]
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


def friskær(box, behold_største=True, streg=False, væk=()):
    """Fjerner gulvet rundt om en figur (fyldning fra kanten). Felterne i
    væk (x0, y0, x1, y1 i mockuppen) er naboer, der viskes ud først."""
    c = im.crop(box).copy()
    px = c.load()
    for (x0, y0, x1, y1) in væk:
        for y in range(max(y0, box[1]), min(y1, box[3])):
            for x in range(max(x0, box[0]), min(x1, box[2])):
                px[x - box[0], y - box[1]] = (0, 0, 0, 0)
    return friskær_billede(c, behold_største, streg)


def friskær_billede(c, behold_største=True, streg=False):
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


# sne er hvid og meget lysere end gulvet, så den bliver stående
def gulvagtig(p):
    r, g, b, a = p
    if a < 20:
        return True
    lys = (r + g + b) / 3
    return 48 < lys <= 165 and b >= r - 6 and b >= g and max(r, g, b) - min(r, g, b) < 75


def gem(img, navn):
    img.save(os.path.join(ud, navn + ".png"), optimize=True)
    print(navn, img.size)


# ── sidebjælken (tallene males over, spillet skriver dem selv) ──
side = im.crop((0, 0, 402, 941)).copy()
d = side.load()
def mal(x0, y0, x1, y1, fra):
    for y in range(y0, y1):
        c = d[fra, y]
        for x in range(x0, x1):
            d[x, y] = c
mal(272, 520, 352, 566, 266)   # "1-5"
mal(238, 582, 290, 624, 232)   # "0"
mal(238, 632, 318, 670, 232)   # "---"
gem(sc(side), "side")

# ── bagvæggen: banens mure, sne og gulv forneden bliver gennemsigtige ──
bag = im.crop((402, 0, 1672, 218)).copy()
d = bag.load()
w, h = bag.size
for y in range(184, h):
    for x in range(w):
        X = x + 402
        if 880 <= X <= 1000 and y < 222:
            continue      # vognens hjul
        if 1016 <= X <= 1080 and y < 208:
            continue      # skabets bund
        if 1128 <= X <= 1392 and y < 212:
            continue      # porten
        if X < 532 or X > 1428:
            if not gulvagtig(d[x, y]):
                continue  # gaverne og kassen i hjørnerne
        mur = 532 <= X <= 806 or 1000 <= X <= 1128 or 1380 <= X <= 1428
        if mur or gulvagtig(d[x, y]):
            d[x, y] = (0, 0, 0, 0)
gem(sc(bag), "bag")

# ── brikker og pynt ──
gem(friskær((781, 418, 884, 542)), "kasse")      # skaleres i spillet
gem(im.crop((1049, 679, 1137, 755)), "gulv")
gem(sc(friskær((407, 722, 502, 878))), "toende")
gem(sc(friskær((470, 745, 590, 941), væk=[(578, 820, 700, 941)])), "trae")
gem(sc(friskær((1568, 300, 1672, 575))), "trae2")
gem(sc(friskær((580, 835, 692, 941))), "gave")
gem(sc(friskær((1492, 668, 1650, 870), væk=[(1576, 600, 1672, 708), (1480, 838, 1500, 941), (1580, 838, 1672, 941)])), "snemand")
gem(sc(friskær((1586, 836, 1672, 941))), "kasser_hjoerne")
gem(sc(friskær((1374, 822, 1480, 941))), "gave2")

# ── julehunden ──
from PIL import ImageSequence
fr = [friskær_billede(x.convert("RGBA")) for x in ImageSequence.Iterator(Image.open(gif))]
def boks(ims):
    bs = [i.getbbox() for i in ims]
    return (min(b[0] for b in bs), min(b[1] for b in bs), max(b[2] for b in bs), max(b[3] for b in bs))
side_b = max(x.getbbox()[2] - x.getbbox()[0] for x in fr[4:8])
skala = 150 / side_b       # hunden fra siden er 1,5 felt bred med huen
for navn, a in (("jul_n", 0), ("jul_h", 4), ("jul_o", 8), ("jul_v", 12)):
    b = boks(fr[a:a + 4])
    for i in range(4):
        c = fr[a + i].crop(b)
        c = c.resize((round(c.width * skala), round(c.height * skala)), Image.LANCZOS)
        c.save(os.path.join(ud, f"{navn}_{i}.png"), optimize=True)
    print(navn, c.size)
