--[[--------------------------------------------------------------------------
    JCT - Options.lua
    Standalone configuration window, slash commands, and test mode.

    The window is standalone rather than embedded in Blizzard's options
    panel, because the Settings vs InterfaceOptions API differs between
    Classic builds. We still try to add an entry to whichever system exists,
    but it only contains a button that opens this window - so the addon can
    never be made unconfigurable by an API change.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

local Options = {}
ns.Options = Options

local W                       -- ns.Widgets, resolved at build time
local widgets = {}            -- everything with a :Refresh()
local tabs = {}
local window
local built = false

local CONTENT_W = 540         -- width the widgets are laid out against
local MIN_W, MIN_H = 700, 400
local MAX_W, MAX_H = 1400, 1000

local area                    -- the content region, resolved in Build()

-- Widgets are positioned at build time against CONTENT_W, so widening the
-- window does not reflow them. What it must do is widen the scroll children
-- to match, otherwise the content sits in a narrow strip with the panel
-- background showing through beside it.
local function ResizeContent()
    if not area then return end
    local w = area:GetWidth() - 6
    if w < CONTENT_W then w = CONTENT_W end
    for i = 1, #tabs do
        local content = tabs[i].scroll and tabs[i].scroll.content
        if content then content:SetWidth(w) end
    end
end

function ns.ApplyWindowGeometry()
    if not window then return end
    local ui = ns.db.ui
    window:SetSize(ui.width or 760, ui.height or 580)
    window:ClearAllPoints()
    window:SetPoint(ui.point or "CENTER", UIParent, ui.relPoint or "CENTER",
                    ui.x or 0, ui.y or 0)
    ResizeContent()
end

--------------------------------------------------------------------------
-- Layout helper
--------------------------------------------------------------------------

local function NewCursor(content)
    return {
        parent = content,
        y = -8,
        Add = function(self, widget, height, indent)
            widget:SetPoint("TOPLEFT", self.parent, "TOPLEFT", 12 + (indent or 0), self.y)
            self.y = self.y - (height or 26)
            widgets[#widgets + 1] = widget
            return widget
        end,
        Gap = function(self, h)
            self.y = self.y - (h or 8)
        end,
        Header = function(self, text)
            local fs = W.Header(self.parent, text)
            fs:SetPoint("TOPLEFT", self.parent, "TOPLEFT", 10, self.y - 4)
            self.y = self.y - 26
            return fs
        end,
        Note = function(self, text)
            local fs = W.Label(self.parent, text, 11, 0.65, 0.65, 0.7)
            fs:SetPoint("TOPLEFT", self.parent, "TOPLEFT", 12, self.y)
            fs:SetWidth(CONTENT_W - 24)
            fs:SetJustifyH("LEFT")
            local h = fs:GetStringHeight() or 14
            self.y = self.y - (h + 8)
            return fs
        end,
        Finish = function(self)
            self.parent:SetHeight(-self.y + 20)
            self.parent:SetWidth(CONTENT_W)
        end,
    }
end

--------------------------------------------------------------------------
-- Item list builders for dropdowns
--------------------------------------------------------------------------

local function fontItems()
    local names = ns.SortedFontNames()
    local out = {}
    for i = 1, #names do out[i] = { value = names[i], label = names[i] } end
    return out
end

local function frameItems()
    local out = {}
    for i = 1, #ns.FRAME_ORDER do
        local n = ns.FRAME_ORDER[i]
        out[i] = { value = n, label = ns.FRAME_LABELS[n] or n }
    end
    return out
end

-- Same list, but a frame that is switched off is marked, because routing a
-- stream at a disabled frame silently throws those messages away.
local function routeItems()
    local out = frameItems()
    for i = 1, #out do
        local cfg = ns.db.frames[out[i].value]
        if cfg and not cfg.enabled then
            out[i].label = out[i].label .. " |cffff5555(off)|r"
        end
    end
    return out
end

local OUTLINE_ITEMS = {
    { value = "",                   label = "None" },
    { value = "OUTLINE",            label = "Outline" },
    { value = "THICKOUTLINE",       label = "Thick outline" },
    { value = "OUTLINE, MONOCHROME", label = "Outline + monochrome" },
}

local ANIM_ITEMS = {
    { value = "up",         label = "Scroll up" },
    { value = "down",       label = "Scroll down" },
    { value = "fountain",   label = "Fountain (arc out and back)" },
    { value = "gravity",    label = "Lob (up, then falls)" },
    { value = "diagonal",   label = "Diagonal (up and out)" },
    { value = "bounce",     label = "Bounce (overshoot and settle)" },
    { value = "wobble",     label = "Wobble (rise with a sway)" },
    { value = "burst",      label = "Burst (scatter outward)" },
    { value = "horizontal", label = "Horizontal" },
    { value = "static",     label = "Static (stack in place)" },
}

local CURVE_ITEMS = {
    { value = "right",     label = "Right" },
    { value = "left",      label = "Left" },
    { value = "alternate", label = "Alternate" },
}

local ALIGN_ITEMS = {
    { value = "LEFT",   label = "Left" },
    { value = "CENTER", label = "Centre" },
    { value = "RIGHT",  label = "Right" },
}

local ANCHOR_ITEMS = {
    { value = "screen",    label = "A fixed spot on screen" },
    { value = "nameplate", label = "The unit it's about (nameplate)" },
}

local ICONSIDE_ITEMS = {
    { value = "LEFT",  label = "Left of number" },
    { value = "RIGHT", label = "Right of number" },
    { value = "NONE",  label = "No icon" },
}

local STRATA_ITEMS = {
    { value = "BACKGROUND", label = "Background" },
    { value = "LOW",        label = "Low" },
    { value = "MEDIUM",     label = "Medium" },
    { value = "HIGH",       label = "High" },
    { value = "DIALOG",     label = "Dialog" },
}

local function presetItems()
    local out = {}
    for i = 1, #ns.Presets.order do
        local key = ns.Presets.order[i]
        out[i] = { value = key, label = ns.Presets.list[key].label }
    end
    return out
end

--------------------------------------------------------------------------
-- Tab: General
--------------------------------------------------------------------------

local function BuildGeneral(content)
    local c = NewCursor(content)
    local db = ns.db

    c:Header("Addon")
    c:Add(W.Checkbox(content, "Enable JCT",
        function() return db.enabled end,
        function(v) db.enabled = v; if not v then ns.Engine:ClearAll() end end))
    c:Add(W.Checkbox(content, "Take over Blizzard's combat text",
        function() return db.suppressBlizzard end,
        function(v)
            db.suppressBlizzard = v
            if v then ns.SuppressBlizzard() else ns.RestoreBlizzard() end
        end,
        "Turns off Blizzard's own floating numbers, including the ones the game engine draws over your target's head. Those engine-drawn numbers cannot be restyled by any addon, only switched off."))

    c:Gap(6)
    c:Header("Layout preset")
    c:Add(W.Dropdown(content, "Preset", presetItems,
        function() return db.preset end,
        function(v) ns.Presets:Apply(v) end, 260), 46)
    local desc = W.Label(content, "", 11, 0.65, 0.65, 0.7)
    desc:SetPoint("TOPLEFT", content, "TOPLEFT", 12, c.y)
    desc:SetWidth(CONTENT_W - 24)
    desc:SetJustifyH("LEFT")
    desc.Refresh = function(self)
        local p = ns.Presets.list[ns.db.preset]
        self:SetText(p and p.description or "")
    end
    desc:Refresh()
    widgets[#widgets + 1] = desc
    c.y = c.y - 34

    c:Gap(4)
    c:Header("Text")
    c:Add(W.Dropdown(content, "Font", fontItems,
        function() return db.general.font end,
        function(v) db.general.font = v; ns.Engine:BuildAll() end, 260), 46)
    c:Add(W.Slider(content, "Font size", 8, 38, 1,
        function() return db.general.fontSize end,
        function(v) db.general.fontSize = v; ns.Engine:BuildAll() end, 260), 46)
    c:Add(W.Dropdown(content, "Outline", function() return OUTLINE_ITEMS end,
        function() return db.general.outline end,
        function(v) db.general.outline = v; ns.Engine:BuildAll() end, 260), 46)
    c:Add(W.Checkbox(content, "Drop shadow",
        function() return db.general.shadow end,
        function(v) db.general.shadow = v; ns.Engine:BuildAll() end))

    c:Gap(6)
    c:Header("Motion")
    c:Add(W.Slider(content, "How long a number lives (seconds)", 0.5, 6, 0.1,
        function() return db.general.duration end,
        function(v) db.general.duration = v; ns.Engine:BuildAll() end, 260, 1), 46)
    c:Add(W.Slider(content, "Fade out over (seconds)", 0, 5, 0.05,
        function() return db.general.fadeTime or 0.6 end,
        function(v) db.general.fadeTime = v; ns.Engine:BuildAll() end, 260, 2), 46)
    c:Note("Lifetime and fade are both in seconds, so a 2.0s life with a 0.6s fade holds for 1.4s and then fades. Set the fade equal to the lifetime to have a number fading the whole way.")
    c:Add(W.Slider(content, "Crit size multiplier", 1.0, 3.0, 0.05,
        function() return db.general.critScale end,
        function(v) db.general.critScale = v; ns.Engine:BuildAll() end, 260, 2), 46)
    c:Add(W.Checkbox(content, "Crit pop (overshoot and settle)",
        function() return db.general.critPop end,
        function(v) db.general.critPop = v; ns.Engine:BuildAll() end))
    c:Add(W.Checkbox(content, "Crits get their own stream",
        function() return db.general.critsOwnStream end,
        function(v) db.general.critsOwnStream = v end,
        "On: a crit becomes a 'crit' message and can be routed to its own frame. Off: a melee crit stays a melee message in the melee stream, just bigger - better if you are reading attack rhythm rather than hunting big numbers."))
    c:Add(W.Dropdown(content, "Frame strata", function() return STRATA_ITEMS end,
        function() return db.general.strata end,
        function(v) db.general.strata = v; ns.Engine:BuildAll() end, 260), 46)
    c:Add(W.Slider(content, "Overall opacity", 0.1, 1.0, 0.05,
        function() return db.general.alpha end,
        function(v) db.general.alpha = v; ns.Engine:BuildAll() end, 260, 2), 46)

    c:Gap(6)
    c:Header("Number formatting")
    c:Add(W.Checkbox(content, "Thousands separators (12,345)",
        function() return db.format.separators end,
        function(v) db.format.separators = v end))
    c:Add(W.Checkbox(content, "Abbreviate (12.3k)",
        function() return db.format.abbreviate end,
        function(v) db.format.abbreviate = v end,
        "Off by default. TBC numbers are small enough that abbreviating loses more information than it saves space."))
    c:Add(W.Checkbox(content, "Spell icons",
        function() return db.format.icons end,
        function(v) db.format.icons = v end))
    c:Add(W.Slider(content, "Icon size (0 = match font size)", 0, 40, 1,
        function() return db.format.iconSize end,
        function(v) db.format.iconSize = v end, 260), 46)
    c:Add(W.Checkbox(content, "Show spell names",
        function() return db.format.showSpellName end,
        function(v) db.format.showSpellName = v end))
    c:Add(W.Checkbox(content, "Show hit count after merging (1250 x5)",
        function() return db.format.showCount end,
        function(v) db.format.showCount = v end))

    c:Gap(14)
    c:Header("Reset")
    c:Note("Puts every setting back to its default and re-applies the current preset. There is no undo.")
    local resetBtn = W.Button(content, "Reset everything", 170, 24, function()
        Options:Reset()
    end)
    resetBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 12, c.y)
    c.y = c.y - 34

    c:Finish()
end

--------------------------------------------------------------------------
-- Tab: Layout
--------------------------------------------------------------------------

Options.selectedFrame = "outgoing"

local function fcfg()
    return ns.db.frames[Options.selectedFrame]
end

local function BuildLayout(content)
    local c = NewCursor(content)

    c:Note("Pick a frame, then move it with the sliders or unlock and drag it. Anything left blank inherits from the General tab.")

    c:Add(W.Dropdown(content, "Editing frame", frameItems,
        function() return Options.selectedFrame end,
        function(v) Options.selectedFrame = v end, 260), 46)

    c:Gap(4)
    c:Add(W.Checkbox(content, "Frame enabled",
        function() return fcfg().enabled end,
        function(v) fcfg().enabled = v; ns.Engine:BuildFrame(Options.selectedFrame) end))

    c:Gap(6)
    c:Header("Where it appears")
    c:Add(W.Dropdown(content, "Attach to", function() return ANCHOR_ITEMS end,
        function() return fcfg().anchor or "screen" end,
        function(v) fcfg().anchor = v; ns.Engine:BuildFrame(Options.selectedFrame) end, 300), 46)
    c:Note("Attach to the unit and numbers float up from whatever the message is about - what you hit, what hit you, the enemy who used a cooldown - following it as it moves, the way Blizzard's own combat text does. This needs nameplates turned on, and only works within nameplate range.")

    local npX = c:Add(W.Slider(content, "Sideways offset from the nameplate", -300, 300, 2,
        function() return fcfg().npOffsetX or 0 end,
        function(v) fcfg().npOffsetX = v; ns.Engine:BuildFrame(Options.selectedFrame) end, 260), 46)
    local npY = c:Add(W.Slider(content, "Height above the nameplate", -200, 300, 2,
        function() return fcfg().npOffsetY or 34 end,
        function(v) fcfg().npOffsetY = v; ns.Engine:BuildFrame(Options.selectedFrame) end, 260), 46)
    c:Note("These two are what move the numbers around on the nameplate. The Position sliders below do not apply while attached to a unit.")
    c:Add(W.Checkbox(content, "Fall back to the fixed position when there is no nameplate",
        function() return fcfg().npFallback ~= false end,
        function(v) fcfg().npFallback = v end,
        "Units out of range, or with nameplates hidden, have nothing to attach to. Leave this on to show those messages at the frame's fixed position instead of dropping them."))

    c:Gap(6)
    c:Header("Position and size")
    c:Note("While attached to a unit, Position only sets where the fallback appears. Height still controls how far a number travels.")
    local posX = c:Add(W.Slider(content, "Horizontal position", -900, 900, 1,
        function() return fcfg().x end,
        function(v) fcfg().x = v; ns.Engine:BuildFrame(Options.selectedFrame) end, 260), 46)
    local posY = c:Add(W.Slider(content, "Vertical position", -600, 600, 1,
        function() return fcfg().y end,
        function(v) fcfg().y = v; ns.Engine:BuildFrame(Options.selectedFrame) end, 260), 46)

    -- Grey out whichever pair does not apply to the current anchor mode, so
    -- a slider never silently ignores you.
    widgets[#widgets + 1] = { Refresh = function()
        local np = (fcfg().anchor == "nameplate")
        if npX.SetEnabled then npX:SetEnabled(np) end
        if npY.SetEnabled then npY:SetEnabled(np) end
        if posX.SetEnabled then posX:SetEnabled(not np) end
        if posY.SetEnabled then posY:SetEnabled(not np) end
    end }
    c:Add(W.Slider(content, "Width", 40, 900, 5,
        function() return fcfg().width end,
        function(v) fcfg().width = v; ns.Engine:BuildFrame(Options.selectedFrame) end, 260), 46)
    c:Add(W.Slider(content, "Height", 40, 800, 5,
        function() return fcfg().height end,
        function(v) fcfg().height = v; ns.Engine:BuildFrame(Options.selectedFrame) end, 260), 46)
    c:Add(W.Slider(content, "Scale", 0.4, 2.0, 0.05,
        function() return fcfg().scale end,
        function(v) fcfg().scale = v; ns.Engine:BuildFrame(Options.selectedFrame) end, 260, 2), 46)

    c:Gap(6)
    c:Header("Motion")
    c:Add(W.Dropdown(content, "Animation", function() return ANIM_ITEMS end,
        function() return fcfg().animation end,
        function(v) fcfg().animation = v; ns.Engine:BuildFrame(Options.selectedFrame) end, 260), 46)
    c:Add(W.Dropdown(content, "Curve / direction", function() return CURVE_ITEMS end,
        function() return fcfg().curve end,
        function(v) fcfg().curve = v; ns.Engine:BuildFrame(Options.selectedFrame) end, 260), 46)
    c:Add(W.Slider(content, "Random horizontal jitter (px)", 0, 40, 1,
        function() return fcfg().stagger end,
        function(v) fcfg().stagger = v; ns.Engine:BuildFrame(Options.selectedFrame) end, 260), 46)

    c:Gap(6)
    c:Header("Text in this frame")
    c:Add(W.Dropdown(content, "Alignment", function() return ALIGN_ITEMS end,
        function() return fcfg().align end,
        function(v) fcfg().align = v; ns.Engine:BuildFrame(Options.selectedFrame) end, 260), 46)
    c:Add(W.Slider(content, "Font size override (0 = inherit)", 0, 38, 1,
        function() return fcfg().fontSize or 0 end,
        function(v)
            fcfg().fontSize = (v <= 0) and nil or v
            ns.Engine:BuildFrame(Options.selectedFrame)
        end, 260), 46)
    c:Add(W.Slider(content, "Lifetime override (0 = inherit)", 0, 8, 0.1,
        function() return fcfg().duration or 0 end,
        function(v)
            fcfg().duration = (v <= 0) and nil or v
            ns.Engine:BuildFrame(Options.selectedFrame)
        end, 260, 1), 46)
    c:Add(W.Slider(content, "Fade override (0 = inherit)", 0, 5, 0.05,
        function() return fcfg().fadeTime or 0 end,
        function(v)
            fcfg().fadeTime = (v <= 0) and nil or v
            ns.Engine:BuildFrame(Options.selectedFrame)
        end, 260, 2), 46)
    c:Add(W.Slider(content, "Maximum simultaneous lines", 1, 30, 1,
        function() return fcfg().maxLines end,
        function(v) fcfg().maxLines = v; ns.Engine:BuildFrame(Options.selectedFrame) end, 260), 46)
    c:Add(W.Dropdown(content, "Icon position", function() return ICONSIDE_ITEMS end,
        function() return fcfg().iconSide end,
        function(v) fcfg().iconSide = v; ns.Engine:BuildFrame(Options.selectedFrame) end, 260), 46)

    c:Finish()
end

--------------------------------------------------------------------------
-- Tab: Routing
--------------------------------------------------------------------------

local function BuildRouting(content)
    local c = NewCursor(content)
    c:Note("Decide which frame each kind of message goes to. Send everything to one frame for a single stream, or spread it out.")

    for i = 1, #ns.CLASSES do
        local class = ns.CLASSES[i]
        c:Add(W.Dropdown(content, class.label, routeItems,
            function() return ns.db.routing[class.key] end,
            function(v) ns.db.routing[class.key] = v end, 260), 46)
    end

    c:Finish()
end

--------------------------------------------------------------------------
-- Tab: Filters
--------------------------------------------------------------------------

local THRESHOLDS = {
    { key = "minOutDamage", label = "Hide your hits below" },
    { key = "minOutCrit",   label = "Hide your crits below" },
    { key = "minPetDamage", label = "Hide pet hits below" },
    { key = "minPetCrit",   label = "Hide pet crits below" },
    { key = "minInDamage",  label = "Hide damage taken below" },
    { key = "minInCrit",    label = "Hide crits taken below" },
    { key = "minHeal",      label = "Hide your heals below" },
    { key = "minHealCrit",  label = "Hide your heal crits below" },
    { key = "minInHeal",    label = "Hide heals you receive below" },
    { key = "minPower",     label = "Hide power gains below" },
}

local TOGGLES = {
    { key = "showAutoAttack", label = "Melee swings" },
    { key = "showAutoShot",   label = "Auto Shot" },
    { key = "showDots",       label = "Your DoT ticks" },
    { key = "showHots",       label = "Your HoT ticks" },
    { key = "showOverheal",   label = "Overhealing (shown in brackets)" },
    { key = "showMisses",     label = "Your misses, dodges, parries" },
    { key = "showIncomingMisses", label = "Attacks you avoided" },
    { key = "showProcs",      label = "Buffs and procs you gain in combat", tip = "Buffs landing on you while in combat: trinket procs, Bestial Wrath, Rapid Fire, Quick Shots. Restricted to combat so raid buffing does not flood the screen." },
    { key = "showAuraFades",  label = "Buffs falling off you in combat" },
    { key = "showStates",     label = "Stances, aspects, forms, auras, seals", tip = "Hunter aspects, warrior stances, druid forms, paladin auras and seals, mage and warlock armours, shaman shields, Stealth, Shadowform. Shown in and out of combat, because that is when you change them - and losing one gets its own colour so a dazed Cheetah or an expired seal reads as the mistake it is." },
    { key = "collapseStateSwaps", label = "Treat a state swap as one message", tip = "Swapping Hawk for Viper is one decision but two combat log events. With this on, the fade of the old state is dropped when a new one from the same group lands right behind it, so only genuine losses show the fade colour." },
    { key = "showPetMelee",   label = "Pet melee swings", tip = "Off by default. A Beast Mastery pet's white swings are the single loudest source of combat text in the game." },
    { key = "showPetSpells",  label = "Pet abilities" },
    { key = "showPetCrits",   label = "Pet crits use crit styling" },
    { key = "showPetMisses",  label = "Pet misses" },
    { key = "showIncoming",   label = "Damage taken" },
    { key = "showIncomingHeals", label = "Healing you receive" },
    { key = "showPower",      label = "Mana / rage / energy gains" },
    { key = "showEnvironmental", label = "Falling, fire, drowning" },
    { key = "showKillingBlow", label = "Killing blows" },
    { key = "showInterrupts", label = "Interrupts" },
    { key = "showDispels",    label = "Dispels and spell steals" },
    { key = "showLowHealth",  label = "Low health warning" },
    { key = "showCombatState", label = "Entering / leaving combat" },
    { key = "onlyInCombat",   label = "Only show anything while in combat" },
}

local function BuildFilters(content)
    local c = NewCursor(content)

    c:Header("Thresholds")
    c:Note("Applied after merging, so a stream of small ticks that adds up to a big number still gets through.")
    for i = 1, #THRESHOLDS do
        local t = THRESHOLDS[i]
        c:Add(W.Slider(content, t.label, 0, 5000, 25,
            function() return ns.db.filters[t.key] end,
            function(v) ns.db.filters[t.key] = v end, 260), 46)
    end

    c:Gap(6)
    c:Header("What to show")
    for i = 1, #TOGGLES do
        local t = TOGGLES[i]
        c:Add(W.Checkbox(content, t.label,
            function() return ns.db.filters[t.key] end,
            function(v) ns.db.filters[t.key] = v end, t.tip))
    end

    c:Gap(8)
    c:Header("Blocked spells")
    c:Note("Spells you have seen in combat appear here. Tick one to stop it producing combat text. Use /jct block <spellID> to add one by hand.")

    local clearBtn = W.Button(content, "Clear the seen list", 160, 22, function()
        ns.Events:ClearSeenSpells()
        Options:Refresh()
    end)
    clearBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 12, c.y)
    c.y = c.y - 30

    local listHolder = CreateFrame("Frame", nil, content)
    listHolder:SetSize(CONTENT_W - 24, 10)
    listHolder:SetPoint("TOPLEFT", content, "TOPLEFT", 12, c.y)
    listHolder.rows = {}
    listHolder.Refresh = function(self)
        -- Clicking any checkbox anywhere refreshes every widget, so this
        -- list must not re-sort itself on every click. Rebuild only when the
        -- set of seen spells has actually changed.
        local stamp = ns.db.filters.seenCount or 0
        if self.__sorted and self.__stamp == stamp then
            for i = 1, #self.rows do
                local row = self.rows[i]
                if row:IsShown() and row.__entry then
                    row:SetChecked(ns.db.filters.blacklist[row.__entry.id] and true or false)
                end
            end
            return
        end
        self.__stamp = stamp

        local seen = ns.db.filters.seenSpells
        local sorted = {}
        for id, name in pairs(seen) do sorted[#sorted + 1] = { id = id, name = name } end
        table.sort(sorted, function(a, b) return (a.name or "") < (b.name or "") end)
        self.__sorted = sorted

        for i = 1, #sorted do
            local row = self.rows[i]
            local entry = sorted[i]
            if not row then
                row = W.Checkbox(self, "", function() return false end, function() end)
                row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(i - 1) * 22)
                self.rows[i] = row
            end
            row.__entry = entry
            row.__get = function() return ns.db.filters.blacklist[row.__entry.id] end
            row.__set = function(v) ns.db.filters.blacklist[row.__entry.id] = v or nil end
            row.label:SetText(string.format("%s |cff707070(%d)|r", entry.name or "?", entry.id))
            row:SetChecked(ns.db.filters.blacklist[entry.id] and true or false)
            row:Show()
        end
        for i = #sorted + 1, #self.rows do self.rows[i]:Hide() end
        local h = (#sorted * 22) + 4
        self:SetHeight(h > 10 and h or 10)
        content:SetHeight(-c.y + h + 30)
    end
    widgets[#widgets + 1] = listHolder
    listHolder:Refresh()

    content:SetWidth(CONTENT_W)
end

--------------------------------------------------------------------------
-- Tab: Profiles
--------------------------------------------------------------------------

local function BuildProfiles(content)
    local c = NewCursor(content)

    c:Header("Profiles")
    c:Note("A profile is a complete snapshot of every setting: layout, fonts, colours, routing, filters, merge windows, enemy alerts. Profiles are stored separately from your live settings and are shared across all your characters, so one saved on your hunter can be loaded on your priest.")
    c:Note("Saving costs nothing and there is no limit, so take one before you experiment.")

    local current = W.Label(content, "", 12, 0.55, 0.85, 0.55)
    current:SetPoint("TOPLEFT", content, "TOPLEFT", 12, c.y)
    current:SetWidth(CONTENT_W - 24)
    current:SetJustifyH("LEFT")
    current.Refresh = function(self)
        local name = ns.db.currentProfile
        if name then
            self:SetText("Last saved or loaded: |cffffff00" .. name .. "|r")
        else
            self:SetText("No profile saved yet.")
        end
    end
    current:Refresh()
    widgets[#widgets + 1] = current
    c.y = c.y - 26

    c:Gap(4)
    local nameBox = W.EditBox(content, "Profile name", 260)
    nameBox:SetPoint("TOPLEFT", content, "TOPLEFT", 12, c.y)
    c.y = c.y - 46

    local listHolder   -- forward declaration; the save button refreshes it

    local function doSave()
        local name = nameBox:GetText()
        local stored, err
        if not name or name:gsub("%s", "") == "" then
            -- No name given: pick one that cannot collide with an existing
            -- profile, rather than silently overwriting "Profile 3".
            stored = ns.Profiles:SaveAuto("Profile " .. (ns.Profiles:Count() + 1))
        else
            local ok
            ok, stored = ns.Profiles:Save(name)
            if not ok then err = stored; stored = nil end
        end
        if stored then
            ns.Print("saved profile |cffffff00" .. stored .. "|r.")
            nameBox:SetText("")
        else
            ns.Print(err or "could not save that profile.")
        end
        if listHolder then listHolder.__stamp = nil end
        Options:Refresh()
    end

    nameBox.editBox:SetScript("OnEnterPressed", function(self)
        doSave()
        self:ClearFocus()
    end)

    local saveBtn = W.Button(content, "Save current settings", 190, 24, doSave)
    saveBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 12, c.y)
    c.y = c.y - 34

    c:Gap(6)
    c:Header("Saved profiles")

    listHolder = CreateFrame("Frame", nil, content)
    listHolder:SetSize(CONTENT_W - 24, 10)
    listHolder:SetPoint("TOPLEFT", content, "TOPLEFT", 12, c.y)
    listHolder.rows = {}
    listHolder.Refresh = function(self)
        local names = ns.Profiles:List()

        -- Cheap change detection: clicking anything refreshes every widget,
        -- and rebuilding this list on each click would be wasteful.
        local stamp = table.concat(names, "\001") .. "\002" .. tostring(ns.db.currentProfile)
        if self.__stamp == stamp then return end
        self.__stamp = stamp

        for i = 1, #names do
            local name = names[i]
            local row = self.rows[i]
            if not row then
                row = CreateFrame("Frame", nil, self)
                row:SetSize(CONTENT_W - 24, 26)
                row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(i - 1) * 28)

                row.label = W.Label(row, "", 12)
                row.label:SetPoint("LEFT", row, "LEFT", 2, 0)
                row.label:SetWidth(CONTENT_W - 200)
                row.label:SetJustifyH("LEFT")

                row.loadBtn = W.Button(row, "Load", 74, 22, function()
                    local ok, err = ns.Profiles:Load(row.__name)
                    if ok then
                        ns.Print("loaded profile |cffffff00" .. row.__name .. "|r.")
                    else
                        ns.Print(err or "could not load that profile.")
                    end
                    self.__stamp = nil
                    Options:Refresh()
                end)
                row.loadBtn:SetPoint("RIGHT", row, "RIGHT", -84, 0)

                row.delBtn = W.Button(row, "Delete", 74, 22, function()
                    -- Two-step, because there is no undo.
                    if row.__armed then
                        ns.Profiles:Delete(row.__name)
                        ns.Print("deleted profile |cffffff00" .. row.__name .. "|r.")
                        self.__stamp = nil
                        Options:Refresh()
                    else
                        row.__armed = true
                        row.delBtn:SetLabel("Sure?")
                        if C_Timer and C_Timer.After then
                            C_Timer.After(4, function()
                                if row.__armed then
                                    row.__armed = false
                                    row.delBtn:SetLabel("Delete")
                                end
                            end)
                        end
                    end
                end)
                row.delBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)

                self.rows[i] = row
            end

            row.__name = name
            row.__armed = false
            row.delBtn:SetLabel("Delete")
            if name == ns.db.currentProfile then
                row.label:SetText("|cffffff00" .. name .. "|r  |cff707070(current)|r")
            else
                row.label:SetText(name)
            end
            row:Show()
        end
        for i = #names + 1, #self.rows do self.rows[i]:Hide() end

        local h = (#names * 28) + 4
        if #names == 0 then h = 24 end
        self:SetHeight(h)
        self.__height = h
        if self.OnResized then self:OnResized() end
    end
    widgets[#widgets + 1] = listHolder
    listHolder:Refresh()

    ------------------------------------------------------------------
    -- Share: export and import
    ------------------------------------------------------------------

    -- The share block sits below a list whose height changes, so it is
    -- parked in its own frame and repositioned whenever the list resizes.
    local share = CreateFrame("Frame", nil, content)
    share:SetSize(CONTENT_W - 24, 300)
    share:SetPoint("TOPLEFT", listHolder, "BOTTOMLEFT", 0, -18)

    local shareHeader = W.Header(share, "Share")
    shareHeader:SetPoint("TOPLEFT", share, "TOPLEFT", -2, 0)

    local shareNote = W.Label(share,
        "Export turns your settings into a block of text you can paste anywhere. "
        .. "Only what you have actually changed from the defaults is included, so it stays short. "
        .. "Click the box to select all of it, then Ctrl+C.",
        11, 0.65, 0.65, 0.7)
    shareNote:SetPoint("TOPLEFT", share, "TOPLEFT", 0, -22)
    shareNote:SetWidth(CONTENT_W - 24)
    shareNote:SetJustifyH("LEFT")

    local exportBox = W.TextArea(share, "Export", CONTENT_W - 24, 60, true)
    exportBox:SetPoint("TOPLEFT", share, "TOPLEFT", 0, -70)

    local exportBtn = W.Button(share, "Export current settings", 200, 24, function()
        local str, err = ns.Codec.Export(ns.db)
        if str then
            exportBox:SetText(str)
            exportBox:SelectAll()
            ns.Print("exported " .. #str .. " characters. Ctrl+C to copy.")
        else
            ns.Print(err or "could not export.")
        end
    end)
    exportBtn:SetPoint("TOPLEFT", share, "TOPLEFT", 0, -156)

    local importBox = W.TextArea(share, "Import", CONTENT_W - 24, 60)
    importBox:SetPoint("TOPLEFT", share, "TOPLEFT", 0, -192)

    local importBtn = W.Button(share, "Import and apply", 200, 24, function()
        local text = importBox:GetText()
        local cfg, err = ns.Codec.Import(text)
        if not cfg then
            ns.Print("|cffff5555" .. tostring(err) .. "|r")
            return
        end
        if not ns.Profiles.LooksLikeConfig(cfg) then
            ns.Print("|cffff5555that string decoded, but it is not a valid JCT configuration.|r")
            return
        end

        -- Never a one-way door: snapshot before overwriting anything.
        local backup = ns.Profiles:SaveAuto("Before import")
        local ok, applyErr = ns.Profiles:ApplyConfig(cfg, "Imported")
        if ok then
            importBox:SetText("")
            if backup then
                ns.Print("imported and applied. Your previous setup was saved as |cffffff00"
                    .. backup .. "|r.")
            else
                ns.Print("imported and applied.")
            end
        else
            ns.Print("|cffff5555" .. (applyErr or "could not apply that configuration.") .. "|r")
        end
        if listHolder then listHolder.__stamp = nil end
        Options:Refresh()
    end)
    importBtn:SetPoint("TOPLEFT", share, "TOPLEFT", 0, -278)

    listHolder.OnResized = function(self)
        content:SetHeight(-c.y + (self.__height or 24) + 18 + 320)
    end
    listHolder:OnResized()

    content:SetWidth(CONTENT_W)
end

--------------------------------------------------------------------------
-- Tab: Enemies
--------------------------------------------------------------------------

local SCOPE_ITEMS = {
    { value = "targetfocus", label = "My target and focus only" },
    { value = "players",     label = "Any enemy player nearby" },
    { value = "all",         label = "Everything hostile, NPCs included" },
}

local function BuildEnemies(content)
    local c = NewCursor(content)

    c:Header("Enemy ability alerts")
    c:Note("Tells you when an enemy uses something that matters: a PvP trinket, Escape Artist, Recklessness, a cooldown or a stun. Matched by spell name, so every rank of a spell is covered by one entry.")

    c:Add(W.Checkbox(content, "Show enemy ability alerts",
        function() return ns.db.filters.showEnemySpells end,
        function(v) ns.db.filters.showEnemySpells = v end))

    c:Add(W.Dropdown(content, "Whose abilities", function() return SCOPE_ITEMS end,
        function() return ns.db.filters.enemyScope end,
        function(v) ns.db.filters.enemyScope = v end, 280), 46)
    c:Note("Combat log range is roughly 100 yards, so an arena is covered completely while a large battleground is not. Target and focus keeps this readable in a BG.")

    c:Add(W.Checkbox(content, "Label the caster",
        function() return ns.db.filters.enemyShowCaster end,
        function(v) ns.db.filters.enemyShowCaster = v end,
        "Marks focus casts, and shows the caster's name when you widen the scope beyond target and focus."))

    c:Gap(6)
    c:Header("Categories")
    for i = 1, #ns.ENEMY_CATEGORIES do
        local cat = ns.ENEMY_CATEGORIES[i]
        c:Add(W.Checkbox(content, cat.label,
            function() return ns.db.filters.enemyCategories[cat.key] end,
            function(v) ns.db.filters.enemyCategories[cat.key] = v end))
    end

    c:Gap(8)
    c:Header("Reactive abilities")
    c:Note("Counterattack, Mongoose Bite, Overpower, Revenge and Riposte become usable off a parry, dodge or block, and are read straight from the combat log rather than from Blizzard's combat text system, so they keep working with Blizzard's text switched off.")
    c:Note("Execute, Hammer of Wrath and Victory Rush have no combat log signature at all, so those are detected by asking the client whether the spell has become usable. That leaves the 20% health threshold to the server instead of guessing at it, which matters against enemy players where the health API only reports whole percentages.")
    c:Note("Only abilities this character actually knows are watched.")

    c:Add(W.Checkbox(content, "Alert when a reactive ability lights up",
        function() return ns.db.filters.showReactives end,
        function(v) ns.db.filters.showReactives = v end))

    local detected = W.Label(content, "", 11, 0.55, 0.85, 0.55)
    detected:SetPoint("TOPLEFT", content, "TOPLEFT", 12, c.y)
    detected:SetWidth(CONTENT_W - 24)
    detected:SetJustifyH("LEFT")
    detected.Refresh = function(self)
        self:SetText("Detected on this character: " .. ns.ReactiveSummary())
    end
    detected:Refresh()
    widgets[#widgets + 1] = detected
    c.y = c.y - 28

    c:Gap(6)
    c:Header("Individual spells")
    c:Note("Untick anything you would rather not hear about.")

    local listHolder = CreateFrame("Frame", nil, content)
    listHolder:SetSize(CONTENT_W - 24, 10)
    listHolder:SetPoint("TOPLEFT", content, "TOPLEFT", 12, c.y)
    listHolder.rows = {}
    listHolder.Refresh = function(self)
        -- Same caching rule as the seen-spells list: only rebuild when the
        -- resolved spell data has actually changed, not on every click.
        local stamp = ns.spellDataVersion or 0
        if self.__sorted and self.__stamp == stamp then
            for i = 1, #self.rows do
                local row = self.rows[i]
                if row:IsShown() and row.__entry then
                    row:SetChecked(not ns.db.filters.enemyBlacklist[row.__entry.name])
                end
            end
            return
        end
        self.__stamp = stamp

        local sorted = {}
        for name, entry in pairs(ns.enemyByName) do
            sorted[#sorted + 1] = { name = name, category = entry.category, id = entry.id }
        end
        table.sort(sorted, function(a, b)
            if a.category ~= b.category then return a.category < b.category end
            return a.name < b.name
        end)
        self.__sorted = sorted

        for i = 1, #sorted do
            local entry = sorted[i]
            local row = self.rows[i]
            if not row then
                row = W.Checkbox(self, "", function() return false end, function() end)
                row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(i - 1) * 22)
                self.rows[i] = row
            end
            row.__entry = entry
            row.__get = function() return not ns.db.filters.enemyBlacklist[row.__entry.name] end
            row.__set = function(v) ns.db.filters.enemyBlacklist[row.__entry.name] = (not v) or nil end
            row.label:SetText(string.format("%s  |cff707070%s|r", entry.name, entry.category))
            row:SetChecked(not ns.db.filters.enemyBlacklist[entry.name])
            row:Show()
        end
        for i = #sorted + 1, #self.rows do self.rows[i]:Hide() end
        local h = (#sorted * 22) + 4
        self:SetHeight(h > 10 and h or 10)
        content:SetHeight(-c.y + h + 30)
    end
    widgets[#widgets + 1] = listHolder
    listHolder:Refresh()

    content:SetWidth(CONTENT_W)
end

--------------------------------------------------------------------------
-- Tab: Colours
--------------------------------------------------------------------------

local COLOR_ROWS = {
    { key = "outMelee",    label = "Melee swings" },
    { key = "outAutoShot", label = "Auto Shot" },
    { key = "outDamage",   label = "Your spell / ability damage" },
    { key = "outCrit",     label = "Your crits" },
    { key = "outDot",      label = "Your DoT ticks" },
    { key = "outHeal",     label = "Your healing" },
    { key = "outHealCrit", label = "Your healing crits" },
    { key = "outMiss",     label = "Your misses" },
    { key = "petDamage",   label = "Pet damage" },
    { key = "petCrit",     label = "Pet crits" },
    { key = "petHeal",     label = "Pet healing" },
    { key = "petMiss",     label = "Pet misses" },
    { key = "inDamage",    label = "Damage taken" },
    { key = "inCrit",      label = "Crits taken" },
    { key = "inHeal",      label = "Healing taken" },
    { key = "inMiss",      label = "Attacks you avoided" },
    { key = "power",       label = "Power gains" },
    { key = "notify",      label = "Notifications" },
    { key = "reactive",    label = "Reactive ability ready" },
    { key = "state",       label = "State gained (aspect, stance, form)" },
    { key = "stateFade",   label = "State lost" },
    { key = "enemyBreak",  label = "Enemy broke your control" },
    { key = "enemy",       label = "Enemy cooldowns" },
    { key = "killingBlow", label = "Killing blows" },
    { key = "interrupt",   label = "Interrupts" },
    { key = "dispel",      label = "Dispels" },
    { key = "lowHealth",   label = "Low health warning" },
}

local SCHOOL_ROWS = {
    { mask = 1,  label = "Physical" },
    { mask = 2,  label = "Holy" },
    { mask = 4,  label = "Fire" },
    { mask = 8,  label = "Nature" },
    { mask = 16, label = "Frost" },
    { mask = 20, label = "Frostfire" },
    { mask = 32, label = "Shadow" },
    { mask = 36, label = "Shadowflame" },
    { mask = 64, label = "Arcane" },
}

local function BuildColors(content)
    local c = NewCursor(content)

    c:Add(W.Checkbox(content, "Colour outgoing damage by spell school",
        function() return ns.db.colors.useSchoolColors end,
        function(v) ns.db.colors.useSchoolColors = v end,
        "When on, your spell damage uses the school colours below and the per-type colour is only a fallback."))

    c:Gap(6)
    c:Header("Message colours")
    for i = 1, #COLOR_ROWS do
        local row = COLOR_ROWS[i]
        c:Add(W.ColorSwatch(content, row.label,
            function()
                local t = ns.db.colors[row.key]
                return t[1], t[2], t[3]
            end,
            function(r, g, b)
                local t = ns.db.colors[row.key]
                t[1], t[2], t[3] = r, g, b
            end), 24)
    end

    c:Gap(8)
    c:Header("Spell school colours")
    for i = 1, #SCHOOL_ROWS do
        local row = SCHOOL_ROWS[i]
        c:Add(W.ColorSwatch(content, row.label,
            function()
                local t = ns.db.schoolColors[row.mask] or { 1, 1, 1 }
                return t[1], t[2], t[3]
            end,
            function(r, g, b)
                ns.db.schoolColors[row.mask] = { r, g, b }
            end), 24)
    end

    c:Finish()
end

--------------------------------------------------------------------------
-- Tab: Merging
--------------------------------------------------------------------------

local MERGE_ROWS = {
    { key = "outDamage",   label = "Your spell / ability damage" },
    { key = "outMelee",    label = "Your melee swings" },
    { key = "outAutoShot", label = "Your Auto Shot" },
    { key = "outDot",    label = "Your DoT ticks" },
    { key = "outHeal",   label = "Your healing" },
    { key = "outMiss",   label = "Your misses" },
    { key = "petDamage", label = "Pet damage" },
    { key = "petHeal",   label = "Pet healing" },
    { key = "petMiss",   label = "Pet misses" },
    { key = "inDamage",  label = "Damage taken" },
    { key = "inHeal",    label = "Healing taken" },
    { key = "inMiss",    label = "Attacks you avoided" },
    { key = "power",     label = "Power gains" },
}

local function BuildMerge(content)
    local c = NewCursor(content)

    c:Note("The first hit in a window is always shown immediately; only the hits behind it are folded into one follow-up number with a count. So a single hit is never delayed, but a Volley or a pet swing stream collapses into something readable. Ranks of the same spell are collapsed automatically. Set an interval to 0 to turn merging off for that stream - melee and Auto Shot ship at 0 because their timing is the point.")

    c:Add(W.Checkbox(content, "Enable merging",
        function() return ns.db.merge.enabled end,
        function(v) ns.db.merge.enabled = v; ns.Events:FlushAll() end))
    c:Add(W.Checkbox(content, "Merge critical hits too",
        function() return ns.db.merge.mergeCrits end,
        function(v) ns.db.merge.mergeCrits = v end,
        "Off by default: a crit is information you want the instant it happens, not half a second later folded into a total."))

    c:Gap(6)
    c:Header("Merge window per stream (seconds)")
    for i = 1, #MERGE_ROWS do
        local row = MERGE_ROWS[i]
        c:Add(W.Slider(content, row.label, 0, 5, 0.1,
            function() return ns.db.merge.intervals[row.key] or 0 end,
            function(v) ns.db.merge.intervals[row.key] = v end, 260, 1), 46)
    end

    c:Finish()
end

--------------------------------------------------------------------------
-- Window assembly
--------------------------------------------------------------------------

local TAB_DEFS = {
    { key = "general", label = "General",  build = BuildGeneral },
    { key = "layout",  label = "Layout",   build = BuildLayout },
    { key = "routing", label = "Routing",  build = BuildRouting },
    { key = "filters", label = "Filters",  build = BuildFilters },
    { key = "enemies", label = "Enemies",  build = BuildEnemies },
    { key = "colors",  label = "Colours",  build = BuildColors },
    { key = "merge",   label = "Merging",  build = BuildMerge },
    { key = "profiles", label = "Profiles", build = BuildProfiles },
}

local function SelectTab(key)
    for i = 1, #tabs do
        local t = tabs[i]
        if t.key == key then
            t.scroll:Show()
            W.SetColor(t.button.__bg, 0.20, 0.34, 0.50, 1)
        else
            t.scroll:Hide()
            W.SetColor(t.button.__bg, 0.12, 0.13, 0.17, 1)
        end
    end
    Options.currentTab = key
end

local function Build()
    if built then return end
    W = ns.Widgets
    built = true

    window = W.Window("JCT_OptionsWindow", "Jabe's Combat Text", 760, 580)

    -- Tab column
    local tabCol = CreateFrame("Frame", nil, window)
    tabCol:SetPoint("TOPLEFT", window, "TOPLEFT", 8, -36)
    tabCol:SetSize(130, 480)

    -- Content area. Anchored to both corners, so it tracks the window size
    -- on its own while the grip is being dragged.
    area = CreateFrame("Frame", nil, window)
    area:SetPoint("TOPLEFT", window, "TOPLEFT", 146, -36)
    area:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -10, 46)
    W.Backdrop(area, 0.02, 0.03, 0.04, 0.6, 0.4)

    for i = 1, #TAB_DEFS do
        local def = TAB_DEFS[i]
        local scroll = W.ScrollArea(area)
        scroll:SetPoint("TOPLEFT", area, "TOPLEFT", 2, -2)
        scroll:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -2, 2)
        scroll:Hide()
        def.build(scroll.content)

        local b = W.Button(tabCol, def.label, 126, 26, function() SelectTab(def.key) end)
        b:SetPoint("TOPLEFT", tabCol, "TOPLEFT", 0, -(i - 1) * 30)

        tabs[i] = { key = def.key, scroll = scroll, button = b }
    end

    -- Bottom action bar
    local unlockBtn
    unlockBtn = W.Button(window, "Unlock frames", 130, 24, function(self)
        local newState = not ns.Engine.unlocked
        ns.Engine:SetUnlocked(newState)
        self:SetLabel(newState and "Lock frames" or "Unlock frames")
    end)
    unlockBtn:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 10, 12)

    local gridBtn = W.Button(window, "Grid", 70, 24, function()
        ns.Engine:ToggleGrid()
    end)
    gridBtn:SetPoint("LEFT", unlockBtn, "RIGHT", 6, 0)

    local testBtn = W.Button(window, "Test", 70, 24, function(self)
        local running = Options:ToggleTest()
        self:SetLabel(running and "Stop test" or "Test")
    end)
    testBtn:SetPoint("LEFT", gridBtn, "RIGHT", 6, 0)

    local okBtn = W.Button(window, "Okay", 100, 24, function()
        window:Hide()
    end)
    -- Kept clear of the resize grip in the corner.
    okBtn:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -26, 12)

    -- Resize from the bottom right corner; size and position are remembered.
    W.AddResizeGrip(window, MIN_W, MIN_H, MAX_W, MAX_H, function(w, h)
        ns.db.ui.width = math.floor(w + 0.5)
        ns.db.ui.height = math.floor(h + 0.5)
        ResizeContent()
    end)

    window:SetScript("OnSizeChanged", ResizeContent)

    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        local ui = ns.db.ui
        ui.point, ui.relPoint = point, relPoint
        ui.x, ui.y = math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5)
    end)

    ns.ApplyWindowGeometry()
    SelectTab("general")
end

function Options:Open()
    Build()
    window:Show()
    self:Refresh()
end

function Options:OpenTab(key)
    Build()
    SelectTab(key)
    window:Show()
    self:Refresh()
end

function Options:Close()
    if window then window:Hide() end
end

function Options:Toggle()
    Build()
    if window:IsShown() then window:Hide() else self:Open() end
end

function Options:Refresh()
    if not built then return end
    for i = 1, #widgets do
        local widget = widgets[i]
        if widget and widget.Refresh then
            widget:Refresh(widget)
        end
    end
end

function Options:Reset()
    -- Snapshot first. Reset has no undo, and the whole point of profiles is
    -- that you should never be one misclick away from losing your layout.
    local backup = ns.Profiles and ns.Profiles:SaveAuto("Before reset")

    local preset = ns.db.preset
    -- Survives the wipe: the only record of Blizzard's original CVar values.
    local cvars = ns.db.savedCVars
    wipe(ns.db)
    ns.fill(ns.db, ns.defaults)
    ns.db.preset = preset or "columns"
    ns.Presets:Apply(ns.db.preset)
    if type(cvars) == "table" then ns.db.savedCVars = cvars end
    ns.db.initialised = true
    ns.Engine:BuildAll()
    ns.ApplyWindowGeometry()
    self:Refresh()
    if backup then
        ns.Print("settings reset to defaults. Your previous setup was saved as the profile |cffffff00"
            .. backup .. "|r.")
    else
        ns.Print("settings reset to defaults.")
    end
end

--------------------------------------------------------------------------
-- Test mode
--------------------------------------------------------------------------

local testFrame = CreateFrame("Frame", "JCT_TestDriver")
testFrame:Hide()

local random = math.random

local TEST_SPELLS = {
    { id = 3044,  name = "Arcane Shot" },
    { id = 34120, name = "Steady Shot" },
    { id = 2643,  name = "Multi-Shot" },
    { id = 75,    name = "Auto Shot" },
    { id = 34026, name = "Kill Command" },
    { id = 1978,  name = "Serpent Sting" },
}

local function pick(t) return t[random(#t)] end

-- anchor = what the message is ABOUT, matching what the real combat log
-- paths pass. Notifications are a genuine mix: an interrupt is about the
-- thing you interrupted, a proc is about you.
local NOTIFY_SAMPLES = {
    { text = "Killing Blow: Training Dummy",   anchor = "target" },
    { text = "Interrupted: Frostbolt", spellID = 2139, anchor = "target" },
    { text = "Dispelled: Renew",       spellID = 527,  anchor = "target" },
    { text = "Quick Shots",            spellID = 6150, anchor = "player" },
    { text = "LOW HEALTH",                          anchor = "player" },
}
local ENEMY_SAMPLES = {
    { text = "Recklessness", spellID = 1719 },
    { text = "Ice Block", spellID = 45438 },
    { text = "Psychic Scream", spellID = 8122 },
    { text = "Bestial Wrath", spellID = 19574 },
}
local BREAK_SAMPLES = {
    { text = "PvP Trinket", spellID = 42292 },
    { text = "Escape Artist", spellID = 20589 },
    { text = "Will of the Forsaken", spellID = 7744 },
    { text = "Blessing of Freedom", spellID = 1044 },
}
-- Deliberately a mix of gains and losses, so tuning the state colours means
-- seeing both against each other rather than one at a time.
local STATE_SAMPLES = {
    { text = "Aspect of the Hawk",  spellID = 13165 },
    { text = "Aspect of the Viper", spellID = 34074 },
    { text = "Aspect of the Cheetah", spellID = 5118, lost = true },
    { text = "Berserker Stance",    spellID = 2458 },
    { text = "Seal of Command",     spellID = 20375, lost = true },
}
local REACTIVE_SAMPLES = {
    { text = "Mongoose Bite!", spellID = 1495 },
    { text = "Overpower!", spellID = 7384 },
    { text = "Execute!", spellID = 5308 },
}

-- class -> a plausible sample message
local SAMPLES = {
    outDamage   = function() local s = pick(TEST_SPELLS)
                      return random(300, 1400), { spellID = s.id, spellName = s.name, school = 1 }, "target" end,
    outMelee    = function() return random(200, 900), {}, "target" end,
    outAutoShot = function() return random(400, 1100), { spellID = 75, spellName = "Auto Shot" }, "target" end,
    outCrit     = function() local s = pick(TEST_SPELLS)
                      return random(1500, 4200), { crit = true, spellID = s.id, spellName = s.name, school = 1 }, "target" end,
    outDot      = function() return random(90, 260), { spellID = 1978, spellName = "Serpent Sting", school = 8 }, "target" end,
    outHeal     = function() return random(300, 900), {}, "player" end,
    outHealCrit = function() return random(900, 2000), { crit = true }, "player" end,
    outMiss     = function() return nil, { text = "Dodge" }, "target" end,
    petDamage   = function() return random(150, 700), { spellID = 34026, spellName = "Kill Command" }, "target" end,
    petCrit     = function() return random(700, 1600), { crit = true, spellID = 34026 }, "target" end,
    petHeal     = function() return random(100, 400), {}, "player" end,
    petMiss     = function() return nil, { text = "Miss" }, "target" end,
    inDamage    = function() return random(200, 1800), {}, "target" end,
    inCrit      = function() return random(1800, 3500), { crit = true }, "target" end,
    inHeal      = function() return random(500, 2600), {}, "player" end,
    inMiss      = function() return nil, { text = "Parry" }, "target" end,
    power       = function() return random(40, 300), { suffix = "Mana" }, "player" end,
    notify      = function() local s = pick(NOTIFY_SAMPLES)
                      return nil, { text = s.text, spellID = s.spellID }, s.anchor end,
    reactive    = function() local s = pick(REACTIVE_SAMPLES)
                      return nil, { text = s.text, spellID = s.spellID }, "player" end,
    state       = function() local s = pick(STATE_SAMPLES)
                      return nil, {
                          text       = s.lost and ("-" .. s.text) or s.text,
                          spellID    = s.spellID,
                          forceColor = s.lost and ns.db.colors.stateFade or nil,
                      }, "player" end,
    enemy       = function() local s = pick(ENEMY_SAMPLES)
                      return nil, { text = s.text, spellID = s.spellID }, "target" end,
    enemyBreak  = function() local s = pick(BREAK_SAMPLES)
                      return nil, { text = s.text, spellID = s.spellID }, "target" end,
}

-- Rough weighting for the background mix, so an untargeted test still looks
-- like a fight rather than an even spread of everything.
local MIX = {
    "outDamage", "outDamage", "outDamage", "outMelee", "outMelee", "outAutoShot",
    "outAutoShot", "outCrit", "outCrit", "outDot", "petDamage", "petDamage",
    "inDamage", "inDamage", "inHeal", "power", "outMiss", "notify", "reactive",
    "state", "enemy", "enemyBreak",
}

-- What is the user looking at right now? Test output is biased hard toward
-- it, because waiting twenty seconds for one notification to appear is no
-- way to tune a notification frame.
local function focusClasses()
    if not window or not window:IsShown() then return nil end
    local tab = Options.currentTab

    if tab == "enemies" then
        return { "enemy", "enemyBreak", "reactive" }
    elseif tab == "merge" then
        return { "outDamage", "outDot", "petDamage", "inDamage" }
    elseif tab == "layout" or tab == "routing" or tab == "colors" then
        -- Everything currently routed to the frame being edited. On the
        -- routing and colours tabs that is still the most useful bias.
        local target = Options.selectedFrame
        if tab ~= "layout" then return nil end
        local out = {}
        for i = 1, #ns.CLASSES do
            local key = ns.CLASSES[i].key
            if ns.db.routing[key] == target and SAMPLES[key] then
                out[#out + 1] = key
            end
        end
        if #out > 0 then return out end
    end
    return nil
end

testFrame:SetScript("OnUpdate", function(self, elapsed)
    self.acc = (self.acc or 0) + elapsed
    if self.acc < (self.next or 0.2) then return end
    self.acc = 0

    local focus = focusClasses()
    -- Fire the thing being tuned fast, and the background mix at a normal
    -- combat pace.
    self.next = focus and (random(90, 260) / 1000) or (random(80, 500) / 1000)

    local class
    if focus and random(100) <= 78 then
        class = focus[random(#focus)]
    else
        class = MIX[random(#MIX)]
    end

    local fn = SAMPLES[class]
    if not fn then return end
    local amount, info, anchorKind = fn()
    info = info or {}
    -- Resolve the anchor exactly as the real combat log paths do, so test
    -- mode cannot show a placement that never happens in play. Messages
    -- about YOU have no nameplate to attach to in TBC and will fall back,
    -- which is precisely what they do in a real fight.
    if anchorKind == "target" then
        info.anchorGUID = UnitGUID and UnitGUID("target") or nil
    elseif anchorKind == "player" then
        info.anchorGUID = ns.playerGUID
    end
    ns.Events.Display(class, amount, info)
end)

function Options:ToggleTest()
    if testFrame:IsShown() then
        testFrame:Hide()
        return false
    end
    if InCombatLockdown() then
        ns.Print("test mode is disabled in combat - you already have real numbers to look at.")
        return false
    end
    testFrame:Show()
    ns.Print("test mode on. Output follows whichever tab you are on - the Layout tab "
        .. "targets the frame you are editing, the Enemies tab fires enemy alerts. "
        .. "Run |cffffff00/jct test|r again to stop.")
    return true
end

--------------------------------------------------------------------------
-- /jct debug
--
-- Everything I would otherwise ask you to check by hand, printed in one go.
-- Every lookup is guarded, so this is safe to run on any client.
--------------------------------------------------------------------------

local function yesno(v, goodIsTrue)
    local good = goodIsTrue == false and (not v) or (goodIsTrue ~= false and v)
    local color = good and "|cff55ff55" or "|cffff8855"
    return color .. (v and "yes" or "no") .. "|r"
end

local function exists(v)
    return (v ~= nil) and "|cff55ff55present|r" or "|cffff8855absent|r"
end

function Options:Debug()
    local out = function(label, value)
        print("  |cff9d9d9d" .. label .. "|r  " .. tostring(value))
    end

    print("|cff7fbfffJCT diagnostics|r  (addon v" .. tostring(ns.version) .. ")")

    -- Client -------------------------------------------------------------
    local version, build, date, toc
    if GetBuildInfo then
        local ok, a, b, c, d = pcall(GetBuildInfo)
        if ok then version, build, date, toc = a, b, c, d end
    end
    out("client", tostring(version) .. " build " .. tostring(build)
        .. "   interface |cffffff00" .. tostring(toc) .. "|r")
    if toc and tonumber(toc) and tonumber(toc) ~= 20506 then
        print("  |cffff8855note|r  JCT.toc declares 20506. Change it to "
              .. tostring(toc) .. " to clear the out-of-date flag.")
    end

    -- API ----------------------------------------------------------------
    out("CombatLogGetCurrentEventInfo", exists(CombatLogGetCurrentEventInfo))
    out("combat log registered", yesno(
        ns.Events.frame and ns.Events.frame:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED")))
    out("C_CombatText", exists(C_CombatText))
    out("combat text info fn", exists(ns.compat.GetCombatTextInfo))
    out("C_Timer", exists(C_Timer))
    out("options system", (Settings and Settings.RegisterCanvasLayoutCategory)
        and "modern Settings API"
        or (InterfaceOptions_AddCategory and "legacy InterfaceOptions" or "|cffff8855neither|r"))

    -- CVars --------------------------------------------------------------
    print("  |cff9d9d9dcombat text CVars|r")
    local function showCVar(base)
        local name = ns.ResolveCVar and ns.ResolveCVar(base) or base
        if not name then
            print("    " .. base .. "  |cff707070not on this client|r")
            return
        end
        local value = ns.compat.GetCVar(name)
        local good = (value == "0")
        print("    " .. name .. " = " .. (good and "|cff55ff55" or "|cffff8855")
              .. tostring(value) .. "|r")
    end
    local raw = ns.compat.GetCVar("enableFloatingCombatText")
    print("    enableFloatingCombatText = " .. ((raw == "0") and "|cff55ff55" or "|cffff8855")
          .. tostring(raw) .. "|r")
    showCVar("floatingCombatTextCombatDamage")
    showCVar("floatingCombatTextCombatHealing")
    showCVar("floatingCombatTextPetMeleeDamage")
    showCVar("floatingCombatTextPetSpellDamage")
    showCVar("floatingCombatTextCombatLogPeriodicSpells")
    print("    |cff707070(0 = suppressed, which is what you want while JCT is on)|r")

    -- Addon state --------------------------------------------------------
    local built, enabled = 0, {}
    for i = 1, #ns.FRAME_ORDER do
        local name = ns.FRAME_ORDER[i]
        if ns.Engine.frames[name] then built = built + 1 end
        if ns.db.frames[name] and ns.db.frames[name].enabled then
            enabled[#enabled + 1] = name
        end
    end
    out("preset", tostring(ns.db.preset))
    out("frames built", built .. " of " .. #ns.FRAME_ORDER)
    out("frames enabled", table.concat(enabled, ", "))
    out("font", tostring(ns.db.general.font) .. "  ->  " .. tostring(ns.FontPath(ns.db.general.font)))
    out("addon enabled", yesno(ns.db.enabled))
    out("suppressing Blizzard", yesno(ns.db.suppressBlizzard))

    -- Spell data ---------------------------------------------------------
    local resolved = 0
    for _ in pairs(ns.enemyByName) do resolved = resolved + 1 end
    out("enemy alert spells", resolved .. " resolved, "
        .. #ns.enemyUnresolved .. " failed"
        .. (#ns.enemyUnresolved > 0 and "  |cffff8855(/jct spells)|r" or ""))
    out("reactives detected", ns.ReactiveSummary())
    out("nameplate API", yesno(ns.Nameplates and ns.Nameplates.available))
    out("nameplates tracked", ns.Nameplates and ns.Nameplates:Tracked() or 0)
    out("target / focus", tostring(ns.targetGUID and "set" or "none")
        .. " / " .. tostring(ns.focusGUID and "set" or "none"))

    -- Traffic ------------------------------------------------------------
    local s = ns.Events.stats
    out("combat events involving you", s.relevant)
    out("messages drawn", s.shown)
    if s.relevant > 0 and s.shown == 0 then
        print("  |cffff5555Events are arriving but nothing is being drawn.|r"
              .. " Check the Filters tab, and that the frames your streams route to are enabled.")
    elseif s.relevant == 0 then
        print("  |cff9d9d9dNo combat events counted yet - hit something and run this again.|r")
    end

    -- Presets ------------------------------------------------------------
    ns.Presets:Verify()
end

--------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------

local function HandleSlash(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S*)%s*(.*)$")

    if cmd == "" or cmd == "config" or cmd == "options" then
        Options:Toggle()

    elseif cmd == "unlock" then
        ns.Engine:SetUnlocked(true)
        ns.Print("frames unlocked. Drag them, then |cffffff00/jct lock|r.")

    elseif cmd == "lock" then
        ns.Engine:SetUnlocked(false)
        ns.Print("frames locked.")

    elseif cmd == "grid" then
        ns.Engine:ToggleGrid()

    elseif cmd == "test" then
        Options:ToggleTest()

    elseif cmd == "preset" then
        if ns.Presets.list[rest] then
            ns.Presets:Apply(rest)
            ns.Print("preset set to " .. rest .. ".")
        else
            local names = {}
            for i = 1, #ns.Presets.order do names[#names + 1] = ns.Presets.order[i] end
            ns.Print("presets: " .. table.concat(names, ", "))
        end

    elseif cmd == "block" then
        local id = tonumber(rest)
        if id then
            ns.db.filters.blacklist[id] = true
            ns.Print("blocked spell " .. id .. ".")
        else
            ns.Print("usage: /jct block <spellID>")
        end

    elseif cmd == "unblock" then
        local id = tonumber(rest)
        if id then
            ns.db.filters.blacklist[id] = nil
            ns.Print("unblocked spell " .. id .. ".")
        end

    elseif cmd == "debug" or cmd == "diag" then
        Options:Debug()

    elseif cmd == "spells" then
        local u = #ns.unknownAbilities
        if u > 0 then
            ns.Print("|cffff8855" .. u .. " reactive/conditional/state ability ID(s) did not resolve:|r")
            for i = 1, u do print("    " .. tostring(ns.unknownAbilities[i])) end
        end
        ns.Print("reactive and conditional abilities on this character: " .. ns.ReactiveSummary())
        local states = 0
        for _ in pairs(ns.stateByName or {}) do states = states + 1 end
        ns.Print("tracked states (stances, aspects, forms, seals): " .. states)
        local n = #ns.enemyUnresolved
        if n == 0 then
            ns.Print("every curated enemy spell ID resolved cleanly.")
        else
            ns.Print("|cffff8855" .. n .. " spell ID(s) did not resolve on this client:|r")
            for i = 1, n do
                print("    " .. tostring(ns.enemyUnresolved[i]))
            end
            ns.Print("those alerts will never fire. Send me the list and I'll correct them.")
        end

    elseif cmd == "profile" then
        local sub, arg = rest:match("^(%S*)%s*(.*)$")
        if sub == "save" then
            local ok, err = ns.Profiles:Save(arg)
            ns.Print(ok and ("saved profile |cffffff00" .. arg .. "|r.") or err)
        elseif sub == "load" then
            local ok, err = ns.Profiles:Load(arg)
            ns.Print(ok and ("loaded profile |cffffff00" .. arg .. "|r.") or err)
        elseif sub == "delete" then
            local ok, err = ns.Profiles:Delete(arg)
            ns.Print(ok and ("deleted profile |cffffff00" .. arg .. "|r.") or err)
        else
            local names = ns.Profiles:List()
            if #names == 0 then
                ns.Print("no profiles saved yet. |cffffff00/jct profile save <name>|r")
            else
                ns.Print("profiles: " .. table.concat(names, ", "))
            end
        end
        Options:Refresh()

    elseif cmd == "export" or cmd == "import" or cmd == "share" then
        -- Both live in the same place, and an export string is far too long
        -- to paste into a chat command anyway.
        Options:OpenTab("profiles")
        ns.Print("export and import are at the bottom of the Profiles tab.")

    elseif cmd == "verify" then
        ns.Presets:Verify()

    elseif cmd == "reset" then
        Options:Reset()

    elseif cmd == "on" then
        ns.db.enabled = true
        ns.Print("enabled.")

    elseif cmd == "off" then
        ns.db.enabled = false
        ns.Engine:ClearAll()
        ns.Print("disabled.")

    else
        ns.Print("commands: |cffffff00/jct|r (options), unlock, lock, grid, test, preset <name>, profile save|load|delete <name>, export, block <id>, unblock <id>, debug, spells, verify, reset, on, off")
    end
end

--------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------

local ADDON_TITLE = "Jabe's Combat Text"

-- Shuts whichever options UI this client uses, so selecting the entry in
-- Options -> AddOns hands straight over to the real window rather than
-- leaving it stacked behind Blizzard's panel.
local function CloseBlizzardOptions()
    if Settings and Settings.CloseUI then
        pcall(Settings.CloseUI)
    elseif _G.InterfaceOptionsFrame and _G.HideUIPanel then
        pcall(_G.HideUIPanel, _G.InterfaceOptionsFrame)
    elseif _G.InterfaceOptionsFrame then
        pcall(_G.InterfaceOptionsFrame.Hide, _G.InterfaceOptionsFrame)
    end
end

function Options:Init()
    SLASH_JCT1 = "/jct"
    SLASH_JCT2 = "/jabescombattext"
    SlashCmdList["JCT"] = HandleSlash

    -- Stub for the Options -> AddOns list. Selecting it just opens the real
    -- window, which is the same thing /jct does.
    local panel = CreateFrame("Frame")
    panel.name = ADDON_TITLE

    local title = panel:CreateFontString(nil, "ARTWORK")
    ns.SafeSetFont(title, [[Fonts\FRIZQT__.TTF]], 16, "OUTLINE")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(ADDON_TITLE)

    local note = panel:CreateFontString(nil, "ARTWORK")
    ns.SafeSetFont(note, [[Fonts\FRIZQT__.TTF]], 12, "")
    note:SetPoint("TOPLEFT", 16, -44)
    note:SetTextColor(0.7, 0.7, 0.7)
    note:SetText("Opens the configuration window. You can also type /jct.")

    local btn = CreateFrame("Button", nil, panel)
    btn:SetSize(220, 26)
    btn:SetPoint("TOPLEFT", 16, -74)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(btn)
    if bg.SetColorTexture then bg:SetColorTexture(0.16, 0.18, 0.22, 1) else bg:SetTexture(0.16, 0.18, 0.22, 1) end
    local btext = btn:CreateFontString(nil, "OVERLAY")
    ns.SafeSetFont(btext, [[Fonts\FRIZQT__.TTF]], 13, "")
    btext:SetPoint("CENTER")
    btext:SetText("Open " .. ADDON_TITLE)
    btn:SetScript("OnClick", function()
        CloseBlizzardOptions()
        Options:Open()
    end)

    -- Selecting the category in the AddOns list opens the window directly.
    -- Deferred a frame: closing the options UI from inside its own OnShow
    -- runs while Blizzard is still mid-layout.
    panel:SetScript("OnShow", function()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                CloseBlizzardOptions()
                Options:Open()
            end)
        else
            Options:Open()
        end
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, ADDON_TITLE)
        if ok and category then
            pcall(Settings.RegisterAddOnCategory, category)
            Options.settingsCategory = category
        end
    elseif InterfaceOptions_AddCategory then
        pcall(InterfaceOptions_AddCategory, panel)
    end
end
