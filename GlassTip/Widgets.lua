--=====================================================================
-- GlassTip - Widget toolkit (no Blizzard templates, fully custom look)
--=====================================================================
local ADDON, ns = ...

local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = "Fonts\\FRIZQT__.TTF"

ns.C = {
    accent   = { 0.42, 0.78, 1.00 },
    accentD  = { 0.20, 0.45, 0.65 },
    panel    = { 0.052, 0.058, 0.072 },
    raised   = { 0.085, 0.093, 0.112 },
    line     = { 1, 1, 1, 0.07 },
    text     = { 0.92, 0.93, 0.96 },
    dim      = { 0.60, 0.63, 0.70 },
    good     = { 0.40, 0.85, 0.50 },
}

local function px(f, layer, sub)
    local t = f:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
    t:SetTexture(WHITE)
    return t
end
ns.px = px

function ns:Fill(frame, r, g, b, a, sub)
    local t = px(frame, "BACKGROUND", sub or -7)
    t:SetAllPoints(frame)
    t:SetVertexColor(r, g, b, a or 1)
    return t
end

function ns:Outline(frame, r, g, b, a, inset, size)
    inset = inset or 0
    size = size or 1
    local e = {}
    for _, k in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        e[k] = px(frame, "BORDER", 1)
        e[k]:SetVertexColor(r, g, b, a)
    end
    e.TOP:SetPoint("TOPLEFT", frame, "TOPLEFT", -inset, inset)
    e.TOP:SetPoint("TOPRIGHT", frame, "TOPRIGHT", inset, inset)
    e.TOP:SetHeight(size)
    e.BOTTOM:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -inset, -inset)
    e.BOTTOM:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", inset, -inset)
    e.BOTTOM:SetHeight(size)
    e.LEFT:SetPoint("TOPLEFT", frame, "TOPLEFT", -inset, inset)
    e.LEFT:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -inset, -inset)
    e.LEFT:SetWidth(size)
    e.RIGHT:SetPoint("TOPRIGHT", frame, "TOPRIGHT", inset, inset)
    e.RIGHT:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", inset, -inset)
    e.RIGHT:SetWidth(size)
    return e
end

function ns:FS(parent, size, r, g, b, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size or 12, flags or "")
    fs:SetTextColor(r or ns.C.text[1], g or ns.C.text[2], b or ns.C.text[3])
    return fs
end

--=====================================================================
-- Section header
--=====================================================================
function ns:Header(parent, text)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(24)
    local fs = ns:FS(f, 12, ns.C.accent[1], ns.C.accent[2], ns.C.accent[3])
    fs:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 6)
    fs:SetText(text:upper())
    local line = px(f, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", fs, "BOTTOMRIGHT", 8, 4)
    line:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 6)
    line:SetVertexColor(1, 1, 1, 0.08)
    f.height = 24
    return f
end

--=====================================================================
-- Checkbox
--=====================================================================
function ns:Check(parent, label, get, set, tip)
    local f = CreateFrame("Button", nil, parent)
    f:SetHeight(22)

    local box = CreateFrame("Frame", nil, f)
    box:SetSize(16, 16)
    box:SetPoint("LEFT", f, "LEFT", 0, 0)
    ns:Fill(box, 0.03, 0.035, 0.045, 0.9, -6)
    f.edge = ns:Outline(box, 1, 1, 1, 0.16)

    local mark = px(box, "ARTWORK")
    mark:SetPoint("TOPLEFT", 3, -3)
    mark:SetPoint("BOTTOMRIGHT", -3, 3)
    mark:SetVertexColor(ns.C.accent[1], ns.C.accent[2], ns.C.accent[3], 1)
    f.mark = mark

    local fs = ns:FS(f, 12)
    fs:SetPoint("LEFT", box, "RIGHT", 8, 0)
    fs:SetText(label)
    f.label = fs

    f:SetScript("OnClick", function(self)
        set(not get())
        self:Update()
        if ns.Refresh then ns:Refresh() end
    end)
    f:SetScript("OnEnter", function(self)
        for _, e in pairs(self.edge) do e:SetVertexColor(ns.C.accent[1], ns.C.accent[2], ns.C.accent[3], 0.8) end
        if tip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(label, 1, 1, 1)
            GameTooltip:AddLine(tip, 0.7, 0.72, 0.78, true)
            GameTooltip:Show()
        end
    end)
    f:SetScript("OnLeave", function(self)
        for _, e in pairs(self.edge) do e:SetVertexColor(1, 1, 1, 0.16) end
        GameTooltip:Hide()
    end)

    function f:Update()
        local v = get()
        self.mark:SetShown(v and true or false)
        self.label:SetTextColor(v and ns.C.text[1] or ns.C.dim[1],
                                v and ns.C.text[2] or ns.C.dim[2],
                                v and ns.C.text[3] or ns.C.dim[3])
    end
    f:Update()
    f.height = 22
    return f
end

--=====================================================================
-- Slider
--=====================================================================
function ns:Slider(parent, label, minV, maxV, step, get, set, fmt)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(42)

    local fs = ns:FS(f, 12)
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    fs:SetText(label)

    local val = ns:FS(f, 12, ns.C.accent[1], ns.C.accent[2], ns.C.accent[3])
    val:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)

    local s = CreateFrame("Slider", nil, f)
    s:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -20)
    s:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -20)
    s:SetHeight(16)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouseWheel(true)

    local track = px(s, "BACKGROUND", -6)
    track:SetHeight(3)
    track:SetPoint("LEFT", s, "LEFT", 0, 0)
    track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
    track:SetVertexColor(1, 1, 1, 0.10)

    local fill = px(s, "BACKGROUND", -5)
    fill:SetHeight(3)
    fill:SetPoint("LEFT", s, "LEFT", 0, 0)
    fill:SetVertexColor(ns.C.accent[1], ns.C.accent[2], ns.C.accent[3], 0.85)

    local thumb = s:CreateTexture(nil, "ARTWORK")
    thumb:SetTexture(WHITE)
    thumb:SetSize(6, 14)
    thumb:SetVertexColor(0.95, 0.97, 1, 1)
    s:SetThumbTexture(thumb)

    f.slider = s
    local updating = false

    local function Display(v)
        val:SetText(fmt and fmt(v) or tostring(v))
        local pct = (maxV > minV) and ((v - minV) / (maxV - minV)) or 0
        local w = s:GetWidth()
        fill:SetWidth(math.max(1, w * pct))
    end

    s:SetScript("OnValueChanged", function(self, v)
        if updating then return end
        if step >= 1 then v = math.floor(v + 0.5) else v = math.floor(v / step + 0.5) * step end
        Display(v)
        set(v)
        if ns.Refresh then ns:Refresh() end
    end)
    s:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(self:GetValue() + delta * step)
    end)
    s:SetScript("OnSizeChanged", function() Display(s:GetValue()) end)

    function f:Update()
        updating = true
        local v = get()
        s:SetValue(v)
        Display(v)
        updating = false
    end
    f:Update()
    f.height = 42
    return f
end

--=====================================================================
-- Dropdown
--=====================================================================
local openList
function ns:Dropdown(parent, label, options, get, set, opts)
    -- options = { {value=..., text=..., font=<optional path>}, ... }
    -- opts    = { maxRows = 10, renderFont = true }
    opts = opts or {}
    local maxRows = opts.maxRows or 12
    local ROW = 20

    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(44)

    local fs = ns:FS(f, 12)
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    fs:SetText(label)

    local btn = CreateFrame("Button", nil, f)
    btn:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -18)
    btn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -18)
    btn:SetHeight(24)
    ns:Fill(btn, ns.C.raised[1], ns.C.raised[2], ns.C.raised[3], 1, -6)
    local edge = ns:Outline(btn, 1, 1, 1, 0.12)

    local cur = ns:FS(btn, 12)
    cur:SetPoint("LEFT", btn, "LEFT", 8, 0)
    cur:SetPoint("RIGHT", btn, "RIGHT", -22, 0)
    cur:SetJustifyH("LEFT")

    local arrow = ns:FS(btn, 10, ns.C.accent[1], ns.C.accent[2], ns.C.accent[3])
    arrow:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    arrow:SetText("\226\150\188")

    local shown = math.min(#options, maxRows)
    local listH = shown * ROW + 4

    local list = CreateFrame("Frame", nil, UIParent)
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetToplevel(true)
    list:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -3)
    list:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -3)
    list:SetHeight(listH)
    ns:Fill(list, 0.04, 0.045, 0.058, 0.98, -7)
    ns:Outline(list, ns.C.accent[1], ns.C.accent[2], ns.C.accent[3], 0.45)
    list:Hide()

    local scroll = CreateFrame("ScrollFrame", nil, list)
    scroll:SetPoint("TOPLEFT", list, "TOPLEFT", 2, -2)
    scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -2, 2)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(10, math.max(1, #options * ROW))
    scroll:SetScrollChild(content)

    local maxScroll = math.max(0, #options * ROW - shown * ROW)
    if maxScroll > 0 then
        list:EnableMouseWheel(true)
        list:SetScript("OnMouseWheel", function(self, delta)
            local v = scroll:GetVerticalScroll() - delta * ROW * 2
            scroll:SetVerticalScroll(math.max(0, math.min(maxScroll, v)))
        end)
    end

    local rows = {}
    for i, opt in ipairs(options) do
        local row = CreateFrame("Button", nil, content)
        row:SetHeight(ROW)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * ROW)
        local hl = px(row, "BACKGROUND", -5)
        hl:SetAllPoints(row)
        hl:SetVertexColor(ns.C.accent[1], ns.C.accent[2], ns.C.accent[3], 0.18)
        hl:Hide()
        local t = ns:FS(row, 12)
        t:SetPoint("LEFT", row, "LEFT", 8, 0)
        t:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        t:SetJustifyH("LEFT")
        t:SetText(opt.text)
        -- show each entry in its own face where we have one
        if opts.renderFont and opt.font then
            pcall(t.SetFont, t, opt.font, 13, "")
        end
        row:SetScript("OnEnter", function() hl:Show() end)
        row:SetScript("OnLeave", function() hl:Hide() end)
        row:SetScript("OnClick", function()
            set(opt.value)
            list:Hide()
            openList = nil
            f:Update()
            if ns.Refresh then ns:Refresh() end
        end)
        rows[i] = { row = row, text = t, opt = opt }
    end

    -- content width follows the list once it has one
    list:SetScript("OnSizeChanged", function(self, w) content:SetWidth(w - 4) end)

    btn:SetScript("OnClick", function()
        if list:IsShown() then
            list:Hide(); openList = nil
        else
            if openList and openList ~= list then openList:Hide() end
            content:SetWidth(list:GetWidth() - 4)
            list:Show(); openList = list
            -- scroll the current selection into view
            local v = get()
            for i, r in ipairs(rows) do
                if r.opt.value == v then
                    scroll:SetVerticalScroll(math.max(0, math.min(maxScroll, (i - 1) * ROW - ROW)))
                    break
                end
            end
        end
    end)
    btn:SetScript("OnHide", function()
        list:Hide()
        if openList == list then openList = nil end
    end)
    btn:SetScript("OnEnter", function()
        for _, e in pairs(edge) do e:SetVertexColor(ns.C.accent[1], ns.C.accent[2], ns.C.accent[3], 0.7) end
    end)
    btn:SetScript("OnLeave", function()
        for _, e in pairs(edge) do e:SetVertexColor(1, 1, 1, 0.12) end
    end)

    function f:Update()
        local v = get()
        local found = false
        for _, r in ipairs(rows) do
            if r.opt.value == v then
                cur:SetText(r.opt.text)
                if opts.renderFont and r.opt.font then
                    pcall(cur.SetFont, cur, r.opt.font, 13, "")
                end
                r.text:SetTextColor(ns.C.accent[1], ns.C.accent[2], ns.C.accent[3])
                found = true
            else
                r.text:SetTextColor(ns.C.text[1], ns.C.text[2], ns.C.text[3])
            end
        end
        if not found then cur:SetText("|cff8a8a94(not installed)|r") end
    end
    f:Update()
    f.height = 44
    return f
end

--=====================================================================
-- Colour swatch
--=====================================================================
local function OpenColorPicker(r, g, b, callback)
    local function apply()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        callback(nr, ng, nb)
    end
    local function cancel(prev)
        if type(prev) == "table" then
            callback(prev.r or prev[1], prev.g or prev[2], prev.b or prev[3])
        end
    end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            swatchFunc = apply, cancelFunc = cancel, hasOpacity = false, r = r, g = g, b = b,
        })
    else
        ColorPickerFrame.func = apply
        ColorPickerFrame.cancelFunc = cancel
        ColorPickerFrame.opacityFunc = nil
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.previousValues = { r = r, g = g, b = b }
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end
end

function ns:ColorSwatch(parent, label, get, set)
    local f = CreateFrame("Button", nil, parent)
    f:SetHeight(22)

    local sw = CreateFrame("Frame", nil, f)
    sw:SetSize(30, 14)
    sw:SetPoint("LEFT", f, "LEFT", 0, 0)
    local tex = ns:Fill(sw, 1, 1, 1, 1, -6)
    ns:Outline(sw, 0, 0, 0, 0.8)
    f.tex = tex

    local fs = ns:FS(f, 12)
    fs:SetPoint("LEFT", sw, "RIGHT", 10, 0)
    fs:SetText(label)

    f:SetScript("OnClick", function(self)
        local c = get()
        OpenColorPicker(c[1], c[2], c[3], function(r, g, b)
            set({ r, g, b })
            self:Update()
            if ns.Refresh then ns:Refresh() end
        end)
    end)

    function f:Update()
        local c = get()
        self.tex:SetVertexColor(c[1], c[2], c[3], 1)
    end
    f:Update()
    f.height = 22
    return f
end

--=====================================================================
-- Button
--=====================================================================
function ns:Button(parent, text, onClick, width)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 120, 24)
    ns:Fill(b, ns.C.raised[1], ns.C.raised[2], ns.C.raised[3], 1, -6)
    local edge = ns:Outline(b, 1, 1, 1, 0.14)
    local fs = ns:FS(b, 12)
    fs:SetPoint("CENTER")
    fs:SetText(text)
    b.text = fs
    b:SetScript("OnEnter", function()
        for _, e in pairs(edge) do e:SetVertexColor(ns.C.accent[1], ns.C.accent[2], ns.C.accent[3], 0.85) end
        fs:SetTextColor(ns.C.accent[1], ns.C.accent[2], ns.C.accent[3])
    end)
    b:SetScript("OnLeave", function()
        for _, e in pairs(edge) do e:SetVertexColor(1, 1, 1, 0.14) end
        fs:SetTextColor(ns.C.text[1], ns.C.text[2], ns.C.text[3])
    end)
    b:SetScript("OnClick", onClick)
    b.height = 24
    return b
end

--=====================================================================
-- Vertical stacker
--=====================================================================
function ns:Stack(container, widgets, pad)
    pad = pad or 8
    local y = 0
    for _, w in ipairs(widgets) do
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -y)
        w:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -y)
        y = y + (w.height or w:GetHeight() or 20) + pad
    end
    return y
end
