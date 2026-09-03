-- ThreatPulse UI.lua
-- Main window. Family style shared with PulseMeter: dark drawn primitives
-- (WHITE8x8 rects, no font-glyph icons), centered mode title with dimmed
-- subtitle, hamburger on the left, drawn chevrons on the right, and menus that
-- grow upward near the bottom of the screen.

local ADDON, TP = ...
local UI = {}
TP.UI = UI

local WHITE = "Interface\\Buttons\\WHITE8X8"
local TITLE_H  = 24
local FOOTER_H = 16

local CLASS_COLORS = {
    WARRIOR = {0.78,0.61,0.43}, PALADIN = {0.96,0.55,0.73},
    HUNTER  = {0.67,0.83,0.45}, ROGUE   = {1.00,0.96,0.41},
    PRIEST  = {1.00,1.00,1.00}, SHAMAN  = {0.00,0.44,0.87},
    MAGE    = {0.41,0.80,0.94}, WARLOCK = {0.58,0.51,0.79},
    DRUID   = {1.00,0.49,0.04},
}

local function P(key) return TP.db.palette[key] end
local function SetTex(t, c) t:SetTexture(WHITE); t:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
local function Lerp(a, b, f) return a + (b - a) * f end

--------------------------------------------------------------------------------
-- Window scaffold
--------------------------------------------------------------------------------

function UI:Build()
    if self.frame then return end
    local db = TP.db

    local f = CreateFrame("Frame", "ThreatPulseFrame", UIParent)
    f:SetSize(db.width, TITLE_H + FOOTER_H + db.maxBars * (db.barHeight + db.barSpacing))
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    self.frame = f

    if db.pos then
        f:SetPoint(db.pos[1], UIParent, db.pos[1], db.pos[2], db.pos[3])
    else
        f:SetPoint("RIGHT", UIParent, "RIGHT", -160, 0)
    end

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.border = {}
    for i = 1, 4 do
        f.border[i] = f:CreateTexture(nil, "BORDER")
    end
    f.border[1]:SetPoint("TOPLEFT"); f.border[1]:SetPoint("TOPRIGHT"); f.border[1]:SetHeight(1)
    f.border[2]:SetPoint("BOTTOMLEFT"); f.border[2]:SetPoint("BOTTOMRIGHT"); f.border[2]:SetHeight(1)
    f.border[3]:SetPoint("TOPLEFT"); f.border[3]:SetPoint("BOTTOMLEFT"); f.border[3]:SetWidth(1)
    f.border[4]:SetPoint("TOPRIGHT"); f.border[4]:SetPoint("BOTTOMRIGHT"); f.border[4]:SetWidth(1)

    self:BuildTitle(f)
    self:BuildFooter(f)
    self.bars = {}
    self:ApplyPalette()

    -- drag
    f:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" and not TP.db.locked and not f.docked then
            f:StartMoving()
        end
    end)
    f:SetScript("OnMouseUp", function(_, btn)
        f:StopMovingOrSizing()
        local point, _, _, x, y = f:GetPoint()
        TP.db.pos = { point, x, y }
        if btn == "RightButton" then
            UI:ShowMenu(f)
        end
    end)
end

--------------------------------------------------------------------------------
-- Title bar: [≡]      Mode name / dimmed subtitle      [‹][›]
--------------------------------------------------------------------------------

local function DrawHamburger(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(16, 14)
    b.lines = {}
    for i = 1, 3 do
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetTexture(WHITE)
        t:SetSize(12, 2)
        t:SetPoint("TOP", 0, -(i - 1) * 4 - 1)
        b.lines[i] = t
    end
    b:SetScript("OnEnter", function()
        for _, t in ipairs(b.lines) do t:SetVertexColor(1, 1, 1, 1) end
    end)
    b:SetScript("OnLeave", function() UI:TintChrome() end)
    return b
end

-- Drawn chevron out of two angled-ish rectangle stubs (2.5.x-safe, no glyphs)
local function DrawChevron(parent, dir)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(14, 14)
    b.parts = {}
    local x = (dir == "left") and 1 or -1
    local t1 = b:CreateTexture(nil, "ARTWORK")
    t1:SetTexture(WHITE); t1:SetSize(7, 2)
    t1:SetPoint("CENTER", x * 1, 2)
    t1:SetRotation(x * 0.6)
    local t2 = b:CreateTexture(nil, "ARTWORK")
    t2:SetTexture(WHITE); t2:SetSize(7, 2)
    t2:SetPoint("CENTER", x * 1, -2)
    t2:SetRotation(-x * 0.6)
    b.parts[1], b.parts[2] = t1, t2
    b:SetScript("OnEnter", function()
        for _, t in ipairs(b.parts) do t:SetVertexColor(1, 1, 1, 1) end
    end)
    b:SetScript("OnLeave", function() UI:TintChrome() end)
    return b
end

function UI:BuildTitle(f)
    local title = CreateFrame("Frame", nil, f)
    title:SetPoint("TOPLEFT"); title:SetPoint("TOPRIGHT")
    title:SetHeight(TITLE_H)
    f.title = title

    title.mode = title:CreateFontString(nil, "OVERLAY")
    title.mode:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    title.mode:SetPoint("CENTER", 0, 4)

    title.sub = title:CreateFontString(nil, "OVERLAY")
    title.sub:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    title.sub:SetPoint("CENTER", 0, -7)

    title.rule = title:CreateTexture(nil, "ARTWORK")
    title.rule:SetPoint("BOTTOMLEFT", 6, 0)
    title.rule:SetPoint("BOTTOMRIGHT", -6, 0)
    title.rule:SetHeight(1)

    title.menu = DrawHamburger(title)
    title.menu:SetPoint("LEFT", 6, 0)
    title.menu:SetScript("OnClick", function() TP.Fire("TOGGLE_OPTIONS") end)

    title.next = DrawChevron(title, "right")
    title.next:SetPoint("RIGHT", -4, 0)
    title.prev = DrawChevron(title, "left")
    title.prev:SetPoint("RIGHT", title.next, "LEFT", -2, 0)
    local cycle = function()
        TP.Fire("SET_VIEW", TP.db.view == "threat" and "tank" or "threat")
    end
    title.next:SetScript("OnClick", cycle)
    title.prev:SetScript("OnClick", cycle)
end

function UI:BuildFooter(f)
    local footer = CreateFrame("Frame", nil, f)
    footer:SetPoint("BOTTOMLEFT"); footer:SetPoint("BOTTOMRIGHT")
    footer:SetHeight(FOOTER_H)
    f.footer = footer
    footer.text = footer:CreateFontString(nil, "OVERLAY")
    footer.text:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
    footer.text:SetPoint("CENTER")
end

--------------------------------------------------------------------------------
-- Bars
--------------------------------------------------------------------------------

local function CreateBar(f, i)
    local db = TP.db
    local bar = CreateFrame("Frame", nil, f)
    bar:SetHeight(db.barHeight)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -(TITLE_H + 2) - (i - 1) * (db.barHeight + db.barSpacing))
    bar:SetPoint("RIGHT", f, "RIGHT", -4, 0)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()

    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT"); bar.fill:SetPoint("BOTTOMLEFT")
    bar.fill:SetWidth(1)

    bar.name = bar:CreateFontString(nil, "OVERLAY")
    bar.name:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    bar.name:SetPoint("LEFT", 4, 0)
    bar.name:SetJustifyH("LEFT")

    bar.pct = bar:CreateFontString(nil, "OVERLAY")
    bar.pct:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    bar.pct:SetPoint("RIGHT", -4, 0)

    return bar
end

function UI:Bar(i)
    local bar = self.bars[i]
    if not bar then
        bar = CreateBar(self.frame, i)
        self.bars[i] = bar
    end
    return bar
end

local function BarColor(row, aggro)
    local db = TP.db
    if row.isPlayer then
        local mode = db.selfBarMode or "custom"
        if mode == "gradient" then
            local f = math.min(row.rawPct / aggro, 1)
            local cool, hot = P("cool"), P("accent")
            return Lerp(cool[1], hot[1], f), Lerp(cool[2], hot[2], f), Lerp(cool[3], hot[3], f)
        elseif mode == "class" and row.class and CLASS_COLORS[row.class] then
            local c = CLASS_COLORS[row.class]
            return c[1], c[2], c[3]
        end
        local c = P("selfBar")
        return c[1], c[2], c[3]
    end
    if db.useClassColors and row.class and CLASS_COLORS[row.class] then
        local c = CLASS_COLORS[row.class]
        if row.isPet then
            -- pet: owner's class color, dimmed, so it reads as "belongs to them"
            return c[1] * 0.65, c[2] * 0.65, c[3] * 0.65
        end
        return c[1], c[2], c[3]
    end
    local c = P(row.isTanking and "tankBar" or "otherBar")
    if row.isPet then return c[1] * 0.65, c[2] * 0.65, c[3] * 0.65 end
    return c[1], c[2], c[3]
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

function UI:Refresh(engine)
    local f = self.frame
    if not f or not f:IsShown() then return end
    local db = TP.db

    -- auto tank view
    local view = db.view
    if db.autoTankView then
        view = engine.playerIsTanking and "tank" or "threat"
    end

    local title = f.title
    title.mode:SetText(view == "tank" and "Tanking" or "Threat")
    title.sub:SetText(engine.mobName or "No target")

    local aggro = (view == "tank") and 110 or TP.AggroThreshold()
    local width = f:GetWidth() - 8
    local shown = 0
    local tank = engine:TankRow()
    local tankThreat = tank and tank.threat or 0

    for i = 1, engine.rowCount do
        local row = engine.rows[i]
        local include = (view ~= "tank") or (not row.isPlayer)
        if include and shown < db.maxBars then
            shown = shown + 1
            local bar = self:Bar(shown)
            bar:Show()
            SetTex(bar.bg, P("barBg"))

            bar.fill:SetTexture(WHITE)
            bar.fill:SetWidth(math.max(1, math.min(row.rawPct / 100, 1) * width))
            local r, g, b = BarColor(row, aggro)
            bar.fill:SetVertexColor(r, g, b, 0.9)

            local tc = P("text")
            local ac = P("accent")
            if row.isPet and row.owner then
                bar.name:SetText(row.name .. " |cff888888(" .. row.owner .. ")|r")
            else
                bar.name:SetText(row.name)
            end
            bar.name:SetTextColor(tc[1], tc[2], tc[3], 1)
            bar.pct:SetText(string.format("%d%%", row.rawPct))
            -- red = genuinely past the pull threshold vs the tank's real threat
            local overPull = (not row.isTanking) and tankThreat > 0
                and row.threat >= tankThreat * aggro / 100
            if overPull then
                bar.pct:SetTextColor(ac[1], ac[2], ac[3], 1)
            else
                bar.pct:SetTextColor(tc[1], tc[2], tc[3], 1)
            end
        end
    end
    for i = shown + 1, #self.bars do
        self.bars[i]:Hide()
    end

    -- footer: TTP in threat view, closest chaser in tank view
    local footer = f.footer.text
    if view == "tank" then
        local top
        for i = 1, engine.rowCount do
            local row = engine.rows[i]
            if not row.isPlayer then top = row; break end
        end
        footer:SetText(top and string.format("Next: %s (%d%%)", top.name, top.rawPct) or "Holding")
        local sc = P("subText"); footer:SetTextColor(sc[1], sc[2], sc[3], 1)
    elseif db.showTTP then
        footer:SetText(TP.TTP:Text())
        if TP.TTP:IsUrgent() then
            local ac = P("accent"); footer:SetTextColor(ac[1], ac[2], ac[3], 1)
        else
            local sc = P("subText"); footer:SetTextColor(sc[1], sc[2], sc[3], 1)
        end
    else
        footer:SetText("")
    end
end

--------------------------------------------------------------------------------
-- Palette application (also called live from Options)
--------------------------------------------------------------------------------

function UI:TintChrome()
    local f = self.frame
    if not f then return end
    local sc = P("subText")
    for _, t in ipairs(f.title.menu.lines) do t:SetVertexColor(sc[1], sc[2], sc[3], 1) end
    for _, t in ipairs(f.title.next.parts) do t:SetVertexColor(sc[1], sc[2], sc[3], 1) end
    for _, t in ipairs(f.title.prev.parts) do t:SetVertexColor(sc[1], sc[2], sc[3], 1) end
end

function UI:ApplyPalette()
    local f = self.frame
    if not f then return end
    SetTex(f.bg, P("windowBg"))
    for i = 1, 4 do SetTex(f.border[i], P("border")) end
    SetTex(f.title.rule, P("border"))
    local tc, sc = P("text"), P("subText")
    f.title.mode:SetTextColor(tc[1], tc[2], tc[3], 1)
    f.title.sub:SetTextColor(sc[1], sc[2], sc[3], 1)
    self:TintChrome()
    if TP.Engine then self:Refresh(TP.Engine) end
end

--------------------------------------------------------------------------------
-- Right-click menu (grows upward near the bottom of the screen; no cascades)
--------------------------------------------------------------------------------

function UI:ShowMenu(anchor)
    if self.menu and self.menu:IsShown() then self.menu:Hide() return end
    local items = {
        { text = TP.db.locked and "Unlock window" or "Lock window",
          fn = function() TP.db.locked = not TP.db.locked end },
        { text = (TP.db.view == "tank") and "Threat view" or "Tank view",
          fn = function() TP.Fire("SET_VIEW", TP.db.view == "tank" and "threat" or "tank") end },
        { text = TP.db.autoTankView and "Auto tank view: on" or "Auto tank view: off",
          fn = function() TP.db.autoTankView = not TP.db.autoTankView end },
        { text = "Options", fn = function() TP.Fire("TOGGLE_OPTIONS") end },
        { text = "Close window", fn = function() UI.frame:Hide() end },
    }

    local m = self.menu
    if not m then
        m = CreateFrame("Frame", "ThreatPulseMenu", UIParent)
        m:SetFrameStrata("DIALOG")
        m:SetWidth(150)
        m.bg = m:CreateTexture(nil, "BACKGROUND"); m.bg:SetAllPoints()
        m.border = {}
        for i = 1, 4 do m.border[i] = m:CreateTexture(nil, "BORDER") end
        m.border[1]:SetPoint("TOPLEFT"); m.border[1]:SetPoint("TOPRIGHT"); m.border[1]:SetHeight(1)
        m.border[2]:SetPoint("BOTTOMLEFT"); m.border[2]:SetPoint("BOTTOMRIGHT"); m.border[2]:SetHeight(1)
        m.border[3]:SetPoint("TOPLEFT"); m.border[3]:SetPoint("BOTTOMLEFT"); m.border[3]:SetWidth(1)
        m.border[4]:SetPoint("TOPRIGHT"); m.border[4]:SetPoint("BOTTOMRIGHT"); m.border[4]:SetWidth(1)
        m.buttons = {}
        self.menu = m
    end

    SetTex(m.bg, P("windowBg"))
    for i = 1, 4 do SetTex(m.border[i], P("border")) end

    local H = 20
    m:SetHeight(#items * H + 8)
    for i, item in ipairs(items) do
        local b = m.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, m)
            b:SetHeight(H)
            b:SetPoint("LEFT", 4, 0); b:SetPoint("RIGHT", -4, 0)
            b.hl = b:CreateTexture(nil, "HIGHLIGHT")
            b.hl:SetAllPoints(); b.hl:SetTexture(WHITE)
            b.text = b:CreateFontString(nil, "OVERLAY")
            b.text:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
            b.text:SetPoint("LEFT", 6, 0)
            m.buttons[i] = b
        end
        b:SetPoint("TOP", m, "TOP", 0, -4 - (i - 1) * H)
        b.hl:SetVertexColor(1, 1, 1, 0.06)
        local tc = P("text")
        b.text:SetText(item.text); b.text:SetTextColor(tc[1], tc[2], tc[3], 1)
        b:SetScript("OnClick", function() item.fn(); m:Hide() end)
        b:Show()
    end
    for i = #items + 1, #m.buttons do m.buttons[i]:Hide() end

    -- grow upward when the anchor sits in the lower third of the screen
    m:ClearAllPoints()
    local _, cy = anchor:GetCenter()
    if cy and cy < (UIParent:GetHeight() / 3) then
        m:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4)
    else
        m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    end
    m:Show()
end

--------------------------------------------------------------------------------
-- Wiring
--------------------------------------------------------------------------------

TP.On("LOGIN", function()
    UI:Build()
end)

TP.On("THREAT_UPDATE", function(engine) UI:Refresh(engine) end)

function UI:Relayout()
    local f = self.frame
    if not f then return end
    local db = TP.db
    f:SetHeight(TITLE_H + FOOTER_H + db.maxBars * (db.barHeight + db.barSpacing) + 4)
    for i, bar in ipairs(self.bars) do
        bar:SetHeight(db.barHeight)
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", f, "TOPLEFT", 4,
            -(TITLE_H + 2) - (i - 1) * (db.barHeight + db.barSpacing))
        bar:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    end
    if TP.Engine then self:Refresh(TP.Engine) end
end

TP.On("LAYOUT_CHANGED", function() UI:Relayout() end)

-- Following your tab-target is only useful if you can SEE it happened:
-- the mob name under the title flashes accent for a beat on each switch.
TP.On("MOB_CHANGED", function()
    local f = UI.frame
    if not f then return end
    local ac = TP.db.palette.accent
    f.title.sub:SetTextColor(ac[1], ac[2], ac[3], 1)
    UI.subFlashAt = GetTime()
    C_Timer.After(1.2, function()
        if GetTime() - (UI.subFlashAt or 0) >= 1.1 then
            local sc = TP.db.palette.subText
            f.title.sub:SetTextColor(sc[1], sc[2], sc[3], 1)
        end
    end)
end)

TP.On("SET_VIEW", function(view)
    TP.db.view = view
    TP.db.autoTankView = false          -- explicit choice overrides auto
    UI:Refresh(TP.Engine)
end)

TP.On("TOGGLE_WINDOW", function()
    if not UI.frame then UI:Build() end
    if UI.frame:IsShown() then UI.frame:Hide() else UI.frame:Show() end
end)

TP.On("PALETTE_CHANGED", function() UI:ApplyPalette() end)
