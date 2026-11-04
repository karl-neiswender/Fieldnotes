# Gallery for 0.7.0

Taken on Classic Era with `/fn shots` (sample data from demo mode; everything is put back after).
Nothing has been uploaded yet. Upload in this order, with these titles and descriptions.

| File | Title | Description |
|---|---|---|
| `01-dashboard.png` | Everything you gather, on your map | Home shows every profession at a glance. Each gather is a dot in its profession's color; hover a profession to light its spots. |
| `02-heat.png` | Find the best grounds | A heat map of where you skin most, with numbered hot spots and a key with real counts. |
| `03-herbalism.png` | Five professions | Skinning, Mining, Herbalism, Fishing and Cloth, each with its own tab, materials and hot spots. Shown: Herbalism in the Solar colors. |
| `04-points.png` | Every gather, one dot | Points view colors each dot by what it gave you. |
| `05-community.png` | Community notes | Import notes other players share and see where everyone gathers. |
| `06-continent.png` | The whole continent | Continent and world maps show a badge on every zone you have notes for. |
| `07-session.png` | One session for everything | One clock for all your gathering: count, per hour, skill gained and a heads-up when it's time for a trainer. |
| `08-settings.png` | Make it yours | Colors, strength and spread, start sessions by hand, and share your notes. |
| `09-stats.png` | Your stats | Best zones for leather per hour and what each creature gives. |
| `10-share.png` | Share in one line | Copy a zone or everything as one line of text for Discord or a friend's Import box. |

## How to retake

1. In Classic Era, `/reload`, open nothing else, then `/fn shots` (or `/fn shots 03` for one).
   Keep the mouse off the map until chat says Done.
2. `/reload` again: the game saves where each subject sat.
3. `python tools/shots.py` (or `python tools/shots.py --only 03`) crops them into `Screenshots/`.
