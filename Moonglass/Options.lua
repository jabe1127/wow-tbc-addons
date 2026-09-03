--[[----------------------------------------------------------------------------
    Moonglass — Options
    Plainly-worded settings, a tooltip on every checkbox, applied live.
------------------------------------------------------------------------------]]
local _, ns = ...

local panel = CreateFrame("Frame", "MoonglassOptionsPanel")
panel.name = "Moonglass"

-- all widgets live on a scrollable content frame so nothing gets cut off
local content

local refreshers = {}
local function OnRefresh()
    for i = 1, #refreshers do refreshers[i]() end
end
panel:SetScript("OnShow", OnRefresh)

local function Apply()
    ns.ApplyMapSettings()
    OnRefresh()
end

local widgetTip = function(self)
    if self.tipTitle then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tipTitle)
        if self.tipText then GameTooltip:AddLine(self.tipText, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end
end
local widgetTipHide = function() GameTooltip:Hide() end

--------------------------------------------------------------- widget kit
local function Header(x, y, text, big)
    local fs = content:CreateFontString(nil, "ARTWORK", big and "GameFontNormalLarge" or "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function Note(x, y, text, width)
    local fs = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetWidth(width or 250)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(0.7, 0.7, 0.75)
    fs:SetText(text)
    return fs
end

local checkCount = 0
local function Check(x, y, label, tip, get, set)
    checkCount = checkCount + 1
    local cb = CreateFrame("CheckButton", "MoonglassOptCheck" .. checkCount, content, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb:SetSize(24, 24)
    local text = cb.Text or _G[cb:GetName() .. "Text"]
    if text then
        text:SetText(label)
        text:SetFontObject("GameFontHighlight")
    end
    cb.tipTitle, cb.tipText = label, tip
    cb:SetScript("OnEnter", widgetTip)
    cb:SetScript("OnLeave", widgetTipHide)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        Apply()
    end)
    refreshers[#refreshers + 1] = function() cb:SetChecked(get() and true or false) end
    return cb
end

local radioCount = 0
local function RadioRow(x, y, label, tip, choices, get, set)
    Header(x, y, label)
    local buttons = {}
    local cx = x + 4
    for i = 1, #choices do
        radioCount = radioCount + 1
        local rb = CreateFrame("CheckButton", "MoonglassOptRadio" .. radioCount, content, "UIRadioButtonTemplate")
        rb:SetPoint("TOPLEFT", cx, y - 18)
        rb:SetSize(16, 16)
        local fs = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", rb, "RIGHT", 2, 0)
        fs:SetText(choices[i].label)
        rb.value = choices[i].value
        rb.tipTitle, rb.tipText = choices[i].label, tip
        rb:SetScript("OnEnter", widgetTip)
        rb:SetScript("OnLeave", widgetTipHide)
        rb:SetScript("OnClick", function()
            set(rb.value)
            Apply()
        end)
        buttons[#buttons + 1] = rb
        cx = cx + 18 + fs:GetStringWidth() + 14
    end
    refreshers[#refreshers + 1] = function()
        for i = 1, #buttons do
            buttons[i]:SetChecked(buttons[i].value == get())
        end
    end
end

local sliderCount = 0
local function Slider(x, y, label, minV, maxV, step, get, set, fmt)
    sliderCount = sliderCount + 1
    local s = CreateFrame("Slider", "MoonglassOptSlider" .. sliderCount, content)
    s:SetPoint("TOPLEFT", x + 4, y - 20)
    s:SetSize(180, 16)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end

    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)
    track:SetHeight(4)
    track:SetColorTexture(0.25, 0.25, 0.3, 0.9)
    s:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = s:GetThumbTexture()
    thumb:SetSize(10, 16)
    thumb:SetVertexColor(0.75, 0.8, 0.95, 1)

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 4)
    title:SetText(label)
    local lo = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    lo:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -2)
    lo:SetText(fmt and fmt(minV) or minV)
    local hi = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hi:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", 0, -2)
    hi:SetText(fmt and fmt(maxV) or maxV)

    local updating
    s:SetScript("OnValueChanged", function(_, value)
        if updating then return end
        value = math.floor(value / step + 0.5) * step
        title:SetText(("%s: %s"):format(label, fmt and fmt(value) or value))
        set(value)
        ns.ApplyMapSettings()
    end)
    refreshers[#refreshers + 1] = function()
        updating = true
        s:SetValue(get())
        updating = false
        local v = get()
        title:SetText(("%s: %s"):format(label, fmt and fmt(v) or v))
    end
    return s
end

local function ColorSwatch(x, y, label, tip, get, set)
    local btn = CreateFrame("Button", nil, content)
    btn:SetPoint("TOPLEFT", x + 4, y)
    btn:SetSize(16, 16)
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(1, 1, 1, 1)
    btn.swatch = btn:CreateTexture(nil, "ARTWORK")
    btn.swatch:SetPoint("TOPLEFT", 1, -1)
    btn.swatch:SetPoint("BOTTOMRIGHT", -1, 1)
    local fs = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("LEFT", btn, "RIGHT", 6, 0)
    fs:SetText(label)
    btn.tipTitle, btn.tipText = label, tip
    btn:SetScript("OnEnter", widgetTip)
    btn:SetScript("OnLeave", widgetTipHide)
    local function paint()
        local r, g, b = get()
        btn.swatch:SetColorTexture(r, g, b, 1)
    end
    btn:SetScript("OnClick", function()
        local r, g, b = get()
        local function commit()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            set(nr, ng, nb)
            paint()
            Apply()
        end
        local function cancel(prev)
            if prev and prev.r then
                set(prev.r, prev.g, prev.b)
                paint()
                Apply()
            end
        end
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = r, g = g, b = b,
                swatchFunc = commit,
                cancelFunc = cancel,
            })
        else
            ColorPickerFrame.func = commit
            ColorPickerFrame.cancelFunc = cancel
            ColorPickerFrame.previousValues = { r = r, g = g, b = b }
            ColorPickerFrame:SetColorRGB(r, g, b)
            ColorPickerFrame:Show()
        end
    end)
    refreshers[#refreshers + 1] = paint
    return btn
end

------------------------------------------------------------------- layout
local L, R = 16, 330   -- column x positions
local db  -- filled on init

local function BuildPanel()
    db = ns.db

    local scroll = CreateFrame("ScrollFrame", "MoonglassOptionsScroll", panel)
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -2, 2)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(600, 1120)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, content:GetHeight() - self:GetHeight())
        local cur = self:GetVerticalScroll() or 0
        self:SetVerticalScroll(math.min(maxScroll, math.max(0, cur - delta * 40)))
    end)

    local y

    Header(L, -16, "Moonglass", true)
    Note(L + 110, -20, "v" .. ns.VERSION, 100)
    Note(L, -36, "Everything applies instantly.  Hold Shift and drag to move the map or the info bar any time.  Mouse wheel scrolls this page.", 560)

    ---------------- left column: the map
    y = -64
    Header(L, y, "Map"); y = y - 6

    y = y - 18
    RadioRow(L, y, "Shape", "Round or square minimap.", {
        { label = "Round", value = "round" },
        { label = "Square", value = "square" },
    }, function() return db.shape end, function(v) db.shape = v end)
    y = y - 44

    RadioRow(L, y, "Border", "How the edge of the map is drawn.", {
        { label = "Glass", value = "glass" },
        { label = "Thin line", value = "thin" },
        { label = "Glow", value = "glow" },
        { label = "None", value = "none" },
    }, function() return db.border end, function(v) db.border = v end)
    y = y - 48

    Check(L, y, "Class-colored border",
        "Tint the thin-line and glow borders with your class color. Uncheck to pick your own color below.",
        function() return db.classColor end, function(v) db.classColor = v end)
    y = y - 26
    ColorSwatch(L + 4, y, "Border color",
        "Custom border color, used when class color is off.",
        function() return db.borderColor.r, db.borderColor.g, db.borderColor.b end,
        function(r, g, b) db.borderColor.r, db.borderColor.g, db.borderColor.b = r, g, b end)
    y = y - 24

    Check(L, y, "Inner shadow",
        "A soft shadow around the inside edge of the map. Subtle, but makes it feel finished.",
        function() return db.vignette end, function(v) db.vignette = v end)
    y = y - 26

    Check(L, y, "Lock the map",
        "When unlocked, drag the map anywhere with the left mouse button. Locked or not, holding Shift while dragging always moves it.",
        function() return db.locked end, function(v) db.locked = v end)
    y = y - 26

    Check(L, y, "Zoom back out automatically",
        "A few seconds after you zoom in, the map returns to the widest view on its own.",
        function() return db.autoZoomOut end, function(v) db.autoZoomOut = v end)
    y = y - 26

    Check(L, y, "Show who pinged",
        "When someone pings the map, their name appears briefly at the bottom of it.",
        function() return db.showPings end, function(v) db.showPings = v end)
    y = y - 26

    Check(L, y, "Hide Blizzard clutter",
        "Hides the zoom buttons, world map button, day/night moon, and clock. Zooming still works with the mouse wheel. (Reload the UI to bring them back after unchecking.)",
        function() return db.hideClutter end, function(v) db.hideClutter = v end)
    y = y - 26

    RadioRow(L, y, "Zone name", "When the zone name is shown at the top of the map.", {
        { label = "Always", value = "always" },
        { label = "On mouse-over", value = "hover" },
        { label = "Hidden", value = "never" },
    }, function() return db.zoneText end, function(v) db.zoneText = v end)
    y = y - 48

    Slider(L, y, "Map size", 120, 280, 10,
        function() return db.size end, function(v) db.size = v end)
    y = y - 52
    Slider(L, y, "Map opacity", 30, 100, 5,
        function() return math.floor(db.opacity * 100 + 0.5) end,
        function(v) db.opacity = v / 100 end,
        function(v) return v .. "%" end)

    ---------------- right column: info bar, buttons, indicators, far zoom
    y = -64
    Header(R, y, "Info bar"); y = y - 24

    Check(R, y, "Show the info bar",
        "A slim bar attached to the map with your gold, the time, and more.",
        function() return db.bar.enabled end, function(v) db.bar.enabled = v end)
    y = y - 26

    RadioRow(R, y, "Position", "Attach the bar under or over the map, or detach it and Shift-drag it anywhere on screen.", {
        { label = "Below map", value = "below" },
        { label = "Above map", value = "above" },
        { label = "Detached", value = "detached" },
    }, function() return db.bar.position end, function(v) db.bar.position = v end)
    y = y - 48

    Check(R, y, "Gold",
        "Your current gold. Hover it for what you've earned and spent this session.",
        function() return db.bar.modules.gold end, function(v) db.bar.modules.gold = v end)
    y = y - 24
    Check(R, y, "Time",
        "The current time. Click it to switch between local and server time.",
        function() return db.bar.modules.time end, function(v) db.bar.modules.time = v end)
    y = y - 24
    Check(R, y, "Guild online",
        "How many guildmates are online. Hover it to see who, click it to open the guild panel.",
        function() return db.bar.modules.guild end, function(v) db.bar.modules.guild = v end)
    y = y - 24
    Check(R, y, "FPS and latency",
        "Your framerate and connection latency.",
        function() return db.bar.modules.fps end, function(v) db.bar.modules.fps = v end)
    y = y - 24
    Check(R, y, "Durability",
        "Your most-damaged piece of gear, as a percentage. Turns red when repairs are urgent.",
        function() return db.bar.modules.durability end, function(v) db.bar.modules.durability = v end)
    y = y - 24
    Check(R, y, "New mail",
        "A mail notice in the bar whenever you have unread mail, with the latest senders on hover. Hidden when your mailbox is clear.",
        function() return db.bar.modules.mail end, function(v) db.bar.modules.mail = v end)
    y = y - 26

    Check(R, y, "24-hour clock",
        "Show 21:30 instead of 9:30 pm.",
        function() return db.bar.hour24 end, function(v) db.bar.hour24 = v end)
    y = y - 30

    Slider(R, y, "Bar text size", 10, 16, 1,
        function() return db.bar.fontSize end, function(v) db.bar.fontSize = v end)
    y = y - 52
    Slider(R, y, "Bar size", 60, 160, 5,
        function() return math.floor((db.bar.scale or 1) * 100 + 0.5) end,
        function(v) db.bar.scale = v / 100 end,
        function(v) return v .. "%" end)
    y = y - 54

    Check(R, y, "Match the map's width",
        "The bar stays exactly as wide as the map. Uncheck to set its length yourself with the slider below.",
        function() return not db.bar.width or db.bar.width == 0 end,
        function(v)
            if v then db.bar.width = 0 else db.bar.width = math.max(db.size, 200) end
        end)
    y = y - 30
    Slider(R, y, "Bar length", 120, 600, 10,
        function() return (db.bar.width and db.bar.width > 0) and db.bar.width or db.size end,
        function(v) db.bar.width = v end)
    y = y - 56

    Header(R, y, "Addon buttons"); y = y - 24
    Check(R, y, "Collect addon buttons into one",
        "Gathers the minimap buttons other addons add into a single tidy button on the map edge.",
        function() return db.bag.enabled end, function(v) db.bag.enabled = v end)
    y = y - 24
    Check(R, y, "Open on hover",
        "Open the collected buttons by mousing over instead of clicking.",
        function() return db.bag.hover end, function(v) db.bag.hover = v end)
    y = y - 30

    Header(R, y, "Queues and alerts"); y = y - 24
    Check(R, y, "Battleground, arena and group queues",
        "Clean icons on the map for every queue you're in: yellow ring while queued, pulsing green when your match is ready (click to enter, right-click to leave).",
        function() return db.indicators.queues end, function(v) db.indicators.queues = v end)
    y = y - 24
    Check(R, y, "Tracking",
        "Shows what you're currently tracking. Click it to change tracking.",
        function() return db.indicators.tracking end, function(v) db.indicators.tracking = v end)
    y = y - 24
    Check(R, y, "New mail",
        "A mail icon when you have unread mail, with the latest senders on hover.",
        function() return db.indicators.mail end, function(v) db.indicators.mail = v end)
    y = y - 30

    Header(R, y, "Blizzard quest tracker"); y = y - 6
    y = y - 18
    RadioRow(R, y, "Quest objectives text",
        "Blizzard puts the quest objectives list right under the minimap, where it overlaps. Move it clear of Moonglass, or hide it completely.", {
        { label = "Leave alone", value = "leave" },
        { label = "Move below", value = "move" },
        { label = "Hide", value = "hide" },
    }, function() return db.questTracker end, function(v) db.questTracker = v end)
    y = y - 46
    Slider(R, y, "Gap below Moonglass", 0, 200, 5,
        function() return db.questTrackerGap or 12 end,
        function(v) db.questTrackerGap = v end)
    y = y - 56

    Header(R, y, "Far zoom"); y = y - 24
    Check(R, y, "Zoom out beyond the normal limit",
        "Keep scrolling the mouse wheel down at the widest view and the map switches to a live zone view centered on you — all the way out to the whole zone.",
        function() return db.farzoom.enabled end, function(v) db.farzoom.enabled = v end)
end

------------------------------------------------------------------ register
ns.RegisterInit(function()
    BuildPanel()
    OnRefresh()

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "Moonglass")
        Settings.RegisterAddOnCategory(category)
        ns.OpenOptions = function()
            Settings.OpenToCategory(category.GetID and category:GetID() or "Moonglass")
        end
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        ns.OpenOptions = function()
            InterfaceOptionsFrame_OpenToCategory(panel)
            InterfaceOptionsFrame_OpenToCategory(panel)
        end
    else
        ns.OpenOptions = function()
            print("|cff9db7ffMoonglass:|r options panel could not be registered on this client.")
        end
    end
end)
