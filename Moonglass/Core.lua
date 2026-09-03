--[[----------------------------------------------------------------------------
    Moonglass — Core
    Saved variables, defaults, event hub, shared utilities, session gold.
------------------------------------------------------------------------------]]
local ADDON, ns = ...

ns.VERSION = "1.5.0"
ns.TEX = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\"
ns.FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

--------------------------------------------------------------------- defaults
ns.defaults = {
    shape        = "round",          -- "round" | "square"
    border       = "glass",          -- "glass" | "thin" | "glow" | "none"
    classColor   = true,             -- tint thin/glow border with class color
    borderColor  = { r = 0.85, g = 0.85, b = 0.95, a = 1 },
    vignette     = true,             -- soft inner shadow
    size         = 180,
    opacity      = 1,
    locked       = true,
    point        = { "TOPRIGHT", -24, -24 },
    autoZoomOut  = true,             -- snap back to widest view after 8s
    showPings    = true,             -- show who pinged the map
    zoneText     = "always",         -- "always" | "hover" | "never"
    hideClutter  = true,             -- zoom buttons, world-map button, day/night, clock
    questTracker = "leave",          -- "leave" | "move" | "hide"
    questTrackerGap = 12,

    bar = {
        enabled  = true,
        position = "below",          -- "below" | "above" | "detached"
        point    = { "CENTER", 0, -220 },   -- used when detached
        scale    = 1,
        width    = 0,                       -- 0 = match the map's width
        fontSize = 12,
        hour24   = false,
        serverTime = false,
        modules  = { time = true, gold = true, guild = true, fps = true, durability = true, mail = true },
    },

    bag = { enabled = true, hover = false },

    indicators = { queues = true, tracking = true, mail = true },

    farzoom = { enabled = true },
}

local function copyDefaults(src, dst)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = copyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

------------------------------------------------------------------- event hub
local hub = CreateFrame("Frame")
local callbacks = {}

function ns.RegisterEvent(event, fn)
    if not callbacks[event] then
        callbacks[event] = {}
        pcall(hub.RegisterEvent, hub, event)  -- pcall: event may not exist on this client
    end
    callbacks[event][#callbacks[event] + 1] = fn
end

hub:SetScript("OnEvent", function(_, event, ...)
    local list = callbacks[event]
    if not list then return end
    for i = 1, #list do list[i](event, ...) end
end)

-- modules register an initializer; Core runs them once the DB is ready
ns.initializers = {}
function ns.RegisterInit(fn) ns.initializers[#ns.initializers + 1] = fn end

-------------------------------------------------------------------- utilities
ns.hidden = CreateFrame("Frame")
ns.hidden:Hide()

function ns.Kill(frame)
    if frame and frame.SetParent then
        frame:SetParent(ns.hidden)
        frame:Hide()
    end
end

function ns.ClassColor()
    local _, class = UnitClass("player")
    local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

function ns.BorderColor()
    local db = ns.db
    if db.classColor then
        local r, g, b = ns.ClassColor()
        return r, g, b, 1
    end
    local c = db.borderColor
    return c.r, c.g, c.b, c.a or 1
end

local GOLD   = "|TInterface\\MoneyFrame\\UI-GoldIcon:%d:%d:2:0|t"
local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:%d:%d:2:0|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:%d:%d:2:0|t"

function ns.FormatMoney(copper, iconSize, full)
    copper = copper or 0
    local neg = copper < 0
    copper = math.abs(copper)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local sz = iconSize or 12
    local gi, si, ci = GOLD:format(sz, sz), SILVER:format(sz, sz), COPPER:format(sz, sz)
    local out
    if g > 0 then
        local gs = tostring(g)
        if g >= 1000 then gs = BreakUpLargeNumbers and BreakUpLargeNumbers(g) or gs end
        if full then
            out = ("%s%s %d%s %d%s"):format(gs, gi, s, si, c, ci)
        else
            out = ("%s%s %d%s"):format(gs, gi, s, si)
        end
    elseif s > 0 then
        out = ("%d%s %d%s"):format(s, si, c, ci)
    else
        out = ("%d%s"):format(c, ci)
    end
    if neg then out = "-" .. out end
    return out
end

function ns.SetFont(fs, size, flags)
    fs:SetFont(ns.FONT, size or 12, flags or "")
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetShadowOffset(1, -1)
end

-- one shared ticker at 1s for cheap periodic updates
local tickers = {}
function ns.RegisterTick(fn) tickers[#tickers + 1] = fn end
C_Timer.NewTicker(1, function()
    for i = 1, #tickers do
        local ok, err = pcall(tickers[i])
        if not ok then geterrorhandler()(err) end
    end
end)

--------------------------------------------------------------- session gold
ns.session = { earned = 0, spent = 0 }
local lastMoney

ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if lastMoney == nil then lastMoney = GetMoney() end
end)

ns.RegisterEvent("PLAYER_MONEY", function()
    local now = GetMoney()
    if lastMoney then
        local delta = now - lastMoney
        if delta > 0 then
            ns.session.earned = ns.session.earned + delta
        elseif delta < 0 then
            ns.session.spent = ns.session.spent - delta
        end
    end
    lastMoney = now
end)

------------------------------------------------------------------------ boot
ns.RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    MoonglassDB = copyDefaults(ns.defaults, MoonglassDB)
    ns.db = MoonglassDB
end)

local booted
ns.RegisterEvent("PLAYER_LOGIN", function()
    if booted then return end
    booted = true
    if not ns.db then
        MoonglassDB = copyDefaults(ns.defaults, MoonglassDB)
        ns.db = MoonglassDB
    end
    for i = 1, #ns.initializers do
        local ok, err = pcall(ns.initializers[i])
        if not ok then geterrorhandler()(err) end
    end
end)

----------------------------------------------------------------------- slash
SLASH_MOONGLASS1 = "/moonglass"
SLASH_MOONGLASS2 = "/mglass"
SlashCmdList.MOONGLASS = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "lock" then
        ns.db.locked = true
        if ns.ApplyMapSettings then ns.ApplyMapSettings() end
        print("|cff9db7ffMoonglass:|r map locked.")
    elseif msg == "unlock" then
        ns.db.locked = false
        if ns.ApplyMapSettings then ns.ApplyMapSettings() end
        print("|cff9db7ffMoonglass:|r map unlocked — drag it where you want, then /moonglass lock.")
    elseif msg == "buttons" then
        if ns.DumpBag then ns.DumpBag() end
    elseif msg == "reset" then
        ns.db.point = { "TOPRIGHT", -24, -24 }
        if ns.ApplyMapSettings then ns.ApplyMapSettings() end
        print("|cff9db7ffMoonglass:|r position reset.")
    else
        if ns.OpenOptions then ns.OpenOptions() end
    end
end
