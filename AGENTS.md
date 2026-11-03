# Fieldnotes: shared project rules

Shared rules for Codex and Claude. Current user instructions take precedence.

## What Fieldnotes is

A gathering journal for Classic Era and Forever. It records every skin (later: ore,
herbs, fish) with the creature, the loot and where you stood, then draws it on the
world map as a density heat map (Approach A) with an optional plot-point layer
(Approach C), plus a stats panel. Skinning ships first; every other profession is a
module on the same event model. See [ROADMAP](ROADMAP.md) and
[CURRENT](reports/CURRENT.md).

## Working rules

- Karl is the creative director and a designer. Explain outcomes briefly and
  clearly. No em dashes in copy or responses. SIMPLE, HELPFUL, CLEAR.
- Visual mockups come before code. Do not start Lua for a feature until its mockup
  in `design/` is approved.
- Support Classic Era and Forever (TOC interfaces 11509 and 16001). Real Lua 5.1.
  Guard optional APIs. Do not infer Forever rules from Era.
- One event shape for every profession: profession, mapID, x, y, time, source
  (npcID / node), items { itemID = count }, character key. Never store names or
  realms in anything that can be shared.
- Sharing is copy-paste only: an add-on cannot reach the internet or the clipboard.
  Share strings and pre-filled links, the same pattern as Forever Goal Tracker's
  Send feedback window.
- **In-game fonts only.** Every visible string uses the game's own fonts through its
  font objects (`GameFontNormal`, `GameFontHighlightSmall`, `NumberFontNormal` ...)
  or `STANDARD_TEXT_FONT`. Ship no font files. Mockup typefaces are stand-ins.
- Map drawing uses pooled textures; no per-frame allocations, redraw only on map or
  filter change.

## Live checkout and copies

- PC checkout: `C:/Program Files (x86)/World of Warcraft/_classic_beta_/Interface/AddOns/Fieldnotes`.
- Classic Era and Forever get plain one-way copies: `sh tools/sync-era.sh` and
  `sh tools/sync-forever.sh` from Git Bash, then `/reload`. **Never link them**: the
  CurseForge app updates an add-on by deleting its folder's contents.
- SavedVariables are local. Never edit, reset or migrate live saves while testing.

## Git

- Commit identity: `karl-neiswender <97697208+karl-neiswender@users.noreply.github.com>`.
- Do not auto-commit or push each small change; sync `main` on request or at an
  agreed closeout. No release tag without Karl's authorization. Version tags trigger
  CurseForge packaging (`.github/workflows/release.yml`).
