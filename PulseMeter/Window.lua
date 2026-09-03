-- PulseMeter Window.lua
-- Meter windows.
--
-- Navigation model (deliberately NOT Details-style):
--   * The title bar has three hit zones - mode (left), fight (right), menu.
--     Each highlights on hover, so what is clickable is obvious.
--   * Everything else lives in ONE pop-up control panel. No tiny toolbar
--     icons, no cascading right-click menus, no working inside the window.
--   * Left-click a bar to drill in, right-click to come back out.

local ADDON, ns = ...
local PM = ns.PM

local WindowProto = {}

-- compact labels for the control panel's mode grid
local SHORT = {
	damage = "Damage", dps = "DPS", healing = "Healing", overhealing = "Overheal",
	absorbs = "Absorbs", healingPlusAbsorbs = "Heal+Abs", damageTaken = "Taken",
	friendlyFire = "Friendly Fire", deaths = "Deaths", interrupts = "Interrupts",
	dispels = "Dispels", ccBreaks = "CC Breaks",
}
local function shortName(key)
	return SHORT[key] or (PM.modes[key] and PM.modes[key].name) or key
end

--------------------------------------------------------------------------
-- Small generic menu (still used by dropdowns in the options panel).
-- Grows upward when the cursor sits low on the screen.
--------------------------------------------------------------------------
local menu = CreateFrame("Frame", "PulseMeterMenu", UIParent, "BackdropTemplate")
menu:SetFrameStrata("FULLSCREEN_DIALOG")
menu:SetBackdrop({
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
})
menu:SetBackdropColor(0.07, 0.07, 0.09, 0.97)
menu:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
menu:Hide()
menu.buttons = {}

local function menuButton(i)
	local b = menu.buttons[i]
	if not b then
		b = CreateFrame("Button", nil, menu)
		b:SetHeight(18)
		b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.text:SetPoint("LEFT", 8, 0)
		b.hl = b:CreateTexture(nil, "HIGHLIGHT")
		b.hl:SetAllPoints()
		b.hl:SetColorTexture(0.3, 0.5, 0.9, 0.35)
		b:SetScript("OnClick", function(self)
			if self.func then self.func() end
			if not self.keepOpen then menu:Hide() end
		end)
		menu.buttons[i] = b
	end
	return b
end

function PM:ShowMenu(items)
	local width = 140
	for i, item in ipairs(items) do
		local b = menuButton(i)
		b:Show()
		if item.title then
			b.text:SetText("|cffffd100" .. item.text .. "|r")
			b.func = nil; b.hl:Hide()
		else
			b.text:SetText((item.checked and "|cff4db8ff> |r" or "  ") .. item.text)
			b.func = item.func
			b.keepOpen = item.keepOpen
			b.hl:Show()
		end
		local w = b.text:GetStringWidth() + 24
		if w > width then width = w end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 2, -2 - (i - 1) * 18)
		b:SetPoint("RIGHT", -2, 0)
	end
	for i = #items + 1, #menu.buttons do menu.buttons[i]:Hide() end

	local h = #items * 18 + 4
	menu:SetSize(width, h)
	menu:ClearAllPoints()
	local scale = UIParent:GetEffectiveScale()
	local x, y = GetCursorPosition()
	x, y = x / scale, y / scale
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	if x + width > sw - 4 then x = sw - width - 4 end
	if x < 4 then x = 4 end
	if y - h < 4 then
		if y + h > sh - 4 then y = sh - h - 4 end
		menu:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
	else
		menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
	end
	menu:Show()
end

menu:SetScript("OnUpdate", function(self)
	if IsMouseButtonDown() and not self:IsMouseOver() then self:Hide() end
end)

--------------------------------------------------------------------------
-- Icon primitives.
--
-- Every icon in this addon is drawn from WHITE8x8 rectangles rather than font
-- characters, because the client's default font has no glyphs for arrows,
-- boxes or gears and renders them as an empty square.
--------------------------------------------------------------------------
local function px(b, layer)
	local t = b:CreateTexture(nil, layer or "OVERLAY")
	t:SetColorTexture(1, 1, 1, 1)
	t:SetVertexColor(0.80, 0.84, 0.90)
	b.parts = b.parts or {}
	b.parts[#b.parts + 1] = t
	return t
end

-- Two offset boxes: the classic "opens in its own window" mark.
local function drawPopOut(b, size)
	b.parts = b.parts or {}
	for _, t in ipairs(b.parts) do t:Hide() end
	local n = 0
	local function bar(w, h, x, y)
		n = n + 1
		local t = b.parts[n] or px(b)
		t:Show(); t:ClearAllPoints()
		t:SetSize(w, h)
		t:SetPoint("CENTER", b, "CENTER", x, y)
	end
	local s = math.max(7, math.floor(size * 0.66))
	local half, off = s / 2, math.max(1, math.floor(s * 0.24))
	bar(s, 1, -off, -half - off)          -- outline: bottom
	bar(s, 1, -off,  half - off)          -- outline: top
	bar(1, s, -half - off, -off)          -- outline: left
	bar(1, s,  half - off, -off)          -- outline: right
	local f = math.max(3, math.floor(s * 0.5))
	bar(f, f, half - off + 1, half - off + 1)   -- the popped-out window
end

--------------------------------------------------------------------------
-- CONTROL PANEL
-- One pop-up that does everything: pick a mode, pick a fight, run actions.
-- Big targets, always the same layout, stays open while you flip around.
--------------------------------------------------------------------------
local CP_W = 264
local control

local function cpSectionLabel(parent, text)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	fs:SetText("|cff7d8794" .. text .. "|r")
	return fs
end

local function cpChip(parent)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetHeight(21)
	b.parts = {}
	b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.text:SetPoint("LEFT", 7, 0)
	b.text:SetPoint("RIGHT", -5, 0)
	b.text:SetJustifyH("LEFT")
	b.text:SetWordWrap(false)
	function b:SetRightInset(inset)
		self.text:ClearAllPoints()
		self.text:SetPoint("LEFT", 7, 0)
		self.text:SetPoint("RIGHT", -(inset or 5), 0)
	end
	b:SetScript("OnEnter", function(self)
		if not self.active then self:SetBackdropColor(0.20, 0.24, 0.32, 1) end
	end)
	b:SetScript("OnLeave", function(self)
		if not self.active then self:SetBackdropColor(0.11, 0.12, 0.15, 1) end
	end)
	function b:SetActive(on)
		self.active = on
		if on then
			self:SetBackdropColor(0.16, 0.40, 0.68, 1)
			self:SetBackdropBorderColor(0.35, 0.65, 1, 1)
			self.text:SetTextColor(1, 1, 1)
		else
			self:SetBackdropColor(0.11, 0.12, 0.15, 1)
			self:SetBackdropBorderColor(0.22, 0.23, 0.28, 1)
			self.text:SetTextColor(0.82, 0.84, 0.88)
		end
	end
	b:SetActive(false)
	return b
end

-- A small button riding on the right edge of a mode chip that spawns a mini
-- window for that mode without disturbing the chip's own click.
local function attachPopOut(chip, getMode, getWin)
	if chip.pop then return chip.pop end
	local p = CreateFrame("Button", nil, chip, "BackdropTemplate")
	p.parts = {}
	p:SetSize(15, 15)
	p:SetPoint("RIGHT", -3, 0)
	p:SetFrameLevel(chip:GetFrameLevel() + 4)
	p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	p:SetBackdropColor(0, 0, 0, 0)
	p:SetBackdropBorderColor(0, 0, 0, 0)
	drawPopOut(p, 13)
	p:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.25, 0.55, 0.95, 0.95)
		self:SetBackdropBorderColor(0.45, 0.75, 1, 1)
		for _, t in ipairs(self.parts) do t:SetVertexColor(1, 1, 1) end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Pop out as a mini window", 1, 1, 1)
		GameTooltip:AddLine("Small, always-on-top bars for just this mode.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	p:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0, 0, 0, 0)
		self:SetBackdropBorderColor(0, 0, 0, 0)
		for _, t in ipairs(self.parts) do t:SetVertexColor(0.62, 0.66, 0.74) end
		GameTooltip:Hide()
	end)
	p:SetScript("OnClick", function()
		local win = getWin()
		PM:CreateMiniWindow(getMode(), win and win.settings.segment, win)
		PM:RefreshControl()
	end)
	for _, t in ipairs(p.parts) do t:SetVertexColor(0.62, 0.66, 0.74) end
	chip.pop = p
	return p
end

local function buildControl()
	control = CreateFrame("Frame", "PulseMeterControl", UIParent, "BackdropTemplate")
	control:SetWidth(CP_W)
	control:SetFrameStrata("FULLSCREEN_DIALOG")
	control:SetClampedToScreen(true)
	control:EnableMouse(true)
	control:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
	})
	control:SetBackdropColor(0.05, 0.055, 0.07, 0.98)
	control:SetBackdropBorderColor(0.28, 0.32, 0.40, 1)
	control:Hide()
	table.insert(UISpecialFrames, "PulseMeterControl")

	control.header = control:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	control.header:SetPoint("TOPLEFT", 10, -8)

	local close = CreateFrame("Button", nil, control, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 1, 2)
	close:SetSize(26, 26)
	close:SetFrameLevel(control:GetFrameLevel() + 10)

	control.chips = {}     -- mode chips
	control.segs = {}      -- fight chips
	control.acts = {}      -- action buttons
	control.labels = {}

	-- click anywhere outside to dismiss
	control:SetScript("OnUpdate", function(self)
		if IsMouseButtonDown() and not self:IsMouseOver() then
			if self.owner and self.owner:IsMouseOver() then return end
			self:Hide()
		end
	end)
end

local function cpLabel(i, text, y)
	local fs = control.labels[i]
	if not fs then
		fs = cpSectionLabel(control, text)
		control.labels[i] = fs
	end
	fs:SetText("|cff7d8794" .. text .. "|r")
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", 10, y)
	fs:Show()
	return y - 16
end

local function cpAction(i, text, y, col, func, danger)
	local b = control.acts[i]
	if not b then
		b = cpChip(control)
		control.acts[i] = b
	end
	b:Show()
	b:SetActive(false)
	b.text:SetText(text)
	b.text:SetJustifyH("CENTER")
	b.text:SetTextColor(danger and 1 or 0.82, danger and 0.45 or 0.84, danger and 0.45 or 0.88)
	b:SetScript("OnClick", func)
	b:ClearAllPoints()
	local w = (CP_W - 26) / 2
	b:SetWidth(w)
	b:SetPoint("TOPLEFT", 10 + (col - 1) * (w + 6), y)
	return b
end

function PM:ToggleControl(win, forceShow)
	if not control then buildControl() end
	if control:IsShown() and control.owner == win and not forceShow then
		control:Hide()
		return
	end
	control.owner = win
	self:RefreshControl()
	control:Show()

	-- park it beside the window, flipping/clamping so it always fits
	control:ClearAllPoints()
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	local h = control:GetHeight()
	local wl, wt = win:GetLeft(), win:GetTop()
	if not wl then
		control:SetPoint("CENTER")
		return
	end
	local x = wl + win:GetWidth() * win:GetScale() + 6
	if x + CP_W > sw then x = wl - CP_W - 6 end
	if x < 4 then x = 4 end
	local y = wt * win:GetScale()
	if y - h < 4 then y = h + 4 end
	if y > sh - 4 then y = sh - 4 end
	control:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
end

function PM:RefreshControl()
	if not control or not control:IsShown() and not control.owner then return end
	local win = control.owner
	if not win then return end
	local s = win.settings

	control.header:SetText("|cff4db8ff" .. (s.isMini and "Mini " or "Window ") .. win.index .. "|r")
	local y = -30

	------------------------------------------------------------------ modes
	y = cpLabel(1, "SHOW", y)
	local col, w = 1, (CP_W - 26) / 2
	local n = 0
	for _, key in ipairs(PM.modeOrder) do
		n = n + 1
		local b = control.chips[n]
		if not b then
			b = cpChip(control)
			control.chips[n] = b
		end
		b:Show()
		b:SetWidth(w)
		b:SetRightInset(21)          -- leave room for the pop-out button
		b.text:SetJustifyH("LEFT")
		b.text:SetText(shortName(key))
		b:SetActive(s.mode == key)
		b.modeKey = key
		b:SetScript("OnClick", function()
			win:SetMode(key)
			PM:RefreshControl()
		end)
		attachPopOut(b, function() return b.modeKey end, function() return control.owner end)
		b.pop:Show()
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 10 + (col - 1) * (w + 6), y)
		if col == 2 then y = y - 24; col = 1 else col = 2 end
	end
	if col == 2 then y = y - 24 end
	for i = n + 1, #control.chips do control.chips[i]:Hide() end

	----------------------------------------------------------------- fights
	y = y - 6
	y = cpLabel(2, "FIGHT", y)
	local segList = {
		{ label = "Current", value = "current" },
		{ label = "Overall", value = "overall" },
	}
	if PM.loadedArchive then
		segList[#segList + 1] = {
			label = "\226\152\133 " .. (PM.loadedArchive.name or "Saved fight"),
			value = "archive",
		}
	end
	for i = 1, math.min(#PM.history, 8) do
		segList[#segList + 1] = { label = i .. ". " .. PM.history[i].name, value = i }
	end
	col = 1
	for i, entry in ipairs(segList) do
		local b = control.segs[i]
		if not b then
			b = cpChip(control)
			control.segs[i] = b
		end
		b:Show()
		b.text:SetJustifyH("LEFT")
		b.text:SetText(entry.label)
		b:SetActive(s.segment == entry.value)
		b:SetScript("OnClick", function()
			s.segment = entry.value
			win.offset = 0
			win.dirty = true
			win:Refresh()
			PM:RefreshControl()
		end)
		b:ClearAllPoints()
		if i <= 2 then
			b:SetWidth(w)
			b:SetPoint("TOPLEFT", 10 + (i - 1) * (w + 6), y)
			if i == 2 then y = y - 24 end
		else
			b:SetWidth(CP_W - 20)
			b:SetPoint("TOPLEFT", 10, y)
			y = y - 24
		end
	end
	for i = #segList + 1, #control.segs do control.segs[i]:Hide() end

	---------------------------------------------------------------- actions
	y = y - 6
	y = cpLabel(3, "ACTIONS", y)
	local ai, pending = 0, 0
	local function act(text, fn, danger)
		ai = ai + 1
		pending = pending + 1
		local colN = (pending % 2 == 1) and 1 or 2
		cpAction(ai, text, y, colN, fn, danger)
		if colN == 2 then y = y - 24 end
		return control.acts[ai]
	end
	local function actWide(text, fn, danger)
		if pending % 2 == 1 then y = y - 24 end   -- close a half-filled row
		pending = 0
		ai = ai + 1
		local b = cpAction(ai, text, y, 1, fn, danger)
		b:SetWidth(CP_W - 20)
		y = y - 24
		return b
	end

	act("Death Log", function() PM:ToggleBrowser("deaths") end)
	act("Saved Fights", function() PM:ToggleBrowser("saved") end)
	act("Reset Data", function() PM:ResetAll(); PM:RefreshControl() end, true)
	act("Edit Layout", function() PM:ToggleEditMode(); control:Hide() end)
	act("Docking...", function() PM:ToggleLayoutPanel(win) end)
	act("Settings", function() PM:ToggleOptions(win.index); control:Hide() end)
	act("New Window", function() PM:CreateNewWindow(); PM:RefreshControl() end)
	if PM.current then
		act("End Fight", function() PM:SplitSegment(); PM:RefreshControl() end)
	else
		act("Hide Window", function() win:Hide(); control:Hide() end)
	end

	-- Log Lovers cross-links, only when that addon is actually loaded
	if PM.LL then
		act("Combat Log", function() PM.LL.OpenLog() end)
		act("LL Stats", function() PM.LL.OpenStats() end)
	end

	if #PM.db.windows > 1 then
		actWide("Close This Window", function()
			PM:DeleteWindow(win.index)
			control:Hide()
		end, true)
	elseif pending % 2 == 1 then
		y = y - 24
	end
	for i = ai + 1, #control.acts do control.acts[i]:Hide() end

	control:SetHeight(-y + 16)
end

--------------------------------------------------------------------------
-- Title-bar widgets
--
-- Layout:  [<]        Mode Name        [>] [menu]
--                  fight name (dim)
-- The arrows step through modes without opening anything; the centre opens
-- the mode picker; the fight line opens the fight picker.
--------------------------------------------------------------------------

-- A real button look: filled panel, border, brightens on hover. Glyph fonts
-- can't be trusted here (the client's default font has no box/circle glyphs
-- and renders tofu), so every icon is drawn from WHITE8x8 rectangles.
local function chromeButton(parent, win, tip)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetFrameLevel(parent:GetFrameLevel() + 6)
	b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	b:SetBackdropColor(1, 1, 1, 0.10)
	b:SetBackdropBorderColor(1, 1, 1, 0.18)
	b.parts = {}
	b:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.25, 0.55, 0.95, 0.95)
		self:SetBackdropBorderColor(0.45, 0.75, 1, 1)
		for _, t in ipairs(self.parts) do t:SetVertexColor(1, 1, 1) end
		if tip then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(tip, 1, 1, 1)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function(self)
		self:SetBackdropColor(1, 1, 1, 0.10)
		self:SetBackdropBorderColor(1, 1, 1, 0.18)
		for _, t in ipairs(self.parts) do t:SetVertexColor(0.80, 0.84, 0.90) end
		GameTooltip:Hide()
	end)
	return b
end

-- chevron drawn as a stack of 1px rows: widening then narrowing
local function drawChevron(b, dir, size)
	for _, t in ipairs(b.parts) do t:Hide() end
	local rows = math.max(3, math.floor(size * 0.6))
	if rows % 2 == 0 then rows = rows - 1 end
	local half = (rows - 1) / 2
	local thick = math.max(1, math.floor(size / 7))
	for i = 0, rows - 1 do
		local t = b.parts[i + 1] or px(b)
		t:Show()
		local depth = half - math.abs(i - half)          -- 0 at tips, max in the middle
		t:ClearAllPoints()
		t:SetSize(thick, 1)
		local x = (dir == "left") and (half / 2 - depth) or (depth - half / 2)
		t:SetPoint("CENTER", b, "CENTER", x, half - i)
	end
end

-- three stacked bars: an unambiguous "menu" affordance that always renders
local function drawMenuIcon(b, size)
	for _, t in ipairs(b.parts) do t:Hide() end
	local w = math.max(6, math.floor(size * 0.55))
	local gap = math.max(2, math.floor(size * 0.18))
	for i = 1, 3 do
		local t = b.parts[i] or px(b)
		t:Show()
		t:ClearAllPoints()
		t:SetSize(w, 1)
		t:SetPoint("CENTER", b, "CENTER", 0, gap - (i - 1) * gap)
	end
end

-- an invisible clickable label zone (mode name, fight name)
local function titleZone(parent, win)
	local b = CreateFrame("Button", nil, parent)
	b:SetFrameLevel(parent:GetFrameLevel() + 5)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b.hl = b:CreateTexture(nil, "BACKGROUND")
	b.hl:SetAllPoints()
	b.hl:SetColorTexture(1, 1, 1, 0.10)
	b.hl:Hide()
	b.text = b:CreateFontString(nil, "OVERLAY")
	b.text:SetPoint("CENTER")
	b.text:SetJustifyH("CENTER")
	b.text:SetWordWrap(false)
	b:SetScript("OnEnter", function(self) self.hl:Show() end)
	b:SetScript("OnLeave", function(self) self.hl:Hide() end)
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnDragStart", function()
		if PM.editMode or not win.settings.locked then
			win:Unlink("drag"); win:StartMoving(); win.moving = true
		end
	end)
	b:SetScript("OnDragStop", function()
		if win.moving then
			win:StopMovingOrSizing(); win.moving = false
			win:SavePosition()
			PM:UpdateDockChain(win)
			if PM.editMode then PM:TryLink(win) end
		end
	end)
	return b
end

--------------------------------------------------------------------------
-- Window creation
--------------------------------------------------------------------------
local windowCount = 0

function PM:CreateWindow(settings, index)
	windowCount = windowCount + 1
	local f = CreateFrame("Frame", "PulseMeterWindow" .. windowCount, UIParent, "BackdropTemplate")
	for k, v in pairs(WindowProto) do f[k] = v end   -- never setmetatable a Frame
	f.settings = settings
	f.index = index
	f.bars = {}
	f.offset = 0
	f.drillGUID = nil

	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:SetResizable(true)
	if f.SetResizeBounds then f:SetResizeBounds(120, 40, 900, 900)
	elseif f.SetMinResize then f:SetMinResize(120, 40); f:SetMaxResize(900, 900) end
	f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
	f:EnableMouse(true)
	f:EnableMouseWheel(true)

	------------------------------------------------------------------ title
	local title = CreateFrame("Frame", nil, f, "BackdropTemplate")
	title:SetPoint("TOPLEFT"); title:SetPoint("TOPRIGHT")
	title:SetHeight(settings.titleHeight)
	title:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
	title:EnableMouse(true)
	f.title = title

	-- accent stripe so the header reads as a header, not just a darker bar
	title.accent = title:CreateTexture(nil, "ARTWORK")
	title.accent:SetPoint("TOPLEFT"); title.accent:SetPoint("BOTTOMLEFT")
	title.accent:SetWidth(2)
	title.accent:SetColorTexture(0.30, 0.72, 1.00, 0.9)

	-- previous / next mode
	local prev = chromeButton(title, f, "Previous mode")
	prev:SetScript("OnClick", function() f:CycleMode(-1) end)
	title.prev = prev

	local nextB = chromeButton(title, f, "Next mode")
	nextB:SetScript("OnClick", function() f:CycleMode(1) end)
	title.next = nextB

	-- menu, far right
	local menuBtn = chromeButton(title, f, "Controls: modes, fights, actions")
	menuBtn:SetScript("OnClick", function() PM:ToggleControl(f) end)
	title.menuBtn = menuBtn

	-- back out of a drill-down
	local back = chromeButton(title, f, "Back")
	back:SetScript("OnClick", function() f:ExitDrill() end)
	back:Hide()
	title.back = back

	-- centred mode name
	local modeZone = titleZone(title, f)
	modeZone:SetScript("OnClick", function(_, btn)
		if btn == "RightButton" then PM:ToggleControl(f) else f:OpenModePicker() end
	end)
	title.modeZone = modeZone

	-- fight name, centred underneath (or dim inline on short title bars)
	local segZone = titleZone(title, f)
	segZone:SetScript("OnClick", function(_, btn)
		if btn == "RightButton" then PM:ToggleControl(f) else f:OpenSegmentPicker() end
	end)
	title.segZone = segZone

	-- dragging from blank title space
	title:SetScript("OnMouseDown", function(_, btn)
		if btn == "LeftButton" and (PM.editMode or not settings.locked) then
			f:Unlink("drag"); f:StartMoving(); f.moving = true
		end
	end)
	title:SetScript("OnMouseUp", function(_, btn)
		if f.moving then
			f:StopMovingOrSizing(); f.moving = false
			f:SavePosition()
			PM:UpdateDockChain(f)
			if PM.editMode then PM:TryLink(f) end
		end
		if btn == "RightButton" then PM:ToggleControl(f) end
	end)

	------------------------------------------------------------------- body
	local body = CreateFrame("Frame", nil, f)
	body:SetPoint("BOTTOMRIGHT")
	f.body = body

	f:SetScript("OnMouseUp", function(_, btn)
		if btn == "RightButton" then
			if f.drillGUID then f:ExitDrill() else PM:ToggleControl(f) end
		elseif btn == "MiddleButton" then f:QuickSwitch() end
	end)

	f:SetScript("OnMouseWheel", function(_, delta)
		if IsShiftKeyDown() then f:CycleMode(delta > 0 and -1 or 1)
		else
			f.offset = math.max(0, f.offset - delta)
			f:Refresh()
		end
	end)

	local acc = 0
	f:SetScript("OnUpdate", function(self, elapsed)
		acc = acc + elapsed
		if acc >= PM.db.general.updateInterval then
			acc = 0
			if PM.testMode and self.index == 1 then PM:TickTestData() end
			if PM.inCombat or PM.testMode or self.dirty then
				self:Refresh()
				self.dirty = false
			end
		end
	end)

	f:ApplySettings()
	f:RestorePosition()
	f:Refresh()
	return f
end

--------------------------------------------------------------------------
-- Position / linking
--------------------------------------------------------------------------
function WindowProto:SavePosition()
	local s = self.settings
	s.point = "BOTTOMLEFT"
	s.x = self:GetLeft() or s.x
	s.y = self:GetBottom() or s.y
	s.width = math.floor(self:GetWidth() + 0.5)
	s.height = math.floor(self:GetHeight() + 0.5)
	if s.anchorTo then
		local other = PM.windows[s.anchorTo]
		if other and other:GetLeft() then
			s.relX = (self:GetLeft() or 0) - other:GetLeft()
			s.relY = (self:GetTop() or 0) - other:GetTop()
		end
	end
end

function WindowProto:RestorePosition()
	local s = self.settings
	self:SetSize(s.width, s.height)
	self:ClearAllPoints()
	local other = s.anchorTo and PM.windows[s.anchorTo]
	if other and other ~= self then
		if s.dockEdge then
			PM:ApplyDock(self)
			return
		end
		self:SetPoint("TOPLEFT", other, "TOPLEFT", s.relX or 0, s.relY or 0)
	elseif s.point == "BOTTOMLEFT" then
		self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", s.x or 0, s.y or 0)
	else
		self:SetPoint(s.point or "CENTER", UIParent, s.relPoint or s.point or "CENTER", s.x or 0, s.y or 0)
	end
end

function WindowProto:Unlink(reason)
	local s = self.settings
	if s.anchorTo then
		local l, b = self:GetLeft(), self:GetBottom()
		s.anchorTo, s.dockEdge, s.relX, s.relY = nil, nil, nil, nil
		self:ClearAllPoints()
		self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l or 300, b or 300)
		if reason == "drag" then PM:Print("Window " .. self.index .. " undocked.") end
	end
end

--------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------
function WindowProto:ApplySettings()
	local s = self.settings
	self:SetScale(s.scale)
	self:SetAlpha(s.alpha)
	self:SetFrameStrata(s.strata)
	self:SetBackdropColor(unpack(s.bgColor))

	local th = s.titleHeight
	self.title:SetHeight(th)
	self.title:SetBackdropColor(unpack(s.titleColor))
	self.title:SetShown(s.showTitle)
	self.title.accent:SetShown(s.showTitle and not s.isMini)

	local font, size, outline = PM:GetFont(s.font), s.fontSize, s.fontOutline
	local t = self.title
	local btn = math.max(10, math.min(th - 5, 18))
	local stacked = (not s.isMini) and th >= 24

	t.prev:SetSize(btn, btn);    drawChevron(t.prev, "left", btn)
	t.next:SetSize(btn, btn);    drawChevron(t.next, "right", btn)
	t.back:SetSize(btn, btn);    drawChevron(t.back, "left", btn)
	t.menuBtn:SetSize(btn, btn); drawMenuIcon(t.menuBtn, btn)

	local pad = 3
	t.prev:ClearAllPoints();    t.prev:SetPoint("LEFT", pad + 2, 0)
	t.back:ClearAllPoints();    t.back:SetPoint("LEFT", pad + 2, 0)
	t.menuBtn:ClearAllPoints(); t.menuBtn:SetPoint("RIGHT", -pad, 0)
	t.next:ClearAllPoints();    t.next:SetPoint("RIGHT", t.menuBtn, "LEFT", -pad, 0)
	t.prev:SetShown(not self.drillGUID)

	-- centre column lives between the arrows
	local mz, sz = t.modeZone, t.segZone
	mz:ClearAllPoints(); sz:ClearAllPoints()
	mz:SetPoint("LEFT", t.prev, "RIGHT", pad, 0)
	mz:SetPoint("RIGHT", t.next, "LEFT", -pad, 0)
	mz.text:SetFont(font, size, outline)

	if stacked then
		local top = math.floor((th - 2) * 0.55)
		mz:SetPoint("TOP", 0, -1)
		mz:SetHeight(top)
		sz:SetPoint("TOPLEFT", mz, "BOTTOMLEFT", 0, 0)
		sz:SetPoint("TOPRIGHT", mz, "BOTTOMRIGHT", 0, 0)
		sz:SetHeight(th - top - 2)
		sz.text:SetFont(font, math.max(size - 2, 7), outline)
		sz:Show()
	else
		mz:SetPoint("TOP", 0, 0); mz:SetPoint("BOTTOM", 0, 0)
		-- no room for a second line: the fight name rides along dim and inline
		sz:SetPoint("LEFT", mz, "LEFT"); sz:SetPoint("RIGHT", mz, "RIGHT")
		sz:SetHeight(1)
		sz.text:SetFont(font, math.max(size - 2, 7), outline)
		sz:Hide()
	end
	self.titleStacked = stacked

	self.body:ClearAllPoints()
	self.body:SetPoint("TOPLEFT", 0, s.showTitle and -(th + 1) or 0)
	self.body:SetPoint("BOTTOMRIGHT")

	self:EnableMouse(not s.clickThrough or PM.editMode)

	for _, b in ipairs(self.bars) do b:Hide() end
	wipe(self.bars)
	self.dirty = true
	self:Refresh()
end

--------------------------------------------------------------------------
-- Bars
--------------------------------------------------------------------------
function WindowProto:GetBar(i)
	local bar = self.bars[i]
	if not bar then
		bar = CreateFrame("StatusBar", nil, self.body)
		bar:SetMinMaxValues(0, 1)
		bar:EnableMouse(true)

		bar.track = bar:CreateTexture(nil, "BACKGROUND")
		bar.track:SetAllPoints()
		bar.track:SetColorTexture(1, 1, 1, 0.055)

		bar.icon = bar:CreateTexture(nil, "ARTWORK")
		bar.icon:SetPoint("LEFT", 1, 0)
		bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		bar.rank = bar:CreateFontString(nil, "OVERLAY")
		bar.rank:SetJustifyH("RIGHT")
		bar.left = bar:CreateFontString(nil, "OVERLAY")
		bar.left:SetJustifyH("LEFT")
		bar.right = bar:CreateFontString(nil, "OVERLAY")
		bar.right:SetPoint("RIGHT", -4, 0)
		bar.right:SetJustifyH("RIGHT")

		bar.hl = bar:CreateTexture(nil, "OVERLAY")
		bar.hl:SetAllPoints()
		bar.hl:SetColorTexture(1, 1, 1, 0.12)
		bar.hl:Hide()

		local win = self
		bar:SetScript("OnEnter", function(b)
			b.hl:Show()
			GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
			if b.spellEntry then
				local e = b.spellEntry
				GameTooltip:AddLine(e.name, 1, 1, 1)
				if e.count then
					GameTooltip:AddDoubleLine("Count", e.s.hits, 0.8, 0.8, 0.8, 1, 1, 1)
				else
					GameTooltip:AddDoubleLine("Total", PM:FormatNumber(e.s.amount), 0.8, 0.8, 0.8, 1, 1, 1)
					GameTooltip:AddDoubleLine("Hits", e.s.hits, 0.8, 0.8, 0.8, 1, 1, 1)
					if e.s.hits > 0 then
						GameTooltip:AddDoubleLine("Average", PM:FormatNumber(e.s.amount / e.s.hits), 0.8, 0.8, 0.8, 1, 1, 1)
						GameTooltip:AddDoubleLine("Crit", string.format("%.0f%%", e.s.crits / e.s.hits * 100), 0.8, 0.8, 0.8, 1, 1, 1)
					end
					GameTooltip:AddDoubleLine("Biggest hit", PM:FormatNumber(e.s.max), 0.8, 0.8, 0.8, 1, 1, 1)
				end
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine("Right-click to go back", 0.5, 0.7, 1)
			elseif b.actor then
				local mode = PM.modes[win.settings.mode]
				local seg = PM:GetSegment(win.settings.segment)
				if mode and mode.tooltip and seg then mode.tooltip(GameTooltip, b.actor, seg) end
				if mode and (mode.detail or mode.openBrowser) then
					GameTooltip:AddLine(" ")
					GameTooltip:AddLine("Click for the full breakdown", 0.5, 0.7, 1)
				end
			end
			GameTooltip:Show()
		end)
		bar:SetScript("OnLeave", function(b) b.hl:Hide(); GameTooltip:Hide() end)
		bar:SetScript("OnMouseUp", function(b, btn)
			if btn == "LeftButton" then
				if win.drillGUID then return end
				local mode = PM.modes[win.settings.mode]
				if b.actor and mode then
					if mode.openBrowser then PM:ToggleBrowser(mode.openBrowser, true)
					elseif mode.detail then win:EnterDrill(b.actor) end
				end
			elseif btn == "RightButton" then
				if win.drillGUID then win:ExitDrill() else PM:ToggleControl(win) end
			elseif btn == "MiddleButton" then
				win:QuickSwitch()
			end
		end)
		self.bars[i] = bar
	end
	return bar
end

--------------------------------------------------------------------------
-- Drill-down
--------------------------------------------------------------------------
function WindowProto:EnterDrill(actor)
	self.drillGUID = actor.guid
	self.drillName = actor.name
	self.drillClass = actor.class
	self.offset = 0
	self.title.back:Show()
	self.title.prev:Hide()
	self:ApplySettings()
end

function WindowProto:ExitDrill()
	self.drillGUID = nil
	self.offset = 0
	self.title.back:Hide()
	self.title.prev:Show()
	self:ApplySettings()
end

--------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------
local function layoutBar(self, bar, i, barH, gap)
	local s = self.settings
	bar:ClearAllPoints()
	local yoff = (i - 1) * (barH + gap)
	if s.growUp then
		bar:SetPoint("BOTTOMLEFT", 0, yoff)
		bar:SetPoint("BOTTOMRIGHT", 0, yoff)
	else
		bar:SetPoint("TOPLEFT", 0, -yoff)
		bar:SetPoint("TOPRIGHT", 0, -yoff)
	end
	bar:SetHeight(barH)
end

function WindowProto:Refresh()
	local s = self.settings
	local seg = PM:GetSegment(s.segment)
	local mode = PM.modes[s.mode]
	if not mode then return end

	local barH, gap = s.barHeight, s.barSpacing
	local visible = math.floor(self.body:GetHeight() / (barH + gap))
	if visible < 1 then visible = 1 end
	local font, fsize, outline = PM:GetFont(s.font), s.fontSize, s.fontOutline
	local tex = PM:GetTexture(s.texture)

	local function styleText(bar)
		bar.rank:SetFont(font, math.max(fsize - 1, 7), outline)
		bar.left:SetFont(font, fsize, outline)
		bar.right:SetFont(font, fsize, outline)
		bar.rank:SetTextColor(0.55, 0.58, 0.64)
	end

	------------------------------------------------ drill-down (spell view)
	if self.drillGUID then
		local actor = seg and seg.actors[self.drillGUID]
		if not actor or not mode.detail then self:ExitDrill() return end
		local list, total = mode.detail(actor, seg)
		local sub = "|cff9aa4b2" .. mode.name .. "|r"
			.. (total > 0 and ("  " .. PM:FormatNumber(total)) or "")
		if self.titleStacked then
			self.title.modeZone.text:SetText(self.drillName or "?")
			self.title.segZone.text:SetText(sub)
		else
			self.title.modeZone.text:SetText((self.drillName or "?") .. "  " .. sub)
			self.title.segZone.text:SetText("")
		end

		local maxOffset = math.max(0, #list - visible)
		if self.offset > maxOffset then self.offset = maxOffset end
		local topValue = list[1] and list[1].value or 1
		local r, g, b = 0.55, 0.6, 0.68
		if s.classColors and self.drillClass then r, g, b = PM:ClassColor(self.drillClass) end

		for i = 1, visible do
			local e = list[i + self.offset]
			local bar = self:GetBar(i)
			if e then
				layoutBar(self, bar, i, barH, gap)
				bar:SetStatusBarTexture(tex)
				bar:SetValue(e.value / math.max(topValue, 1))
				bar:SetStatusBarColor(r, g, b, 1)
				bar.icon:Hide()
				styleText(bar)
				bar.rank:ClearAllPoints(); bar.rank:Hide()
				bar.left:ClearAllPoints()
				bar.left:SetPoint("LEFT", 5, 0)
				bar.left:SetPoint("RIGHT", bar.right, "LEFT", -4, 0)
				bar.left:SetText(e.name)
				local rt = e.count and tostring(e.s.hits) or PM:FormatNumber(e.value)
				if s.showPercent and total > 0 then
					rt = rt .. string.format("  |cffb9c2ce%.0f%%|r", e.value / total * 100)
				end
				bar.right:SetText(rt)
				bar.spellEntry = e
				bar.actor = nil
				bar:Show()
			else
				bar:Hide(); bar.spellEntry = nil; bar.actor = nil
			end
		end
		for i = visible + 1, #self.bars do self.bars[i]:Hide() end
		return
	end

	------------------------------------------------------------ normal view
	local segLabel
	if PM.testMode then segLabel = "Test data"
	elseif s.segment == "archive" then
		segLabel = seg and ("\226\152\133 " .. (seg.name or "Saved")) or "Saved fight gone"
	elseif s.segment == "current" then
		segLabel = (seg and (seg.enemy or seg.name)) or "No fight yet"
	elseif s.segment == "overall" then segLabel = "Overall"
	else segLabel = seg and seg.name or "?" end

	local list, total = PM:GetSortedActors(seg, s.mode)
	local live = (seg and PM.current == seg) and "|cff4dff88* |r" or ""
	local sub = live .. "|cff9aa4b2" .. segLabel .. "|r"
		.. (total > 0 and ("  " .. PM:FormatNumber(total)) or "")
	if self.titleStacked then
		self.title.modeZone.text:SetText(mode.name)
		self.title.segZone.text:SetText(sub)
	else
		self.title.modeZone.text:SetText(mode.name .. "  " .. sub)
		self.title.segZone.text:SetText("")
	end

	local maxOffset = math.max(0, #list - visible)
	if self.offset > maxOffset then self.offset = maxOffset end
	local topValue = list[1] and list[1].value or 1

	for i = 1, visible do
		local entry = list[i + self.offset]
		local bar = self:GetBar(i)
		if entry then
			local a = entry.actor
			local n = i + self.offset
			layoutBar(self, bar, i, barH, gap)
			bar:SetStatusBarTexture(tex)
			bar:SetValue(entry.value / math.max(topValue, 1))

			local r, g, b
			if s.classColors and a.class then r, g, b = PM:ClassColor(a.class)
			else r, g, b = unpack(s.barColor) end
			bar:SetStatusBarColor(r, g, b, 1)

			styleText(bar)
			local leftAnchor, leftPad = bar, 5
			bar.rank:ClearAllPoints()
			if s.showRank then
				bar.rank:Show()
				bar.rank:SetPoint("LEFT", 4, 0)
				bar.rank:SetWidth(fsize + 6)
				bar.rank:SetText(n .. ".")
				leftAnchor, leftPad = bar.rank, 3
			else
				bar.rank:Hide()
			end

			bar.left:ClearAllPoints()
			if s.showIcons and a.class and CLASS_ICON_TCOORDS[a.class] then
				bar.icon:Show()
				bar.icon:SetSize(barH - 2, barH - 2)
				bar.icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
				bar.icon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[a.class]))
				bar.icon:ClearAllPoints()
				bar.icon:SetPoint("LEFT", leftAnchor, leftAnchor == bar and "LEFT" or "RIGHT", leftPad, 0)
				bar.left:SetPoint("LEFT", bar.icon, "RIGHT", 3, 0)
			else
				bar.icon:Hide()
				bar.left:SetPoint("LEFT", leftAnchor, leftAnchor == bar and "LEFT" or "RIGHT", leftPad, 0)
			end
			bar.left:SetPoint("RIGHT", bar.right, "LEFT", -4, 0)
			bar.left:SetText(a.name)

			local v1 = mode.barText and mode.barText(a, seg)
			local rt = ""
			if s.showValue and v1 then rt = v1 end
			if s.showPercent and total > 0 then
				rt = rt .. string.format("  |cffb9c2ce%.0f%%|r", entry.value / total * 100)
			end
			bar.right:SetText(rt)
			bar.actor = a
			bar.spellEntry = nil
			bar:Show()
		else
			bar:Hide(); bar.actor = nil; bar.spellEntry = nil
		end
	end
	for i = visible + 1, #self.bars do
		self.bars[i]:Hide(); self.bars[i].actor = nil; self.bars[i].spellEntry = nil
	end
end

--------------------------------------------------------------------------
-- Mode / segment switching
--------------------------------------------------------------------------
function WindowProto:SetMode(key)
	self.settings.mode = key
	self.offset = 0
	if self.drillGUID then self:ExitDrill() end
	self.dirty = true
	self:Refresh()
end

function WindowProto:CycleMode(dir)
	local order = PM.modeOrder
	local cur = 1
	for i, k in ipairs(order) do if k == self.settings.mode then cur = i break end end
	self:SetMode(order[((cur - 1 + dir) % #order) + 1])
end

function WindowProto:QuickSwitch()
	local qm = self.settings.quickModes
	if not qm or #qm == 0 then return self:CycleMode(1) end
	local cur = 0
	for i, k in ipairs(qm) do if k == self.settings.mode then cur = i break end end
	self:SetMode(qm[(cur % #qm) + 1])
end

function WindowProto:OpenModePicker()
	local items = { { title = true, text = "Show" } }
	for _, key in ipairs(PM.modeOrder) do
		items[#items + 1] = {
			text = PM.modes[key].name, checked = (self.settings.mode == key),
			func = function() self:SetMode(key) end,
		}
	end
	PM:ShowMenu(items)
end

function WindowProto:OpenSegmentPicker()
	local s = self.settings
	local function pick(v)
		s.segment = v; self.offset = 0; self.dirty = true; self:Refresh()
	end
	local items = { { title = true, text = "Fight" } }
	items[#items + 1] = { text = "Current fight", checked = s.segment == "current", func = function() pick("current") end }
	items[#items + 1] = { text = "Overall", checked = s.segment == "overall", func = function() pick("overall") end }
	if PM.loadedArchive then
		items[#items + 1] = { text = "Saved: " .. (PM.loadedArchive.name or "?"),
			checked = s.segment == "archive", func = function() pick("archive") end }
	end
	for i = 1, #PM.history do
		local seg = PM.history[i]
		items[#items + 1] = { text = i .. ". " .. seg.name, checked = s.segment == i,
			func = function() pick(i) end }
	end
	PM:ShowMenu(items)
end

-- kept so older calls (and the API) still work
function WindowProto:OpenMenu() PM:ToggleControl(self) end
function WindowProto:OpenSegmentMenu() self:OpenSegmentPicker() end

--------------------------------------------------------------------------
-- Window collection management
--------------------------------------------------------------------------
function PM:RebuildWindows()
	for _, w in ipairs(self.windows) do w:Hide() end
	wipe(self.windows)
	self:ScanSharedMedia()
	for i, s in ipairs(self.db.windows) do
		self.windows[i] = self:CreateWindow(s, i)
	end
	for _, w in ipairs(self.windows) do w:RestorePosition() end
end

function PM:CreateNewWindow()
	local s = self:NewWindowSettings()
	s.x = (s.x or 0) - 30 * #self.db.windows
	table.insert(self.db.windows, s)
	local i = #self.db.windows
	self.windows[i] = self:CreateWindow(s, i)
	self:Print("Created window " .. i .. ".")
	return self.windows[i]
end

function PM:CreateMiniWindow(modeKey, segment, near)
	local s = self:NewWindowSettings()
	s.isMini = true
	s.mode = modeKey
	s.segment = segment or "overall"
	s.width, s.height = 158, 76
	s.titleHeight = 15
	s.barHeight = 12
	s.barSpacing = 0
	s.fontSize = 9
	s.showRank = false
	s.showPercent = false
	s.showIcons = false
	s.texture = "minimal"
	-- park it next to whatever window it was popped out of, stepping down so
	-- several pop-outs in a row don't stack on top of each other
	local bx, by = 400 + 30 * #self.db.windows, 300
	if near and near.GetLeft and near:GetLeft() then
		bx = near:GetLeft() + near:GetWidth() + 8
		by = (near:GetBottom() or 300) + near:GetHeight() - s.height
		local step = 0
		for _, w in ipairs(self.windows) do
			if w.settings.isMini then step = step + 1 end
		end
		by = by - step * (s.height + 6)
		if by < 20 then by = 20 end
		if bx + s.width > UIParent:GetWidth() then
			bx = math.max(4, (near:GetLeft() or 400) - s.width - 8)
		end
	end
	s.point, s.x, s.y = "BOTTOMLEFT", bx, by
	s.quickModes = { "deaths", "interrupts", "dispels" }
	table.insert(self.db.windows, s)
	local i = #self.db.windows
	self.windows[i] = self:CreateWindow(s, i)
	self:Print(("Popped out |cffffd100%s|r as mini window %d. Right-click it to close."):format(
		(self.modes[modeKey] and self.modes[modeKey].name) or modeKey, i))
	return self.windows[i]
end

function PM:DeleteWindow(index)
	if #self.db.windows <= 1 then self:Print("Cannot delete the last window.") return end
	table.remove(self.db.windows, index)
	for _, s in ipairs(self.db.windows) do
		if s.anchorTo then
			if s.anchorTo == index then s.anchorTo, s.dockEdge, s.relX, s.relY = nil, nil, nil, nil
			elseif s.anchorTo > index then s.anchorTo = s.anchorTo - 1 end
		end
	end
	self:RebuildWindows()
end

function PM:RefreshWindows(force)
	for _, w in ipairs(self.windows) do
		w.dirty = true
		if force then w:Refresh() end
	end
	if control and control:IsShown() then self:RefreshControl() end
end

function PM:ToggleAllWindows()
	local anyShown = false
	for _, w in ipairs(self.windows) do
		if w:IsShown() then anyShown = true break end
	end
	for _, w in ipairs(self.windows) do w:SetShown(not anyShown) end
end

function PM:UpdateWindowAlphas(inCombat)
	for _, w in ipairs(self.windows) do
		local s = w.settings
		w:SetAlpha(inCombat and s.combatAlpha or s.oocAlpha)
	end
end
