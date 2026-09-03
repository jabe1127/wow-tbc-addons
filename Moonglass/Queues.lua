--[[----------------------------------------------------------------------------
    Moonglass — Indicators
    Clear BG / arena queue state, LFG listing, tracking, and mail — as clean
    circular icons docked to the map.
------------------------------------------------------------------------------]]
local _, ns = ...

local containerFrame
local pvpButtons = {}
local trackButton, mailButton, lfgButton, trackMenu
local softHidden = {}

local COLORS = {
    queued  = { 1.0, 0.85, 0.30 },
    confirm = { 0.30, 1.00, 0.40 },
    active  = { 0.40, 0.70, 1.00 },
    idle    = { 0.55, 0.55, 0.62 },
}

local hasLFGList = C_LFGList and C_LFGList.HasActiveEntryInfo

local function GetTrackingTex()
    if C_Minimap and C_Minimap.GetTrackingTexture then return C_Minimap.GetTrackingTexture() end
    if GetTrackingTexture then return GetTrackingTexture() end
end

local function NumTrackingTypes()
    if C_Minimap and C_Minimap.GetNumTrackingTypes then return C_Minimap.GetNumTrackingTypes() end
    if GetNumTrackingTypes then return GetNumTrackingTypes() end
    return 0
end

local function TrackingInfo(i)
    if C_Minimap and C_Minimap.GetTrackingInfo then
        local info = C_Minimap.GetTrackingInfo(i)
        if type(info) == "table" then
            return info.name, info.texture, info.active
        end
    end
    if GetTrackingInfo then return GetTrackingInfo(i) end
end

local function SetTrackingByIndex(i, on)
    if C_Minimap and C_Minimap.SetTracking then C_Minimap.SetTracking(i, on)
    elseif SetTracking then SetTracking(i, on) end
end

local function SoftHide(frame)
    if frame and not softHidden[frame] then
        softHidden[frame] = frame:GetParent()
        frame:SetParent(ns.hidden)
    end
end

local function SoftShow(frame)
    if frame and softHidden[frame] then
        frame:SetParent(softHidden[frame])
        softHidden[frame] = nil
    end
end

----------------------------------------------------------- icon button kit
local function NewIcon(name)
    local btn = CreateFrame("Button", "MoonglassIndicator" .. name, containerFrame)
    btn:SetSize(22, 22)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", 2, -2)
    btn.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    btn.mask = btn:CreateMaskTexture()
    btn.mask:SetAllPoints(btn.icon)
    btn.mask:SetTexture(ns.TEX .. "mask_circle", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    btn.icon:AddMaskTexture(btn.mask)

    btn.ring = btn:CreateTexture(nil, "OVERLAY")
    btn.ring:SetAllPoints()
    btn.ring:SetTexture(ns.TEX .. "ring_thin")

    btn.count = btn:CreateFontString(nil, "OVERLAY")
    ns.SetFont(btn.count, 12, "OUTLINE")
    btn.count:SetPoint("CENTER")

    local ag = btn:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1); a:SetToAlpha(0.35); a:SetDuration(0.5)
    btn.pulse = ag

    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:Hide()
    return btn
end

local function SetRing(btn, state)
    local c = COLORS[state] or COLORS.idle
    btn.ring:SetVertexColor(c[1], c[2], c[3], 1)
    if state == "confirm" then
        if not btn.pulse:IsPlaying() then btn.pulse:Play() end
    else
        btn.pulse:Stop()
        btn:SetAlpha(1)
    end
end

------------------------------------------------------------------- layout
local function Layout()
    local x = 0
    local order = {}
    for i = 1, #pvpButtons do order[#order + 1] = pvpButtons[i] end
    order[#order + 1] = lfgButton
    order[#order + 1] = trackButton
    order[#order + 1] = mailButton
    for i = 1, #order do
        local btn = order[i]
        if btn and btn:IsShown() then
            btn:ClearAllPoints()
            btn:SetPoint("LEFT", containerFrame, "LEFT", x, 0)
            x = x + 25
        end
    end
    containerFrame:SetSize(math.max(x, 1), 22)
end

--------------------------------------------------------------- pvp queues
local function MaxBattlefields()
    local ok, n = pcall(GetMaxBattlefieldID)
    if ok and type(n) == "number" and n > 0 then return n end
    return 3
end

local function QueueTooltip(tt, i)
    local status, mapName, _, _, _, teamSize = GetBattlefieldStatus(i)
    local kind = (teamSize and teamSize > 0) and ("Arena %dv%d"):format(teamSize, teamSize) or "Battleground"
    tt:SetText(mapName or kind)
    if status == "queued" then
        tt:AddLine("In queue — " .. kind, 1, 0.85, 0.3)
        local waited = GetBattlefieldTimeWaited and GetBattlefieldTimeWaited(i)
        local est = GetBattlefieldEstimatedWaitTime and GetBattlefieldEstimatedWaitTime(i)
        if waited and waited > 0 then
            tt:AddDoubleLine("Time in queue", SecondsToTime(math.floor(waited / 1000)), 0.8, 0.8, 0.8, 1, 1, 1)
        end
        if est and est > 0 then
            tt:AddDoubleLine("Estimated wait", SecondsToTime(math.floor(est / 1000)), 0.8, 0.8, 0.8, 1, 1, 1)
        end
        tt:AddLine(" ")
        tt:AddLine("Right-click to leave this queue.", 0.6, 0.75, 1)
    elseif status == "confirm" then
        tt:AddLine("Your match is ready!", 0.3, 1, 0.4)
        local exp = GetBattlefieldPortExpiration and GetBattlefieldPortExpiration(i)
        if exp and exp > 0 then
            tt:AddDoubleLine("Time to join", SecondsToTime(exp), 0.8, 0.8, 0.8, 1, 1, 1)
        end
        tt:AddLine(" ")
        tt:AddLine("Click to enter.  Right-click to leave the queue.", 0.6, 0.75, 1)
    elseif status == "active" then
        tt:AddLine("Match in progress", 0.4, 0.7, 1)
    end
end

local function UpdateQueues()
    if not ns.db.indicators.queues then
        for i = 1, #pvpButtons do pvpButtons[i]:Hide() end
        Layout()
        return
    end
    local max = MaxBattlefields()
    for i = 1, max do
        local btn = pvpButtons[i]
        if not btn then
            btn = NewIcon("PvP" .. i)
            btn.slot = i
            btn:SetScript("OnClick", function(_, mouse)
                local status = GetBattlefieldStatus(btn.slot)
                if mouse == "RightButton" then
                    if status == "queued" or status == "confirm" then
                        AcceptBattlefieldPort(btn.slot)  -- no accept flag = leave queue
                    end
                elseif status == "confirm" then
                    AcceptBattlefieldPort(btn.slot, 1)
                end
            end)
            btn:SetScript("OnEnter", function()
                GameTooltip:SetOwner(btn, "ANCHOR_BOTTOMRIGHT")
                QueueTooltip(GameTooltip, btn.slot)
                GameTooltip:Show()
            end)
            pvpButtons[i] = btn
        end
        local ok, status, _, _, _, _, teamSize = pcall(GetBattlefieldStatus, i)
        if ok and status and status ~= "none" then
            local isArena = teamSize and teamSize > 0
            btn.icon:SetTexture(isArena
                and "Interface\\PVPFrame\\PVP-ArenaPoints-Icon"
                or "Interface\\BattlefieldFrame\\UI-Battlefield-Icon")
            if not btn.wasStatus or btn.wasStatus ~= status then
                if status == "confirm" then
                    pcall(PlaySound, (SOUNDKIT and SOUNDKIT.PVP_THROUGH_QUEUE) or 8459)
                end
                btn.wasStatus = status
            end
            SetRing(btn, status)
            btn:Show()
        else
            btn.wasStatus = nil
            btn:Hide()
        end
    end
    Layout()
end

local function TickQueues()
    -- live countdown on a ready match
    for i = 1, #pvpButtons do
        local btn = pvpButtons[i]
        if btn:IsShown() then
            local status = GetBattlefieldStatus(btn.slot)
            if status == "confirm" and GetBattlefieldPortExpiration then
                local exp = GetBattlefieldPortExpiration(btn.slot)
                btn.count:SetText(exp and exp > 0 and exp or "")
            else
                btn.count:SetText("")
            end
            if GameTooltip:IsOwned(btn) and GameTooltip:IsShown() then
                GameTooltip:ClearLines()
                QueueTooltip(GameTooltip, btn.slot)
                GameTooltip:Show()
            end
        end
    end
end

----------------------------------------------------------------- tracking
local function BuildTrackMenu()
    trackMenu = CreateFrame("Frame", "MoonglassTrackMenu", UIParent, "BackdropTemplate")
    trackMenu:SetFrameStrata("DIALOG")
    trackMenu:SetBackdrop({
        bgFile = ns.TEX .. "bar_bg",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    trackMenu:SetBackdropBorderColor(0, 0, 0, 0.9)
    trackMenu:Hide()
    trackMenu.rows = {}
    trackMenu:SetScript("OnLeave", function()
        C_Timer.After(0.4, function()
            if not (MouseIsOver and MouseIsOver(trackMenu)) then trackMenu:Hide() end
        end)
    end)
end

local function OpenTrackMenu()
    local n = NumTrackingTypes()
    if n == 0 then return end
    for i = 1, n do
        local row = trackMenu.rows[i]
        if not row then
            row = CreateFrame("Button", nil, trackMenu)
            row:SetHeight(20)
            row:SetPoint("LEFT", 6, 0)
            row:SetPoint("RIGHT", -6, 0)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(16, 16)
            row.icon:SetPoint("LEFT")
            row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            row.text = row:CreateFontString(nil, "OVERLAY")
            ns.SetFont(row.text, 12, "")
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.check = row:CreateTexture(nil, "OVERLAY")
            row.check:SetSize(14, 14)
            row.check:SetPoint("RIGHT")
            row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.08)
            trackMenu.rows[i] = row
        end
        row:SetPoint("TOP", trackMenu, "TOP", 0, -6 - (i - 1) * 20)
        local name, tex, active = TrackingInfo(i)
        row.text:SetText(name or ("Tracking " .. i))
        if tex then row.icon:SetTexture(tex) end
        row.check:SetShown(active and true or false)
        row.index = i
        row.active = active
        row:SetScript("OnClick", function()
            SetTrackingByIndex(row.index, not row.active)
            trackMenu:Hide()
        end)
        row:Show()
    end
    for i = n + 1, #trackMenu.rows do trackMenu.rows[i]:Hide() end
    local width = 90
    for i = 1, n do
        width = math.max(width, trackMenu.rows[i].text:GetStringWidth() + 50)
    end
    trackMenu:SetSize(width + 12, n * 20 + 12)
    trackMenu:ClearAllPoints()
    trackMenu:SetPoint("TOP", trackButton, "BOTTOM", 0, -4)
    trackMenu:Show()
end

-- what is actually being tracked right now: prefer the active entry in the
-- tracking list (works for hunter tracking, Find Herbs, etc.); fall back to
-- the minimap's own tracking texture
local function ActiveTracking()
    local firstTex
    for i = 1, NumTrackingTypes() do
        local _, tex, active = TrackingInfo(i)
        if active and tex and not firstTex then firstTex = tex end
    end
    return firstTex or GetTrackingTex()
end

local function UpdateTracking()
    if not ns.db.indicators.tracking then trackButton:Hide() Layout() return end
    local tex = ActiveTracking()
    if tex then
        trackButton.icon:SetTexture(tex)
        trackButton.icon:SetDesaturated(false)
        trackButton.icon:SetAlpha(1)
        SetRing(trackButton, "active")
    else
        trackButton.icon:SetTexture("Interface\\Minimap\\Tracking\\None")
        trackButton.icon:SetDesaturated(true)
        trackButton.icon:SetAlpha(0.6)
        SetRing(trackButton, "idle")
    end
    trackButton:Show()
    Layout()
end

--------------------------------------------------------------------- mail
local function UpdateMail()
    if not ns.db.indicators.mail then mailButton:Hide() Layout() return end
    if HasNewMail and HasNewMail() then
        mailButton:Show()
    else
        mailButton:Hide()
    end
    Layout()
end

---------------------------------------------------------------------- lfg
local function UpdateLFG()
    if not lfgButton then return end
    if ns.db.indicators.queues and hasLFGList and C_LFGList.HasActiveEntryInfo() then
        lfgButton:Show()
    else
        lfgButton:Hide()
    end
    Layout()
end

---------------------------------------------------------------------- apply
function ns.ApplyIndicatorSettings()
    if not containerFrame then return end
    local db = ns.db
    containerFrame:ClearAllPoints()
    local half = db.size / 2 + 2
    if db.shape == "round" then
        containerFrame:SetPoint("LEFT", ns.holder, "CENTER", -half * 0.7071, half * 0.7071)
    else
        containerFrame:SetPoint("TOPLEFT", ns.holder, "TOPLEFT", 4, -4)
    end

    if db.indicators.queues then SoftHide(MiniMapBattlefieldFrame) else SoftShow(MiniMapBattlefieldFrame) end
    if db.indicators.tracking then
        SoftHide(MiniMapTracking)
        if MinimapCluster then SoftHide(MinimapCluster.Tracking) end
    else
        SoftShow(MiniMapTracking)
        if MinimapCluster then SoftShow(MinimapCluster.Tracking) end
    end
    if db.indicators.mail then SoftHide(MiniMapMailFrame) else SoftShow(MiniMapMailFrame) end

    UpdateQueues()
    UpdateTracking()
    UpdateMail()
    UpdateLFG()
end

----------------------------------------------------------------------- init
ns.RegisterInit(function()
    containerFrame = CreateFrame("Frame", "MoonglassIndicators", ns.holder)
    containerFrame:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    containerFrame:SetSize(22, 22)

    trackButton = NewIcon("Tracking")
    trackButton:SetScript("OnClick", function()
        if trackMenu:IsShown() then trackMenu:Hide() else OpenTrackMenu() end
    end)
    trackButton:SetScript("OnEnter", function()
        GameTooltip:SetOwner(trackButton, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText("Tracking")
        local any = false
        for i = 1, NumTrackingTypes() do
            local name, _, active = TrackingInfo(i)
            if active and name then
                GameTooltip:AddLine(name, 0.4, 0.9, 0.4)
                any = true
            end
        end
        if not any then GameTooltip:AddLine("Not tracking anything", 0.7, 0.7, 0.7) end
        if NumTrackingTypes() > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click to choose what to track.", 0.6, 0.75, 1)
        end
        GameTooltip:Show()
    end)
    BuildTrackMenu()

    mailButton = NewIcon("Mail")
    mailButton.icon:SetTexture("Interface\\Icons\\INV_Letter_15")
    SetRing(mailButton, "queued")
    mailButton:SetScript("OnEnter", function()
        GameTooltip:SetOwner(mailButton, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText("You have mail")
        if GetLatestThreeSenders then
            local s1, s2, s3 = GetLatestThreeSenders()
            for _, s in ipairs({ s1, s2, s3 }) do
                GameTooltip:AddLine(s, 0.8, 0.8, 0.8)
            end
        end
        GameTooltip:Show()
    end)

    lfgButton = NewIcon("LFG")
    lfgButton.icon:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
    SetRing(lfgButton, "queued")
    lfgButton:SetScript("OnEnter", function()
        GameTooltip:SetOwner(lfgButton, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText("Group Finder")
        GameTooltip:AddLine("You are listed in the group finder.", 1, 0.85, 0.3)
        GameTooltip:Show()
    end)

    ns.RegisterEvent("UPDATE_BATTLEFIELD_STATUS", UpdateQueues)
    ns.RegisterEvent("PLAYER_ENTERING_WORLD", ns.ApplyIndicatorSettings)
    ns.RegisterEvent("MINIMAP_UPDATE_TRACKING", UpdateTracking)
    ns.RegisterEvent("UPDATE_PENDING_MAIL", UpdateMail)
    ns.RegisterEvent("MAIL_INBOX_UPDATE", UpdateMail)
    if hasLFGList then
        ns.RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE", UpdateLFG)
    end
    ns.RegisterTick(TickQueues)

    ns.ApplyIndicatorSettings()
end)
