--[[--------------------------------------------------------------------------
    JCT - Format.lua
    Number formatting, inline icons, colour resolution.

    Kept allocation-light: this runs once per displayed message, which in a
    25-man raid can be a few hundred times per second before merging.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

local Format = {}
ns.Format = Format

local format, floor, abs = string.format, math.floor, math.abs
local tostring = tostring

--------------------------------------------------------------------------
-- Numbers
--------------------------------------------------------------------------

-- 1234567 -> "1,234,567"
local function withSeparators(n)
    local s = tostring(n)
    local out, count = "", 0
    for i = #s, 1, -1 do
        out = s:sub(i, i) .. out
        count = count + 1
        if count % 3 == 0 and i > 1 then out = "," .. out end
    end
    return out
end

function Format.Number(value)
    local f = ns.db and ns.db.format
    if not f then return tostring(value) end

    local n = value
    local negative = false
    if n < 0 then negative = true; n = -n end
    n = floor(n + 0.5)

    local s
    if f.abbreviate and n >= 1000 then
        if n >= 1000000 then
            s = format("%.1fm", n / 1000000)
        else
            s = format("%.1fk", n / 1000)
        end
        -- trim a trailing ".0"
        s = s:gsub("%.0([km])$", "%1")
    elseif f.separators and n >= 1000 then
        s = withSeparators(n)
    else
        s = tostring(n)
    end

    if negative then s = "-" .. s end
    return s
end

--------------------------------------------------------------------------
-- Icons
--
-- The 64:64:5:59:5:59 tail crops the 5px bevel off a standard 64px icon so
-- it sits flush with the text instead of floating in a grey box.
--------------------------------------------------------------------------

local iconCache = {}

function Format.Icon(texture, size)
    if not texture then return nil end
    size = size or 16
    local key = tostring(texture) .. ":" .. size
    local cached = iconCache[key]
    if cached then return cached end
    local s = format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t", texture, size, size)
    iconCache[key] = s
    return s
end

function Format.SpellIcon(spellID, size)
    if not spellID then return nil end
    local tex = ns.compat.GetSpellTexture(spellID)
    if not tex then return nil end
    return Format.Icon(tex, size)
end

--------------------------------------------------------------------------
-- Colours
--------------------------------------------------------------------------

local WHITE = { 1, 1, 1 }

function Format.ClassColor(classKey)
    local c = ns.db and ns.db.colors and ns.db.colors[classKey]
    if c then return c[1], c[2], c[3] end
    return 1, 1, 1
end

function Format.SchoolColor(mask, fallbackClass)
    local db = ns.db
    if not db then return 1, 1, 1 end
    if db.colors.useSchoolColors and mask then
        local c = db.schoolColors[mask]
        if c then return c[1], c[2], c[3] end
        -- Unknown hybrid mask: use the lowest set bit we recognise.
        local m = 1
        while m <= 64 do
            if bit.band(mask, m) ~= 0 then
                local cc = db.schoolColors[m]
                if cc then return cc[1], cc[2], cc[3] end
            end
            m = m * 2
        end
    end
    return Format.ClassColor(fallbackClass or "outDamage")
end

function Format.HexColor(r, g, b)
    return format("%02x%02x%02x", floor(r * 255), floor(g * 255), floor(b * 255))
end

--------------------------------------------------------------------------
-- Message assembly
--
-- opts = {
--   amount     = number or nil
--   text       = string or nil   (used instead of amount)
--   spellID    = number or nil
--   spellName  = string or nil
--   count      = number or nil   (merge count; > 1 appends "xN")
--   crit       = boolean
--   iconSize   = number
--   iconSide   = "LEFT" | "RIGHT" | "NONE"
-- }
--------------------------------------------------------------------------

function Format.Build(opts)
    local f = ns.db.format
    local body

    if opts.text then
        body = opts.text
    else
        body = Format.Number(opts.amount or 0)
    end

    if opts.crit then
        if f.critPrefix ~= "" then body = f.critPrefix .. body end
        if f.critSuffix ~= "" then body = body .. f.critSuffix end
    end

    if opts.suffix and not opts.text then
        body = body .. " " .. opts.suffix
    end

    if f.showSpellName and opts.spellName and not opts.text then
        body = opts.spellName .. " " .. body
    end

    if f.showCount and opts.count and opts.count > 1 then
        body = body .. format(" |cff9d9d9dx%d|r", opts.count)
    end

    if f.icons and opts.iconSide and opts.iconSide ~= "NONE" then
        local icon = opts.iconTexture and Format.Icon(opts.iconTexture, opts.iconSize)
                     or Format.SpellIcon(opts.spellID, opts.iconSize)
        if icon then
            if opts.iconSide == "RIGHT" then
                body = body .. " " .. icon
            else
                body = icon .. " " .. body
            end
        end
    end

    return body
end

--------------------------------------------------------------------------
-- Power type names (TBC set)
--------------------------------------------------------------------------

Format.POWER_NAMES = {
    [0] = "Mana",
    [1] = "Rage",
    [2] = "Focus",
    [3] = "Energy",
    [4] = "Happiness",
    [5] = "Runes",
    [6] = "Runic Power",
}

-- Power gains deliberately use the user-configurable "Power gains" colour
-- rather than a hardcoded per-resource palette, so the colour swatch in the
-- options window actually does something.
