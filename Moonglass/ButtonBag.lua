--[[----------------------------------------------------------------------------
    Moonglass — Button Bag
    Collects addon minimap buttons into one button with a flyout drawer.

    Instead of reparenting each addon's own art (which inherits every
    oddity — square icons, oversized rings, weird sizes), each collected
    button is made invisible and represented by a uniform circular PROXY
    that shows the button's icon and forwards clicks and tooltips to it.
------------------------------------------------------------------------------]]
local _, ns = ...

local bagButton, drawer
local collected = {}   -- [button] = restore info
local proxies = {}     -- [button] = proxy frame
local proxyPool = {}
local COLS, CELL, PAD = 5, 34, 8
local ICON = 28

local blacklist = {
    MinimapZoomIn = true, MinimapZoomOut = true,
    MiniMapWorldMapButton = true, GameTimeFrame = true,
    TimeManagerClockButton = true, MiniMapTracking = true,
    MiniMapTrackingButton = true, MiniMapMailFrame = true,
    MiniMapBattlefieldFrame = true, MinimapZoneTextButton = true,
    MiniMapVoiceChatFrame = true, MinimapToggleButton = true,
    MiniMapRecordingButton = true, QueueStatusButton = true,
    MiniMapLFGFrame = true, MiniMapMeetingStoneFrame = true,
    GarrisonLandingPageMinimapButton = true,
    ExpansionLandingPageMinimapButton = true,
    MinimapBackdrop = true, MinimapCompassTexture = true,
}

-- words that mark a frame as a config-panel widget, not a minimap button
local badWords = {
    "Checkbox", "CheckButton", "Config", "Option", "Panel", "Tab",
    "Tooltip", "Setting", "Show", "Hide", "Toggle", "Enable",
}

local function NameIsMinimapButton(name)
    if not name then return false end
    for i = 1, #badWords do
        if name:find(badWords[i]) then return false end
    end
    return (name:find("MinimapButton$") or name:find("MinimapIcon$")
        or name:find("^LibDBIcon10_")) and true or false
end

local function IsCollectable(btn, fromGlobalScan)
    if collected[btn] then return false end
    if not btn.IsObjectType then return false end
    local isButton = btn:IsObjectType("Button")
    local isFrame = btn:IsObjectType("Frame")
    if not isButton and not isFrame then return false end
    local name = btn:GetName()
    if name then
        if blacklist[name] then return false end
        if name:find("^Moonglass") then return false end
    end
    if not isButton and not NameIsMinimapButton(name) then
        return false
    end
    if fromGlobalScan then
        if not NameIsMinimapButton(name) then return false end
        local p = btn:GetParent()
        if p ~= Minimap and p ~= MinimapBackdrop and p ~= MinimapCluster and p ~= UIParent then
            return false
        end
    end
    local w = btn:GetWidth() or 0
    if w < 12 or w > 50 then return false end
    return true
end

------------------------------------------------------------------ proxies
local function CleanName(name)
    if not name then return "Addon button" end
    name = name:gsub("^LibDBIcon10_", ""):gsub("MinimapButton$", ""):gsub("MinimapIcon$", "")
    return name ~= "" and name or "Addon button"
end

-- pick the texture region that most plausibly is the button's icon:
-- largest shown texture that isn't a border/highlight decoration
-- true when a texture path/fileID looks like decoration rather than the icon
local function IsDecoration(tex)
    if not tex then return true end
    if type(tex) == "number" then
        return tex == 136430          -- MiniMap-TrackingBorder
    end
    local s = tostring(tex)
    return (s:find("TrackingBorder") or s:find("[Bb]order")
        or s:find("[Hh]ighlight") or s:find("MinimapButtonFrame")
        or s:find("UI%-Minimap%-Background")) and true or false
end

-- some sources report collapsed/degenerate texcoords (all zeros, or a
-- zero-area span); copying those makes the icon render as nothing
local function UsableCoords(c)
    if #c ~= 8 then return false end
    local minx, maxx = math.min(c[1], c[3], c[5], c[7]), math.max(c[1], c[3], c[5], c[7])
    local miny, maxy = math.min(c[2], c[4], c[6], c[8]), math.max(c[2], c[4], c[6], c[8])
    return (maxx - minx) > 0.05 and (maxy - miny) > 0.05
end

local function considerRegion(r, best, btnW)
    if not (r and r.IsObjectType and r:IsObjectType("Texture")) then return best end
    if not r:IsShown() then return best end
    local ok, tex = pcall(r.GetTexture, r)
    if not ok or not tex or IsDecoration(tex) then return best end
    local w, h = r:GetWidth() or 0, r:GetHeight() or 0
    -- prefer regions that plausibly ARE the icon: not wildly bigger than
    -- the button itself (those are backdrops/rings)
    local score = w * h
    if btnW and btnW > 0 and w > btnW * 1.25 then score = score * 0.01 end
    if not best or score > best.score then return { r = r, score = score } end
    return best
end

-- named fields addons commonly use for their icon texture, checked first
local ICON_FIELDS = { "icon", "Icon", "texture", "Texture", "iconTexture", "image" }

local function FindIconTexture(B)
    local w = B:GetWidth() or 0

    for i = 1, #ICON_FIELDS do
        local f = B[ICON_FIELDS[i]]
        if type(f) == "table" and f.IsObjectType and f.GetTexture then
            local okO, isTex = pcall(f.IsObjectType, f, "Texture")
            if okO and isTex then
                local ok, tex = pcall(f.GetTexture, f)
                if ok and tex and not IsDecoration(tex) then return f end
            end
        end
    end

    local best = nil
    if B.GetNormalTexture then
        local ok, nt = pcall(B.GetNormalTexture, B)
        if ok and nt then best = considerRegion(nt, nil, w) end
    end
    local okR, regions = pcall(function() return { B:GetRegions() } end)
    if okR then
        for i = 1, #regions do best = considerRegion(regions[i], best, w) end
    end
    if not best then
        local okC, kids = pcall(function() return { B:GetChildren() } end)
        if okC then
            for i = 1, #kids do
                local k = kids[i]
                if k and k.GetRegions then
                    local okK, rs = pcall(function() return { k:GetRegions() } end)
                    if okK then
                        for j = 1, #rs do best = considerRegion(rs[j], best, w) end
                    end
                end
            end
        end
    end
    return best and best.r or nil
end

-- Fills the proxy's icon from the button. Returns true when a real icon was
-- found; false means the caller should fall back to showing the button
-- itself, so a cell is never left empty.
local function UpdateProxyIcon(B, P)
    local src = FindIconTexture(B)
    if src then
        local okT, tex = pcall(src.GetTexture, src)
        if okT and tex then
            P.icon:SetTexture(tex)
            local okC, c = pcall(function() return { src:GetTexCoord() } end)
            if okC and UsableCoords(c) then
                P.icon:SetTexCoord(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8])
            else
                P.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            end
            local okv, r, g, b, a = pcall(src.GetVertexColor, src)
            if okv and type(r) == "number" then
                -- honour the addon's dimming but never render near-black,
                -- and never inherit a fully transparent vertex alpha
                P.icon:SetVertexColor(math.max(r, 0.35), math.max(g or 0, 0.35), math.max(b or 0, 0.35), 1)
                if a and a < 0.1 then P.icon:SetVertexColor(1, 1, 1, 1) end
            else
                P.icon:SetVertexColor(1, 1, 1, 1)
            end
            P.icon:SetAlpha(1)
            P.icon:Show()
            P.letter:SetText("")
            return true
        end
    end
    P.icon:Hide()
    P.letter:SetText("")
    return false
end

local proxyCount = 0
local function AcquireProxy()
    local P = table.remove(proxyPool)
    if P then return P end
    proxyCount = proxyCount + 1
    P = CreateFrame("Button", "MoonglassBagProxy" .. proxyCount, drawer)
    P:SetSize(ICON, ICON)
    P:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    P.mask = P:CreateMaskTexture()
    P.mask:SetAllPoints()
    P.mask:SetTexture(ns.TEX .. "mask_circle", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

    P.bg = P:CreateTexture(nil, "BACKGROUND")
    P.bg:SetAllPoints()
    P.bg:SetColorTexture(0.10, 0.10, 0.13, 0.95)
    P.bg:AddMaskTexture(P.mask)

    P.icon = P:CreateTexture(nil, "ARTWORK")
    P.icon:SetPoint("TOPLEFT", 1, -1)
    P.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    P.icon:AddMaskTexture(P.mask)

    P.ring = P:CreateTexture(nil, "OVERLAY")
    P.ring:SetAllPoints()
    P.ring:SetTexture(ns.TEX .. "ring_thin")
    P.ring:SetVertexColor(0.5, 0.5, 0.58, 0.8)

    local hl = P:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture(ns.TEX .. "mask_circle")
    hl:SetVertexColor(1, 1, 1, 1)
    hl:SetAlpha(0.15)

    P.letter = P:CreateFontString(nil, "OVERLAY")
    ns.SetFont(P.letter, 14, "OUTLINE")
    P.letter:SetPoint("CENTER")

    P:SetScript("OnClick", function(self, mb)
        local B = self.target
        if not B then return end
        local h = B:GetScript("OnClick")
        if h then pcall(h, B, mb, false) end
    end)
    P:SetScript("OnMouseDown", function(self, mb)
        local B = self.target
        local h = B and B:GetScript("OnMouseDown")
        if h then pcall(h, B, mb) end
    end)
    P:SetScript("OnMouseUp", function(self, mb)
        local B = self.target
        local h = B and B:GetScript("OnMouseUp")
        if h then pcall(h, B, mb) end
    end)
    P:SetScript("OnEnter", function(self)
        local B = self.target
        local h = B and B:GetScript("OnEnter")
        if h and pcall(h, B, true) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.label or "Addon button")
        GameTooltip:Show()
    end)
    P:SetScript("OnLeave", function(self)
        local B = self.target
        local h = B and B:GetScript("OnLeave")
        pcall(function() if h then h(B, true) end end)
        GameTooltip:Hide()
    end)
    return P
end

------------------------------------------------------------------ pinning
-- the real (invisible) button sits exactly under its proxy so that
-- tooltips the addon anchors to it appear in the right place
local repinning = false
local function Pin(B)
    local P = proxies[B]
    if not P then return end
    repinning = true
    B:ClearAllPoints()
    B:SetPoint("CENTER", P, "CENTER")
    repinning = false
end

------------------------------------------------------------------- layout
-- Two display modes per button:
--   proxy  — we extracted its icon: button hidden, uniform disc shows the icon
--   direct — no icon found: the real button is shown, scaled into the cell,
--            sitting on our disc, so a cell is never blank
local function ApplyMode(B, P)
    if P.hasIcon then
        P:EnableMouse(true)
        B:SetAlpha(0)
        if B.EnableMouse then B:EnableMouse(false) end
        B:SetScale(collected[B] and collected[B].scale or 1)
    else
        P:EnableMouse(false)
        B:SetAlpha(1)
        if B.EnableMouse then B:EnableMouse(true) end
        local w = B:GetWidth() or 32
        if w > 0 then B:SetScale(ICON / w) end
    end
end

local function Layout()
    local i = 0
    for B in pairs(collected) do
        local P = proxies[B]
        if P then
            if B:IsShown() then
                local col = i % COLS
                local row = math.floor(i / COLS)
                P:ClearAllPoints()
                P:SetPoint("CENTER", drawer, "TOPLEFT",
                    PAD + CELL / 2 + col * CELL,
                    -(PAD + CELL / 2 + row * CELL))
                P:Show()
                ApplyMode(B, P)        -- re-assert: some addons reset these
                Pin(B)
                i = i + 1
            else
                P:Hide()
            end
        end
    end
    local rows = math.max(1, math.ceil(i / COLS))
    local cols = math.min(math.max(i, 1), COLS)
    drawer:SetSize(PAD * 2 + cols * CELL, PAD * 2 + rows * CELL)
    return i
end

local function RefreshIcons()
    for B, P in pairs(proxies) do
        if P:IsShown() then
            P.hasIcon = UpdateProxyIcon(B, P)
            ApplyMode(B, P)
        end
    end
end

------------------------------------------------------------ collect/free
local function Collect(B)
    local info = {
        parent = B:GetParent(),
        scale = B:GetScale(),
        strata = B:GetFrameStrata(),
        alpha = B:GetAlpha(),
        mouse = (not B.IsMouseEnabled) or B:IsMouseEnabled(),
        points = {},
    }
    for i = 1, B:GetNumPoints() do
        info.points[i] = { B:GetPoint(i) }
    end
    collected[B] = info

    local P = AcquireProxy()
    P.target = B
    P.label = CleanName(B:GetName())
    proxies[B] = P

    B:SetParent(drawer)
    B:SetFrameStrata("DIALOG")
    P.hasIcon = UpdateProxyIcon(B, P)
    ApplyMode(B, P)

    if not B.__mgHooked then
        B.__mgHooked = true
        hooksecurefunc(B, "SetPoint", function(b)
            if repinning or not collected[b] then return end
            C_Timer.After(0, function()
                if collected[b] then Pin(b) end
            end)
        end)
    end
end

local function Restore()
    for B, info in pairs(collected) do
        local P = proxies[B]
        if P then
            P.target = nil
            P:Hide()
            proxyPool[#proxyPool + 1] = P
        end
        proxies[B] = nil
        B:SetParent(info.parent or Minimap)
        B:SetScale(info.scale or 1)
        B:SetFrameStrata(info.strata or "MEDIUM")
        B:SetAlpha(info.alpha or 1)
        B:EnableMouse(info.mouse ~= false)
        B:ClearAllPoints()
        if #info.points > 0 then
            for i = 1, #info.points do
                local p = info.points[i]
                pcall(B.SetPoint, B, p[1], p[2], p[3], p[4], p[5])
            end
        else
            B:SetPoint("CENTER", Minimap, "CENTER", 0, -80)
        end
    end
    wipe(collected)
end

--------------------------------------------------------------------- scan
local function ScanGlobals()
    for k, v in pairs(_G) do
        if type(k) == "string" and type(v) == "table"
            and NameIsMinimapButton(k)
            and not blacklist[k] then
            local ok, yes = pcall(IsCollectable, v, true)
            if ok and yes then pcall(Collect, v) end
        end
    end
end

local function Scan()
    if not ns.db.bag.enabled then return end
    local frames = { Minimap, MinimapBackdrop, MinimapCluster }
    for f = 1, #frames do
        local parent = frames[f]
        if parent then
            local kids = { parent:GetChildren() }
            for i = 1, #kids do
                if IsCollectable(kids[i]) then Collect(kids[i]) end
            end
        end
    end
    ScanGlobals()
    if drawer:IsShown() then Layout() end
end

---------------------------------------------------------------- open/close
local function OpenDrawer()
    Scan()
    local n = Layout()
    if n == 0 then return end
    RefreshIcons()
    drawer:ClearAllPoints()
    local _, cy = ns.holder:GetCenter()
    local mid = (UIParent:GetHeight() or 768) / 2
    if cy and cy < mid then
        drawer:SetPoint("BOTTOM", bagButton, "TOP", 0, 6)
    else
        drawer:SetPoint("TOP", bagButton, "BOTTOM", 0, -6)
    end
    drawer:Show()
end

local closeTimer
local function CancelClose()
    if closeTimer then closeTimer:Cancel(); closeTimer = nil end
end

local function DelayedClose()
    CancelClose()
    closeTimer = C_Timer.NewTimer(0.5, function()
        closeTimer = nil
        if not (MouseIsOver and (MouseIsOver(drawer) or MouseIsOver(bagButton))) then
            drawer:Hide()
        else
            DelayedClose()
        end
    end)
end

---------------------------------------------------------------------- build
local function BuildFrames()
    bagButton = CreateFrame("Button", "MoonglassBagButton", ns.holder)
    bagButton:SetSize(26, 26)
    bagButton:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    local tex = bagButton:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture(ns.TEX .. "btn_bag")
    bagButton:SetHighlightTexture(ns.TEX .. "btn_bag", "ADD")
    bagButton:GetHighlightTexture():SetAlpha(0.3)

    drawer = CreateFrame("Frame", "MoonglassDrawer", UIParent, "BackdropTemplate")
    drawer:SetFrameStrata("DIALOG")
    drawer:SetBackdrop({
        bgFile = ns.TEX .. "bar_bg",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    drawer:SetBackdropBorderColor(0, 0, 0, 0.9)
    drawer:SetClampedToScreen(true)
    drawer:Hide()

    -- while open: rescan, refresh icons, re-lay out — buttons that appear,
    -- vanish, change icon, or get re-anchored all settle within a tick
    local openTicker
    drawer:SetScript("OnShow", function()
        if openTicker then openTicker:Cancel() end
        openTicker = C_Timer.NewTicker(0.75, function()
            if drawer:IsShown() then
                Scan()
                Layout()
                RefreshIcons()
            elseif openTicker then
                openTicker:Cancel()
                openTicker = nil
            end
        end)
    end)
    drawer:SetScript("OnHide", function()
        if openTicker then openTicker:Cancel(); openTicker = nil end
    end)

    bagButton:SetScript("OnClick", function()
        if drawer:IsShown() then drawer:Hide() else OpenDrawer() end
    end)
    bagButton:SetScript("OnEnter", function()
        CancelClose()
        if ns.db.bag.hover and not drawer:IsShown() then OpenDrawer() end
        GameTooltip:SetOwner(bagButton, "ANCHOR_LEFT")
        GameTooltip:SetText("Addon buttons")
        GameTooltip:AddLine(ns.db.bag.hover and "Buttons open on hover."
            or "Click to show your collected minimap buttons.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    bagButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if ns.db.bag.hover then DelayedClose() end
    end)
    drawer:SetScript("OnEnter", CancelClose)
    drawer:SetScript("OnLeave", function()
        if ns.db.bag.hover then DelayedClose() end
    end)
    drawer:EnableMouse(true)
end

---------------------------------------------------------------------- apply
function ns.ApplyBagSettings()
    local db = ns.db
    if not bagButton then return end
    if db.bag.enabled then
        bagButton:Show()
        bagButton:ClearAllPoints()
        local half = db.size / 2 + 2
        if db.shape == "round" then
            bagButton:SetPoint("CENTER", ns.holder, "CENTER", -half * 0.7071, -half * 0.7071)
        else
            bagButton:SetPoint("CENTER", ns.holder, "BOTTOMLEFT", 2, 2)
        end
        C_Timer.After(0.1, Scan)
    else
        bagButton:Hide()
        drawer:Hide()
        Restore()
    end
end

-- exposed for tests/debugging
function ns.GetBagProxy(btn) return proxies[btn] end

-- /moonglass buttons — report what was collected and how it renders
function ns.DumpBag()
    Scan()
    local n = 0
    print("|cff9db7ffMoonglass:|r collected addon buttons —")
    for B, P in pairs(proxies) do
        n = n + 1
        local src = FindIconTexture(B)
        local tex = src and select(2, pcall(src.GetTexture, src)) or nil
        print(("  %s  |cff888888%s|r  %s"):format(
            P.label or "?",
            B:IsShown() and "shown" or "hidden",
            P.hasIcon and ("icon: " .. tostring(tex)) or "|cffffd200no icon found — showing button directly|r"))
    end
    if n == 0 then print("  (none)") end
end

----------------------------------------------------------------------- init
ns.RegisterInit(function()
    BuildFrames()
    ns.ApplyBagSettings()
    C_Timer.After(6, Scan)
    C_Timer.After(15, Scan)
    C_Timer.After(30, Scan)
end)
