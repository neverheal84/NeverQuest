-- NeverQuest lookups: where a handful of quests start and end, looked up by hand.
--
-- These are the quests that are new in WoW Forever. No database has places for them, and the
-- game does not tell an addon where a quest starts unless it is being offered to you. Until a
-- NeverQuest client has seen each one in the game, the places below fill the gap.
--
-- Source: the Warcraft Wiki (https://warcraft.wiki.gg), one quest page at a time, read on
-- 2026-11-21. Each entry names the page it came from. The wiki's text is available under the
-- Creative Commons Attribution-ShareAlike 4.0 licence
-- (https://creativecommons.org/licenses/by-sa/4.0/), and this file, which is built from it, is
-- offered under the same licence. It is kept apart from the rest of NeverQuest for that reason.
--
-- How these are treated:
--   * They are hints, and say so on the map. Anything a NeverQuest client has seen for itself
--     replaces them, and so does the next export built into Starts.lua.
--   * They are never written into your saved data, exported, or shared.
--   * Two of them were checked against places NeverQuest recorded in the game (quests 86784
--     and 95314) and agreed to within a tenth of a percent of the map.
--
-- Fields: t title, l level, rl level needed, f side, m map, x y where it starts (0 to 1),
-- by who gives it; em ex ey eby the same for where it ends; page the wiki page name.

local ADDON, ns = ...

ns.Lookups = {
	source = "Warcraft Wiki (warcraft.wiki.gg), CC BY-SA 4.0",
	read = "2026-11-21",
	q = {
		-- Tirisfal Glades
		[86784] = { t = "Sticks and Bones", l = 7, rl = 4, f = "H", m = 1420, x = 0.585, y = 0.514, by = "Deathguard Bartholomew",
			em = 1420, ex = 0.573, ey = 0.555, eby = "Eleanor Shackleton", page = "Sticks_and_Bones_(Forever)" },
		[95314] = { t = "That Shadowvale Green Elixir", l = 10, rl = 7, f = "H", m = 1420, x = 0.594, y = 0.522, by = "Carolai Anise",
			em = 1420, ex = 0.594, ey = 0.522, eby = "Carolai Anise", page = "That_Shadowvale_Green_Elixir" },
		[99142] = { t = "Tomb Weed", l = 11, rl = 5, f = "H", m = 1420, x = 0.577, y = 0.490, by = "Junior Apothecary Holland",
			em = 1420, ex = 0.577, ey = 0.490, eby = "Junior Apothecary Holland", page = "Tomb_Weed_(quest)" },
		[91285] = { t = "Murlocs at the Gates", l = 11, rl = 7, f = "H", m = 1420, x = 0.219, y = 0.452, by = "Breton Samuels",
			em = 1420, ex = 0.219, ey = 0.452, eby = "Breton Samuels", page = "Murlocs_at_the_Gates" },
		[91294] = { t = "Touring the Grounds", l = 11, rl = 8, f = "H", m = 1420, x = 0.219, y = 0.452, by = "Breton Samuels",
			em = 1420, ex = 0.221, ey = 0.447, eby = "Danitha Morr", page = "Touring_the_Grounds" },
		[91316] = { t = "Making Repairs", l = 11, rl = 8, f = "H", m = 1420, x = 0.227, y = 0.447, by = "Jorin Croge",
			em = 1420, ex = 0.227, ey = 0.447, eby = "Jorin Croge", page = "Making_Repairs_(Forever)" },
		[91317] = { t = "The Tarnished", l = 12, rl = 9, f = "H", m = 1420, x = 0.221, y = 0.447, by = "Danitha Morr",
			em = 1420, ex = 0.221, ey = 0.447, eby = "Danitha Morr", page = "The_Tarnished" },
		[95803] = { t = "A Token of Good Faith", l = 12, rl = 9, f = "H", m = 1420, x = 0.221, y = 0.447, by = "Danitha Morr",
			eby = "Lady Sylvanas Windrunner", page = "A_Token_of_Good_Faith" },
		[96895] = { t = "The Argent Emissary", l = 13, rl = 10, f = "H", m = 1420, x = 0.615, y = 0.535, by = "Deathguard Terrence",
			em = 1420, ex = 0.658, ey = 0.610, eby = "Hadric Harlson", page = "The_Argent_Emissary" },
		[96898] = { t = "Remnants of War", l = 12, rl = 10, f = "H", m = 1420, x = 0.658, y = 0.610, by = "Hadric Harlson",
			em = 1420, ex = 0.658, ey = 0.610, eby = "Hadric Harlson", page = "Remnants_of_War" },
		[96897] = { t = "The Cult of the Damned", l = 12, rl = 10, f = "H", m = 1420, x = 0.658, y = 0.610, by = "Hadric Harlson",
			em = 1420, ex = 0.658, ey = 0.610, eby = "Hadric Harlson", page = "The_Cult_of_the_Damned_(quest)" },
		-- Its page gives no place for the giver; his place is from the two pages above.
		[96899] = { t = "Bandarion Keep", l = 13, rl = 10, f = "H", m = 1420, x = 0.658, y = 0.610, by = "Hadric Harlson",
			eby = "Leonid Barthalomew the Revered", page = "Bandarion_Keep_(quest)" },
		-- Named on their pages, with no place given yet. The names feed the NPC icons.
		[96896] = { t = "A Righteous Cause", l = 13, rl = 10, f = "H", by = "Leonid Barthalomew the Revered",
			eby = "Leonid Barthalomew the Revered", page = "A_Righteous_Cause" },
		[99152] = { t = "As Above, So Below", l = 10, rl = 7, f = "H", by = "Hilda the Breaker", eby = "Hilda the Breaker",
			page = "As_Above,_So_Below" },
		[99153] = { t = "The One That Got Away", l = 10, rl = 7, f = "H", by = "Ephram Barbaro", eby = "Ephram Barbaro",
			page = "The_One_That_Got_Away_(Forever)" },
	},
}
