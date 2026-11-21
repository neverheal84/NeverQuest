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
	-- Finished, no marker, but the hand-in is known (not just a guess or a whole zone).
	local t = e.turnin
	if not e.dist and e.complete and t and t.m and (t.source == "learned" or t.source == "npc") then
		e.dist = ns.Nav.Distance(t.m, t.x, t.y)
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
	return ns.KillName(text) or text:match("^(.-): %d+/%d+")
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
	return progress, firstOpen, mob, objectives and #objectives or 0
end

function Q:Scan()
	wipe(self.log)
	wipe(self.byID)

	local playerMap = C_Map.GetBestMapForUnit("player")
	local zoneMap = playerMap and ns.Nav.GetZoneMap(playerMap)
	local positions = {}
	local scannedMaps = {}
	if playerMap then scannedMaps[playerMap] = true end
	if zoneMap then scannedMaps[zoneMap] = true end
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
				local count
				e.progress, e.objective, e.mob, count = ObjectiveSummary(qid, complete)
				e.noObjectives = count == 0   -- "find the place" quests: the text is the only guide
				e.logIndex = i
				local link, icon, charges, showWhenComplete = GetQuestLogSpecialItemInfo(i)
				if link and not ns.IsSecret(link) and (not complete or showWhenComplete) then
					e.item = { link = link, icon = icon, charges = ns.Num(charges), id = tonumber(link:match("item:(%d+)")) }
				end
				local p = positions[qid]
				-- Not on the maps around you: ask the game which map the quest points to (for a
				-- finished quest, where it's handed in) and read its marker there.
				if not p and GetQuestUiMapID then
					local qm = ns.Num(ns.SafeCall(GetQuestUiMapID, qid, true))
					if qm and qm ~= 0 and not scannedMaps[qm] then
						scannedMaps[qm] = true
						CollectPositions(qm, positions)
					end
					p = positions[qid]
				end
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
		if ns.QuestSpots then ns.QuestSpots:Apply(e) end   -- hand-checked spots have the last word
		e.turnin = Q:ResolveTurnin(e)
		UpdatePath(e)
	end

	-- Alerts when a quest's objectives become complete.
	for qid in pairs(completeState) do
		if not self.byID[qid] then completeState[qid] = nil end
	end
	for qid, e in pairs(self.byID) do
		if scannedOnce and e.complete and not completeState[qid] then
			-- A quest with nothing to do ("go and talk to...") is finished the moment you take
			-- it. That is not news, and telling you, your party and the recorder that it is
			-- "ready to turn in" as you accept it is noise. A quest you could already finish
			-- when you took it (you were carrying the items) still says so: that one is.
			local justTaken = completeState[qid] == nil
			if not (justTaken and e.noObjectives) then
				ns:SendMessage("QUEST_READY", e)
			end
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
	if ns.QuestDB then ns.Call("questdb record", function() ns.QuestDB:Record(m, out) end) end
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
function Q:NoteForeignRequest() foreignRequest = GetTime() end

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
	-- Nothing new (the game repeats itself a lot, above all during the quest database scan):
	-- keep what we have and spare the guide, tracker and maps a rebuild.
	local parts = { m }
	for _, o in ipairs(list) do
		parts[#parts + 1] = o.questID
		parts[#parts + 1] = type(o.title) == "string" and not ns.IsSecret(o.title) and o.title or "?"
		parts[#parts + 1] = string.format("%.3f,%.3f", ns.Num(o.x) or 0, ns.Num(o.y) or 0)
	end
	local sig = table.concat(parts, "|")
	if sig == self.offerSig and #self.offers == #list then return end
	self.offerSig = sig
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

-- Distances only change when you move, so this does nothing while you stand still: no pass
-- over the log, and no message for the guide, tracker, maps and nameplates to rebuild on.
-- It still looks again every so often, because a few things here go by the clock (a spawn
-- spot you visited comes back onto the tour after a few minutes).
local MOVE_YARDS = 4
local IDLE_REFRESH = 30
local lastPass = { t = -math.huge }

function Q:DistancesStale() lastPass.t = -math.huge end

function Q:UpdateDistances(force)
	local m, x, y = ns.Nav.GetPlayerPosition()
	local now = GetTime()
	if not force and now - lastPass.t < IDLE_REFRESH and m == lastPass.m then
		if not m then return false end
		if ns.Nav.DistanceBetween(lastPass.m, lastPass.x, lastPass.y, m, x, y) < MOVE_YARDS then return false end
	end
	lastPass.m, lastPass.x, lastPass.y, lastPass.t = m, x, y, now
	for _, e in ipairs(self.log) do
		ApplySpawn(e)
		UpdatePath(e)
	end
	for _, o in ipairs(self.offers) do
		o.dist = ns.Nav.Distance(o.m, o.x, o.y)
	end
	ns:SendMessage("DISTANCES_UPDATED")
	return true
end

-- A spot learned while you stand still changes where the nearest one is.
ns:RegisterMessage("SPAWNS_UPDATED", function() Q:DistancesStale() end)

---------------------------------------------------------------------------
-- NPC memory: names of quest givers and turn-in NPCs, learned from your own quest dialogs
-- and shared by all your characters.
---------------------------------------------------------------------------
local lastNPC

-- The NPC (or object) in the quest window. A party member sharing a quest isn't a quest giver.
local function NoteNPC()
	if UnitExists("npc") and UnitIsPlayer("npc") then return nil end
	local name = ns.SafeName("npc")
	if name then lastNPC = { name = name, t = GetTime() } end
	return name
end
local lastDetail, lastComplete   -- { questID, t }: the quest you last read from, or handed to, an NPC

function Q:LastNPC(window)
	if lastNPC and GetTime() - lastNPC.t <= (window or 30) then return lastNPC.name end
end

function Q:GiverName(questID) return questID and ns.db.npcs.giver[questID] or nil end
function Q:TurnInName(questID) return questID and ns.db.npcs.turnin[questID] or nil end

ns:RegisterEvent("QUEST_DETAIL", function()
	local name, questID = NoteNPC(), GetQuestID()
	if name and questID and questID > 0 then
		ns.db.npcs.giver[questID] = name
		lastDetail = { questID = questID, t = GetTime() }
	end
end)
local function NoteTurnIn()
	local name, questID = NoteNPC(), GetQuestID()
	if name and questID and questID > 0 then
		ns.db.npcs.turnin[questID] = name
		lastComplete = { questID = questID, t = GetTime() }
	end
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

-- Spots are only kept when you were actually at that quest's NPC: not for quests shared by a
-- party member, started from an item, or handed in remotely (a pop-up turn-in, a shared
-- completion), where where you stood says nothing about where the NPC is.
local SPOT_WINDOW = 90

-- Did you just take this quest from an NPC yourself, rather than have it shared to you or
-- start it from an item?
function Q:TakenFromNPC(questID)
	return questID ~= nil and lastDetail ~= nil and lastDetail.questID == questID
		and GetTime() - lastDetail.t <= SPOT_WINDOW
end
ns:RegisterEvent("QUEST_ACCEPTED", function(_, questID)
	if questID and lastDetail and lastDetail.questID == questID and GetTime() - lastDetail.t <= SPOT_WINDOW then
		ns.db.npcs.giverAt[questID] = Spot()
	end
	Q:NPCsChanged()
end)
ns:RegisterEvent("QUEST_TURNED_IN", function(_, questID)
	if questID and lastComplete and lastComplete.questID == questID and GetTime() - lastComplete.t <= SPOT_WINDOW then
		ns.db.npcs.turninAt[questID] = Spot()
	end
	Q:NPCsChanged()
	if questID then Q:ForgetText(questID) end
end)

-- Which zone a quest belongs to: its quest log header when that's a zone, else where its
-- objective is. Quest givers use the map they're on.
local headerZone = {}
function Q:ZoneOf(e)
	if not e then return nil end
	-- A finished quest belongs to the zone you hand it in, when that's known.
	if e.complete and e.knownSpot and e.pos and e.pos.zone then return e.pos.zone end
	local t = e.complete and e.turnin
	if t and t.source ~= "giver" then
		if t.zone then return t.zone end
		if t.m then return ns.Nav.MapName(ns.Nav.GetZoneMap(t.m)) end
	end
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
---------------------------------------------------------------------------
-- Where a quest is handed in
--
-- In order: where any of your characters handed it in; the game's own marker; the NPC the
-- quest text names, if you've met them; the zone the text names; and only when nothing says
-- otherwise, where you picked it up. "Bring this to Zargh" when Zargh isn't the quest giver
-- never falls back to the quest giver.
---------------------------------------------------------------------------
local CITIES = { "Stormwind City", "Stormwind", "Ironforge", "Darnassus", "Orgrimmar", "Thunder Bluff", "Undercity" }
local zoneNames
local function ZoneNames()
	if zoneNames then return zoneNames end
	zoneNames = {}
	for name in pairs((ns.Profiles and ns.Profiles.ZONES) or {}) do table.insert(zoneNames, name) end
	for _, c in ipairs(CITIES) do table.insert(zoneNames, c) end
	table.sort(zoneNames, function(a, b) return #a > #b end)
	return zoneNames
end

-- The last zone a text names ("...to Gryan Stoutmantle in Westfall.").
function Q.ZoneInText(text)
	if type(text) ~= "string" or ns.IsSecret(text) then return nil end
	local lower = text:lower()
	local best, bestAt
	for _, name in ipairs(ZoneNames()) do
		local l, from = name:lower(), 1
		while true do
			local i = lower:find(l, from, true)
			if not i then break end
			local before, after = lower:sub(i - 1, i - 1), lower:sub(i + #l, i + #l)
			if not before:match("%a") and not after:match("%a") and (not bestAt or i > bestAt) then best, bestAt = name, i end
			from = i + 1
		end
	end
	if best == "Stormwind" then best = "Stormwind City" end
	return best
end

local NPC_PATTERNS = {
	"[Rr]eturn to (.-) at ", "[Rr]eturn to (.-) in ", "[Rr]eturn to (.-)[%.!,]",
	"[Rr]eport to (.-) at ", "[Rr]eport to (.-) in ", "[Rr]eport to (.-)[%.!,]",
	"[Ss]peak with (.-) at ", "[Ss]peak with (.-) in ", "[Ss]peak with (.-)[%.!,]",
	"[Ss]peak to (.-) at ", "[Ss]peak to (.-) in ", "[Tt]alk to (.-) at ", "[Tt]alk to (.-) in ", "[Tt]alk to (.-)[%.!,]",
	" to (%u[^%.,!]-) at ", " to (%u[^%.,!]-) in ", " to (%u[^%.,!]-)[%.!]",
}

-- The NPC a text sends you to, if it names one.
function Q.NPCInText(text)
	if type(text) ~= "string" or ns.IsSecret(text) then return nil end
	for _, pat in ipairs(NPC_PATTERNS) do
		local name = text:match(pat)
		if name then
			name = name:gsub("^%s+", ""):gsub("%s+$", "")
			local words = select(2, name:gsub("%S+", ""))
			if name:match("^%u") and not name:find("%d") and words <= 5 and #name <= 40
				and Q.ZoneInText(name) ~= name and not name:match("^The %u%l+$") then
				return name
			end
		end
	end
end

-- Quest texts don't change: read them once.
local textInfo = {}
local function TextInfo(e)
	local qid = e.questID
	local info = textInfo[qid]
	if not info then
		info = {}
		local ok, _, objectives = pcall(GetQuestLogQuestText, e.logIndex)
		if ok and type(objectives) == "string" and not ns.IsSecret(objectives) and objectives ~= "" then
			info.objNpc, info.objZone = Q.NPCInText(objectives), Q.ZoneInText(objectives)
			textInfo[qid] = info   -- kept only once the text has loaded; right after accepting it may not have
		end
	end
	if e.complete and info.doneRead == nil and GetQuestLogCompletionText then
		local ok, done = pcall(GetQuestLogCompletionText, e.logIndex)
		info.doneRead = true
		if ok and type(done) == "string" and not ns.IsSecret(done) then
			info.doneNpc, info.doneZone = Q.NPCInText(done), Q.ZoneInText(done)
		end
	end
	return info
end
Q.TextInfo = TextInfo
function Q:ForgetText(questID) textInfo[questID] = nil end

-- NPCs you've met, from quests you picked up or handed in: name -> where they stand.
local npcIndex, npcDirty = nil, true
local function NPCSpot(name)
	if npcDirty or not npcIndex then
		npcIndex = {}
		local npcs = ns.db.npcs
		for qid, n in pairs(npcs.giver) do
			local at = npcs.giverAt[qid]
			if at and type(n) == "string" then npcIndex[n:lower()] = at end
		end
		for qid, n in pairs(npcs.turnin) do
			local at = npcs.turninAt[qid]
			if at and type(n) == "string" then npcIndex[n:lower()] = at end
		end
		npcDirty = false
	end
	local at = npcIndex[name:lower()]
	if at then return at end
	if ns.Spawns and ns.Spawns.NpcSpot then
		local m, x, y = ns.Spawns:NpcSpot(name)
		if m then return { m = m, x = x, y = y } end
	end
end
function Q:NPCsChanged() npcDirty = true end

function Q:ResolveTurnin(e)
	local qid = e.questID
	local npcs = ns.db.npcs
	if e.complete and e.pos and not e.pos.waypoint then
		return { m = e.pos.m, x = e.pos.x, y = e.pos.y, source = e.knownSpot and "known" or "game", npc = npcs.turnin[qid] }
	end
	local info = TextInfo(e)
	local npc = (e.complete and info.doneNpc) or info.objNpc
	local zone = (e.complete and info.doneZone) or info.objZone
	local function InZone(spot)
		if not zone then return true end
		local z = ns.Nav.MapName(ns.Nav.GetZoneMap(spot.m))
		return not z or (ns.Profiles and ns.Profiles.SameZone(zone, z)) or z == zone
	end
	-- Where you handed it in before, unless the quest text says it's somewhere else (a spot
	-- saved by an older version from a remote turn-in).
	local at = npcs.turninAt[qid]
	if at and InZone(at) then return { m = at.m, x = at.x, y = at.y, source = "learned", npc = npcs.turnin[qid] } end
	if npc then
		local spot = NPCSpot(npc)
		if spot and InZone(spot) then return { m = spot.m, x = spot.x, y = spot.y, source = "npc", npc = npc } end
	end
	local giver, giverName = npcs.giverAt[qid], npcs.giver[qid]
	local sameNPC = npc and giverName and npc:lower() == giverName:lower()
	if giver then
		local giverZone = ns.Nav.MapName(ns.Nav.GetZoneMap(giver.m))
		local sameZone = not zone or (ns.Profiles and ns.Profiles.SameZone(zone, giverZone))
		if sameNPC then return { m = giver.m, x = giver.x, y = giver.y, source = "npc", npc = npc } end
		if not npc and sameZone and not e.noObjectives then
			return { m = giver.m, x = giver.x, y = giver.y, source = "giver", npc = giverName }
		end
	end
	if zone then
		local m = ns.Profiles and ns.Profiles.ZoneID(zone)
		if m then return { m = m, x = 0.5, y = 0.5, source = "zone", zone = zone, npc = npc } end
	end
	if npc then return { source = "unknown", npc = npc } end
end

-- Where a quest will be handed in: a spot (or nil) and whether it's only a guess.
function Q:TurnInSpot(questID)
	local e = self.byID[questID]
	if e then
		-- In your log: ResolveTurnin already weighed everything, including "nowhere known".
		local t = e.turnin
		if t and t.m then return t, t.source == "giver" or t.source == "zone" end
		return nil
	end
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
	-- The world map only needs redrawing while it's open.
	if WorldMapFrame and WorldMapFrame:IsShown() then
		ns.Debounce("mapoffers", 0.5, function() ns:SendMessage("MAP_OFFERS_UPDATED") end)
	end
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

-- Looked at every 2 seconds, and redone only if you have moved (see UpdateDistances);
-- available quests are re-requested every 30.
local tick = 0
ns.Ticker(2, "Quest distances", function()
	if not ns.ready then return end
	tick = tick + 1
	Q:UpdateDistances()
	if tick % 15 == 0 then Q:RequestOffers() end
end)
