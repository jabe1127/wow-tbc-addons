-- LogLovers Chat: full chat capture, formatting, history, and view filters
local ADDON, NS = ...

local C = NS.C
local CHAT = {}
NS.CHAT = CHAT

-------------------------------------------------------------------------------
-- Chat types
-------------------------------------------------------------------------------
-- key -> { event suffix(es), label, short tag, full tag, group }
CHAT.TYPES = {
    { key = "SAY",              label = "Say",            short = "S",   full = "Say",            group = "player" },
    { key = "YELL",             label = "Yell",           short = "Y",   full = "Yell",           group = "player" },
    { key = "EMOTE",            label = "Emotes",         short = "E",   full = "Emote",          group = "player" },
    { key = "WHISPER",          label = "Whispers",       short = "W",   full = "Whisper",        group = "player" },
    { key = "PARTY",            label = "Party",          short = "P",   full = "Party",          group = "player" },
    { key = "RAID",             label = "Raid",           short = "R",   full = "Raid",           group = "player" },
    { key = "RAID_WARNING",     label = "Raid warning",   short = "RW",  full = "Raid Warning",   group = "player" },
    { key = "BATTLEGROUND",     label = "Battleground",   short = "BG",  full = "Battleground",   group = "player" },
    { key = "GUILD",            label = "Guild",          short = "G",   full = "Guild",          group = "player" },
    { key = "OFFICER",          label = "Officer",        short = "O",   full = "Officer",        group = "player" },
    { key = "CHANNEL",          label = "Numbered channels", short = "#", full = "Channel",       group = "channel" },
    { key = "SYSTEM",           label = "System",         short = "Sys", full = "System",         group = "info" },
    { key = "LOOT",             label = "Loot",           short = "L",   full = "Loot",           group = "info" },
    { key = "MONEY",            label = "Money",          short = "$",   full = "Money",          group = "info" },
    { key = "XP",               label = "XP / Honor",     short = "XP",  full = "XP",             group = "info" },
    { key = "SKILL",            label = "Skill-ups",      short = "Sk",  full = "Skill",          group = "info" },
    { key = "TRADESKILL",       label = "Professions (item creations)", short = "Prof", full = "Profession", group = "info" },
    { key = "FACTION",          label = "Reputation",     short = "Rep", full = "Reputation",     group = "info" },
    { key = "ADDON",            label = "Addon messages", short = "A",   full = "Addon",          group = "info" },
    { key = "NPC",              label = "NPC dialogue",   short = "NPC", full = "NPC",            group = "npc" },
    { key = "BOSS",             label = "Boss emotes",    short = "B",   full = "Boss",           group = "npc" },
}

-- event -> { type key, color key override }
local EVENT_MAP = {
    CHAT_MSG_SAY                = { "SAY", "SAY" },
    CHAT_MSG_YELL               = { "YELL", "YELL" },
    CHAT_MSG_EMOTE              = { "EMOTE", "EMOTE" },
    CHAT_MSG_TEXT_EMOTE         = { "EMOTE", "EMOTE" },
    CHAT_MSG_WHISPER            = { "WHISPER", "WHISPER" },
    CHAT_MSG_WHISPER_INFORM     = { "WHISPER", "WHISPER_INFORM" },
    CHAT_MSG_BN_WHISPER         = { "WHISPER", "BN_WHISPER" },
    CHAT_MSG_BN_WHISPER_INFORM  = { "WHISPER", "BN_WHISPER_INFORM" },
    CHAT_MSG_PARTY              = { "PARTY", "PARTY" },
    CHAT_MSG_PARTY_LEADER       = { "PARTY", "PARTY_LEADER" },
    CHAT_MSG_RAID               = { "RAID", "RAID" },
    CHAT_MSG_RAID_LEADER        = { "RAID", "RAID_LEADER" },
    CHAT_MSG_RAID_WARNING       = { "RAID_WARNING", "RAID_WARNING" },
    CHAT_MSG_BATTLEGROUND       = { "BATTLEGROUND", "BATTLEGROUND" },
    CHAT_MSG_BATTLEGROUND_LEADER= { "BATTLEGROUND", "BATTLEGROUND_LEADER" },
    CHAT_MSG_GUILD              = { "GUILD", "GUILD" },
    CHAT_MSG_OFFICER            = { "OFFICER", "OFFICER" },
    CHAT_MSG_CHANNEL            = { "CHANNEL", "CHANNEL" },
    CHAT_MSG_SYSTEM             = { "SYSTEM", "SYSTEM" },
    CHAT_MSG_AFK                = { "WHISPER", "AFK" },
    CHAT_MSG_DND                = { "WHISPER", "DND" },
    CHAT_MSG_IGNORED            = { "SYSTEM", "IGNORED" },
    CHAT_MSG_CHANNEL_NOTICE     = { "SYSTEM", "CHANNEL" },
    CHAT_MSG_LOOT               = { "LOOT", "LOOT" },
    CHAT_MSG_MONEY              = { "MONEY", "MONEY" },
    CHAT_MSG_COMBAT_XP_GAIN     = { "XP", "COMBAT_XP_GAIN" },
    CHAT_MSG_COMBAT_HONOR_GAIN  = { "XP", "COMBAT_HONOR_GAIN" },
    CHAT_MSG_COMBAT_FACTION_CHANGE = { "FACTION", "COMBAT_FACTION_CHANGE" },
    CHAT_MSG_SKILL              = { "SKILL", "SKILL" },
    CHAT_MSG_TRADESKILLS        = { "TRADESKILL", "TRADESKILLS" },
    CHAT_MSG_OPENING            = { "SKILL", "OPENING" },
    CHAT_MSG_PET_INFO           = { "SKILL", "PET_INFO" },
    CHAT_MSG_BG_SYSTEM_NEUTRAL  = { "SYSTEM", "BG_SYSTEM_NEUTRAL" },
    CHAT_MSG_BG_SYSTEM_ALLIANCE = { "SYSTEM", "BG_SYSTEM_ALLIANCE" },
    CHAT_MSG_BG_SYSTEM_HORDE    = { "SYSTEM", "BG_SYSTEM_HORDE" },
    CHAT_MSG_MONSTER_SAY        = { "NPC", "MONSTER_SAY" },
    CHAT_MSG_MONSTER_YELL       = { "NPC", "MONSTER_YELL" },
    CHAT_MSG_MONSTER_EMOTE      = { "NPC", "MONSTER_EMOTE" },
    CHAT_MSG_MONSTER_WHISPER    = { "NPC", "MONSTER_WHISPER" },
    CHAT_MSG_RAID_BOSS_EMOTE    = { "BOSS", "RAID_BOSS_EMOTE" },
    CHAT_MSG_RAID_BOSS_WHISPER  = { "BOSS", "RAID_BOSS_WHISPER" },
}

local SHORT_TAG, FULL_TAG = {}, {}
for _, t in ipairs(CHAT.TYPES) do
    SHORT_TAG[t.key] = t.short
    FULL_TAG[t.key] = t.full
end

-- color-key specific tag overrides
local COLORKEY_TAG = {
    PARTY_LEADER = { "PL", "Party Leader" },
    RAID_LEADER = { "RL", "Raid Leader" },
    BATTLEGROUND_LEADER = { "BGL", "BG Leader" },
    RAID_WARNING = { "RW", "Raid Warning" },
}

function CHAT.DefaultFilter(preset)
    local f = { types = {}, channelsAll = true, channelNames = {} }
    local function on(...)
        for _, k in ipairs({ ... }) do f.types[k] = true end
    end
    if preset == "all" then
        for _, t in ipairs(CHAT.TYPES) do f.types[t.key] = true end
    elseif preset == "general" then
        on("SAY", "YELL", "EMOTE", "WHISPER", "PARTY", "RAID", "RAID_WARNING",
            "BATTLEGROUND", "GUILD", "OFFICER", "CHANNEL", "SYSTEM", "NPC", "BOSS", "ADDON")
    elseif preset == "whispers" then
        on("WHISPER")
        f.channelsAll = false
    elseif preset == "guild" then
        on("GUILD", "OFFICER")
        f.channelsAll = false
    elseif preset == "loot" then
        on("LOOT", "MONEY", "XP", "SKILL", "TRADESKILL", "FACTION", "SYSTEM")
        f.channelsAll = false
    elseif preset == "trade" then
        f.types.CHANNEL = true
        f.channelsAll = false
        f.channelNames = { trade = true, lookingforgroup = true }
    else
        for _, t in ipairs(CHAT.TYPES) do f.types[t.key] = true end
    end
    return f
end

CHAT.VIEW_PRESETS = {
    { key = "all",      label = "Everything" },
    { key = "general",  label = "General (no loot spam)" },
    { key = "whispers", label = "Whispers" },
    { key = "guild",    label = "Guild" },
    { key = "loot",     label = "Loot & info" },
    { key = "trade",    label = "Trade / LFG" },
}

function CHAT.StripName(name)
    if not name then return "" end
    return string.lower(name:match("^([^%-]+)") or name)
end

function CHAT.Passes(d, f)
    -- per-person whisper conversation view
    if f.whisperWith then
        return d.type == "WHISPER" and CHAT.StripName(d.author) == f.whisperWith
    end
    if not f.types[d.type] then return false end
    if d.type == "CHANNEL" and not f.channelsAll then
        -- restricted to an explicit list of channel names
        local base = string.lower(d.chanBase or "")
        base = base:gsub("%s+", "")
        if not f.channelNames[base] then return false end
    end
    return true
end

-------------------------------------------------------------------------------
-- Server channel management (join / leave / enumerate)
-------------------------------------------------------------------------------
function CHAT.JoinedChannels()
    local out = {}
    local list = { GetChannelList() }
    -- 2.5.x returns triplets: id, name, disabled
    for i = 1, #list, 3 do
        local id, name = list[i], list[i + 1]
        if type(id) == "number" and type(name) == "string" then
            out[#out + 1] = { id = id, name = name }
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function CHAT.ServerChannels()
    local out = {}
    if EnumerateServerChannels then
        local list = { EnumerateServerChannels() }
        for _, name in ipairs(list) do
            if type(name) == "string" then out[#out + 1] = name end
        end
    end
    return out
end


function CHAT.JoinChannel(name)
    if not name or name == "" then return end
    JoinPermanentChannel(name, nil, 1)
    NS.Print("joined channel \"" .. name .. "\".")
end

function CHAT.LeaveChannel(name)
    if not name or name == "" then return end
    LeaveChannelByName(name)
    NS.Print("left channel \"" .. name .. "\".")
end

-------------------------------------------------------------------------------
-- Buffer (wrappers around persisted plain-data records)
-------------------------------------------------------------------------------
local buffer = {}         -- array of { d = savedRecord, line, plain, gen }
local MAXBUF = 2000

local function pushWrapper(d)
    local w = { d = d }
    buffer[#buffer + 1] = w
    if #buffer > MAXBUF then table.remove(buffer, 1) end
    return w
end

function CHAT.Each(fn)
    for i = 1, #buffer do
        if fn(buffer[i]) then return end
    end
end

function CHAT.Clear()
    wipe(buffer)
    -- wipe the saved copy whether or not history is currently switched on, or
    -- turning it back on resurrects everything you just cleared
    if NS.db.chat.historyLines then wipe(NS.db.chat.historyLines) end
end

-------------------------------------------------------------------------------
-- Formatting
-------------------------------------------------------------------------------
local URL_PATTERNS = {
    "%f[%S]https?://[^%s|]+",
    "%f[%S]www%.[%w_%-]+%.[^%s|]+",
}

local function linkifyURLs(text)
    if not NS.db.chat.urls then return text end
    if text:find("|H", 1, true) then return text end -- don't touch messages with links
    for _, pat in ipairs(URL_PATTERNS) do
        text = text:gsub("(" .. pat .. ")", function(url)
            return "|Hllurl:" .. url .. "|h" .. C("[" .. url .. "]", "4db8ff") .. "|h"
        end)
    end
    return text
end

local function typeColor(colorKey)
    local info = ChatTypeInfo and (ChatTypeInfo[colorKey] or ChatTypeInfo.SYSTEM)
    if info then return NS.RGBToHex(info.r, info.g, info.b) end
    return "ffffff"
end

-- resolves the display color for a message, honoring user overrides
local function msgColor(d)
    local colors = NS.db.chat.colors
    if d.type == "CHANNEL" and d.chanBase then
        local key = string.lower(d.chanBase):gsub("%s+", "")
        if colors.channels[key] then return colors.channels[key] end
    end
    if colors.types[d.type] then return colors.types[d.type] end
    return typeColor(d.colorKey or d.type)
end

-- exposed for the options color list (default shown when no override)
function CHAT.DefaultTypeColor(typeKey)
    -- map type keys to a representative Blizzard color key
    local rep = {
        XP = "COMBAT_XP_GAIN", FACTION = "COMBAT_FACTION_CHANGE",
        SKILL = "SKILL", TRADESKILL = "TRADESKILLS",
        NPC = "MONSTER_SAY", BOSS = "RAID_BOSS_EMOTE",
        ADDON = "SYSTEM",
    }
    return typeColor(rep[typeKey] or typeKey)
end

function CHAT.DefaultChannelColor()
    return typeColor("CHANNEL")
end

-------------------------------------------------------------------------------
-- Escape-safe word highlighting
--
-- A formatted chat line is full of |cffXXXXXX, |Hlink|h...|h and |Ttexture|t.
-- Dropping a colour code into the middle of any of those produces a malformed
-- escape, which at best renders as garbage and at worst errors the client - so
-- the line is split into escapes and visible text first, and only the visible
-- text is ever searched.
-------------------------------------------------------------------------------
local function splitEscapes(s)
    local out, i, n, plainStart = {}, 1, #s, 1
    while i <= n do
        if s:sub(i, i) == "|" then
            local c, stop = s:sub(i + 1, i + 1), nil
            if c == "c" then
                stop = i + 9                      -- |cAARRGGBB
            elseif c == "r" or c == "n" or c == "|" then
                stop = i + 1
            elseif c == "H" then
                -- whole hyperlink, payload and display text together
                local a = s:find("|h", i + 2, true)
                if a then
                    local b = s:find("|h", a + 2, true)
                    stop = (b and b + 1) or (a + 1)
                end
            elseif c == "T" then
                local a = s:find("|t", i + 2, true)
                stop = a and a + 1
            end
            if stop and stop <= n then
                if i > plainStart then
                    out[#out + 1] = { text = s:sub(plainStart, i - 1) }
                end
                out[#out + 1] = { text = s:sub(i, stop), escape = true }
                i = stop + 1
                plainStart = i
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end
    if plainStart <= n then out[#out + 1] = { text = s:sub(plainStart) } end
    return out
end
CHAT.SplitEscapes = splitEscapes

function CHAT.HighlightWord(body, word, hex)
    if not body or not word or word == "" then return body end
    local needle = string.lower(word)
    local pieces = splitEscapes(body)
    local lastColor, changed = "", false

    for _, p in ipairs(pieces) do
        if p.escape then
            -- remember the colour in force, so re-opening it after a |r keeps
            -- the rest of the line its original colour
            if p.text:sub(1, 2) == "|c" then lastColor = p.text
            elseif p.text == "|r" then lastColor = "" end
        else
            local lower = string.lower(p.text)
            local out, from = {}, 1
            local s, e = lower:find(needle, 1, true)
            while s do
                out[#out + 1] = p.text:sub(from, s - 1)
                out[#out + 1] = C(p.text:sub(s, e), hex) .. lastColor
                from = e + 1
                s, e = lower:find(needle, e + 1, true)
            end
            if #out > 0 then
                out[#out + 1] = p.text:sub(from)
                p.text = table.concat(out)
                changed = true
            end
        end
    end
    if not changed then return body end

    local parts = {}
    for i, p in ipairs(pieces) do parts[i] = p.text end
    return table.concat(parts)
end

local function playerLink(name, guid, fallbackHex)
    if not name or name == "" then return "" end
    local disp = name:match("^([^%-]+)") or name
    local hex
    if guid and guid ~= "" then
        local _, class = GetPlayerInfoByGUID(guid)
        if class and RAID_CLASS_COLORS[class] then
            local cc = RAID_CLASS_COLORS[class]
            hex = NS.RGBToHex(cc.r, cc.g, cc.b)
        end
    end
    hex = hex or fallbackHex or NS.COLORS.text
    -- level, but only when we genuinely know it - never a guessed or blank [ ]
    local lvl = ""
    if NS.db.chat.showLevels and NS.PLAYERS then
        local known = NS.PLAYERS.KnownLevel(name)
        if known then lvl = C("[" .. known .. "]", NS.COLORS.dim) end
    end
    return lvl .. "|Hllp:" .. name .. "|h" .. C(disp, hex) .. "|h"
end

local function tagFor(d, hex)
    local shortMode = NS.db.chat.shortTags
    local tag
    if d.type == "CHANNEL" then
        if shortMode then
            tag = tostring(d.chanIdx or "#")
        else
            tag = (d.chanIdx and (d.chanIdx .. ". ") or "") .. (d.chanBase or "Channel")
        end
    else
        local override = COLORKEY_TAG[d.colorKey]
        if override then
            tag = shortMode and override[1] or override[2]
        else
            tag = shortMode and SHORT_TAG[d.type] or FULL_TAG[d.type]
        end
    end
    if not tag then return "" end
    return C("[" .. tag .. "]", hex) .. " "
end

local function chatTimestamp(d)
    local mode = NS.db.general.timestampMode
    if mode == "none" then return "" end
    return C(date("%H:%M ", d.t), NS.COLORS.timestamp)
end

function CHAT.FormatWrapper(w)
    if w.line and w.gen == NS.formatGen then return w.line end
    local d = w.d
    local hex = msgColor(d)
    local ts = chatTimestamp(d)
    local body

    local flags = ""
    if d.flags and d.flags ~= "" then
        flags = C("<" .. d.flags .. "> ", NS.COLORS.death)
    end
    local lang = ""
    if d.lang and d.lang ~= "" and d.lang ~= (GetDefaultLanguage and GetDefaultLanguage("player")) then
        lang = C("[" .. d.lang .. "] ", NS.COLORS.dim)
    end

    -- {rt1}/{skull}/... -> raid target textures, before anything else runs, so
    -- the URL linkifier and the alert highlighter both see them as escapes
    local text = linkifyURLs(NS.ReplaceIconTokens(d.text or ""))

    if d.type == "SYSTEM" or d.type == "LOOT" or d.type == "MONEY" or d.type == "XP"
        or d.type == "SKILL" or d.type == "TRADESKILL" or d.type == "FACTION" or d.type == "ADDON" then
        if d.type == "ADDON" then
            body = text -- already colored by the addon that printed it
        else
            body = C(text, hex)
        end
    elseif d.type == "NPC" or d.type == "BOSS" then
        local t = text
        local hadToken = t:find("%%s") ~= nil
        if hadToken then
            local safeName = (d.author or ""):gsub("%%", "%%%%")
            t = t:gsub("%%s", safeName)
        end
        local prefix = ""
        if d.colorKey == "MONSTER_SAY" then prefix = (d.author or "?") .. " says: "
        elseif d.colorKey == "MONSTER_YELL" then prefix = (d.author or "?") .. " yells: "
        elseif d.colorKey == "MONSTER_WHISPER" or d.colorKey == "RAID_BOSS_WHISPER" then
            prefix = (d.author or "?") .. " whispers: "
        elseif d.colorKey == "MONSTER_EMOTE" or d.colorKey == "RAID_BOSS_EMOTE" then
            -- emote text usually embeds the name via %s; only prepend if it didn't
            if not hadToken then prefix = (d.author or "") .. " " end
        end
        body = C(prefix .. t, hex)
    elseif d.colorKey == "EMOTE" and d.textEmote then
        body = C(text, hex)
    elseif d.colorKey == "EMOTE" then
        body = playerLink(d.author, d.guid, hex) .. C(" " .. text, hex)
    else
        local tag = tagFor(d, hex)
        local isBN = d.colorKey and d.colorKey:find("^BN_") ~= nil
        local who
        if isBN then
            -- Battle.net names aren't valid /w targets; plain colored text
            who = C(d.author or "?", hex)
        else
            who = playerLink(d.author, d.guid, hex)
        end
        local sep = C(": ", hex)
        local pop = ""
        if d.type == "WHISPER" and d.author and d.author ~= "" then
            -- inline pop-out: click to give this conversation its own window
            pop = "|Hllpop:" .. d.author .. "|h" .. C("[+]", NS.COLORS.accent) .. "|h "
        end
        if d.colorKey == "WHISPER" or d.colorKey == "BN_WHISPER"
            or d.colorKey == "AFK" or d.colorKey == "DND" then
            local mark = (d.colorKey == "AFK" and "AFK ") or (d.colorKey == "DND" and "DND ") or ""
            tag = C("[" .. (NS.db.chat.shortTags and "W" or "From") .. "]", hex) .. " " .. C(mark, NS.COLORS.death)
        elseif d.colorKey == "WHISPER_INFORM" or d.colorKey == "BN_WHISPER_INFORM" then
            tag = C("[" .. (NS.db.chat.shortTags and "W>" or "To") .. "]", hex) .. " "
        end
        body = pop .. tag .. flags .. lang .. who .. sep .. C(text, hex)
    end

    -- a line that tripped an alert word gets that word picked out in colour
    if d.alert then
        local a = NS.db.chat.alerts
        body = CHAT.HighlightWord(body, d.alert, a.color or NS.COLORS.highlight)
    end

    -- "the same thing again" collapses into one line with a count
    if (d.repeats or 1) > 1 then
        body = body .. C("  x" .. d.repeats, NS.COLORS.accent)
    end

    w.line = ts .. body
    w.plain = NS.StripEscapes(w.line)
    w.plainLower = string.lower(w.plain)
    w.gen = NS.formatGen
    return w.line
end

function CHAT.MatchesSearch(w, needle)
    if not needle or needle == "" then return true end
    CHAT.FormatWrapper(w)
    return string.find(w.plainLower, needle, 1, true) ~= nil
end

-------------------------------------------------------------------------------
-- Ingest
-------------------------------------------------------------------------------
local lastWhisperSound = 0

-- Blizzard's /r (and the R key) read a "last tell target" that is normally set
-- by ChatFrame_MessageEventHandler. We unregister those events from Blizzard's
-- frames, so we have to feed the reply system ourselves.
local function setLastTell(name, chatType)
    if not name or name == "" then return end
    local fn = _G.ChatEdit_SetLastTellTarget
        or (_G.ChatFrameUtil and _G.ChatFrameUtil.SetLastTellTarget)
    if fn then pcall(fn, name, chatType or "WHISPER") end
end

local function setLastTold(name, chatType)
    if not name or name == "" then return end
    local fn = _G.ChatEdit_SetLastToldTarget
        or (_G.ChatFrameUtil and _G.ChatFrameUtil.SetLastToldTarget)
    if fn then pcall(fn, name, chatType or "WHISPER") end
end

NS.SetLastToldTarget = setLastTold

-------------------------------------------------------------------------------
-- Word lists: alerts, blocking, and repeat collapsing
-------------------------------------------------------------------------------
-- Public chat is where spam lives; guild and group chat is where your friends
-- live. The two get treated differently on purpose.
local PUBLIC_TYPES = { CHANNEL = true, SAY = true, YELL = true, EMOTE = true }
local PEER_KEYS = {
    GUILD = true, OFFICER = true, PARTY = true, PARTY_LEADER = true,
    RAID = true, RAID_LEADER = true, RAID_WARNING = true,
    BATTLEGROUND = true, BATTLEGROUND_LEADER = true,
    WHISPER_INFORM = true, BN_WHISPER_INFORM = true,
}
-- Only things a person typed at you can be blocked. Loot, money, system lines,
-- skill-ups and other addons' output are never candidates, however unlucky the
-- word list is.
local BLOCKABLE_TYPES = {
    CHANNEL = true, SAY = true, YELL = true, EMOTE = true, WHISPER = true,
    GUILD = true, OFFICER = true, PARTY = true, RAID = true, BATTLEGROUND = true,
}

local function isMe(author)
    if not author or author == "" or not NS.playerName then return false end
    return CHAT.StripName(author) == CHAT.StripName(NS.playerName)
end

local function containsWord(haystack, word)
    if not haystack or not word or word == "" then return false end
    return haystack:find(word, 1, true) ~= nil
end

-- Which alert word (if any) this message trips.
function CHAT.AlertWord(d)
    local a = NS.db.chat.alerts
    if not a or not a.enabled or not d.text then return nil end
    -- your own words are not news to you
    if isMe(d.author) then return nil end
    local lower = string.lower(NS.StripEscapes(d.text))
    if a.ownName and NS.playerName then
        local me = string.lower(NS.playerName)
        if containsWord(lower, me) then return NS.playerName end
    end
    for _, word in ipairs(a.words or {}) do
        if containsWord(lower, word) then return word end
    end
    return nil
end

-- True if this message should never be shown at all.
--
-- Deliberately narrow: only chat a stranger can send you. Blocking "gold" must
-- never eat "You loot 1 Gold", a guildmate's message, your own typing, or
-- another addon's output printed through AddMessage.
function CHAT.Blocked(d)
    local b = NS.db.chat.block
    if not b or not b.enabled or not d.text then return false end
    if #(b.words or {}) == 0 then return false end
    if not BLOCKABLE_TYPES[d.type] then return false end
    if isMe(d.author) then return false end
    if b.sparePeers and PEER_KEYS[d.colorKey] then return false end
    local hay = string.lower(NS.StripEscapes(d.text) .. " " .. (d.author or ""))
    for _, word in ipairs(b.words) do
        if containsWord(hay, word) then return true end
    end
    return false
end

function CHAT.WordList(list)
    return table.concat(list or {}, ", ")
end

function CHAT.ParseWordList(text)
    local out, seen = {}, {}
    for token in string.gmatch(text or "", "[^,;\n]+") do
        token = string.lower((token:gsub("^%s+", ""):gsub("%s+$", "")))
        if token ~= "" and not seen[token] then
            seen[token] = true
            out[#out + 1] = token
        end
    end
    return out
end

-- The most recent wrapper carrying the same author and text, if it is recent
-- enough to be a repeat rather than a coincidence.
local function findRepeat(d)
    local dd = NS.db.chat.dedupe
    if not dd or not dd.enabled or not d.text or d.text == "" then return nil end
    if dd.publicOnly and not PUBLIC_TYPES[d.type] then return nil end
    local cutoff = (d.t or time()) - (dd.seconds or 30)
    for i = #buffer, math.max(#buffer - 60, 1), -1 do
        local w = buffer[i]
        local o = w.d
        if (o.t or 0) < cutoff then return nil end
        if o.type == d.type and o.author == d.author and o.text == d.text
            and o.chanBase == d.chanBase then
            return w
        end
    end
    return nil
end

-- -inf, not 0: GetTime() is small right after the client starts, so a plain 0
-- would swallow the first alert of the session
local lastAlertSound = -math.huge

local function ingest(d)
    local db = NS.db.chat

    -- blocked outright: never buffered, never persisted, never counted unread
    if CHAT.Blocked(d) then
        db.block.count = (db.block.count or 0) + 1
        return
    end

    d.alert = CHAT.AlertWord(d)

    -- Everything below the buffering runs whether or not this line turns out
    -- to be a repeat. A friend whispering "you there?" twice must still ping,
    -- still raise the whisper bar, and still update your /r target.
    if d.alert then
        local a = db.alerts
        if a.sound and NS.PlayAlertSound then
            local now = GetTime()
            if now - lastAlertSound > 2 then
                lastAlertSound = now
                NS.PlayAlertSound(a.soundKey, a.soundFile)
            end
        end
    end

    -- what we know about the people we talk to
    if NS.PLAYERS and d.author and d.author ~= "" then
        if d.colorKey == "WHISPER" then
            NS.PLAYERS.NoteWhisper(d.author, d.text, false)
        elseif d.colorKey == "WHISPER_INFORM" then
            NS.PLAYERS.NoteWhisper(d.author, d.text, true)
        end
        -- profession links are the only exact source of someone's skill level
        if d.text and d.text:find("|Htrade:", 1, true) then
            NS.PLAYERS.ObserveMessage(d.author, d.text)
        end
    end

    -- keep /r, shift-R and tell history working
    local ck = d.colorKey
    if ck == "WHISPER" or ck == "AFK" or ck == "DND" then
        setLastTell(d.author, "WHISPER")
    elseif ck == "BN_WHISPER" then
        setLastTell(d.author, "BN_WHISPER")
    elseif ck == "WHISPER_INFORM" then
        setLastTold(d.author, "WHISPER")
    elseif ck == "BN_WHISPER_INFORM" then
        setLastTold(d.author, "BN_WHISPER")
    end

    if ck == "WHISPER" or ck == "BN_WHISPER" then
        if db.whisperSound then
            local now = GetTime()
            if now - lastWhisperSound > 1 then
                lastWhisperSound = now
                if PlaySound then PlaySound(3081) end -- TellMessage
            end
        end
        if db.whisperBar and NS.NotifyWhisper and d.author and d.author ~= "" then
            NS.NotifyWhisper(d.author)
        end
    end

    -- the same line again: bump the existing one instead of adding a new one
    local dup = findRepeat(d)
    if dup then
        dup.d.repeats = (dup.d.repeats or 1) + 1
        dup.line, dup.plain, dup.gen = nil, nil, nil
        -- deliberately NOT touching dup.d.t: the record keeps the timestamp of
        -- the first sighting, so history stays in order and findRepeat's window
        -- measures from when the spam started
        if NS.RefreshChat then NS.RefreshChat() end
        return
    end

    -- persist (plain data only)
    if db.history then
        local h = db.historyLines
        h[#h + 1] = d
        while #h > (db.historySize or 500) do table.remove(h, 1) end
    end
    local w = pushWrapper(d)
    if NS.DispatchChat then NS.DispatchChat(w) end
end

local function normalizeChanBase(base)
    if not base or base == "" then return nil end
    -- "Trade - City" -> "Trade"; leading "2. " stripped if present
    base = base:gsub("^%d+%.%s*", "")
    base = base:match("^(.-)%s*%-") or base
    base = base:gsub("%s+$", "")
    if base == "" then return nil end
    return base
end

local function onChatEvent(event, text, author, lang, channelString, target,
        flags, zoneID, chanIdx, chanBase, _, lineID, guid)
    local map = EVENT_MAP[event]
    if not map then return end

    if event == "CHAT_MSG_CHANNEL_NOTICE" then
        -- arg1 is a token like "YOU_JOINED"; render it the way Blizzard does
        local fmtStr = _G["CHAT_" .. tostring(text) .. "_NOTICE"]
        if fmtStr then
            local ok, rendered = pcall(string.format, fmtStr, chanIdx or 0, channelString or "")
            if ok then text = rendered end
        end
    elseif event == "CHAT_MSG_IGNORED" then
        text = string.format(CHAT_IGNORED or "%s is ignoring you.", author or tostring(text))
    end

    local d = {
        t = time(),
        type = map[1],
        colorKey = map[2],
        text = text,
        author = author,
        lang = lang,
        flags = flags,
        guid = guid,
        chanIdx = chanIdx,
        chanBase = normalizeChanBase((chanBase ~= "" and chanBase) or channelString),
    }
    if event == "CHAT_MSG_TEXT_EMOTE" then d.textEmote = true end
    ingest(d)
end

-- Addon prints go straight to ChatFrameN:AddMessage without an event.
-- Only hooked on frames we HIDE (visible Blizzard frames would double-report
-- normal chat, since they also process CHAT_MSG_* events).
local function hookAddMessage(cf)
    if not cf or cf.llAddMessageHooked then return end
    cf.llAddMessageHooked = true
    hooksecurefunc(cf, "AddMessage", function(_, text)
        if type(text) ~= "string" then return end
        ingest({ t = time(), type = "ADDON", colorKey = "SYSTEM", text = text })
    end)
end

-------------------------------------------------------------------------------
-- Init / Blizzard chat hiding
-------------------------------------------------------------------------------
local chatEvents = {}
for ev in pairs(EVENT_MAP) do chatEvents[#chatEvents + 1] = ev end

local function unregisterBlizzardChatEvents()
    for i = 1, (NUM_CHAT_WINDOWS or 7) do
        local cf = _G["ChatFrame" .. i]
        if cf and cf.llChatReplaced then
            for ev in pairs(EVENT_MAP) do
                pcall(cf.UnregisterEvent, cf, ev)
            end
        end
    end
end

local chatEventFrame = CreateFrame("Frame")
chatEventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "UPDATE_CHAT_WINDOWS" or event == "UPDATE_FLOATING_CHAT_WINDOWS" then
        -- Blizzard re-registers chat events on its frames here and can bring
        -- tabs back with them; undo both for the frames we replaced
        -- the sweep re-hides anything Blizzard brought back; unregistering is
        -- what catches frames it re-registered events on
        unregisterBlizzardChatEvents()
        if CHAT.SweepBlizzardChat then CHAT.SweepBlizzardChat(true) end
        return
    end
    onChatEvent(event, ...)
end)

-- Hide one Blizzard chat tab for good.
--
-- Hiding it once is not enough. Blizzard shows tabs again from a dozen places -
-- docking, undocking, closing a window, the chat-settings refresh - so the tab
-- needs a Show hook that puts it straight back down. This is the difference
-- between a tab that stays gone and the "shadow tab" left behind when a
-- Battle.net whisper pop-out is closed.
local function hideBlizzardTab(tab)
    if not tab then return end
    tab.llChatHidden = true
    if not tab.llChatHooked then
        tab.llChatHooked = true
        hooksecurefunc(tab, "Show", function(t)
            if t.llChatHidden then t:Hide() end
        end)
    end
    -- Only when it is actually up. Hiding an already-hidden tab is not free:
    -- it marks Blizzard's dock dirty, the dock rebuilds its tabs next frame,
    -- and if a sweep is hooked to that rebuild the two feed each other forever.
    if tab:IsShown() then tab:Hide() end
end

local function hideBlizzardFrame(cf, name)
    if not cf then return end
    if not cf.llChatReplaced then
        cf.llChatReplaced = true
        cf:SetScript("OnShow", cf.Hide)
        hookAddMessage(cf)
        -- Stop Blizzard frames from double-processing chat events while we
        -- replace them (runtime only - saved chat settings are untouched,
        -- everything restores on /reload with the module disabled). Once per
        -- frame: the sweep runs behind seven hooks and two events, and redoing
        -- forty UnregisterEvent calls per frame per sweep was pure waste.
        for ev in pairs(EVENT_MAP) do
            pcall(cf.UnregisterEvent, cf, ev)
        end
    end
    if cf:IsShown() then cf:Hide() end
    hideBlizzardTab(_G[(name or "") .. "Tab"])
end

-- Blizzard's pop-out whisper windows are created on demand and recycled, so
-- they are never in the numbered list. Walk everything: the permanent frames,
-- whatever CHAT_FRAMES currently holds, and the numbered frames past
-- NUM_CHAT_WINDOWS that temporary windows actually live in.
local MAX_CHAT_FRAMES = 50
-- Sweeps are idempotent, so back-to-back ones are wasted work. Anything that
-- can conjure a chat frame goes through a hook that forces one; the rest can
-- wait a quarter of a second.
local lastSweep, sweepSeq = -math.huge, 0
function CHAT.SweepBlizzardChat(force)
    if not NS.db or not NS.db.chat or not NS.db.chat.hideBlizzard then return end
    local now = GetTime and GetTime() or 0
    if not force and (now - lastSweep) < 0.25 then return end
    lastSweep = now
    sweepSeq = sweepSeq + 1
    local seen = {}
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local name = "ChatFrame" .. i
        seen[name] = true
        hideBlizzardFrame(_G[name], name)
    end
    for _, name in ipairs(CHAT_FRAMES or {}) do
        if not seen[name] then
            seen[name] = true
            hideBlizzardFrame(_G[name], name)
        end
    end
    -- Temporary windows are numbered contiguously above the permanent ones, so
    -- the first gap is the end of the list. Bail there rather than probing all
    -- fifty slots on every sweep.
    for i = (NUM_CHAT_WINDOWS or 10) + 1, MAX_CHAT_FRAMES do
        local name = "ChatFrame" .. i
        local cf = _G[name]
        if not cf then break end
        if not seen[name] then hideBlizzardFrame(cf, name) end
    end
end

-- test hook: how many sweeps have actually done work
function CHAT.SweepCount() return sweepSeq end

function CHAT.HideBlizzardChat()
    CHAT.SweepBlizzardChat(true)

    local extras = { ChatFrameMenuButton, ChatFrameChannelButton }
    for _, b in ipairs(extras) do
        if b then
            b:Hide()
            if not b.llHooked then
                b.llHooked = true
                hooksecurefunc(b, "Show", function(x) x:Hide() end)
            end
        end
    end

    -- Every path that can conjure or resurrect a Blizzard chat tab gets a
    -- sweep behind it. Opening a pop-out is the obvious one; closing it is the
    -- one that left a shadow tab, because Blizzard shows the tab again on its
    -- way to recycling the frame.
    if not CHAT.tempHooked then
        CHAT.tempHooked = true
        -- One pending follow-up sweep at a time. This used to allocate a fresh
        -- timer and closure on every hook call.
        local pending = false
        local function sweepSoon()
            -- forced: these hooks only fire when the user opens, closes or docks
            -- a window, and a tab must not be allowed to flash for a frame
            CHAT.SweepBlizzardChat(true)
            if pending or not (C_Timer and C_Timer.After) then return end
            pending = true
            C_Timer.After(0, function()
                pending = false
                -- forced: this is the one that runs after Blizzard has finished
                -- re-docking, and it must not be swallowed by the throttle
                CHAT.SweepBlizzardChat(true)
            end)
        end
        CHAT.sweepSoon = sweepSoon
        -- Deliberately NOT FCFDock_UpdateTabs: Blizzard calls that from the
        -- dock's OnUpdate, so hooking it runs a sweep every frame the dock is
        -- dirty - and a sweep that hides a docked frame dirties the dock. The
        -- dock/close/select hooks below cover every way a tab comes back
        -- without sitting in the frame loop.
        for _, fname in ipairs({
            "FCF_OpenTemporaryWindow", "FCF_Close", "FCF_DockFrame",
            "FCF_UnDockFrame", "FCF_OpenNewWindow", "FCF_SelectDockFrame",
        }) do
            if type(_G[fname]) == "function" then
                hooksecurefunc(fname, sweepSoon)
            end
        end
    end

    -- keep our unregistering in force when Blizzard refreshes chat windows
    chatEventFrame:RegisterEvent("UPDATE_CHAT_WINDOWS")
    pcall(chatEventFrame.RegisterEvent, chatEventFrame, "UPDATE_FLOATING_CHAT_WINDOWS")
end

function CHAT.Init()
    local db = NS.db.chat
    if not db.enabled then return end

    -- restore history
    if db.history then
        for _, d in ipairs(db.historyLines) do
            d.chanBase = normalizeChanBase(d.chanBase)  -- migrate pre-1.2 records
            pushWrapper(d)
        end
    end

    for _, ev in ipairs(chatEvents) do
        pcall(chatEventFrame.RegisterEvent, chatEventFrame, ev)
    end

    if db.hideBlizzard then
        CHAT.HideBlizzardChat()
    end

    NS.InitChatWindow()
end

-------------------------------------------------------------------------------
-- Player link menu / URL clicks
-------------------------------------------------------------------------------
local function inviteUnit(name)
    if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(name)
    elseif InviteUnit then InviteUnit(name) end
end

-- Blizzard's own player dropdown, exactly as clicking a name in the stock chat
-- frame produces it: Whisper, Invite, Add Friend, Ignore, Report and whatever
-- else the client offers for that person. We only pick the context.
local blizzDropdown

function CHAT.ShowBlizzardPlayerMenu(name)
    if not name or name == "" then return false end
    if not (UIDropDownMenu_Initialize and ToggleDropDownMenu and UnitPopup_ShowMenu) then
        return false
    end
    local short = name:match("^([^%-]+)") or name

    if not blizzDropdown then
        blizzDropdown = CreateFrame("Frame", "LogLoversPlayerDropDown", UIParent,
            "UIDropDownMenuTemplate")
        blizzDropdown.displayMode = "MENU"
    end

    -- the menu Blizzard shows depends on your relationship to the player
    local which = "CHAT_ROSTER"
    if UnitInRaid and UnitInRaid(short) then which = "RAID_PLAYER"
    elseif UnitInParty and UnitInParty(short) then which = "PARTY" end

    blizzDropdown.name = short
    blizzDropdown.unit = nil
    blizzDropdown.chatType = nil
    blizzDropdown.chatTarget = nil
    blizzDropdown.lineID = nil

    local function open(w)
        UIDropDownMenu_Initialize(blizzDropdown, function(self, level, menuList)
            UnitPopup_ShowMenu(self, w, nil, short)
        end, "MENU")
        ToggleDropDownMenu(1, nil, blizzDropdown, "cursor", 3, -3)
    end

    if NS.CloseMenu then NS.CloseMenu() end
    -- CHAT_ROSTER is the chat-name context; FRIEND is the older fallback
    if pcall(open, which) then return true end
    if which ~= "CHAT_ROSTER" and pcall(open, "CHAT_ROSTER") then return true end
    if pcall(open, "FRIEND") then return true end
    return false
end

function CHAT.PlayerMenu(name)
    local disp = name:match("^([^%-]+)") or name

    local items = { { text = disp .. "  (Log Lovers)", header = true } }
    -- everything we have observed about them, above the actions
    if NS.PlayerInfoItems then
        for _, it in ipairs(NS.PlayerInfoItems(name,
                function() CHAT.PlayerMenu(name) end, true)) do
            items[#items + 1] = it
        end
    end

    for _, extra in ipairs({
        { text = "Whisper", func = function() NS.StartWhisper(name) end },
        { text = "Invite to group", func = function() inviteUnit(name) end },
        { text = "Add friend", func = function()
            if C_FriendList and C_FriendList.AddFriend then C_FriendList.AddFriend(disp)
            elseif AddFriend then AddFriend(disp) end
        end },
        { text = "Ignore", func = function()
            if C_FriendList and C_FriendList.AddIgnore then C_FriendList.AddIgnore(disp)
            elseif AddIgnore then AddIgnore(disp) end
        end },
        { text = "Insert name into chat box", func = function()
            if ChatEdit_InsertLink then ChatEdit_InsertLink(name) end
        end },
        { text = "Copy name", func = function()
            NS.ShowCopyText("Player name", name)
        end },
    }) do
        items[#items + 1] = extra
    end

    NS.ShowMenu(items)
end

function CHAT.HandleLinkClick(link, text, button)
    local kind, rest = link:match("^(%a+):(.*)$")
    if kind == "llpop" then
        if NS.PopOutWhisper then NS.PopOutWhisper(rest) end
        return true
    elseif kind == "llp" then
        -- left = whisper, shift = /who printed straight into chat,
        -- ctrl = the full menu, right = Blizzard's own menu,
        -- alt = straight to an invite with no menu in the way.
        --
        -- Shift runs the lookup and prints the answer the way typing /who
        -- does. No window, no menu, no second click.
        if NS.db.chat.altInvite and IsAltKeyDown and IsAltKeyDown() then
            inviteUnit(rest)
        elseif IsShiftKeyDown and IsShiftKeyDown() then
            if NS.PLAYERS and NS.PLAYERS.LookupToChat then
                NS.PLAYERS.LookupToChat(rest)
            end
        elseif IsControlKeyDown and IsControlKeyDown() then
            CHAT.PlayerMenu(rest)
        elseif button == "RightButton" then
            -- Blizzard's own menu, with ours as the fallback if the client
            -- does not expose the dropdown API
            if not CHAT.ShowBlizzardPlayerMenu(rest) then
                CHAT.PlayerMenu(rest)
            end
        else
            NS.StartWhisper(rest)
        end
        return true
    elseif kind == "llurl" then
        NS.ShowCopyText("URL", rest)
        return true
    elseif kind == "spell" then
        local id = tonumber(rest:match("^(%d+)"))
        if IsShiftKeyDown() then
            local slink = id and NS.GetSpellLink(id)
            if slink and ChatEdit_InsertLink then ChatEdit_InsertLink(slink) end
        elseif id then
            local name = text and text:match("%[(.-)%]") or "?"
            NS.OpenSpellInspector(id, name)
        end
        return true
    elseif kind == "item" or kind == "quest" or kind == "enchant"
        or kind == "talent" or kind == "achievement" or kind == "trade"
        or kind == "glyph" or kind == "instancelock" or kind == "currency" then
        -- `text` is already the complete, colored hyperlink; never re-wrap it
        -- (nesting |H..|h produces an invalid escape code when sent)
        local full = text
        if not full or not full:find("|H", 1, true) then
            full = "|H" .. link .. "|h" .. (text or "[link]") .. "|h"
        end
        if IsShiftKeyDown() then
            if ChatEdit_InsertLink then ChatEdit_InsertLink(full) end
        elseif SetItemRef then
            pcall(SetItemRef, link, full, button or "LeftButton")
        end
        return true
    end
    return false
end

function CHAT.HandleLinkEnter(frame, link)
    local kind = link:match("^(%a+):")
    if kind == "item" or kind == "quest" or kind == "enchant"
        or kind == "talent" or kind == "spell" then
        GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
        if ok then GameTooltip:Show() else GameTooltip:Hide() end
        return true
    elseif kind == "llurl" then
        GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
        GameTooltip:SetText("Click to copy this URL", 0.4, 0.75, 1)
        GameTooltip:Show()
        return true
    elseif kind == "llpop" then
        GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
        GameTooltip:SetText("Pop out this conversation", NS.ACCENT.r, NS.ACCENT.g, NS.ACCENT.b)
        GameTooltip:AddLine(NS.C("Opens a window for just this person, with its own reply box.", NS.COLORS.dim))
        GameTooltip:Show()
        return true
    elseif kind == "llp" then
        GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
        local disp = link:match("^llp:([^%-]+)") or "player"
        GameTooltip:SetText(disp, 1, 1, 1)
        GameTooltip:AddLine(NS.C("Click: whisper  -  Shift or right-click: menu", NS.COLORS.dim))
        GameTooltip:AddLine(NS.C("Ctrl-click: what Log Lovers knows about them", NS.COLORS.dim))
        GameTooltip:Show()
        return true
    end
    return false
end
