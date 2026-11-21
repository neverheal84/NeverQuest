-- NeverQuest Route: follows the paths a target actually needs (cave and building entrances,
-- tunnels, zone exits, flights) instead of a straight line.
--
-- For the active target, the next "leg" comes from, in order:
--   1. a flight plan, when flying between discovered flight masters is clearly faster
--   2. the game's own route: quest waypoints for quests, or the route Blizzard computes for
--      the tracked map pin (NeverQuest places that pin for non-quest targets)
--   3. a map link (cave, building or zone entrance) leading to the target's map
-- With no leg, the arrow points straight at the target.

local ADDON, ns = ...
local R = {}
ns.Route = R

local FLY_SPEED = 30          -- yards per second on a flight path, roughly
local FLY_OVERHEAD = 25       -- seconds to talk to the flight master, take off and land
local MIN_FLIGHT_TRIP = 1200  -- straight-line yards before flights are considered
local SAME_SPOT = 8           -- a "waypoint" this close to the target is the target itself

R.speed = 7                   -- best ground speed seen this session (yards per second)

local function Num(v) return ns.Num(v) end
local function Text(v)
	if type(v) ~= "string" or ns.IsSecret(v) or v == "" then return nil end
	return v
end

---------------------------------------------------------------------------
-- Game routes
---------------------------------------------------------------------------
-- Next waypoint the game has for a quest (cave entrance, tunnel, zone exit, boat...).
function R.QuestLeg(questID)
	if not questID or not ns.db.nav.paths then return nil end
	local m, x, y = C_QuestLog.GetNextWaypoint(questID)
	x, y = Num(x), Num(y)
	if not m or not x or not y then return nil end
	return { m = m, x = x, y = y, text = Text(C_QuestLog.GetNextWaypointText(questID)), kind = "path" }
end

-- Next waypoint of the route Blizzard computes for the tracked map pin. Only meaningful while
-- the tracked pin is the one NeverQuest placed for this target.
function R.NativeLeg()
	if not ns.db.nav.paths or not ns.Nav.ownsUserWaypoint or not C_SuperTrack.IsSuperTrackingUserWaypoint() then return nil end
	local pm = C_Map.GetBestMapForUnit("player")
	if not pm then return nil end
	for _, m in ipairs({ pm, ns.Nav.GetZoneMap(pm) }) do
		local x, y, text = C_Navigation.GetNextWaypointForMap(m)
		x, y = Num(x), Num(y)
		if x and y then return { m = m, x = x, y = y, text = Text(text), kind = "path" } end
	end
end

-- Map links (entrances to caves, buildings and neighbouring maps) that lead toward the target's map.
function R.LinkLeg(tm)
	if not ns.db.nav.paths or not tm then return nil end
	local pm = C_Map.GetBestMapForUnit("player")
	if not pm or pm == tm then return nil end
	local wanted, id, guard = {}, tm, 0
	while id and id > 0 and guard < 6 do
		wanted[id] = true
		local info = C_Map.GetMapInfo(id)
		id, guard = info and info.parentMapID, guard + 1
	end
	local searched = {}
	for _, m in ipairs({ pm, ns.Nav.GetZoneMap(pm) }) do
		if not searched[m] then
			searched[m] = true
			for _, link in ipairs(C_Map.GetMapLinksForMap(m) or {}) do
				if link.linkedUiMapID and wanted[link.linkedUiMapID] and link.linkedUiMapID ~= m and link.position then
					local x, y = link.position:GetXY()
					if Num(x) and Num(y) then
						return { m = m, x = x, y = y, text = "Go to " .. (Text(link.name) or ns.Nav.MapName(link.linkedUiMapID)), kind = "link" }
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Flight paths
---------------------------------------------------------------------------
local nodeCache = {}

-- Flight masters this character has discovered and may use, in continent map coordinates.
function R.KnownNodes(continentMap)
	local cached = nodeCache[continentMap]
	if cached and GetTime() - cached.t < 30 then return cached.nodes end
	local nodes = {}
	local faction = UnitFactionGroup("player")
	local F = Enum.FlightPathFaction
	for _, info in ipairs(C_TaxiMap.GetTaxiNodesForMap(continentMap) or {}) do
		local ok = not info.isUndiscovered
		if ok and F and info.faction == F.Horde then ok = faction == "Horde" end
		if ok and F and info.faction == F.Alliance then ok = faction == "Alliance" end
		if ok and info.position then
			local x, y = info.position:GetXY()
			if Num(x) and Num(y) then
				table.insert(nodes, { id = info.nodeID, name = Text(info.name) or "flight master", m = continentMap, x = x, y = y })
			end
		end
	end
	nodeCache[continentMap] = { t = GetTime(), nodes = nodes }
	return nodes
end

local function Nearest(nodes, m, x, y)
	local best, bestD
	for _, n in ipairs(nodes) do
		local d = ns.Nav.DistanceBetween(m, x, y, n.m, n.x, n.y)
		if d < math.huge and (not bestD or d < bestD) then best, bestD = n, d end
	end
	return best, bestD
end

-- Returns a flight plan for reaching the target, or nil when walking/riding is as good.
function R.PlanFlight(t)
	if not ns.db.nav.flights then return nil end
	local pm, px, py = ns.Nav.GetPlayerPosition()
	if not pm then return nil end
	local cont = ns.Nav.GetContinentMap(pm)
	if not cont or cont ~= ns.Nav.GetContinentMap(t.m) then return nil end
	local direct = ns.Nav.DistanceBetween(pm, px, py, t.m, t.x, t.y)
	if direct == math.huge or direct < MIN_FLIGHT_TRIP then return nil end
	local nodes = R.KnownNodes(cont)
	if #nodes < 2 then return nil end
	local from, toFrom = Nearest(nodes, pm, px, py)
	local to, toTarget = Nearest(nodes, t.m, t.x, t.y)
	if not from or not to or from.id == to.id then return nil end
	local hop = ns.Nav.DistanceBetween(from.m, from.x, from.y, to.m, to.x, to.y)
	local speed = math.max(7, R.speed)
	local walkTime = direct / speed
	local flyTime = toFrom / speed + FLY_OVERHEAD + hop / FLY_SPEED + toTarget / speed
	if flyTime < walkTime * 0.75 and walkTime - flyTime > 30 then
		return { from = from, to = to, saves = walkTime - flyTime }
	end
end

---------------------------------------------------------------------------
-- Next leg for the active target
---------------------------------------------------------------------------
local function TargetKey(t)
	return t and (t.key or string.format("%d:%.4f:%.4f", t.m or 0, t.x or 0, t.y or 0)) or nil
end

-- Flight plans stick to a target once chosen, until you land or get close enough to go direct.
function R:FlightFor(t)
	local key = TargetKey(t)
	local f = self.flight
	if f and f.key ~= key then f, self.flight = nil, nil end
	if f then
		if f.landed then return nil end
		local d = ns.Nav.Distance(t.m, t.x, t.y)
		if d and d < MIN_FLIGHT_TRIP * 0.6 then
			self.flight = { key = key, landed = true }
			return nil
		end
		return f
	end
	if self.plannedFor == key and GetTime() - (self.plannedAt or 0) < 15 then return nil end
	self.plannedFor, self.plannedAt = key, GetTime()
	local plan = R.PlanFlight(t)
	if plan then
		plan.key = key
		self.flight = plan
	end
	return plan
end

local function SameSpot(a, b)
	return ns.Nav.DistanceBetween(a.m, a.x, a.y, b.m, b.x, b.y) <= SAME_SPOT
end

function R:Compute(t)
	if not t or not t.m then return nil end
	if UnitOnTaxi("player") then
		local f = self.flight
		local text = (f and f.to) and ("Flying to " .. f.to.name) or "In flight"
		local left = self:FlightLeft()
		if left then text = text .. "  ~" .. ns.Duration(left) .. " left" end
		return { inFlight = true, text = text, left = left }
	end
	-- Ghosts can't take flights or follow quest routes: only cave and building entrances help.
	if t.src == "corpse" then return R.LinkLeg(t.m) end
	local f = self:FlightFor(t)
	if f and f.from then
		return { m = f.from.m, x = f.from.x, y = f.from.y, kind = "flight", node = f.from, dest = f.to,
			text = string.format("Fly from %s to %s", f.from.name, f.to.name) }
	end
	local leg
	if t.questID and C_QuestLog.IsOnQuest(t.questID) then
		leg = R.QuestLeg(t.questID)
	else
		leg = R.NativeLeg()
	end
	-- A waypoint at the target itself still carries useful directions ("Take the tunnel...").
	if leg and (not SameSpot(leg, t) or leg.text) then return leg end
	return R.LinkLeg(t.m)
end

-- Cached for half a second; events that change routes clear the cache.
function R:Leg(t)
	local key = TargetKey(t)
	local now = GetTime()
	if self.cache and self.cache.key == key and now - self.cache.t < 0.5 then return self.cache.leg end
	local leg = self:Compute(t)
	local legKey = leg and (leg.inFlight and "flight" or string.format("%s:%d:%.3f:%.3f", leg.kind or "", leg.m or 0, leg.x or 0, leg.y or 0)) or "none"
	self.cache = { key = key, t = now, leg = leg }
	if legKey ~= self.lastLegKey then
		self.lastLegKey = legKey
		ns.Debug("route: " .. (leg and (leg.text or leg.kind or "next waypoint") or "straight to target"))
		ns:SendMessage("ROUTE_CHANGED", leg)
	end
	return leg
end

function R:Invalidate()
	self.cache = nil
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
for _, event in ipairs({ "SUPER_TRACKING_PATH_UPDATED", "SUPER_TRACKING_CHANGED", "WAYPOINT_UPDATE", "QUEST_POI_UPDATE",
	"ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_CONTROL_GAINED", "PLAYER_CONTROL_LOST" }) do
	ns:RegisterEvent(event, function() R:Invalidate() end)
end

ns:RegisterEvent("TAXI_NODE_STATUS_CHANGED", function() wipe(nodeCache) R:Invalidate() end)

-- How long each flight takes isn't something the game tells an addon, so it's timed: the first
-- time you fly a planned leg it's measured, and from then on the arrow counts it down.
local function FlightKey(f)
	return (f and f.from and f.to and f.from.name and f.to.name) and (f.from.name .. ">" .. f.to.name) or nil
end

function R:FlightLeft()
	local t = self.airborne
	if not t then return nil end
	local known = ns.db.flightTimes[t.key]
	if not known then return nil end
	return math.max(0, known - (GetTime() - t.start))
end

ns:RegisterEvent("PLAYER_CONTROL_LOST", function()
	ns.After(0.5, function()
		local f = R.flight
		local key = FlightKey(f)
		if key and not f.landed and UnitOnTaxi("player") then
			R.airborne = { key = key, start = GetTime() }
		end
	end)
end)

-- Landing ends the flight leg; the next leg (or the target itself) takes over.
ns:RegisterEvent("PLAYER_CONTROL_GAINED", function()
	ns.After(1, function()
		local f = R.flight
		local air = R.airborne
		R.airborne = nil
		if f and not f.landed and not UnitOnTaxi("player") and f.to then
			local d = ns.Nav.Distance(f.to.m, f.to.x, f.to.y)
			if d and d < 250 and air and air.key == FlightKey(f) then
				-- Landed where the plan said: that's a clean timing (the 1s is this handler's own delay).
				local took = math.floor(GetTime() - air.start - 1 + 0.5)
				if took >= 10 and took <= 1500 then ns.db.flightTimes[air.key] = took end
			end
			if d and d < 250 then
				R.flight = { key = f.key, landed = true }
				R:Invalidate()
			end
		end
	end)
end)

-- At the flight master, remind which flight to take.
ns:RegisterEvent("TAXIMAP_OPENED", function()
	wipe(nodeCache)
	local f = R.flight
	if f and f.to and not f.landed then
		ns.Alert("Fly to " .. f.to.name, 0.4, 0.8, 1)
	end
end)

-- Remember the fastest ground speed seen (mounted speed once you have a mount).
ns.Ticker(2, "Route speed", function()
	if not ns.ready or UnitOnTaxi("player") then return end
	local _, runSpeed = GetUnitSpeed("player")
	runSpeed = Num(runSpeed)
	if runSpeed and runSpeed > R.speed and runSpeed < 40 then R.speed = runSpeed end
end)
