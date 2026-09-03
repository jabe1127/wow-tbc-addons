--[[----------------------------------------------------------------------------
    Moonglass — Far Zoom
    Zoom out far beyond the client cap: past the widest minimap zoom, the map
    switches to a live zone-art view centered on the player.
------------------------------------------------------------------------------]]
local _, ns = ...

local overlay, container, mask, bg, arrow, label
local tiles = {}
local overlayTiles = {}   -- explored-area textures drawn over the base art
local level = 0
local zone            -- { mapID, layerW, layerH, tileW, tileH, cols, rows }
local spans = { 0.20, 0.35, 0.60, 1.0 }
local names = { "Wide view", "Very wide view", "Huge view", "Whole zone" }
local MAXLEVEL = #spans
local labelTimer

local hasMapAPI = C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapArtLayers
    and C_Map.GetMapArtLayerTextures and C_Map.GetPlayerMapPosition

function ns.FarZoomActive() return level > 0 end

---------------------------------------------------------------------- build
local function BuildFrames()
    overlay = CreateFrame("Frame", "MoonglassFarZoom", Minimap)
    overlay:SetAllPoints(Minimap)
    overlay:SetFrameLevel(Minimap:GetFrameLevel() + 3)
    overlay:SetClipsChildren(true)
    overlay:Hide()

    bg = overlay:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.02, 0.02, 0.03, 1)

    mask = overlay:CreateMaskTexture()
    mask:SetAllPoints(overlay)
    bg:AddMaskTexture(mask)

    container = CreateFrame("Frame", nil, overlay)
    container:SetPoint("TOPLEFT")  -- repositioned every update
    container:SetSize(64, 64)

    local af = CreateFrame("Frame", nil, overlay)
    af:SetFrameLevel(overlay:GetFrameLevel() + 1)
    af:SetPoint("CENTER")
    af:SetSize(20, 20)
    arrow = af:CreateTexture(nil, "OVERLAY")
    arrow:SetAllPoints()
    arrow:SetTexture("Interface\\Minimap\\MinimapArrow")

    label = overlay:CreateFontString(nil, "OVERLAY")
    ns.SetFont(label, 11, "OUTLINE")
    label:SetPoint("BOTTOM", overlay, "BOTTOM", 0, 10)
    label:SetTextColor(0.75, 0.85, 1)
end

function ns.FarZoomRefresh()
    if not overlay then return end
    if mask then
        mask:SetTexture(ns.db.shape == "square"
            and "Interface\\ChatFrame\\ChatFrameBackground"
            or ns.TEX .. "mask_circle",
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
end

---------------------------------------------------------------------- zone
local function LoadZone()
    zone = nil
    if not hasMapAPI then return false end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return false end
    local layers = C_Map.GetMapArtLayers(mapID)
    local layer = layers and layers[1]
    if not layer then return false end
    local files = C_Map.GetMapArtLayerTextures(mapID, 1)
    if not files or #files == 0 then return false end

    local cols = math.ceil(layer.layerWidth / layer.tileWidth)
    local rows = math.ceil(layer.layerHeight / layer.tileHeight)
    zone = {
        mapID = mapID,
        layerW = layer.layerWidth, layerH = layer.layerHeight,
        tileW = layer.tileWidth, tileH = layer.tileHeight,
        cols = cols, rows = rows,
    }

    local n = 0
    for row = 0, rows - 1 do
        for col = 0, cols - 1 do
            n = n + 1
            local file = files[n]
            local t = tiles[n]
            if not t then
                t = container:CreateTexture(nil, "ARTWORK")
                t:AddMaskTexture(mask)
                tiles[n] = t
            end
            if file then
                t:SetTexture(file)
                t.col, t.row = col, row
                t:Show()
            else
                t:Hide()
            end
        end
    end
    for i = n + 1, #tiles do tiles[i]:Hide() end

    -- the base art shows the world as UNdiscovered; the areas you have
    -- explored come from separate overlay textures, so fetch those too
    zone.explored = {}
    if C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures then
        local infos = C_MapExplorationInfo.GetExploredMapTextures(mapID)
        if infos then
            for i = 1, #infos do
                local info = infos[i]
                if info and info.fileDataIDs and #info.fileDataIDs > 0 then
                    zone.explored[#zone.explored + 1] = {
                        w = info.textureWidth, h = info.textureHeight,
                        x = info.offsetX, y = info.offsetY,
                        files = info.fileDataIDs,
                    }
                end
            end
        end
    end
    return true
end

local function LayoutTiles()
    if not zone then return end
    local w = Minimap:GetWidth()
    local span = spans[level] or 1
    local zoneW = w / span
    local scale = zoneW / zone.layerW
    local zoneH = zone.layerH * scale
    container:SetSize(zoneW, zoneH)
    local n = 0
    for row = 0, zone.rows - 1 do
        for col = 0, zone.cols - 1 do
            n = n + 1
            local t = tiles[n]
            if t and t:IsShown() then
                t:SetSize(zone.tileW * scale, zone.tileH * scale)
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", container, "TOPLEFT", col * zone.tileW * scale, -row * zone.tileH * scale)
            end
        end
    end

    -- explored-area overlays: each block is a grid of 256px tiles, with the
    -- last column/row cut to the block's exact size
    local oi = 0
    for e = 1, #zone.explored do
        local ov = zone.explored[e]
        local wide = math.ceil(ov.w / 256)
        local tall = math.ceil(ov.h / 256)
        for row = 0, tall - 1 do
            local th = (row == tall - 1) and (ov.h - 256 * row) or 256
            for col = 0, wide - 1 do
                local tw = (col == wide - 1) and (ov.w - 256 * col) or 256
                oi = oi + 1
                local t = overlayTiles[oi]
                if not t then
                    t = container:CreateTexture(nil, "ARTWORK", nil, 1)
                    t:AddMaskTexture(mask)
                    overlayTiles[oi] = t
                end
                local file = ov.files[row * wide + col + 1]
                if file then
                    t:SetTexture(file)
                    t:SetSize(tw * scale, th * scale)
                    t:ClearAllPoints()
                    t:SetPoint("TOPLEFT", container, "TOPLEFT",
                        (ov.x + col * 256) * scale, -(ov.y + row * 256) * scale)
                    t:Show()
                else
                    t:Hide()
                end
            end
        end
    end
    for i = oi + 1, #overlayTiles do overlayTiles[i]:Hide() end

    return zoneW, zoneH
end

------------------------------------------------------------------- updates
local elapsed = 0
local function OnUpdate(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.05 then return end
    elapsed = 0
    if not zone then return end
    local pos = C_Map.GetPlayerMapPosition(zone.mapID, "player")
    if not pos then
        ns.FarZoomSet(0)
        return
    end
    local px, py = pos:GetXY()
    if not px then ns.FarZoomSet(0) return end
    local zoneW, zoneH = container:GetWidth(), container:GetHeight()
    container:ClearAllPoints()
    container:SetPoint("TOPLEFT", overlay, "CENTER", -px * zoneW, py * zoneH)
    arrow:SetRotation(GetPlayerFacing() or 0)
end

local function ShowLabel()
    label:SetText(names[level] or "")
    label:SetAlpha(1)
    if labelTimer then labelTimer:Cancel() end
    labelTimer = C_Timer.NewTimer(1.6, function()
        labelTimer = nil
        if UIFrameFadeOut then UIFrameFadeOut(label, 0.5, 1, 0) else label:SetAlpha(0) end
    end)
end

------------------------------------------------------------------- control
function ns.FarZoomSet(newLevel)
    if not overlay then return end
    newLevel = math.max(0, math.min(MAXLEVEL, newLevel))
    if newLevel == level then return end
    if newLevel > 0 and level == 0 then
        if not LoadZone() then
            print("|cff9db7ffMoonglass:|r no zone map art available here.")
            return
        end
        ns.FarZoomRefresh()
        overlay:Show()
        overlay:SetScript("OnUpdate", OnUpdate)
    end
    level = newLevel
    if level == 0 then
        overlay:Hide()
        overlay:SetScript("OnUpdate", nil)
    else
        LayoutTiles()
        elapsed = 1  -- force immediate reposition
        OnUpdate(nil, 1)
        ShowLabel()
    end
end

function ns.FarZoomStep(dir)
    if not ns.db.farzoom.enabled then return end
    ns.FarZoomSet(level + dir)
end

----------------------------------------------------------------------- init
ns.RegisterInit(function()
    BuildFrames()
    ns.FarZoomRefresh()

    local function OnZoneChange()
        if level > 0 then
            if LoadZone() then
                LayoutTiles()
            else
                ns.FarZoomSet(0)
            end
        end
    end
    ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", OnZoneChange)
    ns.RegisterEvent("PLAYER_ENTERING_WORLD", OnZoneChange)
    -- newly explored areas appear as soon as you discover them
    ns.RegisterEvent("MAP_EXPLORATION_UPDATED", OnZoneChange)
end)
