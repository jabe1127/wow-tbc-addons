local ADDON, ns = ...
local Skin, Util, Queue, Flyout = ns.Skin, ns.Util, ns.Queue, ns.Flyout

local Editor
local ROW_H = 26
local ROWS = 8

local function Build()
    if Editor then return Editor end

    local f = Skin:Window("LoadoutQueueFrame", UIParent, 330, 320, "Slot queue")
    Skin:MakePersistent(f, "queue", "CENTER", 0, 60)
    f:RestorePosition()
    f:SetFrameStrata("HIGH")
    f:SetScript("OnDragStart", function(self)
        if not ns.db.locked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SavePosition()
    end)
    tinsert(UISpecialFrames, "LoadoutQueueFrame")

    local blurb = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    blurb:SetPoint("TOPLEFT", 10, -32)
    blurb:SetPoint("RIGHT", -10, 0)
    blurb:SetJustifyH("LEFT")
    blurb:SetJustifyV("TOP")
    blurb:SetSpacing(2)
    blurb:SetText("Top of the list wins. Whichever item is highest and off cooldown is the one you wear.")
    blurb:SetTextColor(unpack(Skin.colors.textDim))
    blurb:SetHeight(28)

    local auto = Skin:Check(f, "Swap automatically")
    auto:SetPoint("TOPLEFT", 8, -62)
    auto:SetScript("OnClick", function(self)
        local q = Queue:Ensure(f.slotID)
        q.auto = self:GetChecked() and true or false
        ns:Fire("QUEUES_CHANGED")
    end)
    f.auto = auto

    f.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, f)
        r:SetHeight(ROW_H - 2)
        r:SetPoint("TOPLEFT", 10, -(90 + (i - 1) * ROW_H))
        r:SetPoint("RIGHT", -10, 0)
        r.bg = Skin:Fill(r, Skin.colors.row)

        local icon = r:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("LEFT", 4, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.icon = icon

        local rank = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rank:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        rank:SetWidth(16)
        rank:SetJustifyH("LEFT")
        r.rank = rank

        local text = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", rank, "RIGHT", 2, 0)
        text:SetPoint("RIGHT", -76, 0)
        text:SetJustifyH("LEFT")
        r.text = text

        local state = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        state:SetPoint("RIGHT", -68, 0)
        r.state = state

        local del = Skin:Button(r, "×", 18, 18)
        del:SetPoint("RIGHT", -3, 0)
        del.text:SetTextColor(1, 0.45, 0.45)
        del:SetScript("OnClick", function()
            if r.index then Queue:Remove(f.slotID, r.index) f:Refresh() end
        end)

        local down = Skin:Button(r, "▼", 18, 18)
        down:SetPoint("RIGHT", del, "LEFT", -2, 0)
        down:SetScript("OnClick", function()
            if r.index then Queue:Move(f.slotID, r.index, 1) f:Refresh() end
        end)

        local up = Skin:Button(r, "▲", 18, 18)
        up:SetPoint("RIGHT", down, "LEFT", -2, 0)
        up:SetScript("OnClick", function()
            if r.index then Queue:Move(f.slotID, r.index, -1) f:Refresh() end
        end)

        r:SetScript("OnEnter", function(self)
            if not self.link then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.link)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)

        f.rows[i] = r
    end

    local add = Skin:AccentButton(f, "Add an item", 140, 22)
    add:SetPoint("BOTTOMLEFT", 10, 10)
    add.tooltipText = "Pick something from your bags for this slot"
    add:SetScript("OnClick", function(self)
        Flyout:OpenPicker(self, f.slotID, function(data)
            Queue:Add(f.slotID, data)
            f:Refresh()
        end, { mode = "outward", reference = f })
    end)

    local cycle = Skin:Button(f, "Next now", 90, 22)
    cycle:SetPoint("BOTTOMRIGHT", -10, 10)
    cycle.tooltipText = "Step to the next available item straight away"
    cycle:SetScript("OnClick", function()
        Queue:Cycle(f.slotID)
    end)

    function f:Refresh()
        local slotID = self.slotID
        if not slotID then return end

        self.title:SetText("Queue — " .. Util:SlotName(slotID))
        local q = Queue:Get(slotID)
        self.auto:SetChecked(q and q.auto)

        local entries = q and q.entries or {}
        local current = Util:GetEquipped(slotID)

        for i = 1, ROWS do
            local r = self.rows[i]
            local e = entries[i]
            if e then
                r.index = i
                r.link  = e.link
                r.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                r.rank:SetText(i .. ".")
                r.rank:SetTextColor(unpack(Skin.colors.textDim))
                r.text:SetText(Util:Truncate(e.name or "?", 22))

                local worn = current and current.key == e.key
                local left = Queue:CooldownLeft(e)
                local have = Queue:IsAvailable(e)

                if not have then
                    r.state:SetText("|cff8a8a92missing|r")
                elseif left > 1.5 then
                    r.state:SetText(string.format("|cffffcc00%ds|r", math.ceil(left)))
                else
                    r.state:SetText("|cff9fe08cready|r")
                end

                r.text:SetTextColor(worn and 1 or 0.85, worn and 1 or 0.87, worn and 1 or 0.9)
                r.bg:SetColorTexture(unpack(worn and Skin.colors.rowHover or Skin.colors.row))
                r:Show()
            else
                r.index = nil
                r.link = nil
                r:Hide()
            end
        end
    end

    f:SetScript("OnShow", function(self) self:Refresh() end)
    Editor = f
    return f
end

ns:Listen("OPEN_QUEUE", function(slotID)
    if not slotID then return end
    local f = Build()
    f.slotID = slotID
    f:Show()
    f:Refresh()
end)

ns:Listen("QUEUES_CHANGED", function()
    if Editor and Editor:IsShown() then Editor:Refresh() end
end)

ns:Listen("EQUIP_FINISHED", function()
    if Editor and Editor:IsShown() then Editor:Refresh() end
end)

ns:Listen("RESET_POSITIONS", function()
    if Editor then Editor:RestorePosition() end
end)

-- Keep the cooldown numbers ticking while the window is open.
ns:Listen("PLAYER_READY", function()
    C_Timer.NewTicker(0.5, function()
        if Editor and Editor:IsShown() then Editor:Refresh() end
    end)
end)
