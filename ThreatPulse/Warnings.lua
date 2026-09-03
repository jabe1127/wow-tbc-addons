-- ThreatPulse Warnings.lua
-- Threshold warnings. Role presets (110 melee / 130 ranged) with a warn line at
-- a configurable % of that threshold, plus fully custom raw% thresholds.
-- Each channel (sound / flash / splash) toggles independently. Edge-triggered
-- with hysteresis so a bar hovering on a line doesn't machine-gun alerts.

local ADDON, TP = ...
local W = {}
TP.Warnings = W

local HYSTERESIS = 5       -- must drop this many raw% below a line to re-arm

-- Alerts play on the Dialog channel: unused during combat, and its volume can
-- be driven directly — that's what the alert volume slider controls. Quest/NPC
-- voiceover shares the channel; that's the tradeoff.
local CHANNEL = "Dialog"

function W.ApplyVolume()
    if SetCVar then
        SetCVar("Sound_DialogVolume", (TP.db.warnings.volume or 60) / 100)
        SetCVar("Sound_EnableDialog", 1)
    end
end
TP.On("LOGIN", function() W.ApplyVolume() end)

-- A cue is either a built-in sound kit ID (number) or a file path registered
-- through LibSharedMedia (string) — DBM/BigWigs/Fojji packs arrive as paths.
function W.PlayCue(v)
    if type(v) == "number" then
        PlaySound(v, CHANNEL)
    elseif type(v) == "string" then
        PlaySoundFile(v, CHANNEL)
    end
end

W.fired = {}               -- [key] = true while armed-off

--------------------------------------------------------------------------------
-- Output channels
--------------------------------------------------------------------------------

local flashFrame, splashFrame

-- Soft vignette color and shape
local FLASH_R, FLASH_G, FLASH_B = 0.88, 0.14, 0.07
local FLASH_ALPHA = 0.32
local FLASH_DEPTH = 110

-- Gradient API differs by client build: modern uses SetGradient(orient, colorMin,
-- colorMax) with CreateColor; older uses SetGradientAlpha; if neither works we
-- layer thin strips with stepped alpha for a smooth fade.
local function PaintEdge(f, point)
    local vertical = (point == "TOP" or point == "BOTTOM")
    local function anchorStrip(t, inset, depth)
        t:ClearAllPoints()
        if point == "TOP" then
            t:SetPoint("TOPLEFT", 0, -inset); t:SetPoint("TOPRIGHT", 0, -inset); t:SetHeight(depth)
        elseif point == "BOTTOM" then
            t:SetPoint("BOTTOMLEFT", 0, inset); t:SetPoint("BOTTOMRIGHT", 0, inset); t:SetHeight(depth)
        elseif point == "LEFT" then
            t:SetPoint("TOPLEFT", inset, 0); t:SetPoint("BOTTOMLEFT", inset, 0); t:SetWidth(depth)
        else
            t:SetPoint("TOPRIGHT", -inset, 0); t:SetPoint("BOTTOMRIGHT", -inset, 0); t:SetWidth(depth)
        end
    end

    local t = f:CreateTexture(nil, "ARTWORK")
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    anchorStrip(t, 0, FLASH_DEPTH)

    local orient = vertical and "VERTICAL" or "HORIZONTAL"
    -- gradient runs start→end as bottom→top (VERTICAL) or left→right (HORIZONTAL)
    local edgeAtStart = (point == "BOTTOM" or point == "LEFT")

    if t.SetGradient and CreateColor then
        t:SetVertexColor(1, 1, 1, 1)
        local solid = CreateColor(FLASH_R, FLASH_G, FLASH_B, FLASH_ALPHA)
        local clear = CreateColor(FLASH_R, FLASH_G, FLASH_B, 0)
        if edgeAtStart then t:SetGradient(orient, solid, clear)
        else t:SetGradient(orient, clear, solid) end
        return
    end
    if t.SetGradientAlpha then
        if edgeAtStart then
            t:SetGradientAlpha(orient, FLASH_R, FLASH_G, FLASH_B, FLASH_ALPHA,
                                       FLASH_R, FLASH_G, FLASH_B, 0)
        else
            t:SetGradientAlpha(orient, FLASH_R, FLASH_G, FLASH_B, 0,
                                       FLASH_R, FLASH_G, FLASH_B, FLASH_ALPHA)
        end
        return
    end
    -- no gradient support: stack thin strips with stepped alpha
    t:Hide()
    local steps = 6
    local stripDepth = FLASH_DEPTH / steps
    for i = 1, steps do
        local s = f:CreateTexture(nil, "ARTWORK")
        s:SetTexture("Interface\\Buttons\\WHITE8X8")
        anchorStrip(s, (i - 1) * stripDepth, stripDepth)
        s:SetVertexColor(FLASH_R, FLASH_G, FLASH_B,
            FLASH_ALPHA * (1 - (i - 1) / steps) ^ 1.6)
    end
end

local function EnsureFlash()
    if flashFrame then return flashFrame end
    local f = CreateFrame("Frame", "ThreatPulseFlash", UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(false)
    f:Hide()

    PaintEdge(f, "TOP")
    PaintEdge(f, "BOTTOM")
    PaintEdge(f, "LEFT")
    PaintEdge(f, "RIGHT")

    local ag = f:CreateAnimationGroup()
    local a1 = ag:CreateAnimation("Alpha")
    a1:SetFromAlpha(0); a1:SetToAlpha(1); a1:SetDuration(0.10); a1:SetOrder(1)
    local hold = ag:CreateAnimation("Alpha")
    hold:SetFromAlpha(1); hold:SetToAlpha(1); hold:SetDuration(0.15); hold:SetOrder(2)
    local a2 = ag:CreateAnimation("Alpha")
    a2:SetFromAlpha(1); a2:SetToAlpha(0); a2:SetDuration(0.9); a2:SetOrder(3)
    ag:SetScript("OnFinished", function() f:Hide() end)
    f.anim = ag
    flashFrame = f
    return f
end

local function EnsureSplash()
    if splashFrame then return splashFrame end
    local f = CreateFrame("Frame", "ThreatPulseSplash", UIParent)
    f:SetSize(600, 60)
    f:SetPoint("CENTER", 0, 180)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:Hide()
    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 30, "THICKOUTLINE")
    fs:SetPoint("CENTER")
    f.text = fs

    local ag = f:CreateAnimationGroup()
    local s = ag:CreateAnimation("Scale")
    s:SetScale(1.15, 1.15); s:SetDuration(0.15); s:SetOrder(1)
    local hold = ag:CreateAnimation("Alpha")
    hold:SetFromAlpha(1); hold:SetToAlpha(1); hold:SetDuration(1.2); hold:SetOrder(2)
    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(1); fade:SetToAlpha(0); fade:SetDuration(0.5); fade:SetOrder(3)
    ag:SetScript("OnFinished", function() f:Hide() end)
    f.anim = ag
    splashFrame = f
    return f
end

function W:Emit(text, cfg)
    local base = TP.db.warnings
    cfg = cfg or base
    if cfg.sound then
        W.PlayCue(cfg.soundKit or base.soundKit or 8959)
    end
    if cfg.flash then
        local f = EnsureFlash()
        f:Show(); f.anim:Stop(); f.anim:Play()
    end
    if cfg.splash then
        local f = EnsureSplash()
        local c = TP.db.palette.accent
        f.text:SetText(text)
        f.text:SetTextColor(c[1], c[2], c[3], 1)
        f:Show(); f.anim:Stop(); f.anim:Play()
    end
end

--------------------------------------------------------------------------------
-- Evaluation
--------------------------------------------------------------------------------

local function Check(self, key, pct, line, text, cfg)
    if pct >= line then
        if not self.fired[key] then
            self.fired[key] = true
            self:Emit(text, cfg)
        end
    elseif pct < line - HYSTERESIS then
        self.fired[key] = nil
    end
end

function W:Evaluate(engine)
    local wcfg = TP.db.warnings
    local me = engine:PlayerRow()

    if engine.playerIsTanking then
        -- Tank side: others' threat as a % of YOURS (raw values, not display %).
        if not me or me.threat <= 0 then return end
        for i = 1, engine.rowCount do
            local row = engine.rows[i]
            if not row.isPlayer then
                local pct = row.threat / me.threat * 100
                Check(self, "tank:" .. row.guid, pct, wcfg.tankWarnPct,
                    row.name .. " is at " .. math.floor(pct) .. "%!")
            end
        end
        return
    end

    if not me then return end
    local tank = engine:TankRow()
    if not tank or tank.threat <= 0 then return end

    -- True pull rule: your threat vs the tanking unit's threat. This stays
    -- correct even when the display is normalized or the mob is fixating.
    local vsTank = me.threat / tank.threat * 100
    local aggro = TP.AggroThreshold()

    -- role-preset line: warnPct% of your aggro threshold
    local line = aggro * wcfg.warnPct / 100
    Check(self, "self:preset", vsTank, line,
        "HIGH THREAT — " .. math.floor(vsTank) .. "%")

    -- aggro crossing: distinct cue when you actually pass the threshold
    if wcfg.aggroAlert then
        Check(self, "self:aggro", vsTank, aggro, "AGGRO — YOU PULLED", {
            sound = wcfg.sound, flash = wcfg.flash, splash = wcfg.splash,
            soundKit = wcfg.aggroSoundKit,
        })
    end

    -- custom raw% lines
    for i, c in ipairs(wcfg.custom) do
        Check(self, "self:custom" .. i, vsTank, c.pct,
            "THREAT " .. math.floor(vsTank) .. "%", c)
    end
end

TP.On("THREAT_UPDATE", function(engine) W:Evaluate(engine) end)

-- clear latch state out of combat and when the tracked mob changes
TP.RegisterEvent("PLAYER_REGEN_ENABLED", function() wipe(W.fired) end)
TP.On("MOB_CHANGED", function() wipe(W.fired) end)

-- /tp test
TP.On("TEST_WARNING", function()
    W:Emit("HIGH THREAT — 98%")
end)
