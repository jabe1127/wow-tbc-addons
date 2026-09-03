-- LogLovers DeathRecap: per-unit event history and death timeline browser
local ADDON, NS = ...

local C = NS.C

-- a hoverable/clickable spell token, same link type the combat windows use
local function spellLink(sid, name, hex, iconSize)
    name = name or "Melee"
    local body = NS.IconTag(sid, iconSize or 12) .. C(name, hex or "e8c9a0")
    if sid then
        return "|Hspell:" .. sid .. "|h" .. body .. "|h"
    end
    return body
end

-- Who did it. The timeline used to trail the source name in grey after the
-- spell, and left it off aura lines entirely - so "who put that on me" and
-- "who landed the killing blow" were the two things you could not read. The
-- name now leads every row, coloured by class (or role, for a recap restored
-- after the client has forgotten the GUID) and clickable like any other unit.
local function actorToken(rec)
    local name = rec and rec.sn
    if not name or name == "" then return C("Environment", NS.COLORS.dim) end
    local short = name:match("^([^%-]+)") or name
    local hex = NS.UnitColor(rec.sg, name, rec.sf)
    local icon = NS.RaidIconTag and NS.RaidIconTag(rec.srf, 12) or ""
    if rec.sg then
        return icon .. "|Hllu:" .. rec.sg .. ":" .. name .. "|h" .. C(short, hex) .. "|h"
    end
    return icon .. C(short, hex)
end
NS.DeathActorToken = actorToken

local RECAP_SEP = "  " .. C("\194\187", "8b96a5") .. "  "   -- »

NS.deaths = {}                -- newest last: { guid, name, t, feign, segIndex, events = { rec... } }
local recent = {}             -- [guid] = { touched = t, list = { rec... } }
local ingestCounter = 0
local deathCounter = 0

local TRACKED = { damage = true, healing = true, misses = true, auras = true, interrupts = true, dispels = true }

local function pruneList(entry, now, window)
    local list = entry.list
    while #list > 0 and (now - list[1].t) > window do
        table.remove(list, 1)
    end
end

-- How far back a timeline reaches for this event.
--
-- "Whole fight" means back to the start of the current combat segment, so a
-- boss kill shows the whole pull rather than the last few seconds. Out of
-- combat there is no segment, so the plain seconds window is the floor.
local function recapWindow(cfgDR, rec)
    local secs = cfgDR.seconds or 12
    if cfgDR.wholeFight and rec.segStart then
        return math.max((rec.t or 0) - rec.segStart, secs)
    end
    return secs
end

function NS.DeathRecapIngest(rec)
    local cfgDR = NS.db.deathRecap
    if not cfgDR.enabled then return end

    -- track events landing on a unit
    if rec.dg and TRACKED[rec.cat] then
        local e = recent[rec.dg]
        if not e then
            e = { touched = rec.t, list = {} }
            recent[rec.dg] = e
        end
        e.touched = rec.t
        table.insert(e.list, rec)
        pruneList(e, rec.t, recapWindow(cfgDR, rec))
        local cap = cfgDR.maxEvents or 200
        while #e.list > cap do table.remove(e.list, 1) end
    end

    -- housekeeping sweep
    ingestCounter = ingestCounter + 1
    if ingestCounter % 1000 == 0 then
        for guid, e in pairs(recent) do
            if rec.t - e.touched > 120 then recent[guid] = nil end
        end
    end

    -- record deaths
    if rec.sub == "UNIT_DIED" or rec.sub == "UNIT_DESTROYED" or rec.sub == "UNIT_DISSIPATES" then
        if cfgDR.friendlyOnly then
            local r = rec.dstRole
            if r == "hostile" or r == "neutral" then return end
        end
        local e = recent[rec.dg]
        local events = {}
        if e then
            pruneList(e, rec.t, recapWindow(cfgDR, rec))
            for i, r2 in ipairs(e.list) do events[i] = r2 end
        end
        deathCounter = deathCounter + 1
        local death = {
            id = deathCounter,
            guid = rec.dg, name = rec.dn or "Unknown", t = rec.t,
            feign = rec.feign, segIndex = rec.segIndex, events = events,
            role = rec.dstRole,
        }
        table.insert(NS.deaths, death)
        NS.TrimDeaths()
        rec.deathIdx = deathCounter
        NS.SaveDeath(death)
    end
end

-------------------------------------------------------------------------------
-- Persistence
--
-- The in-memory recap holds whole event records; SavedVariables gets a compact
-- copy with only the fields the timeline actually renders. Each saved entry is
-- kept as a live reference on its death, so loot picked up later lands in both.
-------------------------------------------------------------------------------
local SAVED_FIELDS = {
    "t", "cat", "sub", "amt", "over", "absorbed", "crit",
    "sid", "sname", "miss", "aura", "env",
    -- who did it: the name, its GUID (so the saved line stays clickable and
    -- class-coloured) and its flags (so it still colours by role if the client
    -- has forgotten the GUID by the time you read the recap back)
    "sn", "sg", "sf", "srf",
    -- detail that used to be parsed and then thrown away
    "resisted", "blocked", "dose", "glance", "crush", "offhand",
}
local RENDERED_DIRECTLY = { damage = true, healing = true, misses = true, auras = true }

local function compactEvent(rec)
    local out = { restored = true }
    -- Skip zeroes and falses. Every damage record carries resisted=0,
    -- blocked=0, glance=false and so on, and the timeline only ever renders
    -- them when they are set - writing them all out nearly doubled the size of
    -- the saved history for nothing.
    for _, k in ipairs(SAVED_FIELDS) do
        local v = rec[k]
        if v and v ~= 0 then out[k] = v end
    end
    if rec.restored then
        -- already a compact copy: its text was baked when it was first saved,
        -- and re-running the formatter would rebuild it from fields we never
        -- persisted and quietly degrade the line
        out.plain = rec.plain
    elseif not RENDERED_DIRECTLY[rec.cat] then
        -- interrupts, dispels and anything else are rendered through the normal
        -- formatter, which needs fields we do not keep - bake the text now.
        -- FormatRecord prefixes its own timestamp; the recap timeline adds a
        -- relative one, so strip it or the restored line shows both.
        if NS.FormatRecord then pcall(NS.FormatRecord, rec) end
        local text = rec.plain
        if text and NS.FormatTime then
            local okT, stamp = pcall(NS.FormatTime, rec)
            if okT and stamp and stamp ~= "" then
                stamp = NS.StripEscapes(stamp)
                if stamp ~= "" and text:sub(1, #stamp) == stamp then
                    text = text:sub(#stamp + 1)
                end
            end
        end
        out.plain = text or rec.sub
    end
    return out
end

-- Same rule as the saved history: recaps you pinned are never the ones dropped
-- to make room for a new death.
function NS.TrimDeaths()
    local limit = (NS.db.deathRecap.maxDeaths or 60)
    local i = 1
    -- never the last element: if every older entry is pinned, going one over
    -- the limit is far better than deleting the death that just happened and
    -- leaving a dead [recap] link in the log
    while #NS.deaths > limit and i < #NS.deaths do
        if NS.deaths[i].keep then
            i = i + 1
        else
            table.remove(NS.deaths, i)
        end
    end
end

-- The saved copy of a death, if it is still in the history. Deaths can outlive
-- their saved entry (the history is smaller), and the history table itself is
-- replaced when the user clears it - so never trust a stale death.saved.
local function savedEntryFor(death)
    local hist = NS.db and NS.db.deathHistory
    if not hist then return nil end
    for _, s in ipairs(hist) do
        if s == death.saved then return s end
    end
    for _, s in ipairs(hist) do
        if s.guid == death.guid and s.t == death.t then return s end
    end
end

function NS.SaveDeath(death)
    local cfgDR = NS.db and NS.db.deathRecap
    if not cfgDR or not cfgDR.persist then return end
    NS.db.deathHistory = NS.db.deathHistory or {}

    local ev = {}
    for i, rec in ipairs(death.events) do ev[i] = compactEvent(rec) end
    local saved = {
        guid = death.guid, name = death.name, t = death.t,
        feign = death.feign, role = death.role, events = ev,
        loot = death.loot, restored = true,
        -- carried BEFORE the trim below, or pinning a recap on a full history
        -- would drop the very entry it just wrote
        keep = death.keep, title = death.title,
    }
    death.saved = saved
    table.insert(NS.db.deathHistory, saved)
    NS.TrimDeathHistory()
end

-- Drops the oldest recaps until the history fits, skipping any the user has
-- explicitly kept. Keeping 3 out of a 150 limit leaves 147 rolling slots.
function NS.TrimDeathHistory()
    local hist = NS.db.deathHistory
    if not hist then return end
    local limit = (NS.db.deathRecap.keepHistory or 40)
    local i = 1
    -- same rule as the in-memory list: the newest entry is never the sacrifice
    while #hist > limit and i < #hist do
        if hist[i].keep then
            i = i + 1
        else
            table.remove(hist, i)
        end
    end
end

-- How many of the saved recaps are pinned, and what that leaves rolling.
function NS.DeathHistoryCounts()
    local total, kept = 0, 0
    for _, s in ipairs(NS.db.deathHistory or {}) do
        total = total + 1
        if s.keep then kept = kept + 1 end
    end
    return total, kept
end

-- Called once at login. Restored deaths sort before anything this session, and
-- their ids continue the same sequence so [recap] links stay unique.
function NS.RestoreDeaths()
    local cfgDR = NS.db.deathRecap
    NS.db.deathHistory = NS.db.deathHistory or {}
    if not cfgDR.persist then
        -- history is off, but a recap the user deliberately saved is not
        -- history - it is a thing they asked to keep, so it still comes back
        for i = #NS.db.deathHistory, 1, -1 do
            if not NS.db.deathHistory[i].keep then table.remove(NS.db.deathHistory, i) end
        end
        if #NS.db.deathHistory == 0 then return 0 end
    end
    NS.TrimDeathHistory()
    local hist = NS.db.deathHistory

    for _, saved in ipairs(hist) do
        deathCounter = deathCounter + 1
        table.insert(NS.deaths, {
            id = deathCounter,
            guid = saved.guid, name = saved.name, t = saved.t,
            feign = saved.feign, role = saved.role,
            events = saved.events or {},
            loot = saved.loot,
            keep = saved.keep,
            title = saved.title,
            saved = saved,
            fromLastSession = true,
        })
    end
    -- the in-memory cap still applies, but a recap you deliberately saved is
    -- never the one thrown away to make room
    local restored = #hist
    local i = 1
    while #NS.deaths > (cfgDR.maxDeaths or 60) and i <= #NS.deaths do
        if NS.deaths[i].keep then
            i = i + 1
        else
            table.remove(NS.deaths, i)
            restored = restored - 1
        end
    end
    return math.max(restored, 0)
end

-- Clears the rolling history. Recaps the user explicitly saved survive unless
-- includeSaved is set, because throwing away a fight someone pinned on purpose
-- is not what "clear history" should mean.
function NS.ClearDeathHistory(includeSaved)
    local hist = NS.db.deathHistory
    if not hist then
        NS.db.deathHistory = {}
        hist = NS.db.deathHistory
    end
    local dropped = 0
    for i = #hist, 1, -1 do
        if includeSaved or not hist[i].keep then
            table.remove(hist, i)
            dropped = dropped + 1
        end
    end
    for i = #NS.deaths, 1, -1 do
        local d = NS.deaths[i]
        if includeSaved or not d.keep then
            if d.fromLastSession then
                table.remove(NS.deaths, i)
            else
                -- its saved copy is gone, so it must stop claiming to be saved
                d.saved, d.keep, d.title = nil, nil, nil
            end
        end
    end
    if NS.ClearDeathSelection then NS.ClearDeathSelection() end
    if NS.RefreshDeathBrowser then NS.RefreshDeathBrowser() end
    return dropped
end

-------------------------------------------------------------------------------
-- Saving individual recaps
--
-- A saved recap is pinned: never auto-dropped, shown in gold, and renameable.
-- It still occupies one of the history slots, so saving 3 with a limit of 150
-- leaves 147 for the rolling ones.
-------------------------------------------------------------------------------
function NS.SetDeathKept(death, keep)
    if not death then return false end
    death.keep = keep and true or nil
    if not keep then death.title = nil end

    if keep then
        -- pinning something from this session has to write it to disk, or it
        -- would not survive the logout it was pinned to survive
        local saved = savedEntryFor(death)
        if not saved then
            local wasPersist = NS.db.deathRecap.persist
            NS.db.deathRecap.persist = true
            -- pcall: an error in here must not leave persistence switched on
            -- behind the user's back, since that setting gets written to disk
            pcall(NS.SaveDeath, death)
            NS.db.deathRecap.persist = wasPersist
            saved = death.saved
        end
        if saved then
            saved.keep = true
            saved.title = death.title
            death.saved = saved
        end
        -- pinning past the limit means nothing new is being kept; say so
        local _, kept = NS.DeathHistoryCounts()
        local limit = NS.db.deathRecap.keepHistory or 40
        if kept >= limit then
            NS.Print("that is " .. kept .. " saved recaps, your whole limit of " .. limit ..
                ". Nothing new will be kept until you raise it or unsave a few.")
        end
    else
        local saved = savedEntryFor(death)
        if saved then saved.keep, saved.title = nil, nil end
        NS.TrimDeathHistory()
    end
    if NS.RefreshDeathBrowser then NS.RefreshDeathBrowser(death) end
    return true
end

function NS.RenameDeath(death, title)
    if not death then return false end
    title = (title or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if title == "" then title = nil end
    -- naming a recap is how you save it; there is no sensible "named but
    -- about to be auto-deleted" state
    if title and not death.keep then NS.SetDeathKept(death, true) end
    death.title = title
    local saved = savedEntryFor(death)
    if saved then saved.title = title end
    if NS.RefreshDeathBrowser then NS.RefreshDeathBrowser(death) end
    return true
end

function NS.DeleteDeath(death)
    if not death then return false end
    local saved = savedEntryFor(death)
    if saved then
        for i, s in ipairs(NS.db.deathHistory or {}) do
            if s == saved then table.remove(NS.db.deathHistory, i) break end
        end
    end
    for i, d in ipairs(NS.deaths) do
        if d == death then table.remove(NS.deaths, i) break end
    end
    if NS.ClearDeathSelection then NS.ClearDeathSelection() end
    if NS.RefreshDeathBrowser then NS.RefreshDeathBrowser() end
    return true
end

-- Label for a recap in lists and headers: its name if it has one.
-- Who landed the last blow, for the list rows and the tooltip. Nil when the
-- recap holds no damage at all (a feign, or a death with an empty timeline).
function NS.DeathKiller(death)
    if not death or not death.events then return nil end
    for i = #death.events, 1, -1 do
        local rec = death.events[i]
        if rec.cat == "damage" then
            local n = rec.sn
            if n and n ~= "" then return (n:match("^([^%-]+)") or n), rec end
            return (rec.env or "Environment"), rec
        end
    end
    return nil
end

function NS.DeathLabel(death)
    if not death then return "?" end
    return death.title or death.name or "Unknown"
end

-------------------------------------------------------------------------------
-- Loot: what the corpse actually dropped
-------------------------------------------------------------------------------
local ITEM_QUALITY_HEX = {
    [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd",
    [4] = "a335ee", [5] = "ff8000", [6] = "e6cc80", [7] = "00ccff",
}

local function lootSourceGUID(slots)
    if GetLootSourceInfo then
        for slot = 1, slots do
            local ok, g = pcall(GetLootSourceInfo, slot)
            if ok and type(g) == "string" and g ~= "" then return g end
        end
    end
    -- clients without GetLootSourceInfo: the corpse you are looting is almost
    -- always your target
    if UnitGUID and UnitExists and UnitExists("target") then
        if not UnitIsDead or UnitIsDead("target") then return UnitGUID("target") end
    end
end

-- Falls back to the most recent unfriendly death, so looting still lands
-- somewhere sensible when the client gives us no source GUID at all.
local function deathForLoot(guid, now)
    -- when the client told us whose corpse this is, that answer is final -
    -- guessing would staple loot onto an unrelated kill
    if guid then return NS.FindLastDeath(guid) end
    for i = #NS.deaths, 1, -1 do
        local d = NS.deaths[i]
        if not d.fromLastSession and (d.role == "hostile" or d.role == "neutral") then
            if not now or (now - d.t) < 120 then return d end
            return nil
        end
    end
end

function NS.CaptureLoot()
    local cfgDR = NS.db and NS.db.deathRecap
    if not cfgDR or not cfgDR.enabled or not cfgDR.trackLoot then return end
    local slots = (GetNumLootItems and GetNumLootItems()) or 0
    if slots == 0 then return end

    local items = {}
    for slot = 1, slots do
        local link = GetLootSlotLink and GetLootSlotLink(slot)
        local _, name, qty, _, quality
        if GetLootSlotInfo then
            _, name, qty, _, quality = GetLootSlotInfo(slot)
        end
        local isMoney = false
        if GetLootSlotType and LOOT_SLOT_MONEY then
            isMoney = GetLootSlotType(slot) == LOOT_SLOT_MONEY
        elseif not link and name then
            isMoney = true
        end
        if link or name then
            items[#items + 1] = {
                link = link, name = name, count = qty or 1,
                quality = quality, money = isMoney or nil,
            }
        end
    end
    if #items == 0 then return end

    local now = (time and time()) or 0
    local death = deathForLoot(lootSourceGUID(slots), now > 0 and now or nil)
    if not death then return end

    death.loot = items
    local saved = savedEntryFor(death)
    if saved then
        saved.loot = items
        death.saved = saved
    end
    if NS.RefreshDeathBrowser then NS.RefreshDeathBrowser(death) end
end

local lootWatcher = CreateFrame("Frame")
lootWatcher:RegisterEvent("LOOT_OPENED")
lootWatcher:SetScript("OnEvent", function()
    if NS.db then pcall(NS.CaptureLoot) end
end)

function NS.FindLastDeath(guid)
    for i = #NS.deaths, 1, -1 do
        if NS.deaths[i].guid == guid then return NS.deaths[i] end
    end
end

-------------------------------------------------------------------------------
-- Browser UI
-------------------------------------------------------------------------------
local frame, listButtons, detailText
local currentMode = "killed"
local currentDeath
listButtons = {}

-------------------------------------------------------------------------------
-- Fight-log view modes
--
-- The recap's own event list only ever held what landed ON the dying unit, so
-- it could not answer "what was I doing" or "what was the rest of the raid
-- doing". Those views are built from the ring buffer instead, through the same
-- filter predicate the combat windows use - so the three modes here are exactly
-- the three the rest of the addon already understands, and no extra events have
-- to be recorded or saved to support them.
--
--   killed  - what killed them. The stored recap, unchanged, and the only mode
--             that works for a recap restored from a previous session.
--   mine    - what I and my pet did during the fight.
--   onme    - what was done to me during the fight.
--   all     - everything everyone did. Long; this is what the pop-out is for.
-------------------------------------------------------------------------------
NS.FIGHT_MODES = {
    { key = "killed", label = "What killed me" },
    { key = "mine",   label = "Me & pet" },
    { key = "onme",   label = "On me" },
    { key = "all",    label = "Everyone" },
}

local function modeFilter(mode)
    local f = NS.DefaultFilterAll()
    local scope = (mode == "all") and "all" or "me"
    for _, loc in ipairs(NS.LOCATIONS) do f.scopes[loc.key] = scope end
    if mode == "mine" then f.direction = "out"
    elseif mode == "onme" then f.direction = "in"
    else f.direction = "both" end
    return f
end

-- The window a fight log covers: the whole fight when we know where it started,
-- otherwise the same seconds the recap itself used.
local function fightWindow(death)
    local secs = NS.db.deathRecap.seconds or 12
    local first = death.events and death.events[1]
    local from = (first and first.t) or (death.t - secs)
    -- the recap's own first event is a floor, not the truth: the fight may have
    -- started before anything landed on this unit
    for _, seg in ipairs(NS.segments or {}) do
        if seg.index == death.segIndex and seg.firstT then
            from = math.min(from, seg.firstT)
            break
        end
    end
    return from, death.t
end

-- Records for one death's fight, in the requested mode. Returns nil when the
-- buffer can no longer answer (a restored recap, or a fight rolled out of the
-- buffer), so callers can fall back to the stored timeline and say so.
function NS.FightLogFor(death, mode)
    if not death or mode == "killed" then return nil end
    if death.restored or (death.events and death.events[1] and death.events[1].restored) then
        return nil
    end
    local from, to = fightWindow(death)
    local f = modeFilter(mode)
    local out, seen, oldest = {}, false, nil
    NS.BufferEach(function(rec)
        if oldest == nil or rec.t < oldest then oldest = rec.t end
        if rec.t >= from and rec.t <= to then
            seen = true
            if NS.RecordPasses(rec, f) then out[#out + 1] = rec end
        end
    end)
    if not seen then return nil end
    -- The buffer may hold only the tail of a long fight. Say so, rather than
    -- printing a header that claims this is the whole thing.
    if oldest and oldest > from + 1 then out.clipped = oldest - from end
    return out
end

-- One timeline row, shared by the recap and by the fight-log views.
local function recapRow(rec)
    local body
    -- every row reads the same way: who » what » how much
    if rec.cat == "damage" then
        body = actorToken(rec) .. RECAP_SEP ..
            spellLink(rec.sid, rec.sname or rec.env, "e8c9a0") .. "  " ..
            C("-" .. NS.FormatNumber(rec.amt or 0), "ff7a7a") ..
            (rec.crit and C(" crit", NS.COLORS.crit) or "")
        local extra = {}
        if rec.over and rec.over > 0 then extra[#extra + 1] = NS.FormatNumber(rec.over) .. " overkill" end
        if rec.absorbed and rec.absorbed > 0 then extra[#extra + 1] = NS.FormatNumber(rec.absorbed) .. " absorbed" end
        if rec.resisted and rec.resisted > 0 then extra[#extra + 1] = NS.FormatNumber(rec.resisted) .. " resisted" end
        if rec.blocked and rec.blocked > 0 then extra[#extra + 1] = NS.FormatNumber(rec.blocked) .. " blocked" end
        if rec.glance then extra[#extra + 1] = "glancing" end
        if rec.crush then extra[#extra + 1] = "crushing" end
        if #extra > 0 then body = body .. C(" (" .. table.concat(extra, ", ") .. ")", NS.COLORS.dim) end
    elseif rec.cat == "healing" then
        body = actorToken(rec) .. RECAP_SEP ..
            spellLink(rec.sid, rec.sname, NS.COLORS.heal) .. "  " ..
            C("+" .. NS.FormatNumber(rec.amt or 0), NS.COLORS.heal) ..
            (rec.crit and C(" crit", NS.COLORS.crit) or "")
        if rec.over and rec.over > 0 then
            body = body .. C(" (" .. NS.FormatNumber(rec.over) .. " over)", NS.COLORS.dim)
        end
    elseif rec.cat == "misses" then
        body = actorToken(rec) .. RECAP_SEP ..
            spellLink(rec.sid, rec.sname or "Melee", NS.COLORS.miss) .. "  " ..
            C((NS.MISS_LABELS[rec.miss] or rec.miss or "Miss"):upper(), NS.COLORS.miss) ..
            (rec.offhand and C(" (OH)", NS.COLORS.dim) or "")
    elseif rec.cat == "auras" then
        local sign = (rec.sub == "SPELL_AURA_APPLIED" or rec.sub == "SPELL_AURA_APPLIED_DOSE"
            or rec.sub == "SPELL_AURA_REFRESH") and "+" or "-"
        local hex = rec.aura == "BUFF" and NS.COLORS.buff or NS.COLORS.debuff
        body = actorToken(rec) .. RECAP_SEP .. C(sign, hex) .. " " ..
            spellLink(rec.sid, rec.sname, hex) ..
            ((rec.dose and rec.dose > 0) and C(" (" .. rec.dose .. ")", NS.COLORS.dim) or "")
    elseif rec.restored then
        -- restored from a previous session: the text was baked at save time
        body = C(rec.plain or rec.sub or "?", NS.COLORS.dim)
    else
        NS.FormatRecord(rec)
        body = rec.plain
    end
    return body
end

-------------------------------------------------------------------------------
-- Reading a death
--
-- A recap is two hundred events, and the moment someone dies they shed fifteen
-- buffs, so the bottom of every timeline was fifteen lines of "loses X". The
-- questions a raid leader has - what hit them, who healed them, what were they
-- carrying when they went down - are all in those lines, but only by reading
-- every one. So: answer the questions first, condense the timeline, and keep
-- every event reachable underneath.
-------------------------------------------------------------------------------
local SHED_WINDOW = 0.5      -- auras removed this close to the death are the shed
local BURST_WINDOW = 5       -- "the last five seconds"

local function shortName(n) return (n or "?"):match("^([^%-]+)") or n or "?" end

-- Everything the summary needs, in one pass.
local function analyse(death)
    local a = {
        totalDmg = 0, totalHeal = 0, totalOver = 0, totalAbsorb = 0,
        burstDmg = 0, burstHeal = 0, burstAbsorb = 0,
        killer = nil, biggest = 0, biggestRec = nil,
        bySource = {}, sourceOrder = {},     -- who hit them, by source then spell
        byHealer = {}, healerOrder = {},     -- who healed them
        shedBuffs = {}, shedDebuffs = {},    -- what they died carrying
        shedIdx = {},                        -- event indexes folded into the shed
    }
    local t0 = death.t or 0
    for idx, rec in ipairs(death.events) do
        local dt = t0 - (rec.t or t0)
        if rec.cat == "damage" then
            local amt = rec.amt or 0
            a.totalDmg = a.totalDmg + amt
            a.totalAbsorb = a.totalAbsorb + (rec.absorbed or 0)
            if dt <= BURST_WINDOW then
                a.burstDmg = a.burstDmg + amt
                a.burstAbsorb = a.burstAbsorb + (rec.absorbed or 0)
            end
            if amt > a.biggest then a.biggest, a.biggestRec = amt, rec end
            a.killer = rec
            local who = rec.sn or rec.env or "Environment"
            local src = a.bySource[who]
            if not src then
                src = { name = who, total = 0, spells = {}, spellOrder = {}, rec = rec }
                a.bySource[who] = src
                a.sourceOrder[#a.sourceOrder + 1] = who
            end
            src.total = src.total + amt
            local sp = rec.sname or rec.env or "Melee"
            local e = src.spells[sp]
            if not e then
                e = { name = sp, sid = rec.sid, total = 0, count = 0 }
                src.spells[sp] = e
                src.spellOrder[#src.spellOrder + 1] = sp
            end
            e.total, e.count = e.total + amt, e.count + 1
        elseif rec.cat == "healing" then
            local amt, over = rec.amt or 0, rec.over or 0
            local eff = math.max(0, amt - over)
            a.totalHeal, a.totalOver = a.totalHeal + eff, a.totalOver + over
            if dt <= BURST_WINDOW then a.burstHeal = a.burstHeal + eff end
            local who = rec.sn or "?"
            local h = a.byHealer[who]
            if not h then
                h = { name = who, eff = 0, over = 0, count = 0, spells = {}, spellOrder = {}, rec = rec }
                a.byHealer[who] = h
                a.healerOrder[#a.healerOrder + 1] = who
            end
            h.eff, h.over, h.count = h.eff + eff, h.over + over, h.count + 1
            local sp = rec.sname or "Heal"
            if not h.spells[sp] then
                h.spells[sp] = { sid = rec.sid, count = 0 }
                h.spellOrder[#h.spellOrder + 1] = sp
            end
            h.spells[sp].count = h.spells[sp].count + 1
        elseif rec.cat == "auras" and dt <= SHED_WINDOW
            and (rec.sub == "SPELL_AURA_REMOVED" or rec.sub == "SPELL_AURA_REMOVED_DOSE") then
            -- the shed: everything drops at once when you die
            local list = (rec.aura == "DEBUFF") and a.shedDebuffs or a.shedBuffs
            list[#list + 1] = rec
            a.shedIdx[idx] = true
        end
    end
    table.sort(a.sourceOrder, function(x, y) return a.bySource[x].total > a.bySource[y].total end)
    table.sort(a.healerOrder, function(x, y) return a.byHealer[x].eff > a.byHealer[y].eff end)
    for _, who in ipairs(a.sourceOrder) do
        local src = a.bySource[who]
        table.sort(src.spellOrder, function(x, y) return src.spells[x].total > src.spells[y].total end)
    end
    -- burst: the last five seconds carried most of it. Nobody heals through
    -- that; the conversation is about the mechanic, not the healers.
    a.burst = a.totalDmg > 0 and (a.burstDmg / a.totalDmg) >= 0.6
    return a
end

local function auraNames(list, max)
    local names = {}
    for _, rec in ipairs(list) do names[#names + 1] = rec.sname or "?" end
    table.sort(names)
    if #names > max then
        local shown = {}
        for k = 1, max do shown[k] = names[k] end
        return table.concat(shown, ", ") .. ", +" .. (#names - max) .. " more"
    end
    return table.concat(names, ", ")
end

-- The timeline with the noise folded: the death-shed as one line, and a run
-- of the same source landing the same spell with nothing else in between as
-- one row with a count and a time range. A boss swings every two seconds, so
-- a time-based window would never have caught the thing that fills a recap.
-- The killing blow is never folded into anything: it is the line the eye
-- lands on, and it has to be there.
local function condensedTimeline(death, a)
    local rows = {}
    local prev
    for idx, rec in ipairs(death.events) do
        if not a.shedIdx[idx] then
            local mergeable = (rec.cat == "damage" or rec.cat == "healing" or rec.cat == "misses")
                and rec ~= a.killer
            if mergeable and prev and prev.mergeable and prev.rec.cat == rec.cat
                and prev.rec.sn == rec.sn
                and (prev.rec.sname or prev.rec.env) == (rec.sname or rec.env) then
                prev.count = prev.count + 1
                prev.total = prev.total + (rec.amt or 0)
                prev.over = prev.over + (rec.over or 0)
                prev.crit = prev.crit or rec.crit
                prev.lastT = rec.t or prev.lastT
                prev.lastRec = rec
            else
                prev = { rec = rec, count = 1, total = rec.amt or 0, over = rec.over or 0,
                         crit = rec.crit, firstT = rec.t or 0, lastT = rec.t or 0,
                         lastRec = rec, mergeable = mergeable }
                rows[#rows + 1] = prev
            end
        end
    end
    return rows
end

-- A condensed row is drawn as its LAST event with the summed amount, so the
-- timestamp is when the run ended and the number is what it added up to.
local function condensedRow(row)
    if row.count == 1 then return recapRow(row.rec) end
    local rec = {}
    for k, v in pairs(row.lastRec) do rec[k] = v end
    rec.amt, rec.over, rec.crit = row.total, row.over, row.crit
    rec.absorbed, rec.resisted, rec.blocked = nil, nil, nil
    local body = recapRow(rec)
    -- the count goes after the spell, before the amount, where it reads
    local mark = C(" \195\151" .. row.count, NS.COLORS.dim)    -- ×N
    local cut = body:find("  [%-%+]", 1) or body:find("  |c%x%x%x%x%x%x%x%x[%-%+]", 1)
    if cut then return body:sub(1, cut - 1) .. mark .. body:sub(cut) end
    return body .. mark
end

local function pct(part, whole)
    if not whole or whole <= 0 then return "" end
    return C("  " .. math.floor(part / whole * 100 + 0.5) .. "%", NS.COLORS.dim)
end

local function recapLines(death)
    local lines = {}
    local head = string.format(NS.SKULL_ICON, 16) .. " "
    if death.keep then
        -- saved recaps read in gold, under whatever you named them
        head = head .. C(death.title or death.name, NS.COLORS.accent)
        if death.title then head = head .. C("   (" .. death.name .. ")", NS.COLORS.dim) end
    else
        head = head .. C(death.name, NS.COLORS.death)
    end
    lines[#lines + 1] = head ..
        C("  " .. date("%b %d %H:%M:%S", death.t), NS.COLORS.timestamp) ..
        (death.feign and C("  (probably Feign Death)", NS.COLORS.dim) or "") ..
        (death.fromLastSession and C("  (earlier session)", NS.COLORS.dim) or "")

    if #death.events == 0 then
        lines[#lines + 1] = " "
        lines[#lines + 1] = C("No tracked events before this death.", NS.COLORS.dim)
        return lines
    end

    local a = analyse(death)
    local dim, txt = NS.COLORS.dim, NS.COLORS.text

    -- the real span this timeline covers, not the configured window
    local span = NS.db.deathRecap.seconds
    local first = death.events[1]
    if first and first.t and death.t and death.t > first.t then
        span = math.floor(death.t - first.t + 0.5)
    end
    local spanText = span >= 60
        and string.format("%d:%02d", math.floor(span / 60), span % 60)
        or (span .. "s")
    lines[#lines + 1] = C("Last " .. spanText .. ":  ", dim) ..
        C(NS.FormatNumber(a.totalDmg) .. " taken", "ff8080") ..
        C("   " .. NS.FormatNumber(a.totalHeal) .. " healed", NS.COLORS.heal) ..
        (a.totalAbsorb > 0 and C("   " .. NS.FormatNumber(a.totalAbsorb) .. " absorbed", "9ad0ff") or "") ..
        C("   " .. #death.events .. " events", dim)
    lines[#lines + 1] = " "

    -- VERDICT -----------------------------------------------------------------
    if a.killer then
        local k = a.killer
        lines[#lines + 1] = C("Killing blow   ", dim) .. actorToken(k) .. RECAP_SEP ..
            spellLink(k.sid, k.sname or k.env, "ffd8a0") .. "  " ..
            C("-" .. NS.FormatNumber(k.amt or 0), "ff7a7a") ..
            (k.crit and C(" crit", NS.COLORS.crit) or "") ..
            ((k.over or 0) > 0 and C("  (" .. NS.FormatNumber(k.over) .. " overkill)", dim) or "")
    end
    if a.biggestRec and a.biggestRec ~= a.killer then
        local b = a.biggestRec
        lines[#lines + 1] = C("Biggest hit    ", dim) .. actorToken(b) .. RECAP_SEP ..
            spellLink(b.sid, b.sname or b.env, "ffd8a0") .. "  " ..
            C("-" .. NS.FormatNumber(a.biggest), "ff7a7a") ..
            (b.crit and C(" crit", NS.COLORS.crit) or "")
    end
    if a.totalDmg > 0 then
        lines[#lines + 1] = C("Last 5 seconds ", dim) ..
            C(NS.FormatNumber(a.burstDmg) .. " taken", "ff8080") ..
            C("  \194\183  " .. NS.FormatNumber(a.burstHeal) .. " healed", NS.COLORS.heal) ..
            (a.burstAbsorb > 0 and C("  \194\183  " .. NS.FormatNumber(a.burstAbsorb) .. " absorbed", "9ad0ff") or "") ..
            C("   \226\134\146 " .. (a.burst and "burst" or "sustained"), a.burst and NS.COLORS.crit or dim)
    end
    if #a.shedDebuffs > 0 then
        lines[#lines + 1] = C("Died with      ", dim) ..
            C(auraNames(a.shedDebuffs, 6), NS.COLORS.debuff)
    end
    if #a.shedBuffs > 0 then
        lines[#lines + 1] = C("Lost " .. #a.shedBuffs .. " buff" .. (#a.shedBuffs == 1 and "" or "s") ..
            "  ", dim) .. C(auraNames(a.shedBuffs, 3), dim)
    end

    -- DAMAGE TAKEN -------------------------------------------------------------
    if #a.sourceOrder > 0 then
        lines[#lines + 1] = " "
        lines[#lines + 1] = C("Damage taken", NS.COLORS.accent)
        local shownSources = 0
        local srcCap = (#a.sourceOrder > 7) and 6 or #a.sourceOrder
        for _, who in ipairs(a.sourceOrder) do
            shownSources = shownSources + 1
            if shownSources > srcCap then
                lines[#lines + 1] = C("   +" .. (#a.sourceOrder - srcCap) .. " more sources", dim)
                break
            end
            local src = a.bySource[who]
            local nameTok = src.rec.sn and actorToken(src.rec) or C(who, NS.COLORS.neutral)
            lines[#lines + 1] = "   " .. nameTok .. "  " ..
                C(NS.FormatNumber(src.total), "ff8080") .. pct(src.total, a.totalDmg)
            local shownSpells = 0
            local cap = (#src.spellOrder > 6) and 5 or #src.spellOrder
            for _, sp in ipairs(src.spellOrder) do
                shownSpells = shownSpells + 1
                if shownSpells > cap then
                    lines[#lines + 1] = C("        +" .. (#src.spellOrder - cap) .. " more", dim)
                    break
                end
                local e = src.spells[sp]
                lines[#lines + 1] = "        " .. spellLink(e.sid, e.name, "e8c9a0") ..
                    (e.count > 1 and C(" \195\151" .. e.count, dim) or "") .. "  " ..
                    C(NS.FormatNumber(e.total), "ff8080") .. pct(e.total, a.totalDmg)
            end
        end
    end

    -- HEALING RECEIVED ---------------------------------------------------------
    lines[#lines + 1] = " "
    lines[#lines + 1] = C("Healing received", NS.COLORS.accent)
    if #a.healerOrder == 0 then
        lines[#lines + 1] = C("   none", dim)
    else
        for _, who in ipairs(a.healerOrder) do
            local h = a.byHealer[who]
            local spells = {}
            for _, sp in ipairs(h.spellOrder) do
                local e = h.spells[sp]
                spells[#spells + 1] = spellLink(e.sid, sp, NS.COLORS.heal) ..
                    (e.count > 1 and C(" \195\151" .. e.count, dim) or "")
            end
            lines[#lines + 1] = "   " .. actorToken(h.rec) .. "  " ..
                C("+" .. NS.FormatNumber(h.eff), NS.COLORS.heal) ..
                (h.over > 0 and C("  (" .. NS.FormatNumber(h.over) .. " over)", dim) or "") ..
                "   " .. table.concat(spells, C(", ", dim))
        end
    end

    -- what the corpse dropped, filled in when you loot it
    if death.loot and #death.loot > 0 then
        lines[#lines + 1] = " "
        lines[#lines + 1] = C("Dropped", NS.COLORS.accent)
        for _, it in ipairs(death.loot) do
            local body
            if it.money then
                body = C(it.name or "money", "ffd700")
            elseif it.link then
                body = it.link
            else
                body = C(it.name or "?", ITEM_QUALITY_HEX[it.quality or 1] or "ffffff")
            end
            if (it.count or 1) > 1 then
                body = body .. C(" x" .. it.count, dim)
            end
            lines[#lines + 1] = "   " .. body
        end
    end

    -- TIMELINE, condensed ------------------------------------------------------
    lines[#lines + 1] = " "
    lines[#lines + 1] = C("Timeline", NS.COLORS.accent)
    for _, row in ipairs(condensedTimeline(death, a)) do
        local ts
        if row.count > 1 and row.lastT - row.firstT >= 0.5 then
            ts = C(string.format("%+.1f\226\128\166%+.1fs", row.firstT - death.t, row.lastT - death.t),
                NS.COLORS.timestamp)
        else
            ts = C(string.format("%+.1fs", row.lastT - death.t), NS.COLORS.timestamp)
        end
        lines[#lines + 1] = ts .. "  " .. condensedRow(row)
    end
    local shed = #a.shedBuffs + #a.shedDebuffs
    if shed > 0 then
        lines[#lines + 1] = C(string.format("%+.1fs", 0), NS.COLORS.timestamp) .. "  " ..
            C("lost " .. shed .. " aura" .. (shed == 1 and "" or "s") .. ": ", dim) ..
            C(auraNames(a.shedDebuffs, 20), NS.COLORS.debuff) ..
            ((#a.shedDebuffs > 0 and #a.shedBuffs > 0) and C(", ", dim) or "") ..
            C(auraNames(a.shedBuffs, 20), dim)
    end
    return lines
end


local function updateDetailButtons()
    if not frame or not frame.saveBtn then return end
    local d = currentDeath
    frame.saveBtn:SetShown(d ~= nil)
    frame.nameBtn:SetShown(d ~= nil)
    if not d then return end
    frame.saveBtn.text:SetFont(NS.CurrentFont(), 11, "")
    frame.nameBtn.text:SetFont(NS.CurrentFont(), 11, "")
    frame.saveBtn.text:SetText(d.keep and C("Saved *", NS.COLORS.accent)
        or C("Save recap", NS.COLORS.text))
    frame.nameBtn.text:SetText(C(d.title and "Rename" or "Name it", NS.COLORS.text))
end

local function renderDetail(death)
    currentDeath = death
    detailText:Clear()
    if not death then
        detailText:AddMessage(C("Select a death on the left.", NS.COLORS.dim))
        updateDetailButtons()
        return
    end
    for _, line in ipairs(NS.FightLogLines(death, currentMode)) do
        detailText:AddMessage(line)
    end
    updateDetailButtons()
    if NS.RefreshFightLogPopout then NS.RefreshFightLogPopout(death) end
end

function NS.SetFightMode(mode)
    currentMode = mode or "killed"
    if currentDeath then renderDetail(currentDeath) end
    if frame and frame.modeButtons then
        for _, b in ipairs(frame.modeButtons) do
            b.text:SetText(b.mode == currentMode
                and C(b.label, NS.COLORS.accent) or C(b.label, NS.COLORS.dim))
        end
    end
end

function NS.FightMode() return currentMode end

-- One row of a fight log, in the recap's own shape: who, what, how much. Uses
-- the combat log's renderer for anything the recap has no compact form for, so
-- interrupts, dispels and casts still read properly.
-- Rows are the expensive part: a 25-man boss fight in "Everyone" is tens of
-- thousands of events, and building them all to display the last few hundred
-- was a three-quarter-second freeze on every click. Render the tail, and say
-- what was left off.
local FIGHT_LOG_ROWS = 400
local POPOUT_LOG_ROWS = 2000

local function fightLogLines(death, mode, recs, maxRows)
    maxRows = maxRows or FIGHT_LOG_ROWS
    local lines = {}
    local head = string.format(NS.SKULL_ICON, 16) .. " "
    local modeLabel = mode
    for _, m in ipairs(NS.FIGHT_MODES) do
        if m.key == mode then modeLabel = m.label break end
    end
    lines[#lines + 1] = head .. C(death.title or death.name, NS.COLORS.accent) ..
        C("  " .. modeLabel, NS.COLORS.dim) ..
        C("  " .. date("%b %d %H:%M:%S", death.t), NS.COLORS.timestamp)

    local from = fightWindow(death)
    local span = math.max(0, math.floor(death.t - from + 0.5))
    local spanText = span >= 60
        and string.format("%d:%02d", math.floor(span / 60), span % 60)
        or (span .. "s")
    lines[#lines + 1] = C("Fight length " .. spanText, NS.COLORS.dim) ..
        C("   " .. #recs .. " event" .. (#recs == 1 and "" or "s"), NS.COLORS.dim)
    if recs.clipped then
        lines[#lines + 1] = C("The event buffer only reaches back part of this fight" ..
            " - the first " .. math.floor(recs.clipped) .. "s are missing.", NS.COLORS.death)
    end

    local first = 1
    if #recs > maxRows then
        first = #recs - maxRows + 1
        lines[#lines + 1] = C("Showing the last " .. maxRows .. " of " .. #recs ..
            ". Pop the log out for more.", NS.COLORS.dim)
    end
    lines[#lines + 1] = " "

    if #recs == 0 then
        lines[#lines + 1] = C("Nothing matched this view.", NS.COLORS.dim)
        return lines
    end

    for idx = first, #recs do
        local rec = recs[idx]
        local dt = rec.t - death.t
        local ts = C(string.format("%+.1fs", dt), NS.COLORS.timestamp)
        local body
        if rec.cat == "damage" or rec.cat == "healing"
            or rec.cat == "misses" or rec.cat == "auras" then
            body = recapRow(rec)
        else
            NS.FormatRecord(rec)
            -- FormatRecord prefixes its own timestamp; the timeline supplies a
            -- relative one, so strip it rather than showing both
            local text = rec.line
            local okT, stamp = pcall(NS.FormatTime, rec)
            if okT and stamp and stamp ~= "" and text:sub(1, #stamp) == stamp then
                text = text:sub(#stamp + 1)
            end
            body = text
        end
        lines[#lines + 1] = ts .. "  " .. body
    end
    return lines
end

-- The lines for whatever the browser is currently showing.
function NS.FightLogLines(death, mode, maxRows)
    if not death then return {} end
    local recs = (mode and mode ~= "killed") and NS.FightLogFor(death, mode) or nil
    if not recs then
        local lines = recapLines(death)
        if mode and mode ~= "killed" then
            table.insert(lines, 2, C(
                "That view needs the live event buffer, which no longer covers this" ..
                " fight. Showing what killed them instead.", NS.COLORS.death))
        end
        return lines
    end
    return fightLogLines(death, mode, recs, maxRows)
end

-- The same timeline as plain text, for the copy box.
function NS.DeathRecapText(death, mode)
    if not death then return "" end
    local out = {}
    for _, line in ipairs(NS.FightLogLines(death, mode or currentMode)) do
        out[#out + 1] = NS.StripEscapes(line)
    end
    return table.concat(out, "\n")
end

-- How many rows fit is a property of the pane, not a number typed here. It was
-- a constant, which meant the window could only ever be one size and any change
-- to its height either wasted space or drew rows off the bottom where their
-- death could never be clicked.
local ROW_PITCH = 19
local ROW_TOP_INSET = 4
local listOffset = 0

local function rowCapacity()
    local h = frame and frame.listPane and frame.listPane:GetHeight() or 0
    if not h or h <= 0 then h = 404 end
    return math.max(1, math.floor((h - ROW_TOP_INSET) / ROW_PITCH))
end

local function renderList()
    for _, b in ipairs(listButtons) do b:Hide() end
    local rows = rowCapacity()
    local total = #NS.deaths
    local maxOffset = math.max(0, total - rows)
    if listOffset > maxOffset then listOffset = maxOffset end
    if listOffset < 0 then listOffset = 0 end

    local shown = 0
    for i = total - listOffset, 1, -1 do
        if shown >= rows then break end
        shown = shown + 1
        local death = NS.deaths[i]
        local b = listButtons[shown]
        if not b then
            b = CreateFrame("Button", nil, frame.listPane)
            b:SetHeight(18)
            b:SetPoint("TOPLEFT", 4, -ROW_TOP_INSET - (shown - 1) * ROW_PITCH)
            b:SetPoint("TOPRIGHT", -4, -ROW_TOP_INSET - (shown - 1) * ROW_PITCH)
            b.text = b:CreateFontString(nil, "OVERLAY")
            -- Anchored on one side only, a FontString renders at its natural
            -- width - so a long row ran straight out of the list and over the
            -- timeline beside it. Pin both edges and stop it wrapping, and the
            -- client truncates it to fit instead.
            b.text:SetPoint("LEFT", 4, 0)
            b.text:SetPoint("RIGHT", -4, 0)
            b.text:SetJustifyH("LEFT")
            if b.text.SetWordWrap then b.text:SetWordWrap(false) end
            b.hl = b:CreateTexture(nil, "HIGHLIGHT")
            b.hl:SetAllPoints()
            b.hl:SetColorTexture(1, 0.3, 0.3, 0.08)
            b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            listButtons[shown] = b
        end
        b.text:SetFont(NS.CurrentFont(), 11, "")
        local stamp = death.fromLastSession and date("%m/%d %H:%M", death.t)
            or date("%H:%M:%S", death.t)
        -- saved recaps stand out in gold and show the name you gave them
        local label = death.keep and (death.title or death.name) or death.name
        local hex = death.keep and NS.COLORS.accent
            or (death.feign and NS.COLORS.dim or NS.COLORS.text)
        -- "who killed them" is the one thing you scan this list for
        local killer = NS.DeathKiller(death)
        -- "Illidari Shadowlord" is longer than the row; the full name is on the
        -- timeline, this is just enough to tell two rows apart
        if killer and #killer > 16 then killer = killer:sub(1, 15) .. "\226\128\166" end
        b.text:SetText(C(stamp, NS.COLORS.timestamp) .. " " ..
            (death.keep and C("* ", NS.COLORS.accent) or "") ..
            C(label, hex) ..
            (killer and C("  by " .. killer, NS.COLORS.dim) or "") ..
            (death.loot and C(" +", NS.COLORS.pet) or ""))
        b.death = death
        b:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                NS.DeathRecapMenu(self.death)
            else
                renderDetail(self.death)
            end
        end)
        b:Show()
    end
    if shown == 0 then
        renderDetail(nil)
    end
    if frame and frame.countText then
        local _, kept = NS.DeathHistoryCounts()
        local savedNote = kept > 0 and C("   " .. kept .. " saved", NS.COLORS.accent) or ""
        local base
        if total > rows then
            base = string.format("%d-%d of %d",
                math.max(total - listOffset - shown + 1, 1), total - listOffset, total)
        else
            base = total .. (total == 1 and " death" or " deaths")
        end
        frame.countText:SetText(C(base, NS.COLORS.dim) .. savedNote ..
            C("   right-click a row for options  \194\183  wheel to scroll either side",
              NS.COLORS.dim))
    end
end

function NS.DeathRecapMenu(death)
    if not death then return end
    local total, kept = NS.DeathHistoryCounts()
    local limit = NS.db.deathRecap.keepHistory or 40
    local items = {
        { text = NS.DeathLabel(death), header = true },
        { text = death.keep and "Unsave (let it roll off again)" or "Save this recap",
          checked = death.keep,
          func = function() NS.SetDeathKept(death, not death.keep) end },
        { text = death.title and "Rename it" or "Give it a name",
          func = function()
            NS.ShowInputBox("Name for this recap", death.title or death.name, function(txt)
                NS.RenameDeath(death, txt)
            end)
        end },
        { separator = true },
        -- the menu acts on the row you right-clicked, so copy that row's recap
        -- rather than whatever view happens to be open on another death
        { text = "Copy what killed them", func = function()
            NS.ShowCopyText("Recap: " .. NS.DeathLabel(death),
                NS.DeathRecapText(death, "killed"))
        end },
        { text = "Delete this recap", func = function() NS.DeleteDeath(death) end },
        { text = kept .. " of " .. limit .. " slots saved, " ..
            math.max(limit - kept, 0) .. " rolling", disabled = true },
    }
    NS.ShowMenu(items)
end

-- Re-draw after loot lands on a death that is already on screen.
function NS.RefreshDeathBrowser(death)
    if not frame or not frame:IsShown() then return end
    renderList()
    if death and currentDeath == death then renderDetail(death) end
end

-- The open recap may be showing a death that just got cleared out.
function NS.ClearDeathSelection()
    currentDeath = nil
    if detailText then renderDetail(nil) end
end

local function ensureFrame()
    if frame then return end
    frame = CreateFrame("Frame", "LogLoversDeaths", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    local saved = NS.db.deathSize
    frame:SetSize(math.max(640, (saved and saved.w) or 760),
                  math.max(420, (saved and saved.h) or 500))
    local pos = NS.db.deathPos
    if type(pos) == "table" and pos[1] then
        frame:SetPoint(pos[1], UIParent, pos[1], pos[2] or 0, pos[3] or 0)
    else
        frame:SetPoint("CENTER")
    end
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        if point then
            NS.db.deathPos = { point, math.floor(x + 0.5), math.floor(y + 0.5) }
        end
    end)
    frame:SetClampedToScreen(true)
    NS.SkinPanel(frame, { r = 0.055, g = 0.043, b = 0.028, a = 0.97 })
    tinsert(UISpecialFrames, "LogLoversDeaths")

    local title = frame:CreateFontString(nil, "OVERLAY")
    title:SetFont(NS.CurrentFont(), 14, "")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText(C("Death Recaps", NS.COLORS.accent))

    local close = NS.MakeIconButton(frame, "Interface\\Buttons\\UI-StopButton", nil,
        function() frame:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)

    -- save / rename act on whatever is open on the right
    frame.saveBtn = CreateFrame("Button", nil, frame,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    NS.SkinPanel(frame.saveBtn, { r = 0.16, g = 0.11, b = 0.05, a = 0.92 },
        { r = 0.52, g = 0.37, b = 0.14, a = 0.95 })
    frame.saveBtn:SetSize(96, 18)
    frame.saveBtn:SetPoint("TOPRIGHT", close, "TOPLEFT", -8, -1)
    frame.saveBtn.text = frame.saveBtn:CreateFontString(nil, "OVERLAY")
    frame.saveBtn.text:SetPoint("CENTER")
    frame.saveBtn.hl = frame.saveBtn:CreateTexture(nil, "HIGHLIGHT")
    frame.saveBtn.hl:SetAllPoints()
    frame.saveBtn.hl:SetColorTexture(NS.ACCENT.r, NS.ACCENT.g, NS.ACCENT.b, 0.10)
    frame.saveBtn:SetScript("OnClick", function()
        local d = currentDeath
        if d then NS.SetDeathKept(d, not d.keep) end
    end)

    frame.nameBtn = CreateFrame("Button", nil, frame,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    NS.SkinPanel(frame.nameBtn, { r = 0.16, g = 0.11, b = 0.05, a = 0.92 },
        { r = 0.52, g = 0.37, b = 0.14, a = 0.95 })
    frame.nameBtn:SetSize(72, 18)
    frame.nameBtn:SetPoint("TOPRIGHT", frame.saveBtn, "TOPLEFT", -6, 0)
    frame.nameBtn.text = frame.nameBtn:CreateFontString(nil, "OVERLAY")
    frame.nameBtn.text:SetPoint("CENTER")
    frame.nameBtn.hl = frame.nameBtn:CreateTexture(nil, "HIGHLIGHT")
    frame.nameBtn.hl:SetAllPoints()
    frame.nameBtn.hl:SetColorTexture(NS.ACCENT.r, NS.ACCENT.g, NS.ACCENT.b, 0.10)
    frame.nameBtn:SetScript("OnClick", function()
        -- capture the selection now: the popup is not modal, so the user can
        -- click another row before typing a name
        local d = currentDeath
        if not d then return end
        NS.ShowInputBox("Name for this recap", d.title or d.name, function(txt)
            NS.RenameDeath(d, txt)
        end)
    end)

    frame.countText = frame:CreateFontString(nil, "OVERLAY")
    frame.countText:SetFont(NS.CurrentFont(), 10, "")
    frame.countText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 2, -2)
    frame.countText:SetJustifyH("LEFT")

    frame.listPane = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    NS.SkinPanel(frame.listPane, { r = 0, g = 0, b = 0, a = 0.35 })
    frame.listPane:SetPoint("TOPLEFT", 10, -46)
    frame.listPane:SetPoint("BOTTOMLEFT", 10, 22)
    frame.listPane:SetWidth(250)
    -- belt and braces: nothing inside the list can paint outside it, whatever
    -- a row's text does
    if frame.listPane.SetClipsChildren then frame.listPane:SetClipsChildren(true) end
    frame.listPane:EnableMouseWheel(true)
    frame.listPane:SetScript("OnMouseWheel", function(_, delta)
        -- newest is at the top, so scrolling down walks back through history
        listOffset = listOffset + (delta > 0 and -3 or 3)
        renderList()
    end)

    -- The three views. They are the same two axes the combat windows use -
    -- who, and which direction - so what you learn here transfers.
    frame.modeRow = CreateFrame("Frame", nil, frame)
    frame.modeRow:SetPoint("TOPLEFT", frame.listPane, "TOPRIGHT", 10, -2)
    frame.modeRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -46)
    frame.modeRow:SetHeight(20)
    frame.modeButtons = {}
    local prev
    for _, m in ipairs(NS.FIGHT_MODES) do
        local b = CreateFrame("Button", nil, frame.modeRow)
        b:SetHeight(18)
        b.mode, b.label = m.key, m.label
        b.text = b:CreateFontString(nil, "OVERLAY")
        b.text:SetFont(NS.CurrentFont(), 11, "")
        b.text:SetPoint("LEFT", 6, 0)
        b.text:SetText(C(m.label, NS.COLORS.dim))
        b:SetWidth((b.text:GetStringWidth() or 60) + 14)
        b.hl = b:CreateTexture(nil, "HIGHLIGHT")
        b.hl:SetAllPoints()
        b.hl:SetColorTexture(NS.ACCENT.r, NS.ACCENT.g, NS.ACCENT.b, 0.10)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        else b:SetPoint("LEFT", 0, 0) end
        b:SetScript("OnClick", function() NS.SetFightMode(b.mode) end)
        frame.modeButtons[#frame.modeButtons + 1] = b
        prev = b
    end

    frame.popBtn = CreateFrame("Button", nil, frame.modeRow,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    NS.SkinPanel(frame.popBtn, { r = 0.16, g = 0.11, b = 0.05, a = 0.92 },
        { r = 0.52, g = 0.37, b = 0.14, a = 0.95 })
    frame.popBtn:SetSize(70, 18)
    frame.popBtn:SetPoint("RIGHT", 0, 0)
    frame.popBtn.text = frame.popBtn:CreateFontString(nil, "OVERLAY")
    frame.popBtn.text:SetFont(NS.CurrentFont(), 11, "")
    frame.popBtn.text:SetPoint("CENTER")
    frame.popBtn.text:SetText(C("Pop out", NS.COLORS.accent))
    frame.popBtn.hl = frame.popBtn:CreateTexture(nil, "HIGHLIGHT")
    frame.popBtn.hl:SetAllPoints()
    frame.popBtn.hl:SetColorTexture(NS.ACCENT.r, NS.ACCENT.g, NS.ACCENT.b, 0.10)
    frame.popBtn:SetScript("OnClick", function()
        if currentDeath then NS.PopOutFightLog(currentDeath, currentMode) end
    end)

    -- a message frame (not a FontString) so spell links are hoverable
    detailText = CreateFrame("ScrollingMessageFrame", nil, frame)
    detailText:SetPoint("TOPLEFT", frame.modeRow, "BOTTOMLEFT", 0, -4)
    -- clear of the resize grip in the corner, or the last line sits under it
    detailText:SetPoint("BOTTOMRIGHT", -10, 22)
    detailText:SetFont(NS.CurrentFont(), 11, "")
    detailText:SetJustifyH("LEFT")
    detailText:SetFading(false)
    detailText:SetMaxLines(FIGHT_LOG_ROWS + 40)
    detailText:SetInsertMode(SCROLLING_MESSAGE_FRAME_INSERT_MODE_BOTTOM or "BOTTOM")
    if detailText.SetIndentedWordWrap then detailText:SetIndentedWordWrap(true) end
    detailText:SetSpacing(3)
    detailText:SetHyperlinksEnabled(true)
    detailText:EnableMouse(true)
    detailText:EnableMouseWheel(true)
    detailText:SetScript("OnMouseWheel", function(self, delta)
        for _ = 1, 3 do
            if delta > 0 then self:ScrollUp() else self:ScrollDown() end
        end
    end)
    detailText:SetScript("OnHyperlinkEnter", function(self, link)
        NS.HandleLinkEnter(self, link)
    end)
    detailText:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)

    -- Drag it bigger. The list pane grows with the window up to a point, so
    -- long names get more room, and the timeline keeps whatever is left.
    frame:SetResizable(true)
    NS.SetResizeLimits(frame, 640, 420, 1600, 1200)
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        NS.db.deathSize = {
            w = math.floor(frame:GetWidth() + 0.5),
            h = math.floor(frame:GetHeight() + 0.5),
        }
    end)

    frame:SetScript("OnSizeChanged", function(self)
        -- a third of the width for the list, within sane bounds, so neither
        -- pane can be squeezed into uselessness
        local w = self:GetWidth() or 760
        frame.listPane:SetWidth(math.max(230, math.min(420, w * 0.34)))
        -- the number of rows that fit has changed with the height
        renderList()
    end)
    detailText:SetScript("OnHyperlinkClick", function(self, link, text, button)
        local id = link:match("^spell:(%d+)")
        if id then
            if IsShiftKeyDown() then
                local slink = NS.GetSpellLink(tonumber(id))
                if slink and ChatEdit_InsertLink then ChatEdit_InsertLink(slink) end
            else
                NS.OpenSpellInspector(tonumber(id), text and text:match("|h(.-)|h") or "?")
            end
            return
        end
        if link:match("^item:") then
            -- loot links behave exactly as they do in chat
            if IsShiftKeyDown() and ChatEdit_InsertLink then
                ChatEdit_InsertLink(text or link)
            elseif SetItemRef then
                pcall(SetItemRef, link, text, button, self)
            end
        end
    end)

    -- gives the save/name buttons their font and hides them until something is
    -- selected, instead of two blank boxes on first open
    updateDetailButtons()

    frame:Hide()
end

-- test hook: the list pane itself, so a test can resize it
function NS.DeathListPane() return frame and frame.listPane end

-- test hook: is row i actually on screen?
function NS.DeathListRowShown(i)
    local b = listButtons and listButtons[i]
    return b and b:IsShown() and true or false
end

-- test hook: how many rows the list currently has room for
function NS.DeathListCapacity() return rowCapacity() end

-- test hook: the label on a death list row, so a layout regression that lets it
-- spill over the timeline beside it is catchable
function NS.DeathListRowLabel(i)
    local b = listButtons and listButtons[i or 1]
    return b and b.text
end

-------------------------------------------------------------------------------
-- Pop-out fight log
--
-- A raid fight in "Everyone" runs to thousands of lines, which is not something
-- to read in half a window. This is the same content in its own resizable,
-- movable frame, with its own view switcher.
-------------------------------------------------------------------------------
local popFrame
local popDeath, popMode

local function popRender()
    if not popFrame or not popFrame:IsShown() or not popDeath then return end
    popFrame.text:Clear()
    for _, line in ipairs(NS.FightLogLines(popDeath, popMode, POPOUT_LOG_ROWS)) do
        popFrame.text:AddMessage(line)
    end
    for _, b in ipairs(popFrame.modeButtons) do
        b.text:SetText(b.mode == popMode
            and C(b.label, NS.COLORS.accent) or C(b.label, NS.COLORS.dim))
    end
    popFrame.title:SetText(C(popDeath.title or popDeath.name, NS.COLORS.accent))

    -- Buttons for whatever else in the family can act on this fight - a threat
    -- replay, a meter view. LogLovers does not know what these are; they are
    -- registered through LogLoversAPI.RegisterProvider.
    -- the fight as the API publishes it, so a provider can hand the id straight
    -- back to LogLoversAPI and get the same fight
    local seg
    for _, sg in ipairs(NS.segments or {}) do
        if sg.index == popDeath.segIndex then seg = sg break end
    end
    local fight = {
        id = seg and seg.id,
        startStamp = seg and seg.startStamp or popDeath.t,
        index = popDeath.segIndex,
        label = seg and NS.SegmentLabel(seg) or popDeath.name,
        death = popDeath,
    }
    local API = _G.LogLoversAPI
    local list = (API and API.ProvidersFor) and API.ProvidersFor(fight) or {}
    popFrame.providerButtons = popFrame.providerButtons or {}
    for _, b in ipairs(popFrame.providerButtons) do b:Hide() end
    local prev
    for i, p in ipairs(list) do
        local b = popFrame.providerButtons[i]
        if not b then
            b = CreateFrame("Button", nil, popFrame,
                BackdropTemplateMixin and "BackdropTemplate" or nil)
            NS.SkinPanel(b, { r = 0.16, g = 0.11, b = 0.05, a = 0.92 },
                { r = 0.52, g = 0.37, b = 0.14, a = 0.95 })
            b:SetHeight(18)
            b.text = b:CreateFontString(nil, "OVERLAY")
            b.text:SetFont(NS.CurrentFont(), 11, "")
            b.text:SetPoint("CENTER")
            b.hl = b:CreateTexture(nil, "HIGHLIGHT")
            b.hl:SetAllPoints()
            b.hl:SetColorTexture(NS.ACCENT.r, NS.ACCENT.g, NS.ACCENT.b, 0.10)
            popFrame.providerButtons[i] = b
        end
        b.text:SetText(C(p.label or p.key, NS.COLORS.accent))
        b:SetWidth((b.text:GetStringWidth() or 70) + 20)
        b:ClearAllPoints()
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0)
        else b:SetPoint("BOTTOMLEFT", 10, 4) end
        b:SetScript("OnClick", function()
            local ok, err = pcall(p.show, fight)
            if not ok then
                NS.Print((p.label or p.key) .. " failed: " .. tostring(err))
            end
        end)
        b:Show()
        prev = b
    end
end

-- Keeps the pop-out in step when the browser changes selection. It used to
-- re-render its own unchanged content instead, which doubled the cost of every
-- click in the browser for no visible effect.
function NS.RefreshFightLogPopout(death)
    if not (popFrame and popFrame:IsShown()) then return end
    if death and death ~= popDeath then popDeath = death end
    if popDeath then popRender() end
end

function NS.PopOutFightLog(death, mode)
    if not death then return false end
    popDeath, popMode = death, mode or "all"
    if not popFrame then
        popFrame = CreateFrame("Frame", "LogLoversFightLog", UIParent,
            BackdropTemplateMixin and "BackdropTemplate" or nil)
        local saved = NS.db.fightLogSize
        popFrame:SetSize(math.max(520, (saved and saved.w) or 820),
                         math.max(300, (saved and saved.h) or 520))
        local pos = NS.db.fightLogPos
        if type(pos) == "table" and pos[1] then
            popFrame:SetPoint(pos[1], UIParent, pos[1], pos[2] or 0, pos[3] or 0)
        else
            popFrame:SetPoint("CENTER", 60, -40)
        end
        popFrame:SetFrameStrata("DIALOG")
        popFrame:SetMovable(true)
        popFrame:EnableMouse(true)
        popFrame:RegisterForDrag("LeftButton")
        popFrame:SetScript("OnDragStart", popFrame.StartMoving)
        popFrame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local point, _, _, x, y = self:GetPoint()
            if point then
                NS.db.fightLogPos = { point, math.floor(x + 0.5), math.floor(y + 0.5) }
            end
        end)
        popFrame:SetClampedToScreen(true)
        NS.SkinPanel(popFrame, { r = 0.055, g = 0.043, b = 0.028, a = 0.97 })
        tinsert(UISpecialFrames, "LogLoversFightLog")

        popFrame.title = popFrame:CreateFontString(nil, "OVERLAY")
        popFrame.title:SetFont(NS.CurrentFont(), 14, "")
        popFrame.title:SetPoint("TOPLEFT", 12, -10)

        local close = NS.MakeIconButton(popFrame, "Interface\\Buttons\\UI-StopButton", nil,
            function() popFrame:Hide() end)
        close:SetPoint("TOPRIGHT", -8, -8)

        local copy = NS.MakeIconButton(popFrame, "Interface\\Buttons\\UI-GuildButton-PublicNote-Up",
            "Copy this log", function()
                local label = popMode
                for _, m in ipairs(NS.FIGHT_MODES) do
                    if m.key == popMode then label = m.label break end
                end
                NS.ShowCopyText((popDeath and popDeath.name or "Fight") .. " - " .. label,
                    NS.DeathRecapText(popDeath, popMode))
            end)
        copy:SetPoint("RIGHT", close, "LEFT", -4, 0)

        popFrame.modeRow = CreateFrame("Frame", nil, popFrame)
        popFrame.modeRow:SetPoint("TOPLEFT", 10, -34)
        popFrame.modeRow:SetPoint("TOPRIGHT", -10, -34)
        popFrame.modeRow:SetHeight(20)
        popFrame.modeButtons = {}
        local prev
        for _, m in ipairs(NS.FIGHT_MODES) do
            local b = CreateFrame("Button", nil, popFrame.modeRow)
            b:SetHeight(18)
            b.mode, b.label = m.key, m.label
            b.text = b:CreateFontString(nil, "OVERLAY")
            b.text:SetFont(NS.CurrentFont(), 11, "")
            b.text:SetPoint("LEFT", 6, 0)
            b.text:SetText(C(m.label, NS.COLORS.dim))
            b:SetWidth((b.text:GetStringWidth() or 60) + 14)
            b.hl = b:CreateTexture(nil, "HIGHLIGHT")
            b.hl:SetAllPoints()
            b.hl:SetColorTexture(NS.ACCENT.r, NS.ACCENT.g, NS.ACCENT.b, 0.10)
            if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
            else b:SetPoint("LEFT", 0, 0) end
            b:SetScript("OnClick", function() popMode = b.mode popRender() end)
            popFrame.modeButtons[#popFrame.modeButtons + 1] = b
            prev = b
        end

        popFrame.text = CreateFrame("ScrollingMessageFrame", nil, popFrame)
        popFrame.text:SetPoint("TOPLEFT", popFrame.modeRow, "BOTTOMLEFT", 0, -4)
        popFrame.text:SetPoint("BOTTOMRIGHT", -10, 22)
        popFrame.text:SetFont(NS.CurrentFont(), 11, "")
        popFrame.text:SetJustifyH("LEFT")
        popFrame.text:SetFading(false)
        popFrame.text:SetMaxLines(POPOUT_LOG_ROWS + 40)
        popFrame.text:SetInsertMode(SCROLLING_MESSAGE_FRAME_INSERT_MODE_BOTTOM or "BOTTOM")
        if popFrame.text.SetIndentedWordWrap then popFrame.text:SetIndentedWordWrap(true) end
        popFrame.text:SetSpacing(3)
        popFrame.text:SetHyperlinksEnabled(true)
        popFrame.text:EnableMouse(true)
        popFrame.text:EnableMouseWheel(true)
        popFrame.text:SetScript("OnMouseWheel", function(self, delta)
            local step = (IsShiftKeyDown and IsShiftKeyDown()) and 10 or 3
            for _ = 1, step do
                if delta > 0 then self:ScrollUp() else self:ScrollDown() end
            end
        end)
        popFrame.text:SetScript("OnHyperlinkEnter", function(self, link)
            NS.HandleLinkEnter(self, link)
        end)
        popFrame.text:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
        popFrame.text:SetScript("OnHyperlinkClick", function(self, link, text, button)
            -- the first argument is the owning combat window, not the frame
            NS.HandleLinkClick(nil, link, text, button)
        end)

        popFrame:SetResizable(true)
        NS.SetResizeLimits(popFrame, 520, 300, 1800, 1400)
        local grip = CreateFrame("Button", nil, popFrame)
        grip:SetSize(16, 16)
        grip:SetPoint("BOTTOMRIGHT", -2, 2)
        grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
        grip:SetScript("OnMouseDown", function() popFrame:StartSizing("BOTTOMRIGHT") end)
        grip:SetScript("OnMouseUp", function()
            popFrame:StopMovingOrSizing()
            NS.db.fightLogSize = {
                w = math.floor(popFrame:GetWidth() + 0.5),
                h = math.floor(popFrame:GetHeight() + 0.5),
            }
        end)
    end
    popFrame:Show()
    popRender()
    return true
end

function NS.ToggleDeaths()
    ensureFrame()
    if frame:IsShown() then frame:Hide() return end
    renderList()
    frame:Show()
end

function NS.OpenDeathRecap(death)
    ensureFrame()
    renderList()
    renderDetail(death)
    frame:Show()
end

function NS.OpenDeathRecapByIndex(id)
    for i = #NS.deaths, 1, -1 do
        if NS.deaths[i].id == id then
            NS.OpenDeathRecap(NS.deaths[i])
            return
        end
    end
    NS.Print("that death is no longer in the recap history.")
end
