--[[----------------------------------------------------------------------------
    Moonglass — Info Bar
    Gold + session gold, time, guild online, FPS/latency, durability.
------------------------------------------------------------------------------]]
local _, ns = ...

local bar
local modules = {}      -- ordered list of module tables
local BarDragStart, BarDragStop   -- defined below, used by module buttons

local function ShortName(name)
    if not name then return "?" end
    if Ambiguate then return Ambiguate(name, "guild") end
    return name:match("^([^%-]+)") or name
end

local function classColorStr(classFileName)
    local c = classFileName and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFileName]
    if c then return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) end
    return "|cffffffff"
end

------------------------------------------------------------------ framework
local function NewModule(key, order)
    local m = { key = key, order = order }
    modules[#modules + 1] = m
    return m
end

local function BuildModuleFrames()
    table.sort(modules, function(a, b) return a.order < b.order end)
    for i = 1, #modules do
        local m = modules[i]
        local btn = CreateFrame("Button", "MoonglassBarModule" .. m.key, bar)
        btn:SetHeight(18)
        local fs = btn:CreateFontString(nil, "OVERLAY")
        fs:SetPoint("CENTER")
        m.btn, m.fs = btn, fs
        btn:RegisterForDrag("LeftButton")
        btn:SetScript("OnDragStart", BarDragStart)
        btn:SetScript("OnDragStop", BarDragStop)
        btn:SetScript("OnEnter", function()
            if m.tooltip then
                GameTooltip:SetOwner(btn, ns.db.bar.position == "below" and "ANCHOR_BOTTOM" or "ANCHOR_TOP")
                m.tooltip(GameTooltip)
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btn:SetScript("OnClick", function() if m.click then m.click() end end)
    end
end

local function Layout()
    local db = ns.db.bar
    local gap, total, shown = 16, 0, 0
    for i = 1, #modules do
        local m = modules[i]
        if m.btn:IsShown() then
            local w = m.fs:GetStringWidth() + 2
            m.btn:SetWidth(w)
            total = total + w
            shown = shown + 1
        end
    end
    if shown == 0 then return end
    total = total + gap * (shown - 1)
    -- manual length if set, otherwise match the map; never squeeze the text
    local base = (db.width and db.width > 0) and db.width or ns.db.size
    local barW = math.max(base, total + 16)
    bar:SetWidth(barW)
    local x = (barW - total) / 2
    for i = 1, #modules do
        local m = modules[i]
        if m.btn:IsShown() then
            m.btn:ClearAllPoints()
            m.btn:SetPoint("LEFT", bar, "LEFT", x, 0)
            x = x + m.btn:GetWidth() + gap
        end
    end
    bar:SetHeight(db.fontSize + 10)
end

local function UpdateAll()
    if not bar or not bar:IsShown() then return end
    for i = 1, #modules do
        local m = modules[i]
        local on = ns.db.bar.modules[m.key]
        if on and m.visible and not m.visible() then on = false end
        m.btn:SetShown(on and true or false)
        if on and m.update then m.update(m.fs) end
    end
    Layout()
end
ns.UpdateInfoBar = UpdateAll

-------------------------------------------------------------------- modules
-- Time -----------------------------------------------------------------
local mTime = NewModule("time", 1)
local function timeString(server)
    local h, m
    if server then
        h, m = GetGameTime()
    else
        local t = date("*t")
        h, m = t.hour, t.min
    end
    if ns.db.bar.hour24 then
        return ("%02d:%02d"):format(h, m)
    end
    local suffix = h >= 12 and "pm" or "am"
    local h12 = h % 12
    if h12 == 0 then h12 = 12 end
    return ("%d:%02d %s"):format(h12, m, suffix)
end
mTime.update = function(fs)
    fs:SetText("|cffb8c4e0" .. timeString(ns.db.bar.serverTime) .. "|r")
end
mTime.tooltip = function(tt)
    tt:SetText("Time")
    tt:AddDoubleLine("Local", timeString(false), 0.8, 0.8, 0.8, 1, 1, 1)
    tt:AddDoubleLine("Server", timeString(true), 0.8, 0.8, 0.8, 1, 1, 1)
    tt:AddLine(" ")
    tt:AddLine("Click to switch between local and server time.", 0.6, 0.75, 1, true)
end
mTime.click = function()
    ns.db.bar.serverTime = not ns.db.bar.serverTime
    UpdateAll()
end

-- Gold ------------------------------------------------------------------
local mGold = NewModule("gold", 2)
mGold.update = function(fs)
    fs:SetText(ns.FormatMoney(GetMoney(), ns.db.bar.fontSize))
end
mGold.tooltip = function(tt)
    tt:SetText("Gold")
    tt:AddDoubleLine("Current", ns.FormatMoney(GetMoney(), 12, true), 0.8, 0.8, 0.8, 1, 1, 1)
    tt:AddLine(" ")
    tt:AddLine("This session", 1, 0.82, 0)
    tt:AddDoubleLine("Earned", ns.FormatMoney(ns.session.earned, 12, true), 0.8, 0.8, 0.8, 0.4, 1, 0.4)
    tt:AddDoubleLine("Spent", ns.FormatMoney(ns.session.spent, 12, true), 0.8, 0.8, 0.8, 1, 0.4, 0.4)
    local net = ns.session.earned - ns.session.spent
    local r, g, b = 1, 1, 1
    if net > 0 then r, g, b = 0.4, 1, 0.4 elseif net < 0 then r, g, b = 1, 0.4, 0.4 end
    tt:AddDoubleLine("Net", ns.FormatMoney(net, 12, true), 0.8, 0.8, 0.8, r, g, b)
end

-- Guild -----------------------------------------------------------------
local mGuild = NewModule("guild", 3)
local guildOnline = 0
local function RequestRoster()
    if not IsInGuild() then return end
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end
end
local function CountOnline()
    if not IsInGuild() then guildOnline = 0 return end
    local _, online = GetNumGuildMembers()
    if type(online) == "number" then
        guildOnline = online
    else
        local total = GetNumGuildMembers() or 0
        local n = 0
        for i = 1, total do
            local online9 = select(9, GetGuildRosterInfo(i))
            if online9 then n = n + 1 end
        end
        guildOnline = n
    end
end
mGuild.visible = function() return IsInGuild() end
mGuild.update = function(fs)
    fs:SetText(("|cff35e035Guild:|r %d"):format(guildOnline))
end
mGuild.tooltip = function(tt)
    RequestRoster()
    local gname = GetGuildInfo("player")
    tt:SetText(gname or "Guild")
    tt:AddLine(("%d online"):format(guildOnline), 0.35, 0.9, 0.35)
    tt:AddLine(" ")
    local total = GetNumGuildMembers() or 0
    local listed = 0
    for i = 1, total do
        local name, _, _, level, _, zone, _, _, online, status, classFileName = GetGuildRosterInfo(i)
        if online then
            listed = listed + 1
            if listed <= 30 then
                local tag = ""
                if status == 1 then tag = " |cffffd200<AFK>|r"
                elseif status == 2 then tag = " |cffe03535<DND>|r"
                elseif type(status) == "string" and status ~= "" then
                    tag = " |cffffd200" .. status .. "|r"
                end
                tt:AddDoubleLine(
                    ("%s%s|r%s"):format(classColorStr(classFileName), ShortName(name), tag),
                    ("%s |cff808080%s|r"):format(level or "", zone or ""),
                    1, 1, 1, 0.8, 0.8, 0.8)
            end
        end
    end
    if listed > 30 then
        tt:AddLine(("…and %d more"):format(listed - 30), 0.6, 0.6, 0.6)
    end
    tt:AddLine(" ")
    tt:AddLine("Click to open your guild panel.", 0.6, 0.75, 1)
end
mGuild.click = function()
    if not pcall(ToggleFriendsFrame, 3) then
        pcall(ToggleGuildFrame)
    end
end

-- FPS / latency ---------------------------------------------------------
local mFps = NewModule("fps", 4)
mFps.update = function(fs)
    local fps = math.floor(GetFramerate() + 0.5)
    local _, _, home = GetNetStats()
    fs:SetText(("|cffb8c4e0%d|r fps |cffb8c4e0%d|r ms"):format(fps, home or 0))
end
mFps.tooltip = function(tt)
    local down, up, home, world = GetNetStats()
    tt:SetText("Performance")
    tt:AddDoubleLine("Framerate", ("%d fps"):format(math.floor(GetFramerate() + 0.5)), 0.8, 0.8, 0.8, 1, 1, 1)
    tt:AddDoubleLine("Home latency", ("%d ms"):format(home or 0), 0.8, 0.8, 0.8, 1, 1, 1)
    tt:AddDoubleLine("World latency", ("%d ms"):format(world or 0), 0.8, 0.8, 0.8, 1, 1, 1)
    tt:AddDoubleLine("Bandwidth", ("%.1f down / %.1f up KB/s"):format(down or 0, up or 0), 0.8, 0.8, 0.8, 1, 1, 1)
end

-- Durability ------------------------------------------------------------
local mDur = NewModule("durability", 5)
local durSlots = {
    { 1, "Head" }, { 3, "Shoulder" }, { 5, "Chest" }, { 6, "Waist" },
    { 7, "Legs" }, { 8, "Feet" }, { 9, "Wrist" }, { 10, "Hands" },
    { 16, "Main Hand" }, { 17, "Off Hand" }, { 18, "Ranged" },
}
local function DurColor(p)
    if p >= 0.5 then return 0.35, 0.9, 0.35
    elseif p >= 0.2 then return 1, 0.85, 0.3
    else return 1, 0.35, 0.35 end
end
local function MinDurability()
    local worst = 1
    for i = 1, #durSlots do
        local cur, maxd = GetInventoryItemDurability(durSlots[i][1])
        if cur and maxd and maxd > 0 then
            local p = cur / maxd
            if p < worst then worst = p end
        end
    end
    return worst
end
mDur.update = function(fs)
    local p = MinDurability()
    local r, g, b = DurColor(p)
    fs:SetText(("Armor |cff%02x%02x%02x%d%%|r"):format(r * 255, g * 255, b * 255, math.floor(p * 100 + 0.5)))
end
mDur.tooltip = function(tt)
    tt:SetText("Durability")
    for i = 1, #durSlots do
        local cur, maxd = GetInventoryItemDurability(durSlots[i][1])
        if cur and maxd and maxd > 0 then
            local p = cur / maxd
            local r, g, b = DurColor(p)
            tt:AddDoubleLine(durSlots[i][2], ("%d%%"):format(math.floor(p * 100 + 0.5)), 0.8, 0.8, 0.8, r, g, b)
        end
    end
end

-- Mail (only appears while you have unread mail) ------------------------
local mMail = NewModule("mail", 6)
mMail.visible = function() return HasNewMail and HasNewMail() and true or false end
mMail.update = function(fs)
    local sz = ns.db.bar.fontSize + 2
    fs:SetText(("|TInterface\\Icons\\INV_Letter_15:%d:%d:0:0:64:64:5:59:5:59|t |cffffd200Mail|r"):format(sz, sz))
end
mMail.tooltip = function(tt)
    tt:SetText("You have mail")
    if GetLatestThreeSenders then
        local s1, s2, s3 = GetLatestThreeSenders()
        for _, s in ipairs({ s1, s2, s3 }) do
            tt:AddLine(s, 0.8, 0.8, 0.8)
        end
    end
end

------------------------------------------------------------------- dragging
local barMoving
function BarDragStart()
    local db = ns.db.bar
    if db.position == "detached" then
        -- shift-drag always moves the bar; plain drag when the map is unlocked
        if IsShiftKeyDown() or not ns.db.locked then
            bar:StartMoving()
            barMoving = true
        end
    else
        -- attached: dragging the bar moves the whole map
        ns.StartMapDrag()
    end
end

function BarDragStop()
    if barMoving then
        bar:StopMovingOrSizing()
        barMoving = nil
        local point, _, relPoint, x, y = bar:GetPoint(1)
        ns.db.bar.point = { point, x, y, relPoint }
    elseif ns.db.bar.position ~= "detached" then
        ns.StopMapDrag()
    end
end

---------------------------------------------------------------------- apply
function ns.ApplyBarSettings()
    if not bar then return end
    local db = ns.db.bar
    if not db.enabled then bar:Hide() return end
    bar:Show()
    bar:SetScale(db.scale or 1)
    bar:ClearAllPoints()
    if db.position == "detached" then
        bar:SetParent(UIParent)
        bar:SetFrameStrata("LOW")
        local p = db.point
        bar:SetPoint(p[1], UIParent, p[4] or p[1], p[2], p[3])
        bar.bg:SetTexCoord(0, 1, 0, 1)
    elseif db.position == "above" then
        bar:SetParent(ns.holder)
        bar:SetFrameLevel(Minimap:GetFrameLevel() + 4)
        bar:SetPoint("BOTTOM", ns.holder, "TOP", 0, 4)
        bar.bg:SetTexCoord(0, 1, 1, 0)
    else
        bar:SetParent(ns.holder)
        bar:SetFrameLevel(Minimap:GetFrameLevel() + 4)
        bar:SetPoint("TOP", ns.holder, "BOTTOM", 0, -4)
        bar.bg:SetTexCoord(0, 1, 0, 1)
    end
    for i = 1, #modules do
        ns.SetFont(modules[i].fs, db.fontSize, "")
    end
    UpdateAll()
end

----------------------------------------------------------------------- init
ns.RegisterInit(function()
    bar = CreateFrame("Frame", "MoonglassInfoBar", ns.holder)
    bar:SetFrameLevel(Minimap:GetFrameLevel() + 4)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", BarDragStart)
    bar:SetScript("OnDragStop", BarDragStop)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetTexture(ns.TEX .. "bar_bg")

    BuildModuleFrames()

    ns.RegisterEvent("PLAYER_MONEY", UpdateAll)
    ns.RegisterEvent("GUILD_ROSTER_UPDATE", function() CountOnline(); UpdateAll() end)
    ns.RegisterEvent("PLAYER_GUILD_UPDATE", function() RequestRoster() end)
    ns.RegisterEvent("UPDATE_INVENTORY_DURABILITY", UpdateAll)
    ns.RegisterEvent("UPDATE_PENDING_MAIL", UpdateAll)
    ns.RegisterEvent("MAIL_INBOX_UPDATE", UpdateAll)
    ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        RequestRoster()
        CountOnline()
        ns.ApplyBarSettings()
    end)

    ns.RegisterTick(UpdateAll)

    -- roster data goes stale unless requested periodically
    C_Timer.NewTicker(20, RequestRoster)

    ns.ApplyBarSettings()
end)
