-- PulseMeter LogLovers.lua
-- Bridge to the Log Lovers combat log addon (also by Jabe).
--
-- What this buys you when both addons are installed:
--
--  1. ONE combat log parse. Log Lovers already registers
--     COMBAT_LOG_EVENT_UNFILTERED and normalizes every event. We tap that
--     single stream instead of registering our own, so the log is read once
--     per event instead of twice.
--
--  2. Shared fight boundaries. Log Lovers segments on regen enable/disable,
--     which splits a boss fight the moment you personally drop combat.
--     PulseMeter's group-combat segmentation is stricter, so we stamp our
--     fight identity onto Log Lovers' segments and both addons agree on
--     what "this pull" means.
--
--  3. Death recaps come from Log Lovers. Its recap keeps full normalized
--     events, survives a reload, and knows the killing blow - strictly
--     better than our own ring buffer. When it's present, PulseMeter's
--     death browser lists its deaths and hands off to its recap window.
--
--  4. Cross-links both ways: PulseMeter's control panel can open the log
--     and the stats browser, and Log Lovers gets a PulseMeter.API handle.

local ADDON, ns = ...
local PM = ns.PM

local LL           -- the Log Lovers namespace once we find it
local Bridge = {}

--------------------------------------------------------------------------
-- Cross-links used by the control panel
--------------------------------------------------------------------------
function Bridge.OpenLog()
	if LL and LL.ShowWindow then pcall(LL.ShowWindow, 1) end
end

function Bridge.OpenStats()
	if LL and LL.ToggleStats then pcall(LL.ToggleStats) end
end

function Bridge.OpenDeaths()
	if LL and LL.ToggleDeaths then pcall(LL.ToggleDeaths) end
end

-- Open one specific death in Log Lovers' recap window.
function Bridge.OpenRecap(death)
	if not LL then return false end
	if death and LL.OpenDeathRecap then
		local ok = pcall(LL.OpenDeathRecap, death)
		if ok then return true end
	end
	if LL.ToggleDeaths then pcall(LL.ToggleDeaths) end
	return true
end

-- Most recent Log Lovers death record for a GUID, if any.
function Bridge.FindDeath(guid)
	if LL and LL.FindLastDeath then
		local ok, d = pcall(LL.FindLastDeath, guid)
		if ok then return d end
	end
end

--------------------------------------------------------------------------
-- Death list, grouped into PulseMeter's fights.
--
-- Log Lovers stamps deaths with the combat-log clock (epoch seconds) while
-- our segments run on GetTime(), so segments carry startStamp/endStamp to
-- make the two comparable.
--------------------------------------------------------------------------
-- Deaths cluster at the end of a pull - someone dies as the boss falls, or
-- during the grace period - and the combat-log clock only has one-second
-- resolution, so the window needs slack on both ends.
local MATCH_SLACK = 4

function Bridge.DeathsForSegment(seg, claimed)
	local out = {}
	if not (LL and LL.deaths and seg) then return out end
	local from = seg.startStamp
	local to = seg.endStamp or (time() + MATCH_SLACK)
	if not from then return out end
	for _, d in ipairs(LL.deaths) do
		if d.t and d.t >= from - MATCH_SLACK and d.t <= to + MATCH_SLACK and not d.feign then
			out[#out + 1] = d
			if claimed then claimed[d] = true end
		end
	end
	return out
end

-- Anything the fights did not claim still has to be reachable, or a death
-- lands in a gap between segments and silently disappears from the browser.
function Bridge.UnclaimedDeaths(claimed)
	local out = {}
	if not (LL and LL.deaths) then return out end
	for _, d in ipairs(LL.deaths) do
		if not d.feign and not (claimed and claimed[d]) then out[#out + 1] = d end
	end
	return out
end

function Bridge.HasDeaths()
	return LL and LL.deaths and #LL.deaths > 0
end

-- One-line summary for a death row: who killed them and with what.
function Bridge.DeathSummary(d)
	if not (LL and LL.DeathKiller) then return "" end
	local ok, killer, rec = pcall(LL.DeathKiller, d)
	if not ok or not killer then return "" end
	local spell = rec and (rec.sname or rec.env)
	if spell then return killer .. " - " .. spell end
	return killer
end

--------------------------------------------------------------------------
-- Single-parse feed
--------------------------------------------------------------------------
local function attachFeed()
	if PM.llFeedHooked or not LL or type(LL.HandleCLEU) ~= "function" then return end
	if not PM.db.general.llBridge then return end
	if PM.db.general.externalFeed then return end   -- someone else already owns the feed

	local orig = LL.HandleCLEU
	LL.HandleCLEU = function(...)
		-- Log Lovers first: it owns the event, we're the guest. A failure on
		-- either side must not stop the other from seeing the event.
		local ok, err = pcall(orig, ...)
		if not ok then geterrorhandler()(err) end

		if PM.llFeedDisabled then return end
		local ok2, err2 = pcall(PM.ParseCLEU, PM, ...)
		if not ok2 then
			PM.stats.errors = PM.stats.errors + 1
			if PM.stats.errors <= 3 then
				PM:Print("|cffff4d4dparser error:|r " .. tostring(err2))
			end
		end
	end

	PM.llFeedHooked = true
	PM:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	PM.llBridge = "active (shared combat log feed)"
end

local function detachFeed()
	-- we cannot cleanly unwrap, so just take our own registration back and
	-- let the wrapper no-op via the flag
	PM.llFeedDisabled = true
	PM:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	PM.llBridge = "off (PulseMeter reads the log itself)"
end

--------------------------------------------------------------------------
-- Fight boundary sharing
--------------------------------------------------------------------------
local function shareSegments()
	if not LL or not LL.On then return end

	-- when PulseMeter opens a fight, remember which Log Lovers segment it
	-- lines up with so both addons can talk about the same pull
	PM.API:RegisterCallback("SEGMENT_START", function(_, seg)
		local cur = LL.currentSegment
		if cur then
			seg.llSegIndex = cur.index
			seg.zone = cur.zone
		end
	end)

	PM.API:RegisterCallback("SEGMENT_END", function(_, seg)
		-- give unnamed trash pulls the zone Log Lovers already knows about
		if seg and not seg.enemy and seg.zone and seg.zone ~= "" then
			seg.name = "Trash - " .. seg.zone
		end
	end)
end

--------------------------------------------------------------------------
-- Hand our API to Log Lovers so it can show live meter data if it wants
--------------------------------------------------------------------------
local function publishAPI()
	if not LL then return end
	LL.PulseMeter = PM.API
end

--------------------------------------------------------------------------
-- Wiring
--------------------------------------------------------------------------
local function tryBridge()
	if LL then return end
	LL = _G.LogLovers
	if not LL then
		PM.llBridge = "not detected"
		return
	end
	PM.LL = Bridge
	Bridge.NS = LL
	publishAPI()
	shareSegments()
	attachFeed()
	if not PM.llFeedHooked then
		PM.llBridge = "linked (separate feeds)"
	end
end

function PM:SetLLBridge(on)
	self.db.general.llBridge = on and true or false
	if on then
		tryBridge()
		if self.llFeedHooked then
			self.llFeedDisabled = false
			self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
			self.llBridge = "active (shared combat log feed)"
		end
		self:Print("Log Lovers bridge |cff4dff4dON|r.")
	else
		detachFeed()
		self:Print("Log Lovers bridge |cffff4d4dOFF|r - PulseMeter reads the combat log on its own.")
	end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" and name ~= "LogLovers" then return end
	if not PM.db then return end   -- our own DB is not up yet; PLAYER_LOGIN will retry
	tryBridge()
	if event == "PLAYER_LOGIN" and LL then
		PM:Print("Log Lovers detected - " .. (PM.llBridge or "linked")
			.. ". Death recaps and the combat log are one click away in the window controls.")
	end
end)
