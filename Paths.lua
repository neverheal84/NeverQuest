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

local ADDON, ns = ...
local P = {}
ns.Paths = P

local CELL = 100 / 3          -- yards a cell
local COST = { a = 1, b = 1.3, c = 1.6, d = 2, e = 3, f = 4, g = 8, h = 25, i = 40 }
local ROUGH = 25              -- cost from which a cell is no place to stand: spots snap off it
local SNAP = 3                -- cells a spot may be moved to reach standable ground
local SLICE = 2500            -- cells settled per slice of work
local KEEP = 48               -- spots' distances kept at once
local SQ2 = math.sqrt(2)
local floor, huge = math.floor, math.huge

local zones = {}              -- [uiMapID] = { w, h, cost = { [cell] = cost }, fields = { [cell] = field } } or false
local queue = {}              -- fields being worked out, oldest first
local stamp, count = 0, 0

-- paused: set by the test harness, whose older sections were written against straight lines.
function P:On() return not self.paused and ns.db.guide.paths ~= false and ns.PathData ~= nil end

local function Zone(m)
	local z = zones[m]
	if z == nil then
		local d = ns.PathData and ns.PathData[m]
		if not d then zones[m] = false return false end
		z = { w = d.w, h = d.h, sx = d.yw / CELL, sy = d.yh / CELL, cost = {}, fields = {} }
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
								if nd < (dist[nc] or huge) then
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
		return f
	end
	if not start then return nil end
	stamp = stamp + 1
	f = { dist = { [cell] = 0 }, heap = { cell, 0 }, n = 1, used = stamp, z = z, cell = cell }
	z.fields[cell] = f
	queue[#queue + 1] = f
	count = count + 1
	-- Too many kept: forget the one used longest ago.
	if count > KEEP then
		local old
		for _, zz in pairs(zones) do
			if zz then
				for _, g in pairs(zz.fields) do
					if g.done and (not old or g.used < old.used) then old = g end
				end
			end
		end
		if old then old.z.fields[old.cell] = nil count = count - 1 end
	end
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
-- Yards of walking between two spots on one zone's map (costly ground counting for more: deep
-- water twice, steep ground more), or nil when it isn't known (yet). The second spot is the one
-- whose distances get worked out and kept: make it the quest stop, not the player.
function P:Yards(m, x1, y1, x2, y2)
	if not self:On() then return nil end
	local z = Zone(m)
	if not z then return nil end
	local a, b = CellOf(z, x1, y1), CellOf(z, x2, y2)
	if not a or not b or a == b then return nil end
	local f = Field(z, b)
	local d = f and f.done and f.dist[a]
	if not d then
		local g = Field(z, a)
		d = g and g.done and g.dist[b]
		if not d and not f then Field(z, b, true) end
	end
	return d and d * CELL or nil
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
	if not (f and f.done and f.dist[a]) then
		f, from, back = Field(z, a), b, true
		if not (f and f.done and f.dist[b]) then return nil end
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
					if d and d < bestD and (dx == 0 or dy == 0 or (z.cost[y * w + nx + 1] and z.cost[ny * w + x + 1])) then best, bestD = nc, d end
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
function P:Reset() zones, queue, count = {}, {}, 0 end
function P:Has(m) return self:On() and Zone(m) and true or false end

ns:OnInit(function()
	ns.Ticker(0.02, "paths", function() P:Work() end)
end)

ns:AddSlash("paths", function(rest)
	rest = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if rest == "on" or rest == "off" then
		ns.db.guide.paths = rest == "on"
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
