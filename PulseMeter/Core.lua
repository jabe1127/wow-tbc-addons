-- PulseMeter Core.lua
-- Namespace, saved variables & profiles, combat segments, group/pet tracking.

local ADDON, ns = ...
local PM = CreateFrame("Frame", "PulseMeterFrame", UIParent)
ns.PM = PM
_G.PulseMeter = PM

PM.version = "1.0.0"
PM.windows = {}          -- live window objects
PM.callbacks = {}        -- external callback registry (see API.lua)

--------------------------------------------------------------------------
-- Defaults
--------------------------------------------------------------------------
local WINDOW_DEFAULTS = {
	point = "RIGHT", x = -40, y = 0,
	width = 260, height = 200,
	mode = "damage",
	segment = "current",          -- "current" | "overall" | index into history
	locked = false,
	barHeight = 18, barSpacing = 1,
	texture = "gradient",
	font = "Friz Quadrata", fontSize = 11, fontOutline = "OUTLINE",
	classColors = true,
	barColor = { 0.25, 0.60, 0.95, 1 },
	bgColor = { 0, 0, 0, 0.45 },
	titleColor = { 0.10, 0.10, 0.12, 0.90 },
	showTitle = true, showRank = true, showValue = true, showPercent = true, showPerSecond = true,
	showSpark = true, showIcons = true,
	scale = 1, alpha = 1, strata = "LOW",
	growUp = false,
	combatAlpha = 1, oocAlpha = 1,      -- per-state opacity
	quickModes = { "damage", "healing", "damageTaken", "deaths" }, -- middle-click cycle
	clickThrough = false,
	titleHeight = 26,
	toolbarOpen = false,
	isMini = false,
}

local DEFAULTS = {
	general = {
		externalFeed = false,     -- true = another addon feeds CLEU via API
		segmentHistory = 15,
		minFightLength = 5,       -- seconds; shorter fights are discarded
		mergePets = true,
		trackTargets = false,     -- per-target damage totals; nothing reads them yet
		onlyGroup = true,         -- only track group members (+pets)
		numberFormat = "short",   -- "short" | "full"
		decimals = 1,
		updateInterval = 0.5,
		deathLogSize = 16,
		combatGrace = 4,          -- sec out of combat before a fight closes
		deadGrace = 30,           -- longer grace while you're dead on a boss fight
		bossEndDelay = 1.5,       -- sec after the boss dies before closing
		maxFightLength = 900,     -- hard cap (sec); auto-splits runaway segments
		autoSplitTrash = false,   -- close trash pulls the moment combat drops
		llBridge = true,          -- share Log Lovers' combat log feed when present
		archive = {
			enabled = true,       -- permanently save boss fights
			spellDetail = true,   -- keep per-spell breakdowns (bigger, far more useful)
			killsOnly = false,    -- false = wipes are saved too
			raidOnly = false,     -- true = only archive while in a raid group
			maxFights = 60,       -- oldest unpinned fights prune past this
			maxSpells = 20,       -- spells kept per actor per category
			minDuration = 10,     -- ignore anything shorter than this
		},
		hideInCombatEditWarning = false,
		uiVersion = 0,
		-- right-click menu configuration (trimmable, per user request)
		menu = {
			modes = true, segments = true, actions = true,
			historyCount = 3,
		},
		menuModes = {
			damage = true, dps = true, healing = true, damageTaken = true,
			deaths = true, interrupts = true, dispels = true,
			overhealing = false, absorbs = false, healingPlusAbsorbs = false,
			friendlyFire = false, ccBreaks = false,
		},
	},
	edit = {
		snap = true, snapDist = 12,
		grid = false, gridSize = 32,
		showGuides = true,
	},
	windows = {},                -- array of window settings tables
}

--------------------------------------------------------------------------
-- Utility
--------------------------------------------------------------------------
local function deepcopy(src)
	local t = {}
	for k, v in pairs(src) do
		t[k] = (type(v) == "table") and deepcopy(v) or v
	end
	return t
end
ns.deepcopy = deepcopy

-- fill missing keys from defaults (non-destructive)
local function reconcile(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			reconcile(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end
ns.reconcile = reconcile

function PM:NewWindowSettings()
	return deepcopy(WINDOW_DEFAULTS)
end

function PM:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff4db8ffPulseMeter:|r " .. tostring(msg))
end

local floor = math.floor
function PM:FormatNumber(v)
	v = v or 0
	if self.db.general.numberFormat == "full" then
		return tostring(floor(v + 0.5))
	end
	local d = self.db.general.decimals
	if v >= 1e6 then return string.format("%." .. d .. "fM", v / 1e6)
	elseif v >= 1e3 then return string.format("%." .. d .. "fk", v / 1e3)
	else return tostring(floor(v + 0.5)) end
end

--------------------------------------------------------------------------
-- Profiles
--------------------------------------------------------------------------
local function charKey()
	return UnitName("player") .. " - " .. GetRealmName()
end

function PM:InitDB()
	PulseMeterDB = PulseMeterDB or {}
	local db = PulseMeterDB
	db.profiles = db.profiles or {}
	db.profileKeys = db.profileKeys or {}
	-- deliberately outside profiles: raid history must survive profile
	-- switching, renaming, and deletion
	db.archive = db.archive or { fights = {}, nextId = 1 }

	local key = db.profileKeys[charKey()] or charKey()
	db.profileKeys[charKey()] = key
	if not db.profiles[key] then
		db.profiles[key] = deepcopy(DEFAULTS)
	end
	self.db = db.profiles[key]
	self.profileName = key
	reconcile(self.db, DEFAULTS)

	-- The title bar became a two-line, centre-aligned header. Windows saved
	-- before that are too short to fit the fight line, so give them room once.
	if (self.db.general.uiVersion or 0) < 2 then
		self.db.general.uiVersion = 2
		for _, w in ipairs(self.db.windows) do
			if not w.isMini and (w.titleHeight or 0) < 26 then w.titleHeight = 26 end
		end
	end

	-- guarantee at least one window
	if #self.db.windows == 0 then
		self.db.windows[1] = self:NewWindowSettings()
	end
	for _, w in ipairs(self.db.windows) do
		reconcile(w, WINDOW_DEFAULTS)
	end
end

function PM:ListProfiles()
	local out = {}
	for name in pairs(PulseMeterDB.profiles) do out[#out + 1] = name end
	table.sort(out)
	return out
end

function PM:SetProfile(name, copyFromCurrent)
	if not PulseMeterDB.profiles[name] then
		PulseMeterDB.profiles[name] = copyFromCurrent and deepcopy(self.db) or deepcopy(DEFAULTS)
	end
	PulseMeterDB.profileKeys[charKey()] = name
	self:InitDB()
	self:RebuildWindows()
	self:Print("Profile set to |cffffffff" .. name .. "|r")
end

function PM:DeleteProfile(name)
	if name == self.profileName then self:Print("Cannot delete active profile.") return end
	PulseMeterDB.profiles[name] = nil
	for ck, pk in pairs(PulseMeterDB.profileKeys) do
		if pk == name then PulseMeterDB.profileKeys[ck] = ck end
	end
	self:Print("Deleted profile " .. name)
end

--------------------------------------------------------------------------
-- Group roster / pet ownership / guid->unit map
--------------------------------------------------------------------------
PM.roster = {}       -- [guid] = { name, class, unit }
PM.rosterEmpty = true
PM.petOwners = {}    -- [petGUID] = ownerGUID
PM.guidToUnit = {}   -- [guid] = unitID (for UnitHealth in death log)

local function scanUnit(unit)
	if not UnitExists(unit) then return end
	local guid = UnitGUID(unit)
	if not guid then return end
	local _, class = UnitClass(unit)
	PM.roster[guid] = { name = UnitName(unit), class = class, unit = unit }
	PM.guidToUnit[guid] = unit
	local pet = (unit == "player") and "pet" or (unit:gsub("^(%a+)(%d+)$", "%1pet%2"))
	if pet and UnitExists(pet) then
		local pg = UnitGUID(pet)
		if pg then
			PM.petOwners[pg] = guid
			PM.guidToUnit[pg] = pet
		end
	end
end

function PM:UpdateRoster()
	wipe(self.roster); wipe(self.guidToUnit)
	-- keep petOwners across updates (summons persist), just refresh known ones
	scanUnit("player")
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do scanUnit("raid" .. i) end
	elseif IsInGroup() then
		for i = 1, GetNumGroupMembers() - 1 do scanUnit("party" .. i) end
	end
	self.rosterEmpty = (next(self.roster) == nil)
end

-- Walk a summon chain up to the player who owns it. Totems, elementals and
-- treants are summoned by SPELL_SUMMON rather than being unit-token pets, and
-- some of them summon each other (Fire Elemental Totem -> Greater Fire
-- Elemental), so a single petOwners lookup is not enough.
function PM:ResolveOwner(guid)
	local cur, hops = guid, 0
	while cur and hops < 6 do
		local owner = self.petOwners[cur]
		if not owner then return nil end
		if self.roster[owner] then return owner end
		cur = owner
		hops = hops + 1
	end
	return nil
end

function PM:IsGroupGUID(guid)
	if self.rosterEmpty then self:UpdateRoster() end -- self-heal if the login scan was missed
	if self.roster[guid] then return true end
	return self:ResolveOwner(guid) and true or false
end

-- Guardians whose damage we could not attribute to a player, so the problem is
-- visible in /pm debug instead of silently vanishing from the meter.
PM.unattributed = {}

--------------------------------------------------------------------------
-- Segments
--------------------------------------------------------------------------
PM.current = nil        -- active fight segment
PM.overall = nil        -- accumulating "overall" segment
PM.history = {}         -- most recent first

local function newSegment(name)
	return {
		name = name or "Current fight",
		startTime = GetTime(),
		startStamp = time(),      -- wall clock, to line up with Log Lovers records
		endTime = nil,
		endStamp = nil,
		actors = {},          -- [guid] = actor table (see Parser)
		enemy = nil,          -- best-guess fight name
		intLog = {},          -- { t, src, dst, spell }
		dispelLog = {},       -- { t, src, dst, aura }
	}
end
ns.newSegment = newSegment

function PM:GetActiveTime(seg)
	if not seg then return 0 end
	return math.max((seg.endTime or GetTime()) - seg.startTime, 1)
end

function PM:StartCombat()
	if self.current then return end
	self.current = newSegment()
	if not self.overall then
		self.overall = newSegment("Overall")
	end
	self.inCombat = true
	self:FireCallback("SEGMENT_START", self.current)
	self:RefreshWindows(true)
end

function PM:EndCombat(reason)
	local seg = self.current
	if not seg then return end
	seg.endTime = GetTime()
	seg.endStamp = time()
	seg.name = seg.enemy or ("Fight " .. date("%H:%M:%S"))
	if seg.enemy and not ns.BOSSES[seg.enemy] and (seg.enemyCount or 1) > 1 then
		seg.name = seg.enemy .. " +" .. (seg.enemyCount - 1)
	end
	seg.endReason = reason
	self.current = nil
	self.inCombat = false

	-- permanent boss archive, independent of the rolling history cap
	if self.Archive then
		local ok, err = pcall(self.Archive.Save, seg)
		if not ok then self:Print("|cffff4d4darchive error:|r " .. tostring(err)) end
	end

	if seg.hasData then self.lastFight = seg end

	local len = seg.endTime - seg.startTime
	if len >= self.db.general.minFightLength and next(seg.actors) then
		table.insert(self.history, 1, seg)
		while #self.history > self.db.general.segmentHistory do
			table.remove(self.history)
		end
	end
	self:FireCallback("SEGMENT_END", seg)
	self:RefreshWindows(true)
end

-- Manually close the current fight and start fresh ( /pm new ).
function PM:SplitSegment()
	if self.current then
		self:EndCombat("manual")
		self:Print("Fight closed manually.")
	else
		self:Print("No fight in progress.")
	end
end

function PM:ResetAll()
	self.current = nil
	self.overall = nil
	self.lastFight = nil
	wipe(self.history)
	self:Print("Data reset.")
	self:RefreshWindows(true)
end

function PM:GetSegment(sel)
	if self.testMode then return self.testSegment end
	if sel == "archive" then
		return self.loadedArchive
	elseif sel == "current" then
		local cur = self.current
		if cur and cur.hasData then return cur end
		-- a freshly opened, still-empty segment never wins over a real fight
		return self.lastFight or self.history[1] or cur
	elseif sel == "overall" then
		return self.overall
	elseif type(sel) == "number" then
		return self.history[sel]
	end
end

--------------------------------------------------------------------------
-- Test mode: fills every window with believable fake raid data so you can
-- skin and arrange without a target dummy. Auto-enabled by edit mode when
-- there is no real data yet.
--------------------------------------------------------------------------
local TEST_ACTORS = {
	{ "Jabe", "ROGUE" }, { "Thalor", "WARRIOR" }, { "Mira", "PRIEST" },
	{ "Kelthas", "MAGE" }, { "Durn", "SHAMAN" }, { "Ashwyn", "WARLOCK" },
	{ "Petra", "PALADIN" }, { "Loam", "DRUID" }, { "Fenwick", "HUNTER" },
}
local TEST_SPELLS = {
	ROGUE = { "Sinister Strike", "Eviscerate", "Melee" },
	WARRIOR = { "Mortal Strike", "Whirlwind", "Melee" },
	PRIEST = { "Smite", "Shadow Word: Pain", "Mind Blast" },
	MAGE = { "Fireball", "Scorch", "Fire Blast" },
	SHAMAN = { "Lightning Bolt", "Chain Lightning", "Melee" },
	WARLOCK = { "Shadow Bolt", "Corruption", "Curse of Agony" },
	PALADIN = { "Seal of Command", "Judgement", "Melee" },
	DRUID = { "Wrath", "Moonfire", "Starfire" },
	HUNTER = { "Auto Shot", "Steady Shot", "Multi-Shot" },
}
local TEST_HEALS = { "Flash Heal", "Greater Heal", "Chain Heal", "Healing Touch", "Holy Light" }

local function testActor(i, def)
	local dmg = math.random(60000, 240000)
	local a = {
		guid = "test-" .. i, name = def[1], class = def[2], isPet = false,
		damage = dmg, damageTaken = math.random(8000, 45000), friendlyFire = math.random(0, 900),
		healing = math.random(5000, 120000), overhealing = math.random(2000, 40000),
		absorbs = math.random(0, 15000), healingTaken = math.random(10000, 40000),
		interrupts = math.random(0, 8), dispels = math.random(0, 12), steals = math.random(0, 2),
		ccBreaks = math.random(0, 3), deaths = math.random(0, 2),
		dmgSpells = {}, healSpells = {}, takenSpells = {},
		intSpells = {}, dispelSpells = {}, ccSpells = {},
		targets = {}, deathEvents = nil,
	}
	local spells = TEST_SPELLS[def[2]]
	local remain = dmg
	for si, sn in ipairs(spells) do
		local amt = si == #spells and remain or math.floor(remain * (0.35 + math.random() * 0.2))
		remain = remain - amt
		a.dmgSpells[sn] = { amount = amt, hits = math.random(20, 90), crits = math.random(3, 25), max = math.floor(amt / 10), icon = nil }
	end
	local hn = TEST_HEALS[math.random(#TEST_HEALS)]
	a.healSpells[hn] = { amount = a.healing, hits = math.random(10, 40), crits = math.random(1, 8), max = math.floor(a.healing / 6), icon = nil }
	a.takenSpells["Shadow Bolt Volley"] = { amount = a.damageTaken, hits = math.random(4, 15), crits = 0, max = math.floor(a.damageTaken / 4), icon = nil }
	if a.interrupts > 0 then
		a.intSpells["Frostbolt"] = { amount = 0, hits = a.interrupts, crits = 0, max = 0 }
	end
	if a.dispels > 0 then
		a.dispelSpells["Polymorph"] = { amount = 0, hits = a.dispels, crits = 0, max = 0 }
	end
	if a.deaths > 0 then
		a.deathEvents = {}
		for _ = 1, a.deaths do
			local log = {}
			local hp = 100
			for li = 6, 1, -1 do
				local hit = math.random(1500, 4500)
				hp = math.max(hp - math.random(12, 30), 0)
				log[#log + 1] = {
					t = GetTime() - li * 1.4, text = "Shadow Bolt (Test Boss)",
					amount = hit, heal = (li == 4), hp = hp * 100, hpMax = 10000,
				}
			end
			a.deathEvents[#a.deathEvents + 1] = { time = GetTime(), log = log }
		end
	end
	return a
end

function PM:BuildTestSegment()
	local seg = newSegment("Test Data")
	seg.enemy = "Gruul the Dragonkiller"
	seg.startTime = GetTime() - 95
	for i, def in ipairs(TEST_ACTORS) do
		seg.actors["test-" .. i] = testActor(i, def)
	end
	for i = 1, 10 do
		local src = TEST_ACTORS[math.random(#TEST_ACTORS)][1]
		seg.intLog[#seg.intLog + 1] = { t = i * 8.3, src = src, dst = "Gronn Adept", spell = "Heal" }
		seg.dispelLog[#seg.dispelLog + 1] = { t = i * 7.1, src = src, dst = TEST_ACTORS[math.random(#TEST_ACTORS)][1], aura = "Ground Slam Daze" }
	end
	self.testSegment = seg
end

function PM:SetTestMode(on)
	self.testMode = on and true or false
	if on and not self.testSegment then self:BuildTestSegment() end
	self:RefreshWindows(true)
	self:Print("Test mode " .. (on and "|cff4dff4dON|r - windows show fake data" or "|cffff4d4dOFF|r"))
end

-- small live jitter so test data feels alive; called from window updates
function PM:TickTestData()
	local seg = self.testSegment
	if not seg then return end
	for _, a in pairs(seg.actors) do
		if math.random(3) == 1 then
			local add = math.random(200, 1600)
			a.damage = a.damage + add
			for _, s in pairs(a.dmgSpells) do s.amount = s.amount + add break end
		end
	end
end

-- combat end detection: player leaves combat AND no group damage for 3s
local lastActivity = 0
function PM:NoteActivity() lastActivity = GetTime() end

--------------------------------------------------------------------------
-- Combat-state driven segmentation.
--
-- The old build closed a fight when the COMBAT LOG went quiet. In a raid the
-- log never goes quiet - every one of 24 other raiders' events counts as
-- "activity", so segments merged into one endless blob. We now ask the units
-- themselves whether anyone is still fighting, which is what actually defines
-- a pull.
--------------------------------------------------------------------------
local function groupStillFighting()
	if UnitAffectingCombat("player") then return true end
	local pet = UnitExists("pet") and UnitAffectingCombat("pet")
	if pet then return true end
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local u = "raid" .. i
			if UnitExists(u) and not UnitIsDeadOrGhost(u) and UnitIsVisible(u)
				and UnitAffectingCombat(u) then
				return true
			end
		end
	elseif IsInGroup() then
		for i = 1, GetNumGroupMembers() - 1 do
			local u = "party" .. i
			if UnitExists(u) and not UnitIsDeadOrGhost(u) and UnitIsVisible(u)
				and UnitAffectingCombat(u) then
				return true
			end
		end
	end
	return false
end
PM.GroupInCombat = groupStillFighting

local outOfCombatSince = nil
local endChecker = 0
PM:SetScript("OnUpdate", function(self, elapsed)
	endChecker = endChecker + elapsed
	if endChecker < 0.5 then return end
	endChecker = 0

	local seg = self.current
	if not seg then outOfCombatSince = nil return end
	local now = GetTime()
	local g = self.db.general

	-- 1. hard cap: never let one segment swallow an entire raid night
	if (now - seg.startTime) > (g.maxFightLength or 900) then
		self:EndCombat("timeout")
		self:Print("Fight ran past the length cap - split into a new segment.")
		return
	end

	-- 2. the boss died: close promptly so loot and rezzing aren't tacked on.
	-- Trash never qualifies - the group-combat check below handles that, so a
	-- multi-mob pull stays in one segment.
	if seg.bossDiedAt and seg.enemy and ns.BOSSES[seg.enemy]
		and (now - seg.bossDiedAt) > (g.bossEndDelay or 1.5) then
		self:EndCombat("boss")
		return
	end

	-- 3. nobody in the group is in combat any more
	if groupStillFighting() then
		outOfCombatSince = nil
		self.inCombat = true
	else
		outOfCombatSince = outOfCombatSince or now
		local grace = g.combatGrace or 4

		-- Corpse-running out of a raid puts every group member out of range,
		-- so UnitAffectingCombat reports nobody fighting even though the pull
		-- is still going. Hold a boss fight open much longer while you're
		-- dead, so a battle rez - or the raid finishing without you - still
		-- lands in the same segment instead of splitting it in half.
		if UnitIsDeadOrGhost("player") and IsInGroup()
			and seg.enemy and ns.BOSSES[seg.enemy] then
			grace = math.max(grace, g.deadGrace or 30)
		elseif seg.enemy and not ns.BOSSES[seg.enemy] and g.autoSplitTrash then
			grace = 1
		end

		if (now - outOfCombatSince) > grace then
			self:EndCombat("combat-drop")
			outOfCombatSince = nil
		end
	end
end)

--------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------
PM:RegisterEvent("ADDON_LOADED")
PM:SetScript("OnEvent", function(self, event, ...)
	if self[event] then self[event](self, ...) end
end)

function PM:ADDON_LOADED(name)
	if name ~= ADDON then return end
	self:UnregisterEvent("ADDON_LOADED")
	self:InitDB()

	self:RegisterEvent("PLAYER_LOGIN")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("GROUP_ROSTER_UPDATE")
	self:RegisterEvent("UNIT_PET")
	self:RegisterEvent("PLAYER_REGEN_DISABLED")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	-- ALWAYS read the combat log ourselves until an external feed actually
	-- connects via the API (API:SetExternalFeed). A stale saved setting can
	-- no longer silently disable all data collection.
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	if self.db.general.externalFeed then
		self:Print("|cffffd100Note:|r external feed setting is on, but PulseMeter keeps reading the combat log until a feed connects via the API.")
	end
end

function PM:PLAYER_ENTERING_WORLD()
	self:UpdateRoster()
end

function PM:PLAYER_LOGIN()
	self:UpdateRoster()
	self:RebuildWindows()
	self:Print("loaded. |cffffffff/pm|r for options, |cffffffff/pm edit|r for live edit mode.")
end

function PM:GROUP_ROSTER_UPDATE() self:UpdateRoster() end
function PM:UNIT_PET(unit) scanUnit(unit) end

function PM:PLAYER_REGEN_DISABLED()
	self:StartCombat()
	self:UpdateWindowAlphas(true)
end

function PM:PLAYER_REGEN_ENABLED()
	-- deliberately does NOT extend the fight; the OnUpdate loop decides,
	-- based on whether anyone in the group is still actually fighting
	self:UpdateWindowAlphas(false)
end

PM.stats = { events = 0, damage = 0, errors = 0 }

function PM:COMBAT_LOG_EVENT_UNFILTERED()
	local ok, err = pcall(self.ParseCLEU, self, CombatLogGetCurrentEventInfo())
	if not ok then
		self.stats.errors = self.stats.errors + 1
		if self.stats.errors <= 3 then
			self:Print("|cffff4d4dparser error:|r " .. tostring(err))
		end
	end
end

function PM:Debug()
	local g = self.db.general
	self:Print("--- debug ---")
	local own = self:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED") and true or false
	self:Print("own CLEU registration: " .. tostring(own)
		.. "  |  fed by Log Lovers: " .. tostring((self.llFeedHooked and not self.llFeedDisabled) and true or false))
	self:Print("test mode: " .. tostring(self.testMode) .. "  |  in combat: " .. tostring(self.inCombat))
	local n = 0
	for _ in pairs(self.roster) do n = n + 1 end
	self:Print("roster size: " .. n .. " (should be at least 1 - you)")
	self:Print("CLEU events seen: " .. self.stats.events .. "  |  damage events recorded: " .. self.stats.damage
		.. "  |  parse errors: " .. self.stats.errors)
	self:Print("current segment: " .. tostring(self.current and "yes" or "no")
		.. "  |  history segments: " .. #self.history)
	if self.current then
		self:Print(("fight running %ds  |  group in combat: %s  |  enemy: %s"):format(
			GetTime() - self.current.startTime, tostring(groupStillFighting()),
			tostring(self.current.enemy)))
	end
	self:Print("LogLovers bridge: " .. (self.llBridge or "not detected"))

	-- Count everything on the machine that is reading the combat log. This is
	-- the only honest way to answer "how many addons are parsing this twice".
	if GetFramesRegisteredForEvent then
		local ok, list = pcall(function()
			return { GetFramesRegisteredForEvent("COMBAT_LOG_EVENT_UNFILTERED") }
		end)
		if ok and list then
			local names = {}
			for i, fr in ipairs(list) do
				if i > 12 then names[#names + 1] = "..." break end
				local n = fr.GetName and fr:GetName()
				names[#names + 1] = n or "(unnamed)"
			end
			self:Print(("frames reading the combat log: |cffffd100%d|r  -  %s"):format(
				#list, table.concat(names, ", ")))
			if #list > 2 then
				self:Print("|cff888888Each of those calls CombatLogGetCurrentEventInfo() and parses "
					.. "independently. Fewer is cheaper.|r")
			end
		end
	end
	if self.Archive then
		self:Print(("archived boss fights: %d  |  approx size: %s"):format(
			#self.Archive.Fights(), self.Archive.SizeText()))
	end

	local orphans, n = {}, 0
	for name, hits in pairs(self.unattributed) do
		n = n + 1
		if n <= 8 then orphans[#orphans + 1] = name .. " x" .. hits end
	end
	if n > 0 then
		self:Print("|cffffd100unattributed summons:|r " .. table.concat(orphans, ", ")
			.. (n > 8 and (" (+" .. (n - 8) .. " more)") or ""))
		self:Print("|cff888888These are shown as their own rows rather than merged. "
			.. "Their damage is counted either way.|r")
	else
		self:Print("unattributed summons: none - every pet and totem mapped to an owner")
	end
	if self.stats.events == 0 then
		self:Print("|cffffd100No combat log events received at all - check that the addon folder is named exactly 'PulseMeter'.|r")
	elseif self.stats.damage == 0 and self.stats.errors > 0 then
		self:Print("|cffffd100Events arrive but the parser is erroring - the message above tells us where. Send it my way.|r")
	end
end

--------------------------------------------------------------------------
-- Callbacks (used by API.lua)
--------------------------------------------------------------------------
function PM:FireCallback(msg, ...)
	local list = self.callbacks[msg]
	if not list then return end
	for _, fn in ipairs(list) do
		local ok, err = pcall(fn, msg, ...)
		if not ok then geterrorhandler()(err) end
	end
end

--------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------
SLASH_PULSEMETER1 = "/pulsemeter"
SLASH_PULSEMETER2 = "/pm"
SlashCmdList.PULSEMETER = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, arg = msg:match("^(%S*)%s*(.*)$")
	if cmd == "edit" then
		PM:ToggleEditMode()
	elseif cmd == "reset" then
		PM:ResetAll()
	elseif cmd == "new" or cmd == "split" then
		PM:SplitSegment()
	elseif cmd == "window" then
		PM:CreateNewWindow()
	elseif cmd == "toggle" then
		PM:ToggleAllWindows()
	elseif cmd == "deaths" or cmd == "browser" or cmd == "log" or cmd == "logs" then
		PM:ToggleBrowser(cmd == "deaths" and "deaths" or nil)
	elseif cmd == "test" then
		PM:SetTestMode(not PM.testMode)
	elseif cmd == "debug" then
		PM:Debug()
	elseif cmd == "saved" or cmd == "archive" or cmd == "fights" then
		PM:ToggleBrowser("saved")
	elseif cmd == "ll" or cmd == "loglovers" then
		if arg == "on" then PM:SetLLBridge(true)
		elseif arg == "off" then PM:SetLLBridge(false)
		else PM:Print("Log Lovers bridge: " .. (PM.llBridge or "not detected")
			.. "  (/pm ll on | off)") end
	elseif cmd == "mini" then
		if arg == "deaths" or arg == "interrupts" or arg == "dispels" then
			PM:CreateMiniWindow(arg == "deaths" and "deaths" or arg)
		else
			PM:Print("Usage: /pm mini deaths | interrupts | dispels")
		end
	else
		PM:ToggleOptions()
	end
end
