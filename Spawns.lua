-- NeverQuest Spawns: remembers where quest mobs, quest drops and objectives are, plus spots you
-- mark yourself and rares or treasures you spot. NeverQuest ships no spawn database: every spot
-- here comes from your own game client while you play, from your party, or from a string a
-- friend gave you. Shared by all your characters.
--
-- How spots are learned:
--   kill credit   a "slain" objective goes up: the mob died within fighting range of you
--   quest loot    a quest item comes from a corpse or an object: you were standing at it
--   other         "use", "explore" and similar objectives tick over where you are
--   sightings     a mob tied to one of your quests is close by (nameplate, target, mouseover)
--   vignettes     rares and treasures the game shows on your minimap

local ADDON, ns = ...
local S = {}
ns.Spawns = S

local floor, min = math.floor, math.min

local MERGE_YARDS = 35      -- sightings closer than this become one spot
local RARE_MERGE = 60
local MAX_SPOTS = 40        -- per mob or objective per map; the weakest spots drop off
local MAX_COUNT = 999
local MAX_MARKS = 500
local SIGHT_COOLDOWN = 45   -- seconds before the same mob near the same spot counts again
local LOOT_WINDOW = 8       -- seconds a loot window stays linked to quest progress
local VISITED_YARDS = 25    -- the guide moves on from a spot once you've been this close
local VISITED_FOR = 180     -- ...and comes back to it after this many seconds
local MAP_CAP = 300         -- most learned spots drawn on one world map

local LINE_QUEST_TITLE = (Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle) or 17
local LINE_QUEST_OBJECTIVE = (Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective) or 8

-- One color per active quest, in quest log order.
S.PALETTE = {
	{ 1.00, 0.82, 0.10 }, { 0.30, 0.80, 1.00 }, { 1.00, 0.42, 0.32 }, { 0.50, 1.00, 0.35 },
	{ 0.85, 0.50, 1.00 }, { 1.00, 0.62, 0.15 }, { 0.35, 1.00, 0.85 }, { 1.00, 0.50, 0.78 },
}
S.GRAY = { 0.72, 0.72, 0.72 }
S.version = 0

local function Data() return ns.db.spawnData end
local function Cfg() return ns.db.spawns end
local function Round(v) return floor(v * 10000 + 0.5) / 10000 end

-- Text safe to store and send: no secret values, color codes or the separators used below.
local function Clean(text)
	if type(text) ~= "string" or ns.IsSecret(text) then return nil end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[|%^~\r\n]", "")
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	return text ~= "" and text or nil
end
S.Clean = Clean

local function Key(name) return name:lower() end

-- Calls a game function and returns its first result, or nil when it errors or the game
-- hides the answer (a secret value can't even be tested, so check before using it).
local function SafeCall(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn, ...)
	if not ok or v == nil or ns.IsSecret(v) then return nil end
	return v
end

local function ValidPoint(m, x, y)
	return type(m) == "number" and m > 0 and type(x) == "number" and type(y) == "number"
		and x >= 0 and x <= 1 and y >= 0 and y <= 1
end

-- "Kobold Vermin slain: 3/10", "0/10 Kobold Vermin slain" and "Linen Cloth: 3/10" all give
-- the bare name. Text without a count ("Speak with Marshal Dughan") comes back as it is.
function S.ObjectiveName(text)
	text = Clean(text)
	if not text then return nil end
	local killed = ns.KillName(text)
	if killed then return killed end
	local s = text:gsub("^%-%s*", ""):gsub("%s*%(.-%)%s*$", "")
	s = s:gsub("%d+%s*/%s*%d+", "")
	s = s:gsub("%s*:%s*$", ""):gsub("^%s*:%s*", "")
	s = s:gsub("%s+slain$", ""):gsub("^%s+", ""):gsub("%s+$", "")
	return s ~= "" and s or nil
end

local function Ago(t)
	if not t then return "a while" end
	local d = math.max(0, time() - t)
	if d < 60 then return "moments" end
	if d < 3600 then return floor(d / 60) .. " min" end
	if d < 86400 then return floor(d / 3600) .. " h" end
	return floor(d / 86400) .. (d < 172800 and " day" or " days")
end
S.Ago = Ago

local function Changed()
	S.version = S.version + 1
	S.index = nil
	ns.Debounce("spawnsupdated", 0.3, function() ns:SendMessage("SPAWNS_UPDATED") end)
end

---------------------------------------------------------------------------
-- Spots: { x, y, count, lastSeen } per map. A new sighting close to an existing spot moves
-- it toward the average position instead of adding another.
---------------------------------------------------------------------------
local function AddSpot(rec, m, x, y, count, merge)
	rec.m = rec.m or {}
	local spots = rec.m[m]
	if not spots then
		spots = {}
		rec.m[m] = spots
	end
	local best, bestD
	for _, s in ipairs(spots) do
		local d = ns.Nav.DistanceBetween(m, s[1], s[2], m, x, y)
		if d < merge and (not bestD or d < bestD) then best, bestD = s, d end
	end
	if best then
		local total = best[3] + count
		best[1] = Round((best[1] * best[3] + x * count) / total)
		best[2] = Round((best[2] * best[3] + y * count) / total)
		best[3] = min(MAX_COUNT, total)
		best[4] = time()
		return best, false
	end
	local spot = { Round(x), Round(y), count, time() }
	table.insert(spots, spot)
	if #spots > MAX_SPOTS then
		table.sort(spots, function(a, b)
			if a[3] ~= b[3] then return a[3] > b[3] end
			return (a[4] or 0) > (b[4] or 0)
		end)
		spots[#spots] = nil
	end
	return spot, true
end

function S:LearnNpc(name, m, x, y, count, questID, objIndex, fromParty)
	name = Clean(name)
	if not name or not ValidPoint(m, x, y) then return end
	local npcs = Data().npcs
	local key = Key(name)
	local rec = npcs[key]
	if not rec then
		rec = { n = name, m = {} }
		npcs[key] = rec
	end
	if questID then
		rec.q = rec.q or {}
		if objIndex or not rec.q[questID] then rec.q[questID] = objIndex or 0 end
	end
	local spot, new = AddSpot(rec, m, x, y, count or 1, MERGE_YARDS)
	Changed()
	if new and not fromParty then self:Share("n", name, m, spot[1], spot[2], questID or 0, objIndex or 0) end
	ns.Debug(string.format("spawns: %s %s at %s %.1f, %.1f", new and "new spot for" or "seen", name, ns.Nav.MapName(m), x * 100, y * 100))
	return spot, new
end

-- Best known spot for an NPC by name (most sightings): map, x, y.
function S:NpcSpot(name)
	name = Clean(name)
	local rec = name and Data().npcs[Key(name)]
	if not rec or not rec.m then return nil end
	local bm, bs
	for m, spots in pairs(rec.m) do
		for _, s in ipairs(spots) do
			if not bs or s[3] > bs[3] then bm, bs = m, s end
		end
	end
	if bs then return bm, bs[1], bs[2] end
end

function S:LearnObjective(questID, objIndex, text, m, x, y, count, fromParty)
	if not questID or not objIndex or not ValidPoint(m, x, y) then return end
	local objs = Data().objs
	objs[questID] = objs[questID] or {}
	local rec = objs[questID][objIndex]
	if not rec then
		rec = { t = Clean(text), m = {} }
		objs[questID][objIndex] = rec
	end
	rec.t = rec.t or Clean(text)
	local spot, new = AddSpot(rec, m, x, y, count or 1, MERGE_YARDS)
	Changed()
	if new and not fromParty then self:Share("o", questID, objIndex, m, spot[1], spot[2], rec.t or "") end
	ns.Debug(string.format("spawns: objective spot for quest %d #%d at %s %.1f, %.1f", questID, objIndex, ns.Nav.MapName(m), x * 100, y * 100))
	return spot, new
end

function S:LearnRare(name, atlas, m, x, y, vignetteID)
	name = Clean(name)
	if not name or not ValidPoint(m, x, y) then return end
	local rares = Data().rares
	local key = (vignetteID and vignetteID > 0) and ("v" .. vignetteID) or Key(name)
	local rec = rares[key]
	if not rec then
		rec = { n = name, m = {} }
		rares[key] = rec
	end
	if atlas and atlas ~= "" then rec.a = atlas end
	local spot, new = AddSpot(rec, m, x, y, 1, RARE_MERGE)
	Changed()
	ns.Debug(string.format("spawns: rare or treasure %s at %s %.1f, %.1f", name, ns.Nav.MapName(m), x * 100, y * 100))
	return spot, new
end

-- Links a mob to a quest (and objective, when known) without adding a spot.
function S:Link(name, questID, objIndex)
	name = Clean(name)
	if not name or not questID then return end
	local npcs = Data().npcs
	local rec = npcs[Key(name)]
	if not rec then
		rec = { n = name, m = {} }
		npcs[Key(name)] = rec
	end
	rec.q = rec.q or {}
	local cur = rec.q[questID]
	if cur == nil or (objIndex and cur ~= objIndex) then
		rec.q[questID] = objIndex or cur or 0
		Changed()
	end
end

---------------------------------------------------------------------------
-- Your own marks: spawns, objective spots and notes placed by hand.
---------------------------------------------------------------------------
local MARK_KINDS = { spawn = true, objective = true, note = true }

function S:MarkLabel(mark)
	if mark.k == "spawn" then return "Spawn: " .. (mark.l or "?") end
	if mark.k == "objective" then
		local title = mark.q and C_QuestLog.GetTitleForQuestID(mark.q)
		return "Objective: " .. (mark.l or "?") .. ((title and not ns.IsSecret(title)) and (" (" .. title .. ")") or "")
	end
	return mark.l or "Note"
end

function S:AddMark(m, x, y, kind, label, questID, objIndex, from)
	if not ValidPoint(m, x, y) then return end
	kind = MARK_KINDS[kind] and kind or "note"
	label = Clean(label)
	if kind == "spawn" and not label then return end
	local marks = Data().marks
	x, y = Round(x), Round(y)
	for _, mk in ipairs(marks) do
		if mk.m == m and mk.k == kind and mk.l == label and ns.Nav.DistanceBetween(m, mk.x, mk.y, m, x, y) < 5 then
			return mk
		end
	end
	local mark = { m = m, x = x, y = y, k = kind, l = label, q = questID, o = objIndex, t = time(), by = from }
	table.insert(marks, mark)
	while #marks > MAX_MARKS do table.remove(marks, 1) end
	Changed()
	if not from then
		self:Share("k", kind, label or "", m, x, y, questID or 0, objIndex or 0)
		ns.Print(string.format("marked %s at %s %.1f, %.1f.", self:MarkLabel(mark), ns.Nav.MapName(m), x * 100, y * 100))
	end
	return mark
end

function S:RemoveMark(mark)
	local marks = Data().marks
	for i, mk in ipairs(marks) do
		if mk == mark then
			table.remove(marks, i)
			Changed()
			return true
		end
	end
end

function S:MarksNear(m, x, y, yards)
	local out = {}
	for _, mk in ipairs(Data().marks) do
		local d = (mk.m == m) and ns.Nav.DistanceBetween(m, mk.x, mk.y, m, x, y)
		if not d and ns.Nav.GetContinentMap(mk.m) == ns.Nav.GetContinentMap(m) then
			d = ns.Nav.DistanceBetween(mk.m, mk.x, mk.y, m, x, y)
		end
		if d and d <= yards then table.insert(out, mk) end
	end
	return out
end

---------------------------------------------------------------------------
-- Forgetting
---------------------------------------------------------------------------
function S:ForgetSpot(spots, spot)
	if not spots then return end
	for i, s in ipairs(spots) do
		if s == spot then
			table.remove(spots, i)
			Changed()
			return true
		end
	end
end

function S:ForgetEntry(ent)
	if not ent then return end
	if ent.kind == "npc" then
		local npcs = Data().npcs
		for key, rec in pairs(npcs) do
			if rec == ent.rec then npcs[key] = nil end
		end
	elseif ent.kind == "obj" then
		for _, list in pairs(Data().objs) do
			for i, rec in pairs(list) do
				if rec == ent.rec then list[i] = nil end
			end
		end
	elseif ent.kind == "mark" then
		return self:RemoveMark(ent.rec)
	elseif ent.kind == "rare" then
		local rares = Data().rares
		for key, rec in pairs(rares) do
			if rec == ent.rec then rares[key] = nil end
		end
	end
	Changed()
end

function S:ForgetName(name)
	name = Clean(name)
	if not name then return false end
	local npcs = Data().npcs
	if npcs[Key(name)] then
		npcs[Key(name)] = nil
		Changed()
		return true
	end
	return false
end

function S:Clear(what)
	local data = Data()
	if what == "learned" or what == "all" then
		wipe(data.npcs)
		wipe(data.objs)
	end
	if what == "marks" or what == "all" then wipe(data.marks) end
	if what == "rares" or what == "all" then wipe(data.rares) end
	Changed()
end

function S:Stats()
	local data = Data()
	local st = { mobs = 0, mobSpots = 0, objSpots = 0, marks = #data.marks, rares = 0 }
	for _, rec in pairs(data.npcs) do
		st.mobs = st.mobs + 1
		for _, spots in pairs(rec.m or {}) do st.mobSpots = st.mobSpots + #spots end
	end
	for _, list in pairs(data.objs) do
		for _, rec in pairs(list) do
			for _, spots in pairs(rec.m or {}) do st.objSpots = st.objSpots + #spots end
		end
	end
	for _ in pairs(data.rares) do st.rares = st.rares + 1 end
	return st
end

function S:StatsText()
	local st = self:Stats()
	return string.format("%d mobs at %d spots, %d objective spots, %d marks, %d rares and treasures",
		st.mobs, st.mobSpots, st.objSpots, st.marks, st.rares)
end

---------------------------------------------------------------------------
-- What to draw: spots for the open objectives of your quests (plus everything, with
-- "show all known spawns"), and your marks. Rebuilt when quests or spots change.
---------------------------------------------------------------------------
function S:Invalidate()
	self.index = nil
end

-- After a settings change: redraw everything that shows spots.
function S:Refresh()
	Changed()
end

local function AddRef(idx, ent, qid, i)
	for _, r in ipairs(ent.refs) do
		if r.q == qid and r.i == i then return end
	end
	table.insert(ent.refs, { q = qid, i = i })
end

function S:Index()
	if self.index then return self.index end
	local idx = { quests = {}, entries = {}, points = {}, byQuest = {} }
	self.index = idx
	local data, cfg = Data(), Cfg()

	local n = 0
	for _, e in ipairs(ns.Quests.log) do
		if not e.complete and not e.failed then
			local open = {}
			for i, o in ipairs(C_QuestLog.GetQuestObjectives(e.questID) or {}) do
				if not o.finished then
					open[i] = { text = Clean(o.text), type = o.type, name = S.ObjectiveName(o.text) }
				end
			end
			if next(open) then
				n = n + 1
				idx.quests[e.questID] = { e = e, open = open, color = S.PALETTE[(n - 1) % #S.PALETTE + 1] }
			end
		end
	end

	local byRec = {}
	local function Want(rec, kind, name, qid, i)
		local ent = byRec[rec]
		if not ent then
			ent = { kind = kind, rec = rec, name = name, refs = {} }
			byRec[rec] = ent
			table.insert(idx.entries, ent)
		end
		if qid then AddRef(idx, ent, qid, i) end
		return ent
	end

	local npcs = data.npcs
	for qid, q in pairs(idx.quests) do
		for i, o in pairs(q.open) do
			-- "Kobold Vermin slain": the mob with that name.
			if o.type == "monster" and o.name then
				local rec = npcs[Key(o.name)]
				if rec then Want(rec, "npc", rec.n, qid, i) end
			end
			local orec = data.objs[qid] and data.objs[qid][i]
			if orec then Want(orec, "obj", o.name or o.text or orec.t, qid, i) end
		end
	end
	-- Mobs linked to a quest by a drop or by their tooltip.
	for _, rec in pairs(npcs) do
		if rec.q then
			for qid, i in pairs(rec.q) do
				local q = idx.quests[qid]
				if q then
					if i and i > 0 then
						if q.open[i] then Want(rec, "npc", rec.n, qid, i) end
					else
						Want(rec, "npc", rec.n, qid, nil)
					end
				end
			end
		end
	end
	if cfg.showAll then
		for _, rec in pairs(npcs) do
			if not byRec[rec] then Want(rec, "npc", rec.n) end
		end
	end

	local function Index(p, ent)
		table.insert(idx.points, p)
		for _, r in ipairs(ent.refs) do
			idx.byQuest[r.q] = idx.byQuest[r.q] or {}
			table.insert(idx.byQuest[r.q], p)
		end
	end
	for _, ent in ipairs(idx.entries) do
		for m, spots in pairs(ent.rec.m or {}) do
			for _, s in ipairs(spots) do
				Index({ m = m, x = s[1], y = s[2], w = s[3], t = s[4], ent = ent, spot = s, spots = spots }, ent)
			end
		end
	end
	for _, mk in ipairs(data.marks) do
		local ent = { kind = "mark", rec = mk, name = S:MarkLabel(mk), refs = {} }
		if mk.k == "objective" and mk.q and idx.quests[mk.q] then
			if not mk.o or idx.quests[mk.q].open[mk.o] then AddRef(idx, ent, mk.q, mk.o) end
		elseif mk.k == "spawn" and mk.l then
			local key = Key(mk.l)
			for qid, q in pairs(idx.quests) do
				for i, o in pairs(q.open) do
					if o.type == "monster" and o.name and Key(o.name) == key then AddRef(idx, ent, qid, i) end
				end
				local rec = npcs[key]
				if rec and rec.q and rec.q[qid] then
					local li = rec.q[qid]
					if li == 0 then AddRef(idx, ent, qid, nil) elseif q.open[li] then AddRef(idx, ent, qid, li) end
				end
			end
		end
		Index({ m = mk.m, x = mk.x, y = mk.y, w = 1, t = mk.t, ent = ent, mark = mk }, ent)
	end
	return idx
end

function S:ColorFor(p)
	local ent = p.ent
	local r = ent and ent.refs[1]
	local q = r and self:Index().quests[r.q]
	return q and q.color or S.GRAY
end

-- Nearest known spot for one of a quest's open objectives. Spots you've just been to are
-- skipped for a few minutes, so the arrow tours the spawn points instead of parking on one.
local visited = setmetatable({}, { __mode = "k" })

function S:NearestFor(questID)
	if not ns.db.spawns.aim then return nil end
	local list = self:Index().byQuest[questID]
	if not list then return nil end
	local now = GetTime()
	local best, bestD, fresh, freshD
	for _, p in ipairs(list) do
		local d = ns.Nav.Distance(p.m, p.x, p.y)
		if d then
			local token = p.spot or p.mark
			if d <= VISITED_YARDS and token then visited[token] = now end
			if not bestD or d < bestD then best, bestD = p, d end
			local seen = token and visited[token]
			if not (seen and now - seen < VISITED_FOR) and (not freshD or d < freshD) then fresh, freshD = p, d end
		end
	end
	local p, d = fresh or best, fresh and freshD or bestD
	if not p then return nil end
	return { m = p.m, x = p.x, y = p.y, dist = d, label = p.ent.name, kind = p.ent.kind,
		mob = (p.ent.kind == "npc") and p.ent.name or (p.mark and p.mark.k == "spawn" and p.mark.l) or nil }
end

-- Nearest learned spot for any of a quest's objectives, finished or not (party catch-up uses
-- this to send you back to help someone finish a quest you've already done).
function S:AnySpotFor(questID)
	local best, bestD
	local function Try(m, s, label)
		local d = ns.Nav.Distance(m, s[1], s[2])
		if d and (not bestD or d < bestD) then best, bestD = { m = m, x = s[1], y = s[2], label = label }, d end
	end
	local data = Data()
	for _, rec in pairs(data.npcs) do
		if rec.q and rec.q[questID] ~= nil then
			for m, spots in pairs(rec.m or {}) do
				for _, s in ipairs(spots) do Try(m, s, rec.n) end
			end
		end
	end
	for _, rec in pairs(data.objs[questID] or {}) do
		for m, spots in pairs(rec.m or {}) do
			for _, s in ipairs(spots) do Try(m, s, rec.t) end
		end
	end
	if best then best.dist = bestD end
	return best
end

-- Points on (or translated onto) one world map, strongest first.
function S:MapPoints(mapID)
	local out = {}
	if not mapID then return out end
	local info = C_Map.GetMapInfo(mapID)
	local zoomedIn = info and info.mapType and info.mapType >= Enum.UIMapType.Zone
	local cont = ns.Nav.GetContinentMap(mapID)
	local sameCont = {}
	local function OnThisContinent(m)
		local v = sameCont[m]
		if v == nil then
			v = (m == mapID) or (cont ~= nil and ns.Nav.GetContinentMap(m) == cont)
			sameCont[m] = v
		end
		return v
	end
	local function Place(p, extra)
		if not OnThisContinent(p.m) then return end
		local x, y = ns.Nav.TranslatePoint(p.m, p.x, p.y, mapID)
		if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
			local pt = extra or {}
			for k, v in pairs(p) do if pt[k] == nil then pt[k] = v end end
			pt.mx, pt.my = x, y
			table.insert(out, pt)
		end
	end
	local learned = {}
	for _, p in ipairs(self:Index().points) do
		if p.mark then
			Place(p, { kind = "mark" })
		elseif zoomedIn then
			table.insert(learned, p)
		end
	end
	table.sort(learned, function(a, b) return (a.w or 0) > (b.w or 0) end)
	local placed = 0
	for _, p in ipairs(learned) do
		if placed >= MAP_CAP then break end
		local before = #out
		Place(p, { kind = "spot" })
		if #out > before then placed = placed + 1 end
	end
	if Cfg().rares then
		for _, rec in pairs(Data().rares) do
			local ent = { kind = "rare", rec = rec, name = rec.n, refs = {} }
			for m, spots in pairs(rec.m or {}) do
				for _, s in ipairs(spots) do
					Place({ m = m, x = s[1], y = s[2], w = s[3], t = s[4], ent = ent, spot = s, spots = spots }, { kind = "rare" })
				end
			end
		end
	end
	return out
end

-- Points near you for the minimap.
function S:NearbyPoints(yards, cap)
	local out = {}
	local function Consider(p, kind)
		local d = ns.Nav.Distance(p.m, p.x, p.y)
		if d and d <= yards then
			local pt = { kind = kind, dist = d }
			for k, v in pairs(p) do if pt[k] == nil then pt[k] = v end end
			table.insert(out, pt)
		end
	end
	for _, p in ipairs(self:Index().points) do
		Consider(p, p.mark and "mark" or "spot")
	end
	if Cfg().rares then
		for _, rec in pairs(Data().rares) do
			local ent = { kind = "rare", rec = rec, name = rec.n, refs = {} }
			for m, spots in pairs(rec.m or {}) do
				for _, s in ipairs(spots) do
					Consider({ m = m, x = s[1], y = s[2], w = s[3], t = s[4], ent = ent, spot = s, spots = spots }, "rare")
				end
			end
		end
	end
	table.sort(out, function(a, b) return a.dist < b.dist end)
	for i = #out, (cap or 60) + 1, -1 do out[i] = nil end
	return out
end

function S:Signature()
	local idx = self:Index()
	return S.version .. ":" .. #idx.points
end

---------------------------------------------------------------------------
-- Tooltips and menus for drawn points
---------------------------------------------------------------------------
function S:PointTitle(p)
	local ent = p.ent
	if not ent then return "?" end
	if ent.kind == "mark" then return self:MarkLabel(ent.rec) end
	return ent.name or "?"
end

function S:Tooltip(tt, p)
	local ent = p.ent
	if not ent then return end
	tt:AddLine(self:PointTitle(p), 1, 0.82, 0, true)
	if ent.kind == "mark" then
		tt:AddLine(ent.rec.by and ("Marked by " .. ent.rec.by) or "Your mark", 0.6, 0.8, 1)
	elseif ent.kind == "rare" then
		tt:AddLine(string.format("Rare or treasure, spotted %d %s, last %s ago", p.w or 1, (p.w or 1) == 1 and "time" or "times", Ago(p.t)), 1, 1, 1, true)
	end
	local idx = self:Index()
	for _, r in ipairs(ent.refs) do
		local q = idx.quests[r.q]
		if q then
			local o = r.i and q.open[r.i]
			local c = q.color
			tt:AddLine(q.e.title .. ((o and o.text) and (":  " .. o.text) or ""), c[1], c[2], c[3], true)
		end
	end
	if ent.kind == "npc" or ent.kind == "obj" then
		tt:AddLine(string.format("Seen here %d %s, last %s ago", p.w or 1, (p.w or 1) == 1 and "time" or "times", Ago(p.t)), 0.8, 0.8, 0.8)
	end
	local d = ns.Nav.Distance(p.m, p.x, p.y)
	if d then tt:AddLine(ns.Yards(d), 0.8, 0.8, 0.8) end
end

function S:SetWaypoint(p)
	ns.Nav:AddUser(p.m, p.x, p.y, self:PointTitle(p))
end

function S:PointMenu(owner, p)
	local title = self:PointTitle(p)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		-- No menu system: right-click forgets learned spots and removes marks.
		if p.mark then self:RemoveMark(p.mark) else self:ForgetSpot(p.spots, p.spot) end
		return
	end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(title)
		root:CreateButton("Set a waypoint here", function() S:SetWaypoint(p) end)
		if p.mark then
			root:CreateButton("Remove this mark", function() S:RemoveMark(p.mark) end)
		else
			root:CreateButton("Forget this spot", function() S:ForgetSpot(p.spots, p.spot) end)
			if p.ent and p.ent.name then
				root:CreateButton("Forget every spot for " .. p.ent.name, function() S:ForgetEntry(p.ent) end)
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Marking: Alt+right-click on the world map, /nq mark, /nq mapnote, or the key binding.
---------------------------------------------------------------------------
local function TargetNPC()
	if not UnitExists("target") or SafeCall(UnitIsPlayer, "target") ~= false then return nil end
	return ns.SafeName("target")
end

function S:OpenMarkMenu(m, x, y, owner)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		return self:AskName("spawn", m, x, y)
	end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(string.format("Mark %s %.1f, %.1f", ns.Nav.MapName(m), x * 100, y * 100))
		local target = TargetNPC()
		if target then
			root:CreateButton("Spawn: " .. target, function() S:AddMark(m, x, y, "spawn", target) end)
		end
		local objectives = root:CreateButton("Quest objective")
		local any = false
		for _, e in ipairs(ns.Quests.log) do
			if not e.complete and not e.failed then
				local questMenu
				for i, o in ipairs(C_QuestLog.GetQuestObjectives(e.questID) or {}) do
					local text = Clean(o.text)
					if not o.finished and text then
						questMenu = questMenu or objectives:CreateButton(e.title)
						local qid, index = e.questID, i
						questMenu:CreateButton(text, function()
							S:AddMark(m, x, y, "objective", S.ObjectiveName(text) or text, qid, index)
						end)
						any = true
					end
				end
			end
		end
		if not any then objectives:SetEnabled(false) end
		root:CreateButton("Mob spawn (type a name)...", function() S:AskName("spawn", m, x, y) end)
		root:CreateButton("Note...", function() S:AskName("note", m, x, y) end)
		local near = S:MarksNear(m, x, y, 25)
		if #near > 0 then
			root:CreateDivider()
			root:CreateButton(string.format("Remove %d %s here", #near, #near == 1 and "mark" or "marks"), function()
				for _, mk in ipairs(near) do S:RemoveMark(mk) end
			end)
		end
	end)
end

function S:AskName(kind, m, x, y)
	local f = self.dialog
	if not f then
		f = CreateFrame("Frame", "NeverQuestMarkDialog", UIParent, "BackdropTemplate")
		f:SetSize(330, 112)
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
		f:SetFrameStrata("DIALOG")
		ns.ApplyBackdrop(f, 0.97)
		table.insert(UISpecialFrames, "NeverQuestMarkDialog")
		f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		f.title:SetPoint("TOP", 0, -14)
		f.edit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
		f.edit:SetSize(270, 20)
		f.edit:SetPoint("TOP", 0, -42)
		f.edit:SetAutoFocus(false)
		f.edit:SetMaxLetters(60)
		local function Accept()
			local text = f.edit:GetText()
			if Clean(text) then S:AddMark(f.m, f.x, f.y, f.kind, text) end
			f:Hide()
		end
		f.ok = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		f.ok:SetSize(100, 22)
		f.ok:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 14)
		f.ok:SetText("Mark")
		f.ok:SetScript("OnClick", Accept)
		f.cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		f.cancel:SetSize(100, 22)
		f.cancel:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 14)
		f.cancel:SetText("Cancel")
		f.cancel:SetScript("OnClick", function() f:Hide() end)
		f.edit:SetScript("OnEnterPressed", Accept)
		f.edit:SetScript("OnEscapePressed", function() f:Hide() end)
		self.dialog = f
	end
	f.kind, f.m, f.x, f.y = kind, m, x, y
	f.title:SetText(kind == "spawn" and "Mob name for this spawn" or "Note for this spot")
	f.edit:SetText(kind == "spawn" and (TargetNPC() or "") or "")
	f:Show()
	f.edit:SetFocus()
	f.edit:HighlightText()
end

-- Marks where you stand: a name marks that mob's spawn, otherwise your target's, otherwise
-- the mark menu opens.
function S:MarkHere(text)
	local m, x, y = ns.Nav.GetPlayerPosition()
	if not m then
		ns.Print("your position isn't available here, so nothing can be marked.")
		return
	end
	text = Clean(text)
	if text then return self:AddMark(m, x, y, "spawn", text) end
	local target = TargetNPC()
	if target then return self:AddMark(m, x, y, "spawn", target) end
	self:OpenMarkMenu(m, x, y)
end

function S:NoteHere(text)
	local m, x, y = ns.Nav.GetPlayerPosition()
	if not m then
		ns.Print("your position isn't available here, so nothing can be marked.")
		return
	end
	if Clean(text) then
		self:AddMark(m, x, y, "note", text)
	else
		self:AskName("note", m, x, y)
	end
end

---------------------------------------------------------------------------
-- Party sharing: new spots and marks go to party members running NeverQuest.
-- Body after "P": fields joined by "^".
--   n^name^map^x^y^quest^objective        mob spot
--   o^quest^objective^map^x^y^text        objective spot
--   k^kind^label^map^x^y^quest^objective  mark
---------------------------------------------------------------------------
local tokens, lastRefill = 5, 0

local function Field(v)
	if type(v) == "number" then
		if v == floor(v) then return tostring(v) end
		return string.format("%.4f", v)
	end
	return Clean(tostring(v or "")) or ""
end

function S:Share(kind, ...)
	if not Cfg().share or not ns.Party or not ns.Party:IsActive() then return end
	local now = GetTime()
	tokens = min(5, tokens + (now - lastRefill) * 0.5)
	lastRefill = now
	if tokens < 1 then return end
	tokens = tokens - 1
	local parts = { kind }
	for i = 1, select("#", ...) do parts[#parts + 1] = Field((select(i, ...))) end
	ns.Party:SendRaw("P" .. table.concat(parts, "^"))
end

local function Split(text)
	local f = {}
	for part in (text .. "^"):gmatch("(.-)%^") do f[#f + 1] = part end
	return f
end

local function NonZero(v)
	v = tonumber(v)
	if v and v ~= 0 then return v end
end

function S:FromParty(sender, body)
	if not Cfg().share or type(body) ~= "string" then return end
	local f = Split(body)
	local kind = f[1]
	if kind == "n" then
		local m, x, y = tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
		if ValidPoint(m, x, y) then self:LearnNpc(f[2], m, x, y, 1, NonZero(f[6]), NonZero(f[7]), true) end
	elseif kind == "o" then
		local q, o, m, x, y = tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5]), tonumber(f[6])
		if q and o and ValidPoint(m, x, y) then self:LearnObjective(q, o, f[7], m, x, y, 1, true) end
	elseif kind == "k" then
		local m, x, y = tonumber(f[4]), tonumber(f[5]), tonumber(f[6])
		if ValidPoint(m, x, y) then
			self:AddMark(m, x, y, f[2], f[3] ~= "" and f[3] or nil, NonZero(f[7]), NonZero(f[8]), sender or "party")
		end
	end
end

---------------------------------------------------------------------------
-- Export / import: one text string with everything, for friends and guildmates.
-- QMS1~record~record...  with records like the party messages plus a count:
--   n^name^map^x^y^count^quest:objective,...
--   o^quest^objective^map^x^y^count^text
--   k^kind^label^map^x^y^quest^objective
--   r^name^atlas^map^x^y^count
---------------------------------------------------------------------------
function S:Export()
	local data = Data()
	local out = { "QMS1" }
	for _, rec in pairs(data.npcs) do
		local links = {}
		for q, i in pairs(rec.q or {}) do links[#links + 1] = q .. ":" .. (i or 0) end
		table.sort(links)
		local linkText = table.concat(links, ",")
		for m, spots in pairs(rec.m or {}) do
			for _, s in ipairs(spots) do
				out[#out + 1] = string.format("n^%s^%d^%.4f^%.4f^%d^%s", Field(rec.n), m, s[1], s[2], s[3], linkText)
			end
		end
		if not next(rec.m or {}) and linkText ~= "" then
			out[#out + 1] = string.format("n^%s^0^0^0^0^%s", Field(rec.n), linkText)
		end
	end
	for q, list in pairs(data.objs) do
		for i, rec in pairs(list) do
			for m, spots in pairs(rec.m or {}) do
				for _, s in ipairs(spots) do
					out[#out + 1] = string.format("o^%d^%d^%d^%.4f^%.4f^%d^%s", q, i, m, s[1], s[2], s[3], Field(rec.t))
				end
			end
		end
	end
	for _, mk in ipairs(data.marks) do
		out[#out + 1] = string.format("k^%s^%s^%d^%.4f^%.4f^%d^%d", mk.k, Field(mk.l), mk.m, mk.x, mk.y, mk.q or 0, mk.o or 0)
	end
	for _, rec in pairs(data.rares) do
		for m, spots in pairs(rec.m or {}) do
			for _, s in ipairs(spots) do
				out[#out + 1] = string.format("r^%s^%s^%d^%.4f^%.4f^%d", Field(rec.n), Field(rec.a), m, s[1], s[2], s[3])
			end
		end
	end
	return table.concat(out, "~"), #out - 1
end

function S:Import(text)
	if type(text) ~= "string" then return nil end
	text = text:gsub("[\r\n\t]", "")
	if text:sub(1, 4) ~= "QMS1" then
		ns.Print("that isn't NeverQuest spawn data (it starts with QMS1~).")
		return nil
	end
	local data = Data()
	local got = { spots = 0, marks = 0, rares = 0, skipped = 0 }
	local first = true
	for record in text:gmatch("[^~]+") do
		if first then
			first = false
		else
			local f = Split(record)
			local kind = f[1]
			local ok = false
			if kind == "n" then
				local name = Clean(f[2])
				local m, x, y, c = tonumber(f[3]), tonumber(f[4]), tonumber(f[5]), tonumber(f[6]) or 1
				if name then
					local key = Key(name)
					local rec = data.npcs[key] or { n = name, m = {} }
					data.npcs[key] = rec
					for q, i in (f[7] or ""):gmatch("(%d+):(%d+)") do
						rec.q = rec.q or {}
						q, i = tonumber(q), tonumber(i)
						if rec.q[q] == nil or (i > 0 and rec.q[q] == 0) then rec.q[q] = i end
					end
					if ValidPoint(m, x, y) then
						AddSpot(rec, m, x, y, math.max(1, min(c, MAX_COUNT)), MERGE_YARDS)
						got.spots = got.spots + 1
					end
					ok = true
				end
			elseif kind == "o" then
				local q, i, m, x, y, c = tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5]), tonumber(f[6]), tonumber(f[7]) or 1
				if q and i and ValidPoint(m, x, y) then
					data.objs[q] = data.objs[q] or {}
					local rec = data.objs[q][i] or { t = Clean(f[8]), m = {} }
					data.objs[q][i] = rec
					AddSpot(rec, m, x, y, math.max(1, min(c, MAX_COUNT)), MERGE_YARDS)
					got.spots = got.spots + 1
					ok = true
				end
			elseif kind == "k" then
				local m, x, y = tonumber(f[4]), tonumber(f[5]), tonumber(f[6])
				if ValidPoint(m, x, y) and self:AddMark(m, x, y, f[2], f[3] ~= "" and f[3] or nil, NonZero(f[7]), NonZero(f[8]), "import") then
					got.marks = got.marks + 1
					ok = true
				end
			elseif kind == "r" then
				local name = Clean(f[2])
				local m, x, y, c = tonumber(f[4]), tonumber(f[5]), tonumber(f[6]), tonumber(f[7]) or 1
				if name and ValidPoint(m, x, y) then
					local key = Key(name)
					local rec = data.rares[key] or { n = name, m = {} }
					data.rares[key] = rec
					if Clean(f[3]) then rec.a = Clean(f[3]) end
					AddSpot(rec, m, x, y, math.max(1, min(c, MAX_COUNT)), RARE_MERGE)
					got.rares = got.rares + 1
					ok = true
				end
			end
			if not ok then got.skipped = got.skipped + 1 end
		end
	end
	Changed()
	ns.Print(string.format("imported %d spots, %d marks and %d rares or treasures%s.", got.spots, got.marks, got.rares,
		got.skipped > 0 and (" (" .. got.skipped .. " lines skipped)") or ""))
	return got
end

---------------------------------------------------------------------------
-- Learning from quest progress
---------------------------------------------------------------------------
local snap = {}       -- [questID] = { [objective] = count }
local lastLoot        -- { m, x, y, source, items, t }

local function Here()
	if UnitOnTaxi and UnitOnTaxi("player") then return nil end
	if IsInInstance and IsInInstance() then return nil end
	return ns.Nav.GetPlayerPosition()
end

local function RecentLoot()
	if lastLoot and GetTime() - lastLoot.t <= LOOT_WINDOW then return lastLoot end
end

local function Progressed(e, i, o, counted)
	local m, x, y = Here()
	local name = S.ObjectiveName(o.text)
	if o.type == "monster" then
		-- One kill that counts for two quests is still one sighting.
		if name and counted[Key(name)] then return S:Link(name, e.questID, i) end
		if name then counted[Key(name)] = true end
		if name and m then S:LearnNpc(name, m, x, y, 1, e.questID, i) end
	elseif o.type == "item" then
		-- Items count only when they came out of a loot window just now; bags, mail and
		-- vendors don't tell us where anything spawns.
		local loot = RecentLoot()
		if not loot then return end
		if loot.source and counted[Key(loot.source)] then
			S:Link(loot.source, e.questID, i)
		elseif loot.source then
			counted[Key(loot.source)] = true
			S:LearnNpc(loot.source, loot.m, loot.x, loot.y, 1, e.questID, i)
		else
			S:LearnObjective(e.questID, i, name, loot.m, loot.x, loot.y, 1)
		end
	elseif m then
		S:LearnObjective(e.questID, i, name, m, x, y, 1)
	end
end

function S:ScanProgress()
	local learn = ns.ready and Cfg().learn
	local present, counted = {}, {}
	for _, e in ipairs(ns.Quests.log) do
		local qid = e.questID
		present[qid] = true
		local prev = snap[qid]
		local cur = {}
		for i, o in ipairs(C_QuestLog.GetQuestObjectives(qid) or {}) do
			local have = ns.Num(o.numFulfilled)
			local need = ns.Num(o.numRequired)
			if not need or need == 0 then have = o.finished and 1 or 0 end
			cur[i] = have or 0
			if learn and prev and prev[i] and cur[i] > prev[i] then
				ns.Call("Spawn learning", Progressed, e, i, o, counted)
			end
		end
		snap[qid] = cur
	end
	for qid in pairs(snap) do
		if not present[qid] then snap[qid] = nil end
	end
end

ns:RegisterMessage("QUESTS_UPDATED", function()
	S:Invalidate()
	S:ScanProgress()
end)

ns:RegisterEvent("LOOT_READY", function()
	if not Cfg().learn then return end
	local m, x, y = Here()
	if not m then return end
	local items, quest = {}, false
	for slot = 1, (GetNumLootItems and GetNumLootItems() or 0) do
		local _, item, _, _, _, _, isQuestItem, questID, isActive = GetLootSlotInfo(slot)
		local hidden = ns.IsSecret(isQuestItem) or ns.IsSecret(questID) or ns.IsSecret(isActive)
		-- Quest-starting items (a quest you don't have yet) aren't objectives.
		if not hidden and isQuestItem and not (questID and not isActive) then
			quest = true
			if Clean(item) then table.insert(items, Clean(item)) end
		end
	end
	if not quest then return end
	local source
	for _, unit in ipairs({ "target", "mouseover" }) do
		if UnitExists(unit) and SafeCall(UnitIsDead, unit) == true and SafeCall(UnitIsPlayer, unit) == false then
			source = ns.SafeName(unit)
			if source then break end
		end
	end
	lastLoot = { m = m, x = x, y = y, source = source, items = items, t = GetTime() }
	ns.Debug("spawns: quest loot from " .. (source or "an object") .. ": " .. table.concat(items, ", "))
end)

---------------------------------------------------------------------------
-- Learning from nearby quest mobs (nameplates, target, mouseover)
---------------------------------------------------------------------------
local plates = {}
local recentSight = {}
local tooltipChecked = {}

ns:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, unit) plates[unit] = true end)
ns:RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, unit) plates[unit] = nil end)
ns:RegisterEvent("QUEST_ACCEPTED", function() wipe(tooltipChecked) end)

-- The unit's tooltip lists the quests (and objectives) it counts for.
local function LinkFromTooltip(unit, name)
	if tooltipChecked[name] then return end
	tooltipChecked[name] = true
	local data = SafeCall(C_TooltipInfo and C_TooltipInfo.GetUnit, unit)
	if type(data) ~= "table" or type(data.lines) ~= "table" then return end
	local titles = {}
	for _, e in ipairs(ns.Quests.log) do titles[e.title] = e.questID end
	local quest
	for _, line in ipairs(data.lines) do
		local kind, text = line.type, line.leftText
		if not ns.IsSecret(kind) and type(text) == "string" and not ns.IsSecret(text) then
			if kind == LINE_QUEST_TITLE then
				quest = titles[text]
				if quest then S:Link(name, quest, nil) end
			elseif kind == LINE_QUEST_OBJECTIVE and quest then
				local want = S.ObjectiveName(text)
				for i, o in ipairs(C_QuestLog.GetQuestObjectives(quest) or {}) do
					local have = S.ObjectiveName(o.text)
					if want and have and want:lower() == have:lower() then
						S:Link(name, quest, i)
						break
					end
				end
			end
		end
	end
end

local function Close(unit)
	if InCombatLockdown() then return false end
	return SafeCall(CheckInteractDistance, unit, 4) == true
end

local function Sight(unit, m, x, y)
	if not UnitExists(unit) or SafeCall(UnitIsPlayer, unit) ~= false then return end
	if SafeCall(C_QuestLog.UnitIsRelatedToActiveQuest, unit) ~= true then return end
	local name = ns.SafeName(unit)
	if not name then return end
	LinkFromTooltip(unit, name)
	if not Close(unit) then return end
	local last = recentSight[name]
	if last and GetTime() - last.t < SIGHT_COOLDOWN and last.m == m
		and ns.Nav.DistanceBetween(m, last.x, last.y, m, x, y) < MERGE_YARDS then
		return
	end
	recentSight[name] = { m = m, x = x, y = y, t = GetTime() }
	S:LearnNpc(name, m, x, y, 1)
end

function S:ScanNearby()
	local cfg = Cfg()
	if not ns.ready or not cfg.learn or not cfg.nameplates then return end
	local m, x, y = Here()
	if not m then return end
	Sight("target", m, x, y)
	Sight("mouseover", m, x, y)
	local n = 0
	for unit in pairs(plates) do
		n = n + 1
		if n > 20 then break end
		Sight(unit, m, x, y)
	end
end

ns.Ticker(1.5, "Spawn sightings", function() S:ScanNearby() end)

---------------------------------------------------------------------------
-- Rares and treasures (the game's vignettes)
---------------------------------------------------------------------------
local seenVignette = {}

local function LearnVignette(guid)
	if not guid or ns.IsSecret(guid) or seenVignette[guid] then return end
	local info = C_VignetteInfo.GetVignetteInfo(guid)
	if type(info) ~= "table" or ns.IsSecret(info.onMinimap) or not info.onMinimap then return end
	local name = Clean(info.name)
	if not name then return end
	local m = C_Map.GetBestMapForUnit("player")
	if not m then return end
	local pos = C_VignetteInfo.GetVignettePosition(guid, m)
	if not pos then return end
	local x, y = pos:GetXY()
	x, y = ns.Num(x), ns.Num(y)
	if not x or not y or (x == 0 and y == 0) then return end
	seenVignette[guid] = true
	local atlas = info.atlasName
	if ns.IsSecret(atlas) or type(atlas) ~= "string" then atlas = nil end
	S:LearnRare(name, atlas, m, x, y, ns.Num(info.vignetteID))
end

function S:ScanVignettes()
	if not ns.ready or not Cfg().rares or not C_VignetteInfo then return end
	if IsInInstance and IsInInstance() then return end
	for _, guid in ipairs(C_VignetteInfo.GetVignettes() or {}) do
		pcall(LearnVignette, guid)
	end
end

ns:RegisterEvent("VIGNETTES_UPDATED", function()
	ns.Debounce("vignettes", 1, function() S:ScanVignettes() end)
end)
ns:RegisterEvent("VIGNETTE_MINIMAP_UPDATED", function(_, guid, onMinimap)
	if not ns.IsSecret(onMinimap) and onMinimap and ns.ready and Cfg().rares then pcall(LearnVignette, guid) end
end)
ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
	wipe(plates)
	ns.After(3, function() S:ScanVignettes() end)
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
-- 1.8.2: spawn dots moved off the minimap by default; turn them off for saved settings too.
ns:OnInit(function()
	local done = ns.db.migrated
	if not done.spawnsMinimapOff then
		done.spawnsMinimapOff = true
		ns.db.spawns.minimap = false
	end
end)

ns:AddSlash("mark", function(rest) S:MarkHere(rest) end,
	"/nq mark [mob name] - mark a mob spawn where you stand (your target, or the name you type)")
ns:AddSlash("mapnote", function(rest) S:NoteHere(rest) end,
	"/nq mapnote [text] - leave a note on the map where you stand")

ns:AddSlash("spawns", function(rest)
	local cmd, arg = (rest or ""):match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	if cmd == "export" then
		local text, count = S:Export()
		ns.UI:ShowIO("export", text, "Export spawns and marks", count .. " records. Press Ctrl+C to copy, then share the text.")
	elseif cmd == "import" then
		ns.UI:ShowIO("import", "", "Import spawns and marks", "Paste NeverQuest spawn data (starts with QMS1~) and click Import.",
			function(text) return S:Import(text) ~= nil end)
	elseif cmd == "clear" then
		local what = (arg ~= "" and arg:lower()) or ""
		if what == "learned" or what == "marks" or what == "rares" or what == "all" then
			S:Clear(what)
			ns.Print("cleared " .. what .. ".")
		else
			ns.Print("/nq spawns clear learned | marks | rares | all")
		end
	elseif cmd == "forget" then
		ns.Print(S:ForgetName(arg) and ("forgot every spot for " .. arg .. ".") or ("no spots known for " .. (arg ~= "" and arg or "that name") .. "."))
	elseif cmd == "all" then
		Cfg().showAll = not Cfg().showAll
		Changed()
		ns.Print(Cfg().showAll and "showing every known spawn." or "showing spawns for your quests only.")
	else
		ns.Print("spawn memory: " .. S:StatsText() .. ".")
		DEFAULT_CHAT_FRAME:AddMessage("   /nq spawns export | import | all | forget <mob> | clear learned|marks|rares|all")
		DEFAULT_CHAT_FRAME:AddMessage("   Alt+right-click the world map to mark a spot. Right-click a spot to forget it.")
	end
end, "/nq spawns - spawn memory: export, import, show all, forget or clear")
