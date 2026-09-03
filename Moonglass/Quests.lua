--[[----------------------------------------------------------------------------
    Moonglass — Blizzard quest tracker
    The default quest watch frame is placed by Blizzard's managed-position
    system, which parks it right under the minimap. This lets you move it
    clear of the map or hide it outright.
------------------------------------------------------------------------------]]
local _, ns = ...

local original = {}      -- [frame] = { parent, points = {...} }
local moving = false     -- guard so our own SetPoint doesn't re-trigger the hook
local hooked = {}

-- the tracker is named differently across client versions
local function TrackerFrames()
    local list = {}
    local candidates = {
        _G.QuestWatchFrame,          -- Classic / TBC
        _G.WatchFrame,               -- Wrath+
        _G.ObjectiveTrackerFrame,    -- modern
        _G.QuestTimerFrame,          -- timed-quest readout
    }
    for i = 1, #candidates do
        local f = candidates[i]
        if f and f.SetPoint then list[#list + 1] = f end
    end
    return list
end

local function Remember(f)
    if original[f] then return end
    local info = { parent = f:GetParent(), points = {} }
    for i = 1, f:GetNumPoints() do
        info.points[i] = { f:GetPoint(i) }
    end
    original[f] = info
end

-- Blizzard re-anchors managed frames whenever the UI relayouts; drop the
-- tracker from that system so our placement sticks
local function Unmanage(f)
    local name = f:GetName()
    if name and UIPARENT_MANAGED_FRAME_POSITIONS then
        UIPARENT_MANAGED_FRAME_POSITIONS[name] = nil
    end
    pcall(f.SetMovable, f, true)
    pcall(f.SetUserPlaced, f, true)
end

local function AnchorFrame()
    -- sit below whatever the bottom-most piece of Moonglass is
    local db = ns.db
    if db.bar.enabled and db.bar.position == "below" and _G.MoonglassInfoBar then
        return _G.MoonglassInfoBar
    end
    return ns.holder
end

local function PlaceBelow(f)
    local anchor = AnchorFrame()
    if not anchor then return end
    moving = true
    f:ClearAllPoints()
    f:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -(ns.db.questTrackerGap or 12))
    moving = false
end

local function HookFrame(f)
    if hooked[f] then return end
    hooked[f] = true
    hooksecurefunc(f, "SetPoint", function(self)
        if moving then return end
        if ns.db and ns.db.questTracker == "move" then
            C_Timer.After(0, function()
                if ns.db.questTracker == "move" then PlaceBelow(self) end
            end)
        end
    end)
end

function ns.ApplyQuestTracker()
    local mode = ns.db.questTracker or "leave"
    local frames = TrackerFrames()
    for i = 1, #frames do
        local f = frames[i]
        Remember(f)

        if mode == "hide" then
            -- parking it on a hidden frame survives Blizzard's own Show()
            -- calls, and is fully reversible
            if f:GetParent() ~= ns.hidden then
                f:SetParent(ns.hidden)
            end
        else
            if original[f] and f:GetParent() == ns.hidden then
                f:SetParent(original[f].parent or UIParent)
            end

            if mode == "move" then
                Unmanage(f)
                HookFrame(f)
                PlaceBelow(f)
            else
                -- back to Blizzard's own placement
                local info = original[f]
                if info and #info.points > 0 then
                    moving = true
                    f:ClearAllPoints()
                    for p = 1, #info.points do
                        local pt = info.points[p]
                        pcall(f.SetPoint, f, pt[1], pt[2], pt[3], pt[4], pt[5])
                    end
                    moving = false
                end
                pcall(f.SetUserPlaced, f, false)
            end
        end
    end
end

ns.RegisterInit(function()
    ns.ApplyQuestTracker()
    -- the tracker is created/relaid-out lazily, so re-apply on the events
    -- that rebuild it
    local function reapply()
        if ns.db.questTracker and ns.db.questTracker ~= "leave" then
            ns.ApplyQuestTracker()
        end
    end
    ns.RegisterEvent("PLAYER_ENTERING_WORLD", reapply)
    ns.RegisterEvent("QUEST_LOG_UPDATE", reapply)
    ns.RegisterEvent("QUEST_WATCH_UPDATE", reapply)
    ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", reapply)
    C_Timer.After(2, reapply)
end)
