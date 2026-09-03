-- PulseMeter Bosses.lua
-- TBC raid bosses + world bosses. Fights whose primary enemy is in this table
-- get their own group in the browser; everything else lands in "Trash".

local ADDON, ns = ...

ns.BOSSES = {
	-- Karazhan
	["Attumen the Huntsman"] = true, ["Midnight"] = true, ["Moroes"] = true,
	["Maiden of Virtue"] = true, ["The Big Bad Wolf"] = true, ["Romulo"] = true,
	["Julianne"] = true, ["The Crone"] = true, ["Dorothee"] = true,
	["The Curator"] = true, ["Terestian Illhoof"] = true, ["Shade of Aran"] = true,
	["Netherspite"] = true, ["Prince Malchezaar"] = true, ["Nightbane"] = true,
	["Echo of Medivh"] = true,
	-- Gruul's Lair
	["High King Maulgar"] = true, ["Gruul the Dragonkiller"] = true,
	-- Magtheridon's Lair
	["Magtheridon"] = true,
	-- Serpentshrine Cavern
	["Hydross the Unstable"] = true, ["The Lurker Below"] = true,
	["Leotheras the Blind"] = true, ["Fathom-Lord Karathress"] = true,
	["Morogrim Tidewalker"] = true, ["Lady Vashj"] = true,
	-- Tempest Keep
	["Al'ar"] = true, ["Void Reaver"] = true, ["High Astromancer Solarian"] = true,
	["Kael'thas Sunstrider"] = true,
	-- Battle for Mount Hyjal
	["Rage Winterchill"] = true, ["Anetheron"] = true, ["Kaz'rogal"] = true,
	["Azgalor"] = true, ["Archimonde"] = true,
	-- Black Temple
	["High Warlord Naj'entus"] = true, ["Supremus"] = true, ["Shade of Akama"] = true,
	["Teron Gorefiend"] = true, ["Gurtogg Bloodboil"] = true,
	["Reliquary of Souls"] = true, ["Essence of Suffering"] = true,
	["Essence of Desire"] = true, ["Essence of Anger"] = true,
	["Mother Shahraz"] = true, ["The Illidari Council"] = true,
	["Gathios the Shatterer"] = true, ["High Nethermancer Zerevor"] = true,
	["Lady Malande"] = true, ["Veras Darkshadow"] = true,
	["Illidan Stormrage"] = true,
	-- Zul'Aman
	["Nalorakk"] = true, ["Akil'zon"] = true, ["Jan'alai"] = true,
	["Halazzi"] = true, ["Hex Lord Malacrass"] = true, ["Zul'jin"] = true,
	-- Sunwell Plateau
	["Kalecgos"] = true, ["Sathrovarr the Corruptor"] = true, ["Brutallus"] = true,
	["Felmyst"] = true, ["Grand Warlock Alythess"] = true, ["Lady Sacrolash"] = true,
	["M'uru"] = true, ["Entropius"] = true, ["Kil'jaeden"] = true,
	-- World bosses
	["Doom Lord Kazzak"] = true, ["Doomwalker"] = true,
}
