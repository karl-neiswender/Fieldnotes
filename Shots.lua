local ADDON, FN = ...

-- /fn shots: the CurseForge gallery in one go, after Forever Goal Tracker's /goals shots. Each scene
-- is staged on the sample data (demo mode), given a moment for its slides and fades, and taken with
-- the game's Screenshot() as lossless TGA. Where the subject sat on screen (the map window with
-- the dock and its tabs, or a window) is saved in FieldnotesDB.shotRects, in screen pixels, so
-- tools/shots.py can crop each shot exactly after a /reload writes the saved variables.
-- Everything is put back after: the map settings, the dock, demo mode, the session.
--   /fn shots      every shot
--   /fn shots 03   just the one whose name starts with that

local SHOTS = {
    { file = "01-dashboard", map = 1426, prof = "all", lit = "mining", show = "account" },
    { file = "02-heat", map = 1434, prof = "skinning", mode = "heat", show = "account" },
    { file = "03-herbalism", map = 1429, prof = "herbalism", mode = "heat", show = "account", colors = "solar" },
    { file = "04-points", map = 1436, prof = "skinning", mode = "points", show = "account" },
    { file = "05-community", map = 1413, prof = "skinning", mode = "heat", show = "community", colors = "snowfall" },
    { file = "06-continent", map = 1415, prof = "skinning", mode = "heat", show = "account" },
    { file = "07-session", map = 1426, prof = "mining", mode = "spotlight", show = "account", session = true,
        subject = "tracker" },
    { file = "08-settings", map = 1426, prof = "fishing", mode = "heat", show = "account", settings = true },
    { file = "09-stats", subject = "stats" },
    { file = "10-share", subject = "share" },
}
FN.SHOTS = SHOTS

-- a frame's rectangle in screen pixels (left, bottom, right, top), from the top-left origin the
-- image uses: x from the left, y from the top
local function Pixels(f)
    if not (f and f:IsShown() and f:GetLeft()) then return nil end
    local s = f:GetEffectiveScale()
    local w, h = GetPhysicalScreenSize and GetPhysicalScreenSize()
    local uiH = UIParent:GetHeight() * UIParent:GetEffectiveScale()
    local k = (h and uiH > 0) and (h / uiH) or 1
    local top = (h or uiH) - f:GetTop() * s * k
    return { f:GetLeft() * s * k, top, f:GetRight() * s * k, (h or uiH) - f:GetBottom() * s * k }
end

local function Union(a, b)
    if not a then return b end
    if not b then return a end
    return { math.min(a[1], b[1]), math.min(a[2], b[2]), math.max(a[3], b[3]), math.max(a[4], b[4]) }
end

-- the map window, the dock and every tab on its rail
local function MapRect()
    local r = Pixels(WorldMapFrame.BorderFrame) or Pixels(WorldMapFrame)
    local ui = FN.MapUI
    if ui then
        r = Union(r, Pixels(ui.dock))
        r = Union(r, Pixels(ui.tab))
        for _, t in ipairs(ui.rail or {}) do r = Union(r, Pixels(t)) end
    end
    return r
end

local function Stage(shot)
    local s = FN.Map.S()
    if FN.HideTracker then FN.HideTracker() end
    if FN.StatsFrame and FN.StatsFrame() then FN.StatsFrame():Hide() end
    if FN.ShareFrame and FN.ShareFrame() then FN.ShareFrame():Hide() end
    if shot.map then
        s.on = true
        s.mode = shot.mode or "heat"
        s.show = shot.show or "account"
        s.colors = shot.colors or "thermal"
        s.when, s.leather, s.dots = 0, 0, false
        FN.db.settings.dockOpen = true
        if not WorldMapFrame:IsShown() then ToggleWorldMap() end
        WorldMapFrame:SetMapID(shot.map)
        FN.MapUI.OpenSettings(false)
        FN.MapUI.GoTo(shot.prof)
        FN.Map.SetLit(shot.lit)
        if shot.settings then FN.MapUI.OpenSettings(true) end
    elseif WorldMapFrame:IsShown() then
        ToggleWorldMap()
    end
    if shot.session then
        -- a staged session: skins, ore and cloth, about 42 minutes in
        FN.SessionEnd()
        FN.SessionStart()
        local function Gather(prof, n, item, each)
            for _ = 1, n do FN.SessionGather(prof, 0, { [item] = each }) end
        end
        Gather("skinning", 34, 2318, 2)
        Gather("mining", 9, 2770, 2)
        Gather("cloth", 12, 2589, 1)
        for _ = 1, 17 do FN.SessionGather("cloth", 0, {}) end
        FN.session.start = GetTime() - 2530
        FN.ShowTracker()
    end
    if shot.subject == "stats" then FN.ShowStats() end
    if shot.subject == "share" then FN.ShowShare() end
end

local function Subject(shot)
    if shot.subject == "tracker" then return Union(MapRect(), Pixels(FN.TrackerFrame and FN.TrackerFrame())) end
    if shot.subject == "stats" then return Pixels(FN.StatsFrame and FN.StatsFrame()) end
    if shot.subject == "share" then return Pixels(FN.ShareFrame and FN.ShareFrame()) end
    return MapRect()
end

function FN.TakeShots(only)
    local list = {}
    for _, shot in ipairs(SHOTS) do
        if not only or shot.file:sub(1, #only) == only then list[#list + 1] = shot end
    end
    if #list == 0 then FN.Print("No gallery shot starts with \"" .. tostring(only) .. "\".") return end
    if FN.shooting then FN.Print("Already taking screenshots.") return end
    if not Screenshot then FN.Print("This client can't take screenshots from an add-on.") return end
    if InCombatLockdown and InCombatLockdown() then FN.Print("Not in combat.") return end

    -- what to put back
    local saved = {}
    for k, v in pairs(FN.Map.S()) do saved[k] = v end
    local dockOpen, compact = FN.db.settings.dockOpen, FN.db.settings.trackerCompact
    local hadDemo = FN.db.settings.demo and FN.db.demo
    local getCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
    local setCVar = (C_CVar and C_CVar.SetCVar) or SetCVar
    local cvars = getCVar and { getCVar("screenshotFormat"), getCVar("screenshotQuality") } or {}
    if setCVar then
        pcall(setCVar, "screenshotFormat", "tga")
        pcall(setCVar, "screenshotQuality", "10")
    end
    if not hadDemo then FN.DemoLoad() end
    FN.db.settings.trackerCompact = false
    FN.db.shotRects = FN.db.shotRects or {}
    FN.shooting = true
    FN.Print("Taking " .. #list .. " screenshots. Keep the mouse off the map.")

    local function Finish()
        FN.shooting = nil
        FN.SessionEnd()
        local s = FN.Map.S()
        wipe(s)
        for k, v in pairs(saved) do s[k] = v end
        FN.db.settings.dockOpen, FN.db.settings.trackerCompact = dockOpen, compact
        FN.Map.SetLit(nil)
        FN.MapUI.OpenSettings(false)
        if FN.StatsFrame and FN.StatsFrame() then FN.StatsFrame():Hide() end
        if FN.ShareFrame and FN.ShareFrame() then FN.ShareFrame():Hide() end
        if not hadDemo then FN.DemoClear() end
        if setCVar then
            if cvars[1] then pcall(setCVar, "screenshotFormat", cvars[1]) end
            if cvars[2] then pcall(setCVar, "screenshotQuality", cvars[2]) end
        end
        FN.Map.Refresh()
        FN.Print("Done: " .. #list .. " screenshots. Type /reload (it saves where each subject sat), then tell Claude to process the shots.")
    end

    local function Step(i)
        local shot = list[i]
        if not shot then
            Finish()
            return
        end
        local ok, err = pcall(Stage, shot)
        if not ok then
            FN.Print("Shot " .. shot.file .. " could not be staged: " .. tostring(err))
        end
        -- let the dock slide, the tabs glide and the heat draw, then shoot
        C_Timer.After(i == 1 and 2.5 or 1.8, function()
            GameTooltip:Hide()
            local r = Subject(shot)
            if r then
                local w, h = GetPhysicalScreenSize and GetPhysicalScreenSize()
                FN.db.shotRects[shot.file] = string.format("%d,%d,%d,%d,%d,%d", r[1], r[2], r[3], r[4], w or 0, h or 0)
            end
            pcall(Screenshot)
            C_Timer.After(1.2, function() Step(i + 1) end)
        end)
    end
    Step(1)
end
