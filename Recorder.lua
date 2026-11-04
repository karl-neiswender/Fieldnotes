local ADDON, FN = ...

-- Skinning detection.
--
-- A skin is a Skinning cast on a corpse followed by the loot window. The cast is noted when it
-- is sent (with the corpse's name), cleared if it fails, and the next loot window within a few
-- seconds is taken as the skin. Loot without a Skinning cast before it (an ordinary kill) is
-- never counted.

-- Skinning's ranks (Apprentice to Artisan); the spell's own name also counts, for other ranks
local SKINNING_SPELLS = { [8613] = true, [8617] = true, [8618] = true, [10768] = true }
local WINDOW = 6 -- seconds from sending the cast to the loot window
local skinName

local pending -- { cast, name, guid, sent }
local lastLootAt = 0

local function IsSkinning(spellID)
    if SKINNING_SPELLS[spellID] then return true end
    if not skinName or not spellID then return false end
    return (GetSpellInfo(spellID)) == skinName
end

-- "Creature-0-1234-0-56-2522-0000ABCD" -> 2522
local function NpcFromGUID(guid)
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, npc = strsplit("-", guid)
    if kind == "Creature" then return tonumber(npc) end
end
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

-- the skinning rank, and the most the current rank allows (75 for Apprentice, and so on)
local function SkinningSkill()
    if not skinName or not GetNumSkillLines then return 0 end
    for i = 1, GetNumSkillLines() do
        local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
        if not isHeader and name == skinName then return rank or 0, maxRank end
    end
    return 0
end

FN.SkinningSkill = SkinningSkill

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

local function LootSourceGUID()
    if not GetLootSourceInfo then return nil end
    for slot = 1, GetNumLootItems() do
        local guid = GetLootSourceInfo(slot)
        if NpcFromGUID(guid) then return guid end
    end
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
end

local function RecordSkin(cast)
    local items, links = {}, {}
    for slot = 1, GetNumLootItems() do
        if LootSlotHasItem(slot) then
            local link = GetLootSlotLink(slot)
            local id = link and tonumber(link:match("item:(%d+)"))
            if id then
                local _, _, qty = GetLootSlotInfo(slot)
                qty = qty or 1
                items[id] = (items[id] or 0) + qty
                links[#links + 1] = qty > 1 and (link .. " x" .. qty) or link
            end
        end
    end
    if not next(items) then return end

    local guid = LootSourceGUID() or cast.guid
    local npc = NpcFromGUID(guid)
    local info = guid and seen[guid]
    FN.NoteCreature(npc, info, cast.name)

    local mapID, x, y = PlayerPosition()
    FN.Add("skinning", mapID, {
        x = x, y = y, time = time(), npc = npc or 0, char = FN.CharIndex(),
        skill = SkinningSkill(), items = items,
    })
    if FN.SessionAdd then FN.SessionAdd(npc, items) end

    if FN.db.settings.chat then
        local who = (info and info.name) or cast.name or "Unknown creature"
        FN.Print(who .. "  " .. table.concat(links, ", "))
    end
end

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

f:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
    if not FN.db then return end
    if event == "UPDATE_MOUSEOVER_UNIT" then
        Remember("mouseover")
    elseif event == "PLAYER_TARGET_CHANGED" then
        Remember("target")
    elseif event == "UNIT_SPELLCAST_SENT" then
        -- unit, target name, cast GUID, spell ID
        if a1 ~= "player" or not IsSkinning(a4) then return end
        Remember("mouseover")
        Remember("target")
        local guid
        for _, unit in ipairs({ "mouseover", "target" }) do
            if not guid and UnitExists(unit) and UnitIsDead(unit) and UnitName(unit) == a2 then
                guid = UnitGUID(unit)
            end
        end
        pending = { cast = a3, name = a2 ~= "" and a2 or nil, guid = guid, sent = GetTime() }
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        -- unit, cast GUID, spell ID
        if a1 == "player" and pending and a2 == pending.cast then pending = nil end
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        -- both can fire for one loot window: take the first
        if not pending or GetTime() - lastLootAt < 0.5 then return end
        if GetTime() - pending.sent > WINDOW then
            pending = nil
            return
        end
        lastLootAt = GetTime()
        local cast = pending
        pending = nil
        RecordSkin(cast)
    elseif event == "LOOT_CLOSED" then
        lastLootAt = 0
    end
end)

table.insert(FN.onLogin, function()
    skinName = GetSpellInfo(8613)
end)
