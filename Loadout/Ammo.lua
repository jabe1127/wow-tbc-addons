local ADDON, ns = ...
local Util, C = ns.Util, ns.C

-- =========================================================================
--  Ammunition
--
--  Deliberately minimal. There is exactly one thing this does on its own:
--  when the ammo slot is EMPTY, load the hardest-hitting stack your weapon
--  can fire. It never replaces ammunition you are already carrying loaded,
--  so if you deliberately put something else on, it stays on.
-- =========================================================================

local Ammo = {}
ns.Ammo = Ammo

-- ---------------------------------------------------------------- type ---
local ARROW  = _G.ARROW  or "Arrow"
local BULLET = _G.BULLET or "Bullet"

function Ammo:RequiredType()
    if not Util.RANGED then return nil end
    local link = GetInventoryItemLink("player", Util.RANGED)
    if not link then return nil end

    local _, _, _, _, _, _, subType = GetItemInfo(link)
    if not subType then return nil end

    local s = subType:lower()
    if s:find("bow") or s:find("crossbow") then return ARROW end
    if s:find("gun") then return BULLET end
    return nil
end

-- ----------------------------------------------------------------- dps ---
local scanner = CreateFrame("GameTooltip", "LoadoutAmmoScanner", nil, "GameTooltipTemplate")
scanner:SetOwner(UIParent, "ANCHOR_NONE")

local dpsCache = {}

function Ammo:DPS(link)
    local itemID = Util:ItemID(link)
    if not itemID then return 0 end
    if dpsCache[itemID] then return dpsCache[itemID] end

    local value
    pcall(function()
        scanner:ClearLines()
        scanner:SetHyperlink(link)
        for i = 1, scanner:NumLines() do
            local fs = _G["LoadoutAmmoScannerTextLeft" .. i]
            local text = fs and fs:GetText()
            if text and text:lower():find("per second") then
                local n = text:match("([%d]+%.?[%d]*)")
                if n then value = tonumber(n) break end
            end
        end
    end)

    if not value then
        -- Item level tracks ammo damage closely enough to rank by.
        value = (select(4, GetItemInfo(link)) or 0) / 10
    end

    dpsCache[itemID] = value
    return value
end

-- ------------------------------------------------------------ what I have --
function Ammo:Candidates()
    local want = self:RequiredType()
    local playerLevel = UnitLevel("player") or 70
    local out = {}

    Util:ScanBags(function(bag, slot, link)
        if Util:EquipLoc(link) ~= "INVTYPE_AMMO" then return end

        local name, _, quality, _, reqLevel, _, subType = GetItemInfo(link)
        if not name then return end
        if want and subType and subType ~= want then return end
        if reqLevel and reqLevel > playerLevel then return end

        local count = 1
        if C.GetContainerItemInfo then
            local _, stack = C.GetContainerItemInfo(bag, slot)
            count = stack or 1
        end

        table.insert(out, {
            bag = bag, slot = slot, link = link,
            key = Util:ItemKey(link), name = name,
            quality = quality or 1, count = count,
            dps = self:DPS(link),
        })
    end)

    table.sort(out, function(a, b)
        if a.dps ~= b.dps then return a.dps > b.dps end
        return a.count > b.count
    end)

    return out
end

function Ammo:Best()
    return self:Candidates()[1]
end

function Ammo:LoadedID()
    return GetInventoryItemID and GetInventoryItemID("player", Util.AMMO or 0) or nil
end

-- ---------------------------------------------------------------- load ---
-- force = the player asked for this explicitly, so replace what is loaded.
function Ammo:EquipBest(silent, force)
    if not Util.AMMO then return false end

    local busy, what = ns:Interacting()
    if busy then
        if not silent then
            ns:Print("Not touching ammunition while " .. tostring(what or "a window") .. " is in play.")
        end
        return false
    end

    if not force and self:LoadedID() then
        return true   -- something is loaded; leave it alone
    end

    local best = self:Best()
    if not best then
        if not silent then ns:Print("No usable ammunition in your bags.") end
        return false
    end

    if self:LoadedID() == Util:ItemID(best.link) then
        if not silent then ns:Print("Already using " .. best.name .. ".") end
        return true
    end

    C.UseContainerItem(best.bag, best.slot)
    if not silent then
        ns:Print("Loading " .. best.name .. " ("
            .. string.format("%.1f", best.dps) .. " dps).")
    end
    return true
end

-- =========================================================================
--  Refill watcher
--
--  Fires only on an empty slot, only when nothing is being interacted with,
--  and never more than once every few seconds.
-- =========================================================================
local lastTry = 0

local function CheckAmmo()
    if not ns.db or not ns.db.autoAmmoRefill then return end
    if not Util.AMMO then return end
    if ns.Equip.running then return end
    if ns:Interacting() then return end
    if GetTime() - lastTry < 3 then return end

    if not GetInventoryItemLink("player", Util.RANGED or 0) then return end
    if Ammo:LoadedID() then return end   -- still have ammo loaded

    lastTry = GetTime()
    C_Timer.After(0.3, function()
        if ns:Interacting() then return end
        if Ammo:LoadedID() then return end
        Ammo:EquipBest(true)
    end)
end

ns:On("PLAYER_EQUIPMENT_CHANGED", CheckAmmo)
ns:On("UNIT_INVENTORY_CHANGED", function(_, unit)
    if unit == "player" then CheckAmmo() end
end)
