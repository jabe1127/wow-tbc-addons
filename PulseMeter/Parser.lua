-- PulseMeter Parser.lua
-- Combat log parsing for the TBC 2.5.x client.
-- Tracks: damage done/taken, healing + overheal, absorbs (reconstructed - TBC has
-- no SPELL_ABSORBED event), deaths with a death-recap log, interrupts, dispels,
-- spell steals, CC breaks, and friendly fire.

local ADDON, ns = ...
local PM = ns.PM

-- Hot-path locals. In Lua 5.1 every global read is a hash lookup in the
-- function environment; in a parser that runs hundreds of times a second
-- those add up, and localising costs nothing.
local band = bit.band
local GetTime = GetTime
local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local tonumber, select, ipairs, pairs = tonumber, select, ipairs, pairs
local tinsert, tremove = table.insert, table.remove
-- literal fallbacks: if any constant is missing in this client build, the
-- file must still load (values unchanged since 2.4)
local GROUP_MASK = bit.bor(
	COMBATLOG_OBJECT_AFFILIATION_MINE or 0x00000001,
	COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x00000002,
	COMBATLOG_OBJECT_AFFILIATION_RAID or 0x00000004
)
local PET_MASK = bit.bor(COMBATLOG_OBJECT_TYPE_PET or 0x00001000,
	COMBATLOG_OBJECT_TYPE_GUARDIAN or 0x00002000)
local HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x00000040
local FRIENDLY = COMBATLOG_OBJECT_REACTION_FRIENDLY or 0x00000010

--------------------------------------------------------------------------
-- Actor management
--------------------------------------------------------------------------
local function getActor(seg, guid, name, flags)
	local a = seg.actors[guid]
	if not a then
		if not name then
			local info = PM.roster[guid]
			name = info and info.name
		end
		a = {
			guid = guid, name = name or "Unknown", flags = flags,
			class = nil, isPet = false, owner = nil,
			damage = 0, damageTaken = 0, friendlyFire = 0,
			healing = 0, overhealing = 0, absorbs = 0, healingTaken = 0,
			absorbedTaken = 0,
			interrupts = 0, dispels = 0, steals = 0, ccBreaks = 0, deaths = 0,
			dmgSpells = {}, healSpells = {}, takenSpells = {},
			intSpells = {}, dispelSpells = {}, ccSpells = {},
			targets = {},
			deathLog = nil, deathEvents = nil,
		}
		local info = PM.roster[guid]
		if info then a.class = info.class end
		if flags and band(flags, PET_MASK) > 0 then
			a.isPet = true
			a.owner = PM:ResolveOwner(guid)
		end
		seg.actors[guid] = a
	end
	return a
end

-- resolve pets to owners when merge is on; returns the actor credit goes to
local function creditActor(seg, guid, name, flags, mergePets)
	if mergePets == nil then mergePets = PM.db.general.mergePets end
	if mergePets and PM.petOwners[guid] then
		local ownerGUID = PM:ResolveOwner(guid)
		if ownerGUID and ownerGUID ~= guid then
			local owner = PM.roster[ownerGUID]
			local a = getActor(seg, ownerGUID, owner and owner.name or "Unknown", nil)
			return a, true, name
		end
	end
	-- A summoned thing we never saw summoned - joined mid-fight, or something
	-- we don't know about. Note it for /pm debug and let it keep its own row
	-- so the damage still shows up somewhere instead of vanishing.
	if mergePets and flags and name and band(flags, PET_MASK) > 0 then
		PM.unattributed[name] = (PM.unattributed[name] or 0) + 1
	end
	return getActor(seg, guid, name, flags), false, nil
end

local function bumpSpell(tbl, key, icon, amount, crit)
	local s = tbl[key]
	if not s then
		s = { amount = 0, hits = 0, crits = 0, max = 0, icon = icon }
		tbl[key] = s
	end
	s.amount = s.amount + amount
	s.hits = s.hits + 1
	if crit then s.crits = s.crits + 1 end
	if amount > s.max then s.max = amount end
end

--------------------------------------------------------------------------
-- Death log (ring buffer per group member)
--------------------------------------------------------------------------
-- A true ring buffer over PRE-ALLOCATED entry tables.
--
-- The old version allocated a fresh table per incoming hit and then used
-- table.remove(log, 1) to trim, which is an O(n) shift on every event. It
-- also pre-built the display string ("Shadow Bolt (Gruul)") for every hit,
-- even though the string is only ever read if that player actually dies.
-- Both are now deferred: entries are overwritten in place, and the string is
-- built once, on death.
local function logDeathEvent(destGUID, spellName, srcName, amount, isHeal)
	local seg = PM.current
	if not seg then return end
	local a = seg.actors[destGUID]
	if not a then return end
	local log = a.deathLog
	if not log then
		log = { head = 0, count = 0 }
		a.deathLog = log
	end
	local maxN = PM.db.general.deathLogSize
	if log.max and log.max ~= maxN then
		log.head, log.count = 0, 0        -- resizing invalidates the ring
	end
	local idx = log.head % maxN + 1
	log.head = idx
	if log.count < maxN then log.count = log.count + 1 end
	local e = log[idx]
	if not e then e = {}; log[idx] = e end
	e.t = GetTime()
	e.spell = spellName
	e.src = srcName
	e.amount = amount
	e.heal = isHeal
	local unit = PM.guidToUnit[destGUID]
	if unit then
		e.hp, e.hpMax = UnitHealth(unit), UnitHealthMax(unit)
	else
		e.hp, e.hpMax = 0, 0
	end
	log.max = maxN
end

-- Flatten the ring into oldest-to-newest order. Only runs on an actual death,
-- so allocating here is fine.
local function snapshotDeathLog(log)
	local out = {}
	if not log or log.count == 0 then return out end
	local maxN = log.max or log.count
	local start = (log.head - log.count) % maxN + 1
	for i = 0, log.count - 1 do
		local e = log[(start + i - 1) % maxN + 1]
		if e then
			out[#out + 1] = {
				t = e.t, amount = e.amount, heal = e.heal, hp = e.hp, hpMax = e.hpMax,
				text = (e.spell or "Melee") .. " (" .. (e.src or "?") .. ")",
			}
		end
	end
	return out
end

--------------------------------------------------------------------------
-- Simple shield-absorb attribution (TBC has no SPELL_ABSORBED event).
-- We remember the most recent absorb-shield cast on each target and credit
-- that caster when the target absorbs damage.
--------------------------------------------------------------------------
local ABSORB_SPELLS = {
	-- Power Word: Shield ranks
	[17] = true, [592] = true, [600] = true, [3747] = true, [6065] = true, [6066] = true,
	[10898] = true, [10899] = true, [10900] = true, [10901] = true, [25217] = true, [25218] = true,
	-- Ice Barrier
	[11426] = true, [13031] = true, [13032] = true, [13033] = true, [27134] = true, [33405] = true,
	-- Mana Shield
	[1463] = true, [8494] = true, [8495] = true, [10191] = true, [10192] = true, [10193] = true,
	[27131] = true,
	-- Frost Ward / Fire Ward / Shadow Ward (partial absorbs)
	[6143] = true, [8461] = true, [8462] = true, [10177] = true, [28609] = true, [32796] = true,
	[543] = true, [8457] = true, [8458] = true, [10223] = true, [10225] = true, [27128] = true,
	[6229] = true, [11739] = true, [11740] = true, [28610] = true,
}
local shieldOn = {}   -- [destGUID] = casterGUID

-- Every event is applied to exactly two segments (this fight, and overall).
-- Building `{ cur, self.overall }` per event was the single largest source of
-- garbage in the parser, so the same two-slot table is reused forever.
local segBuf = { false, false }

--------------------------------------------------------------------------
-- Main parser
--------------------------------------------------------------------------
local damageEvents = {
	SWING_DAMAGE = "swing", RANGE_DAMAGE = "spell", SPELL_DAMAGE = "spell",
	SPELL_PERIODIC_DAMAGE = "spell", DAMAGE_SHIELD = "spell", DAMAGE_SPLIT = "spell",
	ENVIRONMENTAL_DAMAGE = "env",
	SPELL_EXTRA_ATTACKS = false,
}
-- Deliberately absent: SWING_DAMAGE_LANDED (a duplicate of SWING_DAMAGE on
-- modern clients) and SPELL_ABSORBED (partial absorbs come from the damage
-- event's own absorbed field, full ones from SPELL_MISSED). Adding either
-- would double-count.

local ENV_NAMES = {
	FALLING = "Falling", DROWNING = "Drowning", FATIGUE = "Fatigue",
	FIRE = "Fire", LAVA = "Lava", SLIME = "Slime",
}

-- Anything summoned rather than possessed: these never appear as a unit token,
-- so SPELL_SUMMON is the only way to learn who owns them.
local summonEvents = {
	SPELL_SUMMON = true, SPELL_CREATE = true,
}
local missEvents = {
	SWING_MISSED = "swing", RANGE_MISSED = "spell", SPELL_MISSED = "spell",
	SPELL_PERIODIC_MISSED = "spell", DAMAGE_SHIELD_MISSED = "spell",
}
local healEvents = { SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true }

function PM:ParseCLEU(timestamp, subevent, hideCaster,
		srcGUID, srcName, srcFlags, srcRaidFlags,
		dstGUID, dstName, dstFlags, dstRaidFlags, ...)

	local stats = PM.stats
	stats.events = stats.events + 1
	local g = self.db.general
	local srcGroup = srcGUID and (self:IsGroupGUID(srcGUID) or (srcFlags and band(srcFlags, GROUP_MASK) > 0))
	local dstGroup = dstGUID and (self:IsGroupGUID(dstGUID) or (dstFlags and band(dstFlags, GROUP_MASK) > 0))

	-- The boss is never "in our group", so its death has to be checked before
	-- the group filter or the fight would run on until the grace timer.
	if self.current and dstName and self.current.enemy == dstName
		and ns.BOSSES[dstName]
		and (subevent == "UNIT_DIED" or subevent == "PARTY_KILL") then
		-- Only an actual boss ends the pull early. A trash mob dying means
		-- the next one is already on you; the group-combat check decides.
		self.current.bossDiedAt = GetTime()
	end

	-- Totems, treants, elementals and guardians are summoned, not possessed,
	-- so this is where we learn who they belong to. It has to run before the
	-- group filter and before a fight exists, because totems go down during
	-- the pull countdown.
	if summonEvents[subevent] and srcGUID and dstGUID then
		self.petOwners[dstGUID] = srcGUID
		if self.unattributed[dstName or ""] then self.unattributed[dstName] = nil end
	end

	if g.onlyGroup and not srcGroup and not dstGroup then return end

	-- Start a fight lazily. Damage always counts. Healing only counts while
	-- somebody is actually in combat, otherwise out-of-combat top-ups between
	-- pulls each open and discard a throwaway segment.
	if not self.current and (srcGroup or dstGroup) then
		local dt = damageEvents[subevent]
		if dt and dt ~= "env" then      -- a fall on the way to the raid isn't a fight
			self:StartCombat()
		elseif healEvents[subevent] and (self.inCombat or self:GroupInCombat()) then
			self:StartCombat()
		end
	end
	local cur = self.current
	if not cur then
		-- still allow shield bookkeeping outside combat
		if subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" then
			local spellId = ...
			if ABSORB_SPELLS[spellId] then shieldOn[dstGUID] = srcGUID end
		elseif subevent == "SPELL_AURA_REMOVED" then
			local spellId = ...
			if ABSORB_SPELLS[spellId] then shieldOn[dstGUID] = nil end
		end
		return
	end

	self:NoteActivity()
	segBuf[1] = cur
	segBuf[2] = self.overall
	local segs = segBuf

	------------------------------------------------------------------
	-- DAMAGE
	------------------------------------------------------------------
	local dtype = damageEvents[subevent]
	if dtype then
		-- Each select(n, ...) walks the vararg again, so pull everything out in
		-- a single destructuring assignment instead of three passes.
		local spellId, spellName, amount, overkill, critical, absorbed
		if dtype == "swing" then
			local a1, a2, _s, _r, _b, a6, a7 = ...
			amount, overkill, absorbed, critical = a1, a2, a6, a7
			spellName = "Melee"
			spellId = 6603
		elseif dtype == "env" then
			-- environmentalType, amount, overkill, school, resisted, blocked,
			-- absorbed, critical
			local e1, e2, e3, _s, _r, _b, e7, e8 = ...
			amount, overkill, absorbed, critical = e2, e3, e7, e8
			spellName = ENV_NAMES[e1] or e1 or "Environment"
			spellId = nil
		else
			local s1, s2, _s3, a4, a5, _s6, _r, _b, a9, a10 = ...
			spellId, spellName = s1, s2
			amount, overkill, absorbed, critical = a4, a5, a9, a10
		end
		absorbed = tonumber(absorbed) or 0
		if absorbed > 0 and dstGroup then
			-- real absorbed amount from the log beats guessing from shield auras
			local caster = shieldOn[dstGUID]
			for si = 1, 2 do local seg = segs[si]
				if caster and self:IsGroupGUID(caster) then
					local a = creditActor(seg, caster, nil, nil)
					a.absorbs = a.absorbs + absorbed
				end
				local v = getActor(seg, dstGUID, dstName, dstFlags)
				v.absorbedTaken = (v.absorbedTaken or 0) + absorbed
			end
		end
		amount = amount or 0
		if amount <= 0 then return end
		stats.damage = stats.damage + 1
		cur.hasData = true

		-- fight naming: a real boss always wins over whatever trash we hit first
		if dstName and dstFlags and band(dstFlags, HOSTILE) > 0 then
			if not cur.enemy or (ns.BOSSES[dstName] and not ns.BOSSES[cur.enemy]) then
				cur.enemy = dstName
			end
			-- Track how many distinct mobs this pull covered so a multi-mob
			-- trash pack doesn't look like it is stuck on the first mob's name.
			local seen = cur.enemies
			if not seen then seen = {}; cur.enemies = seen end
			if not seen[dstName] then
				seen[dstName] = true
				cur.enemyCount = (cur.enemyCount or 0) + 1
			end
		end
		if not cur.enemy and srcFlags and band(srcFlags, HOSTILE) > 0 and srcName then
			cur.enemy = srcName
		end

		for si = 1, 2 do local seg = segs[si]
			-- attacker side
			if srcGroup then
				local a, merged, petName = creditActor(seg, srcGUID, srcName, srcFlags, g.mergePets)
				local ff = dstGroup and band(dstFlags or 0, FRIENDLY) > 0
				if ff then
					a.friendlyFire = a.friendlyFire + amount
				else
					a.damage = a.damage + amount
					local key = merged and petName and (spellName .. " (" .. petName .. ")") or spellName
					bumpSpell(a.dmgSpells, key, spellId, amount, critical)
					if g.trackTargets then
						local key = dstName or "?"
						a.targets[key] = (a.targets[key] or 0) + amount
					end
				end
			end
			-- victim side
			if dstGroup then
				local v = creditActor(seg, dstGUID, dstName, dstFlags, g.mergePets)
				v.damageTaken = v.damageTaken + amount
				bumpSpell(v.takenSpells, spellName or "?", spellId, amount, critical)
			end
		end
		if dstGroup then
			logDeathEvent(dstGUID, spellName, srcName, amount, false)
		end
		return
	end

	------------------------------------------------------------------
	-- MISSES (absorb reconstruction lives here)
	------------------------------------------------------------------
	local mtype = missEvents[subevent]
	if mtype then
		local missType, amountMissed, spellName
		if mtype == "swing" then
			local m1, _oh, m3 = ...
			missType, amountMissed = m1, m3
			spellName = "Melee"
		else
			local _s1, s2, _s3, m4, _oh, m6 = ...
			spellName, missType, amountMissed = s2, m4, m6
		end
		if missType == "ABSORB" and dstGroup then
			amountMissed = tonumber(amountMissed) or 0
			if amountMissed > 0 then
				local caster = shieldOn[dstGUID]
				if caster and self:IsGroupGUID(caster) then
					for si = 1, 2 do local seg = segs[si]
						local a = creditActor(seg, caster, nil, nil)
						a.absorbs = a.absorbs + amountMissed
					end
				end
				logDeathEvent(dstGUID, "Absorbed " .. (spellName or "hit"), nil, amountMissed, true)
			end
		end
		return
	end

	------------------------------------------------------------------
	-- HEALING
	------------------------------------------------------------------
	if healEvents[subevent] then
		local spellId, spellName, _, amount, overheal, absorbed, critical = ...
		amount = amount or 0
		overheal = overheal or 0
		cur.hasData = true
		local effective = amount - overheal
		for si = 1, 2 do local seg = segs[si]
			if srcGroup then
				local a = creditActor(seg, srcGUID, srcName, srcFlags)
				a.healing = a.healing + effective
				a.overhealing = a.overhealing + overheal
				bumpSpell(a.healSpells, spellName or "?", spellId, effective, critical)
			end
			if dstGroup then
				local v = getActor(seg, dstGUID, dstName, dstFlags)
				v.healingTaken = v.healingTaken + effective
			end
		end
		if dstGroup and effective > 0 then
			logDeathEvent(dstGUID, spellName or "Heal", srcName, effective, true)
		end
		return
	end

	------------------------------------------------------------------
	-- INTERRUPTS
	------------------------------------------------------------------
	if subevent == "SPELL_INTERRUPT" then
		if srcGroup then
			local _, _, _, exId, exName = ...
			for si = 1, 2 do local seg = segs[si]
				local a = creditActor(seg, srcGUID, srcName, srcFlags)
				a.interrupts = a.interrupts + 1
				bumpSpell(a.intSpells, exName or "?", exId, 0, false)
			end
			table.insert(cur.intLog, {
				t = GetTime() - cur.startTime,
				src = srcName or "?", dst = dstName or "?", spell = exName or "?",
			})
			if #cur.intLog > 200 then table.remove(cur.intLog, 1) end
		end
		return
	end

	------------------------------------------------------------------
	-- DISPELS / STEALS
	------------------------------------------------------------------
	if subevent == "SPELL_DISPEL" or subevent == "SPELL_STOLEN" then
		if srcGroup then
			local _, _, _, exId, exName = ...
			for si = 1, 2 do local seg = segs[si]
				local a = creditActor(seg, srcGUID, srcName, srcFlags)
				if subevent == "SPELL_STOLEN" then a.steals = a.steals + 1
				else a.dispels = a.dispels + 1 end
				bumpSpell(a.dispelSpells, exName or "?", exId, 0, false)
			end
			table.insert(cur.dispelLog, {
				t = GetTime() - cur.startTime,
				src = srcName or "?", dst = dstName or "?", aura = exName or "?",
			})
			if #cur.dispelLog > 200 then table.remove(cur.dispelLog, 1) end
		end
		return
	end

	------------------------------------------------------------------
	-- CC BREAKS
	------------------------------------------------------------------
	if subevent == "SPELL_AURA_BROKEN" or subevent == "SPELL_AURA_BROKEN_SPELL" then
		if srcGroup then
			local spellId, spellName = ...
			for si = 1, 2 do local seg = segs[si]
				local a = creditActor(seg, srcGUID, srcName, srcFlags)
				a.ccBreaks = a.ccBreaks + 1
				bumpSpell(a.ccSpells, spellName or "?", spellId, 0, false)
			end
		end
		return
	end

	------------------------------------------------------------------
	-- AURAS (shield bookkeeping)
	------------------------------------------------------------------
	if subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" then
		local spellId = ...
		if ABSORB_SPELLS[spellId] then shieldOn[dstGUID] = srcGUID end
		return
	end
	if subevent == "SPELL_AURA_REMOVED" then
		local spellId = ...
		if ABSORB_SPELLS[spellId] then shieldOn[dstGUID] = nil end
		return
	end

	------------------------------------------------------------------
	-- DEATHS
	------------------------------------------------------------------
	if subevent == "UNIT_DIED" or subevent == "UNIT_DESTROYED" then
		if dstGroup and not (dstFlags and band(dstFlags, PET_MASK) > 0) then
			for si = 1, 2 do local seg = segs[si]
				local v = getActor(seg, dstGUID, dstName, dstFlags)
				v.deaths = v.deaths + 1
			end
			-- snapshot the death log for the recap tooltip
			local a = cur.actors[dstGUID]
			if a and a.deathLog then
				a.deathEvents = a.deathEvents or {}
				tinsert(a.deathEvents, { time = GetTime(), log = snapshotDeathLog(a.deathLog) })
				a.deathLog.head, a.deathLog.count = 0, 0
			end
		end
		return
	end
end
