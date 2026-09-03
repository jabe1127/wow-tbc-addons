-- LogLovers Util: shims, formatting helpers, unit info cache
local ADDON, NS = ...

local band = bit.band
local format = string.format

-- exposed so other files can test combat log object flags without re-importing bit
NS.Band = band

-------------------------------------------------------------------------------
-- API shims (TBC Anniversary 2.5.5/2.5.6, tolerant of modernized APIs)
-------------------------------------------------------------------------------
NS.GetSpellTexture = _G.GetSpellTexture
    or (C_Spell and C_Spell.GetSpellTexture)
    or function() return nil end

NS.GetSpellLink = _G.GetSpellLink
    or (C_Spell and C_Spell.GetSpellLink)
    or function() return nil end

function NS.SetResizeLimits(frame, minW, minH, maxW, maxH)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(minW, minH, maxW, maxH)
    else
        if frame.SetMinResize then frame:SetMinResize(minW, minH) end
        if frame.SetMaxResize and maxW then frame:SetMaxResize(maxW, maxH) end
    end
end

function NS.OpenColorPicker(r, g, b, a, callback)
    local function apply()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        local na = 1
        if ColorPickerFrame.GetColorAlpha then
            na = ColorPickerFrame:GetColorAlpha()
        elseif OpacitySliderFrame then
            na = 1 - OpacitySliderFrame:GetValue()
        end
        callback(nr, ng, nb, na)
    end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b, opacity = a, hasOpacity = true,
            swatchFunc = apply, opacityFunc = apply,
            cancelFunc = function(prev)
                if prev then callback(prev.r, prev.g, prev.b, prev.a or prev.opacity or 1) end
            end,
        })
    else
        ColorPickerFrame.hasOpacity = true
        ColorPickerFrame.opacity = 1 - (a or 1)
        ColorPickerFrame.previousValues = { r = r, g = g, b = b, opacity = 1 - (a or 1) }
        ColorPickerFrame.func = apply
        ColorPickerFrame.opacityFunc = apply
        ColorPickerFrame.cancelFunc = function(prev)
            if prev then callback(prev.r, prev.g, prev.b, 1 - (prev.opacity or 0)) end
        end
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end
end

-------------------------------------------------------------------------------
-- Text helpers
-------------------------------------------------------------------------------
function NS.C(text, hex)
    return "|cff" .. hex .. text .. "|r"
end

function NS.RGBToHex(r, g, b)
    return format("%02x%02x%02x", (r or 1) * 255, (g or 1) * 255, (b or 1) * 255)
end

local function commaFormat(n)
    local s = tostring(math.floor(n))
    local out, k = s, nil
    while true do
        out, k = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return out
end

function NS.FormatNumber(n)
    if not n then return "0" end
    local mode = NS.db and NS.db.general.numberMode or "full"
    if mode == "short" then
        local a = math.abs(n)
        if a >= 1000000 then return format("%.2fm", n / 1000000) end
        if a >= 10000 then return format("%.1fk", n / 1000) end
    end
    return commaFormat(n)
end

function NS.SchoolInfo(school)
    if not school or school == 0 then return NS.SCHOOLS[0x01] end
    for _, mask in ipairs(NS.SCHOOL_ORDER) do
        if band(school, mask) ~= 0 then return NS.SCHOOLS[mask] end
    end
    return NS.SCHOOLS[0x01]
end

function NS.SchoolName(school)
    if not school or school == 0 then return "Physical" end
    local names
    for _, mask in ipairs(NS.SCHOOL_ORDER) do
        if band(school, mask) ~= 0 then
            if names then names = NS.SCHOOLS[mask].name .. "/" .. names
            else names = NS.SCHOOLS[mask].name end
        end
    end
    return names or "Physical"
end

function NS.IconTag(spellId, size)
    if not (NS.db and NS.db.appearance.showIcons) then return "" end
    local tex = spellId and NS.GetSpellTexture(spellId)
    if not tex then return "" end
    size = size or (NS.db and NS.db.appearance.iconSize) or 14
    return format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t ", tex, size, size)
end

function NS.RaidIconTag(raidFlags, size)
    if not raidFlags or raidFlags == 0 then return "" end
    for i = 1, 8 do
        local mask = 2 ^ (i - 1)
        if band(raidFlags, mask) ~= 0 then
            return format("|T" .. NS.RAID_ICON_TEX .. ":%d|t", i, size or 12)
        end
    end
    return ""
end

-- Blizzard turns {rt1}..{rt8} and {star}/{skull}/etc into raid-target textures
-- inside its own chat handler. Log Lovers formats chat itself, so that step has
-- to happen here or the raw braces show up in the line.
local RAID_ICON_TOKENS = {
    star = 1, rt1 = 1,
    circle = 2, coin = 2, rt2 = 2,
    diamond = 3, rt3 = 3,
    triangle = 4, rt4 = 4,
    moon = 5, rt5 = 5,
    square = 6, rt6 = 6,
    cross = 7, x = 7, rt7 = 7,
    skull = 8, rt8 = 8,
}
NS.RAID_ICON_TOKENS = RAID_ICON_TOKENS

function NS.ReplaceIconTokens(text)
    if type(text) ~= "string" then return text end
    if not string.find(text, "{", 1, true) then return text end
    local out = string.gsub(text, "{(%a+%d*)}", function(tok)
        local i = RAID_ICON_TOKENS[string.lower(tok)]
        if not i then return nil end
        -- :0 tells the client to scale the texture to the current font height
        return format("|T" .. NS.RAID_ICON_TEX .. ":0|t", i)
    end)
    return out
end

-- Can the client actually load this font file? Asked before committing a
-- custom path, because everything the addon draws - including the options
-- panel - uses whatever font is set.
local fontProbe
function NS.FontLoads(path)
    if type(path) ~= "string" or path == "" then return false end
    if not fontProbe then
        local f = CreateFrame("Frame", nil, UIParent)
        f:Hide()
        fontProbe = f:CreateFontString(nil, "OVERLAY")
    end
    if not fontProbe or not fontProbe.SetFont then return true end
    local ok, applied = pcall(fontProbe.SetFont, fontProbe, path, 12, "")
    if not ok then return false end
    -- SetFont returns false on a bad path in modern clients and nil on older
    -- ones, where GetFont is the only way to tell
    if applied == false then return false end
    local got = fontProbe.GetFont and fontProbe:GetFont()
    if got == nil then return false end
    return true
end

function NS.StripEscapes(text)
    -- A raid marker goes back to the token that produced it, so searching for
    -- "skull" still finds the line and copying it out still says what was
    -- marked, instead of leaving a hole where the icon was
    text = string.gsub(text, "|TInterface\\TargetingFrame\\UI%-RaidTargetingIcon_(%d)[^|]*|t",
        function(i) return "{rt" .. i .. "}" end)
    text = string.gsub(text, "|T[^|]*|t", "")
    text = string.gsub(text, "|H[^|]*|h(%[?)", "%1")
    text = string.gsub(text, "|h", "")
    text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    text = string.gsub(text, "|r", "")
    return text
end

-------------------------------------------------------------------------------
-- Unit info / flags
-------------------------------------------------------------------------------
local OBJ = {
    AFF_MINE     = COMBATLOG_OBJECT_AFFILIATION_MINE or 0x00000001,
    AFF_PARTY    = COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x00000002,
    AFF_RAID     = COMBATLOG_OBJECT_AFFILIATION_RAID or 0x00000004,
    REACT_FRIEND = COMBATLOG_OBJECT_REACTION_FRIENDLY or 0x00000010,
    REACT_NEUT   = COMBATLOG_OBJECT_REACTION_NEUTRAL or 0x00000020,
    REACT_HOSTILE= COMBATLOG_OBJECT_REACTION_HOSTILE or 0x00000040,
    TYPE_PLAYER  = COMBATLOG_OBJECT_TYPE_PLAYER or 0x00000400,
    TYPE_PET     = COMBATLOG_OBJECT_TYPE_PET or 0x00001000,
    TYPE_GUARDIAN= COMBATLOG_OBJECT_TYPE_GUARDIAN or 0x00002000,
}
NS.OBJ = OBJ

-- True for anything that is not another player: mobs, bosses, totems, pets.
-- Flags are missing on some synthesised records, in which case "not a player"
-- is the safer answer for the callers that use this to widen a filter.
function NS.IsNPC(flags)
    if not flags then return false end
    return band(flags, OBJ.TYPE_PLAYER) == 0
end

-- Role of a unit relative to the player: player/pet/party/raid/friendly/hostile/neutral
function NS.RoleOf(guid, flags)
    if not flags then return "neutral" end
    local isMine = band(flags, OBJ.AFF_MINE) ~= 0
    local isPetType = band(flags, OBJ.TYPE_PET) ~= 0 or band(flags, OBJ.TYPE_GUARDIAN) ~= 0
    if isMine then
        if isPetType then return "pet" end
        if guid and guid == NS.playerGUID then return "player" end
        return "pet" -- mine but not me: totems/guardians
    end
    if band(flags, OBJ.AFF_PARTY) ~= 0 then return "party" end
    if band(flags, OBJ.AFF_RAID) ~= 0 then return "raid" end
    if band(flags, OBJ.REACT_HOSTILE) ~= 0 then return "hostile" end
    if band(flags, OBJ.REACT_FRIEND) ~= 0 then return "friendly" end
    return "neutral"
end

-- Class color cache by GUID
local classCache = {}
function NS.UnitColor(guid, name, flags)
    if guid and classCache[guid] then return classCache[guid] end
    local hex, resolved
    if guid and NS.db and NS.db.appearance.classColors
        and flags and band(flags, OBJ.TYPE_PLAYER) ~= 0 then
        local _, class = GetPlayerInfoByGUID(guid)
        if class and RAID_CLASS_COLORS[class] then
            local c = RAID_CLASS_COLORS[class]
            hex = NS.RGBToHex(c.r, c.g, c.b)
            resolved = true
        end
    end
    if not hex and flags then
        local role = NS.RoleOf(guid, flags)
        if role == "hostile" then hex = NS.COLORS.hostile
        elseif role == "neutral" then hex = NS.COLORS.neutral
        elseif role == "pet" then hex = NS.COLORS.pet
        else hex = NS.COLORS.friendly end
    end
    hex = hex or NS.COLORS.text
    -- Only remember a colour we actually looked up. The fallback role colour
    -- used to be cached too, so anyone whose class the client had not learned
    -- yet - exactly the people you meet mid-fight in a BG or a pug - stayed
    -- the wrong colour for the rest of the session.
    if guid and resolved then classCache[guid] = hex end
    return hex
end

function NS.ClassOf(guid)
    if not guid then return nil end
    local _, class = GetPlayerInfoByGUID(guid)
    return class
end

function NS.WipeClassCache()
    wipe(classCache)
end

-------------------------------------------------------------------------------
-- Timestamps
-------------------------------------------------------------------------------
function NS.FormatTime(rec)
    local mode = NS.db.general.timestampMode
    if mode == "none" then return "" end
    if mode == "combat" then
        local base = rec.segStart
        if base then
            local d = rec.t - base
            return NS.C(format("%d:%04.1f ", math.floor(d / 60), d % 60), NS.COLORS.timestamp)
        end
        return NS.C("--:-- ", NS.COLORS.timestamp)
    end
    local frac = ""
    if mode == "hmsms" then
        frac = format(".%03d", math.floor((rec.t % 1) * 1000))
    end
    return NS.C(date("%H:%M:%S", rec.t) .. frac .. " ", NS.COLORS.timestamp)
end

-------------------------------------------------------------------------------
-- Misc
-------------------------------------------------------------------------------
function NS.DeepCopy(src)
    if type(src) ~= "table" then return src end
    local t = {}
    for k, v in pairs(src) do t[k] = NS.DeepCopy(v) end
    return t
end

function NS.MergeDefaults(dst, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            NS.MergeDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = NS.DeepCopy(v)
        end
    end
    return dst
end

function NS.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(NS.C("Log Lovers: ", NS.COLORS.accent) .. tostring(msg))
end

-- A continuation line: same destination, no prefix. Printing "Log Lovers:" in
-- front of every line of a multi-line answer buries the answer.
function NS.PrintRaw(msg)
    DEFAULT_CHAT_FRAME:AddMessage(tostring(msg))
end

function NS.CurrentFont()
    local ap = NS.db.appearance
    if ap.customFont and ap.customFont ~= "" then return ap.customFont end
    return ap.font
end

-------------------------------------------------------------------------------
-- Alert sounds
-------------------------------------------------------------------------------
function NS.SoundByKey(key)
    for _, s in ipairs(NS.ALERT_SOUNDS) do
        if s.key == key then return s end
    end
end

-- Sounds contributed by LibSharedMedia, if the user has it. Keys are prefixed
-- so they can never collide with our built-ins. Cached, because this is
-- reachable from the combat log event handler.
local lsmSounds, lsmCount = nil, -1
function NS.SharedMediaSounds()
    local LSM
    if LibStub then
        local ok, lib = pcall(LibStub, "LibSharedMedia-3.0", true)
        if ok then LSM = lib end
    end
    if not LSM then
        lsmSounds, lsmCount = {}, 0
        return lsmSounds
    end
    local ok2, tbl = pcall(LSM.HashTable, LSM, "sound")
    if not ok2 or type(tbl) ~= "table" then
        lsmSounds, lsmCount = lsmSounds or {}, lsmCount
        return lsmSounds
    end
    local n = 0
    for _ in pairs(tbl) do n = n + 1 end
    if lsmSounds and n == lsmCount then return lsmSounds end

    local out = {}
    for name, path in pairs(tbl) do
        out[#out + 1] = { key = "lsm:" .. name, name = name .. " (LSM)", file = path }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    lsmSounds, lsmCount = out, n
    return out
end

function NS.ResolveSound(key, customPath)
    if not key or key == "none" then return nil end
    if key == "custom" then
        if customPath and customPath ~= "" then return { file = customPath } end
        return nil
    end
    local lsmName = type(key) == "string" and key:match("^lsm:(.+)$")
    if lsmName then
        for _, s in ipairs(NS.SharedMediaSounds()) do
            if s.key == key then return s end
        end
        return nil
    end
    return NS.SoundByKey(key)
end

-- Plays a sound by key. Returns true if something was actually asked to play,
-- which is what the options preview button reports back to the user.
function NS.PlayAlertSound(key, customPath)
    local s = NS.ResolveSound(key, customPath)
    if not s then return false end
    if s.file then
        if not PlaySoundFile then return false end
        local ok, willPlay = pcall(PlaySoundFile, s.file, "Master")
        return ok and willPlay ~= false
    end
    local id = s.id
    if s.kit and type(SOUNDKIT) == "table" and SOUNDKIT[s.kit] then
        id = SOUNDKIT[s.kit]
    end
    if not id or not PlaySound then return false end
    local ok, willPlay = pcall(PlaySound, id, "Master")
    if not ok then ok, willPlay = pcall(PlaySound, id) end
    return ok and willPlay ~= false
end

-- The sound a given highlight should use, honouring the global default.
function NS.HighlightSoundKey(hl)
    -- highlights can arrive from an imported profile, so never assume a table
    if type(hl) ~= "table" then return "none" end
    if hl.soundKey then return hl.soundKey end
    -- pre-1.5 highlights only had a true/false "sound" flag
    if hl.sound == false then return "none" end
    return NS.db.general.highlightSoundKey or NS.DEFAULT_ALERT_SOUND
end
