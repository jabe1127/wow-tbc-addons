local ADDON, ns = ...
local Util, Skin, Sets, Equip, Flyout = ns.Util, ns.Skin, ns.Sets, ns.Equip, ns.Flyout

local Editor
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
local BOTTOM_ROW = { "MainHandSlot", "SecondaryHandSlot", "RangedSlot" }

-- =========================================================================
--  Slot state
-- =========================================================================
local STATE = { ITEM = 1, EMPTY = 2, IGNORED = 3, UNSET = 4 }

local function SlotState(set, slotID)
    if not set then return STATE.UNSET end
    if (set.ignored or {})[slotID] then return STATE.IGNORED end
    if set.items[slotID] then return STATE.ITEM end
    if (set.empty or {})[slotID] then return STATE.EMPTY end
    return STATE.UNSET
end

local function Assign(set, slotID, data)
    set.ignored[slotID] = nil
    set.empty[slotID]   = nil
    local info = Util:ItemInfo(data.link)
    set.items[slotID] = {
        key  = data.key,
        link = data.link,
        name = info and info.name or data.name,
    }
    ns:Fire("SETS_CHANGED")
end

local function MarkEmpty(set, slotID)
    set.ignored[slotID] = nil
    set.items[slotID]   = nil
    set.empty[slotID]   = true
    ns:Fire("SETS_CHANGED")
end

local function MarkIgnored(set, slotID)
    set.items[slotID]   = nil
    set.empty[slotID]   = nil
    set.ignored[slotID] = true
    ns:Fire("SETS_CHANGED")
end

local function ClearSlot(set, slotID)
    set.items[slotID]   = nil
    set.empty[slotID]   = nil
    set.ignored[slotID] = nil
    ns:Fire("SETS_CHANGED")
end

-- =========================================================================
--  Window
-- =========================================================================
local function Build()
    if Editor then return Editor end

    local width  = 4 * STEP - GAP + 18 + 200
    local height = 9 * STEP + 92

    local f = Skin:Window("LoadoutEditorFrame", UIParent, width, height, "Edit set")
    Skin:MakePersistent(f, "editor", "CENTER", -260, 0)
    f:RestorePosition()
    f:SetScript("OnDragStart", function(self)
        if not ns.db.locked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SavePosition()
    end)
    f:SetFrameStrata("HIGH")
    tinsert(UISpecialFrames, "LoadoutEditorFrame")

    -- ---------------------------------------------------------- slot grid --
    local grid = CreateFrame("Frame", nil, f)
    grid:SetPoint("TOPLEFT", 9, -34)
    grid:SetSize(4 * STEP - GAP, 9 * STEP)

    f.buttons = {}

    local function OnSlotClick(self, button)
        local set = Sets:Get(f.setName)
        if not set then return end
        local slotID = self.slotID

        if button == "RightButton" then
            ns.Menu:Open(self, {
                { text = "Use worn item", func = function()
                    local eq = Util:GetEquipped(slotID)
                    if eq then
                        Assign(set, slotID, eq)
                    else
                        ns:Print("Nothing is equipped in that slot.")
                    end
                end },
                { text = "Choose item…", func = function()
                    Flyout:OpenPicker(self, slotID, function(data)
                        Assign(set, slotID, data)
                    end, { mode = "outward", reference = f })
                end },
                { text = "Unequip this slot", func = function() MarkEmpty(set, slotID) end },
                { text = "Ignore this slot",  func = function() MarkIgnored(set, slotID) end },
                { text = "Clear", danger = true, func = function() ClearSlot(set, slotID) end },
            })
            return
        end

        -- Left-click cycles nothing surprising: it just opens the picker.
        Flyout:OpenPicker(self, slotID, function(data)
            Assign(set, slotID, data)
        end, { mode = "outward", reference = f })
    end

    local function OnSlotEnter(self)
        local set = Sets:Get(f.setName)
        local state = SlotState(set, self.slotID)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(Util:SlotName(self.slotID), 1, 1, 1)
        if state == STATE.ITEM then
            local item = set.items[self.slotID]
            if item and item.link then
                GameTooltip:SetHyperlink(item.link)
                GameTooltip:AddLine(" ")
                if not Util:FindItem(item.key) then
                    GameTooltip:AddLine("Not in your bags right now", 1, 0.5, 0.5)
                end
            end
        elseif state == STATE.EMPTY then
            GameTooltip:AddLine("Will be unequipped", 1, 0.6, 0.4)
        elseif state == STATE.IGNORED then
            GameTooltip:AddLine("Ignored — never touched by this set", 0.6, 0.6, 0.65)
        elseif Util.AMMO and self.slotID == Util.AMMO then
            GameTooltip:AddLine("Not pinned — the set will load the highest-dps ammunition your weapon can fire",
                0.55, 0.8, 0.55, true)
        else
            GameTooltip:AddLine("Not part of this set", 0.6, 0.6, 0.65)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click: choose an item", 0.4, 0.85, 1)
        GameTooltip:AddLine("Right-click: slot options", 0.4, 0.85, 1)
        GameTooltip:Show()
    end

    local function AddSlot(key, x, y)
        local entry = Util.slotByKey[key]
        if not entry then return end
        local b = Skin:SlotButton(grid, entry.id, SLOT)
        b:SetPoint("TOPLEFT", x, -y)
        b.emptyTex = entry.texture
        b.pip:Hide()

        local overlay = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        overlay:SetPoint("CENTER")
        overlay:Hide()
        b.overlay = overlay

        b:SetScript("OnClick", OnSlotClick)
        b:SetScript("OnEnter", OnSlotEnter)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)

        f.buttons[entry.id] = b
    end

    for i, key in ipairs(LEFT_COL)   do AddSlot(key, 0,    (i - 1) * STEP) end
    for i, key in ipairs(RIGHT_COL)  do AddSlot(key, STEP, (i - 1) * STEP) end
    for i, key in ipairs(BOTTOM_ROW) do AddSlot(key, (i - 1) * STEP, 8 * STEP + 6) end

    -- ------------------------------------------------------------- sidebar --
    local sideX = 9 + 2 * STEP + 16
    local sideW = width - sideX - 10

    local nameFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameFS:SetPoint("TOPLEFT", sideX, -36)
    nameFS:SetWidth(sideW)
    nameFS:SetJustifyH("LEFT")
    f.nameFS = nameFS

    local countFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countFS:SetPoint("TOPLEFT", sideX, -54)
    countFS:SetTextColor(unpack(Skin.colors.textDim))
    f.countFS = countFS

    local legend = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    legend:SetPoint("TOPLEFT", sideX, -76)
    legend:SetWidth(sideW)
    legend:SetJustifyH("LEFT")
    legend:SetSpacing(3)
    legend:SetText(
        "|cff9fe08cItem|r  the set equips it\n" ..
        "|cffffa060Empty|r  the slot gets emptied\n" ..
        "|cff8a8a92Ignored|r  never touched\n" ..
        "|cff5a5a62Unset|r  filled in on 'update'")
    legend:SetTextColor(unpack(Skin.colors.textDim))

    local y = -152
    local function SideButton(label, tip, onClick, accent)
        local b = accent and Skin:AccentButton(f, label, sideW, 22)
                        or Skin:Button(f, label, sideW, 20)
        b:SetPoint("TOPLEFT", sideX, y)
        b.tooltipText = tip
        b:SetScript("OnClick", onClick)
        y = y - (accent and 26 or 24)
        return b
    end

    SideButton("Fill from worn gear", "Overwrite every non-ignored slot with what you are wearing.", function()
        if f.setName then
            Sets:SaveCurrent(f.setName, true)
            f:Refresh()
        end
    end, true)

    SideButton("Equip this set", nil, function()
        if f.setName then
            Sets:Equip(f.setName)
            ns.Rules:Release()
        end
    end)

    SideButton("Ignore empty slots", "Mark every currently-unset slot as ignored.", function()
        local set = Sets:Get(f.setName)
        if not set then return end
        for _, s in ipairs(Util.slots) do
            if SlotState(set, s.id) == STATE.UNSET then
                set.ignored[s.id] = true
            end
        end
        ns:Fire("SETS_CHANGED")
        f:Refresh()
    end)

    SideButton("Clear all slots", "Empty the set completely.", function()
        local set = Sets:Get(f.setName)
        if not set then return end
        wipe(set.items)
        wipe(set.empty)
        wipe(set.ignored)
        ns:Fire("SETS_CHANGED")
        f:Refresh()
    end)

    SideButton("Rename", nil, function()
        if not f.setName then return end
        local d = StaticPopup_Show("LOADOUT_RENAME_SET", f.setName)
        if d then d.data = f.setName end
    end)

    SideButton("Change icon", nil, function()
        if f.setName then ns:OpenIconPicker(f.setName) end
    end)

    -- boss rule shortcut
    local bossBtn = Skin:Button(f, "Rule from target", sideW, 20)
    bossBtn:SetPoint("TOPLEFT", sideX, y - 8)
    bossBtn.tooltipText = "Create a rule that equips this set whenever you target your current target."
    bossBtn:SetScript("OnClick", function()
        if f.setName then
            ns.Rules:AddFromTarget(f.setName)
            ns:Fire("TOGGLE_OPTIONS_RULES")
        end
    end)

    -- ------------------------------------------------------------ refresh --
    function f:Refresh()
        local set = Sets:Get(self.setName)
        if not set then self:Hide() return end

        self.title:SetText("Edit set")
        self.nameFS:SetText(self.setName)

        local n, missing = 0, 0
        for slotID, item in pairs(set.items) do
            n = n + 1
            if not Util:FindItem(item.key) then missing = missing + 1 end
        end
        if missing > 0 then
            self.countFS:SetText(n .. " item(s), |cffff6666" .. missing .. " missing|r")
        else
            self.countFS:SetText(n .. " item(s)")
        end

        for _, s in ipairs(Util.slots) do
            local b = self.buttons[s.id]
            if b then
                local state = SlotState(set, s.id)
                b.overlay:Hide()
                b.icon:SetDesaturated(false)
                b.icon:SetVertexColor(1, 1, 1)

                if state == STATE.ITEM then
                    local item = set.items[s.id]
                    local info = Util:ItemInfo(item.link)
                    b.icon:SetTexture(info and info.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
                    b.icon:SetAlpha(1)
                    b:SetQualityBorder(info and info.quality or 1)
                    if not Util:FindItem(item.key) then
                        b.icon:SetVertexColor(1, 0.5, 0.5)
                    end
                elseif state == STATE.EMPTY then
                    b.icon:SetTexture(b.emptyTex)
                    b.icon:SetDesaturated(true)
                    b.icon:SetAlpha(0.35)
                    b:SetQualityBorder(1)
                    b.overlay:SetText("|cffffa060∅|r")
                    b.overlay:Show()
                elseif state == STATE.IGNORED then
                    b.icon:SetTexture(b.emptyTex)
                    b.icon:SetDesaturated(true)
                    b.icon:SetAlpha(0.15)
                    b:SetQualityBorder(1)
                    b.overlay:SetText("|cff8a8a92–|r")
                    b.overlay:Show()
                else
                    b.icon:SetTexture(b.emptyTex)
                    b.icon:SetDesaturated(true)
                    b.icon:SetAlpha(0.35)
                    b:SetQualityBorder(1)
                end
            end
        end
    end

    f:SetScript("OnShow", function(self) self:Refresh() end)
    Editor = f
    return f
end

-- =========================================================================
--  Wiring
-- =========================================================================
ns:Listen("OPEN_EDITOR", function(setName)
    local set = Sets:Get(setName)
    if not set then
        ns:Print("No set named '" .. tostring(setName) .. "'.")
        return
    end
    -- older sets may predate these tables
    set.items   = set.items   or {}
    set.empty   = set.empty   or {}
    set.ignored = set.ignored or {}

    local f = Build()
    f.setName = setName
    f:Show()
    f:Refresh()
end)

ns:Listen("SETS_CHANGED", function()
    if Editor and Editor:IsShown() then Editor:Refresh() end
end)

ns:Listen("EQUIP_FINISHED", function()
    if Editor and Editor:IsShown() then Editor:Refresh() end
end)

ns:Listen("RESET_POSITIONS", function()
    if Editor then Editor:RestorePosition() end
end)
