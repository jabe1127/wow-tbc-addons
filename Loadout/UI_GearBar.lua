local ADDON, ns = ...
local Skin, Util, Equip, Flyout = ns.Skin, ns.Util, ns.Equip, ns.Flyout

local Bar
local PAD = 4

-- Shirt and tabard are cosmetic and never swapped mid-fight, so they stay
-- out of the bar unless you ask for them.
local COSMETIC = { ShirtSlot = true, TabardSlot = true }
local SKIP = { AmmoSlot = true }   -- ammo manages itself

local function SlotList()
    local out = {}
    for _, s in ipairs(Util.slots) do
        if not SKIP[s.key] and (ns.db.gearbar.showCosmetic or not COSMETIC[s.key]) then
            table.insert(out, s)
        end
    end
    return out
end

-- One bag pass telling us which slots have alternatives waiting.
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
--  Slot buttons
-- =========================================================================
local function CreateSlot(parent, index)
    local b = Skin:SlotButton(parent, nil, 32)
    b:SetParent(parent)

    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self)
        if ns.db.locked then return end
        local bar = self:GetParent()
        bar:StartMoving()
        bar.isMoving = true
    end)
    b:SetScript("OnDragStop", function(self)
        local bar = self:GetParent()
        if not bar.isMoving then return end
        bar:StopMovingOrSizing()
        bar.isMoving = nil
        bar:SavePosition()
    end)

    b:SetScript("OnEnter", function(self)
        if not self.slotID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local hasItem = GameTooltip:SetInventoryItem("player", self.slotID)
        if not hasItem then
            GameTooltip:AddLine(Util:SlotName(self.slotID), 1, 1, 1)
            GameTooltip:AddLine("Empty", 0.6, 0.6, 0.65)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Right-click: unequip", 0.4, 0.85, 1)
        GameTooltip:Show()

        -- Same pop-out as the character pane. A horizontal bar drops its
        -- choices downward; a vertical one opens to the side.
        if ns.db.gearbar.vertical then
            Flyout:Open(self, self.slotID, { mode = "outward", reference = self:GetParent() })
        else
            Flyout:Open(self, self.slotID, { below = true })
        end
    end)

    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
        Flyout:ScheduleHide()
    end)

    b:SetScript("OnClick", function(self, click)
        if not self.slotID then return end
        local link = GetInventoryItemLink("player", self.slotID)
        if IsModifiedClick("CHATLINK") and link then
            ChatEdit_InsertLink(link)
            return
        end
        if click == "RightButton" then
            if IsShiftKeyDown() then
                ns.Menu:Open(self, {
                    { text = "GEAR BAR", header = true },
                    { text = "Item queue for this slot…",
                      func = function() ns:Fire("OPEN_QUEUE", self.slotID) end },
                    { text = ns.db.gearbar.vertical and "Lay out horizontally" or "Lay out vertically",
                      func = function()
                          ns.db.gearbar.vertical = not ns.db.gearbar.vertical
                          ns:Fire("GEARBAR_UPDATED")
                      end },
                    { text = ns.db.locked and "Unlock frames" or "Lock frames",
                      func = function()
                          ns.db.locked = not ns.db.locked
                          ns:Fire("GEARBAR_UPDATED")
                          ns:Fire("BAR_UPDATED")
                      end },
                    { text = "Options", func = function() ns:Fire("TOGGLE_OPTIONS") end },
                    { text = "Hide gear bar", danger = true, func = function()
                          ns.db.gearbar.show = false
                          ns:Fire("GEARBAR_UPDATED")
                      end },
                })
                return
            end
            Equip:UnequipSlot(self.slotID)
            ns.Rules:Release()
        end
    end)

    return b
end

-- =========================================================================
--  Bar
-- =========================================================================
local function Build()
    if Bar then return Bar end

    local f = CreateFrame("Frame", "LoadoutGearBar", UIParent)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("MEDIUM")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:Hide()

    f.bg = Skin:Fill(f, Skin.colors.bg)
    f.borderTex = Skin:Border(f)
    f.slots = {}

    Skin:MakePersistent(f, "gearbar", "CENTER", 0, -230)
    f:RestorePosition()

    f:SetScript("OnDragStart", function(self)
        if ns.db.locked then return end
        self:StartMoving()
        self.isMoving = true
    end)
    f:SetScript("OnDragStop", function(self)
        if not self.isMoving then return end
        self:StopMovingOrSizing()
        self.isMoving = nil
        self:SavePosition()
    end)

    local grip = f:CreateTexture(nil, "OVERLAY")
    grip:SetPoint("TOPLEFT", 1, -1)
    grip:SetPoint("TOPRIGHT", -1, -1)
    grip:SetHeight(2)
    grip:SetColorTexture(Skin:Accent())
    grip:SetAlpha(0.7)
    f.grip = grip

    function f:Refresh()
        local cfg   = ns.db.gearbar
        local slots = SlotList()
        local size  = cfg.size or 32
        local gap   = cfg.spacing or 3
        local counts = CountCandidates()

        -- Which slots actually get a square
        local shown = {}
        for _, s in ipairs(slots) do
            local link = GetInventoryItemLink("player", s.id)
            if link or not cfg.hideEmpty then
                table.insert(shown, { entry = s, link = link })
            end
        end

        local total = #shown
        local wrap = (cfg.wrap and cfg.wrap > 0) and cfg.wrap or math.max(total, 1)

        for i = 1, math.max(total, #self.slots) do
            local b = self.slots[i]
            if i <= total then
                if not b then
                    b = CreateSlot(self, i)
                    self.slots[i] = b
                end

                local data  = shown[i]
                local entry = data.entry
                b.slotID  = entry.id
                b.emptyTex = entry.texture
                b:SetSize(size, size)

                if data.link then
                    local info = Util:ItemInfo(data.link)
                    b.icon:SetTexture(info and info.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
                    b.icon:SetDesaturated(false)
                    b.icon:SetAlpha(1)
                    b:SetQualityBorder(info and info.quality or 1)
                else
                    b.icon:SetTexture(entry.texture)
                    b.icon:SetDesaturated(true)
                    b.icon:SetAlpha(0.45)
                    b:SetQualityBorder(1)
                end
                b.pip:SetShown((counts[entry.id] or 0) > 0)

                local index = i - 1
                local line  = math.floor(index / wrap)
                local pos   = index % wrap
                local along = PAD + pos * (size + gap)
                local down  = PAD + line * (size + gap)
                b:ClearAllPoints()
                if cfg.vertical then
                    b:SetPoint("TOPLEFT", self, "TOPLEFT", down, -along)
                else
                    b:SetPoint("TOPLEFT", self, "TOPLEFT", along, -down)
                end
                b:Show()
            elseif b then
                b.slotID = nil
                b:Hide()
            end
        end

        local across = math.min(math.max(total, 1), wrap)
        local lines  = math.ceil(math.max(total, 1) / wrap)
        local a = PAD * 2 + across * size + (across - 1) * gap
        local bDim = PAD * 2 + lines * size + (lines - 1) * gap
        if cfg.vertical then
            self:SetSize(bDim, a)
        else
            self:SetSize(a, bDim)
        end

        for _, tex in ipairs(self.borderTex) do
            tex:SetAlpha(cfg.backdrop and 1 or 0)
        end
        self.bg:SetAlpha(cfg.backdrop and 1 or 0)
        self.grip:SetShown(not ns.db.locked)
    end

    f:SetScript("OnShow", function(self) self:Refresh() end)

    Bar = f
    return f
end

-- =========================================================================
--  Wiring
-- =========================================================================
local function Update()
    if not ns.db then return end
    if not ns.db.gearbar.show then
        if Bar then Bar:Hide() end
        return
    end
    local f = Build()
    f:Show()
    f:Refresh()
end

local pending = false
local function QueueRefresh()
    if not Bar or not Bar:IsShown() then return end
    if pending then return end
    pending = true
    C_Timer.After(0.1, function()
        pending = false
        if Bar and Bar:IsShown() then Bar:Refresh() end
    end)
end

ns:Listen("PLAYER_READY",     Update)
ns:Listen("GEARBAR_UPDATED",  Update)
ns:Listen("EQUIP_FINISHED",   QueueRefresh)
ns:Listen("RESET_POSITIONS",  function() if Bar then Bar:RestorePosition() end end)

ns:On("PLAYER_EQUIPMENT_CHANGED", QueueRefresh)
ns:On("BAG_UPDATE_DELAYED",       QueueRefresh)
ns:On("UNIT_INVENTORY_CHANGED",   QueueRefresh)

ns.ToggleGearBar = function()
    ns.db.gearbar.show = not ns.db.gearbar.show
    Update()
end
