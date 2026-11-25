-- NeverQuest Pace: watches how you actually earn XP and lets the route adjust to it.
--
-- The planner used to assume everyone kills a mob in 22 seconds, gets an item every 30, and
-- earns nothing but the quest reward. Nobody plays like that. This measures, per character:
--   * how long one unit of an objective really takes you (a kill, an item, an object), from the
--     gaps between its progress ticks. Stops to gather, drink, loot or fight an extra mob are in
--     those gaps, so they're in the figure;
--   * how much XP a kill gives you right now (rested bonus and mob level included);
--   * how many XP-giving kills an item takes, for drop quests.
-- The planner and the advisor use them once there's enough to go on, and fall back to the fixed
-- figures until then. All of it is a moving average, so it follows you as you level, change
-- gear, group up or start gathering.

local ADDON, ns = ...
local Pc = {}
ns.Pace = Pc

local DEFAULT = { monster = 22, item = 30, object = 15 }  -- the planner's fixed seconds per unit
local MIN_SCALE, MAX_SCALE = 0.4, 3     -- learned seconds stay within this much of the fixed figure
local GAP_CAP = 6                       -- a gap longer than this many times the fixed figure isn't work: you went away
local WARMUP = 4                        -- samples before a figure is used
local ALPHA = 0.2                       -- how fast the averages follow you
local KILL_WARMUP = 5
local KILL_OUTLIER = 3                  -- an XP gain this many times the average isn't a kill (exploring a new area)
local KILL_STALE_LEVELS = 3             -- levels gained since the last kill sample before the kill figure is distrusted
local MAX_KILLS_PER_ITEM = 6

local function Cfg() return ns.db.guide end
local function Store()
	local p = ns.char.pace
	if type(p) ~= "table" then p = {} ns.char.pace = p end
	p.secs, p.n, p.kills = p.secs or {}, p.n or {}, p.kills or {}
	return p
end

-- paused: set by the test harness, whose older sections were written against the standard figures.
function Pc:On() return not self.paused and Cfg().learnPace ~= false end

local function Blend(old, n, sample)
	if not old or n <= 0 then return sample end
	if n < WARMUP then return old + (sample - old) / (n + 1) end
	return old + (sample - old) * ALPHA
end

---------------------------------------------------------------------------
-- What the planner asks
---------------------------------------------------------------------------
-- Your seconds per unit for an objective type, or nil while it isn't known.
function Pc:Secs(kind)
	if not self:On() then return nil end
	local p = Store()
	local base = DEFAULT[kind]
	if not base or (p.n[kind] or 0) < WARMUP or not p.secs[kind] then return nil end
	return math.max(base * MIN_SCALE, math.min(base * MAX_SCALE, p.secs[kind]))
end

-- How your pace compares with the fixed figures overall (1 = the same), for estimates that
-- don't know an objective's type. Weighted by how much of each you've done.
function Pc:Scale()
	if not self:On() then return 1 end
	local p = Store()
	local sum, weight = 0, 0
	for kind, base in pairs(DEFAULT) do
		local s = self:Secs(kind)
		if s then
			local w = math.min(p.n[kind], 30)
			sum, weight = sum + s / base * w, weight + w
		end
	end
	return weight > 0 and sum / weight or 1
end

-- XP from one kill right now, or nil while it isn't known.
function Pc:KillXP()
	if not self:On() then return nil end
	local p = Store()
	if (p.killN or 0) < KILL_WARMUP or not p.killXP then return nil end
	if p.killLevel and (UnitLevel("player") or 0) - p.killLevel >= KILL_STALE_LEVELS then return nil end
	return p.killXP
end

-- Kills that give XP per unit of an objective: 1 for a kill objective, what you've seen for
-- items (nil while unknown), none for objects.
function Pc:KillsPer(kind)
	if kind == "monster" then return 1 end
	if kind ~= "item" or not self:On() then return nil end
	local p = Store()
	if (p.kills.n or 0) < WARMUP or not p.kills.per then return nil end
	return math.min(MAX_KILLS_PER_ITEM, p.kills.per)
end

-- Kill XP still to come from a quest's open objectives: units left times XP per kill. 0 while
-- nothing is known, and for gray quests, whose mobs give you nothing.
function Pc:KillXPFor(e)
	local per = self:KillXP()
	if not per or not e or e.complete or e.trivial then return 0 end
	local xp = 0
	for _, o in ipairs(C_QuestLog.GetQuestObjectives(e.questID) or {}) do
		if not o.finished then
			local need, have = ns.Num(o.numRequired) or 0, ns.Num(o.numFulfilled) or 0
			local kills = self:KillsPer(o.type)
			if kills and need > have then xp = xp + (need - have) * kills * per end
		end
	end
	return xp
end

---------------------------------------------------------------------------
-- Watching
---------------------------------------------------------------------------
local last = {}        -- [quest] = { at = time of its last tick, have = { per objective }, kills = kills since }
local killCount = 0    -- XP-giving kills seen this session

local function Sample(kind, secsPerUnit)
	local base = DEFAULT[kind]
	if not base then return end
	local p = Store()
	local n = p.n[kind] or 0
	p.secs[kind] = Blend(p.secs[kind], n, secsPerUnit)
	p.n[kind] = n + 1
end

function Pc:Watch()
	if not ns.ready or not self:On() then return end
	local now = GetTime()
	local seen = {}
	for _, e in ipairs(ns.Quests.log) do
		local qid = e.questID
		seen[qid] = true
		local rec = last[qid]
		local objs = C_QuestLog.GetQuestObjectives(qid) or {}
		if not rec then
			rec = { have = {}, kills = killCount }
			for i, o in ipairs(objs) do rec.have[i] = ns.Num(o.numFulfilled) or 0 end
			last[qid] = rec
		else
			local ticked
			for i, o in ipairs(objs) do
				local have = ns.Num(o.numFulfilled) or 0
				local gained = have - (rec.have[i] or 0)
				rec.have[i] = have
				if gained > 0 and DEFAULT[o.type] then
					ticked = true
					-- The first tick has nothing to be measured from: the walk there isn't work.
					if rec.at then
						local gap = now - rec.at
						if gap > 0 and gap / gained <= DEFAULT[o.type] * GAP_CAP then
							Sample(o.type, gap / gained)
							if o.type == "item" then
								local p = Store()
								local n = p.kills.n or 0
								p.kills.per = Blend(p.kills.per, n, (killCount - rec.kills) / gained)
								p.kills.n = n + 1
							end
						end
					end
				end
			end
			if ticked then
				rec.at, rec.kills = now, killCount
				if ns.Planner then ns.Planner.dirty = true end
			end
		end
	end
	for qid in pairs(last) do if not seen[qid] then last[qid] = nil end end
end

-- XP that didn't come from a quest (XP.lua tells the two apart).
function Pc:OnKillXP(delta)
	if not self:On() then return end
	delta = ns.Num(delta)
	if not delta or delta <= 0 then return end
	local p = Store()
	local n = p.killN or 0
	if n >= KILL_WARMUP and p.killXP and delta > p.killXP * KILL_OUTLIER then return end
	killCount = killCount + 1
	p.killXP = Blend(p.killXP, n, delta)
	p.killN = n + 1
	p.killLevel = UnitLevel("player")
end

function Pc:Reset()
	ns.char.pace = {}
	last, killCount = {}, 0
	if ns.Planner then ns.Planner.dirty = true end
	if ns.Advisor then ns.Advisor:Forget() end
end

ns:RegisterMessage("QUESTS_UPDATED", function() Pc:Watch() end)
ns:RegisterMessage("KILL_XP", function(_, delta) Pc:OnKillXP(delta) end)

ns:AddSlash("pace", function(rest)
	rest = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if rest == "reset" then
		Pc:Reset()
		ns.Print("pace forgotten. The route uses the standard figures until it has watched you again.")
		return
	elseif rest == "on" or rest == "off" then
		Cfg().learnPace = rest == "on"
		if ns.Planner then ns.Planner.dirty = true end
		if ns.Advisor then ns.Advisor:Forget() end
		ns.Print("learning from your XP and pace is " .. rest .. ".")
		return
	end
	if not Pc:On() then
		ns.Print("learning from your XP and pace is off (/nq pace on). The route uses the standard figures.")
		return
	end
	local p = Store()
	ns.Print("what the route has learned from watching you:")
	local names = { monster = "a kill", item = "an item", object = "an object" }
	for _, kind in ipairs({ "monster", "item", "object" }) do
		local s = Pc:Secs(kind)
		DEFAULT_CHAT_FRAME:AddMessage(string.format("   %s: %s", names[kind], s
			and string.format("about %d seconds (standard %d), from %d", s + 0.5, DEFAULT[kind], p.n[kind])
			or string.format("standard %d seconds for now (%d of %d seen)", DEFAULT[kind], p.n[kind] or 0, WARMUP)))
	end
	local k = Pc:KillXP()
	DEFAULT_CHAT_FRAME:AddMessage("   XP per kill: " .. (k and ns.Comma(math.floor(k + 0.5)) or
		string.format("not known yet (%d of %d kills seen)", p.killN or 0, KILL_WARMUP)))
	local per = Pc:KillsPer("item")
	DEFAULT_CHAT_FRAME:AddMessage("   kills per quest item: " .. (per and string.format("%.1f", per) or "not known yet"))
	DEFAULT_CHAT_FRAME:AddMessage("   /nq pace reset forgets it, /nq pace off stops it.")
end, "/nq pace [reset|on|off] - what the route has learned from your XP gain and pace")
