-- Silk : Auras ------------------------------------------------------------
-- Rounded-square icons, a thin ring tinted by debuff school, stack counts,
-- and duration text kept fresh by one shared quarter-second ticker. No
-- cooldown swipes: numbers read cleaner on glass.

local ADDON, ns = ...

ns.auraContainers = {}

-- icon --------------------------------------------------------------------

local function NewIcon(parent)
    local b = CreateFrame("Frame", nil, parent)
    b:EnableMouse(true)

    local mask = b:CreateMaskTexture()
    mask:SetAllPoints(b)
    mask:SetTexture(ns.TEX.iconMask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(b)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:AddMaskTexture(mask)
    b.icon = icon

    local ring = b:CreateTexture(nil, "OVERLAY", nil, 0)
    ring:SetAllPoints(b)
    ring:SetTexture(ns.TEX.iconRing)
    b.ring = ring

    local count = ns.NewText(b)
    count:SetPoint("BOTTOMRIGHT", 1, 0)
    b.count = count

    local dur = ns.NewText(b)
    dur:SetPoint("TOP", b, "BOTTOM", 0, -1)
    b.dur = dur

    b:SetScript("OnEnter", function(s)
        if not s.unit or not s.index then return end
        GameTooltip:SetOwner(s, "ANCHOR_BOTTOMRIGHT")
        if s.helpful then
            GameTooltip:SetUnitBuff(s.unit, s.index, s.filter)
        else
            GameTooltip:SetUnitDebuff(s.unit, s.index, s.filter)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return b
end

-- container ---------------------------------------------------------------

local cproto = {}

function cproto:GetIcon(k)
    local b = self.icons[k]
    if not b then
        b = NewIcon(self)
        self.icons[k] = b
    end
    return b
end

function cproto:HideAll()
    for k = 1, #self.icons do self.icons[k]:Hide() end
end

local function DressIcon(b, size, iconTex, count, helpful, dtype)
    b:SetSize(size, size)
    b.icon:SetTexture(iconTex)
    ns.SetFont(b.count, -3)
    ns.SetFont(b.dur, -3)
    b.count:SetText((count and count > 1) and count or "")
    if helpful then
        b.ring:SetVertexColor(1, 1, 1, 0.16)
    else
        local c = DebuffTypeColor and DebuffTypeColor[dtype or "none"]
        if c then
            b.ring:SetVertexColor(c.r, c.g, c.b, 0.95)
        else
            b.ring:SetVertexColor(0.78, 0.24, 0.26, 0.9)
        end
    end
end

function cproto:UpdateMini(o)
    local unit = self.unit
    local list = {}
    for i = 1, 40 do
        local name, iconTex, count, dtype = UnitDebuff(unit, i)
        if not name then break end
        list[#list + 1] = { i = i, icon = iconTex, count = count, dtype = dtype,
                            disp = ns.CanDispel(dtype) }
    end
    table.sort(list, function(a, b)
        if a.disp ~= b.disp then return a.disp end
        return a.i < b.i
    end)
    local n = math.min(#list, o.maxShown or 3)
    for k = 1, n do
        local d = list[k]
        local b = self:GetIcon(k)
        DressIcon(b, o.size, d.icon, d.count, false, d.dtype)
        b.unit, b.index, b.helpful, b.filter = unit, d.i, false, nil
        b.expires = nil
        b.dur:SetText("")
        b:ClearAllPoints()
        b:SetPoint("RIGHT", self, "RIGHT", -((k - 1) * (o.size + (o.spacing or 3))), 0)
        b:Show()
    end
    for k = n + 1, #self.icons do self.icons[k]:Hide() end
    if n > 0 then
        self:SetSize(n * (o.size + (o.spacing or 3)), o.size)
    else
        self:SetSize(2, 2)
    end
end

function cproto:Update()
    local o = self.getOpts()
    local unit = self.unit
    if not o or not o.enabled or not UnitExists(unit) then
        self:HideAll()
        self:SetSize(2, 2)
        return
    end
    if o.mini then
        return self:UpdateMini(o)
    end

    local filter
    if o.helpful then
        filter = "HELPFUL"
    else
        filter = o.onlyMine and "HARMFUL|PLAYER" or "HARMFUL"
    end

    local size = o.size or 22
    local perRow = math.max(1, o.perRow or 8)
    local maxShown = o.maxShown or 16
    local sp = o.spacing or 4
    local rowH = size + 16
    local corner = self:Corner(o)
    local dx = (o.growX == "left") and -1 or 1
    local dy = (o.growY == "up") and 1 or -1
    local shown = 0

    for i = 1, 40 do
        local name, iconTex, count, dtype, duration, expires
        if o.helpful then
            name, iconTex, count, dtype, duration, expires = UnitBuff(unit, i, filter)
        else
            name, iconTex, count, dtype, duration, expires = UnitDebuff(unit, i, filter)
        end
        if not name then break end
        shown = shown + 1
        if shown > maxShown then
            shown = maxShown
            break
        end

        local b = self:GetIcon(shown)
        DressIcon(b, size, iconTex, count, o.helpful, dtype)
        b.unit, b.index, b.helpful, b.filter = unit, i, o.helpful, filter
        b.expires = (duration and duration > 0) and expires or nil
        if not b.expires then b.dur:SetText("") end

        local col = (shown - 1) % perRow
        local row = math.floor((shown - 1) / perRow)
        b:ClearAllPoints()
        b:SetPoint(corner, self, corner, dx * col * (size + sp), dy * row * rowH)
        b:Show()
    end

    for k = shown + 1, #self.icons do self.icons[k]:Hide() end

    -- the block becomes a real region covering its icons, which is what the
    -- layout-mode drag handle grabs
    if shown > 0 then
        local cols = math.min(shown, perRow)
        local rows = math.ceil(shown / perRow)
        self:SetSize(cols * (size + sp) - sp, (rows - 1) * rowH + size)
    else
        self:SetSize(2, 2)
    end
end

-- attach ------------------------------------------------------------------

-- The block's growth corner: icons stack away from it, so the corner stays
-- pinned wherever you put it no matter how many auras are up.
function cproto:Corner(o)
    local v = (o.growY == "up") and "BOTTOM" or "TOP"
    local h = (o.growX == "left") and "RIGHT" or "LEFT"
    return v .. h
end

function cproto:Reanchor()
    local o = self.getOpts() or {}
    local corner = self:Corner(o)
    local f = self.owner
    self:ClearAllPoints()

    if self.side == "MINI" then
        self:SetPoint("RIGHT", f, "RIGHT", -6 + (o.x or 0), o.y or 0)
        return
    end

    if o.detach then
        self:SetPoint(corner, UIParent, "CENTER", o.px or 0, o.py or 0)
        return
    end

    local hx = (o.growX == "left") and "RIGHT" or "LEFT"
    -- growing upward, the bottom row's duration text hangs into the frame,
    -- so lift the block clear of it
    local pad = (o.growY == "up") and 12 or 0
    if self.side == "TOP" then
        self:SetPoint(corner, f, "TOP" .. hx, o.x or 0, 7 + pad + (o.y or 0))
    else
        self:SetPoint(corner, f, "BOTTOM" .. hx, o.x or 0, -7 + pad + (o.y or 0))
    end
end

function ns.AttachAuras(f, unit, side, getOpts)
    local c = CreateFrame("Frame", nil, f)
    c:SetSize(2, 2)
    c:SetFrameLevel(f:GetFrameLevel() + 12)
    c.side, c.unit, c.getOpts, c.owner = side, unit, getOpts, f
    c.icons = {}
    for k, v in pairs(cproto) do c[k] = v end
    c:Reanchor()
    table.insert(ns.auraContainers, c)
    return c
end

-- duration ticker ---------------------------------------------------------

local function FmtDur(t)
    if t >= 3600 then return math.ceil(t / 3600) .. "h" end
    if t >= 60 then return math.ceil(t / 60) .. "m" end
    return tostring(math.ceil(t))
end

C_Timer.NewTicker(0.25, function()
    local now = GetTime()
    for ci = 1, #ns.auraContainers do
        local c = ns.auraContainers[ci]
        if c:IsVisible() then
            for k = 1, #c.icons do
                local b = c.icons[k]
                if b:IsShown() and b.expires then
                    local t = b.expires - now
                    if t <= 0 then
                        b.dur:SetText("")
                    else
                        b.dur:SetText(FmtDur(t))
                        if t < 5.5 then
                            b.dur:SetTextColor(1, 0.42, 0.36)
                        else
                            b.dur:SetTextColor(0.85, 0.88, 0.93)
                        end
                    end
                end
            end
        end
    end
end)
