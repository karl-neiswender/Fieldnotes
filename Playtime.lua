local ADDON, FN = ...

-- Playtime: how long each character on this account plays, for the Time page (TimePage.lua,
-- design/time-2026-11-17/Playtime-v4.html, approved by Karl 2026-11-17). Local only, never shared.
--
-- FieldnotesDB.playtime = {
--   roster   { [char] = { class = "HUNTER", level = 60, copper = carried at last look,
--                         played = /played seconds, pre = /played from before Fieldnotes kept time } }
--   days     { [YYYYMMDD] = { [char] = { p = { [hour] = seconds }, a = { [hour] = AFK seconds } } } }
--   sessions { "char:start:seconds:afk:lastSeen", ... }   one per log in; a /reload carries on
-- }
-- char is the character's position in FieldnotesDB.chars, as in the gathering records.
-- Time counts from log in to log out. AFK time (by /afk or the game's idle timer) is kept apart,
-- so the page can leave it out (the default) or count it.

local PT = {}
FN.Playtime = PT

local TICK = 15        -- seconds between counts
local RELOAD = 120     -- a log in this soon after the last one was seen carries that session on
local Date = date or (os and os.date)

local cur              -- this log in's session: { i = index in sessions, char, start, secs, afk }
local last             -- GetTime() at the last count
local away = false     -- AFK since the last count

function PT.Store()
    local db = FN.db
    db.playtime = db.playtime or {}
    local p = db.playtime
    p.roster = p.roster or {}
    p.days = p.days or {}
    p.sessions = p.sessions or {}
    return p
end

-- "char:start:secs:afk:last" <-> numbers
function PT.DecodeSession(s)
    local c, start, secs, afk, seen = s:match("^(%d+):(%d+):(%d+):(%d+):(%d+)$")
    if not c then return end
    return tonumber(c), tonumber(start), tonumber(secs), tonumber(afk), tonumber(seen)
end
local function EncodeSession(c, start, secs, afk, seen)
    return string.format("%d:%d:%d:%d:%d", c, start, math.floor(secs + 0.5), math.floor(afk + 0.5), seen)
end

-- everything counted for a character so far, AFK included (for /played's earlier part)
local function Tracked(char)
    local total = 0
    for _, chars in pairs(PT.Store().days) do
        local e = chars[char]
        if e then
            for _, v in pairs(e.p or {}) do total = total + v end
            for _, v in pairs(e.a or {}) do total = total + v end
        end
    end
    return total
end

-- add the time since the last count to this hour of today, under the AFK state it was spent in
local function Count()
    if not cur or not GetTime then return end
    local now = GetTime()
    local dt = last and (now - last) or 0
    last = now
    if dt <= 0 then return end
    dt = math.min(dt, TICK * 8) -- (a long hitch or loading screen counts a little, not all of it)
    local t = Date and Date("*t", time())
    if type(t) ~= "table" then return end
    local key = t.year * 10000 + t.month * 100 + t.day
    local days = PT.Store().days
    days[key] = days[key] or {}
    local e = days[key][cur.char]
    if not e then
        e = { p = {}, a = {} }
        days[key][cur.char] = e
    end
    local bucket = away and e.a or e.p
    bucket[t.hour] = (bucket[t.hour] or 0) + dt
    if away then cur.afk = cur.afk + dt else cur.secs = cur.secs + dt end
    PT.Store().sessions[cur.i] = EncodeSession(cur.char, cur.start, cur.secs, cur.afk, time())
end
PT.Count = Count

-- this character's class, level and carried coin (only the logged-in character can be asked)
local function Roster()
    local char = FN.CharIndex()
    local r = PT.Store().roster[char] or {}
    PT.Store().roster[char] = r
    if UnitClass then
        local _, class = UnitClass("player")
        r.class = class or r.class
    end
    if UnitLevel then
        local level = UnitLevel("player")
        if level and level > 0 then r.level = level end
    end
    if GetMoney then r.copper = GetMoney() end
    return r
end

-- /played, asked quietly at log in: the game's chat line is held back for our own ask only
local quiet = false
local held
local function Unquiet()
    if held then
        ChatFrame_DisplayTimePlayed = held
        held = nil
    end
    quiet = false
end
local function AskPlayed()
    if not RequestTimePlayed then return end
    if type(ChatFrame_DisplayTimePlayed) == "function" and not held then
        held = ChatFrame_DisplayTimePlayed
        ChatFrame_DisplayTimePlayed = function() end
        quiet = true
        if C_Timer then C_Timer.After(10, Unquiet) end
    end
    RequestTimePlayed()
end

local function Start()
    local store = PT.Store()
    local char = FN.CharIndex()
    local now = time()
    -- a /reload: the last session of this character, seen moments ago, carries on
    for i = #store.sessions, 1, -1 do
        local c, start, secs, afk, seen = PT.DecodeSession(store.sessions[i])
        if c == char then
            if seen and now - seen <= RELOAD then cur = { i = i, char = char, start = start, secs = secs, afk = afk } end
            break
        end
    end
    if not cur then
        cur = { i = #store.sessions + 1, char = char, start = now, secs = 0, afk = 0 }
        store.sessions[cur.i] = EncodeSession(char, now, 0, 0, now)
    end
    last = GetTime and GetTime() or nil
    away = UnitIsAFK and UnitIsAFK("player") and true or false
    Roster()
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(TICK, Count) end
    if C_Timer then C_Timer.After(3, AskPlayed) else AskPlayed() end
end
table.insert(FN.onLogin, Start)

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGOUT", "PLAYER_FLAGS_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_MONEY", "TIME_PLAYED_MSG" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, a1)
    if not FN.db or not cur then return end
    if event == "PLAYER_FLAGS_CHANGED" then
        -- the time since the last count was spent in the old state
        Count()
        away = UnitIsAFK and UnitIsAFK("player") and true or false
    elseif event == "PLAYER_LOGOUT" then
        Count()
        Roster()
    elseif event == "PLAYER_LEVEL_UP" then
        local r = Roster()
        if type(a1) == "number" then r.level = a1 end
    elseif event == "PLAYER_MONEY" then
        Roster()
    elseif event == "TIME_PLAYED_MSG" then
        local total = tonumber(a1)
        if total then
            local r = Roster()
            r.played = total
            -- what /played had before Fieldnotes kept time: worked out once, the first time asked
            if not r.pre then r.pre = math.max(0, total - Tracked(cur.char)) end
        end
        -- (the chat frame may hear it after us: give it a moment before the line comes back)
        if quiet then
            if C_Timer then C_Timer.After(0.5, Unquiet) else Unquiet() end
        end
    end
end)
