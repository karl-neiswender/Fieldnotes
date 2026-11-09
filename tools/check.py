"""Checks Fieldnotes' Lua with real Lua 5.1 (the game's version).

1. Compiles every file in the .toc: catches syntax slips and Lua's 200-local limit.
2. Loads them against a small stand-in for the WoW API and plays a few skins:
   a real skin is recorded once (even when both loot events fire), an ordinary kill's loot
   and a failed cast are not, and /fn runs without errors.
3. Plays it all twice: as Classic Era (the old item globals, GetItemInfo) and as Forever (only
   C_Item, and the game's side tab template). Forever dropped the old globals, which broke every
   item page there while these checks, Era-only, still passed (2026-11-05).

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
function Widget:CreateLine() local l = NewWidget("line"); l.owner = self; return l end
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
function UnitCreatureType(u) return units[u] and units[u].type or "Beast" end
function UnitLevel(u) return units[u] and units[u].level or 0 end
SPELLS = { [8613] = "Skinning", [8618] = "Skinning", [2575] = "Mining", [2366] = "Herb Gathering",
  [7620] = "Fishing", [921] = "Pick Pocket", [3365] = "Opening" }
function GetSpellInfo(id) return SPELLS[id] or "Other" end
function IsFishingLoot() return fishingLoot end
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
function LootSlotHasItem(i) return loot[i] ~= nil and not loot[i].money end
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

# Forever, over the Era stand-in above: no old item globals (only C_Item), and the game's side tab
# (LargeSideTabButtonTemplate: a Frame, clicked through its own handler, with no OnClick script)
FOREVER = r"""
GetItemInfo, GetItemIcon = nil, nil
C_Item = { GetItemInfo = function(id) return nil end, GetItemIconByID = function() return 134400 end }
local plainFrame = CreateFrame
function CreateFrame(kind, name, parent, tmpl)
  local f = plainFrame(kind, name, parent)
  if tmpl == "LargeSideTabButtonTemplate" then
    f.Icon = NewWidget("texture"); f.w, f.h = 54, 54
    f.SetCustomOnMouseUpHandler = function(self, fn) self.scripts.OnClick = fn end
    f.SetChecked = function(self, v) assert(type(v) == "boolean", "SetChecked wants true or false") end
    f.SetScript = function(self, k, fn)
      if k == "OnClick" or k == "OnEnter" or k == "OnLeave" then error("the side tab has no " .. k .. " script") end
      self.scripts[k] = fn
    end
  end
  return f
end
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

-- 6. the other professions
local function Count(prof) local n = 0 for _, l in pairs(FieldnotesDB.events[prof] or {}) do n = n + #l end return n end
local function Last(prof) local l = FieldnotesDB.events[prof][1434] return l[#l] end
local vein = "GameObject-0-1-0-1-1731-00000DEF"
now = now + 10
Fire("UNIT_SPELLCAST_SENT", "player", "Copper Vein", "cast-4", 2575)
now = now + 3
loot = { { id = 2770, n = 3, guid = vein } }
Fire("LOOT_READY"); Fire("LOOT_OPENED"); Fire("LOOT_CLOSED")
local mined = Count("mining") == 1 and Last("mining"):find(":1731:1:0:2770=3$") ~= nil
  and FieldnotesDB.nodes[1731].name == "Copper Vein"
now = now + 10
Fire("UNIT_SPELLCAST_SENT", "player", "", "cast-5", 7620)
now = now + 18
fishingLoot = true
loot = { { id = 6291, n = 1, guid = "GameObject-0-1-0-1-35591-0000BBB" } }
Fire("LOOT_READY"); Fire("LOOT_CLOSED")
fishingLoot = false
local fished = Count("fishing") == 1 and Last("fishing"):find(":0:1:0:6291=1$") ~= nil
-- a humanoid with Linen, the same corpse again, a humanoid with nothing, a pickpocket
local thug = "Creature-0-1-0-1-116-00000AAA"
units.target = { name = "Defias Thug", guid = thug, dead = true, level = 10, type = "Humanoid" }
Fire("PLAYER_TARGET_CHANGED")
now = now + 10
loot = { { id = 2589, n = 2, guid = thug }, { id = 117, n = 1, guid = thug } }
Fire("LOOT_READY"); Fire("LOOT_CLOSED")
Fire("LOOT_READY"); Fire("LOOT_CLOSED")
local thug2 = "Creature-0-1-0-1-116-00000AAB"
units.target = { name = "Defias Thug", guid = thug2, dead = true, level = 10, type = "Humanoid" }
Fire("PLAYER_TARGET_CHANGED")
loot = { { id = 117, n = 1, guid = thug2 } }
Fire("LOOT_READY"); Fire("LOOT_CLOSED")
local thug3 = "Creature-0-1-0-1-116-00000AAC"
Fire("UNIT_SPELLCAST_SENT", "player", "Defias Thug", "cast-6", 921)
loot = { { id = 2589, n = 1, guid = thug3 } }
Fire("LOOT_READY"); Fire("LOOT_CLOSED")
-- (the tiger's Silk in 2. counts too: a creature of any type that drops cloth)
local cl = {}
for _, r in ipairs(FieldnotesDB.events.cloth[1434]) do if r:find(":116:") then cl[#cl + 1] = r end end
local clothOk = #FieldnotesDB.events.cloth[1434] == 3 and #cl == 2 and cl[1]:find(":116:1:0:2589=2$") ~= nil and cl[2]:find(":116:1:0:$") ~= nil
gatherResult = (mined and "m" or "-") .. (fished and "f" or "-") .. (clothOk and "c" or "-")
  .. (Count("skinning") == 1 and "s" or "-")
units.target = nil
-- the tracker: one session, a row per profession in the order first gathered
sessionOrder = table.concat(ns.session.order, ",")

-- treasure: a chest opened (money in it) counts once though opened twice; a quest crate does not
local chest = "GameObject-0-1-0-1-2843-00000CCC"
now = now + 10
Fire("UNIT_SPELLCAST_SENT", "player", "Battered Chest", "cast-7", 3365)
now = now + 2
loot = { { id = 118, n = 1, guid = chest }, { money = true, guid = chest } }
Fire("LOOT_READY"); Fire("LOOT_CLOSED")
now = now + 5
Fire("LOOT_READY"); Fire("LOOT_CLOSED")
now = now + 5
Fire("UNIT_SPELLCAST_SENT", "player", "Crate of Supplies", "cast-8", 3365)
now = now + 2
loot = { { id = 5000, n = 1, guid = "GameObject-0-1-0-1-9999-00000DDD" } }
Fire("LOOT_READY"); Fire("LOOT_CLOSED")
treasureOk = Count("treasure") == 1 and Last("treasure"):find(":2843:1:0:118=1$") ~= nil
  and FieldnotesDB.nodes[2843].name == "Battered Chest"

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
for _, c in ipairs({ "solar", "frost", "plasma", "viridis", "thermal" }) do
  FieldnotesDB.settings.map.colors = c
  Open("heat", "account")
end
local gear = ns.Map.ui.gear
gear.scripts.OnClick(gear)
Open("heat", "account")
local settingsOpen = ns.Map.ui.reset.shown and 1 or 0
-- Darken map: a saved value past the most is held to it, and the map still draws
FieldnotesDB.settings.map.dim = 5
dimHeld = ns.Map.S().dim == ns.Map.DIM_MAX
FieldnotesDB.settings.map.colors = "snowfall" -- the old name of Frost, in a saved setting
frostKept = ns.Map.S().colors == "frost"
FieldnotesDB.settings.map.colors = "thermal"
FieldnotesDB.settings.map.dim = 0.6
Open("heat", "account")
FieldnotesDB.settings.map.dim = ns.Map.DEFAULTS.dim
FieldnotesDB.settings.map.when = 7
local recent = Open("heat", "account")
FieldnotesDB.settings.map.when = 0
WorldMapFrame.mapID = 1415 -- the continent: a badge per zone with notes
Open("heat", "account")
local continentBadges = ns.Map.ui.badgeCount
WorldMapFrame.mapID = 1426
-- the small map: a dock beside it (room on the right), the toolbar when maximized
local toolbarLayout = ns.Map.ui.layout
-- the full-screen Home key: clicking a profession's row opens its page, with all of its material
-- (a leather filter left over from another page must not carry across)
FieldnotesDB.settings.map.prof = "all"
FieldnotesDB.settings.map.leather = "hides"
Open("heat", "account")
local homeKey = ns.MapUI.key
local miningRow
for _, l in ipairs(homeKey.legend) do
  if l.b.entry and l.b.entry.prof == "mining" then miningRow = l.b end
end
miningRow.scripts.OnEnter(miningRow)
miningRow.scripts.OnClick(miningRow)
keyOpens = FieldnotesDB.settings.map.prof == "mining" and FieldnotesDB.settings.map.leather == 0
-- a leather filter (Hides) chosen on Skinning does not follow you back to it
FieldnotesDB.settings.map.prof = "all"
FieldnotesDB.settings.map.leather = "hides"
ns.Map.SetProf("skinning")
keyOpens = keyOpens and FieldnotesDB.settings.map.leather == 0 and FieldnotesDB.settings.map.prof == "skinning"
FieldnotesDB.settings.map.prof = "skinning"
FieldnotesDB.settings.map.leather = 0
Open("heat", "account")
WorldMapFrame.IsMaximized = function() return false end
function WorldMapFrame:GetLeft() return 300 end
function WorldMapFrame:GetRight() return 1300 end
function UIParent:GetRight() return 1920 end
Open("points", "account")
local dockLayout = ns.Map.ui.layout
-- the dashboard: every gather as a dot; hovering a row lights that profession (glows added),
-- another row lights its own instead; a profession tab goes to its page, the Fieldnotes tab back
FieldnotesDB.settings.map.prof = "all"
local dash = Open("points", "account")
ns.Map.SetLit("skinning")
local dashLit = ShownOnMap()
ns.Map.SetLit("mining")
local dashOther = ShownOnMap()
ns.Map.SetLit(nil)
local dashModel = ns.Map.model.kind
local tabs = ns.MapUI.tabs
local skinTab
for _, t in ipairs(tabs) do if t.p.key == "skinning" then skinTab = t end end
skinTab.scripts.OnClick(skinTab)
skinTab.scripts.OnClick(skinTab) -- a tab never folds the dock
local toSkinning = FieldnotesDB.settings.map.prof == "skinning" and FieldnotesDB.settings.dockOpen ~= false
ns.MapUI.home.scripts.OnClick(ns.MapUI.home)
local toDash = FieldnotesDB.settings.map.prof == "all"
-- a dashboard row opens its page even for a profession with nothing yet
local miningRow = ns.MapUI.dock.dash.rows[2]
miningRow.scripts.OnClick(miningRow)
rowOpens = FieldnotesDB.settings.map.prof == "mining"
ns.MapUI.home.scripts.OnClick(ns.MapUI.home)
skinTab.scripts.OnClick(skinTab)
ns.MapUI.tab.scripts.OnClick(ns.MapUI.tab) -- the Fieldnotes tab only folds and opens
local folded = FieldnotesDB.settings.dockOpen == false and FieldnotesDB.settings.map.prof == "skinning"
ns.MapUI.tab.scripts.OnClick(ns.MapUI.tab) -- and opening lands on Home
folded = folded and FieldnotesDB.settings.dockOpen ~= false and FieldnotesDB.settings.map.prof == "all"
FieldnotesDB.settings.map.prof = "skinning"
Open("heat", "account")
dashResult = (dash > 20 and "d" or "-") .. (dashLit > dash and "l" or "-") .. ((dashOther > dash and dashOther ~= dashLit) and "o" or "-")
  .. (dashModel == "dash" and "m" or "-") .. ((toSkinning and toDash and folded) and "t" or "-")
-- sessions by hand only (Settings): a gather starts nothing, a started session still counts
FieldnotesDB.settings.autoSession = false
ns.SessionEnd()
ns.SessionGather("mining", 1731, { [2770] = 1 })
local stayedOff = not ns.SessionRunning()
ns.SessionStart()
ns.SessionGather("mining", 1731, { [2770] = 1 })
local counted = ns.session.total == 1
ns.SessionEnd()
FieldnotesDB.settings.autoSession = nil
dashResult = dashResult .. ((stayedOff and counted) and "a" or "-")
-- the session window: stays up when idle unless Settings hides it, a click brings it back, and a
-- saved size is held inside its limits
do
  local t0 = now
  ns.SessionStart()
  local tf = ns.TrackerFrame()
  now = now + 200
  tf.scripts.OnUpdate(tf, 2)
  local stayed = tf:IsShown()
  FieldnotesDB.settings.trackerAutoHide = true
  tf.scripts.OnUpdate(tf, 2)
  local hid = not tf:IsShown()
  ns.ShowTracker(true)
  tf.scripts.OnUpdate(tf, 2)
  local reopenedStays = ns.TrackerShown()
  FieldnotesDB.settings.trackerAutoHide = nil
  FieldnotesDB.settings.tracker = false
  tf:Hide()
  ns.ShowTracker()
  local autoRespected = not tf:IsShown()
  ns.ShowTracker(true)
  local clickOverrides = tf:IsShown()
  FieldnotesDB.settings.tracker = nil
  FieldnotesDB.settings.trackerSize = { w = 999, h = 400 }
  ns.UpdateTracker()
  local biggest = tf:GetWidth() == 420 and tf:GetHeight() == 400
  FieldnotesDB.settings.trackerSize = { w = 100 }
  ns.UpdateTracker()
  local smallest = tf:GetWidth() == 232 and tf:GetHeight() > 0 and tf:GetHeight() < 400
  FieldnotesDB.settings.trackerSize = nil
  -- the X: a gather does not reopen it or end the session; a click does reopen it; a new session shows it
  ns.CloseTracker()
  local before = ns.session.total
  ns.SessionGather("mining", 1731, { [2770] = 1 })
  local closedStays = not tf:IsShown() and ns.SessionRunning() and ns.session.total == before + 1
  ns.ShowTracker(true)
  local closedReopens = tf:IsShown()
  ns.CloseTracker()
  ns.SessionEnd()
  ns.SessionStart()
  local newSessionShows = tf:IsShown()
  -- a long quiet spell does not start a new session: the count carries on until End
  ns.SessionGather("mining", 1731, { [2770] = 1 })
  now = now + 3600
  ns.SessionGather("mining", 1731, { [2770] = 1 })
  local carriesOn = ns.session.total == 2
  ns.SessionEnd()
  -- opacity: only the background fades (the window's own alpha, which would fade its text, is left
  -- alone), held to 0-100%, and full is the default
  local fullByDefault = ns.TrackerOpacity() == 1
  local edgeAlpha, windowFaded
  tf.SetBackdropBorderColor = function(_, _, _, _, a) edgeAlpha = a end
  tf.SetAlpha = function() windowFaded = true end
  local edge = ns.Style.STYLE.panel.edge
  ns.SetTrackerOpacity(0.6)
  local opacitySet = math.abs(edgeAlpha - (edge[4] or 1) * 0.6) < 0.001 and FieldnotesDB.settings.trackerAlpha == 0.6
  ns.SetTrackerOpacity(-1)
  local opacityFloor = edgeAlpha == 0 and not windowFaded
  ns.SetTrackerOpacity(nil)
  tf.SetBackdropBorderColor, tf.SetAlpha = nil, nil
  -- the gear's panel opens and closes, and goes when the window does
  ns.ToggleTrackerSettings()
  local sp = ns.TrackerSettings()
  local panelOpens = sp:IsShown()
  ns.ToggleTrackerSettings()
  local panelCloses = not sp:IsShown()
  ns.ToggleTrackerSettings()
  tf.scripts.OnHide(tf)
  local panelGoes = not sp:IsShown()
  trackerPanelOk = panelOpens and panelCloses and panelGoes
  now = t0
  trackerWindowOk = stayed and hid and reopenedStays and autoRespected and clickOverrides and biggest and smallest
    and closedStays and closedReopens and newSessionShows and carriesOn and fullByDefault and opacitySet and opacityFloor
end
ns.SessionStart()
local sessionOn = ns.SessionRunning()
ns.SessionEnd()
print("map        layouts: maximized " .. tostring(toolbarLayout) .. ", small " .. tostring(dockLayout))
local layouts = (toolbarLayout == "toolbar" and dockLayout == "dock" and sessionOn and not ns.SessionRunning()) and 1 or 0
local mapResult = layouts .. "," .. continentBadges .. "," .. spot .. "," .. hides .. "," .. settingsOpen .. "," .. recent .. "," .. heat .. "," .. pointsMe .. "," .. pointsAll .. "," .. pointsCommunity .. "," .. empty .. "," .. off .. "," .. spotsListed .. "," .. heatDots

-- 7. the Stats page in the dock, on the demo: /fn opens it, the Stats tab closes it again
WorldMapFrame:Show()
SlashCmdList.FIELDNOTES("")
local page = ns.MapUI.dock.statsPage
local opened = ns.StatsShown() and page:IsShown()
local mapS = FieldnotesDB.settings.map
mapS.statsProf, mapS.show, mapS.when = "skinning", "account", 0
page:Update()
local u = page
local stats = u.tiles[1].value.text .. "|" .. u.tiles[2].value.text .. "|" .. u.tiles[3].value.text .. "|" .. u.tiles[4].value.text
mapS.show = "me"
page:Update()
local meSkins = u.tiles[1].value.text
mapS.show = "account"
-- All: every profession counted, the donut drawn, a profession's own card only for a profession
mapS.statsProf = "all"
page:Update()
local allCount = #page.data.recs
local skinOnly = 0
for _ in pairs(page.data.byProf) do skinOnly = skinOnly + 1 end
mapS.statsProf = "cloth"
page:Update()
local clothCard = next(page.data.cloth) ~= nil
mapS.statsProf = "all"
ns.MapUI.dock.stats.scripts.OnClick(ns.MapUI.dock.stats)
statsPageOk = opened and not ns.StatsShown() and skinOnly >= 5 and allCount > 3000 and clothCard

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

def play(flavor, stubs, verbose):
    rt = lua51.LuaRuntime()
    for stub in stubs:
        rt.execute(stub)
    if not verbose:
        rt.execute("print = function() end")  # the Lua side's own info lines: the first pass says them
    g = rt.globals()
    g.FILES = rt.table_from(FILES)
    g.SOURCES = rt.table_from(sources)
    count, first, cname, clevel, chat, refused, demo_count, faked, real_kept, cleared, map_result, stats, me_skins, tracker, demo_share, real_share, cap_alert = rt.execute(PLAY)
    say = print if verbose else (lambda *_: None)
    say("share      real: %s" % real_share)
    say("stats      tiles %s, Me %s" % (stats, me_skins))
    layouts, continent, spot, hides, settings_open, recent, heat, p_me, p_all, p_comm, empty, off, spots_listed, heat_dots = [int(v) for v in map_result.split(",")]
    say("map        continent badges %d" % continent)
    say("map        spotlight %d, hides %d, last 7 days %d, settings panel %s" % (spot, hides, recent, "open" if settings_open else "closed"))
    say("map        heat %d, points me %d / account %d / community %d, empty map %d, off %d" % (heat, p_me, p_all, p_comm, empty, off))
    say("demo       %d sample skins" % demo_count)
    checks = [
        ("one skin recorded, not four", count == 1),
        ("record holds place, time, creature, character, skill and loot",
         first == "471:220:1700000000:682:1:225:2319=2,2934=1"),
        ("creature remembered from mouseover", cname == "Stranglethorn Tiger" and clevel == 33),
        ("mining: a vein's ore recorded with its node", rt.globals().gatherResult[0] == "m"),
        ("fishing: a catch recorded where you stood", rt.globals().gatherResult[1] == "f"),
        ("cloth: humanoid loots counted once each, with or without cloth; Pick Pocket left out",
         rt.globals().gatherResult[2] == "c"),
        ("other professions leave skinning alone", rt.globals().gatherResult[3] == "s"),
        ("treasure: a chest recorded once with its object; a quest crate is not", rt.globals().treasureOk is True),
        ("tracker: one session, a row per profession in the order gathered",
         rt.globals().sessionOrder == "skinning,cloth,mining,fishing"),
        ("dashboard: every gather a dot, no heat", rt.globals().dashResult[0] == "d" and rt.globals().dashResult[3] == "m"),
        ("dashboard: hovering a row lights its dots", rt.globals().dashResult[1] == "l"),
        ("dashboard: another row lights its own dots instead", rt.globals().dashResult[2] == "o"),
        ("tabs: a tab opens its page, Home the dashboard; Fieldnotes only folds and opens (on Home)", rt.globals().dashResult[4] == "t"),
        ("dashboard: every row opens its page, even a profession with nothing yet", rt.globals().rowOpens == True),
        ("session: with auto start off, only Start begins one", rt.globals().dashResult[5] == "a"),
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
        ("full-screen Home key: a profession row opens its page and starts on all of its material", rt.globals().keyOpens == True),
        ("map: Spotlight dims the map", spot > heat),
        ("map: the Hides leather filter draws fewer areas than all skins", 0 < hides < heat),
        ("map: the settings panel opens", settings_open == 1),
        ("map: Darken map holds a saved value to its most", rt.globals().dimHeld == True),
        ("map: a saved Snowfall choice carries over to Frost", rt.globals().frostKept == True),
        ("map: Last 7 days draws less than All time", recent < heat),
        ("map: drew without an error", rt.globals().mapError is None),
        ("every /fn command runs, in demo mode and with real records", len(list(rt.globals().commandErrors.values())) == 0),
        ("session tracker counts the real skin", bool(tracker)),
        ("session window: stays when idle unless set to hide, a click reopens it, size held in limits",
         rt.globals().trackerWindowOk is True),
        ("session window: the gear's settings panel opens, closes and goes with the window",
         rt.globals().trackerPanelOk is True),
        ("skill cap: one trainer alert, the tracker folds and opens", bool(cap_alert)),
        ("share: demo text reads back whole, a cut-off paste is caught, import adds to Community", bool(demo_share)),
        ("share: demo text and your own text are refused; someone else's joins Community", real_share == "ok"),
        ("stats page: /fn opens it in the dock, the Stats tab closes it; All counts every profession",
         rt.globals().statsPageOk is True),
        ("stats page fills its numbers", stats.split("|")[0].replace(",", "").isdigit() and stats.split("|")[1] != "-"),
        ("stats page: Me counts fewer skins than Account",
         0 < int(me_skins.replace(",", "")) < int(stats.split("|")[0].replace(",", ""))),
    ]
    good = True
    for label, passed in checks:
        good = good and passed
        if verbose or not passed:
            print(("ok         " if passed else "FAIL       ") + ("" if verbose else "[" + flavor + "] ") + label)
    for e in rt.globals().commandErrors.values():
        print("COMMAND    [" + flavor + "] " + e)
    if not good:
        print("record: " + str(first))
        print(chat)
    if not verbose:
        n = sum(1 for _, passed in checks if passed)
        print("%-10s %d of %d checks pass" % (flavor, n, len(checks)))
    return good


if ok:
    ok = play("era", [STUB], True)
    ok = play("forever", [STUB, FOREVER], False) and ok

sys.exit(0 if ok else 1)
