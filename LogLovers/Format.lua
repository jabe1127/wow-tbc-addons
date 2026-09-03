-- LogLovers Format: normalized record -> rich interactive text line
local ADDON, NS = ...

local C = NS.C
local fmt = string.format

NS.formatGen = 1
function NS.InvalidateFormats()
    NS.formatGen = NS.formatGen + 1
end

-------------------------------------------------------------------------------
-- Tokens
-------------------------------------------------------------------------------
local function unitToken(guid, name, flags, raidFlags)
    if not name or name == "" then return C("Unknown", NS.COLORS.dim) end
    local hex = NS.UnitColor(guid, name, flags)
    local icon = NS.RaidIconTag(raidFlags, 12)
    if guid then
        return icon .. "|Hllu:" .. guid .. ":" .. name .. "|h" .. C(name, hex) .. "|h"
    end
    return icon .. C(name, hex)
end

local function spellToken(sid, sname, school)
    if not sname then return C("Melee", NS.COLORS.dim) end
    local hex
    if NS.db.appearance.schoolColors and school then
        hex = NS.SchoolInfo(school).color
    else
        hex = "d8c26e"
    end
    local hl = NS.db.highlights[string.lower(sname)]
    local prefix = ""
    if hl then
        hex = hl.color or NS.COLORS.highlight
        prefix = "|TInterface\\DialogFrame\\UI-Dialog-Icon-AlertNew:12|t"
    end
    local icon = NS.IconTag(sid)
    local text = C("[" .. sname .. "]", hex)
    if sid then
        return prefix .. icon .. "|Hspell:" .. sid .. "|h" .. text .. "|h"
    end
    return prefix .. icon .. text
end

local function meleeToken()
    return C("Melee", "cfcfcf")
end

local function amount(rec, hex)
    local s = NS.FormatNumber(rec.amt or 0)
    if rec.crit then s = "*" .. s .. "*" end
    return C(s, hex)
end

local function dmgAmountHex(rec)
    if NS.db.appearance.schoolColors and rec.dmgSchool then
        return NS.SchoolInfo(rec.dmgSchool).color
    end
    return "ffffff"
end

local function trailers(rec)
    local t = {}
    if rec.glance then t[#t + 1] = "glancing" end
    if rec.crush then t[#t + 1] = "crushing" end
    if rec.resisted and rec.resisted > 0 then t[#t + 1] = NS.FormatNumber(rec.resisted) .. " resisted" end
    if rec.blocked and rec.blocked > 0 then t[#t + 1] = NS.FormatNumber(rec.blocked) .. " blocked" end
    if rec.absorbed and rec.absorbed > 0 then t[#t + 1] = NS.FormatNumber(rec.absorbed) .. " absorbed" end
    if rec.over and rec.over > 0 then
        if rec.cat == "healing" then t[#t + 1] = NS.FormatNumber(rec.over) .. " over"
        else t[#t + 1] = NS.FormatNumber(rec.over) .. " overkill" end
    end
    if rec.offhand then t[#t + 1] = "OH" end
    if #t == 0 then return "" end
    return " " .. C("(" .. table.concat(t, ", ") .. ")", NS.COLORS.dim)
end

-------------------------------------------------------------------------------
-- Per-subevent renderers
-------------------------------------------------------------------------------
-- The separator between the two names was the dimmest thing on the line, which
-- is exactly backwards: it is the glyph that tells you which name is which.
local ARROW = " " .. NS.C("\194\187", "9aa6b8") .. " "   -- »

local function srcDst(rec)
    return unitToken(rec.sg, rec.sn, rec.sf, rec.srf) .. ARROW ..
           unitToken(rec.dg, rec.dn, rec.df, rec.drf)
end

local R = {}

R.damage = function(rec, verbose)
    local sp = rec.sub == "SWING_DAMAGE" and meleeToken()
        or rec.sub == "ENVIRONMENTAL_DAMAGE" and C(rec.env or "Environment", NS.COLORS.neutral)
        or spellToken(rec.sid, rec.sname, rec.sch)
    local hex = dmgAmountHex(rec)
    local tag = ""
    if rec.sub == "DAMAGE_SHIELD" then tag = C(" (shield)", NS.COLORS.dim)
    elseif rec.sub == "DAMAGE_SPLIT" then tag = C(" (split)", NS.COLORS.dim)
    elseif rec.sub == "SPELL_PERIODIC_DAMAGE" then tag = C(" (dot)", NS.COLORS.dim) end
    if verbose then
        local verb = rec.crit and "crits" or "hits"
        if rec.sub == "ENVIRONMENTAL_DAMAGE" then
            return unitToken(rec.dg, rec.dn, rec.df, rec.drf) .. " suffers " ..
                amount(rec, hex) .. " from " .. sp .. "." .. trailers(rec)
        end
        return unitToken(rec.sg, rec.sn, rec.sf, rec.srf) .. "'s " .. sp .. " " ..
            (rec.sub == "SWING_DAMAGE" and (verb .. " ") or (rec.crit and "crits " or "hits ")) ..
            unitToken(rec.dg, rec.dn, rec.df, rec.drf) .. " for " ..
            amount(rec, hex) .. "." .. tag .. trailers(rec)
    end
    if rec.sub == "ENVIRONMENTAL_DAMAGE" then
        -- "Jabe Falling 450" read as three unrelated tokens. Keep the same
        -- source -> target order as every other line, with the environment
        -- standing in as the source, so the arrow never points backwards.
        return C(rec.env or "Environment", NS.COLORS.neutral) .. ARROW ..
            unitToken(rec.dg, rec.dn, rec.df, rec.drf) .. "  " ..
            amount(rec, hex) .. trailers(rec)
    end
    return srcDst(rec) .. "  " .. sp .. "  " .. amount(rec, hex) .. tag .. trailers(rec)
end

R.misses = function(rec, verbose)
    local sp = (rec.sub == "SWING_MISSED") and meleeToken()
        or spellToken(rec.sid, rec.sname, rec.sch)
    local label = NS.MISS_LABELS[rec.miss or "MISS"] or rec.miss or "Miss"
    local amt = ""
    if rec.missAmt and rec.missAmt > 0 then
        amt = C(" (" .. NS.FormatNumber(rec.missAmt) .. ")", NS.COLORS.dim)
    end
    local tag = ""
    if rec.sub == "SPELL_PERIODIC_MISSED" then tag = C(" (dot)", NS.COLORS.dim) end
    -- off-hand was parsed and then dropped, so a dual-wielder could not tell
    -- which weapon whiffed
    local oh = rec.offhand and C(" (OH)", NS.COLORS.dim) or ""
    if verbose then
        -- "was immune by" and "was immune to by" are both nonsense; immunity is
        -- the one outcome that belongs to the target, not the swing
        if rec.miss == "IMMUNE" then
            return unitToken(rec.dg, rec.dn, rec.df, rec.drf) .. " is " ..
                C("immune", NS.COLORS.miss) .. " to " ..
                unitToken(rec.sg, rec.sn, rec.sf, rec.srf) .. "'s " .. sp ..
                "." .. amt .. tag .. oh
        end
        local verb = NS.MISS_VERBS[rec.miss or "MISS"] or string.lower(label)
        return unitToken(rec.sg, rec.sn, rec.sf, rec.srf) .. "'s " .. sp .. " was " ..
            C(verb, NS.COLORS.miss) .. " by " ..
            unitToken(rec.dg, rec.dn, rec.df, rec.drf) .. "." .. amt .. tag .. oh
    end
    return srcDst(rec) .. "  " .. sp .. "  " ..
        C(string.upper(label), NS.COLORS.miss) .. amt .. tag .. oh
end

R.healing = function(rec, verbose)
    local sp = spellToken(rec.sid, rec.sname, rec.sch)
    local hot = rec.sub == "SPELL_PERIODIC_HEAL" and C(" (hot)", NS.COLORS.dim) or ""
    if verbose then
        return unitToken(rec.sg, rec.sn, rec.sf, rec.srf) .. "'s " .. sp ..
            (rec.crit and " critically heals " or " heals ") ..
            unitToken(rec.dg, rec.dn, rec.df, rec.drf) .. " for " ..
            amount(rec, NS.COLORS.heal) .. "." .. hot .. trailers(rec)
    end
    return srcDst(rec) .. "  " .. sp .. "  " ..
        C("+", NS.COLORS.heal) .. amount(rec, NS.COLORS.heal) .. hot .. trailers(rec)
end

R.power = function(rec, verbose)
    local sp = spellToken(rec.sid, rec.sname, rec.sch)
    local p = NS.POWER_NAMES[rec.power or 0] or NS.POWER_NAMES[0]
    local isGain = rec.sub:find("ENERGIZE") ~= nil
    local verb = isGain and "+" or "-"
    local extra = ""
    if rec.extraAmt and rec.extraAmt > 0 then
        extra = C(" (+" .. NS.FormatNumber(rec.extraAmt) .. ")", NS.COLORS.dim)
    end
    if isGain and rec.over and rec.over > 0 then
        extra = extra .. C(" (" .. NS.FormatNumber(rec.over) .. " over)", NS.COLORS.dim)
    end
    if verbose then
        if isGain then
            return unitToken(rec.dg, rec.dn, rec.df, rec.drf) .. " gains " ..
                C(NS.FormatNumber(rec.amt or 0) .. " " .. p.name, p.color) ..
                " from " .. sp .. "." .. extra
        end
        return unitToken(rec.sg, rec.sn, rec.sf, rec.srf) .. "'s " .. sp .. " drains " ..
            C(NS.FormatNumber(rec.amt or 0) .. " " .. p.name, p.color) .. " from " ..
            unitToken(rec.dg, rec.dn, rec.df, rec.drf) .. "." .. extra
    end
    return srcDst(rec) .. "  " .. sp .. "  " ..
        C(verb .. NS.FormatNumber(rec.amt or 0) .. " " .. p.name, p.color) .. extra
end

R.auras = function(rec, verbose)
    local sp = spellToken(rec.sid, rec.sname, rec.sch)
    local isBuff = rec.aura == "BUFF"
    local sign, hex
    local unit = unitToken(rec.dg, rec.dn, rec.df, rec.drf)
    local dose = rec.dose and rec.dose > 0 and C(" (" .. rec.dose .. ")", NS.COLORS.dim) or ""
    -- The caster was parsed and then dropped, so "who put that on me" - the one
    -- question an aura line exists to answer - had no answer. Show it whenever
    -- somebody other than the target did it.
    local caster = ""
    if rec.sn and rec.sn ~= "" and rec.sg ~= rec.dg then
        caster = unitToken(rec.sg, rec.sn, rec.sf, rec.srf) .. ARROW
    end
    if rec.sub == "SPELL_AURA_APPLIED" or rec.sub == "SPELL_AURA_APPLIED_DOSE" then
        sign, hex = "+", isBuff and NS.COLORS.buff or NS.COLORS.debuff
    elseif rec.sub == "SPELL_AURA_REMOVED" or rec.sub == "SPELL_AURA_REMOVED_DOSE" then
        sign, hex = "-", NS.COLORS.dim
    elseif rec.sub == "SPELL_AURA_REFRESH" then
        sign, hex = "~", isBuff and NS.COLORS.buff or NS.COLORS.debuff
    else -- broken
        local by = rec.xname and (" with " .. spellToken(rec.xid, rec.xname, rec.xsch)) or ""
        if rec.sn and rec.sn ~= "" then
            if verbose then
                return unitToken(rec.sg, rec.sn, rec.sf, rec.srf) .. " " ..
                    C("breaks", NS.COLORS.interrupt) .. " " .. sp .. " on " .. unit .. by .. "."
            end
            return unitToken(rec.sg, rec.sn, rec.sf, rec.srf) .. ARROW .. unit ..
                "  " .. C("break", NS.COLORS.interrupt) .. "  " .. sp .. by
        end
        if verbose then
            return unit .. "'s " .. sp .. " " .. C("breaks", NS.COLORS.interrupt) .. by .. "."
        end
        return unit .. "  " .. C("break", NS.COLORS.interrupt) .. "  " .. sp .. by
    end
    if verbose then
        local verb
        if sign == "+" then verb = isBuff and " gains " or " is afflicted by "
        elseif sign == "-" then verb = isBuff and " loses " or " is cured of "
        else verb = " refreshes " end
        if caster ~= "" then
            return unitToken(rec.sg, rec.sn, rec.sf, rec.srf) .. "'s " .. sp ..
                (sign == "-" and " fades from " or " lands on ") .. unit .. dose .. "."
        end
        return unit .. verb .. sp .. dose .. "."
    end
    return caster .. unit .. "  " .. C(sign, hex) .. " " .. sp .. dose
end

R.casts = function(rec, verbose)
    local sp = spellToken(rec.sid, rec.sname, rec.sch)
    local unit = unitToken(rec.sg, rec.sn, rec.sf, rec.srf)
    if rec.sub == "SPELL_CAST_START" then
        return unit .. " " .. C("begins", NS.COLORS.interrupt) .. " " .. sp
    elseif rec.sub == "SPELL_CAST_FAILED" then
        return unit .. " " .. C("fails", NS.COLORS.fail) .. " " .. sp ..
            (rec.failReason and C(" (" .. rec.failReason .. ")", NS.COLORS.dim) or "")
    end
    local tgt = ""
    if rec.dn then tgt = ARROW .. unitToken(rec.dg, rec.dn, rec.df, rec.drf) end
    return unit .. " " .. C("casts", NS.COLORS.dim) .. " " .. sp .. tgt
end

R.interrupts = function(rec, verbose)
    local sp = spellToken(rec.sid, rec.sname, rec.sch)
    local xsp = spellToken(rec.xid, rec.xname, rec.xsch)
    if verbose then
        return unitToken(rec.sg, rec.sn, rec.sf, rec.srf) .. " " ..
            C("interrupts", NS.COLORS.interrupt) .. " " ..
            unitToken(rec.dg, rec.dn, rec.df, rec.drf) .. "'s " .. xsp .. " with " .. sp .. "."
    end
    return srcDst(rec) .. "  " .. C("INTERRUPT", NS.COLORS.interrupt) .. "  " .. xsp ..
        C("  (", NS.COLORS.dim) .. sp .. C(")", NS.COLORS.dim)
end

R.dispels = function(rec, verbose)
    local sp = spellToken(rec.sid, rec.sname, rec.sch)
    local xsp = spellToken(rec.xid, rec.xname, rec.xsch)
    local verb, short = "dispels", "DISPEL"
    if rec.sub == "SPELL_STOLEN" then verb, short = "steals", "STEAL"
    elseif rec.sub == "SPELL_DISPEL_FAILED" then verb, short = "fails to dispel", "DISPEL FAILED" end
    -- buff or debuff was parsed and never shown, so a stolen buff and a cured
    -- debuff looked identical
    local kind = rec.aura and C(" " .. string.lower(rec.aura), NS.COLORS.dim) or ""
    if verbose then
        return unitToken(rec.sg, rec.sn, rec.sf, rec.srf) .. " " ..
            C(verb, NS.COLORS.dispel) .. " " .. xsp .. kind .. " from " ..
            unitToken(rec.dg, rec.dn, rec.df, rec.drf) .. " " ..
            C("(", NS.COLORS.dim) .. sp .. C(")", NS.COLORS.dim)
    end
    return srcDst(rec) .. "  " .. C(short, NS.COLORS.dispel) .. "  " .. xsp .. kind ..
        C("  (", NS.COLORS.dim) .. sp .. C(")", NS.COLORS.dim)
end

R.deaths = function(rec, verbose)
    local skull = fmt(NS.SKULL_ICON, 14) .. " "
    if rec.sub == "PARTY_KILL" then
        return unitToken(rec.sg, rec.sn, rec.sf, rec.srf) .. " " ..
            C("killed", NS.COLORS.death) .. " " ..
            unitToken(rec.dg, rec.dn, rec.df, rec.drf)
    end
    local name = unitToken(rec.dg, rec.dn, rec.df, rec.drf)
    local recap = ""
    if rec.deathIdx then
        recap = "  |Hlld:" .. rec.deathIdx .. "|h" .. C("[recap]", NS.COLORS.accent) .. "|h"
    end
    local feign = rec.feign and C(" (Feign Death?)", NS.COLORS.dim) or ""
    return skull .. name .. " " .. C("dies", NS.COLORS.death) .. feign .. recap
end

R.enchants = function(rec, verbose)
    local verb = rec.sub == "ENCHANT_APPLIED" and "gains" or "loses"
    local what = C(rec.sname or "an enchant", NS.COLORS.buff) ..
        (rec.itemName and C(" on " .. rec.itemName, NS.COLORS.dim) or "")
    local dst = unitToken(rec.dg, rec.dn, rec.df, rec.drf)
    -- who applied the poison/oil/sharpening stone used to be dropped
    if rec.sn and rec.sn ~= "" and rec.sg ~= rec.dg then
        local src = unitToken(rec.sg, rec.sn, rec.sf, rec.srf)
        if verbose then
            return src .. " applies " .. what .. " to " .. dst .. "."
        end
        return src .. ARROW .. dst .. "  " .. C(verb, NS.COLORS.dim) .. "  " .. what
    end
    if verbose then
        return dst .. " " .. C(verb, NS.COLORS.dim) .. " " .. what .. "."
    end
    return dst .. "  " .. C(verb, NS.COLORS.dim) .. "  " .. what
end

R.other = function(rec, verbose)
    local unitS = unitToken(rec.sg, rec.sn, rec.sf, rec.srf)
    local unitD = unitToken(rec.dg, rec.dn, rec.df, rec.drf)
    local sp = spellToken(rec.sid, rec.sname, rec.sch)
    if rec.sub == "SPELL_EXTRA_ATTACKS" then
        return unitS .. " gains " .. C((rec.amt or 1) .. " extra attack(s)", NS.COLORS.crit) ..
            " from " .. sp
    elseif rec.sub == "SPELL_SUMMON" then
        return unitS .. " " .. C("summons", NS.COLORS.dim) .. " " .. unitD .. " (" .. sp .. ")"
    elseif rec.sub == "SPELL_CREATE" then
        return unitS .. " " .. C("creates", NS.COLORS.dim) .. " " .. sp
    elseif rec.sub == "SPELL_INSTAKILL" then
        return unitS .. " " .. C("INSTAKILLS", NS.COLORS.death) .. " " .. unitD .. " (" .. sp .. ")"
    elseif rec.sub == "SPELL_RESURRECT" then
        return unitS .. " " .. C("resurrects", NS.COLORS.buff) .. " " .. unitD .. " (" .. sp .. ")"
    elseif rec.sub:find("DURABILITY") then
        return unitS .. " damages " .. unitD .. "'s equipment (" .. sp .. ")"
    end
    return unitS .. " " .. C(rec.sub, NS.COLORS.dim) .. " " .. unitD
end

-------------------------------------------------------------------------------
-- Entry point
-------------------------------------------------------------------------------
function NS.FormatRecord(rec)
    if rec.line and rec.gen == NS.formatGen then return rec.line end
    local verbose = NS.db.general.style == "verbose"
    local renderer = R[rec.cat] or R.other
    local ok, body = pcall(renderer, rec, verbose)
    if not ok or not body then
        body = C(rec.sub or "?", NS.COLORS.dim)
    end
    rec.line = NS.FormatTime(rec) .. body
    rec.plain = NS.StripEscapes(rec.line)
    rec.plainLower = string.lower(rec.plain)
    rec.gen = NS.formatGen
    return rec.line
end

-- Plain text with a fixed timestamp, for exports/captures (independent of UI ts mode)
function NS.ExportLine(rec)
    NS.FormatRecord(rec)
    local body = rec.plain
    if NS.db.general.timestampMode == "none" then
        body = date("%H:%M:%S", rec.t) .. " " .. body
    end
    return body
end
