-- PulseMeter Browser.lua
-- The log browser: Deaths | Interrupts | Dispels tabs.
-- Left pane: fights grouped by boss (see Bosses.lua) with a Trash bucket
-- for everything else. Right pane: the detailed log.

local ADDON, ns = ...
local PM = ns.PM
local BOSSES = ns.BOSSES

local browser

--------------------------------------------------------------------------
-- Data assembly
--------------------------------------------------------------------------
-- Returns ordered groups: { name, isTrash, segs = { seg, ... } }
local function collectGroups()
	local groups, trash = {}, { name = "Trash", isTrash = true, segs = {} }
	local function addSeg(seg)
		if not seg then return end
		local enemy = seg.enemy
		if enemy and BOSSES[enemy] then
			groups[#groups + 1] = { name = seg.name, segs = { seg } }
		else
			table.insert(trash.segs, seg)
		end
	end
	addSeg(PM.testMode and PM.testSegment or PM.current)
	if not PM.testMode then
		for _, seg in ipairs(PM.history) do addSeg(seg) end
	end
	if #trash.segs > 0 then groups[#groups + 1] = trash end
	return groups
end

local function fmtClock(sec)
	sec = math.max(sec or 0, 0)
	return string.format("%d:%02d", math.floor(sec / 60), math.floor(sec % 60))
end

--------------------------------------------------------------------------
-- UI shell
--------------------------------------------------------------------------
local function buildBrowser()
	browser = CreateFrame("Frame", "PulseMeterBrowser", UIParent, "BackdropTemplate")
	browser:SetSize(640, 420)
	browser:SetPoint("CENTER")
	browser:SetFrameStrata("HIGH")
	browser:SetMovable(true)
	browser:EnableMouse(true)
	browser:SetClampedToScreen(true)
	browser:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
	})
	browser:SetBackdropColor(0.06, 0.06, 0.08, 0.97)
	browser:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
	browser:Hide()
	table.insert(UISpecialFrames, "PulseMeterBrowser")

	local titleBar = CreateFrame("Frame", nil, browser)
	titleBar:SetPoint("TOPLEFT"); titleBar:SetPoint("TOPRIGHT")
	titleBar:SetHeight(26)
	titleBar:EnableMouse(true)
	titleBar:SetFrameLevel(browser:GetFrameLevel() + 1)
	titleBar:SetScript("OnMouseDown", function() browser:StartMoving() end)
	titleBar:SetScript("OnMouseUp", function() browser:StopMovingOrSizing() end)

	browser.titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	browser.titleText:SetPoint("LEFT", 10, 0)
	browser.titleText:SetText("|cff4db8ffPulseMeter|r Log Browser")
	browser.sourceText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	browser.sourceText:SetPoint("LEFT", browser.titleText, "RIGHT", 10, 0)

	local close = CreateFrame("Button", nil, browser, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 3)
	close:SetFrameLevel(browser:GetFrameLevel() + 10)

	-- tabs
	browser.tabs = {}
	local tabDefs = { { "deaths", "Deaths" }, { "interrupts", "Interrupts" },
		{ "dispels", "Dispels" }, { "saved", "Saved Fights" } }
	for i, def in ipairs(tabDefs) do
		local t = CreateFrame("Button", nil, browser, "BackdropTemplate")
		t:SetSize(96, 20)
		t:SetPoint("TOPLEFT", 8 + (i - 1) * 100, -26)
		t:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
		t.text = t:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		t.text:SetPoint("CENTER")
		t.text:SetText(def[2])
		t.tabKey = def[1]
		t:SetScript("OnClick", function()
			browser.activeTab = def[1]
			browser.selected = nil
			browser.selectedFight = nil
			browser.Rebuild()
		end)
		browser.tabs[i] = t
	end

	-- left list
	local leftScroll = CreateFrame("ScrollFrame", "PulseMeterBrowserLeft", browser, "UIPanelScrollFrameTemplate")
	leftScroll:SetPoint("TOPLEFT", 8, -52)
	leftScroll:SetPoint("BOTTOMLEFT", 8, 8)
	leftScroll:SetWidth(210)
	local leftChild = CreateFrame("Frame", nil, leftScroll)
	leftChild:SetSize(210, 10)
	leftScroll:SetScrollChild(leftChild)
	browser.leftChild = leftChild
	browser.leftRows = {}

	-- right pane
	local rightBG = CreateFrame("Frame", nil, browser, "BackdropTemplate")
	rightBG:SetPoint("TOPLEFT", 246, -52)
	rightBG:SetPoint("BOTTOMRIGHT", -8, 8)
	rightBG:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
	rightBG:SetBackdropColor(0, 0, 0, 0.35)

	local rightScroll = CreateFrame("ScrollFrame", "PulseMeterBrowserRight", browser, "UIPanelScrollFrameTemplate")
	rightScroll:SetPoint("TOPLEFT", rightBG, 6, -6)
	rightScroll:SetPoint("BOTTOMRIGHT", rightBG, -26, 6)
	local rightChild = CreateFrame("Frame", nil, rightScroll)
	rightChild:SetSize(340, 10)
	rightScroll:SetScrollChild(rightChild)
	browser.rightChild = rightChild
	browser.rightLines = {}
	browser.rightBG = rightBG
	browser.rightScroll = rightScroll

	-- actions that operate on the selected saved fight
	local bar = CreateFrame("Frame", nil, browser)
	bar:SetPoint("BOTTOMLEFT", rightBG, "BOTTOMLEFT", 6, 6)
	bar:SetPoint("BOTTOMRIGHT", rightBG, "BOTTOMRIGHT", -6, 6)
	bar:SetHeight(22)
	bar:SetFrameLevel(browser:GetFrameLevel() + 8)
	bar:Hide()
	browser.actionBar = bar

	local function mkBtn(label, x, w, fn)
		local b = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
		b:SetSize(w, 21)
		b:SetPoint("LEFT", x, 0)
		b:SetText(label)
		b:SetScript("OnClick", fn)
		return b
	end
	bar.load = mkBtn("Show in Window", 0, 118, function()
		if browser.selectedFight then PM:LoadArchivedFight(browser.selectedFight.id) end
	end)
	bar.pin = mkBtn("Pin", 122, 62, function()
		if browser.selectedFight then
			PM.Archive.TogglePin(browser.selectedFight.id)
			browser.Rebuild()
		end
	end)
	bar.del = mkBtn("Delete", 188, 62, function()
		if browser.selectedFight then
			PM.Archive.Delete(browser.selectedFight.id)
			browser.selectedFight, browser.selected = nil, nil
			browser.Rebuild()
		end
	end)
end

-- The action bar eats space at the bottom of the right pane, so the scroll
-- frame has to give that space back on the tabs where the bar is hidden.
local function setActionBar(show)
	if not browser.actionBar then return end
	browser.actionBar:SetShown(show and browser.selectedFight ~= nil)
	browser.rightScroll:ClearAllPoints()
	browser.rightScroll:SetPoint("TOPLEFT", browser.rightBG, 6, -6)
	browser.rightScroll:SetPoint("BOTTOMRIGHT", browser.rightBG, -26,
		(show and browser.selectedFight) and 32 or 6)
end

--------------------------------------------------------------------------
-- Row / line pools
--------------------------------------------------------------------------
local function leftRow(i)
	local r = browser.leftRows[i]
	if not r then
		r = CreateFrame("Button", nil, browser.leftChild, "BackdropTemplate")
		r:SetHeight(17)
		r:SetPoint("LEFT"); r:SetPoint("RIGHT")
		r:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
		r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		r.text:SetPoint("LEFT", 6, 0)
		r.text:SetPoint("RIGHT", -4, 0)
		r.text:SetJustifyH("LEFT")
		r.hl = r:CreateTexture(nil, "HIGHLIGHT")
		r.hl:SetAllPoints()
		r.hl:SetColorTexture(0.3, 0.5, 0.9, 0.25)
		browser.leftRows[i] = r
	end
	return r
end

local function rightLine(i)
	local fs = browser.rightLines[i]
	if not fs then
		fs = browser.rightChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("LEFT", 2, 0)
		fs:SetPoint("RIGHT", -2, 0)
		fs:SetJustifyH("LEFT")
		browser.rightLines[i] = fs
	end
	return fs
end

local function setRightLines(lines)
	for i, line in ipairs(lines) do
		local fs = rightLine(i)
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", 2, -(i - 1) * 15)
		fs:SetPoint("RIGHT", -2, 0)
		fs:SetText(line)
		fs:Show()
	end
	for i = #lines + 1, #browser.rightLines do browser.rightLines[i]:Hide() end
	browser.rightChild:SetHeight(#lines * 15 + 10)
end

--------------------------------------------------------------------------
-- Right pane renderers
--------------------------------------------------------------------------
local function renderDeath(entry)
	-- entry = { player, class, seg, ev }
	local lines = {}
	local cr, cg, cb = PM:ClassColor(entry.class)
	local hex = string.format("|cff%02x%02x%02x", cr * 255, cg * 255, cb * 255)
	lines[#lines + 1] = hex .. entry.player .. "|r died - " .. entry.seg.name
	lines[#lines + 1] = " "
	for _, e in ipairs(entry.ev.log) do
		local delta = string.format("|cff888888-%4.1fs|r", entry.ev.time - e.t)
		local amt
		if e.heal then
			amt = "|cff4dff4d+" .. PM:FormatNumber(e.amount) .. "|r"
		else
			amt = "|cffff4d4d-" .. PM:FormatNumber(e.amount) .. "|r"
		end
		local hp = ""
		if e.hpMax and e.hpMax > 0 then
			hp = string.format("  |cffaaaaaa(%d%% hp)|r", e.hp / e.hpMax * 100)
		end
		lines[#lines + 1] = delta .. "  " .. amt .. "  " .. e.text .. hp
	end
	setRightLines(lines)
end

-- Log Lovers keeps a far richer recap than our own ring buffer, so when it is
-- installed we show its timeline and hand off to its window for the full view.
local function renderLLDeath(entry)
	local lines = {}
	local d = entry.ll
	local cr, cg, cb = PM:ClassColor(entry.class)
	local hex = string.format("|cff%02x%02x%02x", cr * 255, cg * 255, cb * 255)
	lines[#lines + 1] = hex .. (d.name or "?") .. "|r died - "
		.. ((entry.seg and entry.seg.name) or "Unknown fight")
	local killer = PM.LL and PM.LL.DeathSummary(d)
	if killer and killer ~= "" then
		lines[#lines + 1] = "|cffff8080Killing blow:|r " .. killer
	end
	lines[#lines + 1] = " "
	local text = ""
	if PM.LL and PM.LL.NS and PM.LL.NS.DeathRecapText then
		local ok, t = pcall(PM.LL.NS.DeathRecapText, d)
		if ok and t then text = t end
	end
	if text ~= "" then
		for line in tostring(text):gmatch("[^\n]+") do
			lines[#lines + 1] = line
		end
	else
		lines[#lines + 1] = "|cff888888No timeline recorded.|r"
	end
	lines[#lines + 1] = " "
	lines[#lines + 1] = "|cff4db8ffClick this death again to open the full Log Lovers recap.|r"
	setRightLines(lines)
end

local function renderSavedFight(entry)
	browser.selectedFight = entry
	local lines = {}
	local seg = PM.Archive.Restore(entry)
	lines[#lines + 1] = "|cffffd100" .. (entry.name or "?") .. "|r  "
		.. (entry.kill and "|cff4dff88KILL|r" or "|cffff6666WIPE|r")
		.. (entry.pin and "  |cff4db8ff[pinned]|r" or "")
	lines[#lines + 1] = "|cff888888" .. (entry.zone or "?") .. "  -  "
		.. date("%b %d %Y  %H:%M", entry.date or time())
		.. "  -  " .. PM.Archive.Duration(entry) .. "|r"
	if entry.char then
		lines[#lines + 1] = "|cff888888recorded by " .. entry.char
			.. (entry.size and entry.size > 0 and ("  -  " .. entry.size .. " players") or "") .. "|r"
	end
	lines[#lines + 1] = " "

	local function topList(title, modeKey, n)
		local list, total = PM:GetSortedActors(seg, modeKey)
		if #list == 0 then return end
		lines[#lines + 1] = "|cff4db8ff" .. title .. "|r  |cff888888("
			.. PM:FormatNumber(total) .. " total)|r"
		for i = 1, math.min(n, #list) do
			local e = list[i]
			local cr, cg, cb = PM:ClassColor(e.actor.class)
			local hex = string.format("|cff%02x%02x%02x", cr * 255, cg * 255, cb * 255)
			local perSec = (seg.endTime or 1) > 0 and (e.value / math.max(seg.endTime, 1)) or 0
			lines[#lines + 1] = string.format("  %d. %s%s|r   %s   |cff888888%s/s|r",
				i, hex, e.actor.name, PM:FormatNumber(e.value), PM:FormatNumber(perSec))
		end
		lines[#lines + 1] = " "
	end
	topList("Damage", "damage", 8)
	topList("Healing", "healing", 5)

	if entry.deaths and #entry.deaths > 0 then
		lines[#lines + 1] = "|cffff6666Deaths (" .. #entry.deaths .. ")|r"
		for _, d in ipairs(entry.deaths) do
			lines[#lines + 1] = string.format("  |cff888888%s|r  %s   |cff888888%s|r",
				fmtClock(d[2]), d[1], d[3] or "")
		end
		lines[#lines + 1] = " "
	end
	if entry.il and #entry.il > 0 then
		lines[#lines + 1] = "|cff4db8ffInterrupts (" .. #entry.il .. ")|r"
		for i = 1, math.min(#entry.il, 12) do
			local e = entry.il[i]
			lines[#lines + 1] = string.format("  |cff888888%s|r  %s interrupted %s",
				fmtClock(e[1]), e[2], e[4])
		end
	end
	setRightLines(lines)
end

local function renderEventLog(group, key, verb)
	-- key = "intLog"/"dispelLog"; verb formats a line
	local lines = {}
	local any = false
	for _, seg in ipairs(group.segs) do
		local log = seg[key]
		if log and #log > 0 then
			any = true
			if #group.segs > 1 then
				lines[#lines + 1] = "|cffffd100" .. seg.name .. "|r"
			end
			for _, e in ipairs(log) do
				lines[#lines + 1] = string.format("|cff888888%s|r  %s", fmtClock(e.t), verb(e))
			end
			lines[#lines + 1] = " "
		end
	end
	if not any then lines[1] = "|cff888888Nothing recorded.|r" end
	setRightLines(lines)
end

--------------------------------------------------------------------------
-- Rebuild
--------------------------------------------------------------------------
local function rebuild()
	-- tab highlight
	for _, t in ipairs(browser.tabs) do
		if t.tabKey == browser.activeTab then
			t:SetBackdropColor(0.2, 0.35, 0.55, 1)
		else
			t:SetBackdropColor(0.1, 0.1, 0.12, 1)
		end
	end

	if browser.sourceText then
		if browser.activeTab == "saved" then
			browser.sourceText:SetText(#PM.Archive.Fights() .. " fights, ~" .. PM.Archive.SizeText())
		else
			browser.sourceText:SetText(PM.LL and PM.LL.HasDeaths()
				and "deaths from Log Lovers" or "")
		end
	end

	local groups = collectGroups()
	local rows = {}   -- { header=?, text=..., onClick=? }

	setActionBar(browser.activeTab == "saved")

	if browser.activeTab == "saved" then
		local groupsA = PM.Archive.Groups()
		for _, g in ipairs(groupsA) do
			rows[#rows + 1] = { header = true, text = g.name .. "  (" .. #g.fights .. ")" }
			for _, f in ipairs(g.fights) do
				local mark = f.kill and "|cff4dff88+|r" or "|cffff6666x|r"
				rows[#rows + 1] = {
					text = mark .. " " .. (f.pin and "|cff4db8ff*|r" or "") .. (f.name or "?")
						.. "  |cff888888" .. PM.Archive.Duration(f) .. "|r",
					onClick = function() renderSavedFight(f) end,
				}
			end
		end
		if #rows == 0 then
			rows[1] = { header = true, text = "No boss fights saved yet" }
			browser.selectedFight = nil
			setRightLines({
				"|cff888888Every boss pull is saved here automatically and kept",
				"until you delete it - across logouts, across leaving the raid.|r",
				" ",
				"|cff888888Trash is never archived. Pinned fights are never pruned.|r",
			})
			browser.selected = -1
		end
	elseif browser.activeTab == "deaths" then
		local useLL = PM.LL and PM.LL.HasDeaths()
		local claimed = useLL and {} or nil
		for _, group in ipairs(groups) do
			local deaths = {}
			for _, seg in ipairs(group.segs) do
				if useLL then
					for _, d in ipairs(PM.LL.DeathsForSegment(seg, claimed)) do
						local class
						for _, a in pairs(seg.actors) do
							if a.name == d.name then class = a.class break end
						end
						deaths[#deaths + 1] = {
							ll = d, player = d.name or "?", class = class,
							seg = seg, when = (d.t or 0) - (seg.startStamp or 0),
						}
					end
				else
					for _, a in pairs(seg.actors) do
						if a.deathEvents then
							for _, ev in ipairs(a.deathEvents) do
								deaths[#deaths + 1] = {
									player = a.name, class = a.class, seg = seg, ev = ev,
									when = ev.time - seg.startTime,
								}
							end
						end
					end
				end
			end
			if #deaths > 0 then
				rows[#rows + 1] = { header = true, text = group.name .. "  (" .. #deaths .. ")" }
				table.sort(deaths, function(x, y) return (x.when or 0) < (y.when or 0) end)
				for _, d in ipairs(deaths) do
					rows[#rows + 1] = {
						text = d.player .. "  |cff888888" .. fmtClock(d.when) .. "|r",
						entry = d,
						onClick = function()
							if d.ll then
								-- second click on an already selected death opens
								-- the full Log Lovers recap window
								if browser.lastDeath == d.ll then
									PM.LL.OpenRecap(d.ll)
								end
								browser.lastDeath = d.ll
								renderLLDeath(d)
							else
								browser.lastDeath = nil
								renderDeath(d)
							end
						end,
					}
				end
			end
		end
		if useLL then
			local leftover = PM.LL.UnclaimedDeaths(claimed)
			if #leftover > 0 then
				rows[#rows + 1] = { header = true, text = "Other deaths  (" .. #leftover .. ")" }
				table.sort(leftover, function(x, y) return (x.t or 0) < (y.t or 0) end)
				for _, d in ipairs(leftover) do
					local entry = { ll = d, player = d.name or "?", seg = { name = "Outside a tracked fight" } }
					rows[#rows + 1] = {
						text = (d.name or "?") .. "  |cff888888" .. date("%H:%M", d.t or time()) .. "|r",
						entry = entry,
						onClick = function()
							if browser.lastDeath == d then PM.LL.OpenRecap(d) end
							browser.lastDeath = d
							renderLLDeath(entry)
						end,
					}
				end
			end
		end
		if #rows == 0 then
			rows[1] = { header = true, text = "No deaths recorded" }
		end
	else
		local key = browser.activeTab == "interrupts" and "intLog" or "dispelLog"
		local verb
		if browser.activeTab == "interrupts" then
			verb = function(e) return string.format("|cffffffff%s|r interrupted %s's |cff4db8ff%s|r", e.src, e.dst, e.spell) end
		else
			verb = function(e) return string.format("|cffffffff%s|r dispelled |cff4db8ff%s|r on %s", e.src, e.aura, e.dst) end
		end
		for _, group in ipairs(groups) do
			local n = 0
			for _, seg in ipairs(group.segs) do n = n + #(seg[key] or {}) end
			rows[#rows + 1] = {
				text = group.name .. "  |cff888888(" .. n .. ")|r",
				onClick = function() renderEventLog(group, key, verb) end,
			}
		end
		if #rows == 0 then rows[1] = { header = true, text = "No fights recorded" } end
	end

	-- render left rows
	for i, row in ipairs(rows) do
		local r = leftRow(i)
		r:Show()
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", 0, -(i - 1) * 18)
		r:SetPoint("RIGHT")
		if row.header then
			r.text:SetText("|cffffd100" .. row.text .. "|r")
			r:SetBackdropColor(0.12, 0.12, 0.16, 1)
			r:SetScript("OnClick", nil)
			r.hl:Hide()
		else
			r.text:SetText(row.text)
			r:SetBackdropColor(0, 0, 0, 0.25)
			r:SetScript("OnClick", function()
				browser.selected = i
				if row.onClick then row.onClick() end
				rebuild()
			end)
			r.hl:Show()
			if browser.selected == i then
				r:SetBackdropColor(0.2, 0.35, 0.55, 0.9)
			end
		end
	end
	for i = #rows + 1, #browser.leftRows do browser.leftRows[i]:Hide() end
	browser.leftChild:SetHeight(#rows * 18 + 10)

	-- auto-select first clickable row if nothing selected
	if not browser.selected then
		for i, row in ipairs(rows) do
			if row.onClick then
				browser.selected = i
				row.onClick()
				-- re-highlight without infinite recursion
				local r = leftRow(i)
				r:SetBackdropColor(0.2, 0.35, 0.55, 0.9)
				break
			end
		end
		if not browser.selected then setRightLines({ "|cff888888Nothing to show yet.|r" }) end
	end

	setActionBar(browser.activeTab == "saved")
end

--------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------
function PM:ToggleBrowser(tab, forceShow)
	if not browser then
		buildBrowser()
		browser.Rebuild = rebuild
		browser.activeTab = "deaths"
	end
	if tab then browser.activeTab = tab end
	if browser:IsShown() and not forceShow and not tab then
		browser:Hide()
	else
		browser.selected = nil
		rebuild()
		browser:Show()
	end
end
