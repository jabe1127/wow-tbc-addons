-- LogLovers Players: what we know about the people we run into
--
-- Classic and TBC have no API for another player's professions, level, guild
-- or history - GetProfessions and friends only ever answer about you. So this
-- module is an observer, not a database: everything here was either seen
-- happening (a Smelting cast, a whisper, a trade) or asked for explicitly
-- (a /who lookup). It never claims to know more than it watched.
local ADDON, NS = ...

local C = NS.C
local PLAYERS = {}
NS.PLAYERS = PLAYERS

-------------------------------------------------------------------------------
-- Profession detection
--
-- Every one of these is a cast that appears in the combat log, so seeing one
-- from a player is proof they have that profession. Gathering and the "open a
-- node" casts are the reliable ones; crafting mostly casts under the crafted
-- item's own name, which we cannot map without a full recipe table.
-------------------------------------------------------------------------------
local CAST_PROFESSION = {
    ["mining"]              = "Mining",
    ["smelting"]            = "Mining",
    ["herb gathering"]      = "Herbalism",
    ["skinning"]            = "Skinning",
    ["disenchant"]          = "Enchanting",
    ["fishing"]             = "Fishing",
    ["cooking"]             = "Cooking",
    ["basic campfire"]      = "Cooking",
    ["alchemy"]             = "Alchemy",
    ["blacksmithing"]       = "Blacksmithing",
    ["enchanting"]          = "Enchanting",
    ["engineering"]         = "Engineering",
    ["jewelcrafting"]       = "Jewelcrafting",
    ["leatherworking"]      = "Leatherworking",
    ["tailoring"]           = "Tailoring",
    ["first aid"]           = "First Aid",
    ["lockpicking"]         = "Lockpicking",
    ["pick lock"]           = "Lockpicking",
    ["prospecting"]         = "Jewelcrafting",
    ["runeforging"]         = "Runeforging",
}

-- Substring fallbacks: crafted items cast under their own name, and a few of
-- those names are unambiguous enough to be worth catching.
local CAST_PATTERNS = {
    { "bandage", "First Aid" },
    { "smelt",   "Mining" },
}

-- Profession links (|Htrade:spellID:skill:max:...|h[Alchemy]|h) are the only
-- exact source we get, and they carry the player's real skill level. Matching
-- the bracketed name in the same pattern keeps skill and profession paired,
-- and reads correctly on non-English clients.
local TRADE_LINK = "|Htrade:%d+:(%d+):[^|]*|h%[(.-)%]|h"

-------------------------------------------------------------------------------
-- Storage
-------------------------------------------------------------------------------
local MAX_CASUAL = 400   -- players we only ever watched, pruned oldest-first
local seqCounter = 0     -- arrival order, to break same-second ties when pruning

local function key(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    -- "Bob-Realm" and "Bob" are the same person on a single-realm client
    local short = name:match("^([^%-]+)") or name
    return string.lower(short), short
end

-- A player is "kept" once you have actually dealt with them, or spent a /who
-- on them. Everyone else is casual observation and gets pruned as the table
-- grows - the cache should never cost you something you asked for.
--
-- Sharing a raid is the weakest of these: a nightly 25-man plus battlegrounds
-- promotes dozens of near-strangers a day and they used to stay forever. If
-- grouping is ALL you ever did with someone, that expires; a note, a whisper, a
-- trade or a /who is a deliberate act and never does.
local GROUP_ONLY_TTL = 60 * 24 * 60 * 60   -- 60 days
local MAX_KEPT = 1500

local function keptDeliberately(p)
    return (p.note and p.note ~= "")
        or (p.whisperIn or 0) > 0 or (p.whisperOut or 0) > 0
        or (p.trades or 0) > 0
        or p.whoAt ~= nil
end

local function isKept(p, now)
    if keptDeliberately(p) then return true end
    if (p.groups or 0) > 0 then
        now = now or time()
        return (now - (p.lastSeen or 0)) < GROUP_ONLY_TTL
    end
    return false
end

-- Runs BEFORE a new record is inserted, so it can never evict the record we
-- are about to hand back to the caller.
local function prune(headroom)
    local db = NS.db.players
    if not db then return end
    local now = time()
    local casual, kept = {}, {}
    for k, p in pairs(db) do
        local entry = { k = k, at = p.lastSeen or 0, n = p.seq or 0 }
        if isKept(p, now) then kept[#kept + 1] = entry
        else casual[#casual + 1] = entry end
    end
    -- seq breaks ties: a whole crowd seen within the same second still evicts
    -- in the order it arrived rather than at random
    local function oldestFirst(a, b)
        if a.at ~= b.at then return a.at < b.at end
        return a.n < b.n
    end
    local limit = MAX_CASUAL - (headroom or 0)
    if #casual > limit then
        table.sort(casual, oldestFirst)
        for i = 1, #casual - limit do db[casual[i].k] = nil end
    end
    -- a backstop on the kept side too, so the file can never grow without end
    if #kept > MAX_KEPT then
        table.sort(kept, oldestFirst)
        local drop = #kept - MAX_KEPT
        for i = 1, #kept do
            if drop <= 0 then break end
            local p = db[kept[i].k]
            -- never drop somebody you wrote a note about
            if p and (not p.note or p.note == "") then
                db[kept[i].k] = nil
                drop = drop - 1
            end
        end
    end
end

-- Pruning walks and sorts the whole cache, so doing it on every insert is
-- quadratic when records arrive in a burst. Amortise it: the cache is allowed
-- to drift a little over the cap between sweeps.
local PRUNE_EVERY = 64
local pruneCountdown = 0

local function maybePrune()
    if pruneCountdown > 0 then
        pruneCountdown = pruneCountdown - 1
        return
    end
    pruneCountdown = PRUNE_EVERY
    prune(PRUNE_EVERY + 1)
end

local function tracking()
    return NS.db and NS.db.general and NS.db.general.trackPlayers
end
PLAYERS.Tracking = tracking

-- Creates a record no matter what the tracking switch says. Only for things
-- the user explicitly asked for: a note, a /who they clicked.
local function ensure(name)
    local k, short = key(name)
    if not k then return nil end
    NS.db.players = NS.db.players or {}
    local p = NS.db.players[k]
    if not p then
        maybePrune()
        seqCounter = seqCounter + 1
        p = { name = short, firstSeen = time(), lastSeen = time(),
              seq = seqCounter, professions = {} }
        NS.db.players[k] = p
    end
    p.name = p.name or short
    p.professions = p.professions or {}
    p.lastSeen = p.lastSeen or time()
    return p
end

-- Every passive observer goes through here, so the tracking switch is enforced
-- in exactly one place instead of at a dozen call sites.
local function record(name)
    if not tracking() then return nil end
    return ensure(name)
end

function PLAYERS.Get(name, create)
    if create then return ensure(name) end
    local k = key(name)
    if not k or not NS.db.players then return nil end
    local p = NS.db.players[k]
    if p then p.professions = p.professions or {} end
    return p
end

local function touch(name)
    local p = record(name)
    if p then p.lastSeen = time() end
    return p
end
PLAYERS.Touch = touch

function PLAYERS.ForgetAll()
    local n = 0
    for _ in pairs(NS.db.players or {}) do n = n + 1 end
    NS.db.players = {}
    return n
end

function PLAYERS.Count()
    local total, kept = 0, 0
    for _, p in pairs(NS.db.players or {}) do
        total = total + 1
        if isKept(p) then kept = kept + 1 end
    end
    return total, kept
end

function PLAYERS.Forget(name)
    local k = key(name)
    if not k or not NS.db.players then return false end
    if not NS.db.players[k] then return false end
    NS.db.players[k] = nil
    return true
end

-- Explicit user action, so it works even with passive tracking switched off.
function PLAYERS.SetNote(name, text)
    local p = ensure(name)
    if not p then return false end
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    p.note = text ~= "" and text or nil
    return true
end

-------------------------------------------------------------------------------
-- Professions
-------------------------------------------------------------------------------
-- src: "cast" (seen doing it) or "link" (they linked it, so we know the skill)
function PLAYERS.NoteProfession(name, prof, skill, src)
    if not prof then return end
    local p = record(name)
    if not p then return end
    local prev = p.professions[prof]
    -- a linked profession is authoritative and must never be downgraded by a
    -- later cast sighting
    if prev and prev.src == "link" and src ~= "link" then
        prev.at = time()
        return
    end
    p.professions[prof] = { skill = skill or (prev and prev.skill), at = time(), src = src or "cast" }
    p.lastSeen = time()
end

-- Called from the combat log for every cast by a player who is not you.
function PLAYERS.ObserveCast(name, spellLower)
    if not name or not spellLower then return end
    local prof = CAST_PROFESSION[spellLower]
    if not prof then
        for _, pat in ipairs(CAST_PATTERNS) do
            if spellLower:find(pat[1], 1, true) then prof = pat[2] break end
        end
    end
    if prof then PLAYERS.NoteProfession(name, prof, nil, "cast") end
end

-- Called for every chat message; picks profession links out of the text. Each
-- link carries its own skill level, so they are read as pairs - a message with
-- two professions in it must not give both the first one's number.
function PLAYERS.ObserveMessage(name, text)
    if not name or not text or not text:find("|Htrade:", 1, true) then return end
    for skill, prof in text:gmatch(TRADE_LINK) do
        prof = prof:gsub("^%s+", ""):gsub("%s+$", "")
        if prof ~= "" then
            PLAYERS.NoteProfession(name, prof, tonumber(skill), "link")
        end
    end
end

function PLAYERS.ProfessionList(p)
    local out = {}
    for prof, info in pairs((p and p.professions) or {}) do
        out[#out + 1] = { name = prof, skill = info.skill, src = info.src, at = info.at }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-------------------------------------------------------------------------------
-- Whispers, groups, trades
-------------------------------------------------------------------------------
function PLAYERS.NoteWhisper(name, text, outgoing)
    local p = touch(name)
    if not p then return end
    if outgoing then
        p.whisperOut = (p.whisperOut or 0) + 1
    else
        p.whisperIn = (p.whisperIn or 0) + 1
    end
    p.lastWhisperAt = time()
    p.lastWhisperOut = outgoing and true or nil
    if text and text ~= "" then
        -- strip escapes first: cutting a |cff.. or |Hitem:..|h in half would
        -- put a broken escape into the menu FontString
        local plain = NS.StripEscapes and NS.StripEscapes(text) or text
        p.lastWhisper = string.sub(plain, 1, 120)
    end
end

-- Group members are counted once per stint together, not once per roster
-- update, or standing in a raid for an hour would say you grouped 200 times.
local inGroupWith = {}

function PLAYERS.ScanGroup()
    local n = (GetNumGroupMembers and GetNumGroupMembers())
        or ((GetNumRaidMembers and GetNumRaidMembers() or 0) > 0
            and GetNumRaidMembers() or ((GetNumPartyMembers and GetNumPartyMembers() or 0) + 1))
        or 0
    local seen = {}
    local isRaid = (IsInRaid and IsInRaid()) or ((GetNumRaidMembers and GetNumRaidMembers() or 0) > 0)
    local prefix = isRaid and "raid" or "party"
    local count = isRaid and n or (n - 1)
    for i = 1, math.max(count, 0) do
        local unit = prefix .. i
        local uname = UnitName and UnitName(unit)
        if uname and uname ~= NS.playerName then
            local k = key(uname)
            if k then
                seen[k] = true
                if not inGroupWith[k] then
                    inGroupWith[k] = true
                    local p = touch(uname)
                    if p then
                        -- inGroupWith is session-local, so a /reload mid-raid
                        -- would otherwise count everyone again
                        local recent = p.lastGroupAt and (time() - p.lastGroupAt) < 900
                        if not recent then p.groups = (p.groups or 0) + 1 end
                        p.lastGroupAt = time()
                    end
                end
            end
        end
    end
    for k in pairs(inGroupWith) do
        if not seen[k] then inGroupWith[k] = nil end
    end
end

-- Trades: the window exposes both sides, so we can record what changed hands.
local tradeName, tradeGave, tradeGot, tradeMoneyGave, tradeMoneyGot
local tradeDone, tradeCancelled

-- Slots 1-6 change hands. Slot 7 is the "will not be traded" slot (enchants,
-- lockboxes) on both sides and must never be counted as given or received.
local TRADE_SLOTS = 6

local function snapshotTrade()
    tradeGave, tradeGot = {}, {}
    for i = 1, TRADE_SLOTS do
        local link = GetTradePlayerItemLink and GetTradePlayerItemLink(i)
        if link then tradeGave[#tradeGave + 1] = link end
        local tlink = GetTradeTargetItemLink and GetTradeTargetItemLink(i)
        if tlink then tradeGot[#tradeGot + 1] = tlink end
    end
    tradeMoneyGave = (GetPlayerTradeMoney and GetPlayerTradeMoney()) or 0
    tradeMoneyGot = (GetTargetTradeMoney and GetTargetTradeMoney()) or 0
end

function PLAYERS.TradeOpened()
    tradeName = (UnitName and UnitName("NPC")) or nil
    tradeDone, tradeCancelled = nil, nil
    snapshotTrade()
end

function PLAYERS.TradeChanged()
    if tradeName then snapshotTrade() end
end

function PLAYERS.TradeCancelled()
    tradeCancelled = true
end

-- Only called when the client confirms the trade actually completed.
function PLAYERS.TradeCompleted()
    if not tradeName or tradeDone then return end
    tradeDone = true
    local p = touch(tradeName)
    if p then
        p.trades = (p.trades or 0) + 1
        p.lastTradeAt = time()
        p.lastTradeGave = (tradeGave and #tradeGave > 0) and tradeGave or nil
        p.lastTradeGot = (tradeGot and #tradeGot > 0) and tradeGot or nil
        p.lastTradeMoneyGave = (tradeMoneyGave or 0) > 0 and tradeMoneyGave or nil
        p.lastTradeMoneyGot = (tradeMoneyGot or 0) > 0 and tradeMoneyGot or nil
    end
end

-- The window closing is the backstop signal. A cancelled trade always fires
-- TRADE_REQUEST_CANCEL first, so anything that closes without one went through
-- even if the client never printed the "Trade complete" message.
function PLAYERS.TradeClosed()
    if tradeName and not tradeCancelled and not tradeDone then
        PLAYERS.TradeCompleted()
    end
    tradeName, tradeDone, tradeCancelled = nil, nil, nil
end

-------------------------------------------------------------------------------
-- /who lookups
--
-- The server throttles these hard, so one at a time with a cooldown, and the
-- result is cached. SetWhoToUI keeps the answer out of the chat frame.
-------------------------------------------------------------------------------
local whoPending, whoSentAt, whoRestore = nil, 0, nil
local WHO_COOLDOWN = 5

-- 2.5.x moved this into C_FriendList and renamed the trailing I to i. Without
-- it the results print into the chat frame, which is the whole thing we are
-- trying to avoid.
local function whoToUI(on)
    local fn = (C_FriendList and C_FriendList.SetWhoToUi) or SetWhoToUI
    if not fn then return false end
    local ok = pcall(fn, on and true or false)
    if not ok then ok = pcall(fn, on and 1 or 0) end
    return ok
end

-- Routing results to the UI is what makes them readable in code, but it is also
-- what pops the Who window open: Blizzard's FriendsFrame listens for
-- WHO_LIST_UPDATE and shows itself. Take the event away from it for the couple
-- of seconds our lookup is in flight, and the window never appears. Our own
-- frame keeps its registration, so we still get the results.
local WHO_UI_FRAMES = { "FriendsFrame", "WhoFrame", "WhoListScrollFrame" }
local whoSuppressed = nil
local whoFrameWasShown = false
local whoSuppressTimer = nil

local function restoreWhoUI()
    if whoSuppressTimer then
        pcall(whoSuppressTimer.Cancel, whoSuppressTimer)
        whoSuppressTimer = nil
    end
    if not whoSuppressed then return end
    for _, f in ipairs(whoSuppressed) do
        pcall(f.RegisterEvent, f, "WHO_LIST_UPDATE")
    end
    whoSuppressed = nil
    -- if something opened it anyway, put it back the way we found it
    local ff = _G.FriendsFrame
    if ff and not whoFrameWasShown and ff.IsShown and ff:IsShown() then
        pcall(ff.Hide, ff)
    end
end
PLAYERS.RestoreWhoUI = restoreWhoUI

local function suppressWhoUI()
    if whoSuppressed then return end
    whoSuppressed = {}
    local ff = _G.FriendsFrame
    whoFrameWasShown = (ff and ff.IsShown and ff:IsShown()) and true or false
    for _, n in ipairs(WHO_UI_FRAMES) do
        local f = _G[n]
        if f and f.UnregisterEvent then
            local registered = true
            if f.IsEventRegistered then
                local ok, r = pcall(f.IsEventRegistered, f, "WHO_LIST_UPDATE")
                registered = ok and r and true or false
            end
            if registered then
                pcall(f.UnregisterEvent, f, "WHO_LIST_UPDATE")
                whoSuppressed[#whoSuppressed + 1] = f
            end
        end
    end
    -- a lookup that never comes back must not leave the Who window deaf
    if C_Timer and C_Timer.NewTimer then
        whoSuppressTimer = C_Timer.NewTimer(8, restoreWhoUI)
    end
end

function PLAYERS.WhoAge(p)
    if not p or not p.whoAt then return nil end
    return time() - p.whoAt
end

function PLAYERS.RequestWho(name, onDone)
    local k, short = key(name)
    if not k then return false, "no name" end
    local now = time()
    if whoPending and (now - whoSentAt) < WHO_COOLDOWN then
        return false, "a lookup is already running - try again in a moment"
    end
    if not (C_FriendList and C_FriendList.SendWho) and not SendWho then
        return false, "this client has no /who API"
    end

    whoPending, whoSentAt = k, now
    PLAYERS.whoCallback = onDone

    suppressWhoUI()
    whoRestore = whoToUI(true) or nil
    local query = 'n-"' .. short .. '"'
    if C_FriendList and C_FriendList.SendWho then
        pcall(C_FriendList.SendWho, query)
    else
        pcall(SendWho, query)
    end
    return true
end

-- Levels are baked into cached chat lines, so learning one has to invalidate
-- the format cache or old lines keep showing no level forever.
local function levelsChanged()
    if not NS.db.chat or not NS.db.chat.showLevels then return end
    if NS.InvalidateFormats then NS.InvalidateFormats() end
    if NS.RefreshChat then NS.RefreshChat() end
end

local function readWhoResults()
    local rows = {}
    local num = 0
    if C_FriendList and C_FriendList.GetNumWhoResults then
        num = C_FriendList.GetNumWhoResults() or 0
    elseif GetNumWhoResults then
        num = GetNumWhoResults() or 0
    end
    for i = 1, num do
        local wname, guild, level, race, class, zone
        if C_FriendList and C_FriendList.GetWhoInfo then
            local info = C_FriendList.GetWhoInfo(i)
            if info then
                wname, guild, level, race, class, zone =
                    info.fullName, info.fullGuildName, info.level, info.raceStr,
                    info.classStr, info.area
            end
        elseif GetWhoInfo then
            wname, guild, level, race, class, zone = GetWhoInfo(i)
        end
        if wname then
            rows[#rows + 1] = {
                name = wname, guild = (guild ~= "" and guild) or nil,
                level = level, race = race, class = class,
                zone = (zone ~= "" and zone) or nil,
            }
            -- The name the user actually clicked is recorded whatever the
            -- tracking switch says, since they asked for it. Any extra rows
            -- the server threw in are only kept if tracking is on.
            local k = key(wname)
            local p = (k == whoPending) and ensure(wname) or record(wname)
            if p then
                p.level = level
                p.race = race
                p.class = class
                p.guild = (guild ~= "" and guild) or nil
                p.zone = (zone ~= "" and zone) or nil
                p.whoAt = time()
                p.lastSeen = time()
            end
        end
    end
    if num > 0 then levelsChanged() end
    return num, rows
end

function PLAYERS.WhoListUpdate()
    if not whoPending then return end
    local found, rows = readWhoResults()
    -- Only hand the routing back if the Who window was closed when we started.
    -- If the user had it open, it wants results going to the UI and it is not
    -- ours to switch off.
    if whoRestore and not whoFrameWasShown then
        whoToUI(false)
    end
    whoRestore = nil
    restoreWhoUI()
    local cb, k = PLAYERS.whoCallback, whoPending
    whoPending, PLAYERS.whoCallback = nil, nil
    if cb then cb(NS.db.players and NS.db.players[k], found, rows) end
end

-------------------------------------------------------------------------------
-- Guild members: free, accurate, and no server round trip
-------------------------------------------------------------------------------
-- Guild members are NOT imported into the saved player cache.
--
-- They used to be, and it was a mistake: GUILD_ROSTER_UPDATE fires every time
-- anyone in the guild logs in or out, so a 500-member guild meant 500 record
-- creations - each one walking and sorting the whole cache - plus a full chat
-- re-render, several times a minute. That is the login/logout stutter.
--
-- Instead the roster is read into one small runtime-only index, rebuilt at most
-- once every 30 seconds and only when the roster has actually changed.
local guildIndex = {}      -- [lowered name] = { level, class, zone, rank, note }
local guildName = nil
local guildDirty, guildBuiltAt, guildIndexN = true, 0, -1

local GUILD_REBUILD_EVERY = 10

-- The roster event itself does nothing but set a flag - a guildmate logging in
-- must cost nothing. The index is rebuilt lazily, the first time something
-- actually asks about a guild member and at most once every few seconds.
local function rebuildGuildIndex()
    if not GetNumGuildMembers or not GetGuildRosterInfo then return end
    guildDirty, guildBuiltAt = false, time()

    local n = GetNumGuildMembers() or 0
    guildIndexN = n
    local fresh, levelsMoved = {}, false
    for i = 1, n do
        local gname, rank, _, level, class, zone, note = GetGuildRosterInfo(i)
        if gname then
            local k = key(gname)
            if k then
                fresh[k] = {
                    level = level, class = class, rank = rank,
                    zone = (zone and zone ~= "") and zone or nil,
                    note = (note and note ~= "") and note or nil,
                }
                -- Only a CHANGED level is worth re-rendering chat for. Someone
                -- logging in or out does not move anybody's level, and forcing
                -- a re-format of the whole buffer for that was the stutter.
                local old = guildIndex[k]
                if old and old.level ~= level then levelsMoved = true end
            end
        end
    end
    guildIndex = fresh
    guildName = (GetGuildInfo and GetGuildInfo("player")) or guildName
    if levelsMoved then levelsChanged() end
end

local function ensureGuildIndex()
    if not guildDirty then return end
    -- A changed member count means someone really did come or go, so the index
    -- is stale now, not in ten seconds. One cheap call decides it.
    local n = (GetNumGuildMembers and GetNumGuildMembers()) or 0
    if n ~= guildIndexN then rebuildGuildIndex() return end
    if guildBuiltAt > 0 and (time() - guildBuiltAt) < GUILD_REBUILD_EVERY then return end
    rebuildGuildIndex()
end

function PLAYERS.GuildRosterChanged()
    guildDirty = true
end

function PLAYERS.RebuildGuildIndex()
    guildDirty = true
    guildBuiltAt = 0
    rebuildGuildIndex()
end

-- What the roster says about one person, or nil. Never touches the cache.
function PLAYERS.GuildInfo(name)
    local k = key(name)
    if not k then return nil end
    ensureGuildIndex()
    local g = guildIndex[k]
    if not g then return nil end
    return g, guildName
end

function PLAYERS.KnownLevel(name)
    local k = key(name)
    if not k then return nil end
    local p = NS.db.players and NS.db.players[k]
    if p and p.level and p.level > 0 then return p.level end
    ensureGuildIndex()
    local g = guildIndex[k]
    if g and g.level and g.level > 0 then return g.level end
    return nil
end

-------------------------------------------------------------------------------
-- The info block shown at the top of a player menu
-------------------------------------------------------------------------------
local function ago(t)
    if not t then return nil end
    local d = time() - t
    if d < 60 then return "just now" end
    if d < 3600 then return math.floor(d / 60) .. "m ago" end
    if d < 86400 then return math.floor(d / 3600) .. "h ago" end
    return math.floor(d / 86400) .. "d ago"
end
PLAYERS.Ago = ago

local function money(copper)
    if not copper or copper <= 0 then return nil end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 and g == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end
PLAYERS.Money = money

-- Returns an array of { text = , hex = } lines. Empty when we know nothing,
-- so the menu can skip the block entirely rather than showing "unknown".
function PLAYERS.InfoLines(name)
    local p = PLAYERS.Get(name, false)
    local lines = {}
    local dim, txt = NS.COLORS.dim, NS.COLORS.text
    -- guild details come straight off the roster, so a guildmate has an info
    -- block even if you have never interacted with them
    local g, gName = PLAYERS.GuildInfo(name)
    if not p and not g then return lines end
    p = p or {}

    -- identity
    local id = {}
    local level = p.level or (g and g.level)
    if level then id[#id + 1] = "Level " .. level end
    if p.race then id[#id + 1] = p.race end
    if p.class or (g and g.class) then id[#id + 1] = p.class or g.class end
    if #id > 0 then
        lines[#lines + 1] = { text = table.concat(id, " "), hex = txt, kind = "who" }
    end

    local guild = (g and gName) or p.guild
    if guild then
        local line = "<" .. guild .. ">"
        local rank = (g and g.rank) or p.guildRank
        if rank and rank ~= "" then line = line .. "  " .. rank end
        lines[#lines + 1] = { text = line, hex = NS.COLORS.accentDim, kind = "who" }
    end
    local note = (g and g.note) or p.guildNote
    if note then
        lines[#lines + 1] = { text = "Guild note: " .. note, hex = dim, kind = "guildnote" }
    end

    local zone = p.zone or (g and g.zone)
    if zone then
        local age = PLAYERS.WhoAge(p)
        local stamp = (p.zone and age and age > 300) and ("  (" .. ago(p.whoAt) .. ")") or ""
        lines[#lines + 1] = { text = "In " .. zone .. stamp, hex = dim, kind = "who" }
    end

    -- professions, always labelled as observed rather than looked up
    local profs = PLAYERS.ProfessionList(p)
    if #profs > 0 then
        local parts = {}
        for _, pr in ipairs(profs) do
            parts[#parts + 1] = pr.skill and (pr.name .. " " .. pr.skill) or pr.name
        end
        lines[#lines + 1] = { text = "Seen using: " .. table.concat(parts, ", "),
                              hex = NS.COLORS.pet }
    end

    -- history with you
    if (p.whisperIn or 0) + (p.whisperOut or 0) > 0 then
        local total = (p.whisperIn or 0) + (p.whisperOut or 0)
        lines[#lines + 1] = { text = total .. " whisper" .. (total == 1 and "" or "s") ..
            (p.lastWhisperAt and ("  last " .. ago(p.lastWhisperAt)) or ""), hex = dim }
        if p.lastWhisper then
            local arrow = p.lastWhisperOut and "you: " or ""
            lines[#lines + 1] = { text = '  "' .. arrow .. p.lastWhisper .. '"', hex = dim }
        end
    end
    if (p.groups or 0) > 0 then
        lines[#lines + 1] = { text = "Grouped " .. p.groups .. "x" ..
            (p.lastGroupAt and ("  last " .. ago(p.lastGroupAt)) or ""), hex = dim }
    end
    if (p.trades or 0) > 0 then
        lines[#lines + 1] = { text = "Traded " .. p.trades .. "x" ..
            (p.lastTradeAt and ("  last " .. ago(p.lastTradeAt)) or ""), hex = dim }
        local gave = p.lastTradeGave and #p.lastTradeGave or 0
        local got = p.lastTradeGot and #p.lastTradeGot or 0
        local mGave, mGot = money(p.lastTradeMoneyGave), money(p.lastTradeMoneyGot)
        local bits = {}
        if gave > 0 then bits[#bits + 1] = "gave " .. gave .. " item" .. (gave == 1 and "" or "s") end
        if mGave then bits[#bits + 1] = "gave " .. mGave end
        if got > 0 then bits[#bits + 1] = "got " .. got .. " item" .. (got == 1 and "" or "s") end
        if mGot then bits[#bits + 1] = "got " .. mGot end
        if #bits > 0 then
            lines[#lines + 1] = { text = "  last trade: " .. table.concat(bits, ", "), hex = dim }
        end
    end

    if p.note then
        lines[#lines + 1] = { text = "Note: " .. p.note, hex = NS.COLORS.accent }
    end
    return lines
end

-------------------------------------------------------------------------------
-- Shift-click a name: the answer, in chat
--
-- Exactly what typing /who prints, because that is the thing everybody already
-- knows how to read:
--
--   [Lampart]: Level 66 Undead Warrior <M O B> - Zangarmarsh
--   1 player total
--
-- Results are routed away from Blizzard's Who window and rendered here instead,
-- so no window opens and there is nothing else to click. The client's own
-- format strings are used when they exist, so this stays right in every locale.
-------------------------------------------------------------------------------
local WHO_GUILD_FALLBACK = "[%s]: Level %d %s %s <%s> - %s"
local WHO_PLAIN_FALLBACK = "[%s]: Level %d %s %s - %s"
local WHO_TOTAL_FALLBACK = "%d player total"

local function shortName(name)
    return (name or ""):match("^([^%-]+)") or name or "?"
end

-- Blizzard prints /who results in the system colour.
local function systemHex()
    local info = ChatTypeInfo and ChatTypeInfo.SYSTEM
    if info and NS.RGBToHex then return NS.RGBToHex(info.r, info.g, info.b) end
    return "ffff00"
end

local function whoRowText(row)
    local level = tonumber(row.level) or 0
    local race = row.race or ""
    local class = row.class or ""
    local zone = row.zone or ""
    local fmt, args
    if row.guild and row.guild ~= "" then
        fmt = _G.WHO_LIST_GUILD_FORMAT or WHO_GUILD_FALLBACK
        args = { row.name, level, race, class, row.guild, zone }
    else
        fmt = _G.WHO_LIST_FORMAT or WHO_PLAIN_FALLBACK
        args = { row.name, level, race, class, zone }
    end
    -- a locale whose format string takes different arguments must not error the
    -- click; fall back to the shape we know
    local ok, out = pcall(string.format, fmt, unpack(args))
    if not ok then
        if row.guild and row.guild ~= "" then
            out = string.format(WHO_GUILD_FALLBACK, row.name, level, race, class, row.guild, zone)
        else
            out = string.format(WHO_PLAIN_FALLBACK, row.name, level, race, class, zone)
        end
    end
    return out
end

local function whoTotalText(n)
    local fmt = (n == 1 and _G.WHO_NUM_RESULTS) or _G.WHO_NUM_RESULTS_PLURAL
        or _G.WHO_NUM_RESULTS or WHO_TOTAL_FALLBACK
    local ok, out = pcall(string.format, fmt, n)
    if not ok then
        out = n .. (n == 1 and " player total" or " players total")
    end
    return out
end

-- Prints one /who answer, exactly as the game would have.
function PLAYERS.PrintWho(rows)
    local hex = systemHex()
    rows = rows or {}
    for _, row in ipairs(rows) do
        NS.PrintRaw(NS.C(whoRowText(row), hex))
    end
    NS.PrintRaw(NS.C(whoTotalText(#rows), hex))
end

-- Everything we know but never looked up, from an existing record. Used when a
-- lookup cannot be run right now, so a shift-click is never a no-op.
function PLAYERS.PrintKnown(name, why)
    local hex = systemHex()
    local disp = shortName(name)
    local lines = PLAYERS.InfoLines(name)
    local who = {}
    for _, l in ipairs(lines) do
        if l.kind == "who" then who[#who + 1] = l.text end
    end
    if #who > 0 then
        NS.PrintRaw(NS.C("[" .. disp .. "]: " .. table.concat(who, " "), hex) ..
            (why and NS.C("  (" .. why .. ")", NS.COLORS.dim) or ""))
    else
        NS.Print(disp .. (why and (" - " .. why) or " - nothing known about them yet."))
    end
end

-- Runs the lookup and prints the answer.
function PLAYERS.LookupToChat(name)
    local sent = PLAYERS.RequestWho(name, function(_, found, rows)
        PLAYERS.PrintWho(rows)
    end)
    if not sent then
        -- another lookup is still in flight, or this client has no /who API
        PLAYERS.PrintKnown(name, "another lookup is still running")
    end
    return true
end

-- The trade item links of the last trade, for the "what did we trade" popup.
function PLAYERS.LastTradeText(name)
    local p = PLAYERS.Get(name, false)
    if not p or not p.lastTradeAt then return nil end
    local out = { "Last trade with " .. (p.name or name) .. " - " .. date("%c", p.lastTradeAt), "" }
    out[#out + 1] = "You gave:"
    for _, l in ipairs(p.lastTradeGave or {}) do out[#out + 1] = "   " .. NS.StripEscapes(l) end
    if p.lastTradeMoneyGave then out[#out + 1] = "   " .. money(p.lastTradeMoneyGave) end
    if #out == 3 then out[#out + 1] = "   (nothing)" end
    out[#out + 1] = ""
    out[#out + 1] = "You got:"
    local mark = #out
    for _, l in ipairs(p.lastTradeGot or {}) do out[#out + 1] = "   " .. NS.StripEscapes(l) end
    if p.lastTradeMoneyGot then out[#out + 1] = "   " .. money(p.lastTradeMoneyGot) end
    if #out == mark then out[#out + 1] = "   (nothing)" end
    return table.concat(out, "\n")
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event, arg1, arg2)
    if not NS.db then return end
    if event == "PLAYER_LOGIN" then
        for _, ev in ipairs({
            "GROUP_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE",
            "TRADE_SHOW", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED",
            "TRADE_MONEY_CHANGED", "TRADE_ACCEPT_UPDATE", "TRADE_CLOSED",
            "TRADE_REQUEST_CANCEL", "WHO_LIST_UPDATE", "UI_INFO_MESSAGE",
            "GUILD_ROSTER_UPDATE",
        }) do
            pcall(self.RegisterEvent, self, ev)
        end
        pcall(PLAYERS.ScanGroup)
        -- GUILD_ROSTER_UPDATE only fires when something asks for the roster,
        -- and nothing else in this addon ever does
        if GuildRoster then pcall(GuildRoster) end
        if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
        PLAYERS.GuildRosterChanged()
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED"
        or event == "RAID_ROSTER_UPDATE" then
        pcall(PLAYERS.ScanGroup)
    elseif event == "GUILD_ROSTER_UPDATE" then
        -- one assignment; the rebuild happens lazily when something asks
        PLAYERS.GuildRosterChanged()
    elseif event == "TRADE_SHOW" then
        pcall(PLAYERS.TradeOpened)
    elseif event == "TRADE_PLAYER_ITEM_CHANGED" or event == "TRADE_TARGET_ITEM_CHANGED"
        or event == "TRADE_MONEY_CHANGED" or event == "TRADE_ACCEPT_UPDATE" then
        pcall(PLAYERS.TradeChanged)
    elseif event == "UI_INFO_MESSAGE" then
        -- 2.5.x sends (messageType, message); older clients sent just the
        -- message, so check both slots rather than guessing
        if ERR_TRADE_COMPLETE
            and (arg1 == ERR_TRADE_COMPLETE or arg2 == ERR_TRADE_COMPLETE) then
            pcall(PLAYERS.TradeCompleted)
        end
    elseif event == "TRADE_REQUEST_CANCEL" then
        pcall(PLAYERS.TradeCancelled)
    elseif event == "TRADE_CLOSED" then
        pcall(PLAYERS.TradeClosed)
    elseif event == "WHO_LIST_UPDATE" then
        pcall(PLAYERS.WhoListUpdate)
    end
end)
