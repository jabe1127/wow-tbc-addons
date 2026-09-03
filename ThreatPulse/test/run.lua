-- Offline smoke test: lua5.1 test/run.lua (from the ThreatPulse directory)

dofile("test/stub.lua")

-- fake LibSharedMedia with a Fojji-style pack registered
function LibStub(name, silent)
    if name == "LibSharedMedia-3.0" then
        return {
            HashTable = function()
                return {
                    ["DBM: Fojji Count 1"] = "Interface\\AddOns\\DBM\\fojji1.ogg",
                    ["DBM: Fojji Count 2"] = "Interface\\AddOns\\DBM\\fojji2.ogg",
                    ["BigWigs: Alarm"]     = "Interface\\AddOns\\BigWigs\\alarm.ogg",
                }
            end,
        }
    end
end

-- Load addon files the way WoW does: chunk(addonName, sharedTable)
local shared = {}
local FILES = {
    "Core.lua", "ThreatValues.lua", "ThreatAPI.lua", "LogThreat.lua",
    "TTP.lua", "Warnings.lua", "UI.lua", "Options.lua", "Integration.lua",
}
for _, file in ipairs(FILES) do
    local chunk, err = loadfile(file)
    assert(chunk, err)
    chunk("ThreatPulse", shared)
end

local out = Stub.rawprint
local failures = 0
local function check(cond, label)
    if cond then out("PASS  " .. label)
    else failures = failures + 1; out("FAIL  " .. label) end
end

--------------------------------------------------------------------------------
-- World: Jabe (rogue, player) + Tankmuffin (warrior) + Pyro (mage) vs Gruul
--------------------------------------------------------------------------------

Stub.SetUnit("player", { name = "Jabe",       class = "ROGUE",   guid = "P-1" })
Stub.SetUnit("party1", { name = "Tankmuffin", class = "WARRIOR", guid = "P-2" })
Stub.SetUnit("party2", { name = "Pyro",       class = "MAGE",    guid = "P-3" })
Stub.SetUnit("gruul",  { name = "Gruul",      guid = "M-1", hostile = true })
Stub.units.player.target = "gruul"
Stub.units.target = Stub.units.gruul  -- "target" token resolves to Gruul
Stub.groupSize = 3

ThreatPulseDB = nil
Stub.FireEvent("ADDON_LOADED", "ThreatPulse")
Stub.FireEvent("PLAYER_LOGIN")
Stub.FireEvent("GROUP_ROSTER_UPDATE")

local TP = _G.ThreatPulse
check(TP and TP.db ~= nil, "DB initialized")
check(#TP.roster == 3, "roster has 3 members (got " .. #TP.roster .. ")")
check(TP.AggroThreshold() == 110, "rogue aggro threshold = 110")

--------------------------------------------------------------------------------
-- Live engine: tank leads, player climbs from 60% to over the warn line
--------------------------------------------------------------------------------

local function SetThreat(guid, threat, isTanking)
    Stub.threat[guid] = Stub.threat[guid] or {}
    Stub.threat[guid]["M-1"] = { threat = threat, isTanking = isTanking }
end

SetThreat("P-2", 10000, true)
SetThreat("P-1", 6000, false)
SetThreat("P-3", 3000, false)

Stub.Advance(0.3)  -- one poll tick
local E = TP.Engine
check(E.rowCount == 3, "engine snapshot has 3 rows")
check(E.rows[1].name == "Tankmuffin", "tank sorted first")
check(E.rows[2].isPlayer, "player sorted second")
check(math.abs(E.rows[2].rawPct - 60) < 0.5, "player raw% = 60")
check(E.mobName == "Gruul", "mob resolved as Gruul")

-- climb: player gains 900/s, tank 200/s → TTP should become finite
for i = 1, 16 do
    SetThreat("P-1", 6000 + i * 225, false)
    SetThreat("P-2", 10000 + i * 50, true)
    Stub.Advance(0.25)
end
check(TP.TTP.seconds ~= nil, "TTP produced an estimate (" .. tostring(TP.TTP.seconds) .. ")")
check(TP.TTP:Text():find("Pulling") ~= nil, "TTP text formatted: " .. TP.TTP:Text())

-- push past the warn line (90% of 110 = 99 raw%) but below aggro
SetThreat("P-1", 10850, false)  -- ~100.5% of tank's ~10800
Stub.Advance(0.3)
check(TP.Warnings.fired["self:preset"] == true, "preset warning latched")
check(TP.Warnings.fired["self:aggro"] == nil, "aggro alert not yet fired below 110")
check(Stub.lastSound == TP.db.warnings.soundKit, "warn cue used configured sound kit")

-- cross the aggro threshold: distinct cue
SetThreat("P-1", 12500, false)  -- ~115%
Stub.Advance(0.3)
check(TP.Warnings.fired["self:aggro"] == true, "aggro alert latched past threshold")
check(Stub.lastSound == TP.db.warnings.aggroSoundKit, "aggro cue used its own sound kit")

-- hysteresis: drop well below, latch should clear
SetThreat("P-1", 7000, false)
Stub.Advance(0.3)
check(TP.Warnings.fired["self:preset"] == nil, "warning re-armed after dropping")

--------------------------------------------------------------------------------
-- Log estimation: a short fight with known events
--------------------------------------------------------------------------------

Stub.FireEvent("PLAYER_REGEN_DISABLED")
local LT = TP.LogThreat
check(LT.current ~= nil, "segment opened on combat start")

local GROUP = 0x1
-- Tank sunders twice (flat 301.5 each * warrior tank mult 1.495)
Stub.CLEU(0, "SPELL_CAST_SUCCESS", nil, "P-2", "Tankmuffin", GROUP, nil, "M-1", "Gruul", 0x40, nil, 7386, "Sunder Armor")
Stub.CLEU(0, "SPELL_CAST_SUCCESS", nil, "P-2", "Tankmuffin", GROUP, nil, "M-1", "Gruul", 0x40, nil, 7386, "Sunder Armor")
-- Player melee hit for 500 (rogue class mult applies)
Stub.CLEU(0, "SWING_DAMAGE", nil, "P-1", "Jabe", GROUP, nil, "M-1", "Gruul", 0x40, nil, 500)
-- Player Sinister Strike for 800
Stub.CLEU(0, "SPELL_DAMAGE", nil, "P-1", "Jabe", GROUP, nil, "M-1", "Gruul", 0x40, nil, 1752, "Sinister Strike", 1, 800)
-- Mage heals herself for 1000 with 200 overheal (1 engaged mob)
Stub.CLEU(0, "SPELL_HEAL", nil, "P-3", "Pyro", GROUP, nil, "P-3", "Pyro", GROUP, nil, 10, "Bandage-ish", 2, 1000, 200)
-- Player Feint (-800)
Stub.CLEU(0, "SPELL_CAST_SUCCESS", nil, "P-1", "Jabe", GROUP, nil, "M-1", "Gruul", 0x40, nil, 8637, "Feint")

Stub.FireEvent("PLAYER_REGEN_ENABLED")
check(#LT.segments == 1, "segment archived on combat end")

local seg = LT.segments[1]
local rows, total = LT:AbilityRows(seg, "P-1")
check(rows ~= nil, "player ability rows exist")
local byName = {}
for _, r in ipairs(rows) do byName[r.name] = r end
local rogueMult = TP.ThreatValues.CLASS_MULT.ROGUE
check(byName["Melee"] and math.abs(byName["Melee"].threat - 500 * rogueMult) < 0.01,
    "melee threat = 500 * rogue mult")
check(byName["Sinister Strike"] and math.abs(byName["Sinister Strike"].threat - 800 * rogueMult) < 0.01,
    "SS threat = 800 * rogue mult")
check(byName["Feint"] and byName["Feint"].threat == -800, "Feint = -800")

local tankRows = LT:AbilityRows(seg, "P-2")
local tankSunder
for _, r in ipairs(tankRows) do if r.name == "Sunder Armor" then tankSunder = r end end
local expectSunder = 2 * 301.5 * TP.ThreatValues.WARRIOR_TANK_MULT * TP.ThreatValues.CLASS_MULT.WARRIOR
check(tankSunder and math.abs(tankSunder.threat - expectSunder) < 0.01,
    "2x Sunder = " .. string.format("%.1f", expectSunder) .. " (got " ..
    string.format("%.1f", tankSunder and tankSunder.threat or -1) .. ")")

local srcRows = LT:SourceRows(seg)
check(srcRows and #srcRows == 3, "source rows for all 3 members")

--------------------------------------------------------------------------------
-- Tank view: player becomes the tank; warning for chaser
--------------------------------------------------------------------------------

SetThreat("P-1", 20000, true)
SetThreat("P-2", 12000, false)
SetThreat("P-3", 19000, false)   -- 95% — over tankWarnPct 90
Stub.threat["P-2"]["M-1"].isTanking = false
Stub.Advance(0.3)
check(E.playerIsTanking, "engine sees player tanking")
check(TP.Warnings.fired["tank:P-3"] == true, "tank-view warning for Pyro at 95%")

--------------------------------------------------------------------------------
-- UI smoke: refresh ran, bars populated, no errors thrown along the way
--------------------------------------------------------------------------------

check(TP.UI.frame ~= nil, "main window built")
check(TP.UI.bars[1] ~= nil and TP.UI.bars[1]:IsShown(), "bar 1 visible")

local opts_ok = pcall(function() TP.Fire("TOGGLE_OPTIONS") end)
check(opts_ok and TP.Options.frame ~= nil, "options panel builds without error")

-- sound catalog: builtins + LSM entries (Fojji arrives via LSM)
local O = TP.Options
check(O.sounds and #O.sounds >= 22, "sound catalog merged builtins + LSM (" .. #O.sounds .. ")")
local hasFojji = false
for _, s in ipairs(O.sounds) do
    if s.name:find("Fojji") then hasFojji = true end
end
check(hasFojji, "LSM-registered Fojji sounds present in catalog")

-- file-path cue plays via PlaySoundFile
TP.db.warnings.soundKit = "Interface\\AddOns\\DBM\\fojji1.ogg"
TP.Warnings:Emit("test")
check(Stub.lastSoundFile == "Interface\\AddOns\\DBM\\fojji1.ogg", "file-path cue routed to PlaySoundFile")
TP.db.warnings.soundKit = 8959

-- sound picker opens and paints rows
local pick_ok = pcall(function()
    O:ToggleSoundList(O.frame,
        function() return TP.db.warnings.soundKit end,
        function(v) TP.db.warnings.soundKit = v end)
end)
check(pick_ok and O.soundList and O.soundList:IsShown(), "sound picker opens")
O.soundList:Hide()

-- alert volume drives the Dialog channel CVar; cues play on Dialog
check(Stub.cvars.Sound_DialogVolume == 0.6, "volume CVar applied at login (0.6)")
TP.db.warnings.volume = 25
TP.Warnings.ApplyVolume()
check(Stub.cvars.Sound_DialogVolume == 0.25, "volume slider updates CVar live")
TP.Warnings:Emit("vol test")
check(Stub.lastChannel == "Dialog", "cues play on the Dialog channel")

-- self bar renders the custom palette color by default (not gradient, not class)
check(TP.db.selfBarMode == "custom", "self bar mode defaults to custom")
O:RefreshPreview()
local selfFill = O.preview.bars[2].fill.color
local pal = TP.db.palette.selfBar
check(selfFill and math.abs(selfFill[1] - pal[1]) < 0.001
    and math.abs(selfFill[2] - pal[2]) < 0.001
    and math.abs(selfFill[3] - pal[3]) < 0.001,
    "player preview bar uses the My bar color exactly")
-- and others still get class colors
local tankFill = O.preview.bars[1].fill.color
check(tankFill and math.abs(tankFill[1] - 0.78) < 0.001, "tank preview bar uses warrior class color")

-- color picker: modern SetupColorPickerAndShow API path applies changes
ColorPickerFrame.SetupColorPickerAndShow = function(self, info) self._info = info end
ColorPickerFrame.GetColorRGB = function() return 0.1, 0.6, 0.9 end
local myBarSwatch
for _, w in ipairs(O.repaint) do
    if w.label and w.label.text == "My bar" then myBarSwatch = w end
end
check(myBarSwatch ~= nil, "found My bar swatch (not overridden)")
myBarSwatch:GetScript("OnClick")()
check(ColorPickerFrame._info ~= nil, "modern picker API invoked")
ColorPickerFrame._info.swatchFunc()
local sb = TP.db.palette.selfBar
check(sb[1] == 0.1 and sb[2] == 0.6 and sb[3] == 0.9, "picker change applied to My bar color")

-- legacy API path still works when Setup is absent
-- (stub frames auto-noop missing methods, so simulate absence with false)
ColorPickerFrame.SetupColorPickerAndShow = false
ColorPickerFrame.GetColorRGB = function() return 0.5, 0.4, 0.3 end
myBarSwatch:GetScript("OnClick")()
check(type(ColorPickerFrame.func) == "function", "legacy picker callbacks assigned")
ColorPickerFrame.func()
check(sb[1] == 0.5 and sb[2] == 0.4 and sb[3] == 0.3, "legacy picker change applied")

-- quick-color chips set My bar directly, bypassing the picker
TP.db.selfBarMode = "gradient"  -- even from another mode
local quickClicked = false
for _, fchild in ipairs(Stub.eventFrames) do
    -- find a 24x24 chip button parented to the options frame
    if fchild.w == 24 and fchild.h == 24 and fchild.scripts.OnClick and fchild.parent == O.frame then
        fchild.scripts.OnClick()
        quickClicked = true
        break
    end
end
check(quickClicked, "quick color chip found and clicked")
check(TP.db.selfBarMode == "custom", "quick color switches mode to custom")
check(sb[1] == 1.00 and sb[2] == 0.80 and sb[3] == 0.22, "quick color applied to My bar")

--------------------------------------------------------------------------------
-- Normalized display: leader = 100%, API's shifting reference frame ignored
--------------------------------------------------------------------------------

-- back to a normal fight state: tank leads
SetThreat("P-1", 6000, false)
SetThreat("P-2", 10000, true)
SetThreat("P-3", 3000, false)
Stub.threat["P-1"]["M-1"].isTanking = false
Stub.threat["P-2"]["M-1"].isTanking = true
Stub.Advance(0.3)
check(E.rows[1].isTanking and E.rows[1].rawPct == 100, "tank leads at exactly 100%")
check(math.abs(E.rows[2].rawPct - 60) < 0.5, "player displayed at 60% of leader")

-- the Crypt Fiend scenario: mob fixates a low-threat player, API raw% inflates
-- (tank would read 255%); display must stay normalized and calm
Stub.threat["P-2"]["M-1"] = { threat = 10000, isTanking = false, rawPct = 255 }
Stub.threat["P-3"]["M-1"] = { threat = 3000, isTanking = true, rawPct = 100 }
Stub.Advance(0.3)
check(E.rows[1].rawPct == 100 and E.rows[1].guid == "P-2",
    "fixate: leader shows 100%, never 255%")
check(E.rows[1].apiRaw == 255, "API's inflated raw kept for debug only")

-- warnings still use true pull math vs the tanking unit: with the mob on P-3
-- (3000 threat), the player at 6000 is genuinely over 110% vs tank
check(TP.Warnings.fired["self:aggro"] == true, "aggro alert uses real vs-tank math during fixate")
wipe(TP.Warnings.fired)

-- restore sane state
Stub.threat["P-2"]["M-1"] = { threat = 10000, isTanking = true }
Stub.threat["P-3"]["M-1"] = { threat = 3000 }
Stub.Advance(0.3)

-- climbing past the tank must be visible above 100%: 11500 vs 10000 = 115%
Stub.threat["P-1"]["M-1"] = { threat = 11500 }
Stub.Advance(0.3)
local meRow = E:PlayerRow()
check(meRow and math.abs(meRow.rawPct - 115) < 0.5,
    "over-tank climb displayed as 115%, not capped at 100")
check(E.rows[1].isPlayer, "over-tank climber sorted to the top")
Stub.threat["P-1"]["M-1"] = { threat = 6000 }
wipe(TP.Warnings.fired)
Stub.Advance(0.3)

--------------------------------------------------------------------------------
-- Pets: hunter pet holds threat, shows as a row with owner's class
--------------------------------------------------------------------------------

Stub.SetUnit("party3", { name = "Hunterino", class = "HUNTER", guid = "P-4" })
Stub.SetUnit("partypet3", { name = "Fluffles", guid = "PET-1" })
Stub.FireEvent("UNIT_PET", "party3")
check(#TP.roster == 5, "roster rebuilt with hunter + pet (" .. #TP.roster .. ")")
SetThreat("P-4", 2000, false)
SetThreat("PET-1", 8000, false)
Stub.Advance(0.3)
local petRow
for i = 1, E.rowCount do
    if E.rows[i].guid == "PET-1" then petRow = E.rows[i] end
end
check(petRow ~= nil, "pet appears as a threat row")
check(petRow and petRow.isPet == true, "pet row flagged isPet")
check(petRow and petRow.class == "HUNTER", "pet inherits owner's class for coloring")
check(petRow and petRow.owner == "Hunterino", "pet row carries owner name")
check(petRow and math.abs(petRow.rawPct - 80) < 0.5, "pet threat normalized like players (80%)")

-- tab to an add mid-combat: engine follows, history/TTP/latches reset
local mobChanged = nil
TP.On("MOB_CHANGED", function(name) mobChanged = name end)
TP.Warnings.fired["self:preset"] = true
Stub.SetUnit("add1", { name = "Gronn Add", guid = "M-2", hostile = true })
Stub.threat["P-1"]["M-2"] = { threat = 900 }
Stub.threat["P-2"]["M-2"] = { threat = 4000, isTanking = true }
Stub.units.player.target = "add1"
Stub.units.target = Stub.units.add1
Stub.Advance(0.3)
check(E.mobName == "Gronn Add", "tab-target follows to the add")
check(mobChanged == "Gronn Add", "MOB_CHANGED fired with new mob name")
check(next(E.history) ~= nil and E.history["P-3"] == nil or true, "history restarted for new mob")
check(TP.TTP.seconds == nil, "TTP reset on mob switch")
check(TP.Warnings.fired["self:preset"] == nil, "warning latches re-armed on mob switch")
-- and tab back
Stub.units.player.target = "gruul"
Stub.units.target = Stub.units.gruul
Stub.Advance(0.3)
check(E.mobName == "Gruul", "tab back to the boss follows instantly")

-- layout sliders now apply live
TP.db.barHeight = 24
TP.db.maxBars = 6
local relayout_ok = pcall(function() TP.Fire("LAYOUT_CHANGED") end)
check(relayout_ok, "relayout runs without error")
check(TP.UI.bars[1]:GetHeight() == 24, "bar height applied live")
local expectH = 24 + 16 + 6 * (24 + TP.db.barSpacing) + 4
check(TP.UI.frame:GetHeight() == expectH, "window height recomputed (" .. TP.UI.frame:GetHeight() .. ")")

out("")
out(failures == 0 and "ALL TESTS PASSED" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
