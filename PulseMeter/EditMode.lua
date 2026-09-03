-- PulseMeter EditMode.lua
-- Live window editing: drag from anywhere, 4 corner resize grips, magnetic
-- snapping (screen edges, screen center, and other PulseMeter windows),
-- alignment guide lines, optional grid, position HUD, arrow-key nudging.

local ADDON, ns = ...
local PM = ns.PM

PM.editMode = false

--------------------------------------------------------------------------
-- Guide lines (shared overlay)
--------------------------------------------------------------------------
local overlay = CreateFrame("Frame", "PulseMeterEditOverlay", UIParent)
overlay:SetAllPoints()
overlay:SetFrameStrata("TOOLTIP")
overlay:Hide()

local guideV = overlay:CreateTexture(nil, "OVERLAY")
guideV:SetColorTexture(0.2, 0.85, 1, 0.8)
guideV:SetWidth(1)
guideV:Hide()

local guideH = overlay:CreateTexture(nil, "OVERLAY")
guideH:SetColorTexture(0.2, 0.85, 1, 0.8)
guideH:SetHeight(1)
guideH:Hide()

local gridLines = {}
local function showGrid()
	local size = PM.db.edit.gridSize
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	local n = 0
	for x = size, sw, size do
		n = n + 1
		local t = gridLines[n] or overlay:CreateTexture(nil, "BACKGROUND")
		gridLines[n] = t
		t:SetColorTexture(1, 1, 1, 0.06)
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", x, 0); t:SetPoint("BOTTOMLEFT", x, 0)
		t:SetWidth(1)
		t:Show()
	end
	for y = size, sh, size do
		n = n + 1
		local t = gridLines[n] or overlay:CreateTexture(nil, "BACKGROUND")
		gridLines[n] = t
		t:SetColorTexture(1, 1, 1, 0.06)
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", 0, -y); t:SetPoint("TOPRIGHT", 0, -y)
		t:SetHeight(1)
		t:Show()
	end
	for i = n + 1, #gridLines do gridLines[i]:Hide() end
end
local function hideGrid()
	for _, t in ipairs(gridLines) do t:Hide() end
end

--------------------------------------------------------------------------
-- HUD (shows coords + size of the frame being edited, and hotkey help)
--------------------------------------------------------------------------
local hud = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
hud:SetSize(300, 76)
hud:SetPoint("TOP", 0, -30)
hud:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
hud:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
hud:SetBackdropBorderColor(0.2, 0.85, 1, 0.8)

hud.title = hud:CreateFontString(nil, "OVERLAY", "GameFontNormal")
hud.title:SetPoint("TOP", 0, -6)
hud.title:SetText("|cff4db8ffPulseMeter Edit Mode|r")

hud.info = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
hud.info:SetPoint("TOP", 0, -24)
hud.info:SetText("Drag windows to move - corners to resize")

hud.help = hud:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hud.help:SetPoint("TOP", 0, -40)
hud.help:SetText("Shift = no snap | Arrows = nudge | G = grid | D = docking | Esc = done")

local dockBtn = CreateFrame("Button", nil, hud, "UIPanelButtonTemplate")
dockBtn:SetSize(90, 18)
dockBtn:SetPoint("BOTTOM", -50, 4)
dockBtn:SetText("Docking...")
dockBtn:SetScript("OnClick", function() PM:ToggleLayoutPanel(PM.editSelected) end)

local exit = CreateFrame("Button", nil, hud, "UIPanelButtonTemplate")
exit:SetSize(60, 18)
exit:SetPoint("BOTTOM", 50, 4)
exit:SetText("Done")
exit:SetScript("OnClick", function() PM:ToggleEditMode() end)

--------------------------------------------------------------------------
-- Snapping
--------------------------------------------------------------------------
-- returns snapped left/bottom for a frame being dragged
local function computeSnap(frame)
	local e = PM.db.edit
	if not e.snap or IsShiftKeyDown() then
		guideV:Hide(); guideH:Hide()
		return nil
	end
	local dist = e.snapDist
	local L, B, W, H = frame:GetLeft(), frame:GetBottom(), frame:GetWidth(), frame:GetHeight()
	if not L then return nil end
	local R, T = L + W, B + H
	local CX, CY = L + W / 2, B + H / 2
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()

	local bestDX, bestDY = nil, nil
	local guideX, guideY = nil, nil

	local function tryX(myEdge, target, offsetToLeft)
		local d = target - myEdge
		if math.abs(d) <= dist and (not bestDX or math.abs(d) < math.abs(bestDX)) then
			bestDX = d
			guideX = target
		end
	end
	local function tryY(myEdge, target)
		local d = target - myEdge
		if math.abs(d) <= dist and (not bestDY or math.abs(d) < math.abs(bestDY)) then
			bestDY = d
			guideY = target
		end
	end

	-- screen edges + center
	tryX(L, 0); tryX(R, sw); tryX(CX, sw / 2)
	tryY(B, 0); tryY(T, sh); tryY(CY, sh / 2)

	-- other windows
	for _, other in ipairs(PM.windows) do
		if other ~= frame and other:IsShown() then
			local oL, oB = other:GetLeft(), other:GetBottom()
			if oL then
				local oR, oT = oL + other:GetWidth(), oB + other:GetHeight()
				-- edge-to-edge and edge alignment
				tryX(L, oL); tryX(L, oR); tryX(R, oR); tryX(R, oL)
				tryY(B, oB); tryY(B, oT); tryY(T, oT); tryY(T, oB)
			end
		end
	end

	-- grid snapping
	if e.grid then
		local g = e.gridSize
		local gx = math.floor(L / g + 0.5) * g
		local gy = math.floor(B / g + 0.5) * g
		tryX(L, gx); tryY(B, gy)
	end

	-- guides
	if PM.db.edit.showGuides then
		if guideX then
			guideV:ClearAllPoints()
			guideV:SetPoint("TOPLEFT", guideX, 0)
			guideV:SetPoint("BOTTOMLEFT", guideX, 0)
			guideV:Show()
		else guideV:Hide() end
		if guideY then
			guideH:ClearAllPoints()
			guideH:SetPoint("BOTTOMLEFT", 0, guideY)
			guideH:SetPoint("BOTTOMRIGHT", 0, guideY)
			guideH:Show()
		else guideH:Hide() end
	end

	if bestDX or bestDY then
		return L + (bestDX or 0), B + (bestDY or 0)
	end
end

local function applyPosition(frame, left, bottom)
	frame:ClearAllPoints()
	frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
end

--------------------------------------------------------------------------
-- Per-window edit chrome
--------------------------------------------------------------------------
local function attachEditChrome(win)
	if win.editChrome then return win.editChrome end
	local c = {}

	-- glow border
	local border = CreateFrame("Frame", nil, win, "BackdropTemplate")
	border:SetPoint("TOPLEFT", -2, 2)
	border:SetPoint("BOTTOMRIGHT", 2, -2)
	border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
	border:SetBackdropBorderColor(0.2, 0.85, 1, 0.9)
	border:SetFrameLevel(win:GetFrameLevel() + 10)
	c.border = border

	-- label
	local label = border:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("BOTTOM", win, "TOP", 0, 6)
	c.label = label

	-- drag surface (covers whole window while editing)
	local drag = CreateFrame("Frame", nil, win)
	drag:SetAllPoints()
	drag:SetFrameLevel(win:GetFrameLevel() + 11)
	drag:EnableMouse(true)
	c.drag = drag

	drag:SetScript("OnMouseDown", function(_, btn)
		if btn == "LeftButton" then
			PM.editSelected = win
			if _G.PulseMeterLayoutPanel and _G.PulseMeterLayoutPanel:IsShown() then
				PM:ToggleLayoutPanel(win, true)
			end
			win:Unlink("drag")
			win:StartMoving()
			win.editMoving = true
		end
	end)
	drag:SetScript("OnMouseUp", function(_, btn)
		if win.editMoving then
			win:StopMovingOrSizing()
			win.editMoving = false
			local l, b = computeSnap(win)
			if l then applyPosition(win, l, b) end
			guideV:Hide(); guideH:Hide()
			win:SavePosition()
			PM:UpdateDockChain(win)
			PM:TryLink(win)
			win:SavePosition()
		end
		if btn == "RightButton" then win:OpenMenu() end
	end)
	drag:SetScript("OnUpdate", function()
		if win.editMoving then
			computeSnap(win) -- live guides while dragging
			hud.info:SetFormattedText("Window %d - x: %d  y: %d  -  %d x %d",
				win.index, win:GetLeft() or 0, win:GetBottom() or 0, win:GetWidth(), win:GetHeight())
		end
	end)

	-- 4 corner resize grips
	local corners = {
		{ "BOTTOMRIGHT", "BOTTOMRIGHT" },
		{ "BOTTOMLEFT", "BOTTOMLEFT" },
		{ "TOPRIGHT", "TOPRIGHT" },
		{ "TOPLEFT", "TOPLEFT" },
	}
	c.grips = {}
	for _, def in ipairs(corners) do
		local grip = CreateFrame("Frame", nil, win)
		grip:SetSize(14, 14)
		grip:SetPoint(def[1])
		grip:SetFrameLevel(win:GetFrameLevel() + 12)
		grip:EnableMouse(true)
		local t = grip:CreateTexture(nil, "OVERLAY")
		t:SetAllPoints()
		t:SetColorTexture(0.2, 0.85, 1, 0.9)
		grip:SetScript("OnEnter", function() t:SetColorTexture(1, 1, 1, 1) end)
		grip:SetScript("OnLeave", function() t:SetColorTexture(0.2, 0.85, 1, 0.9) end)
		grip:SetScript("OnMouseDown", function()
			PM.editSelected = win
			win:StartSizing(def[2])
			win.editSizing = true
		end)
		grip:SetScript("OnMouseUp", function()
			win:StopMovingOrSizing()
			win.editSizing = false
			win:SavePosition()
			win.dirty = true
			win:Refresh()
			PM:UpdateDockChain(win)
		end)
		grip:SetScript("OnUpdate", function()
			if win.editSizing then
				hud.info:SetFormattedText("Window %d - %d x %d", win.index, win:GetWidth(), win:GetHeight())
				win:Refresh()
				PM:UpdateDockChain(win)
			end
		end)
		c.grips[#c.grips + 1] = grip
	end

	win.editChrome = c
	return c
end

local function setChromeShown(win, shown)
	local c = win.editChrome
	if not c then
		if not shown then return end
		c = attachEditChrome(win)
	end
	c.border:SetShown(shown)
	c.drag:SetShown(shown)
	for _, g in ipairs(c.grips) do g:SetShown(shown) end
	if shown then
		local p = PM:DockParent(win)
		c.label:SetFormattedText("Window %d - %s%s", win.index,
			PM.modes[win.settings.mode].name,
			p and ("  |cff4db8ff(docked to " .. p.index .. ")|r") or "")
		c.label:Show()
	else
		c.label:Hide()
	end
end

--------------------------------------------------------------------------
-- Keyboard: arrow nudge, G grid toggle, Esc/Enter exit
--------------------------------------------------------------------------
local keys = CreateFrame("Frame", nil, overlay)
keys:EnableKeyboard(true)
keys:SetPropagateKeyboardInput(true)
local function setPropagate(self, v)
	if not InCombatLockdown() then
		self:SetPropagateKeyboardInput(v)
	end
end
keys:SetScript("OnKeyDown", function(self, key)
	if not PM.editMode then setPropagate(self, true) return end
	local handled = true
	local step = IsShiftKeyDown() and 10 or 1
	local win = PM.editSelected
	if key == "ESCAPE" or key == "ENTER" then
		PM:ToggleEditMode()
	elseif key == "D" then
		PM:ToggleLayoutPanel(PM.editSelected)
	elseif key == "G" then
		PM.db.edit.grid = not PM.db.edit.grid
		if PM.db.edit.grid then showGrid() else hideGrid() end
	elseif win and (key == "UP" or key == "DOWN" or key == "LEFT" or key == "RIGHT") then
		local l, b = win:GetLeft(), win:GetBottom()
		if key == "UP" then b = b + step
		elseif key == "DOWN" then b = b - step
		elseif key == "LEFT" then l = l - step
		elseif key == "RIGHT" then l = l + step end
		applyPosition(win, l, b)
		win:SavePosition()
		hud.info:SetFormattedText("Window %d - x: %d  y: %d", win.index, l, b)
	else
		handled = false
	end
	setPropagate(self, not handled)
end)

--------------------------------------------------------------------------
-- Toggle
--------------------------------------------------------------------------
function PM:ToggleEditMode()
	if InCombatLockdown() and not self.editMode then
		self:Print("Edit mode is available, but be careful editing mid-combat.")
	end
	self.editMode = not self.editMode
	if self.editMode then
		-- auto test data so you can see what you're styling
		if not self.testMode and not self.current and #self.history == 0 then
			self:SetTestMode(true)
			self.autoTest = true
		end
		overlay:Show()
		if self.db.edit.grid then showGrid() end
		self.editSelected = self.windows[1]
		for _, w in ipairs(self.windows) do
			w:Show()
			w:EnableMouse(true)
			setChromeShown(w, true)
		end
		hud.info:SetText("Click a window to select it")
	else
		if self.autoTest then
			self.autoTest = nil
			self:SetTestMode(false)
		end
		overlay:Hide()
		hideGrid()
		guideV:Hide(); guideH:Hide()
		self.editSelected = nil
		for _, w in ipairs(self.windows) do
			setChromeShown(w, false)
			w:ApplySettings()
		end
	end
end
