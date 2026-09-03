local ADDON, ns = ...

-- =========================================================================
--  "Swap after the cast lands"
--
--  Macro lines all run in the same instant, so a /jb sitting under a /cast
--  fires while the spell is still in the air. Classic snapshots stats on
--  completion, so that strips the gear before it counts. This arms a swap
--  that waits for the cast to finish instead.
-- =========================================================================

local pending = nil       -- { set = <name> or nil for restore, expires = }
local WINDOW = 12         -- seconds before an unused arm quietly expires

local function Fire()
    if not pending then return end
    local target = pending.set
    pending = nil

    if target then
        ns.Sets:Equip(target)
    else
        ns.Sets:Restore(true)
    end
    ns.Rules:Release()
end

function ns:ArmAfterCast(setName)
    -- Nothing being cast right now? There is nothing to wait for, so just
    -- do it. Covers instants, where the cast has already resolved by the
    -- time this line of the macro runs.
    if not (UnitCastingInfo("player") or UnitChannelInfo("player")) then
        pending = { set = setName }
        Fire()
        return
    end

    pending = { set = setName, expires = GetTime() + WINDOW }
end

function ns:CancelAfterCast()
    pending = nil
end

local function OnCastEnd(event, unit)
    if unit ~= "player" then return end
    if not pending then return end
    Fire()
end

ns:On("UNIT_SPELLCAST_SUCCEEDED",   OnCastEnd)
ns:On("UNIT_SPELLCAST_STOP",        OnCastEnd)
ns:On("UNIT_SPELLCAST_CHANNEL_STOP", OnCastEnd)
ns:On("UNIT_SPELLCAST_FAILED",      OnCastEnd)
ns:On("UNIT_SPELLCAST_INTERRUPTED", OnCastEnd)

-- An arm that never gets a cast should not linger and surprise you later.
ns:Listen("PLAYER_READY", function()
    C_Timer.NewTicker(1.0, function()
        if pending and pending.expires and GetTime() > pending.expires then
            pending = nil
        end
    end)
end)

-- =========================================================================
--  Delayed gear commands
--
--  Macros run every line in the same instant and Blizzard has no /wait, so
--  "swap, then swap back a moment later" is impossible in a plain macro.
--  Gear changes are unprotected, though, so Loadout can hold one on a timer and
--  run it later. Casting cannot be delayed this way — the client refuses a
--  spell cast that did not come from a hardware keypress — so these only
--  ever perform gear operations.
-- =========================================================================

local timers = {}
local MAX_DELAY = 60

function ns:Delay(seconds, fn, label)
    seconds = tonumber(seconds) or 0
    if seconds < 0 then seconds = 0 end
    if seconds > MAX_DELAY then seconds = MAX_DELAY end

    local token = { label = label, at = GetTime() + seconds }
    timers[token] = true

    C_Timer.After(seconds, function()
        if not timers[token] then return end   -- cancelled while waiting
        timers[token] = nil
        fn()
    end)

    return token
end

function ns:CancelDelays()
    local n = 0
    for token in pairs(timers) do
        timers[token] = nil
        n = n + 1
    end
    return n
end

function ns:PendingDelays()
    local out = {}
    for token in pairs(timers) do
        table.insert(out, token)
    end
    return out
end

-- The subset of Loadout commands that are safe to run from a timer.
-- Everything here only moves items around; nothing casts.
function ns:RunGearCommand(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")

    if text == "" or text == "back" or text == "restore" then
        ns.Sets:Restore()
        ns.Rules:Release()
        return true
    end

    local cmd, rest = text:match("^(%S+)%s*(.-)$")
    local lower = (cmd or ""):lower()

    if lower == "off" or lower == "undress" then
        local armorOnly = rest:lower():find("armor") or rest:lower():find("armour")
        ns.Equip:UnequipAll(false, armorOnly and true or false)
        ns.Rules:Release()
        return true
    elseif lower == "item" and rest ~= "" then
        ns.Equip:EquipByName(rest, 1)
        ns.Rules:Release()
        return true
    elseif lower == "item2" and rest ~= "" then
        ns.Equip:EquipByName(rest, 2)
        ns.Rules:Release()
        return true
    end

    -- Anything else is treated as a set name, with or without a leading
    -- "equip", so "/jd 2 Threat" and "/jd 2 equip Threat" both work.
    local target = (lower == "equip" or lower == "e") and rest or text
    local name, err = ns.Sets:Resolve(target)
    if err then
        ns:Print("'" .. target .. "' matches more than one set.")
        return false
    end
    if not name then
        ns:Print("No set matching '" .. target .. "'.")
        return false
    end

    ns.Sets:Equip(name)
    ns.Rules:Release()
    return true
end
