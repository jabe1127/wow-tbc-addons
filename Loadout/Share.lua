local ADDON, ns = ...
local Util = ns.Util

-- =========================================================================
--  Sharing sets
--
--  Encoding is deliberately dull: percent-escape anything that is not
--  alphanumeric, one record per line. It is bulkier than a compressed blob
--  but it cannot be broken by an apostrophe in a set name, and it never
--  executes anything on import.
-- =========================================================================

local Share = {}
ns.Share = Share

local HEADER = "LOADOUT1"

local function enc(str)
    return (tostring(str or ""):gsub("[^%w]", function(c)
        return string.format("%%%02X", c:byte())
    end))
end

local function dec(str)
    return (tostring(str or ""):gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

-- =========================================================================
--  Encode
-- =========================================================================
function Share:EncodeSets(names)
    local out = { HEADER }

    for _, name in ipairs(names) do
        local set = ns.Sets:Get(name)
        if set then
            table.insert(out, "S " .. enc(name) .. " " .. enc(set.icon or ""))

            for slotID, item in pairs(set.items or {}) do
                table.insert(out, table.concat({
                    "I", tostring(slotID), enc(item.key), enc(item.name or ""),
                }, " "))
            end
            for slotID in pairs(set.empty or {}) do
                table.insert(out, "E " .. tostring(slotID))
            end
            for slotID in pairs(set.ignored or {}) do
                table.insert(out, "G " .. tostring(slotID))
            end
        end
    end

    return table.concat(out, "\n")
end

-- =========================================================================
--  Decode
-- =========================================================================
function Share:Decode(text)
    if type(text) ~= "string" then return nil, "nothing to read" end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil, "nothing to read" end
    if not text:find(HEADER, 1, true) then
        return nil, "that does not look like a Loadout string"
    end

    local sets, current = {}, nil

    for line in text:gmatch("[^\r\n]+") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        local tag, rest = line:match("^(%a)%s*(.*)$")

        if tag == "S" then
            local nameEnc, iconEnc = rest:match("^(%S*)%s*(%S*)$")
            current = {
                name    = dec(nameEnc),
                icon    = (iconEnc ~= "" and dec(iconEnc)) or nil,
                items   = {},
                empty   = {},
                ignored = {},
            }
            if current.name ~= "" then
                table.insert(sets, current)
            else
                current = nil
            end

        elseif tag == "I" and current then
            local slot, key, name = rest:match("^(%-?%d+)%s+(%S*)%s*(%S*)$")
            slot = tonumber(slot)
            if slot and key and key ~= "" then
                current.items[slot] = { key = dec(key), name = dec(name) }
            end

        elseif tag == "E" and current then
            local slot = tonumber(rest)
            if slot then current.empty[slot] = true end

        elseif tag == "G" and current then
            local slot = tonumber(rest)
            if slot then current.ignored[slot] = true end
        end
    end

    if #sets == 0 then return nil, "no sets found in that string" end
    return sets
end

-- =========================================================================
--  Install
-- =========================================================================
local function UniqueName(base)
    if not ns.Sets:Exists(base) then return base end
    for i = 2, 50 do
        local candidate = base .. " " .. i
        if not ns.Sets:Exists(candidate) then return candidate end
    end
    return base .. " " .. time()
end

-- mode: "rename" (default), "overwrite", "skip"
function Share:Install(sets, mode)
    local added, replaced, skipped = 0, 0, 0

    for _, incoming in ipairs(sets) do
        local name = incoming.name
        local exists = ns.Sets:Exists(name)

        if exists and mode == "skip" then
            skipped = skipped + 1
        else
            if exists and mode ~= "overwrite" then
                name = UniqueName(name)
            end
            if exists and mode == "overwrite" then
                replaced = replaced + 1
            else
                added = added + 1
            end

            ns.cdb.sets[name] = {
                name    = name,
                icon    = incoming.icon or "Interface\\Icons\\INV_Misc_Bag_08",
                items   = incoming.items,
                empty   = incoming.empty,
                ignored = incoming.ignored,
            }
        end
    end

    ns.Sets:GetOrder()
    ns:Fire("SETS_CHANGED")
    return added, replaced, skipped
end

function Share:ImportString(text, mode)
    local sets, err = self:Decode(text)
    if not sets then
        ns:Print("|cffff6666" .. err .. "|r")
        return false
    end
    local added, replaced, skipped = self:Install(sets, mode)
    ns:Print(("Imported %d set(s)%s%s."):format(
        added,
        replaced > 0 and (", replaced " .. replaced) or "",
        skipped  > 0 and (", skipped " .. skipped)  or ""))
    return true
end

-- =========================================================================
--  Account-wide library
--  Lives in the account-level saved variables, so every character on the
--  account sees the same shelf.
-- =========================================================================
local function lib() return ns.db.library end

function Share:LibraryNames()
    local out = {}
    for name in pairs(lib()) do table.insert(out, name) end
    table.sort(out)
    return out
end

function Share:ToLibrary(setName)
    local set = ns.Sets:Get(setName)
    if not set then return false end

    local copy = { icon = set.icon, items = {}, empty = {}, ignored = {} }
    for slotID, item in pairs(set.items or {}) do
        copy.items[slotID] = { key = item.key, name = item.name }
    end
    for slotID in pairs(set.empty   or {}) do copy.empty[slotID]   = true end
    for slotID in pairs(set.ignored or {}) do copy.ignored[slotID] = true end
    copy.from = UnitName("player")

    lib()[setName] = copy
    ns:Fire("LIBRARY_CHANGED")
    return true
end

function Share:FromLibrary(name, mode)
    local stored = lib()[name]
    if not stored then return false end
    local incoming = {
        name    = name,
        icon    = stored.icon,
        items   = stored.items,
        empty   = stored.empty,
        ignored = stored.ignored,
    }
    local added, replaced = self:Install({ incoming }, mode or "rename")
    ns:Print(("Copied '%s' to this character."):format(name))
    return true
end

function Share:RemoveFromLibrary(name)
    lib()[name] = nil
    ns:Fire("LIBRARY_CHANGED")
end

function Share:LibraryEntry(name)
    return lib()[name]
end
