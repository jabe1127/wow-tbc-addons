-- Minimal WoW 2.5.x API stub for offline ThreatPulse testing (Lua 5.1).

local Stub = {}
_G.Stub = Stub

--------------------------------------------------------------------------------
-- Simulated clock
--------------------------------------------------------------------------------

Stub.now = 1000.0
function GetTime() return Stub.now end
function Stub.Advance(dt)
    Stub.now = Stub.now + dt
    for _, t in ipairs(Stub.tickers) do
        while Stub.now - t.last >= t.interval do
            t.last = t.last + t.interval
            t.fn()
        end
    end
    local i = 1
    while i <= #Stub.afters do
        local a = Stub.afters[i]
        if Stub.now >= a.at then
            table.remove(Stub.afters, i)
            a.fn()
        else
            i = i + 1
        end
    end
end

Stub.tickers = {}
Stub.afters = {}
C_Timer = {
    NewTicker = function(interval, fn)
        local t = { interval = interval, fn = fn, last = Stub.now }
        table.insert(Stub.tickers, t)
        return t
    end,
    After = function(dt, fn)
        table.insert(Stub.afters, { at = Stub.now + dt, fn = fn })
    end,
}

--------------------------------------------------------------------------------
-- bit ops (pure Lua 5.1)
--------------------------------------------------------------------------------

bit = {}
function bit.band(a, b)
    local r, p = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then r = r + p end
        a = math.floor(a / 2); b = math.floor(b / 2); p = p * 2
    end
    return r
end
function bit.bor(a, b, ...)
    local r, p = 0, 1
    while a > 0 or b > 0 do
        if a % 2 == 1 or b % 2 == 1 then r = r + p end
        a = math.floor(a / 2); b = math.floor(b / 2); p = p * 2
    end
    if select("#", ...) > 0 then return bit.bor(r, ...) end
    return r
end

COMBATLOG_OBJECT_AFFILIATION_MINE  = 0x1
COMBATLOG_OBJECT_AFFILIATION_PARTY = 0x2
COMBATLOG_OBJECT_AFFILIATION_RAID  = 0x4

--------------------------------------------------------------------------------
-- misc globals
--------------------------------------------------------------------------------

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function PlaySound(id, channel) Stub.lastSound = id; Stub.lastChannel = channel end
Stub.cvars = {}
function SetCVar(name, v) Stub.cvars[name] = v end
function GetCVar(name) return Stub.cvars[name] end
function GetCursorPosition() return 0, 0 end
SlashCmdList = {}
Stub.prints = {}
local rawprint = print
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    table.insert(Stub.prints, table.concat(parts, " "))
end
Stub.rawprint = rawprint

--------------------------------------------------------------------------------
-- Frames / regions
--------------------------------------------------------------------------------

local function noop() end
local Region = {}
Region.__index = function(t, k)
    local v = rawget(Region, k)
    if v then return v end
    return noop
end

function Region.new(kind, parent)
    local r = setmetatable({
        kind = kind, parent = parent, shown = true,
        w = 100, h = 20, text = "",
    }, Region)
    return r
end

function Region:SetSize(w, h) self.w, self.h = w, h end
function Region:SetWidth(w) self.w = w end
function Region:SetHeight(h) self.h = h end
function Region:GetWidth() return self.w end
function Region:GetHeight() return self.h end
function Region:Show() self.shown = true end
function Region:Hide() self.shown = false end
function Region:IsShown() return self.shown end
function Region:SetText(t) self.text = t end
function Region:GetText() return self.text end
function Region:GetCenter() return 512, 400 end
function Region:GetLeft() return 100 end
function Region:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Region:GetEffectiveScale() return 1 end
function Region:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
function Region:SetTextColor(r, g, b, a) self.tcolor = { r, g, b, a } end

local Frame = setmetatable({}, { __index = Region })
Frame.__index = function(t, k)
    local v = rawget(Frame, k) or rawget(Region, k)
    if v then return v end
    return noop
end

Stub.eventFrames = {}

function Frame.new(kind, parent)
    local f = setmetatable(Region.new(kind, parent), Frame)
    f.scripts = {}
    f.events = {}
    f.children = {}
    table.insert(Stub.eventFrames, f)
    return f
end

function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:RegisterEvent(e) self.events[e] = true end
function Frame:UnregisterEvent(e) self.events[e] = nil end
function Frame:CreateTexture() local t = Region.new("Texture", self) return t end
function Frame:CreateFontString() local t = Region.new("FontString", self) t.GetStringWidth = function() return 40 end return t end
function Frame:CreateAnimationGroup()
    local ag = Frame.new("AnimationGroup", self)
    ag.CreateAnimation = function() return Frame.new("Animation", ag) end
    ag.Play = noop; ag.Stop = noop
    return ag
end

function CreateFrame(kind, name, parent)
    local f = Frame.new(kind, parent)
    if name then _G[name] = f end
    return f
end

UIParent = Frame.new("Frame")
UIParent.w, UIParent.h = 1024, 768
ColorPickerFrame = Frame.new("Frame")
ColorPickerFrame.GetColorRGB = function() return 1, 0, 0 end
ColorPickerFrame.SetColorRGB = noop
OpacitySliderFrame = Frame.new("Slider")
OpacitySliderFrame.GetValue = function() return 0 end

function Stub.FireEvent(event, ...)
    for _, f in ipairs(Stub.eventFrames) do
        if f.events[event] and f.scripts.OnEvent then
            f.scripts.OnEvent(f, event, ...)
        end
    end
end

--------------------------------------------------------------------------------
-- World model
--------------------------------------------------------------------------------

Stub.units = {}   -- [token] = { name, class, guid, hostile, dead, target }
Stub.threat = {}  -- [guid][mobGUID] = { threat, isTanking }

function Stub.SetUnit(token, def) Stub.units[token] = def end
function Stub.Resolve(token)
    -- support chained "Xtarget" tokens one level deep
    local u = Stub.units[token]
    if u then return u end
    local base = token:match("^(.-)target$")
    if base then
        local bu = Stub.Resolve(base)
        if bu and bu.target then return Stub.units[bu.target] end
    end
    return nil
end

function UnitExists(t) return Stub.Resolve(t) ~= nil end
function UnitName(t) local u = Stub.Resolve(t) return u and u.name end
function UnitGUID(t) local u = Stub.Resolve(t) return u and u.guid end
function UnitClass(t) local u = Stub.Resolve(t) return u and u.name, u and u.class end
function UnitCanAttack(_, t) local u = Stub.Resolve(t) return u and u.hostile or false end
function UnitIsDeadOrGhost(t) local u = Stub.Resolve(t) return u and u.dead or false end
function UnitIsUnit(a, b)
    local ua, ub = Stub.Resolve(a), Stub.Resolve(b)
    return ua ~= nil and ua == ub
end
function IsInRaid() return false end
function GetNumGroupMembers() return Stub.groupSize or 0 end

function UnitDetailedThreatSituation(unit, mob)
    local u, m = Stub.Resolve(unit), Stub.Resolve(mob)
    if not u or not m then return nil end
    local byMob = Stub.threat[u.guid]
    local entry = byMob and byMob[m.guid]
    if not entry then return nil end
    local tankThreat = 0
    for guid, mobs in pairs(Stub.threat) do
        local e = mobs[m.guid]
        if e and e.isTanking then tankThreat = e.threat end
    end
    local rawPct = entry.rawPct
        or (tankThreat > 0 and (entry.threat / tankThreat * 100) or 100)
    return entry.isTanking or false, 1, rawPct, rawPct, entry.threat
end

Stub.cleu = nil
function CombatLogGetCurrentEventInfo() return unpack(Stub.cleu) end
function Stub.CLEU(...)
    Stub.cleu = { ... }
    Stub.FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
end

function PlaySoundFile(path, channel) Stub.lastSoundFile = path; Stub.lastChannel = channel end

function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
