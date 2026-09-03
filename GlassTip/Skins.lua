--=====================================================================
-- GlassTip - Skins
--
-- A skin is a set of values stamped into the active profile. It is a
-- starting point, not a lock: anything it sets can be changed afterwards
-- in the options, and changing it does not mark the skin as "off".
-- Anchor settings are deliberately never touched by a skin.
--=====================================================================
local ADDON, ns = ...

local FRIZ  = "Fonts\\FRIZQT__.TTF"
local MORPH = "Fonts\\MORPHEUS.TTF"

ns.skinOrder = { "blizzard", "vellum", "fel", "frostglass", "arcane" }

ns.skins = {

    ------------------------------------------------------------- Blizzard
    -- Hands the frame art back to the game and turns off everything we
    -- draw. Anchoring, the health bar, fonts, content and profiles all
    -- keep working exactly as they do on the other skins.
    blizzard = {
        name = "Blizzard",
        blurb = "The game's own frame. Every other option still applies.",
        swatch = { 0.10, 0.10, 0.16 },
        style = {
            blizzard    = true,
            bgTexture   = "",
            grain       = 0,
            borderMode  = "custom",
            border      = { 0.32, 0.36, 0.45 },
            borderSize  = 1,
            inner       = false,
            accent      = false,
            glow        = 0,
            brackets    = false,
            shadow      = false,
            gloss       = false,
            font        = FRIZ,
            nameSize    = 15,
            bodySize    = 12,
            outline     = "NONE",
        },
        bar = { height = 12, colorMode = "reaction", sheen = true, textInside = true, textSize = 11 },
        palette = {
            label = "8d93a3", tag = "ffd45a", type = "9a9aa8",
            guild = "8fd6c0", rank = "b6b8c4", sep = "5f6470",
            barText = "f5f6fa", barSub = "b8bcc8",
        },
    },

    --------------------------------------------------------------- Vellum
    vellum = {
        name = "Vellum",
        blurb = "Aged paper and a double gold frame. Serif type.",
        swatch = { 0.91, 0.86, 0.74 },
        style = {
            blizzard    = false,
            bg          = { 0.91, 0.86, 0.74 },
            bgAlpha     = 0.97,
            bgTexture   = "PARCHMENT",
            bgTexTint   = { 0.94, 0.88, 0.74 },
            grain       = 0,
            borderMode  = "custom",
            border      = { 0.48, 0.36, 0.18 },
            borderSize  = 2,
            inner       = true,
            innerColor  = { 0.72, 0.58, 0.35 },
            innerAlpha  = 0.85,
            innerInset  = 4,
            accent      = false,
            accentSize  = 2,
            glow        = 0,
            brackets    = false,
            shadow      = true,
            gloss       = false,
            font        = MORPH,
            nameSize    = 16,
            bodySize    = 13,
            outline     = "NONE",
        },
        bar = { height = 16, colorMode = "reaction", sheen = true, textInside = true, textSize = 12 },
        palette = {
            label = "6b5836", tag = "8a6410", type = "7d6c4c",
            guild = "4a6b52", rank = "6b5836", sep = "9a8558",
            barText = "f7ecd6", barSub = "e4d5b4",
        },
    },

    ----------------------------------------------------------------- Fel
    fel = {
        name = "Fel",
        blurb = "Outland green, with the border bleeding light outward.",
        swatch = { 0.56, 0.88, 0.29 },
        style = {
            blizzard    = false,
            bg          = { 0.031, 0.075, 0.047 },
            bgAlpha     = 0.93,
            bgTexture   = "",
            grain       = 0.05,
            borderMode  = "custom",
            border      = { 0.56, 0.88, 0.29 },
            borderSize  = 1,
            inner       = false,
            accent      = true,
            accentSize  = 2,
            glow        = 0.55,
            glowMode    = "custom",
            glowColor   = { 0.42, 0.85, 0.20 },
            glowSize    = 18,
            brackets    = false,
            shadow      = false,
            gloss       = true,
            font        = FRIZ,
            nameSize    = 15,
            bodySize    = 12,
            outline     = "NONE",
        },
        bar = { height = 16, colorMode = "reaction", sheen = true, textInside = true, textSize = 11 },
        palette = {
            label = "6f8a63", tag = "d8f56a", type = "7f9a75",
            guild = "9be07a", rank = "89a37e", sep = "4e6647",
            barText = "0c2109", barSub = "1d3a17",
        },
    },

    ---------------------------------------------------------- Frostglass
    frostglass = {
        name = "Frostglass",
        blurb = "Pale frosted panel. Reads well over dark ground.",
        swatch = { 0.86, 0.92, 0.96 },
        style = {
            blizzard    = false,
            bg          = { 0.86, 0.92, 0.96 },
            bgAlpha     = 0.88,
            bgTexture   = "",
            grain       = 0.035,
            borderMode  = "reaction",
            border      = { 0.49, 0.77, 0.92 },
            borderSize  = 1,
            inner       = true,
            innerColor  = { 1, 1, 1 },
            innerAlpha  = 0.55,
            innerInset  = 2,
            accent      = true,
            accentSize  = 2,
            glow        = 0.22,
            glowMode    = "custom",
            glowColor   = { 0.60, 0.82, 0.95 },
            glowSize    = 12,
            brackets    = false,
            shadow      = true,
            gloss       = true,
            font        = FRIZ,
            nameSize    = 15,
            bodySize    = 12,
            outline     = "NONE",
        },
        bar = { height = 15, colorMode = "reaction", sheen = true, textInside = true, textSize = 11 },
        palette = {
            label = "5b7285", tag = "8a6a12", type = "63788a",
            guild = "1f6b57", rank = "4a5f6e", sep = "8fa5b4",
            barText = "12303f", barSub = "3d5a6b",
        },
    },

    -------------------------------------------------------------- Arcane
    arcane = {
        name = "Arcane",
        blurb = "Deep indigo, gold frame and corner brackets. Serif type.",
        swatch = { 0.85, 0.71, 0.29 },
        style = {
            blizzard    = false,
            bg          = { 0.082, 0.063, 0.122 },
            bgAlpha     = 0.95,
            bgTexture   = "",
            grain       = 0.045,
            borderMode  = "custom",
            border      = { 0.85, 0.71, 0.29 },
            borderSize  = 1,
            inner       = true,
            innerColor  = { 0.85, 0.71, 0.29 },
            innerAlpha  = 0.28,
            innerInset  = 3,
            accent      = true,
            accentSize  = 2,
            glow        = 0.18,
            glowMode    = "custom",
            glowColor   = { 0.52, 0.34, 0.72 },
            glowSize    = 14,
            brackets    = true,
            bracketColor= { 0.85, 0.71, 0.29 },
            bracketSize = 20,
            shadow      = true,
            gloss       = true,
            font        = MORPH,
            nameSize    = 16,
            bodySize    = 13,
            outline     = "NONE",
        },
        bar = { height = 16, colorMode = "reaction", sheen = true, textInside = true, textSize = 12 },
        palette = {
            label = "8b83a0", tag = "d8b44a", type = "9a92ad",
            guild = "b98ce6", rank = "a79cc0", sep = "5c5273",
            barText = "f4ecff", barSub = "c3b2da",
        },
    },
}

--=====================================================================
-- Applying
--=====================================================================
local function stamp(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = { unpack(v) }
        else
            dst[k] = v
        end
    end
end

function ns:SetSkin(key)
    local skin = ns.skins[key]
    if not skin or not ns.db then return end

    stamp(ns.db.style, skin.style)
    stamp(ns.db.bar, skin.bar)
    stamp(ns.db.palette, skin.palette)

    -- resolve texture placeholders to real paths now that MEDIA is known
    if ns.db.style.bgTexture == "PARCHMENT" then
        ns.db.style.bgTexture = ns.TEX.parchment
    end

    ns.db.skin = key
    ns:Refresh()
    if ns.RefreshOptions then ns:RefreshOptions() end
end

function ns:CurrentSkin()
    return ns.db and ns.db.skin
end
