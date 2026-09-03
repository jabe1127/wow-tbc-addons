-- =========================================================================
-- Quiver - Core.lua
-- Shared foundation for the shot alert feed: saved variables, small API
-- shims, and slash commands.
-- =========================================================================

local ADDON, TS = ...

TS.version = "3.0.0"
TS.modules = {}
TS.inits   = {}
TS.testing = false

TS.FONT = "Fonts\\FRIZQT__.TTF"

-- ------------------------------------------------- small API compat shims
function TS.SpellTexture(spellID)
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellID)
    end
    if GetSpellTexture then
        return GetSpellTexture(spellID)
    end
end

function TS.SpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellID)
    end
    if GetSpellInfo then
        return (GetSpellInfo(spellID))
    end
end

-- Seconds remaining on a spell's cooldown, ignoring the global cooldown.
-- Returns 0 when ready.
function TS.SpellCooldown(spell)
    if not spell then return 0 end
    local start, duration
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(spell)
        if info then start, duration = info.startTime, info.duration end
    elseif GetSpellCooldown then
        start, duration = GetSpellCooldown(spell)
    end
    if not start or not duration or duration <= 2 then return 0 end
    local left = (start + duration) - GetTime()
    return left > 0 and left or 0
end

-- --------------------------------------------------------------- defaults
TS.defaults = {
    locked = true,
    optionsTab = "feed",     -- which options page was last open
    blacklist = {},          -- [spellID] = spellName, never announced
    alerts = {
        enabled  = true,
        size     = 44,
        duration = 1.1,
        growth   = "UP",          -- UP | DOWN | LEFT | RIGHT
        spacing  = 6,
        showName = true,
        sound    = false,
        point = "CENTER", relPoint = "CENTER", x = 0, y = -120,

        showAuto   = true,        -- Auto Shot repeats on its own
        showMelee  = true,        -- melee swings aren't casts
        readySweep = true,        -- cooldown sweep on the icon
    },
    colors = {
        cast  = { 1.00, 0.82, 0.25 },
        auto  = { 0.55, 0.68, 0.90 },
        melee = { 0.85, 0.60, 0.35 },
    },
    warnings = {
        pos = {},               -- saved drag positions per readout
        -- melee glow
        glow           = true,
        glowHeight     = 70,
        glowAlpha      = 0.55,
        glowFalloff    = 1.6,   -- 1.0 solid slab, 3.0 thin lip + soft tail
        glowColor      = { 1.00, 0.55, 0.20 },
        -- swing fill (out of melee only)
        glowSwing      = true,
        glowSwingAlpha = 0.45,
        swingColor     = { 1.00, 1.00, 1.00 },
        -- text warnings
        showAspect    = true,
        showPetWarn   = true,
        showPetDanger = true,
        petWarnPct    = 70,
        petDangerPct  = 35,
        fontWarn      = 13,
        fontDanger    = 24,
    },
}

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(v, type(dst[k]) == "table" and dst[k] or {})
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

-- ------------------------------------------------------------ blacklist
function TS.IsBlocked(spellID)
    return spellID ~= nil and TS.db.blacklist[spellID] ~= nil
end

function TS.Block(spellID)
    if not spellID then return false end
    local name = TS.SpellName(spellID)
    TS.db.blacklist[spellID] = name or ("Spell " .. spellID)
    return true, name
end

function TS.Unblock(spellID)
    if not spellID or TS.db.blacklist[spellID] == nil then return false end
    local name = TS.db.blacklist[spellID]
    TS.db.blacklist[spellID] = nil
    return true, name
end

function TS.BlockedCount()
    local n = 0
    for _ in pairs(TS.db.blacklist) do n = n + 1 end
    return n
end

function TS.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd200Quiver:|r " .. msg)
end

-- ---------------------------------------------------------- lock / test
function TS.SetLocked(locked, silent)
    TS.db.locked = locked
    for _, m in ipairs(TS.modules) do
        m.SetPreview(not locked)
    end
    if silent then return end
    TS.Print(locked and "Anchor locked."
                     or "Anchor unlocked - drag it, then |cffffd200/qv lock|r.")
end

function TS.SetTesting(on)
    TS.testing = on
    for _, m in ipairs(TS.modules) do
        m.Test(on)
    end
    TS.Print(on and "Test mode ON. |cffffd200/qv test|r again to stop."
                 or "Test mode off.")
end

local function RefreshAll()
    for _, m in ipairs(TS.modules) do
        m.ApplyConfig()
    end
end
TS.RefreshAll = RefreshAll

function TS.ResetDB()
    wipe(TS.db)
    CopyDefaults(TS.defaults, TS.db)
    RefreshAll()
end

-- ------------------------------------------------------------------ init
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")

    -- carry settings over from the TrueShot days
    if not QuiverDB and type(TrueShotDB) == "table" then
        QuiverDB = TrueShotDB
    end
    QuiverDB = QuiverDB or {}
    CopyDefaults(TS.defaults, QuiverDB)
    TS.db = QuiverDB

    for _, init in ipairs(TS.inits) do
        local ok, err = pcall(init, TS.db)
        if not ok then
            TS.Print("|cffff4040A module failed to load:|r " .. tostring(err))
        end
    end
end)

-- -------------------------------------------------------- slash commands
local function Toggle(key, label)
    local a = TS.db.alerts
    a[key] = not a[key]
    TS.Print(label .. (a[key] and " |cff40ff40on|r." or " |cffff4040off|r."))
    RefreshAll()
end

SLASH_QUIVER1 = "/quiver"
SLASH_QUIVER2 = "/qv"
SlashCmdList.QUIVER = function(msg)
    local db = TS.db
    if not db then return end
    local cmd, a1 = strsplit(" ", strtrim(msg or ""):lower())

    if cmd == "unlock" then
        TS.SetLocked(false)
    elseif cmd == "lock" then
        TS.SetLocked(true)
    elseif cmd == "test" then
        TS.SetTesting(not TS.testing)
    elseif cmd == "reset" then
        TS.ResetDB()
        TS.Print("Settings reset.")
    elseif cmd == "size" then
        local n = tonumber(a1)
        if not n then
            TS.Print("Usage: /qv size <24-96>")
            return
        end
        db.alerts.size = math.max(24, math.min(96, n))
        RefreshAll()
        TS.Print("Alert size set to " .. db.alerts.size .. ".")
    elseif cmd == "sound" then
        Toggle("sound", "Alert sound")
    elseif cmd == "melee" then
        Toggle("showMelee", "Melee swing alerts")
    elseif cmd == "auto" then
        Toggle("showAuto", "Auto Shot alerts")

    elseif cmd == "glow" then
        db.warnings.glow = not db.warnings.glow
        TS.Print("Melee glow " .. (db.warnings.glow and "|cff40ff40on|r." or "|cffff4040off|r."))
        RefreshAll()

    elseif cmd == "swingfill" then
        db.warnings.glowSwing = not db.warnings.glowSwing
        TS.Print("Swing fill " .. (db.warnings.glowSwing and "|cff40ff40on|r." or "|cffff4040off|r."))
        RefreshAll()

    elseif cmd == "aspect" then
        db.warnings.showAspect = not db.warnings.showAspect
        TS.Print("Aspect warning " .. (db.warnings.showAspect and "|cff40ff40on|r." or "|cffff4040off|r."))
        RefreshAll()

    elseif cmd == "pet" then
        local on = not db.warnings.showPetWarn
        db.warnings.showPetWarn = on
        db.warnings.showPetDanger = on
        TS.Print("Pet warnings " .. (on and "|cff40ff40on|r." or "|cffff4040off|r."))
        RefreshAll()

    elseif cmd == "block" then
        local id = tonumber(a1) or TS.lastSpellID
        if not id then
            TS.Print("Nothing to block yet. Use |cffffd200/qv block <spellID>|r," ..
                     " or cast something and run |cffffd200/qv block|r.")
            return
        end
        local _, name = TS.Block(id)
        TS.Print("Blocked " .. (name or ("spell " .. id)) ..
                 " |cff808080(" .. id .. ")|r.")
        RefreshAll()

    elseif cmd == "unblock" then
        local id = tonumber(a1)
        if not id then
            TS.Print("Usage: |cffffd200/qv unblock <spellID>|r")
            return
        end
        local ok, name = TS.Unblock(id)
        TS.Print(ok and ("Unblocked " .. (name or id) .. ".")
                     or ("Spell " .. id .. " wasn't blocked."))
        RefreshAll()

    elseif cmd == "blocked" then
        local n = TS.BlockedCount()
        if n == 0 then
            TS.Print("Nothing blocked.")
            return
        end
        TS.Print("Blocked (" .. n .. "):")
        for id, name in pairs(db.blacklist) do
            DEFAULT_CHAT_FRAME:AddMessage("   " .. tostring(name) ..
                " |cff808080" .. id .. "|r  |cffffd200/qv unblock " .. id .. "|r")
        end

    elseif cmd == "clearblocked" then
        wipe(db.blacklist)
        TS.Print("Blocklist cleared.")
        RefreshAll()
    elseif cmd == "" or cmd == "config" or cmd == "options" then
        if TS.ToggleOptions then TS.ToggleOptions() end
    else
        TS.Print("Quiver v" .. TS.version .. " commands:")
        for _, l in ipairs({
            "|cffffd200/qv|r - open the options window",
            "|cffffd200/qv unlock|r / |cffffd200lock|r - move the alert anchor",
            "|cffffd200/qv test|r - animated preview",
            "|cffffd200/qv size <px>|r - icon size",
            "|cffffd200/qv melee|r - toggle melee swing alerts",
            "|cffffd200/qv auto|r - toggle Auto Shot alerts",
            "|cffffd200/qv glow|r - melee range glow",
            "|cffffd200/qv swingfill|r - swing fill while out of melee",
            "|cffffd200/qv aspect|r - wrong-aspect warning",
            "|cffffd200/qv pet|r - pet health warnings",
            "|cffffd200/qv block [id]|r - block a spell (no id = last one cast)",
            "|cffffd200/qv unblock <id>|r - unblock a spell",
            "|cffffd200/qv blocked|r - list blocked spells",
            "|cffffd200/qv sound|r - toggle the alert sound",
            "|cffffd200/qv reset|r - restore defaults",
        }) do
            DEFAULT_CHAT_FRAME:AddMessage("   " .. l)
        end
    end
end
