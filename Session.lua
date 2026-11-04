local ADDON, FN = ...

-- The session tracker: a small panel you can drag anywhere. It appears with your first skin,
-- counts the session as you go (skins, skins per minute, ruined, a bar per minute, the loot)
-- and hides itself after two minutes without a skin. Five quiet minutes end the session; the
-- next skin starts a new one. Pause stops the clock (a break does not lower your rate).

local St = FN.Style
local C = St.C

local RUINED = 2934
local IDLE = 300 -- seconds without a skin that end a session
local FADE = 120 -- seconds without a skin before the tracker hides
local SPARK = 24 -- minutes in the tracker's bar chart
local LOOT_ROWS = 4

local session = { count = 0, ruined = 0, loot = {}, creatures = {}, minutes = {}, paused = 0 }
FN.session = session

-- seconds of skinning so far, leaving out pauses
local function Active()
    if not session.start then return 0 end
    local stop = session.pausedAt or GetTime()
    return math.max(0, stop - session.start - session.paused)
end
FN.SessionSeconds = Active

local function Reset(now)
    session.count, session.ruined, session.paused = 0, 0, 0
    session.start, session.last, session.pausedAt = now, nil, nil
    wipe(session.loot)
    wipe(session.creatures)
    wipe(session.minutes)
end

-- skins per minute, counting at least one minute so the first skin reads as 1.0, not a spike
function FN.SessionRate()
    if session.count == 0 then return 0 end
    return session.count / math.max(1, Active() / 60)
end

-- leather per hour this session (Ruined Leather Scraps left out)
function FN.SessionLeatherRate()
    if session.count == 0 then return 0 end
    local n = 0
    for id, k in pairs(session.loot) do
        if id ~= RUINED then n = n + k end
    end
    return n / math.max(1 / 60, Active() / 3600)
end

-- Start, pause and end, for the tracker's buttons and the map's session controls
function FN.SessionRunning() return session.start ~= nil end
function FN.SessionPaused() return session.pausedAt ~= nil end

function FN.SessionStart()
    local now = GetTime()
    Reset(now)
    session.last = now -- a session started by hand is not idle yet
    FN.ShowTracker()
end

function FN.SessionTogglePause()
    if not session.start then return end
    local now = GetTime()
    if session.pausedAt then
        session.paused = session.paused + (now - session.pausedAt)
        session.pausedAt = nil
        session.last = now -- a resumed session is not idle
    else
        session.pausedAt = now
    end
    FN.UpdateTracker()
end

function FN.SessionEnd()
    Reset(nil)
    session.start = nil
    FN.HideTracker()
end

-- ------------------------------------------------------------
-- The panel
-- ------------------------------------------------------------
local frame, ui = nil, {}

local function Build()
    frame = St.Frame("Frame", UIParent)
    frame:SetSize(232, 200)
    frame:SetFrameStrata("MEDIUM")
    St.Etch(frame, St.STYLE.panel, 12, 0.94)
    St.Movable(frame, "trackerPos")
    St.PlaceSaved(frame, "trackerPos", "RIGHT", "RIGHT", -60, 120)
    frame:Hide()

    ui.dot = frame:CreateTexture(nil, "ARTWORK")
    ui.dot:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    ui.dot:SetSize(8, 8)
    ui.dot:SetPoint("TOPLEFT", 14, -16)
    ui.title = St.Title(frame, 12)
    ui.title:SetPoint("LEFT", ui.dot, "RIGHT", 7, 0)
    ui.title:SetText("Skinning")
    ui.clock = St.Text(frame, 11, C.INK2)
    ui.clock:SetPoint("TOPRIGHT", -14, -14)
    ui.clock:SetJustifyH("RIGHT")

    ui.stats = {}
    for i, label in ipairs({ "skins", "per minute", "ruined" }) do
        local v = St.Text(frame, 18, C.TEXT)
        v:SetPoint("TOPLEFT", 14 + (i - 1) * 70, -34)
        local l = St.Text(frame, 10, C.SUBTEXT)
        l:SetPoint("TOPLEFT", v, "BOTTOMLEFT", 0, -2)
        l:SetText(label)
        ui.stats[i] = v
    end

    -- one bar per minute, the newest on the right
    ui.bars = {}
    local gap, w = 2, (232 - 28 - (SPARK - 1) * 2) / SPARK
    for i = 1, SPARK do
        local t = frame:CreateTexture(nil, "ARTWORK")
        t:SetTexture(St.SOLID)
        t:SetWidth(w)
        t:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 14 + (i - 1) * (w + gap), -100)
        ui.bars[i] = t
    end

    ui.rule = frame:CreateTexture(nil, "ARTWORK")
    ui.rule:SetColorTexture(0.33, 0.29, 0.20, 0.8)
    ui.rule:SetHeight(1)
    ui.rule:SetPoint("TOPLEFT", 14, -108)
    ui.rule:SetPoint("TOPRIGHT", -14, -108)

    ui.loot = {}
    for i = 1, LOOT_ROWS do
        local row = {}
        row.icon = frame:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("TOPLEFT", 14, -116 - (i - 1) * 20)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.name = St.Text(frame, 11, C.TEXT)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.count = St.Text(frame, 11, C.TITLE)
        row.count:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
        row.count:SetPoint("TOP", row.icon, "TOP", 0, -2)
        row.count:SetJustifyH("RIGHT")
        ui.loot[i] = row
    end

    ui.pause = St.ChoiceButton(frame, function() FN.SessionTogglePause() end)
    ui.finish = St.ChoiceButton(frame, function() FN.SessionEnd() end)
    ui.finish.text:SetText("End session")
    ui.finish:SetChosen(true)
    ui.finish:SetScript("OnLeave", function(self) self:SetChosen(true) end)

    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 1 then return end
        elapsed = 0
        if not session.pausedAt and session.last and GetTime() - session.last > FADE then
            frame:Hide()
            return
        end
        FN.UpdateTracker()
    end)
end

function FN.UpdateTracker()
    if not frame or not frame:IsShown() then return end
    local secs = Active()
    ui.clock:SetText(string.format("%d:%02d", math.floor(secs / 60), math.floor(secs % 60)))
    local paused = session.pausedAt ~= nil
    if paused then
        ui.dot:SetVertexColor(C.SUBTEXT[1], C.SUBTEXT[2], C.SUBTEXT[3])
    else
        ui.dot:SetVertexColor(0.31, 0.75, 0.23) -- Forever Goal Tracker's done green
    end
    ui.title:SetText(paused and "Paused" or "Skinning")
    ui.stats[1]:SetText(session.count)
    ui.stats[2]:SetText(string.format("%.1f", FN.SessionRate()))
    ui.stats[3]:SetText(session.count > 0 and (math.floor(session.ruined / session.count * 100 + 0.5) .. "%") or "-")

    local nowMinute = math.floor(secs / 60) + 1
    local peak = 1
    for m = nowMinute - SPARK + 1, nowMinute do peak = math.max(peak, session.minutes[m] or 0) end
    for i, t in ipairs(ui.bars) do
        local n = session.minutes[nowMinute - SPARK + i] or 0
        t:SetHeight(math.max(2, 34 * n / peak))
        if n > 0 then
            St.VGradient(t, { 1.00, 0.86, 0.30 }, { 0.62, 0.42, 0.05 })
        else
            t:SetVertexColor(1, 0.94, 0.82, 0.10)
        end
    end

    local ids = {}
    for id in pairs(session.loot) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        if (a == RUINED) ~= (b == RUINED) then return b == RUINED end -- scraps last
        if session.loot[a] ~= session.loot[b] then return session.loot[a] > session.loot[b] end
        return a < b
    end)
    for i, row in ipairs(ui.loot) do
        local id = ids[i]
        if id then
            local name = GetItemInfo(id)
            row.icon:SetTexture(GetItemIcon and GetItemIcon(id) or nil)
            row.name:SetText(name or "...")
            row.count:SetText("x " .. session.loot[id])
        end
        row.icon:SetShown(id ~= nil)
        row.name:SetShown(id ~= nil)
        row.count:SetShown(id ~= nil)
    end
    local shown = math.min(#ids, LOOT_ROWS)
    local y = -116 - shown * 20 - 6
    ui.pause.text:SetText(paused and "Resume" or "Pause")
    ui.pause:SetChosen(false)
    ui.pause:ClearAllPoints()
    ui.pause:SetPoint("TOPLEFT", 14, y)
    ui.pause:SetWidth(98)
    ui.finish:ClearAllPoints()
    ui.finish:SetPoint("TOPRIGHT", -14, y)
    ui.finish:SetWidth(98)
    frame:SetHeight(-y + 22 + 14)
end

function FN.ShowTracker()
    if FN.db.settings.tracker == false then return end
    if not frame then Build() end
    frame:Show()
    FN.UpdateTracker()
end

function FN.HideTracker()
    if frame then frame:Hide() end
end

function FN.SessionAdd(npc, items)
    local now = GetTime()
    if session.pausedAt then -- a skin while paused carries on the session
        session.paused = session.paused + (now - session.pausedAt)
        session.pausedAt = nil
    end
    if not session.start or not session.last or now - session.last > IDLE then Reset(now) end
    session.count = session.count + 1
    session.last = now
    if items[RUINED] then session.ruined = session.ruined + 1 end
    for id, n in pairs(items) do session.loot[id] = (session.loot[id] or 0) + n end
    if npc and npc > 0 then session.creatures[npc] = (session.creatures[npc] or 0) + 1 end
    local m = math.floor(Active() / 60) + 1
    session.minutes[m] = (session.minutes[m] or 0) + 1
    FN.ShowTracker()
end

local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "GET_ITEM_INFO_RECEIVED") -- loot names arriving after a skin
ev:SetScript("OnEvent", function() FN.UpdateTracker() end)
