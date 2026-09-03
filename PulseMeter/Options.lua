-- PulseMeter Options.lua
-- Options panel: left tab rail, wide scrollable content with section
-- dividers, a live skin preview strip, and a global Test Mode toggle.

local ADDON, ns = ...
local PM = ns.PM

local panel
local CONTENT_W = 470

--------------------------------------------------------------------------
-- Widget factory
--------------------------------------------------------------------------
local W = {}

function W.header(parent, text, y)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetPoint("TOPLEFT", 14, y - 6)
	fs:SetText("|cff4db8ff" .. text .. "|r")
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(0.3, 0.3, 0.38, 0.8)
	line:SetPoint("TOPLEFT", 14, y - 24)
	line:SetPoint("TOPRIGHT", -20, y - 24)
	line:SetHeight(1)
	return y - 34
end

function W.check(parent, label, y, get, set, col)
	local x = col == 2 and (CONTENT_W / 2 + 8) or 14
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetPoint("TOPLEFT", x, y)
	cb:SetSize(20, 20)
	cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cb.text:SetPoint("LEFT", cb, "RIGHT", 3, 0)
	cb.text:SetWidth(CONTENT_W / 2 - 48)
	cb.text:SetJustifyH("LEFT")
	cb.text:SetWordWrap(false)
	cb.text:SetText(label)
	cb:SetChecked(get())
	cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
	return col == 2 and y or y, cb  -- caller advances y
end

-- two checkboxes side by side; advances y once
function W.checkRow(parent, y, a, b)
	W.check(parent, a[1], y, a[2], a[3], 1)
	if b then W.check(parent, b[1], y, b[2], b[3], 2) end
	return y - 22
end

function W.slider(parent, label, y, minV, maxV, step, get, set)
	local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
	s:SetPoint("TOPLEFT", 18, y - 16)
	s:SetWidth(200)
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	s:SetObeyStepOnDrag(true)
	if s.Low then s.Low:SetText("") end
	if s.High then s.High:SetText("") end
	if s.Text then s.Text:SetText("") end
	s.label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	s.label:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 3)
	local function updLabel(v)
		s.label:SetFormattedText("%s: |cff4db8ff%s|r", label, string.format(step < 1 and "%.2f" or "%d", v))
	end
	s:SetValue(get())
	updLabel(get())
	s:SetScript("OnValueChanged", function(self, v)
		updLabel(v)
		set(v)
	end)
	return y - 44, s
end

function W.dropdown(parent, label, y, options, get, set)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(200, 22)
	b:SetPoint("TOPLEFT", 18, y - 16)
	b.label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.label:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 0, 3)
	b.label:SetText(label)
	local function currentText()
		local cur = get()
		for _, o in ipairs(options()) do
			if o.value == cur then return o.text end
		end
		return "select..."
	end
	b:SetText(currentText())
	b:SetScript("OnClick", function()
		local items = {}
		for _, o in ipairs(options()) do
			items[#items + 1] = {
				text = o.text, checked = (o.value == get()),
				func = function() set(o.value); b:SetText(o.text) end,
			}
		end
		PM:ShowMenu(items)
	end)
	return y - 46, b
end

function W.color(parent, label, y, get, set)
	local sw = CreateFrame("Button", nil, parent, "BackdropTemplate")
	sw:SetSize(18, 18)
	sw:SetPoint("TOPLEFT", 18, y - 2)
	sw:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	sw:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
	local function paint()
		local c = get()
		sw:SetBackdropColor(c[1], c[2], c[3], 1)
	end
	paint()
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("LEFT", sw, "RIGHT", 6, 0)
	fs:SetText(label)
	sw:SetScript("OnClick", function()
		local c = get()
		local function apply()
			local r, g, b = ColorPickerFrame:GetColorRGB()
			local a = c[4] or 1
			if ColorPickerFrame.GetColorAlpha then
				a = ColorPickerFrame:GetColorAlpha()
			elseif OpacitySliderFrame then
				a = 1 - OpacitySliderFrame:GetValue()
			end
			set({ r, g, b, a })
			paint()
		end
		local info = {
			r = c[1], g = c[2], b = c[3], opacity = c[4] or 1, hasOpacity = true,
			swatchFunc = apply, opacityFunc = apply,
			cancelFunc = function(prev)
				if prev then set({ prev.r, prev.g, prev.b, prev.opacity or 1 }); paint() end
			end,
		}
		if ColorPickerFrame.SetupColorPickerAndShow then
			ColorPickerFrame:SetupColorPickerAndShow(info)
		else
			ColorPickerFrame.func = apply
			ColorPickerFrame.opacityFunc = apply
			ColorPickerFrame.hasOpacity = true
			ColorPickerFrame.opacity = 1 - (c[4] or 1)
			ColorPickerFrame.previousValues = { r = c[1], g = c[2], b = c[3], opacity = c[4] }
			ColorPickerFrame.cancelFunc = info.cancelFunc
			ColorPickerFrame:SetColorRGB(c[1], c[2], c[3])
			ColorPickerFrame:Show()
		end
	end)
	return y - 24, sw
end

function W.button(parent, label, y, func, width)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 180, 22)
	b:SetPoint("TOPLEFT", 14, y)
	b:SetText(label)
	b:SetScript("OnClick", func)
	return y - 26, b
end

--------------------------------------------------------------------------
-- Live preview strip: 3 sample bars drawn with the window's settings
--------------------------------------------------------------------------
local PREVIEW = {
	{ "Jabe", "ROGUE", 1.0, "184.2k (32.1%)" },
	{ "Kelthas", "MAGE", 0.78, "143.6k (25.0%)" },
	{ "Mira", "PRIEST", 0.55, "101.3k (17.7%)" },
}

local function buildPreview(parent, y, s)
	local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	box:SetPoint("TOPLEFT", 14, y)
	box:SetSize(CONTENT_W - 34, 0)
	box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
	box.bars = {}
	box.title = CreateFrame("Frame", nil, box, "BackdropTemplate")
	box.title:SetPoint("TOPLEFT"); box.title:SetPoint("TOPRIGHT")
	box.title:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
	box.title.text = box.title:CreateFontString(nil, "OVERLAY")
	box.title.text:SetPoint("LEFT", 6, 0)

	function box:Redraw()
		local font, size, outline = PM:GetFont(s.font), s.fontSize, s.fontOutline
		local tex = PM:GetTexture(s.texture)
		self:SetBackdropColor(unpack(s.bgColor))
		self.title:SetHeight(s.titleHeight)
		self.title:SetBackdropColor(unpack(s.titleColor))
		self.title.text:SetFont(font, size, outline)
		self.title.text:SetText("Damage: Preview")
		local h = s.titleHeight + 1
		for i, def in ipairs(PREVIEW) do
			local bar = self.bars[i]
			if not bar then
				bar = CreateFrame("StatusBar", nil, self)
				bar:SetMinMaxValues(0, 1)
				bar.left = bar:CreateFontString(nil, "OVERLAY")
				bar.left:SetPoint("LEFT", 4, 0)
				bar.right = bar:CreateFontString(nil, "OVERLAY")
				bar.right:SetPoint("RIGHT", -4, 0)
				self.bars[i] = bar
			end
			bar:ClearAllPoints()
			bar:SetPoint("TOPLEFT", 0, -h)
			bar:SetPoint("TOPRIGHT", 0, -h)
			bar:SetHeight(s.barHeight)
			bar:SetStatusBarTexture(tex)
			bar:SetValue(def[3])
			if s.classColors then
				bar:SetStatusBarColor(PM:ClassColor(def[2]))
			else
				bar:SetStatusBarColor(unpack(s.barColor))
			end
			bar.left:SetFont(font, size, outline)
			bar.right:SetFont(font, size, outline)
			bar.left:SetText((s.showRank and (i .. ". ") or "") .. def[1])
			bar.right:SetText((s.showValue and def[4]) or "")
			h = h + s.barHeight + s.barSpacing
		end
		self:SetHeight(h + 2)
	end
	box:Redraw()
	return y - box:GetHeight() - 14, box
end

--------------------------------------------------------------------------
-- Panel shell
--------------------------------------------------------------------------
local function buildPanel()
	panel = CreateFrame("Frame", "PulseMeterOptions", UIParent, "BackdropTemplate")
	panel:SetSize(680, 540)
	panel:SetPoint("CENTER")
	panel:SetFrameStrata("DIALOG")
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:SetClampedToScreen(true)
	panel:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
	})
	panel:SetBackdropColor(0.06, 0.06, 0.08, 0.97)
	panel:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
	panel:Hide()
	table.insert(UISpecialFrames, "PulseMeterOptions")

	local titleBar = CreateFrame("Frame", nil, panel)
	titleBar:SetPoint("TOPLEFT"); titleBar:SetPoint("TOPRIGHT")
	titleBar:SetHeight(30)
	titleBar:EnableMouse(true)
	titleBar:SetFrameLevel(panel:GetFrameLevel() + 1)
	titleBar:SetScript("OnMouseDown", function() panel:StartMoving() end)
	titleBar:SetScript("OnMouseUp", function() panel:StopMovingOrSizing() end)

	local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("LEFT", 14, 0)
	title:SetText("|cff4db8ffPulseMeter|r")

	-- global test mode toggle in the header, always reachable
	local test = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	test:SetSize(110, 20)
	test:SetPoint("TOPRIGHT", -30, -5)
	local function testLabel()
		test:SetText(PM.testMode and "Test Mode: ON" or "Test Mode: OFF")
	end
	testLabel()
	test:SetScript("OnClick", function()
		PM:SetTestMode(not PM.testMode)
		testLabel()
	end)
	test:SetFrameLevel(panel:GetFrameLevel() + 10) -- above the drag strip
	panel.testBtn = test

	local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 3)
	close:SetFrameLevel(panel:GetFrameLevel() + 10)

	-- tab rail
	local rail = CreateFrame("Frame", nil, panel, "BackdropTemplate")
	rail:SetPoint("TOPLEFT", 0, -30)
	rail:SetPoint("BOTTOMLEFT")
	rail:SetWidth(140)
	rail:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
	rail:SetBackdropColor(0.04, 0.04, 0.05, 1)
	if rail.SetClipsChildren then rail:SetClipsChildren(true) end
	panel.rail = rail
	panel.tabs = {}

	-- scrollable content
	local scroll = CreateFrame("ScrollFrame", "PulseMeterOptionsScroll", panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 142, -34)
	scroll:SetPoint("BOTTOMRIGHT", -28, 8)
	panel.scroll = scroll
end

local function freshContent()
	if panel.content then
		panel.content:Hide()
		panel.content:SetParent(nil)
	end
	local c = CreateFrame("Frame", nil, panel.scroll)
	c:SetSize(CONTENT_W, 400)
	panel.scroll:SetScrollChild(c)
	panel.content = c
	return c
end

--------------------------------------------------------------------------
-- Tabs
--------------------------------------------------------------------------
local activeTab = "general"
local function selectTab(id) activeTab = id; panel.Rebuild() end

local function buildTabs()
	for _, b in ipairs(panel.tabs) do b:Hide() end
	local n, y = 0, -8
	local function tab(id, text, indent)
		n = n + 1
		local b = panel.tabs[n]
		if not b then
			b = CreateFrame("Button", nil, panel.rail, "BackdropTemplate")
			b:SetSize(132, 21)
			b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
			b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			b.text:SetPoint("LEFT", 10, 0)
			b.text:SetPoint("RIGHT", -4, 0)
			b.text:SetJustifyH("LEFT")
			b.text:SetWordWrap(false)
			panel.tabs[n] = b
		end
		b:Show()
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 4, y)
		b.text:SetText((indent and "   " or "") .. text)
		local on = activeTab == id
		b:SetBackdropColor(on and 0.16 or 0.04, on and 0.30 or 0.04, on and 0.50 or 0.05, 1)
		b:SetScript("OnClick", function() selectTab(id) end)
		y = y - 23
	end
	tab("general", "General")
	tab("fights", "Fights & Segments")
	tab("edit", "Edit / Snapping")
	for i, s in ipairs(PM.db.windows) do
		tab("win" .. i, (s.isMini and "Mini " or "Window ") .. i .. "  |cff888888(" ..
			(PM.modes[s.mode] and PM.modes[s.mode].name or s.mode) .. ")|r", true)
	end
	tab("profiles", "Profiles")

	y = y - 10
	local function railBtn(key, label, fn)
		local b = panel[key]
		if not b then
			b = CreateFrame("Button", nil, panel.rail, "UIPanelButtonTemplate")
			b:SetSize(128, 20)
			b:SetText(label)
			b:SetScript("OnClick", fn)
			panel[key] = b
		end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 6, y)
		y = y - 23
	end
	railBtn("btnNewWin", "+ New Window", function()
		PM:CreateNewWindow(); selectTab("win" .. #PM.db.windows)
	end)
	railBtn("btnMiniD", "+ Mini: Deaths", function()
		PM:CreateMiniWindow("deaths"); selectTab("win" .. #PM.db.windows)
	end)
	railBtn("btnMiniI", "+ Mini: Interrupts", function()
		PM:CreateMiniWindow("interrupts"); selectTab("win" .. #PM.db.windows)
	end)
	railBtn("btnMiniDis", "+ Mini: Dispels", function()
		PM:CreateMiniWindow("dispels"); selectTab("win" .. #PM.db.windows)
	end)
	railBtn("btnBrowser", "Log Browser", function() PM:ToggleBrowser("deaths") end)
	railBtn("btnEdit", "Edit Mode", function() PM:ToggleEditMode() end)
end

--------------------------------------------------------------------------
-- Tab content
--------------------------------------------------------------------------
local function buildGeneral(c)
	local g = PM.db.general
	local y = -4
	y = W.header(c, "Tracking", y)
	y = W.checkRow(c, y,
		{ "Only track group members", function() return g.onlyGroup end, function(v) g.onlyGroup = v end },
		{ "Merge pets into owners", function() return g.mergePets end, function(v) g.mergePets = v end })
	y = y - 6
	y = W.header(c, "Data", y)
	y = W.dropdown(c, "Number format", y,
		function() return { { text = "Short (1.2k)", value = "short" }, { text = "Full (1234)", value = "full" } } end,
		function() return g.numberFormat end, function(v) g.numberFormat = v; PM:RefreshWindows(true) end)
	y = W.slider(c, "Update interval (sec)", y, 0.1, 2, 0.1,
		function() return g.updateInterval end, function(v) g.updateInterval = v end)
	y = W.slider(c, "Death log entries per death", y, 5, 30, 1,
		function() return g.deathLogSize end, function(v) g.deathLogSize = v end)
	y = y - 6
	y = W.header(c, "Actions", y)
	y = W.button(c, "Reset all data", y, function() PM:ResetAll() end)
	c:SetHeight(-y + 40)
end

local function buildFights(c)
	local g = PM.db.general
	local y = -4
	y = W.header(c, "When A Fight Ends", y)
	local fs = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", 14, y)
	fs:SetJustifyH("LEFT")
	fs:SetText("A fight closes when nobody in your group is still in combat.\n"
		.. "Raid chatter in the combat log no longer keeps it open, which is\n"
		.. "what used to glue several boss pulls into one segment.")
	y = y - 52

	y = W.slider(c, "Grace period after combat drops (sec)", y, 1, 15, 0.5,
		function() return g.combatGrace end, function(v) g.combatGrace = v end)
	y = W.slider(c, "Delay after the boss dies (sec)", y, 0, 10, 0.5,
		function() return g.bossEndDelay end, function(v) g.bossEndDelay = v end)
	y = W.slider(c, "Grace while you're dead on a boss (sec)", y, 5, 120, 5,
		function() return g.deadGrace end, function(v) g.deadGrace = v end)
	y = W.slider(c, "Hard cap on one fight (sec)", y, 120, 3600, 60,
		function() return g.maxFightLength end, function(v) g.maxFightLength = v end)
	y = W.slider(c, "Minimum fight length to keep (sec)", y, 0, 30, 1,
		function() return g.minFightLength end, function(v) g.minFightLength = v end)
	y = W.slider(c, "Fights kept in history", y, 5, 40, 1,
		function() return g.segmentHistory end, function(v) g.segmentHistory = v end)
	y = W.checkRow(c, y,
		{ "Close trash pulls instantly", function() return g.autoSplitTrash end,
			function(v) g.autoSplitTrash = v end })
	y = y - 4
	y = W.button(c, "End the current fight now", y, function() PM:SplitSegment() end, 210)

	y = y - 8
	y = W.header(c, "Saved Boss Fights", y)
	local A = PM.Archive
	local a = A.Settings()
	local info = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	info:SetPoint("TOPLEFT", 14, y)
	info:SetJustifyH("LEFT")
	info:SetText("Boss pulls are written to disk and kept until you delete them,\n"
		.. "no matter how many fights ago. Trash is never saved.\n"
		.. "|cff888888Stored: " .. #A.Fights() .. " fights, about " .. A.SizeText()
		.. ". Pinned fights are never pruned.|r")
	y = y - 52
	y = W.checkRow(c, y,
		{ "Save boss fights", function() return a.enabled end, function(v) a.enabled = v end },
		{ "Keep spell breakdowns", function() return a.spellDetail end, function(v) a.spellDetail = v end })
	y = W.checkRow(c, y,
		{ "Kills only (skip wipes)", function() return a.killsOnly end, function(v) a.killsOnly = v end },
		{ "Only while in a raid", function() return a.raidOnly end, function(v) a.raidOnly = v end })
	y = W.slider(c, "Fights kept before pruning", y, 10, 300, 10,
		function() return a.maxFights end, function(v) a.maxFights = v; A.Prune() end)
	y = W.slider(c, "Spells kept per player", y, 5, 40, 1,
		function() return a.maxSpells end, function(v) a.maxSpells = v end)
	y = W.button(c, "Open saved fights", y, function() PM:ToggleBrowser("saved") end, 210)
	y = W.button(c, "Delete all unpinned fights", y, function()
		A.Clear(true); panel.Rebuild()
	end, 210)

	y = y - 8
	y = W.header(c, "Log Lovers", y)
	local ll = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	ll:SetPoint("TOPLEFT", 14, y)
	ll:SetJustifyH("LEFT")
	if PM.LL then
		ll:SetText("Status: |cff4dff4d" .. (PM.llBridge or "linked") .. "|r\n"
			.. "Deaths come from Log Lovers' recap, and the window controls can\n"
			.. "open its combat log and stats browser directly.")
	else
		ll:SetText("|cff888888Log Lovers is not loaded. Install it alongside\n"
			.. "PulseMeter and the two share one combat log parse, one set of\n"
			.. "fight boundaries, and Log Lovers' richer death recaps.|r")
	end
	y = y - 54
	y = W.checkRow(c, y,
		{ "Share Log Lovers' combat log feed", function() return g.llBridge end,
			function(v) PM:SetLLBridge(v) end })
	if PM.LL then
		y = y - 4
		y = W.button(c, "Open Log Lovers death recaps", y, function() PM.LL.OpenDeaths() end, 210)
		y = W.button(c, "Open Log Lovers stats", y, function() PM.LL.OpenStats() end, 210)
	end
	c:SetHeight(-y + 40)
end

local function buildEdit(c)
	local e = PM.db.edit
	local y = -4
	y = W.header(c, "Edit Mode & Snapping", y)
	y = W.checkRow(c, y,
		{ "Magnetic snapping", function() return e.snap end, function(v) e.snap = v end },
		{ "Cyan alignment guides", function() return e.showGuides end, function(v) e.showGuides = v end })
	y = W.checkRow(c, y,
		{ "Grid overlay ('G' in edit mode)", function() return e.grid end, function(v) e.grid = v end })
	y = W.slider(c, "Snap distance (px)", y, 4, 30, 1,
		function() return e.snapDist end, function(v) e.snapDist = v end)
	y = W.slider(c, "Grid size (px)", y, 8, 128, 8,
		function() return e.gridSize end, function(v) e.gridSize = v end)
	y = y - 6
	y = W.header(c, "Docking", y)
	local d = PM.DockConfig()
	local fs = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", 14, y)
	fs:SetJustifyH("LEFT")
	fs:SetText("Drop a window against another and they dock. By default the child\ntakes the parent's size, so a snapped pair matches. These are the\ndefaults for new docks; each pair can override them in its panel.")
	y = y - 52
	y = W.checkRow(c, y,
		{ "New docks match width", function() return d.matchWidth end, function(v) d.matchWidth = v end },
		{ "New docks match height", function() return d.matchHeight end, function(v) d.matchHeight = v end })
	y = W.checkRow(c, y,
		{ "Open the dock panel on snap", function() return d.showPanel end, function(v) d.showPanel = v end })
	y = W.slider(c, "Default gap between docked windows (px)", y, 0, 20, 1,
		function() return d.gap end, function(v) d.gap = v end)
	y = W.button(c, "Open docking panel", y, function() PM:ToggleLayoutPanel() end, 210)
	c:SetHeight(-y + 40)
end

local function buildWindow(c, i)
	local s = PM.db.windows[i]
	if not s then return end
	local win = PM.windows[i]
	local preview
	local function apply()
		if win then win:ApplySettings() end
		if preview then preview:Redraw() end
	end

	local y = -4
	y = W.header(c, (s.isMini and "Mini Window " or "Window ") .. i, y)
	y, preview = buildPreview(c, y, s)

	y = W.dropdown(c, "Mode", y,
		function()
			local out = {}
			for _, key in ipairs(PM.modeOrder) do
				out[#out + 1] = { text = PM.modes[key].name, value = key }
			end
			return out
		end,
		function() return s.mode end, function(v) s.mode = v; apply() end)

	y = W.dropdown(c, "Segment", y,
		function()
			local out = { { text = "Current fight", value = "current" }, { text = "Overall", value = "overall" } }
			for hi = 1, math.min(#PM.history, 10) do
				out[#out + 1] = { text = hi .. ". " .. PM.history[hi].name, value = hi }
			end
			return out
		end,
		function() return s.segment end, function(v) s.segment = v; apply() end)

	y = y - 4
	y = W.header(c, "Skin", y)
	y = W.dropdown(c, "Apply a skin preset", y,
		function()
			local out = {}
			for pi, p in ipairs(PM.skinPresets) do out[#out + 1] = { text = p.name, value = pi } end
			return out
		end,
		function() return 0 end,
		function(v) if win then PM:ApplySkinPreset(win, v); if preview then preview:Redraw() end end end)

	y = W.dropdown(c, "Bar texture", y,
		function()
			local out = {}
			for name in pairs(PM.textures) do out[#out + 1] = { text = name, value = name } end
			table.sort(out, function(a, b) return a.text < b.text end)
			return out
		end,
		function() return s.texture end, function(v) s.texture = v; apply() end)

	y = W.dropdown(c, "Font", y,
		function()
			local out = {}
			for name in pairs(PM.fonts) do out[#out + 1] = { text = name, value = name } end
			table.sort(out, function(a, b) return a.text < b.text end)
			return out
		end,
		function() return s.font end, function(v) s.font = v; apply() end)

	y = W.slider(c, "Font size", y, 7, 20, 1,
		function() return s.fontSize end, function(v) s.fontSize = v; apply() end)
	y = W.slider(c, "Bar height", y, 8, 40, 1,
		function() return s.barHeight end, function(v) s.barHeight = v; apply() end)
	y = W.slider(c, "Bar spacing", y, 0, 10, 1,
		function() return s.barSpacing end, function(v) s.barSpacing = v; apply() end)
	y = W.slider(c, "Title bar height", y, 10, 30, 1,
		function() return s.titleHeight end, function(v) s.titleHeight = v; apply() end)
	y = W.slider(c, "Window scale", y, 0.5, 2, 0.05,
		function() return s.scale end, function(v) s.scale = v; apply() end)
	y = W.slider(c, "Opacity in combat", y, 0.1, 1, 0.05,
		function() return s.combatAlpha end, function(v) s.combatAlpha = v; s.alpha = v; apply() end)
	y = W.slider(c, "Opacity out of combat", y, 0.1, 1, 0.05,
		function() return s.oocAlpha end, function(v) s.oocAlpha = v end)

	y = W.color(c, "Background color", y,
		function() return s.bgColor end, function(v) s.bgColor = v; apply() end)
	y = W.color(c, "Title bar color", y,
		function() return s.titleColor end, function(v) s.titleColor = v; apply() end)
	y = W.color(c, "Bar color (when class colors off)", y,
		function() return s.barColor end, function(v) s.barColor = v; apply() end)

	y = y - 4
	y = W.header(c, "Elements", y)
	local rows = {
		{ { "Class colors", "classColors" }, { "Class icons", "showIcons" } },
		{ { "Title bar", "showTitle" }, { "Rank numbers", "showRank" } },
		{ { "Values", "showValue" }, { "Percent", "showPercent" } },
		{ { "Grow bars upward", "growUp" }, { "Locked", "locked" } },
		{ { "Click-through", "clickThrough" } },
	}
	for _, row in ipairs(rows) do
		local a, b = row[1], row[2]
		y = W.checkRow(c, y,
			{ a[1], function() return s[a[2]] end, function(v) s[a[2]] = v; apply() end },
			b and { b[1], function() return s[b[2]] end, function(v) s[b[2]] = v; apply() end } or nil)
	end

	y = y - 8
	if #PM.db.windows > 1 then
		y = W.button(c, "Delete this window", y, function()
			PM:DeleteWindow(i)
			selectTab("general")
		end)
	end
	c:SetHeight(-y + 40)
end

local function buildProfiles(c)
	local y = -4
	y = W.header(c, "Profiles", y)
	local fs = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", 14, y)
	fs:SetText("Active profile: |cffffffff" .. PM.profileName .. "|r")
	y = y - 24

	y = W.dropdown(c, "Switch to profile", y,
		function()
			local out = {}
			for _, name in ipairs(PM:ListProfiles()) do out[#out + 1] = { text = name, value = name } end
			return out
		end,
		function() return PM.profileName end,
		function(v) PM:SetProfile(v); panel.Rebuild() end)

	local lbl = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	lbl:SetPoint("TOPLEFT", 18, y - 4)
	lbl:SetText("New profile name:")
	local eb = CreateFrame("EditBox", nil, c, "InputBoxTemplate")
	eb:SetSize(180, 22)
	eb:SetPoint("TOPLEFT", 24, y - 20)
	eb:SetAutoFocus(false)
	y = y - 48
	y = W.button(c, "Create (copy current settings)", y, function()
		local name = eb:GetText()
		if name and name ~= "" then PM:SetProfile(name, true); panel.Rebuild() end
	end, 210)
	y = W.button(c, "Create empty", y, function()
		local name = eb:GetText()
		if name and name ~= "" then PM:SetProfile(name, false); panel.Rebuild() end
	end, 210)

	y = y - 8
	y = W.dropdown(c, "Delete profile", y,
		function()
			local out = {}
			for _, name in ipairs(PM:ListProfiles()) do
				if name ~= PM.profileName then out[#out + 1] = { text = name, value = name } end
			end
			return out
		end,
		function() return nil end,
		function(v) PM:DeleteProfile(v); panel.Rebuild() end)
	c:SetHeight(-y + 40)
end

--------------------------------------------------------------------------
-- Toggle
--------------------------------------------------------------------------
function PM:ToggleOptions(windowIndex)
	if not panel then
		buildPanel()
		panel.Rebuild = function()
			buildTabs()
			local c = freshContent()
			if activeTab == "general" then buildGeneral(c)
			elseif activeTab == "fights" then buildFights(c)
			elseif activeTab == "edit" then buildEdit(c)
			elseif activeTab == "profiles" then buildProfiles(c)
			else
				local i = tonumber(activeTab:match("^win(%d+)$"))
				if i and PM.db.windows[i] then buildWindow(c, i)
				else activeTab = "general"; buildGeneral(c) end
			end
			if panel.testBtn then
				panel.testBtn:SetText(PM.testMode and "Test Mode: ON" or "Test Mode: OFF")
			end
		end
	end
	if windowIndex then activeTab = "win" .. windowIndex end
	if panel:IsShown() and not windowIndex then
		panel:Hide()
	else
		panel.Rebuild()
		panel:Show()
	end
end
