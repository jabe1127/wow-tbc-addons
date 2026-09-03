--[[--------------------------------------------------------------------------
    JCT - Profiles.lua
    Named, account-wide configuration snapshots.

    JCT_Profiles is a separate saved variable from JCT_DB, so a profile
    survives anything that happens to the active config - including Reset.
    Because it is account-wide rather than per-character, a profile saved on
    one character can be loaded on any other.

    ns.db is never replaced, only emptied and refilled in place. Every module
    holds a reference to that table, so swapping it for a different one would
    leave half the addon pointed at the old config.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

local Profiles = {}
ns.Profiles = Profiles

-- Keys not worth carrying in a profile: session noise that would bloat every
-- snapshot without meaning anything on another character.
local function stripVolatile(t)
    if t.filters then
        t.filters.seenSpells = nil
        t.filters.seenCount = nil
    end
    return t
end

local function store()
    if type(_G.JCT_Profiles) ~= "table" then _G.JCT_Profiles = {} end
    return _G.JCT_Profiles
end

function Profiles:List()
    local out = {}
    for name in pairs(store()) do out[#out + 1] = name end
    table.sort(out, function(a, b) return a:lower() < b:lower() end)
    return out
end

function Profiles:Exists(name)
    return store()[name] ~= nil
end

function Profiles:Count()
    local n = 0
    for _ in pairs(store()) do n = n + 1 end
    return n
end

-- Returns true, or false plus a reason.
function Profiles:Save(name)
    if type(name) ~= "string" then return false, "no name given" end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return false, "no name given" end
    if #name > 40 then return false, "name is too long" end
    if not ns.db then return false, "settings are not loaded yet" end

    local snapshot = stripVolatile(ns.deepCopy(ns.db))
    snapshot.initialised = nil
    snapshot.currentProfile = nil   -- otherwise every profile carries the
                                    -- name of whatever was loaded before it
    snapshot.savedCVars = nil       -- belongs to this machine, not a profile
    store()[name] = snapshot
    ns.db.currentProfile = name
    return true, name
end

function Profiles:Load(name)
    local snapshot = store()[name]
    if not snapshot then return false, "no profile called '" .. tostring(name) .. "'" end
    if not ns.db then return false, "settings are not loaded yet" end

    -- Keep the seen-spell list: it is a record of what this character has
    -- actually met in combat, not a setting, so a profile should not wipe it.
    -- savedCVars likewise - it is the only record of what Blizzard's combat
    -- text settings were before we took them over.
    local seen = ns.db.filters and ns.db.filters.seenSpells
    local seenCount = ns.db.filters and ns.db.filters.seenCount
    local cvars = ns.db.savedCVars

    wipe(ns.db)
    for k, v in pairs(ns.deepCopy(snapshot)) do ns.db[k] = v end
    ns.fill(ns.db, ns.defaults)

    if seen then
        ns.db.filters.seenSpells = seen
        ns.db.filters.seenCount = seenCount
    end
    if type(cvars) == "table" then ns.db.savedCVars = cvars end
    ns.db.initialised = true
    ns.db.currentProfile = name

    ns.ApplyAll()

    -- Settings that live outside the frame rebuild have to be re-applied by
    -- hand, or the UI would say one thing while the game did another.
    if ns.db.suppressBlizzard then ns.SuppressBlizzard() else ns.RestoreBlizzard() end
    if ns.ApplyWindowGeometry then ns.ApplyWindowGeometry() end

    return true
end

function Profiles:Delete(name)
    if not store()[name] then return false, "no profile called '" .. tostring(name) .. "'" end
    store()[name] = nil
    if ns.db and ns.db.currentProfile == name then ns.db.currentProfile = nil end
    return true
end

-- Save under a name that does not collide with an existing profile, used for
-- the automatic snapshot taken before anything destructive.
function Profiles:SaveAuto(baseName)
    local name = baseName
    local n = 2
    while store()[name] and n <= 200 do
        name = baseName .. " " .. n
        n = n + 1
    end
    -- Rather than overwrite someone's 200th backup, refuse.
    if store()[name] then return nil end
    -- Save returns the trimmed name it actually stored under, which is what
    -- we must report - otherwise a message can name a key that does not exist.
    local ok, stored = self:Save(name)
    return ok and stored or nil
end

--------------------------------------------------------------------------
-- Migration from the FCT-era addon
--
-- WoW names a saved-variables file after the addon FOLDER, so renaming the
-- folder orphans the old file. But if the old addon is still installed and
-- enabled, its saved variables are loaded into memory as usual and we can
-- simply read them - no file surgery required.
--
-- Two sources are checked, in order of reliability:
--   1. _G.FCT.db     - the old addon's live config table
--   2. _G.FCT_DB     - its saved variable, declared in our own TOC so it
--                      also resolves if the WTF file WAS renamed by hand
--------------------------------------------------------------------------

-- Deliberately strict. A half-recognised table would be copied over the live
-- config and then hit SetSize/SetFrameStrata with whatever it contained.
local function looksLikeConfig(t)
    if type(t) ~= "table" then return false end
    if type(t.frames) ~= "table" or type(t.general) ~= "table" then return false end
    if type(t.routing) ~= "table" or type(t.colors) ~= "table" then return false end
    if type(t.general.fontSize) ~= "number" then return false end
    -- At least one frame has to carry plausible geometry.
    for _, f in pairs(t.frames) do
        if type(f) == "table" and type(f.x) == "number" and type(f.y) == "number"
           and type(f.width) == "number" and type(f.height) == "number" then
            return true
        end
    end
    return false
end

-- Scrub anything that would reach a widget call with a value it rejects.
--
-- Type checking alone is not enough. fill() only adds missing keys, it never
-- corrects an existing one, so a config carrying scale = 0 or an unknown
-- frame strata reaches SetScale/SetFrameStrata in Engine:BuildFrame and
-- throws - and because BuildAll runs at login BEFORE slash commands are
-- registered, that would leave no way to undo the import from inside the
-- game. Everything below is therefore range-checked, not just type-checked.

local VALID = {
    strata   = { BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true,
                 DIALOG = true, FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true },
    animation = { up = true, down = true, fountain = true, horizontal = true, static = true,
                  gravity = true, diagonal = true, burst = true, wobble = true, bounce = true },
    curve    = { left = true, right = true, alternate = true },
    align    = { LEFT = true, CENTER = true, RIGHT = true },
    iconSide = { LEFT = true, RIGHT = true, NONE = true },
    outline  = { [""] = true, OUTLINE = true, THICKOUTLINE = true, MONOCHROME = true,
                 ["OUTLINE, MONOCHROME"] = true, ["THICKOUTLINE, MONOCHROME"] = true },
    anchor   = { screen = true, nameplate = true },
}

-- key -> { min, max }
local FRAME_RANGE = {
    x        = { -5000, 5000 },
    y        = { -5000, 5000 },
    width    = { 20, 2000 },
    height   = { 20, 2000 },
    scale    = { 0.2, 3 },
    maxLines = { 1, 60 },
    stagger  = { 0, 200 },
    fontSize = { 4, 64 },
    duration = { 0.1, 30 },
    fadeTime = { 0, 30 },
    npOffsetX = { -600, 600 },
    npOffsetY = { 0, 400 },
}

local GENERAL_RANGE = {
    fontSize  = { 4, 64 },
    duration  = { 0.1, 30 },
    fadeStart = { 0.05, 1 },
    critScale = { 0.5, 5 },
    alpha     = { 0.05, 1 },
}

-- Drops the key entirely when it is out of range, so fill() restores the
-- default rather than the addon running on a nonsense value.
local function checkNumber(t, key, range)
    local v = t[key]
    if v == nil then return end
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge
       or v < range[1] or v > range[2] then
        t[key] = nil
    end
end

local function checkEnum(t, key, set)
    local v = t[key]
    if v ~= nil and (type(v) ~= "string" or not set[v]) then t[key] = nil end
end

local function clampColorTable(t)
    if type(t) ~= "table" then return end
    for i = 1, 3 do
        local v = t[i]
        if type(v) ~= "number" or v ~= v then
            t[i] = nil
        elseif v < 0 then t[i] = 0
        elseif v > 1 then t[i] = 1 end
    end
end

local function sanitise(cfg)
    local g = cfg.general
    if type(g) ~= "table" then g = {}; cfg.general = g end
    if type(g.font) ~= "string" then g.font = nil end
    checkEnum(g, "strata", VALID.strata)
    checkEnum(g, "outline", VALID.outline)
    for key, range in pairs(GENERAL_RANGE) do checkNumber(g, key, range) end

    if type(cfg.frames) == "table" then
        for name, f in pairs(cfg.frames) do
            if type(f) ~= "table" then
                cfg.frames[name] = nil
            else
                for key, range in pairs(FRAME_RANGE) do checkNumber(f, key, range) end
                checkEnum(f, "animation", VALID.animation)
                checkEnum(f, "curve", VALID.curve)
                checkEnum(f, "align", VALID.align)
                checkEnum(f, "iconSide", VALID.iconSide)
                checkEnum(f, "outline", VALID.outline)
                checkEnum(f, "anchor", VALID.anchor)
                if f.npFallback ~= nil then f.npFallback = f.npFallback and true or false end
                if f.font ~= nil and type(f.font) ~= "string" then f.font = nil end
            end
        end
    end

    if type(cfg.routing) == "table" then
        for class, frameName in pairs(cfg.routing) do
            if type(frameName) ~= "string" then cfg.routing[class] = nil end
        end
    end

    if type(cfg.colors) == "table" then
        for _, v in pairs(cfg.colors) do clampColorTable(v) end
    end
    if type(cfg.schoolColors) == "table" then
        for _, v in pairs(cfg.schoolColors) do clampColorTable(v) end
    end

    cfg.savedCVars = nil
    cfg.currentProfile = nil
    return cfg
end

-- Exposed so the import path can validate a decoded string with exactly the
-- same test the migration uses.
Profiles.LooksLikeConfig = looksLikeConfig
Profiles.Sanitise = sanitise

-- Overwrite the live settings with a config table from anywhere - an import
-- string, a migration - and save it under a profile name so it is never lost.
function Profiles:ApplyConfig(cfg, profileName)
    if not looksLikeConfig(cfg) then return false, "that is not a valid configuration" end
    if not ns.db then return false, "settings are not loaded yet" end

    local clean = sanitise(ns.deepCopy(cfg))

    -- Things that belong to this machine and this character rather than to
    -- the imported settings. savedCVars especially: it is the only record of
    -- what Blizzard's combat text CVars were before we took them over, so
    -- losing it would make "Take over Blizzard's combat text" impossible to
    -- switch back off, permanently.
    local seen      = ns.db.filters and ns.db.filters.seenSpells
    local seenCount = ns.db.filters and ns.db.filters.seenCount
    local ui        = ns.deepCopy(ns.db.ui or ns.defaults.ui)
    local cvars     = ns.db.savedCVars

    -- Full rollback copy: if applying throws, the user is left exactly where
    -- they were rather than with a half-written config they cannot escape.
    local rollback = ns.deepCopy(ns.db)

    wipe(ns.db)
    for k, v in pairs(clean) do ns.db[k] = v end
    -- Repairs anything sanitise had to remove outright.
    ns.fill(ns.db, ns.defaults)

    if seen then
        ns.db.filters.seenSpells = seen
        ns.db.filters.seenCount = seenCount
    end
    ns.db.ui = ui
    if type(cvars) == "table" then ns.db.savedCVars = cvars end
    ns.db.initialised = true

    local ok, err = pcall(ns.ApplyAll)
    if not ok then
        wipe(ns.db)
        for k, v in pairs(rollback) do ns.db[k] = v end
        pcall(ns.ApplyAll)
        return false, "that configuration could not be applied (" .. tostring(err)
                      .. "). Nothing was changed."
    end

    if profileName then
        local stored = self:SaveAuto(profileName)
        ns.db.currentProfile = stored
    end

    if ns.db.suppressBlizzard then ns.SuppressBlizzard() else ns.RestoreBlizzard() end
    return true
end

function Profiles:FindLegacyConfig()
    local legacy = _G.FCT and _G.FCT.db
    if looksLikeConfig(legacy) then return legacy, "the running FCT addon" end
    -- Not declared in our TOC on purpose: declaring another addon's saved
    -- variable makes WoW write OUR copy into THEIR file at logout, which
    -- would destroy the very settings we are trying to rescue. This branch
    -- only fires if something else has already put the global there.
    if looksLikeConfig(_G.FCT_DB) then return _G.FCT_DB, "the FCT saved variables" end
    return nil
end

-- Stops the old addon drawing over the top of us for the rest of the session,
-- so both can be enabled at once without seeing double.
--
-- Its persisted config is left untouched. Silencing happens at the event
-- layer instead, so if the user ever goes back to FCT it behaves normally.
function Profiles:SilenceLegacy()
    local old = _G.FCT
    if not old then return false end

    -- Its Core driver frame is the important one: it holds CVAR_UPDATE, and
    -- its CVar suppression is gated on suppressBlizzard rather than enabled.
    -- Leave it registered and the two addons fight over the combat text
    -- CVars for the rest of the session.
    if old.eventFrame then pcall(old.eventFrame.UnregisterAllEvents, old.eventFrame) end
    if old.Events and old.Events.Disable then pcall(old.Events.Disable, old.Events) end
    if old.Engine and old.Engine.ClearAll then pcall(old.Engine.ClearAll, old.Engine) end

    -- Hand the CVars back before we take them over. The old addon zeroed
    -- them at its own login, which means our SuppressBlizzard saw zeroes and
    -- recorded nothing to restore. Letting it undo its work first means we
    -- capture the user's real values.
    if old.RestoreBlizzard then pcall(old.RestoreBlizzard) end

    return true
end

function Profiles:MigrateFromLegacy()
    local legacy, source = self:FindLegacyConfig()
    if not legacy then return false end

    -- Build and validate a candidate BEFORE touching the live table, so a
    -- failure part way through cannot leave the saved variables half-written.
    local candidate = sanitise(stripVolatile(ns.deepCopy(legacy)))
    if not looksLikeConfig(candidate) then return false end

    local seen = ns.db.filters and ns.db.filters.seenSpells

    wipe(ns.db)
    for k, v in pairs(candidate) do ns.db[k] = v end
    ns.fill(ns.db, ns.defaults)
    if seen then ns.db.filters.seenSpells = seen end
    ns.db.initialised = true

    -- Keep a copy so the import survives even a Reset.
    self:Save("Imported from FCT")
    ns.db.currentProfile = "Imported from FCT"

    local silenced = self:SilenceLegacy()
    ns.ApplyAll()
    return true, source, silenced
end
