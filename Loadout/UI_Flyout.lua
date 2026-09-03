local ADDON, ns = ...
local Util, Skin, Equip = ns.Util, ns.Skin, ns.Equip

local Flyout = CreateFrame("Frame", "LoadoutFlyout", UIParent)
ns.Flyout = Flyout

Flyout:SetFrameStrata("FULLSCREEN_DIALOG")
Flyout:SetClampedToScreen(true)
Flyout:Hide()
Flyout.buttons = {}

local PAD = 5

Skin:Fill(Flyout, Skin.colors.bg)
Skin:Border(Flyout)

local header = Flyout:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
header:SetPoint("TOPLEFT", PAD + 1, -PAD)
header:SetTextColor(Skin:Accent())
Flyout.header = header

local closeBtn = CreateFrame("Button", nil, Flyout)
closeBtn:SetSize(16, 14)
closeBtn:SetPoint("TOPRIGHT", -PAD, -PAD + 2)
local closeFS = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
closeFS:SetPoint("CENTER")
closeFS:SetText("×")
closeFS:SetTextColor(0.7, 0.7, 0.75)
closeBtn:SetScript("OnEnter", function() closeFS:SetTextColor(1, 0.4, 0.4) end)
closeBtn:SetScript("OnLeave", function() closeFS:SetTextColor(0.7, 0.7, 0.75) end)
closeBtn:SetScript("OnClick", function() Flyout:Hide() end)
closeBtn:Hide()
Flyout.closeBtn = closeBtn

tinsert(UISpecialFrames, "LoadoutFlyout")

-- =========================================================================
--  Button pool
-- =========================================================================
local function CreateItemButton(index)
    local b = CreateFrame("Button", "LoadoutFlyoutItem" .. index, Flyout)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    Skin:Fill(b, { 0, 0, 0, 0.7 })

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.icon = icon

    b.borderTex = Skin:Border(b, { 0.2, 0.21, 0.24, 1 })

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetColorTexture(1, 1, 1, 0.20)

    local worn = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    worn:SetPoint("BOTTOMRIGHT", -2, 2)
    worn:SetText("W")
    worn:SetTextColor(1, 0.82, 0.2)
    worn:Hide()
    b.wornTag = worn

    b:SetScript("OnEnter", function(self)
        Flyout:CancelHide()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.data then
            if self.data.bag then
                GameTooltip:SetBagItem(self.data.bag, self.data.slot)
            elseif self.data.invSlot then
                GameTooltip:SetInventoryItem("player", self.data.invSlot)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click to equip", 0.4, 0.85, 1)
            GameTooltip:Show()
        end
    end)

    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
        Flyout:ScheduleHide()
    end)

    b:SetScript("OnClick", function(self, button)
        local d = self.data
        if not d then return end
        if IsModifiedClick("CHATLINK") then
            ChatEdit_InsertLink(d.link)
            return
        end
        if Flyout.callback then
            local cb = Flyout.callback
            Flyout:Hide()
            cb(d, Flyout.callbackSlot)
            return
        end
        if d.bag then
            Equip:EquipFromBag(d.bag, d.slot, Flyout.invSlot)
        elseif d.invSlot then
            Equip:SwapWorn(d.invSlot, Flyout.invSlot)
        end
        -- A manual swap means the player is taking over from any rule.
        ns.Rules:Release()
        Flyout:Hide()
    end)

    return b
end

local function GetButton(index)
    if not Flyout.buttons[index] then
        Flyout.buttons[index] = CreateItemButton(index)
    end
    return Flyout.buttons[index]
end

-- =========================================================================
--  Show / hide
-- =========================================================================
function Flyout:CancelHide()
    self.hideAt = nil
end

function Flyout:ScheduleHide()
    self.hideAt = GetTime() + 0.35
end

Flyout:SetScript("OnEnter", function(self) self:CancelHide() end)
Flyout:SetScript("OnLeave", function(self) self:ScheduleHide() end)
Flyout:EnableMouse(true)

Flyout:SetScript("OnUpdate", function(self)
    if self.sticky then return end
    if not self.hideAt then return end
    if self:IsMouseOver() then
        self:CancelHide()
        return
    end
    if self.anchor and self.anchor:IsMouseOver() then
        self:CancelHide()
        return
    end
    if GetTime() >= self.hideAt then
        self:Hide()
    end
end)

Flyout:SetScript("OnHide", function(self)
    self.hideAt       = nil
    self.anchor       = nil
    self.invSlot      = nil
    self.callback     = nil
    self.callbackSlot = nil
    self.sticky       = nil
end)

function Flyout:Open(anchor, invSlot, opts)
    if not ns.db then return end
    opts = opts or {}
    if self:IsShown() and self.invSlot == invSlot and not opts.force then
        self:CancelHide()
        return
    end

    local items = Util:GetCandidates(invSlot, { includeEquipped = opts.includeEquipped })
    if #items == 0 then
        self:Hide()
        if opts.emptyMessage then ns:Print(opts.emptyMessage) end
        return
    end

    self.anchor       = anchor
    self.invSlot      = invSlot
    self.callback     = opts.callback
    self.callbackSlot = invSlot
    self.sticky       = opts.sticky
    self:CancelHide()

    local size = ns.db.flyoutSize or 34
    local cols = opts.columns or math.min(ns.db.flyoutColumns or 6, #items)
    cols = math.max(1, math.min(cols, #items))
    local rows = math.ceil(#items / cols)

    self.header:SetText(Util:SlotName(invSlot):upper()
        .. (opts.callback and "  ·  CHOOSE" or ""))
    self.closeBtn:SetShown(opts.sticky and true or false)

    for i = 1, math.max(#items, #self.buttons) do
        local b = self.buttons[i]
        if i <= #items then
            b = GetButton(i)
            local d = items[i]
            b.data = d
            b:SetSize(size, size)
            b.icon:SetTexture(d.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
            local r, g, bl = Util:QualityColor(d.quality)
            for _, tex in ipairs(b.borderTex) do
                tex:SetColorTexture(r, g, bl, 1)
            end
            b.wornTag:SetShown(d.worn == true)

            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", self, "TOPLEFT",
                PAD + col * (size + 3),
                -(PAD + 14) - row * (size + 3))
            b:Show()
        elseif b then
            b:Hide()
            b.data = nil
        end
    end

    self:SetSize(
        PAD * 2 + cols * size + (cols - 1) * 3,
        PAD * 2 + 14 + rows * size + (rows - 1) * 3
    )

    -- Anchor: prefer right of the slot, fall back to left, then below.
    self:ClearAllPoints()

    -- Slots along the bottom of a panel drop straight down instead of
    -- sideways, so the weapon row does not fly off across the screen.
    if opts.below then
        local room = (anchor:GetBottom() or 0) - self:GetHeight() - 8
        if room > (UIParent:GetBottom() or 0) then
            self:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
        else
            self:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4)
        end
        self:Show()
        return
    end

    -- Which way does it open? Compare the slot's position against a
    -- reference frame's centre. "inward" opens toward that centre (so the
    -- right-hand column of the character sheet flies back over the model
    -- rather than off into open screen); "outward" opens away from it.
    local reference = opts.reference
    if not reference then
        reference = anchor
        while reference:GetParent() and reference:GetParent() ~= UIParent do
            reference = reference:GetParent()
        end
    end

    local anchorX = anchor:GetCenter()
    local refX    = reference and reference:GetCenter() or nil
    local openLeft

    if anchorX and refX then
        local rightOfCentre = anchorX > refX
        if opts.mode == "outward" then
            openLeft = not rightOfCentre
        else
            openLeft = rightOfCentre
        end
    else
        openLeft = false
    end

    -- Screen-space veto: never push the flyout off the edge.
    local w = self:GetWidth()
    local fitsLeft  = ((anchor:GetLeft()  or 0) - w - 6) > (UIParent:GetLeft() or 0)
    local fitsRight = ((anchor:GetRight() or 0) + w + 6) < (UIParent:GetRight() or 0)

    if openLeft and not fitsLeft and fitsRight then
        openLeft = false
    elseif not openLeft and not fitsRight and fitsLeft then
        openLeft = true
    end

    if openLeft then
        self:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4, 4)
    else
        self:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 4)
    end

    self:Show()
end

-- Picker mode: click hands the item back to `callback` instead of equipping.
-- Stays open until something is chosen or Escape/click-away closes it.
function Flyout:OpenPicker(anchor, invSlot, callback, opts)
    opts = opts or {}
    self:Hide()
    self:Open(anchor, invSlot, {
        force           = true,
        includeEquipped = true,
        sticky          = true,
        callback        = callback,
        mode            = opts.mode,
        reference       = opts.reference,
        emptyMessage    = "Nothing in your bags fits that slot.",
    })
end

-- Convenience wrapper used by both the Loadout window and the character sheet.
function Flyout:AttachTo(button, invSlot, getEnabled, opts)
    button:HookScript("OnEnter", function(self)
        if getEnabled and not getEnabled() then return end
        Flyout:Open(self, invSlot, opts)
    end)
    button:HookScript("OnLeave", function()
        Flyout:ScheduleHide()
    end)
end
