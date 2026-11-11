local ADDON, FN = ...

-- The session tracker: a small panel you can drag anywhere. One session, one clock, for every
-- profession (professions v4 mockup, 2026-11-04): a row appears the first time you gather
-- something of a profession this session, with its count, per hour on the shared clock, and
-- your skill and what this session added (Cloth: how often humanoids dropped it). Then the
-- session's top loot. It appears with your first gather and stays until the session ends (Settings
-- can hide it after two minutes without a gather). A session runs until you end it or log out: a
-- /reload carries it over (saved at logout, read back only after a reload). Pause stops the clock. The chevron folds it to one line: the clock, then each profession's initial and count.
-- End session opens a full recap of what you gathered, with Undo and Done, until you close it.
-- The dots in its bottom right corner resize it. When a skill reaches its rank's cap, it says so,
-- once in chat and on screen: time to see a trainer.
-- Money (coin you loot) joins a running session as its own row, the amount and per hour; it never
-- starts a session, does not count while paused and stays out of the gather count.
-- Going AFK pauses a running session, and coming back resumes it, unless you paused it yourself.
-- Its settings can make it expand up: the header sits on the bottom edge and never moves, and the
-- window opens above it, in the usual reading order (totals, loot, then the buttons).

local St = FN.Style
local C = St.C

local RUINED = 2934
local FADE = 120 -- seconds without a skin before the tracker hides, when that setting is on
local LOOT_ROWS = 4 -- always room for this many; a taller window shows more

-- count, ruined, loot, creatures: skinning's (the stats window reads them); total and allLoot:
-- every profession's; profs[key] = { count, loots, skillStart }, in order of first gather
local session = { count = 0, ruined = 0, loot = {}, creatures = {}, minutes = {}, paused = 0,
    total = 0, allLoot = {}, profs = {}, order = {} }
FN.session = session
local closed = false -- the X was pressed: gathers leave the window shut until asked or a new session
local afkPaused = false -- AFK paused the session: coming back resumes it (a pause by hand stays)
local recap = nil -- the session just ended, while the window shows it (a Snapshot); Undo puts it back

-- seconds of skinning so far, leaving out pauses
local function Active()
    if not session.start then return 0 end
    local stop = session.pausedAt or GetTime()
    return math.max(0, stop - session.start - session.paused)
end
FN.SessionSeconds = Active

local function Reset(now)
    closed = false
    afkPaused = false
    recap = nil
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

-- ------------------------------------------------------------
-- Keeping a session: over a /reload, and for Undo after End session
-- ------------------------------------------------------------
local KEPT = { "count", "ruined", "total", "skillStart" }
local KEPT_TABLES = { "loot", "creatures", "minutes", "allLoot", "profs", "order" }

local function Copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = type(v) == "table" and Copy(v) or v end
    return out
end

-- the clock is kept as seconds played, not as times, so the moments of the reload itself do not count
local function Snapshot()
    if not session.start then return nil end
    local s = { active = Active(), paused = session.pausedAt ~= nil, closed = closed, shown = FN.TrackerShown(), afk = afkPaused,
        quiet = session.last and GetTime() - session.last or nil }
    for _, k in ipairs(KEPT) do s[k] = session[k] end
    for _, k in ipairs(KEPT_TABLES) do s[k] = Copy(session[k]) end
    return s
end

local function Restore(s)
    if type(s) ~= "table" or type(s.active) ~= "number" then return end
    local now = GetTime()
    Reset(now)
    for _, k in ipairs(KEPT) do session[k] = s[k] end
    for _, k in ipairs(KEPT_TABLES) do session[k] = type(s[k]) == "table" and s[k] or {} end
    session.start = now - s.active
    session.pausedAt = s.paused and now or nil
    session.last = s.quiet and now - s.quiet or nil
    closed = s.closed == true
    afkPaused = s.paused and s.afk == true
    if s.shown then FN.ShowTracker() end
end

function FN.SessionHas(prof) return session.start ~= nil and session.profs[prof] ~= nil end

local function ProfInfo(key)
    return FN.Map and FN.Map.PROF and FN.Map.PROF[key] or { key = key, label = key, unit = "gather", units = "gathers",
        color = { 0.8, 0.8, 0.8 } }
end

-- "34 skins" while you only skin, else "43 gathers": the dock's session row and the toolbar
-- (Money is an amount, not a gather, so it is left out of both)
function FN.SessionLabel()
    local n = session.total or 0
    local only, kinds = nil, 0
    for _, key in ipairs(session.order) do
        if key ~= "money" then only, kinds = key, kinds + 1 end
    end
    if kinds == 1 then
        local p = ProfInfo(only)
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
    afkPaused = false -- a click wins over AFK either way
    if session.pausedAt then
        session.paused = session.paused + (now - session.pausedAt)
        session.pausedAt = nil
        session.last = now -- a resumed session is not idle
    else
        session.pausedAt = now
    end
    FN.UpdateTracker()
end

-- A session with nothing in it just closes. Anything gathered opens the recap, even if the window
-- was closed: ending is a click you may want back.
function FN.SessionEnd()
    local ended = session.start and (session.total > 0 or session.profs.money ~= nil) and Snapshot() or nil
    Reset(nil)
    session.start = nil
    recap = ended
    if recap then
        recap.ended = true
        FN.ShowTracker(true)
    else
        FN.HideTracker()
    end
end

-- the session carries on as if it was never ended, with the same clock
function FN.SessionUndo()
    local s = recap
    if not s then return end
    s.closed, s.shown = false, true
    Restore(s)
    FN.UpdateTracker()
end

function FN.SessionDone()
    recap = nil
    FN.HideTracker()
end

function FN.SessionRecap() return recap end

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
local W, PADX = 232, 14 -- W is the default width and the smallest
local MAX_W, MAX_H = 420, 560
local HEADER_FLIP = 40 -- the top edge and the bottom edge this far apart keep the header on the same pixels
local sizing = false -- the corner dots are being dragged
local reopened = 0 -- when a click last asked for the window (GetTime), so it does not hide at once

-- how solid the window's background is, 0 to 1 (Settings); text, icons and buttons stay solid
function FN.TrackerOpacity()
    return math.max(0, math.min(1, tonumber(FN.db.settings.trackerAlpha) or 1))
end

function FN.SetTrackerOpacity(v)
    FN.db.settings.trackerAlpha = v
    if frame then frame:SetEtchFade(FN.TrackerOpacity()) end
end

-- the size you dragged it to: a width, and a height only if you made it taller than its content
local function SavedSize()
    local s = FN.db.settings.trackerSize
    if type(s) ~= "table" then return W, nil end
    local h = tonumber(s.h)
    return math.max(W, math.min(MAX_W, tonumber(s.w) or W)), h and math.min(MAX_H, h) or nil
end

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

local function Up() return FN.db.settings.trackerExpand == "up" end

-- the panel hangs from its header's edge, so folding and growing move only the far edge (it was
-- placed by its middle, so both edges moved). Saved that way, it stays where it was left.
local function Hang()
    local up = Up()
    local left, y = frame:GetLeft(), up and frame:GetBottom() or frame:GetTop()
    if not left or not y then return end
    local point = up and "BOTTOMLEFT" or "TOPLEFT"
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, "BOTTOMLEFT", left, y)
    FN.db.settings.trackerPos = { point, "BOTTOMLEFT", left, y }
end

local function SetHeightHung(h)
    local point, _, relPoint = frame:GetPoint()
    local hung = point == (Up() and "BOTTOMLEFT" or "TOPLEFT") and relPoint == "BOTTOMLEFT"
    -- never while it is being dragged (the mover owns its position), and only once
    if not frame.dragging and not hung then Hang() end
    frame:SetHeight(h)
end

-- quiet long enough to hide: only when Settings asks for it, never while paused or being resized
local function IdleHide()
    if FN.db.settings.trackerAutoHide ~= true or sizing or session.pausedAt or not session.last then return false end
    return GetTime() - math.max(session.last, reopened) > FADE
end

-- three dots in the far right corner (the top one when it expands up); drag them to resize. The
-- window never gets smaller than
-- what it is showing. Dragged back to that smallest height, it goes back to fitting its content.
local function BuildGrip()
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(14, 14)
    local dots, spots = {}, { { 4, 4 }, { 8, 4 }, { 4, 8 } }
    for i in ipairs(spots) do
        dots[i] = grip:CreateTexture(nil, "ARTWORK")
        dots[i]:SetSize(2, 2)
    end
    function grip:Seat()
        local up = Up()
        local corner = up and "TOPRIGHT" or "BOTTOMRIGHT"
        self:ClearAllPoints()
        self:SetPoint(corner)
        for i, at in ipairs(spots) do
            dots[i]:ClearAllPoints()
            dots[i]:SetPoint(corner, -at[1], up and -at[2] or at[2])
        end
    end
    local function Tint(lit)
        local c = lit and C.TITLE or C.INK2
        for _, d in ipairs(dots) do d:SetColorTexture(c[1], c[2], c[3], 1) end
    end
    Tint(false)
    grip:SetScript("OnEnter", function() Tint(true) end)
    grip:SetScript("OnLeave", function() if not sizing then Tint(false) end end)
    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        Hang() -- the header's edge stays put while the far corner follows the mouse
        local minH = ui.needH or 120
        local maxH = math.max(MAX_H, minH)
        if frame.SetResizeBounds then
            frame:SetResizeBounds(W, minH, MAX_W, maxH)
        elseif frame.SetMinResize then
            frame:SetMinResize(W, minH)
            frame:SetMaxResize(MAX_W, maxH)
        end
        sizing = true
        frame:StartSizing(Up() and "TOPRIGHT" or "BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function(self)
        Tint(self:IsMouseOver())
        if not sizing then return end
        frame:StopMovingOrSizing()
        sizing = false
        Hang()
        local w, h = math.floor(frame:GetWidth() + 0.5), math.floor(frame:GetHeight() + 0.5)
        FN.db.settings.trackerSize = { w = w, h = h > (ui.needH or 0) + 1 and h or nil }
        FN.UpdateTracker()
    end)
    return grip
end

-- the header's dot and close button, and the corner dots, on the edges this direction uses (the
-- rest of the header hangs from those two)
local function SeatHeader()
    ui.dot:ClearAllPoints()
    ui.close:ClearAllPoints()
    if Up() then
        ui.dot:SetPoint("BOTTOMLEFT", PADX, 16)
        ui.close:SetPoint("BOTTOMRIGHT", -PADX, 15)
    else
        ui.dot:SetPoint("TOPLEFT", PADX, -16)
        ui.close:SetPoint("TOPRIGHT", -PADX, -15)
    end
    ui.grip:Seat()
end

-- the gear is gold while its panel is open
local function GearTint()
    if not ui.gear then return end
    local c = ui.settings and ui.settings:IsShown() and C.TITLE or C.INK2
    ui.gear.icon:SetVertexColor(c[1], c[2], c[3])
end

-- the window's own settings, in a small panel beside it (always solid, so it stays readable however
-- see-through the window is); made the first time the gear is pressed
local function BuildSettings()
    local PANEL_W, PAD = 190, 12
    local p = St.Frame("Frame", frame)
    p:SetSize(PANEL_W, 165)
    St.Etch(p, St.STYLE.panel, 12, 1)
    p:EnableMouse(true)
    p:SetClampedToScreen(true)
    p:Hide()

    local title = St.Title(p, 12)
    title:SetPoint("TOPLEFT", PAD, -12)
    title:SetText("Window settings")

    local label = St.Text(p, 10, C.INK2)
    label:SetPoint("TOPLEFT", PAD, -36)
    label:SetText("Background opacity")
    local value = St.Text(p, 10, C.INK2)
    value:SetPoint("TOPRIGHT", -PAD, -36)
    value:SetJustifyH("RIGHT")
    local function Percent(v) value:SetText(math.floor(v * 100 + 0.5) .. "%") end
    local slider = St.Slider(p, PANEL_W - PAD * 2, 0, 1, 0.05, function(v)
        FN.SetTrackerOpacity(v)
        Percent(v)
    end)
    slider:SetPoint("TOPLEFT", PAD, -52)

    local expandText = St.Text(p, 10, C.INK2)
    expandText:SetPoint("TOPLEFT", PAD, -83)
    expandText:SetText("Expand")
    local half = math.floor((PANEL_W - PAD * 2 - 4) / 2)
    local down, up
    local function SyncExpand()
        down:SetChosen(not Up())
        up:SetChosen(Up())
    end
    down = St.ChoiceButton(p, function()
        FN.SetTrackerExpand("down")
        SyncExpand()
    end)
    down.text:SetText("Down")
    down.tip = "The window opens below its header."
    down:SetWidth(half)
    down:SetPoint("TOPLEFT", PAD, -99)
    up = St.ChoiceButton(p, function()
        FN.SetTrackerExpand("up")
        SyncExpand()
    end)
    up.text:SetText("Up")
    up.tip = "The window opens above its header."
    up:SetWidth(half)
    up:SetPoint("TOPRIGHT", -PAD, -99)

    local hideText = St.Text(p, 10, C.INK2)
    hideText:SetPoint("TOPLEFT", PAD, -136)
    hideText:SetText("Hide when idle")
    local hide = CreateFrame("Button", nil, p)
    hide:SetSize(36, 18)
    hide:SetPoint("TOPRIGHT", -PAD, -133)
    hide.toggle = St.Toggle(hide)
    hide.toggle:SetAllPoints()
    hide:SetScript("OnClick", function(self)
        FN.db.settings.trackerAutoHide = FN.db.settings.trackerAutoHide ~= true
        self.toggle:SetOn(FN.db.settings.trackerAutoHide == true)
    end)
    hide:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Hide when idle", 1, 1, 1)
        GameTooltip:AddLine("On: the window hides after two minutes without a gather and comes back with your next one. Off: it stays until the session ends.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    hide:SetScript("OnLeave", function() GameTooltip:Hide() end)

    function p:Sync()
        local v = FN.TrackerOpacity()
        slider:Set(v)
        Percent(v)
        SyncExpand()
        hide.toggle:SetOn(FN.db.settings.trackerAutoHide == true)
    end
    ui.settings = p
end

function FN.TrackerSettings() return ui.settings end

-- on whichever side has room, level with the window's header
local function SeatSettings()
    local p = ui.settings
    local center = frame:GetCenter()
    local onLeft = center and center > UIParent:GetWidth() / 2
    local edge = Up() and "BOTTOM" or "TOP"
    p:ClearAllPoints()
    if onLeft then
        p:SetPoint(edge .. "RIGHT", frame, edge .. "LEFT", -4, 0)
    else
        p:SetPoint(edge .. "LEFT", frame, edge .. "RIGHT", 4, 0)
    end
end

-- "up" or "down". The header stays on the same spot of the screen; the window turns around it.
function FN.SetTrackerExpand(dir)
    local up = dir == "up"
    if up == Up() then return end
    local left, top, bottom
    if frame then left, top, bottom = frame:GetLeft(), frame:GetTop(), frame:GetBottom() end
    FN.db.settings.trackerExpand = up and "up" or nil
    if not frame then return end
    if left and top and bottom then
        local point, y = up and "BOTTOMLEFT" or "TOPLEFT", up and top - HEADER_FLIP or bottom + HEADER_FLIP
        frame:ClearAllPoints()
        frame:SetPoint(point, UIParent, "BOTTOMLEFT", left, y)
        FN.db.settings.trackerPos = { point, "BOTTOMLEFT", left, y }
    end
    SeatHeader()
    if ui.settings and ui.settings:IsShown() then SeatSettings() end
    FN.UpdateTracker()
end

function FN.ToggleTrackerSettings()
    if not frame then return end
    if not ui.settings then BuildSettings() end
    local p = ui.settings
    if p:IsShown() then
        p:Hide()
    else
        p:Sync()
        SeatSettings()
        p:Show()
    end
    GearTint()
end

local function Build()
    frame = St.Frame("Frame", UIParent)
    frame:SetSize(SavedSize(), 200)
    frame:SetFrameStrata("MEDIUM")
    frame:SetResizable(true)
    St.Etch(frame, St.STYLE.panel, 12, 0.94)
    St.Movable(frame, "trackerPos")
    frame:SetEtchFade(FN.TrackerOpacity())
    frame:HookScript("OnDragStart", function(self) self.dragging = true end)
    frame:HookScript("OnDragStop", function(self) self.dragging = false end)
    frame:HookScript("OnSizeChanged", function() if sizing then FN.UpdateTracker() end end)
    St.PlaceSaved(frame, "trackerPos", "RIGHT", "RIGHT", -60, 120)
    frame:Hide()
    ui.grip = BuildGrip()

    -- the header: the dot (glowing while you skin), the title, the clock and the fold chevron
    ui.dot = frame:CreateTexture(nil, "ARTWORK", nil, 2)
    ui.dot:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    ui.dot:SetSize(8, 8)
    ui.glow = St.Glow(frame, ui.dot, { 0.31, 0.75, 0.23 }) -- breathes while the session runs
    ui.title = St.Title(frame, 12)
    ui.title:SetPoint("LEFT", ui.dot, "RIGHT", 7, 0)
    ui.title:SetText("Session")
    ui.fold = St.IconButton(frame, "chevron-white", 10, function()
        FN.db.settings.trackerCompact = not Compact()
        FN.UpdateTracker()
    end)
    -- the X closes the window only; the session carries on (the stop square ends it)
    ui.close = St.IconButton(frame, "close-white", 10, function() FN.CloseTracker() end)
    SeatHeader()
    ui.fold:SetPoint("RIGHT", ui.close, "LEFT", -9, 0)
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
    ui.gear = St.IconButton(frame, "gear-white", 11, function() FN.ToggleTrackerSettings() end)
    ui.gear:SetPoint("RIGHT", ui.fold, "LEFT", -9, 0)
    -- the clock sits with the status it describes; the controls hang from the right edge, so the
    -- clock's changing width never moves them (it nudged them every second, seen in game)
    ui.clock = St.Text(frame, 11, C.INK2)
    ui.clock:SetPoint("LEFT", ui.title, "RIGHT", 8, 0)

    -- folded: the header and the three numbers stay; pause and end become icons in the header,
    -- and at the skill cap one orange line keeps the trainer in view
    -- a stop square, not an X: it ends the session, it does not close the panel
    ui.minStop = St.IconButton(frame, "stop-white", 9, function() FN.SessionEnd() end)
    ui.minStop:SetPoint("RIGHT", ui.gear, "LEFT", -12, 0)
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
    IconTip(ui.close, function() return recap and "Close" or "Close (the session keeps running)" end)
    IconTip(ui.gear, "Window settings")
    ui.gear:HookScript("OnLeave", GearTint) -- stays gold while its panel is open
    IconTip(ui.minStop, "End session")
    IconTip(ui.minPause, function() return session.pausedAt and "Resume" or "Pause" end)
    ui.line = St.Text(frame, 10, ORANGE)
    ui.line:SetPoint("TOPLEFT", PADX, -72)
    ui.line:SetWordWrap(false)

    -- open: a row per profession gathered this session (made as needed, see Row below)
    ui.rows = {}
    ui.empty = St.Text(frame, 10, C.SUBTEXT)
    ui.empty:SetText("Gather anything to start counting.")

    ui.rule = frame:CreateTexture(nil, "ARTWORK")
    ui.rule:SetColorTexture(0.33, 0.29, 0.20, 0.8)
    ui.rule:SetHeight(1)

    ui.loot = {} -- made as needed, see LootRow below

    -- Pause (or Resume) and End session. Gold follows the likely next step: neither while
    -- running, Resume while paused. Ending is rare and stops the count, so it never leads.
    ui.pause = IconChoice(frame, function()
        if recap then FN.SessionUndo() else FN.SessionTogglePause() end
    end)
    ui.pause:SetScript("OnLeave", function(self) self:SetChosen(session.pausedAt ~= nil) end)
    ui.finish = St.ChoiceButton(frame, function()
        if recap then FN.SessionDone() else FN.SessionEnd() end
    end)
    ui.finish.text:SetText("End session")

    -- the settings panel goes with the window, and starts closed next time
    frame:HookScript("OnHide", function()
        if ui.settings then ui.settings:Hide() end
        GearTint()
    end)

    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 1 then return end
        elapsed = 0
        if IdleHide() then
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

-- one line of the session's loot: its icon, name and count
local function LootRow(i)
    local row = ui.loot[i]
    if row then return row end
    row = {}
    row.icon = frame:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.name = St.Text(frame, 11, C.TEXT)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetWordWrap(false)
    row.count = St.Text(frame, 11, C.TITLE)
    row.count:SetPoint("RIGHT", frame, "RIGHT", -PADX, 0)
    row.count:SetPoint("TOP", row.icon, "TOP", 0, -2)
    row.count:SetJustifyH("RIGHT")
    ui.loot[i] = row
    return row
end

local function Hex(c) return string.format("%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end

-- an icon inside a line of text, tinted (|T path : size : size : x : y : 64 : 64 : crop : r : g : b |t)
local function InlineIcon(name, c, size)
    size = size or 13
    return string.format("|T%s:%d:%d:0:0:64:64:0:64:0:64:%d:%d:%d|t", St.Icon(name), size, size,
        c[1] * 255, c[2] * 255, c[3] * 255)
end

-- a profession's line in the recap: what the session added and how fast it went
-- a rate rounded to its largest coin's neighbour: copper only while under a silver an hour, else no
-- copper, so the line does not flicker as the clock runs
local function MoneyRate(copper)
    copper = math.floor(copper)
    if copper >= 100 then copper = math.floor(copper / 100 + 0.5) * 100 end
    return FN.FormatMoney(copper)
end

local function MoneyLine(e, hours)
    return MoneyRate((e.copper or 0) / hours) .. " per hour  ·  " .. e.count
        .. (e.count == 1 and " loot" or " loots")
end

local function RecapLine(key, e, hours)
    if key == "money" then return MoneyLine(e, hours) end
    local rate = math.floor(e.count / hours + 0.5) .. "/hr"
    if key == "cloth" and e.loots > 0 then
        return string.format("%d%% of humanoid loots  ·  %s", math.floor(e.count / e.loots * 100 + 0.5), rate)
    end
    local rank = Skill(key)
    local gain = rank and e.skillStart and rank - e.skillStart or 0
    return gain > 0 and ("+" .. gain .. " skill  ·  " .. rate) or rate
end

function FN.UpdateTracker()
    if not frame or not frame:IsShown() then return end
    local src = recap or session -- a recap has the same shape as the running session
    local secs = recap and recap.active or Active()
    local paused = session.pausedAt ~= nil
    local compact = Compact() and not recap -- the recap is always the full window
    local up = Up()
    -- while the corner dots are dragged the window's live size leads; otherwise the saved one
    local w, wantH = SavedSize()
    if sizing then
        w, wantH = frame:GetWidth(), frame:GetHeight()
    else
        frame:SetWidth(w)
    end
    ui.grip:SetShown(not compact)

    ui.clock:SetText(Clock(secs))
    ui.title:SetText(recap and "Session ended" or paused and "Paused" or "Session")
    ui.fold:SetShown(not recap)
    ui.gear:SetShown(not recap)
    if recap and ui.settings and ui.settings:IsShown() then
        ui.settings:Hide()
        GearTint()
    end
    if paused or recap then
        ui.dot:SetVertexColor(C.SUBTEXT[1], C.SUBTEXT[2], C.SUBTEXT[3])
    else
        ui.dot:SetVertexColor(0.31, 0.75, 0.23) -- Forever Goal Tracker's done green
    end
    -- the glow breathes only while the session runs
    local glowing = session.start ~= nil and not paused
    ui.glow:SetOn(glowing)
    -- points the way the window will move: down to open and up to fold, or the reverse when it expands up
    ui.fold.icon:SetRotation(compact ~= up and 0 or math.pi)

    -- the first profession at its cap, for the folded note
    local capNote
    for _, key in ipairs(session.order) do
        local rank, cap = Skill(key)
        if not capNote and not ProfInfo(key).anyone and Capped(rank, cap) then capNote = ProfInfo(key).label .. " " .. CapNote(cap) end
    end

    local open = not compact
    ui.minPause:SetShown(compact)
    ui.minStop:SetShown(compact)
    for _, f in ipairs({ ui.rule, ui.pause, ui.finish }) do f:SetShown(open) end
    ui.empty:SetShown(#src.order == 0)

    if compact then
        -- one line: each profession's initial in its color, and its count
        local parts = {}
        for _, key in ipairs(session.order) do
            local p, e = ProfInfo(key), session.profs[key]
            parts[#parts + 1] = InlineIcon(key .. "-white", p.color) .. " "
                .. (key == "money" and FN.FormatMoney(e.copper or 0) or e.count)
        end
        for _, r in ipairs(ui.rows) do ShowRow(r, false) end
        for _, row in ipairs(ui.loot) do
            row.icon:Hide()
            row.name:Hide()
            row.count:Hide()
        end
        ui.minPause.icon:SetTexture(St.Icon(paused and "play-white" or "pause-white"))
        -- expanding up, the lines stack upward from the header, so they hang from the bottom edge
        local anchor, sign = up and "BOTTOMLEFT" or "TOPLEFT", up and 1 or -1
        ui.empty:ClearAllPoints()
        ui.empty:SetPoint(anchor, PADX, sign * 36)
        ui.summary = ui.summary or St.Text(frame, 12, C.TEXT)
        ui.summary:ClearAllPoints()
        ui.summary:SetPoint(anchor, PADX, sign * 36)
        ui.summary:SetText(table.concat(parts, "     "))
        ui.summary:SetShown(#parts > 0)
        ui.line:ClearAllPoints()
        ui.line:SetPoint(anchor, PADX, sign * 54)
        ui.line:SetWidth(w - PADX * 2)
        ui.line:SetShown(capNote ~= nil)
        if capNote then ui.line:SetText(capNote) end
        SetHeightHung(capNote and 74 or 58)
        return
    end
    if ui.summary then ui.summary:Hide() end
    ui.line:Hide()

    local loot = src.allLoot
    local ids = {}
    for id in pairs(loot) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        if (a == RUINED) ~= (b == RUINED) then return b == RUINED end -- scraps last
        if loot[a] ~= loot[b] then return loot[a] > loot[b] end
        return a < b
    end)
    -- the smallest this content fits in: its rows, four lines of loot, the buttons. Any height
    -- beyond that goes to more lines of loot; the buttons stay at the bottom. Expanding up only
    -- moves the header: the sections keep their reading order (a flipped order read badly in game).
    local rowCount = #src.order
    local above, below = up and 14 or 36, up and 36 or 14 -- room above the rows and below the buttons
    local rowsEnd = above + (rowCount > 0 and ROW_H * rowCount - 4 or 16)
    local base = math.min(#ids, LOOT_ROWS)
    local needH = rowsEnd + 8 + base * 20 + (base > 0 and 6 or 2) + 22 + below
    local h = math.max(needH, wantH or 0)
    ui.needH = needH
    local shown = math.min(#ids, base + math.floor((h - needH) / 20))

    if rowCount == 0 then
        ui.empty:ClearAllPoints()
        ui.empty:SetPoint("TOPLEFT", PADX, -above)
    end
    -- per-hour rates move in whole minutes (and with each gather), not every second: a rate that
    -- ticked with the clock was distracting (Karl, 2026-11-10)
    local hours = math.max(1, math.floor(secs / 60)) / 60
    for i, key in ipairs(src.order) do
        local p, e, r = ProfInfo(key), src.profs[key], Row(i)
        local y = -above - ROW_H * (i - 1)
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
        local money = key == "money"
        -- Money's amount is too wide to sit beside a rate: it takes the right edge, its rate the line below
        r.count:SetText(money and FN.FormatMoney(e.copper or 0) or e.count)
        r.rate:ClearAllPoints()
        r.rate:SetPoint("TOPRIGHT", -PADX, y)
        r.rate:SetText((recap or money) and "" or math.floor(e.count / hours + 0.5) .. "/hr") -- the recap has it on the line below
        r.count:ClearAllPoints()
        r.count:SetPoint("TOPRIGHT", (recap or money) and -PADX or -PADX - 58, y)
        local sub, orange
        if money then
            sub = MoneyLine(e, hours)
        elseif recap then
            sub = RecapLine(key, e, hours)
        elseif key == "cloth" then
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
        r.sub:SetWidth(w - PADX * 2 - 28)
        r.sub:SetText(sub)
        local c = orange and ORANGE or C.SUBTEXT
        r.sub:SetTextColor(c[1], c[2], c[3])
    end
    for i = rowCount + 1, #ui.rows do ShowRow(ui.rows[i], false) end

    ui.rule:ClearAllPoints()
    ui.rule:SetPoint("TOPLEFT", PADX, -rowsEnd)
    ui.rule:SetPoint("TOPRIGHT", -PADX, -rowsEnd)

    for i = 1, math.max(shown, #ui.loot) do
        local row, id = LootRow(i), i <= shown and ids[i] or nil
        if id then
            local name = FN.ItemInfo(id)
            row.icon:SetTexture(FN.ItemIcon(id))
            row.name:SetWidth(w - PADX * 2 - 24 - 44)
            row.name:SetText(name or "...")
            row.count:SetText("x " .. loot[id])
            row.icon:ClearAllPoints()
            row.icon:SetPoint("TOPLEFT", PADX, -rowsEnd - 8 - (i - 1) * 20)
        end
        row.icon:SetShown(id ~= nil)
        row.name:SetShown(id ~= nil)
        row.count:SetShown(id ~= nil)
    end

    local buttonY, buttonW = 22 + below - h, math.floor((w - PADX * 2 - 8) / 2)
    ui.pause.text:SetText(recap and "Undo" or paused and "Resume" or "Pause")
    ui.pause.icon:SetShown(not recap)
    ui.finish.text:SetText(recap and "Done" or "End session")
    ui.pause.icon:SetTexture(St.Icon(paused and "play-white" or "pause-white"))
    ui.pause:SetChosen(paused)
    ui.pause:ClearAllPoints()
    ui.pause:SetPoint("TOPLEFT", PADX, buttonY)
    ui.pause:SetWidth(buttonW)
    ui.finish:ClearAllPoints()
    ui.finish:SetPoint("TOPRIGHT", -PADX, buttonY)
    ui.finish:SetWidth(buttonW)
    if not sizing then SetHeightHung(h) end
end

function FN.TrackerFrame() return frame end
function FN.TrackerParts() return ui end

-- asked: a click on the running session. It opens even after /fn tracker turned the automatic
-- window off, and counts as activity so the idle hide does not take it away again at once.
function FN.ShowTracker(asked)
    if not asked and (closed or FN.db.settings.tracker == false) then return end
    if not frame then Build() end
    if asked then
        reopened = GetTime()
        closed = false
    end
    frame:Show()
    frame:Raise()
    FN.UpdateTracker()
end

function FN.TrackerShown() return frame ~= nil and frame:IsShown() end

function FN.CloseTracker()
    if recap then
        FN.SessionDone()
        return
    end
    closed = true
    FN.HideTracker()
end

function FN.HideTracker()
    if frame then frame:Hide() end
end

-- one gather of any profession (Recorder.lua). Cloth: every humanoid loot comes here, with its
-- cloth or with nothing; only the ones with cloth count.
function FN.SessionGather(prof, source, items)
    local now = GetTime()
    if session.pausedAt then -- a gather (coin too) while paused carries on the session
        session.paused = session.paused + (now - session.pausedAt)
        session.pausedAt = nil
        afkPaused = false
    end
    if prof == "money" then
        -- coin starts a session like any gather, but is not counted as one
        if not session.start then
            if FN.db.settings.autoSession == false then return end
            Reset(now)
            if FN.Map and FN.Map.Refresh then FN.Map.Refresh() end -- the tab's recording dot
        end
        local e = session.profs.money
        if not e then
            e = { count = 0, loots = 0, copper = 0 }
            session.profs.money = e
            session.order[#session.order + 1] = "money"
        end
        e.count, e.loots = e.count + 1, e.loots + 1
        e.copper = (e.copper or 0) + (items[FN.COIN] or 0)
        FN.ShowTracker()
        return
    end
    local has = next(items) ~= nil
    if prof == "cloth" and not has and not session.start then return end -- an empty loot starts nothing
    if not session.start then
        -- sessions can be set to start only by hand (Settings): then no session, nothing to count
        if FN.db.settings.autoSession == false then return end
        Reset(now)
    end
    local e = session.profs[prof]
    if not e then
        e = { count = 0, loots = 0, skillStart = not ProfInfo(prof).anyone and FN.ProfessionSkill and FN.ProfessionSkill(prof) or nil }
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

-- AFK (by /afk or the game's own idle timer) pauses a running session; back again, it resumes,
-- but only a pause AFK made
local function AfkChanged()
    if not session.start or not UnitIsAFK then return end
    local away = UnitIsAFK("player") and true or false
    if away and not session.pausedAt then
        FN.SessionTogglePause()
        afkPaused = true
    elseif not away and afkPaused and session.pausedAt then
        FN.SessionTogglePause() -- clears afkPaused
    end
end

function FN.SessionAdd(npc, items) FN.SessionGather("skinning", npc, items) end

local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "PLAYER_LOGOUT") -- fires on a /reload as well as a real log out
pcall(ev.RegisterEvent, ev, "PLAYER_ENTERING_WORLD") -- and this one says which it was
pcall(ev.RegisterEvent, ev, "GET_ITEM_INFO_RECEIVED") -- loot names arriving after a skin
pcall(ev.RegisterEvent, ev, "SKILL_LINES_CHANGED") -- a skill point, or a new rank from a trainer
pcall(ev.RegisterEvent, ev, "PLAYER_FLAGS_CHANGED") -- going AFK or coming back
ev:SetScript("OnEvent", function(_, event, unit, isReload)
    if event == "PLAYER_FLAGS_CHANGED" then
        if unit == "player" then AfkChanged() end
        return
    end
    if event == "PLAYER_LOGOUT" then
        if FN.db then FN.db.liveSession = Snapshot() or recap end
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        local saved = FN.db and FN.db.liveSession
        if saved == nil then return end
        FN.db.liveSession = nil
        if not isReload then return end -- a real log in starts fresh
        if type(saved) == "table" and saved.ended then
            recap = saved
            FN.ShowTracker(true)
        else
            Restore(saved)
        end
        return
    end
    if event == "SKILL_LINES_CHANGED" then AlertIfCapped() end
    FN.UpdateTracker()
end)
