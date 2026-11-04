local ADDON, FN = ...

-- The session tracker: a small panel you can drag anywhere. It appears with your first skin,
-- counts the session as you go (skins, skins per minute, ruined, your skill and what this session
-- added, the loot) and hides itself after two minutes without a skin. Five quiet minutes end the
-- session; the next skin starts a new one. Pause stops the clock (a break does not lower your
-- rate). The chevron folds it to one line. When your skill reaches its rank's cap, it says so,
-- and says it once in chat and on screen: time to see a trainer.

local St = FN.Style
local C = St.C

local RUINED = 2934
local IDLE = 300 -- seconds without a skin that end a session
local FADE = 120 -- seconds without a skin before the tracker hides
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
    session.skillStart = FN.SkinningSkill and FN.SkinningSkill() or nil
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
-- Skill: your rank, its cap, and the trainer alert
-- ------------------------------------------------------------
-- the rank a trainer teaches next, by the cap you are at (Classic's skinning ranks)
local NEXT_RANK = { [75] = "Journeyman", [150] = "Expert", [225] = "Artisan" }
local TOP_CAP = 300
local ORANGE = { 1.00, 0.55, 0.15 }

local function Skill()
    if not FN.SkinningSkill then return nil end
    local rank, cap = FN.SkinningSkill()
    if type(rank) ~= "number" or rank <= 0 or type(cap) ~= "number" or cap <= 0 then return nil end
    return rank, cap
end

-- capped: at the top of your rank, short of the last one
local function Capped(rank, cap) return rank and cap and rank >= cap and cap < TOP_CAP end

-- the panel's note at the cap: short, one line (the bar and "75 / 75" already show the cap)
local function CapNote(cap) return "Capped  ·  train " .. (NEXT_RANK[cap] or "the next rank") end

local function TrainerLine(cap)
    local nextRank = NEXT_RANK[cap]
    return nextRank and ("Visit a skinning trainer to learn " .. nextRank .. ".")
        or "Visit a skinning trainer to learn the next rank."
end

-- once per cap: a line in chat, the words across the middle of the screen and a sound
local function AlertIfCapped()
    local rank, cap = Skill()
    if not Capped(rank, cap) then return end
    FN.db.settings.capAlerted = FN.db.settings.capAlerted or {}
    if FN.db.settings.capAlerted[cap] then return end
    FN.db.settings.capAlerted[cap] = true
    local line = string.format("Skinning %d / %d: you're at your rank's cap. %s", rank, cap, TrainerLine(cap))
    FN.Print(line)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(line, ORANGE[1], ORANGE[2], ORANGE[3])
    end
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
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
    ui.title:SetText("Skinning")
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

    -- open: three numbers
    ui.stats, ui.statLabels = {}, {}
    for i, label in ipairs({ "skins", "per minute", "ruined" }) do
        local v = St.Text(frame, 18, C.TEXT)
        v:SetPoint("TOPLEFT", PADX + (i - 1) * 70, -34)
        local l = St.Text(frame, 10, C.SUBTEXT)
        l:SetPoint("TOPLEFT", v, "BOTTOMLEFT", 0, -2)
        l:SetText(label)
        ui.stats[i], ui.statLabels[i] = v, l
    end

    -- your skill: rank / cap, what this session added, and a slim bar toward the cap
    ui.skillLabel = St.Text(frame, 10, C.SUBTEXT)
    ui.skillLabel:SetText("Skill")
    ui.skillValue = St.Text(frame, 11, C.TEXT)
    ui.skillValue:SetJustifyH("RIGHT")
    ui.skillGain = St.Text(frame, 10, C.TITLE)
    ui.skillGain:SetJustifyH("RIGHT")
    ui.skillTrack = frame:CreateTexture(nil, "ARTWORK")
    ui.skillTrack:SetColorTexture(1, 0.94, 0.82, 0.08)
    ui.skillTrack:SetHeight(4)
    ui.skillFill = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    ui.skillFill:SetTexture(St.SOLID)
    ui.skillFill:SetHeight(4)
    -- at the cap: an orange note, the clearest thing in the panel
    ui.alert = St.Text(frame, 11, ORANGE)
    ui.alert:SetWidth(W - PADX * 2)
    ui.alert:SetJustifyV("TOP")

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

function FN.UpdateTracker()
    if not frame or not frame:IsShown() then return end
    local secs = Active()
    local paused = session.pausedAt ~= nil
    local compact = Compact()
    local rank, cap = Skill()
    local capped = Capped(rank, cap)
    local gain = rank and session.skillStart and math.max(0, rank - session.skillStart) or 0

    ui.clock:SetText(Clock(secs))
    ui.title:SetText(paused and "Paused" or "Skinning")
    if paused then
        ui.dot:SetVertexColor(C.SUBTEXT[1], C.SUBTEXT[2], C.SUBTEXT[3])
    else
        ui.dot:SetVertexColor(0.31, 0.75, 0.23) -- Forever Goal Tracker's done green
    end
    -- the glow breathes only while the session runs
    local glowing = session.start ~= nil and not paused
    ui.glow:SetOn(glowing)
    ui.fold.icon:SetRotation(compact and 0 or math.pi) -- down to open, up to fold

    local ruined = session.count > 0 and (math.floor(session.ruined / session.count * 100 + 0.5) .. "%") or "-"
    local open = not compact
    ui.line:SetShown(compact and capped)
    ui.minPause:SetShown(compact)
    ui.minStop:SetShown(compact)
    ui.stats[1]:SetText(session.count)
    ui.stats[2]:SetText(string.format("%.1f", FN.SessionRate()))
    ui.stats[3]:SetText(ruined)
    for _, f in ipairs({ ui.skillLabel, ui.skillValue, ui.skillGain, ui.skillTrack, ui.skillFill, ui.rule,
        ui.pause, ui.finish }) do
        f:SetShown(open)
    end
    ui.alert:SetShown(open and capped)

    if compact then
        if capped then ui.line:SetText(CapNote(cap)) end
        ui.minPause.icon:SetTexture(St.Icon(paused and "play-white" or "pause-white"))
        for _, row in ipairs(ui.loot) do
            row.icon:Hide()
            row.name:Hide()
            row.count:Hide()
        end
        SetHeightFromTop(capped and 94 or 78)
        return
    end

    local y = -78
    ui.skillLabel:SetShown(rank ~= nil)
    ui.skillValue:SetShown(rank ~= nil)
    ui.skillGain:SetShown(rank ~= nil and gain > 0)
    ui.skillTrack:SetShown(rank ~= nil)
    ui.skillFill:SetShown(rank ~= nil)
    if rank then
        ui.skillLabel:ClearAllPoints()
        ui.skillLabel:SetPoint("TOPLEFT", PADX, y)
        ui.skillValue:ClearAllPoints()
        ui.skillValue:SetPoint("TOPRIGHT", -PADX, y + 1)
        ui.skillValue:SetText(rank .. " / " .. cap)
        ui.skillGain:ClearAllPoints()
        ui.skillGain:SetPoint("RIGHT", ui.skillValue, "LEFT", -8, 0)
        ui.skillGain:SetText("+" .. gain .. " this session")
        y = y - 16
        local barW = W - PADX * 2
        ui.skillTrack:ClearAllPoints()
        ui.skillTrack:SetPoint("TOPLEFT", PADX, y)
        ui.skillTrack:SetWidth(barW)
        ui.skillFill:ClearAllPoints()
        ui.skillFill:SetPoint("TOPLEFT", PADX, y)
        ui.skillFill:SetWidth(math.max(1, barW * math.min(1, rank / cap)))
        if capped then
            ui.skillFill:SetVertexColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
        else
            St.HGradient(ui.skillFill, { 0.62, 0.42, 0.05 }, { 1.00, 0.86, 0.30 })
        end
        y = y - 12
        if capped then
            ui.alert:SetText(CapNote(cap))
            ui.alert:ClearAllPoints()
            ui.alert:SetPoint("TOPLEFT", PADX, y)
            y = y - ui.alert:GetStringHeight() - 8
        end
    end

    ui.rule:ClearAllPoints()
    ui.rule:SetPoint("TOPLEFT", PADX, y)
    ui.rule:SetPoint("TOPRIGHT", -PADX, y)
    y = y - 8

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
pcall(ev.RegisterEvent, ev, "SKILL_LINES_CHANGED") -- a skill point, or a new rank from a trainer
ev:SetScript("OnEvent", function(_, event)
    if event == "SKILL_LINES_CHANGED" then AlertIfCapped() end
    FN.UpdateTracker()
end)
