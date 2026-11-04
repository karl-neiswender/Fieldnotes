local ADDON, FN = ...

-- The map's controls, built from the map v2 mockups (design/map-v2-2026-11-03):
--
--   Small map: a dock outside the map's edge (right, or left when there is no room or a quest
--   panel sits on the right), the full height of the map, so nothing of Fieldnotes covers the
--   map but the heat itself. A "Fieldnotes" tab folds it away and back.
--   Full-screen map: one toolbar centred at the top and a small key in a bottom corner.
--
-- Both hold the same things: the profession, the on/off switch, View, Show, the material list
-- (leather, ore...), the key, the session (start, pause, end), Stats, Share and a gear for the
-- two settings left (Colors, When).
--
-- Professions v4 (design/professions-v4-2026-11-04): under the dock's Fieldnotes tab, one small
-- tab per profession in its color. The Fieldnotes tab opens the dashboard: a row per profession,
-- and on the map every gather as a dot in its profession's color (hover a row to light its dots). Map.lua draws the map and hands Render() a model of what is
-- on screen. Slides and fades follow the motion notes in that folder's README.

local MapUI = {}
FN.MapUI = MapUI

local St = FN.Style
local C = St.C
local STYLE = St.STYLE
local M -- FN.Map, set in Init (Map.lua loads first)
local ui -- shared with Map.lua (FN.Map.ui)

local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local BLOB = "Interface\\AddOns\\Fieldnotes\\Media\\blob" -- the soft round glow
local DOCK_W = 228
local PAD = 12
local INNER = DOCK_W - PAD * 2
local TAB_W, TAB_H = 26, 150 -- TAB_H: the stacked-letter fallback; a turned word sets its own
local TAB_TOP, TAB_GAP, TAB_BOTTOM = 8, 8, 8 -- room above the word, word to chevron, below it
local TAB_TUCK = 8 -- how far the open tab slips under the dock's edge, so the two read as one
local DOCK_TOP_H = 218 -- the dock's controls above the key (title to the material list)
local TOP_SHIFT = 20 -- the old profession row's room, given back now the tabs choose the profession
-- the dock's spacing, on a 4-unit scale: a section label, 16 to its controls (22 tall), 14 to the
-- next label. The first label sits 16 under the place line.
local FIRST_Y = -60 -- the first section label, from the dock's top
local LABEL_GAP = 16 -- a label's top to its controls' top
local CTRL_H = 22
local GROUP_GAP = 16 -- controls' bottom to the next label
local STEP = LABEL_GAP + CTRL_H + GROUP_GAP
local FOOTER_H = 4 -- the room under the session row (Stats, Share and settings moved to the tabs)
local EDGE_TUCK = 10 -- the map window's art stops this far inside its border frame's edge
local LIST_ROWS = 6
local GREEN = { 0.31, 0.75, 0.23 }

-- Silver relief icons share Forever Goal Tracker's treatment.
local PROF_ICONS = {
    skinning = "skinning-white",
    mining = "mining-white",
    herbalism = "herbalism-white",
    fishing = "fishing-white",
    cloth = "cloth-white",
}
local MODES = {
    { key = "heat", label = "Heat", tip = "A glow where you gather most" },
    { key = "points", label = "Points", tip = "One dot per gather, colored by what it gave" },
    { key = "spotlight", label = "Spotlight", tip = "The map dims, except where you gather" },
}
-- a section label's color for a profession: its hue, brought to the grey label's lightness and
-- softened a little toward that grey (pure color at that lightness read too loud)
local function LabelTint(c)
    local function Lum(x) return 0.299 * x[1] + 0.587 * x[2] + 0.114 * x[3] end
    local grey = C.SUBTEXT
    local k = Lum(grey) * 1.12 / math.max(0.05, Lum(c))
    local out = {}
    for i = 1, 3 do
        local v = math.min(1, c[i] * k)
        out[i] = v + (grey[i] - v) * 0.3
    end
    return out
end

-- n skins, n catches: the profession's own word
local function Units(p, n)
    p = p or { unit = "gather", units = "gathers" }
    return n .. " " .. (n == 1 and p.unit or p.units)
end
local SHOWS = {
    { key = "me", label = "Me", tip = "This character only" },
    { key = "account", label = "Account", tip = "Every character on this account" },
    { key = "community", label = "Community", tip = "Everyone who has shared, merged" },
}
local SCHEME_NAMES = { thermal = "Thermal", solar = "Solar", snowfall = "Snowfall" }
local WHENS = { { 0, "All time" }, { 30, "30 days" }, { 7, "7 days" } }

local model = {}
local profTabs, shownTabs = {}, {}
local PROF_TAB_H, PROF_TAB_GAP = 30, 4
local ProfMark, GoTo, Dashboard, FormatCount, SetSheet, ApplyTab, Glide -- defined with the dock
local homeTab
local utilTabs = {} -- Stats and Settings, under the profession tabs after a little gap
local UTIL_GAP = 12
local TAB_DROP = 14 -- the Fieldnotes tab's top, below the dock's

local function Refresh() M.Refresh() end

-- while a slider is dragged, redraw at most ten times a second (each redraw places every glow),
-- and the last move always lands
local sliderDue
local function SliderRefresh()
    if sliderDue then return end
    sliderDue = true
    C_Timer.After(0.1, function()
        sliderDue = false
        Refresh()
    end)
end

local function Label(parent, text)
    local fs = St.Text(parent, 10, C.SUBTEXT)
    fs:SetText(text)
    return fs
end

local function Choice(parent, label, onClick, tip)
    local b = St.ChoiceButton(parent, onClick)
    b.text:SetText(label)
    b.tip = tip
    b:SetHeight(22)
    return b
end

-- the gold button for a main action, with an optional icon before its label
local function Primary(parent, label, icon, onClick)
    local b = St.ChoiceButton(parent, onClick)
    b:SetChosen(true)
    b:SetScript("OnLeave", function(self) self:SetChosen(true) end)
    b.text:SetText(label)
    if icon then
        b.icon = b:CreateTexture(nil, "OVERLAY")
        b.icon:SetTexture(St.Icon(icon))
        b.icon:SetSize(9, 9)
        b.icon:SetVertexColor(C.TITLE[1], C.TITLE[2], C.TITLE[3])
        b.icon:SetPoint("RIGHT", b.text, "LEFT", -6, 0)
    end
    return b
end

local function Rule(parent)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(0.33, 0.29, 0.20, 1)
    return t
end

local function Plural(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

local function Clock(secs)
    secs = math.floor(secs)
    if secs >= 3600 then return string.format("%d:%02d:%02d", secs / 3600, (secs % 3600) / 60, secs % 60) end
    return string.format("%d:%02d", secs / 60, secs % 60)
end

-- ------------------------------------------------------------
-- The switch, with its slide: Fieldnotes off fades the heat away (and drifts the key down),
-- on brings it back. The toolbar's own narrowing is in LayoutToolbar.
-- ------------------------------------------------------------
local function SetOn(on)
    local s = M.S()
    if s.on == on then return end
    s.on = on
    if on then
        Refresh() -- draw first, then fade it in
        St.Animate("fn-overlay", 1, 0.3, "out", M.SetOverlayAlpha)
    else
        St.Animate("fn-overlay", 0, 0.3, "in", M.SetOverlayAlpha, Refresh)
        MapUI.Render(model) -- the controls follow straight away
    end
end

local function Switch(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(36, 18)
    b.toggle = St.Toggle(b)
    b.toggle:SetAllPoints()
    b:SetScript("OnClick", function() SetOn(not M.S().on) end)
    b:SetScript("OnEnter", function(self)
        self.toggle:SetOn(M.S().on, true)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Fieldnotes", C.TITLE[1], C.TITLE[2], C.TITLE[3])
        GameTooltip:AddLine("Show or hide your notes on the map.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self.toggle:SetOn(M.S().on)
        GameTooltip:Hide()
    end)
    return b
end

-- ------------------------------------------------------------
-- The leather list: one dropdown shared by the dock and the toolbar. It lists this map's
-- leathers, most first, with how many; past six it scrolls (mouse wheel, thin bar).
-- ------------------------------------------------------------
local list
local ROW_H, LIST_PAD, SPLIT = 22, 4, 9 -- row height, inner padding, the room the divider takes

local function FillList()
    local items = model.leathers or {}
    local maxOffset = math.max(0, #items - LIST_ROWS)
    list.offset = math.max(0, math.min(list.offset or 0, maxOffset))
    local y = -LIST_PAD
    local split = false
    for i, row in ipairs(list.rows) do
        local item = items[list.offset + i]
        row:SetShown(item ~= nil)
        if item then
            row.key = item.key
            row.text:SetText(item.label)
            row.count:SetText(item.count or "")
            if item.color then
                row.dot:SetVertexColor(item.color[1], item.color[2], item.color[3], 1)
            else
                row.dot:SetVertexColor(0.3, 0.3, 0.3, 0.6) -- All: the same quiet dot as the button
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", list, "TOPLEFT", LIST_PAD, y)
            row:SetPoint("TOPRIGHT", list, "TOPRIGHT", -LIST_PAD - (#items > LIST_ROWS and 6 or 0), y)
            row:SetChosen(item.key == model.leather)
            y = y - ROW_H
            -- a thin rule between "All leather" and the leathers themselves
            if item.key == 0 and items[list.offset + i + 1] then
                list.split:ClearAllPoints()
                list.split:SetPoint("TOPLEFT", list, "TOPLEFT", LIST_PAD + 8, y - (SPLIT - 1) / 2)
                list.split:SetPoint("TOPRIGHT", list, "TOPRIGHT", -LIST_PAD - 8, y - (SPLIT - 1) / 2)
                split = true
                y = y - SPLIT
            end
        end
    end
    list.split:SetShown(split)
    list:SetHeight(-y + LIST_PAD)
    local scrolls = #items > LIST_ROWS
    list.track:SetShown(scrolls)
    list.thumb:SetShown(scrolls)
    if scrolls then
        local trackH = -y - LIST_PAD
        local thumbH = math.max(16, trackH * LIST_ROWS / #items)
        list.thumb:SetHeight(thumbH)
        list.thumb:ClearAllPoints()
        list.thumb:SetPoint("TOPRIGHT", list, "TOPRIGHT", -5, -LIST_PAD - (trackH - thumbH) * list.offset / maxOffset)
    end
end

-- a flat row: a soft wash on hover; chosen, a gold bar at its left edge and gold text
local function ListRow(parent, onClick)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row.wash = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.wash:SetAllPoints()
    row.wash:SetTexture(St.SOLID)
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetTexture(St.SOLID)
    row.bar:SetVertexColor(C.ACCENT[1], C.ACCENT[2], C.ACCENT[3], 1)
    row.bar:SetWidth(2)
    row.bar:SetPoint("TOPLEFT", 0, -3)
    row.bar:SetPoint("BOTTOMLEFT", 0, 3)
    row.dot = row:CreateTexture(nil, "OVERLAY")
    row.dot:SetTexture(CIRCLE)
    row.dot:SetSize(8, 8)
    row.dot:SetPoint("LEFT", 10, 0)
    row.text = St.Text(row, 10, C.INK2)
    row.text:SetPoint("LEFT", 25, 0)
    row.text:SetPoint("RIGHT", -44, 0)
    row.text:SetWordWrap(false)
    row.count = St.Text(row, 10, C.SUBTEXT)
    row.count:SetPoint("RIGHT", -8, 0)
    row.count:SetJustifyH("RIGHT")
    function row:Paint()
        local c = self.chosen and C.TITLE or (self.hover and C.TEXT or C.INK2)
        self.text:SetTextColor(c[1], c[2], c[3])
        self.bar:SetShown(self.chosen)
        if self.chosen then
            self.wash:SetVertexColor(1, 0.82, 0, self.hover and 0.16 or 0.10)
        else
            self.wash:SetVertexColor(1, 0.92, 0.70, self.hover and 0.07 or 0)
        end
    end
    function row:SetChosen(on)
        self.chosen = on
        self:Paint()
    end
    row:SetScript("OnEnter", function(self)
        self.hover = true
        self:Paint()
    end)
    row:SetScript("OnLeave", function(self)
        self.hover = false
        self:Paint()
    end)
    row:SetScript("OnClick", onClick)
    return row
end

local function BuildList()
    list = St.Frame("Frame", UIParent)
    St.Etch(list, STYLE.panel, 12)
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetClampedToScreen(true)
    list:EnableMouse(true)
    list:EnableMouseWheel(true)
    list:Hide()
    list.rows = {}
    for i = 1, LIST_ROWS do
        list.rows[i] = ListRow(list, function(self)
            M.S().leather = self.key
            list:Hide()
            Refresh()
        end)
    end
    list.split = Rule(list)
    list.split:SetHeight(1)
    list.track = list:CreateTexture(nil, "ARTWORK")
    list.track:SetColorTexture(1, 0.94, 0.82, 0.05)
    list.track:SetWidth(3)
    list.track:SetPoint("TOPRIGHT", -5, -LIST_PAD)
    list.track:SetPoint("BOTTOMRIGHT", -5, LIST_PAD)
    list.thumb = list:CreateTexture(nil, "OVERLAY")
    list.thumb:SetColorTexture(0.42, 0.37, 0.26, 1)
    list.thumb:SetWidth(3)
    list:SetScript("OnMouseWheel", function(_, delta)
        list.offset = (list.offset or 0) - delta
        FillList()
    end)
    -- the owner's chevron points down again once the list closes
    list:SetScript("OnHide", function()
        if list.owner and list.owner.arrow then list.owner.arrow:SetRotation(0) end
    end)
end

local function ToggleList(owner)
    if list:IsShown() and list.owner == owner then
        list:Hide()
        return
    end
    if list:IsShown() then list:Hide() end
    list.owner = owner
    list.offset = 0
    -- the list lives on UIParent but must match the button on the map, whose window has its own
    -- scale: same scale, same width, just under it
    local base = UIParent:GetEffectiveScale() or 1
    local own = owner:GetEffectiveScale() or base
    if base > 0 and own > 0 then list:SetScale(own / base) end
    list:SetWidth(math.max(owner:GetWidth() or 0, 160))
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -3)
    FillList()
    list:Show()
    list:Raise() -- above the stats or share window, if one is open
    if owner.arrow then owner.arrow:SetRotation(math.pi) end
end

-- the button that opens the list: the chosen leather's dot and name, and a chevron
local function LeatherButton(parent)
    local b = Choice(parent, "All leather", function(self) ToggleList(self) end)
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", 24, 0)
    b.text:SetPoint("RIGHT", -22, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b.dot = b:CreateTexture(nil, "OVERLAY")
    b.dot:SetTexture(CIRCLE)
    b.dot:SetSize(8, 8)
    b.dot:SetPoint("LEFT", 9, 0)
    b.arrow = b:CreateTexture(nil, "OVERLAY")
    b.arrow:SetTexture(St.Icon("chevron-white"))
    b.arrow:SetVertexColor(C.INK2[1], C.INK2[2], C.INK2[3])
    b.arrow:SetSize(9, 9)
    b.arrow:SetPoint("RIGHT", -8, 0)
    function b:Update()
        local chosen
        for _, l in ipairs(model.leathers or {}) do
            if l.key == model.leather then chosen = l end
        end
        self.text:SetText(chosen and chosen.label or "All leather")
        local c = chosen and chosen.color
        if c then
            self.dot:SetVertexColor(c[1], c[2], c[3])
        else
            self.dot:SetVertexColor(0.3, 0.3, 0.3, 0.6) -- All: an empty ring look
        end
    end
    return b
end

-- ------------------------------------------------------------
-- The key: on this map, how many skins, what you skin most, and the scale
-- ------------------------------------------------------------
-- withSpots: the card also lists the hot spots the map pins, one line each (the dock's key); a
-- row and its pin light together (hover either), and a click on a row pings its pin
local SPOT_ROW = 17
local function SpotRow(k, i, width)
    local row = CreateFrame("Button", nil, k)
    row:SetSize(width - 10, SPOT_ROW)
    row.rank = i
    row.wash = row:CreateTexture(nil, "BACKGROUND")
    row.wash:SetAllPoints()
    row.wash:SetTexture(St.SOLID)
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetTexture(St.SOLID)
    row.bar:SetVertexColor(C.ACCENT[1], C.ACCENT[2], C.ACCENT[3], 1)
    row.bar:SetWidth(2)
    row.bar:SetPoint("TOPLEFT", 0, -2)
    row.bar:SetPoint("BOTTOMLEFT", 0, 2)
    row.badge = row:CreateTexture(nil, "ARTWORK")
    row.badge:SetTexture(CIRCLE)
    row.badge:SetSize(13, 13)
    row.badge:SetPoint("LEFT", 6, 0)
    if i == 1 then
        row.badge:SetVertexColor(C.ACCENT[1], C.ACCENT[2], C.ACCENT[3], 1)
    else
        row.badge:SetVertexColor(0.83, 0.80, 0.71, 1)
    end
    -- a ring that breathes out from the badge while the row is lit, on the pin's clock
    row.halo = row:CreateTexture(nil, "ARTWORK", nil, -1)
    row.halo:SetTexture(St.Media("ring"))
    row.halo:SetPoint("CENTER", row.badge, "CENTER", 0, 0)
    row.halo:SetVertexColor(C.ACCENT[1], C.ACCENT[2], C.ACCENT[3], 1)
    row.halo:Hide()
    row.num = St.Text(row, 9, { 0.10, 0.07, 0.03 })
    row.num:SetPoint("CENTER", row.badge, "CENTER", 0, 0)
    row.num:SetJustifyH("CENTER")
    row.num:SetText(i)
    row.count = St.Text(row, 11, C.TEXT)
    row.count:SetPoint("LEFT", 25, 0)
    row.coords = St.Text(row, 10, C.INK2)
    row.coords:SetPoint("RIGHT", -5, 0)
    row.coords:SetJustifyH("RIGHT")
    row.who = St.Text(row, 10, C.SUBTEXT)
    row.who:SetPoint("LEFT", row.count, "RIGHT", 6, 0)
    row.who:SetPoint("RIGHT", row.coords, "LEFT", -6, 0)
    row.who:SetWordWrap(false)
    row.who:SetJustifyH("LEFT")
    local function Breathe(self)
        local period = M.PULSE or 1.6
        local t = (GetTime() % period) / period
        local d = 13 + 10 * (1 - (1 - t) ^ 3)
        self.halo:SetSize(d, d)
        self.halo:SetAlpha(0.6 * (1 - t) ^ 1.6)
    end
    function row:Paint()
        local on = self.hover or self.lit
        self.bar:SetShown(on)
        self.wash:SetVertexColor(1, 0.82, 0, on and 0.10 or 0)
        self.halo:SetShown(on and true or false)
        if on then
            Breathe(self)
            self:SetScript("OnUpdate", Breathe)
        else
            self:SetScript("OnUpdate", nil)
        end
    end
    row:SetScript("OnEnter", function(self)
        self.hover = true
        self:Paint()
        M.LightPin(self.rank, true)
        if self.whoFull and self.who:IsTruncated() then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.whoFull, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.hover = false
        self:Paint()
        M.LightPin(self.rank, false)
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self) M.PingPin(self.rank) end)
    row:Paint()
    return row
end

local function KeyCard(parent, width, withSpots)
    local k = St.Frame("Frame", parent)
    St.Etch(k, STYLE.row, 12)
    k:SetWidth(width)
    k.withSpots = withSpots == true
    if withSpots then
        k.spotRule = k:CreateTexture(nil, "ARTWORK")
        k.spotRule:SetColorTexture(0.33, 0.29, 0.20, 0.8)
        k.spotRule:SetHeight(1)
        k.spotRows = {}
        for i = 1, 3 do k.spotRows[i] = SpotRow(k, i, width) end
    end
    k.big = St.Text(k, 18, C.TEXT)
    k.big:SetPoint("TOPLEFT", 11, -10)
    k.message = St.Text(k, 11, C.INK2)
    k.message:SetPoint("TOPLEFT", 11, -12)
    k.message:SetWidth(width - 22)
    k.message:SetJustifyV("TOP")
    k.rows = {}
    for i = 1, 2 do
        local l = St.Text(k, 10, C.SUBTEXT)
        local v = St.Text(k, 11, C.TEXT)
        v:SetJustifyH("RIGHT")
        v:SetWidth(width - 100)
        v:SetWordWrap(false)
        k.rows[i] = { l = l, v = v }
    end
    k.fewer = St.Text(k, 10, C.SUBTEXT)
    k.fewer:SetText("Fewer")
    k.more = St.Text(k, 10, C.SUBTEXT)
    k.more:SetText("More")
    -- the ramp: 16 stretches, each a smooth blend between its ends, laid edge to edge. Overlapping
    -- them doubled the faint end's transparency at every seam, which read as stripes in game.
    k.ramp = {}
    for i = 1, 16 do
        local t = k:CreateTexture(nil, "ARTWORK")
        t:SetTexture(St.SOLID)
        t:SetHeight(8)
        k.ramp[i] = t
    end
    function k:PaintRamp(x, y, barW, fade)
        local n = #self.ramp
        local step = barW / n
        for i, t in ipairs(self.ramp) do
            local v0, v1 = (i - 1) / n, i / n
            local r0, g0, b0 = M.Ramp(v0)
            local r1, g1, b1 = M.Ramp(v1)
            t:SetWidth(step)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", self, "TOPLEFT", x + (i - 1) * step, y)
            St.HGradient(t, { r0, g0, b0 }, { r1, g1, b1 }, fade and M.Quiet(v0) or 1, fade and M.Quiet(v1) or 1)
        end
    end
    -- on a zone's heat: the ramp runs the card's width with skin counts under it, its left end
    -- fading as the map's quiet areas do, over a faint track so the bar still reads as one
    k.track = k:CreateTexture(nil, "ARTWORK", nil, -1)
    k.track:SetColorTexture(1, 0.94, 0.82, 0.06)
    k.track:SetHeight(8)
    k.ticks = {}
    for i = 1, 5 do
        local t = St.Text(k, 10, C.SUBTEXT)
        t:SetWordWrap(false)
        k.ticks[i] = t
    end
    k.caption = St.Text(k, 10, C.SUBTEXT)
    k.caption:SetText("in one spot")
    k.caption:SetJustifyH("CENTER")
    k.scale = St.Text(k, 10, C.SUBTEXT)
    k.scale:SetWidth(width - 22)
    k.legend = {}
    for i = 1, 5 do
        local d = k:CreateTexture(nil, "ARTWORK")
        d:SetTexture(CIRCLE)
        d:SetSize(8, 8)
        local t = St.Text(k, 10, C.INK2)
        t:SetPoint("LEFT", d, "RIGHT", 5, 0)
        k.legend[i] = { d = d, t = t }
    end
    k.demo = St.Text(k, 10, C.SUBTEXT)
    k.demo:SetText("Sample data  ·  /fn demo off to hide it")

    -- maxH: the room it has; past it, the key leaves out its caption, scale line and demo note,
    -- then hot spots from the bottom (spotCap), keeping at least the first
    function k:Update(m, maxH, compact, spotCap)
        local y
        local hasData = not m.message
        local spots = self.withSpots and hasData and m.kind ~= "continent" and m.spots or nil
        local nSpots = spots and math.min(#spots, spotCap or 3) or 0
        if self.withSpots then
            self.spotRule:SetShown(nSpots > 0)
            for i, row in ipairs(self.spotRows) do row:SetShown(i <= nSpots) end
        end
        self.big:SetShown(hasData)
        self.message:SetShown(not hasData)
        for _, r in ipairs(self.rows) do
            r.l:Hide()
            r.v:Hide()
        end
        for _, l in ipairs(self.legend) do
            l.d:Hide()
            l.t:Hide()
        end
        local showRamp = hasData and m.mode == "heat" or (hasData and m.kind == "continent")
        local numbered = showRamp and m.peak ~= nil
        for _, t in ipairs(self.ramp) do t:SetShown(showRamp) end
        self.track:SetShown(numbered)
        for _, t in ipairs(self.ticks) do t:Hide() end
        self.caption:SetShown(numbered and not compact)
        self.fewer:SetShown(showRamp and not numbered)
        self.more:SetShown(showRamp and not numbered)
        self.scale:SetShown(not compact and (hasData and m.scale ~= nil and m.mode ~= "points" or (hasData and m.kind == "continent")))
        if not hasData then
            self.message:SetText(m.message)
            y = -12 - self.message:GetStringHeight() - 10
        else
            self.big:SetText(Units(m.p, m.skins or 0))
            self.caption:SetText((m.p and m.p.units or "gathers") .. " in one spot")
            y = -34
            local rows
            local p = m.p or {}
            if m.kind == "continent" then
                rows = { { "Zones", m.zones and tostring(m.zones) }, { "Most " .. (p.units or ""), m.bestZone } }
            elseif nSpots > 0 then
                rows = {} -- the hot spots below name the creatures instead
            elseif m.prof == "fishing" then
                rows = { { "Main catch", m.topLoot } }
            else
                rows = { { m.prof == "skinning" and "Most skinned" or "Most from", m.topWho },
                    { "Main " .. (p.material or "leather"), m.topLoot } }
            end
            for i, r in ipairs(rows) do
                if r[2] then
                    local row = self.rows[i]
                    row.l:SetText(r[1])
                    row.v:SetText(r[2])
                    row.l:ClearAllPoints()
                    row.l:SetPoint("TOPLEFT", self, "TOPLEFT", 11, y)
                    row.v:ClearAllPoints()
                    row.v:SetPoint("TOPRIGHT", self, "TOPRIGHT", -11, y)
                    row.l:Show()
                    row.v:Show()
                    y = y - 16
                end
            end
            y = y - 4
            if numbered then
                local barW = width - 22
                self.track:ClearAllPoints()
                self.track:SetPoint("TOPLEFT", self, "TOPLEFT", 11, y - 1)
                self.track:SetWidth(barW)
                self:PaintRamp(11, y - 1, barW, true)
                y = y - 12
                -- 1 at the quiet end, then even steps up to the busiest spot on this map
                local peak = math.max(1, m.peak)
                local marks = { { 0, 1 } }
                if peak >= 8 then
                    for q = 1, 3 do marks[#marks + 1] = { q / 4, math.floor(peak * q / 4 + 0.5) } end
                end
                if peak > 1 then marks[#marks + 1] = { 1, peak } end
                for i, mk in ipairs(marks) do
                    local t = self.ticks[i]
                    t:SetText(mk[2])
                    t:ClearAllPoints()
                    local point = mk[1] == 0 and "TOPLEFT" or (mk[1] == 1 and "TOPRIGHT" or "TOP")
                    t:SetPoint(point, self, "TOPLEFT", 11 + barW * mk[1], y)
                    t:Show()
                end
                y = y - 12
                if self.caption:IsShown() then
                    self.caption:ClearAllPoints()
                    self.caption:SetPoint("TOP", self, "TOPLEFT", width / 2, y)
                    y = y - 14
                end
            elseif showRamp then
                self.fewer:ClearAllPoints()
                self.fewer:SetPoint("TOPLEFT", self, "TOPLEFT", 11, y)
                local barW = width - 22 - self.fewer:GetStringWidth() - self.more:GetStringWidth() - 12
                self:PaintRamp(11 + self.fewer:GetStringWidth() + 6, y - 1, barW, false)
                self.more:ClearAllPoints()
                self.more:SetPoint("TOPRIGHT", self, "TOPRIGHT", -11, y)
                y = y - 16
            elseif m.legend then
                local x = 11
                for i, l in ipairs(m.legend) do
                    local row = self.legend[i]
                    row.d:SetVertexColor(l.color[1], l.color[2], l.color[3])
                    row.t:SetText(l.label)
                    local w = 13 + row.t:GetStringWidth() + 10
                    if x > 11 and x + w > width - 8 then x, y = 11, y - 15 end
                    row.d:ClearAllPoints()
                    row.d:SetPoint("TOPLEFT", self, "TOPLEFT", x, y - 2)
                    row.d:Show()
                    row.t:Show()
                    x = x + w
                end
                y = y - 15
            end
            if m.scale and self.scale:IsShown() then
                self.scale:SetText(m.scale)
                self.scale:ClearAllPoints()
                self.scale:SetPoint("TOPLEFT", self, "TOPLEFT", 11, y)
                y = y - self.scale:GetStringHeight() - 4
            end
        end
        if nSpots > 0 then
            y = y - 1
            self.spotRule:ClearAllPoints()
            self.spotRule:SetPoint("TOPLEFT", self, "TOPLEFT", 11, y)
            self.spotRule:SetPoint("TOPRIGHT", self, "TOPRIGHT", -11, y)
            y = y - 3
            for i = 1, nSpots do
                local sp, row = spots[i], self.spotRows[i]
                row.count:SetText(sp.count)
                row.coords:SetText(sp.coords)
                row.whoFull = sp.who ~= "" and sp.who or sp.loot
                row.who:SetText(row.whoFull)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", self, "TOPLEFT", 5, y)
                y = y - SPOT_ROW
            end
        end
        self.demo:SetShown(m.inDemo and not compact)
        if m.inDemo and not compact then
            self.demo:ClearAllPoints()
            self.demo:SetPoint("TOPLEFT", self, "TOPLEFT", 11, y - 2)
            y = y - 16
        end
        self:SetHeight(-y + 8)
        self.lastRoom, self.lastSpots = maxH, nSpots -- for /fn debug
        if maxH and -y + 8 > maxH then
            if not compact then return self:Update(m, maxH, true, spotCap) end
            if nSpots > 1 then return self:Update(m, maxH, true, nSpots - 1) end
        end
    end
    return k
end

-- ------------------------------------------------------------
-- The session: start with play, pause and end while it runs. The same session as the
-- tracker panel (Session.lua).
-- ------------------------------------------------------------
local function SessionCard(parent, width)
    local sc = St.Frame("Frame", parent)
    St.Etch(sc, STYLE.row, 12)
    sc:SetSize(width, 34)
    sc:EnableMouse(true)
    sc.dot = sc:CreateTexture(nil, "ARTWORK", nil, 2) -- above its glow
    sc.dot:SetTexture(CIRCLE)
    sc.dot:SetSize(8, 8)
    sc.dot:SetPoint("LEFT", 11, 0)
    sc.glow = St.Glow(sc, sc.dot, GREEN) -- breathes while the session runs, as on the tracker
    sc.title = St.Title(sc, 12)
    sc.title:SetPoint("LEFT", sc.dot, "RIGHT", 7, 0)
    -- beside the clock: "Paused" or the skins so far, stopping short of the pause and end icons
    sc.detail = St.Text(sc, 10, C.INK2)
    sc.detail:SetPoint("LEFT", sc.title, "RIGHT", 8, 0)
    sc.detail:SetWordWrap(false)
    sc.detail:SetJustifyH("LEFT")
    sc.start = Primary(sc, "Start", "play-white", function()
        FN.SessionStart()
        sc:Update()
    end)
    sc.start.tip = "A session also starts by itself with your first gather."
    sc.start:SetSize(70, 22)
    sc.start:SetPoint("RIGHT", -6, 0)
    sc.stop = St.IconButton(sc, "stop-white", 10, function() -- stop, not close: it ends the session
        FN.SessionEnd()
        sc:Update()
    end)
    sc.stop:SetPoint("RIGHT", -11, 0)
    sc.pause = St.IconButton(sc, "pause-white", 12, function()
        FN.SessionTogglePause()
        sc:Update()
    end)
    sc.pause:SetPoint("RIGHT", sc.stop, "LEFT", -10, 0)
    local function Tip(self, text)
        self:SetScript("OnEnter", function(b)
            b.icon:SetVertexColor(C.TITLE[1], C.TITLE[2], C.TITLE[3])
            GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
            GameTooltip:SetText(type(text) == "function" and text() or text, 1, 1, 1)
            GameTooltip:Show()
        end)
        self:SetScript("OnLeave", function(b)
            b.icon:SetVertexColor(C.INK2[1], C.INK2[2], C.INK2[3])
            GameTooltip:Hide()
        end)
    end
    Tip(sc.stop, "End session")
    Tip(sc.pause, function() return FN.SessionPaused() and "Resume" or "Pause" end)
    -- the card itself explains the running session on hover
    sc:SetScript("OnEnter", function(self)
        if not FN.SessionRunning() then return end
        local s = FN.session
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("This session", C.TITLE[1], C.TITLE[2], C.TITLE[3])
        GameTooltip:AddLine(string.format("%s in %s", FN.SessionLabel(), Clock(FN.SessionSeconds())), 1, 1, 1)
        for _, key in ipairs(s.order or {}) do
            local p, e = M.PROF[key], s.profs[key]
            if p and e then GameTooltip:AddLine(p.label .. "  " .. e.count, p.color[1], p.color[2], p.color[3]) end
        end
        GameTooltip:Show()
    end)
    sc:SetScript("OnLeave", function() GameTooltip:Hide() end)

    function sc:Update()
        local running, paused = FN.SessionRunning(), FN.SessionPaused()
        self.start:SetShown(not running)
        self.pause:SetShown(running)
        self.stop:SetShown(running)
        self.detail:SetShown(running)
        self.glow:SetOn(running and not paused)
        if not running then
            self.dot:SetVertexColor(0.36, 0.35, 0.33)
            self.title:SetText("Session")
            self.title:SetTextColor(C.TITLE[1], C.TITLE[2], C.TITLE[3])
        else
            if paused then
                self.dot:SetVertexColor(C.SUBTEXT[1], C.SUBTEXT[2], C.SUBTEXT[3])
                self.title:SetTextColor(C.INK2[1], C.INK2[2], C.INK2[3])
            else
                self.dot:SetVertexColor(GREEN[1], GREEN[2], GREEN[3])
                self.title:SetTextColor(C.TITLE[1], C.TITLE[2], C.TITLE[3])
            end
            self.title:SetText(Clock(FN.SessionSeconds()))
            -- paused, the word takes the count's place (the card's tooltip still has the count)
            self.detail:SetText(paused and "Paused" or FN.SessionLabel())
            self.detail:SetWidth(math.max(20, width - 11 - 15 - self.title:GetStringWidth() - 8 - 56))
            self.pause.icon:SetTexture(St.Icon(paused and "play-white" or "pause-white"))
        end
    end
    -- the clock ticks once a second while the card is on screen
    local elapsed = 0
    sc:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= 1 then
            elapsed = 0
            if FN.SessionRunning() then self:Update() end
        end
    end)
    return sc
end

-- ------------------------------------------------------------
-- The settings: Colors and When. In the dock a sheet slides up over it from the bottom; on
-- the full-screen map it drops from the gear.
-- ------------------------------------------------------------
-- noWhen: leave out When (the dock: the dashboard has it; the full-screen map keeps it)
local function SettingsBody(parent, width, noWhen)
    local b = { parent = parent }
    b.colorsLabel = Label(parent, "COLORS")
    b.swatches = {}
    local slot = math.min(width / #M.SCHEME_ORDER, 72)
    for i, name in ipairs(M.SCHEME_ORDER) do
        local sw = CreateFrame("Button", nil, parent)
        sw:SetSize(slot, 46)
        sw.ring = sw:CreateTexture(nil, "ARTWORK", nil, 1)
        sw.ring:SetTexture(CIRCLE)
        sw.ring:SetSize(32, 32)
        sw.ring:SetPoint("TOP", 0, 0)
        -- the whole ramp, most at the top: the disc cut into thin slices of the same round
        -- texture, each blended across its stretch of the scheme (two colours hid Solar's
        -- orange and gold, seen in game)
        local D, SLICES = 26, 8
        for j = 1, SLICES do
            local t = sw:CreateTexture(nil, "ARTWORK", nil, 2)
            t:SetTexture(CIRCLE)
            local y0, y1 = (j - 1) / SLICES, j / SLICES
            t:SetTexCoord(0, 1, y0, y1)
            t:SetSize(D, D / SLICES)
            t:SetPoint("TOP", sw.ring, "TOP", 0, -(32 - D) / 2 - (j - 1) * D / SLICES)
            local rt, gt, bt = M.SchemeColor(name, 1 - y0)
            local rb, gb, bb = M.SchemeColor(name, 1 - y1)
            St.VGradient(t, { rt, gt, bt }, { rb, gb, bb })
        end
        sw.name = St.Text(sw, 10, C.INK2)
        sw.name:SetPoint("BOTTOM", 0, 0)
        sw.name:SetJustifyH("CENTER")
        sw.name:SetText(SCHEME_NAMES[name])
        sw.key = name
        sw:SetScript("OnClick", function()
            M.S().colors = name
            Refresh()
        end)
        b.swatches[i] = sw
    end
    b.whens = {}
    if not noWhen then b.whenLabel = Label(parent, "WHEN") end
    for i, w in ipairs(noWhen and {} or WHENS) do
        local btn = Choice(parent, w[2], function()
            M.S().when = w[1]
            Refresh()
        end)
        btn.value = w[1]
        b.whens[i] = btn
    end
    b.strengthLabel = Label(parent, "STRENGTH")
    b.strengthValue = St.Text(parent, 10, C.INK2)
    b.strengthValue:SetJustifyH("RIGHT")
    b.slider = St.Slider(parent, width, 0.5, 2.5, 0.05, function(v)
        M.S().strength = v
        b.strengthValue:SetText(math.floor(v * 100 + 0.5) .. "%")
        SliderRefresh()
    end)
    b.spreadLabel = Label(parent, "SPREAD")
    b.spreadValue = St.Text(parent, 10, C.INK2)
    b.spreadValue:SetJustifyH("RIGHT")
    b.spreadSlider = St.Slider(parent, width, 0.5, 2.5, 0.05, function(v)
        M.S().spread = v
        b.spreadValue:SetText(math.floor(v * 100 + 0.5) .. "%")
        SliderRefresh()
    end)
    b.note = St.Text(parent, 10, C.SUBTEXT)
    b.note:SetWidth(width)
    b.note:SetText("Strength is how bold the heat is; spread, how wide each glow reaches.")
    -- the session: start by itself with your first gather (on by default), or only by hand
    b.sessionLabel = Label(parent, "SESSION")
    b.autoText = St.Text(parent, 10, C.INK2)
    b.autoText:SetText("Start with my first gather")
    b.auto = CreateFrame("Button", nil, parent)
    b.auto:SetSize(36, 18)
    b.auto.toggle = St.Toggle(b.auto)
    b.auto.toggle:SetAllPoints()
    b.auto:SetScript("OnClick", function(self)
        FN.db.settings.autoSession = FN.db.settings.autoSession == false
        self.toggle:SetOn(FN.db.settings.autoSession ~= false)
    end)
    b.auto:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Start sessions by themselves", 1, 1, 1)
        GameTooltip:AddLine("Off: a session starts only when you press Start. Your gathers are always recorded.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b.auto:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- sharing lives here now: one button for the share window (Share and Import)
    b.shareLabel = Label(parent, "SHARE")
    b.share = Choice(parent, "Share or import notes", function() FN.ShowShare() end,
        "Copy your notes as one line of text, or paste someone else's")
    b.share.icon = b.share:CreateTexture(nil, "OVERLAY")
    b.share.icon:SetTexture(St.Icon("share-white"))
    b.share.icon:SetSize(12, 12)
    b.share.icon:SetPoint("RIGHT", b.share.text, "LEFT", -6, 0)
    b.reset = Choice(parent, "Reset map settings", function()
        local s = M.S()
        s.colors, s.when, s.strength, s.spread, s.leather = M.DEFAULTS.colors, M.DEFAULTS.when,
            M.DEFAULTS.strength, M.DEFAULTS.spread, 0
        Refresh()
    end)

    -- lay it out from (x, y) down; returns the bottom y
    function b:Layout(x, y)
        self.colorsLabel:ClearAllPoints()
        self.colorsLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        y = y - 16
        for i, sw in ipairs(self.swatches) do
            sw:ClearAllPoints()
            sw:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (i - 1) * slot, y)
            local on = model.colors == sw.key
            if on then
                sw.ring:SetVertexColor(C.ACCENT[1], C.ACCENT[2], C.ACCENT[3], 1)
            else
                sw.ring:SetVertexColor(0, 0, 0, 1)
            end
            sw.name:SetTextColor((on and C.TITLE or C.INK2)[1], (on and C.TITLE or C.INK2)[2], (on and C.TITLE or C.INK2)[3])
        end
        y = y - 62
        if self.whenLabel then
            self.whenLabel:ClearAllPoints()
            self.whenLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
            y = y - 16
            local w3 = (width - 6) / 3
            for i, btn in ipairs(self.whens) do
                btn:SetSize(w3, 22)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (i - 1) * (w3 + 3), y)
                btn:SetChosen(model.when == btn.value)
            end
            y = y - 38
        end
        self.strengthLabel:ClearAllPoints()
        self.strengthLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        self.strengthValue:ClearAllPoints()
        self.strengthValue:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y)
        local st = M.S().strength
        self.strengthValue:SetText(math.floor(st * 100 + 0.5) .. "%")
        y = y - 18
        self.slider:ClearAllPoints()
        self.slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        self.slider:Set(st)
        y = y - 34
        self.spreadLabel:ClearAllPoints()
        self.spreadLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        self.spreadValue:ClearAllPoints()
        self.spreadValue:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y)
        local sp = M.S().spread
        self.spreadValue:SetText(math.floor(sp * 100 + 0.5) .. "%")
        y = y - 18
        self.spreadSlider:ClearAllPoints()
        self.spreadSlider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        self.spreadSlider:Set(sp)
        y = y - 34
        self.note:ClearAllPoints()
        self.note:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        y = y - self.note:GetStringHeight() - 16
        self.reset:SetSize(width, 22)
        self.reset:ClearAllPoints()
        self.reset:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        y = y - 22 - 24
        self.sessionLabel:ClearAllPoints()
        self.sessionLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        y = y - 18
        self.autoText:ClearAllPoints()
        self.autoText:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 3)
        self.auto:ClearAllPoints()
        self.auto:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y)
        self.auto.toggle:SetOn(FN.db.settings.autoSession ~= false)
        y = y - 18 - 24
        self.shareLabel:ClearAllPoints()
        self.shareLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        y = y - 16
        self.share:SetSize(width, 22)
        self.share:ClearAllPoints()
        self.share:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        return y - 22
    end
    return b
end

local function GearButton(parent, onClick)
    local g = St.IconButton(parent, "gear-white", 16, onClick)
    g:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(C.TITLE[1], C.TITLE[2], C.TITLE[3])
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Map settings", C.TITLE[1], C.TITLE[2], C.TITLE[3])
        GameTooltip:AddLine("Colors, strength, spread and time range", 1, 1, 1)
        GameTooltip:Show()
    end)
    g:SetScript("OnLeave", function(self)
        self:Tint()
        GameTooltip:Hide()
    end)
    function g:Tint()
        local s = M.S()
        local changed = s.colors ~= M.DEFAULTS.colors or s.when ~= M.DEFAULTS.when
            or math.abs(s.strength - M.DEFAULTS.strength) > 0.01 or math.abs(s.spread - M.DEFAULTS.spread) > 0.01
        local c = self.open and C.TITLE or (changed and C.GOLD2 or C.INK2)
        self.icon:SetVertexColor(c[1], c[2], c[3])
    end
    return g
end

-- an icon in the dock's footer, with its name in a tooltip (the gear's sisters)
local function FooterIcon(parent, icon, name, tip, onClick)
    local b = St.IconButton(parent, icon, 16, onClick)
    b:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(C.TITLE[1], C.TITLE[2], C.TITLE[3])
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(name, C.TITLE[1], C.TITLE[2], C.TITLE[3])
        GameTooltip:AddLine(tip, 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(C.INK2[1], C.INK2[2], C.INK2[3])
        GameTooltip:Hide()
    end)
    return b
end

-- ------------------------------------------------------------
-- The dock (small map)
-- ------------------------------------------------------------
local dock, tab, sheet

-- the hot spot row for a pin the mouse is over (Map.lua calls this), and whether a row is lit
function MapUI.LightSpot(rank, on)
    local row = dock and dock.key.spotRows and dock.key.spotRows[rank]
    if not row then return end
    row.lit = on
    row:Paint()
end
function MapUI.SpotLit(rank)
    local row = dock and dock.key.spotRows and dock.key.spotRows[rank]
    return row and (row.hover or row.lit) and row:IsShown() and true or false
end

local function DockOpen() return FN.db.settings.dockOpen ~= false end

-- a profession's mark: its icon tinted in its color, or its initial until the icon exists.
-- p can change later (the dock's title mark follows the page): mark:Set(p)
ProfMark = function(parent, size, p)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.initial = St.Text(f, math.floor(size * 0.8), C.INK2)
    f.initial:SetPoint("CENTER", 0, 0)
    f.initial:SetJustifyH("CENTER")
    function f:Set(q)
        self.p = q
        if not q then
            self.icon:Hide()
            self.initial:Hide()
            return
        end
        local file = PROF_ICONS[q.key]
        self.icon:SetShown(file ~= nil)
        self.initial:SetShown(file == nil)
        if file then
            self.icon:SetTexture(St.Icon(file))
            self.icon:SetVertexColor(q.color[1], q.color[2], q.color[3])
        else
            self.initial:SetText(q.label:sub(1, 1))
            self.initial:SetTextColor(q.color[1], q.color[2], q.color[3])
        end
    end
    f:Set(p)
    return f
end

-- A rail tab's look at its current `out` (see RailTab in BuildDock)
local REST = { 0.84, 0.82, 0.78 } -- every icon at rest: the painted silver, barely toned
local TAB_SLIDE = 8 -- how much further the active tab reaches out (hover: 0.4 of it)
-- The active tab is the page itself reaching out. Rather than guess the dock's color (a guess
-- showed as a lighter block, seen in game), each tab carries a copy of the dock's own background,
-- the same gradient and grime laid out on the same rectangle as the dock (so every pixel matches),
-- seen only through a window over the tab and the strip of the dock's border beside it. Shown
-- while active, that window erases the border between them: tab and page are one surface.
-- Over it, a faint light of the tab's color comes in from the tab's outer edge.
local SEAM_IN = 5 -- how far into the dock the window reaches (past the dock's border)
local RECESS = 0.72 -- inactive tabs: a shade darker, as if they sat behind the page
local LIGHT_PEAK = 0.34 -- at the outer edge; 0.14 and 0.2 did not show in game

local function PageCopy(t)
    local clip = CreateFrame("Frame", nil, dock)
    clip:SetClipsChildren(true)
    clip:Hide()
    local copy = CreateFrame("Frame", nil, clip)
    -- the dock's rectangle, reaching on past its right edge so the copy runs under the tab too
    copy:SetPoint("TOPLEFT", dock, "TOPLEFT", -80, 0)
    copy:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT", 80, 0)
    local inset = 3 -- St.Etch's inset at the dock's edge size (12)
    copy.bg = copy:CreateTexture(nil, "BACKGROUND", nil, -7)
    copy.bg:SetTexture(St.SOLID)
    copy.bg:SetPoint("TOPLEFT", dock, "TOPLEFT", inset - 80, -inset)
    copy.bg:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT", 80, inset)
    St.VGradient(copy.bg, STYLE.dock.top, STYLE.dock.bottom)
    -- the grime as St.Grime lays it on the dock: same strength, same fade, same tile origin
    local grime = CreateFrame("Frame", nil, clip)
    -- (wider than the dock to the right, so the grime runs on under the tab; the tile is laid from
    -- the left at its real size, so the part over the dock is the dock's own)
    grime:SetPoint("TOPLEFT", dock, "TOPLEFT", 0, 0)
    grime:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT", 80, 0)
    St.Grime(grime, 0.25, 12, 0, 150, 220)
    -- the light lives on the icon's frame, the one layer known to draw above the copy (on the
    -- window, then on a frame of its own inside it, it never showed in game, though /fn debug had it
    -- shown at its strength), under the icon itself; it reaches past that small frame to fill the tab
    clip.light = t.mark:CreateTexture(nil, "BACKGROUND")
    clip.light:SetTexture(St.Media("fade"))
    clip.light:Hide()
    clip.copy, clip.grime, clip.lightF = copy, grime, t.mark
    t.page = clip
end

ApplyTab = function(t)
    local v = t.out or 0
    local a = math.max(0, (v - 0.4) / 0.6) -- how active it looks: nothing while only hovered
    t:SetWidth(TAB_W + (t.tuck or 0) + TAB_SLIDE * v)
    -- at rest the tab is recessed, a shade darker than the page
    local d = STYLE.dock
    St.VGradient(t.etchBg, { d.top[1] * RECESS, d.top[2] * RECESS, d.top[3] * RECESS },
        { d.bottom[1] * RECESS, d.bottom[2] * RECESS, d.bottom[3] * RECESS })
    local rest, c = t.rest or REST, t.color
    t.icon:SetVertexColor(rest[1] + (c[1] - rest[1]) * a, rest[2] + (c[2] - rest[2]) * a, rest[3] + (c[3] - rest[3]) * a)
    t.icon:SetAlpha(0.72 + 0.28 * math.min(1, v / 0.4))

    if not t.page and dock then PageCopy(t) end
    local page = t.page
    if not page then return end
    page:SetShown(a > 0.01 and t:IsShown())
    page.light:SetShown(a > 0.01)
    if a <= 0.01 then return end
    local right = t.side ~= "LEFT" -- the dock is to the tab's left
    local tuck = t.tuck or 0
    page:SetAlpha(a)
    local base = dock:GetFrameLevel() + 4
    page:SetFrameLevel(base)
    page.copy:SetFrameLevel(base + 1)
    page.grime:SetFrameLevel(base + 1)
    -- the icon (and the session dot on it) stays above the copy
    t.mark:SetFrameLevel(base + 3)
    page:ClearAllPoints()
    if right then
        page:SetPoint("TOPLEFT", t, "TOPLEFT", tuck - SEAM_IN, -3)
        page:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -3, 3)
    else
        page:SetPoint("TOPRIGHT", t, "TOPRIGHT", -tuck + SEAM_IN, -3)
        page:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 3, 3)
    end
    -- the light: from the outer edge inward, gone before it reaches the page
    local light = page.light
    light:ClearAllPoints()
    -- (corner anchors only: no edge anchor fighting another for the same side)
    if right then
        light:SetPoint("TOPRIGHT", page, "TOPRIGHT")
        light:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT")
        light:SetTexCoord(1, 0, 0, 1)
    else
        light:SetPoint("TOPLEFT", page, "TOPLEFT")
        light:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT")
        light:SetTexCoord(0, 1, 0, 1)
    end
    light:SetWidth(math.max(4, (t:GetWidth() or TAB_W) - tuck - 3))
    light:SetVertexColor(c[1], c[2], c[3], LIGHT_PEAK * a)
end

-- glide a tab toward its state: active 1, hovered 0.4, else 0
Glide = function(t, instant)
    local target = t.active and 1 or (t.hover and 0.4 or 0)
    St.Animate(t.id, target, instant and 0 or 0.22, "out", function(v)
        t.out = v
        ApplyTab(t)
    end)
end

-- which professions get a tab: the ones this character knows, Cloth for everyone, and in
-- Account or Community any profession with notes
local function TabProfs()
    local s, out = M.S(), {}
    local sum = M.Summary(s.show, 0)
    for _, p in ipairs(M.PROFS) do
        local known = p.key == "cloth" or (FN.ProfessionSkill and (FN.ProfessionSkill(p.key) or 0) > 0)
        local any = sum[p.key] and sum[p.key].n > 0
        if known or (s.show ~= "me" and any) or (FN.View() ~= FN.db and any) then out[#out + 1] = p end
    end
    return out
end

-- go to a page ("all": the dashboard). The tab of the page already open folds the dock.
GoTo = function(key)
    local s = M.S()
    if list then list:Hide() end
    if dock.sheetOpen then
        SetSheet(false)
        if DockOpen() and s.prof == key then
            MapUI.Render(model)
            return
        end
    end
    FN.db.settings.dockOpen = true
    if s.prof ~= key then
        s.prof = key
        M.SetLit(nil)
        Refresh()
    end
    MapUI.Render(model)
end

-- the settings, laid out in their scroll area (from its top), which then measures them
local function SheetLayout()
    local bottom = sheet.body:Layout(PAD, -4)
    sheet.area:SetHeight(-bottom + 12)
end

SetSheet = function(open)
    dock.sheetOpen = open
    ui.gear = dock.gear
    dock.gear.open = open
    dock.gear:Tint()
    if open then
        sheet:Show()
        SheetLayout()
    else
        dock.body:Show()
    end
    -- one panel, two pages: the settings slide in from the dock's left edge inside the same panel
    -- (the dock clips them), pushing the dock's own content right as it fades; back reverses it
    St.Animate("fn-sheet", open and 1 or 0, 0.3, open and "out" or "in", function(v)
        local x = -DOCK_W * (1 - v)
        sheet:SetAlpha(0.3 + 0.7 * v)
        sheet:ClearAllPoints()
        sheet:SetPoint("TOPLEFT", dock, "TOPLEFT", x, 0)
        sheet:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT", x, 0)
        dock.body:SetAlpha(1 - v)
        dock.body:ClearAllPoints()
        dock.body:SetPoint("TOPLEFT", dock, "TOPLEFT", 48 * v, 0)
        dock.body:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT", 48 * v, 0)
    end, function()
        if open then dock.body:Hide() else sheet:Hide() end
    end)
end

-- ------------------------------------------------------------
-- The dashboard (the Fieldnotes tab): Show and When, then one row per profession with how
-- many, where most, and the skill toward its cap. Hovering a row lights that profession's dots
-- on the map; a click opens its tab.
-- ------------------------------------------------------------
local DASH_ROW = 34
local ROW_GAP = 4 -- between rows
local CARD_PAD = 6 -- the card's inner edge to its rows
local function DashRow(parent, p, width)
    local r = CreateFrame("Button", nil, parent)
    r:SetSize(width, DASH_ROW)
    r.p = p
    -- hover: the profession's color washes in from the bar and fades across the row
    r.wash = r:CreateTexture(nil, "BACKGROUND")
    r.wash:SetAllPoints()
    r.wash:SetTexture(St.Media("fade"))
    r.wash:SetVertexColor(p.color[1], p.color[2], p.color[3], 0.22)
    r.wash:Hide()
    -- the profession's color down the row's edge (the tabs carry its icon), brighter on hover
    r.bar = r:CreateTexture(nil, "ARTWORK")
    r.bar:SetColorTexture(p.color[1], p.color[2], p.color[3], 1)
    r.bar:SetPoint("TOPLEFT", 0, -4)
    r.bar:SetPoint("BOTTOMLEFT", 0, 4)
    r.bar:SetWidth(2)
    r.bar:SetAlpha(0.7)
    r.name = St.Text(r, 11, C.TEXT)
    r.name:SetPoint("TOPLEFT", 12, -5)
    r.name:SetText(p.label)
    r.count = St.Text(r, 11, C.TEXT)
    r.count:SetPoint("TOPRIGHT", -8, -5)
    r.count:SetJustifyH("RIGHT")
    r.sub = St.Text(r, 9, C.SUBTEXT)
    r.sub:SetPoint("TOPLEFT", 12, -19)
    r.sub:SetWidth(width - 12 - 58)
    r.sub:SetWordWrap(false)
    r.skill = St.Text(r, 9, C.SUBTEXT)
    r.skill:SetPoint("TOPRIGHT", -8, -19)
    r.skill:SetJustifyH("RIGHT")
    -- the skill toward its cap, a hairline under the row
    r.track = r:CreateTexture(nil, "ARTWORK")
    r.track:SetColorTexture(0.18, 0.165, 0.14, 1)
    r.track:SetHeight(1)
    r.track:SetPoint("BOTTOMLEFT", 12, 2)
    r.track:SetPoint("BOTTOMRIGHT", -8, 2)
    r.fill = r:CreateTexture(nil, "ARTWORK", nil, 1)
    r.fill:SetColorTexture(p.color[1], p.color[2], p.color[3], 0.9)
    r.fill:SetHeight(1)
    r.fill:SetPoint("BOTTOMLEFT", r.track, "BOTTOMLEFT")
    local function Lit(on)
        r.wash:SetShown(on)
        r.bar:SetAlpha(on and 1 or 0.7)
        M.SetLit(on and p.key or nil)
    end
    r:SetScript("OnEnter", function() Lit(true) end)
    r:SetScript("OnLeave", function() Lit(false) end)
    r:SetScript("OnClick", function(self) if self.tabbed then GoTo(p.key) end end)

    function r:Update(sum)
        local n = sum and sum.n or 0
        local rank, cap = 0, nil
        if p.key ~= "cloth" and FN.ProfessionSkill then rank, cap = FN.ProfessionSkill(p.key) end
        rank = rank or 0
        self.count:SetText(n > 0 and FormatCount(n) or "-")
        local sub
        if n == 0 then
            sub = "nothing yet"
        elseif p.key == "cloth" and sum.loots > 0 then
            sub = string.format("%d%% drop rate", math.floor(n / sum.loots * 100 + 0.5))
        else
            sub = sum.bestZone and ("most in " .. sum.bestZone) or ""
        end
        self.sub:SetText(sub)
        if p.key == "cloth" then
            self.skill:SetText(sum and sum.loots > 0 and (FormatCount(sum.loots) .. " loots") or "")
        elseif rank > 0 then
            self.skill:SetText(cap and (rank .. " / " .. cap) or tostring(rank))
        else
            self.skill:SetText("not learned")
        end
        local frac = (rank > 0 and cap and cap > 0) and math.min(1, rank / cap) or 0
        self.track:SetShown(frac > 0)
        self.fill:SetShown(frac > 0)
        if frac > 0 then self.fill:SetWidth(math.max(1, (width - 20) * frac)) end
        self.name:SetAlpha(n > 0 and 1 or 0.5)
        self.count:SetAlpha(n > 0 and 1 or 0.5)
    end
    return r
end

-- 1,279
FormatCount = function(n)
    local s = tostring(math.floor(n))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

-- the scrolling part of a dock page: under the title, over the session row
local SCROLL_TOP = 46
local SCROLL_BOTTOM = FOOTER_H + 8 + 34 + 6
local function DockScroll(parent)
    local o = St.Scroll(parent)
    o.scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -SCROLL_TOP)
    o.scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -6, SCROLL_BOTTOM)
    o.content:SetWidth(DOCK_W - 6)
    return o
end

Dashboard = function(parent)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetAllPoints()
    holder:Hide()
    holder.area = DockScroll(holder)
    local d = holder.area.content
    local w3 = (INNER - 6) / 3
    local y = FIRST_Y + SCROLL_TOP
    Label(d, "SHOW"):SetPoint("TOPLEFT", PAD, y)
    d.shows = {}
    for i, sh in ipairs(SHOWS) do
        local b = Choice(d, sh.label, function()
            M.S().show = sh.key
            Refresh()
        end, sh.tip)
        b.key = sh.key
        b:SetSize(w3, CTRL_H)
        b:SetPoint("TOPLEFT", PAD + (i - 1) * (w3 + 3), y - LABEL_GAP)
        d.shows[i] = b
    end
    y = y - STEP
    Label(d, "WHEN"):SetPoint("TOPLEFT", PAD, y)
    d.whens = {}
    for i, wh in ipairs(WHENS) do
        local b = Choice(d, wh[2], function()
            M.S().when = wh[1]
            Refresh()
        end)
        b.key = wh[1]
        b:SetSize(w3, CTRL_H)
        b:SetPoint("TOPLEFT", PAD + (i - 1) * (w3 + 3), y - LABEL_GAP)
        d.whens[i] = b
    end
    y = y - STEP
    d.card = St.Frame("Frame", d)
    St.Etch(d.card, STYLE.card or STYLE.row, 4)
    d.card:SetPoint("TOPLEFT", PAD, y)
    d.card:SetWidth(INNER)
    d.rows = {}
    for i, p in ipairs(M.PROFS) do
        local r = DashRow(d.card, p, INNER - CARD_PAD * 2)
        r:SetPoint("TOPLEFT", CARD_PAD, -CARD_PAD - (i - 1) * (DASH_ROW + ROW_GAP))
        d.rows[i] = r
    end
    local cardH = CARD_PAD * 2 + #M.PROFS * (DASH_ROW + ROW_GAP) - ROW_GAP
    d.card:SetHeight(cardH)

    d.bottom = -y + cardH + 12
    function holder:Update()
        local s = M.S()
        for _, b in ipairs(d.shows) do b:SetChosen(b.key == s.show) end
        for _, b in ipairs(d.whens) do b:SetChosen(b.key == s.when) end
        local sum = M.Summary(s.show, s.when)
        local tabbed = {}
        for _, p in ipairs(TabProfs()) do tabbed[p.key] = true end
        for _, r in ipairs(d.rows) do
            r.tabbed = tabbed[r.p.key]
            r:Update(sum[r.p.key])
        end
        self.area:SetHeight(d.bottom)
    end
    holder.rows = d.rows
    return holder
end

local function BuildDock()
    dock = St.Frame("Frame", WorldMapFrame)
    St.Etch(dock, STYLE.dock, 12)
    St.Grime(dock, 0.25, 12, 0, 150, 220) -- as on Forever Goal Tracker's window: strongest at the top
    -- a profession page's glow: a large, soft radial light of its color, centred on the title's icon
    -- and reaching about halfway down, over the fill and grime and under everything else. Cut to
    -- the dock by its texture coordinates (it is the dock's own texture, so it cannot spill out).
    dock.glow = dock:CreateTexture(nil, "BACKGROUND", nil, -4)
    dock.glow:SetTexture(St.Media("radial"))
    dock.glow:SetPoint("TOPLEFT", 3, -3)
    dock.glow:SetPoint("BOTTOMRIGHT", -3, 3)
    dock.glow:SetAlpha(0)
    function dock:SetGlow(p)
        local w, h = self:GetWidth() or 0, self:GetHeight() or 0
        if p and w > 0 and h > 0 then
            local R = h * 0.5 -- radius: about halfway down the dock
            local cx, cy = PAD + 8 - 3, PAD + 10 - 3 -- the icon, from the glow's top-left
            local iw, ih = w - 6, h - 6
            self.glow:SetTexCoord(0.5 - cx / (2 * R), 0.5 + (iw - cx) / (2 * R),
                0.5 - cy / (2 * R), 0.5 + (ih - cy) / (2 * R))
            self.glow:SetVertexColor(p.color[1], p.color[2], p.color[3])
        end
        local target = p and 0.16 or 0
        if self.glowKey ~= (p and p.key) then
            self.glowKey = p and p.key
            St.Animate("fn-page-glow", 0, 0, nil, function(v) self.glow:SetAlpha(v) end)
        end
        St.Animate("fn-page-glow", target, 0.4, "out", function(v) self.glow:SetAlpha(v) end)
    end
    dock:SetWidth(DOCK_W)
    dock:EnableMouse(true)
    dock:Hide()
    dock.body = CreateFrame("Frame", nil, dock)
    dock.body:SetAllPoints()
    local body = dock.body

    -- the title (the profession, or Fieldnotes on the dashboard) and the switch; the place under it
    dock.switch = Switch(body)
    dock.switch:SetPoint("TOPRIGHT", -PAD, -PAD - 1)
    dock.icon = ProfMark(body, 16)
    dock.icon:SetPoint("TOPLEFT", PAD, -PAD - 1)
    dock.prof = St.Title(body, 15)
    dock.prof:SetPoint("TOPLEFT", PAD, -PAD - 2)
    dock.place = St.Text(body, 10, C.SUBTEXT)
    dock.place:SetPoint("TOPLEFT", PAD, -PAD - 23)
    dock.place:SetJustifyH("LEFT")
    dock.place:SetWidth(INNER - 44)
    dock.place:SetWordWrap(false)

    -- a profession's page; the dashboard (Dashboard below) takes its place for "all"
    dock.page = CreateFrame("Frame", nil, body)
    dock.page:SetAllPoints()
    local shared = body
    body = dock.page
    local y = FIRST_Y
    dock.viewLabel = Label(body, "VIEW")
    dock.viewLabel:SetPoint("TOPLEFT", PAD, y)
    -- "Every skin": one dot per skin over Heat or Spotlight (Points shows them already). A small
    -- switch, at three quarters of the main one's size, on the View label's line
    local DS = 0.75
    dock.dots = CreateFrame("Button", nil, body)
    dock.dots:SetScale(DS)
    dock.dots:SetSize(36, 18)
    dock.dots.toggle = St.Toggle(dock.dots)
    dock.dots.toggle:SetAllPoints()
    dock.dots:SetPoint("RIGHT", body, "TOPRIGHT", -PAD / DS, (y - 5) / DS)
    dock.dots:SetScript("OnClick", function()
        if M.S().mode == "points" then return end
        M.S().dots = not M.S().dots
        Refresh()
    end)
    dock.dots:SetScript("OnEnter", function(self)
        local s = M.S()
        if s.mode ~= "points" then self.toggle:SetOn(s.dots, true) end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Every skin", C.TITLE[1], C.TITLE[2], C.TITLE[3])
        GameTooltip:AddLine(s.mode == "points" and "Points already shows every skin."
            or "Lay one dot per skin over the heat.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    dock.dots:SetScript("OnLeave", function(self)
        self.toggle:SetOn(M.S().dots and M.S().mode ~= "points")
        GameTooltip:Hide()
    end)
    dock.dotsLabel = St.Text(body, 10, C.INK2)
    dock.dotsLabel:SetText("Every skin") -- "Every vein" and so on, set in RenderDock
    dock.dotsLabel:SetPoint("RIGHT", dock.dots, "LEFT", -6, 0)
    local w3 = (INNER - 6) / 3
    dock.modes = {}
    for i, m in ipairs(MODES) do
        local b = Choice(body, m.label, function()
            M.S().mode = m.key
            Refresh()
        end, m.tip)
        b.key = m.key
        b:SetSize(w3, CTRL_H)
        b:SetPoint("TOPLEFT", PAD + (i - 1) * (w3 + 3), y - LABEL_GAP)
        dock.modes[i] = b
    end
    y = y - STEP
    dock.showLabel = Label(body, "SHOW")
    dock.showLabel:SetPoint("TOPLEFT", PAD, y)
    dock.shows = {}
    for i, sh in ipairs(SHOWS) do
        local b = Choice(body, sh.label, function()
            M.S().show = sh.key
            Refresh()
        end, sh.tip)
        b.key = sh.key
        b:SetSize(w3, CTRL_H)
        b:SetPoint("TOPLEFT", PAD + (i - 1) * (w3 + 3), y - LABEL_GAP)
        dock.shows[i] = b
    end
    y = y - STEP
    dock.matLabel = Label(body, "LEATHER")
    dock.matLabel:SetPoint("TOPLEFT", PAD, y)
    dock.leather = LeatherButton(body)
    dock.leather:SetSize(INNER, 24)
    dock.leather:SetPoint("TOPLEFT", PAD, y - LABEL_GAP)
    y = y - LABEL_GAP - 24 - GROUP_GAP
    dock.key = KeyCard(body, INNER, true)
    dock.key:SetPoint("TOPLEFT", PAD, y)
    body = shared
    dock.dash = Dashboard(body)
    dock.session = SessionCard(body, INNER)

    -- the settings page: no panel of its own, it rises inside the dock (which clips it)
    dock:SetClipsChildren(true)
    sheet = CreateFrame("Frame", nil, dock)
    sheet:SetFrameLevel(dock:GetFrameLevel() + 20)
    sheet:SetAllPoints(dock)
    sheet:EnableMouse(true)
    sheet:Hide()
    local title = St.Title(sheet, 15)
    title:SetPoint("TOPLEFT", PAD + 16, -PAD - 2)
    title:SetText("Settings")
    -- back, not close: a chevron pointing the way the settings leave (left, back to the dock)
    local close = St.IconButton(sheet, "chevron-white", 11, function() SetSheet(false) end)
    close.icon:SetRotation(-math.pi / 2)
    close:SetPoint("TOPLEFT", PAD - 2, -PAD - 3)
    close:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(C.TITLE[1], C.TITLE[2], C.TITLE[3])
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Back", 1, 1, 1)
        GameTooltip:Show()
    end)
    close:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(C.INK2[1], C.INK2[2], C.INK2[3])
        GameTooltip:Hide()
    end)
    sheet.area = St.Scroll(sheet)
    sheet.area.scroll:SetPoint("TOPLEFT", sheet, "TOPLEFT", 0, -40)
    sheet.area.scroll:SetPoint("BOTTOMRIGHT", sheet, "BOTTOMRIGHT", -6, PAD)
    sheet.area.content:SetWidth(DOCK_W - 6)
    sheet.body = SettingsBody(sheet.area.content, INNER, true)

    -- the tab that folds the dock away and back: "Fieldnotes" down its length, and a chevron
    -- pointing the way it will go (out when folded, back toward the map when open)
    tab = St.Frame("Button", WorldMapFrame)
    St.Etch(tab, STYLE.dock, 12)
    St.Grime(tab, 0.25, 12, 0.53, 150, 220)
    tab:SetSize(TAB_W, TAB_H)
    -- "Fieldnotes" turned a quarter clockwise to read top to bottom, as in the mockup; a client
    -- whose text cannot turn stacks the letters instead
    tab.letters = St.Title(tab, 13)
    tab.letters:SetJustifyH("CENTER")
    if tab.letters.SetRotation and pcall(tab.letters.SetRotation, tab.letters, -math.pi / 2) then
        tab.letters:SetText("Fieldnotes")
        -- the tab is only as long as the word, its chevron and a little room around them
        local w = tab.letters:GetStringWidth()
        if type(w) ~= "number" or w <= 0 then w = 64 end
        local tabH = math.floor(TAB_TOP + w + TAB_GAP + 10 + TAB_BOTTOM + 0.5)
        tab:SetHeight(tabH)
        -- the game turns a font string about the top centre of its box, so the turned word sits
        -- half a line left of that point: place the point half a line right of where it should go
        local h = tab.letters:GetStringHeight()
        if type(h) ~= "number" or h <= 0 then h = 13 end
        tab.letterX, tab.letterY = h / 2, tabH / 2 - TAB_TOP - w / 2
        tab.letters:SetPoint("TOP", tab, "CENTER", tab.letterX, tab.letterY)
    else
        tab.letters:SetText("F\ni\ne\nl\nd\nn\no\nt\ne\ns")
        tab.letters:SetPoint("TOP", 0, -12)
    end
    tab.chevron = tab:CreateTexture(nil, "OVERLAY")
    tab.chevron:SetTexture(St.Icon("chevron-white"))
    tab.chevron:SetVertexColor(C.TITLE[1], C.TITLE[2], C.TITLE[3])
    tab.chevron:SetSize(10, 10)
    tab.chevron:SetPoint("BOTTOM", 0, TAB_BOTTOM)
    -- the Fieldnotes tab only opens and closes the dock; opening lands on Home (the dashboard)
    tab:SetScript("OnClick", function()
        if list then list:Hide() end
        if DockOpen() then
            if dock.sheetOpen then SetSheet(false) end
            FN.db.settings.dockOpen = false
        else
            FN.db.settings.dockOpen = true
            local s = M.S()
            if s.prof ~= "all" then
                s.prof = "all"
                M.SetLit(nil)
                Refresh()
            end
        end
        MapUI.Render(model)
    end)
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(DockOpen() and "Close" or "Open", 1, 1, 1)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tab:Hide()

    -- The rail's tabs (Home, a tab per profession, Stats, Settings) share one look: every icon
    -- the same quiet silver at rest, on the plain tab; hovered, it brightens and the tab glides out
    -- a little; active, it glides out further, its icon takes its color (a profession's, or gold),
    -- and a soft light of that color rises from the edge it shares with the dock, washing out
    -- across the tab. Nothing glows around the icon (it muddied the icon, Karl). One value per tab (out: 0 at
    -- rest, 0.4 hovered, 1 active) drives all of it, eased, so every change glides.
    local function RailTab(icon, color, name, tipText, onClick)
        local t = St.Frame("Button", WorldMapFrame)
        St.Etch(t, STYLE.dock, 8)
        t:SetSize(TAB_W, PROF_TAB_H)
        t.color = color
        t.out, t.tuck = 0, 0
        t.rest, t.active, t.hover = false, false, false -- (rest: an icon color other than silver)
        t.id = "fn-rail-" .. icon
        t.page = false -- the copy of the page shown while active (PageCopy, made on first use)
        t.mark = CreateFrame("Frame", nil, t)
        t.mark:SetSize(16, 16) -- one size for the whole rail: the icon set is balanced to it
        t.icon = t.mark:CreateTexture(nil, "ARTWORK")
        t.icon:SetAllPoints()
        t.icon:SetTexture(St.Icon(icon))
        t:SetScript("OnClick", onClick)
        t:SetScript("OnEnter", function(self)
            self.hover = true
            Glide(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(name, color[1], color[2], color[3])
            if tipText then GameTooltip:AddLine(tipText, 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        t:SetScript("OnLeave", function(self)
            self.hover = false
            Glide(self)
            GameTooltip:Hide()
        end)
        t:Hide()
        ApplyTab(t)
        return t
    end

    -- Home: the dashboard, Codex's book
    homeTab = RailTab("book-white", C.TITLE, "Home", "All your professions", function() GoTo("all") end)
    homeTab.p = { key = "all" }
    homeTab.rec = homeTab:CreateTexture(nil, "OVERLAY") -- (never shown: only professions record)
    homeTab.rec:Hide()

    -- one tab per profession
    profTabs = {}
    for i, p in ipairs(M.PROFS) do
        local t = RailTab(PROF_ICONS[p.key], p.color, p.label, nil, function() GoTo(p.key) end)
        t.p = p
        -- a green dot while this session records it
        t.rec = t.mark:CreateTexture(nil, "OVERLAY", nil, 2)
        t.rec:SetTexture(CIRCLE)
        t.rec:SetSize(5, 5)
        t.rec:SetVertexColor(GREEN[1], GREEN[2], GREEN[3])
        t.rec:SetPoint("TOPRIGHT", t.mark, "TOPRIGHT", 4, 4)
        profTabs[i] = t
    end

    -- Stats and Settings, at the dock's bottom. Settings opens the settings page inside the dock
    -- (at rest its icon turns a darker gold while anything differs from the defaults); Stats opens
    -- the stats window.
    dock.stats = RailTab("stats-white", C.TITLE, "Stats", "Your gathering stats", function()
        FN.ToggleStats()
        MapUI.Render(model)
    end)
    dock.stats.p = false
    function dock.stats:Tint() ApplyTab(self) end
    dock.gear = RailTab("gear-white", C.TITLE, "Settings", "Map colors, strength and spread, sessions, and sharing",
        function()
            if not DockOpen() then
                FN.db.settings.dockOpen = true
                MapUI.Render(model)
            end
            SetSheet(not dock.sheetOpen)
            MapUI.Render(model)
        end)
    dock.gear.p = false
    function dock.gear:Tint()
        local s = M.S()
        local changed = s.colors ~= M.DEFAULTS.colors or math.abs(s.strength - M.DEFAULTS.strength) > 0.01
            or math.abs(s.spread - M.DEFAULTS.spread) > 0.01
        self.rest = changed and C.GOLD2 or false
        ApplyTab(self)
    end
    utilTabs[1], utilTabs[2] = dock.stats, dock.gear
end

-- which side of the small map the dock goes on, and the gap between the map's art and the
-- window's own edge
-- the map window's visible edge: its border frame where the client has one (the window itself
-- is wider than its border, which left an 18px gap beside the dock on Era, 2026-11-03)
local function MapEdge()
    local f = WorldMapFrame.BorderFrame
    if not (type(f) == "table" and f.GetRight and f:GetRight()) then f = WorldMapFrame end
    return f:GetRight() or 0, f:GetLeft() or 0
end

local function DockSide()
    local container = WorldMapFrame.ScrollContainer or WorldMapFrame
    local right, left = MapEdge()
    local screen = UIParent:GetRight() or 0
    local q = WorldMapFrame.QuestLog
    local quest = type(q) == "table" and q.IsShown and q:IsShown()
    local roomRight = screen - right >= DOCK_W + TAB_W + 4
    local roomLeft = left >= DOCK_W + TAB_W + 4
    -- gap: from the map art's edge to the window's outer edge, less the border frame's empty
    -- margin, so the dock touches the window's gold edge
    if (quest or not roomRight) and roomLeft then
        return "LEFT", left - (container:GetLeft() or left) + EDGE_TUCK
    end
    if roomRight or not roomLeft then return "RIGHT", (container:GetRight() or right) - right + EDGE_TUCK end
    return "LEFT", left - (container:GetLeft() or left) + EDGE_TUCK
end

local function LayoutDock()
    local container = WorldMapFrame.ScrollContainer or WorldMapFrame
    local side, gap = DockSide()
    local open = DockOpen()
    -- the window's full height, its title bar to its footer, tucked inside its gold edge at both
    -- ends the same, so the dock reads as part of the map window (it started at the map art)
    local border = WorldMapFrame.BorderFrame
    if not (type(border) == "table" and border.GetBottom and border:GetBottom()) then border = WorldMapFrame end
    local inset = EDGE_TUCK - 2
    local top, bottom, artTop = border:GetTop(), border:GetBottom(), container:GetTop()
    local dy = 0
    if top and bottom and artTop and top > bottom then
        dock:SetHeight(top - bottom - inset * 2)
        dy = (top - inset) - artTop
    else
        dock:SetHeight(container:GetHeight())
    end
    local edge = side == "RIGHT" and "TOPLEFT" or "TOPRIGHT"
    local mapEdge = side == "RIGHT" and "TOPRIGHT" or "TOPLEFT"
    local dir = side == "RIGHT" and 1 or -1

    -- the rail: Fieldnotes, then the profession tabs, a gap, Stats and Settings. Only the
    -- Fieldnotes tab shows while the dock is folded; the rest arrive and leave with the dock.
    local s = M.S()
    local shown = {}
    for _, p in ipairs(TabProfs()) do shown[p.key] = true end
    wipe(shownTabs)
    for _, t in ipairs(profTabs) do
        if shown[t.p.key] then shownTabs[#shownTabs + 1] = t else t:Hide() end
    end
    local rail = { homeTab }
    MapUI.rail = rail
    for _, t in ipairs(shownTabs) do rail[#rail + 1] = t end
    for _, t in ipairs(utilTabs) do rail[#rail + 1] = t end

    -- slide in and out sideways from the map's edge, the rail with it
    -- (only a fold or unfold animates; any other redraw just places it)
    local moving = dock.wasOpen ~= nil and dock.wasOpen ~= open
    dock.wasOpen = open
    St.Animate("fn-dock", open and 1 or 0, moving and 0.28 or 0, open and "out" or "in", function(v)
        dock:SetAlpha(v)
        dock:ClearAllPoints()
        dock:SetPoint(edge, container, mapEdge, dir * (-gap + 24 * (v - 1)), dy)
        -- open, the tab grows by what hides under the dock, and its word and chevron stay centred
        -- on the part that shows
        local tuck = TAB_TUCK * v
        tab:SetWidth(TAB_W + tuck)
        -- (less one unit: the dock's border art stops a little short of its frame, seen in game)
        local shift = (side == "RIGHT" and 1 or -1) * (tuck / 2 - v)
        if tab.letterX then
            tab.letters:ClearAllPoints()
            tab.letters:SetPoint("TOP", tab, "CENTER", tab.letterX + shift, tab.letterY)
        end
        tab.chevron:ClearAllPoints()
        tab.chevron:SetPoint("BOTTOM", tab, "BOTTOM", shift, TAB_BOTTOM)
        tab:ClearAllPoints()
        if side == "RIGHT" then
            tab:SetPoint("TOPLEFT", container, "TOPRIGHT", -gap + (DOCK_W - TAB_TUCK) * v, dy - TAB_DROP)
        else
            tab:SetPoint("TOPRIGHT", container, "TOPLEFT", gap - (DOCK_W - TAB_TUCK) * v, dy - TAB_DROP)
        end
        -- the profession tabs hang under it; Stats and Settings sit at the dock's bottom (but never
        -- over the profession tabs on a short dock). All as wide, fading with the dock.
        local below = 0
        local nUtil = #utilTabs
        -- (offsets from the Fieldnotes tab's bottom edge, which sits TAB_DROP under the dock's top)
        local profBottom = -(#shownTabs + 1) * (PROF_TAB_H + PROF_TAB_GAP)
        local utilTop = -(dock:GetHeight() - TAB_DROP * 2) + (tab:GetHeight() or 0)
            + nUtil * PROF_TAB_H + (nUtil - 1) * PROF_TAB_GAP
        utilTop = math.min(utilTop, profBottom - UTIL_GAP)
        for i, t in ipairs(rail) do
            if t == utilTabs[1] then below = utilTop + PROF_TAB_GAP end
            below = below - PROF_TAB_GAP
            t.tuck = tuck
            ApplyTab(t)
            t:SetAlpha(v)
            t:ClearAllPoints()
            if side == "RIGHT" then
                t:SetPoint("TOPLEFT", tab, "BOTTOMLEFT", 0, below)
            else
                t:SetPoint("TOPRIGHT", tab, "BOTTOMRIGHT", 0, below)
            end
            below = below - PROF_TAB_H
            t.mark:ClearAllPoints()
            t.mark:SetPoint("CENTER", t, "CENTER", shift, 0)
        end
    end, function()
        if not DockOpen() then
            dock:Hide()
            -- back to rest, so the active tab glides out again on the next open
            for _, t in ipairs(rail) do
                t:Hide()
                t.active, t.hover = false, false
                Glide(t, true)
            end
        end
    end)
    if open then dock:Show() end
    -- the tab sits just under the dock, so its inner edge hides beneath the dock's border
    tab:SetFrameLevel(math.max(1, (dock:GetFrameLevel() or 2) - 1))
    tab:Show()
    for _, t in ipairs(rail) do
        if open or moving then t:Show() end
        t:SetFrameLevel(tab:GetFrameLevel())
        -- the wash is strongest at the dock and fades outward
        if t.side ~= side then
            t.side = side
            ApplyTab(t)
        end
        local active
        if t.p then
            active = not dock.sheetOpen and s.prof == t.p.key
            t.rec:SetShown(t.p.key ~= "all" and FN.SessionHas and FN.SessionHas(t.p.key) or false)
        elseif t == dock.gear then
            active = dock.sheetOpen == true
        else
            active = FN.StatsShown and FN.StatsShown() or false
        end
        active = open and active
        if t.active ~= active then
            t.active = active
            Glide(t)
        end
    end
    dock.gear:Tint()
    -- the chevron points out when folded, back toward the map when open
    local outward = side == "RIGHT" and math.pi / 2 or -math.pi / 2
    tab.chevron:SetRotation(open and -outward or outward)
end

local function RenderDock(m)
    local s = M.S()
    dock.switch.toggle:SetOn(s.on)
    local dash = s.prof == "all"
    local p = M.PROF[s.prof]
    dock.icon:Set(p)
    dock.prof:ClearAllPoints()
    dock.prof:SetPoint("TOPLEFT", PAD + (p and 22 or 0), -PAD - 2)
    dock.prof:SetText(dash and "Fieldnotes" or p.label)
    dock.place:SetText(dash and ("All professions" .. (m.place and ("  ·  " .. m.place) or "")) or (m.place or ""))
    dock.page:SetShown(not dash)
    dock.dash:SetShown(dash)
    dock:SetGlow((not dash and not dock.sheetOpen) and p or nil)
    if dash then
        dock.dash:Update()
        dock.session:ClearAllPoints()
        dock.session:SetPoint("BOTTOMLEFT", dock.body, "BOTTOMLEFT", PAD, FOOTER_H + 8)
        dock.session:Update()
        dock.dash:SetAlpha(s.on and 1 or 0.45)
        dock.gear:Tint()
        if dock.sheetOpen then SheetLayout() end
        return
    end
    dock.matLabel:SetText(string.upper(p.material))
    -- the section labels take the profession's hue at the grey's own lightness, so they sit exactly
    -- where the grey did in the hierarchy, just warmer or cooler with the page
    local lc = LabelTint(p.color)
    for _, l in ipairs({ dock.viewLabel, dock.showLabel, dock.matLabel }) do l:SetTextColor(lc[1], lc[2], lc[3]) end
    dock.dotsLabel:SetText("Every " .. p.unit)
    for _, b in ipairs(dock.modes) do b:SetChosen(b.key == s.mode) end
    for _, b in ipairs(dock.shows) do b:SetChosen(b.key == s.show) end
    dock.leather:Update()
    local points = s.mode == "points"
    dock.dots.toggle:SetOn(s.dots and not points)
    -- the session row first, so the key can measure the room above it
    dock.session:ClearAllPoints()
    dock.session:SetPoint("BOTTOMLEFT", dock.body, "BOTTOMLEFT", PAD, FOOTER_H + 8)
    -- the key holds the hot spots; when the dock is short it drops its caption, then spots
    local room = dock:GetHeight() - DOCK_TOP_H - 6 - 34 - (FOOTER_H + 8)
    local keyTop, sessionTop = dock.key:GetTop(), dock.session:GetTop()
    if type(keyTop) == "number" and type(sessionTop) == "number" and keyTop > sessionTop then
        room = keyTop - sessionTop - 5
    end
    dock.key:Update(m, room > 40 and room or nil)
    dock.session:Update()
    -- switched off, everything below the switch steps back
    local a = s.on and 1 or 0.45
    for _, f in ipairs({ dock.modes[1], dock.modes[2], dock.modes[3], dock.shows[1], dock.shows[2], dock.shows[3],
        dock.leather, dock.key }) do
        f:SetAlpha(a)
    end
    -- the Every skin switch also steps back in Points, which shows every skin already
    dock.dots:SetAlpha(a * (points and 0.4 or 1))
    dock.dotsLabel:SetAlpha(a * (points and 0.4 or 1))
    dock.gear:Tint()
    if dock.sheetOpen then SheetLayout() end
end

-- ------------------------------------------------------------
-- The toolbar and key (full-screen map)
-- ------------------------------------------------------------
local hud, bar, hudKey, pop

local function SetPop(open)
    pop.open = open
    bar.gear.open = open
    bar.gear:Tint()
    if open then
        pop:Show()
        local bottom = pop.body:Layout(14, -14)
        pop:SetHeight(-bottom + 14)
    end
    -- drops from the gear: a short slide down and a fade
    St.Animate("fn-pop", open and 1 or 0, 0.22, open and "out" or "in", function(v)
        pop:SetAlpha(v)
        pop:ClearAllPoints()
        pop:SetPoint("TOPRIGHT", bar.gear, "BOTTOMRIGHT", 14, -14 + 8 * (1 - v))
    end, function()
        if not open then pop:Hide() end
    end)
end

local function BuildToolbar()
    local container = WorldMapFrame.ScrollContainer or WorldMapFrame
    hud = CreateFrame("Frame", nil, container)
    hud:SetAllPoints(container)
    hud:EnableMouse(false)

    bar = St.Frame("Frame", hud)
    St.Etch(bar, STYLE.panel, 12, 0.94)
    bar:SetHeight(36)
    bar:EnableMouse(true)
    bar:SetClipsChildren(true)
    bar.title = St.Title(bar, 14)
    bar.title:SetText("Fieldnotes")
    bar.switch = Switch(bar)
    bar.modes, bar.shows = {}, {}
    for i, m in ipairs(MODES) do
        local b = Choice(bar, m.label, function()
            M.S().mode = m.key
            Refresh()
        end, m.tip)
        b.key = m.key
        bar.modes[i] = b
    end
    for i, sh in ipairs(SHOWS) do
        local b = Choice(bar, sh.label, function()
            M.S().show = sh.key
            Refresh()
        end, sh.tip)
        b.key = sh.key
        bar.shows[i] = b
    end
    bar.leather = LeatherButton(bar)
    -- the session chip: Start with play; while running, its clock and skins (click to pause)
    bar.session = Choice(bar, "Start", function()
        if FN.SessionRunning() then FN.SessionTogglePause() else FN.SessionStart() end
        MapUI.Render(model)
    end, "Start, pause or resume your session")
    bar.session.icon = bar.session:CreateTexture(nil, "OVERLAY")
    bar.session.icon:SetSize(9, 9)
    bar.session.icon:SetPoint("LEFT", 9, 0)
    bar.session.text:ClearAllPoints()
    bar.session.text:SetPoint("LEFT", 24, 0)
    bar.stop = St.IconButton(bar, "stop-white", 9, function() -- stop, not close: it ends the session
        FN.SessionEnd()
        MapUI.Render(model)
    end)
    bar.stop:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("End session", 1, 1, 1)
        GameTooltip:Show()
    end)
    bar.stop:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar.stats = Choice(bar, "Stats", function() FN.ToggleStats() end, "Your skinning stats")
    bar.share = Choice(bar, "Share", function() FN.ShowShare() end, "Share your notes, or import someone else's")
    bar.gear = GearButton(bar, function() SetPop(not pop.open) end)
    bar.dividers = {}
    for i = 1, 4 do
        local d = Rule(bar)
        d:SetSize(1, 18)
        bar.dividers[i] = d
    end
    local elapsed = 0
    bar:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 1 then
            elapsed = 0
            if FN.SessionRunning() and bar:IsShown() then MapUI.Render(model) end
        end
    end)

    hudKey = KeyCard(hud, 260)

    pop = St.Frame("Frame", hud)
    St.Etch(pop, STYLE.panel, 12)
    pop:SetWidth(300)
    pop:EnableMouse(true)
    pop:Hide()
    pop.body = SettingsBody(pop, 272)
end

-- lay the toolbar out left to right; switched off it narrows to the name and switch, keeping
-- its centre (the centre of the map)
local function LayoutToolbar(m)
    local s = M.S()
    local x = 12
    bar.title:ClearAllPoints()
    bar.title:SetPoint("LEFT", bar, "LEFT", x, 0)
    x = x + bar.title:GetStringWidth() + 10
    bar.switch:ClearAllPoints()
    bar.switch:SetPoint("LEFT", bar, "LEFT", x, 0)
    x = x + 36 + 10
    local closedW = x
    local function Place(f, w)
        f:SetWidth(w)
        f:ClearAllPoints()
        f:SetPoint("LEFT", bar, "LEFT", x, 0)
        x = x + w + 3
    end
    local function Divider(i)
        bar.dividers[i]:ClearAllPoints()
        bar.dividers[i]:SetPoint("LEFT", bar, "LEFT", x + 3, 0)
        x = x + 10
    end
    Divider(1)
    for _, b in ipairs(bar.modes) do
        Place(b, math.ceil(b.text:GetStringWidth()) + 18)
        b:SetChosen(b.key == s.mode)
    end
    x = x + 3
    Divider(2)
    for _, b in ipairs(bar.shows) do
        Place(b, math.ceil(b.text:GetStringWidth()) + 18)
        b:SetChosen(b.key == s.show)
    end
    x = x + 3
    Divider(3)
    bar.leather:Update()
    Place(bar.leather, 150)
    x = x + 3
    Divider(4)
    local running, paused = FN.SessionRunning(), FN.SessionPaused()
    if running then
        bar.session.text:SetText(Clock(FN.SessionSeconds()) .. "  ·  " .. FN.SessionLabel())
        bar.session.icon:SetTexture(St.Icon(paused and "play-white" or "pause-white"))
    else
        bar.session.text:SetText("Start session")
        bar.session.icon:SetTexture(St.Icon("play-white"))
    end
    bar.session.icon:SetVertexColor(C.INK2[1], C.INK2[2], C.INK2[3])
    Place(bar.session, math.ceil(bar.session.text:GetStringWidth()) + 34)
    bar.stop:SetShown(running)
    if running then
        bar.stop:ClearAllPoints()
        bar.stop:SetPoint("LEFT", bar, "LEFT", x + 2, 0)
        x = x + 18
    end
    Place(bar.stats, math.ceil(bar.stats.text:GetStringWidth()) + 18)
    Place(bar.share, math.ceil(bar.share.text:GetStringWidth()) + 18)
    bar.gear:ClearAllPoints()
    bar.gear:SetPoint("LEFT", bar, "LEFT", x + 6, 0)
    bar.gear:Tint()
    local openW = x + 6 + 16 + 12
    -- narrow from both sides about the centre when switched off; widen back when on
    -- only switching on or off animates; a redraw (the session clock, a filter) just resizes
    local moving = bar.wasOn ~= nil and bar.wasOn ~= s.on
    bar.wasOn = s.on
    St.Animate("fn-bar", s.on and openW or closedW, moving and 0.3 or 0, s.on and "out" or "in", function(v)
        bar:SetWidth(v)
        local inner = (v - closedW) / math.max(1, openW - closedW)
        for _, f in ipairs({ bar.modes[1], bar.modes[2], bar.modes[3], bar.shows[1], bar.shows[2], bar.shows[3],
            bar.leather, bar.session, bar.stop, bar.stats, bar.share, bar.gear,
            bar.dividers[1], bar.dividers[2], bar.dividers[3], bar.dividers[4] }) do
            f:SetAlpha(inner)
        end
    end)
    bar:ClearAllPoints()
    bar:SetPoint("TOP", hud, "TOP", 0, -10)

    -- the key: bottom corner, fading and drifting down when switched off
    hudKey:Update(m)
    local corner = m.keyCorner or "BOTTOMLEFT"
    St.Animate("fn-key", s.on and 1 or 0, moving and 0.3 or 0, s.on and "out" or "in", function(v)
        hudKey:SetAlpha(v)
        hudKey:ClearAllPoints()
        hudKey:SetPoint(corner, hud, corner, corner == "BOTTOMRIGHT" and -10 or 10, 10 - 12 * (1 - v))
    end)
    if pop.open then
        local bottom = pop.body:Layout(14, -14)
        pop:SetHeight(-bottom + 14)
    end
end

-- ------------------------------------------------------------
-- Choosing a layout and drawing it
-- ------------------------------------------------------------
local function Maximized()
    if WorldMapFrame.IsMaximized then
        local ok, v = pcall(WorldMapFrame.IsMaximized, WorldMapFrame)
        if ok then return v and true or false end
    end
    local w, sw = WorldMapFrame:GetWidth() or 0, UIParent:GetWidth() or 0
    return sw > 0 and w >= sw * 0.9
end

-- the dock needs room beside the map; without it the toolbar comes in, as on the full-screen map
local function UseDock()
    if Maximized() then return false end
    local right, left = MapEdge()
    local screen = UIParent:GetRight() or 0
    return screen - right >= DOCK_W + TAB_W + 4 or left >= DOCK_W + TAB_W + 4
end

function MapUI.Render(m)
    if not dock then return end
    model = m or model
    local docked = UseDock()
    ui.layout = docked and "dock" or "toolbar"
    -- shared with tools/check.py and the gear and Reset in the open settings
    ui.gear = docked and dock.gear or bar.gear
    ui.reset = docked and sheet.body.reset or pop.body.reset
    if list and list:IsShown() then FillList() end
    if docked then
        bar:Hide()
        hudKey:Hide()
        if pop.open then SetPop(false) end
        LayoutDock()
        RenderDock(model)
    else
        dock:Hide()
        tab:Hide()
        if dock.sheetOpen then SetSheet(false) end
        bar:Show()
        hudKey:Show()
        LayoutToolbar(model)
    end
end

function MapUI.Layer(strata)
    if not hud then return end
    hud:SetFrameStrata(strata)
    hud:SetFrameLevel(1000)
    pop:SetFrameLevel(bar:GetFrameLevel() + 10)
end

function MapUI.Debug(Size)
    FN.Print("  layout " .. tostring(ui.layout) .. "; dock " .. Size(dock) .. "; tab " .. Size(tab))
    FN.Print("  toolbar " .. Size(bar) .. "; key " .. Size(hudKey))
    local k = dock and dock.key
    if k then
        local room, shown, h = rawget(k, "lastRoom"), rawget(k, "lastSpots"), k:GetHeight()
        local all = type(model.spots) == "table" and #model.spots or 0
        FN.Print(string.format("  dock key: room %s, height %.1f, hot spots %d of %d",
            type(room) == "number" and string.format("%.1f", room) or "none", type(h) == "number" and h or 0,
            type(shown) == "number" and shown or 0, all))
    end
    -- the active tab: its copied page, the light over it, and their layers
    for _, t in ipairs({ homeTab, dock and dock.stats, dock and dock.gear, unpack(profTabs) }) do
        local page = t and rawget(t, "page")
        if t and rawget(t, "active") and page then
            local light = page.light
            local _, _, _, la = light:GetVertexColor()
            FN.Print(string.format("  active tab: out %.2f, page %s level %d, light frame level %d, light %s w %.1f alpha %.2f",
                rawget(t, "out") or 0, page:IsShown() and "shown" or "hidden", page:GetFrameLevel() or 0,
                t.mark:GetFrameLevel() or 0, light:IsShown() and "shown" or "hidden", light:GetWidth() or 0,
                la or 0))
        end
    end
end

function MapUI.Init()
    if dock then return end
    M = FN.Map
    ui = M.ui
    St.Animate("fn-overlay", M.S().on and 1 or 0, 0, nil, M.SetOverlayAlpha) -- where the fade starts from
    BuildList()
    BuildDock()
    MapUI.tab, MapUI.tabs, MapUI.home = tab, profTabs, homeTab -- for /fn debug and the checks
    MapUI.dock = dock
    -- for /fn shots: go to a page, open or close the settings
    function MapUI.GoTo(key) GoTo(key) end
    function MapUI.OpenSettings(open)
        if (dock.sheetOpen == true) ~= (open == true) then SetSheet(open == true) end
        MapUI.Render(model)
    end
    BuildToolbar()
    WorldMapFrame:HookScript("OnHide", function()
        if list then list:Hide() end
        if dock.sheetOpen then SetSheet(false) end
        if pop.open then SetPop(false) end
    end)
end
