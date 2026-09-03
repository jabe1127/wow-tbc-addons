-- Silk : Group ------------------------------------------------------------
-- Party (party1-4) and raid (raid1-40) as pre-built secure cells driven by
-- RegisterUnitWatch, so show/hide stays combat-legal. Layout re-sorts by
-- subgroup out of combat and defers gracefully while fighting. Dispellable
-- debuffs tint the cell outline; out-of-range members fade.

local ADDON, ns = ...

ns.groupCells = { party = {}, raid = {} }

-- anchors -----------------------------------------------------------------

local function MakeAnchor(name)
    local a = CreateFrame("Frame", name, UIParent)
    a:SetSize(120, 18)
    a:SetMovable(true)
    a:SetClampedToScreen(true)
    return a
end

ns.PartyAnchor = MakeAnchor("SilkPartyAnchor")
ns.RaidAnchor  = MakeAnchor("SilkRaidAnchor")

-- cell updates ------------------------------------------------------------

local function cellCfg(f)
    return ns.db[f.kind]
end

local function CellHealth(f, instant)
    local unit = f.unit
    if not UnitExists(unit) then return end
    local cfg = cellCfg(f)
    local m = UnitHealthMax(unit)
    if not m or m <= 0 then m = 1 end
    local v = UnitHealth(unit) or 0
    local pct = v / m
    f.bar.health:SetStatusColor(ns.HealthColor(unit, pct))

    local txt = ""
    if not UnitIsConnected(unit) then
        txt = "off"
        v = m
    elseif UnitIsGhost(unit) then
        txt = "ghost"
        v = 0
    elseif UnitIsDead(unit) then
        txt = "dead"
        v = 0
    else
        local mode = (f.kind == "raid") and cfg.text or "percent"
        if mode == "percent" then
            local p = math.floor(pct * 100 + 0.5)
            if p < 100 then txt = p .. "%" end
        elseif mode == "deficit" then
            local d = m - v
            if d > 0 then txt = "-" .. ns.Short(d) end
        elseif mode == "current" then
            txt = ns.Short(v)
        end
    end
    ns.Text(f.status, txt)

    if instant then
        f.bar.health:SetInstant(v, m)
    else
        f.bar.health:SetValue(v, m)
    end
end

local function CellPower(f, instant)
    local unit = f.unit
    if not cellCfg(f).power then return end
    if not UnitExists(unit) then return end
    local m = UnitPowerMax(unit)
    if not m or m <= 0 then
        f.bar:ShowPower(false)
        return
    end
    f.bar:ShowPower(true)
    local v = UnitPower(unit) or 0
    f.bar.power:SetStatusColor(ns.PowerColor(unit))
    if instant then
        f.bar.power:SetInstant(v, m)
    else
        f.bar.power:SetValue(v, m)
    end
end

-- The one place a cell's alpha is decided. Refreshes apply the CURRENT
-- decision instead of blasting everything back to full -- which was making
-- out-of-range members strobe every time a roster event refreshed the grid.
-- Only the ticker probes UnitInRange, and it takes two consecutive
-- out-of-range readings before fading, so someone strafing along the range
-- boundary doesn't flicker.
local function CellAlphaNow(f)
    if f.rosterOnly then return 0.55 end
    if f.faded then
        local cfg = cellCfg(f)
        return (cfg.rangeAlpha ~= nil and cfg.rangeAlpha) or 0.45
    end
    return 1
end

local function CellName(f)
    local unit = f.unit
    if not UnitExists(unit) then return end
    local nm = UnitName(unit) or ""
    if nm == "" and f.lastName then nm = f.lastName end
    f.lastName = nm ~= "" and nm or f.lastName
    local cfg = cellCfg(f)
    local maxLen = (f.kind == "raid") and (cfg.nameLen or 0) or 0
    if maxLen > 0 and #nm > maxLen then
        nm = nm:sub(1, maxLen)
    end
    ns.Text(f.name, nm)
    local tc = (cfg.texts or {}).name
    ns.TextColor(f.name, tc, ns.NameColor(unit))
end

-- A resurrection on the way is the one thing a healer must see at a glance:
-- it decides whether to spend another combat res or move on. The badge sits
-- centered and breathes gently so it reads even in a wall of red bars.
local function UpdateResBadge(f)
    local badge = f.resBadge
    if not badge then return end
    local cfg = cellCfg(f)
    local want = cfg.resBadge ~= false
        and UnitExists(f.unit)
        and UnitHasIncomingResurrection
        and select(2, pcall(UnitHasIncomingResurrection, f.unit)) and true or false
    if want then
        badge:Show()
        if not badge.pulsing then
            badge.pulsing = true
            badge.t = 0
            badge:SetScript("OnUpdate", function(b, dt)
                b.t = b.t + dt * 3.2
                b:SetAlpha(0.78 + 0.22 * math.abs(math.sin(b.t)))
            end)
        end
    else
        if badge.pulsing then
            badge.pulsing = false
            badge:SetScript("OnUpdate", nil)
        end
        badge:Hide()
    end
end

-- One decision for the cell's border. Aggro outranks a dispellable debuff:
-- a healer can cleanse a poison two seconds late, but a clothie holding
-- threat is about to be a corpse. Tanking pulses red; merely insecure holds
-- steady amber; then the dispel colour; then whatever the profile says.
local THREAT_TANKING  = { 0.92, 0.30, 0.26 }
local THREAT_INSECURE = { 0.98, 0.62, 0.20 }

local function cellThreat(f)
    local cfg = cellCfg(f)
    if cfg.threat == false or not UnitThreatSituation then return 0 end
    local ok, lvl = pcall(UnitThreatSituation, f.unit)
    if not ok or type(lvl) ~= "number" then return 0 end
    return lvl
end

local function ApplyCellBorder(f)
    local cfg = cellCfg(f)
    local unit = f.unit

    local lvl = cellThreat(f)
    if lvl >= 3 then
        f.bar:SetOutlineColor(THREAT_TANKING[1], THREAT_TANKING[2], THREAT_TANKING[3], 1)
        if not f.bar.threatPulse then
            f.bar.threatPulse = true
            f.bar.tpT = 0
            f.bar:SetScript("OnUpdate", function(b, dt)
                b.tpT = b.tpT + dt * 4
                local k = 0.72 + 0.28 * math.abs(math.sin(b.tpT))
                b.outline:SetVertexColor(THREAT_TANKING[1] * k + (1 - k) * 0.3,
                    THREAT_TANKING[2] * k, THREAT_TANKING[3] * k, 1)
            end)
        end
        return
    end
    if f.bar.threatPulse then
        f.bar.threatPulse = nil
        f.bar:SetScript("OnUpdate", nil)
    end
    if lvl == 2 then
        f.bar:SetOutlineColor(THREAT_INSECURE[1], THREAT_INSECURE[2], THREAT_INSECURE[3], 1)
        return
    end

    if not (f.kind == "raid" and not cfg.dispel) then
        local found
        for i = 1, 16 do
            local name, _, _, dtype = UnitDebuff(unit, i)
            if not name then break end
            if dtype and ns.CanDispel(dtype) then
                found = dtype
                break
            end
        end
        if found and DebuffTypeColor and DebuffTypeColor[found] then
            local c = DebuffTypeColor[found]
            f.bar:SetOutlineColor(c.r, c.g, c.b, 0.95)
            return
        end
    end
    f.bar:SetOutlineColor(nil)
end

local CellDispel = ApplyCellBorder

-- returns true when this cell's token now refers to a different player
local function cellSwapped(f)
    local guid = UnitExists(f.unit) and UnitGUID(f.unit) or nil
    if guid ~= f.lastGUID then
        f.lastGUID = guid
        return true
    end
    return false
end

-- Someone the roster lists but whose unit token will not resolve. Rather than
-- leave their place empty -- which is what was happening all night -- give
-- them a real cell built from roster data and dim it, so the slot is filled
-- and it's obvious that person's data isn't coming through.
local function CellRosterOnly(f)
    local name, _, _, _, _, fileName, _, online = GetRaidRosterInfo(f.index)
    name = name or f.holdName or f.lastName
    f.holdName = name
    ns.Text(f.name, name or "?")
    local c = fileName and RAID_CLASS_COLORS and RAID_CLASS_COLORS[fileName]
    if c then
        f.name:SetTextColor(c.r * 0.75, c.g * 0.75, c.b * 0.75)
    else
        f.name:SetTextColor(0.60, 0.63, 0.69)
    end
    ns.Text(f.status, online == false and "offline" or "away")
    f.bar.health:SetStatusColor(0.26, 0.28, 0.33)
    f.bar.health:SetInstant(1, 1)
    f.bar:ShowPower(false)
    if f.bar.threatPulse then
        f.bar.threatPulse = nil
        f.bar:SetScript("OnUpdate", nil)
    end
    f.bar:SetOutlineColor(nil)
    if f.debuffC then f.debuffC:HideAll() end
    f:SetAlpha(0.55)
end

local function CellFull(f)
    if f.kind == "raid" and f.seated and not UnitExists(f.unit) then
        f.rosterOnly = true
        if f.resBadge then f.resBadge:Hide() end
        return CellRosterOnly(f)
    end
    f.rosterOnly = nil
    f.holdName = nil
    f:SetAlpha(CellAlphaNow(f))
    UpdateResBadge(f)
    if not UnitExists(f.unit) then return end
    CellName(f)
    CellHealth(f, true)
    CellPower(f, true)
    CellDispel(f)
    if f.debuffC then f.debuffC:Update() end
end

local cellHandlers = {
    UNIT_HEALTH = function(f, u) if u == f.unit then CellHealth(f) end end,
    UNIT_MAXHEALTH = function(f, u) if u == f.unit then CellHealth(f) end end,
    UNIT_POWER_UPDATE = function(f, u) if u == f.unit then CellPower(f) end end,
    UNIT_MAXPOWER = function(f, u) if u == f.unit then CellPower(f) end end,
    UNIT_DISPLAYPOWER = function(f, u) if u == f.unit then CellPower(f) end end,
    UNIT_NAME_UPDATE = function(f, u) if u == f.unit then CellName(f) end end,
    UNIT_THREAT_SITUATION_UPDATE = function(f, u)
        if u == f.unit then ApplyCellBorder(f) end
    end,
    INCOMING_RESURRECT_CHANGED = function(f, u)
        if u == f.unit then UpdateResBadge(f) end
    end,
    UNIT_CONNECTION = function(f, u)
        if u == f.unit then
            CellHealth(f)
            CellPower(f)
        end
    end,
    UNIT_AURA = function(f, u)
        if u ~= f.unit then return end
        CellDispel(f)
        if f.debuffC then f.debuffC:Update() end
    end,
    PLAYER_ENTERING_WORLD = function(f) CellFull(f) end,
}
cellHandlers.UNIT_HEALTH_FREQUENT = cellHandlers.UNIT_HEALTH
cellHandlers.UNIT_POWER_FREQUENT = cellHandlers.UNIT_POWER_UPDATE

-- cell construction -------------------------------------------------------

local function SpawnCell(kind, index)
    local unit = kind .. index
    local f = CreateFrame("Button", "Silk" .. kind .. index, UIParent, "SecureUnitButtonTemplate")
    f.kind, f.unit, f.index = kind, unit, index
    f:SetAttribute("unit", unit)
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")
    f:RegisterForClicks("AnyUp")
    f:SetFrameStrata("LOW")

    f.bar = ns.CreateUnitBar(f)
    f.health = f.bar.health
    f.power = f.bar.power

    local bl = CreateFrame("Frame", nil, f)
    bl:SetAllPoints(f)
    bl:SetFrameLevel(f:GetFrameLevel() + 9)
    local tl = CreateFrame("Frame", nil, f)
    tl:SetAllPoints(f)
    tl:SetFrameLevel(f:GetFrameLevel() + 10)
    f.name = ns.NewText(tl)
    f.status = ns.NewText(tl)
    ns.AttachTextBg(f.name, bl)
    ns.AttachTextBg(f.status, bl)

    local badge = CreateFrame("Frame", nil, tl)
    badge:SetPoint("CENTER", f, "CENTER", 0, 0)
    local bt = badge:CreateTexture(nil, "OVERLAY")
    bt:SetAllPoints()
    bt:SetTexture(ns.TEX.res)
    badge:Hide()
    f.resBadge = badge

    if kind == "party" then
        f.debuffC = ns.AttachAuras(f, unit, "MINI", function()
            local c = ns.db.party
            return { enabled = (c.debuffIcons or 0) > 0, mini = true, spacing = 3,
                     size = math.max(14, c.h - 14), maxShown = c.debuffIcons }
        end)
    end

    f:SetScript("OnEnter", function(s)
        GameTooltip_SetDefaultAnchor(GameTooltip, s)
        GameTooltip:SetUnit(s.unit)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f:SetScript("OnEvent", function(s, event, a1)
        local h = cellHandlers[event]
        if not h then return end
        -- if the token was remapped since the last event, rebuild instead of
        -- animating from the previous occupant's numbers
        if cellSwapped(s) then
            if UnitExists(s.unit) then CellFull(s) end
            return
        end
        h(s, a1)
    end)
    ns.RegSafe(f, "UNIT_HEALTH", unit)
    ns.RegSafe(f, "INCOMING_RESURRECT_CHANGED", unit)
    ns.RegSafe(f, "UNIT_THREAT_SITUATION_UPDATE", unit)
    ns.RegSafe(f, "UNIT_HEALTH_FREQUENT", unit)
    ns.RegSafe(f, "UNIT_MAXHEALTH", unit)
    ns.RegSafe(f, "UNIT_POWER_UPDATE", unit)
    ns.RegSafe(f, "UNIT_POWER_FREQUENT", unit)
    ns.RegSafe(f, "UNIT_MAXPOWER", unit)
    ns.RegSafe(f, "UNIT_DISPLAYPOWER", unit)
    ns.RegSafe(f, "UNIT_NAME_UPDATE", unit)
    ns.RegSafe(f, "UNIT_CONNECTION", unit)
    ns.RegSafe(f, "UNIT_AURA", unit)
    pcall(f.RegisterEvent, f, "PLAYER_ENTERING_WORLD")

    f:SetScript("OnShow", CellFull)
    return f
end

-- sizing ------------------------------------------------------------------

local function ApplyCell(f)
    local cfg = cellCfg(f)
    local db = ns.db
    f:SetScale(db.scale or 1)
    f:SetSize(cfg.w, cfg.h)

    f.bar:ClearAllPoints()
    f.bar:SetAllPoints(f)
    f.bar:SetPowerHeight(4)
    f.bar:ShowPower(cfg.power and true or false)
    f.bar:ApplyStyle()

    local tc = cfg.texts or {}
    local tn, ts = tc.name or {}, tc.status or {}
    local nx, ny = tn[1] or 0, tn[2] or 0
    local sx, sy = ts[1] or 0, ts[2] or 0

    f.name:ClearAllPoints()
    f.status:ClearAllPoints()
    if f.kind == "party" then
        f.name:SetPoint("LEFT", f.bar, "LEFT", 9 + nx, ny)
        f.name:SetWidth(cfg.w * 0.52)
        f.name:SetJustifyH("LEFT")
        local delta = (f.kind == "raid") and (cfg.fontDelta or 0) or 0
    ns.SetFont(f.name, -1 + delta + (tn.size or 0), tn)
        f.status:SetPoint("RIGHT", f.bar, "RIGHT", -9 + sx, sy)
        ns.SetFont(f.status, -2 + delta + (ts.size or 0), ts)
    else
        f.name:SetPoint("TOP", f.bar, "TOP", nx, -3 + ny)
        f.name:SetWidth(cfg.w - 8)
        f.name:SetJustifyH("CENTER")
        ns.SetFont(f.name, -2 + (tn.size or 0), tn)
        f.status:SetPoint("BOTTOM", f.bar, "BOTTOM", sx, 3 + sy)
        ns.SetFont(f.status, -3 + (ts.size or 0), ts)
    end
    local p = ns.palette.text
    ns.TextColor(f.status, ts, p[1], p[2], p[3])
    f.name.__cfg, f.status.__cfg = tn, ts
    if tn.show == false then f.name:Hide() else f.name:Show() end
    if ts.show == false then f.status:Hide() else f.status:Show() end
    ns.RefreshTextBg(f.name, tn)
    ns.RefreshTextBg(f.status, ts)
    if ns.SyncHaloText then
        ns.SyncHaloText(f.name)
        ns.SyncHaloText(f.status)
    end
    if f.resBadge then
        local bs = math.max(12, math.min(20, math.floor(cfg.h * 0.55)))
        f.resBadge:SetSize(bs, bs)
    end
    if f.debuffC then f.debuffC:Reanchor() end
end

-- visibility + layout -----------------------------------------------------

local function setWatch(f, want)
    if want then
        if not f.watched then
            RegisterUnitWatch(f)
            f.watched = true
        end
    else
        if f.watched then
            UnregisterUnitWatch(f)
            f.watched = false
        end
        f:Hide()
    end
end

-- How many raid seats to lay out. Generous on purpose: the roster count and
-- any token that resolves beyond it both count, so a seat is never lost to a
-- disagreement between the two.
local function RaidSeatCountImpl()
    if not ns.db.raid.enabled or not ns.InRaid() then return 0 end
    local n = 0
    if GetNumGroupMembers then
        local ok, c = pcall(GetNumGroupMembers)
        if ok and type(c) == "number" then n = c end
    end
    for i = 1, 40 do
        if UnitExists("raid" .. i) or GetRaidRosterInfo(i) then
            if i > n then n = i end
        end
    end
    return math.min(n, 40)
end

-- Raid cells deliberately do NOT use RegisterUnitWatch. The watch hides a cell
-- the moment its unit token stops resolving, and because repositioning secure
-- frames is blocked in combat, the layout could not close the gap that left --
-- so a raider disconnecting mid-fight punched a hole for the rest of the
-- fight. Instead seats are allocated out of combat and then held: during
-- combat the visible set is frozen, and a token that vanishes simply turns its
-- cell into a placeholder. Nothing moves, so nothing can gap.
local function ApplyRaidSeats()
    if InCombatLockdown() then return false end
    local n = RaidSeatCountImpl()
    for i = 1, 40 do
        local f = ns.groupCells.raid[i]
        if f.watched then
            UnregisterUnitWatch(f)
            f.watched = false
        end
        local want = (i <= n)
        f.seated = want
        if f:IsShown() ~= want then
            if want then f:Show() else f:Hide() end
        end
    end
    return true
end
ns.ApplyRaidSeats = ApplyRaidSeats

local function UpdateVisibility()
    local pc = ns.db.party
    local wantParty = pc.enabled and not (ns.InRaid() and pc.hideInRaid)
    for i = 1, 4 do
        setWatch(ns.groupCells.party[i], wantParty)
    end
    ApplyRaidSeats()
end

-- Cells hang off the anchor in whichever direction the profile asks for, so
-- the block can be tucked into any screen corner without running off-screen.
local function PlaceCell(f, anchor, cfg, x, y)
    local left = (cfg.growX ~= "left")
    local down = (cfg.growY ~= "up")
    local hx = left and "LEFT" or "RIGHT"
    local cellPoint = (down and "TOP" or "BOTTOM") .. hx
    local relPoint  = (down and "BOTTOM" or "TOP") .. hx
    f:ClearAllPoints()
    f:SetPoint(cellPoint, anchor, relPoint, left and x or -x, down and -y or y)
end
ns.PlaceCell = PlaceCell

local function PartyCellOffset(cfg, i)
    local step = i - 1
    if cfg.orient == "horizontal" then
        return step * (cfg.w + cfg.spacing), 0
    end
    return 0, step * (cfg.h + cfg.spacing)
end

local function LayoutParty()
    local cfg = ns.db.party
    for i = 1, 4 do
        local x, y = PartyCellOffset(cfg, i)
        PlaceCell(ns.groupCells.party[i], ns.PartyAnchor, cfg, x, y)
    end
end


local function RaidCellOffset(cfg, sub, slot)
    local per = math.max(1, cfg.groupsPerRow or 8)
    local col = (sub - 1) % per
    local blk = math.floor((sub - 1) / per)
    -- positive magnitudes; PlaceCell applies the direction
    return col * (cfg.w + cfg.spacing),
        blk * (5 * (cfg.h + cfg.spacing) + 10) + (slot - 1) * (cfg.h + cfg.spacing)
end
ns.RaidCellOffset = RaidCellOffset

-- Positions used to be handed out to all forty indices regardless of whether
-- a unit was actually behind them, while visibility was decided separately by
-- UnitExists. Any cell that got a slot but wasn't shown punched a hole in its
-- group. Occupied cells now pack from slot one, so an empty cell can never
-- reserve a space.
local function LayoutRaid()
    local cfg = ns.db.raid
    local inRaid = ns.InRaid()
    local counts = {}

    local function subgroupOf(i)
        if inRaid then
            local _, _, s = GetRaidRosterInfo(i)
            if s and s >= 1 then return s end
        end
        return math.ceil(i / 5)
    end

    -- pass one: every allocated seat, packed from slot 1. Seats are allocated
    -- out of combat and held, so this can never leave a gap.
    for i = 1, 40 do
        local f = ns.groupCells.raid[i]
        if f.seated then
            local sub = subgroupOf(i)
            counts[sub] = (counts[sub] or 0) + 1
            f.group, f.slot = sub, counts[sub]
            PlaceCell(f, ns.RaidAnchor, cfg, RaidCellOffset(cfg, sub, counts[sub]))
        else
            f.group, f.slot = nil, nil
        end
    end

    -- pass two: park the empty ones after their group's occupied cells, so a
    -- unit that appears mid-combat lands somewhere sensible rather than on
    -- top of somebody else
    for i = 1, 40 do
        local f = ns.groupCells.raid[i]
        if not f.slot then
            local sub = subgroupOf(i)
            counts[sub] = (counts[sub] or 0) + 1
            PlaceCell(f, ns.RaidAnchor, cfg, RaidCellOffset(cfg, sub, counts[sub]))
        end
    end
end

-- A cell's shown state is driven by the secure unit watch, which reacts to
-- things that never produce a roster event -- a member going offline, zoning,
-- or a token briefly failing to resolve. Layout used to recompute only on
-- roster events, so a cell could vanish afterwards and leave the hole its slot
-- was reserving. Any change in visibility now asks for a fresh layout.
local layoutDirty, layoutPending, layoutQueuedForCombat = false, false, false

local function RequestRaidLayout()
    layoutDirty = true
    if layoutPending then return end
    layoutPending = true
    -- debounce: a roster change fires a burst of show/hide in one frame
    C_Timer.After(0.05, function()
        layoutPending = false
        if not layoutDirty then return end
        if InCombatLockdown() then
            -- repositioning is protected; catch it the moment combat ends
            if not layoutQueuedForCombat then
                layoutQueuedForCombat = true
                ns.AfterCombat(function()
                    layoutQueuedForCombat = false
                    layoutDirty = false
                    LayoutRaid()
                end)
            end
            return
        end
        layoutDirty = false
        if ns.ReconcileRaid then ns.ReconcileRaid() end
        LayoutRaid()
    end)
end
ns.RequestRaidLayout = RequestRaidLayout

-- A cell's shown state is driven by the secure unit watch, which can go stale
-- when tokens shift around. Out of combat we can compare it against reality
-- and nudge the watch into re-evaluating.
local lastOccupancy
local function OccupancySignature()
    local t = {}
    for i = 1, 40 do
        local f = ns.groupCells.raid[i]
        t[i] = (f.seated and "S" or "-") .. (f:IsShown() and "1" or "0")
    end
    return table.concat(t) .. ":" .. tostring(RaidSeatCountImpl())
end

function ns.RaidOccupancyChanged()
    local sig = OccupancySignature()
    if sig ~= lastOccupancy then
        lastOccupancy = sig
        return true
    end
    return false
end

local function ReconcileRaid()
    if not ns.db.raid.enabled then return 0 end

    -- Safe in combat: text, colours and bar values are not protected. This is
    -- what turns a cell whose raider just dropped into a placeholder instead
    -- of leaving it showing a stale player.
    for i = 1, 40 do
        local f = ns.groupCells.raid[i]
        if f.seated then
            if UnitExists(f.unit) then
                if f.rosterOnly then CellFull(f) end
            elseif not f.rosterOnly then
                f.rosterOnly = true
                CellRosterOnly(f)
            end
        end
    end

    if InCombatLockdown() then return 0 end

    -- Out of combat the seat count can change, which is the only thing that
    -- needs frames moved.
    local before = 0
    for i = 1, 40 do
        if ns.groupCells.raid[i].seated then before = before + 1 end
    end
    ApplyRaidSeats()
    local after = 0
    for i = 1, 40 do
        local f = ns.groupCells.raid[i]
        if f.seated then
            after = after + 1
            if UnitExists(f.unit) then CellFull(f) end
        end
    end
    if before ~= after then
        LayoutRaid()
        return math.abs(after - before)
    end
    return 0
end
ns.ReconcileRaid = ReconcileRaid

-- Party cells hide in a raid, but that decision was only revisited on roster
-- events, so joining a raid mid-fight could leave them on screen indefinitely.
local function ReconcileParty()
    if InCombatLockdown() then return 0 end
    local pc = ns.db.party
    local want = pc.enabled and not (ns.InRaid() and pc.hideInRaid)
    local fixed = 0
    for i = 1, 4 do
        local f = ns.groupCells.party[i]
        local watched = f.watched and true or false
        if watched ~= want then
            setWatch(f, want)
            fixed = fixed + 1
        elseif not want and f:IsShown() then
            f:Hide()
            fixed = fixed + 1
        end
    end
    return fixed
end
ns.ReconcileParty = ReconcileParty

-- Reports what the roster says versus what is actually on screen.
function ns.RaidReport()
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    ns.Print(("--- raid report --- roster says |cff9be8ff%d|r members, |cff9be8ff%d|r seats allocated")
        :format(n, RaidSeatCountImpl()))
    local shown, tokens, problems = 0, 0, 0
    for i = 1, 40 do
        local f = ns.groupCells.raid[i]
        local rosterName = ns.InRaid() and GetRaidRosterInfo(i) or nil
        local exists = UnitExists(f.unit)
        local vis = f:IsShown()
        if exists then tokens = tokens + 1 end
        if vis then shown = shown + 1 end
        if (f.seated and not vis) or (vis and not f.seated) or (f.seated and not exists) then
            problems = problems + 1
            ns.Print(("  raid%d: roster=%s  unit=%s  seated=%s  shown=%s  group=%s slot=%s%s")
                :format(i, tostring(rosterName), tostring(exists), tostring(f.seated),
                        tostring(vis), tostring(f.group), tostring(f.slot),
                        f.rosterOnly and "  |cffffd166(placeholder)|r" or ""))
        end
    end
    ns.Print(("unit tokens: |cff9be8ff%d|r   cells shown: |cff9be8ff%d|r   mismatches: %s")
        :format(tokens, shown, problems == 0 and "|cff6ee7a0none|r" or ("|cffff6a5e" .. problems .. "|r")))
    local fixed = ReconcileRaid()
    if fixed > 0 then
        ns.Print(("re-synced |cff9be8ff%d|r cell(s)."):format(fixed))
    end
    local ok, g, slots = ns.VerifyRaidGrid()
    if ok then
        ns.Print("grid packing: |cff6ee7a0contiguous|r")
    else
        ns.Print(("grid packing: |cffff6a5eBROKEN|r — group %s has slots %s")
            :format(tostring(g), tostring(slots)))
    end
    ns.HealRaidGrid()
    -- and force a fresh layout regardless, so any stranded gap closes now
    RequestRaidLayout()
    if InCombatLockdown() then
        ns.Print("in combat: repositioning is deferred until the fight ends.")
    end
end

-- Raid unit tokens pack down: when raid3 leaves, the old raid4 becomes raid3
-- and so on. Repositioning cells is not enough — each cell is now pointing at
-- a different player and still displaying the previous one, which reads as a
-- duplicate, and as departed players lingering in a new slot.
local function RefreshAllCells()
    for _, cells in pairs(ns.groupCells) do
        for i = 1, #cells do
            local f = cells[i]
            if UnitExists(f.unit) then
                f.lastGUID = UnitGUID(f.unit)
                CellFull(f)
            elseif f.rosterOnly then
                CellRosterOnly(f)
            else
                -- wipe it so nothing can be left over if it shows again
                f.lastGUID = nil
                f.oorTicks, f.faded, f.holdName = 0, false, nil
                ns.Text(f.name, "")
                ns.Text(f.status, "")
                if f.bar.threatPulse then
                    f.bar.threatPulse = nil
                    f.bar:SetScript("OnUpdate", nil)
                end
                f.bar:SetOutlineColor(nil)
                f.bar.health:SetInstant(0, 1)
                if f.debuffC then f.debuffC:HideAll() end
            end
        end
    end
end

local rosterPending = false
local function OnRoster()
    -- Text, colours and bar values are not protected, so this half runs even
    -- mid-fight; people join, leave and get replaced during combat constantly.
    RefreshAllCells()

    if InCombatLockdown() then
        -- show/hide and repositioning touch secure attributes: defer those
        if not rosterPending then
            rosterPending = true
            ns.AfterCombat(function()
                rosterPending = false
                OnRoster()
            end)
        end
        return
    end
    UpdateVisibility()
    LayoutRaid()
    if ns.ReconcileRaid then ns.ReconcileRaid() end
    if ns.ReconcileParty then ns.ReconcileParty() end
end

-- The client sometimes fires the roster event a moment before the roster data
-- itself settles, so take a second look shortly after.
local function OnRosterEvent()
    OnRoster()
    C_Timer.After(0.15, OnRoster)
    C_Timer.After(0.60, OnRoster)
end
ns.OnRosterEvent = OnRosterEvent

-- range fade --------------------------------------------------------------

-- Verification. Whatever the cause, a group's visible cells must occupy
-- slots 1..n with nothing skipped. Rather than assume the layout logic is
-- correct, check the result and repair it -- and say so, so a cause I haven't
-- found still surfaces instead of silently leaving a hole.
local reportedGap = false

function ns.VerifyRaidGrid()
    local groups = {}
    for i = 1, 40 do
        local f = ns.groupCells.raid[i]
        if f:IsShown() and f.group and f.slot then
            groups[f.group] = groups[f.group] or {}
            table.insert(groups[f.group], f.slot)
        end
    end
    for g, slots in pairs(groups) do
        table.sort(slots)
        for k = 1, #slots do
            if slots[k] ~= k then
                return false, g, table.concat(slots, ",")
            end
        end
    end
    return true
end

-- Runs about once a second out of combat. Cheap, and it means any cause of a
-- gap -- including one I have not identified -- self-corrects within a tick.
function ns.HealRaidGrid()
    if InCombatLockdown() or not ns.db.raid.enabled then return end

    -- 1. anything hiding a seat gets overruled
    local reseated = 0
    for i = 1, 40 do
        local f = ns.groupCells.raid[i]
        local want = f.seated and true or false
        if f:IsShown() ~= want then
            if want then
                f:Show()
                CellFull(f)
            else
                f:Hide()
            end
            reseated = reseated + 1
        end
    end

    -- 2. the packing itself must be contiguous
    local ok, group, slots = ns.VerifyRaidGrid()
    if not ok or reseated > 0 then
        LayoutRaid()
        ok, group, slots = ns.VerifyRaidGrid()
        if not ok and not reportedGap then
            reportedGap = true
            ns.Print(("|cffff6a5egap in the raid grid|r — group %s had slots %s. "):format(
                tostring(group), tostring(slots))
                .. "It has been repaired; please run |cff9be8ff/silk roster|r and send the output.")
        end
    end
end
local reconcileT = 0
C_Timer.NewTicker(0.4, function()
    if not ns.db then return end
    -- every couple of seconds, check the roster against what's on screen
    reconcileT = reconcileT + 0.4
    if reconcileT >= 1 then
        reconcileT = 0
        if ns.ReconcileRaid then ns.ReconcileRaid() end
        if ns.ReconcileParty then ns.ReconcileParty() end
        if ns.HealRaidGrid then ns.HealRaidGrid() end
        -- backstop: if what's on screen no longer matches the roster, relayout
        if ns.RaidOccupancyChanged and ns.RaidOccupancyChanged() then
            ns.RequestRaidLayout()
        end
    end
    for kind, cells in pairs(ns.groupCells) do
        local cfg = ns.db[kind]
        if cfg and cfg.range then
            for i = 1, #cells do
                local f = cells[i]
                if f:IsShown() then
                    -- self-healing: catches any roster edge case within a tick
                    if cellSwapped(f) and UnitExists(f.unit) then
                        f.oorTicks, f.faded = 0, false
                        CellFull(f)
                    end
                    if not f.rosterOnly and not UnitIsUnit(f.unit, "player") then
                        local inR, chk = UnitInRange(f.unit)
                        if chk == false then inR = true end
                        if inR then
                            f.oorTicks, f.faded = 0, false
                        else
                            f.oorTicks = (f.oorTicks or 0) + 1
                            if f.oorTicks >= 2 then f.faded = true end
                        end
                    end
                    f:SetAlpha(CellAlphaNow(f))
                end
            end
        elseif cfg then
            for i = 1, #cells do
                local f = cells[i]
                f.oorTicks, f.faded = 0, false
                f:SetAlpha(CellAlphaNow(f))
            end
        end
    end
end)

-- previews -----------------------------------------------------------------
-- Phantom party and raid frames so both group layouts can be styled solo.
-- They reuse ApplyCell, so whatever you see here is exactly what you get.

local fakeNames = {
    "Sable", "Iris", "Vesper", "Onyx", "Wren", "Juno", "Ash", "Lyric", "Nova", "Rook",
    "Ember", "Fable", "Kestrel", "Moss", "Opal", "Pike", "Quill", "Reed", "Sage", "Thorn",
    "Umber", "Vale", "Willow", "Yarrow", "Zephyr",
}
local classTokens = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}

local previews = {}

local function fakeColor()
    local tok = classTokens[math.random(#classTokens)]
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[tok]
    if c and c.r then return { c.r, c.g, c.b } end
    return { 0.55, 0.62, 0.72 }
end

local function PreviewText(f)
    local mode = (f.kind == "raid") and ns.db.raid.text or "percent"
    local p = math.floor(f.hp)
    if mode == "deficit" then
        ns.Text(f.status, p < 100 and ("-" .. ns.Short((100 - p) * 84)) or "")
    elseif mode == "percent" then
        ns.Text(f.status, p < 100 and (p .. "%") or "")
    else
        ns.Text(f.status, "")
    end
end

local function LayoutPreview(kind)
    local pv = previews[kind]
    if not pv then return end
    local cfg = ns.db[kind]
    local anchor = (kind == "party") and ns.PartyAnchor or ns.RaidAnchor
    for i = 1, #pv.cells do
        local f = pv.cells[i]
        ApplyCell(f)
        f.bar.health:SetStatusColor(f.color[1], f.color[2], f.color[3])
        f.bar.health:SetInstant(f.hp, 100)
        if cfg.power then
            f.bar.power:SetStatusColor(0.35, 0.62, 1.00)
            f.bar.power:SetInstant(f.mp, 100)
        end
        ns.Text(f.name, fakeNames[i] or ("Unit" .. i))
        f.name:SetTextColor(f.color[1], f.color[2], f.color[3])
        PreviewText(f)

        local x, y
        if kind == "party" then
            x, y = PartyCellOffset(cfg, i)
        else
            x, y = RaidCellOffset(cfg, math.ceil(i / 5), (i - 1) % 5 + 1)
        end
        PlaceCell(f, anchor, cfg, x, y)
    end
end

local function BuildPreview(kind, count)
    local pv = CreateFrame("Frame", nil, UIParent)
    pv:SetSize(2, 2)
    pv:SetPoint("CENTER")
    pv.cells = {}
    for i = 1, count do
        local f = CreateFrame("Frame", nil, pv)
        f.kind = kind
        f.bar = ns.CreateUnitBar(f)
        f.health = f.bar.health
        f.power = f.bar.power

        local bl = CreateFrame("Frame", nil, f)
        bl:SetAllPoints(f)
        bl:SetFrameLevel(f:GetFrameLevel() + 9)
        local tl = CreateFrame("Frame", nil, f)
        tl:SetAllPoints(f)
        tl:SetFrameLevel(f:GetFrameLevel() + 10)
        f.name = ns.NewText(tl)
        f.status = ns.NewText(tl)
        ns.AttachTextBg(f.name, bl)
        ns.AttachTextBg(f.status, bl)

        f.color = fakeColor()
        f.hp = math.random(48, 100)
        f.mp = math.random(20, 100)
        pv.cells[i] = f
    end
    pv:Hide()
    previews[kind] = pv

    C_Timer.NewTicker(1.4, function()
        if not pv:IsShown() then return end
        for i = 1, #pv.cells do
            local f = pv.cells[i]
            if math.random() < 0.45 then
                f.hp = math.max(8, math.min(100, f.hp + math.random(-30, 24)))
                f.bar.health:SetValue(f.hp, 100)
                PreviewText(f)
            end
            if ns.db[kind].power and math.random() < 0.4 then
                f.mp = math.max(0, math.min(100, f.mp + math.random(-18, 22)))
                f.bar.power:SetValue(f.mp, 100)
            end
        end
    end)
    return pv
end

function ns.TogglePreview(kind)
    kind = (kind == "party") and "party" or "raid"
    local ok, err = pcall(function()
        if not previews[kind] then
            BuildPreview(kind, kind == "party" and 4 or 25)
        end
        local pv = previews[kind]
        if pv:IsShown() then
            pv:Hide()
            ns.Print(kind .. " preview dismissed.")
        else
            LayoutPreview(kind)
            pv:Show()
            if kind == "party" then
                ns.Print("party preview: 4 phantom teammates. /silk test party again to dismiss.")
            else
                ns.Print("raid preview: 25 phantom raiders reporting in. /silk test again to dismiss.")
            end
        end
    end)
    if not ok then
        ns.Print("|cffff6a5epreview error:|r " .. tostring(err))
    end
end

function ns.ToggleRaidPreview() ns.TogglePreview("raid") end
function ns.PreviewShown(kind) return previews[kind] and previews[kind]:IsShown() end

-- refresh + boot ----------------------------------------------------------

local function RefreshGroup()
    local pc, rc = ns.db.party, ns.db.raid
    ns.PartyAnchor:ClearAllPoints()
    ns.PartyAnchor:SetPoint("CENTER", UIParent, "CENTER", pc.pos[1], pc.pos[2])
    ns.RaidAnchor:ClearAllPoints()
    ns.RaidAnchor:SetPoint("CENTER", UIParent, "CENTER", rc.pos[1], rc.pos[2])

    for kind, cells in pairs(ns.groupCells) do
        for i = 1, #cells do
            ApplyCell(cells[i])
            if cells[i]:IsShown() then CellFull(cells[i]) end
        end
    end
    LayoutParty()
    OnRoster()
    if ns.PreviewShown("party") then LayoutPreview("party") end
    if ns.PreviewShown("raid") then LayoutPreview("raid") end
end
table.insert(ns.refreshers, RefreshGroup)

table.insert(ns.onLogin, function()
    for i = 1, 4 do
        ns.groupCells.party[i] = SpawnCell("party", i)
    end
    for i = 1, 40 do
        ns.groupCells.raid[i] = SpawnCell("raid", i)
    end
    RefreshGroup()

    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD",
                         "RAID_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED",
                         "PARTY_LEADER_CHANGED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", OnRosterEvent)
end)
