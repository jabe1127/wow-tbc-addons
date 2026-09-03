-- LogLovers Events: COMBAT_LOG_EVENT_UNFILTERED -> normalized records
local ADDON, NS = ...

local lastHighlightSound = -math.huge
local recentFeign = {}   -- [guid] = time of last Feign Death aura
local feignCounter = 0

-- [lowered spell name] = true while a spell has only ever been seen as a
-- buff/debuff this session, false once it also shows up as damage, a cast or
-- anything else. Runtime only, never saved. Used to decide whether the
-- right-click menu can offer "hide this buff" - offering it on a DoT tick
-- would be a lie, since hiding the aura would not remove that line.
NS.auraOnly = {}

local function toNum(v) return tonumber(v) or 0 end

function NS.HandleCLEU(timestamp, sub, hideCaster,
        sg, sn, sf, srf, dg, dn, df, drf, ...)

    local cat = NS.SUBEVENT_CAT[sub]
    if not cat then return end

    local rec = {
        t = timestamp, sub = sub, cat = cat,
        sg = sg, sn = sn, sf = sf, srf = srf,
        dg = dg, dn = dn, df = df, drf = drf,
    }

    -- roles
    if sn then rec.srcRole = NS.RoleOf(sg, sf) end
    if dn then rec.dstRole = NS.RoleOf(dg, df) end

    -- segment stamp for combat-relative timestamps
    local seg = NS.currentSegment
    if seg then
        if not seg.firstT then seg.firstT = timestamp end
        rec.segStart = seg.firstT
        rec.segIndex = seg.index
    end

    -- payload by subevent family -----------------------------------------
    if sub == "SWING_DAMAGE" then
        local amt, over, school, res, blk, abs, crit, gl, cr, oh = ...
        rec.amt, rec.over, rec.dmgSchool = toNum(amt), toNum(over), school or 1
        rec.resisted, rec.blocked, rec.absorbed = toNum(res), toNum(blk), toNum(abs)
        rec.crit, rec.glance, rec.crush, rec.offhand = crit and true, gl and true, cr and true, oh and true

    elseif sub == "SWING_MISSED" then
        local miss, oh, missAmt = ...
        rec.miss, rec.offhand, rec.missAmt = miss, oh and true, toNum(missAmt)

    elseif sub == "ENVIRONMENTAL_DAMAGE" then
        local env, amt, over, school, res, blk, abs, crit = ...
        rec.env = env and (env:sub(1, 1) .. env:sub(2):lower()) or "Environment"
        rec.amt, rec.over, rec.dmgSchool = toNum(amt), toNum(over), school or 1
        rec.resisted, rec.blocked, rec.absorbed = toNum(res), toNum(blk), toNum(abs)
        rec.crit = crit and true

    elseif sub == "ENCHANT_APPLIED" or sub == "ENCHANT_REMOVED" then
        local spellName, itemId, itemName = ...
        rec.sname, rec.itemId, rec.itemName = spellName, itemId, itemName

    elseif sub == "PARTY_KILL" or sub == "UNIT_DIED"
        or sub == "UNIT_DESTROYED" or sub == "UNIT_DISSIPATES" then
        -- no payload


    else
        -- all remaining families start with spellId, spellName, spellSchool
        local sid, sname, sch = ...
        rec.sid, rec.sname, rec.sch = sid, sname, sch
        if sname then rec.snameLower = string.lower(sname) end

        if sub == "SPELL_DAMAGE" or sub == "SPELL_PERIODIC_DAMAGE"
            or sub == "RANGE_DAMAGE" or sub == "DAMAGE_SHIELD"
            or sub == "DAMAGE_SPLIT" then
            local _, _, _, amt, over, school, res, blk, abs, crit, gl, cr, oh = ...
            rec.amt, rec.over, rec.dmgSchool = toNum(amt), toNum(over), school or sch or 1
            rec.resisted, rec.blocked, rec.absorbed = toNum(res), toNum(blk), toNum(abs)
            rec.crit, rec.glance, rec.crush, rec.offhand = crit and true, gl and true, cr and true, oh and true

        elseif sub == "SPELL_MISSED" or sub == "SPELL_PERIODIC_MISSED"
            or sub == "RANGE_MISSED" or sub == "DAMAGE_SHIELD_MISSED" then
            local _, _, _, miss, oh, missAmt = ...
            rec.miss, rec.offhand, rec.missAmt = miss, oh and true, toNum(missAmt)

        elseif sub == "SPELL_HEAL" or sub == "SPELL_PERIODIC_HEAL" then
            local _, _, _, amt, over, abs, crit = ...
            rec.amt, rec.over, rec.absorbed = toNum(amt), toNum(over), toNum(abs)
            rec.crit = crit and true

        elseif sub == "SPELL_ENERGIZE" or sub == "SPELL_PERIODIC_ENERGIZE" then
            -- 2.5.x payload: amount, overEnergize, powerType, alternatePowerType
            local _, _, _, amt, over, power = ...
            rec.amt, rec.over, rec.power = toNum(amt), toNum(over), power

        elseif sub == "SPELL_DRAIN" or sub == "SPELL_PERIODIC_DRAIN"
            or sub == "SPELL_LEECH" or sub == "SPELL_PERIODIC_LEECH" then
            local _, _, _, amt, power, extra = ...
            rec.amt, rec.power, rec.extraAmt = toNum(amt), power, toNum(extra)

        elseif sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REMOVED"
            or sub == "SPELL_AURA_REFRESH" then
            local _, _, _, auraType = ...
            rec.aura = auraType
            if sub == "SPELL_AURA_APPLIED" and rec.snameLower == "feign death" and dg then
                recentFeign[dg] = timestamp
                feignCounter = feignCounter + 1
                if feignCounter % 100 == 0 then
                    for g, t2 in pairs(recentFeign) do
                        if timestamp - t2 > 60 then recentFeign[g] = nil end
                    end
                end
            end

        elseif sub == "SPELL_AURA_APPLIED_DOSE" or sub == "SPELL_AURA_REMOVED_DOSE" then
            local _, _, _, auraType, dose = ...
            rec.aura, rec.dose = auraType, toNum(dose)

        elseif sub == "SPELL_AURA_BROKEN" then
            local _, _, _, auraType = ...
            rec.aura = auraType

        elseif sub == "SPELL_AURA_BROKEN_SPELL" then
            local _, _, _, xid, xname, xsch, auraType = ...
            rec.xid, rec.xname, rec.xsch, rec.aura = xid, xname, xsch, auraType

        elseif sub == "SPELL_CAST_FAILED" then
            local _, _, _, reason = ...
            rec.failReason = reason

        elseif sub == "SPELL_INTERRUPT" then
            local _, _, _, xid, xname, xsch = ...
            rec.xid, rec.xname, rec.xsch = xid, xname, xsch

        elseif sub == "SPELL_DISPEL" or sub == "SPELL_STOLEN"
            or sub == "SPELL_DISPEL_FAILED" then
            local _, _, _, xid, xname, xsch, auraType = ...
            rec.xid, rec.xname, rec.xsch, rec.aura = xid, xname, xsch, auraType

        elseif sub == "SPELL_EXTRA_ATTACKS" then
            local _, _, _, amt = ...
            rec.amt = toNum(amt)
        end
    end

    -- segment boss label: first hostile non-player target we damage
    if seg and not seg.label and cat == "damage" and rec.dstRole == "hostile"
        and dg and dg:find("^Creature") then
        seg.label = dn
    end

    -- feign death detection on UNIT_DIED
    if sub == "UNIT_DIED" and dg and recentFeign[dg]
        and (timestamp - recentFeign[dg]) < 1.5 then
        rec.feign = true
    end

    -- Professions have no API in TBC, so the only way to know someone is a
    -- miner is to watch them smelt. Casts by other real players are the source:
    -- "friendly" also covers NPCs, so the player type bit has to be checked or
    -- every innkeeper who cooks lands in the roster.
    if cat == "casts" and rec.snameLower and sn and sg and NS.PLAYERS
        and sf and NS.Band(sf, NS.OBJ.TYPE_PLAYER) ~= 0
        and sg ~= NS.playerGUID then
        local r = rec.srcRole
        if r and r ~= "player" and r ~= "pet" and r ~= "hostile" and r ~= "neutral" then
            NS.PLAYERS.ObserveCast(sn, rec.snameLower)
        end
    end

    -- remember which spells show up ONLY as buffs/debuffs, so a right-click on
    -- one in the log can offer to hide it without guessing
    if rec.snameLower then
        if cat == "auras" then
            if NS.auraOnly[rec.snameLower] == nil then
                NS.auraOnly[rec.snameLower] = true
            end
        else
            NS.auraOnly[rec.snameLower] = false
        end
    end

    -- death recap capture (assigns rec.deathIdx for UNIT_DIED)
    if NS.DeathRecapIngest then NS.DeathRecapIngest(rec) end

    -- highlight sound
    if rec.snameLower and type(NS.db.highlights[rec.snameLower]) == "table" then
        local hl = NS.db.highlights[rec.snameLower]
        local key = NS.HighlightSoundKey(hl)
        if key ~= "none" and NS.db.general.highlightSound then
            local now = GetTime()
            if now - lastHighlightSound > 2 then
                lastHighlightSound = now
                NS.PlayAlertSound(key, hl.soundFile or NS.db.general.highlightSoundFile)
            end
        end
    end

    NS.BufferPush(rec)

    -- live capture
    if NS.captureActive then NS.CaptureLine(rec) end

    -- fan out to windows
    NS.DispatchToWindows(rec)
end
