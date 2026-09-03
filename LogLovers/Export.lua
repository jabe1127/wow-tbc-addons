-- LogLovers Export: copy dialogs and SavedVariables capture sessions
local ADDON, NS = ...

local C = NS.C

-------------------------------------------------------------------------------
-- Copy dialog
-------------------------------------------------------------------------------
local copyFrame, copyBox

local function ensureCopy()
    if copyFrame then return end
    copyFrame = CreateFrame("Frame", "LogLoversCopy", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    copyFrame:SetSize(620, 420)
    copyFrame:SetPoint("CENTER")
    copyFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    copyFrame:SetMovable(true)
    copyFrame:EnableMouse(true)
    copyFrame:RegisterForDrag("LeftButton")
    copyFrame:SetScript("OnDragStart", copyFrame.StartMoving)
    copyFrame:SetScript("OnDragStop", copyFrame.StopMovingOrSizing)
    copyFrame:SetClampedToScreen(true)
    NS.SkinPanel(copyFrame, { r = 0.055, g = 0.043, b = 0.028, a = 0.97 })
    tinsert(UISpecialFrames, "LogLoversCopy")

    local title = copyFrame:CreateFontString(nil, "OVERLAY")
    title:SetFont(NS.CurrentFont(), 14, "")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText(C("Copy / Export", NS.COLORS.accent))
    copyFrame.title = title

    local hint = copyFrame:CreateFontString(nil, "OVERLAY")
    hint:SetFont(NS.CurrentFont(), 10, "")
    hint:SetPoint("TOPRIGHT", -30, -13)
    hint:SetText(C("Ctrl+C to copy - Esc to close", NS.COLORS.dim))

    local close = NS.MakeIconButton(copyFrame, "Interface\\Buttons\\UI-StopButton", nil,
        function() copyFrame:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)

    local scroll = CreateFrame("ScrollFrame", "LogLoversCopyScroll", copyFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -32)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)

    copyBox = CreateFrame("EditBox", nil, scroll)
    copyBox:SetMultiLine(true)
    copyBox:SetFontObject(ChatFontNormal)
    copyBox:SetWidth(560)
    copyBox:SetAutoFocus(false)
    copyBox:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
    scroll:SetScrollChild(copyBox)
end

function NS.ShowCopyText(titleText, text)
    ensureCopy()
    copyFrame.title:SetText(C(titleText or "Copy / Export", NS.COLORS.accent))
    copyBox:SetText(text or "")
    copyFrame:Show()
    copyBox:SetFocus()
    copyBox:HighlightText()
end

-- Export the filtered content of a window (buffer, not just visible lines)
function NS.OpenCopy(index)
    local win = NS.windows[index]
    if not win then return end
    local lines = {}
    NS.BufferEach(function(rec)
        if NS.RecordPasses(rec, win.cfg.filter) then
            NS.FormatRecord(rec) -- ensure plainLower exists before search match
            if NS.RecordMatchesSearch(rec, win.searchText) then
                lines[#lines + 1] = NS.ExportLine(rec)
            end
        end
    end)
    NS.ShowCopyText("Export: " .. win.cfg.name .. " (" .. #lines .. " lines)",
        table.concat(lines, "\n"))
end

-------------------------------------------------------------------------------
-- Capture sessions -> SavedVariables
-------------------------------------------------------------------------------
NS.captureActive = false
local captureLines, captureStart

function NS.CaptureLine(rec)
    captureLines[#captureLines + 1] = NS.ExportLine(rec)
    if #captureLines >= 20000 then
        NS.Print("capture hit 20,000 lines - stopping automatically.")
        NS.CaptureStop()
    end
end

function NS.CaptureStart()
    if NS.captureActive then
        NS.Print("capture already running.")
        return
    end
    captureLines = {}
    captureStart = time()
    NS.captureActive = true
    NS.Print("capture started. All combat log events are being recorded. /ll capture stop to finish.")
end

function NS.CaptureStop()
    if not NS.captureActive then
        NS.Print("no capture running.")
        return
    end
    NS.captureActive = false
    local capture = {
        started = captureStart,
        stopped = time(),
        zone = GetRealZoneText and GetRealZoneText() or "",
        player = NS.playerName,
        count = #captureLines,
        lines = captureLines,
    }
    table.insert(NS.db.captures, capture)
    while #NS.db.captures > 5 do table.remove(NS.db.captures, 1) end
    NS.Print(("capture saved: %d lines (%s). It persists in SavedVariables\\LogLovers.lua after logout/reload."):format(
        capture.count, capture.zone))
    captureLines = nil
end

function NS.ViewCapture(i)
    local cap = NS.db.captures[i]
    if not cap then return end
    NS.ShowCopyText(("Capture %s %s (%d lines)"):format(
        date("%m-%d %H:%M", cap.started), cap.zone or "", cap.count or #cap.lines),
        table.concat(cap.lines, "\n"))
end

function NS.DeleteCapture(i)
    table.remove(NS.db.captures, i)
end

-------------------------------------------------------------------------------
-- Profile import / export (shareable strings)
-------------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function b64encode(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1) ..
            (b and B64:sub(c3 + 1, c3 + 1) or "=") ..
            (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

local B64REV
local function b64decode(data)
    if not B64REV then
        B64REV = {}
        for i = 1, 64 do B64REV[B64:sub(i, i)] = i - 1 end
    end
    data = data:gsub("[^%w%+/=]", "")
    local out = {}
    for i = 1, #data, 4 do
        local c1 = B64REV[data:sub(i, i)]
        local c2 = B64REV[data:sub(i + 1, i + 1)]
        local ch3, ch4 = data:sub(i + 2, i + 2), data:sub(i + 3, i + 3)
        if not c1 or not c2 then return nil end
        local c3 = (ch3 ~= "=" and ch3 ~= "") and B64REV[ch3] or nil
        local c4 = (ch4 ~= "=" and ch4 ~= "") and B64REV[ch4] or nil
        local n = c1 * 262144 + c2 * 4096 + (c3 or 0) * 64 + (c4 or 0)
        out[#out + 1] = string.char(math.floor(n / 65536) % 256)
        if c3 then out[#out + 1] = string.char(math.floor(n / 256) % 256) end
        if c4 then out[#out + 1] = string.char(n % 256) end
    end
    return table.concat(out)
end

local function serialize(v, buf)
    local t = type(v)
    if t == "number" then
        buf[#buf + 1] = tostring(v)
    elseif t == "boolean" then
        buf[#buf + 1] = v and "true" or "false"
    elseif t == "string" then
        buf[#buf + 1] = string.format("%q", v)
    elseif t == "table" then
        buf[#buf + 1] = "{"
        for k, val in pairs(v) do
            local kt = type(k)
            if (kt == "string" or kt == "number" or kt == "boolean")
                and type(val) ~= "function" and type(val) ~= "userdata" then
                buf[#buf + 1] = "["
                serialize(k, buf)
                buf[#buf + 1] = "]="
                serialize(val, buf)
                buf[#buf + 1] = ","
            end
        end
        buf[#buf + 1] = "}"
    else
        buf[#buf + 1] = "nil"
    end
end

local PROFILE_PREFIX = "LOGLOVERS1:"

-------------------------------------------------------------------------------
-- Reading a profile back
--
-- This used to be loadstring() with an empty environment, on the theory that an
-- empty environment is a sandbox. It is not: string methods are still reachable
-- through the string metatable, and neither pcall nor an empty environment stops
-- a loop or a huge allocation - so a pasted profile could hang the client
-- outright. Nothing here executes the data; it is parsed as the small fixed
-- grammar the serializer above emits, and anything else is rejected.
-------------------------------------------------------------------------------
local MAX_PROFILE_BYTES = 512 * 1024
local MAX_DEPTH = 24

local parseValue

local function skipSpace(s, i)
    local _, j = s:find("^[ \t\r\n]*", i)
    return (j or i - 1) + 1
end

local function parseString(s, i)
    -- string.format("%q", ...) output: quotes, with \\ \" \ddd and a
    -- backslash-newline pair standing in for a newline
    local out, n = {}, #s
    i = i + 1
    while i <= n do
        local c = s:sub(i, i)
        if c == '"' then
            return table.concat(out), i + 1
        elseif c == "\\" then
            local nxt = s:sub(i + 1, i + 1)
            if nxt == "" then return nil, "unterminated string" end
            if nxt == "n" then out[#out + 1] = "\n" i = i + 2
            elseif nxt == "r" then out[#out + 1] = "\r" i = i + 2
            elseif nxt == "t" then out[#out + 1] = "\t" i = i + 2
            elseif nxt == "\n" then out[#out + 1] = "\n" i = i + 2
            elseif nxt:match("%d") then
                local digits = s:match("^%d%d?%d?", i + 1)
                out[#out + 1] = string.char(tonumber(digits) % 256)
                i = i + 1 + #digits
            else
                out[#out + 1] = nxt
                i = i + 2
            end
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return nil, "unterminated string"
end

local function parseTable(s, i, depth)
    if depth > MAX_DEPTH then return nil, "profile is nested too deeply" end
    local t = {}
    i = skipSpace(s, i + 1)
    if s:sub(i, i) == "}" then return t, i + 1 end
    while true do
        if s:sub(i, i) ~= "[" then return nil, "expected a key at " .. i end
        local key, err = parseValue(s, i + 1, depth + 1)
        if key == nil then return nil, err end
        i = err                      -- parseValue returns the next index here
        i = skipSpace(s, i)
        if s:sub(i, i) ~= "]" then return nil, "unclosed key at " .. i end
        i = skipSpace(s, i + 1)
        if s:sub(i, i) ~= "=" then return nil, "expected = at " .. i end
        local val, err2 = parseValue(s, i + 1, depth + 1)
        i = err2
        if val == nil and type(i) ~= "number" then return nil, err2 end
        local kt = type(key)
        if kt == "string" or kt == "number" or kt == "boolean" then
            t[key] = val
        end
        i = skipSpace(s, i)
        local c = s:sub(i, i)
        if c == "," then i = skipSpace(s, i + 1)
        elseif c == "}" then return t, i + 1
        else return nil, "expected , or } at " .. i end
        if s:sub(i, i) == "}" then return t, i + 1 end
    end
end

-- returns value, nextIndex  (or nil, errorMessage)
parseValue = function(s, i, depth)
    depth = depth or 0
    i = skipSpace(s, i)
    local c = s:sub(i, i)
    if c == "{" then
        return parseTable(s, i, depth)
    elseif c == '"' then
        return parseString(s, i)
    elseif s:sub(i, i + 3) == "true" then
        return true, i + 4
    elseif s:sub(i, i + 4) == "false" then
        return false, i + 5
    elseif s:sub(i, i + 2) == "nil" then
        -- a nil value is legal in the grammar but carries nothing; report the
        -- index through the second return so the caller can keep going
        return nil, i + 3
    end
    local num = s:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", i)
    if num and num ~= "" and tonumber(num) then
        return tonumber(num), i + #num
    end
    return nil, "unexpected character at " .. i .. ": " .. tostring(s:sub(i, i + 8))
end

function NS.DeserializeProfile(raw)
    if type(raw) ~= "string" or raw == "" then return nil, "empty profile data" end
    if #raw > MAX_PROFILE_BYTES then return nil, "profile is far too large" end
    local v, rest = parseValue(raw, 1, 0)
    if type(v) ~= "table" then
        return nil, type(rest) == "string" and rest or "profile data is not a table"
    end
    return v
end

function NS.ExportProfile()
    local db = NS.db
    local chatCopy = NS.DeepCopy(db.chat)
    chatCopy.historyLines = nil
    if chatCopy.views then
        for _, v in ipairs(chatCopy.views) do v.unread = 0 end
    end
    local profile = {
        v = 1,
        addon = NS.VERSION,
        general = db.general,
        appearance = db.appearance,
        deathRecap = db.deathRecap,
        highlights = db.highlights,
        auraBlock = db.auraBlock,
        windows = db.windows,
        chat = chatCopy,
    }
    local buf = {}
    serialize(profile, buf)
    return PROFILE_PREFIX .. b64encode(table.concat(buf))
end

-- Untrusted data from someone else's game. Every field is type-checked, and
-- nothing touches NS.db until the whole profile has passed - a half-applied
-- profile used to leave the addon erroring on every chat line until /reload.
local function sanitizeHighlights(src)
    local clean = {}
    if type(src) ~= "table" then return clean end
    for k, v in pairs(src) do
        if type(k) == "string" and type(v) == "table" then
            -- the colour is concatenated straight into a |cff escape, so an
            -- unchecked string here lets a shared profile inject working
            -- hyperlinks into every line that spell appears on
            if type(v.color) ~= "string" or not v.color:match("^%x%x%x%x%x%x$") then
                v.color = nil
            end
            if v.soundFile ~= nil and type(v.soundFile) ~= "string" then
                v.soundFile = nil
            end
            if v.soundKey ~= nil and type(v.soundKey) ~= "string" then
                v.soundKey = nil
            end
            clean[string.lower(k)] = v
        end
    end
    return clean
end
NS.SanitizeHighlights = sanitizeHighlights

local function sanitizeWindows(src)
    if type(src) ~= "table" then return nil end
    local clean = {}
    for _, cfg in ipairs(src) do
        if type(cfg) == "table" and type(cfg.filter) == "table" then
            -- profiles shared from before 1.1 have no per-place scopes; carry
            -- their single old setting across rather than leaving a hole
            local f = cfg.filter
            if type(f.scopes) ~= "table" then
                local legacy = f.scope or f.involve
                local everywhere = (legacy == "all" or legacy == "off") and "all"
                    or (legacy == "group" and "group") or "me"
                f.scopes = { world = everywhere, party = everywhere,
                             raid = everywhere, pvp = everywhere, arena = "all" }
                f.scope, f.involve, f.involveAuto, f.involveZones = nil, nil, nil, nil
            end
            clean[#clean + 1] = cfg
        end
    end
    if #clean == 0 then return nil end
    return clean
end

function NS.ImportProfile(text)
    text = (text or ""):gsub("%s+", "")
    if text:sub(1, #PROFILE_PREFIX) ~= PROFILE_PREFIX then
        return false, "not a Log Lovers profile string (missing " .. PROFILE_PREFIX .. " prefix)"
    end
    local raw = b64decode(text:sub(#PROFILE_PREFIX + 1))
    if not raw or raw == "" then return false, "could not decode the string" end

    local profile, err = NS.DeserializeProfile(raw)
    if not profile then return false, err or "corrupted profile data" end
    if profile.v ~= 1 then return false, "profile is from a different format version" end
    for _, key in ipairs({ "general", "appearance" }) do
        if type(profile[key]) ~= "table" then
            return false, "profile is missing its " .. key .. " settings"
        end
    end
    for _, key in ipairs({ "deathRecap", "highlights", "auraBlock", "windows", "chat" }) do
        local v = profile[key]
        if v ~= nil and type(v) ~= "table" then
            return false, "profile has a broken " .. key .. " section"
        end
    end
    local chat = profile.chat
    if chat and chat.views ~= nil and type(chat.views) ~= "table" then
        return false, "profile has a broken chat tab list"
    end

    -- staged: build the whole replacement first, swap only once it is sound
    local keepHistory = (NS.db.chat and NS.db.chat.historyLines) or {}
    local staged = {
        general    = profile.general,
        appearance = profile.appearance,
        deathRecap = profile.deathRecap or NS.db.deathRecap,
        highlights = sanitizeHighlights(profile.highlights),
        auraBlock  = NS.SanitizeAuraBlock(profile.auraBlock),
        windows    = sanitizeWindows(profile.windows) or NS.db.windows,
        chat       = chat or NS.db.chat,
    }
    staged.chat.historyLines = keepHistory

    for k, v in pairs(staged) do NS.db[k] = v end
    NS.MergeDefaults(NS.db, NS.DEFAULTS)
    return true
end

-------------------------------------------------------------------------------
-- Import dialog
-------------------------------------------------------------------------------
local importFrame, importBox

StaticPopupDialogs["LogLovers_RELOAD"] = {
    text = "Profile imported. Reload the UI now to apply it?",
    button1 = "Reload",
    button2 = "Later",
    timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function() ReloadUI() end,
}

function NS.ShowImportDialog()
    if not importFrame then
        importFrame = CreateFrame("Frame", "LogLoversImport", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        importFrame:SetSize(560, 320)
        importFrame:SetPoint("CENTER")
        importFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        importFrame:SetMovable(true)
        importFrame:EnableMouse(true)
        importFrame:RegisterForDrag("LeftButton")
        importFrame:SetScript("OnDragStart", importFrame.StartMoving)
        importFrame:SetScript("OnDragStop", importFrame.StopMovingOrSizing)
        importFrame:SetClampedToScreen(true)
        NS.SkinPanel(importFrame, { r = 0.055, g = 0.043, b = 0.028, a = 0.97 })
        tinsert(UISpecialFrames, "LogLoversImport")

        local title = importFrame:CreateFontString(nil, "OVERLAY")
        title:SetFont(NS.CurrentFont(), 14, "")
        title:SetPoint("TOPLEFT", 12, -10)
        title:SetText(NS.C("Import profile", NS.COLORS.accent))

        local hint = importFrame:CreateFontString(nil, "OVERLAY")
        hint:SetFont(NS.CurrentFont(), 10, "")
        hint:SetPoint("TOPLEFT", 12, -28)
        hint:SetText(NS.C("Paste a LOGLOVERS1: profile string below, then click Import. Your chat history stays; everything else is replaced.", NS.COLORS.dim))

        local close = NS.MakeIconButton(importFrame, "Interface\\Buttons\\UI-StopButton", nil,
            function() importFrame:Hide() end)
        close:SetPoint("TOPRIGHT", -8, -8)

        local scroll = CreateFrame("ScrollFrame", "LogLoversImportScroll", importFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 10, -46)
        scroll:SetPoint("BOTTOMRIGHT", -30, 40)
        importBox = CreateFrame("EditBox", nil, scroll)
        importBox:SetMultiLine(true)
        importBox:SetFontObject(ChatFontNormal)
        importBox:SetWidth(500)
        importBox:SetAutoFocus(false)
        importBox:SetScript("OnEscapePressed", function() importFrame:Hide() end)
        scroll:SetScrollChild(importBox)

        local doImport = CreateFrame("Button", nil, importFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
        NS.SkinPanel(doImport, { r = 0.16, g = 0.11, b = 0.05, a = 0.92 }, { r = 0.52, g = 0.37, b = 0.14, a = 0.95 })
        doImport:SetSize(120, 22)
        doImport:SetPoint("BOTTOMRIGHT", -12, 10)
        local dt = doImport:CreateFontString(nil, "OVERLAY")
        dt:SetFont(NS.CurrentFont(), 12, "")
        dt:SetPoint("CENTER")
        dt:SetText(NS.C("Import", NS.COLORS.accent))
        doImport:SetScript("OnClick", function()
            local safe, ok, err = pcall(NS.ImportProfile, importBox:GetText())
            if not safe then ok, err = false, "profile data could not be read" end
            if ok then
                importFrame:Hide()
                NS.Print("profile imported.")
                StaticPopup_Show("LogLovers_RELOAD")
            else
                NS.Print("import failed: " .. tostring(err))
            end
        end)
    end
    importBox:SetText("")
    importFrame:Show()
    importBox:SetFocus()
end
