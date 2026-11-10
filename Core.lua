local ADDON, FN = ...
_G.Fieldnotes = FN

-- Saved data, account-wide (FieldnotesDB):
--   chars      { "Name-Realm", ... }   records point at a character by its position here;
--                                      only ever read locally, never shared
--   creatures  { [npcID] = { name, type, minLevel, maxLevel } }
--   events     { [profession] = { [mapID] = { record, ... } } }   skinning, mining, herbalism,
--                                      fishing, cloth
--   nodes      { [objectID] = { name } }   mining veins and herbs, as creatures are for skins
--   settings   { chat = true, demo = false }
--   demo       sample data in the same shape (chars, creatures, events), only while loaded
--   liveSession  the running session, written at logout for a /reload and cleared on the way back in
--
-- One record per gather, the same shape for every profession, kept as text so years of
-- skinning stay small:  "x:y:time:source:char:skill:itemID=count,itemID=count"
--   source the creature (skinning, cloth), the node (mining, herbalism) or 0 (fishing)
--   money  coin looted is kept as the item 0 (FN.COIN): "0=2136" is 21 silver 36 copper
--   x, y   position on the zone map, 0-1000 (empty when the game gives none, as in instances)
--   time   seconds since 1970 (time())
FN.DB_VERSION = 1

-- Item lookups that work on every client: Forever has only the C_Item versions, Era the old
-- globals. ItemInfo returns what GetItemInfo does (name, link, ...); nil until the game has the item.
function FN.ItemInfo(id)
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(id) end
    if GetItemInfo then return GetItemInfo(id) end
end
function FN.ItemIcon(id)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    if GetItemIcon then return GetItemIcon(id) end
end

-- Money: looted coin is recorded as this item ID, its count the copper (Recorder.lua)
FN.COIN = 0

-- 21436 copper -> "2g 14s 36c", each letter in its coin's color (numbers stay plain; gold is
-- money's color in the neutral look). plain: no colors. Zero parts are left out; nothing is "0c".
local COIN_HEX = { g = "ffcc33", s = "c9ccd4", c = "c8814a" }
function FN.FormatMoney(copper, plain)
    copper = math.floor(tonumber(copper) or 0)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local out = {}
    local function Part(n, letter)
        out[#out + 1] = plain and (n .. letter) or (n .. "|cff" .. COIN_HEX[letter] .. letter .. "|r")
    end
    if g > 0 then Part(g, "g") end
    if s > 0 then Part(s, "s") end
    if c > 0 or #out == 0 then Part(c, "c") end
    return table.concat(out, " ")
end

local DEFAULT_SETTINGS = { chat = true }

local ACCENT = "|cffece4d0" -- C.TITLE: the neutral look keeps gold for money
function FN.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(ACCENT .. "Fieldnotes|r  " .. tostring(msg))
end

local function InitDB()
    local db = FieldnotesDB
    if type(db) ~= "table" then
        db = {}
        FieldnotesDB = db
    end
    db.version = db.version or FN.DB_VERSION
    db.settings = db.settings or {}
    for k, v in pairs(DEFAULT_SETTINGS) do
        if db.settings[k] == nil then db.settings[k] = v end
    end
    db.chars = db.chars or {}
    db.creatures = db.creatures or {}
    db.events = db.events or {}
    FN.db = db
end

-- this character's position in db.chars, added on first use
function FN.CharIndex()
    if FN.charIndex then return FN.charIndex end
    local key = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
    for i, k in ipairs(FN.db.chars) do
        if k == key then
            FN.charIndex = i
            return i
        end
    end
    table.insert(FN.db.chars, key)
    FN.charIndex = #FN.db.chars
    return FN.charIndex
end

-- ------------------------------------------------------------
-- Records
-- ------------------------------------------------------------
function FN.Encode(r)
    local parts = {}
    for id, n in pairs(r.items) do parts[#parts + 1] = id .. "=" .. n end
    table.sort(parts)
    return string.format("%s:%s:%d:%d:%d:%d:%s",
        r.x and tostring(r.x) or "", r.y and tostring(r.y) or "",
        r.time, r.npc or 0, r.char, r.skill or 0, table.concat(parts, ","))
end

function FN.Decode(s)
    local x, y, t, npc, char, skill, items = s:match("^(%d*):(%d*):(%d+):(%d+):(%d+):(%d+):(.*)$")
    if not t then return nil end
    local r = {
        x = tonumber(x), y = tonumber(y), time = tonumber(t), npc = tonumber(npc),
        char = tonumber(char), skill = tonumber(skill), items = {},
    }
    for id, n in items:gmatch("(%d+)=(%d+)") do r.items[tonumber(id)] = tonumber(n) end
    return r
end

-- store: FN.db (your real records, the default) or FN.db.demo (sample data, see Demo.lua)
function FN.Add(profession, mapID, r, store)
    store = store or FN.db
    local byMap = store.events[profession]
    if not byMap then
        byMap = {}
        store.events[profession] = byMap
    end
    mapID = mapID or 0
    local list = byMap[mapID]
    if not list then
        list = {}
        byMap[mapID] = list
    end
    list[#list + 1] = FN.Encode(r)
    if not FN.bulk then FN.NotifyData() end -- bulk: Demo.lua's loader tells once at the end
end

-- Views that redraw when records change (the map, the stats window): FN.OnData(fn) adds one
FN.dataListeners = {}
function FN.OnData(fn) table.insert(FN.dataListeners, fn) end
function FN.NotifyData()
    for _, fn in ipairs(FN.dataListeners) do fn() end
end

-- What /fn and the map show: the demo store while demo mode is on, else your records.
-- Real skins are always saved to your records, demo mode or not.
function FN.View()
    if FN.db.settings.demo and FN.db.demo then return FN.db.demo end
    return FN.db
end

-- "this character" within the view: the demo's first character stands in for you
function FN.ViewChar()
    if FN.View() ~= FN.db then return 1 end
    return FN.CharIndex()
end

-- ------------------------------------------------------------
-- Start-up
-- ------------------------------------------------------------
FN.onLogin = {}

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name == ADDON then
            InitDB()
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        FN.CharIndex()
        for _, fn in ipairs(FN.onLogin) do fn() end
    end
end)
