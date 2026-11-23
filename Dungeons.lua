-- NeverQuest Dungeons: get a dungeon's quests, and whatever has to be done first, before you run it.
--
-- With the option on (Options > Guide & Routes, or the setup wizard), for each dungeon you've
-- ticked whose level window is coming up, the route picks up its quests. When a quest isn't open
-- to you yet, the route goes for the first quest of the chain that leads to it. Those pickups, and
-- the pre-quests already in your log, count for a lot more on the route than ordinary quests.
-- Dungeon quests in your log wait for the dungeon instead of sending you to its entrance alone.
--
-- Which quests belong to which dungeon comes from three places:
--   * QuestieDB, which files each quest under a zone or a dungeon (not used with Build my own);
--   * the game, which tags a dungeon quest "Dungeon" and says which map it belongs to (this is
--     how dungeons missing from the list below are found, the ones new in WoW Forever among them);
--   * your quest log, which lists dungeon quests under the dungeon's name. Anything one of your
--     characters picks up is remembered for all of them.

local ADDON, ns = ...
local DQ = {}
ns.Dungeons = DQ

-- The game's area numbers for the classic dungeons, which is how QuestieDB files their quests.
-- For dungeons not listed here, the game and your quest log find their quests.
DQ.AREA = {
	["Ragefire Chasm"] = 2437, ["The Deadmines"] = 1581, ["Wailing Caverns"] = 718,
	["Shadowfang Keep"] = 209, ["Blackfathom Deeps"] = 719, ["The Stockade"] = 717,
	["Razorfen Kraul"] = 491, ["Gnomeregan"] = 721, ["Scarlet Monastery"] = 796,
	["Razorfen Downs"] = 722, ["Uldaman"] = 1337, ["Zul'Farrak"] = 1176, ["Maraudon"] = 2100,
	["Temple of Atal'Hakkar"] = 1417, ["Blackrock Depths"] = 1584,
}
-- Other names the game uses for the same dungeon.
local ALIAS = { ["the sunken temple"] = "Temple of Atal'Hakkar", ["sunken temple"] = "Temple of Atal'Hakkar",
	["stormwind stockade"] = "The Stockade", ["the stormwind stockade"] = "The Stockade" }

local LEAD = 2             -- levels before a dungeon's window when its quests start being gathered
local PRE_DEPTH = 8        -- how far back a chain is followed to find what opens a quest
local TAG_DUNGEON = 81     -- the game's quest tag for a dungeon quest
local ASK_PER_TICK = 6
local TICK = 2
local PLAN_TTL = 3

function DQ:On() return ns.db.guide.dungeonQuests ~= false end

function DQ:Wanted(name)
	local skip = ns.db.guide.dungeonSkip
	return not (type(skip) == "table" and skip[name])
end

local function Changed()
	DQ:Forget()
	if ns.Planner then ns.Planner.dirty = true end
	if ns.Guide then ns.Guide:Refresh() end
	ns:SendMessage("DUNGEONS_UPDATED")
end

function DQ:SetWanted(name, on)
	if type(ns.db.guide.dungeonSkip) ~= "table" then ns.db.guide.dungeonSkip = {} end
	ns.db.guide.dungeonSkip[name] = (not on) or nil
	Changed()
end

function DQ:SetOn(on)
	ns.db.guide.dungeonQuests = on and true or false
	Changed()
end

---------------------------------------------------------------------------
-- Names
---------------------------------------------------------------------------
local function Norm(s)
	if type(s) ~= "string" or ns.IsSecret(s) then return nil end
	s = s:lower()
	return ALIAS[s] and ALIAS[s]:lower() or s
end

local byName
-- The dungeon entry (from the 1-60 plan's list) a name refers to, or nil. Ignores "The".
function DQ:ByName(name)
	local n = Norm(name)
	if not n then return nil end
	if not byName then
		byName = {}
		for _, d in ipairs(ns.Profiles.DUNGEONS) do
			local key = d[1]:lower()
			byName[key] = d[1]
			byName[(key:gsub("^the ", ""))] = d[1]
		end
	end
	return byName[n] or byName[(n:gsub("^the ", ""))]
end

-- The dungeons for this character's side, in level order: { name, from, to }.
function DQ:List()
	local plan = ns.Profiles and ns.Profiles:Mine()
	return plan and plan.dungeons or {}
end

function DQ:Info(name)
	for _, d in ipairs(self:List()) do if d.name == name then return d end end
end

---------------------------------------------------------------------------
-- Which quests belong to which dungeon
---------------------------------------------------------------------------
local index            -- [dungeon] = { [questID] = true }
local ofQuest          -- [questID] = dungeon
local areaName = {}    -- [area] = dungeon or false

local function AreaDungeon(area)
	local known = areaName[area]
	if known ~= nil then return known or nil end
	known = false
	for name, id in pairs(DQ.AREA) do
		if id == area then known = name break end
	end
	-- QuestieDB's own dungeon list: the other numbers a dungeon's quests are filed under (most
	-- of Gnomeregan's and Uldaman's), and the dungeons that are new in WoW Forever.
	if not known and ns.Library then
		known = DQ:ByName(ns.Library:DungeonName(area)) or false
	end
	-- And an area neither has a number for: the game names it.
	if not known and C_Map and C_Map.GetAreaInfo then
		known = DQ:ByName(ns.SafeCall(C_Map.GetAreaInfo, area)) or false
	end
	areaName[area] = known
	return known or nil
end

local function Add(name, qid)
	if not (name and qid) then return end
	index[name] = index[name] or {}
	index[name][qid] = true
	ofQuest[qid] = name
end

function DQ:Forget() index, ofQuest, areaName = nil, nil, {} self.plan = nil end

function DQ:Index()
	if index then return index end
	index, ofQuest = {}, {}
	for qid, e in pairs(ns.Library and ns.Library:Layer() or {}) do
		if e.zs then Add(AreaDungeon(e.zs), qid) end
	end
	for qid, name in pairs(ns.db.dungeonLearned or {}) do
		local d = self:ByName(name)
		if d then Add(d, qid) end
	end
	return index
end

-- The dungeon a quest is done in, or nil.
function DQ:QuestDungeon(qid)
	self:Index()
	return qid and ofQuest[qid] or nil
end

function DQ:QuestsFor(name)
	return self:Index()[name] or {}
end

function DQ:Learn(qid, name, why)
	local d = self:ByName(name)
	if not (qid and d) then return false end
	if ns.db.dungeonLearned[qid] == d then return false end
	ns.db.dungeonLearned[qid] = d
	if index then Add(d, qid) end
	self.plan = nil
	ns.Debug(string.format("dungeons: quest %d belongs to %s (%s)", qid, d, why or "?"))
	return true
end

-- Your quest log lists dungeon quests under the dungeon's name.
function DQ:LearnFromLog()
	local any = false
	for _, e in ipairs(ns.Quests.log or {}) do
		if e.zone and self:ByName(e.zone) and self:Learn(e.questID, e.zone, "quest log") then any = true end
	end
	if any then Changed() end
end

-- The game, for quests QuestieDB doesn't place: is it tagged Dungeon, and which map is it on?
-- Asked a few at a time for the quests near the dungeons you're heading for.
local asked = {}
function DQ:Ask(qid)
	local checked = ns.db.dungeonChecked
	if checked[qid] or ns.db.dungeonLearned[qid] then return nil end
	if not (C_QuestLog and C_QuestLog.GetQuestTagInfo) then checked[qid] = true return false end
	local info = ns.SafeCall(C_QuestLog.GetQuestTagInfo, qid)
	if type(info) ~= "table" then
		if not asked[qid] then
			asked[qid] = 1
			if C_QuestLog.RequestLoadQuestByID then pcall(C_QuestLog.RequestLoadQuestByID, qid) end
			return nil
		end
		asked[qid] = asked[qid] + 1
		-- The game has had a few goes and has nothing to say: an ordinary quest.
		if asked[qid] >= 4 then checked[qid] = true end
		return nil
	end
	checked[qid] = true
	if ns.Num(info.tagID) ~= TAG_DUNGEON then return false end
	local map = GetQuestUiMapID and ns.Num(ns.SafeCall(GetQuestUiMapID, qid))
	local name = map and map > 0 and ns.Nav.MapName(map)
	if name and self:Learn(qid, name, "quest tag") then return true end
	return false
end

local pendingAsk = {}
function DQ:QueueAsks()
	wipe(pendingAsk)
	if not self:On() then return end
	local level = UnitLevel("player") or 1
	local lo, hi
	for _, d in ipairs(self:List()) do
		if self:Wanted(d.name) and level >= d.from - LEAD - 2 and level <= d.to then
			lo, hi = math.min(lo or d.from, d.from - 3), math.max(hi or d.to, d.to + 2)
		end
	end
	if not lo then return end
	local checked, learned = ns.db.dungeonChecked, ns.db.dungeonLearned
	self:Index()
	for qid, q in ns.QuestDB:Each() do
		local l = q.l or q.rl
		if l and l >= lo and l <= hi and not checked[qid] and not learned[qid] and not ofQuest[qid] then
			pendingAsk[#pendingAsk + 1] = qid
		end
	end
end

function DQ:Tick()
	if not self:On() or #pendingAsk == 0 or InCombatLockdown() then return end
	local any = false
	for _ = 1, ASK_PER_TICK do
		local qid = table.remove(pendingAsk, 1)
		if not qid then break end
		local got = self:Ask(qid)
		if got == nil and not ns.db.dungeonChecked[qid] then pendingAsk[#pendingAsk + 1] = qid end
		if got then any = true end
	end
	if any then Changed() end
end

---------------------------------------------------------------------------
-- What to do about the dungeons ahead
---------------------------------------------------------------------------
local function Done(id) return ns.SafeCall(C_QuestLog.IsQuestFlaggedCompleted, id) == true end
local function OnQuest(id) return ns.SafeCall(C_QuestLog.IsOnQuest, id) == true end

-- What has to be done before a quest: its own list, and the quest before it in its chain.
local function Pres(qid, q)
	local out, seen = {}, {}
	for _, p in ipairs(q and q.pre or {}) do
		if not seen[p] then seen[p] = true out[#out + 1] = p end
	end
	-- Any one of these will do. With one done already, none of the others matters.
	local one = false
	for _, p in ipairs(q and q.any or {}) do if Done(p) then one = true end end
	if not one then
		for _, p in ipairs(q and q.any or {}) do
			if not seen[p] then seen[p] = true out[#out + 1] = p end
		end
	end
	local prev = ns.QuestDB:PrevQuest(qid)
	if prev and not seen[prev] then out[#out + 1] = prev end
	return out
end

-- The first quest you can pick up that leads to this one: the quest itself when it is open,
-- else the earliest open quest back along its chain. Second answer: a quest on the way that is
-- already in your log (nothing to pick up, just finish it).
local function FirstOpen(qid, depth, seen)
	local D = ns.QuestDB
	local q = D:Get(qid)
	for _, pre in ipairs(Pres(qid, q)) do
		if not seen[pre] then
			seen[pre] = true
			if not Done(pre) then
				if OnQuest(pre) then return nil, pre end
				local st = D:Status(pre)
				if st == "available" then
					local pq = D:Get(pre)
					if pq and pq.m and pq.x then return pre end
				elseif st == "locked" and depth < PRE_DEPTH then
					local found, inLog = FirstOpen(pre, depth + 1, seen)
					if found or inLog then return found, inLog end
				end
			end
		end
	end
	return nil
end

-- The plan for the dungeons ahead, worked out every few seconds:
--   picks    { qid, forQid, dungeon, pre } quests to pick up, dungeon quests and pre-quests
--   wait     [qid] = dungeon   dungeon quests in your log, done in the dungeon
--   prep     [qid] = { dungeon, forQid }   quests in your log that open a dungeon quest
--   rows     { name, from, to, inLog, open, pre, later, done, total } per dungeon
function DQ:Plan()
	local now = GetTime()
	if self.plan and now - self.planAt < PLAN_TTL then return self.plan end
	local plan = { picks = {}, wait = {}, prep = {}, rows = {}, byQuest = {} }
	self.plan, self.planAt = plan, now
	if not self:On() or not ns.QuestDB then return plan end
	local D = ns.QuestDB
	local level = UnitLevel("player") or 1
	local taken = {}
	for _, d in ipairs(self:List()) do
		local quests = self:QuestsFor(d.name)
		local row = { name = d.name, from = d.from, to = d.to, inLog = 0, open = 0, pre = 0, later = 0, done = 0, total = 0 }
		local active = self:Wanted(d.name) and level >= d.from - LEAD and level <= d.to
		for qid in pairs(quests) do
			local q = D:Get(qid)
			local st = D:Status(qid, q)
			if st ~= "faction" and st ~= "other" and st ~= "repeat" then
				row.total = row.total + 1
				if st == "done" then
					row.done = row.done + 1
				elseif st == "log" then
					row.inLog = row.inLog + 1
					if active then plan.wait[qid] = d.name end
				elseif st == "later" then
					row.later = row.later + 1
				elseif active then
					local target, inLog
					if st == "available" and q and q.m and q.x then
						target = qid
					else
						target, inLog = FirstOpen(qid, 1, { [qid] = true })
					end
					if target and not taken[target] then
						taken[target] = true
						local pick = { qid = target, forQid = qid, dungeon = d.name, pre = target ~= qid }
						plan.picks[#plan.picks + 1] = pick
						plan.byQuest[target] = pick
						if target == qid then row.open = row.open + 1 else row.pre = row.pre + 1 end
					elseif inLog and not plan.prep[inLog] then
						plan.prep[inLog] = { dungeon = d.name, forQid = qid }
					end
				end
			end
		end
		row.active = active
		plan.rows[#plan.rows + 1] = row
	end
	return plan
end

-- What the guide says about a quest: a pickup for a dungeon, a quest that opens one, or a
-- dungeon quest waiting for its dungeon. Nil when it is none of those.
function DQ:Note(qid)
	if not (qid and self:On()) then return nil end
	local plan = self:Plan()
	local pick = plan.byQuest[qid]
	if pick then
		return pick.pre and string.format("pre-quest for %s (%s)", self:Title(pick.forQid), pick.dungeon)
			or ("dungeon quest: " .. pick.dungeon)
	end
	local prep = plan.prep[qid]
	if prep then return string.format("opens %s (%s)", self:Title(prep.forQid), prep.dungeon) end
	local d = plan.wait[qid] or self:QuestDungeon(qid)
	if d then return "done in " .. d end
	return nil
end

-- Are you inside this dungeon right now?
function DQ:Inside(name)
	if not (IsInInstance and IsInInstance()) then return false end
	local here = GetInstanceInfo and GetInstanceInfo()
	return self:ByName(here) == name
end

function DQ:Title(qid)
	local q = ns.QuestDB and ns.QuestDB:Get(qid)
	return (q and q.t) or ns.SafeCall(C_QuestLog.GetTitleForQuestID, qid) or ("Quest " .. qid)
end

---------------------------------------------------------------------------
-- Choosing dungeons
---------------------------------------------------------------------------
function DQ:OpenPicker()
	local U = ns.UI
	local f = self.picker
	if not f then
		f = CreateFrame("Frame", "NeverQuestDungeonPicker", UIParent, "BackdropTemplate")
		f:SetSize(560, 120)
		f:SetPoint("CENTER", 0, 40)
		f:SetFrameStrata("DIALOG")
		f:SetToplevel(true)
		ns.ApplyBackdrop(f, 0.97)
		f:SetMovable(true)
		f:EnableMouse(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)
		table.insert(UISpecialFrames, "NeverQuestDungeonPicker")
		f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		f.title:SetPoint("TOPLEFT", 18, -14)
		f.title:SetText("Dungeons to get quests for")
		f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
		f.text:SetWidth(520)
		f.text:SetJustifyH("LEFT")
		f.text:SetText("Ticked dungeons get their quests and pre-quests picked up a couple of levels before you're ready for them.")
		local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -2, -2)
		local p = CreateFrame("Frame", nil, f)
		p:SetPoint("TOPLEFT", 18, -64)
		p:SetPoint("BOTTOMRIGHT", -18, 44)
		local rows = DQ:BuildChecks(p, U, 0)
		f:SetHeight(64 + rows * 24 + 54)
		local all = U.Button(f, "Tick all", 90, function() for _, d in ipairs(DQ:List()) do DQ:SetWanted(d.name, true) end DQ:RefreshChecks() end)
		all:SetPoint("BOTTOMLEFT", 16, 12)
		local none = U.Button(f, "Untick all", 90, function() for _, d in ipairs(DQ:List()) do DQ:SetWanted(d.name, false) end DQ:RefreshChecks() end)
		none:SetPoint("LEFT", all, "RIGHT", 8, 0)
		local done = U.Button(f, "Done", 90, function() f:Hide() end)
		done:SetPoint("BOTTOMRIGHT", -16, 12)
		self.picker = f
	end
	self:RefreshChecks()
	f:Show()
	return f
end

-- Two columns of ticks, one per dungeon for your side. Returns how many rows it took.
DQ.checks = {}
function DQ:BuildChecks(parent, U, top, rowHeight)
	rowHeight = rowHeight or 24
	local list = self:List()
	local rows = math.ceil(#list / 2)
	for i, d in ipairs(list) do
		local col, r = (i - 1) % 2, math.floor((i - 1) / 2)
		local cb = U.Check(parent, col * 262, top - r * rowHeight, string.format("%s  |cff999999%d-%d|r", d.name, d.from, d.to),
			function() return DQ:Wanted(d.name) end,
			function(v) DQ:SetWanted(d.name, v) end)
		cb.dungeon = d.name
		self.checks[#self.checks + 1] = cb
	end
	return rows
end

function DQ:RefreshChecks()
	for _, cb in ipairs(self.checks) do
		if cb.SetChecked and cb.dungeon then cb:SetChecked(self:Wanted(cb.dungeon)) end
	end
end

---------------------------------------------------------------------------
-- /nq dungeons
---------------------------------------------------------------------------
function DQ:StatusLines()
	local lines = {}
	lines[#lines + 1] = self:On()
		and "dungeon quests: on. Ticked dungeons get their quests and pre-quests picked up a couple of levels early. /nq dungeons off turns it off, /nq dungeons pick chooses dungeons."
		or "dungeon quests: off. /nq dungeons on gathers the quests (and pre-quests) for the dungeons you tick."
	for _, row in ipairs(self:Plan().rows) do
		local parts = {}
		if row.open > 0 then parts[#parts + 1] = row.open .. " to pick up" end
		if row.pre > 0 then parts[#parts + 1] = row.pre .. " behind a pre-quest" end
		if row.inLog > 0 then parts[#parts + 1] = row.inLog .. " in your log" end
		if row.done > 0 then parts[#parts + 1] = row.done .. " done" end
		local mark = self:Wanted(row.name) and "|cff33ff33[x]|r" or "|cff888888[ ]|r"
		lines[#lines + 1] = string.format("  %s %s %d-%d: %d quest%s known%s", mark, row.name, row.from, row.to,
			row.total, row.total == 1 and "" or "s", #parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or "")
	end
	return lines
end

ns:AddSlash("dungeons", function(rest)
	rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local low = rest:lower()
	if low == "on" or low == "off" then
		DQ:SetOn(low == "on")
	elseif low == "pick" or low == "choose" then
		DQ:OpenPicker()
		return
	elseif rest ~= "" then
		local name = DQ:ByName(rest)
		if not name then ns.Print("no dungeon called " .. rest .. ". /nq dungeons lists them.") return end
		DQ:SetWanted(name, not DQ:Wanted(name))
		ns.Print(name .. (DQ:Wanted(name) and ": quests will be gathered." or ": left out."))
		return
	end
	for _, line in ipairs(DQ:StatusLines()) do ns.Print(line) end
end, "/nq dungeons [on | off | pick | <dungeon>] - get dungeon quests and their pre-quests first, and choose which dungeons")

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns:RegisterMessage("QUESTS_UPDATED", function()
	ns.Debounce("dungeons:log", 2, function() DQ:LearnFromLog() DQ.plan = nil end)
end)
ns:RegisterMessage("QUESTDB_UPDATED", function() DQ:Forget() ns.Debounce("dungeons:asks", 5, function() DQ:QueueAsks() end) end)
for _, event in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED" }) do
	ns:RegisterEvent(event, function() DQ.plan = nil end)
end
ns:RegisterEvent("PLAYER_LEVEL_UP", function()
	DQ.plan = nil
	ns.After(5, function() DQ:QueueAsks() end)
end)
ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
	if DQ.ticker then return end
	DQ.ticker = ns.Ticker(TICK, "dungeons", function() DQ:Tick() end)
	ns.After(12, function() DQ:QueueAsks() end)
end)
