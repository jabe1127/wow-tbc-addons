-- PulseMeter Modes.lua
-- Every mode a window can display. Each mode defines how to value, format,
-- and detail an actor. Adding a new mode = adding a table entry.

local ADDON, ns = ...
local PM = ns.PM

local function ps(v, seg) return v / PM:GetActiveTime(seg) end

local function spellTooltip(tt, spells, total)
	local list = {}
	for name, s in pairs(spells) do list[#list + 1] = { name = name, s = s } end
	table.sort(list, function(a, b) return a.s.amount > b.s.amount end)
	for i = 1, math.min(#list, 8) do
		local e = list[i]
		local pct = total > 0 and (e.s.amount / total * 100) or 0
		tt:AddDoubleLine(
			string.format("%d. %s", i, e.name),
			string.format("%s (%.0f%%)", PM:FormatNumber(e.s.amount), pct),
			1, 1, 1, 0.85, 0.85, 0.85)
	end
end

PM.modes = {}
PM.modeOrder = {}

local function addMode(key, def)
	def.key = key
	PM.modes[key] = def
	PM.modeOrder[#PM.modeOrder + 1] = key
end

--------------------------------------------------------------------------
addMode("damage", {
	name = "Damage Done",
	value = function(a) return a.damage end,
	barText = function(a, seg)
		return PM:FormatNumber(a.damage), PM:FormatNumber(ps(a.damage, seg)) .. " dps"
	end,
	tooltip = function(tt, a, seg)
		tt:AddLine(a.name .. " - Damage", 1, 1, 1)
		tt:AddDoubleLine("Total", PM:FormatNumber(a.damage), 0.8, 0.8, 0.8, 1, 1, 1)
		tt:AddDoubleLine("DPS", PM:FormatNumber(ps(a.damage, seg)), 0.8, 0.8, 0.8, 1, 1, 1)
		tt:AddLine(" ")
		spellTooltip(tt, a.dmgSpells, a.damage)
	end,
})

addMode("dps", {
	name = "DPS",
	value = function(a, seg) return ps(a.damage, seg) end,
	barText = function(a, seg)
		return PM:FormatNumber(ps(a.damage, seg)), PM:FormatNumber(a.damage) .. " total"
	end,
	tooltip = PM.modes.damage.tooltip,
})

addMode("healing", {
	name = "Healing Done",
	value = function(a) return a.healing end,
	barText = function(a, seg)
		return PM:FormatNumber(a.healing), PM:FormatNumber(ps(a.healing, seg)) .. " hps"
	end,
	tooltip = function(tt, a, seg)
		tt:AddLine(a.name .. " - Healing", 1, 1, 1)
		tt:AddDoubleLine("Effective", PM:FormatNumber(a.healing), 0.8, 0.8, 0.8, 0.3, 1, 0.3)
		tt:AddDoubleLine("Overheal", PM:FormatNumber(a.overhealing), 0.8, 0.8, 0.8, 1, 0.5, 0.5)
		local tot = a.healing + a.overhealing
		if tot > 0 then
			tt:AddDoubleLine("Overheal %", string.format("%.1f%%", a.overhealing / tot * 100), 0.8, 0.8, 0.8, 1, 1, 1)
		end
		tt:AddLine(" ")
		spellTooltip(tt, a.healSpells, a.healing)
	end,
})

addMode("overhealing", {
	name = "Overhealing",
	value = function(a) return a.overhealing end,
	barText = function(a) return PM:FormatNumber(a.overhealing), nil end,
	tooltip = PM.modes.healing.tooltip,
})

addMode("absorbs", {
	name = "Absorbs",
	value = function(a) return a.absorbs end,
	barText = function(a) return PM:FormatNumber(a.absorbs), nil end,
	tooltip = function(tt, a)
		tt:AddLine(a.name .. " - Absorbs", 1, 1, 1)
		tt:AddDoubleLine("Total absorbed", PM:FormatNumber(a.absorbs), 0.8, 0.8, 0.8, 1, 1, 1)
		tt:AddLine("Reconstructed from shield casts +", 0.6, 0.6, 0.6)
		tt:AddLine("absorbed hits (TBC log limitation).", 0.6, 0.6, 0.6)
	end,
})

addMode("healingPlusAbsorbs", {
	name = "Healing + Absorbs",
	value = function(a) return a.healing + a.absorbs end,
	barText = function(a, seg)
		local v = a.healing + a.absorbs
		return PM:FormatNumber(v), PM:FormatNumber(ps(v, seg)) .. " hps"
	end,
	tooltip = PM.modes.healing.tooltip,
})

addMode("damageTaken", {
	name = "Damage Taken",
	value = function(a) return a.damageTaken end,
	barText = function(a) return PM:FormatNumber(a.damageTaken), nil end,
	tooltip = function(tt, a)
		tt:AddLine(a.name .. " - Damage Taken", 1, 1, 1)
		tt:AddDoubleLine("Total", PM:FormatNumber(a.damageTaken), 0.8, 0.8, 0.8, 1, 1, 1)
		tt:AddLine(" ")
		spellTooltip(tt, a.takenSpells, a.damageTaken)
	end,
})

addMode("friendlyFire", {
	name = "Friendly Fire",
	value = function(a) return a.friendlyFire end,
	barText = function(a) return PM:FormatNumber(a.friendlyFire), nil end,
	tooltip = function(tt, a)
		tt:AddLine(a.name .. " - Friendly Fire", 1, 1, 1)
		tt:AddDoubleLine("Total", PM:FormatNumber(a.friendlyFire), 0.8, 0.8, 0.8, 1, 0.4, 0.4)
	end,
})

addMode("deaths", {
	name = "Deaths",
	value = function(a) return a.deaths end,
	barText = function(a) return tostring(a.deaths), nil end,
	tooltip = function(tt, a)
		tt:AddLine(a.name .. " - Deaths: " .. a.deaths, 1, 1, 1)
		local ev = a.deathEvents
		if ev and #ev > 0 then
			local last = ev[#ev]
			tt:AddLine(" ")
			tt:AddLine("Last death recap:", 1, 0.82, 0)
			for _, e in ipairs(last.log) do
				local delta = string.format("-%.1fs", last.time - e.t)
				local r, g, b = 1, 0.45, 0.45
				if e.heal then r, g, b = 0.45, 1, 0.45 end
				tt:AddDoubleLine(
					delta .. "  " .. e.text,
					(e.heal and "+" or "-") .. PM:FormatNumber(e.amount),
					0.8, 0.8, 0.8, r, g, b)
			end
		end
	end,
})

addMode("interrupts", {
	name = "Interrupts",
	value = function(a) return a.interrupts end,
	barText = function(a) return tostring(a.interrupts), nil end,
	tooltip = function(tt, a)
		tt:AddLine(a.name .. " - Interrupts: " .. a.interrupts, 1, 1, 1)
	end,
})

addMode("dispels", {
	name = "Dispels",
	value = function(a) return a.dispels + a.steals end,
	barText = function(a) return tostring(a.dispels + a.steals), nil end,
	tooltip = function(tt, a)
		tt:AddLine(a.name .. " - Dispels", 1, 1, 1)
		tt:AddDoubleLine("Dispels", a.dispels, 0.8, 0.8, 0.8, 1, 1, 1)
		tt:AddDoubleLine("Spell steals", a.steals, 0.8, 0.8, 0.8, 1, 1, 1)
	end,
})

addMode("ccBreaks", {
	name = "CC Breaks",
	value = function(a) return a.ccBreaks end,
	barText = function(a) return tostring(a.ccBreaks), nil end,
	tooltip = function(tt, a)
		tt:AddLine(a.name .. " - CC Breaks: " .. a.ccBreaks, 1, 1, 1)
	end,
})


--------------------------------------------------------------------------
-- Drill-down detail providers (click a bar -> in-window spell breakdown)
--------------------------------------------------------------------------
local function detailFrom(tbl, useHits)
	return function(a)
		local out, total = {}, 0
		local src = a[tbl]
		if src then
			for name, s in pairs(src) do
				local v = useHits and s.hits or s.amount
				if v > 0 then
					out[#out + 1] = { name = name, value = v, s = s, count = useHits }
					total = total + v
				end
			end
		end
		table.sort(out, function(x, y) return x.value > y.value end)
		return out, total
	end
end

PM.modes.damage.detail = detailFrom("dmgSpells")
PM.modes.dps.detail = detailFrom("dmgSpells")
PM.modes.healing.detail = detailFrom("healSpells")
PM.modes.overhealing.detail = detailFrom("healSpells")
PM.modes.healingPlusAbsorbs.detail = detailFrom("healSpells")
PM.modes.damageTaken.detail = detailFrom("takenSpells")
PM.modes.interrupts.detail = detailFrom("intSpells", true)
PM.modes.dispels.detail = detailFrom("dispelSpells", true)
PM.modes.ccBreaks.detail = detailFrom("ccSpells", true)
-- deaths: clicking a bar opens the Death Browser instead (handled in Window)
PM.modes.deaths.openBrowser = "deaths"

--------------------------------------------------------------------------
-- Sorted actor list for a window
--------------------------------------------------------------------------
local sortBuf = {}
function PM:GetSortedActors(seg, modeKey)
	wipe(sortBuf)
	if not seg then return sortBuf, 0 end
	local mode = self.modes[modeKey]
	if not mode then return sortBuf, 0 end
	local total = 0
	for guid, a in pairs(seg.actors) do
		-- When pets are merged their damage went to the owner, so the raw pet
		-- row is a duplicate and gets skipped. A pet with NO resolvable owner
		-- was never merged into anything, so hiding it would delete its damage
		-- from the meter entirely - that is how totem damage went missing.
		local duplicate = self.db.general.mergePets and a.isPet and a.owner ~= nil
		if not duplicate then
			local v = mode.value(a, seg)
			if v and v > 0 then
				sortBuf[#sortBuf + 1] = { actor = a, value = v }
				total = total + v
			end
		end
	end
	table.sort(sortBuf, function(x, y) return x.value > y.value end)
	return sortBuf, total
end
