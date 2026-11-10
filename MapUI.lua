local ADDON, FN = ...

-- The map's controls, built from the map v2 mockups (design/map-v2-2026-11-03):
--
--   Small map: a dock outside the map's edge (right, or left when there is no room or a quest
--   panel sits on the right), the full height of the map, so nothing of Fieldnotes covers the
--   map but the heat itself. A small Fieldnotes button in the map's top-right corner opens and
--   closes it (no slide since 2026-11-07); the dock has its own close X.
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
local DOCK_W = 272 -- (228 until stats v5 moved the stats into the dock, 2026-11-05)
local PAD = 12
local INNER = DOCK_W - PAD * 2
local TAB_W = 34 -- every tab beside the dock, the Fieldnotes tab and the rail alike: squares, like the character window's
local HOME_W, HOME_H = TAB_W, 34
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
    treasure = "treasure-white",
    money = "money-white",
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

-- a title or number in a profession's color: its hue lifted to read as bright text on the dock
-- (Mining red becomes a light coral), not the label's quiet grey step
local function NameTint(c)
    local function Lum(x) return 0.299 * x[1] + 0.587 * x[2] + 0.114 * x[3] end
    local k = 0.64 / math.max(0.05, Lum(c))
    local out = {}
    for i = 1, 3 do
        local v = math.min(1, c[i] * k)
        out[i] = v + (1 - v) * 0.12
    end
    return out
end
local function Hex(c)
    return string.format("%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5))
end

-- n skins, n catches: the profession's own word
local function Units(p, n)
    p = p or { unit = "gather", units = "gathers" }
    return n .. " " .. (n == 1 and p.unit or p.units)
end
local SHOWS = {
    { key = "me", label = "Me", tip = "This character only" },
    { key = "account", label = "Account", tip = "Every character on this account" },
    { key = "community", label = "Community", tip = "Everyone who has shared, merged", soon = true },
}
local SCHEME_NAMES = { thermal = "Thermal", solar = "Solar", frost = "Frost", plasma = "Plasma", viridis = "Viridis" }
local WHENS = { { 0, "All time" }, { 30, "30 days" }, { 7, "7 days" } }

local model = {}
local profTabs, shownTabs = {}, {}
local PROF_TAB_H, PROF_TAB_GAP = 34, 2 -- (gap 4 read loose, Karl 2026-11-06)
local dockClip -- the dock's clipping window (BuildDock)
local ProfMark, GoTo, Dashboard, FormatCount, SetSheet, ApplyTab, Glide -- defined with the dock
local homeTab, RefreshHome
local DOCK_GAP = 4 -- the dock stands this far off the map window's edge (Karl, 2026-11-07)
local MAP_BTN = 24 -- the map button, in the map's top-right corner
local MAP_BTN_INSET = 8 -- from the map art's corner
local MAP_BTN_GAP = 4 -- from another add-on's button
local btnX, btnY = -MAP_BTN_INSET, -MAP_BTN_INSET -- where CornerSpot put it, from the corner
local utilTabs = {} -- Stats and Settings, under the profession tabs after a little gap
local UTIL_GAP = 12
local TAB_DROP = 14 -- the rail's bottom margin, above the dock's bottom edge
-- The dock wears the game's own window frame (Karl, 2026-11-07): the map window's metal border, the
-- nine-slice layout without a portrait (WoW Forever draws it in bronze), as OpenMap does. Its top
-- piece is the title bar. A client without that layout keeps the etched edge and a dark strip.
local NINE_LAYOUT = NineSliceUtil and NineSliceUtil.GetLayout and NineSliceUtil.GetLayout("ButtonFrameTemplateNoPortrait")
    and "ButtonFrameTemplateNoPortrait" or nil
local TITLE_H = NINE_LAYOUT and 21 or 26 -- the dock's title bar (Karl, 2026-11-07: option A); 25 in Forever's panel
-- the frame's inner edge, left, top, right, bottom: where the fill goes (OpenMap's numbers for the
-- same layout; its top piece, the title bar, is the frame's own)
local FILL_IN = { 6, 21, 2, 3 }
-- WoW Forever (Karl, 2026-11-07, after Spoken Places' Place Story panel): the panel in the game's
-- DefaultPanelFlatTemplate, the Map & Quest Log family, as tall as the map window and a wider gap
-- off it, past any side tabs there; the Fieldnotes side tab back on the map's edge, shown while the
-- panel is closed (its close button closes it). Era keeps the corner button and the metal frame.
local FOREVER_GAP = 10 -- between the map window (or the side tabs on its edge) and the panel
local FLAT_FILL = { 7, 25, 5, 6 } -- the flat panel's inside, under its title bar (Spoken's numbers)
local SIDE_TAB_TOP = 30 -- the side tab's top below the map window's, as the character frame's first
local SIDE_TAB_GAP = 3 -- under another add-on's side tab
local COLUMN_SLACK = 12 -- how near the map's edge a side tab's left edge may sit
-- the rail tabs' edge beside the game's frame: its grey metal, not the brown etch (Era; Forever's
-- tabs wear the game's side tab art)
local TAB_METAL = { 0.46, 0.45, 0.43, 1 }
-- inside a game frame (the metal one on Era, the flat panel on Forever) the pages stand this much
-- further in from each side, and the panel is that much wider, so nothing crowds the frame's thick
-- edges (Karl, 2026-11-07, Forever). The pages keep their width (DOCK_W).
local SIDE_IN = 0 -- 8 in a game frame (BuildDock)
local function DockW() return DOCK_W + 2 * SIDE_IN end
local function RailTop() return TITLE_H + 8 end -- the rail's first tab, under the title bar

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

-- A Show button. Community is switched off until it ships ("Coming soon"): dimmed, never chosen,
-- and its click does nothing. Flip `soon` off in SHOWS to bring it back.
local function ShowChoice(parent, sh)
    local b = Choice(parent, sh.label, function()
        if sh.soon then return end
        M.S().show = sh.key
        Refresh()
    end, sh.tip)
    b.key = sh.key
    if sh.soon then
        b.soon = true
        b.text:SetAlpha(0.4)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(sh.label, 1, 1, 1)
            GameTooltip:AddLine("Coming soon", C.TITLE[1], C.TITLE[2], C.TITLE[3])
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
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
        St.Animate("fn-overlay", 1, St.DUR.slow, "soft", M.SetOverlayAlpha)
    else
        St.Animate("fn-overlay", 0, St.DUR.base, "leave", M.SetOverlayAlpha, Refresh)
        MapUI.Render(model) -- the controls follow straight away
    end
end

local function Switch(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(36, 18)
    b.toggle = St.Toggle(b)
    b.toggle:SetAllPoints()
    -- paint the switch from the saved state (called by every redraw, so it is right on load and
    -- changes the moment it is clicked, not after the mouse leaves)
    function b:Sync()
        self.toggle:SetOn(M.S().on, MouseIsOver and MouseIsOver(self) or false)
    end
    b:SetScript("OnClick", function(self)
        SetOn(not M.S().on)
        self:Sync()
    end)
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
-- The dropdown list: one, shared by every dropdown in the add-on. The button that opens it hands
-- over a provider: function() return items, chosenKey, onPick, ruleAfterZero end. An item is
-- { key, label, count?, color?, plain?, disabled? }: a color gives it a dot, plain gives it none,
-- disabled dims it and ignores clicks (Community: "Coming soon"). The leather list is the biggest
-- user: this map's leathers, most first, with how many; past six it scrolls (wheel, thin bar).
-- ------------------------------------------------------------
local list
local ROW_H, LIST_PAD, SPLIT = 22, 4, 9 -- row height, inner padding, the room the divider takes

local function FillList()
    local items, chosenKey, pick, ruleAfterZero = {}, nil, nil, false
    if list.provider then items, chosenKey, pick, ruleAfterZero = list.provider() end
    items = items or {}
    list.pick = pick
    local maxOffset = math.max(0, #items - LIST_ROWS)
    list.offset = math.max(0, math.min(list.offset or 0, maxOffset))
    local y = -LIST_PAD
    local split = false
    for i, row in ipairs(list.rows) do
        local item = items[list.offset + i]
        row:SetShown(item ~= nil)
        if item then
            row.key = item.key
            row.disabled = item.disabled and true or false
            row.text:SetText(item.label)
            row.count:SetText(item.count or "")
            row.dot:SetShown(not item.plain)
            row.text:ClearAllPoints()
            row.text:SetPoint("LEFT", item.plain and 12 or 25, 0)
            row.text:SetPoint("RIGHT", -44, 0)
            if item.color then
                row.dot:SetVertexColor(item.color[1], item.color[2], item.color[3], 1)
            else
                row.dot:SetVertexColor(0.3, 0.3, 0.3, 0.6) -- All: the same quiet dot as the button
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", list, "TOPLEFT", LIST_PAD, y)
            row:SetPoint("TOPRIGHT", list, "TOPRIGHT", -LIST_PAD - (#items > LIST_ROWS and 6 or 0), y)
            row:SetChosen(item.key == chosenKey)
            y = y - ROW_H
            -- a thin rule between "All leather" and the leathers themselves
            if ruleAfterZero and item.key == 0 and items[list.offset + i + 1] then
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
        if self.disabled then
            self.text:SetTextColor(C.SUBTEXT[1], C.SUBTEXT[2], C.SUBTEXT[3])
            self.bar:Hide()
            self.wash:SetVertexColor(1, 0.92, 0.70, 0)
            return
        end
        local c = self.chosen and C.TITLE or (self.hover and C.TEXT or C.INK2)
        self.text:SetTextColor(c[1], c[2], c[3])
        self.bar:SetShown(self.chosen)
        if self.chosen then
            self.wash:SetVertexColor(1, 0.96, 0.86, self.hover and 0.16 or 0.10)
        else
            self.wash:SetVertexColor(1, 0.92, 0.70, self.hover and 0.07 or 0)
        end
    end
    function row:SetChosen(on)
        self.chosen = on and not self.disabled
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
            if self.disabled then return end
            local pick = list.pick
            list:Hide()
            if pick then pick(self.key) end
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

local function ToggleList(owner, provider)
    if list:IsShown() and list.owner == owner then
        list:Hide()
        return
    end
    if list:IsShown() then list:Hide() end
    list.owner = owner
    list.provider = provider
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
local function LeatherProvider()
    return model.leathers or {}, model.leather, function(key)
        M.S().leather = key
        Refresh()
    end, true
end

local function LeatherButton(parent)
    local b = Choice(parent, "All leather", function(self) ToggleList(self, LeatherProvider) end)
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
        -- (nothing on this map yet: "All" and the open profession's word, ore, herbs, loot...)
        self.text:SetText(chosen and chosen.label or ("All " .. ((model.p and model.p.material) or "leather")))
        local c = chosen and chosen.color
        if c then
            self.dot:SetVertexColor(c[1], c[2], c[3])
        else
            self.dot:SetVertexColor(0.3, 0.3, 0.3, 0.6) -- All: an empty ring look
        end
    end
    return b
end

-- a plain dropdown button (no dot): the chosen item's label and a chevron
local function Dropdown(parent, provider)
    local b = Choice(parent, "", function(self) ToggleList(self, provider) end)
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", 11, 0)
    b.text:SetPoint("RIGHT", -22, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b.arrow = b:CreateTexture(nil, "OVERLAY")
    b.arrow:SetTexture(St.Icon("chevron-white"))
    b.arrow:SetVertexColor(C.INK2[1], C.INK2[2], C.INK2[3])
    b.arrow:SetSize(9, 9)
    b.arrow:SetPoint("RIGHT", -8, 0)
    function b:Update()
        local items, chosen = provider()
        for _, it in ipairs(items) do
            if it.key == chosen then self.text:SetText(it.label) end
        end
    end
    return b
end

local function ShowProvider()
    local items = {}
    for i, sh in ipairs(SHOWS) do
        items[i] = { key = sh.key, label = sh.label, plain = true, disabled = sh.soon,
            count = sh.soon and "Coming soon" or nil }
    end
    return items, M.S().show, function(key)
        M.S().show = key
        Refresh()
    end
end

local function WhenProvider()
    local items = {}
    for i, wh in ipairs(WHENS) do items[i] = { key = wh[1], label = wh[2], plain = true } end
    return items, M.S().when, function(key)
        M.S().when = key
        Refresh()
    end
end

-- ------------------------------------------------------------
-- The key: on this map, how many skins, what you skin most, and the scale
-- ------------------------------------------------------------
-- withSpots: the card also lists the hot spots the map pins, one line each (the dock's key); a
-- row and its pin light together (hover either), and a click on a row pings its pin
local SPOT_ROW = 19 -- (17 felt tight, Karl 2026-11-06)
-- Tooltips for the key's items go above the card, so they never cover its numbers
local function CardTip(owner, card)
    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("BOTTOMLEFT", card, "TOPLEFT", 0, 6)
end

local function SpotRow(k, i, width)
    local row = CreateFrame("Button", nil, k)
    row:SetSize(width - 10, SPOT_ROW)
    row.rank = i
    row.wash = St.Pill(row, SPOT_ROW - 1)
    row.wash:Anchor(row, 1, 1)
    row.wash:SetColor(1, 0.96, 0.86, 0)
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
    -- the spot's own heat color, a short pill where a count used to be: the order of the rows is
    -- the order of these colors (red first), so the ranking explains itself (Karl, 2026-11-06).
    -- Shown on Heat only, where the map wears the same colors.
    row.swatchBox = CreateFrame("Frame", nil, row)
    row.swatchBox:SetSize(22, 8)
    row.swatchBox:SetPoint("LEFT", 25, 0)
    row.swatch = St.Pill(row.swatchBox, 8, "ARTWORK")
    row.swatch:Anchor(row.swatchBox, 0, 0, 0)
    function row:SetSwatch(c)
        local on = c ~= nil
        self.swatchBox:SetWidth(on and 22 or 1)
        self.swatchBox:SetShown(on)
        if on then self.swatch:SetColor(c[1], c[2], c[3], 1) end
    end
    row.coords = St.Text(row, 9, C.SUBTEXT)
    row.coords:SetPoint("RIGHT", -5, 0)
    row.coords:SetJustifyH("RIGHT")
    row.who = St.Text(row, 10, C.SUBTEXT)
    row.who:SetPoint("LEFT", row.swatchBox, "RIGHT", 7, 0)
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
        self.wash:SetColor(1, 0.96, 0.86, on and 0.14 or 0)
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
        -- the same story as the pin's tooltip: which spot, why it ranks there, what is there
        if self.spot then
            local way = M.CanWaypoint(self.spot.map)
            CardTip(self, self:GetParent())
            GameTooltip:SetText("Hot spot " .. self.rank, C.TITLE[1], C.TITLE[2], C.TITLE[3])
            GameTooltip:AddLine(M.SpotRankText(self.rank), 1, 1, 1)
            if self.whoFull and self.whoFull ~= "" then
                GameTooltip:AddLine(self.whoFull, C.INK2[1], C.INK2[2], C.INK2[3], true)
            end
            if way then
                GameTooltip:AddLine(self.spot.coords .. "  ·  click to set a waypoint", C.SUBTEXT[1], C.SUBTEXT[2], C.SUBTEXT[3])
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.hover = false
        self:Paint()
        M.LightPin(self.rank, false)
        GameTooltip:Hide()
    end)
    -- a click pings the pin and, where a waypoint can be set (TomTom, or the game's own), sets one
    row:SetScript("OnClick", function(self)
        M.PingPin(self.rank)
        local by, title = M.Waypoint(self.spot)
        if by then FN.Print("Waypoint set: " .. title .. (by == "TomTom" and " (TomTom)" or "")) end
    end)
    row:Paint()
    return row
end

-- glass: the full-screen key lets the map show through, most at the top right, solid at the
-- bottom left where it meets the corner (a fill at GLASS alpha, and a radial of the same dark
-- centred on that corner bringing it back up to nearly solid)
local GLASS = 0.74
local GLASS_LIFT = 0.8
local function KeyCard(parent, width, withSpots, glass)
    local k = St.Frame("Frame", parent)
    St.Etch(k, STYLE.row, 12, glass and GLASS or nil)
    if glass then
        k.lift = k:CreateTexture(nil, "BACKGROUND", nil, -5)
        k.lift:SetTexture(St.Media("radial"))
        k.lift:SetVertexColor(0.045, 0.043, 0.04, GLASS_LIFT)
        k.lift:SetPoint("TOPLEFT", 3, -3)
        k.lift:SetPoint("BOTTOMRIGHT", -3, 3)
        -- the radial's centre sits on the card's bottom-left corner; cut to the card by its texture
        -- coordinates (so it cannot spill), and redone whenever the height changes
        function k:FitLift()
            local w, h = (self:GetWidth() or 0) - 6, (self:GetHeight() or 0) - 6
            if w <= 0 or h <= 0 then return end
            local R = math.max(w, h) * 1.15
            self.lift:SetTexCoord(0.5, 0.5 + w / (2 * R), 0.5 - h / (2 * R), 0.5)
        end
    end
    k:SetWidth(width)
    k.withSpots = withSpots == true
    if withSpots then
        k.spotRule = k:CreateTexture(nil, "ARTWORK")
        k.spotRule:SetColorTexture(0.33, 0.29, 0.20, 0.8)
        k.spotRule:SetHeight(1)
        -- one line over the rows that says how they are ordered, the rule running on from it
        k.spotHead = St.Text(k, 9, C.SUBTEXT)
        k.spotRows = {}
        for i = 1, 3 do k.spotRows[i] = SpotRow(k, i, width) end
    end
    k.big = St.Text(k, 18, C.TEXT)
    k.big:SetPoint("TOPLEFT", 11, -10)
    k.message = St.Text(k, 11, C.INK2)
    k.message:SetPoint("TOPLEFT", 11, -12)
    k.message:SetWidth(width - 22)
    k.message:SetJustifyV("TOP")
    k.message:SetSpacing(11 * 0.2) -- line height 120% of the 11 text (Karl, 2026-11-06)
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
    -- the legend's entries are buttons: a material shows only its own dots (click again for all,
    -- the same choice as the material list); on Home a profession opens its page
    k.legend = {}
    for i = 1, 5 do
        local b = CreateFrame("Button", nil, k)
        b.wash = St.Pill(b, 16)
        b.wash:Anchor(b, 0, 0)
        b.wash:SetColor(1, 0.96, 0.86, 0)
        local d = b:CreateTexture(nil, "ARTWORK")
        d:SetTexture(CIRCLE)
        d:SetSize(8, 8)
        local t = St.Text(b, 10, C.INK2)
        t:SetPoint("LEFT", d, "RIGHT", 5, 0)
        b:SetScript("OnEnter", function(self)
            local l = self.entry
            if not l then return end
            self.wash:SetColor(1, 0.96, 0.86, 0.14)
            CardTip(self, k)
            if l.prof then
                M.SetLit(l.prof)
                GameTooltip:SetText("Open " .. ((M.PROF[l.prof] and M.PROF[l.prof].label) or l.prof), 1, 1, 1)
            elseif M.S().leather == l.key then
                GameTooltip:SetText("Show all again", 1, 1, 1)
            else
                GameTooltip:SetText("Show only " .. l.label, 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        if b.RegisterForClicks then b:RegisterForClicks("LeftButtonDown") end -- act on press
        b:SetScript("OnLeave", function(self)
            self.wash:SetColor(1, 0.96, 0.86, 0)
            if self.entry and self.entry.prof then M.SetLit(nil) end
            GameTooltip:Hide()
        end)
        b:SetScript("OnClick", function(self)
            local l, st = self.entry, M.S()
            if not l then return end
            GameTooltip:Hide()
            if list then list:Hide() end
            if l.prof then
                M.SetProf(l.prof)
            else
                st.leather = (st.leather == l.key) and 0 or l.key
            end
            Refresh()
        end)
        -- Home's bars: a faint track, the profession's color up to its share of the busiest one,
        -- and its count at the right
        local box = CreateFrame("Frame", nil, b)
        box:SetHeight(5)
        local track, fill = St.Pill(box, 5, "BACKGROUND"), St.Pill(box, 5, "ARTWORK")
        local count = St.Text(b, 11, C.TEXT)
        count:SetJustifyH("RIGHT")
        box:Hide()
        count:Hide()
        k.legend[i] = { b = b, d = d, t = t, barBox = box, track = track, fill = fill, count = count }
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
            self.spotHead:SetShown(nSpots > 0)
            for i, row in ipairs(self.spotRows) do row:SetShown(i <= nSpots) end
        end
        self.big:SetShown(hasData)
        self.message:SetShown(not hasData)
        for _, r in ipairs(self.rows) do
            r.l:Hide()
            r.v:Hide()
        end
        -- (the legend's buttons are only hidden at the end, if still unused: hiding and showing the
        -- one under the cursor on every redraw can swallow a click)
        for _, l in ipairs(self.legend) do
            l.b.keep = false
            l.b.entry = nil
        end
        local showRamp = hasData and m.kind ~= "dash" and m.mode == "heat" or (hasData and m.kind == "continent")
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
            -- the card hugs the message: 12 above, 12 below (SetHeight adds the last 8)
            y = -12 - self.message:GetStringHeight() - 4
        else
            -- the number in the profession's color (Karl chose the strong page color, 2026-11-06)
            local n = m.skins or 0
            local word = (m.p and (n == 1 and m.p.unit or m.p.units)) or (n == 1 and "gather" or "gathers")
            if m.p and m.p.money then
                -- Money leads with the amount, its coin letters in their colors
                self.big:SetText(FN.FormatMoney(m.copper or 0) .. "  |cff999999in " .. n .. " " .. word .. "|r")
            elseif m.p and m.p.color then
                self.big:SetText("|cff" .. Hex(NameTint(m.p.color)) .. n .. "|r " .. word)
            else
                self.big:SetText(n .. " " .. word)
            end
            self.caption:SetText((m.p and m.p.units or "gathers") .. " in one spot")
            y = -34
            local rows
            local p = m.p or {}
            if m.kind == "continent" then
                rows = { { "Zones", m.zones and tostring(m.zones) }, { "Most " .. (p.units or ""), m.bestZone } }
            elseif nSpots > 0 or m.kind == "dash" then
                rows = {} -- the hot spots below name the creatures instead
            elseif m.prof == "fishing" then
                rows = { { "Main catch", m.topLoot } }
            elseif m.prof == "money" then
                rows = { { "Most from", m.topWho } } -- the amount is the big line
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
            elseif m.kind == "dash" and m.legend then
                -- Home: one row per profession, its share as a bar
                local btnW = width - 14
                local barLeft = 8 + 8 + 5 + 64
                local barW = btnW - barLeft - 8 - 30 - 6
                for i, l in ipairs(m.legend) do
                    local row = self.legend[i]
                    if not row then break end
                    row.b.entry = l
                    row.b:ClearAllPoints()
                    row.b:SetPoint("TOPLEFT", self, "TOPLEFT", 7, y - (i - 1) * 18)
                    row.b:SetSize(btnW, 17)
                    row.b:SetAlpha(1)
                    row.d:SetVertexColor(l.color[1], l.color[2], l.color[3])
                    row.d:ClearAllPoints()
                    row.d:SetPoint("LEFT", row.b, "LEFT", 8, 0)
                    row.t:SetText(l.label)
                    row.t:SetTextColor(C.INK2[1], C.INK2[2], C.INK2[3])
                    row.count:SetText(l.count)
                    row.count:ClearAllPoints()
                    row.count:SetPoint("RIGHT", row.b, "RIGHT", -8, 0)
                    row.barBox:ClearAllPoints()
                    row.barBox:SetPoint("LEFT", row.b, "LEFT", barLeft, 0)
                    row.barBox:SetSize(barW, 5)
                    row.track:Anchor(row.barBox, 0, 0)
                    row.track:SetColor(1, 0.94, 0.82, 0.09)
                    local fw = math.max(5, barW * (l.frac or 0))
                    row.fill:Anchor(row.barBox, 0, barW - fw)
                    row.fill:SetColor(l.color[1], l.color[2], l.color[3], 0.95)
                    row.barBox:Show()
                    row.count:Show()
                    row.b:Show()
                    row.b.keep = true
                end
                y = y - #m.legend * 18
            elseif m.legend then
                local x = 11
                local chosen = m.leather and m.leather ~= 0 and m.kind ~= "dash" and m.leather or nil
                for i, l in ipairs(m.legend) do
                    local row = self.legend[i]
                    if not row then break end
                    row.b.entry = l
                    row.d:SetVertexColor(l.color[1], l.color[2], l.color[3])
                    row.t:SetText(l.label)
                    local on = chosen == l.key
                    local c = on and C.TITLE or C.INK2
                    row.t:SetTextColor(c[1], c[2], c[3])
                    -- while one is chosen the rest step back, still there to click
                    row.b:SetAlpha((chosen and not on) and 0.45 or 1)
                    local w = 13 + row.t:GetStringWidth() + 10
                    if x > 11 and x + w + 6 > width - 8 then x, y = 11, y - 18 end
                    row.b:ClearAllPoints()
                    row.b:SetPoint("TOPLEFT", self, "TOPLEFT", x - 8, y + 3)
                    row.b:SetSize(w + 6, 16)
                    row.d:ClearAllPoints()
                    row.d:SetPoint("LEFT", row.b, "LEFT", 8, 0)
                    row.barBox:Hide()
                    row.count:Hide()
                    row.b:Show()
                    row.b.keep = true
                    x = x + w + 8
                end
                y = y - 18
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
            self.spotHead:SetText(m.mode == "heat" and "Hottest first" or "Busiest first")
            self.spotHead:ClearAllPoints()
            self.spotHead:SetPoint("TOPLEFT", self, "TOPLEFT", 11, y)
            self.spotRule:ClearAllPoints()
            self.spotRule:SetPoint("LEFT", self.spotHead, "RIGHT", 6, 0)
            self.spotRule:SetPoint("RIGHT", self, "RIGHT", -11, 0)
            y = y - 13
            for i = 1, nSpots do
                local sp, row = spots[i], self.spotRows[i]
                row:SetSwatch(m.mode == "heat" and sp.color or nil)
                -- coordinates only where a click can turn them into a waypoint
                row.coords:SetText(M.CanWaypoint(sp.map) and sp.coords or "")
                row.whoFull = sp.who ~= "" and sp.who or sp.loot
                row.spot = sp
                -- the first spot's badge and halo in the page's color (gold pulled focus from the total)
                if i == 1 then
                    local bc = (m.p and m.p.color) or C.ACCENT
                    row.badge:SetVertexColor(bc[1], bc[2], bc[3], 1)
                    row.halo:SetVertexColor(bc[1], bc[2], bc[3], 1)
                end
                row.who:SetText(sp.who ~= "" and sp.whoShort or sp.lootShort or row.whoFull)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", self, "TOPLEFT", 5, y)
                y = y - SPOT_ROW
            end
        end
        for _, l in ipairs(self.legend) do
            if not l.b.keep then
                l.b:Hide()
                l.barBox:Hide()
                l.count:Hide()
            end
        end
        -- (the dock's key leaves the note to the dock's header, demoInHeader, so it never costs a
        -- hot spot and every page drops the same lines in the same order)
        local demo = m.inDemo and not compact and not rawget(self, "demoInHeader")
        self.demo:SetShown(demo and true or false)
        if demo then
            self.demo:ClearAllPoints()
            self.demo:SetPoint("TOPLEFT", self, "TOPLEFT", 11, y - 2)
            y = y - 16
        end
        -- a fixed card (the full-screen key) keeps one height while you switch views, filters and
        -- pages, so it never jumps; the sample-data note sits on its bottom edge. Only content
        -- taller than that (a continent's long scale line) still grows it.
        local fixedH = rawget(self, "fixedH")
        if type(fixedH) == "number" then
            local h = math.max(-y + 8, fixedH)
            if self.demo:IsShown() then
                self.demo:ClearAllPoints()
                self.demo:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 11, 8)
            end
            self:SetHeight(h)
        else
            self:SetHeight(-y + 8)
        end
        if self.FitLift then self:FitLift() end
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
        if not FN.TrackerShown() then
            GameTooltip:AddLine("Click to open the session window", C.SUBTEXT[1], C.SUBTEXT[2], C.SUBTEXT[3])
        end
        GameTooltip:Show()
    end)
    sc:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- a click on a running session brings its window back (the pause and end icons keep their own clicks)
    sc:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" or not FN.SessionRunning() or not self:IsMouseOver() then return end
        FN.ShowTracker(true)
        self:GetScript("OnEnter")(self) -- the tooltip drops its "click to open" line
    end)

    function sc:Update()
        local running, paused = FN.SessionRunning(), FN.SessionPaused()
        self.start:SetShown(not running)
        self.pause:SetShown(running)
        self.stop:SetShown(running)
        self.detail:SetShown(true)
        self.glow:SetOn(running and not paused)
        if not running then
            self.dot:SetVertexColor(0.36, 0.35, 0.33)
            self.title:SetText("Session")
            self.title:SetTextColor(C.TITLE[1], C.TITLE[2], C.TITLE[3])
            -- the grey dot says "off"; a word beside it says so too
            self.detail:SetText("Idle")
            self.detail:SetTextColor(C.SUBTEXT[1], C.SUBTEXT[2], C.SUBTEXT[3])
            self.detail:SetWidth(40)
        else
            self.detail:SetTextColor(C.INK2[1], C.INK2[2], C.INK2[3])
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
    -- Darken map: the dimming layer between the zone art and the heat; only its alpha changes,
    -- so it follows the thumb live with no redraw
    b.dimLabel = Label(parent, "DARKEN MAP")
    b.dimValue = St.Text(parent, 10, C.INK2)
    b.dimValue:SetJustifyH("RIGHT")
    b.dimSlider = St.Slider(parent, width, 0, M.DIM_MAX, 0.01, function(v)
        M.S().dim = v
        b.dimValue:SetText(math.floor(v * 100 + 0.5) .. "%")
        M.SetDim(v)
    end)
    b.note = St.Text(parent, 10, C.SUBTEXT)
    b.note:SetWidth(width)
    b.note:SetText("Strength is how bold the heat is; spread, how wide each glow reaches; darken, how far the map dims beneath it.")
    -- hot spots: hidden until hovered (default), or every marker always showing
    b.spotsLabel = Label(parent, "HOT SPOTS")
    b.spotsText = St.Text(parent, 10, C.INK2)
    b.spotsText:SetText("Always show hot spots")
    b.spots = CreateFrame("Button", nil, parent)
    b.spots:SetSize(36, 18)
    b.spots.toggle = St.Toggle(b.spots)
    b.spots.toggle:SetAllPoints()
    b.spots:SetScript("OnClick", function(self)
        M.S().spotsShown = not M.S().spotsShown
        self.toggle:SetOn(M.S().spotsShown)
        Refresh()
    end)
    b.spots:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Always show hot spots", 1, 1, 1)
        GameTooltip:AddLine("Off: a hot spot's number and ring show when you hover it, or its row in the key.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b.spots:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
        s.colors, s.when, s.strength, s.spread, s.dim, s.leather = M.DEFAULTS.colors, M.DEFAULTS.when,
            M.DEFAULTS.strength, M.DEFAULTS.spread, M.DEFAULTS.dim, 0
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
        self.dimLabel:ClearAllPoints()
        self.dimLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        self.dimValue:ClearAllPoints()
        self.dimValue:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y)
        local dm = M.S().dim
        self.dimValue:SetText(math.floor(dm * 100 + 0.5) .. "%")
        y = y - 18
        self.dimSlider:ClearAllPoints()
        self.dimSlider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        self.dimSlider:Set(dm)
        y = y - 34
        self.note:ClearAllPoints()
        self.note:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        y = y - self.note:GetStringHeight() - 16
        self.reset:SetSize(width, 22)
        self.reset:ClearAllPoints()
        self.reset:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        y = y - 22 - 24
        self.spotsLabel:ClearAllPoints()
        self.spotsLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        y = y - 18
        self.spotsText:ClearAllPoints()
        self.spotsText:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 3)
        self.spots:ClearAllPoints()
        self.spots:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y)
        self.spots.toggle:SetOn(M.S().spotsShown)
        y = y - 18 - 24
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
            or math.abs(s.dim - M.DEFAULTS.dim) > 0.01
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
local StatsPlace -- (set beside RenderDock)

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
local LIGHT_PEAK = 0.24 -- at the outer edge; 0.14 and 0.2 did not show in game, 0.34 was a little strong (Karl, 2026-11-05)
-- The open tab's edge (Karl, 2026-11-05): one color for every tab, whatever its profession: the
-- chosen ivory since the neutral look (2026-11-10), gold being money's.
local EDGE_GOLD = C.ACCENT -- (the chosen ivory, STYLE.rowSel's edge)

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

-- the open tab's gold edge: three lines on the icon's frame (the layer that draws above the page
-- copy, as the light does), the outer one solid, top and bottom fading toward the dock
-- The open tab's frame, from the game's own art (Karl, 2026-11-05: the flat gold lines had no
-- rounded, bevelled corners): the side tab the character window uses (LargeSideTabButtonTemplate,
-- as the Fieldnotes tab is), chosen, without its icon or mouse, laid behind ours and fitted to the
-- part of the tab past the dock. Made once per tab; nil where the client has no such template.
local NATIVE_H = 54 -- the template's own height (seen in game, /fn debug 2026-11-05)
-- Every rail tab wears the game's side tab now (Karl, 2026-11-05, Forever: only the open tab had it,
-- and its art kept the template's own size, centred, so a dark gap sat at the dock's edge and the
-- tab's own etched box showed past the gold). Two copies per tab: the plain one always, the chosen
-- (gold) one over it at the tab's active strength, so the gold fades in as before. Each piece is
-- stretched to fill its frame, which is fitted to the part of the tab beside the dock.
local function NewArt(t, chosen)
    local ok, f = pcall(CreateFrame, "Frame", nil, t, "LargeSideTabButtonTemplate")
    if not (ok and f and type(f.Icon) == "table" and f.SetChecked) then return nil end
    f:EnableMouse(false)
    f.Icon:Hide()
    f:SetChecked(chosen)
    for _, r in ipairs({ f:GetRegions() }) do
        if r ~= f.Icon and r.GetObjectType and r:GetObjectType() == "Texture" then
            r:ClearAllPoints()
            r:SetAllPoints(f)
            -- the game's chosen art is gold: the neutral look turns it ivory (gold is money's)
            if chosen and r.SetDesaturated then
                pcall(r.SetDesaturated, r, true)
                r:SetVertexColor(1, 0.97, 0.88)
            end
        end
    end
    f:Hide()
    return f
end

local function TabArt(t)
    local art = rawget(t, "art")
    if art ~= nil then return art or nil end
    local plain = NewArt(t, false)
    local gold = plain and NewArt(t, true)
    if plain and gold then
        t.art, t.artOn = plain, gold
        return plain
    end
    t.art = false
end

local function FitArt(t, art, level)
    local h = t:GetHeight() or PROF_TAB_H
    local k = h / NATIVE_H
    local w = math.max(h, (t:GetWidth() or TAB_W) - (t.tuck or 0))
    art:SetScale(k)
    art:SetSize(w / k, NATIVE_H)
    art:ClearAllPoints()
    if t.side ~= "LEFT" then
        art:SetPoint("TOPRIGHT", t, "TOPRIGHT", 0, 0)
    else
        art:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0)
    end
    art:SetFrameLevel(level)
end

local function TabEdge(t, a)
    local metal = dock and rawget(dock, "nine") and TAB_METAL
    local art = TabArt(t)
    if art then
        local gold = t.artOn
        local show = t:IsShown()
        art:SetShown(show)
        gold:SetShown(show and a > 0.01)
        if not show then return end
        -- above the page's copy, under the icon: the plain frame, then the gold one over it
        local level = math.max(t:GetFrameLevel() + 1, (t.mark:GetFrameLevel() or 3) - 2)
        FitArt(t, art, level)
        if a > 0.01 then
            FitArt(t, gold, level + 1)
            gold:SetAlpha(a)
        end
        return
    end
    -- No template (Classic Era): the tab's own border, the game's rounded tooltip edge, turns gold
    -- as it opens, as the Fieldnotes tab's does there (the flat gold lines had square corners)
    if t.SetBackdropBorderColor then
        local r0 = metal or STYLE.dock.edge
        local g = EDGE_GOLD
        t:SetBackdropBorderColor(r0[1] + (g[1] - r0[1]) * a, r0[2] + (g[2] - r0[2]) * a, r0[3] + (g[3] - r0[3]) * a, 1)
    end
end

ApplyTab = function(t)
    local v = t.out or 0
    local a = math.max(0, (v - 0.4) / 0.6) -- how active it looks: nothing while only hovered
    t:SetWidth(TAB_W + (t.tuck or 0) + TAB_SLIDE * v)
    -- the icon's frame sits at one level, open or not, so the game art (two levels under it) is
    -- always above the tab's own fill and the page copy
    if dock then t.mark:SetFrameLevel(dock:GetFrameLevel() + 4 + 5) end
    TabEdge(t, a)
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
    t.mark:SetFrameLevel(base + 5)
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
    St.Animate(t.id, target, instant and 0 or St.DUR.base, "soft", function(v)
        t.out = v
        ApplyTab(t)
    end)
end

-- which professions get a tab: the ones this character knows, Cloth and Treasure for everyone, and in
-- Account or Community any profession with notes
local function TabProfs()
    local s, out = M.S(), {}
    local sum = M.Summary(s.show, 0)
    for _, p in ipairs(M.PROFS) do
        local known = p.anyone or (FN.ProfessionSkill and (FN.ProfessionSkill(p.key) or 0) > 0)
        local any = sum[p.key] and sum[p.key].n > 0
        if known or (s.show ~= "me" and any) or (FN.View() ~= FN.db and any) or s.prof == p.key then out[#out + 1] = p end
    end
    return out
end

-- go to a page ("all": the dashboard). The tab of the page already open folds the dock.
GoTo = function(key)
    local s = M.S()
    if list then list:Hide() end
    dock.statsOpen = false
    if dock.sheetOpen then
        SetSheet(false)
        if DockOpen() and s.prof == key then
            MapUI.Render(model)
            return
        end
    end
    FN.db.settings.dockOpen = true
    if s.prof ~= key then
        M.SetProf(key)
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
    if open then dock.statsOpen = false end
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
    St.Animate("fn-sheet", open and 1 or 0, St.DUR.slow, open and "soft" or "leave", function(v)
        local x = -(DOCK_W + SIDE_IN) * (1 - v)
        sheet:SetAlpha(0.3 + 0.7 * v)
        sheet:ClearAllPoints()
        sheet:SetPoint("TOPLEFT", dock, "TOPLEFT", SIDE_IN + x, -TITLE_H)
        sheet:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT", -SIDE_IN + x, 0)
        dock.body:SetAlpha(1 - v)
        dock.body:ClearAllPoints()
        dock.body:SetPoint("TOPLEFT", dock, "TOPLEFT", SIDE_IN + 48 * v, -TITLE_H)
        dock.body:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT", -SIDE_IN + 48 * v, 0)
    end, function()
        if open then dock.body:Hide() else sheet:Hide() end
    end)
end

-- ------------------------------------------------------------
-- The dashboard (the Fieldnotes tab): Show and When, then one row per profession with how
-- many, where most, and the skill toward its cap. Hovering a row lights that profession's dots
-- on the map; a click opens its tab.
-- ------------------------------------------------------------
local DASH_ROW = 40
local ROW_GAP = 4 -- between rows
local CARD_PAD = 6 -- the card's inner edge to its rows
local ROW_RIGHT = 22 -- the right text stops here, leaving room for the chevron
local ORANGE = { 0.95, 0.60, 0.22 }
local function DashRow(parent, p, width)
    local r = CreateFrame("Button", nil, parent)
    r:SetSize(width, DASH_ROW)
    -- the hover area reaches half the gap up and down, so neighbouring rows meet (no dead strip)
    r:SetHitRectInsets(0, 0, -ROW_GAP / 2, -ROW_GAP / 2)
    r.p = p
    -- hover (option C, Karl 2026-11-06): the row lifts a step, a short glow of the profession's
    -- color leaves the bar and is gone a third of the way in, and the name takes the color.
    -- (A wash across the whole row came out muddy on Mining's red and Treasure's yellow.)
    r.lift = r:CreateTexture(nil, "BACKGROUND", nil, -1)
    r.lift:SetAllPoints()
    r.lift:SetColorTexture(1, 0.95, 0.85, 0.05)
    r.lift:Hide()
    r.wash = r:CreateTexture(nil, "BACKGROUND")
    r.wash:SetPoint("TOPLEFT", 0, 0)
    r.wash:SetPoint("BOTTOMLEFT", 0, 0)
    r.wash:SetWidth(math.floor(width * 0.35))
    r.wash:SetTexture(St.Media("fade"))
    r.wash:SetVertexColor(p.color[1], p.color[2], p.color[3], 0.18) -- (0.26 read a tad strong, Karl)
    r.wash:Hide()
    r.nameLit = NameTint(p.color)
    -- the profession's color down the row's edge (the tabs carry its icon), brighter on hover
    r.bar = r:CreateTexture(nil, "ARTWORK")
    r.bar:SetColorTexture(p.color[1], p.color[2], p.color[3], 1)
    r.bar:SetPoint("TOPLEFT", 0, -4)
    r.bar:SetPoint("BOTTOMLEFT", 0, 4)
    r.bar:SetWidth(2)
    r.bar:SetAlpha(0.7)
    r.name = St.Text(r, 11, C.TEXT)
    r.name:SetPoint("TOPLEFT", 12, -6)
    r.name:SetText(p.label)
    r.count = St.Text(r, 11, C.TEXT)
    r.count:SetPoint("TOPRIGHT", -ROW_RIGHT, -6)
    r.count:SetJustifyH("RIGHT")
    r.sub = St.Text(r, 9, C.SUBTEXT)
    r.sub:SetPoint("TOPLEFT", 12, -21)
    r.sub:SetWidth(width - 12 - ROW_RIGHT - 66)
    r.sub:SetWordWrap(false)
    r.skill = St.Text(r, 9, C.SUBTEXT)
    r.skill:SetPoint("TOPRIGHT", -ROW_RIGHT, -21)
    r.skill:SetJustifyH("RIGHT")
    -- the skill toward its cap, a slim rounded bar at the row's foot
    local barY = -(DASH_ROW / 2) + 5
    r.track = St.Pill(r, 3, "ARTWORK")
    r.track:Anchor(r, 12, ROW_RIGHT, barY)
    r.track:SetColor(0.20, 0.185, 0.16, 1)
    r.fill = St.Pill(r, 3, "ARTWORK", 1)
    -- a chevron that arrives on hover: this row opens something
    r.chev = r:CreateTexture(nil, "OVERLAY")
    r.chev:SetTexture(St.Icon("chevron-white"))
    r.chev:SetSize(10, 10)
    r.chev:SetRotation(math.pi / 2) -- the icon points down; this turns it to point right
    r.chev:SetPoint("RIGHT", -7, 0)
    r.chev:SetVertexColor(C.INK2[1], C.INK2[2], C.INK2[3])
    r.chev:SetAlpha(0)
    local function Lit(on)
        r.wash:SetShown(on)
        r.lift:SetShown(on)
        r.bar:SetAlpha(on and 1 or 0.7)
        r.bar:SetWidth(on and 3 or 2)
        local c = on and r.nameLit or C.TEXT
        r.name:SetTextColor(c[1], c[2], c[3])
        -- the chevron arrives in the profession's color too
        local cc = on and r.nameLit or C.INK2
        r.chev:SetVertexColor(cc[1], cc[2], cc[3])
        St.Animate("fn-chev-" .. p.key, on and 1 or 0, St.DUR.quick, "soft", function(v)
            r.chev:SetAlpha(v)
            r.chev:ClearAllPoints()
            r.chev:SetPoint("RIGHT", -7 - 4 * (1 - v), 0)
        end)
        M.SetLit(on and p.key or nil)
    end
    r:SetScript("OnEnter", function() Lit(true) end)
    r:SetScript("OnLeave", function() Lit(false) end)
    -- every row opens its page, even a profession with nothing yet (the page says so)
    r:SetScript("OnClick", function() GoTo(p.key) end)

    function r:Update(sum)
        local n = sum and sum.n or 0
        local here = sum and sum.here or 0
        local rank, cap = 0, nil
        if not p.anyone and FN.ProfessionSkill then rank, cap = FN.ProfessionSkill(p.key) end
        rank = rank or 0
        local learned = p.anyone or rank > 0
        -- a profession you do not have and have never gathered folds into one line under the card
        self.collapsed = (n == 0 and not learned)
        -- the count, with its unit
        if p.money then -- Money counts its amount, not its loots
            self.count:SetText(n > 0 and FN.FormatMoney(sum.copper or 0) or "")
        else
            self.count:SetText(n > 0 and (FormatCount(n) .. " " .. (n == 1 and p.unit or p.units)) or "")
        end
        -- the line under the name: what is on this map, else where you gather most, else why not
        local sub
        if n == 0 then
            sub = learned and "No gathers yet" or "Not learned"
        elseif here > 0 then
            sub = FormatCount(here) .. " here"
        else
            sub = sum.bestZone and ("most in " .. sum.bestZone) or ""
        end
        self.sub:SetText(sub)
        -- and its right-hand twin: skill toward the cap, a capped note, or cloth's drop rate
        local frac, capped = 0, false
        local text, color = "", C.SUBTEXT
        if p.money then
            if n > 0 then text = FormatCount(n) .. " " .. (n == 1 and p.unit or p.units) end
        elseif p.key == "cloth" then
            if n > 0 and sum.loots > 0 then
                text = string.format("%d%% drop rate", math.floor(n / sum.loots * 100 + 0.5))
            end
        elseif rank > 0 then
            capped = (cap and cap > 0 and cap < 300 and rank >= cap) and true or false
            if capped then
                text, color = "Capped, train next rank", ORANGE
            else
                text = cap and ("Skill " .. rank .. " / " .. cap) or ("Skill " .. rank)
            end
            frac = (cap and cap > 0) and math.min(1, rank / cap) or 0
        end
        self.skill:SetText(text)
        self.skill:SetTextColor(color[1], color[2], color[3])
        for _, t in ipairs({ self.track.l, self.track.m, self.track.r, self.fill.l, self.fill.m, self.fill.r }) do
            t:SetShown(frac > 0)
        end
        if frac > 0 then
            local full = width - 12 - ROW_RIGHT
            self.fill:Anchor(self, 12, width - 12 - math.max(3, full * frac), barY)
            local c = capped and ORANGE or p.color
            self.fill:SetColor(c[1], c[2], c[3], 0.95)
        end
        local live = n > 0
        self.name:SetAlpha(live and 1 or (learned and 0.7 or 0.5))
        self.count:SetAlpha(live and 1 or 0.5)
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
    -- Show and When: two dropdowns on one row, no section labels (they say what they are)
    local w2 = (INNER - 6) / 2
    local y = FIRST_Y + SCROLL_TOP
    d.show = Dropdown(d, ShowProvider)
    d.show:SetSize(w2, CTRL_H)
    d.show:SetPoint("TOPLEFT", PAD, y)
    d.when = Dropdown(d, WhenProvider)
    d.when:SetSize(w2, CTRL_H)
    d.when:SetPoint("TOPLEFT", PAD + w2 + 6, y)
    y = y - CTRL_H - 16
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
    -- a line under the card: the whole, in one sentence
    -- the folded professions, dimmed, in one line
    d.folded = St.Text(d, 9, C.SUBTEXT)
    d.folded:SetPoint("TOPLEFT", d.card, "BOTTOMLEFT", 2, -8)
    d.folded:SetWidth(INNER - 4)
    d.folded:SetJustifyH("LEFT")
    d.folded:SetAlpha(0.6)
    d.total = St.Text(d, 10, C.SUBTEXT)
    d.total:SetWidth(INNER - 4)
    d.total:SetJustifyH("LEFT")

    function holder:Update()
        local s = M.S()
        d.show:Update()
        d.when:Update()
        local sum = M.Summary(s.show, s.when)
        local total, pros = 0, 0
        local shown, folded = 0, {}
        for _, r in ipairs(d.rows) do
            r:Update(sum[r.p.key])
            local n = sum[r.p.key] and sum[r.p.key].n or 0
            total = total + n
            if n > 0 then pros = pros + 1 end
            if r.collapsed then
                r:Hide()
                folded[#folded + 1] = r.p.label
            else
                r:Show()
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", CARD_PAD, -CARD_PAD - shown * (DASH_ROW + ROW_GAP))
                shown = shown + 1
            end
        end
        local h = CARD_PAD * 2 + shown * (DASH_ROW + ROW_GAP) - ROW_GAP
        d.card:SetHeight(h)
        local below = d.card
        local gap = 8
        if #folded > 0 then
            d.folded:SetText("Not learned: " .. table.concat(folded, " · "))
            d.folded:Show()
            below = d.folded
            gap = 8
        else
            d.folded:Hide()
        end
        d.total:ClearAllPoints()
        d.total:SetPoint("TOPLEFT", below, "BOTTOMLEFT", below == d.card and 2 or 0, -gap - (below == d.folded and 6 or 0))
        d.total:SetText(total > 0
            and (FormatCount(total) .. " gathers across " .. pros .. (pros == 1 and " profession" or " professions"))
            or (#folded >= #d.rows - 1
                and "No gathering profession learned yet. Learn one and it shows up here, and its first gather starts a session."
                or "Nothing gathered yet. Your first gather starts a session."))
        d.bottom = -y + h + 8 + (#folded > 0 and 24 or 0) + 36 + 12
        self.area:SetHeight(d.bottom)
    end
    holder.rows = d.rows
    return holder
end

-- where the game's own window (ButtonFrameTemplate) keeps its close button: read once from a
-- throwaway copy, hidden. Falls back to the corner offset the game's portrait windows use.
local function GameCloseSpot()
    local spot = { p = "TOPRIGHT", rp = "TOPRIGHT", x = 4, y = 5, from = "fallback" }
    local ok, f = pcall(CreateFrame, "Frame", nil, UIParent, "ButtonFrameTemplate")
    if not (ok and type(f) == "table") then return spot end
    f:Hide()
    local cb = rawget(f, "CloseButton")
    if cb and cb.GetPoint then
        local p, rel, rp, x, y = cb:GetPoint(1)
        -- (only when it hangs on the window itself; on a title piece the offsets would not carry)
        if type(p) == "string" and (rel == f or rel == nil) and type(x) == "number" then
            spot = { p = p, rp = type(rp) == "string" and rp or p, x = x, y = type(y) == "number" and y or 0,
                w = cb:GetWidth(), h = cb:GetHeight(), from = "the game's window" }
        end
    end
    return spot
end

local function BuildDock()
    -- The dock, its tab and the rail live inside a clipping window that starts at the dock's resting
    -- edge and runs outward. Sliding toward the map, they are cut off there, as if they came out
    -- from behind the map window, rather than crossing its gold border and parchment.
    -- (Placed on the dock's side by LayoutDock.)
    dockClip = CreateFrame("Frame", nil, WorldMapFrame)
    dockClip:SetClipsChildren(true)
    dockClip:EnableMouse(false)
    dockClip:SetSize(DOCK_W + TAB_W + 80, 1000)
    dock = St.Frame("Frame", dockClip)
    -- Forever: the game's side tab (LargeSideTabButtonTemplate), as before 2026-11-07 and as Spoken
    -- Places hangs one. A client without it (Era) gets the corner button below.
    local okTab, native = pcall(CreateFrame, "Frame", "FieldnotesMapTab", WorldMapFrame, "LargeSideTabButtonTemplate")
    if okTab and native and type(native.Icon) == "table" and native.Icon.SetTexture and native.SetCustomOnMouseUpHandler then
        tab = native
        tab.native = true
    end
    if tab then
        local okFlat, flat = pcall(CreateFrame, "Frame", nil, dock, "DefaultPanelFlatTemplate")
        if okFlat and type(flat) == "table" and type(rawget(flat, "SetTitle")) == "function" then
            flat:SetAllPoints()
            flat:SetFrameLevel(dock:GetFrameLevel())
            flat:SetTitle("Fieldnotes")
            flat:EnableMouse(false)
            -- its own background goes: the fill below is the page
            local bg = rawget(flat, "Bg")
            if bg and bg.Hide then bg:Hide() end
            -- its border over the pages, its title over the border
            local nine = rawget(flat, "NineSlice")
            if nine and nine.SetFrameLevel then nine:SetFrameLevel(dock:GetFrameLevel() + 25) end
            local title = rawget(flat, "TitleContainer")
            if title and title.SetFrameLevel then title:SetFrameLevel(dock:GetFrameLevel() + 30) end
            dock.flat = flat
            TITLE_H = FLAT_FILL[2]
        end
    end
    if NINE_LAYOUT and not rawget(dock, "flat") then
        local ok, nine = pcall(CreateFrame, "Frame", nil, dock, "NineSlicePanelTemplate")
        if ok and nine and pcall(NineSliceUtil.ApplyLayoutByName, nine, NINE_LAYOUT) then
            nine:SetAllPoints()
            -- over the page's contents (the settings page slides in under it, clipped) and under
            -- the title and close button
            nine:SetFrameLevel(dock:GetFrameLevel() + 25)
            dock.nine = nine
        end
    end
    -- the fill: the brown window fill and its grime, inside the frame's inner edge (the dock's
    -- whole rectangle poked out past the game frame's cut corners, Karl 2026-11-07). On its own
    -- frame at the dock's level, so the pages (one level up) draw over it.
    local fi = rawget(dock, "flat") and FLAT_FILL or (rawget(dock, "nine") and FILL_IN or { 3, 3, 3, 3 })
    dock.fillIn = fi
    local fill = dock
    if rawget(dock, "nine") or rawget(dock, "flat") then
        fill = CreateFrame("Frame", nil, dock)
        fill:SetPoint("TOPLEFT", fi[1], -fi[2])
        fill:SetPoint("BOTTOMRIGHT", -fi[3], fi[4])
        fill:SetFrameLevel(dock:GetFrameLevel())
        St.Etch(fill, STYLE.dock, 0) -- (no edge: the game's frame is the edge)
        fill.etchHi:Hide()
        St.Grime(fill, 0.25, 0, 0, 150, 220)
    else
        St.Etch(dock, STYLE.dock, 12)
        St.Grime(dock, 0.25, 12, 0, 150, 220) -- as on Forever Goal Tracker's window: strongest at the top
    end
    dock.fill = fill
    -- a profession page's glow: a large, soft radial light of its color, centred on the title's icon
    -- and reaching about halfway down, over the fill and grime and under everything else. Cut to
    -- the fill by its texture coordinates (it is the fill's own texture, so it cannot spill out).
    dock.glow = fill:CreateTexture(nil, "BACKGROUND", nil, -4)
    dock.glow:SetTexture(St.Media("radial"))
    dock.glow:SetPoint("TOPLEFT", dock, "TOPLEFT", fi[1], -fi[2])
    dock.glow:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT", -fi[3], fi[4])
    dock.glow:SetAlpha(0)
    function dock:SetGlow(p)
        local w, h = self:GetWidth() or 0, self:GetHeight() or 0
        if p and w > 0 and h > 0 then
            local R = h * 0.5 -- radius: about halfway down the dock
            local fi = self.fillIn
            local cx, cy = SIDE_IN + PAD + 8 - fi[1], TITLE_H + PAD + 10 - fi[2] -- the icon, from the glow's top-left
            local iw, ih = w - fi[1] - fi[3], h - fi[2] - fi[4]
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
    if rawget(dock, "nine") or rawget(dock, "flat") then SIDE_IN = 8 end -- (see SIDE_IN)
    dock:SetWidth(DOCK_W + 2 * SIDE_IN)
    dock:EnableMouse(true)
    dock:Hide()
    dock.body = CreateFrame("Frame", nil, dock)
    dock.body:SetPoint("TOPLEFT", SIDE_IN, -TITLE_H) -- (everything under the title bar)
    dock.body:SetPoint("BOTTOMRIGHT", -SIDE_IN, 0)
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
        -- the switch sits at the dock's right end, often the screen's edge: open the tip inward
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -4)
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
        local b = ShowChoice(body, sh)
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
    dock.key.demoInHeader = true
    dock.key:SetPoint("TOPLEFT", PAD, y)
    body = shared
    dock.dash = Dashboard(body)
    -- the Stats page (StatsPage.lua): opened by the Stats tab, in place of the old stats window
    dock.statsPage = FN.StatsPage.Build(body, { inner = INNER, pad = PAD, top = FIRST_Y + SCROLL_TOP, ctrlH = CTRL_H,
        Dropdown = Dropdown, ShowProvider = ShowProvider, WhenProvider = WhenProvider, DockScroll = DockScroll,
        -- a chip changes the profession: the header's subtitle follows (it went stale before)
        OnPick = function() if StatsPlace then StatsPlace() end end })
    dock.session = SessionCard(body, INNER)

    -- the settings page: no panel of its own, it rises inside the dock (which clips it)
    dock:SetClipsChildren(true)
    sheet = CreateFrame("Frame", nil, dock)
    sheet:SetFrameLevel(dock:GetFrameLevel() + 20)
    sheet:SetPoint("TOPLEFT", dock, "TOPLEFT", SIDE_IN, -TITLE_H)
    sheet:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT", -SIDE_IN, 0)
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

    -- the Fieldnotes tab only opens and closes the dock; opening lands on Home (the dashboard)
    local function TabClick()
        if list then list:Hide() end
        if DockOpen() then
            if dock.sheetOpen then SetSheet(false) end
            FN.db.settings.dockOpen = false
        else
            FN.db.settings.dockOpen = true
            dock.statsOpen = false
            local s = M.S()
            if s.prof ~= "all" then
                s.prof = "all"
                M.SetLit(nil)
                Refresh()
            end
        end
        MapUI.Render(model)
    end

    -- The map button (Karl, 2026-11-07, replacing the side tab that slid the dock out): a small
    -- etched square with the add-on's icon, inside the map's top-right corner. A click opens the
    -- dock beside the map, or closes it. Its name shows only as a tooltip on hover. It warms on
    -- hover only, never gold (gold is for the page you are on). Placed by LayoutDock, clear of other
    -- add-ons' buttons (CornerSpot).
    if tab then
        -- Forever's side tab: opens the panel; never shown chosen (it is not a page)
        tab.icon = tab.Icon
        tab.icon:SetTexture(St.Media("icon"))
        tab.tooltipText = "Fieldnotes"
        tab:SetCustomOnMouseUpHandler(TabClick)
        tab:EnableMouse(true)
        tab:SetScript("OnHide", function(self)
            if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end)
        RefreshHome = function()
            -- (SetChecked also fits the icon to the tab's inside)
            if tab.SetChecked then tab:SetChecked(false) end
        end
    else
    tab = St.Frame("Button", WorldMapFrame)
    St.Etch(tab, STYLE.dock, 12)
    tab:SetSize(MAP_BTN, MAP_BTN)
    tab.icon = tab:CreateTexture(nil, "ARTWORK")
    tab.icon:SetTexture(St.Media("icon"))
    tab.icon:SetSize(MAP_BTN - 7, MAP_BTN - 7)
    tab.icon:SetPoint("CENTER")
    RefreshHome = function()
        tab:SetEtch(tab.hover and STYLE.btnHover or STYLE.dock)
        tab.icon:SetAlpha(tab.hover and 1 or 0.9)
    end
    tab:SetScript("OnClick", TabClick)
    tab:SetScript("OnEnter", function(self)
        self.hover = true
        RefreshHome()
        -- the button sits at the map's right edge: open the tip inward, under it
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -4)
        GameTooltip:SetText("Fieldnotes", C.TITLE[1], C.TITLE[2], C.TITLE[3])
        GameTooltip:AddLine(DockOpen() and "Click to close" or "Click to open", 1, 1, 1)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function(self)
        self.hover = false
        RefreshHome()
        GameTooltip:Hide()
    end)
    tab:SetScript("OnHide", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    end
    RefreshHome()
    tab:Hide()

    -- The title bar (Karl, 2026-11-07, option A): a dark strip as tall as the map window's own,
    -- "Fieldnotes" at its left and the game's red close button at its right, the same X the map
    -- has a few pixels away. Above the settings page too, so it closes from any page.
    local tb = CreateFrame("Frame", nil, dock)
    tb:SetPoint("TOPLEFT", 3, -3)
    tb:SetPoint("TOPRIGHT", -3, -3)
    tb:SetHeight(TITLE_H - 3)
    tb:SetFrameLevel(dock:GetFrameLevel() + 30)
    tb:EnableMouse(true)
    if not rawget(dock, "nine") and not rawget(dock, "flat") then
        tb.bg = tb:CreateTexture(nil, "BACKGROUND")
        tb.bg:SetAllPoints()
        tb.bg:SetTexture(St.SOLID)
        St.VGradient(tb.bg, { 0.030, 0.028, 0.025 }, { 0.010, 0.010, 0.010 })
        tb.rule = tb:CreateTexture(nil, "BORDER")
        tb.rule:SetTexture(St.SOLID)
        tb.rule:SetHeight(1)
        tb.rule:SetPoint("BOTTOMLEFT")
        tb.rule:SetPoint("BOTTOMRIGHT")
        local edge = STYLE.window.edge
        tb.rule:SetVertexColor(edge[1], edge[2], edge[3], 0.55)
    end
    if rawget(dock, "flat") then
        -- the flat panel draws its own title bar and title; ours only holds the close button
        tb:ClearAllPoints()
        tb:SetPoint("TOPLEFT", 0, 0)
        tb:SetPoint("TOPRIGHT", 0, 0)
        tb:SetHeight(TITLE_H)
        tb:EnableMouse(false)
    elseif rawget(dock, "nine") then
        -- in the frame's metal title bar, centred, in the game's title font, as the map's own title
        tb:ClearAllPoints()
        tb:SetPoint("TOPLEFT", 0, 0)
        tb:SetPoint("TOPRIGHT", 0, 0)
        tb:SetHeight(TITLE_H)
        -- the bar's own dark fill: the frame draws only its metal, so the world showed through
        -- (seen in game on Era, 2026-11-07). On the fill's frame, under the frame's metal.
        tb.bg = dock.fill:CreateTexture(nil, "BACKGROUND", nil, -3)
        tb.bg:SetTexture(St.SOLID)
        tb.bg:SetPoint("TOPLEFT", dock, "TOPLEFT", FILL_IN[1], -3)
        tb.bg:SetPoint("BOTTOMRIGHT", dock, "TOPRIGHT", -FILL_IN[3], -TITLE_H)
        St.VGradient(tb.bg, { 0.060, 0.056, 0.050 }, { 0.020, 0.019, 0.017 })
        -- left, in line with the page's own title, and centred in the bar's opening (under its
        -- top edge, above its bottom rule: a little below the strip's middle)
        tb.title = tb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tb.title:SetPoint("LEFT", tb, "LEFT", PAD, -2)
        tb.title:SetTextColor(C.TITLE[1], C.TITLE[2], C.TITLE[3]) -- the game's gold is money's in Fieldnotes
        tb.title:SetJustifyH("LEFT")
    else
        tb.title = St.Title(tb, 13)
        tb.title:SetPoint("LEFT", PAD - 3, 0)
    end
    if rawget(tb, "title") then tb.title:SetText("Fieldnotes") end
    dock.titleBar = tb
    local function CloseDock()
        if list then list:Hide() end
        if dock.sheetOpen then SetSheet(false) end
        FN.db.settings.dockOpen = false
        MapUI.Render(model)
    end
    -- (the flat panel's own place for it, as Spoken Places' panel has it)
    local okClose, x = pcall(CreateFrame, "Button", nil, rawget(dock, "flat") and dock or tb,
        rawget(dock, "flat") and "UIPanelCloseButtonDefaultAnchors" or "UIPanelCloseButton")
    if okClose and x then
        dock.close = x
        if rawget(dock, "flat") then
            x:SetFrameLevel(dock:GetFrameLevel() + 32)
        elseif rawget(dock, "nine") then
            -- where the game's windows keep theirs, in the frame's corner: read from the game's own
            -- window template, so it sits in the corner's round seat on either client
            local spot = GameCloseSpot()
            dock.closeSpot = spot
            if spot.w and spot.w > 0 then x:SetSize(spot.w, spot.h) end
            x:SetPoint(spot.p, dock, spot.rp, spot.x, spot.y)
        else
            x:SetSize(30, 30)
            x:SetPoint("RIGHT", tb, "RIGHT", 4, 0)
        end
        if not rawget(dock, "flat") then x:SetFrameLevel(tb:GetFrameLevel() + 2) end
        x:SetScript("OnClick", CloseDock)
    else
        -- (no template: the share window's X)
        dock.close = St.IconButton(tb, "close-white", 14, CloseDock)
        dock.close:SetPoint("RIGHT", tb, "RIGHT", -6, 0)
    end

    -- The rail's tabs (Home, a tab per profession, Stats, Settings) share one look: every icon
    -- the same quiet silver at rest, on the plain tab; hovered, it brightens and the tab glides out
    -- a little; active, it glides out further, its icon takes its color (a profession's, or gold),
    -- and a soft light of that color rises from the edge it shares with the dock, washing out
    -- across the tab. Nothing glows around the icon (it muddied the icon, Karl). One value per tab (out: 0 at
    -- rest, 0.4 hovered, 1 active) drives all of it, eased, so every change glides.
    local function RailTab(icon, color, name, tipText, onClick)
        local t = St.Frame("Button", dockClip)
        St.Etch(t, STYLE.dock, 12) -- (12, as the Fieldnotes tab: its open gold border matches)
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
    dock.stats = RailTab("stats-white", C.TITLE, "Stats", "Charts of your gathering", function()
        MapUI.OpenStats(not dock.statsOpen)
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
            or math.abs(s.spread - M.DEFAULTS.spread) > 0.01 or math.abs(s.dim - M.DEFAULTS.dim) > 0.01
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
    local roomRight = screen - right >= DockW() + HOME_W + 4
    local roomLeft = left >= DockW() + HOME_W + 4
    -- gap: from the map art's edge to the window's outer edge, less the border frame's empty
    -- margin, so the dock touches the window's gold edge
    if (quest or not roomRight) and roomLeft then
        return "LEFT", left - (container:GetLeft() or left) + EDGE_TUCK
    end
    if roomRight or not roomLeft then return "RIGHT", (container:GetRight() or right) - right + EDGE_TUCK end
    return "LEFT", left - (container:GetLeft() or left) + EDGE_TUCK
end

-- CornerSpot: other add-ons put their own buttons on the map too (Questie, HandyNotes and the
-- like). Ours should never sit on one, so we look at what is in the map's top-right corner and, if
-- something is where our button goes, step left of it along the top; if the top row is full, step
-- down below it instead. Only small shown frames over the map art count; the map's own big parts
-- and our own are skipped. Checked when the map opens and again a moment later (other add-ons
-- build their buttons late), never per frame.
local function ScreenRect(f)
    if not (f and f.GetRect) then return end
    local l, b, w, h = f:GetRect()
    if not (l and w) then return end
    local k = (f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    return l * k, b * k, (l + w) * k, (b + h) * k
end

local function IsOurs(f)
    for _ = 1, 8 do
        if not f then return false end
        if f == dockClip or f == list or f == tab then return true end
        f = f.GetParent and f:GetParent() or nil
    end
    return false
end

local CORNER = 260 -- how far from the corner, each way, a frame can be in our way
local obstacles = {}
local nbInfo = {} -- what the last look saw, for /fn debug
local function CornerSpot()
    local container = WorldMapFrame.ScrollContainer or WorldMapFrame
    local cl, cb, cr, ct = ScreenRect(container)
    if not cl then return -MAP_BTN_INSET, -MAP_BTN_INSET end
    local k = (container:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    local zl, zb = math.max(cl, cr - CORNER * k), math.max(cb, ct - CORNER * k)
    wipe(obstacles)
    wipe(nbInfo)
    nbInfo.col = string.format("corner x %.0f to %.0f, y %.0f to %.0f", zl, cr, zb, ct)
    local seen = {}
    local function Consider(f)
        if seen[f] then return end
        seen[f] = true
        if f == WorldMapFrame or f == container or (f.IsForbidden and f:IsForbidden()) then return end -- (the game's own protected frames refuse a tainted caller)
        if not (f.IsVisible and f:IsVisible()) or IsOurs(f) then return end
        -- a tooltip or a menu is not a button
        if (f.GetObjectType and f:GetObjectType() == "GameTooltip") or (f.GetFrameStrata and f:GetFrameStrata() == "TOOLTIP") then return end
        local w, h = f:GetWidth(), f:GetHeight()
        if not (w and h) or w < 8 or h < 8 or w > 200 or h > 200 then return end
        local l, b, r, t = ScreenRect(f)
        if not l or r <= zl or l >= cr or t <= zb or b >= ct then return end
        -- its middle over the map art: a side tab hung outside the window is not in our corner
        local mx, my = (l + r) / 2, (b + t) / 2
        if mx > cr or my > ct then return end
        obstacles[#obstacles + 1] = { l, b, r, t }
        if #nbInfo < 8 then
            nbInfo[#nbInfo + 1] = string.format("%s %.0fx%.0f at %.0f,%.0f", tostring(f.GetName and f:GetName() or "?"), w, h, l, b)
        end
    end
    local safe = Consider
    Consider = function(f) pcall(safe, f) end
    local function Scan(parent)
        if not (parent and parent.GetChildren) then return end
        for i = 1, select("#", parent:GetChildren()) do
            local f = select(i, parent:GetChildren())
            if f then Consider(f) end
        end
    end
    Scan(WorldMapFrame)
    Scan(container)
    Scan(WorldMapFrame.BorderFrame)
    Scan(UIParent)
    if type(WorldMapFrame.overlayFrames) == "table" then
        for _, f in ipairs(WorldMapFrame.overlayFrames) do Consider(f) end
    end
    -- the first obstacle our button at (x, y) from the corner would touch
    local function Hit(x, y)
        local r, t = cr + x * k, ct + y * k
        local l, b = r - MAP_BTN * k, t - MAP_BTN * k
        local pad = 2 * k
        for _, o in ipairs(obstacles) do
            if r > o[1] - pad and l < o[3] + pad and t > o[2] - pad and b < o[4] + pad then return o end
        end
    end
    -- along the top first, stepping left of each one in the way
    local x, y = -MAP_BTN_INSET, -MAP_BTN_INSET
    for _ = 1, 12 do
        local o = Hit(x, y)
        if not o then return x, y end
        x = math.min(x - 1, (o[1] - cr) / k - MAP_BTN_GAP)
        if -x + MAP_BTN > CORNER then break end
    end
    -- the top row is full: down the right edge, stepping below each one in the way
    x, y = -MAP_BTN_INSET, -MAP_BTN_INSET
    for _ = 1, 12 do
        local o = Hit(x, y)
        if not o then return x, y end
        y = math.min(y - 1, (o[2] - ct) / k - MAP_BTN_GAP)
        if -y + MAP_BTN > CORNER then break end
    end
    return -MAP_BTN_INSET, -MAP_BTN_INSET
end

-- Forever: the side tabs other add-ons hang down the map window's right edge (Spoken Places' way of
-- finding them, since no list holds them): the lowest one, and how far the widest reaches past the
-- edge. Shorter than half the map, which keeps out a panel standing beside it.
local function SideTabs(border)
    local _, eb, er, et = ScreenRect(border)
    if not er then return nil, 0 end
    local lowest, lowestBottom, reach = nil, nil, 0
    local seen = {}
    for _, parent in ipairs({ WorldMapFrame, WorldMapFrame.BorderFrame or false, QuestMapFrame or false, UIParent }) do
        if type(parent) == "table" and parent.GetChildren then
            for _, f in ipairs({ parent:GetChildren() }) do
                if not seen[f] and not IsOurs(f) and f ~= tab and not (f.IsForbidden and f:IsForbidden())
                    and f.IsVisible and f:IsVisible() then
                    seen[f] = true
                    local l, b, r, top = ScreenRect(f)
                    if l and l >= er - COLUMN_SLACK and (l + r) / 2 > er and top <= et + COLUMN_SLACK
                        and b >= eb - COLUMN_SLACK and top - b < (et - eb) / 2 and r - l < 120 then
                        reach = math.max(reach, r - er)
                        if not lowestBottom or b < lowestBottom then lowest, lowestBottom = f, b end
                    end
                end
            end
        end
    end
    local k = (border:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    return lowest, reach / k
end
local sideLowest, sideReach = nil, 0

local lastScan, wantScan = 0, false

-- Open, the dock draws one layer above the map, so another add-on's side tab on the map's edge
-- (Spoken Places') cannot cover its top corner; folded, it goes back to the map's own layer, so our
-- tab stacks under theirs like any other side tab.
local LAYER_UP = { BACKGROUND = "LOW", LOW = "MEDIUM", MEDIUM = "HIGH", HIGH = "DIALOG", DIALOG = "FULLSCREEN" }
local function DockLayer(open)
    local base = WorldMapFrame:GetFrameStrata() or "MEDIUM"
    local want = open and (LAYER_UP[base] or base) or base
    if dockClip:GetFrameStrata() ~= want then dockClip:SetFrameStrata(want) end
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
    -- the window the dock and its rail live in: from the map window's edge outward
    dockClip:SetHeight(container:GetHeight() + 400)
    dockClip:SetWidth(DockW() + HOME_W + 80)
    dockClip:ClearAllPoints()
    if side == "RIGHT" then
        dockClip:SetPoint("LEFT", container, "RIGHT", -gap - 1, 0)
    else
        dockClip:SetPoint("RIGHT", container, "LEFT", gap + 1, 0)
    end
    dock:ClearAllPoints()
    dock:SetPoint(edge, container, mapEdge, dir * (-gap + DOCK_GAP), dy)
    if rawget(tab, "native") then
        -- Forever: the map window's full height, past the side tabs on its edge, a wider gap off it
        if wantScan or GetTime() - lastScan > 1.5 then
            local ok, low, reach = pcall(SideTabs, border)
            sideLowest, sideReach = ok and low or nil, ok and reach or 0
        end
        if top and bottom and top > bottom then dock:SetHeight(top - bottom) end
        local off = sideReach + FOREVER_GAP
        dock:ClearAllPoints()
        dock:SetPoint(edge, border, mapEdge, dir * off, 0)
        dockClip:ClearAllPoints()
        dockClip:SetWidth(DockW() + HOME_W + 80 + off)
        dockClip:SetHeight((top and bottom and top - bottom or container:GetHeight()) + 400)
        dockClip:SetPoint(side == "RIGHT" and "LEFT" or "RIGHT", border, side == "RIGHT" and "RIGHT" or "LEFT", 0, 0)
    end

    -- the map button: in the map's top-right corner, clear of other add-ons' buttons (CornerSpot)
    if wantScan or GetTime() - lastScan > 1.5 then
        wantScan = false
        lastScan = GetTime()
        local ok, x, y = true, btnX, btnY
        if not rawget(tab, "native") then ok, x, y = pcall(CornerSpot) end
        btnX, btnY = ok and x or -MAP_BTN_INSET, ok and y or -MAP_BTN_INSET
        nbInfo.err = (not ok) and tostring(x) or nil
    end
    tab:ClearAllPoints()
    if rawget(tab, "native") then
        -- the side tab: under the lowest other side tab, else near the window's top; shown while
        -- the panel is closed
        if sideLowest and side == "RIGHT" then
            tab:SetPoint("TOPLEFT", sideLowest, "BOTTOMLEFT", 0, -SIDE_TAB_GAP)
        elseif side == "RIGHT" then
            tab:SetPoint("TOPLEFT", border, "TOPRIGHT", 0, -SIDE_TAB_TOP)
        else
            tab:SetPoint("TOPRIGHT", border, "TOPLEFT", 0, -SIDE_TAB_TOP)
        end
        tab:SetFrameStrata(WorldMapFrame:GetFrameStrata() or "MEDIUM")
        tab:SetFrameLevel((WorldMapFrame:GetFrameLevel() or 1) + 10)
        tab:SetShown(not open)
    else
        tab:SetPoint("TOPRIGHT", container, "TOPRIGHT", btnX, btnY)
        tab:Show()
    end

    -- the rail: Home, then the profession tabs, a gap, Stats and Settings, down the dock's outer
    -- edge, tucked a little under it so the two read as one
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
    -- (less one unit: the dock's border art stops a little short of its frame, seen in game)
    local shift = dir * (TAB_TUCK / 2 - 1)
    -- Stats and Settings sit at the dock's bottom, but never over the profession tabs on a short dock
    local nUtil = #utilTabs
    local profBottom = -(#rail - nUtil) * (PROF_TAB_H + PROF_TAB_GAP)
    local utilTop = -(dock:GetHeight() - TAB_DROP - RailTop()) + nUtil * PROF_TAB_H + (nUtil - 1) * PROF_TAB_GAP
    utilTop = math.min(utilTop, profBottom - UTIL_GAP)
    local below = 0
    for i, t in ipairs(rail) do
        if t == utilTabs[1] then below = utilTop elseif i > 1 then below = below - PROF_TAB_GAP end
        t.tuck = TAB_TUCK
        t:ClearAllPoints()
        if side == "RIGHT" then
            t:SetPoint("TOPLEFT", dock, "TOPRIGHT", -TAB_TUCK, -RailTop() + below)
        else
            t:SetPoint("TOPRIGHT", dock, "TOPLEFT", TAB_TUCK, -RailTop() + below)
        end
        below = below - PROF_TAB_H
        t.mark:ClearAllPoints()
        t.mark:SetPoint("CENTER", t, "CENTER", shift, 0)
    end

    -- open and close: no slide (Karl, 2026-11-07), the dock and its rail simply appear beside the
    -- map with a short fade, and leave the same way. Only a change of state fades; any other
    -- redraw just places it.
    local moving = dock.wasOpen ~= nil and dock.wasOpen ~= open
    dock.wasOpen = open
    -- up as it opens; down only once it is gone (below)
    if open or not moving then DockLayer(open) end
    St.Animate("fn-dock", open and 1 or 0, moving and St.DUR.quick or 0, "out", function(v)
        dock:SetAlpha(v)
        for _, t in ipairs(rail) do t:SetAlpha(v) end
    end, function()
        if not DockOpen() then
            dock:Hide()
            DockLayer(false)
            -- back to rest, so the active tab glides out again on the next open
            for _, t in ipairs(rail) do
                t:Hide()
                t.active, t.hover = false, false
                Glide(t, true)
            end
        end
    end)
    if open then dock:Show() end
    for _, t in ipairs(rail) do
        if open or moving then t:Show() end
        -- just under the dock, so its inner edge hides beneath the dock's border
        t:SetFrameLevel(math.max(1, (dock:GetFrameLevel() or 2) - 1))
        -- the wash is strongest at the dock and fades outward
        t.side = side
        ApplyTab(t)
        local active
        if t.p then
            active = not dock.sheetOpen and not dock.statsOpen and s.prof == t.p.key
            t.rec:SetShown(t.p.key ~= "all" and FN.SessionHas and FN.SessionHas(t.p.key) or false)
        elseif t == dock.gear then
            active = dock.sheetOpen == true
        else
            active = dock.statsOpen == true
        end
        active = open and active
        if t.active ~= active then
            t.active = active
            Glide(t)
        end
    end
    dock.gear:Tint()
    RefreshHome()
end

-- the Stats subtitle: the chosen profession (or all), and every zone, since stats count them all
-- (the map you are on would mislead here)
StatsPlace = function()
    local P = M.PROF[M.S().statsProf]
    dock.place:SetText((P and P.label or "All professions") .. "  ·  All zones")
end

local function RenderDock(m)
    local s = M.S()
    dock.switch:Sync()
    dock.statsPage:SetShown(dock.statsOpen == true)
    if dock.statsOpen then
        dock.icon:Set(nil)
        dock.prof:ClearAllPoints()
        dock.prof:SetPoint("TOPLEFT", PAD, -PAD - 2)
        dock.prof:SetText("Stats")
        dock.prof:SetTextColor(C.TITLE[1], C.TITLE[2], C.TITLE[3])
        dock.place:SetTextColor(C.SUBTEXT[1], C.SUBTEXT[2], C.SUBTEXT[3])
        StatsPlace()
        dock.page:Hide()
        dock.dash:Hide()
        dock:SetGlow(nil)
        dock.statsPage:Update()
        dock.session:ClearAllPoints()
        dock.session:SetPoint("BOTTOMLEFT", dock.body, "BOTTOMLEFT", PAD, FOOTER_H + 8)
        dock.session:Update()
        dock.gear:Tint()
        if dock.sheetOpen then SheetLayout() end
        return
    end
    local dash = s.prof == "all"
    local p = M.PROF[s.prof]
    dock.icon:Set(p)
    dock.prof:ClearAllPoints()
    dock.prof:SetPoint("TOPLEFT", PAD + (p and 22 or 0), -PAD - 2)
    dock.prof:SetText(dash and "Home" or p.label) -- ("Fieldnotes" is the title bar's)
    -- a profession's page wears its color: title, place, the chosen View and the key's total
    local tc = dash and C.TITLE or NameTint(p.color)
    dock.prof:SetTextColor(tc[1], tc[2], tc[3])
    local pc = dash and C.SUBTEXT or LabelTint(p.color)
    dock.place:SetTextColor(pc[1], pc[2], pc[3])
    local place = dash and ("All professions" .. (m.place and ("  ·  " .. m.place) or "")) or (m.place or "")
    -- sample data is said once, up here, on every page (it was the key's last line, dropped first
    -- when short, so some pages said it and some did not)
    if m.inDemo then place = place .. "  ·  |cff999999Sample data|r" end -- C.SUBTEXT (gold read as a third accent)
    dock.place:SetText(place)
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
    -- section labels stay grey: with the title, chosen buttons and total in the profession's color,
    -- tinted labels flattened the hierarchy (Karl, 2026-11-06)
    for _, l in ipairs({ dock.viewLabel, dock.showLabel, dock.matLabel }) do
        l:SetTextColor(C.SUBTEXT[1], C.SUBTEXT[2], C.SUBTEXT[3])
    end
    dock.dotsLabel:SetText("Every " .. p.unit)
    local look = St.AccentLook(p.color)
    for _, b in ipairs(dock.modes) do
        b.look = look
        b:SetChosen(b.key == s.mode)
    end
    for _, b in ipairs(dock.shows) do
        b.look = look -- one chosen color per page
        b:SetChosen(b.key == s.show)
    end
    dock.leather:Update()
    local points = s.mode == "points"
    dock.dots.toggle.onLook = St.ToggleLook(p.color) -- gold stays for the add-on's own switch
    dock.dots.toggle:SetOn(s.dots and not points)
    -- the session row first, so the key can measure the room above it
    dock.session:ClearAllPoints()
    dock.session:SetPoint("BOTTOMLEFT", dock.body, "BOTTOMLEFT", PAD, FOOTER_H + 8)
    -- the key holds the hot spots; when the dock is short it drops its caption, then spots
    local room = dock:GetHeight() - TITLE_H - DOCK_TOP_H - 6 - 34 - (FOOTER_H + 8)
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
    St.Animate("fn-pop", open and 1 or 0, St.DUR.base, open and "soft" or "leave", function(v)
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
    St.Etch(bar, STYLE.panel, 12, 0.98) -- (0.94 let the map's own hint text show through)
    bar:SetHeight(36)
    bar:EnableMouse(true)
    bar:SetClipsChildren(true)
    bar.title = St.Title(bar, 14)
    bar.title:SetText("Fieldnotes")
    bar.switch = Switch(bar)
    -- the pages, as on the dock's rail: Home (the dashboard), then each profession. The chosen
    -- one takes its color (gold for Home); the rest rest in silver.
    bar.profs = {}
    local function PageButton(key, icon, color, tip)
        -- not GoTo: that opens the small map's dock as well
        local b = Choice(bar, "", function()
            if list then list:Hide() end
            if M.S().prof ~= key then
                M.SetProf(key)
                Refresh()
            end
        end, tip)
        b.key, b.color = key, color
        b.icon = b:CreateTexture(nil, "OVERLAY")
        b.icon:SetTexture(St.Icon(icon))
        b.icon:SetSize(15, 15)
        b.icon:SetPoint("CENTER")
        function b:Paint(on)
            self:SetChosen(on)
            local c = on and self.color or REST
            self.icon:SetVertexColor(c[1], c[2], c[3])
        end
        bar.profs[#bar.profs + 1] = b
        return b
    end
    PageButton("all", "book-white", C.TITLE, "Home: all your professions")
    for _, p in ipairs(M.PROFS) do PageButton(p.key, PROF_ICONS[p.key], p.color, p.label) end
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
        local b = ShowChoice(bar, sh)
        bar.shows[i] = b
    end
    bar.leather = LeatherButton(bar)
    -- the session chip: Start with play; while running, its clock and skins (click to pause)
    bar.session = Choice(bar, "Start", function()
        if FN.SessionRunning() then FN.SessionTogglePause() else FN.SessionStart() end
        MapUI.Render(model)
    end, "Start a session: a timer and a tally of what you gather. Click again to pause.")
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
    -- Stats and Share are icons, like the gear: they spend no room on words
    local function IconChoice(icon, onClick, tip)
        local b = Choice(bar, "", onClick, tip)
        b.icon = b:CreateTexture(nil, "OVERLAY")
        b.icon:SetTexture(St.Icon(icon))
        b.icon:SetSize(14, 14)
        b.icon:SetPoint("CENTER")
        b.icon:SetVertexColor(C.INK2[1], C.INK2[2], C.INK2[3])
        return b
    end
    bar.stats = IconChoice("stats-white", function() FN.ToggleStats() end, "Stats")
    bar.share = IconChoice("share-white", function() FN.ShowShare() end, "Share your notes, or import someone else's")
    bar.gear = GearButton(bar, function() SetPop(not pop.open) end)
    bar.dividers = {}
    for i = 1, 5 do
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

    hudKey = KeyCard(hud, 280, true, true) -- with the hot spots, as in the dock, on glass
    -- tall enough for the busiest layout: count, numbered ramp and caption, three hot spots and
    -- the sample-data note (Points' two legend lines need less)
    hudKey.fixedH = 156

    pop = St.Frame("Frame", hud)
    St.Etch(pop, STYLE.panel, 12)
    pop:SetWidth(300)
    pop:EnableMouse(true)
    pop:Hide()
    pop.body = SettingsBody(pop, 272)
end

-- The toolbar spans the map's full width, flush under the map window's title band: on the left
-- the name, switch and pages, then View, Show and the material list; the session, Stats, Share
-- and the gear sit at the right end. Switched off it narrows to the name and switch, snapped to
-- the map's top left corner.
local BAR_H = 36
local function LayoutToolbar(m)
    local s = M.S()
    local dash = s.prof == "all"
    -- One rhythm: 4 between buttons in a group; a divider has 10 either side of it, always
    -- measured from the buttons' edges; 14 at both ends of the bar.
    local GAP, SEP, EDGE = 4, 10, 14
    local x = EDGE
    bar.title:ClearAllPoints()
    bar.title:SetPoint("LEFT", bar, "LEFT", x, 0)
    x = x + bar.title:GetStringWidth() + 10
    bar.switch:ClearAllPoints()
    bar.switch:SetPoint("LEFT", bar, "LEFT", x, 0)
    bar.switch:Sync()
    x = x + 36
    local closedW = x + EDGE
    x = x + GAP -- x is now where the next button would go, as after any button
    local function Place(f, w)
        f:SetWidth(w)
        f:ClearAllPoints()
        f:SetPoint("LEFT", bar, "LEFT", x, 0)
        f:Show()
        x = x + w + GAP
    end
    local function Divider(i)
        local edge = x - GAP -- the last button's right edge
        bar.dividers[i]:ClearAllPoints()
        bar.dividers[i]:SetPoint("LEFT", bar, "LEFT", edge + SEP, 0)
        bar.dividers[i]:Show()
        x = edge + SEP + 1 + SEP
    end
    Divider(1)
    -- the pages: Home, then the professions the dock's rail would show
    local shown = { all = true }
    for _, p in ipairs(TabProfs()) do shown[p.key] = true end
    if not shown[s.prof] then shown[s.prof] = true end
    for _, b in ipairs(bar.profs) do
        if shown[b.key] then
            Place(b, 28)
            b:Paint(b.key == s.prof)
        else
            b:Hide()
        end
    end
    -- View and the material list mean nothing on Home (every gather is a dot there)
    if dash then
        bar.dividers[2]:Hide()
        for _, b in ipairs(bar.modes) do b:Hide() end
        bar.dividers[3]:Hide()
    else
        Divider(2)
        for _, b in ipairs(bar.modes) do
            Place(b, math.ceil(b.text:GetStringWidth()) + 18)
            local bp = M.PROF[s.prof]
            b.look = bp and St.AccentLook(bp.color) or nil
            b:SetChosen(b.key == s.mode)
        end
        Divider(3)
    end
    if dash then Divider(3) end -- (Home: pages, then Show, with one divider between)
    for _, b in ipairs(bar.shows) do
        Place(b, math.ceil(b.text:GetStringWidth()) + 18)
        local bp = M.PROF[s.prof]
        b.look = bp and St.AccentLook(bp.color) or nil
        b:SetChosen(b.key == s.show)
    end
    local leatherX
    if dash then
        bar.dividers[4]:Hide()
        bar.leather:Hide()
    else
        Divider(4)
        leatherX = x
    end

    -- the session chip, and what the right end needs
    local running, paused = FN.SessionRunning(), FN.SessionPaused()
    if running then
        bar.session.text:SetText(Clock(FN.SessionSeconds()) .. "  ·  " .. FN.SessionLabel())
        bar.session.icon:SetTexture(St.Icon(paused and "play-white" or "pause-white"))
    else
        bar.session.text:SetText("Start")
        bar.session.icon:SetTexture(St.Icon("play-white"))
    end
    bar.session.icon:SetVertexColor(C.INK2[1], C.INK2[2], C.INK2[3])
    local sessionW = math.ceil(bar.session.text:GetStringWidth()) + 34
    local ICON_W = 28
    local barW = hud:GetWidth() or 0
    local fullW = math.max(closedW, barW)
    -- right end, from the right edge in: gear, [Stats, Share], [stop], Start, then a divider
    local rightBase = EDGE + 16 + GAP + (running and 16 + GAP or 0) + sessionW + SEP + 1 + SEP
    local iconsW = 2 * (ICON_W + GAP)
    -- the material list takes what is left (110 to 150); Stats and Share give way if even 110 is too much
    local wantLeather = dash and 0 or 110
    local leftMin = (leatherX or x) + wantLeather
    local showIcons = barW <= 0 or leftMin + rightBase + iconsW <= barW
    local leatherW = 0
    if not dash then
        local room = barW - rightBase - (showIcons and iconsW or 0) - leatherX
        leatherW = barW <= 0 and 150 or math.max(96, math.min(150, room))
        bar.leather:Update()
        Place(bar.leather, leatherW)
    end

    -- anchored from the left at the full width, so when the bar narrows they are clipped away with
    -- the rest rather than sliding over the name
    local r = EDGE
    bar.gear:ClearAllPoints()
    bar.gear:SetPoint("LEFT", bar, "LEFT", fullW - r - 16, 0)
    bar.gear:Tint()
    r = r + 16 + GAP
    local function PlaceR(f, w)
        f:SetWidth(w)
        f:ClearAllPoints()
        f:SetPoint("LEFT", bar, "LEFT", fullW - r - w, 0)
        f:Show()
        r = r + w + GAP
    end
    if showIcons then
        PlaceR(bar.share, ICON_W)
        PlaceR(bar.stats, ICON_W)
    else
        bar.share:Hide()
        bar.stats:Hide()
    end
    bar.stop:SetShown(running)
    if running then
        bar.stop:ClearAllPoints()
        bar.stop:SetPoint("LEFT", bar, "LEFT", fullW - r - 16, 0)
        r = r + 16 + GAP
    end
    PlaceR(bar.session, sessionW)
    bar.dividers[5]:ClearAllPoints()
    bar.dividers[5]:SetPoint("LEFT", bar, "LEFT", fullW - (r - GAP) - SEP - 1, 0)
    bar.dividers[5]:Show()

    -- only switching on or off animates; a redraw (the session clock, a filter) just resizes
    local moving = bar.wasOn ~= nil and bar.wasOn ~= s.on
    bar.wasOn = s.on
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", hud, "TOPLEFT", 0, 0)
    bar:SetHeight(BAR_H)
    local inner = {}
    for _, f in ipairs(bar.profs) do inner[#inner + 1] = f end
    for _, f in ipairs({ bar.modes[1], bar.modes[2], bar.modes[3], bar.shows[1], bar.shows[2], bar.shows[3],
        bar.leather, bar.session, bar.stop, bar.stats, bar.share, bar.gear }) do
        inner[#inner + 1] = f
    end
    for _, d in ipairs(bar.dividers) do inner[#inner + 1] = d end
    St.Animate("fn-bar", s.on and 1 or 0, moving and St.DUR.slow or 0, s.on and "soft" or "leave", function(v)
        bar:SetWidth(closedW + (fullW - closedW) * v)
        for _, f in ipairs(inner) do f:SetAlpha(v) end
    end)

    -- the key: snapped into a bottom corner, fading and drifting down when switched off
    hudKey:Update(m, (hud:GetHeight() or 600) - BAR_H - 24)
    local corner = m.keyCorner or "BOTTOMLEFT"
    St.Animate("fn-key", s.on and 1 or 0, moving and St.DUR.slow or 0, s.on and "soft" or "leave", function(v)
        hudKey:SetAlpha(v)
        hudKey:ClearAllPoints()
        hudKey:SetPoint(corner, hud, corner, 0, -12 * (1 - v))
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
    return screen - right >= DockW() + HOME_W + 4 or left >= DockW() + HOME_W + 4
end

-- look at the map's corner again now (the map opened, or another add-on added a button) and
-- move the map button if it has to
function MapUI.Rescan()
    if not (dock and WorldMapFrame:IsShown()) then return end
    wantScan = true
    MapUI.Render(model)
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
    -- the map button rides with the toolbar's layer, above the map art and its pins (Forever's side
    -- tab keeps the map's own layer, as the game's side tabs do: LayoutDock)
    if not rawget(tab, "native") then
        tab:SetFrameStrata(strata)
        tab:SetFrameLevel(1000)
    end
    pop:SetFrameLevel(bar:GetFrameLevel() + 10)
end

function MapUI.Debug(Size)
    FN.Print("  layout " .. tostring(ui.layout) .. "; dock " .. Size(dock) .. "; map button " .. Size(tab))
    local cs = dock and rawget(dock, "closeSpot")
    if cs then FN.Print(string.format("  close button: %s %.1f, %.1f (%s)", cs.p, cs.x, cs.y, cs.from)) end
    if dock and rawget(dock, "flat") then FN.Print("  dock frame: the game's flat panel (DefaultPanelFlatTemplate)") end
    if tab and rawget(tab, "native") then
        FN.Print(string.format("  side tab: under %s, panel %.0f off the map", sideLowest and (sideLowest.GetName and sideLowest:GetName() or "a side tab") or "nothing", sideReach + FOREVER_GAP))
    end
    FN.Print("  dock frame: " .. (NINE_LAYOUT and dock and rawget(dock, "nine") and ("the game's (" .. NINE_LAYOUT .. ")")
        or ("etched" .. (NINE_LAYOUT and ", the game's failed" or ", this client has no game layout"))))
    if nbInfo.err then FN.Print("  corner ERROR: " .. nbInfo.err) end
    if nbInfo.col then FN.Print("  corner " .. nbInfo.col) end
    for _, line in ipairs(nbInfo) do FN.Print("   in the way: " .. line) end
    FN.Print(string.format("  map button at %d, %d from the corner (%s level %d)", btnX, btnY,
        tab and tab:GetFrameStrata() or "?", tab and tab:GetFrameLevel() or 0))
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
            -- its frame: the game's side tab art (TabArt), or the flat lines where there is none
            local art = rawget(t, "art")
            if art then
                FN.Print(string.format("  tab frame: game art %s, scale %.2f, %dx%d, level %d, alpha %.2f",
                    art:IsShown() and "shown" or "hidden", art:GetScale() or 0, art:GetWidth() or 0, art:GetHeight() or 0,
                    art:GetFrameLevel() or 0, art:GetAlpha() or 0))
                -- what the template draws with, so its pieces can be matched
                for _, r in ipairs({ art:GetRegions() }) do
                    if r.GetObjectType and r:GetObjectType() == "Texture" then
                        local layer = r:GetDrawLayer()
                        FN.Print(string.format("   piece %s %s %s %dx%d", tostring(layer), r:IsShown() and "shown" or "hidden",
                            tostring((r.GetAtlas and r:GetAtlas()) or r:GetTexture()), r:GetWidth() or 0, r:GetHeight() or 0))
                    end
                end
            else
                FN.Print("  tab frame: flat lines (" .. (art == false and "this client has no side tab template" or "not made yet") .. ")")
            end
        end
    end
end

function MapUI.Init()
    if dock then return end
    M = FN.Map
    ui = M.ui
    St.Animate("fn-overlay", M.S().on and 1 or 0, 0, nil, M.SetOverlayAlpha) -- where the fade starts from
    -- Community is switched off for now: a saved choice of it falls back to Account
    if M.S().show == "community" then M.S().show = "account" end
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
    -- the Stats page (the Stats tab, /fn): open or close it in the dock
    function MapUI.OpenStats(open)
        if list then list:Hide() end
        if open and dock.sheetOpen then SetSheet(false) end
        dock.statsOpen = open == true
        if open then FN.db.settings.dockOpen = true end
        MapUI.Render(model)
    end
    BuildToolbar()
    MapUI.key = hudKey -- for the checks
    -- other add-ons build their map tabs a moment after the map opens: look, then look again
    WorldMapFrame:HookScript("OnShow", function()
        if not dock then return end
        C_Timer.After(0.3, MapUI.Rescan)
        C_Timer.After(2, MapUI.Rescan)
    end)
    WorldMapFrame:HookScript("OnHide", function()
        if list then list:Hide() end
        if dock.sheetOpen then SetSheet(false) end
        if pop.open then SetPop(false) end
    end)
end

-- ------------------------------------------------------------
-- Stats: a page in the dock (StatsPage.lua). /fn, the toolbar's Stats and /fn shots come here.
-- ------------------------------------------------------------
function FN.StatsShown()
    return dock ~= nil and dock.statsOpen == true and WorldMapFrame:IsShown() and ui.layout == "dock"
end
-- the dock while the Stats page shows (/fn shots frames it), else nil
function FN.StatsFrame() return FN.StatsShown() and dock or nil end
function FN.HideStats()
    if dock and dock.statsOpen then MapUI.OpenStats(false) end
end
function FN.ShowStats()
    if not dock then return end
    if not WorldMapFrame:IsShown() and ToggleWorldMap then ToggleWorldMap() end
    MapUI.OpenStats(true)
    -- the full-screen map has no dock: say where the stats are
    if WorldMapFrame:IsShown() and not UseDock() then
        FN.Print("Stats open in the map's side panel: make the map smaller to see them.")
    end
end
function FN.ToggleStats()
    if FN.StatsShown() then FN.HideStats() else FN.ShowStats() end
end
