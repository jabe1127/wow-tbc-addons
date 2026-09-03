-- LogLovers Core: initialization, ring buffer, segments, slash commands
local ADDON, NS = ...
_G.LogLovers = NS

NS.callbacks = {}          -- named hook lists
function NS.On(event, fn)
    NS.callbacks[event] = NS.callbacks[event] or {}
    table.insert(NS.callbacks[event], fn)
end
function NS.Fire(event, ...)
    local list = NS.callbacks[event]
    if not list then return end
    for _, fn in ipairs(list) do fn(...) end
end

-------------------------------------------------------------------------------
-- Ring buffer of normalized event records
-------------------------------------------------------------------------------
local buf, bufMax, writeIdx, count = {}, 6000, 0, 0

function NS.BufferPush(rec)
    writeIdx = writeIdx % bufMax + 1
    buf[writeIdx] = rec
    if count < bufMax then count = count + 1 end
end

-- Iterate oldest -> newest. fn(rec) returning true stops iteration.
function NS.BufferEach(fn)
    if count == 0 then return end
    local start = (writeIdx - count) % bufMax + 1
    for i = 0, count - 1 do
        local idx = (start + i - 1) % bufMax + 1
        local rec = buf[idx]
        if rec and fn(rec) then return end
    end
end

function NS.BufferCount() return count end

function NS.BufferResize(newMax)
    newMax = math.max(500, math.min(20000, newMax or 6000))
    local tmp = {}
    NS.BufferEach(function(rec) tmp[#tmp + 1] = rec end)
    buf, writeIdx, count = {}, 0, 0
    bufMax = newMax
    local first = math.max(1, #tmp - newMax + 1)
    for i = first, #tmp do
        writeIdx = writeIdx % bufMax + 1
        buf[writeIdx] = tmp[i]
        if count < bufMax then count = count + 1 end
    end
end

function NS.BufferClear()
    buf, writeIdx, count = {}, 0, 0
    collectgarbage("step", 200)
end

-------------------------------------------------------------------------------
-- Combat segments
-------------------------------------------------------------------------------
NS.segments = {}   -- { { index, label, startTime, endTime } ... } newest last
NS.currentSegment = nil
local segCounter = 0

local function startSegment()
    segCounter = segCounter + 1
    NS.currentSegment = {
        index = segCounter,
        -- Cross-addon identity. time() has one-second resolution, so two trash
        -- pulls in the same second share a startStamp; the counter makes it
        -- unique, and the stamp makes it meaningful to another addon.
        id = time() .. "-" .. segCounter,
        label = nil,             -- set to first hostile NPC damaged
        startTime = GetTime(),
        startStamp = time(),
        zone = GetRealZoneText and GetRealZoneText() or "",
    }
    table.insert(NS.segments, NS.currentSegment)
    while #NS.segments > 15 do table.remove(NS.segments, 1) end
    NS.Fire("SEGMENT_START", NS.currentSegment)
end

local function endSegment()
    if NS.currentSegment then
        NS.currentSegment.endTime = GetTime()
        NS.Fire("SEGMENT_END", NS.currentSegment)
    end
    NS.currentSegment = nil
end

function NS.SegmentLabel(seg)
    if not seg then return "Overall" end
    local label = seg.label or seg.zone or "Combat"
    return string.format("#%d %s (%s)", seg.index, label, date("%H:%M", seg.startStamp))
end

-------------------------------------------------------------------------------
-- Event frame
-------------------------------------------------------------------------------
local f = CreateFrame("Frame")
NS.eventFrame = f
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")

local function onCombatLog()
    NS.HandleCLEU(CombatLogGetCurrentEventInfo())
end

f:SetScript("OnEvent", function(self, event, arg1)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        onCombatLog()
    elseif event == "PLAYER_REGEN_DISABLED" then
        startSegment()
    elseif event == "PLAYER_REGEN_ENABLED" then
        endSegment()
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        if NS.UpdateZoneContext then NS.UpdateZoneContext() end
    elseif event == "UNIT_PET" then
        if arg1 == "player" then NS.petGUID = UnitGUID("pet") end
    elseif event == "ADDON_LOADED" and arg1 == ADDON then
        LogLoversDB = LogLoversDB or {}
        NS.db = NS.MergeDefaults(LogLoversDB, NS.DEFAULTS)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        -- 1.0 visual refresh: adopt the icon-matched palette once
        if (NS.db.themeVersion or 0) < 1 then
            NS.db.themeVersion = 1
            local ap, dap = NS.db.appearance, NS.DEFAULTS.appearance
            for _, key in ipairs({ "bg", "border", "titleBg" }) do
                ap[key] = NS.DeepCopy(dap[key])
            end
        end

        -- 1.1: the combat log defaults to you and your pet, both directions.
        -- Showing the whole zone was never a useful default.
        if (NS.db.defaultsVersion or 0) < 3 then
            NS.db.defaultsVersion = 3
            -- source/target role grids are gone; make sure no window is still
            -- silently filtering by a role the user can no longer see or fix
            local function allRoles(t)
                if not t then return end
                for _, role in ipairs(NS.ROLE_LIST) do t[role.key] = true end
            end
            local function sane(f)
                if not f then return end
                -- carry any old single-value setting into the per-location model
                local legacy = f.scope or f.involve
                local everywhere = (legacy == "all" or legacy == "off") and "all"
                    or (legacy == "group" and "group") or "me"
                f.scopes = f.scopes or {
                    world = everywhere, party = everywhere, raid = everywhere,
                    pvp = everywhere, arena = "all",
                }
                if legacy == "out" or legacy == "in" then f.direction = legacy end
                f.direction = f.direction or "both"
                f.scope, f.involve, f.involveAuto, f.involveZones = nil, nil, nil, nil
                allRoles(f.sources)
                allRoles(f.targets)
            end
            for _, cfg in ipairs(NS.db.windows or {}) do sane(cfg.filter) end
            if NS.db.chat and NS.db.chat.views then
                for _, v in ipairs(NS.db.chat.views) do
                    if v.kind == "combat" then sane(v.combatFilter) end
                end
            end
        end

        -- 1.12: the death recap timeline is a dropdown now, and the two memory
        -- sliders are gone. Snap anything the new UI cannot represent, so what
        -- it shows is what is actually in force.
        if (NS.db.defaultsVersion or 0) < 4 then
            NS.db.defaultsVersion = 4
            local dr = NS.db.deathRecap
            local secs = dr.seconds or 12
            if secs <= 20 then dr.seconds = 12
            elseif secs <= 45 then dr.seconds = 30
            else dr.seconds = 60 end
            dr.maxEvents = NS.DEFAULTS.deathRecap.maxEvents
            dr.maxDeaths = NS.DEFAULTS.deathRecap.maxDeaths
        end

        -- SavedVariables can hold anything a shared profile put there, and a
        -- stray value in either of these errors the combat log on every
        -- matching event. Cheap to re-check, impossible to fix in-game if not.
        NS.db.highlights = NS.SanitizeHighlights(NS.db.highlights)
        NS.db.auraBlock = NS.SanitizeAuraBlock(NS.db.auraBlock)

        NS.playerGUID = UnitGUID("player")
        NS.playerName = UnitName("player")
        NS.petGUID = UnitGUID("pet")
        NS.BufferResize(NS.db.general.bufferSize)
        if #NS.db.windows == 0 then
            table.insert(NS.db.windows, NS.DefaultWindow("Combat", "everything"))
        end
        NS.InitWindows()
        -- clear out hidden combat windows left behind by earlier docking, which
        -- used to show up as phantom "popped out" entries in the window picker
        if NS.PruneHiddenWindows then pcall(NS.PruneHiddenWindows) end
        NS.InitBlizzLogOption()
        -- death recaps carried over from the last session
        if NS.RestoreDeaths then pcall(NS.RestoreDeaths) end
        -- The chat module is on for everybody by default, but "/ll chat off"
        -- has to survive the reload it asks for: the failure path below tells
        -- people to use it as an escape hatch, and forcing it back on here
        -- meant that advice was a lie.
        if NS.db.chat.enabled ~= false then NS.db.chat.enabled = true end
        if NS.db.chat.enabled then NS.db.chat.hideBlizzard = true end
        NS.db.chat.whisperBar = true
        NS.db.chat.history = true

        if NS.CHAT then
            -- a chat-module failure must never take the combat log down
            local ok, err = pcall(NS.CHAT.Init)
            if not ok then
                NS.Print("chat module failed to load: " .. tostring(err))
                NS.Print("combat log windows still work. /ll chat off, then /reload, to run without chat.")
            elseif not NS.db.chat.enabled then
                NS.Print("chat module is OFF (Blizzard chat active). " ..
                    NS.C("/ll chat on", NS.COLORS.accent) .. " re-enables it.")
            end
        end
        self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:RegisterEvent("UNIT_PET")
        self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        if NS.UpdateZoneContext then NS.UpdateZoneContext() end
        if NS.RegisterBlizzOptions then pcall(NS.RegisterBlizzOptions) end
        if NS.db.general.minimapHint then
            NS.Print("loaded. Type " .. NS.C("/ll", NS.COLORS.accent) ..
                " for options, " .. NS.C("/ll help", NS.COLORS.accent) .. " for commands.")
        end
    end
end)

-------------------------------------------------------------------------------
-- Hide Blizzard combat log tab (optional)
-------------------------------------------------------------------------------
function NS.InitBlizzLogOption()
    if not NS.db.general.hideBlizzLog then return end
    local tab = _G["ChatFrame2Tab"]
    if tab and _G.ChatFrame2 and _G.ChatFrame2.name == COMBAT_LOG then
        tab:Hide()
        tab.llHidden = true
        if not tab.llHooked then
            tab.llHooked = true
            hooksecurefunc(tab, "Show", function(t)
                if t.llHidden and NS.db.general.hideBlizzLog then t:Hide() end
            end)
        end
    end
end

function NS.SetBlizzLogHidden(hidden)
    NS.db.general.hideBlizzLog = hidden
    local tab = _G["ChatFrame2Tab"]
    if not tab then return end
    if hidden then
        NS.InitBlizzLogOption()
    else
        tab.llHidden = nil
        tab:Show()
    end
end

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------
SLASH_LogLovers1 = "/ll"
SLASH_LogLovers2 = "/loglovers"
SlashCmdList["LogLovers"] = function(msg)
    local raw = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    msg = string.lower(string.trim and string.trim(msg) or raw)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    -- buff names keep the case the user typed, so the options list reads right
    local _, rawRest = raw:match("^(%S*)%s*(.-)$")
    if cmd == "" or cmd == "options" or cmd == "config" then
        NS.ToggleOptions()
    elseif cmd == "help" then
        NS.Print("commands:")
        local lines = {
            "/ll - open options",
            "/ll new - create a new window",
            "/ll chat - show/hide the chat window",
            "/ll me - toggle 'only my events' on every combat view",
            "/ll aoe - AoE farming mode: show kills only",
            "/ll chat on | off - enable/disable the whole chat module",
            "/ll lock | unlock - lock/unlock all windows",
            "/ll clear - clear all window text",
            "/ll search - toggle search bar on main window",
            "/ll stats - open the stats browser",
            "/ll deaths - open the death recap browser",
            "/ll copy - open copy/export for the main window",
            "/ll hidebuff <name> - never show that buff/debuff again",
            "/ll showbuff <name> - undo it (no name = list what is hidden)",
            "/ll capture start | stop - record events to SavedVariables",
            "/ll profile export | import - share or load a full settings profile",
            "/ll wipe - clear the event buffer",
            "/ll reset - reset window positions",
        }
        for _, l in ipairs(lines) do
            DEFAULT_CHAT_FRAME:AddMessage("   " .. NS.C(l, NS.COLORS.dim))
        end
    elseif cmd == "new" then
        NS.CreateWindowInteractive()
    elseif cmd == "me" then
        local on
        local function flip(f)
            if on == nil then on = (NS.EffectiveScope(f) == "all") end
            f.scopes = f.scopes or {}
            for _, loc in ipairs(NS.LOCATIONS) do
                f.scopes[loc.key] = on and "me" or "all"
            end
        end
        for _, cfg in ipairs(NS.db.windows) do flip(cfg.filter) end
        if NS.db.chat and NS.db.chat.views then
            for _, v in ipairs(NS.db.chat.views) do
                if v.kind == "combat" and v.combatFilter then flip(v.combatFilter) end
            end
        end
        NS.RefreshAllWindows()
        if NS.RefreshChat then NS.RefreshChat() end
        NS.Print(on and "combat log: just me, everywhere."
            or "combat log: everyone, everywhere.")
    elseif cmd == "aoe" then
        local on
        local function flip(f)
            if on == nil then on = not f.aoeFarm end
            f.aoeFarm = on
        end
        for _, cfg in ipairs(NS.db.windows or {}) do flip(cfg.filter) end
        if NS.db.chat and NS.db.chat.views then
            for _, v in ipairs(NS.db.chat.views) do
                if v.kind == "combat" and v.combatFilter then flip(v.combatFilter) end
            end
        end
        NS.RefreshAllWindows()
        if NS.RefreshChat then NS.RefreshChat() end
        NS.Print(on and "AoE farming mode ON - kills only."
            or "AoE farming mode off.")
    elseif cmd == "hidebuff" or cmd == "hideaura" then
        if rawRest == "" then
            NS.Print("usage: /ll hidebuff Sayge's Dark Fortune of Damage")
        elseif NS.HideAura(rawRest) then
            NS.Print("hiding " .. rawRest .. " in every combat window.")
        end
    elseif cmd == "showbuff" or cmd == "showaura" then
        if rawRest == "" then
            local hidden = NS.HiddenAuraList()
            if #hidden == 0 then
                NS.Print("no buffs or debuffs are hidden.")
            else
                NS.Print("hidden buffs and debuffs:")
                for _, a in ipairs(hidden) do
                    DEFAULT_CHAT_FRAME:AddMessage("   " .. NS.C(a.name, NS.COLORS.buff))
                end
            end
        elseif NS.AuraHidden(rawRest) then
            -- echo the name as it was stored, not the case that was typed
            local shown = rawRest
            for _, a in ipairs(NS.HiddenAuraList()) do
                if a.key == string.lower(rawRest) then shown = a.name end
            end
            NS.ShowAura(rawRest)
            NS.Print(shown .. " is visible again.")
        else
            NS.Print("that one was not hidden. /ll showbuff lists the hidden ones.")
        end
    elseif cmd == "chat" then
        if rest == "on" then
            NS.db.chat.enabled = true
            NS.Print("chat module enabled - /reload to apply.")
        elseif rest == "off" then
            NS.db.chat.enabled = false
            NS.Print("chat module disabled - /reload to apply.")
        else
            NS.ToggleChatWindow()
        end
    elseif cmd == "lock" then
        NS.SetAllLocked(true); NS.Print("windows locked.")
    elseif cmd == "unlock" then
        NS.SetAllLocked(false); NS.Print("windows unlocked.")
    elseif cmd == "clear" then
        NS.ClearAllWindows()
    elseif cmd == "search" then
        NS.ToggleSearch(1)
    elseif cmd == "stats" then
        NS.ToggleStats()
    elseif cmd == "deaths" then
        NS.ToggleDeaths()
    elseif cmd == "copy" then
        NS.OpenCopy(1)
    elseif cmd == "profile" then
        if rest == "export" then
            NS.ShowCopyText("Log Lovers profile (Ctrl+C to copy, share anywhere)", NS.ExportProfile())
        elseif rest == "import" then
            NS.ShowImportDialog()
        else
            NS.Print("usage: /ll profile export | import")
        end
    elseif cmd == "capture" then
        if rest == "start" then NS.CaptureStart()
        elseif rest == "stop" then NS.CaptureStop()
        else NS.Print("usage: /ll capture start | stop") end
    elseif cmd == "wipe" then
        NS.BufferClear()
        NS.RefreshAllWindows()
        NS.Print("event buffer wiped.")
    elseif cmd == "reset" then
        NS.ResetWindowPositions()
    else
        NS.Print("unknown command. /ll help")
    end
end
