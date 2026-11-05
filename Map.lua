local ADDON, FN = ...

-- The world map overlay, the part drawn on the map itself: a soft heat map of where you skin,
-- one dot per skin, or Spotlight (the map dims except where you skin), with hot spot pins, and
-- on continent and world maps one badge per zone. The controls around it (the dock beside the
-- small map, the toolbar on the full-screen map) are MapUI.lua; each redraw hands it a small
-- model of what is on screen.
--
-- Everything is redrawn only when the map, a filter or the data changes; textures come from
-- pools and are reused. How strong, how wide and how sparse the heat is follows the amount of
-- data, so there is nothing to tune.

local M = {}
FN.Map = M

local COLS = 72 -- heat areas across a zone map; rows follow the map's shape
-- sizes below were tuned on a 56-wide grid; this keeps glows the same size on the finer one
local GRID_SCALE = COLS / 56
local MAX_DOTS = 2000 -- Points view thins out beyond this
local PINS = 3 -- hot spots marked on the map
local HEAT_ALPHA_MIN, HEAT_ALPHA_SPAN = 0.02, 0.6 -- one glow's strength, faintest to densest
-- quiet areas fade to clear: below EDGE_FROM nothing shows, and the heat fades in up to EDGE_TO,
-- so a light scatter no longer tints the whole zone (map v3 mockup). With little data (a busiest
-- spot of a few skins) one skin is already a lot, so the fade eases off toward the old soft edge
-- (0.015 to 0.12) and every pinned spot still glows. Set per draw from the busiest spot.
local FADE_LOW = { 0.015, 0.12 } -- busiest spot of 2 skins or fewer
local FADE_HIGH = { 0.06, 0.32 } -- busiest spot of 20 skins or more
local EDGE_FROM, EDGE_TO = FADE_HIGH[1], FADE_HIGH[2]
local function SetFade(peak)
    local k = math.max(0, math.min(1, ((peak or 20) - 2) / 18))
    EDGE_FROM = FADE_LOW[1] + (FADE_HIGH[1] - FADE_LOW[1]) * k
    EDGE_TO = FADE_LOW[2] + (FADE_HIGH[2] - FADE_LOW[2]) * k
end
local SPOT_DARK = 0.5 -- Spotlight: one shade's darkness; overlapping shades build to about 0.75
local RUINED = 2934
local HIDES = { [783] = true, [4232] = true, [4235] = true, [8169] = true, [8171] = true }
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local BLOB = "Interface\\AddOns\\Fieldnotes\\Media\\blob"

local St = FN.Style
local C = St.C
local ACCENT = C.TITLE
local INK = { 0.106, 0.078, 0.047 }
local SOFT = C.INK2
local DIM = C.SUBTEXT

-- Heat color schemes, fewest to most. Thermal (the default) is the familiar cool-to-warm heat
-- scale; Solar (Karl's OKLCH gradient, 2026-11-03, replacing Ember) rises from deep indigo
-- through violet, magenta, rose, orange and gold to pale butter yellow, its lightness climbing
-- steadily, so it also reads in grayscale (11 of its 32 stops, converted to sRGB);
-- Snowfall follows a weather service's snowfall map (Karl, 2026-11-03): grey and pale blue, deep
-- blue, violet, magenta, hot pink, then teal and lavender at the very top (a saturated lavender:
-- a pale top read as a gap in the heat on parchment, seen in game).
local SCHEMES = {
    thermal = { { 0, 0.16, 0.30, 0.85 }, { 0.3, 0.15, 0.70, 0.85 }, { 0.55, 0.45, 0.85, 0.30 },
        { 0.78, 1.00, 0.85, 0.15 }, { 1, 0.90, 0.18, 0.10 } },
    solar = { { 0, 0.143, 0.120, 0.399 }, { 0.097, 0.219, 0.185, 0.481 }, { 0.194, 0.336, 0.257, 0.574 },
        { 0.29, 0.461, 0.286, 0.598 }, { 0.387, 0.586, 0.301, 0.573 }, { 0.484, 0.694, 0.314, 0.535 },
        { 0.581, 0.806, 0.342, 0.463 }, { 0.677, 0.942, 0.489, 0.310 }, { 0.774, 0.972, 0.732, 0.246 },
        { 0.871, 0.967, 0.873, 0.445 }, { 1, 1.000, 0.952, 0.674 } },
    snowfall = { { 0, 0.60, 0.62, 0.68 }, { 0.12, 0.52, 0.74, 0.96 }, { 0.24, 0.22, 0.42, 0.94 },
        { 0.38, 0.40, 0.18, 0.78 }, { 0.52, 0.84, 0.18, 0.74 }, { 0.66, 1.00, 0.36, 0.62 },
        { 0.78, 0.24, 0.80, 0.76 }, { 0.90, 0.56, 0.46, 0.92 }, { 1, 0.62, 0.36, 1.00 } },
}
M.SCHEME_ORDER = { "thermal", "solar", "snowfall" }
local RAMP = SCHEMES.thermal -- the scheme in use, set by Draw

-- Points colors, given to the map's leading leathers in order; each also differs in lightness.
-- The leading leather gets the strongest color: the pale one vanishes on light parchment.
local PALETTE = {
    { 0.890, 0.604, 0.231 }, { 0.953, 0.875, 0.659 }, { 0.247, 0.561, 0.541 }, { 0.541, 0.208, 0.149 },
}
-- the other professions' materials keep to their profession's hue (Karl, 2026-11-04): mining
-- reds, herbs greens, fish blues, cloth purples, treasure golds (mining's old yellows; mining took
-- red, 2026-11-05). Strongest first, then pale, deep, and a
-- neighbouring hue, so each still reads apart from the others.
local PALETTES = {
    skinning = PALETTE,
    mining = { { 0.88, 0.27, 0.22 }, { 0.98, 0.68, 0.60 }, { 0.58, 0.13, 0.11 }, { 0.80, 0.30, 0.46 } },
    herbalism = { { 0.40, 0.76, 0.27 }, { 0.74, 0.90, 0.54 }, { 0.18, 0.48, 0.20 }, { 0.62, 0.70, 0.24 } },
    fishing = { { 0.27, 0.62, 0.92 }, { 0.64, 0.85, 0.98 }, { 0.14, 0.36, 0.70 }, { 0.30, 0.70, 0.74 } },
    cloth = { { 0.66, 0.45, 0.90 }, { 0.86, 0.75, 0.98 }, { 0.42, 0.25, 0.66 }, { 0.82, 0.46, 0.78 } },
    treasure = { { 0.95, 0.80, 0.15 }, { 0.99, 0.93, 0.60 }, { 0.70, 0.52, 0.08 }, { 0.84, 0.66, 0.30 } },
}
M.PALETTES = PALETTES
local RUINED_COLOR = { 0.56, 0.54, 0.50 }
local OTHER_COLOR = { 0.80, 0.78, 0.74 }
local HIDE_COLOR = { 0.76, 0.62, 0.40 }
M.PALETTE, M.RUINED_COLOR, M.OTHER_COLOR = PALETTE, RUINED_COLOR, OTHER_COLOR -- the stats window's leather colors

-- The professions, in tab order, with their identity colors (professions v4 mockup, 2026-11-04):
-- the tab, icon, dashboard row, tracker row and the dashboard's dots. Heat keeps its own ramps.
--   unit/units: what one record is; material: the list's word; verb: "Nothing <verb> here yet."
--   anyone: no skill to learn, so every character has it (a tab for everyone, never "Not learned")
M.PROFS = {
    { key = "skinning", label = "Skinning", color = { 0.91, 0.50, 0.23 }, unit = "skin", units = "skins",
        material = "leather", verb = "skinned" },
    { key = "mining", label = "Mining", color = { 0.89, 0.33, 0.27 }, unit = "vein", units = "veins",
        material = "ore", verb = "mined" },
    { key = "herbalism", label = "Herbalism", color = { 0.44, 0.75, 0.31 }, unit = "herb", units = "herbs",
        material = "herbs", verb = "gathered" },
    { key = "fishing", label = "Fishing", color = { 0.31, 0.64, 0.88 }, unit = "catch", units = "catches",
        material = "catch", verb = "fished" },
    { key = "cloth", label = "Cloth", color = { 0.65, 0.49, 0.86 }, unit = "drop", units = "drops",
        material = "cloth", verb = "looted for cloth", anyone = true },
    { key = "treasure", label = "Treasure", color = { 0.95, 0.83, 0.23 }, unit = "chest", units = "chests",
        material = "loot", verb = "opened", anyone = true },
}
M.PROF = {}
for _, p in ipairs(M.PROFS) do M.PROF[p.key] = p end

-- prof: a profession's key, or "all" for the dashboard
local DEFAULTS = { on = true, mode = "heat", show = "account", leather = 0, colors = "thermal", when = 0, strength = 1,
    spread = 1, dots = false, prof = "skinning" }
M.DEFAULTS = DEFAULTS

-- the map's settings. leather: 0 (all), an item ID, "hides" or "ruined"
function M.S()
    local s = FN.db.settings.map
    if type(s) ~= "table" then
        s = {}
        FN.db.settings.map = s
    end
    for k, v in pairs(DEFAULTS) do
        if s[k] == nil then s[k] = v end
    end
    if s.colors == "ember" then s.colors = "solar" end -- Solar took Ember's place (2026-11-03)
    if not SCHEMES[s.colors] then s.colors = DEFAULTS.colors end
    if type(s.strength) ~= "number" then s.strength = DEFAULTS.strength end
    s.strength = math.max(0.5, math.min(2.5, s.strength))
    -- spread: a multiplier on the size the data suggests (an old "balanced" word reads as 1)
    if type(s.spread) ~= "number" then s.spread = DEFAULTS.spread end
    s.spread = math.max(0.5, math.min(2.5, s.spread))
    if s.prof ~= "all" and not M.PROF[s.prof] then s.prof = DEFAULTS.prof end
    return s
end
local S = M.S

local function Ramp(v)
    for i = 2, #RAMP do
        local b = RAMP[i]
        if v <= b[1] then
            local a = RAMP[i - 1]
            local t = (v - a[1]) / (b[1] - a[1])
            return a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, a[4] + (b[4] - a[4]) * t
        end
    end
    local l = RAMP[#RAMP]
    return l[2], l[3], l[4]
end
M.Ramp = Ramp

-- how much of the heat shows at v (0..1): clear in quiet areas, full from EDGE_TO up. The key's
-- ramp fades the same way the map does.
local function Quiet(v)
    local e = math.max(0, math.min(1, (v - EDGE_FROM) / (EDGE_TO - EDGE_FROM)))
    return e * e * (3 - 2 * e)
end
M.Quiet = Quiet

-- a scheme's colour at v (0..1), for swatches
function M.SchemeColor(name, v)
    local keep = RAMP
    RAMP = SCHEMES[name] or SCHEMES.thermal
    local r, g, b = Ramp(v)
    RAMP = keep
    return r, g, b
end

local function ItemName(id)
    if id == RUINED then return "Ruined scraps" end
    return (FN.ItemInfo(id)) or "..."
end

local function CreatureName(npc)
    local c = FN.View().creatures[npc]
    return (c and c.name) or "Unknown creature"
end

-- a record's source by name: the creature (skinning, cloth) or the object (mining, herbalism, treasure)
local function SourceName(prof, id)
    if prof == "mining" or prof == "herbalism" or prof == "treasure" then
        local n = FN.View().nodes and FN.View().nodes[id]
        return (n and n.name) or "Unknown node"
    end
    return CreatureName(id)
end

local function Top(counts, n)
    local keys = {}
    for k in pairs(counts) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if counts[a] ~= counts[b] then return counts[a] > counts[b] end
        return tostring(a) < tostring(b)
    end)
    local out = {}
    for i = 1, math.min(n, #keys) do out[i] = keys[i] end
    return out
end

-- the main leather of one skin: its largest stack that is not Ruined Leather Scraps; on a tie,
-- the one more common on this map (rank: itemID -> place among the map's leathers)
local function MainItem(r, rank)
    local best, bestN
    for id, n in pairs(r.items) do
        if id ~= RUINED then
            local better = not bestN or n > bestN
            if not better and n == bestN then
                local a, b = rank and rank[id] or 99, rank and rank[best] or 99
                better = a < b or (a == b and id < best)
            end
            if better then best, bestN = id, n end
        end
    end
    return best or RUINED
end

-- does a skin match the leather filter?
local function Matches(r, leather)
    if leather == 0 then return true end
    if leather == "hides" then
        for id in pairs(r.items) do
            if HIDES[id] then return true end
        end
        return false
    end
    if leather == "ruined" then return r.items[RUINED] ~= nil end
    return r.items[leather] ~= nil
end

-- ------------------------------------------------------------
-- Data for the map on screen
-- ------------------------------------------------------------
-- one profession's records on a map ("all": every profession's, each tagged r.prof). Cloth
-- keeps only the loots that dropped cloth: the map shows where it drops.
local function Records(mapID, show, days, prof)
    local since = (days and days > 0) and (time() - days * 86400) or nil
    local view = FN.View()
    prof = prof or S().prof
    local me, out = FN.ViewChar(), {}
    for _, p in ipairs(M.PROFS) do
        if prof == "all" or prof == p.key then
            -- Community: demo mode's sample layer and every imported share (Share.lua: skinning)
            local lists
            if show == "community" then
                lists = p.key == "skinning" and FN.CommunityLists("skinning", mapID) or {}
            else
                lists = { view.events[p.key] and view.events[p.key][mapID] or {} }
            end
            for _, list in ipairs(lists) do
                for _, str in ipairs(list) do
                    local r = FN.Decode(str)
                    if r and r.x and r.y and (show ~= "me" or r.char == me) and (not since or r.time >= since)
                        and (p.key ~= "cloth" or next(r.items)) then
                        r.prof = p.key
                        out[#out + 1] = r
                    end
                end
            end
        end
    end
    return out
end
M.Records = Records

-- Per profession, everywhere (for the dashboard): how many, the zone with the most, and for
-- Cloth every humanoid loot (loots), so it can say how often cloth drops. Kept until the data
-- or the choice changes.
local summary, summaryKey
FN.OnData(function() summary = nil end)
function M.Summary(show, days)
    local cur = WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID() or 0
    local key = tostring(show) .. ":" .. tostring(days) .. ":" .. tostring(FN.View() ~= FN.db) .. ":" .. tostring(cur)
    if summary and summaryKey == key then return summary end
    local since = (days and days > 0) and (time() - days * 86400) or nil
    local view, me = FN.View(), FN.ViewChar()
    summary, summaryKey = {}, key
    for _, p in ipairs(M.PROFS) do
        local n, loots, best, bestN, onMap = 0, 0, nil, 0, 0
        if show ~= "community" or p.key == "skinning" then
            for mapID, list in pairs(view.events[p.key] or {}) do
                local here = 0
                for _, str in ipairs(list) do
                    local r = FN.Decode(str)
                    if r and (show ~= "me" or r.char == me) and (not since or r.time >= since) then
                        loots = loots + 1
                        if p.key ~= "cloth" or next(r.items) then here = here + 1 end
                    end
                end
                n = n + here
                if mapID == cur then onMap = here end
                if here > bestN then best, bestN = mapID, here end
            end
        end
        local info = best and best ~= 0 and C_Map.GetMapInfo(best)
        -- here: the gathers on the map you are looking at (the dashboard's "41 here")
        summary[p.key] = { n = n, loots = loots, bestZone = info and info.name, here = onMap }
    end
    return summary
end

-- the leather list for the controls: All, each leather most first, then hides and scraps
local function LeatherList(all, prof)
    local skinning = (prof or "skinning") == "skinning"
    local counts, hides, ruined = {}, 0, 0
    for _, r in ipairs(all) do
        for id, n in pairs(r.items) do
            if skinning and id == RUINED then
                ruined = ruined + n
            elseif skinning and HIDES[id] then
                hides = hides + n
            else
                counts[id] = (counts[id] or 0) + n
            end
        end
    end
    local material = M.PROF[prof or "skinning"] and M.PROF[prof or "skinning"].material or "leather"
    local list, colorOf, rank = { { key = 0, label = "All " .. material } }, { [RUINED] = RUINED_COLOR }, {}
    local palette = PALETTES[prof or "skinning"] or PALETTE
    for i, id in ipairs(Top(counts, 12)) do
        local color = palette[i] or OTHER_COLOR
        colorOf[id], rank[id] = color, i
        list[#list + 1] = { key = id, label = ItemName(id), count = counts[id], color = color }
    end
    for id in pairs(HIDES) do colorOf[id] = colorOf[id] or HIDE_COLOR end
    if hides > 0 then list[#list + 1] = { key = "hides", label = "Hides", count = hides, color = HIDE_COLOR } end
    if ruined > 0 then list[#list + 1] = { key = "ruined", label = "Ruined scraps", count = ruined, color = RUINED_COLOR } end
    return list, colorOf, rank
end

-- The heat follows the data: few skins draw tight, exact glows and show every one; many draw
-- broader areas and leave out lone skins (about one skin's worth) so the real grounds stand out.
local function Auto(n)
    -- (glow size in areas, smoothing passes, leave out lone skins)
    if n < 60 then return 1.9 * GRID_SCALE, 2, false end
    if n < 400 then return 2.6 * GRID_SCALE, 3, n >= 100 end
    return 3.6 * GRID_SCALE, 4, true
end

-- returns the smoothed grid, its peak, and the most any one area holds before smoothing
local function HeatGrid(recs, cols, rows, passes)
    local g = {}
    for i = 1, cols * rows do g[i] = 0 end
    for _, r in ipairs(recs) do
        local c = math.min(cols - 1, math.floor(r.x / 1000 * cols))
        local rr = math.min(rows - 1, math.floor(r.y / 1000 * rows))
        local i = rr * cols + c + 1
        g[i] = g[i] + 1
    end
    local rawMax = 0
    for i = 1, #g do
        if g[i] > rawMax then rawMax = g[i] end
    end
    -- smooth with a 3x3 kernel so the heat reads as areas, not specks
    for _ = 1, passes do
        local n = {}
        for rr = 0, rows - 1 do
            for c = 0, cols - 1 do
                local s = 0
                for dr = -1, 1 do
                    for dc = -1, 1 do
                        local r2, c2 = rr + dr, c + dc
                        if r2 >= 0 and r2 < rows and c2 >= 0 and c2 < cols then
                            s = s + g[r2 * cols + c2 + 1] * (dr == 0 and 2 or 1) * (dc == 0 and 2 or 1)
                        end
                    end
                end
                n[rr * cols + c + 1] = s / 16
            end
        end
        g = n
    end
    local max = 0
    for i = 1, #g do
        if g[i] > max then max = g[i] end
    end
    return g, max, rawMax
end

-- the densest areas, at least six areas apart, strongest first
local function Peaks(g, max, cols)
    local order = {}
    for i = 1, #g do
        if g[i] >= max * 0.35 then order[#order + 1] = i end
    end
    table.sort(order, function(a, b) return g[a] > g[b] end)
    local out = {}
    for _, i in ipairs(order) do
        local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
        local far = true
        for _, p in ipairs(out) do
            if math.abs(p.c - c) < 6 * GRID_SCALE and math.abs(p.r - r) < 6 * GRID_SCALE then far = false end
        end
        if far then out[#out + 1] = { c = c, r = r } end
        if #out >= PINS then break end
    end
    return out
end

-- ------------------------------------------------------------
-- What is drawn on the map (made once, the first time the map opens)
-- ------------------------------------------------------------
local overlay, mute
local blobs, dots, rings, pins, shades, badges = {}, {}, {}, {}, {}, {}
local ui = {}
M.ui = ui -- shared with MapUI.lua; read by tools/check.py

local function Pooled(pool, i, layer, sub, texture)
    local t = pool[i]
    if not t then
        t = overlay:CreateTexture(nil, layer, nil, sub)
        t:SetTexture(texture)
        pool[i] = t
    end
    t:Show()
    return t
end

local function HidePool(pool, from)
    for i = from or 1, #pool do pool[i]:Hide() end
end

local function PinTooltip(self)
    local p = self.info
    if not p then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Hot spot " .. (p.rank or ""), ACCENT[1], ACCENT[2], ACCENT[3])
    GameTooltip:AddLine(p.count .. (p.count == 1 and " skin here" or " skins here"), 1, 1, 1)
    if p.who ~= "" then GameTooltip:AddLine(p.who, SOFT[1], SOFT[2], SOFT[3], true) end
    if p.loot ~= "" then GameTooltip:AddLine(p.loot, SOFT[1], SOFT[2], SOFT[3], true) end
    GameTooltip:AddLine(p.coords, DIM[1], DIM[2], DIM[3])
    GameTooltip:Show()
end

local function Pin(i)
    local p = pins[i]
    if p then return p end
    p = CreateFrame("Button", nil, overlay)
    p:SetFrameLevel(overlay:GetFrameLevel() + 10)
    p.disc = p:CreateTexture(nil, "ARTWORK")
    p.disc:SetAllPoints()
    p.disc:SetTexture(CIRCLE)
    p.disc:SetVertexColor(1, 0.96, 0.86, 1)
    p.dot = p:CreateTexture(nil, "OVERLAY")
    p.dot:SetPoint("CENTER")
    p.dot:SetTexture(CIRCLE)
    p.dot:SetVertexColor(INK[1], INK[2], INK[3], 1)
    -- its rank above it, and a gold ring that lights with its row in the dock's hot spots list
    p.num = St.Title(p, 13)
    p.num:SetPoint("BOTTOM", p, "TOP", 0, 1)
    p.num:SetTextColor(1, 1, 1)
    p.num:SetShadowColor(0, 0, 0, 1)
    p.ring = p:CreateTexture(nil, "BACKGROUND")
    p.ring:SetPoint("CENTER")
    p.ring:SetTexture(St.Media("ring"))
    p.ring:SetVertexColor(C.ACCENT[1], C.ACCENT[2], C.ACCENT[3], 1)
    p.ring:Hide()
    -- motion rings (see PinMotion): one breathes while the pin is lit, two ripple out on a ping
    p.pulse = p:CreateTexture(nil, "BACKGROUND", nil, 1)
    p.ripples = {}
    for j, t in ipairs({ p.pulse, p:CreateTexture(nil, "BACKGROUND", nil, 2), p:CreateTexture(nil, "BACKGROUND", nil, 2) }) do
        t:SetPoint("CENTER")
        t:SetTexture(St.Media("ring"))
        t:SetVertexColor(C.ACCENT[1], C.ACCENT[2], C.ACCENT[3], 1)
        t:Hide()
        if j > 1 then p.ripples[j - 1] = t end
    end
    p:SetScript("OnEnter", function(self)
        PinTooltip(self)
        M.LightPin(self.rank, true, true)
    end)
    p:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        M.LightPin(self.rank, false, true)
    end)
    pins[i] = p
    return p
end

-- the pin for a hot spot (by rank), lit with a gold ring; fromPin: the dock's row lights too
local byRank = {}
local function PinScale()
    local mine = overlay and overlay:GetEffectiveScale()
    local screen = UIParent:GetEffectiveScale()
    if not (mine and mine > 0 and screen and screen > 0) then return 1 end
    return screen / mine
end
-- Pin motion, kept small and calm (micro-interaction practice: instant feedback, then a quiet loop;
-- motion that grows outward and slows as it goes, eased out; nothing runs when nothing moves).
--   Lit (its row or the pin hovered): a steady gold ring at once, and a second ring breathing
--   outward and fading every PULSE seconds. The dock's badge breathes on the same clock.
--   Ping (a click on its row): two rings ripple out from the pin, a beat apart, and fade.
local PULSE = 1.6 -- seconds per breath
local PULSE_REACH = 14 -- how far a breath grows past the steady ring
local PING_DUR, PING_GAP, PING_REACH = 0.9, 0.22, 46 -- a ripple's life, the beat between two, its reach
M.PULSE = PULSE

local function EaseOut(t) return 1 - (1 - t) ^ 3 end

local function PinMotion(p)
    local k = p.k or 1
    local base = p:GetWidth() + 10 * k
    local now = GetTime()
    if p.lit then
        local t = (now % PULSE) / PULSE
        local d = base + PULSE_REACH * k * EaseOut(t)
        p.pulse:SetSize(d, d)
        p.pulse:SetAlpha(0.55 * (1 - t) ^ 1.6)
        p.pulse:Show()
    else
        p.pulse:Hide()
    end
    local pinging = false
    if p.pingAt then
        for j, rip in ipairs(p.ripples) do
            local t = (now - p.pingAt - (j - 1) * PING_GAP) / PING_DUR
            if t < 1 then pinging = true end
            if t > 0 and t < 1 then
                local d = base + PING_REACH * k * EaseOut(t)
                rip:SetSize(d, d)
                rip:SetAlpha(0.9 * (1 - t) ^ 2)
                rip:Show()
            else
                rip:Hide()
            end
        end
        if not pinging then p.pingAt = nil end
    end
    if not p.lit and not pinging then p:SetScript("OnUpdate", nil) end
end

-- a pin at rest: no rings, nothing running (each redraw starts its pins this way)
local function PinRest(p)
    p.lit, p.pingAt = false, nil
    p.ring:Hide()
    p.pulse:Hide()
    for _, rip in ipairs(p.ripples) do rip:Hide() end
    p:SetScript("OnUpdate", nil)
end

function M.LightPin(rank, on, fromPin)
    local p = rank and byRank[rank]
    if p and p:IsShown() then
        local base = p:GetWidth() + 10 * (p.k or 1)
        p.lit = on and true or false
        p.ring:SetSize(base, base)
        p.ring:SetAlpha(1)
        p.ring:SetShown(on)
        if on then
            p:SetScript("OnUpdate", PinMotion)
        elseif not p.pingAt then
            PinMotion(p) -- hides the breath and stops
        end
    end
    if fromPin and FN.MapUI and FN.MapUI.LightSpot then FN.MapUI.LightSpot(rank, on) end
end

-- a click on a hot spot row: two rings ripple out from its pin, so the eye finds it
function M.PingPin(rank)
    local p = rank and byRank[rank]
    if not (p and p:IsShown()) then return end
    p.pingAt = GetTime()
    p:SetScript("OnUpdate", PinMotion)
end

-- ------------------------------------------------------------
-- Continent and world maps: one badge per zone
-- ------------------------------------------------------------
-- Each zone you have notes for gets a badge at its centre, sized and coloured by its skins.
-- Hover for the zone's numbers; click to open it.

-- the zones under a continent (or the world), each with its centre on that map
local function ZonesUnder(mapID, zoneType)
    local out, seen = {}, {}
    local ok, kids = pcall(C_Map.GetMapChildrenInfo, mapID, zoneType, true)
    if not ok or type(kids) ~= "table" then return out end
    for _, k in ipairs(kids) do
        if k.mapType == zoneType and not seen[k.mapID] then
            seen[k.mapID] = true
            local ok2, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, k.mapID, mapID)
            if ok2 and minX and maxX and maxX > minX and maxY > minY then
                out[#out + 1] = { id = k.mapID, name = k.name, x = (minX + maxX) / 2, y = (minY + maxY) / 2 }
            end
        end
    end
    return out
end

local function BadgeTooltip(self)
    local z = self.zone
    if not z then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(z.name, ACCENT[1], ACCENT[2], ACCENT[3])
    GameTooltip:AddLine(z.summary, 1, 1, 1)
    if z.who ~= "" then GameTooltip:AddLine(z.who, SOFT[1], SOFT[2], SOFT[3], true) end
    if z.loot ~= "" then GameTooltip:AddLine(z.loot, SOFT[1], SOFT[2], SOFT[3], true) end
    GameTooltip:AddLine("Click to open the zone map.", DIM[1], DIM[2], DIM[3])
    GameTooltip:Show()
end

local function Badge(i)
    local b = badges[i]
    if b then return b end
    b = CreateFrame("Button", nil, overlay)
    -- one layer above the map, so its own icons (dungeon towers, other add-ons' pins) never
    -- cover a badge's number; the controls sit higher still (MapUI.lua)
    b:SetFrameStrata(M.strata or "HIGH")
    b.ring = b:CreateTexture(nil, "ARTWORK", nil, 1)
    b.ring:SetAllPoints()
    b.ring:SetTexture(CIRCLE)
    b.ring:SetVertexColor(0.08, 0.055, 0.03, 0.95)
    b.disc = b:CreateTexture(nil, "ARTWORK", nil, 2)
    b.disc:SetPoint("TOPLEFT", 2, -2)
    b.disc:SetPoint("BOTTOMRIGHT", -2, 2)
    b.disc:SetTexture(CIRCLE)
    b.label = St.Text(b, 11, C.TEXT)
    b.label:SetPoint("CENTER", 0, 0)
    b.label:SetJustifyH("CENTER")
    b.label:SetShadowColor(0, 0, 0, 1)
    b.label:SetShadowOffset(1, -1)
    b:SetScript("OnEnter", BadgeTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        if self.zone then WorldMapFrame:SetMapID(self.zone.id) end
    end)
    badges[i] = b
    return b
end

-- a badge keeps its size on screen however far the map is zoomed (it sits on the map, which scales)
local function ApplyBadge(b, k)
    b.k = k
    b:SetScale(k)
    b:ClearAllPoints()
    b:SetPoint("CENTER", overlay, "TOPLEFT", b.px / k, b.py / k)
end

-- When the map changes, the badges of the map you left stay a moment as copies and fade out,
-- while the new picture fades in: no hard cut. The copies hang off the canvas, not the overlay, so
-- the overlay's own fade-in leaves them alone.
local ghosts = {}
local function GhostBadges()
    local canvas = WorldMapFrame:GetCanvas()
    local any = false
    for i, b in ipairs(badges) do
        if b:IsShown() and b.px then
            local g = ghosts[i]
            if not g then
                g = CreateFrame("Frame", nil, canvas)
                g:EnableMouse(false)
                g.ring = g:CreateTexture(nil, "ARTWORK", nil, 1)
                g.ring:SetAllPoints()
                g.ring:SetTexture(CIRCLE)
                g.ring:SetVertexColor(0.08, 0.055, 0.03, 0.95)
                g.disc = g:CreateTexture(nil, "ARTWORK", nil, 2)
                g.disc:SetPoint("TOPLEFT", 2, -2)
                g.disc:SetPoint("BOTTOMRIGHT", -2, 2)
                g.disc:SetTexture(CIRCLE)
                g.label = St.Text(g, 11, C.TEXT)
                g.label:SetPoint("CENTER", 0, 0)
                g.label:SetShadowOffset(1, -1)
                ghosts[i] = g
            end
            local k = b.k or 1
            g:SetFrameStrata(b:GetFrameStrata())
            g:SetFrameLevel(b:GetFrameLevel())
            g:SetSize(b:GetSize())
            g.k0, g.px, g.py = k, b.px, b.py
            g:SetScale(k)
            g:ClearAllPoints()
            g:SetPoint("CENTER", overlay, "TOPLEFT", b.px / k, b.py / k)
            g.disc:SetVertexColor(b.disc:GetVertexColor())
            g.label:SetText(b.label:GetText())
            g.label:SetTextColor(b.label:GetTextColor())
            g:SetAlpha(1)
            g:Show()
            any = true
        end
    end
    M.ghostRuns = (M.ghostRuns or 0) + 1
    M.ghostAny = any
    if not any then return end
    M.ghostWith = (M.ghostWith or 0) + 1
    St.Animate("fn-ghost", 1, 0, nil, function() end)
    -- the copies swell as they fade, as if the map were still carrying them in: it reads as a
    -- continuation of the zoom, and not as a badge that just turned off
    St.Animate("fn-ghost", 0, 0.8, "soft", function(v)
        for _, g in pairs(ghosts) do
            if g:IsShown() and g.px then
                local k = g.k0 * (1 + 0.45 * (1 - v))
                g:SetScale(k)
                g:ClearAllPoints()
                g:SetPoint("CENTER", overlay, "TOPLEFT", g.px / k, g.py / k)
                g:SetAlpha(v)
            end
        end
    end, function()
        for _, g in pairs(ghosts) do g:Hide() end
    end)
end

local function Short(n)
    if n >= 10000 then return string.format("%dk", math.floor(n / 1000 + 0.5)) end
    if n >= 1000 then return string.format("%.1fk", n / 1000) end
    return tostring(n)
end

local function DrawContinent(s, mapID, zoneType, model)
    model.kind = "continent"
    local zones = ZonesUnder(mapID, zoneType)
    local all, perZone = {}, {}
    for _, z in ipairs(zones) do
        local recs = Records(z.id, s.show, s.when, s.prof)
        if #recs > 0 then
            perZone[#perZone + 1] = { zone = z, recs = recs }
            for _, r in ipairs(recs) do all[#all + 1] = r end
        end
    end
    local list, colorOf = LeatherList(all, s.prof)
    model.leathers, model.colorOf = list, colorOf
    local known = false
    for _, l in ipairs(list) do
        if l.key == s.leather then known = true end
    end
    if not known then s.leather = 0 end
    model.leather = s.leather

    local rows, max, total = {}, 0, 0
    for _, pz in ipairs(perZone) do
        local n, who, loot = 0, {}, {}
        for _, r in ipairs(pz.recs) do
            if Matches(r, s.leather) then
                n = n + 1
                if r.npc > 0 then who[r.npc] = (who[r.npc] or 0) + 1 end
                for id, k in pairs(r.items) do
                    if id ~= RUINED then loot[id] = (loot[id] or 0) + k end
                end
            end
        end
        if n > 0 then
            rows[#rows + 1] = { zone = pz.zone, value = n, who = who, loot = loot }
            max = math.max(max, n)
            total = total + n
        end
    end
    -- biggest first, so smaller badges sit on top where they overlap
    table.sort(rows, function(a, b) return a.value > b.value end)

    local w, h = overlay:GetSize()
    for i, row in ipairs(rows) do
        local v = row.value / max
        local b = Badge(i)
        local size = 22 + 26 * math.sqrt(v) -- area grows with the value
        b:SetSize(size, size)
        b:SetFrameStrata(M.strata or "HIGH")
        b:SetFrameLevel(100 + i)
        b.px, b.py = row.zone.x * w, -row.zone.y * h
        ApplyBadge(b, PinScale())
        local lr, lg, lb = Ramp(0.15 + 0.85 * v)
        b.disc:SetVertexColor(lr, lg, lb)
        b.label:SetText(Short(row.value))
        -- dark numbers on the pale end of the scale, light ones on the dark end
        if 0.299 * lr + 0.587 * lg + 0.114 * lb > 0.6 then
            b.label:SetTextColor(INK[1], INK[2], INK[3])
            b.label:SetShadowColor(1, 1, 1, 0.25)
        else
            b.label:SetTextColor(1, 1, 1)
            b.label:SetShadowColor(0, 0, 0, 1)
        end
        local names, items = {}, {}
        if s.prof ~= "all" then
            for _, npc in ipairs(Top(row.who, 2)) do names[#names + 1] = SourceName(s.prof, npc) end
        end
        for _, id in ipairs(Top(row.loot, 2)) do items[#items + 1] = ItemName(id) end
        local unitP = M.PROF[s.prof] or { unit = "gather", units = "gathers" }
        b.zone = {
            id = row.zone.id, name = row.zone.name,
            summary = row.value .. " " .. (row.value == 1 and unitP.unit or unitP.units),
            who = table.concat(names, ", "), loot = table.concat(items, "  ·  "),
        }
        b:Show()
    end
    ui.badgeCount = #rows

    model.skins = total
    model.zones = #rows
    model.bestZone = rows[1] and rows[1].zone.name
    model.scale = "Badge size and color: " .. ((M.PROF[s.prof] and M.PROF[s.prof].units) or "gathers")
        .. " per zone. Click one to open it."
    if #rows == 0 then
        model.message = s.show == "community" and "Nothing shared on this map yet."
            or ("Nothing " .. ((M.PROF[s.prof] and M.PROF[s.prof].verb) or "gathered") .. " on this map yet.")
    end
    -- on the full-screen map the key goes in whichever bottom corner covers fewer badges
    local left, right = 0, 0
    for _, row in ipairs(rows) do
        if row.zone.y > 0.6 then
            if row.zone.x < 0.5 then left = left + 1 else right = right + 1 end
        end
    end
    model.keyCorner = right < left and "BOTTOMRIGHT" or "BOTTOMLEFT"
end

-- The layer above the map's own, for the continent badges and, over them, the controls. The map
-- changes layer when it is maximized or made small again, and takes every frame on it along,
-- so this is picked again on every redraw (once, at the first open, left the bar behind a
-- maximized map).
local ORDER = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG" }
local function Layer()
    -- the window, its scroll area and the map art can each be on a different layer after a
    -- maximize (/fn debug, 2026-11-03: window MEDIUM, bar HIGH and hidden under the art), so
    -- take the highest of them
    local rank, top = {}, 1
    for i, name in ipairs(ORDER) do rank[name] = i end
    local container = WorldMapFrame.ScrollContainer
    for _, f in ipairs({ WorldMapFrame, container, WorldMapFrame:GetCanvas() }) do
        local r = f and rank[f:GetFrameStrata()]
        if r and r > top then top = r end
    end
    M.strata = ORDER[top + 1] or "FULLSCREEN_DIALOG"
    for _, b in ipairs(badges) do b:SetFrameStrata(M.strata) end
    if FN.MapUI then FN.MapUI.Layer(M.strata) end

    -- the heat and dots go just above the map's art: the explored areas are drawn on frames of
    -- their own, above the canvas, and covered the overlay wherever you had been (2026-11-03:
    -- a blue sliver in a gap between explored areas, the rest hidden). Blizzard's pins (your
    -- arrow, flight points) stay on top.
    local canvas = WorldMapFrame:GetCanvas()
    local level = canvas:GetFrameLevel()
    local mgr = WorldMapFrame.GetPinFrameLevelsManager and WorldMapFrame:GetPinFrameLevelsManager()
    if mgr and mgr.GetValidFrameLevel then
        local ok, l = pcall(mgr.GetValidFrameLevel, mgr, "PIN_FRAME_LEVEL_MAP_EXPLORATION")
        if ok and type(l) == "number" and l > level then level = l end
    end
    if WorldMapFrame.EnumeratePinsByTemplate then
        local ok, iter = pcall(WorldMapFrame.EnumeratePinsByTemplate, WorldMapFrame, "MapExplorationPinTemplate")
        if ok and iter then
            for pin in iter do
                local l = pin:GetFrameLevel()
                if l > level then level = l end
            end
        end
    end
    -- OpenMap (stitched world map) draws its art on the canvas up to this level: go above it
    local om = _G.OpenMapAPI
    if om and om.ArtTopLevel then
        local ok, l = pcall(om.ArtTopLevel)
        if ok and type(l) == "number" and l > level then level = l end
    end
    M.overlayLevel = level + 1
    overlay:SetFrameLevel(M.overlayLevel)
    for _, p in pairs(pins) do p:SetFrameLevel(M.overlayLevel + 10) end
end

-- the overlay fades as a whole when Fieldnotes is switched off or on (MapUI.lua animates it)
function M.SetOverlayAlpha(a)
    if overlay then overlay:SetAlpha(a) end
end

-- The dashboard's map: every gather as a dot in its profession's color, no heat (adding the
-- professions' heat together means nothing). Hovering a dashboard row lights that profession:
-- the others fade back, its dots grow, glow and sit on top.
local function DrawDashboard(s, mapID, model)
    model.kind = "dash"
    local recs = mapID and Records(mapID, s.show, s.when, "all") or {}
    model.skins = #recs
    if #recs == 0 then
        model.message = s.show == "community" and "Nothing shared for this zone yet." or "Nothing gathered here yet."
        return
    end
    -- the full-screen key: each profession's color and count on this map
    local per = {}
    for _, r in ipairs(recs) do per[r.prof] = (per[r.prof] or 0) + 1 end
    model.legend = {}
    local most = 1
    for _, n in pairs(per) do most = math.max(most, n) end
    for _, p in ipairs(M.PROFS) do
        if per[p.key] then
            -- count and frac (of the busiest profession) draw the Home key's bars
            model.legend[#model.legend + 1] = { color = p.color, label = p.label, prof = p.key,
                count = per[p.key], frac = per[p.key] / most }
        end
    end
    local w, h = overlay:GetSize()
    if not w or w <= 0 or not h or h <= 0 then return end
    local lit = M.lit
    if lit and not M.PROF[lit] then lit = nil end
    -- the lit profession last, so its dots sit on top (a stable split: others, then the lit one)
    if lit then
        local others, mine = {}, {}
        for _, r in ipairs(recs) do
            if r.prof == lit then mine[#mine + 1] = r else others[#others + 1] = r end
        end
        for _, r in ipairs(mine) do others[#others + 1] = r end
        recs = others
    end
    local step = math.max(1, math.ceil(#recs / MAX_DOTS))
    -- screen pixels times the map's zoom, so the dots stay small however far in the map is
    local k = PinScale()
    local dot = (#recs > 800 and 2.5 or (#recs > 150 and 3.2 or 4)) * k
    local n, g = 0, 0
    for i = 1, #recs, step do
        local r = recs[i]
        local c = M.PROF[r.prof].color
        local on, dim = r.prof == lit, lit and r.prof ~= lit
        local px, py = r.x / 1000 * w, -r.y / 1000 * h
        local size = on and dot * 1.35 or dot
        if on then
            g = g + 1
            local glow = Pooled(blobs, g, "ARTWORK", 0, BLOB)
            glow:ClearAllPoints()
            glow:SetPoint("CENTER", overlay, "TOPLEFT", px, py)
            glow:SetSize(size * 4, size * 4)
            glow:SetVertexColor(c[1], c[2], c[3], 0.35)
        end
        n = n + 1
        local ring = Pooled(rings, n, "ARTWORK", 1, CIRCLE)
        ring:ClearAllPoints()
        ring:SetPoint("CENTER", overlay, "TOPLEFT", px, py)
        ring:SetSize(size + 2 * k, size + 2 * k)
        ring:SetVertexColor(0.08, 0.055, 0.03, dim and 0.15 or 0.9)
        local d = Pooled(dots, n, "ARTWORK", 2, CIRCLE)
        d:ClearAllPoints()
        d:SetPoint("CENTER", overlay, "TOPLEFT", px, py)
        d:SetSize(size, size)
        d:SetVertexColor(c[1], c[2], c[3], dim and 0.18 or 1)
    end
end

-- go to a page ("all" or a profession). Each page starts on all of its material: a leather
-- filter chosen on another page (Hides, say) never follows you, which read as a nearly empty map.
function M.SetProf(key)
    local s = S()
    if s.prof ~= key then
        s.prof = key
        s.leather = 0
    end
    M.lit = nil
end

-- light one profession's dots on the dashboard map (nil: none)
function M.SetLit(prof)
    if M.lit == prof then return end
    M.lit = prof
    if S().prof == "all" then M.Refresh() end
end

local function Draw()
    local s = S()
    Layer()
    do
        local nowMap = WorldMapFrame:GetMapID()
        if s.on and M.drawnMap ~= nil and nowMap ~= M.drawnMap then GhostBadges() end
    end
    HidePool(blobs)
    HidePool(dots)
    HidePool(rings)
    HidePool(pins)
    HidePool(shades)
    HidePool(badges)
    ui.badgeCount = 0
    RAMP = SCHEMES[s.colors]

    local mapID = WorldMapFrame:GetMapID()
    local model = {
        on = s.on, mode = s.mode, show = s.show, leather = s.leather, colors = s.colors, when = s.when,
        inDemo = FN.View() ~= FN.db, kind = "zone", keyCorner = "BOTTOMLEFT", leathers = {}, colorOf = {},
        prof = s.prof, p = M.PROF[s.prof] or { unit = "gather", units = "gathers", material = "gathers", verb = "gathered" },
        place = mapID and C_Map.GetMapInfo(mapID) and C_Map.GetMapInfo(mapID).name,
    }
    M.model = model

    -- zooming between the continent's badges and a zone's heat: the new picture eases in instead of
    -- snapping (same tween as the on/off fade, so the two never fight). Only when the map changed.
    if s.on and mapID ~= M.drawnMap then
        if M.drawnMap ~= nil then
            St.Animate("fn-overlay", 0, 0, nil, M.SetOverlayAlpha)
            St.Animate("fn-overlay", 1, 0.6, "soft", M.SetOverlayAlpha)
        end
    end
    M.drawnMap = mapID

    if not s.on then
        mute:Hide()
        if FN.MapUI then FN.MapUI.Render(model) end
        return
    end
    mute:SetShown(s.mode ~= "spotlight")

    local info = mapID and C_Map.GetMapInfo(mapID)
    local zoneType = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
    if info and info.mapType and info.mapType < zoneType then
        DrawContinent(s, mapID, zoneType, model)
        if FN.MapUI then FN.MapUI.Render(model) end
        return
    end

    if s.prof == "all" then
        DrawDashboard(s, mapID, model)
        if FN.MapUI then FN.MapUI.Render(model) end
        return
    end

    local all = mapID and Records(mapID, s.show, s.when, s.prof) or {}
    local list, colorOf, rank = LeatherList(all, s.prof)
    model.leathers, model.colorOf = list, colorOf
    local known = false
    for _, l in ipairs(list) do
        if l.key == s.leather then known = true end
    end
    if not known then s.leather = 0 end
    model.leather = s.leather

    local recs = all
    if s.leather ~= 0 then
        recs = {}
        for _, r in ipairs(all) do
            if Matches(r, s.leather) then recs[#recs + 1] = r end
        end
    end
    model.skins = #recs

    if #recs == 0 then
        local verb = model.p.verb
        local learned = model.p.anyone or not FN.ProfessionSkill or (FN.ProfessionSkill(s.prof) or 0) > 0
        if not learned and s.show == "me" then
            model.message = "You haven't learned " .. model.p.label .. " yet."
        elseif #all > 0 then
            model.message = "Nothing here matches that " .. model.p.material .. "."
        elseif s.when > 0 then
            model.message = string.format("Nothing %s here in the last %d days.", verb, s.when)
        elseif s.show == "community" then
            model.message = "Nothing shared for this zone yet."
        elseif s.show == "me" then
            model.message = "This character hasn't " .. verb .. " here yet."
        else
            model.message = "Nothing " .. verb .. " here yet."
        end
        if FN.MapUI then FN.MapUI.Render(model) end
        return
    end

    local w, h = overlay:GetSize()
    if not w or w <= 0 or not h or h <= 0 then
        if FN.MapUI then FN.MapUI.Render(model) end
        return
    end
    local cols = COLS
    local rows = math.max(1, math.floor(cols * h / w + 0.5))
    local cw, ch = w / cols, h / rows
    local spread, passes, hideThin = Auto(#recs)
    local g, max, rawMax = HeatGrid(recs, cols, rows, passes)
    SetFade(rawMax)
    local size = spread * s.spread * math.max(cw, ch)
    local function Counts(i)
        return g[i] / max >= EDGE_FROM and (not hideThin or g[i] >= 0.35 / (GRID_SCALE * GRID_SCALE))
    end

    if s.mode == "heat" then
        -- faint areas first, so the strongest glow sits on top
        local order = {}
        for i = 1, #g do
            if Counts(i) then order[#order + 1] = i end
        end
        table.sort(order, function(a, b) return g[a] < g[b] end)
        for n, i in ipairs(order) do
            local v = g[i] / max
            local t = Pooled(blobs, n, "ARTWORK", 0, BLOB)
            local c, rr = (i - 1) % cols, math.floor((i - 1) / cols)
            t:ClearAllPoints()
            t:SetPoint("CENTER", overlay, "TOPLEFT", (c + 0.5) * cw, -(rr + 0.5) * ch)
            t:SetSize(size, size)
            local r, gg, b = Ramp(v)
            -- quiet areas fade out, so the heat's edge dissolves into the map
            t:SetVertexColor(r, gg, b, math.min(0.95, (HEAT_ALPHA_MIN + HEAT_ALPHA_SPAN * v) * s.strength) * Quiet(v))
        end
    elseif s.mode == "spotlight" then
        -- the map dims everywhere except where you skin: a soft shade on every area, fading
        -- out as the heat rises, one area past each edge so the edges dim evenly too
        local n = 0
        for rr = -1, rows do
            for c = -1, cols do
                local v = 0
                if rr >= 0 and rr < rows and c >= 0 and c < cols then
                    local i = rr * cols + c + 1
                    if Counts(i) then v = g[i] / max end
                end
                local a = math.min(0.9, SPOT_DARK * s.strength) * (1 - math.min(1, v * 1.8)) ^ 1.5
                if a > 0.02 then
                    n = n + 1
                    local t = Pooled(shades, n, "ARTWORK", 0, BLOB)
                    t:ClearAllPoints()
                    t:SetPoint("CENTER", overlay, "TOPLEFT", (c + 0.5) * cw, -(rr + 0.5) * ch)
                    t:SetSize(size * 1.15, size * 1.15)
                    t:SetVertexColor(0.02, 0.015, 0.01, a)
                end
            end
        end
    end
    -- one dot per skin: Points view, or laid over Heat and Spotlight (smaller, a little faint)
    -- with the "Every skin" switch
    local over = s.mode ~= "points"
    if not over or s.dots then
        local step = math.max(1, math.ceil(#recs / MAX_DOTS))
        -- screen pixels (times the map's zoom, so they read the same at any zoom): small, so a
        -- crowded zone stays a scatter of dots and not one orange mass
        local k = PinScale()
        local dot = (over and (#recs > 800 and 2.2 or 3) or (#recs > 800 and 3.5 or (#recs > 150 and 4.2 or 5.5))) * k
        local alpha = over and 0.75 or 1
        local n = 0
        for i = 1, #recs, step do
            local r = recs[i]
            n = n + 1
            local px, py = r.x / 1000 * w, -r.y / 1000 * h
            if not over then
                local ring = Pooled(rings, n, "ARTWORK", 1, CIRCLE)
                ring:ClearAllPoints()
                ring:SetPoint("CENTER", overlay, "TOPLEFT", px, py)
                ring:SetSize(dot + 2 * k, dot + 2 * k)
                ring:SetVertexColor(0.08, 0.055, 0.03, 0.95)
            end
            local d = Pooled(dots, n, "ARTWORK", 2, CIRCLE)
            d:ClearAllPoints()
            d:SetPoint("CENTER", overlay, "TOPLEFT", px, py)
            d:SetSize(dot, dot)
            -- filtered to one leather, every dot is that leather
            local key = s.leather
            local c = (type(key) == "number" and key ~= 0 and colorOf[key])
                or (key == "hides" and HIDE_COLOR) or (key == "ruined" and RUINED_COLOR)
                or colorOf[MainItem(r, rank)] or OTHER_COLOR
            d:SetVertexColor(c[1], c[2], c[3], alpha)
        end
    end

    -- hot spot pins: what lives in each, shown on hover, ranked; the dock lists them too
    model.spots = {}
    wipe(byRank)
    for i, peak in ipairs(Peaks(g, max, cols)) do
        local hx, hy = (peak.c + 0.5) / cols, (peak.r + 0.5) / rows
        local near, who, loot = 0, {}, {}
        for _, r in ipairs(recs) do
            if math.abs(r.x / 1000 - hx) < 2.5 * GRID_SCALE / cols and math.abs(r.y / 1000 - hy) < 2.5 * GRID_SCALE / rows then
                near = near + 1
                if r.npc > 0 then who[r.npc] = (who[r.npc] or 0) + 1 end
                local m = MainItem(r, rank)
                loot[m] = (loot[m] or 0) + 1
            end
        end
        if near > 0 then
            local names, items = {}, {}
            for _, npc in ipairs(Top(who, 2)) do names[#names + 1] = SourceName(s.prof, npc) end
            for _, id in ipairs(Top(loot, 2)) do items[#items + 1] = ItemName(id) end
            local p = Pin(i)
            -- the map art is drawn at its own (smaller) scale; size the pin and its number for the
            -- screen so they read the same at any map size
            local k = PinScale()
            local pin = (i == 1 and 16 or 12) * k
            p:SetSize(pin, pin)
            p.dot:SetSize(pin / 2, pin / 2)
            p.k = k
            p.num:SetFont(STANDARD_TEXT_FONT, 13 * k, "OUTLINE")
            p.num:ClearAllPoints()
            p.num:SetPoint("BOTTOM", p, "TOP", 0, k)
            p:ClearAllPoints()
            p:SetPoint("CENTER", overlay, "TOPLEFT", hx * w, -hy * h)
            local rankN = #model.spots + 1
            p.rank = rankN
            p.num:SetText(rankN)
            PinRest(p)
            p.info = {
                rank = rankN, count = near, who = table.concat(names, ", "), loot = table.concat(items, "  ·  "),
                coords = string.format("%d, %d", math.floor(hx * 100 + 0.5), math.floor(hy * 100 + 0.5)),
            }
            model.spots[rankN] = p.info
            byRank[rankN] = p
            p:Show()
        end
    end

    -- the key: how many, what you skin most here, and the scale
    local who, loot = {}, {}
    for _, r in ipairs(recs) do
        if r.npc > 0 then who[r.npc] = (who[r.npc] or 0) + 1 end
        local m = MainItem(r, rank)
        if m ~= RUINED then loot[m] = (loot[m] or 0) + 1 end
    end
    local topWho, topLoot = Top(who, 1)[1], Top(loot, 1)[1]
    model.topWho = topWho and SourceName(s.prof, topWho)
    model.topLoot = topLoot and ItemName(topLoot)
    if s.mode == "heat" then
        model.peak = rawMax -- the key numbers its ramp from 1 to this
    elseif s.mode == "spotlight" then
        model.scale = "Brightest where you " .. (s.prof == "fishing" and "fish" or "gather") .. " most"
    else
        model.legend = {}
        for _, l in ipairs(list) do
            -- every material, even while one is chosen: the key's entries are its filter too
            if l.key ~= 0 and (#model.legend < 5 or l.key == s.leather) then
                model.legend[#model.legend + 1] = l
            end
        end
        model.legend[6] = nil -- the key has five places; a chosen sixth takes the fifth
        if #model.legend == 5 and s.leather ~= 0 then
            local seen = false
            for i = 1, 5 do if model.legend[i].key == s.leather then seen = true end end
            if not seen then
                for _, l in ipairs(list) do if l.key == s.leather then model.legend[5] = l end end
            end
        end
    end
    if FN.MapUI then FN.MapUI.Render(model) end
end

-- ------------------------------------------------------------
-- Hooks
-- ------------------------------------------------------------
local queued
function M.Refresh()
    if not overlay or queued then return end
    if not WorldMapFrame:IsShown() then return end
    queued = true
    -- once per frame at most: map changes, resizes and data can all arrive together
    C_Timer.After(0, function()
        queued = false
        if not WorldMapFrame:IsShown() then return end
        -- an error while drawing is said once in chat, so it shows even with Lua errors hidden
        local ok, err = pcall(Draw)
        if not ok then
            -- each different error once (the same one every redraw would flood the chat)
            M.lastError = tostring(err)
            M.errorsSaid = M.errorsSaid or {}
            if not M.errorsSaid[M.lastError] then
                M.errorsSaid[M.lastError] = true
                FN.Print("The map overlay hit an error: " .. M.lastError)
            end
        end
    end)
end
FN.OnData(M.Refresh)

-- learning a profession (or ranking one up) changes which tabs and rows show
local skillWatch = CreateFrame("Frame")
pcall(skillWatch.RegisterEvent, skillWatch, "SKILL_LINES_CHANGED")
skillWatch:SetScript("OnEvent", function() M.Refresh() end)

-- /fn debug: what the overlay is doing, for when it doesn't show
function M.Debug()
    local function Size(f)
        if not f then return "missing" end
        local w, h = f:GetSize()
        return string.format("%s %dx%d level %d %s", f:IsShown() and "shown" or "hidden", w or 0, h or 0,
            f:GetFrameLevel() or 0, f:GetFrameStrata() or "?")
    end
    FN.Print("Map debug: WorldMapFrame " .. (WorldMapFrame and Size(WorldMapFrame) or "missing")
        .. ", map " .. tostring(WorldMapFrame and WorldMapFrame:GetMapID()))
    FN.Print("  scroll area " .. Size(WorldMapFrame.ScrollContainer) .. "; map art "
        .. Size(WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()))
    local shownG, a = 0, 0
    for _, g in pairs(ghosts) do if g:IsShown() then shownG = shownG + 1; a = g.GetAlpha and g:GetAlpha() or 0 end end
    FN.Print(string.format("  map changes: %d, with badges on screen: %d, copies showing now: %d (alpha %.2f), map %s",
        M.ghostRuns or 0, M.ghostWith or 0, shownG, a, tostring(M.drawnMap)))
    FN.Print("  overlay " .. Size(overlay) .. "; control layer " .. tostring(M.strata))
    if FN.MapUI and FN.MapUI.Debug then FN.MapUI.Debug(Size) end
    local s = S()
    FN.Print(string.format("  settings: on %s, %s, %s; last error: %s", tostring(s.on), s.mode, s.show,
        M.lastError or "none"))
end

local function Init()
    if overlay or not WorldMapFrame or not WorldMapFrame.GetCanvas then
        M.initSkipped = true
        return
    end
    local canvas = WorldMapFrame:GetCanvas()
    overlay = CreateFrame("Frame", nil, canvas)
    overlay:SetAllPoints(canvas)
    overlay:SetFrameLevel(canvas:GetFrameLevel() + 5)
    overlay:EnableMouse(false)
    mute = overlay:CreateTexture(nil, "BACKGROUND")
    mute:SetAllPoints()
    mute:SetColorTexture(0.08, 0.06, 0.04, 0.18)

    if FN.MapUI then FN.MapUI.Init() end
    Layer()

    if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", M.Refresh) end
    WorldMapFrame:HookScript("OnShow", M.Refresh)
    overlay:SetScript("OnSizeChanged", M.Refresh)
    -- zooming scales the map under us: badges follow every frame; the dots and pins are drawn
    -- again once the zoom settles
    local lastK, still = nil, 0
    overlay:SetScript("OnUpdate", function(_, dt)
        local k = PinScale()
        if not lastK then lastK = k end
        if math.abs(k - lastK) > 0.002 * lastK then
            lastK = k
            still = 0
            for _, b in ipairs(badges) do
                if b:IsShown() and b.px then ApplyBadge(b, k) end
            end
            M.scaleDirty = true
        elseif M.scaleDirty then
            still = still + dt
            if still > 0.15 then
                M.scaleDirty = false
                M.Refresh()
            end
        end
    end)
    -- maximizing or shrinking the map changes its layer and its layout: redraw
    for _, name in ipairs({ "Maximize", "Minimize", "SetFrameStrata" }) do
        if type(WorldMapFrame[name]) == "function" then pcall(hooksecurefunc, WorldMapFrame, name, M.Refresh) end
    end

    local ev = CreateFrame("Frame")
    pcall(ev.RegisterEvent, ev, "GET_ITEM_INFO_RECEIVED") -- leather names arriving after the first draw
    ev:SetScript("OnEvent", M.Refresh)
end

table.insert(FN.onLogin, function()
    if WorldMapFrame then
        Init()
    else
        local wait = CreateFrame("Frame")
        wait:RegisterEvent("ADDON_LOADED")
        wait:SetScript("OnEvent", function(self, _, name)
            if name == "Blizzard_WorldMap" then
                Init()
                self:UnregisterEvent("ADDON_LOADED")
            end
        end)
    end
end)
