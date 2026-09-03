local ADDON, ns = ...
local Util, Equip = ns.Util, ns.Equip

local Sets = {}
ns.Sets = Sets

local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Bag_08"

-- =========================================================================
--  Storage helpers
-- =========================================================================
local function db()  return ns.cdb.sets end
local function ord() return ns.cdb.order end

function Sets:Get(name)
    return name and db()[name] or nil
end

-- Forgiving lookup for macros and slash commands: exact match first, then
-- case-insensitive, then unique prefix.
function Sets:Resolve(name)
    if not name or name == "" then return nil end
    if db()[name] then return name end

    local lower = name:lower()
    local partial
    for _, setName in ipairs(self:GetOrder()) do
        local l = setName:lower()
        if l == lower then return setName end
        if l:sub(1, #lower) == lower then
            if partial then return nil, "ambiguous" end
            partial = setName
        end
    end
    return partial
end

function Sets:Exists(name)
    return self:Get(name) ~= nil
end

function Sets:GetOrder()
    local order, sets = ord(), db()
    -- Repair the order list against the actual set table.
    local seen = {}
    for i = #order, 1, -1 do
        local n = order[i]
        if not sets[n] or seen[n] then
            table.remove(order, i)
        else
            seen[n] = true
        end
    end
    for name in pairs(sets) do
        if not seen[name] then
            table.insert(order, name)
            seen[name] = true
        end
    end
    return order
end

function Sets:Count()
    local n = 0
    for _ in pairs(db()) do n = n + 1 end
    return n
end

function Sets:Move(name, delta)
    local order = self:GetOrder()
    for i, n in ipairs(order) do
        if n == name then
            local j = i + delta
            if j >= 1 and j <= #order then
                order[i], order[j] = order[j], order[i]
                ns:Fire("SETS_CHANGED")
            end
            return
        end
    end
end

-- =========================================================================
--  Creating and updating
-- =========================================================================

-- Snapshot what is worn right now into a set.
-- ignoreEmpty = true  -> slots that are empty are simply not part of the set
-- ignoreEmpty = false -> empty slots are recorded as "make this slot empty"
function Sets:SaveCurrent(name, ignoreEmpty)
    if not name or name == "" then return end

    local existing = self:Get(name)
    local set = existing or {
        name    = name,
        icon    = DEFAULT_ICON,
        ignored = {},
    }

    set.items = {}
    set.empty = {}

    for _, s in ipairs(Util.slots) do
        if not set.ignored[s.id] and s.id ~= Util.AMMO then
            local eq = Util:GetEquipped(s.id)
            if eq then
                local info = Util:ItemInfo(eq.link)
                set.items[s.id] = {
                    key  = eq.key,
                    link = eq.link,
                    name = info and info.name or nil,
                }
            elseif not ignoreEmpty then
                set.empty[s.id] = true
            end
        end
    end

    -- Pick a sensible default icon the first time.
    if not existing or set.icon == DEFAULT_ICON then
        local source = set.items[Util.MAINHAND] or set.items[Util.RANGED]
        if source then
            local info = Util:ItemInfo(source.link)
            if info and info.texture then set.icon = info.texture end
        end
    end

    db()[name] = set
    self:GetOrder()
    ns:Fire("SETS_CHANGED")
    return set
end

function Sets:Rename(oldName, newName)
    if not newName or newName == "" or oldName == newName then return false end
    if self:Exists(newName) then
        ns:Print("A set named '" .. newName .. "' already exists.")
        return false
    end
    local set = self:Get(oldName)
    if not set then return false end

    db()[newName] = set
    db()[oldName] = nil
    set.name = newName

    local order = ord()
    for i, n in ipairs(order) do
        if n == oldName then order[i] = newName break end
    end

    -- keep rules pointing at the right set
    for _, rule in ipairs(ns.cdb.rules) do
        if rule.set == oldName then rule.set = newName end
    end
    if ns.cdb.activeRule == oldName then ns.cdb.activeRule = newName end

    ns:Fire("SETS_CHANGED")
    return true
end

function Sets:Delete(name)
    if not self:Get(name) then return end
    db()[name] = nil
    for i = #ord(), 1, -1 do
        if ord()[i] == name then table.remove(ord(), i) end
    end
    for i = #ns.cdb.rules, 1, -1 do
        if ns.cdb.rules[i].set == name then table.remove(ns.cdb.rules, i) end
    end
    ns:Fire("SETS_CHANGED")
end

function Sets:SetIcon(name, icon)
    local set = self:Get(name)
    if set then
        set.icon = icon
        ns:Fire("SETS_CHANGED")
    end
end

-- Toggle whether a slot participates in a set.
function Sets:ToggleIgnored(name, slotID)
    local set = self:Get(name)
    if not set then return end
    set.ignored = set.ignored or {}
    if set.ignored[slotID] then
        set.ignored[slotID] = nil
    else
        set.ignored[slotID] = true
        set.items[slotID] = nil
        set.empty[slotID] = nil
    end
    ns:Fire("SETS_CHANGED")
end

-- =========================================================================
--  Equipping
-- =========================================================================

-- How many slots of this set are already correct? Used for the UI's
-- "currently worn" highlight.
function Sets:IsEquipped(name)
    local set = self:Get(name)
    if not set then return false end
    for slotID, item in pairs(set.items) do
        local eq = Util:GetEquipped(slotID)
        if not eq or eq.key ~= item.key then return false end
    end
    for slotID in pairs(set.empty or {}) do
        if GetInventoryItemLink("player", slotID) then return false end
    end
    return true
end

-- Remember what we were wearing so /lo restore and /lo toggle can undo it.
function Sets:RememberCurrent()
    ns.cdb.prevGear = Util:SnapshotEquipped()
end

function Sets:Restore(silent)
    if not ns.cdb.prevGear then
        if not silent then ns:Print("Nothing to go back to yet.") end
        return false
    end
    local snapshot = ns.cdb.prevGear
    ns.cdb.prevGear = Util:SnapshotEquipped()
    self:EquipSnapshot(snapshot)
    return true
end

-- One command that swaps in and back out again: press once to put the set
-- on, press again to return to what you were wearing.
function Sets:Toggle(name, silent)
    if self:IsEquipped(name) then
        return self:Restore(silent)
    end
    return self:Equip(name, silent)
end

function Sets:Equip(name, silent)
    local set = self:Get(name)
    if not set then
        ns:Print("No set named '" .. tostring(name) .. "'.")
        return false
    end

    if not self:IsEquipped(name) then
        self:RememberCurrent()
    end

    wipe(Equip.queue)
    Equip:ClearHolds()

    local missing = {}

    -- 1. Explicit unequips (armour first; weapons handled below).
    for slotID in pairs(set.empty or {}) do
        if slotID ~= Util.MAINHAND and slotID ~= Util.OFFHAND then
            Equip:QueueUnequip(slotID)
        end
    end

    -- 2. Two-hander incoming with nothing planned for the off-hand?
    --    Clear the off-hand up front.
    local mhItem = set.items[Util.MAINHAND]
    if mhItem and Util.OFFHAND then
        local info = Util:ItemInfo(mhItem.link)
        if info and Util:IsTwoHander(info.equipLoc) then
            if not set.items[Util.OFFHAND] and GetInventoryItemLink("player", Util.OFFHAND) then
                Equip:QueueUnequip(Util.OFFHAND)
            end
        end
    end

    -- 3. Armour and accessories.
    for _, s in ipairs(Util.slots) do
        local item = set.items[s.id]
        if item and not Util:IsWeaponSlot(s.id) and s.id ~= Util.AMMO then
            local eq = Util:GetEquipped(s.id)
            if not eq or eq.key ~= item.key then
                if Util:FindItem(item.key) then
                    Equip:QueueEquip(s.id, item.key, item.name)
                else
                    table.insert(missing, item.name or "item")
                end
            end
        end
    end

    -- 4. Weapons and ranged last, main hand before off hand.
    local weaponOrder = { Util.MAINHAND, Util.OFFHAND, Util.RANGED }
    for _, slotID in ipairs(weaponOrder) do
        if slotID then
            local item = set.items[slotID]
            if item then
                local eq = Util:GetEquipped(slotID)
                if not eq or eq.key ~= item.key then
                    if Util:FindItem(item.key) then
                        Equip:QueueEquip(slotID, item.key, item.name)
                    else
                        table.insert(missing, item.name or "item")
                    end
                end
            elseif (set.empty or {})[slotID] then
                Equip:QueueUnequip(slotID)
            end
        end
    end

    -- 5. Ammunition is deliberately not part of a set. It is handled on its
    --    own: if the slot is empty the best available stack gets loaded, and
    --    whatever you choose to load yourself is left alone.

    if #missing > 0 and not silent then
        ns:Print("|cffffcc00Missing:|r " .. table.concat(missing, ", "))
    end

    if not Equip:HasWork() then
        if not silent and ns.db.announce then
            ns:Print("'" .. name .. "' is already equipped.")
        end
        ns:Fire("SET_EQUIPPED", name)
        return true
    end

    Equip:Start()

    if ns.db.announce and not silent then
        ns:Print("Equipping '" .. name .. "'.")
    end
    if ns.db.equipSound then
        PlaySound(SOUNDKIT and SOUNDKIT.IG_BACKPACK_OPEN or 862)
    end

    ns.cdb.lastSet = name
    ns:Fire("SET_EQUIPPED", name)
    return true
end

-- Restore a raw snapshot table ({ [slotID] = {key=,link=} or false }).
function Sets:EquipSnapshot(snapshot)
    if not snapshot then return end
    wipe(Equip.queue)
    Equip:ClearHolds()
    for _, s in ipairs(Util.slots) do
        local want = snapshot[s.id]
        local eq   = Util:GetEquipped(s.id)
        if want and want.key then
            if (not eq or eq.key ~= want.key) and Util:FindItem(want.key) then
                Equip:QueueEquip(s.id, want.key, want.name)
            end
        elseif want == false and eq then
            Equip:QueueUnequip(s.id)
        end
    end
    Equip:Start()
end
