local ADDON, FN = ...
_G.Fieldnotes = FN

-- Saved data, account-wide (FieldnotesDB):
--   chars      { "Name-Realm", ... }   records point at a character by its position here;
--                                      only ever read locally, never shared
--   creatures  { [npcID] = { name, type, minLevel, maxLevel } }
--   events     { [profession] = { [mapID] = { record, ... } } }
--   settings   { chat = true, demo = false }
--   demo       sample data in the same shape (chars, creatures, events), only while loaded
--
-- One record per gather, the same shape for every profession, kept as text so years of
-- skinning stay small:  "x:y:time:npcID:char:skill:itemID=count,itemID=count"
--   x, y   position on the zone map, 0-1000 (empty when the game gives none, as in instances)
--   time   seconds since 1970 (time())
FN.DB_VERSION = 1

local DEFAULT_SETTINGS = { chat = true }

local ACCENT = "|cffe9b265"
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
