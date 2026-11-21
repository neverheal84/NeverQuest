-- NeverQuest Planner: puts your next stops (objectives, turn-ins, quest pickups) into one route
-- that wastes as little travel as possible while keeping XP per hour high.
--
-- How a plan is made:
--   1. Every quest becomes a bundle: its objective area, then where it's handed in (known
--      turn-in spot, or where you picked it up, which is usually the same NPC). Finished
--      quests are just the turn-in. Quest givers nearby are cheap one-stop bundles.
--   2. Each bundle is worth its XP plus part of the XP of the quests it opens up (Chains.lua)
--      and costs the extra travel to fit it into the route plus the time to do it.
--   3. Bundles go in one at a time, best XP per second first, each at the place in the route
--      where it adds the least travel (the objective always before its turn-in). Quests worth
--      much less than the best quest on offer are left out ("not on this route").
--   4. The order is then tightened (segments reversed where that shortens the trip).
--   5. The current first stop is kept unless a new plan is clearly better, so the arrow
--      doesn't flip back and forth.

local ADDON, ns = ...
local P = {}
ns.Planner = P

local sqrt, max, min = math.sqrt, math.max, math.min

local DETOUR = 1.25         -- real paths are longer than straight lines
local HORIZON = 1800        -- plan about 30 minutes ahead
local MIN_SHARE = { optimized = 0.35, zone = 0.15, none = 0.3 }  -- leave out quests under this share of the best quest's XP per second
local BREADCRUMB = 1.3      -- quests handed in at your next zone, near the end of a leg
local CHAIN_STARTED = 1.15  -- follow-ups of quests you've done: finish chains you've started
local KEEP_MARGIN = 1.15    -- a new first stop must make the plan 15% better
local WORKING_YARDS = 60    -- this close to the current objective, you're working on it: keep it
local REPLAN_MOVE = 120     -- yards moved before planning again
local REPLAN_EVERY = 8      -- seconds between plans
local MAX_STOPS = 30
local STOP_WORK = 8         -- seconds to talk to an NPC
local PICKUP_SHARE = 0.4    -- a pickup is worth part of its quest's XP: the rest comes later
-- Seconds per objective unit, by objective type.
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

local function D(a, b)
	local dx, dy = a.cx - b.cx, a.cy - b.cy
	return sqrt(dx * dx + dy * dy)
end

---------------------------------------------------------------------------
-- Bundles
---------------------------------------------------------------------------
local function WorkFor(e)
	local t = 0
	for _, o in ipairs(C_QuestLog.GetQuestObjectives(e.questID) or {}) do
		if not o.finished then
			local need, have = ns.Num(o.numRequired) or 0, ns.Num(o.numFulfilled) or 0
			local per = WORK[o.type] or 25
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
	if e.elite or e.group then t = t * 1.6 end
	return t
end

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
	local sum, n = 0, 0
	for _, e in ipairs(ns.Quests.log) do
		if e.xp and e.xp > 0 then sum, n = sum + e.xp, n + 1 end
	end
	local avg = n > 0 and (sum / n) or 300
	self.avgXP = avg

	for _, e in ipairs(ns.Quests.log) do
		if not e.failed and (cfg.showGray or not e.trivial) then
			local xp = (e.xp and e.xp > 0) and e.xp or avg
			local chain, ups = 0, 0
			if ns.Chains then chain, ups = ns.Chains:Value(e.questID, avg) end
			local b = { questID = e.questID, e = e, value = xp + chain, chainCount = ups, stops = {} }
			if e.elite or e.group then b.value = b.value * 0.7 end
			b.value = b.value * StyleWeight(e.questID, ns.Quests:ZoneOf(e), focus, e.complete)
			if ns.Catchup then b.value = b.value * ns.Catchup:Weight(e.questID, e.complete, false) end
			if e.complete then
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
				local s1 = Stop("objective", e.questID, e, e.pos, cont, WorkFor(e))
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
			if ns.Quests:OfferShown(o, true) then
				local chain, ups = 0, 0
				if ns.Chains then chain, ups = ns.Chains:Value(o.questID, avg) end
				local s = Stop("pickup", o.questID, o, o, cont, STOP_WORK)
				if s then
					local b = { questID = o.questID, e = o, value = ((o.xp or avg) + chain) * PICKUP_SHARE, chainCount = ups,
						stops = { s }, work = STOP_WORK, pickup = true }
					b.value = b.value * StyleWeight(o.questID, ns.Quests:ZoneOf(o), focus, false)
					if ns.Catchup then b.value = b.value * ns.Catchup:Weight(o.questID, false, true) end
					s.bundle, s.order = b, 1
					table.insert(bundles, b)
				end
			end
		end
	end
	return bundles
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

-- Extra yards to fit a bundle into the route, and where its stops go.
local function Insertion(route, start, b, forceFirst)
	local s1, s2 = b.stops[1], b.stops[2]
	local d1, i
	if forceFirst then
		local nxt = route[1]
		d1, i = D(start, s1) + (nxt and (D(s1, nxt) - D(start, nxt)) or 0), 1
	else
		d1, i = BestSpot(route, start, nil, nil, s1, 1, #route)
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
local function Tighten(route, start)
	local n = #route
	if n < 3 then return end
	for _ = 1, 40 do
		local improved = false
		for i = 1, n - 1 do
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
	end
end

---------------------------------------------------------------------------
-- Building a plan
---------------------------------------------------------------------------
local function Speed()
	return max(7, (ns.Route and ns.Route.speed) or 7)
end

local function Build(bundles, start, forced)
	local speed = Speed()
	local route, used, value, work = {}, {}, 0, 0

	-- Bar for leaving quests out: a share of the best unfinished quest's XP per second.
	local bestRate = 0
	for _, b in ipairs(bundles) do
		if not b.pickup and b.stops[1].kind == "objective" then
			local d = Insertion(route, start, b)
			bestRate = max(bestRate, b.value / max(5, d * DETOUR / speed + b.work))
		end
	end
	local style = P.focus and P.focus.style or "none"
	local bar = bestRate * (MIN_SHARE[style] or 0.3)

	if forced then
		local d, i, j = Insertion(route, start, forced, true)
		Apply(route, forced, i, j)
		used[forced] = true
		value, work = value + forced.value, work + forced.work
	end

	while #route < MAX_STOPS do
		local best, bestR, bi, bj
		for _, b in ipairs(bundles) do
			if not used[b] then
				local d, i, j = Insertion(route, start, b)
				local rate = b.value / max(5, d * DETOUR / speed + b.work)
				if not bestR or rate > bestR then best, bestR, bi, bj = b, rate, i, j end
			end
		end
		if not best or bestR < bar then break end
		Apply(route, best, bi, bj)
		used[best] = true
		value, work = value + best.value, work + best.work
		if Travel(route, start) * DETOUR / speed + work > HORIZON then break end
	end

	Tighten(route, start)
	local yards = Travel(route, start)
	local secs = yards * DETOUR / speed + work
	local skipped = {}
	for _, b in ipairs(bundles) do
		if not used[b] and not b.pickup then table.insert(skipped, b) end
	end
	return {
		stops = route, yards = yards, seconds = secs, value = value,
		rate = secs > 0 and (value / secs * 3600) or 0, skipped = skipped, bar = bar,
	}
end

function P:Make()
	local m, x, y = ns.Nav.GetPlayerPosition()
	local cont, cx, cy = Locate(m, x, y)
	if not cont then return nil end
	local start = { cx = cx, cy = cy, key = "start" }
	local bundles = self:Bundles(cont)
	local plan = Build(bundles, start)

	-- Keep the current first stop unless the new plan is clearly better.
	local old = self.plan and self.plan.stops[1]
	local first = plan.stops[1]
	if old and first and old.key ~= first.key then
		local keep
		for _, b in ipairs(bundles) do
			if b.stops[1].key == old.key then keep = b break end
		end
		if keep then
			local held = Build(bundles, start, keep)
			local working = keep.stops[1].kind == "objective" and D(start, keep.stops[1]) <= WORKING_YARDS
			if working or plan.rate <= held.rate * KEEP_MARGIN then plan = held end
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
				ns.Duration(self.plan.seconds), ns.Comma(self.plan.value), ns.Comma(self.plan.rate)))
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
		ns.Comma(plan.value), ns.Comma(plan.rate)))
	for i, s in ipairs(plan.stops) do
		local title = s.e and (s.e.title or "?") or "?"
		local what = s.kind == "objective" and "do" or s.predicted and "then turn in" or s.kind == "turnin" and "turn in" or "pick up"
		DEFAULT_CHAT_FRAME:AddMessage(string.format("   %d. %s: %s", i, what, title))
	end
	if #plan.skipped > 0 then
		DEFAULT_CHAT_FRAME:AddMessage("   Not on this route (too far or too little XP for the time): " .. #plan.skipped .. " quest(s).")
	end
end, "/nq route - list the planned route in chat")
