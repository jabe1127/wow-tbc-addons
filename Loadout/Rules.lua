local ADDON, ns = ...
local Util = ns.Util

local Rules = {}
ns.Rules = Rules

-- =========================================================================
--  Helpers
-- =========================================================================
local function InInstance(kind)
    local inside, instanceType = IsInInstance()
    return inside and instanceType == kind
end

local function TargetName()
    if not UnitExists("target") then return nil end
    return UnitName("target")
end

local function NameMatches(actual, param, exact)
    if not actual or not param or param == "" then return false end
    actual = actual:lower()
    param  = param:lower()
    if exact then return actual == param end
    return actual:find(param, 1, true) ~= nil
end

local function IsBossUnit(unit)
    if not UnitExists(unit) then return false end
    if UnitClassification(unit) == "worldboss" then return true end
    if UnitLevel(unit) == -1 then return true end
    return false
end

-- =========================================================================
--  Condition catalogue
--  needsParam: nil | "text"   (free text, with a boss picker attached)
-- =========================================================================
Rules.conditions = {
    -- targeting
    { id = "target_name",  label = "Target is named…",      needsParam = "text", group = "Target",
      test = function(p) return NameMatches(TargetName(), p, true) end },
    { id = "target_like",  label = "Target name contains…", needsParam = "text", group = "Target",
      test = function(p) return NameMatches(TargetName(), p, false) end },
    { id = "target_boss",  label = "Target is a boss",      group = "Target",
      test = function() return IsBossUnit("target") end },
    { id = "target_elite", label = "Target is elite",       group = "Target",
      test = function()
          local c = UnitClassification("target")
          return c == "elite" or c == "rareelite" or c == "worldboss"
      end },
    { id = "target_player", label = "Target is a player",   group = "Target",
      test = function() return UnitExists("target") and UnitIsPlayer("target") end },

    -- auras
    { id = "aura_player", label = "You have the buff…",    needsParam = "text", group = "Buffs",
      test = function(p)
          if not p or p == "" then return false end
          local want = p:lower()
          for i = 1, 40 do
              local name = UnitBuff("player", i)
              if not name then break end
              if name:lower():find(want, 1, true) then return true end
          end
          return false
      end },
    { id = "aura_target", label = "Target has the aura…",  needsParam = "text", group = "Buffs",
      test = function(p)
          if not p or p == "" then return false end
          if not UnitExists("target") then return false end
          local want = p:lower()
          for i = 1, 40 do
              local name = UnitDebuff("target", i)
              if not name then break end
              if name:lower():find(want, 1, true) then return true end
          end
          for i = 1, 40 do
              local name = UnitBuff("target", i)
              if not name then break end
              if name:lower():find(want, 1, true) then return true end
          end
          return false
      end },

    -- movement / state
    { id = "mounted",   label = "Mounted",            group = "State", test = function() return IsMounted() end },
    { id = "flying",    label = "Flying",             group = "State", test = function() return IsFlying and IsFlying() end },
    { id = "taxi",      label = "On a flight path",   group = "State", test = function() return UnitOnTaxi("player") end },
    { id = "swimming",  label = "Swimming",           group = "State", test = function() return IsSwimming() end },
    { id = "combat",    label = "In combat",          group = "State", test = function() return UnitAffectingCombat("player") end },
    { id = "resting",   label = "Resting (inn/city)", group = "State", test = function() return IsResting() end },
    { id = "indoors",   label = "Indoors",            group = "State", test = function() return IsIndoors() end },
    { id = "outdoors",  label = "Outdoors",           group = "State", test = function() return not IsIndoors() end },
    { id = "stealth",   label = "Stealthed",          group = "State", test = function() return IsStealthed() end },

    -- location
    { id = "zone",      label = "Zone is…",           needsParam = "text", group = "Location",
      test = function(p) return NameMatches(GetRealZoneText(), p, false)
                             or NameMatches(GetSubZoneText(), p, false) end },
    { id = "raid",      label = "In a raid instance", group = "Location", test = function() return InInstance("raid") end },
    { id = "dungeon",   label = "In a dungeon",       group = "Location", test = function() return InInstance("party") end },
    { id = "battleground", label = "In a battleground", group = "Location", test = function() return InInstance("pvp") end },
    { id = "arena",     label = "In an arena",        group = "Location", test = function() return InInstance("arena") end },

    -- forms
    { id = "form1", label = "Shapeshift form 1", group = "Form", test = function() return GetShapeshiftFormID() == 1 end },
    { id = "form2", label = "Shapeshift form 2", group = "Form", test = function() return GetShapeshiftFormID() == 2 end },
    { id = "form3", label = "Shapeshift form 3", group = "Form", test = function() return GetShapeshiftFormID() == 3 end },
    { id = "form4", label = "Shapeshift form 4", group = "Form", test = function() return GetShapeshiftFormID() == 4 end },
}

Rules.conditionByID = {}
Rules.groups = {}
do
    local seen = {}
    for _, c in ipairs(Rules.conditions) do
        Rules.conditionByID[c.id] = c
        local g = c.group or "Other"
        if not seen[g] then
            seen[g] = true
            table.insert(Rules.groups, g)
        end
    end
end

function Rules:ConditionLabel(id)
    local c = self.conditionByID[id]
    return c and c.label or ("Unknown (" .. tostring(id) .. ")")
end

function Rules:NeedsParam(id)
    local c = self.conditionByID[id]
    return c and c.needsParam or nil
end

function Rules:IsTargetCondition(id)
    local c = self.conditionByID[id]
    return c and c.group == "Target"
end

function Rules:Describe(rule)
    if not rule then return "" end
    local label = self:ConditionLabel(rule.condition)
    if self:NeedsParam(rule.condition) then
        label = (label:gsub("…", "")) .. "'" .. (rule.param or "?") .. "'"
    end
    if rule.negate then
        label = "Not " .. label:sub(1, 1):lower() .. label:sub(2)
    end
    return label .. " → " .. (rule.set or "(no set)")
end

-- =========================================================================
--  Boss catalogue (TBC) for the rule editor's picker
-- =========================================================================
Rules.bosses = {
    { zone = "Karazhan", list = {
        "Attumen the Huntsman", "Moroes", "Maiden of Virtue", "The Big Bad Wolf",
        "Terestian Illhoof", "Shade of Aran", "Netherspite", "Echo of Medivh",
        "Prince Malchezaar", "Nightbane",
    }},
    { zone = "Gruul's Lair", list = { "High King Maulgar", "Gruul the Dragonkiller" }},
    { zone = "Magtheridon's Lair", list = { "Magtheridon" }},
    { zone = "Serpentshrine Cavern", list = {
        "Hydross the Unstable", "The Lurker Below", "Leotheras the Blind",
        "Fathom-Lord Karathress", "Morogrim Tidewalker", "Lady Vashj",
    }},
    { zone = "Tempest Keep", list = {
        "Al'ar", "Void Reaver", "High Astromancer Solarian", "Kael'thas Sunstrider",
    }},
    { zone = "Hyjal Summit", list = {
        "Rage Winterchill", "Anetheron", "Kaz'rogal", "Azgalor", "Archimonde",
    }},
    { zone = "Black Temple", list = {
        "High Warlord Naj'entus", "Supremus", "Shade of Akama", "Teron Gorefiend",
        "Gurtogg Bloodboil", "Reliquary of the Lost", "Mother Shahraz",
        "Illidari Council", "Illidan Stormrage",
    }},
    { zone = "Zul'Aman", list = {
        "Nalorakk", "Akil'zon", "Jan'alai", "Halazzi", "Hex Lord Malacrass", "Zul'jin",
    }},
    { zone = "Sunwell Plateau", list = {
        "Kalecgos", "Brutallus", "Felmyst", "Grand Warlock Alythess",
        "Lady Sacrolash", "M'uru", "Kil'jaeden",
    }},
}

-- =========================================================================
--  Rule list management
-- =========================================================================
local function list() return ns.cdb.rules end

function Rules:Add(condition, setName, param, negate)
    self.suppressed = nil
    table.insert(list(), {
        enabled   = true,
        condition = condition or "mounted",
        set       = setName,
        param     = param,
        negate    = negate or nil,
    })
    ns:Fire("RULES_CHANGED")
    return #list()
end

function Rules:Remove(index)
    self.suppressed = nil
    table.remove(list(), index)
    ns:Fire("RULES_CHANGED")
    self:Evaluate()
end

function Rules:Move(index, delta)
    local l = list()
    local j = index + delta
    if j < 1 or j > #l then return end
    l[index], l[j] = l[j], l[index]
    ns:Fire("RULES_CHANGED")
    self:Evaluate()
end

function Rules:Toggle(index)
    self.suppressed = nil
    local rule = list()[index]
    if rule then
        rule.enabled = not rule.enabled
        ns:Fire("RULES_CHANGED")
        self:Evaluate()
    end
end

-- Build a boss rule straight from whatever you have targeted.
function Rules:AddFromTarget(setName)
    local name = TargetName()
    if not name then
        ns:Print("You have no target.")
        return
    end
    self:Add("target_name", setName, name)
    ns:Print("Rule added for '" .. name .. "'.")
end

-- =========================================================================
--  Evaluation
-- =========================================================================
Rules.pending = nil
Rules.suppressed = nil    -- the rule you manually overrode, parked until it stops matching

function Rules:Match()
    if not ns.db.autoSwap then return nil end
    for i, rule in ipairs(list()) do
        if rule.enabled and rule.set and ns.Sets:Exists(rule.set) then
            local cond = self.conditionByID[rule.condition]
            if cond then
                local ok, result = pcall(cond.test, rule.param)
                if ok then
                    result = result and true or false
                    if rule.negate then result = not result end
                    if result then return rule, i end
                end
            end
        end
    end
    return nil
end

function Rules:Evaluate()
    if not ns.loaded or not ns.db then return end
    if not ns.db.autoSwap then return end
    if ns.Equip.running then return end

    local rule = self:Match()

    -- You changed gear by hand while a rule was in force. Leave your choice
    -- alone until that rule's situation actually ends — dismounting, leaving
    -- the raid, dropping the target — rather than yanking it straight back.
    if self.suppressed then
        if rule == self.suppressed then return end
        self.suppressed = nil
    end

    local wantSet = rule and rule.set or nil

    if wantSet == ns.cdb.activeRule then return end

    local inCombat = UnitAffectingCombat("player")

    -- Sticky: once a rule has taken hold, do not unwind it mid-fight just
    -- because you tabbed off the boss.
    if inCombat and ns.db.stickyInCombat and ns.cdb.activeRule and not wantSet then
        return
    end

    if inCombat and not ns.db.autoSwapInCombat then
        self.pending = true
        return
    end
    self.pending = nil

    if wantSet then
        if not ns.cdb.activeRule then
            ns.cdb.snapshot = Util:SnapshotEquipped()
        end
        ns.cdb.activeRule = wantSet
        ns.Sets:Equip(wantSet, true)
        if ns.db.announce then
            ns:Print("Rule fired — " .. self:Describe(rule))
        end
    else
        ns.cdb.activeRule = nil
        if ns.db.restoreOnExit and ns.cdb.snapshot then
            ns.Sets:EquipSnapshot(ns.cdb.snapshot)
        end
        ns.cdb.snapshot = nil
    end

    ns:Fire("RULES_APPLIED", wantSet)
end

-- Manual swap: hand control back to the player.
function Rules:Release()
    if ns.db and ns.db.manualOverride then
        local rule = self:Match()
        if rule then
            self.suppressed = rule
            if ns.db.announce then
                ns:Print("Manual change — parking |cffffffff"
                    .. self:ConditionLabel(rule.condition):gsub("…", "")
                    .. "|r until it stops applying.")
            end
        else
            self.suppressed = nil
        end
    else
        self.suppressed = nil
    end

    ns.cdb.activeRule = nil
    ns.cdb.snapshot   = nil
    self.pending      = nil
    ns:Fire("RULES_APPLIED", nil)
end

-- Is a rule currently parked by a manual override?
function Rules:IsSuppressed()
    return self.suppressed ~= nil
end

-- Drop the override and let rules take back over immediately.
function Rules:Resume()
    self.suppressed = nil
    self:Evaluate()
end

-- =========================================================================
--  Hooks
-- =========================================================================
local EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "UPDATE_SHAPESHIFT_FORM",
    "ZONE_CHANGED",
    "ZONE_CHANGED_INDOORS",
    "ZONE_CHANGED_NEW_AREA",
    "PLAYER_UPDATE_RESTING",
    "COMPANION_UPDATE",
    "PLAYER_MOUNT_DISPLAY_CHANGED",
    "UPDATE_STEALTH",
    "UNIT_AURA",
}

for _, e in ipairs(EVENTS) do
    if e == "UNIT_AURA" then
        ns:On(e, function(_, unit)
            if unit == "player" or unit == "target" then Rules:Evaluate() end
        end)
    else
        ns:On(e, function() Rules:Evaluate() end)
    end
end

-- Mount/swim/fly state does not fire reliably on every build, so poll too.
ns:Listen("PLAYER_READY", function()
    -- Both of these describe "what is happening right now", and neither
    -- survives a session usefully. Left in the saved variables they make the
    -- engine think a rule is still applied after a reload, so it never
    -- restores anything. Start every session with a clean slate.
    ns.cdb.activeRule = nil
    ns.cdb.snapshot   = nil
    Rules.suppressed  = nil

    C_Timer.NewTicker(0.30, function() Rules:Evaluate() end)
end)
