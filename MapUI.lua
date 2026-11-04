local ADDON, FN = ...

-- The map's controls, built from the map v2 mockups (design/map-v2-2026-11-03):
--
--   Small map: a dock outside the map's edge (right, or left when there is no room or a quest
--   panel sits on the right), the full height of the map, so nothing of Fieldnotes covers the
--   map but the heat itself. A "Fieldnotes" tab folds it away and back.
--   Full-screen map: one toolbar centred at the top and a small key in a bottom corner.
--
-- Both hold the same things: the profession (Skinning for now), the on/off switch, View, Show,
-- the leather list, the key, the session (start, pause, end), Stats, Share and a gear for the
-- two settings left (Colors, When). Map.lua draws the map and hands Render() a model of what is
-- on screen. Slides and fades follow the motion notes in that folder's README.

local MapUI = {}
FN.MapUI = MapUI

local St = FN.Style
local C = St.C
local STYLE = St.STYLE
local M -- FN.Map, set in Init (Map.lua loads first)
local ui -- shared with Map.lua (FN.Map.ui)

local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local DOCK_W = 228
local PAD = 12
local INNER = DOCK_W - PAD * 2
local TAB_W, TAB_H = 26, 150 -- TAB_H: the stacked-letter fallback; a turned word sets its own
local TAB_TOP, TAB_GAP, TAB_BOTTOM = 8, 8, 8 -- room above the word, word to chevron, below it
local TAB_TUCK = 8 -- how far the open tab slips under the dock's edge, so the two read as one
local FOOTER_H = PAD + 2 + 16 + 12 -- the icon row and the space above it, up to its rule
local EDGE_TUCK = 10 -- the map window's art stops this far inside its border frame's edge
local LIST_ROWS = 6
local GREEN = { 0.31, 0.75, 0.23 }

-- icon: a file name in Media/icons (white on clear, like the others), tinted gold when chosen.
-- Until Karl's profession icons land, each slot shows its initial as a placeholder.
local PROFESSIONS = {
    { key = "skinning", label = "Skinning", ready = true },
    { key = "mining", label = "Mining" },
    { key = "herbalism", label = "Herbalism" },
    { key = "fishing", label = "Fishing" },
}
local MODES = {
    { key = "heat", label = "Heat", tip = "A glow where you skin most" },
    { key = "points", label = "Points", tip = "One dot per skin, colored by its leather" },
    { key = "spotlight", label = "Spotlight", tip = "The map dims, except where you skin" },
}
local SHOWS = {
    { key = "me", label = "Me", tip = "This character only" },
    { key = "account", label = "Account", tip = "Every character on this account" },
    { key = "community", label = "Community", tip = "Everyone who has shared, merged" },
}
local SCHEME_NAMES = { thermal = "Thermal", ember = "Ember" }
local WHENS = { { 0, "All time" }, { 30, "30 days" }, { 7, "7 days" } }

local model = {}

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
local function KeyCard(parent, width)
    local k = St.Frame("Frame", parent)
    St.Etch(k, STYLE.row, 12)
    k:SetWidth(width)
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
    k.ramp = {}
    for i = 1, 30 do
        local t = k:CreateTexture(nil, "ARTWORK")
        t:SetTexture(St.SOLID)
        t:SetHeight(8)
        k.ramp[i] = t
    end
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

    -- maxH: the room it has; past it, the key leaves out its scale line and demo note
    function k:Update(m, maxH, compact)
        local y
        local hasData = not m.message
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
        for _, t in ipairs(self.ramp) do t:SetShown(showRamp) end
        self.fewer:SetShown(showRamp)
        self.more:SetShown(showRamp)
        self.scale:SetShown(not compact and (hasData and m.scale ~= nil and m.mode ~= "points" or (hasData and m.kind == "continent")))
        if not hasData then
            self.message:SetText(m.message)
            y = -12 - self.message:GetStringHeight() - 10
        else
            self.big:SetText(Plural(m.skins or 0, "skin"))
            y = -34
            local rows
            if m.kind == "continent" then
                rows = { { "Zones", m.zones and tostring(m.zones) }, { "Most skins", m.bestZone } }
            else
                rows = { { "Most skinned", m.topWho }, { "Main leather", m.topLoot } }
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
            if showRamp then
                self.fewer:ClearAllPoints()
                self.fewer:SetPoint("TOPLEFT", self, "TOPLEFT", 11, y)
                local barW = width - 22 - self.fewer:GetStringWidth() - self.more:GetStringWidth() - 12
                local step = barW / #self.ramp
                for i, t in ipairs(self.ramp) do
                    t:SetWidth(step + 0.5)
                    t:ClearAllPoints()
                    t:SetPoint("TOPLEFT", self, "TOPLEFT", 11 + self.fewer:GetStringWidth() + 6 + (i - 1) * step, y - 1)
                    t:SetColorTexture(M.Ramp((i - 1) / (#self.ramp - 1)))
                end
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
        self.demo:SetShown(m.inDemo and not compact)
        if m.inDemo and not compact then
            self.demo:ClearAllPoints()
            self.demo:SetPoint("TOPLEFT", self, "TOPLEFT", 11, y - 2)
            y = y - 16
        end
        self:SetHeight(-y + 8)
        if maxH and not compact and -y + 8 > maxH then return self:Update(m, maxH, true) end
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
    sc.dot = sc:CreateTexture(nil, "ARTWORK")
    sc.dot:SetTexture(CIRCLE)
    sc.dot:SetSize(8, 8)
    sc.dot:SetPoint("LEFT", 11, 0)
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
    sc.start.tip = "A session also starts by itself with your first skin."
    sc.start:SetSize(70, 22)
    sc.start:SetPoint("RIGHT", -6, 0)
    sc.stop = St.IconButton(sc, "close-white", 11, function()
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
        GameTooltip:AddLine(string.format("%s in %s", Plural(s.count, "skin"), Clock(FN.SessionSeconds())), 1, 1, 1)
        GameTooltip:AddLine(string.format("%.1f per minute  ·  %d%% ruined", FN.SessionRate(),
            s.count > 0 and math.floor(s.ruined / s.count * 100 + 0.5) or 0), C.INK2[1], C.INK2[2], C.INK2[3])
        GameTooltip:Show()
    end)
    sc:SetScript("OnLeave", function() GameTooltip:Hide() end)

    function sc:Update()
        local running, paused = FN.SessionRunning(), FN.SessionPaused()
        self.start:SetShown(not running)
        self.pause:SetShown(running)
        self.stop:SetShown(running)
        self.detail:SetShown(running)
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
            self.detail:SetText(paused and "Paused" or Plural(FN.session.count, "skin"))
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
local function SettingsBody(parent, width)
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
        sw.fill = sw:CreateTexture(nil, "ARTWORK", nil, 2)
        sw.fill:SetTexture(CIRCLE)
        sw.fill:SetSize(26, 26)
        sw.fill:SetPoint("CENTER", sw.ring)
        local r1, g1, b1 = M.SchemeColor(name, 0.1)
        local r2, g2, b2 = M.SchemeColor(name, 0.95)
        St.VGradient(sw.fill, { r1, g1, b1 }, { r2, g2, b2 })
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
    b.whenLabel = Label(parent, "WHEN")
    b.whens = {}
    for i, w in ipairs(WHENS) do
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
    b.note:SetText("Strength is how bold the heat is; spread, how wide each glow reaches. Thin areas adjust themselves to how much you have skinned.")
    b.reset = Choice(parent, "Reset to defaults", function()
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
        y = y - 58
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
        y = y - 34
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
        y = y - 30
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
        y = y - 30
        self.note:ClearAllPoints()
        self.note:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        y = y - self.note:GetStringHeight() - 14
        self.reset:SetSize(width, 24)
        self.reset:ClearAllPoints()
        self.reset:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        return y - 24
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

local function DockOpen() return FN.db.settings.dockOpen ~= false end

local function SetSheet(open)
    dock.sheetOpen = open
    ui.gear = dock.gear
    dock.gear.open = open
    dock.gear:Tint()
    if open then
        sheet:Show()
        sheet.body:Layout(PAD, -44)
    else
        dock.body:Show()
    end
    -- one panel, two pages: the settings rise from the dock's bottom edge inside the same panel
    -- (the dock clips them) while the dock's own content fades and lifts away
    local rise = math.max(80, (dock:GetHeight() or 0) * 0.35)
    St.Animate("fn-sheet", open and 1 or 0, 0.3, open and "out" or "in", function(v)
        sheet:SetAlpha(v)
        sheet:ClearAllPoints()
        sheet:SetPoint("TOPLEFT", dock, "TOPLEFT", 0, -rise * (1 - v))
        sheet:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT", 0, -rise * (1 - v))
        dock.body:SetAlpha(1 - v)
        dock.body:ClearAllPoints()
        dock.body:SetPoint("TOPLEFT", dock, "TOPLEFT", 0, 16 * v)
        dock.body:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT", 0, 16 * v)
    end, function()
        if open then dock.body:Hide() else sheet:Hide() end
    end)
end

local function BuildDock()
    dock = St.Frame("Frame", WorldMapFrame)
    St.Etch(dock, STYLE.dock, 12)
    St.Grime(dock, 0.25, 12, 0, 150, 220) -- as on Forever Goal Tracker's window: strongest at the top
    dock:SetWidth(DOCK_W)
    dock:EnableMouse(true)
    dock:Hide()
    dock.body = CreateFrame("Frame", nil, dock)
    dock.body:SetAllPoints()
    local body = dock.body

    -- profession row and switch
    dock.profs = {}
    for i, p in ipairs(PROFESSIONS) do
        local b = CreateFrame("Button", nil, body)
        b:SetSize(28, 28)
        b:SetPoint("TOPLEFT", PAD + (i - 1) * 32, -PAD)
        b.rim = b:CreateTexture(nil, "BORDER")
        b.rim:SetAllPoints()
        b.rim:SetTexture(St.SOLID)
        b.fill = b:CreateTexture(nil, "ARTWORK", nil, 1)
        b.fill:SetPoint("TOPLEFT", 1, -1)
        b.fill:SetPoint("BOTTOMRIGHT", -1, 1)
        b.fill:SetTexture(St.SOLID)
        St.VGradient(b.fill, STYLE.row.top, STYLE.row.bottom)
        if p.icon then
            b.icon = b:CreateTexture(nil, "ARTWORK", nil, 2)
            b.icon:SetSize(18, 18)
            b.icon:SetPoint("CENTER")
            b.icon:SetTexture(St.Icon(p.icon))
        else
            b.initial = St.Text(b, 12, C.INK2)
            b.initial:SetPoint("CENTER", 0, 0)
            b.initial:SetJustifyH("CENTER")
            b.initial:SetText(p.label:sub(1, 1))
        end
        b.p = p
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(p.label, C.TITLE[1], C.TITLE[2], C.TITLE[3])
            if not p.ready then GameTooltip:AddLine("Coming later", 1, 1, 1) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        dock.profs[i] = b
    end
    dock.switch = Switch(body)
    dock.switch:SetPoint("TOPRIGHT", -PAD, -PAD - 5)
    dock.prof = St.Title(body, 15)
    dock.prof:SetPoint("TOPLEFT", PAD, -50)
    dock.place = St.Text(body, 10, C.SUBTEXT)
    dock.place:SetPoint("TOPRIGHT", -PAD, -53)
    dock.place:SetJustifyH("RIGHT")
    dock.place:SetWidth(110)
    dock.place:SetWordWrap(false)

    local y = -74
    Label(body, "VIEW"):SetPoint("TOPLEFT", PAD, y)
    local w3 = (INNER - 6) / 3
    dock.modes = {}
    for i, m in ipairs(MODES) do
        local b = Choice(body, m.label, function()
            M.S().mode = m.key
            Refresh()
        end, m.tip)
        b.key = m.key
        b:SetSize(w3, 22)
        b:SetPoint("TOPLEFT", PAD + (i - 1) * (w3 + 3), y - 14)
        dock.modes[i] = b
    end
    y = y - 42
    Label(body, "SHOW"):SetPoint("TOPLEFT", PAD, y)
    dock.shows = {}
    for i, sh in ipairs(SHOWS) do
        local b = Choice(body, sh.label, function()
            M.S().show = sh.key
            Refresh()
        end, sh.tip)
        b.key = sh.key
        b:SetSize(w3, 22)
        b:SetPoint("TOPLEFT", PAD + (i - 1) * (w3 + 3), y - 14)
        dock.shows[i] = b
    end
    y = y - 42
    Label(body, "LEATHER"):SetPoint("TOPLEFT", PAD, y)
    dock.leather = LeatherButton(body)
    dock.leather:SetSize(INNER, 24)
    dock.leather:SetPoint("TOPLEFT", PAD, y - 14)
    y = y - 46
    dock.key = KeyCard(body, INNER)
    dock.key:SetPoint("TOPLEFT", PAD, y)
    dock.session = SessionCard(body, INNER)

    -- the footer: Stats, Share and settings as three icons in a row, under a thin rule
    dock.stats = FooterIcon(body, "stats-white", "Stats", "Your skinning stats", function() FN.ToggleStats() end)
    dock.share = FooterIcon(body, "share-white", "Share", "Share your notes, or import someone else's",
        function() FN.ShowShare() end)
    dock.gear = GearButton(body, function() SetSheet(not dock.sheetOpen) end)
    local slot = INNER / 3
    for i, f in ipairs({ dock.stats, dock.share, dock.gear }) do
        f:SetPoint("BOTTOM", body, "BOTTOMLEFT", PAD + slot * (i - 0.5), PAD + 2)
    end
    dock.rule = Rule(body)
    dock.rule:SetHeight(1)
    dock.rule:SetPoint("BOTTOMLEFT", PAD, FOOTER_H)
    dock.rule:SetPoint("BOTTOMRIGHT", -PAD, FOOTER_H)

    -- the settings page: no panel of its own, it rises inside the dock (which clips it)
    dock:SetClipsChildren(true)
    sheet = CreateFrame("Frame", nil, dock)
    sheet:SetFrameLevel(dock:GetFrameLevel() + 20)
    sheet:SetAllPoints(dock)
    sheet:EnableMouse(true)
    sheet:Hide()
    local title = St.Title(sheet, 15)
    title:SetPoint("TOPLEFT", PAD, -PAD - 2)
    title:SetText("Map settings")
    local close = St.IconButton(sheet, "close-white", 12, function() SetSheet(false) end)
    close:SetPoint("TOPRIGHT", -PAD, -PAD - 2)
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
    sheet.body = SettingsBody(sheet, INNER)

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
    tab:SetScript("OnClick", function()
        FN.db.settings.dockOpen = not DockOpen()
        if list then list:Hide() end
        MapUI.Render(model)
    end)
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(DockOpen() and "Close" or "Open", 1, 1, 1)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tab:Hide()
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
    -- from the top of the map art down to the window's bottom edge (its footer included)
    local border = WorldMapFrame.BorderFrame
    if not (type(border) == "table" and border.GetBottom and border:GetBottom()) then border = WorldMapFrame end
    local top, bottom = container:GetTop(), border:GetBottom()
    if top and bottom and top > bottom then
        dock:SetHeight(top - bottom - (EDGE_TUCK - 2))
    else
        dock:SetHeight(container:GetHeight())
    end
    local edge = side == "RIGHT" and "TOPLEFT" or "TOPRIGHT"
    local mapEdge = side == "RIGHT" and "TOPRIGHT" or "TOPLEFT"
    local dir = side == "RIGHT" and 1 or -1
    -- slide in and out sideways from the map's edge
    -- (only a fold or unfold animates; any other redraw just places it)
    local moving = dock.wasOpen ~= nil and dock.wasOpen ~= open
    dock.wasOpen = open
    St.Animate("fn-dock", open and 1 or 0, moving and 0.28 or 0, open and "out" or "in", function(v)
        dock:SetAlpha(v)
        dock:ClearAllPoints()
        dock:SetPoint(edge, container, mapEdge, dir * (-gap + 24 * (v - 1)), 0)
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
            tab:SetPoint("TOPLEFT", container, "TOPRIGHT", -gap + (DOCK_W - TAB_TUCK) * v, -64)
        else
            tab:SetPoint("TOPRIGHT", container, "TOPLEFT", gap - (DOCK_W - TAB_TUCK) * v, -64)
        end
    end, function()
        if not DockOpen() then dock:Hide() end
    end)
    if open then dock:Show() end
    -- the tab sits just under the dock, so its inner edge hides beneath the dock's border
    tab:SetFrameLevel(math.max(1, (dock:GetFrameLevel() or 2) - 1))
    tab:Show()
    -- the chevron points out when folded, back toward the map when open
    local outward = side == "RIGHT" and math.pi / 2 or -math.pi / 2
    tab.chevron:SetRotation(open and -outward or outward)
end

local function RenderDock(m)
    local s = M.S()
    for _, b in ipairs(dock.profs) do
        local active = b.p.key == "skinning"
        local rim = active and C.ACCENT or { 0.29, 0.25, 0.20 }
        b.rim:SetVertexColor(rim[1], rim[2], rim[3], 1)
        local ink = active and C.TITLE or C.INK2
        local mark = b.p.icon and b.icon or b.initial
        if b.p.icon then mark:SetVertexColor(ink[1], ink[2], ink[3]) else mark:SetTextColor(ink[1], ink[2], ink[3]) end
        mark:SetAlpha(b.p.ready and 1 or 0.45)
    end
    dock.switch.toggle:SetOn(s.on)
    dock.prof:SetText("Skinning")
    dock.place:SetText(m.place or "")
    for _, b in ipairs(dock.modes) do b:SetChosen(b.key == s.mode) end
    for _, b in ipairs(dock.shows) do b:SetChosen(b.key == s.show) end
    dock.leather:Update()
    local room = dock:GetHeight() - 204 - 16 - 34 - (FOOTER_H + 12)
    dock.key:Update(m, room > 40 and room or nil)
    dock.session:Update()
    dock.session:ClearAllPoints()
    dock.session:SetPoint("BOTTOMLEFT", dock.body, "BOTTOMLEFT", PAD, FOOTER_H + 12)
    -- switched off, everything below the switch steps back
    local a = s.on and 1 or 0.45
    for _, f in ipairs({ dock.modes[1], dock.modes[2], dock.modes[3], dock.shows[1], dock.shows[2], dock.shows[3],
        dock.leather, dock.key }) do
        f:SetAlpha(a)
    end
    dock.gear:Tint()
    if dock.sheetOpen then sheet.body:Layout(PAD, -44) end
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
    end, "Start, pause or resume your skinning session")
    bar.session.icon = bar.session:CreateTexture(nil, "OVERLAY")
    bar.session.icon:SetSize(9, 9)
    bar.session.icon:SetPoint("LEFT", 9, 0)
    bar.session.text:ClearAllPoints()
    bar.session.text:SetPoint("LEFT", 24, 0)
    bar.stop = St.IconButton(bar, "close-white", 10, function()
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
        bar.session.text:SetText(Clock(FN.SessionSeconds()) .. "  ·  " .. Plural(FN.session.count, "skin"))
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
end

function MapUI.Init()
    if dock then return end
    M = FN.Map
    ui = M.ui
    St.Animate("fn-overlay", M.S().on and 1 or 0, 0, nil, M.SetOverlayAlpha) -- where the fade starts from
    BuildList()
    BuildDock()
    BuildToolbar()
    WorldMapFrame:HookScript("OnHide", function()
        if list then list:Hide() end
        if dock.sheetOpen then SetSheet(false) end
        if pop.open then SetPop(false) end
    end)
end
