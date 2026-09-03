--[[----------------------------------------------------------------------------
    Moonglass — Map
    Shape, border themes, size, position, opacity, zone text, pings, zoom.
------------------------------------------------------------------------------]]
local _, ns = ...

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"

local holder, glowFrame, borderFrame, ringTex, glowTex
local sqInner, sqBand, sqOuter
local vignette, zoneText, pingText

-- LibDBIcon and friends read this global to lay buttons on the map edge
function GetMinimapShape()
    return (ns.db and ns.db.shape == "square") and "SQUARE" or "ROUND"
end

---------------------------------------------------------------- construction
local function BuildFrames()
    holder = CreateFrame("Frame", "MoonglassMapHolder", UIParent)
    holder:SetFrameStrata("LOW")
    holder:SetMovable(true)
    holder:SetClampedToScreen(true)
    ns.holder = holder

    -- take the Minimap for ourselves
    Minimap:SetParent(holder)
    Minimap:ClearAllPoints()
    Minimap:SetPoint("CENTER", holder, "CENTER")
    Minimap:SetFrameStrata("LOW")

    if MinimapCluster then
        MinimapCluster:EnableMouse(false)
    end

    -- glow sits behind/around the map
    glowFrame = CreateFrame("Frame", nil, holder)
    glowFrame:SetPoint("CENTER")
    glowFrame:SetFrameLevel(math.max(0, holder:GetFrameLevel()))
    glowTex = glowFrame:CreateTexture(nil, "BACKGROUND")
    glowTex:SetAllPoints()

    -- ring border above the map
    borderFrame = CreateFrame("Frame", nil, holder)
    borderFrame:SetPoint("TOPLEFT", -2, 2)
    borderFrame:SetPoint("BOTTOMRIGHT", 2, -2)
    borderFrame:SetFrameLevel(Minimap:GetFrameLevel() + 6)
    ringTex = borderFrame:CreateTexture(nil, "OVERLAY")
    ringTex:SetAllPoints()

    -- square border stack (backdrop frames)
    local function edgeFrame(inset, size)
        local f = CreateFrame("Frame", nil, holder, "BackdropTemplate")
        f:SetPoint("TOPLEFT", -inset, inset)
        f:SetPoint("BOTTOMRIGHT", inset, -inset)
        f:SetFrameLevel(Minimap:GetFrameLevel() + 6)
        f:SetBackdrop({ edgeFile = WHITE8X8, edgeSize = size })
        return f
    end
    sqInner = edgeFrame(1, 1)
    sqBand  = edgeFrame(7, 6)
    sqOuter = edgeFrame(8, 1)

    -- inner shadow
    local vf = CreateFrame("Frame", nil, holder)
    vf:SetAllPoints()
    vf:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    vignette = vf:CreateTexture(nil, "OVERLAY")
    vignette:SetAllPoints()

    -- zone text
    local zf = CreateFrame("Frame", nil, holder)
    zf:SetFrameLevel(Minimap:GetFrameLevel() + 7)
    zf:SetPoint("TOP", holder, "TOP", 0, -6)
    zf:SetSize(10, 10)
    zoneText = zf:CreateFontString(nil, "OVERLAY")
    ns.SetFont(zoneText, 12, "")
    zoneText:SetPoint("TOP", holder, "TOP", 0, -7)
    ns.zoneTextFrame = zf

    -- ping readout
    pingText = holder:CreateFontString(nil, "OVERLAY")
    ns.SetFont(pingText, 12, "OUTLINE")
    pingText:SetPoint("BOTTOM", holder, "BOTTOM", 0, 8)
    pingText:SetAlpha(0)
end

------------------------------------------------------------------- clutter
local function HideClutter()
    ns.Kill(MinimapBorder)
    ns.Kill(MinimapBorderTop)
    ns.Kill(MinimapNorthTag)
    ns.Kill(MinimapCompassTexture)
    ns.Kill(MinimapZoneTextButton)
    ns.Kill(MinimapToggleButton)
    if MinimapCluster then
        ns.Kill(MinimapCluster.BorderTop)
        ns.Kill(MinimapCluster.ZoneTextButton)
    end
    if ns.db.hideClutter then
        ns.Kill(MinimapZoomIn or (Minimap and Minimap.ZoomIn))
        ns.Kill(MinimapZoomOut or (Minimap and Minimap.ZoomOut))
        ns.Kill(MiniMapWorldMapButton)
        ns.Kill(GameTimeFrame)
        ns.Kill(TimeManagerClockButton)
    end
end

--------------------------------------------------------------------- border
local function ApplyBorder()
    local db = ns.db
    local shape, theme = db.shape, db.border
    ringTex:Hide(); glowTex:Hide()
    sqInner:Hide(); sqBand:Hide(); sqOuter:Hide()

    local r, g, b, a = ns.BorderColor()

    if theme == "none" then
        -- nothing
    elseif shape == "round" then
        if theme == "thin" then
            ringTex:SetTexture(ns.TEX .. "ring_thin")
            ringTex:SetVertexColor(r, g, b, a)
            ringTex:Show()
        elseif theme == "glass" then
            ringTex:SetTexture(ns.TEX .. "ring_glass")
            ringTex:SetVertexColor(1, 1, 1, 1)
            ringTex:Show()
        elseif theme == "glow" then
            ringTex:SetTexture(ns.TEX .. "ring_thin")
            ringTex:SetVertexColor(r, g, b, a)
            ringTex:Show()
            glowTex:SetTexture(ns.TEX .. "glow_round")
            glowTex:SetVertexColor(r, g, b, 0.7)
            glowTex:Show()
        end
    else -- square
        if theme == "thin" then
            sqInner:SetBackdropBorderColor(r, g, b, a)
            sqInner:Show()
        elseif theme == "glass" then
            sqInner:SetBackdropBorderColor(0, 0, 0, 0.9)
            sqBand:SetBackdropBorderColor(0.05, 0.05, 0.075, 0.82)
            sqOuter:SetBackdropBorderColor(0.8, 0.84, 0.95, 0.32)
            sqInner:Show(); sqBand:Show(); sqOuter:Show()
        elseif theme == "glow" then
            sqInner:SetBackdropBorderColor(r, g, b, a)
            sqInner:Show()
            glowTex:SetTexture(ns.TEX .. "glow_square")
            glowTex:SetVertexColor(r, g, b, 0.7)
            glowTex:Show()
        end
    end

    if db.vignette then
        vignette:SetTexture(ns.TEX .. (shape == "square" and "vignette_square" or "vignette_round"))
        vignette:Show()
    else
        vignette:Hide()
    end
end

------------------------------------------------------------------ zone text
local pvpColors = {
    sanctuary = { 0.41, 0.80, 0.94 },
    friendly  = { 0.35, 0.90, 0.35 },
    contested = { 1.00, 0.85, 0.30 },
    hostile   = { 1.00, 0.35, 0.35 },
    arena     = { 1.00, 0.35, 0.35 },
    combat    = { 1.00, 0.35, 0.35 },
}

local GetZonePVP = GetZonePVPInfo or (C_PvP and C_PvP.GetZonePVPInfo) or function() end

local function UpdateZoneText()
    local zone = GetMinimapZoneText() or ""
    local pvpType = GetZonePVP()
    local c = pvpColors[pvpType] or { 0.95, 0.95, 1.0 }
    zoneText:SetText(zone)
    zoneText:SetTextColor(c[1], c[2], c[3])
    local mode = ns.db.zoneText
    if mode == "never" then
        zoneText:Hide()
    elseif mode == "always" then
        zoneText:Show()
    else
        zoneText:SetShown(MouseIsOver and MouseIsOver(Minimap) or false)
    end
end

---------------------------------------------------------------------- zoom
local zoomTimer
local function ScheduleZoomOut()
    if not ns.db.autoZoomOut then return end
    if zoomTimer then zoomTimer:Cancel() end
    zoomTimer = C_Timer.NewTimer(8, function()
        zoomTimer = nil
        if Minimap:GetZoom() > 0 then Minimap:SetZoom(0) end
    end)
end

local function OnWheel(_, delta)
    local zoom = Minimap:GetZoom()
    local maxZoom = (Minimap.GetZoomLevels and Minimap:GetZoomLevels() or 6) - 1
    if delta > 0 then
        if ns.FarZoomActive and ns.FarZoomActive() then
            ns.FarZoomStep(-1)
        elseif zoom < maxZoom then
            Minimap:SetZoom(zoom + 1)
            ScheduleZoomOut()
        end
    else
        if zoom > 0 then
            Minimap:SetZoom(zoom - 1)
            if Minimap:GetZoom() == 0 and zoomTimer then zoomTimer:Cancel(); zoomTimer = nil end
        elseif ns.db.farzoom.enabled and ns.FarZoomStep then
            ns.FarZoomStep(1)
        end
    end
end

---------------------------------------------------------------------- drag
local function SavePosition()
    local point, _, relPoint, x, y = holder:GetPoint(1)
    ns.db.point = { point, x, y, relPoint }
end

local function ApplyPosition()
    local p = ns.db.point
    holder:ClearAllPoints()
    holder:SetPoint(p[1], UIParent, p[4] or p[1], p[2], p[3])
end

-- shared with the info bar: shift-drag always moves the map,
-- plain drag moves it when unlocked
function ns.StartMapDrag()
    if IsShiftKeyDown() or not ns.db.locked then
        holder:StartMoving()
        return true
    end
end

function ns.StopMapDrag()
    holder:StopMovingOrSizing()
    SavePosition()
    ApplyPosition()
end

---------------------------------------------------------------------- pings
local pingFade
local function ShowPing(unit)
    if not ns.db.showPings then return end
    local name = UnitName(unit)
    if not name then return end
    local _, class = UnitClass(unit)
    local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
    if c then
        pingText:SetTextColor(c.r, c.g, c.b)
    else
        pingText:SetTextColor(1, 1, 1)
    end
    pingText:SetText(name)
    pingText:SetAlpha(1)
    if pingFade then pingFade:Cancel() end
    pingFade = C_Timer.NewTimer(2, function()
        pingFade = nil
        if UIFrameFadeOut then UIFrameFadeOut(pingText, 0.6, 1, 0) else pingText:SetAlpha(0) end
    end)
end

---------------------------------------------------------------------- apply
function ns.ApplyMapSettings()
    local db = ns.db
    local size = db.size

    holder:SetSize(size, size)
    Minimap:SetSize(size, size)
    glowFrame:SetSize(size * 1.5, size * 1.5)
    holder:SetAlpha(db.opacity)

    Minimap:SetMaskTexture(db.shape == "square"
        and "Interface\\ChatFrame\\ChatFrameBackground"
        or ns.TEX .. "mask_circle")

    ApplyPosition()
    ApplyBorder()
    HideClutter()
    UpdateZoneText()

    ns.SetFont(zoneText, math.max(10, math.floor(size / 15)), "")

    if ns.ApplyBarSettings then ns.ApplyBarSettings() end
    if ns.ApplyBagSettings then ns.ApplyBagSettings() end
    if ns.ApplyIndicatorSettings then ns.ApplyIndicatorSettings() end
    if ns.FarZoomRefresh then ns.FarZoomRefresh() end
    if ns.ApplyQuestTracker then ns.ApplyQuestTracker() end
end

----------------------------------------------------------------------- init
ns.RegisterInit(function()
    BuildFrames()

    Minimap:EnableMouseWheel(true)
    Minimap:SetScript("OnMouseWheel", OnWheel)

    Minimap:RegisterForDrag("LeftButton")
    Minimap:SetScript("OnDragStart", ns.StartMapDrag)
    Minimap:SetScript("OnDragStop", ns.StopMapDrag)

    Minimap:HookScript("OnEnter", function()
        if ns.db.zoneText == "hover" then zoneText:Show() end
    end)
    Minimap:HookScript("OnLeave", function()
        if ns.db.zoneText == "hover" then zoneText:Hide() end
    end)

    ns.RegisterEvent("ZONE_CHANGED", UpdateZoneText)
    ns.RegisterEvent("ZONE_CHANGED_INDOORS", UpdateZoneText)
    ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", UpdateZoneText)
    ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        UpdateZoneText()
        ns.ApplyMapSettings()
    end)
    ns.RegisterEvent("MINIMAP_PING", function(_, unit) ShowPing(unit) end)

    -- if anything else zooms the map in, schedule the snap-back
    hooksecurefunc(Minimap, "SetZoom", function(_, level)
        if level and level > 0 then ScheduleZoomOut() end
    end)

    ns.ApplyMapSettings()
end)
