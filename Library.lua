-- NeverQuest Library: reading QuestieDB.
--
-- NeverQuest's own database holds only what NeverQuest clients have seen in the game, which
-- is a small list to begin with. QuestieDB is the quest database built and curated by the
-- Questie team (GPLv3, https://github.com/Questie/QuestieDB). It is its own addon, installed
-- next to NeverQuest (the CurseForge app does this automatically, because NeverQuest lists it
-- as a required dependency) and kept up to date by them. NeverQuest reads it through its
-- public API, LibQuestieDB, and ships no copy of its data.
--
-- The rules this file keeps:
--   * The two are kept apart. Nothing from QuestieDB is written into NeverQuest's own
--     database, saved variables, exports, or messages to the party or guild. NeverQuest's
--     data stays NeverQuest's, and QuestieDB's stays QuestieDB's.
--   * Anything a NeverQuest client has seen for itself always wins over QuestieDB.
--   * With "Build my own" chosen (/nq db bundled off), or QuestieDB not installed, NeverQuest
--     never reads QuestieDB at all and works from its own data alone.
--
-- QuestieDB's answers are treated like any other outside data: checked, and never trusted to
-- have a particular shape.

local ADDON, ns = ...
local L = {}
ns.Library = L

local CONTRACT = 4       -- the QuestieDB API contract this file was written against
local MAX_SPOTS = 6      -- places kept per NPC; a patrol or a rare has many

-- What NeverQuest asks QuestieDB about each quest, in one read.
local QKEYS = { "name", "startedBy", "finishedBy", "requiredLevel", "questLevel", "requiredRaces",
	"requiredClasses", "preQuestGroup", "preQuestSingle", "exclusiveTo", "zoneOrSort",
	"nextQuestInChain", "specialFlags", "breadcrumbForQuestId", "requiredSkill", "requiredMaxLevel",
	"parentQuest" }

local lib, looked, refused
local areaMap, ends = {}, {}
local layer, layerCount, nameOnly, warming = {}, 0, 0, nil
local nextCache = {}
local ancestors = {}
local zoneTable, dungeonOf
local xpTable, objCache, spawnCache = nil, {}, {}

function L:Reset()
	ancestors = {}
	lib, looked, refused = nil, nil, nil
	areaMap, ends = {}, {}
	layer, layerCount, nameOnly, warming = {}, 0, 0, nil
	nextCache = {}
	zoneTable, dungeonOf = nil, nil
	xpTable, objCache, spawnCache = nil, {}, {}
end

-- QuestieDB's API when it is installed and this version of NeverQuest can read it, whatever
-- the "Quest data" setting says. Looked for once.
local function Find()
	if not looked then
		looked = true
		local q = rawget(_G, "LibQuestieDB")
		if type(q) == "table" and type(q.Quest) == "table" and type(q.Npc) == "table" then
			local ok, fine = true, true
			if type(q.RequireContract) == "function" then
				ok, fine = pcall(q.RequireContract, CONTRACT)
				-- An older QuestieDB still has every field NeverQuest reads (they are all in the
				-- first contract), so it is used rather than turned away.
				if not (ok and fine) and (ns.Num(q.contractVersion) or 0) < CONTRACT then
					ok, fine = pcall(q.RequireContract, 1)
				end
			end
			if ok and fine then lib = q else refused = true end
		end
	end
	return lib
end

-- The QuestieDB API, or nil when it is not installed, too old or too new for this version of
-- NeverQuest, or not wanted ("Build my own").
function L:Get()
	local cfg = ns.db and ns.db.questdb
	if cfg and cfg.bundled == false then return nil end
	return Find()
end

function L:Present() return self:Get() ~= nil end

-- Is QuestieDB installed at all, whatever the setting says?
function L:Installed() return type(rawget(_G, "LibQuestieDB")) == "table" end

-- One field of one quest, NPC or object. QuestieDB's getters are plain functions: Get(id, key).
local function Field(kind, id, key)
	local l = L:Get()
	local entity = l and l[kind]
	local fn = type(entity) == "table" and entity.Get
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn, id, key)
	if ok and not ns.IsSecret(v) then return v end
end

-- Everything NeverQuest uses about a quest, by field name, or nil for a quest QuestieDB
-- doesn't have.
local function Quest(qid)
	local l = L:Get()
	local QD = l and l.Quest
	if type(QD) ~= "table" or type(QD.GetAll) ~= "function" then return nil end
	local ok, row = pcall(QD.GetAll, qid, QKEYS)
	if not ok or type(row) ~= "table" then return nil end
	local q = {}
	for i, key in ipairs(QKEYS) do q[key] = row[i] end
	return q
end
L.Quest = Quest

-- QuestieDB's own table from the game's area numbers to its map numbers, with its overrides
-- laid on top. It ships as Lua source text, which is how QuestieDB hands it to consumers.
local function ZoneTable()
	if zoneTable ~= nil then return zoneTable or nil end
	zoneTable = false
	local l = L:Get()
	local support = l and l.Support
	if type(support) ~= "table" or type(support.Get) ~= "function" then return nil end
	local ok, zdb = pcall(support.Get, "ZoneDB")
	local private = ok and type(zdb) == "table" and zdb.private
	if type(private) ~= "table" then return nil end
	local function Read(v)
		if type(v) == "string" and loadstring then
			local f = loadstring(v)
			local fine, t = false, nil
			if f then fine, t = pcall(f) end
			v = fine and t or nil
		end
		return type(v) == "table" and v or nil
	end
	local t = { map = {}, parent = {} }
	for _, key in ipairs({ "areaIdToUiMapId", "areaIdToUiMapIdOverride" }) do
		for a, m in pairs(Read(private[key]) or {}) do t.map[a] = m end
	end
	for _, key in ipairs({ "subZoneToParentZone", "subZoneToParentZoneOverride" }) do
		for a, p in pairs(Read(private[key]) or {}) do t.parent[a] = p end
	end
	zoneTable = t
	return t
end

-- The dungeon an area number belongs to, by QuestieDB's own list: each dungeon's number, the
-- other numbers its quests are filed under (most Gnomeregan and Uldaman quests sit under one of
-- those), and the dungeons that are new in WoW Forever. Nil for anything else.
function L:DungeonName(areaID)
	areaID = ns.Num(areaID)
	if not areaID or not self:Get() then return nil end
	if not dungeonOf then
		dungeonOf = {}
		local support = lib.Support
		local ok, zdb = pcall(function() return support.Get("ZoneDB") end)
		local list = ok and type(zdb) == "table" and type(zdb.private) == "table" and zdb.private.dungeons
		for id, d in pairs(type(list) == "table" and list or {}) do
			local name = type(d) == "table" and d[1]
			if ns.Num(id) and type(name) == "string" and name ~= "" then
				dungeonOf[id] = name
				for _, other in ipairs(type(d[2]) == "table" and d[2] or {}) do
					if ns.Num(other) and dungeonOf[other] == nil then dungeonOf[other] = name end
				end
			end
		end
	end
	return dungeonOf[areaID]
end

local function RealMap(m)
	m = ns.Num(m)
	return m and m > 0 and C_Map and ns.SafeCall(C_Map.GetMapInfo, m) ~= nil and m or nil
end

-- QuestieDB names zones by the game's area numbers; NeverQuest uses map numbers. QuestieDB's
-- own table answers first, then the area's parent zone, then the game: it gives an area's name,
-- and the name finds the map. An area with no map of its own is left out rather than guessed at.
function L:AreaMap(areaID)
	areaID = ns.Num(areaID)
	if not areaID then return nil end
	local m = areaMap[areaID]
	if m == nil then
		m = false
		local zt = ZoneTable()
		if zt then
			local own = zt.map[areaID]
			if own == 0 then
				areaMap[areaID] = false   -- QuestieDB says this area is not shown on a map
				return nil
			end
			m = RealMap(own) or false
			local parent = not m and ns.Num(zt.parent[areaID])
			if parent then m = RealMap(zt.map[parent]) or false end
		end
		local name = not m and C_Map and C_Map.GetAreaInfo and ns.SafeCall(C_Map.GetAreaInfo, areaID)
		if type(name) == "string" and name ~= "" and not ns.IsSecret(name) then
			local id = ns.Nav.FindZone(name)
			local found = id and ns.Nav.MapName(id)
			if found and found:lower() == name:lower() then m = id end
		end
		areaMap[areaID] = m
	end
	return m or nil
end

-- The ids in one part of "startedBy" or "finishedBy": QuestieDB lists NPCs first, then
-- objects, then items, each a list of numbers.
local function Ids(v, out)
	out = out or {}
	if type(v) == "table" then
		for i = 1, math.min(#v, 8) do
			local id = ns.Num(v[i])
			if id and id > 0 then out[#out + 1] = id end
		end
	end
	return out
end
L.Ids = Ids

local function Places(id, name, out, object)
	local spawns = Field(object and "Object" or "Npc", id, "spawns")
	if type(spawns) ~= "table" then return end
	for areaID, list in pairs(spawns) do
		local m = L:AreaMap(areaID)
		if m and type(list) == "table" then
			for i = 1, math.min(#list, MAX_SPOTS) do
				local s = list[i]
				local x, y = type(s) == "table" and ns.Num(s[1]), type(s) == "table" and ns.Num(s[2])
				if x and y and x > 0 and y > 0 and x <= 100 and y <= 100 then
					out[#out + 1] = { m = m, x = x / 100, y = y / 100, name = name, npcID = (not object) and id or nil,
						objectID = object and id or nil, side = out.side }
				end
			end
		end
	end
end

local function Name(kind, id)
	local name = Field(kind, id, "name")
	return type(name) == "string" and name ~= "" and name or nil
end

-- { start = { spots }, finish = { spots } } for a quest, each spot { m, x, y, name, npcID }.
-- False when QuestieDB has nothing; remembered for the session either way.
function L:Ends(questID)
	questID = ns.Num(questID)
	if not questID or not self:Get() then return nil end
	local known = ends[questID]
	if known ~= nil then return known or nil end
	local res = false
	local q = Quest(questID)
	if q then
		res = { start = {}, finish = {} }
		for field, key in pairs({ startedBy = "start", finishedBy = "finish" }) do
			local by = type(q[field]) == "table" and q[field] or {}
			for _, npcID in ipairs(Ids(by[1])) do
				local name = Name("Npc", npcID)
				if name and not res[key].name then res[key].name = name end
				-- Which side this NPC will talk to: "A", "H", "AH" or unknown.
				local side = Field("Npc", npcID, "friendlyToFaction")
				if type(side) == "string" and side ~= "" and not res[key].side then res[key].side = side end
				Places(npcID, name, res[key])
			end
			-- A quest can start or end at a thing in the world: a wanted poster, a crate.
			for _, objectID in ipairs(Ids(by[2])) do
				local name = Name("Object", objectID)
				if name and not res[key].name then res[key].name = name end
				Places(objectID, name, res[key], true)
			end
		end
		if #res.start == 0 and #res.finish == 0 and not res.start.name and not res.finish.name then res = false end
	end
	ends[questID] = res
	return res or nil
end

-- One place for a quest's start or finish: the nearest to you when that can be measured,
-- otherwise the first listed.
local function Pick(list)
	if not list or #list == 0 then return nil end
	local best, bestD = list[1], nil
	for _, s in ipairs(list) do
		local d = ns.Nav.Distance(s.m, s.x, s.y)
		if d and (not bestD or d < bestD) then best, bestD = s, d end
	end
	return best
end

function L:Start(questID)
	local e = self:Ends(questID)
	return e and Pick(e.start) or nil
end

function L:Finish(questID)
	local e = self:Ends(questID)
	return e and Pick(e.finish) or nil
end

function L:StartName(questID)
	local e = self:Ends(questID)
	return e and e.start.name or nil
end

function L:FinishName(questID)
	local e = self:Ends(questID)
	return e and e.finish.name or nil
end

---------------------------------------------------------------------------
-- What a quest is worth, and where its work is done (Advisor.lua plans with these)
---------------------------------------------------------------------------
local function XPTable()
	if xpTable ~= nil then return xpTable or nil end
	xpTable = false
	local l = L:Get()
	local support = l and l.Support
	if type(support) == "table" and type(support.Get) == "function" then
		local ok, mod = pcall(support.Get, "QuestXP")
		local db = ok and type(mod) == "table" and mod.db
		if type(db) == "table" then xpTable = db end
	end
	return xpTable or nil
end

-- The share of a quest's XP you get at your level: full until you are five levels past it,
-- then 80, 60, 40 and 20%, and a tenth from ten levels on. The classic rule.
function L.XPShare(questLevel, level)
	local over = (ns.Num(level) or 1) - (ns.Num(questLevel) or ns.Num(level) or 1)
	if over <= 5 then return 1 end
	if over == 6 then return 0.8 end
	if over == 7 then return 0.6 end
	if over == 8 then return 0.4 end
	if over == 9 then return 0.2 end
	return 0.1
end

-- The XP a quest gives at a level (yours unless given), by QuestieDB's table, and the quest's
-- own level. Nil when QuestieDB doesn't know it. The game's figure, for a quest in your log,
-- is better and is used before this wherever there is one.
function L:QuestXP(questID, level)
	local t = self:Get() and XPTable()
	local row = t and t[ns.Num(questID) or 0]
	if type(row) ~= "table" then return nil end
	local qlevel, xp = ns.Num(row[1]), ns.Num(row[2])
	if not xp or xp <= 0 then return nil end
	return math.floor(xp * L.XPShare(qlevel, level or UnitLevel("player") or 1) + 0.5), qlevel
end

local SPAWN_CAP = 40    -- places read per mob or object
local DROP_SOURCES = 6  -- mobs or objects read per item

local function SpawnPoints(kind, id, out)
	local spawns = Field(kind, id, "spawns")
	if type(spawns) ~= "table" then return end
	for areaID, list in pairs(spawns) do
		if type(list) == "table" then
			for i = 1, math.min(#list, SPAWN_CAP) do
				local s = list[i]
				local x, y = type(s) == "table" and ns.Num(s[1]), type(s) == "table" and ns.Num(s[2])
				if x and y and x > 0 and y > 0 and x <= 100 and y <= 100 then
					out[#out + 1] = { a = areaID, x = x / 100, y = y / 100 }
				end
			end
		end
	end
end

-- The middle of the area with the most of these places in it, on a map NeverQuest knows:
-- { m, x, y, n }. Where a mob lives in two zones, the one with more of them wins.
local function Centre(points)
	local count = {}
	for _, p in ipairs(points) do count[p.a] = (count[p.a] or 0) + 1 end
	local order = {}
	for a, n in pairs(count) do order[#order + 1] = { a = a, n = n } end
	table.sort(order, function(a, b) return a.n > b.n end)
	for _, o in ipairs(order) do
		local m = L:AreaMap(o.a)
		if m then
			local sx, sy = 0, 0
			for _, p in ipairs(points) do
				if p.a == o.a then sx, sy = sx + p.x, sy + p.y end
			end
			return { m = m, x = sx / o.n, y = sy / o.n, n = o.n }
		end
	end
end

local function IdOf(entry)
	if type(entry) == "number" then return entry end
	return type(entry) == "table" and ns.Num(entry[1]) or nil
end

-- What a quest asks you to do, and where: { spots = { { m, x, y, n, kind } }, count = number
-- of objectives, units = things to kill or collect }, false for a quest with no objectives
-- (talk to someone, take something somewhere), or nil when QuestieDB isn't in use. Kept for
-- the session. A mob, an object, or for an item the mobs and objects it comes from.
function L:Objectives(questID)
	questID = ns.Num(questID)
	if not questID or not self:Get() then return nil end
	local known = objCache[questID]
	if known ~= nil then return known end
	local res = false
	local ob = Field("Quest", questID, "objectives")
	if type(ob) == "table" then
		local spots, count = {}, 0
		local killish = 0   -- objectives done by killing things: mobs, and items that mobs drop
		local function Add(kind, points, kills)
			count = count + 1
			if kills then killish = killish + 1 end
			local c = Centre(points)
			if c then c.kind = kind spots[#spots + 1] = c end
		end
		for _, c in ipairs(type(ob[1]) == "table" and ob[1] or {}) do
			local id, pts = IdOf(c), {}
			if id then SpawnPoints("Npc", id, pts) end
			Add("monster", pts, true)
		end
		for _, c in ipairs(type(ob[2]) == "table" and ob[2] or {}) do
			local id, pts = IdOf(c), {}
			if id then SpawnPoints("Object", id, pts) end
			Add("object", pts)
		end
		for _, c in ipairs(type(ob[3]) == "table" and ob[3] or {}) do
			local id, pts = IdOf(c), {}
			local dropped = false
			if id then
				local npcs, objs = Field("Item", id, "npcDrops"), Field("Item", id, "objectDrops")
				dropped = type(npcs) == "table" and #npcs > 0
				for i = 1, math.min(type(npcs) == "table" and #npcs or 0, DROP_SOURCES) do
					local n = ns.Num(npcs[i]) if n then SpawnPoints("Npc", n, pts) end
				end
				for i = 1, math.min(type(objs) == "table" and #objs or 0, DROP_SOURCES) do
					local o = ns.Num(objs[i]) if o then SpawnPoints("Object", o, pts) end
				end
			end
			Add("item", pts, dropped)
		end
		-- Kill credit: any of several mobs counts ({ { ids }, base mob, text }).
		for _, c in ipairs(type(ob[5]) == "table" and ob[5] or {}) do
			local pts = {}
			local ids = type(c) == "table" and c[1]
			for i = 1, math.min(type(ids) == "table" and #ids or 0, DROP_SOURCES) do
				local n = ns.Num(ids[i]) if n then SpawnPoints("Npc", n, pts) end
			end
			Add("monster", pts, true)
		end
		if count > 0 then
			-- How many: the numbers in the objective text ("Kill 10 Kobold Vermin").
			local units = 0
			local text = Field("Quest", questID, "objectivesText")
			for _, line in ipairs(type(text) == "table" and text or { text }) do
				if type(line) == "string" and not ns.IsSecret(line) then
					for n in line:gmatch("(%d+)%s+%a") do
						n = tonumber(n)
						if n and n >= 2 and n <= 40 then units = units + n end
					end
				end
			end
			res = { spots = spots, count = count, units = math.min(60, math.max(units, count)), killShare = killish / count }
		end
	end
	objCache[questID] = res
	return res
end

-- Every place for each of a quest's objectives, for the maps: a list of
--   { kind = "npc" | "obj", name = the mob or object, match = the objective's own name (the mob,
--     the item or the object), drop = the item it drops, if any, pts = { { m, x, y } } }
-- At most SPAWN_CAP places per mob or object and DROP_SOURCES mobs or objects per item. nil when
-- QuestieDB isn't in use. Kept for the session.
function L:ObjectiveSpawns(questID)
	questID = ns.Num(questID)
	if not questID or not self:Get() then return nil end
	local known = spawnCache[questID]
	if known ~= nil then return known end
	local res = {}
	local ob = Field("Quest", questID, "objectives")
	local function Name(kind, id)
		local n = Field(kind, id, "name")
		return (type(n) == "string" and n ~= "" and not ns.IsSecret(n)) and n or nil
	end
	local function Add(kind, id, match, drop)
		local raw, pts = {}, {}
		SpawnPoints(kind == "npc" and "Npc" or "Object", id, raw)
		for _, s in ipairs(raw) do
			local m = L:AreaMap(s.a)
			if m then pts[#pts + 1] = { m = m, x = s.x, y = s.y } end
		end
		local name = Name(kind == "npc" and "Npc" or "Object", id)
		if #pts > 0 and name then
			res[#res + 1] = { kind = kind, id = id, name = name, match = match or name, drop = drop, pts = pts }
		end
	end
	if type(ob) == "table" then
		for _, c in ipairs(type(ob[1]) == "table" and ob[1] or {}) do
			local id = IdOf(c)
			if id then Add("npc", id) end
		end
		for _, c in ipairs(type(ob[2]) == "table" and ob[2] or {}) do
			local id = IdOf(c)
			if id then Add("obj", id) end
		end
		for _, c in ipairs(type(ob[3]) == "table" and ob[3] or {}) do
			local id = IdOf(c)
			local item = id and Name("Item", id)
			if item then
				local npcs, objs = Field("Item", id, "npcDrops"), Field("Item", id, "objectDrops")
				for i = 1, math.min(type(npcs) == "table" and #npcs or 0, DROP_SOURCES) do
					local n = ns.Num(npcs[i]) if n then Add("npc", n, item, item) end
				end
				for i = 1, math.min(type(objs) == "table" and #objs or 0, DROP_SOURCES) do
					local o = ns.Num(objs[i]) if o then Add("obj", o, item, item) end
				end
			end
		end
		-- Kill credit: any of several mobs counts ({ { ids }, base mob, text }).
		for _, c in ipairs(type(ob[5]) == "table" and ob[5] or {}) do
			local ids = type(c) == "table" and c[1]
			local text = type(c) == "table" and type(c[3]) == "string" and c[3] or nil
			for i = 1, math.min(type(ids) == "table" and #ids or 0, DROP_SOURCES) do
				local n = ns.Num(ids[i]) if n then Add("npc", n, text) end
			end
		end
	end
	spawnCache[questID] = res
	return res
end

-- A class or profession quest (QuestieDB lists the classes, or the skill it needs).
function L:ClassOrProfession(questID)
	questID = ns.Num(questID)
	if not questID or not self:Get() then return false end
	if (ns.Num(Field("Quest", questID, "requiredClasses")) or 0) > 0 then return true end
	local skill = Field("Quest", questID, "requiredSkill")
	return type(skill) == "table" and ns.Num(skill[1]) ~= nil
end

-- QuestieDB's raid flag (questFlags bit 64) for a quest. Read when asked, not kept in the layer.
function L:IsRaid(questID)
	questID = ns.Num(questID)
	if not questID or not self:Get() then return false end
	local flags = ns.Num(Field("Quest", questID, "questFlags"))
	return flags ~= nil and math.floor(flags / 64) % 2 == 1
end

-- Only what has been worked out already, so a caller in a hurry never pays for it: the
-- answer, false (no objectives), or nil (not yet; Advisor.lua works these out in the background).
function L:ObjectivesKnown(questID)
	return objCache[ns.Num(questID) or 0]
end

---------------------------------------------------------------------------
-- The layer: every quest QuestieDB can put on a map, ready to be listed
--
-- Asking about six thousand quests takes a moment, so it is done a few hundred at a time after
-- you log in, and the map fills in over the first second or two. An entry has the same fields
-- as one of NeverQuest's own (QuestDB.lua), marked lib, plus:
--   rl   the level you must be to take it      pre  quests that must be done first
--   bar  "faction" or "other" when this character can never take it
---------------------------------------------------------------------------
local WARM_BATCH = 150   -- quests per step at most
local WARM_BUDGET = 6    -- milliseconds per step at most, so a slow machine never hitches
local WARM_GAP = 0.05
local WARM_GAP_CUT = 0.03  -- after a step that ran out of time, so a slow machine still finishes soon

local function HasBit(mask, n)
	return n and n >= 1 and math.floor(mask / 2 ^ (n - 1)) % 2 == 1
end

-- This character's bit in QuestieDB's race masks. QuestieDB's own table says which: the races
-- that are new in WoW Forever have numbers far above the bit they use. Without the table, the
-- classic rule (race n is bit n) is right for the classic races and nothing is assumed for others.
local function RaceBit()
	local raceID = ns.Num(select(3, UnitRace("player")))
	if not raceID then return nil end
	local l = L:Get()
	local byId = l and type(l.Enum) == "table" and l.Enum.raceMaskById
	if type(byId) == "table" then return ns.Num(byId[raceID]) end
	return raceID <= 30 and 2 ^ (raceID - 1) or nil
end

local function Barred(q)
	local races, classes = ns.Num(q.requiredRaces) or 0, ns.Num(q.requiredClasses) or 0
	if races > 0 then
		local bit = RaceBit()
		if bit and bit > 0 and math.floor(races / bit) % 2 == 0 then return "faction" end
	end
	if classes > 0 then
		local classID = select(3, UnitClass("player"))
		if ns.Num(classID) and not HasBit(classes, classID) then return "other" end
	end
	return nil
end

local function IdList(list, limit)
	local out
	if type(list) == "table" then
		for i = 1, math.min(#list, limit or 6) do
			local id = ns.Num(list[i])
			if id and id > 0 then out = out or {} out[#out + 1] = id end
		end
	end
	return out
end

-- What has to be done first. QuestieDB keeps two lists and they mean different things:
-- preQuestGroup is quests that must ALL be done, preQuestSingle is quests of which ANY ONE will
-- do (the same step under another number for another race or class, mostly). Returns the
-- all-of list and the any-of list; a single with one quest in it is simply required.
local function Pre(q, limit)
	local all, any = IdList(q.preQuestGroup, limit), IdList(q.preQuestSingle, limit)
	if any and #any == 1 then
		all = all or {}
		all[#all + 1] = any[1]
		any = nil
	end
	return all, any
end

-- Every quest that has to be done before this one, all the way back its chain. Cached in
-- `ancestors` (declared at the top, so Reset can clear it).
local function Ancestors(qid)
	local known = ancestors[qid]
	if known then return known end
	known = {}
	ancestors[qid] = known
	local queue, depth = { qid }, 0
	while #queue > 0 and depth < 12 do
		depth = depth + 1
		local nextQueue = {}
		for _, id in ipairs(queue) do
			local single, group = Field("Quest", id, "preQuestSingle"), Field("Quest", id, "preQuestGroup")
			for _, list in ipairs({ IdList(single, 12) or {}, IdList(group, 12) or {} }) do
				for _, p in ipairs(list) do
					if not known[p] and p ~= qid then
						known[p] = true
						nextQueue[#nextQueue + 1] = p
					end
				end
			end
		end
		queue = nextQueue
	end
	return known
end

local function Entry(qid)
	local q = Quest(qid)
	if not q then return nil end
	local title = q.name
	if type(title) ~= "string" or title == "" or ns.IsSecret(title) then return nil end
	-- Placeholders left in the game's data, never offered to anyone: "<NYI> ...", "REUSE ME".
	if title:find("^%s*<") or title:upper():find("^REUSE ?ME") then return nil end
	local e = L:Ends(qid)
	-- No place to stand is still worth having: a quest with a name and a level is enough to
	-- search and to plan by.
	local s = e and e.start[1] or {}
	local level = ns.Num(q.questLevel)
	local rl = ns.Num(q.requiredLevel)
	local pre, any = Pre(q)
	-- Quests that close this one: taking either shuts the other, and an optional lead-in is
	-- pointless once the quest it leads to is taken or done.
	local shut
	local function Shut(id)
		id = ns.Num(id)
		if id and id > 0 and id ~= qid then shut = shut or {} shut[#shut + 1] = id end
	end
	if type(q.exclusiveTo) == "table" then
		for i = 1, math.min(#q.exclusiveTo, 8) do Shut(q.exclusiveTo[i]) end
	end
	Shut(q.breadcrumbForQuestId)
	-- The same quest under another number: the game keeps separate copies of one quest for
	-- different races, classes or versions, all with one title and one giver. Finishing any of
	-- them finishes it as far as a player is concerned. A quest earlier or later in this one's
	-- own chain is a real part of it, not a twin, and is left out: every part of a chain like
	-- The Defias Brotherhood has the same title and giver.
	local twins
	if s.npcID then
		local also = Field("Npc", s.npcID, "questStarts")
		if type(also) == "table" then
			for i = 1, math.min(#also, 60) do
				local other = ns.Num(also[i])
				if other and other ~= qid and Name("Quest", other) == title
					and not Ancestors(qid)[other] and not Ancestors(other)[qid] then
					twins = twins or {} twins[#twins + 1] = other
				end
			end
		end
	end
	local special = ns.Num(q.specialFlags) or 0
	-- zs: the zone (an area number) or category the quest is filed under. Dungeons.lua uses it
	-- to tell which quests are done inside a dungeon.
	local zs = ns.Num(q.zoneOrSort)
	-- skill: a profession and the skill in it the quest asks for.  xl: the last level it is
	-- offered at.  parent: the quest this one is a part of, only offered while that one is in
	-- your log. QuestDB.lua's Status holds these up against the character as it is now.
	local skill = type(q.requiredSkill) == "table" and ns.Num(q.requiredSkill[1]) and q.requiredSkill[1] > 0
		and { q.requiredSkill[1], ns.Num(q.requiredSkill[2]) or 1 } or nil
	local xl, parent = ns.Num(q.requiredMaxLevel), ns.Num(q.parentQuest)
	return { t = title, l = (level and level > 0) and level or nil, rl = (rl and rl > 0) and rl or nil,
		m = s.m, x = s.x, y = s.y, f = e and e.start.side, pre = pre, any = any, bar = Barred(q), lib = true,
		shut = shut, twins = twins, again = (special % 2 == 1) or nil, zs = (zs and zs > 0) and zs or nil,
		skill = skill, xl = (xl and xl > 0) and xl or nil, parent = (parent and parent > 0 and parent ~= qid) and parent or nil }
end

-- The quest QuestieDB says comes next in this one's chain, or nil.
function L:NextInChain(questID)
	questID = ns.Num(questID)
	if not questID or not self:Get() then return nil end
	local known = nextCache[questID]
	if known == nil then
		known = ns.Num(Field("Quest", questID, "nextQuestInChain")) or false
		if known and known <= 0 then known = false end
		nextCache[questID] = known
	end
	return known or nil
end

-- Every quest number QuestieDB has a row for, ascending.
function L:QuestIds()
	local l = self:Get()
	local QD = l and l.Quest
	if type(QD) ~= "table" or type(QD.GetAllIds) ~= "function" then return nil end
	local ok, ids = pcall(QD.GetAllIds)
	return ok and type(ids) == "table" and ids or nil
end

function L:Layer() return layer end
function L:Count() return layerCount, nameOnly end
function L:Warming() return warming ~= nil end

-- Builds the layer in the background. Safe to call again; it only ever runs once at a time.
function L:Warm(done)
	if warming or not self:Get() then return false end
	local ids = self:QuestIds()
	if not ids then return false end
	layer, layerCount, nameOnly = {}, 0, 0
	local run = { i = 1 }
	warming = run
	local function step()
		if warming ~= run then return end
		if InCombatLockdown() then ns.After(2, step) return end
		local began = debugprofilestop and debugprofilestop()
		local cut
		for n = 1, WARM_BATCH do
			-- Out of time for this frame: carry on a moment later.
			if began and n > 10 and debugprofilestop() - began > WARM_BUDGET then cut = true break end
			local qid = ns.Num(ids[run.i])
			if not qid then
				warming = nil
				L:ReleaseCache()
				if ns.QuestDB then ns.QuestDB:ClearNearby() end
				ns:SendMessage("QUESTDB_UPDATED")
				ns:SendMessage("MAP_OFFERS_UPDATED")
				if done then done(layerCount) end
				return
			end
			run.i = run.i + 1
			local e = Entry(qid)
			if e then
				layer[qid] = e
				if e.m then layerCount = layerCount + 1 else nameOnly = nameOnly + 1 end
			end
		end
		ns.After(cut and WARM_GAP_CUT or WARM_GAP, step)
	end
	step()
	return true
end

local told
-- Reading every quest leaves QuestieDB holding a decoded copy of each row. NeverQuest keeps what
-- it needs in its own layer, so once that is built the copies are handed back (QuestieDB's own
-- InvalidateCache; it only means the next read decodes again). Left alone when Questie itself
-- is running, since those copies are then Questie's to use.
function L:ReleaseCache()
	local l = self:Get()
	local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	if not l or type(l.InvalidateCache) ~= "function" or (loaded and ns.SafeCall(loaded, "Questie")) then return false end
	return pcall(l.InvalidateCache) and true or false
end

ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
	if layerCount == 0 and not warming then ns.After(3, function() L:Warm() end) end
	-- Set to use QuestieDB but it isn't there (a manual install without it): say so once a
	-- session, so an emptier map has an explanation.
	if not told and ns.db and ns.db.questdb.bundled ~= false and not L:Get() then
		told = true
		ns.After(6, function()
			if L:Get() then return end
			ns.Print(refused and "QuestieDB is installed but this version of NeverQuest can't read it. Update both through the CurseForge app; until then the map shows what NeverQuest has learned itself."
				or "QuestieDB isn't installed, so the map only shows what NeverQuest has learned itself. The CurseForge app installs it with NeverQuest. To build your own database instead, choose Build my own under Options > Quest database.")
		end)
	end
end)

---------------------------------------------------------------------------
-- /nq lib
---------------------------------------------------------------------------
local function Show(v, depth)
	depth = depth or 0
	local t = type(v)
	if t == "string" then return '"' .. (#v > 60 and (v:sub(1, 60) .. "...") or v) .. '"' end
	if t ~= "table" then return tostring(v) end
	if depth >= 3 then return "{...}" end
	local parts, n = {}, 0
	for k, val in pairs(v) do
		n = n + 1
		if n > 10 then parts[#parts + 1] = "..." break end
		parts[#parts + 1] = tostring(k) .. "=" .. Show(val, depth + 1)
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

function L:Version()
	local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local v = get and ns.SafeCall(get, "QuestieDB", "Version")
	return type(v) == "string" and v ~= "" and v or nil
end

-- QuestieDB's own author line, from its TOC, or nil when it isn't installed.
function L:Authors()
	if not self:Installed() then return nil end
	local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local who = get and ns.SafeCall(get, "QuestieDB", "Author")
	return type(who) == "string" and who ~= "" and not ns.IsSecret(who) and who or nil
end

-- One coloured line on whether QuestieDB is there to be used, whatever the setting says: for
-- the setup wizard, where the choice is made.
function L:Short()
	if not self:Installed() then
		return "|cffff9933QuestieDB isn't installed right now, so NeverQuest works from its own data either way. The CurseForge app installs it with NeverQuest.|r"
	end
	if not Find() then
		return "|cffff9933QuestieDB is installed, but this version of NeverQuest can't read it. Update both through the CurseForge app.|r"
	end
	local v = self:Version()
	return "|cff33ff33QuestieDB" .. (v and (" " .. v) or "") .. " is installed.|r"
end

-- What NeverQuest makes of one quest from QuestieDB, worked out afresh: for /nq lib <id>.
function L:Entry(questID)
	questID = ns.Num(questID)
	return questID and self:Get() and Entry(questID) or nil
end

function L:StatusLines(questID)
	local lines = {}
	local l = self:Get()
	if ns.db.questdb.bundled == false then
		lines[#lines + 1] = "QuestieDB: not in use. You chose to build your own quest database, so NeverQuest goes by what it has seen itself. /nq db bundled on uses QuestieDB again."
	elseif refused then
		lines[#lines + 1] = "QuestieDB: installed, but this version of NeverQuest can't read it. Update both through the CurseForge app. Until then NeverQuest goes by what it has learned itself."
	elseif not l then
		lines[#lines + 1] = "QuestieDB: not installed. NeverQuest lists it as a required dependency, so the CurseForge app installs it for you; with a manual install, add the QuestieDB addon. Until then NeverQuest goes by what it has learned itself."
	else
		lines[#lines + 1] = string.format("QuestieDB%s in use: %d quests placed on the map and %d more known by name and level only%s. QuestieDB is built and curated by the Questie team and updated separately; /nq db bundled off builds your own database instead.",
			self:Version() and (" " .. self:Version()) or "", layerCount, nameOnly, warming and ", still loading" or "")
	end
	if l and questID then
		lines[#lines + 1] = "QuestieDB's answer for quest " .. questID .. ": " .. Show(Quest(questID))
		local e = self:Ends(questID)
		if not e then
			lines[#lines + 1] = "nothing NeverQuest can use from that."
		else
			for _, key in ipairs({ "start", "finish" }) do
				local s = Pick(e[key])
				lines[#lines + 1] = string.format("%s: %s%s", key, e[key].name or "(no name)",
					s and string.format(" at %s %.1f, %.1f (%d places)", ns.Nav.MapName(s.m) or s.m, s.x * 100, s.y * 100, #e[key]) or ", no place on a map NeverQuest knows")
			end
		end
		-- And what that comes to for this character, which is the usual question.
		local entry = Entry(questID)
		if not entry then
			lines[#lines + 1] = "NeverQuest leaves this one out: no name, or a placeholder the game never offers."
		elseif ns.QuestDB then
			local why = { done = "done, or closed by a quest you took or finished", log = "in your log", available = "open to you now",
				later = "opens at level " .. tostring(entry.rl or entry.l or "?"), locked = "waiting on an earlier quest, a profession skill or the quest it is a part of",
				faction = "not for your race or faction", other = "not for this character (class, profession or level)", ["repeat"] = "a repeatable hand-in, not shown as a new quest" }
			local st = ns.QuestDB:Status(questID, ns.QuestDB:Get(questID) or entry)
			lines[#lines + 1] = "for this character: " .. (why[st] or st) .. "."
		end
	end
	return lines
end

local function LibCommand(rest)
	rest = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if (rest == "on" or rest == "off") and ns.QuestDB then ns.QuestDB:SetBundled(rest == "on") end
	for _, line in ipairs(L:StatusLines(tonumber(rest))) do ns.Print(line) end
end
ns:AddSlash("lib", LibCommand, "/nq lib [on | off | <quest number>] - QuestieDB: whether it is in use, and what it says about a quest for this character")
ns:AddSlash("questiedb", LibCommand)
