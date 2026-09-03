local ADDON, ns = ...
local Skin, Sets, Util = ns.Skin, ns.Sets, ns.Util

local Bar
local PAD = 4
local GROUP_GAP = 8   -- breathing room between the set icons and the action slots

-- =========================================================================
--  Reading whatever is on the cursor
-- =========================================================================
local function ActionFromCursor()
    local kind, a, b, c = GetCursorInfo()
    if not kind then return nil end

    if kind == "spell" then
        local spellID = (type(c) == "number") and c or nil
        local name, rank, icon

        if spellID and GetSpellInfo then
            name, rank, icon = GetSpellInfo(spellID)
        end
        if not name and type(a) == "number" and b then
            if GetSpellBookItemName then
                name, rank = GetSpellBookItemName(a, b)
            end
            if GetSpellBookItemTexture then
                icon = GetSpellBookItemTexture(a, b)
            end
        end
        if not name then return nil end

        return {
            type    = "spell",
            name    = name,
            rank    = (rank ~= "" and rank) or nil,
            icon    = icon,
            spellID = spellID,
        }

    elseif kind == "item" then
        local itemID = tonumber(a)
        if not itemID then return nil end
        local name = GetItemInfo(itemID)
        return {
            type   = "item",
            itemID = itemID,
            name   = name or ("item:" .. itemID),
            icon   = GetItemIcon and GetItemIcon(itemID) or nil,
        }

    elseif kind == "macro" then
        local index = tonumber(a)
        if not index then return nil end
        local name, icon = GetMacroInfo(index)
        if not name then return nil end
        return { type = "macro", name = name, icon = icon }
    end

    return nil
end

-- The string the secure button actually casts. Ranks matter in TBC, so a
-- downranked heal dragged off the spellbook stays downranked.
local function SpellAttribute(action)
    if action.rank and action.rank ~= "" then
        return action.name .. "(" .. action.rank .. ")"
    end
    return action.name
end

local function PickupAction(action)
    if not action then return end
    if action.type == "spell" then
        if action.spellID and PickupSpell then
            PickupSpell(action.spellID)
        elseif PickupSpell then
            PickupSpell(action.name)
        end
    elseif action.type == "item" then
        PickupItem(action.itemID)
    elseif action.type == "macro" then
        PickupMacro(action.name)
    end
end

-- =========================================================================
--  Set buttons
-- =========================================================================
local function CreateSetButton(parent, index)
    local b = CreateFrame("Button", "LoadoutSetBarButton" .. index, parent)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

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

    Skin:Fill(b, { 0, 0, 0, 0.75 })

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.icon = icon

    b.borderTex = Skin:Border(b, { 0.22, 0.23, 0.26, 1 })

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetColorTexture(1, 1, 1, 0.20)

    local glow = b:CreateTexture(nil, "OVERLAY")
    glow:SetPoint("BOTTOMLEFT", 1, 1)
    glow:SetPoint("BOTTOMRIGHT", -1, 1)
    glow:SetHeight(2)
    glow:SetColorTexture(Skin:Accent())
    glow:Hide()
    b.glow = glow

    local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOM", 0, 2)
    label:SetJustifyH("CENTER")
    label:Hide()
    b.label = label

    b:SetScript("OnClick", function(self, click)
        if not self.setName then return end
        if click == "RightButton" then
            ns.Menu:Open(self, ns.SetContextEntries(self.setName))
            return
        end
        Sets:Equip(self.setName)
        ns.Rules:Release()
    end)

    b:SetScript("OnEnter", function(self)
        if not self.setName then return end
        local set = Sets:Get(self.setName)
        if not set then return end

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.setName, 1, 1, 1)

        local items, missing = 0, 0
        for _, item in pairs(set.items or {}) do
            items = items + 1
            if not Util:FindItem(item.key) then missing = missing + 1 end
        end
        GameTooltip:AddLine(items .. " item(s)", 0.7, 0.7, 0.75)
        if missing > 0 then
            GameTooltip:AddLine(missing .. " not in your bags", 1, 0.45, 0.45)
        end
        if Sets:IsEquipped(self.setName) then
            GameTooltip:AddLine("Currently worn", 0.5, 0.9, 0.5)
        end
        for _, rule in ipairs(ns.cdb.rules) do
            if rule.set == self.setName then
                GameTooltip:AddLine("Rule: " .. ns.Rules:Describe(rule), 0.55, 0.8, 0.55)
            end
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click: equip", 0.4, 0.85, 1)
        GameTooltip:AddLine("Right-click: options", 0.4, 0.85, 1)
        GameTooltip:Show()
    end)

    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return b
end

-- =========================================================================
--  Action buttons (secure)
-- =========================================================================
local function CreateActionButton(parent, index)
    local b = CreateFrame("Button", "LoadoutActionButton" .. index, parent,
        "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    b.actionIndex = index

    Skin:Fill(b, { 0, 0, 0, 0.75 })

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.icon = icon

    b.borderTex = Skin:Border(b, { 0.30, 0.26, 0.20, 1 })

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetColorTexture(1, 1, 1, 0.20)

    local cd = CreateFrame("Cooldown", "LoadoutActionCooldown" .. index, b,
        "CooldownFrameTemplate")
    cd:SetAllPoints(icon)
    if cd.SetDrawEdge then cd:SetDrawEdge(false) end
    b.cooldown = cd

    local count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMRIGHT", -2, 2)
    b.count = count

    local empty = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    empty:SetPoint("CENTER")
    empty:SetText("+")
    empty:SetTextColor(0.35, 0.36, 0.40)
    b.emptyMark = empty

    -- Drop something on it
    b:SetScript("OnReceiveDrag", function(self)
        if InCombatLockdown() then
            ns:Print("Can't change the bar while in combat.")
            return
        end
        local action = ActionFromCursor()
        if action then
            ns.cdb.actions[self.actionIndex] = action
            ClearCursor()
            ns:Fire("BAR_UPDATED")
        end
    end)

    -- Left-click is wired to the secure attributes; this only handles the
    -- non-secure extras (dropping, and the right-click menu).
    b:SetScript("PreClick", function(self, click)
        if click == "LeftButton" and GetCursorInfo() and not InCombatLockdown() then
            local action = ActionFromCursor()
            if action then
                ns.cdb.actions[self.actionIndex] = action
                ClearCursor()
                ns:Fire("BAR_UPDATED")
            end
        end
    end)

    b:SetScript("PostClick", function(self, click)
        if click ~= "RightButton" then return end
        local action = ns.cdb.actions[self.actionIndex]
        ns.Menu:Open(self, {
            { text = "ACTION SLOT " .. self.actionIndex, header = true },
            { text = action and ("Clear: " .. action.name) or "Empty — drag something here",
              danger = action and true or nil,
              func = function()
                  if InCombatLockdown() then
                      ns:Print("Can't change the bar while in combat.")
                      return
                  end
                  ns.cdb.actions[self.actionIndex] = nil
                  ns:Fire("BAR_UPDATED")
              end },
            { text = "Bar options", func = function() ns:Fire("TOGGLE_OPTIONS") end },
        })
    end)

    b:SetScript("OnDragStart", function(self)
        -- Alt-drag moves the whole bar; a plain drag lifts the action off,
        -- the same way Blizzard's action bars behave.
        if IsAltKeyDown() then
            if ns.db.locked then return end
            local bar = self:GetParent()
            bar:StartMoving()
            bar.isMoving = true
            return
        end
        if InCombatLockdown() then return end
        local action = ns.cdb.actions[self.actionIndex]
        if not action then return end
        PickupAction(action)
        ns.cdb.actions[self.actionIndex] = nil
        ns:Fire("BAR_UPDATED")
    end)

    b:SetScript("OnDragStop", function(self)
        local bar = self:GetParent()
        if not bar.isMoving then return end
        bar:StopMovingOrSizing()
        bar.isMoving = nil
        bar:SavePosition()
    end)

    b:SetScript("OnEnter", function(self)
        local action = ns.cdb.actions[self.actionIndex]
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not action then
            GameTooltip:AddLine("Empty action slot", 1, 1, 1)
            GameTooltip:AddLine("Drag a spell, macro or item here from your spellbook, macro list or bags.",
                0.76, 0.79, 0.84, true)
        elseif action.type == "spell" then
            local shown = false
            if action.spellID and GameTooltip.SetSpellByID then
                shown = pcall(GameTooltip.SetSpellByID, GameTooltip, action.spellID)
            end
            if not shown then
                GameTooltip:AddLine(SpellAttribute(action), 1, 1, 1)
                GameTooltip:AddLine("Spell", 0.7, 0.7, 0.75)
            end
        elseif action.type == "item" then
            local shown = false
            if GameTooltip.SetItemByID then
                shown = pcall(GameTooltip.SetItemByID, GameTooltip, action.itemID)
            end
            if not shown then
                GameTooltip:AddLine(action.name or "Item", 1, 1, 1)
            end
        elseif action.type == "macro" then
            GameTooltip:AddLine(action.name, 1, 1, 1)
            GameTooltip:AddLine("Macro", 0.7, 0.7, 0.75)
        end
        if action then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Drag off to remove  ·  Alt-drag moves the bar", 0.5, 0.5, 0.55)
        end
        GameTooltip:Show()
    end)

    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return b
end

-- Push the stored action into the secure attributes. Protected: out of
-- combat only.
local function ApplyAction(b, action)
    b:SetAttribute("type1", nil)
    b:SetAttribute("spell", nil)
    b:SetAttribute("item",  nil)
    b:SetAttribute("macro", nil)

    if not action then
        b.icon:SetTexture(nil)
        b.emptyMark:Show()
        b.count:SetText("")
        return
    end

    b.emptyMark:Hide()
    b.icon:SetTexture(action.icon or "Interface\\Icons\\INV_Misc_QuestionMark")

    if action.type == "spell" then
        b:SetAttribute("type1", "spell")
        b:SetAttribute("spell", SpellAttribute(action))
    elseif action.type == "item" then
        b:SetAttribute("type1", "item")
        b:SetAttribute("item", "item:" .. action.itemID)
    elseif action.type == "macro" then
        b:SetAttribute("type1", "macro")
        b:SetAttribute("macro", action.name)
    end
end

-- Cooldown swipe, stack count, usability tint. All safe in combat.
local function UpdateActionState(b)
    local action = ns.cdb.actions[b.actionIndex]
    if not action then
        b.cooldown:Hide()
        b.count:SetText("")
        return
    end

    local start, duration, enable
    if action.type == "spell" then
        start, duration, enable = GetSpellCooldown(SpellAttribute(action))
    elseif action.type == "item" then
        start, duration, enable = GetItemCooldown(action.itemID)
        local n = GetItemCount(action.itemID)
        b.count:SetText((n and n > 1) and n or "")
        b.icon:SetDesaturated((n or 0) == 0)
    end

    if start and duration and duration > 0 and (enable == nil or enable == 1) then
        b.cooldown:Show()
        b.cooldown:SetCooldown(start, duration)
    else
        b.cooldown:Hide()
    end

    if action.type == "spell" then
        local usable, noMana = IsUsableSpell(SpellAttribute(action))
        if noMana then
            b.icon:SetVertexColor(0.4, 0.4, 0.95)
        elseif not usable then
            b.icon:SetVertexColor(0.45, 0.45, 0.45)
        else
            b.icon:SetVertexColor(1, 1, 1)
        end
    end
end

-- =========================================================================
--  Bar
-- =========================================================================
local function Build()
    if Bar then return Bar end

    local f = CreateFrame("Frame", "LoadoutSetBar", UIParent)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("MEDIUM")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:Hide()

    f.bg = Skin:Fill(f, Skin.colors.bg)
    f.borderTex = Skin:Border(f)
    f.buttons = {}
    f.actions = {}

    Skin:MakePersistent(f, "bar", "CENTER", 0, -180)
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

    f:SetScript("OnMouseUp", function(self, click)
        if click ~= "RightButton" then return end
        ns.Menu:Open(self, {
            { text = "BAR", header = true },
            { text = ns.db.bar.vertical and "Lay out horizontally" or "Lay out vertically",
              func = function()
                  ns.db.bar.vertical = not ns.db.bar.vertical
                  ns:Fire("BAR_UPDATED")
              end },
            { text = ns.db.bar.labels and "Hide names" or "Show names",
              func = function()
                  ns.db.bar.labels = not ns.db.bar.labels
                  ns:Fire("BAR_UPDATED")
              end },
            { text = ns.db.locked and "Unlock frames" or "Lock frames",
              func = function()
                  ns.db.locked = not ns.db.locked
                  ns:Fire("BAR_UPDATED")
              end },
            { text = "Options", func = function() ns:Fire("TOGGLE_OPTIONS") end },
            { text = "Hide bar", danger = true, func = function()
                  ns.db.bar.show = false
                  ns:Fire("BAR_UPDATED")
              end },
        })
    end)

    local grip = f:CreateTexture(nil, "OVERLAY")
    grip:SetPoint("TOPLEFT", 1, -1)
    grip:SetPoint("TOPRIGHT", -1, -1)
    grip:SetHeight(2)
    grip:SetColorTexture(Skin:Accent())
    grip:SetAlpha(0.7)
    f.grip = grip

    local empty = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    empty:SetPoint("CENTER")
    empty:SetText("No sets yet")
    empty:SetTextColor(unpack(Skin.colors.textDim))
    f.emptyText = empty

    -- ------------------------------------------------------------ layout --
    function f:Refresh()
        -- Action buttons are secure frames: their attributes, size, position
        -- and visibility are all protected while you are in combat. Defer.
        if InCombatLockdown() then
            self.pendingRefresh = true
            self:RefreshSetVisuals()
            self:UpdateActionStates()
            return
        end
        self.pendingRefresh = nil

        local cfg   = ns.db.bar
        local order = Sets:GetOrder()
        local size  = cfg.size or 32
        local gap   = cfg.spacing or 3
        local nAct  = cfg.actions or 0
        local total = #order + nAct
        local wrap  = (cfg.wrap and cfg.wrap > 0) and cfg.wrap or math.max(total, 1)
        if wrap < 1 then wrap = 1 end

        -- Position helper: index is 0-based across the whole bar.
        local singleLine = (cfg.wrap or 0) == 0
        local function Place(button, index, isAction)
            local line = math.floor(index / wrap)
            local pos  = index % wrap
            local bump = (singleLine and isAction and #order > 0) and GROUP_GAP or 0
            local along = PAD + pos * (size + gap) + bump
            local down  = PAD + line * (size + gap)
            button:ClearAllPoints()
            if cfg.vertical then
                button:SetPoint("TOPLEFT", self, "TOPLEFT", down, -along)
            else
                button:SetPoint("TOPLEFT", self, "TOPLEFT", along, -down)
            end
        end

        -- set icons
        for i = 1, math.max(#order, #self.buttons) do
            local b = self.buttons[i]
            if i <= #order then
                if not b then
                    b = CreateSetButton(self, i)
                    self.buttons[i] = b
                end
                b.setName = order[i]
                b:SetSize(size, size)
                Place(b, i - 1, false)
                b:Show()
            elseif b then
                b.setName = nil
                b:Hide()
            end
        end

        -- action slots
        for i = 1, math.max(nAct, #self.actions) do
            local b = self.actions[i]
            if i <= nAct then
                if not b then
                    b = CreateActionButton(self, i)
                    self.actions[i] = b
                end
                b:SetSize(size, size)
                b.count:SetPoint("BOTTOMRIGHT", -2, 2)
                Place(b, #order + i - 1, true)
                ApplyAction(b, ns.cdb.actions[i])
                b:Show()
            elseif b then
                b:Hide()
            end
        end

        self:RefreshSetVisuals()
        self:UpdateActionStates()

        -- frame size
        if total == 0 then
            self:SetSize(96, 28)
            self.emptyText:Show()
        else
            self.emptyText:Hide()
            local across = math.min(total, wrap)
            local lines  = math.ceil(total / wrap)
            local bump   = (singleLine and nAct > 0 and #order > 0) and GROUP_GAP or 0
            local a = PAD * 2 + across * size + (across - 1) * gap + bump
            local b = PAD * 2 + lines  * size + (lines  - 1) * gap
            if cfg.vertical then
                self:SetSize(b, a)
            else
                self:SetSize(a, b)
            end
        end

        for _, tex in ipairs(self.borderTex) do
            tex:SetAlpha(ns.db.bar.backdrop and 1 or 0)
        end
        self.bg:SetAlpha(ns.db.bar.backdrop and 1 or 0)
        self.grip:SetShown(not ns.db.locked)
    end

    -- Safe in combat: only touches colours and text on non-secure children.
    function f:RefreshSetVisuals()
        local cfg = ns.db.bar
        for _, b in ipairs(self.buttons) do
            if b.setName and b:IsShown() then
                local set = Sets:Get(b.setName)
                if set then
                    b.icon:SetTexture(set.icon or "Interface\\Icons\\INV_Misc_Bag_08")
                    local worn = Sets:IsEquipped(b.setName)
                    b.glow:SetShown(worn)
                    for _, tex in ipairs(b.borderTex) do
                        if worn then
                            tex:SetColorTexture(Skin:Accent())
                        elseif ns.cdb.activeRule == b.setName then
                            tex:SetColorTexture(0.85, 0.72, 0.25, 1)
                        else
                            tex:SetColorTexture(0.22, 0.23, 0.26, 1)
                        end
                    end
                    if cfg.labels then
                        b.label:SetText(Util:Truncate(b.setName, 8))
                        b.label:Show()
                    else
                        b.label:Hide()
                    end
                end
            end
        end
    end

    function f:UpdateActionStates()
        for _, b in ipairs(self.actions) do
            if b:IsShown() then UpdateActionState(b) end
        end
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
    if not ns.db.bar.show then
        if Bar and not InCombatLockdown() then Bar:Hide() end
        return
    end
    local f = Build()
    f:Show()
    f:Refresh()
end

local function Visuals()
    if Bar and Bar:IsShown() then
        Bar:RefreshSetVisuals()
        Bar:UpdateActionStates()
    end
end

ns:Listen("PLAYER_READY",    Update)
ns:Listen("BAR_UPDATED",     Update)
ns:Listen("SETS_CHANGED",    Update)
ns:Listen("SET_EQUIPPED",    Visuals)
ns:Listen("EQUIP_FINISHED",  Visuals)
ns:Listen("RULES_APPLIED",   Visuals)
ns:Listen("RESET_POSITIONS", function() if Bar then Bar:RestorePosition() end end)

ns:On("PLAYER_EQUIPMENT_CHANGED", Visuals)
ns:On("SPELL_UPDATE_COOLDOWN",    Visuals)
ns:On("SPELL_UPDATE_USABLE",      Visuals)
ns:On("BAG_UPDATE_COOLDOWN",      Visuals)
ns:On("BAG_UPDATE_DELAYED",       Visuals)

-- Anything deferred because of combat gets applied the moment it ends.
ns:On("PLAYER_REGEN_ENABLED", function()
    if Bar and Bar.pendingRefresh then Bar:Refresh() end
end)

ns.ToggleSetBar = function()
    ns.db.bar.show = not ns.db.bar.show
    Update()
end
