#!/usr/bin/env python3
# Klipper nisserne og julepynten ud af nissemockuppen.
#   python3 nisseklip.py nissemockup.png boxdog/jul
import sys, os
from collections import deque
from PIL import Image

src, ud = sys.argv[1], sys.argv[2]
os.makedirs(ud, exist_ok=True)
im = Image.open(src).convert("RGBA")
S = 640 / im.size[1]


def gulvagtig(p):
    r, g, b, a = p
    if a < 20:
        return True
    lys = (r + g + b) / 3
    return 40 < lys < 200 and b >= r - 10 and b >= g - 5


def kun_hue(p):
    r, g, b, a = p
    return r > 110 and r > g * 1.5 and r > b * 1.5


def friskær(box, væk=(), hue=()):
    """hue: felter hvor kun nissehuen (rød) og den mørke kant beholdes."""
    c = im.crop(box).copy()
    w, h = c.size
    px = c.load()
    for (x0, y0, x1, y1) in hue:
        for y in range(max(y0, box[1]), min(y1, box[3])):
            for x in range(max(x0, box[0]), min(x1, box[2])):
                if not kun_hue(px[x - box[0], y - box[1]]):
                    px[x - box[0], y - box[1]] = (0, 0, 0, 0)
    for (x0, y0, x1, y1) in væk:
        for y in range(max(y0, box[1]), min(y1, box[3])):
            for x in range(max(x0, box[0]), min(x1, box[2])):
                px[x - box[0], y - box[1]] = (0, 0, 0, 0)
    set_ = bytearray(w * h)
    q = deque((x, y) for x in range(w) for y in (0, h - 1))
    q.extend((x, y) for y in range(h) for x in (0, w - 1))
    while q:
        x, y = q.popleft()
        if not (0 <= x < w and 0 <= y < h) or set_[y * w + x] or not gulvagtig(px[x, y]):
            continue
        set_[y * w + x] = 1
        q.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    for y in range(h):
        for x in range(w):
            if set_[y * w + x]:
                px[x, y] = (0, 0, 0, 0)
    # kun den største figur bliver
    set2 = bytearray(w * h)
    bedst = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] and not set2[y * w + x]:
                komp = []
                q = deque([(x, y)])
                set2[y * w + x] = 1
                while q:
                    a, b = q.popleft()
                    komp.append((a, b))
                    for n in ((a + 1, b), (a - 1, b), (a, b + 1), (a, b - 1)):
                        if 0 <= n[0] < w and 0 <= n[1] < h and not set2[n[1] * w + n[0]] and px[n][3]:
                            set2[n[1] * w + n[0]] = 1
                            q.append(n)
                if len(komp) > len(bedst):
                    bedst = komp
    keep = bytearray(w * h)
    for (x, y) in bedst:
        keep[y * w + x] = 1
    for y in range(h):
        for x in range(w):
            if px[x, y][3] and not keep[y * w + x]:
                px[x, y] = (0, 0, 0, 0)
    return c.crop(c.getbbox())


def gem(img, navn):
    img.save(os.path.join(ud, navn + ".png"), optimize=True)
    print(navn, img.size)


# nisserne gemmes i fuld størrelse (spillet skalerer dem til feltet)
gem(friskær((650, 250, 820, 420), væk=[(650, 250, 680, 420), (760, 250, 820, 318), (796, 250, 820, 420), (650, 408, 820, 420), (774, 316, 820, 336)], hue=[(680, 250, 765, 316)]), "nisse_lygte")
gem(friskær((1210, 315, 1360, 495), væk=[(1210, 315, 1234, 495), (1322, 412, 1360, 495)]), "nisse_sover")
gem(friskær((570, 560, 740, 740), væk=[(570, 560, 740, 597), (690, 560, 740, 606)]), "nisse_gave")
gem(friskær((1150, 595, 1310, 765), væk=[(1150, 595, 1252, 613)]), "nisse_stok")

# sidebjælken "Christmas Edition" (tallene males over, spillet skriver dem selv)
side = im.crop((0, 0, 394, 941)).copy()
d = side.load()
def mal(x0, y0, x1, y1, fra):
    for y in range(y0, y1):
        c = d[fra, y]
        for x in range(x0, x1):
            d[x, y] = c
mal(252, 524, 352, 564, 247)   # "3-6"
mal(233, 584, 300, 624, 230)   # "0"
mal(236, 626, 318, 664, 232)   # "83"
gem(side.resize((273, 640), Image.LANCZOS), "side")
gem(friskær((398, 692, 520, 880)).resize((83, 128), Image.LANCZOS), "lygtestub")
