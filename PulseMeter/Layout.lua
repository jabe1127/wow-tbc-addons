-- PulseMeter Layout.lua
-- Docking between windows, and the panel that controls it.
--
-- A dock is a parent/child relationship with an EDGE ("right" means the child
-- sits to the right of its parent). Because the edge is stored rather than a
-- free-floating offset, a docked pair stays flush when either window is
-- resized, and re-docking to a different edge is one click.
--
-- By default a docked child takes the parent's width and height, so snapping
-- two windows together produces a matched pair rather than a ragged one.
-- Both axes are individually switchable in the dock panel.

local ADDON, ns = ...
local PM = ns.PM

local EDGES = { "right", "left", "top", "bottom" }
local EDGE_LABEL = {
	right = "Right of", left = "Left of", top = "Above", bottom = "Below",
}

-- Not every client build exposes SetEnabled on these widgets; Enable/Disable
-- always exist, so route through both.
local function setEnabled(widget, on)
	if not widget then return end
	if widget.SetEnabled then
		widget:SetEnabled(on and true or false)
	elseif on then widget:Enable()
	else widget:Disable() end
end

local function cfg()
	local e = PM.db.edit
	e.dock = e.dock or {}
	local d = e.dock
	if d.matchWidth == nil then d.matchWidth = true end
	if d.matchHeight == nil then d.matchHeight = true end
	if d.showPanel == nil then d.showPanel = true end
	d.gap = d.gap or 0
	return d
end
PM.DockConfig = cfg

--------------------------------------------------------------------------
-- Relationships
--------------------------------------------------------------------------
function PM:DockedChildren(win)
	local out = {}
	for _, w in ipairs(self.windows) do
		if w ~= win and w.settings.anchorTo == win.index then out[#out + 1] = w end
	end
	return out
end

function PM:DockParent(win)
	local a = win.settings.anchorTo
	return a and self.windows[a] or nil
end

-- Per-dock overrides fall back to the global defaults.
local function dockOpt(s, key)
	local d = cfg()
	if s.dockOverride and s.dockOverride[key] ~= nil then return s.dockOverride[key] end
	return d[key]
end
PM.DockOpt = dockOpt

function PM:SetDockOpt(win, key, value)
	local s = win.settings
	s.dockOverride = s.dockOverride or {}
	s.dockOverride[key] = value
	self:ApplyDock(win)
end

--------------------------------------------------------------------------
-- Applying a dock: size first, then anchor
--------------------------------------------------------------------------
function PM:ApplyDock(win)
	local s = win.settings
	local parent = self:DockParent(win)
	if not parent or parent == win then return end

	local gap = dockOpt(s, "gap") or 0
	if dockOpt(s, "matchWidth") then s.width = math.floor(parent:GetWidth() + 0.5) end
	if dockOpt(s, "matchHeight") then s.height = math.floor(parent:GetHeight() + 0.5) end
	win:SetSize(s.width, s.height)

	win:ClearAllPoints()
	local edge = s.dockEdge or "right"
	if edge == "right" then
		win:SetPoint("TOPLEFT", parent, "TOPRIGHT", gap, 0)
	elseif edge == "left" then
		win:SetPoint("TOPRIGHT", parent, "TOPLEFT", -gap, 0)
	elseif edge == "bottom" then
		win:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -gap)
	else -- top
		win:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", 0, gap)
	end

	win.dirty = true
	win:Refresh()
	-- a resized child moves its own children
	for _, kid in ipairs(self:DockedChildren(win)) do self:ApplyDock(kid) end
end

-- Re-flow a whole chain after the parent moves or resizes.
function PM:UpdateDockChain(win)
	for _, kid in ipairs(self:DockedChildren(win)) do
		self:ApplyDock(kid)
	end
end

function PM:DockTo(child, parent, edge, quiet)
	if not child or not parent or child == parent then return end
	local s = child.settings
	s.anchorTo = parent.index
	s.dockEdge = edge or "right"
	s.relX, s.relY = nil, nil
	self:ApplyDock(child)
	child:SavePosition()
	if not quiet then
		self:Print(("Window %d docked %s window %d."):format(
			child.index, (EDGE_LABEL[s.dockEdge] or "next to"):lower(), parent.index))
		if cfg().showPanel then self:ToggleLayoutPanel(child, true) end
	end
end

function PM:UndockWindow(win)
	local s = win.settings
	if not s.anchorTo then return end
	local l, b = win:GetLeft(), win:GetBottom()
	s.anchorTo, s.dockEdge, s.relX, s.relY = nil, nil, nil, nil
	win:ClearAllPoints()
	win:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l or 300, b or 300)
	win:SavePosition()
	self:Print("Window " .. win.index .. " undocked.")
	if panel and panel:IsShown() then self:RefreshLayoutPanel() end
end

-- Swap a docked pair's roles, keeping them in the same place on screen.
function PM:SwapDock(child)
	local parent = self:DockParent(child)
	if not parent then return end
	local grand = parent.settings.anchorTo
	local edge = child.settings.dockEdge or "right"
	local opposite = { right = "left", left = "right", top = "bottom", bottom = "top" }
	local pl, pb = parent:GetLeft(), parent:GetBottom()

	child.settings.anchorTo, child.settings.dockEdge = grand, parent.settings.dockEdge
	parent.settings.anchorTo, parent.settings.dockEdge = child.index, opposite[edge]
	if not grand then
		child:ClearAllPoints()
		child:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", pl or 300, pb or 300)
		child:SavePosition()
	else
		self:ApplyDock(child)
	end
	self:ApplyDock(parent)
	self:RefreshLayoutPanel()
end

--------------------------------------------------------------------------
-- Edge detection for a dropped window
--------------------------------------------------------------------------
local function inChain(other, target, depth)
	if depth > 10 then return true end
	local a = other.settings.anchorTo
	if not a then return false end
	if a == target.index then return true end
	local nxt = PM.windows[a]
	return nxt and inChain(nxt, target, depth + 1) or false
end

-- Which edge of `other` is `win` sitting against, if any?
function PM:DetectDockEdge(win, other, tol)
	tol = tol or 12
	local L, B = win:GetLeft(), win:GetBottom()
	local oL, oB = other:GetLeft(), other:GetBottom()
	if not L or not oL then return nil end
	local R, T = L + win:GetWidth(), B + win:GetHeight()
	local oR, oT = oL + other:GetWidth(), oB + other:GetHeight()

	local vOverlap = (B < oT) and (T > oB)
	local hOverlap = (L < oR) and (R > oL)

	local best, bestD
	local function try(edge, d, ok)
		if ok and math.abs(d) <= tol and (not bestD or math.abs(d) < bestD) then
			best, bestD = edge, math.abs(d)
		end
	end
	try("right", L - oR, vOverlap)
	try("left", R - oL, vOverlap)
	try("bottom", T - oB, hOverlap)
	try("top", B - oT, hOverlap)
	return best
end

-- Called when a drag ends: dock to whichever window we were dropped against.
function PM:TryLink(win)
	if not win:GetLeft() then return end
	for _, other in ipairs(self.windows) do
		if other ~= win and other:IsShown() and not inChain(other, win, 0) then
			local edge = self:DetectDockEdge(win, other)
			if edge then
				self:DockTo(win, other, edge)
				return true
			end
		end
	end
end

--------------------------------------------------------------------------
-- Dock panel
--------------------------------------------------------------------------
local PANEL_W = 280
local panel

local function row(parent, y, h)
	local f = CreateFrame("Frame", nil, parent)
	f:SetPoint("TOPLEFT", 10, y)
	f:SetPoint("TOPRIGHT", -10, y)
	f:SetHeight(h or 20)
	return f
end

local function chip(parent)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetHeight(21)
	b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.text:SetPoint("CENTER")
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
	b:SetScript("OnEnter", function(self)
		if not self.active then self:SetBackdropColor(0.20, 0.24, 0.32, 1) end
	end)
	b:SetScript("OnLeave", function(self)
		if not self.active then self:SetBackdropColor(0.11, 0.12, 0.15, 1) end
	end)
	b:SetActive(false)
	return b
end

local function buildPanel()
	panel = CreateFrame("Frame", "PulseMeterLayoutPanel", UIParent, "BackdropTemplate")
	panel:SetSize(PANEL_W, 340)
	panel:SetPoint("CENTER", 260, 0)
	panel:SetFrameStrata("FULLSCREEN_DIALOG")
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:SetClampedToScreen(true)
	panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	panel:SetBackdropColor(0.05, 0.055, 0.07, 0.98)
	panel:SetBackdropBorderColor(0.28, 0.32, 0.40, 1)
	panel:Hide()
	table.insert(UISpecialFrames, "PulseMeterLayoutPanel")

	local drag = CreateFrame("Frame", nil, panel)
	drag:SetPoint("TOPLEFT"); drag:SetPoint("TOPRIGHT")
	drag:SetHeight(26)
	drag:EnableMouse(true)
	drag:SetFrameLevel(panel:GetFrameLevel() + 1)
	drag:SetScript("OnMouseDown", function() panel:StartMoving() end)
	drag:SetScript("OnMouseUp", function() panel:StopMovingOrSizing() end)

	panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	panel.title:SetPoint("TOPLEFT", 10, -8)
	panel.title:SetText("|cff4db8ffDocking|r")

	local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 1, 2)
	close:SetFrameLevel(panel:GetFrameLevel() + 10)

	panel.sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.sub:SetPoint("TOPLEFT", 10, -28)
	panel.sub:SetPoint("TOPRIGHT", -10, -28)
	panel.sub:SetJustifyH("LEFT")

	panel.edgeLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	panel.edgeLabel:SetPoint("TOPLEFT", 10, -60)
	panel.edgeLabel:SetText("|cff7d8794PLACEMENT|r")

	panel.edges = {}
	for i, e in ipairs(EDGES) do
		local b = chip(panel)
		local w = (PANEL_W - 26) / 2
		b:SetWidth(w)
		b:SetPoint("TOPLEFT", 10 + ((i - 1) % 2) * (w + 6), -78 - math.floor((i - 1) / 2) * 24)
		b.text:SetText(EDGE_LABEL[e] .. " parent")
		b.edge = e
		b:SetScript("OnClick", function()
			local win = panel.win
			if win and win.settings.anchorTo then
				win.settings.dockEdge = e
				PM:ApplyDock(win)
				PM:RefreshLayoutPanel()
			end
		end)
		panel.edges[i] = b
	end

	panel.sizeLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	panel.sizeLabel:SetPoint("TOPLEFT", 10, -132)
	panel.sizeLabel:SetText("|cff7d8794MATCH THE PARENT|r")

	local function check(label, x, y, get, set)
		local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		cb:SetPoint("TOPLEFT", x, y)
		cb:SetSize(20, 20)
		cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
		cb.text:SetText(label)
		cb.get, cb.set = get, set
		cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
		return cb
	end
	panel.cbW = check("Same width", 8, -150,
		nil, function(v) if panel.win then PM:SetDockOpt(panel.win, "matchWidth", v) end end)
	panel.cbH = check("Same height", 8 + (PANEL_W - 26) / 2, -150,
		nil, function(v) if panel.win then PM:SetDockOpt(panel.win, "matchHeight", v) end end)

	panel.gap = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
	panel.gap:SetPoint("TOPLEFT", 14, -192)
	panel.gap:SetWidth(PANEL_W - 40)
	panel.gap:SetMinMaxValues(0, 20)
	panel.gap:SetValueStep(1)
	panel.gap:SetObeyStepOnDrag(true)
	if panel.gap.Low then panel.gap.Low:SetText("") end
	if panel.gap.High then panel.gap.High:SetText("") end
	if panel.gap.Text then panel.gap.Text:SetText("") end
	panel.gapLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.gapLabel:SetPoint("BOTTOMLEFT", panel.gap, "TOPLEFT", 0, 3)
	panel.gap:SetScript("OnValueChanged", function(self, v)
		v = math.floor(v + 0.5)
		panel.gapLabel:SetFormattedText("Gap: |cff4db8ff%d|r px", v)
		if panel.win and not panel.loading then PM:SetDockOpt(panel.win, "gap", v) end
	end)

	local function button(label, x, y, w, fn)
		local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
		b:SetSize(w, 22)
		b:SetPoint("TOPLEFT", x, y)
		b:SetText(label)
		b:SetScript("OnClick", fn)
		return b
	end
	local half = (PANEL_W - 26) / 2
	panel.btnEqualize = button("Match now", 10, -226, half, function()
		if panel.win then PM:ApplyDock(panel.win) end
	end)
	panel.btnSwap = button("Swap order", 16 + half, -226, half, function()
		if panel.win then PM:SwapDock(panel.win) end
	end)
	panel.btnUndock = button("Undock", 10, -252, half, function()
		if panel.win then PM:UndockWindow(panel.win); PM:RefreshLayoutPanel() end
	end)
	panel.btnEdit = button("Edit mode", 16 + half, -252, half, function()
		PM:ToggleEditMode()
	end)

	panel.cbAuto = check("Open this panel when windows snap", 8, -282,
		nil, function(v) cfg().showPanel = v end)

	panel.list = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	panel.list:SetPoint("TOPLEFT", 12, -308)
	panel.list:SetPoint("TOPRIGHT", -12, -308)
	panel.list:SetJustifyH("LEFT")

	-- pick which window the panel is editing
	panel.picker = {}
end

function PM:RefreshLayoutPanel()
	if not panel then return end
	local win = panel.win
	if not win or not win:IsShown() then
		win = self.windows[1]
		panel.win = win
	end
	if not win then return end
	local s = win.settings
	local parent = self:DockParent(win)

	panel.loading = true
	panel.title:SetText("|cff4db8ffDocking|r  |cff888888- window " .. win.index .. "|r")

	if parent then
		panel.sub:SetText(("Window %d is docked %s window %d."):format(
			win.index, (EDGE_LABEL[s.dockEdge or "right"] or "beside"):lower(), parent.index))
	else
		panel.sub:SetText("|cff888888Window " .. win.index .. " is free-floating. Drag it against\n"
			.. "another window in edit mode to dock them.|r")
	end

	for _, b in ipairs(panel.edges) do
		b:SetActive(parent and s.dockEdge == b.edge)
		setEnabled(b, parent)
		b:SetAlpha(parent and 1 or 0.4)
	end

	panel.cbW:SetChecked(dockOpt(s, "matchWidth"))
	panel.cbH:SetChecked(dockOpt(s, "matchHeight"))
	setEnabled(panel.cbW, parent)
	setEnabled(panel.cbH, parent)
	panel.gap:SetValue(dockOpt(s, "gap") or 0)
	panel.gapLabel:SetFormattedText("Gap: |cff4db8ff%d|r px", dockOpt(s, "gap") or 0)
	panel.cbAuto:SetChecked(cfg().showPanel)

	setEnabled(panel.btnUndock, parent)
	setEnabled(panel.btnSwap, parent)
	setEnabled(panel.btnEqualize, parent)

	-- overview of every dock in play
	local lines = {}
	for _, w in ipairs(self.windows) do
		local p = self:DockParent(w)
		if p then
			lines[#lines + 1] = ("window %d  %s  window %d"):format(
				w.index, (EDGE_LABEL[w.settings.dockEdge or "right"] or "-"):lower(), p.index)
		end
	end
	panel.list:SetText(#lines > 0 and ("|cff7d8794LINKS|r\n" .. table.concat(lines, "\n"))
		or "|cff7d8794No windows are docked.|r")

	panel.loading = false
end

function PM:ToggleLayoutPanel(win, forceShow)
	if not panel then buildPanel() end
	if win then panel.win = win end
	if panel:IsShown() and not forceShow then
		panel:Hide()
		return
	end
	panel.win = panel.win or self.windows[1]
	self:RefreshLayoutPanel()
	panel:Show()
end
