"""Give the icon set one optical size, then write Media/icons/*-white.tga and a review sheet.

  python tools/icons.py

Every source is a 64 x 64 painted icon (design/icons-v2-2026-11-04/*-64.png from Codex, plus the
gear, kept as design/icons-v2-2026-11-04/gear-64.png). They all fill their canvas edge to edge, so
a solid stop square read far bigger than a thin skinning knife at the same box. Each icon is
scaled by (TARGET / its ink coverage) ** WEIGHT: heavy shapes shrink, light ones grow a little
(never past MAX_BOX), the way icon families are balanced by eye. WEIGHT below 0.5 keeps the
shapes' own character (a full area match made the stop square look tiny). The result is centred
on its bounding box and saved as uncompressed 32-bit TGA, as the game wants.

Writes design/icons-v2-2026-11-04/Balanced-sheet.png: before and after, at 64 px and at 16 px
(the dock's size), in the profession colours.
Needs Pillow (it reuses Forever Goal Tracker's copy in ../ForeverGoalTracker/tools/.py).
"""
import os
import sys

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(here)
for p in (os.path.join(here, ".py"), os.path.join(root, "..", "ForeverGoalTracker", "tools", ".py")):
    if os.path.isdir(p):
        sys.path.insert(0, p)
from PIL import Image, ImageDraw  # noqa: E402

SRC = os.path.join(root, "design", "icons-v2-2026-11-04")
OUT = os.path.join(root, "Media", "icons")
TARGET, WEIGHT, MAX_BOX, CANVAS = 0.34, 0.35, 58, 64

# source -> game file
ICONS = [
    ("skinning", "skinning-white"), ("mining", "mining-white"), ("herbalism", "herbalism-white"),
    ("fishing", "fishing-white"), ("cloth", "cloth-white"), ("statistics", "stats-white"),
    ("gear", "gear-white"), ("play", "play-white"), ("pause", "pause-white"), ("stop", "stop-white"),
    ("share", "share-white"), ("warning", "warning-white"), ("book", "book-white"),
    ("book-open", "book-open-white"), ("treasure", "treasure-white"), ("coin", "money-white"),
]
TINT = {"skinning": (232, 128, 58), "mining": (227, 84, 69), "treasure": (242, 212, 58), "herbalism": (111, 191, 79),
        "fishing": (79, 163, 224), "cloth": (167, 125, 220), "coin": (255, 204, 51)}


def ink(im):
    a = im.getchannel("A")
    return sum(1 for v in a.tobytes() if v > 40) / float(im.width * im.height)


def balance(im):
    bbox = im.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
    shape = im.crop(bbox)
    k = (TARGET / ink(im)) ** WEIGHT
    k = min(k, MAX_BOX / float(max(shape.size)))
    w, h = max(1, round(shape.width * k)), max(1, round(shape.height * k))
    shape = shape.resize((w, h), Image.LANCZOS)
    out = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    out.paste(shape, ((CANVAS - w) // 2, (CANVAS - h) // 2), shape)
    return out, k


def tinted(im, rgb):
    if not rgb:
        return im
    r, g, b, a = im.split()
    r = r.point(lambda v: v * rgb[0] // 255)
    g = g.point(lambda v: v * rgb[1] // 255)
    b = b.point(lambda v: v * rgb[2] // 255)
    return Image.merge("RGBA", (r, g, b, a))


def main():
    rows = []
    for src, dst in ICONS:
        path = os.path.join(SRC, src + "-64.png")
        before = Image.open(path).convert("RGBA")
        after, k = balance(before)
        after.save(os.path.join(OUT, dst + ".tga"), compression=None)
        rows.append((src, before, after, k))
        print("%-11s ink %3.0f%%  scale %.2f  -> %s.tga" % (src, ink(before) * 100, k, dst))

    # review sheet: two rows (before, after), each icon at 64 and at 16
    cell = 84
    sheet = Image.new("RGB", (40 + cell * len(rows), 330), (22, 20, 17))
    d = ImageDraw.Draw(sheet)
    for j, label in enumerate(("before", "after")):
        y = 20 + j * 150
        d.text((8, y), label, fill=(200, 170, 80))
        for i, (src, before, after, k) in enumerate(rows):
            im = tinted(before if j == 0 else after, TINT.get(src))
            x = 40 + i * cell
            sheet.paste(im, (x, y + 16), im)
            small = im.resize((16, 16), Image.LANCZOS)
            sheet.paste(small, (x + 24, y + 96), small)
            if j == 1:
                d.text((x, y + 124), src[:9], fill=(150, 150, 150))
    sheet.save(os.path.join(SRC, "Balanced-sheet.png"))


if __name__ == "__main__":
    main()
