--=====================================================================
-- GlassTip - Options
--=====================================================================
local ADDON, ns = ...

local WHITE = "Interface\\Buttons\\WHITE8X8"
local C

local function get(tbl, key) return function() return ns.db[tbl][key] end end
local function set(tbl, key) return function(v) ns.db[tbl][key] = v end end

local POINT_OPTIONS = {}
for _, p in ipairs({ "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }) do
    POINT_OPTIONS[#POINT_OPTIONS + 1] = { value = p, text = p:gsub("TOP", "Top "):gsub("BOTTOM", "Bottom "):gsub("LEFT", "Left"):gsub("RIGHT", "Right"):gsub("CENTER", "Center"):gsub("^%s*(.-)%s*$", "%1") }
end

local function pct(v) return string.format("%d%%", v * 100 + 0.5) end
local function num(v) return tostring(v) end
local function pxs(v) return v .. " px" end

--=====================================================================
-- Preview
--=====================================================================
local function BuildPreview(parent)
    local pv = CreateFrame("Frame", nil, parent)
    pv:SetSize(230, 82)

    pv.fallbackBG = ns:Fill(pv, 0.06, 0.06, 0.10, 0.92, -8)
    pv.fallbackBG:Hide()
    pv.fallbackEdge = ns:Outline(pv, 0.42, 0.42, 0.48, 1)
    for _, e in pairs(pv.fallbackEdge) do e:Hide() end

    pv.name = ns:FS(pv, 15)
    pv.name:SetPoint("TOPLEFT", pv, "TOPLEFT", 10, -10)

    pv.line2 = ns:FS(pv, 12)
    pv.line2:SetPoint("TOPLEFT", pv.name, "BOTTOMLEFT", 0, -4)

    pv.line3 = ns:FS(pv, 12)
    pv.line3:SetPoint("TOPLEFT", pv.line2, "BOTTOMLEFT", 0, -4)

    pv.bar = CreateFrame("StatusBar", nil, pv)
    pv.bar:SetStatusBarTexture(WHITE)
    pv.bar:SetMinMaxValues(0, 100)
    pv.bar:SetValue(74)
    pv.barBG = pv.bar:CreateTexture(nil, "BACKGROUND", nil, -2)
    pv.barBG:SetTexture(WHITE)
    pv.barBG:SetAllPoints(pv.bar)
    pv.barL = ns:FS(pv.bar, 11)
    pv.barL:SetPoint("LEFT", pv.bar, "LEFT", 5, 0)
    pv.barR = ns:FS(pv.bar, 11)
    pv.barR:SetPoint("RIGHT", pv.bar, "RIGHT", -5, 0)

    ns.preview = pv
    return pv
end

function ns:UpdatePreview()
    local pv = ns.preview
    if not pv then return end
    local st, bar = ns.db.style, ns.db.bar

    ns:ApplySkin(pv)
    pv.fallbackBG:SetShown(st.blizzard)
    for _, e in pairs(pv.fallbackEdge) do e:SetShown(st.blizzard) end
    -- the unit is hostile, so the reaction colour is red; the frame follows
    -- whatever the skin says
    local ur, ug, ub = 0.92, 0.27, 0.29
    local r, g, b = ur, ug, ub
    if st.borderMode == "custom" then r, g, b = st.border[1], st.border[2], st.border[3] end
    ns:ColorSkin(pv, r, g, b)

    local pal = ns.db.palette
    ns:ApplyFont(pv.name, st.nameSize)
    ns:ApplyFont(pv.line2, st.bodySize)
    ns:ApplyFont(pv.line3, st.bodySize)
    pv.name:SetText("Gruul the Dragonkiller")
    pv.name:SetTextColor(ur, ug, ub)
    pv.line2:SetText(("|cff%sLevel|r |cffff2020??|r |cff%sBoss|r |cff%sGiant|r")
        :format(pal.label, pal.tag, pal.type))
    pv.line3:SetText(("|cff%sKil'jaeden's Vanguard|r |cff%s\226\128\162|r |cff%sOverlord|r")
        :format(pal.guild, pal.sep, pal.rank))

    pv.bar:ClearAllPoints()
    pv.bar:SetPoint("BOTTOMLEFT", pv, "BOTTOMLEFT", 8, 6)
    pv.bar:SetPoint("BOTTOMRIGHT", pv, "BOTTOMRIGHT", -8, 6)
    pv.bar:SetHeight(bar.height)
    pv.bar:SetShown(bar.show)
    pv.bar:SetStatusBarTexture(bar.sheen and ns.TEX.bar or "Interface\\Buttons\\WHITE8X8")
    pv.bar:SetStatusBarColor(ur, ug, ub)
    pv.barBG:SetVertexColor(ur * 0.16, ug * 0.16, ub * 0.16, 0.85)
    ns:ApplyFont(pv.barL, bar.textSize)
    ns:ApplyFont(pv.barR, bar.textSize)
    pv.barL:SetText(bar.text and ("|cff" .. pal.barText .. "485k / 655k") or "")
    pv.barR:SetText((bar.text and bar.percent) and ("|cff" .. pal.barSub .. "74%") or "")
    if bar.textInside and bar.height >= 12 then
        pv.barL:ClearAllPoints(); pv.barL:SetPoint("LEFT", pv.bar, "LEFT", 5, 0)
        pv.barR:ClearAllPoints(); pv.barR:SetPoint("RIGHT", pv.bar, "RIGHT", -5, 0)
    else
        pv.barL:ClearAllPoints(); pv.barL:SetPoint("BOTTOMLEFT", pv.bar, "TOPLEFT", 1, 2)
        pv.barR:ClearAllPoints(); pv.barR:SetPoint("BOTTOMRIGHT", pv.bar, "TOPRIGHT", -1, 2)
    end
end

--=====================================================================
-- Pages
--=====================================================================
local pages = {}

local function PageAnchor(p)
    return {
        ns:Header(p, "Anchor mode"),
        ns:Dropdown(p, "Where should the tooltip appear?", {
            { value = "mouse", text = "Follow the mouse cursor" },
            { value = "fixed", text = "Fixed screen position" },
        }, get("anchor", "mode"), set("anchor", "mode")),

        ns:Header(p, "Mouse anchor"),
        ns:Dropdown(p, "Tooltip corner pinned to the cursor", POINT_OPTIONS,
            get("anchor", "mousePoint"), set("anchor", "mousePoint")),
        ns:Slider(p, "Horizontal offset (X)", -300, 300, 1, get("anchor", "mouseX"), set("anchor", "mouseX"), pxs),
        ns:Slider(p, "Vertical offset (Y)", -300, 300, 1, get("anchor", "mouseY"), set("anchor", "mouseY"), pxs),
        ns:Check(p, "Keep on screen (flip near edges)", get("anchor", "clamp"), set("anchor", "clamp"),
            "Near an edge the tooltip flips to the other side of the cursor rather than sliding under it. Also applies to the fixed anchor."),

        ns:Header(p, "Character pane gear"),
        ns:Check(p, "Anchor gear tooltips to the pane", get("anchor", "paneEnabled"), set("anchor", "paneEnabled"),
            "Hovering gear in the character or inspect window pins the tooltip to one spot on the pane instead of to each individual slot, so every slot behaves the same and tall tooltips stop running off the top."),
        ns:Dropdown(p, "Which side of the pane", {
            { value = "BOTTOM", text = "Below the pane" },
            { value = "TOP",    text = "Above the pane" },
            { value = "LEFT",   text = "Left of the pane" },
            { value = "RIGHT",  text = "Right of the pane" },
            { value = "AUTO",   text = "Whichever side has room" },
        }, get("anchor", "paneSide"), set("anchor", "paneSide")),
        ns:Slider(p, "Pane offset (X)", -200, 200, 1, get("anchor", "paneX"), set("anchor", "paneX"), pxs),
        ns:Slider(p, "Pane offset (Y)", -200, 200, 1, get("anchor", "paneY"), set("anchor", "paneY"), pxs),

        ns:Header(p, "Item tooltips"),
        ns:Dropdown(p, "Where item tooltips go", {
            { value = "anchor", text = "Always at the item anchor" },
            { value = "pane",   text = "Character pane when open, anchor otherwise" },
            { value = "off",    text = "Leave them alone (Blizzard default)" },
        }, get("anchor", "itemMode"), set("anchor", "itemMode")),
        ns:Check(p, "Lock item anchor", get("anchor", "itemLocked"), set("anchor", "itemLocked"),
            "Unlock to drag the orange item anchor box wherever you want gear tooltips to appear."),
        ns:Dropdown(p, "Growth point", POINT_OPTIONS, get("anchor", "itemPoint"), set("anchor", "itemPoint")),
        ns:Slider(p, "Item offset (X)", -300, 300, 1, get("anchor", "itemX"), set("anchor", "itemX"), pxs),
        ns:Slider(p, "Item offset (Y)", -300, 300, 1, get("anchor", "itemY"), set("anchor", "itemY"), pxs),

        ns:Header(p, "Fixed anchor"),
        ns:Check(p, "Lock anchor frame", get("anchor", "locked"), set("anchor", "locked"),
            "Unlock to drag the anchor box around the screen. Also available with /gtip unlock."),
        ns:Dropdown(p, "Growth point", POINT_OPTIONS, get("anchor", "fixedPoint"), set("anchor", "fixedPoint")),
        ns:Slider(p, "Horizontal offset (X)", -300, 300, 1, get("anchor", "fixedX"), set("anchor", "fixedX"), pxs),
        ns:Slider(p, "Vertical offset (Y)", -300, 300, 1, get("anchor", "fixedY"), set("anchor", "fixedY"), pxs),
    }
end

local function PageStyle(p)
    local fontOpts = ns:FontOptions()
    return {
        ns:Header(p, "Frame"),
        ns:Check(p, "Use the Blizzard tooltip frame", get("style", "blizzard"), set("style", "blizzard"),
            "Gives the game its own background and border back and turns off everything GlassTip draws. Anchoring, the health bar, fonts, content and profiles all keep working."),
        ns:Slider(p, "Scale", 0.6, 1.6, 0.01, get("style", "scale"), set("style", "scale"),
            function(v) return string.format("%.2f", v) end),
        ns:Slider(p, "Background opacity", 0, 1, 0.01, get("style", "bgAlpha"), set("style", "bgAlpha"), pct),
        ns:ColorSwatch(p, "Background colour", get("style", "bg"), set("style", "bg")),

        ns:Header(p, "Border"),
        ns:Dropdown(p, "Border colour source", {
            { value = "reaction", text = "Unit reaction / class colour" },
            { value = "custom",   text = "Fixed colour" },
        }, get("style", "borderMode"), set("style", "borderMode")),
        ns:ColorSwatch(p, "Fixed border colour", get("style", "border"), set("style", "border")),
        ns:Slider(p, "Border thickness", 0, 4, 1, get("style", "borderSize"), set("style", "borderSize"),
            function(v) return v <= 0 and "none" or (v .. " px") end),
        ns:Check(p, "Accent bar along the top", get("style", "accent"), set("style", "accent")),
        ns:Slider(p, "Accent thickness", 1, 6, 1, get("style", "accentSize"), set("style", "accentSize"), pxs),
        ns:Check(p, "Drop shadow", get("style", "shadow"), set("style", "shadow")),
        ns:Check(p, "Glass sheen", get("style", "gloss"), set("style", "gloss")),
        ns:Check(p, "Fade in", get("style", "fade"), set("style", "fade")),

        ns:Header(p, "Text"),
        ns:Dropdown(p, "Font", fontOpts, get("style", "font"), set("style", "font"),
            { maxRows = 12, renderFont = true }),
        ns:Dropdown(p, "Font outline", {
            { value = "NONE", text = "None" },
            { value = "OUTLINE", text = "Thin outline" },
            { value = "THICKOUTLINE", text = "Thick outline" },
        }, get("style", "outline"), set("style", "outline")),
        ns:Slider(p, "Name size", 8, 24, 1, get("style", "nameSize"), set("style", "nameSize"), num),
        ns:Slider(p, "Body size", 8, 20, 1, get("style", "bodySize"), set("style", "bodySize"), num),
    }
end

local function PageHealth(p)
    return {
        ns:Header(p, "Health bar"),
        ns:Check(p, "Show health bar", get("bar", "show"), set("bar", "show")),
        ns:Slider(p, "Bar height", 3, 26, 1, get("bar", "height"), set("bar", "height"), pxs),
        ns:Dropdown(p, "Bar position", {
            { value = "bottom", text = "Bottom of tooltip" },
            { value = "top",    text = "Top of tooltip" },
        }, get("bar", "position"), set("bar", "position")),
        ns:Dropdown(p, "Bar colour", {
            { value = "reaction", text = "Reaction / class colour" },
            { value = "class",    text = "Class colour (players)" },
            { value = "gradient", text = "Green to red by health" },
        }, get("bar", "colorMode"), set("bar", "colorMode")),

        ns:Header(p, "Health text"),
        ns:Dropdown(p, "What to show", {
            { value = "auto",    text = "Numbers when available, otherwise %" },
            { value = "number",  text = "Numbers only" },
            { value = "percent", text = "Percent only" },
            { value = "both",    text = "Numbers and percent" },
        }, get("content", "hpMode"), set("content", "hpMode")),
        ns:Check(p, "Show health text", get("bar", "text"), set("bar", "text")),
        ns:Check(p, "Show percent on the right", get("bar", "percent"), set("bar", "percent")),
        ns:Check(p, "Draw text inside the bar", get("bar", "textInside"), set("bar", "textInside"),
            "Off, or with a bar under 12px tall, the text sits above the bar instead."),
        ns:Slider(p, "Health text size", 8, 18, 1, get("bar", "textSize"), set("bar", "textSize"), num),

        ns:Header(p, "Abbreviation"),
        ns:Check(p, "Abbreviate large numbers (485k)", get("content", "abbreviate"), set("content", "abbreviate")),
        ns:Slider(p, "Abbreviate above", 1000, 100000, 1000, get("content", "abbrevAt"), set("content", "abbrevAt"),
            function(v) return tostring(v) end),
    }
end

local function PageContent(p)
    return {
        ns:Header(p, "Creatures"),
        ns:Check(p, "Level", get("content", "showLevel"), set("content", "showLevel")),
        ns:Check(p, "Elite / Rare / Boss tag", get("content", "showClassif"), set("content", "showClassif")),
        ns:Check(p, "Creature type (Humanoid, Beast...)", get("content", "showType"), set("content", "showType")),

        ns:Header(p, "Players"),
        ns:Check(p, "Guild name", get("content", "showGuild"), set("content", "showGuild")),
        ns:Check(p, "Guild rank", get("content", "showGuildRank"), set("content", "showGuildRank")),
        ns:Check(p, "Realm name", get("content", "showRealm"), set("content", "showRealm")),
        ns:Check(p, "Race", get("content", "showRace"), set("content", "showRace")),
        ns:Check(p, "Class", get("content", "showClassText"), set("content", "showClassText")),

        ns:Header(p, "World names"),
        ns:Check(p, "Hide friendly totem names", get("content", "hideTotemNamesFriendly"), set("content", "hideTotemNamesFriendly"),
            "Turns off the floating name above friendly totems. This is a client setting, so it stays changed until you untick it here."),
        ns:Check(p, "Hide enemy totem names", get("content", "hideTotemNamesEnemy"), set("content", "hideTotemNamesEnemy"),
            "Same for enemy totems. Careful in PvP: you lose the label telling you which totem it is."),
        ns:Check(p, "Hide pet names", get("content", "hidePetNames"), set("content", "hidePetNames"),
            "Pets and guardians, friendly and enemy. Your original settings are restored when you untick it."),

        ns:Header(p, "Tooltip suppression"),
        ns:Check(p, "No tooltip for friendly totems", get("content", "noTotemTooltipFriendly"), set("content", "noTotemTooltipFriendly"),
            "Stops the tooltip appearing when you sweep the mouse over your own totem cluster."),
        ns:Check(p, "No tooltip for enemy totems", get("content", "noTotemTooltipEnemy"), set("content", "noTotemTooltipEnemy"),
            "You will not see enemy totem health this way, which matters if you are the one killing them."),
        ns:Check(p, "No tooltip for pets", get("content", "noPetTooltip"), set("content", "noPetTooltip"),
            "Pets and guardians. You will not see their health this way."),

        ns:Header(p, "Extras"),
        ns:Check(p, "Show the unit's current target", get("content", "showTarget"), set("content", "showTarget")),
        ns:Check(p, "Hide unit tooltips in combat", get("content", "hideInCombat"), set("content", "hideInCombat")),
    }
end

--=====================================================================
-- Skins page
--=====================================================================
local function SkinCard(parent, key)
    local skin = ns.skins[key]
    local f = CreateFrame("Button", nil, parent)
    f:SetHeight(56)
    ns:Fill(f, ns.C.raised[1], ns.C.raised[2], ns.C.raised[3], 1, -6)
    local edge = ns:Outline(f, 1, 1, 1, 0.10)

    local sw = CreateFrame("Frame", nil, f)
    sw:SetSize(38, 38)
    sw:SetPoint("LEFT", f, "LEFT", 10, 0)
    local swt = ns:Fill(sw, skin.swatch[1], skin.swatch[2], skin.swatch[3], 1, -5)
    ns:Outline(sw, 0, 0, 0, 0.7)

    local nameFS = ns:FS(f, 14)
    nameFS:SetPoint("TOPLEFT", sw, "TOPRIGHT", 12, -2)
    nameFS:SetText(skin.name)

    local blurb = ns:FS(f, 11, ns.C.dim[1], ns.C.dim[2], ns.C.dim[3])
    blurb:SetPoint("TOPLEFT", nameFS, "BOTTOMLEFT", 0, -4)
    blurb:SetPoint("RIGHT", f, "RIGHT", -46, 0)
    blurb:SetJustifyH("LEFT")
    blurb:SetText(skin.blurb)

    local check = ns:FS(f, 14, ns.C.accent[1], ns.C.accent[2], ns.C.accent[3])
    check:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    check:SetText("\226\151\143")
    check:Hide()

    f:SetScript("OnEnter", function()
        for _, e in pairs(edge) do e:SetVertexColor(ns.C.accent[1], ns.C.accent[2], ns.C.accent[3], 0.7) end
    end)
    f:SetScript("OnLeave", function()
        local on = ns:CurrentSkin() == key
        for _, e in pairs(edge) do
            if on then e:SetVertexColor(ns.C.accent[1], ns.C.accent[2], ns.C.accent[3], 0.9)
            else e:SetVertexColor(1, 1, 1, 0.10) end
        end
    end)
    f:SetScript("OnClick", function() ns:SetSkin(key) end)

    function f:Update()
        local on = ns:CurrentSkin() == key
        check:SetShown(on)
        for _, e in pairs(edge) do
            e:SetVertexColor(on and ns.C.accent[1] or 1, on and ns.C.accent[2] or 1,
                             on and ns.C.accent[3] or 1, on and 0.9 or 0.10)
        end
    end
    f:Update()
    f.height = 56
    return f
end

local function PageSkins(p)
    local w = { ns:Header(p, "Skins") }
    for _, key in ipairs(ns.skinOrder) do
        w[#w + 1] = SkinCard(p, key)
    end
    local note = CreateFrame("Frame", nil, p)
    note:SetHeight(46)
    local fs = ns:FS(note, 11, ns.C.dim[1], ns.C.dim[2], ns.C.dim[3])
    fs:SetPoint("TOPLEFT")
    fs:SetPoint("TOPRIGHT")
    fs:SetJustifyH("LEFT")
    fs:SetSpacing(3)
    fs:SetText("A skin sets colours, frame, font and bar together. Everything it sets stays editable on the other pages, and your anchor settings are never touched.")
    note.height = 46
    w[#w + 1] = note
    return w
end

--=====================================================================
-- Profiles page
--=====================================================================
local function ProfileRow(parent)
    local f = CreateFrame("Button", nil, parent)
    f:SetHeight(28)
    ns:Fill(f, ns.C.raised[1], ns.C.raised[2], ns.C.raised[3], 1, -6)
    local edge = ns:Outline(f, 1, 1, 1, 0.10)

    local dot = ns:FS(f, 12, ns.C.accent[1], ns.C.accent[2], ns.C.accent[3])
    dot:SetPoint("LEFT", f, "LEFT", 10, 0)

    local fs = ns:FS(f, 12)
    fs:SetPoint("LEFT", f, "LEFT", 26, 0)

    local del = ns:Button(f, "\195\151", function()
        if f.pname then StaticPopup_Show("GLASSTIP_DELETE_PROFILE", f.pname, nil, f.pname) end
    end, 22)
    del:SetPoint("RIGHT", f, "RIGHT", -6, 0)
    del:SetHeight(18)

    f:SetScript("OnClick", function() if f.pname then ns:ActivateProfile(f.pname) end end)
    f:SetScript("OnEnter", function()
        for _, e in pairs(edge) do e:SetVertexColor(ns.C.accent[1], ns.C.accent[2], ns.C.accent[3], 0.7) end
    end)
    f:SetScript("OnLeave", function() f:Update() end)

    function f:SetProfile(name)
        self.pname = name
        fs:SetText(name)
        del:SetShown(name ~= "Default")
        self:Update()
    end

    function f:Update()
        local on = ns.activeProfile == self.pname
        dot:SetText(on and "\226\151\143" or "")
        fs:SetTextColor(on and ns.C.accent[1] or ns.C.text[1],
                        on and ns.C.accent[2] or ns.C.text[2],
                        on and ns.C.accent[3] or ns.C.text[3])
        for _, e in pairs(edge) do
            e:SetVertexColor(on and ns.C.accent[1] or 1, on and ns.C.accent[2] or 1,
                             on and ns.C.accent[3] or 1, on and 0.9 or 0.10)
        end
    end
    f.height = 28
    return f
end

local function PageProfiles(p)
    local head = ns:Header(p, "Profiles")

    local who = CreateFrame("Frame", nil, p)
    who:SetHeight(32)
    local whoFS = ns:FS(who, 11, ns.C.dim[1], ns.C.dim[2], ns.C.dim[3])
    whoFS:SetPoint("TOPLEFT")
    whoFS:SetPoint("TOPRIGHT")
    whoFS:SetJustifyH("LEFT")
    whoFS:SetSpacing(3)
    whoFS:SetText("This character uses the selected profile and will keep using it. Other characters keep their own.")
    who.height = 32

    local list = CreateFrame("Frame", nil, p)
    list:SetHeight(30)
    list.rows = {}

    function list:Rebuild()
        local names = ns:ProfileNames()
        for i, name in ipairs(names) do
            local row = self.rows[i]
            if not row then
                row = ProfileRow(self)
                self.rows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(i - 1) * 32)
            row:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -(i - 1) * 32)
            row:SetProfile(name)
            row:Show()
        end
        for i = #names + 1, #self.rows do self.rows[i]:Hide() end
        local h = math.max(30, #names * 32)
        self:SetHeight(h)
        self.height = h
        if p.relayout then p.relayout() end
    end

    function list:Update() self:Rebuild() end
    list:Rebuild()

    local newBtn = ns:Button(p, "New profile", function()
        StaticPopup_Show("GLASSTIP_NEW_PROFILE")
    end, 140)
    newBtn.height = 24

    local copyBtn = ns:Button(p, "Copy current to new", function()
        StaticPopup_Show("GLASSTIP_COPY_PROFILE")
    end, 180)
    copyBtn.height = 24

    return { head, who, list, newBtn, copyBtn }
end

StaticPopupDialogs["GLASSTIP_NEW_PROFILE"] = {
    text = "Name for the new profile:",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    maxLetters = 32,
    OnAccept = function(self)
        local box = self.editBox or (self.GetEditBox and self:GetEditBox())
        local name = box and box:GetText()
        if name and not ns:CreateProfile(name) then
            print("|cff7fd5ffGlassTip:|r that name is already taken.")
        end
        if ns.RefreshOptions then ns:RefreshOptions() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["GLASSTIP_COPY_PROFILE"] = {
    text = "Name for the copy:",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    maxLetters = 32,
    OnAccept = function(self)
        local box = self.editBox or (self.GetEditBox and self:GetEditBox())
        local name = box and box:GetText()
        if name and not ns:CreateProfile(name, ns.activeProfile) then
            print("|cff7fd5ffGlassTip:|r that name is already taken.")
        end
        if ns.RefreshOptions then ns:RefreshOptions() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["GLASSTIP_DELETE_PROFILE"] = {
    text = "Delete the profile \"%s\"?",
    button1 = DELETE or "Delete",
    button2 = CANCEL or "Cancel",
    OnAccept = function(self, data)
        ns:DeleteProfile(data)
        if ns.RefreshOptions then ns:RefreshOptions() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

--=====================================================================
-- Window
--=====================================================================
function ns:BuildOptions()
    if ns.optionsFrame then return ns.optionsFrame end
    C = ns.C

    local f = CreateFrame("Frame", "GlassTipOptions", UIParent)
    f:SetSize(620, 560)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "GlassTipOptions")

    ns:Fill(f, C.panel[1], C.panel[2], C.panel[3], 0.98, -7)
    ns:Outline(f, 0, 0, 0, 0.9, 1)
    ns:Outline(f, 1, 1, 1, 0.10)

    -- title bar
    local title = CreateFrame("Frame", nil, f)
    title:SetPoint("TOPLEFT")
    title:SetPoint("TOPRIGHT")
    title:SetHeight(44)
    ns:Fill(title, 0.02, 0.025, 0.035, 1, -6)
    local accent = ns.px(title, "ARTWORK")
    accent:SetHeight(2)
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("TOPRIGHT")
    accent:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
    ns.SetGradient(accent, "HORIZONTAL", C.accent[1], C.accent[2], C.accent[3], 1, C.accent[1], C.accent[2], C.accent[3], 0.1)
    local tline = ns.px(title, "ARTWORK")
    tline:SetHeight(1)
    tline:SetPoint("BOTTOMLEFT")
    tline:SetPoint("BOTTOMRIGHT")
    tline:SetVertexColor(1, 1, 1, 0.08)

    local ttl = ns:FS(title, 16)
    ttl:SetPoint("LEFT", title, "LEFT", 16, 1)
    ttl:SetText("|cff7fd5ffGlass|rTip")
    local sub = ns:FS(title, 11, C.dim[1], C.dim[2], C.dim[3])
    sub:SetPoint("LEFT", ttl, "RIGHT", 8, 0)
    sub:SetText("unit tooltips")

    local close = ns:Button(title, "\195\151", function() f:Hide() end, 26)
    close:SetPoint("RIGHT", title, "RIGHT", -10, 0)

    -- nav
    local nav = CreateFrame("Frame", nil, f)
    nav:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, 0)
    nav:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    nav:SetWidth(148)
    ns:Fill(nav, 0.035, 0.04, 0.05, 1, -6)
    local navLine = ns.px(nav, "ARTWORK")
    navLine:SetWidth(1)
    navLine:SetPoint("TOPRIGHT")
    navLine:SetPoint("BOTTOMRIGHT")
    navLine:SetVertexColor(1, 1, 1, 0.07)

    -- content area
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", nav, "TOPRIGHT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 104)

    local scroll = CreateFrame("ScrollFrame", nil, body)
    scroll:SetPoint("TOPLEFT", body, "TOPLEFT", 18, -14)
    scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -18, 10)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxS = math.max(0, (self.contentHeight or 0) - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxS, cur - delta * 40)))
    end)

    -- preview strip
    local pvHolder = CreateFrame("Frame", nil, f)
    pvHolder:SetPoint("BOTTOMLEFT", nav, "BOTTOMRIGHT", 0, 0)
    pvHolder:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    pvHolder:SetHeight(104)
    ns:Fill(pvHolder, 0.028, 0.032, 0.04, 1, -6)
    local pvLine = ns.px(pvHolder, "ARTWORK")
    pvLine:SetHeight(1)
    pvLine:SetPoint("TOPLEFT")
    pvLine:SetPoint("TOPRIGHT")
    pvLine:SetVertexColor(1, 1, 1, 0.07)
    local pvLabel = ns:FS(pvHolder, 10, C.dim[1], C.dim[2], C.dim[3])
    pvLabel:SetPoint("TOPLEFT", pvHolder, "TOPLEFT", 18, -8)
    pvLabel:SetText("LIVE PREVIEW")

    local pv = BuildPreview(pvHolder)
    pv:SetPoint("LEFT", pvHolder, "LEFT", 18, -8)

    local resetBtn = ns:Button(pvHolder, "Reset this profile", function()
        ns:ResetProfile()
    end, 150)
    resetBtn:SetPoint("BOTTOMRIGHT", pvHolder, "BOTTOMRIGHT", -18, 16)

    local unlockBtn = ns:Button(pvHolder, "Toggle anchor", function()
        ns.db.anchor.locked = not ns.db.anchor.locked
        if not ns.db.anchor.locked then ns.db.anchor.mode = "fixed" end
        ns:Refresh()
        ns:RefreshOptions()
    end, 150)
    unlockBtn:SetPoint("BOTTOM", resetBtn, "TOP", 0, 6)

    -- build pages
    local defs = {
        { key = "skins",   label = "Skins",      build = PageSkins },
        { key = "anchor",  label = "Anchor",     build = PageAnchor },
        { key = "style",   label = "Appearance", build = PageStyle },
        { key = "health",  label = "Health",     build = PageHealth },
        { key = "content", label = "Content",    build = PageContent },
        { key = "profiles", label = "Profiles",  build = PageProfiles },
    }

    ns.optionWidgets = {}
    local navButtons = {}

    local function ShowPage(key)
        for _, d in ipairs(defs) do
            pages[d.key]:SetShown(d.key == key)
            navButtons[d.key].sel:SetShown(d.key == key)
            navButtons[d.key].text:SetTextColor(
                d.key == key and C.accent[1] or C.text[1],
                d.key == key and C.accent[2] or C.text[2],
                d.key == key and C.accent[3] or C.text[3])
        end
        scroll:SetScrollChild(pages[key])
        scroll.contentHeight = pages[key].contentHeight or 0
        scroll:SetVerticalScroll(0)
        pages[key]:SetWidth(scroll:GetWidth())
    end

    for i, d in ipairs(defs) do
        local page = CreateFrame("Frame", nil, scroll)
        page:SetWidth(410)
        page:SetHeight(1)
        pages[d.key] = page

        local widgets = d.build(page)
        for _, w in ipairs(widgets) do ns.optionWidgets[#ns.optionWidgets + 1] = w end
        page.relayout = function()
            local hh = ns:Stack(page, widgets, 8)
            page.contentHeight = hh + 20
            page:SetHeight(page.contentHeight)
            if scroll:GetScrollChild() == page then scroll.contentHeight = page.contentHeight end
        end
        page.relayout()
        page:Hide()

        local b = CreateFrame("Button", nil, nav)
        b:SetHeight(32)
        b:SetPoint("TOPLEFT", nav, "TOPLEFT", 0, -12 - (i - 1) * 34)
        b:SetPoint("TOPRIGHT", nav, "TOPRIGHT", 0, -12 - (i - 1) * 34)
        local hl = ns.px(b, "BACKGROUND", -5)
        hl:SetAllPoints(b)
        hl:SetVertexColor(1, 1, 1, 0.05)
        hl:Hide()
        local sel = ns.px(b, "ARTWORK")
        sel:SetWidth(3)
        sel:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        sel:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
        sel:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
        sel:Hide()
        local t = ns:FS(b, 13)
        t:SetPoint("LEFT", b, "LEFT", 18, 0)
        t:SetText(d.label)
        b.sel, b.text = sel, t
        b:SetScript("OnEnter", function() hl:Show() end)
        b:SetScript("OnLeave", function() hl:Hide() end)
        b:SetScript("OnClick", function() ShowPage(d.key) end)
        navButtons[d.key] = b
    end

    local hint = ns:FS(nav, 10, C.dim[1], C.dim[2], C.dim[3])
    hint:SetPoint("BOTTOMLEFT", nav, "BOTTOMLEFT", 14, 14)
    hint:SetText("/gtip\n/gtip unlock\n/gtip reset")
    hint:SetJustifyH("LEFT")
    hint:SetSpacing(3)

    f:SetScript("OnShow", function()
        ns:RefreshOptions()
        ns:UpdatePreview()
    end)
    f:Hide()

    ns.optionsFrame = f
    ShowPage("skins")
    return f
end

function ns:RefreshOptions()
    if not ns.optionWidgets then return end
    for _, w in ipairs(ns.optionWidgets) do
        if w.Update then w:Update() end
    end
    ns:UpdatePreview()
end

function ns:ToggleOptions()
    local f = ns:BuildOptions()
    if f:IsShown() then f:Hide() else f:Show() end
end

--=====================================================================
-- Live preview follows any settings change
--=====================================================================
local coreRefresh = ns.Refresh
function ns:Refresh()
    coreRefresh(self)
    if ns.optionsFrame and ns.optionsFrame:IsShown() then
        ns:UpdatePreview()
    end
end

--=====================================================================
-- Blizzard settings entry
--=====================================================================
local proxy = CreateFrame("Frame")
proxy.name = "GlassTip"
proxy:Hide()
proxy:SetScript("OnShow", function(self)
    if self.built then return end
    self.built = true
    local t = self:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, -16)
    t:SetText("GlassTip")
    local d = self:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -8)
    d:SetText("All GlassTip settings live in its own window.")
    local b = CreateFrame("Button", nil, self, "UIPanelButtonTemplate")
    if b then
        b:SetSize(180, 24)
        b:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -14)
        b:SetText("Open GlassTip options")
        b:SetScript("OnClick", function()
            if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
            if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then HideUIPanel(InterfaceOptionsFrame) end
            ns:ToggleOptions()
        end)
    end
end)

local reg = CreateFrame("Frame")
reg:RegisterEvent("PLAYER_LOGIN")
reg:SetScript("OnEvent", function()
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, proxy, "GlassTip")
        if ok and cat then
            cat.ID = "GlassTip"
            pcall(Settings.RegisterAddOnCategory, cat)
        end
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(proxy)
    end
end)
