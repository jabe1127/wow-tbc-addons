-- LogLovers Stats: per-segment breakdowns (damage done / healing done / damage taken)
local ADDON, NS = ...

local C = NS.C

local frame
local mode = "dmg"           -- dmg | heal | taken
local segFilter = nil        -- nil = overall, number = segment index
local expanded = {}          -- [unitKey] = true
local offset = 0
local displayList = {}
local rowPool = {}

local MODES = {
    { key = "dmg",   label = "Damage Done" },
    { key = "heal",  label = "Healing Done" },
    { key = "taken", label = "Damage Taken" },
}

-------------------------------------------------------------------------------
-- Aggregation
-------------------------------------------------------------------------------
local function buildData()
    local units = {}          -- [key] = { name, guid, flags, total, spells = {} }
    local function unitFor(guid, name, flags)
        local key = name or "?"
        local u = units[key]
        if not u then
            u = { name = key, guid = guid, flags = flags, total = 0, spells = {} }
            units[key] = u
        end
        return u
    end
    local function spellFor(u, sid, sname)
        local key = sname or "Melee"
        local s = u.spells[key]
        if not s then
            s = { name = key, sid = sid, total = 0, hits = 0, crits = 0, misses = 0, max = 0 }
            u.spells[key] = s
        end
        return s
    end

    NS.BufferEach(function(rec)
        if segFilter and rec.segIndex ~= segFilter then return end
        if mode == "dmg" then
            if rec.cat == "damage" and rec.sn then
                local u = unitFor(rec.sg, rec.sn, rec.sf)
                local s = spellFor(u, rec.sid, rec.sname or (rec.env and "Environment") or "Melee")
                local amt = rec.amt or 0
                u.total = u.total + amt
                s.total = s.total + amt
                s.hits = s.hits + 1
                if rec.crit then s.crits = s.crits + 1 end
                if amt > s.max then s.max = amt end
            elseif rec.cat == "misses" and rec.sn then
                local u = unitFor(rec.sg, rec.sn, rec.sf)
                local s = spellFor(u, rec.sid, rec.sname or "Melee")
                s.misses = s.misses + 1
            end
        elseif mode == "heal" then
            if rec.cat == "healing" and rec.sn then
                local u = unitFor(rec.sg, rec.sn, rec.sf)
                local s = spellFor(u, rec.sid, rec.sname)
                local amt = (rec.amt or 0) - (rec.over or 0)
                if amt < 0 then amt = 0 end
                u.total = u.total + amt
                s.total = s.total + amt
                s.hits = s.hits + 1
                if rec.crit then s.crits = s.crits + 1 end
                if amt > s.max then s.max = amt end
            end
        else -- taken
            if rec.cat == "damage" and rec.dn then
                local u = unitFor(rec.dg, rec.dn, rec.df)
                local s = spellFor(u, rec.sid, rec.sname or (rec.env and "Environment") or "Melee")
                local amt = rec.amt or 0
                u.total = u.total + amt
                s.total = s.total + amt
                s.hits = s.hits + 1
                if rec.crit then s.crits = s.crits + 1 end
                if amt > s.max then s.max = amt end
            end
        end
    end)

    local sorted = {}
    for _, u in pairs(units) do
        if u.total > 0 then sorted[#sorted + 1] = u end
    end
    table.sort(sorted, function(a, b) return a.total > b.total end)
    return sorted
end

local function flatten(sorted)
    wipe(displayList)
    local maxTotal = sorted[1] and sorted[1].total or 1
    for rank, u in ipairs(sorted) do
        displayList[#displayList + 1] = { kind = "unit", u = u, rank = rank, frac = u.total / maxTotal }
        if expanded[u.name] then
            local spells = {}
            for _, s in pairs(u.spells) do spells[#spells + 1] = s end
            table.sort(spells, function(a, b) return a.total > b.total end)
            for _, s in ipairs(spells) do
                displayList[#displayList + 1] = { kind = "spell", u = u, s = s, frac = s.total / u.total }
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Rendering
-------------------------------------------------------------------------------
local ROWH = 19

local function getSeg(index)
    for _, s in ipairs(NS.segments) do
        if s.index == index then return s end
    end
end

local function visibleRows()
    return math.floor((frame.body:GetHeight() - 4) / ROWH)
end

local function render()
    flatten(buildData())
    local nVis = visibleRows()
    if offset > #displayList - nVis then offset = math.max(0, #displayList - nVis) end

    for _, r in ipairs(rowPool) do r:Hide() end
    for i = 1, nVis do
        local item = displayList[offset + i]
        if not item then break end
        local row = rowPool[i]
        if not row then
            row = CreateFrame("Button", nil, frame.body)
            row:SetHeight(ROWH - 1)
            row:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROWH)
            row:SetPoint("TOPRIGHT", -2, -2 - (i - 1) * ROWH)
            row.bar = row:CreateTexture(nil, "BACKGROUND")
            row.bar:SetPoint("TOPLEFT")
            row.bar:SetPoint("BOTTOMLEFT")
            row.bar:SetTexture("Interface\\Buttons\\WHITE8x8")
            row.left = row:CreateFontString(nil, "OVERLAY")
            row.left:SetPoint("LEFT", 6, 0)
            row.left:SetJustifyH("LEFT")
            row.right = row:CreateFontString(nil, "OVERLAY")
            row.right:SetPoint("RIGHT", -6, 0)
            row.right:SetJustifyH("RIGHT")
            row.hl = row:CreateTexture(nil, "HIGHLIGHT")
            row.hl:SetAllPoints()
            row.hl:SetColorTexture(1, 1, 1, 0.05)
            rowPool[i] = row
        end
        row.left:SetFont(NS.CurrentFont(), 11, "")
        row.right:SetFont(NS.CurrentFont(), 11, "")

        if item.kind == "unit" then
            local u = item.u
            local hex = NS.UnitColor(u.guid, u.name, u.flags)
            local r255 = tonumber(hex:sub(1, 2), 16) / 255
            local g255 = tonumber(hex:sub(3, 4), 16) / 255
            local b255 = tonumber(hex:sub(5, 6), 16) / 255
            row.bar:SetVertexColor(r255, g255, b255, 0.22)
            row.bar:SetWidth(math.max(1, (frame.body:GetWidth() - 4) * item.frac))
            row.left:SetText(C(item.rank .. ".", NS.COLORS.dim) .. " " ..
                (expanded[u.name] and C("v ", NS.COLORS.accent) or C("> ", NS.COLORS.dim)) ..
                C(u.name, hex))
            row.right:SetText(C(NS.FormatNumber(u.total), "ffffff"))
            row:SetScript("OnClick", function()
                expanded[u.name] = not expanded[u.name] or nil
                render()
            end)
        else
            local s = item.s
            row.bar:SetVertexColor(0.5, 0.55, 0.65, 0.12)
            row.bar:SetWidth(math.max(1, (frame.body:GetWidth() - 4) * item.frac))
            local attempts = s.hits + s.misses
            local critPct = s.hits > 0 and (s.crits / s.hits * 100) or 0
            local missPct = attempts > 0 and (s.misses / attempts * 100) or 0
            local detail = string.format("%s   n=%d  avg=%s  max=%s  crit=%.0f%%",
                NS.FormatNumber(s.total), s.hits,
                NS.FormatNumber(s.hits > 0 and s.total / s.hits or 0),
                NS.FormatNumber(s.max), critPct)
            if s.misses > 0 then
                detail = detail .. string.format("  miss=%.0f%%", missPct)
            end
            row.left:SetText("      " .. NS.IconTag(s.sid, 12) .. C(s.name, "d8c26e"))
            row.right:SetText(C(detail, NS.COLORS.dim))
            row:SetScript("OnClick", function()
                if s.sid or s.name then NS.OpenSpellInspector(s.sid, s.name) end
            end)
        end
        row:Show()
    end

    -- if the pinned fight has rolled off the list there is nothing to filter
    -- to; drop the filter rather than showing its numbers under "Overall"
    if segFilter and not getSeg(segFilter) then segFilter = nil end
    frame.segLabel:SetText(C(segFilter and NS.SegmentLabel(getSeg(segFilter)) or "Overall", NS.COLORS.accent))
    for _, tab in ipairs(frame.tabs) do
        local active = tab.mode == mode
        tab.text:SetText(active and C(tab.label, NS.COLORS.accent) or C(tab.label, NS.COLORS.dim))
    end
end

-------------------------------------------------------------------------------
-- Frame
-------------------------------------------------------------------------------
local function ensureFrame()
    if frame then return end
    frame = CreateFrame("Frame", "LogLoversStats", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetSize(680, 440)
    frame:SetPoint("CENTER", 0, 20)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetResizable(true)
    NS.SetResizeLimits(frame, 480, 260, 1200, 900)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    NS.SkinPanel(frame, { r = 0.055, g = 0.043, b = 0.028, a = 0.97 })
    tinsert(UISpecialFrames, "LogLoversStats")

    local title = frame:CreateFontString(nil, "OVERLAY")
    title:SetFont(NS.CurrentFont(), 14, "")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText(C("Combat Stats", NS.COLORS.accent))

    local close = NS.MakeIconButton(frame, "Interface\\Buttons\\UI-StopButton", nil,
        function() frame:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)

    -- mode tabs
    frame.tabs = {}
    local prev
    for _, m in ipairs(MODES) do
        local tab = CreateFrame("Button", nil, frame)
        tab:SetSize(100, 18)
        if prev then tab:SetPoint("LEFT", prev, "RIGHT", 10, 0)
        else tab:SetPoint("TOPLEFT", 12, -32) end
        tab.text = tab:CreateFontString(nil, "OVERLAY")
        tab.text:SetFont(NS.CurrentFont(), 12, "")
        tab.text:SetPoint("LEFT")
        tab.mode, tab.label = m.key, m.label
        tab:SetScript("OnClick", function()
            mode = m.key
            offset = 0
            render()
        end)
        frame.tabs[#frame.tabs + 1] = tab
        prev = tab
    end

    -- segment picker
    local segBtn = CreateFrame("Button", nil, frame)
    segBtn:SetSize(220, 18)
    segBtn:SetPoint("TOPRIGHT", -32, -32)
    frame.segLabel = segBtn:CreateFontString(nil, "OVERLAY")
    frame.segLabel:SetFont(NS.CurrentFont(), 12, "")
    frame.segLabel:SetPoint("RIGHT")
    frame.segLabel:SetJustifyH("RIGHT")
    segBtn:SetScript("OnClick", function()
        local items = { { text = "Segment", header = true },
            { text = "Overall", func = function() segFilter = nil offset = 0 render() end } }
        for i = #NS.segments, 1, -1 do
            local s = NS.segments[i]
            table.insert(items, { text = NS.SegmentLabel(s), checked = segFilter == s.index,
                func = function() segFilter = s.index offset = 0 render() end })
        end
        NS.ShowMenu(items)
    end)

    -- body
    frame.body = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    NS.SkinPanel(frame.body, { r = 0, g = 0, b = 0, a = 0.35 })
    frame.body:SetPoint("TOPLEFT", 10, -54)
    frame.body:SetPoint("BOTTOMRIGHT", -10, 28)
    frame.body:EnableMouseWheel(true)
    frame.body:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta * 3)
        render()
    end)

    local hint = frame:CreateFontString(nil, "OVERLAY")
    hint:SetFont(NS.CurrentFont(), 10, "")
    hint:SetPoint("BOTTOMLEFT", 12, 9)
    hint:SetText(C("Click a unit to expand spells - click a spell for the inspector - scroll to browse", NS.COLORS.dim))

    -- refresh button
    local refresh = CreateFrame("Button", nil, frame)
    refresh:SetSize(60, 16)
    refresh:SetPoint("BOTTOMRIGHT", -12, 8)
    local rt = refresh:CreateFontString(nil, "OVERLAY")
    rt:SetFont(NS.CurrentFont(), 11, "")
    rt:SetPoint("RIGHT")
    rt:SetText(C("refresh", NS.COLORS.accent))
    refresh:SetScript("OnClick", function() render() end)

    frame:SetScript("OnSizeChanged", function() render() end)

    -- resize grip
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)

    frame:Hide()
end

-- test hook: which fight the browser is currently filtered to, if any
function NS.StatsSegmentFilter() return segFilter end

function NS.ToggleStats(forceShow)
    ensureFrame()
    if frame:IsShown() and not forceShow then frame:Hide() return end
    -- Re-pin every time it opens. Pinning once and never again meant that
    -- after enough fights the pinned segment had been rolled off the list, the
    -- header fell back to "Overall" and the numbers were still one old fight's.
    segFilter = NS.currentSegment and NS.currentSegment.index or nil
    offset = 0
    render()
    frame:Show()
end
