local ADDON, ns = ...

local Skin = {}
ns.Skin = Skin

Skin.colors = {
    bg        = { 0.055, 0.058, 0.066, 0.95 },
    panel     = { 0.085, 0.090, 0.100, 0.95 },
    header    = { 0.115, 0.122, 0.135, 1.00 },
    row       = { 0.130, 0.137, 0.152, 0.70 },
    rowHover  = { 0.200, 0.215, 0.240, 0.85 },
    border    = { 0.000, 0.000, 0.000, 0.90 },
    hairline  = { 1.000, 1.000, 1.000, 0.055 },
    text      = { 0.870, 0.880, 0.900 },
    textDim   = { 0.520, 0.540, 0.575 },
}

function Skin:Accent()
    local c = ns.classColor or { r = 0.35, g = 0.78, b = 1 }
    return c.r, c.g, c.b
end

-- ------------------------------------------------------------------ base --
-- Flat fill + 1px border built from plain textures. No BackdropTemplate
-- dependency, so this behaves identically on every Classic build.
function Skin:Fill(frame, color)
    local t = frame:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(frame)
    t:SetColorTexture(unpack(color))
    return t
end

function Skin:Border(frame, color, inset)
    inset = inset or 0
    color = color or self.colors.border
    local edges = {}
    local function line(p1, p2, w, h)
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(unpack(color))
        t:SetPoint(p1, frame, p1, inset, -inset)
        t:SetPoint(p2, frame, p2, -inset, inset)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        table.insert(edges, t)
        return t
    end
    line("TOPLEFT",    "TOPRIGHT",    nil, 1)
    line("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    line("TOPLEFT",    "BOTTOMLEFT",  1,   nil)
    line("TOPRIGHT",   "BOTTOMRIGHT", 1,   nil)
    return edges
end

function Skin:Panel(parent, name)
    local f = CreateFrame("Frame", name, parent)
    f.bg = self:Fill(f, self.colors.panel)
    self:Border(f)
    return f
end

-- ---------------------------------------------------------------- window --
function Skin:Window(name, parent, width, height, title)
    local f = CreateFrame("Frame", name, parent or UIParent)
    f:SetSize(width, height)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("MEDIUM")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")

    f.bg = self:Fill(f, self.colors.bg)
    self:Border(f)

    -- header
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(26)
    self:Fill(header, self.colors.header)
    f.header = header

    -- class-coloured accent line under the header
    local accent = header:CreateTexture(nil, "OVERLAY")
    accent:SetPoint("BOTTOMLEFT", 0, 0)
    accent:SetPoint("BOTTOMRIGHT", 0, 0)
    accent:SetHeight(1)
    local ar, ag, ab = self:Accent()
    accent:SetColorTexture(ar, ag, ab, 0.55)
    f.accent = accent

    local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 9, 0)
    label:SetText(title or "")
    label:SetTextColor(0.95, 0.95, 0.97)
    f.title = label

    -- close button
    local close = CreateFrame("Button", nil, header)
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", -3, 0)
    local x = close:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    x:SetPoint("CENTER", 0, 0)
    x:SetText("×")
    x:SetTextColor(0.7, 0.7, 0.75)
    close:SetScript("OnEnter", function() x:SetTextColor(1, 0.4, 0.4) end)
    close:SetScript("OnLeave", function() x:SetTextColor(0.7, 0.7, 0.75) end)
    close:SetScript("OnClick", function() f:Hide() end)
    f.closeButton = close

    -- drag handling
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if not (ns.db and ns.db.locked) then f:StartMoving() end
    end)
    header:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        if f.SavePosition then f:SavePosition() end
    end)

    return f
end

-- Persist / restore a frame position under ns.cdb.ui[key]
function Skin:MakePersistent(frame, key, defPoint, defX, defY)
    frame.SavePosition = function(self)
        if not ns.cdb then return end
        local point, _, relPoint, x, y = self:GetPoint()
        ns.cdb.ui[key] = { point = point, relPoint = relPoint, x = x, y = y }
    end
    frame.RestorePosition = function(self)
        local p = ns.cdb and ns.cdb.ui[key]
        self:ClearAllPoints()
        if p then
            self:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
        else
            self:SetPoint(defPoint or "CENTER", UIParent, defPoint or "CENTER", defX or 0, defY or 0)
        end
    end
end

-- ---------------------------------------------------------------- button --
function Skin:Button(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 80, height or 20)

    b.bg = self:Fill(b, self.colors.row)
    self:Border(b, { 0, 0, 0, 0.8 })

    local hl = b:CreateTexture(nil, "ARTWORK")
    hl:SetAllPoints(b)
    hl:SetColorTexture(1, 1, 1, 0.07)
    hl:Hide()
    b.hl = hl

    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER", 0, 0)
    fs:SetText(text or "")
    fs:SetTextColor(unpack(self.colors.text))
    b.text = fs
    b.SetLabel = function(self, t) self.text:SetText(t) end

    b:SetScript("OnEnter", function(self)
        self.hl:Show()
        if self.tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.tooltipText, 1, 1, 1, true)
            if self.tooltipExtra then
                GameTooltip:AddLine(self.tooltipExtra, 0.7, 0.7, 0.75, true)
            end
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.hl:Hide()
        GameTooltip:Hide()
    end)
    b:SetScript("OnMouseDown", function(self) self.text:SetPoint("CENTER", 1, -1) end)
    b:SetScript("OnMouseUp", function(self) self.text:SetPoint("CENTER", 0, 0) end)

    return b
end

function Skin:AccentButton(parent, text, width, height)
    local b = self:Button(parent, text, width, height)
    local r, g, bl = self:Accent()
    b.bg:SetColorTexture(r * 0.35, g * 0.35, bl * 0.35, 0.85)
    b.text:SetTextColor(1, 1, 1)
    return b
end

-- ------------------------------------------------------------ checkbutton --
function Skin:Check(parent, label)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(22, 22)
    local fs = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", c, "RIGHT", 2, 0)
    fs:SetText(label)
    fs:SetTextColor(unpack(self.colors.text))
    c.label = fs

    -- Extend the hit area over the label so clicking or hovering the text
    -- behaves the same as the box itself.
    c.SyncHitRect = function(self)
        self:SetHitRectInsets(0, -(self.label:GetStringWidth() + 8), 0, 0)
    end
    c:SyncHitRect()

    local setText = fs.SetText
    fs.SetText = function(self, ...)
        setText(self, ...)
        c:SyncHitRect()
    end

    return c
end

-- ----------------------------------------------------------------- slider --
local sliderCount = 0
function Skin:Slider(parent, label, minV, maxV, step)
    sliderCount = sliderCount + 1
    local name = "LoadoutSlider" .. sliderCount
    local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    s:SetWidth(180)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end

    local text = s.Text or _G[name .. "Text"]
    local low  = s.Low  or _G[name .. "Low"]
    local high = s.High or _G[name .. "High"]
    if text then text:SetText(label) end
    if low  then low:SetText(tostring(minV)) end
    if high then high:SetText(tostring(maxV)) end

    s.labelText = label
    s.textLabel = text
    s.SetLabel  = function(self, t) if self.textLabel then self.textLabel:SetText(t) end end
    return s
end

-- ------------------------------------------------------------ slot button --
-- The workhorse: one equipped-item square.
function Skin:SlotButton(parent, slotID, size)
    size = size or 38   -- slotID may be nil; callers can assign it later
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.slotID = slotID
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    self:Fill(b, { 0, 0, 0, 0.6 })

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.icon = icon

    b.borderTex = self:Border(b, { 0.25, 0.26, 0.29, 1 })

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetColorTexture(1, 1, 1, 0.16)

    -- little corner pip shown when other options exist in bags
    local pip = b:CreateTexture(nil, "OVERLAY")
    pip:SetSize(5, 5)
    pip:SetPoint("TOPRIGHT", -2, -2)
    local ar, ag, ab = self:Accent()
    pip:SetColorTexture(ar, ag, ab, 0.95)
    pip:Hide()
    b.pip = pip

    b.SetQualityBorder = function(self, quality)
        local r, g, bl = 0.25, 0.26, 0.29
        if quality and quality > 1 then
            r, g, bl = ns.Util:QualityColor(quality)
        end
        for _, tex in ipairs(self.borderTex) do
            tex:SetColorTexture(r, g, bl, 1)
        end
    end

    return b
end
