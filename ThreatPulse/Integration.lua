-- ThreatPulse Integration.lua
-- Cross-addon wiring. Everything here is feature-detected: ThreatPulse runs
-- fully standalone, and lights up extra integration when PulseMeter/LogLovers
-- expose the hooks described in INTEGRATION.md.

local ADDON, TP = ...
local I = {}
TP.Integration = I

I.status = { feed = "own", dock = "standalone", mode = "pending" }

--------------------------------------------------------------------------------
-- 1) Combat log feed
-- Preferred: PulseMeter.RegisterLogConsumer(fn) — one marshalling call, shared
-- event ordering with PulseMeter/LogLovers.
-- Fallback: our own CLEU frame (correct, slightly redundant marshalling).
--------------------------------------------------------------------------------

local function AttachFeed()
    local PM = _G.PulseMeter
    if PM and type(PM.RegisterLogConsumer) == "function" then
        PM.RegisterLogConsumer(function(...)
            TP.LogThreat:OnCLEU(...)
        end)
        I.status.feed = "pulsemeter"
        return
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    f:SetScript("OnEvent", function()
        TP.LogThreat:OnCLEU(CombatLogGetCurrentEventInfo())
    end)
    I.feedFrame = f
    I.status.feed = "own"
end

--------------------------------------------------------------------------------
-- 2) Fight boundaries
-- Preferred: PulseMeter.RegisterFightListener({ onStart=fn, onEnd=fn }) so
-- ThreatPulse segments line up 1:1 with PulseMeter fights (including its
-- group-combat-state boss segmentation, which is better than ours).
-- Fallback: player combat state (already wired in LogThreat).
--------------------------------------------------------------------------------

local function AttachBoundaries()
    local PM = _G.PulseMeter
    if PM and type(PM.RegisterFightListener) == "function" then
        PM.RegisterFightListener({
            onStart = function(fight)
                TP.LogThreat.externalBoundaries = true
                TP.LogThreat:BeginSegment()
                if fight and fight.name and TP.LogThreat.current then
                    TP.LogThreat.current.name = fight.name
                end
            end,
            onEnd = function(fight)
                if fight and fight.name and TP.LogThreat.current then
                    TP.LogThreat.current.name = fight.name
                end
                TP.LogThreat:EndSegment()
            end,
        })
    end
end

--------------------------------------------------------------------------------
-- 3) Docking
-- Preferred: PulseMeter.Layout.RegisterWindow(frame, opts) — full member of
-- the dock system (edges, size match, gaps, swap, dock panel).
-- Fallback: free-floating with our own drag + saved position.
--------------------------------------------------------------------------------

local function AttachDock()
    local PM = _G.PulseMeter
    local Layout = PM and PM.Layout
    if Layout and type(Layout.RegisterWindow) == "function" and TP.UI.frame then
        Layout.RegisterWindow(TP.UI.frame, {
            id = "ThreatPulse",
            title = "Threat",
            matchSize = true,
        })
        TP.UI.frame.docked = true
        I.status.dock = "pulsemeter"
    end
end

--------------------------------------------------------------------------------
-- 4) Threat mode inside PulseMeter
-- Preferred: PulseMeter.RegisterExternalMode(spec). The spec below is the
-- contract; the PulseMeter-side shim is ~20 lines (see INTEGRATION.md).
--------------------------------------------------------------------------------

local function AttachMode()
    local PM = _G.PulseMeter
    if PM and type(PM.RegisterExternalMode) == "function" then
        PM.RegisterExternalMode({
            id    = "threat",
            name  = "Threat (est.)",
            -- Whole-group rows for the meter window
            GetRows = function()
                return TP.LogThreat:SourceRows()
            end,
            -- Drill-down: per-ability rows for one source
            GetDetail = function(guid)
                local rows, total, name = TP.LogThreat:AbilityRows(nil, guid)
                return rows, total, name
            end,
            -- Formatting hint for PulseMeter's renderer
            valueSuffix = " thr",
        })
        I.status.mode = "registered"
    else
        I.status.mode = "unavailable"
    end
end

--------------------------------------------------------------------------------
-- Boot: try at login, and retry once after a short delay in case PulseMeter
-- loads after us or builds its API lazily.
--------------------------------------------------------------------------------

TP.On("LOGIN", function()
    AttachFeed()
    AttachBoundaries()
    AttachDock()
    AttachMode()
    C_Timer.After(2, function()
        if I.status.mode == "unavailable" then AttachMode() end
        if I.status.dock == "standalone" then AttachDock() end
    end)
end)

-- Expose our API handle to the family, mirroring LogLovers.PulseMeter.
TP.On("LOGIN", function()
    local PM = _G.PulseMeter
    if PM then PM.ThreatPulse = TP end
    local LL = _G.LogLovers
    if LL then LL.ThreatPulse = TP end
end)
