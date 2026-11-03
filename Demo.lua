local ADDON, FN = ...

-- Demo mode: sample skins for trying Fieldnotes without a high-level skinner.
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
                for _ = 1, 60 + math.floor(Rand() * 80) do
                    local char = Rand() < 0.5 and 1 or (Rand() < 0.6 and 2 or 3)
                    FN.Add("skinning", mapID, {
                        x = Clamp(spot[1] + Gauss() * spot[3]), y = Clamp(spot[2] + Gauss() * spot[3]),
                        time = now - math.floor(Rand() * DAYS * 86400), npc = c[1], char = char,
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
    FN.bulk = nil

    FN.db.demo = store
    FN.db.settings.demo = true
    FN.Print(string.format("Demo mode on: %d sample skins in %d zones, from 3 made-up characters, plus a sample Community layer.", total, #mapIDs))
    if FN.OnDataChanged then FN.OnDataChanged() end
end

function FN.DemoClear()
    local had = FN.db.demo ~= nil
    FN.db.demo = nil
    FN.db.settings.demo = false
    FN.Print(had and "Sample data removed. Showing your own records." or "No sample data was loaded.")
    if FN.OnDataChanged then FN.OnDataChanged() end
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
