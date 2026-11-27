-- NeverQuest Profiles: 1-60 leveling plans for every race and class in WoW Forever.
--
-- A plan is built from these parts:
--   * two zone routes for your race and faction, one per leveling style:
--       zone by zone   bands of zones; you stay in a zone until its quests run out
--       optimized      a route of zones with level windows, worked out from the quest data:
--                      leave when the window ends, come back later when the rest is worth it
--   * class milestones (class quests, talents, riding, dual spec)
--   * dungeon windows (when a dungeon is worth running for your level)
-- Inside each zone the live guide picks the quests. Zone level ranges reported by the game
-- client always win over the fallback ranges listed here.
--
-- Facts (zone levels, travel links, class quest levels, dungeon levels, race/class combos) were
-- cross-checked against published WoW Forever references in November 2026. The optimized routes
-- (1.27) are worked out from QuestieDB's quest data for WoW Forever: every quest each race can
-- take, with its level, giver, objective areas and turn-in, levelled 1-60 in a simulator that
-- routes each zone visit the way the in-game planner does. Each route is the order of zones and
-- level windows that kept the simulated character questing (time with nothing to do counted
-- double), with legs of at least two levels in zones that fit them, the starting zone first, and
-- no early trip to the other continent people don't already make. Skyborne keep the older
-- route. Levels 31-60 weren't part of the Forever beta, so expect those legs to be tuned as the
-- game settles.

local ADDON, ns = ...
local P = {}
ns.Profiles = P

---------------------------------------------------------------------------
-- Zones: fallback level ranges, faction (A = Alliance, H = Horde, C = contested), continent
---------------------------------------------------------------------------
P.ZONES = {
	-- Eastern Kingdoms
	["Elwynn Forest"] = { 1, 10, "A", "EK" },
	["Dun Morogh"] = { 1, 10, "A", "EK" },
	["Tirisfal Glades"] = { 1, 10, "H", "EK" },
	["Westfall"] = { 10, 20, "A", "EK" },
	["Loch Modan"] = { 10, 20, "A", "EK" },
	["Silverpine Forest"] = { 10, 20, "H", "EK" },
	["Redridge Mountains"] = { 15, 25, "A", "EK" },
	["Duskwood"] = { 18, 30, "A", "EK" },
	["Wetlands"] = { 20, 30, "A", "EK" },
	["Hillsbrad Foothills"] = { 20, 30, "C", "EK" },
	["Alterac Mountains"] = { 30, 40, "C", "EK" },
	["Arathi Highlands"] = { 30, 40, "C", "EK" },
	["Stranglethorn Vale"] = { 30, 45, "C", "EK" },
	["Badlands"] = { 35, 45, "C", "EK" },
	["Swamp of Sorrows"] = { 35, 45, "C", "EK" },
	["Riverglades"] = { 36, 44, "C", "EK", new = true },
	["The Hinterlands"] = { 40, 50, "C", "EK" },
	["Searing Gorge"] = { 43, 50, "C", "EK" },
	["Blasted Lands"] = { 45, 55, "C", "EK" },
	["Burning Steppes"] = { 50, 58, "C", "EK" },
	["Western Plaguelands"] = { 51, 58, "C", "EK" },
	["Eastern Plaguelands"] = { 53, 60, "C", "EK" },
	-- Kalimdor
	["Teldrassil"] = { 1, 10, "A", "K" },
	["Durotar"] = { 1, 10, "H", "K" },
	["Mulgore"] = { 1, 10, "H", "K" },
	["Darkshore"] = { 10, 20, "A", "K" },
	["The Barrens"] = { 10, 25, "H", "K" },
	["Stonetalon Mountains"] = { 15, 27, "C", "K" },
	["Ashenvale"] = { 18, 30, "C", "K" },
	["Thousand Needles"] = { 25, 35, "C", "K" },
	["Desolace"] = { 30, 40, "C", "K" },
	["Shen'dralas"] = { 35, 45, "C", "K", new = true },
	["Dustwallow Marsh"] = { 35, 45, "C", "K" },
	["Feralas"] = { 40, 50, "C", "K" },
	["Tanaris"] = { 40, 50, "C", "K" },
	["Azshara"] = { 45, 55, "C", "K" },
	["Un'Goro Crater"] = { 48, 55, "C", "K" },
	["Felwood"] = { 48, 55, "C", "K" },
	["Winterspring"] = { 55, 60, "C", "K" },
	["Silithus"] = { 55, 60, "C", "K" },
	["Mount Hyjal"] = { 56, 60, "C", "K", new = true },
	-- Skyborne start
	["Zephras Isle"] = { 1, 12, "C", "Z", new = true },
}

---------------------------------------------------------------------------
-- Races and classes
---------------------------------------------------------------------------
-- Keyed by the race token the game reports (second value of UnitRace).
P.RACES = {
	Human = { name = "Human", faction = "Alliance", route = "human" },
	Dwarf = { name = "Dwarf", faction = "Alliance", route = "dwarf" },
	Gnome = { name = "Gnome", faction = "Alliance", route = "dwarf" },
	NightElf = { name = "Night Elf", faction = "Alliance", route = "nightelf" },
	Orc = { name = "Orc", faction = "Horde", route = "orc" },
	Troll = { name = "Troll", faction = "Horde", route = "orc" },
	Tauren = { name = "Tauren", faction = "Horde", route = "tauren" },
	Scourge = { name = "Undead", faction = "Horde", route = "undead" },
	Skyborne = { name = "Skyborne", faction = nil, route = { Alliance = "skyborne_a", Horde = "skyborne_h" },
		names = { Alliance = "High Order Skyborne", Horde = "Windshaper Skyborne" } },
}

-- Browsable race entries (Skyborne listed once per faction).
P.RACE_LIST = {
	{ token = "Human", faction = "Alliance" }, { token = "Dwarf", faction = "Alliance" },
	{ token = "Gnome", faction = "Alliance" }, { token = "NightElf", faction = "Alliance" },
	{ token = "Skyborne", faction = "Alliance" },
	{ token = "Orc", faction = "Horde" }, { token = "Troll", faction = "Horde" },
	{ token = "Tauren", faction = "Horde" }, { token = "Scourge", faction = "Horde" },
	{ token = "Skyborne", faction = "Horde" },
}

P.CLASS_NAMES = {
	WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
	SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}
P.CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

-- Playable combinations: [class] = { Alliance = {races}, Horde = {races} } (56 in all).
P.COMBOS = {
	WARRIOR = { Alliance = { "Skyborne", "Human", "Dwarf", "NightElf", "Gnome" }, Horde = { "Skyborne", "Orc", "Scourge", "Tauren", "Troll" } },
	PALADIN = { Alliance = { "Human", "Dwarf" }, Horde = { "Scourge" } },
	HUNTER = { Alliance = { "Skyborne", "Human", "Dwarf", "NightElf" }, Horde = { "Skyborne", "Orc", "Tauren", "Troll" } },
	ROGUE = { Alliance = { "Skyborne", "Human", "Dwarf", "NightElf", "Gnome" }, Horde = { "Skyborne", "Orc", "Scourge", "Troll" } },
	PRIEST = { Alliance = { "Human", "Dwarf", "NightElf", "Gnome" }, Horde = { "Scourge", "Troll" } },
	SHAMAN = { Alliance = { "Dwarf" }, Horde = { "Skyborne", "Orc", "Tauren", "Troll" } },
	MAGE = { Alliance = { "Skyborne", "Human", "Gnome" }, Horde = { "Orc", "Scourge", "Troll" } },
	WARLOCK = { Alliance = { "Human", "Gnome" }, Horde = { "Orc", "Scourge", "Troll" } },
	DRUID = { Alliance = { "Skyborne", "NightElf" }, Horde = { "Skyborne", "Tauren" } },
}

---------------------------------------------------------------------------
-- Zone routes: { from, to, { zones in order of preference }, note }
---------------------------------------------------------------------------
local SHARED_HIGH = {
	{ 41, 45, { "Riverglades", "Badlands", "Swamp of Sorrows", "Dustwallow Marsh", "Shen'dralas" } },
	{ 45, 49, { "Tanaris", "Feralas", "The Hinterlands", "Searing Gorge" } },
	{ 49, 53, { "Un'Goro Crater", "Felwood", "Azshara", "Blasted Lands" } },
	{ 53, 56, { "Burning Steppes", "Western Plaguelands", "Felwood", "Un'Goro Crater" } },
	{ 56, 60, { "Mount Hyjal", "Eastern Plaguelands", "Winterspring", "Silithus" },
		"Mount Hyjal's quests open at 54 and mostly sit at 56-60. You reach it through Winterspring." },
	{ 60, 60, { "Mount Hyjal", "Eastern Plaguelands", "Winterspring" }, "Level 60: finish zones and start dungeons." },
}

local ALLIANCE_MID = {
	{ 17, 21, { "Redridge Mountains", "Westfall" }, "Finish Westfall's last quests if you left any." },
	{ 21, 25, { "Wetlands", "Redridge Mountains" }, "The boat from Menethil Harbor now continues to Southshore." },
	{ 25, 28, { "Duskwood", "Ashenvale" } },
	{ 28, 31, { "Hillsbrad Foothills", "Wetlands", "Duskwood" } },
	{ 31, 36, { "Arathi Highlands", "Stranglethorn Vale", "Alterac Mountains", "Desolace" } },
	{ 36, 41, { "Riverglades", "Shen'dralas", "Stranglethorn Vale", "Dustwallow Marsh" },
		"Riverglades: by road off Redridge, or by ship from Steamwheedle Port in Tanaris. Shen'dralas: through Desolace." },
}

local HORDE_MID = {
	{ 31, 36, { "Thousand Needles", "Arathi Highlands", "Desolace", "Stranglethorn Vale" } },
	{ 36, 41, { "Riverglades", "Shen'dralas", "Stranglethorn Vale", "Dustwallow Marsh", "Desolace" },
		"Riverglades: by road off Redridge, or by ship from Steamwheedle Port in Tanaris. Shen'dralas: through Desolace." },
}

local function Join(...)
	local out = {}
	for i = 1, select("#", ...) do
		for _, band in ipairs((select(i, ...))) do table.insert(out, band) end
	end
	return out
end

P.ROUTES = {
	human = Join({
		{ 1, 11, { "Elwynn Forest" }, "Your starting zone." },
		{ 11, 17, { "Westfall", "Loch Modan" } },
	}, ALLIANCE_MID, SHARED_HIGH),
	dwarf = Join({
		{ 1, 11, { "Dun Morogh" }, "Your starting zone." },
		{ 11, 17, { "Loch Modan", "Westfall" } },
	}, ALLIANCE_MID, SHARED_HIGH),
	nightelf = Join({
		{ 1, 11, { "Teldrassil" }, "Your starting zone." },
		{ 11, 17, { "Darkshore", "Westfall" }, "A ship links Auberdine and Stormwind Harbor, so you can join Westfall early." },
		{ 17, 21, { "Darkshore", "Redridge Mountains", "Westfall" } },
		{ 21, 25, { "Ashenvale", "Wetlands" } },
		{ 25, 28, { "Duskwood", "Ashenvale", "Stonetalon Mountains" } },
		{ 28, 31, { "Hillsbrad Foothills", "Wetlands", "Duskwood" } },
		ALLIANCE_MID[5], ALLIANCE_MID[6],
	}, SHARED_HIGH),
	skyborne_a = Join({
		{ 1, 12, { "Zephras Isle" }, "Your starting zone. Most Skyborne leave around 12-14." },
		{ 12, 17, { "Westfall", "Elwynn Forest", "Loch Modan" }, "Pick up the Elwynn quests you skipped, then Westfall." },
	}, ALLIANCE_MID, SHARED_HIGH),
	orc = Join({
		{ 1, 11, { "Durotar" }, "Your starting zone." },
		{ 11, 16, { "The Barrens" }, "Most of the Horde meets at the Crossroads around 12." },
		{ 16, 21, { "The Barrens", "Silverpine Forest" } },
		{ 21, 25, { "Stonetalon Mountains", "The Barrens", "Hillsbrad Foothills" } },
		{ 25, 28, { "Ashenvale", "Hillsbrad Foothills" } },
		{ 28, 31, { "Thousand Needles", "Hillsbrad Foothills", "Ashenvale" } },
	}, HORDE_MID, SHARED_HIGH),
	tauren = Join({
		{ 1, 11, { "Mulgore" }, "Your starting zone." },
		{ 11, 16, { "The Barrens" }, "Most of the Horde meets at the Crossroads around 12." },
		{ 16, 21, { "The Barrens", "Silverpine Forest" } },
		{ 21, 25, { "Stonetalon Mountains", "The Barrens", "Hillsbrad Foothills" } },
		{ 25, 28, { "Ashenvale", "Hillsbrad Foothills" } },
		{ 28, 31, { "Thousand Needles", "Hillsbrad Foothills", "Ashenvale" } },
	}, HORDE_MID, SHARED_HIGH),
	undead = Join({
		{ 1, 11, { "Tirisfal Glades" }, "Your starting zone." },
		{ 11, 19, { "Silverpine Forest", "The Barrens" }, "Undead can stay in Silverpine longer than other Horde races." },
		{ 19, 23, { "Hillsbrad Foothills", "The Barrens" } },
		{ 23, 27, { "Stonetalon Mountains", "Ashenvale", "Hillsbrad Foothills" } },
		{ 27, 31, { "Thousand Needles", "Ashenvale", "Hillsbrad Foothills" } },
	}, HORDE_MID, SHARED_HIGH),
	skyborne_h = Join({
		{ 1, 12, { "Zephras Isle" }, "Your starting zone. Most Skyborne leave around 12-14." },
		{ 12, 16, { "The Barrens", "Silverpine Forest" } },
		{ 16, 21, { "The Barrens", "Silverpine Forest" } },
		{ 21, 25, { "Stonetalon Mountains", "The Barrens", "Hillsbrad Foothills" } },
		{ 25, 28, { "Ashenvale", "Hillsbrad Foothills" } },
		{ 28, 31, { "Thousand Needles", "Hillsbrad Foothills", "Ashenvale" } },
	}, HORDE_MID, SHARED_HIGH),
}

---------------------------------------------------------------------------
-- Optimized routes: { from, to, zone, note, alt = second choice }. Leave a zone when its window
-- ends, even if quests are left: some legs come back for them when they give better XP.
---------------------------------------------------------------------------
local FAST_SHARED = {
	{ 31, 34, "Arathi Highlands", "Refuge Pointe (Alliance) or Hammerfall (Horde). City of Dalaran (28-33) and Scarlet Monastery fit around here.", alt = "Alterac Mountains" },
	{ 34, 37, "Stranglethorn Vale", "The northern camps first. Leave Booty Bay's later chains for the hop back.", alt = "Desolace" },
	{ 37, 43, "Riverglades", "By road from northern Redridge, or by ship from Steamwheedle Port in Tanaris. Krol'dok Stronghold (40-45) is here; riding at 40." },
	{ 43, 45, "Stranglethorn Vale", "Hop back for Booty Bay's later chains. The Drowned City (35-40) is in this zone if you skipped it.", alt = "Shen'dralas" },
	{ 45, 48, "Tanaris", "Gadgetzan. Zul'Farrak (44-48).", alt = "Feralas" },
	{ 48, 50, "Feralas", "Feathermoon (Alliance) or Camp Mojache (Horde). Maraudon and Alcaz Prison (48-53) fit here.", alt = "The Hinterlands" },
	{ 50, 52, "Un'Goro Crater", "Marshal's Refuge." },
	{ 52, 54, "Felwood", "Emerald Sanctuary, then Timbermaw Hold.", alt = "Azshara" },
	{ 54, 56, "Western Plaguelands", "Chillwind Camp or the Bulwark. Blackrock Depths fits here.", alt = "Burning Steppes" },
	{ 56, 58, "Eastern Plaguelands", "Light's Hope Chapel. Blackmaw Hold (55-60) is in Azshara." },
	{ 58, 60, "Winterspring", "Everlook. Mount Hyjal's quests open from 54.", alt = "Silithus" },
	{ 60, 60, "Mount Hyjal", "Level 60: through Darkwhisper Gorge in Winterspring." },
}

local FAST_ALLIANCE_20 = {
	{ 20, 22, "Redridge Mountains", "Back to Lakeshire for the upper Redridge chains." },
	{ 22, 25, "Wetlands", "Bind in Menethil Harbor. Take the Excavation Site quests for its dungeon (24-29)." },
	{ 25, 28, "Duskwood", "Darkshire's chains. The Stockade fits here.", alt = "Ashenvale" },
	{ 28, 30, "Hillsbrad Foothills", "The boat from Menethil Harbor now continues to Southshore.", alt = "Wetlands" },
	{ 30, 31, "Duskwood", "Hop back to finish Duskwood's late chains." },
}

local FAST_HORDE_19 = {
	{ 19, 22, "Stonetalon Mountains", "Sun Rock Retreat." },
	{ 22, 24, "The Barrens", "Hop back to finish the northern Barrens. Wailing Caverns (18-22) if you have a group." },
	{ 24, 27, "Ashenvale", "Splintertree Post. Blackfathom Deeps (23-26)." },
	{ 27, 30, "Thousand Needles", "Freewind Post, with Camp Taurajo's southern Barrens quests on the way. Razorfen Kraul from 29.", alt = "Hillsbrad Foothills" },
	{ 30, 31, "Hillsbrad Foothills", "Tarren Mill's quick quests on the way to Arathi." },
}

local function Legs(...)
	local out = {}
	for i = 1, select("#", ...) do
		local part = (select(i, ...))
		for _, leg in ipairs(part) do table.insert(out, leg) end
	end
	return out
end

P.FAST_ROUTES = {
	human = {
		{ 1, 12, "Elwynn Forest", "Your starting zone." },
		{ 12, 17, "Loch Modan", "Thelsamar." },
		{ 17, 19, "Westfall", "Sentinel Hill." },
		{ 19, 25, "Redridge Mountains", "Lakeshire." },
		{ 25, 28, "Wetlands", "Menethil Harbor. The boat continues to Southshore." },
		{ 28, 30, "Ashenvale", "Astranaar." },
		{ 30, 34, "Desolace", "Nijel's Point." },
		{ 34, 42, "Riverglades", "By road from northern Redridge." },
		{ 42, 46, "Stranglethorn Vale", "The camps in the north, then Booty Bay." },
		{ 46, 48, "Searing Gorge", "Thorium Point." },
		{ 48, 50, "Tanaris", "Gadgetzan." },
		{ 50, 52, "Azshara", "Talrendis Point." },
		{ 52, 54, "Felwood", "Emerald Sanctuary, then Timbermaw Hold." },
		{ 54, 56, "Western Plaguelands", "Chillwind Camp." },
		{ 56, 60, "Eastern Plaguelands", "Light's Hope Chapel." },
		{ 60, 60, "Mount Hyjal", "Level 60: through Darkwhisper Gorge in Winterspring." },
	},
	dwarf = {
		{ 1, 11, "Dun Morogh", "Your starting zone." },
		{ 11, 17, "Loch Modan", "Thelsamar." },
		{ 17, 19, "Westfall", "Sentinel Hill." },
		{ 19, 23, "Redridge Mountains", "Lakeshire." },
		{ 23, 28, "Wetlands", "Menethil Harbor. The boat continues to Southshore." },
		{ 28, 30, "Ashenvale", "Astranaar." },
		{ 30, 34, "Desolace", "Nijel's Point." },
		{ 34, 42, "Riverglades", "By road from northern Redridge." },
		{ 42, 45, "Stranglethorn Vale", "The camps in the north, then Booty Bay." },
		{ 45, 48, "Searing Gorge", "Thorium Point." },
		{ 48, 50, "Un'Goro Crater", "Marshal's Refuge." },
		{ 50, 52, "Azshara", "Talrendis Point." },
		{ 52, 54, "Felwood", "Emerald Sanctuary, then Timbermaw Hold." },
		{ 54, 56, "Western Plaguelands", "Chillwind Camp." },
		{ 56, 60, "Eastern Plaguelands", "Light's Hope Chapel." },
		{ 60, 60, "Mount Hyjal", "Level 60: through Darkwhisper Gorge in Winterspring." },
	},
	nightelf = {
		{ 1, 10, "Teldrassil", "Your starting zone." },
		{ 10, 17, "Darkshore", "Auberdine. A ship links Auberdine and Stormwind Harbor." },
		{ 17, 20, "Westfall", "Sentinel Hill." },
		{ 20, 24, "Redridge Mountains", "Lakeshire." },
		{ 24, 29, "Wetlands", "Menethil Harbor. The boat continues to Southshore." },
		{ 29, 31, "Duskwood", "Darkshire." },
		{ 31, 34, "Desolace", "Nijel's Point." },
		{ 34, 42, "Riverglades", "By road from northern Redridge." },
		{ 42, 44, "Stranglethorn Vale", "The camps in the north, then Booty Bay." },
		{ 44, 48, "Tanaris", "Gadgetzan." },
		{ 48, 50, "Feralas", "Feathermoon." },
		{ 50, 52, "Un'Goro Crater", "Marshal's Refuge." },
		{ 52, 54, "Azshara", "Talrendis Point." },
		{ 54, 56, "Western Plaguelands", "Chillwind Camp." },
		{ 56, 60, "Eastern Plaguelands", "Light's Hope Chapel." },
		{ 60, 60, "Mount Hyjal", "Level 60: through Darkwhisper Gorge in Winterspring." },
	},
	orc = {
		{ 1, 12, "Durotar", "Your starting zone." },
		{ 12, 20, "The Barrens", "The Crossroads, then Ratchet and Camp Taurajo." },
		{ 20, 22, "Stonetalon Mountains", "Sun Rock Retreat." },
		{ 22, 24, "The Barrens", "Back to The Barrens for its later quests." },
		{ 24, 26, "Ashenvale", "Splintertree Post." },
		{ 26, 29, "Thousand Needles", "Freewind Post and the Shimmering Flats." },
		{ 29, 31, "Hillsbrad Foothills", "Tarren Mill." },
		{ 31, 33, "Stranglethorn Vale", "Grom'gol, then Booty Bay." },
		{ 33, 39, "Arathi Highlands", "Hammerfall." },
		{ 39, 41, "Riverglades", "By road from northern Redridge, or by ship from Steamwheedle Port in Tanaris." },
		{ 41, 43, "Badlands", "Kargath." },
		{ 43, 45, "Stranglethorn Vale", "Back to Stranglethorn Vale for its later quests." },
		{ 45, 47, "Feralas", "Camp Mojache." },
		{ 47, 50, "The Hinterlands", "Revantusk Village." },
		{ 50, 52, "Azshara", "Valormok." },
		{ 52, 54, "Felwood", "Bloodvenom Post, then Timbermaw Hold." },
		{ 54, 56, "Blasted Lands", "Nethergarde's foes, on the way to the Dark Portal." },
		{ 56, 60, "Eastern Plaguelands", "Light's Hope Chapel." },
		{ 60, 60, "Mount Hyjal", "Level 60: through Darkwhisper Gorge in Winterspring." },
	},
	tauren = {
		{ 1, 10, "Mulgore", "Your starting zone." },
		{ 10, 20, "The Barrens", "The Crossroads, then Ratchet and Camp Taurajo." },
		{ 20, 23, "Stonetalon Mountains", "Sun Rock Retreat." },
		{ 23, 25, "The Barrens", "Back to The Barrens for its later quests." },
		{ 25, 27, "Ashenvale", "Splintertree Post." },
		{ 27, 31, "Hillsbrad Foothills", "Tarren Mill." },
		{ 31, 35, "Arathi Highlands", "Hammerfall." },
		{ 35, 42, "Riverglades", "By road from northern Redridge, or by ship from Steamwheedle Port in Tanaris." },
		{ 42, 44, "Stranglethorn Vale", "Grom'gol, then Booty Bay." },
		{ 44, 46, "Tanaris", "Gadgetzan." },
		{ 46, 48, "The Hinterlands", "Revantusk Village." },
		{ 48, 50, "Feralas", "Camp Mojache." },
		{ 50, 52, "Un'Goro Crater", "Marshal's Refuge." },
		{ 52, 54, "Azshara", "Valormok." },
		{ 54, 56, "Felwood", "Bloodvenom Post, then Timbermaw Hold." },
		{ 56, 60, "Eastern Plaguelands", "Light's Hope Chapel." },
		{ 60, 60, "Mount Hyjal", "Level 60: through Darkwhisper Gorge in Winterspring." },
	},
	undead = {
		{ 1, 12, "Tirisfal Glades", "Your starting zone." },
		{ 12, 22, "The Barrens", "The Crossroads, then Ratchet and Camp Taurajo." },
		{ 22, 25, "Stonetalon Mountains", "Sun Rock Retreat." },
		{ 25, 29, "Hillsbrad Foothills", "Tarren Mill." },
		{ 29, 35, "Arathi Highlands", "Hammerfall." },
		{ 35, 38, "Badlands", "Kargath." },
		{ 38, 42, "Riverglades", "By road from northern Redridge, or by ship from Steamwheedle Port in Tanaris." },
		{ 42, 44, "Stranglethorn Vale", "Grom'gol, then Booty Bay." },
		{ 44, 46, "Feralas", "Camp Mojache." },
		{ 46, 49, "The Hinterlands", "Revantusk Village." },
		{ 49, 55, "Azshara", "Valormok." },
		{ 55, 57, "Silithus", "Cenarion Hold." },
		{ 57, 59, "Mount Hyjal", "Through Darkwhisper Gorge in Winterspring. Its quests open from the mid 50s." },
		{ 59, 60, "Eastern Plaguelands", "Light's Hope Chapel." },
		{ 60, 60, "Mount Hyjal", "Back to Mount Hyjal for its later quests." },
	},
	skyborne_a = Legs({
		{ 1, 12, "Zephras Isle", "Your starting zone." },
		{ 12, 15, "Westfall", "Elwynn's leftover quests on the way are worth grabbing." },
		{ 15, 18, "Redridge Mountains", "Lakeshire's lower quests." },
		{ 18, 20, "Westfall", "Hop back to finish Sentinel Hill. The Deadmines (18-22)." },
	}, FAST_ALLIANCE_20, FAST_SHARED),
	skyborne_h = Legs({
		{ 1, 12, "Zephras Isle", "Your starting zone. The skyboat takes you to Mulgore." },
		{ 12, 19, "The Barrens", "The Crossroads, then Ratchet's chains." },
	}, FAST_HORDE_19, FAST_SHARED),
}

P.STYLES = { { "optimized", "Optimized 1-60" }, { "zone", "Zone by zone" } }

function P:Style()
	local s = ns.db and ns.db.guide.style
	return (s == "zone") and "zone" or "optimized"
end

function P:StyleName(style)
	for _, v in ipairs(self.STYLES) do
		if v[1] == (style or self:Style()) then return v[2] end
	end
	return "Optimized 1-60"
end

---------------------------------------------------------------------------
-- Milestones
---------------------------------------------------------------------------
P.SHARED_MILESTONES = {
	{ 10, "Talents open. Change them later at a class trainer in a major city." },
	{ 40, "Riding: Apprentice Riding (about 100 gold) at your race's riding trainer, mount included." },
	{ 40, "Dual Specialization is available from your class trainer." },
	{ 60, "Faster riding is available from your riding trainer." },
}

P.CLASS_MILESTONES = {
	DRUID = { { 10, "Class quest: Bear Form" }, { 14, "Class quest: Cure Poison" },
		{ 16, "Class quest: Aquatic Form (Moonglade)" }, { 20, "Class quest: Cat Form and Prowl" } },
	HUNTER = { { 10, "Class quest: Tame Beast and your first pet (from your trainer)" },
		{ 60, "Class quest: Rhok'delar, Longbow of the Ancient Keepers" } },
	MAGE = { { 10, "Class quest: gear" }, { 15, "Class quest: gear" }, { 26, "Class quest: gear" },
		{ 30, "Class quest: a choice of three wands (Dustwallow Marsh)" } },
	PALADIN = { { 12, "Class quest: Redemption" }, { 20, "Class quest: weapon" },
		{ 40, "Class quest: Summon Warhorse (your mount comes from this quest)" }, { 60, "Class quest chain: Summon Charger" } },
	PRIEST = { { 10, "Class quest: racial priest spell" }, { 20, "Class quest: second racial priest spell" } },
	ROGUE = { { 20, "Class quest: Poisons (Stormwind for Alliance, Orgrimmar for Horde)" } },
	SHAMAN = { { 4, "Class quest: Earth Totem" }, { 10, "Class quest: Fire Totem" },
		{ 20, "Class quest: Water Totem" }, { 30, "Class quest: Air Totem" } },
	WARLOCK = { { 1, "Class quest: Summon Imp (starting zone)" }, { 10, "Class quest: Summon Voidwalker (your capital)" },
		{ 20, "Class quest: Succubus or Incubus, plus a Small Soul Pouch" }, { 30, "Class quest: Summon Felhunter" },
		{ 40, "Class quest: Summon Felsteed (your mount comes from this quest)" }, { 60, "Class quest chain: Summon Dreadsteed" } },
	WARRIOR = { { 10, "Class quest: Defensive Stance" }, { 30, "Class quest: Berserker Stance (Fray Island, The Barrens)" } },
}

---------------------------------------------------------------------------
-- Dungeons: { name, from, to, faction ("A", "H" or "B" for both) } - from/to is when it's worth running
---------------------------------------------------------------------------
P.DUNGEONS = {
	{ "Ragefire Chasm", 13, 15, "H" }, { "The Hall of Thanes", 14, 17, "A" },
	{ "Ruins of Lordaeron", 17, 19, "H" }, { "The Deadmines", 18, 22, "A" },
	{ "Wailing Caverns", 18, 22, "H" }, { "Shadowfang Keep", 22, 25, "H" },
	{ "Blackfathom Deeps", 23, 26, "B" }, { "The Stockade", 25, 29, "A" },
	{ "Excavation Site: Wetlands", 27, 30, "B" }, { "Razorfen Kraul", 29, 33, "B" },
	{ "City of Dalaran", 30, 33, "B" }, { "Gnomeregan", 30, 34, "B" },
	{ "Scarlet Monastery", 30, 44, "B" }, { "The Drowned City", 37, 40, "B" },
	{ "Razorfen Downs", 37, 42, "B" }, { "Krol'dok Stronghold", 40, 45, "B" },
	{ "Uldaman", 41, 45, "B" }, { "Zul'Farrak", 44, 48, "B" }, { "Maraudon", 46, 52, "B" },
	{ "Alcaz Prison", 50, 53, "B" }, { "Temple of Atal'Hakkar", 50, 55, "B" },
	{ "Blackrock Depths", 52, 58, "B" }, { "Blackmaw Hold", 57, 60, "B" }, { "Shaper's Terrace", 58, 60, "B" },
}

---------------------------------------------------------------------------
-- Building plans
---------------------------------------------------------------------------
local zoneIDs = {}

-- Map ID for a zone name on this client (nil if the name doesn't match, e.g. another language).
function P.ZoneID(name)
	if zoneIDs[name] == nil then zoneIDs[name] = ns.Nav.FindZone(name) or false end
	return zoneIDs[name] or nil
end

-- Level range for a zone: the game's own numbers when available, else the table above.
function P.ZoneLevels(name)
	local id = P.ZoneID(name)
	if id then
		local minL, maxL = C_Map.GetMapLevels(id)
		minL, maxL = ns.Num(minL), ns.Num(maxL)
		if minL and maxL and minL > 0 then return minL, maxL, true end
	end
	local z = P.ZONES[name]
	if z then return z[1], z[2], false end
end

function P.RaceName(token, faction)
	local r = P.RACES[token]
	if not r then return token or "?" end
	return (r.names and r.names[faction]) or r.name
end

function P.IsPlayable(token, faction, class)
	local combos = P.COMBOS[class]
	if not combos or not combos[faction] then return false end
	for _, t in ipairs(combos[faction]) do
		if t == token then return true end
	end
	return false
end

-- Builds the plan for a race token, class token and faction.
function P:Build(token, class, faction)
	local race = self.RACES[token]
	faction = faction or (race and race.faction) or "Alliance"
	local routeKey = race and race.route
	if type(routeKey) == "table" then routeKey = routeKey[faction] end
	routeKey = routeKey or (faction == "Horde" and "orc" or "human")
	local plan = {
		token = token, class = class, faction = faction,
		title = P.RaceName(token, faction) .. " " .. (P.CLASS_NAMES[class] or class or ""),
		bands = {}, milestones = {}, dungeons = {},
	}
	for i, b in ipairs(self.ROUTES[routeKey]) do
		table.insert(plan.bands, { index = i, from = b[1], to = b[2], zones = b[3], note = b[4] })
	end
	plan.legs = {}
	for i, l in ipairs(self.FAST_ROUTES[routeKey] or self.FAST_ROUTES.human) do
		table.insert(plan.legs, { index = i, from = l[1], to = l[2], zone = l[3], note = l[4], alt = l.alt })
	end
	for _, m in ipairs(self.SHARED_MILESTONES) do
		table.insert(plan.milestones, { level = m[1], text = m[2], key = "shared:" .. m[1] .. ":" .. m[2]:sub(1, 12) })
	end
	for _, m in ipairs(self.CLASS_MILESTONES[class] or {}) do
		table.insert(plan.milestones, { level = m[1], text = m[2], key = (class or "?") .. ":" .. m[1] .. ":" .. m[2]:sub(1, 16), class = true })
	end
	table.sort(plan.milestones, function(a, b) return a.level < b.level end)
	local tag = faction == "Horde" and "H" or "A"
	for _, d in ipairs(self.DUNGEONS) do
		if d[4] == "B" or d[4] == tag then
			table.insert(plan.dungeons, { name = d[1], from = d[2], to = d[3] })
		end
	end
	return plan
end

function P:Mine()
	local _, token = UnitRace("player")
	local _, class = UnitClass("player")
	local faction = UnitFactionGroup("player")
	local key = (token or "?") .. ":" .. (class or "?") .. ":" .. (faction or "?")
	if not self.mine or self.mineKey ~= key then
		self.mine, self.mineKey = self:Build(token, class, faction), key
	end
	return self.mine
end

function P:BandFor(plan, level)
	local found
	for _, b in ipairs(plan.bands) do
		if level >= b.from and (level < b.to or (b.from == b.to and level >= b.to)) then return b end
		if level >= b.from then found = b end
	end
	return found or plan.bands[1]
end

function P:NextBand(plan, band)
	return band and plan.bands[band.index + 1]
end

function P:LegFor(plan, level)
	local found
	for _, l in ipairs(plan.legs) do
		if level >= l.from and (level < l.to or (l.from == l.to and level >= l.to)) then return l end
		if level >= l.from then found = l end
	end
	return found or plan.legs[1]
end

function P:NextLeg(plan, leg)
	return leg and plan.legs[leg.index + 1]
end

---------------------------------------------------------------------------
-- Where you should be questing now, for the selected style.
--   zoneWork(name) -> how many useful quests (to do, to hand in, or to pick up) a zone has.
-- Returns { style, zones = { [name] = true }, primary, primaryID, nextZone, moveOn, zoneDone,
--           nearEnd, from, to, note, reason } or nil.
---------------------------------------------------------------------------
local function HereZoneName()
	local m = C_Map.GetBestMapForUnit("player")
	m = m and ns.Nav.GetZoneMap(m)
	return m and ns.Nav.MapName(m) or nil, m
end

local function SameZone(a, b)
	if not a or not b then return false end
	if a == b then return true end
	local ia, ib = P.ZoneID(a), P.ZoneID(b)
	return ia ~= nil and ia == ib
end
P.SameZone = SameZone

-- zoneWorkAll, when given, counts gray quests too: Zone by zone's completionist way stays in a
-- zone until those are done as well, up to COMPLETE_SLACK levels past the zone's top level.
local COMPLETE_SLACK = 4
function P:Focus(plan, level, zoneWork, zoneWorkAll)
	local here = HereZoneName()
	local f = { style = self:Style(), zones = {}, here = here }
	if f.style == "optimized" then
		local leg = self:LegFor(plan, level)
		if not leg then return nil end
		local nextLeg = self:NextLeg(plan, leg)
		f.primary, f.from, f.to, f.note = leg.zone, leg.from, leg.to, leg.note
		f.zones[leg.zone] = true
		if leg.alt then f.zones[leg.alt] = true end
		f.nextZone = nextLeg and nextLeg.zone ~= leg.zone and nextLeg.zone or nil
		f.nearEnd = level >= leg.to - 1
		local inFocus = SameZone(here, leg.zone) or (leg.alt and SameZone(here, leg.alt))
		f.moveOn = not inFocus
		f.reason = string.format("Your route: %s for levels %d-%d.%s", leg.zone, leg.from, leg.to, leg.note and (" " .. leg.note) or "")
		-- Nothing left for you here while the next leg's zone has quests you can already take:
		-- go now rather than grind out the rest of the window.
		if inFocus and f.nextZone and zoneWork(here) == 0 and zoneWork(f.nextZone) > 0 then
			f.zoneDone, f.moveOn = true, true
			f.reason = string.format("Nothing left for you in %s. %s is next on your route and already has quests for you.", here, f.nextZone)
			f.primary = f.nextZone
			f.zones = { [f.nextZone] = true }
			local after = nextLeg and self:NextLeg(plan, nextLeg)
			f.nextZone = after and after.zone ~= nextLeg.zone and after.zone or nil
		end
	else
		local band = self:BandFor(plan, level)
		if not band then return nil end
		local prev = band.index > 1 and plan.bands[band.index - 1] or nil
		-- Stay where you are while it's one of your plan's zones for now (or the band before),
		-- you haven't outleveled it and it still has quests for you.
		local stay
		local work, slack = zoneWorkAll or zoneWork, zoneWorkAll and COMPLETE_SLACK or 1
		for _, b in ipairs({ band, prev }) do
			for _, name in ipairs(b and b.zones or {}) do
				if not stay and SameZone(here, name) then
					local _, maxL = self.ZoneLevels(name)
					if (not maxL or maxL >= level - slack) and work(name) > 0 then stay = name end
				end
			end
		end
		-- Wherever you are: the zone you're in still has quests for you and you haven't outleveled
		-- it, so stay, whatever the plan says. You went there for a reason; when it's done, the
		-- next zone comes from the quest data (Advisor:ApplyZones), or from the plan.
		if not stay and here and P.ZONES[here] then
			local minL, maxL = self.ZoneLevels(here)
			if maxL and maxL >= level - slack and (not minL or minL <= level + 3) and work(here) > 0 then stay = here end
		end
		f.from, f.to, f.note = band.from, band.to, band.note
		if stay then
			f.primary = stay
		else
			f.zoneDone = here ~= nil and zoneWork(here) == 0
			-- Nearest first, but a zone with quests open to you beats one with none. Counts for
			-- zones you are not in come from what NeverQuest knows (QuestDB.lua); with nothing
			-- known anywhere, the nearest zone in the plan is still the answer.
			local usable = self:UsableZones(band, level)
			for pass = 1, 2 do
				for _, z in ipairs(usable) do
					if not f.primary and not SameZone(z.name, here) and (pass == 2 or zoneWork(z.name) > 0) then f.primary = z.name end
				end
			end
			local nextBand = self:NextBand(plan, band)
			if not f.primary and nextBand then f.primary = nextBand.zones[1] end
			f.primary = f.primary or band.zones[1]
		end
		f.zones[f.primary] = true
		for _, name in ipairs(band.zones) do
			if not SameZone(name, f.primary) and not f.nextZone and zoneWork(name) > 0 then f.nextZone = name end
		end
		local nextBand = self:NextBand(plan, band)
		f.nextZone = f.nextZone or (nextBand and nextBand.zones[1])
		f.nearEnd = level >= band.to - 1
		f.moveOn = not SameZone(here, f.primary)
		f.reason = stay and string.format(zoneWorkAll and "Zone by zone: finishing every quest in %s." or "Zone by zone: finishing %s.", stay)
			or string.format("Zone by zone: %s is next in your plan (levels %d-%d).", f.primary, band.from, band.to)
	end
	f.primaryID = self.ZoneID(f.primary)
	return f
end

-- How much a quest in this zone is worth to the route, for the selected style.
function P:ZoneWeight(zoneName, focus, complete)
	if not focus or not zoneName then return 1 end
	local w
	local inFocus = false
	for name in pairs(focus.zones) do
		if SameZone(name, zoneName) then inFocus = true end
	end
	if inFocus then
		w = focus.style == "zone" and 1.6 or 1.4
	elseif focus.nextZone and SameZone(focus.nextZone, zoneName) then
		w = focus.nearEnd and 1.2 or 0.8
	else
		w = focus.style == "zone" and 0.25 or 0.4
	end
	-- Finished quests are XP in the bag: hand them in when it's anywhere near the way.
	if complete then w = math.max(w, 0.85) end
	return w
end

-- Zones from a band you can actually use now, best first: the zone you're in if it fits,
-- then zones whose level range still covers you, nearest first.
function P:UsableZones(band, level)
	local here = C_Map.GetBestMapForUnit("player")
	local hereZone = here and ns.Nav.GetZoneMap(here)
	local m, x, y = ns.Nav.GetPlayerPosition()
	local list = {}
	for order, name in ipairs(band.zones) do
		local minL, maxL = P.ZoneLevels(name)
		local id = P.ZoneID(name)
		if not maxL or maxL >= level then
			local dist = (m and id) and ns.Nav.DistanceBetween(m, x, y, id, 0.5, 0.5) or math.huge
			table.insert(list, { name = name, id = id, min = minL, max = maxL, order = order, here = id ~= nil and id == hereZone, dist = dist })
		end
	end
	table.sort(list, function(a, b)
		if a.here ~= b.here then return a.here end
		if (a.dist < math.huge) ~= (b.dist < math.huge) then return a.dist < math.huge end
		if a.dist ~= b.dist and a.dist < math.huge then return a.dist < b.dist end
		return a.order < b.order
	end)
	return list
end

-- Milestones reached recently and not yet ticked off, plus the next one coming up.
function P:DueMilestones(plan, level)
	local due, upcoming = {}, nil
	local done = ns.char.milestones
	for _, ms in ipairs(plan.milestones) do
		if ms.level <= level and ms.level >= level - 3 and not done[ms.key] then
			table.insert(due, ms)
		elseif ms.level > level and not upcoming then
			upcoming = ms
		end
	end
	return due, upcoming
end

function P:DungeonsFor(plan, level)
	local out = {}
	for _, d in ipairs(plan.dungeons) do
		if level >= d.from and level <= d.to then table.insert(out, d) end
	end
	return out
end

-- Rows for the 1-60 plan view, in the selected style.
function P:PlanItems(plan, level)
	local items = {}
	if self:Style() == "optimized" then
		local current = level >= 1 and self:LegFor(plan, level) or nil
		for _, l in ipairs(plan.legs) do
			local minL, maxL = P.ZoneLevels(l.zone)
			local isCurrent = l == current
			local done = level >= l.to and not isCurrent
			local subParts = {}
			if l.note then table.insert(subParts, l.note) end
			if minL then table.insert(subParts, string.format("%s %d-%d", l.zone, minL, maxL)) end
			if l.alt then table.insert(subParts, "or " .. l.alt) end
			local id = P.ZoneID(l.zone)
			table.insert(items, {
				key = "plan:leg:" .. l.index, kind = "zone", level = l.from,
				title = (l.from == l.to and string.format("Lv %d   ", l.from) or string.format("Lv %d-%d   ", l.from, l.to)) .. l.zone,
				sub = table.concat(subParts, "  ·  "),
				right = isCurrent and "|cff66ff66now|r" or (done and "|cff888888done|r" or ""),
				color = done and { 0.55, 0.55, 0.55 } or nil, current = isCurrent,
				m = id, x = id and 0.5 or nil, y = id and 0.5 or nil, navTitle = l.zone,
			})
		end
	end
	local current = level >= 1 and self:BandFor(plan, level) or nil
	for _, b in ipairs(self:Style() == "zone" and plan.bands or {}) do
		local names, levels = {}, {}
		for _, name in ipairs(b.zones) do
			local minL, maxL = P.ZoneLevels(name)
			table.insert(names, name)
			if minL then table.insert(levels, string.format("%s %d-%d", name, minL, maxL)) end
		end
		local isCurrent = b == current
		local done = level >= b.to and not isCurrent
		local subParts = { table.concat(levels, "  ·  ") }
		if b.note then table.insert(subParts, 1, b.note) end
		local first = b.zones[1]
		local id = first and P.ZoneID(first)
		table.insert(items, {
			key = "plan:band:" .. b.index, kind = "zone", level = b.from,
			title = (b.from == b.to and string.format("Lv %d   ", b.from) or string.format("Lv %d-%d   ", b.from, b.to)) .. table.concat(names, " or "),
			sub = table.concat(subParts, "  ·  "),
			right = isCurrent and "|cff66ff66now|r" or (done and "|cff888888done|r" or ""),
			color = done and { 0.55, 0.55, 0.55 } or nil, current = isCurrent,
			m = id, x = id and 0.5 or nil, y = id and 0.5 or nil, navTitle = first,
		})
	end
	for _, ms in ipairs(plan.milestones) do
		local done = ns.char.milestones[ms.key] or ms.level < level - 3
		table.insert(items, {
			key = "plan:ms:" .. ms.key, kind = ms.class and "train" or "level", level = ms.level + 0.1,
			title = string.format("Lv %d   %s", ms.level, ms.text), milestoneKey = ms.key,
			color = (done and level >= ms.level) and { 0.55, 0.55, 0.55 } or { 0.6, 0.85, 1 },
			right = (level >= ms.level and not done) and "|cffffd100due|r" or "",
		})
	end
	for _, d in ipairs(plan.dungeons) do
		table.insert(items, {
			key = "plan:dg:" .. d.name, kind = "dungeon", icon = "Dungeon", level = d.from + 0.2,
			title = string.format("Lv %d-%d   Dungeon: %s", d.from, d.to, d.name),
			color = level > d.to and { 0.55, 0.55, 0.55 } or { 0.85, 0.7, 1 },
			right = (level >= d.from and level <= d.to) and "|cff66ff66good now|r" or "",
		})
	end
	table.sort(items, function(a, b)
		if a.level ~= b.level then return a.level < b.level end
		return a.key < b.key
	end)
	return items
end

ns:RegisterEvent("TRAINER_SHOW", function()
	if ns.ready then ns.char.trainedLevel = UnitLevel("player") end
end)
