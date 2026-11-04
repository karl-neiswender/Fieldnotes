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
