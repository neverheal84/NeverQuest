-- NeverQuest ClassQuests: one place for the quests only your class gets.
--
-- Two halves. The top is live: whatever class quests are in your quest log right now, read from
-- the game (it files them under a header named after your class). The rest is a checklist of
-- what your class has coming and at which level, written by hand for this addon from how the
-- classes work: what each quest gives you and where it starts. Your trainer is the authority.
-- Forever can differ from the original game, so rows can be ticked off or hidden by hand.

local ADDON, ns = ...
local C = {}
ns.ClassQuests = C

-- { level, key, what you get, where it starts and what it takes }
local EVERYONE_50 = { 50, "temple", "Sunken Temple class quest",
	"Your trainer in the capital sends you into the Temple of Atal'Hakkar for a pick of three rare items made for your class. Bring a group." }

C.DATA = {
	WARRIOR = {
		{ 10, "defensive", "Defensive Stance", "Your warrior trainer sends you to a veteran nearby. Taunt and Sunder Armor need this stance, so do it the moment it opens." },
		{ 30, "berserker", "Berserker Stance", "Starts at your trainer and ends on Fray Island, off Ratchet in The Barrens: win the fights in the ring. Bring food and a full health bar." },
		{ 30, "whirlwind", "Whirlwind weapon", "After Berserker Stance, Bath'rah the Windwatcher in the Alterac Mountains sets a long collection run ending in a summoned elemental. Your pick of an axe, a sword or a mace that lasts you well into your 40s." },
		EVERYONE_50,
	},
	PALADIN = {
		{ 12, "redemption", "Redemption", "The Tome of Divinity from your trainer in Stormwind or Ironforge: a short errand that teaches you to bring the dead back." },
		{ 20, "verigan", "Verigan's Fist", "The Tome of Valor, then The Test of Righteousness from Jordan Stilwell outside Ironforge. Four parts, three of them in dungeons (the Deadmines, Blackfathom Deeps, Shadowfang Keep). A two-hand mace worth the trouble." },
		{ 40, "warhorse", "Summon Warhorse", "Your trainer gives you your mount as a quest rather than selling it to you. Free." },
		EVERYONE_50,
		{ 60, "charger", "Summon Charger", "Lord Grayson Shadowbreaker in Stormwind. A long, costly chain across the Plaguelands and Dire Maul that ends in Scholomance." },
	},
	HUNTER = {
		{ 10, "tame", "Tame Beast", "Your trainer hands you a taming rod three times, for three beasts near your starting zone. The third turn-in teaches Tame Beast; your capital's trainer then teaches you to train the pet." },
		EVERYONE_50,
		{ 60, "leaf", "Rhok'delar and Lok'delar", "Starts with the Ancient Petrified Leaf from the cache in Molten Core. Four demons in four zones, each fought alone, for a bow and a staff." },
	},
	ROGUE = {
		{ 10, "first", "First assignment", "Your trainer's first real job for you, in or near your starting zone. A good early piece of gear." },
		{ 20, "poisons", "Poisons", "Alliance: Mathias Shaw in Stormwind sends you to a tower in Westfall. Horde: the Shattered Hand in Orgrimmar sends you to a tower in The Barrens. Both need lockpicking and stealth, and both poison you on the way out: have the cure ready." },
		EVERYONE_50,
	},
	PRIEST = {
		{ 5, "garments", "Garments", "Your trainer has you heal and bless a wounded guard for your first robe." },
		{ 10, "racial1", "Racial priest spell", "Your trainer sends you home to your people's priests for a spell only your race gets." },
		{ 20, "racial2", "Second racial spell", "The second of your race's two priest spells, from your trainer." },
		EVERYONE_50,
		{ 60, "benediction", "Benediction and Anathema", "The Eye of Divinity from the cache in Molten Core and the Eye of Shadow, then a healing trial in the Eastern Plaguelands. One staff with two faces." },
	},
	SHAMAN = {
		{ 4, "earth", "Earth Totem", "Call of Earth, in your starting valley. Your first totem." },
		{ 10, "fire", "Fire Totem", "Call of Fire: a climb in Durotar and a fight in The Barrens. Opens every fire totem." },
		{ 20, "water", "Water Totem", "Call of Water: the longest of the four, from The Barrens to Silverpine and back. Opens healing and mana totems, so start it at 20." },
		{ 30, "air", "Air Totem", "Call of Air: a single trip to Thousand Needles. Opens Windfury and Grace of Air." },
		EVERYONE_50,
	},
	MAGE = {
		{ 10, "first", "First assignment", "A job from your trainer near your capital, for an early robe or staff." },
		{ 15, "second", "Second assignment", "More gear from your trainer. None of your spells wait on a quest, so these are for the items." },
		{ 26, "third", "Third assignment", "Another gear quest from your trainer, a few levels before the wand." },
		{ 30, "wand", "Wand from the marsh", "Your trainer sends you to Tabetha in Dustwallow Marsh. A collection run for your pick of three wands." },
		EVERYONE_50,
		{ 60, "water", "Conjure Water, the last rank", "Not from a trainer: the tome drops in Dire Maul. Everyone in a raid will ask you for it." },
	},
	WARLOCK = {
		{ 1, "imp", "Summon Imp", "In your starting zone, before you leave it." },
		{ 10, "voidwalker", "Summon Voidwalker", "From your trainer in your capital. Your tank from here on." },
		{ 20, "succubus", "Summon Succubus", "A chain from your trainer that ends with summoning and beating her." },
		{ 30, "felhunter", "Summon Felhunter", "Another summon-and-subdue chain. The one you want against casters." },
		{ 40, "felsteed", "Summon Felsteed", "Your mount is a quest from your trainer, not a purchase. Free." },
		{ 50, "infernal", "Inferno", "From Niby the Almighty in Felwood: teaches you to call an Infernal." },
		EVERYONE_50,
		{ 60, "doomguard", "Ritual of Doom", "From Daio the Decrepit in the Tainted Scar, Blasted Lands. The last step needs a group." },
		{ 60, "dreadsteed", "Summon Dreadsteed", "A long, costly chain that ends with a ritual inside Dire Maul. Bring a group that knows it." },
	},
	DRUID = {
		{ 10, "bear", "Bear Form", "Your trainer teaches you to teleport to Moonglade, where the chain starts. It ends with a fight back in your starting lands." },
		{ 14, "cure", "Cure Poison", "From your trainer: a short errand in your race's second zone." },
		{ 16, "aquatic", "Aquatic Form", "Starts in Moonglade: two halves of a pendant from two different shores, then a swim. Worth it for every underwater quest after." },
		EVERYONE_50,
	},
}

-- Profession quests: the few places a profession waits on a quest rather than a trainer.
-- { skill line id, English name, rows }, row = { skill needed, level needed, key, name, how }
C.PROFESSIONS = {
	{ 129, "First Aid", {
		{ 225, 35, "triage", "Triage: Artisan First Aid",
		  "Alliance: Doctor Gustaf VanHowzen in Theramore. Horde: Doctor Gregory Victor in Hammerfall. Save a ward of wounded soldiers against the clock by bandaging the worst off first. Bring plenty of each bandage." },
	} },
	{ 185, "Cooking", {
		{ 225, 35, "clamlette", "Clamlette Surprise: Artisan Cooking",
		  "Dirge Quikcleave in Gadgetzan wants giant eggs, zesty clam meat and Alterac Swiss. Gather them on the way: the eggs and clams come from the high-level coasts and birds." },
	} },
	{ 356, "Fishing", {
		{ 225, 35, "angler", "Nat Pagle's Extreme Angler: Artisan Fishing",
		  "Nat Pagle, on his island in Dustwallow Marsh, wants one rare fish from each of four coasts: Feralas, Desolace, the Swamp of Sorrows and Stranglethorn. Each drops from a named stretch of water, so it takes patience." },
	} },
	{ 164, "Blacksmithing", {
		{ 200, 40, "smithpath", "Armorsmith or Weaponsmith",
		  "Your choice of two paths, taken with a master smith in Ironforge or Orgrimmar by handing in pieces you forge yourself. Each opens plans the other never sees." },
		{ 210, 40, "mithril", "The Mithril Order",
		  "Starts in Booty Bay and leads to Galvan the Ancient in Stranglethorn Vale, who trades ornate mithril plans for work you bring him." },
		{ 250, 40, "weaponmaster", "Hammer, axe or sword mastery",
		  "For weaponsmiths only: a second choice, taken in Everlook, of which kind of weapon you make best." },
	} },
	{ 165, "Leatherworking", {
		{ 225, 40, "leatherpath", "Dragonscale, Elemental or Tribal",
		  "Three paths, each taken with its own master by handing in pieces you make. Dragonscale is mail for hunters and shamans, Elemental is resistance leather, Tribal is druid and rogue gear. Look at what each makes at 300 before you pick." },
		{ 225, 30, "wildleather", "Wild Leather armor",
		  "A leatherworker in Feralas trades a set of Wild Leather patterns for crafted pieces, one quest per pattern." },
	} },
	{ 202, "Engineering", {
		{ 200, 30, "engpath", "Gnomish or Goblin engineering",
		  "Gnomish: Tinkmaster Overspark in Ironforge or Oglethorpe Obnoticus in Booty Bay. Goblin: Nixx Sprocketspring in Gadgetzan. You hand in things you build and get a membership card. Gnomish is gadgets and trinkets, Goblin is explosives." },
	} },
	{ 186, "Mining", {
		{ 230, 48, "darkiron", "Smelt Dark Iron",
		  "Taught by a ghost deep in Blackrock Depths, in exchange for gems and bars you bring. Nobody smelts dark iron without it, so it matters for late blacksmithing." },
	} },
	{ 171, "Alchemy", {} }, { 182, "Herbalism", {} }, { 197, "Tailoring", {} },
	{ 333, "Enchanting", {} }, { 393, "Skinning", {} },
}

-- Your professions: { [skill line id or lowercase name] = { name, skill } }. Clients differ in
-- how they list them, so both ways are tried and anything that errors is skipped.
function C:MyProfessions()
	local mine, found = {}, false
	if GetProfessions and GetProfessionInfo then
		-- The game leaves gaps in this list (no second profession, no fishing), so it's walked by
		-- position rather than as a list that would stop at the first gap.
		local slots = { pcall(GetProfessions) }
		if slots[1] then
			for i = 2, 7 do
				local index = slots[i]
				local ok2, name, _, skill, maxSkill, _, _, line
				if index then ok2, name, _, skill, maxSkill, _, _, line = pcall(GetProfessionInfo, index) end
				if ok2 and name and not ns.IsSecret(name) then
					local rec = { name = name, skill = ns.Num(skill) or 0, max = ns.Num(maxSkill) or 0 }
					if ns.Num(line) then mine[line] = rec end
					mine[name:lower()] = rec
					found = true
				end
			end
		end
	end
	if not found and GetNumSkillLines and GetSkillLineInfo then
		local ok, n = pcall(GetNumSkillLines)
		for i = 1, (ok and ns.Num(n)) or 0 do
			local ok2, name, isHeader, _, rank, _, _, maxRank = pcall(GetSkillLineInfo, i)
			if ok2 and name and not isHeader and not ns.IsSecret(name) then
				mine[name:lower()] = { name = name, skill = ns.Num(rank) or 0, max = ns.Num(maxRank) or 0 }
				found = true
			end
		end
	end
	return mine, found
end

local function ProfTicked() return ns.char.profQuests end

function C:ToggleProf(key)
	local t = ProfTicked()
	t[key] = (not t[key]) or nil
end

function C:ProfItems()
	local items = {}
	local level = UnitLevel("player") or 1
	local mine, known = self:MyProfessions()
	local onlyMine = ns.db.guide.profMine and known
	-- Quests in your log filed under one of your professions.
	local names = {}
	for _, rec in pairs(mine) do names[rec.name] = true end
	local live = {}
	for _, e in ipairs(ns.Quests.log) do if names[e.zone] then table.insert(live, e) end end
	if #live > 0 then
		table.insert(items, { key = "prof:live", icon = "Raid", title = "In your quest log now",
			sub = "Click one to point the arrow at it.", color = { 0.85, 0.7, 1 } })
		for _, e in ipairs(live) do
			table.insert(items, { key = "prof:log:" .. e.questID, kind = e.complete and "turnin" or "objective",
				title = e.title, questID = e.questID, classLog = e,
				sub = e.complete and "Ready to hand in." or (e.objective or "In progress."),
				right = e.complete and "|cff66ff66done|r" or "|cffffd100on it|r" })
		end
	end
	local shown = 0
	for _, prof in ipairs(self.PROFESSIONS) do
		local id, english, rows = prof[1], prof[2], prof[3]
		local rec = mine[id] or mine[english:lower()]
		if rec or not onlyMine then
			shown = shown + 1
			table.insert(items, { key = "prof:" .. id, icon = "Raid", title = rec and rec.name or english,
				sub = #rows == 0 and "Nothing here waits on a quest: it's all trainers and recipes." or
					(rec and "Your skill decides what's open." or "Not one of your professions."),
				right = rec and tostring(rec.skill) or "", color = { 0.85, 0.7, 1 } })
			for _, q in ipairs(rows) do
				local skill, lvl, key, name, how = q[1], q[2], q[3], q[4], q[5]
				local done = ProfTicked()[key]
				local ready = rec and rec.skill >= skill and level >= lvl
				local state = done and "|cff66ff66done|r" or (ready and "|cffffd100now|r") or (skill .. " skill")
				table.insert(items, { key = "prof:" .. key, profKey = key, kind = (ready and not done) and "objective" or "note",
					title = string.format("%d   %s", skill, name),
					sub = how .. "  Needs level " .. lvl .. ".", right = state, current = ready and not done,
					color = done and { 0.55, 0.55, 0.55 } or ((not ready) and { 0.8, 0.8, 0.8 } or nil) })
			end
		end
	end
	if shown == 0 then
		table.insert(items, { key = "prof:none", kind = "note", title = "No professions learned yet",
			sub = "Learn one from a trainer and its quests show here. Turn off \"Only my professions\" in Options to browse them all." })
	end
	return items
end

local function Class() return select(2, UnitClass("player")) or "WARRIOR" end
local function ClassName() return (UnitClass("player")) or "" end
local function Ticked() return ns.char.classQuests end

function C:For(class) return self.DATA[class or Class()] or {} end

-- Class quests in your log right now: the game files them under your class's name.
function C:InLog()
	local out, name = {}, ClassName()
	if name == "" then return out end
	for _, e in ipairs(ns.Quests.log) do
		if e.zone == name then table.insert(out, e) end
	end
	return out
end

-- Entries that are due: you have the level, and you haven't ticked them off.
function C:Due(level)
	local out = {}
	level = level or UnitLevel("player") or 1
	for _, q in ipairs(self:For()) do
		if q[1] <= level and not Ticked()[q[2]] then table.insert(out, q) end
	end
	return out
end

function C:Toggle(key)
	local t = Ticked()
	t[key] = (not t[key]) or nil
end

function C:Items()
	local items = {}
	local level = UnitLevel("player") or 1
	local live = self:InLog()
	if #live > 0 then
		table.insert(items, { key = "class:live", icon = "Raid", title = "In your quest log now",
			sub = "Click one to point the arrow at it.", color = { 0.85, 0.7, 1 } })
		for _, e in ipairs(live) do
			table.insert(items, { key = "class:log:" .. e.questID, kind = e.complete and "turnin" or "objective",
				title = e.title, questID = e.questID, classLog = e,
				sub = e.complete and "Ready to hand in." or (e.objective or "In progress."),
				right = e.complete and "|cff66ff66done|r" or "|cffffd100on it|r" })
		end
	end
	local list = self:For()
	local doneCount = 0
	for _, q in ipairs(list) do if Ticked()[q[2]] then doneCount = doneCount + 1 end end
	table.insert(items, { key = "class:head", icon = "Raid",
		title = ClassName() .. " class quests",
		sub = "What your class has coming and when. Click a row to tick it off. Forever adds some of its own: anything in your log shows above.",
		right = string.format("%d/%d", doneCount, #list), color = { 0.85, 0.7, 1 } })
	local firstOpen
	for _, q in ipairs(list) do
		local lvl, key, name, how = q[1], q[2], q[3], q[4]
		local done = Ticked()[key]
		local due = not done and lvl <= level
		local state = done and "|cff66ff66done|r" or (due and "|cffffd100now|r") or ("at " .. lvl)
		local current = due and not firstOpen
		if current then firstOpen = true end
		table.insert(items, { key = "class:" .. key, classKey = key, kind = due and "objective" or "note",
			title = string.format("Lv %d   %s", lvl, name), sub = how, right = state, current = current,
			color = done and { 0.55, 0.55, 0.55 } or ((not due) and { 0.8, 0.8, 0.8 } or nil) })
	end
	return items
end

ns:AddSlash("professions", function()
	if not ns.UI or not ns.UI.frame then return end
	if not ns.db.guide.profQuests then ns.Print("profession quests are turned off (Options > Guide & Routes).") return end
	ns.db.window.classView = "professions"
	ns.UI.frame:Show()
	ns.UI:SetTab("class")
end, "/nq professions - the quests your professions wait on, and the skill each one needs")

ns:AddSlash("class", function()
	if not ns.UI or not ns.UI.frame then return end
	if not ns.db.guide.classTab then ns.Print("class quests are turned off (Options > Guide & Routes).") return end
	ns.db.window.classView = "class"
	ns.UI.frame:Show()
	ns.UI:SetTab("class")
end, "/nq class - your class quests: what's in your log and what's coming at which level")
