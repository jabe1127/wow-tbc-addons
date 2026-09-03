-- =========================================================================
-- Quiver - Alerts.lua
-- A running history of what you pressed. Each cast pops as an icon,
-- settles into place and fades. The icon carries a cooldown sweep so the
-- feed doubles as a "when is that back" readout.
-- =========================================================================

local ADDON, TS = ...

local POOL_SIZE = 5
local POP_SCALE = 1.45
local POP_TIME  = 0.14
local FADE_FRAC = 0.40

local anchor, acfg
local pool    = {}
local active  = {}      -- newest first
local preview = false

-- ------------------------------------------------------------------ pool
local function CreateAlertFrame()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("HIGH")
    f:Hide()

    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetPoint("TOPLEFT", -1, 1)
    f.border:SetPoint("BOTTOMRIGHT", 1, -1)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- radial cooldown sweep, so the alert also answers "when is it back?"
    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints()
    f.cd:SetDrawEdge(false)
    if f.cd.SetHideCountdownNumbers then
        f.cd:SetHideCountdownNumbers(false)
    end

    f.glow = f:CreateTexture(nil, "OVERLAY")
    f.glow:SetAllPoints()
    f.glow:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    f.glow:SetBlendMode("ADD")

    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetJustifyH("LEFT")
    return f
end

local function GetFrame()
    for _, f in ipairs(pool) do
        if not f.inUse then return f end
    end
    local oldest = active[#active]
    if oldest then
        tremove(active, #active)
        return oldest
    end
end

-- --------------------------------------------------------------- layout
local function Layout()
    local size, gap = acfg.size, acfg.spacing
    local growth = acfg.growth
    for i, f in ipairs(active) do
        local off = (i - 1) * (size + gap)
        f:ClearAllPoints()
        if growth == "DOWN" then
            f:SetPoint("TOP", anchor, "TOP", 0, -off)
        elseif growth == "LEFT" then
            f:SetPoint("RIGHT", anchor, "RIGHT", -off, 0)
        elseif growth == "RIGHT" then
            f:SetPoint("LEFT", anchor, "LEFT", off, 0)
        else -- UP
            f:SetPoint("BOTTOM", anchor, "BOTTOM", 0, off)
        end
        f.slotAlpha = 1 - (i - 1) * 0.13
    end
end

-- ------------------------------------------------------------ public API
-- opts: { icon, label, color, cooldownSpell }
function TS.Alert(opts)
    if not acfg or not acfg.enabled or not opts then return end
    local f = GetFrame()
    if not f then return end

    local size = acfg.size
    f.inUse   = true
    f.started = GetTime()
    f.dur     = acfg.duration
    f.size    = size
    f.slotAlpha = 1

    f.icon:SetTexture(opts.icon or "Interface\\Icons\\INV_Misc_QuestionMark")

    local c = opts.color or { 1, 1, 1 }
    f.border:SetColorTexture(c[1] * 0.7, c[2] * 0.7, c[3] * 0.7, 1)
    f.glow:SetVertexColor(c[1], c[2], c[3])
    f.glow:SetAlpha(0.85)

    f.text:SetFont(TS.FONT, math.max(11, math.floor(acfg.size * 0.36)), "OUTLINE")
    f.text:ClearAllPoints()
    if acfg.growth == "LEFT" then
        f.text:SetPoint("RIGHT", f, "LEFT", -8, 0)
        f.text:SetJustifyH("RIGHT")
    else
        f.text:SetPoint("LEFT", f, "RIGHT", 8, 0)
        f.text:SetJustifyH("LEFT")
    end
    f.text:SetTextColor(c[1], c[2], c[3])
    f.text:SetText(acfg.showName and (opts.label or "") or "")

    -- cooldown sweep, when the alert is for something with a real cooldown
    f.cd:Clear()
    if acfg.readySweep and opts.cooldownSpell then
        local left = TS.SpellCooldown(opts.cooldownSpell)
        if left > 0 then
            f.cd:SetCooldown(GetTime(), left)
        end
    end

    f:SetSize(size, size)
    f:SetAlpha(1)
    f:Show()

    tinsert(active, 1, f)
    while #active > POOL_SIZE do
        local drop = tremove(active, #active)
        drop.inUse = false
        drop.cd:Clear()
        drop:Hide()
    end
    Layout()

    if acfg.sound then
        pcall(PlaySound, 1115)
    end
end

-- --------------------------------------------------------------- OnUpdate
local function OnUpdate()
    if preview then return end
    local now = GetTime()
    local changed = false

    for i = #active, 1, -1 do
        local f = active[i]
        local el = now - f.started
        if el >= f.dur then
            f.inUse = false
            f.cd:Clear()
            f:Hide()
            tremove(active, i)
            changed = true
        else
            local size = f.size
            if el < POP_TIME then
                local k = 1 - (el / POP_TIME)
                local s = size * (1 + (POP_SCALE - 1) * k)
                f:SetSize(s, s)
                f.glow:SetAlpha(0.85 * k)
            else
                f:SetSize(size, size)
                f.glow:SetAlpha(0)
            end
            local fadeStart = f.dur * (1 - FADE_FRAC)
            local base = f.slotAlpha or 1
            if el > fadeStart then
                f:SetAlpha(base * (1 - (el - fadeStart) / (f.dur - fadeStart)))
            else
                f:SetAlpha(base)
            end
        end
    end
    if changed then Layout() end
end

-- ------------------------------------------------------------ preview
local function ClearAll()
    for _, f in ipairs(pool) do
        f.inUse = false
        f.cd:Clear()
        f:Hide()
    end
    wipe(active)
end

local function SetPreview(on)
    preview = on
    if not anchor then return end
    anchor.overlay:SetShown(on)
    if on then
        acfg = TS.db.alerts
        ClearAll()
        anchor:SetSize(acfg.size, acfg.size)
        anchor:Show()
        local f = pool[1]
        f.inUse = true
        f.size = acfg.size
        f:SetSize(acfg.size, acfg.size)
        f:ClearAllPoints()
        f:SetPoint("CENTER", anchor, "CENTER", 0, 0)
        f.icon:SetTexture(TS.SpellTexture(75) or "Interface\\Icons\\INV_Weapon_Bow_07")
        f.icon:SetVertexColor(1, 1, 1)
        f.icon:SetDesaturated(false)
        f.border:SetColorTexture(0.7, 0.57, 0.17, 1)
        f.glow:SetAlpha(0)
        f.cd:Clear()
        f.text:SetFont(TS.FONT, math.max(11, math.floor(acfg.size * 0.36)), "OUTLINE")
        f.text:ClearAllPoints()
        f.text:SetPoint("LEFT", f, "RIGHT", 8, 0)
        f.text:SetTextColor(1, 0.82, 0.25)
        f.text:SetText(acfg.showName and "Shot alerts" or "")
        f:SetAlpha(1)
        f:Show()
    else
        ClearAll()
        anchor:Hide()
    end
end

local function ApplyConfig()
    acfg = TS.db.alerts
    anchor:SetSize(acfg.size, acfg.size)
    anchor:ClearAllPoints()
    anchor:SetPoint(acfg.point, UIParent, acfg.relPoint or acfg.point, acfg.x, acfg.y)
    anchor.cfg = acfg
    if preview then SetPreview(true) end
end

-- ------------------------------------------------------------------ test
local testTimers = {}
local function T(d, fn) testTimers[#testTimers + 1] = C_Timer.NewTimer(d, fn) end

local function StopTest()
    for _, t in ipairs(testTimers) do t:Cancel() end
    wipe(testTimers)
    ClearAll()
end

local function StartTest()
    local col = TS.db.colors
    local function fire(id, kind)
        return function()
            if not TS.testing then return end
            TS.Alert({ icon = TS.SpellTexture(id), label = TS.SpellName(id),
                       color = col[kind] })
        end
    end
    local function loop()
        if not TS.testing then return end
        fire(75, "auto")()                                  -- Auto Shot
        T(0.6, fire(34120, "cast"))                          -- Steady Shot
        T(1.2, fire(3044, "cast"))                           -- Arcane Shot
        T(1.8, function()
            if not TS.testing then return end
            TS.Alert({ icon = GetInventoryItemTexture("player", 16)
                              or "Interface\\Icons\\Ability_MeleeDamage",
                       label = MELEE or "Melee", color = col.melee })
        end)
        T(2.4, fire(1499, "cast"))                           -- Freezing Trap
        T(3.6, loop)
    end
    loop()
end

-- ------------------------------------------------------------------ init
TS.inits[#TS.inits + 1] = function(db)
    acfg = db.alerts

    anchor = CreateFrame("Frame", "QuiverAlertAnchor", UIParent)
    anchor:SetSize(acfg.size, acfg.size)
    anchor:SetPoint(acfg.point, UIParent, acfg.relPoint or acfg.point, acfg.x, acfg.y)
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    anchor:Hide()
    anchor.cfg = acfg

    anchor.overlay = CreateFrame("Frame", nil, anchor)
    anchor.overlay:SetAllPoints()
    anchor.overlay:SetFrameStrata("DIALOG")
    anchor.overlay:EnableMouse(true)
    anchor.overlay:RegisterForDrag("LeftButton")
    anchor.overlay:SetScript("OnDragStart", function() anchor:StartMoving() end)
    anchor.overlay:SetScript("OnDragStop", function()
        anchor:StopMovingOrSizing()
        local c = anchor.cfg
        local p, _, rp, x, y = anchor:GetPoint(1)
        c.point, c.relPoint = p, rp
        c.x, c.y = math.floor(x + 0.5), math.floor(y + 0.5)
    end)
    local ol = anchor.overlay:CreateTexture(nil, "OVERLAY")
    ol:SetAllPoints()
    ol:SetColorTexture(0.2, 0.6, 1.0, 0.3)
    local lbl = anchor.overlay:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(TS.FONT, 10, "OUTLINE")
    lbl:SetPoint("TOP", anchor.overlay, "BOTTOM", 0, -3)
    lbl:SetText("Alert anchor |cffaad4ff(drag)|r")
    anchor.overlay:Hide()

    for i = 1, POOL_SIZE do
        pool[i] = CreateAlertFrame()
    end

    local driver = CreateFrame("Frame", nil, UIParent)
    driver:SetScript("OnUpdate", OnUpdate)

    TS.modules[#TS.modules + 1] = {
        ApplyConfig = ApplyConfig,
        SetPreview  = SetPreview,
        Test        = function(on) if on then StartTest() else StopTest() end end,
    }
end
