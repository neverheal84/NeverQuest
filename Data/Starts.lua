-- NeverQuest quest start data: where quests begin, shipped with the addon so a new character
-- sees a useful map on its first login instead of an empty one.
--
-- Where this comes from, and where it does not:
--   * NeverQuest's own background scan, which asks the game client which quests each zone
--     offers and where their givers stand (QuestDB.lua);
--   * players who send in their own database with /nq db export.
-- Nothing here is taken from another addon, database project or website. Every entry was seen
-- in the live game by NeverQuest itself.
--
-- Fields match the learned database exactly, so the two merge with no conversion:
--   t  title                      l  level the quest opens at
--   m  map ID                     x, y  position on that map, 0 to 1
--   f  faction letters, "A" "H" or "AH"  (absent: either faction)
--   c  classes, ",WARRIOR,ROGUE," (absent: any class)
--
-- Anything a player's own client learns beats what is here, field by field, because their
-- client is the live one. So a wrong entry corrects itself the first time someone plays past it.
--
-- Rebuild with:  python3 -I tools/build_starts.py exports/*.txt

local ADDON, ns = ...

ns.Starts = {
	-- Bumped whenever this file is rebuilt. Shown by /nq db.
	version = 1,
	build = "1.60.1",
	gathered = "2026-11-19",
	-- Contributors, by the name they asked to be credited under.
	credit = {"NeverHeal84"},
	q = {
		[19] = { t = "Tharil'zun", l = 25, m = 1433, x = 0.2830, y = 0.4920, f = "A" },
		[57] = { t = "The Night Watch", l = 26, m = 1431, x = 0.7360, y = 0.4670, f = "A" },
		[69] = { t = "The Legend of Stalvan", l = 28, m = 1431, x = 0.7260, y = 0.4680, f = "A" },
		[70] = { t = "The Legend of Stalvan", l = 28, m = 1429, x = 0.4380, y = 0.6590, f = "A" },
		[72] = { t = "The Legend of Stalvan", l = 28, m = 1453, x = 0.4280, y = 0.7210, f = "A" },
		[75] = { t = "The Legend of Stalvan", l = 28, m = 1429, x = 0.8470, y = 0.6950, f = "A" },
		[78] = { t = "The Legend of Stalvan", l = 28, m = 1429, x = 0.8470, y = 0.6950, f = "A" },
		[79] = { t = "The Legend of Stalvan", l = 28, m = 1431, x = 0.7380, y = 0.4450, f = "A" },
		[80] = { t = "The Legend of Stalvan", l = 28, m = 1431, x = 0.7360, y = 0.4670, f = "A" },
		[93] = { t = "Dusky Crab Cakes", l = 20, m = 1431, x = 0.7380, y = 0.4370, f = "A" },
		[94] = { t = "A Watchful Eye", l = 21, m = 1429, x = 0.6520, y = 0.6990, f = "A" },
		[95] = { t = "Sven's Revenge", l = 25, m = 1431, x = 0.0780, y = 0.3400, f = "A" },
		[97] = { t = "The Legend of Stalvan", l = 28, m = 1431, x = 0.7260, y = 0.4690, f = "A" },
		[98] = { t = "The Legend of Stalvan", l = 35, m = 1431, x = 0.7350, y = 0.4680, f = "A" },
		[115] = { t = "Shadow Magic", l = 23, m = 1433, x = 0.2830, y = 0.4920, f = "A" },
		[156] = { t = "Gather Rot Blossoms", l = 24, m = 1431, x = 0.7380, y = 0.4440, f = "A" },
		[158] = { t = "Zombie Juice", l = 24, m = 1431, x = 0.2800, y = 0.3150, f = "A" },
		[159] = { t = "Juice Delivery", l = 24, m = 1431, x = 0.7390, y = 0.4450, f = "A" },
		[173] = { t = "Worgen in the Woods", l = 28, m = 1431, x = 0.7520, y = 0.4800, f = "A" },
		[174] = { t = "Look to the Stars", l = 25, m = 1431, x = 0.7980, y = 0.4800, f = "A" },
		[175] = { t = "Look to the Stars", l = 25, m = 1431, x = 0.7980, y = 0.4800, f = "A" },
		[177] = { t = "Look to the Stars", l = 25, m = 1431, x = 0.8200, y = 0.5920, f = "A" },
		[181] = { t = "Look to the Stars", l = 30, m = 1431, x = 0.7980, y = 0.4800, f = "A" },
		[221] = { t = "Worgen in the Woods", l = 29, m = 1431, x = 0.7520, y = 0.4800, f = "A" },
		[240] = { t = "Return to Jitters", l = 20, m = 1431, x = 0.7380, y = 0.4360, f = "A" },
		[350] = { t = "Look to an Old Friend", l = 31, m = 1453, x = 0.7850, y = 0.7070, f = "A" },
		[377] = { t = "Crime and Punishment", l = 26, m = 1431, x = 0.7200, y = 0.4770, f = "A" },
		[386] = { t = "What Comes Around...", l = 25, m = 1433, x = 0.2120, y = 0.4660, f = "A" },
		[387] = { t = "Quell the Uprising", l = 26, m = 1453, x = 0.5160, y = 0.6940, f = "A" },
		[388] = { t = "The Color of Blood", l = 26, m = 1453, x = 0.7650, y = 0.6030, f = "A" },
		[391] = { t = "The Stockade Riots", l = 29, m = 1453, x = 0.5160, y = 0.6940, f = "A" },
		[392] = { t = "The Curious Visitor", l = 29, m = 1453, x = 0.5150, y = 0.6920, f = "A" },
		[393] = { t = "Shadow of the Past", l = 29, m = 1453, x = 0.5760, y = 0.4790, f = "A" },
		[394] = { t = "The Head of the Beast", l = 31, m = 1453, x = 0.6620, y = 0.7430, f = "A" },
		[395] = { t = "Brotherhood's End", l = 31, m = 1453, x = 0.7840, y = 0.7080, f = "A" },
		[396] = { t = "An Audience with the King", l = 31, m = 1453, x = 0.5760, y = 0.4780, f = "A" },
		[434] = { t = "The Attack!", l = 31, m = 1453, x = 0.7320, y = 0.3580, f = "A" },
		[536] = { t = "Down the Coast", l = 30, m = 1424, x = 0.5140, y = 0.5850, f = "A" },
		[1078] = { t = "Retrieval for Mauren", l = 26, m = 1453, x = 0.5310, y = 0.8660, f = "A" },
		[1701] = { t = "Fire Hardened Mail", l = 28, m = 1453, x = 0.6470, y = 0.3750, f = "A" },
		[2745] = { t = "Infiltrating the Castle", l = 31, m = 1453, x = 0.6620, y = 0.7420, f = "A" },
		[2746] = { t = "Items of Some Consequence", l = 31, m = 1453, x = 0.7320, y = 0.3580, f = "A" },
		[2928] = { t = "Gyrodrillmatic Excavationators", l = 30, m = 1453, x = 0.6280, y = 0.3430, f = "A" },
		[3370] = { t = "In Nightmares", l = 25, m = 1413, x = 0.4820, y = 0.3280, f = "A" },
		[3765] = { t = "The Corruption Abroad", l = 24, m = 1453, x = 0.3640, y = 0.6740, f = "A" },
		[8168] = { t = "The Battle for Arathi Basin!", l = 25, m = 1417, x = 0.4590, y = 0.4560, f = "A" },
		[8374] = { t = "Claiming Arathi Basin", l = 29, m = 1453, x = 0.8100, y = 0.3820, f = "A" },
		[95772] = { t = "Songblade Search", l = 31, m = 1433, x = 0.2570, y = 0.4660, f = "A" },
		[98386] = { t = "Alther's Mill", l = 21, m = 1433, x = 0.2690, y = 0.4860, f = "A" },
	},
}
