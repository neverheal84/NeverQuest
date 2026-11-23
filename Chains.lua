-- NeverQuest Chains: which quests lead to which, so the guide can favor quests that open up
-- more quests and grab follow-ups while you're standing at the NPC.
--
-- Three sources, in this order:
--   quest lines   the game's C_QuestLine data: the line's name, its quests in order, and
--                 which of them you haven't done yet
--   your play     a quest offered right after you turn one in, that wasn't on offer just
--                 before, is that quest's follow-up. Learned links are shared by all your
--                 characters, so alts know the chains before they get there.
--   the data      what QuestieDB says must come before each quest (QuestDB.lua), read
--                 backwards. Used only where the first
--                 two say nothing, so it helps most on a first character.

local ADDON, ns = ...
local C = {}
ns.Chains = C

local LINK_WINDOW = 45      -- seconds after a turn-in that a new quest counts as its follow-up
local RETRY_AFTER = 60      -- seconds before asking the game again about a quest with no line
local DISCOUNT = { 0.6, 0.4, 0.25 }  -- how much each later quest in a chain adds to its value

local lineCache = {}        -- [questID] = { line = table or false, t = GetTime() }
local requested = {}

local function Clean(text)
	if type(text) ~= "string" or ns.IsSecret(text) or text == "" then return nil end
	return text
end

local function Done(questID)
	return ns.SafeCall(C_QuestLog.IsQuestFlaggedCompleted, questID) == true
end

---------------------------------------------------------------------------
-- The game's quest lines
---------------------------------------------------------------------------
local function FetchLine(questID)
	if not (C_QuestLine and C_QuestLine.GetQuestLineInfo) then return false end
	local m = C_Map.GetBestMapForUnit("player")
	local zone = m and ns.Nav.GetZoneMap(m)
	local info = ns.SafeCall(C_QuestLine.GetQuestLineInfo, questID, zone)
	if type(info) ~= "table" or not ns.Num(info.questLineID) then
		info = ns.SafeCall(C_QuestLine.GetQuestLineInfo, questID)
	end
	if type(info) ~= "table" or not ns.Num(info.questLineID) or info.questLineID == 0 then return false end
	local ids = ns.SafeCall(C_QuestLine.GetQuestLineQuests, info.questLineID)
	if type(ids) ~= "table" or #ids == 0 then return false end
	local index
	for i, id in ipairs(ids) do
		if id == questID then index = i break end
	end
	return { id = info.questLineID, name = Clean(info.questLineName), quests = ids, index = index }
end

-- { id, name, quests = { ids in order }, index = this quest's place } or nil.
function C:Line(questID)
	if not questID then return nil end
	local c = lineCache[questID]
	if c and (c.line or GetTime() - c.t < RETRY_AFTER) then return c.line or nil end
	local line = FetchLine(questID)
	lineCache[questID] = { line = line, t = GetTime() }
	return line or nil
end

---------------------------------------------------------------------------
-- Learned follow-ups
---------------------------------------------------------------------------
function C:Learn(fromID, toID)
	if not fromID or not toID or fromID == toID then return end
	local chains = ns.db.chains
	if chains.next[fromID] == toID then return end
	-- A quest has one learned follow-up and one learned lead-in; the newest sighting wins.
	chains.next[fromID] = toID
	chains.prev[toID] = fromID
	ns.Debug(string.format("chains: quest %d leads to %d", fromID, toID))
	ns:SendMessage("CHAINS_UPDATED")
end

-- The quest before this one (from the game's line, or learned).
function C:Prev(questID)
	local line = self:Line(questID)
	if line and line.index and line.index > 1 then return line.quests[line.index - 1] end
	return ns.db.chains.prev[questID] or (ns.QuestDB and ns.QuestDB:PrevQuest(questID))
end

-- Up to n quests that follow this one and that you haven't done yet, nearest first.
function C:FollowUps(questID, n)
	n = n or 3
	local out, seen = {}, { [questID] = true }
	local line = self:Line(questID)
	if line and line.index then
		for i = line.index + 1, #line.quests do
			local id = line.quests[i]
			if not seen[id] then
				seen[id] = true
				if not Done(id) and not ns.SafeCall(C_QuestLog.IsOnQuest, id) then
					table.insert(out, id)
					if #out >= n then return out end
				end
			end
		end
	end
	local cur = questID
	while #out < n do
		local nextID = ns.db.chains.next[cur]
		if not nextID or seen[nextID] then break end
		seen[nextID] = true
		if not Done(nextID) and not ns.SafeCall(C_QuestLog.IsOnQuest, nextID) then table.insert(out, nextID) end
		cur = nextID
	end
	-- Where the game and your play have nothing more to say, the data carries the chain on.
	if #out < n and ns.QuestDB then
		local steps = 0
		while #out < n and steps < 12 do
			steps = steps + 1
			local nextID = ns.QuestDB:NextQuest(cur, seen)
			if not nextID then break end
			seen[nextID] = true
			if not Done(nextID) and not ns.SafeCall(C_QuestLog.IsOnQuest, nextID) then table.insert(out, nextID) end
			cur = nextID
		end
	end
	return out
end

local function QuestXP(questID, fallback)
	local xp = ns.Num(GetQuestLogRewardXP(questID))
	if xp and xp > 0 then return xp end
	if not requested[questID] then
		requested[questID] = true
		C_QuestLog.RequestLoadQuestByID(questID)
	end
	return fallback or 0
end

-- Extra worth of finishing this quest: part of the XP of the quests it opens up.
-- Returns value, number of follow-ups.
function C:Value(questID, fallbackXP)
	if not ns.db.guide.chains or not questID then return 0, 0 end
	local ups = self:FollowUps(questID, #DISCOUNT)
	local v = 0
	for i, id in ipairs(ups) do
		v = v + QuestXP(id, fallbackXP) * DISCOUNT[i]
	end
	return v, #ups
end

-- Short text for steps and the tracker: "chain: The Defias Brotherhood 3/7" or "leads to 2 more".
function C:Label(questID)
	if not questID then return nil end
	local line = self:Line(questID)
	if line and line.index and #line.quests > 1 then
		return string.format("chain%s %d/%d", line.name and (": " .. line.name) or "", line.index, #line.quests)
	end
	local ups = self:FollowUps(questID, 5)
	if #ups > 0 then
		return "leads to " .. #ups .. (#ups == 1 and " more quest" or " more quests")
	end
	if ns.db.chains.prev[questID] then return "follow-up quest" end
	return nil
end

---------------------------------------------------------------------------
-- Watching turn-ins
---------------------------------------------------------------------------
local offeredNow = {}   -- quests the NPC you're talking to offers right now
local lastTurnIn        -- { q, t, before = { [questID] = true } }

local function NoteGossipOffers()
	wipe(offeredNow)
	for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
		if q.questID then offeredNow[q.questID] = true end
	end
end
ns:RegisterEvent("GOSSIP_SHOW", NoteGossipOffers)
ns:RegisterEvent("QUEST_GREETING", function() wipe(offeredNow) end)

ns:RegisterEvent("QUEST_TURNED_IN", function(_, questID)
	if not ns.ready or not questID then return end
	local before = {}
	for id in pairs(offeredNow) do before[id] = true end
	for _, o in ipairs(ns.Quests.offers) do before[o.questID] = true end
	lastTurnIn = { q = questID, t = GetTime(), before = before, npc = ns.Quests:LastNPC(60) }
end)

-- Only quests from the same NPC count: a quest from the NPC next door isn't a follow-up.
local function MaybeFollowUp(questID)
	if not questID or questID == 0 or not lastTurnIn then return end
	if GetTime() - lastTurnIn.t > LINK_WINDOW then return end
	if questID == lastTurnIn.q or lastTurnIn.before[questID] then return end
	local npc = ns.Quests:LastNPC(10)
	if not npc or (lastTurnIn.npc and npc ~= lastTurnIn.npc) then return end
	C:Learn(lastTurnIn.q, questID)
end

ns:RegisterEvent("QUEST_DETAIL", function() MaybeFollowUp(GetQuestID()) end)
ns:RegisterEvent("QUEST_ACCEPTED", function(_, questID) MaybeFollowUp(questID) end)

-- New quest line data arrived: ask again about quests that had none.
ns:RegisterEvent("QUESTLINE_UPDATE", function()
	for id, c in pairs(lineCache) do
		if not c.line then lineCache[id] = nil end
	end
end)
