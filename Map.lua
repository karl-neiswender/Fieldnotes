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
local EDGE_FROM, EDGE_TO = 0.015, 0.2 -- the faintest heat fades in across this range: a soft edge
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
-- scale; Ember grows steadily darker, so it reads the same in grayscale and for color-blind players.
local SCHEMES = {
    thermal = { { 0, 0.16, 0.30, 0.85 }, { 0.3, 0.15, 0.70, 0.85 }, { 0.55, 0.45, 0.85, 0.30 },
        { 0.78, 1.00, 0.85, 0.15 }, { 1, 0.90, 0.18, 0.10 } },
    ember = { { 0, 0.953, 0.886, 0.651 }, { 0.3, 0.933, 0.702, 0.361 }, { 0.55, 0.871, 0.478, 0.227 },
        { 0.8, 0.702, 0.251, 0.169 }, { 1, 0.416, 0.110, 0.133 } },
}
M.SCHEME_ORDER = { "thermal", "ember" }
local RAMP = SCHEMES.thermal -- the scheme in use, set by Draw

-- Points colors, given to the map's leading leathers in order; each also differs in lightness.
-- The leading leather gets the strongest color: the pale one vanishes on light parchment.
local PALETTE = {
    { 0.890, 0.604, 0.231 }, { 0.953, 0.875, 0.659 }, { 0.247, 0.561, 0.541 }, { 0.541, 0.208, 0.149 },
}
local RUINED_COLOR = { 0.56, 0.54, 0.50 }
local OTHER_COLOR = { 0.80, 0.78, 0.74 }
local HIDE_COLOR = { 0.76, 0.62, 0.40 }
M.PALETTE, M.RUINED_COLOR, M.OTHER_COLOR = PALETTE, RUINED_COLOR, OTHER_COLOR -- the stats window's leather colors

local DEFAULTS = { on = true, mode = "heat", show = "account", leather = 0, colors = "thermal", when = 0, strength = 1, spread = 1 }
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
    if not SCHEMES[s.colors] then s.colors = DEFAULTS.colors end
    if type(s.strength) ~= "number" then s.strength = DEFAULTS.strength end
    s.strength = math.max(0.5, math.min(2.5, s.strength))
    -- spread: a multiplier on the size the data suggests (an old "balanced" word reads as 1)
    if type(s.spread) ~= "number" then s.spread = DEFAULTS.spread end
    s.spread = math.max(0.5, math.min(2.5, s.spread))
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
    return (GetItemInfo(id)) or "..."
end

local function CreatureName(npc)
    local c = FN.View().creatures[npc]
    return (c and c.name) or "Unknown creature"
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
local function Records(mapID, show, days)
    local since = (days and days > 0) and (time() - days * 86400) or nil
    local view = FN.View()
    -- Community: demo mode's sample layer and every imported share (Share.lua)
    local lists
    if show == "community" then
        lists = FN.CommunityLists("skinning", mapID)
    else
        lists = { view.events.skinning and view.events.skinning[mapID] or {} }
    end
    local me, out = FN.ViewChar(), {}
    for _, list in ipairs(lists) do
        for _, str in ipairs(list) do
            local r = FN.Decode(str)
            if r and r.x and r.y and (show ~= "me" or r.char == me) and (not since or r.time >= since) then
                out[#out + 1] = r
            end
        end
    end
    return out
end

-- the leather list for the controls: All, each leather most first, then hides and scraps
local function LeatherList(all)
    local counts, hides, ruined = {}, 0, 0
    for _, r in ipairs(all) do
        for id, n in pairs(r.items) do
            if id == RUINED then
                ruined = ruined + n
            elseif HIDES[id] then
                hides = hides + n
            else
                counts[id] = (counts[id] or 0) + n
            end
        end
    end
    local list, colorOf, rank = { { key = 0, label = "All leather" } }, { [RUINED] = RUINED_COLOR }, {}
    for i, id in ipairs(Top(counts, 12)) do
        local color = PALETTE[i] or OTHER_COLOR
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
    GameTooltip:SetText("Hot spot", ACCENT[1], ACCENT[2], ACCENT[3])
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
    p:SetScript("OnEnter", PinTooltip)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pins[i] = p
    return p
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
        local recs = Records(z.id, s.show, s.when)
        if #recs > 0 then
            perZone[#perZone + 1] = { zone = z, recs = recs }
            for _, r in ipairs(recs) do all[#all + 1] = r end
        end
    end
    local list, colorOf = LeatherList(all)
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
        b:ClearAllPoints()
        b:SetPoint("CENTER", overlay, "TOPLEFT", row.zone.x * w, -row.zone.y * h)
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
        for _, npc in ipairs(Top(row.who, 2)) do names[#names + 1] = CreatureName(npc) end
        for _, id in ipairs(Top(row.loot, 2)) do items[#items + 1] = ItemName(id) end
        b.zone = {
            id = row.zone.id, name = row.zone.name,
            summary = row.value .. (row.value == 1 and " skin" or " skins"),
            who = table.concat(names, ", "), loot = table.concat(items, "  ·  "),
        }
        b:Show()
    end
    ui.badgeCount = #rows

    model.skins = total
    model.zones = #rows
    model.bestZone = rows[1] and rows[1].zone.name
    model.scale = "Badge size and color: skins per zone. Click one to open it."
    if #rows == 0 then
        model.message = s.show == "community" and "Nothing shared on this map yet." or "Nothing skinned on this map yet."
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
    M.overlayLevel = level + 1
    overlay:SetFrameLevel(M.overlayLevel)
    for _, p in pairs(pins) do p:SetFrameLevel(M.overlayLevel + 10) end
end

-- the overlay fades as a whole when Fieldnotes is switched off or on (MapUI.lua animates it)
function M.SetOverlayAlpha(a)
    if overlay then overlay:SetAlpha(a) end
end

local function Draw()
    local s = S()
    Layer()
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
        place = mapID and C_Map.GetMapInfo(mapID) and C_Map.GetMapInfo(mapID).name,
    }
    M.model = model

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

    local all = mapID and Records(mapID, s.show, s.when) or {}
    local list, colorOf, rank = LeatherList(all)
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
        if #all > 0 then
            model.message = "Nothing here matches that leather."
        elseif s.when > 0 then
            model.message = string.format("Nothing skinned here in the last %d days.", s.when)
        elseif s.show == "community" then
            model.message = "Nothing shared for this zone yet."
        elseif s.show == "me" then
            model.message = "This character hasn't skinned here yet."
        else
            model.message = "Nothing skinned here yet."
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
            -- the faintest areas fade in smoothly, so the heat's edge dissolves into the map
            local e = math.min(1, (v - EDGE_FROM) / (EDGE_TO - EDGE_FROM))
            local edge = e * e * (3 - 2 * e)
            t:SetVertexColor(r, gg, b, math.min(0.95, (HEAT_ALPHA_MIN + HEAT_ALPHA_SPAN * v) * s.strength) * edge)
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
    else
        local step = math.max(1, math.ceil(#recs / MAX_DOTS))
        local dot = #recs > 800 and 5 or 7
        local n = 0
        for i = 1, #recs, step do
            local r = recs[i]
            n = n + 1
            local px, py = r.x / 1000 * w, -r.y / 1000 * h
            local ring = Pooled(rings, n, "ARTWORK", 1, CIRCLE)
            ring:ClearAllPoints()
            ring:SetPoint("CENTER", overlay, "TOPLEFT", px, py)
            ring:SetSize(dot + 3, dot + 3)
            ring:SetVertexColor(0.08, 0.055, 0.03, 0.95)
            local d = Pooled(dots, n, "ARTWORK", 2, CIRCLE)
            d:ClearAllPoints()
            d:SetPoint("CENTER", overlay, "TOPLEFT", px, py)
            d:SetSize(dot, dot)
            -- filtered to one leather, every dot is that leather
            local key = s.leather
            local c = (type(key) == "number" and key ~= 0 and colorOf[key])
                or (key == "hides" and HIDE_COLOR) or (key == "ruined" and RUINED_COLOR)
                or colorOf[MainItem(r, rank)] or OTHER_COLOR
            d:SetVertexColor(c[1], c[2], c[3], 1)
        end
    end

    -- hot spot pins: what lives in each, shown on hover
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
            for _, npc in ipairs(Top(who, 2)) do names[#names + 1] = CreatureName(npc) end
            for _, id in ipairs(Top(loot, 2)) do items[#items + 1] = ItemName(id) end
            local p = Pin(i)
            local pin = i == 1 and 16 or 12
            p:SetSize(pin, pin)
            p.dot:SetSize(pin / 2, pin / 2)
            p:ClearAllPoints()
            p:SetPoint("CENTER", overlay, "TOPLEFT", hx * w, -hy * h)
            p.info = {
                count = near, who = table.concat(names, ", "), loot = table.concat(items, "  ·  "),
                coords = string.format("%d, %d", math.floor(hx * 100 + 0.5), math.floor(hy * 100 + 0.5)),
            }
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
    model.topWho = topWho and CreatureName(topWho)
    model.topLoot = topLoot and ItemName(topLoot)
    if s.mode == "heat" then
        model.scale = string.format("Up to %d %s in one area", rawMax, rawMax == 1 and "skin" or "skins")
    elseif s.mode == "spotlight" then
        model.scale = "Brightest where you skin most"
    else
        model.legend = {}
        for _, l in ipairs(list) do
            if l.key ~= 0 and #model.legend < 5 and (s.leather == 0 or s.leather == l.key) then
                model.legend[#model.legend + 1] = l
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
            M.lastError = tostring(err)
            if not M.errorSaid then
                M.errorSaid = true
                FN.Print("The map overlay hit an error: " .. M.lastError)
            end
        end
    end)
end
FN.OnData(M.Refresh)

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
