-- PulseMeter Skins.lua
-- Texture & font registries (with optional LibSharedMedia pickup), color helpers, skin presets.

local ADDON, ns = ...
local PM = ns.PM

local TEXPATH = "Interface\\AddOns\\PulseMeter\\textures\\"

PM.textures = {
	["flat"]     = TEXPATH .. "flat",
	["gradient"] = TEXPATH .. "gradient",
	["glossy"]   = TEXPATH .. "glossy",
	["minimal"]  = TEXPATH .. "minimal",
	["smooth"]   = TEXPATH .. "smooth",
	["blizzard"] = "Interface\\TargetingFrame\\UI-StatusBar",
}

PM.fonts = {
	["Friz Quadrata"] = "Fonts\\FRIZQT__.TTF",
	["Arial Narrow"]  = "Fonts\\ARIALN.TTF",
	["Skurri"]        = "Fonts\\skurri.ttf",
	["Morpheus"]      = "Fonts\\MORPHEUS.ttf",
}

-- Pick up LibSharedMedia if any other addon ships it
function PM:ScanSharedMedia()
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	if not LSM then return end
	for name, path in pairs(LSM:HashTable("statusbar")) do
		if not self.textures[name] then self.textures[name] = path end
	end
	for name, path in pairs(LSM:HashTable("font")) do
		if not self.fonts[name] then self.fonts[name] = path end
	end
end

function PM:GetTexture(key)
	return self.textures[key] or self.textures["gradient"]
end

function PM:GetFont(key)
	return self.fonts[key] or self.fonts["Friz Quadrata"]
end

--------------------------------------------------------------------------
-- Class colors (TBC: no Death Knight etc.)
--------------------------------------------------------------------------
function PM:ClassColor(class)
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then return c.r, c.g, c.b end
	return 0.6, 0.6, 0.6
end

--------------------------------------------------------------------------
-- Skin presets: one click applies a full look to a window
--------------------------------------------------------------------------
PM.skinPresets = {
	{
		name = "Pulse (default)",
		apply = {
			texture = "gradient", font = "Friz Quadrata", fontSize = 11, fontOutline = "OUTLINE",
			barHeight = 18, barSpacing = 1, classColors = true,
			bgColor = { 0, 0, 0, 0.45 }, titleColor = { 0.10, 0.10, 0.12, 0.90 },
		},
	},
	{
		name = "Minimal Dark",
		apply = {
			texture = "minimal", font = "Arial Narrow", fontSize = 11, fontOutline = "",
			barHeight = 15, barSpacing = 0, classColors = true,
			bgColor = { 0.04, 0.04, 0.05, 0.85 }, titleColor = { 0.04, 0.04, 0.05, 1 },
		},
	},
	{
		name = "Glass",
		apply = {
			texture = "glossy", font = "Friz Quadrata", fontSize = 12, fontOutline = "OUTLINE",
			barHeight = 22, barSpacing = 2, classColors = true,
			bgColor = { 0.05, 0.08, 0.12, 0.35 }, titleColor = { 0.05, 0.08, 0.12, 0.70 },
		},
	},
	{
		name = "Recount Classic",
		apply = {
			texture = "blizzard", font = "Friz Quadrata", fontSize = 10, fontOutline = "",
			barHeight = 16, barSpacing = 1, classColors = true,
			bgColor = { 0, 0, 0, 0.6 }, titleColor = { 0.6, 0.1, 0.1, 0.9 },
		},
	},
	{
		name = "Clean Light",
		apply = {
			texture = "smooth", font = "Arial Narrow", fontSize = 11, fontOutline = "",
			barHeight = 18, barSpacing = 2, classColors = true,
			bgColor = { 0.9, 0.9, 0.9, 0.25 }, titleColor = { 0.85, 0.85, 0.88, 0.9 },
		},
	},
}

function PM:ApplySkinPreset(win, presetIndex)
	local preset = self.skinPresets[presetIndex]
	if not preset then return end
	for k, v in pairs(preset.apply) do
		win.settings[k] = (type(v) == "table") and ns.deepcopy(v) or v
	end
	win:ApplySettings()
	self:Print("Applied skin: " .. preset.name)
end
