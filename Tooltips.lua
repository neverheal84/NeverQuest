-- NeverQuest Tooltips: what a mob or an item has to do with your quests, on its tooltip.
--
-- The game already lists your own objectives on a mob it knows belongs to a quest. This adds
-- the two things it leaves out: mobs NeverQuest has learned drop a quest item (the game
-- doesn't flag those until the item is in your bags), and how far along your party is.
-- Item tooltips say which quest wants the item and how many you still need.
--
-- It also keeps the lookup both this and the nameplate icons use: which mob and item names
-- your open objectives are waiting on. All of it comes from your quest log and from what
-- NeverQuest has watched you earn credit from.

local ADDON, ns = ...
local T = {}
ns.Tooltips = T

local SafeCall = ns.SafeCall

local function Cfg() return ns.db.tooltips end

---------------------------------------------------------------------------
-- What your open objectives are waiting on
---------------------------------------------------------------------------
-- { mobs = { [lowercase name] = { ref, ... } }, items = { ... } }, ref = { questID, index, kind }
function T:Index()
	if self.index then return self.index end
	local idx = { mobs = {}, items = {} }
	self.index = idx
	local function Add(map, name, questID, index, kind)
		if type(name) ~= "string" or name == "" then return end
		local key = name:lower()
		local list = map[key]
		if not list then list = {} map[key] = list end
		for _, r in ipairs(list) do
			if r.questID == questID and r.index == index then return end
		end
		table.insert(list, { questID = questID, index = index, kind = kind })
	end
	local sp = ns.Spawns and ns.Spawns:Index()
	if not sp then return idx end
	for questID, q in pairs(sp.quests) do
		for i, o in pairs(q.open) do
			if o.type == "monster" then
				Add(idx.mobs, o.name, questID, i, "kill")
			elseif o.type == "item" or o.type == "object" then
				Add(idx.items, o.name, questID, i, o.type)
			end
		end
	end
	-- Mobs learned as the source of something: a drop, or credit the game gave near them.
	for _, ent in ipairs(sp.entries) do
		if ent.kind == "npc" and ent.name then
			for _, r in ipairs(ent.refs) do
				local q = sp.quests[r.q]
				local o = q and r.i and q.open[r.i]
				if q and (not r.i or o) then
					Add(idx.mobs, ent.name, r.q, r.i, (o and o.type == "monster") and "kill" or "drop")
				end
			end
		end
	end
	return idx
end

function T:Invalidate() self.index = nil end

function T:ForMob(name)
	return type(name) == "string" and self:Index().mobs[name:lower()] or nil
end

function T:ForItem(name)
	return type(name) == "string" and self:Index().items[name:lower()] or nil
end

-- Title, objective text and count for one reference.
function T:Describe(ref)
	local e = ns.Quests.byID[ref.questID]
	local out = { title = e and e.title or ("Quest " .. ref.questID), questID = ref.questID }
	local o = ref.index and (C_QuestLog.GetQuestObjectives(ref.questID) or {})[ref.index]
	if o and o.text and not ns.IsSecret(o.text) then
		out.text = o.text
		out.have, out.need = ns.Num(o.numFulfilled), ns.Num(o.numRequired)
	end
	return out
end

-- The mob the guide's current step is sending you at, lowercase, if it names one.
function T:StepMob()
	local steps = ns.Guide and ns.Guide.steps
	if not steps then return nil end
	for i, s in ipairs(steps) do
		if i > 2 then break end
		local e = s.questID and ns.Quests.byID[s.questID]
		local mob = e and not e.complete and (e.mob or e.dropMob)
		if mob and (s.kind == "objective" or s.kind == "complete") then return mob:lower() end
	end
end

---------------------------------------------------------------------------
-- Lines
---------------------------------------------------------------------------
-- Lines to add to a mob's tooltip: { text, r, g, b }.
function T:UnitLines(unit)
	local cfg = Cfg()
	local lines = {}
	if not unit or not UnitExists(unit) or SafeCall(UnitIsPlayer, unit) ~= false then return lines end
	local refs = self:ForMob(ns.SafeName(unit))
	if not refs then return lines end
	-- When the game knows the mob belongs to a quest it lists your objectives itself.
	local native = SafeCall(C_QuestLog.UnitIsRelatedToActiveQuest, unit) == true
	local partyDone = {}
	for _, ref in ipairs(refs) do
		local d = self:Describe(ref)
		if cfg.units and not native then
			table.insert(lines, { d.title, 1, 0.82, 0 })
			if d.text then
				table.insert(lines, { " - " .. d.text .. (ref.kind == "drop" and "  (drops here)" or ""), 1, 1, 1 })
			elseif ref.kind == "drop" then
				table.insert(lines, { " - drops something this quest needs", 1, 1, 1 })
			end
		end
		if cfg.party and ns.Party and not partyDone[ref.questID] then
			partyDone[ref.questID] = true
			local sum = ns.Party:Summary(ref.questID)
			if sum then table.insert(lines, { d.title .. ": " .. sum, 0.55, 0.8, 1 }) end
		end
	end
	return lines
end

-- Lines for an item: which quest wants it and how many more.
function T:ItemLines(name)
	local lines = {}
	if not Cfg().items then return lines end
	local refs = self:ForItem(name)
	if not refs then return lines end
	for _, ref in ipairs(refs) do
		local d = self:Describe(ref)
		local count = (d.have and d.need and d.need > 0) and string.format("  %d/%d", d.have, d.need) or ""
		table.insert(lines, { "Quest: " .. d.title .. count, 1, 0.82, 0 })
	end
	return lines
end

local function AddLines(tooltip, lines)
	if #lines == 0 then return end
	for _, l in ipairs(lines) do tooltip:AddLine(l[1], l[2], l[3], l[4]) end
	tooltip:Show()
end

local function OnUnit(tooltip)
	if not ns.ready or tooltip ~= GameTooltip then return end
	local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
	if not ok or type(unit) ~= "string" or ns.IsSecret(unit) then return end
	AddLines(tooltip, T:UnitLines(unit))
end

local function OnItem(tooltip)
	if not ns.ready or tooltip ~= GameTooltip then return end
	local ok, name = pcall(tooltip.GetItem, tooltip)
	if not ok or type(name) ~= "string" or ns.IsSecret(name) then return end
	AddLines(tooltip, T:ItemLines(name))
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
local unitGuard, itemGuard = ns.Guard("Quest tooltips", OnUnit), ns.Guard("Quest tooltips", OnItem)
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, unitGuard)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, itemGuard)
elseif GameTooltip and GameTooltip.HookScript then
	pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", unitGuard)
	pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", itemGuard)
end

for _, msg in ipairs({ "QUESTS_UPDATED", "SPAWNS_UPDATED" }) do
	ns:RegisterMessage(msg, function() T:Invalidate() end)
end
