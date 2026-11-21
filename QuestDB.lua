-- NeverQuest quest database: every quest the game has shown you, account-wide.
--
-- Built only from the game client itself, nothing copied from other addons or sites:
--   * a slow background scan asks the game which quests each zone offers (one zone every
--     couple of seconds, paused in combat), once at login and again after you level;
--   * quest givers you see on the world map or nearby are added as you play;
--   * quests you accept add their level, giver spot and NPC name.
-- Every character adds to it, so an alt sees where quests are that it hasn't been offered yet.
-- /nq db <name> searches it, /nq db lists the quests in your zone, and the world map shows
-- known quests that aren't on offer to you right now (faded, with the level they open at).

local ADDON, ns = ...
local D = { queue = {}, scanning = false }
ns.QuestDB = D

local SCAN_GAP = 2            -- seconds between zones
local SCAN_WAIT = 1.5         -- seconds to let the game answer before reading a zone
local RESCAN_AFTER = 6 * 3600 -- full rescan per character after this long (or a new level)

local function Store() return ns.db.questDB end
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
-- spot: "giver" (a real giver position) or nil (title/level only).
function D:Add(qid, title, level, m, x, y)
	qid = ns.Num(qid)
	if not qid or qid <= 0 then return nil end
	local s = Store()
	local q = s.q[qid]
	if not q then
		q = {}
		s.q[qid] = q
	end
	q.t = Text(title) or q.t
	level = ns.Num(level)
	if level and level > 0 then q.l = level end
	x, y = ns.Num(x), ns.Num(y)
	if m and x and y and not (x == 0 and y == 0) and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
		q.m, q.x, q.y = m, R3(x), R3(y)
	end
	local f = Faction()
	if not q.f then q.f = f elseif not q.f:find(f, 1, true) then q.f = q.f .. f end
	local c = Class()
	if not q.c then q.c = "," .. c .. "," elseif not q.c:find("," .. c .. ",", 1, true) then q.c = q.c .. c .. "," end
	q.s = time()
	return q
end

-- A zone's quest givers as the game lists them (Quests.lua CollectOffers calls this).
-- full: the game has answered for this zone, so what's missing isn't on offer to you.
function D:Record(m, list, full)
	if not ns.ready or not m or not list then return end
	for _, o in ipairs(list) do self:Add(o.questID, o.title, o.level, o.m or m, o.x, o.y) end
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
		local q = self:Add(e.questID, e.title, e.level, at and at.m, at and at.x, at and at.y)
		if q and e.zone and Text(e.zone) then q.z = e.zone end
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
		if self.manual then
			self.manual = nil
			ns.Print(string.format("quest database scan done: %d zones, %d quests known.", self.total or 0, self:Count()))
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
end

---------------------------------------------------------------------------
-- Looking things up
---------------------------------------------------------------------------
function D:Count()
	local n = 0
	for _ in pairs(Store().q) do n = n + 1 end
	return n
end

-- "done", "log", "available" (the game offers it now), "later" (level), "other" (seen by your
-- other characters only), or "unknown".
function D:Status(qid, q)
	q = q or Store().q[qid]
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
	for qid, q in pairs(Store().q) do
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
	for qid, q in pairs(Store().q) do
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
	for qid, q in pairs(s.q) do
		if q.m and q.t and not offered[qid] and (q.m == mapID or Zone(q.m) == shown) and (not q.f or q.f:find(mine, 1, true)) then
			local lv = q.l
			local okLevel = not lv or (lv <= level + (cfg.ahead or 3) and (ns.db.givers.gray or lv >= level - (cfg.grayBelow or 6)))
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
						table.insert(out, { qid = qid, q = q, x = x, y = y, status = st, sub = sub })
					end
				end
			end
		end
	end
	return out
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
		ns.Print(string.format("database: %d quests from %d zones%s. /nq db <name> searches it, /nq db way <id> points the arrow.",
			D:Count(), (function() local n = 0 for _ in pairs(Store().scan) do n = n + 1 end return n end)(),
			D.scanning and string.format(" (scanning, %d zones to go)", #D.queue) or ""))
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
		local q = qid and Store().q[qid]
		if not q or not q.m then ns.Print("no known spot for quest " .. (rest ~= "" and rest or "?") .. ". /nq db <name> shows quest IDs.") return end
		ns.Nav:AddUser(q.m, q.x, q.y, "Pick up: " .. (q.t or ("Quest " .. qid)))
	elseif cmd == "map" then
		ns.db.questdb.worldmap = not ns.db.questdb.worldmap
		ns.Print("known quests on the world map " .. (ns.db.questdb.worldmap and "on." or "off."))
		ns:SendMessage("MAP_OFFERS_UPDATED")
	else
		local found, total = D:Search(arg, 8)
		if #found == 0 then ns.Print("no known quest matches \"" .. arg .. "\".") return end
		ns.Print(string.format("%d match%s%s:", total, total == 1 and "" or "es", total > #found and (", first " .. #found) or ""))
		for _, r in ipairs(found) do DEFAULT_CHAT_FRAME:AddMessage("   " .. D:Line(r.qid, r.q)) end
		if #found == 1 and found[1].q.m and found[1].q.x then
			DEFAULT_CHAT_FRAME:AddMessage("   /nq db way " .. found[1].qid .. " points the arrow there.")
		end
	end
end, "/nq db [name|zone <zone>|way <id>|scan|map] - the quest database: search it, list a zone, point the arrow")

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
