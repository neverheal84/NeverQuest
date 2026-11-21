-- NeverQuest Upkeep: the small things that cost leveling time. A full quest log (and what to
-- drop), running low on food, water or ammo, full bags and leftover quest items, logging out
-- where no rested XP builds, a session summary, and asking for a group for elite quests.

local ADDON, ns = ...
local U = { session = {} }
ns.Upkeep = U

local function Cfg() return ns.db.upkeep end

-- Reminders you right-clicked away: hidden until you log in again.
U.hidden = {}
function U:Hide(key)
	if not key then return end
	self.hidden[key] = true
	ns.Print("reminder hidden until you log in again.")
	if ns.Guide then ns.Guide:Refresh() end
end
function U:Shown(row) return row and not self.hidden[row.key] and row or nil end

---------------------------------------------------------------------------
-- Quest log
---------------------------------------------------------------------------
function U:LogCount()
	local max = ns.Num(ns.SafeCall(C_QuestLog.GetMaxNumQuestsCanAccept)) or 25
	local _, n = C_QuestLog.GetNumQuestLogEntries()
	return ns.Num(n) or #ns.Quests.log, max
end

-- Quests worth dropping first: failed, gray, far away, little XP for the walk. Never ones that
-- are ready to hand in, and never the attunement chain you follow.
function U:DropCandidates(limit)
	local followed = ns.Attune and ns.Attune:Following()
	local out = {}
	for _, e in ipairs(ns.Quests.log) do
		if not e.complete then
			local inChain = followed and ns.Attune.Matches and (function()
				for _, step in ipairs(followed.steps) do if ns.Attune.Matches(step, e.title) then return true end end
			end)()
			if not inChain then
				local score = 0
				local why = {}
				if e.failed then score = score + 200 table.insert(why, "failed") end
				if e.trivial then score = score + 100 table.insert(why, "gray") end
				if e.dist then
					score = score + math.min(80, e.dist / 100)
					if e.dist > 1500 then table.insert(why, ns.Yards(e.dist) .. " away") end
				else
					score = score + 20
					table.insert(why, "no map pin")
				end
				local xp = e.xp or 0
				if xp > 0 and e.dist and e.dist > 0 then score = score + math.max(0, 30 - xp / e.dist * 10) end
				if e.group then score = score + 15 table.insert(why, "group quest") end
				table.insert(out, { e = e, score = score, why = table.concat(why, ", ") })
			end
		end
	end
	table.sort(out, function(a, b) return a.score > b.score end)
	while #out > (limit or 3) do table.remove(out) end
	return out
end

local function DropText(c)
	return c.e.title .. (c.why ~= "" and (" (" .. c.why .. ")") or "")
end

ns:RegisterEvent("QUEST_DETAIL", function()
	if not ns.ready or not Cfg().logFull then return end
	local n, max = U:LogCount()
	if n < max then return end
	local drop = U:DropCandidates(1)[1]
	ns.Print(string.format("your quest log is full (%d/%d). %s", n, max,
		drop and ("Drop " .. DropText(drop) .. " to make room.") or "Drop a quest to make room."))
end)

---------------------------------------------------------------------------
-- Bags and supplies
---------------------------------------------------------------------------
local LAST_BAG = NUM_BAG_SLOTS or 4

local function EachBagItem(fn)
	if not (C_Container and C_Container.GetContainerNumSlots) then return end
	for bag = 0, LAST_BAG do
		local slots = ns.SafeCall(C_Container.GetContainerNumSlots, bag) or 0
		for slot = 1, slots do
			local info = ns.SafeCall(C_Container.GetContainerItemInfo, bag, slot)
			if info and info.itemID then fn(bag, slot, info) end
		end
	end
end
U.EachBagItem = EachBagItem

function U:FreeSlots()
	local free = 0
	if not (C_Container and C_Container.GetContainerNumFreeSlots) then return nil end
	for bag = 0, LAST_BAG do
		-- Only general bags count (bag family 0), not quivers or soul bags.
		local ok, n, family = pcall(C_Container.GetContainerNumFreeSlots, bag)
		n = ok and ns.Num(n)
		if n and (not family or family == 0) then free = free + n end
	end
	return free
end

-- Food & drink and ammo (projectiles) in your bags. Food is the "Food & Drink" consumable type,
-- or anything whose use is the Food, Drink or Refreshment spell.
local EAT = { Food = true, Drink = true, Refreshment = true }
local function IsFood(itemID, classID, subclassID)
	if classID ~= 0 then return false end
	if subclassID == 5 then return true end
	local ok, spell = pcall(C_Item.GetItemSpell, itemID)
	return ok and type(spell) == "string" and not ns.IsSecret(spell) and EAT[spell] or false
end

function U:Supplies()
	local food, ammo = 0, 0
	EachBagItem(function(_, _, info)
		local ok, _, _, _, _, _, classID, subclassID = pcall(C_Item.GetItemInfoInstant, info.itemID)
		if ok then
			if IsFood(info.itemID, classID, subclassID) then food = food + (info.stackCount or 1) end
			if classID == 6 then ammo = ammo + (info.stackCount or 1) end
		end
	end)
	return food, ammo
end

local function UsesAmmo()
	if select(2, UnitClass("player")) ~= "HUNTER" then return false end
	local link = GetInventoryItemLink("player", 18)
	if not link then return false end
	local ok, _, _, _, equipLoc = pcall(C_Item.GetItemInfoInstant, link)
	return ok and equipLoc ~= "INVTYPE_THROWN" and equipLoc ~= "INVTYPE_RELIC"
end

-- Quest items you no longer need: ones that start a quest you've already done, and quest items
-- no quest in your log mentions (those are only "probably" leftovers).
function U:Leftovers()
	local sure, maybe = {}, {}
	local mentioned = {}
	for _, e in ipairs(ns.Quests.log) do
		local objectives = ns.SafeCall(C_QuestLog.GetQuestObjectives, e.questID)
		for _, o in ipairs(type(objectives) == "table" and objectives or {}) do
			if type(o.text) == "string" and not ns.IsSecret(o.text) then mentioned[#mentioned + 1] = o.text:lower() end
		end
		if e.item and e.item.id then mentioned[#mentioned + 1] = "item:" .. e.item.id end
	end
	EachBagItem(function(bag, slot, info)
		local q = C_Container.GetContainerItemQuestInfo and ns.SafeCall(C_Container.GetContainerItemQuestInfo, bag, slot)
		local name = info.itemName
		if q and q.questID and not q.isActive and ns.SafeCall(C_QuestLog.IsQuestFlaggedCompleted, q.questID) == true then
			table.insert(sure, { name = name, bag = bag, slot = slot })
		elseif q and q.isQuestItem and not q.questID and type(name) == "string" then
			local lname, found = name:lower(), false
			for _, text in ipairs(mentioned) do
				if text:find(lname, 1, true) or text == "item:" .. info.itemID then found = true break end
			end
			if not found then table.insert(maybe, { name = name, bag = bag, slot = slot }) end
		end
	end)
	return sure, maybe
end

-- Bag contents only change on BAG_UPDATE_DELAYED, so the guide (which refreshes often) reads
-- a cached answer.
function U:BagState()
	local c = self.bagCache
	if c then return c end
	local food, ammo = self:Supplies()
	c = { food = food, ammo = ammo, free = self:FreeSlots() }
	c.upgrade, c.junk = self:BagFinds()
	self.bagCache = c
	return c
end

-- Two things worth knowing about what's in your bags: the gear that beats what you're wearing
-- most, and the junk that is worth least (the one to throw out when you need a slot now).
function U:BagFinds()
	local best, cheap
	EachBagItem(function(bag, slot, info)
		local link = info.hyperlink
		if not link then return end
		local name = link:match("%[(.-)%]") or "item"
		if info.quality == 0 then
			if not info.hasNoValue then
				local ok, _, _, _, _, _, _, _, _, _, _, price = pcall(C_Item.GetItemInfo, info.itemID)
				price = ok and ns.Num(price) or nil
				if price and price > 0 then
					local value = price * math.max(1, ns.Num(info.stackCount) or 1)
					if not cheap or value < cheap.value then cheap = { name = name, link = link, value = value } end
				end
			end
		elseif Cfg().upgrades and ns.Rewards and ns.Rewards.Upgrade then
			local cmp = ns.Rewards:Upgrade(link)
			if cmp and (not best or cmp.gain > best.cmp.gain) then best = { name = name, link = link, cmp = cmp } end
		end
	end)
	return best, cheap
end

ns:RegisterEvent("BAG_UPDATE_DELAYED", function()
	U.bagCache = nil
	ns.Debounce("upkeep:bags", 1, function() if ns.Guide then ns.Guide:Refresh() end end)
end)

-- Guide rows for the things above.
function U:Tips(level)
	local cfg = Cfg()
	local rows = {}
	if cfg.logFull then
		local n, max = self:LogCount()
		if n >= max then
			local drops = self:DropCandidates(2)
			local names = {}
			for _, c in ipairs(drops) do table.insert(names, DropText(c)) end
			table.insert(rows, { kind = "tip", key = "tip:logfull", questID = drops[1] and drops[1].e.questID,
				title = string.format("Quest log full (%d/%d)", n, max),
				openQuest = drops[1] and drops[1].e.questID,
				sub = #names > 0 and ("Drop one to make room: " .. table.concat(names, "; ") .. ". Click to open it in your quest log.") or "Drop a quest to make room.",
				color = { 1, 0.6, 0.3 } })
		end
	end
	local bags = self:BagState()
	if cfg.upgrades and bags.upgrade then
		local up = bags.upgrade
		local diff = ns.Rewards.DiffText(up.cmp.diff)
		local against = up.cmp.against and up.cmp.against:match("%[(.-)%]")
		table.insert(rows, { kind = "tip", key = "tip:upgrade:" .. up.name,
			title = "Upgrade in your bags: " .. up.name,
			sub = (diff ~= "" and (diff .. " ") or "") .. (against and ("over your " .. against .. ".") or "for a slot you have nothing in.")
				.. " Right-click to hide this.",
			color = { 0.4, 1, 0.5 } })
	end
	if cfg.supplies and (level or 0) >= 5 then
		local food, ammo = bags.food, bags.ammo
		if food < (cfg.foodMin or 10) then
			table.insert(rows, { kind = "tip", key = "tip:food",
				title = string.format("Low on food and water (%d left)", food),
				sub = "Stock up at the next innkeeper or food vendor before heading out.", color = { 1, 0.8, 0.4 } })
		end
		if UsesAmmo() and ammo < (cfg.ammoMin or 200) then
			table.insert(rows, { kind = "tip", key = "tip:ammo",
				title = string.format("Low on ammo (%d left)", ammo),
				sub = "Buy arrows or shot at the next general goods or weapon vendor.", color = { 1, 0.8, 0.4 } })
		end
	end
	if cfg.bags then
		local free = bags.free
		if free and free <= (cfg.bagsMin or 3) then
			local sure, maybe = self:Leftovers()
			local extra = ""
			if #sure > 0 then
				local names = {}
				for i = 1, math.min(3, #sure) do names[i] = sure[i].name end
				extra = "  Safe to delete (quest already done): " .. table.concat(names, ", ") .. "."
			elseif #maybe > 0 then
				local names = {}
				for i = 1, math.min(3, #maybe) do names[i] = maybe[i].name end
				extra = "  Probably leftovers (no quest in your log uses them): " .. table.concat(names, ", ") .. "."
			end
			if bags.junk then
				extra = extra .. "  Need a slot now? Your cheapest junk is " .. bags.junk.name .. " (" .. ns.Money(bags.junk.value) .. ")."
			end
			table.insert(rows, { kind = "tip", key = "tip:bags",
				title = string.format("Bags almost full (%d free)", free),
				sub = "Gray items sell automatically at the next vendor." .. extra, color = { 1, 0.8, 0.4 } })
		end
	end
	local out = {}
	for _, row in ipairs(rows) do
		if not self.hidden[row.key] then
			row.reminder = true
			table.insert(out, row)
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Logging out
---------------------------------------------------------------------------
local SLEEPING_BAG = "cozy sleeping bag"
function U:HasSleepingBag()
	local found = false
	EachBagItem(function(_, _, info)
		if type(info.itemName) == "string" and info.itemName:lower() == SLEEPING_BAG then found = true end
	end)
	return found
end

ns:RegisterEvent("PLAYER_CAMPING", function()
	if not ns.ready then return end
	local cfg = Cfg()
	if cfg.rested and not IsResting() and not (ns.XP and ns.XP.IsMaxLevel and ns.XP:IsMaxLevel()) then
		if U:HasSleepingBag() then
			ns.Print("you're logging out where no rested XP builds. Put down your Cozy Sleeping Bag first, or log out at an inn.")
		else
			ns.Print("you're logging out where no rested XP builds. An inn or a city is worth the walk.")
		end
	end
	if cfg.sessionAtLogout then U:PrintSession() end
end)

---------------------------------------------------------------------------
-- Session summary
---------------------------------------------------------------------------
ns:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)
	if U.session.start then return end
	U.session = { start = GetTime(), money = GetMoney(), level = UnitLevel("player"), deaths = 0 }
end)
ns:RegisterEvent("PLAYER_DEAD", function() U.session.deaths = (U.session.deaths or 0) + 1 end)

function U:SessionLines()
	local s = self.session
	if not s.start then return {} end
	local mins = math.max(1, math.floor((GetTime() - s.start) / 60))
	local xp = ns.XP and ns.XP.session or {}
	local levels = UnitLevel("player") - (s.level or UnitLevel("player"))
	local money = GetMoney() - (s.money or GetMoney())
	local perHour = (xp.total or 0) / mins * 60
	local lines = {
		string.format("Played %dh %02dm, %s XP (%s an hour)%s.", math.floor(mins / 60), mins % 60, ns.Comma(xp.total or 0),
			ns.Comma(math.floor(perHour)), levels > 0 and string.format(", %d level%s", levels, levels == 1 and "" or "s") or ""),
		string.format("%d quests handed in, %d kills.", xp.quests or 0, xp.kills or 0),
		string.format("Gold %s%s.", money >= 0 and "+" or "-", ns.Money(math.abs(money))) .. ((s.deaths or 0) > 0 and string.format(" Deaths: %d.", s.deaths) or ""),
	}
	return lines
end

function U:PrintSession()
	ns.Print("this session:")
	for _, l in ipairs(self:SessionLines()) do DEFAULT_CHAT_FRAME:AddMessage("   " .. l) end
end

ns:AddSlash("session", function() U:PrintSession() end, "/nq session - what this play session brought in")

---------------------------------------------------------------------------
-- Asking for a group
---------------------------------------------------------------------------
function U:GroupText(e)
	local link = GetQuestLink and ns.SafeCall(GetQuestLink, e.questID)
	local name = (type(link) == "string" and link ~= "" and link) or ("[" .. (e.title or "quest") .. "]")
	local pct = math.floor((e.progress or 0) * 100 + 0.5)
	return string.format("LFG %s%s, anyone on it?", name, pct > 0 and string.format(" (%d%% done)", pct) or "")
end

-- Puts the message in your chat box to send yourself: nothing goes out without you.
function U:AskForGroup(e)
	if not e then return false end
	local text = self:GroupText(e)
	local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
	if open then pcall(open, text) return true end
	return false
end

ns:AddSlash("lfg", function()
	local pick
	for _, s in ipairs(ns.Guide.steps or {}) do
		local e = s.questID and ns.Quests.byID[s.questID]
		if e and not e.complete and (e.group or e.elite) then pick = e break end
	end
	if not pick then
		for _, e in ipairs(ns.Quests.log) do if not e.complete and (e.group or e.elite) then pick = e break end end
	end
	if not pick then ns.Print("no group or elite quests in your log.") return end
	U:AskForGroup(pick)
end, "/nq lfg - put a looking-for-group message for your next elite quest in the chat box")
