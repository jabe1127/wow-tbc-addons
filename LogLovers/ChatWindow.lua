-- LogLovers ChatWindow: tabbed main chat window, breakout chat windows, edit box dock
local ADDON, NS = ...

local C = NS.C
local CHAT = nil -- set on init (NS.CHAT)

local main            -- { frame, smf, titleBar, tabsRow, tabButtons, searchBox, searchShown, searchText, ebHolder }
local breakouts = {}  -- [viewIndex] = { frame, smf, view }

local function db() return NS.db.chat end
local function views() return NS.db.chat.views end
local function activeView() return views()[db().activeView] or views()[1] end

-- forward declarations (defined below)
local rebuildBreakouts, startTabDrag, stopTabDrag, layoutMain

-------------------------------------------------------------------------------
-- Rendering
-------------------------------------------------------------------------------
local function renderViewInto(smf, v, searchText)
    -- Clear() drops the scroll position. A repeated spam line re-renders the
    -- window, so without this you get yanked to the bottom every time someone
    -- pastes their macro while you are reading back.
    local wasAtBottom = true
    local offset = 0
    if smf.AtBottom then wasAtBottom = smf:AtBottom() and true or false end
    if not wasAtBottom and smf.GetCurrentScroll then
        local ok, val = pcall(smf.GetCurrentScroll, smf)
        if ok then offset = val or 0 end
    end

    smf:Clear()
    if v.kind == "combat" then
        NS.BufferEach(function(rec)
            if NS.RecordPasses(rec, v.combatFilter) then
                NS.FormatRecord(rec)
                if NS.RecordMatchesSearch(rec, searchText) then
                    smf:AddMessage(rec.line)
                end
            end
        end)
    else
        CHAT.Each(function(w)
            if CHAT.Passes(w.d, v.filter) and CHAT.MatchesSearch(w, searchText) then
                smf:AddMessage(CHAT.FormatWrapper(w))
            end
        end)
    end

    if not wasAtBottom and offset > 0 and smf.SetScrollOffset then
        pcall(smf.SetScrollOffset, smf, offset)
    end
    if smf.llUpdateJump then smf.llUpdateJump() end
end

local function refreshMain()
    if not main then return end
    local v = activeView()
    if not v or v.mode == "window" then
        main.smf:Clear()   -- every view is broken out; nothing to show here
        return
    end
    -- renderViewInto does its own Clear. Doing it here first meant it sampled
    -- the scroll position of an already-empty frame, so it always read "at the
    -- bottom" - which is why reading back in the main window got yanked down
    -- every time somebody repeated a line.
    renderViewInto(main.smf, v, main.searchText)
end

local function refreshBreakout(b)
    renderViewInto(b.smf, b.view, nil)
end

-- Tabs live IN the title bar and wrap onto extra rows when they don't fit.
local function updateTabs()
    if not main then return end
    local ap = NS.db.appearance
    local rowH = ap.titleHeight or 19
    local tabH = math.max(14, rowH - 2)
    local fontSize = ap.titleFontSize or 11
    local tb = main.titleBar
    local totalW = main.frame:GetWidth() or 460
    local reservedRight = 86   -- title buttons occupy the right of row 1
    local x, row = 6, 0

    local function place(btn, w)
        local limit = totalW - 6 - (row == 0 and reservedRight or 4)
        if x + w > limit and x > 6 then
            row = row + 1
            x = 6
        end
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", tb, "TOPLEFT", x, -(row * rowH + (rowH - tabH) / 2))
        x = x + w + 2
    end

    for _, btn in ipairs(main.tabButtons) do btn:Hide() end
    local shown = 0
    for i, v in ipairs(views()) do
        if v.mode ~= "window" then
            shown = shown + 1
            local btn = main.tabButtons[shown]
            if not btn then
                btn = CreateFrame("Button", nil, tb)
                btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                btn:RegisterForDrag("LeftButton")
                btn:SetScript("OnDragStart", function(self)
                    if startTabDrag then startTabDrag(self.viewIndex) end
                end)
                btn:SetScript("OnDragStop", function(self)
                    if stopTabDrag then stopTabDrag(self.viewIndex) end
                end)
                btn.text = btn:CreateFontString(nil, "OVERLAY")
                btn.text:SetPoint("CENTER", 0, 0)
                btn.underline = btn:CreateTexture(nil, "ARTWORK")
                btn.underline:SetColorTexture(NS.ACCENT.r, NS.ACCENT.g, NS.ACCENT.b, 0.95)
                btn.underline:SetHeight(2)
                btn.underline:SetPoint("BOTTOMLEFT", 2, 0)
                btn.underline:SetPoint("BOTTOMRIGHT", -2, 0)
                btn.hl = btn:CreateTexture(nil, "HIGHLIGHT")
                btn.hl:SetAllPoints()
                btn.hl:SetColorTexture(NS.ACCENT.r, NS.ACCENT.g, NS.ACCENT.b, 0.09)
                main.tabButtons[shown] = btn
            end
            btn.viewIndex = i
            btn:SetHeight(tabH)
            btn.text:SetFont(NS.CurrentFont(), fontSize, "")
            local name = v.name
            local isActive = i == db().activeView
            if isActive then v.alert = nil end
            if (v.unread or 0) > 0 and not isActive then
                -- a tab holding an alert word shouts louder than a plain unread
                local nameHex = v.alert and (db().alerts.color or NS.COLORS.highlight)
                    or NS.COLORS.text
                btn.text:SetText((v.alert and C("! ", nameHex) or "") ..
                    C(name, nameHex) .. C(" (" .. v.unread .. ")", NS.COLORS.accent))
            else
                btn.text:SetText(C(name, isActive and NS.COLORS.accent or NS.COLORS.dim))
            end
            btn.underline:SetShown(isActive)
            local w = (btn.text:GetStringWidth() or 40) + 14
            btn:SetWidth(w)
            place(btn, w)
            btn:SetScript("OnClick", function(self, mouse)
                if mouse == "RightButton" then
                    NS.ShowChatTabMenu(self.viewIndex)
                else
                    db().activeView = self.viewIndex
                    local vv = views()[self.viewIndex]
                    if vv then vv.unread, vv.alert = 0, nil end
                    updateTabs()
                    refreshMain()
                end
            end)
            btn:Show()
        end
    end

    -- "+" button flows with the tabs
    local plus = main.plusButton
    if not plus then
        plus = CreateFrame("Button", nil, tb)
        plus.text = plus:CreateFontString(nil, "OVERLAY")
        plus.text:SetPoint("CENTER")
        plus.hl = plus:CreateTexture(nil, "HIGHLIGHT")
        plus.hl:SetAllPoints()
        plus.hl:SetColorTexture(NS.ACCENT.r, NS.ACCENT.g, NS.ACCENT.b, 0.10)
        plus:SetScript("OnClick", function() NS.ShowNewChatViewMenu() end)
        main.plusButton = plus
    end
    plus:SetSize(tabH, tabH)
    plus.text:SetFont(NS.CurrentFont(), fontSize + 1, "")
    plus.text:SetText(C("+", NS.COLORS.accent))
    place(plus, tabH)

    -- title bar grows with the number of tab rows
    local rows = row + 1
    tb:SetHeight(rows * rowH + 1)
    if main.titleButtons then
        local yOff = -(rowH - 14) / 2 - 1
        main.titleButtons[1]:ClearAllPoints()
        main.titleButtons[1]:SetPoint("TOPRIGHT", tb, "TOPRIGHT", -4, yOff)
    end
    if main.lastTabRows ~= rows or main.lastRowH ~= rowH then
        main.lastTabRows = rows
        main.lastRowH = rowH
        if layoutMain then layoutMain() end
    end
end

-------------------------------------------------------------------------------
-- Tab drag & drop: reorder along the strip, or pull out into a window
-------------------------------------------------------------------------------
local dragGhost, dragView

local function ensureGhost()
    if dragGhost then return end
    dragGhost = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    NS.SkinPanel(dragGhost, { r = 0.14, g = 0.10, b = 0.04, a = 0.95 },
        { r = 1.0, g = 0.76, b = 0.28, a = 0.9 })
    dragGhost:SetFrameStrata("FULLSCREEN_DIALOG")
    dragGhost:SetSize(80, 20)
    dragGhost:EnableMouse(false)
    dragGhost.text = dragGhost:CreateFontString(nil, "OVERLAY")
    dragGhost.text:SetFont(NS.CurrentFont(), 11, "")
    dragGhost.text:SetPoint("CENTER")
    dragGhost:SetScript("OnUpdate", function(self)
        local scale = UIParent:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / scale, cy / scale + 14)
    end)
    dragGhost:Hide()
end

startTabDrag = function(viewIndex)
    if db().locked then return end
    local v = views()[viewIndex]
    if not v then return end
    dragView = v
    ensureGhost()
    dragGhost.text:SetText(C(v.name, NS.COLORS.accent))
    dragGhost:SetWidth(dragGhost.text:GetStringWidth() + 18)
    dragGhost:Show()
end

stopTabDrag = function()
    if not dragView then return end
    local v = dragView
    dragView = nil
    if dragGhost then dragGhost:Hide() end

    local vlist = views()
    local fromIdx
    for i, vv in ipairs(vlist) do
        if vv == v then fromIdx = i break end
    end
    if not fromIdx then return end

    local scale = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale

    if main.tabsRow:IsMouseOver(15, -15, -15, 15) then
        -- reorder: find the first visible tab whose center is right of the cursor
        local targetIdx = nil
        for _, btn in ipairs(main.tabButtons) do
            if btn:IsShown() and btn:GetLeft() then
                local mid = (btn:GetLeft() + btn:GetRight()) / 2
                if cx < mid then
                    targetIdx = btn.viewIndex
                    break
                end
            end
        end
        local activeRef = vlist[db().activeView]
        table.remove(vlist, fromIdx)
        local insertAt
        if targetIdx == nil then
            insertAt = #vlist + 1                    -- dropped past the last tab
        elseif targetIdx > fromIdx then
            insertAt = targetIdx - 1
        else
            insertAt = targetIdx
        end
        if insertAt < 1 then insertAt = 1 end
        if insertAt > #vlist + 1 then insertAt = #vlist + 1 end
        table.insert(vlist, insertAt, v)
        for i, vv in ipairs(vlist) do
            if vv == activeRef then db().activeView = i break end
        end
        updateTabs()
        refreshMain()
        rebuildBreakouts()
    elseif not main.frame:IsMouseOver() then
        -- pulled out of the chat window entirely: break out at the cursor
        if v.kind == "combat" then
            NS.BreakOutChatView(fromIdx)
            local idx = #NS.db.windows
            local win = NS.windows[idx]
            if win then
                win.cfg.point = { "BOTTOMLEFT",
                    math.max(0, math.floor(cx - (win.cfg.width or 520) / 2)),
                    math.max(0, math.floor(cy - (win.cfg.height or 220) / 2)) }
                win.frame:ClearAllPoints()
                win.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
                    win.cfg.point[2], win.cfg.point[3])
            end
        else
            v.mode = "window"
            v.point = { "BOTTOMLEFT",
                math.max(0, math.floor(cx - (v.width or 340) / 2)),
                math.max(0, math.floor(cy - (v.height or 180) / 2)) }
            if vlist[db().activeView] == v then
                for i, vv in ipairs(vlist) do
                    if vv.mode ~= "window" then db().activeView = i break end
                end
            end
            updateTabs()
            refreshMain()
            rebuildBreakouts()
        end
    end
    -- dropped inside the window body but not on the strip: treated as a cancel
end

-------------------------------------------------------------------------------
-- Dispatch from Chat.lua
-------------------------------------------------------------------------------
function NS.DispatchChat(w)
    if main and main.frame:IsShown() then
        local act = db().activeView
        local tabsDirty = false
        for i, v in ipairs(views()) do
            if v.mode ~= "window" and v.kind ~= "combat" and CHAT.Passes(w.d, v.filter) then
                if i == act then
                    if CHAT.MatchesSearch(w, main.searchText) then
                        main.smf:AddMessage(CHAT.FormatWrapper(w))
                        if main.smf.llUpdateJump then main.smf.llUpdateJump() end
                    end
                else
                    v.unread = (v.unread or 0) + 1
                    if w.d.alert and db().alerts.flashTabs then v.alert = true end
                    tabsDirty = true
                end
            end
        end
        if tabsDirty then updateTabs() end
    end
    for _, b in pairs(breakouts) do
        if b.frame:IsShown() and b.view.kind ~= "combat"
            and CHAT.Passes(w.d, b.view.filter) then
            b.smf:AddMessage(CHAT.FormatWrapper(w))
            if b.smf.llUpdateJump then b.smf.llUpdateJump() end
        end
    end
end

-- combat records feeding docked combat-log tabs (no unread counting; too spammy)
function NS.DispatchCombatToChat(rec)
    if main and main.frame:IsShown() then
        local v = activeView()
        if v and v.mode ~= "window" and v.kind == "combat"
            and NS.RecordPasses(rec, v.combatFilter) then
            NS.FormatRecord(rec)
            if NS.RecordMatchesSearch(rec, main.searchText) then
                main.smf:AddMessage(rec.line)
            end
        end
    end
    for _, b in pairs(breakouts) do
        if b.frame:IsShown() and b.view.kind == "combat"
            and NS.RecordPasses(rec, b.view.combatFilter) then
            NS.FormatRecord(rec)
            b.smf:AddMessage(rec.line)
        end
    end
end

-------------------------------------------------------------------------------
-- Shared SMF construction
-------------------------------------------------------------------------------
local function makeChatSMF(parent, getView)
    local smf = CreateFrame("ScrollingMessageFrame", nil, parent)
    smf:SetJustifyH("LEFT")
    smf:SetFading(false)
    smf:SetMaxLines(1000)
    smf:SetInsertMode(SCROLLING_MESSAGE_FRAME_INSERT_MODE_BOTTOM or "BOTTOM")
    if smf.SetIndentedWordWrap then smf:SetIndentedWordWrap(true) end
    smf:SetHyperlinksEnabled(true)
    smf:EnableMouse(true)
    smf:EnableMouseWheel(true)
    smf:SetScript("OnMouseWheel", function(self, delta)
        -- touching the wheel means you are reading: un-fade what is there
        if self.ResetAllFadeTimes then self:ResetAllFadeTimes() end
        if IsControlKeyDown() then
            if delta > 0 then self:ScrollToTop() else self:ScrollToBottom() end
        elseif IsShiftKeyDown() then
            if delta > 0 then self:PageUp() else self:PageDown() end
        else
            for _ = 1, math.max(db().scrollLines or 3, 1) do
                if delta > 0 then self:ScrollUp() else self:ScrollDown() end
            end
        end
        if self.llUpdateJump then self.llUpdateJump() end
    end)
    smf:SetScript("OnHyperlinkClick", function(self, link, text, button)
        local v = getView and getView()
        if v and v.kind == "combat"
            and not link:find("^llp") and not link:find("^llurl") then
            -- combat-log links get the full combat menus, acting on this tab's filter
            local pseudoWin = {
                cfg = { filter = v.combatFilter },
                smf = self,
                searchText = (main and self == main.smf) and main.searchText or nil,
            }
            NS.HandleLinkClick(pseudoWin, link, text, button)
        else
            CHAT.HandleLinkClick(link, text, button)
        end
    end)
    smf:SetScript("OnHyperlinkEnter", function(self, link)
        if not CHAT.HandleLinkEnter(self, link) then
            NS.HandleLinkEnter(self, link)
        end
    end)
    smf:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)

    -- "jump to bottom": only visible when you have actually scrolled away, so
    -- you can read back without losing your place in the live feed
    local jump = CreateFrame("Button", nil, parent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    NS.SkinPanel(jump, { r = 0.16, g = 0.11, b = 0.05, a = 0.92 },
        { r = 0.52, g = 0.37, b = 0.14, a = 0.95 })
    jump:SetSize(112, 16)
    jump:SetPoint("BOTTOMRIGHT", smf, "BOTTOMRIGHT", -4, 4)
    jump:SetFrameLevel(smf:GetFrameLevel() + 5)
    jump.text = jump:CreateFontString(nil, "OVERLAY")
    jump.text:SetPoint("CENTER")
    jump.hl = jump:CreateTexture(nil, "HIGHLIGHT")
    jump.hl:SetAllPoints()
    jump.hl:SetColorTexture(NS.ACCENT.r, NS.ACCENT.g, NS.ACCENT.b, 0.12)
    jump:SetScript("OnClick", function()
        smf:ScrollToBottom()
        if smf.llUpdateJump then smf.llUpdateJump() end
    end)
    jump:Hide()
    smf.llJump = jump
    smf.llUpdateJump = function()
        jump.text:SetFont(NS.CurrentFont(), 10, "")
        jump.text:SetText(C("v  jump to bottom", NS.COLORS.accent))
        local atBottom = true
        if smf.AtBottom then atBottom = smf:AtBottom() end
        jump:SetShown(not atBottom)
    end

    return smf
end

local function styleChatSMF(smf, fontSize)
    local ap = NS.db.appearance
    local d = db()
    smf:SetFont(NS.CurrentFont(), fontSize or ap.fontSize, ap.outline)
    smf:SetSpacing(ap.lineSpacing)
    smf:SetShadowColor(0, 0, 0, 0.9)
    smf:SetShadowOffset(1, -1)
    -- fade the window away when chat goes quiet; scrolling brings it back
    smf:SetFading(d.fade and true or false)
    if d.fade then smf:SetTimeVisible(math.max(d.fadeTime or 120, 5)) end
    if smf.llUpdateJump then smf.llUpdateJump() end
end

-------------------------------------------------------------------------------
-- Edit box (Blizzard's, reskinned and docked)
-------------------------------------------------------------------------------
-- The typing box header.
--
-- Blizzard writes "To Playername:" in whisper pink and pads the box to match.
-- You just clicked that name, so the word "To" and the colon are noise; what
-- you want is a quiet reminder of where the next line is going. This rewrites
-- the header in place - Blizzard still owns the box, the chat type and the
-- padding maths, so /r, sticky channels and tab-completion are untouched.
local function styleEditHeader()
    local eb, header = _G.ChatFrame1EditBox, _G.ChatFrame1EditBoxHeader
    if not eb or not header or not NS.db or not NS.db.chat then return end
    local mode = NS.db.chat.whisperHeader or "compact"

    local ctype = eb.GetAttribute and eb:GetAttribute("chatType")
    local isWhisper = (ctype == "WHISPER" or ctype == "BN_WHISPER")

    if mode == "blizzard" or not isWhisper then
        -- Blizzard has already written the header by the time this runs, so
        -- there is nothing to restore except the two things we pin: an
        -- explicit width and our colour. Undo those once, then stay out of it.
        if eb.llHeaderTouched then
            eb.llHeaderTouched = nil
            header:SetWidth(0)
            local info = ChatTypeInfo and ctype and ChatTypeInfo[ctype]
            if info then header:SetTextColor(info.r, info.g, info.b) end
            eb:SetTextInsets(15 + (header:GetStringWidth() or 0), 13, 0, 0)
        end
        return
    end

    local target = (eb.GetAttribute and eb:GetAttribute("tellTarget")) or ""
    local short = target:match("^([^%-]+)") or target
    -- Blizzard's overflow ellipsis belongs to its own header text; ours is
    -- short by construction, so it would just dangle
    local suffix = _G.ChatFrame1EditBoxHeaderSuffix
    if suffix then suffix:SetText("") end
    eb.llHeaderTouched = true

    if mode == "off" or short == "" then
        header:SetText("")
        header:SetWidth(0)
        eb:SetTextInsets(8, 13, 0, 0)
        return
    end

    header:SetText(short .. " \194\187 ")
    header:SetWidth(header:GetStringWidth() or 0)
    local a = NS.ACCENT
    if a then header:SetTextColor(a.r, a.g, a.b) end
    -- same shape Blizzard uses, so the caret never sits under the header
    eb:SetTextInsets(15 + (header:GetWidth() or 0), 13, 0, 0)
end
NS.StyleEditHeader = styleEditHeader

-- With the chat window hidden there is nowhere to dock the typing box, and
-- Blizzard's own chat frame is hidden too - so it floats above the action bars
-- instead. Without this, hiding the window left no way to type at all.
local function floatEditBox()
    local eb = _G.ChatFrame1EditBox
    if not eb then return end
    eb:SetParent(UIParent)
    eb:ClearAllPoints()
    eb:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 20)
    eb:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOM", 200, 20)
    eb:SetHeight(22)
end
NS.FloatEditBox = floatEditBox

local function setupEditBox()
    local eb = _G.ChatFrame1EditBox
    if not eb or not main then return end

    -- strip Blizzard art
    local regions = { "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }
    for _, suffix in ipairs(regions) do
        local tex = _G["ChatFrame1EditBox" .. suffix]
        if tex then tex:SetAlpha(0) end
    end

    -- dock into our holder (reparent so it can show while ChatFrame1 is hidden)
    eb:SetParent(main.ebHolder)
    eb:ClearAllPoints()
    eb:SetPoint("TOPLEFT", main.ebHolder, "TOPLEFT", 2, -2)
    eb:SetPoint("BOTTOMRIGHT", main.ebHolder, "BOTTOMRIGHT", -2, 2)
    eb:SetAltArrowKeyMode(false)
    local ap = NS.db.appearance
    eb:SetFont(NS.CurrentFont(), (db().fontSize or ap.fontSize), "")
    local header = _G.ChatFrame1EditBoxHeader
    if header then header:SetFont(NS.CurrentFont(), (db().fontSize or ap.fontSize), "") end

    -- Blizzard rewrites the header every time the chat type changes; re-apply
    -- ours straight after it, once.
    if not eb.llHeaderHooked and hooksecurefunc and _G.ChatEdit_UpdateHeader then
        eb.llHeaderHooked = true
        hooksecurefunc("ChatEdit_UpdateHeader", styleEditHeader)
    end
    styleEditHeader()

    -- Blizzard hides its edit box whenever chat is deactivated (Escape, or
    -- after sending). That is right for the stock UI, where the box floats over
    -- the chat frame - but ours is docked into a permanent slot, so it has to
    -- stay put or the slot goes blank.
    if not eb.llKeptShown and hooksecurefunc then
        eb.llKeptShown = true
        hooksecurefunc("ChatEdit_DeactivateChat", function(box)
            if box == eb and main and main.frame:IsShown() and NS.db.chat.enabled then
                box:Show()
            end
        end)
    end
    -- Blizzard's box starts hidden and only appears when you press Enter. The
    -- hook above keeps it visible once shown; this is what shows it the first
    -- time, so the dock is not an empty slot after every login.
    if main.frame:IsShown() and NS.db.chat.enabled then eb:Show() end
end

-- Start a whisper the way the stock UI does: activate the real edit box, let
-- Blizzard parse "/w Name " into whisper mode so the header reads "To Name",
-- and leave the cursor ready. ChatFrame_OpenChat alone is not enough here,
-- because ChatFrame1 is hidden while our window is up.
function NS.StartWhisper(name)
    if not name or name == "" then return false end
    -- ChatEdit_ParseText matches the client's own slash commands, which are
    -- localised; "/w" is not registered on every locale
    local slash = (_G.SLASH_WHISPER1 or "/w") .. " " .. name .. " "
    local eb = _G.ChatFrame1EditBox
    if eb then
        if ChatEdit_ActivateChat then pcall(ChatEdit_ActivateChat, eb) end
        eb:Show()
        -- if the chat module failed to init, the box may be parented to a
        -- hidden frame; typing into something invisible is worse than the
        -- stock path, so fall through
        if eb:IsVisible() then
            eb:SetText(slash)
            if ChatEdit_ParseText then pcall(ChatEdit_ParseText, eb, 0) end
            eb:SetFocus()
            if eb.SetCursorPosition and eb.GetNumLetters then
                pcall(eb.SetCursorPosition, eb, eb:GetNumLetters())
            end
            return true
        end
    end
    if ChatFrame_OpenChat then
        ChatFrame_OpenChat(slash, DEFAULT_CHAT_FRAME)
        return true
    end
    return false
end

-------------------------------------------------------------------------------
-- Layout
-------------------------------------------------------------------------------
layoutMain = function()
    local f = main.frame
    local topInset = (main.titleBar and main.titleBar:GetHeight() or 20) + 2
    local alertH = (main.alertBar and main.alertBar:IsShown()) and 20 or 0
    local ebH = 22
    local searchH = main.searchShown and 20 or 0

    if main.alertBar and alertH > 0 then
        main.alertBar:ClearAllPoints()
        main.alertBar:SetPoint("TOPLEFT", 1, -topInset)
        main.alertBar:SetPoint("TOPRIGHT", -1, -topInset)
        main.alertBar:SetHeight(18)
    end

    local afterTabs = topInset + alertH

    main.searchBox:SetShown(main.searchShown)
    if main.searchShown then
        main.searchBox:ClearAllPoints()
        main.searchBox:SetPoint("TOPLEFT", 6, -(afterTabs + 2))
        main.searchBox:SetPoint("TOPRIGHT", -6, -(afterTabs + 2))
        main.searchBox:SetHeight(18)
    end

    main.ebHolder:ClearAllPoints()
    if db().editBoxTop then
        main.ebHolder:SetPoint("TOPLEFT", 4, -(afterTabs + searchH + 2))
        main.ebHolder:SetPoint("TOPRIGHT", -4, -(afterTabs + searchH + 2))
        main.ebHolder:SetHeight(ebH)
        main.smf:ClearAllPoints()
        main.smf:SetPoint("TOPLEFT", 8, -(afterTabs + searchH + ebH + 6))
        main.smf:SetPoint("BOTTOMRIGHT", -8, 6)
    else
        main.ebHolder:SetPoint("BOTTOMLEFT", 4, 4)
        main.ebHolder:SetPoint("BOTTOMRIGHT", -4, 4)
        main.ebHolder:SetHeight(ebH)
        main.smf:ClearAllPoints()
        main.smf:SetPoint("TOPLEFT", 8, -(afterTabs + searchH + 4))
        main.smf:SetPoint("BOTTOMRIGHT", -8, ebH + 8)
    end
end

local function saveMainPosition()
    local f = main.frame
    db().point = { "BOTTOMLEFT", math.floor(f:GetLeft() + 0.5), math.floor(f:GetBottom() + 0.5) }
    db().width = math.floor(f:GetWidth() + 0.5)
    db().height = math.floor(f:GetHeight() + 0.5)
end

-------------------------------------------------------------------------------
-- Main window construction
-------------------------------------------------------------------------------
local function createMain()
    local f = CreateFrame("Frame", "LogLoversChat", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    main = { frame = f, tabButtons = {} }
    f:SetFrameStrata("LOW")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    NS.SetResizeLimits(f, 260, 120, 1400, 900)
    NS.SkinPanel(f)
    local p = db().point
    f:SetPoint(p[1] or "BOTTOMLEFT", UIParent, p[1] or "BOTTOMLEFT", p[2] or 30, p[3] or 30)
    f:SetSize(db().width or 460, db().height or 240)

    -- title bar
    local tb = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    main.titleBar = tb
    tb:SetPoint("TOPLEFT", 1, -1)
    tb:SetPoint("TOPRIGHT", -1, -1)
    tb:SetHeight(19)
    NS.SkinPanel(tb, NS.db.appearance.titleBg)
    tb:SetBackdropBorderColor(0, 0, 0, 0)
    tb:EnableMouse(true)
    tb:RegisterForDrag("LeftButton")
    tb:SetScript("OnDragStart", function()
        if not db().locked then f:StartMoving() end
    end)
    tb:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        saveMainPosition()
    end)

    -- the tab strip lives in the title bar itself; no separate "Chat" label
    main.tabsRow = tb

    local gear = NS.MakeIconButton(tb, "Interface\\Buttons\\UI-OptionsButton",
        "Chat options", function() NS.OpenOptionsPage("chat") end)
    gear:SetPoint("TOPRIGHT", -4, -2)
    local copy = NS.MakeIconButton(tb, "Interface\\Buttons\\UI-GuildButton-PublicNote-Up",
        "Copy chat text", function() NS.CopyChatView(db().activeView) end)
    copy:SetPoint("RIGHT", gear, "LEFT", -3, 0)
    local search = NS.MakeIconButton(tb, "Interface\\Common\\UI-Searchbox-Icon",
        "Search chat", function() NS.ToggleChatSearch() end)
    search:SetPoint("RIGHT", copy, "LEFT", -3, 0)
    -- Clearing only the frame looked like it worked and then undid itself on
    -- the next repaint, because every window renders from the buffer.
    local clear = NS.MakeIconButton(tb, "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
        "Clear chat history", function()
            NS.ShowMenu({
                { text = "Clear chat history?", header = true },
                { text = "Clear it", func = function()
                    CHAT.Clear()
                    NS.RefreshChat()
                    NS.Print("chat history cleared.")
                end },
                { text = "Cancel", func = function() end },
            })
        end)
    clear:SetPoint("RIGHT", search, "LEFT", -3, 0)
    main.titleButtons = { gear, copy, search, clear }

    -- re-wrap tabs when the window is resized
    f:SetScript("OnSizeChanged", function()
        if main and main.tabButtons[1] then updateTabs() end
    end)

    -- SMF
    main.smf = makeChatSMF(f, activeView)
    styleChatSMF(main.smf, db().fontSize)

    -- whisper alert bar (shown when a whisper arrives)
    local ab = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    main.alertBar = ab
    NS.SkinPanel(ab, { r = 0.20, g = 0.09, b = 0.06, a = 0.94 }, { r = 0.88, g = 0.35, b = 0.32, a = 0.9 })
    ab.text = ab:CreateFontString(nil, "OVERLAY")
    ab.text:SetFont(NS.CurrentFont(), 11, "")
    ab.text:SetPoint("LEFT", 8, 0)
    ab.pop = CreateFrame("Button", nil, ab)
    ab.pop:SetSize(70, 16)
    ab.pop:SetPoint("RIGHT", -26, 0)
    ab.pop.text = ab.pop:CreateFontString(nil, "OVERLAY")
    ab.pop.text:SetFont(NS.CurrentFont(), 11, "")
    ab.pop.text:SetPoint("RIGHT")
    ab.pop.text:SetText(C("[pop out]", NS.COLORS.accent))
    ab.pop.hl = ab.pop:CreateTexture(nil, "HIGHLIGHT")
    ab.pop.hl:SetAllPoints()
    ab.pop.hl:SetColorTexture(NS.ACCENT.r, NS.ACCENT.g, NS.ACCENT.b, 0.10)
    ab.dismiss = NS.MakeIconButton(ab, "Interface\\Buttons\\UI-StopButton", nil,
        function() NS.HideWhisperBar() end)
    ab.dismiss:SetPoint("RIGHT", -4, 0)
    ab:Hide()

    -- search
    local sb = CreateFrame("EditBox", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    main.searchBox = sb
    NS.SkinPanel(sb, { r = 0, g = 0, b = 0, a = 0.6 })
    sb:SetFont(NS.CurrentFont(), 11, "")
    sb:SetTextInsets(6, 6, 0, 0)
    sb:SetAutoFocus(false)
    sb:SetScript("OnTextChanged", function(self, user)
        if not user then return end
        local t = string.lower(self:GetText() or "")
        main.searchText = t ~= "" and t or nil
        if main.searchTimer then main.searchTimer:Cancel() end
        main.searchTimer = C_Timer.NewTimer(0.15, refreshMain)
    end)
    sb:SetScript("OnEscapePressed", function() NS.ToggleChatSearch(false) end)
    sb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    sb:Hide()

    -- edit box holder
    local ebh = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    main.ebHolder = ebh
    NS.SkinPanel(ebh, { r = 0, g = 0, b = 0, a = 0.55 })

    -- resize grip
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function()
        if not db().locked then f:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        saveMainPosition()
    end)
    main.grip = grip

    -- bg alpha override
    if db().bgAlpha then
        local ap = NS.db.appearance
        f:SetBackdropColor(ap.bg.r, ap.bg.g, ap.bg.b, db().bgAlpha)
    end

    layoutMain()
end

-------------------------------------------------------------------------------
-- Breakout chat windows
-------------------------------------------------------------------------------
local function createBreakout(viewIndex)
    local v = views()[viewIndex]
    if not v then return end
    local f = CreateFrame("Frame", nil, UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    local b = { frame = f, view = v, viewIndex = viewIndex }
    f:SetFrameStrata("LOW")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    NS.SetResizeLimits(f, 200, 90, 1200, 800)
    NS.SkinPanel(f)
    local p = v.point or { "BOTTOMLEFT", 520, 30 }
    f:SetPoint(p[1], UIParent, p[1], p[2], p[3])
    f:SetSize(v.width or 340, v.height or 180)

    local ap = NS.db.appearance
    local tb = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    b.titleBar = tb
    tb:SetPoint("TOPLEFT", 1, -1)
    tb:SetPoint("TOPRIGHT", -1, -1)
    tb:SetHeight(ap.titleHeight or 19)
    NS.SkinPanel(tb, ap.titleBg)
    tb:SetBackdropBorderColor(0, 0, 0, 0)
    tb:EnableMouse(true)
    tb:RegisterForDrag("LeftButton")
    tb:SetScript("OnDragStart", function()
        if not db().locked then f:StartMoving() end
    end)
    tb:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        v.point = { "BOTTOMLEFT", math.floor(f:GetLeft() + 0.5), math.floor(f:GetBottom() + 0.5) }
        v.width = math.floor(f:GetWidth() + 0.5)
        v.height = math.floor(f:GetHeight() + 0.5)
    end)
    tb:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then NS.ShowChatTabMenu(b.viewIndex) end
    end)

    local title = tb:CreateFontString(nil, "OVERLAY")
    title:SetFont(NS.CurrentFont(), ap.titleFontSize or 11, "")
    title:SetPoint("LEFT", 8, 0)
    title:SetText(C(v.name, NS.COLORS.accent))
    b.title = title

    local dock = NS.MakeIconButton(tb, "Interface\\Buttons\\UI-StopButton",
        "Dock back as a tab", function() NS.DockChatView(b.viewIndex) end)
    dock:SetPoint("RIGHT", -4, 0)
    local copy = NS.MakeIconButton(tb, "Interface\\Buttons\\UI-GuildButton-PublicNote-Up",
        "Copy text", function() NS.CopyChatView(b.viewIndex) end)
    copy:SetPoint("RIGHT", dock, "LEFT", -3, 0)

    b.smf = makeChatSMF(f, function() return v end)
    styleChatSMF(b.smf, db().fontSize)
    b.smf:SetPoint("TOPLEFT", 8, -((ap.titleHeight or 19) + 4))

    -- whisper conversation windows get their own reply box
    if v.filter and v.filter.whisperWith then
        local target = v.whisperTarget or v.name
        local holder = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
        NS.SkinPanel(holder, { r = 0, g = 0, b = 0, a = 0.55 })
        holder:SetPoint("BOTTOMLEFT", 4, 4)
        holder:SetPoint("BOTTOMRIGHT", -4, 4)
        holder:SetHeight(20)
        local input = CreateFrame("EditBox", nil, holder)
        b.replyBox = input
        input:SetPoint("TOPLEFT", 4, -2)
        input:SetPoint("BOTTOMRIGHT", -4, 2)
        input:SetFont(NS.CurrentFont(), db().fontSize or ap.fontSize, "")
        input:SetAutoFocus(false)
        local ph = holder:CreateFontString(nil, "OVERLAY")
        ph:SetFont(NS.CurrentFont(), db().fontSize or ap.fontSize, "")
        ph:SetPoint("LEFT", 6, 0)
        ph:SetText(C("Reply to " .. v.name .. "...", "6b7280"))
        local function updatePlaceholder()
            ph:SetShown(not input:HasFocus() and input:GetText() == "")
        end
        input:SetScript("OnEditFocusGained", updatePlaceholder)
        input:SetScript("OnEditFocusLost", updatePlaceholder)
        input:SetScript("OnTextChanged", updatePlaceholder)
        input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        input:SetScript("OnEnterPressed", function(self)
            local text = self:GetText() or ""
            if text ~= "" then
                if text:sub(1, 1) == "/" then
                    -- commands belong to the main chat box; hand the text over
                    self:SetText("")
                    if ChatFrame_OpenChat then ChatFrame_OpenChat(text, DEFAULT_CHAT_FRAME) end
                else
                    SendChatMessage(text, "WHISPER", nil, target)
                    if NS.SetLastToldTarget then NS.SetLastToldTarget(target, "WHISPER") end
                    self:SetText("")
                end
            end
            updatePlaceholder()
        end)
        -- clicking anywhere on the window focuses the reply box
        f:EnableMouse(true)
        f:SetScript("OnMouseDown", function() input:SetFocus() end)
        tb:HookScript("OnMouseDown", function() input:SetFocus() end)
        b.smf:HookScript("OnMouseDown", function() input:SetFocus() end)
        b.smf:SetPoint("BOTTOMRIGHT", -8, 28)
    else
        b.smf:SetPoint("BOTTOMRIGHT", -8, 6)
    end

    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetScript("OnMouseDown", function()
        if not db().locked then f:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        v.width = math.floor(f:GetWidth() + 0.5)
        v.height = math.floor(f:GetHeight() + 0.5)
    end)

    breakouts[viewIndex] = b
    refreshBreakout(b)
end

rebuildBreakouts = function()
    for idx, b in pairs(breakouts) do
        b.frame:Hide()
        b.frame:SetParent(nil)
        breakouts[idx] = nil
    end
    for i, v in ipairs(views()) do
        if v.mode == "window" then createBreakout(i) end
    end
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------
function NS.InitChatWindow()
    CHAT = NS.CHAT
    local d = db()
    if #d.views == 0 then
        d.views = {
            { name = "All",      filter = CHAT.DefaultFilter("all"),      mode = "tab", unread = 0 },
            { name = "Whispers", filter = CHAT.DefaultFilter("whispers"), mode = "tab", unread = 0 },
            { name = "Guild",    filter = CHAT.DefaultFilter("guild"),    mode = "tab", unread = 0 },
            { name = "Loot",     filter = CHAT.DefaultFilter("loot"),     mode = "tab", unread = 0 },
        }
        d.activeView = 1
    end
    -- one-time: give existing installs a docked Combat Log tab too
    if not d.combatTabSeeded then
        d.combatTabSeeded = true
        local hasCombat = false
        for _, v in ipairs(d.views) do
            if v.kind == "combat" then hasCombat = true break end
        end
        if not hasCombat then
            -- a brand new Combat Log tab defaults to "just me & my pet";
            -- a city or raid is unreadable otherwise
            table.insert(d.views, {
                name = "Combat Log", kind = "combat",
                combatFilter = NS.PresetFilter("everything"),
                mode = "tab", unread = 0,
            })
        end
    end
    for _, v in ipairs(d.views) do
        v.unread, v.alert = 0, nil
        -- 1.3.1 migration: TRADESKILL split out of SKILL; inherit the old value
        if v.filter and v.filter.types and v.filter.types.TRADESKILL == nil then
            v.filter.types.TRADESKILL = v.filter.types.SKILL and true or false
        end
    end
    createMain()
    setupEditBox()
    updateTabs()
    refreshMain()
    rebuildBreakouts()

    -- re-assert edit box docking after loading screens
    local ebFrame = CreateFrame("Frame")
    ebFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    ebFrame:SetScript("OnEvent", function()
        -- a loading screen used to re-dock the box into the chat window even
        -- when that window was hidden, leaving no visible way to type
        if main and main.frame:IsShown() then
            setupEditBox()
        else
            floatEditBox()
        end
    end)
end

function NS.ToggleChatSearch(force)
    if not main then return end
    if force ~= nil then main.searchShown = force
    else main.searchShown = not main.searchShown end
    if not main.searchShown then
        main.searchBox:SetText("")
        main.searchText = nil
    end
    layoutMain()
    if main.searchShown then main.searchBox:SetFocus() end
    refreshMain()
end

function NS.ToggleChatWindow()
    if not main then return end
    local show = not main.frame:IsShown()
    main.frame:SetShown(show)
    local eb = _G.ChatFrame1EditBox
    if show then
        setupEditBox()
        updateTabs()
        refreshMain()
    elseif eb then
        floatEditBox()
    end
end

-- test hook: the scrolling frame the main window renders into
function NS.MainChatSMF()
    return main and main.smf
end

function NS.RefreshChat()
    if not main then return end
    updateTabs()
    refreshMain()
    for _, b in pairs(breakouts) do refreshBreakout(b) end
end

function NS.ApplyChatAppearance()
    if not main then return end
    NS.SkinPanel(main.frame)
    if db().bgAlpha then
        local ap = NS.db.appearance
        main.frame:SetBackdropColor(ap.bg.r, ap.bg.g, ap.bg.b, db().bgAlpha)
    end
    NS.SkinPanel(main.titleBar, NS.db.appearance.titleBg)
    main.titleBar:SetBackdropBorderColor(0, 0, 0, 0)
    styleChatSMF(main.smf, db().fontSize)
    local ap = NS.db.appearance
    for _, b in pairs(breakouts) do
        NS.SkinPanel(b.frame)
        styleChatSMF(b.smf, db().fontSize)
        if b.titleBar then
            NS.SkinPanel(b.titleBar, ap.titleBg)
            b.titleBar:SetBackdropBorderColor(0, 0, 0, 0)
            b.titleBar:SetHeight(ap.titleHeight or 19)
        end
        if b.title then
            b.title:SetFont(NS.CurrentFont(), ap.titleFontSize or 11, "")
        end
        b.smf:ClearAllPoints()
        b.smf:SetPoint("TOPLEFT", 8, -((ap.titleHeight or 19) + 4))
        -- a whisper pop-out has its own reply box along the bottom; re-anchoring
        -- flat to 6 used to run the text straight through it
        b.smf:SetPoint("BOTTOMRIGHT", -8, b.replyBox and 28 or 6)
    end
    setupEditBox()
    NS.RefreshChat()
end

function NS.ApplyChatLayout()
    if not main then return end
    layoutMain()
    NS.RefreshChat()
end

function NS.CopyChatView(viewIndex)
    local v = views()[viewIndex]
    if not v then return end
    local lines = {}
    if v.kind == "combat" then
        NS.BufferEach(function(rec)
            if NS.RecordPasses(rec, v.combatFilter) then
                lines[#lines + 1] = NS.ExportLine(rec)
            end
        end)
    else
        CHAT.Each(function(w)
            if CHAT.Passes(w.d, v.filter) then
                CHAT.FormatWrapper(w)
                lines[#lines + 1] = date("%H:%M:%S", w.d.t) .. " " .. w.plain
            end
        end)
    end
    NS.ShowCopyText("Chat: " .. v.name .. " (" .. #lines .. " lines)",
        table.concat(lines, "\n"))
end

function NS.BreakOutChatView(viewIndex)
    local v = views()[viewIndex]
    if not v then return end
    if v.kind == "combat" then
        -- promote to a full combat window (all combat window features)
        local idx = NS.AddWindow(v.name, "everything")
        NS.db.windows[idx].filter = v.combatFilter
        table.remove(views(), viewIndex)
        if db().activeView >= viewIndex then
            db().activeView = math.max(1, db().activeView - 1)
        end
        local vlist = views()
        if vlist[db().activeView] and vlist[db().activeView].mode == "window" then
            for i, vv in ipairs(vlist) do
                if vv.mode ~= "window" then db().activeView = i break end
            end
        end
        NS.RefreshWindow(NS.windows[idx])
        updateTabs()
        refreshMain()
        rebuildBreakouts()
        NS.Print("\"" .. v.name .. "\" is now a combat window. Its title-bar menu can dock it back.")
        return
    end
    v.mode = "window"
    if db().activeView == viewIndex then
        for i, vv in ipairs(views()) do
            if vv.mode ~= "window" then db().activeView = i break end
        end
    end
    updateTabs()
    refreshMain()
    rebuildBreakouts()
end

-- a combat window docks itself into the chat window as a tab
function NS.DockCombatWindowAsTab(windowIndex)
    local cfgW = NS.db.windows[windowIndex]
    if not cfgW then return end
    if not main then
        NS.Print("the chat module is disabled - enable it to dock combat tabs.")
        return
    end
    if #NS.db.windows <= 1 then
        -- keep the last combat window around (hidden); dock a copy of its filter
        table.insert(views(), {
            name = cfgW.name, kind = "combat", combatFilter = NS.DeepCopy(cfgW.filter),
            mode = "tab", unread = 0,
        })
        cfgW.shown = false
        if NS.windows[windowIndex] then NS.windows[windowIndex].frame:Hide() end
        NS.Print("docked as a tab. Your last combat window was hidden, not deleted - reopen it from Windows & Tabs.")
    else
        table.insert(views(), {
            name = cfgW.name, kind = "combat", combatFilter = cfgW.filter,
            mode = "tab", unread = 0,
        })
        NS.DeleteWindow(windowIndex)
    end
    db().activeView = #views()
    updateTabs()
    refreshMain()
end

-------------------------------------------------------------------------------
-- Whisper alert bar / per-person popouts
-------------------------------------------------------------------------------
local whisperBarTimer

function NS.HideWhisperBar()
    if main and main.alertBar then
        main.alertBar:Hide()
        layoutMain()
    end
end

function NS.NotifyWhisper(author)
    if not main or not main.frame:IsShown() then return end
    local stripped = CHAT.StripName(author)
    -- if a conversation window for this person already exists, no bar needed
    for _, v in ipairs(views()) do
        if v.filter and v.filter.whisperWith == stripped then return end
    end
    local ab = main.alertBar
    local disp = author:match("^([^%-]+)") or author
    ab.text:SetText(C("Whisper from ", NS.COLORS.dim) .. C(disp, NS.COLORS.dispel))
    ab.pop:SetScript("OnClick", function()
        NS.PopOutWhisper(author)
        NS.HideWhisperBar()
    end)
    if not ab:IsShown() then
        ab:Show()
        layoutMain()
    end
    if whisperBarTimer then whisperBarTimer:Cancel() end
    whisperBarTimer = C_Timer.NewTimer(15, NS.HideWhisperBar)
end

function NS.PopOutWhisper(author)
    local stripped = CHAT.StripName(author)
    local disp = author:match("^([^%-]+)") or author
    -- reuse an existing conversation view if there is one
    for i, v in ipairs(views()) do
        if v.filter and v.filter.whisperWith == stripped then
            v.mode = "window"
            v.whisperTarget = v.whisperTarget or author
            -- If that conversation was the tab you were reading, the strip now
            -- has an active tab that is no longer a tab: the main window went
            -- blank and stopped taking new chat. Move on to a real tab first.
            if db().activeView == i then
                for j, other in ipairs(views()) do
                    if other.mode ~= "window" then db().activeView = j break end
                end
            end
            updateTabs()
            refreshMain()
            rebuildBreakouts()
            return
        end
    end
    local f = CHAT.DefaultFilter("whispers")
    f.whisperWith = stripped
    table.insert(views(), {
        name = disp, kind = "chat", filter = f, mode = "window", unread = 0,
        whisperTarget = author,
        point = { "BOTTOMLEFT", 420, 260 }, width = 320, height = 160,
    })
    rebuildBreakouts()
    NS.Print("whisper window opened for " .. disp ..
        ". Right-click its title bar to dock or delete it.")
end

function NS.DockChatView(viewIndex)
    local v = views()[viewIndex]
    if not v then return end
    v.mode = "tab"
    updateTabs()
    refreshMain()
    rebuildBreakouts()
end

function NS.AddChatView(name, presetKey)
    if presetKey == "combatlog" or presetKey == "aoefarm" then
        table.insert(views(), {
            name = name, kind = "combat",
            combatFilter = NS.PresetFilter(presetKey == "aoefarm" and "aoefarm" or "everything"),
            mode = "tab", unread = 0,
        })
    else
        table.insert(views(), {
            name = name, filter = CHAT.DefaultFilter(presetKey), mode = "tab", unread = 0,
        })
    end
    db().activeView = #views()
    updateTabs()
    refreshMain()
    return #views()
end

function NS.DeleteChatView(viewIndex)
    local vlist = views()
    if #vlist <= 1 then
        NS.Print("you cannot delete the last chat view.")
        return
    end
    table.remove(vlist, viewIndex)
    if db().activeView >= viewIndex then
        db().activeView = math.max(1, db().activeView - 1)
    end
    -- make sure the active view is a tab, not a breakout window
    if vlist[db().activeView] and vlist[db().activeView].mode == "window" then
        for i, vv in ipairs(vlist) do
            if vv.mode ~= "window" then db().activeView = i break end
        end
    end
    updateTabs()
    refreshMain()
    rebuildBreakouts()
end

-------------------------------------------------------------------------------
-- Menus
-------------------------------------------------------------------------------
StaticPopupDialogs["LogLovers_RENAME_CHATVIEW"] = {
    text = "Rename chat tab",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function(self, data)
        local eb = self.GetEditBox and self:GetEditBox() or self.editBox
        local txt = eb and eb:GetText()
        if txt and txt ~= "" and data and views()[data] then
            views()[data].name = txt
            updateTabs()
            local b = breakouts[data]
            if b then b.title:SetText(C(txt, NS.COLORS.accent)) end
        end
    end,
    OnShow = function(self, data)
        local eb = self.GetEditBox and self:GetEditBox() or self.editBox
        if eb and data and views()[data] then eb:SetText(views()[data].name) end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["LogLovers_RENAME_CHATVIEW"].OnAccept(parent, parent.data)
        parent:Hide()
    end,
}

function NS.ShowChatTabMenu(viewIndex)
    local v = views()[viewIndex]
    if not v then return end
    local isWindow = v.mode == "window"
    local isCombat = v.kind == "combat"
    local breakLabel
    if isCombat then breakLabel = "Break out into combat window"
    elseif isWindow then breakLabel = "Dock as tab"
    else breakLabel = "Break out into window" end
    NS.ShowMenu({
        { text = v.name, header = true },
        { text = "Rename...", func = function()
            StaticPopup_Show("LogLovers_RENAME_CHATVIEW", nil, nil, viewIndex)
        end },
        { text = "Edit filters...", func = function()
            NS.OpenOptionsPage("chat", viewIndex)
        end },
        { text = breakLabel, func = function()
            if isWindow and not isCombat then NS.DockChatView(viewIndex)
            else NS.BreakOutChatView(viewIndex) end
        end },
        { text = "Mark all read", disabled = isCombat, func = function()
            v.unread, v.alert = 0, nil
            updateTabs()
        end },
        { text = "Copy text...", func = function() NS.CopyChatView(viewIndex) end },
        { text = "New tab...", func = function() NS.ShowNewChatViewMenu() end },
        { text = "Delete...", func = function() NS.DeleteChatView(viewIndex) end },
    })
end

-- onCreated is called with the new view's index once the user has actually
-- picked something. The options page used to guess on a zero-second timer,
-- which fires while the menu is still open - so it selected the PREVIOUS tab
-- and every edit after that silently landed on the wrong one.
function NS.ShowNewChatViewMenu(onCreated)
    local function made(name, key)
        local idx = NS.AddChatView(name, key)
        if onCreated then onCreated(idx) end
    end
    local items = { { text = "New chat tab", header = true } }
    for _, p in ipairs(NS.CHAT.VIEW_PRESETS) do
        table.insert(items, { text = p.label, func = function() made(p.label, p.key) end })
    end
    table.insert(items, { separator = true })
    table.insert(items, { text = "Combat log", func = function()
        made("Combat Log", "combatlog")
    end })
    table.insert(items, { text = "AoE farming (kills only)", func = function()
        made("Kills", "aoefarm")
    end })
    NS.ShowMenu(items)
end
