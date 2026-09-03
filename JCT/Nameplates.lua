--[[--------------------------------------------------------------------------
    JCT - Nameplates.lua
    Tracks which nameplate belongs to which GUID, so combat text can be
    anchored over a unit instead of at a fixed point on screen.

    The awkward part is frame recycling. WoW keeps a small pool of nameplate
    frames and hands the same frame to a different unit as things come and go,
    so a naive GUID -> frame map goes stale silently and numbers start
    appearing over the wrong mob. Both directions are tracked here, and the
    reverse map is used to evict the previous owner whenever a frame is
    handed to someone new.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

local NP = {}
ns.Nameplates = NP

NP.byGUID = {}      -- [guid]  = plate frame
NP.byPlate = {}     -- [plate] = guid
NP.count = 0

local C_NamePlate = _G.C_NamePlate
NP.available = (C_NamePlate and C_NamePlate.GetNamePlateForUnit) and true or false

--------------------------------------------------------------------------
-- Tracking
--------------------------------------------------------------------------

function NP:OnUnitAdded(unit)
    if not NP.available or not unit then return end

    -- Resolve the frame BEFORE the GUID. If we bail out after this point
    -- without clearing byPlate, the reverse map still names the previous
    -- occupant, and that is the one case Get's guard cannot catch: both
    -- maps agree with each other and both are wrong.
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or not plate then return end

    local previous = NP.byPlate[plate]

    local guid = UnitGUID(unit)
    if not guid then
        if previous then NP.byGUID[previous] = nil end
        NP.byPlate[plate] = nil
        return
    end

    -- Only evict the previous occupant if it is still on THIS frame. It may
    -- have already moved to another plate, in which case clearing it here
    -- would silently break a perfectly good mapping.
    if previous and previous ~= guid and NP.byGUID[previous] == plate then
        NP.byGUID[previous] = nil
    end

    NP.byGUID[guid] = plate
    NP.byPlate[plate] = guid
end

function NP:OnUnitRemoved(unit)
    if not NP.available or not unit then return end
    local guid = UnitGUID(unit)
    if guid then
        local plate = NP.byGUID[guid]
        if plate then NP.byPlate[plate] = nil end
        NP.byGUID[guid] = nil
        return
    end
    -- UnitGUID can already be nil by the time this fires. Fall back to
    -- dropping anything whose frame is no longer on screen.
    for g, p in pairs(NP.byGUID) do
        if not p:IsShown() then
            NP.byPlate[p] = nil
            NP.byGUID[g] = nil
        end
    end
end

function NP:Reset()
    wipe(NP.byGUID)
    wipe(NP.byPlate)
end

-- Rebuild from scratch. Used at login and after a zone change, when
-- NAME_PLATE_UNIT_ADDED may have fired before we were listening.
function NP:Rescan()
    if not NP.available then return end
    NP:Reset()
    if not C_NamePlate.GetNamePlates then return end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then return end
    for i = 1, #plates do
        local plate = plates[i]
        local unit = plate and plate.namePlateUnitToken
        if unit then NP:OnUnitAdded(unit) end
    end
end

--------------------------------------------------------------------------
-- Lookup
--------------------------------------------------------------------------

function NP:Get(guid)
    if not guid then return nil end
    local plate = NP.byGUID[guid]
    if not plate then return nil end
    if not plate:IsShown() then return nil end
    -- Guard against a frame that was recycled without us seeing the event.
    if NP.byPlate[plate] ~= guid then return nil end
    return plate
end

-- There is deliberately no Position() here, and there cannot be one.
--
-- Nameplates are anchor restricted regions (patch 8.2, which reached Classic
-- with the 2.5.6 UI rebase). Any attempt to read their geometry from addon
-- code - GetCenter, GetLeft, GetTop, GetRect, GetPoint - throws
-- "Can't measure restricted regions". Blizzard did this specifically to stop
-- addons deriving unit world positions, and there is no sanctioned API that
-- gives it back.
--
-- What IS allowed is anchoring TO a nameplate. So combat text is positioned
-- with SetPoint offsets against the plate and never measured. IsShown is
-- also permitted, which is what makes Get() below safe.

-- The state of an anchor we handed out earlier:
--
--   "owned"    still this unit's plate, everything normal
--   "orphaned" the unit is gone - died, walked off - but the plate has not
--              been handed to anyone else. The frame still sits where it
--              was, so anything anchored to it can finish its animation
--              exactly as if nothing happened. This is the common case when
--              you kill something quickly, and it MUST keep working: a
--              number vanishing because its target died is the one moment
--              you most want to see it.
--   "stolen"   the plate now belongs to a different unit, and has moved to
--              that unit. Anything still anchored to it would be dragged
--              across the screen, so those have to be retired.
function NP:AnchorState(plate, guid)
    if not plate or not guid then return "stolen" end
    local owner = NP.byPlate[plate]
    if owner == guid then return "owned" end
    if owner == nil then return "orphaned" end
    return "stolen"
end

function NP:Tracked()
    local n = 0
    for _ in pairs(NP.byGUID) do n = n + 1 end
    return n
end

--------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------

local f = CreateFrame("Frame", "JCT_Nameplates")
NP.frame = f

f:SetScript("OnEvent", function(_, event, arg1)
    if event == "NAME_PLATE_UNIT_ADDED" then
        NP:OnUnitAdded(arg1)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        NP:OnUnitRemoved(arg1)
    elseif event == "PLAYER_ENTERING_WORLD" then
        NP:Rescan()
    end
end)

function NP:Enable()
    if not NP.available then return false end
    pcall(f.RegisterEvent, f, "NAME_PLATE_UNIT_ADDED")
    pcall(f.RegisterEvent, f, "NAME_PLATE_UNIT_REMOVED")
    pcall(f.RegisterEvent, f, "PLAYER_ENTERING_WORLD")
    NP:Rescan()
    return true
end
