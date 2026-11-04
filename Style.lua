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
    -- the map dock and its tab: Forever Goal Tracker's warm brown window fill (with St.Grime over
    -- it), edged like a panel so the map window's own gold frame stays the strongest line
    dock     = { top = { 0.105, 0.095, 0.080 }, bottom = { 0.016, 0.016, 0.016 }, edge = { 0.33, 0.29, 0.20, 1 } },
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

-- A pill: a fixed-height rounded bar, in three slices of Media/pill (round caps, a stretched
-- middle), so a hover can be as wide as its row with true round ends.
--   local p = St.Pill(frame, 15); p:Anchor(frame, 4, 4); p:SetColor(1, 0.82, 0, 0.14)
function St.Pill(parent, h, layer, sub)
    local p = {}
    local file = St.Media("pill")
    local function Slice(c0, c1)
        local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
        t:SetTexture(file)
        t:SetTexCoord(c0, c1, 0, 1)
        t:SetHeight(h)
        return t
    end
    p.l, p.m, p.r = Slice(0, 0.25), Slice(0.25, 0.75), Slice(0.75, 1)
    p.l:SetWidth(h / 2)
    p.r:SetWidth(h / 2)
    function p:Anchor(frame, left, right, y)
        self.l:ClearAllPoints()
        self.l:SetPoint("LEFT", frame, "LEFT", left or 0, y or 0)
        self.r:ClearAllPoints()
        self.r:SetPoint("RIGHT", frame, "RIGHT", -(right or 0), y or 0)
        self.m:ClearAllPoints()
        self.m:SetPoint("LEFT", self.l, "RIGHT", 0, 0)
        self.m:SetPoint("RIGHT", self.r, "LEFT", 0, 0)
    end
    function p:SetColor(r, g, b, a)
        self.l:SetVertexColor(r, g, b, a)
        self.m:SetVertexColor(r, g, b, a)
        self.r:SetVertexColor(r, g, b, a)
    end
    return p
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

-- Forever Goal Tracker's grime (FGT.AddGrime): Media/grime (512px, seamless) repeated at its real
-- size inside the etched border, above the fill and below everything else. Full strength for
-- `solid` px from the top, fading over `fade` px to a faint floor that keeps the dark gradient
-- from banding. offset (0-1) shifts where the tile starts so neighbours don't repeat in step.
do
    local GRIME = St.Media("grime")
    local TILE, FLOOR = 512, 0.07
    function St.Grime(frame, alpha, edgeSize, offset, solid, fade)
        local inset = math.floor((edgeSize or 12) / 4)
        solid, fade, offset = solid or 0, fade or 140, offset or 0
        local body = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
        local strip = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
        local rest = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
        for _, t in ipairs({ body, strip, rest }) do t:SetTexture(GRIME, "REPEAT", "REPEAT") end
        body:SetPoint("TOPLEFT", inset, -inset)
        body:SetPoint("TOPRIGHT", -inset, -inset)
        strip:SetPoint("TOPLEFT", body, "BOTTOMLEFT")
        strip:SetPoint("TOPRIGHT", body, "BOTTOMRIGHT")
        rest:SetPoint("TOPLEFT", strip, "BOTTOMLEFT")
        rest:SetPoint("BOTTOMRIGHT", -inset, inset)
        body:SetVertexColor(1, 1, 1, alpha)
        St.VGradient(strip, { 1, 1, 1 }, { 1, 1, 1 }, alpha, FLOOR)
        rest:SetVertexColor(1, 1, 1, FLOOR)
        local function Fit()
            local w, h = (frame:GetWidth() or 0) - 2 * inset, (frame:GetHeight() or 0) - 2 * inset
            if w <= 0 or h <= 0 then return end
            local s = math.min(solid, h)
            local f = math.max(1, math.min(fade, h - s))
            body:SetHeight(math.max(0.01, s))
            body:SetShown(s > 0)
            strip:SetHeight(f)
            local x0, x1, y0 = offset, offset + w / TILE, offset * 0.6
            body:SetTexCoord(x0, x1, y0, y0 + s / TILE)
            strip:SetTexCoord(x0, x1, y0 + s / TILE, y0 + (s + f) / TILE)
            rest:SetShown(h - s - f > 0)
            rest:SetTexCoord(x0, x1, y0 + (s + f) / TILE, y0 + h / TILE)
        end
        frame:HookScript("OnSizeChanged", Fit)
        Fit()
    end
end

-- The running session's breathing glow, the same wherever a session dot shows (the tracker, the
-- map dock's session row): a soft halo (Media/blob, added light) under the dot, swelling to about
-- twice its size and fading, one calm breath every 2 s. It runs on the game's clock (GetTime), like
-- the map's pins, and only while on: the game's own looping animation stuttered when a refresh
-- restarted it (seen in game). g:SetOn(on) starts or stops it.
local BREATH, GLOW_SIZE = 2.0, 18
St.BREATH = BREATH
function St.Glow(parent, dot, color)
    local g = CreateFrame("Frame", nil, parent)
    g:Hide()
    g.halo = parent:CreateTexture(nil, "ARTWORK", nil, 1)
    g.halo:SetTexture(St.Media("blob"))
    g.halo:SetBlendMode("ADD")
    g.halo:SetSize(GLOW_SIZE, GLOW_SIZE)
    g.halo:SetPoint("CENTER", dot, "CENTER", 0, 0)
    g.halo:SetVertexColor(color[1], color[2], color[3], 1)
    g.halo:Hide()
    g:SetScript("OnUpdate", function()
        local t = (GetTime() % BREATH) / BREATH
        local e = 1 - (1 - t) ^ 3
        local d = GLOW_SIZE * (1 + 1.1 * e)
        g.halo:SetSize(d, d)
        g.halo:SetAlpha(0.7 * (1 - e))
    end)
    function g:SetOn(on)
        on = on and true or false
        self.halo:SetShown(on)
        self:SetShown(on)
    end
    return g
end

-- a window that can be dragged anywhere and remembers where it was left (settings[key])
function St.Movable(frame, key)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    -- windows on the same layer come to the front when opened or clicked, whole, so two of them
    -- (stats and share) never weave their pieces through each other
    frame:SetToplevel(true)
    frame:HookScript("OnShow", function(self)
        self:Raise()
        -- a floating window fades in rather than appearing (closing stays instant, so a click on
        -- its X never waits)
        local function Apply(v) self:SetAlpha(v) end
        St.Animate("fn-win-" .. key, 0, 0, nil, Apply) -- start from clear
        St.Animate("fn-win-" .. key, 1, St.DUR.quick + 0.04, "soft", Apply)
    end)
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

-- A slider in the house style: a recessed track, a gold fill up to the knob, and Forever Goal
-- Tracker's knob. s:Set(v) places it without calling back; dragging calls onChange(v).
function St.Slider(parent, width, min, max, step, onChange)
    local s = CreateFrame("Slider", nil, parent)
    s:SetSize(width, 16)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s.track = s:CreateTexture(nil, "BACKGROUND")
    s.track:SetColorTexture(0.012, 0.012, 0.012, 1)
    s.track:SetHeight(6)
    s.track:SetPoint("LEFT", 0, 0)
    s.track:SetPoint("RIGHT", 0, 0)
    s.fill = s:CreateTexture(nil, "BORDER")
    s.fill:SetTexture(SOLID)
    s.fill:SetHeight(4)
    s.fill:SetPoint("LEFT", s.track, "LEFT", 1, 0)
    St.HGradient(s.fill, { 0.32, 0.18, 0.01 }, { 1.00, 0.86, 0.30 })
    local knob = s:CreateTexture(nil, "OVERLAY")
    knob:SetTexture(St.Media("knob"))
    knob:SetSize(14, 14)
    St.VGradient(knob, { 1.00, 0.96, 0.78 }, { 0.92, 0.70, 0.22 })
    s:SetThumbTexture(knob)
    local quiet = false
    local function Fill(v)
        s.fill:SetWidth(math.max(1, (width - 2) * (v - min) / (max - min)))
    end
    s:SetScript("OnValueChanged", function(_, v)
        Fill(v)
        if not quiet then onChange(v) end
    end)
    function s:Set(v)
        quiet = true
        self:SetValue(v)
        quiet = false
        Fill(v)
    end
    return s
end

-- ------------------------------------------------------------
-- Motion: one small driver for every slide and fade
-- ------------------------------------------------------------
-- St.Animate(id, to, seconds, ease, apply, done): moves a number from where it is now (its last
-- value, or `to` the first time) to `to`, calling apply(value) every frame. A new call with the
-- same id takes over from wherever the old one had got to, so a second click mid-way reverses
-- smoothly instead of snapping. ease: "out" (fast then settling: opening) or "in" (gentle start:
-- closing). The driver runs only while something is moving.
local tweens, values, driver = {}, {}, nil
local EASE = {
    out = function(p) return 1 - (1 - p) ^ 3 end,
    ["in"] = function(p) return p * p * p end,
    both = function(p) return p < 0.5 and 4 * p * p * p or 1 - (-2 * p + 2) ^ 3 / 2 end,
    -- a longer, softer settle than "out": things arrive quickly and come to rest without a thud
    soft = function(p) return 1 - (1 - p) ^ 4 end,
    -- the same, mirrored: a gentle departure that speeds up, and finishes without a lurch
    leave = function(p) return p < 0.5 and 2 * p * p or 1 - (-2 * p + 2) ^ 2 / 2 end,
}
-- One set of durations for the whole add-on, so every motion has the same rhythm:
--   quick: a state change you cause (a chosen button, a hover)
--   base: something moving a short way (a list, a pop-over, the toolbar)
--   slow: a panel or page arriving or leaving (the dock, settings)
St.DUR = { quick = 0.16, base = 0.26, slow = 0.34 }
function St.Animate(id, to, seconds, ease, apply, done)
    local from = values[id]
    if from == nil then from = to end
    if not seconds or seconds <= 0 or from == to then
        tweens[id] = nil
        values[id] = to
        apply(to)
        if done then done() end
        return
    end
    if not driver then
        driver = CreateFrame("Frame")
        driver:SetScript("OnUpdate", function(self, dt)
            local any = false
            for key, t in pairs(tweens) do
                t.t = t.t + dt
                local p = math.min(1, t.t / t.dur)
                local v = t.from + (t.to - t.from) * (EASE[t.ease] or EASE.both)(p)
                values[key] = v
                t.apply(v)
                if p >= 1 then
                    tweens[key] = nil
                    if t.done then t.done() end
                else
                    any = true
                end
            end
            if not any and not next(tweens) then self:Hide() end
        end)
    end
    tweens[id] = { from = from, to = to, t = 0, dur = seconds, ease = ease, apply = apply, done = done }
    driver:Show()
end

-- where an animation last left its value (nil before the first)
function St.AnimValue(id) return values[id] end

-- ------------------------------------------------------------
-- A mouse-wheel scroll area, after Forever Goal Tracker's: content slides under a soft bottom
-- shade while there is more below (the shade eases away at the end), and a slim bronze thumb
-- shows where you are. The shade is stacked flat strips, one per pixel, eased, as on FGT (real
-- gradient calls have come and gone between clients). Anchor o.scroll, put things in o.content
-- (its top-left is the scroll area's), then o:SetHeight(contentHeight) after each layout.
--   color: the panel's color where the shade sits, so rows seem to slide under it
-- ------------------------------------------------------------
function St.Scroll(parent, color)
    local o = {}
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:EnableMouseWheel(true)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    o.scroll, o.content = scroll, content

    color = color or { 0.03, 0.028, 0.025 }
    local SHADE = 28
    local fade = CreateFrame("Frame", nil, parent)
    fade:SetHeight(SHADE)
    fade:SetFrameLevel(parent:GetFrameLevel() + 20)
    fade:SetPoint("BOTTOMLEFT", scroll, "BOTTOMLEFT", 0, 0)
    fade:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0)
    for i = 1, SHADE do
        local a = (1 - (i - 0.5) / SHADE) ^ 1.6
        local t = fade:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(color[1], color[2], color[3], a)
        t:SetPoint("BOTTOMLEFT", fade, "BOTTOMLEFT", 0, i - 1)
        t:SetPoint("BOTTOMRIGHT", fade, "BOTTOMRIGHT", 0, i - 1)
        t:SetHeight(1)
    end
    fade:Hide()
    o.fade = fade

    local thumb = parent:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(STYLE.row.edge[1], STYLE.row.edge[2], STYLE.row.edge[3], 0.95)
    thumb:SetWidth(2)
    thumb:Hide()

    local function Max() return math.max(0, (content:GetHeight() or 0) - (scroll:GetHeight() or 0)) end

    local fadeTo -- the shade eases in and out over 0.3 s as you reach the end or leave it
    local function Shade(on)
        local target = on and 1 or 0
        if fadeTo == target then return end
        fadeTo = target
        if on and not fade:IsShown() then
            fade:SetAlpha(0)
            fade:Show()
        end
        fade:SetScript("OnUpdate", function(self, dt)
            local a = self:GetAlpha()
            a = target > a and math.min(target, a + dt / 0.3) or math.max(target, a - dt / 0.3)
            self:SetAlpha(a)
            if a == target then
                self:SetScript("OnUpdate", nil)
                if target == 0 then self:Hide() end
            end
        end)
    end

    function o:Update()
        local max, cur = Max(), scroll:GetVerticalScroll() or 0
        if cur > max then
            cur = max
            scroll:SetVerticalScroll(cur)
        end
        Shade(max > 1 and cur < max - 1)
        local viewH = scroll:GetHeight() or 0
        if max > 1 and viewH > 0 then
            local contentH = content:GetHeight()
            local thumbH = math.max(18, viewH * viewH / contentH)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, -(cur / max) * (viewH - thumbH))
            thumb:SetHeight(thumbH)
            thumb:Show()
        else
            thumb:Hide()
        end
    end
    function o:SetHeight(h)
        content:SetHeight(math.max(1, h))
        content:SetWidth(scroll:GetWidth() or 1)
        self:Update()
    end
    function o:ScrollTo(v)
        scroll:SetVerticalScroll(math.max(0, math.min(Max(), v)))
        self:Update()
    end
    scroll:SetScript("OnMouseWheel", function(_, delta) o:ScrollTo((scroll:GetVerticalScroll() or 0) - delta * 36) end)
    scroll:SetScript("OnSizeChanged", function(self)
        content:SetWidth(self:GetWidth())
        o:Update()
    end)
    return o
end
