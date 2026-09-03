local ADDON, ns = ...
local C = ns.C

local Util = {}
ns.Util = Util

-- =========================================================================
--  Inventory slots
--  Built at load so slots missing on a given client (AmmoSlot on modern
--  builds, for example) simply never enter the table.
-- =========================================================================
local SLOT_DEFS = {
    { key = "HeadSlot",          label = HEADSLOT          or "Head" },
    { key = "NeckSlot",          label = NECKSLOT          or "Neck" },
    { key = "ShoulderSlot",      label = SHOULDERSLOT      or "Shoulder" },
    { key = "BackSlot",          label = BACKSLOT          or "Back" },
    { key = "ChestSlot",         label = CHESTSLOT         or "Chest" },
    { key = "ShirtSlot",         label = SHIRTSLOT         or "Shirt" },
    { key = "TabardSlot",        label = TABARDSLOT        or "Tabard" },
    { key = "WristSlot",         label = WRISTSLOT         or "Wrist" },
    { key = "HandsSlot",         label = HANDSSLOT         or "Hands" },
    { key = "WaistSlot",         label = WAISTSLOT         or "Waist" },
    { key = "LegsSlot",          label = LEGSSLOT          or "Legs" },
    { key = "FeetSlot",          label = FEETSLOT          or "Feet" },
    { key = "Finger0Slot",       label = FINGER0SLOT       or "Ring 1" },
    { key = "Finger1Slot",       label = FINGER1SLOT       or "Ring 2" },
    { key = "Trinket0Slot",      label = TRINKET0SLOT      or "Trinket 1" },
    { key = "Trinket1Slot",      label = TRINKET1SLOT      or "Trinket 2" },
    { key = "MainHandSlot",      label = MAINHANDSLOT      or "Main Hand" },
    { key = "SecondaryHandSlot", label = SECONDARYHANDSLOT or "Off Hand" },
    { key = "RangedSlot",        label = RANGEDSLOT        or "Ranged" },
    { key = "AmmoSlot",          label = AMMOSLOT          or "Ammo" },
}

Util.slots      = {}   -- ordered array of { id, key, label, emptyTexture }
Util.slotByID   = {}
Util.slotByKey  = {}

do
    for _, def in ipairs(SLOT_DEFS) do
        local ok, id, tex = pcall(GetInventorySlotInfo, def.key)
        if ok and id then
            local entry = {
                id      = id,
                key     = def.key,
                label   = def.label,
                texture = tex,
            }
            table.insert(Util.slots, entry)
            Util.slotByID[id]      = entry
            Util.slotByKey[def.key] = entry
        end
    end
end

function Util:SlotName(id)
    local s = self.slotByID[id]
    return s and s.label or ("Slot " .. tostring(id))
end

function Util:IsWeaponSlot(id)
    local s = self.slotByID[id]
    if not s then return false end
    return s.key == "MainHandSlot" or s.key == "SecondaryHandSlot" or s.key == "RangedSlot"
end

local function SlotID(key)
    local s = Util.slotByKey[key]
    return s and s.id
end

Util.MAINHAND = SlotID("MainHandSlot")
Util.OFFHAND  = SlotID("SecondaryHandSlot")
Util.RANGED   = SlotID("RangedSlot")
Util.AMMO     = SlotID("AmmoSlot")

-- =========================================================================
--  Equip location -> candidate inventory slots
-- =========================================================================
local EQUIP_LOC = {
    INVTYPE_HEAD            = { "HeadSlot" },
    INVTYPE_NECK            = { "NeckSlot" },
    INVTYPE_SHOULDER        = { "ShoulderSlot" },
    INVTYPE_BODY            = { "ShirtSlot" },
    INVTYPE_CHEST           = { "ChestSlot" },
    INVTYPE_ROBE            = { "ChestSlot" },
    INVTYPE_WAIST           = { "WaistSlot" },
    INVTYPE_LEGS            = { "LegsSlot" },
    INVTYPE_FEET            = { "FeetSlot" },
    INVTYPE_WRIST           = { "WristSlot" },
    INVTYPE_HAND            = { "HandsSlot" },
    INVTYPE_FINGER          = { "Finger0Slot", "Finger1Slot" },
    INVTYPE_TRINKET         = { "Trinket0Slot", "Trinket1Slot" },
    INVTYPE_CLOAK           = { "BackSlot" },
    INVTYPE_WEAPON          = { "MainHandSlot", "SecondaryHandSlot" },
    INVTYPE_SHIELD          = { "SecondaryHandSlot" },
    INVTYPE_2HWEAPON        = { "MainHandSlot" },
    INVTYPE_WEAPONMAINHAND  = { "MainHandSlot" },
    INVTYPE_WEAPONOFFHAND   = { "SecondaryHandSlot" },
    INVTYPE_HOLDABLE        = { "SecondaryHandSlot" },
    INVTYPE_RANGED          = { "RangedSlot" },
    INVTYPE_RANGEDRIGHT     = { "RangedSlot" },
    INVTYPE_THROWN          = { "RangedSlot" },
    INVTYPE_RELIC           = { "RangedSlot" },
    INVTYPE_TABARD          = { "TabardSlot" },
    INVTYPE_AMMO            = { "AmmoSlot" },
}

-- Does an item with this equip location fit the given inventory slot id?
function Util:FitsSlot(equipLoc, slotID)
    local keys = EQUIP_LOC[equipLoc or ""]
    if not keys then return false end
    for _, key in ipairs(keys) do
        local s = self.slotByKey[key]
        if s and s.id == slotID then return true end
    end
    return false
end

function Util:IsTwoHander(equipLoc)
    return equipLoc == "INVTYPE_2HWEAPON"
end

-- =========================================================================
--  Item identity
--  Keys ignore enchants and gems so a set does not break the moment you
--  enchant a piece, but they keep the random-suffix id so "of the Bandit"
--  greens stay distinguishable.
-- =========================================================================
function Util:ItemKey(link)
    if not link then return nil end
    local id, _, _, _, _, _, suffix = link:match(
        "item:(%d+):(%-?%d*):(%-?%d*):(%-?%d*):(%-?%d*):(%-?%d*):(%-?%d*)")
    if not id then
        id = link:match("item:(%d+)")
        if not id then return nil end
        return id .. ":0"
    end
    return id .. ":" .. tostring(tonumber(suffix) or 0)
end

function Util:ItemID(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- Equip location, resolved without depending on a warm item cache.
-- GetItemInfoInstant reads straight from the client's item DB, so it answers
-- for items GetItemInfo has not cached yet.
function Util:EquipLoc(link)
    if not link then return nil end
    if GetItemInfoInstant then
        local _, _, _, loc = GetItemInfoInstant(link)
        if loc and loc ~= "" then return loc end
    end
    local loc = select(9, GetItemInfo(link))
    if loc and loc ~= "" then return loc end
    return nil
end

function Util:ItemInfo(link)
    if not link then return nil end
    local name, _, quality, _, _, _, _, _, equipLoc, texture = GetItemInfo(link)
    if not name then
        -- Not cached yet; fall back to the instant lookup.
        local id, _, _, loc, icon = GetItemInfoInstant(link)
        return {
            name     = link:match("%[(.-)%]") or "…",
            quality  = 1,
            equipLoc = loc,
            texture  = icon or GetItemIcon and GetItemIcon(link),
            cached   = false,
        }
    end
    return {
        name     = name,
        quality  = quality,
        equipLoc = (equipLoc and equipLoc ~= "") and equipLoc or self:EquipLoc(link),
        texture  = texture,
        cached   = true,
    }
end

-- =========================================================================
--  Scanning
-- =========================================================================

-- Currently equipped item for a slot, or nil.
-- The ammo slot does not report a hyperlink the way gear slots do, so it is
-- resolved through the item id instead.
function Util:GetEquipped(slotID)
    local link = GetInventoryItemLink("player", slotID)

    if not link and self.AMMO and slotID == self.AMMO then
        local id = GetInventoryItemID and GetInventoryItemID("player", slotID)
        if id then
            local _, itemLink = GetItemInfo(id)
            if itemLink then
                link = itemLink
            else
                return { link = nil, key = tostring(id) .. ":0", id = id }
            end
        end
    end

    if not link then return nil end
    return {
        link = link,
        key  = self:ItemKey(link),
        id   = self:ItemID(link),
    }
end

-- The item id embedded in a key ("12654:0" -> 12654).
function Util:KeyItemID(key)
    if not key then return nil end
    return tonumber(key:match("^(%d+)"))
end

-- Everything worn right now: { [slotID] = {link=,key=,id=} }
function Util:SnapshotEquipped()
    local out = {}
    for _, s in ipairs(self.slots) do
        out[s.id] = self:GetEquipped(s.id) or false
    end
    return out
end

-- Walk the bags. fn(bag, slot, link) -> return true to stop early.
function Util:ScanBags(fn)
    for bag = 0, C.NUM_BAGS do
        local size = C.GetContainerNumSlots(bag) or 0
        for slot = 1, size do
            local link = C.GetContainerItemLink(bag, slot)
            if link then
                if fn(bag, slot, link) then return end
            end
        end
    end
end

-- =========================================================================
--  Bank
--  Only reachable while the bank window is open, so everything here checks
--  Util.bankOpen before pretending the items exist.
-- =========================================================================
Util.BANK_CONTAINER = _G.BANK_CONTAINER or -1
Util.bankOpen = false

function Util:BankContainers()
    local out = { self.BANK_CONTAINER }
    local first = (_G.NUM_BAG_SLOTS or 4) + 1
    local last  = first + (_G.NUM_BANKBAGSLOTS or 6) - 1
    for bag = first, last do
        table.insert(out, bag)
    end
    return out
end

function Util:IsBankContainer(bag)
    if bag == self.BANK_CONTAINER then return true end
    return bag > (_G.NUM_BAG_SLOTS or 4)
end

function Util:ScanBank(fn)
    if not self.bankOpen then return end
    for _, bag in ipairs(self:BankContainers()) do
        local size = C.GetContainerNumSlots(bag) or 0
        for slot = 1, size do
            local link = C.GetContainerItemLink(bag, slot)
            if link then
                if fn(bag, slot, link) then return end
            end
        end
    end
end

-- Bags first, then the bank if it happens to be open.
function Util:ScanAll(fn)
    local stop = false
    self:ScanBags(function(bag, slot, link)
        if fn(bag, slot, link, false) then stop = true return true end
    end)
    if stop then return end
    self:ScanBank(function(bag, slot, link)
        return fn(bag, slot, link, true)
    end)
end

-- Find an item by key. Returns bag, slot (bags) or invSlotID (equipped).
function Util:FindItem(key)
    if not key then return nil end
    local fBag, fSlot
    self:ScanAll(function(bag, slot, link)
        if self:ItemKey(link) == key then
            fBag, fSlot = bag, slot
            return true
        end
    end)
    if fBag then return fBag, fSlot end

    for _, s in ipairs(self.slots) do
        local link = GetInventoryItemLink("player", s.id)
        if link and self:ItemKey(link) == key then
            return nil, nil, s.id
        end
    end
    return nil
end

-- All bag items that can go into slotID, sorted by quality then name.
-- opts.includeEquipped = also list what is currently worn in that slot.
function Util:GetCandidates(slotID, opts)
    opts = opts or {}
    local out = {}
    local seen = {}
    local equipped = self:GetEquipped(slotID)
    local equippedKey = equipped and equipped.key or nil

    if opts.includeEquipped and equipped then
        local info = self:ItemInfo(equipped.link)
        seen[equippedKey] = true
        table.insert(out, {
            invSlot = slotID,
            link    = equipped.link,
            key     = equippedKey,
            name    = info and info.name or "?",
            quality = info and info.quality or 1,
            texture = info and info.texture,
            worn    = true,
        })
    end

    self:ScanAll(function(bag, slot, link, fromBank)
        local equipLoc = self:EquipLoc(link)
        if equipLoc and self:FitsSlot(equipLoc, slotID) then
            local key = self:ItemKey(link)
            if key and not seen[key] and (opts.includeEquipped or key ~= equippedKey) then
                seen[key] = true
                local info = self:ItemInfo(link)
                table.insert(out, {
                    bag     = bag,
                    slot    = slot,
                    link    = link,
                    key     = key,
                    name    = info and info.name or "…",
                    quality = info and info.quality or 1,
                    texture = info and info.texture,
                    bank    = fromBank or nil,
                })
            end
        end
    end)

    -- The other ring/trinket you are wearing is also a valid swap target.
    local partner = self:PartnerSlot(slotID)
    if partner then
        local e = self:GetEquipped(partner)
        if e and not seen[e.key] then
            seen[e.key] = true
            local info = self:ItemInfo(e.link)
            table.insert(out, {
                invSlot = partner,
                link    = e.link,
                key     = e.key,
                name    = info and info.name or "?",
                quality = info and info.quality or 1,
                texture = info and info.texture,
                worn    = true,
            })
        end
    end

    table.sort(out, function(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        return (a.name or "") < (b.name or "")
    end)
    return out
end

function Util:GetBagCandidates(slotID)
    return self:GetCandidates(slotID)
end

-- Paired slot for rings / trinkets / weapons.
function Util:PartnerSlot(slotID)
    local s = self.slotByID[slotID]
    if not s then return nil end
    local pairs_ = {
        Finger0Slot  = "Finger1Slot",
        Finger1Slot  = "Finger0Slot",
        Trinket0Slot = "Trinket1Slot",
        Trinket1Slot = "Trinket0Slot",
    }
    local other = pairs_[s.key]
    return other and SlotID(other) or nil
end

-- First empty bag slot, for unequipping.
function Util:FindEmptyBagSlot()
    for bag = 0, C.NUM_BAGS do
        local size = C.GetContainerNumSlots(bag) or 0
        for slot = 1, size do
            if not C.GetContainerItemLink(bag, slot) then
                return bag, slot
            end
        end
    end
    return nil
end

function Util:QualityColor(quality)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

function Util:Truncate(text, max)
    if not text then return "" end
    if #text <= max then return text end
    return text:sub(1, max - 1) .. "…"
end
