-- PulseMeter API.lua
-- Public integration surface. This is how your other addon plugs in.
--
-- Two integration styles:
--
--  A) PulseMeter reads the combat log itself (default). Your addon just
--     reads data back out:
--         local seg = PulseMeter.API:GetCurrentSegment()
--
--  B) Your addon owns the combat log and FEEDS PulseMeter. Enable
--     "External combat log feed" in /pm options (or set it below), then
--     from your addon's CLEU handler call:
--         PulseMeter.API:FeedCLEU(CombatLogGetCurrentEventInfo())
--     PulseMeter will not register COMBAT_LOG_EVENT_UNFILTERED itself.

local ADDON, ns = ...
local PM = ns.PM

local API = {}
PM.API = API

--------------------------------------------------------------------------
-- Feeding events (integration style B)
--------------------------------------------------------------------------
function API:SetExternalFeed(enabled)
	PM.db.general.externalFeed = enabled and true or false
	if enabled then
		PM:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
		PM:Print("External combat log feed connected.")
	else
		PM:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	end
end

-- Accepts the exact return values of CombatLogGetCurrentEventInfo().
function API:FeedCLEU(...)
	PM:ParseCLEU(...)
end

--------------------------------------------------------------------------
-- Reading data
--------------------------------------------------------------------------
function API:GetCurrentSegment() return PM.current or PM.history[1] end
function API:GetOverallSegment() return PM.overall end
function API:GetHistory() return PM.history end
function API:GetSegment(sel) return PM:GetSegment(sel) end
function API:IsInCombat() return PM.inCombat and true or false end

-- Sorted list for any mode: returns array of {actor=..., value=...}, total
function API:GetRanking(segmentSel, modeKey)
	local seg = PM:GetSegment(segmentSel or "current")
	return PM:GetSortedActors(seg, modeKey or "damage")
end

-- Convenience single-actor lookup by name or GUID
function API:GetActor(segmentSel, nameOrGUID)
	local seg = PM:GetSegment(segmentSel or "current")
	if not seg then return end
	if seg.actors[nameOrGUID] then return seg.actors[nameOrGUID] end
	for _, a in pairs(seg.actors) do
		if a.name == nameOrGUID then return a end
	end
end

--------------------------------------------------------------------------
-- Callbacks
--   "SEGMENT_START"  (segment)
--   "SEGMENT_END"    (segment)
-- Usage:
--   PulseMeter.API:RegisterCallback("SEGMENT_END", function(msg, seg) ... end)
--------------------------------------------------------------------------
function API:RegisterCallback(message, fn)
	PM.callbacks[message] = PM.callbacks[message] or {}
	table.insert(PM.callbacks[message], fn)
end

function API:UnregisterCallback(message, fn)
	local list = PM.callbacks[message]
	if not list then return end
	for i = #list, 1, -1 do
		if list[i] == fn then table.remove(list, i) end
	end
end

--------------------------------------------------------------------------
-- Extending: register a custom mode from another addon.
--   PulseMeter.API:RegisterMode("myKey", {
--       name = "My Stat",
--       value = function(actor, segment) return actor.myStat or 0 end,
--       barText = function(actor, segment) return "text", nil end,
--       tooltip = function(gameTooltip, actor, segment) ... end,
--   })
-- Your addon can stamp custom fields onto actors from a SEGMENT_START
-- callback or by feeding events and mutating segment.actors[guid].
--------------------------------------------------------------------------
function API:RegisterMode(key, def)
	if PM.modes[key] then return false, "mode exists" end
	def.key = key
	PM.modes[key] = def
	PM.modeOrder[#PM.modeOrder + 1] = key
	return true
end

--------------------------------------------------------------------------
-- Window control from another addon
--------------------------------------------------------------------------
function API:SetWindowMode(index, modeKey)
	local w = PM.windows[index]
	if w and PM.modes[modeKey] then w:SetMode(modeKey) end
end

function API:ToggleWindows() PM:ToggleAllWindows() end
function API:ResetData() PM:ResetAll() end
