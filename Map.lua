local ADDON, FN = ...

-- The world map overlay: a soft heat map of where you skin (or one dot per skin), drawn on the
-- map's canvas so it moves with the map, plus a slim control bar along the top, a small key in
-- the bottom-left corner and hot spot pins that explain themselves on hover.
--
-- Classic Era's map is small and cannot zoom, so the controls take as little of it as they can.
-- Everything is redrawn only when the map, a filter or the data changes; textures come from
-- pools and are reused. Panels, buttons, the switch and text share Forever Goal Tracker's look
-- (Style.lua); text uses the game's own font.

local M = {}
FN.Map = M

local COLS = 56 -- heat areas across a zone map; rows follow the map's shape
local MAX_DOTS = 2000 -- Points view thins out beyond this
local PINS = 3 -- hot spots marked on the map
local HEAT_ALPHA_MIN, HEAT_ALPHA_SPAN = 0.12, 0.5 -- one glow's strength, faintest to densest
local RUINED = 2934
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local BLOB = "Interface\\AddOns\\Fieldnotes\\Media\\blob"

local St = FN.Style
local C = St.C
local ACCENT = C.TITLE
local INK = { 0.106, 0.078, 0.047 }
local SOFT = C.INK2
local DIM = C.SUBTEXT
-- Heat color schemes, fewest to most. All but Thermal grow steadily darker, so they read the
-- same in grayscale and for color-blind players; Thermal is the familiar cool-to-warm scale.
local SCHEMES = {
    ember = { { 0, 0.953, 0.886, 0.651 }, { 0.3, 0.933, 0.702, 0.361 }, { 0.55, 0.871, 0.478, 0.227 },
        { 0.8, 0.702, 0.251, 0.169 }, { 1, 0.416, 0.110, 0.133 } },
    thermal = { { 0, 0.16, 0.30, 0.85 }, { 0.3, 0.15, 0.70, 0.85 }, { 0.55, 0.45, 0.85, 0.30 },
        { 0.78, 1.00, 0.85, 0.15 }, { 1, 0.90, 0.18, 0.10 } },
    frost = { { 0, 0.85, 0.93, 1.00 }, { 0.3, 0.61, 0.79, 1.00 }, { 0.55, 0.25, 0.55, 1.00 },
        { 0.8, 0.00, 0.30, 0.75 }, { 1, 0.04, 0.16, 0.40 } },
    verdant = { { 0, 0.97, 0.93, 0.65 }, { 0.3, 0.78, 0.86, 0.45 }, { 0.55, 0.45, 0.72, 0.35 },
        { 0.8, 0.18, 0.50, 0.28 }, { 1, 0.05, 0.28, 0.18 } },
    gold = { { 0, 1.00, 0.95, 0.75 }, { 0.3, 1.00, 0.86, 0.45 }, { 0.55, 0.95, 0.70, 0.15 },
        { 0.8, 0.75, 0.50, 0.05 }, { 1, 0.45, 0.28, 0.02 } },
}
local RAMP = SCHEMES.ember -- the scheme in use, set by Draw
-- what each area's heat counts
local HIDES = { [783] = true, [4232] = true, [4235] = true, [8169] = true, [8171] = true }
local UNITS = { skins = "skins", leather = "leather", hides = "hides" }
-- spread: each glow's size in areas, and smoothing passes
local SPREADS = { tight = { 1.9, 1 }, balanced = { 2.6, 2 }, broad = { 3.6, 3 } }
local SPOT_DARK = 0.5 -- Spotlight: one shade's darkness; overlapping shades build to about 0.75
-- Points colors, given to the map's leading leathers in order; each also differs in lightness.
-- The leading leather gets the strongest color: the pale one vanishes on light parchment.
local PALETTE = {
    { 0.890, 0.604, 0.231 }, { 0.953, 0.875, 0.659 }, { 0.247, 0.561, 0.541 }, { 0.541, 0.208, 0.149 },
}
local RUINED_COLOR = { 0.56, 0.54, 0.50 }
local OTHER_COLOR = { 0.80, 0.78, 0.74 }
M.PALETTE, M.RUINED_COLOR, M.OTHER_COLOR = PALETTE, RUINED_COLOR, OTHER_COLOR -- the stats window's leather colors

local SHOWS = {
    { key = "me", label = "Me", tip = "This character only" },
    { key = "account", label = "Account", tip = "Every character on this account" },
    { key = "community", label = "Community", tip = "Everyone who has shared, merged" },
}
local MODES = {
    { key = "heat", label = "Heat", tip = "A glow where you skin most" },
    { key = "points", label = "Points", tip = "One dot per skin, colored by its leather" },
    { key = "spotlight", label = "Spotlight", tip = "The map dims, except where you skin" },
}
local SETTINGS = {
    { key = "colors", label = "COLORS", opts = { { "ember", "Ember" }, { "thermal", "Thermal" }, { "frost", "Frost" },
        { "verdant", "Verdant" }, { "gold", "Gold" } } },
    { key = "heatBy", label = "HEAT BY", opts = { { "skins", "Skins" }, { "leather", "Leather" }, { "hides", "Hides" } } },
    { key = "when", label = "WHEN", opts = { { 0, "All time" }, { 30, "30 days" }, { 7, "7 days" } } },
    { key = "strength", label = "STRENGTH", opts = { { 0.65, "Subtle" }, { 1, "Normal" }, { 1.4, "Bold" } } },
    { key = "spread", label = "SPREAD", opts = { { "tight", "Tight" }, { "balanced", "Balanced" }, { "broad", "Broad" } } },
    { key = "thin", label = "THIN AREAS", opts = { { false, "Show" }, { true, "Hide" } } },
}
local DEFAULTS = { colors = "ember", heatBy = "skins", when = 0, strength = 1, spread = "balanced", thin = true }

local function S()
    local s = FN.db.settings.map
    if type(s) ~= "table" then
        s = {}
        FN.db.settings.map = s
    end
    if s.on == nil then s.on = true end
    s.mode = s.mode or "heat"
    s.show = s.show or "account"
    s.leather = s.leather or 0
    for k, v in pairs(DEFAULTS) do
        if s[k] == nil then s[k] = v end
    end
    if not SCHEMES[s.colors] then s.colors = DEFAULTS.colors end
    if not SPREADS[s.spread] then s.spread = DEFAULTS.spread end
    return s
end

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

local function Commas(n)
    local s = tostring(math.floor(n + 0.5))
    while true do
        local k
        s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        if k == 0 then return s end
    end
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
        return a < b
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

-- ------------------------------------------------------------
-- Widgets
-- ------------------------------------------------------------
-- an etched panel; slightly see-through, so the map still shows at its edges
local function Card(parent)
    local f = St.Frame("Frame", parent)
    St.Etch(f, St.STYLE.panel, 12, 0.94)
    f:EnableMouse(true) -- clicks on a panel never reach the map below
    return f
end

local Text = St.Text -- (parent, size, color)
local function Button(parent, onClick) return St.ChoiceButton(parent, onClick) end
local function SetSelected(b, on) b:SetChosen(on) end

-- etched buttons side by side, 3px apart; returns their total width
local function Segments(parent, buttons, x)
    local bx = x
    for i, b in ipairs(buttons) do
        b:SetSize(math.ceil(b.text:GetStringWidth()) + 18, 22)
        b:ClearAllPoints()
        b:SetPoint("LEFT", parent, "LEFT", bx, 0)
        bx = bx + b:GetWidth() + (i < #buttons and 3 or 0)
    end
    return bx - x
end

-- ------------------------------------------------------------
-- Frames (made once, the first time the map opens)
-- ------------------------------------------------------------
local overlay, mute, hud, bar, key, menu
local blobs, dots, rings, pins, shades, badges = {}, {}, {}, {}, {}, {}
local Layer -- picks the overlay's layer (above Draw)
local modeButtons, showButtons, menuRows, legendRows, rampBar = {}, {}, {}, {}, {}
local ui = {}
M.ui = ui -- read by tools/check.py

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

local function CloseMenu()
    if menu then menu:Hide() end
end

local function BuildBar()
    bar = Card(hud)
    bar:SetPoint("TOPLEFT", hud, "TOPLEFT", 10, -10)
    bar:SetHeight(34)

    -- the name and on/off switch
    ui.header = CreateFrame("Button", nil, bar)
    ui.header:SetPoint("LEFT", 0, 0)
    ui.header:SetHeight(34)
    ui.header:SetScript("OnClick", function()
        S().on = not S().on
        CloseMenu()
        M.Refresh()
    end)
    ui.header:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Fieldnotes", ACCENT[1], ACCENT[2], ACCENT[3])
        GameTooltip:AddLine("Click to show or hide your skinning notes on the map.", 1, 1, 1, true)
        GameTooltip:Show()
        ui.toggle:SetOn(S().on, true)
    end)
    ui.header:SetScript("OnLeave", function()
        GameTooltip:Hide()
        ui.toggle:SetOn(S().on)
    end)
    ui.title = St.Title(ui.header, 13)
    ui.title:SetPoint("LEFT", 10, 0)
    ui.title:SetText("Fieldnotes")
    ui.toggle = St.Toggle(ui.header)
    ui.toggle:SetPoint("LEFT", ui.title, "RIGHT", 10, 0)

    for i, m in ipairs(MODES) do
        local b = Button(bar, function()
            S().mode = m.key
            CloseMenu()
            M.Refresh()
        end)
        b.text:SetText(m.label)
        b.key = m.key
        b.tip = m.tip
        modeButtons[i] = b
    end
    for i, sh in ipairs(SHOWS) do
        local b = Button(bar, function()
            S().show = sh.key
            CloseMenu()
            M.Refresh()
        end)
        b.text:SetText(sh.label)
        b.key = sh.key
        b.tip = sh.tip
        showButtons[i] = b
    end

    -- the settings: a gear that opens the map's options and the leather filter
    ui.gear = St.IconButton(bar, "gear-white", 16, function()
        if menu:IsShown() then menu:Hide() else menu:Show() end
        M.Refresh()
    end)
    local function GearTint(self, hover)
        local c = (hover or menu:IsShown()) and C.TITLE or (self.active and C.GOLD2 or C.INK2)
        self.icon:SetVertexColor(c[1], c[2], c[3])
    end
    ui.gear.Tint = GearTint
    ui.gear:SetScript("OnEnter", function(self)
        GearTint(self, true)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Map settings", ACCENT[1], ACCENT[2], ACCENT[3])
        GameTooltip:AddLine("Leather, colors, what the heat counts, time and more.", 1, 1, 1, true)
        if self.active then GameTooltip:AddLine("Some settings are changed from their defaults.", C.INK2[1], C.INK2[2], C.INK2[3], true) end
        GameTooltip:Show()
    end)
    ui.gear:SetScript("OnLeave", function(self)
        GearTint(self)
        GameTooltip:Hide()
    end)

    ui.dividers = {}
    for i = 1, 3 do
        local d = bar:CreateTexture(nil, "ARTWORK")
        d:SetColorTexture(0.33, 0.29, 0.20, 1) -- the panel's own edge color
        d:SetSize(1, 18)
        ui.dividers[i] = d
    end

    menu = Card(hud)
    menu:SetFrameLevel(bar:GetFrameLevel() + 10)
    menu:SetWidth(320)
    menu:Hide()

    -- one row of choices per setting; the leather row is filled per map
    ui.sections = {}
    for _, spec in ipairs(SETTINGS) do
        local sec = { spec = spec, buttons = {} }
        sec.label = Text(menu, 10, C.SUBTEXT)
        sec.label:SetText(spec.label)
        for i, opt in ipairs(spec.opts) do
            local b = Button(menu, function()
                S()[spec.key] = opt[1]
                M.Refresh()
            end)
            b.text:SetText(opt[2])
            b.value = opt[1]
            sec.buttons[i] = b
        end
        ui.sections[#ui.sections + 1] = sec
    end
    ui.leatherLabel = Text(menu, 10, C.SUBTEXT)
    ui.leatherLabel:SetText("LEATHER")
    ui.preview = {}
    for i = 1, 37 do
        local t = menu:CreateTexture(nil, "ARTWORK")
        t:SetTexture(WHITE)
        t:SetSize(8, 6)
        ui.preview[i] = t
    end
    ui.reset = Button(menu, function()
        local st = S()
        for k, v in pairs(DEFAULTS) do st[k] = v end
        st.leather = 0
        M.Refresh()
    end)
    ui.reset.text:SetText("Reset")
end

local function LeatherChip(i)
    local b = menuRows[i]
    if b then return b end
    b = Button(menu, function(self)
        S().leather = self.itemID
        M.Refresh()
    end)
    b.swatch = b:CreateTexture(nil, "ARTWORK")
    b.swatch:SetSize(8, 8)
    b.swatch:SetTexture(CIRCLE)
    b.swatch:SetPoint("LEFT", 9, 0)
    menuRows[i] = b
    return b
end

-- lay the bar out left to right; with the overlay off only the name and switch remain
local function LayoutBar(on)
    local x = math.ceil(ui.title:GetStringWidth()) + 10 + 10 + 36 + 10
    ui.header:SetWidth(x)
    for _, d in ipairs(ui.dividers) do d:SetShown(on) end
    for _, b in ipairs(modeButtons) do b:SetShown(on) end
    for _, b in ipairs(showButtons) do b:SetShown(on) end
    ui.gear:SetShown(on)
    if not on then
        bar:SetWidth(x)
        return
    end
    local function Divider(i)
        ui.dividers[i]:ClearAllPoints()
        ui.dividers[i]:SetPoint("LEFT", bar, "LEFT", x + 4, 0)
        x = x + 10
    end
    local s = S()
    for _, b in ipairs(modeButtons) do SetSelected(b, b.key == s.mode) end
    for _, b in ipairs(showButtons) do SetSelected(b, b.key == s.show) end
    Divider(1)
    x = x + Segments(bar, modeButtons, x) + 6
    Divider(2)
    x = x + Segments(bar, showButtons, x) + 6
    Divider(3)
    ui.gear:ClearAllPoints()
    ui.gear:SetPoint("LEFT", bar, "LEFT", x + 2, 0)
    x = x + 2 + 16 + 12
    bar:SetWidth(x)
    local active = s.leather ~= 0
    for k, v in pairs(DEFAULTS) do
        if s[k] ~= v then active = true end
    end
    ui.gear.active = active
    ui.gear:Tint()
end

local function BuildKey()
    key = Card(hud)
    key:SetPoint("BOTTOMLEFT", hud, "BOTTOMLEFT", 10, 10)
    ui.line = Text(key, 11, C.TEXT)
    ui.line:SetPoint("TOPLEFT", 10, -9)
    ui.fewer = Text(key, 10, C.SUBTEXT)
    ui.fewer:SetText("Fewer")
    for i = 1, 36 do
        local t = key:CreateTexture(nil, "ARTWORK")
        t:SetSize(4, 8)
        t:SetColorTexture(Ramp((i - 1) / 35))
        rampBar[i] = t
    end
    ui.more = Text(key, 10, C.SUBTEXT)
    ui.more:SetText("More")
    ui.scale = Text(key, 10, C.SUBTEXT)
    ui.demo = Text(key, 10, C.SUBTEXT)
    ui.demo:SetText("Sample data  ·  /fn demo off to hide it")
end

local function LegendRow(i)
    local row = legendRows[i]
    if row then return row end
    row = {}
    row.dot = key:CreateTexture(nil, "ARTWORK")
    row.dot:SetSize(8, 8)
    row.dot:SetTexture(CIRCLE)
    row.text = Text(key, 11, SOFT)
    row.text:SetPoint("LEFT", row.dot, "RIGHT", 5, 0)
    legendRows[i] = row
    return row
end

local function PinTooltip(self)
    local p = self.info
    if not p then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Hot spot", ACCENT[1], ACCENT[2], ACCENT[3])
    GameTooltip:AddLine(p.count .. " skins here", 1, 1, 1)
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

-- how much one skin adds to its area: itself, its leather, or its hides
local function Weight(r, by)
    if by == "skins" then return 1 end
    local n = 0
    for id, k in pairs(r.items) do
        if by == "hides" and HIDES[id] then n = n + k end
        if by == "leather" and id ~= RUINED and not HIDES[id] then n = n + k end
    end
    return n
end

-- returns the smoothed grid, its peak, and the most any one area holds before smoothing
local function HeatGrid(recs, cols, rows, by, passes)
    local g = {}
    for i = 1, cols * rows do g[i] = 0 end
    for _, r in ipairs(recs) do
        local c = math.min(cols - 1, math.floor(r.x / 1000 * cols))
        local rr = math.min(rows - 1, math.floor(r.y / 1000 * rows))
        local i = rr * cols + c + 1
        g[i] = g[i] + Weight(r, by)
    end
    local rawMax = 0
    for i = 1, #g do
        if g[i] > rawMax then rawMax = g[i] end
    end
    -- smooth with a 3x3 kernel so the heat reads as areas, not specks
    for _ = 1, passes or 2 do
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
            if math.abs(p.c - c) < 6 and math.abs(p.r - r) < 6 then far = false end
        end
        if far then out[#out + 1] = { c = c, r = r } end
        if #out >= PINS then break end
    end
    return out
end

-- ------------------------------------------------------------
-- Drawing
-- ------------------------------------------------------------
local function SetSwitch(on) ui.toggle:SetOn(on) end

-- the settings panel, top to bottom: leather chips, then a row of choices per setting
local function LayoutSettings(ids, colorOf)
    local s = S()
    local inner = 296
    local y = -12
    local function Row(buttons, chosen)
        local x = 0
        for _, b in ipairs(buttons) do
            local w = math.ceil(b.text:GetStringWidth()) + (b.swatch and 30 or 18)
            if x > 0 and x + w > inner then x, y = 0, y - 25 end
            b:SetSize(w, 22)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", menu, "TOPLEFT", 12 + x, y)
            if b.swatch then
                b.text:ClearAllPoints()
                b.text:SetPoint("LEFT", 22, 0)
            end
            SetSelected(b, chosen(b))
            b:Show()
            x = x + w + 3
        end
        y = y - 22 - 12
    end
    local function Label(fs)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", menu, "TOPLEFT", 12, y)
        y = y - 14
    end

    Label(ui.leatherLabel)
    local chips = {}
    for i, id in ipairs(ids) do
        local b = LeatherChip(i)
        b.itemID = id
        b.text:SetText(id == 0 and "All" or ItemName(id))
        local c = colorOf[id]
        b.swatch:SetShown(c ~= nil and id ~= 0)
        if c then b.swatch:SetVertexColor(c[1], c[2], c[3]) end
        chips[i] = b
    end
    HidePool(menuRows, #ids + 1)
    Row(chips, function(b) return b.itemID == s.leather end)

    for _, sec in ipairs(ui.sections) do
        Label(sec.label)
        Row(sec.buttons, function(b) return s[sec.spec.key] == b.value end)
        if sec.spec.key == "colors" then
            -- the chosen scheme, fewest to most
            y = y + 6
            for i, t in ipairs(ui.preview) do
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", menu, "TOPLEFT", 12 + (i - 1) * 8, y)
                t:SetVertexColor(Ramp((i - 1) / (#ui.preview - 1)))
            end
            y = y - 6 - 12
        end
    end
    ui.reset:SetSize(math.ceil(ui.reset.text:GetStringWidth()) + 18, 22)
    ui.reset:ClearAllPoints()
    ui.reset:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -12, y + 34) -- beside the last row
    SetSelected(ui.reset, false)
    menu:SetHeight(-y)
    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", ui.gear, "BOTTOMRIGHT", 14, -14)
end

-- the key: one line of words, then the heat scale or the dot colors, then the demo note
-- scale: the words under the heat scale ("Up to 54 skins in one area"), or Spotlight's note
local function LayoutKey(line, mode, legendIDs, colorOf, inDemo, scale)
    ui.line:SetText(line)
    local width = math.max(200, ui.line:GetStringWidth() + 20)
    local y = -26
    local heat = mode == "heat" and legendIDs ~= nil
    ui.scale:SetShown(scale ~= nil and legendIDs ~= nil)
    for _, t in ipairs(rampBar) do t:SetShown(heat) end
    ui.fewer:SetShown(heat)
    ui.more:SetShown(heat)
    for _, row in ipairs(legendRows) do
        row.dot:Hide()
        row.text:Hide()
    end
    if heat then
        ui.fewer:ClearAllPoints()
        ui.fewer:SetPoint("TOPLEFT", key, "TOPLEFT", 10, y)
        local bx = 10 + ui.fewer:GetStringWidth() + 6
        for i, t in ipairs(rampBar) do
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", key, "TOPLEFT", bx + (i - 1) * 4, y - 2)
        end
        for i, t in ipairs(rampBar) do t:SetColorTexture(Ramp((i - 1) / (#rampBar - 1))) end
        ui.more:ClearAllPoints()
        ui.more:SetPoint("TOPLEFT", key, "TOPLEFT", bx + #rampBar * 4 + 6, y)
        width = math.max(width, bx + #rampBar * 4 + 6 + ui.more:GetStringWidth() + 10)
        y = y - 16
    end
    if scale and legendIDs then
        ui.scale:SetText(scale)
        ui.scale:ClearAllPoints()
        ui.scale:SetPoint("TOPLEFT", key, "TOPLEFT", 10, y)
        width = math.max(width, ui.scale:GetStringWidth() + 20)
        y = y - 16
    end
    if heat or mode == "spotlight" then
        -- the heat scale and Spotlight's note are placed above
    elseif legendIDs then
        local x = 10
        for i, id in ipairs(legendIDs) do
            local row = LegendRow(i)
            local c = colorOf[id] or OTHER_COLOR
            row.dot:SetVertexColor(c[1], c[2], c[3])
            row.text:SetText(ItemName(id))
            local w = 13 + row.text:GetStringWidth() + 12
            if x > 10 and x + w > width + 40 then
                x, y = 10, y - 16
            end
            row.dot:ClearAllPoints()
            row.dot:SetPoint("TOPLEFT", key, "TOPLEFT", x, y - 2)
            row.dot:Show()
            row.text:Show()
            x = x + w
            width = math.max(width, x)
        end
        y = y - 16
    end
    ui.demo:SetShown(inDemo)
    if inDemo then
        ui.demo:ClearAllPoints()
        ui.demo:SetPoint("TOPLEFT", key, "TOPLEFT", 10, y - 2)
        width = math.max(width, ui.demo:GetStringWidth() + 20)
        y = y - 16
    end
    key:SetSize(width, -y + 6)
    key:ClearAllPoints()
    key:SetPoint(ui.keyCorner or "BOTTOMLEFT", hud, ui.keyCorner or "BOTTOMLEFT",
        ui.keyCorner == "BOTTOMRIGHT" and -10 or 10, 10)
    key:Show()
end

-- ------------------------------------------------------------
-- Continent and world maps: one badge per zone
-- ------------------------------------------------------------
-- Each zone you have notes for gets a badge at its centre, sized and coloured by how much it
-- gave (whatever Heat by counts). Hover for the zone's numbers; click to open it.

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
    -- cover a badge's number; the bar and key sit higher still (see Init)
    b:SetFrameStrata(M.strata or "HIGH")
    b.ring = b:CreateTexture(nil, "ARTWORK", nil, 1)
    b.ring:SetAllPoints()
    b.ring:SetTexture(CIRCLE)
    b.ring:SetVertexColor(0.08, 0.055, 0.03, 0.95)
    b.disc = b:CreateTexture(nil, "ARTWORK", nil, 2)
    b.disc:SetPoint("TOPLEFT", 2, -2)
    b.disc:SetPoint("BOTTOMRIGHT", -2, 2)
    b.disc:SetTexture(CIRCLE)
    b.label = Text(b, 11, C.TEXT)
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

local function DrawContinent(s, mapID, zoneType, inDemo)
    local zones = ZonesUnder(mapID, zoneType)
    -- every zone's skins once, for the leather list and the badges
    local perZone, itemCounts = {}, {}
    for _, z in ipairs(zones) do
        local recs = Records(z.id, s.show, s.when)
        if #recs > 0 then
            perZone[#perZone + 1] = { zone = z, recs = recs }
            for _, r in ipairs(recs) do
                for id, n in pairs(r.items) do
                    if id ~= RUINED then itemCounts[id] = (itemCounts[id] or 0) + n end
                end
            end
        end
    end
    local leading = Top(itemCounts, 6)
    local colorOf = { [RUINED] = RUINED_COLOR }
    for i, id in ipairs(leading) do colorOf[id] = PALETTE[i] or OTHER_COLOR end
    if s.leather ~= 0 and not itemCounts[s.leather] then s.leather = 0 end
    local menuIDs = { 0 }
    for _, id in ipairs(leading) do menuIDs[#menuIDs + 1] = id end
    if menu:IsShown() then LayoutSettings(menuIDs, colorOf) end
    LayoutBar(true)

    -- each zone's total of whatever Heat by counts
    local rows, max, total, skins = {}, 0, 0, 0
    for _, pz in ipairs(perZone) do
        local value, n, who, loot = 0, 0, {}, {}
        for _, r in ipairs(pz.recs) do
            local wgt = Weight(r, s.heatBy)
            if (s.leather == 0 or r.items[s.leather]) and wgt > 0 then
                value, n = value + wgt, n + 1
                if r.npc > 0 then who[r.npc] = (who[r.npc] or 0) + 1 end
                for id, k in pairs(r.items) do
                    if id ~= RUINED then loot[id] = (loot[id] or 0) + k end
                end
            end
        end
        if value > 0 then
            rows[#rows + 1] = { zone = pz.zone, value = value, skins = n, who = who, loot = loot }
            max = math.max(max, value)
            total, skins = total + value, skins + n
        end
    end
    -- biggest first, so smaller badges sit on top where they overlap
    table.sort(rows, function(a, b) return a.value > b.value end)

    local w, h = overlay:GetSize()
    local unit = UNITS[s.heatBy]
    for i, row in ipairs(rows) do
        local v = row.value / max
        local b = Badge(i)
        local size = 22 + 26 * math.sqrt(v) -- area grows with the value
        b:SetSize(size, size)
        b:SetFrameLevel(100 + i)
        b:ClearAllPoints()
        b:SetPoint("CENTER", overlay, "TOPLEFT", row.zone.x * w, -row.zone.y * h)
        b.disc:SetVertexColor(Ramp(0.15 + 0.85 * v))
        b.label:SetText(Short(row.value))
        -- dark numbers on the pale end of the scale, light ones on the dark end
        local lr, lg, lb = Ramp(0.15 + 0.85 * v)
        local light = 0.299 * lr + 0.587 * lg + 0.114 * lb
        if light > 0.6 then
            b.label:SetTextColor(INK[1], INK[2], INK[3])
            b.label:SetShadowColor(1, 1, 1, 0.25)
        else
            b.label:SetTextColor(1, 1, 1)
            b.label:SetShadowColor(0, 0, 0, 1)
        end
        local names, items = {}, {}
        for _, npc in ipairs(Top(row.who, 2)) do names[#names + 1] = CreatureName(npc) end
        for _, id in ipairs(Top(row.loot, 2)) do items[#items + 1] = ItemName(id) end
        local summary = row.skins .. (row.skins == 1 and " skin" or " skins")
        if s.heatBy ~= "skins" then summary = string.format("%d %s from %s", row.value, unit, summary) end
        b.zone = {
            id = row.zone.id, name = row.zone.name, summary = summary,
            who = table.concat(names, ", "), loot = table.concat(items, "  ·  "),
        }
        b:Show()
    end
    ui.badgeCount = #rows

    if #rows == 0 then
        LayoutKey(s.show == "community" and "Nothing shared on this map yet." or "Nothing skinned on this map yet.",
            "heat", nil, colorOf, inDemo)
        return
    end
    -- the key goes in whichever bottom corner covers fewer badges (the sea, usually)
    local left, right = 0, 0
    for _, row in ipairs(rows) do
        if row.zone.y > 0.6 then
            if row.zone.x < 0.5 then left = left + 1 else right = right + 1 end
        end
    end
    ui.keyCorner = right < left and "BOTTOMRIGHT" or "BOTTOMLEFT"
    local line = string.format("%s %s in %d zone%s  ·  most: %s", Commas(total), unit, #rows,
        #rows == 1 and "" or "s", rows[1].zone.name)
    LayoutKey(line, "heat", {}, colorOf, inDemo, "Badge size and color: " .. unit .. " per zone  ·  click to open")
end

-- The layer above the map's own, for the continent badges and, over them, the bar, key and
-- settings. The map changes layer when it is maximized or made small again, and takes every
-- frame on it along, so this is picked again on every redraw (once, at the first open, left the
-- bar behind a maximized map).
local ORDER = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG" }
Layer = function()
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
    hud:SetFrameStrata(M.strata)
    hud:SetFrameLevel(1000)
    menu:SetFrameLevel(bar:GetFrameLevel() + 10)
    for _, b in ipairs(badges) do b:SetFrameStrata(M.strata) end
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
    ui.keyCorner = "BOTTOMLEFT" -- zone maps keep the key bottom left; continents choose
    SetSwitch(s.on)
    RAMP = SCHEMES[s.colors]

    if not s.on then
        LayoutBar(false)
        CloseMenu()
        mute:Hide()
        key:Hide()
        return
    end
    mute:SetShown(s.mode ~= "spotlight")
    local inDemo = FN.View() ~= FN.db

    local mapID = WorldMapFrame:GetMapID()
    local info = mapID and C_Map.GetMapInfo(mapID)
    local zoneType = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
    if info and info.mapType and info.mapType < zoneType then
        DrawContinent(s, mapID, zoneType, inDemo)
        return
    end
    local all = mapID and Records(mapID, s.show, s.when) or {}

    -- this map's leathers, most first; colors go to the leading four
    local itemCounts = {}
    for _, r in ipairs(all) do
        for id, n in pairs(r.items) do
            if id ~= RUINED then itemCounts[id] = (itemCounts[id] or 0) + n end
        end
    end
    local leading = Top(itemCounts, 6)
    local colorOf, rank = { [RUINED] = RUINED_COLOR }, {}
    for i, id in ipairs(leading) do
        colorOf[id] = PALETTE[i] or OTHER_COLOR
        rank[id] = i
    end
    if s.leather ~= 0 and not itemCounts[s.leather] then s.leather = 0 end

    local menuIDs = { 0 }
    for _, id in ipairs(leading) do menuIDs[#menuIDs + 1] = id end
    if menu:IsShown() then LayoutSettings(menuIDs, colorOf) end
    LayoutBar(true)

    -- the chosen leather, and only skins that count toward the heat (Heat by Hides: skins with hides)
    local recs = all
    if s.leather ~= 0 or s.heatBy ~= "skins" then
        recs = {}
        for _, r in ipairs(all) do
            if (s.leather == 0 or r.items[s.leather]) and Weight(r, s.heatBy) > 0 then recs[#recs + 1] = r end
        end
    end

    if #recs == 0 then
        local msg = "Nothing skinned here yet."
        if #all > 0 then
            msg = "Nothing here matches the leather or Heat by setting."
        elseif s.when > 0 then
            msg = string.format("Nothing skinned here in the last %d days.", s.when)
        elseif s.show == "community" then
            msg = "Nothing shared for this zone yet."
        elseif s.show == "me" then
            msg = "This character has not skinned here yet."
        end
        LayoutKey(msg, s.mode, nil, colorOf, inDemo)
        return
    end

    local w, h = overlay:GetSize()
    if not w or w <= 0 or not h or h <= 0 then return end
    local cols = COLS
    local rows = math.max(1, math.floor(cols * h / w + 0.5))
    local cw, ch = w / cols, h / rows
    local spread = SPREADS[s.spread]
    local g, max, rawMax = HeatGrid(recs, cols, rows, s.heatBy, spread[2])
    local size = spread[1] * math.max(cw, ch)
    -- an area shows when it holds enough to matter: thin areas (about one skin's worth) can be
    -- hidden; hides are rare, so any area with one counts
    local thin = ({ skins = 0.35, leather = 0.7, hides = 0.12 })[s.heatBy]
    local function Counts(i)
        return g[i] / max >= 0.04 and (not s.thin or g[i] >= thin)
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
            t:SetVertexColor(r, gg, b, math.min(0.95, (HEAT_ALPHA_MIN + HEAT_ALPHA_SPAN * v) * s.strength))
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
                local a = SPOT_DARK * math.min(1.2, s.strength) * (1 - math.min(1, v * 1.8)) ^ 1.5
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
        local size = #recs > 800 and 5 or 7
        local n = 0
        for i = 1, #recs, step do
            local r = recs[i]
            n = n + 1
            local px, py = r.x / 1000 * w, -r.y / 1000 * h
            local ring = Pooled(rings, n, "ARTWORK", 1, CIRCLE)
            ring:ClearAllPoints()
            ring:SetPoint("CENTER", overlay, "TOPLEFT", px, py)
            ring:SetSize(size + 3, size + 3)
            ring:SetVertexColor(0.08, 0.055, 0.03, 0.95)
            local dot = Pooled(dots, n, "ARTWORK", 2, CIRCLE)
            dot:ClearAllPoints()
            dot:SetPoint("CENTER", overlay, "TOPLEFT", px, py)
            dot:SetSize(size, size)
            -- filtered to one leather, every dot is that leather
            local c = colorOf[s.leather ~= 0 and s.leather or MainItem(r, rank)] or OTHER_COLOR
            dot:SetVertexColor(c[1], c[2], c[3], 1)
        end
    end

    -- hot spot pins: what lives in each, shown on hover
    for i, peak in ipairs(Peaks(g, max, cols)) do
        local hx, hy = (peak.c + 0.5) / cols, (peak.r + 0.5) / rows
        local near, who, loot = 0, {}, {}
        for _, r in ipairs(recs) do
            if math.abs(r.x / 1000 - hx) < 2.5 / cols and math.abs(r.y / 1000 - hy) < 2.5 / rows then
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
            local size = i == 1 and 16 or 12
            p:SetSize(size, size)
            p.dot:SetSize(size / 2, size / 2)
            p:ClearAllPoints()
            p:SetPoint("CENTER", overlay, "TOPLEFT", hx * w, -hy * h)
            p.info = {
                count = near, who = table.concat(names, ", "), loot = table.concat(items, "  ·  "),
                coords = string.format("%d, %d", math.floor(hx * 100 + 0.5), math.floor(hy * 100 + 0.5)),
            }
            p:Show()
        end
    end

    -- the key's one line: how many, and what leads
    local whoAll = {}
    for _, r in ipairs(recs) do
        if r.npc > 0 then whoAll[r.npc] = (whoAll[r.npc] or 0) + 1 end
    end
    local parts = { #recs .. (#recs == 1 and " skin" or " skins") }
    local topWho = Top(whoAll, 1)[1]
    if topWho then parts[#parts + 1] = CreatureName(topWho) end
    local topLoot = s.leather ~= 0 and s.leather or leading[1]
    if topLoot then parts[#parts + 1] = ItemName(topLoot) end
    local legendIDs, scale = {}, nil
    if s.mode == "heat" then
        scale = string.format("Up to %d %s in one area", rawMax, UNITS[s.heatBy])
    elseif s.mode == "spotlight" then
        scale = "Brightest where you skin most"
    end
    if s.mode == "points" and s.leather ~= 0 then
        legendIDs[1] = s.leather
    elseif s.mode == "points" then
        for _, id in ipairs(leading) do
            if #legendIDs < 4 then legendIDs[#legendIDs + 1] = id end
        end
        legendIDs[#legendIDs + 1] = RUINED
    end
    LayoutKey(table.concat(parts, "  ·  "), s.mode, legendIDs, colorOf, inDemo, scale)
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
    FN.Print("  overlay " .. Size(overlay) .. "; bar layer " .. tostring(M.strata))
    FN.Print("  hud " .. Size(hud) .. "; bar " .. Size(bar) .. "; key " .. Size(key))
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
    local container = WorldMapFrame.ScrollContainer or WorldMapFrame

    overlay = CreateFrame("Frame", nil, canvas)
    overlay:SetAllPoints(canvas)
    overlay:SetFrameLevel(canvas:GetFrameLevel() + 5)
    overlay:EnableMouse(false)
    mute = overlay:CreateTexture(nil, "BACKGROUND")
    mute:SetAllPoints()
    mute:SetColorTexture(0.08, 0.06, 0.04, 0.18)

    hud = CreateFrame("Frame", nil, container)
    hud:SetAllPoints(container)
    hud:EnableMouse(false)

    BuildBar()
    BuildKey()
    Layer()

    if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", M.Refresh) end
    WorldMapFrame:HookScript("OnShow", M.Refresh)
    WorldMapFrame:HookScript("OnHide", CloseMenu)
    menu:SetScript("OnHide", function() if ui.gear then ui.gear:Tint() end end)
    overlay:SetScript("OnSizeChanged", M.Refresh)
    -- maximizing or shrinking the map changes its layer: redraw so the bar follows
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
