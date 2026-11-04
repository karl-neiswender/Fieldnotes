"""Crop the gallery screenshots /fn shots took, and name them.

  python tools/shots.py [--only 03] [client folder]

In game: /fn shots (or /fn shots 03 for one), wait for "Done", then /reload so the game writes
where each subject sat (FieldnotesDB.shotRects, in screen pixels) to the saved variables. This
takes the newest burst of screenshots from the client's Screenshots folder (taken a couple of
seconds apart, in gallery order), crops each to its subject with a small margin, and saves
Screenshots/NN-name.png in the repo.
Default client: Classic Era on this PC (the repo sits in the beta's AddOns folder).
Needs Pillow (it reuses Forever Goal Tracker's copy in ../ForeverGoalTracker/tools/.py).
"""
import glob
import os
import re
import sys

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(here)
for p in (os.path.join(here, ".py"), os.path.join(root, "..", "ForeverGoalTracker", "tools", ".py")):
    if os.path.isdir(p):
        sys.path.insert(0, p)
from PIL import Image  # noqa: E402

# the same order as SHOTS in Shots.lua
NAMES = ["01-dashboard", "02-heat", "03-herbalism", "04-points", "05-community", "06-continent",
         "07-session", "08-settings", "09-stats", "10-share"]
MARGIN = 10

args = sys.argv[1:]
only = None
if "--only" in args:
    only = args[args.index("--only") + 1]
    args = [a for a in args if a not in ("--only", only)]
    NAMES = [n for n in NAMES if n.startswith(only)]
    if len(NAMES) != 1:
        sys.exit("--only needs one shot: %r matches %d" % (only, len(NAMES)))
client = args[0] if args else os.path.join(root, "..", "..", "..", "..", "_classic_era_")
client = os.path.abspath(client)

svs = glob.glob(os.path.join(client, "WTF", "Account", "*", "SavedVariables", "Fieldnotes.lua"))
if not svs:
    sys.exit("No Fieldnotes saved variables under " + client + ". /reload in game after /fn shots.")
sv = max(svs, key=os.path.getmtime)
text = open(sv, encoding="utf-8", errors="replace").read()
rects = {m.group(1): [int(v) for v in m.group(2).split(",")]
         for m in re.finditer(r'\["(\d\d-[\w-]+)"\]\s*=\s*"([\d,-]+)"', text)}

files = []
for ext in ("tga", "jpg", "jpeg", "png"):
    files += glob.glob(os.path.join(client, "Screenshots", "WoWScrnShot_*." + ext))
files.sort(key=os.path.getmtime)
if not files:
    sys.exit("No screenshots in " + os.path.join(client, "Screenshots"))
# the newest burst: files no more than 20 s apart, counting back from the last
burst = [files[-1]]
for f in reversed(files[:-1]):
    if os.path.getmtime(burst[0]) - os.path.getmtime(f) > 20:
        break
    burst.insert(0, f)
if len(burst) < len(NAMES):
    print("Warning: the newest burst has %d screenshots, expected %d." % (len(burst), len(NAMES)))
burst = burst[-len(NAMES):]
names = NAMES[len(NAMES) - len(burst):]

out_dir = os.path.join(root, "Screenshots")
os.makedirs(out_dir, exist_ok=True)
for src, name in zip(burst, names):
    img = Image.open(src).convert("RGB")
    r = rects.get(name)
    if not r:
        print("  %s: no saved position, kept whole" % name)
        box = (0, 0, img.width, img.height)
    else:
        l, t, rr, b, w, h = r
        if not h:
            # (saved by 0.7.0's first /fn shots, which lost the screen height: the numbers are in
            # the game's UI units, where the screen is 768 tall)
            kx = ky = img.height / 768.0
        else:
            # the game saved pixels for its own screen size; scale if the image differs
            kx = img.width / float(w) if w else 1
            ky = img.height / float(h)
        box = (max(0, int(l * kx) - MARGIN), max(0, int(t * ky) - MARGIN),
               min(img.width, int(rr * kx) + MARGIN), min(img.height, int(b * ky) + MARGIN))
    out = os.path.join(out_dir, name + ".png")
    img.crop(box).save(out, optimize=True)
    print("  %s -> Screenshots/%s.png (%dx%d)" % (os.path.basename(src), name, box[2] - box[0], box[3] - box[1]))
