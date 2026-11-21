-- NeverQuest Catchup: party catch-up mode. In a party, the guide and route adapt so everyone
-- keeps up together:
--   shared quests first     quests your party members also have count for more
--   help before handing in  if you've finished a quest a party member hasn't, the turn-in waits
--                           and the route takes you back to its objective spot to help
--   their quests            quest givers for quests a party member is on count for more, and
--                           the guide suggests asking them to share the ones you can't pick up
--   your quests             the guide suggests sharing quests they don't have (click to share)
--   group level             zones are chosen for the lowest level in the party
--   regroup                 when someone is far away, a step points the arrow at them
-- Quest lists come from party members running NeverQuest (Party.lua); levels and positions come
-- from the game for everyone in the party.

local ADDON, ns = ...
local C = {}
ns.Catchup = C

local REGROUP_YARDS = 300
local SHARED_BONUS, SHARED_MAX = 0.25, 1.6
local WAIT = 0.35          -- a turn-in waits while a party member is still working on that quest
local THEIRS = 2.5         -- picking up a quest a party member is on
local HELP_SHARE = 0.6     -- helping a party member finish is worth part of the quest's XP to the group

local function Cfg() return ns.db.party end

function C:Active()
	return (ns.ready and Cfg().catchUp and IsInGroup() and not IsInRaid() and UnitExists("party1")) and true or false
end

local function Completed(questID)
	return ns.SafeCall(C_QuestLog.IsQuestFlaggedCompleted, questID) == true
end

-- Everyone else in the party: name, level, position, and their quests if they run NeverQuest.
function C:Mates()
	local out = {}
	for i = 1, 4 do
		local unit = "party" .. i
		if UnitExists(unit) then
			local name = ns.SafeName(unit)
			local mate = { unit = unit, name = name or unit, level = ns.Num(UnitLevel(unit)) }
			local member = name and ns.Party.members[name]
			mate.quests = member and member.quests or nil
			local m = ns.SafeCall(C_Map.GetBestMapForUnit, unit)
			if m then
				local pos = ns.SafeCall(C_Map.GetPlayerMapPosition, m, unit)
				if pos then
					local x, y = pos:GetXY()
					x, y = ns.Num(x), ns.Num(y)
					if x and y and not (x == 0 and y == 0) then
						mate.m, mate.x, mate.y = m, x, y
						mate.dist = ns.Nav.Distance(m, x, y)
					end
				end
			end
			table.insert(out, mate)
		end
	end
	return out
end

local function AddName(t, qid, name, extra)
	t[qid] = t[qid] or {}
	table.insert(t[qid], extra or name)
end

-- Who shares what, who's behind, and the party's lowest level. Recomputed at most once a second.
function C:State()
	if not self:Active() then
		self.state = nil
		return nil
	end
	local now = GetTime()
	if self.state and now - self.state.t < 1 then return self.state end
	local st = { t = now, mates = self:Mates(), shared = {}, behind = {}, theirs = {}, lacking = {}, withAddon = 0 }
	st.myLevel = UnitLevel("player")
	st.groupLevel = st.myLevel
	for _, mate in ipairs(st.mates) do
		if mate.level and mate.level < st.groupLevel then st.groupLevel, st.lowest = mate.level, mate end
	end
	local mine = ns.Quests.byID
	for _, mate in ipairs(st.mates) do
		if mate.quests then
			st.withAddon = st.withAddon + 1
			for qid, state in pairs(mate.quests) do
				local e = mine[qid]
				if e then
					AddName(st.shared, qid, mate.name)
					if e.complete and state ~= "c" then
						AddName(st.behind, qid, nil, { name = mate.name, pct = tonumber(state) or 0 })
					end
				elseif state ~= "c" and not Completed(qid) then
					AddName(st.theirs, qid, mate.name)
				end
			end
			for qid in pairs(mine) do
				if mate.quests[qid] == nil then AddName(st.lacking, qid, mate.name) end
			end
		end
	end
	self.state = st
	return st
end

function C:Invalidate()
	self.state = nil
end

-- Level to plan zones for: the lowest in the party when that setting is on.
function C:PlanLevel(myLevel)
	local st = Cfg().groupLevel and self:State()
	if st and st.groupLevel < myLevel - 1 then return st.groupLevel, st.lowest end
	return myLevel
end

-- How much a quest is worth to the route in catch-up mode.
function C:Weight(questID, complete, isPickup)
	local st = self:State()
	if not st then return 1 end
	if isPickup then return st.theirs[questID] and THEIRS or 1 end
	local w = 1
	local shared = st.shared[questID]
	if shared and not complete then w = w * math.min(SHARED_MAX, 1 + SHARED_BONUS * #shared) end
	if complete and st.behind[questID] then w = w * WAIT end
	return w
end

local function Names(list, field)
	local out = {}
	for _, v in ipairs(list) do
		if type(v) == "table" then
			table.insert(out, field == "pct" and string.format("%s %d%%", v.name, v.pct) or v.name)
		else
			table.insert(out, v)
		end
	end
	return table.concat(out, ", ")
end
C.Names = Names

-- For a finished quest a party member is still on: where to go to help, and what it's worth.
function C:HelpFor(e, avgXP)
	local st = self:State()
	local behind = st and st.behind[e.questID]
	if not behind then return nil end
	local spot = ns.Spawns and ns.Spawns:AnySpotFor(e.questID)
	return {
		names = Names(behind, "pct"), spot = spot,
		value = ((e.xp and e.xp > 0) and e.xp or avgXP or 300) * HELP_SHARE * #behind,
	}
end

function C:Note(questID, kind)
	local st = self:State()
	if not st then return nil end
	if kind == "pickup" and st.theirs[questID] then
		return Names(st.theirs[questID]) .. " on this"
	elseif kind == "turnin" and st.behind[questID] then
		return "waiting for " .. Names(st.behind[questID], "pct")
	end
end

function C:Share(questID)
	if not questID or not IsInGroup() then return false end
	if ns.SafeCall(C_QuestLog.IsPushableQuest, questID) ~= true then
		ns.Print("that quest can't be shared.")
		return false
	end
	local index = ns.SafeCall(C_QuestLog.GetLogIndexForQuestID, questID)
	if not index then return false end
	QuestLogPushQuest(index)
	ns.PlaySound(SOUNDKIT.IG_QUEST_LOG_OPEN)
	return true
end

---------------------------------------------------------------------------
-- Guide rows
---------------------------------------------------------------------------
local function After(steps)
	local at = 1
	while steps[at] and (steps[at].milestoneKey or ((steps[at].kind == "turnin" or steps[at].kind == "pickup")
		and not steps[at].predicted and steps[at].dist and steps[at].dist <= 300)) do
		at = at + 1
	end
	return at
end

function C:Steps(steps)
	local st = self:State()
	if not st then return end
	local cfg = Cfg()

	-- Regroup: point the arrow at whoever is furthest away.
	if cfg.regroup then
		local far
		for _, mate in ipairs(st.mates) do
			if mate.dist and mate.dist > REGROUP_YARDS and (not far or mate.dist > far.dist) then far = mate end
		end
		if far then
			table.insert(steps, After(steps), { kind = "goto", key = "regroup:" .. far.name, m = far.m, x = far.x, y = far.y,
				title = string.format("Regroup with %s (%s away)", far.name, ns.Yards(far.dist)),
				navTitle = far.name, sub = "Party catch-up: quest together so nobody falls behind.", color = { 0.4, 0.8, 1 }, regroup = true })
		end
	end

	-- Summary of the party.
	local parts = {}
	for _, mate in ipairs(st.mates) do
		table.insert(parts, mate.name .. (mate.level and (" " .. mate.level) or ""))
	end
	local sub = {}
	if st.lowest and st.groupLevel < st.myLevel - 1 and cfg.groupLevel then
		table.insert(sub, string.format("zones for level %d (%s)", st.groupLevel, st.lowest.name))
	end
	local nShared, nBehind = 0, 0
	for _ in pairs(st.shared) do nShared = nShared + 1 end
	for _ in pairs(st.behind) do nBehind = nBehind + 1 end
	if nShared > 0 then table.insert(sub, nShared .. " shared " .. (nShared == 1 and "quest" or "quests") .. " first") end
	if nBehind > 0 then table.insert(sub, nBehind .. " turn-in" .. (nBehind == 1 and "" or "s") .. " waiting for the party") end
	if st.withAddon < #st.mates then table.insert(sub, "quest lists only from party members running NeverQuest") end
	table.insert(steps, { kind = "tip", key = "tip:party", title = "Party catch-up: " .. table.concat(parts, ", "),
		sub = #sub > 0 and table.concat(sub, "  ·  ") or "Shared quests first; turn-ins wait for everyone.", color = { 0.4, 0.8, 1 } })

	if not cfg.shareTips then return end
	-- Quests you can share with them, and quests to ask them for (not on offer near you).
	local offered = {}
	for _, o in ipairs(ns.Quests.offers) do offered[o.questID] = true end
	local n = 0
	for qid, names in pairs(st.lacking) do
		local e = ns.Quests.byID[qid]
		if n < 2 and e and not e.trivial and ns.SafeCall(C_QuestLog.IsPushableQuest, qid) == true then
			n = n + 1
			table.insert(steps, { kind = "tip", key = "share:" .. qid, questID = qid, shareQuest = qid,
				title = "Share with your party: " .. e.title, sub = Names(names) .. " doesn't have it. Click to share.", color = { 0.4, 0.8, 1 } })
		end
	end
	n = 0
	for qid, names in pairs(st.theirs) do
		if n < 2 and not offered[qid] then
			local title = ns.SafeCall(C_QuestLog.GetTitleForQuestID, qid)
			if title then
				n = n + 1
				table.insert(steps, { kind = "tip", key = "ask:" .. qid, questID = qid,
					title = "Ask " .. Names(names) .. " to share: " .. title, sub = "They're on it and you don't have it.", color = { 0.4, 0.8, 1 } })
			end
		end
	end
end

for _, msg in ipairs({ "PARTY_UPDATED", "QUESTS_UPDATED" }) do
	ns:RegisterMessage(msg, function()
		C:Invalidate()
		if ns.Planner then ns.Planner.dirty = true end
	end)
end
ns:RegisterEvent("GROUP_ROSTER_UPDATE", function() C:Invalidate() end)
ns:RegisterEvent("UNIT_LEVEL", function(_, unit)
	if unit and unit:match("^party") then C:Invalidate() end
end)
