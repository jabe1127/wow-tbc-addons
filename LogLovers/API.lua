-- LogLovers API: the surface other addons in the family talk to.
--
-- PulseMeter owns the saved fights, ThreatPulse owns threat, LogLovers owns the
-- event log. None of them can rely on loading first, so this table is created by
-- whoever gets there first and only ever added to - never replaced.
local ADDON, NS = ...

_G.LogLoversAPI = _G.LogLoversAPI or {}
local API = _G.LogLoversAPI

-- never replace what another addon may already be relying on
API.version = API.version or 1
API.addonVersion = NS.VERSION

-- The namespace itself, for anything not covered below. Everything here is fair
-- game to call; everything else may move between versions.
_G.LogLovers = NS

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
-- LogLovers fires: SEGMENT_START, SEGMENT_END (both with the segment table).
function NS.On(event, fn)
    if type(event) ~= "string" or type(fn) ~= "function" then return false end
    NS.callbacks[event] = NS.callbacks[event] or {}
    table.insert(NS.callbacks[event], fn)
    return true
end
API.On = NS.On

-------------------------------------------------------------------------------
-- Fights
--
-- A fight's cross-addon identity is its wall-clock start (`startStamp`), NOT its
-- index: indices are per-session counters and will not line up between addons.
-------------------------------------------------------------------------------
function API.Fights()
    local out = {}
    for _, seg in ipairs(NS.segments or {}) do
        out[#out + 1] = {
            id = seg.id,                 -- pass this back, not startStamp
            startStamp = seg.startStamp, -- one-second resolution: not unique
            label = NS.SegmentLabel(seg),
            zone = seg.zone,
            index = seg.index,
            ended = seg.endTime ~= nil,
        }
    end
    return out
end

-- Accepts a fight id, a whole fight table, or (for convenience) a startStamp -
-- in which case the newest fight in that second wins.
local function findSegment(fight)
    if type(fight) == "table" then fight = fight.id or fight.startStamp end
    if fight == nil then return nil end
    local byStamp
    for _, s in ipairs(NS.segments or {}) do
        if s.id == fight then return s end
        if s.startStamp == fight then byStamp = s end
    end
    return byStamp
end
API.FindFight = findSegment

-- Records for one fight, oldest first. `mode` is one of the FIGHT_MODES keys
-- ("mine", "onme", "all"); omit it for everything. Returns nil when the live
-- buffer no longer covers that fight - it does not survive a reload.
function API.FightEvents(fight, mode)
    local seg = findSegment(fight)
    if not seg then return nil end

    local f = NS.DefaultFilterAll()
    local scope = (mode == "mine" or mode == "onme") and "me" or "all"
    for _, loc in ipairs(NS.LOCATIONS) do f.scopes[loc.key] = scope end
    f.direction = (mode == "mine" and "out") or (mode == "onme" and "in") or "both"

    -- segIndex is stamped on every record when it is parsed, so it is exact.
    -- Bounding by time as well used to admit the next pull's events, because
    -- the fight's measured duration and its first logged event come off
    -- different clocks.
    local out, seen = {}, false
    NS.BufferEach(function(rec)
        if rec.segIndex == seg.index then
            seen = true
            if NS.RecordPasses(rec, f) then out[#out + 1] = rec end
        end
    end)
    if not seen then return nil end
    return out
end

-- Plain text of one fight, for a meter that wants to show or export it.
function API.FightText(fight, mode)
    local recs = API.FightEvents(fight, mode)
    if not recs then return nil end
    local out = {}
    for _, rec in ipairs(recs) do out[#out + 1] = NS.ExportLine(rec) end
    return table.concat(out, "\n")
end

-------------------------------------------------------------------------------
-- Opening things
-------------------------------------------------------------------------------
-- Open the death/fight log on the death nearest a fight, in a given mode.
-- Returns false when there is no death in that fight to anchor on.
function API.OpenFightLog(fight, mode)
    local seg = fight and findSegment(fight) or nil
    local best
    for _, d in ipairs(NS.deaths or {}) do
        if not seg then best = d
        elseif d.segIndex == seg.index then best = d end
    end
    if not best then return false end
    NS.PopOutFightLog(best, mode or "all")
    return true
end

function API.OpenDeaths()
    NS.ToggleDeaths()
    return true
end

-------------------------------------------------------------------------------
-- Providers
--
-- Anything that can do something with a fight registers here, and LogLovers
-- renders a button for it. This is how ThreatPulse's "Threat replay" and
-- PulseMeter's own views appear without LogLovers knowing they exist.
--
--   LogLoversAPI.RegisterProvider{
--       key = "threat", label = "Threat replay",
--       show = function(fight) ThreatPulse.OpenReplay(fight) end,
--       canShow = function(fight) return true end,   -- optional
--   }
-------------------------------------------------------------------------------
API.providers = API.providers or {}

function API.RegisterProvider(p)
    if type(p) ~= "table" or type(p.key) ~= "string" or type(p.show) ~= "function" then
        return false
    end
    for i, existing in ipairs(API.providers) do
        if existing.key == p.key then API.providers[i] = p return true end
    end
    table.insert(API.providers, p)
    if NS.RefreshFightLogPopout then NS.RefreshFightLogPopout() end
    return true
end

function API.ProvidersFor(fight)
    local out = {}
    for _, p in ipairs(API.providers) do
        local ok = true
        if p.canShow then
            local safe, r = pcall(p.canShow, fight)
            ok = safe and r and true or false
        end
        if ok then out[#out + 1] = p end
    end
    return out
end
