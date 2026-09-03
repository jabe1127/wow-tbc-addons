-- Silk : Frames -----------------------------------------------------------
-- Player, pet, target, target-of-target, and focus. Circular portraits with
-- a luminous rank ring (gold elite, silver rare, crimson boss), a tiny gem
-- beside the level, a mood dot for hunter pets, and capsule combo pips
-- under the target.

local ADDON, ns = ...

local UNITS = { "player", "pet", "target", "targettarget", "focus" }
ns.units = {}

-- hide Blizzard -----------------------------------------------------------

local hidden = CreateFrame("Frame")
hidden:Hide()

local function bury(f)
    if not f then return end
    pcall(f.UnregisterAllEvents, f)
    pcall(f.Hide, f)
    pcall(f.SetParent, f, hidden)
end

-- Which Blizzard frames to bury. The party frames in particular have several
-- shapes on this client: the classic PartyMemberFrame1-4, the newer PartyFrame
-- container with MemberFrame children, and the raid-style CompactPartyFrame
-- when "Use Raid-Style Party Frames" is on. Missing any one of them leaves a
-- second set of party frames on screen next to Silk's.
local BLIZZ_NAMES = {
    "PlayerFrame", "PetFrame", "TargetFrame", "FocusFrame", "ComboFrame",
    "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4",
    "PartyMemberFrame1PetFrame", "PartyMemberFrame2PetFrame",
    "PartyMemberFrame3PetFrame", "PartyMemberFrame4PetFrame",
    "PartyFrame", "CompactPartyFrame", "PartyMemberBackground",
    "CompactRaidFrameManager", "CompactRaidFrameContainer",
    "CastingBarFrame", "PlayerCastingBarFrame", "PetCastingBarFrame",
    "TargetFrameSpellBar", "FocusFrameSpellBar",
}

ns.buriedBlizzard = {}

local function buryNamed(name, frame)
    frame = frame or _G[name]
    if not frame or ns.buriedBlizzard[name] then return end
    bury(frame)
    ns.buriedBlizzard[name] = true
end

local function HideBlizzard()
    -- SetParent on a protected frame is blocked mid-combat
    if InCombatLockdown() then
        ns.AfterCombat(HideBlizzard)
        return
    end
    for i = 1, #BLIZZ_NAMES do
        buryNamed(BLIZZ_NAMES[i])
    end
    -- the newer container keeps its members as fields rather than globals
    local pf = _G["PartyFrame"]
    if pf then
        for i = 1, 4 do
            local m = pf["MemberFrame" .. i]
            if m then buryNamed("PartyFrame.MemberFrame" .. i, m) end
        end
    end
end
ns.HideBlizzard = HideBlizzard

-- Separate from the rest: this one is opt-in, so it runs from the refresher.
-- Restoring it needs a /reload, which is normal for hidden Blizzard frames.
local buriedBuffs = false
local function ApplyBlizzardBuffs()
    if buriedBuffs or not ns.db.hideBlizzardBuffs then return end
    bury(BuffFrame)
    bury(TemporaryEnchantFrame)
    buriedBuffs = true
    ns.Print("default buff frame hidden. /reload to bring it back if you turn this off.")
end

-- element updates ---------------------------------------------------------

local rank = ns.palette.rank
local classify = {
    elite     = { ring = rank.elite, gem = rank.elite },
    rareelite = { ring = rank.elite, gem = rank.rare },
    rare      = { ring = rank.rare,  gem = rank.rare },
    worldboss = { ring = rank.boss,  gem = rank.boss },
}

-- Target-of-target has no event of its own and is polled, so the unit behind
-- the frame can change between two ticks with nothing to announce it. Gliding
-- from the previous unit's numbers is wrong even once they're clamped, so a
-- swap snaps instead.
local function unitSwapped(f)
    local guid = UnitExists(f.unit) and UnitGUID(f.unit) or nil
    if guid ~= f.lastGUID then
        f.lastGUID = guid
        return true
    end
    return false
end

-- A pulse costs a script call every frame for as long as it is registered,
-- so the handler is attached only while something is actually pulsing rather
-- than left running to check a flag.
local function setPulse(frame, on, restAlpha)
    if on then
        if not frame.pulsing then
            frame.pulsing = true
            frame.t = 0
            frame:SetScript("OnUpdate", frame.pulseFn)
        end
    elseif frame.pulsing then
        frame.pulsing = false
        frame:SetScript("OnUpdate", nil)
        frame:SetAlpha(restAlpha or 1)
    end
end

local function StatusText(unit)
    if not UnitIsConnected(unit) then return "Offline" end
    if UnitIsGhost(unit) then return "Ghost" end
    if UnitIsDead(unit) then return "Dead" end
    return nil
end

local function UpdateHealth(f, instant)
    local unit = f.unit
    if not UnitExists(unit) then return end
    local m = UnitHealthMax(unit)
    if not m or m <= 0 then m = 1 end
    local v = UnitHealth(unit) or 0
    local pct = v / m
    f.bar.health:SetStatusColor(ns.HealthColor(unit, pct))

    local status = StatusText(unit)
    local hp = f.texts.hp
    if status then
        if not UnitIsConnected(unit) then v = m else v = 0 end
        ns.Text(hp, status)
    else
        local mode = ns.db.hpFormat
        if mode == "value" then
            ns.Text(hp, ns.Short(v))
        elseif mode == "percent" then
            ns.Text(hp, math.floor(pct * 100 + 0.5) .. "%")
        else
            ns.Text(hp, ns.Short(v) .. " · " .. math.floor(pct * 100 + 0.5) .. "%")
        end
    end

    if instant then
        f.bar.health:SetInstant(v, m)
    else
        f.bar.health:SetValue(v, m)
    end
end

local function UpdatePower(f, instant)
    local unit = f.unit
    if not UnitExists(unit) then return end
    local m = UnitPowerMax(unit)
    local detached = f.cfg.powerDetach
    if not m or m <= 0 then
        f.bar:ShowPower(false)
        f.powerBar:Hide()
        ns.Text(f.texts.power, "")
        return
    end
    local target
    if detached then
        f.bar:ShowPower(false)
        f.powerBar:Show()
        target = f.powerBar
    else
        f.bar:ShowPower(true)
        f.powerBar:Hide()
        target = f.bar.power
    end
    local v = UnitPower(unit) or 0
    target:SetStatusColor(ns.PowerColor(unit))
    ns.Text(f.texts.power, ns.Short(v))
    if instant then
        target:SetInstant(v, m)
    else
        target:SetValue(v, m)
    end
end

local function UpdateName(f)
    local unit = f.unit
    if not UnitExists(unit) then return end
    ns.Text(f.texts.name, UnitName(unit) or "")
    ns.TextColor(f.texts.name, f.cfg.texts and f.cfg.texts.name, ns.NameColor(unit))
end

local function UpdateLevel(f)
    local unit = f.unit
    if not UnitExists(unit) then return end
    local lvl = UnitLevel(unit) or 0
    local cls = UnitClassification and UnitClassification(unit) or "normal"
    local c = classify[cls]
    local lv = f.texts.level

    local lt = f.cfg.texts and f.cfg.texts.level
    if lvl <= 0 or cls == "worldboss" then
        ns.Text(lv, "??")
        ns.TextColor(lv, lt, rank.elite[1], rank.elite[2], rank.elite[3])
    else
        ns.Text(lv, lvl)
        ns.TextColor(lv, lt, 0.76, 0.80, 0.87)
    end

    if c then
        f.gem:SetVertexColor(c.gem[1], c.gem[2], c.gem[3], 1)
        f.gem:Show()
    else
        f.gem:Hide()
    end

    if f.portraitOn then
        if c then
            f.pring:SetVertexColor(c.ring[1], c.ring[2], c.ring[3], 0.95)
            f.pglow:SetVertexColor(c.ring[1], c.ring[2], c.ring[3], 0.45)
            f.pglow:Show()
        else
            f.pring:SetVertexColor(1, 1, 1, 0.12)
            f.pglow:Hide()
        end
        f.bar:SetOutlineColor(nil)
    else
        if c then
            f.bar:SetOutlineColor(c.ring[1], c.ring[2], c.ring[3], 0.9)
        else
            f.bar:SetOutlineColor(nil)
        end
    end
end

local function UpdatePortrait(f)
    if not f.portraitOn or not UnitExists(f.unit) then return end
    local unit = f.unit
    if ns.db.classIconPortraits and UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        local tc = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
        if tc then
            f.ptex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
            f.ptex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
            return
        end
    end
    SetPortraitTexture(f.ptex, unit)
    f.ptex:SetTexCoord(0.09, 0.91, 0.09, 0.91)
end

local function UpdateMood(f)
    if not f.mood then return end
    if not f.cfg.mood or not GetPetHappiness or not UnitExists("pet") then
        setPulse(f.mood, false, 0.95)
        f.mood:Hide()
        return
    end
    local h = GetPetHappiness()
    if not h then
        setPulse(f.mood, false, 0.95)
        f.mood:Hide()
        return
    end
    local c = ns.palette.happiness[h] or ns.palette.happiness[2]
    f.mood.tex:SetVertexColor(c[1], c[2], c[3])
    setPulse(f.mood, h == 1, 0.95)
    f.mood:Show()
end

local function UpdateRaidIcon(f)
    local idx = UnitExists(f.unit) and GetRaidTargetIndex(f.unit) or nil
    if idx then
        SetRaidTargetIconTexture(f.raidIcon, idx)
        f.raidIcon:Show()
    else
        f.raidIcon:Hide()
    end
end

local GOLD  = { 1, 0.82, 0.30 }
local EMBER = { 1, 0.42, 0.22 }

local function UpdateCombo(f)
    local c = f.combo
    if not c then return end
    local n = (GetComboPoints and GetComboPoints("player", "target")) or 0
    if not f.cfg.combo or n <= 0 or not UnitExists("target") then
        setPulse(c, false, 1)
        c:Hide()
        return
    end
    for i = 1, 5 do
        local pip = c.pips[i]
        if i <= n then
            local r, g, b = ns.Mix(GOLD, EMBER, (i - 1) / 4)
            pip.tex:SetVertexColor(r, g, b, 1)
        else
            pip.tex:SetVertexColor(0.13, 0.14, 0.18, 0.85)
        end
    end
    setPulse(c, n >= 5, 1)
    c:Show()
end

local function FullUpdate(f)
    if not UnitExists(f.unit) then
        f.lastGUID = nil
        return
    end
    unitSwapped(f)   -- record identity; this update is already instant
    if f.castBar and ns.CastCheck then ns.CastCheck(f) end
    UpdateName(f)
    UpdateLevel(f)
    UpdateHealth(f, true)
    UpdatePower(f, true)
    UpdatePortrait(f)
    UpdateRaidIcon(f)
    if f.mood then UpdateMood(f) end
    if f.combo then UpdateCombo(f) end
    if f.debuffC then f.debuffC:Update() end
    if f.buffC then f.buffC:Update() end
end

-- event handlers ----------------------------------------------------------

local handlers = {}

-- castbar -----------------------------------------------------------------
-- The same shell as every other bar -- same corners, finish, border, shadow --
-- with a rounded spell icon set into the left cap, the spell name, and a
-- timer. Interruptible casts fill warm gold; uninterruptible ones go cold
-- grey, which is the read that matters in PvP and on bosses. Channels drain
-- instead of filling. An interrupted cast flashes red and melts away.

local CAST_COLOR    = { 0.97, 0.78, 0.32 }
local NOINT_COLOR   = { 0.48, 0.51, 0.58 }
local INTERRUPT_RED = { 0.92, 0.30, 0.26 }

local function CastTick(cb)
    local now = GetTime() * 1000
    if cb.flashT then
        cb.flashT = cb.flashT - (now - (cb.lastNow or now)) / 1000
        cb.lastNow = now
        local a = math.max(0, math.min(1, cb.flashT / 0.45))
        cb:SetAlpha(a)
        if cb.flashT <= 0 then
            cb.flashT = nil
            cb:SetScript("OnUpdate", nil)
            cb:Hide()
            cb:SetAlpha(1)
        end
        return
    end
    cb.lastNow = now
    if cb.shownAt and (now - cb.shownAt) < 160 then
        cb:SetAlpha(math.min(1, (now - cb.shownAt) / 150))
    elseif cb.shownAt then
        cb.shownAt = nil
        cb:SetAlpha(1)
    end
    local dur = cb.endMS - cb.startMS
    if dur <= 0 then dur = 1 end
    local frac
    if cb.channel then
        frac = (cb.endMS - now) / dur
    else
        frac = (now - cb.startMS) / dur
    end
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    cb:SetInstant(frac, 1)
    if cb.timer and cb.owner.cfg.castTime ~= false then
        local left = math.max(0, (cb.endMS - now) / 1000)
        ns.Text(cb.timer, left >= 10 and math.floor(left + 0.5) or string.format("%.1f", left))
    end
    if now >= cb.endMS then
        cb:SetInstant(cb.channel and 0 or 1, 1)
        cb.flashT = 0.35
    end
end

local function CastApplyState(cb)
    local c = cb.noInt and NOINT_COLOR or CAST_COLOR
    cb:SetStatusColor(c[1], c[2], c[3])
    cb:SetOutlineColor(nil)
end

local function StartCast(f, channel)
    local cb = f.castBar
    if not cb or not f.cfg.castbar then return end
    local name, _, texture, startMS, endMS, _, _, noInt
    if channel then
        local ok
        -- name, text, texture, startMS, endMS, isTradeSkill, notInterruptible
        ok, name, _, texture, startMS, endMS, _, noInt = pcall(UnitChannelInfo, f.unit)
        if not ok then name = nil end
    else
        local ok, castID
        -- name, text, texture, startMS, endMS, isTradeSkill, castID, notInterruptible
        ok, name, _, texture, startMS, endMS, _, castID, noInt = pcall(UnitCastingInfo, f.unit)
        if not ok then name = nil end
        cb.castID = castID
    end
    if not name or not startMS or not endMS then
        return
    end
    cb.channel = channel and true or false
    if channel then cb.castID = nil end
    cb.startMS, cb.endMS = startMS, endMS
    cb.noInt = noInt and true or false
    cb.flashT = nil
    cb:SetAlpha(1)
    ns.Text(cb.spell, name)
    if cb.icon then
        cb.icon:SetTexture(texture or 136243)
        cb.iconF:SetShown(f.cfg.castIcon ~= false)
    end
    CastApplyState(cb)
    cb:SetInstant(cb.channel and 1 or 0, 1)
    cb:Show()
    cb:SetScript("OnUpdate", CastTick)
end

local function sameCast(cb, castGUID)
    if not castGUID or not cb.castID then return true end
    return castGUID == cb.castID
end

-- the cast finished on its own: hold the full bar for a beat and fade, so a
-- half-second Multi-Shot leaves a visible trace instead of blinking
local function CompleteCast(f)
    local cb = f.castBar
    if not cb or not cb:IsShown() or cb.flashT then return end
    cb:SetInstant(cb.channel and 0 or 1, 1)
    cb.flashT = 0.35
    cb.lastNow = GetTime() * 1000
    cb:SetScript("OnUpdate", CastTick)
end

local function StopCast(f, interrupted)
    local cb = f.castBar
    if not cb or not cb:IsShown() then return end
    if interrupted then
        cb:SetStatusColor(INTERRUPT_RED[1], INTERRUPT_RED[2], INTERRUPT_RED[3])
        cb:SetInstant(1, 1)
        ns.Text(cb.spell, "Interrupted")
        ns.Text(cb.timer, "")
        cb.flashT = 0.8
        cb.lastNow = GetTime() * 1000
        cb:SetScript("OnUpdate", CastTick)
    else
        cb:SetScript("OnUpdate", nil)
        cb:Hide()
    end
end

-- a frame's unit may already be mid-cast when we acquire it (new target)
local function CastCheck(f)
    if not f.castBar or not f.cfg.castbar then
        if f.castBar then StopCast(f) end
        return
    end
    local ok, name = pcall(UnitCastingInfo, f.unit)
    if ok and name then
        StartCast(f, false)
        return
    end
    local ok2, cname = pcall(UnitChannelInfo, f.unit)
    if ok2 and cname then
        StartCast(f, true)
        return
    end
    StopCast(f)
end
ns.CastCheck = CastCheck

-- An instant that never casts (this client's Multi-Shot) still deserves its
-- moment on the castbar: full gold bar with the spell's name and icon,
-- fading over half a second. A real cast in progress is never stomped.
function ns.FlashInstant(f, name, spellId)
    local cb = f and f.castBar
    if not cb or not f.cfg.castbar then return end
    if cb:IsShown() and not cb.flashT then return end
    cb.channel = false
    cb.castID = nil
    cb.noInt = false
    CastApplyState(cb)
    ns.Text(cb.spell, name or "")
    ns.Text(cb.timer, "")
    local tex
    if spellId then
        if C_Spell and C_Spell.GetSpellTexture then
            local ok, t = pcall(C_Spell.GetSpellTexture, spellId)
            if ok then tex = t end
        end
        if not tex and GetSpellTexture then
            local ok, t = pcall(GetSpellTexture, spellId)
            if ok then tex = t end
        end
    end
    if cb.icon then
        if tex then
            cb.icon:SetTexture(tex)
            cb.iconF:SetShown(f.cfg.castIcon ~= false)
        else
            cb.iconF:Hide()
        end
    end
    cb:SetInstant(1, 1)
    cb.shownAt = nil
    cb:SetAlpha(1)
    cb.flashT = 0.5
    cb.lastNow = GetTime() * 1000
    cb:Show()
    cb:SetScript("OnUpdate", CastTick)
end

-- layout mode needs something to drag: a frozen sample cast
function ns.ShowCastSample(f, on)
    local cb = f.castBar
    if not cb then return end
    if on and f.cfg.castbar then
        cb:SetScript("OnUpdate", nil)
        cb.flashT = nil
        cb:SetAlpha(1)
        CastApplyState(cb)
        cb.noInt = false
        cb:SetStatusColor(CAST_COLOR[1], CAST_COLOR[2], CAST_COLOR[3])
        ns.Text(cb.spell, "Castbar")
        ns.Text(cb.timer, "1.4")
        if cb.icon then
            cb.icon:SetTexture(136243)
            cb.iconF:SetShown(f.cfg.castIcon ~= false)
        end
        cb:SetInstant(0.6, 1)
        cb:Show()
    else
        CastCheck(f)
    end
end

-- /silk trace: record exactly what the client sends around a cast, plus what
-- UnitCastingInfo reports at that instant, into a window that can be copied.
-- This is the ground truth the simulator cannot provide.
local trace = { on = false, lines = {} }
ns.castTrace = trace

local function traceLine(event, a1, a2, a3)
    if not trace.on or a1 ~= "player" then return end
    local ok, name, _, _, startMS, endMS, _, castID = pcall(UnitCastingInfo, "player")
    local api = (ok and name) and string.format("API: %s %d-%d id=%s", name,
        startMS or 0, endMS or 0, tostring(castID)) or "API: nothing"
    trace.lines[#trace.lines + 1] = string.format("%.2f  %-30s a2=%s a3=%s | %s",
        GetTime(), event, tostring(a2), tostring(a3), api)
    if #trace.lines > 200 then table.remove(trace.lines, 1) end
end
ns.TraceCast = traceLine

function ns.ToggleCastTrace()
    if not trace.on then
        trace.on = true
        trace.lines = {}
        trace.t0 = GetTime()
        ns.Print("cast trace ON for 25 seconds — cast a few Multi-Shots and Steady Shots with auto shot running.")
        C_Timer.After(25, function()
            trace.on = false
            ns.ShowCastTrace()
        end)
    else
        trace.on = false
        ns.ShowCastTrace()
    end
end

function ns.ShowCastTrace()
    local w = ns.traceWindow
    if not w then
        w = CreateFrame("Frame", "SilkTraceWindow", UIParent)
        w:SetSize(700, 420)
        w:SetPoint("CENTER")
        w:SetFrameStrata("DIALOG")
        w:SetMovable(true)
        w:EnableMouse(true)
        w:RegisterForDrag("LeftButton")
        w:SetScript("OnDragStart", w.StartMoving)
        w:SetScript("OnDragStop", w.StopMovingOrSizing)
        local bg = w:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.05, 0.06, 0.08, 0.96)
        local sf = CreateFrame("ScrollFrame", nil, w)
        sf:SetPoint("TOPLEFT", 10, -30)
        sf:SetPoint("BOTTOMRIGHT", -10, 10)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFont("Fonts\\ARIALN.TTF", 12, "")
        eb:SetWidth(670)
        sf:SetScrollChild(eb)
        eb:SetScript("OnEscapePressed", function() w:Hide() end)
        local title = w:CreateFontString(nil, "OVERLAY")
        title:SetFont("Fonts\\ARIALN.TTF", 13, "")
        title:SetPoint("TOPLEFT", 12, -10)
        title:SetText("Silk cast trace — Ctrl-A, Ctrl-C, paste it to me. Esc closes.")
        title:SetTextColor(0.61, 0.90, 1.00)
        w.eb = eb
        ns.traceWindow = w
    end
    local hdr = string.format("Silk %s | class %s | ranged speed %.2f | %d lines\n",
        tostring(ns.version or "?"), tostring(select(2, UnitClass("player"))),
        (ns.swing and ns.swing.rg.speed) or 0, #trace.lines)
    w.eb:SetText(hdr .. table.concat(trace.lines, "\n"))
    w:Show()
    w.eb:SetFocus()
    w.eb:HighlightText()
end

local function BuildCastBar(f)
    local cb = ns.CreateBar(f, "cast")
    cb.owner = f
    cb:Hide()

    local tl = CreateFrame("Frame", nil, cb)
    tl:SetAllPoints(cb)
    tl:SetFrameLevel(cb:GetFrameLevel() + 10)

    -- rounded icon set into the left end, same language as the aura icons
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
    cb.iconF, cb.icon = iconF, icon

    cb.spell = ns.NewText(tl)
    cb.spell:SetPoint("LEFT", cb, "LEFT", 8, 0)
    cb.timer = ns.NewText(tl)
    cb.timer:SetPoint("RIGHT", cb, "RIGHT", -9, 0)
    cb.tl = tl

    cb:SetScript("OnShow", function(b)
        b.shownAt = GetTime() * 1000
        b.tl:SetFrameLevel(b:GetFrameLevel() + 10)
        if b.overlayMode then
            if f.txtLayer then f.txtLayer:SetAlpha(0) end
            if f.bgLayer then f.bgLayer:SetAlpha(0) end
        end
    end)
    cb:SetScript("OnHide", function(b)
        if f.txtLayer then f.txtLayer:SetAlpha(1) end
        if f.bgLayer then f.bgLayer:SetAlpha(1) end
    end)

    f.castBar = cb
    return cb
end

function ns.CastMode(cfg)
    if cfg.castMode then return cfg.castMode end
    if cfg.castDetach then return "free" end
    return "below"
end

-- Inside mode: the cast takes over the unit's own capsule. The castbar sits
-- exactly on the bar's rect, above the text layers, with its own border and
-- shadow switched off so the frame's border -- an elite's gold ring
-- included -- stays visible around the sweep. Name and health fade out for
-- the duration; spell icon, name and time take their places.
local function ApplyCastLayout(f)
    local cb = f.castBar
    if not cb then return end
    local cfg = f.cfg
    if not cfg.castbar then
        StopCast(f)
        return
    end
    local mode = ns.CastMode(cfg)
    local h = cfg.castH or 18
    cb.overlayMode = (mode == "inside")
    cb:ClearAllPoints()
    if mode == "inside" then
        cb:SetAllPoints(f.bar)
        cb:SetFrameLevel(f:GetFrameLevel() + 12)
        if cb.inner and cb.inner.SetFrameLevel then
            cb.inner:SetFrameLevel(f:GetFrameLevel() + 13)
        end
        h = cfg.h
    elseif mode == "free" then
        cb:SetFrameLevel(f:GetFrameLevel() + 1)
        cb:SetPoint("CENTER", UIParent, "CENTER", cfg.castPos[1], cfg.castPos[2])
        cb:SetSize((cfg.castW or 0) > 0 and cfg.castW or cfg.w, h)
    else
        cb:SetFrameLevel(f:GetFrameLevel() + 1)
        cb:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -6)
        cb:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -6)
        cb:SetHeight(h)
    end
    cb:ApplyStyle()
    if cb.overlayMode then
        -- the frame provides the border and shadow; the castbar only paints inside
        cb.outline:SetAlpha(0)
        if cb.drop then cb.drop:SetAlpha(0) end
    else
        cb.outline:SetAlpha(1)
    end
    local pad = math.max(2, math.floor(h * 0.14))
    local isz = h - pad * 2
    cb.iconF:SetSize(isz, isz)
    cb.iconF:ClearAllPoints()
    cb.iconF:SetPoint("LEFT", cb, "LEFT", pad + 1, 0)
    cb.spell:ClearAllPoints()
    cb.spell:SetPoint("LEFT", cb, "LEFT",
        (cfg.castIcon ~= false) and (isz + pad * 2 + 4) or 9, 0)
    ns.SetFont(cb.spell, -1)
    ns.SetFont(cb.timer, -2)
    ns.TextColor(cb.spell, nil, 0.94, 0.96, 0.99)
    ns.TextColor(cb.timer, nil, ns.palette.text[1], ns.palette.text[2], ns.palette.text[3])
end
ns.ApplyCastLayout = ApplyCastLayout

-- The WeakAuras method: events are only a wake-up call. What the bar shows
-- is whatever the client says is being cast RIGHT NOW. If the API says a
-- cast is in progress, it's on the bar regardless of what event arrived; if
-- the API says nothing is, the bar finishes. Stray events for other casts
-- can't touch it because they aren't consulted.
local function ResyncCast(f, event, castGUID)
    local cb = f.castBar
    if not cb or not f.cfg.castbar then return end
    local ok, name, _, _, _, _, _, castID = pcall(UnitCastingInfo, f.unit)
    if ok and name then
        if not cb:IsShown() or cb.flashT or cb.channel or (castID and cb.castID ~= castID) then
            StartCast(f, false)
        end
        return
    end
    local ok2, cname = pcall(UnitChannelInfo, f.unit)
    if ok2 and cname then
        if not cb:IsShown() or cb.flashT or not cb.channel then
            StartCast(f, true)
        end
        return
    end
    -- nothing is being cast: whatever is on the bar is over
    if cb:IsShown() and not cb.flashT then
        if event == "UNIT_SPELLCAST_INTERRUPTED" and sameCast(cb, castGUID) then
            StopCast(f, true)
        elseif (event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET")
            and sameCast(cb, castGUID) then
            StopCast(f)
        elseif cb.channel then
            StopCast(f)
        else
            CompleteCast(f)
        end
    end
end

handlers.UNIT_SPELLCAST_START = function(f, unit)
    if unit == f.unit then StartCast(f, false) end
end
handlers.UNIT_SPELLCAST_CHANNEL_START = function(f, unit)
    if unit == f.unit then StartCast(f, true) end
end
handlers.UNIT_SPELLCAST_DELAYED = function(f, unit)
    if unit == f.unit and f.castBar and f.castBar:IsShown() then StartCast(f, false) end
end
handlers.UNIT_SPELLCAST_CHANNEL_UPDATE = function(f, unit)
    if unit == f.unit and f.castBar and f.castBar:IsShown() then StartCast(f, true) end
end
handlers.UNIT_SPELLCAST_STOP = function(f, unit, castGUID)
    if unit == f.unit then ResyncCast(f, "UNIT_SPELLCAST_STOP", castGUID) end
end
handlers.UNIT_SPELLCAST_SUCCEEDED = function(f, unit, castGUID)
    if unit == f.unit then ResyncCast(f, "UNIT_SPELLCAST_SUCCEEDED", castGUID) end
end
handlers.UNIT_SPELLCAST_CHANNEL_STOP = function(f, unit)
    if unit == f.unit then StopCast(f) end
end
handlers.UNIT_SPELLCAST_INTERRUPTED = function(f, unit, castGUID)
    if unit == f.unit then ResyncCast(f, "UNIT_SPELLCAST_INTERRUPTED", castGUID) end
end
handlers.UNIT_SPELLCAST_FAILED = function(f, unit, castGUID)
    if unit == f.unit then ResyncCast(f, "UNIT_SPELLCAST_FAILED", castGUID) end
end
handlers.UNIT_SPELLCAST_FAILED_QUIET = function(f, unit, castGUID)
    if unit == f.unit then ResyncCast(f, "UNIT_SPELLCAST_FAILED_QUIET", castGUID) end
end
handlers.UNIT_SPELLCAST_INTERRUPTIBLE = function(f, unit)
    if unit == f.unit and f.castBar and f.castBar:IsShown() then
        f.castBar.noInt = false
        CastApplyState(f.castBar)
    end
end
handlers.UNIT_SPELLCAST_NOT_INTERRUPTIBLE = function(f, unit)
    if unit == f.unit and f.castBar and f.castBar:IsShown() then
        f.castBar.noInt = true
        CastApplyState(f.castBar)
    end
end

handlers.UNIT_HEALTH = function(f, unit)
    if unit == f.unit then UpdateHealth(f) end
end
handlers.UNIT_HEALTH_FREQUENT = handlers.UNIT_HEALTH
handlers.UNIT_MAXHEALTH = handlers.UNIT_HEALTH

handlers.UNIT_POWER_UPDATE = function(f, unit)
    if unit == f.unit then UpdatePower(f) end
    if f.combo and unit == "player" then UpdateCombo(f) end
end
handlers.UNIT_POWER_FREQUENT = handlers.UNIT_POWER_UPDATE
handlers.UNIT_MAXPOWER = handlers.UNIT_POWER_UPDATE
handlers.UNIT_DISPLAYPOWER = handlers.UNIT_POWER_UPDATE

handlers.UNIT_NAME_UPDATE = function(f, unit)
    if unit == f.unit then UpdateName(f) end
end
handlers.UNIT_FACTION = function(f, unit)
    if unit == f.unit then
        UpdateHealth(f)
        UpdateName(f)
    end
end
handlers.UNIT_LEVEL = function(f, unit)
    if unit == f.unit then UpdateLevel(f) end
end
handlers.UNIT_CONNECTION = function(f, unit)
    if unit == f.unit then
        UpdateHealth(f)
        UpdatePower(f)
    end
end
handlers.UNIT_AURA = function(f, unit)
    if unit ~= f.unit then return end
    if f.debuffC then f.debuffC:Update() end
    if f.buffC then f.buffC:Update() end
end
handlers.UNIT_PORTRAIT_UPDATE = function(f, unit)
    if unit == f.unit then UpdatePortrait(f) end
end
handlers.UNIT_MODEL_CHANGED = handlers.UNIT_PORTRAIT_UPDATE

handlers.PLAYER_TARGET_CHANGED = function(f)
    FullUpdate(f)
    if f.key == "target" and UnitExists("target") and not InCombatLockdown() then
        UIFrameFadeIn(f, 0.14, 0.3, 1)
    end
end
handlers.PLAYER_FOCUS_CHANGED = function(f)
    FullUpdate(f)
end
handlers.UNIT_PET = function(f, unit)
    if unit == "player" then FullUpdate(f) end
end
handlers.UNIT_HAPPINESS = function(f)
    UpdateMood(f)
end
handlers.PLAYER_COMBO_POINTS = function(f)
    UpdateCombo(f)
end
handlers.RAID_TARGET_UPDATE = function(f)
    UpdateRaidIcon(f)
end
handlers.PLAYER_ENTERING_WORLD = function(f)
    FullUpdate(f)
end

-- construction ------------------------------------------------------------

local function Skeleton(f)
    -- portrait
    local p = CreateFrame("Frame", nil, f)
    f.pholder = p

    local glow = p:CreateTexture(nil, "BACKGROUND", nil, -8)
    glow:SetTexture(ns.TEX.ringGlow)
    glow:SetBlendMode("ADD")
    glow:SetPoint("CENTER")
    glow:Hide()
    f.pglow = glow

    local back = p:CreateTexture(nil, "BACKGROUND", nil, -6)
    back:SetTexture(ns.TEX.circle)
    back:SetAllPoints(p)
    back:SetVertexColor(ns.palette.charcoal[1], ns.palette.charcoal[2], ns.palette.charcoal[3], 0.92)

    local pmask = p:CreateMaskTexture()
    pmask:SetPoint("TOPLEFT", 2, -2)
    pmask:SetPoint("BOTTOMRIGHT", -2, 2)
    pmask:SetTexture(ns.TEX.circle, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

    local ptex = p:CreateTexture(nil, "ARTWORK")
    ptex:SetPoint("TOPLEFT", 2, -2)
    ptex:SetPoint("BOTTOMRIGHT", -2, 2)
    ptex:AddMaskTexture(pmask)
    f.ptex = ptex

    local ring = p:CreateTexture(nil, "OVERLAY")
    ring:SetAllPoints(p)
    ring:SetTexture(ns.TEX.ring)
    ring:SetVertexColor(1, 1, 1, 0.12)
    f.pring = ring

    -- one capsule holding both health and power
    f.bar = ns.CreateUnitBar(f)
    f.health = f.bar.health
    -- used only when the power bar is detached; hidden otherwise
    f.powerBar = ns.CreateBar(f, "power")
    f.powerBar:Hide()
    f.power = f.bar.power

    -- backdrop layer sits just under the text layer, both above the bars
    local bl = CreateFrame("Frame", nil, f)
    bl:SetAllPoints(f)
    bl:SetFrameLevel(f:GetFrameLevel() + 9)
    local tl = CreateFrame("Frame", nil, f)
    tl:SetAllPoints(f)
    tl:SetFrameLevel(f:GetFrameLevel() + 10)
    f.txtLayer, f.bgLayer = tl, bl

    f.texts = {}
    local keys = { "name", "hp", "power", "level" }
    for i = 1, #keys do
        local fs = ns.NewText(tl)
        ns.AttachTextBg(fs, bl)
        f.texts[keys[i]] = fs
    end

    -- rank gem
    local gem = tl:CreateTexture(nil, "OVERLAY", nil, 2)
    gem:SetTexture(ns.TEX.gem)
    gem:SetPoint("RIGHT", f.texts.level, "LEFT", -2, 0)
    gem:Hide()
    f.gem = gem

    -- raid marker
    local ri = tl:CreateTexture(nil, "OVERLAY", nil, 3)
    ri:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    ri:SetSize(16, 16)
    ri:SetPoint("CENTER", f, "TOP", 0, 1)
    ri:Hide()
    f.raidIcon = ri
end

local function ApplyTextPositions(f)
    local cfg = f.cfg
    for key, fs in pairs(f.texts) do
        local base = (key == "name") and 0 or -1
        local t = cfg.texts and cfg.texts[key]
        -- when the power bar floats free, its number goes with it
        local host = f
        if key == "power" and cfg.powerDetach then host = f.powerBar end
        fs.__cfg = t
        if t then
            fs:ClearAllPoints()
            fs:SetPoint(t[1], host, t[1], t[2], t[3])
            ns.SetFont(fs, base + (t.size or 0), t)
            if key == "hp" or key == "power" then
                local p = ns.palette.text
                ns.TextColor(fs, t, p[1], p[2], p[3])
            end
            if t.show == false then fs:Hide() else fs:Show() end
        else
            ns.SetFont(fs, base)
        end
        ns.RefreshTextBg(fs, t)
        if ns.SyncHaloText then ns.SyncHaloText(fs) end
    end
end
ns.ApplyTextPositions = ApplyTextPositions

local function ApplySizes(f)
    local cfg = f.cfg
    local db = ns.db
    f:SetScale(db.scale or 1)
    f:SetSize(cfg.w, cfg.h)

    local ph = math.max(5, math.floor(cfg.h * 0.20 + 0.5))
    local left = 0
    f.portraitOn = cfg.portrait and true or false
    if f.portraitOn then
        f.pholder:Show()
        f.pholder:SetSize(cfg.h, cfg.h)
        f.pholder:ClearAllPoints()
        f.pholder:SetPoint("LEFT", 0, 0)
        f.pglow:SetSize(cfg.h * 1.45, cfg.h * 1.45)
        left = cfg.h + 7
    else
        f.pholder:Hide()
    end

    -- the bar always fills the frame; power is a slice inside it
    f.bar:ClearAllPoints()
    f.bar:SetPoint("TOPLEFT", left, 0)
    f.bar:SetPoint("TOPRIGHT", 0, 0)
    f.bar:SetHeight(cfg.h)

    f.powerBar:ClearAllPoints()
    if cfg.powerDetach then
        f.bar:ShowPower(false)
        f.powerBar:SetPoint("CENTER", UIParent, "CENTER", cfg.powerPos[1], cfg.powerPos[2])
        f.powerBar:SetSize(
            (cfg.powerW or 0) > 0 and cfg.powerW or (cfg.w - left),
            (cfg.powerH or 0) > 0 and cfg.powerH or ph)
        f.powerBar:Show()
    else
        f.bar:SetPowerHeight((cfg.powerH or 0) > 0 and cfg.powerH or ph)
        f.bar:ShowPower(true)
        f.powerBar:Hide()
    end

    f.bar:ApplyStyle()
    f.powerBar:ApplyStyle()
    ApplyCastLayout(f)
    if ns.ApplySwingLayout then ns.ApplySwingLayout(f) end

    f.gem:SetSize((db.fontSize or 12) + 2, (db.fontSize or 12) + 2)
    ApplyTextPositions(f)

    if f.debuffC then
        f.debuffC:Reanchor()
        f.debuffC:Update()
    end
    if f.buffC then
        f.buffC:Reanchor()
        f.buffC:Update()
    end

    if f.mood then
        f.mood:ClearAllPoints()
        if f.portraitOn then
            f.mood:SetPoint("CENTER", f.pholder, "TOPRIGHT", -4, -4)
        else
            f.mood:SetPoint("CENTER", f, "TOPRIGHT", -2, 0)
        end
    end
    if f.combo then
        for i = 1, 5 do
            f.combo.pips[i]:SetCapStyle(db.corner)
        end
    end
end

local function ApplyPosition(f)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", f.cfg.pos[1], f.cfg.pos[2])
end

local function ApplyWatch(f)
    if f.cfg.enabled then
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

local function Spawn(key)
    local unit = key
    local f = CreateFrame("Button", "Silk" .. key, UIParent, "SecureUnitButtonTemplate")
    f.key, f.unit = key, unit
    f.cfg = ns.db.frames[key]
    f:SetAttribute("unit", unit)
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")
    f:RegisterForClicks("AnyUp")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetFrameStrata("LOW")

    Skeleton(f)

    -- tooltip
    f:SetScript("OnEnter", function(s)
        GameTooltip_SetDefaultAnchor(GameTooltip, s)
        GameTooltip:SetUnit(s.unit)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- auras
    if f.cfg.auras then
        f.debuffC = ns.AttachAuras(f, unit, "TOP", function()
            local a = f.cfg.auras
            return { enabled = a.debuffs, helpful = false, size = a.size,
                     perRow = a.perRow, maxShown = a.maxShown, onlyMine = a.onlyMine,
                     spacing = a.spacing, x = a.dx, y = a.dy,
                     detach = a.dDetach, px = a.dPos and a.dPos[1], py = a.dPos and a.dPos[2],
                     growX = a.dGrowX, growY = a.dGrowY }
        end)
        f.buffC = ns.AttachAuras(f, unit, "BOTTOM", function()
            local a = f.cfg.auras
            return { enabled = a.buffs, helpful = true,
                     size = (a.bSize or 0) > 0 and a.bSize or a.size,
                     perRow = (a.bPerRow or 0) > 0 and a.bPerRow or a.perRow,
                     maxShown = a.maxShown, onlyMine = false,
                     spacing = a.spacing, x = a.bx, y = a.by,
                     detach = a.bDetach, px = a.bPos and a.bPos[1], py = a.bPos and a.bPos[2],
                     growX = a.bGrowX, growY = a.bGrowY }
        end)
    end

    -- combo pips (target)
    if key == "target" then
        local c = CreateFrame("Frame", nil, f)
        c:SetSize(5 * 22 - 4, 8)
        c:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -6)
        c.pips = {}
        for i = 1, 5 do
            local pip = ns.Capsule(c)
            pip:SetSize(18, 7)
            pip:SetPoint("LEFT", (i - 1) * 22, 0)
            local t = pip:CreateTexture(nil, "ARTWORK")
            t:SetAllPoints()
            t:SetColorTexture(1, 1, 1)
            t:SetVertexColor(0.13, 0.14, 0.18, 0.85)
            pip:AddMasked(t)
            pip:SetCapStyle(ns.db.corner)
            pip.tex = t
            c.pips[i] = pip
        end
        c:SetScript("OnHide", function(s) setPulse(s, false, 1) end)
        c.pulseFn = function(s, dt)
            s.t = (s.t or 0) + dt * 5
            s:SetAlpha(0.8 + 0.2 * math.abs(math.sin(s.t)))
        end
        c:Hide()
        f.combo = c
    end

    -- mood dot (pet)
    if key == "pet" then
        local m = CreateFrame("Frame", nil, f)
        m:SetSize(10, 10)
        m:SetFrameLevel(f:GetFrameLevel() + 5)
        local t = m:CreateTexture(nil, "OVERLAY")
        t:SetAllPoints()
        t:SetTexture(ns.TEX.dot)
        m.tex = t
        m:SetScript("OnHide", function(s) setPulse(s, false, 0.95) end)
        m.pulseFn = function(s, dt)
            s.t = (s.t or 0) + dt * 5
            s:SetAlpha(0.5 + 0.45 * math.abs(math.sin(s.t)))
        end
        m:Hide()
        f.mood = m
    end

    -- events
    f:SetScript("OnEvent", function(s, event, a1, a2, a3)
        if s.key == "player" and ns.castTrace and ns.castTrace.on
            and type(event) == "string" and event:find("SPELLCAST", 1, true) then
            ns.TraceCast(event, a1, a2, a3)
        end
        local h = handlers[event]
        if h then h(s, a1, a2, a3) end
    end)

    ns.RegSafe(f, "UNIT_HEALTH", unit)
    ns.RegSafe(f, "UNIT_HEALTH_FREQUENT", unit)
    ns.RegSafe(f, "UNIT_MAXHEALTH", unit)
    if key == "target" then
        ns.RegSafe(f, "UNIT_POWER_UPDATE", unit, "player")
        ns.RegSafe(f, "UNIT_POWER_FREQUENT", unit, "player")
    else
        ns.RegSafe(f, "UNIT_POWER_UPDATE", unit)
        ns.RegSafe(f, "UNIT_POWER_FREQUENT", unit)
    end
    ns.RegSafe(f, "UNIT_MAXPOWER", unit)
    ns.RegSafe(f, "UNIT_DISPLAYPOWER", unit)
    ns.RegSafe(f, "UNIT_NAME_UPDATE", unit)
    ns.RegSafe(f, "UNIT_LEVEL", unit)
    ns.RegSafe(f, "UNIT_FACTION", unit)
    ns.RegSafe(f, "UNIT_CONNECTION", unit)
    ns.RegSafe(f, "UNIT_AURA", unit)
    if key == "player" or key == "target" or key == "focus" then
        BuildCastBar(f)
        if key == "player" then
            ns.BuildPlayerSwing(f)
        else
            ns.BuildEnemySwing(f)
        end
        for _, e in ipairs({
            "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
            "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET",
            "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED",
            "UNIT_SPELLCAST_DELAYED",
            "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
            "UNIT_SPELLCAST_CHANNEL_STOP",
            "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
        }) do
            ns.RegSafe(f, e, unit)
        end
    end
    ns.RegSafe(f, "UNIT_PORTRAIT_UPDATE", unit)
    ns.RegSafe(f, "UNIT_MODEL_CHANGED", unit)
    pcall(f.RegisterEvent, f, "RAID_TARGET_UPDATE")
    pcall(f.RegisterEvent, f, "PLAYER_ENTERING_WORLD")
    if key == "target" or key == "targettarget" then
        pcall(f.RegisterEvent, f, "PLAYER_TARGET_CHANGED")
    end
    if key == "target" then
        pcall(f.RegisterEvent, f, "PLAYER_COMBO_POINTS")
    end
    if key == "focus" then
        pcall(f.RegisterEvent, f, "PLAYER_FOCUS_CHANGED")
    end
    if key == "pet" then
        ns.RegSafe(f, "UNIT_PET", "player")
        ns.RegSafe(f, "UNIT_HAPPINESS", "pet")
    end

    f:SetScript("OnShow", FullUpdate)

    ns.units[key] = f
    return f
end

-- refresh + boot ----------------------------------------------------------

local function RefreshFrames()
    HideBlizzard()
    ApplyBlizzardBuffs()
    for key, f in pairs(ns.units) do
        f.cfg = ns.db.frames[key]
        ApplySizes(f)
        ApplyPosition(f)
        ApplyWatch(f)
        if f:IsShown() then FullUpdate(f) end
    end
end
table.insert(ns.refreshers, RefreshFrames)

table.insert(ns.onLogin, function()
    HideBlizzard()
    -- party frames in particular are often built the first time you group,
    -- long after login, so keep checking on the events that create them
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    pcall(watcher.RegisterEvent, watcher, "CVAR_UPDATE")
    watcher:SetScript("OnEvent", HideBlizzard)
    for i = 1, #UNITS do
        Spawn(UNITS[i])
    end
    RefreshFrames()

    -- target-of-target has no events of its own: keep it fresh with a light poll
    C_Timer.NewTicker(0.3, function()
        local f = ns.units.targettarget
        if f and f:IsShown() and UnitExists(f.unit) then
            local snap = unitSwapped(f)
            UpdateName(f)
            UpdateHealth(f, snap)
            UpdatePower(f, snap)
            UpdateLevel(f)
            if snap or f.portraitOn then UpdatePortrait(f) end
        elseif f then
            f.lastGUID = nil
        end
    end)
end)
