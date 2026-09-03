-- ThreatPulse TTP.lua
-- Time-to-pull: given your threat-gain rate vs the tank's, roughly how many
-- seconds until you cross your aggro threshold. Smoothed with an EMA; treat it
-- as a trend gauge, not a countdown clock.

local ADDON, TP = ...
local TTP = {}
TP.TTP = TTP

local EMA_ALPHA = 0.30
local MAX_SHOWN = 30      -- beyond this we just say "Safe"

TTP.seconds = nil          -- smoothed estimate, nil = safe/unknown
TTP.raw     = nil

function TTP:Update(engine)
    local me   = engine:PlayerRow()
    local tank = engine:TankRow()

    if not me or not tank or me.isTanking then
        self.seconds, self.raw = nil, nil
        return
    end

    local myRate   = engine:Rate(me.guid)
    local tankRate = engine:Rate(tank.guid)
    if not myRate or not tankRate then
        self.seconds, self.raw = nil, nil
        return
    end

    local threshold = TP.AggroThreshold() / 100
    local ceiling   = tank.threat * threshold
    local gap       = ceiling - me.threat
    local closing   = myRate - tankRate * threshold

    if gap <= 0 then
        self.raw = 0
    elseif closing <= 0 then
        self.raw = nil                    -- not closing; safe
    else
        self.raw = gap / closing
    end

    if not self.raw or self.raw > MAX_SHOWN then
        self.seconds = nil
    elseif self.seconds then
        self.seconds = self.seconds + EMA_ALPHA * (self.raw - self.seconds)
    else
        self.seconds = self.raw
    end
end

-- Display string for the footer.
function TTP:Text()
    if not self.seconds then return "Safe" end
    if self.seconds <= 0.5 then return "PULLING NOW" end
    return string.format("Pulling in ~%.1fs", self.seconds)
end

function TTP:IsUrgent()
    return self.seconds ~= nil and self.seconds < 5
end

TP.On("THREAT_UPDATE", function(engine) TTP:Update(engine) end)
TP.On("MOB_CHANGED", function() TTP.seconds, TTP.raw = nil, nil end)
