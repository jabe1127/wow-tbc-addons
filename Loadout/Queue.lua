local ADDON, ns = ...
local Util = ns.Util

-- =========================================================================
--  Slot queues
--
--  A ranked list of items for one slot. Whichever is highest in the list
--  and off cooldown is the one you wear. The classic use is two on-use
--  trinkets: fire the first, and the moment it goes on cooldown the second
--  takes its place, so you are never sitting on a dead slot.
-- =========================================================================

local Queue = {}
ns.Queue = Queue

local READY_GRACE = 1.5   -- seconds of cooldown left we treat as "ready"

local function all() return ns.cdb.queues end

function Queue:Get(slotID)
    return all()[slotID]
end

function Queue:Ensure(slotID)
    local q = all()[slotID]
    if not q then
        q = { entries = {}, auto = true }
        all()[slotID] = q
    end
    q.entries = q.entries or {}
    return q
end

function Queue:Delete(slotID)
    all()[slotID] = nil
    ns:Fire("QUEUES_CHANGED")
end

function Queue:Add(slotID, data)
    local q = self:Ensure(slotID)
    for _, e in ipairs(q.entries) do
        if e.key == data.key then return end
    end
    local info = Util:ItemInfo(data.link)
    table.insert(q.entries, {
        key  = data.key,
        link = data.link,
        name = info and info.name or data.name,
        icon = info and info.texture,
    })
    ns:Fire("QUEUES_CHANGED")
end

function Queue:Remove(slotID, index)
    local q = self:Get(slotID)
    if not q then return end
    table.remove(q.entries, index)
    if #q.entries == 0 then
        all()[slotID] = nil
    end
    ns:Fire("QUEUES_CHANGED")
end

function Queue:Move(slotID, index, delta)
    local q = self:Get(slotID)
    if not q then return end
    local j = index + delta
    if j < 1 or j > #q.entries then return end
    q.entries[index], q.entries[j] = q.entries[j], q.entries[index]
    ns:Fire("QUEUES_CHANGED")
end

-- =========================================================================
--  Readiness
-- =========================================================================
function Queue:CooldownLeft(entry)
    local itemID = Util:ItemID(entry.link)
    if not itemID then return 0 end
    local start, duration, enable = GetItemCooldown(itemID)
    if not start or start == 0 or not duration or duration == 0 then return 0 end
    if enable == 0 then return 0 end
    local left = (start + duration) - GetTime()
    return left > 0 and left or 0
end

function Queue:IsAvailable(entry)
    if Util:FindItem(entry.key) then return true end
    -- Already worn somewhere counts as available.
    for _, s in ipairs(Util.slots) do
        local eq = Util:GetEquipped(s.id)
        if eq and eq.key == entry.key then return true end
    end
    return false
end

-- The entry that should be worn in this slot right now, and its index.
function Queue:Pick(slotID)
    local q = self:Get(slotID)
    if not q or #q.entries == 0 then return nil end

    local firstAvailable
    for i, entry in ipairs(q.entries) do
        if self:IsAvailable(entry) then
            firstAvailable = firstAvailable or { entry = entry, index = i }
            if self:CooldownLeft(entry) <= READY_GRACE then
                return entry, i
            end
        end
    end

    -- Everything is on cooldown: stay with the highest-ranked one you own
    -- rather than shuffling pointlessly.
    if firstAvailable then
        return firstAvailable.entry, firstAvailable.index
    end
    return nil
end

-- Manual step: move to the next item in the list, wrapping around.
function Queue:Cycle(slotID)
    local q = self:Get(slotID)
    if not q or #q.entries == 0 then
        ns:Print("Nothing queued for " .. Util:SlotName(slotID) .. ".")
        return
    end

    local current = Util:GetEquipped(slotID)
    local at = 0
    for i, entry in ipairs(q.entries) do
        if current and entry.key == current.key then at = i break end
    end

    for step = 1, #q.entries do
        local i = ((at + step - 1) % #q.entries) + 1
        local entry = q.entries[i]
        if self:IsAvailable(entry) and (not current or entry.key ~= current.key) then
            ns.Equip:EquipByKey(slotID, entry.key, entry.name)
            ns.Rules:Release()
            return
        end
    end

    ns:Print("Nothing else in that queue is available.")
end

-- =========================================================================
--  Automatic swapping
-- =========================================================================
local pending = false

function Queue:Evaluate()
    if not ns.db or not ns.db.queuesEnabled then return end
    if ns.Equip.running then return end
    if ns.Util.bankOpen then return end

    local inCombat = UnitAffectingCombat("player")
    if inCombat and not ns.db.queuesInCombat then return end

    for slotID, q in pairs(all()) do
        if q.auto and #q.entries > 0 then
            -- Weapons are left out of automatic swapping: changing them
            -- resets your swing timer, which costs more than it gains.
            if not (inCombat and Util:IsWeaponSlot(slotID)) then
                local want = self:Pick(slotID)
                local current = Util:GetEquipped(slotID)
                if want and (not current or current.key ~= want.key) then
                    -- Only act if what we are wearing is actually a queued
                    -- item, or the slot is empty. Never yank something you
                    -- put on deliberately that is not part of the queue.
                    local currentIsQueued = false
                    if current then
                        for _, e in ipairs(q.entries) do
                            if e.key == current.key then currentIsQueued = true break end
                        end
                    end
                    if not current or currentIsQueued then
                        ns.Equip:EquipByKey(slotID, want.key, want.name)
                        return   -- one swap per pass, verify next time
                    end
                end
            end
        end
    end
end

local function Schedule()
    if pending then return end
    pending = true
    C_Timer.After(0.25, function()
        pending = false
        Queue:Evaluate()
    end)
end

ns:On("BAG_UPDATE_COOLDOWN",       Schedule)
ns:On("SPELL_UPDATE_COOLDOWN",     Schedule)
ns:On("PLAYER_EQUIPMENT_CHANGED",  Schedule)
ns:On("PLAYER_REGEN_ENABLED",      Schedule)

ns:Listen("PLAYER_READY", function()
    C_Timer.NewTicker(1.0, function() Queue:Evaluate() end)
end)
