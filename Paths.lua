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
--  * Only the route planner asks for a spot's distances (Want), nearest stops first, and no more
--    than KEEP at once: the Barrens has 60,000 cells, and 48 spots' worth was over 100 MB.
--    A spot over the limit is measured in a straight line, and stays that way: nothing is thrown
--    away to make room for it while the route still wants what's kept.

local ADDON, ns = ...
local P = {}
ns.Paths = P

local CELL = 100 / 3          -- yards a cell
local COST = { a = 1, b = 1.3, c = 1.6, d = 2, e = 3, f = 4, g = 8, h = 25, i = 40 }
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
-- Off unless switched on (guide.walk; 1.28.0 and 1.28.1 had it on for everyone under another name).
function P:On() return not self.paused and ns.db.guide.walk == true and ns.PathData ~= nil end

local function Zone(m)
	local z = zones[m]
	if z == nil then
		local d = ns.PathData and ns.PathData[m]
		if not d then zones[m] = false return false end
		z = { w = d.w, h = d.h, sx = d.yw / CELL, sy = d.yh / CELL, yw = d.yw, yh = d.yh, cost = {}, fields = {} }
		local i, cost = 0, z.cost
		for n, ch in d[1]:gmatch("(%d*)(%D)") do
			n = tonumber(n) or 1
			local c = COST[ch]
			if c then for k = i + 1, i + n do cost[k] = c end end
			i = i + n
		end
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
local function Step(z, f)
	local cost, dist, heap, n, w, h = z.cost, f.dist, f.heap, f.n, z.w, z.h
	local budget = SLICE
	while n > 0 and budget > 0 do
		local cell, d
		cell, d, n = Pop(heap, n)
		if d <= dist[cell] then
			budget = budget - 1
			local c = cost[cell]
			local x = (cell - 1) % w
			local y = (cell - 1 - x) / w
			for dy = -1, 1 do
				local ny = y + dy
				if ny >= 0 and ny < h then
					for dx = -1, 1 do
						local nx = x + dx
						if (dx ~= 0 or dy ~= 0) and nx >= 0 and nx < w then
							local nc = ny * w + nx + 1
							local k = cost[nc]
							-- (no cutting a corner past ground that isn't there)
							if k and (dx == 0 or dy == 0 or (cost[y * w + nx + 1] and cost[ny * w + x + 1])) then
								local nd = d + (c + k) / 2 * ((dx ~= 0 and dy ~= 0) and SQ2 or 1)
								if nd < dist[nc] then
									dist[nc] = nd
									n = Push(heap, n, nc, nd)
								end
							end
						end
					end
				end
			end
		end
	end
	f.n = n
	if n == 0 then f.done, f.heap = true, nil end
	return f.done
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
			if ns.Planner then ns.Planner.dirty = true end
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
	if not self:On() then return nil end
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

-- A straight walk between two cells that stays on ground no worse than `worst`.
local function Clear(z, x0, y0, x1, y1, worst)
	local n = math.max(math.abs(x1 - x0), math.abs(y1 - y0)) * 2
	for s = 1, n - 1 do
		local x, y = floor(x0 + (x1 - x0) * s / n + 0.5), floor(y0 + (y1 - y0) * s / n + 0.5)
		local c = z.cost[y * z.w + x + 1]
		if not c or c > worst then return false end
	end
	return true
end

-- The way to walk from the first spot to the second, as the corners between them on the zone's
-- map: { x, y, x, y, ... } (empty when it's a straight walk), or nil when it isn't known.
function P:Route(m, x1, y1, x2, y2)
	if not self:On() then return nil end
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
	-- Downhill on the distances, cell by cell.
	local w, h, dist = z.w, z.h, f.dist
	local xs, ys, worst = {}, {}, 0
	local cell = from
	for _ = 1, w * h do
		local x = (cell - 1) % w
		local y = (cell - 1 - x) / w
		xs[#xs + 1], ys[#ys + 1] = x, y
		worst = math.max(worst, z.cost[cell])
		if dist[cell] == 0 then break end
		local best, bestD = nil, dist[cell]
		for dy = -1, 1 do
			for dx = -1, 1 do
				local nx, ny = x + dx, y + dy
				if nx >= 0 and nx < w and ny >= 0 and ny < h then
					local nc = ny * w + nx + 1
					local d = dist[nc]
					if d and d < huge and d < bestD and (dx == 0 or dy == 0 or (z.cost[y * w + nx + 1] and z.cost[ny * w + x + 1])) then best, bestD = nc, d end
				end
			end
		end
		if not best then break end
		cell = best
	end
	-- Pulled tight: keep a corner only where a straight walk would cross worse ground.
	local keep, i, n = {}, 1, #xs
	while i < n do
		local j = n
		while j > i + 1 and not Clear(z, xs[i], ys[i], xs[j], ys[j], worst) do j = j - 1 end
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

ns:OnInit(function()
	ns.Ticker(0.02, "paths", function() P:Work() end)
end)

ns:AddSlash("paths", function(rest)
	rest = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if rest == "on" or rest == "off" then
		ns.db.guide.walk = rest == "on"
		if rest == "off" then P:Reset() end
		if ns.Planner then ns.Planner.dirty = true end
		ns:SendMessage("PATHS_READY")
		ns.Print("walking paths are " .. rest .. (rest == "off" and ": distances are straight lines again." or "."))
		return
	end
	local m = ns.Nav.GetPlayerPosition()
	local n = 0
	for _ in pairs(ns.PathData or {}) do n = n + 1 end
	ns.Print(string.format("walking paths are %s. %d zones have path data; this zone %s. /nq paths on|off.",
		P:On() and "on" or "off", n, (m and ns.PathData and ns.PathData[m]) and "does" or "doesn't"))
end, "/nq paths [on|off] - measure quest distances along walkable ground, not straight lines")
