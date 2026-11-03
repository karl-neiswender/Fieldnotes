local ADDON, FN = ...

-- The world map overlay: a soft heat map of where you skin (or one dot per skin), drawn on the
-- map's canvas so it moves with the map, plus a slim control bar along the top, a small key in
-- the bottom-left corner and hot spot pins that explain themselves on hover.
--
-- Classic Era's map is small and cannot zoom, so the controls take as little of it as they can.
-- Everything is redrawn only when the map, a filter or the data changes; textures come from
-- pools and are reused. All text uses the game's own font objects.

local M = {}
FN.Map = M

local COLS = 56 -- heat areas across a zone map; rows follow the map's shape
local MAX_DOTS = 2000 -- Points view thins out beyond this
local PINS = 3 -- hot spots marked on the map
local BLOB_SIZE = 2.6 -- each heat area's soft glow, in areas, so neighbours melt together
local HEAT_ALPHA_MIN, HEAT_ALPHA_SPAN = 0.12, 0.5 -- one glow's strength, faintest to densest
local RUINED = 2934
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local BLOB = "Interface\\AddOns\\Fieldnotes\\Media\\blob"
local ARROW = "Interface\\Buttons\\Arrow-Down-Up"

local ACCENT = { 0.914, 0.698, 0.396 }
local INK = { 0.106, 0.078, 0.047 }
local SOFT = { 0.85, 0.80, 0.70 }
local DIM = { 0.66, 0.60, 0.50 }
local RAMP = {
    { 0, 0.953, 0.886, 0.651 }, { 0.3, 0.933, 0.702, 0.361 }, { 0.55, 0.871, 0.478, 0.227 },
    { 0.8, 0.702, 0.251, 0.169 }, { 1, 0.416, 0.110, 0.133 },
}
-- Points colors, given to the map's leading leathers in order; each also differs in lightness.
-- The leading leather gets the strongest color: the pale one vanishes on light parchment.
local PALETTE = {
    { 0.890, 0.604, 0.231 }, { 0.953, 0.875, 0.659 }, { 0.247, 0.561, 0.541 }, { 0.541, 0.208, 0.149 },
}
local RUINED_COLOR = { 0.56, 0.54, 0.50 }
local OTHER_COLOR = { 0.80, 0.78, 0.74 }

local SHOWS = {
    { key = "me", label = "Me", tip = "This character only" },
    { key = "account", label = "Account", tip = "Every character on this account" },
    { key = "community", label = "Community", tip = "Everyone who has shared, merged" },
}
local MODES = { { key = "heat", label = "Heat" }, { key = "points", label = "Points" } }

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
local function Border(frame)
    local edges = {}
    for i = 1, 4 do
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.94, 0.82, 0.59, 0.22)
        edges[i] = t
    end
    edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)
end

-- a glass panel: see-through dark fill, a faint light falling from the top edge, a warm border
local function Card(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.055, 0.042, 0.03, 0.74)
    local sheen = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    sheen:SetPoint("TOPLEFT", 1, -1)
    sheen:SetPoint("TOPRIGHT", -1, -1)
    sheen:SetHeight(14)
    sheen:SetColorTexture(1, 1, 1, 1)
    if CreateColor and sheen.SetGradient and pcall(sheen.SetGradient, sheen, "VERTICAL",
            CreateColor(1, 0.95, 0.85, 0), CreateColor(1, 0.95, 0.85, 0.07)) then
        sheen:Show()
    else
        sheen:Hide()
    end
    Border(f)
    f:EnableMouse(true) -- clicks on a panel never reach the map below
    return f
end

local function Text(parent, font, c)
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    if c then fs:SetTextColor(c[1], c[2], c[3]) end
    fs:SetJustifyH("LEFT")
    return fs
end

local function SetSelected(b, on)
    b.selected = on
    if on then
        b.bg:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
        b.text:SetTextColor(INK[1], INK[2], INK[3])
    else
        b.bg:SetColorTexture(1, 0.94, 0.82, 0)
        b.text:SetTextColor(SOFT[1], SOFT[2], SOFT[3])
    end
end

local function Button(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b.bg = b:CreateTexture(nil, "BACKGROUND", nil, 2)
    b.bg:SetAllPoints()
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        if not self.selected then self.bg:SetColorTexture(1, 0.94, 0.82, 0.12) end
        if self.tip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(self.tip, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        SetSelected(self, self.selected)
        if self.tip then GameTooltip:Hide() end
    end)
    SetSelected(b, false)
    return b
end

-- buttons side by side inside a faint track; returns the track's width
local function Segments(parent, buttons, x)
    local track = buttons.track
    if not track then
        track = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
        track:SetColorTexture(1, 0.94, 0.82, 0.06)
        buttons.track = track
    end
    local bx = x + 2
    for _, b in ipairs(buttons) do
        b:SetSize(b.text:GetStringWidth() + 18, 20)
        b:ClearAllPoints()
        b:SetPoint("LEFT", parent, "LEFT", bx, 0)
        bx = bx + b:GetWidth()
    end
    track:ClearAllPoints()
    track:SetPoint("LEFT", parent, "LEFT", x, 0)
    track:SetSize(bx - x + 2, 24)
    return bx - x + 2
end

-- ------------------------------------------------------------
-- Frames (made once, the first time the map opens)
-- ------------------------------------------------------------
local overlay, mute, hud, bar, key, menu
local blobs, dots, rings, pins = {}, {}, {}, {}
local modeButtons, showButtons, menuRows, legendRows, rampBar = {}, {}, {}, {}, {}
local ui = {}

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
    bar:SetHeight(32)

    -- the name and on/off switch
    ui.header = CreateFrame("Button", nil, bar)
    ui.header:SetPoint("LEFT", 0, 0)
    ui.header:SetHeight(32)
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
    end)
    ui.header:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.title = Text(ui.header, "GameFontNormal")
    ui.title:SetPoint("LEFT", 10, 0)
    ui.title:SetText("Fieldnotes")
    ui.track = ui.header:CreateTexture(nil, "ARTWORK")
    ui.track:SetSize(26, 14)
    ui.track:SetPoint("LEFT", ui.title, "RIGHT", 8, 0)
    ui.knob = ui.header:CreateTexture(nil, "OVERLAY")
    ui.knob:SetSize(10, 10)
    ui.knob:SetTexture(CIRCLE)

    for i, m in ipairs(MODES) do
        local b = Button(bar, function()
            S().mode = m.key
            CloseMenu()
            M.Refresh()
        end)
        b.text:SetText(m.label)
        b.key = m.key
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

    -- the leather filter: a button that opens a short list
    ui.leather = Button(bar, function()
        if menu:IsShown() then menu:Hide() else menu:Show() end
    end)
    ui.leather.arrow = ui.leather:CreateTexture(nil, "OVERLAY")
    ui.leather.arrow:SetTexture(ARROW)
    ui.leather.arrow:SetSize(12, 12)
    ui.leather.arrow:SetPoint("RIGHT", -6, -1)
    ui.leather.text:ClearAllPoints()
    ui.leather.text:SetPoint("LEFT", 9, 0)

    ui.dividers = {}
    for i = 1, 3 do
        local d = bar:CreateTexture(nil, "ARTWORK")
        d:SetColorTexture(0.94, 0.82, 0.59, 0.16)
        d:SetSize(1, 16)
        ui.dividers[i] = d
    end

    menu = Card(hud)
    menu:SetFrameLevel(bar:GetFrameLevel() + 10)
    menu:Hide()
end

local function MenuRow(i)
    local b = menuRows[i]
    if b then return b end
    b = Button(menu, function(self)
        S().leather = self.itemID
        menu:Hide()
        M.Refresh()
    end)
    b:SetHeight(20)
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", 24, 0)
    b.swatch = b:CreateTexture(nil, "ARTWORK")
    b.swatch:SetSize(8, 8)
    b.swatch:SetTexture(CIRCLE)
    b.swatch:SetPoint("LEFT", 10, 0)
    menuRows[i] = b
    return b
end

-- lay the bar out left to right; with the overlay off only the name and switch remain
local function LayoutBar(on, leatherLabel)
    local x = ui.title:GetStringWidth() + 10 + 8 + 26 + 10
    ui.header:SetWidth(x)
    for _, d in ipairs(ui.dividers) do d:SetShown(on) end
    for _, b in ipairs(modeButtons) do b:SetShown(on) end
    for _, b in ipairs(showButtons) do b:SetShown(on) end
    ui.leather:SetShown(on)
    if not on then
        bar:SetWidth(x)
        return
    end
    local function Divider(i)
        ui.dividers[i]:ClearAllPoints()
        ui.dividers[i]:SetPoint("LEFT", bar, "LEFT", x + 2, 0)
        x = x + 5
    end
    local s = S()
    for _, b in ipairs(modeButtons) do SetSelected(b, b.key == s.mode) end
    for _, b in ipairs(showButtons) do SetSelected(b, b.key == s.show) end
    Divider(1)
    x = x + Segments(bar, modeButtons, x) + 6
    Divider(2)
    x = x + Segments(bar, showButtons, x) + 6
    Divider(3)
    ui.leather.text:SetText(leatherLabel)
    ui.leather:SetSize(ui.leather.text:GetStringWidth() + 32, 20)
    ui.leather:ClearAllPoints()
    ui.leather:SetPoint("LEFT", bar, "LEFT", x, 0)
    x = x + ui.leather:GetWidth() + 6
    bar:SetWidth(x)
end

local function BuildKey()
    key = Card(hud)
    key:SetPoint("BOTTOMLEFT", hud, "BOTTOMLEFT", 10, 10)
    ui.line = Text(key, "GameFontHighlightSmall")
    ui.line:SetPoint("TOPLEFT", 10, -9)
    ui.fewer = Text(key, "GameFontDisableSmall")
    ui.fewer:SetText("Fewer")
    for i = 1, 36 do
        local t = key:CreateTexture(nil, "ARTWORK")
        t:SetSize(4, 8)
        t:SetColorTexture(Ramp((i - 1) / 35))
        rampBar[i] = t
    end
    ui.more = Text(key, "GameFontDisableSmall")
    ui.more:SetText("More")
    ui.demo = Text(key, "GameFontDisableSmall")
    ui.demo:SetText("Sample data  ·  /fn demo off to hide it")
end

local function LegendRow(i)
    local row = legendRows[i]
    if row then return row end
    row = {}
    row.dot = key:CreateTexture(nil, "ARTWORK")
    row.dot:SetSize(8, 8)
    row.dot:SetTexture(CIRCLE)
    row.text = Text(key, "GameFontHighlightSmall", SOFT)
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
local function Records(mapID, show)
    local view = FN.View()
    local events = (show == "community") and (view.community and view.community.events) or view.events
    local list = events and events.skinning and events.skinning[mapID] or {}
    local me, out = FN.ViewChar(), {}
    for _, str in ipairs(list) do
        local r = FN.Decode(str)
        if r and r.x and r.y and (show ~= "me" or r.char == me) then out[#out + 1] = r end
    end
    return out
end

local function HeatGrid(recs, cols, rows)
    local g = {}
    for i = 1, cols * rows do g[i] = 0 end
    for _, r in ipairs(recs) do
        local c = math.min(cols - 1, math.floor(r.x / 1000 * cols))
        local rr = math.min(rows - 1, math.floor(r.y / 1000 * rows))
        local i = rr * cols + c + 1
        g[i] = g[i] + 1
    end
    -- smooth twice with a 3x3 kernel so the heat reads as areas, not specks
    for _ = 1, 2 do
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
    return g, max
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
local function SetSwitch(on)
    ui.knob:ClearAllPoints()
    if on then
        ui.track:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
        ui.knob:SetVertexColor(INK[1], INK[2], INK[3])
        ui.knob:SetPoint("CENTER", ui.track, "CENTER", 6, 0)
    else
        ui.track:SetColorTexture(0.23, 0.19, 0.16, 1)
        ui.knob:SetVertexColor(DIM[1], DIM[2], DIM[3])
        ui.knob:SetPoint("CENTER", ui.track, "CENTER", -6, 0)
    end
end

local function LayoutMenu(ids, colorOf, selected)
    local width = 120
    for i, id in ipairs(ids) do
        local b = MenuRow(i)
        b.itemID = id
        b.text:SetText(id == 0 and "All leather" or ItemName(id))
        width = math.max(width, b.text:GetStringWidth() + 40)
        local c = colorOf[id]
        b.swatch:SetShown(c ~= nil)
        if c then b.swatch:SetVertexColor(c[1], c[2], c[3]) end
        SetSelected(b, selected == id)
        b:Show()
    end
    HidePool(menuRows, #ids + 1)
    for i = 1, #ids do
        local b = menuRows[i]
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * 20)
        b:SetWidth(width - 8)
    end
    menu:SetSize(width, #ids * 20 + 8)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", ui.leather, "BOTTOMLEFT", -2, -6)
end

-- the key: one line of words, then the heat scale or the dot colors, then the demo note
local function LayoutKey(line, mode, legendIDs, colorOf, inDemo)
    ui.line:SetText(line)
    local width = math.max(200, ui.line:GetStringWidth() + 20)
    local y = -26
    local heat = mode == "heat" and legendIDs ~= nil
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
        ui.more:ClearAllPoints()
        ui.more:SetPoint("TOPLEFT", key, "TOPLEFT", bx + #rampBar * 4 + 6, y)
        width = math.max(width, bx + #rampBar * 4 + 6 + ui.more:GetStringWidth() + 10)
        y = y - 16
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
    key:Show()
end

local function Draw()
    local s = S()
    HidePool(blobs)
    HidePool(dots)
    HidePool(rings)
    HidePool(pins)
    SetSwitch(s.on)

    if not s.on then
        LayoutBar(false)
        CloseMenu()
        mute:Hide()
        key:Hide()
        return
    end
    mute:Show()
    local inDemo = FN.View() ~= FN.db

    local mapID = WorldMapFrame:GetMapID()
    local info = mapID and C_Map.GetMapInfo(mapID)
    local zoneType = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
    local all = mapID and Records(mapID, s.show) or {}

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
    LayoutMenu(menuIDs, colorOf, s.leather)
    LayoutBar(true, s.leather == 0 and "All leather" or ItemName(s.leather))

    local recs = all
    if s.leather ~= 0 then
        recs = {}
        for _, r in ipairs(all) do
            if r.items[s.leather] then recs[#recs + 1] = r end
        end
    end

    if info and info.mapType and info.mapType < zoneType then
        LayoutKey("Open a zone map to see your notes there.", s.mode, nil, colorOf, inDemo)
        return
    end
    if #recs == 0 then
        local msg = "Nothing skinned here yet."
        if s.show == "community" then
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
    local g, max = HeatGrid(recs, cols, rows)

    if s.mode == "heat" then
        -- faint areas first, so the strongest glow sits on top
        local order = {}
        for i = 1, #g do
            if g[i] / max >= 0.04 then order[#order + 1] = i end
        end
        table.sort(order, function(a, b) return g[a] < g[b] end)
        local size = BLOB_SIZE * math.max(cw, ch)
        for n, i in ipairs(order) do
            local v = g[i] / max
            local t = Pooled(blobs, n, "ARTWORK", 0, BLOB)
            local c, rr = (i - 1) % cols, math.floor((i - 1) / cols)
            t:ClearAllPoints()
            t:SetPoint("CENTER", overlay, "TOPLEFT", (c + 0.5) * cw, -(rr + 0.5) * ch)
            t:SetSize(size, size)
            local r, gg, b = Ramp(v)
            t:SetVertexColor(r, gg, b, HEAT_ALPHA_MIN + HEAT_ALPHA_SPAN * v)
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
    local legendIDs = {}
    if s.mode == "points" and s.leather ~= 0 then
        legendIDs[1] = s.leather
    elseif s.mode == "points" then
        for _, id in ipairs(leading) do
            if #legendIDs < 4 then legendIDs[#legendIDs + 1] = id end
        end
        legendIDs[#legendIDs + 1] = RUINED
    end
    LayoutKey(table.concat(parts, "  ·  "), s.mode, legendIDs, colorOf, inDemo)
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
        if WorldMapFrame:IsShown() then Draw() end
    end)
end
FN.OnDataChanged = M.Refresh

local function Init()
    if overlay or not WorldMapFrame or not WorldMapFrame.GetCanvas then return end
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
    hud:SetFrameLevel(container:GetFrameLevel() + 50)
    hud:EnableMouse(false)

    BuildBar()
    BuildKey()

    if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", M.Refresh) end
    WorldMapFrame:HookScript("OnShow", M.Refresh)
    WorldMapFrame:HookScript("OnHide", CloseMenu)
    overlay:SetScript("OnSizeChanged", M.Refresh)

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
