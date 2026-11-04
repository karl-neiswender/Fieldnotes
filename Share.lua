local ADDON, FN = ...

-- Sharing: your notes as one line of text to copy and paste anywhere (a game add-on cannot
-- reach the internet or the clipboard), and an Import box that adds someone else's line to
-- your Community layer, never to your own numbers.
--
-- The text is "!FN1!<share id>!<flags><checksum>!<body>":
--   share id  six random letters made once per account, so a newer share from the same
--             person replaces their older one instead of counting twice. Not a name.
--   flags     "D" for demo mode's sample data (which only imports into demo mode), else "-"
--   checksum  catches a paste that was cut short
--   body      tallies, not single skins: each zone is cut into a 32 x 32 grid (squares about
--             25 yards across) and each square holds, per creature, how many skins, how many
--             weeks before the zone's newest skin, and the loot. The share lists its leathers
--             once and each zone its creatures once, so a tally points at them by number.
--             No character names, realms or times of day.
-- Every number is written as a small base-64 varint (5 bits per letter, a flag for "more").

local St = FN.Style
local C = St.C

local GRID = 32
local EPOCH_DAY = 18262 -- 2020-01-01, so day numbers stay short
local PREFIX = "!FN1!"
local ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local VALUE = {}
for i = 1, #ALPHA do VALUE[ALPHA:sub(i, i)] = i - 1 end

local Share = {}
FN.Share = Share

-- ------------------------------------------------------------
-- Writing and reading numbers
-- ------------------------------------------------------------
local function PutInt(out, n)
    n = math.max(0, math.floor(n))
    while n >= 32 do
        local d = n % 32
        out[#out + 1] = ALPHA:sub(33 + d, 33 + d)
        n = math.floor(n / 32)
    end
    out[#out + 1] = ALPHA:sub(n + 1, n + 1)
end

-- a reader over the body: r:Int() returns the next number, or nil past the end or on a bad letter
local function Reader(body)
    local pos, len = 1, #body
    local r = {}
    function r:Int()
        local total, mult = 0, 1
        while pos <= len do
            local v = VALUE[body:sub(pos, pos)]
            pos = pos + 1
            if not v then return nil end
            if v >= 32 then
                total = total + (v - 32) * mult
                mult = mult * 32
            else
                return total + v * mult
            end
        end
        return nil
    end
    function r:Done() return pos > len end
    return r
end

local function Checksum(body)
    local sum = 0
    for i = 1, #body do sum = (sum * 31 + body:byte(i)) % 1048573 end
    return sum
end

function Share.ID()
    local id = FN.db.shareID
    if type(id) ~= "string" or #id ~= 6 then
        local t = {}
        for i = 1, 6 do
            local k = math.random(1, 52)
            t[i] = ALPHA:sub(k, k)
        end
        id = table.concat(t)
        FN.db.shareID = id
    end
    return id
end

-- ------------------------------------------------------------
-- Making share text
-- ------------------------------------------------------------
-- mapIDs: the zones to share (nil: every zone). Returns the text, skins, zones.
function Share.Make(mapIDs)
    local view = FN.View()
    local byMap = view.events.skinning or {}
    local zones = {}
    if mapIDs then
        for _, id in ipairs(mapIDs) do zones[#zones + 1] = id end
    else
        for id in pairs(byMap) do zones[#zones + 1] = id end
    end
    table.sort(zones)

    local out, skins, zoneCount = {}, 0, 0
    local parts = {}
    for _, mapID in ipairs(zones) do
        local tallies, order = {}, {}
        for _, str in ipairs(byMap[mapID] or {}) do
            local r = FN.Decode(str)
            if r and r.x and r.y and r.npc then
                local cell = math.min(GRID - 1, math.floor(r.y / 1000 * GRID)) * GRID
                    + math.min(GRID - 1, math.floor(r.x / 1000 * GRID))
                local key = cell * 1000000 + r.npc
                local t = tallies[key]
                if not t then
                    t = { cell = cell, npc = r.npc, skins = 0, day = 0, items = {} }
                    tallies[key] = t
                    order[#order + 1] = key
                end
                t.skins = t.skins + 1
                t.day = math.max(t.day, math.floor(r.time / 86400) - EPOCH_DAY)
                for id, n in pairs(r.items) do t.items[id] = (t.items[id] or 0) + n end
            end
        end
        if #order > 0 then
            table.sort(order)
            zoneCount = zoneCount + 1
            parts[#parts + 1] = { mapID = mapID, tallies = tallies, order = order }
        end
    end

    -- the share's leathers, once
    local itemIDs, itemIndex = {}, {}
    for _, z in ipairs(parts) do
        for _, key in ipairs(z.order) do
            for id in pairs(z.tallies[key].items) do
                if not itemIndex[id] then
                    itemIDs[#itemIDs + 1] = id
                    itemIndex[id] = true
                end
            end
        end
    end
    table.sort(itemIDs)
    for i, id in ipairs(itemIDs) do itemIndex[id] = i - 1 end
    PutInt(out, #itemIDs)
    for _, id in ipairs(itemIDs) do PutInt(out, id) end

    PutInt(out, #parts)
    for _, z in ipairs(parts) do
        -- the zone: its newest day, and its creatures once
        local newest, npcs, npcIndex = 0, {}, {}
        for _, key in ipairs(z.order) do
            local t = z.tallies[key]
            newest = math.max(newest, t.day)
            if not npcIndex[t.npc] then
                npcs[#npcs + 1] = t.npc
                npcIndex[t.npc] = true
            end
        end
        table.sort(npcs)
        for i, npc in ipairs(npcs) do npcIndex[npc] = i - 1 end
        PutInt(out, z.mapID)
        PutInt(out, math.max(0, newest))
        PutInt(out, #npcs)
        for _, npc in ipairs(npcs) do PutInt(out, npc) end
        PutInt(out, #z.order)
        for _, key in ipairs(z.order) do
            local t = z.tallies[key]
            PutInt(out, t.cell)
            PutInt(out, npcIndex[t.npc])
            PutInt(out, t.skins)
            PutInt(out, math.floor((newest - t.day) / 7)) -- weeks before the zone's newest
            local ids = {}
            for id in pairs(t.items) do ids[#ids + 1] = id end
            table.sort(ids)
            PutInt(out, #ids)
            for _, id in ipairs(ids) do
                PutInt(out, itemIndex[id])
                PutInt(out, t.items[id])
            end
            skins = skins + t.skins
        end
    end
    local body = table.concat(out)
    local check = {}
    PutInt(check, Checksum(body))
    local flags = (view ~= FN.db) and "D" or "-"
    return PREFIX .. Share.ID() .. "!" .. flags .. table.concat(check) .. "!" .. body, skins, zoneCount
end

-- ------------------------------------------------------------
-- Reading share text
-- ------------------------------------------------------------
-- Returns a share { sender, demo, zones = { [mapID] = { tally... } }, skins, zoneCount }
-- or nil and a reason a player can act on.
function Share.Read(text)
    text = (text or ""):gsub("%s+", "")
    if text == "" then return nil, "" end
    local start = text:find(PREFIX, 1, true)
    if not start then return nil, "That doesn't look like Fieldnotes share text." end
    local sender, flags, check, body = text:sub(start):match("^!FN1!(%w%w%w%w%w%w)!([D%-])([%w%+/]-)!([%w%+/]*)$")
    if not sender then return nil, "The share text looks incomplete. Copy the whole line again." end
    local want = Reader(check):Int()
    if want ~= Checksum(body) then return nil, "Part of the share text is missing. Copy the whole line again." end

    local BAD = "The share text could not be read."
    local r = Reader(body)
    local share = { sender = sender, demo = flags == "D", zones = {}, skins = 0, zoneCount = 0 }
    local nItems = r:Int()
    if not nItems then return nil, BAD end
    local itemIDs = {}
    for i = 1, nItems do
        itemIDs[i] = r:Int()
        if not itemIDs[i] then return nil, BAD end
    end
    local nZones = r:Int()
    if not nZones then return nil, BAD end
    for _ = 1, nZones do
        local mapID, newest, nNpcs = r:Int(), r:Int(), r:Int()
        if not (mapID and newest and nNpcs) then return nil, BAD end
        local npcs = {}
        for i = 1, nNpcs do
            npcs[i] = r:Int()
            if not npcs[i] then return nil, BAD end
        end
        local nTallies = r:Int()
        if not nTallies then return nil, BAD end
        local list = {}
        for _ = 1, nTallies do
            local cell, ni, n, weeks, kinds = r:Int(), r:Int(), r:Int(), r:Int(), r:Int()
            if not (cell and ni and n and weeks and kinds and npcs[ni + 1]) then return nil, BAD end
            local t = { cell = cell, npc = npcs[ni + 1], skins = n, day = newest - weeks * 7, items = {} }
            for _ = 1, kinds do
                local ii, k = r:Int(), r:Int()
                if not (ii and k and itemIDs[ii + 1]) then return nil, BAD end
                t.items[itemIDs[ii + 1]] = k
            end
            list[#list + 1] = t
            share.skins = share.skins + t.skins
        end
        share.zones[mapID] = list
        share.zoneCount = share.zoneCount + 1
    end
    if not r:Done() then return nil, BAD end
    return share
end

-- ------------------------------------------------------------
-- The Community layer
-- ------------------------------------------------------------
-- Imported shares live in <store>.community.senders[share id] = { at, skins, events }, each
-- tally turned back into skins near its square's centre so the map draws them like any others.
local function Target() return FN.View() end

local function Expand(t)
    local out = {}
    local cx, cy = t.cell % GRID, math.floor(t.cell / GRID)
    local time = (t.day + EPOCH_DAY) * 86400 + 43200
    for k = 1, t.skins do
        -- spread the skins a little inside their square, the same way every time
        local jx = ((k * 37 + t.cell * 11) % 13) / 13
        local jy = ((k * 53 + t.cell * 7) % 11) / 11
        local items = {}
        for id, n in pairs(t.items) do
            local share = math.floor(n / t.skins) + ((k <= n % t.skins) and 1 or 0)
            if share > 0 then items[id] = share end
        end
        out[#out + 1] = FN.Encode({
            x = math.floor((cx + jx) / GRID * 1000), y = math.floor((cy + jy) / GRID * 1000),
            time = time, npc = t.npc, char = 0, skill = 0, items = items,
        })
    end
    return out
end

-- skins already imported from this share id (for "new to you")
function Share.Known(sender)
    local c = Target().community
    local s = c and c.senders and c.senders[sender]
    return s and s.skins or 0
end

function Share.Import(share)
    local store = Target()
    if share.sender == Share.ID() and store == FN.db then return false, "That's your own share text." end
    if share.demo and store == FN.db then
        return false, "That's sample data from demo mode. It can only be imported in demo mode."
    end
    store.community = store.community or {}
    store.community.senders = store.community.senders or {}
    local events = { skinning = {} }
    for mapID, list in pairs(share.zones) do
        local records = {}
        for _, t in ipairs(list) do
            for _, str in ipairs(Expand(t)) do records[#records + 1] = str end
        end
        events.skinning[mapID] = records
    end
    store.community.senders[share.sender] = { at = time(), skins = share.skins, events = events }
    FN.NotifyData()
    return true
end

function Share.CommunityTotals()
    local c = Target().community
    local sets, skins = 0, 0
    for _, s in pairs(c and c.senders or {}) do
        sets, skins = sets + 1, skins + (s.skins or 0)
    end
    return sets, skins
end

function Share.ClearCommunity()
    local c = Target().community
    if c then c.senders = nil end
    FN.NotifyData()
end

-- Every list of Community skins for one zone: demo mode's sample layer plus imported shares.
function FN.CommunityLists(profession, mapID)
    local c, out = FN.View().community, {}
    if not c then return out end
    local l = c.events and c.events[profession] and c.events[profession][mapID]
    if l then out[#out + 1] = l end
    for _, s in pairs(c.senders or {}) do
        l = s.events and s.events[profession] and s.events[profession][mapID]
        if l then out[#out + 1] = l end
    end
    return out
end

-- ------------------------------------------------------------
-- The window: Share or Import, one at a time
-- ------------------------------------------------------------
-- The same family as the stats window: "Fieldnotes" and a subtitle, the choices at the top
-- right, a rule, then one task. Share: what to share, the text (selected, ready for Ctrl+C),
-- whether it fits in a Discord message, and what it holds. Import: paste, a preview card,
-- then Add to Community.
local W, H, PAD = 480, 344, 18
local GREEN = { 0.31, 0.75, 0.23 }
local AMBER = { 0.95, 0.66, 0.20 }
local RED = { 0.90, 0.45, 0.35 }
local DISCORD = 2000 -- characters Discord takes in one message
local frame, ui = nil, {}
FN.shareUI = ui -- read by tools/check.py

local function ZoneName(mapID)
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return (info and info.name) or ("Map " .. mapID)
end

local function Plural(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

local function CurrentZone()
    local id = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local byMap = FN.View().events.skinning or {}
    if id and byMap[id] and #byMap[id] > 0 then return id end
end

local function Box(parent, width)
    local eb = St.Frame("EditBox", parent)
    St.Etch(eb, St.STYLE.row, 12)
    eb:SetSize(width, 30)
    eb:SetAutoFocus(false)
    eb:SetFont(STANDARD_TEXT_FONT, 11, "")
    eb:SetTextColor(C.TEXT[1], C.TEXT[2], C.TEXT[3])
    eb:SetTextInsets(10, 10, 0, 0)
    pcall(eb.SetMaxLetters, eb, 0)
    pcall(eb.SetMaxBytes, eb, 0)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return eb
end

local function Label(parent, text)
    local fs = St.Text(parent, 10, C.SUBTEXT)
    fs:SetText(text)
    return fs
end

-- a small status: a coloured dot and words
local function Status(parent)
    local s = {}
    s.dot = parent:CreateTexture(nil, "ARTWORK")
    s.dot:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    s.dot:SetSize(7, 7)
    s.text = St.Text(parent, 10, C.INK2)
    s.text:SetPoint("LEFT", s.dot, "RIGHT", 6, 0)
    function s:Set(color, words)
        self.dot:SetVertexColor(color[1], color[2], color[3])
        self.text:SetText(words)
        self.dot:Show()
        self.text:Show()
    end
    function s:Hide()
        self.dot:Hide()
        self.text:Hide()
    end
    return s
end

-- the gold button used for the one main action; dimmed and inert until it has something to do
local function Primary(parent, label, onClick)
    local b = St.ChoiceButton(parent, onClick)
    b.text:SetText(label)
    b:SetChosen(true)
    b:SetScript("OnLeave", function(self) self:SetChosen(true) end)
    b:SetSize(math.ceil(b.text:GetStringWidth()) + 28, 24)
    function b:SetReady(on)
        if on then self:Enable() else self:Disable() end
        self:SetAlpha(on and 1 or 0.4)
    end
    return b
end

local Show -- picks a tab (below)

local function MakeShareText()
    local zone = CurrentZone()
    if ui.scope == "zone" and not zone then ui.scope = "all" end
    local text, skins, zones = Share.Make(ui.scope == "zone" and { zone } or nil)
    ui.text = text
    ui.out:SetText(text)
    ui.out:SetCursorPosition(0)
    ui.out:HighlightText()
    if ui.tab == "share" and frame:IsShown() then ui.out:SetFocus() end
    ui.scopeZone:SetChosen(ui.scope == "zone")
    ui.scopeAll:SetChosen(ui.scope == "all")
    ui.scopeZone:SetAlpha(zone and 1 or 0.4)
    ui.scopeZone.tip = not zone and "You haven't skinned in the zone you're in." or nil
    if skins == 0 then
        ui.summary:SetText("Nothing skinned yet. Skin something, then share it.")
    elseif ui.scope == "zone" then
        ui.summary:SetText(ZoneName(zone) .. "  ·  " .. Plural(skins, "skin"))
    else
        ui.summary:SetText(Plural(zones, "zone") .. "  ·  " .. Plural(skins, "skin"))
    end
    if #text <= DISCORD then
        ui.fit:Set(GREEN, "Fits in a Discord message")
    else
        ui.fit:Set(AMBER, "Long: share it as a text file or forum post")
    end
    ui.demoNote:SetShown(FN.View() ~= FN.db)
end

local function UpdateCommunityLine()
    local sets, skins = Share.CommunityTotals()
    ui.community:SetText(sets == 0 and "Your Community layer is empty"
        or ("Community: " .. Plural(sets, "share") .. "  ·  " .. Plural(skins, "skin")))
    ui.clear:SetShown(sets > 0)
end

local function ReadImport()
    local text = ui.input:GetText() or ""
    local share, why = Share.Read(text)
    ui.pending = share
    for _, k in ipairs({ "skins", "zones", "new", "skinsL", "zonesL", "newL" }) do ui[k]:SetShown(share ~= nil) end
    ui.zoneList:SetShown(share ~= nil)
    ui.waiting:SetShown(share == nil and text:gsub("%s", "") == "")
    ui.add:SetReady(share ~= nil)
    if share then
        ui.state:Set(GREEN, "Ready to add")
        ui.skins:SetText(share.skins)
        ui.zones:SetText(share.zoneCount)
        ui.new:SetText(math.max(0, share.skins - Share.Known(share.sender)))
        local names = {}
        for mapID in pairs(share.zones) do names[#names + 1] = ZoneName(mapID) end
        table.sort(names)
        ui.zoneList:SetText(table.concat(names, "  ·  "))
    elseif ui.waiting:IsShown() then
        ui.state:Hide()
    else
        ui.state:Set(RED, why or "That can't be read.")
    end
end

local function Build()
    frame = St.Frame("Frame", UIParent)
    frame:SetSize(W, H)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    St.Etch(frame, St.STYLE.window, 16)
    St.Grime(frame, 0.25, 16, 0.37, 150, 220) -- as the stats window, its tile started elsewhere
    St.Movable(frame, "sharePos")
    St.PlaceSaved(frame, "sharePos", "CENTER", "CENTER", 0, 60)
    frame:Hide()
    _G.FieldnotesShareFrame = frame
    if UISpecialFrames then table.insert(UISpecialFrames, "FieldnotesShareFrame") end

    -- header, as in the stats window
    local title = St.Title(frame, 16)
    title:SetPoint("TOPLEFT", PAD + 2, -PAD)
    title:SetText("Fieldnotes")
    ui.sub = St.Text(frame, 11, C.SUBTEXT)
    ui.sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
    ui.close = St.IconButton(frame, "close-white", 14, function() frame:Hide() end)
    ui.close:SetPoint("TOPRIGHT", -PAD, -PAD)
    ui.tabs = {}
    local x = -PAD - 14 - 12
    for i = 2, 1, -1 do
        local key = i == 1 and "share" or "import"
        local b = St.ChoiceButton(frame, function() Show(key) end)
        b.text:SetText(i == 1 and "Share" or "Import")
        b.key = key
        b:SetWidth(math.ceil(b.text:GetStringWidth()) + 18)
        b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", x, -PAD + 4)
        x = x - b:GetWidth() - 3
        ui.tabs[i] = b
    end
    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(0.33, 0.29, 0.20, 0.8)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", PAD, -46)
    rule:SetPoint("TOPRIGHT", -PAD, -46)

    local innerW = W - PAD * 2

    -- Share
    local share = CreateFrame("Frame", nil, frame)
    share:SetPoint("TOPLEFT", PAD, -60)
    share:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    ui.sharePage = share
    Label(share, "WHAT TO SHARE"):SetPoint("TOPLEFT", 0, 0)
    local half = (innerW - 6) / 2
    ui.scopeZone = St.ChoiceButton(share, function()
        if CurrentZone() then ui.scope = "zone" end
        MakeShareText()
    end)
    ui.scopeZone.text:SetText("This zone")
    ui.scopeZone:SetSize(half, 26)
    ui.scopeZone:SetPoint("TOPLEFT", 0, -16)
    ui.scopeAll = St.ChoiceButton(share, function()
        ui.scope = "all"
        MakeShareText()
    end)
    ui.scopeAll.text:SetText("All my skinning")
    ui.scopeAll:SetSize(half, 26)
    ui.scopeAll:SetPoint("TOPLEFT", half + 6, -16)
    ui.summary = St.Text(share, 11, C.INK2)
    ui.summary:SetPoint("TOPLEFT", 0, -52)

    Label(share, "SHARE TEXT"):SetPoint("TOPLEFT", 0, -82)
    ui.select = St.ChoiceButton(share, function()
        ui.out:SetFocus()
        ui.out:HighlightText()
    end)
    ui.select.text:SetText("Select")
    ui.select:SetSize(math.ceil(ui.select.text:GetStringWidth()) + 24, 30)
    ui.select:SetPoint("TOPRIGHT", 0, -98)
    ui.select.tip = "Selects the text again, ready for Ctrl+C"
    ui.out = Box(share, innerW - ui.select:GetWidth() - 6)
    ui.out:SetPoint("TOPLEFT", 0, -98)
    -- read-only: any typing puts the text back and selects it again
    ui.out:SetScript("OnTextChanged", function(self, typed)
        if typed and ui.text then
            self:SetText(ui.text)
            self:HighlightText()
        end
    end)
    ui.out:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    ui.out:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    local copy = St.Text(share, 11, C.TEXT)
    copy:SetPoint("TOPLEFT", 0, -138)
    copy:SetText("Press Ctrl+C to copy, then paste it anywhere.")
    ui.fit = Status(share)
    ui.fit.dot:SetPoint("TOPLEFT", 1, -158)

    local foot = share:CreateTexture(nil, "ARTWORK")
    foot:SetColorTexture(0.33, 0.29, 0.20, 0.45)
    foot:SetHeight(1)
    foot:SetPoint("BOTTOMLEFT", 0, 40)
    foot:SetPoint("BOTTOMRIGHT", 0, 40)
    local privacy = St.Text(share, 10, C.SUBTEXT)
    privacy:SetPoint("BOTTOMLEFT", 0, 20)
    privacy:SetWidth(innerW)
    privacy:SetText("Shares where you skinned, what and how much. Never your name, realm or times of day.")
    ui.demoNote = St.Text(share, 10, C.SUBTEXT)
    ui.demoNote:SetPoint("BOTTOMLEFT", 0, 4)
    ui.demoNote:SetText("Sample data: it only imports into demo mode.")

    -- Import
    local import = CreateFrame("Frame", nil, frame)
    import:SetPoint("TOPLEFT", PAD, -60)
    import:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    ui.importPage = import
    Label(import, "PASTE SHARE TEXT  (Ctrl+V)"):SetPoint("TOPLEFT", 0, 0)
    ui.input = Box(import, innerW)
    ui.input:SetPoint("TOPLEFT", 0, -16)
    ui.input:SetScript("OnTextChanged", function() ReadImport() end)
    ui.input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- the preview card
    local card = St.Frame("Frame", import)
    St.Etch(card, St.STYLE.row, 12)
    card:SetPoint("TOPLEFT", 0, -56)
    card:SetSize(innerW, 128)
    ui.state = Status(card)
    ui.state.dot:SetPoint("TOPLEFT", 14, -16)
    ui.waiting = St.Text(card, 11, C.SUBTEXT)
    ui.waiting:SetPoint("CENTER", 0, 6)
    ui.waiting:SetJustifyH("CENTER")
    ui.waiting:SetText("Paste share text above to see what's in it.")
    local labels = { "skins", "zones", "new to you" }
    for i, k in ipairs({ "skins", "zones", "new" }) do
        ui[k] = St.Text(card, 20, C.TEXT)
        ui[k]:SetPoint("TOPLEFT", 14 + (i - 1) * 110, -34)
        ui[k .. "L"] = St.Text(card, 10, C.SUBTEXT)
        ui[k .. "L"]:SetPoint("TOPLEFT", ui[k], "BOTTOMLEFT", 0, -2)
        ui[k .. "L"]:SetText(labels[i])
    end
    ui.zoneList = St.Text(card, 10, C.INK2)
    ui.zoneList:SetPoint("TOPLEFT", 14, -88)
    ui.zoneList:SetWidth(innerW - 28)
    ui.zoneList:SetJustifyV("TOP")
    local note = St.Text(import, 10, C.SUBTEXT)
    note:SetPoint("TOPLEFT", 0, -192)
    note:SetWidth(innerW)
    note:SetText("It goes into your Community layer, never your own numbers. A newer share from the same person replaces their older one.")

    ui.add = Primary(import, "Add to Community", function()
        if not ui.pending then return end
        local ok, why = Share.Import(ui.pending)
        if ok then
            FN.Print(string.format("Added %s to your Community layer.", Plural(ui.pending.skins, "skin")))
            ui.input:SetText("")
            ReadImport()
            ui.state:Set(GREEN, "Added. Choose Community on your map to see it.")
        else
            ui.state:Set(RED, why)
        end
        UpdateCommunityLine()
    end)
    ui.add:SetPoint("BOTTOMRIGHT", 0, 0)
    ui.community = St.Text(import, 10, C.SUBTEXT)
    ui.community:SetPoint("BOTTOMLEFT", 0, 6)
    ui.clear = St.ChoiceButton(import, function()
        Share.ClearCommunity()
        UpdateCommunityLine()
        ReadImport()
    end)
    ui.clear.text:SetText("Remove all")
    ui.clear:SetSize(math.ceil(ui.clear.text:GetStringWidth()) + 18, 22)
    ui.clear:SetPoint("LEFT", ui.community, "RIGHT", 10, 0)
    ui.clear.tip = "Empties your Community layer. Your own notes stay."

    ui.scope = "zone"
    ui.tab = "share"
end

Show = function(tab)
    ui.tab = tab
    for _, b in ipairs(ui.tabs) do b:SetChosen(b.key == tab) end
    ui.sharePage:SetShown(tab == "share")
    ui.importPage:SetShown(tab == "import")
    ui.sub:SetText(tab == "share" and "Share notes" or "Import notes")
    if tab == "share" then
        MakeShareText()
    else
        ReadImport()
        UpdateCommunityLine()
        ui.input:SetFocus()
    end
end

function FN.ShareFrame() return frame end

function FN.ShowShare(focusImport)
    if not frame then Build() end
    ui.tab = focusImport and "import" or "share"
    frame:Show()
    Show(ui.tab)
end

function FN.ToggleShare()
    if frame and frame:IsShown() then frame:Hide() else FN.ShowShare() end
end
