-- NeverQuest Planner: puts your next stops (objectives, turn-ins, quest pickups) into one route
-- that wastes as little travel as possible while keeping XP per hour high.
--
-- How a plan is made:
--   1. Every quest becomes a bundle: its objective area, then where it's handed in (known
--      turn-in spot, or where you picked it up, which is usually the same NPC). Finished
--      quests are just the turn-in. Quest givers nearby are cheap one-stop bundles.
--   2. Each bundle is worth its XP plus part of the XP of the quests it opens up (Chains.lua)
--      and costs the extra travel to fit it into the route plus the time to do it. Pace.lua
--      watches you play: once it knows them, the time is your own seconds per kill and per
--      item, and the XP includes what the kills themselves give you.
--   3. Bundles go in one at a time, best XP per second first, each at the place in the route
--      where it adds the least travel (the objective always before its turn-in). Quests worth
--      much less than the best quest on offer are left out ("not on this route"). Finished
--      quests handed in near each other are judged as one trip: alone, none of them pays for
--      the walk across the map, while the pile of them sitting in one town plainly does.
--   4. Quests right on the way that are still worth their time go in too, even past the half
--      hour the plan looks ahead: if the route takes you there, you do them while you're there.
--   5. The order is then tightened: stretches reversed, and single stops or runs of up to
--      three moved, wherever that shortens the trip (a turn-in never before its objective).
--   6. Finished quests handed in right where you stand go first, and so do quests worth taking
--      that are given there, so you don't walk out of town and come back for them (the walking
--      is the same either way; the XP isn't, their follow-ups open up now, and a quest taken
--      now can be done on this trip). Not while you're working on an objective close by. And
--      when the route passes a turn-in or a quest giver before it comes back for it, that's done
--      the first time by.
--   Distances are walks over real ground where PathData.lua covers the zone (see D below).
--   7. The current first stop is kept unless that costs 20 seconds or more over the same stops in
--      a better order, and a stop you were sent away from isn't gone back to until your quests
--      change, so the arrow doesn't flip back and forth (see Make).

local ADDON, ns = ...
local P = {}
ns.Planner = P

local sqrt, max, min = math.sqrt, math.max, math.min

local DETOUR = 1.25         -- real paths are longer than straight lines
local HORIZON = 1800        -- plan about 30 minutes ahead
local MIN_SHARE = { optimized = 0.35, zone = 0.15, none = 0.3 }  -- leave out quests under this share of the best quest's XP per second
local BREADCRUMB = 1.3      -- quests handed in at your next zone, near the end of a leg
local CHAIN_STARTED = 1.15  -- follow-ups of quests you've done: finish chains you've started
local SWITCH_SECONDS = 20   -- the first stop changes when keeping it first would cost this many seconds more for the same stops
local KEEP_MARGIN = 1.15    -- ...or, when the new plan has dropped it altogether, when that plan is 15% better
local WORKING_YARDS = 60    -- this close to the current objective, you're working on it: keep it
local REPLAN_MOVE = 120     -- yards moved before planning again
local REPLAN_EVERY = 8      -- seconds between plans
local MAX_STOPS = 30
local FLIGHT_MIN = 1200      -- yards apart before a flight is thought of (Route.lua's MIN_FLIGHT_TRIP)
local FLIGHT_GAIN = 0.75     -- ...and it has to take under three quarters of the walk
local FLY_SPEED, FLY_OVERHEAD = 30, 25  -- yards a second in the air; seconds to talk, take off and land
local NEAR_PICKUP = 100      -- yards: a quest you may do, given this close to you or to the last stop here, is picked up whatever it's worth
local NEAR_ROUTE = 60        -- ...and one this small a detour off the route, likewise
local LOG_ROOM = 5           -- free quest log slots kept: none of those "may do" pickups once it's this full
local WALK_STOPS = 24        -- the nearest stops whose walking distances are asked for (Paths.lua keeps that many)
local WALK_READY = 0.9       -- walking distances are used once this share of them is known
local TOO_HIGH = 3          -- quests more than this many levels above you wait until you're within it (finished ones are handed in whatever their level)
local ONTHEWAY = 150        -- yards of extra walking: a quest this close to the route is done on the same visit
local ONTHEWAY_BAR = 0.5    -- ...when it's worth at least half the usual bar for its time
local HERE = 200            -- yards: finished quests handed in this close to you (or to the last one) are handed in first
local HERE_MAX = 500        -- ...as long as they're within this many yards of where you stand
local HERE_TOWN = 350       -- in a town or city (resting), where the NPCs are further apart
local HERE_TOWN_MAX = 900
local NEAR_WORK = 150       -- an objective still to do this close, and closer than any turn-in: you finish it first
local EARLY = 25            -- yards: a turn-in moves earlier in the route when that costs no more walking than this
local TURNIN_RUN = 600      -- yards: finished quests handed in this close to each other are one trip
local BANKED_PER_LEVEL = 0.06  -- finished quests lose XP as you out-level them, so they move up the list
local BANKED_MAX = 1.5
local STOP_WORK = 8         -- seconds to talk to an NPC
local PICKUP_SHARE = 0.4    -- a pickup is worth part of its quest's XP: the rest comes later
local AHEAD_SHARE = 0.8     -- a pickup in the zone you're heading to, planned before you get there
local AHEAD_MAX = 6         -- of those, at most this many per zone, nearest first
local DUNGEON_SHARE = 1.0   -- a dungeon quest, or the pre-quest that opens it: worth the dungeon quest's XP
local PREP_BOOST = 2.0      -- and doubled, so they're done before the dungeon (Dungeons.lua)
local GOBACK = 6            -- a quest you chose to go back for from the missed list (Advisor.lua): next, unless something is right beside you
-- Seconds per objective unit, by objective type, until Pace.lua has measured yours.
local WORK = { monster = 22, item = 30, object = 15, event = 30, log = 20, progressbar = 150 }

P.plan = nil
P.dirty = true

---------------------------------------------------------------------------
-- Positions in continent yards, so distances are plain math
---------------------------------------------------------------------------
local sizeCache = {}

local function Locate(m, x, y)
	if not m or not x or not y then return nil end
	local cont = ns.Nav.GetContinentMap(m)
	if not cont then return nil end
	local cx, cy = ns.Nav.TranslatePoint(m, x, y, cont)
	if not cx or not cy then return nil end
	local size = sizeCache[cont]
	if not size then
		local w, h = C_Map.GetMapWorldSize(cont)
		size = { ns.Num(w) or 0, ns.Num(h) or 0 }
		sizeCache[cont] = size
	end
	if size[1] <= 0 or size[2] <= 0 then return nil end
	return cont, cx * size[1], cy * size[2]
end

-- Yards between two stops (or you and a stop). Where Paths.lua knows the walk over real ground
-- (PathData.lua: cliffs, water, the way round a mountain), that counts when it's longer than the
-- straight line's usual allowance; otherwise the straight line, as ever.
--
-- 1.28.5: and where two spots are far apart and there are flight masters you know near both
-- (Route.lua remembers the ones your flight map has shown you can fly to), the trip counts as
-- walk, fly, walk, by the same sums the arrow uses before it says "Fly from X to Y". So a stop
-- across the continent by a flight path you have is nearer than one half as far with no way but
-- your feet. flights: your flight masters on this continent, in continent yards (Make sets it).
local walkOK = false
local flights, flightSpeed
local function NearNode(s)
	if s.fnFor ~= flights then
		local best, bestD
		for _, n in ipairs(flights) do
			local dx, dy = s.cx - n.cx, s.cy - n.cy
			local d = dx * dx + dy * dy
			if not bestD or d < bestD then best, bestD = n, d end
		end
		s.fnFor, s.fn, s.fd = flights, best, bestD and sqrt(bestD) or nil
	end
	return s.fn, s.fd
end
local function D(a, b)
	local dx, dy = a.cx - b.cx, a.cy - b.cy
	local d = sqrt(dx * dx + dy * dy)
	local fly
	if flights and d >= FLIGHT_MIN then
		local na, da = NearNode(a)
		local nb, db = NearNode(b)
		if na and nb and na ~= nb then
			local hx, hy = na.cx - nb.cx, na.cy - nb.cy
			-- (in yards of walking: the planner turns yards into seconds with DETOUR / speed)
			fly = da + db + (FLY_OVERHEAD + sqrt(hx * hx + hy * hy) / FLY_SPEED) * flightSpeed / DETOUR
			if fly >= d * FLIGHT_GAIN then fly = nil end
		end
	end
	if walkOK and a.m and a.m == b.m and a.x and b.x then
		if b.key == "start" then a, b = b, a end
		local walk = ns.Paths:Yards(a.m, a.x, a.y, b.x, b.y)
		if walk and walk / DETOUR > d then d = walk / DETOUR end
	end
	if fly and fly < d then return fly end
	return d
end
P._D = D

---------------------------------------------------------------------------
-- Bundles
---------------------------------------------------------------------------
local function WorkFor(e)
	local t = 0
	for _, o in ipairs(C_QuestLog.GetQuestObjectives(e.questID) or {}) do
		if not o.finished then
			local need, have = ns.Num(o.numRequired) or 0, ns.Num(o.numFulfilled) or 0
			local per = (ns.Pace and ns.Pace:Secs(o.type)) or WORK[o.type] or 25
			if o.type == "progressbar" then
				t = t + per * max(0.1, 1 - (e.progress or 0))
			elseif need > 0 then
				t = t + per * max(1, need - have)
			else
				t = t + per
			end
		end
	end
	if t <= 0 then t = 30 end
	-- Elite and group quests are slow and risky alone; in a group they're ordinary quests.
	if (e.elite or e.group) and not IsInGroup() then t = t * 1.6 end
	-- A quest above your level takes longer: tougher mobs, more deaths.
	local over = (ns.Num(e.level) or 0) - (UnitLevel("player") or 1)
	if over > 0 then t = t * (1 + 0.15 * over) end
	return t
end

-- Too far above you to send you there yet: more than TOO_HIGH levels over your level.
function P.TooHigh(level)
	level = ns.Num(level)
	return level ~= nil and level - (UnitLevel("player") or 1) > TOO_HIGH
end
P.TOO_HIGH = TOO_HIGH

local function Stop(kind, questID, e, pos, cont, work, extra)
	if not pos then return nil end
	local c, cx, cy = Locate(pos.m, pos.x, pos.y)
	if not c or c ~= cont then return nil end
	local s = { kind = kind, questID = questID, e = e, m = pos.m, x = pos.x, y = pos.y, cx = cx, cy = cy,
		work = work, key = kind .. ":" .. questID }
	if extra then for k, v in pairs(extra) do s[k] = v end end
	return s
end

-- Leveling style weighting (Profiles.lua): quests in the zones your style wants you in now count
-- for more, quests elsewhere for less; finishing chains and heading on to your next zone count
-- for more.
local function StyleWeight(questID, zoneName, focus, complete)
	if not focus then return 1 end
	local w = ns.Profiles:ZoneWeight(zoneName, focus, complete)
	local at = ns.db.npcs.turninAt[questID]
	if focus.nearEnd and focus.nextZone and at then
		local z = ns.Nav.MapName(ns.Nav.GetZoneMap(at.m))
		if ns.Profiles.SameZone(z, focus.nextZone) then w = w * BREADCRUMB end
	end
	local prev = ns.Chains and ns.db.guide.chains and ns.Chains:Prev(questID)
	if prev and ns.SafeCall(C_QuestLog.IsQuestFlaggedCompleted, prev) == true then w = w * CHAIN_STARTED end
	return w
end

function P:Bundles(cont)
	local cfg = ns.db.guide
	local bundles = {}
	local focus = ns.Guide and ns.Guide:Focus()
	self.focus = focus
	-- Advisor.lua: quests you skipped stay off the route, ones you're going back for count for
	-- a lot more, and Zone by zone is completionist: every quest in its zone, gray ones too.
	local AD = ns.Advisor
	local complete = AD and AD:Completionist() or false
	self.completionist = complete
	local function Skipped(qid) return AD and AD:IsSkipped(qid) end
	local function Back(qid) return AD and AD:IsGoingBack(qid) end
	local function InFocus(zoneName)
		if not (focus and zoneName) then return false end
		for name in pairs(focus.zones or {}) do
			if ns.Profiles.SameZone(name, zoneName) then return true end
		end
		return false
	end
	local sum, n = 0, 0
	for _, e in ipairs(ns.Quests.log) do
		if e.xp and e.xp > 0 then sum, n = sum + e.xp, n + 1 end
	end
	local avg = n > 0 and (sum / n) or 300
	self.avgXP = avg
	-- Dungeon quests (Dungeons.lua): what to pick up before the dungeons ahead, which quests in
	-- your log open one, and which wait for the dungeon itself.
	local dplan = ns.Dungeons and ns.Dungeons:On() and ns.Dungeons:Plan() or nil
	local function WaitsForDungeon(e)
		local d = dplan and not e.complete and dplan.wait[e.questID]
		return d and not ns.Dungeons:Inside(d)
	end

	for _, e in ipairs(ns.Quests.log) do
		-- A finished quest is never dropped for being gray. Its XP was earned at the level you
		-- did the work at, and all that's left is to walk over and collect it.
		-- A dungeon quest waits for the dungeon: the route doesn't send you to its entrance alone.
		local gray = e.trivial and not (cfg.showGray or e.complete or (complete and InFocus(ns.Quests:ZoneOf(e))))
		local tooHigh = not e.complete and P.TooHigh(e.level)
		if not e.failed and not gray and not tooHigh and not WaitsForDungeon(e) and not Skipped(e.questID) then
			local xp = (e.xp and e.xp > 0) and e.xp or avg
			local chain, ups = 0, 0
			if ns.Chains then chain, ups = ns.Chains:Value(e.questID, avg) end
			-- XP from the kills themselves, once Pace.lua has seen what a kill gives you.
			local kill = ns.Pace and ns.Pace:KillXPFor(e) or 0
			local b = { questID = e.questID, e = e, value = xp + chain + kill, xp = xp + kill, kill = kill, chainCount = ups, stops = {} }
			if (e.elite or e.group) and not IsInGroup() then b.value = b.value * 0.7 end
			b.value = b.value * StyleWeight(e.questID, ns.Quests:ZoneOf(e), focus, e.complete)
			if ns.Catchup then b.value = b.value * ns.Catchup:Weight(e.questID, e.complete, false) end
			-- A quest that opens a dungeon quest you're gathering: done first.
			if dplan and dplan.prep[e.questID] then b.value = b.value * PREP_BOOST end
			if Back(e.questID) then b.value = b.value * GOBACK end
			if e.complete then
				-- Banked XP: a finished quest is worth less every level you gain past its level,
				-- so the longer it sits the sooner it should be done.
				local qlevel = ns.Num(e.level)
				if qlevel and qlevel > 0 then
					local over = (UnitLevel("player") or qlevel) - qlevel
					if over > 0 then b.value = b.value * min(BANKED_MAX, 1 + over * BANKED_PER_LEVEL) end
				end
				-- Party catch-up: back to the objective to help whoever hasn't finished, then hand in.
				local help = ns.Catchup and ns.Catchup:HelpFor(e, avg)
				local h = help and help.spot and Stop("objective", e.questID, e, help.spot, cont, 60, { help = help.names, key = "help:" .. e.questID })
				if h then
					table.insert(b.stops, h)
					b.value = b.value + help.value
				end
				local pos = e.pos
				if not pos then
					-- No marker: use what's known about the hand-in (Quests:ResolveTurnin). A zone
					-- with no spot in it isn't a stop to plan around; the guide lists it instead.
					local at = ns.Quests:TurnInSpot(e.questID)
					if at and at.source ~= "zone" then pos = at end
				end
				local s = Stop("turnin", e.questID, e, pos, cont, STOP_WORK)
				if s then table.insert(b.stops, s) end
			else
				-- A dungeon or raid quest whose only marker is the quest NPC: the work is inside the
				-- instance, so there's nowhere out here to send you. It's no stop until it's done
				-- (the dungeon planner, Dungeons.lua, says when to run it).
				-- (Quests:Inside. One with a marker of its own, away from the NPC, keeps its stop.)
				local inside = ns.Quests:Inside(e)
				local s1 = not inside and Stop("objective", e.questID, e, e.pos, cont, WorkFor(e))
				if s1 then
					table.insert(b.stops, s1)
					if e.pos.waypoint then b.value = b.value * 0.8 end  -- the real area is past this point
					-- Only the NPC is marked: the objective could be anywhere, so it waits, and there's
					-- no separate turn-in stop on the same spot.
					if e.pos.npc then b.value = b.value * 0.5 end
					local spot = not e.pos.npc and ns.Quests:TurnInSpot(e.questID)
					if spot and spot.source == "zone" then spot = nil end
					local s2 = spot and Stop("turnin", e.questID, e, spot, cont, STOP_WORK, { predicted = true, key = "then:" .. e.questID })
					if s2 then table.insert(b.stops, s2) end
				end
			end
			if #b.stops > 0 then
				b.work = 0
				for i, s in ipairs(b.stops) do
					s.bundle, s.order = b, i
					b.work = b.work + s.work
				end
				table.insert(bundles, b)
			end
		end
	end

	if cfg.planPickups then
		for _, o in ipairs(ns.Quests.offers) do
			-- Zone by zone takes the gray ones in its zone too; red (too high) ones wait either way.
			local shown = ns.Quests:OfferShown(o, true) and not P.TooHigh(o.level)
				or (complete and (o.trivial or o.difficulty == 0) and o.difficulty ~= 4 and InFocus(ns.Quests:ZoneOf(o)))
			if shown and not Skipped(o.questID) then
				local chain, ups = 0, 0
				if ns.Chains then chain, ups = ns.Chains:Value(o.questID, avg) end
				local s = Stop("pickup", o.questID, o, o, cont, STOP_WORK)
				if s then
					-- Worth taking by what the whole quest is worth for the time it takes (Advisor.lua),
					-- not only by its XP: a quest whose work is across the map counts for less.
					local xp = o.xp or (AD and AD:XP(o.questID)) or avg
					local fit = AD and AD:PickupFactor(o.questID) or 1
					local b = { questID = o.questID, e = o, value = (xp + chain) * PICKUP_SHARE * fit, xp = xp, chainCount = ups,
						stops = { s }, work = STOP_WORK, pickup = true }
					-- A quest you may do: your level, not gray, not one that needs a group you
					-- haven't got. Passing its giver, you take it; it can be dropped later.
					local kind = ns.Quests:Kind(o.questID)
					b.mayDo = not (o.trivial or o.difficulty == 0 or o.difficulty == 4)
						and (not kind or kind == "PvP" or (IsInGroup and IsInGroup()) or false) and true or false
					if Back(o.questID) then b.value = b.value * GOBACK end
					b.value = b.value * StyleWeight(o.questID, ns.Quests:ZoneOf(o), focus, false)
					if ns.Catchup then b.value = b.value * ns.Catchup:Weight(o.questID, false, true) end
					s.bundle, s.order = b, 1
					table.insert(bundles, b)
				end
			end
		end
		self:AheadBundles(bundles, cont, focus, avg)
	end
	if dplan then self:DungeonBundles(bundles, cont, avg, dplan) end
	self:BackBundles(bundles, cont, avg)
	return bundles
end

-- Quests from the missed list you chose to go back for and haven't picked up again: a stop at
-- their giver, worth a lot, so the route takes you there. One on another continent is left to
-- the guide's own "Go back for" step (Advisor.lua).
function P:BackBundles(bundles, cont, avg)
	local AD = ns.Advisor
	if not AD then return end
	local have = {}
	for _, b in ipairs(bundles) do have[b.questID] = true end
	for qid in pairs(ns.char.goBack or {}) do
		if not have[qid] and not ns.Quests.byID[qid] then
			local q = ns.QuestDB and ns.QuestDB:Get(qid)
			if q and q.m and q.x and ns.QuestDB:Status(qid, q) == "available" then
				local o = { questID = qid, title = q.t or AD.Title(qid), level = q.l, m = q.m, x = q.x, y = q.y,
					dist = ns.Nav.Distance(q.m, q.x, q.y), back = true }
				local s = Stop("pickup", qid, o, o, cont, STOP_WORK)
				if s then
					local b = { questID = qid, e = o, value = (AD:XP(qid) or avg) * GOBACK, xp = AD:XP(qid) or avg, chainCount = 0,
						stops = { s }, work = STOP_WORK, pickup = true, back = true }
					s.bundle, s.order = b, 1
					table.insert(bundles, b)
				end
			end
		end
	end
end

-- Dungeon quests and the pre-quests that open them (Dungeons.lua), for the dungeons you've ticked
-- whose level window is coming up. Worth the dungeon quest's XP and then some, so they're picked
-- up before ordinary quests. One already on the route as a pickup just gets the higher value.
local dungeonRequested = {}
function P:DungeonBundles(bundles, cont, avg, dplan)
	local byQuest = {}
	for _, b in ipairs(bundles) do if b.pickup then byQuest[b.questID] = b end end
	for _, pick in ipairs(dplan.picks) do
		if not (ns.Advisor and ns.Advisor:IsSkipped(pick.qid)) then
		local xp = ns.Num(GetQuestLogRewardXP(pick.forQid))
		if not (xp and xp > 0) and not dungeonRequested[pick.forQid] then
			dungeonRequested[pick.forQid] = true
			pcall(C_QuestLog.RequestLoadQuestByID, pick.forQid)
		end
		local worth = ((xp and xp > 0) and xp or avg) * DUNGEON_SHARE * PREP_BOOST
		local b = byQuest[pick.qid]
		if b then
			b.value = max(b.value, worth)
			b.dungeon = pick.dungeon
		else
			local q = ns.QuestDB:Get(pick.qid)
			if q and q.m and q.x then
				local o = { questID = pick.qid, title = q.t or ns.Dungeons:Title(pick.qid), level = q.l, m = q.m, x = q.x, y = q.y,
					dist = ns.Nav.Distance(q.m, q.x, q.y) }
				local s = Stop("pickup", pick.qid, o, o, cont, STOP_WORK)
				if s then
					b = { questID = pick.qid, e = o, value = worth, xp = avg, chainCount = 0, stops = { s }, work = STOP_WORK,
						pickup = true, dungeon = pick.dungeon }
					s.bundle, s.order = b, 1
					table.insert(bundles, b)
					byQuest[pick.qid] = b
				end
			end
		end
		end
	end
end

-- Quest givers in the zone your plan sends you to next (or now, when you're somewhere else).
-- The game only reports quests on offer for the map you're on, so these come from what
-- NeverQuest knows (QuestDB.lua); the moment you arrive, the game's own list takes over.
local aheadRequested = {}
function P:AheadBundles(bundles, cont, focus, avg)
	if not focus or not ns.QuestDB or not ns.Profiles then return end
	local targets = {}
	if focus.moveOn and focus.primaryID then targets[#targets + 1] = focus.primaryID end
	if focus.nearEnd and focus.nextZone then
		local id = ns.Profiles.ZoneID(focus.nextZone)
		if id then targets[#targets + 1] = id end
	end
	local taken = {}
	for _, o in ipairs(ns.Quests.offers) do taken[o.questID] = true end
	for _, b in ipairs(bundles) do taken[b.questID] = true end
	for qid in pairs(ns.char.skipped or {}) do taken[qid] = true end
	local doneZone = {}
	for _, zid in ipairs(targets) do
		if zid ~= ns.Quests.offerMap and not doneZone[zid] then
			doneZone[zid] = true
			local picks = {}
			for _, k in ipairs(ns.QuestDB:OpenIn(zid)) do
				if not taken[k.qid] and not P.TooHigh(k.q.l) then
					picks[#picks + 1] = { k = k, d = ns.Nav.Distance(k.q.m, k.q.x, k.q.y) or math.huge }
				end
			end
			table.sort(picks, function(a, b) return a.d < b.d end)
			local zoneName = ns.Nav.MapName(zid)
			for i = 1, math.min(#picks, AHEAD_MAX) do
				local k, q = picks[i].k, picks[i].k.q
				taken[k.qid] = true
				local xp = ns.Num(GetQuestLogRewardXP(k.qid))
				if not (xp and xp > 0) and not aheadRequested[k.qid] then
					aheadRequested[k.qid] = true
					pcall(C_QuestLog.RequestLoadQuestByID, k.qid)
				end
				local o = { questID = k.qid, title = q.t, level = q.l, m = q.m, x = q.x, y = q.y,
					xp = (xp and xp > 0) and xp or nil, dist = picks[i].d < math.huge and picks[i].d or nil, ahead = true }
				local chain, ups = 0, 0
				if ns.Chains then chain, ups = ns.Chains:Value(k.qid, avg) end
				local s = Stop("pickup", k.qid, o, o, cont, STOP_WORK)
				if s then
					local b = { questID = k.qid, e = o, value = ((o.xp or avg) + chain) * PICKUP_SHARE * AHEAD_SHARE, xp = o.xp or avg,
						chainCount = ups, stops = { s }, work = STOP_WORK, pickup = true, ahead = true }
					b.value = b.value * StyleWeight(k.qid, zoneName, focus, false)
					s.bundle, s.order = b, 1
					table.insert(bundles, b)
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Cheapest insertion (open route: it doesn't come back to the start)
---------------------------------------------------------------------------
-- Element k of the route with stop s inserted at position i (nil past the end).
local function Virtual(route, i, s, k)
	if not s then return route[k] end
	if k < i then return route[k] end
	if k == i then return s end
	return route[k - 1]
end

local function BestSpot(route, start, ins, insAt, stop, from, len)
	local best, bestK = math.huge, nil
	for k = from, len + 1 do
		local prev = (k == 1) and start or Virtual(route, insAt, ins, k - 1)
		local nxt = Virtual(route, insAt, ins, k)
		local delta = D(prev, stop) + (nxt and (D(stop, nxt) - D(prev, nxt)) or 0)
		if delta < best then best, bestK = delta, k end
	end
	return best, bestK
end

-- Extra yards to fit a bundle into the route, and where its stops go. from: the first place a
-- stop may go (2 keeps a forced first stop first).
local function Insertion(route, start, b, forceFirst, from)
	local s1, s2 = b.stops[1], b.stops[2]
	local d1, i
	if forceFirst then
		local nxt = route[1]
		d1, i = D(start, s1) + (nxt and (D(s1, nxt) - D(start, nxt)) or 0), 1
	else
		d1, i = BestSpot(route, start, nil, nil, s1, math.min(from or 1, #route + 1), #route)
	end
	if not s2 then return d1, i end
	local d2, j = BestSpot(route, start, s1, i, s2, i + 1, #route + 1)
	return d1 + d2, i, j
end

local function Apply(route, b, i, j)
	table.insert(route, i, b.stops[1])
	if j then table.insert(route, j, b.stops[2]) end
end

local function Travel(route, start)
	local yards, prev = 0, start
	for _, s in ipairs(route) do
		yards = yards + D(prev, s)
		prev = s
	end
	return yards
end

-- Reverse segments while that shortens the route, never putting a turn-in before its objective.
-- first: the first position that may move (2 keeps a forced first stop where it is).
local function Tighten(route, start, first)
	local n = #route
	if n < 3 then return false end
	local changed = false
	for _ = 1, 40 do
		local improved = false
		for i = first or 1, n - 1 do
			for j = i + 1, n do
				-- Segment i..j must not hold both stops of one quest.
				local ok, seen = true, {}
				for k = i, j do
					local b = route[k].bundle
					if seen[b] then ok = false break end
					seen[b] = true
				end
				if ok then
					local before = (i == 1) and start or route[i - 1]
					local after = route[j + 1]
					local old = D(before, route[i]) + (after and D(route[j], after) or 0)
					local new = D(before, route[j]) + (after and D(route[i], after) or 0)
					if new < old - 0.5 then
						local a, z = i, j
						while a < z do
							route[a], route[z] = route[z], route[a]
							a, z = a + 1, z - 1
						end
						improved = true
					end
				end
			end
		end
		if not improved then break end
		changed = true
	end
	return changed
end

-- Every turn-in after its objective.
local function Valid(route)
	local at = {}
	for k, s in ipairs(route) do if s.order == 1 then at[s.bundle] = k end end
	for k, s in ipairs(route) do
		if s.order == 2 and at[s.bundle] and at[s.bundle] > k then return false end
	end
	return true
end

-- Move single stops, or runs of two or three in a row, to wherever they save the most travel.
-- Reversing stretches can't do this when a stretch holds both stops of a quest, and a route
-- full of objectives and their turn-ins is mostly made of those. A run keeps its own order.
local function Relocate(route, start, first)
	first = first or 1
	local n = #route
	if n < 2 then return false end
	local changed = false
	for _ = 1, 40 do
		local improved = false
		for len = 1, 3 do
			for i = first, n - len + 1 do
				local j = i + len - 1
				local prev = (i == 1) and start or route[i - 1]
				local nxt = route[j + 1]
				local gain = D(prev, route[i]) + (nxt and (D(route[j], nxt) - D(prev, nxt)) or 0)
				local bestK, bestSave
				for k = first - 1, n do
					-- the gap after route[k] (k = 0: right after where you stand), outside the run
					if k < i - 1 or k > j then
						local u = (k == 0) and start or route[k]
						local v = route[k + 1]
						local cost = D(u, route[i]) + (v and (D(route[j], v) - D(u, v)) or 0)
						local save = gain - cost
						if save > 0.5 and (not bestSave or save > bestSave) then
							-- only if no turn-in ends up before its objective
							local moved = {}
							for x = 1, n do
								if x < i or x > j then moved[#moved + 1] = route[x] end
								if x == k then for y = i, j do moved[#moved + 1] = route[y] end end
							end
							if k == 0 then
								local front = {}
								for y = i, j do front[#front + 1] = route[y] end
								for _, s in ipairs(moved) do front[#front + 1] = s end
								moved = front
							end
							if Valid(moved) then bestK, bestSave = moved, save end
						end
					end
				end
				if bestK then
					for x = 1, n do route[x] = bestK[x] end
					improved, changed = true, true
				end
			end
		end
		if not improved then break end
	end
	return changed
end

-- Both, until neither finds anything more.
local function Improve(route, start, first)
	for _ = 1, 8 do
		local a = Tighten(route, start, first)
		local b = Relocate(route, start, first)
		if not a and not b then break end
	end
end

-- Hand in, and pick up, the first time the route passes by, not on a later visit: each turn-in
-- and pickup moves to the earliest place it fits for at most EARLY more yards (a turn-in never
-- before its objective). When you're coming back anyway the walking is the same, but the XP comes
-- sooner, the follow-ups open up, and a quest picked up on the way out can be done on this trip
-- instead of the next one.
-- Runs last, since the passes above would move them back to save those few yards.
local function Earlier(route, start, first)
	first = first or 1
	for k = first + 1, #route do
		local s = route[k]
		if s.kind == "turnin" or s.kind == "pickup" then
			local prev, nxt = route[k - 1], route[k + 1]
			local saved = D(prev, s) + (nxt and (D(s, nxt) - D(prev, nxt)) or 0)
			for p = first, k - 1 do
				local u = (p == 1) and start or route[p - 1]
				local v = route[p]
				if D(u, s) + D(s, v) - D(u, v) - saved <= EARLY then
					table.remove(route, k)
					table.insert(route, p, s)
					if Valid(route) then break end
					table.remove(route, p)
					table.insert(route, k, s)
				end
			end
		end
	end
end

P._Earlier = Earlier  -- for the tests

---------------------------------------------------------------------------
-- Building a plan
---------------------------------------------------------------------------
local function Speed()
	return max(7, (ns.Route and ns.Route.speed) or 7)
end

-- Finished quests handed in near each other are one trip, and that is how they have to be
-- judged: a single turn-in across the map never pays for the walk on its own, while the ten
-- sitting in the same town clearly do. The other finished quests handed in within reach of
-- this one, or nil if it stands alone.
local function Cluster(bundles, used, b)
	local s = b.stops[1]
	if not s or #b.stops > 1 or s.kind ~= "turnin" then return nil end
	local out
	for _, o in ipairs(bundles) do
		if o ~= b and not used[o] and #o.stops == 1 and o.stops[1].kind == "turnin"
			and D(s, o.stops[1]) <= TURNIN_RUN then
			out = out or {}
			table.insert(out, o)
		end
	end
	return out
end

-- Rate for making that trip once and clearing the whole pile: the walk out, the shortest
-- nearest-first path around the stops, and the time spent talking to each NPC.
local function RunRate(cluster, b, d, speed)
	local value, work, inner = b.value, b.work, 0
	local at, left, n = b.stops[1], {}, #cluster
	for i, o in ipairs(cluster) do
		value, work = value + o.value, work + o.work
		left[i] = o.stops[1]
	end
	for _ = 1, n do
		local bestD, bestI = math.huge, nil
		for i = 1, n do
			local s = left[i]
			if s then
				local dd = D(at, s)
				if dd < bestD then bestD, bestI = dd, i end
			end
		end
		if not bestI then break end
		inner, at = inner + bestD, left[bestI]
		left[bestI] = nil
	end
	return value / max(5, (d + inner) * DETOUR / speed + work)
end

-- Finished quests handed in where you stand, and quests worth taking that are given there,
-- nearest first, each within HERE yards of the one before (you first), none more than HERE_MAX
-- from you; further in a town or city, where you're resting and the NPCs are spread out. None
-- while you're working on an objective: one still to do is close by and closer than any of
-- these turn-ins.
local function HereFirst(bundles, start, bar, speed, room)
	local town = IsResting and ns.SafeCall(IsResting) == true
	local step, reach = town and HERE_TOWN or HERE, town and HERE_TOWN_MAX or HERE_MAX
	local work, turnin = math.huge, math.huge
	for _, b in ipairs(bundles) do
		local s = b.stops[1]
		if s and not b.pickup then
			if s.kind == "objective" then work = min(work, D(start, s))
			elseif #b.stops == 1 and s.kind == "turnin" then turnin = min(turnin, D(start, s)) end
		end
	end
	if work <= NEAR_WORK and work < turnin then return nil end
	local list, taken, at = {}, {}, start
	while true do
		local best, bestD, bestNear
		for _, b in ipairs(bundles) do
			local s = b.stops[1]
			local ok = not taken[b] and #b.stops == 1 and (s.kind == "turnin" or (s.kind == "pickup" and bar and b.value / (D(at, s) * DETOUR / speed + b.work) >= bar))
			-- Right here and one you may do: taken while you're passing, worth the bar or not.
			local near = not ok and not taken[b] and b.mayDo and room > 0 and D(at, s) <= NEAR_PICKUP
			if ok or near then
				local d = D(at, s)
				if d <= step and D(start, s) <= reach and (not bestD or d < bestD) then best, bestD, bestNear = b, d, near end
			end
		end
		if not best then break end
		if bestNear then room = room - 1 best.passing = true end
		taken[best] = true
		list[#list + 1] = best
		at = best.stops[1]
	end
	return list, room
end

local function Rates(plan)
	local secs = plan.seconds
	plan.rate = secs > 0 and (plan.value / secs * 3600) or 0
	plan.xpRate = secs > 0 and (plan.xp / secs * 3600) or 0
	plan.plainRate = secs > 0 and (plan.plain / secs * 3600) or 0
	return plan
end

local function Build(bundles, start, forced)
	local speed = Speed()
	local route, used, value, work = {}, {}, 0, 0

	-- Bar for leaving quests out: a share of the best unfinished quest's XP per second.
	local bestRate = 0
	for _, b in ipairs(bundles) do
		if not b.pickup and not b.e.complete and b.stops[1].kind == "objective" then
			local d = Insertion(route, start, b)
			bestRate = max(bestRate, b.value / max(5, d * DETOUR / speed + b.work))
		end
	end
	local style = P.focus and P.focus.style or "none"
	local bar = bestRate * (MIN_SHARE[style] or 0.3)
	-- Zone by zone, completionist: nothing is left out for being slow, only for not fitting
	-- in the next half hour.
	if P.completionist and style == "zone" then bar = 0 end

	-- Hand in what's ready right here before going anywhere, a forced first stop included.
	-- Room in the quest log for quests taken just because you're passing (LOG_ROOM slots are kept).
	local room = P.LogRoom()
	local hereList, roomLeft = HereFirst(bundles, start, bar, speed, room)
	room = roomLeft or room
	for _, b in ipairs(hereList or {}) do
		Apply(route, b, #route + 1)
		used[b] = true
		value, work = value + b.value, work + b.work
	end
	local here = #route

	if forced and not used[forced] then
		Apply(route, forced, #route + 1, forced.stops[2] and #route + 2 or nil)
		used[forced] = true
		value, work = value + forced.value, work + forced.work
	end

	-- The turn-ins here and a forced first stop stay first: everything else goes in after them.
	local from = here + ((forced and route[here + 1] == forced.stops[1]) and 1 or 0) + 1
	while #route < MAX_STOPS do
		local best, bestR, bi, bj, bestRun
		for _, b in ipairs(bundles) do
			if not used[b] then
				local d, i, j = Insertion(route, start, b, false, from)
				local rate = b.value / max(5, d * DETOUR / speed + b.work)
				local cluster = Cluster(bundles, used, b)
				local run = cluster and RunRate(cluster, b, d, speed)
				local asRun = run and run > rate
				if asRun then rate = run end
				if not bestR or rate > bestR then
					best, bestR, bi, bj, bestRun = b, rate, i, j, asRun and cluster or nil
				end
			end
		end
		if not best or bestR < bar then break end
		Apply(route, best, bi, bj)
		used[best] = true
		value, work = value + best.value, work + best.work
		-- Judged as one trip, so it goes in as one trip: every quest in the pile helps pay for
		-- the walk, and stopping after the first would waste it.
		if bestRun then
			for _, o in ipairs(bestRun) do
				if #route >= MAX_STOPS then break end
				local d, i = Insertion(route, start, o, false, from)
				Apply(route, o, i)
				used[o] = true
				value, work = value + o.value, work + o.work
			end
		end
		if Travel(route, start) * DETOUR / speed + work > HORIZON then break end
	end

	-- While you're there: a quest right on the way is done on the same visit, even past the half
	-- hour this plan looks ahead, as long as it's still worth its time.
	for _, b in ipairs(bundles) do
		if #route >= MAX_STOPS then break end
		if not used[b] and #b.stops > 0 and #route + #b.stops <= MAX_STOPS then
			local d, i, j = Insertion(route, start, b, false, from)
			local rate = b.value / max(5, d * DETOUR / speed + b.work)
			-- (and a quest giver you walk right past, for a quest you may do: taken as you go)
			local passing = b.pickup and b.mayDo and room > 0 and d <= NEAR_ROUTE
			if (d <= ONTHEWAY and rate >= bar * ONTHEWAY_BAR) or passing then
				if passing and not (rate >= bar * ONTHEWAY_BAR) then room = room - 1 b.passing = true end
				Apply(route, b, i, j)
				used[b] = true
				value, work = value + b.value, work + b.work
			end
		end
	end

	Improve(route, start, from)
	Earlier(route, start, from)
	local yards = Travel(route, start)
	local secs = yards * DETOUR / speed + work
	local skipped = {}
	for _, b in ipairs(bundles) do
		if not used[b] and not b.pickup then table.insert(skipped, b) end
	end
	-- value and rate are what the planner ranks by: XP weighted for your leveling style, chains,
	-- going back for a quest and so on. xp is the plain XP of the quests this trip works on, and
	-- plainRate the unweighted XP per hour (a pickup counting for its share), which is what other
	-- quests are measured against and what you're shown.
	local xp, plain = 0, 0
	for b in pairs(used) do
		if b.pickup then plain = plain + (b.xp or 0) * PICKUP_SHARE
		else xp = xp + (b.xp or 0) end
	end
	plain = plain + xp
	return Rates({
		stops = route, yards = yards, seconds = secs, value = value, xp = xp, plain = plain,
		skipped = skipped, bar = bar, here = here,
	})
end

-- Free quest log slots beyond the ones kept back.
function P.LogRoom()
	local cap = ns.Num(C_QuestLog.GetMaxNumQuestsCanAccept and ns.SafeCall(C_QuestLog.GetMaxNumQuestsCanAccept)) or 25
	local _, n = C_QuestLog.GetNumQuestLogEntries()
	return max(0, cap - (ns.Num(n) or 0) - LOG_ROOM)
end

function P:Make()
	local m, x, y = ns.Nav.GetPlayerPosition()
	local cont, cx, cy = Locate(m, x, y)
	if not cont then return nil end
	local start = { cx = cx, cy = cy, key = "start", m = m, x = x, y = y }
	walkOK = false
	-- Flight masters you can fly to on this continent (none until a flight map has shown them).
	flights = nil
	if ns.db.nav.flights and ns.Route and ns.Route.KnownNodes then
		local size = sizeCache[cont]
		local list = {}
		for _, n in ipairs(ns.Route.KnownNodes(cont) or {}) do
			list[#list + 1] = { cx = n.x * size[1], cy = n.y * size[2], name = n.name }
		end
		if #list >= 2 then flights, flightSpeed = list, Speed() end
	end
	local bundles = self:Bundles(cont)
	-- Walking distances (Paths.lua): say which stops matter, nearest first. They're used once
	-- nearly all of them are known; until then every distance is a straight line, so the route
	-- is never built from a mix of the two (a stop measured straight looks nearer than it is
	-- beside ones measured on foot).
	if ns.Paths and ns.Paths:Planning() and not self.straight then  -- (.straight: the test harness's switch)
		local list = {}
		for _, b in ipairs(bundles) do
			for _, s in ipairs(b.stops) do
				if s.m and s.x then list[#list + 1] = s s.sd = D(start, s) end
			end
		end
		table.sort(list, function(p, q) return p.sd < q.sd end)
		ns.Paths:Begin()
		local known, total = 0, 0
		for _, s in ipairs(list) do
			local got = ns.Paths:Want(s.m, s.x, s.y)
			if got ~= nil and total < WALK_STOPS then
				total = total + 1
				if got then known = known + 1 end
			end
		end
		walkOK = total > 0 and known >= total * WALK_READY
	end
	-- A quest you chose to go back for (Advisor.lua) is where you go next: the nearest one is
	-- the first stop, wherever cheapest insertion would have put it.
	local back
	for _, b in ipairs(bundles) do
		if b.back then
			local d = D(start, b.stops[1])
			if not back or d < back.d then back = { b = b, d = d } end
		end
	end
	local plan = Build(bundles, start, back and back.b)

	-- Keep the current first stop unless changing is clearly better, so the arrow doesn't flip
	-- back and forth. Going back for a quest waits only for an objective you're standing in.
	--
	-- Two builds of the route are not a fair comparison: each leaves out different quests at the
	-- half-hour mark, and the one that happens to drop a slow quest looks better for it. Walking
	-- a few yards could flip which one won, and the arrow with it. So where the new plan still
	-- has the old first stop, the question asked is the plain one: the same stops, with the old
	-- one first, how much longer is that? Only when the new plan has dropped the old stop
	-- altogether are two builds compared, and then it takes the full 15%.
	-- And a stop you were sent away from isn't gone back to until something changes in your
	-- quests, whatever the sums say: one change of mind is planning, two is pacing up and down.
	local sig = #bundles
	for _, b in ipairs(bundles) do sig = sig + b.questID * (b.pickup and 7 or (b.e.complete and 3 or 1)) end
	if sig ~= self.leftSig then self.leftSig, self.left = sig, {} end
	local old = self.plan and self.plan.stops[1]
	local first = plan.stops[1]
	if old and first and old.key ~= first.key and (plan.here or 0) == 0 then
		local keep
		for _, b in ipairs(bundles) do
			if b.stops[1].key == old.key then keep = b break end
		end
		if keep then
			local working = keep.stops[1].kind == "objective" and D(start, keep.stops[1]) <= WORKING_YARDS
			local stay = working or (not back and self.left[first.key])
			local at
			for k, s in ipairs(plan.stops) do if s.key == old.key then at = k break end end
			if not stay and not back and at then
				local route = {}
				for k, s in ipairs(plan.stops) do route[k] = s end
				table.insert(route, 1, table.remove(route, at))
				Improve(route, start, 2)
				Earlier(route, start, 2)
				local speed = Speed()
				local yards = Travel(route, start)
				if (yards - plan.yards) * DETOUR / speed < SWITCH_SECONDS then
					local secs = plan.seconds + (yards - plan.yards) * DETOUR / speed
					plan.stops, plan.yards, plan.seconds = route, yards, secs
					Rates(plan)
				else
					self.left[old.key] = true
				end
			elseif stay or not back then
				local held = Build(bundles, start, keep)
				if stay or plan.rate <= held.rate * KEEP_MARGIN then
					plan = held
				else
					self.left[old.key] = true
				end
			end
		end
	end

	plan.made, plan.m, plan.x, plan.y, plan.cont = GetTime(), m, x, y, cont
	plan.rank = {}
	for i, s in ipairs(plan.stops) do
		if not plan.rank[s.questID] then plan.rank[s.questID] = i end
	end
	return plan
end

-- The current plan, made again when quests change, you move or it gets old.
function P:Get()
	if not ns.db.guide.planner then return nil end
	local plan = self.plan
	local now = GetTime()
	local stale = self.dirty or not plan or now - (plan.made or 0) > REPLAN_EVERY
	if not stale and plan.m then
		local d = ns.Nav.Distance(plan.m, plan.x, plan.y)
		if not d or d > REPLAN_MOVE then stale = true end
	end
	if stale then
		self.dirty = false
		self.plan = self:Make()
		if self.plan then
			ns.Debug(string.format("planner: %d stops, %s, ~%s XP (%s XP/h)", #self.plan.stops,
				ns.Duration(self.plan.seconds), ns.Comma(self.plan.xp), ns.Comma(self.plan.xpRate)))
		end
	end
	return self.plan
end

-- Order of quests on the route (1 = next), for the tracker. Quests off the route aren't listed.
function P:Rank(questID)
	local plan = self.plan
	return plan and plan.rank and plan.rank[questID] or nil
end

for _, msg in ipairs({ "QUESTS_UPDATED", "OFFERS_UPDATED", "SPAWNS_UPDATED", "CHAINS_UPDATED" }) do
	ns:RegisterMessage(msg, function() P.dirty = true end)
end

ns:AddSlash("route", function()
	local plan = P:Get()
	if not plan then
		ns.Print(ns.db.guide.planner and "no route right now (your position isn't available, or nothing to do here)."
			or "route planning is off (Options > Guide & Routes).")
		return
	end
	ns.Print(string.format("route: %d stops, ~%s, ~%s XP (%s XP/hour).", #plan.stops, ns.Duration(plan.seconds),
		ns.Comma(plan.xp), ns.Comma(plan.xpRate)))
	for i, s in ipairs(plan.stops) do
		local title = s.e and (s.e.title or "?") or "?"
		local what = s.kind == "objective" and "do" or s.predicted and "then turn in" or s.kind == "turnin" and "turn in" or "pick up"
		DEFAULT_CHAT_FRAME:AddMessage(string.format("   %d. %s: %s", i, what, title))
	end
	if #plan.skipped > 0 then
		DEFAULT_CHAT_FRAME:AddMessage("   Not on this route (too far or too little XP for the time): " .. #plan.skipped .. " quest(s).")
	end
end, "/nq route - list the planned route in chat")
