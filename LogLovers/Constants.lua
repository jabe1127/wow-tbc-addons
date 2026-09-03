-- LogLovers Constants: colors, categories, subevent mapping, defaults
local ADDON, NS = ...

NS.VERSION = "1.14.0"

-------------------------------------------------------------------------------
-- Colors (hex, no alpha)
-------------------------------------------------------------------------------
-- Palette taken from the addon icon: gold glow, aged parchment, warm wood,
-- and the heart's red. Combat-relevant colors (schools, power, class) stay
-- functional so the log is still readable at a glance.
NS.COLORS = {
    accent      = "ffc247",   -- icon gold
    accentDim   = "c99a3c",
    timestamp   = "8f8371",
    text        = "ece3d1",   -- parchment
    dim         = "9d9382",
    friendly    = "8ecdf0",
    hostile     = "ef7a6a",
    neutral     = "ffd166",
    pet         = "c9e08a",
    heal        = "8fd98f",
    overheal    = "4c7a4c",
    mana        = "6f9ae0",
    rage        = "e06a5c",
    energy      = "ffe66d",
    miss        = "a99f8e",
    death       = "e04c4c",   -- heart red
    buff        = "8fd98f",
    debuff      = "e0897a",
    fail        = "c9584f",
    interrupt   = "ffa94d",
    dispel      = "d0a3ea",
    highlight   = "ffd700",
    crit        = "ffb347",
}

-- accent as RGB, for textures/borders that cannot take a hex string
NS.ACCENT = { r = 1.00, g = 0.76, b = 0.28 }
NS.ACCENT_SOFT = { r = 0.62, g = 0.46, b = 0.16 }

-- Spell school colors (TBC bit masks)
NS.SCHOOLS = {
    [0x01] = { name = "Physical", color = "ffffb3" },
    [0x02] = { name = "Holy",     color = "ffe680" },
    [0x04] = { name = "Fire",     color = "ff8a5c" },
    [0x08] = { name = "Nature",   color = "77e08a" },
    [0x10] = { name = "Frost",    color = "80d4ff" },
    [0x20] = { name = "Shadow",   color = "a58aff" },
    [0x40] = { name = "Arcane",   color = "ff85e0" },
}
NS.SCHOOL_ORDER = { 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01 }

NS.POWER_NAMES = {
    [0] = { name = "Mana",   color = NS.COLORS.mana },
    [1] = { name = "Rage",   color = NS.COLORS.rage },
    [2] = { name = "Focus",  color = "ffb26b" },
    [3] = { name = "Energy", color = NS.COLORS.energy },
    [4] = { name = "Happiness", color = "8affc1" },
}

NS.MISS_LABELS = {
    MISS = "Miss", DODGE = "Dodge", PARRY = "Parry", BLOCK = "Block",
    RESIST = "Resist", ABSORB = "Absorb", IMMUNE = "Immune",
    EVADE = "Evade", DEFLECT = "Deflect", REFLECT = "Reflect",
}

-- Sentence form, for the verbose style. Without these the log read "was dodge
-- by", "was immune by".
NS.MISS_VERBS = {
    MISS = "missed", DODGE = "dodged", PARRY = "parried", BLOCK = "blocked",
    RESIST = "resisted", ABSORB = "absorbed", IMMUNE = "immune",
    EVADE = "evaded", DEFLECT = "deflected", REFLECT = "reflected",
}

-------------------------------------------------------------------------------
-- Event categories
-------------------------------------------------------------------------------
-- Category keys used by filters: damage, healing, auras, casts, misses,
-- power, deaths, dispels, interrupts, enchants, other
NS.SUBEVENT_CAT = {
    SWING_DAMAGE            = "damage",
    RANGE_DAMAGE            = "damage",
    SPELL_DAMAGE            = "damage",
    SPELL_PERIODIC_DAMAGE   = "damage",
    DAMAGE_SHIELD           = "damage",
    DAMAGE_SPLIT            = "damage",
    ENVIRONMENTAL_DAMAGE    = "damage",

    SWING_MISSED            = "misses",
    RANGE_MISSED            = "misses",
    SPELL_MISSED            = "misses",
    SPELL_PERIODIC_MISSED   = "misses",
    DAMAGE_SHIELD_MISSED    = "misses",

    SPELL_HEAL              = "healing",
    SPELL_PERIODIC_HEAL     = "healing",

    SPELL_ENERGIZE          = "power",
    SPELL_PERIODIC_ENERGIZE = "power",
    SPELL_DRAIN             = "power",
    SPELL_PERIODIC_DRAIN    = "power",
    SPELL_LEECH             = "power",
    SPELL_PERIODIC_LEECH    = "power",

    SPELL_AURA_APPLIED      = "auras",
    SPELL_AURA_REMOVED      = "auras",
    SPELL_AURA_APPLIED_DOSE = "auras",
    SPELL_AURA_REMOVED_DOSE = "auras",
    SPELL_AURA_REFRESH      = "auras",
    SPELL_AURA_BROKEN       = "auras",
    SPELL_AURA_BROKEN_SPELL = "auras",

    SPELL_CAST_START        = "casts",
    SPELL_CAST_SUCCESS      = "casts",
    SPELL_CAST_FAILED       = "casts",

    SPELL_INTERRUPT         = "interrupts",

    SPELL_DISPEL            = "dispels",
    SPELL_DISPEL_FAILED     = "dispels",
    SPELL_STOLEN            = "dispels",

    PARTY_KILL              = "deaths",
    UNIT_DIED               = "deaths",
    UNIT_DESTROYED          = "deaths",
    UNIT_DISSIPATES         = "deaths",

    ENCHANT_APPLIED         = "enchants",
    ENCHANT_REMOVED         = "enchants",

    SPELL_EXTRA_ATTACKS     = "other",
    SPELL_SUMMON            = "other",
    SPELL_CREATE            = "other",
    SPELL_INSTAKILL         = "other",
    SPELL_DURABILITY_DAMAGE = "other",
    SPELL_DURABILITY_DAMAGE_ALL = "other",
    SPELL_RESURRECT         = "other",
}

NS.CATEGORY_LIST = {
    { key = "damage",     label = "Damage" },
    { key = "healing",    label = "Healing" },
    { key = "misses",     label = "Misses / Avoids" },
    { key = "auras",      label = "Buffs / Debuffs" },
    { key = "casts",      label = "Casts" },
    { key = "power",      label = "Power gains / drains" },
    { key = "interrupts", label = "Interrupts" },
    { key = "dispels",    label = "Dispels / Steals" },
    { key = "deaths",     label = "Deaths / Kills" },
    { key = "enchants",   label = "Enchants" },
    { key = "other",      label = "Other" },
}

NS.ROLE_LIST = {
    { key = "player",   label = "You" },
    { key = "pet",      label = "Your pet" },
    { key = "party",    label = "Party" },
    { key = "raid",     label = "Raid" },
    { key = "friendly", label = "Other friendly" },
    { key = "hostile",  label = "Hostile" },
    { key = "neutral",  label = "Neutral" },
}

NS.RAID_ICON_TEX = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"
NS.SKULL_ICON = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:%d|t"

NS.FONTS = {
    { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow",  path = "Fonts\\ARIALN.TTF" },
    { name = "Skurri",        path = "Fonts\\skurri.ttf" },
    { name = "Morpheus",      path = "Fonts\\MORPHEUS.ttf" },
}

NS.OUTLINES = {
    { name = "None",          flag = "" },
    { name = "Outline",       flag = "OUTLINE" },
    { name = "Thick Outline", flag = "THICKOUTLINE" },
    { name = "Monochrome",    flag = "OUTLINE, MONOCHROME" },
}

-------------------------------------------------------------------------------
-- Alert sounds for spell highlights.
--
-- "kit" is looked up in Blizzard's SOUNDKIT table first (names are stable
-- across clients); "id" is the raw sound-kit id used when SOUNDKIT is missing
-- the name. Anything the client does not have simply does not play - a wrong
-- id is never an error.
-------------------------------------------------------------------------------
NS.ALERT_SOUNDS = {
    { key = "none",       name = "No sound" },
    { key = "raidwarn",   name = "Raid warning",    kit = "RAID_WARNING",              id = 8959 },
    { key = "readycheck", name = "Ready check",     kit = "READY_CHECK",               id = 8960 },
    { key = "whisper",    name = "Whisper ping",    kit = "TELL_MESSAGE",              id = 3081 },
    { key = "questdone",  name = "Quest complete",  kit = "IG_QUEST_LIST_COMPLETE",    id = 878  },
    { key = "mapping",    name = "Map ping",        kit = "MAP_PING",                  id = 3175 },
    { key = "auction",    name = "Auction bell",    kit = "AUCTION_WINDOW_OPEN",       id = 5274 },
    { key = "levelup",    name = "Level up",        kit = "LEVELUP",                   id = 888  },
    { key = "menuopen",   name = "Menu click",      kit = "IG_MAINMENU_OPEN",          id = 850  },
    { key = "alarm",      name = "Alarm clock",     kit = "ALARM_CLOCK_WARNING_3",     id = 12867 },
    { key = "custom",     name = "Custom file...",  custom = true },
}

NS.DEFAULT_ALERT_SOUND = "raidwarn"

-- What the typing box shows when you are aimed at one person. Blizzard's own
-- header is a loud "To Playername:" in whisper pink, which is a lot of shouting
-- for something you already know you just clicked.
NS.WHISPER_HEADER_MODES = {
    { key = "compact",  label = "Compact (Name \194\187)" },
    { key = "blizzard", label = "Blizzard's (To Name:)" },
    { key = "off",      label = "Nothing" },
}

-- How far back a death timeline reaches. This used to be a checkbox plus a
-- slider, which needed two lines of explanation to say which one was in force.
NS.RECAP_SPANS = {
    { key = "fight", label = "The whole fight" },
    { key = "12",    label = "Last 12 seconds" },
    { key = "30",    label = "Last 30 seconds" },
    { key = "60",    label = "Last minute" },
}

NS.TIMESTAMP_MODES = {
    { key = "none",    label = "None" },
    { key = "hms",     label = "HH:MM:SS" },
    { key = "hmsms",   label = "HH:MM:SS.mmm" },
    { key = "combat",  label = "Combat-relative (M:SS.t)" },
}

NS.NUMBER_MODES = {
    { key = "full",  label = "Full (1,234,567)" },
    { key = "short", label = "Short (1.23m)" },
}

-- Who a combat view shows. "Just me" always means you AND your pet - there is
-- deliberately no way to separate them.
NS.SCOPE_CHOICES = {
    { key = "me",    label = "Just me" },
    { key = "group", label = "Me and my group" },
    { key = "all",   label = "Everyone" },
}

-- Which direction of events to show. Independent of who.
NS.DIRECTION_MODES = {
    { key = "both", label = "Everything I'm involved in" },
    { key = "out",  label = "Only what I do" },
    { key = "in",   label = "Only what's done to me" },
}

-- Where you are. Each situation gets its own "who" setting.
NS.LOCATIONS = {
    { key = "world", label = "Out in the world" },
    { key = "party", label = "Dungeons" },
    { key = "raid",  label = "Raids" },
    { key = "pvp",   label = "Battlegrounds" },
    { key = "arena", label = "Arenas" },
}

NS.DEFAULT_SCOPES = {
    world = "me", party = "me", raid = "me", pvp = "me", arena = "all",
}

NS.STYLE_MODES = {
    { key = "compact", label = "Compact (arrows)" },
    { key = "verbose", label = "Sentence" },
}

-------------------------------------------------------------------------------
-- Window presets
-------------------------------------------------------------------------------
local function allOn(list)
    local t = {}
    for _, e in ipairs(list) do t[e.key] = true end
    return t
end

function NS.DefaultFilterAll()
    return {
        categories = allOn(NS.CATEGORY_LIST),
        sources    = allOn(NS.ROLE_LIST),
        targets    = allOn(NS.ROLE_LIST),
        minAmount  = 0,
        aoeFarm    = false,   -- deaths only: one line per kill
        direction  = "both",  -- both | out | in
        scopes     = { world = "me", party = "me", raid = "me", pvp = "me", arena = "all" },
        hideCastStart = false,
        spellMode  = "off",   -- off | allow | block
        spellList  = {},      -- [lowered name or spellId string] = true
    }
end

NS.WINDOW_PRESETS = {
    { key = "everything", label = "Everything" },
    { key = "outgoing",   label = "My damage (you + pet)" },
    { key = "incoming",   label = "Incoming (on you)" },
    { key = "healing",    label = "Healing" },
    { key = "pet",        label = "Pet only" },
    { key = "auras",      label = "Buffs & debuffs" },
    { key = "deaths",     label = "Deaths & kills" },
    { key = "aoefarm",    label = "AoE farming (kills only)" },
    { key = "unfiltered", label = "Everyone, everywhere" },
    { key = "empty",      label = "Blank (configure yourself)" },
}

function NS.PresetFilter(key)
    local f = NS.DefaultFilterAll()
    local function only(t, ...)
        for k in pairs(t) do t[k] = false end
        for _, v in ipairs({ ... }) do t[v] = true end
    end
    if key == "outgoing" then
        only(f.categories, "damage", "misses", "interrupts", "deaths")
        f.direction = "out"
        -- direction alone is relative to whoever the view counts as "us", so in
        -- an arena (which defaults to Everyone) a window called "My damage"
        -- would have filled up with the enemy's. Pin the source too.
        only(f.sources, "player", "pet")
    elseif key == "incoming" then
        only(f.categories, "damage", "misses", "healing", "auras", "deaths")
        f.direction = "in"
    elseif key == "healing" then
        only(f.categories, "healing")
    elseif key == "pet" then
        only(f.sources, "pet")
    elseif key == "auras" then
        only(f.categories, "auras", "dispels")
    elseif key == "deaths" then
        only(f.categories, "deaths")
    elseif key == "aoefarm" then
        -- the flag alone does the filtering, so unticking it restores
        -- whatever event types the view had before
        f.aoeFarm = true
    elseif key == "unfiltered" then
        for _, loc in ipairs(NS.LOCATIONS) do f.scopes[loc.key] = "all" end
    end
    return f
end

-------------------------------------------------------------------------------
-- Saved variables defaults
-------------------------------------------------------------------------------
NS.DEFAULTS = {
    general = {
        bufferSize     = 6000,     -- normalized events kept in memory
        timestampMode  = "hms",
        numberMode     = "full",
        style          = "compact",
        hideBlizzLog   = false,
        highlightSound = true,      -- master switch for highlight alert sounds
        highlightSoundKey  = "raidwarn",  -- sound used by highlights set to "default"
        highlightSoundFile = "",          -- path used when a sound is set to "custom"
        minimapHint    = true,
        trackPlayers   = true,      -- remember people you whisper, group and trade with
    },
    appearance = {
        font        = "Fonts\\FRIZQT__.TTF",
        customFont  = "",
        fontSize    = 13,
        outline     = "",
        iconSize    = 14,
        showIcons   = true,
        classColors = true,
        schoolColors= true,
        bg          = { r = 0.055, g = 0.043, b = 0.030, a = 0.66 },
        border      = { r = 0.30, g = 0.21, b = 0.09, a = 0.95 },
        titleBg     = { r = 0.10, g = 0.075, b = 0.042, a = 0.90 },
        lineSpacing = 2,
        titleHeight = 19,
        titleFontSize = 11,
    },
    deathRecap = {
        enabled       = true,
        seconds       = 12,     -- floor, and the whole window when out of combat
        wholeFight    = true,   -- in combat, go back to the start of the pull
        maxEvents     = 200,    -- hard cap per timeline, so a long fight is bounded
        friendlyOnly  = false,
        maxDeaths     = 60,     -- kept in memory this session
        persist       = true,   -- keep recaps across logout / reload
        keepHistory   = 40,     -- how many are written to SavedVariables
        trackLoot     = true,   -- record what a corpse dropped when you loot it
    },
    deathHistory = {},          -- persisted recaps, oldest first
    chat = {
        -- these four are no longer options: the addon exists to do them
        enabled       = true,
        hideBlizzard  = true,
        shortTags     = true,
        urls          = true,
        whisperSound  = true,
        history       = true,
        historySize   = 500,
        historyLines  = {},
        editBoxTop    = false,
        whisperHeader = "compact",
        locked        = false,
        point         = { "BOTTOMLEFT", 30, 30 },
        width         = 460,
        height        = 240,
        fontSize      = nil,   -- nil = inherit appearance
        bgAlpha       = nil,   -- nil = inherit appearance
        activeView    = 1,
        views         = {},    -- { name, kind="chat"|"combat", filter/combatFilter, mode="tab"|"window", unread, point?, width?, height? }
        combatTabSeeded = false,
        whisperBar    = true,
        colors        = { types = {}, channels = {} },   -- hex color overrides

        scrollLines   = 3,      -- lines per mouse wheel notch
        fade          = false,  -- fade chat lines out when it goes quiet
        fadeTime      = 120,    -- seconds before a line fades
        showLevels    = false,  -- [70] before names we know the level of
        altInvite     = true,   -- alt-click a name to invite them

        -- Words that should get your attention. Your own name is included
        -- automatically unless you turn that off.
        alerts = {
            enabled   = true,
            ownName   = true,
            words     = {},          -- array of lowercase words
            color     = "ffd700",
            soundKey  = "raidwarn",
            soundFile = "",
            sound     = true,
            flashTabs = true,
        },

        -- Words that should never reach you. Gold sellers, mostly.
        block = {
            enabled   = true,
            words     = {},          -- array of lowercase words
            sparePeers = true,       -- never filter guild, party, raid or officer
            count     = 0,           -- how many messages have been dropped
        },

        -- Collapse the same line repeated over and over into one "x3".
        dedupe = {
            enabled    = true,
            seconds    = 30,
            publicOnly = true,       -- only channels, say, yell and emotes
        },
    },
    highlights  = {},   -- [lowered spell name] = { color = "ffd700", soundKey = "raidwarn" }
    auraBlock   = {},   -- [lowered aura name] = display name; hidden in every window
    players     = {},   -- [lowered name] = what we have observed about them
    windows     = {},   -- array of window configs, filled on first run
    captures    = {},   -- saved capture sessions
    deathPos    = nil,
    fightLogPos = nil,
    fightLogSize = nil,
    deathSize   = nil,
    optionsPos  = nil,
    optionsSize = nil,
    themeVersion = 0,     -- bumped by Core when the 1.0 palette is applied
    defaultsVersion = 0,  -- bumped by Core when sane combat defaults are applied
    version     = 1,
}

function NS.DefaultWindow(name, presetKey, x, y, w, h)
    return {
        name      = name or "Combat",
        filter    = NS.PresetFilter(presetKey or "everything"),
        shown     = true,
        locked    = false,
        clickThrough = false,
        point     = { "BOTTOMLEFT", x or 30, y or 140 },
        width     = w or 520,
        height    = h or 220,
        fontSize  = nil,       -- nil = inherit appearance.fontSize
        bgAlpha   = nil,       -- nil = inherit
        maxLines  = 1500,
        fade      = false,
        fadeTime  = 12,
        showTitle = true,
    }
end
