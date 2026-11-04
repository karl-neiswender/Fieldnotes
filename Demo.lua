local ADDON, FN = ...

-- Demo mode: sample notes for trying Fieldnotes without a high-level gatherer: skins, and
-- (since 0.7) veins, herbs, catches and humanoid loots for cloth.
--
-- Everything lives in FieldnotesDB.demo, apart from your own records, and /fn demo off deletes
-- it. While it is on, /fn (and later the map) show the demo; real skins are still saved to your
-- records as usual. The creatures carry demo IDs (990000 and up) so they can never be mistaken
-- for real data; the zones, names and leather are real.

local LIGHT, MEDIUM, HEAVY, THICK = 2318, 2319, 4234, 4304
local LIGHT_HIDE, MEDIUM_HIDE, HEAVY_HIDE, RUINED = 783, 4232, 4235, 2934

-- zone map ID -> creatures: { demo ID, name, type, levels, skill, spots { x, y, spread }, loot }
-- loot: { itemID, chance, most } rolled one by one
local ZONES = {
    [1429] = { -- Elwynn Forest
        { 990001, "Young Wolf", "Beast", 1, 3, 10, { { 380, 820, 50 }, { 280, 700, 40 } }, { { LIGHT, 0.85, 1 }, { RUINED, 0.35, 2 } } },
        { 990002, "Timber Wolf", "Beast", 3, 5, 25, { { 520, 780, 60 } }, { { LIGHT, 0.9, 2 }, { RUINED, 0.25, 1 } } },
        { 990003, "Stonetusk Boar", "Beast", 5, 6, 35, { { 690, 790, 60 }, { 420, 560, 50 } }, { { LIGHT, 0.9, 2 }, { LIGHT_HIDE, 0.06, 1 } } },
    },
    [1426] = { -- Dun Morogh
        { 990011, "Small Crag Boar", "Beast", 3, 4, 20, { { 300, 720, 50 } }, { { LIGHT, 0.9, 1 }, { RUINED, 0.3, 2 } } },
        { 990012, "Winter Wolf", "Beast", 7, 8, 45, { { 470, 480, 60 }, { 630, 560, 50 } }, { { LIGHT, 0.9, 2 }, { LIGHT_HIDE, 0.06, 1 } } },
    },
    [1438] = { -- Teldrassil
        { 990021, "Nightsaber", "Beast", 5, 6, 30, { { 590, 600, 55 }, { 400, 320, 45 } }, { { LIGHT, 0.9, 2 }, { RUINED, 0.2, 1 } } },
        { 990022, "Webwood Spider", "Beast", 4, 5, 25, { { 570, 750, 40 } }, { { LIGHT, 0.85, 1 }, { RUINED, 0.35, 2 } } },
    },
    [1411] = { -- Durotar
        { 990031, "Mottled Boar", "Beast", 1, 2, 10, { { 430, 640, 50 } }, { { LIGHT, 0.85, 1 }, { RUINED, 0.35, 2 } } },
        { 990032, "Dire Mottled Boar", "Beast", 6, 7, 40, { { 500, 400, 60 }, { 550, 250, 50 } }, { { LIGHT, 0.9, 2 }, { LIGHT_HIDE, 0.06, 1 } } },
    },
    [1412] = { -- Mulgore
        { 990041, "Plainstrider", "Beast", 2, 4, 15, { { 460, 600, 70 } }, { { LIGHT, 0.9, 1 }, { RUINED, 0.3, 2 } } },
        { 990042, "Prairie Wolf", "Beast", 5, 7, 35, { { 530, 300, 60 }, { 400, 420, 50 } }, { { LIGHT, 0.9, 2 }, { LIGHT_HIDE, 0.06, 1 } } },
    },
    [1420] = { -- Tirisfal Glades
        { 990051, "Duskbat", "Beast", 4, 6, 30, { { 520, 560, 60 } }, { { LIGHT, 0.9, 1 }, { RUINED, 0.3, 2 } } },
        { 990052, "Darkhound", "Beast", 6, 8, 45, { { 650, 450, 55 } }, { { LIGHT, 0.9, 2 }, { LIGHT_HIDE, 0.05, 1 } } },
    },
    [1436] = { -- Westfall
        { 990061, "Coyote", "Beast", 10, 12, 60, { { 460, 380, 70 }, { 560, 620, 60 } }, { { LIGHT, 0.8, 2 }, { MEDIUM, 0.25, 1 }, { RUINED, 0.2, 1 } } },
        { 990062, "Goretusk", "Beast", 12, 14, 75, { { 380, 500, 60 } }, { { LIGHT, 0.6, 2 }, { MEDIUM, 0.45, 1 }, { LIGHT_HIDE, 0.06, 1 } } },
    },
    [1413] = { -- The Barrens
        { 990071, "Zhevra Runner", "Beast", 14, 16, 85, { { 560, 200, 70 }, { 480, 380, 60 } }, { { MEDIUM, 0.8, 2 }, { RUINED, 0.2, 1 } } },
        { 990072, "Savannah Prowler", "Beast", 14, 16, 85, { { 600, 520, 60 } }, { { MEDIUM, 0.85, 2 }, { MEDIUM_HIDE, 0.06, 1 } } },
        { 990073, "Thunderhawk", "Beast", 17, 19, 100, { { 480, 600, 50 } }, { { MEDIUM, 0.8, 2 }, { MEDIUM_HIDE, 0.08, 1 } } },
    },
    [1434] = { -- Stranglethorn Vale
        { 990081, "Stranglethorn Tiger", "Beast", 32, 34, 165, { { 470, 220, 60 } }, { { MEDIUM, 0.6, 2 }, { HEAVY, 0.45, 2 }, { RUINED, 0.15, 1 } } },
        { 990082, "Lashtail Raptor", "Beast", 34, 35, 175, { { 330, 440, 55 } }, { { HEAVY, 0.8, 2 }, { RUINED, 0.12, 1 } } },
        { 990083, "Shadowmaw Panther", "Beast", 38, 40, 200, { { 720, 540, 60 } }, { { HEAVY, 0.85, 2 }, { HEAVY_HIDE, 0.08, 1 } } },
    },
    [1417] = { -- Arathi Highlands
        { 990091, "Highland Thrasher", "Beast", 31, 33, 160, { { 460, 640, 70 }, { 600, 420, 55 } }, { { HEAVY, 0.7, 2 }, { MEDIUM, 0.4, 1 }, { RUINED, 0.15, 1 } } },
    },
    [1418] = { -- Badlands
        { 990101, "Ridge Stalker", "Beast", 36, 38, 190, { { 520, 420, 70 } }, { { HEAVY, 0.85, 2 }, { HEAVY_HIDE, 0.07, 1 } } },
    },
    [1444] = { -- Feralas
        { 990111, "Longtooth Runner", "Beast", 42, 44, 220, { { 520, 520, 70 }, { 700, 380, 50 } }, { { THICK, 0.8, 2 }, { HEAVY, 0.3, 1 }, { RUINED, 0.1, 1 } } },
    },
}
-- The other professions, the same shape: profession -> zone -> sources
--   { demo ID, name, skill, spots { x, y, spread }, loot { itemID, chance, most } }
-- Cloth's loot may roll nothing: a humanoid that dropped no cloth still counts as a loot.
local COPPER, TIN, IRON, ROUGH, COARSE = 2770, 2771, 2772, 2835, 2836
local PEACE, SILVER, EARTH, MAGE, BRIAR, BRUISE, KINGS = 2447, 765, 2449, 785, 2450, 2453, 3356
local SMALLFISH, SNAPPER, CATFISH, COD = 6291, 6289, 6308, 6362
local LINEN, WOOL, SILK = 2589, 2592, 4306
local GATHERS = {
    mining = {
        [1426] = { { 990501, "Copper Vein", 1, { { 760, 300, 40 }, { 220, 560, 45 } }, { { COPPER, 1, 3 }, { ROUGH, 0.6, 2 } } } },
        [1429] = { { 990502, "Copper Vein", 1, { { 760, 640, 50 } }, { { COPPER, 1, 3 }, { ROUGH, 0.6, 2 } } } },
        [1436] = { { 990503, "Tin Vein", 65, { { 300, 300, 50 } }, { { TIN, 1, 3 }, { COARSE, 0.6, 2 } } } },
        [1434] = { { 990504, "Iron Deposit", 125, { { 400, 600, 60 } }, { { IRON, 1, 3 } } } },
    },
    herbalism = {
        [1426] = { { 990601, "Peacebloom", 1, { { 520, 620, 70 } }, { { PEACE, 1, 3 } } },
            { 990602, "Silverleaf", 1, { { 380, 420, 50 } }, { { SILVER, 1, 3 } } } },
        [1429] = { { 990603, "Peacebloom", 1, { { 450, 600, 80 } }, { { PEACE, 1, 3 } } },
            { 990604, "Earthroot", 15, { { 620, 780, 50 } }, { { EARTH, 1, 3 } } } },
        [1436] = { { 990605, "Mageroyal", 50, { { 520, 420, 70 } }, { { MAGE, 1, 3 }, { BRIAR, 0.4, 2 } } } },
        [1413] = { { 990606, "Bruiseweed", 100, { { 520, 450, 80 } }, { { BRUISE, 1, 3 } } } },
        [1434] = { { 990607, "Kingsblood", 125, { { 300, 300, 60 } }, { { KINGS, 1, 3 } } } },
    },
    fishing = {
        [1426] = { { 0, "", 1, { { 340, 510, 25 }, { 690, 520, 20 } }, { { SMALLFISH, 0.6, 1 }, { SNAPPER, 0.5, 1 } } } },
        [1429] = { { 0, "", 1, { { 520, 650, 25 } }, { { SMALLFISH, 0.7, 1 }, { SNAPPER, 0.4, 1 } } } },
        [1436] = { { 0, "", 50, { { 300, 820, 30 } }, { { SNAPPER, 0.6, 1 }, { CATFISH, 0.4, 1 } } } },
        [1434] = { { 0, "", 150, { { 270, 760, 30 } }, { { COD, 0.7, 1 }, { CATFISH, 0.3, 1 } } } },
    },
    cloth = {
        [1426] = { { 990701, "Frostmane Troll Whelp", 0, { { 280, 380, 40 } }, { { LINEN, 0.35, 2 } } } },
        [1429] = { { 990702, "Defias Thug", 0, { { 480, 310, 45 } }, { { LINEN, 0.4, 2 } } },
            { 990703, "Kobold Vermin", 0, { { 400, 800, 30 } }, { { LINEN, 0.3, 1 } } } },
        [1436] = { { 990704, "Defias Pillager", 0, { { 440, 430, 55 }, { 600, 300, 40 } }, { { LINEN, 0.3, 2 }, { WOOL, 0.25, 1 } } } },
        [1413] = { { 990705, "Kolkar Bloodcharger", 0, { { 450, 300, 60 } }, { { WOOL, 0.35, 2 } } } },
        [1434] = { { 990706, "Bloodscalp Warrior", 0, { { 400, 140, 50 } }, { { SILK, 0.4, 2 } } } },
    },
}
FN.DEMO_GATHERS = GATHERS
local CHARS = { "You (demo)", "Alt one (demo)", "Alt two (demo)" }
local DAYS = 60

-- a repeatable random stream (Park-Miller), so every /fn demo builds the same sample
local seed
local function Rand()
    seed = (seed * 16807) % 2147483647
    return seed / 2147483647
end
local function Gauss()
    local u = math.max(Rand(), 1e-9)
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * Rand())
end
local function Clamp(v) return math.max(5, math.min(995, math.floor(v + 0.5))) end

-- Sample skins come in sessions, as real ones do: one character, a run of skins about 20
-- seconds apart, on some day in the last two months.
local sessionLeft, clock, sessionChar = 0, 0, 1
local function NextSkin(now)
    if sessionLeft <= 0 then
        sessionLeft = 25 + math.floor(Rand() * 50)
        clock = now - math.floor(Rand() * DAYS * 86400)
        sessionChar = Rand() < 0.5 and 1 or (Rand() < 0.6 and 2 or 3)
    end
    sessionLeft = sessionLeft - 1
    clock = clock + 12 + math.floor(Rand() * 18)
    return clock, sessionChar
end

local function Roll(c)
    local items = {}
    for _, l in ipairs(c[8]) do
        if Rand() < l[2] then items[l[1]] = 1 + math.floor(Rand() * l[3]) end
    end
    if not next(items) then items[c[8][1][1]] = 1 end
    return items
end

local function Note(store, c)
    FN.NoteCreature(c[1], { name = c[2], type = c[3], level = c[4] }, nil, store)
    FN.NoteCreature(c[1], { name = c[2], type = c[3], level = c[5] }, nil, store)
end

function FN.DemoLoad()
    local store = { chars = {}, creatures = {}, events = {} }
    for i, name in ipairs(CHARS) do store.chars[i] = name end
    seed = 20261103
    local now = time()
    local mapIDs = {}
    for mapID in pairs(ZONES) do mapIDs[#mapIDs + 1] = mapID end
    table.sort(mapIDs)
    local total = 0
    FN.bulk = true
    for _, mapID in ipairs(mapIDs) do
        for _, c in ipairs(ZONES[mapID]) do
            Note(store, c)
            for _, spot in ipairs(c[7]) do
                sessionLeft = 0 -- each spot starts its own sessions
                for _ = 1, 60 + math.floor(Rand() * 80) do
                    local t, char = NextSkin(now)
                    FN.Add("skinning", mapID, {
                        x = Clamp(spot[1] + Gauss() * spot[3]), y = Clamp(spot[2] + Gauss() * spot[3]),
                        time = t, npc = c[1], char = char,
                        skill = c[6] + math.floor(Rand() * 15), items = Roll(c),
                    }, store)
                    total = total + 1
                end
            end
        end
    end
    -- the Community layer: many more players, spread wider, plus one spot per zone you never found
    local community = { events = {} }
    for _, mapID in ipairs(mapIDs) do
        local list = ZONES[mapID]
        for ci, c in ipairs(list) do
            local spots = {}
            for _, spot in ipairs(c[7]) do spots[#spots + 1] = { spot[1], spot[2], spot[3] * 1.4 } end
            if ci == 1 then spots[#spots + 1] = { 150 + math.floor(Rand() * 700), 150 + math.floor(Rand() * 700), 60 } end
            for _, spot in ipairs(spots) do
                for _ = 1, 200 + math.floor(Rand() * 200) do
                    FN.Add("skinning", mapID, {
                        x = Clamp(spot[1] + Gauss() * spot[3]), y = Clamp(spot[2] + Gauss() * spot[3]),
                        time = now - math.floor(Rand() * DAYS * 86400), npc = c[1], char = 0,
                        skill = c[6] + math.floor(Rand() * 15), items = Roll(c),
                    }, community)
                end
            end
        end
    end
    store.community = community

    -- veins, herbs, catches and humanoid loots, in the same sessions as skins
    local gathered = 0
    for _, prof in ipairs({ "mining", "herbalism", "fishing", "cloth" }) do
        local zones = {}
        for mapID in pairs(GATHERS[prof]) do zones[#zones + 1] = mapID end
        table.sort(zones)
        for _, mapID in ipairs(zones) do
            for _, g in ipairs(GATHERS[prof][mapID]) do
                if prof == "cloth" then
                    FN.NoteCreature(g[1], { name = g[2], type = FN.HUMANOID or "Humanoid", level = 5 }, nil, store)
                elseif g[1] > 0 then
                    FN.NoteNode(g[1], g[2], store)
                end
                for _, spot in ipairs(g[4]) do
                    sessionLeft = 0
                    for _ = 1, (prof == "cloth" and 70 or 35) + math.floor(Rand() * 50) do
                        local t, char = NextSkin(now)
                        local items = {}
                        for _, l in ipairs(g[5]) do
                            if Rand() < l[2] then items[l[1]] = 1 + math.floor(Rand() * l[3]) end
                        end
                        if prof ~= "cloth" and not next(items) then items[g[5][1][1]] = 1 end
                        FN.Add(prof, mapID, {
                            x = Clamp(spot[1] + Gauss() * spot[3]), y = Clamp(spot[2] + Gauss() * spot[3]),
                            time = t, npc = g[1], char = char,
                            skill = prof == "cloth" and 0 or g[3] + math.floor(Rand() * 20), items = items,
                        }, store)
                        gathered = gathered + 1
                    end
                end
            end
        end
    end
    FN.bulk = nil

    FN.db.demo = store
    FN.db.settings.demo = true
    FN.Print(string.format("Demo mode on: %d sample skins in %d zones and %d other gathers (ore, herbs, fish, cloth), from 3 made-up characters, plus a sample Community layer.", total, #mapIDs, gathered))
    FN.NotifyData()
end

function FN.DemoClear()
    local had = FN.db.demo ~= nil
    FN.db.demo = nil
    FN.db.settings.demo = false
    FN.Print(had and "Sample data removed. Showing your own records." or "No sample data was loaded.")
    FN.NotifyData()
end

-- one pretend skin where you stand, through the same session tracking as a real one
function FN.DemoFakeSkin()
    if not (FN.db.settings.demo and FN.db.demo) then
        FN.Print("Fake skins only go into sample data. Type /fn demo first.")
        return
    end
    local mapID, x, y = FN.PlayerPosition()
    if not x then
        FN.Print("The game gives no map position here (an instance?). Try outdoors.")
        return
    end
    if not seed then seed = 20261103 end
    seed = (seed + math.floor(GetTime() * 1000)) % 2147483646 + 1
    local list = ZONES[mapID]
    local c = list and list[1 + math.floor(Rand() * #list)]
        or { 990999, "Demo Boar", "Beast", 5, 5, 25, {}, { { LIGHT, 0.9, 2 }, { RUINED, 0.3, 1 } } }
    local items = Roll(c)
    Note(FN.db.demo, c)
    FN.Add("skinning", mapID, { x = x, y = y, time = time(), npc = c[1], char = 1, skill = c[6], items = items }, FN.db.demo)
    FN.SessionAdd(c[1], items)

    local links = {}
    for id, n in pairs(items) do
        local _, link = GetItemInfo(id)
        link = link or ("item " .. id)
        links[#links + 1] = n > 1 and (link .. " x" .. n) or link
    end
    FN.Print(c[2] .. "  " .. table.concat(links, ", ") .. "  (fake)")
end
