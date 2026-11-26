-- NeverQuest Guide: live step-by-step guide, zone suggestions, scripted guides and the route recorder.

local ADDON, ns = ...
local G = {}
ns.Guide = G

G.steps = {}        -- what the Guide tab shows right now
G.registered = {}   -- guides shipped in Guides\*.lua files

G.ICONS = {
	-- "?" is for handing in and "!" for picking up, as everywhere else in the game. Work to do
	-- never uses either (see the icons in Core.lua).
	turnin = "QuestTurnin", pickup = "QuestNormal", objective = ns.ICON_DO,
	accept = "QuestNormal", complete = ns.ICON_DO,
	["goto"] = "Waypoint-MapPin-Tracked", fly = "FlightMaster", travel = "Innkeeper",
	level = "questlog-questtypeicon-heroic", note = "minimap-genericevent-hornicon",
	zone = "Waypoint-MapPin-Tracked", tip = "minimap-genericevent-hornicon",
	grind = "questlog-questtypeicon-heroic", train = "Class", vendor = "Vendor",
	bind = "Innkeeper", flightmaster = "FlightMaster",
}

local QUEST_KINDS = { accept = true, turnin = true, complete = true, level = true, grind = true }
local MANUAL_KINDS = { ["goto"] = true, fly = true, travel = true, note = true,
	train = true, vendor = true, bind = true, flightmaster = true }
-- Steps finished by visiting an NPC: the matching window opening ticks them off.
local VISIT_KINDS = { train = true, vendor = true, bind = true, flightmaster = true }

---------------------------------------------------------------------------
-- Live guide
---------------------------------------------------------------------------
function G:MakeStep(kind, e)
	local cfg = ns.db.guide
	local s = { kind = kind, questID = e.questID, dist = e.dist, xp = e.xp, key = kind .. ":" .. e.questID }
	if e.pos then
		s.m, s.x, s.y = e.pos.m, e.pos.x, e.pos.y
	elseif e.x then
		s.m, s.x, s.y = e.m, e.x, e.y
	end
	s.color = { ns.QuestColor(e.questID) }
	local tag = e.level and ("[" .. e.level .. (e.elite and "+" or "") .. "] ") or ""
	local parts = {}
	local catchupNote = ns.Catchup and ns.Catchup:Note(e.questID, kind)
	if catchupNote then table.insert(parts, "|cff66ccff" .. catchupNote .. "|r") end
	if kind == "turnin" then
		s.title = "Turn in: " .. tag .. e.title
		if e.knownSpot and e.pos and e.pos.known then
			-- Handed in at an object, often in another zone: say what to click and how to get there.
			table.insert(parts, "at the " .. e.pos.label .. ", " .. e.pos.zone)
			table.insert(parts, "|cffbbbbbb" .. e.pos.how .. "|r")
		else
			local t = e.turnin
			s.npc = ns.Quests:TurnInName(e.questID) or (t and t.npc)
			if s.npc then table.insert(parts, "to " .. s.npc) end
			local where = (t and t.source ~= "giver" and (t.zone or (t.m and ns.Nav.MapName(ns.Nav.GetZoneMap(t.m))))) or e.zone
			if where then table.insert(parts, where) end
			if not s.m and t and t.m then s.m, s.x, s.y = t.m, t.x, t.y end
			if t and not e.pos then
				if t.source == "zone" then
					table.insert(parts, "|cff999999somewhere in " .. t.zone .. "|r")
				elseif t.source == "giver" then
					table.insert(parts, "|cff999999guess: where you picked it up|r")
				elseif t.source == "unknown" then
					table.insert(parts, "|cff999999where they are isn't known yet|r")
				end
			end
			if not s.m and e.noObjectives then
				table.insert(parts, "|cff999999no map marker: the quest text is your only guide|r")
			end
		end
	elseif kind == "pickup" then
		s.title = "Pick up: " .. tag .. e.title
		local dungeonNote = ns.Dungeons and ns.Dungeons:Note(e.questID)
		if dungeonNote then table.insert(parts, "|cffd8a8ff" .. dungeonNote .. "|r") end
		s.npc = ns.Quests:GiverName(e.questID)
		if s.npc then table.insert(parts, "from " .. s.npc) end
		if e.ahead then table.insert(parts, "|cff99ccffnext zone on your route: " .. (ns.Nav.MapName(ns.Nav.GetZoneMap(e.m)) or "ahead") .. "|r") end
		if e.important then table.insert(parts, "story") end
	else
		s.title = tag .. e.title
		s.icon = ns.ObjectiveIcon(e)
		local dungeonNote = ns.Dungeons and ns.Dungeons:Note(e.questID)
		if dungeonNote then table.insert(parts, "|cffd8a8ff" .. dungeonNote .. "|r") end
		table.insert(parts, e.objective or "Complete the objectives")
		if e.pos and e.pos.spawn and e.pos.label then
			table.insert(parts, "|cffffd070known spot: " .. e.pos.label .. "|r")
		elseif ns.Quests:Inside(e) then
			-- Nothing to walk to: the marker (if any) is the NPC it's handed to. Not for the arrow.
			s.npcOnly, s.inside, s.noAuto = true, true, true
			table.insert(parts, "|cff999999done inside the " .. (ns.Quests:Kind(e.questID) or "dungeon"):lower() .. ": on the route once it's finished|r")
		elseif e.pos and e.pos.npc then
			s.npcOnly = true
			table.insert(parts, "|cff999999the map only marks the quest NPC; NeverQuest learns the objective area as you play|r")
		end
		local party = cfg.partyInSteps and ns.Party and ns.Party:Summary(e.questID)
		if party then table.insert(parts, "|cff66ccffparty: " .. party .. "|r") end
	end
	local chain = cfg.chains and ((ns.Chains and ns.Chains:Label(e.questID)) or (ns.QuestSpots and ns.QuestSpots:ChainLabel(e)))
	if chain then table.insert(parts, "|cffc8a2ff" .. chain .. "|r") end
	if cfg.viaInSteps and e.leg and e.leg.text then table.insert(parts, "|cff99ccffvia: " .. e.leg.text .. "|r") end
	if cfg.xpInSteps and e.xp and e.xp > 0 then table.insert(parts, "+" .. ns.Comma(e.xp) .. " XP") end
	if e.trivial then table.insert(parts, "|cff999999gray: low XP|r") end
	if e.elite then table.insert(parts, "|cffff8040elite|r") end
	if e.group then table.insert(parts, "|cffff8040group " .. e.group .. "|r") end
	if (e.elite or e.group) and not e.complete and not IsInGroup() then table.insert(parts, "|cff999999Ctrl-click: ask for a group|r") end
	s.sub = table.concat(parts, "  ·  ")
	s.right = e.dist and ns.Yards(e.dist) or (s.m and "" or "|cff888888no map pin|r")
	return s
end

-- Simple ordering: what's next to you, then best XP per distance. Used when route planning is
-- off or there's no plan (no position, instances).
function G:BuildSimple(steps)
	local cfg = ns.db.guide
	local near = cfg.nearbyYards or 200
	local turnins, objectives, pickups, inside = {}, {}, {}, {}
	local AD = ns.Advisor
	local function Skipped(qid) return AD and AD:IsSkipped(qid) end
	for _, e in ipairs(ns.Quests.log) do
		if Skipped(e.questID) then
			-- Skipped: on the missed list, not in the guide.
		elseif e.complete then
			table.insert(turnins, e)
		elseif ns.Quests:Inside(e) then
			-- Done inside a dungeon: listed last, never where the arrow goes.
			table.insert(inside, e)
		elseif not e.failed then
			table.insert(objectives, e)
		end
	end
	for _, o in ipairs(ns.Quests.offers) do
		if ns.Quests:OfferShown(o, true) and not Skipped(o.questID) then table.insert(pickups, o) end
	end

	local function ByDistance(a, b) return (a.dist or 1e9) < (b.dist or 1e9) end
	table.sort(turnins, ByDistance)
	-- Quest givers that start chains come first among those at a similar distance.
	local function PickupScore(o)
		local _, ups = 0, 0
		if ns.Chains and cfg.chains then _, ups = ns.Chains:Value(o.questID, o.xp) end
		return (o.dist or 1e9) / (1 + 0.5 * ups)
	end
	for _, o in ipairs(pickups) do o.pscore = PickupScore(o) end
	table.sort(pickups, function(a, b) return a.pscore < b.pscore end)

	-- XP per yard, boosted for quests that are nearly done and for quests that open up
	-- follow-ups; gray, elite and group quests rank lower.
	local focus = self:Focus()
	for _, e in ipairs(objectives) do
		local xp = (e.xp and e.xp > 0) and e.xp or 150
		if ns.Chains and cfg.chains then xp = xp + ns.Chains:Value(e.questID, xp) end
		xp = xp * ns.Profiles:ZoneWeight(ns.Quests:ZoneOf(e), focus, false)
		local remaining = math.max(0.15, 1 - (e.progress or 0))
		e.score = xp / ((e.dist or 2500) + 250) / remaining
		if e.trivial then e.score = e.score * 0.15 end
		if e.elite or e.group then e.score = e.score * 0.6 end
	end
	table.sort(objectives, function(a, b) return a.score > b.score end)

	-- 1. Anything to hand in or pick up right next to you.
	local used, nearby = {}, {}
	if cfg.nearbyFirst then
		for _, e in ipairs(turnins) do
			if e.dist and e.dist <= near then table.insert(nearby, { e = e, kind = "turnin" }); used[e] = true end
		end
		for _, o in ipairs(pickups) do
			if o.dist and o.dist <= near then table.insert(nearby, { e = o, kind = "pickup" }); used[o] = true end
		end
		table.sort(nearby, function(a, b) return a.e.dist < b.e.dist end)
	end
	for _, n in ipairs(nearby) do table.insert(steps, self:MakeStep(n.kind, n.e)) end

	-- 1b. Plan milestones that are due (class quests, talents, riding) and trainer visits.
	for _, row in ipairs(self:MilestoneSteps()) do table.insert(steps, row) end

	-- 2. Objectives, best XP per distance first.
	for _, e in ipairs(objectives) do table.insert(steps, self:MakeStep("objective", e)) end

	-- 3. Turn-ins further away, nearest first.
	for _, e in ipairs(turnins) do
		if not used[e] then table.insert(steps, self:MakeStep("turnin", e)) end
	end

	-- 4. A few more quest givers in this zone.
	local count = 0
	for _, o in ipairs(pickups) do
		if not used[o] and count < (cfg.maxOffers or 4) then
			table.insert(steps, self:MakeStep("pickup", o))
			count = count + 1
		end
	end

	-- 5. Dungeon quests still to do: for the run, not for the walk.
	for _, e in ipairs(inside) do
		local s = self:MakeStep("objective", e)
		s.later = true
		s.sub = "|cff999999later:|r " .. (s.sub or "")
		table.insert(steps, s)
	end
end

-- Planned ordering (Planner.lua): one route through objectives, turn-ins and pickups.
function G:BuildPlanned(steps, plan)
	local cfg = ns.db.guide
	for _, row in ipairs(self:MilestoneSteps()) do table.insert(steps, row) end
	local onRoute = {}
	local n = 0
	for _, stop in ipairs(plan.stops) do
		onRoute[stop.e] = true
		if not stop.predicted or cfg.showPredicted then
			local s = self:MakeStep(stop.kind, stop.e)
			s.m, s.x, s.y = stop.m, stop.x, stop.y
			n = n + 1
			s.plan = n
			if stop.help then
				s.key = stop.key
				s.title = "Help " .. stop.help:gsub(" %d+%%", "") .. ": " .. (stop.e.title or "")
				s.sub = "Party catch-up: they still need this one (" .. stop.help .. "). Hand it in together."
				s.color = { 0.4, 0.8, 1 }
			elseif stop.predicted then
				s.predicted = true
				s.key = stop.key
				s.title = s.title:gsub("^Turn in: ", "Then turn in: ")
				s.color = { 0.65, 0.65, 0.65 }
				local d = ns.Nav.Distance(stop.m, stop.x, stop.y)
				s.right = d and ns.Yards(d) or ""
			elseif stop.kind == "turnin" and not stop.e.dist then
				local d = ns.Nav.Distance(stop.m, stop.x, stop.y)
				s.right = d and ns.Yards(d) or s.right
			end
			table.insert(steps, s)
		end
	end
	if cfg.routeSummary and #plan.stops > 0 then
		table.insert(steps, { kind = "tip", key = "tip:route",
			title = string.format("Route: %d stops, ~%s", #plan.stops, ns.Duration(plan.seconds)),
			sub = string.format("~%s XP for the trip (about %s XP/hour)%s", ns.Comma(plan.xp or plan.value), ns.Comma(plan.xpRate or plan.rate),
				#plan.skipped > 0 and ("  ·  " .. #plan.skipped .. " quest(s) left for later") or ""),
			color = { 0.6, 0.85, 1 } })
	end
	-- Quests the route leaves out: too far, another continent, or too little XP for the time.
	-- A finished quest is the exception. It is already earned, so it is never filed under
	-- "later" just because NeverQuest has not learned where it is handed in: those go above
	-- the route, with the zone the game says to go to, so you are not flown out past them.
	local hereZone, hereMap
	do
		local m = ns.SafeCall(C_Map.GetBestMapForUnit, "player")
		hereMap = m and ns.Nav.GetZoneMap(m) or nil
		hereZone = hereMap and ns.Nav.MapName(hereMap) or nil
	end
	local waiting = {}
	local AD = ns.Advisor
	for _, e in ipairs(ns.Quests.log) do
		if not onRoute[e] and not e.failed and (cfg.showGray or e.complete or not e.trivial)
			and not (AD and AD:IsSkipped(e.questID)) then
			local s = self:MakeStep(e.complete and "turnin" or "objective", e)
			if e.complete then
				-- MakeStep already explains what is known (who to hand it to, which zone), so
				-- that is left alone; all this does is stop it being buried under "later".
				-- The spot these carry is usually just the middle of a zone, which is no use to
				-- the arrow: it would point at open countryside instead of at real work. So the
				-- arrow never picks one on its own. Clicking the row still points it there.
				s.color = { 0.4, 1, 0.5 }
				s.noAuto = true
				table.insert(waiting, { step = s, here = hereZone ~= nil and ns.Quests:ZoneOf(e) == hereZone })
			else
				s.later = true
				local ql = ns.Num(e.level)
				if ns.Planner and ns.Planner.TooHigh and ns.Planner.TooHigh(ql) then
					-- Too high for now: on the route once you're within a few levels of it.
					s.sub = string.format("|cff999999later:|r level %d, too high for now: on the route from level %d", ql, ql - ns.Planner.TOO_HIGH)
				else
					s.sub = "|cff999999later:|r " .. (s.sub or "")
				end
				table.insert(steps, s)
			end
		end
	end
	-- Ones waiting in the zone you are standing in come first: handing those in before you
	-- leave is free XP, and the route can't tell you to because it doesn't know the spot.
	table.sort(waiting, function(a, b)
		if a.here ~= b.here then return a.here end
		return (a.step.title or "") < (b.step.title or "")
	end)
	local hereCount = 0
	for _, w in ipairs(waiting) do if w.here then hereCount = hereCount + 1 end end
	-- They go above the first step that takes you out of this zone, and below everything still
	-- in it. Handing them in before you travel is free XP; dropping what you are standing next
	-- to for one is not.
	local at = #steps + 1
	if hereMap then
		for i, st in ipairs(steps) do
			if st.m and ns.Nav.GetZoneMap(st.m) ~= hereMap then at = i break end
		end
	end
	for i = #waiting, 1, -1 do table.insert(steps, at, waiting[i].step) end
	-- The notice goes to the top so you can't travel without seeing it, but the quests
	-- themselves stay below the route: they are worth knowing about, not worth dropping
	-- whatever you are standing next to for. It carries no spot, so the arrow ignores it.
	if hereCount > 0 then
		table.insert(steps, 1, { kind = "tip", key = "tip:handin",
			title = hereCount == 1 and "1 finished quest waiting in this zone"
				or (hereCount .. " finished quests waiting in this zone"),
			sub = "Hand these in before you travel: the XP is already earned. NeverQuest doesn't know the spot, so they aren't on the route.",
			color = { 0.4, 1, 0.5 } })
	end
	-- A few more quest givers nearby that aren't on the route.
	local offers = {}
	for _, o in ipairs(ns.Quests.offers) do
		if not onRoute[o] and ns.Quests:OfferShown(o, true) and not (AD and AD:IsSkipped(o.questID)) then table.insert(offers, o) end
	end
	table.sort(offers, function(a, b) return (a.dist or 1e9) < (b.dist or 1e9) end)
	for i = 1, math.min(#offers, cfg.maxOffers or 4) do
		local s = self:MakeStep("pickup", offers[i])
		s.later = true
		table.insert(steps, s)
	end
end

function G:BuildLive()
	local steps, cfg = {}, ns.db.guide
	self.focusTick = (self.focusTick or 0) + 1
	local plan = cfg.planner and ns.Planner and ns.Planner:Get()
	if plan and #plan.stops > 0 then
		self:BuildPlanned(steps, plan)
	else
		self:BuildSimple(steps)
	end
	self.livePlan = plan

	-- The attunement you follow: first once you're at the level cap, otherwise right after your
	-- next leveling step.
	local level = UnitLevel("player")
	local attune = ns.Attune and ns.Attune:GuideStep()
	if attune then
		local atCap = ns.XP and ns.XP.IsMaxLevel and ns.XP:IsMaxLevel()
		table.insert(steps, (atCap or level >= 60 or #steps == 0) and 1 or 2, attune)
	end

	-- Zone advice when this zone has nothing worthwhile left.
	local useful, open = 0, 0
	for _, e in ipairs(ns.Quests.log) do
		if e.complete then useful = useful + 1
		elseif not e.failed then
			open = open + 1
			if not e.trivial then useful = useful + 1 end
		end
	end
	for _, o in ipairs(ns.Quests.offers) do if not o.trivial and o.difficulty ~= 4 then useful = useful + 1 end end
	local zone = self:CurrentZoneLevels()
	if cfg.outleveledTip and zone and level > zone.max + 1 then
		table.insert(steps, { kind = "tip", key = "tip:outleveled",
			title = "You've outleveled " .. zone.name,
			sub = string.format("Zone is levels %d-%d; quests here give reduced XP.", zone.min, zone.max) })
	end
	if self:PlanActive() then
		self:MoveOnStep(steps)
	end
	if ns.Catchup and ns.Catchup:Active() then ns.Catchup:Steps(steps) end
	if not self:PlanActive() and cfg.zoneAdvice and (useful == 0 or (zone and level > zone.max + 1)) then
		for _, z in ipairs(self:SuggestZones(3)) do table.insert(steps, z) end
	end

	-- Hearthstone (first: it replaces a long walk) and a flight path here you don't have yet
	-- (right after your next step when it's close, otherwise with the tips).
	local hearth, flight = nil, nil
	if ns.Travel then hearth, flight = ns.Travel:GuideRows() end
	if hearth then table.insert(steps, 1, hearth) end
	if flight and flight.near then table.insert(steps, math.min(#steps + 1, hearth and 3 or 2), flight) end

	-- Where the 1-60 plan has you now, and dungeons worth running at this level.
	for _, row in ipairs(self:PlanInfoSteps(level)) do table.insert(steps, row) end
	local attuneTip = ns.Attune and ns.Attune:GuideTip(level)
	if attuneTip then table.insert(steps, attuneTip) end
	if flight and not flight.near then table.insert(steps, flight) end
	-- Full quest log, supplies, bag space.
	if ns.Upkeep then
		for _, row in ipairs(ns.Upkeep:Tips(level)) do table.insert(steps, row) end
	end
	-- Quests you chose to go back for, ones worth dropping, the missed list and the best zones.
	if ns.Advisor then ns.Advisor:GuideRows(steps, plan) end

	-- Rested reminder.
	local rested = ns.Num(GetXPExhaustion())
	if cfg.restedTip and rested and rested > 0 and open > 0 then
		table.insert(steps, { kind = "tip", key = "tip:rested",
			title = "Rested: " .. ns.Comma(rested) .. " XP banked",
			sub = "Kills give double XP until it runs out. Turn-ins don't use it." })
	end

	if #steps == 0 then
		table.insert(steps, { kind = "tip", key = "tip:empty", title = "Nothing to do here yet",
			sub = "Open the world map for a moment so this zone's quests load, or check the Nearby tab." })
	end
	return steps
end

---------------------------------------------------------------------------
-- 1-60 plan (Profiles.lua) in the live guide
---------------------------------------------------------------------------
function G:PlanActive()
	return ns.Profiles and ns.db.guide.profile
end

-- Where your leveling style wants you right now (Profiles:Focus), worked out once per refresh.
function G:Focus()
	if not self:PlanActive() then return nil end
	local level = UnitLevel("player")
	-- Party catch-up can plan zones for the lowest level in the party.
	if ns.Catchup then level = ns.Catchup:PlanLevel(level) end
	local key = string.format("%d:%s:%d:%d", level, ns.Profiles:Style(), ns.Quests.offerMap or 0, self.focusTick or 0)
	if self.focusKey ~= key then
		self.focusKey = key
		local all = ns.Advisor and ns.Advisor:Completionist() and function(name) return ns.Quests:ZoneWork(name, true) end or nil
		self.focus = ns.Profiles:Focus(ns.Profiles:Mine(), level, function(name) return ns.Quests:ZoneWork(name) end, all)
		-- Optimized: the zone with the most XP per hour for you, from the quest data.
		if ns.Advisor then ns.Advisor:ApplyZones(self.focus, level) end
	end
	return self.focus
end

-- "Head to <zone>" when your style says it's time to go, placed after anything you can hand
-- in or pick up right where you stand.
function G:MoveOnStep(steps)
	local f = self:Focus()
	if not f or not f.moveOn or not f.primaryID or not ns.db.guide.zoneAdvice then return end
	local title
	if f.style == "optimized" then
		title = "Time to move on: head to " .. f.primary
	elseif f.zoneDone then
		title = "Zone done: head to " .. f.primary
	else
		title = "Head to " .. f.primary
	end
	local sub = f.reason
	local waiting = ns.QuestDB and ns.QuestDB:OpenCount(f.primaryID) or 0
	if waiting > 0 then
		sub = sub .. string.format(" %d %s open to you there.", waiting, waiting == 1 and "quest" or "quests")
	end
	local step = { kind = "zone", key = "zone:" .. f.primaryID, m = f.primaryID, x = 0.5, y = 0.5,
		title = title, navTitle = f.primary, sub = sub, color = { 0.6, 1, 0.6 }, moveOn = true }
	local at = 1
	while steps[at] and (steps[at].milestoneKey or ((steps[at].kind == "turnin" or steps[at].kind == "pickup")
		and not steps[at].predicted and steps[at].dist and steps[at].dist <= 300)) do
		at = at + 1
	end
	table.insert(steps, at, step)
end

-- Zones from your plan, for when this zone runs dry or you've outleveled it.
function G:ProfileZoneSteps(level, n)
	if not self:PlanActive() then return nil end
	local P = ns.Profiles
	local plan = P:Mine()
	local band = P:BandFor(plan, level)
	local out = {}
	local function Add(b, label)
		if not b then return end
		for _, z in ipairs(P:UsableZones(b, level)) do
			if #out >= n then return end
			if z.id and not z.here then
				table.insert(out, { kind = "zone", key = "zone:" .. z.id, m = z.id, x = 0.5, y = 0.5,
					title = "Head to " .. z.name, navTitle = z.name,
					sub = string.format("Your plan%s: levels %d-%d%s", label, z.min or 0, z.max or 0, b.note and ("  ·  " .. b.note) or "") })
			end
		end
	end
	Add(band, "")
	local nextBand = P:NextBand(plan, band)
	if #out < n and nextBand and level >= nextBand.from - 2 then Add(nextBand, " (next)") end
	return #out > 0 and out or nil
end

function G:MilestoneSteps()
	local rows = {}
	if not self:PlanActive() or not ns.db.guide.milestones then return rows end
	local P = ns.Profiles
	local level = UnitLevel("player")
	local due = P:DueMilestones(P:Mine(), level)
	for _, ms in ipairs(due) do
		table.insert(rows, { kind = ms.class and "train" or "level", key = "ms:" .. ms.key, milestoneKey = ms.key,
			title = string.format("Level %d: %s", ms.level, ms.text),
			sub = "Click when it's done to hide this.", color = { 0.6, 0.85, 1 } })
	end
	if level >= 4 and level % 2 == 0 and (ns.char.trainedLevel or 0) < level then
		table.insert(rows, { kind = "train", key = "tip:trainer:" .. level,
			title = "New abilities at your class trainer (level " .. level .. ")",
			sub = "Ranks come every even level. This clears when you visit a trainer.", color = { 0.6, 0.85, 1 } })
	end
	return rows
end

function G:PlanInfoSteps(level)
	local rows = {}
	if not self:PlanActive() then return rows end
	local P = ns.Profiles
	local plan = P:Mine()
	local band = P:BandFor(plan, level)
	if P:Style() == "optimized" then
		local leg = P:LegFor(plan, level)
		local nextLeg = leg and P:NextLeg(plan, leg)
		if leg then
			table.insert(rows, { kind = "tip", key = "tip:plan", openPlan = true,
				title = string.format("Optimized route: %s (levels %d-%d)", leg.zone, leg.from, leg.to),
				sub = (nextLeg and string.format("Then %s at %d. ", nextLeg.zone, nextLeg.from) or "") .. "Click to see the whole route." })
		end
		band = nil
	end
	if band then
		local nextBand = P:NextBand(plan, band)
		local text = table.concat(band.zones, " or ", 1, math.min(2, #band.zones))
		table.insert(rows, { kind = "tip", key = "tip:plan", openPlan = true,
			title = string.format("Zone by zone: %s (levels %d-%d)", text, band.from, band.to),
			sub = (nextBand and nextBand ~= band and nextBand.zones[1] ~= band.zones[1])
				and string.format("Then %s at %d. Click to see the whole 1-60 plan.", nextBand.zones[1], nextBand.from)
				or "Click to see the whole 1-60 plan." })
	end
	if ns.db.guide.dungeonTips then
		local names = {}
		for _, d in ipairs(P:DungeonsFor(plan, level)) do table.insert(names, d.name) end
		if #names > 0 then
			table.insert(rows, { kind = "dungeon", icon = "Dungeon", key = "tip:dungeons",
				title = "Dungeons for your level: " .. table.concat(names, ", ", 1, math.min(3, #names)),
				sub = "Good XP and quest rewards with a group right now.", openPlan = true })
		end
	end
	-- Dungeon quests being gathered (Dungeons.lua): one row per dungeon coming up.
	local DQ = ns.Dungeons
	if DQ and DQ:On() then
		for _, row in ipairs(DQ:Plan().rows) do
			if row.active and (row.open + row.pre + row.inLog) > 0 then
				local parts = {}
				if row.open > 0 then table.insert(parts, row.open .. " to pick up") end
				if row.pre > 0 then table.insert(parts, row.pre .. " behind a pre-quest") end
				if row.inLog > 0 then table.insert(parts, row.inLog .. " in your log") end
				table.insert(rows, { kind = "dungeon", icon = "Dungeon", key = "tip:dq:" .. row.name, openDungeons = true,
					title = string.format("%s quests: %s", row.name, table.concat(parts, ", ")),
					sub = string.format("Picked up before you run it (levels %d-%d). Click to choose which dungeons.", row.from, row.to),
					color = { 0.85, 0.7, 1 } })
			end
		end
	end
	return rows
end

ns:RegisterEvent("TRAINER_SHOW", function() ns.Debounce("guiderefresh", 0.5, function() G:Refresh() end) end)

---------------------------------------------------------------------------
-- Zone suggestions (from the game's own zone level ranges)
---------------------------------------------------------------------------
local zoneLevels

function G:ZoneData()
	if zoneLevels then return zoneLevels end
	zoneLevels = {}
	local seen = {}
	for _, id in ipairs(ns.Nav.GetZoneList()) do
		local minL, maxL = C_Map.GetMapLevels(id)
		minL, maxL = ns.Num(minL), ns.Num(maxL)
		local info = C_Map.GetMapInfo(id)
		if minL and maxL and minL > 0 and maxL >= minL and info and not seen[info.name] then
			seen[info.name] = true
			local cont = ns.Nav.GetContinentMap(id)
			table.insert(zoneLevels, { id = id, min = minL, max = maxL, name = info.name,
				continent = cont, continentName = cont and ns.Nav.MapName(cont) or "" })
		end
	end
	return zoneLevels
end

function G:CurrentZoneLevels()
	local m = C_Map.GetBestMapForUnit("player")
	m = m and ns.Nav.GetZoneMap(m)
	if not m then return end
	local minL, maxL = C_Map.GetMapLevels(m)
	minL, maxL = ns.Num(minL), ns.Num(maxL)
	if minL and maxL and minL > 0 then
		return { id = m, min = minL, max = maxL, name = ns.Nav.MapName(m) }
	end
end

function G:SuggestZones(n)
	local level = UnitLevel("player")
	local here = C_Map.GetBestMapForUnit("player")
	local hereZone = here and ns.Nav.GetZoneMap(here)
	local hereCont = here and ns.Nav.GetContinentMap(here)
	local list = {}
	for _, z in ipairs(self:ZoneData()) do
		if z.min <= level + 1 and z.max >= level and z.id ~= hereZone then
			local score = math.abs((z.min + z.max) / 2 - level)
			if z.continent ~= hereCont then score = score + 6 end
			table.insert(list, { z = z, score = score })
		end
	end
	table.sort(list, function(a, b) return a.score < b.score end)
	local out = {}
	for i = 1, math.min(n, #list) do
		local z = list[i].z
		table.insert(out, { kind = "zone", key = "zone:" .. z.id, m = z.id, x = 0.5, y = 0.5,
			title = "Head to " .. z.name,
			sub = string.format("Levels %d-%d  ·  %s  ·  check it's your faction's zone", z.min, z.max, z.continentName),
			navTitle = z.name })
	end
	return out
end

---------------------------------------------------------------------------
-- Scripted guides
---------------------------------------------------------------------------
function G:FindGuide(name)
	return name and (ns.db.guides[name] or self.registered[name]) or nil
end

function G:GetScript()
	local guide = self:FindGuide(ns.char.script.name)
	if ns.char.script.name and not guide then ns.char.script.name = nil end
	return guide
end

function G:AllGuides()
	local list = {}
	for name, guide in pairs(self.registered) do table.insert(list, { name = name, guide = guide, builtin = true }) end
	for name, guide in pairs(ns.db.guides) do table.insert(list, { name = name, guide = guide }) end
	table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
	return list
end

function G:StepDone(s, index)
	local t = s.t
	if t == "accept" then
		return C_QuestLog.IsOnQuest(s.q) or C_QuestLog.IsQuestFlaggedCompleted(s.q)
	elseif t == "turnin" then
		return C_QuestLog.IsQuestFlaggedCompleted(s.q)
	elseif t == "complete" then
		return C_QuestLog.IsQuestFlaggedCompleted(s.q) or (C_QuestLog.IsOnQuest(s.q) and C_QuestLog.IsComplete(s.q))
	elseif t == "level" then
		return UnitLevel("player") >= (s.lv or 0)
	elseif t == "grind" then
		local level = UnitLevel("player")
		if level ~= (s.lv or 0) then return level > (s.lv or 0) end
		local cur, max = ns.Num(UnitXP("player")) or 0, ns.Num(UnitXPMax("player")) or 1
		return max > 0 and cur / max * 100 >= (s.pct or 0)
	elseif VISIT_KINDS[t] then
		return index ~= nil and ns.char.script.flags[index] == true
	elseif (t == "goto" or t == "fly" or t == "travel") and s.m and s.x then
		local d = ns.Nav.Distance(s.m, s.x, s.y)
		return d ~= nil and d <= (t == "goto" and 15 or 60)
	end
	return false
end

-- A manual step (note, flight, travel) is treated as done once you've clearly moved past it.
local function LaterQuestStepDone(steps, i, lookahead)
	for j = i + 1, math.min(#steps, i + lookahead) do
		local s = steps[j]
		if QUEST_KINDS[s.t] and s.t ~= "level" and s.t ~= "grind" and G:StepDone(s, j) then return true end
	end
	return false
end

function G:Advance()
	local guide = self:GetScript()
	if not guide or self.hold then return end
	local steps, i = guide.steps, ns.char.script.step or 1
	while steps[i] do
		local s = steps[i]
		if self:StepDone(s, i) or (MANUAL_KINDS[s.t] and LaterQuestStepDone(steps, i, 4)) then
			i = i + 1
		else
			break
		end
	end
	if i ~= ns.char.script.step then
		ns.char.script.step = i
		ns.PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
		ns.Debug("guide advanced to step " .. i)
	end
end

-- On load, jump to just after the furthest quest step you've already done.
function G:FastForward()
	local guide = self:GetScript()
	if not guide then return end
	local last = 0
	for i, s in ipairs(guide.steps) do
		if QUEST_KINDS[s.t] and self:StepDone(s, i) then last = i end
	end
	ns.char.script.step = math.max(ns.char.script.step or 1, last + 1)
	self:Advance()
end

function G:LoadScript(name)
	if not self:FindGuide(name) then return ns.Print("no guide named '" .. tostring(name) .. "'.") end
	ns.char.script.name, ns.char.script.step = name, 1
	ns.char.script.flags = {}
	self.pinnedKey, self.hold = nil, nil
	self:FastForward()
	ns.Print("loaded guide: " .. name .. " (step " .. ns.char.script.step .. ").")
	self:Refresh()
end

function G:UseLive()
	ns.char.script.name = nil
	self.pinnedKey = nil
	ns.Nav:SetGuideTarget(nil)
	self:Refresh()
end

-- Back holds the guide on the chosen step until you press Skip or make real progress.
function G:StepBack()
	if not self:GetScript() then return end
	ns.char.script.step = math.max(1, (ns.char.script.step or 1) - 1)
	self.hold = true
	self:Refresh(true)
end

-- Skip: in a scripted guide, the next step. In the live guide, the step the arrow is on: a
-- quest is skipped (off the route, onto the missed list; Advisor.lua) and anything else is
-- dismissed from the arrow, which moves on to the next step.
function G:StepSkip()
	local guide = self:GetScript()
	if not guide then
		local key = ns.Nav.guideTarget and ns.Nav.guideTarget.key
		local step
		for _, s in ipairs(self.steps) do
			if s.key == key then step = s break end
		end
		step = step or self.steps[1]
		if not step then return end
		self.pinnedKey = nil
		if step.questID and ns.Advisor then
			ns.Advisor:Skip(step.questID)
		else
			ns.Nav.dismissedKey = step.key
			self:Refresh(true)
		end
		return
	end
	ns.char.script.step = math.min(#guide.steps + 1, (ns.char.script.step or 1) + 1)
	self.hold = nil
	self:Refresh(true)
end

local function ReleaseHold() G.hold = nil end

-- Opening a trainer, vendor, innkeeper bind or flight map ticks off the matching step if it's
-- the current one or one of the next two.
function G:MarkVisit(kind)
	local guide = self:GetScript()
	if not guide then return end
	local cur = ns.char.script.step or 1
	for i = cur, math.min(#guide.steps, cur + 2) do
		local s = guide.steps[i]
		if s.t == kind and not ns.char.script.flags[i] then
			ns.char.script.flags[i] = true
			self.hold = nil
			self:Refresh()
			return
		end
	end
end
ns:RegisterEvent("QUEST_ACCEPTED", ReleaseHold)
ns:RegisterEvent("QUEST_TURNED_IN", ReleaseHold)
ns:RegisterEvent("PLAYER_LEVEL_UP", ReleaseHold)
ns:RegisterMessage("QUEST_READY", ReleaseHold)

function G:ScriptDisplay(s, index, current)
	local d = { kind = s.t, key = "script:" .. index, index = index, current = current, m = s.m, x = s.x, y = s.y }
	local name = s.title or (s.q and C_QuestLog.GetTitleForQuestID(s.q)) or (s.q and ("Quest " .. s.q)) or ""
	if s.t == "accept" then
		d.title = "Accept: " .. name
	elseif s.t == "turnin" then
		d.title, d.questID = "Turn in: " .. name, s.q
	elseif s.t == "complete" then
		d.title, d.questID = "Complete: " .. name, s.q
		local e = ns.Quests.byID[s.q]
		if e and e.objective and not e.complete then d.sub = e.objective end
	elseif s.t == "level" then
		d.title = "Reach level " .. (s.lv or "?")
	elseif s.t == "fly" then
		d.title = s.note or "Take the flight path"
	elseif s.t == "travel" then
		d.title = s.note or "Hearth or travel"
	elseif s.t == "goto" then
		d.title = s.note or "Go to the marked spot"
	elseif s.t == "grind" then
		d.title = string.format("Grind to level %d (%d%%)", s.lv or 0, s.pct or 0)
		if s.note then d.sub = s.note end
	elseif s.t == "train" then
		d.title = s.note or "Visit your trainer"
	elseif s.t == "vendor" then
		d.title = s.note or "Sell and restock"
	elseif s.t == "bind" then
		d.title = s.note or "Set your hearthstone here"
	elseif s.t == "flightmaster" then
		d.title = s.note or "Get the flight path"
	else
		d.title = s.note or "Note"
	end
	if s.npc then
		d.npc = s.npc
		d.sub = (d.sub and (d.sub .. "  ·  ") or "") .. "talk to " .. s.npc
	end
	if s.q then d.color = { ns.QuestColor(s.q) } end
	if not d.sub and s.m and s.x then
		d.sub = string.format("%s  %.1f, %.1f", ns.Nav.MapName(s.m), s.x * 100, s.y * 100)
	end
	if MANUAL_KINDS[s.t] and current then
		d.sub = (d.sub and (d.sub .. "  ·  ") or "") .. "|cffaaaaaaclick Skip when done|r"
	end
	d.right = (s.m and s.x) and ns.Yards(ns.Nav.Distance(s.m, s.x, s.y)) or ""
	return d
end

function G:BuildScriptView(guide)
	local steps, cur = {}, ns.char.script.step or 1
	if cur > #guide.steps then
		table.insert(steps, { kind = "tip", key = "script:done", title = "Guide complete!",
			sub = "Load another guide or switch back to the live guide." })
	end
	for i = cur, math.min(#guide.steps, cur + 11) do
		table.insert(steps, self:ScriptDisplay(guide.steps[i], i, i == cur))
	end
	return steps
end

---------------------------------------------------------------------------
-- Refresh and arrow auto-tracking
---------------------------------------------------------------------------
function G:Pin(step)
	self.pinnedKey = step and step.key or nil
	ns.Nav.dismissedKey = nil
	if step and step.m then
		ns.Nav:SetGuideTarget({ key = step.key, m = step.m, x = step.x, y = step.y,
			title = step.navTitle or step.title, questID = step.questID, arrive = false })
	end
end

function G:AutoTrack()
	if not ns.db.guide.autoTrack then return end
	local pick
	local function Find(key)
		for _, s in ipairs(self.steps) do
			if s.key == key and s.m then return s end
		end
	end
	-- A step you right-clicked off the arrow stays off it, and the arrow moves on to the next
	-- one rather than going blank. Once that step is finished or gone, so is the dismissal:
	-- if it ever comes back it is a new decision.
	local dismissed = ns.Nav.dismissedKey
	if dismissed then
		local still = false
		for _, s in ipairs(self.steps) do
			if s.key == dismissed then still = true break end
		end
		if not still then
			ns.Nav.dismissedKey = nil
			dismissed = nil
		end
	end
	if self:GetScript() then
		pick = self.steps[1] and self.steps[1].current and self.steps[1].m and self.steps[1] or nil
		if self.pinnedKey then pick = Find(self.pinnedKey) or pick end
	else
		if self.pinnedKey then
			pick = Find(self.pinnedKey)
			if not pick then self.pinnedKey = nil end
		end
		-- Keep the current target while it's still one of the top two, so the arrow doesn't flip back and forth.
		local cur = ns.Nav.guideTarget
		if not pick and cur and cur.key ~= dismissed then
			for i = 1, math.min(2, #self.steps) do
				if self.steps[i].key == cur.key and self.steps[i].m and not self.steps[i].noAuto then pick = self.steps[i] break end
			end
		end
		if not pick then
			for _, s in ipairs(self.steps) do
				if s.m and not s.noAuto and s.key ~= dismissed then pick = s break end
			end
		end
	end
	if pick then
		ns.Nav:SetGuideTarget({ key = pick.key, m = pick.m, x = pick.x, y = pick.y,
			title = pick.navTitle or pick.title, questID = pick.questID, arrive = false })
	else
		ns.Nav:SetGuideTarget(nil)
	end
end

function G:Refresh(force)
	if not ns.ready then return end
	local guide = self:GetScript()
	if guide then
		if not force then self:Advance() end
		self.steps = self:BuildScriptView(guide)
	else
		self.steps = self:BuildLive()
	end
	self:AutoTrack()
	ns:SendMessage("GUIDE_UPDATED")
end

for _, msg in ipairs({ "QUESTS_UPDATED", "OFFERS_UPDATED", "DISTANCES_UPDATED" }) do
	ns:RegisterMessage(msg, function() ns.Debounce("guiderefresh", 0.1, function() G:Refresh() end) end)
end
ns:RegisterEvent("PLAYER_LEVEL_UP", function()
	ns.After(1, function() G:Refresh() end)
end)

---------------------------------------------------------------------------
-- Route recorder
---------------------------------------------------------------------------
local function Round(v) return v and math.floor(v * 1000 + 0.5) / 1000 or nil end

function G:IsRecording() return ns.char.recorder.active end

function G:StartRecording(name)
	if self:IsRecording() then return ns.Print("already recording '" .. ns.char.recorder.name .. "'.") end
	local race, class, faction = UnitRace("player"), UnitClass("player"), UnitFactionGroup("player")
	name = (name and name ~= "") and name or string.format("%s %s from %d", race or "?", class or "?", UnitLevel("player"))
	ns.char.recorder = { active = true, name = name, steps = {}, race = race, class = class,
		faction = faction, startLevel = UnitLevel("player") }
	self.lastPos = nil
	ns.Print("recording route '" .. name .. "'. Play normally; /nq stop saves it, /nq note <text> adds a note here.")
	ns:SendMessage("RECORDER_UPDATED")
end

function G:Record(kind, s, noPosition)
	local rec = ns.char.recorder
	if not rec.active then return end
	s = s or {}
	s.t = kind
	if not noPosition and not s.m then
		local m, x, y = ns.Nav.GetPlayerPosition()
		if m then s.m, s.x, s.y = m, Round(x), Round(y) end
	end
	table.insert(rec.steps, s)
	ns:SendMessage("RECORDER_UPDATED")
end

function G:StopRecording()
	local rec = ns.char.recorder
	if not rec.active then return ns.Print("not recording.") end
	ns.char.recorder = { active = false, steps = {} }
	if #rec.steps == 0 then
		ns:SendMessage("RECORDER_UPDATED")
		return ns.Print("nothing was recorded, so nothing was saved.")
	end
	local name = rec.name
	if ns.db.guides[name] or self.registered[name] then name = name .. " " .. date("%m/%d %H:%M") end
	ns.db.guides[name] = { name = name, race = rec.race, class = rec.class, faction = rec.faction,
		minLevel = rec.startLevel, maxLevel = UnitLevel("player"), steps = rec.steps, recorded = true }
	ns.Print(string.format("saved guide '%s' (%d steps). Load it from the Guides tab on another character.", name, #rec.steps))
	ns:SendMessage("RECORDER_UPDATED")
end

ns:RegisterEvent("QUEST_ACCEPTED", function(_, questID)
	if G:IsRecording() and questID then
		G:Record("accept", { q = questID, title = C_QuestLog.GetTitleForQuestID(questID), npc = ns.Quests:LastNPC(10) })
	end
end)

ns:RegisterEvent("QUEST_TURNED_IN", function(_, questID)
	if G:IsRecording() and questID then
		local e = ns.Quests.byID[questID]
		G:Record("turnin", { q = questID, title = (e and e.title) or C_QuestLog.GetTitleForQuestID(questID),
			npc = ns.Quests:LastNPC(10) or ns.Quests:TurnInName(questID) })
	end
end)

ns:RegisterMessage("QUEST_READY", function(_, e)
	if G:IsRecording() then G:Record("complete", { q = e.questID, title = e.title }) end
end)

ns:RegisterEvent("PLAYER_LEVEL_UP", function(_, level)
	if G:IsRecording() then G:Record("level", { lv = level }, true) end
end)

ns:RegisterEvent("PLAYER_CONTROL_LOST", function()
	ns.After(0.5, function()
		if UnitOnTaxi("player") then G.onTaxi = true end
	end)
end)

ns:RegisterEvent("PLAYER_CONTROL_GAINED", function()
	if not G.onTaxi then return end
	G.onTaxi = false
	ns.After(1, function()
		if G:IsRecording() then
			local m = C_Map.GetBestMapForUnit("player")
			G:Record("fly", { note = "Fly to " .. ns.Nav.MapName(m and ns.Nav.GetZoneMap(m)) })
		end
		G.lastPos = nil
	end)
end)

-- Trainers, vendors, innkeepers and flight masters: tick off matching guide steps, and record them.
local lastVisit = {}
local function Visit(kind, describe)
	G:MarkVisit(kind)
	if not G:IsRecording() then return end
	local npc = ns.SafeName("npc")
	local key = kind .. ":" .. (npc or "?")
	if lastVisit[key] and GetTime() - lastVisit[key] < 300 then return end
	lastVisit[key] = GetTime()
	G:Record(kind, { note = describe(npc), npc = npc })
end

ns:RegisterEvent("TRAINER_SHOW", function()
	Visit("train", function(npc) return npc and ("Train at " .. npc) or "Visit your trainer" end)
end)
ns:RegisterEvent("MERCHANT_SHOW", function()
	Visit("vendor", function(npc) return npc and ("Sell and restock at " .. npc) or "Sell and restock" end)
end)
ns:RegisterEvent("HEARTHSTONE_BOUND", function()
	Visit("bind", function()
		local where = GetBindLocation()
		return "Set your hearthstone" .. ((where and where ~= "" and not ns.IsSecret(where)) and (" in " .. where) or "")
	end)
end)
ns:RegisterEvent("TAXIMAP_OPENED", function()
	Visit("flightmaster", function(npc) return "Get the flight path" .. (npc and (" from " .. npc) or "") end)
end)

-- Hearths and portals show up as a big jump in position without a flight.
ns.Ticker(2, "Route recorder", function()
	if not ns.ready or not G:IsRecording() then return end
	local m, x, y = ns.Nav.GetPlayerPosition()
	if not m then return end
	local last = G.lastPos
	if last and not G.onTaxi and not UnitOnTaxi("player") then
		if ns.Nav.DistanceBetween(last.m, last.x, last.y, m, x, y) > 400 then
			G:Record("travel", { note = "Hearth or travel to " .. ns.Nav.MapName(ns.Nav.GetZoneMap(m)) })
		end
	end
	G.lastPos = { m = m, x = x, y = y }
end)

---------------------------------------------------------------------------
-- Import / export (plain text, one step per line; fields after the last one shown are optional)
--   QMG1~name~race~class~faction~minLevel~maxLevel
--   A~questID~mapID~x~y~title~npc    accept     T~... turn in      C~... complete
--   G~mapID~x~y~note~npc             go to      F~... fly          R~... travel/hearth   N~... note
--   K~... trainer   V~... vendor     H~... set hearth              M~... flight master
--   L~level                          reach a level
--   X~level~percent~mapID~x~y~note   grind until that level and percent
---------------------------------------------------------------------------
local CODES = { accept = "A", turnin = "T", complete = "C", ["goto"] = "G", level = "L", fly = "F", travel = "R", note = "N",
	grind = "X", train = "K", vendor = "V", bind = "H", flightmaster = "M" }
local KINDS = {}
for k, v in pairs(CODES) do KINDS[v] = k end

local function Clean(s) return (tostring(s or ""):gsub("[~\r\n|]", " ")) end

local function Split(s, sep)
	local t, start = {}, 1
	while true do
		local i = s:find(sep, start, true)
		if not i then
			table.insert(t, s:sub(start))
			return t
		end
		table.insert(t, s:sub(start, i - 1))
		start = i + 1
	end
end

function G:Serialize(guide)
	local out = { string.format("QMG1~%s~%s~%s~%s~%d~%d", Clean(guide.name), Clean(guide.race), Clean(guide.class),
		Clean(guide.faction), guide.minLevel or 0, guide.maxLevel or 0) }
	for _, s in ipairs(guide.steps) do
		local code = CODES[s.t]
		if code then
			local pos = (s.m and s.x) and string.format("%d~%.1f~%.1f", s.m, s.x * 100, s.y * 100) or "0~0~0"
			local npc = s.npc and ("~" .. Clean(s.npc)) or ""
			if s.t == "level" then
				table.insert(out, "L~" .. (s.lv or 0))
			elseif s.t == "grind" then
				table.insert(out, string.format("X~%d~%d~%s~%s", s.lv or 0, s.pct or 0, pos, Clean(s.note)))
			elseif s.q then
				table.insert(out, string.format("%s~%d~%s~%s%s", code, s.q, pos, Clean(s.title), npc))
			else
				table.insert(out, string.format("%s~%s~%s%s", code, pos, Clean(s.note), npc))
			end
		end
	end
	return table.concat(out, "\n")
end

function G:Deserialize(text)
	if type(text) ~= "string" then return nil, "no text" end
	text = text:gsub("||", "|")
	local lines = {}
	for line in text:gmatch("[^\r\n]+") do
		line = line:gsub("^%s+", ""):gsub("%s+$", "")
		if line ~= "" and not line:match("^#") then table.insert(lines, line) end
	end
	if not lines[1] or not lines[1]:match("^QMG1~") then
		return nil, "that isn't a NeverQuest guide (the first line should start with QMG1~)."
	end
	local h = Split(lines[1], "~")
	local guide = { name = (h[2] and h[2] ~= "") and h[2] or "Imported guide", race = h[3], class = h[4],
		faction = h[5], minLevel = tonumber(h[6]), maxLevel = tonumber(h[7]), steps = {} }
	local function Pos(s, m, x, y)
		m, x, y = tonumber(m), tonumber(x), tonumber(y)
		if m and m > 0 and x and y then s.m, s.x, s.y = m, x / 100, y / 100 end
		return s
	end
	for i = 2, #lines do
		local p = Split(lines[i], "~")
		local kind = KINDS[p[1]]
		local function Text(v) return (v and v ~= "") and v or nil end
		if kind == "level" then
			local lv = tonumber(p[2])
			if lv then table.insert(guide.steps, { t = "level", lv = lv }) end
		elseif kind == "grind" then
			local lv, pct = tonumber(p[2]), tonumber(p[3])
			if lv then
				table.insert(guide.steps, Pos({ t = "grind", lv = lv, pct = math.max(0, math.min(100, pct or 0)), note = Text(p[7]) }, p[4], p[5], p[6]))
			end
		elseif kind == "accept" or kind == "turnin" or kind == "complete" then
			local q = tonumber(p[2])
			if q then
				table.insert(guide.steps, Pos({ t = kind, q = q, title = Text(p[6]), npc = Text(p[7]) }, p[3], p[4], p[5]))
			end
		elseif kind then
			table.insert(guide.steps, Pos({ t = kind, note = Text(p[5]), npc = Text(p[6]) }, p[2], p[3], p[4]))
		end
	end
	if #guide.steps == 0 then return nil, "no steps found in that text." end
	return guide
end

function G:Import(text)
	local guide, err = self:Deserialize(text)
	if not guide then
		ns.Print(err)
		return false
	end
	local name = guide.name
	if ns.db.guides[name] or self.registered[name] then name = name .. " (imported " .. date("%m/%d %H:%M") .. ")" end
	guide.name = name
	ns.db.guides[name] = guide
	ns.Print(string.format("imported guide '%s' (%d steps).", name, #guide.steps))
	ns:SendMessage("RECORDER_UPDATED")
	return true
end

function G:Delete(name)
	if not ns.db.guides[name] then return end
	ns.db.guides[name] = nil
	if ns.char.script.name == name then self:UseLive() end
	ns.Print("deleted guide '" .. name .. "'.")
	ns:SendMessage("RECORDER_UPDATED")
end

-- Guide files call NeverQuest.RegisterGuide("QMG1~..." or a table with the same fields as a recorded guide).
function ns.RegisterGuide(guide)
	if type(guide) == "string" then
		local parsed, err = G:Deserialize(guide)
		if not parsed then
			ns.After(5, function() ns.Print("a bundled guide failed to load: " .. tostring(err)) end)
			return
		end
		guide = parsed
	end
	if type(guide) == "table" and guide.name and type(guide.steps) == "table" then
		G.registered[guide.name] = guide
	end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
ns:AddSlash("record", function(rest) G:StartRecording(rest) end, "/nq record [name] - start recording your route as a guide")
ns:AddSlash("stop", function() G:StopRecording() end, "/nq stop - stop recording and save the guide")
ns:AddSlash("note", function(rest)
	if not G:IsRecording() then return ns.Print("start recording first (/nq record).") end
	if rest == "" then return ns.Print("usage: /nq note <text>") end
	G:Record("note", { note = rest })
	ns.Print("note added.")
end, "/nq note <text> - add a note at your position while recording")
ns:AddSlash("grind", function(rest)
	if not G:IsRecording() then return ns.Print("start recording first (/nq record).") end
	local cur, max = ns.Num(UnitXP("player")) or 0, ns.Num(UnitXPMax("player")) or 1
	local pct = math.floor(cur / math.max(1, max) * 100)
	G:Record("grind", { lv = UnitLevel("player"), pct = pct, note = rest ~= "" and rest or nil })
	ns.Print(string.format("grind step added: level %d at %d%%.", UnitLevel("player"), pct))
end, "/nq grind [note] - while recording, mark that you ground here up to your current XP")
ns:AddSlash("live", function() G:UseLive() ns.Print("using the live guide.") end, "/nq live - switch to the live guide")
ns:AddSlash("load", function(rest) G:LoadScript(rest) end, "/nq load <name> - load a saved guide")
ns:AddSlash("skip", function() G:StepSkip() end, "/nq skip - skip the step the arrow is on (a quest goes on your missed list)")

ns:OnInit(function()
	if ns.char.recorder.active then
		ns.After(3, function()
			ns.Print("still recording '" .. tostring(ns.char.recorder.name) .. "' (" .. #ns.char.recorder.steps .. " steps). /nq stop saves it.")
		end)
	end
end)
