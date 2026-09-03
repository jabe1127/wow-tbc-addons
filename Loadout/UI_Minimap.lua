local ADDON, ns = ...
local Skin, Sets = ns.Skin, ns.Sets

local button

local function UpdatePosition()
    if not button then return end
    local angle = math.rad(ns.db.minimap.angle or 214)
    local radius = 80
    button:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate(self)
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local px, py = GetCursorPosition()
    px, py = px / scale, py / scale
    ns.db.minimap.angle = math.deg(math.atan2(py - my, px - mx))
    UpdatePosition()
end

local function Build()
    if button or not Minimap then return button end

    local b = CreateFrame("Button", "LoadoutMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetMovable(true)

    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", -1, 1)
    icon:SetTexture("Interface\\Icons\\INV_Chest_Chain_15")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon = icon

    local ring = b:CreateTexture(nil, "OVERLAY")
    ring:SetSize(53, 53)
    ring:SetPoint("TOPLEFT")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b.ring = ring

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetSize(31, 31)
    hl:SetPoint("CENTER")
    hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    hl:SetBlendMode("ADD")

    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    b:SetScript("OnClick", function(self, click)
        if click == "RightButton" then
            local entries = {
                { text = "Options",       func = function() ns:Fire("TOGGLE_OPTIONS") end },
                { text = "Gear sets",     func = function() ns:Fire("TOGGLE_CHAR_PANEL") end },
                { text = "Take gear off", func = function()
                    ns.Equip:UnequipAll(false)
                    ns.Rules:Release()
                end },
            }
            local order = Sets:GetOrder()
            if #order > 0 then
                table.insert(entries, 1, { text = "— equip —", func = function() end })
                for i = #order, 1, -1 do
                    local name = order[i]
                    table.insert(entries, 2, { text = name, func = function()
                        Sets:Equip(name)
                        ns.Rules:Release()
                    end })
                end
            end
            ns.Menu:Open(self, entries)
        else
            ns:Fire("TOGGLE_MAIN")
        end
    end)

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Loadout", 1, 1, 1)
        local worn
        for _, name in ipairs(Sets:GetOrder()) do
            if Sets:IsEquipped(name) then worn = name break end
        end
        GameTooltip:AddLine("Worn set: " .. (worn or "none"), 0.7, 0.7, 0.75)
        if ns.cdb.activeRule then
            GameTooltip:AddLine("Rule active: " .. ns.cdb.activeRule, 0.4, 0.85, 1)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click: gear window", 0.4, 0.85, 1)
        GameTooltip:AddLine("Right-click: quick menu", 0.4, 0.85, 1)
        GameTooltip:AddLine("Drag: move around the minimap", 0.5, 0.5, 0.55)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    button = b
    UpdatePosition()
    b:SetShown(not ns.db.minimap.hide)
    return b
end

ns:Listen("PLAYER_READY", Build)

ns.UpdateMinimapButton = function()
    if not button then Build() end
    if button then
        button:SetShown(not ns.db.minimap.hide)
        UpdatePosition()
    end
end
