local ADDON, FN = ...

-- The Stats page (stats v5, approved by Karl 2026-11-05: design/stats-v5-2026-11-05). It lives in
-- the dock, opened by the Stats tab, in place of the old stats window: one page that scrolls,
-- phone style. Show and When at the top, chips for All or one profession, four headline numbers,
-- then a chart per question:
--   Last 30 days      a column a day, stacked by profession
--   Profession mix    a donut (one profession: "What it gave", its top items)
--   When you gather   day by hour, darker where you gather most
--   Top loot          bars with the item's own icon
--   Best zones        gathers per hour of active time (sessions found in the records)
--   Skill climb       a line per skilled profession, with the rank caps
--   and a card of the chosen profession's own (ruined and creatures, drop rate, best chests...)
-- Every bar, slice, square and point answers on hover with GameTooltip. Drawn with pooled textures
-- and lines, only when the page opens or its choices or the data change.
--
-- Rates come from sessions found in the records: one character's gathers less than five minutes
-- apart are one session, its time counted per zone, and its last gather counted as TAIL seconds.

local St = FN.Style
local C, STYLE = St.C, St.STYLE
local SP = {}
FN.StatsPage = SP

local SOLID = St.SOLID
local GAP, TAIL = 300, 20
local DAYS = 30
local RUINED = 2934
local CP = 8 -- a card's inner edge
local ROW_H = 24 -- a bar row
local FAINT = { 0.46, 0.43, 0.38 }
local EMPTY = { 0.16, 0.15, 0.13 } -- an empty grid square, a bar's track
local CAPS = { 75, 150, 225, 300 }
local DOW = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
local DOW_LONG = { "Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays", "Sundays" }
local Date = date or (os and os.date)

local function Commas(n)
    local s = tostring(math.floor(n + 0.5))
    while true do
        local k
        s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        if k == 0 then return s end
    end
end

local function ZoneName(mapID)
    local i = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return (i and i.name) or "Unknown zone"
end

local function ItemName(id)
    if id == RUINED then return "Ruined Leather Scraps" end
    return (FN.ItemInfo(id)) or "..."
end

local function HourText(h)
    if h == 0 then return "12 am" end
    if h < 12 then return h .. " am" end
    if h == 12 then return "12 pm" end
    return (h - 12) .. " pm"
end

local function Cap(word) return (word:gsub("^%l", string.upper)) end

-- ------------------------------------------------------------
-- Drawing helpers
-- ------------------------------------------------------------

-- the tooltip every chart uses: a title in its color, gold keys and white values, a grey note
local function Tip(owner, title, color, rows, note)
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
    local c = color or C.TITLE
    GameTooltip:SetText(title, c[1], c[2], c[3])
    for _, r in ipairs(rows or {}) do GameTooltip:AddDoubleLine(r[1], r[2], 1, 0.82, 0, 1, 1, 1) end
    if note then GameTooltip:AddLine(note, 0.6, 0.6, 0.6, true) end
    GameTooltip:Show()
end

-- textures and lines, reused from one draw to the next
local function Begin(f)
    f.pool = rawget(f, "pool") or {}
    f.lines = rawget(f, "lines") or {}
    f.usedT, f.usedL = 0, 0
end
local function Tex(f, layer)
    f.usedT = f.usedT + 1
    local t = f.pool[f.usedT]
    if not t then
        t = f:CreateTexture(nil, layer or "ARTWORK")
        t:SetTexture(SOLID)
        f.pool[f.usedT] = t
    end
    t:ClearAllPoints()
    t:Show()
    return t
end
local function Rect(f, x, y, w, h, c, a)
    local t = Tex(f)
    t:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
    t:SetSize(math.max(0.5, w), math.max(0.5, h))
    t:SetVertexColor(c[1], c[2], c[3], a or 1)
    return t
end
-- a straight line, (x, y) from the frame's top left, y down; nil where the client has no lines
local function Line(f, x1, y1, x2, y2, thick, c, a)
    if not f.CreateLine then return end
    f.usedL = f.usedL + 1
    local l = f.lines[f.usedL]
    if not l then
        l = f:CreateLine(nil, "ARTWORK")
        if not l then return end
        l:SetTexture(SOLID)
        f.lines[f.usedL] = l
    end
    l:SetStartPoint("TOPLEFT", f, x1, -y1)
    l:SetEndPoint("TOPLEFT", f, x2, -y2)
    l:SetThickness(thick)
    l:SetVertexColor(c[1], c[2], c[3], a or 1)
    l:Show()
    return l
end
local function Finish(f)
    for i = f.usedT + 1, #f.pool do f.pool[i]:Hide() end
    for i = f.usedL + 1, #f.lines do f.lines[i]:Hide() end
end

-- where the cursor is over a frame, from its top left (y down)
local function Cursor(f)
    if not GetCursorPosition then return end
    local x, y = GetCursorPosition()
    local s = f:GetEffectiveScale() or 1
    local l, t = f:GetLeft(), f:GetTop()
    if not (x and l and t) then return end
    return x / s - l, t - y / s
end

-- a chart that answers on hover: f:Pick(x, y) names what is under the cursor, f:Hot(key) shows
-- it (key nil: nothing). Checked every frame only while the cursor is over the chart.
local function Hoverable(f)
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        self:SetScript("OnUpdate", function(me)
            local x, y = Cursor(me)
            local k = x and me:Pick(x, y) or nil
            if k ~= me.hot then
                me.hot = k
                me:Hot(k)
            end
        end)
    end)
    f:SetScript("OnLeave", function(self)
        self:SetScript("OnUpdate", nil)
        self.hot = nil
        self:Hot(nil)
    end)
end

-- ------------------------------------------------------------
-- The numbers
-- ------------------------------------------------------------
local function Collect(pick, show, days)
    local M = FN.Map
    local view, me = FN.View(), FN.ViewChar()
    local now = time()
    local since = (days and days > 0) and (now - days * 86400) or nil
    local d = { recs = {}, cloth = {}, now = now, since = since, byProf = {}, items = {}, itemProf = {},
        zone = {}, zoneSecs = {}, days = {}, perDay = {}, grid = {}, skill = {}, nodes = {}, npcs = {},
        ruined = 0 }
    for i = 0, DAYS - 1 do d.perDay[i] = {} end
    for dw = 1, 7 do
        d.grid[dw] = {}
        for h = 0, 23 do d.grid[dw][h] = 0 end
    end
    if show == "community" then show = "account" end
    for _, p in ipairs(M.PROFS) do
        if pick == "all" or pick == p.key then
            for mapID, list in pairs(view.events[p.key] or {}) do
                for _, str in ipairs(list) do
                    local r = FN.Decode(str)
                    if r and (show ~= "me" or r.char == me) and (not since or r.time >= since) then
                        r.prof, r.map = p.key, mapID
                        -- Cloth: every humanoid loot counts toward its drop rate; drops are the ones with cloth
                        if p.key == "cloth" then
                            local c = d.cloth[r.npc] or { loots = 0, drops = 0 }
                            d.cloth[r.npc] = c
                            c.loots = c.loots + 1
                            if next(r.items) then c.drops = c.drops + 1 end
                        end
                        if p.key ~= "cloth" or next(r.items) then d.recs[#d.recs + 1] = r end
                    end
                end
            end
        end
    end

    -- per record: profession, item, zone, day, hour, skill, source
    for _, r in ipairs(d.recs) do
        d.byProf[r.prof] = (d.byProf[r.prof] or 0) + 1
        d.zone[r.map] = (d.zone[r.map] or 0) + 1
        for id, n in pairs(r.items) do
            d.items[id] = (d.items[id] or 0) + n
            d.itemProf[id] = d.itemProf[id] or r.prof
        end
        if r.items[RUINED] then d.ruined = d.ruined + 1 end
        if r.npc and r.npc > 0 then d.npcs[r.npc] = (d.npcs[r.npc] or 0) + 1 end
        local ago = math.floor((now - r.time) / 86400)
        if ago >= 0 and ago < DAYS then d.perDay[ago][r.prof] = (d.perDay[ago][r.prof] or 0) + 1 end
        if Date then
            local t = Date("*t", r.time)
            if type(t) == "table" and t.wday and t.hour then
                local dw = (t.wday + 5) % 7 + 1 -- Monday first
                d.grid[dw][t.hour] = d.grid[dw][t.hour] + 1
                d.days[(t.year or 0) * 1000 + (t.yday or 0)] = true
            end
        end
        -- skill: this character's own, as each gather saw it
        if r.char == me and r.skill and r.skill > 0 then
            d.skill[r.prof] = d.skill[r.prof] or {}
            local sk = d.skill[r.prof]
            sk[#sk + 1] = { t = r.time, v = r.skill }
        end
    end
    d.nDays = 0
    for _ in pairs(d.days) do d.nDays = d.nDays + 1 end

    -- sessions, per character in time order: active time per zone and the best session's pace
    local order = {}
    for i, r in ipairs(d.recs) do order[i] = r end
    table.sort(order, function(a, b)
        if a.char ~= b.char then return a.char < b.char end
        return a.time < b.time
    end)
    local prev, count, start, last = nil, 0, nil, nil
    d.best, d.activeSecs = 0, 0
    local function Close()
        if count >= 10 then d.best = math.max(d.best, count / math.max(60, last - start + TAIL) * 3600) end
    end
    for _, r in ipairs(order) do
        local new = not prev or prev.char ~= r.char or r.time - prev.time > GAP
        if new then
            if prev then Close() end
            count, start = 0, r.time
        end
        count, last = count + 1, r.time
        local step = new and TAIL or (r.time - prev.time)
        d.zoneSecs[r.map] = (d.zoneSecs[r.map] or 0) + step
        d.activeSecs = d.activeSecs + step
        prev = r
    end
    if prev then Close() end
    for _, sk in pairs(d.skill) do table.sort(sk, function(a, b) return a.t < b.t end) end
    return d
end

local function TopKeys(counts, n, value)
    local keys = {}
    for k in pairs(counts) do keys[#keys + 1] = k end
    value = value or function(k) return counts[k] end
    table.sort(keys, function(a, b)
        local va, vb = value(a), value(b)
        if va ~= vb then return va > vb end
        return tostring(a) < tostring(b)
    end)
    local out = {}
    for i = 1, math.min(n, #keys) do out[i] = keys[i] end
    return out
end

-- ------------------------------------------------------------
-- Building
-- ------------------------------------------------------------
-- a section: its label (and a grey aside on the right), over an etched card
local function Section(parent, title)
    local s = {}
    s.label = St.Text(parent, 9, C.SUBTEXT)
    s.label:SetText(string.upper(title))
    s.aside = St.Text(parent, 9, FAINT)
    s.aside:SetJustifyH("RIGHT")
    s.card = St.Frame("Frame", parent)
    St.Etch(s.card, STYLE.card or STYLE.row, 4)
    function s:Place(x, y, w, h)
        self.label:ClearAllPoints()
        self.label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        self.aside:ClearAllPoints()
        self.aside:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + w, y)
        self.card:ClearAllPoints()
        self.card:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 13)
        self.card:SetSize(w, h)
        return y - 13 - h - 12
    end
    function s:SetShown(on)
        self.label:SetShown(on)
        self.aside:SetShown(on)
        self.card:SetShown(on)
    end
    return s
end

-- a bar row: an item's icon (or none), a name, a value, a thin bar
local function BarRows(card, n, w)
    local rows = {}
    for i = 1, n do
        local r = CreateFrame("Button", nil, card)
        r:SetSize(w, ROW_H)
        r:SetPoint("TOPLEFT", card, "TOPLEFT", CP, -CP + 2 - (i - 1) * ROW_H)
        r.hl = r:CreateTexture(nil, "BACKGROUND")
        r.hl:SetTexture(SOLID)
        r.hl:SetVertexColor(1, 0.82, 0, 0.07)
        r.hl:SetAllPoints()
        r.hl:Hide()
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(16, 16)
        r.icon:SetPoint("LEFT", r, "LEFT", 0, 0)
        r.name = St.Text(r, 10, C.TEXT)
        r.w = w
        r.name:SetWordWrap(false)
        r.value = St.Text(r, 10, C.SUBTEXT)
        r.value:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, -2)
        r.value:SetJustifyH("RIGHT")
        r.track = r:CreateTexture(nil, "BORDER")
        r.track:SetTexture(SOLID)
        r.track:SetVertexColor(EMPTY[1], EMPTY[2], EMPTY[3])
        r.track:SetHeight(3)
        r.fill = r:CreateTexture(nil, "ARTWORK")
        r.fill:SetTexture(SOLID)
        r.fill:SetHeight(3)
        r:SetScript("OnEnter", function(self)
            self.hl:Show()
            if self.tip then self.tip(self) end
        end)
        r:SetScript("OnLeave", function(self)
            self.hl:Hide()
            GameTooltip:Hide()
        end)
        rows[i] = r
    end
    return rows
end

-- fill a row: an icon texture, or nil for none (the name then starts at the left edge; a
-- letter on a dark square said nothing, Karl 2026-11-06); frac 0..1 of the bar
local function SetRow(r, icon, name, value, frac, color, tip)
    local x = icon and 22 or 0
    r.icon:SetShown(icon ~= nil)
    if icon then r.icon:SetTexture(icon) end
    r.name:ClearAllPoints()
    r.name:SetPoint("TOPLEFT", r, "TOPLEFT", x, -2)
    r.name:SetWidth(r.w - x - 56)
    r.track:ClearAllPoints()
    r.track:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", x, 3)
    r.track:SetWidth(r.w - x)
    r.fill:ClearAllPoints()
    r.fill:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", x, 3)
    r.barW = r.w - x
    r.name:SetText(name)
    r.value:SetText(value)
    r.fill:SetWidth(math.max(1, r.barW * math.max(0, math.min(1, frac))))
    r.fill:SetVertexColor(color[1], color[2], color[3])
    r.tip = tip
    r:Show()
end

-- a headline number: big value, a label, a faint line under it
local function Tile(parent, w)
    local t = St.Frame("Frame", parent)
    St.Etch(t, STYLE.card or STYLE.row, 4)
    t:SetSize(w, 52)
    t.value = St.Text(t, 15, C.TEXT)
    t.value:SetPoint("TOPLEFT", t, "TOPLEFT", 9, -8)
    t.value:SetWidth(w - 14)
    t.value:SetWordWrap(false)
    t.label = St.Text(t, 9, C.SUBTEXT)
    t.label:SetPoint("TOPLEFT", t, "TOPLEFT", 9, -27)
    t.sub = St.Text(t, 8, FAINT)
    t.sub:SetPoint("TOPLEFT", t, "TOPLEFT", 9, -39)
    t.sub:SetWidth(w - 14)
    t.sub:SetWordWrap(false)
    t:EnableMouse(true)
    t:SetScript("OnEnter", function(self) if self.tip then self.tip(self) end end)
    t:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return t
end

-- a little legend: a square and a word per entry, three to a line
local function Legend(parent, w)
    local g = { items = {} }
    for i = 1, 6 do
        local sq = parent:CreateTexture(nil, "ARTWORK")
        sq:SetTexture(SOLID)
        sq:SetSize(7, 7)
        local fs = St.Text(parent, 9, C.INK2)
        g.items[i] = { sq = sq, fs = fs }
    end
    function g:Set(list, x, y)
        for i, it in ipairs(self.items) do
            local e = list[i]
            it.sq:SetShown(e ~= nil)
            it.fs:SetShown(e ~= nil)
            if e then
                local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
                local px, py = x + col * (w / 3), y - row * 13
                it.sq:ClearAllPoints()
                it.sq:SetPoint("TOPLEFT", parent, "TOPLEFT", px, py - 3)
                it.sq:SetVertexColor(e.color[1], e.color[2], e.color[3])
                it.fs:ClearAllPoints()
                it.fs:SetPoint("TOPLEFT", parent, "TOPLEFT", px + 11, py)
                it.fs:SetText(e.label)
            end
        end
        return list[4] and 26 or (list[1] and 13 or 0)
    end
    return g
end

-- ------------------------------------------------------------
-- The page
-- ------------------------------------------------------------
-- opts: inner (the content's width), pad, top (the first row's y), ctrlH, Dropdown, ShowProvider,
-- WhenProvider, DockScroll (MapUI's own, so the page matches the dock's other pages)
function SP.Build(parent, opts)
    local M = FN.Map
    local W, PAD = opts.inner, opts.pad
    local CW = W - CP * 2 -- a chart's width inside its card
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetAllPoints()
    holder:Hide()
    holder.area = opts.DockScroll(holder)
    local d = holder.area.content
    holder.content = d

    -- Show and When, as on the dashboard (they share the map's choice)
    local w2 = (W - 6) / 2
    d.show = opts.Dropdown(d, opts.ShowProvider)
    d.show:SetSize(w2, opts.ctrlH)
    d.show:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, opts.top)
    d.when = opts.Dropdown(d, opts.WhenProvider)
    d.when:SetSize(w2, opts.ctrlH)
    d.when:SetPoint("TOPLEFT", d, "TOPLEFT", PAD + w2 + 6, opts.top)

    -- chips: All, then one per profession (a dot of its color); the choice is kept
    local chipY = opts.top - opts.ctrlH - 8
    local n = #M.PROFS
    local unit = (W - n * 4) / (n + 1.6)
    holder.chips = {}
    local x = PAD
    for i = 0, n do
        local p = i > 0 and M.PROFS[i] or nil
        local key = p and p.key or "all"
        local b = St.ChoiceButton(d, function()
            M.S().statsProf = key
            holder:Update()
            if opts.OnPick then opts.OnPick() end
        end)
        b.key = key
        local w = p and unit or unit * 1.6
        b:SetSize(w, 22)
        b:SetPoint("TOPLEFT", d, "TOPLEFT", x, chipY)
        x = x + w + 4
        if p then
            b.text:SetText("")
            b.dot = b:CreateTexture(nil, "OVERLAY")
            b.dot:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
            b.dot:SetSize(9, 9)
            b.dot:SetPoint("CENTER")
            b.dot:SetVertexColor(p.color[1], p.color[2], p.color[3])
            b.tip = p.label
        else
            b.text:SetText("All")
            b.tip = "Every profession"
        end
        holder.chips[#holder.chips + 1] = b
    end

    -- the four numbers
    local tw = (W - 6) / 2
    holder.tiles = {}
    for i = 1, 4 do holder.tiles[i] = Tile(d, tw) end

    -- Last 30 days: a column a day
    local cols = Section(d, "Last 30 days")
    cols.aside:SetText("a column a day")
    local COL_H = 70
    cols.chart = CreateFrame("Frame", nil, cols.card)
    cols.chart:SetSize(CW, COL_H)
    cols.chart:SetPoint("TOPLEFT", cols.card, "TOPLEFT", CP, -CP)
    cols.left = St.Text(cols.card, 8, FAINT)
    cols.left:SetPoint("TOPLEFT", cols.chart, "BOTTOMLEFT", 0, -3)
    cols.left:SetText("30 days ago")
    cols.right = St.Text(cols.card, 8, FAINT)
    cols.right:SetPoint("TOPRIGHT", cols.chart, "BOTTOMRIGHT", 0, -3)
    cols.right:SetText("Today")
    cols.legend = Legend(cols.card, CW)
    Hoverable(cols.chart)

    -- the donut: the mix of professions, or of one profession's items
    local mix = Section(d, "Profession mix")
    local DN = 100
    mix.chart = CreateFrame("Frame", nil, mix.card)
    mix.chart:SetSize(DN, DN)
    mix.chart:SetPoint("TOPLEFT", mix.card, "TOPLEFT", CP, -CP)
    mix.total = St.Text(mix.chart, 13, C.TEXT)
    mix.total:SetPoint("CENTER", mix.chart, "CENTER", 0, 4)
    mix.unit = St.Text(mix.chart, 8, C.SUBTEXT)
    mix.unit:SetPoint("TOP", mix.total, "BOTTOM", 0, -1)
    mix.rows = {}
    local listW = CW - DN - 10
    for i = 1, 6 do
        local r = CreateFrame("Button", nil, mix.card)
        r:SetSize(listW, 15)
        r:SetPoint("TOPLEFT", mix.chart, "TOPRIGHT", 10, -4 - (i - 1) * 15)
        r.hl = r:CreateTexture(nil, "BACKGROUND")
        r.hl:SetTexture(SOLID)
        r.hl:SetVertexColor(1, 0.82, 0, 0.08)
        r.hl:SetAllPoints()
        r.hl:Hide()
        r.sq = r:CreateTexture(nil, "ARTWORK")
        r.sq:SetTexture(SOLID)
        r.sq:SetSize(7, 7)
        r.sq:SetPoint("LEFT", r, "LEFT", 2, 0)
        r.name = St.Text(r, 9, C.TEXT)
        r.name:SetPoint("LEFT", r, "LEFT", 13, 0)
        r.name:SetWidth(listW - 13 - 58)
        r.name:SetWordWrap(false)
        r.pct = St.Text(r, 9, C.SUBTEXT)
        r.pct:SetPoint("RIGHT", r, "RIGHT", -2, 0)
        r.pct:SetJustifyH("RIGHT")
        r.n = St.Text(r, 9, C.INK2)
        r.n:SetPoint("RIGHT", r, "RIGHT", -32, 0)
        r.n:SetJustifyH("RIGHT")
        r.index = i
        r:SetScript("OnEnter", function(self) mix.chart:Hot(self.index, self) end)
        r:SetScript("OnLeave", function() mix.chart:Hot(nil) end)
        mix.rows[i] = r
    end
    Hoverable(mix.chart)

    -- When you gather: day by hour
    local grid = Section(d, "When you gather")
    grid.aside:SetText("day by hour")
    local GL = 22 -- the day names' column
    local cell = math.floor((CW - GL) / 24 * 10) / 10
    grid.chart = CreateFrame("Frame", nil, grid.card)
    grid.chart:SetSize(GL + cell * 24, cell * 7)
    grid.chart:SetPoint("TOPLEFT", grid.card, "TOPLEFT", CP, -CP)
    for i, name in ipairs(DOW) do
        local fs = St.Text(grid.chart, 8, FAINT)
        fs:SetPoint("LEFT", grid.chart, "TOPLEFT", 0, -(i - 0.5) * cell)
        fs:SetText(name)
    end
    for i, h in ipairs({ 0, 6, 12, 18 }) do
        local fs = St.Text(grid.card, 8, FAINT)
        fs:SetPoint("TOPLEFT", grid.chart, "BOTTOMLEFT", GL + h * cell, -3)
        fs:SetText(({ "12a", "6a", "12p", "6p" })[i])
    end
    Hoverable(grid.chart)

    -- Top loot and Best zones: bar rows
    local loot = Section(d, "Top loot")
    loot.aside:SetText("by count")
    loot.rows = BarRows(loot.card, 5, CW)
    local zones = Section(d, "Best zones")
    zones.rows = BarRows(zones.card, 5, CW)

    -- Skill climb: lines
    local climb = Section(d, "Skill climb")
    local SK_H = 72
    climb.chart = CreateFrame("Frame", nil, climb.card)
    climb.chart:SetSize(CW, SK_H)
    climb.chart:SetPoint("TOPLEFT", climb.card, "TOPLEFT", CP, -CP - 2)
    climb.empty = St.Text(climb.card, 10, C.SUBTEXT)
    climb.empty:SetPoint("TOPLEFT", climb.card, "TOPLEFT", CP + 2, -CP - 2)
    climb.empty:SetWidth(CW - 4)
    climb.empty:SetJustifyH("LEFT")
    climb.legend = Legend(climb.card, CW)
    climb.caps = {}
    for i = 1, #CAPS do
        local fs = St.Text(climb.chart, 8, { 0.55, 0.45, 0.27 })
        fs:SetJustifyH("RIGHT")
        climb.caps[i] = fs
    end
    Hoverable(climb.chart)

    -- the chosen profession's own card
    local own = Section(d, "")
    own.aside:SetText("this profession only")
    own.rows = BarRows(own.card, 5, CW)
    own.note = St.Text(own.card, 9, FAINT)
    own.note:SetWidth(CW)
    own.note:SetJustifyH("LEFT")

    local endNote = St.Text(d, 9, FAINT)
    endNote:SetText("Hover any bar, slice or square for details.")

    -- ---------------------------------------------------------------- drawing
    function holder:Update()
        local s = M.S()
        d.show:Update()
        d.when:Update()
        local pick = s.statsProf
        if pick ~= "all" and not M.PROF[pick] then pick = "all" end
        s.statsProf = pick
        for _, b in ipairs(self.chips) do b:SetChosen(b.key == pick) end
        local P = M.PROF[pick]
        local profs = P and { P } or M.PROFS
        local unitWord = P and P.units or "gathers"
        local accent = P and P.color or C.ACCENT
        local data = Collect(pick, s.show, s.when)
        self.data = data -- (read by tools/check.py)
        local total = #data.recs
        local y = chipY - 22 - 12

        -- the numbers
        local topZone = TopKeys(data.zone, 1)[1]
        local hours = data.activeSecs / 3600
        local perHour = hours > 0.05 and total / hours or 0
        local tiles = {
            { Commas(total), Cap(unitWord), s.when > 0 and ("in " .. s.when .. " days") or "all time",
                function(o) Tip(o, Cap(unitWord), nil, { { "Counted", Commas(total) },
                    { "Per day out", data.nDays > 0 and Commas(total / data.nDays) or "-" } }) end },
            { perHour > 0 and Commas(perHour) or "-", "Per hour",
                data.best > 0 and ("best session " .. Commas(data.best)) or "while you gather",
                function(o) Tip(o, "Per hour", nil, { { "Average", perHour > 0 and (Commas(perHour) .. "/hr") or "-" },
                    { "Best session", data.best > 0 and (Commas(data.best) .. "/hr") or "-" },
                    { "Time gathering", string.format("%.1f hr", hours) } },
                    "Counts the time between gathers; gaps over five minutes are left out.") end },
            { tostring(data.nDays), "Days out", s.when > 0 and ("of the last " .. s.when) or "with a gather",
                function(o) Tip(o, "Days out", nil, { { "Days with a gather", data.nDays } }) end },
            { topZone and ZoneName(topZone) or "-", "Top zone", topZone and (Commas(data.zone[topZone]) .. " " .. unitWord) or "",
                function(o)
                    if not topZone then return end
                    Tip(o, ZoneName(topZone), nil, { { Cap(unitWord), Commas(data.zone[topZone]) },
                        { "Share", math.floor(data.zone[topZone] / math.max(1, total) * 100 + 0.5) .. "%" } })
                end },
        }
        for i, t in ipairs(self.tiles) do
            local v = tiles[i]
            t.value:SetText(v[1])
            t.label:SetText(v[2])
            t.sub:SetText(v[3])
            t.tip = v[4]
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", d, "TOPLEFT", PAD + ((i - 1) % 2) * (tw + 6), y - math.floor((i - 1) / 2) * 58)
        end
        y = y - 58 * 2 - 6

        -- Last 30 days
        do
            local f = cols.chart
            Begin(f)
            local max = 1
            for i = 0, DAYS - 1 do
                local sum = 0
                for _, v in pairs(data.perDay[i]) do sum = sum + v end
                max = math.max(max, sum)
            end
            local bw = CW / DAYS
            for _, frac in ipairs({ 0.5, 1 }) do Rect(f, 0, COL_H - COL_H * frac, CW, 1, EMPTY, 1) end
            for i = 0, DAYS - 1 do
                local x0, base = (DAYS - 1 - i) * bw, COL_H
                for _, p in ipairs(profs) do
                    local v = data.perDay[i][p.key] or 0
                    if v > 0 then
                        local h = v / max * (COL_H - 3)
                        Rect(f, x0 + 0.5, base - h, bw - 1.5, h, p.color, 1)
                        base = base - h
                    end
                end
            end
            f.hl = rawget(f, "hl") or f:CreateTexture(nil, "OVERLAY")
            f.hl:SetTexture(SOLID)
            f.hl:SetVertexColor(1, 1, 1, 0.12)
            f.hl:Hide()
            Finish(f)
            function f:Pick(x, yy)
                if x < 0 or x > CW or yy < 0 or yy > COL_H then return end
                return DAYS - 1 - math.min(DAYS - 1, math.floor(x / bw))
            end
            function f:Hot(i)
                if not i then
                    self.hl:Hide()
                    GameTooltip:Hide()
                    return
                end
                self.hl:ClearAllPoints()
                self.hl:SetPoint("TOPLEFT", self, "TOPLEFT", (DAYS - 1 - i) * bw, 0)
                self.hl:SetSize(bw, COL_H)
                self.hl:Show()
                local rows = {}
                for _, p in ipairs(profs) do
                    local v = data.perDay[i][p.key]
                    if v and v > 0 then rows[#rows + 1] = { "|cff" .. string.format("%02x%02x%02x", p.color[1] * 255, p.color[2] * 255, p.color[3] * 255) .. p.label .. "|r", v } end
                end
                local when = i == 0 and "Today" or (i == 1 and "Yesterday" or (Date and Date("%a %b %d", data.now - i * 86400) or (i .. " days ago")))
                Tip(self, when, nil, rows, #rows == 0 and "Nothing gathered" or nil)
            end
            local legendH = 0
            if not P then
                local list = {}
                for _, p in ipairs(M.PROFS) do list[#list + 1] = { label = p.label, color = p.color } end
                legendH = cols.legend:Set(list, CP, -CP - COL_H - 16) + 4
            else
                cols.legend:Set({}, 0, 0)
            end
            cols:SetShown(true)
            y = cols:Place(PAD, y, W, CP + COL_H + 14 + legendH + CP)
        end

        -- the donut
        do
            local parts = {}
            if P then
                local pal = M.PALETTES[pick] or {}
                for i, id in ipairs(TopKeys(data.items, 5)) do
                    parts[#parts + 1] = { label = ItemName(id), v = data.items[id], color = pal[i] or M.OTHER_COLOR }
                end
            else
                for _, p in ipairs(M.PROFS) do
                    if (data.byProf[p.key] or 0) > 0 then parts[#parts + 1] = { label = p.label, v = data.byProf[p.key], color = p.color } end
                end
            end
            local sum = 0
            for _, pt in ipairs(parts) do sum = sum + pt.v end
            mix.label:SetText(P and "WHAT IT GAVE" or "PROFESSION MIX")
            mix.aside:SetText(P and "items, top five" or "share of gathers")
            mix.total:SetText(Commas(sum))
            mix.unit:SetText(P and "items" or "gathers")
            local f = mix.chart
            Begin(f)
            local N, R, r = 120, DN / 2 - 2, DN / 2 - 16
            local cx, cy = DN / 2, DN / 2
            f.segs = {}
            local acc, slice, edge = 0, 1, parts[1] and parts[1].v or 0
            for k = 0, N - 1 do
                local frac = (k + 0.5) / N
                while parts[slice + 1] and frac * sum > edge do
                    slice = slice + 1
                    edge = edge + parts[slice].v
                end
                local a = math.pi / 2 - frac * math.pi * 2
                local ca, sa = math.cos(a), math.sin(a)
                local c = sum > 0 and parts[slice] and parts[slice].color or EMPTY
                local l = Line(f, cx + ca * r, cy - sa * r, cx + ca * R, cy - sa * R, 2 * math.pi * R / N + 0.9, c, 1)
                if l then f.segs[#f.segs + 1] = { line = l, slice = sum > 0 and slice or 0, c = c } end
            end
            Finish(f)
            local function Light(i)
                -- dim by mixing toward the empty track at full alpha: the slice's lines overlap a
                -- little, and a lowered alpha stacked where they overlap (grey spokes)
                for _, sg in ipairs(f.segs) do
                    local c, k = sg.c, (not i or sg.slice == i) and 1 or 0.3
                    sg.line:SetVertexColor(c[1] * k + EMPTY[1] * (1 - k), c[2] * k + EMPTY[2] * (1 - k),
                        c[3] * k + EMPTY[3] * (1 - k), 1)
                end
                for j, row in ipairs(mix.rows) do row.hl:SetShown(i == j) end
            end
            function f:Pick(x, yy)
                local dx, dy = x - cx, cy - yy
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist < r - 2 or dist > R + 2 or sum <= 0 then return end
                local a = (math.pi / 2 - math.atan2(dy, dx)) % (math.pi * 2)
                local at, run = a / (math.pi * 2) * sum, 0
                for i, pt in ipairs(parts) do
                    run = run + pt.v
                    if at <= run then return i end
                end
                return #parts
            end
            function f:Hot(i, owner)
                Light(i)
                if not i or not parts[i] then
                    GameTooltip:Hide()
                    return
                end
                local pt = parts[i]
                Tip(owner or self, pt.label, pt.color, { { P and "Items" or "Gathers", Commas(pt.v) },
                    { "Share", string.format("%.1f%%", pt.v / math.max(1, sum) * 100) } })
            end
            for i, row in ipairs(mix.rows) do
                local pt = parts[i]
                row:SetShown(pt ~= nil)
                if pt then
                    row.sq:SetVertexColor(pt.color[1], pt.color[2], pt.color[3])
                    row.name:SetText(pt.label)
                    row.n:SetText(Commas(pt.v))
                    row.pct:SetText(math.floor(pt.v / math.max(1, sum) * 100 + 0.5) .. "%")
                end
            end
            Light(nil)
            mix:SetShown(true)
            y = mix:Place(PAD, y, W, CP + DN + CP)
        end

        -- When you gather
        do
            local f = grid.chart
            Begin(f)
            local max = 1
            for dw = 1, 7 do for h = 0, 23 do max = math.max(max, data.grid[dw][h]) end end
            for dw = 1, 7 do
                for h = 0, 23 do
                    local v = data.grid[dw][h]
                    if v > 0 then
                        Rect(f, GL + h * cell, (dw - 1) * cell, cell - 1.5, cell - 1.5, accent, 0.15 + 0.85 * (v / max) ^ 0.7)
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
                local v = data.grid[dw][h]
                Tip(self, DOW_LONG[dw] .. ", " .. HourText(h), nil, { { Cap(unitWord), v } },
                    (v > 0 and v == max) and "Your busiest hour" or nil)
            end
            grid:SetShown(true)
            y = grid:Place(PAD, y, W, CP + cell * 7 + 14 + CP - 2)
        end

        -- Top loot
        do
            local ids = TopKeys(data.items, 5)
            local first = ids[1] and data.items[ids[1]] or 1
            for i, row in ipairs(loot.rows) do
                local id = ids[i]
                if id then
                    local p = M.PROF[data.itemProf[id]] or P or { color = C.ACCENT, label = "" }
                    local from = 0
                    for _, r in ipairs(data.recs) do if r.items[id] then from = from + 1 end end
                    SetRow(row, FN.ItemIcon(id) or nil, ItemName(id), Commas(data.items[id]), data.items[id] / first, p.color,
                        function(o)
                            Tip(o, ItemName(id), nil, { { "Looted", Commas(data.items[id]) },
                                { "From", Commas(from) .. " " .. (p.units or "gathers") },
                                { "Each time", string.format("%.1f", data.items[id] / math.max(1, from)) } }, p.label)
                        end)
                else
                    row:Hide()
                end
            end
            loot:SetShown(#ids > 0)
            if #ids > 0 then y = loot:Place(PAD, y, W, CP * 2 + #ids * ROW_H - 4) end
        end

        -- Best zones
        do
            local rate = {}
            for mapID, n in pairs(data.zone) do
                local secs = data.zoneSecs[mapID] or 0
                if n >= 5 and secs > 0 then rate[mapID] = n / secs * 3600 end
            end
            local ids = TopKeys(rate, 5)
            local first = ids[1] and rate[ids[1]] or 1
            zones.aside:SetText((P and P.units or "gathers") .. " per hour")
            for i, row in ipairs(zones.rows) do
                local mapID = ids[i]
                if mapID then
                    local name = ZoneName(mapID)
                    SetRow(row, nil, name, Commas(rate[mapID]) .. "/hr", rate[mapID] / first, accent,
                        function(o)
                            Tip(o, name, nil, { { "Per hour", Commas(rate[mapID]) }, { Cap(unitWord), Commas(data.zone[mapID]) },
                                { "Time here", string.format("%.1f hr", (data.zoneSecs[mapID] or 0) / 3600) } })
                        end)
                else
                    row:Hide()
                end
            end
            zones:SetShown(#ids > 0)
            if #ids > 0 then y = zones:Place(PAD, y, W, CP * 2 + #ids * ROW_H - 4) end
        end

        -- Skill climb
        do
            local f = climb.chart
            Begin(f)
            local series = {}
            for _, p in ipairs(profs) do
                local sk = data.skill[p.key]
                if not p.anyone and sk and #sk > 0 then series[#series + 1] = { p = p, pts = sk } end
            end
            local lo, hi, t0, t1 = 1000, 0, nil, data.now
            for _, se in ipairs(series) do
                for _, pt in ipairs(se.pts) do
                    lo, hi = math.min(lo, pt.v), math.max(hi, pt.v)
                    t0 = t0 and math.min(t0, pt.t) or pt.t
                end
            end
            t0 = data.since or t0
            f.points = {}
            local legendH = 0
            if #series == 0 then
                climb.empty:SetText(P and P.anyone and (P.label .. " has no skill to climb: every character can do it.")
                    or "No skill gains here yet. Gather with a profession and its climb shows here.")
                climb.empty:Show()
                for _, fs in ipairs(climb.caps) do fs:Hide() end
                climb.legend:Set({}, 0, 0)
                Finish(f)
                climb:SetShown(true)
                y = climb:Place(PAD, y, W, CP * 2 + 28)
            else
                climb.empty:Hide()
                lo, hi = math.max(0, lo - 8), hi + 8
                local span = math.max(1, t1 - (t0 or t1))
                local function X(t) return (t - (t0 or t1)) / span * (CW - 2) + 1 end
                local function Y(v) return SK_H - (v - lo) / math.max(1, hi - lo) * (SK_H - 4) - 2 end
                for i, cap in ipairs(CAPS) do
                    local on = cap > lo and cap < hi
                    climb.caps[i]:SetShown(on)
                    if on then
                        Rect(f, 0, Y(cap), CW, 1, { 0.35, 0.29, 0.16 }, 1)
                        climb.caps[i]:ClearAllPoints()
                        climb.caps[i]:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, -Y(cap) + 1)
                        climb.caps[i]:SetText("cap " .. cap)
                    end
                end
                local list = {}
                for _, se in ipairs(series) do
                    -- a step a day at most: the day's highest skill
                    local byDay, keys = {}, {}
                    for _, pt in ipairs(se.pts) do
                        local k = math.floor(pt.t / 86400)
                        if not byDay[k] then keys[#keys + 1] = k end
                        if not byDay[k] or pt.v > byDay[k].v then byDay[k] = pt end
                    end
                    table.sort(keys)
                    local prevX, prevY
                    local start = byDay[keys[1]].v
                    for _, k in ipairs(keys) do
                        local pt = byDay[k]
                        local px, py = X(pt.t), Y(pt.v)
                        if prevX then Line(f, prevX, prevY, px, py, 2, se.p.color, 1) end
                        prevX, prevY = px, py
                        f.points[#f.points + 1] = { x = px, y = py, p = se.p, v = pt.v, t = pt.t, gain = pt.v - start }
                    end
                    if #keys == 1 then Rect(f, prevX - 2, prevY - 2, 4, 4, se.p.color, 1) end
                    list[#list + 1] = { label = se.p.label, color = se.p.color }
                end
                f.hl = rawget(f, "hl") or f:CreateTexture(nil, "OVERLAY")
                f.hl:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
                f.hl:SetSize(7, 7)
                f.hl:Hide()
                Finish(f)
                function f:Pick(x, yy)
                    local best, bestD
                    for i, pt in ipairs(self.points) do
                        local dd = (pt.x - x) ^ 2 + (pt.y - yy) ^ 2
                        if not bestD or dd < bestD then best, bestD = i, dd end
                    end
                    if bestD and bestD < 14 * 14 then return best end
                end
                function f:Hot(i)
                    local pt = i and self.points[i]
                    if not pt then
                        self.hl:Hide()
                        GameTooltip:Hide()
                        return
                    end
                    self.hl:ClearAllPoints()
                    self.hl:SetPoint("CENTER", self, "TOPLEFT", pt.x, -pt.y)
                    self.hl:SetVertexColor(pt.p.color[1], pt.p.color[2], pt.p.color[3])
                    self.hl:Show()
                    Tip(self, pt.p.label .. " " .. pt.v, pt.p.color, {
                        { "Day", Date and Date("%b %d", pt.t) or "" },
                        { "Gained since", "+" .. pt.gain } })
                end
                if not P and #list > 1 then legendH = climb.legend:Set(list, CP, -CP - 2 - SK_H - 8) + 4 else climb.legend:Set({}, 0, 0) end
                climb:SetShown(true)
                y = climb:Place(PAD, y, W, CP + 2 + SK_H + 8 + legendH + CP - 4)
            end
            climb.aside:SetText(s.when > 0 and ("over " .. s.when .. " days") or "all time")
        end

        -- the profession's own card
        if P then
            local entries, title, note = {}, "", nil
            local function Named(counts, nameOf, n)
                for _, k in ipairs(TopKeys(counts, n)) do
                    entries[#entries + 1] = { name = nameOf(k), v = counts[k], text = Commas(counts[k]) }
                end
            end
            local view = FN.View()
            local function Creature(id) local c = view.creatures and view.creatures[id]; return (c and c.name) or "Unknown creature" end
            local function Node(id) local c = view.nodes and view.nodes[id]; return (c and c.name) or "Unknown" end
            if pick == "skinning" then
                title = "Ruined and creatures"
                local pct = total > 0 and data.ruined / total * 100 or 0
                entries[1] = { name = "Ruined scraps", v = pct, max = 100, text = math.floor(pct + 0.5) .. "%",
                    tip = "Skins that gave Ruined Leather Scraps. Fewer at higher skill." }
                Named(data.npcs, Creature, 4)
            elseif pick == "cloth" then
                title = "Drop rate by creature"
                local rate = {}
                for npc, c in pairs(data.cloth) do if c.loots >= 3 then rate[npc] = c.drops / c.loots * 100 end end
                for _, npc in ipairs(TopKeys(rate, 5)) do
                    local c = data.cloth[npc]
                    entries[#entries + 1] = { name = Creature(npc), v = rate[npc], max = 100, text = math.floor(rate[npc] + 0.5) .. "%",
                        tip = c.drops .. " of " .. c.loots .. " loots gave cloth." }
                end
                note = "Of humanoid loots: how often each creature dropped cloth."
            elseif pick == "treasure" then
                title = "Best chests"
                Named(data.npcs, Node, 5)
            elseif pick == "mining" then
                title = "Veins"
                Named(data.npcs, Node, 5)
            elseif pick == "herbalism" then
                title = "Herbs"
                Named(data.npcs, Node, 5)
            else
                title = "Waters"
                Named(data.zone, ZoneName, 5)
            end
            own.label:SetText(string.upper(title))
            local top = 1
            for _, e in ipairs(entries) do if not e.max then top = math.max(top, e.v) end end
            for i, row in ipairs(own.rows) do
                local e = entries[i]
                if e then
                    SetRow(row, nil, e.name, e.text, e.v / (e.max or top), P.color, function(o)
                        Tip(o, e.name, nil, { { e.max and "Rate" or "Count", e.text } }, e.tip)
                    end)
                else
                    row:Hide()
                end
            end
            own.note:SetShown(note ~= nil)
            local h = CP * 2 + #entries * ROW_H - 4
            if note then
                own.note:SetText(note)
                own.note:ClearAllPoints()
                own.note:SetPoint("TOPLEFT", own.card, "TOPLEFT", CP, -CP - #entries * ROW_H)
                h = h + 16
            end
            own:SetShown(#entries > 0)
            if #entries > 0 then y = own:Place(PAD, y, W, h) end
        else
            own:SetShown(false)
        end

        endNote:ClearAllPoints()
        endNote:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, y + 2)
        holder.area:SetHeight(-y + 24) -- (measures the page, and the scroll bar follows)
    end
    return holder
end
