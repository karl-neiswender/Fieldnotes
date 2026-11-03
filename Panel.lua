local ADDON, FN = ...

-- The stats window (/fn): four headline numbers, your best zones for leather per hour, what
-- your skins gave you, and the creatures of the zone you are in. Me or Account at the top
-- right chooses whose skins it counts. Built once, redrawn when it opens or the data changes.
--
-- Rates come from sessions found in the records themselves: one character's skins with less
-- than five minutes between them are one session, and its time is counted per zone.

local St = FN.Style
local C = St.C
local STYLE = St.STYLE

local RUINED = 2934
local GAP = 300 -- seconds between skins that split two sessions
local TAIL = 20 -- seconds a session's last skin is counted as taking
local W, H = 720, 470
local PAD = 16
local ZONE_ROWS, CREATURE_ROWS, MIX = 5, 7, 5

local frame, ui = nil, {}
FN.statsUI = ui -- read by tools/check.py
local zoneRows, creatureRows, mixBars, mixKeys = {}, {}, {}, {}

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

local function ZoneName(mapID)
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return (info and info.name) or ("Map " .. mapID)
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

-- Skinning needed for a creature of this level (Classic's rule)
local function SkillFor(level)
    if not level or level <= 10 then return 1 end
    if level <= 20 then return (level - 10) * 10 end
    return level * 5
end

local function Show()
    local s = FN.db.settings
    if s.statsShow ~= "me" then s.statsShow = "account" end
    return s.statsShow
end

-- ------------------------------------------------------------
-- Numbers
-- ------------------------------------------------------------
local function Collect()
    local view = FN.View()
    local show, me = Show(), FN.ViewChar()
    local all, chars = {}, {}
    for mapID, list in pairs(view.events.skinning or {}) do
        for _, str in ipairs(list) do
            local r = FN.Decode(str)
            if r and (show ~= "me" or r.char == me) then
                r.map = mapID
                all[#all + 1] = r
                chars[r.char] = true
            end
        end
    end
    local nChars = 0
    for _ in pairs(chars) do nChars = nChars + 1 end

    -- sessions: per character, in time order, split by long gaps; time is counted per zone
    table.sort(all, function(a, b)
        if a.char ~= b.char then return a.char < b.char end
        return a.time < b.time
    end)
    local zoneSecs, zoneLeather, zoneSkins, zoneWho, zoneLoot = {}, {}, {}, {}, {}
    local bestRate, prev = 0, nil
    local sessCount, sessStart, sessLast = 0, nil, nil
    local function CloseSession()
        if sessCount >= 10 then
            bestRate = math.max(bestRate, sessCount / math.max(1, (sessLast - sessStart + TAIL) / 60))
        end
    end
    local mix, ruined, maxSkill = {}, 0, 0
    for _, r in ipairs(all) do
        local newSession = not prev or prev.char ~= r.char or r.time - prev.time > GAP
        if newSession then
            if prev then CloseSession() end
            sessCount, sessStart = 0, r.time
        end
        sessCount, sessLast = sessCount + 1, r.time
        local step = newSession and TAIL or (r.time - prev.time)
        zoneSecs[r.map] = (zoneSecs[r.map] or 0) + step
        zoneSkins[r.map] = (zoneSkins[r.map] or 0) + 1
        zoneWho[r.map] = zoneWho[r.map] or {}
        zoneLoot[r.map] = zoneLoot[r.map] or {}
        if r.npc > 0 then zoneWho[r.map][r.npc] = (zoneWho[r.map][r.npc] or 0) + 1 end
        if r.items[RUINED] then ruined = ruined + 1 end
        for id, n in pairs(r.items) do
            mix[id] = (mix[id] or 0) + n
            if id ~= RUINED then
                zoneLeather[r.map] = (zoneLeather[r.map] or 0) + n
                zoneLoot[r.map][id] = (zoneLoot[r.map][id] or 0) + n
            end
        end
        if r.char == me then maxSkill = math.max(maxSkill, r.skill or 0) end
        prev = r
    end
    if prev then CloseSession() end

    return {
        all = all, nChars = nChars, ruined = ruined, mix = mix, bestRate = bestRate,
        zoneSecs = zoneSecs, zoneLeather = zoneLeather, zoneSkins = zoneSkins,
        zoneWho = zoneWho, zoneLoot = zoneLoot, maxSkill = maxSkill,
    }
end

-- ------------------------------------------------------------
-- Building
-- ------------------------------------------------------------
local function Tile(parent)
    local t = St.Frame("Frame", parent)
    St.Etch(t, STYLE.row, 12)
    t.label = St.Text(t, 10, C.SUBTEXT)
    t.label:SetPoint("TOPLEFT", 12, -10)
    t.value = St.Text(t, 20, C.TEXT)
    t.value:SetPoint("TOPLEFT", 12, -24)
    t.sub = St.Text(t, 10, C.SUBTEXT)
    t.sub:SetPoint("TOPLEFT", 12, -48)
    return t
end

local function Heading(parent, text)
    local h = St.Title(parent, 12)
    h:SetText(text)
    return h
end

local function Build()
    frame = St.Frame("Frame", UIParent)
    frame:SetSize(W, H)
    frame:SetFrameStrata("FULLSCREEN_DIALOG") -- above the map and its Fieldnotes bar
    St.Etch(frame, STYLE.window, 16)
    St.Movable(frame, "statsPos")
    St.PlaceSaved(frame, "statsPos", "CENTER", "CENTER", 0, 40)
    frame:Hide()
    _G.FieldnotesStatsFrame = frame
    if UISpecialFrames then table.insert(UISpecialFrames, "FieldnotesStatsFrame") end -- Escape closes it

    ui.title = St.Title(frame, 16)
    ui.title:SetPoint("TOPLEFT", PAD + 2, -PAD)
    ui.title:SetText("Fieldnotes")
    ui.sub = St.Text(frame, 11, C.SUBTEXT)
    ui.sub:SetPoint("LEFT", ui.title, "RIGHT", 10, -1)

    ui.close = St.IconButton(frame, "close-white", 14, function() frame:Hide() end)
    ui.close:SetPoint("TOPRIGHT", -PAD, -PAD)
    ui.shows = {}
    local x = -PAD - 14 - 12
    for i = 2, 1, -1 do
        local opt = ({ { "me", "Me" }, { "account", "Account" } })[i]
        local b = St.ChoiceButton(frame, function()
            FN.db.settings.statsShow = opt[1]
            FN.RefreshStats()
        end)
        b.text:SetText(opt[2])
        b.key = opt[1]
        b:SetWidth(math.ceil(b.text:GetStringWidth()) + 18)
        b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", x, -PAD + 4)
        x = x - b:GetWidth() - 3
        ui.shows[i] = b
    end

    ui.rule = frame:CreateTexture(nil, "ARTWORK")
    ui.rule:SetColorTexture(0.33, 0.29, 0.20, 0.8)
    ui.rule:SetHeight(1)
    ui.rule:SetPoint("TOPLEFT", PAD, -46)
    ui.rule:SetPoint("TOPRIGHT", -PAD, -46)

    local tileW = (W - PAD * 2 - 3 * 10) / 4
    ui.tiles = {}
    for i = 1, 4 do
        local t = Tile(frame)
        t:SetSize(tileW, 66)
        t:SetPoint("TOPLEFT", PAD + (i - 1) * (tileW + 10), -58)
        ui.tiles[i] = t
    end

    -- left column: best zones, then what you got
    local colW = (W - PAD * 2 - 20) / 2
    local left = CreateFrame("Frame", nil, frame)
    left:SetPoint("TOPLEFT", PAD, -140)
    left:SetSize(colW, H - 140 - PAD)
    ui.zonesHead = Heading(left, "Best zones for your skill")
    ui.zonesHead:SetPoint("TOPLEFT", 0, 0)
    ui.zonesCap = St.Text(left, 10, C.SUBTEXT)
    ui.zonesCap:SetPoint("TOPRIGHT", 0, -1)
    ui.zonesCap:SetJustifyH("RIGHT")
    ui.zonesCap:SetText("Leather per hour")
    for i = 1, ZONE_ROWS do
        local row = {}
        local y = -22 - (i - 1) * 40
        row.name = St.Text(left, 11, C.TEXT)
        row.name:SetPoint("TOPLEFT", 0, y)
        row.value = St.Text(left, 11, C.TITLE)
        row.value:SetPoint("TOPRIGHT", 0, y)
        row.value:SetJustifyH("RIGHT")
        row.bar = St.Bar(left, 6)
        row.bar:SetPoint("TOPLEFT", 0, y - 16)
        row.bar:SetPoint("TOPRIGHT", 0, y - 16)
        row.note = St.Text(left, 10, C.SUBTEXT)
        row.note:SetPoint("TOPLEFT", 0, y - 26)
        row.note:SetWidth(colW)
        zoneRows[i] = row
    end
    ui.zonesEmpty = St.Text(left, 11, C.INK2)
    ui.zonesEmpty:SetPoint("TOPLEFT", 0, -24)
    ui.zonesEmpty:SetWidth(colW)

    local mixY = -22 - ZONE_ROWS * 40 - 8
    ui.mixHead = Heading(left, "What you got")
    ui.mixHead:SetPoint("TOPLEFT", 0, mixY)
    ui.mixBar = CreateFrame("Frame", nil, left)
    ui.mixBar:SetPoint("TOPLEFT", 0, mixY - 22)
    ui.mixBar:SetSize(colW, 10)
    for i = 1, MIX do
        local t = ui.mixBar:CreateTexture(nil, "ARTWORK")
        t:SetTexture(St.SOLID)
        t:SetHeight(10)
        mixBars[i] = t
        local k = {}
        k.dot = left:CreateTexture(nil, "ARTWORK")
        k.dot:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        k.dot:SetSize(8, 8)
        k.text = St.Text(left, 10, C.INK2)
        k.text:SetPoint("LEFT", k.dot, "RIGHT", 5, 0)
        mixKeys[i] = k
    end
    ui.mixY = mixY
    ui.left = left
    ui.colW = colW

    -- right column: the creatures of one zone
    local right = CreateFrame("Frame", nil, frame)
    right:SetPoint("TOPRIGHT", -PAD, -140)
    right:SetSize(colW, H - 140 - PAD)
    ui.whoHead = Heading(right, "Creatures")
    ui.whoHead:SetPoint("TOPLEFT", 0, 0)
    ui.whoCap = St.Text(right, 10, C.SUBTEXT)
    ui.whoCap:SetPoint("TOPRIGHT", 0, -1)
    ui.whoCap:SetJustifyH("RIGHT")
    local cols = { { "Creature", 0, "LEFT" }, { "Skins", 196, "RIGHT" }, { "Main drop", 212, "LEFT" }, { "Ruined", colW, "RIGHT" } }
    for _, c in ipairs(cols) do
        local h = St.Text(right, 10, C.SUBTEXT)
        h:SetText(c[1])
        h:SetJustifyH(c[3])
        if c[3] == "RIGHT" then h:SetPoint("TOPRIGHT", right, "TOPLEFT", c[2], -24) else h:SetPoint("TOPLEFT", c[2], -24) end
    end
    for i = 1, CREATURE_ROWS do
        local row = {}
        local y = -40 - (i - 1) * 34
        row.line = right:CreateTexture(nil, "ARTWORK")
        row.line:SetColorTexture(0.33, 0.29, 0.20, 0.45)
        row.line:SetHeight(1)
        row.line:SetPoint("TOPLEFT", 0, y)
        row.line:SetPoint("TOPRIGHT", 0, y)
        row.name = St.Text(right, 11, C.TEXT)
        row.name:SetPoint("TOPLEFT", 0, y - 6)
        row.name:SetWidth(170)
        row.name:SetWordWrap(false)
        row.meta = St.Text(right, 10, C.SUBTEXT)
        row.meta:SetPoint("TOPLEFT", 0, y - 19)
        row.skins = St.Text(right, 11, C.TITLE)
        row.skins:SetPoint("TOPRIGHT", right, "TOPLEFT", 196, y - 6)
        row.skins:SetJustifyH("RIGHT")
        row.dot = right:CreateTexture(nil, "ARTWORK")
        row.dot:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        row.dot:SetSize(8, 8)
        row.dot:SetPoint("TOPLEFT", 212, y - 8)
        row.drop = St.Text(right, 11, C.TEXT)
        row.drop:SetPoint("LEFT", row.dot, "RIGHT", 5, 0)
        row.drop:SetWidth(colW - 212 - 13 - 44)
        row.drop:SetWordWrap(false)
        row.ruined = St.Text(right, 11, C.INK2)
        row.ruined:SetPoint("TOPRIGHT", 0, y - 6)
        row.ruined:SetJustifyH("RIGHT")
        creatureRows[i] = row
    end
    ui.whoEmpty = St.Text(right, 11, C.INK2)
    ui.whoEmpty:SetPoint("TOPLEFT", 0, -44)
    ui.whoEmpty:SetWidth(colW)

    ui.demo = St.Text(frame, 10, C.SUBTEXT)
    ui.demo:SetPoint("BOTTOMLEFT", PAD, PAD - 4)
    ui.demo:SetText("Sample data  ·  /fn demo off to hide it")

    frame:SetScript("OnShow", function() FN.RefreshStats() end)
end

-- ------------------------------------------------------------
-- Drawing
-- ------------------------------------------------------------
local function SetTile(i, label, value, sub)
    local t = ui.tiles[i]
    t.label:SetText(label)
    t.value:SetText(value)
    t.sub:SetText(sub)
end

local function Swatch(tex, id, colorOf)
    local c = colorOf[id] or FN.Map.OTHER_COLOR
    tex:SetVertexColor(c[1], c[2], c[3])
end

function FN.RefreshStats()
    if not frame or not frame:IsShown() then return end
    local show = Show()
    for _, b in pairs(ui.shows) do b:SetChosen(b.key == show) end
    local d = Collect()
    local view = FN.View()
    local inDemo = view ~= FN.db
    ui.demo:SetShown(inDemo)

    local live = FN.SkinningSkill and FN.SkinningSkill() or 0
    local skill = (not inDemo and live > 0) and live or d.maxSkill
    ui.sub:SetText(string.format("Skinning %s  ·  %s", skill > 0 and skill or "-",
        show == "me" and "This character" or "All characters"))

    -- headline numbers
    local total = #d.all
    SetTile(1, "Skins", Commas(total), show == "me" and "All time, this character"
        or string.format("All time, %d character%s", d.nChars, d.nChars == 1 and "" or "s"))
    local s = FN.session
    if s.count > 0 then
        SetTile(2, "Skins per minute", string.format("%.1f", FN.SessionRate()),
            d.bestRate > 0 and string.format("This session  ·  best %.1f", d.bestRate) or "This session")
        SetTile(3, "Leather per hour", Commas(FN.SessionLeatherRate()), "This session")
    else
        SetTile(2, "Skins per minute", d.bestRate > 0 and string.format("%.1f", d.bestRate) or "-", "Your best session")
        local bestZone, bestLph = nil, 0
        for map, secs in pairs(d.zoneSecs) do
            local lph = (d.zoneLeather[map] or 0) / math.max(1 / 60, secs / 3600)
            if (d.zoneSkins[map] or 0) >= 10 and lph > bestLph then bestZone, bestLph = map, lph end
        end
        SetTile(3, "Leather per hour", bestLph > 0 and Commas(bestLph) or "-", bestZone and ("Best: " .. ZoneName(bestZone)) or "Skin a while to see it")
    end
    SetTile(4, "Ruined", total > 0 and (math.floor(d.ruined / total * 100 + 0.5) .. "%") or "-", "Fewer at higher skill")

    -- best zones: leather per hour, zones you have the skill for first
    local zones = {}
    for map, secs in pairs(d.zoneSecs) do
        if (d.zoneSkins[map] or 0) >= 10 then
            local need = 0
            for npc in pairs(d.zoneWho[map]) do
                local c = view.creatures[npc]
                if c and c.minLevel then need = math.max(need, SkillFor(c.minLevel)) end
            end
            zones[#zones + 1] = {
                map = map, lph = (d.zoneLeather[map] or 0) / math.max(1 / 60, secs / 3600),
                need = need, can = skill <= 0 or need <= skill,
            }
        end
    end
    table.sort(zones, function(a, b)
        if a.can ~= b.can then return a.can end
        return a.lph > b.lph
    end)
    local peak = zones[1] and zones[1].lph or 1
    for _, z in ipairs(zones) do peak = math.max(peak, z.lph) end
    for i, row in ipairs(zoneRows) do
        local z = zones[i]
        row.name:SetShown(z ~= nil)
        row.value:SetShown(z ~= nil)
        row.bar:SetShown(z ~= nil)
        row.note:SetShown(z ~= nil)
        if z then
            row.name:SetText(ZoneName(z.map))
            local c = z.can and C.TEXT or C.SUBTEXT
            row.name:SetTextColor(c[1], c[2], c[3])
            row.value:SetText(Commas(z.lph))
            row.bar:SetValue(z.lph / peak)
            row.bar:SetAlpha(z.can and 1 or 0.45)
            local lead = Top(d.zoneLoot[z.map], 1)[1]
            local whoNames = {}
            for _, npc in ipairs(Top(d.zoneWho[z.map], 2)) do
                local cr = view.creatures[npc]
                whoNames[#whoNames + 1] = (cr and cr.name) or "Unknown creature"
            end
            local note = (lead and ItemName(lead) or "") .. "  ·  " .. table.concat(whoNames, ", ")
            if not z.can then note = string.format("Needs about %d skill  ·  %s", z.need, note) end
            row.note:SetText(note)
        end
    end
    ui.zonesEmpty:SetShown(#zones == 0)
    ui.zonesEmpty:SetText(total == 0 and "Skin something, or type /fn demo to try Fieldnotes with sample data."
        or "Skin a little longer in one zone to see its leather per hour.")

    -- what you got: the leading leathers, then everything else, Ruined last
    local colorOf, rank = {}, {}
    local leathers = {}
    for id, n in pairs(d.mix) do
        if id ~= RUINED then leathers[id] = n end
    end
    local lead = Top(leathers, MIX - 1)
    for i, id in ipairs(lead) do
        colorOf[id] = FN.Map.PALETTE[i] or FN.Map.OTHER_COLOR
        rank[#rank + 1] = id
    end
    if d.mix[RUINED] then
        colorOf[RUINED] = FN.Map.RUINED_COLOR
        rank[#rank + 1] = RUINED
    end
    local sum = 0
    for _, id in ipairs(rank) do sum = sum + d.mix[id] end
    local x, kx, ky = 0, 0, ui.mixY - 40
    for i = 1, MIX do
        local id, bar, key = rank[i], mixBars[i], mixKeys[i]
        bar:SetShown(id ~= nil)
        key.dot:SetShown(id ~= nil)
        key.text:SetShown(id ~= nil)
        if id then
            local w = math.max(2, (ui.colW - (#rank - 1) * 2) * d.mix[id] / sum)
            bar:ClearAllPoints()
            bar:SetPoint("LEFT", ui.mixBar, "LEFT", x, 0)
            bar:SetWidth(w)
            local c = colorOf[id]
            St.VGradient(bar, c, { c[1] * 0.7, c[2] * 0.7, c[3] * 0.7 })
            x = x + w + 2
            key.text:SetText(string.format("%s  %d%%", ItemName(id), math.floor(d.mix[id] / sum * 100 + 0.5)))
            Swatch(key.dot, id, colorOf)
            local kw = 13 + key.text:GetStringWidth() + 14
            if kx > 0 and kx + kw > ui.colW then kx, ky = 0, ky - 16 end
            key.dot:ClearAllPoints()
            key.dot:SetPoint("TOPLEFT", ui.left, "TOPLEFT", kx, ky - 2)
            kx = kx + kw
        end
    end
    ui.mixHead:SetShown(#rank > 0)

    -- creatures: the zone you are in, or your busiest zone
    local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local map = here
    if not (map and d.zoneSkins[map]) then
        map = Top(d.zoneSkins, 1)[1]
    end
    ui.whoCap:SetText(map and ZoneName(map) or "")
    local rows = {}
    if map then
        local per = {}
        for _, r in ipairs(d.all) do
            if r.map == map and r.npc > 0 then
                local p = per[r.npc]
                if not p then
                    p = { npc = r.npc, skins = 0, ruined = 0, loot = {} }
                    per[r.npc] = p
                    rows[#rows + 1] = p
                end
                p.skins = p.skins + 1
                if r.items[RUINED] then p.ruined = p.ruined + 1 end
                for id, n in pairs(r.items) do
                    if id ~= RUINED then p.loot[id] = (p.loot[id] or 0) + n end
                end
            end
        end
        table.sort(rows, function(a, b) return a.skins > b.skins end)
    end
    for i, row in ipairs(creatureRows) do
        local p = rows[i]
        for _, k in ipairs({ "name", "meta", "skins", "dot", "drop", "ruined", "line" }) do row[k]:SetShown(p ~= nil) end
        if p then
            local cr = view.creatures[p.npc]
            row.name:SetText((cr and cr.name) or "Unknown creature")
            local lv = cr and cr.minLevel and (cr.minLevel == cr.maxLevel and cr.minLevel or (cr.minLevel .. "-" .. cr.maxLevel))
            row.meta:SetText(((cr and cr.type) or "Creature") .. (lv and ("  ·  " .. lv) or ""))
            row.skins:SetText(p.skins)
            local drop = Top(p.loot, 1)[1]
            row.drop:SetText(drop and ItemName(drop) or "-")
            Swatch(row.dot, drop, colorOf)
            row.ruined:SetText(math.floor(p.ruined / p.skins * 100 + 0.5) .. "%")
        end
    end
    ui.whoEmpty:SetShown(#rows == 0)
    ui.whoEmpty:SetText("Creatures you skin show up here.")
end

function FN.ShowStats()
    if not frame then Build() end
    frame:Show()
    FN.RefreshStats()
end

function FN.ToggleStats()
    if frame and frame:IsShown() then frame:Hide() else FN.ShowStats() end
end

FN.OnData(function() FN.RefreshStats() end)
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "GET_ITEM_INFO_RECEIVED") -- leather names arriving after the first draw
ev:SetScript("OnEvent", function() FN.RefreshStats() end)
