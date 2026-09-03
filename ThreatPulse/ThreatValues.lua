-- ThreatPulse ThreatValues.lua
-- Data-driven TBC 2.4-era threat constants for combat-log estimation.
-- These numbers drive the *estimated* per-ability breakdown only; the live
-- meter always uses the server's real values via UnitDetailedThreatSituation.
--
-- Everything here is tunable. If a number looks off in practice, fix it here —
-- no code changes needed elsewhere.

local ADDON, TP = ...
local TV = {}
TP.ThreatValues = TV

--------------------------------------------------------------------------------
-- Global rates
--------------------------------------------------------------------------------

TV.HEAL_FACTOR    = 0.5   -- threat per point of effective healing (split among engaged mobs)
TV.MANA_FACTOR    = 0.5   -- threat per point of mana gained
TV.RAGE_FACTOR    = 5.0   -- threat per point of rage gained
TV.ENERGY_FACTOR  = 5.0   -- threat per point of energy gained

--------------------------------------------------------------------------------
-- Trackable stance/aura multipliers (detected from CLEU aura events per GUID)
-- key = exact aura name as it appears in the combat log
--------------------------------------------------------------------------------

TV.AURA_MULTIPLIERS = {
    ["Righteous Fury"]              = { school = "holy", mult = 1.90 }, -- assumes 2/2 Improved RF (prot standard)
    ["Bear Form"]                   = { school = "all",  mult = 1.30 },
    ["Dire Bear Form"]              = { school = "all",  mult = 1.30 },
    ["Blessing of Salvation"]       = { school = "all",  mult = 0.70 },
    ["Greater Blessing of Salvation"] = { school = "all", mult = 0.70 },
    ["Tranquil Air Totem"]          = { school = "all",  mult = 0.80 },
    ["Fetish of the Sand Reaver"]   = { school = "all",  mult = 0.30 }, -- rare but cheap to support
}

-- Warrior stances never appear in CLEU. Heuristic: a warrior who casts Sunder
-- Armor or Shield Slam is flagged "tanking" and gets Defensive Stance + 3/3
-- Defiance (1.3 * 1.15 = 1.495) applied to subsequent physical threat.
TV.WARRIOR_TANK_MULT = 1.495
TV.WARRIOR_TANK_FLAG_SPELLS = {
    ["Sunder Armor"] = true, ["Shield Slam"] = true, ["Devastate"] = true,
    ["Shield Block"] = true, ["Revenge"] = true,
}

--------------------------------------------------------------------------------
-- Flat bonus threat per cast/hit (added on top of damage threat, after mults)
-- Values are the commonly cited 2.4.3 max-rank numbers.
--------------------------------------------------------------------------------

TV.FLAT_ON_CAST = {   -- SPELL_CAST_SUCCESS, no damage required
    ["Sunder Armor"]     = 301.5,
    ["Demoralizing Shout"] = 56,
    ["Demoralizing Roar"]  = 42,
    ["Battle Shout"]     = 69,   -- split among nearby engaged mobs; treated flat here
    ["Commanding Shout"] = 68,
    ["Shield Block"]     = 0,    -- flag-only (see WARRIOR_TANK_FLAG_SPELLS)
}

TV.FLAT_ON_DAMAGE = { -- added when the ability lands
    ["Shield Slam"]   = 305,
    ["Revenge"]       = 201,
    ["Heroic Strike"] = 196,
    ["Cleave"]        = 130,
    ["Devastate"]     = 100,  -- plus sunder threat handled via cast
    ["Maul"]          = 322,
    ["Swipe"]         = 0,    -- swipe bonus is in its multiplier below
    ["Lacerate"]      = 267,
    ["Mangle (Bear)"] = 264,
    ["Holy Shield"]   = 0,    -- holy shield block threat can't be attributed cleanly; skip
    ["Consecration"]  = 0,
}

--------------------------------------------------------------------------------
-- Per-ability damage-threat multipliers (before stance/aura mults)
--------------------------------------------------------------------------------

TV.ABILITY_MULT = {
    ["Sinister Strike"] = 1.0,
    ["Swipe"]           = 1.75,
    ["Thunder Clap"]    = 1.75,
    ["Mind Blast"]      = 2.0,
    ["Holy Light"]      = 1.0,  -- heals handled by HEAL_FACTOR path
    ["Execute"]         = 1.25,
}

--------------------------------------------------------------------------------
-- Threat-modifying utility abilities (negative / wipe effects)
-- handled specially by LogThreat: value = fraction of current estimated total
--------------------------------------------------------------------------------

TV.REDUCERS = {
    ["Feint"]        = { flat = -800 },          -- rank 6 ≈ 800
    ["Fade"]         = { temporary = true },     -- can't model temp threat; annotate only
    ["Vanish"]       = { wipe = true },
    ["Feign Death"]  = { wipe = true },
    ["Soulshatter"]  = { fraction = -0.5 },
    ["Invisibility"] = { wipe = true },
}

--------------------------------------------------------------------------------
-- Class baseline passive multipliers (talents we can't see; conservative 1.0)
--------------------------------------------------------------------------------

TV.CLASS_MULT = {
    ROGUE  = 0.71,  -- assumes 5/5 subtlety-free? No: 3/3 is uncommon; use 0.71 for typical combat spec w/ 5% — 
                    -- NOTE: this is the single most spec-dependent number here. Tune to taste.
    MAGE   = 0.70,  -- 2/2 Burning Soul / Frost Channeling common on fire/frost respectively (approximation)
    WARLOCK= 0.90,  -- Destructive Reach / Improved Drain Soul vary; mild default
    PRIEST = 0.92,  -- Shadow Affinity / Silent Resolve common
    HUNTER = 1.00,
    WARRIOR= 0.90,  -- Berserker Stance 0.8 * assumed 5/5 Improved Berserker? Conservative blended default
    PALADIN= 1.00,
    SHAMAN = 1.00,
    DRUID  = 1.00,  -- cat Subtlety-free default; bear handled by aura mult
}
