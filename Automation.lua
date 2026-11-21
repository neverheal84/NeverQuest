-- NeverQuest Automation: auto accept / turn in quests and pick the most valuable reward.
-- Hold Shift while talking to an NPC to skip all of it.

local ADDON, ns = ...
local A = {}
ns.Automation = A

local function Skip()
	return IsShiftKeyDown()
end

local function IsGray(questID)
	return questID and questID > 0 and C_QuestLog.IsQuestTrivial(questID)
end

---------------------------------------------------------------------------
-- Quest dialog
---------------------------------------------------------------------------
ns:RegisterEvent("QUEST_DETAIL", function(_, questStartItemID)
	local cfg = ns.db.auto
	if not cfg.accept or Skip() then return end
	if questStartItemID and questStartItemID ~= 0 then return end  -- item-started: Blizzard shows its own popup
	local questID = GetQuestID()
	if not questID or questID == 0 then return end
	if QuestFlagsPVP and QuestFlagsPVP() then return end            -- PvP quests need a confirmation
	if cfg.skipGray and IsGray(questID) then return end
	if QuestGetAutoAccept() then
		if QuestIsFromAreaTrigger and QuestIsFromAreaTrigger() then return end
		AcknowledgeAutoAcceptQuest()
	else
		AcceptQuest()
	end
	ns.Debug("auto-accepted quest " .. questID)
end)

ns:RegisterEvent("QUEST_PROGRESS", function()
	local cfg = ns.db.auto
	if not cfg.turnin or Skip() then return end
	local questID = GetQuestID()
	if cfg.skipRepeatable and questID and questID > 0 and C_QuestLog.IsRepeatableQuest(questID) then return end
	if IsQuestCompletable() then
		CompleteQuest()
		ns.Debug("auto-completed quest " .. tostring(questID))
	end
end)

-- Vendor value of each reward choice; returns best index, its link and value, or nil if data is still loading.
local function BestVendorChoice(count)
	local bestIndex, bestValue, bestLink = nil, -1, nil
	for i = 1, count do
		local link = GetQuestItemLink("choice", i)
		if not link then return nil end
		local _, _, _, _, _, _, _, _, _, _, sellPrice = C_Item.GetItemInfo(link)
		if sellPrice == nil then return nil end
		local _, _, numItems = GetQuestItemInfo("choice", i)
		local value = (ns.Num(sellPrice) or 0) * math.max(1, ns.Num(numItems) or 1)
		if value > bestValue then bestIndex, bestValue, bestLink = i, value, link end
	end
	return bestIndex, bestLink, bestValue
end

local function HandleReward(attempt)
	local cfg = ns.db.auto
	if QuestFrameRewardPanel and not QuestFrameRewardPanel:IsShown() then return end
	local count = GetNumQuestChoices() or 0
	local money = GetQuestMoneyToGet and GetQuestMoneyToGet() or 0

	if count <= 1 then
		if cfg.turnin and money == 0 then
			GetQuestReward(count)
			ns.Debug("auto turn-in, reward choice " .. count)
		end
		return
	end
	if cfg.reward == "off" then return end

	local index, link, value = BestVendorChoice(count)
	if not index then
		if attempt < 6 then ns.After(0.3, function() HandleReward(attempt + 1) end) end
		return
	end
	if cfg.reward == "value" and cfg.turnin and money == 0 then
		ns.Print("took highest vendor value: " .. link .. " (" .. ns.Money(value) .. ")")
		GetQuestReward(index)
	else
		ns.Print("highest vendor value: " .. link .. " (" .. ns.Money(value) .. "). Check it against any upgrade before choosing.")
	end
end

ns:RegisterEvent("QUEST_COMPLETE", function()
	if Skip() then return end
	local cfg = ns.db.auto
	if not cfg.turnin and cfg.reward == "off" then return end
	local questID = GetQuestID()
	if cfg.skipRepeatable and questID and questID > 0 and C_QuestLog.IsRepeatableQuest(questID) then return end
	-- Let Blizzard's quest frame finish laying out the reward panel first.
	ns.After(0.05, function() HandleReward(1) end)
end)

---------------------------------------------------------------------------
-- NPC gossip and quest greeting windows: turn in finished quests first, then take new ones
---------------------------------------------------------------------------
-- Each quest is auto-picked at most once per 30 seconds, so declining a quest (or one we
-- chose not to accept) doesn't bounce you straight back into it.
local recentlyPicked = {}
local function FreshPick(key)
	local now = GetTime()
	if recentlyPicked[key] and now - recentlyPicked[key] < 30 then return false end
	recentlyPicked[key] = now
	return true
end

ns:RegisterEvent("GOSSIP_SHOW", function()
	local cfg = ns.db.auto
	if not cfg.gossip or Skip() then return end
	if cfg.turnin then
		for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
			if q.isComplete and q.questID and not (cfg.skipRepeatable and q.repeatable) and FreshPick("a" .. q.questID) then
				return C_GossipInfo.SelectActiveQuest(q.questID)
			end
		end
	end
	if cfg.accept then
		for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
			if q.questID and not q.isIgnored and not (cfg.skipGray and q.isTrivial) and not (cfg.skipRepeatable and q.repeatable)
				and FreshPick("n" .. q.questID) then
				return C_GossipInfo.SelectAvailableQuest(q.questID)
			end
		end
	end
end)

ns:RegisterEvent("QUEST_GREETING", function()
	local cfg = ns.db.auto
	if not cfg.gossip or Skip() then return end
	if cfg.turnin then
		for i = 1, GetNumActiveQuests() do
			local title, isComplete = GetActiveTitle(i)
			if isComplete and FreshPick("ga" .. tostring(title)) then return SelectActiveQuest(i) end
		end
	end
	if cfg.accept then
		for i = 1, GetNumAvailableQuests() do
			local isTrivial, _, isRepeatable = GetAvailableQuestInfo(i)
			if not (cfg.skipGray and isTrivial) and not (cfg.skipRepeatable and isRepeatable)
				and FreshPick("gn" .. tostring(GetAvailableTitle and GetAvailableTitle(i) or i)) then
				return SelectAvailableQuest(i)
			end
		end
	end
end)
