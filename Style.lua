local ADDON, FN = ...

-- The look Fieldnotes shares with Forever Goal Tracker, so the two read as one family:
-- etched tiles (a warm vertical gradient inside the tooltip border, with a 1px sheen catching
-- light along the top), gold for whatever is chosen, title-gold headings with a dark drop
-- shadow, and the same pill switch, knob and icons (Media/pill, Media/knob, Media/icons).
-- Colors and gradients are Forever Goal Tracker's own values (its Core.lua C and STYLE).
-- Text uses the game's own font (STANDARD_TEXT_FONT) at set sizes.

local St = {}
FN.Style = St

local C = {
    TITLE   = { 1.00, 0.843, 0.369 }, -- heading gold
    ACCENT  = { 1.00, 0.82, 0.00 },   -- gold
    GOLD2   = { 0.784, 0.608, 0.102 }, -- deep gold
    TEXT    = { 0.91, 0.91, 0.91 },
    INK2    = { 0.741, 0.741, 0.741 },
    SUBTEXT = { 0.541, 0.541, 0.541 },
}
St.C = C

local STYLE = {
    window   = { top = { 0.105, 0.095, 0.080 }, bottom = { 0.016, 0.016, 0.016 }, edge = { 0.78, 0.61, 0.10, 1 } },
    row      = { top = { 0.150, 0.142, 0.130 }, bottom = { 0.050, 0.048, 0.045 }, edge = { 0.28, 0.26, 0.22, 1 } },
    panel    = { top = { 0.060, 0.057, 0.052 }, bottom = { 0.022, 0.022, 0.022 }, edge = { 0.33, 0.29, 0.20, 1 } },
    button   = { top = { 0.240, 0.225, 0.200 }, bottom = { 0.080, 0.075, 0.068 }, edge = { 0.42, 0.37, 0.26, 1 } },
    btnHover = { top = { 0.330, 0.300, 0.240 }, bottom = { 0.120, 0.110, 0.090 }, edge = { 0.85, 0.68, 0.20, 1 } },
    rowSel   = { top = { 0.380, 0.290, 0.060 }, bottom = { 0.110, 0.080, 0.015 }, edge = { 1.00, 0.82, 0.00, 1 } },
    goldHover = { top = { 0.470, 0.365, 0.085 }, bottom = { 0.155, 0.115, 0.025 }, edge = { 1.00, 0.89, 0.30, 1 } },
}
St.STYLE = STYLE

local SOLID = "Interface\\Buttons\\WHITE8x8"
local ETCH_EDGE = "Interface\\Tooltips\\UI-Tooltip-Border"
function St.Media(name) return "Interface\\AddOns\\" .. ADDON .. "\\Media\\" .. name end
function St.Icon(name) return St.Media("icons\\" .. name) end
St.SOLID = SOLID

-- A frame that can take a backdrop (Classic Era and Forever both need the template).
function St.Frame(kind, parent)
    return CreateFrame(kind, nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
end

-- Vertical gradient, top color to bottom color. Two colour objects are reused for every call
-- (one made per call would be garbage on every redraw). Falls back to a flat midpoint.
local gradLow, gradHigh
function St.VGradient(tex, top, bottom, topA, bottomA)
    if CreateColor and not gradLow then
        gradLow, gradHigh = CreateColor(0, 0, 0, 1), CreateColor(0, 0, 0, 1)
    end
    local ok = false
    if gradLow and tex.SetGradient then
        gradLow.r, gradLow.g, gradLow.b, gradLow.a = bottom[1], bottom[2], bottom[3], bottomA or 1
        gradHigh.r, gradHigh.g, gradHigh.b, gradHigh.a = top[1], top[2], top[3], topA or 1
        ok = pcall(tex.SetGradient, tex, "VERTICAL", gradLow, gradHigh)
    end
    if not ok then
        tex:SetVertexColor((top[1] + bottom[1]) / 2, (top[2] + bottom[2]) / 2, (top[3] + bottom[3]) / 2,
            ((topA or 1) + (bottomA or 1)) / 2)
    end
end

-- Horizontal gradient, left color to right color (same reused colour objects).
function St.HGradient(tex, left, right, leftA, rightA)
    if CreateColor and not gradLow then
        gradLow, gradHigh = CreateColor(0, 0, 0, 1), CreateColor(0, 0, 0, 1)
    end
    local ok = false
    if gradLow and tex.SetGradient then
        gradLow.r, gradLow.g, gradLow.b, gradLow.a = left[1], left[2], left[3], leftA or 1
        gradHigh.r, gradHigh.g, gradHigh.b, gradHigh.a = right[1], right[2], right[3], rightA or 1
        ok = pcall(tex.SetGradient, tex, "HORIZONTAL", gradLow, gradHigh)
    end
    if not ok then tex:SetVertexColor(right[1], right[2], right[3], ((leftA or 1) + (rightA or 1)) / 2) end
end

-- Turns a backdrop frame into an etched gradient tile; frame:SetEtch(style) switches states.
-- alpha < 1 lets the map show faintly through panels that sit on it.
function St.Etch(frame, style, edgeSize, alpha)
    edgeSize = edgeSize or 12
    local inset = math.floor(edgeSize / 4)
    if frame.SetBackdrop then
        frame:SetBackdrop({ edgeFile = ETCH_EDGE, edgeSize = edgeSize,
            insets = { left = inset, right = inset, top = inset, bottom = inset } })
    end
    frame.etchBg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    frame.etchBg:SetTexture(SOLID)
    frame.etchBg:SetPoint("TOPLEFT", inset, -inset)
    frame.etchBg:SetPoint("BOTTOMRIGHT", -inset, inset)
    -- 1px inner top sheen, the bevel catching light
    frame.etchHi = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
    frame.etchHi:SetTexture(SOLID)
    frame.etchHi:SetHeight(1)
    frame.etchHi:SetPoint("TOPLEFT", inset, -inset)
    frame.etchHi:SetPoint("TOPRIGHT", -inset, -inset)
    frame.etchHi:SetVertexColor(1, 0.92, 0.70, 0.07)
    function frame:SetEtch(st)
        St.VGradient(self.etchBg, st.top, st.bottom, alpha, alpha)
        if self.SetBackdropBorderColor then
            self:SetBackdropBorderColor(st.edge[1], st.edge[2], st.edge[3], st.edge[4] or 1)
        end
    end
    frame:SetEtch(style)
end

function St.Text(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size or 11, "")
    local c = color or C.TEXT
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetJustifyH("LEFT")
    return fs
end

-- a heading: title gold with a dark drop shadow
function St.Title(parent, size)
    local fs = St.Text(parent, size or 13, C.TITLE)
    fs:SetShadowColor(0.2, 0.14, 0.02, 1)
    fs:SetShadowOffset(1, -1)
    return fs
end

-- A small etched button; b:SetChosen(true) makes it gold, the way Forever Goal Tracker marks
-- the chosen option in a row of choices.
function St.ChoiceButton(parent, onClick)
    local b = St.Frame("Button", parent)
    St.Etch(b, STYLE.button, 8)
    b.text = St.Text(b, 10, C.INK2)
    b.text:SetPoint("CENTER")
    b:SetHeight(22)
    function b:SetChosen(on)
        self.chosen = on
        self:SetEtch(on and STYLE.rowSel or STYLE.button)
        local c = on and C.TITLE or C.INK2
        self.text:SetTextColor(c[1], c[2], c[3])
    end
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        self:SetEtch(self.chosen and STYLE.goldHover or STYLE.btnHover)
        if self.tip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(self.tip, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self:SetChosen(self.chosen)
        if self.tip then GameTooltip:Hide() end
    end)
    b:SetChosen(false)
    return b
end

-- On/off switch: a pill track with a 1px rim and a gradient (gold on, dark off) and a round
-- knob with its own top-lit gradient and a soft shadow. t:SetOn(on) moves it.
local TOGGLE_LOOK = {
    on  = { rim = { 0.85, 0.68, 0.20 }, top = { 0.55, 0.42, 0.10 }, bottom = { 0.22, 0.16, 0.03 },
            knobTop = { 1.00, 0.96, 0.78 }, knobBottom = { 0.92, 0.70, 0.22 } },
    off = { rim = { 0.32, 0.30, 0.26 }, top = { 0.17, 0.16, 0.15 }, bottom = { 0.05, 0.05, 0.05 },
            knobTop = { 0.66, 0.65, 0.62 }, knobBottom = { 0.36, 0.35, 0.33 } },
}
function St.Toggle(parent)
    local t = CreateFrame("Frame", nil, parent)
    t:SetSize(36, 18)
    t.rim = t:CreateTexture(nil, "BACKGROUND")
    t.rim:SetTexture(St.Media("pill"))
    t.rim:SetAllPoints(t)
    t.fill = t:CreateTexture(nil, "BORDER")
    t.fill:SetTexture(St.Media("pill"))
    t.fill:SetPoint("TOPLEFT", 1, -1)
    t.fill:SetPoint("BOTTOMRIGHT", -1, 1)
    t.shadow = t:CreateTexture(nil, "ARTWORK", nil, 1)
    t.shadow:SetTexture(St.Media("knob"))
    t.shadow:SetSize(14, 14)
    t.shadow:SetVertexColor(0, 0, 0, 0.55)
    t.knob = t:CreateTexture(nil, "ARTWORK", nil, 2)
    t.knob:SetTexture(St.Media("knob"))
    t.knob:SetSize(14, 14)
    function t:SetOn(on, hover)
        local L = on and TOGGLE_LOOK.on or TOGGLE_LOOK.off
        local lift = hover and 0.12 or 0
        self.rim:SetVertexColor(math.min(1, L.rim[1] + lift), math.min(1, L.rim[2] + lift), math.min(1, L.rim[3] + lift))
        St.VGradient(self.fill, L.top, L.bottom)
        St.VGradient(self.knob, L.knobTop, L.knobBottom)
        local x = on and 20 or 2
        self.knob:ClearAllPoints()
        self.knob:SetPoint("LEFT", self, "LEFT", x, 0)
        self.shadow:ClearAllPoints()
        self.shadow:SetPoint("LEFT", self, "LEFT", x, -1)
    end
    return t
end

-- A recessed track with a lit gold fill (Forever Goal Tracker's progress bar, square-cornered):
-- deep amber on the left building to gold at the tip, the lower half shaded, a 1px sheen on top.
-- bar:SetValue(0..1)
function St.Bar(parent, height)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(height)
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetAllPoints()
    bar.track:SetColorTexture(0.012, 0.012, 0.012, 1)
    bar.lip = bar:CreateTexture(nil, "BORDER")
    bar.lip:SetColorTexture(1, 0.9, 0.6, 0.08)
    bar.lip:SetHeight(1)
    bar.lip:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
    bar.lip:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    bar.fill = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    bar.fill:SetTexture(SOLID)
    bar.fill:SetPoint("TOPLEFT", 1, -1)
    bar.fill:SetPoint("BOTTOMLEFT", 1, 1)
    St.HGradient(bar.fill, { 0.32, 0.18, 0.01 }, { 1.00, 0.86, 0.30 })
    bar.shade = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    bar.shade:SetTexture(SOLID)
    bar.shade:SetAllPoints(bar.fill)
    St.VGradient(bar.shade, { 0, 0, 0 }, { 0, 0, 0 }, 0, 0.45)
    bar.sheen = bar:CreateTexture(nil, "OVERLAY")
    bar.sheen:SetTexture(SOLID)
    bar.sheen:SetHeight(1)
    bar.sheen:SetPoint("TOPLEFT", bar.fill, "TOPLEFT")
    bar.sheen:SetPoint("TOPRIGHT", bar.fill, "TOPRIGHT")
    St.HGradient(bar.sheen, { 1, 0.9, 0.6 }, { 1, 1, 0.9 }, 0.05, 0.8)
    function bar:SetValue(v)
        v = math.max(0, math.min(1, v or 0))
        local w = math.max(1, (self:GetWidth() - 2) * v)
        self.fill:SetWidth(w)
        self.fill:SetShown(v > 0)
        self.shade:SetShown(v > 0)
        self.sheen:SetShown(v > 0)
    end
    return bar
end

-- a small icon button: Media/icons/<name>-white tinted grey, brightening on hover
function St.IconButton(parent, icon, size, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(St.Icon(icon))
    b.icon:SetVertexColor(C.INK2[1], C.INK2[2], C.INK2[3])
    b:SetScript("OnEnter", function(self) self.icon:SetVertexColor(C.TITLE[1], C.TITLE[2], C.TITLE[3]) end)
    b:SetScript("OnLeave", function(self) self.icon:SetVertexColor(C.INK2[1], C.INK2[2], C.INK2[3]) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- a window that can be dragged anywhere and remembers where it was left (settings[key])
function St.Movable(frame, key)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        FN.db.settings[key] = { point, relPoint, x, y }
    end)
end
function St.PlaceSaved(frame, key, point, relPoint, x, y)
    local p = FN.db.settings[key]
    frame:ClearAllPoints()
    if type(p) == "table" and p[1] then
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        frame:SetPoint(point, UIParent, relPoint, x, y)
    end
end
