-- PulseMeter Archive.lua
-- Permanent storage for boss fights.
--
-- The rolling history (PM.history) is a short in-memory list that dies with
-- the session. The archive is different: every boss pull is written into
-- SavedVariables and stays there until you delete it - across logouts,
-- across leaving the raid, across dying and releasing mid-fight.
--
-- Memory model
-- ------------
-- Live segments are convenient but fat: every actor carries six keyed spell
-- tables and a target map. Serialising that verbatim would put megabytes of
-- repeated key names into SavedVariables. Archived fights are therefore
-- COMPACTED into positional arrays on the way in and only rehydrated into a
-- normal segment when you actually open one. One fight is expanded at a time.
--
-- Anything not pinned is pruned oldest-first once the fight count passes the
-- limit, so the file cannot grow without bound.

local ADDON, ns = ...
local PM = ns.PM

local Archive = {}
PM.Archive = Archive

local SCHEMA = 1

--------------------------------------------------------------------------
-- Store access. Lives at the top level of PulseMeterDB, NOT inside a
-- profile, so switching or deleting a profile never destroys raid history.
--------------------------------------------------------------------------
local function store()
	PulseMeterDB = PulseMeterDB or {}
	PulseMeterDB.archive = PulseMeterDB.archive or { fights = {}, nextId = 1 }
	local a = PulseMeterDB.archive
	a.fights = a.fights or {}
	a.nextId = a.nextId or 1
	return a
end
Archive.Store = store

function Archive.Settings()
	local g = PM.db.general
	g.archive = g.archive or {}
	local s = g.archive
	if s.enabled == nil then s.enabled = true end
	if s.spellDetail == nil then s.spellDetail = true end
	if s.killsOnly == nil then s.killsOnly = false end
	if s.raidOnly == nil then s.raidOnly = false end
	s.maxFights = s.maxFights or 60
	s.maxSpells = s.maxSpells or 20
	s.minDuration = s.minDuration or 10
	return s
end

--------------------------------------------------------------------------
-- Compaction
--------------------------------------------------------------------------
-- keyed spell table -> { {name, amount, hits, crits, max, spellId}, ... }
local function packSpells(tbl, limit)
	if not tbl then return nil end
	local list = {}
	for name, s in pairs(tbl) do
		if (s.amount or 0) > 0 or (s.hits or 0) > 0 then
			list[#list + 1] = { name, s.amount or 0, s.hits or 0, s.crits or 0, s.max or 0, s.icon }
		end
	end
	if #list == 0 then return nil end
	table.sort(list, function(x, y)
		if x[2] == y[2] then return x[3] > y[3] end
		return x[2] > y[2]
	end)
	while #list > limit do table.remove(list) end
	return list
end

local function unpackSpells(list)
	local out = {}
	if not list then return out end
	for _, e in ipairs(list) do
		out[e[1]] = { amount = e[2], hits = e[3], crits = e[4], max = e[5], icon = e[6] }
	end
	return out
end

-- Deaths are stored as a one-line summary only. The full timeline belongs to
-- Log Lovers, which already persists its own recaps and does it better.
local function packDeaths(seg)
	local out = {}
	for _, a in pairs(seg.actors) do
		if a.deathEvents then
			for _, ev in ipairs(a.deathEvents) do
				local killer, spell
				local last = ev.log and ev.log[#ev.log]
				if last then
					spell = last.text
				end
				out[#out + 1] = {
					a.name, math.max((ev.time or 0) - seg.startTime, 0), spell or "", killer or "",
				}
			end
		end
	end
	table.sort(out, function(x, y) return x[2] < y[2] end)
	return #out > 0 and out or nil
end

function Archive.Compact(seg)
	local s = Archive.Settings()
	local limit = s.spellDetail and s.maxSpells or 0
	local entry = {
		v = SCHEMA,
		id = 0,
		name = seg.enemy or seg.name,
		zone = seg.zone,
		date = seg.startStamp or time(),
		dur = math.floor(((seg.endTime or 0) - seg.startTime) * 10 + 0.5) / 10,
		kill = seg.bossDiedAt and true or false,
		char = UnitName("player"),
		realm = GetRealmName and GetRealmName() or "",
		size = GetNumGroupMembers and GetNumGroupMembers() or 0,
		actors = {},
	}

	for _, a in pairs(seg.actors) do
		if not (PM.db.general.mergePets and a.isPet) then
			local any = (a.damage or 0) + (a.healing or 0) + (a.damageTaken or 0)
				+ (a.deaths or 0) + (a.interrupts or 0) + (a.dispels or 0)
			if any > 0 then
				local rec = {
					n = a.name, c = a.class,
					d = a.damage or 0, h = a.healing or 0, oh = a.overhealing or 0,
					ab = a.absorbs or 0, dt = a.damageTaken or 0, ff = a.friendlyFire or 0,
					ht = a.healingTaken or 0, ints = a.interrupts or 0,
					dis = a.dispels or 0, st = a.steals or 0, cc = a.ccBreaks or 0,
					dth = a.deaths or 0,
				}
				if limit > 0 then
					rec.ds = packSpells(a.dmgSpells, limit)
					rec.hs = packSpells(a.healSpells, limit)
					rec.ts = packSpells(a.takenSpells, limit)
					rec.is = packSpells(a.intSpells, limit)
					rec.xs = packSpells(a.dispelSpells, limit)
					rec.cs = packSpells(a.ccSpells, limit)
				end
				entry.actors[#entry.actors + 1] = rec
			end
		end
	end

	entry.deaths = packDeaths(seg)

	-- interrupt / dispel logs, capped: these are cheap and genuinely useful
	if seg.intLog and #seg.intLog > 0 then
		entry.il = {}
		for i = 1, math.min(#seg.intLog, 60) do
			local e = seg.intLog[i]
			entry.il[i] = { math.floor(e.t * 10) / 10, e.src, e.dst, e.spell }
		end
	end
	if seg.dispelLog and #seg.dispelLog > 0 then
		entry.dl = {}
		for i = 1, math.min(#seg.dispelLog, 60) do
			local e = seg.dispelLog[i]
			entry.dl[i] = { math.floor(e.t * 10) / 10, e.src, e.dst, e.aura }
		end
	end

	return entry
end

--------------------------------------------------------------------------
-- Rehydration: one archived fight -> a segment the windows can render
--------------------------------------------------------------------------
function Archive.Restore(entry)
	if not entry then return nil end
	local seg = {
		name = entry.name or "Saved fight",
		enemy = entry.name,
		zone = entry.zone,
		startTime = 0,
		endTime = entry.dur or 1,
		startStamp = entry.date,
		endStamp = (entry.date or 0) + (entry.dur or 0),
		actors = {},
		intLog = {},
		dispelLog = {},
		archived = true,
		archiveId = entry.id,
	}
	for i, r in ipairs(entry.actors or {}) do
		local guid = "archive-" .. (entry.id or 0) .. "-" .. i
		seg.actors[guid] = {
			guid = guid, name = r.n, class = r.c, isPet = false,
			damage = r.d or 0, healing = r.h or 0, overhealing = r.oh or 0,
			absorbs = r.ab or 0, damageTaken = r.dt or 0, friendlyFire = r.ff or 0,
			healingTaken = r.ht or 0, interrupts = r.ints or 0, dispels = r.dis or 0,
			steals = r.st or 0, ccBreaks = r.cc or 0, deaths = r.dth or 0,
			absorbedTaken = 0,
			dmgSpells = unpackSpells(r.ds), healSpells = unpackSpells(r.hs),
			takenSpells = unpackSpells(r.ts), intSpells = unpackSpells(r.is),
			dispelSpells = unpackSpells(r.xs), ccSpells = unpackSpells(r.cs),
			targets = {}, deathEvents = nil,
		}
	end
	for _, e in ipairs(entry.il or {}) do
		seg.intLog[#seg.intLog + 1] = { t = e[1], src = e[2], dst = e[3], spell = e[4] }
	end
	for _, e in ipairs(entry.dl or {}) do
		seg.dispelLog[#seg.dispelLog + 1] = { t = e[1], src = e[2], dst = e[3], aura = e[4] }
	end
	return seg
end

--------------------------------------------------------------------------
-- Writing
--------------------------------------------------------------------------
function Archive.ShouldSave(seg)
	local s = Archive.Settings()
	if not s.enabled then return false, "archive off" end
	if not seg or not seg.enemy then return false, "no enemy" end
	if not ns.BOSSES[seg.enemy] then return false, "not a boss" end
	if s.killsOnly and not seg.bossDiedAt then return false, "wipe, kills-only is on" end
	if s.raidOnly and not (IsInRaid and IsInRaid()) then return false, "not in a raid" end
	local dur = (seg.endTime or GetTime()) - seg.startTime
	if dur < (s.minDuration or 10) then return false, "too short" end
	if not next(seg.actors) then return false, "no data" end
	return true
end

function Archive.Save(seg)
	local ok = Archive.ShouldSave(seg)
	if not ok then return nil end
	local a = store()
	local entry = Archive.Compact(seg)
	entry.id = a.nextId
	a.nextId = a.nextId + 1
	table.insert(a.fights, entry)
	Archive.Prune()
	PM:Print(("Saved |cffffd100%s|r (%s, %s) - %d fights archived. |cff888888/pm saved|r"):format(
		entry.name, entry.kill and "kill" or "wipe", Archive.Duration(entry), #a.fights))
	return entry
end

-- oldest unpinned fights go first; pinned ones are never auto-removed
function Archive.Prune()
	local s = Archive.Settings()
	local a = store()
	local limit = s.maxFights or 60
	while #a.fights > limit do
		local victim
		for i = 1, #a.fights do
			if not a.fights[i].pin then victim = i break end
		end
		if not victim then return end   -- everything is pinned; respect that
		table.remove(a.fights, victim)
	end
end

--------------------------------------------------------------------------
-- Queries and maintenance
--------------------------------------------------------------------------
function Archive.Fights() return store().fights end

function Archive.Find(id)
	for i, f in ipairs(store().fights) do
		if f.id == id then return f, i end
	end
end

function Archive.Delete(id)
	local f, i = Archive.Find(id)
	if not i then return false end
	table.remove(store().fights, i)
	if PM.loadedArchive and PM.loadedArchive.archiveId == id then
		PM.loadedArchive = nil
		PM:RefreshWindows(true)
	end
	return true
end

function Archive.TogglePin(id)
	local f = Archive.Find(id)
	if not f then return end
	f.pin = not f.pin and true or nil
	return f.pin
end

function Archive.Clear(keepPinned)
	local a = store()
	if keepPinned then
		for i = #a.fights, 1, -1 do
			if not a.fights[i].pin then table.remove(a.fights, i) end
		end
	else
		wipe(a.fights)
	end
	PM.loadedArchive = nil
	PM:RefreshWindows(true)
end

function Archive.Duration(entry)
	local d = entry.dur or 0
	return string.format("%d:%02d", math.floor(d / 60), math.floor(d % 60))
end

-- Rough serialised size, so the options panel can show what this costs.
local function measure(v)
	local t = type(v)
	if t == "number" then return 8
	elseif t == "string" then return #v + 3
	elseif t == "boolean" then return 5
	elseif t ~= "table" then return 4 end
	local n = 2
	for k, val in pairs(v) do
		if type(k) == "string" then n = n + #k + 4 end
		n = n + measure(val) + 1
	end
	return n
end

function Archive.EstimateBytes()
	return measure(store().fights)
end

function Archive.SizeText()
	local b = Archive.EstimateBytes()
	if b > 1048576 then return string.format("%.1f MB", b / 1048576) end
	if b > 1024 then return string.format("%.0f KB", b / 1024) end
	return b .. " B"
end

-- Group fights into raid nights for the browser: same zone, same calendar day.
function Archive.Groups()
	local groups, index = {}, {}
	local fights = store().fights
	for i = #fights, 1, -1 do            -- newest first
		local f = fights[i]
		local day = date("%Y-%m-%d", f.date or time())
		local key = (f.zone or "Unknown") .. "|" .. day .. "|" .. (f.char or "")
		local g = index[key]
		if not g then
			g = {
				name = (f.zone or "Unknown") .. "  -  " .. date("%b %d", f.date or time()),
				char = f.char, fights = {},
			}
			index[key] = g
			groups[#groups + 1] = g
		end
		g.fights[#g.fights + 1] = f
	end
	return groups
end

--------------------------------------------------------------------------
-- Loading one into the windows
--------------------------------------------------------------------------
function PM:LoadArchivedFight(id, windowIndex)
	local entry = Archive.Find(id)
	if not entry then self:Print("That saved fight is gone.") return end
	self.loadedArchive = Archive.Restore(entry)
	local w = self.windows[windowIndex or 1] or self.windows[1]
	if w then
		w.settings.segment = "archive"
		w.offset = 0
		w.dirty = true
		w:Refresh()
	end
	self:Print(("Loaded |cffffd100%s|r (%s) into window %d."):format(
		entry.name, date("%b %d %H:%M", entry.date or time()), w and w.index or 1))
end
