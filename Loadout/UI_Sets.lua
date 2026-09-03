local ADDON, ns = ...
local Util, Skin, Sets, Equip = ns.Util, ns.Skin, ns.Sets, ns.Equip

-- =========================================================================
--  Static popups
-- =========================================================================
StaticPopupDialogs["LOADOUT_NEW_SET"] = {
    text = "Name this gear set:",
    button1 = SAVE or "Save",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    maxLetters = 40,
    OnShow = function(self)
        local eb = self.editBox or _G[self:GetName() .. "EditBox"]
        if eb then eb:SetText("") eb:SetFocus() end
    end,
    OnAccept = function(self)
        local eb = self.editBox or _G[self:GetName() .. "EditBox"]
        local name = eb and eb:GetText() or ""
        if name ~= "" then
            Sets:SaveCurrent(name, true)
            ns:Print("Saved '" .. name .. "'.")
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["LOADOUT_NEW_SET"].OnAccept(parent)
        parent:Hide()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["LOADOUT_RENAME_SET"] = {
    text = "Rename '%s' to:",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    maxLetters = 40,
    OnShow = function(self, data)
        local eb = self.editBox or _G[self:GetName() .. "EditBox"]
        if eb then eb:SetText(data or "") eb:HighlightText() eb:SetFocus() end
    end,
    OnAccept = function(self, data)
        local eb = self.editBox or _G[self:GetName() .. "EditBox"]
        local name = eb and eb:GetText() or ""
        if name ~= "" then Sets:Rename(data, name) end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["LOADOUT_RENAME_SET"].OnAccept(parent, parent.data)
        parent:Hide()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["LOADOUT_DELETE_SET"] = {
    text = "Delete the gear set '%s'?",
    button1 = DELETE or "Delete",
    button2 = CANCEL or "Cancel",
    OnAccept = function(self, data) Sets:Delete(data) end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- =========================================================================
--  Lightweight context menu
-- =========================================================================
local Menu = CreateFrame("Frame", "LoadoutContextMenu", UIParent)
ns.Menu = Menu
Menu:SetFrameStrata("FULLSCREEN_DIALOG")
Menu:SetClampedToScreen(true)
Menu:EnableMouse(true)
Menu:Hide()
Skin:Fill(Menu, Skin.colors.bg)
Skin:Border(Menu)
Menu.rows = {}

local MENU_ROW_H = 19

local function MenuRow(i)
    if Menu.rows[i] then return Menu.rows[i] end
    local r = CreateFrame("Button", nil, Menu)
    r:SetHeight(MENU_ROW_H)
    r:SetPoint("LEFT", 3, 0)
    r:SetPoint("RIGHT", -3, 0)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(r)
    hl:SetColorTexture(1, 1, 1, 0.10)
    local fs = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", 6, 0)
    fs:SetJustifyH("LEFT")
    r.text = fs
    r:SetScript("OnClick", function(self)
        Menu:Hide()
        if self.func then self.func() end
    end)
    Menu.rows[i] = r
    return r
end

function Menu:Open(anchor, entries)
    local width = 120
    for i, e in ipairs(entries) do
        local r = MenuRow(i)
        r.text:SetText(e.text)
        if e.header then
            r.text:SetTextColor(Skin:Accent())
            r.func = nil
            r:EnableMouse(false)
        else
            r.text:SetTextColor(unpack(e.danger and { 1, 0.4, 0.4 } or Skin.colors.text))
            r.func = e.func
            r:EnableMouse(true)
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", self, "TOPLEFT", 3, -(3 + (i - 1) * MENU_ROW_H))
        r:SetPoint("TOPRIGHT", self, "TOPRIGHT", -3, -(3 + (i - 1) * MENU_ROW_H))
        r:Show()
        width = math.max(width, r.text:GetStringWidth() + 22)
    end
    for i = #entries + 1, #self.rows do self.rows[i]:Hide() end

    self:SetSize(width, #entries * MENU_ROW_H + 6)
    self:ClearAllPoints()
    local scale = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    self:Show()
end

Menu:SetScript("OnUpdate", function(self)
    if self:IsShown() and not self:IsMouseOver(20, -20, -20, 20) then
        if self.closeAt and GetTime() > self.closeAt then self:Hide() end
        self.closeAt = self.closeAt or (GetTime() + 0.6)
    else
        self.closeAt = nil
    end
end)

-- =========================================================================
--  Icon picker
-- =========================================================================
local IconPicker
local function GetIconPicker()
    if IconPicker then return IconPicker end

    local f = Skin:Window("LoadoutIconPicker", UIParent, 8 * 34 + 22, 6 * 34 + 62, "Choose an icon")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetPoint("CENTER")
    f:Hide()
    f.page = 1
    f.buttons = {}

    local icons = {}
    f.icons = icons

    local function BuildIconList()
        if #icons > 0 then return end
        table.insert(icons, "Interface\\Icons\\INV_Misc_Bag_08")
        if GetMacroIcons then
            local t = {}
            GetMacroIcons(t)
            for _, v in ipairs(t) do table.insert(icons, v) end
        elseif GetNumMacroIcons then
            for i = 1, GetNumMacroIcons() do
                table.insert(icons, GetMacroIconInfo(i))
            end
        end
    end

    for i = 1, 48 do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(32, 32)
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(b)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.icon = icon
        Skin:Border(b, { 0.2, 0.21, 0.24, 1 })
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(b)
        hl:SetColorTexture(1, 1, 1, 0.25)
        local col, row = (i - 1) % 8, math.floor((i - 1) / 8)
        b:SetPoint("TOPLEFT", 11 + col * 34, -34 - row * 34)
        b:SetScript("OnClick", function(self)
            if f.setName and self.tex then
                Sets:SetIcon(f.setName, self.tex)
            end
            f:Hide()
        end)
        f.buttons[i] = b
    end

    local prev = Skin:Button(f, "<", 30, 20)
    prev:SetPoint("BOTTOMLEFT", 11, 9)
    local next_ = Skin:Button(f, ">", 30, 20)
    next_:SetPoint("BOTTOMRIGHT", -11, 9)
    local pageText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pageText:SetPoint("BOTTOM", 0, 14)

    function f:Refresh()
        BuildIconList()
        local total = math.max(1, math.ceil(#icons / 48))
        self.page = math.max(1, math.min(self.page, total))
        for i = 1, 48 do
            local idx = (self.page - 1) * 48 + i
            local b = self.buttons[i]
            local tex = icons[idx]
            if tex then
                if type(tex) == "number" then
                    b.icon:SetTexture(tex)
                else
                    b.icon:SetTexture("Interface\\Icons\\" .. tostring(tex):gsub("^Interface\\\\Icons\\\\", ""))
                end
                b.tex = b.icon:GetTexture()
                b:Show()
            else
                b:Hide()
            end
        end
        pageText:SetText(self.page .. " / " .. total)
    end

    prev:SetScript("OnClick", function() f.page = f.page - 1 f:Refresh() end)
    next_:SetScript("OnClick", function() f.page = f.page + 1 f:Refresh() end)

    IconPicker = f
    return f
end

function ns:OpenIconPicker(setName)
    local f = GetIconPicker()
    f.setName = setName
    f.page = 1
    f:Refresh()
    f:Show()
end

-- =========================================================================
--  Set list widget (shared by the main window and the character panel)
-- =========================================================================
local ROW_H = 22

local function SetContextEntries(name)
    return {
        { text = "Equip",              func = function() Sets:Equip(name) ns.Rules:Release() end },
        { text = "Edit set…",          func = function() ns:Fire("OPEN_EDITOR", name) end },
        { text = "Update from worn",   func = function() Sets:SaveCurrent(name, true) ns:Print("Updated '" .. name .. "'.") end },
        { text = "Rule from target",   func = function() ns.Rules:AddFromTarget(name) end },
        { text = "Rename",             func = function()
            local d = StaticPopup_Show("LOADOUT_RENAME_SET", name)
            if d then d.data = name end
        end },
        { text = "Change icon",        func = function() ns:OpenIconPicker(name) end },
        { text = "Move up",            func = function() Sets:Move(name, -1) end },
        { text = "Move down",          func = function() Sets:Move(name, 1) end },
        { text = "Delete", danger = true, func = function()
            if ns.db.confirmDelete then
                local d = StaticPopup_Show("LOADOUT_DELETE_SET", name)
                if d then d.data = name end
            else
                Sets:Delete(name)
            end
        end },
    }
end

ns.SetContextEntries = SetContextEntries

function ns:CreateSetList(parent, width, rowCount)
    local list = CreateFrame("Frame", nil, parent)
    list:SetSize(width, rowCount * ROW_H)
    list.offset = 0
    list.rows = {}

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
        local total = #Sets:GetOrder()
        local maxOffset = math.max(0, total - rowCount)
        self.offset = math.max(0, math.min(maxOffset, self.offset - delta))
        self:Refresh()
    end)

    for i = 1, rowCount do
        local r = CreateFrame("Button", nil, list)
        r:SetHeight(ROW_H - 2)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        r.bg = Skin:Fill(r, Skin.colors.row)

        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(r)
        hl:SetColorTexture(1, 1, 1, 0.09)

        local mark = r:CreateTexture(nil, "ARTWORK")
        mark:SetPoint("TOPLEFT", 0, 0)
        mark:SetPoint("BOTTOMLEFT", 0, 0)
        mark:SetWidth(2)
        mark:SetColorTexture(Skin:Accent())
        mark:Hide()
        r.mark = mark

        local icon = r:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", 6, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.icon = icon

        local fs = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        fs:SetPoint("RIGHT", -4, 0)
        fs:SetJustifyH("LEFT")
        r.text = fs

        r:SetScript("OnClick", function(self, button)
            if not self.setName then return end
            if button == "RightButton" then
                ns.Menu:Open(self, SetContextEntries(self.setName))
            elseif IsShiftKeyDown() then
                ns:Fire("OPEN_EDITOR", self.setName)
            else
                Sets:Equip(self.setName)
                ns.Rules:Release()
            end
        end)

        r:SetScript("OnEnter", function(self)
            if not self.setName then return end
            local set = Sets:Get(self.setName)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.setName, 1, 1, 1)

            local items, missing, ignored, empties = 0, 0, 0, 0
            for _, item in pairs(set.items or {}) do
                items = items + 1
                if not ns.Util:FindItem(item.key) then missing = missing + 1 end
            end
            for _ in pairs(set.ignored or {}) do ignored = ignored + 1 end
            for _ in pairs(set.empty   or {}) do empties = empties + 1 end

            GameTooltip:AddLine(items .. " item(s)"
                .. (empties > 0 and (", " .. empties .. " emptied") or "")
                .. (ignored > 0 and (", " .. ignored .. " ignored") or ""),
                0.7, 0.7, 0.75)
            if missing > 0 then
                GameTooltip:AddLine(missing .. " not in your bags", 1, 0.45, 0.45)
            end

            for _, rule in ipairs(ns.cdb.rules) do
                if rule.set == self.setName then
                    GameTooltip:AddLine("Rule: " .. ns.Rules:Describe(rule), 0.55, 0.8, 0.55)
                end
            end

            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Left-click: equip", 0.4, 0.85, 1)
            GameTooltip:AddLine("Shift-click: edit", 0.4, 0.85, 1)
            GameTooltip:AddLine("Right-click: options", 0.4, 0.85, 1)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)

        list.rows[i] = r
    end

    function list:Refresh()
        local order = Sets:GetOrder()
        local total = #order
        self.offset = math.max(0, math.min(self.offset, math.max(0, total - rowCount)))

        for i = 1, rowCount do
            local r = self.rows[i]
            local name = order[i + self.offset]
            if name then
                local set = Sets:Get(name)
                r.setName = name
                r.text:SetText(name)
                r.icon:SetTexture(set.icon or "Interface\\Icons\\INV_Misc_Bag_08")

                local worn   = Sets:IsEquipped(name)
                local ruled  = (ns.cdb.activeRule == name)
                r.mark:SetShown(worn or ruled)
                if worn then
                    r.text:SetTextColor(1, 1, 1)
                    r.bg:SetColorTexture(unpack(Skin.colors.rowHover))
                else
                    r.text:SetTextColor(unpack(Skin.colors.text))
                    r.bg:SetColorTexture(unpack(Skin.colors.row))
                end
                r:Show()
            else
                r.setName = nil
                r:Hide()
            end
        end

        if total == 0 then
            if not self.emptyText then
                local fs = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                fs:SetPoint("TOP", 0, -14)
                fs:SetText("No sets yet")
                fs:SetTextColor(unpack(Skin.colors.textDim))
                self.emptyText = fs
            end
            self.emptyText:Show()
        elseif self.emptyText then
            self.emptyText:Hide()
        end
    end

    ns:Listen("SETS_CHANGED",  function() if list:IsVisible() then list:Refresh() end end)
    ns:Listen("SET_EQUIPPED",  function() if list:IsVisible() then list:Refresh() end end)
    ns:Listen("RULES_APPLIED", function() if list:IsVisible() then list:Refresh() end end)
    ns:Listen("EQUIP_FINISHED", function() if list:IsVisible() then list:Refresh() end end)
    list:SetScript("OnShow", function(self) self:Refresh() end)

    return list
end

-- =========================================================================
--  Character frame side panel — the fast path for save / equip / remove
-- =========================================================================
local CharPanel

local function BuildCharPanel()
    if CharPanel then return CharPanel end
    if not CharacterFrame then return nil end

    local f = CreateFrame("Frame", "LoadoutCharacterPanel", CharacterFrame)
    f:SetSize(190, 340)
    f:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", -6, -12)
    f:SetFrameStrata(CharacterFrame:GetFrameStrata())
    f:SetFrameLevel(CharacterFrame:GetFrameLevel())
    f:SetClampedToScreen(true)
    f:Hide()

    Skin:Fill(f, Skin.colors.bg)
    Skin:Border(f)

    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(24)
    Skin:Fill(header, Skin.colors.header)

    local accent = header:CreateTexture(nil, "OVERLAY")
    accent:SetPoint("BOTTOMLEFT")
    accent:SetPoint("BOTTOMRIGHT")
    accent:SetHeight(1)
    local ar, ag, ab = Skin:Accent()
    accent:SetColorTexture(ar, ag, ab, 0.55)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("LEFT", 8, 0)
    title:SetText("Gear Sets")
    title:SetTextColor(0.95, 0.95, 0.97)

    -- list
    local list = ns:CreateSetList(f, 172, 11)
    list:SetPoint("TOPLEFT", 9, -32)
    f.list = list

    -- buttons
    local save = Skin:AccentButton(f, "Save current", 172, 22)
    save:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -8)
    save.tooltipText = "Save what you are wearing as a new set."
    save:SetScript("OnClick", function() StaticPopup_Show("LOADOUT_NEW_SET") end)

    local undress = Skin:Button(f, "Take gear off", 84, 20)
    undress:SetPoint("TOPLEFT", save, "BOTTOMLEFT", 0, -5)
    undress.tooltipText = "Unequip everything except shirt and tabard."
    undress.tooltipExtra = "Shift-click to include shirt and tabard."
    undress:SetScript("OnClick", function()
        Equip:UnequipAll(IsShiftKeyDown())
        ns.Rules:Release()
    end)

    local window = Skin:Button(f, "Window", 84, 20)
    window:SetPoint("TOPRIGHT", save, "BOTTOMRIGHT", 0, -5)
    window.tooltipText = "Open the standalone gear window."
    window:SetScript("OnClick", function() ns:Fire("TOGGLE_MAIN") end)

    local opts = Skin:Button(f, "Options", 172, 20)
    opts:SetPoint("TOPLEFT", undress, "BOTTOMLEFT", 0, -5)
    opts:SetScript("OnClick", function() ns:Fire("TOGGLE_OPTIONS") end)

    f:SetHeight(32 + 11 * ROW_H + 8 + 22 + 5 + 20 + 5 + 20 + 10)

    CharPanel = f
    return f
end

-- Toggle tab on the character frame
local function BuildCharTab()
    if not CharacterFrame or not ns.db.showCharButton then return end
    if CharacterFrame.loadoutTab then return end

    local tab = CreateFrame("Button", "LoadoutCharacterTab", CharacterFrame)
    tab:SetSize(24, 64)
    -- Hangs off the outside edge so it never covers an equipment slot.
    tab:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", -31, -62)
    tab:SetFrameLevel(CharacterFrame:GetFrameLevel() + 4)

    Skin:Fill(tab, Skin.colors.header)
    Skin:Border(tab)
    local hl = tab:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(tab)
    hl:SetColorTexture(1, 1, 1, 0.12)

    local fs = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER")
    fs:SetText("G\nE\nA\nR")
    fs:SetSpacing(-2)
    fs:SetTextColor(Skin:Accent())

    tab:SetScript("OnClick", function()
        local p = BuildCharPanel()
        if not p then return end
        if p:IsShown() then p:Hide() else p:Show() p.list:Refresh() end
    end)
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Loadout", 1, 1, 1)
        GameTooltip:AddLine("Save, equip and remove gear sets.", 0.7, 0.7, 0.75)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)

    CharacterFrame.loadoutTab = tab

    CharacterFrame:HookScript("OnHide", function()
        if CharPanel then CharPanel:Hide() end
        ns.Flyout:Hide()
    end)
end

-- =========================================================================
--  Flyouts on Blizzard's paper doll slots
-- =========================================================================
-- The weapon row sits along the bottom of the character panel, so its
-- choices stack downward in a single column rather than sideways.
local BOTTOM_SLOTS = {
    MainHandSlot = true, SecondaryHandSlot = true,
    RangedSlot = true, AmmoSlot = true,
}

local function HookPaperDoll()
    for _, s in ipairs(Util.slots) do
        local btn = _G["Character" .. s.key]
        if btn and not btn.loadoutHooked then
            btn.loadoutHooked = true
            local opts
            if BOTTOM_SLOTS[s.key] then
                opts = { below = true, columns = 1 }
            else
                opts = { mode = "inward", reference = CharacterFrame }
            end
            ns.Flyout:AttachTo(btn, s.id, function()
                return ns.db and ns.db.hoverFromPaper
            end, opts)
        end
    end
end

ns:Listen("PLAYER_READY", function()
    BuildCharTab()
    HookPaperDoll()
end)

ns:Listen("TOGGLE_CHAR_PANEL", function()
    local p = BuildCharPanel()
    if p then
        if p:IsShown() then p:Hide() else p:Show() end
    end
end)
