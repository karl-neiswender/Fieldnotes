# Era walkthrough review (2026-11-06)

Source: Karl's 5:51 narrated recording on Classic Era (1690x822, 30 fps), demo data. Read as contact
sheets every 3 s, then frame by frame (5-8 fps) at the zone change (1:06-1:16) and dashboard hovers
(0:39-0:44). Times are mm:ss into the recording.

## Bugs

All five fixed on 2026-11-06 (checks pass, copied to Era, not yet seen in game). Fix 1 kept the new
picture's fade-in, shortened to St.DUR.base. Fix 5 changed only the demo data; the chart already took
each day's highest value, so real data was fine.

1. **Ghost badges pop over the zone map** (1:12, 1:15). Clicking a continent zone shows the continent's
   badges (98, 206, 434...) at full size over the new zone's art for a few frames, and then they fade.
   Going back, faded copies sit beside the new badges. Era has no zoom, so the copies have nothing to
   follow. Cause: `GhostBadges()` in Map.lua:685, called from `Draw()` at Map.lua:996 on every map
   change. Fix: drop the ghosts (keep only the new layer's fade-in), or only ghost when OpenMap is zooming.
2. **Grey "sunbeams" on the dimmed donut** (3:49-4:00, Stats > Profession mix). The donut is built from
   N radial lines, each 0.9 px wider than its share so they overlap. Dimmed slices drop to alpha 0.35,
   and where two lines overlap the alpha stacks, so spokes show. Cause: `Light()` at StatsPage.lua:748.
   Fix: dim by mixing the color toward the card fill at alpha 1, not by lowering alpha.
3. **Dead hover gaps between dashboard rows** (0:39-0:44). Between two rows nothing is lit for a frame or
   two, so moving down the list flickers. Rows are DASH_ROW 40 with ROW_GAP 4 (MapUI.lua:1639-1640).
   Fix: extend each row's hit rect 2 px up and down (`SetHitRectInsets(0, 0, -2, -2)`), so the rows meet.
4. **Every skin tooltip runs off the screen** (2:42). "Lay one dot per skin over the h..." is cut off at
   the right edge. It is anchored `ANCHOR_BOTTOM` on a control near the screen's edge (MapUI.lua:1945).
   Fix: anchor it to the dock's left (`ANCHOR_LEFT`), or use CardTip's placement.
5. **Skill climb is a sawtooth** (4:40-5:30). In the demo the line drops back almost to zero again and
   again. The chart already keeps each day's highest value (StatsPage.lua:935), but Demo.lua gives each
   record a skill from the creature's level plus noise, not from time. This is demo-only, but the gallery
   and anyone running `/fn demo` see it. Fix: make demo skill rise with the record's time. Also plot a
   running maximum, so the line can never step down.

## Clarity

Items 6-11 were built on 2026-11-06, except for Home's empty space (11), which waits for a mockup. For
item 10, "Sample data" moved to the dock's header, where it costs no room in the key, so pages drop lines
the same way. Empty pages give a one-line how-to.

6. **The Stats subtitle says "All professions · Dun Morogh"**, but the stats are for every zone (Top zone
   says Elwynn Forest). Cause: MapUI.lua:2486. Fix: drop the place on Stats, or say "All zones".
7. **The Fieldnotes rail tab is always gold** (Karl), so it reads as selected next to the real active
   tab. Fix: rest it in the same silver as the other rail icons and keep gold for the active tab only.
8. **Letter badges in Stats** (B M F D T in Best zones, R C D Z Y in Ruined and creatures; Karl: "it
   doesn't mean anything"). Set by `SetRow(row, nil, name:sub(1, 1), ...)` at StatsPage.lua:876 and :1036.
   Fix: remove them and let the name start at the left edge. Possible later step: creature portraits
   (`SetPortraitTextureFromCreatureDisplayID` needs a display ID, which we don't store) or a zone icon.
9. **Hot spot coordinates can't be used** (Karl). Fix: a click on a hot spot row sets a waypoint: TomTom's
   `/way` if it's loaded, otherwise the game's own user waypoint where the client has it
   (`C_Map.SetUserWaypoint`; check it exists on Era as well as Forever). Show "Click for a waypoint" in
   the tooltip.
10. **The two key layouts don't match each other.** At the same height, Skinning shows 3 hot spots with no
   "skins in one spot" caption and no "Sample data" line, while Mining shows 2 spots, the caption and the
   note (2:30 vs 2:57). The key drops lines when short (by design), but the order makes pages look
   different. Fix: drop in a fixed order (caption first, then the third spot) and always keep the
   sample-data note while demo data is on.
11. **Empty space.** Home has a large gap under "2,914 gathers across 5 professions" (0:51). Treasure's
   empty page is one line on a tall empty card (4:12). Fix: on an empty page, give a short how-to ("Open
   chests while Fieldnotes is on; they show here"). On Home, either show the Session card higher or use
   the room for a "this week" line.

## Visual

12. **Dashboard row hover** (Karl: the bar and wash look basic). The Mining and Treasure washes come out
   muddy, red-brown and olive. Try: a brighter left bar (2 px to 3 px, full color), the wash only behind
   the left third and lighter, and the name lifted to the profession's color on hover.
13. **Use profession color in more places on its page** (Karl). Today only the radial glow and section
   labels carry it. Candidates: the place subtitle ("Dun Morogh", grey now), the active View segment's
   fill and edge, the total's number ("59 veins"), the key's rank discs, and the dropdown's chevron.
   Keep text contrast by using LabelTint's luminance matching.
14. **Hot spot rows are tight** (Karl, 2:57). Rank disc, count, name and coordinates sit in about 11 px.
   Fix: 2 px more line height, count in a fixed-width column, coordinates in SUBTEXT at 9.
15. **Fishing's hot spot name is cut short** ("Raw Brilliant Smallfish · Raw...", 4:20). With two items,
   show the top item and "+1".
16. **Rail tabs could sit closer** (Karl, "possibly"). There's room to cut 2-4 px between them, worth trying
   with #7.

## What worked (Karl's words and the frames agree)

- Profession pages, Heat and Points, Me and Account, material filters and their legend dimming.
- Hot spot hover: rows and pins light together and the ping reads well.
- Stats as a whole: Karl "really likes" it. Loot icons are a keeper (they are why letter badges look
  thin next to them).

## User-testing notes

- Karl expected scroll-zoom on Era and found click / right-click instead. That's the game, not us, but
  the continent view could say "Click a zone" in the key when it's empty.
- Hovering a continent badge shows "Click to open the zone map" (0:03). That was found without hunting:
  keep it.
- Karl went straight to the coordinates as something to act on. That says a waypoint is wanted more
  than just more information.

## Push Stats further (ideas, for Karl to pick from)

- Per-session history: the last 10 sessions with time, count and per hour, plus best-ever markers.
- Route efficiency: gathers per hour by zone and level range ("where should I go at 150 skill").
- Rare drops log: the first time each rare item dropped, when and where.
- Week-over-week: this week vs last, per profession.
