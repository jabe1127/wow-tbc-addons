--[[--------------------------------------------------------------------------
    JCT - SpellData.lua
    Curated enemy-ability alert list and reactive-ability definitions.

    Why this matches on NAME rather than ID
    ---------------------------------------
    In TBC every rank of a spell has its own ID. Listing one ID per spell and
    matching on that ID would miss every other rank - a silent no-op that is
    miserable to debug in game. Instead, at login each ID below is resolved to
    its localised name once, and matching happens by name. So a single correct
    ID per spell covers every rank, on every locale, and a wrong ID fails
    loudly (it shows up in /jct spells as unresolved) instead of quietly.

    IDs verified against TBC PvP addon source (Gladdy TBC / TBC Anniversary,
    OmniBar TBC, ArenaLive-TBC) and cross-checked against the TBC databases.
    A handful are marked UNVERIFIED below; run /jct spells in game to see
    whether any of them failed to resolve.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

local strlower = string.lower

--------------------------------------------------------------------------
-- Categories
--
--   break  - frees them from your control, or makes them immune to it.
--            The one you want to see instantly: your trap/fear just died.
--   cc     - crowd control and interrupts they cast
--   cd     - major offensive/defensive cooldowns
--   racial - racial abilities
--------------------------------------------------------------------------

ns.ENEMY_CATEGORIES = {
    { key = "break",  label = "CC breaks and immunities" },
    { key = "cc",     label = "Crowd control and interrupts" },
    { key = "cd",     label = "Major cooldowns" },
    { key = "racial", label = "Racials" },
}

-- { spellID, category }
-- Rank does not matter; one correct ID per spell is enough.
ns.ENEMY_SPELLS = {

    ---------------------------------------------------------------- break
    { 42292, "break" },   -- PvP Trinket (shared by every Insignia/Medallion)
    {  7744, "break" },   -- Will of the Forsaken
    { 20589, "break" },   -- Escape Artist
    { 20594, "break" },   -- Stoneform
    {  1044, "break" },   -- Blessing of Freedom
    { 10278, "break" },   -- Blessing of Protection
    {   642, "break" },   -- Divine Shield
    { 45438, "break" },   -- Ice Block
    { 31224, "break" },   -- Cloak of Shadows
    { 23920, "break" },   -- Spell Reflection

    ------------------------------------------------------------------- cc
    { 14309, "cc" },      -- Freezing Trap Effect (the trap actually landing)
    { 14311, "cc" },      -- Freezing Trap (the trap being dropped)
    { 27068, "cc" },      -- Wyvern Sting
    { 19503, "cc" },      -- Scatter Shot
    { 19577, "cc" },      -- Intimidation
    {  8122, "cc" },      -- Psychic Scream
    { 15487, "cc" },      -- Silence
    {  5782, "cc" },      -- Fear
    { 17928, "cc" },      -- Howl of Terror
    { 30414, "cc" },      -- Shadowfury
    { 27223, "cc" },      -- Death Coil
    { 10308, "cc" },      -- Hammer of Justice
    { 20066, "cc" },      -- Repentance
    { 33786, "cc" },      -- Cyclone
    { 26989, "cc" },      -- Entangling Roots
    {  8983, "cc" },      -- Bash
    { 45334, "cc" },      -- Feral Charge Effect
    {  2139, "cc" },      -- Counterspell
    { 25454, "cc" },      -- Earth Shock (the shaman interrupt in TBC)
    {  8177, "cc" },      -- Grounding Totem
    {  8143, "cc" },      -- Tremor Totem

    ------------------------------------------------------------------- cd
    -- Warrior
    {  1719, "cd" },      -- Recklessness
    {   871, "cd" },      -- Shield Wall
    { 20230, "cd" },      -- Retaliation
    { 12292, "cd" },      -- Death Wish
    { 12975, "cd" },      -- Last Stand
    { 18499, "cd" },      -- Berserker Rage
    { 20252, "cd" },      -- Intercept
    -- Rogue
    { 13750, "cd" },      -- Adrenaline Rush
    { 13877, "cd" },      -- Blade Flurry
    { 26669, "cd" },      -- Evasion
    { 14185, "cd" },      -- Preparation
    { 26889, "cd" },      -- Vanish
    { 14177, "cd" },      -- Cold Blood
    { 11305, "cd" },      -- Sprint
    -- Hunter
    { 19574, "cd" },      -- Bestial Wrath
    { 34471, "cd" },      -- The Beast Within
    {  3045, "cd" },      -- Rapid Fire
    { 19263, "cd" },      -- Deterrence
    {  5384, "cd" },      -- Feign Death
    { 23989, "cd" },      -- Readiness
    -- Mage
    {    66, "cd" },      -- Invisibility
    { 12043, "cd" },      -- Presence of Mind
    { 12042, "cd" },      -- Arcane Power
    { 12472, "cd" },      -- Icy Veins
    { 11129, "cd" },      -- Combustion
    {  1953, "cd" },      -- Blink
    -- Warlock
    { 18708, "cd" },      -- Fel Domination
    { 29858, "cd" },      -- Soulshatter (threat drop, not a CC break)
    -- Priest
    { 10060, "cd" },      -- Power Infusion
    { 33206, "cd" },      -- Pain Suppression
    {  6346, "cd" },      -- Fear Ward
    { 15473, "cd" },      -- Shadowform
    { 14751, "cd" },      -- Inner Focus
    { 32375, "cd" },      -- Mass Dispel        UNVERIFIED
    -- Paladin
    {  5573, "cd" },      -- Divine Protection
    { 31884, "cd" },      -- Avenging Wrath
    {  4987, "cd" },      -- Cleanse            UNVERIFIED
    -- Druid
    { 22812, "cd" },      -- Barkskin
    { 17116, "cd" },      -- Nature's Swiftness (druid)
    { 29166, "cd" },      -- Innervate
    { 16979, "cd" },      -- Feral Charge
    -- Shaman
    {  2825, "cd" },      -- Bloodlust
    { 32182, "cd" },      -- Heroism
    { 16188, "cd" },      -- Nature's Swiftness (shaman)
    { 16166, "cd" },      -- Elemental Mastery

    --------------------------------------------------------------- racial
    { 20600, "racial" },  -- Perception
    { 20572, "racial" },  -- Blood Fury (melee)
    { 33697, "racial" },  -- Blood Fury (hybrid)
    { 33702, "racial" },  -- Blood Fury (caster)
    { 26297, "racial" },  -- Berserking
    { 20549, "racial" },  -- War Stomp
    { 20580, "racial" },  -- Shadowmeld
    { 28730, "racial" },  -- Arcane Torrent (mana)
    { 25046, "racial" },  -- Arcane Torrent (energy)
    { 28880, "racial" },  -- Gift of the Naaru
    { 20577, "racial" },  -- Cannibalize        UNVERIFIED
}

--------------------------------------------------------------------------
-- Reactive abilities
--
-- Detected from the combat log rather than from Blizzard's SPELL_ACTIVE
-- message, because that message rides on the very system JCT switches off.
--
-- trigger values:
--   selfParry       - you parried an incoming attack
--   selfDodge       - you dodged an incoming attack
--   selfAvoid       - you blocked, dodged or parried
--   targetDodge     - your target dodged your attack
--
-- Rank 1 IDs only: every rank you have trained stays known, so checking
-- rank 1 is enough to tell whether you have the ability at all.
--------------------------------------------------------------------------

ns.REACTIVES = {
    -- Nothing here is health-gated; see USABLE_ABILITIES below for those.
    { id = 19306, trigger = "selfParry",   class = "HUNTER"  },  -- Counterattack (Survival talent)
    { id =  1495, trigger = "selfDodge",   class = "HUNTER"  },  -- Mongoose Bite
    { id =  7384, trigger = "targetDodge", class = "WARRIOR" },  -- Overpower
    { id =  6572, trigger = "selfAvoid",   class = "WARRIOR" },  -- Revenge
    { id = 14251, trigger = "selfParry",   class = "ROGUE"   },  -- Riposte
}

--------------------------------------------------------------------------
-- Stances, aspects, forms, auras, seals and armours
--
-- Deliberately separate from the generic "buff you gained" branch, because
-- these behave differently in two ways that matter:
--
--   * They are states you CHOSE, so they are worth announcing out of
--     combat. Swapping Hawk for Viper, or Battle for Defensive, almost
--     always happens between pulls - which is exactly where the generic
--     buff branch goes quiet to avoid raid-buff spam.
--   * Losing one is an alarm rather than a notification. A dazed Cheetah,
--     an expired seal, a form you got knocked out of - each is a mistake
--     you want to notice, so the fade gets its own colour.
--
-- 'cat' groups mutually exclusive states. Swapping within a category is one
-- event, not two, so the fade of the old state is swallowed when a new one
-- from the same category lands right behind it. Entries with no cat are
-- standalone: their fade always shows.
--
-- Rank 1 IDs, matched by NAME at runtime so every rank collapses onto one
-- entry. Anything that fails to resolve is reported by /jct debug rather
-- than silently doing nothing.
--------------------------------------------------------------------------

ns.STATE_AURAS = {
    -- Hunter
    { id = 13165, cat = "aspect" },   -- Aspect of the Hawk
    { id = 13163, cat = "aspect" },   -- Aspect of the Monkey
    { id =  5118, cat = "aspect" },   -- Aspect of the Cheetah
    { id = 13159, cat = "aspect" },   -- Aspect of the Pack
    { id = 13161, cat = "aspect" },   -- Aspect of the Beast
    { id = 20043, cat = "aspect" },   -- Aspect of the Wild
    { id = 34074, cat = "aspect" },   -- Aspect of the Viper
    { id = 19506 },                   -- Trueshot Aura

    -- Warrior
    { id =  2457, cat = "stance" },   -- Battle Stance
    { id =    71, cat = "stance" },   -- Defensive Stance
    { id =  2458, cat = "stance" },   -- Berserker Stance

    -- Druid
    { id =  5487, cat = "form" },     -- Bear Form
    { id =  9634, cat = "form" },     -- Dire Bear Form
    { id =   768, cat = "form" },     -- Cat Form
    { id =   783, cat = "form" },     -- Travel Form
    { id =  1066, cat = "form" },     -- Aquatic Form
    { id = 24858, cat = "form" },     -- Moonkin Form
    { id = 33891, cat = "form" },     -- Tree of Life
    { id = 33943, cat = "form" },     -- Flight Form
    { id = 40120, cat = "form" },     -- Swift Flight Form
    { id =  5215 },                   -- Prowl

    -- Paladin
    { id =   465, cat = "palaura" },  -- Devotion Aura
    { id =  7294, cat = "palaura" },  -- Retribution Aura
    { id = 19746, cat = "palaura" },  -- Concentration Aura
    { id = 19876, cat = "palaura" },  -- Shadow Resistance Aura
    { id = 19888, cat = "palaura" },  -- Frost Resistance Aura
    { id = 19891, cat = "palaura" },  -- Fire Resistance Aura
    { id = 32223, cat = "palaura" },  -- Crusader Aura
    { id = 20154, cat = "seal" },     -- Seal of Righteousness
    { id = 20375, cat = "seal" },     -- Seal of Command
    { id = 21082, cat = "seal" },     -- Seal of the Crusader
    { id = 20164, cat = "seal" },     -- Seal of Justice
    { id = 20165, cat = "seal" },     -- Seal of Light
    { id = 20166, cat = "seal" },     -- Seal of Wisdom
    { id = 31892, cat = "seal" },     -- Seal of Blood
    { id = 31801, cat = "seal" },     -- Seal of Vengeance

    -- Rogue
    { id =  1784 },                   -- Stealth
    { id =  5171 },                   -- Slice and Dice

    -- Priest
    { id = 15473 },                   -- Shadowform
    { id =   588 },                   -- Inner Fire

    -- Shaman
    { id =  2645 },                   -- Ghost Wolf
    { id =   324, cat = "shshield" }, -- Lightning Shield
    { id = 24398, cat = "shshield" }, -- Water Shield
    { id =   974, cat = "shshield" }, -- Earth Shield

    -- Mage
    { id =   168, cat = "armor" },    -- Frost Armor
    { id =  7302, cat = "armor" },    -- Ice Armor
    { id =  6117, cat = "armor" },    -- Mage Armor
    { id = 30482, cat = "armor" },    -- Molten Armor
    { id =  1463 },                   -- Mana Shield
    { id = 11426 },                   -- Ice Barrier

    -- Warlock
    { id =   687, cat = "armor" },    -- Demon Skin
    { id =   706, cat = "armor" },    -- Demon Armor
    { id = 28176, cat = "armor" },    -- Fel Armor
    { id = 19028 },                   -- Soul Link
}

--------------------------------------------------------------------------
-- Conditional abilities that no combat log event announces
--
-- Execute and Hammer of Wrath open up when the target drops below 20%
-- health; Victory Rush opens for 20 seconds after a kill that grants
-- experience or honour. None of these produce a combat log event, so they
-- are detected from SPELL_UPDATE_USABLE instead.
--
-- Deliberately NOT done with health maths, for three reasons:
--   * In Classic, UnitHealth returns real values for NPCs but a 0-100
--     PERCENTAGE for enemy players, so a fraction has 1% granularity in PvP
--     and the alert would land up to 1% of max health early or late.
--   * The two tooltips disagree - Execute says "less than 20%", Hammer of
--     Wrath says "20% or less" - and whether the 2.5.6 server actually
--     distinguishes them is not something I can verify from outside.
--   * Victory Rush has no health condition at all, so it would need a
--     separate mechanism anyway. PARTY_KILL is the obvious candidate and
--     the wrong one: it also fires for grey mobs that grant nothing.
--
-- Asking the client whether the spell is usable sidesteps all three: the
-- server owns that answer. IsUsableSpell returns (usable, notEnoughPower),
-- and notEnoughPower true means the CONDITION is met but you are short on
-- rage - which is still worth telling you about.
--------------------------------------------------------------------------

ns.USABLE_ABILITIES = {
    { id =  5308, class = "WARRIOR" },  -- Execute
    { id = 34428, class = "WARRIOR" },  -- Victory Rush
    { id = 24275, class = "PALADIN" },  -- Hammer of Wrath
}

--------------------------------------------------------------------------
-- Runtime resolution
--------------------------------------------------------------------------

ns.enemyByName   = {}   -- [localised name] = { category, id }
ns.enemyResolved = {}   -- [id] = name        (for the options list)
ns.enemyUnresolved = {} -- array of ids that did not resolve
ns.activeReactives = {} -- [trigger] = { name, id }   only what you know
ns.activeUsable    = {} -- array of { name, id }     only what you know
-- [lowercase name] = id, for EVERY reactive whose name resolves, known or
-- not. Used to recognise Blizzard's own SPELL_ACTIVE announcement of an
-- ability JCT also derives itself, so the two do not both get displayed.
ns.reactiveByName  = {}
-- [lowercase name] = { cat = <group or nil>, id = <rank 1 id> }
-- Built for every state whose name resolves, regardless of class: you can
-- be given a state you did not cast, and matching by name costs nothing.
ns.stateByName     = {}
ns.unknownAbilities = {} -- ids that would not resolve to a name at all

local function knowsSpell(id, name, class)
    if IsSpellKnown then
        local ok, known = pcall(IsSpellKnown, id)
        if ok and known then return true end
    end
    -- Passing a NAME (rather than an ID) to GetSpellInfo queries your
    -- spellbook, so a nil result means you do not have it. Used as a
    -- fallback when IsSpellKnown is unavailable.
    if name and _G.GetSpellInfo then
        local ok, found = pcall(_G.GetSpellInfo, name)
        if ok and found then return true end
    end
    -- Neither API reachable: fall back to class rather than silently
    -- deciding you know nothing. Better a spurious entry than a missing one.
    if class and not IsSpellKnown and not _G.GetSpellInfo then
        local _, playerClass = UnitClass("player")
        return class == playerClass
    end
    return false
end

local lastBuild = 0
local pendingBuild = false

ns.spellDataVersion = 0

function ns.BuildSpellData(force)
    -- SPELLS_CHANGED arrives in bursts and resolving ~90 spell names is not
    -- free, so throttle. The throttle has to be TRAILING, not leading: the
    -- last event of a burst is the one carrying the final spellbook, so a
    -- leading-only throttle would permanently miss a talent point spent
    -- within the window and Counterattack would never be detected.
    local now = GetTime and GetTime() or 0
    if not force and lastBuild > 0 and (now - lastBuild) < 2 then
        if not pendingBuild and C_Timer and C_Timer.After then
            pendingBuild = true
            C_Timer.After(2.5, function()
                pendingBuild = false
                ns.BuildSpellData(true)
            end)
        end
        return
    end
    lastBuild = now
    ns.spellDataVersion = ns.spellDataVersion + 1

    wipe(ns.enemyByName)
    wipe(ns.enemyResolved)
    wipe(ns.enemyUnresolved)
    wipe(ns.activeReactives)
    wipe(ns.activeUsable)
    wipe(ns.reactiveByName)
    wipe(ns.stateByName)
    wipe(ns.unknownAbilities)

    for i = 1, #ns.ENEMY_SPELLS do
        local id, category = ns.ENEMY_SPELLS[i][1], ns.ENEMY_SPELLS[i][2]
        local name = ns.compat.GetSpellName(id)
        if name and name ~= "" then
            -- First entry wins, so the category listed earlier in the table
            -- takes priority when two IDs share a name.
            if not ns.enemyByName[name] then
                ns.enemyByName[name] = { category = category, id = id, name = name }
            end
            ns.enemyResolved[id] = name
        else
            ns.enemyUnresolved[#ns.enemyUnresolved + 1] = id
        end
    end

    for i = 1, #ns.REACTIVES do
        local r = ns.REACTIVES[i]
        local name = ns.compat.GetSpellName(r.id)
        if not name then
            ns.unknownAbilities[#ns.unknownAbilities + 1] = r.id
        else
            ns.reactiveByName[strlower(name)] = r.id
        end
        if name and knowsSpell(r.id, name, r.class) then
            local list = ns.activeReactives[r.trigger]
            if not list then
                list = {}
                ns.activeReactives[r.trigger] = list
            end
            list[#list + 1] = { name = name, id = r.id }
        end
    end

    for i = 1, #ns.STATE_AURAS do
        local s = ns.STATE_AURAS[i]
        local name = ns.compat.GetSpellName(s.id)
        if not name or name == "" then
            ns.unknownAbilities[#ns.unknownAbilities + 1] = s.id
        else
            ns.stateByName[strlower(name)] = { cat = s.cat, id = s.id }
        end
    end

    for i = 1, #ns.USABLE_ABILITIES do
        local a = ns.USABLE_ABILITIES[i]
        local name = ns.compat.GetSpellName(a.id)
        if not name then
            ns.unknownAbilities[#ns.unknownAbilities + 1] = a.id
        else
            ns.reactiveByName[strlower(name)] = a.id
        end
        if name and knowsSpell(a.id, name, a.class) then
            ns.activeUsable[#ns.activeUsable + 1] = { name = name, id = a.id }
        end
    end
end

function ns.ReactiveSummary()
    local names = {}
    for _, list in pairs(ns.activeReactives) do
        for i = 1, #list do names[#names + 1] = list[i].name end
    end
    for i = 1, #ns.activeUsable do names[#names + 1] = ns.activeUsable[i].name end
    if #names == 0 then return "none for this character" end
    table.sort(names)
    return table.concat(names, ", ")
end
