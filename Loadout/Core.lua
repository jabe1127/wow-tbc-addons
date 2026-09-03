local ADDON, ns = ...

ns.ADDON   = ADDON
ns.VERSION = "1.3.0"
ns.TITLE   = "Loadout"
ns.SHORT   = "LO"

_G.Loadout = ns
_G.JGM = ns   -- old name, kept so existing /run macros keep working

-- =========================================================================
--  Client compatibility layer
--  Anniversary / Classic clients moved container functions into C_Container
--  at different times. Everything below goes through ns.C so the rest of the
--  addon never has to care which build it is running on.
-- =========================================================================
local C = {}
ns.C = C

local CC = _G.C_Container

if CC and CC.GetContainerNumSlots then
    C.GetContainerNumSlots = CC.GetContainerNumSlots
    C.GetContainerItemLink = CC.GetContainerItemLink
    C.PickupContainerItem  = CC.PickupContainerItem
    C.GetContainerItemID   = CC.GetContainerItemID
    C.UseContainerItem     = CC.UseContainerItem
    C.IsItemLocked = function(bag, slot)
        local info = CC.GetContainerItemInfo(bag, slot)
        return (info and info.isLocked) and true or false
    end
    C.GetContainerItemInfo = function(bag, slot)
        local i = CC.GetContainerItemInfo(bag, slot)
        if not i then return nil end
        return i.iconFileID, i.stackCount, i.isLocked, i.quality, i.isReadable,
               i.hasLoot, i.hyperlink, i.isFiltered, i.hasNoValue, i.itemID
    end
else
    C.GetContainerNumSlots = _G.GetContainerNumSlots
    C.GetContainerItemLink = _G.GetContainerItemLink
    C.PickupContainerItem  = _G.PickupContainerItem
    C.GetContainerItemID   = _G.GetContainerItemID
    C.UseContainerItem     = _G.UseContainerItem
    C.IsItemLocked = function(bag, slot)
        local _, _, locked = _G.GetContainerItemInfo(bag, slot)
        return locked and true or false
    end
    C.GetContainerItemInfo = _G.GetContainerItemInfo
end

-- =========================================================================
--  Interaction lock
--
--  UseContainerItem means "sell" at a merchant, "attach" at a mailbox and
--  "deposit" at a bank. Checking whether a frame is visible turned out to be
--  unreliable — UI replacements rename or reparent those frames — so the
--  lock is driven by the game's own open/close events instead, with a grace
--  period afterwards to cover anything still in flight.
-- =========================================================================
ns.interaction = { count = 0, until_ = 0, what = nil }

local GRACE = 3.0

function ns:Interacting()
    if self.interaction.count > 0 then return true, self.interaction.what end
    if GetTime() < self.interaction.until_ then return true, self.interaction.what end
    return false
end

function ns:InteractionOpened(what)
    self.interaction.count = self.interaction.count + 1
    self.interaction.what  = what
end

function ns:InteractionClosed(what)
    self.interaction.count = math.max(0, self.interaction.count - 1)
    self.interaction.until_ = GetTime() + GRACE
end

do
    local raw = C.UseContainerItem
    C.UseContainerItem = function(bag, slot)
        local busy, what = ns:Interacting()
        if busy then
            print("|cffff5555Loadout|r: item action blocked ("
                .. tostring(what or "window open") .. ").")
            return
        end
        return raw(bag, slot)
    end
end

C.NUM_BAGS = _G.NUM_BAG_SLOTS or 4

-- =========================================================================
--  Event bus
-- =========================================================================
local bus = CreateFrame("Frame")
ns.bus = bus

local handlers = {}

function ns:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        -- Some events do not exist on every build; never let that break load.
        pcall(bus.RegisterEvent, bus, event)
    end
    table.insert(handlers[event], fn)
end

bus:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], event, ...)
        if not ok then
            print("|cffff5555Loadout error|r (" .. event .. "): " .. tostring(err))
        end
    end
end)

-- Internal message bus (addon -> addon), used by the UI to refresh itself.
local msgs = {}

function ns:Listen(msg, fn)
    msgs[msg] = msgs[msg] or {}
    table.insert(msgs[msg], fn)
end

function ns:Fire(msg, ...)
    local list = msgs[msg]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then
            print("|cffff5555Loadout error|r (" .. msg .. "): " .. tostring(err))
        end
    end
end

-- =========================================================================
--  Saved variables
-- =========================================================================
ns.defaults = {
    -- account wide
    scale            = 1.0,
    locked           = false,
    showEmptySlots   = true,
    flyoutColumns    = 6,
    flyoutSize       = 34,
    hoverDelay       = 0.30,
    hoverFromMain    = true,   -- flyouts from the Loadout window
    hoverFromPaper   = true,   -- flyouts from Blizzard's character sheet
    showCharButton   = true,   -- show the Loadout tab on the character frame
    autoSwap         = true,   -- master switch for rules
    autoSwapInCombat = false,  -- allow rules to fire while in combat
    stickyInCombat   = true,   -- keep an applied rule until combat ends
    restoreOnExit    = true,   -- restore previous gear when no rule matches
    manualOverride   = true,   -- a manual swap parks the matching rule until it stops matching
    announce         = false,  -- chat message on set equip
    confirmDelete    = true,
    equipSound       = true,
    library          = {},     -- account-wide set library, shared by every character
    tooltipSetInfo   = true,   -- "In sets: …" line on item tooltips
    queuesEnabled    = true,   -- slot queues swap on their own
    queuesInCombat   = true,   -- ...including mid-fight (the point, for trinkets)
    autoAmmoRefill   = true,   -- reload automatically when the slot runs dry
    minimap          = { hide = false, angle = 214 },
    bar = {                    -- floating click-to-equip icon bar
        show     = false,
        size     = 32,
        spacing  = 3,
        vertical = false,
        wrap     = 0,          -- 0 = never wrap
        backdrop = true,
        labels   = false,
        actions  = 0,          -- extra click-to-use slots for spells/macros/items
    },
    gearbar = {                -- floating line of equipment slots
        show         = false,
        size         = 32,
        spacing      = 3,
        vertical     = false,
        wrap         = 0,
        backdrop     = true,
        hideEmpty    = false,
        showCosmetic = false,  -- include shirt and tabard
    },
}

ns.charDefaults = {
    actions   = {},   -- [index] = { type=, name=, ... } for the bar's action slots
    holds     = {},   -- items that must not be stripped while their buff is up
    queues    = {},   -- [slotID] = { entries = {...}, auto = true }
    library   = nil,  -- (account-wide set library lives in Loadout_DB)
    sets      = {},   -- [name] = setTable
    order     = {},   -- display order of set names
    rules     = {},   -- ordered list, index 1 = highest priority
    ui        = {},   -- frame positions
    snapshot  = nil,  -- gear saved before the first rule swap
    activeRule = nil,
}

local function ApplyDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            if type(v) == "table" then
                dst[k] = {}
                ApplyDefaults(dst[k], v)
            else
                dst[k] = v
            end
        elseif type(v) == "table" and type(dst[k]) == "table" then
            ApplyDefaults(dst[k], v)
        end
    end
    return dst
end
ns.ApplyDefaults = ApplyDefaults

function ns:Print(...)
    print("|cff5fd7ffLoadout|r:", ...)
end

-- =========================================================================
--  Boot
-- =========================================================================
ns:On("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end

    -- Carry over anything saved under the addon's previous name. The old
    -- file has to be renamed on disk for the client to hand it to us; see
    -- the notes shipped with this version.
    if not Loadout_DB and JGM_DB then
        Loadout_DB = JGM_DB
        JGM_DB = nil
    end
    if not Loadout_CharDB and JGM_CharDB then
        Loadout_CharDB = JGM_CharDB
        JGM_CharDB = nil
    end

    Loadout_DB     = ApplyDefaults(Loadout_DB or {}, ns.defaults)
    Loadout_CharDB = ApplyDefaults(Loadout_CharDB or {}, ns.charDefaults)

    ns.db  = Loadout_DB
    ns.cdb = Loadout_CharDB

    ns.playerClass = select(2, UnitClass("player"))
    ns.classColor  = (RAID_CLASS_COLORS and RAID_CLASS_COLORS[ns.playerClass])
                     or { r = 0.4, g = 0.8, b = 1.0 }

    ns.loaded = true
    ns:Fire("DB_READY")
end)

ns:On("BANKFRAME_OPENED", function()
    ns.Util.bankOpen = true
    ns:InteractionOpened("bank")
    ns:Fire("BANK_STATE", true)
end)

ns:On("BANKFRAME_CLOSED", function()
    ns.Util.bankOpen = false
    ns:InteractionClosed("bank")
    ns:Fire("BANK_STATE", false)
end)

for _, pair in ipairs({
    { "MERCHANT_SHOW",            "MERCHANT_CLOSED",           "vendor" },
    { "MAIL_SHOW",                "MAIL_CLOSED",               "mailbox" },
    { "TRADE_SHOW",               "TRADE_CLOSED",              "trade" },
    { "AUCTION_HOUSE_SHOW",       "AUCTION_HOUSE_CLOSED",      "auction house" },
    { "GUILDBANKFRAME_OPENED",    "GUILDBANKFRAME_CLOSED",     "guild bank" },
    { "OPEN_TABARD_FRAME",        "CLOSE_TABARD_FRAME",        "tabard vendor" },
    { "TRAINER_SHOW",             "TRAINER_CLOSED",            "trainer" },
    { "LOOT_OPENED",              "LOOT_CLOSED",               "loot window" },
}) do
    local openEvent, closeEvent, label = pair[1], pair[2], pair[3]
    ns:On(openEvent,  function() ns:InteractionOpened(label) end)
    ns:On(closeEvent, function() ns:InteractionClosed(label) end)
end

-- Modern clients funnel every one of these through a single pair of events.
ns:On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function() ns:InteractionOpened("a window") end)
ns:On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function() ns:InteractionClosed("a window") end)

ns:On("PLAYER_LOGIN", function()
    ns:Fire("PLAYER_READY")
end)

-- =========================================================================
--  Slash commands
-- =========================================================================
SLASH_LOADOUT1 = "/lo"
SLASH_LOADOUT2 = "/loadout"
SLASH_LOADOUT3 = "/gear"
SLASH_LOADOUT4 = "/jgm"      -- previous name, kept so old macros keep working

-- Short, macro-friendly aliases. Macros have a 255-character budget, so
-- "/je Snapshot" beats "/lo equip Snapshot".
SLASH_LOADOUTEQUIP1  = "/le"
SLASH_LOADOUTEQUIP2  = "/loadoutequip"
SLASH_LOADOUTEQUIP3  = "/je"
SlashCmdList.LOADOUTEQUIP = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local name, err = ns.Sets:Resolve(msg)
    if err then ns:Print("'" .. msg .. "' matches more than one set.") return end
    if not name then ns:Print("No set matching '" .. msg .. "'.") return end
    ns.Sets:Equip(name)
    ns.Rules:Release()
end

SLASH_LOADOUTTOGGLE1 = "/lt"
SLASH_LOADOUTTOGGLE2 = "/loadouttoggle"
SLASH_LOADOUTTOGGLE3 = "/jt"
SlashCmdList.LOADOUTTOGGLE = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local name, err = ns.Sets:Resolve(msg)
    if err then ns:Print("'" .. msg .. "' matches more than one set.") return end
    if not name then ns:Print("No set matching '" .. msg .. "'.") return end
    ns.Sets:Toggle(name)
    ns.Rules:Release()
end

-- Run a gear command after a delay.
SLASH_LOADOUTDELAY1 = "/ld"
SLASH_LOADOUTDELAY2 = "/loadoutdelay"
SLASH_LOADOUTDELAY3 = "/jd"
SlashCmdList.LOADOUTDELAY = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")

    if msg:lower() == "cancel" then
        local n = ns:CancelDelays()
        ns:Print(n == 0 and "Nothing was pending." or ("Cancelled " .. n .. " pending swap(s)."))
        return
    end

    local secs, rest = msg:match("^(%d*%.?%d+)%s*(.-)$")
    if not secs then
        ns:Print("Usage: /jd <seconds> [set or command]   ·   /jd cancel")
        return
    end

    ns:Delay(secs, function() ns:RunGearCommand(rest) end,
        (rest ~= "" and rest or "restore"))
end

-- Wait for the current cast to land, then swap.
SLASH_LOADOUTAFTER1 = "/la"
SLASH_LOADOUTAFTER2 = "/loadoutafter"
SLASH_LOADOUTAFTER3 = "/ja"
SlashCmdList.LOADOUTAFTER = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" then
        ns:ArmAfterCast(nil)   -- restore previous gear
        return
    end
    local name, err = ns.Sets:Resolve(msg)
    if err then ns:Print("'" .. msg .. "' matches more than one set.") return end
    if not name then ns:Print("No set matching '" .. msg .. "'.") return end
    ns:ArmAfterCast(name)
end

SLASH_LOADOUTBACK1 = "/lb"
SLASH_LOADOUTBACK2 = "/loadoutback"
SLASH_LOADOUTBACK3 = "/jb"
SlashCmdList.LOADOUTBACK = function()
    ns.Sets:Restore()
    ns.Rules:Release()
end

SlashCmdList.LOADOUT = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "show" then
        ns:Fire("TOGGLE_MAIN")
    elseif cmd == "config" or cmd == "options" or cmd == "opt" then
        ns:Fire("TOGGLE_OPTIONS")
    elseif (cmd == "equip" or cmd == "e") and rest ~= "" then
        local name, err = ns.Sets:Resolve(rest)
        if err then ns:Print("'" .. rest .. "' matches more than one set.")
        elseif not name then ns:Print("No set matching '" .. rest .. "'.")
        else ns.Sets:Equip(name) ns.Rules:Release() end
    elseif (cmd == "toggle" or cmd == "t") and rest ~= "" then
        local name, err = ns.Sets:Resolve(rest)
        if err then ns:Print("'" .. rest .. "' matches more than one set.")
        elseif not name then ns:Print("No set matching '" .. rest .. "'.")
        else ns.Sets:Toggle(name) ns.Rules:Release() end
    elseif cmd == "restore" or cmd == "back" then
        ns.Sets:Restore()
        ns.Rules:Release()
    elseif cmd == "item" and rest ~= "" then
        ns.Equip:EquipByName(rest, 1)
        ns.Rules:Release()
    elseif cmd == "item2" and rest ~= "" then
        ns.Equip:EquipByName(rest, 2)
        ns.Rules:Release()
    elseif cmd == "save" and rest ~= "" then
        ns.Sets:SaveCurrent(rest)
        ns:Print("Saved set: " .. rest)
    elseif cmd == "delete" and rest ~= "" then
        ns.Sets:Delete(rest)
        ns:Print("Deleted set: " .. rest)
    elseif cmd == "list" then
        ns:Print("Sets:")
        for _, name in ipairs(ns.Sets:GetOrder()) do
            print("   - " .. name)
        end
    elseif cmd == "edit" and rest ~= "" then
        ns:Fire("OPEN_EDITOR", rest)
    elseif cmd == "scan" then
        ns:Print("bag scan:")
        local total, equippable = 0, 0
        ns.Util:ScanBags(function(bag, slot, link)
            total = total + 1
            local loc = ns.Util:EquipLoc(link)
            if loc and loc ~= "" then equippable = equippable + 1 end
        end)
        print("   " .. total .. " item(s) in bags, " .. equippable .. " equippable")
        for _, sl in ipairs(ns.Util.slots) do
            local list = ns.Util:GetCandidates(sl.id)
            if #list > 0 then
                local names = {}
                for i = 1, math.min(#list, 4) do names[i] = list[i].name end
                print("   " .. sl.label .. ": " .. #list .. " — " .. table.concat(names, ", "))
            end
        end
    elseif cmd == "next" and rest ~= "" then
        local target = rest:lower()
        for _, sl in ipairs(ns.Util.slots) do
            if sl.label:lower():find(target, 1, true) or sl.key:lower():find(target, 1, true) then
                ns.Queue:Cycle(sl.id)
                return
            end
        end
        ns:Print("No slot matching '" .. rest .. "'.")
    elseif cmd == "ammo" then
        if rest:lower() == "list" then
            local list = ns.Ammo:Candidates()
            if #list == 0 then
                ns:Print("No usable ammunition in your bags.")
            else
                ns:Print("ammunition, best first:")
                for i, a in ipairs(list) do
                    print(string.format("   %d. %s — %.1f dps (%d)", i, a.name, a.dps, a.count))
                end
            end
        else
            ns.Ammo:EquipBest(false, true)
        end
    elseif cmd == "gearbar" or cmd == "gb" then
        ns.db.gearbar.show = not ns.db.gearbar.show
        ns:Fire("GEARBAR_UPDATED")
        ns:Print("Gear bar " .. (ns.db.gearbar.show and "shown." or "hidden."))
    elseif cmd == "bar" then
        ns.db.bar.show = not ns.db.bar.show
        ns:Fire("BAR_UPDATED")
        ns:Print("Set bar " .. (ns.db.bar.show and "shown." or "hidden."))
    elseif cmd == "boss" and rest ~= "" then
        ns.Rules:AddFromTarget(rest)
    elseif cmd == "off" or cmd == "undress" then
        local armorOnly = rest:lower():find("armor") or rest:lower():find("armour")
        ns.Equip:UnequipAll(false, armorOnly and true or false)
        ns.Rules:Release()
    elseif cmd == "unlock" then
        ns.db.locked = false
        ns:Print("Frames unlocked.")
    elseif cmd == "lock" then
        ns.db.locked = true
        ns:Print("Frames locked.")
    elseif cmd == "reset" then
        wipe(ns.cdb.ui)
        ns:Fire("RESET_POSITIONS")
        ns:Print("Frame positions reset.")
    else
        ns:Print("commands:")
        print("   /lo                 toggle the gear window")
        print("   /lo config          open the settings window")
        print("   /lo equip <name>    equip a set")
        print("   /lo edit <name>     open the set editor")
        print("   /lo bar             toggle the floating set bar")
        print("   /lo gearbar         toggle the floating gear bar")
        print("   /lo next <slot>     step to the next item queued for a slot")
        print("   /lo ammo            load the best ammunition you are carrying")
        print("   /lo ammo list       rank the ammunition in your bags by dps")
        print("   /lo scan            diagnostic: what Loadout sees in your bags")
        print("|cff5fd7ffFor macros:|r")
        print("   /le <set>            equip a set")
        print("   /lt <set>            toggle a set on, then back off again")
        print("   /lb                  go back to the gear you had before")
        print("   /la [set]            wait for the cast to land, then swap (blank = go back)")
        print("   /ld <secs> [set]     swap after a delay (blank set = go back)")
        print("   /ld cancel           cancel anything waiting on a timer")
        print("   /lo item <name>     equip one item by name from your bags")
        print("   /lo item2 <name>    same, but into the second ring/trinket slot")
        print("   /lo save <name>     save current gear as a set")
        print("   /lo boss <name>     rule: equip <name> when you target your current target")
        print("   /lo delete <name>   delete a set")
        print("   /lo off             take your gear off")
        print("   /lo off armor       strip armour only, leaving weapons alone")
        print("   /lo list            list sets")
        print("   /lo lock | unlock | reset")
    end
end

-- =========================================================================
--  Key bindings
-- =========================================================================
BINDING_HEADER_LOADOUT       = "Loadout"
BINDING_NAME_LOADOUT_TOGGLE  = "Toggle gear window"
BINDING_NAME_LOADOUT_OPTIONS = "Toggle options"
BINDING_NAME_LOADOUT_UNDRESS = "Take gear off"
for i = 1, 10 do
    _G["BINDING_NAME_LOADOUT_SET" .. i] = "Equip set " .. i
end

-- Called from Bindings.xml
function ns:EquipSetByIndex(index)
    local name = self.Sets:GetOrder()[index]
    if name then
        self.Sets:Equip(name)
        self.Rules:Release()
    else
        self:Print("No set in slot " .. index .. ".")
    end
end
