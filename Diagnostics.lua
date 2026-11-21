-- NeverQuest Diagnostics: /nq check runs a live self-test on this client, /nq report gathers
-- what's needed for a bug report. Both open in a copyable window.

local ADDON, ns = ...
local D = {}
ns.Diagnostics = D

local TOC_INTERFACE = 16001

local ATLASES = {
	"QuestNormal", "QuestTurnin", "questlog-questtypeicon-quest", "questlog-questtypeicon-heroic",
	"Waypoint-MapPin-Tracked", "Waypoint-MapPin-Untracked", "Waypoint-MapPin-Highlight",
	"Navigation-Tracked-Arrow", "FlightMaster", "Innkeeper", "Vendor", "Class",
	"minimap-genericevent-hornicon", "common-search-magnifyingglass", "VignetteKill",
	"UI-QuestPoiRecurring-QuestBang", "Quest-Campaign-Available", "UI-QuestPoiLegendary-QuestBang", "Dungeon", "Raid",
}

local function Line(list, status, label, detail)
	table.insert(list, { status = status, text = string.format("[%s] %s%s", status, label, detail and (": " .. detail) or "") })
end

function D:Check()
	local out = {}
	local _, build, _, iface = GetBuildInfo()
	local version = GetBuildInfo()
	Line(out, iface == TOC_INTERFACE and "OK" or "WARN", "Client",
		string.format("%s (%s), interface %s, NeverQuest built for %d, locale %s", tostring(version), tostring(build), tostring(iface), TOC_INTERFACE, GetLocale()))
	if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
		Line(out, "WARN", "Language", "mob names for the target button are read from English objective text")
	end

	-- Position and map
	local m, x, y = ns.Nav.GetPlayerPosition()
	if m then
		Line(out, "OK", "Position", string.format("%s (#%d) %.1f, %.1f", ns.Nav.MapName(m), m, x * 100, y * 100))
		local zone = ns.Nav.GetZoneMap(m)
		local w = C_Map.GetMapWorldSize(zone)
		Line(out, (w and w > 0) and "OK" or "FAIL", "Map size", (w and w > 0) and string.format("%s is %d yards wide", ns.Nav.MapName(zone), w) or "unknown, distances won't work here")
		local cont = ns.Nav.GetContinentMap(m)
		Line(out, cont and "OK" or "WARN", "Continent", cont and ns.Nav.MapName(cont) or "not found, cross-zone distances won't work here")
		local minL, maxL = C_Map.GetMapLevels(zone)
		Line(out, ns.Num(minL) and minL > 0 and "OK" or "WARN", "Zone levels", ns.Num(minL) and minL > 0 and (minL .. "-" .. maxL) or "none reported (cities have none)")
	else
		Line(out, "FAIL", "Position", "not available here (instances hide it); try again outdoors")
	end
	local facing = GetPlayerFacing()
	Line(out, (facing and not ns.IsSecret(facing)) and "OK" or "WARN", "Facing", (facing and not ns.IsSecret(facing)) and string.format("%.2f", facing) or "hidden here, the arrow can't rotate")
	local radius = C_Minimap.GetViewRadius()
	Line(out, (ns.Num(radius) and radius > 0) and "OK" or "FAIL", "Minimap view radius", tostring(radius) .. " yards")

	-- Quests
	local log, withPos, withRoute, withItem, sampleRoute = ns.Quests.log, 0, 0, 0, nil
	for _, e in ipairs(log) do
		if e.pos then withPos = withPos + 1 end
		if e.leg then
			withRoute = withRoute + 1
			sampleRoute = sampleRoute or (e.leg.text and (e.title .. ' -> "' .. e.leg.text .. '"'))
		end
		if e.item then withItem = withItem + 1 end
	end
	Line(out, "OK", "Quest log", string.format("%d quests, %d with a map location, %d with a game route, %d with a usable item", #log, withPos, withRoute, withItem))
	if #log > 0 and withPos == 0 then Line(out, "WARN", "Quest locations", "none found; open the world map once, then run /nq check again") end
	if sampleRoute then Line(out, "OK", "Route example", sampleRoute) end
	local xpKnown = 0
	for _, e in ipairs(log) do if e.xp and e.xp > 0 then xpKnown = xpKnown + 1 end end
	if #log > 0 then Line(out, xpKnown > 0 and "OK" or "WARN", "Quest XP values", xpKnown .. " of " .. #log .. " known") end
	local offers = #ns.Quests.offers
	local shownOffers, byDiff = 0, { [0] = 0, 0, 0, 0, 0 }
	for _, o in ipairs(ns.Quests.offers) do
		if ns.Quests:OfferShown(o) then shownOffers = shownOffers + 1 end
		if o.difficulty then byDiff[o.difficulty] = byDiff[o.difficulty] + 1 end
	end
	Line(out, "OK", "Quest givers on maps", string.format("%d of %d shown (gray %d, green %d, yellow %d, orange %d, red %d)",
		shownOffers, #ns.Quests.offers, byDiff[0], byDiff[1], byDiff[2], byDiff[3], byDiff[4]))
	Line(out, offers > 0 and "OK" or "WARN", "Quest givers nearby (game data)",
		offers > 0 and tostring(offers) or "0; normal if you've done everything here, otherwise open the world map once")

	-- Routes and travel
	if m then
		local cont = ns.Nav.GetContinentMap(m)
		local known = cont and #ns.Route.KnownNodes(cont) or 0
		local all = cont and #(C_TaxiMap.GetTaxiNodesForMap(cont) or {}) or 0
		Line(out, all > 0 and "OK" or "WARN", "Flight masters", string.format("%d usable of %d on this continent", known, all))
		local links = #(C_Map.GetMapLinksForMap(ns.Nav.GetZoneMap(m)) or {})
		Line(out, "OK", "Map links (entrances) here", tostring(links))
	end
	-- Leveling plan: do the plan's zone names match this client's map names?
	local plan = ns.Profiles:Mine()
	local names, found, missingZones = {}, 0, {}
	local function Check(name)
		if name and not names[name] then
			names[name] = true
			if ns.Profiles.ZoneID(name) then found = found + 1 else table.insert(missingZones, name) end
		end
	end
	for _, b in ipairs(plan.bands) do
		for _, name in ipairs(b.zones) do Check(name) end
	end
	for _, l in ipairs(plan.legs) do
		Check(l.zone)
		Check(l.alt)
	end
	local total = found + #missingZones
	Line(out, #missingZones == 0 and "OK" or "WARN", "Leveling plan",
		string.format("%s: %d of %d zones found on this client%s", plan.title, found, total,
			#missingZones > 0 and (" (not found: " .. table.concat(missingZones, ", ") .. ")") or ""))

	local focus = ns.Guide:Focus()
	Line(out, "OK", "Leveling style", ns.Profiles:StyleName() .. (focus and string.format("; now %s%s%s", focus.primary or "?",
		focus.nextZone and (", then " .. focus.nextZone) or "", focus.moveOn and " (time to move there)" or "") or "; plan off"))

	local active = ns.Nav:GetActive()
	if active then
		local leg = ns.Route:Leg(active)
		Line(out, "OK", "Active target", (active.title or "?") .. (leg and ('  via "' .. (leg.text or leg.kind or "waypoint") .. '"') or "  (straight line)"))
		if not active.questID then
			Line(out, (ns.Nav.ownsUserWaypoint and C_SuperTrack.IsSuperTrackingUserWaypoint()) and "OK" or "WARN", "Game route for map pin",
				(ns.Nav.ownsUserWaypoint and C_SuperTrack.IsSuperTrackingUserWaypoint()) and "tracking our pin" or "not tracking our pin (in-world marker off, or another pin is tracked)")
		end
	else
		Line(out, "OK", "Active target", "none (try /way 50 50 then /nq check)")
	end

	-- UI pieces
	local missing = {}
	for _, a in ipairs(ATLASES) do
		if not C_Texture.GetAtlasInfo(a) then table.insert(missing, a) end
	end
	Line(out, #missing == 0 and "OK" or "WARN", "Icons", #missing == 0 and ("all " .. #ATLASES .. " found") or ("missing: " .. table.concat(missing, ", ")))
	Line(out, ns.Pins.attached and "OK" or "FAIL", "World map layer", ns.Pins.attached and "attached" or "not attached")
	Line(out, ns.UI.category and "OK" or "WARN", "Settings pages", ns.UI.category and "registered" or "using the fallback window")
	Line(out, ns.Buttons.bar and "OK" or "FAIL", "Button bar", ns.Buttons.bar and ("created; item key: " .. (GetBindingKey("CLICK NeverQuestItemButton1:LeftButton") or "none") ..
		", target key: " .. (GetBindingKey("CLICK NeverQuestTargetButton:LeftButton") or "none")) or "missing")
	Line(out, "OK", "Party sync", ns.db.party.enabled and (IsInGroup() and "on, in a group" or "on, not in a group") or "off")
	local st = ns.Catchup:State()
	Line(out, "OK", "Party catch-up", not ns.db.party.catchUp and "off" or (st and string.format(
		"active: %d party members (%d with NeverQuest), group level %d", #st.mates, st.withAddon, st.groupLevel) or "on, waiting for a party"))
	local sendFn = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	Line(out, (not ns.db.announce.enabled or sendFn) and "OK" or "WARN", "Party announcements",
		ns.Announce:StatusText() .. (ns.Announce:Locked() and " (chat locked by the game right now)" or ""))
	Line(out, "OK", "Setup wizard", ns.db.setupDone and "done (/nq setup runs it again)" or "not run yet (/nq setup)")
	Line(out, "OK", "Raid attunements", ns.Attune:StatusText() .. (ns.db.guide.attunements and "" or ", guide steps off"))
	local mb = ns.MinimapButton.button
	Line(out, (not ns.db.minimapButton.shown or (mb and mb:IsShown())) and "OK" or "WARN", "Minimap button",
		ns.db.minimapButton.shown and (mb and "shown" or "not created") or "hidden (/nq minimap)")

	-- Route planner, quest chains and the tracker.
	if ns.db.guide.planner then
		local plan = ns.Planner:Get()
		Line(out, "OK", "Route planner", plan and string.format("%d stops, ~%s, ~%s XP/hour, %d quest(s) left for later",
			#plan.stops, ns.Duration(plan.seconds), ns.Comma(plan.rate), #plan.skipped) or "no route here (no position, or nothing to do)")
	else
		Line(out, "OK", "Route planner", "off (simple order)")
	end
	local learned, lines, sample = 0, 0, nil
	for _ in pairs(ns.db.chains.next) do learned = learned + 1 end
	for _, e in ipairs(ns.Quests.log) do
		local line = ns.Chains:Line(e.questID)
		if line then
			lines = lines + 1
			sample = sample or ns.Chains:Label(e.questID)
		end
	end
	Line(out, "OK", "Quest chains", string.format("%d of your quests are in a game quest line%s; %d follow-ups learned",
		lines, sample and (" (e.g. " .. sample .. ")") or "", learned))
	local tc = ns.db.tracker
	Line(out, "OK", "Quest tracker", string.format("%s; Blizzard's quest list: %s; %d quests tracked there now",
		tc.shown and "shown" or "hidden", ns.Tracker:BlizzardMode(), C_QuestLog.GetNumQuestWatches()))

	-- Spawn memory: what's stored, and the game functions it learns through.
	local sc = ns.db.spawns
	Line(out, "OK", "Spawn memory", ns.Spawns:StatsText() .. (sc.learn and "; learning on" or "; learning off"))
	local apis, missingApis = {
		{ "menus", MenuUtil and MenuUtil.CreateContextMenu },
		{ "quest mob check", C_QuestLog.UnitIsRelatedToActiveQuest },
		{ "unit tooltips", C_TooltipInfo and C_TooltipInfo.GetUnit },
		{ "range check", CheckInteractDistance },
		{ "loot info", GetLootSlotInfo },
		{ "rares", C_VignetteInfo and C_VignetteInfo.GetVignettes },
	}, {}
	for _, a in ipairs(apis) do
		if type(a[2]) ~= "function" then table.insert(missingApis, a[1]) end
	end
	Line(out, #missingApis == 0 and "OK" or "WARN", "Spawn learning",
		#missingApis == 0 and "all game functions present" or ("missing: " .. table.concat(missingApis, ", ")))
	local plates = 0
	if C_NamePlate and C_NamePlate.GetNamePlates then
		local ok, list = pcall(C_NamePlate.GetNamePlates)
		plates = (ok and type(list) == "table") and #list or 0
	end
	local here = 0
	local m = C_Map.GetBestMapForUnit("player")
	if m then here = #ns.Spawns:MapPoints(m) end
	Line(out, "OK", "Spawns on this map", string.format("%d drawn here; %d nameplates visible now%s", here, plates,
		sc.nameplates and "" or " (learning from nearby mobs is off)"))

	-- Health
	UpdateAddOnMemoryUsage()
	local kb = GetAddOnMemoryUsage(ADDON) or 0
	Line(out, kb < 8000 and "OK" or "WARN", "Memory", string.format("%.1f MB", kb / 1024))
	local paused = {}
	for name in pairs(ns.paused) do table.insert(paused, name) end
	Line(out, #paused == 0 and "OK" or "FAIL", "Paused features", #paused == 0 and "none" or table.concat(paused, ", "))
	Line(out, #ns.db.errors == 0 and "OK" or "WARN", "Errors logged", #ns.db.errors == 0 and "none" or (#ns.db.errors .. " (see /nq report)"))
	return out
end

function D:RunCheck()
	local results = self:Check()
	local counts = { OK = 0, WARN = 0, FAIL = 0 }
	local lines = { string.format("NeverQuest %s self-test, %s", ns.version, date("%Y-%m-%d %H:%M")) }
	for _, r in ipairs(results) do
		counts[r.status] = (counts[r.status] or 0) + 1
		table.insert(lines, r.text)
	end
	ns.Print(string.format("self-test: %d OK, %d warnings, %d problems. Copy the window text to share it.", counts.OK, counts.WARN, counts.FAIL))
	ns.UI:ShowIO("export", table.concat(lines, "\n"), "NeverQuest self-test", "Press Ctrl+C to copy. WARN lines are often normal; FAIL lines need a fix.")
	return counts, lines
end

function D:Report()
	local version, build, _, iface = GetBuildInfo()
	local db = ns.db
	local lines = {
		string.format("NeverQuest %s report, %s", ns.version, date("%Y-%m-%d %H:%M")),
		string.format("Client %s (%s), interface %s, locale %s", tostring(version), tostring(build), tostring(iface), GetLocale()),
		string.format("Level %d %s %s, %s", UnitLevel("player"), UnitRace("player") or "?", UnitClass("player") or "?", UnitFactionGroup("player") or "?"),
		string.format("Settings: accept=%s turnin=%s gossip=%s reward=%s | guideArrow=%s paths=%s flights=%s marker=%s | minimap=%s worldmap=%s | items=%s target=%s | party=%s",
			tostring(db.auto.accept), tostring(db.auto.turnin), tostring(db.auto.gossip), tostring(db.auto.reward),
			tostring(db.guide.autoTrack), tostring(db.nav.paths), tostring(db.nav.flights), tostring(db.nav.nativeWaypoint),
			tostring(db.pins.minimap), tostring(db.pins.worldmap), tostring(db.buttons.items), tostring(db.buttons.target), tostring(db.party.enabled)),
		"Guide: " .. (ns.char.script.name and ("scripted '" .. ns.char.script.name .. "' step " .. ns.char.script.step) or "live") ..
			(ns.char.recorder.active and (", recording " .. #ns.char.recorder.steps .. " steps") or ""),
	}
	local others = {}
	for i = 1, C_AddOns.GetNumAddOns() do
		local name = C_AddOns.GetAddOnInfo(i)
		if name and name ~= ADDON and C_AddOns.IsAddOnLoaded(i) then table.insert(others, name) end
	end
	table.insert(lines, "Other addons loaded (" .. #others .. "): " .. (#others > 0 and table.concat(others, ", ", 1, math.min(#others, 40)) or "none"))
	local paused = {}
	for name in pairs(ns.paused) do table.insert(paused, name) end
	table.insert(lines, "Paused: " .. (#paused > 0 and table.concat(paused, ", ") or "none"))
	table.insert(lines, "")
	if #db.errors == 0 then
		table.insert(lines, "No errors logged.")
	else
		table.insert(lines, "Errors (newest first):")
		for i = #db.errors, 1, -1 do
			local e = db.errors[i]
			table.insert(lines, string.format("%dx in %s (v%s): %s", e.count or 1, e.where or "?", e.version or "?", e.msg))
			if e.stack then
				local n = 0
				for stackLine in e.stack:gmatch("[^\n]+") do
					n = n + 1
					if n > 4 then break end
					table.insert(lines, "    " .. stackLine)
				end
			end
		end
	end
	ns.UI:ShowIO("export", table.concat(lines, "\n"), "NeverQuest bug report", "Press Ctrl+C to copy, then paste it to whoever is helping you.")
	return lines
end

ns:AddSlash("check", function() D:RunCheck() end, "/nq check - run a self-test and show copyable results")
ns:AddSlash("report", function() D:Report() end, "/nq report - copyable bug report with recent errors")
ns:AddSlash("clearerrors", function()
	wipe(ns.db.errors)
	ns.Print("error log cleared.")
end, "/nq clearerrors - empty the error log")
