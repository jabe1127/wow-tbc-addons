--[[--------------------------------------------------------------------------
    JCT - Widgets.lua
    A tiny, dependency-free widget kit.

    Deliberately uses NO Blizzard XML templates and no Ace libraries. The
    Classic client was rebased onto the 12.0 UI codebase and several long
    standing templates (UIDropDownMenu in particular) are not guaranteed to
    exist any more. Everything here is built from raw frames and textures
    that have shipped with every client since vanilla.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

local W = {}
ns.Widgets = W

local UIFONT = [[Fonts\FRIZQT__.TTF]]

local function setColor(tex, r, g, b, a)
    if tex.SetColorTexture then
        tex:SetColorTexture(r, g, b, a)
    else
        tex:SetTexture(r, g, b, a)
    end
end
W.SetColor = setColor

--------------------------------------------------------------------------
-- Backdrop built from plain textures
--------------------------------------------------------------------------

function W.Backdrop(frame, r, g, b, a, borderAlpha)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    setColor(bg, r or 0.05, g or 0.05, b or 0.07, a or 0.94)
    frame.__bg = bg

    borderAlpha = borderAlpha or 0.5
    local edges = {}
    for i = 1, 4 do
        local t = frame:CreateTexture(nil, "BORDER")
        setColor(t, 0.35, 0.38, 0.45, borderAlpha)
        edges[i] = t
    end
    edges[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    edges[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    edges[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    edges[3]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    edges[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    edges[4]:SetWidth(1)
    frame.__edges = edges
    return frame
end

--------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------

function W.Label(parent, text, size, r, g, b, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ns.SafeSetFont(fs, UIFONT, size or 12, flags or "")
    fs:SetText(text or "")
    fs:SetTextColor(r or 0.9, g or 0.9, b or 0.9)
    fs:SetJustifyH("LEFT")
    return fs
end

function W.Header(parent, text)
    local fs = W.Label(parent, text, 14, 0.5, 0.75, 1.0, "OUTLINE")
    return fs
end

--------------------------------------------------------------------------
-- Button
--------------------------------------------------------------------------

function W.Button(parent, text, width, height, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 100, height or 22)
    W.Backdrop(b, 0.16, 0.18, 0.22, 1, 0.7)

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    setColor(hl, 0.4, 0.6, 1.0, 0.25)

    local fs = W.Label(b, text, 12, 0.95, 0.95, 0.95)
    fs:SetPoint("CENTER")
    fs:SetJustifyH("CENTER")
    b.text = fs

    b:SetScript("OnClick", function(self)
        if onClick then onClick(self) end
    end)
    b.SetLabel = function(self, t) self.text:SetText(t) end
    return b
end

--------------------------------------------------------------------------
-- Checkbox
--------------------------------------------------------------------------

function W.Checkbox(parent, label, get, set, tooltip)
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(22, 22)
    cb:SetNormalTexture([[Interface\Buttons\UI-CheckBox-Up]])
    cb:SetPushedTexture([[Interface\Buttons\UI-CheckBox-Down]])
    cb:SetHighlightTexture([[Interface\Buttons\UI-CheckBox-Highlight]])
    cb:SetCheckedTexture([[Interface\Buttons\UI-CheckBox-Check]])

    local fs = W.Label(cb, label, 12)
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb.label = fs

    cb.__get, cb.__set = get, set
    cb:SetScript("OnClick", function(self)
        local v = self:GetChecked() and true or false
        if self.__set then self.__set(v) end
        if ns.Options and ns.Options.Refresh then ns.Options:Refresh() end
    end)

    if tooltip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    cb.Refresh = function(self)
        if self.__get then self:SetChecked(self.__get() and true or false) end
    end
    cb:Refresh()
    return cb
end

--------------------------------------------------------------------------
-- Slider
--------------------------------------------------------------------------

function W.Slider(parent, label, minV, maxV, step, get, set, width, decimals)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width or 220, 40)

    local title = W.Label(holder, label, 12)
    title:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)

    local value = W.Label(holder, "", 12, 1, 0.85, 0.3)
    value:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
    value:SetJustifyH("RIGHT")

    local s = CreateFrame("Slider", nil, holder)
    s:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -18)
    s:SetSize(width or 220, 16)
    s:SetOrientation("HORIZONTAL")
    s:SetHitRectInsets(0, 0, -6, -6)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:SetThumbTexture([[Interface\Buttons\UI-SliderBar-Button-Horizontal]])
    local th = s:GetThumbTexture()
    if th then th:SetSize(16, 16) end

    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", s, "LEFT", 0, 0)
    track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
    track:SetHeight(4)
    setColor(track, 0.25, 0.27, 0.32, 1)

    holder.slider = s
    holder.__get, holder.__set = get, set
    holder.__decimals = decimals or 0

    local function fmt(v)
        if holder.__decimals > 0 then
            return string.format("%." .. holder.__decimals .. "f", v)
        end
        return tostring(math.floor(v + 0.5))
    end

    s:SetScript("OnValueChanged", function(self, v)
        if holder.__loading then return end
        if holder.__decimals == 0 then v = math.floor(v + 0.5) end
        value:SetText(fmt(v))
        if holder.__set then holder.__set(v) end
    end)

    holder.Refresh = function(self)
        if not self.__get then return end
        self.__loading = true
        local v = self.__get() or minV
        self.slider:SetValue(v)
        value:SetText(fmt(v))
        self.__loading = false
    end

    -- A slider that does nothing in the current mode should look like it,
    -- rather than quietly ignoring you.
    holder.SetEnabled = function(self, on)
        on = on and true or false
        self.slider:EnableMouse(on)
        local a = on and 1 or 0.3
        title:SetAlpha(a)
        value:SetAlpha(a)
        self.slider:SetAlpha(a)
    end

    holder:Refresh()
    return holder
end

--------------------------------------------------------------------------
-- Dropdown (fully custom; no UIDropDownMenu dependency)
--------------------------------------------------------------------------

local openList

local function closeOpenList()
    if openList then
        openList:Hide()
        openList = nil
    end
end

function W.Dropdown(parent, label, itemsFn, get, set, width)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width or 200, 40)

    local title = W.Label(holder, label, 12)
    title:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)

    local btn = CreateFrame("Button", nil, holder)
    btn:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -16)
    btn:SetSize(width or 200, 22)
    W.Backdrop(btn, 0.12, 0.13, 0.17, 1, 0.6)

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(btn)
    setColor(hl, 0.4, 0.6, 1.0, 0.18)

    local text = W.Label(btn, "", 12, 1, 1, 1)
    text:SetPoint("LEFT", btn, "LEFT", 6, 0)
    text:SetPoint("RIGHT", btn, "RIGHT", -16, 0)
    text:SetJustifyH("LEFT")
    btn.text = text

    local arrow = W.Label(btn, "v", 10, 0.7, 0.7, 0.7)
    arrow:SetPoint("RIGHT", btn, "RIGHT", -6, 0)

    holder.__get, holder.__set, holder.__itemsFn = get, set, itemsFn

    local list = CreateFrame("Frame", nil, UIParent)
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:EnableMouse(true)
    list:Hide()
    W.Backdrop(list, 0.07, 0.08, 0.11, 0.98, 0.8)
    list.buttons = {}
    list:SetScript("OnHide", function() if openList == list then openList = nil end end)

    local MAXROWS = 16
    list.offset = 0

    local function buildList()
        local items = holder.__itemsFn() or {}
        local n = #items
        local shown = (n < MAXROWS) and n or MAXROWS
        list:SetSize((width or 200), shown * 20 + 8)

        if list.offset > n - shown then list.offset = n - shown end
        if list.offset < 0 then list.offset = 0 end

        for i = 1, shown do
            local item = items[i + list.offset]
            local b = list.buttons[i]
            if not b then
                b = CreateFrame("Button", nil, list)
                b:SetSize((width or 200) - 8, 20)
                local h = b:CreateTexture(nil, "HIGHLIGHT")
                h:SetAllPoints(b)
                setColor(h, 0.4, 0.6, 1.0, 0.3)
                b.text = W.Label(b, "", 12, 0.92, 0.92, 0.92)
                b.text:SetPoint("LEFT", b, "LEFT", 4, 0)
                list.buttons[i] = b
            end
            b:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -4 - (i - 1) * 20)
            b.text:SetText(item.label or tostring(item.value))
            b.__value = item.value
            b:SetScript("OnClick", function(self)
                closeOpenList()
                if holder.__set then holder.__set(self.__value) end
                holder:Refresh()
                if ns.Options and ns.Options.Refresh then ns.Options:Refresh() end
            end)
            b:Show()
        end
        for i = shown + 1, #list.buttons do list.buttons[i]:Hide() end
        list.__count = n
        list.__shown = shown
    end

    -- Long lists (the font list, once LibSharedMedia is loaded) scroll
    -- rather than running off the bottom of the screen.
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
        if (self.__count or 0) <= (self.__shown or 0) then return end
        self.offset = self.offset - delta
        buildList()
    end)

    btn:SetScript("OnClick", function(self)
        if openList == list then closeOpenList() return end
        closeOpenList()
        list.offset = 0
        buildList()
        list:ClearAllPoints()
        list:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
        list:Show()
        list:Raise()
        openList = list
    end)

    holder.Refresh = function(self)
        if not self.__get then return end
        local v = self.__get()
        local items = self.__itemsFn() or {}
        local shownLabel = tostring(v)
        for i = 1, #items do
            if items[i].value == v then shownLabel = items[i].label break end
        end
        btn.text:SetText(shownLabel)
    end
    holder:Refresh()
    holder.button = btn
    return holder
end

W.CloseDropdowns = closeOpenList

--------------------------------------------------------------------------
-- Colour swatch
--------------------------------------------------------------------------

function W.ColorSwatch(parent, label, get, set)
    local holder = CreateFrame("Button", nil, parent)
    holder:SetSize(180, 20)

    local sw = CreateFrame("Button", nil, holder)
    sw:SetSize(16, 16)
    sw:SetPoint("LEFT", holder, "LEFT", 0, 0)
    W.Backdrop(sw, 0, 0, 0, 1, 0.8)
    local fill = sw:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", sw, "TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", sw, "BOTTOMRIGHT", -2, 2)
    setColor(fill, 1, 1, 1, 1)
    holder.fill = fill

    local fs = W.Label(holder, label, 12)
    fs:SetPoint("LEFT", sw, "RIGHT", 6, 0)

    local function openPicker()
        local r, g, b = get()
        local function apply()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            set(nr, ng, nb)
            setColor(fill, nr, ng, nb, 1)
        end
        local function cancel(prev)
            local pr, pg, pb
            if type(prev) == "table" then
                pr, pg, pb = prev.r or prev[1], prev.g or prev[2], prev.b or prev[3]
            end
            pr, pg, pb = pr or r, pg or g, pb or b
            set(pr, pg, pb)
            setColor(fill, pr, pg, pb, 1)
        end

        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = r, g = g, b = b,
                hasOpacity = false,
                swatchFunc = apply,
                cancelFunc = cancel,
            })
        else
            ColorPickerFrame.func = apply
            ColorPickerFrame.swatchFunc = apply
            ColorPickerFrame.cancelFunc = cancel
            ColorPickerFrame.opacityFunc = nil
            ColorPickerFrame.hasOpacity = false
            ColorPickerFrame.previousValues = { r = r, g = g, b = b, [1] = r, [2] = g, [3] = b }
            ColorPickerFrame:SetColorRGB(r, g, b)
            ColorPickerFrame:Hide()
            ColorPickerFrame:Show()
        end
    end

    sw:SetScript("OnClick", openPicker)
    holder:SetScript("OnClick", openPicker)

    holder.Refresh = function(self)
        local r, g, b = get()
        setColor(self.fill, r or 1, g or 1, b or 1, 1)
    end
    holder:Refresh()
    return holder
end

--------------------------------------------------------------------------
-- Text entry
--------------------------------------------------------------------------

function W.EditBox(parent, label, width, onAccept)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width or 220, 44)

    local title = W.Label(holder, label, 12)
    title:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)

    local eb = CreateFrame("EditBox", nil, holder)
    eb:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -16)
    eb:SetSize(width or 220, 22)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(40)
    eb:SetTextInsets(6, 6, 0, 0)
    ns.SafeSetFont(eb, UIFONT, 12, "")
    eb:SetTextColor(1, 1, 1)
    W.Backdrop(eb, 0.12, 0.13, 0.17, 1, 0.6)

    eb:EnableMouse(true)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self)
        if onAccept then onAccept(self:GetText()) end
        self:ClearFocus()
    end)
    -- Without this, closing the window while the box has focus leaves the
    -- keyboard captured and movement keys dead until you click elsewhere.
    -- A child's OnHide fires when any ancestor hides, so this covers tab
    -- switches too.
    eb:SetScript("OnHide", function(self) self:ClearFocus() end)

    holder.editBox = eb
    holder.GetText = function(self) return self.editBox:GetText() end
    holder.SetText = function(self, t) self.editBox:SetText(t or "") end
    return holder
end

--------------------------------------------------------------------------
-- Multi-line text box, for export and import strings
--------------------------------------------------------------------------

-- selectOnFocus: right for an export box (click, Ctrl+C, done), wrong for an
-- import box, where reselecting everything on a stray click means the next
-- keystroke wipes what was pasted.
function W.TextArea(parent, label, width, height, selectOnFocus)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width or 500, (height or 70) + 18)

    local title = W.Label(holder, label, 12)
    title:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)

    local box = CreateFrame("Frame", nil, holder)
    box:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -16)
    box:SetSize(width or 500, height or 70)
    W.Backdrop(box, 0.10, 0.11, 0.15, 1, 0.6)

    local scroll = CreateFrame("ScrollFrame", nil, box)
    scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 5, -4)
    scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -5, 4)

    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetWidth((width or 500) - 10)
    eb:SetHeight(height or 70)
    ns.SafeSetFont(eb, UIFONT, 11, "")
    eb:SetTextColor(0.9, 0.95, 1)
    eb:EnableMouse(true)
    -- An export string is a few hundred characters; the default cap is far
    -- lower than that, and 0 means no limit.
    pcall(eb.SetMaxLetters, eb, 0)

    scroll:SetScrollChild(eb)

    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnHide", function(self) self:ClearFocus() end)
    if selectOnFocus then
        -- Clicking in selects everything, so copying is Ctrl+C, no dragging.
        eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    end
    eb:SetScript("OnTextChanged", function(self)
        local h = self:GetHeight()
        if h and h > 0 then scroll:UpdateScrollChildRect() end
    end)

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxScroll = (eb:GetHeight() or 0) - (self:GetHeight() or 0)
        if maxScroll < 0 then maxScroll = 0 end
        local new = cur - delta * 20
        if new < 0 then new = 0 end
        if new > maxScroll then new = maxScroll end
        self:SetVerticalScroll(new)
    end)

    -- Clicking the surrounding box focuses the text, which is a much bigger
    -- target than the text itself when the box is empty.
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() eb:SetFocus() end)

    holder.editBox = eb
    holder.GetText = function(self) return self.editBox:GetText() end
    holder.SetText = function(self, t)
        self.editBox:SetText(t or "")
        self.editBox:SetCursorPosition(0)
    end
    holder.SelectAll = function(self)
        self.editBox:SetFocus()
        self.editBox:HighlightText()
    end
    return holder
end

--------------------------------------------------------------------------
-- Scroll container (mouse wheel only; no scrollbar widget needed)
--------------------------------------------------------------------------

function W.ScrollArea(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxScroll = (content:GetHeight() or 0) - (self:GetHeight() or 0)
        if maxScroll < 0 then maxScroll = 0 end
        local new = cur - delta * 40
        if new < 0 then new = 0 end
        if new > maxScroll then new = maxScroll end
        self:SetVerticalScroll(new)
    end)
    scroll.content = content
    return scroll
end

--------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------

function W.Window(globalName, title, width, height)
    local f = CreateFrame("Frame", globalName, UIParent)
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()
    -- An open dropdown is a child of UIParent, so it has to be dismissed
    -- explicitly or it is left floating over the game world.
    f:SetScript("OnHide", function() closeOpenList() end)
    W.Backdrop(f, 0.04, 0.05, 0.07, 0.96, 0.8)

    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    bar:SetHeight(28)
    local barbg = bar:CreateTexture(nil, "ARTWORK")
    barbg:SetAllPoints(bar)
    setColor(barbg, 0.10, 0.14, 0.20, 1)

    local t = W.Label(bar, title, 15, 0.55, 0.78, 1.0, "OUTLINE")
    t:SetPoint("LEFT", bar, "LEFT", 10, 0)

    local close = W.Button(f, "X", 22, 20, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

    f.titleBar = bar
    return f
end

--------------------------------------------------------------------------
-- Resize grip
--
-- SetMinResize/SetMaxResize were replaced by SetResizeBounds in 10.0, and
-- this client is on the rebased codebase, so try the new one first and fall
-- back rather than assuming either exists.
--------------------------------------------------------------------------

function W.AddResizeGrip(frame, minW, minH, maxW, maxH, onStop)
    frame:SetResizable(true)

    if frame.SetResizeBounds then
        pcall(frame.SetResizeBounds, frame, minW, minH, maxW, maxH)
    else
        if frame.SetMinResize then pcall(frame.SetMinResize, frame, minW, minH) end
        if frame.SetMaxResize then pcall(frame.SetMaxResize, frame, maxW, maxH) end
    end

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(frame:GetFrameLevel() + 10)
    grip:SetNormalTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Up]])
    grip:SetHighlightTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Highlight]])
    grip:SetPushedTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Down]])
    grip:EnableMouse(true)
    grip:RegisterForDrag("LeftButton")

    grip:SetScript("OnDragStart", function()
        -- An open dropdown is anchored to a widget that is about to move.
        closeOpenList()
        frame:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        if onStop then onStop(frame:GetWidth(), frame:GetHeight()) end
    end)

    frame.resizeGrip = grip
    return grip
end
