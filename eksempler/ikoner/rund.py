#!/usr/bin/env python3
"""Gives a Dash app logo rounded, transparent corners (tegn-ikoner.Dash calls it)."""
import sys
from PIL import Image, ImageDraw

for path in sys.argv[1:]:
    im = Image.open(path).convert("RGBA")
    big = 4                                   # draw the mask 4x as big: soft edges
    w, h = im.size
    mask = Image.new("L", (w * big, h * big), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w * big - 1, h * big - 1), radius=48 * big, fill=255)
    im.putalpha(mask.resize((w, h), Image.LANCZOS))
    im.save(path)
