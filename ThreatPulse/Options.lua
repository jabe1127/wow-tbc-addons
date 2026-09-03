-- ThreatPulse Options.lua
-- Options panel: drawn primitives, live preview strip, override-aware color
-- swatches, and a scrollable sound picker fed by built-in sound kits plus
-- everything registered in LibSharedMedia (DBM / BigWigs / Fojji packs, etc).

local ADDON, TP = ...
local O = {}
TP.Options = O

local WHITE = "Interface\\Buttons\\WHITE8X8"
local WIDTH, PAD = 460, 16
local FONT = "Fonts\\FRIZQT__.TTF"
local ROW = 28

local function P(key) return TP.db.palette[key] end
local function SetTex(t, c) t:SetTexture(WHITE); t:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
local function Lerp(a, b, f) return a + (b - a) * f end

O.repaint = {}   -- widgets with a :Paint() to refresh on any change

local function Changed()
    for _, w in ipairs(O.repaint) do w:Paint() end
    O:RefreshPreview()
    TP.Fire("PALETTE_CHANGED")
end

-- The color picker API differs across client builds: older ones use the
-- .func/.cancelFunc globals, newer ones require SetupColorPickerAndShow(info)
-- and silently ignore the old assignments. Support both.
local function OpenColorPicker(c, onChange)
    local function apply()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        c[1], c[2], c[3] = r, g, b
        onChange()
    end
    local function cancel(prev)
        if prev and prev.r then
            c[1], c[2], c[3] = prev.r, prev.g, prev.b
        end
        onChange()
    end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = c[1], g = c[2], b = c[3],
            hasOpacity = false,
            swatchFunc = apply,
            cancelFunc = cancel,
        })
    else
        ColorPickerFrame.func = apply
        ColorPickerFrame.swatchFunc = apply
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.opacityFunc = nil
        ColorPickerFrame.cancelFunc = cancel
        ColorPickerFrame.previousValues = { r = c[1], g = c[2], b = c[3] }
        ColorPickerFrame:SetColorRGB(c[1], c[2], c[3])
        ColorPickerFrame:Raise()
        ColorPickerFrame:Show()
    end
end

--------------------------------------------------------------------------------
-- Sound catalog: built-in kits + LibSharedMedia ("Fojji" etc live here)
--------------------------------------------------------------------------------

-- Built-in sound kit IDs. Any ID that doesn't exist on this client just plays
-- silence — report those and they get culled.
local BUILTIN_SOUNDS = {
    { name = "Raid warning",   kit = 8959  },
    { name = "Ready check",    kit = 8960  },
    { name = "Alarm 1",        kit = 12867 },
    { name = "Alarm 2",        kit = 12889 },
    { name = "Level up",       kit = 888   },
    { name = "PvP queue",      kit = 8458  },
    { name = "Map ping",       kit = 3175  },
    { name = "Bell (Horde)",   kit = 565   },
    { name = "Bell (Alliance)",kit = 566   },
    { name = "Bell (Night Elf)", kit = 568 },
    { name = "Coin",           kit = 120   },
    { name = "Quest failed",   kit = 846   },
    { name = "Quest complete", kit = 878   },
    { name = "Whisper",        kit = 3081  },
    { name = "Player invite",  kit = 880   },
    { name = "Auction open",   kit = 5274  },
    { name = "Auction close",  kit = 5275  },
    { name = "Menu open",      kit = 850   },
    { name = "Menu option",    kit = 852   },
}

O.sounds = nil   -- { {name, value} } where value = kit id (number) or file path (string)

function O:BuildSoundCatalog()
    local list = {}
    for _, s in ipairs(BUILTIN_SOUNDS) do
        list[#list + 1] = { name = s.name, value = s.kit }
    end
    local LSM = _G.LibStub and _G.LibStub("LibSharedMedia-3.0", true)
    if LSM and LSM.HashTable then
        local media = LSM:HashTable("sound")
        if media then
            local named = {}
            for name, path in pairs(media) do
                named[#named + 1] = { name = name, value = path }
            end
            table.sort(named, function(a, b) return a.name < b.name end)
            for _, e in ipairs(named) do list[#list + 1] = e end
        end
    end
    self.sounds = list
end

function O:SoundName(value)
    if not self.sounds then self:BuildSoundCatalog() end
    for _, s in ipairs(self.sounds) do
        if s.value == value then return s.name end
    end
    return type(value) == "string" and value:match("[^\\/]+$") or ("Sound " .. tostring(value))
end

--------------------------------------------------------------------------------
-- Drawn widgets
--------------------------------------------------------------------------------

local function Label(parent, text, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size or 13, "")
    fs:SetText(text)
    local c = P("text")
    fs:SetTextColor(c[1], c[2], c[3], 1)
    return fs
end

local function SectionRule(parent, text)
    local fs = Label(parent, text, 12)
    local sc = P("subText")
    fs:SetTextColor(sc[1], sc[2], sc[3], 1)
    local rule = parent:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    SetTex(rule, P("border"))
    return fs, rule
end

local function Checkbox(parent, text, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(240, ROW - 2)
    b.box = b:CreateTexture(nil, "ARTWORK")
    b.box:SetSize(16, 16); b.box:SetPoint("LEFT", 0, 0)
    b.mark = b:CreateTexture(nil, "OVERLAY")
    b.mark:SetSize(8, 8); b.mark:SetPoint("CENTER", b.box, "CENTER")
    b.label = Label(b, text)
    b.label:SetPoint("LEFT", b.box, "RIGHT", 8, 0)
    function b:Paint()
        SetTex(self.box, P("barBg"))
        if get() then SetTex(self.mark, P("accent")); self.mark:Show()
        else self.mark:Hide() end
    end
    b:SetScript("OnClick", function() set(not get()); Changed() end)
    b:Paint()
    table.insert(O.repaint, b)
    return b
end

local function Slider(parent, text, min, max, get, set, onRelease)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(WIDTH - PAD * 2, 40)
    f.label = Label(f, text)
    f.label:SetPoint("TOPLEFT", 0, 0)
    f.value = Label(f, "", 12)
    f.value:SetPoint("TOPRIGHT", 0, 0)
    local sc = P("subText")
    f.value:SetTextColor(sc[1], sc[2], sc[3], 1)

    local track = CreateFrame("Frame", nil, f)
    track:SetHeight(14)
    track:SetPoint("BOTTOMLEFT", 0, 2); track:SetPoint("BOTTOMRIGHT", 0, 2)
    track:EnableMouse(true)
    track.bg = track:CreateTexture(nil, "ARTWORK")
    track.bg:SetPoint("LEFT"); track.bg:SetPoint("RIGHT")
    track.bg:SetHeight(4)
    track.thumb = track:CreateTexture(nil, "OVERLAY")
    track.thumb:SetSize(9, 16)

    function f:Paint()
        SetTex(track.thumb, P("accent"))
        SetTex(track.bg, P("barBg"))
        local v = get()
        local frac = (v - min) / (max - min)
        local w = track:GetWidth()
        if not w or w <= 0 then w = WIDTH - PAD * 2 end
        track.thumb:ClearAllPoints()
        track.thumb:SetPoint("CENTER", track, "LEFT", frac * w, 0)
        f.value:SetText(math.floor(v + 0.5))
    end

    local function FromCursor()
        local x = GetCursorPosition() / UIParent:GetEffectiveScale()
        local left = track:GetLeft()
        if not left then return end
        local frac = math.max(0, math.min(1, (x - left) / track:GetWidth()))
        set(math.floor(min + frac * (max - min) + 0.5))
        Changed()
    end

    track:SetScript("OnMouseDown", function()
        track:SetScript("OnUpdate", FromCursor)
    end)
    track:SetScript("OnMouseUp", function()
        track:SetScript("OnUpdate", nil)
        if onRelease then onRelease() end
    end)
    C_Timer.After(0, function() f:Paint() end)
    table.insert(O.repaint, f)
    return f
end

-- overrideFn returns a string describing what's overriding this color, or nil
local function Swatch(parent, text, colorKey, overrideFn)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(210, ROW - 2)
    b.chip = b:CreateTexture(nil, "ARTWORK")
    b.chip:SetSize(18, 18); b.chip:SetPoint("LEFT", 0, 0)
    b.edge = b:CreateTexture(nil, "BORDER")
    b.edge:SetPoint("TOPLEFT", b.chip, -1, 1); b.edge:SetPoint("BOTTOMRIGHT", b.chip, 1, -1)
    b.label = Label(b, text)
    b.label:SetPoint("LEFT", b.chip, "RIGHT", 7, 0)
    function b:Paint()
        SetTex(self.edge, P("border"))
        local over = overrideFn and overrideFn()
        local c = P(colorKey)
        if over then
            self.chip:SetTexture(WHITE)
            self.chip:SetVertexColor(c[1] * 0.35, c[2] * 0.35, c[3] * 0.35, 1)
            local sc = P("subText")
            self.label:SetText(text .. "  (" .. over .. ")")
            self.label:SetTextColor(sc[1], sc[2], sc[3], 1)
        else
            SetTex(self.chip, c)
            local tc = P("text")
            self.label:SetText(text)
            self.label:SetTextColor(tc[1], tc[2], tc[3], 1)
        end
    end
    b:SetScript("OnClick", function()
        if overrideFn and overrideFn() then return end  -- inert while overridden
        OpenColorPicker(P(colorKey), Changed)
    end)
    b:Paint()
    table.insert(O.repaint, b)
    return b
end

local function CycleButton(parent, values, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(180, ROW - 2)
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
    b.label = Label(b, "")
    b.label:SetPoint("CENTER")
    function b:Paint()
        SetTex(self.bg, P("barBg"))
        self.label:SetText(get())
    end
    b:SetScript("OnClick", function()
        local cur = get()
        for i, v in ipairs(values) do
            if v == cur then set(values[i % #values + 1]) break end
        end
        Changed()
    end)
    b:Paint()
    table.insert(O.repaint, b)
    return b
end

--------------------------------------------------------------------------------
-- Sound picker: button + scrollable drawn dropdown (mousewheel to scroll)
--------------------------------------------------------------------------------

local VISIBLE_SOUND_ROWS = 10

function O:EnsureSoundList()
    if self.soundList then return self.soundList end
    local f = CreateFrame("Frame", "ThreatPulseSoundList", UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetSize(260, VISIBLE_SOUND_ROWS * (ROW - 2) + 8)
    f:EnableMouse(true)
    f:Hide()
    f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetAllPoints()
    f.border = {}
    for i = 1, 4 do f.border[i] = f:CreateTexture(nil, "BORDER") end
    f.border[1]:SetPoint("TOPLEFT"); f.border[1]:SetPoint("TOPRIGHT"); f.border[1]:SetHeight(1)
    f.border[2]:SetPoint("BOTTOMLEFT"); f.border[2]:SetPoint("BOTTOMRIGHT"); f.border[2]:SetHeight(1)
    f.border[3]:SetPoint("TOPLEFT"); f.border[3]:SetPoint("BOTTOMLEFT"); f.border[3]:SetWidth(1)
    f.border[4]:SetPoint("TOPRIGHT"); f.border[4]:SetPoint("BOTTOMRIGHT"); f.border[4]:SetWidth(1)

    f.rows = {}
    for i = 1, VISIBLE_SOUND_ROWS do
        local r = CreateFrame("Button", nil, f)
        r:SetHeight(ROW - 2)
        r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * (ROW - 2))
        r:SetPoint("RIGHT", -4, 0)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT")
        r.hl:SetAllPoints(); r.hl:SetTexture(WHITE); r.hl:SetVertexColor(1, 1, 1, 0.06)
        r.label = Label(r, "", 12)
        r.label:SetPoint("LEFT", 4, 0)
        r.label:SetPoint("RIGHT", -4, 0)
        r.label:SetJustifyH("LEFT")
        f.rows[i] = r
    end

    f.offset = 0
    f:SetScript("OnMouseWheel", function(_, delta)
        local maxOff = math.max(0, #O.sounds - VISIBLE_SOUND_ROWS)
        f.offset = math.max(0, math.min(maxOff, f.offset - delta * 3))
        O:PaintSoundList()
    end)
    f:EnableMouseWheel(true)

    self.soundList = f
    return f
end

function O:PaintSoundList()
    local f = self.soundList
    SetTex(f.bg, P("windowBg"))
    for i = 1, 4 do SetTex(f.border[i], P("border")) end
    for i = 1, VISIBLE_SOUND_ROWS do
        local r = f.rows[i]
        local entry = self.sounds[f.offset + i]
        if entry then
            r:Show()
            local tc = (entry.value == f.currentGet()) and P("accent") or P("text")
            r.label:SetText(entry.name)
            r.label:SetTextColor(tc[1], tc[2], tc[3], 1)
            r:SetScript("OnClick", function()
                f.currentSet(entry.value)
                TP.Warnings.PlayCue(entry.value)  -- audition
                Changed()
                f:Hide()
            end)
        else
            r:Hide()
        end
    end
end

function O:ToggleSoundList(anchor, get, set)
    if not self.sounds then self:BuildSoundCatalog() end
    local f = self:EnsureSoundList()
    if f:IsShown() and f.anchor == anchor then f:Hide() return end
    f.anchor = anchor
    f.currentGet, f.currentSet = get, set
    -- start scrolled to the current selection
    f.offset = 0
    for i, s in ipairs(self.sounds) do
        if s.value == get() then
            f.offset = math.max(0, math.min(i - 1, #self.sounds - VISIBLE_SOUND_ROWS))
            break
        end
    end
    f:ClearAllPoints()
    local _, cy = anchor:GetCenter()
    if cy and cy < (UIParent:GetHeight() / 2) then
        f:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 3)
    else
        f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -3)
    end
    self:PaintSoundList()
    f:Show()
end

local function SoundButton(parent, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(240, ROW - 2)
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
    b.label = Label(b, "", 12)
    b.label:SetPoint("LEFT", 6, 0)
    b.label:SetPoint("RIGHT", -6, 0)
    b.label:SetJustifyH("LEFT")
    function b:Paint()
        SetTex(self.bg, P("barBg"))
        self.label:SetText(O:SoundName(get()))
    end
    b:SetScript("OnClick", function() O:ToggleSoundList(b, get, set) end)
    b:Paint()
    table.insert(O.repaint, b)
    return b
end

--------------------------------------------------------------------------------
-- Live preview strip
--------------------------------------------------------------------------------

local PREVIEW_ROWS = {
    { name = "Tankmuffin",  class = "WARRIOR", rawPct = 100, isTanking = true },
    { name = "Jabe",        class = "ROGUE",   rawPct = 86,  isPlayer = true },
    { name = "Pyrolicious", class = "MAGE",    rawPct = 61 },
}
local CLASS_COLORS = {
    WARRIOR = {0.78,0.61,0.43}, ROGUE = {1.00,0.96,0.41}, MAGE = {0.41,0.80,0.94},
}

function O:BuildPreview(parent, y)
    local box = CreateFrame("Frame", nil, parent)
    box:SetPoint("TOPLEFT", PAD, y)
    box:SetPoint("RIGHT", -PAD, 0)
    box:SetHeight(3 * 26 + 8)
    box.bg = box:CreateTexture(nil, "BACKGROUND")
    box.bg:SetAllPoints()
    box.bars = {}
    for i = 1, 3 do
        local bar = CreateFrame("Frame", nil, box)
        bar:SetHeight(24)
        bar:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 26)
        bar:SetPoint("RIGHT", -4, 0)
        bar.bg = bar:CreateTexture(nil, "BACKGROUND")
        bar.bg:SetAllPoints()
        bar.fill = bar:CreateTexture(nil, "ARTWORK")
        bar.fill:SetPoint("TOPLEFT"); bar.fill:SetPoint("BOTTOMLEFT")
        bar.name = Label(bar, "", 12)
        bar.name:SetPoint("LEFT", 4, 0)
        bar.pct = Label(bar, "", 12)
        bar.pct:SetPoint("RIGHT", -4, 0)
        box.bars[i] = bar
    end
    self.preview = box
    return box:GetHeight()
end

function O:RefreshPreview()
    local box = self.preview
    if not box then return end
    local db = TP.db
    SetTex(box.bg, P("windowBg"))
    local aggro = 110
    local maxPct = 1
    for _, row in ipairs(PREVIEW_ROWS) do
        if row.rawPct > maxPct then maxPct = row.rawPct end
    end
    for i, row in ipairs(PREVIEW_ROWS) do
        local bar = box.bars[i]
        local width = box:GetWidth() - 8
        if width <= 0 then width = WIDTH - PAD * 2 - 8 end
        SetTex(bar.bg, P("barBg"))
        bar.fill:SetTexture(WHITE)
        bar.fill:SetWidth(math.max(1, (row.rawPct / maxPct) * width))
        local r, g, b
        if row.isPlayer then
            local mode = db.selfBarMode or "custom"
            if mode == "gradient" then
                local fr = math.min(row.rawPct / aggro, 1)
                local cool, hot = P("cool"), P("accent")
                r, g, b = Lerp(cool[1], hot[1], fr), Lerp(cool[2], hot[2], fr), Lerp(cool[3], hot[3], fr)
            elseif mode == "class" then
                local c = CLASS_COLORS[row.class]; r, g, b = c[1], c[2], c[3]
            else
                local c = P("selfBar"); r, g, b = c[1], c[2], c[3]
            end
        elseif db.useClassColors then
            local c = CLASS_COLORS[row.class]; r, g, b = c[1], c[2], c[3]
        else
            local c = P(row.isTanking and "tankBar" or "otherBar")
            r, g, b = c[1], c[2], c[3]
        end
        bar.fill:SetVertexColor(r, g, b, 0.9)
        local tc = P("text")
        bar.name:SetText(row.name); bar.name:SetTextColor(tc[1], tc[2], tc[3], 1)
        bar.pct:SetText(row.rawPct .. "%"); bar.pct:SetTextColor(tc[1], tc[2], tc[3], 1)
    end
end

--------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------

function O:Build()
    if self.frame then return end
    local db = TP.db
    self:BuildSoundCatalog()

    local f = CreateFrame("Frame", "ThreatPulseOptions", UIParent)
    f:SetSize(WIDTH, 600)  -- provisional; corrected to content height below
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")  -- below ColorPickerFrame's DIALOG so the picker always sits on top
    f:SetMovable(true); f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:Hide()
    self.frame = f

    f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetAllPoints()
    f.border = {}
    for i = 1, 4 do f.border[i] = f:CreateTexture(nil, "BORDER") end
    f.border[1]:SetPoint("TOPLEFT"); f.border[1]:SetPoint("TOPRIGHT"); f.border[1]:SetHeight(1)
    f.border[2]:SetPoint("BOTTOMLEFT"); f.border[2]:SetPoint("BOTTOMRIGHT"); f.border[2]:SetHeight(1)
    f.border[3]:SetPoint("TOPLEFT"); f.border[3]:SetPoint("BOTTOMLEFT"); f.border[3]:SetWidth(1)
    f.border[4]:SetPoint("TOPRIGHT"); f.border[4]:SetPoint("BOTTOMRIGHT"); f.border[4]:SetWidth(1)

    local title = Label(f, "ThreatPulse", 16)
    title:SetPoint("TOP", 0, -12)
    local close = CreateFrame("Button", nil, f)
    close:SetSize(20, 20); close:SetPoint("TOPRIGHT", -10, -10)
    close.a = close:CreateTexture(nil, "ARTWORK")
    close.a:SetSize(14, 2); close.a:SetPoint("CENTER"); close.a:SetRotation(0.785)
    close.b = close:CreateTexture(nil, "ARTWORK")
    close.b:SetSize(14, 2); close.b:SetPoint("CENTER"); close.b:SetRotation(-0.785)
    SetTex(close.a, P("subText")); SetTex(close.b, P("subText"))
    close:SetScript("OnClick", function()
        f:Hide()
        if O.soundList then O.soundList:Hide() end
    end)

    f:SetScript("OnMouseDown", function() f:StartMoving() end)
    f:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)

    local y = -40

    -- Preview
    local h = self:BuildPreview(f, y)
    y = y - h - 16

    -- Colors
    local cl, crule = SectionRule(f, "Colors")
    cl:SetPoint("TOPLEFT", PAD, y)
    crule:SetPoint("TOPLEFT", PAD, y - 16); crule:SetPoint("RIGHT", -PAD, 0)
    y = y - 28

    local cb1 = Checkbox(f, "Class colors (others)",
        function() return db.useClassColors end,
        function(v) db.useClassColors = v end)
    cb1:SetPoint("TOPLEFT", PAD, y); cb1:SetSize(190, ROW - 2)

    local SELF_MODES = { custom = "My bar: Custom color", class = "My bar: Class color", gradient = "My bar: Heat gradient" }
    local SELF_ORDER = { "custom", "class", "gradient" }
    local selfMode = CycleButton(f, {}, function() return "" end, function() end) -- rebuilt below
    selfMode:SetSize(220, ROW - 2)
    selfMode:SetPoint("TOPLEFT", PAD + 210, y)
    function selfMode:Paint()
        SetTex(self.bg, P("barBg"))
        self.label:SetText(SELF_MODES[db.selfBarMode or "custom"])
    end
    selfMode:SetScript("OnClick", function()
        local cur = db.selfBarMode or "custom"
        for i, m in ipairs(SELF_ORDER) do
            if m == cur then db.selfBarMode = SELF_ORDER[i % #SELF_ORDER + 1] break end
        end
        Changed()
    end)
    selfMode:Paint()
    y = y - ROW - 4

    -- override notes keep the swatches honest about what actually renders
    local function selfOverride()
        local mode = db.selfBarMode or "custom"
        if mode == "gradient" then return "gradient active" end
        if mode == "class" then return "class color" end
    end
    local function groupOverride()
        if db.useClassColors then return "class colors" end
    end

    local swatches = {
        { "Window",  "windowBg" }, { "Bars",   "barBg" },
        { "Accent",  "accent"   }, { "Cool",   "cool"  },
        { "My bar",  "selfBar",  selfOverride  }, { "Tank",   "tankBar",  groupOverride },
        { "Others",  "otherBar", groupOverride }, { "Text",   "text"  },
    }
    for i, s in ipairs(swatches) do
        local col = (i - 1) % 2
        local rowN = math.floor((i - 1) / 2)
        local sw = Swatch(f, s[1], s[2], s[3])
        sw:SetPoint("TOPLEFT", PAD + col * 215, y - rowN * ROW)
    end
    y = y - math.ceil(#swatches / 2) * ROW - 6

    -- one-click bar colors: sets My bar directly, no color picker involved
    local qcLabel = Label(f, "My bar quick colors", 12)
    local qsc = P("subText")
    qcLabel:SetTextColor(qsc[1], qsc[2], qsc[3], 1)
    qcLabel:SetPoint("TOPLEFT", PAD, y)
    y = y - 20

    local QUICK = {
        {1.00, 0.80, 0.22}, {0.90, 0.22, 0.22}, {1.00, 0.50, 0.10},
        {0.30, 0.85, 0.35}, {0.20, 0.80, 0.75}, {0.25, 0.55, 1.00},
        {0.65, 0.40, 0.95}, {1.00, 0.45, 0.75}, {0.95, 0.95, 0.98},
        {0.62, 0.62, 0.68}, {0.35, 0.95, 1.00}, {0.70, 1.00, 0.25},
    }
    for i, qc in ipairs(QUICK) do
        local chip = CreateFrame("Button", nil, f)
        chip:SetSize(24, 24)
        chip:SetPoint("TOPLEFT", PAD + (i - 1) * 32, y)
        chip.tex = chip:CreateTexture(nil, "ARTWORK")
        chip.tex:SetAllPoints(); chip.tex:SetTexture(WHITE)
        chip.tex:SetVertexColor(qc[1], qc[2], qc[3], 1)
        chip.edge = chip:CreateTexture(nil, "BORDER")
        chip.edge:SetPoint("TOPLEFT", -1, 1); chip.edge:SetPoint("BOTTOMRIGHT", 1, -1)
        SetTex(chip.edge, P("border"))
        chip:SetScript("OnClick", function()
            local c = P("selfBar")
            c[1], c[2], c[3] = qc[1], qc[2], qc[3]
            db.selfBarMode = "custom"   -- clicking a color means you want that color
            Changed()
        end)
    end
    y = y - 24 - 14

    -- Warnings
    local wl, wrule = SectionRule(f, "Warnings")
    wl:SetPoint("TOPLEFT", PAD, y)
    wrule:SetPoint("TOPLEFT", PAD, y - 16); wrule:SetPoint("RIGHT", -PAD, 0)
    y = y - 28

    local roleLabel = Label(f, "Role preset")
    roleLabel:SetPoint("TOPLEFT", PAD, y - 3)
    local role = CycleButton(f, { "auto", "melee", "ranged", "tank" },
        function() return db.warnings.role end,
        function(v) db.warnings.role = v end)
    role:SetPoint("TOPLEFT", PAD + 120, y)

    local test = CreateFrame("Button", nil, f)
    test:SetSize(52, ROW - 2)
    test:SetPoint("TOPRIGHT", -PAD, y)
    test.bg = test:CreateTexture(nil, "BACKGROUND"); test.bg:SetAllPoints()
    test.label = Label(test, "Test"); test.label:SetPoint("CENTER")
    function test:Paint() SetTex(self.bg, P("barBg")) end
    test:Paint(); table.insert(O.repaint, test)
    test:SetScript("OnClick", function() TP.Fire("TEST_WARNING") end)
    y = y - ROW - 6

    local s1 = Slider(f, "Warn at % of aggro threshold", 50, 110,
        function() return db.warnings.warnPct end,
        function(v) db.warnings.warnPct = v end)
    s1:SetPoint("TOPLEFT", PAD, y)
    y = y - 46

    local s2 = Slider(f, "Tank view: warn when others reach raw %", 50, 110,
        function() return db.warnings.tankWarnPct end,
        function(v) db.warnings.tankWarnPct = v end)
    s2:SetPoint("TOPLEFT", PAD, y)
    y = y - 50

    local wsLabel = Label(f, "Warn sound")
    wsLabel:SetPoint("TOPLEFT", PAD, y - 3)
    local ws = SoundButton(f,
        function() return db.warnings.soundKit end,
        function(v) db.warnings.soundKit = v end)
    ws:SetPoint("TOPLEFT", PAD + 120, y)
    y = y - ROW - 2

    local asLabel = Label(f, "Aggro sound")
    asLabel:SetPoint("TOPLEFT", PAD, y - 3)
    local as = SoundButton(f,
        function() return db.warnings.aggroSoundKit end,
        function(v) db.warnings.aggroSoundKit = v end)
    as:SetPoint("TOPLEFT", PAD + 120, y)
    y = y - ROW - 6

    local vol = Slider(f, "Alert volume", 0, 100,
        function() return db.warnings.volume or 60 end,
        function(v)
            db.warnings.volume = v
            TP.Warnings.ApplyVolume()
        end,
        function()
            TP.Warnings.PlayCue(db.warnings.soundKit)  -- hear it at the new volume
        end)
    vol:SetPoint("TOPLEFT", PAD, y)
    y = y - 46

    local acb = Checkbox(f, "Alert when I cross the aggro threshold",
        function() return db.warnings.aggroAlert end,
        function(v) db.warnings.aggroAlert = v end)
    acb:SetPoint("TOPLEFT", PAD, y); acb:SetSize(340, ROW - 2)
    y = y - ROW - 2

    local wcb1 = Checkbox(f, "Sound",
        function() return db.warnings.sound end,
        function(v) db.warnings.sound = v end)
    wcb1:SetPoint("TOPLEFT", PAD, y); wcb1:SetSize(85, ROW - 2)
    local wcb2 = Checkbox(f, "Screen flash",
        function() return db.warnings.flash end,
        function(v) db.warnings.flash = v end)
    wcb2:SetPoint("TOPLEFT", PAD + 100, y); wcb2:SetSize(130, ROW - 2)
    local wcb3 = Checkbox(f, "Text splash",
        function() return db.warnings.splash end,
        function(v) db.warnings.splash = v end)
    wcb3:SetPoint("TOPLEFT", PAD + 245, y); wcb3:SetSize(130, ROW - 2)
    y = y - ROW - 10

    -- Display
    local dl, drule = SectionRule(f, "Display")
    dl:SetPoint("TOPLEFT", PAD, y)
    drule:SetPoint("TOPLEFT", PAD, y - 16); drule:SetPoint("RIGHT", -PAD, 0)
    y = y - 28

    local s3 = Slider(f, "Bar height", 12, 28,
        function() return db.barHeight end,
        function(v) db.barHeight = v; TP.Fire("LAYOUT_CHANGED") end)
    s3:SetPoint("TOPLEFT", PAD, y)
    y = y - 46

    local s4 = Slider(f, "Max bars", 4, 20,
        function() return db.maxBars end,
        function(v) db.maxBars = v; TP.Fire("LAYOUT_CHANGED") end)
    s4:SetPoint("TOPLEFT", PAD, y)
    y = y - 50

    local dcb1 = Checkbox(f, "Show time-to-pull",
        function() return db.showTTP end,
        function(v) db.showTTP = v end)
    dcb1:SetPoint("TOPLEFT", PAD, y); dcb1:SetSize(190, ROW - 2)
    local dcb2 = Checkbox(f, "Auto tank view",
        function() return db.autoTankView end,
        function(v) db.autoTankView = v end)
    dcb2:SetPoint("TOPLEFT", PAD + 210, y); dcb2:SetSize(180, ROW - 2)
    y = y - ROW

    -- size the panel to its content — nothing spills
    f:SetHeight(-y + 14)

    self:ApplyPalette()
    self:RefreshPreview()
end

function O:ApplyPalette()
    local f = self.frame
    if not f then return end
    SetTex(f.bg, P("windowBg"))
    for i = 1, 4 do SetTex(f.border[i], P("border")) end
end

TP.On("TOGGLE_OPTIONS", function()
    if not O.frame then O:Build() end
    if O.frame:IsShown() then
        O.frame:Hide()
        if O.soundList then O.soundList:Hide() end
    else
        O.frame:Show(); O:RefreshPreview()
    end
end)

TP.On("PALETTE_CHANGED", function() O:ApplyPalette() end)
