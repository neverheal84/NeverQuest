-- NeverQuest quest spots: hand-checked places for quests the game gives no map marker, such as
-- scavenger hunts that end at an object in another zone. Our own entries, written from where
-- each step actually is in WoW Forever. The start of NeverQuest's own quest database.
--
-- Matched by quest title (and faction when the two sides differ), because quest IDs aren't
-- published for every Forever quest yet.

local ADDON, ns = ...
local QS = {}
ns.QuestSpots = QS

-- Zone name -> classic map ID, used when the zone can't be found by name.
local MAP_IDS = {
	["Westfall"] = 1436, ["The Barrens"] = 1413, ["Stonetalon Mountains"] = 1442,
	["Loch Modan"] = 1432, ["Arathi Highlands"] = 1417, ["Hillsbrad Foothills"] = 1424,
}

local COZY = "Cozy Sleeping Bag"

-- title: the quest's name; faction: only when the sides differ.
-- turnin: where you hand it in (zone, x, y in percent, what to click, how to get there).
QS.LIST = {
	{ title = "...and that note you found", faction = "Alliance", chain = COZY, step = 1, total = 6,
		turnin = { zone = "The Barrens", x = 46.4, y = 73.9, what = "Burned-Out Remains",
			how = "The note points to the other faction's land: the ruined tower south of Camp Taurajo in The Barrens. Horde territory, so watch out." } },
	{ title = "...and that note you found", faction = "Horde", chain = COZY, step = 1, total = 6,
		turnin = { zone = "Westfall", x = 37.5, y = 50.7, what = "Burned-Out Remains",
			how = "The note points to the other faction's land: the cart wreckage at the Alexston Farmstead in Westfall. Alliance territory, so watch out." } },
	{ title = "Stepping Stones", chain = COZY, step = 2, total = 6,
		turnin = { zone = "Stonetalon Mountains", x = 40.6, y = 52.4, what = "Pocket Litter",
			how = "Take the path up the mountain northeast of Sun Rock Retreat to an abandoned camp; it's on a crate outside the tent. Reward: a 12-slot bag." } },
	{ title = "Scramble", chain = COZY, step = 3, total = 6,
		turnin = { zone = "Stonetalon Mountains", x = 39.6, y = 49.8, what = "Mound of Dirt",
			how = "Climb the hill north of the camp and jump across the gap to the mound. Miss the jump and you're back at the bottom." } },
	{ title = "Wet Job", chain = COZY, step = 4, total = 6,
		turnin = { zone = "Loch Modan", x = 49.4, y = 12.9, what = "Eagle Figurine",
			how = "At Stonewrought Dam, drop onto the carved dwarf heads on the Wetlands side; the figurine is on a ledge. Don't miss, or you fall to the Wetlands." } },
	{ title = "Eagle's Fist", chain = COZY, step = 5, total = 6,
		turnin = { zone = "Arathi Highlands", x = 22.5, y = 24.2, what = "Messenger Bag",
			how = "On top of Thoradin's Wall between Hillsbrad Foothills and Arathi Highlands: climb up and follow it into a tucked-away room; the bag hangs near the outer edge." } },
	{ title = "This Must Be The Place", chain = COZY, step = 6, total = 6,
		turnin = { zone = "Arathi Highlands", x = 22.5, y = 24.2, what = "Hastily Rolled-Up Satchel",
			how = "Right below the Messenger Bag. Reward: the Cozy Sleeping Bag." } },
}

-- "…and that note you found", "... and that note you found" and "...and that note you found"
-- are the same quest.
function QS.Norm(title)
	if type(title) ~= "string" or ns.IsSecret(title) then return nil end
	local t = title:lower():gsub("\226\128\166", "..."):gsub("^[%.%s]+", ""):gsub("%s+", " "):gsub("%s+$", "")
	return t
end

local byTitle
local function Index()
	if byTitle then return byTitle end
	byTitle = {}
	for _, entry in ipairs(QS.LIST) do
		local key = QS.Norm(entry.title)
		byTitle[key] = byTitle[key] or {}
		table.insert(byTitle[key], entry)
	end
	return byTitle
end

function QS:Find(title, faction)
	local list = Index()[QS.Norm(title) or ""]
	if not list then return nil end
	faction = faction or UnitFactionGroup("player")
	for _, entry in ipairs(list) do
		if not entry.faction or entry.faction == faction then return entry end
	end
end

function QS.MapID(zone)
	return (ns.Profiles and ns.Profiles.ZoneID(zone)) or MAP_IDS[zone]
end

-- Where to go for this quest log entry: { m, x, y, known = true, label, how, zone }.
function QS:Spot(e)
	local entry = e and self:Find(e.title)
	if not entry then return nil end
	-- Short names like "Scramble" could belong to other quests: these entries are all
	-- text-only quests, so a quest with objectives isn't one of them.
	if e.noObjectives == false then return nil end
	local t = entry.turnin
	local m = QS.MapID(t.zone)
	if not m then return nil end
	return { m = m, x = t.x / 100, y = t.y / 100, known = true, label = t.what, how = t.how, zone = t.zone }, entry
end

-- Applied while scanning the log: a known spot replaces a missing or doubtful game marker.
function QS:Apply(e)
	local spot, entry = self:Spot(e)
	if not spot then return false end
	e.pos = spot
	e.knownSpot = entry
	return true
end

function QS:ChainLabel(e)
	local entry = e and e.knownSpot
	if not entry or not entry.chain then return nil end
	return string.format("%s %d/%d", entry.chain, entry.step, entry.total)
end
