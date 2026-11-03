local ADDON, FN = ...

local RUINED = 2934 -- Ruined Leather Scraps
local IDLE = 300 -- seconds without a skin that end a session

-- ------------------------------------------------------------
-- Session: from your first skin until five quiet minutes
-- ------------------------------------------------------------
local session = { count = 0, ruined = 0, loot = {}, creatures = {} }

function FN.SessionAdd(npc, items)
    local now = GetTime()
    if not session.last or now - session.last > IDLE then
        session.count, session.ruined, session.start = 0, 0, now
        wipe(session.loot)
        wipe(session.creatures)
    end
    session.count = session.count + 1
    session.last = now
    if items[RUINED] then session.ruined = session.ruined + 1 end
    for id, n in pairs(items) do session.loot[id] = (session.loot[id] or 0) + n end
    if npc and npc > 0 then session.creatures[npc] = (session.creatures[npc] or 0) + 1 end
end

-- skins per minute, counting at least one minute so the first skin reads as 1.0, not a spike
function FN.SessionRate()
    if session.count == 0 then return 0 end
    local minutes = math.max(1, (session.last - session.start) / 60)
    return session.count / minutes
end

-- ------------------------------------------------------------
-- Words and numbers
-- ------------------------------------------------------------
local function ItemText(id)
    local _, link = GetItemInfo(id)
    return link or ("item " .. id)
end

local function CreatureText(npc)
    local c = FN.View().creatures[npc]
    return (c and c.name) or ("creature " .. npc)
end

local function Top(counts, n, label)
    local keys = {}
    for k in pairs(counts) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return counts[a] > counts[b] end)
    local out = {}
    for i = 1, math.min(n, #keys) do out[i] = label(keys[i]) .. " " .. counts[keys[i]] end
    return #out > 0 and table.concat(out, ", ") or "none yet"
end

local function ZoneName(mapID)
    local info = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return (info and info.name) or GetZoneText() or "this zone"
end

-- ------------------------------------------------------------
-- /fn
-- ------------------------------------------------------------
-- true when the game has not loaded an item's name yet; asking (GetItemInfo) starts the load
local function AnyUncached(ids)
    local missing = false
    for id in pairs(ids) do
        if not GetItemInfo(id) then missing = true end
    end
    return missing
end

local function Summary(retried)
    local view = FN.View()
    local byMap = view.events.skinning or {}
    local me = FN.ViewChar()
    local total, mine = 0, 0
    for _, list in pairs(byMap) do
        total = total + #list
        for _, s in ipairs(list) do
            if s:match("^%d*:%d*:%d+:%d+:(%d+):") == tostring(me) then mine = mine + 1 end
        end
    end

    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local here, who, loot, ruined = byMap[mapID or 0] or {}, {}, {}, 0
    for _, s in ipairs(here) do
        local r = FN.Decode(s)
        if r then
            if r.npc > 0 then who[r.npc] = (who[r.npc] or 0) + 1 end
            for id, n in pairs(r.items) do
                if id == RUINED then ruined = ruined + 1 else loot[id] = (loot[id] or 0) + n end
            end
        end
    end

    -- item names not loaded yet would print as "item 2318": wait a moment for them, once
    if not retried and C_Timer and AnyUncached(loot) then
        C_Timer.After(1, function() Summary(true) end)
        return
    end

    if view ~= FN.db then FN.Print("Demo mode: showing sample data. /fn demo off to go back.") end
    FN.Print(string.format("%d skins on this account, %d by this character.", total, mine))
    if session.count > 0 then
        FN.Print(string.format("This session: %d skins, %.1f per minute, %d%% ruined.",
            session.count, FN.SessionRate(), math.floor(session.ruined / session.count * 100 + 0.5)))
    end
    if #here > 0 then
        FN.Print(string.format("%s: %d skins, %d%% ruined.", ZoneName(mapID), #here,
            math.floor(ruined / #here * 100 + 0.5)))
        FN.Print("  Creatures: " .. Top(who, 3, CreatureText))
        FN.Print("  Leather: " .. Top(loot, 3, ItemText))
    else
        FN.Print(ZoneName(mapID) .. ": nothing skinned here yet.")
    end
end

SLASH_FIELDNOTES1 = "/fn"
SLASH_FIELDNOTES2 = "/fieldnotes"
SlashCmdList.FIELDNOTES = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" then
        Summary()
    elseif msg == "chat" then
        FN.db.settings.chat = not FN.db.settings.chat
        FN.Print("A chat line for each skin is now " .. (FN.db.settings.chat and "on." or "off."))
    elseif msg == "demo" then
        FN.DemoLoad()
        Summary()
    elseif msg == "demo off" then
        FN.DemoClear()
    elseif msg == "fake" then
        FN.DemoFakeSkin()
    else
        FN.Print("/fn  your skinning so far, this session and this zone")
        FN.Print("/fn chat  turn the chat line for each skin on or off")
        FN.Print("/fn demo  load sample data to try Fieldnotes (your own records stay as they are)")
        FN.Print("/fn fake  pretend to skin something where you stand (demo mode only)")
        FN.Print("/fn demo off  remove the sample data")
    end
end
