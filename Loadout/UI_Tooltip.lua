local ADDON, ns = ...
local Util, Sets = ns.Util, ns.Sets

-- Cache: rebuilt whenever sets change, so tooltips stay cheap.
local memberOf = {}
local dirty = true

local function Rebuild()
    wipe(memberOf)
    for name, set in pairs(ns.cdb.sets) do
        for _, item in pairs(set.items or {}) do
            if item.key then
                memberOf[item.key] = memberOf[item.key] or {}
                table.insert(memberOf[item.key], name)
            end
        end
    end
    for _, list in pairs(memberOf) do table.sort(list) end
    dirty = false
end

ns:Listen("SETS_CHANGED", function() dirty = true end)

local function AddSetLine(tooltip)
    if not ns.db or not ns.db.tooltipSetInfo then return end
    if not ns.cdb then return end
    if dirty then Rebuild() end

    local _, link = tooltip:GetItem()
    if not link then return end
    local key = Util:ItemKey(link)
    local sets = key and memberOf[key]
    if not sets or #sets == 0 then return end

    tooltip:AddLine("In sets: " .. table.concat(sets, ", "), 0.37, 0.84, 1, true)
    tooltip:Show()
end

local hooked = {}
local function Hook(tooltip)
    if not tooltip or hooked[tooltip] then return end
    hooked[tooltip] = true
    if tooltip.HookScript then
        tooltip:HookScript("OnTooltipSetItem", AddSetLine)
    end
end

ns:Listen("PLAYER_READY", function()
    Hook(GameTooltip)
    Hook(ItemRefTooltip)
    Hook(ShoppingTooltip1)
    Hook(ShoppingTooltip2)
end)
