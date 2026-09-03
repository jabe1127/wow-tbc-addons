--[[--------------------------------------------------------------------------
    JCT - Engine.lua
    The display layer: one Frame per stream, a pool of FontStrings per frame,
    and a single global OnUpdate that drives every active string.

    Design notes
    ------------
    * One OnUpdate for the whole addon, hidden when nothing is animating, so
      the addon costs literally zero out of combat.
    * FontStrings are pooled forever. A FontString cannot be garbage
      collected in WoW, so pooling is mandatory rather than an optimisation.
    * SetFont is cached (see ns.SafeSetFont). It is the single most expensive
      call in this path and most strings in a fight share one font.
    * Overlap avoidance is done in the TIME domain, not the position domain:
      when a new string appears, older strings are pushed forward in time so
      they stay spaced out. That keeps every path function a pure function of
      progress, and has the nice side effect that a burst of damage visibly
      accelerates the older numbers off screen instead of stacking them.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

local Engine = {}
ns.Engine = Engine

Engine.frames = {}

local floor, random, sqrt = math.floor, math.random, math.sqrt
local tinsert, tremove = table.insert, table.remove

local POP_TIME    = 0.18   -- seconds of crit overshoot
local POP_OVERSHOOT = 0.60 -- extra scale at the start of the pop
local MIN_GAP_PX  = 6      -- vertical breathing room between strings

--------------------------------------------------------------------------
-- Resolved settings (frame value, else general value)
--------------------------------------------------------------------------

local function resolve(frameName)
    local db = ns.db
    local g  = db.general
    local f  = db.frames[frameName]
    return {
        fontPath  = ns.FontPath(f.font or g.font),
        fontSize  = f.fontSize or g.fontSize,
        outline   = f.outline  or g.outline,
        duration  = f.duration or g.duration,
        fadeTime  = f.fadeTime or g.fadeTime,
        critScale = g.critScale,
        critPop   = g.critPop,
        shadow    = g.shadow,
        animation = f.animation,
        curve     = f.curve,
        align     = f.align,
        maxLines  = f.maxLines,
        stagger   = f.stagger or 0,
        width     = f.width,
        height    = f.height,
        iconSide  = f.iconSide,
        scale     = f.scale or 1,
        anchor    = f.anchor or "screen",
        npOffsetX = f.npOffsetX or 0,
        npOffsetY = f.npOffsetY or 34,
        npFallback = (f.npFallback ~= false),
    }
end

-- Fade is configured in seconds ("fade out over 0.6s"), which is how people
-- actually think about it, but the animator wants the fraction of life at
-- which fading begins. Convert here, and fall back to the old fraction-based
-- setting for configs saved before the change.
local function fadeFraction(cfg, g)
    local dur = cfg.duration or 2
    local ft = cfg.fadeTime
    if type(ft) ~= "number" then
        ft = dur * (1 - (g.fadeStart or 0.7))
    end
    if ft < 0 then ft = 0 end
    if ft > dur then ft = dur end
    if dur <= 0 then return 1 end
    return (dur - ft) / dur
end

-- Nameplate-anchored strings are positioned with SetPoint offsets against
-- the plate itself - never by measuring it, which is forbidden. The frame is
-- forced to scale 1 so those offsets stay in honest screen pixels rather than
-- being multiplied by a per-frame scale.
local function isNameplateMode(cfg)
    return cfg and cfg.anchor == "nameplate"
        and ns.Nameplates and ns.Nameplates.available
end
ns.IsNameplateCfg = isNameplateMode

local ANCHOR_FOR_ALIGN = {
    LEFT   = "BOTTOMLEFT",
    CENTER = "BOTTOM",
    RIGHT  = "BOTTOMRIGHT",
}

--------------------------------------------------------------------------
-- Frame construction
--------------------------------------------------------------------------

function Engine:BuildFrame(name)
    if not ns.db then return end
    local cfgRaw = ns.db.frames[name]
    if not cfgRaw then return end

    local df = self.frames[name]
    if not df then
        df = {
            name   = name,
            pool   = {},
            active = {},
        }
        local f = CreateFrame("Frame", "JCT_Frame_" .. name, UIParent)
        f:SetClampedToScreen(true)
        f:SetMovable(true)
        f:EnableMouse(false)
        f.jctName = name
        df.frame = f

        -- Mover overlay, only visible while unlocked.
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(f)
        if bg.SetColorTexture then
            bg:SetColorTexture(0.1, 0.5, 0.9, 0.18)
        else
            bg:SetTexture(0.1, 0.5, 0.9, 0.18)
        end
        bg:Hide()
        df.bg = bg

        local label = f:CreateFontString(nil, "OVERLAY")
        ns.SafeSetFont(label, [[Fonts\FRIZQT__.TTF]], 13, "OUTLINE")
        label:SetPoint("TOP", f, "TOP", 0, -4)
        label:SetTextColor(1, 1, 1)
        label:Hide()
        df.label = label

        self.frames[name] = df
    end

    local cfg = resolve(name)
    cfg.fadeStart = fadeFraction(cfg, ns.db.general)
    df.cfg = cfg

    local f = df.frame
    f:SetSize(cfg.width, cfg.height)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", cfgRaw.x, cfgRaw.y)
    f:SetFrameStrata(ns.db.general.strata or "MEDIUM")
    f:SetScale(isNameplateMode(cfg) and 1 or cfg.scale)
    f:SetAlpha(ns.db.general.alpha or 1)
    if df.label then
        df.label:SetText((ns.FRAME_LABELS[name] or name) .. "  " .. floor(cfg.width) .. "x" .. floor(cfg.height))
    end

    -- While unlocked, even disabled frames stay visible so they can be
    -- positioned. Without the `self.unlocked` term, dragging a disabled
    -- frame makes it vanish the moment BuildFrame runs on drag stop.
    if cfgRaw.enabled or self.unlocked then f:Show() else f:Hide() end

    -- Invalidate the font cache on every pooled string so the new settings
    -- are picked up on next use.
    for i = 1, #df.pool do
        df.pool[i].__jctPath = nil
    end
end

function Engine:BuildAll()
    if not ns.db then return end
    for i = 1, #ns.FRAME_ORDER do
        self:BuildFrame(ns.FRAME_ORDER[i])
    end
    if self.unlocked then self:SetUnlocked(true) end
end

--------------------------------------------------------------------------
-- FontString pool
--------------------------------------------------------------------------

local function acquire(df)
    local fs = tremove(df.pool)
    if not fs then
        fs = df.frame:CreateFontString(nil, "OVERLAY")
    end
    fs:Show()
    return fs
end

local function release(df, rec)
    local fs = rec.fs
    fs:Hide()
    fs:ClearAllPoints()
    fs:SetText("")
    fs:SetAlpha(1)
    if rec.crit then
        -- SetTextHeight was used during the pop, so our cached tuple is
        -- stale. Force a fresh SetFont next time this string is used.
        fs.__jctPath = nil
    end
    df.pool[#df.pool + 1] = fs
    rec.fs = nil
end

--------------------------------------------------------------------------
-- Motion paths. Each returns x, y in frame-local space, measured from the
-- frame's bottom anchor corner.
--------------------------------------------------------------------------

local function pathUp(rec, p)
    return rec.baseX, rec.h * p
end

local function pathDown(rec, p)
    return rec.baseX, rec.h * (1 - p)
end

-- Sideways parabola with its vertex at mid height: the number leaves the
-- anchor line, bulges out to the full frame width halfway up, and comes back
-- in as it fades. Two multiplies per frame.
local function pathFountain(rec, p)
    local y = rec.up and (rec.h * p) or (rec.h * (1 - p))
    local dy = y - rec.midY
    local dx = (rec.midY * rec.midY - dy * dy) / rec.fourA
    if dx < 0 then dx = 0 end
    return rec.baseX + dx * rec.sign, y
end

local function pathHorizontal(rec, p)
    return rec.baseX + rec.w * p * rec.sign, rec.rowY
end

local function pathStatic(rec, _)
    return rec.baseX, rec.rowY
end

-- Lob: thrown upward, decelerating, falling back. This is the shape the
-- game engine uses for its own world text, and it suits nameplate mode.
local function pathGravity(rec, p)
    return rec.baseX + rec.w * 0.45 * p * rec.sign, 4 * rec.h * p * (1 - p)
end

-- Straight line up and out at an angle.
local function pathDiagonal(rec, p)
    return rec.baseX + rec.w * p * rec.sign, rec.h * p
end

-- Radiates outward on a per-message angle, biased upward. Good for AoE:
-- simultaneous hits scatter instead of forming a column.
local function pathBurst(rec, p)
    return rec.baseX + rec.burstX * p, rec.burstY * p
end

-- Rises with a gentle sideways sway. Organic rather than mechanical.
local function pathWobble(rec, p)
    return rec.baseX + math.sin(p * 6.2832 * 1.5) * rec.wobbleAmp, rec.h * p
end

-- Rises fast, overshoots, settles. The damping term fades with p so it
-- stops moving by the time it has faded out.
local function pathBounce(rec, p)
    local ease = 1 - (1 - p) * (1 - p)
    return rec.baseX, rec.h * (ease + math.sin(p * 9) * 0.06 * (1 - p))
end

local PATHS = {
    up         = pathUp,
    down       = pathDown,
    gravity    = pathGravity,
    diagonal   = pathDiagonal,
    burst      = pathBurst,
    wobble     = pathWobble,
    bounce     = pathBounce,
    fountain   = pathFountain,
    horizontal = pathHorizontal,
    static     = pathStatic,
}

--------------------------------------------------------------------------
-- The driver
--------------------------------------------------------------------------

local driver = CreateFrame("Frame", "JCT_Driver")
driver:Hide()
Engine.driver = driver


local function animate(df, rec, p)
    local path = PATHS[rec.path] or pathUp
    local x, y = path(rec, p)

    if rec.worldAnchor then
        -- Offsets against the plate, never coordinates read from it. The
        -- text tracks the unit for free because the anchor does the work.
        rec.fs:SetPoint("CENTER", rec.plate, "CENTER",
                        rec.npOffsetX + x, rec.npOffsetY + y)
    else
        rec.fs:SetPoint(rec.anchor, df.frame, rec.anchor, x, y)
    end

    -- fade
    local fadeStart = rec.fadeStart
    if p >= fadeStart then
        local a = (1 - p) / (1 - fadeStart)
        if a < 0 then a = 0 end
        rec.fs:SetAlpha(a)
    elseif rec.alphaSet ~= 1 then
        rec.fs:SetAlpha(1)
        rec.alphaSet = 1
    end

    -- crit pop
    if rec.pop then
        if rec.elapsed < POP_TIME then
            local t = rec.elapsed / POP_TIME
            local scale = 1 + POP_OVERSHOOT * (1 - t)
            rec.fs:SetTextHeight(rec.h0 * scale)
        elseif not rec.popDone then
            rec.fs:SetTextHeight(rec.h0)
            rec.popDone = true
        end
    end
end

driver:SetScript("OnUpdate", function(self, elapsed)
    local anyActive = false
    local frames = Engine.frames
    for _, df in pairs(frames) do
        local active = df.active
        local n = #active
        if n > 0 then
            for i = n, 1, -1 do
                local rec = active[i]
                rec.elapsed = rec.elapsed + elapsed
                local p = rec.elapsed / rec.duration
                -- A dead or departed unit leaves its plate parked where it
                -- was, so the number carries on and fades out normally -
                -- which is the whole point when you one-shot something.
                -- Only a plate that has been handed to a DIFFERENT unit has
                -- to be abandoned, because it physically moves to that unit
                -- and would drag the text across the screen with it.
                if rec.worldAnchor
                   and ns.Nameplates:AnchorState(rec.plate, rec.plateGUID) == "stolen" then
                    release(df, rec)
                    tremove(active, i)
                elseif p >= 1 then
                    release(df, rec)
                    tremove(active, i)
                else
                    animate(df, rec, p)
                    anyActive = true
                end
            end
        end
    end
    if not anyActive then
        self:Hide()
    end
end)

--------------------------------------------------------------------------
-- Adding a message
--------------------------------------------------------------------------

-- opts: crit (bool), sizeOverride (number)
function Engine:Add(frameName, text, r, g, b, opts)
    if not ns.db or not ns.db.enabled then return end
    local df = self.frames[frameName]
    if not df then return end
    local cfgRaw = ns.db.frames[frameName]
    if not cfgRaw or not cfgRaw.enabled then return end
    if not text or text == "" then return end

    local cfg = df.cfg
    if not cfg then return end

    opts = opts or false
    local crit = opts and opts.crit or false

    -- Nameplate anchoring. Resolved once, at spawn: if the unit has no plate
    -- up we either fall back to the frame's fixed position or drop the
    -- message, but we never wait around hoping a plate appears later.
    local worldAnchor, plateGUID, plate = false, nil, nil
    if isNameplateMode(cfg) then
        local guid = opts and opts.anchorGUID
        plate = guid and ns.Nameplates:Get(guid) or nil
        if plate then
            worldAnchor, plateGUID = true, guid
        end
        if not worldAnchor and not cfg.npFallback then return end
    end

    local size = (opts and opts.sizeOverride) or cfg.fontSize
    if crit then size = size * cfg.critScale end
    size = floor(size + 0.5)
    if size > ns.MAX_FONT_SIZE then size = ns.MAX_FONT_SIZE end

    local fs = acquire(df)
    -- SafeSetFont returns the size it actually applied; use that for the pop
    -- animation so a clamped crit settles at the size it was drawn at.
    size = ns.SafeSetFont(fs, cfg.fontPath, size, cfg.outline) or size
    fs:SetText(text)
    fs:SetTextColor(r or 1, g or 1, b or 1)
    if cfg.shadow then
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
    fs:SetJustifyH(cfg.align)
    fs:SetAlpha(1)

    local active = df.active
    local w, h = cfg.width, cfg.height

    -- Stagger / curve sign
    local sign = 1
    if cfg.curve == "left" then
        sign = -1
    elseif cfg.curve == "alternate" then
        df.flip = not df.flip
        sign = df.flip and 1 or -1
    end

    local baseX = 0
    if cfg.stagger and cfg.stagger > 0 then
        baseX = random(-cfg.stagger, cfg.stagger)
    end

    local rec = {
        fs        = fs,
        elapsed   = 0,
        duration  = cfg.duration,
        fadeStart = cfg.fadeStart,
        path      = cfg.animation,
        anchor    = ANCHOR_FOR_ALIGN[cfg.align] or "BOTTOM",
        w         = w,
        h         = h,
        baseX     = baseX,
        sign      = sign,
        crit      = crit,
        h0        = size,
        pop       = crit and cfg.critPop or false,
        popDone   = false,
        alphaSet  = 1,
        up        = (cfg.animation ~= "down"),
        worldAnchor = worldAnchor,
        plateGUID = plateGUID,
        plate     = plate,
        npOffsetX = cfg.npOffsetX,
        npOffsetY = cfg.npOffsetY,
    }

    if cfg.animation == "burst" then
        -- Biased upward: a spread of roughly 40 to 140 degrees.
        local ang = (40 + random(0, 100)) * 0.0174533
        rec.burstX = math.cos(ang) * (w * 0.5) * sign
        rec.burstY = math.sin(ang) * h
    elseif cfg.animation == "wobble" then
        rec.wobbleAmp = w * 0.18
    elseif cfg.animation == "fountain" then
        rec.midY  = h / 2
        rec.fourA = (rec.midY * rec.midY) / (w > 0 and w or 1)
    elseif cfg.animation == "horizontal" or cfg.animation == "static" then
        local rowH = size + MIN_GAP_PX
        local maxRows = floor(h / rowH)
        if maxRows < 1 then maxRows = 1 end
        local row = #active % maxRows
        rec.rowY = row * rowH
    end

    -- Time-domain spacing for the vertical styles.
    local a = cfg.animation
    if a == "up" or a == "down" or a == "fountain" or a == "diagonal"
       or a == "wobble" or a == "bounce" then
        local perPixel = cfg.duration / (h > 0 and h or 1)
        local gap = (size + MIN_GAP_PX) * perPixel
        -- Only space against strings sharing the same anchor. Numbers over
        -- one mob must not push numbers over a different mob out of the way.
        local prev = 0
        for i = #active, 1, -1 do
            local older = active[i]
            if older.plateGUID == plateGUID then
                local need = prev + gap
                if older.elapsed < need then
                    older.elapsed = need
                else
                    break
                end
                prev = older.elapsed
            end
        end
    end

    active[#active + 1] = rec

    -- Cap the number of simultaneous strings.
    --
    -- In nameplate mode the cap has to be counted PER UNIT, not per frame:
    -- hitting six mobs with one Volley would otherwise blow through a
    -- frame-wide cap instantly and evict whichever mob happened to be
    -- oldest, rather than thinning out the crowded one.
    local limit = cfg.maxLines or 12
    if plateGUID then
        local mine = 0
        for i = #active, 1, -1 do
            if active[i].plateGUID == plateGUID then mine = mine + 1 end
        end
        while mine > limit do
            for i = 1, #active do
                if active[i].plateGUID == plateGUID then
                    release(df, active[i])
                    tremove(active, i)
                    break
                end
            end
            mine = mine - 1
        end
    else
        local overflow = #active - limit
        while overflow > 0 do
            local oldest = active[1]
            if oldest then
                release(df, oldest)
                tremove(active, 1)
            end
            overflow = overflow - 1
        end
    end

    animate(df, rec, 0)
    if not driver:IsShown() then driver:Show() end
end

-- Used by the router to decide whether merging has to be split per unit.
function Engine:IsNameplateFrame(frameName)
    local df = self.frames[frameName]
    return df and df.cfg and isNameplateMode(df.cfg) or false
end

function Engine:ClearAll()
    for _, df in pairs(self.frames) do
        for i = #df.active, 1, -1 do
            release(df, df.active[i])
            tremove(df.active, i)
        end
    end
    driver:Hide()
end

--------------------------------------------------------------------------
-- Unlock / drag mode
--------------------------------------------------------------------------

local function onDragStart(self)
    self:StartMoving()
end

local function onDragStop(self)
    self:StopMovingOrSizing()
    local name = self.jctName
    if not name or not ns.db then return end
    -- Convert back to a CENTER-relative offset so it survives resolution
    -- changes and UI scale.
    -- SetPoint offsets live in this frame's own coordinate space, so the
    -- pixel delta has to be divided by THIS frame's effective scale, not
    -- UIParent's. Getting that wrong makes a scaled frame jump on every drag.
    if self.IsAnchoringRestricted and self:IsAnchoringRestricted() then return end
    local scale = self:GetEffectiveScale()
    local uiScale = UIParent:GetEffectiveScale()
    local ok, cx, cy = pcall(self.GetCenter, self)
    if not ok then return end
    local ux, uy = UIParent:GetCenter()
    if not cx or not ux then return end
    local x = (cx * scale - ux * uiScale) / scale
    local y = (cy * scale - uy * uiScale) / scale
    ns.db.frames[name].x = floor(x + 0.5)
    ns.db.frames[name].y = floor(y + 0.5)
    Engine:BuildFrame(name)
    if ns.Options and ns.Options.Refresh then ns.Options:Refresh() end
end

function Engine:SetUnlocked(state)
    self.unlocked = state and true or false
    for name, df in pairs(self.frames) do
        local f = df.frame
        if self.unlocked then
            f:Show()
            f:EnableMouse(true)
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", onDragStart)
            f:SetScript("OnDragStop", onDragStop)
            df.bg:Show()
            df.label:Show()
        else
            f:EnableMouse(false)
            f:RegisterForDrag()
            f:SetScript("OnDragStart", nil)
            f:SetScript("OnDragStop", nil)
            df.bg:Hide()
            df.label:Hide()
            if ns.db and not ns.db.frames[name].enabled then f:Hide() end
        end
    end
end

--------------------------------------------------------------------------
-- Alignment grid (32px boxes, red centre axes)
--------------------------------------------------------------------------

local grid

function Engine:ToggleGrid()
    if grid and grid:IsShown() then
        grid:Hide()
        return false
    end
    if not grid then
        grid = CreateFrame("Frame", "JCT_Grid", UIParent)
        grid:SetAllPoints(UIParent)
        grid:SetFrameStrata("BACKGROUND")
        local w, h = UIParent:GetWidth(), UIParent:GetHeight()
        local step = 32
        local function line(x1, y1, x2, y2, r, g, b, a, thick)
            local t = grid:CreateTexture(nil, "BACKGROUND")
            if t.SetColorTexture then t:SetColorTexture(r, g, b, a) else t:SetTexture(r, g, b, a) end
            t:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x1, y1)
            t:SetSize((x2 - x1) > 0 and (x2 - x1) or thick, (y2 - y1) > 0 and (y2 - y1) or thick)
        end
        local n = 0
        local x = 0
        while x <= w do
            n = n + 1
            local a, r, g, b, thick = 0.35, 0.6, 0.6, 0.6, 1
            if n % 4 == 0 then a, r, g, b = 0.5, 1, 1, 0.2 end
            line(x, 0, x, h, r, g, b, a, thick)
            x = x + step
        end
        n = 0
        local y = 0
        while y <= h do
            n = n + 1
            local a, r, g, b, thick = 0.35, 0.6, 0.6, 0.6, 1
            if n % 4 == 0 then a, r, g, b = 0.5, 1, 1, 0.2 end
            line(0, y, w, y, r, g, b, a, thick)
            y = y + step
        end
        line(w / 2 - 1, 0, w / 2 + 1, h, 1, 0.1, 0.1, 0.8, 2)
        line(0, h / 2 - 1, w, h / 2 + 1, 1, 0.1, 0.1, 0.8, 2)
    end
    grid:Show()
    return true
end
