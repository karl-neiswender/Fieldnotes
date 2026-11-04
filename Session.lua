local ADDON, FN = ...

-- The session tracker: a small panel you can drag anywhere. One session, one clock, for every
-- profession (professions v4 mockup, 2026-11-04): a row appears the first time you gather
-- something of a profession this session, with its count, per hour on the shared clock, and
-- your skill and what this session added (Cloth: how often humanoids dropped it). Then the
-- session's top loot. It appears with your first gather and hides after two minutes without one;
-- five quiet minutes end the session. Pause stops the clock. The chevron folds it to one line:
-- the clock, then each profession's initial and count. When a skill reaches its rank's cap, it
-- says so, once in chat and on screen: time to see a trainer.

local St = FN.Style
local C = St.C

local RUINED = 2934
local IDLE = 300 -- seconds without a skin that end a session
local FADE = 120 -- seconds without a skin before the tracker hides
local LOOT_ROWS = 4

-- count, ruined, loot, creatures: skinning's (the stats window reads them); total and allLoot:
-- every profession's; profs[key] = { count, loots, skillStart }, in order of first gather
local session = { count = 0, ruined = 0, loot = {}, creatures = {}, minutes = {}, paused = 0,
    total = 0, allLoot = {}, profs = {}, order = {} }
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
    session.skillStart = FN.SkinningSkill and FN.SkinningSkill() or nil
    session.total = 0
    wipe(session.loot)
    wipe(session.creatures)
    wipe(session.minutes)
    wipe(session.allLoot)
    wipe(session.profs)
    wipe(session.order)
end

function FN.SessionHas(prof) return session.start ~= nil and session.profs[prof] ~= nil end

local function ProfInfo(key)
    return FN.Map and FN.Map.PROF and FN.Map.PROF[key] or { key = key, label = key, unit = "gather", units = "gathers",
        color = { 0.8, 0.8, 0.8 } }
end

-- "34 skins" while you only skin, else "43 gathers": the dock's session row and the toolbar
function FN.SessionLabel()
    local n = session.total or 0
    if #session.order == 1 then
        local p = ProfInfo(session.order[1])
        return n .. " " .. (n == 1 and p.unit or p.units)
    end
    return n .. (n == 1 and " gather" or " gathers")
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
-- Skill: your rank, its cap, and the trainer alert
-- ------------------------------------------------------------
-- the rank a trainer teaches next, by the cap you are at (Classic's ranks, the same for every
-- gathering profession)
local NEXT_RANK = { [75] = "Journeyman", [150] = "Expert", [225] = "Artisan" }
local TOP_CAP = 300
local ORANGE = { 1.00, 0.55, 0.15 }
local SKILLED = { "skinning", "mining", "herbalism", "fishing" }

local function Skill(prof)
    prof = prof or "skinning"
    if not FN.ProfessionSkill then return nil end
    local rank, cap = FN.ProfessionSkill(prof)
    if type(rank) ~= "number" or rank <= 0 or type(cap) ~= "number" or cap <= 0 then return nil end
    return rank, cap
end

-- capped: at the top of your rank, short of the last one
local function Capped(rank, cap) return rank and cap and rank >= cap and cap < TOP_CAP end

-- the panel's note at the cap: short, one line
local function CapNote(cap)
    local warn = string.format("|T%s:12:12:0:0:64:64:0:64:0:64:255:140:38|t ", St.Icon("warning-white"))
    return warn .. "Capped  ·  train " .. (NEXT_RANK[cap] or "the next rank")
end

local function TrainerLine(prof, cap)
    local nextRank = NEXT_RANK[cap]
    local who = string.lower(ProfInfo(prof).label)
    return nextRank and ("Visit a " .. who .. " trainer to learn " .. nextRank .. ".")
        or ("Visit a " .. who .. " trainer to learn the next rank.")
end

-- once per profession and cap: a line in chat, the words across the screen and a sound
-- (skinning's caps keep their old keys, 75 and so on, so an alert already given stays given)
local function AlertIfCapped()
    FN.db.settings.capAlerted = FN.db.settings.capAlerted or {}
    for _, prof in ipairs(SKILLED) do
        local rank, cap = Skill(prof)
        if Capped(rank, cap) then
            local key = prof == "skinning" and cap or (prof .. cap)
            if not FN.db.settings.capAlerted[key] then
                FN.db.settings.capAlerted[key] = true
                local line = string.format("%s %d / %d: you're at your rank's cap. %s", ProfInfo(prof).label, rank, cap,
                    TrainerLine(prof, cap))
                FN.Print(line)
                if UIErrorsFrame and UIErrorsFrame.AddMessage then
                    UIErrorsFrame:AddMessage(line, ORANGE[1], ORANGE[2], ORANGE[3])
                end
                if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
            end
        end
    end
end

-- ------------------------------------------------------------
-- The panel
-- ------------------------------------------------------------
local frame, ui = nil, {}
local W, PADX = 232, 14

-- a button with an icon before its label (pause, play)
local function IconChoice(parent, onClick)
    local b = St.ChoiceButton(parent, onClick)
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetSize(9, 9)
    b.icon:SetPoint("RIGHT", b.text, "LEFT", -6, 0)
    local set = b.SetChosen
    function b:SetChosen(on)
        set(self, on)
        local c = on and C.TITLE or C.INK2
        self.icon:SetVertexColor(c[1], c[2], c[3])
    end
    b:SetChosen(false)
    return b
end

local function Compact() return FN.db.settings.trackerCompact == true end

-- the panel hangs from its top edge, so folding and growing move only its bottom (it was placed
-- by its middle, so both edges moved). Saved that way, it stays where it was left.
local function SetHeightFromTop(h)
    local point, _, relPoint = frame:GetPoint()
    local hung = point == "TOPLEFT" and relPoint == "BOTTOMLEFT"
    local left, top = frame:GetLeft(), frame:GetTop()
    -- never while it is being dragged (the mover owns its position), and only once
    if not frame.dragging and not hung and left and top then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        FN.db.settings.trackerPos = { "TOPLEFT", "BOTTOMLEFT", left, top }
    end
    frame:SetHeight(h)
end

local function Build()
    frame = St.Frame("Frame", UIParent)
    frame:SetSize(W, 200)
    frame:SetFrameStrata("MEDIUM")
    St.Etch(frame, St.STYLE.panel, 12, 0.94)
    St.Movable(frame, "trackerPos")
    frame:HookScript("OnDragStart", function(self) self.dragging = true end)
    frame:HookScript("OnDragStop", function(self) self.dragging = false end)
    St.PlaceSaved(frame, "trackerPos", "RIGHT", "RIGHT", -60, 120)
    frame:Hide()

    -- the header: the dot (glowing while you skin), the title, the clock and the fold chevron
    ui.dot = frame:CreateTexture(nil, "ARTWORK", nil, 2)
    ui.dot:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    ui.dot:SetSize(8, 8)
    ui.dot:SetPoint("TOPLEFT", PADX, -16)
    ui.glow = St.Glow(frame, ui.dot, { 0.31, 0.75, 0.23 }) -- breathes while the session runs
    ui.title = St.Title(frame, 12)
    ui.title:SetPoint("LEFT", ui.dot, "RIGHT", 7, 0)
    ui.title:SetText("Session")
    ui.fold = St.IconButton(frame, "chevron-white", 10, function()
        FN.db.settings.trackerCompact = not Compact()
        FN.UpdateTracker()
    end)
    ui.fold:SetPoint("TOPRIGHT", -PADX, -15)
    ui.fold:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(C.TITLE[1], C.TITLE[2], C.TITLE[3])
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(Compact() and "Show more" or "Show less", 1, 1, 1)
        GameTooltip:Show()
    end)
    ui.fold:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(C.INK2[1], C.INK2[2], C.INK2[3])
        GameTooltip:Hide()
    end)
    -- the clock sits with the status it describes; the controls hang from the right edge, so the
    -- clock's changing width never moves them (it nudged them every second, seen in game)
    ui.clock = St.Text(frame, 11, C.INK2)
    ui.clock:SetPoint("LEFT", ui.title, "RIGHT", 8, 0)

    -- folded: the header and the three numbers stay; pause and end become icons in the header,
    -- and at the skill cap one orange line keeps the trainer in view
    -- a stop square, not an X: it ends the session, it does not close the panel
    ui.minStop = St.IconButton(frame, "stop-white", 9, function() FN.SessionEnd() end)
    ui.minStop:SetPoint("RIGHT", ui.fold, "LEFT", -12, 0)
    ui.minPause = St.IconButton(frame, "pause-white", 10, function() FN.SessionTogglePause() end)
    ui.minPause:SetPoint("RIGHT", ui.minStop, "LEFT", -9, 0)
    local function IconTip(b, text)
        b:SetScript("OnEnter", function(self)
            self.icon:SetVertexColor(C.TITLE[1], C.TITLE[2], C.TITLE[3])
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(type(text) == "function" and text() or text, 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
            self.icon:SetVertexColor(C.INK2[1], C.INK2[2], C.INK2[3])
            GameTooltip:Hide()
        end)
    end
    IconTip(ui.minStop, "End session")
    IconTip(ui.minPause, function() return session.pausedAt and "Resume" or "Pause" end)
    ui.line = St.Text(frame, 10, ORANGE)
    ui.line:SetPoint("TOPLEFT", PADX, -72)
    ui.line:SetWidth(W - PADX * 2)
    ui.line:SetWordWrap(false)

    -- open: a row per profession gathered this session (made as needed, see Row below)
    ui.rows = {}
    ui.empty = St.Text(frame, 10, C.SUBTEXT)
    ui.empty:SetText("Gather anything to start counting.")

    ui.rule = frame:CreateTexture(nil, "ARTWORK")
    ui.rule:SetColorTexture(0.33, 0.29, 0.20, 0.8)
    ui.rule:SetHeight(1)

    ui.loot = {}
    for i = 1, LOOT_ROWS do
        local row = {}
        row.icon = frame:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.name = St.Text(frame, 11, C.TEXT)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.count = St.Text(frame, 11, C.TITLE)
        row.count:SetPoint("RIGHT", frame, "RIGHT", -PADX, 0)
        row.count:SetPoint("TOP", row.icon, "TOP", 0, -2)
        row.count:SetJustifyH("RIGHT")
        ui.loot[i] = row
    end

    -- Pause (or Resume) and End session. Gold follows the likely next step: neither while
    -- running, Resume while paused. Ending is rare and stops the count, so it never leads.
    ui.pause = IconChoice(frame, function() FN.SessionTogglePause() end)
    ui.pause:SetScript("OnLeave", function(self) self:SetChosen(session.pausedAt ~= nil) end)
    ui.finish = St.ChoiceButton(frame, function() FN.SessionEnd() end)
    ui.finish.text:SetText("End session")

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

local function Clock(secs)
    return string.format("%d:%02d", math.floor(secs / 60), math.floor(secs % 60))
end

-- one profession's row: a mark on a soft square of its color, its name, the count and per hour,
-- and under it the skill line (or the cap note, in orange)
local ROW_H = 34
local function Row(i)
    local r = ui.rows[i]
    if r then return r end
    r = {}
    r.chip = frame:CreateTexture(nil, "ARTWORK")
    r.chip:SetSize(20, 20)
    r.mark = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    r.mark:SetSize(14, 14)
    r.mark:SetPoint("CENTER", r.chip, "CENTER", 0, 0)
    r.name = St.Text(frame, 12, C.TEXT)
    r.name:SetPoint("TOPLEFT", r.chip, "TOPRIGHT", 8, 1)
    r.rate = St.Text(frame, 10, C.SUBTEXT)
    r.rate:SetJustifyH("RIGHT")
    r.rate:SetWidth(52)
    r.count = St.Text(frame, 12, C.TEXT)
    r.count:SetJustifyH("RIGHT")
    r.count:SetPoint("RIGHT", r.rate, "LEFT", -6, 0)
    r.sub = St.Text(frame, 10, C.SUBTEXT)
    r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
    r.sub:SetWidth(W - PADX * 2 - 28)
    r.sub:SetWordWrap(false)
    r.rule = frame:CreateTexture(nil, "ARTWORK")
    r.rule:SetColorTexture(0.33, 0.29, 0.20, 0.45)
    r.rule:SetHeight(1)
    ui.rows[i] = r
    return r
end

local function ShowRow(r, on)
    for _, k in ipairs({ "chip", "mark", "name", "rate", "count", "sub", "rule" }) do r[k]:SetShown(on) end
end

local function Hex(c) return string.format("%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end

-- an icon inside a line of text, tinted (|T path : size : size : x : y : 64 : 64 : crop : r : g : b |t)
local function InlineIcon(name, c, size)
    size = size or 13
    return string.format("|T%s:%d:%d:0:0:64:64:0:64:0:64:%d:%d:%d|t", St.Icon(name), size, size,
        c[1] * 255, c[2] * 255, c[3] * 255)
end

function FN.UpdateTracker()
    if not frame or not frame:IsShown() then return end
    local secs = Active()
    local paused = session.pausedAt ~= nil
    local compact = Compact()

    ui.clock:SetText(Clock(secs))
    ui.title:SetText(paused and "Paused" or "Session")
    if paused then
        ui.dot:SetVertexColor(C.SUBTEXT[1], C.SUBTEXT[2], C.SUBTEXT[3])
    else
        ui.dot:SetVertexColor(0.31, 0.75, 0.23) -- Forever Goal Tracker's done green
    end
    -- the glow breathes only while the session runs
    local glowing = session.start ~= nil and not paused
    ui.glow:SetOn(glowing)
    ui.fold.icon:SetRotation(compact and 0 or math.pi) -- down to open, up to fold

    -- the first profession at its cap, for the folded note
    local capNote
    for _, key in ipairs(session.order) do
        local rank, cap = Skill(key)
        if not capNote and key ~= "cloth" and Capped(rank, cap) then capNote = ProfInfo(key).label .. " " .. CapNote(cap) end
    end

    local open = not compact
    ui.minPause:SetShown(compact)
    ui.minStop:SetShown(compact)
    for _, f in ipairs({ ui.rule, ui.pause, ui.finish }) do f:SetShown(open) end
    ui.empty:SetShown(#session.order == 0)

    if compact then
        -- one line: each profession's initial in its color, and its count
        local parts = {}
        for _, key in ipairs(session.order) do
            local p, e = ProfInfo(key), session.profs[key]
            parts[#parts + 1] = InlineIcon(key .. "-white", p.color) .. " " .. e.count
        end
        for _, r in ipairs(ui.rows) do ShowRow(r, false) end
        for _, row in ipairs(ui.loot) do
            row.icon:Hide()
            row.name:Hide()
            row.count:Hide()
        end
        ui.minPause.icon:SetTexture(St.Icon(paused and "play-white" or "pause-white"))
        ui.empty:ClearAllPoints()
        ui.empty:SetPoint("TOPLEFT", PADX, -36)
        ui.summary = ui.summary or St.Text(frame, 12, C.TEXT)
        ui.summary:ClearAllPoints()
        ui.summary:SetPoint("TOPLEFT", PADX, -36)
        ui.summary:SetText(table.concat(parts, "     "))
        ui.summary:SetShown(#parts > 0)
        ui.line:ClearAllPoints()
        ui.line:SetPoint("TOPLEFT", PADX, -54)
        ui.line:SetShown(capNote ~= nil)
        if capNote then ui.line:SetText(capNote) end
        SetHeightFromTop(capNote and 74 or 58)
        return
    end
    if ui.summary then ui.summary:Hide() end
    ui.line:Hide()

    local y = -36
    if #session.order == 0 then
        ui.empty:ClearAllPoints()
        ui.empty:SetPoint("TOPLEFT", PADX, y)
        y = y - 20
    end
    local hours = math.max(1 / 60, secs / 3600)
    for i, key in ipairs(session.order) do
        local p, e, r = ProfInfo(key), session.profs[key], Row(i)
        ShowRow(r, true)
        r.rule:SetShown(i > 1)
        r.rule:ClearAllPoints()
        r.rule:SetPoint("TOPLEFT", PADX, y + 4)
        r.rule:SetPoint("TOPRIGHT", -PADX, y + 4)
        r.chip:ClearAllPoints()
        r.chip:SetPoint("TOPLEFT", PADX, y - 2)
        r.chip:SetColorTexture(p.color[1], p.color[2], p.color[3], 0.16)
        r.mark:SetTexture(St.Icon(key .. "-white"))
        r.mark:SetVertexColor(p.color[1], p.color[2], p.color[3])
        r.name:SetText(p.label)
        r.count:SetText(e.count)
        r.rate:ClearAllPoints()
        r.rate:SetPoint("TOPRIGHT", -PADX, y)
        r.rate:SetText(math.floor(e.count / hours + 0.5) .. "/hr")
        r.count:ClearAllPoints()
        r.count:SetPoint("TOPRIGHT", -PADX - 58, y)
        local sub, orange
        if key == "cloth" then
            sub = e.loots > 0 and string.format("%d%% of humanoid loots", math.floor(e.count / e.loots * 100 + 0.5)) or ""
        else
            local rank, cap = Skill(key)
            if Capped(rank, cap) then
                sub, orange = CapNote(cap), true
            elseif rank then
                local gain = e.skillStart and math.max(0, rank - e.skillStart) or 0
                sub = "Skill " .. rank .. " / " .. cap .. (gain > 0 and ("  ·  +" .. gain .. " this session") or "")
            else
                sub = ""
            end
        end
        r.sub:SetText(sub)
        local c = orange and ORANGE or C.SUBTEXT
        r.sub:SetTextColor(c[1], c[2], c[3])
        y = y - ROW_H
    end
    for i = #session.order + 1, #ui.rows do ShowRow(ui.rows[i], false) end
    y = y + 4

    ui.rule:ClearAllPoints()
    ui.rule:SetPoint("TOPLEFT", PADX, y)
    ui.rule:SetPoint("TOPRIGHT", -PADX, y)
    y = y - 8

    local loot = session.allLoot
    local ids = {}
    for id in pairs(loot) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        if (a == RUINED) ~= (b == RUINED) then return b == RUINED end -- scraps last
        if loot[a] ~= loot[b] then return loot[a] > loot[b] end
        return a < b
    end)
    for i, row in ipairs(ui.loot) do
        local id = ids[i]
        if id then
            local name = GetItemInfo(id)
            row.icon:SetTexture(GetItemIcon and GetItemIcon(id) or nil)
            row.name:SetText(name or "...")
            row.count:SetText("x " .. loot[id])
            row.icon:ClearAllPoints()
            row.icon:SetPoint("TOPLEFT", PADX, y - (i - 1) * 20)
        end
        row.icon:SetShown(id ~= nil)
        row.name:SetShown(id ~= nil)
        row.count:SetShown(id ~= nil)
    end
    local shown = math.min(#ids, LOOT_ROWS)
    y = y - shown * 20 - (shown > 0 and 6 or 2)

    ui.pause.text:SetText(paused and "Resume" or "Pause")
    ui.pause.icon:SetTexture(St.Icon(paused and "play-white" or "pause-white"))
    ui.pause:SetChosen(paused)
    ui.pause:ClearAllPoints()
    ui.pause:SetPoint("TOPLEFT", PADX, y)
    ui.pause:SetWidth(98)
    ui.finish:ClearAllPoints()
    ui.finish:SetPoint("TOPRIGHT", -PADX, y)
    ui.finish:SetWidth(98)
    SetHeightFromTop(-y + 22 + 14)
end

function FN.TrackerFrame() return frame end

function FN.ShowTracker()
    if FN.db.settings.tracker == false then return end
    if not frame then Build() end
    frame:Show()
    FN.UpdateTracker()
end

function FN.HideTracker()
    if frame then frame:Hide() end
end

-- one gather of any profession (Recorder.lua). Cloth: every humanoid loot comes here, with its
-- cloth or with nothing; only the ones with cloth count.
function FN.SessionGather(prof, source, items)
    local now = GetTime()
    if session.pausedAt then -- a gather while paused carries on the session
        session.paused = session.paused + (now - session.pausedAt)
        session.pausedAt = nil
    end
    local has = next(items) ~= nil
    if prof == "cloth" and not has and not session.start then return end -- an empty loot starts nothing
    if FN.db.settings.autoSession == false then
        -- sessions start only by hand (Settings): no session, nothing to count; a running one
        -- never ends by itself
        if not session.start then return end
    elseif not session.start or not session.last or now - session.last > IDLE then
        Reset(now)
    end
    local e = session.profs[prof]
    if not e then
        e = { count = 0, loots = 0, skillStart = prof ~= "cloth" and FN.ProfessionSkill and FN.ProfessionSkill(prof) or nil }
        session.profs[prof] = e
        session.order[#session.order + 1] = prof
    end
    e.loots = e.loots + 1
    if prof == "cloth" and not has then
        FN.UpdateTracker()
        return
    end
    e.count = e.count + 1
    session.total = session.total + 1
    session.last = now
    for id, n in pairs(items) do session.allLoot[id] = (session.allLoot[id] or 0) + n end
    if prof == "skinning" then
        session.count = session.count + 1
        if items[RUINED] then session.ruined = session.ruined + 1 end
        for id, n in pairs(items) do session.loot[id] = (session.loot[id] or 0) + n end
        if source and source > 0 then session.creatures[source] = (session.creatures[source] or 0) + 1 end
        local m = math.floor(Active() / 60) + 1
        session.minutes[m] = (session.minutes[m] or 0) + 1
    end
    FN.ShowTracker()
    if FN.Map and FN.Map.Refresh then FN.Map.Refresh() end -- the tab's recording dot
end

function FN.SessionAdd(npc, items) FN.SessionGather("skinning", npc, items) end

local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "GET_ITEM_INFO_RECEIVED") -- loot names arriving after a skin
pcall(ev.RegisterEvent, ev, "SKILL_LINES_CHANGED") -- a skill point, or a new rank from a trainer
ev:SetScript("OnEvent", function(_, event)
    if event == "SKILL_LINES_CHANGED" then AlertIfCapped() end
    FN.UpdateTracker()
end)
