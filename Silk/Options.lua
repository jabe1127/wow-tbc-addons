-- Silk : Options ----------------------------------------------------------
-- A custom-skinned panel: smoked glass, pill toggles, capsule sliders,
-- segmented controls, and color swatches. No Blizzard templates. Also the
-- layout mode (drag frames + individual text handles) and /silk commands.

local ADDON, ns = ...

local PANEL_W, PANEL_H = 560, 600
local RAIL_W = 122
local PADX = 4
local CW = PANEL_W - 152 - 20

local panel
local widgets = {}
local tabs = {}
local selectTab
local overlays

-- little helpers ----------------------------------------------------------

local function accent()
    local a = ns.db.accent
    return a.r, a.g, a.b
end

-- Dark text on a light accent pill must NOT carry a black outline: the outline
-- swallows the glyph and reads as a smudge. flags = "" for dark-on-light.
local function pfont(fs, size, flags)
    fs:SetFont("Fonts\\ARIALN.TTF", size, flags == nil and "OUTLINE" or flags)
    fs:SetShadowOffset(0, 0)
end

local INK = { 0.05, 0.06, 0.09 }   -- text that sits on accent

local function glass(parent, style)
    local h = ns.Capsule(parent)
    local bg = h:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1)
    bg:SetVertexColor(0.09, 0.10, 0.13, 0.97)
    h:AddMasked(bg)
    local gl = h:CreateTexture(nil, "OVERLAY")
    gl:SetAllPoints()
    gl:SetTexture(ns.TEX.gloss)
    gl:SetAlpha(0.05)
    h:AddMasked(gl)
    h:SetCapStyle(style or "soft")
    h.bg = bg
    return h
end

local function glassPanel(parent)
    local holder = CreateFrame("Frame", nil, parent)
    local mask = holder:CreateMaskTexture()
    mask:SetAllPoints(holder)
    mask:SetTexture(ns.TEX.panelMask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    holder.mask = mask
    holder.Add = function(self, tex)
        tex:AddMaskTexture(self.mask)
    end
    local bg = holder:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1)
    bg:SetVertexColor(0.055, 0.062, 0.080, 0.975)
    holder:Add(bg)
    local gl = holder:CreateTexture(nil, "OVERLAY")
    gl:SetAllPoints()
    gl:SetTexture(ns.TEX.gloss)
    gl:SetAlpha(0.05)
    holder:Add(gl)
    return holder
end

local function refreshAllWidgets()
    for i = 1, #widgets do
        local w = widgets[i]
        if w.Refresh then w:Refresh() end
    end
    if panel then
        if panel.title then panel.title:SetTextColor(accent()) end
        if panel.currentTab and selectTab then selectTab(panel.currentTab) end
    end
end

-- color picker -------------------------------------------------------------
-- Silk's own, rather than ColorPickerFrame: the Blizzard picker's callback
-- contract differs across client versions and silently does nothing when it
-- doesn't match. This one is guaranteed to fire.

local cpicker

local PRESETS = {
    { 0.61, 0.90, 1.00 }, { 1.00, 1.00, 1.00 }, { 0.92, 0.94, 0.97 },
    { 0.62, 0.66, 0.72 }, { 0.36, 0.85, 0.52 }, { 0.97, 0.78, 0.32 },
    { 0.92, 0.31, 0.33 }, { 0.78, 0.55, 1.00 }, { 1.00, 0.62, 0.32 },
    { 0.35, 0.62, 1.00 }, { 1.00, 0.78, 0.26 }, { 0.06, 0.07, 0.10 },
}

local function chanSlider(parent, y, label, letter)
    local lb = ns.NewText(parent)
    pfont(lb, 11)
    lb:SetPoint("TOPLEFT", 14, y)
    lb:SetText(letter)
    lb:SetTextColor(0.72, 0.76, 0.83)

    local val = ns.NewText(parent)
    pfont(val, 11)
    val:SetPoint("TOPRIGHT", -14, y)
    val:SetTextColor(0.85, 0.88, 0.94)

    local track = glass(parent, "capsule")
    track:SetSize(150, 6)
    track:SetPoint("TOPLEFT", 30, y - 5)
    local fill = track:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT")
    fill:SetPoint("BOTTOMLEFT")
    fill:SetColorTexture(1, 1, 1)
    fill:SetWidth(0.001)
    track:AddMasked(fill)
    local knob = track:CreateTexture(nil, "OVERLAY", nil, 3)
    knob:SetSize(13, 13)
    knob:SetTexture(ns.TEX.dot)
    knob:SetVertexColor(0.95, 0.97, 1)

    local hit = CreateFrame("Frame", nil, parent)
    hit:SetPoint("TOPLEFT", track, "TOPLEFT", -6, 9)
    hit:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", 6, -9)
    hit:EnableMouse(true)

    local o = { track = track, fill = fill, knob = knob, val = val, hit = hit, key = label }
    function o:Set(v)
        local t = math.max(0, math.min(1, v))
        local tw = self.track:GetWidth()
        self.fill:SetWidth(math.max(0.001, tw * t))
        self.knob:ClearAllPoints()
        self.knob:SetPoint("CENTER", self.track, "LEFT", tw * t, 0)
        self.val:SetText(math.floor(t * 255 + 0.5))
    end
    return o
end

local function buildColorPicker()
    local p = CreateFrame("Frame", "SilkColorPicker", UIParent)
    p:SetSize(210, 296)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:SetMovable(true)
    p:EnableMouse(true)
    p:SetClampedToScreen(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", function(s) s:StartMoving() end)
    p:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    local skin = glassPanel(p)
    skin:SetAllPoints()

    local title = ns.NewText(skin)
    pfont(title, 13)
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Color")

    -- live preview
    local prev = ns.Capsule(p)
    prev:SetSize(60, 20)
    prev:SetPoint("TOPRIGHT", -14, -10)
    local ptex = prev:CreateTexture(nil, "ARTWORK")
    ptex:SetAllPoints()
    ptex:SetColorTexture(1, 1, 1)
    prev:AddMasked(ptex)
    prev:SetCapStyle("capsule")
    p.preview = ptex

    p.chan = {
        r = chanSlider(p, -44, "r", "R"),
        g = chanSlider(p, -70, "g", "G"),
        b = chanSlider(p, -96, "b", "B"),
    }

    -- hex entry
    local hexlb = ns.NewText(p)
    pfont(hexlb, 11)
    hexlb:SetPoint("TOPLEFT", 14, -126)
    hexlb:SetText("Hex")
    hexlb:SetTextColor(0.72, 0.76, 0.83)

    local box = glass(p, "soft")
    box:SetSize(96, 22)
    box:SetPoint("TOPLEFT", 48, -122)
    local eb = CreateFrame("EditBox", nil, box)
    eb:SetAllPoints()
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(7)
    eb:SetTextInsets(8, 8, 0, 0)
    eb:SetFont("Fonts\\ARIALN.TTF", 12, "")
    eb:SetTextColor(0.92, 0.94, 0.97)
    p.hex = eb

    -- presets
    local plb = ns.NewText(p)
    pfont(plb, 11)
    plb:SetPoint("TOPLEFT", 14, -154)
    plb:SetText("Presets")
    plb:SetTextColor(0.72, 0.76, 0.83)

    p.presets = {}
    for i = 1, #PRESETS do
        local sw = CreateFrame("Button", nil, p)
        sw:SetSize(18, 18)
        local col = (i - 1) % 6
        local row = math.floor((i - 1) / 6)
        sw:SetPoint("TOPLEFT", 14 + col * 30, -172 - row * 24)
        local t = sw:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints()
        t:SetTexture(ns.TEX.dot)
        t:SetVertexColor(PRESETS[i][1], PRESETS[i][2], PRESETS[i][3])
        local ring = sw:CreateTexture(nil, "OVERLAY")
        ring:SetPoint("TOPLEFT", -2, 2)
        ring:SetPoint("BOTTOMRIGHT", 2, -2)
        ring:SetTexture(ns.TEX.ring)
        ring:SetVertexColor(1, 1, 1, 0.18)
        sw.rgb = PRESETS[i]
        p.presets[i] = sw
    end

    -- buttons
    local function mkBtn(text, xoff, w)
        local b = glass(p, "capsule")
        b:SetSize(w, 24)
        b:SetPoint("BOTTOMLEFT", xoff, 12)
        b:EnableMouse(true)
        local lb = ns.NewText(b)
        pfont(lb, 12, "")
        lb:SetPoint("CENTER")
        lb:SetText(text)
        b.label = lb
        return b
    end
    p.okBtn = mkBtn("Apply", 14, 88)
    p.cancelBtn = mkBtn("Cancel", 110, 86)

    p:Hide()
    return p
end

function ns.ShowColorPicker(r, g, b, onChange, onCancel)
    if not cpicker then cpicker = buildColorPicker() end
    local p = cpicker
    local cur = { r = r or 1, g = g or 1, b = b or 1 }
    local start = { r = cur.r, g = cur.g, b = cur.b }

    local function paint(live)
        p.preview:SetVertexColor(cur.r, cur.g, cur.b)
        p.chan.r:Set(cur.r)
        p.chan.g:Set(cur.g)
        p.chan.b:Set(cur.b)
        local ar, ag, ab = accent()
        p.chan.r.fill:SetVertexColor(ar, ag, ab, 0.9)
        p.chan.g.fill:SetVertexColor(ar, ag, ab, 0.9)
        p.chan.b.fill:SetVertexColor(ar, ag, ab, 0.9)
        if not p.hex:HasFocus() then
            p.hex:SetText(string.format("%02X%02X%02X",
                math.floor(cur.r * 255 + 0.5),
                math.floor(cur.g * 255 + 0.5),
                math.floor(cur.b * 255 + 0.5)))
        end
        if live and onChange then onChange(cur.r, cur.g, cur.b) end
    end

    -- channel dragging
    for key, s in pairs(p.chan) do
        local function fromCursor()
            local cx = GetCursorPosition() / s.track:GetEffectiveScale()
            local t = (cx - s.track:GetLeft()) / s.track:GetWidth()
            if t < 0 then t = 0 elseif t > 1 then t = 1 end
            cur[key] = t
            paint(true)
        end
        s.hit:SetScript("OnMouseDown", function(h)
            fromCursor()
            h:SetScript("OnUpdate", fromCursor)
        end)
        s.hit:SetScript("OnMouseUp", function(h)
            h:SetScript("OnUpdate", nil)
        end)
    end

    p.hex:SetScript("OnEnterPressed", function(e)
        local txt = (e:GetText() or ""):gsub("#", ""):gsub("%s", "")
        local hr, hg, hb = txt:match("^(%x%x)(%x%x)(%x%x)$")
        if hr then
            cur.r = tonumber(hr, 16) / 255
            cur.g = tonumber(hg, 16) / 255
            cur.b = tonumber(hb, 16) / 255
            paint(true)
        end
        e:ClearFocus()
        paint(false)
    end)
    p.hex:SetScript("OnEscapePressed", function(e) e:ClearFocus() paint(false) end)

    for i = 1, #p.presets do
        local sw = p.presets[i]
        sw:SetScript("OnClick", function(s)
            cur.r, cur.g, cur.b = s.rgb[1], s.rgb[2], s.rgb[3]
            paint(true)
        end)
    end

    p.okBtn:SetScript("OnMouseDown", function()
        p:Hide()
        if onChange then onChange(cur.r, cur.g, cur.b) end
    end)
    p.cancelBtn:SetScript("OnMouseDown", function()
        p:Hide()
        if onCancel then
            onCancel(start.r, start.g, start.b)
        elseif onChange then
            onChange(start.r, start.g, start.b)
        end
    end)

    local ar, ag, ab = accent()
    p.okBtn.bg:SetVertexColor(ar, ag, ab, 0.92)
    p.okBtn.label:SetTextColor(INK[1], INK[2], INK[3])
    p.cancelBtn.bg:SetVertexColor(1, 1, 1, 0.10)
    p.cancelBtn.label:SetTextColor(0.85, 0.88, 0.94)

    p:ClearAllPoints()
    if panel and panel:IsShown() then
        p:SetPoint("TOPLEFT", panel, "TOPRIGHT", 10, 0)
    else
        p:SetPoint("CENTER", UIParent, "CENTER", 260, 0)
    end
    paint(false)
    p:Show()
    p:Raise()
end

local function openPicker(r0, g0, b0, cb)
    ns.ShowColorPicker(r0, g0, b0, cb)
end

-- dropdown + font picker ---------------------------------------------------

local dropdown

local function ensureDropdown()
    if dropdown then return dropdown end
    local d = CreateFrame("Frame", nil, UIParent)
    d:SetFrameStrata("FULLSCREEN_DIALOG")
    d:SetSize(230, 220)
    d:EnableMouse(true)
    local skin = glassPanel(d)
    skin:SetAllPoints()
    local sf = CreateFrame("ScrollFrame", nil, d)
    sf:SetPoint("TOPLEFT", 8, -8)
    sf:SetPoint("BOTTOMRIGHT", -8, 8)
    local ch = CreateFrame("Frame", nil, sf)
    ch:SetSize(214, 10)
    sf:SetScrollChild(ch)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(s, delta)
        local maxs = math.max(0, ch:GetHeight() - s:GetHeight())
        local nv = s:GetVerticalScroll() - delta * 40
        if nv < 0 then nv = 0 elseif nv > maxs then nv = maxs end
        s:SetVerticalScroll(nv)
    end)
    d.sf, d.child, d.rows = sf, ch, {}

    -- a visible thumb, so a long list *looks* scrollable instead of looking
    -- like ten fonts
    local thumb = d:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(ns.TEX.dot)
    thumb:SetVertexColor(1, 1, 1, 0.22)
    thumb:SetWidth(3)
    d.thumb = thumb
    function d:UpdateThumb()
        local vh, chh = sf:GetHeight(), ch:GetHeight()
        if chh <= vh + 1 then
            thumb:Hide()
            return
        end
        local frac = vh / chh
        local th = math.max(18, vh * frac)
        local maxScroll = chh - vh
        local t = (sf:GetVerticalScroll() or 0) / maxScroll
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 2, -t * (vh - th))
        thumb:Show()
    end
    local baseWheel = sf:GetScript("OnMouseWheel")
    sf:SetScript("OnMouseWheel", function(s, delta)
        baseWheel(s, delta)
        d:UpdateThumb()
    end)

    d:Hide()
    dropdown = d
    return d
end

local ROW = 22

local function openDropdown(owner, entries, current, onPick)
    local d = ensureDropdown()
    if d.search and not d.__refilter then
        d.search:Hide()
        d.sf:ClearAllPoints()
        d.sf:SetPoint("TOPLEFT", 4, -6)
        d.sf:SetPoint("BOTTOMRIGHT", -4, 6)
    end
    for i = 1, #entries do
        local e = entries[i]
        local r = d.rows[i]
        if not r then
            r = CreateFrame("Button", nil, d.child)
            r:SetHeight(ROW)
            local hl = r:CreateTexture(nil, "BACKGROUND")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1)
            hl:SetAlpha(0)
            local fs = r:CreateFontString(nil, "OVERLAY")
            fs:SetPoint("LEFT", 6, 0)
            pfont(fs, 13, "")
            r.fs, r.hl = fs, hl
            r:SetScript("OnEnter", function(s) s.hl:SetAlpha(0.10) end)
            r:SetScript("OnLeave", function(s) s.hl:SetAlpha(0) end)
            d.rows[i] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
        r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW)
        -- font first: SetText on a fontstring with no font raises an error
        if e.path and e.path ~= "" then
            if r.fs:SetFont(e.path, 13, "") == false then
                r.fs:SetFont("Fonts\\ARIALN.TTF", 13, "")
            end
        else
            r.fs:SetFont("Fonts\\ARIALN.TTF", 13, "")
        end
        r.fs:SetText(e.name)
        if e.path == current then
            r.fs:SetTextColor(accent())
        else
            r.fs:SetTextColor(0.85, 0.88, 0.94)
        end
        r:SetScript("OnClick", function()
            d:Hide()
            onPick(e.path)
        end)
        r:Show()
    end
    for i = #entries + 1, #d.rows do d.rows[i]:Hide() end

    d.child:SetHeight(math.max(10, #entries * ROW))
    d:ClearAllPoints()
    d:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -4)
    local searchH = d.search and d.search:IsShown() and 26 or 0
    d:SetHeight(math.min(384, #entries * ROW + 16 + searchH))
    d.sf:SetVerticalScroll(0)
    if d.UpdateThumb then d:UpdateThumb() end
    d:Show()
    d:Raise()
end

-- The font list runs long, so the picker gets a filter box: type a few
-- letters and the list narrows as you go. Every row draws in its own face,
-- which is the only honest way to choose a font.
local function openFontDropdown(owner, entries, current, onPick)
    local d = ensureDropdown()
    if not d.search then
        local box = glass(d, "soft")
        box:SetHeight(22)
        box:SetPoint("TOPLEFT", 6, -5)
        box:SetPoint("TOPRIGHT", -6, -5)
        local eb = CreateFrame("EditBox", nil, box)
        eb:SetAllPoints()
        eb:SetAutoFocus(false)
        eb:SetTextInsets(8, 8, 0, 0)
        eb:SetFont("Fonts\\ARIALN.TTF", 12, "")
        eb:SetTextColor(0.92, 0.94, 0.97)
        local hint = box:CreateFontString(nil, "OVERLAY")
        pfont(hint, 11, "")
        hint:SetPoint("LEFT", 8, 0)
        hint:SetText("filter…")
        hint:SetTextColor(0.55, 0.58, 0.66)
        eb:SetScript("OnTextChanged", function(e)
            hint:SetShown((e:GetText() or "") == "")
            if d.__refilter then d.__refilter(e:GetText() or "") end
        end)
        eb:SetScript("OnEscapePressed", function(e) e:ClearFocus() d:Hide() end)
        d.search, d.searchBox = box, eb
    end
    d.search:Show()
    d.searchBox:SetText("")
    d.sf:ClearAllPoints()
    d.sf:SetPoint("TOPLEFT", 4, -30)
    d.sf:SetPoint("BOTTOMRIGHT", -4, 6)
    d.__refilter = function(txt)
        txt = txt:lower()
        local filtered = {}
        for i = 1, #entries do
            if txt == "" or entries[i].name:lower():find(txt, 1, true) then
                filtered[#filtered + 1] = entries[i]
            end
        end
        openDropdown(owner, filtered, current, onPick)
        d.search:Show()
    end
    openDropdown(owner, entries, current, onPick)
    d.search:Show()
end

local function fontpicker(child, label, get, set, allowDefault)
    child.cursor = child.cursor - 32
    local y = child.cursor + 28
    local fs = child:CreateFontString(nil, "OVERLAY")
    pfont(fs, 12)
    fs:SetPoint("TOPLEFT", PADX, y - 7)
    fs:SetText(label)
    fs:SetTextColor(0.85, 0.88, 0.94)

    local b = glass(child, "capsule")
    b:SetSize(200, 24)
    b:SetPoint("TOPRIGHT", -PADX, y - 2)
    b:EnableMouse(true)
    local cur = b:CreateFontString(nil, "OVERLAY")
    cur:SetPoint("CENTER")
    pfont(cur, 13, "")

    local w = { get = get, cur = cur, skin = b }
    w.Refresh = function(s)
        local path = s.get()
        local name = (not path or path == "") and "Default" or ns.FontName(path)
        -- font before text, always
        local shown = (path and path ~= "") and path or ns.db.font
        if s.cur:SetFont(shown, 13, "") == false then
            s.cur:SetFont("Fonts\\ARIALN.TTF", 13, "")
        end
        s.cur:SetText(name)
        s.cur:SetTextColor(accent())
        s.skin.bg:SetVertexColor(1, 1, 1, 0.07)
    end
    b:SetScript("OnMouseDown", function()
        local entries = {}
        if allowDefault then entries[1] = { name = "Default", path = "" } end
        local l = ns.FontList()
        for i = 1, #l do entries[#entries + 1] = l[i] end
        local d = ensureDropdown()
        d.__refilter = nil
        openFontDropdown(b, entries, get(), function(path)
            d.__refilter = nil
            set(path)
            refreshAllWidgets()
            ns.ApplyAll()
        end)
    end)
    table.insert(widgets, w)
    w:Refresh()
    return w
end

-- widget kit --------------------------------------------------------------

local function header(child, text)
    child.cursor = child.cursor - 28
    local y = child.cursor + 22
    local fs = child:CreateFontString(nil, "OVERLAY")
    pfont(fs, 11)
    fs:SetPoint("TOPLEFT", PADX, y)
    fs:SetText(string.upper(text))
    local line = child:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1)
    line:SetVertexColor(1, 1, 1, 0.08)
    line:SetPoint("TOPLEFT", PADX, y - 15)
    line:SetPoint("TOPRIGHT", -PADX, y - 15)
    line:SetHeight(1)
    local w = { fs = fs }
    w.Refresh = function(s)
        s.fs:SetTextColor(accent())
    end
    table.insert(widgets, w)
    w:Refresh()
    child.cursor = child.cursor - 6
end

local function note(child, text)
    local y = child.cursor
    local fs = child:CreateFontString(nil, "OVERLAY")
    pfont(fs, 11)
    fs:SetPoint("TOPLEFT", PADX, y - 6)
    fs:SetWidth(CW - PADX * 2)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    fs:SetTextColor(0.58, 0.62, 0.70)
    child.cursor = y - 14 - fs:GetStringHeight()
end

local function toggle(child, label, get, set)
    child.cursor = child.cursor - 30
    local y = child.cursor + 26
    local fs = child:CreateFontString(nil, "OVERLAY")
    pfont(fs, 12)
    fs:SetPoint("TOPLEFT", PADX, y - 5)
    fs:SetText(label)
    fs:SetTextColor(0.85, 0.88, 0.94)

    local track = glass(child, "capsule")
    track:SetSize(40, 20)
    track:SetPoint("TOPRIGHT", -PADX, y - 2)
    track:EnableMouse(true)
    local knob = track:CreateTexture(nil, "OVERLAY", nil, 2)
    knob:SetSize(14, 14)
    knob:SetTexture(ns.TEX.dot)

    local w = { track = track, knob = knob, get = get }
    w.Refresh = function(s)
        local on = s.get()
        s.knob:ClearAllPoints()
        s.knob:SetPoint("LEFT", s.track, "LEFT", on and 23 or 3, 0)
        if on then
            local r, g, b = accent()
            s.track.bg:SetVertexColor(r, g, b, 0.35)
            s.knob:SetVertexColor(r, g, b, 1)
        else
            s.track.bg:SetVertexColor(1, 1, 1, 0.08)
            s.knob:SetVertexColor(0.55, 0.58, 0.66, 1)
        end
    end
    track:SetScript("OnMouseDown", function()
        set(not get())
        w:Refresh()
        ns.ApplyAll()
    end)
    table.insert(widgets, w)
    w:Refresh()
    return w
end

local function slider(child, label, minv, maxv, step, get, set, fmt)
    child.cursor = child.cursor - 42
    local y = child.cursor + 38
    local fs = child:CreateFontString(nil, "OVERLAY")
    pfont(fs, 12)
    fs:SetPoint("TOPLEFT", PADX, y - 4)
    fs:SetText(label)
    fs:SetTextColor(0.85, 0.88, 0.94)
    local val = child:CreateFontString(nil, "OVERLAY")
    pfont(val, 11)
    val:SetPoint("TOPRIGHT", -PADX, y - 5)

    -- click the number to type an exact value: dragging a knob to land on
    -- precisely 14 is the definition of clunky
    local valBtn = CreateFrame("Button", nil, child)
    valBtn:SetPoint("TOPRIGHT", -PADX + 4, y - 1)
    valBtn:SetSize(56, 18)
    local entry = CreateFrame("EditBox", nil, child)
    entry:SetPoint("TOPRIGHT", -PADX, y - 1)
    entry:SetSize(52, 18)
    entry:SetAutoFocus(true)
    entry:SetJustifyH("RIGHT")
    entry:SetFont("Fonts\\ARIALN.TTF", 12, "")
    entry:SetTextColor(0.61, 0.90, 1.00)
    entry:Hide()
    local function commitEntry()
        local n = tonumber((entry:GetText() or ""):gsub("%%", ""))
        entry:Hide()
        val:Show()
        if not n then return end
        if fmt == "pct" and n > 1.5 then n = n / 100 end
        if n < minv then n = minv elseif n > maxv then n = maxv end
        n = math.floor(n / step + 0.5) * step
        set(n)
        refreshAllWidgets()
        ns.ApplyAll()
    end
    entry:SetScript("OnEnterPressed", commitEntry)
    entry:SetScript("OnEscapePressed", function(e) e:Hide() val:Show() end)
    valBtn:SetScript("OnClick", function()
        local v = get() or minv
        entry:SetText(fmt == "pct" and tostring(math.floor(v * 100 + 0.5))
            or tostring(math.floor(v / step + 0.5) * step))
        val:Hide()
        entry:Show()
        entry:HighlightText()
    end)

    local track = glass(child, "capsule")
    track:SetSize(CW - PADX * 2, 6)
    track:SetPoint("TOPLEFT", PADX, y - 26)
    local fill = track:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT")
    fill:SetPoint("BOTTOMLEFT")
    fill:SetColorTexture(1, 1, 1)
    fill:SetWidth(0.001)
    track:AddMasked(fill)
    local knob = track:CreateTexture(nil, "OVERLAY", nil, 3)
    knob:SetSize(15, 15)
    knob:SetTexture(ns.TEX.dot)

    local hit = CreateFrame("Frame", nil, child)
    hit:SetPoint("TOPLEFT", track, "TOPLEFT", -6, 8)
    hit:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", 6, -8)
    hit:EnableMouse(true)

    local function fmtv(v)
        if fmt == "int" then return tostring(math.floor(v + 0.5)) end
        if fmt == "pct" then return tostring(math.floor(v * 100 + 0.5)) .. "%" end
        return string.format("%.2f", v)
    end

    local function place()
        local v = get()
        local t = (v - minv) / (maxv - minv)
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
        local tw = track:GetWidth()
        fill:SetWidth(math.max(0.001, tw * t))
        knob:ClearAllPoints()
        knob:SetPoint("CENTER", track, "LEFT", tw * t, 0)
        val:SetText(fmtv(v))
    end

    local w = {}
    w.Refresh = function()
        local r, g, b = accent()
        fill:SetVertexColor(r, g, b, 0.9)
        knob:SetVertexColor(0.95, 0.97, 1)
        val:SetTextColor(accent())
        place()
    end

    local dragging = false
    local lastApply = 0
    local function cursorValue()
        local cx = GetCursorPosition() / track:GetEffectiveScale()
        local t = (cx - track:GetLeft()) / track:GetWidth()
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
        local v = minv + t * (maxv - minv)
        if step and step > 0 then
            v = minv + math.floor((v - minv) / step + 0.5) * step
        end
        if v < minv then v = minv elseif v > maxv then v = maxv end
        return v
    end
    hit:SetScript("OnMouseDown", function(s)
        dragging = true
        set(cursorValue())
        place()
        s:SetScript("OnUpdate", function()
            if not dragging then return end
            local v = cursorValue()
            if v ~= get() then
                set(v)
                place()
                local t = GetTime()
                if t - lastApply > 0.08 then
                    lastApply = t
                    ns.ApplyAll()
                end
            end
        end)
    end)
    hit:SetScript("OnMouseUp", function(s)
        dragging = false
        s:SetScript("OnUpdate", nil)
        place()
        ns.ApplyAll()
    end)

    table.insert(widgets, w)
    w:Refresh()
    return w
end

local function seg(child, label, options, get, set, trackW)
    child.cursor = child.cursor - 32
    local y = child.cursor + 28
    local fs = child:CreateFontString(nil, "OVERLAY")
    pfont(fs, 12)
    fs:SetPoint("TOPLEFT", PADX, y - 7)
    fs:SetText(label)
    fs:SetTextColor(0.85, 0.88, 0.94)

    local track = glass(child, "capsule")
    local TW = trackW or 216
    track:SetSize(TW, 24)
    track:SetPoint("TOPRIGHT", -PADX, y - 2)
    track:EnableMouse(true)
    local n = #options
    local segW = TW / n

    local hi = ns.Capsule(track)
    hi:SetSize(segW - 4, 20)
    local hitex = hi:CreateTexture(nil, "ARTWORK")
    hitex:SetAllPoints()
    hitex:SetColorTexture(1, 1, 1)
    hi:AddMasked(hitex)
    hi:SetCapStyle("capsule")

    local labelLayer = CreateFrame("Frame", nil, track)
    labelLayer:SetAllPoints(track)

    local w = { labels = {}, hi = hi, hitex = hitex, get = get, options = options,
                track = track, segW = segW }
    for i = 1, n do
        local ol = labelLayer:CreateFontString(nil, "OVERLAY")
        pfont(ol, 11)
        ol:SetPoint("CENTER", track, "LEFT", segW * (i - 0.5), 0)
        ol:SetText(options[i][1])
        w.labels[i] = ol
    end
    w.Refresh = function(s)
        local v = s.get()
        local idx = 1
        for i = 1, #s.options do
            if s.options[i][2] == v then
                idx = i
                break
            end
        end
        s.hi:ClearAllPoints()
        s.hi:SetPoint("LEFT", s.track, "LEFT", s.segW * (idx - 1) + 2, 0)
        local r, g, b = accent()
        s.hitex:SetVertexColor(r, g, b, 0.95)
        for i = 1, #s.labels do
            if i == idx then
                pfont(s.labels[i], 11, "")           -- no outline over the accent
                s.labels[i]:SetTextColor(INK[1], INK[2], INK[3])
            else
                pfont(s.labels[i], 11)
                s.labels[i]:SetTextColor(0.70, 0.74, 0.81)
            end
        end
    end
    track:SetScript("OnMouseDown", function()
        local cx = GetCursorPosition() / track:GetEffectiveScale()
        local i = math.floor((cx - track:GetLeft()) / segW) + 1
        if i < 1 then i = 1 elseif i > n then i = n end
        set(options[i][2])
        w:Refresh()
        ns.ApplyAll()
    end)
    table.insert(widgets, w)
    w:Refresh()
    return w
end

local function swatch(child, label, get, set)
    child.cursor = child.cursor - 30
    local y = child.cursor + 26
    local fs = child:CreateFontString(nil, "OVERLAY")
    pfont(fs, 12)
    fs:SetPoint("TOPLEFT", PADX, y - 5)
    fs:SetText(label)
    fs:SetTextColor(0.85, 0.88, 0.94)

    local b = CreateFrame("Button", nil, child)
    b:SetSize(20, 20)
    b:SetPoint("TOPRIGHT", -PADX - 8, y - 2)
    local dot = b:CreateTexture(nil, "ARTWORK")
    dot:SetAllPoints()
    dot:SetTexture(ns.TEX.dot)
    local ring = b:CreateTexture(nil, "OVERLAY")
    ring:SetPoint("TOPLEFT", -2, 2)
    ring:SetPoint("BOTTOMRIGHT", 2, -2)
    ring:SetTexture(ns.TEX.ring)
    ring:SetVertexColor(1, 1, 1, 0.25)

    local w = { dot = dot, get = get }
    w.Refresh = function(s)
        local c = s.get()
        s.dot:SetVertexColor(c.r, c.g, c.b)
    end
    b:SetScript("OnClick", function()
        local c = get()
        openPicker(c.r, c.g, c.b, function(r, g, bl)
            set(r, g, bl)
            refreshAllWidgets()
            ns.ApplyAll()
        end)
    end)
    table.insert(widgets, w)
    w:Refresh()
    return w
end

local function button(child, label, onClick, wpx)
    child.cursor = child.cursor - 34
    local y = child.cursor + 28
    local b = glass(child, "capsule")
    b:SetSize(wpx or 150, 26)
    b:SetPoint("TOPLEFT", PADX, y - 2)
    b:EnableMouse(true)
    local lb = b:CreateFontString(nil, "OVERLAY")
    pfont(lb, 12, "")
    lb:SetPoint("CENTER")
    lb:SetText(label)

    local w = { skin = b, label = lb }
    w.Refresh = function(s)
        local r, g, bl = accent()
        s.skin.bg:SetVertexColor(r, g, bl, 0.92)
        s.label:SetTextColor(INK[1], INK[2], INK[3])
    end
    b:SetScript("OnEnter", function()
        local r, g, bl = accent()
        b.bg:SetVertexColor(r, g, bl, 1)
    end)
    b:SetScript("OnLeave", function()
        w:Refresh()
    end)
    b:SetScript("OnMouseDown", function()
        onClick(w)
    end)
    table.insert(widgets, w)
    w:Refresh()
    return w
end

-- tab contents ------------------------------------------------------------

-- A live sample at the top of the tab: every control below restyles it the
-- instant it changes, so nobody has to guess what a slider does or keep a
-- target alive to see their choices.
local preview
local function buildPreview(c)
    c.cursor = c.cursor - 96
    local host = CreateFrame("Frame", nil, c)
    host:SetPoint("TOPLEFT", PADX, c.cursor + 88)
    host:SetPoint("TOPRIGHT", -PADX, c.cursor + 88)
    host:SetHeight(84)

    local bar = ns.CreateUnitBar(host)
    bar:SetPoint("TOPLEFT", 10, -18)
    bar:SetPoint("TOPRIGHT", -10, -18)
    bar:SetHeight(40)
    bar:SetPowerHeight(7)
    bar:ShowPower(true)

    local tl = CreateFrame("Frame", nil, host)
    tl:SetAllPoints(host)
    tl:SetFrameLevel(host:GetFrameLevel() + 10)
    local bl = CreateFrame("Frame", nil, host)
    bl:SetAllPoints(host)
    bl:SetFrameLevel(host:GetFrameLevel() + 9)
    local nameFS = ns.NewText(tl)
    ns.AttachTextBg(nameFS, bl)
    nameFS:SetPoint("LEFT", bar, "LEFT", 10, 4)
    local hpFS = ns.NewText(tl)
    ns.AttachTextBg(hpFS, bl)
    hpFS:SetPoint("RIGHT", bar, "RIGHT", -10, 4)

    preview = { bar = bar, name = nameFS, hp = hpFS, t = 0, hpv = 74 }
    local w = {}
    w.Refresh = function()
        bar:ApplyStyle()
        ns.SetFont(nameFS, 1)
        ns.SetFont(hpFS, 0)
        local cm = ns.db.colorMode
        if cm == "custom" then
            local cc = ns.db.customColor or { r = 0.4, g = 0.8, b = 1 }
            bar.health:SetStatusColor(cc.r, cc.g, cc.b)
        else
            bar.health:SetStatusColor(0.67, 0.83, 0.45)   -- a hunter, obviously
        end
        bar.power:SetStatusColor(0.35, 0.62, 1.00)
        ns.Text(nameFS, "Jabe")
        ns.Text(hpFS, "8.4k · " .. preview.hpv .. "%")
        ns.TextColor(nameFS, nil, 0.67, 0.83, 0.45)
        ns.TextColor(hpFS, nil, ns.palette.text[1], ns.palette.text[2], ns.palette.text[3])
        ns.RefreshTextBg(nameFS)
        ns.RefreshTextBg(hpFS)
        bar.health:SetInstant(preview.hpv, 100)
        bar.power:SetInstant(62, 100)
    end
    table.insert(widgets, w)
    w.Refresh()

    -- gentle simulated damage while the panel is open, so glide, ghost and
    -- spark are all visible right there in the panel
    host:SetScript("OnUpdate", function(_, dt)
        preview.t = preview.t + dt
        if preview.t > 1.6 then
            preview.t = 0
            local delta = math.random(-26, 20)
            preview.hpv = math.max(15, math.min(100, preview.hpv + delta))
            bar.health:SetValue(preview.hpv, 100)
            bar.power:SetValue(math.random(30, 95), 100)
            ns.Text(hpFS, "8.4k · " .. preview.hpv .. "%")
        end
    end)
end

local function buildLook(c)
    buildPreview(c)
    header(c, "Silhouette")
    seg(c, "Corners",
        { { "Capsule", "capsule" }, { "Soft", "soft" }, { "Square", "flat" } },
        function() return ns.db.corner end,
        function(v) ns.db.corner = v end)
    slider(c, "Scale", 0.6, 1.6, 0.05,
        function() return ns.db.scale end,
        function(v) ns.db.scale = v end)

    header(c, "Surface")
    note(c, "The finish of the fill itself. Satin has a quiet sheen, Glass a lit top edge, Velvet a soft bloom — all tinted by whatever colour the bar is.")
    seg(c, "Finish",
        { { "Flat", "flat" }, { "Satin", "satin" }, { "Glass", "glass" }, { "Velvet", "velvet" } },
        function() return ns.db.barFinish end,
        function(v) ns.db.barFinish = v end)

    header(c, "Depth")
    note(c, "A soft shadow under every frame lifts it off the world, and a one-pixel rim light along the top makes the surface read as glass rather than paint.")
    toggle(c, "Frame shadow",
        function() return ns.db.frameShadow end,
        function(v) ns.db.frameShadow = v end)
    slider(c, "Shadow reach", 3, 14, 1,
        function() return ns.db.frameShadowSize end,
        function(v) ns.db.frameShadowSize = v end, "int")
    slider(c, "Shadow strength", 0.1, 1, 0.05,
        function() return ns.db.frameShadowAlpha end,
        function(v) ns.db.frameShadowAlpha = v end, "pct")
    slider(c, "Top rim light", 0, 0.4, 0.02,
        function() return ns.db.topline end,
        function(v) ns.db.topline = v end, "pct")

    header(c, "Type")
    fontpicker(c, "Font", function() return ns.db.font end,
        function(v) ns.db.font = v end, false)
    note(c, "Soft and Heavy are drawn by Silk itself — the text's own silhouette rendered behind it — because the client's Thick outline is crude at small sizes.")
    seg(c, "Outline",
        { { "None", "NONE" }, { "Thin", "OUTLINE" }, { "Thick", "THICK" },
          { "Soft", "SOFT" }, { "Heavy", "HEAVY" } },
        function() return ns.db.outline end,
        function(v) ns.db.outline = v end)
    toggle(c, "Monochrome (crisper small text)",
        function() return ns.db.monochrome end,
        function(v) ns.db.monochrome = v end)
    toggle(c, "Text shadow",
        function() return ns.db.shadow end,
        function(v) ns.db.shadow = v end)
    slider(c, "Shadow offset X", -3, 3, 1,
        function() return ns.db.shadowX end,
        function(v) ns.db.shadowX = v end, "int")
    slider(c, "Shadow offset Y", -3, 3, 1,
        function() return ns.db.shadowY end,
        function(v) ns.db.shadowY = v end, "int")
    header(c, "Readability")
    note(c, "A dark capsule behind each text element. On bright class-coloured bars this does far more for legibility than any outline — turn it on here, then override it per element in Text & Bars.")
    toggle(c, "Text backdrop",
        function() return ns.db.textBg end,
        function(v) ns.db.textBg = v end)
    slider(c, "Backdrop opacity", 0.1, 1, 0.05,
        function() return ns.db.textBgAlpha end,
        function(v) ns.db.textBgAlpha = v end, "pct")
    slider(c, "Backdrop padding", 2, 12, 1,
        function() return ns.db.textBgPad end,
        function(v) ns.db.textBgPad = v end, "int")

    header(c, "Shadow")
    swatch(c, "Shadow color",
        function() return ns.db.shadowColor end,
        function(r, g, b)
            local sc = ns.db.shadowColor
            sc.r, sc.g, sc.b = r, g, b
        end)
    slider(c, "Shadow strength", 0, 1, 0.05,
        function() return (ns.db.shadowColor and ns.db.shadowColor.a) or 0.85 end,
        function(v) ns.db.shadowColor.a = v end, "pct")
    slider(c, "Font size", 9, 16, 1,
        function() return ns.db.fontSize end,
        function(v) ns.db.fontSize = v end, "int")
    note(c, "The list gathers every font the client has loaded, anything other addons have registered, and all of SharedMedia — it refreshes each time you open this panel. With outline off, turn the shadow up instead; that usually reads better at small sizes than a heavy outline.")

    header(c, "Color")
    seg(c, "Bars",
        { { "Class", "class" }, { "Custom", "custom" }, { "Vitality", "vitality" } },
        function() return ns.db.colorMode end,
        function(v) ns.db.colorMode = v end)
    swatch(c, "Custom bar color",
        function() return ns.db.customColor end,
        function(r, g, b)
            local cc = ns.db.customColor
            cc.r, cc.g, cc.b = r, g, b
        end)
    swatch(c, "Accent",
        function() return ns.db.accent end,
        function(r, g, b)
            local a = ns.db.accent
            a.r, a.g, a.b = r, g, b
        end)

    header(c, "Glass")
    slider(c, "Background opacity", 0.1, 0.9, 0.05,
        function() return ns.db.bgAlpha end,
        function(v) ns.db.bgAlpha = v end, "pct")
    slider(c, "Gloss", 0, 0.6, 0.05,
        function() return ns.db.gloss end,
        function(v) ns.db.gloss = v end, "pct")

    header(c, "Border")
    note(c, "The outline around every bar. Class mode colours it by the unit, which reads well with a dark bar background. Elite and rare targets still override it with their rank colour, as do dispellable debuffs on raid cells.")
    slider(c, "Thickness", 0, 4, 1,
        function() return ns.db.borderSize end,
        function(v) ns.db.borderSize = v end, "int")
    seg(c, "Color", { { "Dark", "dark" }, { "Class", "class" }, { "Custom", "custom" } },
        function() return ns.db.borderMode end,
        function(v) ns.db.borderMode = v end)
    swatch(c, "Custom border",
        function() return ns.db.borderColor end,
        function(r, g, b)
            local col = ns.db.borderColor
            col.r, col.g, col.b = r, g, b
            ns.db.borderMode = "custom"
        end)
    slider(c, "Opacity", 0.2, 1, 0.05,
        function() return ns.db.borderAlpha end,
        function(v) ns.db.borderAlpha = v end, "pct")

    header(c, "Empty bar")
    note(c, "The unfilled part of a bar. Match tints it toward the bar's own colour, which goes yellow on a neutral mob and orange on a hunter. Dark keeps it neutral charcoal whatever the bar is doing.")
    slider(c, "Empty bar opacity", 0.3, 1, 0.05,
        function() return ns.db.troughAlpha end,
        function(v) ns.db.troughAlpha = v end, "pct")
    note(c, "At full opacity the empty part is solid. Lower it to see the world through the bar — note that an elite's gold edge will then tint it slightly, since that colour sits behind the bar.")
    seg(c, "Background",
        { { "Match", "match" }, { "Dark", "dark" }, { "Custom", "custom" } },
        function() return ns.db.bgMode end,
        function(v) ns.db.bgMode = v end)
    slider(c, "Match strength", 0, 0.4, 0.01,
        function() return ns.db.bgTint end,
        function(v) ns.db.bgTint = v end, "pct")
    swatch(c, "Custom background",
        function() return ns.db.bgColor end,
        function(r, g, b)
            local col = ns.db.bgColor
            col.r, col.g, col.b = r, g, b
            ns.db.bgMode = "custom"
        end)
    swatch(c, "Damage trail",
        function() return ns.db.lossColor end,
        function(r, g, b)
            local col = ns.db.lossColor
            col.r, col.g, col.b = r, g, b
        end)

    header(c, "Motion")
    slider(c, "Fill glide", 5, 20, 1,
        function() return ns.db.smooth end,
        function(v) ns.db.smooth = v end, "int")
    toggle(c, "Damage ghost trail",
        function() return ns.db.ghost end,
        function(v) ns.db.ghost = v end)

    header(c, "Text")
    seg(c, "Health text",
        { { "Value", "value" }, { "Percent", "percent" }, { "Both", "both" } },
        function() return ns.db.hpFormat end,
        function(v) ns.db.hpFormat = v end)
end

local function castGroup(c, label, cfgFn)
    header(c, label)
    toggle(c, "Enable",
        function() return cfgFn().castbar end,
        function(v) cfgFn().castbar = v end)
    slider(c, "Height", 10, 30, 1,
        function() return cfgFn().castH or 18 end,
        function(v) cfgFn().castH = v end, "int")
    toggle(c, "Spell icon",
        function() return cfgFn().castIcon ~= false end,
        function(v) cfgFn().castIcon = v end)
    toggle(c, "Time remaining",
        function() return cfgFn().castTime ~= false end,
        function(v) cfgFn().castTime = v end)
    seg(c, "Placement",
        { { "Inside", "inside" }, { "Below", "below" }, { "Free", "free" } },
        function() return ns.CastMode(cfgFn()) end,
        function(v)
            cfgFn().castMode = v
            cfgFn().castDetach = (v == "free")
        end)
    note(c, "Inside takes over the frame itself while a cast is up — the name and health fade out, the spell sweeps across the capsule, and the frame's border stays. Below hangs a separate bar under the frame; Free floats anywhere, dragged with /silk unlock.")
    slider(c, "Free width (0 = match frame)", 0, 400, 2,
        function() return cfgFn().castW or 0 end,
        function(v) cfgFn().castW = v end, "int")
    note(c, "Interruptible casts fill gold; casts you cannot interrupt go cold grey. Channels drain instead of filling, and an interrupted cast flashes red before melting away. Height applies to Below and Free — Inside uses the frame's own height.")
end

local function swingGroupPlayer(c, cfgFn)
    local S = function() return cfgFn().swing end
    header(c, "Swing timers")
    note(c, "Exact, from the combat log. Melee shows main hand with the off hand as a slice inside it; the ranged bar is Auto Shot for hunters and the wand for casters, with the half-second aim window drawn on the track. Haste procs rescale the bar mid-swing, and a cast that pushes a shot snaps the bar to where the shot will really land.")
    toggle(c, "Melee bar",
        function() return S().melee ~= false end, function(v) S().melee = v end)
    toggle(c, "Ranged bar (Auto Shot / wand)",
        function() return S().ranged ~= false end, function(v) S().ranged = v end)
    seg(c, "On top", { { "Auto", "auto" }, { "Melee", "melee" }, { "Ranged", "ranged" } },
        function() return S().order or "auto" end, function(v) S().order = v end)
    note(c, "Auto puts the shot bar on top for hunters and melee on top for everyone else.")
    slider(c, "Bar height", 8, 24, 1,
        function() return S().h or 14 end, function(v) S().h = v end, "int")
    toggle(c, "Hide when idle",
        function() return S().hideIdle ~= false end, function(v) S().hideIdle = v end)
    slider(c, "Idle grace (seconds)", 1, 15, 1,
        function() return S().idleDelay or 5 end, function(v) S().idleDelay = v end, "int")
    toggle(c, "Detach (place it anywhere)",
        function() return S().detach end, function(v) S().detach = v end)
    slider(c, "Detached width (0 = match frame)", 0, 400, 2,
        function() return S().w or 0 end, function(v) S().w = v end, "int")
end

local function swingGroupEnemy(c, label, cfgFn)
    local S = function() return cfgFn().swing end
    header(c, label)
    note(c, "An estimate: no API exposes a mob's attack speed, so the bar measures the gap between its swings and reads \"calibrating\" until it has seen two. Very good on a boss that's been swinging for a while; blind for the first seconds of a pull.")
    toggle(c, "Enemy swing bar",
        function() return S().enemy end, function(v) S().enemy = v end)
    slider(c, "Bar height", 8, 24, 1,
        function() return S().h or 12 end, function(v) S().h = v end, "int")
    toggle(c, "Detach (place it anywhere)",
        function() return S().detach end, function(v) S().detach = v end)
    slider(c, "Detached width (0 = match frame)", 0, 400, 2,
        function() return S().w or 0 end, function(v) S().w = v end, "int")
end

local function buildPlayer(c)
    local P = function() return ns.db.frames.player end
    local E = function() return ns.db.frames.pet end

    header(c, "Player")
    toggle(c, "Enable",
        function() return P().enabled end, function(v) P().enabled = v end)
    slider(c, "Width", 140, 340, 2,
        function() return P().w end, function(v) P().w = v end, "int")
    slider(c, "Height", 26, 64, 1,
        function() return P().h end, function(v) P().h = v end, "int")
    toggle(c, "Portrait",
        function() return P().portrait end, function(v) P().portrait = v end)
    toggle(c, "Debuffs above frame",
        function() return P().auras.debuffs end, function(v) P().auras.debuffs = v end)

    header(c, "Pet")
    toggle(c, "Enable",
        function() return E().enabled end, function(v) E().enabled = v end)
    slider(c, "Width", 100, 260, 2,
        function() return E().w end, function(v) E().w = v end, "int")
    slider(c, "Height", 20, 48, 1,
        function() return E().h end, function(v) E().h = v end, "int")
    toggle(c, "Portrait",
        function() return E().portrait end, function(v) E().portrait = v end)
    toggle(c, "Happiness mood dot",
        function() return E().mood end, function(v) E().mood = v end)

    header(c, "Portraits")
    toggle(c, "Class icons for players",
        function() return ns.db.classIconPortraits end,
        function(v) ns.db.classIconPortraits = v end)

    header(c, "Your own buffs")
    note(c, "Silk can draw your buffs itself: switch to Player in the Text & Bars tab, turn on the buff block, detach it and place it wherever you like. Then hide the default one below.")
    toggle(c, "Hide the default WoW buff frame",
        function() return ns.db.hideBlizzardBuffs end,
        function(v) ns.db.hideBlizzardBuffs = v end)
    castGroup(c, "Player castbar", function() return ns.db.frames.player end)

    swingGroupPlayer(c, function() return ns.db.frames.player end)

end

local function buildTarget(c)
    local T = function() return ns.db.frames.target end
    local F = function() return ns.db.frames.focus end
    local O = function() return ns.db.frames.targettarget end

    header(c, "Target")
    toggle(c, "Enable",
        function() return T().enabled end, function(v) T().enabled = v end)
    slider(c, "Width", 140, 340, 2,
        function() return T().w end, function(v) T().w = v end, "int")
    slider(c, "Height", 26, 64, 1,
        function() return T().h end, function(v) T().h = v end, "int")
    toggle(c, "Portrait",
        function() return T().portrait end, function(v) T().portrait = v end)
    toggle(c, "Buffs below frame",
        function() return T().auras.buffs end, function(v) T().auras.buffs = v end)
    toggle(c, "Debuffs above frame",
        function() return T().auras.debuffs end, function(v) T().auras.debuffs = v end)
    toggle(c, "Only my debuffs",
        function() return T().auras.onlyMine end, function(v) T().auras.onlyMine = v end)
    slider(c, "Aura size", 14, 30, 1,
        function() return T().auras.size end, function(v) T().auras.size = v end, "int")
    slider(c, "Auras per row", 4, 12, 1,
        function() return T().auras.perRow end, function(v) T().auras.perRow = v end, "int")
    toggle(c, "Combo points",
        function() return T().combo end, function(v) T().combo = v end)
    note(c, "Buff and debuff blocks have their own position, grow direction and size controls in the Text & Bars tab — pick the frame there, then scroll to Debuff block / Buff block.")

    header(c, "Focus")
    toggle(c, "Enable",
        function() return F().enabled end, function(v) F().enabled = v end)
    slider(c, "Width", 120, 260, 2,
        function() return F().w end, function(v) F().w = v end, "int")
    slider(c, "Height", 20, 48, 1,
        function() return F().h end, function(v) F().h = v end, "int")
    toggle(c, "Portrait",
        function() return F().portrait end, function(v) F().portrait = v end)
    toggle(c, "Debuffs above frame",
        function() return F().auras.debuffs end, function(v) F().auras.debuffs = v end)

    header(c, "Target of Target")
    toggle(c, "Enable",
        function() return O().enabled end, function(v) O().enabled = v end)
    slider(c, "Width", 100, 220, 2,
        function() return O().w end, function(v) O().w = v end, "int")
    slider(c, "Height", 18, 40, 1,
        function() return O().h end, function(v) O().h = v end, "int")
    castGroup(c, "Target castbar", function() return ns.db.frames.target end)
    castGroup(c, "Focus castbar", function() return ns.db.frames.focus end)

    swingGroupEnemy(c, "Target swing timer", function() return ns.db.frames.target end)
    swingGroupEnemy(c, "Focus swing timer", function() return ns.db.frames.focus end)

end

-- Text & Auras ------------------------------------------------------------
-- One set of controls serves all five unit frames: every getter and setter
-- reads through `editing`, so switching the frame picker just re-reads the
-- same widgets against a different table.

local editing = "player"

local ANCHORS = {
    { "TL", "TOPLEFT" }, { "TR", "TOPRIGHT" }, { "C", "CENTER" },
    { "BL", "BOTTOMLEFT" }, { "BR", "BOTTOMRIGHT" },
}

local function ecfg() return ns.db.frames[editing] end

local function tblock(key)
    local t = ecfg().texts
    if not t[key] then t[key] = { "TOPLEFT", 0, 0, size = 0, show = true } end
    return t[key]
end

local OUTLINE_OPTS = {
    { "Auto", "" }, { "None", "NONE" }, { "Thin", "OUTLINE" },
    { "Thick", "THICK" }, { "Soft", "SOFT" }, { "Heavy", "HEAVY" },
}

local function textGroup(c, title, key)
    header(c, title)
    toggle(c, "Show",
        function() return tblock(key).show ~= false end,
        function(v) tblock(key).show = v end)
    seg(c, "Anchor", ANCHORS,
        function() return tblock(key)[1] end,
        function(v) tblock(key)[1] = v end, 240)
    slider(c, "X offset", -200, 200, 1,
        function() return tblock(key)[2] or 0 end,
        function(v) tblock(key)[2] = v end, "int")
    slider(c, "Y offset", -120, 120, 1,
        function() return tblock(key)[3] or 0 end,
        function(v) tblock(key)[3] = v end, "int")
    slider(c, "Size", -4, 8, 1,
        function() return tblock(key).size or 0 end,
        function(v) tblock(key).size = v end, "int")
    fontpicker(c, "Font",
        function() return tblock(key).font or "" end,
        function(v) tblock(key).font = v end, true)
    seg(c, "Outline", OUTLINE_OPTS,
        function() return tblock(key).outline or "" end,
        function(v) tblock(key).outline = v end, 240)
    seg(c, "Color", { { "Auto", "auto" }, { "Custom", "custom" } },
        function() return tblock(key).colorMode or "auto" end,
        function(v) tblock(key).colorMode = v end)
    swatch(c, "Custom color",
        function() return tblock(key).color end,
        function(r, g, b)
            local col = tblock(key).color
            col.r, col.g, col.b = r, g, b
            tblock(key).colorMode = "custom"
        end)
    seg(c, "Backdrop", { { "Auto", "auto" }, { "On", "on" }, { "Off", "off" } },
        function() return tblock(key).bg or "auto" end,
        function(v) tblock(key).bg = v end)
end

local function powerGroup(c)
    header(c, "Power bar")
    note(c, "By default the power bar is part of the health bar: one capsule, one outline, sharing whatever corner style you picked. Detaching splits it out into its own capsule that you can place anywhere — the power number follows it. Drag it directly with /silk unlock.")
    toggle(c, "Detach from frame",
        function() return ecfg().powerDetach end,
        function(v) ecfg().powerDetach = v end)
    slider(c, "X position", -700, 700, 1,
        function() return ecfg().powerPos[1] end,
        function(v) ecfg().powerPos[1] = v end, "int")
    slider(c, "Y position", -450, 450, 1,
        function() return ecfg().powerPos[2] end,
        function(v) ecfg().powerPos[2] = v end, "int")
    slider(c, "Height (0 = auto)", 0, 40, 1,
        function() return ecfg().powerH or 0 end,
        function(v) ecfg().powerH = v end, "int")
    note(c, "Height applies either way: attached it sets how thick the power slice is, detached it sets the bar's own height.")
    slider(c, "Detached width (0 = match frame)", 0, 400, 2,
        function() return ecfg().powerW or 0 end,
        function(v) ecfg().powerW = v end, "int")
end

-- prefix is "b" for the buff block or "d" for the debuff block
local function auraGroup(c, title, prefix)
    local function A() return ecfg().auras end
    local function has() return A() ~= nil end
    local function get(k, dflt)
        local a = A()
        return (a and a[k] ~= nil) and a[k] or dflt
    end
    local function set(k, v)
        local a = A()
        if a then a[k] = v end
    end
    local posKey = prefix .. "Pos"
    local function pos(i)
        local a = A()
        if not a or not a[posKey] then return 0 end
        return a[posKey][i] or 0
    end
    local function setPos(i, v)
        local a = A()
        if a and a[posKey] then a[posKey][i] = v end
    end

    header(c, title)
    toggle(c, "Show " .. (prefix == "b" and "buffs" or "debuffs"),
        function() return get(prefix == "b" and "buffs" or "debuffs", false) end,
        function(v) set(prefix == "b" and "buffs" or "debuffs", v) end)
    toggle(c, "Detach from frame",
        function() return get(prefix .. "Detach", false) end,
        function(v) set(prefix .. "Detach", v) end)
    slider(c, "X", -700, 700, 1,
        function()
            if get(prefix .. "Detach", false) then return pos(1) end
            return get(prefix == "b" and "bx" or "dx", 0)
        end,
        function(v)
            if get(prefix .. "Detach", false) then setPos(1, v)
            else set(prefix == "b" and "bx" or "dx", v) end
        end, "int")
    slider(c, "Y", -450, 450, 1,
        function()
            if get(prefix .. "Detach", false) then return pos(2) end
            return get(prefix == "b" and "by" or "dy", 0)
        end,
        function(v)
            if get(prefix .. "Detach", false) then setPos(2, v)
            else set(prefix == "b" and "by" or "dy", v) end
        end, "int")
    seg(c, "Grow across", { { "Right", "right" }, { "Left", "left" } },
        function() return get(prefix .. "GrowX", "right") end,
        function(v) set(prefix .. "GrowX", v) end)
    seg(c, "Grow vertical", { { "Down", "down" }, { "Up", "up" } },
        function() return get(prefix .. "GrowY", prefix == "b" and "down" or "up") end,
        function(v) set(prefix .. "GrowY", v) end)

    if prefix == "b" then
        slider(c, "Icon size (0 = shared)", 0, 40, 1,
            function() return get("bSize", 0) end,
            function(v) set("bSize", v) end, "int")
        slider(c, "Per row (0 = shared)", 0, 16, 1,
            function() return get("bPerRow", 0) end,
            function(v) set("bPerRow", v) end, "int")
    else
        slider(c, "Icon size", 12, 40, 1,
            function() return get("size", 22) end,
            function(v) set("size", v) end, "int")
        slider(c, "Per row", 2, 16, 1,
            function() return get("perRow", 8) end,
            function(v) set("perRow", v) end, "int")
        slider(c, "Max shown", 4, 32, 1,
            function() return get("maxShown", 16) end,
            function(v) set("maxShown", v) end, "int")
        slider(c, "Spacing", 0, 14, 1,
            function() return get("spacing", 4) end,
            function(v) set("spacing", v) end, "int")
        toggle(c, "Only my debuffs",
            function() return get("onlyMine", false) end,
            function(v) set("onlyMine", v) end)
    end
end

local function buildText(c)
    header(c, "Which frame")
    seg(c, "Editing",
        { { "Player", "player" }, { "Pet", "pet" }, { "Target", "target" },
          { "ToT", "targettarget" }, { "Focus", "focus" } },
        function() return editing end,
        function(v)
            editing = v
            refreshAllWidgets()
        end, 250)
    note(c, "Everything below edits the frame selected above. Anchor picks the corner the text hangs from; X and Y nudge it from there. You can also drag any of these live with /silk unlock.")

    textGroup(c, "Name text", "name")
    textGroup(c, "Health text", "hp")
    textGroup(c, "Power text", "power")
    textGroup(c, "Level text", "level")

    powerGroup(c)

    auraGroup(c, "Debuff block", "d")
    auraGroup(c, "Buff block", "b")
    note(c, "Attached, X and Y nudge the block relative to the frame. Detached, they place it anywhere on screen and it stops following the frame entirely — good for putting your own buffs where the default ones used to sit. Both blocks also get a drag handle in /silk unlock.")
end

local function groupText(c, which, key, label)
    header(c, label)
    local function tb()
        local t = ns.db[which].texts
        if not t[key] then t[key] = { 0, 0, size = 0, show = true } end
        return t[key]
    end
    toggle(c, "Show", function() return tb().show ~= false end,
        function(v) tb().show = v end)
    slider(c, "X offset", -120, 120, 1,
        function() return tb()[1] or 0 end, function(v) tb()[1] = v end, "int")
    slider(c, "Y offset", -40, 40, 1,
        function() return tb()[2] or 0 end, function(v) tb()[2] = v end, "int")
    slider(c, "Size", -4, 8, 1,
        function() return tb().size or 0 end, function(v) tb().size = v end, "int")
    fontpicker(c, "Font", function() return tb().font or "" end,
        function(v) tb().font = v end, true)
    seg(c, "Outline", OUTLINE_OPTS,
        function() return tb().outline or "" end,
        function(v) tb().outline = v end, 240)
    seg(c, "Color", { { "Auto", "auto" }, { "Custom", "custom" } },
        function() return tb().colorMode or "auto" end,
        function(v) tb().colorMode = v end)
    swatch(c, "Custom color", function() return tb().color end,
        function(r, g, b)
            local col = tb().color
            col.r, col.g, col.b = r, g, b
            tb().colorMode = "custom"
        end)
    seg(c, "Backdrop", { { "Auto", "auto" }, { "On", "on" }, { "Off", "off" } },
        function() return tb().bg or "auto" end,
        function(v) tb().bg = v end)
end

local function buildParty(c)
    local P = function() return ns.db.party end
    header(c, "Party")
    toggle(c, "Enable",
        function() return P().enabled end, function(v) P().enabled = v end)
    slider(c, "Width", 120, 280, 2,
        function() return P().w end, function(v) P().w = v end, "int")
    slider(c, "Height", 22, 52, 1,
        function() return P().h end, function(v) P().h = v end, "int")
    slider(c, "Spacing", 0, 24, 1,
        function() return P().spacing end, function(v) P().spacing = v end, "int")
    toggle(c, "Power sliver",
        function() return P().power end, function(v) P().power = v end)
    slider(c, "Debuff icons", 0, 4, 1,
        function() return P().debuffIcons end, function(v) P().debuffIcons = v end, "int")
    toggle(c, "Range fade",
        function() return P().range end, function(v) P().range = v end)
    toggle(c, "Hide while in a raid",
        function() return P().hideInRaid end, function(v) P().hideInRaid = v end)

    header(c, "Direction")
    note(c, "Cells grow away from the anchor in whichever direction you pick, so the block can sit flush in any corner of the screen.")
    seg(c, "Orientation",
        { { "Vertical", "vertical" }, { "Horizontal", "horizontal" } },
        function() return P().orient end, function(v) P().orient = v end)
    seg(c, "Horizontal", { { "Right", "right" }, { "Left", "left" } },
        function() return P().growX end, function(v) P().growX = v end)
    seg(c, "Vertical", { { "Down", "down" }, { "Up", "up" } },
        function() return P().growY end, function(v) P().growY = v end)

    groupText(c, "party", "name", "Party name text")
    groupText(c, "party", "status", "Party status text")

    header(c, "Preview")
    note(c, "Four phantom teammates, health drifting on its own, so you can style party frames without a group.")
    button(c, "Toggle party preview", function()
        ns.TogglePreview("party")
    end, 180)
    toggle(c, "Aggro highlight",
        function() return ns.db.party.threat ~= false end,
        function(v) ns.db.party.threat = v end)

end

local function buildRaid(c)
    local R = function() return ns.db.raid end
    header(c, "Raid")
    toggle(c, "Enable",
        function() return R().enabled end, function(v) R().enabled = v end)
    slider(c, "Cell width", 44, 110, 2,
        function() return R().w end, function(v) R().w = v end, "int")
    slider(c, "Cell height", 20, 52, 1,
        function() return R().h end, function(v) R().h = v end, "int")
    slider(c, "Spacing", 0, 14, 1,
        function() return R().spacing end, function(v) R().spacing = v end, "int")
    slider(c, "Groups per row", 1, 8, 1,
        function() return R().groupsPerRow end, function(v) R().groupsPerRow = v end, "int")
    seg(c, "Cell text",
        { { "None", "none" }, { "Percent", "percent" }, { "Deficit", "deficit" } },
        function() return R().text end,
        function(v) R().text = v end)
    toggle(c, "Power sliver",
        function() return R().power end, function(v) R().power = v end)
    toggle(c, "Dispellable tint",
        function() return R().dispel end, function(v) R().dispel = v end)

    header(c, "Healer kit")
    note(c, "The details that decide whether raid frames are usable in a fight: an incoming-resurrection badge, deficit text so you see the size of the heal rather than what's left, short names, and how far out-of-range players fade.")
    toggle(c, "Resurrection badge",
        function() return R().resBadge ~= false end,
        function(v) R().resBadge = v end)
    toggle(c, "Aggro highlight",
        function() return R().threat ~= false end,
        function(v) R().threat = v end)
    note(c, "Tanking pulses the cell's border red; holding threat without tanking yet turns it amber. Aggro outranks the dispel colour — a debuff can wait two seconds, aggro on a clothie can't.")
    seg(c, "Health text",
        { { "None", "none" }, { "Percent", "percent" },
          { "Deficit", "deficit" }, { "Current", "current" } },
        function() return R().text end,
        function(v) R().text = v end)
    slider(c, "Name length (0 = full)", 0, 12, 1,
        function() return R().nameLen or 0 end,
        function(v) R().nameLen = v end, "int")
    slider(c, "Cell text size", -4, 4, 1,
        function() return R().fontDelta or 0 end,
        function(v) R().fontDelta = v end, "int")
    slider(c, "Out-of-range fade", 0.1, 1, 0.05,
        function() return R().rangeAlpha or 0.45 end,
        function(v) R().rangeAlpha = v end, "pct")
    toggle(c, "Range fade",
        function() return R().range end, function(v) R().range = v end)

    header(c, "Direction")
    note(c, "Groups grow away from the anchor in the direction you pick. For a top-right corner block, set Horizontal to Left and Vertical to Down, then drag the anchor into the corner.")
    seg(c, "Horizontal", { { "Right", "right" }, { "Left", "left" } },
        function() return R().growX end, function(v) R().growX = v end)
    seg(c, "Vertical", { { "Down", "down" }, { "Up", "up" } },
        function() return R().growY end, function(v) R().growY = v end)

    groupText(c, "raid", "name", "Raid name text")
    groupText(c, "raid", "status", "Raid status text")

    header(c, "Preview")
    note(c, "Fills the raid area with 25 phantom raiders so you can style it solo. Their health drifts on its own — a live demo of the fill engine.")
    button(c, "Toggle raid preview", function()
        ns.TogglePreview("raid")
    end, 180)
end

local function buildLayout(c)
    header(c, "Layout mode")
    note(c, "Unlock to drag any frame. The player, pet, target, ToT and focus frames also grow a small pill handle over each text — name, health, power, level — so every number sits exactly where you want it. Combat locks everything automatically.")

    local unlockBtn
    unlockBtn = button(c, "Unlock frames", function()
        ns.SetLayoutMode(not ns.layoutMode)
    end, 170)
    local baseRefresh = unlockBtn.Refresh
    unlockBtn.Refresh = function(s)
        baseRefresh(s)
        s.label:SetText(ns.layoutMode and "Lock & save" or "Unlock frames")
    end

    header(c, "Reset")
    note(c, "If a global font or outline change seems to do nothing, an element is probably holding its own override. This clears every per-element font, outline, colour and backdrop override back to Auto, positions untouched.")
    button(c, "Clear all text overrides", function()
        local function clear(t)
            if type(t) ~= "table" then return end
            t.font, t.outline, t.bg, t.colorMode = "", "", "auto", "auto"
        end
        for _, fcfg in pairs(ns.db.frames) do
            for _, t in pairs(fcfg.texts or {}) do clear(t) end
        end
        for _, which in ipairs({ "party", "raid" }) do
            for _, t in pairs(ns.db[which].texts or {}) do clear(t) end
        end
        refreshAllWidgets()
        ns.ApplyAll()
        ns.Print("per-element text overrides cleared — everything follows the Look tab again.")
    end, 200)
    button(c, "Reset text positions", function()
        for key, fcfg in pairs(ns.db.frames) do
            local d = ns.defaults.frames[key] and ns.defaults.frames[key].texts
            if d then
                fcfg.texts = {}
                for tk, tv in pairs(d) do
                    fcfg.texts[tk] = { tv[1], tv[2], tv[3] }
                end
            end
        end
        ns.ApplyAll()
        ns.Print("text positions reset.")
    end, 190)

    local armed = -100
    local resetBtn
    resetBtn = button(c, "Reset Silk (everything)", function(w)
        if GetTime() - armed < 5 then
            armed = -100
            ns.ResetProfile()
            refreshAllWidgets()
            ns.Print("profile reset to defaults.")
        else
            armed = GetTime()
            w.label:SetText("Click again to confirm")
        end
    end, 190)
    local baseReset = resetBtn.Refresh
    resetBtn.Refresh = function(s)
        baseReset(s)
        if GetTime() - armed >= 5 then
            s.label:SetText("Reset Silk (everything)")
        end
    end
end

-- panel -------------------------------------------------------------------

local function BuildPanel()
    panel = CreateFrame("Frame", "SilkOptions", UIParent)
    panel:SetSize(PANEL_W, PANEL_H)
    panel:SetPoint("CENTER", 0, 30)
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true)
    panel:Hide()
    table.insert(UISpecialFrames, "SilkOptions")

    local skin = glassPanel(panel)
    skin:SetAllPoints()

    local drag = CreateFrame("Frame", nil, panel)
    drag:SetPoint("TOPLEFT")
    drag:SetPoint("TOPRIGHT")
    drag:SetHeight(50)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() panel:StartMoving() end)
    drag:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)

    local title = skin:CreateFontString(nil, "OVERLAY")
    pfont(title, 22)
    title:SetPoint("TOPLEFT", 20, -14)
    title:SetText("Silk")
    panel.title = title

    local tag = skin:CreateFontString(nil, "OVERLAY")
    pfont(tag, 10)
    tag:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 2)
    tag:SetText("unit frames, poured smooth")
    tag:SetTextColor(0.55, 0.60, 0.68)

    local ver = skin:CreateFontString(nil, "OVERLAY")
    pfont(ver, 9)
    ver:SetPoint("BOTTOMLEFT", 18, 10)
    ver:SetText("v" .. (ns.version or "?") .. "  ·  /silk")
    ver:SetTextColor(0.42, 0.46, 0.54)

    local close = CreateFrame("Button", nil, panel)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -14, -13)
    close:SetFrameLevel(panel:GetFrameLevel() + 10)
    local cbg = close:CreateTexture(nil, "BACKGROUND")
    cbg:SetAllPoints()
    cbg:SetTexture(ns.TEX.dot)
    cbg:SetVertexColor(0.14, 0.15, 0.19, 0.95)
    local cx = close:CreateFontString(nil, "OVERLAY")
    pfont(cx, 12)
    cx:SetPoint("CENTER", 0, 0)
    cx:SetText("×")
    cx:SetTextColor(0.8, 0.84, 0.9)
    close:SetScript("OnEnter", function()
        cbg:SetVertexColor(accent())
        cx:SetTextColor(0.06, 0.07, 0.09)
    end)
    close:SetScript("OnLeave", function()
        cbg:SetVertexColor(0.14, 0.15, 0.19, 0.95)
        cx:SetTextColor(0.8, 0.84, 0.9)
    end)
    close:SetScript("OnClick", function() panel:Hide() end)

    local order = {
        { key = "look",   label = "Look" },
        { key = "player", label = "Player & Pet" },
        { key = "target", label = "Target & Focus" },
        { key = "text",   label = "Text & Bars" },
        { key = "party",  label = "Party" },
        { key = "raid",   label = "Raid" },
        { key = "layout", label = "Layout" },
    }

    for i = 1, #order do
        local info = order[i]
        local b = glass(panel, "soft")
        b:SetSize(RAIL_W - 8, 28)
        b:SetPoint("TOPLEFT", 16, -58 - (i - 1) * 33)
        b:EnableMouse(true)
        local lb = b:CreateFontString(nil, "OVERLAY")
        pfont(lb, 11)
        lb:SetPoint("CENTER")
        lb:SetText(info.label)
        b.label = lb
        b:SetScript("OnMouseDown", function()
            selectTab(info.key)
        end)

        local sf = CreateFrame("ScrollFrame", nil, panel)
        sf:SetPoint("TOPLEFT", 152, -58)
        sf:SetPoint("BOTTOMRIGHT", -14, 14)
        local child = CreateFrame("Frame", nil, sf)
        child:SetSize(CW, 10)
        child.cursor = -4
        sf:SetScrollChild(child)
        sf:EnableMouseWheel(true)
        sf:SetScript("OnMouseWheel", function(s, delta)
            local cur = s:GetVerticalScroll()
            local maxs = math.max(0, child:GetHeight() - s:GetHeight())
            local nv = cur - delta * 36
            if nv < 0 then nv = 0 elseif nv > maxs then nv = maxs end
            s:SetVerticalScroll(nv)
        end)
        sf:Hide()

        tabs[info.key] = { button = b, scroll = sf, child = child }
    end

    selectTab = function(key)
        for k, t in pairs(tabs) do
            local on = (k == key)
            t.scroll:SetShown(on)
            if on then
                local r, g, b = accent()
                t.button.bg:SetVertexColor(r, g, b, 0.22)
                t.button.label:SetTextColor(0.95, 0.97, 1)
            else
                t.button.bg:SetVertexColor(1, 1, 1, 0.05)
                t.button.label:SetTextColor(0.62, 0.66, 0.74)
            end
        end
        panel.currentTab = key
    end

    buildLook(tabs.look.child)
    buildPlayer(tabs.player.child)
    buildTarget(tabs.target.child)
    buildText(tabs.text.child)
    buildParty(tabs.party.child)
    buildRaid(tabs.raid.child)
    buildLayout(tabs.layout.child)

    for _, t in pairs(tabs) do
        t.child:SetHeight(math.max(10, -t.child.cursor + 20))
    end

    selectTab("look")
end

function ns.TogglePanel()
    if not panel then
        BuildPanel()
    end
    if panel:IsShown() then
        panel:Hide()
        if cpicker then cpicker:Hide() end
    else
        -- other addons register fonts at their own pace, so rescan on open
        ns.FontList(true)
        refreshAllWidgets()
        panel:Show()
    end
end

-- layout mode -------------------------------------------------------------

ns.layoutMode = false

local prettyName = {
    player = "Player", pet = "Pet", target = "Target",
    targettarget = "ToT", focus = "Focus",
}

local function anchorCoords(target, point)
    local cx, cy = target:GetCenter()
    local x, y = cx, cy
    if point:find("LEFT") then
        x = target:GetLeft() or cx
    elseif point:find("RIGHT") then
        x = target:GetRight() or cx
    end
    if point:find("TOP") then
        y = target:GetTop() or cy
    elseif point:find("BOTTOM") then
        y = target:GetBottom() or cy
    end
    return x, y
end

-- `point` is the corner the element is anchored by. Aura blocks hang off
-- their growth corner, so saving the center would make them jump on the next
-- refresh.
local function saveFramePos(target, posTable, point)
    point = point or "CENTER"
    local s = target:GetEffectiveScale()
    local us = UIParent:GetEffectiveScale()
    local ux, uy = UIParent:GetCenter()
    local x, y = anchorCoords(target, point)
    posTable[1] = math.floor(x * s / us - ux + 0.5)
    posTable[2] = math.floor(y * s / us - uy + 0.5)
    target:ClearAllPoints()
    target:SetPoint(point, UIParent, "CENTER", posTable[1], posTable[2])
end

local function frameOverlay(target, label, getPos, cond, getPoint)
    local ov = CreateFrame("Button", nil, UIParent)
    ov:SetFrameStrata("FULLSCREEN_DIALOG")
    ov:SetAllPoints(target)
    ov:EnableMouse(true)
    ov:RegisterForDrag("LeftButton")
    ov.cond = cond
    local skin = glass(ov, "soft")
    skin:SetAllPoints()
    ov.skinbg = skin.bg
    local lb = skin:CreateFontString(nil, "OVERLAY")
    pfont(lb, 10)
    lb:SetPoint("CENTER")
    lb:SetText(label)
    lb:SetTextColor(0.95, 0.97, 1)
    ov:SetScript("OnDragStart", function()
        target:StartMoving()
    end)
    ov:SetScript("OnDragStop", function()
        target:StopMovingOrSizing()
        saveFramePos(target, getPos(), getPoint and getPoint() or "CENTER")
    end)
    ov:Hide()
    return ov
end

local function textHandle(f, tkey)
    local h = CreateFrame("Button", nil, UIParent)
    h:SetFrameStrata("FULLSCREEN_DIALOG")
    h:SetSize(34, 15)
    h:EnableMouse(true)
    local skin = glass(h, "capsule")
    skin:SetAllPoints()
    h.skinbg = skin.bg
    local lb = skin:CreateFontString(nil, "OVERLAY")
    pfont(lb, 9, "")
    lb:SetPoint("CENTER")
    lb:SetText(tkey)
    lb:SetTextColor(INK[1], INK[2], INK[3])
    h:SetScript("OnShow", function(s)
        s:ClearAllPoints()
        s:SetPoint("CENTER", f.texts[tkey], "CENTER", 0, 0)
    end)
    local dragging = false
    local sx, sy, bx, by
    h:SetScript("OnMouseDown", function(s)
        local t = f.cfg.texts and f.cfg.texts[tkey]
        if not t then return end
        sx, sy = GetCursorPosition()
        bx, by = t[2], t[3]
        dragging = true
        s:SetScript("OnUpdate", function()
            if not dragging then return end
            local cx2, cy2 = GetCursorPosition()
            local sc = f:GetEffectiveScale()
            local t2 = f.cfg.texts[tkey]
            t2[2] = math.floor(bx + (cx2 - sx) / sc + 0.5)
            t2[3] = math.floor(by + (cy2 - sy) / sc + 0.5)
            ns.ApplyTextPositions(f)
            s:ClearAllPoints()
            s:SetPoint("CENTER", f.texts[tkey], "CENTER", 0, 0)
        end)
    end)
    h:SetScript("OnMouseUp", function(s)
        dragging = false
        s:SetScript("OnUpdate", nil)
    end)
    h:Hide()
    return h
end

local function buildOverlays()
    overlays = { frames = {}, handles = {} }
    for key, f in pairs(ns.units) do
        table.insert(overlays.frames,
            frameOverlay(f, prettyName[key] or key, function() return f.cfg.pos end))
        -- the power bar gets its own handle, but only while it's detached
        f.powerBar:SetMovable(true)
        f.powerBar:SetClampedToScreen(true)
        table.insert(overlays.frames,
            frameOverlay(f.powerBar, (prettyName[key] or key) .. " power",
                function() return f.cfg.powerPos end,
                function() return f.cfg.powerDetach and f.powerBar:IsShown() end))
        if f.swingHost then
            f.swingHost:SetMovable(true)
            f.swingHost:SetClampedToScreen(true)
            table.insert(overlays.frames,
                frameOverlay(f.swingHost, (prettyName[key] or key) .. " swing timers",
                    function() return f.cfg.swing and f.cfg.swing.pos end,
                    function() return f.cfg.swing and f.cfg.swing.detach and f.swingHost.wanted end))
        end
        if f.castBar then
            f.castBar:SetMovable(true)
            f.castBar:SetClampedToScreen(true)
            table.insert(overlays.frames,
                frameOverlay(f.castBar, (prettyName[key] or key) .. " castbar",
                    function() return f.cfg.castPos end,
                    function() return f.cfg.castbar and ns.CastMode(f.cfg) == "free" end))
        end
        for tkey in pairs(f.texts) do
            table.insert(overlays.handles, textHandle(f, tkey))
        end
        -- detached aura blocks are draggable too
        local blocks = { { f.debuffC, "dPos", "debuffs" }, { f.buffC, "bPos", "buffs" } }
        for i = 1, #blocks do
            local cont, poskey, word = blocks[i][1], blocks[i][2], blocks[i][3]
            if cont then
                cont:SetMovable(true)
                cont:SetClampedToScreen(true)
                table.insert(overlays.frames,
                    frameOverlay(cont, (prettyName[key] or key) .. " " .. word,
                        function() return f.cfg.auras[poskey] end,
                        function()
                            local a = f.cfg.auras
                            return a and a[(poskey == "bPos") and "bDetach" or "dDetach"]
                                and cont:IsShown() and cont:GetWidth() > 4
                        end,
                        function()
                            local o = cont.getOpts() or {}
                            return cont:Corner(o)
                        end))
            end
        end
    end
    table.insert(overlays.frames,
        frameOverlay(ns.PartyAnchor, "Party", function() return ns.db.party.pos end))
    table.insert(overlays.frames,
        frameOverlay(ns.RaidAnchor, "Raid", function() return ns.db.raid.pos end))
end

function ns.SetLayoutMode(on)
    if on and InCombatLockdown() then
        ns.Print("can't unlock during combat.")
        return
    end
    if on and not overlays then
        buildOverlays()
    end
    ns.layoutMode = on and true or false
    for _, key in ipairs({ "player", "target", "focus" }) do
        local f = ns.units[key]
        if f and f.castBar and ns.ShowCastSample then
            ns.ShowCastSample(f, ns.layoutMode)
        end
        if f and f.swingHost and ns.ShowSwingSample then
            ns.ShowSwingSample(f, ns.layoutMode)
        end
    end
    if overlays then
        for i = 1, #overlays.frames do
            local o = overlays.frames[i]
            local want = ns.layoutMode and (not o.cond or o.cond())
            o:SetShown(want and true or false)
            if want then
                local r, g, b = accent()
                o.skinbg:SetVertexColor(r, g, b, 0.20)
            end
        end
        for i = 1, #overlays.handles do
            local h = overlays.handles[i]
            h:SetShown(ns.layoutMode)
            if ns.layoutMode then
                local r, g, b = accent()
                h.skinbg:SetVertexColor(r, g, b, 0.9)
            end
        end
    end
    if ns.layoutMode then
        ns.Print("frames unlocked — drag frames and text pills. /silk lock to save.")
    else
        ns.Print("frames locked.")
    end
    refreshAllWidgets()
end

local guard = CreateFrame("Frame")
guard:RegisterEvent("PLAYER_REGEN_DISABLED")
guard:SetScript("OnEvent", function()
    if ns.layoutMode then
        ns.SetLayoutMode(false)
    end
end)

-- slash -------------------------------------------------------------------

SLASH_SILK1 = "/silk"
SlashCmdList.SILK = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "unlock" then
        ns.SetLayoutMode(true)
    elseif msg == "lock" then
        ns.SetLayoutMode(false)
    elseif msg == "test party" or msg == "testparty" or msg == "party" then
        ns.TogglePreview("party")
    elseif msg == "test" or msg == "test raid" or msg == "raid" then
        ns.TogglePreview("raid")
    elseif msg == "trace" then
        if ns.ToggleCastTrace then ns.ToggleCastTrace() end
    elseif msg == "swing" then
        if ns.SwingReport then ns.SwingReport() end
    elseif msg == "roster" or msg == "raidcheck" then
        if ns.RaidReport then ns.RaidReport() end
    elseif msg == "diag" then
        local d = ns.fontDiag or {}
        ns.Print("--- diagnostics ---")
        ns.Print(("fonts available: |cff9be8ff%d|r"):format(#ns.FontList(true)))
        ns.Print(("global font: %s"):format(tostring(ns.db.font)))
        ns.Print(("outline: |cff9be8ff%s|r   monochrome: |cff9be8ff%s|r   shadow: |cff9be8ff%s|r (%s, %s)")
            :format(tostring(ns.db.outline), tostring(ns.db.monochrome),
                    tostring(ns.db.shadow), tostring(ns.db.shadowX), tostring(ns.db.shadowY)))
        ns.Print(("backdrop: |cff9be8ff%s|r  alpha %s"):format(
            tostring(ns.db.textBg), tostring(ns.db.textBgAlpha)))
        ns.Print(("bars animating right now: |cff9be8ff%d|r (0 when everything is settled)")
            :format(ns.AnimCount and ns.AnimCount() or -1))
        local buried, names = 0, {}
        for k in pairs(ns.buriedBlizzard or {}) do
            buried = buried + 1
            names[#names + 1] = k
        end
        table.sort(names)
        ns.Print(("Blizzard frames hidden: |cff9be8ff%d|r"):format(buried))
        if buried > 0 then
            ns.Print("  " .. table.concat(names, ", "))
        end
        ns.Print(("last font applied: %s @%s  flags asked '%s' got '%s'"):format(
            tostring(d.path), tostring(d.size), tostring(d.asked), tostring(d.got)))
        if d.fellBack then
            ns.Print("|cffff6a5ecould not load:|r " .. tostring(d.fellBack))
        end
        local pf = ns.units and ns.units.player
        if pf and pf.texts and pf.texts.name then
            local p, sz, fl = pf.texts.name:GetFont()
            ns.Print(("player name text reports: %s @%s '%s'"):format(
                tostring(p), tostring(sz), tostring(fl or "")))
        end
        local overrides = 0
        for key, fcfg in pairs(ns.db.frames) do
            for tk, t in pairs(fcfg.texts or {}) do
                if (t.font or "") ~= "" or (t.outline or "") ~= "" then
                    overrides = overrides + 1
                    ns.Print(("override: %s.%s font=%s outline=%s"):format(
                        key, tk, tostring(t.font), tostring(t.outline)))
                end
            end
        end
        if overrides == 0 then ns.Print("no per-element font overrides active.") end
    elseif msg == "reset confirm" then
        ns.ResetProfile()
        refreshAllWidgets()
        ns.Print("profile reset.")
    elseif msg == "reset" then
        ns.Print("this wipes every Silk setting for this character. Type  /silk reset confirm  to proceed.")
    else
        ns.TogglePanel()
    end
end

-- keep panel skins in step with live settings -----------------------------

table.insert(ns.refreshers, function()
    if panel and panel:IsShown() then
        refreshAllWidgets()
    end
end)
