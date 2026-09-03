-- =========================================================================
-- Quiver - Options.lua
-- Options window in the addon's own style. Hand-built widgets, no XML
-- templates, so it behaves the same on any anniversary-era client.
-- =========================================================================

local ADDON, TS = ...

local panel
local widgets = {}

local function A() return TS.db.alerts end
local function C() return TS.db.colors end
local function W() return TS.db.warnings end

-- ------------------------------------------------------- widget builders
local function Label(parent, text, fontObject)
    local fs = parent:CreateFontString(nil, "OVERLAY", fontObject or "GameFontHighlight")
    fs:SetText(text)
    return fs
end

local function Header(parent, text, y)
    local fs = Label(parent, text, "GameFontNormal")
    fs:SetPoint("TOPLEFT", 16, y)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 16, y - 15)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -16, y - 15)
    line:SetHeight(1)
    line:SetColorTexture(0.4, 0.4, 0.4, 0.5)
    return fs
end

local function Check(parent, x, y, text, getter, setter)
    local c = CreateFrame("CheckButton", nil, parent)
    c:SetPoint("TOPLEFT", x, y)
    c:SetSize(22, 22)
    c:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    c:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    c:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    c:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    local label = Label(c, text)
    label:SetPoint("LEFT", c, "RIGHT", 3, 0)
    c:SetScript("OnClick", function(self)
        setter(self:GetChecked() and true or false)
        TS.RefreshAll()
    end)
    function c:Refresh() self:SetChecked(getter() and true or false) end
    widgets[#widgets + 1] = c
    return c
end

local function Slider(parent, x, y, width, text, minV, maxV, step, getter, setter, fmt)
    local s = CreateFrame("Slider", nil, parent)
    s:SetPoint("TOPLEFT", x, y)
    s:SetSize(width, 17)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)

    local rail = s:CreateTexture(nil, "BACKGROUND")
    rail:SetPoint("LEFT", 0, 0); rail:SetPoint("RIGHT", 0, 0)
    rail:SetHeight(6); rail:SetColorTexture(0, 0, 0, 0.9)
    local railIn = s:CreateTexture(nil, "BACKGROUND", nil, 1)
    railIn:SetPoint("LEFT", 1, 0); railIn:SetPoint("RIGHT", -1, 0)
    railIn:SetHeight(4); railIn:SetColorTexture(0.28, 0.28, 0.28, 0.9)

    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:GetThumbTexture():SetSize(26, 26)

    local name = Label(s, text)
    name:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 3)
    local value = Label(s, "", "GameFontNormal")
    value:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", 0, 3)

    local function fmtVal(v)
        if fmt == "sec" then return string.format("%.1fs", v) end
        if fmt == "pct" then return string.format("%d%%", math.floor(v * 100 + 0.5)) end
        if fmt == "raw" then return string.format("%.1f", v) end
        return tostring(math.floor(v + 0.5))
    end

    local fractional = (fmt == "sec" or fmt == "pct" or fmt == "raw")

    s:SetScript("OnValueChanged", function(self, v)
        if not fractional then v = math.floor(v + 0.5) end
        value:SetText(fmtVal(v))
        if self.loading then return end
        setter(v)
        TS.RefreshAll()
    end)
    function s:Refresh()
        self.loading = true
        self:SetValue(getter())
        value:SetText(fmtVal(getter()))
        self.loading = false
    end
    widgets[#widgets + 1] = s
    return s
end

local function Button(parent, w, h, text, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
    b:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight", "ADD")
    b:GetNormalTexture():SetTexCoord(0, 0.625, 0, 0.6875)
    b:GetPushedTexture():SetTexCoord(0, 0.625, 0, 0.6875)
    b:GetHighlightTexture():SetTexCoord(0, 0.625, 0, 0.6875)
    b.label = Label(b, text, "GameFontNormal")
    b.label:SetPoint("CENTER", 0, 0)
    b:SetScript("OnClick", function(self) onClick(self) end)
    return b
end

local function OpenColorPicker(resolver, onChange)
    local c = resolver()
    local r0, g0, b0 = c[1], c[2], c[3]
    local function apply(r, g, b)
        local cur = resolver()
        cur[1], cur[2], cur[3] = r, g, b
        onChange()
    end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r0, g = g0, b = b0, hasOpacity = false,
            swatchFunc = function() apply(ColorPickerFrame:GetColorRGB()) end,
            cancelFunc = function() apply(r0, g0, b0) end,
        })
    else
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.func = function() apply(ColorPickerFrame:GetColorRGB()) end
        ColorPickerFrame.cancelFunc = function() apply(r0, g0, b0) end
        ColorPickerFrame:SetColorRGB(r0, g0, b0)
        ColorPickerFrame:Show()
    end
end

local function Swatch(parent, x, y, text, resolver)
    local b = CreateFrame("Button", nil, parent)
    b:SetPoint("TOPLEFT", x, y)
    b:SetSize(16, 16)
    local border = b:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints(); border:SetColorTexture(0, 0, 0, 1)
    local sw = b:CreateTexture(nil, "ARTWORK")
    sw:SetPoint("TOPLEFT", 1, -1); sw:SetPoint("BOTTOMRIGHT", -1, 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.2)
    local label = Label(b, text)
    label:SetPoint("LEFT", b, "RIGHT", 5, 0)
    local function paint()
        local c = resolver()
        sw:SetColorTexture(c[1], c[2], c[3], 1)
    end
    b:SetScript("OnClick", function()
        OpenColorPicker(resolver, function() paint(); TS.RefreshAll() end)
    end)
    b.Refresh = paint
    widgets[#widgets + 1] = b
    return b
end

local function Dropdown(parent, x, y, width, text, options, getter, setter)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("TOPLEFT", x, y)
    holder:SetSize(width, 22)
    local name = Label(holder, text)
    name:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", 0, 3)

    local btn = Button(holder, width, 22, "", function(self)
        local cur = getter()
        local idx = 1
        for i, o in ipairs(options) do
            if o.value == cur then idx = i break end
        end
        local nxt = options[(idx % #options) + 1]
        setter(nxt.value)
        self.label:SetText(nxt.text)
        TS.RefreshAll()
    end)
    btn:SetPoint("TOPLEFT", 0, 0)
    function holder:Refresh()
        local cur = getter()
        for _, o in ipairs(options) do
            if o.value == cur then btn.label:SetText(o.text) return end
        end
        btn.label:SetText(options[1].text)
    end
    widgets[#widgets + 1] = holder
    return holder
end

-- --------------------------------------------------------- panel builder
local function BuildPanel()
    panel = CreateFrame("Frame", "QuiverOptions", UIParent)
    panel:SetSize(380, 100)
    panel:SetPoint("CENTER", 0, 40)
    panel:SetFrameStrata("DIALOG")
    panel:SetToplevel(true)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:Hide()
    tinsert(UISpecialFrames, "QuiverOptions")

    local border = panel:CreateTexture(nil, "BACKGROUND", nil, 0)
    border:SetPoint("TOPLEFT", -1, 1); border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0, 0, 0, 0.95)
    local bg = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetAllPoints(); bg:SetColorTexture(0.08, 0.08, 0.08, 0.96)

    local strip = panel:CreateTexture(nil, "BACKGROUND", nil, 2)
    strip:SetPoint("TOPLEFT", 0, 0); strip:SetPoint("TOPRIGHT", 0, 0)
    strip:SetHeight(30); strip:SetColorTexture(0.13, 0.13, 0.13, 1)
    local accent = panel:CreateTexture(nil, "BACKGROUND", nil, 3)
    accent:SetPoint("TOPLEFT", 0, -30); accent:SetPoint("TOPRIGHT", 0, -30)
    accent:SetHeight(1); accent:SetColorTexture(1, 0.82, 0.1, 0.55)

    local title = Label(panel, "Quiver", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -7)
    local ver = Label(panel, "v" .. TS.version, "GameFontDisableSmall")
    ver:SetPoint("LEFT", title, "RIGHT", 6, -1)

    local dragZone = CreateFrame("Frame", nil, panel)
    dragZone:SetPoint("TOPLEFT", 0, 0); dragZone:SetPoint("TOPRIGHT", -28, 0)
    dragZone:SetHeight(30)
    dragZone:EnableMouse(true)
    dragZone:RegisterForDrag("LeftButton")
    dragZone:SetScript("OnDragStart", function() panel:StartMoving() end)
    dragZone:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)

    local close = CreateFrame("Button", nil, panel)
    close:SetSize(26, 26)
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    close:SetScript("OnClick", function() panel:Hide() end)

    -- Two pages: the alert feed, and the peripheral warnings. Each page is
    -- its own frame so laying one out never disturbs the other.
    local pages, tabs = {}, {}
    local function ShowPage(which)
        for name, f in pairs(pages) do f:SetShown(name == which) end
        for name, t in pairs(tabs) do
            t.selected = (name == which)
            t.tex:SetColorTexture(t.selected and 0.22 or 0.13,
                                  t.selected and 0.20 or 0.13,
                                  t.selected and 0.10 or 0.13, 1)
            t.label:SetTextColor(t.selected and 1 or 0.65,
                                 t.selected and 0.82 or 0.65,
                                 t.selected and 0.25 or 0.65)
        end
        panel:SetHeight(pages[which].pageHeight)
        TS.db.optionsTab = which
    end

    local function MakeTab(key, text, index)
        local t = CreateFrame("Button", nil, panel)
        t:SetSize(110, 22)
        t:SetPoint("TOPLEFT", 14 + (index - 1) * 114, -34)
        t.tex = t:CreateTexture(nil, "BACKGROUND")
        t.tex:SetAllPoints()
        t.label = Label(t, text, "GameFontNormalSmall")
        t.label:SetPoint("CENTER")
        t:SetScript("OnClick", function() ShowPage(key) end)
        tabs[key] = t
        local f = CreateFrame("Frame", nil, panel)
        f:SetPoint("TOPLEFT", 0, -58)
        f:SetPoint("TOPRIGHT", 0, -58)
        f:SetHeight(10)
        pages[key] = f
        return f
    end

    local feed  = MakeTab("feed", "Cast feed", 1)
    local warns = MakeTab("warnings", "Warnings", 2)

    -- ================================================== page: cast feed
    local panelRef = panel
    panel = feed
    local y = -8

    Header(panel, "Announce", y); y = y - 26
    Check(panel, 20, y, "Auto Shot",
        function() return A().showAuto end, function(v) A().showAuto = v end)
    Check(panel, 195, y, "Melee swings",
        function() return A().showMelee end, function(v) A().showMelee = v end)
    y = y - 24
    Check(panel, 20, y, "Show spell name",
        function() return A().showName end, function(v) A().showName = v end)
    Check(panel, 195, y, "Cooldown sweep",
        function() return A().readySweep end, function(v) A().readySweep = v end)
    y = y - 24
    Check(panel, 20, y, "Play a sound",
        function() return A().sound end, function(v) A().sound = v end)
    y = y - 32

    Header(panel, "Appearance", y); y = y - 40
    Slider(panel, 20, y, 155, "Icon size", 24, 96, 2,
        function() return A().size end, function(v) A().size = v end)
    Slider(panel, 205, y, 155, "Duration", 0.5, 3.0, 0.1,
        function() return A().duration end, function(v) A().duration = v end, "sec")
    y = y - 42
    Dropdown(panel, 20, y, 155, "Grow", {
        { value = "UP",    text = "Upwards" },
        { value = "DOWN",  text = "Downwards" },
        { value = "LEFT",  text = "Leftwards" },
        { value = "RIGHT", text = "Rightwards" },
    }, function() return A().growth end, function(v) A().growth = v end)
    Slider(panel, 205, y, 155, "Spacing", 0, 24, 1,
        function() return A().spacing end, function(v) A().spacing = v end)
    y = y - 34

    Header(panel, "Colors", y); y = y - 24
    Swatch(panel, 20,  y, "Casts", function() return C().cast end)
    Swatch(panel, 195, y, "Auto Shot", function() return C().auto end)
    y = y - 24
    Swatch(panel, 20,  y, "Melee", function() return C().melee end)
    y = y - 30

    Header(panel, "Blocked spells", y); y = y - 26
    local blockedText = Label(panel, "", "GameFontHighlight")
    blockedText:SetPoint("TOPLEFT", 20, y)
    blockedText.Refresh = function(self)
        local n = TS.BlockedCount()
        self:SetText(n == 0 and "Nothing blocked."
                             or (n .. (n == 1 and " spell" or " spells") ..
                                 " won't be announced."))
    end
    widgets[#widgets + 1] = blockedText
    y = y - 24

    local blockBtn = Button(panel, 110, 22, "Block last", function()
        local id = TS.lastSpellID
        if not id then
            TS.Print("Nothing cast yet this session.")
            return
        end
        local _, name = TS.Block(id)
        TS.Print("Blocked " .. (name or ("spell " .. id)) ..
                 " |cff808080(" .. id .. ")|r.")
        blockedText:Refresh()
    end)
    blockBtn:SetPoint("TOPLEFT", 20, y)

    local clearBtn = Button(panel, 110, 22, "Clear list", function()
        wipe(TS.db.blacklist)
        blockedText:Refresh()
        TS.Print("Blocklist cleared.")
    end)
    clearBtn:SetPoint("TOPRIGHT", -20, y)
    y = y - 26

    local blockHint = Label(panel, "/qv blocked lists them; /qv block <id> adds one.",
                            "GameFontDisableSmall")
    blockHint:SetPoint("TOPLEFT", 20, y)
    y = y - 26

    local hint = Label(panel, "The anchor is draggable while this window is open.",
                       "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 20, y)
    y = y - 30
    feed:SetHeight(-y)
    feed.pageHeight = -y + 100

    -- ================================================== page: warnings
    panel = warns
    y = -8

    Header(panel, "Melee range glow", y); y = y - 26
    Check(panel, 20, y, "Glow while in melee",
        function() return W().glow end, function(v) W().glow = v end)
    y = y - 38
    Slider(panel, 20, y, 155, "Depth", 20, 200, 5,
        function() return W().glowHeight end, function(v) W().glowHeight = v end)
    Slider(panel, 205, y, 155, "Strength", 0.05, 1, 0.05,
        function() return W().glowAlpha end, function(v) W().glowAlpha = v end, "pct")
    y = y - 42
    Slider(panel, 20, y, 155, "Falloff", 1, 3, 0.1,
        function() return W().glowFalloff end, function(v) W().glowFalloff = v end, "raw")
    Swatch(panel, 205, y + 2, "Glow color", function() return W().glowColor end)
    y = y - 34

    Header(panel, "Swing fill", y); y = y - 26
    Check(panel, 20, y, "Fill while out of melee",
        function() return W().glowSwing end, function(v) W().glowSwing = v end)
    y = y - 38
    Slider(panel, 20, y, 155, "Strength", 0.05, 1, 0.05,
        function() return W().glowSwingAlpha end,
        function(v) W().glowSwingAlpha = v end, "pct")
    Swatch(panel, 205, y + 2, "Fill color", function() return W().swingColor end)
    y = y - 34

    Header(panel, "Aspect & pet", y); y = y - 26
    Check(panel, 20, y, "Wrong aspect",
        function() return W().showAspect end, function(v) W().showAspect = v end)
    y = y - 24
    Check(panel, 20, y, "Pet hurt",
        function() return W().showPetWarn end, function(v) W().showPetWarn = v end)
    Check(panel, 195, y, "Pet in danger",
        function() return W().showPetDanger end, function(v) W().showPetDanger = v end)
    y = y - 38
    Slider(panel, 20, y, 155, "Hurt below %", 20, 95, 5,
        function() return W().petWarnPct end, function(v) W().petWarnPct = v end)
    Slider(panel, 205, y, 155, "Danger below %", 5, 60, 5,
        function() return W().petDangerPct end, function(v) W().petDangerPct = v end)
    y = y - 42
    Slider(panel, 20, y, 155, "Warning text", 8, 24, 1,
        function() return W().fontWarn end, function(v) W().fontWarn = v end)
    Slider(panel, 205, y, 155, "Danger text", 12, 48, 1,
        function() return W().fontDanger end, function(v) W().fontDanger = v end)
    y = y - 34

    local whint = Label(panel, "Warning text is draggable while this window is open.",
                        "GameFontDisableSmall")
    whint:SetPoint("TOPLEFT", 20, y)
    y = y - 30
    warns:SetHeight(-y)
    warns.pageHeight = -y + 100

    panel = panelRef

    local testBtn
    local function UpdateTestButton()
        testBtn.label:SetText(TS.testing and "Stop test" or "Start test")
    end
    testBtn = Button(panel, 110, 22, "Start test", function()
        TS.SetTesting(not TS.testing)
        UpdateTestButton()
    end)
    testBtn:SetPoint("BOTTOMLEFT", 20, 14)

    local defBtn = Button(panel, 110, 22, "Defaults", function()
        TS.ResetDB()
        TS.SetLocked(false, true)
        for _, w in ipairs(widgets) do w:Refresh() end
        TS.Print("Settings reset.")
    end)
    defBtn:SetPoint("BOTTOMRIGHT", -20, 14)

    ShowPage(TS.db.optionsTab or "feed")

    panel:SetScript("OnShow", function()
        TS.SetLocked(false, true)
        for _, w in ipairs(widgets) do w:Refresh() end
        UpdateTestButton()
        ShowPage(TS.db.optionsTab or "feed")
    end)
    panel:SetScript("OnHide", function()
        if TS.testing then TS.SetTesting(false) end
        TS.SetLocked(true, true)
    end)
end

function TS.ToggleOptions()
    if not panel then return end
    if panel:IsShown() then panel:Hide() else panel:Show() end
end

function TS.OpenOptions()
    if panel and not panel:IsShown() then panel:Show() end
end

-- ------------------------------------- Blizzard AddOns settings listing
local function RegisterBlizzOptions()
    local frame = CreateFrame("Frame")
    frame.name = "Quiver"
    local title = Label(frame, "Quiver |cffffd200Hunter|r", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    local sub = Label(frame, "Cast feed, melee glow, aspect and pet warnings.")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    local open = Button(frame, 170, 24, "Open Quiver options", function()
        if SettingsPanel and SettingsPanel:IsShown() then
            HideUIPanel(SettingsPanel)
        elseif InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then
            InterfaceOptionsFrame:Hide()
        end
        TS.OpenOptions()
    end)
    open:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -14)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local ok = pcall(function()
            local cat = Settings.RegisterCanvasLayoutCategory(frame, "Quiver")
            Settings.RegisterAddOnCategory(cat)
        end)
        if ok then return end
    end
    if InterfaceOptions_AddCategory then
        pcall(InterfaceOptions_AddCategory, frame)
    end
end

TS.inits[#TS.inits + 1] = function(db)
    BuildPanel()
    RegisterBlizzOptions()
end
