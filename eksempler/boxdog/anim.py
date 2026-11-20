#!/usr/bin/env python3
# Klipper BoxDog-animationerne ud af GIF'erne.
#   python3 anim.py forfra.gif side.gif maal.gif ud-mappe
# forfra.gif: 16 billeder (0-3 nedad, 4-7 højre, 8-11 opad, 12-15 venstre)
# side.gif:   gang til højre (spejles til venstre)
# maal.gif:   potefeltet der lyser
# Alt gemmes i en størrelse, hvor et felt er 100 px.
import sys, os
from collections import deque
from PIL import Image, ImageSequence

forfra, side, maal, ud = sys.argv[1:5]
os.makedirs(ud, exist_ok=True)
FELT = 100
HUND_B = 142          # hunden fra siden er 1,42 felt bred


def billeder(f):
    return [x.convert("RGBA") for x in ImageSequence.Iterator(Image.open(f))]


def gulvagtig(p):
    r, g, b, a = p
    if a < 20:
        return True
    lys = (r + g + b) / 3
    return b >= r - 8 and b >= g - 4 and max(r, g, b) - min(r, g, b) < 80 and lys > 30


def friskær(im):
    """Fjerner gulv og skygge rundt om hunden (fyldning fra kanten)."""
    im = im.copy()
    w, h = im.size
    px = im.load()
    set_ = bytearray(w * h)
    q = deque()
    for x in range(w):
        q.append((x, 0)); q.append((x, h - 1))
    for y in range(h):
        q.append((0, y)); q.append((w - 1, y))
    while q:
        x, y = q.popleft()
        if not (0 <= x < w and 0 <= y < h) or set_[y * w + x]:
            continue
        if not gulvagtig(px[x, y]):
            continue
        set_[y * w + x] = 1
        q.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    for y in range(h):
        for x in range(w):
            if set_[y * w + x]:
                px[x, y] = (0, 0, 0, 0)
    # kun den største figur bliver (løse gulvprikker væk)
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
    return im


def fælles_boks(ims):
    bs = [i.getbbox() for i in ims]
    return (min(b[0] for b in bs), min(b[1] for b in bs), max(b[2] for b in bs), max(b[3] for b in bs))


def gem_serie(ims, navn, skala, spejl=False):
    box = fælles_boks(ims)
    for i, im in enumerate(ims):
        c = im.crop(box)
        c = c.resize((round(c.width * skala), round(c.height * skala)), Image.LANCZOS)
        if spejl:
            c = c.transpose(Image.FLIP_LEFT_RIGHT)
        c.save(os.path.join(ud, f"{navn}_{i}.png"), optimize=True)
    print(navn, len(ims), c.size)


ff = [friskær(x) for x in billeder(forfra)]
sg = [friskær(x) for x in billeder(side)]

# samme størrelse i alle retninger: hunden fra siden skal være HUND_B bred
b_ff = max(x.getbbox()[2] - x.getbbox()[0] for x in ff[4:8])
b_sg = max(x.getbbox()[2] - x.getbbox()[0] for x in sg)
gem_serie(ff[0:4], "hund_n", HUND_B / b_ff)
gem_serie(ff[8:12], "hund_o", HUND_B / b_ff)
gem_serie(sg, "hund_h", HUND_B / b_sg)
gem_serie(sg, "hund_v", HUND_B / b_sg, spejl=True)

mf = billeder(maal)
box = fælles_boks(mf)
skala = FELT * 1.02 / (box[2] - box[0])
for i, im in enumerate(mf):
    c = im.crop(box)
    c = c.resize((round(c.width * skala), round(c.height * skala)), Image.LANCZOS)
    c.save(os.path.join(ud, f"maal_{i}.png"), optimize=True)
print("maal", len(mf), c.size)
