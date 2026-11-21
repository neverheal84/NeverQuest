-- NeverQuest Travel: flight paths you haven't picked up yet, and your hearthstone.
--
-- Flight paths come from the game's own flight map data for the zone you're in (the same list
-- the world map draws). Your hearthstone spot is noted where you stand when you bind it.

local ADDON, ns = ...
local T = {}
ns.Travel = T

local HEARTHSTONE = 6948
local NEAR_TURNIN = 400     -- yards: a turn-in this close to your hearth spot counts as "there"

local function Cfg() return ns.db.travel end

---------------------------------------------------------------------------
-- Flight paths
---------------------------------------------------------------------------
local taxiCache = {}
function T:MissingFlightPaths(zoneMap)
	zoneMap = zoneMap or ns.Quests.offerMap
	if not zoneMap or not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return {} end
	local cached = taxiCache[zoneMap]
	if cached and GetTime() - cached.t < 10 then
		for _, fp in ipairs(cached.list) do fp.dist = ns.Nav.Distance(fp.m, fp.x, fp.y) end
		table.sort(cached.list, function(a, b) return (a.dist or 1e9) < (b.dist or 1e9) end)
		return cached.list
	end
	local out = {}
	local faction = UnitFactionGroup("player")
	local F = Enum.FlightPathFaction
	for _, info in ipairs(ns.SafeCall(C_TaxiMap.GetTaxiNodesForMap, zoneMap) or {}) do
		local ok = info.isUndiscovered == true
		if ok and F and info.faction == F.Horde then ok = faction == "Horde" end
		if ok and F and info.faction == F.Alliance then ok = faction == "Alliance" end
		if ok and info.position then
			local x, y = info.position:GetXY()
			x, y = ns.Num(x), ns.Num(y)
			if x and y and x > 0 and x < 1 and y > 0 and y < 1 then
				local name = type(info.name) == "string" and not ns.IsSecret(info.name) and info.name or "Flight master"
				table.insert(out, { id = info.nodeID, name = name, m = zoneMap, x = x, y = y, dist = ns.Nav.Distance(zoneMap, x, y) })
			end
		end
	end
	table.sort(out, function(a, b) return (a.dist or 1e9) < (b.dist or 1e9) end)
	taxiCache[zoneMap] = { t = GetTime(), list = out }
	return out
end

-- A new flight path learned: look again.
function T:ForgetFlightPaths() wipe(taxiCache) end
ns:RegisterEvent("TAXIMAP_OPENED", function() wipe(taxiCache) end)
ns:RegisterEvent("UI_INFO_MESSAGE", function(_, _, msg)
	-- "New flight path discovered!": drop the step right away.
	if msg ~= nil and msg == ERR_NEWTAXIPATH then
		wipe(taxiCache)
		ns.Debounce("travel:fp", 0.5, function() if ns.Guide then ns.Guide:Refresh() end end)
	end
end)

function T:FlightStep()
	if not Cfg().flightPaths or UnitLevel("player") < 5 or UnitOnTaxi("player") then return nil end
	local fp = self:MissingFlightPaths()[1]
	if not fp then return nil end
	return { kind = "tip", icon = "FlightMaster", key = "fp:" .. (fp.id or fp.name), m = fp.m, x = fp.x, y = fp.y,
		title = "Get the flight path: " .. fp.name:gsub(",.*$", ""),
		sub = "Talk to the flight master once and you can fly here from now on. Click to point the arrow.",
		right = fp.dist and ns.Yards(fp.dist) or "", color = { 0.55, 0.85, 1 }, near = fp.dist and fp.dist < 400,
		later = not (fp.dist and fp.dist < 400) }   -- far ones stay off the route line until you choose them
end

---------------------------------------------------------------------------
-- Hearthstone
---------------------------------------------------------------------------
function T:BindName()
	local n = GetBindLocation and ns.SafeCall(GetBindLocation)
	return type(n) == "string" and not ns.IsSecret(n) and n ~= "" and n or nil
end

-- The spot you bound at, if we saw it happen and it still matches the game's bind name.
function T:HearthSpot()
	local h = ns.char.hearth
	local name = self:BindName()
	if h and h.m and (not name or h.name == name) then return h end
	return nil
end

function T:HasHearthstone()
	return (ns.Num(ns.SafeCall(C_Item.GetItemCount, HEARTHSTONE)) or 0) > 0
end

-- Seconds until it's ready (0 when ready), or nil without one.
function T:HearthCooldown()
	if not self:HasHearthstone() then return nil end
	local fn = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
	if not fn then return 0 end
	local ok, start, duration = pcall(fn, HEARTHSTONE)
	start, duration = ok and ns.Num(start) or 0, ok and ns.Num(duration) or 0
	if start <= 0 or duration <= 0 then return 0 end
	return math.max(0, start + duration - GetTime())
end

-- Finished quests handed in near your hearth spot, when hearthing beats the trip there.
function T:HearthPlan()
	local cfg = Cfg()
	if not cfg.hearth then return nil end
	local h = self:HearthSpot()
	if not h then return nil end
	local cd = self:HearthCooldown()
	if not cd or cd > 0 then return nil end
	local away = ns.Nav.Distance(h.m, h.x, h.y)
	local pm = ns.Nav.GetPlayerPosition()
	local otherContinent = pm and ns.Nav.GetContinentMap(pm) ~= ns.Nav.GetContinentMap(h.m)
	if not otherContinent and (not away or away < (cfg.hearthMinYards or 1500)) then return nil end
	local there = {}
	for _, e in ipairs(ns.Quests.log) do
		if e.complete then
			local spot = ns.Quests:TurnInSpot(e.questID)
			if spot and spot.m and spot.source ~= "zone" and spot.source ~= "unknown" then
				local d = ns.Nav.DistanceBetween(h.m, h.x, h.y, spot.m, spot.x, spot.y)
				if d and d < NEAR_TURNIN then table.insert(there, e) end
			end
		end
	end
	if #there == 0 then return nil end
	-- Everything still open near you comes first: hearth only once this area is done.
	for _, e in ipairs(ns.Quests.log) do
		if not e.complete and not e.failed and not e.trivial and e.dist and e.dist < (cfg.hearthMinYards or 1500) then return nil end
	end
	return { name = h.name, m = h.m, x = h.x, y = h.y, quests = there, away = away }
end

function T:HearthStep()
	local plan = self:HearthPlan()
	if not plan then return nil end
	local names = {}
	for i = 1, math.min(3, #plan.quests) do names[i] = plan.quests[i].title end
	return { kind = "tip", icon = "Innkeeper", key = "hearth:" .. (plan.name or "?"), hearth = true,
		title = string.format("Hearth to %s: %d turn-in%s wait there", plan.name or "your inn", #plan.quests, #plan.quests == 1 and "" or "s"),
		sub = "Your hearthstone is ready and nothing's left nearby. " .. table.concat(names, ", ") .. (#plan.quests > 3 and ", ..." or "") ..
			(ns.db.buttons.items and ".  It's on your quest item bar." or "."),
		right = plan.away and ns.Yards(plan.away) or "", color = { 0.9, 0.8, 0.5 } }
end

local function SaveBind()
	local m, x, y = ns.Nav.GetPlayerPosition()
	local name = T:BindName()
	if m and not (IsInInstance and IsInInstance()) then
		ns.char.hearth = { name = name, m = m, x = x, y = y, zone = ns.Nav.MapName(ns.Nav.GetZoneMap(m) or m) }
	elseif name then
		ns.char.hearth = { name = name }
	end
end
T.SaveBind = SaveBind

ns:RegisterEvent("HEARTHSTONE_BOUND", function() SaveBind() end)
ns:RegisterEvent("CONFIRM_BINDER", function() T.binderAt = GetTime() end)

-- At an inn far from your hearth spot: one reminder per place per session.
T.nagged = {}
ns:RegisterEvent("PLAYER_UPDATE_RESTING", function()
	if not ns.ready or not Cfg().setHearth or not IsResting() or not T:HasHearthstone() then return end
	local bind = T:BindName()
	local here = GetSubZoneText and GetSubZoneText() or ""
	if here == "" then here = GetZoneText and GetZoneText() or "" end
	if not bind or here == "" or bind == here or T.nagged[here] then return end
	local h = T:HearthSpot()
	local away = h and ns.Nav.Distance(h.m, h.x, h.y)
	if h and away and away < 2000 then return end
	-- Only worth it when you have quests around here.
	local nearby = 0
	for _, e in ipairs(ns.Quests.log) do if not e.complete and e.dist and e.dist < 2500 then nearby = nearby + 1 end end
	for _, o in ipairs(ns.Quests.offers) do if not o.trivial and o.dist and o.dist < 2500 then nearby = nearby + 1 end end
	if nearby < 3 then return end
	T.nagged[here] = true
	ns.Print(string.format("your hearthstone is set to %s%s. If you'll quest around here a while, make this inn your home (talk to the innkeeper).",
		bind, away and (", " .. ns.Yards(away) .. " away") or ""))
end)

-- Rows for the guide: flight path (near the top when it's close), hearth (first).
function T:GuideRows()
	local U = ns.Upkeep
	local hearth, flight = self:HearthStep(), self:FlightStep()
	if U then hearth, flight = U:Shown(hearth), U:Shown(flight) end
	if hearth then hearth.reminder = true end
	if flight then flight.reminder = true end
	return hearth, flight
end
