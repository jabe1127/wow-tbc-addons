-- ThreatPulse LogThreat.lua
-- Per-ability threat ESTIMATION from the combat log. Powers the "which ability
-- generated how much threat" breakdown (surfaced as a PulseMeter mode when
-- available). Clearly an estimate: stances and talents are inferred, not read.

local ADDON, TP = ...
local LT = {}
TP.LogThreat = LT

local TV = nil -- bound on DB_READY (ThreatValues loads before us, but be safe)
TP.On("DB_READY", function() TV = TP.ThreatValues end)

local band = bit.band
local GROUP_MASK = bit.bor(
    COMBATLOG_OBJECT_AFFILIATION_MINE or 0x1,
    COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x2,
    COMBATLOG_OBJECT_AFFILIATION_RAID or 0x4
)

--------------------------------------------------------------------------------
-- Segments
--------------------------------------------------------------------------------

LT.segments   = {}     -- newest last; capped
LT.current    = nil
local MAX_SEGMENTS = 30

local function NewSegment()
    return {
        start   = GetTime(),
        stop    = nil,
        name    = nil,          -- stamped from PulseMeter fight name when available
        sources = {},           -- [srcGUID] = { name, class, total, abilities = { [spell] = { threat, count } } }
        mobs    = {},           -- [mobGUID] = lastSeen  (engaged-mob set for heal split)
        auras   = {},           -- [guid] = { [auraName] = true }
        tankFlag= {},           -- [guid] = true (warrior tank heuristic)
    }
end

function LT:BeginSegment()
    if self.current then self:EndSegment() end
    self.current = NewSegment()
end

function LT:EndSegment()
    local seg = self.current
    if not seg then return end
    seg.stop = GetTime()
    if next(seg.sources) then
        local list = self.segments
        list[#list + 1] = seg
        if #list > MAX_SEGMENTS then table.remove(list, 1) end
        TP.Fire("SEGMENT_ENDED", seg)
    end
    self.current = nil
end

-- Called by Integration when PulseMeter announces fight boundaries; also
-- driven by player combat state as a standalone fallback.
TP.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if not LT.externalBoundaries then LT:BeginSegment() end
end)
TP.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if not LT.externalBoundaries then LT:EndSegment() end
end)

--------------------------------------------------------------------------------
-- Accounting
--------------------------------------------------------------------------------

local function Source(seg, guid, name, class)
    local s = seg.sources[guid]
    if not s then
        s = { name = name, class = class, total = 0, abilities = {} }
        seg.sources[guid] = s
    end
    return s
end

local function Add(seg, guid, name, class, spell, amount)
    if amount == 0 then return end
    local s = Source(seg, guid, name, class)
    s.total = s.total + amount
    local a = s.abilities[spell]
    if not a then a = { threat = 0, count = 0 }; s.abilities[spell] = a end
    a.threat = a.threat + amount
    a.count  = a.count + 1
end

local function EngagedMobCount(seg)
    local now, n = GetTime(), 0
    for guid, t in pairs(seg.mobs) do
        if now - t < 12 then n = n + 1 else seg.mobs[guid] = nil end
    end
    return n > 0 and n or 1
end

local function Multiplier(seg, guid, class, school)
    local m = (TV.CLASS_MULT[class] or 1.0)
    local auras = seg.auras[guid]
    if auras then
        for aura in pairs(auras) do
            local def = TV.AURA_MULTIPLIERS[aura]
            if def and (def.school == "all" or def.school == school) then
                m = m * def.mult
            end
        end
    end
    if class == "WARRIOR" and seg.tankFlag[guid] and school == "physical" then
        m = m * TV.WARRIOR_TANK_MULT
    end
    return m
end

--------------------------------------------------------------------------------
-- CLEU handler
--------------------------------------------------------------------------------

-- Accepts the already-marshalled CLEU vararg (same shape PulseMeter/LogLovers
-- pass along their shared feed).
function LT:OnCLEU(timestamp, event, _, srcGUID, srcName, srcFlags, _,
                   dstGUID, dstName, dstFlags, _, ...)
    local seg = self.current
    if not seg or not TV then return end

    local srcIsGroup = srcGUID and band(srcFlags or 0, GROUP_MASK) ~= 0
    local dstIsGroup = dstGUID and band(dstFlags or 0, GROUP_MASK) ~= 0

    -- track engaged mobs (anything hostile trading damage with the group)
    if event:find("_DAMAGE", 1, true) then
        if srcIsGroup and dstGUID and not dstIsGroup then
            seg.mobs[dstGUID] = GetTime()
        elseif dstIsGroup and srcGUID and not srcIsGroup then
            seg.mobs[srcGUID] = GetTime()
        end
    end

    -- aura tracking for everyone in the group
    if (event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REMOVED") and dstIsGroup then
        local _, spellName = ...
        if TV.AURA_MULTIPLIERS[spellName] then
            local set = seg.auras[dstGUID]
            if not set then set = {}; seg.auras[dstGUID] = set end
            set[spellName] = (event == "SPELL_AURA_APPLIED") or nil
        end
        return
    end

    if not srcIsGroup then return end
    local info  = TP.rosterInfo[srcGUID]
    local class = info and info.class
    local name  = (info and info.name) or srcName

    if event == "SWING_DAMAGE" then
        local amount = ...
        Add(seg, srcGUID, name, class, "Melee",
            (amount or 0) * Multiplier(seg, srcGUID, class, "physical"))

    elseif event == "SPELL_DAMAGE" or event == "SPELL_PERIODIC_DAMAGE"
        or event == "RANGE_DAMAGE" then
        local spellId, spellName, spellSchool, amount = ...
        amount = amount or 0
        local school = (spellSchool == 1) and "physical"
            or (spellSchool == 2) and "holy" or "magic"
        local threat = amount * (TV.ABILITY_MULT[spellName] or 1.0)
        threat = threat + (TV.FLAT_ON_DAMAGE[spellName] or 0)
        Add(seg, srcGUID, name, class, spellName,
            threat * Multiplier(seg, srcGUID, class, school))

    elseif event == "SPELL_CAST_SUCCESS" then
        local spellId, spellName = ...
        if class == "WARRIOR" and TV.WARRIOR_TANK_FLAG_SPELLS[spellName] then
            seg.tankFlag[srcGUID] = true
        end
        local flat = TV.FLAT_ON_CAST[spellName]
        if flat and flat > 0 then
            Add(seg, srcGUID, name, class, spellName,
                flat * Multiplier(seg, srcGUID, class, "physical"))
        end
        local red = TV.REDUCERS[spellName]
        if red and red.flat then
            Add(seg, srcGUID, name, class, spellName, red.flat)
        elseif red and red.fraction then
            local s = seg.sources[srcGUID]
            if s then
                Add(seg, srcGUID, name, class, spellName, s.total * red.fraction)
            end
        end

    elseif event == "SPELL_HEAL" or event == "SPELL_PERIODIC_HEAL" then
        local spellId, spellName, _, amount, overheal = ...
        local effective = (amount or 0) - (overheal or 0)
        if effective > 0 then
            local threat = effective * TV.HEAL_FACTOR / EngagedMobCount(seg)
            Add(seg, srcGUID, name, class, spellName,
                threat * Multiplier(seg, srcGUID, class, "magic"))
        end

    elseif event == "SPELL_ENERGIZE" or event == "SPELL_PERIODIC_ENERGIZE" then
        local spellId, spellName, _, amount, _, powerType = ...
        amount = amount or 0
        local factor = (powerType == 0 and TV.MANA_FACTOR)
            or (powerType == 1 and TV.RAGE_FACTOR)
            or (powerType == 3 and TV.ENERGY_FACTOR) or 0
        if factor > 0 and amount > 0 then
            Add(seg, srcGUID, name, class, spellName .. " (resource)", amount * factor)
        end
    end
end

--------------------------------------------------------------------------------
-- Query API (consumed by the PulseMeter mode and by /tp debugging)
--------------------------------------------------------------------------------

-- Returns sorted rows for a segment (default: latest finished, else current):
-- { { name="Sunder Armor", threat=1234, count=8, pct=42.1 }, ... }, playerTotal
function LT:AbilityRows(seg, guid)
    seg = seg or self.segments[#self.segments] or self.current
    if not seg then return nil end
    guid = guid or UnitGUID("player")
    local src = seg.sources[guid]
    if not src then return nil end
    local rows = {}
    for spell, a in pairs(src.abilities) do
        rows[#rows + 1] = {
            name = spell, threat = a.threat, count = a.count,
            pct = src.total > 0 and (a.threat / src.total * 100) or 0,
        }
    end
    table.sort(rows, function(x, y) return x.threat > y.threat end)
    return rows, src.total, src.name
end

-- Per-source totals for a segment (whole-group view)
function LT:SourceRows(seg)
    seg = seg or self.segments[#self.segments] or self.current
    if not seg then return nil end
    local rows = {}
    for guid, s in pairs(seg.sources) do
        rows[#rows + 1] = { guid = guid, name = s.name, class = s.class, threat = s.total }
    end
    table.sort(rows, function(x, y) return x.threat > y.threat end)
    return rows
end
