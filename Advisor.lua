-- NeverQuest Advisor: the decisions around the route.
--
--   * Optimized: which zone gives you the most XP per hour right now, worked out from what
--     QuestieDB says about every quest you can take (its XP, where its work is, where it is
--     handed in) rather than only from the 1-60 plan. The plan stays as the fallback and the
--     tie-breaker.
--   * Optimized: which quests in your log aren't worth finishing, so you can drop them.
--   * Zone by zone: the completionist way. Every quest in the zone, gray ones included, nothing
--     dropped, and the zone is left only when it is done (Planner.lua and Profiles.lua ask
--     Completionist()).
--   * Both: quests you skip, drop or leave behind are kept on a list, and any of them can be
--     gone back for. Skipped quests stay off the route until you take them back.
--
-- Planner.lua, Guide.lua, Tracker.lua and UI.lua ask here; nothing here draws anything itself.

local ADDON, ns = ...
local A = {}
ns.Advisor = A

local DETOUR = 1.25           -- real paths are longer than straight lines
local STOP = 8                -- seconds to talk to an NPC
local UNIT_SECS = 25          -- seconds per thing to kill or collect
local OBJ_DEFAULT = 150       -- seconds for an objective with no count in its text
local NO_SPOT_YARDS = 350     -- an objective whose area isn't known: assume this far from the giver
local LEG_CAP = 2500          -- yards: one leg of a quest never counts for more than this
local ZONE_HORIZON = 2700     -- a zone is scored on its best 45 minutes of quests
local THIN = 900              -- under 15 minutes of quests left counts as a thin zone
local BETWEEN = 1.15          -- getting from one quest to the next
-- STAY and FAR_SHARE come from a 1-60 simulation on QuestieDB's data (a human, a dwarf and a night
-- elf): staying until another zone is twice as good, and counting the other continent at 0.7, levels
-- about 10% faster than the plan alone and changes zone the least.
local STAY = 2                -- another zone must be this much better to leave the one you're in
local PLAN_BONUS = 1.1        -- zones your 1-60 plan names for now
local CROSS_CONTINENT = 1200  -- seconds: a boat or a zeppelin, with the walking at both ends
local FAR_SHARE = 0.7         -- a zone across the sea also counts for this share: you'd be cut off from the rest
local MIN_QUESTS = 4          -- fewer known quests than this anywhere: keep to the plan
local HEADROOM = 2            -- levels a zone must still have above you before the guide sends you to it from elsewhere
local DROP_SHARE = 0.25       -- a quest under this share of the route's XP per hour is worth dropping
local DROP_ROOM = 3           -- ...once the quest log has this few slots free beyond the planner's reserve (8 in all)

local BUDGET = 4              -- milliseconds per frame for working out where quests' work is
local SCORE_TTL = 20          -- seconds zone scores are reused

local function Cfg() return ns.db.guide end

local function HereZone()
	local m = ns.SafeCall(C_Map.GetBestMapForUnit, "player")
	return m and ns.Nav.GetZoneMap(m) or nil
end

local function Speed()
	return math.max(7, (ns.Route and ns.Route.speed) or 7)
end

local function Title(qid)
	local e = ns.Quests and ns.Quests.byID[qid]
	if e and e.title then return e.title end
	local q = ns.QuestDB and ns.QuestDB:Get(qid)
	if q and q.t then return q.t end
	local t = ns.SafeCall(C_QuestLog.GetTitleForQuestID, qid)
	return (type(t) == "string" and t ~= "" and not ns.IsSecret(t)) and t or ("Quest " .. qid)
end
A.Title = Title

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
function A:Completionist()
	return ns.Profiles and ns.Profiles:Style() == "zone" and Cfg().completionist ~= false or false
end

-- The quest data chooses zones in both styles (1.25; before, Optimized only).
function A:SmartOn()
	return ns.Profiles and Cfg().smartZones ~= false and Cfg().profile ~= false or false
end

function A:DropOn()
	return Cfg().dropAdvice ~= false and not self:Completionist()
end

function A:MissedOn() return Cfg().missedList ~= false end

---------------------------------------------------------------------------
-- What a quest is worth and how long it takes
---------------------------------------------------------------------------
local est = {}

local function Dist(a, b)
	if not (a and b and a.m and b.m) then return NO_SPOT_YARDS end
	local d = ns.Nav.DistanceBetween(a.m, a.x, a.y, b.m, b.x, b.y)
	if not d or d == math.huge then return LEG_CAP end
	-- The walk over real ground, where Paths.lua has it for either end (1.28.5): a quest whose
	-- work is the other side of a ridge takes longer than the straight line says.
	if a.m == b.m and ns.Paths then
		local walk = ns.Paths:Yards(a.m, a.x, a.y, b.x, b.y)
		if walk and walk / DETOUR > d then d = walk / DETOUR end
	end
	return math.min(d, LEG_CAP)
end

-- A typical quest's XP at a level, for quests nothing knows the XP of.
function A:AverageXP(level)
	local avg = ns.Planner and ns.Planner.avgXP
	if avg and avg > 0 then return avg end
	return 60 + (level or UnitLevel("player") or 1) * 70
end

-- The XP for a quest at your level: the game's figure when it is in your log, else QuestieDB's.
function A:XP(qid)
	local e = ns.Quests and ns.Quests.byID[qid]
	if e and ns.Num(e.xp) and e.xp > 0 then return e.xp end
	return ns.Library and ns.Library:QuestXP(qid) or nil
end

-- { xp, secs, rate (XP per second), guessed } for doing a quest from its giver: walking to
-- where its work is, the work, and walking to where it's handed in. A quest in your log counts
-- only the work that's left.
function A:Estimate(qid, q)
	local level = UnitLevel("player") or 1
	local L = ns.Library
	local objs = L and L:ObjectivesKnown(qid)
	local e = ns.Quests and ns.Quests.byID[qid]
	local key = (e and ((e.complete and "c" or "") .. string.format("%.2f", e.progress or 0))) or ""
	-- What Pace.lua has learned about you: your pace against the standard, and XP per kill.
	local Pc = ns.Pace
	local scale, killXP = Pc and Pc:Scale() or 1, Pc and Pc:KillXP() or nil
	local pace = math.floor(scale * 20 + 0.5) * 100000 + math.floor((killXP or 0) / 10) + ((ns.Paths and ns.Paths:Planning() and ns.Paths.epoch or 0) % 1000) * 1e7
	local c = est[qid]
	if c and c.level == level and c.objs == objs and c.key == key and c.pace == pace then return c end
	q = q or (ns.QuestDB and ns.QuestDB:Get(qid))
	local xp = self:XP(qid)
	local qlevel = (q and q.l) or (e and ns.Num(e.level))
	local guessed = not xp
	xp = xp or self:AverageXP(level)
	if objs == nil and L and L:Get() then self:Queue(qid) end
	local from = (q and q.m and q.x) and q or (e and e.pos and e.pos.m and e.pos) or nil
	local finish = (L and L:Finish(qid)) or from
	local yards, work, prev = 0, 0, from
	if e and e.complete then
		work = 0
	elseif objs then
		for _, s in ipairs(objs.spots) do
			if prev then yards = yards + Dist(prev, s) end
			prev = s
		end
		yards = yards + NO_SPOT_YARDS * math.max(0, objs.count - #objs.spots)
		work = (objs.units > objs.count) and (objs.units * UNIT_SECS) or (objs.count * OBJ_DEFAULT)
	elseif objs == nil then
		yards, work = NO_SPOT_YARDS * 2, OBJ_DEFAULT
	end
	if prev and finish and not (e and e.complete) then yards = yards + Dist(prev, finish) end
	if e and not e.complete then work = work * math.max(0.15, 1 - (e.progress or 0)) end
	work = work * scale
	-- The kills' own XP: what's left of a quest in your log, or the killing share of one you
	-- don't have yet. Nothing for a quest that's gone gray.
	if killXP then
		if e then xp = xp + Pc:KillXPFor(e)
		elseif objs and not (qlevel and level - qlevel > 5) then xp = xp + objs.units * (objs.killShare or 0) * killXP end
	end
	if e and (e.elite or e.group) and not IsInGroup() then work = work * 1.6 end
	if qlevel and qlevel > level then work = work * (1 + 0.15 * (qlevel - level)) end
	local secs = yards * DETOUR / Speed() + work + 2 * STOP
	c = { level = level, objs = objs, key = key, pace = pace, xp = xp, secs = secs, rate = xp / math.max(30, secs), guessed = guessed }
	est[qid] = c
	return c
end

function A:Forget()
	est = {}
	self.scores = nil
end

-- How much a quest you could pick up is worth taking, compared with a typical quest: an average
-- quest is about ten minutes for its XP. 0.4 to 1.6. Zone by zone takes everything at face value.
function A:PickupFactor(qid, q)
	if self:Completionist() then return 1 end
	local x = self:Estimate(qid, q)
	local typical = self:AverageXP() / 600
	if typical <= 0 then return 1 end
	return math.max(0.4, math.min(1.6, x.rate / typical))
end

-- Working out where quests' work is reads a lot from QuestieDB, so it is done a few at a time
-- in the background; estimates made before it's known use a default and improve afterwards.
local pending, queued, working = {}, {}, false
function A:Queue(qid)
	if queued[qid] then return end
	queued[qid] = true
	pending[#pending + 1] = qid
	if working then return end
	working = true
	local function step()
		local L = ns.Library
		if not (L and L:Get()) then pending, queued, working = {}, {}, false return end
		if InCombatLockdown() then ns.After(2, step) return end
		local began, n = debugprofilestop and debugprofilestop(), 0
		while #pending > 0 do
			local id = table.remove(pending, 1)
			queued[id] = nil
			L:Objectives(id)
			n = n + 1
			if began then
				if debugprofilestop() - began > BUDGET then break end
			elseif n >= 25 then break end
		end
		if #pending > 0 then
			ns.After(0.05, step)
		else
			working = false
			ns.Debounce("advisor:objectives", 1, function()
				A.scores = nil
				if ns.Planner then ns.Planner.dirty = true end
				ns:SendMessage("ADVISOR_UPDATED")
			end)
		end
	end
	ns.After(0, step)
end
function A:Pending() return #pending end

---------------------------------------------------------------------------
-- Zones by XP per hour (Optimized)
---------------------------------------------------------------------------
local function ZoneOfQuest(e)
	local name = ns.Quests:ZoneOf(e)
	return name and ns.Profiles and ns.Profiles.ZoneID(name) or nil
end

-- One zone's score: its best 45 minutes of quests for you, as XP per hour, with the trip there
-- counted and thin zones marked down (you'd only have to move again soon).
function A:ScoreZone(id, name, here, planZones)
	local list = {}
	for _, k in ipairs(ns.QuestDB and ns.QuestDB:OpenIn(id) or {}) do
		if not self:IsSkipped(k.qid) then list[#list + 1] = self:Estimate(k.qid, k.q) end
	end
	for _, e in ipairs(ns.Quests.log) do
		if not e.failed and not e.trivial and not self:IsSkipped(e.questID) and ZoneOfQuest(e) == id then
			list[#list + 1] = self:Estimate(e.questID)
		end
	end
	table.sort(list, function(a, b) return a.rate > b.rate end)
	local xp, secs, n = 0, 0, 0
	for _, x in ipairs(list) do
		if secs >= ZONE_HORIZON then break end
		xp, secs, n = xp + x.xp, secs + x.secs * BETWEEN, n + 1
	end
	local travel, far = 0, false
	if id ~= here then
		local m, x, y = ns.Nav.GetPlayerPosition()
		local d = m and ns.Nav.DistanceBetween(m, x, y, id, 0.5, 0.5) or math.huge
		if d == math.huge then
			travel, far = CROSS_CONTINENT, true
		else
			local speed = Speed()
			if d > 1500 and ns.db.nav.flights ~= false then speed = speed * 2.5 end
			travel = math.min(900, d * DETOUR / speed)
		end
	end
	local score = n > 0 and (xp / math.max(60, secs + travel) * 3600) or 0
	if secs < THIN then score = score * (0.5 + 0.5 * secs / THIN) end
	if planZones and planZones[name] then score = score * PLAN_BONUS end
	if far then score = score * FAR_SHARE end
	return { id = id, name = name, score = score, xp = xp, secs = secs, n = n, travel = travel, here = id == here, far = far }
end

-- Every zone that fits your level and side, best first. Reused for a few seconds.
function A:ZoneScores(planZones)
	local level = UnitLevel("player") or 1
	local here = HereZone()
	local key = table.concat({ level, here or 0, ns.QuestDB and ns.QuestDB:OpenTick() or 0, #ns.Quests.log,
		(ns.Library and ns.Library:Get()) and 1 or 0 }, ":")
	local s = self.scores
	if s and s.key == key and GetTime() - s.at < SCORE_TTL then return s.list end
	local P = ns.Profiles
	local side = UnitFactionGroup("player") == "Horde" and "H" or "A"
	local hereMap = ns.SafeCall(C_Map.GetBestMapForUnit, "player")
	local hereCont = hereMap and ns.Nav.GetContinentMap and ns.Nav.GetContinentMap(hereMap)
	local list = {}
	for name, z in pairs(P.ZONES) do
		local id = P.ZoneID(name)
		local isHere = id ~= nil and id == here
		local fits = z[3] == "C" or z[3] == side
		-- Starting zones: your own race's (your plan names it), the one you're standing in, and
		-- the others on the continent you're on, so an Undead who sails to Kalimdor at 6 can use
		-- Durotar. Another continent's are a long way for little XP, and the Skyborne isle only
		-- counts from your plan or while you're on it.
		if z[2] <= 12 or z[4] == "Z" then
			local near = z[4] ~= "Z" and hereCont and id and ns.Nav.GetContinentMap(id) == hereCont
			fits = fits and (isHere or (planZones and planZones[name]) or near or false)
		end
		if fits and id then
			local minL, maxL = P.ZoneLevels(name)
			-- Zones that fit your level now; one you've outleveled only while you're still in it.
			-- 1.28.9: and one you'd have to travel to needs a couple of levels left in it. At 29
			-- Ashenvale (18 to 30) still "fit", so its leftover quests could outscore everything and
			-- send you back to a zone you were about to outgrow. Your plan's zones are the exception.
			local inPlan = planZones and planZones[name]
			local room = maxL and (maxL >= math.min(level + HEADROOM, 60) or (maxL >= level and (isHere or inPlan)))
			if minL and maxL and minL <= level + 2 and (room or (isHere and maxL >= level - 4)) then
				list[#list + 1] = self:ScoreZone(id, name, here, planZones)
			end
		end
	end
	table.sort(list, function(a, b) return a.score > b.score end)
	self.scores = { key = key, at = GetTime(), list = list }
	return list
end

-- The quest data chooses the guide's zone (Profiles:Focus) at every level and in both styles,
-- from wherever you are; the 1-60 plan breaks ties, and stands when too little is known.
--   Optimized: the best zone by XP per hour, but the zone you're in is kept while it is at
--     least half as good, so going somewhere on purpose is followed rather than undone.
--   Zone by zone: you stay wherever you are while it has quests for you (Profiles:Focus);
--     once it's done, the next zone is the best one from here.
function A:ApplyZones(f, level)
	if not f or not self:SmartOn() then return f end
	local plan = {}
	for name in pairs(f.zones or {}) do plan[name] = true end
	local list = self:ZoneScores(plan)
	local best = list[1]
	if not best or best.n < MIN_QUESTS then return f end
	local here = HereZone()
	if f.style == "zone" then
		f.scores = list
		if not f.moveOn then return f end
		local pick
		for _, z in ipairs(list) do
			if z.id ~= here and z.n > 0 then pick = z break end
		end
		if not pick then return f end
		local planZone = f.primary
		f.smart, f.planZone = true, planZone
		f.primary, f.primaryID = pick.name, pick.id
		f.zones = { [pick.name] = true }
		f.reason = string.format("Zone by zone: %s next, with %d %s for you and the most XP per hour from here.",
			pick.name, pick.n, pick.n == 1 and "quest" or "quests")
		if planZone and not ns.Profiles.SameZone(planZone, pick.name) then
			f.reason = f.reason .. " Your 1-60 plan has " .. planZone .. "."
		end
		return f
	end
	local pick = best
	for _, z in ipairs(list) do
		if z.id == here and z ~= best and z.n > 0 and z.score * STAY >= best.score then pick = z end
	end
	local after
	for _, z in ipairs(list) do
		if z ~= pick and z.n > 0 then after = z break end
	end
	local planZone = f.primary
	f.smart, f.planZone, f.scores = true, planZone, list
	f.primary, f.primaryID = pick.name, pick.id
	f.zones = { [pick.name] = true }
	f.nextZone = after and after.name or f.nextZone
	f.nearEnd = pick.secs < THIN
	f.moveOn = pick.id ~= here
	f.zoneDone = pick.here and pick.n == 0 or false
	f.reason = string.format("Most XP per hour for you now: about %s XP/hour from %d %s here.",
		ns.Comma(math.floor(pick.score / 100 + 0.5) * 100), pick.n, pick.n == 1 and "quest" or "quests")
	if planZone and not ns.Profiles.SameZone(planZone, pick.name) then
		f.reason = f.reason .. " Your 1-60 plan has " .. planZone .. "."
	end
	return f
end

---------------------------------------------------------------------------
-- Skipped, dropped and left behind
---------------------------------------------------------------------------
local function Rec(qid)
	local q = ns.QuestDB and ns.QuestDB:Get(qid)
	local e = ns.Quests and ns.Quests.byID[qid]
	local snap = A.snap and A.snap[qid]
	local m = (q and q.m and ns.Nav.GetZoneMap(q.m)) or (snap and snap.m) or HereZone()
	return { at = time(), t = (e and e.title) or (snap and snap.t) or Title(qid), l = (q and q.l) or (e and ns.Num(e.level)) or (snap and snap.l), m = m }
end

local function Changed()
	A.scores = nil
	if ns.QuestDB then ns.QuestDB:ClearNearby() end
	if ns.Planner then ns.Planner.dirty = true end
	if ns.Guide then ns.Guide:Refresh() end
	if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
	ns:SendMessage("ADVISOR_UPDATED")
end

-- Auto-accept's "only the ones the route will do": a quest is taken when the route already
-- plans to pick it up, when it's for a dungeon you chose or the attunement you follow, when it's
-- a class or profession quest, or when what it's worth for its time keeps up with your route
-- (the same test the guide uses before suggesting you drop one, so nothing is taken only to be
-- dropped), counting what its follow-ups are worth. Elite, group, dungeon and raid quests wait
-- for a group unless your dungeon plan wants them. Quests you skipped are never taken.
function A:WorthTaking(qid, title)
	qid = ns.Num(qid)
	if not qid then return false end
	if self:IsSkipped(qid) then return false end
	if self:IsGoingBack(qid) then return true end
	local plan = ns.Planner and ns.Planner.plan
	if plan and plan.rank and plan.rank[qid] then return true end
	local dplan = ns.Dungeons and ns.Dungeons:On() and ns.Dungeons:Plan() or nil
	if dplan and (dplan.byQuest[qid] or dplan.wait[qid] or dplan.prep[qid]) then return true end
	local followed = ns.Attune and ns.Attune:Following()
	if followed and title and ns.Attune.Matches then
		for _, step in ipairs(followed.steps) do if ns.Attune.Matches(step, title) then return true end end
	end
	if ns.Library and ns.Library.ClassOrProfession and ns.Library:ClassOrProfession(qid) then return true end
	-- Too far above you: the route won't send you there yet.
	local q = ns.QuestDB and ns.QuestDB:Get(qid)
	local lib = ns.Library and ns.Library.Entry and ns.Library:Entry(qid)
	local qlevel = (q and q.l) or (lib and lib.l)
	if ns.Planner and ns.Planner.TooHigh and ns.Planner.TooHigh(qlevel) then return false end
	local kind = ns.Quests:Kind(qid)
	if kind and kind ~= "PvP" and not IsInGroup() then return false end
	local planRate = plan and (plan.plainRate or plan.rate) or 0
	if planRate <= 0 then return true end
	local x = self:Estimate(qid)
	local chain = 0
	if ns.Chains and ns.db.guide.chains then chain = ns.Chains:Value(qid, self:AverageXP()) or 0 end
	local rate = (x.xp + chain) / math.max(30, x.secs) * 3600
	return rate >= planRate * DROP_SHARE
end

function A:IsSkipped(qid) return qid ~= nil and ns.char.skipped[qid] ~= nil end
function A:IsGoingBack(qid) return qid ~= nil and ns.char.goBack[qid] == true end

function A:Skip(qid, silent)
	qid = ns.Num(qid)
	if not qid then return false end
	ns.char.skipped[qid] = Rec(qid)
	ns.char.goBack[qid] = nil
	if not silent then
		ns.Print(string.format("skipped |cffffd100%s|r. The route leaves it out; it's on your missed list (Quests tab > Missed, or /nq missed) whenever you want it back.", Title(qid)))
	end
	Changed()
	return true
end

function A:Unskip(qid)
	qid = ns.Num(qid)
	if not qid or not ns.char.skipped[qid] then return false end
	ns.char.skipped[qid] = nil
	Changed()
	return true
end

-- Go back for a quest on the missed list: it is no longer skipped, and the route counts it for
-- a lot more until it's handed in.
function A:GoBack(qid, on)
	qid = ns.Num(qid)
	if not qid then return false end
	if on == false then
		ns.char.goBack[qid] = nil
	else
		ns.char.goBack[qid] = true
		ns.char.skipped[qid] = nil
		ns.char.missedHidden[qid] = nil
		ns.Print(string.format("going back for |cffffd100%s|r: it's on your route now.", Title(qid)))
	end
	Changed()
	return true
end

-- Off the missed list for good (it can still turn up on the route like any other quest).
function A:Hide(qid)
	qid = ns.Num(qid)
	if not qid then return false end
	ns.char.skipped[qid], ns.char.dropped[qid], ns.char.goBack[qid] = nil, nil, nil
	ns.char.missedHidden[qid] = true
	Changed()
	return true
end

local WHY_ORDER = { back = 0, skipped = 1, dropped = 2, left = 3 }
local WHY_TEXT = { skipped = "you skipped it", dropped = "you dropped it", left = "left behind" }

-- The missed list: quests you skipped or dropped, and quests still open to you in zones you
-- have quested in and moved on from. Each { qid, t, l, zone, why, status, gray, back, q }.
-- Gray ones you left behind only with withGray; ones you skipped or dropped always.
function A:Missed(withGray)
	local out, seen = {}, {}
	local D = ns.QuestDB
	if not D then return out end
	local level = UnitLevel("player") or 1
	local grayBelow = D.GrayBelow(level)
	local here = HereZone()
	local function Add(qid, why, rec)
		if seen[qid] or ns.char.missedHidden[qid] then return end
		local q = D:Get(qid)
		local st = D:Status(qid, q)
		-- A quest you skipped can still be in your log: it stays listed so you can take it back.
		if st == "done" or (st == "log" and why ~= "skipped") then return end
		if why == "left" and st ~= "available" then return end
		if st == "faction" or st == "other" then return end
		local ql = (q and q.l) or (rec and rec.l)
		local gray = (ql and ql < grayBelow) or false
		if why == "left" and gray and not withGray then return end
		seen[qid] = true
		out[#out + 1] = { qid = qid, why = why, t = (q and q.t) or (rec and rec.t) or Title(qid), l = ql,
			zone = (q and q.m and ns.Nav.GetZoneMap(q.m)) or (rec and rec.m), q = q, status = st, gray = gray,
			back = ns.char.goBack[qid] == true }
	end
	for qid in pairs(ns.char.goBack) do
		if not (ns.Quests.byID[qid]) then Add(qid, ns.char.skipped[qid] and "skipped" or ns.char.dropped[qid] and "dropped" or "left", ns.char.dropped[qid]) end
	end
	for qid, rec in pairs(ns.char.skipped) do Add(qid, "skipped", rec) end
	for qid, rec in pairs(ns.char.dropped) do Add(qid, "dropped", rec) end
	for zone in pairs(ns.char.visited) do
		if zone ~= here then
			for _, k in ipairs(D:OpenIn(zone, true)) do Add(k.qid, "left") end
		end
	end
	table.sort(out, function(a, b)
		local wa, wb = a.back and 0 or WHY_ORDER[a.why], b.back and 0 or WHY_ORDER[b.why]
		if wa ~= wb then return wa < wb end
		if a.gray ~= b.gray then return not a.gray end
		local za, zb = a.zone and ns.Nav.MapName(a.zone) or "", b.zone and ns.Nav.MapName(b.zone) or ""
		if za ~= zb then return za < zb end
		return (a.l or 0) < (b.l or 0)
	end)
	return out
end

-- Quests skipped in the log count, plus open ones on the list worth the trip.
function A:MissedCount(withGray)
	local n = 0
	for _, m in ipairs(self:Missed(withGray)) do
		if m.status == "available" or m.why ~= "left" then n = n + 1 end
	end
	return n
end

---------------------------------------------------------------------------
-- Quests worth dropping (Optimized)
---------------------------------------------------------------------------
local function Protected(e, dplan, followed)
	if A:IsGoingBack(e.questID) then return true end
	if dplan and (dplan.wait[e.questID] or dplan.prep[e.questID]) then return true end
	if followed and ns.Attune.Matches then
		for _, step in ipairs(followed.steps) do if ns.Attune.Matches(step, e.title) then return true end end
	end
	-- Your class's and your professions' quests are filed under their names in the quest log.
	local className = UnitClass("player")
	if e.zone and e.zone == className then return true end
	if e.zone and ns.ClassQuests then
		local mine = ns.ClassQuests:MyProfessions()
		for _, rec in pairs(mine) do if type(rec) == "table" and rec.name == e.zone then return true end end
	end
	-- A quest that opens a chain of two or more is worth more than its own XP says.
	if ns.Chains and Cfg().chains then
		local _, ups = ns.Chains:Value(e.questID, 0)
		if (ups or 0) >= 2 then return true end
	end
	return false
end

-- The quests in your log not worth finishing, most pointless first: { e, why, score }.
-- Never one that's finished, one you chose to go back for, a dungeon quest you're gathering,
-- your attunement chain, a class or profession quest, or one that opens a chain.
function A:DropCandidates(limit)
	if not self:DropOn() then return {} end
	local plan = ns.Planner and ns.Planner.plan
	local planRate = plan and (plan.plainRate or plan.rate) or 0
	local focus = ns.Guide and ns.Guide.focus
	local dplan = ns.Dungeons and ns.Dungeons:On() and ns.Dungeons:Plan() or nil
	local followed = ns.Attune and ns.Attune:Following()
	local level = UnitLevel("player") or 1
	local tight = not (ns.Planner and ns.Planner.LogRoom) or ns.Planner.LogRoom() <= DROP_ROOM
	local out = {}
	for _, e in ipairs(ns.Quests.log) do
		if not e.complete and not Protected(e, dplan, followed) then
			local why, score = {}, 0
			if e.failed then
				why[#why + 1], score = "failed", 300
			elseif e.trivial then
				why[#why + 1], score = "gray: little XP", 200
			else
				local onRoute = plan and plan.rank and plan.rank[e.questID]
				if not onRoute then
					local x = self:Estimate(e.questID)
					local r = x.rate * 3600
					-- (a slow quest costs nothing sitting in the log: it's only worth dropping for
					-- being slow once the log is filling up. 1.28.5: quests are picked up in passing.)
					if planRate > 0 and r < planRate * DROP_SHARE and tight then
						why[#why + 1] = string.format("about %s XP/hour against %s on your route", ns.Comma(math.floor(r / 100) * 100), ns.Comma(math.floor(planRate / 100) * 100))
						score = score + 100
					end
					local zname = ns.Quests:ZoneOf(e)
					local _, maxL = zname and ns.Profiles and ns.Profiles.ZoneLevels(zname)
					local inFocus = false
					for name in pairs(focus and focus.zones or {}) do if ns.Profiles.SameZone(name, zname) then inFocus = true end end
					if zname and maxL and maxL < level - 1 and not inFocus then
						why[#why + 1] = "in " .. zname .. ", which you've outleveled"
						score = score + 80
					end
					if (e.elite or e.group) and not IsInGroup() then
						why[#why + 1] = "needs a group"
						score = score + 40
					end
				end
			end
			if score >= 80 then out[#out + 1] = { e = e, why = table.concat(why, ", "), score = score } end
		end
	end
	table.sort(out, function(a, b) return a.score > b.score end)
	while #out > (limit or 3) do table.remove(out) end
	return out
end

-- Opens the game's own "abandon this quest?" box for a quest; nothing is dropped until you
-- confirm it there.
function A:Abandon(qid)
	qid = ns.Num(qid)
	if not qid or InCombatLockdown() or ns.SafeCall(C_QuestLog.IsOnQuest, qid) ~= true then return false end
	if C_QuestLog.SetSelectedQuest then ns.SafeCall(C_QuestLog.SetSelectedQuest, qid) end
	if C_QuestLog.SetAbandonQuest then ns.SafeCall(C_QuestLog.SetAbandonQuest)
	elseif SetAbandonQuest then ns.SafeCall(SetAbandonQuest) end
	if StaticPopup_Show then StaticPopup_Show("ABANDON_QUEST", Title(qid)) end
	return true
end

---------------------------------------------------------------------------
-- Guide rows
---------------------------------------------------------------------------
-- Quests you chose to go back for that the route can't reach from here (another continent, or
-- no place known on this one), as steps of their own; and the notes on dropping, the missed
-- list and the best zones.
function A:GuideRows(steps, plan)
	local G = ns.Guide
	local onRoute = plan and plan.rank or {}
	local backs = {}
	for qid in pairs(ns.char.goBack) do
		if not onRoute[qid] then
			local e = ns.Quests.byID[qid]
			local s
			if e then
				s = G:MakeStep(e.complete and "turnin" or "objective", e)
			else
				local q = ns.QuestDB and ns.QuestDB:Get(qid)
				if q and q.m and q.x then
					s = G:MakeStep("pickup", { questID = qid, title = q.t or Title(qid), level = q.l, m = q.m, x = q.x, y = q.y,
						dist = ns.Nav.Distance(q.m, q.x, q.y) })
				end
			end
			if s then
				s.key = "back:" .. qid
				s.title = "Go back for: " .. (s.title:gsub("^Pick up: ", ""):gsub("^Turn in: ", "turn in "))
				local zone = s.m and ns.Nav.MapName(ns.Nav.GetZoneMap(s.m))
				s.sub = "|cff99ccffon your missed list" .. (zone and (", " .. zone) or "") .. "|r" .. (s.sub and s.sub ~= "" and ("  ·  " .. s.sub) or "")
				s.color = { 0.6, 0.85, 1 }
				backs[#backs + 1] = s
			end
		end
	end
	table.sort(backs, function(a, b) return (a.dist or 1e9) < (b.dist or 1e9) end)
	-- Right after anything you can do where you stand.
	local at = 1
	while steps[at] and (steps[at].milestoneKey or ((steps[at].kind == "turnin" or steps[at].kind == "pickup")
		and not steps[at].predicted and steps[at].dist and steps[at].dist <= 300)) do
		at = at + 1
	end
	for i = #backs, 1, -1 do table.insert(steps, at, backs[i]) end

	local drops = self:DropCandidates(3)
	if #drops > 0 then
		local names = {}
		for _, c in ipairs(drops) do names[#names + 1] = c.e.title .. " (" .. c.why .. ")" end
		local key = "tip:drop"
		if not (ns.Upkeep and ns.Upkeep.hidden and ns.Upkeep.hidden[key]) then
		steps[#steps + 1] = { kind = "tip", key = key,
			openQuest = drops[1].e.questID, dropQuest = drops[1].e.questID, reminder = true,
			title = #drops == 1 and "Worth dropping: " .. drops[1].e.title or ("Worth dropping: " .. #drops .. " quests"),
			sub = table.concat(names, "; ") .. ". Click to open the first in your quest log, right-click to hide this note. Right-click a quest in the guide or tracker for Drop or Skip.",
			color = { 1, 0.7, 0.4 } }
		end
	end

	if self:MissedOn() then
		local complete = self:Completionist()
		local n = self:MissedCount(complete)
		if n > 0 then
			steps[#steps + 1] = { kind = "tip", key = "tip:missed", openMissed = true,
				title = n == 1 and "1 quest skipped or left behind" or (n .. " quests skipped or left behind"),
				sub = "Click to see them on the Quests tab. Right-click one there to go back for it.",
				color = { 0.6, 0.85, 1 } }
		end
	end

	local f = G.focus
	if f and f.smart and f.scores and (f.moveOn or f.nearEnd) then
		local parts = {}
		for i = 1, math.min(3, #f.scores) do
			local z = f.scores[i]
			if z.n > 0 then parts[#parts + 1] = string.format("%s ~%s/h (%d)", z.name, ns.Comma(math.floor(z.score / 100 + 0.5) * 100), z.n) end
		end
		if #parts > 1 then
			steps[#steps + 1] = { kind = "tip", key = "tip:zones", title = "Best zones for you now",
				sub = table.concat(parts, "  ·  ") .. ". XP per hour from the quests you can take, travel included. /nq zones lists them all.",
				color = { 0.6, 0.85, 1 } }
		end
	end
end

-- Right-click menu entries for a quest, shared by the guide, the tracker and the missed list.
-- noAbandon: the caller has its own Abandon entry.
function A:MenuItems(root, qid, noAbandon)
	if not qid then return end
	local inLog = ns.SafeCall(C_QuestLog.IsOnQuest, qid) == true
	if self:IsSkipped(qid) then
		root:CreateButton("Take it back (stop skipping)", function() A:Unskip(qid) end)
	else
		root:CreateButton("Skip it (the route leaves it out)", function() A:Skip(qid) end)
	end
	if self:IsGoingBack(qid) then
		root:CreateButton("Stop going back for it", function() A:GoBack(qid, false) end)
	elseif not inLog then
		root:CreateButton("Go back for it", function() A:GoBack(qid, true) end)
	end
	if inLog and not noAbandon then
		root:CreateButton("Abandon quest...", function() A:Abandon(qid) end)
	end
end

---------------------------------------------------------------------------
-- The missed list on the Quests tab
---------------------------------------------------------------------------
function A:Items(withGray)
	local items = {}
	for _, m in ipairs(self:Missed(withGray)) do
		local parts = {}
		parts[#parts + 1] = m.back and "|cff99ccffgoing back for it|r" or WHY_TEXT[m.why]
		local zone = m.zone and ns.Nav.MapName(m.zone)
		if zone then parts[#parts + 1] = zone end
		local giver = ns.Quests:GiverName(m.qid)
		if giver then parts[#parts + 1] = "from " .. giver end
		if m.status == "log" then
			parts[#parts + 1] = "|cff66ccffin your log|r"
		elseif m.status == "later" then
			parts[#parts + 1] = "|cffff9933opens at level " .. ((m.q and (m.q.rl or m.q.l)) or "?") .. "|r"
		elseif m.status == "locked" then
			parts[#parts + 1] = "|cff999999needs an earlier quest first|r"
		end
		if m.gray then parts[#parts + 1] = "|cff999999gray now: little XP|r" end
		local xp = self:XP(m.qid)
		if xp and xp > 0 then parts[#parts + 1] = "+" .. ns.Comma(xp) .. " XP" end
		local item = { key = "missed:" .. m.qid, questID = m.qid, missedQuest = m.qid,
			icon = "QuestNormal", title = (m.l and ("[" .. m.l .. "] ") or "") .. m.t,
			color = m.gray and { 0.6, 0.6, 0.6 } or { ns.QuestColor(m.qid) },
			sub = table.concat(parts, "  ·  "),
			right = (m.q and m.q.m and ns.Yards(ns.Nav.Distance(m.q.m, m.q.x, m.q.y))) or "" }
		if m.q and m.q.m and m.q.x then
			item.m, item.x, item.y = m.q.m, m.q.x, m.q.y
			item.navTitle = "Pick up: " .. m.t
		end
		items[#items + 1] = item
	end
	if #items == 0 then
		items[1] = { kind = "tip", key = "missed:none", title = "Nothing missed",
			sub = "Quests you skip or drop, and quests still open in zones you've moved on from, show here." }
	end
	return items
end

---------------------------------------------------------------------------
-- Keeping the list up to date
---------------------------------------------------------------------------
local turned = {}

local function QuestArg(a, b) return ns.Num(b) or ns.Num(a) end

local function Visited()
	local z = HereZone()
	if z then ns.char.visited[z] = math.max(ns.char.visited[z] or 0, UnitLevel("player") or 1) end
end

-- Titles and zones of what's in the log, so a quest that has just gone can still be named.
ns:RegisterMessage("QUESTS_UPDATED", function()
	local snap = {}
	for _, e in ipairs(ns.Quests.log) do
		snap[e.questID] = { t = e.title, l = ns.Num(e.level), m = e.pos and e.pos.m and ns.Nav.GetZoneMap(e.pos.m) or HereZone() }
	end
	A.snap = snap
	A.scores = nil
end)

ns:RegisterEvent("QUEST_ACCEPTED", function(_, a, b)
	if not ns.ready then return end
	local qid = QuestArg(a, b)
	Visited()
	if qid then
		ns.char.dropped[qid] = nil
		if ns.char.skipped[qid] then ns.char.skipped[qid] = nil end
	end
	A.scores = nil
end)

ns:RegisterEvent("QUEST_TURNED_IN", function(_, qid)
	if not ns.ready then return end
	qid = ns.Num(qid)
	Visited()
	if qid then
		turned[qid] = GetTime()
		ns.char.skipped[qid], ns.char.dropped[qid], ns.char.goBack[qid] = nil, nil, nil
	end
	est[qid or 0] = nil
	A.scores = nil
end)

-- Gone from the log without being handed in: dropped.
ns:RegisterEvent("QUEST_REMOVED", function(_, qid)
	if not ns.ready then return end
	qid = ns.Num(qid)
	if not qid then return end
	local snap = A.snap and A.snap[qid]
	ns.After(1, function()
		if turned[qid] and GetTime() - turned[qid] < 5 then return end
		if ns.SafeCall(C_QuestLog.IsQuestFlaggedCompleted, qid) == true then return end
		if ns.SafeCall(C_QuestLog.IsOnQuest, qid) == true then return end
		local rec = Rec(qid)
		if snap then rec.t, rec.l, rec.m = snap.t or rec.t, snap.l or rec.l, snap.m or rec.m end
		ns.char.dropped[qid] = rec
		A.scores = nil
		if ns.Planner then ns.Planner.dirty = true end
	end)
end)

ns:RegisterEvent("PLAYER_LEVEL_UP", function() A.scores = nil end)

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
ns:AddSlash("missed", function(rest)
	rest = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, arg = rest:match("^(%S+)%s*(.-)$")
	local id = tonumber(arg)
	if cmd == "back" and id then A:GoBack(id, true) return end
	if (cmd == "unskip" or cmd == "take") and id then
		ns.Print(A:Unskip(id) and ("taken back: " .. Title(id) .. ".") or "that quest isn't skipped.")
		return
	end
	if (cmd == "forget" or cmd == "hide") and id then A:Hide(id) ns.Print("off the missed list: " .. Title(id) .. ".") return end
	if cmd == "clear" then
		wipe(ns.char.skipped) wipe(ns.char.dropped) wipe(ns.char.goBack)
		Changed()
		ns.Print("cleared the quests you skipped and dropped. Quests left behind in other zones still show while they're open to you.")
		return
	end
	local list = A:Missed(A:Completionist())
	if #list == 0 then ns.Print("nothing on your missed list.") return end
	ns.Print(string.format("%d %s skipped, dropped or left behind (Quests tab > Missed has them all):", #list, #list == 1 and "quest" or "quests"))
	for i = 1, math.min(15, #list) do
		local m = list[i]
		DEFAULT_CHAT_FRAME:AddMessage(string.format("   |cffffd100%d|r %s%s - %s%s%s", m.qid, m.l and ("[" .. m.l .. "] ") or "", m.t,
			m.back and "going back for it" or WHY_TEXT[m.why], m.zone and (", " .. (ns.Nav.MapName(m.zone) or "?")) or "",
			m.gray and " (gray)" or ""))
	end
	ns.Print("/nq missed back <id> goes back for one, unskip <id> takes a skipped one back, forget <id> takes one off the list.")
end, "/nq missed [back <id> | unskip <id> | forget <id> | clear] - quests you skipped, dropped or left behind")

ns:AddSlash("zones", function()
	local list = A:ZoneScores()
	if #list == 0 then ns.Print("no zones fit your level right now.") return end
	ns.Print("zones for you now, by XP per hour from the quests you can take (travel included):")
	for i = 1, math.min(10, #list) do
		local z = list[i]
		DEFAULT_CHAT_FRAME:AddMessage(string.format("   %d. %s: ~%s XP/hour, %d %s%s%s", i, z.name, ns.Comma(math.floor(z.score / 100 + 0.5) * 100),
			z.n, z.n == 1 and "quest" or "quests", z.here and " (you're here)" or "", z.travel > 0 and string.format(", %s to get there%s", ns.Duration(z.travel), z.far and " by boat or zeppelin" or "") or ""))
	end
	if A:Pending() > 0 then ns.Print("still working out where " .. A:Pending() .. " quests' objectives are; these firm up in a moment.") end
	if not A:SmartOn() then ns.Print("the guide isn't choosing zones this way right now: turn on \"Choose zones from the quest data\" (and following your 1-60 plan) under Options > Guide & Routes.") end
end, "/nq zones - every zone that fits your level, by XP per hour")

ns:AddSlash("drop", function()
	if A:Completionist() then ns.Print("Zone by zone finishes every quest, so it doesn't suggest dropping any.") return end
	local list = A:DropCandidates(10)
	if #list == 0 then ns.Print("nothing in your log looks worth dropping.") return end
	ns.Print("worth dropping:")
	for _, c in ipairs(list) do DEFAULT_CHAT_FRAME:AddMessage("   " .. c.e.title .. ": " .. c.why) end
	ns.Print("right-click a quest in the guide or tracker for Drop or Skip.")
end, "/nq drop - quests in your log that aren't worth finishing")
