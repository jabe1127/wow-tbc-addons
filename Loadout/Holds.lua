local ADDON, ns = ...
local Util = ns.Util

-- =========================================================================
--  Item holds
--
--  Some raid pieces are worn for a proc or an on-use buff — the two necks
--  that get rotated in raids being the obvious case. Swapping the item off
--  while its buff is still ticking throws the buff away, so a hold tells
--  Loadout to leave that slot alone until the aura has dropped, then finish
--  the swap on its own.
-- =========================================================================

local Holds = {}
ns.Holds = Holds

local function list() return ns.cdb.holds end

-- ------------------------------------------------------------ aura check --
function Holds:HasAura(name)
    if not name or name == "" then return false end
    local wanted = name:lower()
    for i = 1, 40 do
        local buff = UnitBuff("player", i)
        if not buff then break end
        if buff:lower() == wanted then return true end
    end
    return false
end

-- Every buff currently on the player, for the picker.
function Holds:CurrentAuras()
    local out = {}
    for i = 1, 40 do
        local buff = UnitBuff("player", i)
        if not buff then break end
        table.insert(out, buff)
    end
    table.sort(out)
    return out
end

-- ------------------------------------------------------------- storage ---
function Holds:Add(key, itemName, aura)
    table.insert(list(), { key = key, item = itemName, aura = aura or "" })
    ns:Fire("HOLDS_CHANGED")
end

function Holds:Remove(index)
    table.remove(list(), index)
    ns:Fire("HOLDS_CHANGED")
end

function Holds:ForKey(key)
    if not key then return nil end
    for _, entry in ipairs(list()) do
        if entry.key == key then return entry end
    end
    return nil
end

-- ------------------------------------------------------------- queries ---
-- Is the item currently worn in this slot protected right now?
function Holds:IsSlotHeld(slotID)
    local equipped = Util:GetEquipped(slotID)
    if not equipped then return false end

    local entry = self:ForKey(equipped.key)
    if not entry or not entry.aura or entry.aura == "" then return false end

    if self:HasAura(entry.aura) then
        return true, entry
    end
    return false
end

function Holds:Describe(entry)
    return (entry.item or "item") .. " while " .. (entry.aura ~= "" and entry.aura or "?")
end

-- =========================================================================
--  Watcher: the moment a held buff falls off, finish the swap.
-- =========================================================================
ns:On("UNIT_AURA", function(_, unit)
    if unit ~= "player" then return end
    ns.Equip:ReleaseHolds()
end)

ns:Listen("PLAYER_READY", function()
    -- UNIT_AURA is reliable, but a slow tick catches anything it misses
    -- (an aura expiring while you are loading, for instance).
    C_Timer.NewTicker(1.0, function()
        if #ns.Equip.holdQueue > 0 then
            ns.Equip:ReleaseHolds()
        end
    end)
end)
