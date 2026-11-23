-- NeverQuest Library: reading the LibQuestDB quest library.
--
-- NeverQuest's own database holds only what NeverQuest clients have seen in the game, which
-- is a small list to begin with. LibQuestDB (by Pimptasty, MIT licence) is a full quest
-- database, and a copy of it ships inside NeverQuest in Libs\QuestDB, unchanged, with its
-- licence. NeverQuest asks it where quests start and end and uses the answers to fill the map.
-- A newer copy installed as its own addon is used in place of the bundled one.
--
-- The rules this file keeps:
--   * The two are kept apart. Nothing from the library is written into NeverQuest's own
--     database, saved variables, exports, or messages to the party or guild. NeverQuest's
--     data stays NeverQuest's, and the library's stays the library's.
--   * Anything a NeverQuest client has seen for itself always wins over the library.
--   * With the library switched off (/nq lib off) everything works exactly as before.
--
-- The library is used through its published functions only. Its answers are treated like any
-- other outside data: checked, and never trusted to have a particular shape.

local ADDON, ns = ...
local L = {}
ns.Library = L

local NAME = "LibQuestDB-1.0"
local MAX_SPOTS = 6      -- places kept per NPC; a patrol or a rare has many

local lib, looked
local areaMap, ends = {}, {}
local layer, layerCount, nameOnly, warming = {}, 0, 0, nil
local nextCache = {}

function L:Reset()
	lib, looked = nil, nil
	areaMap, ends = {}, {}
	layer, layerCount, nameOnly, warming = {}, 0, 0, nil
	nextCache = {}
end

-- The library, or nil when it is not installed, not ready, or switched off.
function L:Get()
	local cfg = ns.db and ns.db.questdb
	if cfg and (cfg.library == false or cfg.bundled == false) then return nil end
	if not looked then
		looked = true
		local stub = _G.LibStub
		if stub then
			local ok, found = pcall(stub, NAME, true)
			if ok and type(found) == "table" and type(found.GetQuest) == "function" then lib = found end
		end
	end
	if not lib then return nil end
	if type(lib.IsReady) == "function" then
		local ok, ready = pcall(lib.IsReady, lib)
		if not ok or ready == false then return nil end
	end
	return lib
end

function L:Present() return self:Get() ~= nil end

local function Call(name, ...)
	local l = L:Get()
	local fn = l and l[name]
	if type(fn) ~= "function" then return nil end
	local ok, res = pcall(fn, l, ...)
	if ok and not ns.IsSecret(res) then return res end
end

-- The library names zones by the game's area numbers; NeverQuest uses map numbers. The game
-- gives an area's name, and the name finds the map. An area with no map of its own (a cave, a
-- subzone) is left out rather than guessed at.
function L:AreaMap(areaID)
	areaID = ns.Num(areaID)
	if not areaID then return nil end
	local m = areaMap[areaID]
	if m == nil then
		m = false
		-- The library's own answer first; it is built from this client's tables.
		local own = ns.Num(Call("GetUiMapId", areaID))
		if own and own > 0 and ns.SafeCall(C_Map.GetMapInfo, own) ~= nil then m = own end
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

-- NPC numbers out of whatever shape "startedBy" or "finishedBy" turns out to have: a number,
-- a list of numbers, a list of { id = , type = }, a table keyed npc / npcs / creature, or a
-- list of lists whose first is the NPCs.
local function NpcIDs(v, out, depth)
	out, depth = out or {}, depth or 0
	if type(v) == "number" then
		if v > 0 then out[#out + 1] = v end
	elseif type(v) == "table" and depth < 3 then
		local keyed = v.npc or v.npcs or v.creature or v.creatures or v.NPC
		if keyed ~= nil then
			NpcIDs(keyed, out, depth + 1)
		elseif v.id ~= nil then
			local kind = v.type or v.kind
			if kind == nil or kind == "npc" or kind == "creature" then NpcIDs(v.id, out, depth + 1) end
		elseif type(v[1]) == "table" and v[1].id == nil then
			NpcIDs(v[1], out, depth + 1)
		else
			for i = 1, math.min(#v, 8) do NpcIDs(v[i], out, depth + 1) end
		end
	end
	return out
end
L.NpcIDs = NpcIDs

local function Places(npcID, name, out, object)
	local spawns = Call(object and "GetObjectSpawns" or "GetNPCSpawns", npcID)
	if type(spawns) ~= "table" then return end
	for areaID, list in pairs(spawns) do
		local m = L:AreaMap(areaID)
		if m and type(list) == "table" then
			for i = 1, math.min(#list, MAX_SPOTS) do
				local s = list[i]
				local x, y = type(s) == "table" and ns.Num(s[1] or s.x), type(s) == "table" and ns.Num(s[2] or s.y)
				if x and y and x > 0 and y > 0 and x <= 100 and y <= 100 then
					out[#out + 1] = { m = m, x = x / 100, y = y / 100, name = name, npcID = (not object) and npcID or nil,
						objectID = object and npcID or nil, side = out.side }
				end
			end
		end
	end
end

-- { start = { spots }, finish = { spots } } for a quest, each spot { m, x, y, name, npcID }.
-- False when the library has nothing; remembered for the session either way.
function L:Ends(questID)
	questID = ns.Num(questID)
	if not questID or not self:Get() then return nil end
	local known = ends[questID]
	if known ~= nil then return known or nil end
	local res = false
	local q = Call("GetQuest", questID)
	if type(q) == "table" then
		res = { start = {}, finish = {} }
		for field, key in pairs({ startedBy = "start", finishedBy = "finish" }) do
			for _, npcID in ipairs(NpcIDs(q[field])) do
				local npc = Call("GetNPC", npcID)
				local name = type(npc) == "table" and type(npc.name) == "string" and not ns.IsSecret(npc.name) and npc.name or nil
				if name and not res[key].name then res[key].name = name end
				-- Which side this NPC will talk to: "A", "H", "AH" or unknown.
				local side = type(npc) == "table" and type(npc.friendlyToFaction) == "string" and npc.friendlyToFaction or nil
				if side and not res[key].side then res[key].side = side end
				Places(npcID, name, res[key])
			end
			-- A quest can start or end at a thing in the world: a wanted poster, a crate.
			local objects = type(q[field]) == "table" and q[field].objects
			if type(objects) == "table" then
				for i = 1, math.min(#objects, 8) do
					local id = ns.Num(objects[i])
					if id and id > 0 then
						local obj = Call("GetObject", id)
						local name = type(obj) == "table" and type(obj.name) == "string" and not ns.IsSecret(obj.name) and obj.name or nil
						Places(id, name, res[key], true)
					end
				end
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
-- The layer: every quest the library can put on a map, ready to be listed
--
-- Asking the library about four thousand quests takes a moment, so it is done a few hundred
-- at a time after you log in, and the map fills in over the first second or two. An entry has
-- the same fields as one of NeverQuest's own (QuestDB.lua), marked lib, plus:
--   rl   the level you must be to take it      pre  quests that must be done first
--   bar  "faction" or "other" when this character can never take it
---------------------------------------------------------------------------
local WARM_BATCH = 150
local WARM_GAP = 0.05

local function HasBit(mask, n)
	return n and n >= 1 and math.floor(mask / 2 ^ (n - 1)) % 2 == 1
end

local function Barred(q)
	local races, classes = ns.Num(q.requiredRaces) or 0, ns.Num(q.requiredClasses) or 0
	if races > 0 then
		local raceID = select(3, UnitRace("player"))
		if ns.Num(raceID) and not HasBit(races, raceID) then return "faction" end
	end
	if classes > 0 then
		local classID = select(3, UnitClass("player"))
		if ns.Num(classID) and not HasBit(classes, classID) then return "other" end
	end
	return nil
end

local function Entry(qid)
	local q = Call("GetQuest", qid)
	if type(q) ~= "table" or q.hidden then return nil end
	local title = q.name
	if type(title) ~= "string" or title == "" or ns.IsSecret(title) then return nil end
	local e = L:Ends(qid)
	-- No place to stand is still worth having: the quests that are new in WoW Forever come
	-- with a name and a level and nothing else, and that is enough to search and to plan by.
	local s = e and e.start[1] or {}
	local level = ns.Num(q.questLevel)
	local rl = ns.Num(q.requiredLevel)
	local pre
	for _, field in ipairs({ "preQuestSingle", "preQuestGroup" }) do
		local list = q[field]
		if type(list) == "table" then
			for i = 1, math.min(#list, 6) do
				local id = ns.Num(list[i])
				if id and id > 0 then pre = pre or {} pre[#pre + 1] = id end
			end
		end
	end
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
	-- them finishes it as far as a player is concerned. A copy that this one follows on from
	-- is a real earlier part, not a twin, and is left out.
	local twins
	if s.npcID then
		local also = Call("GetQuestsStartedByNPC", s.npcID)
		if type(also) == "table" then
			for i = 1, math.min(#also, 60) do
				local other = ns.Num(also[i])
				if other and other ~= qid then
					local h = Call("GetQuestHeader", other)
					if type(h) == "table" and h.name == title then
						local follows = false
						for _, need in ipairs(pre or {}) do if need == other then follows = true end end
						if not follows then twins = twins or {} twins[#twins + 1] = other end
					end
				end
			end
		end
	end
	local special = ns.Num(q.specialFlags) or 0
	return { t = title, l = (level and level > 0) and level or nil, rl = (rl and rl > 0) and rl or nil,
		m = s.m, x = s.x, y = s.y, f = e and e.start.side, pre = pre, bar = Barred(q), lib = true,
		shut = shut, twins = twins, again = (special % 2 == 1) or nil }
end

-- The quest the library says comes next in this one's chain, or nil.
function L:NextInChain(questID)
	questID = ns.Num(questID)
	if not questID or not self:Get() then return nil end
	local known = nextCache[questID]
	if known == nil then
		local q = Call("GetQuest", questID)
		known = type(q) == "table" and ns.Num(q.nextQuestInChain) or false
		if known and known <= 0 then known = false end
		nextCache[questID] = known
	end
	return known or nil
end

-- Every quest number the library has a row for, ascending.
function L:QuestIds()
	local ids = Call("GetQuestIds")
	return type(ids) == "table" and ids or nil
end

function L:Layer() return layer end
function L:Count() return layerCount, nameOnly end
function L:Warming() return warming ~= nil end

-- Builds the layer in the background. Safe to call again; it only ever runs once at a time.
function L:Warm(done)
	if warming or not self:Get() then return false end
	local ids = Call("GetQuestIds")
	if type(ids) ~= "table" then return false end
	layer, layerCount, nameOnly = {}, 0, 0
	local run = { i = 1 }
	warming = run
	local function step()
		if warming ~= run then return end
		if InCombatLockdown() then ns.After(2, step) return end
		for _ = 1, WARM_BATCH do
			local qid = ns.Num(ids[run.i])
			if not qid then
				warming = nil
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
		ns.After(WARM_GAP, step)
	end
	step()
	return true
end

ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
	if layerCount == 0 and not warming then ns.After(3, function() L:Warm() end) end
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

function L:StatusLines(questID)
	local lines = {}
	local off = ns.db.questdb.library == false
	local l = self:Get()
	if ns.db.questdb.bundled == false then
		lines[#lines + 1] = "quest library: not in use, along with the rest of the bundled quest data. /nq db bundled on uses it again."
	elseif off then
		lines[#lines + 1] = "quest library: switched off. /nq lib on uses it again."
	elseif not l then
		lines[#lines + 1] = "quest library: not loaded. NeverQuest is using only what it has learned itself."
	else
		lines[#lines + 1] = string.format("quest library: LibQuestDB in use, %d quests placed on the map and %d more known by name and level only%s (data source: %s). It ships with NeverQuest under its own MIT licence; /nq lib off ignores it.",
			layerCount, nameOnly, warming and ", still loading" or "", tostring(Call("GetDataSource") or "?"))
	end
	if l and questID then
		lines[#lines + 1] = "raw answer for quest " .. questID .. ": " .. Show(Call("GetQuest", questID))
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
	end
	return lines
end

ns:AddSlash("lib", function(rest)
	rest = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if rest == "on" or rest == "off" then
		ns.db.questdb.library = (rest == "on")
		L:Reset()
		if rest == "on" then L:Warm() end
		if ns.QuestDB then ns.QuestDB:ClearNearby() end
		ns:SendMessage("QUESTDB_UPDATED")
		ns:SendMessage("MAP_OFFERS_UPDATED")
	end
	for _, line in ipairs(L:StatusLines(tonumber(rest))) do ns.Print(line) end
end, "/nq lib [on | off | <quest number>] - the optional LibQuestDB quest library: whether it is in use, and what it says about a quest")
