-- Silk : Swing --------------------------------------------------------------
-- Swing timers, in the same shell as everything else.
--
-- Player bars are exact: the combat log says the instant a swing or shot
-- lands, and the client says how long until the next one. Haste changes are
-- applied mid-swing by rescaling the remaining time, so a proc or a lost buff
-- moves the bar the moment it happens instead of after the next hit.
--
-- The ranged bar is built around the hunter's problem: an Auto Shot needs a
-- half-second of stillness before it fires. That aim window is drawn on the
-- bar, the fill warms when it enters it, and if a cast pushes the shot -- a
-- Steady Shot started too late -- the bar visibly snaps to where the shot
-- will actually land. Casters get their wand on the same bar.
--
-- Enemy bars are estimates. No API exposes a mob's attack speed, so the bar
-- measures the interval between its swings and says so until it has two.

local ADDON, ns = ...

local MELEE_MH   = { 0.62, 0.72, 0.86 }
local MELEE_OH   = { 0.48, 0.56, 0.68 }
local RANGED     = { 0.97, 0.78, 0.32 }
local RANGED_AIM = { 0.98, 0.55, 0.22 }
local ENEMY      = { 0.80, 0.42, 0.40 }
local AIM_WINDOW = 0.5

-- ranged auto-repeat and shoot spells that fire from the ranged slot
local RANGED_SPELLS = {
    [75] = "Auto Shot", [5019] = "Wand",
    [2480] = "Shoot", [7918] = "Shoot", [7919] = "Shoot", [2764] = "Throw",
}

-- On-next-swing attacks REPLACE the white hit: when Raptor Strike or Heroic
-- Strike is queued, the swing lands as SPELL_DAMAGE with that spell's id and
-- no SWING_DAMAGE ever fires -- so the melee bar must count these as the
-- main-hand swing they are. Every rank of every on-next-swing attack in TBC.
local NEXT_SWING = {}
for _, id in ipairs({
    2973, 14260, 14261, 14262, 14263, 14264, 14265, 14266, 27014,   -- Raptor Strike
    78, 284, 285, 1608, 11564, 11565, 11566, 11567, 25286, 29707, 30324, -- Heroic Strike
    845, 7369, 11608, 11609, 20569, 25231,                          -- Cleave
    6807, 6808, 6809, 8972, 9745, 9880, 9881, 26996,                -- Maul
}) do NEXT_SWING[id] = true end
local NEXT_SWING_NAMES = {
    ["Raptor Strike"] = true, ["Heroic Strike"] = true,
    ["Cleave"] = true, ["Maul"] = true,
}

-- Multi-Shot never produces a cast on this client: no START event, and
-- UnitCastingInfo reports nothing while it happens -- the trace proved it.
-- The only signal is SUCCEEDED, so that's what drives the feedback.
local MULTI_SPELLS = {
    [2643] = true, [14288] = true, [14289] = true, [14290] = true,
    [25294] = true, [27021] = true,
}

-- localized names for the same spells, so the shot is recognised in any
-- client language and even if the event's argument order differs
local RANGED_NAMES = {}
local MULTI_NAMES = {}

local function spellName(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and type(info) == "table" then return info.name end
    end
    if GetSpellInfo then
        local ok, n = pcall(GetSpellInfo, id)
        if ok then return n end
    end
end

local function buildRangedNames()
    for id in pairs(MULTI_SPELLS) do
        local n = spellName(id)
        if n then MULTI_NAMES[n] = true end
    end
    MULTI_NAMES["Multi-Shot"] = true
    for id in pairs(RANGED_SPELLS) do
        local name
        if C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, id)
            if ok and type(info) == "table" then name = info.name end
        end
        if not name and GetSpellInfo then
            local ok, n = pcall(GetSpellInfo, id)
            if ok then name = n end
        end
        if name then RANGED_NAMES[name] = true end
    end
    RANGED_NAMES["Auto Shot"] = true
    RANGED_NAMES["Shoot"] = true
    for id in pairs(NEXT_SWING) do
        local n = spellName(id)
        if n then NEXT_SWING_NAMES[n] = true end
    end
end

local function isMultiShot(a2, a3)
    if type(a3) == "number" and MULTI_SPELLS[a3] then return true end
    if type(a3) == "string" and MULTI_NAMES[a3] then return true end
    if type(a2) == "string" and MULTI_NAMES[a2] then return true end
    return false
end

local function isRangedShot(a2, a3)
    if type(a3) == "number" and RANGED_SPELLS[a3] then return true end
    if type(a3) == "string" and RANGED_NAMES[a3] then return true end
    if type(a2) == "string" and RANGED_NAMES[a2] then return true end
    return false
end

local diag = { shots = 0, lastShotAt = 0, lastEvent = "none" }
ns.swingDiag = diag

local playerGUID
local swing = {          -- player state
    mh = { speed = 2.0, nextAt = 0, last = 0 },
    oh = { speed = 2.0, nextAt = 0, last = 0, has = false },
    rg = { speed = 2.0, nextAt = 0, last = 0, label = "Auto Shot", stopped = false },
    lastActivity = 0,
    castStart = nil,
    castEnd = nil,
}
local enemyCal = setmetatable({}, { __mode = "k" })   -- guid -> { speed, last }
ns.swing = swing

-- helpers -------------------------------------------------------------------

local function now() return GetTime() end

local function readMeleeSpeeds()
    local ok, mh, oh = pcall(UnitAttackSpeed, "player")
    if not ok then return end
    if mh and mh > 0 then swing.mh.speed = mh end
    if oh and oh > 0 then
        swing.oh.speed, swing.oh.has = oh, true
    else
        swing.oh.has = false
    end
end

local function readRangedSpeed()
    local ok, speed = pcall(UnitRangedDamage, "player")
    if ok and speed and speed > 0 then swing.rg.speed = speed end
end

-- a haste change mid-swing scales what's left of the swing
local function rescale(t, newSpeed)
    if not newSpeed or newSpeed <= 0 or t.speed <= 0 then return end
    local n = now()
    local remaining = t.nextAt - n
    if remaining > 0 then
        t.nextAt = n + remaining * (newSpeed / t.speed)
    end
    t.speed = newSpeed
end

local function landed(t)
    local n = now()
    t.last = n
    t.nextAt = n + t.speed
    swing.lastActivity = n
end

-- a cast in progress pushes an auto shot that would fire inside it
local function applyPush()
    local ce = swing.castEnd
    if ce and swing.rg.nextAt < ce and swing.rg.nextAt > (now() - 0.05) then
        swing.rg.pushedTo = ce
    else
        swing.rg.pushedTo = nil
    end
end

local function rangedLabel()
    local ok, _, class = pcall(UnitClass, "player")
    if ok and class == "HUNTER" then return "Auto Shot" end
    return "Wand"
end

-- bars ----------------------------------------------------------------------

local function makeLabelLayer(bar)
    local tl = CreateFrame("Frame", nil, bar)
    tl:SetAllPoints(bar)
    tl:SetFrameLevel(bar:GetFrameLevel() + 10)
    local iconF = CreateFrame("Frame", nil, tl)
    local icon = iconF:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local mask = iconF:CreateMaskTexture()
    mask:SetAllPoints()
    mask:SetTexture(ns.TEX.iconMask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    icon:AddMaskTexture(mask)
    local ring = iconF:CreateTexture(nil, "OVERLAY")
    ring:SetPoint("TOPLEFT", -1, 1)
    ring:SetPoint("BOTTOMRIGHT", 1, -1)
    ring:SetTexture(ns.TEX.iconRing)
    ring:SetVertexColor(0, 0, 0, 0.9)
    bar.iconF, bar.icon = iconF, icon
    bar.label = ns.NewText(tl)
    bar.label:SetPoint("LEFT", bar, "LEFT", 8, 0)
    bar.timer = ns.NewText(tl)
    bar.timer:SetPoint("RIGHT", bar, "RIGHT", -9, 0)
end

local function styleBar(bar, h, iconTex)
    bar:SetHeight(h)
    bar:ApplyStyle()
    local pad = math.max(2, math.floor(h * 0.14))
    local isz = h - pad * 2
    bar.iconF:SetSize(isz, isz)
    bar.iconF:ClearAllPoints()
    bar.iconF:SetPoint("LEFT", bar, "LEFT", pad + 1, 0)
    local hasIcon = iconTex ~= nil
    bar.iconF:SetShown(hasIcon)
    if hasIcon then bar.icon:SetTexture(iconTex) end
    bar.label:ClearAllPoints()
    bar.label:SetPoint("LEFT", bar, "LEFT", hasIcon and (isz + pad * 2 + 4) or 9, 0)
    ns.SetFont(bar.label, -2)
    ns.SetFont(bar.timer, -3)
    ns.TextColor(bar.label, nil, 0.90, 0.92, 0.96)
    ns.TextColor(bar.timer, nil, ns.palette.text[1], ns.palette.text[2], ns.palette.text[3])
end

local function inventoryIcon(slot)
    if not GetInventoryItemTexture then return nil end
    local ok, tex = pcall(GetInventoryItemTexture, "player", slot)
    if ok then return tex end
    return nil
end

-- player host: melee (with off-hand slice) stacked over ranged
local function BuildPlayerSwing(f)
    local host = CreateFrame("Frame", nil, f)
    host:Hide()
    f.swingHost = host

    local melee = ns.CreateUnitBar(host)
    melee:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    melee:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
    makeLabelLayer(melee)
    melee.health:SetStatusColor(MELEE_MH[1], MELEE_MH[2], MELEE_MH[3])
    melee.power:SetStatusColor(MELEE_OH[1], MELEE_OH[2], MELEE_OH[3])
    host.melee = melee

    local ranged = ns.CreateBar(host, "ranged")
    ranged:SetPoint("TOPLEFT", melee, "BOTTOMLEFT", 0, -4)
    ranged:SetPoint("TOPRIGHT", melee, "BOTTOMRIGHT", 0, -4)
    makeLabelLayer(ranged)
    ranged:SetStatusColor(RANGED[1], RANGED[2], RANGED[3])
    -- the aim window: a warm band over the last half second of the track
    local aim = ranged.inner:CreateTexture(nil, "ARTWORK", nil, 2)
    aim:SetColorTexture(1, 1, 1)
    aim:SetVertexColor(RANGED_AIM[1], RANGED_AIM[2], RANGED_AIM[3], 0.28)
    aim:SetPoint("TOPRIGHT", ranged.inner, "TOPRIGHT", 0, 0)
    aim:SetPoint("BOTTOMRIGHT", ranged.inner, "BOTTOMRIGHT", 0, 0)
    aim:SetWidth(1)
    ranged.inner:AddMasked(aim)
    ranged.aim = aim
    -- the cast you're in, drawn on the same timeline: Steady, Multi, Aimed
    -- appear as a translucent block from where they started to where they
    -- end, so you can see whether they fit before the shot -- and it turns
    -- red the instant a cast runs into the shot window (a clip)
    local cast = ranged.inner:CreateTexture(nil, "ARTWORK", nil, 3)
    cast:SetColorTexture(1, 1, 1)
    cast:SetVertexColor(1, 1, 1, 0.38)
    cast:SetPoint("TOPLEFT", ranged.inner, "TOPLEFT", 0, 0)
    cast:SetPoint("BOTTOMLEFT", ranged.inner, "BOTTOMLEFT", 0, 0)
    cast:SetWidth(1)
    cast:Hide()
    ranged.inner:AddMasked(cast)
    ranged.castOverlay = cast
    -- a bright pin dropped where a Multi-Shot fired, fading over a beat
    local pin = ranged.inner:CreateTexture(nil, "ARTWORK", nil, 4)
    pin:SetColorTexture(1, 1, 1)
    pin:SetVertexColor(1, 0.96, 0.78, 1)
    pin:SetPoint("TOPLEFT", ranged.inner, "TOPLEFT", 0, 0)
    pin:SetPoint("BOTTOMLEFT", ranged.inner, "BOTTOMLEFT", 0, 0)
    pin:SetWidth(2)
    pin:Hide()
    ranged.inner:AddMasked(pin)
    ranged.multiPin = pin
    host.ranged = ranged

    host:SetScript("OnUpdate", function(_, dt) ns.SwingTickPlayer(f) end)
    return host
end

local function BuildEnemySwing(f)
    local host = CreateFrame("Frame", nil, f)
    host:Hide()
    f.swingHost = host
    local bar = ns.CreateBar(host, "enemy")
    bar:SetAllPoints(host)
    makeLabelLayer(bar)
    bar:SetStatusColor(ENEMY[1], ENEMY[2], ENEMY[3])
    host.enemy = bar
    host:SetScript("OnUpdate", function() ns.SwingTickEnemy(f) end)
    return host
end

-- layout --------------------------------------------------------------------

local function swingCfg(f)
    local c = f.cfg.swing
    return c
end

-- stacks under the castbar's slot (whether or not a cast is showing), or
-- floats free when detached
local function ApplySwingLayout(f)
    local host = f.swingHost
    if not host then return end
    local cfg = f.cfg
    local sc = cfg.swing
    if not sc then host:Hide() return end
    local h = sc.h or 14

    local bars = 0
    if host.melee then
        local wantMelee = sc.melee ~= false
        local wantRanged = sc.ranged ~= false
        host.melee:SetShown(wantMelee)
        host.ranged:SetShown(wantRanged)
        if wantMelee then
            styleBar(host.melee, h, inventoryIcon(16))
            readMeleeSpeeds()
            host.melee:SetPowerHeight(math.max(3, math.floor(h * 0.3)))
            host.melee:ShowPower(swing.oh.has)
            ns.Text(host.melee.label, "Melee")
            bars = bars + 1
        end
        if wantRanged then
            styleBar(host.ranged, h, inventoryIcon(18))
            ns.Text(host.ranged.label, swing.rg.label)
            bars = bars + 1
        end

        -- Which bar sits on top. A hunter's primary timer is the shot, so
        -- Auto puts ranged first for hunters and melee first for everyone
        -- else; either can be forced.
        local rangedFirst
        if sc.order == "ranged" then
            rangedFirst = true
        elseif sc.order == "melee" then
            rangedFirst = false
        else
            local ok, _, class = pcall(UnitClass, "player")
            rangedFirst = ok and class == "HUNTER"
        end
        local first, second
        if wantMelee and wantRanged then
            if rangedFirst then
                first, second = host.ranged, host.melee
            else
                first, second = host.melee, host.ranged
            end
        else
            first = wantMelee and host.melee or host.ranged
        end
        first:ClearAllPoints()
        first:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        first:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
        if second then
            second:ClearAllPoints()
            second:SetPoint("TOPLEFT", first, "BOTTOMLEFT", 0, -4)
            second:SetPoint("TOPRIGHT", first, "BOTTOMRIGHT", 0, -4)
        end
    elseif host.enemy then
        if sc.enemy then
            styleBar(host.enemy, h, nil)
            ns.Text(host.enemy.label, "Swing")
            bars = 1
        end
    end
    if bars == 0 then
        host.wanted = false
        host:Hide()
        return
    end
    host.wanted = true

    local totalH = bars * h + (bars - 1) * 4
    host:ClearAllPoints()
    if sc.detach then
        host:SetPoint("CENTER", UIParent, "CENTER", sc.pos[1], sc.pos[2])
        host:SetSize((sc.w or 0) > 0 and sc.w or cfg.w, totalH)
    else
        local below = 6
        if cfg.castbar then below = below + (cfg.castH or 18) + 4 end
        host:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -below)
        host:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -below)
        host:SetHeight(totalH)
    end
end
ns.ApplySwingLayout = ApplySwingLayout

-- ticking ------------------------------------------------------------------

local function fracOf(t, n)
    local dur = t.speed
    if dur <= 0 then return 0 end
    local elapsed = n - (t.nextAt - dur)
    if elapsed < 0 then return 0 end
    if elapsed > dur then return 1 end
    return elapsed / dur
end

local function fmtTime(s)
    if s < 0 then s = 0 end
    return string.format("%.1f", s)
end

function ns.SwingTickPlayer(f)
    local host = f.swingHost
    if not host or not host:IsShown() then return end
    local n = now()

    if host.melee:IsShown() then
        local m = host.melee
        if (n - (swing.mh.polledAt or 0)) > 0.1 then
            swing.mh.polledAt = n
            local ok, mh, oh = pcall(UnitAttackSpeed, "player")
            if ok then
                if mh and mh > 0 and math.abs(mh - swing.mh.speed) > 0.001 then rescale(swing.mh, mh) end
                if oh and oh > 0 then
                    if math.abs(oh - swing.oh.speed) > 0.001 then rescale(swing.oh, oh) end
                    if not swing.oh.has then swing.oh.has = true m:ShowPower(true) end
                elseif swing.oh.has then
                    swing.oh.has = false
                    m:ShowPower(false)
                end
            end
        end
        m.health:SetInstant(fracOf(swing.mh, n), 1)
        if swing.oh.has then m.power:SetInstant(fracOf(swing.oh, n), 1) end
        ns.Text(m.timer, fmtTime(swing.mh.nextAt - n))
    end
    if host.ranged:IsShown() then
        local r = host.ranged
        local t = swing.rg

        -- haste safety net: events cover most changes, but nothing is
        -- allowed to slip through -- re-read the speed ten times a second
        if (n - (t.polledAt or 0)) > 0.1 then
            t.polledAt = n
            local ok, speed = pcall(UnitRangedDamage, "player")
            if ok and speed and speed > 0 and math.abs(speed - t.speed) > 0.001 then
                rescale(t, speed)
                applyPush()
            end
        end

        local fireAt = t.pushedTo or t.nextAt
        local cycleStart = t.last > 0 and t.last or (t.nextAt - t.speed)
        local span = fireAt - cycleStart
        if span <= 0 then span = t.speed end
        local shotStart = fireAt - AIM_WINDOW
        local iw = r.iw or 0

        local phase
        local recent = (n - t.last) < (t.speed * 2 + 1)
        if not ns.layoutMode and (t.stopped or not recent) and n > fireAt + 0.08 then
            phase = "off"
        elseif n < shotStart then
            phase = "wait"
        elseif n <= fireAt + 0.08 then
            phase = "shot"
        else
            phase = "late"
        end

        if phase == "off" then
            r:SetInstant(0, 1)
            ns.Text(r.label, t.label)
            ns.Text(r.timer, "")
            r.castOverlay:Hide()
        else
            local frac = (n - cycleStart) / span
            if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
            r:SetInstant(frac, 1)
            if phase == "wait" then
                -- the number that matters: how long until the shot needs you
                -- still. That is the room you have to fit a cast.
                ns.Text(r.label, t.label)
                ns.Text(r.timer, fmtTime(shotStart - n))
            elseif phase == "shot" then
                ns.Text(r.label, "Firing")
                ns.Text(r.timer, fmtTime(fireAt - n))
            else
                -- the timer passed with no shot in the log: you moved during
                -- the aim, or the target is out of range
                ns.Text(r.label, "Delayed")
                ns.Text(r.timer, "")
            end

            -- aim band scaled to this cycle
            if iw > 0 then
                local aw = iw * math.min(1, AIM_WINDOW / span)
                if r.aimW ~= aw then
                    r.aimW = aw
                    r.aim:SetWidth(math.max(1, aw))
                end
            end

            -- cast overlay on the same timeline
            local cs, ce = swing.castStart, swing.castEnd
            if cs and ce and iw > 0 and phase ~= "late" then
                local a = (cs - cycleStart) / span
                local b = (ce - cycleStart) / span
                if a < 0 then a = 0 end
                local clip = b > (1 - AIM_WINDOW / span)   -- runs into the shot window
                if b > 1 then b = 1 end
                if b > a then
                    local x, w = iw * a, iw * (b - a)
                    if r.ovX ~= x or r.ovW ~= w then
                        r.ovX, r.ovW = x, w
                        r.castOverlay:ClearAllPoints()
                        r.castOverlay:SetPoint("TOPLEFT", r.inner, "TOPLEFT", x, 0)
                        r.castOverlay:SetPoint("BOTTOMLEFT", r.inner, "BOTTOMLEFT", x, 0)
                        r.castOverlay:SetWidth(math.max(1, w))
                    end
                    if r.ovClip ~= clip then
                        r.ovClip = clip
                        if clip then
                            r.castOverlay:SetVertexColor(0.95, 0.30, 0.25, 0.55)
                        else
                            r.castOverlay:SetVertexColor(1, 1, 1, 0.38)
                        end
                    end
                    if not r.castOverlay:IsShown() then r.castOverlay:Show() end
                end
            elseif r.castOverlay:IsShown() then
                r.castOverlay:Hide()
            end
        end

        -- Multi-Shot pin: where in the cycle it fired, fading out
        local ma = swing.multiAt
        if ma and (n - ma) < 0.8 and iw > 0 and phase ~= "off" then
            local px = iw * (swing.multiFrac or 0)
            if r.pinX ~= px then
                r.pinX = px
                r.multiPin:ClearAllPoints()
                r.multiPin:SetPoint("TOPLEFT", r.inner, "TOPLEFT", px, 0)
                r.multiPin:SetPoint("BOTTOMLEFT", r.inner, "BOTTOMLEFT", px, 0)
            end
            r.multiPin:SetAlpha(1 - (n - ma) / 0.8)
            if not r.multiPin:IsShown() then r.multiPin:Show() end
        elseif r.multiPin:IsShown() then
            r.multiPin:Hide()
            r.pinX = nil
        end

        -- fill colour: a bright blink the instant a shot fires, gold while
        -- waiting, amber while the shot is firing, dimmed when late or off
        local want = (phase == "shot") and "aim" or (phase == "wait") and "gold" or "dim"
        if t.firedAt and (n - t.firedAt) < 0.15 and phase ~= "off" then
            want = "fired"
        end
        if r.wasPhase ~= want then
            r.wasPhase = want
            if want == "fired" then
                r:SetStatusColor(1, 0.97, 0.82)
            elseif want == "aim" then
                r:SetStatusColor(RANGED_AIM[1], RANGED_AIM[2], RANGED_AIM[3])
            elseif want == "gold" then
                r:SetStatusColor(RANGED[1], RANGED[2], RANGED[3])
            else
                r:SetStatusColor(RANGED[1] * 0.55, RANGED[2] * 0.55, RANGED[3] * 0.55)
            end
        end
    end
end

function ns.SwingTickEnemy(f)
    local host = f.swingHost
    if not host or not host:IsShown() then return end
    local bar = host.enemy
    local cal
    if ns.layoutMode and host.sample then
        cal = host.sample
    else
        local guid = UnitExists(f.unit) and UnitGUID(f.unit) or nil
        cal = guid and enemyCal[guid]
    end
    if not cal or not cal.speed then
        bar:SetInstant(0, 1)
        ns.Text(bar.timer, cal and "calibrating…" or "")
        return
    end
    local n = now()
    local elapsed = n - cal.last
    local frac = elapsed / cal.speed
    if frac > 1 then frac = 1 end
    bar:SetInstant(frac, 1)
    ns.Text(bar.timer, fmtTime(cal.speed - elapsed))
end

-- visibility: always while fighting, otherwise a grace period after the last
-- swing, unless the profile asks for it always
local function refreshVisibility()
    local n = now()
    local inCombat = UnitAffectingCombat and select(2, pcall(UnitAffectingCombat, "player"))
    for _, key in ipairs({ "player", "target", "focus" }) do
        local f = ns.units[key]
        local host = f and f.swingHost
        if host and host.wanted then
            local sc = f.cfg.swing or {}
            local show
            if ns.layoutMode then
                show = true
            elseif key == "player" then
                show = (sc.hideIdle == false) or inCombat
                    or (n - swing.lastActivity) < (sc.idleDelay or 5)
            else
                local guid = UnitExists(f.unit) and UnitGUID(f.unit) or nil
                local cal = guid and enemyCal[guid]
                show = f:IsShown() and cal ~= nil
                    and (inCombat or (n - (cal.last or 0)) < (sc.idleDelay or 5))
            end
            host:SetShown(show and true or false)
        end
    end
end

-- events --------------------------------------------------------------------

local function onCombatLog()
    local _, sub, _, srcGUID, _, _, _, dstGUID = CombatLogGetCurrentEventInfo()
    if srcGUID == playerGUID then
        if sub == "SWING_DAMAGE" or sub == "SWING_MISSED" then
            local isOff
            if sub == "SWING_DAMAGE" then
                isOff = select(21, CombatLogGetCurrentEventInfo())
            else
                isOff = select(13, CombatLogGetCurrentEventInfo())
            end
            readMeleeSpeeds()
            landed(isOff and swing.oh or swing.mh)
        elseif sub == "SPELL_DAMAGE" or sub == "SPELL_MISSED" then
            local spellId, spellNm = select(12, CombatLogGetCurrentEventInfo())
            if NEXT_SWING[spellId]
                or (type(spellNm) == "string" and NEXT_SWING_NAMES[spellNm]) then
                -- this WAS the main-hand swing
                readMeleeSpeeds()
                landed(swing.mh)
                diag.lastEvent = "NEXTSWING " .. tostring(spellId)
            end
        end
        -- Ranged shots are NOT reset from the combat log on purpose: damage
        -- events fire when the projectile lands, which at range is most of a
        -- second after the shot left the bow. UNIT_SPELLCAST_SUCCEEDED fires
        -- the instant Auto Shot fires; that's the reset (see the event handler)
        return
    end

    -- an enemy we're watching: measure the gap between its swings
    if sub == "SWING_DAMAGE" or sub == "SWING_MISSED" then
        for _, key in ipairs({ "target", "focus" }) do
            local f = ns.units[key]
            if f and f.swingHost and UnitExists(f.unit) and UnitGUID(f.unit) == srcGUID then
                local n = now()
                local cal = enemyCal[srcGUID]
                if not cal then
                    cal = { last = n }
                    enemyCal[srcGUID] = cal
                else
                    local gap = n - cal.last
                    if gap > 0.4 and gap < 8 then
                        -- blend toward the newest interval so parry-haste and
                        -- one-off hiccups don't yank the bar around
                        cal.speed = cal.speed and (cal.speed * 0.4 + gap * 0.6) or gap
                    end
                    cal.last = n
                end
            end
        end
    end
end

local function onSpeedChange(unit, event)
    if unit ~= "player" then return end
    if event == "UNIT_ATTACK_SPEED" then
        local ok, mh, oh = pcall(UnitAttackSpeed, "player")
        if ok then
            rescale(swing.mh, mh)
            if oh and oh > 0 then
                rescale(swing.oh, oh)
                swing.oh.has = true
            else
                swing.oh.has = false
            end
            local f = ns.units.player
            if f and f.swingHost and f.swingHost.melee then
                f.swingHost.melee:ShowPower(swing.oh.has)
            end
        end
    else
        local ok, speed = pcall(UnitRangedDamage, "player")
        if ok then rescale(swing.rg, speed) end
    end
    applyPush()
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        onCombatLog()
    elseif event == "UNIT_ATTACK_SPEED" or event == "UNIT_RANGEDDAMAGE" then
        onSpeedChange(a1, event)
    elseif event == "UNIT_SPELLCAST_START" then
        if a1 == "player" then
            local ok, _, _, _, startMS, endMS, _, castID = pcall(UnitCastingInfo, "player")
            swing.castEnd = (ok and endMS) and (endMS / 1000) or nil
            swing.castStart = (ok and startMS) and (startMS / 1000) or nil
            swing.castGUID = a2 or castID
            applyPush()
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" and a1 == "player" and isRangedShot(a2, a3) then
        -- the shot left the bow: this is the moment the cycle restarts
        readRangedSpeed()
        swing.rg.firedAt = now()
        landed(swing.rg)
        swing.rg.pushedTo = nil
        swing.rg.stopped = false
        diag.shots = diag.shots + 1
        diag.lastShotAt = now()
        diag.lastEvent = "SUCCEEDED " .. tostring(a3)
        if diag.shots == 1 then
            ns.Print("auto shot tracking is live (first shot seen).")
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" and a1 == "player" and isMultiShot(a2, a3) then
        -- no cast ever exists for this spell, so the success IS the feedback:
        -- flash it on the castbar and pin where in the cycle it landed
        local t = swing.rg
        local n2 = now()
        local fireAt = t.pushedTo or t.nextAt
        local span = fireAt - t.last
        if span > 0 then
            local frac = (n2 - t.last) / span
            if frac >= 0 and frac <= 1 then
                swing.multiAt, swing.multiFrac = n2, frac
            end
        end
        if ns.FlashInstant then
            local nm = (type(a3) == "number" and spellName(a3)) or "Multi-Shot"
            ns.FlashInstant(ns.units.player, nm, type(a3) == "number" and a3 or nil)
        end
        swing.lastActivity = n2
        diag.lastEvent = "MULTI " .. tostring(a3)
        -- if this client ever DOES cast Multi-Shot, the overlay must clear:
        -- same API-truth rule as every other cast event
        local okc, cname, _, _, cs, ce, _, cid = pcall(UnitCastingInfo, "player")
        if okc and cname and cs and ce then
            swing.castStart, swing.castEnd, swing.castGUID = cs / 1000, ce / 1000, cid
            applyPush()
        else
            swing.castStart, swing.castEnd, swing.castGUID = nil, nil, nil
        end
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED"
        or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET"
        or event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- the API decides, not the event: if the client says a cast is still
        -- in progress it stays on the track; if not, it's gone. Auto Shot's
        -- own FAILED_QUIET / STOP therefore can't erase a Multi-Shot.
        if a1 == "player" then
            local ok, name, _, _, startMS, endMS, _, castID = pcall(UnitCastingInfo, "player")
            if ok and name and startMS and endMS then
                swing.castEnd = endMS / 1000
                swing.castStart = startMS / 1000
                swing.castGUID = castID
                applyPush()
            else
                swing.castEnd = nil
                swing.castStart = nil
                swing.castGUID = nil
            end
        end
    elseif event == "START_AUTOREPEAT_SPELL" then
        swing.rg.stopped = false
        swing.lastActivity = now()
        -- turning auto shot on: the first shot needs its half second of aim
        if swing.rg.nextAt < now() then
            readRangedSpeed()
            swing.rg.last = now() - (swing.rg.speed - AIM_WINDOW)
            swing.rg.nextAt = now() + AIM_WINDOW
        end
    elseif event == "STOP_AUTOREPEAT_SPELL" then
        swing.rg.stopped = true
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "UNIT_INVENTORY_CHANGED" then
        readMeleeSpeeds()
        readRangedSpeed()
        local f = ns.units.player
        if f then ApplySwingLayout(f) end
    elseif event == "PLAYER_REGEN_DISABLED" then
        swing.lastActivity = now()
    end
    refreshVisibility()
end)

table.insert(ns.onLogin, function()
    playerGUID = UnitGUID("player")
    buildRangedNames()
    swing.rg.label = rangedLabel()
    readMeleeSpeeds()
    readRangedSpeed()
    for _, e in ipairs({
        "COMBAT_LOG_EVENT_UNFILTERED", "UNIT_ATTACK_SPEED", "UNIT_RANGEDDAMAGE",
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_INTERRUPTED",
        "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_SUCCEEDED",
        "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL",
        "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED",
        "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    C_Timer.NewTicker(0.25, refreshVisibility)
end)

-- layout-mode sample so there is something to drag
function ns.ShowSwingSample(f, on)
    local host = f.swingHost
    if not host then return end
    if on then
        local n = now()
        if host.melee then
            swing.mh.nextAt = n + swing.mh.speed * 0.4
            swing.oh.nextAt = n + swing.oh.speed * 0.7
            swing.rg.nextAt = n + swing.rg.speed * 0.3
            swing.lastActivity = n
        elseif host.enemy then
            -- kept on the host, never in the calibration table: a sample must
            -- not masquerade as a real measurement of the current target
            host.sample = { speed = 2.0, last = n - 0.8 }
        end
    else
        host.sample = nil
    end
    refreshVisibility()
end

function ns.SwingReport()
    local t = swing.rg
    local n = now()
    ns.Print("--- swing report ---")
    ns.Print(("ranged speed |cff9be8ff%.2f|r   shots seen |cff9be8ff%d|r   last shot %.1fs ago")
        :format(t.speed, diag.shots, diag.lastShotAt > 0 and (n - diag.lastShotAt) or -1))
    ns.Print(("next fire in %.2fs   pushed=%s   stopped=%s   last event: %s")
        :format(t.nextAt - n, tostring(t.pushedTo ~= nil), tostring(t.stopped), diag.lastEvent))
    ns.Print(("melee %.2f / off-hand %s   cast overlay: %s")
        :format(swing.mh.speed, swing.oh.has and string.format("%.2f", swing.oh.speed) or "none",
                swing.castEnd and "active" or "none"))
    if diag.shots == 0 then
        ns.Print("|cffff6a5eno shot events received yet|r — fire a few auto shots, then run this again.")
    end
end

ns.BuildPlayerSwing = BuildPlayerSwing
ns.BuildEnemySwing = BuildEnemySwing
