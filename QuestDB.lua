-- NeverQuest quest database: every quest the game has shown you, account-wide, over the quest
-- start data NeverQuest ships.
--
-- Built only from the game client itself, nothing copied from other addons or sites:
--   * a slow background scan asks the game which quests each zone offers (one zone every
--     couple of seconds, paused in combat), once at login and again after you level;
--   * quest givers you see on the world map or nearby are added as you play;
--   * quests you accept add their level, giver spot and NPC name;
--   * party members running NeverQuest pass on the starts they know;
--   * Data/Starts.lua, gathered the same way by other players and built into the addon.
-- Every character adds to it, so an alt sees where quests are that it hasn't been offered yet.
-- What your own client learns always beats what NeverQuest ships, field by field.
-- /nq db <name> searches it, /nq db lists the quests in your zone, /nq db export hands your
-- own data to a friend or back to us, and the world map shows known quests that aren't on
-- offer to you right now (faded, with the level they open at).

local ADDON, ns = ...
local D = { queue = {}, scanning = false, loads = {}, queued = {} }
ns.QuestDB = D

local SCAN_GAP = 2            -- seconds between zones
local SCAN_WAIT = 1.5         -- seconds to let the game answer before reading a zone
local RESCAN_AFTER = 6 * 3600 -- full rescan per character after this long (or a new level)

local function Store() return ns.db.questDB end
local EMPTY = {}
local function Base() return (ns.Starts and type(ns.Starts.q) == "table") and ns.Starts.q or EMPTY end
local function Faction()
	local f = UnitFactionGroup("player")
	return f == "Horde" and "H" or (f == "Alliance" and "A") or "N"
end
local function Class() return select(2, UnitClass("player")) or "?" end
local function R3(v) return math.floor(v * 1000 + 0.5) / 1000 end
local function Text(v) return type(v) == "string" and not ns.IsSecret(v) and v ~= "" and v or nil end
local function CharKey() return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "") end

---------------------------------------------------------------------------
-- Adding
---------------------------------------------------------------------------
-- origin: "them" when another player passed this on, otherwise your own client saw it.
--
-- First-hand beats hearsay, always. Your client either stood at the giver or was offered the
-- quest; a guildmate's report is good evidence but it is still a report, so it fills gaps and
-- corrects other reports, and never overwrites a place you have been. q.o records which this
-- is (2 yours, 1 theirs) and q.n counts how many others have agreed on a shared place.
local AGREE = 0.02      -- map fractions: reports this close are about the same spot

-- Who has told us about a quest in this session. Not saved: it exists to stop one client
-- resending the same record from reading as a second opinion, which is a within-session
-- problem. Names are dropped when you log out.
local voices = {}

function D:NewVoice(qid, from)
	if not from or from == "" then return true end
	local seen = voices[qid]
	if not seen then seen = {} voices[qid] = seen end
	if seen[from] then return false end
	seen[from] = true
	return true
end

function D:ResetVoices(qid, from)
	voices[qid] = from and { [from] = true } or nil
end

---------------------------------------------------------------------------
-- What other players send is checked before any of it is kept.
--
-- Your own client can be taken at its word. A message from a guildmate, a party member or a
-- pasted import cannot: it may come from a broken addon, an old version, or somebody being
-- clever. So a report has to look like a quest (a sane number, a real map, a plausible level),
-- its title is cleaned of anything the game would draw as a colour, a texture or a link, and
-- no one sender can pour an unlimited number of them into your saved data.
---------------------------------------------------------------------------
local MAX_QUEST_ID = 999999     -- far above any quest the game has
local MAX_LEVEL = 100
local MAX_TITLE = 80
local INTAKE_BURST = 300        -- reports one sender may deliver at once
local INTAKE_PER_SEC = 0.5      -- and how fast that allowance comes back
local MAX_HEARSAY = 20000       -- quests known only from other people, in all

local intake, realMap, hearsay = {}, {}, nil

function D:ResetIntake()
	intake, hearsay = {}, nil
end

-- No escape codes (the game reads "|T...|t" as a picture and "|H...|h" as a link), no control
-- characters, and no essays.
local function CleanTitle(title)
	title = Text(title)
	if not title then return nil end
	title = title:gsub("|", ""):gsub("%c", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if #title > MAX_TITLE then title = title:sub(1, MAX_TITLE):gsub("%s+$", "") end
	return title ~= "" and title or nil
end
D.CleanTitle = CleanTitle

local function RealMap(m)
	if type(m) ~= "number" or m <= 0 or m ~= math.floor(m) then return false end
	local known = realMap[m]
	if known == nil then
		known = ns.SafeCall(C_Map.GetMapInfo, m) ~= nil
		realMap[m] = known
	end
	return known
end

local function HearsayCount()
	if not hearsay then
		hearsay = 0
		for _, q in pairs(Store().q) do
			if q.o ~= 2 then hearsay = hearsay + 1 end
		end
	end
	return hearsay
end

-- May this sender add one more report? Imports have no sender: you pasted those yourself.
local function Allowed(from)
	if not from or from == "" then return true end
	local now = GetTime()
	local b = intake[from]
	if not b then
		b = { n = INTAKE_BURST, t = now }
		intake[from] = b
	end
	b.n = math.min(INTAKE_BURST, b.n + (now - b.t) * INTAKE_PER_SEC)
	b.t = now
	if b.n < 1 then return false end
	b.n = b.n - 1
	return true
end

function D:Add(qid, title, level, m, x, y, origin, from)
	qid = ns.Num(qid)
	if not qid or qid <= 0 then return nil end
	local theirs = origin == "them"
	level = ns.Num(level)
	x, y = ns.Num(x), ns.Num(y)
	local s = Store()
	local q = s.q[qid]
	if theirs then
		if qid > MAX_QUEST_ID or qid ~= math.floor(qid) then return nil end
		title = CleanTitle(title)
		if level and (level < 1 or level > MAX_LEVEL or level ~= math.floor(level)) then level = nil end
		if m and not RealMap(m) then return nil end
		if not Allowed(from) then return nil end
		if not q and HearsayCount() >= MAX_HEARSAY then return nil end
	end
	local changed = false
	if not q then
		q = {}
		s.q[qid] = q
		changed = true
		if theirs and hearsay then hearsay = hearsay + 1 end
	end
	local was = q.o
	if Text(title) and not (theirs and q.t) and q.t ~= Text(title) then q.t, changed = Text(title), true end
	if level and level > 0 and not (theirs and q.l) and q.l ~= level then q.l, changed = level, true end
	if m and x and y and not (x == 0 and y == 0) and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
		x, y = R3(x), R3(y)
		if not theirs then
			-- Yours: takes the slot whatever was there before.
			if q.m ~= m or q.x ~= x or q.y ~= y or q.o ~= 2 then changed = true end
			q.m, q.x, q.y, q.o, q.n = m, x, y, 2, nil
		elseif not q.m then
			q.m, q.x, q.y, q.o, q.n = m, x, y, 1, 1
			changed = true
			self:ResetVoices(qid, from)
		elseif q.o ~= 2 then
			-- Theirs against theirs: agreement counts, disagreement defers to the better backed.
			-- Only a sender we haven't already heard from about this quest counts, or one person
			-- repeating themselves would look exactly like a second person agreeing.
			if q.m == m and math.abs(q.x - x) <= AGREE and math.abs(q.y - y) <= AGREE then
				if self:NewVoice(qid, from) then q.n = (q.n or 1) + 1 end
			elseif (q.n or 1) <= 1 then
				q.m, q.x, q.y, q.n = m, x, y, 1
				changed = true
				self:ResetVoices(qid, from)
			end
		end
	end
	-- Something you had only heard about and have now seen for yourself is no longer hearsay.
	if hearsay and was and was ~= 2 and q.o == 2 and hearsay > 0 then hearsay = hearsay - 1 end
	-- Faction and class record which of YOUR characters has seen this quest, so they are only
	-- ever stamped first-hand. Stamping them from a report would claim your class was offered a
	-- quest it has never seen, and would mark another faction's quest as yours.
	if not theirs then
		local f = Faction()
		if not q.f then q.f = f elseif not q.f:find(f, 1, true) then q.f = q.f .. f end
		local c = Class()
		if not q.c then q.c = "," .. c .. "," elseif not q.c:find("," .. c .. ",", 1, true) then q.c = q.c .. c .. "," end
	end
	q.s = time()
	-- The game repeats the same offers many times a minute. Only something actually new is a
	-- reason to work out the minimap's points again.
	if changed then D:ClearNearby() end
	return q
end

---------------------------------------------------------------------------
-- Your learned data laid over the data NeverQuest ships.
--
-- Yours wins field by field, because your client is the live one: a title, level or position
-- you have seen replaces the shipped one, and a shipped field fills a gap you don't have yet.
-- Read through Get and Each rather than a cached copy, so a write anywhere (a profile reset,
-- saved variables loading, a test) can never leave a stale view behind.
---------------------------------------------------------------------------
function D:Get(qid)
	local mine, base = Store().q[qid], Base()[qid]
	if not base then return mine end
	if not mine then return base end
	local m = { t = mine.t or base.t, l = mine.l or base.l, f = mine.f or base.f,
		c = mine.c or base.c, z = mine.z or base.z, s = mine.s }
	if mine.m and mine.x then
		m.m, m.x, m.y = mine.m, mine.x, mine.y
	else
		m.m, m.x, m.y = base.m, base.x, base.y
	end
	return m
end

-- Every known quest, yours first and then the shipped ones you have no entry for. Nothing is
-- copied unless a shipped entry actually has something to add, so map draws allocate little.
function D:Each()
	local store, base = Store().q, Base()
	local qid, q, mine = nil, nil, true
	return function()
		if mine then
			qid, q = next(store, qid)
			if qid then
				local b = base[qid]
				if b and (not q.t or not q.l or not q.m or not q.x or not q.f) then return qid, D:Get(qid) end
				return qid, q
			end
			mine, qid = false, nil
		end
		repeat
			qid, q = next(base, qid)
		until qid == nil or store[qid] == nil
		return qid, q
	end
end

-- A plain table of everything, for callers that want one. Built fresh, never cached.
function D:All()
	local out = {}
	for qid, q in self:Each() do out[qid] = q end
	return out
end

-- Where this quest's position came from, for the pin tooltip: "learned" when your own
-- client saw it, "shipped" when it came with the addon, nil when there is no position.
function D:Source(qid)
	local mine = Store().q[qid]
	if mine and mine.m and mine.x then return "learned" end
	local base = Base()[qid]
	if base and base.m and base.x then return "shipped" end
	return nil
end

function D:ShippedCount()
	local n = 0
	for _ in pairs(Base()) do n = n + 1 end
	return n
end

-- A zone's quest givers as the game lists them (Quests.lua CollectOffers calls this).
-- full: the game has answered for this zone, so what's missing isn't on offer to you.
function D:Record(m, list, full)
	if not ns.ready or not m or not list then return end
	for _, o in ipairs(list) do self:Add(o.questID, o.title, o.level, o.m or m, o.x, o.y) end
	-- One quest you can see opens up its whole chain, including the parts you can't take yet.
	for _, o in ipairs(list) do self:QueueChain(o.questID, o.m or m) end
	if full or #list > 0 then
		local s = Store()
		s.scan[m] = s.scan[m] or {}
		local c, lvl = Class(), UnitLevel("player")
		if (s.scan[m][c] or 0) < lvl then s.scan[m][c] = lvl end
	end
end

-- From your quest log: level, and the giver spot once you've met the NPC.
function D:RecordLog()
	local npcs = ns.db.npcs
	for _, e in ipairs(ns.Quests.log) do
		local at = npcs.giverAt[e.questID]
		local before = Store().q[e.questID]
		local hadSpot = before and before.m and before.x
		local q = self:Add(e.questID, e.title, e.level, at and at.m, at and at.x, at and at.y)
		if q and e.zone and Text(e.zone) then q.z = e.zone end
		-- A giver you stood in front of yourself: worth passing to the party.
		if q and not hadSpot and q.m and q.x then self:Share(e.questID, q) end
		-- And the rest of the chain you're now in, so you can see what's coming.
		self:QueueChain(e.questID, at and at.m)
	end
end

---------------------------------------------------------------------------
-- Background scan
---------------------------------------------------------------------------
local function Collect(m)
	local out, seen = {}, {}
	local function Add(info)
		if not info or not info.questID or seen[info.questID] then return end
		seen[info.questID] = true
		local level = ns.Num(ns.SafeCall(C_QuestLog.GetQuestDifficultyLevel, info.questID))
		table.insert(out, { questID = info.questID, title = info.questName, level = level, m = m, x = info.x, y = info.y })
	end
	for _, info in ipairs(ns.SafeCall(C_QuestLine.GetAvailableQuestLines, m) or {}) do Add(info) end
	for _, qid in ipairs(ns.SafeCall(C_QuestLine.GetForceVisibleQuests, m) or {}) do
		Add(ns.SafeCall(C_QuestLine.GetQuestLineInfo, qid, m))
	end
	return out
end
D.Collect = Collect

function D:ScanDue()
	local me = Store().chars[CharKey()]
	if not me then return true end
	return me.level ~= UnitLevel("player") or time() - (me.t or 0) > RESCAN_AFTER
end

function D:StartScan(force)
	if self.scanning or not ns.db.questdb.scan then return false end
	if not force and not self:ScanDue() then return false end
	if not (C_QuestLine and C_QuestLine.RequestQuestLinesForMap) then return false end
	wipe(self.queue)
	local here = ns.Quests.offerMap
	for _, id in ipairs(ns.Nav.GetZoneList()) do
		if id ~= here then table.insert(self.queue, id) end
	end
	self.total = #self.queue
	self.found = 0
	self.scanning = true
	self:Step()
	return true
end

function D:Step()
	if not self.scanning then return end
	-- Wait out combat, death, dungeons and battlegrounds.
	if InCombatLockdown() or UnitIsDeadOrGhost("player") or (IsInInstance and IsInInstance()) then
		ns.After(5, function() D:Step() end)
		return
	end
	local m = table.remove(self.queue, 1)
	if not m then
		self.scanning = false
		Store().chars[CharKey()] = { t = time(), level = UnitLevel("player") }
		-- Ask about your own zone again so its quest list is fresh after all that.
		ns.Debounce("offers", 1, function() ns.Quests:RequestOffers() end)
		ns:SendMessage("QUESTDB_UPDATED")
		-- Always say so, not just for a manual scan: knowing the scan has finished is how you
		-- know the map is as complete as it's going to get, and when it's safe to export.
		local manual = self.manual
		self.manual = nil
		if manual or not ns.db.quietLogin then
			ns.Print(string.format("quest database scan done: %d zones, %d quests known.%s",
				self.total or 0, self:Count(),
				#self.loads > 0 and string.format(" Asking the game about %d more from your chains.", #self.loads) or ""))
		end
		return
	end
	if ns.Quests.NoteForeignRequest then ns.Quests:NoteForeignRequest() end
	pcall(C_QuestLine.RequestQuestLinesForMap, m)
	ns.After(SCAN_WAIT, function()
		local list = Collect(m)
		D:Record(m, list, true)
		D.found = (D.found or 0) + #list
		ns.After(SCAN_GAP - SCAN_WAIT, function() D:Step() end)
	end)
end

function D:StopScan()
	self.scanning = false
	wipe(self.queue)
	wipe(self.loads)
	wipe(self.queued)
end

---------------------------------------------------------------------------
-- Deep scan: the quests the game won't offer this character
--
-- The zone scan can only see what you could accept right now, which is why a level 5
-- character's database stays nearly empty however many zones it has looked at. A quest line
-- knows its whole chain, though, so one quest you can see opens up the rest: the game will
-- load a quest's title and level on request even for a quest you can't take yet.
--
-- This is how the big quest databases came to hold every quest rather than your own, except
-- that nothing here is copied from them: it's the game answering questions an addon is meant
-- to ask. Asks are spread out so the server isn't hammered, and paused in combat and while
-- dead, like the zone scan.
---------------------------------------------------------------------------
local LOAD_BATCH = 5       -- quests asked about together, so one wait covers several
local LOAD_GAP = 0.25      -- seconds between batches
local LOAD_READ = 0.6      -- time to let the game answer before reading a batch
local LOAD_CAP = 600       -- most quests waiting to be asked about at once

-- Everything in this quest's chain that we know nothing useful about yet.
function D:QueueChain(questID, m)
	if not ns.db.questdb.deep or not ns.Chains or not C_QuestLog.RequestLoadQuestByID then return 0 end
	local line = ns.Chains:Line(questID)
	if not line or type(line.quests) ~= "table" then return 0 end
	local added = 0
	for _, qid in ipairs(line.quests) do
		qid = ns.Num(qid)
		if qid and qid > 0 and not self.queued[qid] and #self.loads < LOAD_CAP then
			local known = self:Get(qid)
			-- A title and a level is all we want from this; places come from the zone scan.
			if not (known and known.t and known.l) then
				self.queued[qid] = true
				self.loads[#self.loads + 1] = { qid = qid, m = m }
				added = added + 1
			end
		end
	end
	if added > 0 then self:PumpLoads() end
	return added
end

-- Reads one quest the game has just loaded. Returns true when something was learned.
function D:ReadLoaded(job)
	local title = ns.SafeCall(C_QuestLog.GetTitleForQuestID, job.qid)
	if type(title) ~= "string" or title == "" or ns.IsSecret(title) then return false end
	local level = ns.Num(ns.SafeCall(C_QuestLog.GetQuestDifficultyLevel, job.qid))
	-- A place too, if the line happens to know one for it on that map.
	local x, y
	if job.m then
		local info = ns.SafeCall(C_QuestLine.GetQuestLineInfo, job.qid, job.m)
		if type(info) == "table" then x, y = ns.Num(info.x), ns.Num(info.y) end
	end
	if x and y and (x <= 0 or x > 1 or y <= 0 or y > 1) then x, y = nil, nil end
	self:Add(job.qid, title, (level and level > 0) and level or nil, (x and job.m) or nil, x, y)
	return true
end

function D:PumpLoads()
	if self.loading or #self.loads == 0 then return end
	self.loading = true
	self.deepFound, self.deepTotal = 0, #self.loads
	local function step()
		if #self.loads == 0 then
			self.loading = false
			ns:SendMessage("QUESTDB_UPDATED")
			ns:SendMessage("MAP_OFFERS_UPDATED")
			-- Say so: this is the part that tells you the database is ready to export.
			if (self.deepFound or 0) > 0 then
				ns.Print(string.format("learned %d more quest%s from your chains. %d quests known in all.",
					self.deepFound, self.deepFound == 1 and "" or "s", self:Count()))
			end
			return
		end
		if InCombatLockdown() or UnitIsDeadOrGhost("player") then
			ns.After(5, step)
			return
		end
		-- Ask about a handful at once, then read them all after one wait.
		local batch = {}
		for _ = 1, LOAD_BATCH do
			local job = table.remove(self.loads, 1)
			if not job then break end
			batch[#batch + 1] = job
			pcall(C_QuestLog.RequestLoadQuestByID, job.qid)
		end
		ns.After(LOAD_READ, function()
			for _, job in ipairs(batch) do
				if D:ReadLoaded(job) then D.deepFound = (D.deepFound or 0) + 1 end
			end
			ns.After(LOAD_GAP, step)
		end)
	end
	step()
end

---------------------------------------------------------------------------
-- Looking things up
---------------------------------------------------------------------------
function D:Count()
	local n = 0
	for _ in self:Each() do n = n + 1 end
	return n
end

-- "done", "log", "available" (the game offers it now), "later" (level), "other" (seen by your
-- other characters only), or "unknown".
function D:Status(qid, q)
	q = q or self:Get(qid)
	if ns.SafeCall(C_QuestLog.IsQuestFlaggedCompleted, qid) == true then return "done" end
	if ns.SafeCall(C_QuestLog.IsOnQuest, qid) == true then return "log" end
	if not q then return "unknown" end
	if q.l and q.l > UnitLevel("player") then return "later" end
	if q.f and not q.f:find(Faction(), 1, true) then return "faction" end
	if q.c and not q.c:find("," .. Class() .. ",", 1, true) then return "other" end
	return "available"
end

local STATUS_TEXT = {
	done = "|cff808080done|r", log = "|cff66ccffin your log|r", available = "|cff33ff33available|r",
	later = "|cffff9933later|r", other = "|cffccccccseen by your other characters|r", faction = "|cffff6666other faction|r",
	unknown = "",
}

function D:ZoneName(q)
	if q.m then return ns.Nav.MapName(ns.Nav.GetZoneMap(q.m) or q.m) end
	return q.z or "?"
end

function D:Line(qid, q)
	local st = self:Status(qid, q)
	local giver = ns.db.npcs.giver[qid]
	local where = self:ZoneName(q) .. (q.x and string.format(" %.1f, %.1f", q.x * 100, q.y * 100) or "")
	local tail = st == "later" and string.format(" (opens at level %d)", q.l) or ""
	return string.format("|cffffd100%d|r %s%s - %s%s - %s%s", qid, q.l and ("[" .. q.l .. "] ") or "", q.t or ("Quest " .. qid),
		where, giver and (" (" .. giver .. ")") or "", STATUS_TEXT[st] or st, tail)
end

function D:Search(text, limit)
	text = (text or ""):lower()
	local id = tonumber(text)
	local out = {}
	for qid, q in self:Each() do
		if (id and qid == id) or (not id and q.t and q.t:lower():find(text, 1, true)) then
			table.insert(out, { qid = qid, q = q })
		end
	end
	table.sort(out, function(a, b)
		if (a.q.l or 0) ~= (b.q.l or 0) then return (a.q.l or 0) < (b.q.l or 0) end
		return (a.q.t or "") < (b.q.t or "")
	end)
	local total = #out
	while #out > (limit or 8) do table.remove(out) end
	return out, total
end

-- Every known quest whose giver is in that zone (or child maps of it).
function D:InZone(zoneMap)
	local out = {}
	for qid, q in self:Each() do
		if q.m and (q.m == zoneMap or ns.Nav.GetZoneMap(q.m) == zoneMap) then table.insert(out, { qid = qid, q = q }) end
	end
	table.sort(out, function(a, b) return (a.q.l or 0) < (b.q.l or 0) end)
	return out
end

function D:ZoneSummary(zoneMap)
	local counts = { done = 0, log = 0, available = 0, later = 0, other = 0, faction = 0, unknown = 0 }
	local list = self:InZone(zoneMap)
	for _, r in ipairs(list) do
		local st = self:Status(r.qid, r.q)
		counts[st] = (counts[st] or 0) + 1
	end
	return #list, counts, list
end

-- Known quests to show on the world map: ones the game doesn't list for you right now.
function D:MapPoints(mapID, offered)
	local cfg = ns.db.questdb
	if not cfg.worldmap then return {} end
	local out, level, myClass, mine = {}, UnitLevel("player"), Class(), Faction()
	local s = Store()
	-- Only quests whose giver is in the zone on screen (cheap to check for thousands).
	local zoneOf = {}
	local function Zone(m)
		local z = zoneOf[m]
		if z == nil then z = ns.Nav.GetZoneMap(m) or m zoneOf[m] = z end
		return z
	end
	local shown = Zone(mapID)
	for qid, q in self:Each() do
		if q.m and q.t and not offered[qid] and (q.m == mapID or Zone(q.m) == shown) and (not q.f or q.f:find(mine, 1, true)) then
			local lv = q.l
			-- Both ceilings answer to the same two checkboxes the live offers use, so ticking
			-- "include red (too high)" actually reveals what your guild has sent you from ahead.
			local okLevel = not lv
				or ((ns.db.givers.red or lv <= level + (cfg.ahead or 3))
					and (ns.db.givers.gray or lv >= level - (cfg.grayBelow or 6)))
			if okLevel then
				local x, y = ns.Nav.TranslatePoint(q.m, q.x, q.y, mapID)
				if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
					local st = self:Status(qid, q)
					local hidden = st == "done" or st == "log" or st == "faction"
					-- This class has asked the game about this zone at the quest's level and wasn't
					-- offered it: class or race quest, or an earlier quest comes first.
					local scanned = (s.scan[q.m] or {})[myClass]
					if not hidden and st == "other" and scanned and scanned >= (lv or 1) then hidden = true end
					if not hidden then
						local sub
						if st == "later" then
							sub = string.format("Opens at level %d.", lv)
						elseif st == "other" then
							sub = "Seen by your other characters. It may be for another class or race."
						else
							sub = "Not offered to you right now: it may need an earlier quest first."
						end
						local giver = ns.db.npcs.giver[qid]
						if giver then sub = "From " .. giver .. ". " .. sub end
						table.insert(out, { qid = qid, q = q, x = x, y = y, status = st, sub = sub,
							src = self:Source(qid) })
					end
				end
			end
		end
	end
	return out
end

-- Quest starts near you, for the minimap.
--
-- The minimap redraws several times a second, and walking the whole database that often would
-- be wasteful, so the zone's points are worked out once and reused for a few seconds. Anything
-- that changes what belongs on the map (learning something, levelling, a setting) clears it.
local near = { key = nil, at = 0, points = nil }
local NEAR_TTL = 8

function D:ClearNearby()
	near.key, near.points = nil, nil
end

function D:NearbyPoints(yards, cap)
	if not ns.db.questdb.minimap then return {} end
	local m = ns.SafeCall(C_Map.GetBestMapForUnit, "player")
	local zone = m and ns.Nav.GetZoneMap(m)
	if not zone then return {} end
	local key = table.concat({ zone, UnitLevel("player") or 0,
		ns.db.givers.gray and 1 or 0, ns.db.givers.red and 1 or 0 }, ":")
	local now = GetTime()
	if near.key ~= key or not near.points or now - near.at > NEAR_TTL then
		local offered = {}
		for _, o in ipairs(ns.Quests.offers or {}) do
			if o.questID then offered[o.questID] = true end
		end
		near.points, near.key, near.at = self:MapPoints(zone, offered), key, now
	end
	local out = {}
	for _, k in ipairs(near.points) do
		local d = ns.Nav.Distance(k.q.m, k.q.x, k.q.y)
		if d and d <= yards then
			out[#out + 1] = { dist = d, qid = k.qid, q = k.q, m = k.q.m, x = k.q.x, y = k.q.y,
				status = k.status, sub = k.sub, src = k.src }
		end
	end
	table.sort(out, function(a, b) return a.dist < b.dist end)
	for i = #out, (cap or 12) + 1, -1 do out[i] = nil end
	return out
end

---------------------------------------------------------------------------
-- Export / import / party sharing
--
-- One text string with the quest starts this account knows, so you can hand them to a friend
-- or send them back to us to be built into the addon for everybody. It carries quests and
-- places only: no character names, no realm, nothing about you.
--
-- NQQ1~<client build>~<addon version>~record~record...   with records:
--   <questID>^<title>^<level>^<map>^<x>^<y>^<factions>^<firsthand>
--
-- <firsthand> is 1 when your own client saw the place and empty when another player passed it
-- on. Without it a build would count a relayed copy of one report as a second, independent
-- one, and read agreement into data that only ever had a single source.
--
-- The class list is deliberately left out. In your own database it records which of your
-- characters have seen a quest, which says nothing about who can take it, so merging it
-- across people would invent restrictions that aren't real.
---------------------------------------------------------------------------
local SEP, REC = "^", "~"

local function Field(v)
	if v == nil then return "" end
	v = tostring(v)
	if ns.IsSecret(v) then return "" end
	return (v:gsub("[%^~\r\n|]", " "):gsub("%s+$", ""))
end

local function Split(text)
	local f = {}
	for part in (text .. SEP):gmatch("(.-)%" .. SEP) do f[#f + 1] = part end
	return f
end

local function Build()
	return (ns.Starts and ns.Starts.build) or (GetBuildInfo and select(1, GetBuildInfo())) or "?"
end

-- Only quests with a place, since a title on its own helps nobody find anything.
function D:Export()
	local out = { "NQQ1", Field(Build()), Field(ns.version or "?") }
	local n = 0
	for qid, q in self:Each() do
		if q.m and q.x and q.y and q.t then
			out[#out + 1] = string.format("%d%s%s%s%s%s%d%s%.4f%s%.4f%s%s%s%s", qid, SEP, Field(q.t), SEP,
				q.l and tostring(q.l) or "", SEP, q.m, SEP, q.x, SEP, q.y, SEP, Field(q.f),
				SEP, q.o == 2 and "1" or "")
			n = n + 1
		end
	end
	return table.concat(out, REC), n
end

function D:Import(text)
	if type(text) ~= "string" then return nil end
	text = text:gsub("[\r\n\t]", "")
	if text:sub(1, 4) ~= "NQQ1" then
		ns.Print("that isn't NeverQuest quest start data (it starts with NQQ1~).")
		return nil
	end
	local added, updated, skipped, at = 0, 0, 0, 0
	for record in text:gmatch("[^" .. REC .. "]+") do
		at = at + 1
		if at > 3 then                      -- 1 the tag, 2 the client build, 3 the addon version
			local f = Split(record)
			local qid = tonumber(f[1])
			local m, x, y = tonumber(f[4]), tonumber(f[5]), tonumber(f[6])
			local had = qid and Store().q[qid]
			if qid and f[2] ~= "" and m and x and y then
				local q = self:Add(qid, f[2], tonumber(f[3]), m, x, y, "them")
				if q then
					-- Which factions can take it fills a gap and nothing more: what your own
					-- characters have seen is never rewritten by somebody's file.
					if not q.f and f[7] and #f[7] <= 3 and f[7]:match("^[AHN]+$") then q.f = f[7] end
					if had then updated = updated + 1 else added = added + 1 end
				else
					skipped = skipped + 1
				end
			else
				skipped = skipped + 1
			end
		end
	end
	ns.Print(string.format("quest starts imported: %d new, %d updated%s.", added, updated,
		skipped > 0 and (", " .. skipped .. " skipped") or ""))
	ns:SendMessage("MAP_OFFERS_UPDATED")
	ns:SendMessage("QUESTDB_UPDATED")
	return true
end

-- Party sharing: one start at a time, rate limited, only places you learned yourself.
local tokens, lastRefill = 5, 0

local function Record(qid, q)
	return "Q" .. table.concat({ qid, Field(q.t), q.l or "",
		q.m, string.format("%.4f", q.x), string.format("%.4f", q.y) }, SEP)
end

function D:Share(qid, q)
	local cfg = ns.db.questdb
	if not (cfg.share or cfg.guild) or not ns.Party then return end
	if not (q and q.m and q.x and q.t) then return end
	local now = GetTime()
	tokens = math.min(5, tokens + (now - lastRefill) * 0.5)
	lastRefill = now
	if tokens < 1 then return end
	local where = (cfg.share and cfg.guild and "both") or (cfg.guild and "guild") or "party"
	if ns.Party:SendRaw(Record(qid, q), where) then tokens = tokens - 1 end
end

function D:FromParty(sender, body, via)
	local cfg = ns.db.questdb
	if via == "guild" then
		if not cfg.guild then return end
	elseif not cfg.share then
		return
	end
	if type(body) ~= "string" then return end
	local f = Split(body)
	local qid, m, x, y = tonumber(f[1]), tonumber(f[4]), tonumber(f[5]), tonumber(f[6])
	if not qid or f[2] == "" or not m or not x or not y then return end
	if x <= 0 or x > 1 or y <= 0 or y > 1 then return end
	if self:Add(qid, f[2], tonumber(f[3]), m, x, y, "them", sender) then
		self.fromOthers = (self.fromOthers or 0) + 1
		ns.Debounce("questdb:partydraw", 2, function()
			ns:SendMessage("MAP_OFFERS_UPDATED")
		end)
	end
end

---------------------------------------------------------------------------
-- Asking the guild
--
-- A new character knows nothing, and its guildmates between them know most of the world. One
-- request gets a bounded answer from each of a few of them: their best backed starts, spread
-- over a few seconds so nobody's chat is flooded, and nothing is sent twice within the hour.
---------------------------------------------------------------------------
local ASK_COOLDOWN = 600      -- seconds before you may ask again
local ANSWER_COOLDOWN = 300   -- seconds before you answer another request
local ANSWER_CAP = 120        -- most starts one answer carries
local MSG_ROOM = 200          -- characters to fill before starting a new line
-- The game lets an addon send a short burst and then about one message a second, and silently
-- drops the rest. So an answer starts briskly and then settles to a pace the game accepts, and
-- a line the game refuses is sent again rather than lost.
local ANSWER_QUICK = 5        -- lines sent at the quick pace
local ANSWER_GAP = 0.4        -- seconds between those
local ANSWER_STEADY = 1.1     -- seconds between the rest
local ANSWER_RETRY = 2.5      -- wait after a refused line
local ANSWER_TRIES = 6        -- refusals in a row before giving up
local ENOUGH_ANSWERS = 3      -- others already answering: yours would only add traffic
local ASK_WINDOW = 120        -- seconds an ask of yours is still "being answered"

function D:Ask()
	if not ns.db.questdb.guild then return false, "guild sharing is off. /nq db guild turns it on." end
	if not ns.Party or not ns.Party:GuildActive() then return false, "you aren't in a guild." end
	local now = GetTime()
	if self.askedAt and now - self.askedAt < ASK_COOLDOWN then
		return false, string.format("already asked. Try again in %d seconds.", math.ceil(ASK_COOLDOWN - (now - self.askedAt)))
	end
	self.askedAt = now
	self.fromAsk = 0
	ns.Party:SendRaw("R", "guild")
	return true
end

-- Someone asked. Answer with the starts we are most sure of, in a few lines.
function D:OnAsked(sender)
	if not ns.db.questdb.guild or not ns.Party then return end
	local now = GetTime()
	-- Who else answers this request is counted from here (see FromBatch).
	local ask = { at = now, n = 0, who = {} }
	self.heardAsk = ask
	if self.answeredAt and now - self.answeredAt < ANSWER_COOLDOWN then return end
	self.answeredAt = now
	local picks, base = {}, Base()
	for qid, q in self:Each() do
		-- No point sending back the shipped file: they have the same one.
		local b = base[qid]
		local same = b and b.m == q.m and b.x == q.x and b.y == q.y
		if q.m and q.x and q.y and q.t and not same then
			picks[#picks + 1] = { qid = qid, q = q, rank = (q.o == 2 and 100 or (q.n or 1)) }
		end
	end
	if #picks == 0 then return end
	table.sort(picks, function(a, b)
		if a.rank ~= b.rank then return a.rank > b.rank end
		return a.qid < b.qid
	end)
	while #picks > ANSWER_CAP do table.remove(picks) end
	-- Pack into lines, then send them spread out so one answer isn't a wall of traffic.
	local lines, cur = {}, {}
	local len = 0
	for _, p in ipairs(picks) do
		local rec = table.concat({ p.qid, Field(p.q.t), p.q.l or "", p.q.m,
			string.format("%.4f", p.q.x), string.format("%.4f", p.q.y) }, SEP)
		if len + #rec + 1 > MSG_ROOM and #cur > 0 then
			lines[#lines + 1] = table.concat(cur, REC)
			cur, len = {}, 0
		end
		cur[#cur + 1] = rec
		len = len + #rec + 1
	end
	if #cur > 0 then lines[#lines + 1] = table.concat(cur, REC) end
	local i, tries = 1, 0
	local function nextLine()
		if not lines[i] or not ns.db.questdb.guild then return end
		if ns.Party:SendRaw("B" .. lines[i], "guild") then
			i, tries = i + 1, 0
			ns.After(i <= ANSWER_QUICK and ANSWER_GAP or ANSWER_STEADY, nextLine)
		else
			tries = tries + 1
			if tries < ANSWER_TRIES then ns.After(ANSWER_RETRY, nextLine) end
		end
	end
	-- Everybody with the addon hears the same request. Waiting a random moment spreads the
	-- answers out, and whoever finds that a few guildmates got there first says nothing: the
	-- asker already has plenty coming, and you stay free to answer the next one.
	ns.After(1 + math.random() * 4, function()
		if ask.n >= ENOUGH_ANSWERS then
			if D.answeredAt == now then D.answeredAt = nil end
			return
		end
		nextLine()
	end)
end

-- A batch answering a request: the same records, several to a line.
function D:FromBatch(sender, body)
	if not ns.db.questdb.guild or type(body) ~= "string" then return end
	local ask = self.heardAsk
	if ask and sender and not ask.who[sender] and GetTime() - ask.at < 30 then
		ask.who[sender] = true
		ask.n = ask.n + 1
	end
	local got = 0
	for record in body:gmatch("[^" .. REC .. "]+") do
		local f = Split(record)
		local qid, m, x, y = tonumber(f[1]), tonumber(f[4]), tonumber(f[5]), tonumber(f[6])
		if qid and f[2] ~= "" and m and x and y and x > 0 and x <= 1 and y > 0 and y <= 1 then
			if self:Add(qid, f[2], tonumber(f[3]), m, x, y, "them", sender) then got = got + 1 end
		end
	end
	if got > 0 then
		-- Counted apart from the ones that drift in passively, so an answer to /nq db ask
		-- reports what the ask actually brought and not everything since you logged in. An
		-- answer to somebody else's ask is learned from just the same, without a word in chat.
		if self.askedAt and GetTime() - self.askedAt < ASK_WINDOW then
			self.fromAsk = (self.fromAsk or 0) + got
		else
			self.fromOthers = (self.fromOthers or 0) + got
		end
		ns.Debounce("questdb:guilddraw", 3, function()
			ns:SendMessage("MAP_OFFERS_UPDATED")
			ns:SendMessage("QUESTDB_UPDATED")
			if (D.fromAsk or 0) > 0 then
				ns.Print(string.format("%d quest starts from your guild. %d quests known in all.",
					D.fromAsk, D:Count()))
				D.fromAsk = 0
			end
		end)
	end
end

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
local function PrintZone(zoneMap, full)
	local name = ns.Nav.MapName(zoneMap)
	local n, c, list = D:ZoneSummary(zoneMap)
	if n == 0 then
		ns.Print(name .. ": no quests known here yet." .. (D.scanning and " The scan is still running." or ""))
		return
	end
	ns.Print(string.format("%s: %d known quests. %d done, %d in your log, %d available, %d for later levels%s.", name, n,
		c.done, c.log, c.available, c.later, c.other > 0 and string.format(", %d seen by other characters", c.other) or ""))
	if full then
		local shown = 0
		for _, r in ipairs(list) do
			local st = D:Status(r.qid, r.q)
			if st ~= "done" and st ~= "faction" then
				DEFAULT_CHAT_FRAME:AddMessage("   " .. D:Line(r.qid, r.q))
				shown = shown + 1
				if shown >= 15 then break end
			end
		end
	end
end

ns:AddSlash("db", function(arg)
	arg = (arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, rest = arg:match("^(%S+)%s*(.*)$")
	cmd = (cmd or ""):lower()
	if cmd == "" then
		local m = ns.Quests.offerMap
		if m then PrintZone(m, true) end
		local shipped = D:ShippedCount()
		ns.Print(string.format("database: %d quests from %d zones%s%s. /nq db <name> searches it, /nq db way <id> points the arrow.",
			D:Count(), (function() local n = 0 for _ in pairs(Store().scan) do n = n + 1 end return n end)(),
			shipped > 0 and string.format(", %d of them shipped with the addon", shipped) or "",
			D.scanning and string.format(" (scanning, %d zones to go)", #D.queue) or ""))
		if #D.loads > 0 then
			ns.Print(string.format("asking the game about %d more quests from your chains.", #D.loads))
		end
	elseif cmd == "zone" then
		local m = rest ~= "" and ns.Nav.FindZone(rest) or ns.Quests.offerMap
		if not m then ns.Print("no zone called " .. rest .. ".") return end
		PrintZone(ns.Nav.GetZoneMap(m) or m, true)
	elseif cmd == "scan" then
		if D.scanning then ns.Print("already scanning, " .. #D.queue .. " zones to go.") return end
		D.manual = true
		D:StartScan(true)
		ns.Print(string.format("scanning %d zones in the background (about %d seconds).", D.total or 0, (D.total or 0) * SCAN_GAP))
	elseif cmd == "way" or cmd == "go" then
		local qid = tonumber(rest)
		local q = qid and D:Get(qid)
		if not q or not q.m then ns.Print("no known spot for quest " .. (rest ~= "" and rest or "?") .. ". /nq db <name> shows quest IDs.") return end
		ns.Nav:AddUser(q.m, q.x, q.y, "Pick up: " .. (q.t or ("Quest " .. qid)))
	elseif cmd == "map" then
		ns.db.questdb.worldmap = not ns.db.questdb.worldmap
		ns.Print("known quests on the world map " .. (ns.db.questdb.worldmap and "on." or "off."))
		D:ClearNearby()
		ns:SendMessage("MAP_OFFERS_UPDATED")
	elseif cmd == "minimap" then
		ns.db.questdb.minimap = not ns.db.questdb.minimap
		ns.Print("known quests on the minimap " .. (ns.db.questdb.minimap and "on." or "off."))
		D:ClearNearby()
		ns:SendMessage("MAP_OFFERS_UPDATED")
	elseif cmd == "export" then
		local text, n = D:Export()
		-- Whether or not there's anything to export yet, outstanding work is the thing you
		-- need told: it's the reason an export would be short, and the reason to wait.
		local busy
		if D.scanning or #D.loads > 0 then
			busy = string.format("|cffff9933still working|r: %s%s%s.",
				D.scanning and string.format("%d zones to scan", #D.queue) or "",
				(D.scanning and #D.loads > 0) and ", " or "",
				#D.loads > 0 and string.format("%d quests to ask about", #D.loads) or "")
		end
		if n == 0 then
			ns.Print((busy and (busy .. " ") or "")
				.. "no quest starts with a place to export yet." .. (busy and "" or " /nq db scan fills the database in."))
			return
		end
		if busy then
			ns.Print(busy .. " Your export will be short of what it could be, so it's worth waiting.")
		end
		ns.UI:ShowIO("export", text, "Export quest starts",
			n .. " quest starts. Press Ctrl+C to copy. Quests and places only: no character or realm names.")
	elseif cmd == "import" then
		ns.UI:ShowIO("import", rest ~= "" and rest or "", "Import quest starts",
			"Paste quest start data (it begins with NQQ1~) and press Import.", function(t) return D:Import(t) end)
	elseif cmd == "ready" or cmd == "status" then
		if D.scanning then
			ns.Print(string.format("zone scan running: %d of %d zones to go (about %d seconds).",
				#D.queue, D.total or 0, #D.queue * SCAN_GAP))
		elseif #D.loads > 0 then
			ns.Print(string.format("asking the game about %d more quests from your chains (about %d seconds).",
				#D.loads, math.ceil(#D.loads / LOAD_BATCH * (LOAD_READ + LOAD_GAP))))
		else
			local _, n = D:Export()
			ns.Print(string.format("nothing running. %d quests known, %d of them with a place to put on the map.",
				D:Count(), n))
		end
	elseif cmd == "ask" then
		local ok, why = D:Ask()
		ns.Print(ok and "asked your guild for quest starts. Answers arrive over the next few seconds."
			or ("can't ask: " .. (why or "?")))
	elseif cmd == "guild" then
		ns.db.questdb.guild = not ns.db.questdb.guild
		ns.Print("sharing quest starts with your guild " .. (ns.db.questdb.guild and "on." or "off."))
	elseif cmd == "share" then
		ns.db.questdb.share = not ns.db.questdb.share
		ns.Print("sharing quest starts with your party " .. (ns.db.questdb.share and "on." or "off."))
	else
		local found, total = D:Search(arg, 8)
		if #found == 0 then ns.Print("no known quest matches \"" .. arg .. "\".") return end
		ns.Print(string.format("%d match%s%s:", total, total == 1 and "" or "es", total > #found and (", first " .. #found) or ""))
		for _, r in ipairs(found) do DEFAULT_CHAT_FRAME:AddMessage("   " .. D:Line(r.qid, r.q)) end
		if #found == 1 and found[1].q.m and found[1].q.x then
			DEFAULT_CHAT_FRAME:AddMessage("   /nq db way " .. found[1].qid .. " points the arrow there.")
		end
	end
end, "/nq db [name|zone <zone>|way <id>|scan|ready|ask|guild|share|map|minimap|export|import] - the quest database: search it, list a zone, point the arrow, check whether it's finished, ask your guild for theirs")

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns:RegisterMessage("QUESTS_UPDATED", function()
	ns.Debounce("questdb:log", 5, function() D:RecordLog() end)
end)

ns:RegisterEvent("QUEST_ACCEPTED", function()
	ns.Debounce("questdb:log", 2, function() D:RecordLog() end)
end)

ns:RegisterEvent("PLAYER_LEVEL_UP", function()
	-- New quests open up: look again once the level-up settles.
	ns.After(20, function() D:StartScan() end)
end)

ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
	if D.started then return end
	D.started = true
	ns.After(30, function() D:StartScan() end)
end)
