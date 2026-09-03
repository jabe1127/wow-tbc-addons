local ADDON, ns = ...
local Skin, Sets, Rules = ns.Skin, ns.Sets, ns.Rules

local Opt
local SelectTab

-- =========================================================================
--  Small helpers
-- =========================================================================
local function SectionLabel(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    fs:SetTextColor(Skin:Accent())
    return fs
end

-- Plain-English explanation attached to any control.
local function Tip(widget, title, body, extra)
    if not widget then return end
    widget.tipTitle = title
    widget.tipBody  = body
    widget.tipExtra = extra
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.tipTitle, 1, 1, 1)
        GameTooltip:AddLine(self.tipBody, 0.76, 0.79, 0.84, true)
        if self.tipExtra then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(self.tipExtra, 0.55, 0.78, 0.55, true)
        end
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function BindCheck(check, key, onChange)
    check:SetChecked(ns.db[key])
    check:SetScript("OnShow", function(self) self:SetChecked(ns.db[key]) end)
    check:SetScript("OnClick", function(self)
        ns.db[key] = self:GetChecked() and true or false
        if onChange then onChange(ns.db[key]) end
    end)
end

-- A button that opens ns.Menu with a list of choices.
local function ChoiceButton(parent, width, getText, buildEntries)
    local b = Skin:Button(parent, "", width, 20)
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", 6, 0)
    b.text:SetPoint("RIGHT", -14, 0)
    b.text:SetJustifyH("LEFT")

    local arrow = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrow:SetPoint("RIGHT", -5, 0)
    arrow:SetText("▾")
    arrow:SetTextColor(unpack(Skin.colors.textDim))

    b.Update = function(self) self.text:SetText(getText() or "—") end
    b:SetScript("OnClick", function(self) ns.Menu:Open(self, buildEntries(self)) end)
    b:Update()
    return b
end

local editCount = 0
local function EditBox(parent, width)
    editCount = editCount + 1
    local e = CreateFrame("EditBox", "LoadoutEditBox" .. editCount, parent, "InputBoxTemplate")
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    e:SetFontObject("GameFontHighlightSmall")
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return e
end

-- =========================================================================
--  Rules editor
-- =========================================================================
local RULE_ROW_H = 27
local RULE_MAXROWS = 18
local RULE_TOP = 46

local function ConditionEntries(onPick)
    local entries = {}
    for _, group in ipairs(Rules.groups) do
        table.insert(entries, { text = group:upper(), header = true })
        for _, c in ipairs(Rules.conditions) do
            if (c.group or "Other") == group then
                table.insert(entries, { text = c.label, func = function() onPick(c) end })
            end
        end
    end
    return entries
end

-- The picker offers whatever suits the condition: bosses for targeting
-- rules, live auras for buff rules, the current zone for zone rules.
local function ParamEntries(conditionID, onPick)
    local entries = {}

    if conditionID == "aura_player" then
        entries[1] = { text = "YOUR BUFFS", header = true }
        for _, name in ipairs(ns.Holds:CurrentAuras()) do
            table.insert(entries, { text = name, func = function() onPick(name) end })
        end
        if #entries == 1 then
            entries[2] = { text = "No buffs on you", func = function() end }
        end
        return entries

    elseif conditionID == "aura_target" then
        entries[1] = { text = "ON YOUR TARGET", header = true }
        local seen = {}
        for _, fn in ipairs({ UnitDebuff, UnitBuff }) do
            for i = 1, 40 do
                local name = fn("target", i)
                if not name then break end
                if not seen[name] then
                    seen[name] = true
                    table.insert(entries, { text = name, func = function() onPick(name) end })
                end
            end
        end
        if #entries == 1 then
            entries[2] = { text = "Nothing on your target", func = function() end }
        end
        return entries

    elseif conditionID == "zone" then
        entries[1] = { text = "WHERE YOU ARE", header = true }
        local zone, sub = GetRealZoneText(), GetSubZoneText()
        if zone and zone ~= "" then
            table.insert(entries, { text = zone, func = function() onPick(zone) end })
        end
        if sub and sub ~= "" and sub ~= zone then
            table.insert(entries, { text = sub, func = function() onPick(sub) end })
        end
        table.insert(entries, { text = "RAIDS", header = true })
        for _, raid in ipairs(Rules.bosses) do
            table.insert(entries, { text = raid.zone, func = function() onPick(raid.zone) end })
        end
        return entries
    end

    if UnitExists("target") then
        table.insert(entries, { text = "Use target: " .. UnitName("target"),
            func = function() onPick(UnitName("target")) end })
    end
    for _, raid in ipairs(Rules.bosses) do
        table.insert(entries, { text = raid.zone:upper(), header = true })
        for _, boss in ipairs(raid.list) do
            table.insert(entries, { text = boss, func = function() onPick(boss) end })
        end
    end
    return entries
end

local function BuildRulesPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    panel.rows = {}
    panel.offset = 0

    local intro = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    intro:SetPoint("TOPLEFT", 12, -10)
    intro:SetPoint("TOPRIGHT", -12, -10)
    intro:SetJustifyH("LEFT")
    intro:SetSpacing(2)
    intro:SetText("Checked top to bottom — the first match wins. When nothing matches, "
        .. "the gear you had before the first rule fired comes back.")
    intro:SetTextColor(unpack(Skin.colors.textDim))
    intro:SetHeight(28)

    panel.visible = 9

    for i = 1, RULE_MAXROWS do
        local r = CreateFrame("Frame", nil, panel)
        r:SetHeight(RULE_ROW_H - 3)
        r:SetPoint("TOPLEFT", 12, -(RULE_TOP + (i - 1) * RULE_ROW_H))
        r:SetPoint("TOPRIGHT", -12, -(RULE_TOP + (i - 1) * RULE_ROW_H))
        r.bg = Skin:Fill(r, Skin.colors.row)

        local function rule() return r.index and ns.cdb.rules[r.index] or nil end

        local enable = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
        enable:SetSize(20, 20)
        enable:SetPoint("LEFT", 2, 0)
        enable:SetScript("OnClick", function()
            if r.index then Rules:Toggle(r.index) end
        end)
        Tip(enable, "Rule on/off",
            "Unticking parks a rule without deleting it. Handy for turning a boss rule off for one night without rebuilding it later.")
        r.enable = enable

        -- is / not toggle
        local neg = Skin:Button(r, "is", 30, 20)
        neg:SetPoint("LEFT", enable, "RIGHT", 3, 0)
        neg.Update = function(self)
            local ru = rule()
            local on = ru and ru.negate
            self.text:SetText(on and "not" or "is")
            if on then
                self.text:SetTextColor(1, 0.72, 0.3)
            else
                self.text:SetTextColor(unpack(Skin.colors.textDim))
            end
        end
        neg:SetScript("OnClick", function(self)
            local ru = rule()
            if ru then
                ru.negate = (not ru.negate) or nil
                self:Update()
                ns:Fire("RULES_CHANGED")
                Rules:Evaluate()
            end
        end)
        Tip(neg, "is / not",
            "Flips the condition around. Set it to 'not' and the rule fires whenever the "
            .. "situation is NOT true — 'not mounted', 'not in combat', 'no target'.",
            "A 'not' rule is true most of the time, so keep it near the bottom of the list where more specific rules can win first.")
        r.neg = neg

        local cond = ChoiceButton(r, 126,
            function()
                local ru = rule()
                return ru and Rules:ConditionLabel(ru.condition) or "—"
            end,
            function()
                return ConditionEntries(function(c)
                    local ru = rule()
                    if ru then
                        ru.condition = c.id
                        if not c.needsParam then ru.param = nil end
                        ns:Fire("RULES_CHANGED")
                        Rules:Evaluate()
                    end
                end)
            end)
        cond:SetPoint("LEFT", neg, "RIGHT", 3, 0)
        Tip(cond, "When this happens…",
            "The situation that triggers this rule. Pick things like being mounted, being in a raid, or having a particular boss targeted. Rules are checked from the top down and the first one that matches wins, so put the most specific ones highest.")
        r.cond = cond

        -- free-text parameter (boss name, zone name)
        local param = EditBox(r, 118)
        param:SetPoint("LEFT", cond, "RIGHT", 8, 0)
        param:SetScript("OnEnterPressed", function(self)
            local ru = rule()
            if ru then
                ru.param = self:GetText()
                ns:Fire("RULES_CHANGED")
                Rules:Evaluate()
            end
            self:ClearFocus()
        end)
        param:SetScript("OnEditFocusLost", function(self)
            local ru = rule()
            if ru then
                ru.param = self:GetText()
                Rules:Evaluate()
            end
        end)
        Tip(param, "Name to match",
            "The boss, mob, or zone name this rule looks for. Type it exactly as it appears in game, or use the button beside this box to pick from a list.")
        r.param = param

        -- boss / target picker for the parameter
        local pick = Skin:Button(r, "…", 20, 20)
        pick:SetPoint("LEFT", param, "RIGHT", 2, 0)
        pick.tooltipText = "Pick a value for this condition"
        pick.tooltipExtra = "Offers whatever fits: raid bosses and your current target for targeting rules, live auras for buff rules, your current zone for zone rules."
        pick:SetScript("OnClick", function(self)
            local ru = rule()
            ns.Menu:Open(self, ParamEntries(ru and ru.condition, function(name)
                local ru = rule()
                if ru then
                    ru.param = name
                    ns:Fire("RULES_CHANGED")
                    Rules:Evaluate()
                end
            end))
        end)
        r.pick = pick

        local arrow = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        arrow:SetPoint("LEFT", pick, "RIGHT", 6, 0)
        arrow:SetText("→")
        arrow:SetTextColor(unpack(Skin.colors.textDim))
        r.arrow = arrow

        local setBtn = ChoiceButton(r, 118,
            function()
                local ru = rule()
                return ru and ru.set or "(pick a set)"
            end,
            function()
                local entries = {}
                for _, name in ipairs(Sets:GetOrder()) do
                    table.insert(entries, { text = name, func = function()
                        local ru = rule()
                        if ru then
                            ru.set = name
                            ns:Fire("RULES_CHANGED")
                            Rules:Evaluate()
                        end
                    end })
                end
                if #entries == 0 then
                    entries[1] = { text = "No sets saved", func = function() end }
                end
                return entries
            end)
        setBtn:SetPoint("LEFT", arrow, "RIGHT", 6, 0)
        Tip(setBtn, "…equip this set",
            "The gear set that gets put on when the condition above is true. Only sets you have already saved show up here.")
        r.setBtn = setBtn

        local del = Skin:Button(r, "×", 20, 20)
        del:SetPoint("RIGHT", -2, 0)
        del.text:SetTextColor(1, 0.45, 0.45)
        del.tooltipText = "Delete this rule"
        del:SetScript("OnClick", function()
            if r.index then Rules:Remove(r.index) end
        end)

        local down = Skin:Button(r, "▼", 20, 20)
        down:SetPoint("RIGHT", del, "LEFT", -2, 0)
        down.tooltipText = "Move down"
        down.tooltipExtra = "Lower rules only fire when nothing above them matches."
        down:SetScript("OnClick", function()
            if r.index then Rules:Move(r.index, 1) end
        end)

        local up = Skin:Button(r, "▲", 20, 20)
        up:SetPoint("RIGHT", down, "LEFT", -2, 0)
        up.tooltipText = "Move up"
        up.tooltipExtra = "Higher rules win over lower ones."
        up:SetScript("OnClick", function()
            if r.index then Rules:Move(r.index, -1) end
        end)

        panel.rows[i] = r
    end

    local add = Skin:AccentButton(panel, "Add rule", 100, 22)
    add:SetPoint("TOPLEFT", 12, -(RULE_TOP + panel.visible * RULE_ROW_H + 10))
    add.tooltipText = "Add a blank rule"
    add.tooltipExtra = "Creates a new row you can then point at any condition and set."
    panel.addButton = add
    add:SetScript("OnClick", function()
        Rules:Add("mounted", Sets:GetOrder()[1])
        panel.offset = math.max(0, #ns.cdb.rules - panel.visible)
        panel:Refresh()
    end)

    local addNot = Skin:Button(panel, "Add 'not mounted' rule", 160, 22)
    addNot:SetPoint("LEFT", add, "RIGHT", 8, 0)
    addNot.tooltipText = "Add a rule that fires whenever you are not mounted"
    addNot.tooltipExtra = "Point it at your normal set. Keep it at the bottom of the list."
    addNot:SetScript("OnClick", function()
        Rules:Add("mounted", Sets:GetOrder()[1], nil, true)
        panel.offset = math.max(0, #ns.cdb.rules - panel.visible)
        panel:Refresh()
    end)

    local addBoss = Skin:Button(panel, "Add rule from target", 150, 22)
    addBoss:SetPoint("LEFT", addNot, "RIGHT", 8, 0)
    addBoss.tooltipText = "Creates a 'target is named X' rule from your current target."
    addBoss:SetScript("OnClick", function()
        Rules:AddFromTarget(Sets:GetOrder()[1])
        panel.offset = math.max(0, #ns.cdb.rules - panel.visible)
        panel:Refresh()
    end)

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", add, "BOTTOMLEFT", 0, -8)
    hint:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("Boss sets: target the boss, hit 'Add rule from target', then point the rule at a set.")
    hint:SetTextColor(unpack(Skin.colors.textDim))

    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(self, delta)
        local total = #ns.cdb.rules
        self.offset = math.max(0, math.min(math.max(0, total - self.visible), self.offset - delta))
        self:Refresh()
    end)

    -- How many rows actually fit at the window's current height.
    function panel:Layout()
        local h = self:GetHeight() or 400
        local fits = math.floor((h - RULE_TOP - 72) / RULE_ROW_H)
        self.visible = math.max(3, math.min(RULE_MAXROWS, fits))
        self.addButton:SetPoint("TOPLEFT", 12, -(RULE_TOP + self.visible * RULE_ROW_H + 10))
    end

    panel:SetScript("OnSizeChanged", function(self)
        self:Layout()
        self:Refresh()
    end)

    function panel:Refresh()
        local rules = ns.cdb.rules
        for i = 1, RULE_MAXROWS do
            local r = self.rows[i]
            local index = i + self.offset
            local ru = (i <= self.visible) and rules[index] or nil
            if ru then
                r.index = index
                r.enable:SetChecked(ru.enabled)
                r.neg:Update()
                r.cond:Update()
                r.setBtn:Update()

                local needs = Rules:NeedsParam(ru.condition)
                r.param:SetShown(needs and true or false)
                r.pick:SetShown(needs and true or false)
                if needs then
                    if not r.param:HasFocus() then r.param:SetText(ru.param or "") end
                    r.arrow:ClearAllPoints()
                    r.arrow:SetPoint("LEFT", r.pick, "RIGHT", 6, 0)
                else
                    r.arrow:ClearAllPoints()
                    r.arrow:SetPoint("LEFT", r.cond, "RIGHT", 8, 0)
                end

                local active = ru.enabled and ns.cdb.activeRule == ru.set
                r.bg:SetColorTexture(unpack(active and Skin.colors.rowHover or Skin.colors.row))
                r:Show()
            else
                r.index = nil
                r:Hide()
            end
        end
    end

    panel:SetScript("OnShow", function(self) self:Layout() self:Refresh() end)
    ns:Listen("RULES_CHANGED", function() if panel:IsVisible() then panel:Refresh() end end)
    ns:Listen("RULES_APPLIED", function() if panel:IsVisible() then panel:Refresh() end end)
    ns:Listen("SETS_CHANGED",  function() if panel:IsVisible() then panel:Refresh() end end)

    return panel
end

-- =========================================================================
--  General panel
-- =========================================================================
local function BuildGeneralPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)

    local COL2 = 300

    SectionLabel(panel, "HOVER SWAPPING", 14, -12)

    local c1 = Skin:Check(panel, "Flyouts from the Loadout window")
    c1:SetPoint("TOPLEFT", 12, -28)
    BindCheck(c1, "hoverFromMain")
    Tip(c1, "Flyouts from the Loadout window",
        "When you point at a gear slot in Loadout's own window, a small panel pops out showing every item in your bags that fits that slot. Click one to put it on. Turn this off if you only want the pop-out on Blizzard's character sheet.")

    local c2 = Skin:Check(panel, "Flyouts from the character sheet")
    c2:SetPoint("TOPLEFT", 12, -52)
    BindCheck(c2, "hoverFromPaper")
    Tip(c2, "Flyouts from the character sheet",
        "Same pop-out, but on Blizzard's own character panel (the one you open with C). Point at your helm and every other helm in your bags appears next to it.")

    local cols = Skin:Slider(panel, "Flyout columns: " .. (ns.db.flyoutColumns or 6), 3, 12, 1)
    cols:SetPoint("TOPLEFT", 22, -92)
    cols:SetValue(ns.db.flyoutColumns or 6)
    Tip(cols, "Flyout columns",
        "How many items sit side by side in the hover pop-out before it starts a new row. Lower numbers make a tall narrow panel, higher numbers a short wide one.")
    cols:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v + 0.5)
        ns.db.flyoutColumns = v
        self:SetLabel("Flyout columns: " .. v)
    end)

    local size = Skin:Slider(panel, "Flyout icon size: " .. (ns.db.flyoutSize or 34), 22, 48, 1)
    size:SetPoint("TOPLEFT", 22, -136)
    size:SetValue(ns.db.flyoutSize or 34)
    Tip(size, "Flyout icon size",
        "How large the item icons are inside the hover pop-out, in pixels.")
    size:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v + 0.5)
        ns.db.flyoutSize = v
        self:SetLabel("Flyout icon size: " .. v)
    end)

    -- -------------------------------------------------------- queues ----
    SectionLabel(panel, "SLOT QUEUES", COL2, -140)

    local q1 = Skin:Check(panel, "Let slot queues swap on their own")
    q1:SetPoint("TOPLEFT", COL2 - 2, -158)
    BindCheck(q1, "queuesEnabled")
    Tip(q1, "Let slot queues swap on their own",
        "A queue is a ranked list of items for one slot. Whichever is highest in the list and off cooldown is the one you wear. Point at a slot on the gear bar or gear window and shift-right-click to build one.",
        "Two on-use trinkets: fire the first, and the second takes over the moment the first goes on cooldown.")

    local q2 = Skin:Check(panel, "...including during a fight")
    q2:SetPoint("TOPLEFT", COL2 - 2, -182)
    BindCheck(q2, "queuesInCombat")
    Tip(q2, "...including during a fight",
        "Mid-fight is usually the whole point for trinkets. Weapons are never swapped automatically in combat regardless, since that resets your swing timer.")

    -- ---------------------------------------------------------- ammo ----
    SectionLabel(panel, "AMMUNITION", COL2, -12)

    local ammoHint = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ammoHint:SetPoint("TOPLEFT", COL2, -28)
    ammoHint:SetWidth(250)
    ammoHint:SetJustifyH("LEFT")
    ammoHint:SetJustifyV("TOP")
    ammoHint:SetSpacing(2)
    ammoHint:SetText("Sets do not touch your ammo slot. It is only ever filled when it is empty.")
    ammoHint:SetTextColor(unpack(Skin.colors.textDim))
    ammoHint:SetHeight(28)

    local am2 = Skin:Check(panel, "Load ammunition when the slot runs empty")
    am2:SetPoint("TOPLEFT", COL2 - 2, -60)
    BindCheck(am2, "autoAmmoRefill")
    Tip(am2, "Load ammunition when the slot runs empty",
        "When you shoot your last arrow or bullet, the hardest-hitting stack in your bags that your weapon can fire is loaded for you. It only acts on an empty slot, so anything you load yourself stays put.",
        "Never runs while a vendor, bank, mailbox or trade window is in play.")

    local ammoNow = Skin:Button(panel, "Load best now", 130, 20)
    ammoNow:SetPoint("TOPLEFT", COL2 - 2, -88)
    ammoNow.tooltipText = "Load the highest-dps ammunition you are carrying"
    ammoNow.tooltipExtra = "Replaces what is loaded. Same as /lo ammo."
    ammoNow:SetScript("OnClick", function() ns.Ammo:EquipBest(false, true) end)

    SectionLabel(panel, "AUTOMATIC SWAPPING", 14, -180)

    local a1 = Skin:Check(panel, "Enable rules")
    a1:SetPoint("TOPLEFT", 12, -196)
    BindCheck(a1, "autoSwap", function() Rules:Evaluate() end)
    Tip(a1, "Enable rules",
        "The master switch for automatic gear changes. With this off, Loadout never swaps anything on its own and every rule you have written is ignored. Sets you click on still equip normally.")

    local a2 = Skin:Check(panel, "Allow swaps while in combat")
    a2:SetPoint("TOPLEFT", 12, -220)
    BindCheck(a2, "autoSwapInCombat")
    Tip(a2, "Allow swaps while in combat",
        "Normally Loadout waits until you are out of combat before a rule fires, so it cannot change your weapon in the middle of a fight and cost you a swing. Turn this on if you want rules to take effect immediately, mid-fight.",
        "Leave off unless you know you want mid-fight swaps.")

    local a3 = Skin:Check(panel, "Keep a rule's gear on until combat ends")
    a3:SetPoint("TOPLEFT", 12, -244)
    a3.label:SetText("Keep a rule's gear on until combat ends")
    BindCheck(a3, "stickyInCombat")
    Tip(a3, "Keep a rule's gear on until combat ends",
        "Once a rule has put a set on you, that set stays on for the rest of the fight even if the rule stops matching. Without this, tabbing off a boss onto an add would immediately strip your boss set back off mid-pull.")

    local a4 = Skin:Check(panel, "Restore previous gear when no rule matches")
    a4:SetPoint("TOPLEFT", 12, -268)
    BindCheck(a4, "restoreOnExit")
    Tip(a4, "Restore previous gear when no rule matches",
        "Loadout photographs what you were wearing just before the first rule fired. When no rule matches any more, it puts that gear back on. Turn this off if you would rather whatever set fired last simply stays on.")

    local a5 = Skin:Check(panel, "A manual change parks the rule until it stops applying")
    a5:SetPoint("TOPLEFT", 12, -292)
    BindCheck(a5, "manualOverride", function() ns.Rules:Resume() end)
    Tip(a5, "A manual change parks the rule until it stops applying",
        "If you swap gear yourself while a rule is holding a set on you, Loadout assumes you meant it and stops interfering. The rule stays parked until its situation genuinely ends — you dismount, leave the raid, drop the target — and then takes over again as normal.",
        "Example: mounted, but you want your PvP trinket on to burn its cooldown. Click it on and it stays on until you dismount.")

    SectionLabel(panel, "INTERFACE", 14, -324)

    local i1 = Skin:Check(panel, "Show the GEAR tab on the character frame")
    i1:SetPoint("TOPLEFT", 12, -340)
    BindCheck(i1, "showCharButton", function(v)
        if CharacterFrame and CharacterFrame.loadoutTab then CharacterFrame.loadoutTab:SetShown(v) end
    end)
    Tip(i1, "Show the GEAR tab on the character frame",
        "Puts a small vertical GEAR tab on the edge of Blizzard's character panel. Clicking it slides out your set list so you can save and equip sets without opening anything else.")

    local i2 = Skin:Check(panel, "Lock frames in place")
    i2:SetPoint("TOPLEFT", 12, -364)
    BindCheck(i2, "locked", function() ns:Fire("BAR_UPDATED") end)
    Tip(i2, "Lock frames in place",
        "Stops Loadout windows and the set bar from being dragged, so you cannot knock them out of position by accident. Unlock before moving anything.")

    local i3 = Skin:Check(panel, "Confirm before deleting a set")
    i3:SetPoint("TOPLEFT", 12, -388)
    BindCheck(i3, "confirmDelete")
    Tip(i3, "Confirm before deleting a set",
        "Pops up an 'are you sure?' box when you delete a gear set. Deleting is permanent, so this is worth keeping on.")

    local i4 = Skin:Check(panel, "Show 'In sets' on item tooltips")
    i4:SetPoint("TOPLEFT", COL2, -340)
    BindCheck(i4, "tooltipSetInfo")
    Tip(i4, "Show 'In sets' on item tooltips",
        "Adds a line to every item tooltip listing which of your gear sets that item belongs to. Handy for knowing what is safe to vendor or disenchant.")

    local i5 = Skin:Check(panel, "Announce set changes in chat")
    i5:SetPoint("TOPLEFT", COL2, -364)
    BindCheck(i5, "announce")
    Tip(i5, "Announce set changes in chat",
        "Prints a line to your chat window whenever a set is equipped or a rule fires. Useful while you are setting rules up and testing them, noisy afterwards.")

    local i6 = Skin:Check(panel, "Play a sound when equipping a set")
    i6:SetPoint("TOPLEFT", COL2, -388)
    BindCheck(i6, "equipSound")
    Tip(i6, "Play a sound when equipping a set",
        "A short bag-rustle noise so you get audible confirmation that a set actually went on.")

    local i7 = Skin:Check(panel, "Show the minimap button")
    Tip(i7, "Show the minimap button",
        "A round Loadout button beside your minimap. Left-click opens the gear window, right-click gives a quick list of your sets to equip, and you can drag it around the minimap's edge.")
    i7:SetPoint("TOPLEFT", COL2, -412)
    i7:SetChecked(not ns.db.minimap.hide)
    i7:SetScript("OnShow", function(self) self:SetChecked(not ns.db.minimap.hide) end)
    i7:SetScript("OnClick", function(self)
        ns.db.minimap.hide = not self:GetChecked()
        if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
    end)

    local scale = Skin:Slider(panel, "Window scale: " .. string.format("%.2f", ns.db.scale or 1), 0.6, 1.6, 0.05)
    scale:SetPoint("TOPLEFT", 22, -428)
    scale:SetValue(ns.db.scale or 1)
    Tip(scale, "Window scale",
        "Shrinks or enlarges the main Loadout window. Below 1.00 it gets smaller, above 1.00 bigger. Use this if the window feels oversized on your resolution.")
    scale:SetScript("OnValueChanged", function(self, v)
        ns.db.scale = v
        self:SetLabel("Window scale: " .. string.format("%.2f", v))
        local m = ns.GetMainFrame and ns.GetMainFrame()
        if m then m:SetScale(v) end
    end)

    return panel
end

-- =========================================================================
--  Keys panel
-- =========================================================================
local function BuildKeysPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)

    SectionLabel(panel, "KEY BINDINGS", 14, -12)

    local info = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    info:SetPoint("TOPLEFT", 12, -30)
    info:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
    info:SetJustifyH("LEFT")
    info:SetSpacing(3)
    info:SetText("Bind these under Game Menu → Key Bindings → Addons → Loadout. "
        .. "'Equip set N' follows the order of your set list, so reordering sets reorders the keys too.")
    info:SetTextColor(unpack(Skin.colors.textDim))
    info:SetHeight(40)

    local rows = {}
    local function AddRow(i, label, binding)
        local r = CreateFrame("Frame", nil, panel)
        r:SetHeight(20)
        r:SetPoint("TOPLEFT", 12, -(80 + (i - 1) * 22))
        r:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
        Skin:Fill(r, Skin.colors.row)

        local l = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetPoint("LEFT", 6, 0)
        l:SetText(label)
        l:SetTextColor(unpack(Skin.colors.text))

        local k = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        k:SetPoint("RIGHT", -8, 0)
        r.keyText = k
        r.binding = binding
        rows[#rows + 1] = r
    end

    AddRow(1, "Toggle gear window", "LOADOUT_TOGGLE")
    AddRow(2, "Toggle options",     "LOADOUT_OPTIONS")
    AddRow(3, "Take gear off",      "LOADOUT_UNDRESS")
    for i = 1, 10 do
        AddRow(3 + i, "Equip set " .. i, "LOADOUT_SET" .. i)
    end

    function panel:Refresh()
        local order = Sets:GetOrder()
        for _, r in ipairs(rows) do
            local key = GetBindingKey(r.binding)
            if key then
                r.keyText:SetText(key)
                r.keyText:SetTextColor(Skin:Accent())
            else
                r.keyText:SetText("unbound")
                r.keyText:SetTextColor(unpack(Skin.colors.textDim))
            end
            local n = r.binding:match("^LOADOUT_SET(%d+)$")
            if n then
                local name = order[tonumber(n)]
                if name then
                    r.keyText:SetText((key or "unbound") .. "  |cff8a8a92" .. name .. "|r")
                end
            end
        end
    end

    panel:SetScript("OnShow", function(self) self:Refresh() end)
    ns:Listen("SETS_CHANGED", function() if panel:IsVisible() then panel:Refresh() end end)
    return panel
end

-- =========================================================================
--  Bars panel
-- =========================================================================
local function BuildBarsPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)

    local C1, C2 = 14, 300

    -- ------------------------------------------------------- set bar ----
    SectionLabel(panel, "SET BAR — one icon per gear set", C1, -12)

    local barHint = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    barHint:SetPoint("TOPLEFT", C1, -28)
    barHint:SetWidth(250)
    barHint:SetJustifyH("LEFT")
    barHint:SetSpacing(2)
    barHint:SetText("One clickable icon per set. Drag it anywhere; right-click the bar for quick layout options.")
    barHint:SetTextColor(unpack(Skin.colors.textDim))
    barHint:SetHeight(28)

    local b1 = Skin:Check(panel, "Show the set bar")
    b1:SetPoint("TOPLEFT", C1 - 2, -60)
    b1:SetChecked(ns.db.bar.show)
    b1:SetScript("OnShow", function(self) self:SetChecked(ns.db.bar.show) end)
    Tip(b1, "Show the set bar",
        "A small floating bar with one icon per gear set. Click an icon to equip that set — no keybinds or menus needed. Drag the bar anywhere on your screen.")
    b1:SetScript("OnClick", function(self)
        ns.db.bar.show = self:GetChecked() and true or false
        ns:Fire("BAR_UPDATED")
    end)

    local b2 = Skin:Check(panel, "Lay it out vertically")
    b2:SetPoint("TOPLEFT", C1 - 2, -84)
    b2:SetChecked(ns.db.bar.vertical)
    b2:SetScript("OnShow", function(self) self:SetChecked(ns.db.bar.vertical) end)
    Tip(b2, "Lay it out vertically",
        "Stacks the set icons in a column instead of a row. Useful along the side of your screen rather than across the bottom.")
    b2:SetScript("OnClick", function(self)
        ns.db.bar.vertical = self:GetChecked() and true or false
        ns:Fire("BAR_UPDATED")
    end)

    local b3 = Skin:Check(panel, "Show set names on the icons")
    b3:SetPoint("TOPLEFT", C1 - 2, -108)
    b3:SetChecked(ns.db.bar.labels)
    b3:SetScript("OnShow", function(self) self:SetChecked(ns.db.bar.labels) end)
    Tip(b3, "Show set names on the icons",
        "Prints each set's name across the bottom of its icon. Long names get shortened. Off by default since the icons alone are usually enough.")
    b3:SetScript("OnClick", function(self)
        ns.db.bar.labels = self:GetChecked() and true or false
        ns:Fire("BAR_UPDATED")
    end)

    local b4 = Skin:Check(panel, "Draw a background behind it")
    b4:SetPoint("TOPLEFT", C1 - 2, -132)
    b4:SetChecked(ns.db.bar.backdrop)
    b4:SetScript("OnShow", function(self) self:SetChecked(ns.db.bar.backdrop) end)
    Tip(b4, "Draw a background behind it",
        "Puts a dark panel behind the set icons. Turn it off for bare floating icons with nothing around them.")
    b4:SetScript("OnClick", function(self)
        ns.db.bar.backdrop = self:GetChecked() and true or false
        ns:Fire("BAR_UPDATED")
    end)

    local barSize = Skin:Slider(panel, "Icon size: " .. (ns.db.bar.size or 32), 20, 52, 1)
    barSize:SetPoint("TOPLEFT", C1 + 8, -172)
    barSize:SetValue(ns.db.bar.size or 32)
    Tip(barSize, "Icon size",
        "How big each set icon on the floating bar is, in pixels.")
    barSize:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v + 0.5)
        ns.db.bar.size = v
        self:SetLabel("Icon size: " .. v)
        ns:Fire("BAR_UPDATED")
    end)

    local barActions = Skin:Slider(panel, "Action slots: " .. (ns.db.bar.actions or 0), 0, 12, 1)
    barActions:SetPoint("TOPLEFT", C1 + 8, -216)
    barActions:SetValue(ns.db.bar.actions or 0)
    Tip(barActions, "Action slots",
        "Adds extra squares on the end of the set bar that you can drag spells, macros or items onto, then click like a normal action bar. Good for parking a swap macro, a potion and a trinket right next to your gear icons.",
        "Slots can only be filled or rearranged out of combat.")
    barActions:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v + 0.5)
        ns.db.bar.actions = v
        self:SetLabel("Action slots: " .. v)
        ns:Fire("BAR_UPDATED")
    end)

    local barWrap = Skin:Slider(panel, "Wrap after: " .. ((ns.db.bar.wrap or 0) == 0 and "never" or ns.db.bar.wrap), 0, 12, 1)
    barWrap:SetPoint("TOPLEFT", C1 + 8, -260)
    barWrap:SetValue(ns.db.bar.wrap or 0)
    Tip(barWrap, "Wrap after",
        "Starts a new row (or column) once this many icons have been placed, turning the bar into a grid. Set to 0 to keep every icon on one line.")
    barWrap:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v + 0.5)
        ns.db.bar.wrap = v
        self:SetLabel("Wrap after: " .. (v == 0 and "never" or v))
        ns:Fire("BAR_UPDATED")
    end)


    -- ------------------------------------------------------ gear bar ----
    SectionLabel(panel, "GEAR BAR — one square per equipment slot", C2, -12)

    local gHint = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gHint:SetPoint("TOPLEFT", C2, -28)
    gHint:SetWidth(250)
    gHint:SetJustifyH("LEFT")
    gHint:SetJustifyV("TOP")
    gHint:SetSpacing(2)
    gHint:SetText("A movable line of your equipped items. Hovering a square gives the same pop-out as the character pane.")
    gHint:SetTextColor(unpack(Skin.colors.textDim))
    gHint:SetHeight(28)

    local g1 = Skin:Check(panel, "Show the gear bar")
    g1:SetPoint("TOPLEFT", C2 - 2, -60)
    g1:SetChecked(ns.db.gearbar.show)
    g1:SetScript("OnShow", function(self) self:SetChecked(ns.db.gearbar.show) end)
    g1:SetScript("OnClick", function(self)
        ns.db.gearbar.show = self:GetChecked() and true or false
        ns:Fire("GEARBAR_UPDATED")
    end)
    Tip(g1, "Show the gear bar",
        "A floating row containing one square for every equipment slot. Point at a square and the same list of swappable items appears that you get on the character pane. Right-click a square to take that piece off.")

    local g2 = Skin:Check(panel, "Lay it out vertically")
    g2:SetPoint("TOPLEFT", C2 - 2, -84)
    g2:SetChecked(ns.db.gearbar.vertical)
    g2:SetScript("OnShow", function(self) self:SetChecked(ns.db.gearbar.vertical) end)
    g2:SetScript("OnClick", function(self)
        ns.db.gearbar.vertical = self:GetChecked() and true or false
        ns:Fire("GEARBAR_UPDATED")
    end)
    Tip(g2, "Lay it out vertically",
        "Stacks the slots into a column instead of a row. A horizontal bar drops its item lists downward; a vertical one opens them out to the side.")

    local g3 = Skin:Check(panel, "Hide slots with nothing in them")
    g3:SetPoint("TOPLEFT", C2 - 2, -108)
    g3:SetChecked(ns.db.gearbar.hideEmpty)
    g3:SetScript("OnShow", function(self) self:SetChecked(ns.db.gearbar.hideEmpty) end)
    g3:SetScript("OnClick", function(self)
        ns.db.gearbar.hideEmpty = self:GetChecked() and true or false
        ns:Fire("GEARBAR_UPDATED")
    end)
    Tip(g3, "Hide slots with nothing in them",
        "Leaves out squares for gear you are not wearing, so the bar only shows what you actually have on. Turn it off if you would rather keep the layout the same length at all times.")

    local g4 = Skin:Check(panel, "Include shirt and tabard")
    g4:SetPoint("TOPLEFT", C2 - 2, -132)
    g4:SetChecked(ns.db.gearbar.showCosmetic)
    g4:SetScript("OnShow", function(self) self:SetChecked(ns.db.gearbar.showCosmetic) end)
    g4:SetScript("OnClick", function(self)
        ns.db.gearbar.showCosmetic = self:GetChecked() and true or false
        ns:Fire("GEARBAR_UPDATED")
    end)
    Tip(g4, "Include shirt and tabard",
        "Those two are left out by default since they are cosmetic and never swapped in a fight. Tick this if you want them on the bar anyway.")

    local g5 = Skin:Check(panel, "Draw a background behind it")
    g5:SetPoint("TOPLEFT", C2 - 2, -156)
    g5:SetChecked(ns.db.gearbar.backdrop)
    g5:SetScript("OnShow", function(self) self:SetChecked(ns.db.gearbar.backdrop) end)
    g5:SetScript("OnClick", function(self)
        ns.db.gearbar.backdrop = self:GetChecked() and true or false
        ns:Fire("GEARBAR_UPDATED")
    end)

    local gSize = Skin:Slider(panel, "Slot size: " .. (ns.db.gearbar.size or 32), 20, 52, 1)
    gSize:SetPoint("TOPLEFT", C2 + 8, -196)
    gSize:SetValue(ns.db.gearbar.size or 32)
    Tip(gSize, "Slot size", "How large each equipment square is, in pixels.")
    gSize:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v + 0.5)
        ns.db.gearbar.size = v
        self:SetLabel("Slot size: " .. v)
        ns:Fire("GEARBAR_UPDATED")
    end)

    local gWrap = Skin:Slider(panel, "Wrap after: " .. ((ns.db.gearbar.wrap or 0) == 0 and "never" or ns.db.gearbar.wrap), 0, 12, 1)
    gWrap:SetPoint("TOPLEFT", C2 + 8, -240)
    gWrap:SetValue(ns.db.gearbar.wrap or 0)
    Tip(gWrap, "Wrap after",
        "Breaks the bar into a grid after this many squares. 0 keeps everything on a single line.")
    gWrap:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v + 0.5)
        ns.db.gearbar.wrap = v
        self:SetLabel("Wrap after: " .. (v == 0 and "never" or v))
        ns:Fire("GEARBAR_UPDATED")
    end)

    local lockNote = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lockNote:SetPoint("TOPLEFT", C1, -300)
    lockNote:SetPoint("RIGHT", panel, "RIGHT", -14, 0)
    lockNote:SetJustifyH("LEFT")
    lockNote:SetJustifyV("TOP")
    lockNote:SetSpacing(2)
    lockNote:SetText("Both bars are moved by dragging them and held in place by 'Lock frames in place' "
        .. "on the General tab. While unlocked, each bar shows a thin coloured strip along its top edge. "
        .. "Shift-right-click a gear square for a quick layout menu.")
    lockNote:SetTextColor(unpack(Skin.colors.textDim))

    return panel
end

-- =========================================================================
--  Holds panel
-- =========================================================================
local HOLD_ROW_H = 27
local HOLD_MAXROWS = 16
local HOLD_TOP = 72

local function BuildHoldsPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    panel.rows = {}

    SectionLabel(panel, "DON'T STRIP THESE WHILE THEIR BUFF IS UP", 14, -12)

    local intro = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    intro:SetPoint("TOPLEFT", 14, -30)
    intro:SetPoint("RIGHT", panel, "RIGHT", -14, 0)
    intro:SetJustifyH("LEFT")
    intro:SetJustifyV("TOP")
    intro:SetSpacing(2)
    intro:SetText("Some pieces are worn for a proc or an on-use buff, and taking them off "
        .. "throws that buff away. List one here and any set change will leave that slot "
        .. "alone until the buff drops, then finish the swap by itself.")
    intro:SetTextColor(unpack(Skin.colors.textDim))
    intro:SetHeight(32)

    panel.visible = 8

    for i = 1, HOLD_MAXROWS do
        local r = CreateFrame("Frame", nil, panel)
        r:SetHeight(HOLD_ROW_H - 3)
        r:SetPoint("TOPLEFT", 14, -(HOLD_TOP + (i - 1) * HOLD_ROW_H))
        r:SetPoint("RIGHT", panel, "RIGHT", -14, 0)
        r.bg = Skin:Fill(r, Skin.colors.row)

        local function entry() return r.index and ns.cdb.holds[r.index] or nil end

        local icon = r:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("LEFT", 4, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.icon = icon

        local itemBtn = ChoiceButton(r, 180,
            function()
                local e = entry()
                return e and (e.item or "(pick an item)") or "—"
            end,
            function()
                local entries = { { text = "CURRENTLY WORN", header = true } }
                for _, sl in ipairs(ns.Util.slots) do
                    local eq = ns.Util:GetEquipped(sl.id)
                    if eq then
                        local info = ns.Util:ItemInfo(eq.link)
                        local nm = info and info.name or eq.link
                        table.insert(entries, { text = nm, func = function()
                            local e = entry()
                            if e then
                                e.key  = eq.key
                                e.item = nm
                                e.icon = info and info.texture
                                ns:Fire("HOLDS_CHANGED")
                            end
                        end })
                    end
                end
                if #entries == 1 then
                    entries[2] = { text = "Nothing equipped", func = function() end }
                end
                return entries
            end)
        itemBtn:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        Tip(itemBtn, "The item to protect",
            "Pick from what you are wearing right now. Put the piece on first, then choose it here.")
        r.itemBtn = itemBtn

        local while_ = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        while_:SetPoint("LEFT", itemBtn, "RIGHT", 8, 0)
        while_:SetText("while")
        while_:SetTextColor(unpack(Skin.colors.textDim))

        local aura = EditBox(r, 170)
        aura:SetPoint("LEFT", while_, "RIGHT", 8, 0)
        aura:SetScript("OnEnterPressed", function(self)
            local e = entry()
            if e then e.aura = self:GetText() ns:Fire("HOLDS_CHANGED") end
            self:ClearFocus()
        end)
        aura:SetScript("OnEditFocusLost", function(self)
            local e = entry()
            if e then e.aura = self:GetText() end
        end)
        Tip(aura, "The buff to wait for",
            "Type the buff name exactly as it appears in your buff bar, or use the button beside this box to grab one you have on right now.")
        r.aura = aura

        local pick = Skin:Button(r, "…", 20, 20)
        pick:SetPoint("LEFT", aura, "RIGHT", 2, 0)
        pick.tooltipText = "Pick from your current buffs"
        pick:SetScript("OnClick", function(self)
            local entries = { { text = "YOUR BUFFS", header = true } }
            for _, name in ipairs(ns.Holds:CurrentAuras()) do
                table.insert(entries, { text = name, func = function()
                    local e = entry()
                    if e then
                        e.aura = name
                        ns:Fire("HOLDS_CHANGED")
                    end
                end })
            end
            if #entries == 1 then
                entries[2] = { text = "No buffs on you", func = function() end }
            end
            ns.Menu:Open(self, entries)
        end)

        local del = Skin:Button(r, "×", 20, 20)
        del:SetPoint("RIGHT", -2, 0)
        del.text:SetTextColor(1, 0.45, 0.45)
        del.tooltipText = "Remove this hold"
        del:SetScript("OnClick", function()
            if r.index then ns.Holds:Remove(r.index) end
        end)

        panel.rows[i] = r
    end

    local add = Skin:AccentButton(panel, "Add a hold", 120, 22)
    add:SetPoint("TOPLEFT", 14, -(HOLD_TOP + panel.visible * HOLD_ROW_H + 10))
    panel.addButton = add
    add.tooltipText = "Add a blank row"
    add:SetScript("OnClick", function()
        ns.Holds:Add(nil, nil, "")
    end)

    local status = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    status:SetPoint("TOPLEFT", add, "BOTTOMLEFT", 0, -10)
    status:SetPoint("RIGHT", panel, "RIGHT", -14, 0)
    status:SetJustifyH("LEFT")
    status:SetSpacing(2)
    panel.status = status

    function panel:Layout()
        local h = self:GetHeight() or 400
        local fits = math.floor((h - HOLD_TOP - 80) / HOLD_ROW_H)
        self.visible = math.max(3, math.min(HOLD_MAXROWS, fits))
        self.addButton:SetPoint("TOPLEFT", 14, -(HOLD_TOP + self.visible * HOLD_ROW_H + 10))
    end

    panel:SetScript("OnSizeChanged", function(self)
        self:Layout()
        self:Refresh()
    end)

    function panel:Refresh()
        local holds = ns.cdb.holds
        for i = 1, HOLD_MAXROWS do
            local r = self.rows[i]
            local e = (i <= self.visible) and holds[i] or nil
            if e then
                r.index = i
                r.itemBtn:Update()
                if not r.aura:HasFocus() then r.aura:SetText(e.aura or "") end
                r.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                local active = e.aura and e.aura ~= "" and ns.Holds:HasAura(e.aura)
                r.bg:SetColorTexture(unpack(active and Skin.colors.rowHover or Skin.colors.row))
                r:Show()
            else
                r.index = nil
                r:Hide()
            end
        end

        local waiting = #ns.Equip.holdQueue
        if waiting > 0 then
            self.status:SetText("|cffffcc00" .. waiting
                .. " swap(s) waiting|r for a buff to drop. They will finish on their own.")
        else
            self.status:SetText("")
        end
    end

    panel:SetScript("OnShow", function(self) self:Layout() self:Refresh() end)
    ns:Listen("HOLDS_CHANGED",  function() if panel:IsVisible() then panel:Refresh() end end)
    ns:Listen("EQUIP_FINISHED", function() if panel:IsVisible() then panel:Refresh() end end)
    return panel
end

-- =========================================================================
--  Macros panel
-- =========================================================================
local function BuildMacrosPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)

    SectionLabel(panel, "COMMANDS FOR YOUR OWN MACROS", 14, -12)

    local intro = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    intro:SetPoint("TOPLEFT", 14, -30)
    intro:SetPoint("RIGHT", panel, "RIGHT", -14, 0)
    intro:SetJustifyH("LEFT")
    intro:SetJustifyV("TOP")
    intro:SetSpacing(2)
    intro:SetText("Gear swapping is not a protected action, so these work inside a normal "
        .. "Blizzard macro alongside /cast and /use — including in combat. Short forms "
        .. "exist because macros only get 255 characters.")
    intro:SetTextColor(unpack(Skin.colors.textDim))
    intro:SetHeight(30)

    local rows = {
        { "/le <set>",          "Equip a gear set. Partial names work: /je snap finds \"Snapshot\"." },
        { "/lt <set>",          "Toggle. First press equips the set, next press puts your old gear back." },
        { "/lb",                "Go back to whatever you were wearing before the last set change." },
        { "/la [set]",          "Wait for the cast in progress to land, then swap. Blank means go back." },
        { "/lo item <name>",   "Equip a single item from your bags by name — no set needed." },
        { "/lo item2 <name>",  "Same, but into the second ring, trinket or weapon slot." },
        { "/ld <secs> [set]",   "Swap after a delay in seconds. Blank set means go back." },
        { "/ld cancel",         "Cancel anything currently waiting on a timer." },
        { "/lo off",           "Take all your gear off." },
        { "/lo off armor",     "Strip armour only — weapons, ranged and ammo stay put." },
    }

    for i, row in ipairs(rows) do
        local r = CreateFrame("Frame", nil, panel)
        r:SetHeight(26)
        r:SetPoint("TOPLEFT", 14, -(70 + (i - 1) * 28))
        r:SetPoint("RIGHT", panel, "RIGHT", -14, 0)
        Skin:Fill(r, Skin.colors.row)

        local cmd = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cmd:SetPoint("LEFT", 8, 0)
        cmd:SetWidth(130)
        cmd:SetJustifyH("LEFT")
        cmd:SetText(row[1])
        cmd:SetTextColor(Skin:Accent())

        local desc = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        desc:SetPoint("LEFT", cmd, "RIGHT", 8, 0)
        desc:SetPoint("RIGHT", -8, 0)
        desc:SetJustifyH("LEFT")
        desc:SetText(row[2])
        desc:SetTextColor(unpack(Skin.colors.text))
    end

    SectionLabel(panel, "EXAMPLES", 14, -(70 + #rows * 28 + 12))

    local ex = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ex:SetPoint("TOPLEFT", 14, -(70 + #rows * 28 + 30))
    ex:SetPoint("RIGHT", panel, "RIGHT", -14, 0)
    ex:SetJustifyH("LEFT")
    ex:SetJustifyV("TOP")
    ex:SetSpacing(3)
    ex:SetText(
        "|cff9fe08cSnapshot in healing gear, swapping back only once the cast lands:|r\n"
        .. "   #showtooltip\n"
        .. "   /le Healing\n"
        .. "   /cast Healing Wave\n"
        .. "   /la\n"
        .. "|cff8a8a92   /lb here would strip the gear mid-cast — use /la.|r\n\n"
        .. "|cff9fe08cOne button that swaps a set on and off:|r\n"
        .. "   #showtooltip\n"
        .. "   /lt Threat\n\n"
        .. "|cff9fe08cSwap a single trinket without building a set:|r\n"
        .. "   /lo item Hero Charm\n\n"
        .. "|cff9fe08cSwap in, fire an instant, swap back a moment later:|r\n"
        .. "   #showtooltip\n"
        .. "   /le Burst\n"
        .. "   /cast Death Wish\n"
        .. "   /ld 1.5")
    ex:SetTextColor(unpack(Skin.colors.text))

    -- Anchored under the examples rather than to the panel floor, so it can
    -- never end up printed on top of them.
    local caveat = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    caveat:SetPoint("TOPLEFT", ex, "BOTTOMLEFT", 0, -14)
    caveat:SetPoint("RIGHT", panel, "RIGHT", -14, 0)
    caveat:SetJustifyH("LEFT")
    caveat:SetJustifyV("TOP")
    caveat:SetSpacing(2)
    caveat:SetText("Armour, rings and trinkets swap freely, including mid-cast. Weapons are the "
        .. "exception: the client refuses a weapon swap while you are casting, so those "
        .. "queue up and land the moment the cast ends.\n"
        .. "Delays only work for gear. Blizzard will not let an addon cast a spell off a "
        .. "timer, so there is no way to delay a /cast — only the swap around it.")
    caveat:SetTextColor(unpack(Skin.colors.textDim))

    return panel
end

-- =========================================================================
--  Share panel
-- =========================================================================
local function BuildSharePanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)

    local COLW = 232

    -- ------------------------------------------------- account library ---
    SectionLabel(panel, "ACCOUNT LIBRARY", 14, -12)

    local libHint = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    libHint:SetPoint("TOPLEFT", 14, -28)
    libHint:SetWidth(COLW)
    libHint:SetJustifyH("LEFT")
    libHint:SetJustifyV("TOP")
    libHint:SetSpacing(2)
    libHint:SetText("A shelf every character on this account can see. Put a set on it here, take a copy on your alt.")
    libHint:SetTextColor(unpack(Skin.colors.textDim))
    libHint:SetHeight(32)

    local LIB_ROWS, LIB_H = 9, 24
    panel.libRows = {}
    for i = 1, LIB_ROWS do
        local r = CreateFrame("Button", nil, panel)
        r:SetSize(COLW, LIB_H - 2)
        r:SetPoint("TOPLEFT", 14, -(66 + (i - 1) * LIB_H))
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r.bg = Skin:Fill(r, Skin.colors.row)

        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(r)
        hl:SetColorTexture(1, 1, 1, 0.09)

        local icon = r:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", 4, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.icon = icon

        local text = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        text:SetPoint("RIGHT", -4, 0)
        text:SetJustifyH("LEFT")
        r.text = text

        r:SetScript("OnClick", function(self, click)
            if not self.entryName then return end
            if click == "RightButton" then
                ns.Menu:Open(self, {
                    { text = "Copy to this character",
                      func = function() ns.Share:FromLibrary(self.entryName, "rename") end },
                    { text = "Replace same-named set here",
                      func = function() ns.Share:FromLibrary(self.entryName, "overwrite") end },
                    { text = "Remove from library", danger = true,
                      func = function() ns.Share:RemoveFromLibrary(self.entryName) end },
                })
            else
                ns.Share:FromLibrary(self.entryName, "rename")
            end
        end)

        r:SetScript("OnEnter", function(self)
            if not self.entryName then return end
            local e = ns.Share:LibraryEntry(self.entryName)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.entryName, 1, 1, 1)
            local n = 0
            for _ in pairs(e and e.items or {}) do n = n + 1 end
            GameTooltip:AddLine(n .. " item(s)", 0.7, 0.7, 0.75)
            if e and e.from then
                GameTooltip:AddLine("Saved from " .. e.from, 0.6, 0.6, 0.65)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click: copy here", 0.4, 0.85, 1)
            GameTooltip:AddLine("Right-click: more", 0.4, 0.85, 1)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)

        panel.libRows[i] = r
    end

    local toLib = Skin:AccentButton(panel, "Put a set on the shelf", COLW, 22)
    toLib:SetPoint("TOPLEFT", 14, -(66 + LIB_ROWS * LIB_H + 8))
    toLib.tooltipText = "Copy one of this character's sets to the account library"
    toLib:SetScript("OnClick", function(self)
        local entries = {}
        for _, name in ipairs(Sets:GetOrder()) do
            table.insert(entries, { text = name, func = function()
                ns.Share:ToLibrary(name)
                ns:Print("'" .. name .. "' is on the account shelf.")
            end })
        end
        if #entries == 0 then
            entries[1] = { text = "No sets saved", func = function() end }
        end
        ns.Menu:Open(self, entries)
    end)

    -- ------------------------------------------------ export / import ---
    local X = 262
    SectionLabel(panel, "EXPORT / IMPORT", X, -12)

    local boxHint = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    boxHint:SetPoint("TOPLEFT", X, -28)
    boxHint:SetPoint("RIGHT", panel, "RIGHT", -14, 0)
    boxHint:SetJustifyH("LEFT")
    boxHint:SetJustifyV("TOP")
    boxHint:SetSpacing(2)
    boxHint:SetText("Text you can paste to a guildmate. Export fills the box — press Ctrl+A then Ctrl+C. To import, paste in and hit Import.")
    boxHint:SetTextColor(unpack(Skin.colors.textDim))
    boxHint:SetHeight(32)

    local boxBG = CreateFrame("Frame", nil, panel)
    boxBG:SetPoint("TOPLEFT", X, -66)
    boxBG:SetPoint("RIGHT", panel, "RIGHT", -14, 0)
    boxBG:SetHeight(LIB_ROWS * LIB_H - 6)
    Skin:Fill(boxBG, { 0, 0, 0, 0.55 })
    Skin:Border(boxBG)

    local scroll = CreateFrame("ScrollFrame", "LoadoutShareScroll", boxBG, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 5, -5)
    scroll:SetPoint("BOTTOMRIGHT", -26, 5)

    local box = CreateFrame("EditBox", "LoadoutShareBox", scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetWidth(230)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(box)
    panel.box = box

    boxBG:SetScript("OnMouseDown", function() box:SetFocus() end)
    boxBG:EnableMouse(true)

    local expAll = Skin:Button(panel, "Export all sets", 110, 20)
    expAll:SetPoint("TOPLEFT", boxBG, "BOTTOMLEFT", 0, -6)
    expAll.tooltipText = "Fill the box with every set on this character"
    expAll:SetScript("OnClick", function()
        local names = Sets:GetOrder()
        if #names == 0 then ns:Print("Nothing to export.") return end
        box:SetText(ns.Share:EncodeSets(names))
        box:HighlightText()
        box:SetFocus()
    end)

    local expOne = Skin:Button(panel, "Export one…", 110, 20)
    expOne:SetPoint("LEFT", expAll, "RIGHT", 6, 0)
    expOne:SetScript("OnClick", function(self)
        local entries = {}
        for _, name in ipairs(Sets:GetOrder()) do
            table.insert(entries, { text = name, func = function()
                box:SetText(ns.Share:EncodeSets({ name }))
                box:HighlightText()
                box:SetFocus()
            end })
        end
        if #entries == 0 then
            entries[1] = { text = "No sets saved", func = function() end }
        end
        ns.Menu:Open(self, entries)
    end)

    local imp = Skin:AccentButton(panel, "Import from box", 110, 22)
    imp:SetPoint("TOPLEFT", expAll, "BOTTOMLEFT", 0, -6)
    imp.tooltipText = "Read whatever is in the box"
    imp.tooltipExtra = "Names that clash get a number added rather than overwriting."
    imp:SetScript("OnClick", function()
        ns.Share:ImportString(box:GetText(), "rename")
    end)

    local impOver = Skin:Button(panel, "Import, replacing", 110, 22)
    impOver:SetPoint("LEFT", imp, "RIGHT", 6, 0)
    impOver.tooltipText = "Same, but same-named sets here are overwritten"
    impOver:SetScript("OnClick", function()
        ns.Share:ImportString(box:GetText(), "overwrite")
    end)

    local clear = Skin:Button(panel, "Clear box", 110, 20)
    clear:SetPoint("TOPLEFT", imp, "BOTTOMLEFT", 0, -6)
    clear:SetScript("OnClick", function() box:SetText("") end)

    function panel:Refresh()
        local names = ns.Share:LibraryNames()
        for i = 1, LIB_ROWS do
            local r = self.libRows[i]
            local name = names[i]
            if name then
                local e = ns.Share:LibraryEntry(name)
                r.entryName = name
                r.text:SetText(name)
                r.text:SetTextColor(unpack(Skin.colors.text))
                r.icon:SetTexture((e and e.icon) or "Interface\\Icons\\INV_Misc_Bag_08")
                r:Show()
            else
                r.entryName = nil
                r:Hide()
            end
        end

        if #names == 0 then
            if not self.libEmpty then
                local fs = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                fs:SetPoint("TOPLEFT", 18, -70)
                fs:SetText("The shelf is empty")
                fs:SetTextColor(unpack(Skin.colors.textDim))
                self.libEmpty = fs
            end
            self.libEmpty:Show()
        elseif self.libEmpty then
            self.libEmpty:Hide()
        end
    end

    panel:SetScript("OnShow", function(self) self:Refresh() end)
    ns:Listen("LIBRARY_CHANGED", function() if panel:IsVisible() then panel:Refresh() end end)
    return panel
end

-- =========================================================================
--  Shared content
--
--  The tabs and panels live in one frame that gets re-parented, so the same
--  UI can sit inside Blizzard's AddOns options or inside a standalone
--  resizable window without being built twice.
-- =========================================================================
local Content, Opt, BlizzPanel, BlizzCategory

local function BuildContent()
    if Content then return Content end

    local c = CreateFrame("Frame", "LoadoutOptionsContent", UIParent)
    c:SetSize(560, 470)

    local body = CreateFrame("Frame", nil, c)
    body:SetPoint("TOPLEFT", 0, -30)
    body:SetPoint("BOTTOMRIGHT", 0, 26)
    Skin:Fill(body, Skin.colors.panel)
    Skin:Border(body)

    local panels = {
        general = BuildGeneralPanel(body),
        rules   = BuildRulesPanel(body),
        keys    = BuildKeysPanel(body),
        macros  = BuildMacrosPanel(body),
        holds   = BuildHoldsPanel(body),
        bars    = BuildBarsPanel(body),
        share   = BuildSharePanel(body),
    }
    c.panels = panels

    local tabs = {}
    SelectTab = function(id)
        for tid, t in pairs(tabs) do
            local on = (tid == id)
            t.bg:SetColorTexture(unpack(on and Skin.colors.rowHover or Skin.colors.row))
            t.text:SetTextColor(on and 1 or 0.6, on and 1 or 0.62, on and 1 or 0.66)
            panels[tid]:SetShown(on)
        end
        c.activeTab = id
    end

    local function AddTab(id, label, x, w)
        local t = Skin:Button(c, label, w, 22)
        t:SetPoint("TOPLEFT", x, -3)
        t:SetScript("OnClick", function() SelectTab(id) end)
        tabs[id] = t
    end

    AddTab("general", "General", 2,   72)
    AddTab("rules",   "Rules",   78,  62)
    AddTab("bars",    "Bars",    144, 54)
    AddTab("holds",   "Keep on", 202, 74)
    AddTab("share",   "Share",   280, 62)
    AddTab("keys",    "Keys",    346, 54)
    AddTab("macros",  "Macros",  404, 70)

    local ver = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ver:SetPoint("BOTTOMLEFT", 4, 6)
    ver:SetText("v" .. ns.VERSION .. "  ·  /lo")
    ver:SetTextColor(unpack(Skin.colors.textDim))

    local wipeBtn = Skin:Button(c, "Delete all sets", 110, 20)
    wipeBtn:SetPoint("BOTTOMRIGHT", -22, 3)
    wipeBtn.text:SetTextColor(1, 0.5, 0.5)
    wipeBtn.tooltipText = "Delete every set and rule on this character"
    wipeBtn.tooltipExtra = "This cannot be undone. Other characters are not affected."
    wipeBtn:SetScript("OnClick", function()
        wipe(ns.cdb.sets)
        wipe(ns.cdb.order)
        wipe(ns.cdb.rules)
        ns.Rules:Release()
        ns:Fire("SETS_CHANGED")
        ns:Fire("RULES_CHANGED")
        ns:Print("All sets and rules deleted for this character.")
    end)

    SelectTab("general")
    Content = c
    return c
end

local function AttachContent(parent, l, t, r, b)
    local c = BuildContent()
    c:SetParent(parent)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", parent, "TOPLEFT", l, t)
    c:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", r, b)
    c:Show()
    if c.activeTab and c.panels[c.activeTab] and c.panels[c.activeTab].Layout then
        c.panels[c.activeTab]:Layout()
    end
end

-- =========================================================================
--  Blizzard's Interface -> AddOns panel
-- =========================================================================
local function BuildBlizzPanel()
    if BlizzPanel then return BlizzPanel end

    local p = CreateFrame("Frame", "LoadoutBlizzOptions", UIParent)
    p.name = ns.TITLE
    p:Hide()

    local title = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -14)
    title:SetText(ns.TITLE)

    local sub = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetWidth(420)
    sub:SetJustifyH("LEFT")
    sub:SetSpacing(3)
    sub:SetText("Gear sets, hover swapping, automatic swap rules and the floating bars.\n\n"
        .. "Settings open in their own window so you can drag it around and resize it "
        .. "while you try things out.")
    sub:SetTextColor(unpack(Skin.colors.text))

    local open = Skin:AccentButton(p, "Open Loadout settings", 190, 24)
    open:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -16)
    open:SetScript("OnClick", function()
        if SettingsPanel then SettingsPanel:Hide() end
        if InterfaceOptionsFrame then InterfaceOptionsFrame:Hide() end
        ns:Fire("OPEN_OPTIONS_WINDOW")
    end)

    local hint = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -14)
    hint:SetText("Also available from |cff5fd7ff/lo config|r or the minimap button.")
    hint:SetTextColor(unpack(Skin.colors.textDim))

    if Settings and Settings.RegisterCanvasLayoutCategory then
        BlizzCategory = Settings.RegisterCanvasLayoutCategory(p, p.name)
        if BlizzCategory then
            BlizzCategory.ID = BlizzCategory.ID or p.name
            Settings.RegisterAddOnCategory(BlizzCategory)
        end
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(p)
    end

    BlizzPanel = p
    return p
end

-- =========================================================================
--  Standalone window (the "pop out" view)
-- =========================================================================
local function BuildWindow()
    if Opt then return Opt end

    local f = Skin:Window("LoadoutOptionsFrame", UIParent, 580, 560, "Loadout — Options")
    Skin:MakePersistent(f, "options", "CENTER", 240, 0)
    f:RestorePosition()

    local MIN_W, MIN_H = 540, 420
    local MAX_W, MAX_H = 1100, 950

    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    else
        if f.SetMinResize then f:SetMinResize(MIN_W, MIN_H) end
        if f.SetMaxResize then f:SetMaxResize(MAX_W, MAX_H) end
    end

    local saved = ns.cdb.ui and ns.cdb.ui.optionsSize
    if saved and saved.w and saved.h then
        f:SetSize(math.max(MIN_W, math.min(MAX_W, saved.w)),
                  math.max(MIN_H, math.min(MAX_H, saved.h)))
    end

    f:SetScript("OnDragStart", function(self)
        if ns.db.locked then return end
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SavePosition()
    end)

    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(f:GetFrameLevel() + 10)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function()
        if ns.db.locked then return end
        f:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        ns.cdb.ui.optionsSize = { w = f:GetWidth(), h = f:GetHeight() }
        f:SavePosition()
        local c = Content
        if c and c.activeTab and c.panels[c.activeTab] then
            if c.panels[c.activeTab].Layout then c.panels[c.activeTab]:Layout() end
            if c.panels[c.activeTab].Refresh then c.panels[c.activeTab]:Refresh() end
        end
    end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Drag to resize", 1, 1, 1)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

    AttachContent(f, 6, -30, -6, 6)

    tinsert(UISpecialFrames, "LoadoutOptionsFrame")
    Opt = f
    return f
end

-- =========================================================================
--  Wiring
-- =========================================================================
ns:Listen("PLAYER_READY", function()
    -- Registered up front so the category is listed even before it is opened.
    BuildBlizzPanel()
end)

ns:Listen("TOGGLE_OPTIONS", function()
    local f = BuildWindow()
    if f:IsShown() then f:Hide() else f:Show() end
end)

ns:Listen("OPEN_OPTIONS_WINDOW", function()
    BuildWindow():Show()
end)

ns:Listen("TOGGLE_OPTIONS_RULES", function()
    BuildWindow():Show()
    if SelectTab then SelectTab("rules") end
end)

ns:Listen("RESET_POSITIONS", function()
    if Opt then Opt:RestorePosition() end
end)
