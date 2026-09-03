-- LogLovers Filters: per-window predicate building and live search matching
local ADDON, NS = ...

-- Does this record involve an amount that minAmount should gate?
local AMOUNT_CATS = { damage = true, healing = true, power = true }

-- profession activity cast names (lowered), used by the hide-others filters
NS.PROFESSION_CASTS = {
    ["alchemy"] = true, ["blacksmithing"] = true, ["enchanting"] = true,
    ["engineering"] = true, ["jewelcrafting"] = true, ["leatherworking"] = true,
    ["tailoring"] = true, ["first aid"] = true, ["smelting"] = true,
    ["disenchant"] = true, ["prospecting"] = true,
    ["herb gathering"] = true, ["mining"] = true, ["skinning"] = true,
}

-- crafted items are cast under their OWN name ("Heavy Netherweave Bandage"),
-- so name lists alone can never cover professions; these substrings help.
NS.PROFESSION_PATTERNS = {
    "bandage", "smelt", "prospect", "disenchant", "pick lock", "picklock",
}

-- Current zone: "none" | "party" | "raid" | "pvp" | "arena"
NS.zoneContext = "none"

local ZONE_NAMES = {
    arena = "Arena", pvp = "Battleground", party = "Dungeon",
    raid = "Raid", none = "Open world",
}

-- Where the player is, in the words the options use.
function NS.CurrentLocation()
    local ctx = NS.zoneContext
    if ctx == "party" or ctx == "raid" or ctx == "pvp" or ctx == "arena" then
        return ctx
    end
    return "world"
end

-- Who this view shows, right here, right now.
function NS.EffectiveScope(f)
    local scopes = f.scopes
    if scopes then
        return scopes[NS.CurrentLocation()] or "me"
    end
    -- settings saved before 1.3
    local legacy = f.scope or f.involve
    if legacy == "all" or legacy == "off" then return "all" end
    if legacy == "group" then return "group" end
    return "me"
end

function NS.EffectiveDirection(f)
    local d = f.direction
    if d == "out" or d == "in" then return d end
    if f.scope == "out" or f.scope == "in" then return f.scope end  -- legacy
    return "both"
end

-- Called on login and every zone change.
function NS.UpdateZoneContext()
    local ctx = "none"
    if IsInInstance then
        local inInstance, itype = IsInInstance()
        if inInstance and itype and itype ~= "none" then ctx = itype end
    end
    local function locOf(z)
        if z == "party" or z == "raid" or z == "pvp" or z == "arena" then return z end
        return "world"
    end
    local prev = NS.zoneContext
    if ctx == prev then return end
    NS.zoneContext = ctx

    -- only bother refreshing if some filter's auto rule is actually involved
    local affected, showAll = false, false
    local function check(f)
        if not f then return end
        local function at(loc)
            return (f.scopes and f.scopes[loc]) or "me"
        end
        local now, before = at(locOf(ctx)), at(locOf(prev))
        if now ~= before then
            affected = true
            if now == "all" then showAll = true end
        end
    end
    for _, cfg in ipairs(NS.db.windows or {}) do check(cfg.filter) end
    if NS.db.chat and NS.db.chat.views then
        for _, v in ipairs(NS.db.chat.views) do
            if v.kind == "combat" then check(v.combatFilter) end
        end
    end
    if not affected then return end

    NS.RefreshAllWindows()
    if NS.RefreshChat then NS.RefreshChat() end
    NS.Print((ZONE_NAMES[ctx] or "Zone") .. ": combat log now showing " ..
        (showAll and "everyone" or "only you and your pet") .. ".")
end

-- Returns true if `rec` passes window filter config `f`
local function isMine(r) return r == "player" or r == "pet" end
local function isGroup(r) return r == "party" or r == "raid" end

function NS.RecordPasses(rec, f)
    -- INVOLVEMENT GATE (most selective, runs first): the event must actually
    -- involve you. This is what makes a city or a 25-man readable - it does not
    -- care what the spell is called, so it catches every buff, bandage, craft,
    -- and pet heal from every stranger without any name list.
    local scope = NS.EffectiveScope(f)
    local dir = NS.EffectiveDirection(f)
    -- A window pinned to one unit is already as selective as it gets; running
    -- the involvement gate on top of it produced a window that stayed empty
    -- forever unless that person happened to act on you.
    local focused = (f.srcName or f.dstName) ~= nil
    if not focused and (scope ~= "all" or dir ~= "both") then
        local s, d = rec.srcRole, rec.dstRole
        -- who counts as "us" for this view
        local function us(role)
            if isMine(role) then return true end
            if scope == "all" then return role ~= nil end
            return scope == "group" and isGroup(role)
        end
        local ok
        -- "Which events" is worded about you - only what YOU do, only what is
        -- done to YOU - so it is measured against you and your pet whatever the
        -- scope says. Scope widens who else shows up in the "both" case; it
        -- used to silently cancel this test instead, which is how a window
        -- called "My damage" filled up with the enemy team's in an arena.
        if dir == "out" then
            ok = isMine(s)
        elseif dir == "in" then
            ok = isMine(d)
        else
            ok = us(s) or us(d)
        end
        -- Deaths are low-volume and high-value, so they bypass the gate for
        -- everything except unrelated friendly players (stranger deaths in a
        -- city). Mobs, bosses, your group, your pet and you always come
        -- through - otherwise you would never see a kill or a [recap] link.
        if not ok and rec.cat == "deaths" and d ~= "friendly" then
            ok = true
        end
        -- A boss ability with no target - Ground Slam, an AoE cast, a summon -
        -- has no destination role to match, so the gate used to drop the most
        -- useful line in a raid. Narrow on purpose: an NPC (never an enemy
        -- player, or a battleground turns into a wall of other people's cast
        -- bars) actually landing an untargeted ability, not failing one.
        if not ok and dir ~= "out" and rec.cat == "casts" and not rec.dn
            and (rec.srcRole == "hostile" or rec.srcRole == "neutral")
            and (rec.sub == "SPELL_CAST_START" or rec.sub == "SPELL_CAST_SUCCESS")
            and NS.IsNPC(rec.sf) then
            ok = true
        end
        if not ok then return false end
    end

    -- AoE farming: nothing but the kill lines, so a 30-mob pull is 30 readable
    -- lines with [recap] links instead of hundreds of damage rows.
    if f.aoeFarm then
        if rec.cat ~= "deaths" then return false end
        -- UNIT_DIED carries the recap link; PARTY_KILL would just double it up
        if rec.sub == "PARTY_KILL" then return false end
    end

    if not f.categories[rec.cat] then return false end

    -- Hidden auras. Global, not per-window: a zone buff you find annoying is
    -- annoying in every window, and nobody wants to blacklist it five times.
    if rec.cat == "auras" and rec.snameLower then
        local blocked = NS.db.auraBlock
        if blocked and blocked[rec.snameLower] then return false end
    end

    -- optional: drop "begins casting" lines, keep completed casts
    if f.hideCastStart and rec.sub == "SPELL_CAST_START" then return false end

    -- optional: hide other players' tradeskill activity, each individually
    if rec.cat == "casts" and rec.snameLower
        and (f.hideOtherProfessions or f.hideOtherCooking or f.hideOtherFishing) then
        local r = rec.srcRole
        if r ~= "player" and r ~= "pet" and r ~= "hostile" then
            local n = rec.snameLower
            if f.hideOtherFishing and n == "fishing" then return false end
            if f.hideOtherCooking and (n == "cooking" or n == "basic campfire") then
                return false
            end
            if f.hideOtherProfessions then
                if NS.PROFESSION_CASTS[n] then return false end
                for _, pat in ipairs(NS.PROFESSION_PATTERNS) do
                    if n:find(pat, 1, true) then return false end
                end
            end
        end
    end

    -- Source / target roles. Deaths and environment events may have nil source.
    if rec.srcRole then
        if not f.sources[rec.srcRole] then return false end
    else
        -- sourceless events (environment, some deaths): let them pass source check
    end
    if rec.dstRole then
        if not f.targets[rec.dstRole] then return false end
    end

    -- Minimum amount gate (only for amount-carrying categories)
    if f.minAmount and f.minAmount > 0 and AMOUNT_CATS[rec.cat] then
        if (rec.amt or 0) < f.minAmount then return false end
    end

    -- Unit focus (set from unit right-click menus)
    if f.srcName and (not rec.sn or string.lower(rec.sn) ~= f.srcName) then return false end
    if f.dstName and (not rec.dn or string.lower(rec.dn) ~= f.dstName) then return false end

    -- Spell allow/block list
    if f.spellMode ~= "off" then
        local key1 = rec.snameLower
        local key2 = rec.sid and tostring(rec.sid)
        local listed = (key1 and f.spellList[key1]) or (key2 and f.spellList[key2])
        if f.spellMode == "allow" then
            if not listed then return false end
        elseif f.spellMode == "block" then
            if listed then return false end
        end
    end

    return true
end

-- Live search: case-insensitive plain-text substring match
function NS.RecordMatchesSearch(rec, needle)
    if not needle or needle == "" then return true end
    return string.find(rec.plainLower, needle, 1, true) ~= nil
end

-- Normalize a user-entered spell list string: "Multi-Shot, 2643, Steady Shot"
function NS.ParseSpellList(text)
    local t = {}
    for token in string.gmatch(text or "", "[^,;]+") do
        token = token:gsub("^%s+", ""):gsub("%s+$", "")
        if token ~= "" then
            t[string.lower(token)] = true
        end
    end
    return t
end

function NS.SpellListToString(list)
    local parts = {}
    for k in pairs(list or {}) do parts[#parts + 1] = k end
    table.sort(parts)
    return table.concat(parts, ", ")
end

-------------------------------------------------------------------------------
-- Hidden auras
--
-- Keyed by lowercase spell name, because that is what the combat log gives us
-- and what the user types. Display names are kept so the options list reads the
-- way the buff is actually spelled.
-------------------------------------------------------------------------------
-- One place that decides what a name maps to, so hide / show / toggle can
-- never disagree about whitespace or case.
local function auraKey(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    return string.lower(name), name
end

local function auraChanged()
    NS.RefreshAllWindows()
    if NS.RefreshChat then NS.RefreshChat() end
    -- the options list of hidden auras is on screen more often than not when
    -- this is used, and it does not repaint itself
    if NS.RefreshOptionsPage then NS.RefreshOptionsPage("views") end
end

function NS.AuraHidden(name)
    local key = auraKey(name)
    if not key then return false end
    local b = NS.db.auraBlock
    return b and b[key] and true or false
end

function NS.HideAura(name)
    local key, display = auraKey(name)
    if not key then return false end
    NS.db.auraBlock = NS.db.auraBlock or {}
    NS.db.auraBlock[key] = display
    auraChanged()
    return true
end

function NS.ShowAura(name)
    local key = auraKey(name)
    if not key then return false end
    local b = NS.db.auraBlock
    if not b or not b[key] then return false end
    b[key] = nil
    auraChanged()
    return true
end

-- Drops anything an imported profile put here that is not a name -> name pair.
-- HiddenAuraList sorts by key, so a stray number key would error the page.
function NS.SanitizeAuraBlock(tbl)
    local clean = {}
    for k, v in pairs(tbl or {}) do
        local key = auraKey(k)
        if key then
            local _, display = auraKey(v)
            clean[key] = display or key
        end
    end
    return clean
end

function NS.ToggleAuraHidden(name)
    if NS.AuraHidden(name) then
        NS.ShowAura(name)
        return false
    end
    NS.HideAura(name)
    return true
end

-- Blocked auras, sorted for display: { {key = lower, name = as typed}, ... }
function NS.HiddenAuraList()
    local out = {}
    for key, disp in pairs(NS.db.auraBlock or {}) do
        if type(key) == "string" then
            out[#out + 1] = { key = key, name = (type(disp) == "string" and disp) or key }
        end
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

-- Auras currently on a unit, so the options can offer "pick from what I have".
-- Only the first return of UnitBuff/UnitDebuff is used: the rest of the
-- signature moved around between client versions, the name never did.
function NS.CurrentAuras(unit)
    unit = unit or "player"
    local out, seen = {}, {}
    local function scan(fn, kind)
        if not fn then return end
        for i = 1, 40 do
            local ok, name = pcall(fn, unit, i)
            if not ok or not name then break end
            local key = string.lower(name)
            if not seen[key] then
                seen[key] = true
                out[#out + 1] = { name = name, key = key, kind = kind }
            end
        end
    end
    scan(UnitBuff, "buff")
    scan(UnitDebuff, "debuff")
    return out
end
