local ADDON, FN = ...

-- Gathering detection: one record per gather, the same shape for every profession.
--
-- Skinning, Mining, Herbalism: the profession's cast is noted when it is sent (with its target's
--   name), cleared if it fails, and the next loot window within a few seconds is the gather.
--   Skinning's source is the creature; Mining's and Herbalism's is the node (its object ID).
-- Fishing: a loot window the game marks as fishing loot (IsFishingLoot), or, on a client without
--   that, loot from no creature soon after a Fishing cast. The source is 0: where you stood.
-- Cloth: an ordinary kill's loot (no gathering cast before it). Every loot of a humanoid is
--   recorded, with its cloth or with nothing, so cloth can show a drop rate. A creature of
--   another type counts once it has dropped cloth (Felcloth from demons). A corpse opened twice
--   counts once. Pick Pocket's loot never counts.
-- Treasure: a chest, trunk or strongbox in the world (a game object, not a lockbox in your bags).
--   Its loot with no gathering cast before it, when the object's name says chest (from the
--   Opening cast that came first) or the loot holds money (any language). Quest crates give
--   neither and are left out. The source is the object; one opened twice counts once.
-- Money: coin you loot (design/money-2026-11-10, option 1A), from the game's own "You loot ..." and
--   "Your share of the loot is ..." lines, which come once per coin taken, so a corpse opened twice
--   counts once. Vendor and auction house money are not gathering and are left out. The source is
--   the loot window's creature or object; the amount is kept as FN.COIN, its count the copper.

local PROFS = {
    -- spell IDs by rank (Apprentice to Artisan), and a spell whose name is the skill line's
    skinning = { spells = { 8613, 8617, 8618, 10768 }, window = 6 },
    mining = { spells = { 2575, 2576, 3564, 10248 }, window = 10 },
    herbalism = { spells = { 2366, 2368, 3570, 11993 }, window = 10, skillNames = { "Herbalism" } },
    fishing = { spells = { 7620, 7731, 7732, 18248 }, window = 35 },
}
FN.GATHER_PROFS = PROFS
local PICK_POCKET = 921
-- the game's Opening casts (a chest's lid, a locked one picked or forced): their target's name
local OPENING = { [3365] = true, [6247] = true, [6477] = true, [6478] = true, [21651] = true, [22810] = true }
-- words in a treasure's name (English; elsewhere the money test still finds one)
local CHEST_WORDS = { "chest", "trunk", "strongbox", "coffer", "footlocker", "cache", "treasure", "lockbox" }
local CLOTH = { [2589] = true, [2592] = true, [4306] = true, [4338] = true, [14047] = true, [14256] = true }
FN.CLOTH_ITEMS = CLOTH

-- spellID -> profession, and each profession's spell name (filled at login, in the client's language)
local bySpell, spellName = {}, {}
for prof, p in pairs(PROFS) do
    for _, id in ipairs(p.spells) do bySpell[id] = prof end
end
local pickName, openName

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return GetSpellInfo and (GetSpellInfo(id)) or nil
end

local function ProfOfSpell(spellID)
    if not spellID then return nil end
    if bySpell[spellID] then return bySpell[spellID] end
    local name = SpellName(spellID)
    if not name then return nil end
    for prof, n in pairs(spellName) do
        if n == name then return prof end
    end
end

local function IsOpening(spellID)
    return OPENING[spellID] or (openName and SpellName(spellID) == openName)
end

local function IsPickPocket(spellID)
    return spellID == PICK_POCKET or (pickName and SpellName(spellID) == pickName)
end

-- "Creature-0-1234-0-56-2522-0000ABCD" -> 2522; "GameObject-0-...-1731-..." for nodes
local function IdFromGUID(guid, kind)
    if type(guid) ~= "string" then return nil end
    local k, _, _, _, _, id = strsplit("-", guid)
    if k == kind then return tonumber(id) end
end
local function NpcFromGUID(guid) return IdFromGUID(guid, "Creature") end
FN.NpcFromGUID = NpcFromGUID

-- What we last saw of each nearby creature: right-clicking a corpse to skin it does not target
-- it, so its type and level come from an earlier mouseover or target.
local seen, seenCount = {}, 0
local function Remember(unit)
    if not UnitExists(unit) or UnitIsPlayer(unit) then return end
    local guid = UnitGUID(unit)
    if not NpcFromGUID(guid) then return end
    if not seen[guid] then
        seenCount = seenCount + 1
        if seenCount > 300 then
            wipe(seen)
            seenCount = 1
        end
    end
    seen[guid] = { name = UnitName(unit), type = UnitCreatureType(unit), level = UnitLevel(unit) }
end

-- a profession's rank, and the most the current rank allows (75 for Apprentice, and so on)
function FN.ProfessionSkill(prof)
    -- the name is read at login; if the game had not loaded the spell yet, read it now
    if not spellName[prof] and PROFS[prof] then spellName[prof] = SpellName(PROFS[prof].spells[1]) end
    local want = spellName[prof]
    local extra = PROFS[prof] and PROFS[prof].skillNames
    if not want and not extra then return 0 end
    local function Matches(name)
        local match = name == want
        if not match and extra then
            for _, e in ipairs(extra) do match = match or name == e end
        end
        return match
    end
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
            if not isHeader and name and Matches(name) then return rank or 0, maxRank end
        end
    end
    -- a client that lists professions apart from the legacy skills pane
    if GetProfessions and GetProfessionInfo then
        local slots = { GetProfessions() }
        for i = 1, 6 do
            if slots[i] then
                local name, _, rank, maxRank = GetProfessionInfo(slots[i])
                if name and Matches(name) then return rank or 0, maxRank end
            end
        end
    end
    return 0
end
function FN.SkinningSkill() return FN.ProfessionSkill("skinning") end

local function PlayerPosition()
    if not (C_Map and C_Map.GetBestMapForUnit) then return 0 end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return 0 end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return mapID end
    local x, y = pos:GetXY()
    if not x or (x == 0 and y == 0) then return mapID end
    return mapID, math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5)
end
FN.PlayerPosition = PlayerPosition

-- the loot window's source: a creature's GUID, or else a node's
local function LootSource()
    if not GetLootSourceInfo then return nil end
    local node
    for slot = 1, GetNumLootItems() do
        local guid = GetLootSourceInfo(slot)
        if NpcFromGUID(guid) then return guid, "creature" end
        if IdFromGUID(guid, "GameObject") then node = node or guid end
    end
    if node then return node, "node" end
end

function FN.NoteCreature(npc, info, fallbackName, store)
    if not npc or npc == 0 then return end
    local creatures = (store or FN.db).creatures
    local c = creatures[npc]
    if not c then
        c = {}
        creatures[npc] = c
    end
    c.name = (info and info.name) or c.name or fallbackName
    if info then
        c.type = info.type or c.type
        local lvl = info.level
        if lvl and lvl > 0 then
            c.minLevel = math.min(c.minLevel or lvl, lvl)
            c.maxLevel = math.max(c.maxLevel or lvl, lvl)
        end
    end
    return c
end

-- nodes by object ID: { name } ("Copper Vein", "Peacebloom")
function FN.NoteNode(id, name, store)
    if not id or id == 0 then return end
    store = store or FN.db
    store.nodes = store.nodes or {}
    local n = store.nodes[id]
    if not n then
        n = {}
        store.nodes[id] = n
    end
    n.name = name or n.name
end

-- the loot window's items: { itemID = count } and their links, for the chat line
local function ReadLoot(keep)
    local items, links = {}, {}
    for slot = 1, GetNumLootItems() do
        if LootSlotHasItem(slot) then
            local link = GetLootSlotLink(slot)
            local id = link and tonumber(link:match("item:(%d+)"))
            if id and (not keep or keep[id]) then
                local _, _, qty = GetLootSlotInfo(slot)
                qty = qty or 1
                items[id] = (items[id] or 0) + qty
                links[#links + 1] = qty > 1 and (link .. " x" .. qty) or link
            end
        end
    end
    return items, links
end

local function Record(prof, source, items, links, who)
    local mapID, x, y = PlayerPosition()
    FN.Add(prof, mapID, {
        x = x, y = y, time = time(), npc = source or 0, char = FN.CharIndex(),
        skill = PROFS[prof] and FN.ProfessionSkill(prof) or 0, items = items,
    })
    if FN.SessionGather then
        FN.SessionGather(prof, source, items)
    elseif prof == "skinning" and FN.SessionAdd then
        FN.SessionAdd(source, items)
    end
    if FN.db.settings.chat and #links > 0 then
        FN.Print((who or "") .. "  " .. table.concat(links, ", "))
    end
end

-- Skinning, Mining or Herbalism, from the cast that was pending
local function RecordCast(cast)
    local items, links = ReadLoot()
    if not next(items) then return end
    local guid, kind = LootSource()
    if cast.prof == "skinning" then
        guid = (kind == "creature" and guid) or cast.guid
        local npc = NpcFromGUID(guid)
        local info = guid and seen[guid]
        FN.NoteCreature(npc, info, cast.name)
        Record("skinning", npc, items, links, (info and info.name) or cast.name or "Unknown creature")
    else
        local node = kind == "node" and IdFromGUID(guid, "GameObject") or nil
        FN.NoteNode(node, cast.name)
        Record(cast.prof, node, items, links, cast.name or "")
    end
end

local function RecordFishing()
    local items, links = ReadLoot()
    if not next(items) then return end
    Record("fishing", 0, items, links, spellName.fishing or "Fishing")
end

-- an ordinary kill's loot: counts for Cloth when the creature is a humanoid or has dropped cloth
local looted, lootedCount = {}, 0
local function RecordKill(guid)
    local npc = NpcFromGUID(guid)
    if not npc or looted[guid] then return end
    local items, links = ReadLoot(CLOTH)
    local info = seen[guid]
    local known = FN.db.creatures[npc]
    local humanoid = (info and info.type == FN.HUMANOID) or (known and (known.type == FN.HUMANOID or known.cloth))
    if not humanoid and not next(items) then return end
    looted[guid] = true
    lootedCount = lootedCount + 1
    if lootedCount > 300 then
        wipe(looted)
        lootedCount = 0
    end
    local c = FN.NoteCreature(npc, info)
    if c and next(items) then c.cloth = true end
    Record("cloth", npc, items, links, (info and info.name) or (c and c.name) or "")
end

-- a treasure: its loot, when the window comes from a chest (see the top). opening: the Opening
-- cast that came before it, { name, cast, sent }
local opening
local function RecordTreasure(guid)
    local id = IdFromGUID(guid, "GameObject")
    if not id or looted[guid] then return end
    local name = opening and GetTime() - opening.sent < 10 and opening.name or nil
    opening = nil
    local money = false
    for slot = 1, GetNumLootItems() do
        if not LootSlotHasItem(slot) then money = true end
    end
    local chest = money
    local lower = name and name:lower()
    if lower then
        for _, w in ipairs(CHEST_WORDS) do
            if lower:find(w, 1, true) then chest = true end
        end
    end
    if not chest then return end
    looted[guid] = true
    lootedCount = lootedCount + 1
    local items, links = ReadLoot()
    FN.NoteNode(id, name)
    Record("treasure", id, items, links, name or "Treasure")
end

-- the loot window open now (or last): its source, for the coin it gives
local lootFrom -- { id, at }

-- "You loot 2 Silver, 14 Copper" -> 214. The coin words come from the game's own strings, so this
-- reads every language; a word with grammatical forms (|4one:few:many;) matches any of them.
local function CoinPattern(fmt, fallback)
    fmt = type(fmt) == "string" and fmt or fallback
    local p = fmt:gsub("|4[^;]*;", "\1"):gsub("%%d", "\2"):gsub("([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1")
    return (p:gsub("\1", "%%S+"):gsub("\2", "(%%d+)"))
end
local COINS -- { pattern, copper each }, built on first use (the strings load with the game)
function FN.ParseMoney(msg)
    if type(msg) ~= "string" then return 0 end
    COINS = COINS or {
        { CoinPattern(_G.GOLD_AMOUNT, "%d Gold"), 10000 },
        { CoinPattern(_G.SILVER_AMOUNT, "%d Silver"), 100 },
        { CoinPattern(_G.COPPER_AMOUNT, "%d Copper"), 1 },
    }
    local total = 0
    for _, c in ipairs(COINS) do
        local n = msg:match(c[1])
        if n then total = total + tonumber(n) * c[2] end
    end
    return total
end

-- only the game's loot lines carry coin you gathered (not, say, a quest's reward)
local function LineMatcher(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("%%s", "\1"):gsub("([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1")
    return "^" .. (p:gsub("\1", ".+"))
end
local MONEY_LINES
local function IsLootMoney(msg)
    MONEY_LINES = MONEY_LINES or {}
    if not MONEY_LINES.built then
        MONEY_LINES.built = true
        for _, g in ipairs({ "YOU_LOOT_MONEY", "LOOT_MONEY_SPLIT", "YOU_LOOT_MONEY_GUILD", "LOOT_MONEY_SPLIT_GUILD" }) do
            local m = LineMatcher(_G[g])
            if m then MONEY_LINES[#MONEY_LINES + 1] = m end
        end
    end
    if #MONEY_LINES == 0 then return true end -- a client without them: trust the event
    for _, m in ipairs(MONEY_LINES) do
        if msg:find(m) then return true end
    end
    return false
end

local function RecordMoney(msg)
    if not IsLootMoney(msg) then return end
    local copper = FN.ParseMoney(msg)
    if copper <= 0 then return end
    local source = lootFrom and GetTime() - lootFrom.at < 30 and lootFrom.id or 0
    Record("money", source, { [FN.COIN] = copper }, {})
end

local pending -- { prof, cast, name, guid, sent }
local fishingAt -- GetTime() of the last Fishing cast, for clients without IsFishingLoot
local pickAt = 0
local lastLootAt = 0

local f = CreateFrame("Frame")
local function On(event)
    pcall(f.RegisterEvent, f, event) -- skip events a client lacks
end
On("UNIT_SPELLCAST_SENT")
On("UNIT_SPELLCAST_FAILED")
On("UNIT_SPELLCAST_INTERRUPTED")
On("UPDATE_MOUSEOVER_UNIT")
On("PLAYER_TARGET_CHANGED")
On("LOOT_READY")
On("LOOT_OPENED")
On("LOOT_CLOSED")
On("CHAT_MSG_MONEY")

local function OnLoot()
    -- both loot events can fire for one loot window: take the first
    local now = GetTime()
    if now - lastLootAt < 0.5 then return end
    lastLootAt = now
    do -- the source of any coin this window gives
        local guid, kind = LootSource()
        local id = guid and (kind == "creature" and NpcFromGUID(guid) or IdFromGUID(guid, "GameObject"))
        if id and kind == "node" then FN.NoteNode(id) end
        lootFrom = { id = id or 0, at = now }
    end
    if pending and now - pending.sent > (PROFS[pending.prof].window or 6) then pending = nil end
    if pending then
        local cast = pending
        pending = nil
        RecordCast(cast)
        return
    end
    if now - pickAt < 3 then return end
    local guid, kind = LootSource()
    local fishing = IsFishingLoot and IsFishingLoot()
    if not IsFishingLoot then
        fishing = fishingAt and now - fishingAt < PROFS.fishing.window and kind ~= "creature"
    end
    if fishing then
        fishingAt = nil
        RecordFishing()
    elseif kind == "creature" then
        RecordKill(guid)
    elseif kind == "node" then
        RecordTreasure(guid)
    end
end

f:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
    if not FN.db then return end
    if event == "UPDATE_MOUSEOVER_UNIT" then
        Remember("mouseover")
    elseif event == "PLAYER_TARGET_CHANGED" then
        Remember("target")
    elseif event == "UNIT_SPELLCAST_SENT" then
        -- unit, target name, cast GUID, spell ID
        if a1 ~= "player" then return end
        if IsPickPocket(a4) then
            pickAt = GetTime()
            return
        end
        if IsOpening(a4) then
            opening = { name = a2 ~= "" and a2 or nil, cast = a3, sent = GetTime() }
            return
        end
        local prof = ProfOfSpell(a4)
        if not prof then return end
        if prof == "fishing" then
            fishingAt = GetTime()
            return
        end
        local guid
        if prof == "skinning" then
            Remember("mouseover")
            Remember("target")
            for _, unit in ipairs({ "mouseover", "target" }) do
                if not guid and UnitExists(unit) and UnitIsDead(unit) and UnitName(unit) == a2 then
                    guid = UnitGUID(unit)
                end
            end
        end
        pending = { prof = prof, cast = a3, name = a2 ~= "" and a2 or nil, guid = guid, sent = GetTime() }
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        -- unit, cast GUID, spell ID
        if a1 == "player" and pending and a2 == pending.cast then pending = nil end
        if a1 == "player" and opening and a2 == opening.cast then opening = nil end
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        OnLoot()
    elseif event == "LOOT_CLOSED" then
        lastLootAt = 0
    elseif event == "CHAT_MSG_MONEY" then
        RecordMoney(a1)
    end
end)

table.insert(FN.onLogin, function()
    for prof, p in pairs(PROFS) do spellName[prof] = SpellName(p.spells[1]) end
    pickName = SpellName(PICK_POCKET)
    openName = SpellName(3365)
end)

-- the game's word for humanoid creatures (UnitCreatureType is in the client's language)
FN.HUMANOID = ({
    deDE = "Humanoid", frFR = "Humanoïde", esES = "Humanoide", esMX = "Humanoide",
    ptBR = "Humanoide", itIT = "Umanoide", ruRU = "Гуманоид", koKR = "인간형", zhCN = "人型生物", zhTW = "人型生物",
})[GetLocale and GetLocale() or "enUS"] or "Humanoid"
