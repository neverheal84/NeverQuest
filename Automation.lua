-- NeverQuest Automation: auto accept / turn in quests, pick the most valuable reward, auto loot,
-- and sell junk at vendors. Hold Shift while talking to an NPC (or opening a vendor) to skip it.

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
	ns.Rewards:ClearMark()

	-- Vendor value only, or an upgrade for your class first (Rewards.lua).
	local best
	if cfg.reward == "value" then
		local index, link, value = BestVendorChoice(count)
		best = index and { index = index, link = link, value = value } or nil
	else
		best = ns.Rewards:Best(count)
	end
	if not best then
		if attempt < 6 then ns.After(0.3, function() HandleReward(attempt + 1) end) end
		return
	end
	local what
	if best.upgrade then
		local up = best.upgrade
		what = best.link .. " is an upgrade" .. (up.against and (" over " .. up.against) or " (that slot is empty)")
		local d = ns.Rewards.DiffText(up.diff)
		if d ~= "" then what = what .. " (" .. d .. ")" end
	else
		what = "no upgrade here; highest vendor value: " .. best.link .. " (" .. ns.Money(best.value or 0) .. ")"
	end
	ns.Rewards:MarkButton(best.index)
	local take = (cfg.reward == "value" or cfg.reward == "upgrade") and cfg.turnin and money == 0
	if take then
		ns.Print("took " .. what .. ".")
		GetQuestReward(best.index)
	else
		ns.Print(what .. ". It's marked with a green arrow.")
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

---------------------------------------------------------------------------
-- Auto loot: take everything from a loot window at once. Holding the game's auto-loot key
-- (Shift unless you changed it) leaves the window open so you can look first. Items waiting
-- on a group roll are left alone, and bind-on-pickup items still ask you, as usual.
---------------------------------------------------------------------------
local lootDone = false

function A:LootAll(isGameAutoLoot)
	if type(LootSlot) ~= "function" then return 0 end
	local n = ns.Num(GetNumLootItems and GetNumLootItems()) or 0
	local taken = 0
	for slot = n, 1, -1 do
		local ok, _, _, _, _, _, locked = pcall(GetLootSlotInfo, slot)
		if ok and not (locked == true) then
			LootSlot(slot)
			taken = taken + 1
		end
	end
	return taken
end

ns:RegisterEvent("LOOT_READY", function(_, isGameAutoLoot)
	if lootDone or not ns.db.loot.auto then return end
	local toggleHeld = IsModifiedClick and IsModifiedClick("AUTOLOOTTOGGLE")
	-- The game's own auto loot inverts with that key; ours just steps aside.
	if toggleHeld and not isGameAutoLoot then return end
	lootDone = true
	local taken = A:LootAll(isGameAutoLoot)
	ns.Debug("auto loot: " .. taken .. " slots")
end)
ns:RegisterEvent("LOOT_CLOSED", function() lootDone = false end)

---------------------------------------------------------------------------
-- Sell junk: gray items go when you open a vendor. Hold Shift while opening to skip it.
-- Uses the game's own "sell all junk" when it's there, so nothing can be used by mistake.
---------------------------------------------------------------------------
local merchantOpen = false
A.junkLog = {}

-- Every gray item with a sell price: { bag, slot, itemID, count, value }.
function A:Junk()
	local out, total = {}, 0
	if not (C_Container and C_Container.GetContainerNumSlots) then return out, 0 end
	local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
	for bag = 0, lastBag do
		local slots = ns.SafeCall(C_Container.GetContainerNumSlots, bag) or 0
		for slot = 1, slots do
			local info = ns.SafeCall(C_Container.GetContainerItemInfo, bag, slot)
			if info and info.quality == 0 and not info.hasNoValue and info.itemID then
				local ok, _, _, _, _, _, _, _, _, _, _, price = pcall(C_Item.GetItemInfo, info.itemID)
				price = ok and ns.Num(price) or 0
				if price > 0 then
					local value = price * math.max(1, ns.Num(info.stackCount) or 1)
					table.insert(out, { bag = bag, slot = slot, itemID = info.itemID, count = info.stackCount or 1, value = value, locked = info.isLocked })
					total = total + value
				end
			end
		end
	end
	return out, total
end

-- One item at a time, checking the vendor is still open and the slot still holds that item:
-- using an item with no vendor open would equip or use it.
local function SellNext(queue, i, done)
	if not merchantOpen then return done(i - 1) end
	local item = queue[i]
	if not item then return done(i - 1) end
	local info = ns.SafeCall(C_Container.GetContainerItemInfo, item.bag, item.slot)
	if info and info.itemID == item.itemID and not info.isLocked then
		C_Container.UseContainerItem(item.bag, item.slot)
	end
	C_Timer.After(0.2, function() SellNext(queue, i + 1, done) end)
end

function A:SellJunk(fromCommand)
	if not merchantOpen then return false end
	local junk, total = self:Junk()
	if #junk == 0 then
		if fromCommand then ns.Print("no junk to sell.") end
		return false
	end
	local count = #junk
	local function Report()
		-- Count what actually left your bags.
		local left, leftValue = self:Junk()
		local sold, value = count - #left, total - leftValue
		if sold > 0 and ns.db.loot.junkReport then
			ns.Print(string.format("sold %d junk item%s for %s.", sold, sold == 1 and "" or "s", ns.Money(value)))
		end
		table.insert(self.junkLog, { sold = sold, value = value })
	end
	local usedGame = false
	if C_MerchantFrame and C_MerchantFrame.SellAllJunkItems then
		local enabled = not C_MerchantFrame.IsSellAllJunkEnabled or ns.SafeCall(C_MerchantFrame.IsSellAllJunkEnabled) ~= false
		if enabled then usedGame = pcall(C_MerchantFrame.SellAllJunkItems) end
	end
	if usedGame then
		C_Timer.After(1.5, Report)
	else
		SellNext(junk, 1, function() C_Timer.After(0.5, Report) end)
	end
	return true
end

---------------------------------------------------------------------------
-- Auto repair: everything, from guild funds first if you allow it and the guild pays.
---------------------------------------------------------------------------
A.repairLog = {}
function A:Repair(manual)
	if not (CanMerchantRepair and ns.SafeCall(CanMerchantRepair)) then
		if manual then ns.Print("this vendor can't repair.") end
		return false
	end
	local ok, cost, needed = pcall(GetRepairAllCost)
	cost = ok and ns.Num(cost) or 0
	if not ok or not needed or cost <= 0 then
		if manual then ns.Print("nothing needs repairing.") end
		return false
	end
	local guild = ns.db.loot.repairGuild and CanGuildBankRepair and ns.SafeCall(CanGuildBankRepair)
	if guild then
		local limit = GetGuildBankWithdrawMoney and ns.Num(ns.SafeCall(GetGuildBankWithdrawMoney))
		if limit and limit >= 0 and limit < cost then guild = false end
	end
	if not guild and GetMoney() < cost then
		ns.Print("repairs cost " .. ns.Money(cost) .. ", more than you have.")
		return false
	end
	if not pcall(RepairAllItems, guild and true or nil) then return false end
	table.insert(self.repairLog, { cost = cost, guild = guild and true or false })
	ns.Print("repaired everything for " .. ns.Money(cost) .. (guild and " (guild funds)." or "."))
	return true
end

ns:RegisterEvent("MERCHANT_SHOW", function()
	merchantOpen = true
	if IsShiftKeyDown() then return end
	if ns.db.loot.repair then A:Repair() end
	if ns.db.loot.junk then
		C_Timer.After(0.3, function() if merchantOpen then A:SellJunk() end end)
	end
end)

ns:AddSlash("repair", function(arg)
	arg = (arg or ""):lower()
	if arg == "on" or arg == "off" then
		ns.db.loot.repair = arg == "on"
		ns.Print("auto repair " .. (ns.db.loot.repair and "on." or "off."))
	elseif arg == "guild" then
		ns.db.loot.repairGuild = not ns.db.loot.repairGuild
		ns.Print("guild-funded repairs " .. (ns.db.loot.repairGuild and "on (used when your guild allows it)." or "off."))
	elseif merchantOpen then
		A:Repair(true)
	else
		ns.Print("auto repair is " .. (ns.db.loot.repair and "on" or "off") .. ". /nq repair on|off|guild")
	end
end, "/nq repair [on|off|guild] - repair at vendors automatically (guild funds optional)")
ns:RegisterEvent("MERCHANT_CLOSED", function() merchantOpen = false end)
function A:MerchantOpen() return merchantOpen end

ns:AddSlash("junk", function()
	if merchantOpen then
		A:SellJunk(true)
	else
		local junk, total = A:Junk()
		ns.Print(#junk == 0 and "no junk in your bags." or string.format("%d junk item%s worth %s; %s", #junk, #junk == 1 and "" or "s", ns.Money(total),
			ns.db.loot.junk and "they sell when you next open a vendor." or "open a vendor and type /nq junk to sell them."))
	end
end, "/nq junk - sell gray items now (at a vendor), or see what they're worth")

ns:AddSlash("loot", function(arg)
	arg = (arg or ""):lower()
	if arg == "on" or arg == "off" then ns.db.loot.auto = arg == "on" else ns.db.loot.auto = not ns.db.loot.auto end
	ns.Print("auto loot " .. (ns.db.loot.auto and "on (hold Shift to look first)." or "off."))
end, "/nq loot [on|off] - auto loot everything at once")
