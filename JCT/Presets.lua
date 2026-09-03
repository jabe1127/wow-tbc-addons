--[[--------------------------------------------------------------------------
    JCT - Presets.lua
    Layout presets. A preset only touches frame geometry / animation and the
    class -> frame routing table. It never overwrites your font family,
    colours or filters, so you can switch layouts without losing your tuning.

    Every preset must define every frame and route every class, otherwise a
    class could end up pointing at a disabled frame and its messages would
    vanish silently. Presets:Verify() checks exactly that.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

local Presets = {}
ns.Presets = Presets

Presets.order = { "columns", "classic", "weave", "minimal", "nameplate" }

--------------------------------------------------------------------------
-- Small helper so the tables below stay readable
--------------------------------------------------------------------------

local function F(enabled, x, y, w, h, anim, curve, align, maxLines, fontSize, iconSide, stagger, anchor, npOffsetY)
    return {
        enabled   = enabled,
        anchor    = anchor or "screen",
        npOffsetY = npOffsetY or 34,
        x         = x,
        y         = y,
        width     = w,
        height    = h,
        animation = anim,
        curve     = curve,
        align     = align,
        maxLines  = maxLines,
        fontSize  = fontSize,      -- nil means inherit from General
        iconSide  = iconSide,
        stagger   = stagger or 0,
    }
end

local OFF = F(false, 0, 0, 150, 200, "up", "right", "CENTER", 8, nil, "NONE", 0, "screen", 34)

local function off()
    local t = {}
    for k, v in pairs(OFF) do t[k] = v end
    return t
end

--------------------------------------------------------------------------
-- Definitions
--------------------------------------------------------------------------

Presets.list = {

    -----------------------------------------------------------------
    -- COLUMNS: separate boxes per stream, xCT+ style. Each kind of
    -- information owns a fixed piece of screen, so you learn where to
    -- look instead of reading one mixed stream.
    -----------------------------------------------------------------
    columns = {
        label = "Columns",
        description = "Separate boxes for outgoing, crits, pet, incoming, healing, power and notifications. Every stream has its own fixed spot on screen.",
        frames = {
            outgoing = F(true,   280,  -20, 180, 340, "up",   "right", "LEFT",   14, nil, "LEFT",  0),
            crit     = F(true,   190,  150, 240, 170, "up",   "right", "CENTER",  6, 32,  "LEFT", 10),
            melee    = off(),
            ranged   = off(),
            pet      = F(true,   470,  -20, 150, 260, "up",   "right", "LEFT",   10, 18,  "LEFT",  0),
            incoming = F(true,  -280,  -20, 200, 320, "up",   "left",  "RIGHT",  12, nil, "RIGHT", 0),
            healing  = F(true,  -480,  -20, 160, 260, "up",   "left",  "RIGHT",  10, 18,  "RIGHT", 0),
            power    = F(true,     0, -190, 180, 120, "up",   "right", "CENTER",  5, 17,  "NONE",  0),
            notify   = F(true,     0,  215, 440, 120, "down", "right", "CENTER",  5, 20,  "LEFT",  0),
            enemy    = F(true,     0,  330, 470, 130, "down", "right", "CENTER",  5, 22,  "LEFT",  0),
        },
        routing = {
            outDamage = "outgoing", outMelee = "outgoing", outAutoShot = "outgoing",
            outCrit   = "crit",     outDot   = "outgoing",
            outHeal   = "healing",  outHealCrit = "crit",  outMiss = "outgoing",
            petDamage = "pet",      petCrit  = "pet",      petHeal = "pet", petMiss = "pet",
            inDamage  = "incoming", inCrit   = "incoming", inHeal  = "healing", inMiss = "incoming",
            power     = "power",    notify   = "notify",   reactive = "notify",
            state     = "notify",
            enemy     = "enemy",    enemyBreak = "enemy",
        },
    },

    -----------------------------------------------------------------
    -- CLASSIC: the familiar two arcs either side of your character,
    -- the shape Blizzard uses, but with your font, your colours and
    -- real control over speed and position.
    -----------------------------------------------------------------
    classic = {
        label = "Classic arcs",
        description = "The familiar Blizzard shape: everything you do arcs up the right of your character, everything done to you up the left. Restyled and repositionable.",
        frames = {
            outgoing = F(true,   150,  -60, 130, 420, "fountain", "right", "LEFT",  16, nil, "NONE", 0),
            crit     = off(),
            melee    = off(),
            ranged   = off(),
            pet      = off(),
            incoming = F(true,  -150,  -60, 130, 420, "fountain", "left",  "RIGHT", 16, nil, "NONE", 0),
            healing  = off(),
            power    = F(true,     0, -150, 180, 110, "up",       "right", "CENTER", 4, 17, "NONE", 0),
            notify   = F(true,     0,  200, 440, 110, "down",     "right", "CENTER", 4, 20, "LEFT", 0),
            enemy    = F(true,     0,  310, 470, 120, "down",     "right", "CENTER", 4, 22, "LEFT", 0),
        },
        routing = {
            outDamage = "outgoing", outMelee = "outgoing", outAutoShot = "outgoing",
            outCrit   = "outgoing", outDot   = "outgoing",
            outHeal   = "outgoing", outHealCrit = "outgoing", outMiss = "outgoing",
            petDamage = "outgoing", petCrit  = "outgoing", petHeal = "outgoing", petMiss = "outgoing",
            inDamage  = "incoming", inCrit   = "incoming", inHeal  = "incoming", inMiss = "incoming",
            power     = "power",    notify   = "notify",   reactive = "notify",
            state     = "notify",
            enemy     = "enemy",    enemyBreak = "enemy",
        },
    },

    -----------------------------------------------------------------
    -- WEAVE: built for reading your own attack rhythm. Melee swings and
    -- Auto Shot get small dedicated frames close to your character, so
    -- the two alternate positionally as well as by colour. Abilities
    -- and crits stay out to the right where they do not interfere.
    -----------------------------------------------------------------
    weave = {
        label = "Weave (melee + shot timing)",
        description = "Melee swings and Auto Shot get their own small frames either side of your character so the alternation reads at a glance, and neither ever merges. Abilities, crits and pet damage stay out to the right.",
        frames = {
            outgoing = F(true,   300,  -20, 170, 300, "up",   "right", "LEFT",   12, 20,  "LEFT",  0),
            crit     = F(true,   230,  170, 240, 150, "up",   "right", "CENTER",  5, 30,  "NONE",  8),
            melee    = F(true,   140, -140, 130, 210, "up",   "right", "CENTER",  5, 24,  "NONE",  0),
            ranged   = F(true,  -140, -140, 130, 210, "up",   "left",  "CENTER",  5, 24,  "NONE",  0),
            pet      = F(true,   480,  -20, 150, 240, "up",   "right", "LEFT",    8, 16,  "NONE",  0),
            incoming = F(true,  -300,  -20, 180, 300, "up",   "left",  "RIGHT",  10, 20,  "NONE",  0),
            healing  = F(true,  -480,  -20, 150, 220, "up",   "left",  "RIGHT",   8, 18,  "NONE",  0),
            power    = F(true,     0, -230, 180, 110, "up",   "right", "CENTER",  4, 17,  "NONE",  0),
            notify   = F(true,     0,  230, 440, 120, "down", "right", "CENTER",  5, 22,  "LEFT",  0),
            enemy    = F(true,     0,  345, 470, 130, "down", "right", "CENTER",  5, 22,  "LEFT",  0),
        },
        routing = {
            outDamage = "outgoing", outMelee = "melee",    outAutoShot = "ranged",
            outCrit   = "crit",     outDot   = "outgoing",
            outHeal   = "healing",  outHealCrit = "crit",  outMiss = "outgoing",
            petDamage = "pet",      petCrit  = "pet",      petHeal = "pet", petMiss = "pet",
            inDamage  = "incoming", inCrit   = "incoming", inHeal  = "healing", inMiss = "incoming",
            power     = "power",    notify   = "notify",   reactive = "notify",
            state     = "notify",
            enemy     = "enemy",    enemyBreak = "enemy",
        },
        -- Crits stay in the stream they came from, so a melee crit is still
        -- a melee-coloured number in the melee box, just bigger.
        general = { critsOwnStream = false },
    },

    -----------------------------------------------------------------
    -- MINIMAL: two tight columns and nothing else.
    -----------------------------------------------------------------
    minimal = {
        label = "Minimal",
        description = "Two tight columns and nothing else. Your damage right, damage taken left, everything else folded in.",
        frames = {
            outgoing = F(true,   230,    0, 160, 260, "up",   "right", "LEFT",   8, 20, "NONE", 0),
            crit     = off(),
            melee    = off(),
            ranged   = off(),
            pet      = off(),
            incoming = F(true,  -230,    0, 160, 260, "up",   "left",  "RIGHT",  8, 20, "NONE", 0),
            healing  = off(),
            power    = off(),
            notify   = F(true,     0,  190, 400, 100, "down", "right", "CENTER", 3, 18, "NONE", 0),
            enemy    = off(),
        },
        routing = {
            outDamage = "outgoing", outMelee = "outgoing", outAutoShot = "outgoing",
            outCrit   = "outgoing", outDot   = "outgoing",
            outHeal   = "outgoing", outHealCrit = "outgoing", outMiss = "outgoing",
            petDamage = "outgoing", petCrit  = "outgoing", petHeal = "outgoing", petMiss = "outgoing",
            inDamage  = "incoming", inCrit   = "incoming", inHeal  = "incoming", inMiss = "incoming",
            power     = "outgoing", notify   = "notify",   reactive = "notify",
            state     = "notify",
            enemy     = "notify",   enemyBreak = "notify",
        },
    },

    -----------------------------------------------------------------
    -- NAMEPLATE: the shape Blizzard uses. Your damage floats up from
    -- whatever you hit, damage taken floats up from whatever hit you,
    -- and enemy cooldowns appear over the enemy who used them.
    --
    -- Frames in this mode ignore their x/y: each message is positioned
    -- from the unit it concerns, and follows that unit as it moves.
    -----------------------------------------------------------------
    nameplate = {
        label = "Over the target (Blizzard-style)",
        description = "Numbers float up from the unit they belong to and follow it as it moves, the way Blizzard's own combat text does - but with your font, colours, filtering and merging. Needs nameplates turned on; anything without a nameplate falls back to a fixed position.",
        frames = {
            outgoing = F(true,   250,  -20, 140, 110, "up",   "right", "CENTER", 10, nil, "NONE", 12, "nameplate", 62),
            crit     = F(true,   190,  140, 150, 130, "up",   "right", "CENTER",  6, 30,  "NONE", 14, "nameplate", 92),
            melee    = off(),
            ranged   = off(),
            pet      = F(true,   430,  -20, 130, 100, "up",   "right", "CENTER",  8, 17,  "NONE", 16, "nameplate", 8),
            incoming = F(true,  -250,  -20, 140, 110, "up",   "left",  "CENTER", 10, nil, "NONE", 12, "nameplate", 34),
            healing  = F(true,  -430,  -20, 140, 110, "up",   "right", "CENTER",  8, 18,  "NONE", 12, "nameplate", 20),
            power    = F(true,     0, -190, 180, 120, "up",   "right", "CENTER",  5, 17,  "NONE",  0),
            notify   = F(true,     0,  215, 440, 120, "down", "right", "CENTER",  5, 20,  "LEFT",  0),
            enemy    = F(true,     0,  300, 260, 100, "up",   "right", "CENTER",  4, 20,  "NONE",  0, "nameplate", 124),
        },
        routing = {
            outDamage = "outgoing", outMelee = "outgoing", outAutoShot = "outgoing",
            outCrit   = "crit",     outDot   = "outgoing",
            outHeal   = "healing",  outHealCrit = "crit",  outMiss = "outgoing",
            petDamage = "pet",      petCrit  = "pet",      petHeal = "pet", petMiss = "pet",
            inDamage  = "incoming", inCrit   = "incoming", inHeal  = "healing", inMiss = "incoming",
            power     = "power",    notify   = "notify",   reactive = "notify",
            state     = "notify",
            enemy     = "enemy",    enemyBreak = "enemy",
        },
    },
}

--------------------------------------------------------------------------
-- Application
--------------------------------------------------------------------------

function Presets:Apply(name)
    local preset = Presets.list[name]
    if not preset then
        if ns.Print then ns.Print("unknown preset '" .. tostring(name) .. "'") end
        return false
    end
    local db = ns.db
    if not db then return false end

    for frameName, values in pairs(preset.frames) do
        local target = db.frames[frameName]
        if not target then
            target = ns.deepCopy(ns.defaults.frames[frameName] or ns.defaults.frames.outgoing)
            db.frames[frameName] = target
        end
        for k, v in pairs(values) do
            target[k] = v
        end
        -- A key absent from the preset table means "inherit from General".
        if values.fontSize == nil then target.fontSize = nil end
        if values.duration == nil then target.duration = nil end
        if values.anchor == nil then target.anchor = "screen" end
    end

    for classKey, frameName in pairs(preset.routing) do
        db.routing[classKey] = frameName
    end

    if preset.general then
        for k, v in pairs(preset.general) do
            db.general[k] = v
        end
    end

    db.preset = name
    if ns.ApplyAll then ns.ApplyAll() end
    return true
end

function Presets:Get(name)
    return Presets.list[name]
end

--------------------------------------------------------------------------
-- Self-check: no class may route to a frame the preset disabled, and every
-- class must be routed. Run with /jct verify.
--------------------------------------------------------------------------

function Presets:Verify()
    local problems = 0
    for presetName, preset in pairs(Presets.list) do
        for i = 1, #ns.CLASSES do
            local key = ns.CLASSES[i].key
            local target = preset.routing[key]
            if not target then
                ns.Print(presetName .. ": class '" .. key .. "' is not routed anywhere")
                problems = problems + 1
            else
                local frame = preset.frames[target]
                if not frame then
                    ns.Print(presetName .. ": class '" .. key .. "' routes to unknown frame '" .. target .. "'")
                    problems = problems + 1
                elseif not frame.enabled then
                    ns.Print(presetName .. ": class '" .. key .. "' routes to disabled frame '" .. target .. "'")
                    problems = problems + 1
                end
            end
        end
        for i = 1, #ns.FRAME_ORDER do
            if preset.frames[ns.FRAME_ORDER[i]] == nil then
                ns.Print(presetName .. ": missing frame definition '" .. ns.FRAME_ORDER[i] .. "'")
                problems = problems + 1
            end
        end
    end
    if problems == 0 then ns.Print("all presets verified clean.") end
    return problems
end
