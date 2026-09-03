--[[--------------------------------------------------------------------------
    JCT - Floating Combat Text
    Core.lua : namespace, compatibility shims, saved variables, and the
               takeover of Blizzard's built-in floating combat text.

    Client target: TBC Anniversary (2.5.6, interface 20506).
    Everything here is written defensively because the Classic client was
    rebased onto the modern (12.0) UI codebase: several globals that existed
    in TBC 2.5.5 are gone, and several CVars gained a "_v2" twin.
----------------------------------------------------------------------------]]

local ADDON, ns = ...
_G.JCT = ns

ns.addonName = ADDON

--------------------------------------------------------------------------
-- Compatibility shims
--------------------------------------------------------------------------

local compat = {}
ns.compat = compat

compat.GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata

ns.version = (compat.GetAddOnMetadata and compat.GetAddOnMetadata(ADDON, "Version")) or "1.0.0"

-- CVar access -----------------------------------------------------------
local function _GetCVar(name)
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
    return _G.GetCVar and _G.GetCVar(name)
end

local function _SetCVar(name, value)
    -- SetCVar can be refused during combat lockdown for some CVar classes.
    local fn = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
    if not fn then return false end
    local ok = pcall(fn, name, value)
    return ok
end

local function _CVarExists(name)
    local fn = (C_CVar and C_CVar.GetCVarInfo) or _G.GetCVarInfo
    if not fn then return false end
    local ok, value = pcall(fn, name)
    return (ok and value ~= nil) and true or false
end

compat.GetCVar = _GetCVar
compat.SetCVar = _SetCVar
compat.CVarExists = _CVarExists

-- Spell info ------------------------------------------------------------
function compat.GetSpellName(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and type(info) == "table" then return info.name end
        if ok and type(info) == "string" then return info end
    end
    if _G.GetSpellInfo then
        local ok, name = pcall(_G.GetSpellInfo, spellID)
        if ok then return name end
    end
    return nil
end

function compat.GetSpellTexture(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and tex then return tex end
    end
    if _G.GetSpellTexture then
        local ok, tex = pcall(_G.GetSpellTexture, spellID)
        if ok and tex then return tex end
    end
    return nil
end

-- Returns true only for a real cooldown, not the global cooldown. If no
-- cooldown API is reachable it returns false, so callers stay permissive.
function compat.SpellOnCooldown(spellID)
    if not spellID then return false end
    local start, duration
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
        if ok and type(info) == "table" then
            start, duration = info.startTime, info.duration
        end
    end
    if start == nil and _G.GetSpellCooldown then
        local ok, s, d = pcall(_G.GetSpellCooldown, spellID)
        if ok then start, duration = s, d end
    end
    if not start or start == 0 then return false end
    if not duration or duration <= 1.5 then return false end
    return true
end

-- Returns usable, notEnoughPower. A spell gated on a condition (target
-- below 20% health, a recent kill) reports notEnoughPower = true when the
-- condition IS met but you are short on rage, so callers that want "is the
-- condition satisfied" should treat either as yes.
function compat.IsSpellUsable(nameOrID)
    if not nameOrID then return false, false end
    if C_Spell and C_Spell.IsSpellUsable then
        local ok, usable, noPower = pcall(C_Spell.IsSpellUsable, nameOrID)
        if ok then return usable and true or false, noPower and true or false end
    end
    if _G.IsUsableSpell then
        local ok, usable, noPower = pcall(_G.IsUsableSpell, nameOrID)
        if ok then return usable and true or false, noPower and true or false end
    end
    return false, false
end

-- COMBAT_TEXT_UPDATE plumbing -------------------------------------------
compat.GetCombatTextInfo = (C_CombatText and C_CombatText.GetCurrentEventInfo)
                            or _G.GetCurrentCombatTextEventInfo
compat.SetCombatTextUnit  = (C_CombatText and C_CombatText.SetActiveUnit)
                            or _G.CombatTextSetActiveUnit

--------------------------------------------------------------------------
-- Fonts
--
-- SetFont() on 2.5.6 rejects nil / false / "NONE" as the flags argument.
-- Always pass "" for "no outline". ns.SafeSetFont enforces that and caches
-- the last applied tuple, because SetFont is one of the most expensive
-- calls you can make in a combat-text hot path.
--------------------------------------------------------------------------

ns.fonts = {
    ["Friz Quadrata"] = [[Fonts\FRIZQT__.TTF]],
    ["Arial Narrow"]  = [[Fonts\ARIALN.TTF]],
    ["Skurri"]        = [[Fonts\SKURRI.TTF]],
    ["Morpheus"]      = [[Fonts\MORPHEUS.TTF]],
    ["2002"]          = [[Fonts\2002.TTF]],
    ["2002 Bold"]     = [[Fonts\2002B.TTF]],
    ["Nimrod"]        = [[Fonts\NIM_____.TTF]],
}

-- Drop .ttf files into JCT\Fonts\ and add a line here to use them.
-- (The client cannot list a directory, so the table is the index.)
ns.customFonts = {
    -- ["Expressway"] = [[Interface\AddOns\JCT\Fonts\Expressway.ttf]],
    -- ["Big Noodle"] = [[Interface\AddOns\JCT\Fonts\BigNoodleTitling.ttf]],
}

function ns.RefreshFontList()
    for name, path in pairs(ns.customFonts) do
        ns.fonts[name] = path
    end
    -- Pull in LibSharedMedia fonts if any other addon has loaded it.
    local LSM = _G.LibStub and _G.LibStub("LibSharedMedia-3.0", true)
    if LSM and LSM.HashTable then
        local hash = LSM:HashTable("font")
        if hash then
            for name, path in pairs(hash) do
                if ns.fonts[name] == nil then ns.fonts[name] = path end
            end
        end
    end
end

function ns.FontPath(name)
    return ns.fonts[name] or ns.fonts["Friz Quadrata"] or [[Fonts\FRIZQT__.TTF]]
end

function ns.SortedFontNames()
    local t = {}
    for name in pairs(ns.fonts) do t[#t + 1] = name end
    table.sort(t)
    return t
end

ns.MAX_FONT_SIZE = 64

-- Cached, flag-safe SetFont. Returns the size actually applied, which is not
-- always the size asked for.
--
-- Two traps this works around:
--   * On 2.5.6 SetFont rejects nil / false / "NONE" as the flags argument.
--     Always pass "".
--   * SetFont RETURNS false for a missing font file rather than raising, so
--     a pcall alone will not catch a bad path - the string just renders
--     invisible forever. Check the return value.
function ns.SafeSetFont(fontString, path, size, flags)
    if not fontString then return 0 end
    if type(flags) ~= "string" then flags = "" end
    if flags == "NONE" then flags = "" end
    if type(size) ~= "number" or size < 4 then size = 12 end
    if size > ns.MAX_FONT_SIZE then size = ns.MAX_FONT_SIZE end
    -- Cache on the REQUESTED path, not the one that ended up applied, so a
    -- font file that fails to load does not re-attempt on every single string.
    if fontString.__jctPath == path and fontString.__jctSize == size
       and fontString.__jctFlags == flags then
        return size
    end
    local ok, applied = pcall(fontString.SetFont, fontString, path, size, flags)
    if (not ok) or applied == false then
        -- Bad or missing font file: fall back to one that always exists.
        pcall(fontString.SetFont, fontString, [[Fonts\FRIZQT__.TTF]], size, flags)
    end
    fontString.__jctPath  = path
    fontString.__jctSize  = size
    fontString.__jctFlags = flags
    return size
end

--------------------------------------------------------------------------
-- Event classes and frames
--------------------------------------------------------------------------

-- Every message produced by Events.lua is tagged with one of these class
-- keys. Routing maps class -> display frame, so the user can send anything
-- anywhere without touching code.
ns.CLASSES = {
    { key = "outDamage",   label = "Your spell / ability damage" },
    { key = "outMelee",    label = "Your melee swings" },
    { key = "outAutoShot", label = "Your Auto Shot" },
    { key = "outCrit",     label = "Your crits" },
    { key = "outDot",      label = "Your DoT ticks" },
    { key = "outHeal",     label = "Your healing" },
    { key = "outHealCrit", label = "Your healing crits" },
    { key = "outMiss",     label = "Your misses / dodges / parries" },
    { key = "petDamage",   label = "Pet damage" },
    { key = "petCrit",     label = "Pet crits" },
    { key = "petHeal",     label = "Pet healing" },
    { key = "petMiss",     label = "Pet misses" },
    { key = "inDamage",    label = "Damage taken" },
    { key = "inCrit",      label = "Crits taken" },
    { key = "inHeal",      label = "Healing taken" },
    { key = "inMiss",      label = "Attacks you avoided" },
    { key = "power",       label = "Mana / rage / energy gains" },
    { key = "notify",      label = "Procs, interrupts, dispels, kills" },
    { key = "reactive",    label = "Reactive abilities now usable" },
    { key = "state",       label = "Stances, aspects, forms, seals" },
    { key = "enemyBreak",  label = "Enemy broke your control" },
    { key = "enemy",       label = "Enemy cooldowns and abilities" },
}

ns.FRAME_ORDER = {
    "outgoing", "crit", "melee", "ranged", "pet",
    "incoming", "healing", "power", "notify", "enemy",
}

ns.FRAME_LABELS = {
    enemy    = "Enemy alerts",
    outgoing = "Outgoing",
    crit     = "Crits",
    melee    = "Melee swings",
    ranged   = "Auto Shot",
    pet      = "Pet",
    incoming = "Incoming",
    healing  = "Healing",
    power    = "Power",
    notify   = "Notifications",
}

--------------------------------------------------------------------------
-- Defaults
--------------------------------------------------------------------------

local function frameDefault(x, y, w, h, anim)
    return {
        enabled   = true,
        x         = x,
        y         = y,
        width     = w,
        height    = h,
        animation = anim or "up",     -- up | down | fountain | horizontal | static
        curve     = "right",          -- left | right | alternate (fountain/horizontal/stagger)
        align     = "CENTER",         -- LEFT | CENTER | RIGHT
        maxLines  = 12,
        -- nil in any of these means "inherit from General"
        font      = nil,
        fontSize  = nil,
        outline   = nil,
        duration  = nil,
        fadeTime  = nil,
        stagger   = 0,                -- px of random horizontal jitter
        iconSide  = "LEFT",           -- LEFT | RIGHT | NONE
        scale     = 1.0,
            -- duration and fadeTime may be overridden per frame; nil inherits
    -- "screen"    : fixed position, the frame's x/y
        -- "nameplate" : follows the unit the message concerns, Blizzard-style
        anchor    = "screen",
        npOffsetX = 0,                -- sideways offset from the nameplate
        npOffsetY = 34,               -- height above the nameplate to start at
        npFallback = true,            -- use the screen position when the unit
                                      -- has no nameplate up
    }
end

ns.defaults = {
    dbVersion       = 1,
    enabled         = true,
    suppressBlizzard = true,
    preset          = "columns",

    -- Options window geometry, so it stays where and how you left it.
    ui = {
        width    = 760,
        height   = 580,
        point    = "CENTER",
        relPoint = "CENTER",
        x        = 0,
        y        = 0,
    },

    general = {
        font       = "Friz Quadrata",
        fontSize   = 22,
        outline    = "OUTLINE",       -- "" | OUTLINE | THICKOUTLINE | MONOCHROME | "OUTLINE, MONOCHROME"
        shadow     = true,
        duration   = 2.0,             -- seconds a number lives
        fadeTime   = 0.6,             -- seconds of fade at the end of a life
        fadeStart  = 0.70,            -- legacy fraction, kept only for migration
        critScale  = 1.45,            -- crit font multiplier
        critPop    = true,            -- overshoot-and-settle on crits
        critsOwnStream = true,        -- crits become their own class (and so
                                      -- can be routed to a dedicated frame);
                                      -- turn off to keep a melee crit in the
                                      -- melee stream, just bigger
        strata     = "MEDIUM",
        alpha      = 1.0,
    },

    format = {
        separators   = true,          -- 12,345
        abbreviate   = false,         -- 12.3k  (off: TBC numbers are small)
        critPrefix   = "",
        critSuffix   = "",
        icons        = true,
        iconSize     = 0,             -- 0 = match font size
        showSpellName = false,
        showCount    = true,          -- "1250 x5" after a merge
    },

    merge = {
        enabled   = true,
        mergeCrits = false,
        -- The first hit of a window is always shown immediately; only the
        -- hits that follow it inside the window are folded into a single
        -- follow-up number. That keeps the timing signal intact - which
        -- matters if you are reading your own attack rhythm - while still
        -- collapsing a Volley or a pet swing stream into something legible.
        intervals = {
            outDamage   = 0.5,
            outMelee    = 0,      -- never merge: this is a timing signal
            outAutoShot = 0,      -- never merge: this is a timing signal
            outDot      = 1.0,
            outHeal     = 0.5,
            outMiss     = 2.0,
            petDamage   = 0.5,
            petHeal     = 1.0,
            petMiss     = 3.0,
            inDamage    = 0.6,
            inHeal      = 1.0,
            inMiss      = 2.0,
            power       = 1.0,
        },
    },

    filters = {
        -- thresholds are applied AFTER merging
        minOutDamage   = 0,
        minOutCrit     = 0,
        minPetDamage   = 0,
        minPetCrit     = 0,
        minInDamage    = 0,
        minInCrit      = 0,
        minHeal        = 0,
        minHealCrit    = 0,
        minInHeal      = 0,
        minPower       = 0,

        showAutoAttack = true,
        showAutoShot   = true,
        showPetMelee   = false,       -- pet white swings are the loudest spam in the game
        showPetSpells  = true,
        showPetCrits   = true,
        showDots       = true,
        showHots       = true,
        showOverheal   = false,
        showMisses     = true,
        showIncomingMisses = true,
        showPetMisses  = false,
        showProcs      = true,
        showAuraFades  = false,

        -- Stances, aspects, forms, paladin auras and seals, armours.
        -- On by default and NOT restricted to combat, unlike the two above:
        -- these are deliberate choices, not incoming spam.
        showStates        = true,
        collapseStateSwaps = true,

        -- Enemy ability alerts
        showEnemySpells = true,
        enemyScope      = "targetfocus",   -- targetfocus | players | all
        enemyShowCaster = true,
        enemyCategories = {
            ["break"]  = true,
            cc         = true,
            cd         = true,
            racial     = true,
        },
        enemyBlacklist  = {},              -- [spellName] = true

        -- Reactive abilities (Counterattack, Mongoose Bite, Overpower...)
        showReactives   = true,
        showIncoming   = true,
        showIncomingHeals = true,
        showPower      = true,
        showEnvironmental = true,
        showKillingBlow = true,
        showInterrupts = true,
        showDispels    = true,
        showLowHealth  = true,
        showCombatState = false,
        onlyInCombat   = false,

        blacklist      = {},          -- [spellID] = true
        seenSpells     = {},          -- [spellID] = spellName, for the filter UI
    },

    colors = {
        -- physical / school driven damage uses schoolColors unless useSchoolColors is off
        useSchoolColors = true,
        -- Melee and Auto Shot deliberately sit far apart from the white of
        -- Physical spell damage, so a weave rhythm is readable peripherally
        -- without having to actually read the numbers.
        outMelee     = { 1.00, 0.62, 0.20 },
        outAutoShot  = { 0.45, 1.00, 0.88 },
        outDamage    = { 1.00, 1.00, 1.00 },
        outCrit      = { 1.00, 0.82, 0.20 },
        outDot       = { 0.85, 0.65, 1.00 },
        outHeal      = { 0.30, 1.00, 0.30 },
        outHealCrit  = { 0.45, 1.00, 0.45 },
        outMiss      = { 0.70, 0.70, 0.70 },
        petDamage    = { 0.62, 0.72, 1.00 },
        petCrit      = { 0.72, 0.80, 1.00 },
        petHeal      = { 0.40, 1.00, 0.70 },
        petMiss      = { 0.55, 0.65, 0.75 },
        inDamage     = { 1.00, 0.30, 0.30 },
        inCrit       = { 1.00, 0.10, 0.10 },
        inHeal       = { 0.30, 1.00, 0.30 },
        inMiss       = { 0.75, 0.75, 0.75 },
        power        = { 0.30, 0.55, 1.00 },
        notify       = { 1.00, 0.82, 0.00 },
        reactive     = { 0.30, 1.00, 0.45 },
        -- Gaining a state is cool and calm; losing one is warm and loud.
        -- The pair is meant to be readable without actually reading it.
        state        = { 0.55, 0.85, 1.00 },
        stateFade    = { 1.00, 0.45, 0.30 },
        enemy        = { 1.00, 0.55, 0.85 },
        enemyBreak   = { 1.00, 0.25, 0.25 },
        killingBlow  = { 1.00, 0.40, 0.00 },
        interrupt    = { 1.00, 1.00, 0.40 },
        dispel       = { 0.80, 0.60, 1.00 },
        lowHealth    = { 1.00, 0.10, 0.10 },
    },

    schoolColors = {
        [1]  = { 1.00, 1.00, 1.00 }, -- Physical
        [2]  = { 1.00, 0.90, 0.50 }, -- Holy
        [4]  = { 1.00, 0.50, 0.00 }, -- Fire
        [8]  = { 0.30, 1.00, 0.30 }, -- Nature
        [16] = { 0.50, 1.00, 1.00 }, -- Frost
        [20] = { 0.60, 0.80, 1.00 }, -- Frostfire
        [32] = { 0.50, 0.30, 0.90 }, -- Shadow
        [36] = { 0.80, 0.40, 0.40 }, -- Shadowflame
        [64] = { 1.00, 0.50, 1.00 }, -- Arcane
    },

    routing = {
        outDamage   = "outgoing",
        outMelee    = "outgoing",
        outAutoShot = "outgoing",
        outCrit     = "crit",
        outDot      = "outgoing",
        outHeal     = "healing",
        outHealCrit = "crit",
        outMiss     = "outgoing",
        petDamage   = "pet",
        petCrit     = "pet",
        petHeal     = "pet",
        petMiss     = "pet",
        inDamage    = "incoming",
        inCrit      = "incoming",
        inHeal      = "healing",
        inMiss      = "incoming",
        power       = "power",
        notify      = "notify",
        reactive    = "notify",
        state       = "notify",
        enemyBreak  = "enemy",
        enemy       = "enemy",
    },

    frames = {
        outgoing = frameDefault( 260,  -20, 180, 320, "up"),
        crit     = frameDefault( 210,  120, 220, 160, "up"),
        melee    = frameDefault( 130, -130, 130, 200, "up"),
        ranged   = frameDefault(-130, -130, 130, 200, "up"),
        pet      = frameDefault( 400,  -20, 160, 260, "up"),
        incoming = frameDefault(-260,  -20, 200, 320, "up"),
        healing  = frameDefault(-420,  -20, 160, 260, "up"),
        power    = frameDefault(   0, -170, 160, 120, "up"),
        notify   = frameDefault(   0,  200, 420, 120, "down"),
        enemy    = frameDefault(   0,  300, 460, 130, "down"),
    },
}

-- The melee and Auto Shot frames only exist for the weave preset; everything
-- else folds those streams into the outgoing column.
ns.defaults.frames.melee.enabled  = false
ns.defaults.frames.ranged.enabled = false

--------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------

local function deepCopy(src)
    local out = {}
    for k, v in pairs(src) do
        if type(v) == "table" then out[k] = deepCopy(v) else out[k] = v end
    end
    return out
end
ns.deepCopy = deepCopy

-- Fill in anything the saved table is missing without clobbering user values.
local function fill(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            fill(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end
ns.fill = fill

local function InitDB()
    -- "Fresh" means a genuinely empty saved-variables table. Do NOT test for
    -- a marker key: an install upgrading from a build that predates the
    -- marker would look fresh and have its dragged frame positions wiped.
    --
    -- Migration from the old FCT addon happens later, at PLAYER_LOGIN, once
    -- every addon has finished loading - see Profiles:MigrateFromLegacy.
    local fresh = (type(_G.JCT_DB) ~= "table") or (next(_G.JCT_DB) == nil)
    if type(_G.JCT_DB) ~= "table" then _G.JCT_DB = {} end
    ns.db = _G.JCT_DB
    ns.dbWasFresh = fresh

    -- Fade used to be a fraction of a message's life; it is now a plain
    -- number of seconds. Convert once, before fill() would paper over the
    -- old setting with the new default.
    local g = ns.db.general
    if type(g) == "table" and g.fadeTime == nil and type(g.fadeStart) == "number" then
        local d = type(g.duration) == "number" and g.duration or 2.0
        g.fadeTime = d * (1 - g.fadeStart)
    end

    fill(ns.db, ns.defaults)
    -- frames added in later versions
    for _, name in ipairs(ns.FRAME_ORDER) do
        if type(ns.db.frames[name]) ~= "table" then
            ns.db.frames[name] = deepCopy(ns.defaults.frames[name])
        else
            fill(ns.db.frames[name], ns.defaults.frames[name])
        end
    end
    -- On a genuinely fresh install, lay the frames out with the preset the
    -- DB claims to be using, so what you see matches what the options say.
    if fresh and ns.Presets then
        ns.Presets:Apply(ns.db.preset or "columns")
    end
    ns.db.initialised = true
end

--------------------------------------------------------------------------
-- Blizzard floating combat text takeover
--
-- Two separate systems:
--   1. Engine-side world text (numbers over the target's head). Lua cannot
--      restyle these at all; the only lever is the CVar.
--   2. The Lua-side Blizzard_CombatText addon (text near your character).
--      It is LoadOnDemand and gated entirely by enableFloatingCombatText.
--------------------------------------------------------------------------

local ENGINE_CVARS = {
    "floatingCombatTextCombatDamage",
    "floatingCombatTextCombatHealing",
    "floatingCombatTextCombatLogPeriodicSpells",
    "floatingCombatTextPetMeleeDamage",
    "floatingCombatTextPetSpellDamage",
    "floatingCombatTextCombatDamageAllAutos",
    "floatingCombatTextSpellMechanics",
    "floatingCombatTextSpellMechanicsOther",
    "floatingCombatTextAllSpellMechanics",
    "floatingCombatTextCombatHealingAbsorbSelf",
    "floatingCombatTextCombatHealingAbsorbTarget",
}

local resolvedCVars       -- cache: base name -> real name on this client
local suppressing = false

-- What the user had before we touched anything. Persisted, because an
-- in-memory copy only lets you restore Blizzard's combat text during the
-- same session that captured it - log out and the originals are gone.
local function savedCVars()
    if not ns.db then return nil end
    if type(ns.db.savedCVars) ~= "table" then ns.db.savedCVars = {} end
    return ns.db.savedCVars
end

local function ResolveCVar(base)
    if not resolvedCVars then resolvedCVars = {} end
    local cached = resolvedCVars[base]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end
    local v2 = base .. "_v2"
    if _CVarExists(v2) then
        resolvedCVars[base] = v2
        return v2
    elseif _CVarExists(base) then
        resolvedCVars[base] = base
        return base
    end
    resolvedCVars[base] = false
    return nil
end
ns.ResolveCVar = ResolveCVar

local function SuppressBlizzard()
    if not ns.db or not ns.db.suppressBlizzard then return end
    local saved = savedCVars()
    if not saved then return end
    suppressing = true

    -- Lua side. This single switch unregisters every event on Blizzard's
    -- frame and prevents the LoD addon from loading at all.
    if _GetCVar("enableFloatingCombatText") ~= "0" then
        if saved.enableFloatingCombatText == nil then
            saved.enableFloatingCombatText = _GetCVar("enableFloatingCombatText")
        end
        _SetCVar("enableFloatingCombatText", "0")
    end

    -- Engine side. Each one must be zeroed individually.
    for i = 1, #ENGINE_CVARS do
        local name = ResolveCVar(ENGINE_CVARS[i])
        if name then
            local current = _GetCVar(name)
            if current ~= "0" then
                if saved[name] == nil then saved[name] = current end
                _SetCVar(name, "0")
            end
        end
    end

    -- Belt and braces: if the addon was already loaded this session, hide it.
    local ct = _G.CombatText
    if ct and ct.IsShown and ct:IsShown() then
        pcall(ct.Hide, ct)
    end

    suppressing = false
end
ns.SuppressBlizzard = SuppressBlizzard

function ns.RestoreBlizzard()
    local saved = savedCVars()
    if not saved then return end
    suppressing = true
    for name, value in pairs(saved) do
        if value ~= nil then _SetCVar(name, value) end
    end
    wipe(saved)
    resolvedCVars = nil
    suppressing = false
end

--------------------------------------------------------------------------
-- Ownership tracking: which GUIDs count as "me"
--------------------------------------------------------------------------

ns.playerGUID = nil
ns.petGUID    = nil
ns.targetGUID = nil
ns.focusGUID  = nil
ns.myGuardians = {}   -- [guid] = true, for totems / snakes / short-lived pets

local function UpdateGUIDs()
    ns.playerGUID = UnitGUID("player")
    ns.petGUID = UnitGUID("pet")
end

-- Cached rather than looked up per combat log event, because the enemy
-- alert path runs on every SPELL_CAST_SUCCESS in range.
local function UpdateTarget()
    ns.targetGUID = UnitGUID("target")
end

local function UpdateFocus()
    ns.focusGUID = UnitGUID("focus")
end

--------------------------------------------------------------------------
-- Event dispatch
--------------------------------------------------------------------------

local driver = CreateFrame("Frame", "JCT_EventFrame")
ns.eventFrame = driver

local function OnCombatTextUnitChanged()
    if compat.SetCombatTextUnit then
        pcall(compat.SetCombatTextUnit, "player")
    end
end

driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("CVAR_UPDATE")
driver:RegisterEvent("UNIT_PET")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:RegisterEvent("PLAYER_REGEN_DISABLED")
driver:RegisterEvent("PLAYER_TARGET_CHANGED")
pcall(driver.RegisterEvent, driver, "PLAYER_FOCUS_CHANGED")
pcall(driver.RegisterEvent, driver, "SPELLS_CHANGED")
pcall(driver.RegisterEvent, driver, "CHARACTER_POINTS_CHANGED")

driver:SetScript("OnEvent", function(self, event, arg1, arg2, ...)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then
            InitDB()
            ns.RefreshFontList()
            if ns.Engine then pcall(ns.Engine.BuildAll, ns.Engine) end
        elseif arg1 == "Blizzard_CombatText" then
            -- User (or another addon) turned JCT back on and the LoD addon
            -- loaded. Push it back down.
            SuppressBlizzard()
        end

    elseif event == "PLAYER_TARGET_CHANGED" then
        UpdateTarget()

    elseif event == "PLAYER_FOCUS_CHANGED" then
        UpdateFocus()

    elseif event == "SPELLS_CHANGED" or event == "CHARACTER_POINTS_CHANGED" then
        -- Respec or a newly trained rank changes which reactives you have.
        if ns.BuildSpellData then ns.BuildSpellData() end

    elseif event == "PLAYER_LOGIN" then
        UpdateGUIDs()
        UpdateTarget()
        UpdateFocus()
        if ns.BuildSpellData then ns.BuildSpellData(true) end

        -- Migration runs BEFORE our own CVar suppression. The old addon
        -- zeroed the combat text CVars at its login, so if we suppressed
        -- first we would see zeroes and record nothing to restore. Letting
        -- it hand them back first means we capture the user's real values.
        -- Only ever on a genuinely empty config, and only once.
        local migrated, source, silenced
        if ns.dbWasFresh and ns.Profiles then
            local ok, err = pcall(function()
                migrated, source, silenced = ns.Profiles:MigrateFromLegacy()
            end)
            if not ok then
                migrated = false
                ns.Print("could not import the old FCT settings: " .. tostring(err))
            end
        end

        SuppressBlizzard()
        OnCombatTextUnitChanged()

        -- BuildAll is pcall'd deliberately. It is the one call here that
        -- touches user-supplied values (frame sizes, scale, strata), and if
        -- it threw, everything after it would be skipped - including the
        -- slash commands, leaving no way to fix the config from in game.
        if ns.Engine then
            local ok, err = pcall(ns.Engine.BuildAll, ns.Engine)
            if not ok then
                ns.Print("|cffff5555could not build the display frames:|r " .. tostring(err))
                ns.Print("run |cffffff00/jct reset|r to get back to a working configuration.")
            end
        end
        if ns.Nameplates then ns.Nameplates:Enable() end
        if ns.Events then ns.Events:Enable() end
        if ns.Options then ns.Options:Init() end
        print("|cff7fbfffJabe's Combat Text|r loaded. Type |cffffff00/jct|r for options.")

        if migrated then
            ns.Print("imported your settings from " .. tostring(source)
                .. ", and saved them as the profile |cffffff00Imported from FCT|r.")
            if silenced then
                ns.Print("the old FCT addon has been silenced for this session - "
                    .. "untick it in the AddOns list and you are done.")
            end
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateGUIDs()
        UpdateTarget()
        UpdateFocus()
        SuppressBlizzard()
        OnCombatTextUnitChanged()

    elseif event == "CVAR_UPDATE" then
        if suppressing then return end
        if type(arg1) == "string" and arg1:find("loatingCombatText") then
            SuppressBlizzard()
        end

    elseif event == "UNIT_PET" then
        if arg1 == "player" then UpdateGUIDs() end

    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.inCombat = false
        wipe(ns.myGuardians)
        if ns.Events then ns.Events:OnCombatState(false) end

    elseif event == "PLAYER_REGEN_DISABLED" then
        ns.inCombat = true
        if ns.Events then ns.Events:OnCombatState(true) end
    end
end)

--------------------------------------------------------------------------
-- Public helpers
--------------------------------------------------------------------------

function ns.Print(msg)
    print("|cff7fbfffJCT|r: " .. tostring(msg))
end

function ns.ApplyAll()
    if ns.Engine then ns.Engine:BuildAll() end
    if ns.Options and ns.Options.Refresh then ns.Options:Refresh() end
end
