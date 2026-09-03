-- ThreatPulse ThreatAPI.lua
-- Live threat engine. Server-authoritative values via UnitDetailedThreatSituation,
-- polled on a light ticker plus event nudges. No estimation here — this is exact.

local ADDON, TP = ...
local Engine = {}
TP.Engine = Engine

local POLL_INTERVAL   = 0.25
local HISTORY_SECONDS = 6      -- rolling threat history per unit, feeds TTP

Engine.mobUnit  = nil
Engine.mobGUID  = nil
Engine.mobName  = nil
Engine.rows     = {}           -- sorted snapshot rows (tables reused)
Engine.rowCount = 0
Engine.history  = {}           -- [guid] = { first, head, [i] = {t, v} }
Engine.playerIsTanking = false
Engine.tankGUID = nil

local rowPool = setmetatable({}, { __index = function(t, i)
    local r = {}; rawset(t, i, r); return r
end })
local sortBuf = {}

--------------------------------------------------------------------------------
-- Mob resolution: which mob's threat table we display.
-- 1) your target, if attackable
-- 2) your target's target (you're targeting the tank)
-- 3) sticky: the previous mob, found via any group member's target
-- 4) any group member's attackable target
--------------------------------------------------------------------------------

local function Attackable(unit)
    return UnitExists(unit)
        and UnitCanAttack("player", unit)
        and not UnitIsDeadOrGhost(unit)
end

function Engine:ResolveMob()
    if Attackable("target") then return "target" end
    if Attackable("targettarget") then return "targettarget" end
    if self.mobGUID then
        for i = 1, #TP.roster do
            local tu = TP.roster[i] .. "target"
            if Attackable(tu) and UnitGUID(tu) == self.mobGUID then
                return tu
            end
        end
    end
    for i = 1, #TP.roster do
        local tu = TP.roster[i] .. "target"
        if Attackable(tu) then return tu end
    end
    return nil
end

--------------------------------------------------------------------------------
-- History (for TTP)
--------------------------------------------------------------------------------

local function PushHistory(self, guid, t, threat)
    local h = self.history[guid]
    if not h then h = { first = 1, head = 0 }; self.history[guid] = h end
    h.head = h.head + 1
    local slot = h[h.head]
    if slot then slot.t, slot.v = t, threat
    else h[h.head] = { t = t, v = threat } end
    local cutoff = t - HISTORY_SECONDS
    while h.first < h.head and h[h.first].t < cutoff do
        h.first = h.first + 1
    end
end

-- Linear threat/sec over stored history; nil until ~1s of data exists.
function Engine:Rate(guid)
    local h = self.history[guid]
    if not h or h.head == 0 then return nil end
    local a, b = h[h.first], h[h.head]
    if not a or not b or (b.t - a.t) < 1.0 then return nil end
    return (b.v - a.v) / (b.t - a.t)
end

--------------------------------------------------------------------------------
-- Snapshot
--------------------------------------------------------------------------------

function Engine:Snapshot()
    local mob = self:ResolveMob()
    self.rowCount = 0
    self.playerIsTanking = false
    self.tankGUID = nil

    if not mob then
        self.mobUnit, self.mobGUID, self.mobName = nil, nil, nil
        self.lastMobGUID = nil
        TP.Fire("THREAT_UPDATE", self)
        return
    end

    self.mobUnit = mob
    self.mobGUID = UnitGUID(mob)
    self.mobName = UnitName(mob)

    local now = GetTime()
    local n = 0
    local playerGUID = UnitGUID("player")
    local maxThreat = 0

    for i = 1, #TP.roster do
        local unit = TP.roster[i]
        local isTanking, _, scaledPct, rawPct, threat =
            UnitDetailedThreatSituation(unit, mob)
        if threat and threat > 0 then
            n = n + 1
            local row  = rowPool[n]
            local guid = UnitGUID(unit)
            local info = TP.rosterInfo[guid]
            row.unit      = unit
            row.guid      = guid
            row.name      = UnitName(unit)
            row.class     = (info and info.class) or select(2, UnitClass(unit))
            row.isPet     = info and info.isPet or false
            row.owner     = info and info.owner
            row.isTanking = isTanking and true or false
            row.apiRaw    = rawPct or 0   -- the API's number: relative to whoever
                                          -- the mob is attacking, so it inflates
                                          -- during fixates/swaps. Kept for debug.
            row.threat    = threat
            row.isPlayer  = (guid == playerGUID)
            if threat > maxThreat then maxThreat = threat end
            PushHistory(self, guid, now, threat)
            if row.isTanking then self.tankGUID = guid end
            if row.isPlayer and row.isTanking then self.playerIsTanking = true end
        end
    end

    -- Display reference: the TANKING unit's threat, so a climber reads 101%,
    -- 105%... right up to their 110/130 pull point. Exception: when the mob is
    -- on a low-threat unit (fixates, web wraps), "vs tank" would inflate the
    -- whole list (the 255% Crypt Fiend problem) — if the tanking unit holds
    -- less than half the leader's threat, normalize to the leader instead.
    local tankThreat = 0
    for i = 1, n do
        if rowPool[i].isTanking then tankThreat = rowPool[i].threat end
    end
    local ref = maxThreat
    if tankThreat > 0 and tankThreat >= maxThreat * 0.5 then
        ref = tankThreat
    end
    for i = 1, n do
        local row = rowPool[i]
        row.rawPct = ref > 0 and math.min(row.threat / ref * 100, 999) or 0
    end

    wipe(sortBuf)
    for i = 1, n do sortBuf[i] = rowPool[i] end
    table.sort(sortBuf, function(a, b)
        if a.threat ~= b.threat then return a.threat > b.threat end
        return (a.name or "") < (b.name or "")
    end)
    for i = 1, n do self.rows[i] = sortBuf[i] end
    self.rowCount = n

    -- Target switched to a different mob mid-combat: rates, TTP, and warning
    -- latches all refer to the old mob's threat table. Reset them.
    if self.mobGUID ~= self.lastMobGUID then
        wipe(self.history)
        self.lastMobGUID = self.mobGUID
        TP.Fire("MOB_CHANGED", self.mobName)
    end

    TP.Fire("THREAT_UPDATE", self)
end

function Engine:PlayerRow()
    for i = 1, self.rowCount do
        if self.rows[i].isPlayer then return self.rows[i] end
    end
end

function Engine:TankRow()
    for i = 1, self.rowCount do
        if self.rows[i].isTanking then return self.rows[i] end
    end
end

--------------------------------------------------------------------------------
-- Ticker + event nudges
--------------------------------------------------------------------------------

TP.On("LOGIN", function()
    Engine.ticker = C_Timer.NewTicker(POLL_INTERVAL, function()
        Engine:Snapshot()
    end)
end)

TP.RegisterEvent("PLAYER_TARGET_CHANGED", function() Engine:Snapshot() end)
TP.RegisterEvent("PLAYER_REGEN_ENABLED", function() wipe(Engine.history) end)
