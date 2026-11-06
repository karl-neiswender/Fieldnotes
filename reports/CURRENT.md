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
- Dock refinement pass (2026-11-03, Karl's notes on the v0.6.0 dock): the tab's "Fieldnotes" turns a
  quarter to read top to bottom (stacked letters only where text cannot turn); profession slots are
  placeholders (initials) until Karl's icons; the dock tucks against the map window's gold edge and
  runs down to its bottom edge (EDGE_TUCK in MapUI.lua, an estimate from a screenshot); Stats and
  Share are icons beside the gear in a footer under a rule (Media/icons/stats-white, share-white are
  placeholders); map settings rise inside the dock instead of a second panel; colors cut to Thermal
  (default) and Ember. Checks pass, copied to Era. Not yet seen in game; new icon files need a full
  client restart, not /reload. Saved color choices stay as they are: Reset to defaults picks Thermal.
- Second dock pass (2026-11-03): the turned tab word is re-centred (the game turns text about the top
  centre of its box); the leather list has flat rows (hover wash, gold bar and text for the chosen
  one, a rule under All leather), matches the button's scale and width, and its chevron flips while
  open; the dock's session row shows the clock, then "Paused" or the skins, clear of its icons.
  Checks pass, copied to Era. Not yet seen in game.
- Third dock pass (2026-11-03): the tab is as long as its word and chevron (about 100 instead of
  150), tucks under the dock's edge so the two read as one, and its tooltip says Open or Close.
  Movable windows (stats, share, tracker) now come to the front whole when opened or clicked, so
  stats and share no longer weave through each other. Checks pass, copied to Era. Not yet seen in game.
- Fourth dock pass (2026-11-03): tab padding evened (word one unit left, less room on top). The dock
  and tab take Forever Goal Tracker's window look: its warm brown fill (STYLE.dock in Style.lua, with
  a panel edge) and its grime texture (Media/grime.tga copied from FGT; St.Grime ports FGT.AddGrime,
  strongest at the top, fading down). Checks pass, copied to Era. Needs a full client restart for the
  new texture. Not yet seen in game.
- Stats and share windows get the same grime over their brown window fill (2026-11-03). Checks
  pass, copied to Era. Not yet seen in game.
- Map v3 mockup (design/map-v3-2026-11-03/Dock.html): hot spots list, quiet areas fading out,
  numbers on the key, dots over heat. Waiting for Karl's approval before any Lua.
- Map v3 built (approved 2026-11-03): quiet areas fade out (EDGE_FROM/EDGE_TO 0.06 to 0.32, M.Quiet);
  the key numbers its ramp from 1 to the busiest spot ("skins in one spot"), its left end fading
  the same way; pins show their rank and a gold ring (Media/ring.tga from FGT); the dock lists the
  hot spots under the key (row and pin light together, a click pings the pin; the list gives way
  when the dock is short); an "Every skin" switch beside View lays dots over Heat or Spotlight
  (setting map.dots). Checks pass (28), copied to Era. Needs a full client restart (new texture).
  Not yet seen in game.
- Map v3 fixes after Karl's first look (2026-11-03): the dock's hot spots moved into the key card
  (one line each: rank, skins, creature, coordinates; replacing Most skinned / Main leather), since a
  separate list never fit at Karl's UI scale; the key drops its caption, then spots, when short. The
  fade eases off with little data (SetFade in Map.lua: 0.015-0.12 for a busiest spot of 2 skins, up to
  0.06-0.32 from 20), so every pinned spot glows. Finer key ramp (64 steps), larger pin numbers,
  tighter dock top. New Snowfall color scheme after a snowfall forecast map (grey, blue, violet,
  magenta, pink, teal, lavender). Checks pass (28), copied to Era. Not yet seen in game.
- After Karl's Snowfall test (2026-11-03, Elwynn, Community): Snowfall now ends on a saturated
  lavender-violet (its pale top read as a gap); hot spot rows are 1 unit shorter and show the bare
  count, so three fit and creature names get room; pins and their rank numbers are sized for the
  screen (PinScale in Map.lua), since the map art's own smaller scale shrank them. Checks pass (28),
  copied to Era. Not yet seen in game.
- After Karl's Every skin test (2026-11-03): the key measures its room from the session row's real
  position (the added-up constants came out short, so the third hot spot never showed); dots over
  the heat lose their dark rims and shrink a size (Points keeps its rimmed dots); the key's ramp is
  16 edge-to-edge gradient stretches (overlapping segments striped its faint end). Checks pass (28),
  copied to Era. Not yet seen in game.
- Third hot spot (2026-11-03): it missed by rounding (needed about 127 of about 127). The card is
  2 units shorter and keeps 5 instead of 8 above the session row. /fn debug now prints the dock
  key's room, height and how many hot spots it shows. Checks pass (28), copied to Era. Not yet seen.
- Hot spot motion (2026-11-03, Karl): lit (row or pin hovered) shows a steady gold ring at once
  and a second ring breathing outward every 1.6 s; the dock's numbered badge breathes on the same
  clock. A click on a row pings the pin with two eased-out ripples, 0.22 s apart (PinMotion in
  Map.lua). Nothing runs while nothing moves. Checks pass (28), copied to Era. Not yet seen in game.
- Solar replaces Ember (2026-11-03, Karl's OKLCH gradient: deep indigo to pale butter yellow, 11
  of 32 stops in sRGB). A saved Ember choice reads as Solar. Checks pass (28), copied to Era.
- Color swatches show each scheme's whole ramp (8 slices of the round texture, most at the top),
  2026-11-03. Checks pass (28), copied to Era.
- Session tracker pass (2026-11-03, Karl): per-minute bars removed; a Skill row (rank / cap, "+N this
  session", a slim bar toward the cap); at a rank's cap (below 300) an orange note to see a trainer
  for the next rank, and once per cap a chat line, on-screen words and the raid warning sound
  (settings.capAlerted). The dot's green glow breathes while running (a game animation group).
  Pause / Resume carry icons; gold follows the likely next step (Resume while paused), End session
  stays neutral. A chevron folds the tracker to one line (settings.trackerCompact) with pause and
  end as icons. Checks pass (29), copied to Era. Not yet seen in game.
- Tracker refinements from Karl's recording (2026-11-03): the running dot's glow uses the soft heat
  texture (Media/blob, added light), starts fainter (0.35), swells to 1.8x and breathes every 2.4 s
  (a hard disc at 1.6x / 1.6 s read as busy). Folded, the tracker keeps its header and the three
  numbers; pause and end become header icons; at the skill cap one orange line stays. Checks pass
  (29), copied to Era. Not yet seen in game.
- Tracker, Karl's second recording (2026-11-03): glow brighter but still soft (0.7 start, 2.1x,
  2 s breath); the panel hangs from its top-left corner (re-anchored once, never mid-drag, saved
  that way), so folding moves only its bottom edge; the cap note is "Capped · train Journeyman"
  (chat keeps the fuller line). Checks pass (29), copied to Era. Not yet seen in game.
- Tracker, Karl's third recording (2026-11-03): the header groups status left (dot, title, clock)
  and controls right (pause, stop, fold), so the clock's width no longer nudges the icons. End is a
  stop square (Media/icons/stop-white.tga, new) wherever it is an icon: tracker, dock session row,
  full-screen toolbar; the settings close stays an X. The glow runs on GetTime like the map pins
  (the game's looping animation stuttered when the refresh restarted it). Checks pass (29), copied
  to Era. Needs a full client restart (new icon). Not yet seen in game.
- Session glow shared (St.Glow in Style.lua): the dock's Session row dot breathes like the tracker's
  while a session runs (2026-11-03). Checks pass (29), copied to Era. Not yet seen in game.
- Professions v4 (2026-11-04, mockup design/professions-v4-2026-11-04 approved by Karl with two changes:
  hovering a dashboard row lights that profession's dots, Mining is yellow). Built:
  Recorder.lua records Mining and Herbalism (cast, then loot; source = the node's object ID, names in
  <store>.nodes), Fishing (IsFishingLoot; source 0) and Cloth (every humanoid kill loot, with its cloth or
  empty, once per corpse; any creature once it drops cloth; Pick Pocket left out). Map.lua: M.PROFS (identity
  colors), settings.map.prof ("all" = dashboard), Records per profession, M.Summary, the dashboard map (dots
  in profession colors, M.SetLit for hover). MapUI.lua: the profession row is gone; profession tabs hang
  under the Fieldnotes tab (known professions, Cloth, any with notes outside Me); the Fieldnotes tab opens
  the dashboard (Show, When, a row per profession with count, best zone or cloth rate, skill bar), then
  folds. Session.lua: one session for every profession, a row each (count, per hour, skill +N or cap note),
  folded to one line of initials and counts; cap alerts per profession. Demo adds ore, herbs, fish and
  cloth. Checks pass (38), copied to Era. Not yet seen in game. Stats and Share stay skinning-only; the
  full-screen toolbar has no profession switch yet; icons are initials until Codex's set.
- v4 UX pass after Karl's first Elwynn look (2026-11-04): the dock spans the map window's full height
  (title bar to footer, inset the same at both ends); the tab rail is Fieldnotes, the profession tabs, a
  gap, then Stats and Settings tabs (the footer is gone; the Settings tab is the old gear, settings fill the
  dock); only the Fieldnotes tab shows while folded, the rest fade with the dock. Settings gains SESSION
  ("Start with my first gather", settings.autoSession, default on) and SHARE (opens the share window).
  Dashboard rows are compact (30 tall, 11/9 type, a color bar instead of the repeated mark, hairline skill
  bar, cloth as "41% drop rate"), which also clears the session row. Checks pass (39), copied to Era. Not
  yet seen in game. Open/fold motion waits for Karl's video.
- Karl's second v4 look (2026-11-04): dashboard row hover is a wash of the profession's color fading left
  to right (the bar no longer thickens); the tab rail starts 14 under the dock's top (TAB_DROP); the Stats
  tab lights only while the stats window is open (FN.StatsShown, refreshed on close); Settings and the
  dashboard scroll (St.Scroll in Style.lua, after FGT's CreateScrollArea: wheel, slim bronze thumb, a
  28-strip bottom shade that eases away at the end). The profession page still fits by dropping key lines.
  Checks pass (39), copied to Era. Not yet seen in game.
- Karl's third v4 look (2026-11-04): When left the dock's settings (the dashboard has it; the full-screen
  map's settings keep it); Stats and Settings tabs sit at the dock's bottom (never over the profession
  tabs); settings slide in from the dock's left edge (the dock's content drifts right and fades) with a
  back chevron before the title instead of an X. Spacing pass on a 4-unit scale (MapUI.lua FIRST_Y,
  LABEL_GAP 16, CTRL_H 22, GROUP_GAP 16): labels no longer crowd the controls above; dashboard rows 34 tall
  with 4 between and 6 card padding, more inner padding; settings gaps opened up. Checks pass (39), copied
  to Era. Not yet seen in game.
- Codex's icon set (design/icons-v2-2026-11-04, painted silver relief) and logo (design/branding/selected)
  installed 2026-11-04. tools/icons.py balances the set to one optical size: each 64 px source is scaled by
  (0.34 / ink coverage) ^ 0.35, capped at a 58 px box, centred, written to Media/icons/*-white.tga (gear
  included; its source saved as gear-64.png). Coverage went from 28-71% to 28-41%; review sheet
  Balanced-sheet.png. Used: profession tabs and dock title, Stats and Settings tabs (both 16 now), tracker
  rows (icon on the color chip) and its folded line (inline icons), the warning triangle before every cap
  note, the share arrow on Settings' Share button. Media/icon.tga (the logo, 64 px) is the TOC IconTexture.
  Checks pass (39), copied to Era. Needs a full client restart (new and changed textures). Not yet seen.
- Rail tabs, Karl's notes (2026-11-04): a Home tab (Codex's book, balanced by tools/icons.py) opens the
  dashboard; the Fieldnotes tab now only opens and closes, and opening lands on Home; tabs never fold
  the dock. Every rail icon rests in one silver (REST in MapUI.lua); color is for the active tab only (its
  profession's, gold for Home, Stats, Settings). No left edge: the active tab has a soft glow behind its
  icon and a wash of its color fading outward, and reaches TAB_SLIDE (8) further out; hovered, 0.4 of
  that. One eased value per tab (Glide/ApplyTab, 0.22 s) drives width, color, glow and wash, so every
  change glides; folding resets them, so the active tab glides out again on open. Checks pass (39),
  copied to Era. Needs a full client restart (book icon). Not yet seen in game.
- Rail tabs, Karl's next look (2026-11-04): inactive tabs are plain (a texture's alpha did not hide a
  gradient's colour in game, so each inactive tab kept a tint: the wash is now hidden, and rebuilt with its
  alpha inside the gradient while active). No glow around the icon (it muddied it). Active: the icon in its
  color, a wash fading out from the dock, and an 8 px light along the edge shared with the dock (edgeLight).
  Checks pass (39), copied to Era (/reload is enough). Not yet seen in game.
- Active tab light redrawn (2026-11-04): in game the HGradient wash came out as a solid gold block, so the
  light is 14 flat strips from the dock-side edge outward (alpha 0.55(1-x)^4 + 0.16(1-x)), as FGT builds
  its fades. The scroll thumb moved inside the dock's border. Checks pass (39), copied to Era. Not yet seen.
- Active tab light, third try (2026-11-04): the strips banded. Now one texture, Media/fade.tga (256x4
  white, alpha (1-x)^2.2, smooth because the game filters it), tinted to the tab's color at 0.42 alpha,
  flipped by tex coords for a dock on the left. The dashboard row hover uses the same texture (0.22).
  Checks pass (39), copied to Era. Needs a full client restart (new texture). Not yet seen in game.
- Rail tabs refinement (2026-11-04, Karl approved): the active tab joins the dock. A seam frame (7 wide,
  4 into the dock, above the dock's border) is filled with the dock's own fill at that height plus the
  light's first tint, hiding the borders that read as a black bar; the active tab's fill becomes the dock's
  fill at its height (DockFill: STYLE.dock's gradient plus the grime's top lift). The light is softer and
  longer: peak 0.28, Media/fade.tga now (1-x)^1.4. Inactive tabs are recessed (fill x0.72). All eased by
  the tab's one value. Checks pass (39), copied to Era. Needs a full client restart (fade.tga changed).
  Not yet seen in game.
- Active tab, fourth pass (2026-11-04, Karl: not blending, light should be subtler and come from the right):
  the guessed seam color showed as a lighter block. Now each tab carries a copy of the dock's own background
  (STYLE.dock gradient and St.Grime on the dock's rectangle, extended right), seen through a clipping window
  (a child of the dock, above its border) over the tab and 5 px of the dock's edge; shown while active, it
  erases the border between them. The light comes in from the tab's outer edge (peak 0.14, 85% of the tab).
  Icons sit above the copy. Checks pass (39), copied to Era (/reload). Not yet seen in game.
- 2026-11-04: the tab light had vanished (a texture on the clipping window drew under its child frames);
  it now has its own frame above the copied page, peak 0.2. Profession pages get a glow (Karl): Media/radial
  (256 px, smooth radial alpha), tinted to the profession, alpha 0.16, centred on the title icon with a
  radius of half the dock's height, cut to the dock by texture coordinates, under all content; fades in
  0.4 s on a page change, none on Home or with Settings open. Checks pass (39), copied to Era. Needs a full
  client restart (new texture). Not yet seen in game.
- Tab light, still invisible though /fn debug had it shown at 0.34 (2026-11-04): moved onto the icon's
  frame (BACKGROUND layer, under the icon), the layer known to draw above the copied page; the page and the
  light use corner anchors only (the TOP/BOTTOM plus LEFT/RIGHT anchors were over-constrained). /fn debug
  prints the active tab's page, layers and light. Checks pass (39), copied to Era (/reload). Not yet seen.
- The tab light shows now (Karl, 2026-11-04: "looking great"). Profession pages' section labels (VIEW, SHOW,
  the material) take the profession's hue at the grey label's lightness (LabelTint: luminance-matched,
  x1.12, softened 30% toward the grey). Checks pass (39), copied to Era (/reload). Not yet seen.
- 0.7.0 release prep (2026-11-04): TOC 0.7.0 with new Notes; CHANGELOG 0.7.0; README and ROADMAP rewritten
  for five professions; reports/CurseForge-description-0.7.0.md and CurseForge-gallery-0.7.0.md (FGT's
  format, AI disclaimer). Shots.lua: /fn shots stages ten demo scenes (dashboard, heat, herbalism, points,
  community, continent, session, settings, stats, share), takes TGA screenshots and saves each subject's
  pixel rect in FieldnotesDB.shotRects; tools/shots.py crops the newest Era burst into Screenshots/ after a
  /reload. Screenshots/ is left out of the package and the Era copy. Checks pass (39), copied to Era.
  Waiting on: Karl's /fn shots run, the CurseForge project (ID for the TOC, CF_API_KEY secret), the tag.
- CurseForge project created (2026-11-04): Fieldnotes, ID 1783590 (in the TOC), MIT, 3rd-party distribution
  allowed, categories Professions + Map & Minimap, Skinning, Mining, Herbalism. Awaiting moderation. Pushed.
  Still to do: CF_API_KEY repo secret, the v0.7.0 tag (Karl's go), gallery shots.
- v0.7.0 released (2026-11-04): CF_API_KEY added by Karl; tag v0.7.0 pushed; the Release workflow passed
  (16 s) and uploaded v0.7.0 to project 1783590 as a Release for game versions 1.15.9 and 1.60.1, now
  Under Review with the project. Still to do: gallery shots (/fn shots), Forever checks after launch.
- Demo spots on walkable ground (2026-11-04, Karl: some samples sat in mountains or the sea): every spot
  moved onto known places (towns, camps, mines, lakeshores, creature grounds), spreads tightened (about
  half), the scatter cut off at 1.8 spreads, and the Community layer's random extra spot replaced by a
  fixed one per zone (COMMUNITY_EXTRA). Coordinates are from memory: check them in the gallery shots.
  Checks pass, copied to Era. Not yet seen.
- First gallery run (2026-11-04): shots.py now handles the first run's rects (Shots.lua lost the screen
  height to `a and f()`, fixed). The run showed stale sample data (saved demo from before the spot fix):
  /fn shots now always rebuilds the demo. Checked every crop against the map art: Dun Morogh's only lake is
  east of Kharanos, so fishing sits on its shores; Dun Morogh and Stranglethorn spots nudged onto open
  ground; Spotlight's key no longer says "skin" on other pages; the session shot puts the tracker beside
  the dock (put back after). Checks pass, copied to Era. Retake pending.
- Gallery taken and checked (2026-11-04): all ten shots cropped into Screenshots/ (contact sheet
  design/Gallery-0.7.0-contact-sheet.png); every sample spot on walkable ground; session shot has the tracker
  beside the dock. Not uploaded yet (CurseForge Media tab, titles in reports/CurseForge-gallery-0.7.0.md).
- Full-screen map pass (2026-11-04, Karl's notes): the heat seemed broken because the toolbar had no
  profession switch and sat on Home (the dashboard draws dots, never heat). The toolbar now spans the
  map's full width flush under the title band: name, switch and page buttons (Home plus each profession,
  as on the rail) on the left, then View, Show and the material list (View and the list hide on Home);
  session, Stats, Share and the gear at the right end. Switched off it narrows to name and switch in the
  top left corner. The key snaps into the bottom corner and lists the hot spots (rank, count, creature,
  coordinates; hover lights the pin, click pings it); on Home it shows each profession's color and count.
  Checks pass, copied to Era. Not yet seen in game.
- Key legend and material colors (2026-11-04, Karl): the key's legend entries are buttons. In Points a
  material shows only its own dots (click again for all; the same setting as the material list), the
  others step back while one is chosen, and all five stay listed. On Home a profession entry lights its
  dots on hover and opens its page on click. Materials keep to their profession's hue (M.PALETTES in
  Map.lua): mining yellows, herbs greens, fish blues, cloth purples; skinning keeps its palette. Checks pass
  (39), copied to Era. Not yet seen in game.
- Full-screen key keeps one height (2026-11-04, Karl: it jumped while switching views): hudKey.fixedH 156,
  room for the count, numbered ramp, three hot spots and the sample note, which now sits on the card's
  bottom edge. Taller content (a continent's scale line) still grows it. The dock's key is unchanged.
  Checks pass (39), copied to Era. Not yet seen in game.
- Switch fix (2026-11-04, Karl): after /reload the full-screen toolbar's switch was a blank white pill
  until hovered, and a click only showed its new state after the mouse left. The toolbar never painted
  it (only the dock did). Switch now has Sync() (state from settings, hover lift from MouseIsOver),
  called by both layouts on every draw and on click. Checks pass (39), copied to Era. Not yet seen.
- Community switched off (2026-11-04, Karl): the Show row's Community button (dock, Home dashboard and
  full-screen toolbar, via ShowChoice in MapUI.lua) is dimmed with a "Coming soon" tooltip and does
  nothing; a saved Community choice falls back to Account on load. The Community layer, imports and
  /fn shots still work underneath. To bring it back, drop `soon = true` from SHOWS. Checks pass (39),
  copied to Era. Not yet seen in game.
- Motion pass (2026-11-04, Karl's recording of the dock folding): the dock moved 24 while its tab and
  rail moved 220, so the tab and icons swept across the dock's words before the tab snapped into place.
  Now dock, tab and rail slide as one piece, the whole width (St.DUR.slow 0.34 s, "soft" arriving,
  "leave" departing), and the content fades as v squared, so it is gone before it reaches the map edge.
  Style.lua: St.DUR (quick 0.16, base 0.26, slow 0.34), easings "soft" and "leave"; movable windows
  (stats, share, tracker) fade in on open (closing stays instant). Settings slide, pop-over, toolbar,
  key, heat fade and rail glide use the shared durations and easings. Checks pass (39), copied to Era
  (/reload). Not yet seen in game; needs a new recording to judge.
- Motion pass, second look (2026-11-04, Karl's recording, read frame by frame at 30 fps): the dock, tab and
  rail now slide as one piece (fold takes about 0.23 s). A faint grey ghost of the dock's fill lingered for
  2 to 3 frames after its text was gone, so the fade is cubed (v^3) and folding takes St.DUR.base (0.26)
  while opening keeps St.DUR.slow (0.34). Checks pass (39), copied to Era. Not yet seen.
- Dock clipping (2026-11-04, Karl: sliding pieces lingered over the map): the dock, the Fieldnotes tab and
  every rail tab are now children of one clipping window (dockClip, SetClipsChildren) that starts at the
  dock's resting edge (the tab's folded position, 1 px of margin) and runs outward, taller than the dock.
  Sliding toward the map, everything is cut off at that edge, as if emerging from behind the map window.
  LayoutDock places it per side. Checks pass (39), copied to Era. Not yet seen in game (frame levels moved
  up by one; watch the tab and rail tabs' layering and tooltips).
- Full-screen polish (2026-11-04, Karl's screenshots): the key's tooltips (hot spots, legend) now sit above
  the card (CardTip) instead of over its numbers; hot spot rows and legend entries hover as pills
  (St.Pill in Style.lua: Media/pill in three slices, true round ends); the full-screen key is glass
  (fill 0.74 plus a radial lift centred on the bottom-left corner, so the map shows through at the top
  right; the dock's key stays solid); Stats and Share are icon buttons and the session chip reads "Start"
  (the heat page ran out of room and dropped Stats and Share, and the leather list touched the session
  chip); toolbar fill 0.98 (the map's own hint text ghosted through at 0.94); pin numbers are outlined
  (lost in dense Points clusters). Checks pass (39), copied to Era. Not yet seen in game.
- Home bar chart (2026-11-04, Karl approved): on Home the full-screen key's legend became five rows, each a
  profession dot and name, a pill bar in its color sized to its share of the busiest profession (faint track
  behind), and its count at the right. Rows stay buttons (hover lights that profession's dots, click opens
  its page). Map.lua's dashboard legend carries count and frac. Checks pass (39), copied to Era. Not yet seen.
- Karl's notes on the Home key and toolbar (2026-11-04): (1) a Home key row's tooltip said "Open Mining" but
  the click did nothing in game (it passed in the harness, so likely an engine detail): the key no longer
  hides and re-shows its legend buttons on every redraw (it hid the one under the cursor), and legend rows
  act on press (RegisterForClicks LeftButtonDown). (2) Skinning opened on Hides because the leather filter
  is one setting shared by every page: M.SetProf (Map.lua) now clears it whenever the page changes (dock
  tabs, toolbar page buttons, key rows). (3) Toolbar spacing rebuilt on one rhythm: 4 between buttons, 10
  either side of every divider (measured from button edges), 14 at both ends; the material list takes the
  room that is left (96 to 150) before Stats and Share give way. New check for (1) and (2). Checks pass
  (40), copied to Era. Not yet seen in game.
- Lua error "invalid key to 'next'" at Style.lua St.Animate's driver (Karl, 2026-11-04): a tween's apply or
  done started another tween (a dock fold sets the rail tabs gliding) while pairs() walked `tweens`. The
  driver now walks a snapshot of the ids and leaves a tween replaced mid-run alone. Checks pass (40), copied
  to Era. The harness does not run the driver's OnUpdate, so this is verified by reading, not by a check.
- Dashboard redesign (2026-11-04, Karl approved the review, no mockup): Show and When are two compact rows
  with no section labels (about 48 units back for the rows); Community stays dimmed with its "Coming soon"
  tooltip. Rows: "68 skins" with its unit; the line under the name is "41 here" (the map you are on:
  M.Summary now carries `here`, keyed by map), else "most in <zone>", "No gathers yet" or "Not learned";
  the right-hand line is "Skill 75 / 75", an orange "Capped, train next rank" (rank at its cap, below 300),
  or cloth's drop rate; skill is a 3 px rounded bar (St.Pill). Every row opens its page (a profession with
  nothing yet gets its tab and a page saying "You haven't learned X yet."); a chevron slides in on hover.
  A totals line under the card ("73 gathers across 2 professions"); the Session card says "Idle" beside its
  grey dot; small grey text (C.SUBTEXT) lifted from 0.541 to 0.60. Checks pass (41), copied to Era. Not seen.
- Dashboard fix (2026-11-04, Karl's screenshot): the Show row (Me, Account, Community) was missing, pushed
  above the scroll area by a +38 offset. The controls now start where the old SHOW label sat.
- Dashboard dropdowns (2026-11-04, Karl: spacing felt tight; the totals line was cut off by the Session card):
  Show and When are two dropdowns on one row (Dropdown in MapUI.lua), about 28 units back. The leather list is
  now the add-on's one dropdown list: the opening button hands it a provider (items, chosen key, pick action,
  rule after "All"); items can be plain (no dot) or disabled. Community is in the Show menu, dimmed, with
  "Coming soon" beside it, and ignores clicks. The profession pages keep their button rows. Checks pass (41),
  copied to Era. Not yet seen in game.

- 2026-11-04 (Forever + OpenMap): overlay now sits above OpenMap's art (OpenMapAPI.ArtTopLevel); badges
  and dots keep their on-screen size at any zoom; dashboard folds unlearned professions into one line.
  PARKED: smooth continent<->zone zoom transition. Map.lua has a fade-in on map change plus fading
  badge copies (GhostBadges); `/fn debug` shows they fire, but Karl saw no difference in game. Next try:
  tie the blend to OpenMap's zoom (OpenMapAPI.GetView) instead of the map-ID change. Not committed.
- Hot spots hidden until hovered (2026-11-05, Karl chose option E from inline mockups). Each pin is
  an invisible hover area the size of its cluster (HIT_REACH 2.2 cells either side; peaks are 6 apart,
  so areas never overlap) that takes no clicks (SetMouseClickEnabled(false), guarded; without it the
  area shrinks back to the marker). Hover or a lit dock row fades in the marker, rank and gold ring
  (St.DUR.quick); the tooltip follows after 0.15 s, anchored to the marker. A ping shows it for the
  ripple. Settings > HOT SPOTS > "Always show hot spots" (settings.map.spotsShown, default off).
  Checks pass (43), copied to Era and Forever. Seen in Karl's recording (Dun Morogh, Skinning and
  Mining): hover, dock rows and the fade all work. Fixed from it: the tooltip said "skins" on every
  page; it now uses the profession's word (veins, herbs...). Still to confirm: map clicks pass
  through the hover areas.
- Rail tab frames on Forever (2026-11-05, Karl's screenshot: "funky"): the open tab's game art kept the
  template's own size, centred, so a dark gap sat at the dock edge and the tab's etched box showed past
  the gold; closed tabs had a different frame. Now every rail tab wears LargeSideTabButtonTemplate (a
  plain copy always, a chosen copy over it at the tab's active strength), every piece stretched to fill
  the visible part of the tab. Icon frame at dock level +9 always, art two under it. Era keeps the
  gold-turning tooltip border. Checks pass (43), copied to Era and Forever. Not yet seen in game: watch
  for stretched bevel corners (the art is about 1.3x wider than its own shape).
- v0.8.0 release (2026-11-05, Karl's go): TOC 0.8.0 (Notes add treasure chests), CHANGELOG 0.8.0
  (Treasure, Stats page, hidden hot spots, Home dashboard, full-screen toolbar, profession colors,
  Forever side tabs, OpenMap, fixes). Includes the rail tab frame fix, unseen in game (Karl chose to
  ship it). Tag v0.8.0 pushed to trigger the CurseForge workflow.
- 2026-11-06 (Karl): v0.8.0 went through on CurseForge. In-game sessions on Forever work as intended,
  rail tab frames included. Still open: visual polish passes on both Forever and Era (nothing broken).
- Era walkthrough review (2026-11-06): Karl's narrated recording, 16 findings in
  reports/Review-Era-video-2026-11-06.md. The 5 bugs are fixed: ghost badge copies removed (a new map's
  picture still fades in, now St.DUR.base); donut slices dim by mixing toward the empty track at full
  alpha (lowered alpha stacked into grey spokes); dashboard rows' hover areas reach half the gap
  (no dead strip); the Every skin tooltip opens inward from the switch; demo skill climbs with time
  (SkillAt in Demo.lua; /fn demo off then /fn demo to rebuild). Checks pass (43), copied to Era.
  Not yet seen in game. Clarity and visual items (6-16) wait for Karl's pick.
- Clarity items 6-11 built (2026-11-06): the Stats subtitle reads "All zones" (stats count every zone);
  the Fieldnotes tab is never shown chosen (Forever: SetChecked(false); Era: STYLE.dock edge, warm only
  on hover); Stats rows lose their letter badges (SetRow takes an icon or nil, the name then starts at
  the left); a click on a hot spot row also sets a waypoint (M.Waypoint in Map.lua: TomTom if loaded,
  else C_Map.SetUserWaypoint where the client has it, all guarded; tooltip "Click to set a waypoint
  here" only then; a chat line confirms); the dock's "Sample data" moved from the key's last line to the
  dock header (demoInHeader), so it never costs a hot spot; empty profession pages add how they fill (HOW
  in Map.lua). Home's empty space is left for a mockup. Checks pass (43), copied to Era and Forever. Not
  yet seen in game; unknown whether Era has C_Map.SetUserWaypoint (without TomTom the hint simply
  does not show).
- Karl's check of 6-11 (2026-11-06): 7, 8, 10 OK. Fixed after: (6) the Stats subtitle went stale when a
  chip changed the profession (it only refreshed on a full render): StatsPlace in MapUI.lua, called by
  the chips through opts.OnPick. (9) Era has no map pins, so without TomTom the coordinates hid: M.CanWaypoint
  is strict (every C_Map/UiMapPoint/C_SuperTrack piece, and CanSetUserWaypointOnMap says yes), and the
  hot spot rows and pin tooltips show coordinates only when it is true. (11) the key's message: line
  height 120% (SetSpacing 2.2 at 11), 12 padding above and below. Checks pass (43), copied to Era and
  Forever. Not yet seen in game.
- Visual items 14-16 built (2026-11-06): hot spot rows 19 tall (was 17), the count in a 30-wide
  right-aligned column, coordinates 9 in SUBTEXT; rows show the top name or item plus "+N" (whoShort /
  lootShort in Map.lua), with the full list in the tooltip; rail tab gap 2 (was 4). Checks pass (43),
  copied to Era and Forever. Not yet seen in game. Items 12 (row hover) and 13 (profession color on its
  page) were shown as inline mockups (hover A today / B lifted row / C short glow; color 1 subtle /
  2 strong) and wait for Karl's pick.
- Karl picked hover C (plus a colored name) and color 2 (2026-11-06). Built: dashboard rows on hover lift
  a step (5% warm white), a glow of the profession's color leaves the bar and fades out by 35% of the
  row (fade.tga, 0.26), the bar goes 2 to 3 px, and the name takes NameTint (the hue lifted to bright
  text). Profession pages: title in NameTint, place in LabelTint, the chosen View button in the
  profession's own chosen look (St.AccentLook in Style.lua: ChoiceButton's b.look; dock and full-screen
  toolbar), and the key's total number in NameTint. Show (Me / Account) stays gold, as in the mockup.
  Stats and Home keep gold titles. Checks pass (43), copied to Era and Forever. Not yet seen in game.
- After Karl's screenshots of every page (2026-11-06): Home row glow softened (0.26 to 0.18); its chevron
  arrives in NameTint. Then one accent per page, gold for the add-on itself (Karl: "all of it"): Show
  buttons take the page's AccentLook too (dock and toolbar); the "Every ..." switch's on state is the
  profession's (St.ToggleLook in Style.lua, toggle.onLook; the master switch and Session Start stay
  gold); section labels back to grey; "Sample data" in grey; the first hot spot's badge and halo in the
  profession's color (map pins keep their gold ring). Treasure is teal now ({0.25, 0.78, 0.68}, palette
  of teals; it melted into the UI gold), and Fishing's fourth material moved from teal to indigo. Checks
  pass (43), copied to Era and Forever. Not yet seen in game.
- v0.8.1 release (2026-11-06, Karl's go): TOC 0.8.1, CHANGELOG 0.8.1 (waypoints, page colors, teal
  Treasure, hot spot rows, fixes from the Era walkthrough). Tag v0.8.1 pushed to trigger the CurseForge
  workflow.
