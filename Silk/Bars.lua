-- Silk : Bars -------------------------------------------------------------
-- A status bar built from scratch. No StatusBar widget: masked fills whose
-- widths are driven by the shared animation driver, so health pours instead
-- of snapping. Damage leaves a warm ghost trail that lingers for a beat, and
-- a soft additive spark rides the leading edge while anything is moving.
--
-- The structural idea: a *shell* owns the capsule silhouette — outline,
-- background, gloss, and the two cap masks — and one or two *segments* draw
-- inside it. Every segment is clipped by the shell's masks, so a health
-- segment across the top and a power segment along the bottom share one
-- continuous rounded outline. The power bar is part of the bar rather than a
-- second pill parked underneath it, and it inherits whatever corner style is
-- selected. Detaching just gives the power segment a shell of its own.

local ADDON, ns = ...

-- segment ------------------------------------------------------------------

local seg = {}

-- Every one of these is a C call into the client. During raid combat dozens
-- of segments animate at once, so re-asserting a width or a shown state that
-- is already correct is the single biggest cost in the whole addon. Each
-- write is guarded against the last value we set.
local function showPart(self, tex, key, want)
    if self[key] ~= want then
        self[key] = want
        if want then tex:Show() else tex:Hide() end
    end
end

local function widthPart(self, tex, key, w)
    if self[key] ~= w then
        self[key] = w
        tex:SetWidth(w)
    end
end

local function alphaPart(self, tex, key, a)
    local last = self[key]
    if not last or math.abs(last - a) > 0.004 then
        self[key] = a
        tex:SetAlpha(a)
    end
end

function seg:InvalidateCache()
    self.cFW, self.cLW, self.cLA, self.cSA = nil, nil, nil, nil
    self.cFillVis, self.cLossVis, self.cSparkVis = nil, nil, nil
end

function seg:SetStatusColor(r, g, b)
    self.cr, self.cg, self.cb = r, g, b
    self.fill:SetVertexColor(r, g, b)
    if not self.tintsBackground then return end

    -- The empty part of the bar. Left to itself it takes a wash of the fill
    -- colour, which turns yellow on a neutral mob and orange on a hunter --
    -- so how much of that wash it takes, or whether it takes any, is a
    -- setting. This runs on every health event, so only write on a change.
    local db = ns.db
    if not db then return end
    local ch = ns.palette.charcoal
    local mode = db.bgMode or "match"
    local br, bgc, bb
    if mode == "custom" then
        local c = db.bgColor or { r = ch[1], g = ch[2], b = ch[3] }
        br, bgc, bb = c.r, c.g, c.b
    elseif mode == "dark" then
        br, bgc, bb = ch[1], ch[2], ch[3]
    else
        local t = db.bgTint or 0.14
        br, bgc, bb = ch[1] + r * t, ch[2] + g * t, ch[3] + b * t
    end
    if (db.borderMode or "dark") == "class" and not self.shell.tinted then
        self.shell:ApplyBorderColor()
    end
    local a = db.bgAlpha or 0.5
    local bgtex = self.shell.bg
    if bgtex.cr ~= br or bgtex.cg ~= bgc or bgtex.cb ~= bb then
        bgtex.cr, bgtex.cg, bgtex.cb = br, bgc, bb
        bgtex:SetVertexColor(br, bgc, bb)
    end
    if bgtex.ca ~= a then
        bgtex.ca = a
        bgtex:SetAlpha(a)
    end
end

function seg:SetInstant(v, m)
    m = (m and m > 0) and m or 1
    v = math.max(0, math.min(v or 0, m))
    self.maxv = m
    self.tgt, self.disp, self.lossv = v, v, v
    self.holdT, self.sparkA = 0, 0
    self.init = true
    self.spark:SetAlpha(0)
    self:Layout()
end

-- Values carry the scale they were set at. If the maximum changes -- a pet
-- talent pushing focus past its cap, a max-power event, or the frame being
-- handed a different unit entirely -- anything still holding the old scale
-- has to come back inside the new one, or disp/max produces a huge ratio.
function seg:ClampToMax()
    local m = self.maxv
    if m <= 0 then m = 1 self.maxv = 1 end
    if self.tgt > m then self.tgt = m end
    if self.tgt < 0 then self.tgt = 0 end
    if self.disp > m then self.disp = m end
    if self.disp < 0 then self.disp = 0 end
    if self.lossv > m then self.lossv = m end
    if self.lossv < self.disp then self.lossv = self.disp end
end

function seg:SetValue(v, m)
    m = (m and m > 0) and m or 1
    v = math.max(0, math.min(v or 0, m))
    if not self.init then return self:SetInstant(v, m) end
    local scaleChanged = (m ~= self.maxv)
    self.maxv = m
    if scaleChanged then self:ClampToMax() end
    if v < self.disp and ns.db and ns.db.ghost then
        if self.lossv < self.disp then self.lossv = self.disp end
        self.holdT = 0.22
    end
    self.tgt = v
    ns.Animate(self)
end

-- point is TOPLEFT or BOTTOMLEFT: which edge of the shell this segment hugs
function seg:SetGeometry(point, height)
    self.point, self.segH = point, math.max(1, height or 1)
    local inner = self.shell.inner

    self.fill:ClearAllPoints()
    self.fill:SetPoint(point, inner, point, 0, 0)
    self.fill:SetHeight(self.segH)

    self.loss:ClearAllPoints()
    if point == "TOPLEFT" then
        self.loss:SetPoint("TOPLEFT", self.fill, "TOPRIGHT")
    else
        self.loss:SetPoint("BOTTOMLEFT", self.fill, "BOTTOMRIGHT")
    end
    self.loss:SetHeight(self.segH)

    self.spark:SetSize(math.max(10, self.segH * 1.4), math.max(14, self.segH * 2.4))
    self:InvalidateCache()
    self:Layout()
end


function seg:Layout()
    local iw = self.shell.iw or 0
    if iw <= 0 or not self.visible then
        showPart(self, self.fill, "cFillVis", false)
        showPart(self, self.loss, "cLossVis", false)
        showPart(self, self.spark, "cSparkVis", false)
        return
    end
    local m = self.maxv
    if m <= 0 then m = 1 end

    -- the fill can never be wider than its track, whatever the values say
    local fr = self.disp / m
    if fr < 0 then fr = 0 elseif fr > 1 then fr = 1 end
    local fw = iw * fr
    widthPart(self, self.fill, "cFW", math.max(fw, 0.001))
    showPart(self, self.fill, "cFillVis", fw >= 0.6)
    showPart(self, self.spark, "cSparkVis", true)

    local lr = self.lossv / m
    if lr < 0 then lr = 0 elseif lr > 1 then lr = 1 end
    local lw = iw * lr - fw
    if lw < 0.6 then
        showPart(self, self.loss, "cLossVis", false)
    else
        widthPart(self, self.loss, "cLW", lw)
        local gap = (self.lossv - self.disp)
        alphaPart(self, self.loss, "cLA", 0.55 * math.min(1, gap / (m * 0.02)))
        showPart(self, self.loss, "cLossVis", true)
    end
end

function seg:SetVisible(on)
    if self.visible == (on and true or false) then return end
    self.visible = on and true or false
    if not self.visible then
        self.fill:Hide()
        self.loss:Hide()
        self.spark:Hide()
    else
        self:Layout()
    end
end

function seg:Step(dt)
    local db = ns.db
    local cont = false
    local m = self.maxv
    local speed = ((db and db.smooth) or 12) * self.speedMul

    local d = self.tgt - self.disp
    if math.abs(d) > m * 0.0015 then
        self.disp = self.disp + d * math.min(dt * speed, 1)
        cont = true
    else
        self.disp = self.tgt
    end

    if not (db and db.ghost) then
        self.lossv = self.disp
    elseif self.lossv < self.disp then
        self.lossv = self.disp
    elseif self.lossv > self.disp then
        if self.holdT > 0 then
            self.holdT = self.holdT - dt
        else
            local gap = self.lossv - self.disp
            local step = gap * math.min(dt * 9, 1)
            local floorStep = m * dt * 0.30
            if step < floorStep then step = math.min(gap, floorStep) end
            self.lossv = self.lossv - step
            if self.lossv - self.disp < m * 0.002 then self.lossv = self.disp end
        end
        cont = true
    end

    self:Layout()

    local activity = math.abs(self.tgt - self.disp) / m
    local targetA = math.min(activity * 8, 1) * 0.65
    local sa = self.sparkA + (targetA - self.sparkA) * math.min(dt * 10, 1)
    if targetA < 0.02 and sa < 0.02 then
        sa = 0
    elseif sa > 0.02 then
        cont = true
    end
    self.sparkA = sa
    alphaPart(self, self.spark, "cSA", self.visible and sa or 0)

    return cont
end

local function newSegment(shell, kind, sublevel)
    local s = {}
    for k, v in pairs(seg) do s[k] = v end
    s.shell = shell
    s.speedMul = (kind == "power") and 1.5 or 1
    s.maxv, s.tgt, s.disp, s.lossv = 1, 0, 0, 0
    s.holdT, s.sparkA = 0, 0
    s.visible = true
    s.tintsBackground = (kind ~= "power")

    local inner = shell.inner
    local base = sublevel or 0

    local fill = inner:CreateTexture(nil, "ARTWORK", nil, base)
    fill:SetColorTexture(1, 1, 1)
    fill:SetWidth(0.001)
    inner:AddMasked(fill)
    s.fill = fill

    function s:ApplyFinish()
        local tex = ns.FINISH[(ns.db and ns.db.barFinish) or "flat"]
        if tex then
            self.fill:SetTexture(tex)
        else
            self.fill:SetColorTexture(1, 1, 1)
        end
        if self.cr then self.fill:SetVertexColor(self.cr, self.cg, self.cb) end
    end

    local loss = inner:CreateTexture(nil, "ARTWORK", nil, base + 1)
    loss:SetColorTexture(1, 1, 1)
    local lc = ns.palette.loss
    loss:SetVertexColor(lc[1], lc[2], lc[3])
    loss:SetWidth(0.001)
    loss:Hide()
    inner:AddMasked(loss)
    s.loss = loss

    local spark = inner:CreateTexture(nil, "OVERLAY", nil, base + 1)
    spark:SetTexture(ns.TEX.spark)
    spark:SetBlendMode("ADD")
    spark:SetPoint("CENTER", fill, "RIGHT", 0, 0)
    spark:SetAlpha(0)
    inner:AddMasked(spark)
    s.spark = spark

    return s
end

-- shell --------------------------------------------------------------------

local shellProto = {}

-- The border. Passing a colour tints it for a rank ring or a dispellable
-- debuff; passing nothing returns it to whatever the profile asks for.
function shellProto:ApplyBorderColor()
    local db = ns.db
    if not db then return end
    local mode = db.borderMode or "dark"
    local a = db.borderAlpha or 0.85
    if mode == "class" and self.health and self.health.cr then
        self.outline:SetVertexColor(self.health.cr, self.health.cg, self.health.cb, a)
    elseif mode == "custom" then
        local c = db.borderColor or { r = 0, g = 0, b = 0 }
        self.outline:SetVertexColor(c.r, c.g, c.b, a)
    else
        self.outline:SetVertexColor(0, 0, 0, a)
    end
end

function shellProto:SetOutlineColor(r, g, b, a)
    if r then
        self.tinted = true
        self.outline:SetVertexColor(r, g, b, a or 0.9)
    else
        self.tinted = false
        self:ApplyBorderColor()
    end
end

function shellProto:ApplyStyle()
    local db = ns.db
    if not db then return end
    self:SetCapStyle(db.corner)
    self.inner:SetCapStyle(db.corner)
    self.gloss:SetAlpha(db.gloss or 0.3)
    if self.trough then
        self.trough:SetAlpha(db.troughAlpha or 1)
    end

    local bs = db.borderSize or 1
    self.inner:ClearAllPoints()
    self.inner:SetPoint("TOPLEFT", bs, -bs)
    self.inner:SetPoint("BOTTOMRIGHT", -bs, bs)
    if not self.tinted then self:ApplyBorderColor() end

    if self.drop then
        local sz = db.frameShadowSize or 7
        self.drop:SetTexture(ns.SHADOW[db.corner] or ns.SHADOW.capsule)
        self.drop:ClearAllPoints()
        self.drop:SetPoint("TOPLEFT", -sz, sz)
        self.drop:SetPoint("BOTTOMRIGHT", sz, -sz)
        self.drop:SetAlpha(db.frameShadow and (db.frameShadowAlpha or 0.55) or 0)
    end
    if self.topline then
        self.topline:SetAlpha(db.topline or 0)
    end
    if self.health and self.health.ApplyFinish then self.health:ApplyFinish() end
    if self.power and self.power.ApplyFinish then self.power:ApplyFinish() end

    local lc = db.lossColor
    if not lc then
        local p = ns.palette.loss
        lc = { r = p[1], g = p[2], b = p[3] }
    end
    if self.health then self.health.loss:SetVertexColor(lc.r, lc.g, lc.b) end
    if self.power then self.power.loss:SetVertexColor(lc.r, lc.g, lc.b) end

    -- drop the cached background so a changed mode or tint is picked up
    self.bg.cr, self.bg.ca = nil, nil
    if self.health and self.health.cr then
        self.health:SetStatusColor(self.health.cr, self.health.cg, self.health.cb)
    end
end

-- how tall the power slice is; the health slice takes what's left
function shellProto:SetPowerHeight(px)
    self.powerH = math.max(1, px or 4)
    self:Relayout()
end

function shellProto:ShowPower(on)
    self.powerOn = on and true or false
    if self.power then self.power:SetVisible(self.powerOn) end
    if self.divider then self.divider:SetShown(self.powerOn) end
    self:Relayout()
end

function shellProto:Relayout()
    local ih = self.ih or 0
    if ih <= 0 then return end
    if self.power and self.powerOn then
        local ph = math.min(self.powerH or 4, math.max(1, ih - 3))
        self.power:SetGeometry("BOTTOMLEFT", ph)
        self.health:SetGeometry("TOPLEFT", math.max(1, ih - ph - 1))
        if self.divider then
            self.divider:ClearAllPoints()
            self.divider:SetPoint("BOTTOMLEFT", self.inner, "BOTTOMLEFT", 0, ph)
            self.divider:SetPoint("BOTTOMRIGHT", self.inner, "BOTTOMRIGHT", 0, ph)
            self.divider:SetHeight(1)
        end
    elseif self.health then
        self.health:SetGeometry("TOPLEFT", ih)
    end
end

local function newShell(parent)
    local shell = ns.Capsule(parent)
    for k, v in pairs(shellProto) do shell[k] = v end

    local outline = shell:CreateTexture(nil, "BACKGROUND", nil, -8)
    outline:SetAllPoints()
    outline:SetColorTexture(1, 1, 1)
    outline:SetVertexColor(0, 0, 0, 0.85)
    shell:AddMasked(outline)
    shell.outline = outline

    local inner = ns.Capsule(shell)
    inner:SetPoint("TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", -1, 1)
    shell.inner = inner

    -- The outline sits behind the whole bar, not just its border, so anything
    -- tinting it -- an elite's gold rank ring, a dispellable debuff on a raid
    -- cell -- used to flood the empty part of the bar through the translucent
    -- background. This opaque trough covers the interior, leaving the tint
    -- visible only as the 1px edge it was meant to be.
    local trough = inner:CreateTexture(nil, "BACKGROUND", nil, -8)
    trough:SetAllPoints()
    trough:SetColorTexture(0, 0, 0)
    inner:AddMasked(trough)
    shell.trough = trough

    local bg = inner:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1)
    bg:SetVertexColor(ns.palette.charcoal[1], ns.palette.charcoal[2], ns.palette.charcoal[3])
    inner:AddMasked(bg)
    shell.bg = bg

    local gloss = inner:CreateTexture(nil, "OVERLAY", nil, 0)
    gloss:SetAllPoints()
    gloss:SetTexture(ns.TEX.gloss)
    inner:AddMasked(gloss)
    shell.gloss = gloss

    -- a soft dark halo under the whole bar: what separates "floating panel"
    -- from "rectangle pasted on the world". Not masked -- it must extend past
    -- the silhouette -- and drawn at the very back so everything sits on it.
    local drop = shell:CreateTexture(nil, "BACKGROUND", nil, -8)
    drop:SetPoint("TOPLEFT", -7, 7)
    drop:SetPoint("BOTTOMRIGHT", 7, -7)
    drop:SetTexture(ns.SHADOW.capsule)
    shell.drop = drop

    -- a 1px light edge along the very top of the inner area: the sliver of
    -- rim light that makes the surface read as glass rather than paint
    local topline = inner:CreateTexture(nil, "OVERLAY", nil, 2)
    topline:SetPoint("TOPLEFT", 0, 0)
    topline:SetPoint("TOPRIGHT", 0, 0)
    topline:SetHeight(1)
    topline:SetColorTexture(1, 1, 1)
    topline:SetAlpha(0.10)
    inner:AddMasked(topline)
    shell.topline = topline

    local baseOSC = inner:GetScript("OnSizeChanged")
    inner:SetScript("OnSizeChanged", function(s, w, h)
        if baseOSC then baseOSC(s, w, h) end
        shell.iw, shell.ih = w, h
        if shell.health then shell.health:InvalidateCache() end
        if shell.power then shell.power:InvalidateCache() end
        shell:Relayout()
        if shell.health then shell.health:Layout() end
        if shell.power then shell.power:Layout() end
    end)

    return shell
end

-- public -------------------------------------------------------------------

-- A single-segment bar: its own capsule, filled edge to edge. Used for the
-- detached power bar and anywhere a lone bar is wanted.
function ns.CreateBar(parent, kind)
    local shell = newShell(parent)
    shell.health = newSegment(shell, kind, 0)
    shell.powerOn = false

    -- proxy the value API onto the frame so callers can treat it as one bar
    shell.SetStatusColor = function(self, r, g, b) self.health:SetStatusColor(r, g, b) end
    shell.SetValue       = function(self, v, m) self.health:SetValue(v, m) end
    shell.SetInstant     = function(self, v, m) self.health:SetInstant(v, m) end
    shell.Layout         = function(self) self.health:Layout() end

    shell:ApplyStyle()
    return shell
end

-- Health and power inside one silhouette. The power slice sits along the
-- bottom of the same capsule, clipped by the same masks, so the rounded ends
-- stay continuous and both follow the chosen corner style.
function ns.CreateUnitBar(parent)
    local shell = newShell(parent)
    shell.health = newSegment(shell, "health", 0)
    shell.power  = newSegment(shell, "power", 4)
    shell.powerH, shell.powerOn = 4, true

    local div = shell.inner:CreateTexture(nil, "ARTWORK", nil, 3)
    div:SetColorTexture(0, 0, 0)
    div:SetAlpha(0.55)
    shell.inner:AddMasked(div)
    shell.divider = div

    shell:ApplyStyle()
    return shell
end
