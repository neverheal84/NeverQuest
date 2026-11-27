-- NeverQuest Paths: how far it really is to walk between two spots in a zone.
--
-- PathData.lua says, for every zone, what the ground is like in cells about 33 yards square: open,
-- steep, deep water, lava, a cliff. This measures the cheapest walk over those cells, so the route
-- planner knows that the quest across the ridge is a long way round and the one down the valley
-- isn't, and the map line can follow the way you'd actually go.
--
-- How: for a spot the route cares about (a quest stop), the cost of walking to it from every cell
-- of its zone is worked out once (Dijkstra's algorithm), a slice at a time so the game never
-- stutters, and kept. The distance between that spot and anywhere else, you included, is then a
-- lookup. Until a spot's distances are ready, and anywhere there's no data (cities, caves, between
-- zones), the answer is "don't know" and callers use the straight line as before.
--
-- 1.28.2, after the first try in the game sent people back and forth:
--  * A distance to where you stand is read between the cells around you, not from the one cell
--    you're in, so it changes smoothly as you walk instead of jumping 30 yards at every cell edge
--    (those jumps flipped the route's "is it close enough to do first" tests on and off).
--
-- 1.28.4, after a line drawn over the side of a mountain in the Wetlands:
--  * The data is now edges, not just cells: what the walk from each cell to each neighbour costs,
--    measured on the fine map. Two open cells with a ridge between them are no longer joined.
--  * Hillsides cost more than gentle ground, so the way goes by the valley when there is one.
--  * Drawing the route line along the walk (pins.pathLine, on) is separate from planning the
--    route by walking distance (guide.walk, off).
--
--  * Only the route planner and the map lines ask for a spot's distances (Want), nearest stops first, and no more
--    than KEEP at once: the Barrens has 60,000 cells, and 48 spots' worth was over 100 MB.
--    A spot over the limit is measured in a straight line, and stays that way: nothing is thrown
--    away to make room for it while the route still wants what's kept.

local ADDON, ns = ...
local P = {}
ns.Paths = P

local CELL = 100 / 3          -- yards a cell
local COST = { a = 1, b = 1.3, c = 1.6, d = 2, e = 3, f = 4, g = 8, h = 25, i = 40 }
local MAX_ZONES = 2           -- zones kept unpacked (the Barrens is 60,000 cells, five numbers each)
local ROUGH = 25              -- cost from which a cell is no place to stand: spots snap off it
local SNAP = 3                -- cells a spot may be moved to reach standable ground
local SLICE = 1500            -- cells settled per slice of work
local KEEP = 24               -- spots' distances kept at once (each is a number per cell of its zone)
local NEAR_CELLS = 2          -- closer than this many cells, a straight line is the better measure
local SQ2 = math.sqrt(2)
local floor, huge = math.floor, math.huge

local zones = {}              -- [uiMapID] = { w, h, cost = { [cell] = cost }, fields = { [cell] = field } } or false
local queue = {}              -- fields being worked out, oldest first
local stamp, count, round = 0, 0, 0

-- paused: set by the test harness, whose older sections were written against straight lines.
-- Two uses, two switches: the route planner measuring by the walk (guide.walk, off unless you
-- switch it on) and the map lines following it (pins.pathLine, on).
function P:Planning() return not self.paused and ns.db.guide.walk == true and ns.PathData ~= nil end
function P:Lines() return not self.paused and ns.db.pins.pathLine ~= false and ns.PathData ~= nil end
function P:On() return self:Planning() or self:Lines() end

-- A run-length coded string into an array: f(letter) for each cell (false where it gives nothing,
-- so the array stays a plain one).
local function Unpack(s, f)
	local out, i = {}, 0
	for n, ch in s:gmatch("(%d*)(%D)") do
		n = tonumber(n) or 1
		local v = f(ch) or false
		for k = i + 1, i + n do out[k] = v end
		i = i + n
	end
	return out
end
local EDGE = {}
for k = 0, 25 do EDGE[string.char(97 + k)] = 2 ^ ((k - 4) / 4) end
local function Cost(ch) return COST[ch] end
local function Edge(ch) return EDGE[ch] end

local function Zone(m)
	local z = zones[m]
	if z == nil then
		local d = ns.PathData and ns.PathData[m]
		if not d or not d[5] then zones[m] = false return false end
		-- Room for it: zones with nothing being kept for them are packed away again.
		local n = 0
		for _, zz in pairs(zones) do if zz then n = n + 1 end end
		if n >= MAX_ZONES then
			for id, zz in pairs(zones) do
				if zz and not next(zz.fields) then zones[id] = nil end
			end
		end
		z = { w = d.w, h = d.h, sx = d.yw / CELL, sy = d.yh / CELL, yw = d.yw, yh = d.yh, fields = {},
			cost = Unpack(d[1], Cost),
			e1 = Unpack(d[2], Edge), e2 = Unpack(d[3], Edge), e3 = Unpack(d[4], Edge), e4 = Unpack(d[5], Edge) }
		zones[m] = z
	end
	return z
end

-- The cell a spot stands in, moved to the nearest standable ground when it's on a cliff or off the map.
local function CellOf(z, x, y)
	if not x or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
	local w, h = z.w, z.h
	local cx, cy = floor(x * z.sx), floor(y * z.sy)
	if cx >= w then cx = w - 1 end
	if cy >= h then cy = h - 1 end
	local c = z.cost[cy * w + cx + 1]
	if c and c < ROUGH then return cy * w + cx + 1 end
	local best, bestD
	for dy = -SNAP, SNAP do
		for dx = -SNAP, SNAP do
			local nx, ny = cx + dx, cy + dy
			if nx >= 0 and nx < w and ny >= 0 and ny < h then
				local n = z.cost[ny * w + nx + 1]
				if n and n < ROUGH then
					local d = dx * dx + dy * dy
					if not bestD or d < bestD then best, bestD = ny * w + nx + 1, d end
				end
			end
		end
	end
	return best
end

---------------------------------------------------------------------------
-- A spot's distances: the cost of the cheapest walk from every cell to it
---------------------------------------------------------------------------
local function Push(heap, n, cell, d)
	n = n + 1
	local i = n
	while i > 1 do
		local p = floor(i / 2)
		if heap[p * 2] <= d then break end
		heap[i * 2 - 1], heap[i * 2] = heap[p * 2 - 1], heap[p * 2]
		i = p
	end
	heap[i * 2 - 1], heap[i * 2] = cell, d
	return n
end

local function Pop(heap, n)
	local cell, d = heap[1], heap[2]
	local lc, ld = heap[n * 2 - 1], heap[n * 2]
	n = n - 1
	local i = 1
	while true do
		local c = i * 2
		if c > n then break end
		if c < n and heap[c * 2 + 2] < heap[c * 2] then c = c + 1 end
		if heap[c * 2] >= ld then break end
		heap[i * 2 - 1], heap[i * 2] = heap[c * 2 - 1], heap[c * 2]
		i = c
	end
	heap[i * 2 - 1], heap[i * 2] = lc, ld
	return cell, d, n
end

-- One slice of a field's work. True when it's finished.
-- A cell's eight ways out: its own four edges (east, southeast, south, southwest) and the four
-- its neighbours hold to it. An edge off the side of the map was never written, so a plain lookup
-- is enough: no bounds to check.
local function Step(z, f)
	local dist, heap, n, w = f.dist, f.heap, f.n, z.w
	local e1, e2, e3, e4 = z.e1, z.e2, z.e3, z.e4
	local budget = SLICE
	while n > 0 and budget > 0 do
		local cell, d
		cell, d, n = Pop(heap, n)
		if d <= dist[cell] then
			budget = budget - 1
			local k, nc, nd
			k = e1[cell] if k then nc = cell + 1 nd = d + k if nd < dist[nc] then dist[nc] = nd n = Push(heap, n, nc, nd) end end
			k = e2[cell] if k then nc = cell + w + 1 nd = d + k if nd < dist[nc] then dist[nc] = nd n = Push(heap, n, nc, nd) end end
			k = e3[cell] if k then nc = cell + w nd = d + k if nd < dist[nc] then dist[nc] = nd n = Push(heap, n, nc, nd) end end
			k = e4[cell] if k then nc = cell + w - 1 nd = d + k if nd < dist[nc] then dist[nc] = nd n = Push(heap, n, nc, nd) end end
			nc = cell - 1 k = e1[nc] if k then nd = d + k if nd < dist[nc] then dist[nc] = nd n = Push(heap, n, nc, nd) end end
			nc = cell - w - 1 k = e2[nc] if k then nd = d + k if nd < dist[nc] then dist[nc] = nd n = Push(heap, n, nc, nd) end end
			nc = cell - w k = e3[nc] if k then nd = d + k if nd < dist[nc] then dist[nc] = nd n = Push(heap, n, nc, nd) end end
			nc = cell - w + 1 k = e4[nc] if k then nd = d + k if nd < dist[nc] then dist[nc] = nd n = Push(heap, n, nc, nd) end end
		end
	end
	f.n = n
	if n == 0 then f.done, f.heap = true, nil end
	return f.done
end

-- What the step between two neighbouring cells costs, or nil when there's no way.
local function StepCost(z, a, b)
	local d, w = b - a, z.w
	if d == 1 then return z.e1[a] or nil elseif d == -1 then return z.e1[b] or nil
	elseif d == w + 1 then return z.e2[a] or nil elseif d == -w - 1 then return z.e2[b] or nil
	elseif d == w then return z.e3[a] or nil elseif d == -w then return z.e3[b] or nil
	elseif d == w - 1 then return z.e4[a] or nil elseif d == -w + 1 then return z.e4[b] or nil end
	return nil
end

local function Field(z, cell, start)
	local f = z.fields[cell]
	if f then
		stamp = stamp + 1
		f.used = stamp
		if start then f.round = round end
		return f
	end
	if not start then return nil end
	-- Full: make room by forgetting a spot the route no longer asks for (the one asked for
	-- longest ago). When it still wants them all, this one goes without.
	if count >= KEEP then
		local old
		for _, zz in pairs(zones) do
			if zz then
				for _, g in pairs(zz.fields) do
					if g.round < round and (not old or g.round < old.round or (g.round == old.round and g.used < old.used)) then old = g end
				end
			end
		end
		if not old then return nil end
		old.z.fields[old.cell] = nil
		count = count - 1
		for i, g in ipairs(queue) do if g == old then table.remove(queue, i) break end end
	end
	stamp = stamp + 1
	-- (every cell filled in, so the distances sit in one plain array: a third of the memory)
	local dist = {}
	for i = 1, z.w * z.h do dist[i] = huge end
	dist[cell] = 0
	f = { dist = dist, heap = { cell, 0 }, n = 1, used = stamp, round = round, z = z, cell = cell }
	z.fields[cell] = f
	queue[#queue + 1] = f
	count = count + 1
	return f
end

-- Does a slice of the oldest unfinished field. True while there's more to do.
function P:Work()
	local f = queue[1]
	if not f then return false end
	if Step(f.z, f) then
		table.remove(queue, 1)
		if #queue == 0 then
			-- What the route was guessing at, it now knows.
			if ns.Planner and P:Planning() then ns.Planner.dirty = true end
			ns:SendMessage("PATHS_READY")
		end
	end
	return #queue > 0
end

function P:Finish() while self:Work() do end end
function P:Busy() return #queue > 0 end

---------------------------------------------------------------------------
-- What callers ask
---------------------------------------------------------------------------
-- A spot's distance read between the cells around a point, so it changes smoothly as the point
-- moves (the point is you, walking). nil when none of the cells around it can be walked.
local REACH = 3                -- cells of walking: a neighbour further off than this by foot is across a cliff, not beside you
local function Between(z, dist, x, y)
	local w, h = z.w, z.h
	local own = CellOf(z, x, y)
	local base = own and dist[own]
	if not base or base >= huge then return nil end
	local fx, fy = x * z.sx - 0.5, y * z.sy - 0.5
	local x0, y0 = floor(fx), floor(fy)
	local tx, ty = fx - x0, fy - y0
	local sum, wsum = 0, 0
	for j = 0, 1 do
		local cy = y0 + j
		if cy >= 0 and cy < h then
			for i = 0, 1 do
				local cx = x0 + i
				if cx >= 0 and cx < w then
					local d = dist[cy * w + cx + 1]
					if d and d - base <= REACH and base - d <= REACH then
						local k = (i == 0 and 1 - tx or tx) * (j == 0 and 1 - ty or ty)
						sum, wsum = sum + d * k, wsum + k
					end
				end
			end
		end
	end
	if wsum < 0.05 then return base end
	return sum / wsum
end

-- The route planner says which spots it cares about: Begin, then Want for each stop, nearest
-- first. Want is true when that spot's distances are ready, false when they're being worked out
-- (or there's no room for them), nil where there's no data.
function P:Begin() round = round + 1 end
function P:Want(m, x, y)
	if not self:On() then return nil end
	local z = Zone(m)
	if not z then return nil end
	local c = CellOf(z, x, y)
	if not c then return nil end
	local f = Field(z, c, true)
	return f and f.done or false
end

-- Yards of walking from a point to a spot on one zone's map (costly ground counting for more:
-- deep water twice, steep ground more), or nil when it isn't known. The second one is the spot
-- whose distances are used (a quest stop the planner has asked for with Want); the first can be
-- anywhere, you included. Two spots very close together: nil, a straight line says it better.
function P:Yards(m, x1, y1, x2, y2)
	if not self:Planning() then return nil end
	local z = Zone(m)
	if not z then return nil end
	if not x1 or not x2 then return nil end
	local dx, dy = (x1 - x2) * z.sx, (y1 - y2) * z.sy
	local n = math.sqrt(dx * dx + dy * dy)
	if n < NEAR_CELLS then return nil end
	-- The walk is measured to the middle of the spot's cell. What's handed back is the straight
	-- line between the two real points, stretched by how much longer the walk is than the
	-- straight line to that middle: two NPCs in one cell keep their own distances, and nothing
	-- jumps as either point moves.
	local b = CellOf(z, x2, y2)
	local f = b and Field(z, b)
	local d, qx, qy, cell
	if f and f.done then
		d, qx, qy, cell = Between(z, f.dist, x1, y1), x1, y1, b
	else
		local a = CellOf(z, x1, y1)
		local g = a and Field(z, a)
		if g and g.done then d, qx, qy, cell = Between(z, g.dist, x2, y2), x2, y2, a end
	end
	if not d or d >= huge then return nil end
	local cx, cy = (cell - 1) % z.w, floor((cell - 1) / z.w)
	local ex, ey = qx * z.sx - (cx + 0.5), qy * z.sy - (cy + 0.5)
	local straight = math.sqrt(ex * ex + ey * ey)
	local r = straight > 0.5 and d / straight or 1
	if r < 1 then r = 1 end
	-- Close by, the cells are too coarse to say much: ease in between two and four cells.
	if n < NEAR_CELLS * 2 then r = 1 + (r - 1) * (n - NEAR_CELLS) / NEAR_CELLS end
	return n * r * CELL
end

-- What walking straight from one cell to another costs, cell by cell, or nil when the straight
-- line has no way through.
local function Straight(z, x0, y0, x1, y1)
	local n = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
	local sum, at = 0, y0 * z.w + x0 + 1
	for s = 1, n do
		local x, y = floor(x0 + (x1 - x0) * s / n + 0.5), floor(y0 + (y1 - y0) * s / n + 0.5)
		local to = y * z.w + x + 1
		if to ~= at then
			local k = StepCost(z, at, to)
			if not k then return nil end
			sum, at = sum + k, to
		end
	end
	return sum
end

-- The way to walk from the first spot to the second, as the corners between them on the zone's
-- map: { x, y, x, y, ... } (empty when it's a straight walk), or nil when it isn't known.
function P:Route(m, x1, y1, x2, y2)
	if not self:Lines() then return nil end
	local z = Zone(m)
	if not z then return nil end
	local a, b = CellOf(z, x1, y1), CellOf(z, x2, y2)
	if not a or not b then return nil end
	if a == b then return {} end
	local f, from, back = Field(z, b), a, false
	if not (f and f.done and f.dist[a] < huge) then
		f, from, back = Field(z, a), b, true
		if not (f and f.done and f.dist[b] < huge) then return nil end
	end
	-- Downhill on the distances, cell by cell, along the edges.
	local w, h, dist = z.w, z.h, f.dist
	local xs, ys, ds = {}, {}, {}
	local cell = from
	for _ = 1, w * h do
		local x = (cell - 1) % w
		xs[#xs + 1], ys[#ys + 1], ds[#ds + 1] = x, (cell - 1 - x) / w, dist[cell]
		if dist[cell] == 0 then break end
		local best, bestD = nil, dist[cell]
		for dy = -1, 1 do
			for dx = -1, 1 do
				local nx = x + dx
				if (dx ~= 0 or dy ~= 0) and nx >= 0 and nx < w then
					local nc = cell + dy * w + dx
					local d = nc >= 1 and dist[nc]
					if d and d < bestD and StepCost(z, cell, nc) then best, bestD = nc, d end
				end
			end
		end
		if not best then break end
		cell = best
	end
	-- Pulled tight: a corner goes when walking straight past it costs no more than going by it.
	local keep, i, n = {}, 1, #xs
	while i < n do
		local j = n
		while j > i + 1 do
			local s = Straight(z, xs[i], ys[i], xs[j], ys[j])
			if s and s <= (ds[i] - ds[j]) * 1.02 + 0.01 then break end
			j = j - 1
		end
		if j < n then keep[#keep + 1] = j end
		i = j
	end
	local out = {}
	for k = 1, #keep do
		local q = back and keep[#keep + 1 - k] or keep[k]
		out[#out + 1] = (xs[q] + 0.5) / z.sx
		out[#out + 1] = (ys[q] + 0.5) / z.sy
	end
	return out
end

-- (for the offline tools: the cell a spot stands in)
function P:CellOf(m, x, y) local z = Zone(m) return z and CellOf(z, x, y) or nil end
function P:Reset() zones, queue, count, round = {}, {}, 0, 0 end
function P:Count() return count end
function P:Has(m) return self:On() and Zone(m) and true or false end
-- (for the tests: what walking dead straight between two spots would cost, and what the way costs,
-- both in cells of open ground; nil where there's no way or it isn't known)
function P:Compare(m, x1, y1, x2, y2)
	local z = Zone(m)
	local a, b = z and CellOf(z, x1, y1), z and CellOf(z, x2, y2)
	if not a or not b then return nil end
	local f = Field(z, b)
	local w = z.w
	return Straight(z, (a - 1) % w, floor((a - 1) / w), (b - 1) % w, floor((b - 1) / w)), f and f.done and f.dist[a] < huge and f.dist[a] or nil
end
-- (for the tests: what the ground costs where you'd stand in the cell at a point; nil for no ground)
function P:CostAt(m, x, y)
	local z = Zone(m)
	if not z or x < 0 or x >= 1 or y < 0 or y >= 1 then return nil end
	return z.cost[floor(y * z.sy) * z.w + floor(x * z.sx) + 1] or nil
end

ns:OnInit(function()
	ns.Ticker(0.02, "paths", function() P:Work() end)
end)

ns:AddSlash("paths", function(rest)
	rest = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if rest == "on" or rest == "off" then
		ns.db.guide.walk = rest == "on"
		if rest == "off" and not P:Lines() then P:Reset() end
		if ns.Planner then ns.Planner.dirty = true end
		ns:SendMessage("PATHS_READY")
		ns.Print("planning the route by walking distance is " .. rest .. (rest == "off" and ": it measures in straight lines." or "."))
		return
	elseif rest == "line" then
		ns.db.pins.pathLine = not P:Lines()
		if not P:On() then P:Reset() end
		ns:SendMessage("PATHS_READY")
		ns.Print("route lines " .. (ns.db.pins.pathLine and "follow the walkable way." or "are straight."))
		return
	end
	local m = ns.Nav.GetPlayerPosition()
	local n = 0
	for _ in pairs(ns.PathData or {}) do n = n + 1 end
	ns.Print(string.format("route lines %s (/nq paths line). Planning by walking distance is %s (/nq paths on|off). %d zones have path data; this zone %s.",
		P:Lines() and "follow the walkable way" or "are straight", P:Planning() and "on" or "off", n, (m and ns.PathData and ns.PathData[m]) and "does" or "doesn't"))
end, "/nq paths [line|on|off] - route lines along walkable ground; plan the route by walking distance")
