-- ThreatPulse Core.lua
-- Namespace, saved variables, event dispatch, roster tracking, slash commands.

local ADDON, TP = ...
_G.ThreatPulse = TP
TP.version = "0.1.0"

--------------------------------------------------------------------------------
-- Defaults
--------------------------------------------------------------------------------

local DEFAULTS = {
    pos          = nil,       -- {point, x, y} when free-floating
    locked       = false,
    width        = 240,
    barHeight    = 18,
    barSpacing   = 2,
    maxBars      = 10,
    showTTP      = true,
    view         = "threat",  -- "threat" | "tank"
    autoTankView = true,      -- auto-switch to tank view while tanking

    useClassColors = true,     -- everyone else's bars use class colors
    selfBarMode    = "custom", -- "custom" (My bar swatch) | "class" | "gradient"

    palette = {
        windowBg  = { 0.055, 0.055, 0.075, 0.92 },
        border    = { 0.28,  0.28,  0.34,  1.00 },
        barBg     = { 0.10,  0.10,  0.135, 0.90 },
        text      = { 0.93,  0.93,  0.95,  1.00 },
        subText   = { 0.55,  0.55,  0.62,  1.00 },
        accent    = { 1.00,  0.30,  0.25,  1.00 }, -- aggro line, hot end, alerts
        cool      = { 0.30,  0.62,  0.95,  1.00 }, -- cold end of gradient
        selfBar   = { 1.00,  0.80,  0.22,  1.00 }, -- used when class colors off
        tankBar   = { 0.36,  0.78,  0.50,  1.00 },
        otherBar  = { 0.52,  0.52,  0.60,  1.00 },
    },

    warnings = {
        role         = "auto", -- auto | melee | ranged | tank
        warnPct      = 90,     -- warn at this % of YOUR aggro threshold
        tankWarnPct  = 90,     -- (tank view) warn when someone reaches this raw%
        sound        = true,
        flash        = true,
        splash       = true,
        soundKit     = 8959,   -- warn-line audio cue (Raid warning)
        volume       = 60,     -- alert volume 0-100 (drives the Dialog channel)
        aggroAlert   = true,   -- separate alert when you actually cross the aggro threshold
        aggroSoundKit= 12867,  -- aggro-crossing audio cue (Alarm)
        custom       = {},     -- { {pct=100, sound=true, flash=true, splash=true}, ... } raw% thresholds
    },
}

local function CopyDefaults(src, dst)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

--------------------------------------------------------------------------------
-- Event dispatcher
--------------------------------------------------------------------------------

TP.events = {}
local frame = CreateFrame("Frame")
TP.eventFrame = frame

function TP.RegisterEvent(event, fn)
    if not TP.events[event] then
        TP.events[event] = {}
        frame:RegisterEvent(event)
    end
    local t = TP.events[event]
    t[#t + 1] = fn
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = TP.events[event]
    if not list then return end
    for i = 1, #list do
        list[i](event, ...)
    end
end)

-- Internal message bus (module-to-module, no WoW events involved)
TP.callbacks = {}
function TP.On(msg, fn)
    local t = TP.callbacks[msg]
    if not t then t = {}; TP.callbacks[msg] = t end
    t[#t + 1] = fn
end
function TP.Fire(msg, ...)
    local t = TP.callbacks[msg]
    if not t then return end
    for i = 1, #t do t[i](...) end
end

--------------------------------------------------------------------------------
-- Roster
--------------------------------------------------------------------------------

TP.roster = {}          -- ordered unit tokens, "player" first
TP.rosterInfo = {}      -- [guid] = { name, class, unit }

function TP.RebuildRoster()
    local roster, info = TP.roster, TP.rosterInfo
    wipe(roster)
    wipe(info)

    local function add(unit, petOf)
        if UnitExists(unit) then
            roster[#roster + 1] = unit
            local guid = UnitGUID(unit)
            if guid then
                if petOf then
                    -- Pets carry their owner's class for coloring, and a flag
                    -- so the UI can render them as pets.
                    local ownerInfo = info[UnitGUID(petOf)]
                    info[guid] = {
                        name  = UnitName(unit),
                        class = ownerInfo and ownerInfo.class,
                        unit  = unit,
                        isPet = true,
                        owner = ownerInfo and ownerInfo.name,
                    }
                else
                    local _, class = UnitClass(unit)
                    info[guid] = { name = UnitName(unit), class = class, unit = unit }
                end
            end
        end
    end

    add("player")
    add("pet", "player")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local u = "raid" .. i
            if not UnitIsUnit(u, "player") then
                add(u)
                add("raidpet" .. i, u)
            end
        end
    else
        for i = 1, 4 do
            add("party" .. i)
            add("partypet" .. i, "party" .. i)
        end
    end
    TP.Fire("ROSTER_CHANGED")
end

--------------------------------------------------------------------------------
-- Role / aggro threshold
--------------------------------------------------------------------------------

local MELEE_CLASSES = { WARRIOR = true, ROGUE = true, PALADIN = true, SHAMAN = true, DRUID = true }

-- Returns the raw% at which the player pulls aggro: 110 melee, 130 ranged.
function TP.AggroThreshold()
    local role = TP.db.warnings.role
    if role == "melee" or role == "tank" then return 110 end
    if role == "ranged" then return 130 end
    -- auto: by class, plus range check against target when possible
    local _, class = UnitClass("player")
    if MELEE_CLASSES[class] then return 110 end
    return 130
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

TP.RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    ThreatPulseDB = CopyDefaults(DEFAULTS, ThreatPulseDB)
    TP.db = ThreatPulseDB
    TP.Fire("DB_READY")
end)

TP.RegisterEvent("PLAYER_LOGIN", function()
    TP.RebuildRoster()
    TP.Fire("LOGIN")
end)

TP.RegisterEvent("GROUP_ROSTER_UPDATE", TP.RebuildRoster)
TP.RegisterEvent("UNIT_PET", TP.RebuildRoster)

--------------------------------------------------------------------------------
-- Slash
--------------------------------------------------------------------------------

SLASH_THREATPULSE1 = "/threatpulse"
SLASH_THREATPULSE2 = "/tp"
SlashCmdList.THREATPULSE = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "options" or msg == "opt" or msg == "config" then
        TP.Fire("TOGGLE_OPTIONS")
    elseif msg == "lock" then
        TP.db.locked = not TP.db.locked
        print("|cffff4e42ThreatPulse|r window " .. (TP.db.locked and "locked." or "unlocked."))
    elseif msg == "tank" then
        TP.Fire("SET_VIEW", "tank")
    elseif msg == "threat" then
        TP.Fire("SET_VIEW", "threat")
    elseif msg == "test" then
        TP.Fire("TEST_WARNING")
    else
        TP.Fire("TOGGLE_WINDOW")
    end
end
