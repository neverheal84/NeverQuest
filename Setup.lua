-- NeverQuest setup wizard: a few short pages that pick the main settings, opened on a fresh
-- install and any time with /nq setup. Everything it sets is also under Options.

local ADDON, ns = ...
local Setup = {}
ns.Setup = Setup

local W, H = 560, 480

local function Cfg() return ns.db end

-- Refresh helpers shared by several pages.
local function Pins() if ns.Pins then ns.Pins:Refresh(true) end end
local function Guide()
	if ns.Planner then ns.Planner.dirty = true end
	if ns.Guide then ns.Guide.focusKey = nil ns.Guide:Refresh() end
end

---------------------------------------------------------------------------
-- Pages: title, text, and a builder that adds controls at (x, y) rows.
---------------------------------------------------------------------------
Setup.PAGES = {
	{
		key = "welcome", title = "Welcome to NeverQuest",
		text = "NeverQuest plans your leveling route, points the way, tracks your quests and learns where quest mobs are as you play.\n\n" ..
			"This setup takes a minute and picks the basics. Everything here can be changed later under Options, and |cffffd100/nq setup|r brings this back.\n\n" ..
			"What you'll see:\n" ..
			"  |cffffd100Main window|r (|cffffd100/nq|r or the minimap button): your next steps, quest log, nearby quests, raid attunements and journal.\n" ..
			"  |cffffd100Arrow|r: points at the guide's top step, a waypoint, or your corpse.\n" ..
			"  |cffffd100Route line|r on the world map and the minimap: the way to your next stops, round cliffs and water.\n" ..
			"  |cffffd100Tracker|r on the right: your quests in the order the guide will do them.\n" ..
			"  |cffffd100XP panel|r: XP per hour and time to level.\n\n" ..
			"Happy with the defaults? Click |cffffd100Use recommended|r and you're done.",
	},
	{
		key = "leveling", title = "Leveling and your route",
		text = "|cffffd100Optimized 1-60|r goes where the XP per hour is best for you and suggests quests to drop. |cffffd100Zone by zone|r is the completionist way: every quest in a zone, gray ones too.\n\nRight-click a quest to skip it. Skipped and dropped quests go on a list (Quests tab > Missed) you can go back to.",
		build = function(p, U, row)
			local db = Cfg()
			U.Cycle(p, 0, row(30), "Leveling style:", ns.Profiles.STYLES, function() return ns.Profiles:Style() end,
				function(v) db.guide.style = v Guide() end)
			U.Check(p, 0, row(), "Follow my race's 1-60 plan", function() return db.guide.profile end, function(v) db.guide.profile = v Guide() end,
				"Quests in the zones your plan wants you in count for more, and the guide says when to move on.")
			U.Check(p, 0, row(), "Plan one short route through my quests", function() return db.guide.planner end, function(v) db.guide.planner = v Guide() end,
				"Orders objectives, turn-ins and pickups to save walking back and forth.")
			U.Check(p, 0, row(), "Measure the route by the walk, not straight lines", function() return db.guide.walk ~= false end,
				function(v) db.guide.walk = v and true or false if ns.Paths and not ns.Paths:On() then ns.Paths:Reset() end Guide() end,
				"NeverQuest knows the ground in 43 zones: cliffs, deep water, hillsides, the way round a mountain. With this on, the order of your stops and which quests make one trip go by the walk you'd really make. Cities, caves and buildings use straight lines.")
			U.Check(p, 0, row(), "Pick up quests along the way", function() return db.guide.planPickups end, function(v) db.guide.planPickups = v Guide() end,
				"Quest givers worth the walk go on the route, and a quest you may do is picked up when you pass within about 100 yards of its giver. Five quest log slots stay free; slow quests are only suggested for dropping when the log is nearly full.")
			U.Check(p, 0, row(), "Learn from my XP gain and pace", function() return db.guide.learnPace ~= false end,
				function(v) db.guide.learnPace = v if ns.Advisor then ns.Advisor:Forget() end Guide() end,
				"Measures how long your kills and pickups really take and how much XP your kills give, and plans with those instead of standard figures. /nq pace shows what it has learned.")
			U.Check(p, 0, row(), "Guide steers the arrow", function() return db.guide.autoTrack end, function(v) db.guide.autoTrack = v Guide() end)
			U.Check(p, 0, row(), "Include gray (low level) quests", function() return db.guide.showGray end, function(v) db.guide.showGray = v Guide() end)
		end,
	},
	{
		key = "dungeons", title = "Dungeon quests",
		text = "Dungeon quests are some of the best XP and rewards while leveling. With this on, the route picks up the quests for the dungeons you tick a couple of levels before you're ready, and first does any quests that have to come before them. Untick the dungeons you don't plan to run.",
		build = function(p, U, row)
			local db = Cfg()
			U.Check(p, 0, row(30), "Get dungeon quests and their pre-quests first", function() return db.guide.dungeonQuests ~= false end,
				function(v) ns.Dungeons:SetOn(v) end,
				"These count for a lot more on the route than ordinary quests. Dungeon quests in your log wait for the dungeon: they're off the route (and the arrow) until they're done, then handed in like any other. /nq dungeons lists them.")
			local top = row(4)
			local rows = ns.Dungeons:BuildChecks(p, U, top, 22)
			for _ = 1, rows do row(22) end
		end,
	},
	{
		key = "maps", title = "Maps and navigation",
		text = "The route line runs from where you stand through your next stops. Spawn spots are learned from your own play: where quest mobs died, what dropped quest items, and spots you mark yourself.",
		build = function(p, U, row)
			local db = Cfg()
			U.Check(p, 0, row(), "Waypoint arrow", function() return db.arrow.shown end, function(v) db.arrow.shown = v ns.Nav:Update() end)
			U.Check(p, 0, row(), "Route lines on the world map", function() return db.pins.routeLine end, function(v) db.pins.routeLine = v Pins() end,
				"Joins the guide's next steps on the world map. The numbered pins stay either way.")
			U.Check(p, 0, row(), "Route line on the minimap", function() return db.pins.mmLine end, function(v) db.pins.mmLine = v Pins() end,
				"The same line on the minimap, cut off at its edge. /nq mmline switches it too.")
			U.Check(p, 0, row(), "Lines follow the walkable way", function() return db.pins.pathLine ~= false end,
				function(v) db.pins.pathLine = v and true or false if ns.Paths and not ns.Paths:On() then ns.Paths:Reset() end ns:SendMessage("PATHS_READY") Pins() end,
				"The lines bend round cliffs, deep water and mountains instead of running straight over them. A line is straight for a second or two after the route changes while the way is worked out.")
			U.Check(p, 0, row(), "Quest givers on the world map", function() return db.givers.worldmap end, function(v) db.givers.worldmap = v Pins() Guide() end,
				"Quests you can pick up, with their level in the quest's difficulty color.")
			U.Check(p, 0, row(), "Learn spawn spots as I play", function() return db.spawns.learn end, function(v) db.spawns.learn = v end)
			U.Check(p, 0, row(), "Tiny quest dots on the minimap", function() return db.spawns.minimap end, function(v) db.spawns.minimap = v Pins() end,
				"Where your quests' mobs and objects are, drawn small.")
			U.Cycle(p, 0, row(30), "Hover tooltips:", { { "line", "One line" }, { "off", "Off" }, { "full", "Full" } },
				function() return ns.TipMode() end, function(v) db.window.tips = v end)
		end,
	},
	{
		key = "tracker", title = "Quest tracker and XP panel",
		text = "The NeverQuest tracker lists your quests on the right side of the screen, grouped by zone and numbered in the order the guide will do them.",
		build = function(p, U, row)
			local tc = Cfg().tracker
			U.Check(p, 0, row(), "Show the NeverQuest tracker", function() return tc.shown end,
				function(v) tc.shown = v ns.Tracker:Refresh() ns.Tracker:ControlBlizzard() end)
			U.Cycle(p, 0, row(30), "Blizzard's quest list:", { { "hide", "Hide it" }, { "sort", "Sort by priority" }, { "leave", "Leave it alone" } },
				function() return tc.blizzard end, function(v) tc.blizzard = v ns.Tracker:ControlBlizzard() end,
				"Hide: Blizzard's list is emptied while NeverQuest's tracker shows. Sort: it stays, in NeverQuest's order.")
			U.Check(p, 0, row(), "XP panel", function() return Cfg().hud.shown end, function(v) Cfg().hud.shown = v ns.XP:Refresh() end,
				"XP per hour, time to level, quests or kills to level, rested XP.")
		end,
	},
	{
		key = "automation", title = "Automation",
		text = "Hold |cffffd100Shift|r while talking to an NPC, looting or opening a vendor to skip automation that time.",
		build = function(p, U, row)
			local au = Cfg().auto
			U.Check(p, 0, row(), "Accept quests automatically", function() return au.accept end, function(v) au.accept = v end)
			U.Cycle(p, 16, row(30), "Which quests:", { { "all", "Every quest" }, { "route", "Only ones the route will do" } },
				function() return au.acceptOnly or "all" end, function(v) au.acceptOnly = v end,
				"Only ones the route will do: quests on your route (those picked up in passing too), class and profession quests, quests for your chosen dungeons and attunement, and others worth their time. Elite and group quests wait for a group. Anything else you can still accept by hand.")
			U.Check(p, 0, row(), "Turn in finished quests automatically", function() return au.turnin end, function(v) au.turnin = v end)
			U.Check(p, 0, row(), "Pick quests in NPC dialog windows", function() return au.gossip end, function(v) au.gossip = v end)
			U.Check(p, 0, row(), "Skip gray quests", function() return au.skipGray end, function(v) au.skipGray = v end)
			U.Cycle(p, 0, row(30), "Reward choice:", { { "suggest", "Mark the best one" }, { "upgrade", "Take upgrades, else value" },
				{ "value", "Take highest vendor value" }, { "off", "Do nothing" } },
				function() return au.reward end, function(v) au.reward = v end)
			local lt = Cfg().loot
			U.Check(p, 0, row(), "Auto loot everything (hold Shift to look first)", function() return lt.auto end, function(v) lt.auto = v end)
			U.Check(p, 0, row(), "Sell junk (gray items) at vendors", function() return lt.junk end, function(v) lt.junk = v end,
				"You can buy them back from the vendor's Buyback tab.")
			U.Check(p, 0, row(), "Repair at vendors", function() return lt.repair end, function(v) lt.repair = v end)
		end,
	},
	{
		key = "helpers", title = "Reminders and travel",
		text = "Small things that cost leveling time. Reminders show up as rows in the guide.\n\nNeverQuest only flies you between flight masters your flight map has shown you can reach: open the flight map once at any flight master so it knows which you have.",
		build = function(p, U, row)
			local db = Cfg()
			local function Re() if ns.Guide then ns.Guide:Refresh() end end
			U.Check(p, 0, row(), "Quest log full: say what to drop", function() return db.upkeep.logFull end, function(v) db.upkeep.logFull = v Re() end)
			U.Check(p, 0, row(), "Low on food, water, ammo or bag space", function() return db.upkeep.supplies and db.upkeep.bags end,
				function(v) db.upkeep.supplies, db.upkeep.bags = v, v Re() end)
			U.Check(p, 0, row(), "Logging out with no rested XP", function() return db.upkeep.rested end, function(v) db.upkeep.rested = v end)
			U.Check(p, 0, row(), "Flight paths you don't have yet", function() return db.travel.flightPaths end, function(v) db.travel.flightPaths = v Re() end)
			U.Check(p, 0, row(), "Use my flight paths", function() return db.nav.flights end,
				function(v) db.nav.flights = v if ns.Route and ns.Route.DropFlight then ns.Route:DropFlight() end Guide() end,
				"The arrow says \"Fly from X to Y\" when that's clearly faster, and the route counts a long trip as walk, fly, walk when you know a flight master near both ends.")
			U.Check(p, 0, row(), "Say when to hearth back to hand in quests", function() return db.travel.hearth end, function(v) db.travel.hearth = v Re() end)
			U.Check(p, 0, row(), "Raid attunement reminders from level 50", function() return db.guide.attunements end, function(v) db.guide.attunements = v Guide() end)
		end,
	},
	{
		key = "database", title = "Quest database",
		text = "Where NeverQuest's quest givers and turn-ins come from.\n\n" ..
			"|cffffd100QuestieDB|r (recommended): the quest database built and kept up to date by the Questie team, installed with NeverQuest as its own addon. It fills in what NeverQuest hasn't seen yet, so the map is full from your first login. Where your own game shows its data is wrong, NeverQuest notes it and stops showing the wrong place.\n\n" ..
			"|cffffd100Build my own|r: NeverQuest doesn't read QuestieDB at all. Only what your characters see, what NeverQuest ships of its own, and what other NeverQuest players in your party and guild pass on. The map starts emptier and fills in as you play.",
		note = function() return ns.Library and ns.Library:Short() end,
		build = function(p, U, row)
			local db = Cfg()
			U.Cycle(p, 0, row(30), "Quest data:", { { "bundled", "QuestieDB" }, { "own", "Build my own" } },
				function() return db.questdb.bundled == false and "own" or "bundled" end,
				function(v) if ns.QuestDB then ns.QuestDB:SetBundled(v == "bundled") else db.questdb.bundled = (v == "bundled") end Pins() Guide() end,
				"You can switch any time under Options, or with /nq db bundled on | off.")
			U.Check(p, 0, row(), "Note where QuestieDB's data is wrong", function() return db.questdb.fixes ~= false end,
				function(v) db.questdb.fixes = v if ns.QuestDB then ns.QuestDB:ClearNearby() end ns:SendMessage("MAP_OFFERS_UPDATED") end,
				"Standing where QuestieDB puts a quest giver, with the quest not on offer to you, or finding the giver or turn-in somewhere else: NeverQuest writes it down and stops showing the wrong place. /nq db fixes lists them.")
			U.Check(p, 0, row(), "Scan zones in the background", function() return db.questdb.scan end,
				function(v) db.questdb.scan = v if not v and ns.QuestDB then ns.QuestDB:StopScan() end end,
				"Asks the game which quests each zone offers you, paused in combat. This is how NeverQuest builds its own data. /nq db searches it.")
			U.Check(p, 0, row(), "Known quests on the world map", function() return db.questdb.worldmap end, function(v) db.questdb.worldmap = v end)
		end,
	},
	{
		key = "party", title = "Playing in a group",
		text = "In a party the tracker shows each member, the quests you share and who still needs what. Members don't need NeverQuest for that; those who run it also share their progress and learned spots.",
		build = function(p, U, row)
			local db = Cfg()
			U.Check(p, 0, row(), "Share quest progress with my party", function() return db.party.enabled end,
				function(v) db.party.enabled = v if v and ns.Party then ns.Party:SendSnapshot() end end)
			U.Check(p, 0, row(), "Party catch-up", function() return db.party.catchUp end, function(v) db.party.catchUp = v Guide() end,
				"The guide and route adapt so everyone keeps up: shared quests first, turn-ins wait for whoever still needs them.")
			U.Check(p, 0, row(), "Tell me when my party makes progress", function() return db.party.alerts ~= false end, function(v) db.party.alerts = v and true or false end,
				"A short line in your own chat, with a sound, when someone finishes an objective of a quest you share or everyone's ready to hand in. Nobody else sees it.")
			U.Check(p, 0, row(), "Announce completions in party chat", function() return db.announce.enabled end, function(v) db.announce.enabled = v end,
				"Finished objectives, quests ready to turn in and raid attunement steps. Each type can be switched off under Options.")
		end,
	},
	{
		key = "look", title = "Size and text",
		text = "More choices (fonts, outlines, sizes for each panel) are under Options > Scale & Text.",
		build = function(p, U, row)
			local db = Cfg()
			local St = ns.Style
			U.Cycle(p, 0, row(30), "Text size:", St.TEXT_SIZES, function() return db.style.textScale end, function(v) db.style.textScale = v St:Apply() end)
			U.Cycle(p, 0, row(30), "Main window size:", St.SCALES, function() return db.window.scale end, function(v) db.window.scale = v ns.UI:ApplyScale() end)
			U.Check(p, 0, row(), "NeverQuest button on the minimap", function() return db.minimapButton.shown end,
				function(v) db.minimapButton.shown = v if ns.MinimapButton then ns.MinimapButton:Refresh() end end)
			U.Check(p, 0, row(), "Login message in chat", function() return not db.quietLogin end, function(v) db.quietLogin = not v end)
		end,
	},
	{
		key = "done", title = "You're set",
		text = "Handy commands:\n" ..
			"  |cffffd100/nq|r  open or close NeverQuest\n" ..
			"  |cffffd100/nq help|r  how everything works, and every command\n" ..
			"  |cffffd100/nq setup|r  this setup again\n" ..
			"  |cffffd100/nq options|r  every setting\n" ..
			"  |cffffd100/nq route|r  your planned route, stop by stop\n" ..
			"  |cffffd100/nq zones|r  why the guide wants you in this zone\n" ..
			"  |cffffd100/nq missed|r  quests you skipped, dropped or left behind\n" ..
			"  |cffffd100/nq paths|r  walking paths and route lines (|cffffd100/nq mmline|r for the minimap line)\n" ..
			"  |cffffd100/nq raids|r  raid attunement guides\n" ..
			"  |cffffd100/nq db <name>|r  find a quest in the quest database\n" ..
			"  |cffffd100/way 45 63|r  a waypoint in your zone\n\n" ..
			"Open the flight map once at a flight master so NeverQuest knows which flight paths you have. Hover almost anything in NeverQuest for a tooltip; right-click the minimap button for quick settings.",
	},
}

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
function Setup:Create()
	if self.frame then return self.frame end
	local U = ns.UI
	local f = CreateFrame("Frame", "NeverQuestSetup", UIParent, "BackdropTemplate")
	f:SetSize(W, H)
	f:SetPoint("CENTER", 0, 60)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	ns.ApplyBackdrop(f, 0.97)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	table.insert(UISpecialFrames, "NeverQuestSetup")
	self.frame = f

	f.step = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.step:SetPoint("TOPRIGHT", -36, -16)
	f.logo = f:CreateTexture(nil, "ARTWORK")
	f.logo:SetTexture(ns.LOGO)
	f.logo:SetSize(40, 40)
	f.logo:SetPoint("TOPLEFT", 16, -12)
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.title:SetPoint("TOPLEFT", f.logo, "TOPRIGHT", 10, -4)
	f.by = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.by:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
	f.by:SetText("NeverQuest " .. ns.version .. "  ·  by " .. ns.AUTHOR)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.text:SetPoint("TOPLEFT", 20, -66)
	f.text:SetWidth(W - 40)
	f.text:SetJustifyH("LEFT")
	f.text:SetJustifyV("TOP")
	f.text:SetSpacing(2)

	-- One frame of controls per page, shown with its page.
	self.pageFrames = {}
	for i, page in ipairs(self.PAGES) do
		local p = CreateFrame("Frame", nil, f)
		p:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -18)
		p:SetPoint("BOTTOMRIGHT", -20, 50)
		p:Hide()
		if page.build then
			local y = 0
			local function Row(gap)
				local at = y
				y = y - (gap or 28)
				return at
			end
			page.build(p, U, Row)
		end
		self.pageFrames[i] = p
	end

	f.back = U.Button(f, "Back", 90, function() Setup:Go(Setup.index - 1) end)
	f.back:SetPoint("BOTTOMLEFT", 16, 14)
	f.next = U.Button(f, "Next", 110, function()
		if Setup.index >= #Setup.PAGES then Setup:Finish() else Setup:Go(Setup.index + 1) end
	end)
	f.next:SetPoint("BOTTOMRIGHT", -16, 14)
	f.quick = U.Button(f, "Use recommended", 140, function() Setup:UseRecommended() end)
	f.quick:SetPoint("RIGHT", f.next, "LEFT", -8, 0)
	f.skip = U.Button(f, "Skip setup", 100, function() Setup:Finish(true) end)
	f.skip:SetPoint("LEFT", f.back, "RIGHT", 8, 0)
	f.guide = U.Button(f, "Open the guide", 130, function()
		Setup:Finish()
		if ns.UI.frame then ns.UI.frame:Show() ns.UI:SetTab("guide") end
	end)
	f.guide:SetPoint("RIGHT", f.next, "LEFT", -8, 0)
	f.help = U.Button(f, "Open help", 100, function()
		Setup:Finish()
		if ns.Help then ns.Help:Open() end
	end)
	f.help:SetPoint("RIGHT", f.guide, "LEFT", -8, 0)
	return f
end

function Setup:Go(i)
	local f = self:Create()
	i = math.max(1, math.min(#self.PAGES, i))
	self.index = i
	local page = self.PAGES[i]
	for n, p in ipairs(self.pageFrames) do p:SetShown(n == i) end
	f.title:SetText(page.title)
	-- A page can add a line that depends on how things stand right now.
	local note = page.note and page.note()
	f.text:SetText((page.text or "") .. (note and ("\n\n" .. note) or ""))
	f.step:SetFormattedText("Step %d of %d", i, #self.PAGES)
	local last = i == #self.PAGES
	f.back:SetShown(i > 1)
	f.skip:SetShown(i == 1)
	f.quick:SetShown(i == 1)
	f.next:SetText(last and "Finish" or (i == 1 and "Let's go" or "Next"))
	f.guide:SetShown(last)
	f.help:SetShown(last)
end

function Setup:Open(pageKey)
	local f = self:Create()
	local start = 1
	for i, page in ipairs(self.PAGES) do if page.key == pageKey then start = i end end
	self:Go(start)
	f:Show()
end

-- Recommended means NeverQuest's defaults: nothing to change, so go straight to the summary.
function Setup:UseRecommended()
	self:Go(#self.PAGES)
end

function Setup:Finish(skipped)
	Cfg().setupDone = true
	if self.frame then self.frame:Hide() end
	if skipped then ns.Print("setup skipped. |cffffd100/nq setup|r runs it any time, |cffffd100/nq help|r explains everything.") end
end

-- First run: open the wizard once you're in the world and out of combat. Characters that
-- already had NeverQuest get a one-time chat note instead.
local function FirstRun()
	local db = Cfg()
	if db.setupDone then return end
	if ns.freshInstall then
		if InCombatLockdown() then
			Setup.waitCombat = true
			return
		end
		Setup:Open()
	elseif not db.setupHinted then
		db.setupHinted = true
		ns.Print("new: |cffffd100/nq setup|r walks through the main settings, and |cffffd100/nq help|r explains every feature and command.")
	end
end
Setup.FirstRun = FirstRun

ns:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)
	if not ns.ready or Setup.checked then return end
	Setup.checked = true
	ns.After(4, function() ns.Call("setup wizard", FirstRun) end)
end)

ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
	if Setup.waitCombat then
		Setup.waitCombat = nil
		ns.Call("setup wizard", FirstRun)
	end
end)

ns:AddSlash("setup", function(arg)
	Setup:Open((arg or ""):lower())
end, "/nq setup - the setup wizard (main settings in a few steps)")
ns:AddSlash("wizard", function(arg) Setup:Open((arg or ""):lower()) end)
