--[[--------------------------------------------------------------------------
    JCT - Events.lua
    Combat log parsing, classification, merging, filtering and routing.

    Hot path discipline
    -------------------
    * Bail out of COMBAT_LOG_EVENT_UNFILTERED as early as possible. In a
      25-man raid this fires thousands of times per second and almost none
      of it concerns you.
    * No table allocation on the reject path.
    * Thresholds are applied AFTER merging, so a "hide hits under 500" filter
      never silently eats a merged 5000 damage tick train.
    * The FIRST hit inside a merge window is displayed immediately and only
      the hits behind it are folded together. Merging that delays everything
      by a fixed interval destroys the timing information in the stream,
      which is the main thing worth reading if you are pacing your own
      attacks.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

local Events = {}
ns.Events = Events

local band = bit and bit.band or function() return 0 end
local GetTime = GetTime
local strlower = string.lower
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo

local AFFILIATION_MINE = 0x00000001
local REACTION_HOSTILE = 0x00000040
local CONTROL_PLAYER   = 0x00000100

local SPELLID_AUTO_SHOT = 75

-- Counters for /jct debug. Incremented past the early bail only, so this
-- costs nothing on the thousands of raid events that are not yours.
Events.stats = { relevant = 0, shown = 0 }

--------------------------------------------------------------------------
-- Labels
--------------------------------------------------------------------------

local MISS_LABEL = {
    MISS    = "Miss",
    DODGE   = "Dodge",
    PARRY   = "Parry",
    BLOCK   = "Block",
    RESIST  = "Resist",
    ABSORB  = "Absorb",
    IMMUNE  = "Immune",
    EVADE   = "Evade",
    DEFLECT = "Deflect",
    REFLECT = "Reflect",
}

local ENV_LABEL = {
    DROWNING = "Drowning",
    FALLING  = "Falling",
    FATIGUE  = "Fatigue",
    FIRE     = "Fire",
    LAVA     = "Lava",
    SLIME    = "Slime",
}

--------------------------------------------------------------------------
-- Rank aliasing
--
-- In TBC every rank of a spell has its own spellID, so merging on the raw
-- ID would split "Steady Shot (Rank 3)" from "Steady Shot (Rank 4)".
-- Collapse by name the first time each is seen; no curated table needed.
-- This ID is used ONLY as a merge key - the icon and name shown always come
-- from the real per-event spellID.
--------------------------------------------------------------------------

local nameToID = {}

local function canonicalID(spellID, spellName)
    if not spellID then return nil end
    if not spellName then return spellID end
    local known = nameToID[spellName]
    if known then return known end
    nameToID[spellName] = spellID
    return spellID
end

--------------------------------------------------------------------------
-- Thresholds
--------------------------------------------------------------------------

local OUT_DAMAGE_CLASSES = {
    outDamage = true, outMelee = true, outAutoShot = true, outDot = true,
}

local function passesThreshold(class, amount)
    local f = ns.db.filters
    if not amount then return true end
    local a = amount < 0 and -amount or amount

    if OUT_DAMAGE_CLASSES[class] then
        return a >= (f.minOutDamage or 0)
    elseif class == "outCrit" then
        return a >= (f.minOutCrit or 0)
    elseif class == "petDamage" then
        return a >= (f.minPetDamage or 0)
    elseif class == "petCrit" then
        return a >= (f.minPetCrit or 0)
    elseif class == "inDamage" then
        return a >= (f.minInDamage or 0)
    elseif class == "inCrit" then
        return a >= (f.minInCrit or 0)
    elseif class == "outHeal" or class == "petHeal" then
        return a >= (f.minHeal or 0)
    elseif class == "outHealCrit" then
        return a >= (f.minHealCrit or 0)
    elseif class == "inHeal" then
        return a >= (f.minInHeal or 0)
    elseif class == "power" then
        return a >= (f.minPower or 0)
    end
    return true
end

--------------------------------------------------------------------------
-- Colour selection
--
-- Class first, always. Melee swings and Auto Shot are their own classes so
-- they get their own colour and their own routing, and a crit keeps crit
-- identity instead of being repainted by its spell school.
--------------------------------------------------------------------------

local function colorFor(class, info)
    local Format = ns.Format
    if (class == "outDamage" or class == "outDot") and info and info.school then
        return Format.SchoolColor(info.school, class)
    end
    return Format.ClassColor(class)
end

--------------------------------------------------------------------------
-- Display
--------------------------------------------------------------------------

local function Display(class, amount, info)
    local db = ns.db
    if not db or not db.enabled then return end
    if db.filters.onlyInCombat and not ns.inCombat then return end

    info = info or {}

    if not passesThreshold(class, amount) then return end

    local frameName = db.routing[class]
    if not frameName then return end
    local df = ns.Engine.frames[frameName]
    if not df or not df.cfg then return end

    local r, g, b = colorFor(class, info)
    if info.forceColor then
        r, g, b = info.forceColor[1], info.forceColor[2], info.forceColor[3]
    end

    local iconSize = db.format.iconSize
    if not iconSize or iconSize == 0 then iconSize = df.cfg.fontSize end

    local text = ns.Format.Build({
        amount      = amount,
        text        = info.text,
        spellID     = info.spellID,
        spellName   = info.spellName,
        count       = info.count,
        crit        = info.crit,
        suffix      = info.suffix,
        iconSize    = iconSize,
        iconSide    = df.cfg.iconSide,
        iconTexture = info.iconTexture,
    })

    ns.Engine:Add(frameName, text, r, g, b, {
        crit = info.crit,
        anchorGUID = info.anchorGUID,
    })
    Events.stats.shown = Events.stats.shown + 1
end

Events.Display = Display

--------------------------------------------------------------------------
-- Merging
--
-- Model: the first event of a key opens a window and is shown immediately.
-- Events arriving inside that window accumulate. When the window closes the
-- accumulated total is shown as one number with a hit count. So a single
-- hit is never delayed, and a burst costs you two lines instead of twenty.
--------------------------------------------------------------------------

local pending = {}
local pendingCount = 0

local mergeDriver = CreateFrame("Frame", "JCT_MergeDriver")
mergeDriver:Hide()

local function discard(key)
    if pending[key] then
        pending[key] = nil
        pendingCount = pendingCount - 1
    end
end

local function flushEntry(key, entry)
    discard(key)
    if not entry or entry.count <= 0 then return end
    Display(entry.class, entry.isText and nil or entry.amount, {
        crit        = entry.crit,
        spellID     = entry.spellID,
        spellName   = entry.spellName,
        school      = entry.school,
        count       = entry.count,
        iconTexture = entry.iconTexture,
        text        = entry.text,
        suffix      = entry.suffix,
        forceColor  = entry.forceColor,
        anchorGUID  = entry.anchorGUID,
    })
end

mergeDriver:SetScript("OnUpdate", function(self, elapsed)
    self.acc = (self.acc or 0) + elapsed
    if self.acc < 0.05 then return end
    self.acc = 0
    local now = GetTime()
    for key, entry in pairs(pending) do
        if now >= entry.due then
            flushEntry(key, entry)
        end
    end
    if pendingCount <= 0 then
        pendingCount = 0
        self:Hide()
    end
end)

local function openWindow(key, class, info, due)
    pending[key] = {
        class       = class,
        amount      = 0,
        count       = 0,
        isText      = info.text and true or false,
        crit        = info.crit,
        spellID     = info.spellID,
        spellName   = info.spellName,
        school      = info.school,
        iconTexture = info.iconTexture,
        text        = info.text,
        suffix      = info.suffix,
        forceColor  = info.forceColor,
        anchorGUID  = info.anchorGUID,
        due         = due,
    }
    pendingCount = pendingCount + 1
    if not mergeDriver:IsShown() then mergeDriver:Show() end
end

local function Push(class, amount, info)
    local db = ns.db
    if not db or not db.enabled then return end
    info = info or {}

    local m = db.merge
    local interval = m.enabled and m.intervals[class] or 0

    -- Crits bypass the merger unless explicitly allowed: a crit is
    -- information you want the instant it lands, not folded into a total.
    if info.crit and not m.mergeCrits then interval = 0 end

    if not interval or interval <= 0 then
        Display(class, amount, info)
        return
    end

    local spellKey = info.canonID or info.text or "other"
    -- Incoming damage is keyed by attacker too, otherwise two adds hitting
    -- you sum into one number and you cannot tell there are two of them.
    local destKey = info.destKey or ""
    -- A nameplate-anchored stream must also split per unit, or hits on three
    -- different mobs would merge into one number floating over one of them.
    if info.anchorGUID and ns.Engine:IsNameplateFrame(db.routing[class]) then
        destKey = destKey .. "\001" .. info.anchorGUID
    end
    local key = class .. "\001" .. tostring(spellKey) .. "\001"
                .. (info.crit and "c" or "n") .. "\001" .. destKey

    local entry = pending[key]
    local now = GetTime()

    if not entry then
        Display(class, amount, info)
        openWindow(key, class, info, now + interval)
    elseif now >= entry.due then
        -- Window closed but the sweeper has not run yet. Flush what is
        -- there, show this one now, and open a fresh window. Without this
        -- a dense stream keeps pushing the deadline out and never draws.
        flushEntry(key, entry)
        Display(class, amount, info)
        openWindow(key, class, info, now + interval)
    else
        entry.amount = entry.amount + (amount or 0)
        entry.count  = entry.count + 1
    end
end

Events.Push = Push

function Events:FlushAll()
    for key, entry in pairs(pending) do
        flushEntry(key, entry)
    end
    pendingCount = 0
    mergeDriver:Hide()
end

--------------------------------------------------------------------------
-- Spell tracking for the filter UI
--------------------------------------------------------------------------

local MAX_SEEN = 400

local function trackSpell(spellID, spellName)
    if not spellID or not spellName then return end
    local filters = ns.db.filters
    local seen = filters.seenSpells
    if seen[spellID] then return end
    local n = filters.seenCount
    if not n then
        n = 0
        for _ in pairs(seen) do n = n + 1 end
    end
    if n >= MAX_SEEN then
        filters.seenCount = n
        return
    end
    seen[spellID] = spellName
    filters.seenCount = n + 1
end

function Events:ClearSeenSpells()
    wipe(ns.db.filters.seenSpells)
    ns.db.filters.seenCount = 0
end

--------------------------------------------------------------------------
-- Enemy ability alerts
--
-- Runs on SPELL_CAST_SUCCESS and SPELL_AURA_APPLIED from units that are
-- neither yours nor targeting you, so it has to sit ahead of the ownership
-- early-bail. The guards are ordered cheapest-first: a GUID comparison
-- rejects the overwhelming majority before any table lookup happens.
--
-- Matching is by NAME, resolved once at login from the curated ID list in
-- SpellData.lua, so every rank of a spell is covered by one entry.
--------------------------------------------------------------------------

local lastEnemyAlert = {}

local function CheckEnemyAlert(sGUID, sName, sFlags, spellID, spellName)
    if not spellName or not sGUID then return end

    -- Name lookup first: it rejects essentially all raid traffic with a
    -- single hash probe, which is cheaper than the flag tests.
    local entry = ns.enemyByName[spellName]
    if not entry then return end

    local f = ns.db.filters
    if f.enemyBlacklist[spellName] then return end
    if not f.enemyCategories[entry.category] then return end

    local scope = f.enemyScope
    local isFocus = (sGUID == ns.focusGUID)

    if scope == "targetfocus" then
        if not isFocus and sGUID ~= ns.targetGUID then return end
    elseif scope == "players" then
        if band(sFlags or 0, CONTROL_PLAYER) == 0 then return end
    end

    -- Hostile check applies to EVERY scope. Without it, focusing a teammate
    -- in arena reports their PvP trinket as the enemy's, and a healer whose
    -- target is friendly all the time gets a constant stream of nonsense.
    if band(sFlags or 0, REACTION_HOSTILE) == 0 then return end

    -- SPELL_CAST_SUCCESS and SPELL_AURA_APPLIED often both fire for the same
    -- ability. Collapse them.
    local key = sGUID .. "\001" .. spellName
    local now = GetTime()
    local last = lastEnemyAlert[key]
    if last and (now - last) < 1.0 then return end
    lastEnemyAlert[key] = now

    local text = spellName
    if f.enemyShowCaster then
        if isFocus then
            text = "|cff9d9d9dfocus|r " .. text
        elseif sName and scope ~= "targetfocus" then
            text = "|cff9d9d9d" .. tostring(sName) .. "|r " .. text
        end
    end

    Display(entry.category == "break" and "enemyBreak" or "enemy", nil, {
        text       = text,
        spellID    = spellID or entry.id,
        anchorGUID = sGUID,
    })
end

--------------------------------------------------------------------------
-- Reactive abilities
--
-- Derived from avoidance events rather than from Blizzard's SPELL_ACTIVE
-- message, which rides on the system JCT switches off. Only abilities you
-- actually know are watched - a Beast Mastery hunter has Mongoose Bite but
-- not Counterattack, which is a Survival talent.
--------------------------------------------------------------------------

-- THREE things can announce the same reactive: the combat-log derivation
-- below, the SPELL_UPDATE_USABLE edge detector, and Blizzard's own
-- COMBAT_TEXT_UPDATE "SPELL_ACTIVE" event. That last one keeps arriving even
-- with enableFloatingCombatText off - the CVar gates Blizzard's *display*
-- addon, not delivery of the event - so without a shared guard you get
-- "Mongoose Bite!" twice, once from each path.
--
-- Keyed by NAME rather than ID, because the three paths do not agree on
-- which rank's ID they carry and a name is the only thing they share.
--
-- The window has to sit between two bounds: longer than the gap between
-- the two announcements of one proc (tens of milliseconds), shorter than
-- the cooldown of the shortest reactive JCT watches (Overpower, Revenge,
-- Mongoose Bite and Counterattack are all 5s; Riposte is 6s). 3s.
local reactiveShown = {}
local REACTIVE_DEDUPE = 3.0

local function claimReactive(name)
    if not name then return false end
    local key = strlower(name)
    local now = GetTime()
    local last = reactiveShown[key]
    if last and (now - last) < REACTIVE_DEDUPE then return false end
    reactiveShown[key] = now
    return true
end

local function FireReactive(trigger)
    if not ns.db.filters.showReactives then return end
    local list = ns.activeReactives[trigger]
    if not list then return end
    for i = 1, #list do
        local r = list[i]
        -- Cooldown is checked BEFORE claiming, so an on-cooldown ability
        -- does not burn the dedupe slot that the real announcement needs.
        -- Every reactive here has a 5-6s cooldown, so without this you get
        -- told Counterattack is ready four seconds before it actually is.
        if not ns.compat.SpellOnCooldown(r.id) and claimReactive(r.name) then
            Display("reactive", nil, {
                text    = r.name .. "!",
                spellID = r.id,
            })
        end
    end
end

--------------------------------------------------------------------------
-- State swap collapsing
--
-- Swapping Hawk for Viper is ONE decision, but the combat log reports it as
-- two events. Announcing both means the useful half ("you are now on
-- Viper") arrives next to a red alarm ("you lost Hawk") that is not an
-- alarm at all - and after a few swaps you stop reading either.
--
-- So a fade within a category is held briefly. If a state from the same
-- category lands inside the window the fade is dropped, because the gain
-- already says everything. If nothing replaces it, the fade fires and you
-- get the alarm you actually wanted.
--
-- The hold has to survive both event orders: the log does not guarantee
-- REMOVED before APPLIED, so a gain is timestamped as well as queued
-- against, and a fade that arrives just after its replacement is dropped on
-- the spot rather than queued at all.
--------------------------------------------------------------------------

local STATE_SWAP_WINDOW = 0.4
local stateGain   = {}   -- [cat] = GetTime() of the last gain in that category
local pendingFade = {}   -- [cat] = { name, spellID, guid }

local function GainState(cat)
    if not cat then return end
    stateGain[cat] = GetTime()
    pendingFade[cat] = nil
end

local function ShowFade(name, spellID, guid)
    Display("state", nil, {
        text       = "-" .. tostring(name or "?"),
        spellID    = spellID,
        forceColor = ns.db.colors.stateFade,
        anchorGUID = guid,
    })
end

local function FadeState(cat, name, spellID, guid)
    -- No category, or collapsing turned off: nothing to wait for.
    if not cat or not ns.db.filters.collapseStateSwaps
       or not (C_Timer and C_Timer.After) then
        ShowFade(name, spellID, guid)
        return
    end

    local now = GetTime()
    local gained = stateGain[cat]
    if gained and (now - gained) < STATE_SWAP_WINDOW then
        -- The replacement already went past. This fade is the tail of a
        -- swap, not a loss.
        return
    end

    pendingFade[cat] = { name = name, spellID = spellID, guid = guid }
    C_Timer.After(STATE_SWAP_WINDOW, function()
        local p = pendingFade[cat]
        if not p then return end       -- a replacement landed and cleared it
        pendingFade[cat] = nil
        ShowFade(p.name, p.spellID, p.guid)
    end)
end

--------------------------------------------------------------------------
-- Conditional abilities (Execute, Hammer of Wrath, Victory Rush)
--
-- Nothing in the combat log announces these, so they are edge-detected off
-- SPELL_UPDATE_USABLE. Asking the client whether the spell is usable puts
-- the server in charge of the threshold, which avoids doing health maths
-- that would be wrong by up to 1% against enemy players (UnitHealth returns
-- a percentage, not a real value, for hostile players in Classic).
--------------------------------------------------------------------------

local usableState = {}

local function CheckUsable()
    local list = ns.activeUsable
    if not list or #list == 0 then return end
    if not ns.db or not ns.db.enabled then return end
    if not ns.db.filters.showReactives then return end

    for i = 1, #list do
        local a = list[i]
        local usable, noPower = ns.compat.IsSpellUsable(a.name)
        -- noPower means the condition is met and you are only short on rage,
        -- which is still worth knowing about.
        local ready = (usable or noPower) and true or false
        if ready ~= usableState[a.id] then
            usableState[a.id] = ready
            if ready and not ns.compat.SpellOnCooldown(a.id)
               and claimReactive(a.name) then
                Display("reactive", nil, { text = a.name .. "!", spellID = a.id })
            end
        end
    end
end

--------------------------------------------------------------------------
-- Combat log
--------------------------------------------------------------------------

local function HandleCLEU()
    local db = ns.db
    if not db or not db.enabled then return end

    local _, sub, _, sGUID, sName, sFlags, _, dGUID, dName, _, _,
          p1, p2, p3, p4, p5, p6, p7, p8, p9, p10 = CombatLogGetCurrentEventInfo()

    local playerGUID = ns.playerGUID
    if not playerGUID then return end

    local fromMe = (sGUID == playerGUID)
    local fromPet = false
    if not fromMe and sGUID then
        if sGUID == ns.petGUID or ns.myGuardians[sGUID] then
            fromPet = true
        elseif sFlags and band(sFlags, AFFILIATION_MINE) ~= 0 then
            fromPet = true
        end
    end
    local toMe = (dGUID == playerGUID)

    -- Enemy alerts have to be checked ahead of the ownership bail: an enemy
    -- popping a cooldown on themselves is neither yours nor aimed at you,
    -- and an enemy landing CC on you would otherwise be swallowed by the
    -- buffs-only guard on the aura branch further down.
    if db.filters.showEnemySpells and not fromMe and not fromPet
       and (sub == "SPELL_CAST_SUCCESS" or sub == "SPELL_AURA_APPLIED") then
        CheckEnemyAlert(sGUID, sName, sFlags, p1, p2)
    end

    -- Early bail: nothing else here concerns us.
    if not fromMe and not fromPet and not toMe then return end

    Events.stats.relevant = Events.stats.relevant + 1

    local f = db.filters
    if f.onlyInCombat and not ns.inCombat then return end
    local critsOwn = db.general.critsOwnStream

    ------------------------------------------------------------------
    -- Guardian tracking (totems, snakes, short-lived summons)
    ------------------------------------------------------------------
    if sub == "SPELL_SUMMON" then
        if fromMe and dGUID then ns.myGuardians[dGUID] = true end
        return
    end

    ------------------------------------------------------------------
    -- Damage
    ------------------------------------------------------------------
    if sub == "SWING_DAMAGE" or sub == "RANGE_DAMAGE" or sub == "SPELL_DAMAGE"
       or sub == "SPELL_PERIODIC_DAMAGE" or sub == "DAMAGE_SHIELD" then

        local spellID, spellName, amount, school, critical
        local isSwing = (sub == "SWING_DAMAGE")

        if isSwing then
            amount, school, critical = p1, p3, p7
        else
            spellID, spellName = p1, p2
            amount, school, critical = p4, p6, p10
            if school == nil then school = p3 end
        end

        if type(amount) ~= "number" or amount <= 0 then return end
        critical = critical and true or false

        -- A PARTIAL block arrives here as damage with a non-zero blocked
        -- field, not as SWING_MISSED. In TBC that is the normal case, so a
        -- warrior's Revenge would almost never light up if we only watched
        -- the miss branch.
        if toMe and not fromMe then
            local blocked = isSwing and p5 or p8
            if type(blocked) == "number" and blocked > 0 then
                FireReactive("selfAvoid")
            end
        end

        local isPeriodic = (sub == "SPELL_PERIODIC_DAMAGE")
        local isAutoShot = (sub == "RANGE_DAMAGE" and spellID == SPELLID_AUTO_SHOT)

        if spellID and f.blacklist[spellID] then return end

        local class

        if fromMe then
            if isSwing and not f.showAutoAttack then return end
            if isAutoShot and not f.showAutoShot then return end
            if isPeriodic and not f.showDots then return end

            if isPeriodic then
                class = "outDot"
            elseif isSwing then
                class = "outMelee"
            elseif isAutoShot then
                class = "outAutoShot"
            else
                class = "outDamage"
            end
            if critical and critsOwn then class = "outCrit" end

        elseif fromPet then
            if isSwing and not f.showPetMelee then return end
            if not isSwing and not f.showPetSpells then return end
            if critical and not f.showPetCrits then critical = false end
            class = (critical and critsOwn) and "petCrit" or "petDamage"

        elseif toMe then
            if not f.showIncoming then return end
            class = (critical and critsOwn) and "inCrit" or "inDamage"
        else
            return
        end

        trackSpell(spellID, spellName)

        Push(class, amount, {
            crit      = critical,
            spellID   = spellID,
            spellName = spellName,
            canonID   = canonicalID(spellID, spellName) or (isSwing and "melee") or "other",
            school    = school,
            destKey   = (class == "inDamage" or class == "inCrit") and sGUID or nil,
            -- What this message is "about": the thing you hit, or the thing
            -- that hit you. Only used by nameplate-anchored frames.
            anchorGUID = (fromMe or fromPet) and dGUID or sGUID,
        })
        return
    end

    ------------------------------------------------------------------
    -- Misses / avoidance
    ------------------------------------------------------------------
    if sub == "SWING_MISSED" or sub == "RANGE_MISSED" or sub == "SPELL_MISSED"
       or sub == "SPELL_PERIODIC_MISSED" then

        local spellID, spellName, missType, amountMissed
        local isSwing = (sub == "SWING_MISSED")
        if isSwing then
            missType, amountMissed = p1, p3
        else
            spellID, spellName = p1, p2
            missType, amountMissed = p4, p6
        end

        local isAutoShot = (sub == "RANGE_MISSED" and spellID == SPELLID_AUTO_SHOT)

        -- Reactive abilities light up off avoidance, and do so independently
        -- of whether you display miss text at all.
        if toMe and not fromMe then
            if missType == "PARRY" then
                FireReactive("selfParry")
                FireReactive("selfAvoid")
            elseif missType == "DODGE" then
                FireReactive("selfDodge")
                FireReactive("selfAvoid")
            elseif missType == "BLOCK" then
                FireReactive("selfAvoid")
            end
        elseif fromMe and missType == "DODGE" then
            FireReactive("targetDodge")
        end

        local label = MISS_LABEL[missType] or missType
        if not label then return end
        if type(amountMissed) == "number" and amountMissed > 0 then
            label = label .. " (" .. ns.Format.Number(amountMissed) .. ")"
        end

        if spellID and f.blacklist[spellID] then return end

        local class
        if fromMe then
            if not f.showMisses then return end
            -- If you turned off melee or Auto Shot damage, you do not want
            -- their misses either.
            if isSwing and not f.showAutoAttack then return end
            if isAutoShot and not f.showAutoShot then return end
            class = "outMiss"
        elseif fromPet then
            if not f.showPetMisses then return end
            class = "petMiss"
        elseif toMe then
            if not f.showIncomingMisses then return end
            class = "inMiss"
        else
            return
        end

        trackSpell(spellID, spellName)

        Push(class, nil, {
            text       = label,
            spellID    = spellID,
            spellName  = spellName,
            anchorGUID = (fromMe or fromPet) and dGUID or sGUID,
        })
        return
    end

    ------------------------------------------------------------------
    -- Healing
    ------------------------------------------------------------------
    if sub == "SPELL_HEAL" or sub == "SPELL_PERIODIC_HEAL" then
        local spellID, spellName = p1, p2
        local amount, overhealing, critical = p4, p5, p7
        if type(amount) ~= "number" then return end
        overhealing = (type(overhealing) == "number") and overhealing or 0
        critical = critical and true or false

        local effective = amount - overhealing
        if effective < 0 then effective = 0 end
        if effective == 0 and not f.showOverheal then return end
        if spellID and f.blacklist[spellID] then return end

        local isPeriodic = (sub == "SPELL_PERIODIC_HEAL")

        local class
        if fromMe then
            if isPeriodic and not f.showHots then return end
            class = (critical and critsOwn) and "outHealCrit" or "outHeal"
        elseif fromPet then
            class = "petHeal"
        elseif toMe then
            if not f.showIncomingHeals then return end
            class = "inHeal"
        else
            return
        end

        trackSpell(spellID, spellName)

        local suffix
        if f.showOverheal and overhealing > 0 then
            suffix = "|cff9d9d9d(" .. ns.Format.Number(overhealing) .. ")|r"
        end

        Push(class, effective, {
            crit       = critical,
            spellID    = spellID,
            spellName  = spellName,
            canonID    = canonicalID(spellID, spellName),
            suffix     = suffix,
            -- Heals anchor to whoever was healed, in both directions: a heal
            -- you receive belongs over you, not over the healer.
            anchorGUID = dGUID,
        })
        return
    end

    ------------------------------------------------------------------
    -- Power gains
    ------------------------------------------------------------------
    if sub == "SPELL_ENERGIZE" or sub == "SPELL_PERIODIC_ENERGIZE" then
        if not toMe then return end
        if not f.showPower then return end
        local spellID, spellName = p1, p2
        local amount = p4
        -- overEnergize was added to this payload after TBC's original
        -- layout, so the power type is at p6 on newer builds and p5 on
        -- older ones. Probe rather than assume.
        local powerType = p6
        if type(powerType) ~= "number" then powerType = p5 end
        if type(amount) ~= "number" or amount == 0 then return end

        Push("power", amount, {
            spellID   = spellID,
            spellName = spellName,
            canonID   = canonicalID(spellID, spellName),
            suffix    = ns.Format.POWER_NAMES[powerType],
            anchorGUID = dGUID,
        })
        return
    end

    ------------------------------------------------------------------
    -- Stances, aspects, forms, auras, seals, armours
    --
    -- Checked ahead of the generic buff branches, and NOT gated on being in
    -- combat: these are states you chose, and you choose most of them
    -- between pulls. See the STATE_AURAS comment in SpellData.lua.
    ------------------------------------------------------------------
    if toMe and f.showStates
       and (sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REMOVED")
       and p4 == "BUFF" then
        local spellName = p2
        local st = spellName and ns.stateByName[strlower(spellName)]
        if st then
            local spellID = p1
            if spellID and f.blacklist[spellID] then return end
            if sub == "SPELL_AURA_APPLIED" then
                GainState(st.cat)
                Display("state", nil, {
                    text       = spellName,
                    spellID    = spellID,
                    anchorGUID = dGUID,
                })
            else
                FadeState(st.cat, spellName, spellID, dGUID)
            end
            return
        end
    end

    ------------------------------------------------------------------
    -- Buff gains (procs)
    --
    -- Only while in combat, only buffs landing on you. Out of combat this
    -- would be nothing but raid buff spam.
    ------------------------------------------------------------------
    if sub == "SPELL_AURA_APPLIED" then
        if not f.showProcs then return end
        if not toMe or not ns.inCombat then return end
        if p4 ~= "BUFF" then return end
        local spellID, spellName = p1, p2
        if spellID and f.blacklist[spellID] then return end
        trackSpell(spellID, spellName)
        Display("notify", nil, {
            text       = tostring(spellName or "?"),
            spellID    = spellID,
            anchorGUID = dGUID,
        })
        return
    end

    if sub == "SPELL_AURA_REMOVED" then
        if not f.showAuraFades then return end
        if not toMe or not ns.inCombat then return end
        if p4 ~= "BUFF" then return end
        local spellID, spellName = p1, p2
        if spellID and f.blacklist[spellID] then return end
        Display("notify", nil, {
            text       = "-" .. tostring(spellName or "?"),
            spellID    = spellID,
            forceColor = ns.db.colors.outMiss,
            anchorGUID = dGUID,
        })
        return
    end

    ------------------------------------------------------------------
    -- Other notifications
    ------------------------------------------------------------------
    if sub == "SPELL_INTERRUPT" then
        if not fromMe and not fromPet then return end
        if not f.showInterrupts then return end
        Display("notify", nil, {
            text       = "Interrupted: " .. tostring(p5 or "?"),
            spellID    = p1,
            forceColor = ns.db.colors.interrupt,
            anchorGUID = dGUID,
        })
        return
    end

    if sub == "SPELL_DISPEL" or sub == "SPELL_STOLEN" then
        if not fromMe and not fromPet then return end
        if not f.showDispels then return end
        local verb = (sub == "SPELL_STOLEN") and "Stolen: " or "Dispelled: "
        Display("notify", nil, {
            text       = verb .. tostring(p5 or "?"),
            spellID    = p1,
            forceColor = ns.db.colors.dispel,
            anchorGUID = dGUID,
        })
        return
    end

    if sub == "PARTY_KILL" then
        if not fromMe then return end
        if not f.showKillingBlow then return end
        Display("notify", nil, {
            text       = "Killing Blow: " .. tostring(dName or "?"),
            forceColor = ns.db.colors.killingBlow,
            anchorGUID = dGUID,
        })
        return
    end

    if sub == "ENVIRONMENTAL_DAMAGE" then
        if not toMe then return end
        if not f.showEnvironmental then return end
        local envType, amount = p1, p2
        if type(amount) ~= "number" or amount <= 0 then return end
        Push("inDamage", amount, {
            spellName = ENV_LABEL[envType] or envType,
            canonID   = "env:" .. tostring(envType),
        })
        return
    end
end

--------------------------------------------------------------------------
-- COMBAT_TEXT_UPDATE
--
-- Used only for the handful of things the combat log cannot give us, so
-- nothing is ever shown twice. Note that this event is driven by the same
-- system the "take over Blizzard's combat text" option switches off, so on
-- some builds it will simply never fire. Nothing breaks if it does not.
--------------------------------------------------------------------------

local function HandleCombatText(messageType, a2, a3)
    local db = ns.db
    if not db or not db.enabled then return end

    local v1, v2 = a2, a3
    local getInfo = ns.compat.GetCombatTextInfo
    if getInfo then
        local ok, r1, r2 = pcall(getInfo)
        if ok and r1 ~= nil then v1, v2 = r1, r2 end
    end
    if v1 == nil then return end

    if messageType == "SPELL_ACTIVE" then
        local name = tostring(v1)
        -- If this is an ability JCT already watches, it belongs in the
        -- reactive stream (its own colour, its own icon, its own routing),
        -- not the generic notify stream - and the shared guard decides
        -- whether this announcement or the combat-log one got here first.
        -- Matched against every reactive whose name resolves, not just the
        -- ones knowsSpell confirmed: the server saying the ability just lit
        -- up is better evidence that you have it than our spellbook probe.
        local watched = ns.reactiveByName and ns.reactiveByName[strlower(name)]
        if watched then
            if not db.filters.showReactives then return end
            if claimReactive(name) then
                Display("reactive", nil, { text = name .. "!", spellID = watched })
            end
            return
        end
        Display("notify", nil, {
            text       = name .. "!",
            forceColor = db.colors.notify,
        })
    elseif messageType == "HONOR_GAINED" then
        Display("notify", nil, { text = "+" .. tostring(v1) .. " Honor" })
    elseif messageType == "FACTION" then
        local delta = tonumber(v2) or 0
        local sign = delta >= 0 and "+" or ""
        Display("notify", nil, { text = sign .. tostring(delta) .. " " .. tostring(v1) })
    elseif messageType == "EXTRA_ATTACKS" then
        Display("notify", nil, { text = "Extra Attacks " .. tostring(v1) })
    end
end

--------------------------------------------------------------------------
-- Low health warning
--------------------------------------------------------------------------

local lowHealth = false

local function CheckHealth()
    if not ns.db or not ns.db.filters.showLowHealth then return end
    if ns.db.filters.onlyInCombat and not ns.inCombat then return end
    local cur, max = UnitHealth("player"), UnitHealthMax("player")
    if not max or max == 0 then return end
    local ratio = cur / max
    if ratio <= 0.2 and not lowHealth then
        lowHealth = true
        Display("notify", nil, {
            text       = "LOW HEALTH",
            forceColor = ns.db.colors.lowHealth,
            anchorGUID = ns.playerGUID,
        })
    elseif ratio > 0.25 then
        lowHealth = false
    end
end

--------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------

local ef = CreateFrame("Frame", "JCT_CombatEvents")
Events.frame = ef

ef:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        HandleCLEU()
    elseif event == "COMBAT_TEXT_UPDATE" then
        HandleCombatText(arg1, arg2, arg3)
    elseif event == "UNIT_HEALTH" then
        CheckHealth()
    elseif event == "SPELL_UPDATE_USABLE" then
        CheckUsable()
    elseif event == "PLAYER_TARGET_CHANGED" then
        wipe(usableState)
        CheckUsable()
    end
end)

function Events:Enable()
    local ok = pcall(ef.RegisterEvent, ef, "COMBAT_LOG_EVENT_UNFILTERED")
    if not ok then
        ns.Print("|cffff5555this client refused COMBAT_LOG_EVENT_UNFILTERED|r - damage numbers will not work.")
    end
    pcall(ef.RegisterEvent, ef, "COMBAT_TEXT_UPDATE")
    if ef.RegisterUnitEvent then
        pcall(ef.RegisterUnitEvent, ef, "UNIT_HEALTH", "player")
    else
        pcall(ef.RegisterEvent, ef, "UNIT_HEALTH")
    end
    -- Registered unconditionally rather than only when this character has a
    -- conditional ability, so a respec or a newly trained rank cannot leave
    -- the event unhooked. CheckUsable returns on its first line when the
    -- list is empty, which is the case for most classes.
    pcall(ef.RegisterEvent, ef, "SPELL_UPDATE_USABLE")
    pcall(ef.RegisterEvent, ef, "PLAYER_TARGET_CHANGED")
    self.enabled = true
end

function Events:Disable()
    ef:UnregisterAllEvents()
    self.enabled = false
    self:FlushAll()
end

function Events:OnCombatState(entering)
    if not ns.db then return end
    if entering then
        lowHealth = false
    else
        self:FlushAll()
        wipe(lastEnemyAlert)
        wipe(reactiveShown)
    end
    if ns.db.filters.showCombatState then
        Display("notify", nil, {
            text = entering and "+ Combat" or "- Combat",
        })
    end
end
