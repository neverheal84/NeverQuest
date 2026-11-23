-- NeverQuest Fixes: where QuestieDB's quest data turned out to be wrong, as your own game shows it.
--
-- QuestieDB (the Questie team's quest database, read by Library.lua) fills in quest givers and
-- turn-ins NeverQuest hasn't seen for itself. Now and then a place is wrong for WoW Forever.
-- This notices when the game says so and writes it down, so the wrong place stops being shown:
--
--   * not here: you stood where QuestieDB puts a quest giver, the game was asked again what your
--     zone offers you, and that quest was not among them. QuestieDB's place is dropped for
--     characters of the same race and class (a quest can be for some races or classes only).
--   * moved: you took the quest, or handed it in, at an NPC well away from where QuestieDB said.
--     What NeverQuest saw itself replaces QuestieDB's place anyway; this keeps a note so the
--     data can be put right.
--   * you said so: Ctrl+click a known quest on the world map. Hidden for all your characters.
--
-- When the game later offers the quest, a "not here" note is dropped (or becomes "moved" if the
-- giver turned out to be elsewhere). Nothing here is shared with your party or guild, and
-- QuestieDB itself is never changed; /nq db export carries the notes, places only, so they can
-- be passed on to the Questie team.

local ADDON, ns = ...
local F = {}
ns.Fixes = F

local NEAR = 25          -- yards: standing here, the quest giver would be right in front of you
local MOVED = 60         -- yards between QuestieDB's place and the real one before it counts as wrong
local CONFIRM = 5        -- seconds at an empty spot, with a fresh answer from the game, before it counts
local TICK = 2
local LIST_TTL = 30      -- seconds the zone's QuestieDB places are reused before being worked out again
local ASK_GAP = 4        -- seconds between asking the game again what your zone offers
local MAX_NOTES = 2500

local function R4(v) return v and math.floor(v * 10000 + 0.5) / 10000 end

local function Store()
	local s = ns.db.questDB
	if type(s.fix) ~= "table" then s.fix = {} end
	return s.fix
end

-- Race and class, as the game names them: a "not here" only holds for characters like this one.
function F:Me()
	if not self.me then
		self.me = (select(2, UnitRace("player")) or "?") .. "-" .. (select(2, UnitClass("player")) or "?")
	end
	return self.me
end

function F:On() return ns.db.questdb.fixes ~= false end

-- Whether to drop a quest's giver place: "all" (you said it isn't there), "borrowed" (the
-- QuestieDB place was empty for a character like this one) or nil. Called for every quest on
-- every map draw, so it does as little as it can.
function F:HideStart(qid)
	local fix = ns.db.questDB.fix
	local f = fix and fix[qid]
	local s = f and f.s
	if not s then return nil end
	if s.why == "user" then return "all" end
	if s.why == "gone" and ns.db.questdb.fixes ~= false and s.who == (self.me or self:Me()) then return "borrowed" end
	return nil
end

function F:Get(qid) return Store()[qid] end

function F:Count()
	local n, gone, moved, user = 0, 0, 0, 0
	for _, f in pairs(Store()) do
		for _, r in pairs(f) do
			n = n + 1
			if r.why == "gone" then gone = gone + 1 elseif r.why == "user" then user = user + 1 else moved = moved + 1 end
		end
	end
	return n, gone, moved, user
end

local function Changed()
	if ns.QuestDB then ns.QuestDB:ClearNearby() end
	ns:SendMessage("MAP_OFFERS_UPDATED")
	ns:SendMessage("FIXES_UPDATED")
end

-- Keeps the notes to a size saved variables can carry: the oldest go first.
local function Trim(fix)
	local n = 0
	for _ in pairs(fix) do n = n + 1 end
	if n <= MAX_NOTES then return end
	local all = {}
	for qid, f in pairs(fix) do
		local at = math.huge
		for _, r in pairs(f) do at = math.min(at, r.at or 0) end
		all[#all + 1] = { qid = qid, at = at }
	end
	table.sort(all, function(a, b) return a.at < b.at end)
	for i = 1, n - MAX_NOTES do fix[all[i].qid] = nil end
end

-- side "s" (where the quest is picked up) or "e" (where it is handed in).
function F:Note(qid, side, why, bundled, real)
	if not qid or (side ~= "s" and side ~= "e") then return end
	local fix = Store()
	local f = fix[qid] or {}
	local r = { why = why, at = time and time() or 0, v = ns.version }
	if bundled and bundled.m then r.m, r.x, r.y = bundled.m, R4(bundled.x), R4(bundled.y) end
	if real and real.m then r.rm, r.rx, r.ry = real.m, R4(real.x), R4(real.y) end
	if why == "gone" then r.who = self:Me() end
	f[side] = r
	fix[qid] = f
	Trim(fix)
	Changed()
	return r
end

function F:Clear(qid, side)
	local fix = Store()
	local f = fix[qid]
	if not f then return false end
	if side then f[side] = nil else f = nil end
	if f and next(f) == nil then f = nil end
	fix[qid] = f
	Changed()
	return true
end

function F:ClearAll()
	local n = self:Count()
	ns.db.questDB.fix = {}
	Changed()
	return n
end

local function Title(qid)
	local q = ns.QuestDB and ns.QuestDB:Get(qid)
	return (q and q.t) or ("Quest " .. qid)
end

---------------------------------------------------------------------------
-- You said so: Ctrl+click on a known quest on the world map.
---------------------------------------------------------------------------
function F:NotHere(qid, m, x, y)
	if not qid then return end
	local title = Title(qid)
	local b = ns.QuestDB and ns.QuestDB:BundledStart(qid)
	self:Note(qid, "s", "user", b or (m and { m = m, x = x, y = y }))
	ns.Print(string.format("|cffffd100%s|r won't be shown there any more. /nq db fixes undo %d brings it back.", title, qid))
end

---------------------------------------------------------------------------
-- Not here: standing at QuestieDB's place for a quest giver, and the game doesn't offer the quest.
---------------------------------------------------------------------------
local zone = { id = nil, at = -math.huge, list = nil }
local pending = {}
local lastAsk = -math.huge

function F:ForgetZone() zone.id, zone.list = nil, nil end

-- The QuestieDB places in a zone that are in use right now: quests NeverQuest itself has no place
-- for, that this character can take. Only the zone's own map; a giver inside a building or cave
-- with a map of its own is left alone, since the zone's list may not include it.
local function Candidates(zoneMap)
	local now = GetTime()
	if zone.id == zoneMap and zone.list and now - zone.at < LIST_TTL then return zone.list end
	local D, out, seen = ns.QuestDB, {}, {}
	local lvl = UnitLevel("player") or 1
	local gray = ns.db.questdb.grayBelow or 6
	local function Consider(qid, m)
		if seen[qid] or m ~= zoneMap then return end
		seen[qid] = true
		local q = D:Get(qid)
		if not (q and q.lib and q.m == zoneMap and q.x and q.y) then return end
		-- The game may leave a gray quest out of the list; nothing can be read from its absence.
		if q.l and q.l < lvl - gray then return end
		if D:Status(qid, q) ~= "available" then return end
		out[#out + 1] = { qid = qid, m = q.m, x = q.x, y = q.y }
	end
	for qid, e in pairs(ns.Library and ns.Library:Layer() or {}) do Consider(qid, e.m) end
	zone.id, zone.at, zone.list = zoneMap, now, out
	return out
end

function F:Tick()
	if not self:On() or not (ns.QuestDB and ns.QuestDB:Bundled()) or not ns.ready then return end
	if InCombatLockdown() or UnitIsDeadOrGhost("player") or (IsInInstance and IsInInstance()) then return end
	local Q = ns.Quests
	local m = ns.SafeCall(C_Map.GetBestMapForUnit, "player")
	local zoneMap = m and ns.Nav.GetZoneMap(m)
	if not zoneMap or m ~= zoneMap or Q.offerMap ~= zoneMap then wipe(pending) return end
	local offered = {}
	for _, o in ipairs(Q.offers or {}) do if o.questID then offered[o.questID] = true end end
	local now, near = GetTime(), {}
	for _, c in ipairs(Candidates(zoneMap)) do
		local d = ns.Nav.Distance(c.m, c.x, c.y)
		if d and d <= NEAR and not offered[c.qid] then
			near[c.qid] = true
			local p = pending[c.qid]
			if not p then
				pending[c.qid] = { t = now }
				if now - lastAsk >= ASK_GAP then
					lastAsk = now
					Q:RequestOffers()
				end
			elseif now - p.t >= CONFIRM and (Q.answeredAt or 0) > p.t and (Q.offersRead or 0) >= (Q.answeredAt or 0) then
				pending[c.qid] = nil
				-- One last look: what you can take may have changed while you stood here.
				if ns.QuestDB:Status(c.qid) == "available" then
					self:Note(c.qid, "s", "gone", c)
					self:ForgetZone()
				end
			end
		end
	end
	for qid in pairs(pending) do if not near[qid] then pending[qid] = nil end end
end

---------------------------------------------------------------------------
-- Moved: the giver or the turn-in turned out to be somewhere else.
---------------------------------------------------------------------------
local function Far(b, real)
	if not (b and real and real.m) then return false end
	local d = ns.Nav.DistanceBetween(b.m, b.x, b.y, real.m, real.x, real.y)
	return d == nil or d > MOVED
end

ns:RegisterEvent("QUEST_ACCEPTED", function(_, questID)
	if not (questID and F:On() and ns.Quests:TakenFromNPC(questID)) then return end
	local real = ns.db.npcs.giverAt[questID]
	local b = ns.QuestDB:BundledStart(questID)
	if not (b and real) then return end
	if Far(b, real) then
		F:Note(questID, "s", "moved", b, real)
	else
		local f = F:Get(questID)
		if f and f.s and f.s.why == "gone" then F:Clear(questID, "s") end
	end
end)

ns:RegisterEvent("QUEST_TURNED_IN", function(_, questID)
	if not (questID and F:On()) then return end
	-- Quests.lua has just saved where you stood if you handed it in at the NPC; a spot saved
	-- before, with you somewhere else now, says nothing about this turn-in.
	local real = ns.db.npcs.turninAt[questID]
	if not real then return end
	local here = ns.Nav.Distance(real.m, real.x, real.y)
	if not here or here > 5 then return end
	local b = ns.QuestDB:BundledEnd(questID)
	if b and Far(b, real) then F:Note(questID, "e", "moved", b, real) end
end)

-- The game offering a quest settles a "not here": it was a matter of what you could take (the
-- note goes), or the giver stands somewhere else (the note says where).
ns:RegisterMessage("OFFERS_UPDATED", function()
	local fix = ns.db.questDB.fix
	if not fix or next(fix) == nil then return end
	for _, o in ipairs(ns.Quests.offers or {}) do
		local f = o.questID and fix[o.questID]
		local s = f and f.s
		if s and (s.why == "gone" or s.why == "user") then
			local real = { m = o.m, x = o.x, y = o.y }
			if s.m and Far(s, real) then
				s.why, s.who, s.rm, s.rx, s.ry = "moved", nil, o.m, R4(o.x), R4(o.y)
				Changed()
			elseif s.why == "gone" then
				F:Clear(o.questID, "s")
			end
		end
	end
end)

for _, msg in ipairs({ "QUESTDB_UPDATED", "MAP_OFFERS_UPDATED" }) do
	ns:RegisterMessage(msg, function() zone.at = -math.huge end)
end
ns:RegisterEvent("PLAYER_LEVEL_UP", function() F:ForgetZone() end)
ns:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() wipe(pending) end)

ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
	if F.ticker then return end
	F.ticker = ns.Ticker(TICK, "fixes", function() F:Tick() end)
end)

---------------------------------------------------------------------------
-- Export: places only, nothing about you.
--   X<side>^<questID>^<why>^<map>^<x>^<y>^<real map>^<real x>^<real y>
---------------------------------------------------------------------------
local function Num4(v) return v and string.format("%.4f", v) or "" end

function F:ExportRecords()
	local out, ids = {}, {}
	for qid in pairs(Store()) do ids[#ids + 1] = qid end
	table.sort(ids)
	for _, qid in ipairs(ids) do
		local f = Store()[qid]
		for _, side in ipairs({ "s", "e" }) do
			local r = f[side]
			if r and r.why then
				out[#out + 1] = table.concat({ "X" .. side, tostring(qid), r.why, r.m and tostring(r.m) or "", Num4(r.x), Num4(r.y),
					r.rm and tostring(r.rm) or "", Num4(r.rx), Num4(r.ry) }, "^")
			end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- /nq db fixes
---------------------------------------------------------------------------
local WHY = {
	gone = "the giver wasn't there for you: the game didn't offer the quest where QuestieDB puts it",
	moved = "found somewhere else",
	user = "you said it isn't there",
}

function F:Lines(limit)
	local rows = {}
	for qid, f in pairs(Store()) do
		for side, r in pairs(f) do rows[#rows + 1] = { qid = qid, side = side, r = r } end
	end
	table.sort(rows, function(a, b) return (a.r.at or 0) > (b.r.at or 0) end)
	local lines = {}
	for i = 1, math.min(#rows, limit or 10) do
		local row = rows[i]
		local r = row.r
		local where = row.side == "e" and "turn-in" or "giver"
		local real = r.rm and string.format(" (really at %s %.1f, %.1f)", ns.Nav.MapName(r.rm) or r.rm, (r.rx or 0) * 100, (r.ry or 0) * 100) or ""
		local who = r.who and (" [" .. r.who:gsub("%-", " "):lower() .. "]") or ""
		lines[#lines + 1] = string.format("|cffffd100%d|r %s, %s: %s%s%s", row.qid, Title(row.qid), where, WHY[r.why] or r.why, real, who)
	end
	return lines, #rows
end

function F:Command(rest)
	rest = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	local undo = rest:match("^undo%s+(%d+)$")
	if rest == "clear" then
		local n = self:ClearAll()
		ns.Print(string.format("forgot %d note%s about QuestieDB's quest data.", n, n == 1 and "" or "s"))
		return
	elseif undo then
		local qid = tonumber(undo)
		if self:Clear(qid) then
			ns.Print(string.format("|cffffd100%s|r: the note is gone, and QuestieDB's place is used again.", Title(qid)))
		else
			ns.Print("no note for quest " .. undo .. ".")
		end
		return
	elseif rest ~= "" then
		ns.Print("/nq db fixes [undo <quest number> | clear]: where QuestieDB's quest data turned out to be wrong.")
		return
	end
	local n, gone, moved, user = self:Count()
	if n == 0 then
		ns.Print("no notes yet about QuestieDB's quest data being wrong." .. (self:On() and "" or " Noting them is switched off (Options, Quest database)."))
		return
	end
	ns.Print(string.format("%d place%s where QuestieDB's quest data was wrong: %d not there for you, %d found somewhere else, %d you marked yourself. Newest first:",
		n, n == 1 and "" or "s", gone, moved, user))
	local lines, total = self:Lines(10)
	for _, line in ipairs(lines) do DEFAULT_CHAT_FRAME:AddMessage("   " .. line) end
	if total > #lines then DEFAULT_CHAT_FRAME:AddMessage(string.format("   ...and %d more.", total - #lines)) end
	DEFAULT_CHAT_FRAME:AddMessage("   /nq db fixes undo <quest number> brings one back, /nq db fixes clear forgets them all. Export starts sends them in.")
end
