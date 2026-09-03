-- Silk : Core ------------------------------------------------------------
-- Saved variables, defaults, palette, the capsule factory that gives every
-- element its rounded silhouette, the shared animation driver, and the
-- live-apply pipeline.

local ADDON, ns = ...
ns.version = "2.5.1"

ns.MEDIA = "Interface\\AddOns\\Silk\\Media\\"

ns.CAPS = {
    capsule = { ns.MEDIA .. "cap_full_l.tga", ns.MEDIA .. "cap_full_r.tga" },
    soft    = { ns.MEDIA .. "cap_soft_l.tga", ns.MEDIA .. "cap_soft_r.tga" },
    flat    = { ns.MEDIA .. "cap_flat_l.tga", ns.MEDIA .. "cap_flat_r.tga" },
}

ns.TEX = {
    circle    = ns.MEDIA .. "circle.tga",
    ring      = ns.MEDIA .. "ring.tga",
    ringGlow  = ns.MEDIA .. "ring_glow.tga",
    iconMask  = ns.MEDIA .. "icon_mask.tga",
    iconRing  = ns.MEDIA .. "icon_ring.tga",
    gloss     = ns.MEDIA .. "gloss.tga",
    gem       = ns.MEDIA .. "gem.tga",
    spark     = ns.MEDIA .. "spark.tga",
    dot       = ns.MEDIA .. "dot.tga",
    panelMask = ns.MEDIA .. "panel_mask.tga",
    fillSatin  = ns.MEDIA .. "fill_satin.tga",
    fillGlass  = ns.MEDIA .. "fill_glass.tga",
    fillVelvet = ns.MEDIA .. "fill_velvet.tga",
    res        = ns.MEDIA .. "res.tga",
}

-- silhouette-matched drop shadows, keyed by corner style
ns.SHADOW = {
    capsule = ns.MEDIA .. "shadow_capsule.tga",
    soft    = ns.MEDIA .. "shadow_soft.tga",
    flat    = ns.MEDIA .. "shadow_flat.tga",
}

-- bar surface finishes: grayscale, tinted by the bar's own colour
ns.FINISH = {
    flat   = false,               -- plain colour, no texture
    satin  = ns.TEX.fillSatin,
    glass  = ns.TEX.fillGlass,
    velvet = ns.TEX.fillVelvet,
}

-- defaults ---------------------------------------------------------------

-- text element. "" on font/outline means "inherit the global setting".
local function T(p, x, y)
    return { p, x, y, size = 0, show = true, font = "", outline = "",
             colorMode = "auto", color = { r = 1, g = 1, b = 1 }, bg = "auto" }
end

-- group cell text: x, y offset from its built-in anchor
local function G(x, y)
    return { x, y, size = 0, show = true, font = "", outline = "",
             colorMode = "auto", color = { r = 1, g = 1, b = 1 }, bg = "auto" }
end

-- aura block. Buffs and debuffs each get an offset, an optional detached
-- position, and their own grow direction, so either can be flung anywhere.
local function A(t, px, py)
    t.spacing = 4
    t.bx, t.by, t.dx, t.dy = 0, 0, 0, 0
    t.bDetach, t.bPos = false, { px, py - 70 }
    t.dDetach, t.dPos = false, { px, py + 70 }
    t.bGrowX, t.bGrowY = "right", "down"
    t.dGrowX, t.dGrowY = "right", "up"
    t.bSize, t.bPerRow = 0, 0      -- 0 = inherit the shared size / per row
    return t
end

ns.defaults = {
    scale       = 1.0,
    font        = "Fonts\\ARIALN.TTF",
    fontSize    = 12,
    outline     = "OUTLINE",     -- NONE | OUTLINE | THICK
    monochrome  = false,
    shadow      = true,
    shadowX     = 1,
    shadowY     = -1,
    textBg      = false,
    textBgAlpha = 0.55,
    textBgPad   = 5,
    shadowColor = { r = 0, g = 0, b = 0, a = 0.85 },
    corner      = "capsule",     -- capsule | soft | flat
    colorMode   = "class",       -- class | custom | vitality
    customColor = { r = 0.36, g = 0.68, b = 1.00 },
    accent      = { r = 0.61, g = 0.90, b = 1.00 },
    bgAlpha     = 0.50,
    troughAlpha = 1.0,
    barFinish   = "satin",       -- flat | satin | glass | velvet
    frameShadow = true,
    frameShadowSize  = 7,
    frameShadowAlpha = 0.55,
    topline     = 0.10,          -- 1px light edge along the top of each bar
    borderSize  = 1,
    borderMode  = "dark",        -- dark | class | custom
    borderColor = { r = 0, g = 0, b = 0 },
    borderAlpha = 0.85,
    bgMode      = "match",       -- match | dark | custom
    bgTint      = 0.14,
    bgColor     = { r = 0.055, g = 0.062, b = 0.078 },
    lossColor   = { r = 1.00, g = 0.45, b = 0.38 },
    gloss       = 0.32,
    smooth      = 12,
    ghost       = true,
    hpFormat    = "both",        -- value | percent | both
    classIconPortraits = false,
    hideBlizzardBuffs  = false,

    frames = {
        player = {
            swing = { melee = true, ranged = true, h = 14, hideIdle = true, idleDelay = 5,
                      order = "auto",   -- auto | melee | ranged  (which bar is on top)
                      detach = false, pos = { -300, -330 }, w = 0 },
            castbar = true, castMode = "below", castH = 18, castIcon = true, castTime = true,
            castDetach = false, castPos = { -300, -292 }, castW = 0,
            powerDetach = false, powerPos = { -300, -280 }, powerW = 0, powerH = 0,
            enabled = true, w = 232, h = 42, portrait = true,
            pos = { -300, -235 },
            auras = A({ debuffs = true, buffs = false, size = 22, perRow = 8, maxShown = 16, onlyMine = false }, -300, -235),
            texts = { name = T("TOPLEFT", 12, -6), hp = T("TOPRIGHT", -12, -6),
                      power = T("BOTTOMRIGHT", -12, 3), level = T("BOTTOMLEFT", 12, 3) },
        },
        pet = {
            powerDetach = false, powerPos = { -330, -320 }, powerW = 0, powerH = 0,
            auras = A({ debuffs = false, buffs = false, size = 18, perRow = 6, maxShown = 8, onlyMine = false }, -330, -290),
            enabled = true, w = 172, h = 30, portrait = true, mood = true,
            pos = { -330, -290 },
            texts = { name = T("TOPLEFT", 9, -5), hp = T("TOPRIGHT", -9, -5),
                      power = T("BOTTOMRIGHT", -9, 2), level = T("BOTTOMLEFT", 9, 2) },
        },
        target = {
            swing = { enemy = true, h = 12, idleDelay = 5,
                      detach = false, pos = { 300, -330 }, w = 0 },
            castbar = true, castMode = "inside", castH = 18, castIcon = true, castTime = true,
            castDetach = false, castPos = { 300, -292 }, castW = 0,
            powerDetach = false, powerPos = { 300, -280 }, powerW = 0, powerH = 0,
            enabled = true, w = 232, h = 42, portrait = true, combo = true,
            pos = { 300, -235 },
            auras = A({ debuffs = true, buffs = true, size = 24, perRow = 8, maxShown = 16, onlyMine = false }, 300, -235),
            texts = { name = T("TOPLEFT", 12, -6), hp = T("TOPRIGHT", -12, -6),
                      power = T("BOTTOMRIGHT", -12, 3), level = T("BOTTOMLEFT", 12, 3) },
        },
        targettarget = {
            powerDetach = false, powerPos = { 566, -330 }, powerW = 0, powerH = 0,
            enabled = true, w = 152, h = 26, portrait = false,
            pos = { 566, -300 },
            auras = A({ debuffs = false, buffs = false, size = 18, perRow = 6, maxShown = 6, onlyMine = false }, 566, -300),
            texts = { name = T("TOPLEFT", 9, -4), hp = T("TOPRIGHT", -9, -4),
                      power = T("BOTTOMRIGHT", -9, 2), level = T("BOTTOMLEFT", 9, 2) },
        },
        focus = {
            swing = { enemy = false, h = 12, idleDelay = 5,
                      detach = false, pos = { -640, -200 }, w = 0 },
            castbar = true, castMode = "inside", castH = 18, castIcon = true, castTime = true,
            castDetach = false, castPos = { -640, -160 }, castW = 0,
            powerDetach = false, powerPos = { -620, -120 }, powerW = 0, powerH = 0,
            enabled = true, w = 192, h = 32, portrait = true,
            pos = { -620, -80 },
            auras = A({ debuffs = true, buffs = false, size = 20, perRow = 6, maxShown = 12, onlyMine = false }, -620, -80),
            texts = { name = T("TOPLEFT", 9, -5), hp = T("TOPRIGHT", -9, -5),
                      power = T("BOTTOMRIGHT", -9, 2), level = T("BOTTOMLEFT", 9, 2) },
        },
    },

    party = {
        enabled = true, threat = true, w = 190, h = 34, spacing = 10, power = true,
        debuffIcons = 3, range = true, hideInRaid = true,
        orient = "vertical",         -- vertical | horizontal
        growX = "right", growY = "down",
        pos = { -860, 150 },
        texts = { name = G(0, 0), status = G(0, 0) },
    },
    raid = {
        enabled = true, w = 68, h = 34, spacing = 4, groupsPerRow = 8,
        text = "percent",       -- none | percent | deficit
        power = false, dispel = true, range = true, threat = true,
        resBadge = true,
        nameLen = 0,             -- 0 = full names
        rangeAlpha = 0.45,
        fontDelta = 0,
        growX = "right", growY = "down",
        pos = { -860, -130 },
        texts = { name = G(0, 0), status = G(0, 0) },
    },
}

-- palette ----------------------------------------------------------------

ns.palette = {
    charcoal = { 0.055, 0.062, 0.078 },
    text     = { 0.92, 0.94, 0.97 },
    grey     = { 0.62, 0.66, 0.72 },
    reaction = {
        friendly = { 0.36, 0.83, 0.55 },
        neutral  = { 0.96, 0.79, 0.36 },
        hostile  = { 0.90, 0.36, 0.38 },
        tapped   = { 0.55, 0.57, 0.62 },
        dead     = { 0.45, 0.47, 0.52 },
    },
    power = {
        MANA    = { 0.35, 0.62, 1.00 },
        RAGE    = { 0.90, 0.33, 0.36 },
        ENERGY  = { 1.00, 0.87, 0.40 },
        FOCUS   = { 1.00, 0.62, 0.32 },
        default = { 0.65, 0.70, 0.78 },
    },
    happiness = {
        [3] = { 0.36, 0.88, 0.52 },
        [2] = { 1.00, 0.76, 0.32 },
        [1] = { 1.00, 0.36, 0.30 },
    },
    vitality = {
        hi  = { 0.36, 0.85, 0.52 },
        mid = { 0.97, 0.78, 0.32 },
        lo  = { 0.92, 0.31, 0.33 },
    },
    loss  = { 1.00, 0.45, 0.38 },
    rank  = {
        elite = { 1.00, 0.78, 0.26 },
        rare  = { 0.76, 0.83, 0.96 },
        boss  = { 0.95, 0.28, 0.33 },
    },
}

-- small helpers ----------------------------------------------------------

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff9be8ffSilk|r  " .. tostring(msg))
end

function ns.Short(v)
    v = v or 0
    if v >= 1e6 then
        return string.format("%.1fm", v / 1e6)
    elseif v >= 1e4 then
        return string.format("%.0fk", v / 1e3)
    elseif v >= 1e3 then
        return string.format("%.1fk", v / 1e3)
    end
    return tostring(math.floor(v + 0.5))
end

local function lerp(a, b, t) return a + (b - a) * t end

function ns.Mix(c1, c2, t)
    return lerp(c1[1], c2[1], t), lerp(c1[2], c2[2], t), lerp(c1[3], c2[3], t)
end

function ns.ClassColor(unit)
    local _, class = UnitClass(unit)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.8, 0.8, 0.8
end

function ns.ReactionColor(unit)
    local p = ns.palette.reaction
    local r = UnitReaction(unit, "player")
    if not r then return p.neutral[1], p.neutral[2], p.neutral[3] end
    if r >= 5 then return p.friendly[1], p.friendly[2], p.friendly[3] end
    if r == 4 then return p.neutral[1], p.neutral[2], p.neutral[3] end
    return p.hostile[1], p.hostile[2], p.hostile[3]
end

function ns.HealthColor(unit, pct)
    local db, p = ns.db, ns.palette
    if UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) then
        return p.reaction.dead[1], p.reaction.dead[2], p.reaction.dead[3]
    end
    if db.colorMode == "custom" then
        local c = db.customColor
        return c.r, c.g, c.b
    elseif db.colorMode == "vitality" then
        pct = pct or 1
        if pct > 0.5 then
            return ns.Mix(p.vitality.mid, p.vitality.hi, (pct - 0.5) * 2)
        end
        return ns.Mix(p.vitality.lo, p.vitality.mid, pct * 2)
    end
    if UnitIsPlayer(unit) then return ns.ClassColor(unit) end
    if UnitIsTapDenied and UnitIsTapDenied(unit) then
        return p.reaction.tapped[1], p.reaction.tapped[2], p.reaction.tapped[3]
    end
    return ns.ReactionColor(unit)
end

function ns.PowerColor(unit)
    local _, tok = UnitPowerType(unit)
    local c = ns.palette.power[tok] or ns.palette.power.default
    return c[1], c[2], c[3]
end

function ns.NameColor(unit)
    if UnitIsPlayer(unit) then return ns.ClassColor(unit) end
    local t = ns.palette.text
    return t[1], t[2], t[3]
end

-- fonts ------------------------------------------------------------------
-- WoW gives addons no way to list a directory, so "every font available" is
-- assembled three ways: probe a wide list of known paths, harvest the path
-- out of every Font object the client or any addon has registered, and take
-- whatever SharedMedia offers. Anything that fails to load is dropped.

local BUNDLED = "Interface\\AddOns\\Silk\\Media\\Fonts\\"

-- Fonts Silk ships itself. WoW installs only a handful of usable typefaces
-- and gives addons no way to read a directory, so the only way to offer a
-- real choice is to bundle the files. All open licence (OFL / Apache / UFL).
local PACKAGED = {
    { "Anton", BUNDLED .. "Anton.ttf" },
    { "Archivo Narrow", BUNDLED .. "ArchivoNarrow.ttf" },
    { "Assistant", BUNDLED .. "Assistant.ttf" },
    { "Audiowide", BUNDLED .. "Audiowide.ttf" },
    { "Barlow Condensed", BUNDLED .. "BarlowCondensed.ttf" },
    { "Bebas Neue", BUNDLED .. "BebasNeue.ttf" },
    { "Big Shoulders", BUNDLED .. "BigShoulders.ttf" },
    { "Cabin", BUNDLED .. "Cabin.ttf" },
    { "Chakra Petch", BUNDLED .. "ChakraPetch.ttf" },
    { "Comfortaa", BUNDLED .. "Comfortaa.ttf" },
    { "DM Sans", BUNDLED .. "DMSans.ttf" },
    { "Dosis", BUNDLED .. "Dosis.ttf" },
    { "Electrolize", BUNDLED .. "Electrolize.ttf" },
    { "Encode Sans Condensed", BUNDLED .. "EncodeSansCondensed.ttf" },
    { "Exo 2", BUNDLED .. "Exo2.ttf" },
    { "Figtree", BUNDLED .. "Figtree.ttf" },
    { "Fira Sans Condensed", BUNDLED .. "FiraSansCondensed.ttf" },
    { "Heebo", BUNDLED .. "Heebo.ttf" },
    { "IBM Plex Sans", BUNDLED .. "IBMPlexSans.ttf" },
    { "Inter", BUNDLED .. "Inter.ttf" },
    { "Josefin Sans", BUNDLED .. "JosefinSans.ttf" },
    { "Jost", BUNDLED .. "Jost.ttf" },
    { "Karla", BUNDLED .. "Karla.ttf" },
    { "Khand", BUNDLED .. "Khand.ttf" },
    { "Lato", BUNDLED .. "Lato.ttf" },
    { "Lexend", BUNDLED .. "Lexend.ttf" },
    { "Manrope", BUNDLED .. "Manrope.ttf" },
    { "Montserrat", BUNDLED .. "Montserrat.ttf" },
    { "Mulish", BUNDLED .. "Mulish.ttf" },
    { "News Cycle", BUNDLED .. "NewsCycle.ttf" },
    { "Noto Sans", BUNDLED .. "NotoSans.ttf" },
    { "Nunito Sans", BUNDLED .. "NunitoSans.ttf" },
    { "Open Sans", BUNDLED .. "OpenSans.ttf" },
    { "Orbitron", BUNDLED .. "Orbitron.ttf" },
    { "Oswald", BUNDLED .. "Oswald.ttf" },
    { "Outfit", BUNDLED .. "Outfit.ttf" },
    { "Overpass", BUNDLED .. "Overpass.ttf" },
    { "Oxanium", BUNDLED .. "Oxanium.ttf" },
    { "Play", BUNDLED .. "Play.ttf" },
    { "Public Sans", BUNDLED .. "PublicSans.ttf" },
    { "Quantico", BUNDLED .. "Quantico.ttf" },
    { "Rajdhani", BUNDLED .. "Rajdhani.ttf" },
    { "Raleway", BUNDLED .. "Raleway.ttf" },
    { "Roboto", BUNDLED .. "Roboto.ttf" },
    { "Roboto Condensed", BUNDLED .. "RobotoCondensed.ttf" },
    { "Rubik", BUNDLED .. "Rubik.ttf" },
    { "Russo One", BUNDLED .. "RussoOne.ttf" },
    { "Saira Condensed", BUNDLED .. "SairaCondensed.ttf" },
    { "Sora", BUNDLED .. "Sora.ttf" },
    { "Space Grotesk", BUNDLED .. "SpaceGrotesk.ttf" },
    { "Teko", BUNDLED .. "Teko.ttf" },
    { "Titillium Web", BUNDLED .. "TitilliumWeb.ttf" },
    { "Ubuntu Condensed", BUNDLED .. "UbuntuCondensed.ttf" },
    { "Work Sans", BUNDLED .. "WorkSans.ttf" },
    { "Yanone Kaffeesatz", BUNDLED .. "YanoneKaffeesatz.ttf" },
}

local BUILTIN = {
    { "Arial Narrow",   "Fonts\\ARIALN.TTF" },
    { "Friz Quadrata",  "Fonts\\FRIZQT__.TTF" },
    { "Skurri",         "Fonts\\SKURRI.TTF" },
    { "Morpheus",       "Fonts\\MORPHEUS.TTF" },
    { "Nimrod",         "Fonts\\NIM_____.TTF" },
    { "Bookman",        "Fonts\\bLEI00D.TTF" },
    { "2002",           "Fonts\\2002.TTF" },
    { "2002 Bold",      "Fonts\\2002B.TTF" },
    -- locale variants: present on some clients, probed away on others
    { "Friz Quadrata (CYR)", "Fonts\\FRIZQT___CYR.TTF" },
    { "Morpheus (CYR)",      "Fonts\\MORPHEUS_CYR.TTF" },
    { "Skurri (CYR)",        "Fonts\\SKURRI_CYR.TTF" },
    { "AR Hei",         "Fonts\\ARHei.ttf" },
    { "AR Kai",         "Fonts\\ARKai_T.ttf" },
    { "AR Kai Combat",  "Fonts\\ARKai_C.ttf" },
    { "AR CJK Hei",     "Fonts\\bHEI00M.ttf" },
    { "AR CJK Hei Bold","Fonts\\bHEI01B.ttf" },
    { "AR CJK Kai",     "Fonts\\bKAI00M.ttf" },
    { "K Damage",       "Fonts\\K_Damage.TTF" },
    { "K Pagetext",     "Fonts\\K_Pagetext.TTF" },
}

local function prettyFontName(path)
    local file = path:match("([^\\/]+)$") or path
    file = file:gsub("%.[Tt][Tt][FfCc]$", ""):gsub("%.[Oo][Tt][Ff]$", "")
    file = file:gsub("[_]+", " "):gsub("%s+", " ")
    file = file:gsub("^%s*(.-)%s*$", "%1")
    if file == "" then return path end
    return file
end

local probe
local fontCache

function ns.FontList(rebuild)
    if fontCache and not rebuild then return fontCache end
    if not probe then
        probe = CreateFrame("Frame"):CreateFontString(nil, "BACKGROUND")
    end
    local list, seen, seenName = {}, {}, {}
    local function add(name, path)
        if type(path) ~= "string" or path == "" or seen[path] then return end
        -- the same face often exists at several paths (Silk's bundled copy,
        -- SharedMedia's, another addon's); one entry per name is enough
        local key = tostring(name):lower():gsub("%s+", " ")
        if seenName[key] then return end
        if probe:SetFont(path, 12, "") == false then return end
        seen[path] = true
        seenName[key] = true
        list[#list + 1] = { name = name, path = path }
    end

    for i = 1, #PACKAGED do add(PACKAGED[i][1], PACKAGED[i][2]) end
    for i = 1, #BUILTIN do add(BUILTIN[i][1], BUILTIN[i][2]) end

    -- every Font object in the global namespace knows its own file, which
    -- surfaces fonts shipped by other addons without guessing at filenames
    -- Every Font object in the global namespace knows its own file, which
    -- surfaces fonts shipped by other addons without guessing at filenames.
    -- Walking _G is by far the most expensive thing Silk does, so it happens
    -- once and the result is reused; SharedMedia below is re-read every time,
    -- which is what actually changes as addons load.
    if not ns.scannedFonts then
        local found = {}
        pcall(function()
            for _, obj in pairs(_G) do
                if type(obj) == "table" then
                    local good, otype = pcall(function()
                        return obj.GetObjectType and obj:GetObjectType()
                    end)
                    if good and otype == "Font" then
                        local got, path = pcall(function() return obj:GetFont() end)
                        if got and type(path) == "string" then
                            found[#found + 1] = path
                        end
                    end
                end
            end
        end)
        ns.scannedFonts = found
    end
    for i = 1, #ns.scannedFonts do
        add(prettyFontName(ns.scannedFonts[i]), ns.scannedFonts[i])
    end

    -- anything registered with SharedMedia by any addon
    local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
    if lsm and lsm.HashTable then
        local good, tbl = pcall(lsm.HashTable, lsm, "font")
        if good and type(tbl) == "table" then
            local names = {}
            for n in pairs(tbl) do names[#names + 1] = n end
            table.sort(names)
            for i = 1, #names do add(names[i], tbl[names[i]]) end
        end
    end

    if #list == 0 then
        list[1] = { name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" }
    end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    fontCache = list
    return list
end

function ns.FontName(path)
    if not path or path == "" then return "Default" end
    local l = ns.FontList()
    for i = 1, #l do
        if l[i].path == path then return l[i].name end
    end
    return prettyFontName(path)
end

-- Every fontstring is born with a font. SetText on a fontstring that has
-- never had SetFont called raises "Font not set", and the real font arrives
-- later from ns.SetFont, so this closes the gap in between.
function ns.NewText(parent, layer, sublevel)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY", nil, sublevel)
    fs:SetFont("Fonts\\ARIALN.TTF", 12, "OUTLINE")
    fs:SetWordWrap(false)
    return fs
end

-- SOFT and HEAVY are Silk's own halo styles: WoW's native THICKOUTLINE is
-- crude at small sizes, so these render the text's own silhouette behind it
-- as offset dark copies -- four directions for Soft, eight for Heavy. It's
-- the same trick professional UIs use to fake a clean sub-pixel outline.
local OUTLINES = { NONE = "", OUTLINE = "OUTLINE", THICK = "THICKOUTLINE",
                   SOFT = "", HEAVY = "" }
local HALO_DIRS = {
    SOFT  = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } },
    HEAVY = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
              { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } },
}

local function syncHalo(fs, okey, path, size)
    local dirs = HALO_DIRS[okey]
    fs.__haloN = dirs and #dirs or 0
    if not dirs then
        if fs.__halo then
            for i = 1, #fs.__halo do fs.__halo[i]:Hide() end
        end
        return
    end
    fs.__halo = fs.__halo or {}
    local parent = fs:GetParent()
    local db = ns.db
    local hc = (db and db.shadowColor) or { r = 0, g = 0, b = 0 }
    for i = 1, #dirs do
        local c = fs.__halo[i]
        if not c then
            c = parent:CreateFontString(nil, "BORDER")
            c:SetWordWrap(false)
            fs.__halo[i] = c
        end
        if c:SetFont(path, size, "") == false then
            c:SetFont("Fonts\\ARIALN.TTF", size, "")
        end
        c:ClearAllPoints()
        c:SetPoint("CENTER", fs, "CENTER", dirs[i][1], dirs[i][2])
        c:SetTextColor(hc.r or 0, hc.g or 0, hc.b or 0, 0.9)
        c:SetText(fs:GetText() or "")
        if fs:IsShown() then c:Show() else c:Hide() end
    end
    for i = #dirs + 1, #fs.__halo do fs.__halo[i]:Hide() end
end

function ns.SyncHaloText(fs)
    if not fs.__halo then return end
    local txt = fs:GetText() or ""
    local n = fs.__haloN or 0
    local shown = fs:IsShown() and txt ~= ""
    for i = 1, #fs.__halo do
        local c = fs.__halo[i]
        if i <= n and shown then
            if c.__lastTxt ~= txt then
                c.__lastTxt = txt
                c:SetText(txt)
            end
            if not c:IsShown() then c:Show() end
        elseif c:IsShown() then
            c:Hide()
        end
    end
end

-- Applying a font is not fire-and-forget: the client silently refuses some
-- flag combinations, so every attempt is read back with GetFont and we walk
-- a list of alternatives until one sticks. The last result is kept for
-- /silk diag so a failure is visible instead of mysterious.
ns.fontDiag = {}

local function applyFont(fs, path, size, flags)
    local ok = fs:SetFont(path, size, flags)
    if ok == false then return false end
    local gotPath, _, gotFlags = fs:GetFont()
    if not gotPath then return false end
    -- some clients normalise the flag string; treat any non-nil as applied
    return true, gotPath, gotFlags or ""
end

function ns.SetFont(fs, delta, t)
    local db = ns.db
    local path = (t and t.font and t.font ~= "" and t.font) or db.font
    local okey = (t and t.outline and t.outline ~= "" and t.outline) or db.outline or "OUTLINE"
    local base = OUTLINES[okey]
    if not base then base = "OUTLINE" end
    local size = math.max(6, (db.fontSize or 12) + (delta or 0))

    -- ordered candidates, best first
    local tries
    if db.monochrome then
        if base == "" then
            tries = { "MONOCHROME", "" }
        else
            tries = { base .. ", MONOCHROME", "MONOCHROME, " .. base,
                      base .. ",MONOCHROME", base }
        end
    else
        tries = { base }
    end
    if base ~= "" then tries[#tries + 1] = "OUTLINE" end
    tries[#tries + 1] = ""

    local applied, usedPath, usedFlags
    for i = 1, #tries do
        local good, gp, gf = applyFont(fs, path, size, tries[i])
        if good then
            applied, usedPath, usedFlags = tries[i], gp, gf
            break
        end
    end
    if not applied then
        fs:SetFont("Fonts\\ARIALN.TTF", size, base)
        applied, usedPath, usedFlags = base, "Fonts\\ARIALN.TTF", base
        ns.fontDiag.fellBack = path
    end

    ns.fontDiag.path, ns.fontDiag.size = usedPath, size
    ns.fontDiag.asked, ns.fontDiag.got = tries[1], usedFlags

    syncHalo(fs, okey, usedPath, size)

    if db.shadow then
        local c = db.shadowColor or { r = 0, g = 0, b = 0, a = 0.85 }
        fs:SetShadowColor(c.r, c.g, c.b, c.a or 0.85)
        fs:SetShadowOffset(db.shadowX or 1, db.shadowY or -1)
    else
        fs:SetShadowColor(0, 0, 0, 0)
        fs:SetShadowOffset(0, 0)
    end
end

-- text backdrop ----------------------------------------------------------
-- A dark capsule behind a text element. Font outlines can only do so much on
-- top of a bright class-coloured bar; this is the setting that actually makes
-- numbers readable, and it doesn't depend on the client accepting font flags.

function ns.AttachTextBg(fs, layer)
    local bd = ns.Capsule(layer)
    local tex = bd:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(1, 1, 1)
    bd:AddMasked(tex)
    bd:SetCapStyle("capsule")
    bd.tex = tex
    bd:Hide()
    fs.__bd = bd
    return bd
end

-- Called on every text change, so it must not re-assert anchors and colours
-- that have not moved. The backdrop hangs off the fontstring itself, so its
-- points only change when the padding setting does.
function ns.RefreshTextBg(fs, t)
    local bd = fs.__bd
    if not bd then return end
    t = t or fs.__cfg
    local db = ns.db
    local mode = (t and t.bg) or "auto"
    local on
    if mode == "on" then
        on = true
    elseif mode == "off" then
        on = false
    else
        on = db.textBg
    end
    local txt = fs:GetText()
    if not on or not fs:IsShown() or not txt or txt == "" then
        if bd.shownState ~= false then
            bd.shownState = false
            bd:Hide()
        end
        return
    end

    local pad = db.textBgPad or 5
    if bd.padState ~= pad then
        bd.padState = pad
        local vpad = math.max(1, math.floor(pad * 0.5))
        bd:ClearAllPoints()
        bd:SetPoint("TOPLEFT", fs, "TOPLEFT", -pad, vpad)
        bd:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", pad, -vpad)
    end
    local a = db.textBgAlpha or 0.55
    if bd.alphaState ~= a then
        bd.alphaState = a
        bd.tex:SetVertexColor(0, 0, 0, a)
    end
    if bd.shownState ~= true then
        bd.shownState = true
        bd:Show()
    end
end

-- set text through this so the backdrop tracks what's actually displayed
function ns.Text(fs, str)
    str = str or ""
    if fs.__lastStr == str then return end
    fs.__lastStr = str
    fs:SetText(str)
    if fs.__bd then ns.RefreshTextBg(fs) end
    if fs.__halo then ns.SyncHaloText(fs) end
end

-- honors a per-element custom color, otherwise takes the color passed in
function ns.TextColor(fs, t, r, g, b)
    if t and t.colorMode == "custom" and t.color then
        fs:SetTextColor(t.color.r, t.color.g, t.color.b)
    elseif r then
        fs:SetTextColor(r, g, b)
    end
end

local dispelByClass = {
    PRIEST  = { Magic = true, Disease = true },
    PALADIN = { Magic = true, Poison = true, Disease = true },
    SHAMAN  = { Poison = true, Disease = true },
    MAGE    = { Curse = true },
    DRUID   = { Curse = true, Poison = true },
}

-- Whether we're in a raid as opposed to a party. Everything about party
-- visibility hangs off this one answer, so it doesn't rest on a single API:
-- if IsInRaid is missing or throws on this client, fall back to the legacy
-- count and finally to whether raid unit tokens resolve at all.
function ns.InRaid()
    if IsInRaid then
        local ok, res = pcall(IsInRaid)
        if ok and res ~= nil then return res and true or false end
    end
    if GetNumRaidMembers then
        local ok, n = pcall(GetNumRaidMembers)
        if ok and type(n) == "number" then return n > 0 end
    end
    return UnitExists("raid1") and true or false
end

function ns.CanDispel(dtype)
    if not dtype then return false end
    local _, class = UnitClass("player")
    local t = class and dispelByClass[class]
    return (t and t[dtype]) and true or false
end

-- the capsule factory ----------------------------------------------------
-- Two cap masks (CLAMPTOWHITE wrap) shape any region into a pill with
-- perfectly circular ends at ANY width, because each mask is anchored as a
-- height-sized square. Everything rounded in Silk is built on this.

function ns.Capsule(parent)
    local h = CreateFrame("Frame", nil, parent)
    local ml = h:CreateMaskTexture()
    ml:SetPoint("TOPLEFT")
    ml:SetPoint("BOTTOMLEFT")
    local mr = h:CreateMaskTexture()
    mr:SetPoint("TOPRIGHT")
    mr:SetPoint("BOTTOMRIGHT")
    h.__ml, h.__mr = ml, mr
    h:SetScript("OnSizeChanged", function(s, w, ht)
        local d = s.__capSize or math.max(ht or 1, 1)
        s.__ml:SetWidth(d)
        s.__mr:SetWidth(d)
    end)
    h.AddMasked = function(self, tex)
        tex:AddMaskTexture(self.__ml)
        tex:AddMaskTexture(self.__mr)
    end
    h.SetCapStyle = function(self, key)
        local c = ns.CAPS[key] or ns.CAPS.capsule
        self.__ml:SetTexture(c[1], "CLAMPTOWHITE", "CLAMPTOWHITE")
        self.__mr:SetTexture(c[2], "CLAMPTOWHITE", "CLAMPTOWHITE")
    end
    h.SetCapSize = function(self, px)
        self.__capSize = px
        local d = px or math.max(self:GetHeight() or 1, 1)
        self.__ml:SetWidth(d)
        self.__mr:SetWidth(d)
    end
    return h
end

-- animation driver -------------------------------------------------------
-- One frame drives every animating bar; bars unregister themselves the
-- moment they settle, so idle cost is zero.

local active = {}
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(_, dt)
    local any = false
    for bar in pairs(active) do
        if bar:Step(dt) then any = true else active[bar] = nil end
    end
    if not any then driver:Hide() end
end)

function ns.Animate(bar)
    active[bar] = true
    driver:Show()
end

-- how many bars are still animating; zero when everything has settled
function ns.AnimCount()
    local n = 0
    for _ in pairs(active) do n = n + 1 end
    return n
end

-- combat-safe deferral ---------------------------------------------------

local queued = {}
local combatWatcher = CreateFrame("Frame")
combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
combatWatcher:SetScript("OnEvent", function()
    local q = queued
    queued = {}
    for i = 1, #q do q[i]() end
end)

function ns.AfterCombat(fn)
    if InCombatLockdown() then
        table.insert(queued, fn)
    else
        fn()
    end
end

function ns.RegSafe(f, event, u1, u2)
    if u1 and f.RegisterUnitEvent then
        if pcall(f.RegisterUnitEvent, f, event, u1, u2) then return end
    end
    pcall(f.RegisterEvent, f, event)
end

-- live-apply pipeline ----------------------------------------------------

ns.refreshers = {}

local applyQueued = false
function ns.ApplyAll()
    if InCombatLockdown() then
        if not applyQueued then
            applyQueued = true
            ns.Print("settings will apply when combat ends.")
            ns.AfterCombat(function()
                applyQueued = false
                ns.ApplyAll()
            end)
        end
        return
    end
    for i = 1, #ns.refreshers do ns.refreshers[i]() end
end

-- saved variables --------------------------------------------------------

local function copyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            copyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function ns.ResetProfile()
    SilkDB[ns.charKey] = {}
    copyDefaults(ns.defaults, SilkDB[ns.charKey])
    ns.db = SilkDB[ns.charKey]
    ns.ApplyAll()
end

ns.onLogin = {}

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        SilkDB = SilkDB or {}
        local key = UnitName("player") .. "-" .. (GetRealmName() or "Realm")
        SilkDB[key] = SilkDB[key] or {}
        copyDefaults(ns.defaults, SilkDB[key])
        ns.db = SilkDB[key]
        ns.charKey = key
    elseif event == "PLAYER_LOGIN" then
        for i = 1, #ns.onLogin do ns.onLogin[i]() end
    end
end)
