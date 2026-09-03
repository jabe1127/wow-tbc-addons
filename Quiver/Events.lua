-- =========================================================================
-- Quiver - Events.lua
-- Turns what you press into alerts.
--
-- Any spell you successfully cast is announced, so nothing needs a curated
-- list and new abilities work automatically. Two exceptions handled here:
--   Auto Shot - fires repeatedly on its own, so it gets its own toggle
--   Melee     - not a cast at all, so it comes from the combat log swing
-- =========================================================================

local ADDON, TS = ...

local AUTO_SHOT, WAND_SHOOT = 75, 5019
local playerGUID

local function Announce(spellID, kind)
    local a = TS.db.alerts
    TS.Alert({
        icon  = TS.SpellTexture(spellID),
        label = TS.SpellName(spellID),
        color = TS.db.colors[kind] or TS.db.colors.cast,
        cooldownSpell = (kind == "cast") and TS.SpellName(spellID) or nil,
    })
end

local function OnEvent(self, event, arg1, arg2, arg3)
    if TS.testing or not TS.db then return end
    local a = TS.db.alerts

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local spellID = arg3
        -- remembered even when blocked, so /tsh block can target the last
        -- thing you cast without needing to look up its id
        TS.lastSpellID = spellID
        if TS.IsBlocked(spellID) then return end
        if spellID == AUTO_SHOT or spellID == WAND_SHOOT then
            if a.showAuto then Announce(spellID, "auto") end
        elseif a.enabled then
            Announce(spellID, "cast")
        end

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not a.showMelee then return end
        local _, sub, _, srcGUID, _, _, _, _, _, _, _, _, p13 = CombatLogGetCurrentEventInfo()
        if srcGUID ~= playerGUID then return end
        -- main-hand swings only; on-next-swing abilities already announced
        -- themselves as casts
        if sub == "SWING_DAMAGE" then
            if select(21, CombatLogGetCurrentEventInfo()) then return end
            TS.Alert({
                icon  = GetInventoryItemTexture("player", 16)
                        or "Interface\\Icons\\Ability_MeleeDamage",
                label = MELEE or "Melee",
                color = TS.db.colors.melee,
            })
        elseif sub == "SWING_MISSED" and not p13 then
            TS.Alert({
                icon  = GetInventoryItemTexture("player", 16)
                        or "Interface\\Icons\\Ability_MeleeDamage",
                label = MELEE or "Melee",
                color = TS.db.colors.melee,
            })
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        playerGUID = UnitGUID("player")
    end
end

TS.inits[#TS.inits + 1] = function(db)
    playerGUID = UnitGUID("player")
    local ev = CreateFrame("Frame")
    if not pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player") then
        ev:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    end
    ev:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", OnEvent)
end
