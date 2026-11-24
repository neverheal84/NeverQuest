-- NeverQuest Pins: minimap pins (quest givers, objectives, turn-ins, waypoints, known spawns) and
-- a world map layer that shows your waypoint queue, a numbered preview of the guide's next
-- steps, and the spawn and objective spots from Spawns.lua.

local ADDON, ns = ...
local P = {}
ns.Pins = P

local sqrt, cos, sin, min = math.sqrt, math.cos, math.sin, math.min

local ATLAS = {
	giver = "QuestNormal", turnin = "QuestTurnin", objective = ns.ICON_DO,
	waypoint = "Waypoint-MapPin-Untracked", active = "Waypoint-MapPin-Tracked",
	note = "minimap-genericevent-hornicon", rare = "VignetteKill",
	party = "Interface\\WorldMap\\WorldMapPartyIcon",
}
P.ATLAS = ATLAS
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SPAWN_KINDS = { spot = true, mark = true, rare = true }

-- Looks for spawn points (learned spots, marks, rares) on both maps. The frame needs Dot and
-- Ring (round, white, tinted here) and Icon (atlas) textures.
-- Learned spots are small dots (a little bigger the more often they've been seen); the dot
-- size setting scales them, and marks, notes and rares with them.
local function ApplySpawnLook(f, p, scale)
	local size, alpha, atlas, ring
	if p.kind == "rare" then
		atlas, size, alpha = (p.ent and p.ent.rec and p.ent.rec.a) or ATLAS.rare, 13, 0.9
	elseif p.kind == "mark" and p.mark and p.mark.k == "note" then
		atlas, size, alpha = ATLAS.note, 13, 1
	elseif p.kind == "mark" then
		size, alpha, ring = 8, 1, { 1, 0.95, 0.7, 1 }
	else
		local w = p.w or 1
		size = 5 + min(3, (w - 1) * 0.5)
		alpha = 0.5 + 0.4 * min(w, 6) / 6
		ring = { 0, 0, 0, 0.75 }
	end
	size = size * (scale or 1) * (ns.db.spawns.dotSize or 1)
	f:SetSize(size, size)
	if f.Ring then
		f.Ring:ClearAllPoints()
		f.Ring:SetPoint("TOPLEFT", -1, 1)
		f.Ring:SetPoint("BOTTOMRIGHT", 1, -1)
	end
	if atlas then
		f.Icon:SetAtlas(atlas, false)
		f.Icon:Show()
		f.Dot:Hide()
		f.Ring:Hide()
	else
		local c = ns.Spawns:ColorFor(p)
		f.Icon:Hide()
		f.Dot:SetVertexColor(c[1], c[2], c[3], 1)
		f.Dot:Show()
		f.Ring:SetVertexColor(ring[1], ring[2], ring[3], ring[4])
		f.Ring:Show()
	end
	f:SetAlpha(alpha)
end

-- Icon for a quest giver: daily, campaign/story and legendary quests get their own "!".
local function GiverAtlas(o)
	if o.legendary then return "UI-QuestPoiLegendary-QuestBang" end
	if o.campaign or o.important then return "Quest-Campaign-Available" end
	if o.daily then return "UI-QuestPoiRecurring-QuestBang" end
	return ATLAS.giver
end
P.GiverAtlas = GiverAtlas

local function LevelTag(o)
	return o.level and ("[" .. o.level .. "] ") or ""
end

local function StepAtlas(step)
	return step.icon or ns.Guide.ICONS[step.kind] or ATLAS.waypoint
end

local function Inside(x, y)
	return x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1
end

-- What your party still needs that you can help with (Party:HelpList), one blue marker per
-- quest where its work is: quests they're on that you've finished or don't have.
function P:PartyPoints()
	local out = {}
	if ns.db.party.mapHelp == false or not ns.Party or not IsInGroup() or IsInRaid() then return out end
	for _, h in ipairs(ns.Party:HelpList()) do
		if h.spot and h.spot.m then
			table.insert(out, { kind = "party", m = h.spot.m, x = h.spot.x, y = h.spot.y, questID = h.questID,
				atlas = ATLAS.party, key = "help:" .. h.questID, title = "Party: " .. h.title, qtitle = h.title, sub = table.concat(h.who, "; ") })
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Minimap
---------------------------------------------------------------------------
local mm = { pins = {}, points = {} }

function P:MinimapPoints()
	local cfg, pts = ns.db.pins, {}
	local questie = ns.QuestieOverlap()
	-- Known spawns and marks near you go in first so quest pins draw over them.
	-- Only spots for your quests' objectives (and your own marks) go on the minimap: it has no
	-- room for every spot ever learned, or for rares.
	if ns.db.spawns.minimap and ns.Spawns and not questie then
		local all = ns.db.spawns.showAll
		for _, sp in ipairs(ns.Spawns:NearbyPoints(450, 60)) do
			local forQuest = sp.ent and sp.ent.refs and #sp.ent.refs > 0
			if sp.mark or forQuest or (all and sp.kind ~= "rare") then
				table.insert(pts, { kind = sp.kind, m = sp.m, x = sp.x, y = sp.y, spawn = sp })
			end
		end
	end
	if cfg.mmGivers and not questie then
		for _, o in ipairs(ns.Quests.offers) do
			if ns.Quests:OfferShown(o) then
				table.insert(pts, { kind = "giver", m = o.m, x = o.x, y = o.y, questID = o.questID, offer = o, qtitle = o.title,
					key = "pickup:" .. o.questID, title = "Pick up: " .. LevelTag(o) .. o.title, atlas = GiverAtlas(o),
					faded = o.trivial, sub = o.xp and ("+" .. ns.Comma(o.xp) .. " XP") or nil, level = o.level })
			end
		end
	end
	-- Quest starts from the database: your alts, your party, your guild, and the data shipped
	-- with the addon. These draw faded and only within sight, since unlike the world map the
	-- minimap has no room to show a whole zone's worth.
	if ns.db.questdb.minimap and not questie and ns.QuestDB then
		for _, k in ipairs(ns.QuestDB:NearbyPoints(400, 10)) do
			table.insert(pts, { kind = "giver", m = k.m, x = k.x, y = k.y, questID = k.qid,
				key = "known:" .. k.qid, faded = true, known = true, src = k.src, qtitle = k.q.t,
				title = "Known quest: " .. (k.q.l and ("[" .. k.q.l .. "] ") or "") .. k.q.t,
				sub = k.sub, level = k.q.l })
		end
	end
	for _, pt in ipairs(self:PartyPoints()) do table.insert(pts, pt) end
	if cfg.mmQuests then
		for _, e in ipairs(ns.Quests.log) do
			if e.pos and not e.pos.waypoint then
				table.insert(pts, { kind = e.complete and "turnin" or "objective", m = e.pos.m, x = e.pos.x, y = e.pos.y,
					atlas = (not e.complete) and ns.ObjectiveIcon(e) or nil,
					questID = e.questID, key = (e.complete and "turnin:" or "objective:") .. e.questID, qtitle = e.title,
					title = (e.complete and "Turn in: " or "") .. LevelTag(e) .. e.title, sub = (not e.complete) and e.objective or nil,
					level = e.level })
			end
		end
	end
	-- The active target's next route leg (entrance, tunnel, flight master) is what the arrow
	-- follows, so it gets the "active" pin; the destination itself shows as a normal pin.
	local active = ns.Nav:GetActive()
	local leg = active and ns.Route:Leg(active)
	if leg and not leg.m then leg = nil end
	if leg then
		table.insert(pts, { kind = "active", m = leg.m, x = leg.x, y = leg.y, title = leg.text or "Next waypoint",
			sub = "On the way to: " .. (active.title or "your target"), isLeg = true })
	end
	if cfg.mmWaypoints then
		for i, wp in ipairs(ns.char.waypoints) do
			table.insert(pts, { kind = (i == 1 and not leg) and "active" or "waypoint", m = wp.m, x = wp.x, y = wp.y,
				title = wp.title or ("Waypoint " .. i), user = true, index = i })
		end
	end
	local gt = ns.Nav.guideTarget
	if gt and not ns.char.waypoints[1] and gt.m then
		table.insert(pts, { kind = leg and "waypoint" or "active", m = gt.m, x = gt.x, y = gt.y, title = gt.title, key = gt.key, guideTarget = true })
	end
	return pts
end

local function PointClick(pt)
	if pt.spawn then
		ns.Spawns:SetWaypoint(pt.spawn)
	elseif pt.user then
		local q = ns.char.waypoints
		if pt.index and q[pt.index] and pt.index > 1 then
			table.insert(q, 1, table.remove(q, pt.index))
			ns.Nav:Update()
		end
	elseif pt.key and pt.m then
		ns.Guide:Pin({ key = pt.key, m = pt.m, x = pt.x, y = pt.y, title = pt.title, questID = pt.questID })
	end
end

-- Every quest icon on both maps: the quest's name in its difficulty color, its level, and what
-- kind of quest it is when it isn't an ordinary one (Dungeon, Raid, Elite, Group, PvP). Nothing
-- else, whatever the tooltip setting (a party icon adds who needs it). Off hides it.
function P:QuestTip(tt, questID, title, level, extra)
	level = ns.Num(level)
	local e = questID and ns.Quests.byID[questID]
	local lib = questID and ns.Library and ns.Library.Entry and ns.Library:Entry(questID)
	title = title or (e and e.title) or (lib and lib.t)
		or (questID and C_QuestLog.GetTitleForQuestID and ns.SafeCall(C_QuestLog.GetTitleForQuestID, questID)) or ("Quest " .. tostring(questID))
	level = level or (e and ns.Num(e.level)) or (lib and ns.Num(lib.l))
	local r, g, b = ns.LevelColor(level, questID)
	tt:AddLine(title, r, g, b, true)
	local kind = ns.Quests:Kind(questID)
	local line = level and ("Level " .. level) or nil
	if kind then line = line and (line .. ", " .. kind) or kind end
	if line then tt:AddLine(line, 1, 1, 1) end
	if extra and extra ~= "" then tt:AddLine(extra, 0.8, 0.8, 0.8, true) end
	return ns.TipShow(nil, true)
end

local QUEST_KINDS = { giver = true, turnin = true, objective = true, party = true }

local function PointTooltip(owner, pt)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if pt.questID and QUEST_KINDS[pt.kind] then
		P:QuestTip(GameTooltip, pt.questID, pt.qtitle, pt.level, pt.kind == "party" and pt.sub or nil)
		return
	end
	if pt.spawn then
		ns.Spawns:Tooltip(GameTooltip, pt.spawn)
		GameTooltip:AddLine("Click: set a waypoint here", 0.5, 0.8, 1)
		ns.TipShow()
		return
	end
	GameTooltip:AddLine(pt.title or "", 1, 0.82, 0, true)
	if pt.sub and pt.sub ~= "" then GameTooltip:AddLine(pt.sub, 1, 1, 1, true) end
	local d = ns.Nav.Distance(pt.m, pt.x, pt.y)
	if d then GameTooltip:AddLine(ns.Yards(d), 0.8, 0.8, 0.8) end
	GameTooltip:AddLine(pt.user and "Click: make this the active waypoint" or "Click: point the arrow here", 0.5, 0.8, 1)
	ns.TipShow()
end

local function MinimapPin(i)
	local pin = mm.pins[i]
	if pin then return pin end
	pin = CreateFrame("Button", nil, Minimap)
	pin:SetSize(14, 14)
	pin:SetFrameStrata(Minimap:GetFrameStrata())
	pin:SetFrameLevel(Minimap:GetFrameLevel() + 6)
	pin.icon = pin:CreateTexture(nil, "OVERLAY")
	pin.icon:SetAllPoints()
	pin.Icon = pin.icon
	-- Round dot with a ring, for known spawns and marks.
	pin.Ring = pin:CreateTexture(nil, "BACKGROUND")
	pin.Ring:SetColorTexture(1, 1, 1, 1)
	pin.Ring:SetPoint("TOPLEFT", -1, 1)
	pin.Ring:SetPoint("BOTTOMRIGHT", 1, -1)
	pin.Dot = pin:CreateTexture(nil, "ARTWORK")
	pin.Dot:SetColorTexture(1, 1, 1, 1)
	pin.Dot:SetAllPoints()
	for _, tex in ipairs({ pin.Ring, pin.Dot }) do
		local mask = pin:CreateMaskTexture()
		mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(tex)
		tex:AddMaskTexture(mask)
	end
	pin.Ring:Hide()
	pin.Dot:Hide()
	-- The quest's level beside its icon, in its difficulty color.
	pin.Level = pin:CreateFontString(nil, "OVERLAY", _G.NeverQuestFontNumber and "NeverQuestFontNumber" or "NumberFontNormal")
	pin.Level:SetPoint("LEFT", pin, "RIGHT", -1, 0)
	pin.Level:Hide()
	pin:SetScript("OnEnter", function(self) if self.point then PointTooltip(self, self.point) end end)
	pin:SetScript("OnLeave", GameTooltip_Hide)
	pin:SetScript("OnClick", function(self) if self.point then PointClick(self.point) end end)
	mm.pins[i] = pin
	return pin
end

-- The level label on a minimap pin: shown for quests (to pick up, to work on, to hand in) when
-- quest levels are switched on, in the quest's difficulty color; known quests a little dimmer.
function P.ApplyMinimapLevel(pin, pt, on, scale)
	local lv = pt and not pt.spawn and ns.Num(pt.level)
	if not (on and lv and lv > 0) then
		pin.Level:SetText("")
		pin.Level:Hide()
		return
	end
	pin.Level:SetText(tostring(lv))
	local r, g, b = ns.LevelColor(lv, pt.questID)
	if pt.known then r, g, b = r * 0.8, g * 0.8, b * 0.8 end
	pin.Level:SetTextColor(r, g, b)
	pin.Level:SetScale(math.max(0.6, 0.75 * (scale or 1)))
	pin.Level:Show()
end

local function HideMinimapPins(from)
	for i = from, #mm.pins do mm.pins[i]:Hide() end
end

-- Points are converted once into the coordinates of the map you're standing on; each frame
-- only the player's position changes.
function P:RebuildMinimap()
	wipe(mm.points)
	mm.refMap = nil
	if not ns.ready or not ns.db.pins.minimap or not Minimap then return HideMinimapPins(1) end
	local ref = C_Map.GetBestMapForUnit("player")
	if not ref then return HideMinimapPins(1) end
	mm.refMap = ref
	mm.w, mm.h = C_Map.GetMapWorldSize(ref)
	for _, pt in ipairs(self:MinimapPoints()) do
		local x, y = ns.Nav.TranslatePoint(pt.m, pt.x, pt.y, ref)
		if x then
			pt.rx, pt.ry = x, y
			table.insert(mm.points, pt)
		end
	end
	self:UpdateMinimap()
end

function P:UpdateMinimap()
	if not mm.refMap or #mm.points == 0 then return HideMinimapPins(1) end
	if C_Map.GetBestMapForUnit("player") ~= mm.refMap then return self:RebuildMinimap() end
	local px, py = ns.Nav.PlayerXY(mm.refMap)
	local radius = C_Minimap.GetViewRadius()
	if not px or not radius or radius <= 0 or not mm.w or mm.w <= 0 then return HideMinimapPins(1) end

	local half = Minimap:GetWidth() / 2
	local pxPerYard = half / radius
	local limit = half - 7
	local cf, sf = 1, 0
	if C_CVar.GetCVarBool("rotateMinimap") then
		local facing = GetPlayerFacing()
		if facing and not ns.IsSecret(facing) then cf, sf = cos(facing), sin(facing) end
	end

	local n = 0
	for _, pt in ipairs(mm.points) do
		local ex = (pt.rx - px) * mm.w * pxPerYard      -- east, in minimap pixels
		local ny = -(pt.ry - py) * mm.h * pxPerYard     -- north
		local sx, sy = ex * cf + ny * sf, -ex * sf + ny * cf
		local d = sqrt(sx * sx + sy * sy)
		local show, edge = d <= limit, false
		if not show and pt.kind == "active" then
			sx, sy = sx * limit / d, sy * limit / d
			show, edge = true, true
		end
		if show then
			n = n + 1
			local pin = MinimapPin(n)
			pin:ClearAllPoints()
			pin:SetPoint("CENTER", Minimap, "CENTER", sx, sy)
			-- This runs many times a second and all that changes between runs is where the
			-- pin sits. What it looks like is only set when the pin is given something else
			-- to show (or the size setting changes).
			local scale = ns.db.pins.mmScale or 1
			local levels = ns.db.givers.levels and true or false
			if pin.point ~= pt or pin.lookScale ~= scale or pin.lookLevels ~= levels then
				pin.point, pin.lookScale, pin.lookEdge, pin.lookLevels = pt, scale, nil, levels
				P.ApplyMinimapLevel(pin, pt, levels, scale)
				if pt.spawn then
					pin:SetFrameLevel(Minimap:GetFrameLevel() + 5)
					ApplySpawnLook(pin, pt.spawn, 0.85 * scale)
				else
					pin:SetFrameLevel(Minimap:GetFrameLevel() + 6)
					pin.Dot:Hide()
					pin.Ring:Hide()
					pin.icon:Show()
					ns.SetIcon(pin.icon, pt.atlas or ATLAS[pt.kind] or ATLAS.waypoint)
					local size = ((pt.kind == "active") and 16 or 13) * scale
					pin:SetSize(size, size)
				end
			end
			if not pt.spawn and pin.lookEdge ~= edge then
				pin.lookEdge = edge
				pin:SetAlpha(edge and 0.75 or (pt.faded and 0.55 or 1))
			end
			pin:Show()
		end
	end
	HideMinimapPins(n + 1)
end

---------------------------------------------------------------------------
-- World map layer
---------------------------------------------------------------------------
-- Blizzard's map canvas code can load after NeverQuest, so the pin mixin and the data provider
-- start as plain method tables and get Blizzard's base methods when the world map attaches.
NeverQuestMapPinMixin = {}
NeverQuestSpawnPinMixin = {}
local PinMethods, SpawnPinMethods = {}, {}

-- The line under a known quest's marker that says where its place came from, or nil when
-- that is switched off.
function P.SourceLine(info)
	if not (info and info.known and ns.db.pins.sources) then return nil end
	return info.src == "library" and "From QuestieDB, the Questie team's quest database. Not yet seen in game by NeverQuest."
		or info.src == "shipped" and "From the quest data NeverQuest ships."
		or "Your own quest database, learned while playing."
end

function PinMethods:OnLoad()
	self:SetScalingLimits(1, 1.0, 1.25)
end

-- The map sets which mouse buttons pass through a pin each time it's placed, and that call is
-- protected: from addon code during combat it would be blocked. Ours never change, so set
-- them once, outside combat.
function PinMethods:CheckMouseButtonPassthrough()
	if self.qmPassthrough or InCombatLockdown() then return end
	self.qmPassthrough = true
	self:SetPassThroughButtons("RightButton")
end

function PinMethods:OnAcquired(info)
	self.info = info
	self:UseFrameLevelType(info.frameLevel or "PIN_FRAME_LEVEL_WAYPOINT_LOCATION")
	ns.SetIcon(self.Icon, info.atlas)
	local size = (info.size or 22) * (ns.db.pins.wmScale or 1)
	self:SetSize(size, size)
	self.Icon:SetSize(size, size)
	self.Label:SetText(info.label or "")
	local c = info.labelColor
	if c then self.Label:SetTextColor(c[1], c[2], c[3]) else self.Label:SetTextColor(1, 1, 1) end
	self:SetAlpha(info.alpha or 1)
	self:SetPosition(info.x, info.y)
end

function PinMethods:OnMouseEnter()
	local info = self.info
	if not info then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if info.questID and (info.offer or info.turnin or info.known or info.partyHelp) then
		P:QuestTip(GameTooltip, info.questID, info.qtitle, info.qlevel, info.partyHelp and info.sub or nil)
		return
	end
	GameTooltip:AddLine(info.title or "", 1, 0.82, 0, true)
	if info.sub and info.sub ~= "" then GameTooltip:AddLine(info.sub, 1, 1, 1, true) end
	if info.known then
		-- Where the place came from is off by default (while the sources are being tested);
		-- /nq db sources turns it back on.
		local line = P.SourceLine(info)
		if line then GameTooltip:AddLine(line, 0.6, 0.6, 0.6) end
		GameTooltip:AddLine("Click: set a waypoint.  Ctrl+click: not here, hide it.", 0.5, 0.8, 1, true)
	elseif info.user then
		GameTooltip:AddLine("Click: make active.  Shift+click: remove.", 0.5, 0.8, 1)
	elseif info.legPin then
		GameTooltip:AddLine("Next stop on the way. The arrow goes here first.", 0.5, 0.8, 1)
	elseif info.partyHelp then
		GameTooltip:AddLine("Your party still needs this. Click: point the arrow here.", 0.5, 0.8, 1, true)
	else
		GameTooltip:AddLine("Guide step " .. (info.label or "") .. ".  Click: point the arrow here.", 0.5, 0.8, 1)
	end
	ns.TipShow()
end

function PinMethods:OnMouseLeave()
	GameTooltip:Hide()
end

function PinMethods:OnClick(button)
	local info = self.info
	if button ~= "LeftButton" or not info then return end
	if info.offer or info.turnin then
		local key = (info.offer and "pickup:" or "turnin:") .. info.questID
		if IsShiftKeyDown() then
			ns.Guide:Pin({ key = key, m = info.m, x = info.wx, y = info.wy, title = info.title, questID = info.questID })
		else
			ns.Nav:AddUser(info.m, info.wx, info.wy, info.title)
		end
	elseif info.known then
		if IsControlKeyDown() and ns.Fixes then
			ns.Fixes:NotHere(info.questID, info.m, info.wx, info.wy)
		else
			ns.Nav:AddUser(info.m, info.wx, info.wy, info.title)
		end
	elseif info.user then
		if IsShiftKeyDown() then
			ns.Nav:Remove(info.index)
		else
			PointClick({ user = true, index = info.index })
		end
	elseif info.step then
		ns.Guide:Pin(info.step)
	elseif info.partyHelp then
		ns.Guide:Pin({ key = "help:" .. info.questID, m = info.m, x = info.wx, y = info.wy, title = info.title, questID = info.questID })
	end
end

-- Spawn and objective spots, marks, rares. Right-click opens their menu, so it doesn't pass
-- through to the map (and no protected call is needed).
function SpawnPinMethods:OnLoad()
	self:SetScalingLimits(1, 0.9, 1.2)
end

function SpawnPinMethods:CheckMouseButtonPassthrough() end

function SpawnPinMethods:OnAcquired(p)
	self.point = p
	self:UseFrameLevelType(p.kind == "spot" and "PIN_FRAME_LEVEL_DIG_SITE" or "PIN_FRAME_LEVEL_GOSSIP")
	ApplySpawnLook(self, p, ns.db.pins.wmScale or 1)
	self:SetPosition(p.mx, p.my)
end

function SpawnPinMethods:OnMouseEnter()
	local p = self.point
	if not p then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	ns.Spawns:Tooltip(GameTooltip, p)
	GameTooltip:AddLine(p.mark and "Click: set a waypoint.  Shift+click: remove.  Right-click: options."
		or "Click: set a waypoint.  Right-click: options.", 0.5, 0.8, 1, true)
	ns.TipShow()
end

function SpawnPinMethods:OnMouseLeave()
	GameTooltip:Hide()
end

function SpawnPinMethods:OnClick(button)
	local p = self.point
	if not p then return end
	if button == "RightButton" then
		ns.Spawns:PointMenu(self, p)
	elseif button == "LeftButton" then
		if p.mark and IsShiftKeyDown() then
			ns.Spawns:RemoveMark(p.mark)
		else
			ns.Spawns:SetWaypoint(p)
		end
	end
end

local provider = {}
P.provider = provider

function provider:RemoveAllData()
	self:GetMap():RemoveAllPinsByTemplate("NeverQuestMapPinTemplate")
	self:GetMap():RemoveAllPinsByTemplate("NeverQuestSpawnPinTemplate")
	if self.lines then
		for _, line in ipairs(self.lines) do line:Hide() end
	end
end

function provider:Line(i)
	self.lines = self.lines or {}
	local line = self.lines[i]
	if not line then
		local canvas = self:GetMap():GetCanvas()
		if not self.lineFrame then
			self.lineFrame = CreateFrame("Frame", nil, canvas)
			self.lineFrame:SetAllPoints(canvas)
		end
		line = self.lineFrame:CreateLine(nil, "OVERLAY")
		line:SetColorTexture(1, 0.82, 0.1, 0.75)
		self.lines[i] = line
	end
	return line
end

function provider:RefreshAllData()
	self:RemoveAllData()
	if not ns.ready then return end
	local map = self:GetMap()
	local mapID = map:GetMapID()
	if not mapID then return end
	local firstPin

	-- Quest givers for the map you're looking at (any zone), level-appropriate unless the
	-- settings say otherwise, each with its level in the quest's difficulty color.
	local mapInfo = C_Map.GetMapInfo(mapID)
	local zoomedIn = mapInfo and mapInfo.mapType and mapInfo.mapType >= Enum.UIMapType.Zone
	local givers = ns.db.givers
	local questie = ns.QuestieOverlap()
	local offered = {}
	local here = ns.Quests.offerMap
	local thisZone = givers.otherZones or mapID == here or ns.Nav.GetZoneMap(mapID) == here
	if givers.worldmap and zoomedIn and not questie then
		local list = thisZone and ns.Quests:OffersForMap(mapID) or {}
		for _, o in ipairs(list) do offered[o.questID] = true end
		for _, o in ipairs(list) do
			if ns.Quests:OfferShown(o) then
				local x, y = ns.Nav.TranslatePoint(o.m, o.x, o.y, mapID)
				if Inside(x, y) then
					map:AcquirePin("NeverQuestMapPinTemplate", {
						x = x, y = y, m = o.m, wx = o.x, wy = o.y, offer = o, questID = o.questID,
						atlas = GiverAtlas(o), size = 18, alpha = o.trivial and 0.6 or 1,
						label = (givers.levels and o.level) and tostring(o.level) or "",
						labelColor = { ns.QuestColor(o.questID) }, frameLevel = "PIN_FRAME_LEVEL_TRACKED_CONTENT",
						title = "Pick up: " .. LevelTag(o) .. o.title, qtitle = o.title, qlevel = o.level,
					})
				end
			end
		end
	end
	-- Known quests from the quest database that the game isn't offering you right now.
	if givers.worldmap and zoomedIn and thisZone and not questie and ns.QuestDB then
		for _, k in ipairs(ns.QuestDB:MapPoints(mapID, offered)) do
			map:AcquirePin("NeverQuestMapPinTemplate", {
				x = k.x, y = k.y, m = k.q.m, wx = k.q.x, wy = k.q.y, known = true, questID = k.qid,
				atlas = ATLAS.giver, size = 15, alpha = 0.45,
				label = (givers.levels and k.q.l) and tostring(k.q.l) or "", labelColor = (function()
					local r, g, b = ns.LevelColor(k.q.l, k.qid) return { r * 0.8, g * 0.8, b * 0.8 } end)(),
				title = "Known quest: " .. (k.q.l and ("[" .. k.q.l .. "] ") or "") .. k.q.t, sub = k.sub, src = k.src,
				qtitle = k.q.t, qlevel = k.q.l,
			})
		end
	end
	-- Where to hand in finished quests.
	if givers.turnins and zoomedIn then
		for _, q in ipairs(C_QuestLog.GetQuestsOnMap(mapID) or {}) do
			local qx, qy = ns.Num(q.x), ns.Num(q.y)
			if q.questID and qx and qy and C_QuestLog.IsComplete(q.questID) then
				local title = C_QuestLog.GetTitleForQuestID(q.questID) or ("Quest " .. q.questID)
				map:AcquirePin("NeverQuestMapPinTemplate", {
					x = qx, y = qy, m = mapID, wx = qx, wy = qy, turnin = true, questID = q.questID,
					atlas = ATLAS.turnin, size = 18, label = "", frameLevel = "PIN_FRAME_LEVEL_TRACKED_CONTENT",
					title = "Turn in: " .. title, qtitle = title,
				})
			end
		end
	end

	-- What your party still needs.
	if zoomedIn then
		for _, pt in ipairs(P:PartyPoints()) do
			local x, y = ns.Nav.TranslatePoint(pt.m, pt.x, pt.y, mapID)
			if Inside(x, y) then
				map:AcquirePin("NeverQuestMapPinTemplate", {
					x = x, y = y, m = pt.m, wx = pt.x, wy = pt.y, partyHelp = true, questID = pt.questID,
					atlas = pt.atlas, size = 16, label = "", title = pt.title, sub = pt.sub, qtitle = pt.qtitle,
				})
			end
		end
	end

	-- Known spawns, objective spots, your marks and rares (under the quest and route pins).
	if ns.db.spawns.worldmap and ns.Spawns and not questie then
		for _, p in ipairs(ns.Spawns:MapPoints(mapID)) do
			map:AcquirePin("NeverQuestSpawnPinTemplate", p)
		end
	end
	if not ns.db.pins.worldmap then return end

	-- Your waypoint queue, numbered in order.
	for i, wp in ipairs(ns.char.waypoints) do
		local x, y = ns.Nav.TranslatePoint(wp.m, wp.x, wp.y, mapID)
		if Inside(x, y) then
			local pin = map:AcquirePin("NeverQuestMapPinTemplate", {
				x = x, y = y, user = true, index = i, label = tostring(i),
				atlas = i == 1 and ATLAS.active or ATLAS.waypoint,
				title = wp.title or ("Waypoint " .. i),
				sub = string.format("%s  %.1f, %.1f", ns.Nav.MapName(wp.m), wp.x * 100, wp.y * 100),
			})
			firstPin = firstPin or pin
		end
	end

	-- Route preview: the guide's next steps, numbered and joined by a line from where you stand.
	if ns.db.pins.route then
		local canvas = map:GetCanvas()
		local cw, ch = canvas:GetWidth(), canvas:GetHeight()
		local lx, ly = ns.Nav.PlayerXY(mapID)
		local thickness = (ns.db.pins.lineWidth or 3) / math.max(0.1, map:GetCanvasScale())
		local n, lines = 0, 0
		local function Segment(x, y)
			if lx and ns.db.pins.routeLine then
				lines = lines + 1
				local line = self:Line(lines)
				line:SetThickness(thickness)
				line:SetStartPoint("TOPLEFT", canvas, lx * cw, -ly * ch)
				line:SetEndPoint("TOPLEFT", canvas, x * cw, -y * ch)
				line:Show()
			end
			lx, ly = x, y
		end
		-- The route runs through the active target's next leg first.
		local active = ns.Nav:GetActive()
		local leg = active and ns.Route:Leg(active)
		if leg and leg.m then
			local x, y = ns.Nav.TranslatePoint(leg.m, leg.x, leg.y, mapID)
			if Inside(x, y) then
				local pin = map:AcquirePin("NeverQuestMapPinTemplate", {
					x = x, y = y, legPin = true, label = "", atlas = ATLAS.active,
					title = leg.text or "Next waypoint", sub = "On the way to: " .. (active.title or "your target"),
				})
				firstPin = firstPin or pin
				Segment(x, y)
			end
		end
		-- Where you need to go next: objectives, finished turn-ins and pickups. Turn-ins for quests
		-- that aren't done yet (and the NPC standing in for an unknown objective area) wait, and
		-- quests left for later aren't part of the route.
		local withTurnins = ns.db.pins.routeTurnins
		for _, step in ipairs(ns.Guide.steps) do
			if n >= (ns.db.pins.routeSteps or 5) then break end
			local skip = step.later or ((step.predicted or step.npcOnly) and not withTurnins)
			if step.m and step.x and not skip then
				local x, y = ns.Nav.TranslatePoint(step.m, step.x, step.y, mapID)
				if Inside(x, y) then
					n = n + 1
					local pin = map:AcquirePin("NeverQuestMapPinTemplate", {
						x = x, y = y, step = step, label = tostring(n), atlas = StepAtlas(step),
						title = step.title, sub = step.sub,
					})
					firstPin = firstPin or pin
					Segment(x, y)
				end
			end
		end
	end
	-- Keep the route line just under the pins.
	if self.lineFrame and firstPin then
		self.lineFrame:SetFrameLevel(math.max(1, firstPin:GetFrameLevel() - 1))
	end
end

function provider:OnCanvasScaleChanged()
	local thickness = (ns.db.pins.lineWidth or 3) / math.max(0.1, self:GetMap():GetCanvasScale())
	for _, line in ipairs(self.lines or {}) do line:SetThickness(thickness) end
end

function provider:OnCanvasSizeChanged()
	self:RefreshAllData()
end

local function WorldMapClick(map, button, cursorX, cursorY)
	if not IsAltKeyDown() then return false end
	local mapID = map:GetMapID()
	if not mapID or not cursorX or not cursorY then return false end
	if button == "LeftButton" and ns.db.pins.altClick then
		ns.Nav:AddUser(mapID, cursorX, cursorY, nil)
		return true
	elseif button == "RightButton" and ns.db.spawns.markClick and ns.Spawns then
		ns.Spawns:OpenMarkMenu(mapID, cursorX, cursorY, map)
		return true
	end
	return false
end

function P:AttachWorldMap()
	if self.attached or not WorldMapFrame or not WorldMapFrame.AddDataProvider then return end
	if not MapCanvasPinMixin or not MapCanvasDataProviderMixin then return end
	self.attached = true
	Mixin(NeverQuestMapPinMixin, MapCanvasPinMixin)
	for k, v in pairs(PinMethods) do NeverQuestMapPinMixin[k] = v end
	Mixin(NeverQuestSpawnPinMixin, MapCanvasPinMixin)
	for k, v in pairs(SpawnPinMethods) do NeverQuestSpawnPinMixin[k] = v end
	local methods = {}
	for k, v in pairs(provider) do methods[k] = v end
	Mixin(provider, MapCanvasDataProviderMixin)
	for k, v in pairs(methods) do provider[k] = v end
	WorldMapFrame:AddDataProvider(provider)
	WorldMapFrame:AddCanvasClickHandler(WorldMapClick, 95)
	ns.Debug("world map layer attached")
end

---------------------------------------------------------------------------
-- Refresh wiring
---------------------------------------------------------------------------
local function Signature()
	local parts = {}
	for _, wp in ipairs(ns.char.waypoints) do table.insert(parts, string.format("%d%.3f%.3f", wp.m, wp.x, wp.y)) end
	table.insert(parts, "|")
	local n = 0
	for _, s in ipairs(ns.Guide.steps) do
		if s.m and n < 8 then
			n = n + 1
			table.insert(parts, string.format("%s%d%.3f%.3f", s.key or "", s.m, s.x, s.y))
		end
	end
	local gt = ns.Nav.guideTarget
	table.insert(parts, gt and gt.key or "-")
	table.insert(parts, ns.Route.lastLegKey or "-")
	table.insert(parts, ns.Spawns and ns.Spawns:Signature() or "-")
	return table.concat(parts, ",")
end

function P:Refresh(force)
	if not ns.ready then return end
	local sig = Signature()
	local changed = force or sig ~= self.lastSig
	self.lastSig = sig
	self:RebuildMinimap()
	if changed and self.attached and WorldMapFrame:IsShown() then provider:RefreshAllData() end
end

for _, msg in ipairs({ "OFFERS_UPDATED", "MAP_OFFERS_UPDATED" }) do
	ns:RegisterMessage(msg, function() ns.Debounce("giverpins", 0.3, function() P:Refresh(true) end) end)
end
for _, msg in ipairs({ "QUESTS_UPDATED", "WAYPOINTS_CHANGED", "GUIDE_UPDATED", "ROUTE_CHANGED" }) do
	ns:RegisterMessage(msg, function() ns.Debounce("pins", 0.2, function() P:Refresh() end) end)
end
ns:RegisterMessage("SPAWNS_UPDATED", function() ns.Debounce("spawnpins", 0.3, function() P:Refresh(true) end) end)
ns:RegisterMessage("PARTY_UPDATED", function() ns.Debounce("partypins", 0.5, function() P:Refresh(true) end) end)
ns:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() ns.Debounce("pins", 0.5, function() P:Refresh(true) end) end)
ns:RegisterEvent("ZONE_CHANGED", function() ns.Debounce("pins", 0.5, function() P:Refresh() end) end)
ns:RegisterEvent("PLAYER_LOGIN", function() P:AttachWorldMap() end)
ns:RegisterEvent("ADDON_LOADED", function(_, name)
	if name == "Blizzard_WorldMap" then P:AttachWorldMap() end
end)

ns:OnInit(function()
	local driver = CreateFrame("Frame")
	local acc = 0
	local sinceRebuild = 0
	driver:SetScript("OnUpdate", ns.Guard("Minimap pins", function(_, elapsed)
		acc = acc + elapsed
		sinceRebuild = sinceRebuild + elapsed
		if acc < 0.05 then return end
		acc = 0
		if not ns.db.pins.minimap then return end
		-- Which known spawns are near changes as you move.
		if sinceRebuild >= 4 and ns.db.spawns.minimap then
			sinceRebuild = 0
			P:RebuildMinimap()
		else
			P:UpdateMinimap()
		end
	end))
end)
