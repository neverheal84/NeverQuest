-- NeverQuest MinimapButton: a round button on the edge of the minimap. Click to open NeverQuest,
-- right-click for quick settings, drag to move it around the minimap.

local ADDON, ns = ...
local B = {}
ns.MinimapButton = B

local ICON = ns.ICON   -- the NeverQuest logo
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function Cfg() return ns.db.minimapButton end

-- Round minimaps put the button on a circle; square ones (some minimap addons report this
-- through GetMinimapShape) put it on the square's edge.
function B:Place()
	local b = self.button
	if not b then return end
	local angle = math.rad(Cfg().angle or 210)
	local x, y = math.cos(angle), math.sin(angle)
	local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
	if shape == "SQUARE" then
		local m = math.max(math.abs(x), math.abs(y))
		if m > 0 then x, y = x / m, y / m end
	end
	local r = (Minimap:GetWidth() or 140) / 2 + 8
	b:ClearAllPoints()
	b:SetPoint("CENTER", Minimap, "CENTER", x * r, y * r)
end

local function Drag()
	local mx, my = Minimap:GetCenter()
	if not mx then return end
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	cx, cy = cx / scale, cy / scale
	Cfg().angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
	B:Place()
end

function B:Tooltip(owner)
	local tt = GameTooltip
	tt:SetOwner(owner, "ANCHOR_LEFT")
	tt:AddLine("NeverQuest " .. ns.version)
	local step
	for _, s in ipairs(ns.Guide.steps or {}) do
		if s.m and s.title then step = s break end
	end
	if step then tt:AddLine("Next: " .. step.title, 1, 1, 1, true) end
	local plan = ns.Guide.livePlan
	if plan and plan.stops and #plan.stops > 0 then
		tt:AddLine(string.format("Route: %d stops, ~%s, ~%s XP/hour", #plan.stops, ns.Duration(plan.seconds), ns.Comma(plan.rate)), 0.6, 0.85, 1)
	end
	local s = ns.XP and ns.XP:Stats()
	if s and s.perHour then
		tt:AddLine(string.format("XP/hour: %s, level in %s", ns.Comma(s.perHour), ns.Duration(s.toLevel)), 0.8, 0.8, 0.8)
	end
	if ns.Profiles then tt:AddLine("Style: " .. ns.Profiles:StyleName(), 0.8, 0.8, 0.8) end
	if ns.Catchup and ns.Catchup:Active() then
		tt:AddLine("Party catch-up is on", 0.4, 0.8, 1)
	end
	tt:AddLine(" ")
	tt:AddLine("Click: open NeverQuest.  Shift+click: show or hide the tracker.", 0.5, 0.8, 1, true)
	tt:AddLine("Right-click: quick settings.  Drag: move.", 0.5, 0.8, 1, true)
	ns.TipShow()
end

function B:Menu(owner)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		if ns.UI then ns.UI:OpenOptions() end
		return
	end
	local db = ns.db
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("NeverQuest")
		root:CreateButton("Open NeverQuest", function() ns.UI.frame:Show() ns.UI:SetTab("guide") end)
		root:CreateButton("1-60 plan", function() ns.UI.frame:Show() ns.UI:SetTab("guide") ns.UI:TogglePlan(true) end)
		root:CreateButton("Raid attunements", function() ns.UI.frame:Show() ns.UI:SetTab("raids") end)
		root:CreateButton("Class quests", function() ns.UI.frame:Show() ns.UI:SetTab("class") end)
		root:CreateButton("Help", function() ns.Help:Open() end)
		root:CreateButton("Setup wizard", function() ns.Setup:Open() end)
		root:CreateButton("Session summary", function() ns.Upkeep:PrintSession() end)
		root:CreateDivider()
		root:CreateCheckbox("Quest tracker", function() return db.tracker.shown end, function()
			db.tracker.shown = not db.tracker.shown
			ns.Tracker:Refresh()
			ns.Tracker:ControlBlizzard()
		end)
		root:CreateCheckbox("XP panel", function() return db.hud.shown end, function() db.hud.shown = not db.hud.shown ns.XP:Refresh() end)
		root:CreateCheckbox("Waypoint arrow", function() return db.arrow.shown end, function() db.arrow.shown = not db.arrow.shown ns.Nav:Update() end)
		root:CreateCheckbox("Party announcements", function() return db.announce.enabled end, function()
			db.announce.enabled = not db.announce.enabled
		end)
		root:CreateCheckbox("Known quests on the world map", function() return db.questdb.worldmap end, function()
			db.questdb.worldmap = not db.questdb.worldmap
			ns:SendMessage("MAP_OFFERS_UPDATED")
		end)
		root:CreateCheckbox("Known quests on the minimap", function() return db.questdb.minimap end, function()
			db.questdb.minimap = not db.questdb.minimap
			if ns.QuestDB and ns.QuestDB.ClearNearby then ns.QuestDB:ClearNearby() end
			ns:SendMessage("MAP_OFFERS_UPDATED")
		end)
		root:CreateCheckbox("Party alerts", function() return db.party.alerts ~= false end, function() ns.Party:Set("alerts") end)
		root:CreateCheckbox("Party catch-up", function() return db.party.catchUp end, function()
			db.party.catchUp = not db.party.catchUp
			ns.Planner.dirty = true
			ns.Guide:Refresh()
		end)
		root:CreateDivider()
		for _, st in ipairs(ns.Profiles.STYLES) do
			local value = st[1]
			root:CreateRadio("Style: " .. st[2], function() return ns.Profiles:Style() == value end, function() ns.UI:SetStyle(value) end)
		end
		root:CreateDivider()
		root:CreateButton("Options...", function() ns.UI:OpenOptions() end)
		root:CreateButton("Hide this button", function()
			Cfg().shown = false
			B:Refresh()
			ns.Print("minimap button hidden. /nq minimap brings it back.")
		end)
	end)
end

function B:Create()
	if self.button or not Minimap then return self.button end
	local b = CreateFrame("Button", "NeverQuestMinimapButton", Minimap)
	b:SetSize(32, 32)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(Minimap:GetFrameLevel() + 8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")

	-- The same layout as the game's own round minimap buttons.
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	b.bg:SetSize(25, 25)
	b.bg:SetPoint("TOPLEFT", 2, -4)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetTexture(ICON)
	b.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
	b.icon:SetSize(20, 20)
	b.icon:SetPoint("TOPLEFT", 7, -6)
	local mask = b:CreateMaskTexture()
	mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(b.icon)
	b.icon:AddMaskTexture(mask)
	b.border = b:CreateTexture(nil, "OVERLAY")
	b.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	b.border:SetSize(54, 54)
	b.border:SetPoint("TOPLEFT")
	b.glow = b:CreateTexture(nil, "HIGHLIGHT")
	b.glow:SetColorTexture(1, 1, 1, 0.25)
	b.glow:SetAllPoints(b.icon)
	b.glow:AddMaskTexture(mask)

	b:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			B:Menu(self)
		elseif IsShiftKeyDown() then
			ns.db.tracker.shown = not ns.db.tracker.shown
			ns.Tracker:Refresh()
			ns.Tracker:ControlBlizzard()
		elseif ns.UI then
			ns.UI:Toggle()
		end
	end)
	b:SetScript("OnDragStart", function(self)
		if Cfg().locked then return end
		self:SetScript("OnUpdate", Drag)
		GameTooltip:Hide()
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	b:SetScript("OnEnter", function(self) B:Tooltip(self) end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	self.button = b
	return b
end

function B:Refresh()
	if not ns.ready then return end
	if not Cfg().shown then
		if self.button then self.button:Hide() end
		return
	end
	local b = self:Create()
	if not b then return end
	self:Place()
	b:Show()
end

ns:RegisterEvent("PLAYER_LOGIN", function() B:Refresh() end)
-- The minimap changes size with Edit Mode and when it's rotated: keep the button on its edge.
ns:RegisterEvent("CVAR_UPDATE", function(_, name)
	if name == "rotateMinimap" then ns.After(0.2, function() B:Place() end) end
end)
if Minimap and Minimap.HookScript then
	Minimap:HookScript("OnSizeChanged", function() B:Place() end)
end

ns:AddSlash("minimap", function(rest)
	local cfg = Cfg()
	if (rest or ""):lower() == "lock" then
		cfg.locked = not cfg.locked
		ns.Print(cfg.locked and "minimap button locked." or "minimap button unlocked (drag it around the minimap).")
	else
		cfg.shown = not cfg.shown
		ns.Print(cfg.shown and "minimap button shown." or "minimap button hidden.")
	end
	B:Refresh()
end, "/nq minimap [lock] - show or hide the minimap button, or lock it in place")
