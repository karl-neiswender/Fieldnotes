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
-- Spots sit on ground players walk: towns, camps, mines, lakeshores and the creatures' own
-- grounds, from their map coordinates (x, y in tenths of a percent). The scatter is tight and cut
-- off (Gauss below), so no sample lands in mountains or open water (Karl, 2026-11-04: some did).
local ZONES = {
    [1429] = { -- Elwynn Forest
        { 990001, "Young Wolf", "Beast", 1, 3, 10, { { 470, 470, 25 }, { 530, 520, 22 } }, { { LIGHT, 0.85, 1 }, { RUINED, 0.35, 2 } } },
        { 990002, "Timber Wolf", "Beast", 3, 5, 25, { { 380, 760, 28 }, { 300, 680, 24 } }, { { LIGHT, 0.9, 2 }, { RUINED, 0.25, 1 } } },
        { 990003, "Stonetusk Boar", "Beast", 5, 6, 35, { { 690, 780, 28 }, { 620, 660, 24 } }, { { LIGHT, 0.9, 2 }, { LIGHT_HIDE, 0.06, 1 } } },
    },
    [1426] = { -- Dun Morogh
        { 990011, "Small Crag Boar", "Beast", 3, 4, 20, { { 290, 710, 22 } }, { { LIGHT, 0.9, 1 }, { RUINED, 0.3, 2 } } },
        { 990012, "Winter Wolf", "Beast", 7, 8, 45, { { 430, 500, 26 }, { 600, 480, 22 } }, { { LIGHT, 0.9, 2 }, { LIGHT_HIDE, 0.06, 1 } } },
    },
    [1438] = { -- Teldrassil
        { 990021, "Nightsaber", "Beast", 5, 6, 30, { { 560, 560, 26 }, { 600, 420, 22 } }, { { LIGHT, 0.9, 2 }, { RUINED, 0.2, 1 } } },
        { 990022, "Webwood Spider", "Beast", 4, 5, 25, { { 560, 700, 20 } }, { { LIGHT, 0.85, 1 }, { RUINED, 0.35, 2 } } },
    },
    [1411] = { -- Durotar
        { 990031, "Mottled Boar", "Beast", 1, 2, 10, { { 440, 640, 22 } }, { { LIGHT, 0.85, 1 }, { RUINED, 0.35, 2 } } },
        { 990032, "Dire Mottled Boar", "Beast", 6, 7, 40, { { 510, 420, 26 }, { 530, 290, 22 } }, { { LIGHT, 0.9, 2 }, { LIGHT_HIDE, 0.06, 1 } } },
    },
    [1412] = { -- Mulgore
        { 990041, "Plainstrider", "Beast", 2, 4, 15, { { 470, 620, 28 } }, { { LIGHT, 0.9, 1 }, { RUINED, 0.3, 2 } } },
        { 990042, "Prairie Wolf", "Beast", 5, 7, 35, { { 540, 400, 26 }, { 470, 470, 22 } }, { { LIGHT, 0.9, 2 }, { LIGHT_HIDE, 0.06, 1 } } },
    },
    [1420] = { -- Tirisfal Glades
        { 990051, "Duskbat", "Beast", 4, 6, 30, { { 520, 560, 26 } }, { { LIGHT, 0.9, 1 }, { RUINED, 0.3, 2 } } },
        { 990052, "Darkhound", "Beast", 6, 8, 45, { { 600, 520, 24 } }, { { LIGHT, 0.9, 2 }, { LIGHT_HIDE, 0.05, 1 } } },
    },
    [1436] = { -- Westfall
        { 990061, "Coyote", "Beast", 10, 12, 60, { { 480, 380, 30 }, { 520, 600, 26 } }, { { LIGHT, 0.8, 2 }, { MEDIUM, 0.25, 1 }, { RUINED, 0.2, 1 } } },
        { 990062, "Goretusk", "Beast", 12, 14, 75, { { 400, 500, 26 } }, { { LIGHT, 0.6, 2 }, { MEDIUM, 0.45, 1 }, { LIGHT_HIDE, 0.06, 1 } } },
    },
    [1413] = { -- The Barrens
        { 990071, "Zhevra Runner", "Beast", 14, 16, 85, { { 540, 240, 30 }, { 480, 380, 26 } }, { { MEDIUM, 0.8, 2 }, { RUINED, 0.2, 1 } } },
        { 990072, "Savannah Prowler", "Beast", 14, 16, 85, { { 560, 480, 26 } }, { { MEDIUM, 0.85, 2 }, { MEDIUM_HIDE, 0.06, 1 } } },
        { 990073, "Thunderhawk", "Beast", 17, 19, 100, { { 470, 620, 24 } }, { { MEDIUM, 0.8, 2 }, { MEDIUM_HIDE, 0.08, 1 } } },
    },
    [1434] = { -- Stranglethorn Vale
        { 990081, "Stranglethorn Tiger", "Beast", 32, 34, 165, { { 470, 230, 22 } }, { { MEDIUM, 0.6, 2 }, { HEAVY, 0.45, 2 }, { RUINED, 0.15, 1 } } },
        { 990082, "Lashtail Raptor", "Beast", 34, 35, 175, { { 370, 450, 20 } }, { { HEAVY, 0.8, 2 }, { RUINED, 0.12, 1 } } },
        { 990083, "Shadowmaw Panther", "Beast", 38, 40, 200, { { 470, 330, 20 } }, { { HEAVY, 0.85, 2 }, { HEAVY_HIDE, 0.08, 1 } } },
    },
    [1417] = { -- Arathi Highlands
        { 990091, "Highland Thrasher", "Beast", 31, 33, 160, { { 460, 560, 28 }, { 580, 420, 24 } }, { { HEAVY, 0.7, 2 }, { MEDIUM, 0.4, 1 }, { RUINED, 0.15, 1 } } },
    },
    [1418] = { -- Badlands
        { 990101, "Ridge Stalker", "Beast", 36, 38, 190, { { 480, 420, 28 } }, { { HEAVY, 0.85, 2 }, { HEAVY_HIDE, 0.07, 1 } } },
    },
    [1444] = { -- Feralas
        { 990111, "Longtooth Runner", "Beast", 42, 44, 220, { { 700, 520, 26 }, { 740, 420, 22 } }, { { THICK, 0.8, 2 }, { HEAVY, 0.3, 1 }, { RUINED, 0.1, 1 } } },
    },
}
-- the Community layer's extra spot per zone: somewhere you never found, on open ground too
local COMMUNITY_EXTRA = {
    [1429] = { 260, 600, 22 }, [1426] = { 520, 480, 22 }, [1438] = { 520, 640, 20 }, [1411] = { 520, 520, 20 },
    [1412] = { 560, 560, 22 }, [1420] = { 470, 380, 22 }, [1436] = { 440, 700, 22 }, [1413] = { 450, 560, 24 },
    [1434] = { 370, 560, 20 }, [1417] = { 400, 460, 22 }, [1418] = { 560, 360, 22 }, [1444] = { 680, 600, 20 },
}
-- The other professions, the same shape: profession -> zone -> sources
--   { demo ID, name, skill, spots { x, y, spread }, loot { itemID, chance, most } }
-- Cloth's loot may roll nothing: a humanoid that dropped no cloth still counts as a loot.
local COPPER, TIN, IRON, ROUGH, COARSE = 2770, 2771, 2772, 2835, 2836
local PEACE, SILVER, EARTH, MAGE, BRIAR, BRUISE, KINGS = 2447, 765, 2449, 785, 2450, 2453, 3356
local SMALLFISH, SNAPPER, CATFISH, COD = 6291, 6289, 6308, 6362
local LINEN, WOOL, SILK = 2589, 2592, 4306
local POTION, JERKY, WATER, MALACHITE, ARROW = 118, 117, 159, 774, 2512
local GATHERS = {
    mining = {
        [1426] = { { 990501, "Copper Vein", 1, { { 600, 400, 14 }, { 470, 440, 14 } }, { { COPPER, 1, 3 }, { ROUGH, 0.6, 2 } } } },
        [1429] = { { 990502, "Copper Vein", 1, { { 610, 530, 16 }, { 390, 810, 14 } }, { { COPPER, 1, 3 }, { ROUGH, 0.6, 2 } } } },
        [1436] = { { 990503, "Tin Vein", 65, { { 440, 250, 16 } }, { { TIN, 1, 3 }, { COARSE, 0.6, 2 } } } },
        [1434] = { { 990504, "Iron Deposit", 125, { { 410, 580, 16 } }, { { IRON, 1, 3 } } } },
    },
    herbalism = {
        [1426] = { { 990601, "Peacebloom", 1, { { 470, 540, 30 } }, { { PEACE, 1, 3 } } },
            { 990602, "Silverleaf", 1, { { 330, 520, 22 } }, { { SILVER, 1, 3 } } } },
        [1429] = { { 990603, "Peacebloom", 1, { { 450, 620, 34 } }, { { PEACE, 1, 3 } } },
            { 990604, "Earthroot", 15, { { 600, 740, 24 } }, { { EARTH, 1, 3 } } } },
        [1436] = { { 990605, "Mageroyal", 50, { { 500, 450, 30 } }, { { MAGE, 1, 3 }, { BRIAR, 0.4, 2 } } } },
        [1413] = { { 990606, "Bruiseweed", 100, { { 500, 420, 32 } }, { { BRUISE, 1, 3 } } } },
        [1434] = { { 990607, "Kingsblood", 125, { { 380, 370, 20 } }, { { KINGS, 1, 3 } } } },
    },
    -- fishing: from the shore of a lake or the coast
    -- (Dun Morogh's map shows one lake, east of Kharanos: its west and east shores)
    fishing = {
        [1426] = { { 0, "", 1, { { 676, 400, 6 }, { 742, 355, 6 } }, { { SMALLFISH, 0.6, 1 }, { SNAPPER, 0.5, 1 } } } },
        [1429] = { { 0, "", 1, { { 520, 650, 10 } }, { { SMALLFISH, 0.7, 1 }, { SNAPPER, 0.4, 1 } } } },
        [1436] = { { 0, "", 50, { { 320, 820, 10 } }, { { SNAPPER, 0.6, 1 }, { CATFISH, 0.4, 1 } } } },
        [1434] = { { 0, "", 150, { { 370, 660, 6 } }, { { COD, 0.7, 1 }, { CATFISH, 0.3, 1 } } } },
    },
    cloth = {
        [1426] = { { 990701, "Frostmane Troll Whelp", 0, { { 260, 520, 18 } }, { { LINEN, 0.35, 2 } } } },
        [1429] = { { 990702, "Defias Thug", 0, { { 520, 380, 18 } }, { { LINEN, 0.4, 2 } } },
            { 990703, "Kobold Vermin", 0, { { 400, 800, 14 } }, { { LINEN, 0.3, 1 } } } },
        [1436] = { { 990704, "Defias Pillager", 0, { { 430, 650, 20 }, { 450, 260, 16 } }, { { LINEN, 0.3, 2 }, { WOOL, 0.25, 1 } } } },
        [1413] = { { 990705, "Kolkar Bloodcharger", 0, { { 450, 300, 22 } }, { { WOOL, 0.35, 2 } } } },
        [1434] = { { 990706, "Bloodscalp Warrior", 0, { { 440, 150, 16 } }, { { SILK, 0.4, 2 } } } },
    },
    -- treasure: a few chests where camps and ruins are; far fewer than other gathers
    treasure = {
        [1426] = { { 990801, "Battered Chest", 0, { { 300, 560, 14 }, { 680, 560, 16 } },
            { { POTION, 0.6, 2 }, { JERKY, 0.5, 3 }, { LINEN, 0.4, 2 } } } },
        [1429] = { { 990802, "Battered Chest", 0, { { 420, 790, 16 } }, { { POTION, 0.6, 2 }, { WATER, 0.5, 3 } } } },
        [1436] = { { 990803, "Tattered Chest", 0, { { 450, 270, 18 } }, { { MALACHITE, 0.4, 1 }, { ARROW, 0.5, 200 } } } },
        [1434] = { { 990804, "Solid Chest", 0, { { 420, 360, 18 } }, { { MALACHITE, 0.5, 1 }, { WOOL, 0.4, 2 } } } },
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
-- a normal scatter, cut off at 1.8 spreads: no long tails into the hills or the sea
local function Gauss()
    local u = math.max(Rand(), 1e-9)
    local v = math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * Rand())
    return math.max(-1.8, math.min(1.8, v))
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

-- Sample skill climbs with time, as a real character's does: from 1 two months ago to the
-- profession's top today (a skill drawn from the creature's level zigzagged the Skill climb chart).
local SKILL_TOP = { skinning = 300, mining = 245, herbalism = 210, fishing = 175 }
local function SkillAt(prof, now, t)
    local top = SKILL_TOP[prof]
    if not top then return 0 end
    local frac = math.max(0, math.min(1, 1 - (now - t) / (DAYS * 86400)))
    return 1 + math.floor((top - 1) * frac ^ 0.75)
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
                        skill = SkillAt("skinning", now, t), items = Roll(c),
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
            for _, spot in ipairs(c[7]) do spots[#spots + 1] = { spot[1], spot[2], spot[3] * 1.2 } end
            if ci == 1 and COMMUNITY_EXTRA[mapID] then spots[#spots + 1] = COMMUNITY_EXTRA[mapID] end
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
    for _, prof in ipairs({ "mining", "herbalism", "fishing", "cloth", "treasure" }) do
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
                    local runs = prof == "treasure" and (6 + math.floor(Rand() * 8))
                        or ((prof == "cloth" and 70 or 35) + math.floor(Rand() * 50))
                    for _ = 1, runs do
                        local t, char = NextSkin(now)
                        local items = {}
                        for _, l in ipairs(g[5]) do
                            if Rand() < l[2] then items[l[1]] = 1 + math.floor(Rand() * l[3]) end
                        end
                        if prof ~= "cloth" and not next(items) then items[g[5][1][1]] = 1 end
                        local x, y = Clamp(spot[1] + Gauss() * spot[3]), Clamp(spot[2] + Gauss() * spot[3])
                        FN.Add(prof, mapID, {
                            x = x, y = y, time = t, npc = g[1], char = char,
                            skill = SkillAt(prof, now, t), items = items,
                        }, store)
                        gathered = gathered + 1
                        -- Money: humanoids drop coin most times, chests always. Amounts come from
                        -- the time, not Rand(), so the rest of the sample data stays as it was.
                        if (prof == "cloth" and t % 5 < 3) or prof == "treasure" then
                            local copper = prof == "treasure" and (250 + t % 1500) or (12 + t % 260)
                            FN.Add("money", mapID, { x = x, y = y, time = t, npc = g[1], char = char, skill = 0,
                                items = { [FN.COIN] = copper } }, store)
                        end
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
        local _, link = FN.ItemInfo(id)
        link = link or ("item " .. id)
        links[#links + 1] = n > 1 and (link .. " x" .. n) or link
    end
    FN.Print(c[2] .. "  " .. table.concat(links, ", ") .. "  (fake)")
end
