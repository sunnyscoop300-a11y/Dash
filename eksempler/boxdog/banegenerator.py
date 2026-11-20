#!/usr/bin/env python3
# Banegenerator til BoxDog: laver tilfældige lagerrum, løser dem og gemmer
# de svære.  python3 gen.py sekunder frø ud.jsonl
import sys, random, json, time
sys.path.append('/home/claude/boxdog')
from collections import deque
import solve2
from solve2 import parse, live_cells, reach, frozen, D


def løs(kort, limit=400_000):
    """Giver (skub, antal stillinger) eller None."""
    walls, goals, boxes, p = parse(kort)
    W = max(len(r) for r in kort); H = len(kort)
    live = live_cells(walls, goals, W, H)
    if any(b not in live and b not in goals for b in boxes):
        return None
    bs = frozenset(boxes); r = reach(p, walls, bs); start = (min(r), bs)
    seen = {start: 0}; q = deque([(start, r)])
    while q:
        (pn, bs), r = q.popleft(); d = seen[(pn, bs)]
        if bs == goals:
            return d, len(seen)
        for b in bs:
            for dx, dy in D:
                pl = (b[0] - dx, b[1] - dy); t = (b[0] + dx, b[1] + dy)
                if pl not in r or t in walls or t in bs or t not in live:
                    continue
                nb = (bs - {b}) | {t}
                if t not in goals and frozen(t, nb, walls):
                    continue
                r2 = reach(b, walls, nb); k = (min(r2), nb)
                if k in seen:
                    continue
                seen[k] = d + 1; q.append((k, r2))
                if len(seen) > limit:
                    return None
    return None


def rum(rng):
    w = rng.randint(7, 10); h = rng.randint(6, 8)          # indvendigt
    tæt = rng.uniform(0.22, 0.34)
    g = [['#'] * (w + 2) for _ in range(h + 2)]
    for y in range(1, h + 1):
        for x in range(1, w + 1):
            g[y][x] = '#' if rng.random() < tæt else ' '
    W = w + 2; H = h + 2
    # blindgyder fyldes op (felter med tre mure omkring)
    ændret = True
    while ændret:
        ændret = False
        for y in range(1, h + 1):
            for x in range(1, w + 1):
                if g[y][x] == ' ' and sum(g[y + dy][x + dx] == '#' for dx, dy in D) >= 3:
                    g[y][x] = '#'; ændret = True
    walls = {(x, y) for y in range(H) for x in range(W) if g[y][x] == '#'}
    fl = [(x, y) for y in range(H) for x in range(W) if g[y][x] == ' ']
    if not fl:
        return None
    # kun det største sammenhængende rum bliver
    bedst = set()
    set_ = set()
    for c in fl:
        if c in set_:
            continue
        r = reach(c, walls, set())
        set_ |= r
        if len(r) > len(bedst):
            bedst = r
    for (x, y) in fl:
        if (x, y) not in bedst:
            g[y][x] = '#'
    fl = sorted(bedst)
    if len(fl) < 24:
        return None
    walls = {(x, y) for y in range(H) for x in range(W) if g[y][x] == '#'}
    return g, fl, walls


def bane(rng):
    """Baglæns: kasserne starter på potefelterne, og hunden trækker dem væk.
    Så kan banen altid løses."""
    r = rum(rng)
    if not r:
        return None
    g, fl, walls = r
    k = rng.choice((3, 4, 4, 5, 5, 6))
    goals = set(rng.sample(fl, k))
    boxes = set(goals)
    fri = [c for c in fl if c not in boxes]
    if not fri:
        return None
    p = rng.choice(fri)
    for _ in range(rng.randint(200, 900)):
        træk = [(dx, dy) for dx, dy in D
                if (p[0] + dx, p[1] + dy) in boxes
                and (p[0] - dx, p[1] - dy) not in walls and (p[0] - dx, p[1] - dy) not in boxes]
        if træk and rng.random() < 0.55:
            dx, dy = rng.choice(træk)
            boxes.remove((p[0] + dx, p[1] + dy)); boxes.add(p)
            p = (p[0] - dx, p[1] - dy)
            continue
        dx, dy = rng.choice(D)
        bag = (p[0] - dx, p[1] - dy)
        if bag not in walls and bag not in boxes:
            p = bag
    if sum(1 for b in boxes if b in goals) > 1:
        return None
    for (x, y) in goals: g[y][x] = '.'
    for (x, y) in boxes: g[y][x] = '*' if (x, y) in goals else '$'
    g[p[1]][p[0]] = '+' if p in goals else '@'
    return [''.join(r) for r in g]


def main():
    sek = float(sys.argv[1]); rng = random.Random(int(sys.argv[2])); ud = open(sys.argv[3], 'a')
    slut = time.time() + sek; n = 0; gemt = 0
    while time.time() < slut:
        kort = bane(rng); n += 1
        if not kort:
            continue
        res = løs(kort, 250_000)
        if res and res[0] >= 20:
            ud.write(json.dumps({"kort": kort, "skub": res[0], "stillinger": res[1]}) + "\n"); ud.flush()
            gemt += 1
    print(f"forsøg {n}, gemt {gemt}")


if __name__ == '__main__':
    main()
