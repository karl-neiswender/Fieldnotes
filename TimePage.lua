local ADDON, FN = ...

-- The Time page (design/time-2026-11-17/Playtime-v4.html, approved by Karl 2026-11-17). It lives
-- in the dock, opened by the Time tab (a clock, just above Stats): how long you play, across every
-- character on this account. One page that scrolls:
--   range       Week, 2 Weeks, Month (a column a day), Year (a column a month), All (a column a year)
--   headline    time played, how many characters, against the range before
--   three facts days played, a day you play, longest session (a clicked day: sessions, longest,
--               first log in)
--   AFK switch  AFK time is left out unless this is on
--   chart       columns stacked by class color; a click narrows the page to that column
--   class key   each class's share
--   When you play  day by hour, as on Stats
--   Gathered    each profession's total and coin, a rate per hour played on hover
--   Characters  grouped by class (with its share): level, gold looted in coin icons, time under
--               their own headings, a bar of the share of all time; a click opens what they
--               gathered, the coin they carry and their time played in all
-- The time itself is kept by Playtime.lua. Drawn with pooled textures, only when the page opens or
-- its choices or the data change.

local St = FN.Style
local C, STYLE = St.C, St.STYLE
local TP = {}
FN.TimePage = TP
local K = FN.StatsPage.kit -- (StatsPage.lua loads first)

local SOLID = St.SOLID
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local Date = date or (os and os.date)
local MON = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
local DOW_ONE = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" }
local UP, DOWN = "|cff8fd18f", "|cffd9a08a"
local RANGES = {
    { key = "7", label = "Week", days = 7, word = "in the last 7 days", prev = "the 7 days before" },
    { key = "14", label = "2 Weeks", days = 14, word = "in the last 2 weeks", prev = "the 2 weeks before" },
    { key = "30", label = "Month", days = 30, word = "in the last 30 days", prev = "the 30 days before" },
    { key = "year", label = "Year", word = "in the last 12 months", prev = "the 12 months before" },
    { key = "all", label = "All", word = "all time" },
}
local RANGE = {}
for _, r in ipairs(RANGES) do RANGE[r.key] = r end
-- the class colors the game uses, for clients without RAID_CLASS_COLORS
local CLASS_FALLBACK = {
    WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 }, HUNTER = { 0.67, 0.83, 0.45 },
    ROGUE = { 1.00, 0.96, 0.41 }, PRIEST = { 1.00, 1.00, 1.00 }, SHAMAN = { 0.00, 0.44, 0.87 },
    MAGE = { 0.41, 0.80, 0.94 }, WARLOCK = { 0.58, 0.51, 0.79 }, DRUID = { 1.00, 0.49, 0.04 },
}

-- ------------------------------------------------------------
-- Small helpers
-- ------------------------------------------------------------
local function ClassColor(class)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c and c.r then return { c.r, c.g, c.b } end
    return CLASS_FALLBACK[class] or C.INK2
end
local function ClassName(class)
    local n = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]
    return n or (class:sub(1, 1) .. class:sub(2):lower())
end
local function Hex(c) return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end

-- 95 -> "1m", 5400 -> "1h 30m", 400 hours -> "400h"
local function Fmt(secs)
    local m = math.floor((secs or 0) / 60 + 0.5)
    if m < 60 then return m .. "m" end
    local h = math.floor(m / 60)
    if h >= 100 then return K.Commas(h) .. "h" end
    return h .. "h" .. (m % 60 > 0 and (" " .. (m % 60) .. "m") or "")
end

-- seconds to whole minutes, so a class total is the sum of the minutes its rows show
local function Minutes(secs) return math.floor((secs or 0) / 60 + 0.5) * 60 end

-- coin with the game's coin icons, two units as in the mockup: gold and silver, or silver and copper
-- (letters read as seconds next to a time column: "2s" beside "59m")
local COIN_ICON = {
    g = "|TInterface\\MoneyFrame\\UI-GoldIcon:10:10:1:0|t",
    s = "|TInterface\\MoneyFrame\\UI-SilverIcon:10:10:1:0|t",
    c = "|TInterface\\MoneyFrame\\UI-CopperIcon:10:10:1:0|t",
}
local function Coins(copper)
    copper = math.floor(tonumber(copper) or 0)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local out = {}
    if g > 0 then out[#out + 1] = K.Commas(g) .. COIN_ICON.g end
    if s > 0 then out[#out + 1] = s .. COIN_ICON.s end
    if (c > 0 and g == 0) or #out == 0 then out[#out + 1] = c .. COIN_ICON.c end
    return table.concat(out, " ")
end

-- a day as a number, 20261117, and back
local function KeyOf(t)
    local d = Date and Date("*t", t)
    if type(d) ~= "table" then return 0, 1, 0 end
    return d.year * 10000 + d.month * 100 + d.day, (d.wday + 5) % 7 + 1, d.hour or 0
end
local function Split(key) return math.floor(key / 10000), math.floor(key / 100) % 100, key % 100 end
-- Monday = 1, for any day (Sakamoto's method)
local function Weekday(key)
    local y, m, d = Split(key)
    local t = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
    if m < 3 then y = y - 1 end
    local w = (y + math.floor(y / 4) - math.floor(y / 100) + math.floor(y / 400) + t[m] + d) % 7 -- 0 = Sunday
    return (w + 6) % 7 + 1
end

-- ------------------------------------------------------------
-- The numbers
-- ------------------------------------------------------------
-- The range's columns, each a span of day keys [lo, hi]. Days are walked back from today's noon,
-- so a clock change never puts two columns on one day.
local function Columns(range, firstKey)
    local cols = {}
    local today = time()
    local noon = today - (tonumber(Date and Date("%H", today)) or 12) * 3600 + 12 * 3600
    local R = RANGE[range]
    if R.days then
        for i = R.days - 1, 0, -1 do
            local key, wd = KeyOf(noon - i * 86400)
            local _, m, d = Split(key)
            local every = R.days == 7 and 1 or (R.days == 14 and 2 or 5)
            cols[#cols + 1] = { lo = key, hi = key,
                tick = R.days == 7 and K.DOW[wd] or (i % every == 0 and tostring(d) or ""),
                name = (i == 0 and "Today" or (i == 1 and "Yesterday" or DOW_ONE[wd])) .. ", " .. MON[m] .. " " .. d }
        end
        -- the range before: as many days again
        local first = KeyOf(noon - (2 * R.days - 1) * 86400)
        cols.prevLo, cols.prevHi = first, KeyOf(noon - R.days * 86400)
    elseif range == "year" then
        local y, m = Split(KeyOf(today))
        for i = 11, 0, -1 do
            local yy, mm = y, m - i
            while mm < 1 do mm, yy = mm + 12, yy - 1 end
            cols[#cols + 1] = { lo = yy * 10000 + mm * 100 + 1, hi = yy * 10000 + mm * 100 + 31,
                tick = MON[mm]:sub(1, 1), name = MON[mm] .. " " .. yy }
        end
        cols.prevLo, cols.prevHi = cols[1].lo - 10000, cols[1].lo - 1
    else
        local y = Split(KeyOf(today))
        local from = math.min(y, firstKey and Split(firstKey) or y)
        if y - from > 11 then from = y - 11 end
        for yy = from, y do
            cols[#cols + 1] = { lo = yy * 10000 + 101, hi = yy * 10000 + 1231, tick = tostring(yy), name = tostring(yy) }
        end
    end
    cols.noon = noon
    return cols
end

-- days from today back to lo (not before the first day Fieldnotes kept time), within [lo, hi]
local function DaysIn(noon, lo, hi, firstKey)
    local n, floor = 0, math.max(lo, firstKey or lo)
    for i = 0, 4000 do
        local key = KeyOf(noon - i * 86400)
        if key < floor then break end
        if key <= hi then n = n + 1 end
    end
    return math.max(1, n)
end

-- everything the page shows for the range (and the chosen column, if any)
function TP.Collect(range, focus, withAfk)
    local store = FN.Playtime and FN.Playtime.Store() or { days = {}, roster = {}, sessions = {} }
    local view = FN.View()
    if view ~= FN.db and view.playtime then store = view.playtime end -- (demo mode's sample)
    local firstKey
    for key in pairs(store.days) do if not firstKey or key < firstKey then firstKey = key end end
    local cols = Columns(range, firstKey)
    if focus and not cols[focus] then focus = nil end
    local lo, hi = cols[1].lo, cols[#cols].hi
    if focus then lo, hi = cols[focus].lo, cols[focus].hi end
    local d = { cols = cols, focus = focus, roster = store.roster, firstKey = firstKey, secs = 0, prev = 0,
        perChar = {}, byClass = {}, heat = {}, got = {}, copper = 0, days = {}, sessions = 0, longest = 0,
        firstHour = nil, all = {} }
    for dw = 1, 7 do
        d.heat[dw] = {}
        for h = 0, 23 do d.heat[dw][h] = 0 end
    end
    local roster = store.roster
    local function Char(c)
        local v = d.perChar[c]
        if not v then
            v = { secs = 0, copper = 0, got = {} }
            d.perChar[c] = v
        end
        return v
    end

    -- time: per day, per character, per hour
    for key, chars in pairs(store.days) do
        for c, e in pairs(chars) do
            local p, a = 0, 0
            for _, v in pairs(e.p or {}) do p = p + v end
            for _, v in pairs(e.a or {}) do a = a + v end
            local secs = p + (withAfk and a or 0)
            d.all[c] = (d.all[c] or 0) + p + a
            if secs > 0 then
                local class = roster[c] and roster[c].class
                for _, col in ipairs(cols) do
                    if key >= col.lo and key <= col.hi then
                        col.secs = (col.secs or 0) + secs
                        if class then
                            col.byClass = col.byClass or {}
                            col.byClass[class] = (col.byClass[class] or 0) + secs
                        end
                    end
                end
                if key >= lo and key <= hi then
                    d.secs = d.secs + secs
                    Char(c).secs = Char(c).secs + secs
                    if class then d.byClass[class] = (d.byClass[class] or 0) + secs end
                    d.days[key] = true
                    local dw = Weekday(key)
                    for h, v in pairs(e.p or {}) do d.heat[dw][h] = d.heat[dw][h] + v end
                    if withAfk then for h, v in pairs(e.a or {}) do d.heat[dw][h] = d.heat[dw][h] + v end end
                elseif not focus and cols.prevLo and key >= cols.prevLo and key <= cols.prevHi then
                    d.prev = d.prev + secs
                end
            end
        end
    end
    -- All: each character's /played from before Fieldnotes kept time
    d.pre = 0
    if range == "all" and not focus then
        for c, r in pairs(roster) do
            if (r.pre or 0) > 0 then
                d.pre = d.pre + r.pre
                Char(c).secs = Char(c).secs + r.pre
                if r.class then d.byClass[r.class] = (d.byClass[r.class] or 0) + r.pre end
            end
        end
    end

    -- sessions: how many, the longest, the first log in of a chosen day
    for _, s in ipairs(store.sessions) do
        local c, start, secs, afk = FN.Playtime.DecodeSession(s)
        if c then
            local key, _, hour = KeyOf(start)
            if key >= lo and key <= hi then
                local len = secs + (withAfk and afk or 0)
                if len >= 60 then
                    d.sessions = d.sessions + 1
                    d.longest = math.max(d.longest, len)
                    if not d.firstHour or hour < d.firstHour then d.firstHour = hour end
                end
            end
        end
    end

    -- what was gathered, per character: every profession's records in the range
    local M = FN.Map
    local since = time() - (DaysIn(cols.noon, lo, hi) + 2) * 86400
    for _, p in ipairs(M.PROFS) do
        for _, list in pairs(view.events[p.key] or {}) do
            for _, str in ipairs(list) do
                local t = tonumber(str:match("^%d*:%d*:(%d+):"))
                if t and t >= since then
                    local r = FN.Decode(str)
                    local key = r and KeyOf(r.time)
                    if key and key >= lo and key <= hi then
                        local v = Char(r.char)
                        if p.money then
                            local n = r.items[FN.COIN] or 0
                            d.copper, v.copper = d.copper + n, v.copper + n
                        elseif p.key ~= "cloth" or next(r.items) then
                            d.got[p.key] = (d.got[p.key] or 0) + 1
                            v.got[p.key] = (v.got[p.key] or 0) + 1
                        end
                    end
                end
            end
        end
    end
    d.nDays = 0
    for _ in pairs(d.days) do d.nDays = d.nDays + 1 end
    d.span = DaysIn(cols.noon, lo, hi, firstKey)
    return d
end

-- ------------------------------------------------------------
-- The page
-- ------------------------------------------------------------
-- opts: inner (the content's width), pad, top (the first row's y), ctrlH, DockScroll
function TP.Build(parent, opts)
    local Tip, Begin, Rect, Finish, Hoverable, Section = K.Tip, K.Begin, K.Rect, K.Finish, K.Hoverable, K.Section
    local CP, FAINT, EMPTY = K.CP, K.FAINT, K.EMPTY
    local M = FN.Map
    local W, PAD = opts.inner, opts.pad
    local CW = W - CP * 2
    local S = FN.db.settings
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetAllPoints()
    holder:Hide()
    holder.area = opts.DockScroll(holder)
    local d = holder.area.content
    holder.content = d
    holder.open = {} -- characters opened in the list
    local focus -- the chosen column, or nil

    -- the range: one row of choices
    -- (each button is its word plus an even share of the room left, so "2 Weeks" isn't squeezed
    -- into the same width as "All")
    holder.ranges = {}
    local words = 0
    for i, R in ipairs(RANGES) do
        local b = St.ChoiceButton(d, function()
            S.timeRange = R.key
            focus = nil
            holder:Update()
        end)
        b.key = R.key
        b.text:SetText(R.label)
        b.tw = b.text:GetStringWidth() or 0
        words = words + b.tw
        holder.ranges[i] = b
    end
    local spare = math.max(0, (W - 3 * (#RANGES - 1) - words) / #RANGES)
    local x = PAD
    for _, b in ipairs(holder.ranges) do
        b:SetSize(b.tw + spare, opts.ctrlH)
        b:SetPoint("TOPLEFT", d, "TOPLEFT", x, opts.top)
        x = x + b.tw + spare + 3
    end

    -- the headline
    local what = St.Text(d, 10, C.SUBTEXT)
    local back = St.ChoiceButton(d, function()
        focus = nil
        holder:Update()
    end)
    back:SetSize(60, 18)
    back.tip = "Back to the whole range"
    local num = St.Text(d, 26, C.TEXT)
    local who = St.Text(d, 11, C.SUBTEXT)
    who:SetPoint("BOTTOMLEFT", num, "BOTTOMRIGHT", 6, 3)
    local cmp = St.Text(d, 10, C.INK2)
    cmp:SetWidth(W)

    -- three facts
    local fw = (W - 12) / 3
    holder.facts = {}
    for i = 1, 3 do
        local t = K.Tile(d, fw)
        t:SetHeight(40)
        t.sub:Hide()
        t.label:SetWordWrap(false)
        holder.facts[i] = t
    end

    -- AFK: left out unless switched on
    local afk = CreateFrame("Button", nil, d)
    afk:SetSize(W, 18)
    afk.toggle = St.Toggle(afk)
    afk.toggle:SetPoint("LEFT", afk, "LEFT", 0, 0)
    afk.toggle:SetScale(0.8)
    afk.text = St.Text(afk, 10, C.SUBTEXT)
    afk.text:SetPoint("LEFT", afk, "LEFT", 36, 0)
    afk.text:SetText("Count time spent AFK")
    afk:SetScript("OnClick", function()
        S.timeAfk = not S.timeAfk
        holder:Update()
    end)
    afk:SetScript("OnEnter", function(self)
        afk.toggle:SetOn(S.timeAfk, true)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Count time spent AFK", 1, 1, 1)
        GameTooltip:AddLine("Off: only time you were at the keys. On: every minute logged in, as /played counts it.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    afk:SetScript("OnLeave", function()
        afk.toggle:SetOn(S.timeAfk)
        GameTooltip:Hide()
    end)

    -- the chart: columns stacked by class
    local chart = Section(d, "Time played")
    holder.chart = chart -- (read by tools/check.py)
    local COL_H, YL = 80, 22 -- the chart's height, its hour labels' column
    chart.f = CreateFrame("Frame", nil, chart.card)
    chart.f:SetSize(CW, COL_H)
    chart.f:SetPoint("TOPLEFT", chart.card, "TOPLEFT", CP, -CP - 4)
    chart.yl, chart.ticks, chart.keys = {}, {}, {}
    for i = 1, 6 do
        local fs = St.Text(chart.f, 8, FAINT)
        fs:SetJustifyH("RIGHT")
        fs:SetWidth(YL - 4)
        chart.yl[i] = fs
    end
    for i = 1, 31 do
        local fs = St.Text(chart.card, 8, FAINT)
        fs:SetJustifyH("CENTER")
        chart.ticks[i] = fs
    end
    -- the class key: hovering a class picks it out in the columns (the rest fade back), as the
    -- mockup's legend does; only alphas change, nothing is redrawn
    -- (eased over 0.16 s, as the mockup's `transition: opacity .16s` with CSS's "ease")
    local FADE = 0.16
    local fading, fadeT = {}, 0
    local fader = CreateFrame("Frame", nil, chart.card)
    local function Ease(p) return 1 - (1 - p) ^ 3 end
    local function FadeStep(_, elapsed)
        fadeT = fadeT + (elapsed or FADE)
        local p = math.min(1, fadeT / FADE)
        local e = Ease(p)
        for _, it in ipairs(fading) do it.obj:SetAlpha(it.from + (it.to - it.from) * e) end
        if p >= 1 then
            fading = {}
            fader:SetScript("OnUpdate", nil)
        end
    end
    local function FadeTo(list)
        fading, fadeT = {}, 0
        for _, it in ipairs(list) do
            local from = it.obj.GetAlpha and it.obj:GetAlpha() or it.to
            fading[#fading + 1] = { obj = it.obj, from = tonumber(from) or it.to, to = it.to }
        end
        fader:SetScript("OnUpdate", FadeStep)
    end
    local function PickClass(class)
        local list = {}
        for _, s in ipairs(chart.segs or {}) do
            local on = not class or s.class == class
            list[#list + 1] = { obj = s.t, to = on and 1 or 0.15 }
        end
        for _, k in ipairs(chart.keys) do
            local on = not class or k.class == class
            list[#list + 1] = { obj = k.sq, to = on and 1 or 0.35 }
            list[#list + 1] = { obj = k.fs, to = on and 1 or 0.45 }
        end
        FadeTo(list)
    end
    -- (a redraw puts every piece back at full and stops any fade in flight)
    function chart:StopFade()
        fading = {}
        fader:SetScript("OnUpdate", nil)
    end
    for i = 1, 9 do
        local sq = chart.card:CreateTexture(nil, "ARTWORK")
        sq:SetTexture(SOLID)
        sq:SetSize(7, 7)
        local k = { sq = sq, fs = St.Text(chart.card, 9, C.INK2) }
        k.btn = CreateFrame("Button", nil, chart.card)
        k.btn:SetPoint("TOPLEFT", sq, "TOPLEFT", -3, 4)
        k.btn:SetSize(CW / 3 - 4, 14)
        k.btn:SetScript("OnEnter", function(self)
            PickClass(k.class)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            local c = ClassColor(k.class)
            GameTooltip:SetText(ClassName(k.class), c[1], c[2], c[3])
            if k.secs then GameTooltip:AddLine(Fmt(k.secs) .. " played, " .. k.pct .. "% of the range", 0.8, 0.8, 0.8) end
            GameTooltip:Show()
        end)
        k.btn:SetScript("OnLeave", function()
            PickClass(nil)
            GameTooltip:Hide()
        end)
        chart.keys[i] = k
    end
    Hoverable(chart.f)
    chart.f:SetScript("OnMouseUp", function(self)
        local x, y = K.Cursor(self)
        local i = x and self:Pick(x, y)
        if not i then return end
        focus = (focus ~= i) and i or nil
        GameTooltip:Hide()
        holder:Update()
    end)

    -- When you play: day by hour
    local grid = Section(d, "When you play")
    grid.aside:SetText("day by hour")
    local GL = 22
    local cell = math.floor((CW - GL) / 24 * 10) / 10
    grid.f = CreateFrame("Frame", nil, grid.card)
    grid.f:SetSize(GL + cell * 24, cell * 7)
    grid.f:SetPoint("TOPLEFT", grid.card, "TOPLEFT", CP, -CP)
    for i, name in ipairs(K.DOW) do
        local fs = St.Text(grid.f, 8, FAINT)
        fs:SetPoint("LEFT", grid.f, "TOPLEFT", 0, -(i - 0.5) * cell)
        fs:SetText(name)
    end
    for i, h in ipairs({ 0, 6, 12, 18 }) do
        local fs = St.Text(grid.card, 8, FAINT)
        fs:SetPoint("TOPLEFT", grid.f, "BOTTOMLEFT", GL + h * cell, -3)
        fs:SetText(({ "12a", "6a", "12p", "6p" })[i])
    end
    grid.busy = St.Text(grid.card, 9, C.SUBTEXT)
    grid.busy:SetPoint("TOPLEFT", grid.f, "BOTTOMLEFT", 0, -17)
    grid.busy:SetWidth(CW)
    Hoverable(grid.f)

    -- Gathered: a small total per profession, coin last
    local got = Section(d, "Gathered")
    got.cells = {}
    for i = 1, 8 do
        local b = CreateFrame("Button", nil, got.card)
        b:SetSize(CW / 3, 16)
        b.dot = b:CreateTexture(nil, "ARTWORK")
        b.dot:SetTexture(CIRCLE)
        b.dot:SetSize(7, 7)
        b.dot:SetPoint("LEFT", b, "LEFT", 1, 0)
        b.text = St.Text(b, 10, C.TEXT)
        b.text:SetPoint("LEFT", b, "LEFT", 12, 0)
        b.text:SetWidth(CW / 3 - 14)
        b.text:SetWordWrap(false)
        b:SetScript("OnEnter", function(self) if self.tip then self.tip(self) end end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        got.cells[i] = b
    end
    got.empty = St.Text(got.card, 10, C.SUBTEXT)
    got.empty:SetPoint("TOPLEFT", got.card, "TOPLEFT", CP + 2, -CP - 2)
    got.empty:SetText("Nothing gathered")

    -- Characters: a card per class, as in the mockup (Playtime-v4.html .group): the class, its
    -- time, then a row per character: name and level, gold looted, time, an arrow; a bar of their
    -- time against the busiest character's along the row's foot
    local list = { cards = {} }
    list.label = St.Text(d, 9, C.SUBTEXT)
    list.label:SetText("CHARACTERS")
    list.aside = St.Text(d, 9, FAINT)
    list.aside:SetJustifyH("RIGHT")
    list.aside:SetText("gold looted  ·  time")
    local GW = W - 12          -- inside a class card (6 a side)
    local TIME_R = 4 + 7 + 10  -- the time's right edge, left of the arrow
    local GOLD_R = TIME_R + 58 + 10
    local function Card(i)
        local g = list.cards[i]
        if g then return g end
        g = St.Frame("Frame", d)
        St.Etch(g, STYLE.card or STYLE.row, 4)
        g:SetWidth(W)
        g.head = CreateFrame("Button", nil, g)
        g.head:SetSize(GW, 24)
        g.head:SetPoint("TOPLEFT", g, "TOPLEFT", 6, -4)
        g.sq = g.head:CreateTexture(nil, "ARTWORK")
        g.sq:SetTexture(SOLID)
        g.sq:SetSize(9, 9)
        g.sq:SetPoint("LEFT", g.head, "LEFT", 4, 0)
        g.name = St.Text(g.head, 10, C.TEXT)
        g.name:SetPoint("LEFT", g.head, "LEFT", 19, 0)
        g.time = St.Text(g.head, 11, C.TEXT)
        g.time:SetPoint("RIGHT", g.head, "RIGHT", -4, 0)
        g.rule = g.head:CreateTexture(nil, "ARTWORK")
        g.rule:SetTexture(SOLID)
        g.rule:SetVertexColor(EMPTY[1], EMPTY[2], EMPTY[3])
        g.rule:SetHeight(1)
        g.rule:SetPoint("BOTTOMLEFT", g.head, "BOTTOMLEFT", 0, 0)
        g.rule:SetPoint("BOTTOMRIGHT", g.head, "BOTTOMRIGHT", 0, 0)
        g.chev = g.head:CreateTexture(nil, "ARTWORK")
        g.chev:SetTexture(St.Icon("play-white"))
        g.chev:SetSize(7, 7)
        g.chev:SetPoint("RIGHT", g.head, "RIGHT", -4, 0)
        g.chev:SetVertexColor(FAINT[1], FAINT[2], FAINT[3])
        g.head:SetScript("OnClick", function(self)
            if self.toggle then
                holder.open.others = not holder.open.others or nil
                holder:Update()
            end
        end)
        g.rows = {}
        list.cards[i] = g
        return g
    end
    local function Row(g, i)
        local r = g.rows[i]
        if r then return r end
        r = CreateFrame("Button", nil, g)
        r:SetSize(GW, 24)
        r.hl = r:CreateTexture(nil, "BACKGROUND")
        r.hl:SetTexture(SOLID)
        r.hl:SetVertexColor(1, 0.96, 0.86, 0.06)
        r.hl:SetPoint("TOPLEFT")
        r.hl:SetPoint("TOPRIGHT")
        r.hl:SetHeight(24)
        r.hl:Hide()
        r.name = St.Text(r, 10, C.TEXT)
        r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -6)
        r.level = St.Text(r, 9, C.SUBTEXT)
        r.level:SetPoint("LEFT", r.name, "RIGHT", 4, 0)
        r.time = St.Text(r, 10, C.TEXT)
        r.time:SetPoint("TOPRIGHT", r, "TOPRIGHT", -TIME_R, -6)
        r.time:SetJustifyH("RIGHT")
        r.gold = St.Text(r, 9, C.INK2)
        r.gold:SetPoint("TOPRIGHT", r, "TOPRIGHT", -GOLD_R, -7)
        r.gold:SetJustifyH("RIGHT")
        r.chev = r:CreateTexture(nil, "ARTWORK")
        r.chev:SetTexture(St.Icon("play-white"))
        r.chev:SetSize(7, 7)
        r.chev:SetPoint("TOPRIGHT", r, "TOPRIGHT", -4, -8)
        r.chev:SetVertexColor(FAINT[1], FAINT[2], FAINT[3])
        r.bar = r:CreateTexture(nil, "ARTWORK")
        r.bar:SetTexture(SOLID)
        r.bar:SetHeight(2)
        r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -21)
        r.detail = St.Text(r, 9, C.SUBTEXT)
        r.detail:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -28)
        r.detail:SetWidth(GW - 8)
        r.detail:SetJustifyH("LEFT")
        r.detail:SetSpacing(3)
        r:SetScript("OnEnter", function(self) self.hl:Show() end)
        r:SetScript("OnLeave", function(self) self.hl:Hide() end)
        r:SetScript("OnClick", function(self)
            holder.open[self.char] = not holder.open[self.char] or nil
            holder:Update()
        end)
        g.rows[i] = r
        return r
    end

    local note = St.Text(d, 9, FAINT)
    note:SetWidth(W)
    note:SetJustifyH("LEFT")
    note:SetSpacing(2)

    -- ---------------------------------------------------------------- drawing
    function holder:Update()
        local range = RANGE[S.timeRange] and S.timeRange or "14"
        S.timeRange = range
        local withAfk = S.timeAfk == true
        for _, b in ipairs(self.ranges) do b:SetChosen(b.key == range) end
        local data = TP.Collect(range, focus, withAfk)
        self.data = data -- (read by tools/check.py)
        focus = data.focus
        local cols, R = data.cols, RANGE[range]
        local sel = focus and cols[focus]
        local oneDay = sel and R.days ~= nil
        local total = data.secs + data.pre
        local y = opts.top - opts.ctrlH - 12

        -- the headline
        back:SetShown(sel ~= nil)
        what:ClearAllPoints()
        if sel then
            back.text:SetText("< " .. R.label)
            back:ClearAllPoints()
            back:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, y + 2)
            what:SetPoint("LEFT", back, "RIGHT", 6, 0)
            what:SetText(sel.name)
        else
            what:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, y)
            what:SetText("Played " .. R.word)
        end
        y = y - 20
        num:ClearAllPoints()
        num:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, y)
        local n = 0
        for c, v in pairs(data.perChar) do if v.secs > 0 and data.roster[c] then n = n + 1 end end
        if total > 0 then
            num:SetText(Fmt(total))
            num:SetTextColor(C.TEXT[1], C.TEXT[2], C.TEXT[3])
            who:SetText(n .. (n == 1 and " character" or " characters"))
        else
            num:SetText("Not played")
            num:SetTextColor(C.SUBTEXT[1], C.SUBTEXT[2], C.SUBTEXT[3])
            who:SetText("")
        end
        y = y - 32
        local line = ""
        if not sel and R.prev and data.prev > 0 then
            local diff = data.secs - data.prev
            line = (diff >= 0 and UP or DOWN) .. Fmt(math.abs(diff)) .. (diff >= 0 and " more" or " less") .. "|r than " .. R.prev
        elseif not sel and range == "all" and data.pre > 0 then
            line = "Includes /played from before Fieldnotes kept time"
        end
        cmp:SetText(line)
        cmp:ClearAllPoints()
        cmp:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, y)
        if line ~= "" then y = y - 16 end
        y = y - 6

        -- three facts
        local facts
        if oneDay then
            facts = {
                { tostring(data.sessions), data.sessions == 1 and "session" or "sessions" },
                { data.longest > 0 and Fmt(data.longest) or "-", "longest" },
                { data.firstHour and K.HourText(data.firstHour) or "-", "first log in" },
            }
        else
            facts = {
                { data.nDays .. "|cff999999 of " .. K.Commas(data.span) .. "|r", "days played" },
                { data.nDays > 0 and Fmt(data.secs / data.nDays) or "-", "per day" },
                { data.longest > 0 and Fmt(data.longest) or "-", "longest" },
            }
        end
        local tips = {
            "Days with any time played, of the days in this range (from the day Fieldnotes started keeping time).",
            "Time played on an average day you logged in (days with no play left out).",
            "Your longest session: one log in, start to log out. A /reload carries it on.",
        }
        if oneDay then tips = { "Each log in that day.", "The longest log in that day.", "When you first logged in that day." } end
        -- each tile is as wide as its words, plus an even share of the room left over
        -- (measured unbounded: a capped, no-wrap string reports its clipped width, which kept the
        -- tiles at their old size)
        local function Wide(fs)
            fs:SetWidth(0)
            return (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0
        end
        local needs, room = {}, 0
        for i, t in ipairs(self.facts) do
            if t.label.GetFont then -- (back to full size, in case the last draw made it smaller)
                local font, size, flags = t.label:GetFont()
                t.labelSize = t.labelSize or size
                if font and t.labelSize then t.label:SetFont(font, t.labelSize, flags) end
            end
            t.value:SetText(facts[i][1])
            t.label:SetText(facts[i][2])
            needs[i] = math.max(Wide(t.value), Wide(t.label)) + 20
            room = room + needs[i]
        end
        -- too wide even so (a narrow dock): the labels go a size smaller rather than lose letters
        if room > W - 12 then
            room = 0
            for i, t in ipairs(self.facts) do
                local font, size, flags
                if t.label.GetFont then font, size, flags = t.label:GetFont() end
                if font and size then t.label:SetFont(font, size - 1, flags) end
                needs[i] = math.max(Wide(t.value), Wide(t.label)) + 20
                room = room + needs[i]
            end
        end
        local spare = (W - 12 - room) / 3
        local fx = PAD
        for i, t in ipairs(self.facts) do
            local tw = math.max(20, needs[i] + spare)
            t:SetWidth(tw)
            t.value:SetWidth(tw - 14)
            t.label:SetWidth(tw - 14)
            local tipText = tips[i]
            t.tip = function(o) Tip(o, facts[i][2]:gsub("^%l", string.upper), nil, nil, tipText) end
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", d, "TOPLEFT", fx, y)
            fx = fx + tw + 6
        end
        y = y - 40 - 8
        afk:ClearAllPoints()
        afk:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, y)
        afk.toggle:SetOn(withAfk)
        y = y - 18 - 12

        -- the chart
        do
            local f = chart.f
            Begin(f)
            local maxS = 3600
            for _, col in ipairs(cols) do maxS = math.max(maxS, col.secs or 0) end
            local step
            for _, s in ipairs({ 0.5, 1, 2, 3, 5, 10, 20, 25, 50, 100, 200, 500, 1000 }) do
                if maxS / 3600 / s <= 4 then step = s break end
            end
            step = step or 2000
            local top = math.ceil(maxS / 3600 / step) * step
            local PW = CW - YL
            for i, fs in ipairs(chart.yl) do
                local v = (i - 1) * step
                local show = v <= top + 1e-9
                fs:SetShown(show)
                if show then
                    local yy = COL_H - v / top * COL_H
                    Rect(f, YL, yy, PW, 1, EMPTY, 1)
                    fs:ClearAllPoints()
                    fs:SetPoint("RIGHT", f, "TOPLEFT", YL - 4, -yy)
                    fs:SetText(v == 0 and "0" or (v .. "h"))
                end
            end
            local nc = #cols
            local bw = PW / nc
            local cw = math.min(bw - 2, 18)
            local order = {}
            for class in pairs(data.byClass) do order[#order + 1] = class end
            for _, col in ipairs(cols) do for class in pairs(col.byClass or {}) do
                if not data.byClass[class] then order[#order + 1] = class; data.byClass[class] = 0 end
            end end
            table.sort(order, function(a, b)
                if data.byClass[a] ~= data.byClass[b] then return data.byClass[a] > data.byClass[b] end
                return a < b
            end)
            chart:StopFade()
            chart.segs = {}
            for i, col in ipairs(cols) do
                local x0 = YL + (i - 1) * bw + (bw - cw) / 2
                local base = COL_H
                local dim = focus and focus ~= i
                for _, class in ipairs(order) do
                    local v = col.byClass and col.byClass[class] or 0
                    if v > 0 then
                        local h = v / 3600 / top * COL_H
                        local t = Rect(f, x0, base - h, cw, h, ClassColor(class), dim and 0.3 or 1)
                        t:SetAlpha(1)
                        chart.segs[#chart.segs + 1] = { t = t, class = class }
                        base = base - h
                    end
                end
                if focus == i then Rect(f, x0, COL_H + 3, cw, 2, C.ACCENT, 1) end
                local tk = chart.ticks[i]
                tk:ClearAllPoints()
                tk:SetPoint("TOP", f, "BOTTOMLEFT", YL + (i - 0.5) * bw, -6)
                tk:SetText(col.tick)
                tk:Show()
            end
            for i = nc + 1, #chart.ticks do chart.ticks[i]:Hide() end
            f.hl = rawget(f, "hl") or f:CreateTexture(nil, "OVERLAY")
            f.hl:SetTexture(SOLID)
            f.hl:SetVertexColor(1, 1, 1, 0.10)
            f.hl:Hide()
            Finish(f)
            function f:Pick(x, yy)
                if x < YL or x > CW or yy < 0 or yy > COL_H + 6 then return end
                return math.max(1, math.min(nc, math.floor((x - YL) / bw) + 1))
            end
            function f:Hot(i)
                if not i then
                    self.hl:Hide()
                    GameTooltip:Hide()
                    return
                end
                local col = cols[i]
                self.hl:ClearAllPoints()
                self.hl:SetPoint("TOPLEFT", self, "TOPLEFT", YL + (i - 1) * bw, 0)
                self.hl:SetSize(bw, COL_H)
                self.hl:Show()
                local rows = {}
                if (col.secs or 0) > 0 then
                    rows[1] = { "Played", Fmt(col.secs) }
                    for _, class in ipairs(order) do
                        local v = col.byClass and col.byClass[class]
                        if v and v > 0 then rows[#rows + 1] = { Hex(ClassColor(class)) .. ClassName(class) .. "|r", Fmt(v) } end
                    end
                end
                Tip(self, col.name, nil, rows, (col.secs or 0) > 0 and (focus == i and "Click to go back" or "Click to look at just this")
                    or "Not played")
            end
            -- the class key: share of the range
            local kx, ky, kw = CP, -CP - 4 - COL_H - 22, CW / 3
            local shown = 0
            for _, class in ipairs(order) do
                if data.byClass[class] > 0 and shown < #chart.keys then
                    shown = shown + 1
                    local k = chart.keys[shown]
                    local col, row = (shown - 1) % 3, math.floor((shown - 1) / 3)
                    local c = ClassColor(class)
                    k.sq:ClearAllPoints()
                    k.sq:SetPoint("TOPLEFT", chart.card, "TOPLEFT", kx + col * kw, ky - row * 14 - 3)
                    k.sq:SetVertexColor(c[1], c[2], c[3])
                    k.fs:ClearAllPoints()
                    k.fs:SetPoint("TOPLEFT", chart.card, "TOPLEFT", kx + col * kw + 11, ky - row * 14)
                    k.class, k.secs = class, data.byClass[class]
                    k.pct = math.floor(data.byClass[class] / math.max(1, total) * 100 + 0.5)
                    k.fs:SetText(ClassName(class) .. "  |cff6d665a" .. k.pct .. "%|r")
                    k.sq:SetAlpha(1)
                    k.fs:SetAlpha(1)
                    k.sq:Show()
                    k.fs:Show()
                    k.btn:Show()
                end
            end
            for i = shown + 1, #chart.keys do
                chart.keys[i].sq:Hide()
                chart.keys[i].fs:Hide()
                chart.keys[i].btn:Hide()
                chart.keys[i].class = nil
            end
            local keyH = shown > 0 and (math.ceil(shown / 3) * 14 + 4) or 0
            chart.aside:SetText(R.days and "a column a day" or (range == "year" and "a column a month" or "a column a year"))
            y = chart:Place(PAD, y, W, CP + 4 + COL_H + 20 + keyH + CP - 2)
        end

        -- When you play
        do
            local f = grid.f
            Begin(f)
            local heat, max = data.heat, 0
            for dw = 1, 7 do for h = 0, 23 do max = math.max(max, heat[dw][h]) end end
            for dw = 1, 7 do
                for h = 0, 23 do
                    local v = heat[dw][h]
                    if v > 0 then
                        Rect(f, GL + h * cell, (dw - 1) * cell, cell - 1.5, cell - 1.5, C.ACCENT, 0.15 + 0.85 * (v / max) ^ 0.7)
                    else
                        Rect(f, GL + h * cell, (dw - 1) * cell, cell - 1.5, cell - 1.5, EMPTY, 1)
                    end
                end
            end
            f.hl = rawget(f, "hl") or f:CreateTexture(nil, "OVERLAY")
            f.hl:SetTexture(SOLID)
            f.hl:SetVertexColor(1, 1, 1, 0.35)
            f.hl:Hide()
            Finish(f)
            function f:Pick(x, yy)
                if x < GL or yy < 0 then return end
                local h, dw = math.floor((x - GL) / cell), math.floor(yy / cell) + 1
                if h > 23 or dw > 7 then return end
                return dw * 100 + h
            end
            function f:Hot(k)
                if not k then
                    self.hl:Hide()
                    GameTooltip:Hide()
                    return
                end
                local dw, h = math.floor(k / 100), k % 100
                self.hl:ClearAllPoints()
                self.hl:SetPoint("TOPLEFT", self, "TOPLEFT", GL + h * cell, -(dw - 1) * cell)
                self.hl:SetSize(cell - 1.5, cell - 1.5)
                self.hl:Show()
                local v = heat[dw][h]
                Tip(self, (oneDay and DOW_ONE[dw] or K.DOW_LONG[dw]) .. ", " .. K.HourText(h), nil,
                    v > 0 and { { "Played", Fmt(v) } } or nil,
                    v <= 0 and "Not played" or ((v == max and not oneDay) and "Your busiest hour" or nil))
            end
            -- the busiest day and hour, or a chosen day's hours
            local text = ""
            if max > 0 then
                local rowSum, colSum = {}, {}
                for dw = 1, 7 do
                    rowSum[dw] = 0
                    for h = 0, 23 do
                        rowSum[dw] = rowSum[dw] + heat[dw][h]
                        colSum[h] = (colSum[h] or 0) + heat[dw][h]
                    end
                end
                local bd, bh = 1, 0
                for dw = 2, 7 do if rowSum[dw] > rowSum[bd] then bd = dw end end
                for h = 1, 23 do if colSum[h] > colSum[bh] then bh = h end end
                if oneDay then
                    local a, b
                    for h = 0, 23 do if heat[bd][h] > 0 then a = a or h; b = h end end
                    text = "Played from |cffbdbdbd" .. K.HourText(a) .. "|r to |cffbdbdbd" .. K.HourText((b + 1) % 24) .. "|r"
                else
                    text = "Most often on |cffbdbdbd" .. K.DOW_LONG[bd] .. "|r, around |cffbdbdbd" .. K.HourText(bh) .. "|r"
                end
            end
            grid.busy:SetText(text)
            y = grid:Place(PAD, y, W, CP + cell * 7 + 14 + (text ~= "" and 16 or 0) + CP - 2)
        end

        -- Gathered
        do
            local hours = data.secs / 3600 -- (tracked time only: /played from before has no gathers to match)
            local entries = {}
            for _, p in ipairs(M.PROFS) do
                if not p.money and (data.got[p.key] or 0) > 0 then
                    local v = data.got[p.key]
                    entries[#entries + 1] = { color = p.color, text = K.Commas(v) .. " |cff999999" .. p.units .. "|r",
                        tip = function(o) Tip(o, p.label, p.color, { { "In all", K.Commas(v) .. " " .. p.units },
                            { "An hour played", hours > 0.05 and string.format("%.1f", v / hours) or "-" } }) end }
                end
            end
            if data.copper > 0 then
                entries[#entries + 1] = { color = C.MONEY, text = FN.ShortMoney(data.copper) .. " |cff999999looted|r",
                    tip = function(o) Tip(o, "Coin looted", C.MONEY, { { "In all", FN.FormatMoney(data.copper, true) },
                        { "An hour played", hours > 0.05 and FN.FormatMoney(math.floor(data.copper / hours), true) or "-" } }) end }
            end
            for i, b in ipairs(got.cells) do
                local e = entries[i]
                b:SetShown(e ~= nil)
                if e then
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", got.card, "TOPLEFT", CP + ((i - 1) % 3) * (CW / 3), -CP - math.floor((i - 1) / 3) * 18)
                    b.dot:SetVertexColor(e.color[1], e.color[2], e.color[3])
                    b.text:SetText(e.text)
                    b.tip = e.tip
                end
            end
            got.empty:SetShown(#entries == 0)
            got.aside:SetText(sel and sel.name or "")
            y = got:Place(PAD, y, W, CP * 2 + math.max(1, math.ceil(#entries / 3)) * 18 - 4)
        end

        -- Characters, a card per class
        do
            local groups, byClass = {}, {}
            local names = FN.db.chars
            -- characters who gathered in the range but haven't logged in since Fieldnotes kept time
            -- (their class isn't known yet) share one card at the end, closed unless asked
            local OTHER = "~"
            local who = {}
            for c, r in pairs(data.roster) do if r.class then who[c] = r end end
            for c, v in pairs(data.perChar) do
                if not who[c] and (v.copper > 0 or next(v.got) or v.secs > 0) then who[c] = data.roster[c] or {} end
            end
            local maxC = 1
            for c, r in pairs(who) do
                local class = r.class or OTHER
                local g = byClass[class]
                if not g then
                    g = { class = class, secs = 0, copper = 0, list = {} }
                    byClass[class] = g
                    groups[#groups + 1] = g
                end
                local v = data.perChar[c] or { secs = 0, copper = 0, got = {} }
                local secs = Minutes(v.secs)
                g.list[#g.list + 1] = { c = c, r = r, v = v, secs = secs, name = (names[c] or "?"):match("^[^-]+") or "?" }
                g.secs = g.secs + secs
                g.copper = g.copper + v.copper
                maxC = math.max(maxC, secs)
            end
            for _, g in ipairs(groups) do
                table.sort(g.list, function(a, b)
                    if a.secs ~= b.secs then return a.secs > b.secs end
                    if a.v.copper ~= b.v.copper then return a.v.copper > b.v.copper end
                    return a.name < b.name
                end)
            end
            table.sort(groups, function(a, b)
                if (a.class == OTHER) ~= (b.class == OTHER) then return b.class == OTHER end
                if a.secs ~= b.secs then return a.secs > b.secs end
                return a.class < b.class
            end)

            list.label:SetShown(#groups > 0)
            list.aside:SetShown(#groups > 0)
            list.label:ClearAllPoints()
            list.label:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, y)
            list.aside:ClearAllPoints()
            list.aside:SetPoint("TOPRIGHT", d, "TOPLEFT", PAD + W, y)
            local gy = y - 15
            for gi, g in ipairs(groups) do
                local card = Card(gi)
                local other = g.class == OTHER
                local c = other and FAINT or ClassColor(g.class)
                local shut = other and not holder.open.others
                card.sq:SetVertexColor(c[1], c[2], c[3])
                card.head.toggle = other
                card.chev:SetShown(other)
                card.chev:SetRotation(shut and 0 or -math.pi / 2)
                card.rule:SetShown(not shut)
                if other then
                    local n = #g.list
                    card.name:SetText(n .. (n == 1 and " character" or " characters") .. " to log in on")
                    card.name:SetTextColor(C.SUBTEXT[1], C.SUBTEXT[2], C.SUBTEXT[3])
                    card.time:SetText("")
                    card.head.tip = nil
                    card.head:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                        GameTooltip:SetText("Not logged in since this update", 1, 1, 1)
                        GameTooltip:AddLine("They gathered in this range, but Fieldnotes learns a character's class, level and time only while you play them. Log in on each once to sort them by class.", 0.8, 0.8, 0.8, true)
                        GameTooltip:Show()
                    end)
                    card.head:SetScript("OnLeave", function() GameTooltip:Hide() end)
                else
                    card.name:SetText(ClassName(g.class))
                    card.name:SetTextColor(c[1], c[2], c[3])
                    card.time:SetText(g.secs > 0 and Fmt(g.secs) or "-")
                    card.head:SetScript("OnEnter", nil)
                    card.head:SetScript("OnLeave", nil)
                end
                local yy = 4 + 24
                local nr = 0
                if not shut then
                    for _, e in ipairs(g.list) do
                        nr = nr + 1
                        local r = Row(card, nr)
                        r.char = e.c
                        local idle = e.secs <= 0
                        local ink = idle and FAINT or C.TEXT
                        r.name:SetText(e.name)
                        r.name:SetTextColor(ink[1], ink[2], ink[3])
                        r.level:SetText(e.r.level and tostring(e.r.level) or "")
                        local looted = e.v.copper > 0
                        r.gold:SetText(looted and Coins(e.v.copper) or "-")
                        local gi2 = looted and C.INK2 or FAINT
                        r.gold:SetTextColor(gi2[1], gi2[2], gi2[3])
                        r.time:SetText(idle and "-" or Fmt(e.secs))
                        r.time:SetTextColor(ink[1], ink[2], ink[3])
                        r.bar:SetVertexColor(c[1], c[2], c[3], 0.5)
                        r.bar:SetWidth(math.max(6, (GW - 8) * e.secs / maxC)) -- (a few minutes still reads as a bar, not a speck)
                        r.bar:SetShown(not idle)
                        local open = holder.open[e.c] == true
                        r.chev:SetRotation(open and -math.pi / 2 or 0)
                        local rh = 24
                        if open then
                            local parts = {}
                            for _, p in ipairs(M.PROFS) do
                                local v = e.v.got[p.key]
                                if v and v > 0 then parts[#parts + 1] = K.Commas(v) .. " " .. p.units end
                            end
                            local lines = { #parts > 0 and table.concat(parts, "  ·  ") or "Nothing gathered" }
                            if e.r.class then
                                local played = (e.r.pre or 0) + (data.all[e.c] or 0)
                                lines[2] = "Carrying " .. (e.r.copper and FN.FormatMoney(e.r.copper) or "-") .. "  ·  "
                                    .. Fmt(played) .. " played in all"
                            end
                            r.detail:SetText(table.concat(lines, "\n"))
                            r.detail:Show()
                            rh = 24 + 6 + (r.detail:GetStringHeight() or 26)
                        else
                            r.detail:Hide()
                        end
                        r:SetHeight(rh)
                        r:ClearAllPoints()
                        r:SetPoint("TOPLEFT", card, "TOPLEFT", 6, -yy)
                        r:Show()
                        yy = yy + rh
                    end
                end
                for i = nr + 1, #card.rows do card.rows[i]:Hide() end
                local ch = yy + 4
                card:SetHeight(ch)
                card:ClearAllPoints()
                card:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, gy)
                card:Show()
                gy = gy - ch - 6
            end
            for i = #groups + 1, #list.cards do list.cards[i]:Hide() end
            if #groups > 0 then y = gy - 6 end
        end

        note:SetText(withAfk
            and "Time counts every minute you're logged in, AFK included, starting with this version. All adds each character's /played from before."
            or "Time counts only while you're logged in and not AFK, starting with this version. All adds each character's /played from before.")
        note:ClearAllPoints()
        note:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, y + 2)
        y = y - (note:GetStringHeight() or 24)
        holder.area:SetHeight(-y + 24)
    end
    return holder
end
