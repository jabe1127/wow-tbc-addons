local ADDON, ns = ...
local Util, C = ns.Util, ns.C

local Equip = {}
ns.Equip = Equip

Equip.queue     = {}
Equip.holdQueue = {}   -- parked because the worn item's buff is still up
Equip.running   = false
Equip.ticker    = nil

-- Single source of truth for "is a vendor/bank/mail window in play".
function Equip:ContainerActionUnsafe()
    return ns:Interacting()
end

local MAX_ATTEMPTS  = 30      -- ticks an individual action may linger
local TICK_INTERVAL = 0.05    -- verification pass rate
local MAX_RUNTIME   = 6.0     -- seconds before the whole queue is abandoned
local REISSUE_AFTER = 0.35    -- do not re-send a move the server is still chewing on

-- =========================================================================
--  Queue building
-- =========================================================================
function Equip:QueueEquip(slotID, key, label)
    table.insert(self.queue, {
        kind = "equip", slot = slotID, key = key, label = label, attempts = 0,
    })
end

function Equip:QueueUnequip(slotID)
    table.insert(self.queue, {
        kind = "unequip", slot = slotID, attempts = 0,
    })
end

function Equip:HasWork()
    return #self.queue > 0
end

-- =========================================================================
--  Free bag space
--  Built fresh at the start of every pass and consumed as we go, because
--  the server has not confirmed earlier moves in the same pass yet.
-- =========================================================================
local function BuildFreeList()
    local free = {}
    for bag = 0, C.NUM_BAGS do
        local size = C.GetContainerNumSlots(bag) or 0
        for slot = 1, size do
            if not C.GetContainerItemLink(bag, slot) then
                table.insert(free, { bag = bag, slot = slot })
            end
        end
    end
    return free
end

local function TakeFreeSlot(free)
    local entry = table.remove(free, 1)
    if not entry then return nil end
    return entry.bag, entry.slot
end

-- Park whatever is on the cursor somewhere sane.
local function StashCursor(free)
    if not CursorHasItem() then return end
    local bag, slot = TakeFreeSlot(free)
    if bag then
        C.PickupContainerItem(bag, slot)
    end
    if CursorHasItem() then
        ClearCursor()
    end
end

-- =========================================================================
--  Execution
-- =========================================================================
function Equip:Start()
    if #self.queue == 0 then return end

    if CursorHasItem() then
        ns:Print("Cursor is holding an item — drop it first.")
        wipe(self.queue)
        return
    end

    self.startTime = GetTime()

    if not self.running then
        self.running = true
        self.ticker  = C_Timer.NewTicker(TICK_INTERVAL, function() Equip:Tick() end)
    end

    -- Fire the whole batch immediately; the ticker only verifies and retries.
    self:Tick()
end

function Equip:Stop(reason)
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
    self.running = false
    wipe(self.queue)
    if CursorHasItem() then ClearCursor() end
    ns:Fire("EQUIP_FINISHED", reason)
end

-- Held actions survive Stop(); this is how you throw them away.
function Equip:ClearHolds()
    wipe(self.holdQueue)
end

-- Anything whose buff has dropped goes back into the live queue.
function Equip:ReleaseHolds()
    if #self.holdQueue == 0 then return end
    local Holds = ns.Holds
    local moved = false

    for i = #self.holdQueue, 1, -1 do
        local action = self.holdQueue[i]
        if self:IsSatisfied(action) then
            table.remove(self.holdQueue, i)
        elseif not (Holds and select(1, Holds:IsSlotHeld(action.slot))) then
            action.attempts = 0
            action.issuedAt = nil
            table.remove(self.holdQueue, i)
            table.insert(self.queue, action)
            moved = true
        end
    end

    if moved then self:Start() end
end

-- Is this action already satisfied?
function Equip:IsSatisfied(action)
    if action.kind == "equip" then
        -- Ammo is compared by item id: the slot has no hyperlink to match on,
        -- and the stack count changes as you shoot, so nothing else is stable.
        if Util.AMMO and action.slot == Util.AMMO then
            local loaded = GetInventoryItemID and GetInventoryItemID("player", Util.AMMO)
            local wanted = Util:KeyItemID(action.key)
            return loaded ~= nil and wanted ~= nil and loaded == wanted
        end
        local current = Util:GetEquipped(action.slot)
        return current ~= nil and current.key == action.key
    else
        if Util.AMMO and action.slot == Util.AMMO then
            local loaded = GetInventoryItemID and GetInventoryItemID("player", Util.AMMO)
            return loaded == nil
        end
        return GetInventoryItemLink("player", action.slot) == nil
    end
end

-- Issue the move for one action. Returns true if it was actually sent.
function Equip:Issue(action, free)
    if action.kind == "unequip" then
        local bag, slot = TakeFreeSlot(free)
        if not bag then
            action.fatal = "no free bag space"
            return false
        end
        ClearCursor()
        PickupInventoryItem(action.slot)
        if CursorHasItem() then
            C.PickupContainerItem(bag, slot)
            StashCursor(free)
            return true
        end
        ClearCursor()
        return false
    end

    -- equip
    local bag, slot, invSlot = Util:FindItem(action.key)

    if bag then
        if C.IsItemLocked(bag, slot) then return false end

        -- You cannot equip straight out of the bank. Move it into a bag and
        -- let the next pass equip it from there.
        if Util:IsBankContainer(bag) then
            if not Util.bankOpen then
                action.fatal = "it is in the bank"
                return false
            end
            local fbag, fslot = TakeFreeSlot(free)
            if not fbag then
                action.fatal = "no free bag space to pull it from the bank"
                return false
            end
            ClearCursor()
            C.PickupContainerItem(bag, slot)
            if CursorHasItem() then
                C.PickupContainerItem(fbag, fslot)
            end
            StashCursor(free)
            return true
        end

        -- Ammunition will not go into the slot off the cursor; the client
        -- only loads it through the container-use call. That call is the one
        -- that sells at a vendor, so it goes through the guarded shim and is
        -- refused outright if any such window is open.
        if Util.AMMO and action.slot == Util.AMMO then
            if self:ContainerActionUnsafe() then
                action.fatal = "a vendor, bank or mail window is open"
                return false
            end
            C.UseContainerItem(bag, slot)
            return true
        end

        ClearCursor()
        C.PickupContainerItem(bag, slot)
        if CursorHasItem() then
            EquipCursorItem(action.slot)
            StashCursor(free)   -- catch anything the swap displaced
            return true
        end
        ClearCursor()
        return false
    elseif invSlot then
        if invSlot == action.slot then return true end
        ClearCursor()
        PickupInventoryItem(invSlot)
        if CursorHasItem() then
            EquipCursorItem(action.slot)
            StashCursor(free)
            return true
        end
        ClearCursor()
        return false
    end

    action.fatal = Util.bankOpen and "not in your bags or bank" or "not in your bags"
    return false
end

function Equip:Tick()
    if not self.running then return end

    if GetTime() - self.startTime > MAX_RUNTIME then
        if #self.queue > 0 then
            ns:Print("|cffffcc00Timed out|r with " .. #self.queue .. " swap(s) unfinished.")
        end
        self:Stop("timeout")
        return
    end

    -- Weapon swaps are refused by the client mid-cast, but armour, rings and
    -- trinkets go through fine. Only the weapons wait.
    local casting = (UnitCastingInfo("player") or UnitChannelInfo("player")) and true or false

    local free = BuildFreeList()
    StashCursor(free)

    local now = GetTime()
    local i = 1
    local deferred = 0
    local Holds = ns.Holds

    -- One pass over the ENTIRE queue: everything that can move, moves now.
    while i <= #self.queue do
        local action = self.queue[i]
        local remove = false

        if self:IsSatisfied(action) then
            ns:Fire("SLOT_CHANGED", action.slot)
            remove = true
        elseif casting and Util:IsWeaponSlot(action.slot) then
            -- Hold this one until the cast is done; do not burn an attempt.
            deferred = deferred + 1
        elseif Holds and select(1, Holds:IsSlotHeld(action.slot)) then
            -- The item in this slot is protected while its buff is up. Park
            -- the action somewhere with no timeout and pick it up later.
            local _, entry = Holds:IsSlotHeld(action.slot)
            if not action.announced then
                action.announced = true
                ns:Print("|cff9fe08cKeeping|r " .. (entry.item or "that item")
                    .. " on until |cffffffff" .. entry.aura .. "|r drops.")
            end
            table.insert(self.holdQueue, action)
            remove = true
        else
            action.attempts = action.attempts + 1

            -- Do not re-send a move the server has not answered yet.
            local waiting = action.issuedAt and (now - action.issuedAt) < REISSUE_AFTER

            if not waiting then
                if self:Issue(action, free) then
                    action.issuedAt = now
                end
            end

            if action.fatal then
                ns:Print("|cffffcc00Could not move|r "
                    .. (action.label or Util:SlotName(action.slot))
                    .. " — " .. action.fatal .. ".")
                remove = true
            elseif action.attempts > MAX_ATTEMPTS then
                ns:Print("|cffffcc00Gave up on|r "
                    .. (action.label or Util:SlotName(action.slot)) .. ".")
                remove = true
            end
        end

        if remove then
            table.remove(self.queue, i)
        else
            i = i + 1
        end
    end

    -- Waiting on a cast should not count against the overall timeout.
    if deferred > 0 and deferred == #self.queue then
        self.startTime = self.startTime + TICK_INTERVAL
    end

    if #self.queue == 0 then
        self:Stop("done")
    end
end

-- Equip a single named item into its natural slot. `which` picks the second
-- of a pair (ring 2, trinket 2, off hand).
function Equip:EquipByName(search, which)
    if not search or search == "" then return false end
    local lower = search:lower()

    local foundBag, foundSlot, foundLink
    Util:ScanBags(function(bag, slot, link)
        local name = link:match("%[(.-)%]")
        if name and name:lower():find(lower, 1, true) then
            foundBag, foundSlot, foundLink = bag, slot, link
            return true
        end
    end)

    if not foundBag then
        ns:Print("No item matching '" .. search .. "' in your bags.")
        return false
    end

    local equipLoc = Util:EquipLoc(foundLink)
    local target
    for _, s in ipairs(Util.slots) do
        if Util:FitsSlot(equipLoc, s.id) then
            if not target then target = s.id end
            if which == 2 then target = s.id end   -- second matching slot
        end
    end

    if not target then
        ns:Print("That item is not equippable.")
        return false
    end

    self:EquipFromBag(foundBag, foundSlot, target)
    return true
end

-- =========================================================================
--  One-shot helpers
-- =========================================================================
function Equip:EquipFromBag(bag, slot, invSlot)
    if CursorHasItem() then ClearCursor() end
    local link = C.GetContainerItemLink(bag, slot)
    if not link then return end
    local key  = Util:ItemKey(link)
    local info = Util:ItemInfo(link)

    wipe(self.queue)

    -- A two-hander needs the off-hand cleared first.
    if invSlot == Util.MAINHAND and info and Util:IsTwoHander(info.equipLoc) then
        if Util.OFFHAND and GetInventoryItemLink("player", Util.OFFHAND) then
            self:QueueUnequip(Util.OFFHAND)
        end
    end

    self:QueueEquip(invSlot, key, info and info.name)
    self:Start()
end

function Equip:SwapWorn(fromSlot, toSlot)
    if CursorHasItem() then ClearCursor() end
    local a = Util:GetEquipped(fromSlot)
    local b = Util:GetEquipped(toSlot)
    wipe(self.queue)
    if a then self:QueueEquip(toSlot, a.key) end
    if b then self:QueueEquip(fromSlot, b.key) end
    self:Start()
end

-- Equip a known item key into a slot, wherever it currently lives.
function Equip:EquipByKey(invSlot, key, label)
    if not key then return false end
    if CursorHasItem() then ClearCursor() end
    wipe(self.queue)
    self:QueueEquip(invSlot, key, label)
    self:Start()
    return true
end

function Equip:UnequipSlot(invSlot)
    if CursorHasItem() then ClearCursor() end
    wipe(self.queue)
    self:QueueUnequip(invSlot)
    self:Start()
end

-- Strip everything. Shirt and tabard are left alone unless asked for.
-- armorOnly also leaves weapons, ranged and ammo alone, which matters
-- because pulling a weapon resets your swing timer.
function Equip:UnequipAll(includeCosmetic, armorOnly)
    if CursorHasItem() then ClearCursor() end
    wipe(self.queue)
    self:ClearHolds()

    local needed, freeCount = 0, 0
    for _, s in ipairs(Util.slots) do
        local skip = (not includeCosmetic)
            and (s.key == "ShirtSlot" or s.key == "TabardSlot")
        if armorOnly and (Util:IsWeaponSlot(s.id) or s.id == Util.AMMO) then
            skip = true
        end
        if not skip and GetInventoryItemLink("player", s.id) then
            needed = needed + 1
            self:QueueUnequip(s.id)
        end
    end

    for _, entry in ipairs(BuildFreeList()) do freeCount = freeCount + 1 end
    if freeCount < needed then
        ns:Print("|cffffcc00Only " .. freeCount .. " free bag slot(s) for "
            .. needed .. " item(s)|r — some gear will stay on.")
    end

    self:Start()
end
