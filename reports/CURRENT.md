# Current status (2026-11-03)

- Repository created. No add-on code yet, by design.
- Decisions: name **Fieldnotes**; Classic Era + Forever; heat map (Approach A) with a
  plot-point toggle (Approach C); Show: Me / My Account / Community; stats panel;
  low-friction sharing by copy-paste string, like Forever Goal Tracker's feedback link.
- GitHub: https://github.com/karl-neiswender/Fieldnotes (public), `main` pushed.
- Mockups in `design/mockups-2026-11-03` approved by Karl on 2026-11-03.
- v0.1.0 built (Core, Recorder, Stats): skin detection, account-wide records, `/fn`.
  `python3 tools/check.py` passes; copied to Era and Forever. Not yet tested in game.
- Demo mode (`/fn demo`, `/fn fake`, `/fn demo off`) works in game (Karl, Era, 2026-11-03).
- v0.3.0: Map.lua, the world map overlay, reviewed in game on Era (demo Dun Morogh):
  slim top bar (Heat/Points, Me/Account/Community, leather list), soft heat
  (Media/blob.tga), hover hot spot pins, corner key. Checks pass.
- Real skinning verified in game (Era, 2026-11-03): a level 10 character skinning from 1 in
  Dun Morogh; the skins were recorded and showed in the share window.
- Map bar hidden after maximizing the map (2026-11-03): the map's inner frames stay on a higher
  layer than the window, so Map.lua now re-picks its layer above the highest of window, scroll
  area and canvas on every redraw and after Maximize/Minimize. Fixed, confirmed in game.
  `/fn debug` reports the layers; map draw errors print once in chat.
- Not yet tested: Forever client; the redesigned share window in game.
- Style.lua: Forever Goal Tracker's look (etch, gold chosen state, title gold, pill switch,
  icons); map restyled with it, reviewed in game 2026-11-03.
- v0.4.0: Session.lua (session tracker), Panel.lua (stats window, /fn), map settings behind
  the gear (leather, 5 color schemes, Heat by, When, Strength, Spread, Thin areas), Spotlight
  view, continent/world zone badges (reviewed in game on Era 2026-11-03). Checks pass (21).
- Stats window and session tracker reviewed in game on Era (2026-11-03): taller zone rows,
  click a zone for its creatures, sample-data note in the header.
- Real skinning verified in game (Era, 2026-11-03): a level 10 character skinning from 1 in
  Dun Morogh; the skins were recorded and showed in the share window.
- Map bar hidden after maximizing the map (2026-11-03): the map's inner frames stay on a higher
  layer than the window, so Map.lua now re-picks its layer above the highest of window, scroll
  area and canvas on every redraw and after Maximize/Minimize. Fixed, confirmed in game.
  `/fn debug` reports the layers; map draw errors print once in chat.
- Not yet tested: Forever client; the redesigned share window in game.
- Known: on Kalimdor the Moonglade badge sits under the map bar.
- Ideas queued (Atlassian heatmap guide): comparison view (diverging Me vs Community),
  "when you skin" day x hour grid in stats, counts beside hot spot pins, stepped legend.
- v0.5.0: Share.lua: share text (32x32 tallies, per-share leather and per-zone creature lists,
  weeks not times, checksum, random share id; one zone ~1k characters) and Import into
  <store>.community.senders. Share window redesigned (Share | Import tabs, stats-window
  header, no "characters" wording). Checks pass (23).
- Not built yet: a community form link (needs Karl's form), shipping a merged community
  dataset with releases.
- Map v2 mockups (design/map-v2-2026-11-03, canvas bottom row): dock outside the small map with a
  profession switcher, leather dropdown, labelled key, session play/pause; centred toolbar on
  the full-screen map; settings cut to Colors and When. Motion spec in that folder's README.
- v0.6.0 builds it: Map.lua (drawing + model, auto spread/thin), MapUI.lua (dock, tab, sheet,
  toolbar, key, session controls), St.Animate in Style.lua, play/pause icons. Reviewed in game
  on Era (2026-11-03): dock fits at Karl's UI scale (slim session row, key gives up its last
  lines when short), dock measured from the map's border frame, Strength and Spread sliders
  (50-250%), smoother heat (72-wide grid, soft edge fade, alpha from zero). Checks pass (26),
  including every /fn command and no map draw errors.
- Heat and dots hidden under explored map art (2026-11-03): only a sliver of heat showed in a gap
  between explored areas. Map.lua's Layer() now puts the overlay one level above the map's
  exploration art (pin level manager + MapExplorationPinTemplate pins), under Blizzard's pins.
  Checks pass, copied to Era. Not yet confirmed in game.
- Known: a stray "ke" text shows past the right end of the map bar (seen 2026-11-03, not traced).
