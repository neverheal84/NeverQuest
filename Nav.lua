-- NeverQuest Nav: waypoint arrow, /way command and position math.

local ADDON, ns = ...
local Nav = {}
ns.Nav = Nav

local atan2, sqrt, abs, pi, floor = math.atan2, math.sqrt, math.abs, math.pi, math.floor
local TWO_PI = pi * 2

---------------------------------------------------------------------------
-- Map helpers
---------------------------------------------------------------------------
local continentCache, zoneCache = {}, {}

-- Walks up the map tree until it finds a map of the requested type.
local function FindAncestor(mapID, wantedType, cache)
	if not mapID then return nil end
	local cached = cache[mapID]
	if cached ~= nil then return cached or nil end
	local id, guard = mapID, 0
	while id and id > 0 and guard < 12 do
		local info = C_Map.GetMapInfo(id)
		if not info then break end
		if info.mapType == wantedType then
			cache[mapID] = id
			return id
		end
		if info.mapType == Enum.UIMapType.World or info.mapType == Enum.UIMapType.Cosmic then break end
		id, guard = info.parentMapID, guard + 1
	end
	cache[mapID] = false
	return nil
end

function Nav.GetContinentMap(mapID)
	return FindAncestor(mapID, Enum.UIMapType.Continent, continentCache)
end

-- Zone map for any map (caves and buildings resolve to their zone).
function Nav.GetZoneMap(mapID)
	return FindAncestor(mapID, Enum.UIMapType.Zone, zoneCache) or mapID
end

function Nav.MapName(mapID)
	local info = mapID and C_Map.GetMapInfo(mapID)
	return info and info.name or "?"
end

-- Player position on a specific map, or nil if not available there.
function Nav.PlayerXY(mapID)
	if not mapID then return end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return end
	local x, y = pos:GetXY()
	if not x or ns.IsSecret(x) or ns.IsSecret(y) or (x == 0 and y == 0) then return end
	return x, y
end

function Nav.GetPlayerPosition()
	local mapID = C_Map.GetBestMapForUnit("player")
	local x, y = Nav.PlayerXY(mapID)
	if x then return mapID, x, y end
end

-- Converts a point from one map's coordinates to another map's coordinates.
function Nav.TranslatePoint(fromMap, x, y, toMap)
	if fromMap == toMap then return x, y end
	local continentID, world = C_Map.GetWorldPosFromMapPos(fromMap, CreateVector2D(x, y))
	if not continentID or not world then return end
	local _, pos = C_Map.GetMapPosFromWorldPos(continentID, world, toMap)
	if not pos then return end
	return pos:GetXY()
end

-- Distance (yards) and direction from the player to a map point.
-- Direction is counter-clockwise from north, the same convention as GetPlayerFacing().
-- Third return is true when the point is on another continent.
function Nav.Vector(tMap, tx, ty)
	if not tMap or not tx or not ty then return end
	local ref = tMap
	local px, py = Nav.PlayerXY(tMap)
	local x, y = tx, ty
	if not px then
		local pMap = C_Map.GetBestMapForUnit("player")
		local c1, c2 = Nav.GetContinentMap(pMap), Nav.GetContinentMap(tMap)
		if not c1 or not c2 then return end
		if c1 ~= c2 then return nil, nil, true end
		ref = c1
		px, py = Nav.PlayerXY(ref)
		if not px then return end
		x, y = Nav.TranslatePoint(tMap, tx, ty, ref)
		if not x then return end
	end
	local w, h = C_Map.GetMapWorldSize(ref)
	if not w or w <= 0 or not h or h <= 0 then return end
	local dx, dy = (x - px) * w, (y - py) * h
	return sqrt(dx * dx + dy * dy), atan2(-dx, -dy)
end

function Nav.Distance(m, x, y)
	local d = Nav.Vector(m, x, y)
	return d
end

-- Distance in yards between two map points (huge if on different continents).
function Nav.DistanceBetween(m1, x1, y1, m2, x2, y2)
	local ref = Nav.GetContinentMap(m1)
	if not ref or ref ~= Nav.GetContinentMap(m2) then return math.huge end
	local ax, ay = Nav.TranslatePoint(m1, x1, y1, ref)
	local bx, by = Nav.TranslatePoint(m2, x2, y2, ref)
	if not ax or not bx then return math.huge end
	local w, h = C_Map.GetMapWorldSize(ref)
	if not w or w <= 0 then return math.huge end
	local dx, dy = (bx - ax) * w, (by - ay) * h
	return sqrt(dx * dx + dy * dy)
end

---------------------------------------------------------------------------
-- Zone index (zone name lookup for /way and zone suggestions)
---------------------------------------------------------------------------
local zoneIndex

-- "The Riverglades", "Riverglades" and "riverglades" all match; so do "Shen'dralas" and "Shendralas".
local function Normalize(name)
	return (name:lower():gsub("^the ", ""):gsub("[^%w]", ""))
end

local function BuildZoneIndex()
	zoneIndex = { byName = {}, byNorm = {}, zones = {} }
	local T = Enum.UIMapType
	for id = 1, 5000 do
		local info = C_Map.GetMapInfo(id)
		if info and info.name and info.name ~= "" then
			local t = info.mapType
			if t == T.Zone or t == T.Continent or t == T.Micro or t == T.Dungeon or t == T.Orphan then
				local key = info.name:lower()
				local existing = zoneIndex.byName[key]
				if not existing or (t == T.Zone and existing.type ~= T.Zone) then
					zoneIndex.byName[key] = { id = id, type = t }
				end
				local norm = Normalize(info.name)
				local en = zoneIndex.byNorm[norm]
				if not en or (t == T.Zone and en.type ~= T.Zone) then
					zoneIndex.byNorm[norm] = { id = id, type = t, len = #norm }
				end
				if t == T.Zone then table.insert(zoneIndex.zones, id) end
			end
		end
	end
end

function Nav.FindZone(name)
	if not zoneIndex then BuildZoneIndex() end
	name = name:lower():gsub("^%s+", ""):gsub("%s+$", "")
	local exact = zoneIndex.byName[name]
	if exact then return exact.id end
	local norm = Normalize(name)
	if norm == "" then return nil end
	local same = zoneIndex.byNorm[norm]
	if same then return same.id end
	local best, bestLen
	for key, entry in pairs(zoneIndex.byNorm) do
		if key:sub(1, #norm) == norm and (not bestLen or #key < bestLen) then
			best, bestLen = entry.id, #key
		end
	end
	return best
end

function Nav.GetZoneList()
	if not zoneIndex then BuildZoneIndex() end
	return zoneIndex.zones
end

---------------------------------------------------------------------------
-- Waypoints
---------------------------------------------------------------------------
Nav.guideTarget = nil

local function Key(wp)
	return wp and (wp.key or string.format("%s:%d:%.4f:%.4f", wp.src or "?", wp.m or 0, wp.x or 0, wp.y or 0)) or nil
end

-- While you're a ghost, the arrow points at your corpse (ahead of every other target).
local RESURRECT_YARDS = 35

function Nav:CorpseTarget()
	if not ns.db or not ns.db.arrow.corpse then return nil end
	local now = GetTime()
	if self.corpseCheck and now - self.corpseCheck < 0.5 then return self.corpse end
	self.corpseCheck = now
	self.corpse = nil
	if ns.SafeCall(UnitIsGhost, "player") ~= true or not C_DeathInfo then return nil end
	local m = C_Map.GetBestMapForUnit("player")
	if not m then return nil end
	-- Try the map you're on, then its zone and continent (a corpse in a cave from outside it).
	for _, id in ipairs({ m, Nav.GetZoneMap(m), Nav.GetContinentMap(m) }) do
		local pos = ns.SafeCall(C_DeathInfo.GetCorpseMapPosition, id)
		if pos then
			local x, y = pos:GetXY()
			x, y = ns.Num(x), ns.Num(y)
			if x and y and not (x == 0 and y == 0) then
				local d = Nav.Distance(id, x, y)
				local close = d and d <= RESURRECT_YARDS
				self.corpse = { m = id, x = x, y = y, src = "corpse", key = "corpse", arrive = false,
					title = close and "Your corpse: close enough to resurrect" or "Your corpse" }
				return self.corpse
			end
		end
	end
	return nil
end

function Nav:GetActive()
	return self:CorpseTarget() or ns.char.waypoints[1] or self.guideTarget
end

function Nav:AddUser(m, x, y, title, silent)
	table.insert(ns.char.waypoints, { m = m, x = x, y = y, title = title, src = "user", arrive = true })
	if not silent then
		ns.Print(string.format("waypoint added: %s %.1f, %.1f%s", Nav.MapName(m), x * 100, y * 100, title and (" (" .. title .. ")") or ""))
	end
	self:Update()
	return #ns.char.waypoints
end

-- Moves the nearest queued waypoint to the front of the queue.
function Nav:MakeClosestActive()
	local q = ns.char.waypoints
	local best, bestDist
	for i, wp in ipairs(q) do
		local d = Nav.Distance(wp.m, wp.x, wp.y)
		if d and (not bestDist or d < bestDist) then best, bestDist = i, d end
	end
	if not best then return ns.Print("no reachable waypoints on this continent.") end
	if best > 1 then table.insert(q, 1, table.remove(q, best)) end
	ns.Print(string.format("heading to the closest waypoint (%s).", ns.Yards(bestDist)))
	self:Update()
end

-- The guide sets one transient target. Targets with the same key only update coordinates.
function Nav:SetGuideTarget(wp)
	if wp then
		wp.src = "guide"
		wp.key = wp.key or Key(wp)
		if wp.key == self.dismissedKey then return end
		local cur = self.guideTarget
		if cur and cur.key == wp.key then
			cur.m, cur.x, cur.y, cur.title = wp.m, wp.x, wp.y, wp.title
			return
		end
	end
	self.guideTarget = wp
	self:Update()
end

function Nav:Remove(i)
	if ns.char.waypoints[i] then
		table.remove(ns.char.waypoints, i)
		self:Update()
	end
end

function Nav:ClearUser()
	wipe(ns.char.waypoints)
	self:Update()
end

-- Right-click on the arrow: drop the current waypoint.
function Nav:SkipActive()
	if ns.char.waypoints[1] then
		table.remove(ns.char.waypoints, 1)
	elseif self.guideTarget then
		self.dismissedKey = self.guideTarget.key
		self.guideTarget = nil
	end
	self:Update()
end

function Nav:Arrived(wp)
	if ns.db.arrow.sound then ns.PlaySound(SOUNDKIT.MAP_PING) end
	if wp.src == "user" then
		table.remove(ns.char.waypoints, 1)
		ns.Print("arrived" .. (wp.title and (": " .. wp.title) or "."))
	else
		self.guideTarget = nil
		ns:SendMessage("NAV_ARRIVED", wp)
	end
	self:Update()
end

function Nav:ApplyNative(wp)
	if not ns.db.nav.nativeWaypoint then return end
	if self.ownedQuest and C_SuperTrack.GetSuperTrackedQuestID() == self.ownedQuest and not (wp and wp.questID == self.ownedQuest) then
		C_SuperTrack.ClearAllSuperTracked()
	end
	self.ownedQuest = nil
	if not wp then
		if self.ownsUserWaypoint then
			self.applyingNative = true
			C_Map.ClearUserWaypoint()
			self.applyingNative = false
			self.ownsUserWaypoint = false
		end
		return
	end
	if wp.questID and C_QuestLog.IsOnQuest(wp.questID) then
		if self.ownsUserWaypoint then
			self.applyingNative = true
			C_Map.ClearUserWaypoint()
			self.applyingNative = false
			self.ownsUserWaypoint = false
		end
		C_SuperTrack.SetSuperTrackedQuestID(wp.questID)
		self.ownedQuest = wp.questID
	elseif wp.m and C_Map.CanSetUserWaypointOnMap(wp.m) then
		self.applyingNative = true
		local ok = C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(wp.m, wp.x, wp.y)) ~= false
		self.applyingNative = false
		if ok then
			C_SuperTrack.SetSuperTrackedUserWaypoint(true)
			self.ownsUserWaypoint = true
		end
	end
end

function Nav:Update()
	local wp = self:GetActive()
	local key = Key(wp)
	if key ~= self.appliedKey then
		self.appliedKey = key
		self.speed, self.lastDist, self.lastTime = 0, nil, nil
		-- The game marks your corpse itself; our in-world marker steps aside until you're back.
		self:ApplyNative((wp and wp.src ~= "corpse") and wp or nil)
		ns.Debug("arrow target: " .. (wp and ((wp.title or "?") .. " [" .. (wp.src or "?") .. "]") or "none"))
	end
	if self.arrow then self.arrow:Refresh() end
	ns:SendMessage("WAYPOINTS_CHANGED")
end

-- Dying, releasing and coming back switch the arrow to your corpse and back.
local function DeathChanged()
	Nav.corpseCheck = nil
	if ns.ready then Nav:Update() end
end
ns:RegisterEvent("PLAYER_DEAD", DeathChanged)
ns:RegisterEvent("PLAYER_ALIVE", function()
	DeathChanged()
	if ns.ready and ns.db.arrow.corpse and Nav.corpse then ns.Print("the arrow points to your corpse.") end
end)
ns:RegisterEvent("PLAYER_UNGHOST", DeathChanged)
ns:RegisterEvent("PLAYER_ENTERING_WORLD", function() ns.After(1, DeathChanged) end)

-- Blizzard's own map pin (Ctrl+click on the world map) joins the NeverQuest queue, so the arrow follows it too.
ns:RegisterEvent("USER_WAYPOINT_UPDATED", function()
	if Nav.applyingNative or not ns.ready or not ns.db.nav.adoptMapPins then return end
	if not C_Map.HasUserWaypoint() then return end
	local point = C_Map.GetUserWaypoint()
	if not point or not point.uiMapID or not point.position then return end
	local x, y = point.position:GetXY()
	for _, wp in ipairs(ns.char.waypoints) do
		if wp.m == point.uiMapID and math.abs(wp.x - x) < 0.002 and math.abs(wp.y - y) < 0.002 then return end
	end
	table.insert(ns.char.waypoints, 1, { m = point.uiMapID, x = x, y = y, title = "Map pin", src = "user", arrive = true })
	Nav.ownsUserWaypoint = true
	Nav.appliedKey = Key(ns.char.waypoints[1])
	Nav:Update()
end)

---------------------------------------------------------------------------
-- Arrow frame
---------------------------------------------------------------------------
-- Media/Arrow.tga is 256 square with the arrow drawn inside the circle that fits in it, so no
-- corner is ever clipped as it turns. These say how much of the square the art actually uses.
local ARROW_SIZE = 54       -- default width of the texture, not of the arrow drawn in it
local ART_FILL = 0.76       -- of the square's height
local ART_PAD = 0.19        -- empty margin below the arrow

local function CreateArrow()
	local f = CreateFrame("Button", "NeverQuestArrow", UIParent)
	f:SetSize(150, 110)
	f:SetFrameStrata("MEDIUM")
	f:RegisterForClicks("RightButtonUp")
	ns.MakeMovable(f, "arrow", function() return ns.db.arrow.locked end, { "TOP", UIParent, "TOP", 0, -120 })

	-- Our own arrow, drawn at 256 pixels and shown at a fraction of that, so the edges stay
	-- smooth however far it is scaled up and whatever angle it is turned to. Trilinear
	-- filtering picks the right mip level instead of aliasing the full-size art down.
	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetTexture(ns.MEDIA .. "Arrow", nil, nil, "TRILINEAR")
	f.tex:SetSize(ARROW_SIZE, ARROW_SIZE)
	f.tex:SetPoint("TOP", 0, -2)
	-- A texture that snaps to whole pixels crawls and goes jagged as it rotates, because the
	-- snapping fights the rotation. Turning it off is what keeps the edges clean while it turns.
	if f.tex.SetSnapToPixelGrid then ns.SafeCall(f.tex.SetSnapToPixelGrid, f.tex, false) end
	if f.tex.SetTexelSnappingBias then ns.SafeCall(f.tex.SetTexelSnappingBias, f.tex, 0) end

	f.title = f:CreateFontString(nil, "OVERLAY", "NeverQuestFontNormal")
	f.title:SetPoint("TOP", f.tex, "BOTTOM", 0, -2)
	f.title:SetWidth(240)
	f.title:SetWordWrap(false)

	f.dist = f:CreateFontString(nil, "OVERLAY", "NeverQuestFontHighlight")
	f.dist:SetPoint("TOP", f.title, "BOTTOM", 0, -2)

	f.next = f:CreateFontString(nil, "OVERLAY", "NeverQuestFontSmall")
	f.next:SetPoint("TOP", f.dist, "BOTTOM", 0, -2)
	f.next:SetWidth(260)
	f.next:SetWordWrap(false)
	f.next:SetTextColor(0.75, 0.75, 0.75)

	f.coords = f:CreateFontString(nil, "OVERLAY", "NeverQuestFontSmallGray")
	f.coords:SetPoint("TOP", f.next, "BOTTOM", 0, -2)

	f:SetScript("OnClick", function(_, button)
		if button == "RightButton" then
			if IsShiftKeyDown() then
				Nav:ClearUser()
				ns.Print("all waypoints cleared.")
			else
				Nav:SkipActive()
			end
		end
	end)
	f:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("NeverQuest waypoint")
		GameTooltip:AddLine("Right-click: clear this waypoint", 1, 1, 1)
		GameTooltip:AddLine("Shift+Right-click: clear all /way waypoints", 1, 1, 1)
		GameTooltip:AddLine("Drag: move (unless locked)", 1, 1, 1)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", GameTooltip_Hide)

	local elapsedAcc = 0
	f:SetScript("OnUpdate", ns.Guard("Waypoint arrow", function(self, elapsed)
		elapsedAcc = elapsedAcc + elapsed
		if elapsedAcc < 0.05 then return end
		elapsedAcc = 0
		self:UpdateArrow()
	end))

	function f:Refresh()
		self:SetScale(ns.db.arrow.scale or 1)
		local size = ns.db.arrow.size or ARROW_SIZE
		if self.texSize ~= size then
			self.texSize = size
			self.tex:SetSize(size, size)
			-- The art leaves a margin inside its square so that spinning it never clips a
			-- corner, so the title is pulled up into that margin instead of floating below it.
			self.title:ClearAllPoints()
			self.title:SetPoint("TOP", self.tex, "BOTTOM", 0, floor(size * ART_PAD) - 2)
			self:SetHeight(floor(size * ART_FILL) + 70)
		end
		self.coords:SetShown(not ns.db.arrow.compact)
		self.next:SetShown(ns.db.arrow.showThen)
		local wp = Nav:GetActive()
		local show = ns.db.arrow.shown and (wp ~= nil or ns.db.arrow.alwaysShow)
		self:SetShown(show)
		if show then self:UpdateArrow() end
	end

	function f:UpdateArrow()
		local m, px, py = Nav.GetPlayerPosition()
		if m then
			self.coords:SetFormattedText("%s  %.1f, %.1f", Nav.MapName(m), px * 100, py * 100)
		else
			self.coords:SetText("")
		end

		local wp = Nav:GetActive()
		if not wp then
			self.tex:Hide()
			self.title:SetText("No waypoint")
			self.dist:SetText("")
			self.next:SetText("")
			return
		end
		local finalTitle = wp.title or string.format("%s %.1f, %.1f", Nav.MapName(wp.m), wp.x * 100, wp.y * 100)
		local finalDist, _, finalElsewhere = Nav.Vector(wp.m, wp.x, wp.y)

		-- Follow the route's next leg (entrance, tunnel, flight master...) when there is one.
		local leg = ns.Route and ns.Route:Leg(wp)
		if leg and leg.inFlight then
			self.tex:Hide()
			self.title:SetText(leg.text)
			self.dist:SetText(finalDist and (ns.Yards(finalDist) .. " to go") or "")
			self.next:SetText("then: " .. finalTitle)
			return
		end
		local aimM, aimX, aimY = wp.m, wp.x, wp.y
		if leg and leg.m then aimM, aimX, aimY = leg.m, leg.x, leg.y end
		local aimKey = string.format("%d:%.4f:%.4f", aimM, aimX, aimY)
		if aimKey ~= Nav.aimKey then
			Nav.aimKey = aimKey
			Nav.speed, Nav.lastDist, Nav.lastTime = 0, nil, nil
		end
		if leg then
			self.title:SetText(leg.text or "Next waypoint")
			self.next:SetText("then: " .. finalTitle .. (finalDist and ("  (" .. ns.Yards(finalDist) .. ")") or ""))
		else
			self.title:SetText(finalTitle)
			self.next:SetText("")
		end

		local dist, angle, elsewhere = Nav.Vector(aimM, aimX, aimY)
		if not dist then
			self.tex:Hide()
			if elsewhere or finalElsewhere then
				local cont = Nav.GetContinentMap(wp.m)
				self.dist:SetText("On " .. (cont and Nav.MapName(cont) or "another continent") .. ": take a boat, zeppelin or portal")
			else
				self.dist:SetText("No position here")
			end
			return
		end

		local facing = GetPlayerFacing()
		if facing and not ns.IsSecret(facing) then
			local rel = angle - facing
			self.tex:SetRotation(rel)
			rel = (rel + pi) % TWO_PI - pi
			local a = abs(rel)
			if a < 0.35 then
				self.tex:SetVertexColor(0.2, 1, 0.2)
			elseif a < 1.4 then
				local t = (a - 0.35) / 1.05
				self.tex:SetVertexColor(0.2 + 0.8 * t, 1, 0.2 - 0.2 * t)
			else
				local t = math.min(1, (a - 1.4) / 1.4)
				self.tex:SetVertexColor(1, 1 - 0.8 * t, 0)
			end
			self.tex:Show()
		else
			self.tex:Hide()
		end

		-- Smoothed approach speed for the ETA.
		local now = GetTime()
		if Nav.lastDist and Nav.lastTime and now - Nav.lastTime >= 0.5 then
			local v = (Nav.lastDist - dist) / (now - Nav.lastTime)
			Nav.speed = (Nav.speed or 0) * 0.7 + v * 0.3
			Nav.lastDist, Nav.lastTime = dist, now
		elseif not Nav.lastDist then
			Nav.lastDist, Nav.lastTime = dist, now
		end
		local eta = ns.db.arrow.showETA and (Nav.speed or 0) > 1 and (dist / Nav.speed) or nil
		self.dist:SetText(ns.Yards(dist) .. (eta and ("  ~" .. ns.Duration(eta)) or ""))

		local remaining = leg and finalDist or dist
		if wp.arrive and remaining and remaining <= (ns.db.arrow.arrival or 10) then
			Nav:Arrived(wp)
		end
	end

	return f
end

---------------------------------------------------------------------------
-- /way
---------------------------------------------------------------------------
local function ListWaypoints()
	local q = ns.char.waypoints
	if #q == 0 and not Nav.guideTarget then
		ns.Print("no waypoints.")
		return
	end
	ns.Print("waypoints:")
	for i, wp in ipairs(q) do
		DEFAULT_CHAT_FRAME:AddMessage(string.format("   %d. %s %.1f, %.1f %s", i, Nav.MapName(wp.m), wp.x * 100, wp.y * 100, wp.title or ""))
	end
	if Nav.guideTarget then
		DEFAULT_CHAT_FRAME:AddMessage("   guide: " .. (Nav.guideTarget.title or "?"))
	end
end

local function WayCommand(msg)
	msg = (msg or ""):gsub(",", " ")
	local tokens = {}
	for w in msg:gmatch("%S+") do tokens[#tokens + 1] = w end
	local first = tokens[1] and tokens[1]:lower()

	if not first or first == "list" then return ListWaypoints() end
	if first == "clear" or first == "reset" then
		Nav:ClearUser()
		return ns.Print("waypoints cleared.")
	end
	if first == "next" or first == "skip" then return Nav:SkipActive() end
	if first == "closest" or first == "nearest" then return Nav:MakeClosestActive() end
	if first == "remove" and tonumber(tokens[2]) then return Nav:Remove(tonumber(tokens[2])) end
	if first == "here" then
		local m, x, y = Nav.GetPlayerPosition()
		if not m then return ns.Print("no position available here.") end
		return Nav:AddUser(m, x, y, table.concat(tokens, " ", 2) ~= "" and table.concat(tokens, " ", 2) or nil)
	end

	local mapID, i
	if tokens[1]:match("^#%d+$") then
		mapID, i = tonumber(tokens[1]:sub(2)), 2
	else
		i = 1
		while tokens[i] and not tonumber(tokens[i]) do i = i + 1 end
		if i > 1 then
			local zoneName = table.concat(tokens, " ", 1, i - 1)
			mapID = Nav.FindZone(zoneName)
			if not mapID then return ns.Print("unknown zone: " .. zoneName) end
		end
	end
	local x, y = tonumber(tokens[i]), tonumber(tokens[i + 1])
	if not x or not y or x < 0 or x > 100 or y < 0 or y > 100 then
		ns.Print("usage: /way [zone] x y [note]   e.g. /way 45.2 63.8 Innkeeper")
		DEFAULT_CHAT_FRAME:AddMessage("   /way list | clear | next | closest | remove N | here [note]")
		return
	end
	mapID = mapID or C_Map.GetBestMapForUnit("player")
	if not mapID then return ns.Print("can't tell which map you're on; add a zone name.") end
	local title = table.concat(tokens, " ", i + 2)
	Nav:AddUser(mapID, x / 100, y / 100, title ~= "" and title or nil)
end

-- Only claim /way if no other loaded addon already registered it (/nqway always works).
local function SlashTaken(cmd)
	for k, v in pairs(_G) do
		if type(k) == "string" and k:sub(1, 6) == "SLASH_" and not k:find("^SLASH_NEVERQUESTWAY")
			and type(v) == "string" and not ns.IsSecret(v) and v:lower() == cmd then
			return true
		end
	end
	return false
end

SLASH_NEVERQUESTWAY1 = "/nqway"
if not SlashTaken("/way") then
	SLASH_NEVERQUESTWAY2 = "/way"
end
SlashCmdList["NEVERQUESTWAY"] = WayCommand

ns:AddSlash("arrow", function()
	ns.db.arrow.shown = not ns.db.arrow.shown
	Nav:Update()
	ns.Print(ns.db.arrow.shown and "arrow shown." or "arrow hidden.")
end, "/nq arrow - show or hide the waypoint arrow")
table.insert(ns.slashHelp, "/way [zone] x y [note] - add a waypoint (/way list, clear, next, closest, here)")

---------------------------------------------------------------------------
-- Public API for macros and other addons (coordinates are 0-1 map fractions)
---------------------------------------------------------------------------
function ns.AddWaypoint(mapID, x, y, title)
	if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then return nil end
	if x > 1 or y > 1 then x, y = x / 100, y / 100 end
	return Nav:AddUser(mapID, x, y, title, true)
end
function ns.RemoveWaypoint(index) Nav:Remove(index) end
function ns.ClearWaypoints() Nav:ClearUser() end
function ns.GetActiveWaypoint()
	local wp = Nav:GetActive()
	if wp then return wp.m, wp.x, wp.y, wp.title end
end

---------------------------------------------------------------------------
-- Native world map coordinates (Forever already draws them; we just switch them on)
---------------------------------------------------------------------------
function Nav.ApplyMapCoords(enable)
	local value = enable and "1" or "0"
	pcall(SetCVar, "worldMapShowPlayerCoords", value)
	pcall(SetCVar, "worldMapShowCursorCoords", value)
end

ns:OnInit(function()
	Nav.arrow = CreateArrow()
	Nav:Update()
end)

ns:RegisterEvent("PLAYER_LOGIN", function()
	if ns.db.nav.mapCoords then Nav.ApplyMapCoords(true) end
	Nav.appliedKey = nil
	Nav:Update()
end)

ns:RegisterMessage("POSITIONS_RESET", function()
	if Nav.arrow then Nav.arrow:RestorePosition() end
end)
