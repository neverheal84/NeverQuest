-- NeverQuest Quests: quest log scanning, positions, XP values, nearby quest givers and completion alerts,
-- built on the quest data the Forever client already provides.

local ADDON, ns = ...
local Q = {}
ns.Quests = Q

Q.log, Q.byID, Q.offers = {}, {}, {}
local completeState = {}
local scannedOnce = false
local requestedLoad = {}

local function Bool(v) return v and true or false end

-- Distance along the route: to the game's next waypoint (cave entrance, tunnel, zone exit...)
-- and from there to the objective, instead of a straight line through walls.
local function UpdatePath(e)
	local leg = ns.Route.QuestLeg(e.questID)
	e.leg = leg
	-- Quests known only by their routing waypoint move on as the game advances the route.
	if leg and e.pos and e.pos.waypoint then
		e.pos = { m = leg.m, x = leg.x, y = leg.y, waypoint = true }
	end
	if leg then
		local d1 = ns.Nav.Distance(leg.m, leg.x, leg.y)
		local d2 = 0
		if e.pos and not e.pos.waypoint then
			d2 = ns.Nav.DistanceBetween(leg.m, leg.x, leg.y, e.pos.m, e.pos.x, e.pos.y)
			if d2 == math.huge then d2 = 0 end
		end
		e.dist = d1 and (d1 + d2) or (e.pos and ns.Nav.Distance(e.pos.m, e.pos.x, e.pos.y))
	elseif e.pos then
		e.dist = ns.Nav.Distance(e.pos.m, e.pos.x, e.pos.y)
	else
		e.dist = nil
	end
end

-- Known spawn spots (Spawns.lua) for quests still in progress: the arrow goes to whichever
-- is closer, the game's quest area or the nearest spot where the mob or objective has
-- actually been seen. The game's own position is kept in e.nativePos.
-- The game's spot for an unfinished quest that sits right on its quest giver or turn-in NPC
-- isn't where the objective is (some quests only have a marker for the NPC). Flag it so the
-- route doesn't send you to the NPC before the work is done.
local NPC_YARDS = 35
local function MarkNPCSpot(e)
	local n = e.nativePos
	if not n or e.complete or e.failed then return end
	local npcs = ns.db.npcs
	for _, spot in ipairs({ npcs.turninAt[e.questID] or false, npcs.giverAt[e.questID] or false }) do
		if spot and spot.m and ns.Nav.DistanceBetween(n.m, n.x, n.y, spot.m, spot.x, spot.y) <= NPC_YARDS then
			n.npc = true
			return
		end
	end
end
Q.MarkNPCSpot = MarkNPCSpot

local function ApplySpawn(e)
	if e.nativePos == nil then e.nativePos = e.pos or false end
	local native = e.nativePos or nil
	e.pos, e.spawn, e.dropMob = native, nil, nil
	if e.complete or e.failed or not ns.Spawns then return end
	local sp = ns.Spawns:NearestFor(e.questID)
	if not sp then return end
	e.spawn = sp
	if not e.mob and sp.mob then e.dropMob = sp.mob end
	local nd = native and not native.waypoint and ns.Nav.Distance(native.m, native.x, native.y)
	if not native or native.waypoint or native.npc or not nd or (sp.dist and sp.dist < nd) then
		e.pos = { m = sp.m, x = sp.x, y = sp.y, spawn = true, label = sp.label }
	end
end

-- Positions of quest objectives/turn-ins drawn on a map.
local function CollectPositions(mapID, out)
	if not mapID then return end
	local list = C_QuestLog.GetQuestsOnMap(mapID)
	if not list then return end
	for _, info in ipairs(list) do
		local x, y = ns.Num(info.x), ns.Num(info.y)
		if info.questID and x and y and not out[info.questID] then
			out[info.questID] = { m = mapID, x = x, y = y }
		end
	end
end

-- Mob name from a kill objective like "Diseased Timber Wolf slain: 3/8".
local function MobName(o)
	local text = o.text
	if not text or o.type ~= "monster" then return nil end
	return text:match("^(.-) slain: %d+/%d+") or text:match("^%d+/%d+ (.-) slain") or text:match("^(.-): %d+/%d+")
end

local function ObjectiveSummary(questID, complete)
	local objectives = C_QuestLog.GetQuestObjectives(questID)
	local done, total, firstOpen, mob = 0, 0, nil, nil
	if objectives then
		for _, o in ipairs(objectives) do
			local need, have = ns.Num(o.numRequired), ns.Num(o.numFulfilled)
			if need and need > 0 then
				done, total = done + math.min(have or 0, need), total + need
			else
				total = total + 1
				if o.finished then done = done + 1 end
			end
			if not o.finished and not firstOpen and o.text and o.text ~= "" then firstOpen = o.text end
			if not o.finished and not mob then mob = MobName(o) end
		end
	end
	local progress = total > 0 and done / total or (complete and 1 or 0)
	return progress, firstOpen, mob
end

function Q:Scan()
	wipe(self.log)
	wipe(self.byID)

	local playerMap = C_Map.GetBestMapForUnit("player")
	local zoneMap = playerMap and ns.Nav.GetZoneMap(playerMap)
	local positions = {}
	CollectPositions(playerMap, positions)
	if zoneMap ~= playerMap then CollectPositions(zoneMap, positions) end

	local header
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info then
			if info.isHeader then
				header = info.title
			elseif not info.isHidden and info.questID and info.questID > 0 then
				local qid = info.questID
				local complete = Bool(C_QuestLog.IsComplete(qid) or C_QuestLog.ReadyForTurnIn(qid))
				local e = {
					questID = qid,
					title = info.title or C_QuestLog.GetTitleForQuestID(qid) or ("Quest " .. qid),
					level = info.difficultyLevel or info.level,
					zone = header,
					complete = complete,
					failed = Bool(C_QuestLog.IsFailed(qid)),
					trivial = Bool(C_QuestLog.IsQuestTrivial(qid)),
					elite = Bool(C_QuestLog.IsEliteQuest and C_QuestLog.IsEliteQuest(qid)),
					group = (info.suggestedGroup or 0) > 1 and info.suggestedGroup or nil,
					xp = ns.Num(GetQuestLogRewardXP(qid)),
				}
				e.progress, e.objective, e.mob = ObjectiveSummary(qid, complete)
				e.logIndex = i
				local link, icon, charges, showWhenComplete = GetQuestLogSpecialItemInfo(i)
				if link and not ns.IsSecret(link) and (not complete or showWhenComplete) then
					e.item = { link = link, icon = icon, charges = ns.Num(charges), id = tonumber(link:match("item:(%d+)")) }
				end
				local p = positions[qid]
				if not p then
					local m, x, y = C_QuestLog.GetNextWaypoint(qid)
					if m and ns.Num(x) and ns.Num(y) then p = { m = m, x = x, y = y, waypoint = true } end
				end
				e.pos, e.nativePos = p, p or false
				table.insert(self.log, e)
				self.byID[qid] = e
			end
		end
	end

	-- Known spawn spots need the whole log, so paths are worked out once it's built.
	if ns.Spawns then ns.Spawns:Invalidate() end
	for _, e in ipairs(self.log) do
		MarkNPCSpot(e)
		ApplySpawn(e)
		UpdatePath(e)
	end

	-- Alerts when a quest's objectives become complete.
	for qid in pairs(completeState) do
		if not self.byID[qid] then completeState[qid] = nil end
	end
	for qid, e in pairs(self.byID) do
		if scannedOnce and e.complete and not completeState[qid] then
			ns:SendMessage("QUEST_READY", e)
		end
		completeState[qid] = e.complete
	end
	scannedOnce = true
	ns:SendMessage("QUESTS_UPDATED")
end

function Q:RequestScan()
	ns.Debounce("questscan", 0.25, function() Q:Scan() end)
end

---------------------------------------------------------------------------
-- Available quests near you (the same data that puts "!" on the world map)
---------------------------------------------------------------------------
-- How hard a quest is for you, as the game rates it: 0 gray (trivial), 1 green, 2 yellow,
-- 3 orange, 4 red (too high). Falls back to comparing levels.
Q.DIFFICULTY_NAMES = { [0] = "gray, low XP", [1] = "green", [2] = "yellow", [3] = "orange, tough", [4] = "red, too high" }

function Q:Difficulty(questID, level, trivial)
	if trivial then return 0 end
	local d = ns.SafeCall(C_PlayerInfo and C_PlayerInfo.GetContentDifficultyQuestForPlayer, questID)
	if type(d) == "number" and d >= 0 and d <= 4 then return d end
	local mine = UnitLevel("player") or 1
	if not level or level <= 0 then return 2 end
	local diff = level - mine
	if diff >= 5 then return 4 end
	if diff >= 3 then return 3 end
	if diff >= -2 then return 2 end
	return 1
end

-- Quest givers on one map: the same data that puts "!" on the world map.
local function CollectOffers(m)
	local out, seen = {}, {}
	local function Add(info)
		if not info or not info.questID or seen[info.questID] then return end
		local qid = info.questID
		local x, y = ns.Num(info.x), ns.Num(info.y)
		if not x or not y or (x == 0 and y == 0) then return end
		if C_QuestLog.IsOnQuest(qid) or C_QuestLog.IsQuestFlaggedCompleted(qid) then return end
		seen[qid] = true
		local o = {
			questID = qid,
			title = info.questName or C_QuestLog.GetTitleForQuestID(qid) or ("Quest " .. qid),
			m = m, x = x, y = y,
			trivial = Bool(info.isHidden or C_QuestLog.IsQuestTrivial(qid)),
			daily = Bool(info.isDaily),
			important = Bool(info.isImportant or info.isCampaign),
			campaign = Bool(info.isCampaign),
			legendary = Bool(info.isLegendary),
			chainStart = Bool(info.isQuestStart),
			questLine = info.questLineName,
		}
		local level = ns.Num(C_QuestLog.GetQuestDifficultyLevel(qid))
		if level and level > 0 then o.level = level end
		o.difficulty = Q:Difficulty(qid, o.level, o.trivial)
		if o.difficulty == 0 then o.trivial = true end
		local xp = ns.Num(GetQuestLogRewardXP(qid))
		if xp and xp > 0 then
			o.xp = xp
		elseif not requestedLoad[qid] then
			requestedLoad[qid] = true
			C_QuestLog.RequestLoadQuestByID(qid)
		end
		o.dist = ns.Nav.Distance(o.m, o.x, o.y)
		table.insert(out, o)
	end
	for _, info in ipairs(C_QuestLine.GetAvailableQuestLines(m) or {}) do Add(info) end
	for _, qid in ipairs(C_QuestLine.GetForceVisibleQuests(m) or {}) do
		Add(C_QuestLine.GetQuestLineInfo(qid, m))
	end
	return out
end

-- Which quest givers to show. Level-appropriate (green to orange) by default; gray and red
-- are settings. forGuide uses the guide's own "include gray quests" setting.
function Q:OfferShown(o, forGuide)
	local g = ns.db.givers
	if o.trivial or o.difficulty == 0 then
		if forGuide then
			if not ns.db.guide.showGray then return false end
		elseif not g.gray then
			return false
		end
	end
	if o.difficulty == 4 and not g.red then return false end
	if o.daily and not g.dailies then return false end
	return true
end

function Q:RequestOffers()
	local m = C_Map.GetBestMapForUnit("player")
	m = m and ns.Nav.GetZoneMap(m)
	if not m then return end
	self.offerMap = m
	C_QuestLine.RequestQuestLinesForMap(m)
	self:BuildOffers()
end

local foreignRequest = 0   -- when another map's quest givers were last asked for

function Q:BuildOffers()
	local m = self.offerMap
	if not m then
		wipe(self.offers)
		return
	end
	local list = CollectOffers(m)
	-- While the world map asks about another zone, the game may briefly have nothing for
	-- yours; keep what we had instead of emptying the guide.
	if #list == 0 and #self.offers > 0 and self.offers[1].m == m and GetTime() - foreignRequest < 60 then
		return
	end
	wipe(self.offers)
	for _, o in ipairs(list) do table.insert(self.offers, o) end
	ns:SendMessage("OFFERS_UPDATED")
end

-- Quest givers on any map you look at on the world map. The game is asked once per map;
-- QUESTLINE_UPDATE says when its answer is in.
local mapOffers = {}

function Q:OffersForMap(m)
	if not m then return {} end
	if m == self.offerMap then return self.offers end
	local c = mapOffers[m]
	if not c then
		foreignRequest = GetTime()
		C_QuestLine.RequestQuestLinesForMap(m)
		c = { list = CollectOffers(m), t = GetTime() }
		mapOffers[m] = c
	elseif GetTime() - c.t > 30 then
		c.list, c.t = CollectOffers(m), GetTime()
	end
	return c.list
end

function Q:ForgetMapOffers()
	wipe(mapOffers)
end

function Q:UpdateDistances()
	for _, e in ipairs(self.log) do
		ApplySpawn(e)
		UpdatePath(e)
	end
	for _, o in ipairs(self.offers) do
		o.dist = ns.Nav.Distance(o.m, o.x, o.y)
	end
	ns:SendMessage("DISTANCES_UPDATED")
end

---------------------------------------------------------------------------
-- NPC memory: names of quest givers and turn-in NPCs, learned from your own quest dialogs
-- and shared by all your characters.
---------------------------------------------------------------------------
local lastNPC

local function NoteNPC()
	local name = ns.SafeName("npc")
	if name then lastNPC = { name = name, t = GetTime() } end
	return name
end

function Q:LastNPC(window)
	if lastNPC and GetTime() - lastNPC.t <= (window or 30) then return lastNPC.name end
end

function Q:GiverName(questID) return questID and ns.db.npcs.giver[questID] or nil end
function Q:TurnInName(questID) return questID and ns.db.npcs.turnin[questID] or nil end

ns:RegisterEvent("QUEST_DETAIL", function()
	local name, questID = NoteNPC(), GetQuestID()
	if name and questID and questID > 0 then ns.db.npcs.giver[questID] = name end
end)
local function NoteTurnIn()
	local name, questID = NoteNPC(), GetQuestID()
	if name and questID and questID > 0 then ns.db.npcs.turnin[questID] = name end
end
ns:RegisterEvent("QUEST_PROGRESS", NoteTurnIn)
ns:RegisterEvent("QUEST_COMPLETE", NoteTurnIn)

-- Where quests are picked up and handed in (where you stood, next to the NPC). The route
-- planner uses these to guess where a quest you're still working on will be turned in:
-- the turn-in spot if any of your characters has handed it in, else where you got it.
local function Spot()
	if IsInInstance and IsInInstance() then return nil end
	local m, x, y = ns.Nav.GetPlayerPosition()
	if not m then return nil end
	return { m = m, x = math.floor(x * 10000 + 0.5) / 10000, y = math.floor(y * 10000 + 0.5) / 10000 }
end

ns:RegisterEvent("QUEST_ACCEPTED", function(_, questID)
	if questID and Q:LastNPC(10) then ns.db.npcs.giverAt[questID] = Spot() end
end)
ns:RegisterEvent("QUEST_TURNED_IN", function(_, questID)
	if questID then ns.db.npcs.turninAt[questID] = Spot() end
end)

-- Which zone a quest belongs to: its quest log header when that's a zone, else where its
-- objective is. Quest givers use the map they're on.
local headerZone = {}
function Q:ZoneOf(e)
	if not e then return nil end
	if e.zone then
		local known = headerZone[e.zone]
		if known == nil then
			known = (ns.Profiles and ns.Profiles.ZONES[e.zone] ~= nil) or ns.Nav.FindZone(e.zone) ~= nil
			headerZone[e.zone] = known
		end
		if known then return e.zone end
	end
	local p = e.nativePos or e.pos
	if p and p ~= false and not p.waypoint and p.m then return ns.Nav.MapName(ns.Nav.GetZoneMap(p.m)) end
	if e.m then return ns.Nav.MapName(ns.Nav.GetZoneMap(e.m)) end
end

-- Useful quests in a zone: ones to do (not gray), to hand in, or to pick up.
function Q:ZoneWork(name)
	if not name then return 0 end
	local same = ns.Profiles and ns.Profiles.SameZone or function(a, b) return a == b end
	local n = 0
	for _, e in ipairs(self.log) do
		if not e.failed and (e.complete or not e.trivial) and same(self:ZoneOf(e), name) then n = n + 1 end
	end
	for _, o in ipairs(self.offers) do
		if not o.trivial and o.difficulty ~= 4 and same(self:ZoneOf(o), name) then n = n + 1 end
	end
	return n
end

-- Best guess at where a quest is handed in, or nil.
function Q:TurnInSpot(questID)
	local at = ns.db.npcs.turninAt[questID]
	if at then return at, false end
	at = ns.db.npcs.giverAt[questID]
	if at then return at, true end
end
ns:RegisterEvent("GOSSIP_SHOW", NoteNPC)
ns:RegisterEvent("QUEST_GREETING", NoteNPC)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "QUEST_WATCH_UPDATE", "PLAYER_LEVEL_UP",
	"WAYPOINT_UPDATE", "QUEST_POI_UPDATE", "SUPER_TRACKING_PATH_UPDATED", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }) do
	ns:RegisterEvent(event, function() Q:RequestScan() end)
end

ns:RegisterEvent("UNIT_QUEST_LOG_CHANGED", function(_, unit)
	if unit == "player" then Q:RequestScan() end
end)

ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
	ns.After(1, function()
		Q:Scan()
		Q:RequestOffers()
	end)
end)

ns:RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
	Q:RequestScan()
	ns.Debounce("offers", 0.5, function() Q:RequestOffers() end)
end)

ns:RegisterEvent("QUESTLINE_UPDATE", function(_, requestRequired)
	-- Fresh answers for the maps you've looked at, too.
	for m, c in pairs(mapOffers) do c.t = 0 end
	ns.Debounce("mapoffers", 0.5, function() ns:SendMessage("MAP_OFFERS_UPDATED") end)
	if requestRequired then
		ns.Debounce("offers", 0.5, function() Q:RequestOffers() end)
	else
		ns.Debounce("offerbuild", 0.3, function() Q:BuildOffers() end)
	end
end)

ns:RegisterEvent("QUEST_DATA_LOAD_RESULT", function(_, questID)
	if requestedLoad[questID] then
		ns.Debounce("offerbuild", 0.5, function() Q:BuildOffers() end)
	end
end)

-- After a turn-in or pickup, the list of available quests changes.
ns:RegisterEvent("QUEST_TURNED_IN", function()
	Q:ForgetMapOffers()
	ns.Debounce("offers", 1, function() Q:RequestOffers() end)
end)
ns:RegisterEvent("QUEST_ACCEPTED", function()
	Q:ForgetMapOffers()
	ns.Debounce("offerbuild", 0.5, function() Q:BuildOffers() end)
end)
-- Level changes move quests between gray, green, yellow, orange and red.
ns:RegisterEvent("PLAYER_LEVEL_UP", function()
	Q:ForgetMapOffers()
	ns.Debounce("offerbuild", 1, function() Q:BuildOffers() end)
end)

ns:RegisterMessage("QUEST_READY", function(_, e)
	if ns.db.alerts.complete then
		ns.Alert("Ready to turn in: " .. e.title, 0.4, 1, 0.4)
		ns.PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE)
	end
	if ns.db.alerts.trackTurnin and e.pos and not ns.db.guide.autoTrack then
		ns.Nav:SetGuideTarget({ key = "turnin:" .. e.questID, m = e.pos.m, x = e.pos.x, y = e.pos.y, title = "Turn in: " .. e.title, questID = e.questID })
	end
end)

-- Distances refresh every 2 seconds; available quests are re-requested every 30.
local tick = 0
ns.Ticker(2, "Quest distances", function()
	if not ns.ready then return end
	tick = tick + 1
	Q:UpdateDistances()
	if tick % 15 == 0 then Q:RequestOffers() end
end)
