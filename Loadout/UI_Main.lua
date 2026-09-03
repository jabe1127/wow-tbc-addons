local ADDON, ns = ...
local Util, Skin, Sets, Equip, Flyout = ns.Util, ns.Skin, ns.Sets, ns.Equip, ns.Flyout

local Main
local SLOT = 38
local GAP  = 3
local STEP = SLOT + GAP

local LEFT_COL = {
    "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot",
    "ChestSlot", "ShirtSlot", "TabardSlot", "WristSlot",
}
local RIGHT_COL = {
    "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot",
    "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot",
}
local BOTTOM_ROW = {
    "MainHandSlot", "SecondaryHandSlot", "RangedSlot",
}

-- One bag pass that tells us which slots have alternatives waiting.
local function CountCandidates()
    local counts = {}
    Util:ScanBags(function(bag, slot, link)
        local equipLoc = Util:EquipLoc(link)
        if equipLoc then
            for _, s in ipairs(Util.slots) do
                if Util:FitsSlot(equipLoc, s.id) then
                    counts[s.id] = (counts[s.id] or 0) + 1
                end
            end
        end
    end)
    return counts
end

-- =========================================================================
--  Slot button behaviour
-- =========================================================================
local function SetupSlotButton(b, slotEntry)
    b.slotKey = slotEntry.key
    b.emptyTex = slotEntry.texture

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        local hasItem = GameTooltip:SetInventoryItem("player", self.slotID)
        if not hasItem then
            GameTooltip:AddLine(Util:SlotName(self.slotID), 1, 1, 1)
            GameTooltip:AddLine("Empty", 0.6, 0.6, 0.65)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Right-click: unequip", 0.4, 0.85, 1)
        GameTooltip:AddLine("Shift-right-click: item queue", 0.4, 0.85, 1)
        GameTooltip:Show()

        if ns.db.hoverFromMain then
            if self.bottomRow then
                Flyout:Open(self, self.slotID, { below = true, columns = 1 })
            else
                Flyout:Open(self, self.slotID, {
                    mode      = "outward",
                    reference = ns.GetMainFrame and ns.GetMainFrame() or nil,
                })
            end
        end
    end)

    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
        Flyout:ScheduleHide()
    end)

    b:SetScript("OnClick", function(self, button)
        local link = GetInventoryItemLink("player", self.slotID)
        if IsModifiedClick("CHATLINK") and link then
            ChatEdit_InsertLink(link)
            return
        end
        if button == "RightButton" then
            if IsShiftKeyDown() then
                ns.Menu:Open(self, {
                    { text = Util:SlotName(self.slotID):upper(), header = true },
                    { text = "Item queue for this slot…",
                      func = function() ns:Fire("OPEN_QUEUE", self.slotID) end },
                    { text = "Unequip", func = function()
                        Equip:UnequipSlot(self.slotID)
                        ns.Rules:Release()
                    end },
                })
                return
            end
            Equip:UnequipSlot(self.slotID)
            ns.Rules:Release()
        end
    end)
end

local function RefreshSlotButton(b, counts)
    local link = GetInventoryItemLink("player", b.slotID)
    if link then
        local info = Util:ItemInfo(link)
        b.icon:SetTexture(info and info.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        b.icon:SetDesaturated(false)
        b.icon:SetAlpha(1)
        b:SetQualityBorder(info and info.quality or 1)
    else
        b.icon:SetTexture(b.emptyTex)
        b.icon:SetDesaturated(true)
        b.icon:SetAlpha(0.45)
        b:SetQualityBorder(1)
    end
    b.pip:SetShown((counts[b.slotID] or 0) > 0)
end

-- =========================================================================
--  Window construction
-- =========================================================================
local function Build()
    if Main then return Main end

    local width  = 380
    local height = 452

    local f = Skin:Window("LoadoutMainFrame", UIParent, width, height, "Loadout")
    Skin:MakePersistent(f, "main", "CENTER", 0, 0)
    f:RestorePosition()
    f:SetScale(ns.db.scale or 1)
    f:SetScript("OnDragStart", function(self)
        if not ns.db.locked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SavePosition()
    end)
    tinsert(UISpecialFrames, "LoadoutMainFrame")   -- Escape closes it

    -- ---------------------------------------------------------- gear grid --
    local grid = CreateFrame("Frame", nil, f)
    grid:SetPoint("TOPLEFT", 9, -33)
    grid:SetSize(4 * STEP - GAP, 9 * STEP - GAP)

    f.slotButtons = {}

    local function AddSlot(key, x, y)
        local entry = Util.slotByKey[key]
        if not entry then return end
        local b = Skin:SlotButton(grid, entry.id, SLOT)
        b:SetPoint("TOPLEFT", x, -y)
        SetupSlotButton(b, entry)
        f.slotButtons[entry.id] = b
    end

    for i, key in ipairs(LEFT_COL)  do AddSlot(key, 0,        (i - 1) * STEP) end
    for i, key in ipairs(RIGHT_COL) do AddSlot(key, STEP,     (i - 1) * STEP) end
    for i, key in ipairs(BOTTOM_ROW) do
        AddSlot(key, (i - 1) * STEP, 8 * STEP + 6)
        local entry = Util.slotByKey[key]
        if entry and f.slotButtons[entry.id] then
            f.slotButtons[entry.id].bottomRow = true
        end
    end

    -- separator between gear and sets
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", 9 + 2 * STEP + 8, -33)
    sep:SetWidth(1)
    sep:SetHeight(9 * STEP)
    sep:SetColorTexture(1, 1, 1, 0.06)

    -- ----------------------------------------------------------- set list --
    local listX = 9 + 2 * STEP + 20
    local listW = width - listX - 9

    local listLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    listLabel:SetPoint("TOPLEFT", listX, -34)
    listLabel:SetText("SETS")
    listLabel:SetTextColor(Skin:Accent())

    local list = ns:CreateSetList(f, listW, 12)
    list:SetPoint("TOPLEFT", listX, -50)
    f.list = list

    local save = Skin:AccentButton(f, "Save current gear", listW, 22)
    save:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -8)
    save.tooltipText = "Store everything you are wearing as a new set."
    save:SetScript("OnClick", function() StaticPopup_Show("LOADOUT_NEW_SET") end)

    local undress = Skin:Button(f, "Take gear off", listW / 2 - 3, 20)
    undress:SetPoint("TOPLEFT", save, "BOTTOMLEFT", 0, -5)
    undress.tooltipText = "Unequip everything except shirt and tabard."
    undress.tooltipExtra = "Shift-click also removes shirt and tabard."
    undress:SetScript("OnClick", function()
        Equip:UnequipAll(IsShiftKeyDown())
        ns.Rules:Release()
    end)

    local options = Skin:Button(f, "Options", listW / 2 - 3, 20)
    options:SetPoint("TOPRIGHT", save, "BOTTOMRIGHT", 0, -5)
    options:SetScript("OnClick", function() ns:Fire("TOGGLE_OPTIONS") end)

    -- ---------------------------------------------------------- footer bar --
    local footer = CreateFrame("Frame", nil, f)
    footer:SetPoint("BOTTOMLEFT", 1, 1)
    footer:SetPoint("BOTTOMRIGHT", -1, 1)
    footer:SetHeight(22)
    Skin:Fill(footer, Skin.colors.header)

    local status = footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    status:SetPoint("LEFT", 8, 0)
    status:SetTextColor(unpack(Skin.colors.textDim))
    f.status = status

    local autoToggle = Skin:Button(footer, "Auto: on", 70, 16)
    autoToggle:SetPoint("RIGHT", -6, 0)
    autoToggle.tooltipText = "Toggle rule-based automatic gear swapping."
    autoToggle:SetScript("OnClick", function(self)
        ns.db.autoSwap = not ns.db.autoSwap
        if not ns.db.autoSwap then ns.Rules:Release() end
        f:UpdateStatus()
        ns.Rules:Evaluate()
    end)
    f.autoToggle = autoToggle

    -- ------------------------------------------------------------ methods --
    function f:UpdateStatus()
        local n = Sets:Count()
        local active = ns.cdb.activeRule
        if active then
            self.status:SetText(n .. " sets  |cff5fd7ff•|r rule: " .. active)
        elseif ns.Rules:IsSuppressed() then
            self.status:SetText(n .. " sets  |cffffcc00•|r your pick (rule parked)")
        else
            self.status:SetText(n .. " set" .. (n == 1 and "" or "s"))
        end
        self.autoToggle:SetLabel(ns.db.autoSwap and "Auto: on" or "Auto: off")
        self.autoToggle.text:SetTextColor(
            ns.db.autoSwap and 0.5 or 0.6,
            ns.db.autoSwap and 0.9 or 0.6,
            ns.db.autoSwap and 0.6 or 0.65)
    end

    function f:RefreshSlots()
        local counts = CountCandidates()
        for _, b in pairs(self.slotButtons) do
            RefreshSlotButton(b, counts)
        end
    end

    function f:RefreshAll()
        if not self:IsShown() then return end
        self:RefreshSlots()
        self.list:Refresh()
        self:UpdateStatus()
    end

    f:SetScript("OnShow", function(self) self:RefreshAll() end)

    Main = f
    return f
end

-- =========================================================================
--  Wiring
-- =========================================================================
local function Toggle()
    local f = Build()
    if f:IsShown() then f:Hide() else f:Show() end
end

ns:Listen("TOGGLE_MAIN", Toggle)

ns:Listen("RESET_POSITIONS", function()
    if Main then Main:RestorePosition() end
end)

local pending = false
local function QueueRefresh()
    if not Main or not Main:IsShown() then return end
    if pending then return end
    pending = true
    C_Timer.After(0.1, function()
        pending = false
        if Main and Main:IsShown() then Main:RefreshAll() end
    end)
end

ns:On("PLAYER_EQUIPMENT_CHANGED", QueueRefresh)
ns:On("BAG_UPDATE_DELAYED", QueueRefresh)
ns:On("UNIT_INVENTORY_CHANGED", QueueRefresh)
ns:Listen("EQUIP_FINISHED", QueueRefresh)
ns:Listen("SETS_CHANGED", QueueRefresh)
ns:Listen("RULES_APPLIED", QueueRefresh)

ns.GetMainFrame = function() return Main end
ns.BuildMainFrame = Build
