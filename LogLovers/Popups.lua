-- LogLovers Popups: context menus, hover tooltips, spell inspector
local ADDON, NS = ...

local C = NS.C

-------------------------------------------------------------------------------
-- Lightweight context menu
-------------------------------------------------------------------------------
local menu, catcher
local menuButtons = {}

local function ensureMenu()
    if menu then return end
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    catcher:SetScript("OnClick", function() NS.CloseMenu() end)
    catcher:Hide()

    menu = CreateFrame("Frame", "LogLoversMenu", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(catcher:GetFrameLevel() + 5)
    NS.SkinPanel(menu, { r = 0.065, g = 0.05, b = 0.032, a = 0.97 })
    menu:EnableMouseWheel(true)
    menu:SetScript("OnMouseWheel", function(_, delta)
        -- shift pages, for the hundred-entry sound lists LibSharedMedia makes
        local step = (IsShiftKeyDown and IsShiftKeyDown()) and 15 or 3
        if NS.ScrollMenu then NS.ScrollMenu(delta > 0 and -step or step) end
    end)
    menu:Hide()
end

function NS.CloseMenu()
    if menu then menu:Hide() end
    if catcher then catcher:Hide() end
end

-- LibSharedMedia can contribute a hundred sounds, so a menu can easily be
-- taller than the screen. Anything past what fits scrolls with the wheel.
local currentItems, menuScroll, pinnedHeader = nil, 0, nil

local function maxMenuRows()
    local h = (UIParent and UIParent:GetHeight()) or 768
    return math.max(6, math.floor((h - 80) / 18))
end

-- Builds the list actually drawn: a pinned header, then the scrolled window,
-- with "more above/below" markers so it is obvious the list continues.
local function visibleItems()
    local items = currentItems or {}
    local body, header = items, nil
    if items[1] and items[1].header then
        header = items[1]
        body = {}
        for i = 2, #items do body[#body + 1] = items[i] end
    end
    pinnedHeader = header

    local rows = maxMenuRows() - (header and 1 or 0)
    if #body <= rows then
        menuScroll = 0
        local out = {}
        if header then out[1] = header end
        for _, it in ipairs(body) do out[#out + 1] = it end
        return out, false
    end

    -- two rows go to the markers
    local window = rows - 2
    local maxScroll = #body - window
    if menuScroll > maxScroll then menuScroll = maxScroll end
    if menuScroll < 0 then menuScroll = 0 end

    local out = {}
    if header then out[1] = header end
    out[#out + 1] = {
        text = menuScroll > 0 and ("^  " .. menuScroll .. " more above") or "  scroll for more",
        disabled = true,
    }
    for i = menuScroll + 1, menuScroll + window do
        out[#out + 1] = body[i]
    end
    local below = #body - (menuScroll + window)
    out[#out + 1] = {
        text = below > 0 and ("v  " .. below .. " more below") or "  end of list",
        disabled = true,
    }
    return out, true
end

-- items: { { text=, func=, header=, disabled=, checked= } ... }
local function layoutMenu()
    for _, b in ipairs(menuButtons) do b:Hide() end
    local items = visibleItems()

    local width, y = 120, -6
    for i, item in ipairs(items) do
        local b = menuButtons[i]
        if not b then
            b = CreateFrame("Button", nil, menu)
            b:SetHeight(18)
            b.text = b:CreateFontString(nil, "OVERLAY")
            b.text:SetPoint("LEFT", 10, 0)
            -- bounded on both sides so a very long name truncates instead of
            -- spilling out past the menu's edge
            b.text:SetPoint("RIGHT", -10, 0)
            b.text:SetJustifyH("LEFT")
            b.text:SetWordWrap(false)
            b.hl = b:CreateTexture(nil, "HIGHLIGHT")
            b.hl:SetAllPoints()
            b.hl:SetColorTexture(NS.ACCENT.r, NS.ACCENT.g, NS.ACCENT.b, 0.10)
            menuButtons[i] = b
        end
        b.text:SetFont(NS.CurrentFont(), 11, "")
        b:SetPoint("TOPLEFT", 1, y)
        b:SetPoint("TOPRIGHT", -1, y)
        if not b.rule then
            b.rule = b:CreateTexture(nil, "ARTWORK")
            b.rule:SetHeight(1)
            b.rule:SetPoint("LEFT", 8, 0)
            b.rule:SetPoint("RIGHT", -8, 0)
            b.rule:SetColorTexture(NS.ACCENT.r, NS.ACCENT.g, NS.ACCENT.b, 0.30)
        end
        b.rule:SetShown(item.separator and true or false)
        if item.separator then
            b.text:SetText("")
            b:SetScript("OnClick", nil)
            b:EnableMouse(false)
            b:SetHeight(9)
            b:Show()
            y = y - 9
        elseif item.header then
            b.text:SetText(C(item.text, NS.COLORS.accent))
            b:SetScript("OnClick", nil)
            b:EnableMouse(false)
        elseif item.disabled then
            b.text:SetText(C(item.text, item.hex or "555b63"))
            b:SetScript("OnClick", nil)
            b:EnableMouse(false)
        else
            local mark = item.checked and C("+ ", NS.COLORS.buff) or ""
            b.text:SetText(mark .. C(item.text, NS.COLORS.text))
            b:EnableMouse(true)
            b:SetScript("OnClick", function()
                NS.CloseMenu()
                if item.func then item.func() end
            end)
        end
        if not item.separator then
            b:SetHeight(18)
            b:Show()
            local w = b.text:GetStringWidth() + 24
            if w > width then width = w end
            y = y - 18
        end
    end

    local menuH = -y + 6
    menu:SetSize(math.min(width, 460), menuH)
    menu.llRows = #items
    return menuH
end

-- How many rows the menu is currently drawing, and how far it is scrolled.
-- Used by the test harness to prove a long list is windowed rather than run
-- off the screen.
function NS.MenuState()
    if not menu then return 0, 0 end
    return menu.llRows or 0, menuScroll
end

-- Re-draws in place while scrolling: the anchor is left alone so the menu does
-- not walk across the screen under the cursor.
function NS.ScrollMenu(delta)
    if not currentItems or not menu or not menu:IsShown() then return end
    menuScroll = menuScroll + delta
    layoutMenu()
end

function NS.ShowMenu(items)
    ensureMenu()
    currentItems, menuScroll = items, 0
    local menuH = layoutMenu()
    local width = menu:GetWidth() or 120

    local scale = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    local sw = UIParent:GetWidth() or 1024
    local sh = UIParent:GetHeight() or 768
    local mx = math.min(math.max(cx + 4, 4), sw - width - 8)  -- keep on screen sideways

    -- Vertically: prefer opening downward from the cursor, flip up when there
    -- is no room, and clamp so the menu can never run off either edge - a tall
    -- LSM list used to have its top half cut away.
    local top
    if cy >= menuH + 12 then
        top = cy - 4                 -- opens downward
    elseif (sh - cy) >= menuH + 12 then
        top = cy + menuH + 6         -- opens upward
    else
        top = math.min(sh - 6, menuH + 6)
    end
    top = math.max(math.min(top, sh - 6), menuH + 6)

    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", mx, top)
    catcher:Show()
    menu:Show()
end

-------------------------------------------------------------------------------
-- Hover tooltips
-------------------------------------------------------------------------------
local function unitHoverStats(guid)
    local dmg, heal, taken, deaths = 0, 0, 0, 0
    local segIdx = NS.currentSegment and NS.currentSegment.index
        or (#NS.segments > 0 and NS.segments[#NS.segments].index)
    if not segIdx then segIdx = nil end
    NS.BufferEach(function(rec)
        if segIdx and rec.segIndex ~= segIdx then return end
        if rec.cat == "damage" then
            if rec.sg == guid then dmg = dmg + (rec.amt or 0) end
            if rec.dg == guid then taken = taken + (rec.amt or 0) end
        elseif rec.cat == "healing" and rec.sg == guid then
            heal = heal + (rec.amt or 0) - (rec.over or 0)
        elseif rec.sub == "UNIT_DIED" and rec.dg == guid and not rec.feign then
            deaths = deaths + 1
        end
    end)
    return dmg, heal, taken, deaths, segIdx ~= nil
end

function NS.HandleLinkEnter(frame, link)
    local kind, rest = link:match("^(%a+):(.*)$")
    if kind == "spell" then
        local id = tonumber(rest:match("^(%d+)"))
        if id then
            GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
            GameTooltip:SetHyperlink("spell:" .. id)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(C("Spell ID ", NS.COLORS.dim) .. C(tostring(id), NS.COLORS.accent) ..
                C("  |  click for actions", NS.COLORS.dim), 1, 1, 1)
            GameTooltip:Show()
        end
    elseif kind == "llu" then
        local guid, name = rest:match("^([^:]+):(.+)$")
        if not guid then return end
        GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
        GameTooltip:SetText(name, 1, 1, 1)
        local class = NS.ClassOf(guid)
        if class then
            local cc = RAID_CLASS_COLORS[class]
            GameTooltip:AddLine(class:sub(1, 1) .. class:sub(2):lower(), cc.r, cc.g, cc.b)
        end
        local dmg, heal, taken, deaths, isSeg = unitHoverStats(guid)
        local scope = isSeg and "This fight" or "Overall"
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(C(scope .. " damage", NS.COLORS.dim), NS.FormatNumber(dmg), 1, 1, 1, 1, 0.8, 0.4)
        GameTooltip:AddDoubleLine(C("Healing", NS.COLORS.dim), NS.FormatNumber(heal), 1, 1, 1, 0.5, 0.93, 0.6)
        GameTooltip:AddDoubleLine(C("Damage taken", NS.COLORS.dim), NS.FormatNumber(taken), 1, 1, 1, 1, 0.5, 0.5)
        if deaths > 0 then
            GameTooltip:AddDoubleLine(C("Deaths", NS.COLORS.dim), deaths, 1, 1, 1, 1, 0.3, 0.3)
        end
        GameTooltip:AddLine(C("click for actions", NS.COLORS.dim))
        GameTooltip:Show()
    elseif kind == "lld" then
        GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
        GameTooltip:SetText("Death recap", 1, 0.4, 0.4)
        GameTooltip:AddLine(C("Click to open the timeline of this death.", NS.COLORS.dim))
        GameTooltip:Show()
    elseif kind == "item" then
        GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
        pcall(GameTooltip.SetHyperlink, GameTooltip, link)
        GameTooltip:Show()
    end
end

-------------------------------------------------------------------------------
-- Player info block
--
-- Shared by the chat name menu and the combat log unit menu, so shift-clicking
-- a name anywhere shows the same thing above the usual actions.
-------------------------------------------------------------------------------
-- autoLookup: run the /who straight away rather than offering it as a second
-- click. Opening this menu IS the request to look somebody up, so making the
-- user then find and click "Look them up" was a click for nothing.
function NS.PlayerInfoItems(name, rebuild, autoLookup)
    local items = {}
    if not NS.PLAYERS then return items end

    for _, line in ipairs(NS.PLAYERS.InfoLines(name)) do
        items[#items + 1] = { text = line.text, disabled = true, hex = line.hex }
    end

    local p = NS.PLAYERS.Get(name, false)
    local age = NS.PLAYERS.WhoAge(p)
    -- worth looking up when we have never done one, or the answer is old
    -- enough that their zone is probably wrong now
    local stale = (not age) or age > 300

    local function sendWho(quiet)
        return NS.PLAYERS.RequestWho(name, function(_, found)
            if (found or 0) == 0 then
                NS.Print(name .. " is not online, or is hidden from /who.")
            elseif rebuild then
                rebuild()
            end
        end)
    end

    if stale and autoLookup then
        local ok, err = sendWho(true)
        if ok then
            items[#items + 1] = {
                text = age and "Refreshing their details..." or "Looking them up...",
                disabled = true, hex = NS.COLORS.dim,
            }
        else
            -- the /who is on cooldown or unavailable; leave them a way to retry
            items[#items + 1] = {
                text = "Look them up (/who)",
                func = function()
                    local ok2, err2 = sendWho()
                    if not ok2 then NS.Print(err2 or err or "could not look them up.") end
                end,
            }
        end
    elseif stale then
        items[#items + 1] = {
            text = age and "Refresh their details (/who)" or "Look them up (/who)",
            func = function()
                local ok, err = sendWho()
                if not ok then NS.Print(err or "could not look them up.") end
            end,
        }
    end

    items[#items + 1] = {
        text = (p and p.note) and "Edit note" or "Add a note",
        func = function() NS.EditPlayerNote(name) end,
    }
    if p and p.lastTradeAt then
        items[#items + 1] = { text = "What we last traded", func = function()
            NS.ShowCopyText("Trade with " .. (p.name or name),
                NS.PLAYERS.LastTradeText(name) or "")
        end }
    end
    if p then
        items[#items + 1] = { text = "Forget what I know about them", func = function()
            NS.PLAYERS.Forget(name)
            NS.Print("forgot everything about " .. name .. ".")
        end }
    end

    items[#items + 1] = { separator = true }
    return items
end

function NS.EditPlayerNote(name)
    local p = NS.PLAYERS and NS.PLAYERS.Get(name, false)
    NS.ShowInputBox("Note about " .. name, p and p.note or "", function(text)
        NS.PLAYERS.SetNote(name, text)
        if text and text ~= "" then
            NS.Print("noted: " .. name .. " - " .. text)
        else
            NS.Print("cleared the note on " .. name .. ".")
        end
    end)
end

-------------------------------------------------------------------------------
-- Click actions
-------------------------------------------------------------------------------
local function spellMenu(win, sid, sname)
    local lower = string.lower(sname)
    local hl = NS.db.highlights[lower]
    if type(hl) ~= "table" then hl = nil end
    local cfg = win.cfg
    local items = {
        { text = sname, header = true },
        { text = "Spell details", func = function() NS.OpenSpellInspector(sid, sname) end },
    }

    -- one-click escape from a zone buff you are sick of seeing. Only offered
    -- for spells actually seen as a buff or debuff, since that is all the
    -- hidden-aura list affects.
    if (NS.auraOnly and NS.auraOnly[lower]) or NS.AuraHidden(sname) then
        local hidden = NS.AuraHidden(sname)
        table.insert(items, {
            text = hidden and "Show this buff/debuff again" or "Hide this buff/debuff everywhere",
            checked = hidden,
            func = function()
                NS.ToggleAuraHidden(sname)
                NS.Print((hidden and "showing " or "hiding ") .. sname ..
                    " in every combat window.")
            end,
        })
        table.insert(items, { separator = true })
    end

    for _, extra in ipairs({
        { text = "Only this spell (this window)", func = function()
            cfg.filter.spellMode = "allow"
            cfg.filter.spellList = { [lower] = true }
            NS.RefreshWindow(win)
        end },
        { text = "Hide this spell (this window)", func = function()
            if cfg.filter.spellMode ~= "block" then
                cfg.filter.spellMode = "block"
                cfg.filter.spellList = {}
            end
            cfg.filter.spellList[lower] = true
            NS.RefreshWindow(win)
        end },
        { text = "New window for this spell", func = function()
            local idx = NS.AddWindow(sname, "everything")
            local f = NS.db.windows[idx].filter
            f.spellMode = "allow"
            f.spellList = { [lower] = true }
            NS.RefreshWindow(NS.windows[idx])
        end },
        { text = hl and "Remove highlight" or "Highlight this spell", checked = hl ~= nil,
          func = function()
            if hl then NS.db.highlights[lower] = nil
            else NS.db.highlights[lower] = { color = NS.COLORS.highlight } end
            NS.ApplyAppearance()
        end },
        { text = "Link to chat", func = function()
            local link = sid and NS.GetSpellLink(sid)
            if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
        end },
        { text = "Reset spell filter (this window)", func = function()
            cfg.filter.spellMode = "off"
            cfg.filter.spellList = {}
            NS.RefreshWindow(win)
        end },
    }) do
        items[#items + 1] = extra
    end

    NS.ShowMenu(items)
end

local function unitMenu(win, guid, name)
    local lower = string.lower(name)
    local cfg = win.cfg
    local death = NS.FindLastDeath and NS.FindLastDeath(guid)
    local isPlayer = guid and guid:find("^Player") and true or false

    local items = { { text = name, header = true } }
    -- same info block as the chat menu, but only for real players
    if isPlayer and NS.PlayerInfoItems then
        for _, it in ipairs(NS.PlayerInfoItems(name,
                function() unitMenu(win, guid, name) end, true)) do
            items[#items + 1] = it
        end
    end

    for _, extra in ipairs({
        { text = "Only FROM " .. name .. " (this window)", checked = cfg.filter.srcName == lower,
          func = function()
            cfg.filter.srcName = (cfg.filter.srcName == lower) and nil or lower
            NS.RefreshWindow(win)
        end },
        { text = "Only TO " .. name .. " (this window)", checked = cfg.filter.dstName == lower,
          func = function()
            cfg.filter.dstName = (cfg.filter.dstName == lower) and nil or lower
            NS.RefreshWindow(win)
        end },
        { text = "Clear unit focus", disabled = not (cfg.filter.srcName or cfg.filter.dstName),
          func = function()
            cfg.filter.srcName, cfg.filter.dstName = nil, nil
            NS.RefreshWindow(win)
        end },
        { text = "New window focused on " .. name, func = function()
            local idx = NS.AddWindow(name, "everything")
            NS.db.windows[idx].filter.srcName = lower
            NS.RefreshWindow(NS.windows[idx])
        end },
        { text = "Open stats browser", func = function() NS.ToggleStats(true) end },
    }) do
        items[#items + 1] = extra
    end
    if isPlayer then
        table.insert(items, { text = "Whisper " .. name, func = function()
            NS.StartWhisper(name)
        end })
    end
    if death then
        table.insert(items, { text = "Death recap (" .. name .. ")",
            func = function() NS.OpenDeathRecap(death) end })
    end
    NS.ShowMenu(items)
end

function NS.HandleLinkClick(win, link, text, button)
    -- The fight-log pop-out has no combat window behind it, but the spell and
    -- unit menus both offer "filter this window" actions. Borrow the first
    -- combat window for those so the menus still work from anywhere.
    win = win or (NS.windows and NS.windows[1])
    if not win or not win.cfg then return end
    local kind, rest = link:match("^(%a+):(.*)$")
    if kind == "spell" then
        local id = tonumber(rest:match("^(%d+)"))
        local name = text and text:match("%[(.-)%]") or (id and GetSpellInfo and GetSpellInfo(id)) or "?"
        if IsShiftKeyDown() then
            local slink = id and NS.GetSpellLink(id)
            if slink and ChatEdit_InsertLink then ChatEdit_InsertLink(slink) end
            return
        end
        spellMenu(win, id, name)
    elseif kind == "llu" then
        local guid, name = rest:match("^([^:]+):(.+)$")
        if not guid then return end
        -- same as in chat: shift is the lookup, printed straight into chat
        if IsShiftKeyDown and IsShiftKeyDown() and guid:find("^Player")
            and NS.PLAYERS and NS.PLAYERS.LookupToChat then
            NS.PLAYERS.LookupToChat(name)
        else
            unitMenu(win, guid, name)
        end
    elseif kind == "lld" then
        local idx = tonumber(rest)
        if idx then NS.OpenDeathRecapByIndex(idx) end
    elseif kind == "item" or kind == "quest" or kind == "enchant"
        or kind == "talent" or kind == "achievement" or kind == "currency" then
        -- `text` is already a complete hyperlink; wrapping it in another
        -- |H..|h yields an invalid escape code when the line is sent to chat
        local full = text
        if not full or not full:find("|H", 1, true) then
            full = "|H" .. link .. "|h" .. (text or "[link]") .. "|h"
        end
        if IsShiftKeyDown() then
            if ChatEdit_InsertLink then ChatEdit_InsertLink(full) end
        elseif SetItemRef then
            pcall(SetItemRef, link, full, button or "LeftButton")
        end
    end
end

-------------------------------------------------------------------------------
-- Preset menu / window title menu
-------------------------------------------------------------------------------
function NS.ShowPresetMenu(callback)
    local items = { { text = "New window preset", header = true } }
    for _, p in ipairs(NS.WINDOW_PRESETS) do
        table.insert(items, { text = p.label, func = function() callback(p.key, p.label) end })
    end
    NS.ShowMenu(items)
end

local function dialogEditBox(dialog)
    -- 2.5.6 modern StaticPopup uses dialog:GetEditBox(); older clients use .editBox
    if dialog.GetEditBox then return dialog:GetEditBox() end
    return dialog.editBox
end

StaticPopupDialogs["LogLovers_RENAME_WINDOW"] = {
    text = "Rename window",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function(self, data)
        local eb = dialogEditBox(self)
        local txt = eb and eb:GetText()
        if txt and txt ~= "" and data and NS.db.windows[data] then
            NS.db.windows[data].name = txt
            NS.UpdateWindowTitle(data)
        end
    end,
    OnShow = function(self, data)
        local eb = dialogEditBox(self)
        if eb and data and NS.db.windows[data] then
            eb:SetText(NS.db.windows[data].name)
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["LogLovers_RENAME_WINDOW"].OnAccept(parent, parent.data)
        parent:Hide()
    end,
}

-- Generic "type something" box. The prompt and callback live on the dialog
-- table because StaticPopup only carries one opaque data value.
local inputInitial, inputCallback

StaticPopupDialogs["LogLovers_INPUT"] = {
    text = "%s",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    maxLetters = 200,
    timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function(self)
        local eb = dialogEditBox(self)
        if inputCallback then inputCallback(eb and eb:GetText() or "") end
        inputCallback = nil
    end,
    OnCancel = function() inputCallback = nil end,
    OnShow = function(self)
        local eb = dialogEditBox(self)
        if eb then
            eb:SetText(inputInitial or "")
            eb:HighlightText()
            eb:SetFocus()
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["LogLovers_INPUT"].OnAccept(parent)
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        inputCallback = nil
        self:GetParent():Hide()
    end,
}

function NS.ShowInputBox(prompt, initial, onAccept)
    inputInitial, inputCallback = initial, onAccept
    StaticPopup_Show("LogLovers_INPUT", prompt)
end

StaticPopupDialogs["LogLovers_DELETE_WINDOW"] = {
    text = "Delete window \"%s\"? This cannot be undone.",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function(self, data)
        if data then NS.DeleteWindow(data) end
    end,
}

-- The menu items, separated from showing them, so a test can click one.
function NS.WindowMenuItems(index)
    local win = NS.windows and NS.windows[index]
    if not win then return nil end
    local captured
    local realShow = NS.ShowMenu
    NS.ShowMenu = function(items) captured = items end
    pcall(NS.ShowWindowMenu, win)
    NS.ShowMenu = realShow
    return captured
end

function NS.ShowWindowMenu(win)
    local cfg = win.cfg
    NS.ShowMenu({
        { text = cfg.name, header = true },
        { text = "Rename...", func = function()
            StaticPopup_Show("LogLovers_RENAME_WINDOW", nil, nil, win.index)
        end },
        { text = cfg.locked and "Unlock" or "Lock", checked = cfg.locked, func = function()
            NS.SetWindowLocked(win.index, not cfg.locked)
        end },
        { text = "Click-through text", checked = cfg.clickThrough, func = function()
            NS.SetWindowClickThrough(win.index, not cfg.clickThrough)
        end },
        { text = "Only me & my pet", checked = NS.EffectiveScope(cfg.filter) ~= "all",
          func = function()
            -- this used to write the pre-1.3 "scope" field, which nothing has
            -- read since the per-place model landed - the item was a no-op and
            -- its checkmark never moved
            local wide = (NS.EffectiveScope(cfg.filter) == "all")
            -- a filter imported from an old profile may predate the per-place
            -- model entirely
            cfg.filter.scopes = cfg.filter.scopes or NS.DeepCopy(NS.DEFAULT_SCOPES)
            for _, loc in ipairs(NS.LOCATIONS) do
                cfg.filter.scopes[loc.key] = wide and "me" or "all"
            end
            cfg.filter.scope, cfg.filter.involve = nil, nil
            NS.RefreshWindow(win)
        end },
        { text = "Window options...", func = function() NS.OpenOptionsForWindow(win.index) end },
        { text = "Dock into chat as a tab", func = function()
            if NS.DockCombatWindowAsTab then NS.DockCombatWindowAsTab(win.index) end
        end },
        { text = "Copy / export...", func = function() NS.OpenCopy(win.index) end },
        { text = "New window...", func = function() NS.CreateWindowInteractive() end },
        { text = "Hide window", func = function() cfg.shown = false win.frame:Hide() end },
        { text = "Delete window...", func = function()
            StaticPopup_Show("LogLovers_DELETE_WINDOW", cfg.name, nil, win.index)
        end },
    })
end

-------------------------------------------------------------------------------
-- Spell inspector
-------------------------------------------------------------------------------
local inspector

local function buildSpellStats(sname)
    local lower = string.lower(sname)
    local function newAgg()
        return { casts = 0, hits = 0, crits = 0, misses = 0, total = 0,
                 max = 0, min = nil, resisted = 0, missTypes = {} }
    end
    local mine, taken = newAgg(), newAgg()
    NS.BufferEach(function(rec)
        if rec.snameLower ~= lower then return end
        local agg
        local mineSrc = rec.srcRole == "player" or rec.srcRole == "pet"
        if mineSrc then agg = mine
        elseif rec.dstRole == "player" or rec.dstRole == "pet" then agg = taken
        else return end
        if rec.sub == "SPELL_CAST_SUCCESS" then
            agg.casts = agg.casts + 1
        elseif rec.cat == "damage" or rec.cat == "healing" then
            agg.hits = agg.hits + 1
            agg.total = agg.total + (rec.amt or 0)
            if rec.crit then agg.crits = agg.crits + 1 end
            if (rec.amt or 0) > agg.max then agg.max = rec.amt end
            if not agg.min or (rec.amt or 0) < agg.min then agg.min = rec.amt or 0 end
            agg.resisted = agg.resisted + (rec.resisted or 0)
        elseif rec.cat == "misses" then
            agg.misses = agg.misses + 1
            local mt = rec.miss or "MISS"
            agg.missTypes[mt] = (agg.missTypes[mt] or 0) + 1
        end
    end)
    return mine, taken
end

local function aggLines(agg, label)
    local out = {}
    local attempts = agg.hits + agg.misses
    out[#out + 1] = C(label, NS.COLORS.accent)
    if attempts == 0 and agg.casts == 0 then
        out[#out + 1] = C("   no data in buffer", NS.COLORS.dim)
        return out
    end
    if agg.casts > 0 then out[#out + 1] = "   Casts: " .. C(agg.casts, "ffffff") end
    if attempts > 0 then
        out[#out + 1] = "   Landed: " .. C(agg.hits, "ffffff") ..
            "   Crit: " .. C(string.format("%d (%.1f%%)", agg.crits, agg.hits > 0 and agg.crits / agg.hits * 100 or 0), NS.COLORS.crit)
        out[#out + 1] = "   Total: " .. C(NS.FormatNumber(agg.total), "ffffff") ..
            "   Avg: " .. C(NS.FormatNumber(agg.hits > 0 and agg.total / agg.hits or 0), "ffffff")
        out[#out + 1] = "   Min: " .. C(NS.FormatNumber(agg.min or 0), "ffffff") ..
            "   Max: " .. C(NS.FormatNumber(agg.max), "ffffff")
        if agg.resisted > 0 then
            out[#out + 1] = "   Partially resisted: " .. C(NS.FormatNumber(agg.resisted), NS.COLORS.dim)
        end
        if agg.misses > 0 then
            local parts = {}
            for mt, n in pairs(agg.missTypes) do
                parts[#parts + 1] = (NS.MISS_LABELS[mt] or mt) .. " " .. n
            end
            out[#out + 1] = "   Missed: " .. C(agg.misses .. " (" .. table.concat(parts, ", ") .. ")", NS.COLORS.miss) ..
                C(string.format("  %.1f%%", agg.misses / attempts * 100), NS.COLORS.miss)
        end
    end
    return out
end

function NS.OpenSpellInspector(sid, sname)
    if not inspector then
        inspector = CreateFrame("Frame", "LogLoversInspector", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        inspector:SetSize(380, 460)
        inspector:SetPoint("CENTER", 120, 40)
        inspector:SetFrameStrata("DIALOG")
        inspector:SetMovable(true)
        inspector:EnableMouse(true)
        inspector:RegisterForDrag("LeftButton")
        inspector:SetScript("OnDragStart", inspector.StartMoving)
        inspector:SetScript("OnDragStop", inspector.StopMovingOrSizing)
        NS.SkinPanel(inspector, { r = 0.055, g = 0.043, b = 0.028, a = 0.97 })
        inspector:SetClampedToScreen(true)
        tinsert(UISpecialFrames, "LogLoversInspector")

        inspector.title = inspector:CreateFontString(nil, "OVERLAY")
        inspector.title:SetFont(NS.CurrentFont(), 14, "")
        inspector.title:SetPoint("TOPLEFT", 40, -12)

        inspector.sub = inspector:CreateFontString(nil, "OVERLAY")
        inspector.sub:SetFont(NS.CurrentFont(), 10, "")
        inspector.sub:SetPoint("TOPLEFT", 40, -30)

        inspector.icon = inspector:CreateTexture(nil, "ARTWORK")
        inspector.icon:SetSize(24, 24)
        inspector.icon:SetPoint("TOPLEFT", 10, -12)
        inspector.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        local close = NS.MakeIconButton(inspector, "Interface\\Buttons\\UI-StopButton", nil,
            function() inspector:Hide() end)
        close:SetPoint("TOPRIGHT", -8, -8)

        inspector.tip = CreateFrame("GameTooltip", "LogLoversInspectorTip", inspector, "GameTooltipTemplate")
        inspector.tip:SetOwner(inspector, "ANCHOR_NONE")

        inspector.body = inspector:CreateFontString(nil, "OVERLAY")
        inspector.body:SetFont(NS.CurrentFont(), 11, "")
        inspector.body:SetPoint("TOPLEFT", 14, -220)
        inspector.body:SetPoint("TOPRIGHT", -14, -220)
        inspector.body:SetJustifyH("LEFT")
        inspector.body:SetJustifyV("TOP")
        inspector.body:SetSpacing(3)
    end

    inspector.title:SetText(C(sname or "?", NS.COLORS.accent))
    inspector.sub:SetText(C(sid and ("Spell ID " .. sid) or "No spell ID (melee/effect)", NS.COLORS.dim))
    local tex = sid and NS.GetSpellTexture(sid)
    inspector.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")

    -- embedded tooltip
    local tip = inspector.tip
    tip:SetOwner(inspector, "ANCHOR_NONE")
    tip:ClearAllPoints()
    tip:SetPoint("TOPLEFT", inspector, "TOPLEFT", 10, -46)
    if sid then
        tip:SetHyperlink("spell:" .. sid)
        tip:Show()
    else
        tip:Hide()
    end

    local mine, taken = buildSpellStats(sname or "")
    local lines = {}
    for _, l in ipairs(aggLines(mine, "By you (and pet)")) do lines[#lines + 1] = l end
    lines[#lines + 1] = " "
    for _, l in ipairs(aggLines(taken, "Against you")) do lines[#lines + 1] = l end
    lines[#lines + 1] = " "
    lines[#lines + 1] = C("Scope: entire event buffer (" .. NS.BufferCount() .. " events)", NS.COLORS.dim)
    inspector.body:SetText(table.concat(lines, "\n"))

    inspector:Show()
end
