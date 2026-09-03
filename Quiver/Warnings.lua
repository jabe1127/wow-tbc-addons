-- =========================================================================
-- Warnings.lua
-- Peripheral-vision feedback, ported from WeaveGrid:
--   melee glow  - orange band down from the top while inside melee range
--   swing fill  - white band filling right-to-left with your melee swing,
--                 only while OUT of melee
--   aspect      - wrong aspect up mid-fight
--   pet health  - pet getting hurt / pet about to die
-- Click-through and at the lowest strata: this has to read without being
-- looked at directly.
-- =========================================================================

local ADDON, TS = ...

local WING_CLIP  = 2974
local RAPTOR     = 2973
local GLOW_BANDS = 12

-- Aspects that should never be up mid-fight: Cheetah and Pack daze you when
-- struck, Monkey is the dodge aspect standing where Hawk belongs. Resolved
-- by ID once so names come back localised, then matched by name so every
-- rank is covered by one entry.
local ASPECT_IDS = { 5118, 13159, 13163 }
local badAspects

local function BuildAspectNames()
    if badAspects then return end
    badAspects = {}
    for _, id in ipairs(ASPECT_IDS) do
        local nm = TS.SpellName(id)
        if nm then badAspects[nm] = true end
    end
end

local wcfg
local glowFrame, swingFrame
local glowTex, swingTex = {}, {}
local aspectF, petWarnF, petDangerF
local glowMelee, glowAt = false, 0
local lastSwing = 0
local preview = false
local raptorName

-- ----------------------------------------------------------------- probe
local function ProbeMelee(unit)
    if C_Spell and C_Spell.IsSpellInRange then
        local ok, r = pcall(C_Spell.IsSpellInRange, WING_CLIP, unit)
        if ok and r ~= nil then return r == true or r == 1 end
    end
    if IsSpellInRange then
        local nm = TS.SpellName(WING_CLIP)
        if nm then return IsSpellInRange(nm, unit) == 1 end
    end
    return nil
end

-- ------------------------------------------------------------------ bands
-- Stacked bands of falling opacity fake a gradient; a flat block reads as a
-- UI panel rather than a glow.
local function LayoutBands()
    local H = wcfg.glowHeight
    local h = H / GLOW_BANDS
    glowFrame:SetHeight(H)
    swingFrame:SetHeight(H)
    local fall = wcfg.glowFalloff
    local gc, sc = wcfg.glowColor, wcfg.swingColor
    for i = 1, GLOW_BANDS do
        -- exponent is sharpness: 1.0 reads as a solid slab, 3.0 as a thin
        -- bright lip with a long soft tail
        local a = (1 - (i - 1) / GLOW_BANDS) ^ fall
        local t = glowTex[i]
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", glowFrame, "TOPLEFT", 0, -(i - 1) * h)
        t:SetPoint("TOPRIGHT", glowFrame, "TOPRIGHT", 0, -(i - 1) * h)
        t:SetHeight(h + 1)
        t:SetColorTexture(gc[1], gc[2], gc[3], a)
        local w = swingTex[i]
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", swingFrame, "TOPLEFT", 0, -(i - 1) * h)
        w:SetPoint("TOPRIGHT", swingFrame, "TOPRIGHT", 0, -(i - 1) * h)
        w:SetHeight(h + 1)
        w:SetColorTexture(sc[1], sc[2], sc[3], a)
    end
end

-- --------------------------------------------------------------- readouts
local function MakeReadout(key, width, dy, fontSize, outline)
    local f = CreateFrame("Frame", "QuiverWarn_" .. key, UIParent)
    f:SetSize(width, fontSize + 8)
    f:SetPoint("TOP", UIParent, "TOP", 0, dy)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(false)
    f:Hide()
    f.key, f.defDy = key, dy
    f.label = f:CreateFontString(nil, "OVERLAY")
    f.label:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.label:SetFont(TS.FONT, fontSize, outline or "OUTLINE")
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local pt, _, rp, x, y = self:GetPoint()
        TS.db.warnings.pos[self.key] = { pt, rp, x, y }
    end)
    return f
end

local function PlaceReadout(f)
    local saved = TS.db.warnings.pos[f.key]
    f:ClearAllPoints()
    if saved then
        f:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, f.defDy)
    end
end

-- ------------------------------------------------------------- 10Hz poll
local function Poll()
    if not wcfg then return end

    if preview then
        aspectF.label:SetText("|cffff6020ASPECT OF THE CHEETAH|r")
        aspectF:Show()
        petWarnF.label:SetText("|cffffcc20pet 62%|r")
        petWarnF:Show()
        petDangerF.label:SetText("|cffff2020PET 24%|r")
        petDangerF:Show()
        return
    end

    -- melee state, probed on its own so it never depends on anything else
    -- being switched on
    if wcfg.glow or wcfg.glowSwing then
        local u = "target"
        if UnitExists(u) and not UnitIsDeadOrGhost(u) then
            glowMelee = (ProbeMelee(u) == true)
        else
            glowMelee = false
        end
    end

    BuildAspectNames()

    -- wrong aspect, only while it can actually hurt you
    local bad
    if wcfg.showAspect and UnitAffectingCombat("player") then
        for i = 1, 40 do
            local name = UnitBuff and UnitBuff("player", i)
            if not name then break end
            if badAspects[name] then bad = name break end
        end
    end
    if bad then
        aspectF.label:SetText("|cffff6020" .. bad:upper() .. "|r")
        aspectF:Show()
    else
        aspectF:Hide()
    end

    -- pet health: the big readout takes over from the small one
    local pct
    if UnitExists("pet") and not UnitIsDead("pet") then
        local hp, mx = UnitHealth("pet"), UnitHealthMax("pet")
        if mx and mx > 0 then pct = hp / mx * 100 end
    end
    local danger = pct and wcfg.showPetDanger and pct < wcfg.petDangerPct
    local warn   = pct and wcfg.showPetWarn and pct < wcfg.petWarnPct and not danger
    if danger then
        petDangerF.label:SetText(string.format("|cffff2020PET %d%%|r", pct))
        petDangerF:Show()
    else
        petDangerF:Hide()
    end
    if warn then
        petWarnF.label:SetText(string.format("|cffffcc20pet %d%%|r", pct))
        petWarnF:Show()
    else
        petWarnF:Hide()
    end
end

-- ------------------------------------------------------------- per-frame
local function OnUpdate()
    if not wcfg then return end
    local now = GetTime()

    -- melee glow, eased both ways so a probe blip at the boundary can't
    -- strobe it
    if wcfg.glow then
        local want = preview and ((now % 6) > 3) or glowMelee
        local target = want and wcfg.glowAlpha or 0
        local dt = (glowAt > 0) and math.min(0.1, now - glowAt) or 0
        glowAt = now
        local cur = glowFrame:GetAlpha() or 0
        local step = dt * 6                 -- ~170ms to full, either way
        if math.abs(target - cur) <= step then
            cur = target
        else
            cur = cur + ((target > cur) and step or -step)
        end
        glowFrame:SetAlpha(cur)
        if cur > 0.01 then glowFrame:Show() else glowFrame:Hide() end
    else
        glowFrame:Hide()
    end

    -- white swing fill, only while OUT of melee, so the two never overlap
    if wcfg.glowSwing then
        local inMelee = preview and ((now % 6) > 3) or glowMelee
        local sw = UnitAttackSpeed("player") or 2.6
        if not sw or sw <= 0 then sw = 2.6 end
        local pct = 0
        if preview then
            pct = (now % sw) / sw
        elseif lastSwing > 0 then
            pct = math.min(1, (now - lastSwing) / sw)
        end
        if not inMelee and pct > 0 and pct < 1 then
            local screenW = UIParent:GetWidth() or 1920
            swingFrame:SetWidth(math.max(1, screenW * pct))
            swingFrame:SetAlpha(wcfg.glowSwingAlpha)
            swingFrame:Show()
        else
            swingFrame:Hide()
        end
    else
        swingFrame:Hide()
    end
end

-- ---------------------------------------------------------------- events
local function OnEvent(self, event)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, sub, _, srcGUID, _, _, _, _, _, _, _, _, spellName =
            CombatLogGetCurrentEventInfo()
        if srcGUID ~= UnitGUID("player") then return end
        if sub == "SWING_DAMAGE" or sub == "SWING_MISSED" then
            lastSwing = GetTime()
        elseif (sub == "SPELL_DAMAGE" or sub == "SPELL_MISSED")
               and spellName and spellName == raptorName then
            -- Raptor Strike replaces the swing in the log, so it resets the
            -- swing timer too
            lastSwing = GetTime()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        lastSwing = 0
        raptorName = TS.SpellName(RAPTOR)
    end
end

-- ---------------------------------------------------------------- config
local function ApplyConfig()
    wcfg = TS.db.warnings
    LayoutBands()
    aspectF.label:SetFont(TS.FONT, wcfg.fontWarn, "OUTLINE")
    petWarnF.label:SetFont(TS.FONT, wcfg.fontWarn, "OUTLINE")
    petDangerF.label:SetFont(TS.FONT, wcfg.fontDanger, "THICKOUTLINE")
    aspectF:SetHeight(wcfg.fontWarn + 8)
    petWarnF:SetHeight(wcfg.fontWarn + 8)
    petDangerF:SetHeight(wcfg.fontDanger + 10)
    for _, f in ipairs({ aspectF, petWarnF, petDangerF }) do PlaceReadout(f) end
    if not wcfg.glow then glowFrame:Hide() end
    if not wcfg.glowSwing then swingFrame:Hide() end
end

-- Unlocked: readouts become draggable and all three show at once so they
-- can be positioned. Never writes to the toggles.
local function SetPreview(on)
    preview = on
    for _, f in ipairs({ aspectF, petWarnF, petDangerF }) do
        f:EnableMouse(on)
        if not on then f:Hide() end
    end
    if not on then
        glowMelee = false
        Poll()
    end
end

TS.inits[#TS.inits + 1] = function(db)
    wcfg = db.warnings
    raptorName = TS.SpellName(RAPTOR)

    glowFrame = CreateFrame("Frame", "QuiverGlow", UIParent)
    glowFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    glowFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
    glowFrame:SetHeight(90)
    glowFrame:EnableMouse(false)
    glowFrame:SetFrameStrata("BACKGROUND")
    glowFrame:SetAlpha(0)
    glowFrame:Hide()

    swingFrame = CreateFrame("Frame", "QuiverGlowSwing", UIParent)
    swingFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
    swingFrame:SetHeight(90)
    swingFrame:EnableMouse(false)
    swingFrame:SetFrameStrata("BACKGROUND")
    swingFrame:SetAlpha(0)
    swingFrame:Hide()

    for i = 1, GLOW_BANDS do
        glowTex[i]  = glowFrame:CreateTexture(nil, "BACKGROUND")
        swingTex[i] = swingFrame:CreateTexture(nil, "BACKGROUND")
    end

    aspectF    = MakeReadout("aspect",    260, -4,  wcfg.fontWarn)
    petWarnF   = MakeReadout("petWarn",   160, -26, wcfg.fontWarn)
    petDangerF = MakeReadout("petDanger", 260, -50, wcfg.fontDanger, "THICKOUTLINE")

    ApplyConfig()

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", OnEvent)

    local driver = CreateFrame("Frame", nil, UIParent)
    driver:SetScript("OnUpdate", OnUpdate)
    C_Timer.NewTicker(0.1, Poll)

    TS.modules[#TS.modules + 1] = {
        ApplyConfig = ApplyConfig,
        SetPreview  = SetPreview,
        Test        = function() end,
    }
end
