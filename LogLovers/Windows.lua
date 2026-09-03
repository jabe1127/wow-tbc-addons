-- LogLovers Windows: breakout combat log windows (dark glass skin)
local ADDON, NS = ...

NS.windows = {}   -- runtime objects: { cfg, frame, smf, title, search, searchText }

-------------------------------------------------------------------------------
-- Shared skin helpers
-------------------------------------------------------------------------------
local WHITE = "Interface\\Buttons\\WHITE8x8"

function NS.SkinPanel(frame, bg, border)
    if not frame.SetBackdrop and BackdropTemplateMixin then
        Mixin(frame, BackdropTemplateMixin)
    end
    frame:SetBackdrop({
        bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
    })
    local ap = NS.db and NS.db.appearance or NS.DEFAULTS.appearance
    bg = bg or ap.bg
    border = border or ap.border
    frame:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
    frame:SetBackdropBorderColor(border.r, border.g, border.b, border.a)
end

function NS.MakeIconButton(parent, texture, tip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(14, 14)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    t:SetTexture(texture)
    t:SetVertexColor(0.75, 0.78, 0.85, 0.8)
    b.tex = t
    b:SetScript("OnEnter", function(self)
        t:SetVertexColor(1, 1, 1, 1)
        if tip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tip, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        t:SetVertexColor(0.75, 0.78, 0.85, 0.8)
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", onClick)
    return b
end

-------------------------------------------------------------------------------
-- Window object
-------------------------------------------------------------------------------
local function windowFontSize(win)
    return win.cfg.fontSize or NS.db.appearance.fontSize
end

local function applyWindowSkin(win)
    local ap = NS.db.appearance
    local a = win.cfg.bgAlpha or ap.bg.a
    win.frame:SetBackdropColor(ap.bg.r, ap.bg.g, ap.bg.b, a)
    win.frame:SetBackdropBorderColor(ap.border.r, ap.border.g, ap.border.b, ap.border.a)
    if win.titleBar then
        win.titleBar:SetBackdropColor(ap.titleBg.r, ap.titleBg.g, ap.titleBg.b, ap.titleBg.a)
        win.titleBar:SetBackdropBorderColor(0, 0, 0, 0)
        win.titleBar:SetHeight(ap.titleHeight or 19)
    end
    if win.title then
        win.title:SetFont(NS.CurrentFont(), ap.titleFontSize or 11, "")
    end
    win.smf:SetFont(NS.CurrentFont(), windowFontSize(win), ap.outline)
    win.smf:SetSpacing(ap.lineSpacing)
    win.smf:SetShadowColor(0, 0, 0, 0.9)
    win.smf:SetShadowOffset(1, -1)
end

local function savePosition(win)
    local f = win.frame
    win.cfg.point = { "BOTTOMLEFT", math.floor(f:GetLeft() + 0.5), math.floor(f:GetBottom() + 0.5) }
    win.cfg.width = math.floor(f:GetWidth() + 0.5)
    win.cfg.height = math.floor(f:GetHeight() + 0.5)
end

local function restorePosition(win)
    local f = win.frame
    f:ClearAllPoints()
    local p = win.cfg.point
    f:SetPoint(p[1] or "BOTTOMLEFT", UIParent, p[1] or "BOTTOMLEFT", p[2] or 30, p[3] or 140)
    f:SetSize(win.cfg.width or 520, win.cfg.height or 220)
end

local function layoutWindow(win)
    local topInset = win.cfg.showTitle and ((NS.db.appearance.titleHeight or 19) + 3) or 6
    local bottomInset = win.searchShown and 26 or 6
    win.smf:ClearAllPoints()
    win.smf:SetPoint("TOPLEFT", 8, -topInset)
    win.smf:SetPoint("BOTTOMRIGHT", -8, bottomInset)
    if win.titleBar then win.titleBar:SetShown(win.cfg.showTitle) end
    if win.searchBox then win.searchBox:SetShown(win.searchShown) end
end

function NS.RefreshWindow(win)
    if not win then return end
    local smf = win.smf
    smf:Clear()
    local pass = 0
    NS.BufferEach(function(rec)
        if NS.RecordPasses(rec, win.cfg.filter) then
            NS.FormatRecord(rec)
            if NS.RecordMatchesSearch(rec, win.searchText) then
                smf:AddMessage(rec.line)
                pass = pass + 1
            end
        end
    end)
    if win.searchText and win.searchText ~= "" then
        smf:AddMessage(NS.C("— search: \"" .. win.searchText .. "\" (" .. pass .. " lines) —", NS.COLORS.accent))
    end
end

function NS.RefreshAllWindows()
    for _, win in ipairs(NS.windows) do NS.RefreshWindow(win) end
end

function NS.ApplyAppearance()
    NS.InvalidateFormats()
    for _, win in ipairs(NS.windows) do
        applyWindowSkin(win)
        layoutWindow(win)
        NS.RefreshWindow(win)
    end
    if NS.ApplyChatAppearance then NS.ApplyChatAppearance() end
end

local function setLocked(win, locked)
    win.cfg.locked = locked
    win.grip:SetShown(not locked)
end

local function setClickThrough(win, on)
    win.cfg.clickThrough = on
    win.frame:EnableMouse(not on)
    win.smf:EnableMouse(not on)
    -- title bar stays interactive so you can always get the window back
end

local function toggleSearch(win, forceShow)
    if forceShow ~= nil then
        win.searchShown = forceShow
    else
        win.searchShown = not win.searchShown
    end
    layoutWindow(win)
    if win.searchShown then
        win.searchBox:SetFocus()
    else
        win.searchBox:SetText("")
        win.searchText = nil
        NS.RefreshWindow(win)
    end
end

-------------------------------------------------------------------------------
-- Construction
-------------------------------------------------------------------------------
local function onSearchChanged(win, text)
    text = string.lower(text or "")
    if text == "" then win.searchText = nil else win.searchText = text end
    if win.searchTimer then win.searchTimer:Cancel() end
    win.searchTimer = C_Timer.NewTimer(0.15, function() NS.RefreshWindow(win) end)
end

local function createWindow(cfg, index)
    local win = { cfg = cfg, index = index }

    local f = CreateFrame("Frame", "LogLoversWindow" .. index, UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    win.frame = f
    f:SetFrameStrata("LOW")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    NS.SetResizeLimits(f, 220, 90, 1400, 900)
    NS.SkinPanel(f)

    -- Title bar ----------------------------------------------------------
    local tb = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    win.titleBar = tb
    tb:SetPoint("TOPLEFT", 1, -1)
    tb:SetPoint("TOPRIGHT", -1, -1)
    tb:SetHeight(19)
    NS.SkinPanel(tb, NS.db.appearance.titleBg)
    tb:EnableMouse(true)
    tb:RegisterForDrag("LeftButton")
    tb:SetScript("OnDragStart", function()
        if not win.cfg.locked then f:StartMoving() end
    end)
    tb:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        savePosition(win)
    end)
    tb:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then NS.ShowWindowMenu(win) end
    end)

    local title = tb:CreateFontString(nil, "OVERLAY")
    title:SetFont(NS.CurrentFont(), 11, "")
    title:SetPoint("LEFT", 8, 0)
    title:SetText(NS.C(cfg.name, NS.COLORS.accent))
    win.title = title

    -- Title buttons (right to left)
    local close = NS.MakeIconButton(tb, "Interface\\Buttons\\UI-StopButton",
        "Hide window (reopen via /ll)", function()
            cfg.shown = false
            f:Hide()
        end)
    close:SetPoint("RIGHT", -4, 0)
    local gear = NS.MakeIconButton(tb, "Interface\\Buttons\\UI-OptionsButton",
        "Window options", function() NS.OpenOptionsForWindow(win.index) end)
    gear:SetPoint("RIGHT", close, "LEFT", -3, 0)
    local copy = NS.MakeIconButton(tb, "Interface\\Buttons\\UI-GuildButton-PublicNote-Up",
        "Copy / export text", function() NS.OpenCopy(win.index) end)
    copy:SetPoint("RIGHT", gear, "LEFT", -3, 0)
    local search = NS.MakeIconButton(tb, "Interface\\Common\\UI-Searchbox-Icon",
        "Search this window", function() toggleSearch(win) end)
    search:SetPoint("RIGHT", copy, "LEFT", -3, 0)
    local clear = NS.MakeIconButton(tb, "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
        "Clear window", function() win.smf:Clear() end)
    clear:SetPoint("RIGHT", search, "LEFT", -3, 0)

    -- Scrolling message frame -------------------------------------------
    local smf = CreateFrame("ScrollingMessageFrame", nil, f)
    win.smf = smf
    smf:SetJustifyH("LEFT")
    smf:SetFading(cfg.fade or false)
    smf:SetTimeVisible(cfg.fadeTime or 12)
    smf:SetFadeDuration(1.5)
    smf:SetMaxLines(cfg.maxLines or 1500)
    smf:SetInsertMode(SCROLLING_MESSAGE_FRAME_INSERT_MODE_BOTTOM or "BOTTOM")
    if smf.SetIndentedWordWrap then smf:SetIndentedWordWrap(true) end
    smf:SetHyperlinksEnabled(true)
    smf:EnableMouse(true)
    smf:EnableMouseWheel(true)
    smf:SetScript("OnMouseWheel", function(self, delta)
        if IsControlKeyDown() then
            if delta > 0 then self:ScrollToTop() else self:ScrollToBottom() end
        elseif IsShiftKeyDown() then
            if delta > 0 then self:PageUp() else self:PageDown() end
        else
            for _ = 1, 3 do
                if delta > 0 then self:ScrollUp() else self:ScrollDown() end
            end
        end
    end)
    smf:SetScript("OnHyperlinkClick", function(_, link, text, button)
        NS.HandleLinkClick(win, link, text, button)
    end)
    smf:SetScript("OnHyperlinkEnter", function(self, link)
        NS.HandleLinkEnter(self, link)
    end)
    smf:SetScript("OnHyperlinkLeave", function()
        GameTooltip:Hide()
    end)

    -- "jump to present" pill, shown while scrolled up ---------------------
    local jump = CreateFrame("Button", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    NS.SkinPanel(jump, { r = 0.30, g = 0.21, b = 0.07, a = 0.92 })
    jump:SetSize(110, 16)
    jump:SetPoint("BOTTOM", 0, 8)
    local jt = jump:CreateFontString(nil, "OVERLAY")
    jt:SetFont(NS.CurrentFont(), 10, "")
    jt:SetPoint("CENTER")
    jt:SetText("v  newest  v")
    jump:SetScript("OnClick", function() smf:ScrollToBottom() end)
    jump:Hide()
    -- Every frame, per window, just to decide whether an arrow is visible. Ten
    -- times a second is imperceptible and costs a fraction as much.
    local jumpAccum = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        jumpAccum = jumpAccum + (elapsed or 0)
        if jumpAccum < 0.1 then return end
        jumpAccum = 0
        local up = not smf:AtBottom()
        if up ~= jump:IsShown() then jump:SetShown(up) end
    end)

    -- Search box ---------------------------------------------------------
    local sb = CreateFrame("EditBox", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    win.searchBox = sb
    NS.SkinPanel(sb, { r = 0, g = 0, b = 0, a = 0.6 })
    sb:SetHeight(18)
    sb:SetPoint("BOTTOMLEFT", 6, 4)
    sb:SetPoint("BOTTOMRIGHT", -6, 4)
    sb:SetFont(NS.CurrentFont(), 11, "")
    sb:SetTextInsets(6, 6, 0, 0)
    sb:SetAutoFocus(false)
    sb:SetScript("OnTextChanged", function(self, user)
        if user then onSearchChanged(win, self:GetText()) end
    end)
    sb:SetScript("OnEscapePressed", function() toggleSearch(win, false) end)
    sb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    sb:Hide()

    -- Resize grip ---------------------------------------------------------
    local grip = CreateFrame("Button", nil, f)
    win.grip = grip
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function()
        if not win.cfg.locked then f:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        savePosition(win)
    end)

    restorePosition(win)
    applyWindowSkin(win)
    layoutWindow(win)
    setLocked(win, cfg.locked)
    setClickThrough(win, cfg.clickThrough)
    f:SetShown(cfg.shown ~= false)

    return win
end

-------------------------------------------------------------------------------
-- Manager
-------------------------------------------------------------------------------
function NS.InitWindows()
    for i, cfg in ipairs(NS.db.windows) do
        NS.windows[i] = createWindow(cfg, i)
    end
    NS.RefreshAllWindows()
end

function NS.DispatchToWindows(rec)
    for _, win in ipairs(NS.windows) do
        if win.frame:IsShown() and NS.RecordPasses(rec, win.cfg.filter) then
            NS.FormatRecord(rec)
            if NS.RecordMatchesSearch(rec, win.searchText) then
                win.smf:AddMessage(rec.line)
            end
        end
    end
    -- combat-log tabs docked inside the chat window
    if NS.DispatchCombatToChat then NS.DispatchCombatToChat(rec) end
end

function NS.AddWindow(name, presetKey)
    local cfg = NS.DefaultWindow(name or ("Window " .. (#NS.db.windows + 1)), presetKey)
    local n = #NS.db.windows
    cfg.point = { "BOTTOMLEFT", 60 + n * 30, 170 + n * 30 }
    table.insert(NS.db.windows, cfg)
    local idx = #NS.db.windows
    NS.windows[idx] = createWindow(cfg, idx)
    NS.RefreshWindow(NS.windows[idx])
    return idx
end

function NS.DeleteWindow(index)
    local win = NS.windows[index]
    if not win then return end
    win.frame:Hide()
    win.frame:SetParent(nil)
    table.remove(NS.windows, index)
    table.remove(NS.db.windows, index)
    for i, w in ipairs(NS.windows) do w.index = i end
end

function NS.ShowWindow(index)
    local win = NS.windows[index]
    if win then
        win.cfg.shown = true
        win.frame:Show()
        -- a hidden window stops being refreshed, so without this it comes back
        -- showing a frozen snapshot missing everything that happened while it
        -- was away
        NS.RefreshWindow(win)
    end
end

-- Pop out a combat window, reusing a hidden one if there is one.
--
-- Docking the last combat window keeps its config around so its filters are not
-- lost, just hidden. Always creating a new one on top of that piled up configs
-- the user could never see - the phantom "combat log, popped out" entries.
function NS.PopOutCombatWindow(name)
    for i, cfg in ipairs(NS.db.windows or {}) do
        if cfg.shown == false then
            cfg.shown = true
            if name then cfg.name = name end
            if NS.windows[i] then
                NS.windows[i].frame:Show()
                NS.UpdateWindowTitle(i)
                NS.RefreshWindow(NS.windows[i])
            end
            return i
        end
    end
    return NS.AddWindow(name or "Combat", "everything")
end

-- Housekeeping: more than one hidden combat window is always junk left behind
-- by docking. Keep one (it holds a filter someone may want back) and drop the
-- rest.
function NS.PruneHiddenWindows()
    local seenHidden = false
    for i = #(NS.db.windows or {}), 1, -1 do
        local cfg = NS.db.windows[i]
        if cfg.shown == false then
            if seenHidden then
                if NS.windows[i] then
                    NS.windows[i].frame:Hide()
                    NS.windows[i].frame:SetParent(nil)
                    table.remove(NS.windows, i)
                end
                table.remove(NS.db.windows, i)
            else
                seenHidden = true
            end
        end
    end
    for i, w in ipairs(NS.windows) do w.index = i end
end

function NS.SetAllLocked(locked)
    -- Walk the saved configs, not just the live frames: a window that is
    -- currently docked as a chat tab has a config but no frame, and it used to
    -- be skipped entirely - so "lock everything" left things draggable.
    for _, cfg in ipairs(NS.db.windows or {}) do cfg.locked = locked end
    for _, win in ipairs(NS.windows) do setLocked(win, locked) end
    if NS.db.chat then NS.db.chat.locked = locked end
    if NS.RefreshChat then NS.RefreshChat() end
    -- the master switch on the General page shows this state; /ll lock and the
    -- title-bar menus change it from elsewhere, so repaint if it is on screen
    if NS.RefreshOptionsPage then NS.RefreshOptionsPage("general") end
end

-- True only when everything is locked, so one master switch can show a
-- definite state instead of guessing from the first window it finds.
function NS.AllLocked()
    if NS.db.chat and not NS.db.chat.locked then return false end
    for _, cfg in ipairs(NS.db.windows or {}) do
        if not cfg.locked then return false end
    end
    return true
end

function NS.SetWindowLocked(index, locked)
    local win = NS.windows[index]
    if win then setLocked(win, locked) end
end

function NS.SetWindowClickThrough(index, on)
    local win = NS.windows[index]
    if win then setClickThrough(win, on) end
end

function NS.ClearAllWindows()
    for _, win in ipairs(NS.windows) do win.smf:Clear() end
end

function NS.ToggleSearch(index)
    local win = NS.windows[index]
    if win then
        if not win.frame:IsShown() then NS.ShowWindow(index) end
        toggleSearch(win)
    end
end

function NS.ResetWindowPositions()
    for i, win in ipairs(NS.windows) do
        win.cfg.point = { "BOTTOMLEFT", 30 + (i - 1) * 40, 140 + (i - 1) * 40 }
        win.cfg.width, win.cfg.height = 520, 220
        restorePosition(win)
        win.cfg.shown = true
        win.frame:Show()
    end
    NS.Print("window positions reset.")
end

function NS.CreateWindowInteractive()
    NS.ShowPresetMenu(function(presetKey, label)
        local idx = NS.AddWindow(label, presetKey)
        NS.Print("created window \"" .. NS.db.windows[idx].name .. "\".")
    end)
end

function NS.UpdateWindowTitle(index)
    local win = NS.windows[index]
    if win then win.title:SetText(NS.C(win.cfg.name, NS.COLORS.accent)) end
end

function NS.ApplyWindowConfig(index)
    local win = NS.windows[index]
    if not win then return end
    local cfg = win.cfg
    win.smf:SetFading(cfg.fade or false)
    win.smf:SetTimeVisible(cfg.fadeTime or 12)
    win.smf:SetMaxLines(cfg.maxLines or 1500)
    setLocked(win, cfg.locked)
    setClickThrough(win, cfg.clickThrough)
    layoutWindow(win)
    applyWindowSkin(win)
    NS.UpdateWindowTitle(index)
    NS.RefreshWindow(win)
end
