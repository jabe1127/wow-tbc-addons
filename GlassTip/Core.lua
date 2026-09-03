--=====================================================================
-- GlassTip - Core
--=====================================================================
local ADDON, ns = ...
_G.GlassTip = ns

local WHITE = "Interface\\Buttons\\WHITE8X8"
local format, floor, min, max, abs = string.format, math.floor, math.min, math.max, math.abs

--=====================================================================
-- Defaults
--=====================================================================
ns.defaults = {
    skin = "",
    anchor = {
        mode        = "mouse",        -- "mouse" | "fixed"
        mousePoint  = "BOTTOMLEFT",   -- tooltip corner pinned to the cursor
        mouseX      = 16,
        mouseY      = 16,
        fixedPoint  = "BOTTOMRIGHT",  -- growth point when using the fixed anchor
        fixedX      = 0,
        fixedY      = 0,
        frameX      = nil,            -- anchor frame pos (UIParent BOTTOMLEFT)
        frameY      = nil,
        locked      = true,
        clamp       = true,
        paneEnabled = true,           -- character/inspect gear gets its own anchor
        paneSide    = "BOTTOM",       -- BOTTOM | TOP | LEFT | RIGHT | AUTO
        paneX       = 0,
        paneY       = -6,
        itemMode    = "anchor",       -- off | anchor | pane
        itemPoint   = "BOTTOMLEFT",
        itemX       = 0,
        itemY       = 0,
        itemLocked  = true,
        itemFrameX  = nil,
        itemFrameY  = nil,
    },
    style = {
        blizzard    = false,          -- hand the frame back to Blizzard
        scale       = 1.00,
        bgAlpha     = 0.92,
        bg          = { 0.045, 0.050, 0.065 },
        bgTexture   = "",             -- "" = flat colour, else a Media path
        bgTexTint   = { 1, 1, 1 },
        grain       = 0,              -- film grain alpha over the background
        borderMode  = "reaction",     -- reaction | custom
        border      = { 0.32, 0.36, 0.45 },
        borderSize  = 1,
        inner       = false,          -- second, inset frame line
        innerColor  = { 1, 1, 1 },
        innerAlpha  = 0.22,
        innerInset  = 3,
        accent      = true,
        accentSize  = 2,
        glow        = 0,              -- outer glow alpha
        glowMode    = "reaction",     -- reaction | custom
        glowColor   = { 0.55, 0.88, 0.29 },
        glowSize    = 14,
        brackets    = false,          -- ornamental corner brackets
        bracketColor= { 0.85, 0.71, 0.29 },
        bracketSize = 20,
        shadow      = true,
        gloss       = true,
        fade        = true,
        fadeTime    = 0.10,
        font        = "Fonts\\FRIZQT__.TTF",
        nameSize    = 15,
        bodySize    = 12,
        outline     = "NONE",
    },
    palette = {
        label = "8d93a3", tag = "ffd45a", type = "9a9aa8",
        guild = "8fd6c0", rank = "b6b8c4", sep = "5f6470",
        barText = "f5f6fa", barSub = "b8bcc8",
    },
    bar = {
        show        = true,
        sheen       = true,           -- use the gradient bar texture
        height      = 14,
        position    = "bottom",       -- bottom | top
        colorMode   = "reaction",     -- reaction | class | gradient
        text        = true,
        textInside  = true,
        percent     = true,
        textSize    = 11,
    },
    content = {
        showLevel       = true,
        showClassif     = true,
        showType        = true,
        showRace        = true,
        showClassText   = true,
        showGuild       = true,
        showGuildRank   = true,
        showRealm       = true,
        showTarget      = false,
        hideTotemNamesFriendly = false,   -- overhead world names (client CVars)
        hideTotemNamesEnemy    = false,
        hidePetNames           = false,
        noTotemTooltipFriendly = false,   -- suppress the tooltip entirely
        noTotemTooltipEnemy    = false,
        noPetTooltip           = false,
        hpMode          = "auto",     -- auto | number | percent | both
        abbreviate      = true,
        abbrevAt        = 10000,
        hideInCombat    = false,
    },
}

--=====================================================================
-- Helpers
--=====================================================================
local function CopyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end
ns.CopyDefaults = CopyDefaults

local function Hex(r, g, b)
    return format("|cff%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end
ns.Hex = Hex

function ns.SetGradient(tex, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
    if tex.SetGradient and CreateColor then
        if pcall(tex.SetGradient, tex, orientation, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2)) then
            return
        end
    end
    pcall(tex.SetGradientAlpha, tex, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
end

function ns.Short(v)
    v = v or 0
    local db = ns.db and ns.db.content
    if not db or not db.abbreviate then
        return BreakUpLargeNumbers and BreakUpLargeNumbers(v) or tostring(v)
    end
    if v >= 1000000000 then
        return (format("%.1f", v / 1000000000):gsub("%.0$", "")) .. "b"
    elseif v >= 1000000 then
        return (format("%.1f", v / 1000000):gsub("%.0$", "")) .. "m"
    elseif v >= (db.abbrevAt or 10000) then
        return format("%.0fk", v / 1000)
    end
    return tostring(v)
end

ns.MEDIA = "Interface\\AddOns\\GlassTip\\Media\\"
ns.TEX = {
    glowEdge   = ns.MEDIA .. "glow-edge",
    glowCorner = ns.MEDIA .. "glow-corner",
    grain      = ns.MEDIA .. "grain",
    parchment  = ns.MEDIA .. "parchment",
    bar        = ns.MEDIA .. "bar",
    bracket    = ns.MEDIA .. "bracket",
}

-- palette lookup returning a ready-to-use colour escape
function ns:P(key)
    local p = ns.db and ns.db.palette
    return "|cff" .. ((p and p[key]) or "ffffff")
end

--=====================================================================
-- Fonts
--
-- Only a handful ship with the client, and which ones exist depends on
-- the locale, so every candidate is probed before being offered. If
-- LibSharedMedia is loaded (ElvUI, WeakAuras and friends all embed it)
-- its whole registry comes along too.
--=====================================================================
local FONT_CANDIDATES = {
    { "Friz Quadrata",   "Fonts\\FRIZQT__.TTF" },
    { "Arial Narrow",    "Fonts\\ARIALN.TTF" },
    { "Skurri",          "Fonts\\SKURRI.TTF" },
    { "Morpheus",        "Fonts\\MORPHEUS.TTF" },
    { "Nimrod",          "Fonts\\NIM_____.ttf" },
    { "2002",            "Fonts\\2002.TTF" },
    { "2002 Bold",       "Fonts\\2002B.TTF" },
    { "Damage",          "Fonts\\K_Damage.TTF" },
    { "Page Text",       "Fonts\\K_Pagetext.TTF" },
    { "Friz Quadrata CYR", "Fonts\\FRIZQT___CYR.TTF" },
    { "Morpheus CYR",    "Fonts\\MORPHEUS_CYR.TTF" },
    { "AR Hei",          "Fonts\\ARHei.ttf" },
    { "AR Kai",          "Fonts\\ARKai_T.ttf" },
    { "BHei",            "Fonts\\bHEI00M.ttf" },
    { "BKai",            "Fonts\\bKAI00M.ttf" },
}

local probe
local function FontWorks(path)
    if not probe then
        probe = UIParent:CreateFontString(nil, "BACKGROUND")
    end
    -- set a font we know exists, then the candidate; if the candidate
    -- failed to load the old one is still in place
    probe:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    pcall(probe.SetFont, probe, path, 12, "")
    local cur = probe:GetFont()
    return cur ~= nil and cur:lower() == path:lower()
end

function ns:BuildFontList()
    local list, seen = {}, {}

    for _, entry in ipairs(FONT_CANDIDATES) do
        local name, path = entry[1], entry[2]
        if not seen[path:lower()] and FontWorks(path) then
            seen[path:lower()] = true
            list[#list + 1] = { name = name, path = path }
        end
    end
    ns.builtinFontCount = #list

    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local ok, names = pcall(LSM.List, LSM, "font")
        if ok and names then
            local extra = {}
            for _, name in ipairs(names) do
                local path = LSM:Fetch("font", name, true)
                if path and type(path) == "string" and not seen[path:lower()] and FontWorks(path) then
                    seen[path:lower()] = true
                    extra[#extra + 1] = { name = name, path = path }
                end
            end
            table.sort(extra, function(a, b) return a.name < b.name end)
            for _, e in ipairs(extra) do list[#list + 1] = e end
            ns.lsmFontCount = #extra
        end
    end

    ns.fonts = list
    return list
end

function ns:FontOptions()
    local opts = {}
    for _, f in ipairs(ns.fonts or {}) do
        opts[#opts + 1] = { value = f.path, text = f.name, font = f.path }
    end
    return opts
end

ns.fonts = {
    { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
}

ns.reactionColor = {
    [1] = { 0.92, 0.27, 0.29 },  -- hated
    [2] = { 0.92, 0.27, 0.29 },  -- hostile
    [3] = { 0.95, 0.55, 0.25 },  -- unfriendly
    [4] = { 0.98, 0.82, 0.32 },  -- neutral
    [5] = { 0.38, 0.85, 0.50 },  -- friendly
    [6] = { 0.38, 0.85, 0.50 },
    [7] = { 0.38, 0.85, 0.50 },
    [8] = { 0.38, 0.85, 0.50 },
}
local TAPPED = { 0.58, 0.58, 0.62 }

function ns:FontFlags()
    local o = ns.db.style.outline
    return (o == "NONE" or not o) and "" or o
end

function ns:ApplyFont(fs, size)
    if not fs then return end
    if not pcall(fs.SetFont, fs, ns.db.style.font, size, ns:FontFlags()) then
        pcall(fs.SetFont, fs, "Fonts\\FRIZQT__.TTF", size, ns:FontFlags())
    end
end

-- reaction / class colour of a unit
function ns:UnitColor(unit)
    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        local t = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)
        local c = class and t and t[class]
        if c then return c.r, c.g, c.b end
    end
    if UnitIsTapDenied and UnitIsTapDenied(unit) then
        return TAPPED[1], TAPPED[2], TAPPED[3]
    end
    local r = UnitReaction(unit, "player") or 4
    local c = ns.reactionColor[r] or ns.reactionColor[4]
    return c[1], c[2], c[3]
end

local function DifficultyColor(level)
    if not level or level < 1 then return { r = 1, g = 0.20, b = 0.20 } end
    if GetCreatureDifficultyColor then
        local ok, c = pcall(GetCreatureDifficultyColor, level)
        if ok and c then return c end
    end
    local ok, c = pcall(GetQuestDifficultyColor, level)
    if ok and c then return c end
    return { r = 1, g = 0.82, b = 0 }
end

--=====================================================================
-- Skin
--=====================================================================
local function MakeEdges(frame, sublevel)
    local e = {}
    for _, k in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = frame:CreateTexture(nil, "BACKGROUND", nil, sublevel)
        t:SetTexture(WHITE)
        e[k] = t
    end
    return e
end

local function LayoutEdges(e, frame, inset, size)
    -- SetHeight(0) does not mean "invisible", it means "use the texture's
    -- natural size", which for an 8x8 source is an 8px slab. Hide instead.
    if not size or size <= 0 then
        for _, t in pairs(e) do t:Hide() end
        return
    end
    for _, t in pairs(e) do t:Show() end

    e.TOP:ClearAllPoints()
    e.TOP:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", -inset - size, inset)
    e.TOP:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", inset + size, inset)
    e.TOP:SetHeight(size)

    e.BOTTOM:ClearAllPoints()
    e.BOTTOM:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -inset - size, -inset)
    e.BOTTOM:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", inset + size, -inset)
    e.BOTTOM:SetHeight(size)

    e.LEFT:ClearAllPoints()
    e.LEFT:SetPoint("TOPRIGHT", frame, "TOPLEFT", -inset, inset)
    e.LEFT:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", -inset, -inset)
    e.LEFT:SetWidth(size)

    e.RIGHT:ClearAllPoints()
    e.RIGHT:SetPoint("TOPLEFT", frame, "TOPRIGHT", inset, inset)
    e.RIGHT:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", inset, -inset)
    e.RIGHT:SetWidth(size)
end

local function ColorEdges(e, r, g, b, a)
    e.TOP:SetVertexColor(r, g, b, a)
    e.BOTTOM:SetVertexColor(r, g, b, a)
    e.LEFT:SetVertexColor(r, g, b, a)
    e.RIGHT:SetVertexColor(r, g, b, a)
end

local function StripDefault(tip)
    -- remember the original frame art the first time we take it away, so the
    -- Blizzard skin can hand it back later
    if tip.gtSaved == nil then
        tip.gtSaved = {}
        if tip.GetBackdrop then
            tip.gtSaved.backdrop = tip:GetBackdrop() or false
            if tip.GetBackdropColor then
                tip.gtSaved.bd = { tip:GetBackdropColor() }
            end
            if tip.GetBackdropBorderColor then
                tip.gtSaved.bdBorder = { tip:GetBackdropBorderColor() }
            end
        end
    end

    if tip.NineSlice then tip.NineSlice:SetAlpha(0) end
    if tip.SetBackdrop then pcall(tip.SetBackdrop, tip, nil) end
    local name = tip.GetName and tip:GetName()
    if name then
        for _, suffix in ipairs({ "Bg", "Border", "TopOverlay", "BottomOverlay" }) do
            local r = _G[name .. suffix]
            if r and r.SetAlpha then r:SetAlpha(0) end
        end
    end
    if tip.Bg then tip.Bg:SetAlpha(0) end
    if tip.Border then tip.Border:SetAlpha(0) end
end

local function RestoreDefault(tip)
    if tip.NineSlice then tip.NineSlice:SetAlpha(1) end
    local name = tip.GetName and tip:GetName()
    if name then
        for _, suffix in ipairs({ "Bg", "Border", "TopOverlay", "BottomOverlay" }) do
            local r = _G[name .. suffix]
            if r and r.SetAlpha then r:SetAlpha(1) end
        end
    end
    if tip.Bg then tip.Bg:SetAlpha(1) end
    if tip.Border then tip.Border:SetAlpha(1) end

    local saved = tip.gtSaved
    if saved and saved.backdrop and tip.SetBackdrop then
        pcall(tip.SetBackdrop, tip, saved.backdrop)
        if saved.bd and tip.SetBackdropColor then
            pcall(tip.SetBackdropColor, tip, unpack(saved.bd))
        end
        if saved.bdBorder and tip.SetBackdropBorderColor then
            pcall(tip.SetBackdropBorderColor, tip, unpack(saved.bdBorder))
        end
    elseif GameTooltip_SetBackdropStyle and tip == GameTooltip then
        pcall(GameTooltip_SetBackdropStyle, tip, GAME_TOOLTIP_BACKDROP_STYLE_DEFAULT)
    end
end

-- pick whichever treatment the current skin calls for
local function ReskinFrame(tip)
    if ns.db and ns.db.style.blizzard then
        RestoreDefault(tip)
    else
        StripDefault(tip)
    end
end
ns.ReskinFrame = ReskinFrame

function ns:BuildSkin(tip)
    if tip.gtSkin then return tip.gtSkin end
    local s = {}

    -- outer glow: four edges + four corners, drawn outside the frame
    s.glow = {}
    for _, k in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT", "TL", "TR", "BL", "BR" }) do
        local t = tip:CreateTexture(nil, "BACKGROUND", nil, -8)
        t:SetTexture(#k == 2 and ns.TEX.glowCorner or ns.TEX.glowEdge)
        s.glow[k] = t
    end

    -- soft drop shadow (three fading outlines)
    s.shadow = { MakeEdges(tip, -8), MakeEdges(tip, -8), MakeEdges(tip, -8) }

    -- flat background colour
    s.bg = tip:CreateTexture(nil, "BACKGROUND", nil, -7)
    s.bg:SetTexture(WHITE)
    s.bg:SetAllPoints(tip)

    -- optional textured background (parchment and friends)
    s.bgTex = tip:CreateTexture(nil, "BACKGROUND", nil, -6)
    s.bgTex:SetAllPoints(tip)
    s.bgTex:Hide()

    -- film grain
    s.grain = tip:CreateTexture(nil, "BACKGROUND", nil, -5)
    s.grain:SetTexture(ns.TEX.grain, "REPEAT", "REPEAT")
    s.grain:SetAllPoints(tip)
    s.grain:Hide()

    -- gloss sheen over the top third
    s.gloss = tip:CreateTexture(nil, "BACKGROUND", nil, -4)
    s.gloss:SetTexture(WHITE)
    s.gloss:SetPoint("TOPLEFT", tip, "TOPLEFT", 0, 0)
    s.gloss:SetPoint("TOPRIGHT", tip, "TOPRIGHT", 0, 0)
    s.gloss:SetHeight(34)
    ns.SetGradient(s.gloss, "VERTICAL", 1, 1, 1, 0, 1, 1, 1, 0.055)

    s.inner = MakeEdges(tip, -3)
    s.border = MakeEdges(tip, -2)

    -- accent strip along the top
    s.accent = tip:CreateTexture(nil, "BACKGROUND", nil, -1)
    s.accent:SetTexture(WHITE)

    -- ornamental corner brackets
    s.bracket = {}
    for _, k in ipairs({ "TL", "TR", "BL", "BR" }) do
        local t = tip:CreateTexture(nil, "BORDER", nil, 2)
        t:SetTexture(ns.TEX.bracket)
        s.bracket[k] = t
    end
    -- texcoord flips: the source art is a top-left bracket
    s.bracket.TL:SetTexCoord(0, 1, 0, 1)
    s.bracket.TR:SetTexCoord(1, 0, 0, 1)
    s.bracket.BL:SetTexCoord(0, 1, 1, 0)
    s.bracket.BR:SetTexCoord(1, 0, 1, 0)

    tip.gtSkin = s
    return s
end

-- The edge art is authored transparent at x=0, opaque at x=1; the corner art
-- is opaque at its bottom-right. Each piece is flipped or rotated so the solid
-- end always faces the frame.
local GLOW_CORNER_COORD = {
    TL = { 0, 1, 0, 1 },
    TR = { 1, 0, 0, 1 },
    BL = { 0, 1, 1, 0 },
    BR = { 1, 0, 1, 0 },
}
local GLOW_ANCHOR = { TL = "TOPLEFT", TR = "TOPRIGHT", BL = "BOTTOMLEFT", BR = "BOTTOMRIGHT" }

local function LayoutGlow(s, tip, size)
    local g = s.glow
    if not size or size <= 0 then
        for _, t in pairs(g) do t:Hide() end
        return
    end
    for _, t in pairs(g) do t:ClearAllPoints() end

    g.TOP:SetPoint("BOTTOMLEFT", tip, "TOPLEFT", 0, 0)
    g.TOP:SetPoint("BOTTOMRIGHT", tip, "TOPRIGHT", 0, 0)
    g.TOP:SetHeight(size)
    g.TOP:SetTexCoord(0, 0, 1, 0, 0, 1, 1, 1)

    g.BOTTOM:SetPoint("TOPLEFT", tip, "BOTTOMLEFT", 0, 0)
    g.BOTTOM:SetPoint("TOPRIGHT", tip, "BOTTOMRIGHT", 0, 0)
    g.BOTTOM:SetHeight(size)
    g.BOTTOM:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1)

    g.LEFT:SetPoint("TOPRIGHT", tip, "TOPLEFT", 0, 0)
    g.LEFT:SetPoint("BOTTOMRIGHT", tip, "BOTTOMLEFT", 0, 0)
    g.LEFT:SetWidth(size)
    g.LEFT:SetTexCoord(0, 1, 0, 1)

    g.RIGHT:SetPoint("TOPLEFT", tip, "TOPRIGHT", 0, 0)
    g.RIGHT:SetPoint("BOTTOMLEFT", tip, "BOTTOMRIGHT", 0, 0)
    g.RIGHT:SetWidth(size)
    g.RIGHT:SetTexCoord(1, 0, 0, 1)

    for k, anchor in pairs(GLOW_ANCHOR) do
        local t = g[k]
        t:SetSize(size, size)
        local ox = (k == "TL" or k == "BL") and -size or size
        local oy = (k == "TL" or k == "TR") and size or -size
        t:SetPoint("CENTER", tip, anchor, ox / 2, oy / 2)
        local c = GLOW_CORNER_COORD[k]
        t:SetTexCoord(c[1], c[2], c[3], c[4])
    end
end

local function HideCustomLayers(s)
    s.bg:Hide()
    s.bgTex:Hide()
    s.grain:Hide()
    s.gloss:Hide()
    s.accent:Hide()
    ColorEdges(s.border, 0, 0, 0, 0)
    ColorEdges(s.inner, 0, 0, 0, 0)
    for i = 1, 3 do ColorEdges(s.shadow[i], 0, 0, 0, 0) end
    for _, t in pairs(s.glow) do t:Hide() end
    for _, t in pairs(s.bracket) do t:Hide() end
end

function ns:ApplySkin(tip)
    if not tip or not tip.CreateTexture then return end
    local st = ns.db.style
    local s = ns:BuildSkin(tip)

    if st.blizzard then
        RestoreDefault(tip)
        HideCustomLayers(s)
        return
    end

    StripDefault(tip)
    s.bg:Show()
    local bs = tonumber(st.borderSize)
    if not bs or bs < 0 then bs = 1 end
    bs = floor(bs + 0.5)

    s.bg:SetVertexColor(st.bg[1], st.bg[2], st.bg[3], st.bgAlpha)

    if st.bgTexture and st.bgTexture ~= "" then
        s.bgTex:SetTexture(st.bgTexture)
        s.bgTex:SetVertexColor(st.bgTexTint[1], st.bgTexTint[2], st.bgTexTint[3], st.bgAlpha)
        s.bgTex:Show()
    else
        s.bgTex:Hide()
    end

    if (st.grain or 0) > 0 then
        s.grain:SetVertexColor(1, 1, 1, st.grain)
        s.grain:SetHorizTile(true)
        s.grain:SetVertTile(true)
        s.grain:Show()
    else
        s.grain:Hide()
    end

    s.gloss:SetShown(st.gloss)

    LayoutEdges(s.border, tip, 0, bs)
    if st.inner then
        LayoutEdges(s.inner, tip, -(st.innerInset or 3), 1)
        ColorEdges(s.inner, st.innerColor[1], st.innerColor[2], st.innerColor[3], st.innerAlpha)
    else
        ColorEdges(s.inner, 0, 0, 0, 0)
    end

    for i = 1, 3 do
        LayoutEdges(s.shadow[i], tip, bs + (i - 1), 1)
        local a = st.shadow and (0.30 / i) or 0
        ColorEdges(s.shadow[i], 0, 0, 0, a)
    end

    LayoutGlow(s, tip, st.glowSize or 14)

    s.accent:ClearAllPoints()
    s.accent:SetPoint("TOPLEFT", tip, "TOPLEFT", 0, 0)
    s.accent:SetPoint("TOPRIGHT", tip, "TOPRIGHT", 0, 0)
    local acc = tonumber(st.accentSize) or 2
    s.accent:SetHeight(max(1, acc))
    s.accent:SetShown(st.accent and acc > 0)

    local bsz = max(1, tonumber(st.bracketSize) or 20)
    for k, anchor in pairs(GLOW_ANCHOR) do
        local t = s.bracket[k]
        t:ClearAllPoints()
        t:SetSize(bsz, bsz)
        t:SetPoint(anchor, tip, anchor, 0, 0)
        t:SetVertexColor(st.bracketColor[1], st.bracketColor[2], st.bracketColor[3], 1)
        t:SetShown(st.brackets)
    end

    ns:ColorSkin(tip, nil)
end

-- r,g,b == nil -> use the configured static colour
function ns:ColorSkin(tip, r, g, b)
    local s = tip and tip.gtSkin
    if not s then return end
    local st = ns.db.style
    if st.blizzard then return end
    local ur, ug, ub = r, g, b
    if not r then r, g, b = st.border[1], st.border[2], st.border[3] end
    ColorEdges(s.border, r, g, b, 1)
    s.accent:SetVertexColor(r, g, b, 1)
    ns.SetGradient(s.accent, "HORIZONTAL", r, g, b, 1, r, g, b, 0.15)

    local ga = st.glow or 0
    local gr, gg, gb = st.glowColor[1], st.glowColor[2], st.glowColor[3]
    if st.glowMode == "reaction" and ur then gr, gg, gb = ur, ug, ub end
    for _, t in pairs(s.glow) do
        t:SetVertexColor(gr, gg, gb, ga)
        t:SetShown(ga > 0)
    end
end

--=====================================================================
-- Health bar
--=====================================================================
-- The status bar has moved around between builds. Find it, or make our own.
function ns:GetBar()
    local bar = GameTooltipStatusBar or (GameTooltip and GameTooltip.StatusBar)
    if not bar or not bar.SetStatusBarTexture then
        if not ns.ownBar then
            local b = CreateFrame("StatusBar", "GlassTipHealthBar", GameTooltip)
            b:SetMinMaxValues(0, 100)
            b:SetValue(0)
            b:Hide()
            ns.ownBar = b
            ns.usingOwnBar = true
        end
        bar = ns.ownBar
    end
    if bar:GetParent() ~= GameTooltip then bar:SetParent(GameTooltip) end
    bar:SetFrameLevel(GameTooltip:GetFrameLevel() + 2)
    return bar
end

local function SkinBar(bar)
    if not bar or bar.gtSkinned then return end
    bar.gtSkinned = true
    bar:SetStatusBarTexture(ns.db.bar.sheen and ns.TEX.bar or WHITE)

    bar.gtBG = bar:CreateTexture(nil, "BACKGROUND", nil, -2)
    bar.gtBG:SetTexture(WHITE)
    bar.gtBG:SetAllPoints(bar)

    bar.gtEdge = MakeEdges(bar, -3)

    bar.gtGloss = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    bar.gtGloss:SetTexture(WHITE)
    bar.gtGloss:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    bar.gtGloss:SetPoint("BOTTOMRIGHT", bar, "RIGHT", 0, 0)
    ns.SetGradient(bar.gtGloss, "VERTICAL", 1, 1, 1, 0.02, 1, 1, 1, 0.16)

    bar.gtLeft = bar:CreateFontString(nil, "OVERLAY")
    bar.gtLeft:SetPoint("LEFT", bar, "LEFT", 4, 0)
    bar.gtLeft:SetJustifyH("LEFT")

    bar.gtRight = bar:CreateFontString(nil, "OVERLAY")
    bar.gtRight:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    bar.gtRight:SetJustifyH("RIGHT")
end

local function HealthColor(unit, perc)
    local mode = ns.db.bar.colorMode
    if mode == "class" then
        local _, class = UnitClass(unit)
        local t = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)
        local c = class and t and t[class]
        if c then return c.r, c.g, c.b end
    elseif mode == "gradient" then
        local p = (perc or 100) / 100
        if p > 0.5 then
            return (1 - p) * 2 * 0.95, 0.85, 0.30
        else
            return 0.92, 0.85 * (p * 2), 0.28 * (p * 2)
        end
    end
    return ns:UnitColor(unit)
end

function ns:UpdateBar(tip)
    local bar = ns:GetBar()
    if not bar then return end
    SkinBar(bar)

    local unit = tip.gtUnit
    local db = ns.db.bar
    if not db.show or not unit or not UnitExists(unit) then bar:Hide() return end

    local cur, hmax = UnitHealth(unit) or 0, UnitHealthMax(unit) or 0
    if hmax <= 0 or UnitIsDeadOrGhost(unit) then bar:Hide() return end

    local perc = cur / hmax * 100
    -- when the client only hands out percentages, max comes back as 100
    local realNumbers = hmax > 100

    bar:SetMinMaxValues(0, hmax)
    bar:SetValue(cur)

    bar:SetStatusBarTexture(db.sheen and ns.TEX.bar or WHITE)
    local r, g, b = HealthColor(unit, perc)
    bar:SetStatusBarColor(r, g, b)
    bar.gtBG:SetVertexColor(r * 0.16, g * 0.16, b * 0.16, 0.85)
    ColorEdges(bar.gtEdge, 0, 0, 0, 0.55)
    LayoutEdges(bar.gtEdge, bar, 0, 1)

    -- position
    local pad = 8
    bar:ClearAllPoints()
    if db.position == "top" then
        bar:SetPoint("TOPLEFT", tip, "TOPLEFT", pad, -(ns.db.style.accentSize + 4))
        bar:SetPoint("TOPRIGHT", tip, "TOPRIGHT", -pad, -(ns.db.style.accentSize + 4))
    else
        bar:SetPoint("BOTTOMLEFT", tip, "BOTTOMLEFT", pad, 6)
        bar:SetPoint("BOTTOMRIGHT", tip, "BOTTOMRIGHT", -pad, 6)
    end
    bar:SetHeight(db.height)
    bar.gtGloss:SetShown(db.height >= 6)

    -- text
    local mode = ns.db.content.hpMode
    local numTxt, pctTxt = "", format("%.0f%%", perc)
    if realNumbers then
        numTxt = ns.Short(cur) .. " |cff6f6f7a/|r " .. ns.Short(hmax)
    else
        numTxt = pctTxt
    end

    local left, right = "", ""
    if mode == "percent" or (not realNumbers) then
        left, right = pctTxt, ""
    elseif mode == "number" then
        left, right = numTxt, ""
    else -- auto / both
        left = numTxt
        right = db.percent and pctTxt or ""
    end
    if mode == "auto" and not db.percent then right = "" end

    ns:ApplyFont(bar.gtLeft, db.textSize)
    ns:ApplyFont(bar.gtRight, db.textSize)
    local pal = ns.db.palette
    bar.gtLeft:SetText(db.text and (("|cff" .. pal.barText) .. left) or "")
    bar.gtRight:SetText(db.text and (("|cff" .. pal.barSub) .. right) or "")

    if db.textInside and db.height >= 12 then
        bar.gtLeft:ClearAllPoints();  bar.gtLeft:SetPoint("LEFT", bar, "LEFT", 5, 0)
        bar.gtRight:ClearAllPoints(); bar.gtRight:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
    else
        bar.gtLeft:ClearAllPoints();  bar.gtLeft:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 1, 2)
        bar.gtRight:ClearAllPoints(); bar.gtRight:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", -1, 2)
    end

    bar:Show()
end

--=====================================================================
-- Totems and pets
--=====================================================================
-- Creature type comes back localised, so this is reliable on enUS and
-- degrades to "no match" elsewhere rather than misfiring.
function ns:IsTotem(unit)
    local t = UnitCreatureType(unit)
    return t == "Totem"
end

function ns:IsPetLike(unit)
    if UnitIsPlayer(unit) then return false end
    if ns:IsTotem(unit) then return false end
    if UnitIsUnit(unit, "pet") then return true end
    return UnitPlayerControlled and UnitPlayerControlled(unit) or false
end

function ns:IsHostile(unit)
    return UnitCanAttack("player", unit) and true or false
end

ns.nameCVars = {
    { cv = "UnitNameFriendlyTotemName",    key = "hideTotemNamesFriendly" },
    { cv = "UnitNameEnemyTotemName",       key = "hideTotemNamesEnemy" },
    { cv = "UnitNameFriendlyPetName",      key = "hidePetNames" },
    { cv = "UnitNameEnemyPetName",         key = "hidePetNames" },
    { cv = "UnitNameFriendlyGuardianName", key = "hidePetNames" },
    { cv = "UnitNameEnemyGuardianName",    key = "hidePetNames" },
    { cv = "UnitNamePlayerPetName",        key = "hidePetNames" },
}

-- These are client settings, not addon settings: they persist after GlassTip
-- is gone. The original values are stashed the first time we touch them so
-- turning the option back off restores what you had.
function ns:ApplyNameCVars()
    if InCombatLockdown() then
        ns.cvarPending = true
        return
    end
    ns.cvarPending = nil
    local db = ns.db.content
    local sv = GlassTipDB
    sv.savedCVars = sv.savedCVars or {}

    for _, entry in ipairs(ns.nameCVars) do
        local cv, hide = entry.cv, db[entry.key]
        local current = GetCVar(cv)
        if current ~= nil then
            if hide then
                if sv.savedCVars[cv] == nil then sv.savedCVars[cv] = current end
                pcall(SetCVar, cv, "0")
            elseif sv.savedCVars[cv] ~= nil then
                pcall(SetCVar, cv, sv.savedCVars[cv])
                sv.savedCVars[cv] = nil
            end
        end
    end
end

--=====================================================================
-- Content
--=====================================================================
local CLASSIF = {
    worldboss = "Boss",
    rareelite = "Rare Elite",
    elite     = "Elite",
    rare      = "Rare",
}

local function GetTooltipUnit(tip)
    local _, unit = tip:GetUnit()
    if unit and UnitExists(unit) then return unit end

    local focus
    if GetMouseFoci then
        local foci = GetMouseFoci()
        focus = foci and foci[1]
    elseif GetMouseFocus then
        focus = GetMouseFocus()
    end
    if focus and focus.GetAttribute then
        local u = focus:GetAttribute("unit") or focus.unit
        if u and UnitExists(u) then return u end
    end
    if UnitExists("mouseover") then return "mouseover" end
end

function ns:BuildLevelLine(unit, isPlayer)
    local db = ns.db.content
    local parts = {}

    if db.showLevel then
        local lvl = UnitLevel(unit)
        local txt = (lvl and lvl > 0) and tostring(lvl) or "??"
        local c = DifficultyColor(lvl)
        parts[#parts + 1] = ns:P("label") .. (LEVEL or "Level") .. "|r " .. Hex(c.r, c.g, c.b) .. txt .. "|r"
    end

    if isPlayer then
        if db.showRace then
            local race = UnitRace(unit)
            if race then parts[#parts + 1] = ns:P("rank") .. race .. "|r" end
        end
        if db.showClassText then
            local cls, token = UnitClass(unit)
            if cls then
                local t = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)
                local c = token and t and t[token]
                parts[#parts + 1] = (c and Hex(c.r, c.g, c.b) or "|cffffffff") .. cls .. "|r"
            end
        end
    else
        if db.showClassif then
            local tag = CLASSIF[UnitClassification(unit) or ""]
            if tag then parts[#parts + 1] = ns:P("tag") .. tag .. "|r" end
        end
        if db.showType then
            local ct = UnitCreatureType(unit)
            if ct and ct ~= "" then parts[#parts + 1] = ns:P("type") .. ct .. "|r" end
        end
    end

    if not UnitIsConnected(unit) then
        parts[#parts + 1] = "|cff8a8a94" .. (PLAYER_OFFLINE or "Offline") .. "|r"
    elseif UnitIsDeadOrGhost(unit) then
        parts[#parts + 1] = "|cffc45b5b" .. (DEAD or "Dead") .. "|r"
    end

    return table.concat(parts, " ")
end

function ns:UpdateUnitTooltip(tip)
    if tip ~= GameTooltip then return end
    local unit = GetTooltipUnit(tip)
    if not unit or not UnitExists(unit) then
        tip.gtUnit = nil
        local b = ns:GetBar(); if b then b:Hide() end
        return
    end

    local c = ns.db.content
    local suppress = false
    if ns:IsTotem(unit) then
        suppress = ns:IsHostile(unit) and c.noTotemTooltipEnemy or c.noTotemTooltipFriendly
    elseif ns:IsPetLike(unit) then
        suppress = c.noPetTooltip
    end
    if suppress then
        tip.gtUnit = nil
        local b = ns:GetBar(); if b then b:Hide() end
        tip:Hide()
        return
    end

    if ns.db.content.hideInCombat and InCombatLockdown() then
        tip.gtUnit = nil
        tip:Hide()
        return
    end

    tip.gtUnit = unit
    local db = ns.db.content
    local style = ns.db.style
    local isPlayer = UnitIsPlayer(unit)
    local r, g, b = ns:UnitColor(unit)

    if style.borderMode == "custom" then
        ns:ColorSkin(tip, nil)
    else
        ns:ColorSkin(tip, r, g, b)
    end

    -- Name -------------------------------------------------------------
    local nameFS = _G["GameTooltipTextLeft1"]
    if nameFS then
        local name, realm = UnitName(unit)
        local shown = name or (UNKNOWN or "Unknown")
        if isPlayer and realm and realm ~= "" and db.showRealm then
            shown = shown .. " |cff7d7d8a-" .. realm .. "|r"
        end
        if not isPlayer then
            local fam = UnitCreatureFamily and UnitCreatureFamily(unit)
            local classif = UnitClassification(unit)
            if classif == "worldboss" or (UnitLevel(unit) or 0) < 0 then
                shown = "|cffffd45a\226\152\160|r " .. shown
            end
            if fam and UnitPlayerControlled and UnitPlayerControlled(unit) then
                shown = shown .. " |cff7d7d8a(" .. fam .. ")|r"
            end
        end
        nameFS:SetText(shown)
        nameFS:SetTextColor(r, g, b)
        ns:ApplyFont(nameFS, style.nameSize)
    end

    -- Guild / level ------------------------------------------------------
    local guildName, guildRank
    if isPlayer then guildName, guildRank = GetGuildInfo(unit) end

    local levelDone = false
    for i = 2, tip:NumLines() do
        local fs = _G["GameTooltipTextLeft" .. i]
        local text = fs and fs:GetText()
        if fs then ns:ApplyFont(fs, style.bodySize) end
        if text and text ~= "" then
            if guildName and text:find(guildName, 1, true) then
                if db.showGuild then
                    local s = ns:P("guild") .. guildName .. "|r"
                    if db.showGuildRank and guildRank and guildRank ~= "" then
                        s = s .. " " .. ns:P("sep") .. "\226\128\162|r " .. ns:P("rank") .. guildRank .. "|r"
                    end
                    fs:SetText(s)
                else
                    fs:SetText(nil)
                    fs:Hide()
                end
            elseif not levelDone and LEVEL and text:find(LEVEL, 1, true) then
                levelDone = true
                fs:SetText(ns:BuildLevelLine(unit, isPlayer))
            end
        end
    end

    if not levelDone then
        local line = ns:BuildLevelLine(unit, isPlayer)
        if line ~= "" then tip:AddLine(line) end
    end

    -- Target of unit -----------------------------------------------------
    if db.showTarget then
        local tu = unit .. "target"
        if UnitExists(tu) then
            local tr, tg, tb = ns:UnitColor(tu)
            local tn = UnitName(tu)
            if UnitIsUnit(tu, "player") then
                tn = "|cffff5555" .. (YOU or "You") .. "|r"
            else
                tn = Hex(tr, tg, tb) .. (tn or "?") .. "|r"
            end
            tip:AddLine("|cff8d93a3" .. (TARGET or "Target") .. ":|r " .. tn)
        end
    end

    -- room for the health bar
    local extra = (ns.db.bar.show and not UnitIsDeadOrGhost(unit)) and (ns.db.bar.height + 8) or 0
    local bottomPad = (ns.db.bar.position == "bottom") and extra or 0
    local topPad    = (ns.db.bar.position == "top") and extra or 0
    if not pcall(tip.SetPadding, tip, 0, bottomPad, 0, topPad) then
        pcall(tip.SetPadding, tip, 0, bottomPad)
    end

    tip:Show()
    ns:UpdateBar(tip)

    -- the tooltip only reaches its final size here, so re-apply the anchor
    -- now that width and height are known
    if tip.gtOwned then ns:ApplyAnchor(tip) end
end

--=====================================================================
-- Anchoring
--=====================================================================
local POINT_FRACTION = {
    TOPLEFT     = { 0,   1   },
    TOP         = { 0.5, 1   },
    TOPRIGHT    = { 1,   1   },
    LEFT        = { 0,   0.5 },
    CENTER      = { 0.5, 0.5 },
    RIGHT       = { 1,   0.5 },
    BOTTOMLEFT  = { 0,   0   },
    BOTTOM      = { 0.5, 0   },
    BOTTOMRIGHT = { 1,   0   },
}
ns.POINTS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

local function MakeAnchorBox(globalName, label, accent, onMoved)
    local f = CreateFrame("Frame", globalName, UIParent)
    f:SetSize(150, 34)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(WHITE)
    bg:SetAllPoints(f)
    bg:SetVertexColor(0.05, 0.06, 0.08, 0.85)

    local edge = MakeEdges(f, -1)
    LayoutEdges(edge, f, 0, 1)
    ColorEdges(edge, accent[1], accent[2], accent[3], 0.9)

    local txt = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    txt:SetPoint("CENTER")
    txt:SetText(label)
    txt:SetTextColor(accent[1], accent[2], accent[3])

    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx, cy = self:GetCenter()
        local sc = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
        onMoved(cx * sc, cy * sc)
    end)
    f:Hide()
    return f
end

function ns:CreateAnchorFrame()
    if ns.anchorFrame then return ns.anchorFrame end
    ns.anchorFrame = MakeAnchorBox("GlassTipAnchor", "GlassTip units \226\128\148 drag me",
        { 0.42, 0.78, 1 }, function(x, y)
            ns.db.anchor.frameX, ns.db.anchor.frameY = x, y
        end)
    return ns.anchorFrame
end

function ns:CreateItemAnchorFrame()
    if ns.itemAnchor then return ns.itemAnchor end
    ns.itemAnchor = MakeAnchorBox("GlassTipItemAnchor", "GlassTip items \226\128\148 drag me",
        { 1, 0.78, 0.42 }, function(x, y)
            ns.db.anchor.itemFrameX, ns.db.anchor.itemFrameY = x, y
        end)
    return ns.itemAnchor
end

function ns:PositionItemAnchorFrame()
    local f = ns:CreateItemAnchorFrame()
    local db = ns.db.anchor
    if not db.itemFrameX or not db.itemFrameY then
        -- default well clear of the right-hand side of the screen
        db.itemFrameX = GetScreenWidth() * 0.26
        db.itemFrameY = GetScreenHeight() * 0.34
    end
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", db.itemFrameX, db.itemFrameY)
end

function ns:PositionAnchorFrame()
    local f = ns:CreateAnchorFrame()
    local db = ns.db.anchor
    if not db.frameX or not db.frameY then
        db.frameX = GetScreenWidth() * 0.72
        db.frameY = GetScreenHeight() * 0.34
    end
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", db.frameX, db.frameY)
end

function ns:UpdateAnchorVisibility()
    local f = ns:CreateAnchorFrame()
    if ns.db.anchor.locked or ns.db.anchor.mode ~= "fixed" then f:Hide() else f:Show() end

    local i = ns:CreateItemAnchorFrame()
    if ns.db.anchor.itemLocked or ns.db.anchor.itemMode == "off" then i:Hide() else i:Show() end
end

-- screen size expressed in the tooltip's own coordinate units
local function ScreenBounds(tip)
    local s = tip:GetEffectiveScale()
    if s <= 0 then return GetScreenWidth(), GetScreenHeight() end
    local us = UIParent:GetEffectiveScale() / s
    return GetScreenWidth() * us, GetScreenHeight() * us
end

-- Pull a tooltip fully back on screen. Returns true if it had to move.
local function ClampTip(tip, pad)
    pad = pad or 4
    local left, bottom = tip:GetLeft(), tip:GetBottom()
    local w, h = tip:GetWidth(), tip:GetHeight()
    if not left or not bottom or not w or not h or w <= 0 or h <= 0 then return false end

    local sw, sh = ScreenBounds(tip)
    local nl = max(pad, min(left, sw - w - pad))
    local nb = max(pad, min(bottom, sh - h - pad))

    if abs(nl - left) > 0.5 or abs(nb - bottom) > 0.5 then
        tip:ClearAllPoints()
        tip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", nl, nb)
        return true
    end
    return false
end
ns.ClampTip = ClampTip

local function PositionAtMouse(tip)
    local db = ns.db.anchor
    local s = tip:GetEffectiveScale()
    if s <= 0 then return end
    local cx, cy = GetCursorPosition()
    cx, cy = cx / s, cy / s

    local w, h = tip:GetWidth(), tip:GetHeight()
    local frac = POINT_FRACTION[db.mousePoint] or POINT_FRACTION.BOTTOMLEFT
    local ox, oy = db.mouseX, db.mouseY
    local left   = cx + ox - w * frac[1]
    local bottom = cy + oy - h * frac[2]

    if db.clamp then
        local sw, sh = ScreenBounds(tip)
        local pad = 4

        -- Prefer flipping to the far side of the cursor over sliding, so the
        -- tooltip never ends up sitting underneath the pointer.
        if left + w > sw - pad then
            left = cx - abs(ox) - w
        elseif left < pad then
            left = cx + abs(ox)
        end
        if bottom + h > sh - pad then
            bottom = cy - abs(oy) - h
        elseif bottom < pad then
            bottom = cy + abs(oy)
        end

        -- if flipping still doesn't fit (very large tooltip), slide it in
        left   = max(pad, min(left, sw - w - pad))
        bottom = max(pad, min(bottom, sh - h - pad))
    end

    tip:ClearAllPoints()
    tip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
end

local function PositionFixed(tip)
    local db = ns.db.anchor
    ns:PositionAnchorFrame()
    tip:ClearAllPoints()
    tip:SetPoint(db.fixedPoint, ns.anchorFrame, db.fixedPoint, db.fixedX, db.fixedY)
    if db.clamp then ClampTip(tip) end
end

function ns:ApplyAnchor(tip)
    if tip ~= GameTooltip then return end
    -- SetClampedToScreen is sticky on the frame: turning it off here would
    -- leave it off for every tooltip Blizzard positions afterwards (inspect
    -- slots, bags, the character sheet), which is how tall ones end up
    -- running off the top of the screen. Our flip logic runs first, then the
    -- engine clamp acts as a backstop.
    tip:SetClampedToScreen(true)
    if ns.db.anchor.mode == "fixed" then
        PositionFixed(tip)
    else
        PositionAtMouse(tip)
    end
end

--=====================================================================
-- Character pane item tooltips
--
-- Blizzard anchors these to the individual slot button, which puts a tall
-- tooltip off the top of the screen on the upper slots. Instead we pin them
-- to one spot on the pane itself so every slot behaves the same.
--=====================================================================
local PANE_SIDE = {
    BOTTOM = { "TOPLEFT",     "BOTTOMLEFT" },
    TOP    = { "BOTTOMLEFT",  "TOPLEFT" },
    RIGHT  = { "BOTTOMLEFT",  "BOTTOMRIGHT" },
    LEFT   = { "BOTTOMRIGHT", "BOTTOMLEFT" },
}
ns.PANE_SIDES = { "BOTTOM", "TOP", "LEFT", "RIGHT", "AUTO" }

-- Which pane, if any, owns this frame?
local function OwningPane(frame)
    local f, depth = frame, 0
    while f and depth < 8 do
        local n = f.GetName and f:GetName()
        if n then
            if n:find("^Character") and _G.CharacterFrame then return _G.CharacterFrame end
            if n:find("^Inspect") and _G.InspectFrame then return _G.InspectFrame end
            if n == "PaperDollFrame" and _G.CharacterFrame then return _G.CharacterFrame end
        end
        f = f:GetParent()
        depth = depth + 1
    end
end

local function AutoSide(tip, pane)
    local s = tip:GetEffectiveScale()
    if s <= 0 then return "BOTTOM" end
    local sw, sh = ScreenBounds(tip)
    local scale = pane:GetEffectiveScale() / s
    local w, h = tip:GetWidth(), tip:GetHeight()
    local pl = (pane:GetLeft()   or 0) * scale
    local pr = (pane:GetRight()  or 0) * scale
    local pb = (pane:GetBottom() or 0) * scale
    local pt = (pane:GetTop()    or 0) * scale

    if pb - h > 4 then return "BOTTOM" end
    if sw - pr - w > 4 then return "RIGHT" end
    if pl - w > 4 then return "LEFT" end
    if sh - pt - h > 4 then return "TOP" end
    return "BOTTOM"
end

local function PositionOnPane(tip)
    local pane = tip.gtPane
    if not pane or not pane:IsShown() then return end
    local db = ns.db.anchor

    local side = db.paneSide
    if side == "AUTO" then side = AutoSide(tip, pane) end
    local pts = PANE_SIDE[side] or PANE_SIDE.BOTTOM

    tip:ClearAllPoints()
    tip:SetPoint(pts[1], pane, pts[2], db.paneX, db.paneY)
    ClampTip(tip)
end
ns.PositionOnPane = PositionOnPane

-- Item tooltips from anywhere: bags, merchants, loot, and third-party gear
-- panels. In "pane" mode the character window wins while it is open, since
-- that is where you are looking; otherwise the item anchor is used.
local function PositionItem(tip)
    local db = ns.db.anchor
    if db.itemMode == "off" then return end

    if db.itemMode == "pane" then
        local pane = (_G.CharacterFrame and _G.CharacterFrame:IsShown() and _G.CharacterFrame)
                  or (_G.InspectFrame and _G.InspectFrame:IsShown() and _G.InspectFrame)
        if pane then
            tip.gtPane = pane
            PositionOnPane(tip)
            return
        end
    end

    ns:PositionItemAnchorFrame()
    tip:ClearAllPoints()
    tip:SetPoint(db.itemPoint, ns.itemAnchor, db.itemPoint, db.itemX, db.itemY)
    ClampTip(tip)
end
ns.PositionItem = PositionItem

local function IsItemTooltip(tip)
    if tip.gtUnit then return false end
    local ok, _, link = pcall(tip.GetItem, tip)
    return ok and link ~= nil
end

--=====================================================================
-- Hooks / events
--=====================================================================
local driver = CreateFrame("Frame")
driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")

local function Try(label, fn)
    local ok, err = pcall(fn)
    ns.hookStatus = ns.hookStatus or {}
    ns.hookStatus[label] = ok and "ok" or ("FAILED: " .. tostring(err))
    return ok
end

-- One dispatcher, guarded so several registration paths can't double-process
-- the same tooltip in the same frame.
local function Dispatch(tip)
    if tip ~= GameTooltip then return end
    local now = GetTime()
    if tip.gtLastRun == now then return end
    tip.gtLastRun = now
    local ok, err = pcall(ns.UpdateUnitTooltip, ns, tip)
    if not ok then
        ns.lastError = err
        if not ns.errorShown then
            ns.errorShown = true
            print("|cff7fd5ffGlassTip error:|r " .. tostring(err))
            print("|cff7fd5ffGlassTip:|r type /gtip debug for details.")
        end
    end
end
ns.Dispatch = Dispatch

local function HookTooltips()
    local tips = {
        GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2,
        _G["WorldMapTooltip"], _G["GameTooltipTooltip"],
    }
    for _, t in pairs(tips) do
        if t and t.CreateTexture then
            Try("skin", function()
                ns:ApplySkin(t)
                t:HookScript("OnShow", function(self)
                    ReskinFrame(self)
                    if not self.gtUnit then ns:ColorSkin(self, nil) end
                end)
            end)
        end
    end

    -- default anchor takeover (world objects + unit frames)
    Try("anchor hook", function()
        hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tip)
            if tip ~= GameTooltip then return end
            tip.gtOwned = true
            ns:ApplyAnchor(tip)
        end)
    end)

    -- Unit content. Every registration path below is optional; whichever ones
    -- exist on this client get used, and the OnUpdate sweep at the bottom is
    -- the last-resort catch so the tooltip is always processed.
    Try("TooltipDataProcessor", function()
        if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
           and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, Dispatch)
        else
            error("not present on this client", 0)
        end
    end)

    Try("OnTooltipSetUnit", function()
        if GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetUnit") then
            GameTooltip:HookScript("OnTooltipSetUnit", Dispatch)
        else
            error("script no longer exists on this client", 0)
        end
    end)

    Try("pane items", function()
        hooksecurefunc(GameTooltip, "SetOwner", function(tip, owner)
            if tip ~= GameTooltip then return end
            tip.gtPane = nil
            if not ns.db.anchor.paneEnabled or not owner then return end
            local pane = OwningPane(owner)
            if pane then
                tip.gtPane = pane
                PositionOnPane(tip)
            end
        end)
    end)

    Try("item anchor", function()
        if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
           and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip)
                if tip == GameTooltip and not tip.gtPane then PositionItem(tip) end
            end)
        else
            error("not present on this client", 0)
        end
    end)

    Try("SetUnit hook", function()
        hooksecurefunc(GameTooltip, "SetUnit", function(tip) Dispatch(tip) end)
    end)

    Try("clamp", function()
        for _, t in pairs({ GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2 }) do
            if t and t.SetClampedToScreen then t:SetClampedToScreen(true) end
        end
    end)

    Try("show/hide", function()
        GameTooltip:HookScript("OnShow", function(self)
            self:SetScale(ns.db.style.scale)
            if ns.db.style.fade then
                self.gtFade = 0
                self:SetAlpha(0)
            end
        end)

        GameTooltip:HookScript("OnHide", function(self)
            self.gtUnit = nil
            self.gtOwned = nil
            self.gtPane = nil
            self.gtFade = nil
            self.gtLastRun = nil
            local b = ns:GetBar(); if b then b:Hide() end
            if not pcall(self.SetPadding, self, 0, 0, 0, 0) then pcall(self.SetPadding, self, 0, 0) end
        end)
    end)

    local acc = 0
    Try("update loop", function()
        GameTooltip:HookScript("OnUpdate", function(self, e)
            -- fade in
            if self.gtFade and ns.db.style.fade then
                self.gtFade = self.gtFade + e
                local t = ns.db.style.fadeTime
                local a = (t > 0) and min(1, self.gtFade / t) or 1
                self:SetAlpha(a)
                if a >= 1 then self.gtFade = nil end
            end
            -- follow the cursor
            if self.gtOwned and ns.db.anchor.mode == "mouse" then
                PositionAtMouse(self)
            elseif self.gtPane then
                PositionOnPane(self)
            elseif ns.db.anchor.itemMode ~= "off" and IsItemTooltip(self) then
                PositionItem(self)
            end

            acc = acc + e
            if acc > 0.08 then
                acc = 0
                if self.gtUnit then
                    if UnitExists(self.gtUnit) then
                        ns:UpdateBar(self)
                    else
                        local b = ns:GetBar(); if b then b:Hide() end
                    end
                else
                    -- catch-all: a unit tooltip none of the hooks told us about
                    local _, u = self:GetUnit()
                    if u and UnitExists(u) then Dispatch(self) end
                end
            end
        end)
    end)
end

function ns:Refresh()
    if not ns.db then return end
    ns:ApplyNameCVars()
    for _, t in ipairs({ GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2 }) do
        if t and t.gtSkin then ns:ApplySkin(t) end
    end
    GameTooltip:SetScale(ns.db.style.scale)
    ns:PositionAnchorFrame()
    ns:PositionItemAnchorFrame()
    ns:UpdateAnchorVisibility()
    if GameTooltip:IsShown() and GameTooltip.gtUnit then
        ns:UpdateBar(GameTooltip)
    end
end

--=====================================================================
-- Profiles
--=====================================================================
function ns:CharKey()
    local name = UnitName("player") or "?"
    local realm = GetRealmName() or "?"
    return name .. " - " .. realm
end

function ns:InitDB()
    GlassTipDB = GlassTipDB or {}
    local sv = GlassTipDB

    -- migrate a flat v1 database into profiles
    if not sv.profiles then
        local old = nil
        if sv.anchor or sv.style then
            old = {}
            for k, v in pairs(sv) do old[k] = v end
        end
        for k in pairs(sv) do sv[k] = nil end
        sv.profiles = { Default = old or {} }
        sv.chars = {}
        sv.version = 2
    end
    sv.chars = sv.chars or {}
    sv.profiles.Default = sv.profiles.Default or {}

    local key = ns:CharKey()
    local want = sv.chars[key] or "Default"
    if not sv.profiles[want] then want = "Default" end
    sv.chars[key] = want

    CopyDefaults(sv.profiles[want], ns.defaults)
    ns.db = sv.profiles[want]
    ns.activeProfile = want

    -- the totem options used to be single toggles; carry them across
    local c = ns.db.content
    if c.hideTotemNames ~= nil then
        if c.hideTotemNames then
            c.hideTotemNamesFriendly, c.hideTotemNamesEnemy = true, true
        end
        c.hideTotemNames = nil
    end
    if c.noTotemTooltip ~= nil then
        if c.noTotemTooltip then
            c.noTotemTooltipFriendly, c.noTotemTooltipEnemy = true, true
        end
        c.noTotemTooltip = nil
    end
end

function ns:ProfileNames()
    local t = {}
    for name in pairs(GlassTipDB.profiles) do t[#t + 1] = name end
    table.sort(t)
    return t
end

function ns:ActivateProfile(name)
    local sv = GlassTipDB
    if not sv.profiles[name] then return end
    CopyDefaults(sv.profiles[name], ns.defaults)
    sv.chars[ns:CharKey()] = name
    ns.db = sv.profiles[name]
    ns.activeProfile = name
    ns:Refresh()
    if ns.RefreshOptions then ns:RefreshOptions() end
end

local function DeepCopy(src)
    local out = {}
    for k, v in pairs(src) do
        out[k] = (type(v) == "table") and DeepCopy(v) or v
    end
    return out
end

function ns:CreateProfile(name, copyFrom)
    local sv = GlassTipDB
    name = (name or ""):match("^%s*(.-)%s*$")
    if name == "" or sv.profiles[name] then return false end
    sv.profiles[name] = copyFrom and sv.profiles[copyFrom] and DeepCopy(sv.profiles[copyFrom]) or {}
    CopyDefaults(sv.profiles[name], ns.defaults)
    ns:ActivateProfile(name)
    return true
end

function ns:ResetProfile()
    local sv = GlassTipDB
    local name = ns.activeProfile or "Default"
    sv.profiles[name] = {}
    CopyDefaults(sv.profiles[name], ns.defaults)
    ns.db = sv.profiles[name]
    ns:Refresh()
    if ns.RefreshOptions then ns:RefreshOptions() end
end

function ns:DeleteProfile(name)
    local sv = GlassTipDB
    if name == "Default" or not sv.profiles[name] then return false end
    sv.profiles[name] = nil
    for k, v in pairs(sv.chars) do
        if v == name then sv.chars[k] = "Default" end
    end
    if ns.activeProfile == name then ns:ActivateProfile("Default") end
    if ns.RefreshOptions then ns:RefreshOptions() end
    return true
end

driver:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        -- character name is not reliable this early; profile selection waits
        GlassTipDB = GlassTipDB or {}
    elseif event == "PLAYER_REGEN_ENABLED" then
        if ns.cvarPending then ns:ApplyNameCVars() end
    elseif event == "PLAYER_LOGIN" then
        ns:InitDB()
        ns:BuildFontList()
        HookTooltips()
        ns:CreateAnchorFrame()
        ns:CreateItemAnchorFrame()
        ns:PositionAnchorFrame()
        ns:PositionItemAnchorFrame()
        ns:Refresh()
        if ns.BuildOptions then ns:BuildOptions() end
    end
end)

--=====================================================================
-- Slash
--=====================================================================
SLASH_GLASSTIP1 = "/glasstip"
SLASH_GLASSTIP2 = "/gtip"
SlashCmdList["GLASSTIP"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "unlock" then
        ns.db.anchor.locked = false
        ns.db.anchor.mode = "fixed"
        ns:Refresh()
        print("|cff7fd5ffGlassTip:|r anchor unlocked.")
    elseif msg == "unlock items" or msg == "itemunlock" then
        ns.db.anchor.itemLocked = false
        ns:Refresh()
        print("|cff7fd5ffGlassTip:|r item anchor unlocked.")
    elseif msg == "lock items" or msg == "itemlock" then
        ns.db.anchor.itemLocked = true
        ns:Refresh()
        print("|cff7fd5ffGlassTip:|r item anchor locked.")
    elseif msg == "lock" then
        ns.db.anchor.locked = true
        ns:Refresh()
        print("|cff7fd5ffGlassTip:|r anchor locked.")
    elseif msg == "debug" then
        print("|cff7fd5ffGlassTip debug|r")
        for k, v in pairs(ns.hookStatus or {}) do
            print("  " .. k .. ": " .. (v == "ok" and "|cff66dd88ok|r" or ("|cffdd6666" .. v .. "|r")))
        end
        print(("  fonts: %d built-in, %d from LibSharedMedia"):format(
            ns.builtinFontCount or 0, ns.lsmFontCount or 0))
        print("  status bar: " .. (ns.usingOwnBar and "|cffddaa55using our own|r" or "|cff66dd88Blizzard bar|r"))
        if ns.lastError then print("  last error: |cffdd6666" .. tostring(ns.lastError) .. "|r") end
        local u = UnitExists("target") and "target" or (UnitExists("mouseover") and "mouseover" or nil)
        if u then
            print(("  %s: %s  hp %s / %s"):format(u, tostring(UnitName(u)),
                tostring(UnitHealth(u)), tostring(UnitHealthMax(u))))
        else
            print("  no target/mouseover to sample")
        end
    elseif msg == "reset" then
        ns:ResetProfile()
        print("|cff7fd5ffGlassTip:|r profile '" .. tostring(ns.activeProfile) .. "' reset to defaults.")
    elseif msg:match("^skin") then
        local which = msg:match("^skin%s+(.+)$")
        if which and ns.skins[which] then
            ns:SetSkin(which)
            print("|cff7fd5ffGlassTip:|r skin set to " .. ns.skins[which].name .. ".")
        else
            local list = {}
            for _, k in ipairs(ns.skinOrder) do list[#list + 1] = k end
            print("|cff7fd5ffGlassTip:|r skins: " .. table.concat(list, ", "))
        end
    elseif msg:match("^profile") then
        local which = msg:match("^profile%s+(.+)$")
        if which and GlassTipDB.profiles[which] then
            ns:ActivateProfile(which)
            print("|cff7fd5ffGlassTip:|r profile: " .. which)
        else
            print("|cff7fd5ffGlassTip:|r profiles: " .. table.concat(ns:ProfileNames(), ", ")
                .. "  (active: " .. tostring(ns.activeProfile) .. ")")
        end
    else
        if ns.ToggleOptions then ns:ToggleOptions() end
    end
end
