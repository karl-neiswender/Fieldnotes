"""Checks Fieldnotes' Lua with real Lua 5.1 (the game's version).

1. Compiles every file in the .toc: catches syntax slips and Lua's 200-local limit.
2. Loads them against a small stand-in for the WoW API and plays a few skins:
   a real skin is recorded once (even when both loot events fire), an ordinary kill's loot
   and a failed cast are not, and /fn runs without errors.

Run from the repository folder:  python3 tools/check.py
Needs lupa. It reuses Forever Goal Tracker's copy (tools/.py) when that checkout sits next to
this one; otherwise:  pip3 install --target tools/.py lupa
"""
import os
import sys

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(here)
for p in (os.path.join(here, ".py"), os.path.join(root, "..", "ForeverGoalTracker", "tools", ".py")):
    if os.path.isdir(p):
        sys.path.insert(0, p)
from lupa import lua51  # noqa: E402

toc = open(os.path.join(root, "Fieldnotes.toc"), encoding="utf-8").read().splitlines()
FILES = [l.strip() for l in toc if l.strip().endswith(".lua")]

STUB = r"""
chat, handlers, now, clock = {}, {}, 100, 1700000000
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end }
-- frames, textures and font strings: any method not listed does nothing
local Widget = {}
Widget.__index = function(t, k)
  local m = rawget(Widget, k)
  if m then return m end
  return function() end
end
function NewWidget(kind) return setmetatable({ kind = kind, events = {}, scripts = {}, shown = true, w = 0, h = 0, text = "" }, Widget) end
function Widget:RegisterEvent(e) self.events[e] = true; handlers[#handlers + 1] = self end
function Widget:UnregisterEvent(e) self.events[e] = nil end
function Widget:SetScript(name, fn) self.scripts[name] = fn end
function Widget:HookScript(name, fn) self.scripts[name] = fn end
function Widget:Show() self.shown = true end
function Widget:Hide() self.shown = false end
function Widget:SetShown(v) self.shown = v and true or false end
function Widget:IsShown() return self.shown end
function Widget:SetSize(w, h) self.w, self.h = w, h end
function Widget:SetWidth(w) self.w = w end
function Widget:SetHeight(h) self.h = h end
function Widget:GetSize() return self.w, self.h end
function Widget:SetAllPoints(t) if t and t.w then self.w, self.h = t.w, t.h end end
function Widget:GetWidth() return self.w end
function Widget:GetHeight() return self.h end
function Widget:GetFrameLevel() return 1 end
function Widget:GetEffectiveScale() return 1 end
function Widget:SetText(t) self.text = tostring(t) end
function Widget:GetText() return self.text end
function Widget:GetStringWidth() return #self.text * 6 end
function Widget:GetStringHeight() return 12 end
function Widget:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function Widget:CreateTexture() local t = NewWidget("texture"); t.owner = self; textures[#textures + 1] = t; return t end
function Widget:CreateFontString() return NewWidget("fontstring") end
function Widget:Click() if self.scripts.OnClick then self.scripts.OnClick(self) end end
textures = {}
function CreateFrame(kind, name, parent) local f = NewWidget(kind); f.parent = parent; return f end
function Fire(e, ...)
  for _, f in ipairs(handlers) do if f.events[e] and f.scripts.OnEvent then f.scripts.OnEvent(f, e, ...) end end
end
function hooksecurefunc(t, k, fn) local old = t[k]; t[k] = function(...) old(...); fn() end end
GameTooltip = NewWidget("tooltip")
canvas = NewWidget("frame"); canvas.w, canvas.h = 1002, 668
WorldMapFrame = NewWidget("frame")
WorldMapFrame.ScrollContainer = NewWidget("frame")
WorldMapFrame.mapID = 1426
function WorldMapFrame:GetCanvas() return canvas end
function WorldMapFrame:GetMapID() return self.mapID end
function WorldMapFrame:OnMapChanged() end
Enum = { UIMapType = { Zone = 3 } }
-- textures on the map canvas that are showing (heat squares and dots)
function ShownOnMap()
  local n = 0
  for _, t in ipairs(textures) do if t.shown and t.owner and t.owner.parent == canvas then n = n + 1 end end
  return n
end
function GetTime() return now end
function time() return clock end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strsplit(sep, s)
  local out = {}
  for part in (s .. sep):gmatch("(.-)%" .. sep) do out[#out + 1] = part end
  return unpack(out)
end
function UnitName(u) if u == "player" then return "Tester" end return units[u] and units[u].name end
function GetRealmName() return "Realm" end
units = {}
function UnitExists(u) return units[u] ~= nil end
function UnitIsPlayer(u) return false end
function UnitIsDead(u) return units[u] and units[u].dead end
function UnitGUID(u) return units[u] and units[u].guid end
function UnitCreatureType(u) return "Beast" end
function UnitLevel(u) return units[u] and units[u].level or 0 end
function GetSpellInfo(id) if id == 8613 or id == 8618 then return "Skinning" end return "Other" end
function GetNumSkillLines() return 1 end
function GetSkillLineInfo() return "Skinning", false, false, skillRank or 225, 0, 0, skillMax or 300 end
C_Map = {
  GetBestMapForUnit = function() return 1434 end,
  GetPlayerMapPosition = function() return { GetXY = function() return 0.4712, 0.2201 end } end,
  GetMapInfo = function(id) return { name = "Stranglethorn Vale", mapType = id == 1415 and 2 or 3 } end,
  -- Eastern Kingdoms (1415) and a few of its zones, each with its rectangle on the continent
  GetMapChildrenInfo = function(id)
    if id ~= 1415 then return {} end
    local out = {}
    for _, z in ipairs({ 1426, 1429, 1434, 1436, 1417, 1418 }) do out[#out + 1] = { mapID = z, name = "Zone " .. z, mapType = 3 } end
    return out
  end,
  GetMapRectOnMap = function(z) local x = (z % 7) / 8; return x, x + 0.1, x * 0.8, x * 0.8 + 0.1 end,
}
function GetZoneText() return "Stranglethorn Vale" end
loot = {}
function GetNumLootItems() return #loot end
function LootSlotHasItem(i) return loot[i] ~= nil end
function GetLootSlotLink(i) return "|cffffffff|Hitem:" .. loot[i].id .. "::::::::|h[x]|h|r" end
function GetLootSlotInfo(i) return "icon", "x", loot[i].n end
function GetLootSourceInfo(i) return loot[i] and loot[i].guid, 1 end
function GetItemInfo(id) return nil end
SlashCmdList = {}
UIParent = NewWidget("frame")
UISpecialFrames = {}
function GetItemIcon() return 134400 end
C_Timer = { After = function(_, fn) fn() end }
"""

PLAY = r"""
local ns = {}
for _, name in ipairs(FILES) do
  local fn = assert(loadstring(SOURCES[name], "@" .. name))
  fn("Fieldnotes", ns)
end
Fire("ADDON_LOADED", "Fieldnotes")
Fire("PLAYER_LOGIN")

local tiger = "Creature-0-1-0-1-682-00000ABC"
units.mouseover = { name = "Stranglethorn Tiger", guid = tiger, dead = true, level = 33 }
Fire("UPDATE_MOUSEOVER_UNIT")

-- 1. a real skin, both loot events firing
Fire("UNIT_SPELLCAST_SENT", "player", "Stranglethorn Tiger", "cast-1", 8618)
now = now + 2
loot = { { id = 2319, n = 2, guid = tiger }, { id = 2934, n = 1, guid = tiger } }
Fire("LOOT_READY"); Fire("LOOT_OPENED"); Fire("LOOT_CLOSED")

-- 2. ordinary kill loot, no Skinning cast
now = now + 5
loot = { { id = 4306, n = 1, guid = tiger } }
Fire("LOOT_READY"); Fire("LOOT_CLOSED")

-- 3. a cast that fails, then loot
Fire("UNIT_SPELLCAST_SENT", "player", "Stranglethorn Tiger", "cast-2", 8618)
Fire("UNIT_SPELLCAST_FAILED", "player", "cast-2", 8618)
loot = { { id = 2319, n = 1, guid = tiger } }
Fire("LOOT_READY"); Fire("LOOT_CLOSED")

-- 4. a cast whose loot comes too late
Fire("UNIT_SPELLCAST_SENT", "player", "Stranglethorn Tiger", "cast-3", 8618)
now = now + 30
Fire("LOOT_READY"); Fire("LOOT_CLOSED")

SlashCmdList.FIELDNOTES("summary")
SlashCmdList.FIELDNOTES("")
local trackerShown = ns.session.count == 1
-- the skill cap: one trainer alert in chat, not two; the tracker folds and opens without an error
skillRank, skillMax = 75, 75
local said = 0
local before = #chat
Fire("SKILL_LINES_CHANGED")
Fire("SKILL_LINES_CHANGED")
for i = before + 1, #chat do if chat[i]:find("trainer to learn Journeyman") then said = said + 1 end end
FieldnotesDB.settings.trackerCompact = true
ns.UpdateTracker()
FieldnotesDB.settings.trackerCompact = false
ns.UpdateTracker()
skillRank, skillMax = nil, nil
local capAlert = said == 1
SlashCmdList.FIELDNOTES("chat")
SlashCmdList.FIELDNOTES("help")

-- 5. demo mode: sample data apart from the real records, fake skins only into the demo
local realBefore = #FieldnotesDB.events.skinning[1434]
SlashCmdList.FIELDNOTES("fake") -- refused before /fn demo
local refused = #FieldnotesDB.events.skinning[1434] == realBefore and FieldnotesDB.demo == nil
SlashCmdList.FIELDNOTES("demo")
local demoCount = 0
for _, l in pairs(FieldnotesDB.demo.events.skinning) do demoCount = demoCount + #l end
local demoStv = #FieldnotesDB.demo.events.skinning[1434]
SlashCmdList.FIELDNOTES("fake")
local faked = #FieldnotesDB.demo.events.skinning[1434] == demoStv + 1
local realAfter = #FieldnotesDB.events.skinning[1434]
for _, l in pairs(FieldnotesDB.demo.events.skinning) do
  for _, s in ipairs(l) do assert(ns.Decode(s), "bad demo record " .. s) end
end
-- 6. the map overlay, on the demo's Dun Morogh
local function Open(mode, show)
  FieldnotesDB.settings.map = FieldnotesDB.settings.map or {}
  if mode then FieldnotesDB.settings.map.mode = mode end
  if show then FieldnotesDB.settings.map.show = show end
  ns.Map.Refresh()
  return ShownOnMap()
end
WorldMapFrame.scripts.OnShow()
local heat = Open("heat", "account")
-- the dock lists the hot spots the map pins; Every skin lays dots over the heat
local spotsListed = ns.Map.model.spots and #ns.Map.model.spots or 0
FieldnotesDB.settings.map.dots = true
local heatDots = Open("heat", "account")
FieldnotesDB.settings.map.dots = false
local pointsMe, pointsAll, pointsCommunity = Open("points", "me"), Open("points", "account"), Open("points", "community")
WorldMapFrame.mapID = 947 -- a map with no notes
local empty = Open("heat", "account")
WorldMapFrame.mapID = 1426
FieldnotesDB.settings.map.on = false
local off = Open("heat", "account")
FieldnotesDB.settings.map.on = true
-- settings: Spotlight, Heat by Hides, every color scheme, the settings panel open
local spot = Open("spotlight", "account")
FieldnotesDB.settings.map.leather = "hides" -- hides are an entry in the leather list now
local hides = Open("heat", "account")
FieldnotesDB.settings.map.leather = 0
for _, c in ipairs({ "solar", "snowfall", "thermal" }) do
  FieldnotesDB.settings.map.colors = c
  Open("heat", "account")
end
local gear = ns.Map.ui.gear
gear.scripts.OnClick(gear)
Open("heat", "account")
local settingsOpen = ns.Map.ui.reset.shown and 1 or 0
FieldnotesDB.settings.map.when = 7
local recent = Open("heat", "account")
FieldnotesDB.settings.map.when = 0
WorldMapFrame.mapID = 1415 -- the continent: a badge per zone with notes
Open("heat", "account")
local continentBadges = ns.Map.ui.badgeCount
WorldMapFrame.mapID = 1426
-- the small map: a dock beside it (room on the right), the toolbar when maximized
local toolbarLayout = ns.Map.ui.layout
WorldMapFrame.IsMaximized = function() return false end
function WorldMapFrame:GetLeft() return 300 end
function WorldMapFrame:GetRight() return 1300 end
function UIParent:GetRight() return 1920 end
Open("points", "account")
local dockLayout = ns.Map.ui.layout
ns.SessionStart()
local sessionOn = ns.SessionRunning()
ns.SessionEnd()
print("map        layouts: maximized " .. tostring(toolbarLayout) .. ", small " .. tostring(dockLayout))
local layouts = (toolbarLayout == "toolbar" and dockLayout == "dock" and sessionOn and not ns.SessionRunning()) and 1 or 0
local mapResult = layouts .. "," .. continentBadges .. "," .. spot .. "," .. hides .. "," .. settingsOpen .. "," .. recent .. "," .. heat .. "," .. pointsMe .. "," .. pointsAll .. "," .. pointsCommunity .. "," .. empty .. "," .. off .. "," .. spotsListed .. "," .. heatDots

-- 7. the stats window on the demo
SlashCmdList.FIELDNOTES("")
SlashCmdList.FIELDNOTES("")
local u = ns.statsUI
local stats = u.tiles[1].value.text .. "|" .. u.tiles[2].value.text .. "|" .. u.tiles[3].value.text .. "|" .. u.tiles[4].value.text
FieldnotesDB.settings.statsShow = "me"
ns.RefreshStats()
local meSkins = u.tiles[1].value.text
FieldnotesDB.settings.statsShow = "account"

-- 8. sharing in demo mode: a round trip, a cut-off paste, an import into the demo's Community
local text, shSkins, shZones = ns.Share.Make(nil)
local back = ns.Share.Read(text)
local roundTrip = back ~= nil and back.skins == shSkins and back.zoneCount == shZones and back.demo
local cutOff = ns.Share.Read(text:sub(1, #text - 6)) == nil
local before = 0
for _, l in ipairs(ns.CommunityLists("skinning", 1426)) do before = before + #l end
local imported = ns.Share.Import(back)
local after = 0
for _, l in ipairs(ns.CommunityLists("skinning", 1426)) do after = after + #l end
SlashCmdList.FIELDNOTES("share")
local words = ns.shareUI.summary.text .. " | " .. ns.shareUI.fit.text.text
SlashCmdList.FIELDNOTES("import")
print("share      window: " .. words)
-- the window speaks in skins and zones, never "characters" (a WoW player reads that as alts)
local demoShare = roundTrip and cutOff and imported and after > before
  and words:find("skins", 1, true) and not words:lower():find("character", 1, true)

-- every command, in demo mode
commandErrors = {}
for _, cmd in ipairs({ "", "", "stats", "summary", "tracker", "tracker", "chat", "chat", "share", "import", "debug", "fake", "help" }) do
  local ok, err = pcall(SlashCmdList.FIELDNOTES, cmd)
  if not ok then commandErrors[#commandErrors + 1] = "/fn " .. cmd .. " (demo): " .. tostring(err) end
end
SlashCmdList.FIELDNOTES("demo off")
local cleared = FieldnotesDB.demo == nil and not FieldnotesDB.settings.demo

-- 9. sharing for real: demo text and your own text are refused, someone else's is added
local refusedDemo = not ns.Share.Import(back)
local mine = ns.Share.Read((ns.Share.Make(nil)))
local refusedOwn = mine ~= nil and not ns.Share.Import(mine)
local theirs = ns.Share.Read((ns.Share.Make(nil)):gsub("^!FN1!%w%w%w%w%w%w!", "!FN1!Zzzzzz!"))
local addedTheirs = theirs ~= nil and ns.Share.Import(theirs)
local communityReal = 0
for _, l in ipairs(ns.CommunityLists("skinning", 1434)) do communityReal = communityReal + #l end
local realShare = (refusedDemo and refusedOwn and addedTheirs and communityReal == 1) and "ok"
  or ("demo " .. tostring(refusedDemo) .. " own " .. tostring(refusedOwn) .. " theirs " .. tostring(addedTheirs) .. " n " .. communityReal)

-- every command again, with your own records
for _, cmd in ipairs({ "", "", "stats", "summary", "tracker", "tracker", "chat", "chat", "share", "import", "debug", "fake", "help" }) do
  local ok, err = pcall(SlashCmdList.FIELDNOTES, cmd)
  if not ok then commandErrors[#commandErrors + 1] = "/fn " .. cmd .. " (real): " .. tostring(err) end
end
mapError = ns.Map.lastError -- a draw error is caught (and said in chat), so check it here

local list = FieldnotesDB.events.skinning[1434]
return #list, list[1], FieldnotesDB.creatures[682].name, FieldnotesDB.creatures[682].minLevel, table.concat(chat, "\n"),
  refused, demoCount, faked, realAfter == realBefore, cleared, mapResult, stats, meSkins, trackerShown, demoShare, realShare, capAlert
"""

ok = True
rt = lua51.LuaRuntime()
sources = {}
for name in FILES:
    src = open(os.path.join(root, name), encoding="utf-8").read()
    sources[name] = src
    err = rt.eval("function(s, n) local f, e = loadstring(s, '@' .. n) return e end")(src, name)
    if err:
        ok = False
        print("COMPILE    " + err)
print(("compile    " if ok else "COMPILE    ") + ", ".join(FILES))

if ok:
    rt.execute(STUB)
    g = rt.globals()
    g.FILES = rt.table_from(FILES)
    g.SOURCES = rt.table_from(sources)
    count, first, cname, clevel, chat, refused, demo_count, faked, real_kept, cleared, map_result, stats, me_skins, tracker, demo_share, real_share, cap_alert = rt.execute(PLAY)
    print("share      real: %s" % real_share)
    print("stats      tiles %s, Me %s" % (stats, me_skins))
    layouts, continent, spot, hides, settings_open, recent, heat, p_me, p_all, p_comm, empty, off, spots_listed, heat_dots = [int(v) for v in map_result.split(",")]
    print("map        continent badges %d" % continent)
    print("map        spotlight %d, hides %d, last 7 days %d, settings panel %s" % (spot, hides, recent, "open" if settings_open else "closed"))
    print("map        heat %d, points me %d / account %d / community %d, empty map %d, off %d" % (heat, p_me, p_all, p_comm, empty, off))
    print("demo       %d sample skins" % demo_count)
    checks = [
        ("one skin recorded, not four", count == 1),
        ("record holds place, time, creature, character, skill and loot",
         first == "471:220:1700000000:682:1:225:2319=2,2934=1"),
        ("creature remembered from mouseover", cname == "Stranglethorn Tiger" and clevel == 33),
        ("/fn summary runs", "1 skins on this account" in chat),
        ("/fn fake refused outside demo mode", bool(refused)),
        ("/fn demo loads sample skins", demo_count > 1000),
        ("/fn fake adds one skin to the demo", bool(faked)),
        ("real records untouched by demo mode", bool(real_kept)),
        ("/fn demo off removes the sample data", bool(cleared)),
        ("map: heat squares drawn", heat > 20),
        ("map: hot spots are listed for the dock (1 to 3)", 1 <= spots_listed <= 3),
        ("map: Every skin lays dots over the heat", heat_dots > heat),
        ("map: points grow from Me to Account to Community", 0 < p_me < p_all < p_comm),
        ("map: a map without notes draws nothing but the dimming", empty <= 1),
        ("map: switched off draws nothing", off == 0),
        ("map: the continent shows a badge for each zone with notes", continent == 6),
        ("map: toolbar on the full-screen map, dock beside the small one; sessions start and end", layouts == 1),
        ("map: Spotlight dims the map", spot > heat),
        ("map: the Hides leather filter draws fewer areas than all skins", 0 < hides < heat),
        ("map: the settings panel opens", settings_open == 1),
        ("map: Last 7 days draws less than All time", recent < heat),
        ("map: drew without an error", rt.globals().mapError is None),
        ("every /fn command runs, in demo mode and with real records", len(list(rt.globals().commandErrors.values())) == 0),
        ("session tracker counts the real skin", bool(tracker)),
        ("skill cap: one trainer alert, the tracker folds and opens", bool(cap_alert)),
        ("share: demo text reads back whole, a cut-off paste is caught, import adds to Community", bool(demo_share)),
        ("share: demo text and your own text are refused; someone else's joins Community", real_share == "ok"),
        ("stats window fills its tiles", stats.split("|")[0].replace(",", "").isdigit() and stats.split("|")[1] != "-"),
        ("stats window: Me counts fewer skins than Account",
         0 < int(me_skins.replace(",", "")) < int(stats.split("|")[0].replace(",", ""))),
    ]
    for label, passed in checks:
        ok = ok and passed
        print(("ok         " if passed else "FAIL       ") + label)
    for e in rt.globals().commandErrors.values():
        print("COMMAND    " + e)
    if not ok:
        print("record: " + str(first))
        print(chat)

sys.exit(0 if ok else 1)
