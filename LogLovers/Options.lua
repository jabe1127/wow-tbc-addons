-- LogLovers Options: in-game configuration panel
local ADDON, NS = ...

local C = NS.C
local panel
local pages = {}          -- [key] = { frame, refresh }
local currentPage
local sliderCount = 0

-------------------------------------------------------------------------------
-- Option tooltips (looked up by widget label)
-------------------------------------------------------------------------------
local OPTION_TIPS = {
    -- General
    ["Combat events kept"] = "How many combat events are kept in memory. Everything in the buffer can be re-filtered, searched, and exported at any time. Larger = more history, slightly more memory.",
    ["Timestamps"] = "Time shown at the start of every line: off, wall-clock (with or without milliseconds), or seconds into the current fight.",
    ["Number format"] = "Full shows 1,234,567. Short abbreviates to 1.23m / 12.3k.",
    ["Message style"] = "Compact uses arrows (Jabe >> Boar). Sentence writes out full lines like the Blizzard log.",
    ["Whisper header"] = "What the typing box shows once you are aimed at one person. Compact is a quiet 'Name >>'; Blizzard's is the stock 'To Name:' in whisper pink; Nothing leaves the box clean. Only the label changes - the whisper itself still goes where it always did.",
    ["Hide Blizzard's Combat Log tab"] = "Hides the default Combat Log tab on Blizzard's chat frame. Untick to bring it straight back. Only shown when the Log Lovers chat window is off - with it on, every Blizzard chat tab is hidden regardless.",
    ["Play highlight sounds"] = "Master switch for highlight sounds. Off silences every highlight without changing the sound each one is set to. There is a 2 second cooldown so a burst of procs cannot spam you.",
    ["Default alert sound"] = "The sound used by any highlight set to 'use the default'. Picking one here plays it so you can hear it straight away.",
    ["Custom sound file"] = "Full path to your own sound, e.g. Interface\\AddOns\\MySounds\\alert.ogg. Used by anything set to 'Custom file...'. WoW only plays .ogg, .mp3 and .wav files that shipped in an addon folder.",
    ["Spell highlight sound"] = "The sound this one spell plays. Choose 'use the default' to follow the dropdown above, or give this spell a sound of its own. Picking a sound previews it.",
    -- Death recap
    ["Record deaths"] = "Records the seconds leading up to every death so you can replay them. Off also stops loot being attached to kills.",
    ["Timeline"] = "How far back a recap reaches. The whole fight shows a boss pull or a long duel end to end; the fixed windows show exactly that many seconds before the death, which is usually what you want for ganks.",
    ["Open death recap browser"] = "The list of every recorded death, with its timeline. Same as /ll deaths.",
    ["Skip enemy deaths"] = "Records only players, pets and friendly NPCs. Leave OFF if you want [recap] links on the mobs you kill.",
    ["Keep recaps between sessions"] = "Writes recaps to SavedVariables so they survive /reload, logout and relogging. Restored recaps are marked '(earlier session)' and their timelines are read-only snapshots.",
    ["How many to keep"] = "How many recaps are written to disk, up to 200. The oldest roll off as new deaths come in - except any you have saved, which are never dropped. Saved ones still occupy a slot, so 3 saved out of 200 leaves 197 rolling. Higher numbers make your SavedVariables file bigger.",
    ["Clear history..."] = "Empties the recap history. If you have saved any, you get to choose whether to spare them - they were pinned on purpose. Cannot be undone.",
    ["Record what a corpse dropped"] = "When you open a corpse, its drops are attached to that kill's recap - item links included, hoverable and shift-clickable. Kills with loot show a * in the recap list.",
    ["Say hello at login"] = "Prints the small 'Log Lovers loaded' line in chat when you log in.",
    ["Remember people I talk to"] = "Builds the info block you see when you shift-click a name: whisper history, times grouped, trades, and any professions Log Lovers has watched them use. Nothing is sent anywhere - it lives in your SavedVariables. Off stops new records; notes you add by hand still work.",
    ["Forget everyone"] = "Wipes every remembered player, including your notes on them. Cannot be undone.",
    ["Reset positions"] = "Puts every open combat window back to its default place and size. The chat window, your filters, tabs and colours are untouched.",
    ["Clear combat history"] = "Empties the combat event buffer, so every log window starts blank. Death recaps and chat history are separate and are not touched.",
    ["Lock or unlock everything"] = "One switch for every Log Lovers window: the chat window, its tabs, every combat window and every pop-out. Unlocked, drag a title bar to move and the bottom-right corner to resize. Locked, they stay exactly where you put them. Same as /ll lock and /ll unlock.",
    ["Export profile"] = "Copies your entire setup - windows, tabs, filters, colours, highlights, appearance - into one shareable string. Chat history, saved recaps and captures are personal and stay behind.",
    ["Stats browser"] = "Damage, healing and damage taken, per fight or overall, expandable to per-spell rows. Same as /ll stats.",
    ["Import profile..."] = "Paste a profile string somebody shared with you. Your chat history, saved recaps and captures stay; everything else is replaced.",
    ["Start capture"] = "Records every combat event to SavedVariables\\LogLovers.lua for reading outside the game. Survives /reload and logout. Saved captures are listed below.",
    -- Chat words and behaviour
    ["Alt-click a name to invite"] = "Hold Alt and left-click any name in chat or the combat log to invite them straight to your group, skipping the menu.",
    ["Show levels next to names"] = "Puts [70] before a name when Log Lovers knows their level - from a /who you ran, or the guild roster. Names it does not know stay bare rather than showing a blank.",
    ["Fade chat out when it goes quiet"] = "Chat lines fade away after the delay below, so the window disappears when nothing is happening. Scrolling or a new message brings them back.",
    ["Fade chat after"] = "Seconds a chat line stays visible before fading (when fading is on).",
    ["Wheel scrolls"] = "Lines moved per wheel notch. Shift-wheel still pages, Ctrl-wheel still jumps to top or bottom.",
    ["Alert me on my own name"] = "Treats your character name as an alert word, so anyone mentioning you lights up.",
    ["Alert words"] = "Comma separated. Any chat line containing one of these is coloured, plays the alert sound, and marks the tab it landed in. Matching is plain substring and not case-sensitive, so 'heal' also catches 'healer'.",
    ["Alert colour"] = "The colour the matched word is painted in, and the colour an alerting tab turns.",
    ["Alert sound"] = "Plays when an alert word appears, at most once every 2 seconds. Picking a sound previews it.",
    ["Flag the tab"] = "A tab that received an alert word turns your alert colour and gets a ! until you look at it.",
    ["Blocked words"] = "Comma separated. Any chat line containing one of these is dropped before it reaches a window - not hidden, never stored. Built for gold sellers. It also matches sender names.",
    ["Never block guild or group"] = "Keeps the block list off your guild, party, raid, officer and battleground chat, and your own outgoing whispers, so a badly chosen word cannot silence your friends. Strongly recommended.",
    ["Collapse repeats (x3)"] = "The same message from the same person repeated inside the window below shows once with 'x3' instead of filling the screen.",
    ["Public chat only"] = "Limits repeat-collapsing to public chat. Off also collapses repeats in whispers, guild and group chat.",
    ["Repeat window"] = "How long after a message an identical one counts as a repeat rather than a new line.",
    -- Appearance
    ["Font"] = "Font used by all log and chat windows.",
    ["Custom font path"] = "Full path to any font file, e.g. Interface\\AddOns\\SharedMedia\\fonts\\MyFont.ttf. Overrides the dropdown when set. A path the client cannot load is refused rather than applied, so you cannot lock yourself out of this panel.",
    ["Font size"] = "Default text size for all windows. Individual windows can override it.",
    ["Font outline"] = "Outline style applied to window text.",
    ["Line spacing"] = "Extra vertical pixels between lines.",
    ["Show spell icons in lines"] = "Shows each spell's icon before its name in log lines.",
    ["Spell icon size"] = "Pixel size of spell icons in lines.",
    ["Class-colored player names"] = "Colors player names by their class. When off, names use friendly/hostile colors.",
    ["School-colored spells and damage numbers"] = "Colors spell names and damage amounts by spell school (Fire orange, Frost blue, ...).",
    ["Window background (alpha = default window opacity)"] = "Background color of all windows. The color's alpha sets the default opacity; windows can override opacity individually.",
    ["Window border"] = "1px border color of all windows.",
    ["Title bar"] = "Background color of window title bars.",
    ["Title bar height"] = "Height of every window title bar (and the chat tab strip). Bigger = easier to grab and read.",
    ["Title bar text size"] = "Font size of window titles and chat tab names.",
    -- Combat windows
    -- combat categories
    ["Pick from my buffs"] = "Lists every buff and debuff currently on you. Tick one to hide it from every combat window; tick it again to bring it back. Handy for zone buffs - stand in the buff, open this, hide it.",
    ["Hide a buff by name"] = "Type a buff or debuff name and press Enter to hide it everywhere. Not case-sensitive, and it does not have to be on you right now.",
    ["Show kills only"] = "Shows nothing but one line per kill, each with a clickable [recap]. Made for big pulls: instead of hundreds of damage lines you get a tidy list of what died, and can open any kill to see exactly what happened. Turning it off restores your normal event types.",
    ["Reset filters"] = "Puts this window's filters back to the defaults: every event type, every source, no spell list, no minimum, no unit focus. The window keeps its name, place and size.",
    ["Which events"] = "Everything I'm involved in: what I do and what is done to me. Or narrow it to one direction. This is always measured against you and your pet, whatever 'Show' is set to.",
    ["Show"] = "Whose actions this window shows. Just me is you and your pet; Me and my group adds your party or raid; Everyone shows every unit in range.",
    ["Show everyone in arenas"] = "Opens the window up to every combatant in arena, where you want to see the enemy team's casts, heals and cooldowns, without changing what you see anywhere else.",
    ["Use a different setting per place"] = "Set a different answer for the world, dungeons, raids, battlegrounds and arenas separately. Most people never need this; untick it and the world setting applies everywhere.",
    ["Chat lines saved"] = "How many chat lines are saved and restored across reloads and relogging.",
    ["Typing box on top (not bottom)"] = "Docks the typing box above the messages instead of below.",
    ["Hide their professions"] = "When other players are shown, drop their crafting and gathering casts.",
    ["Hide their cooking"] = "When other players are shown, drop their cooking casts.",
    ["Hide their fishing"] = "When other players are shown, drop their fishing casts.",
    ["Chat text size"] = "Override the chat window's text size. 0 uses the font size above.",
    ["Chat opacity"] = "Override the chat window's background opacity. 0 uses the setting above.",
    ["All channels, including ones I join later"] = "This tab shows every numbered channel automatically. Untick to pick exactly which ones.",
    ["Hide 'begins casting' lines"] = "Shows only completed casts instead of both 'begins' and 'casts' for every spell. Halves cast spam.",
    -- roles

    -- Chat behavior
    ["Short channel tags ([2], [G])"] = "Shows [2] instead of [2. Trade] and [G] instead of [Guild], so more of the line is the message. Turn off for the full channel name.",
    ["Clickable URLs (click to copy)"] = "Links pasted in chat become clickable and open a copy box.",
    ["Sound on incoming whisper"] = "Plays the classic whisper sound when someone whispers you (1s cooldown).",
    -- chat types
    -- Highlights
    ["Add spell (exact name)"] = "Type a spell's exact name and press Enter to highlight it everywhere with a color, alert icon, and a sound you pick.",
    ["Join another channel"] = "Type a channel name and press Enter to join it (e.g. a custom community channel).",
    ["Arenas"] = "In arenas, show every combatant - enemy casts, heals, CC and trinkets included - regardless of the setting above.",
    ["Battlegrounds"] = "Same, for battlegrounds.",
    ["Buffs / Debuffs"] = "Auras gained, lost, refreshed, stacked, and broken.",
    ["Casts"] = "Cast starts, successful casts, and failed casts.",
    ["Damage"] = "All direct, periodic, shield, and split damage.",
    ["Deaths / Kills"] = "Unit deaths and killing blows. Deaths carry a clickable [recap] link.",
    ["Dispels / Steals"] = "Dispels, failed dispels, and spellsteals.",
    ["Dungeons"] = "Same, for 5-man dungeon instances.",
    ["Enchants"] = "Temporary enchants applied or fading (sharpening stones, poisons...).",
    ["Everyone"] = "No filtering at all - every unit in range.",
    ["Healing"] = "Direct heals and heals over time.",
    ["Hostile"] = "Hostile units.",
    ["Interrupts"] = "Successful spell interrupts.",
    ["Just me"] = "You and your pet. There is no way to separate them - your pet's damage is your damage.",
    ["Me and my group"] = "You, your pet, and your party or raid.",
    ["Misses / Avoids"] = "Misses, dodges, parries, blocks, full resists, absorbs, immunes.",
    ["Neutral"] = "Neutral units.",
    ["Other friendly"] = "Friendly units not in your group.",
    ["Other"] = "Extra attacks, summons, created items, instakills, durability damage, resurrections.",
    ["Out in the world"] = "Who to show while questing, in cities, or anywhere outside an instance.",
    ["Party"] = "Party chat / events involving party members (includes leader).",
    ["Power gains / drains"] = "Mana/rage/energy/focus gains, drains, and leeches.",
    ["Raid warning"] = "Raid warnings (/rw).",
    ["Raid"] = "Raid chat / events involving raid members (includes leader).",
    ["Raids"] = "Same, for raid instances. Leave this OFF if you want your raid log filtered down to just you.",
    ["You"] = "Your character.",
    ["Your pet"] = "Your pet, guardians, and totems.",
    ["Addon messages"] = "Lines other addons print to chat (damage meters, boss mods...).",
    ["Battleground"] = "Battleground chat (includes BG leader).",
    ["Boss emotes"] = "Raid boss emotes and whispers.",
    ["Emotes"] = "/e custom emotes and /wave-style emotes.",
    ["Guild"] = "Guild chat.",
    ["Loot"] = "Loot messages.",
    ["Money"] = "Money gained or split.",
    ["NPC dialogue"] = "NPC says, yells, and whispers.",
    ["Numbered channels"] = "All numbered channels (General, Trade, LFG, custom...). Fine-tune which ones below.",
    ["Officer"] = "Officer chat.",
    ["Professions (item creations)"] = "Profession crafting spam: 'X creates ...' from you and nearby players (bandages, potions, blasting powder...). Untick to silence it.",
    ["Reputation"] = "Reputation gains and losses.",
    ["Say"] = "/say messages from nearby players.",
    ["Skill-ups"] = "Your skill level-ups, lockpicking, and pet info messages.",
    ["System"] = "System messages: logins, rolls, channel notices, BG announcements.",
    ["Whispers"] = "Incoming and outgoing whispers.",
    ["XP / Honor"] = "Experience and honor gains.",
    ["Yell"] = "/yell messages.",
}

-- every widget attachTip has ever been called on, so the harness can prove
-- none of them is left without an OPTION_TIPS entry
local tipped = {}

function NS.OptionsMissingTips()
    local out, seen = {}, {}
    for _, w in ipairs(tipped) do
        local t = w.tipTitle
        if t and t ~= "" and not w.tipText and not OPTION_TIPS[t] and not seen[t] then
            seen[t] = true
            out[#out + 1] = t
        end
    end
    table.sort(out)
    return out
end

local function attachTip(widget, labelText)
    widget.tipTitle = labelText
    tipped[#tipped + 1] = widget
    local prevEnter = widget:GetScript("OnEnter")
    widget:SetScript("OnEnter", function(self, ...)
        if prevEnter then prevEnter(self, ...) end
        local tip = self.tipText or (self.tipTitle and OPTION_TIPS[self.tipTitle])
        if not tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tipTitle ~= "" and self.tipTitle or " ", 1, 1, 1)
        GameTooltip:AddLine(tip, 0.75, 0.82, 0.88, true)
        GameTooltip:Show()
    end)
    local prevLeave = widget:GetScript("OnLeave")
    widget:SetScript("OnLeave", function(self, ...)
        if prevLeave then prevLeave(self, ...) end
        GameTooltip:Hide()
    end)
end

-------------------------------------------------------------------------------
-- Widget factory (dark glass)
-------------------------------------------------------------------------------
local function label(parent, text, size, hex)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(NS.CurrentFont(), size or 11, "")
    fs:SetText(C(text, hex or NS.COLORS.text))
    fs:SetJustifyH("LEFT")
    return fs
end

local function makeCheck(parent, text, get, set)
    local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    b:SetSize(15, 15)
    NS.SkinPanel(b, { r = 0, g = 0, b = 0, a = 0.6 })
    b.check = b:CreateTexture(nil, "ARTWORK")
    b.check:SetPoint("TOPLEFT", 2, -2)
    b.check:SetPoint("BOTTOMRIGHT", -2, 2)
    b.check:SetColorTexture(NS.ACCENT.r, NS.ACCENT.g, NS.ACCENT.b, 0.95)
    b.label = label(b, text)
    b.label:SetPoint("LEFT", b, "RIGHT", 6, 0)
    b.Refresh = function()
        b.check:SetShown(get() and true or false)
    end
    b:SetScript("OnClick", function()
        set(not get())
        b.Refresh()
    end)
    b.Refresh()
    -- clicking / hovering the label works too
    b:SetHitRectInsets(0, -math.min(230, (b.label:GetStringWidth() or 60) + 10), 0, 0)
    attachTip(b, text)
    return b
end

-- onCommit runs once when the user lets go, not on every step of a drag. Use it
-- for anything destructive: dragging a limit from 200 down to 5 and back must
-- not delete everything on the way past.
-- zeroLabel: what to render instead of "0", so a slider whose zero means
-- "inherit" can say so in the value instead of carrying a parenthetical in its
-- label forever
local function makeSlider(parent, text, minV, maxV, step, get, set, suffix, onCommit, zeroLabel)
    sliderCount = sliderCount + 1
    local name = "LogLoversSlider" .. sliderCount
    local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    s:SetWidth(190)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    _G[name .. "Low"]:SetText("")
    _G[name .. "High"]:SetText("")
    local t = _G[name .. "Text"]
    t:SetFontObject(GameFontHighlightSmall)
    local function updateText(v)
        -- the "inherit" end of the slider is its minimum, which is not always 0
        local shown = (zeroLabel and v <= minV) and zeroLabel
            or (tostring(v) .. (suffix or ""))
        t:SetText(C(text .. ": ", NS.COLORS.dim) .. C(shown, NS.COLORS.text))
    end
    s.Refresh = function()
        local v = get()
        s:SetValue(v)
        updateText(v)
    end
    s:SetScript("OnValueChanged", function(_, v, user)
        v = math.floor(v / step + 0.5) * step
        if step < 1 then v = math.floor(v * 100 + 0.5) / 100 end
        updateText(v)
        if user then set(v) end
    end)
    if onCommit then
        s:SetScript("OnMouseUp", function() onCommit(get()) end)
    end
    s.Refresh()
    attachTip(s, text)
    return s
end

local function makeDropdown(parent, text, items, get, set)
    -- items: array of { key=, label= }
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(340, 20)
    local lbl = label(holder, text)
    lbl:SetPoint("LEFT", holder, "LEFT", 0, 0)
    local b = CreateFrame("Button", nil, holder, BackdropTemplateMixin and "BackdropTemplate" or nil)
    NS.SkinPanel(b, { r = 0, g = 0, b = 0, a = 0.6 })
    b:SetSize(230, 19)
    b:SetPoint("LEFT", holder, "LEFT", 150, 0)
    b.text = label(b, "", 11)
    b.text:SetPoint("LEFT", 7, 0)
    -- stops at the arrow: a long LibSharedMedia name truncates instead of
    -- spilling out over whatever is next to the box
    b.text:SetPoint("RIGHT", b, "RIGHT", -18, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    local arrow = label(b, "v", 10, "6b7280")
    arrow:SetPoint("RIGHT", -6, 0)
    local function currentLabel()
        local v = get()
        for _, it in ipairs(items) do
            if it.key == v then return it.label end
        end
        return tostring(v or "?")
    end
    holder.Refresh = function() b.text:SetText(C(currentLabel(), NS.COLORS.text)) end
    b:SetScript("OnClick", function()
        local menuItems = { { text = text, header = true } }
        for _, it in ipairs(items) do
            table.insert(menuItems, { text = it.label, checked = it.key == get(),
                func = function() set(it.key) holder.Refresh() end })
        end
        NS.ShowMenu(menuItems)
    end)
    holder.Refresh()
    attachTip(b, text)
    return holder
end

local function makeColor(parent, text, getTbl, onChange)
    local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    b:SetSize(16, 16)
    NS.SkinPanel(b, { r = 0, g = 0, b = 0, a = 1 }, { r = 0.4, g = 0.42, b = 0.48, a = 1 })
    b.sw = b:CreateTexture(nil, "ARTWORK")
    b.sw:SetPoint("TOPLEFT", 2, -2)
    b.sw:SetPoint("BOTTOMRIGHT", -2, 2)
    b.label = label(b, text)
    b.label:SetPoint("LEFT", b, "RIGHT", 6, 0)
    b.Refresh = function()
        local cTbl = getTbl()
        b.sw:SetColorTexture(cTbl.r, cTbl.g, cTbl.b, 1)
    end
    b:SetScript("OnClick", function()
        local cTbl = getTbl()
        NS.OpenColorPicker(cTbl.r, cTbl.g, cTbl.b, cTbl.a or 1, function(r, g, bb, a)
            cTbl.r, cTbl.g, cTbl.b, cTbl.a = r, g, bb, a
            b.Refresh()
            if onChange then onChange() end
        end)
    end)
    b.Refresh()
    attachTip(b, text)
    return b
end

local function makeEdit(parent, text, width, get, set)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(400, 20)
    local lbl = label(holder, text)
    lbl:SetPoint("LEFT", holder, "LEFT", 0, 0)
    local e = CreateFrame("EditBox", nil, holder, BackdropTemplateMixin and "BackdropTemplate" or nil)
    NS.SkinPanel(e, { r = 0, g = 0, b = 0, a = 0.6 })
    e:SetSize(width or 170, 19)
    e:SetPoint("LEFT", holder, "LEFT", 150, 0)
    e:SetFont(NS.CurrentFont(), 11, "")
    e:SetTextInsets(6, 6, 0, 0)
    e:SetAutoFocus(false)
    holder.Refresh = function() e:SetText(tostring(get() or "")) end
    e:SetScript("OnEnterPressed", function(self)
        set(self:GetText())
        self:ClearFocus()
    end)
    e:SetScript("OnEscapePressed", function(self)
        holder.Refresh()
        self:ClearFocus()
    end)
    holder.edit = e
    holder.Refresh()
    attachTip(e, text)
    return holder
end

local function makeButton(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    NS.SkinPanel(b, { r = 0.16, g = 0.11, b = 0.05, a = 0.92 }, { r = 0.52, g = 0.37, b = 0.14, a = 0.95 })
    b:SetSize(width or 150, 20)
    b.text = label(b, text, 11, NS.COLORS.accent)
    b.text:SetPoint("CENTER")
    -- buttons whose label is data (a sound name) must not outgrow their box
    b.text:SetWidth((width or 150) - 12)
    b.text:SetJustifyH("CENTER")
    b.text:SetWordWrap(false)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(NS.ACCENT.r, NS.ACCENT.g, NS.ACCENT.b, 0.10)
    b:SetScript("OnClick", onClick)
    return b
end

-- vertical layout cursor
local function stacker(page, startY)
    local top = startY or -12
    local y = top
    local items = {}

    local function add(widget, height, indent, gap)
        items[#items + 1] = {
            w = widget, h = height or 24, indent = indent or 0, gap = gap or 4,
        }
        widget:SetPoint("TOPLEFT", page, "TOPLEFT", 14 + (indent or 0), y)
        y = y - (height or 24) - (gap or 4)
        return widget
    end

    -- Re-anchor everything, skipping hidden widgets so nothing reserves empty
    -- space, then shrink or grow the scroll child to match. Called whenever a
    -- page shows or hides part of itself.
    local function relayout()
        local yy = top
        for _, it in ipairs(items) do
            local w = it.w
            local shown = true
            if w.IsShown then shown = w:IsShown() and true or false end
            if shown then
                local h = rawget(w, "llHeight")
                if type(h) ~= "number" then h = it.h end
                if w.ClearAllPoints then w:ClearAllPoints() end
                w:SetPoint("TOPLEFT", page, "TOPLEFT", 14 + it.indent, yy)
                yy = yy - h - it.gap
            end
        end
        local total = math.max(-yy + 24, 80)
        page.llContentHeight = total
        if page.SetHeight then page:SetHeight(total) end
        return total
    end

    return add, function() return -y end, relayout
end

-------------------------------------------------------------------------------
-- Panel shell
-------------------------------------------------------------------------------
local NAV = {
    { key = "general",    label = "General" },
    { key = "appearance", label = "Appearance" },
    { key = "views",      label = "Windows & Tabs" },
    { key = "channels",   label = "Chat" },
    { key = "highlights", label = "Spell Highlights" },
    { key = "recap",      label = "Death Recap" },
    { key = "about",      label = "About" },
}

local function selectPage(key)
    currentPage = key
    for k, page in pairs(pages) do
        page.scroll:SetShown(k == key)
        if k == key and page.refresh then page.refresh() end
    end
    for _, btn in ipairs(panel.navButtons) do
        if btn.key == key then
            btn.text:SetText(C(btn.label, NS.COLORS.accent))
            btn.bar:Show()
        else
            btn.text:SetText(C(btn.label, NS.COLORS.dim))
            btn.bar:Hide()
        end
    end
end

local function newPage(key, contentHeight)
    local scroll = CreateFrame("ScrollFrame", "LogLoversOptScroll" .. key, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 160, -50)
    scroll:SetPoint("BOTTOMRIGHT", -30, 12)
    local frame = CreateFrame("Frame", nil, scroll)
    frame:SetSize(520, contentHeight or 600)
    scroll:SetScrollChild(frame)
    scroll:Hide()
    pages[key] = { frame = frame, scroll = scroll }
    return frame
end

-------------------------------------------------------------------------------
-- Pages
-------------------------------------------------------------------------------
local function buildGeneral()
    local p = newPage("general", 1200)
    local add, _generalH, relayout = stacker(p)
    local widgets = {}

    add(label(p, "General", 14, NS.COLORS.accent), 22)

    -- First thing on the first page, because "how do I move this" is the
    -- question everyone has first.
    local lockRow = CreateFrame("Frame", nil, p)
    lockRow:SetSize(500, 22)
    add(lockRow, 26)
    local lockBtn = makeButton(lockRow, "", 180, function()
        NS.SetAllLocked(not NS.AllLocked())
        pages.general.refresh()
    end)
    lockBtn:SetPoint("LEFT", 0, 0)
    attachTip(lockBtn, "Lock or unlock everything")
    local lockHint = label(lockRow, "", 11, NS.COLORS.dim)
    lockHint:SetPoint("LEFT", lockBtn, "RIGHT", 10, 0)
    pages.general.updateLock = function()
        local locked = NS.AllLocked()
        lockBtn.text:SetText(C(locked and "Unlock everything" or "Lock everything",
            locked and NS.COLORS.accent or NS.COLORS.text))
        lockHint:SetText(C(locked
            and "Everything is locked. Nothing can be dragged or resized."
            or "Drag any title bar to move a window, or its corner to resize.",
            NS.COLORS.dim))
    end

    widgets[#widgets + 1] = add(makeDropdown(p, "Timestamps", NS.TIMESTAMP_MODES,
        function() return NS.db.general.timestampMode end,
        function(v) NS.db.general.timestampMode = v NS.ApplyAppearance() end), 24)

    widgets[#widgets + 1] = add(makeDropdown(p, "Number format", NS.NUMBER_MODES,
        function() return NS.db.general.numberMode end,
        function(v) NS.db.general.numberMode = v NS.ApplyAppearance() end), 24)

    widgets[#widgets + 1] = add(makeDropdown(p, "Message style", NS.STYLE_MODES,
        function() return NS.db.general.style end,
        function(v) NS.db.general.style = v NS.ApplyAppearance() end), 24)

    -- With the chat replacement running, every Blizzard chat tab is hidden
    -- anyway, so this switch has nothing to do. Only show it to somebody
    -- running the combat log on its own.
    local blizzLogChk = add(makeCheck(p, "Hide Blizzard's Combat Log tab",
        function() return NS.db.general.hideBlizzLog end,
        function(v) NS.SetBlizzLogHidden(v) end), 20)
    widgets[#widgets + 1] = blizzLogChk

    widgets[#widgets + 1] = add(makeCheck(p, "Say hello at login",
        function() return NS.db.general.minimapHint end,
        function(v) NS.db.general.minimapHint = v end), 20, nil, 12)

    add(label(p, "People", 12, NS.COLORS.accent), 18)
    widgets[#widgets + 1] = add(makeCheck(p, "Remember people I talk to",
        function() return NS.db.general.trackPlayers end,
        function(v)
            NS.db.general.trackPlayers = v
            pages.general.refresh()
        end), 20)

    local peopleRow = CreateFrame("Frame", nil, p)
    peopleRow:SetSize(500, 22)
    add(peopleRow, 26, nil, 10)
    local forgetBtn = makeButton(peopleRow, "Forget everyone", 150, function()
        local n = NS.PLAYERS.ForgetAll()
        NS.Print("forgot " .. n .. " " .. (n == 1 and "person" or "people") .. ".")
        pages.general.refresh()
    end)
    forgetBtn:SetPoint("LEFT", 0, 0)
    attachTip(forgetBtn, "Forget everyone")
    local peopleCount = label(peopleRow, "", 11, NS.COLORS.dim)
    peopleCount:SetPoint("LEFT", forgetBtn, "RIGHT", 10, 0)
    pages.general.updatePeople = function()
        local total, kept = NS.PLAYERS.Count()
        if total == 0 then
            peopleCount:SetText(C("Nobody remembered yet.", NS.COLORS.dim))
        else
            peopleCount:SetText(C(total .. " remembered, " .. kept ..
                " you have actually dealt with.", NS.COLORS.dim))
        end
    end

    -- ---------------------------------------------------------------------
    -- Tools: the buttons that used to live on their own Capture & Export page
    -- ---------------------------------------------------------------------
    add(label(p, "Tools", 12, NS.COLORS.accent), 18)

    local toolRow1 = CreateFrame("Frame", nil, p)
    toolRow1:SetSize(500, 22)
    add(toolRow1, 26)
    local b1 = makeButton(toolRow1, "Reset positions", 140, NS.ResetWindowPositions)
    b1:SetPoint("LEFT", 0, 0)
    attachTip(b1, "Reset positions")
    local b2 = makeButton(toolRow1, "Clear combat history", 160, function()
        NS.BufferClear()
        NS.RefreshAllWindows()
    end)
    b2:SetPoint("LEFT", b1, "RIGHT", 8, 0)
    attachTip(b2, "Clear combat history")
    local b3 = makeButton(toolRow1, "Stats browser", 130, function() NS.ToggleStats(true) end)
    b3:SetPoint("LEFT", b2, "RIGHT", 8, 0)
    attachTip(b3, "Stats browser")

    widgets[#widgets + 1] = add(makeSlider(p, "Combat events kept", 1000, 20000, 500,
        function() return NS.db.general.bufferSize end,
        function(v)
            NS.db.general.bufferSize = v
            NS.BufferResize(v)
        end, " events"), 34)

    local toolRow2 = CreateFrame("Frame", nil, p)
    toolRow2:SetSize(500, 22)
    add(toolRow2, 26)
    local expBtn = makeButton(toolRow2, "Export profile", 130, function()
        NS.ShowCopyText("Log Lovers profile (Ctrl+C to copy, share anywhere)", NS.ExportProfile())
    end)
    expBtn:SetPoint("LEFT", 0, 0)
    attachTip(expBtn, "Export profile")
    local impBtn = makeButton(toolRow2, "Import profile...", 130, function()
        NS.ShowImportDialog()
    end)
    impBtn:SetPoint("LEFT", expBtn, "RIGHT", 8, 0)
    attachTip(impBtn, "Import profile...")

    add(label(p, "A profile carries your windows, tabs, filters, colours, highlights and\nappearance. Chat history, saved recaps and captures stay on this character.", 11, NS.COLORS.dim), 30)

    -- ---------------------------------------------------------------------
    -- Event capture, for offline analysis
    -- ---------------------------------------------------------------------
    add(label(p, "Event capture", 12, NS.COLORS.accent), 18)
    local capRow = CreateFrame("Frame", nil, p)
    capRow:SetSize(500, 22)
    add(capRow, 26)
    local capBtn = makeButton(capRow, "Start capture", 150, function()
        if NS.captureActive then NS.CaptureStop() else NS.CaptureStart() end
        pages.general.refresh()
    end)
    capBtn:SetPoint("LEFT", 0, 0)
    attachTip(capBtn, "Start capture")
    local capHint = label(capRow, "", 11, NS.COLORS.dim)
    capHint:SetPoint("LEFT", capBtn, "RIGHT", 10, 0)

    local capListBase = CreateFrame("Frame", nil, p)
    capListBase:SetSize(500, 24)
    add(capListBase, 24)
    local capRows = {}

    pages.general.refresh = function()
        for _, w in ipairs(widgets) do if w.Refresh then w.Refresh() end end
        blizzLogChk:SetShown(not (NS.db.chat and NS.db.chat.enabled))
        if pages.general.updateLock then pages.general.updateLock() end
        if pages.general.updatePeople then pages.general.updatePeople() end

        capBtn.text:SetText(C(NS.captureActive and "Stop capture" or "Start capture",
            NS.captureActive and NS.COLORS.death or NS.COLORS.accent))
        local nCap = #(NS.db.captures or {})
        capHint:SetText(C(NS.captureActive and "Recording every event to SavedVariables."
            or (nCap == 0 and "Records every event to SavedVariables for offline analysis."
                or (nCap .. " saved capture" .. (nCap == 1 and "" or "s") .. ".")),
            NS.COLORS.dim))

        for _, r in ipairs(capRows) do r:Hide() end
        for i, cap in ipairs(NS.db.captures or {}) do
            local r = capRows[i]
            if not r then
                r = CreateFrame("Frame", nil, capListBase, BackdropTemplateMixin and "BackdropTemplate" or nil)
                NS.SkinPanel(r, { r = 0, g = 0, b = 0, a = 0.35 })
                r:SetSize(500, 22)
                r:SetPoint("TOPLEFT", 0, -(i - 1) * 24)
                r.name = label(r, "", 11)
                r.name:SetPoint("LEFT", 8, 0)
                r.name:SetWidth(370)
                r.name:SetWordWrap(false)
                r.view = makeButton(r, "view", 50, nil)
                r.view:SetPoint("RIGHT", -60, 0)
                r.del = makeButton(r, "delete", 50, nil)
                r.del:SetPoint("RIGHT", -4, 0)
                capRows[i] = r
            end
            r.name:SetText(C(date("%m-%d %H:%M", cap.started) .. "  " ..
                (cap.zone or "") .. "  (" .. (cap.count or 0) .. " lines)", NS.COLORS.text))
            r.view:SetScript("OnClick", function() NS.ViewCapture(i) end)
            r.del:SetScript("OnClick", function()
                NS.DeleteCapture(i)
                pages.general.refresh()
            end)
            r:Show()
        end
        local capH = math.max(#(NS.db.captures or {}) * 24, 1)
        capListBase.llHeight = capH
        capListBase:SetHeight(capH)
        capListBase:SetShown(#(NS.db.captures or {}) > 0)

        relayout()
    end
end

local function buildAppearance()
    local p = newPage("appearance", 620)
    local add = stacker(p)
    local widgets = {}
    local function W(w, h, indent, gap)
        widgets[#widgets + 1] = w
        return add(w, h, indent, gap)
    end

    add(label(p, "Appearance", 14, NS.COLORS.accent), 22)

    local fontItems = {}
    for _, fnt in ipairs(NS.FONTS) do
        fontItems[#fontItems + 1] = { key = fnt.path, label = fnt.name }
    end
    if LibStub then
        local LSM = LibStub("LibSharedMedia-3.0", true)
        if LSM then
            for name, path in pairs(LSM:HashTable("font")) do
                fontItems[#fontItems + 1] = { key = path, label = name .. " (LSM)" }
            end
        end
    end

    W(makeDropdown(p, "Font", fontItems,
        function() return NS.db.appearance.font end,
        function(v)
            NS.db.appearance.font = v
            NS.db.appearance.customFont = ""
            NS.ApplyAppearance()
        end), 24)

    W(makeEdit(p, "Custom font path", 220,
        function() return NS.db.appearance.customFont end,
        function(v)
            v = (v or ""):gsub("^%s+", ""):gsub("%s+$", "")
            -- Every label in this panel is drawn with the current font, so a
            -- path the client cannot load used to leave nothing on screen to
            -- fix it with. Try it on a scratch string first.
            if v ~= "" then
                if not NS.FontLoads(v) then
                    NS.Print("that font file could not be loaded - keeping the current font.")
                    pages.appearance.refresh()
                    return
                end
            end
            NS.db.appearance.customFont = (v ~= "" and v) or nil
            NS.ApplyAppearance()
        end), 24)

    W(makeSlider(p, "Font size", 8, 20, 1,
        function() return NS.db.appearance.fontSize end,
        function(v) NS.db.appearance.fontSize = v NS.ApplyAppearance() end), 34)

    local outlineItems = {}
    for _, o in ipairs(NS.OUTLINES) do
        outlineItems[#outlineItems + 1] = { key = o.flag, label = o.name }
    end
    W(makeDropdown(p, "Font outline", outlineItems,
        function() return NS.db.appearance.outline end,
        function(v) NS.db.appearance.outline = v NS.ApplyAppearance() end), 24)

    W(makeSlider(p, "Line spacing", 0, 6, 1,
        function() return NS.db.appearance.lineSpacing end,
        function(v) NS.db.appearance.lineSpacing = v NS.ApplyAppearance() end), 34)

    W(makeSlider(p, "Title bar height", 14, 30, 1,
        function() return NS.db.appearance.titleHeight or 19 end,
        function(v)
            NS.db.appearance.titleHeight = v
            NS.ApplyAppearance()
            if NS.ApplyChatLayout then NS.ApplyChatLayout() end
        end), 34)

    W(makeSlider(p, "Title bar text size", 9, 18, 1,
        function() return NS.db.appearance.titleFontSize or 11 end,
        function(v)
            NS.db.appearance.titleFontSize = v
            NS.ApplyAppearance()
            if NS.ApplyChatLayout then NS.ApplyChatLayout() end
        end), 34)

    -- three related switches, two columns instead of three stacked rows
    local apChecks = {
        { "Show spell icons in lines",
            function() return NS.db.appearance.showIcons end,
            function(v) NS.db.appearance.showIcons = v NS.ApplyAppearance() end },
        { "Class-colored player names",
            function() return NS.db.appearance.classColors end,
            function(v)
                NS.db.appearance.classColors = v
                NS.WipeClassCache()
                NS.ApplyAppearance()
            end },
        { "School-colored spells and damage numbers",
            function() return NS.db.appearance.schoolColors end,
            function(v) NS.db.appearance.schoolColors = v NS.ApplyAppearance() end },
    }
    local apBase = CreateFrame("Frame", nil, p)
    apBase:SetSize(500, 2 * 22)
    add(apBase, 2 * 22)
    for i, def in ipairs(apChecks) do
        local chk = makeCheck(apBase, def[1], def[2], def[3])
        widgets[#widgets + 1] = chk
        chk:SetPoint("TOPLEFT", apBase, "TOPLEFT",
            ((i - 1) % 2) * 250, -math.floor((i - 1) / 2) * 22)
    end

    W(makeSlider(p, "Spell icon size", 8, 24, 1,
        function() return NS.db.appearance.iconSize end,
        function(v) NS.db.appearance.iconSize = v NS.ApplyAppearance() end), 34, nil, 10)

    -- the three window colours on one row rather than three
    add(label(p, "Colours", 12, NS.COLORS.accent), 18)
    local colRow = CreateFrame("Frame", nil, p)
    colRow:SetSize(500, 22)
    add(colRow, 26)
    local colDefs = {
        { "Window background (alpha = default window opacity)", "background",
          function() return NS.db.appearance.bg end },
        { "Window border", "border", function() return NS.db.appearance.border end },
        { "Title bar", "title bar", function() return NS.db.appearance.titleBg end },
    }
    local prev
    for _, d in ipairs(colDefs) do
        local sw = makeColor(colRow, "", d[3], NS.ApplyAppearance)
        widgets[#widgets + 1] = sw
        if prev then sw:SetPoint("LEFT", prev, "RIGHT", 84, 0)
        else sw:SetPoint("LEFT", 0, 0) end
        local lbl = label(colRow, d[2], 11, NS.COLORS.dim)
        lbl:SetPoint("LEFT", sw, "RIGHT", 6, 0)
        sw.tipTitle = d[1]
        prev = sw
    end

    add(label(p, "Chat window", 12, NS.COLORS.accent), 18)
    -- 1 through 7 used to read as themselves and store 8; the slider now skips
    -- straight from "same as above" to the smallest size that actually works
    W(makeSlider(p, "Chat text size", 7, 20, 1,
        function() return NS.db.chat.fontSize or 7 end,
        function(v)
            if v <= 7 then NS.db.chat.fontSize = nil else NS.db.chat.fontSize = v end
            if NS.ApplyChatAppearance then NS.ApplyChatAppearance() end
        end, nil, nil, "same as above"), 34)
    W(makeSlider(p, "Chat opacity", 0, 1, 0.05,
        function() return NS.db.chat.bgAlpha or 0 end,
        function(v)
            if v == 0 then NS.db.chat.bgAlpha = nil else NS.db.chat.bgAlpha = v end
            if NS.ApplyChatAppearance then NS.ApplyChatAppearance() end
        end, nil, nil, "same as above"), 34)

    pages.appearance.refresh = function()
        for _, w in ipairs(widgets) do if w.Refresh then w.Refresh() end end
    end
end

local function hex2rgb(hex)
    return tonumber(hex:sub(1, 2), 16) / 255,
           tonumber(hex:sub(3, 4), 16) / 255,
           tonumber(hex:sub(5, 6), 16) / 255
end

local function buildViews()
    local p = newPage("views", 1500)
    local add, _totalH, relayout = stacker(p)
    local widgets = {}
    local function W(w, h, indent, gap)
        widgets[#widgets + 1] = w
        return add(w, h, indent, gap)
    end

    -- ---------------------------------------------------------------------
    -- Everything you can edit, in one list: chat tabs, combat log tabs, and
    -- standalone combat windows.
    -- ---------------------------------------------------------------------
    local selKind, selIdx = "chat", 1     -- "chat" = a chat view, "window" = a combat window

    local function chatViews() return NS.db.chat.views or {} end

    local function entries()
        local list = {}
        for i, v in ipairs(chatViews()) do
            local what
            if v.kind == "combat" then
                what = (v.mode == "window") and "combat log, popped out" or "combat log tab"
            else
                what = (v.mode == "window") and "chat, popped out" or "chat tab"
            end
            list[#list + 1] = { kind = "chat", idx = i, name = v.name, what = what }
        end
        -- Only windows that are actually floating on screen. A config whose
        -- window was docked as a tab is kept (so the filter is not lost) but
        -- hidden - listing it as "popped out" was a lie, and produced phantom
        -- entries for windows the user could not see anywhere.
        for i, cfg in ipairs(NS.db.windows or {}) do
            if cfg.shown ~= false then
                list[#list + 1] = { kind = "window", idx = i, name = cfg.name,
                                    what = "combat log, popped out" }
            end
        end
        return list
    end

    -- the selected thing, normalised
    local function sel()
        if selKind == "window" then
            local cfg = NS.db.windows[selIdx]
            if cfg then
                return { kind = "window", cfg = cfg, filter = cfg.filter,
                         isCombat = true, name = cfg.name, what = "combat window" }
            end
        else
            local v = chatViews()[selIdx]
            if v then
                local isCombat = v.kind == "combat"
                return { kind = "chat", view = v, filter = isCombat and v.combatFilter or v.filter,
                         isCombat = isCombat, name = v.name,
                         what = isCombat and "combat log" or "chat" }
            end
        end
        -- fall back to the first thing that exists
        if chatViews()[1] then
            selKind, selIdx = "chat", 1
            local v = chatViews()[1]
            local isCombat = v.kind == "combat"
            return { kind = "chat", view = v, filter = isCombat and v.combatFilter or v.filter,
                     isCombat = isCombat, name = v.name,
                     what = isCombat and "combat log" or "chat" }
        end
        return nil
    end

    local function applyChange()
        local e = sel()
        if not e then return end
        if e.kind == "window" then
            NS.RefreshWindow(NS.windows[selIdx])
        else
            NS.RefreshChat()
        end
    end

    add(label(p, "Windows & Tabs", 14, NS.COLORS.accent), 20)
    add(label(p, "Every chat tab, combat log tab and floating window lives here.\nPick one, then set what it shows.", 11, NS.COLORS.dim), 30)

    local selLabel = add(label(p, "", 12), 20)
    -- Filters set from right-click menus - one spell, a minimum amount, a unit
    -- focus, a role restriction from a preset - have no controls anywhere, so a
    -- window quietly filtered down to one spell looked identical to a broken
    -- one. Say what is in force, and give people a way out of it.
    local hiddenLabel = add(label(p, "", 11, NS.COLORS.dim), 18)

    local rowFrame = CreateFrame("Frame", nil, p)
    rowFrame:SetSize(520, 22)
    add(rowFrame, 26)

    local selBtn = makeButton(rowFrame, "Choose", 90, function()
        local items = { { text = "Edit which window or tab?", header = true } }
        for _, e in ipairs(entries()) do
            table.insert(items, {
                text = e.name .. "  (" .. e.what .. ")",
                checked = (e.kind == selKind and e.idx == selIdx),
                func = function()
                    selKind, selIdx = e.kind, e.idx
                    pages.views.refresh()
                end,
            })
        end
        -- actions live below the line, away from the list of things to edit
        table.insert(items, { separator = true })
        table.insert(items, {
            text = "Pop out a combat window",
            func = function()
                local idx = NS.PopOutCombatWindow()
                if idx then
                    selKind, selIdx = "window", idx
                    pages.views.refresh()
                    NS.Print("popped out a combat window - drag its title bar to place it.")
                end
            end,
        })
        NS.ShowMenu(items)
    end)
    selBtn:SetPoint("LEFT", 0, 0)

    local newBtn = makeButton(rowFrame, "New...", 80, function()
        NS.ShowNewChatViewMenu(function(idx)
            selKind, selIdx = "chat", idx or #chatViews()
            pages.views.refresh()
        end)
    end)
    newBtn:SetPoint("LEFT", selBtn, "RIGHT", 6, 0)

    local renBtn = makeButton(rowFrame, "Rename...", 90, function()
        local e = sel()
        if not e then return end
        if e.kind == "window" then
            StaticPopup_Show("LogLovers_RENAME_WINDOW", nil, nil, selIdx)
        else
            StaticPopup_Show("LogLovers_RENAME_CHATVIEW", nil, nil, selIdx)
        end
    end)
    renBtn:SetPoint("LEFT", newBtn, "RIGHT", 6, 0)

    local moveBtn = makeButton(rowFrame, "Pop out", 100, function()
        local e = sel()
        if not e then return end
        if e.kind == "window" then
            if NS.DockCombatWindowAsTab then NS.DockCombatWindowAsTab(selIdx) end
            selKind, selIdx = "chat", #chatViews()
        elseif e.view.mode == "window" then
            NS.DockChatView(selIdx)
        else
            NS.BreakOutChatView(selIdx)
        end
        pages.views.refresh()
    end)
    moveBtn:SetPoint("LEFT", renBtn, "RIGHT", 6, 0)

    local delBtn = makeButton(rowFrame, "Delete", 70, function()
        local e = sel()
        if not e then return end
        if e.kind == "window" then
            if #NS.db.windows > 1 then
                StaticPopup_Show("LogLovers_DELETE_WINDOW", e.name, nil, selIdx)
            else
                NS.Print("that is your last combat window.")
            end
        else
            -- a tab carries a whole filter set; deleting a window asks first,
            -- so deleting a tab should too
            local nm = e.name or "this tab"
            NS.ShowMenu({
                { text = "Delete \"" .. nm .. "\"?", header = true },
                { text = "Delete it", func = function()
                    NS.DeleteChatView(selIdx)
                    selKind, selIdx = "chat", 1
                    pages.views.refresh()
                end },
                { text = "Cancel", func = function() end },
            })
            return
        end
        selKind, selIdx = "chat", 1
        pages.views.refresh()
    end)
    delBtn:SetPoint("LEFT", moveBtn, "RIGHT", 6, 0)

    local resetBtn = makeButton(rowFrame, "Reset filters", 110, function()
        local e = sel()
        if not e or not e.isCombat or not e.filter then return end
        NS.ShowMenu({
            { text = "Reset every filter on this window?", header = true },
            { text = "Reset it", func = function()
                local fresh = NS.DefaultFilterAll()
                -- keep the name and the layout; replace what it shows
                for k in pairs(e.filter) do e.filter[k] = nil end
                for k, v in pairs(fresh) do e.filter[k] = v end
                applyChange()
                pages.views.refresh()
                NS.Print("filters reset.")
            end },
            { text = "Cancel", func = function() end },
        })
    end)
    resetBtn:SetPoint("LEFT", delBtn, "RIGHT", 6, 0)
    attachTip(resetBtn, "Reset filters")

    -- =====================================================================
    -- COMBAT VIEW EDITOR
    -- =====================================================================
    local combatHead = add(label(p, "What this shows", 13, NS.COLORS.accent), 20)

    local aoeChk = W(makeCheck(p, "Show kills only",
        function()
            local e = sel()
            return e and e.filter.aoeFarm
        end,
        function(v)
            local e = sel()
            if e then
                e.filter.aoeFarm = v
                applyChange()
                pages.views.refresh()
            end
        end), 24)

    local aoeHint = add(label(p,
        "Every other setting below is paused while this is on - you get one\n[recap] line per kill and nothing else. Untick to get them back.",
        11, NS.COLORS.dim), 28)

    local dirDD = add(makeDropdown(p, "Which events", NS.DIRECTION_MODES,
        function()
            local e = sel()
            return e and NS.EffectiveDirection(e.filter) or "both"
        end,
        function(v)
            local e = sel()
            if e then
                e.filter.direction = v
                applyChange()
            end
        end), 26)

    -- Who to show.
    --
    -- This used to be five dropdowns - world, dungeon, raid, battleground,
    -- arena - which is 729 combinations to answer one question. Almost everyone
    -- wants one answer everywhere, plus "open it up in arena". So that is the
    -- shape now, and the per-place grid is still there for anyone who really
    -- does want a different answer in dungeons than in raids.
    local whoHead = add(label(p, "Who to show", 12, NS.COLORS.accent), 20)

    -- Arena is the one place the shipped defaults differ, and the one place
    -- everybody agrees you want to see the other team. It gets the checkbox;
    -- every other place shares one answer unless you ask for more.
    local function baseScope(f)
        if not f or not f.scopes then return "me" end
        return f.scopes.world or "me"
    end

    local function scopesAreSimple(f)
        if not f or not f.scopes then return true end
        local base
        for _, loc in ipairs(NS.LOCATIONS) do
            if loc.key ~= "arena" then
                local v = f.scopes[loc.key] or "me"
                if base == nil then base = v elseif v ~= base then return false end
            end
        end
        -- arena may match the rest, or be opened all the way up
        local a = f.scopes.arena or "me"
        return a == base or a == "all"
    end

    local function ensureScopes(f)
        f.scopes = f.scopes or NS.DeepCopy(NS.DEFAULT_SCOPES)
        return f.scopes
    end

    -- One place decides what "Show" means, so the options page and the tests
    -- cannot drift apart. Arena keeps its own answer when it is opened up.
    function NS.OptionsApplyScope(f, v)
        local sc = ensureScopes(f)
        local arenaWide = sc.arena == "all"
        for _, loc in ipairs(NS.LOCATIONS) do
            sc[loc.key] = (loc.key == "arena" and arenaWide) and "all" or v
        end
    end
    function NS.OptionsScopeForm(f)
        return {
            simple = scopesAreSimple(f) and not (f and f.perPlace),
            base = baseScope(f),
            arena = (f and f.scopes and f.scopes.arena) or "me",
        }
    end

    local simpleDD = makeDropdown(p, "Show", NS.SCOPE_CHOICES,
        function()
            local e = sel()
            if not e or not e.filter.scopes then return "me" end
            return e.filter.scopes.world or "me"
        end,
        function(v)
            local e = sel()
            if not e then return end
            NS.OptionsApplyScope(e.filter, v)
            applyChange()
            pages.views.refresh()
        end)
    add(simpleDD, 24)

    local pvpChk = makeCheck(p, "Show everyone in arenas",
        function()
            local e = sel()
            return e and e.filter.scopes and e.filter.scopes.arena == "all"
        end,
        function(v)
            local e = sel()
            if not e then return end
            local sc = ensureScopes(e.filter)
            sc.arena = v and "all" or baseScope(e.filter)
            applyChange()
            pages.views.refresh()
        end)
    add(pvpChk, 22)

    local perPlaceChk = makeCheck(p, "Use a different setting per place",
        function()
            local e = sel()
            return e and e.filter.perPlace or (e and not scopesAreSimple(e.filter))
        end,
        function(v)
            local e = sel()
            if not e then return end
            e.filter.perPlace = v or nil
            if not v then
                -- collapsing back: the world setting wins everywhere, with the
                -- arena checkbox re-applied on top
                local sc = ensureScopes(e.filter)
                local base = sc.world or "me"
                local arenaWide = sc.arena == "all"
                for _, loc in ipairs(NS.LOCATIONS) do
                    sc[loc.key] = (loc.key == "arena" and arenaWide) and "all" or base
                end
                applyChange()
            end
            pages.views.refresh()
        end)
    add(perPlaceChk, 22)

    local locDDs = {}
    for _, loc in ipairs(NS.LOCATIONS) do
        local dd = makeDropdown(p, loc.label, NS.SCOPE_CHOICES,
            function()
                local e = sel()
                if not e or not e.filter.scopes then return "me" end
                return e.filter.scopes[loc.key] or "me"
            end,
            function(v)
                local e = sel()
                if not e then return end
                ensureScopes(e.filter)[loc.key] = v
                -- without this the grid folds itself away mid-edit the moment
                -- the last differing place is set back to match the rest
                e.filter.perPlace = true
                applyChange()
                pages.views.refresh()
            end)
        add(dd, 24)
        locDDs[#locDDs + 1] = dd
    end

    local castChk = W(makeCheck(p, "Hide 'begins casting' lines",
        function()
            local e = sel()
            return e and e.filter.hideCastStart
        end,
        function(v)
            local e = sel()
            if e then
                e.filter.hideCastStart = v
                applyChange()
            end
        end), 22)

    local catHead = add(label(p, "Event types", 12, NS.COLORS.accent), 18)
    local catBase = CreateFrame("Frame", nil, p)
    catBase:SetSize(520, math.ceil(#NS.CATEGORY_LIST / 2) * 22)
    add(catBase, math.ceil(#NS.CATEGORY_LIST / 2) * 22)
    local catChecks = {}
    for i, cat in ipairs(NS.CATEGORY_LIST) do
        local chk = makeCheck(catBase, cat.label,
            function()
                local e = sel()
                return e and e.filter.categories and e.filter.categories[cat.key]
            end,
            function(v)
                local e = sel()
                if e and e.filter.categories then
                    e.filter.categories[cat.key] = v
                    applyChange()
                    -- the hidden-buff section only exists when auras are shown
                    if cat.key == "auras" then pages.views.refresh() end
                end
            end)
        chk:SetPoint("TOPLEFT", catBase, "TOPLEFT",
            ((i - 1) % 2) * 250, -math.floor((i - 1) / 2) * 22)
        catChecks[#catChecks + 1] = chk
    end

    -- ---------------------------------------------------------------------
    -- Hidden auras. Deliberately global: a zone buff that annoys you here
    -- annoys you everywhere, and blacklisting it per window would be silly.
    -- ---------------------------------------------------------------------
    local auraHead = add(label(p, "Hidden buffs and debuffs", 12, NS.COLORS.accent), 18)
    local auraHint = add(label(p,
        "Never shown in any combat window. Made for zone buffs and other people's\nfood, drink and flasks. You can also right-click any buff in the log to hide it.",
        11, NS.COLORS.dim), 30)

    local auraRow = CreateFrame("Frame", nil, p)
    auraRow:SetSize(520, 22)
    add(auraRow, 26)

    local pickBtn = makeButton(auraRow, "Pick from my buffs", 150, function()
        local auras = NS.CurrentAuras("player")
        local items = { { text = "Buffs and debuffs on you", header = true } }
        if #auras == 0 then
            items[#items + 1] = { text = "You have no auras right now", disabled = true }
        end
        local kind
        for _, a in ipairs(auras) do
            if a.kind ~= kind then
                if kind then items[#items + 1] = { separator = true } end
                kind = a.kind
            end
            items[#items + 1] = {
                text = a.name,
                checked = NS.AuraHidden(a.name),
                func = function()
                    NS.ToggleAuraHidden(a.name)
                    pages.views.refresh()
                end,
            }
        end
        NS.ShowMenu(items)
    end)
    pickBtn:SetPoint("LEFT", 0, 0)
    attachTip(pickBtn, "Pick from my buffs")

    local auraEdit = makeEdit(auraRow, "", 200,
        function() return "" end,
        function(v)
            if NS.HideAura(v) then pages.views.refresh() end
        end)
    auraEdit:SetPoint("LEFT", pickBtn, "RIGHT", 8, 0)
    auraEdit.edit:ClearAllPoints()
    auraEdit.edit:SetPoint("LEFT", auraEdit, "LEFT", 0, 0)
    -- makeEdit already installed the tooltip handler; just give it a title
    auraEdit.edit.tipTitle = "Hide a buff by name"

    local auraEditHint = label(auraRow, "type a name, press Enter", 10, NS.COLORS.dim)
    auraEditHint:SetPoint("LEFT", auraEdit.edit, "RIGHT", 8, 0)

    local auraBase = CreateFrame("Frame", nil, p)
    auraBase:SetSize(520, 22)
    add(auraBase, 22)
    local auraRows = {}
    local auraEmpty = label(auraBase, "Nothing hidden yet.", 11, NS.COLORS.dim)
    auraEmpty:SetPoint("TOPLEFT", auraBase, "TOPLEFT", 0, -2)

    -- shown only when other people can actually appear
    local othersHead = add(label(p, "When other players are shown", 12, NS.COLORS.accent), 18)
    local othersBase = CreateFrame("Frame", nil, p)
    othersBase:SetSize(520, 2 * 22)
    add(othersBase, 2 * 22)
    local othersChecks = {}
    do
        local defs = {
            { "Hide their professions", "hideOtherProfessions", 0, 0 },
            { "Hide their cooking", "hideOtherCooking", 250, 0 },
            { "Hide their fishing", "hideOtherFishing", 0, 1 },
        }
        for _, d in ipairs(defs) do
            local field = d[2]
            local chk = makeCheck(othersBase, d[1],
                function()
                    local e = sel()
                    return e and e.filter[field]
                end,
                function(v)
                    local e = sel()
                    if e then
                        e.filter[field] = v
                        applyChange()
                    end
                end)
            chk:SetPoint("TOPLEFT", othersBase, "TOPLEFT", d[3], -d[4] * 22)
            othersChecks[#othersChecks + 1] = chk
        end
    end

    -- =====================================================================
    -- CHAT VIEW EDITOR
    -- =====================================================================
    local chatHead = add(label(p, "Messages this tab shows", 13, NS.COLORS.accent), 20)

    local typeBase = CreateFrame("Frame", nil, p)
    local groupOrder = {
        { key = "player",  label = "Player chat" },
        { key = "channel", label = "Channels" },
        { key = "info",    label = "Info & system" },
        { key = "npc",     label = "NPC" },
    }
    local typeChecks = {}
    local ty = 0
    for _, grp in ipairs(groupOrder) do
        local gl = label(typeBase, grp.label, 11, NS.COLORS.accent)
        gl:SetPoint("TOPLEFT", typeBase, "TOPLEFT", 0, -ty)
        ty = ty + 18
        local col = 0
        for _, t in ipairs(NS.CHAT.TYPES) do
            if t.group == grp.key then
                local chk = makeCheck(typeBase, t.label,
                    function()
                        local e = sel()
                        return e and e.filter and e.filter.types and e.filter.types[t.key]
                    end,
                    function(v)
                        local e = sel()
                        if e and e.filter and e.filter.types then
                            e.filter.types[t.key] = v
                            NS.RefreshChat()
                        end
                    end)
                chk:SetPoint("TOPLEFT", typeBase, "TOPLEFT", col * 250, -ty)
                typeChecks[#typeChecks + 1] = chk
                col = col + 1
                if col == 2 then col = 0 ty = ty + 22 end
            end
        end
        if col ~= 0 then ty = ty + 22 end
        ty = ty + 4
    end
    typeBase:SetSize(520, ty)
    add(typeBase, ty, nil, 0)

    local chanHead = add(label(p, "Channels in this tab", 12, NS.COLORS.accent), 18)
    local chanAll = makeCheck(p, "All channels, including ones I join later",
        function()
            local e = sel()
            return e and e.filter and e.filter.channelsAll
        end,
        function(v)
            local e = sel()
            if not e or not e.filter then return end
            local f = e.filter
            if v then
                f.channelsAll = true
            else
                f.channelsAll = false
                f.channelNames = f.channelNames or {}
                for _, ch in ipairs(NS.CHAT.JoinedChannels()) do
                    local key = string.lower(ch.name):gsub("%s+", "")
                    key = key:match("^(.-)%-") or key
                    f.channelNames[key] = true
                end
            end
            NS.RefreshChat()
            pages.views.refresh()
        end)
    add(chanAll, 22)

    local chanBase = CreateFrame("Frame", nil, p)
    chanBase:SetSize(520, 6 * 22)
    add(chanBase, 6 * 22)
    local chanRows = {}

    local tip = add(label(p, "Tip: right-click any tab in the chat window for the same actions.", 11, NS.COLORS.dim), 20)

    pages.views.entries = entries

    pages.views.selectWindow = function(i)
        selKind, selIdx = "window", i
        pages.views.refresh()
    end
    pages.views.selectChatView = function(i)
        selKind, selIdx = "chat", i
        pages.views.refresh()
    end

    -- =====================================================================
    pages.views.refresh = function()
        local e = sel()
        if not e then
            selLabel:SetText(C("Nothing to edit.", NS.COLORS.dim))
            return
        end
        selLabel:SetText(C("Editing: ", NS.COLORS.dim) ..
            C(e.name, NS.COLORS.accent) .. C("   (" .. e.what .. ")", NS.COLORS.dim))

        -- combat filters only: a chat tab's filter is a different shape and
        -- DefaultFilterAll would destroy it
        local f = e.isCombat and e.filter or nil
        local extra = {}
        if f then
            if f.spellMode == "allow" or f.spellMode == "block" then
                local n = 0
                for _ in pairs(f.spellList or {}) do n = n + 1 end
                extra[#extra + 1] = (f.spellMode == "allow" and "only " or "hiding ") ..
                    n .. " spell" .. (n == 1 and "" or "s")
            end
            if (f.minAmount or 0) > 0 then
                extra[#extra + 1] = "minimum " .. f.minAmount
            end
            if f.srcName then extra[#extra + 1] = "from " .. f.srcName end
            if f.dstName then extra[#extra + 1] = "on " .. f.dstName end
            -- roles read better as what IS shown; several presets pin them on
            -- purpose, so "no hostile, neutral, ..." looked like a fault
            local on, off = {}, 0
            for _, role in ipairs(NS.ROLE_LIST) do
                if f.sources and f.sources[role.key] == false then off = off + 1
                else on[#on + 1] = string.lower(role.label) end
            end
            if off > 0 and #on > 0 then
                extra[#extra + 1] = "sources: " .. table.concat(on, ", ")
            end
        end
        resetBtn:SetShown(f ~= nil)
        if #extra > 0 then
            hiddenLabel:SetText(C("Also filtered - " .. table.concat(extra, "  \194\183  "),
                NS.COLORS.dim))
            hiddenLabel:Show()
        else
            hiddenLabel:SetText("")
            hiddenLabel:Hide()
        end

        if e.kind == "window" then
            moveBtn.text:SetText(C("Dock as tab", NS.COLORS.accent))
        elseif e.view and e.view.mode == "window" then
            moveBtn.text:SetText(C("Dock as tab", NS.COLORS.accent))
        else
            moveBtn.text:SetText(C("Pop out", NS.COLORS.accent))
        end

        local isCombat = e.isCombat
        local aoe = isCombat and e.filter.aoeFarm
        -- combat half
        combatHead:SetShown(isCombat)
        aoeChk:SetShown(isCombat)
        aoeHint:SetShown(isCombat and aoe and true or false)
        dirDD:SetShown(isCombat and not aoe)
        local showWho = isCombat and not aoe
        whoHead:SetShown(showWho)
        local e = sel()
        local perPlace = showWho and e
            and (e.filter.perPlace or not scopesAreSimple(e.filter)) or false
        simpleDD:SetShown(showWho and not perPlace)
        pvpChk:SetShown(showWho and not perPlace
            and (e == nil or baseScope(e.filter) ~= "all"))
        perPlaceChk:SetShown(showWho)
        for _, dd in ipairs(locDDs) do dd:SetShown(showWho and perPlace) end
        castChk:SetShown(showWho)
        catHead:SetShown(isCombat and not aoe)
        catBase:SetShown(isCombat and not aoe)

        -- the aura blacklist is pointless unless this view shows auras at all
        local showAuras = isCombat and not aoe
            and e.filter.categories and e.filter.categories.auras and true or false
        auraHead:SetShown(showAuras)
        auraHint:SetShown(showAuras)
        auraRow:SetShown(showAuras)
        auraBase:SetShown(showAuras)
        if showAuras then
            local hidden = NS.HiddenAuraList()
            for _, r in ipairs(auraRows) do r:Hide() end
            for i, a in ipairs(hidden) do
                local r = auraRows[i]
                if not r then
                    r = CreateFrame("Frame", nil, auraBase)
                    r:SetSize(360, 20)
                    r:SetPoint("TOPLEFT", auraBase, "TOPLEFT", 0, -(i - 1) * 22)
                    r.name = label(r, "", 11)
                    r.name:SetPoint("LEFT", 4, 0)
                    r.name:SetWidth(270)
                    r.name:SetWordWrap(false)
                    r.del = makeButton(r, "show it", 70, nil)
                    r.del:SetPoint("LEFT", 286, 0)
                    auraRows[i] = r
                end
                r.name:SetText(C(a.name, NS.COLORS.buff))
                r.del:SetScript("OnClick", function()
                    NS.ShowAura(a.name)
                    pages.views.refresh()
                end)
                r:Show()
            end
            auraEmpty:SetShown(#hidden == 0)
            local h = math.max(#hidden * 22, 20)
            auraBase.llHeight = h
            auraBase:SetHeight(h)
            auraEdit.Refresh()
        end

        local showOthers = isCombat and not aoe and NS.EffectiveScope(e.filter) ~= "me"
        othersHead:SetShown(showOthers)
        othersBase:SetShown(showOthers)

        -- chat half
        chatHead:SetShown(not isCombat)
        typeBase:SetShown(not isCombat)
        chanHead:SetShown(not isCombat)
        chanAll:SetShown(not isCombat)
        chanBase:SetShown(not isCombat)

        for _, w in ipairs(widgets) do if w.Refresh then w.Refresh() end end
        if dirDD.Refresh then dirDD.Refresh() end
        for _, dd in ipairs(locDDs) do if dd.Refresh then dd.Refresh() end end
        if simpleDD.Refresh then simpleDD.Refresh() end
        if pvpChk.Refresh then pvpChk.Refresh() end
        if perPlaceChk.Refresh then perPlaceChk.Refresh() end
        for _, c in ipairs(catChecks) do c.Refresh() end
        for _, c in ipairs(othersChecks) do c.Refresh() end
        for _, c in ipairs(typeChecks) do c.Refresh() end
        if chanAll.Refresh then chanAll.Refresh() end

        -- per-channel rows for chat tabs
        for _, r in ipairs(chanRows) do r:Hide() end
        local shownRows = 0
        if not isCombat and e.filter then
            local joined = NS.CHAT.JoinedChannels()
            for i, ch in ipairs(joined) do
                if i > 12 then break end
                shownRows = i
                local key = string.lower(ch.name):gsub("%s+", "")
                key = key:match("^(.-)%-") or key
                local r = chanRows[i]
                if not r then
                    r = makeCheck(chanBase, "",
                        function()
                            local ee = sel()
                            if not ee or not ee.filter then return false end
                            local row = chanRows[i]
                            return ee.filter.channelsAll or (row and ee.filter.channelNames[row.chanKey]) or false
                        end,
                        function(val)
                            local ee = sel()
                            if not ee or not ee.filter then return end
                            local f = ee.filter
                            if f.channelsAll then
                                f.channelsAll = false
                                f.channelNames = {}
                                for _, ch2 in ipairs(NS.CHAT.JoinedChannels()) do
                                    local k2 = string.lower(ch2.name):gsub("%s+", "")
                                    k2 = k2:match("^(.-)%-") or k2
                                    f.channelNames[k2] = true
                                end
                            end
                            f.channelNames[chanRows[i].chanKey] = val or nil
                            NS.RefreshChat()
                            pages.views.refresh()
                        end)
                    r:SetPoint("TOPLEFT", chanBase, "TOPLEFT",
                        ((i - 1) % 2) * 250, -math.floor((i - 1) / 2) * 22)
                    chanRows[i] = r
                end
                r.chanKey = key
                r.label:SetText(C(ch.id .. ". " .. ch.name, NS.COLORS.text))
                r:Show()
                r.Refresh()
            end
        end

        -- the channel grid is only as tall as the channels you are actually in
        local chanH = math.max(math.ceil(shownRows / 2) * 22, 0)
        chanBase.llHeight = chanH
        chanBase:SetHeight(math.max(chanH, 1))
        chanBase:SetShown(not isCombat and shownRows > 0)

        relayout()
    end

    pages.views.refresh()
end

local function buildChannels()
    local p = newPage("channels", 1800)
    local add, _chatH, relayout = stacker(p)
    local widgets = {}
    local function refreshChatFmt()
        NS.InvalidateFormats()
        if NS.RefreshChat then NS.RefreshChat() end
    end

    add(label(p, "Chat", 14, NS.COLORS.accent), 22)

    add(label(p, "Chat behaviour", 12, NS.COLORS.accent), 18)
    local chatBeh = {
        { "Short channel tags ([2], [G])",
            function() return NS.db.chat.shortTags end,
            function(v) NS.db.chat.shortTags = v NS.InvalidateFormats() if NS.RefreshChat then NS.RefreshChat() end end },
        { "Alt-click a name to invite",
            function() return NS.db.chat.altInvite end,
            function(v) NS.db.chat.altInvite = v end },
        { "Clickable URLs (click to copy)",
            function() return NS.db.chat.urls end,
            function(v) NS.db.chat.urls = v NS.InvalidateFormats() if NS.RefreshChat then NS.RefreshChat() end end },
        { "Sound on incoming whisper",
            function() return NS.db.chat.whisperSound end,
            function(v) NS.db.chat.whisperSound = v end },
        { "Typing box on top (not bottom)",
            function() return NS.db.chat.editBoxTop end,
            function(v) NS.db.chat.editBoxTop = v if NS.ApplyChatLayout then NS.ApplyChatLayout() end end },
        { "Show levels next to names",
            function() return NS.db.chat.showLevels end,
            function(v)
                NS.db.chat.showLevels = v
                NS.InvalidateFormats()
                if NS.RefreshChat then NS.RefreshChat() end
            end },
        { "Fade chat out when it goes quiet",
            function() return NS.db.chat.fade end,
            function(v)
                NS.db.chat.fade = v
                -- chat-only setting: ApplyAppearance re-formats the whole
                -- combat buffer for nothing
                if NS.ApplyChatAppearance then NS.ApplyChatAppearance() end
                pages.channels.refresh()
            end },
    }
    local cbBase = CreateFrame("Frame", nil, p)
    cbBase:SetSize(500, math.ceil(#chatBeh / 2) * 22)
    add(cbBase, math.ceil(#chatBeh / 2) * 22)
    for i, def in ipairs(chatBeh) do
        local chk = makeCheck(cbBase, def[1], def[2], def[3])
        widgets[#widgets + 1] = chk
        chk:SetPoint("TOPLEFT", cbBase, "TOPLEFT",
            ((i - 1) % 2) * 250, -math.floor((i - 1) / 2) * 22)
    end

    widgets[#widgets + 1] = add(makeDropdown(p, "Whisper header",
        NS.WHISPER_HEADER_MODES,
        function() return NS.db.chat.whisperHeader end,
        function(v)
            NS.db.chat.whisperHeader = v
            local eb = _G.ChatFrame1EditBox
            -- going back to Blizzard's needs its own header rebuilt, since
            -- ours overwrote the text in place
            if eb and _G.ChatEdit_UpdateHeader then pcall(ChatEdit_UpdateHeader, eb) end
            if NS.StyleEditHeader then NS.StyleEditHeader() end
        end), 24)

    -- ApplyAppearance re-formats the whole event buffer; doing that on every
    -- step of a drag is a stutter for a value that only affects fade timing
    local fadeSlider = add(makeSlider(p, "Fade chat after", 10, 600, 10,
        function() return NS.db.chat.fadeTime end,
        function(v) NS.db.chat.fadeTime = v end, "s",
        function() if NS.ApplyChatAppearance then NS.ApplyChatAppearance() end end), 34)
    widgets[#widgets + 1] = fadeSlider

    widgets[#widgets + 1] = add(makeSlider(p, "Wheel scrolls", 1, 10, 1,
        function() return NS.db.chat.scrollLines end,
        function(v) NS.db.chat.scrollLines = v end, " lines"), 34)

    widgets[#widgets + 1] = add(makeSlider(p, "Chat lines saved", 100, 2000, 100,
        function() return NS.db.chat.historySize end,
        function(v) NS.db.chat.historySize = v end, " lines"), 34)

    -- ---------------------------------------------------------------------
    -- Words that matter, and words that do not
    -- ---------------------------------------------------------------------
    add(label(p, "Alert words", 12, NS.COLORS.accent), 18)
    add(label(p, "Chat lines containing these light up, ping you, and mark the tab they\nlanded in. Your own name counts unless you turn that off.", 11, NS.COLORS.dim), 30)

    widgets[#widgets + 1] = add(makeCheck(p, "Alert me on my own name",
        function() return NS.db.chat.alerts.ownName end,
        function(v)
            NS.db.chat.alerts.ownName = v
            NS.InvalidateFormats()
            if NS.RefreshChat then NS.RefreshChat() end
        end), 20)

    widgets[#widgets + 1] = add(makeEdit(p, "Alert words", 260,
        function() return NS.CHAT.WordList(NS.db.chat.alerts.words) end,
        function(v)
            NS.db.chat.alerts.words = NS.CHAT.ParseWordList(v)
            NS.InvalidateFormats()
            if NS.RefreshChat then NS.RefreshChat() end
        end), 24)

    local alertRow = CreateFrame("Frame", nil, p)
    alertRow:SetSize(500, 22)
    add(alertRow, 26)
    local alertColor = makeColor(alertRow, "",
        function()
            local hex = NS.db.chat.alerts.color or NS.COLORS.highlight
            return { r = tonumber(hex:sub(1, 2), 16) / 255,
                     g = tonumber(hex:sub(3, 4), 16) / 255,
                     b = tonumber(hex:sub(5, 6), 16) / 255, a = 1 }
        end, nil)
    alertColor:SetPoint("LEFT", 0, 0)
    alertColor:SetScript("OnClick", function()
        local hex = NS.db.chat.alerts.color or NS.COLORS.highlight
        NS.OpenColorPicker(tonumber(hex:sub(1, 2), 16) / 255,
            tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, 1,
            function(r, g, b)
                NS.db.chat.alerts.color = NS.RGBToHex(r, g, b)
                NS.InvalidateFormats()
                if NS.RefreshChat then NS.RefreshChat() end
                pages.channels.refresh()
            end)
    end)
    attachTip(alertColor, "Alert colour")
    local alertColorLbl = label(alertRow, "colour", 11, NS.COLORS.dim)
    alertColorLbl:SetPoint("LEFT", alertColor, "RIGHT", 6, 0)

    local alertSoundBtn = makeButton(alertRow, "", 170, function()
        local items = { { text = "Sound for alert words", header = true } }
        for _, s in ipairs(NS.ALERT_SOUNDS) do
            if not s.custom then
                items[#items + 1] = { text = s.name,
                    checked = NS.db.chat.alerts.soundKey == s.key and NS.db.chat.alerts.sound,
                    func = function()
                        NS.db.chat.alerts.soundKey = s.key
                        NS.db.chat.alerts.sound = s.key ~= "none"
                        NS.PlayAlertSound(s.key, NS.db.chat.alerts.soundFile)
                        pages.channels.refresh()
                    end }
            end
        end
        -- alerts.soundFile has always been plumbed through to PlayAlertSound;
        -- there was simply no way to set it, so a custom alert sound was
        -- possible for spell highlights and not for alert words
        items[#items + 1] = { text = "Custom file...",
            checked = NS.db.chat.alerts.soundKey == "custom",
            func = function()
                NS.ShowInputBox("Sound file - full path, e.g. Interface\\AddOns\\MySounds\\ping.ogg",
                    NS.db.chat.alerts.soundFile or "", function(v)
                        v = (v or ""):gsub("^%s+", ""):gsub("%s+$", "")
                        if v == "" then return end
                        NS.db.chat.alerts.soundFile = v
                        NS.db.chat.alerts.soundKey = "custom"
                        NS.db.chat.alerts.sound = true
                        NS.PlayAlertSound("custom", v)
                        pages.channels.refresh()
                    end)
            end }
        local lsm = NS.SharedMediaSounds()
        if #lsm > 0 then
            items[#items + 1] = { separator = true }
            items[#items + 1] = { text = #lsm .. " from LibSharedMedia" ..
                " - wheel to scroll, shift-wheel to page", disabled = true }
        end
        for _, s in ipairs(lsm) do
            items[#items + 1] = { text = s.name,
                checked = NS.db.chat.alerts.soundKey == s.key,
                func = function()
                    NS.db.chat.alerts.soundKey = s.key
                    NS.db.chat.alerts.sound = true
                    NS.PlayAlertSound(s.key)
                    pages.channels.refresh()
                end }
        end
        NS.ShowMenu(items)
    end)
    alertSoundBtn:SetPoint("LEFT", alertColorLbl, "RIGHT", 20, 0)
    attachTip(alertSoundBtn, "Alert sound")
    pages.channels.updateAlertSound = function()
        local a = NS.db.chat.alerts
        local nm = "No sound"
        if a.sound then
            for _, s in ipairs(NS.ALERT_SOUNDS) do
                if s.key == a.soundKey then nm = s.name end
            end
            if a.soundKey and a.soundKey:find("^lsm:") then nm = a.soundKey:sub(5) end
        end
        alertSoundBtn.text:SetText(C(nm, a.sound and NS.COLORS.accent or NS.COLORS.dim))
    end

    widgets[#widgets + 1] = add(makeCheck(p, "Flag the tab",
        function() return NS.db.chat.alerts.flashTabs end,
        function(v) NS.db.chat.alerts.flashTabs = v end), 20, nil, 10)

    add(label(p, "Blocked words", 12, NS.COLORS.accent), 18)
    add(label(p, "Any chat line containing one of these is dropped before it reaches a\nwindow. Built for gold sellers. Matching is on plain substrings.", 11, NS.COLORS.dim), 30)

    widgets[#widgets + 1] = add(makeEdit(p, "Blocked words", 260,
        function() return NS.CHAT.WordList(NS.db.chat.block.words) end,
        function(v)
            NS.db.chat.block.words = NS.CHAT.ParseWordList(v)
            pages.channels.refresh()
        end), 24)

    widgets[#widgets + 1] = add(makeCheck(p, "Never block guild or group",
        function() return NS.db.chat.block.sparePeers end,
        function(v) NS.db.chat.block.sparePeers = v end), 20)

    local blockCount = add(label(p, "", 11, NS.COLORS.dim), 20)
    pages.channels.updateBlockCount = function()
        local n = NS.db.chat.block.count or 0
        local nWords = #(NS.db.chat.block.words or {})
        if nWords == 0 then
            blockCount:SetText(C("Nothing blocked. Add words above, comma separated.", NS.COLORS.dim))
        else
            blockCount:SetText(C(nWords .. " blocked word" .. (nWords == 1 and "" or "s") ..
                ", " .. n .. " message" .. (n == 1 and "" or "s") .. " dropped so far.", NS.COLORS.dim))
        end
    end

    add(label(p, "Repeated messages", 12, NS.COLORS.accent), 18)
    widgets[#widgets + 1] = add(makeCheck(p, "Collapse repeats (x3)",
        function() return NS.db.chat.dedupe.enabled end,
        function(v) NS.db.chat.dedupe.enabled = v pages.channels.refresh() end), 20)
    local dupPublic = add(makeCheck(p, "Public chat only",
        function() return NS.db.chat.dedupe.publicOnly end,
        function(v) NS.db.chat.dedupe.publicOnly = v end), 20)
    local dupSecs = add(makeSlider(p, "Repeat window", 5, 300, 5,
        function() return NS.db.chat.dedupe.seconds end,
        function(v) NS.db.chat.dedupe.seconds = v end, "s"), 34, nil, 10)
    widgets[#widgets + 1] = dupPublic
    widgets[#widgets + 1] = dupSecs


    -- server channels --------------------------------------------------------
    add(label(p, "Server channels", 12, NS.COLORS.accent), 18)
    add(label(p, "One click to join or leave. New channels appear in any tab set to\n\"All channels\", or can be picked per tab under Windows & Tabs.", 11, NS.COLORS.dim), 30)

    local chanListBase = CreateFrame("Frame", nil, p)
    chanListBase:SetSize(500, 16 * 24)
    add(chanListBase, 16 * 24, nil, 0)
    local chanRows = {}

    local customEdit = makeEdit(p, "Join another channel", 160,
        function() return "" end,
        function(v)
            v = v:gsub("^%s+", ""):gsub("%s+$", "")
            if v ~= "" then
                NS.CHAT.JoinChannel(v)
                C_Timer.After(0.5, function() pages.channels.refresh() end)
            end
        end)
    add(customEdit, 26)

    -- colors -----------------------------------------------------------------
    local colorsHead = add(label(p, "Chat colors", 12, NS.COLORS.accent), 18)
    local colorsHint = add(label(p, "Click a swatch to override any color; reset restores Blizzard's.", 11, NS.COLORS.dim), 18)

    local colorBase = CreateFrame("Frame", nil, p)
    local colorRows = {}
    local nTypes = #NS.CHAT.TYPES
    colorBase:SetSize(500, math.ceil(nTypes / 2) * 24 + 10)
    add(colorBase, math.ceil(nTypes / 2) * 24 + 10, nil, 0)

    local chanColorsHead = add(label(p, "Channel colors", 12, NS.COLORS.accent), 18)
    local chanColorBase = CreateFrame("Frame", nil, p)
    chanColorBase:SetSize(500, 8 * 24)
    add(chanColorBase, 8 * 24, nil, 0)
    local chanColorRows = {}

    local function makeColorRow(parent, i, perRow)
        local r = CreateFrame("Frame", nil, parent)
        r:SetSize(240, 22)
        r:SetPoint("TOPLEFT", parent, "TOPLEFT",
            ((i - 1) % perRow) * 250, -math.floor((i - 1) / perRow) * 24)
        r.swatch = CreateFrame("Button", nil, r, BackdropTemplateMixin and "BackdropTemplate" or nil)
        r.swatch:SetSize(16, 16)
        r.swatch:SetPoint("LEFT", 0, 0)
        NS.SkinPanel(r.swatch, { r = 0, g = 0, b = 0, a = 1 }, { r = 0.4, g = 0.42, b = 0.48, a = 1 })
        r.swatch.tex = r.swatch:CreateTexture(nil, "ARTWORK")
        r.swatch.tex:SetPoint("TOPLEFT", 2, -2)
        r.swatch.tex:SetPoint("BOTTOMRIGHT", -2, 2)
        r.name = label(r, "", 11)
        r.name:SetPoint("LEFT", r.swatch, "RIGHT", 6, 0)
        r.reset = CreateFrame("Button", nil, r)
        r.reset:SetSize(36, 16)
        r.reset:SetPoint("RIGHT", -2, 0)
        r.reset.text = label(r.reset, "reset", 10, NS.COLORS.dim)
        r.reset.text:SetPoint("RIGHT")
        -- a long channel name would otherwise run under its own reset button
        r.name:SetPoint("RIGHT", r.reset, "LEFT", -6, 0)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.reset.hl = r.reset:CreateTexture(nil, "HIGHLIGHT")
        r.reset.hl:SetAllPoints()
        r.reset.hl:SetColorTexture(1, 1, 1, 0.06)
        return r
    end

    local function bindColorRow(r, name, getHex, setHex, canReset)
        local hex = getHex()
        r.swatch.tex:SetColorTexture(hex2rgb(hex))
        r.name:SetText(C(name, hex))
        r.swatch:SetScript("OnClick", function()
            local cr, cg, cb = hex2rgb(getHex())
            NS.OpenColorPicker(cr, cg, cb, 1, function(nr, ng, nb)
                setHex(NS.RGBToHex(nr, ng, nb))
                refreshChatFmt()
                pages.channels.refresh()
            end)
        end)
        r.reset:SetScript("OnClick", function()
            setHex(nil)
            refreshChatFmt()
            pages.channels.refresh()
        end)
        r.reset:SetShown(canReset)
        r.reset.text:SetShown(canReset)
        r:Show()
    end

    -- The lists here have no fixed size, so they report their real height and
    -- the shared layout pass closes the gaps. This used to be a hand-rolled
    -- chain of anchors that could not cope with anything above it changing.
    local function reflow(listRows, colorRows2)
        -- only 16 join/leave rows are ever drawn, and the channel colour
        -- swatches sit two per row - reserving space per entry left a gap
        local listH = math.max(1, math.min(16, listRows)) * 24
        chanListBase.llHeight = listH
        chanListBase:SetHeight(listH)
        local chH = math.ceil(math.max(1, colorRows2) / 2) * 24
        chanColorBase.llHeight = chH
        chanColorBase:SetHeight(chH)
        -- the fade delay is meaningless with fading switched off
        fadeSlider:SetShown(NS.db.chat.fade and true or false)
        -- the two repeat settings only mean anything while collapsing is on
        local dedupeOn = NS.db.chat.dedupe.enabled and true or false
        dupPublic:SetShown(dedupeOn)
        dupSecs:SetShown(dedupeOn)
        relayout()
    end

    pages.channels.refresh = function()
        local colors = NS.db.chat.colors

        -- server channel join/leave rows
        for _, r in ipairs(chanRows) do r:Hide() end
        local joined = NS.CHAT.JoinedChannels()
        local joinedSet = {}
        local n = 0
        for _, ch in ipairs(joined) do
            joinedSet[string.lower(ch.name)] = true
            n = n + 1
            if n <= 16 then
                local r = chanRows[n]
                if not r then
                    r = CreateFrame("Frame", nil, chanListBase, BackdropTemplateMixin and "BackdropTemplate" or nil)
                    NS.SkinPanel(r, { r = 0, g = 0, b = 0, a = 0.35 })
                    r:SetSize(500, 22)
                    r:SetPoint("TOPLEFT", 0, -(n - 1) * 24)
                    r.name = label(r, "", 11)
                    r.name:SetPoint("LEFT", 8, 0)
                    r.btn = makeButton(r, "", 60, nil)
                    r.btn:SetPoint("RIGHT", -4, 0)
                    chanRows[n] = r
                end
                r.name:SetText(C(ch.id .. ".  " .. ch.name, NS.COLORS.text))
                r.btn.text:SetText(C("leave", "ff8080"))
                r.btn:SetScript("OnClick", function()
                    NS.CHAT.LeaveChannel(ch.name)
                    C_Timer.After(0.5, function() pages.channels.refresh() end)
                end)
                r:Show()
            end
        end
        for _, name in ipairs(NS.CHAT.ServerChannels()) do
            if not joinedSet[string.lower(name)] then
                n = n + 1
                if n > 16 then break end
                local r = chanRows[n]
                if not r then
                    r = CreateFrame("Frame", nil, chanListBase, BackdropTemplateMixin and "BackdropTemplate" or nil)
                    NS.SkinPanel(r, { r = 0, g = 0, b = 0, a = 0.35 })
                    r:SetSize(500, 22)
                    r:SetPoint("TOPLEFT", 0, -(n - 1) * 24)
                    r.name = label(r, "", 11)
                    r.name:SetPoint("LEFT", 8, 0)
                    r.btn = makeButton(r, "", 60, nil)
                    r.btn:SetPoint("RIGHT", -4, 0)
                    chanRows[n] = r
                end
                r.name:SetText(C(name, NS.COLORS.dim))
                r.btn.text:SetText(C("join", NS.COLORS.accent))
                r.btn:SetScript("OnClick", function()
                    NS.CHAT.JoinChannel(name)
                    C_Timer.After(0.5, function() pages.channels.refresh() end)
                end)
                r:Show()
            end
        end

        -- type colors
        for i, t in ipairs(NS.CHAT.TYPES) do
            local r = colorRows[i]
            if not r then
                r = makeColorRow(colorBase, i, 2)
                colorRows[i] = r
            end
            bindColorRow(r, t.label,
                function() return colors.types[t.key] or NS.CHAT.DefaultTypeColor(t.key) end,
                function(hex) colors.types[t.key] = hex end,
                colors.types[t.key] ~= nil)
        end

        -- per-channel colors
        for _, r in ipairs(chanColorRows) do r:Hide() end
        for i, ch in ipairs(joined) do
            if i > 8 then break end
            local r = chanColorRows[i]
            if not r then
                r = makeColorRow(chanColorBase, i, 2)
                chanColorRows[i] = r
            end
            local key = string.lower(ch.name):gsub("%s+", "")
            key = key:match("^(.-)%-") or key
            bindColorRow(r, ch.id .. ". " .. ch.name,
                function() return colors.channels[key] or NS.CHAT.DefaultChannelColor() end,
                function(hex) colors.channels[key] = hex end,
                colors.channels[key] ~= nil)
        end

        customEdit.Refresh()
        for _, w in ipairs(widgets) do if w.Refresh then w.Refresh() end end
        if pages.channels.updateAlertSound then pages.channels.updateAlertSound() end
        if pages.channels.updateBlockCount then pages.channels.updateBlockCount() end
        alertColor.Refresh()
        reflow(n, math.min(8, #joined))
    end
end

local function buildHighlights()
    local p = newPage("highlights", 620)
    local add = stacker(p)

    add(label(p, "Spell Highlights", 14, NS.COLORS.accent), 20)
    add(label(p, "Highlighted spells get an alert icon, a custom color, and a sound of your\nchoice wherever they appear. Great for procs, enemy trinkets, and cooldowns.", 11, NS.COLORS.dim), 32)

    local widgets = {}
    local function W(w, h, indent, gap)
        widgets[#widgets + 1] = w
        return add(w, h, indent, gap)
    end

    -- Every sound the client can offer us, in menu order.
    local function soundChoices()
        local list = {}
        for _, s in ipairs(NS.ALERT_SOUNDS) do
            if not s.custom then list[#list + 1] = { key = s.key, label = s.name } end
        end
        -- "Custom file..." sits with the built-ins, not after a LibSharedMedia
        -- pack that can be two hundred entries long
        list[#list + 1] = { key = "custom", label = "Custom file..." }
        for _, s in ipairs(NS.SharedMediaSounds()) do
            list[#list + 1] = { key = s.key, label = s.name }
        end
        return list
    end

    local function soundLabel(key)
        if not key or key == "none" then return "No sound" end
        for _, it in ipairs(soundChoices()) do
            if it.key == key then return it.label end
        end
        return tostring(key)
    end

    W(makeCheck(p, "Play highlight sounds",
        function() return NS.db.general.highlightSound end,
        function(v) NS.db.general.highlightSound = v pages.highlights.refresh() end), 22)

    -- refilled in place on refresh, so sounds registered by an addon that loads
    -- after the options panel still show up
    local soundItems = soundChoices()

    W(makeDropdown(p, "Default alert sound", soundItems,
        function() return NS.db.general.highlightSoundKey or NS.DEFAULT_ALERT_SOUND end,
        function(v)
            NS.db.general.highlightSoundKey = v
            NS.PlayAlertSound(v, NS.db.general.highlightSoundFile)
            pages.highlights.refresh()
        end), 24)

    -- only worth showing once something is actually set to "Custom file..."
    local customSound = W(makeEdit(p, "Custom sound file", 240,
        function() return NS.db.general.highlightSoundFile end,
        function(v)
            NS.db.general.highlightSoundFile = v:gsub("^%s+", ""):gsub("%s+$", "")
            if not NS.PlayAlertSound("custom", NS.db.general.highlightSoundFile) then
                NS.Print("that sound did not play - check the path, or pick another.")
            end
            pages.highlights.refresh()
        end), 24)

    local function customSoundWanted()
        if (NS.db.general.highlightSoundKey or "") == "custom" then return true end
        for _, hl in pairs(NS.db.highlights) do
            if type(hl) == "table" and hl.soundKey == "custom" then return true end
        end
        return false
    end

    add(label(p, "Each spell below can use this default or a sound of its own.\nPicking a sound plays it.", 11, NS.COLORS.dim), 30)

    local addEdit = makeEdit(p, "Add spell (exact name)", 200,
        function() return "" end,
        function(v)
            v = v:gsub("^%s+", ""):gsub("%s+$", "")
            if v ~= "" then
                NS.db.highlights[string.lower(v)] = { color = NS.COLORS.highlight }
                NS.ApplyAppearance()
                pages.highlights.refresh()
            end
        end)
    add(addEdit, 26)

    local listBase = CreateFrame("Frame", nil, p)
    listBase:SetSize(500, 460)
    add(listBase, 460)

    local rows = {}
    -- tolerant of a hand-edited or imported color that is not 6 hex digits
    local function hexToRGB(hex)
        if type(hex) ~= "string" or #hex < 6 then hex = NS.COLORS.highlight end
        local r = tonumber(hex:sub(1, 2), 16)
        local g = tonumber(hex:sub(3, 4), 16)
        local b = tonumber(hex:sub(5, 6), 16)
        if not (r and g and b) then return 1, 0.82, 0.30 end
        return r / 255, g / 255, b / 255
    end
    pages.highlights.refresh = function()
        local fresh = soundChoices()
        for i = #soundItems, 1, -1 do soundItems[i] = nil end
        for i, it in ipairs(fresh) do soundItems[i] = it end
        customSound:SetShown(customSoundWanted())

        for _, r in ipairs(rows) do r:Hide() end
        local names = {}
        for k, v in pairs(NS.db.highlights) do
            -- never let a bad key from an imported profile error the sort
            if type(k) == "string" and type(v) == "table" then
                names[#names + 1] = k
            end
        end
        table.sort(names)
        for i, name in ipairs(names) do
            if i > 18 then break end
            local r = rows[i]
            if not r then
                r = CreateFrame("Frame", nil, listBase, BackdropTemplateMixin and "BackdropTemplate" or nil)
                NS.SkinPanel(r, { r = 0, g = 0, b = 0, a = 0.35 })
                r:SetSize(500, 22)
                r:SetPoint("TOPLEFT", 0, -(i - 1) * 24)
                r.name = label(r, "", 11)
                r.name:SetPoint("LEFT", 8, 0)
                r.name:SetWidth(210)
                r.name:SetWordWrap(false)

                r.del = makeButton(r, "remove", 60, nil)
                r.del:SetPoint("RIGHT", -4, 0)

                r.colorBtn = makeColor(r, "",
                    function()
                        local hex = (r.hl and r.hl.color) or NS.COLORS.highlight
                        local cr, cg, cb = hexToRGB(hex)
                        return { r = cr, g = cg, b = cb, a = 1 }
                    end, nil)
                r.colorBtn:SetPoint("LEFT", r, "LEFT", 226, 0)
                r.colorBtn:SetScript("OnClick", function()
                    if not r.hl then return end
                    local cr, cg, cb = hexToRGB(r.hl.color or NS.COLORS.highlight)
                    NS.OpenColorPicker(cr, cg, cb, 1, function(nr, ng, nb)
                        r.hl.color = NS.RGBToHex(nr, ng, nb)
                        NS.ApplyAppearance()
                        pages.highlights.refresh()
                    end)
                end)

                -- per-spell sound: "default" follows the dropdown above
                r.soundBtn = makeButton(r, "", 156, function()
                    if not r.hl then return end
                    local items = { { text = "Sound for this spell", header = true } }
                    table.insert(items, {
                        text = "Use the default (" .. soundLabel(
                            NS.db.general.highlightSoundKey or NS.DEFAULT_ALERT_SOUND) .. ")",
                        checked = r.hl.soundKey == nil and r.hl.sound ~= false,
                        func = function()
                            -- clear the pre-1.5 boolean too, or a spell muted
                            -- under the old checkbox can never be un-muted
                            r.hl.soundKey, r.hl.soundFile, r.hl.sound = nil, nil, nil
                            pages.highlights.refresh()
                        end,
                    })
                    table.insert(items, { separator = true })
                    for _, it in ipairs(soundChoices()) do
                        table.insert(items, {
                            text = it.label,
                            checked = r.hl.soundKey == it.key,
                            func = function()
                                r.hl.soundKey, r.hl.sound = it.key, nil
                                if it.key == "custom" then
                                    r.hl.soundFile = NS.db.general.highlightSoundFile
                                end
                                NS.PlayAlertSound(it.key,
                                    r.hl.soundFile or NS.db.general.highlightSoundFile)
                                pages.highlights.refresh()
                            end,
                        })
                    end
                    NS.ShowMenu(items)
                end)
                r.soundBtn:SetPoint("RIGHT", r.del, "LEFT", -6, 0)
                attachTip(r.soundBtn, "Spell highlight sound")
                rows[i] = r
            end
            r.hl = NS.db.highlights[name]
            r.name:SetText(C(name, r.hl.color or NS.COLORS.highlight))
            r.colorBtn.Refresh()

            local muted = not NS.db.general.highlightSound
            local key = NS.HighlightSoundKey(r.hl)
            local txt
            if muted then
                txt = C("sounds off", NS.COLORS.dim)
            elseif r.hl.soundKey == nil then
                txt = C(soundLabel(key), NS.COLORS.dim)
            else
                txt = C(soundLabel(key), NS.COLORS.accent)
            end
            r.soundBtn.text:SetText(txt)

            r.del:SetScript("OnClick", function()
                NS.db.highlights[name] = nil
                NS.ApplyAppearance()
                pages.highlights.refresh()
            end)
            r:Show()
        end
        for _, w in ipairs(widgets) do if w.Refresh then w.Refresh() end end
        addEdit.Refresh()
    end
end

local function buildRecap()
    local p = newPage("recap", 460)
    local add, _recapH, relayout = stacker(p)
    local widgets = {}
    local function W(w, h) widgets[#widgets + 1] = w return add(w, h) end

    add(label(p, "Death Recap", 14, NS.COLORS.accent), 22)

    local recapChecks = {
        { "Record deaths",
            function() return NS.db.deathRecap.enabled end,
            function(v) NS.db.deathRecap.enabled = v pages.recap.refresh() end },
        { "Skip enemy deaths",
            function() return NS.db.deathRecap.friendlyOnly end,
            function(v) NS.db.deathRecap.friendlyOnly = v end },
        { "Record what a corpse dropped",
            function() return NS.db.deathRecap.trackLoot end,
            function(v) NS.db.deathRecap.trackLoot = v end },
    }
    local rcBase = CreateFrame("Frame", nil, p)
    rcBase:SetSize(500, 2 * 22)
    add(rcBase, 2 * 22)
    for i, def in ipairs(recapChecks) do
        local chk = makeCheck(rcBase, def[1], def[2], def[3])
        widgets[#widgets + 1] = chk
        chk:SetPoint("TOPLEFT", rcBase, "TOPLEFT",
            ((i - 1) % 2) * 250, -math.floor((i - 1) / 2) * 22)
    end

    -- one question instead of a checkbox, a slider and two lines of prose
    -- explaining which of them was actually in charge
    local spanDD = W(makeDropdown(p, "Timeline", NS.RECAP_SPANS,
        function()
            local dr = NS.db.deathRecap
            if dr.wholeFight then return "fight" end
            local secs = dr.seconds or 12
            if secs <= 20 then return "12" elseif secs <= 45 then return "30" end
            return "60"
        end,
        function(v)
            local dr = NS.db.deathRecap
            if v == "fight" then
                dr.wholeFight = true
                dr.seconds = dr.seconds or 12
            else
                dr.wholeFight = false
                dr.seconds = tonumber(v) or 12
            end
            pages.recap.refresh()
        end), 24)
    local secHint = add(label(p, "", 11, NS.COLORS.dim), 30)

    add(label(p, "History", 12, NS.COLORS.accent), 20)

    W(makeCheck(p, "Keep recaps between sessions",
        function() return NS.db.deathRecap.persist end,
        function(v)
            -- unticking used to delete the saved history on the spot, pinned
            -- recaps included, with nothing asking first. It now just stops
            -- writing; "Clear history..." below is the one that deletes.
            NS.db.deathRecap.persist = v
            pages.recap.refresh()
        end), 20)
    local keepSlider = W(makeSlider(p, "How many to keep", 5, 200, 5,
        function() return NS.db.deathRecap.keepHistory end,
        function(v) NS.db.deathRecap.keepHistory = v end, nil,
        -- trimming happens on release, so sliding down to read the label and
        -- back up again does not shred the history on the way past
        function()
            NS.TrimDeathHistory()
            pages.recap.refresh()
        end), 34)
    local histLabel = add(label(p, "", 11, NS.COLORS.dim), 30)
    local wipeBtn = add(makeButton(p, "Clear history...", 180, function()
        local total, kept = NS.DeathHistoryCounts()
        if kept == 0 then
            local n = NS.ClearDeathHistory()
            NS.Print("cleared " .. n .. " recap" .. (n == 1 and "" or "s") .. ".")
            pages.recap.refresh()
            return
        end
        -- saved recaps were pinned on purpose, so wiping them is its own choice
        NS.ShowMenu({
            { text = "Clear death recap history", header = true },
            { text = "Clear the " .. (total - kept) .. " unsaved ones", func = function()
                local n = NS.ClearDeathHistory()
                NS.Print("cleared " .. n .. " unsaved recap" .. (n == 1 and "" or "s") ..
                    ", kept " .. kept .. ".")
                pages.recap.refresh()
            end },
            { separator = true },
            { text = "Clear everything, including the " .. kept .. " saved", func = function()
                local n = NS.ClearDeathHistory(true)
                NS.Print("cleared all " .. n .. " recaps.")
                pages.recap.refresh()
            end },
        })
    end), 26)

    local browseBtn = add(makeButton(p, "Open death recap browser", 200, NS.ToggleDeaths), 26)
    attachTip(browseBtn, "Open death recap browser")
    add(label(p, "Deaths also appear in log windows as clickable [recap] links. Looted kills\nrecord their drops; right-click any recap to save and name it.", 11, NS.COLORS.dim), 30)

    pages.recap.refresh = function()
        for _, w in ipairs(widgets) do if w.Refresh then w.Refresh() end end
        if NS.db.deathRecap.wholeFight then
            secHint:SetText(C("A death in combat is shown from the start of the pull." ..
                "\nOut of combat there is no fight to measure, so the last " ..
                (NS.db.deathRecap.seconds or 12) .. " seconds are kept.",
                NS.COLORS.dim))
        else
            secHint:SetText(C("Every timeline reaches back exactly this far.", NS.COLORS.dim))
        end
        local on = NS.db.deathRecap.persist and true or false
        keepSlider:SetShown(on)
        histLabel:SetShown(on)
        wipeBtn:SetShown(on)
        if on then
            local total, kept = NS.DeathHistoryCounts()
            local limit = NS.db.deathRecap.keepHistory or 40
            local txt = total .. " of " .. limit .. " kept right now."
            if kept >= limit then
                txt = txt .. "\n" .. kept .. C(" saved", NS.COLORS.accent) ..
                    C(" - that is your whole limit, so nothing new is being kept." ..
                      " Raise the limit or unsave a few.", NS.COLORS.death)
            elseif kept > 0 then
                txt = txt .. "\n" .. kept .. C(" saved", NS.COLORS.accent) ..
                    C(", so " .. (limit - kept) ..
                      " slots are left for new deaths to roll through.", NS.COLORS.dim)
            else
                txt = txt .. "\nOlder ones drop off as new deaths come in. Right-click any" ..
                    " recap in the browser to save it from that."
            end
            histLabel:SetText(C(txt, NS.COLORS.dim))
        end
        relayout()
    end
end

local function buildAbout()
    local p = newPage("about", 640)
    local add = stacker(p)

    local icon = p:CreateTexture(nil, "ARTWORK")
    icon:SetSize(64, 64)
    icon:SetPoint("TOPLEFT", 14, -6)
    icon:SetTexture("Interface\\AddOns\\LogLovers\\Icon.tga")

    local head = p:CreateFontString(nil, "OVERLAY")
    head:SetFont(NS.CurrentFont(), 17, "")
    head:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -6)
    head:SetText(C("Log ", NS.COLORS.accent) .. C("Lovers", NS.COLORS.text))

    local sub = p:CreateFontString(nil, "OVERLAY")
    sub:SetFont(NS.CurrentFont(), 11, "")
    sub:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -28)
    sub:SetJustifyH("LEFT")
    sub:SetText(C("Version " .. NS.VERSION .. "  |  TBC Anniversary  |  MIT licence", NS.COLORS.dim))

    local spacer = CreateFrame("Frame", nil, p)
    spacer:SetSize(10, 62)
    add(spacer, 62, nil, 0)

    local function section(title, lines)
        add(label(p, title, 12, NS.COLORS.accent), 18)
        add(label(p, lines, 11), select(2, lines:gsub("\n", "")) * 14 + 16)
    end

    section("Combat log", table.concat({
        "Hover a spell for its tooltip; click it for stats, filters or its own window.",
        "Click a name to focus, inspect, or open that unit's death recap.",
        "Unlimited windows, each with its own filters; live search in every one.",
        "Shows you and your pet by default; pick either direction or unfiltered.",
        "Blacklist annoying zone buffs - right-click one, or pick from your auras.",
    }, "\n"))

    section("Chat", table.concat({
        "Full Blizzard chat replacement with draggable, dockable tabs.",
        "Per-tab message types and per-channel picking; join/leave channels in-app.",
        "Whisper pop-outs with their own reply box; click names to whisper.",
        "Shift-click a name for their /who details, history with you and notes.",
        "Alert words light up and ping; blocked words never arrive at all.",
        "Custom colors per message type and per channel; history survives reloads.",
    }, "\n"))

    section("Analysis", table.concat({
        "Death recaps: the final seconds before any death, hit by hit.",
        "Recaps survive logout, and record what each corpse dropped when looted.",
        "Save and name the fights worth keeping; saved ones are never rolled off.",
        "Stats browser: damage, healing and damage taken per fight, per spell.",
        "Spell highlights with a per-spell alert colour and alert sound.",
        "Text export, full event capture, and shareable one-string profiles.",
    }, "\n"))

    section("Handy commands", table.concat({
        "/ll            open these options",
        "/ll me         only my events, on every combat view",
        "/ll aoe        AoE farming mode - kills only",
        "/ll stats      /ll deaths      /ll chat      /ll help",
    }, "\n"))

    add(label(p, "Built for Jabe's hunter, sharpened in raids and arenas.", 11, NS.COLORS.dim), 20)
end

-------------------------------------------------------------------------------
-- Shell
-------------------------------------------------------------------------------
local function ensurePanel()
    if panel then return end
    panel = CreateFrame("Frame", "LogLoversOptions", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    panel:SetSize(740, 540)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- the panel remembered the size you dragged it to but not where you
        -- put it, so it re-centred every session
        local point, _, _, x, y = self:GetPoint()
        if point then
            NS.db.optionsPos = { point, math.floor(x + 0.5), math.floor(y + 0.5) }
        end
    end)
    panel:SetClampedToScreen(true)
    NS.SkinPanel(panel, { r = 0.045, g = 0.035, b = 0.022, a = 0.97 })
    tinsert(UISpecialFrames, "LogLoversOptions")

    -- restore the size and place the user left it in
    local saved = NS.db.optionsSize
    if saved and saved.w and saved.h then
        panel:SetSize(math.max(620, saved.w), math.max(420, saved.h))
    end
    local pos = NS.db.optionsPos
    if type(pos) == "table" and pos[1] then
        panel:ClearAllPoints()
        panel:SetPoint(pos[1], UIParent, pos[1], pos[2] or 0, pos[3] or 0)
    end

    panel:SetResizable(true)
    NS.SetResizeLimits(panel, 620, 420, 1500, 1100)
    local grip = CreateFrame("Button", nil, panel)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() panel:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        panel:StopMovingOrSizing()
        NS.db.optionsSize = {
            w = math.floor(panel:GetWidth() + 0.5),
            h = math.floor(panel:GetHeight() + 0.5),
        }
    end)
    panel:SetScript("OnSizeChanged", function(self)
        for _, page in pairs(pages) do
            if page.scroll and page.frame then
                page.frame:SetWidth(math.max(480, page.scroll:GetWidth() - 6))
            end
        end
    end)

    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(38, 38)
    icon:SetPoint("TOPLEFT", 12, -8)
    icon:SetTexture("Interface\\AddOns\\LogLovers\\Icon.tga")

    local title = panel:CreateFontString(nil, "OVERLAY")
    title:SetFont(NS.CurrentFont(), 16, "")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    title:SetText(C("Log ", NS.COLORS.accent) .. C("Lovers", NS.COLORS.text))

    local subtitle = panel:CreateFontString(nil, "OVERLAY")
    subtitle:SetFont(NS.CurrentFont(), 10, "")
    subtitle:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -20)
    subtitle:SetText(C("v" .. NS.VERSION .. "  -  combat log & chat", NS.COLORS.dim))

    local close = NS.MakeIconButton(panel, "Interface\\Buttons\\UI-StopButton", nil,
        function() panel:Hide() end)
    close:SetPoint("TOPRIGHT", -10, -10)

    -- nav
    local nav = CreateFrame("Frame", nil, panel, BackdropTemplateMixin and "BackdropTemplate" or nil)
    NS.SkinPanel(nav, { r = 0, g = 0, b = 0, a = 0.35 })
    nav:SetPoint("TOPLEFT", 10, -50)
    nav:SetPoint("BOTTOMLEFT", 10, 10)
    nav:SetWidth(140)

    panel.navButtons = {}
    for i, item in ipairs(NAV) do
        local b = CreateFrame("Button", nil, nav)
        b:SetHeight(24)
        b:SetPoint("TOPLEFT", 2, -6 - (i - 1) * 26)
        b:SetPoint("TOPRIGHT", -2, -6 - (i - 1) * 26)
        b.key, b.label = item.key, item.label
        b.text = b:CreateFontString(nil, "OVERLAY")
        b.text:SetFont(NS.CurrentFont(), 12, "")
        b.text:SetPoint("LEFT", 10, 0)
        b.text:SetText(C(item.label, NS.COLORS.dim))
        b.bar = b:CreateTexture(nil, "ARTWORK")
        b.bar:SetColorTexture(NS.ACCENT.r, NS.ACCENT.g, NS.ACCENT.b, 0.9)
        b.bar:SetSize(3, 16)
        b.bar:SetPoint("LEFT", 1, 0)
        b.bar:Hide()
        b.hl = b:CreateTexture(nil, "HIGHLIGHT")
        b.hl:SetAllPoints()
        b.hl:SetColorTexture(NS.ACCENT.r, NS.ACCENT.g, NS.ACCENT.b, 0.08)
        b:SetScript("OnClick", function() selectPage(item.key) end)
        panel.navButtons[#panel.navButtons + 1] = b
    end

    buildGeneral()
    buildAppearance()
    buildViews()
    buildChannels()
    buildHighlights()
    buildRecap()
    buildAbout()

    selectPage("general")
end

function NS.ToggleOptions()
    ensurePanel()
    if panel:IsShown() then panel:Hide() else
        selectPage(currentPage or "general")
        panel:Show()
    end
end

function NS.OpenOptionsForWindow(index)
    ensurePanel()
    panel:Show()
    selectPage("views")
    if pages.views and pages.views.selectWindow then
        pages.views.selectWindow(index)
    end
end

function NS.RegisterBlizzOptions()
    if NS.blizzOptionsRegistered then return end
    NS.blizzOptionsRegistered = true
    local panel = CreateFrame("Frame")
    panel.name = "Log Lovers"
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("|cff33ff99Log|r Lovers")
    local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", 16, -40)
    sub:SetJustifyH("LEFT")
    sub:SetText("Advanced combat log and chat replacement.\nAll configuration lives in Log Lovers' own options window.")
    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetSize(200, 24)
    btn:SetPoint("TOPLEFT", 16, -80)
    btn:SetText("Open Log Lovers options")
    btn:SetScript("OnClick", function()
        NS.ToggleOptions()
    end)
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 16, -114)
    hint:SetText("Or type /ll")
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        category.ID = "LogLovers"
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

-- Repaint a page if it is built and on screen. Used by code outside the
-- options (slash commands, log right-click menus) that changes something the
-- panel is displaying.
function NS.RefreshOptionsPage(key)
    local pg = pages[key]
    if not pg or not pg.refresh or not pg.scroll then return end
    if pg.scroll:IsShown() then pcall(pg.refresh) end
end

-- Height the page's laid-out content currently occupies. Used by the test
-- harness to prove hidden sections are not reserving empty space.
function NS.OptionsContentHeight(key)
    local pg = pages[key]
    if pg and pg.frame then return rawget(pg.frame, "llContentHeight") end
end

-- What the window picker would list right now, for the test harness: the
-- phantom "popped out" entries were only visible by opening the menu.
function NS.OptionsWindowChoices()
    return (pages.views and pages.views.entries and pages.views.entries()) or {}
end

-- Every page key the nav offers, so a dangling entry cannot ship unnoticed.
function NS.OptionsPageKeys()
    local out = {}
    for _, n in ipairs(NAV) do out[#out + 1] = n.key end
    return out
end

function NS.OptionsPageExists(key)
    return pages[key] ~= nil and pages[key].frame ~= nil
end

function NS.OpenOptionsPage(key, chatViewIndex)
    ensurePanel()
    if key == "chat" or key == "windows" then key = "views" end
    -- Capture & Export folded into General in 1.10; old links still work
    if key == "capture" or key == "export" or key == "profiles" then key = "general" end
    if not NS.OptionsPageExists(key) then key = "general" end
    panel:Show()
    selectPage(key)
    if chatViewIndex and pages.views and pages.views.selectChatView then
        pages.views.selectChatView(chatViewIndex)
    end
end
