# Fieldnotes changelog

## 0.6.0

- **The map stays clear.** On the small map, Fieldnotes moves into a dock beside the map (on the
  left when there's no room on the right), with a Fieldnotes tab to fold it away. On the
  full-screen map it's one toolbar centred at the top, with the key in a bottom corner.
- **Everything in one place:** the profession (Skinning now; Mining, Herbalism and Fishing to
  come), the switch, View, Show, a leather list that scrolls as it grows (with Hides and Ruined
  scraps), the key, Stats and Share.
- **Start, pause and end a session from the map,** the same session as the tracker panel.
- **Settings, simpler:** Colors, When, and Strength and Spread sliders. Glow size and thin areas
  start from how much you have skinned, so a handful of skins shows straight away.
- **Smoother heat:** a finer grid, and the faintest heat fades into the map instead of ending
  at an edge.
- Smooth slides and fades: the dock folding, the settings sheet rising over it, and the
  toolbar narrowing to its centre as you switch Fieldnotes off.

## 0.5.0

- **Share your notes** (`/fn share`, or Share in the stats window): one line of text with this
  zone or all your skinning, selected and ready for Ctrl+C. Paste it in Discord, a forum post or
  a friend's Import box. It holds no character names, realms or times of day, just where, what
  and how much. One zone fits in a Discord message.
- **Import notes** (`/fn import`): paste someone's share text to see what's in it, then add it to
  your Community layer. It never mixes into your own numbers. A newer share from the same person
  replaces their older one, and Remove all empties the layer.

## 0.4.0

- **Stats window** (`/fn`): your skins, skins per minute, leather per hour and how often you get
  Ruined Leather Scraps; your best zones for leather per hour, with zones above your skill
  marked; what your skins gave you; and the creatures of the zone you are in. Me or Account
  at the top chooses whose skins it counts.
- **Session tracker**: a small panel you can drag anywhere. It appears with your first skin and
  shows the session's clock, skins, skins per minute, a bar for each minute and your loot.
  Pause stops the clock; it hides after two minutes without a skin. `/fn tracker` turns it off.
- Fieldnotes now shares Forever Goal Tracker's look: etched panels, gold for what is chosen,
  gold headings and the same switch and icons.
- **Continent and world maps** now show a badge on every zone you have notes for, sized and
  colored by its skins (or leather or hides), with the number inside. Hover for the zone's
  creatures and leather; click to open the zone.
- **Spotlight**, a third map view: the map dims, except where you skin.
- **Map settings** behind the gear in the map bar: the leather filter (moved here from the bar),
  five color schemes (Ember, Thermal, Frost, Verdant, Gold), what the heat counts (skins,
  leather or hides), when (all time, 30 or 7 days), strength, spread, and hiding thin areas.
  Reset puts them back. The gear turns gold while anything differs from the defaults.
- The map key now says how much the busiest area holds ("Up to 54 skins in one area").
- `/fn summary` prints the numbers in chat, as `/fn` used to.
- Demo skins now come in sessions, so the rates have something to measure.

## 0.3.0

- Your notes on the world map. Open any zone map:
  - **Heat** shows where you skin most as a soft glow, from pale amber (fewer) to deep red (more).
  - **Points** shows one dot per skin, colored by its leather.
  - **Me, Account or Community** chooses whose notes you see.
  - **Leather** filters the map to one kind of leather.
  - Up to three hot spot pins; hover one to see how many skins, which creatures and what leather.
  - A small key in the corner: the count, the leading creature and leather, and the color scale.
- Everything sits in one slim bar along the top of the map. Click Fieldnotes in the bar to switch
  the overlay off and on.
- Demo mode now includes a sample Community layer.

## 0.1.0

- Records every creature you skin: what it was, what it gave you and where you stood.
- Saved for your whole account, each skin marked with the character who made it.
- A short chat line after each skin (`/fn chat` turns it off).
- `/fn` shows your skinning so far, this session's skins per minute and this zone's
  top creatures and leather.
- Demo mode for trying it out: `/fn demo` loads sample skins across twelve zones,
  `/fn fake` pretends to skin something where you stand, `/fn demo off` removes it all.
  Your own records are never touched.
