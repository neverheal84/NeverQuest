-- NeverQuest help: an in-game guide to every feature, a full command list and troubleshooting.
-- /nq help opens it, /nq help <topic> jumps to a topic, /nq commands lists commands in chat.

local ADDON, ns = ...
local Help = {}
ns.Help = Help

local W, H, LIST_W = 680, 548, 170
local Y = "|cffffd100"   -- heading color
local E = "|r"

local function Lines(...) return table.concat({ ... }, "\n") end

Help.TOPICS = {
	{ key = "start", title = "Getting started", text = function() return Lines(
		Y .. "Getting started" .. E,
		"",
		"NeverQuest plans your leveling route, points the way and tracks your quests. Most of it works the moment you log in:",
		"",
		"  1. Open the main window with " .. Y .. "/nq" .. E .. " or the minimap button.",
		"  2. The " .. Y .. "Guide" .. E .. " tab shows your best next steps. The arrow follows the top one.",
		"  3. Accept quests as usual. The guide plans one short route through them.",
		"  4. The tracker on the right lists your quests in the order you'll do them.",
		"",
		Y .. "Setup wizard" .. E .. ": " .. Y .. "/nq setup" .. E .. " walks through the main settings in a few steps.",
		Y .. "Options" .. E .. ": " .. Y .. "/nq options" .. E .. ", or Esc > Options > AddOns > NeverQuest. Almost every feature can be turned off.",
		Y .. "Tooltips" .. E .. ": hover rows, pins and buttons for details and what clicks do.",
		"",
		"Pick a topic on the left to learn more.")
	end },
	{ key = "guide", title = "Guide and route", text = function() return Lines(
		Y .. "The guide" .. E,
		"The Guide tab always shows your best next move. Steps are objectives, turn-ins, quest pickups and tips such as \"Time to move on\".",
		"",
		Y .. "Route planner" .. E,
		"Your objectives, turn-ins and nearby pickups are put into one short route so you don't walk back and forth. Quests worth too little XP for the trip wait for later. The \"Route:\" row shows the trip's time, XP and XP per hour; " .. Y .. "/nq route" .. E .. " lists it in chat.",
		"",
		Y .. "Quest chains" .. E,
		"Quests that open follow-ups count for more, so chains you start get finished. Steps show \"chain: Name 3/7\".",
		"",
		Y .. "Clicking steps" .. E,
		"  Click: point the arrow at it.",
		"  Right-click: open the quest in your quest log.",
		"  Shift+click: link the quest in chat.",
		"",
		Y .. "Recorded guides" .. E,
		Y .. "/nq record Name" .. E .. " records your route; " .. Y .. "/nq stop" .. E .. " saves it. Replay it on alts from the Guides tab, and share it with Export and Import.")
	end },
	{ key = "plan", title = "Leveling styles", text = function() return Lines(
		Y .. "Two leveling styles" .. E,
		"  " .. Y .. "Optimized 1-60" .. E .. ": hops between zones at the right levels, leaving a zone when its level window ends and coming back for leftovers when they're worth more.",
		"  " .. Y .. "Zone by zone" .. E .. ": stays in a zone until its useful quests run out, then moves on.",
		"",
		"Switch with " .. Y .. "/nq style" .. E .. ", the style button in the plan view, or Options > Guide & Routes.",
		"",
		Y .. "The 1-60 plan" .. E,
		Y .. "/nq plan" .. E .. " (or the 1-60 plan button) shows your route leg by leg with class quests, talents, riding, dual spec and dungeon windows. Browse any race and class with the Race and Class buttons; Mine goes back to yours.",
		"",
		"Quests in the zones your plan wants count for more, and a \"Time to move on\" or \"Zone done\" step points the arrow at the next zone.")
	end },
	{ key = "arrow", title = "Arrow and waypoints", text = function() return Lines(
		Y .. "Waypoint arrow" .. E,
		"Points at the guide's top step, your own waypoints (they come first), or your corpse after you release. It shows distance, ETA and coordinates, and when a target needs a special path it says what to do (enter a cave, take a tunnel, fly).",
		"",
		"  Right-click: clear the current waypoint.  Shift+right-click: clear all.  Drag: move it.",
		"",
		Y .. "Waypoints" .. E,
		"  " .. Y .. "/way 45.2 63.8 Innkeeper" .. E .. "  in your zone",
		"  " .. Y .. "/way Westfall 52 30" .. E .. "  in another zone",
		"  " .. Y .. "/way list" .. E .. ", " .. Y .. "clear" .. E .. ", " .. Y .. "next" .. E .. ", " .. Y .. "closest" .. E .. ", " .. Y .. "here" .. E,
		"  Alt+click the world map to drop a waypoint. Blizzard's own map pin (Ctrl+click) is followed too.",
		"",
		"If another addon owns /way, use " .. Y .. "/nqway" .. E .. ".")
	end },
	{ key = "maps", title = "Maps and spawns", text = function() return Lines(
		Y .. "World map" .. E,
		"Your waypoints, numbered, and a route preview of the guide's next steps joined by a line. The line and its thickness are under Options > Display & Maps.",
		"",
		Y .. "Quest givers" .. E,
		"Quests you can pick up show on the world map with their level in the difficulty color (green, yellow, orange). Open another zone to plan ahead. Click one for a waypoint.",
		"",
		Y .. "Spawns and objectives" .. E,
		"NeverQuest learns as you play: where quest mobs died, what dropped quest items, and where explore objectives ticked over. Colored dots on the world map show the spots for your open objectives; hover one for details. The guide sends you to known spots and tours them.",
		"",
		Y .. "Marking spots" .. E,
		"  Alt+right-click the world map to mark a spawn, an objective, a mob by name or a note.",
		"  " .. Y .. "/nq mark" .. E .. " marks your target's spawn where you stand; " .. Y .. "/nq mapnote" .. E .. " leaves a note.",
		"  Right-click a spot to set a waypoint or forget it; Shift+click removes a mark.",
		"",
		Y .. "/nq spawns" .. E .. " shows a summary; " .. Y .. "/nq spawns export" .. E .. " and " .. Y .. "import" .. E .. " share everything as text.")
	end },
	{ key = "tracker", title = "Quest tracker", text = function() return Lines(
		Y .. "Quest tracker" .. E,
		"Lists your quests on the right side of the screen, grouped by zone (your zone first) and numbered in the order the guide will do them. Each quest shows level, distance, objectives, who to turn it in to, its chain and party progress.",
		"",
		"  Click a quest: point the arrow at it.",
		"  Right-click a quest: pin it, hide it, share it, or open it in the quest log.",
		"  Click a zone header: collapse it.",
		"  Right-click the tracker header: sorting and quick options. Drag the header to move it.",
		"",
		Y .. "Blizzard's quest list" .. E,
		"By default it's emptied while NeverQuest's tracker shows. You can keep it in NeverQuest's order or leave it alone instead (Options > Tracker). " .. Y .. "/nq tracker" .. E .. " shows or hides the tracker.")
	end },
	{ key = "raids", title = "Raid attunements", text = function() return Lines(
		Y .. "Raid attunements" .. E,
		"The Raids tab (" .. Y .. "/nq raids" .. E .. ") lists every step of the Onyxia's Lair attunement for your faction: who gives it, where, what to do, and whether you need a group or a dungeon.",
		"",
		"  Steps tick off as you play: finished quests, turn-ins, the quest you're on, or the amulet in your bags.",
		"  Right-click a step to mark it done or not done yourself.",
		"  Click the raid row to follow it: its next step joins your guide (first once you're at the level cap).",
		"  \"Show Horde/Alliance\" browses the other faction's chain.",
		"",
		"The Barrow Deeps and Hyjal Summit need no attunement. Raid details may change as the raids open; right-click a step if it ticks off wrongly.")
	end },
	{ key = "party", title = "Playing in a group", text = function() return Lines(
		Y .. "Party sync" .. E,
		"Party members who also run NeverQuest see each other's progress on shared quests, and spawn spots one of you learns show up for the other.",
		"",
		Y .. "Party catch-up" .. E,
		"The guide and route adapt so everyone keeps up: shared quests first, turn-ins wait while someone still needs that quest (with a \"Help\" step back to its objective), quests a party member is on count for more, and zones are picked for the lowest level in the party. \"Share with your party\" rows share a quest when clicked.",
		"",
		Y .. "Party announcements" .. E,
		"Your group hears about finished objectives, quests ready to turn in and raid attunement steps in party chat. Turn-ins can be added; every type has its own switch under Options.",
		"  " .. Y .. "/nq announce off" .. E .. " / " .. Y .. "on" .. E .. "  all of them",
		"  " .. Y .. "/nq announce test" .. E .. "  send a test line")
	end },
	{ key = "buttons", title = "Buttons, XP and journal", text = function() return Lines(
		Y .. "Quest item bar" .. E,
		"Usable quest items for your next steps, with cooldowns. Keybindable.",
		"",
		Y .. "Target button" .. E,
		"Targets the NPC or mob for your next step. NPC names are learned from your quest conversations. The TARGET button on the quest item bar is off by default: turn it on under Options > Display & Maps > Buttons, or with " .. Y .. "/nq buttons target" .. E .. ". The key binding (Target next NPC or mob) works either way.",
		"",
		Y .. "XP panel" .. E,
		"XP per hour, time to level, quests or kills to level and rested XP. Right-click it to open the main window. " .. Y .. "/nq xp" .. E .. " prints the numbers in chat.",
		"",
		Y .. "Quests, Nearby and Journal tabs" .. E,
		"Quests ranks your log by XP per distance. Nearby lists quests you can pick up close by. Journal lists every quest you've turned in, and Splits compares each level's time with your fastest character.")
	end },
	{ key = "automation", title = "Automation", text = function() return Lines(
		Y .. "Quests" .. E,
		"NeverQuest can accept quests and turn in finished ones for you, and pick quests in NPC dialog windows. Gray and repeatable quests are skipped by default.",
		"",
		Y .. "Quest rewards" .. E,
		"With several rewards to choose from, NeverQuest checks each one against what you're wearing, using the stats your class cares about, and marks the best with a green arrow. Chat says why (for example \"+6 Agility, +2 Stamina over your old belt\"). With no upgrade it marks the one that sells for the most. Under Options you can let it take upgrades, or always take the highest vendor value.",
		"",
		Y .. "Auto loot" .. E,
		"Takes everything from a loot window at once. Items waiting on a group roll are left alone, and bind-on-pickup items still ask you. " .. Y .. "/nq loot" .. E .. " turns it on or off.",
		"",
		Y .. "Sell junk" .. E,
		"Gray items are sold when you open a vendor, and chat says what they brought in. Changed your mind? The vendor's Buyback tab has the most recent ones. " .. Y .. "/nq junk" .. E .. " sells them now at a vendor, or tells you what they're worth anywhere else.",
		"",
		Y .. "Repairs" .. E,
		"Opening a vendor that can repair fixes all your gear and says what it cost. It can use guild funds first when your rank allows it (" .. Y .. "/nq repair guild" .. E .. "). " .. Y .. "/nq repair" .. E .. " repairs now at a vendor.",
		"",
		Y .. "Hold Shift" .. E .. " while talking to an NPC, looting, or opening a vendor to skip automation that time.")
	end },
	{ key = "upkeep", title = "Reminders and travel", text = function() return Lines(
		Y .. "Quest log full" .. E,
		"When your log is full the guide shows which quests to drop first: failed, gray, far away, or little XP for the walk. Quests ready to hand in and your attunement chain are never suggested. Talking to a quest giver with a full log says it in chat too.",
		"",
		Y .. "Supplies and bags" .. E,
		"The guide reminds you when food and water run low, when a hunter's ammo runs low, and when your bags are nearly full. With full bags it lists quest items you can safely delete because their quest is already done.",
		"",
		Y .. "Rested XP" .. E,
		"Logging out away from an inn or city gives you no rested XP. NeverQuest reminds you, and mentions your Cozy Sleeping Bag if you have one.",
		"",
		Y .. "Flight paths" .. E,
		"A guide step points you to any flight master in your zone you haven't talked to yet. Close ones go right after your next step.",
		"",
		Y .. "Hearthstone" .. E,
		"NeverQuest notes where you bind your hearthstone. When it's ready, nothing is left near you, and finished quests are handed in near your inn, the guide's first step says to hearth back, and the hearthstone appears on your quest item bar. At an inn far from your hearth spot it can suggest binding there.",
		"",
		Y .. "Session summary" .. E,
		Y .. "/nq session" .. E .. " shows time played, XP and XP per hour, levels, quests, kills, gold and deaths since you logged in.",
		"",
		Y .. "Asking for a group" .. E,
		"Ctrl-click an elite or group quest in the guide (or use its right-click menu in the tracker) to put a looking-for-group message with the quest link in your chat box. Nothing is sent until you press Enter. " .. Y .. "/nq lfg" .. E .. " does it for your next elite quest.")
	end },
	{ key = "database", title = "Quest database", text = function() return Lines(
		Y .. "What it is" .. E,
		"A list of every quest the game has shown any of your characters: name, level, zone, and where the quest giver stands. It's built only from the game itself. A slow background scan asks which quests each zone offers (one zone every couple of seconds, paused in combat), and quests you see or accept as you play are added too. Alts benefit from what your other characters have seen.",
		"",
		Y .. "Using it" .. E,
		"  " .. Y .. "/nq db" .. E .. "  your zone: known quests, how many are done, in your log, available, or for later levels",
		"  " .. Y .. "/nq db <name>" .. E .. "  find quests by name (or quest ID)",
		"  " .. Y .. "/nq db zone <zone>" .. E .. "  the same list for another zone",
		"  " .. Y .. "/nq db way <id>" .. E .. "  point the arrow at a quest's giver",
		"  " .. Y .. "/nq db scan" .. E .. "  scan every zone again now",
		"",
		Y .. "On the world map" .. E,
		"Quests you know about that aren't on offer to you right now show as faded markers with their level: ones that open in a few levels, or ones after an earlier quest. Click one for a waypoint. " .. Y .. "/nq db map" .. E .. " turns them off.",
		"",
		Y .. "Questie" .. E,
		"If you also run Questie, NeverQuest leaves quest givers and spawn spots on the maps to it, so they aren't drawn twice. Your guide, route and arrow keep working. " .. Y .. "/nq questie" .. E .. " switches this.")
	end },
	{ key = "commands", title = "All commands", text = function()
		local out = { Y .. "All commands" .. E, "", "Type these in chat. " .. Y .. "/neverquest" .. E .. " works in place of " .. Y .. "/nq" .. E .. ".", "" }
		local lines = {}
		for _, line in ipairs(ns.slashHelp) do table.insert(lines, line) end
		table.sort(lines)
		for _, line in ipairs(lines) do
			local cmd, what = line:match("^(%S+[^%-]-)%s+%-%s+(.+)$")
			if cmd then
				table.insert(out, "  " .. Y .. cmd .. E .. "  " .. what)
			else
				table.insert(out, "  " .. line)
			end
		end
		return table.concat(out, "\n")
	end },
	{ key = "keys", title = "Key bindings", text = function() return Lines(
		Y .. "Key bindings" .. E,
		"Esc > Options > Keybindings > AddOns > NeverQuest:",
		"",
		"  Open or close NeverQuest",
		"  Use quest item 1 and quest item 2",
		"  Target next NPC or mob",
		"  Skip guide step",
		"  Mark a spawn where I stand")
	end },
	{ key = "news", title = "What's new", text = function() return Lines(
		Y .. "1.13" .. E,
		"  Reminders in the guide (full log, supplies, bags, flight paths, hearth) can be right-clicked away until you log in again.",
		"  Two-handed weapons are compared with your main hand and off-hand together.",
		"  A reward is never judged or taken while the game is still loading its stats.",
		"  The quest database scan waits outside dungeons and battlegrounds and no longer redraws the guide and maps for every zone it checks.",
		"  A new flight path drops its guide step the moment you learn it.",
		"",
		Y .. "1.12" .. E,
		"  Reward upgrades: the best quest reward for your class gets a green arrow.",
		"  Auto repair, with guild funds if you want (" .. Y .. "/nq repair" .. E .. ").",
		"  Quest database: " .. Y .. "/nq db" .. E .. " knows every quest your characters have been shown.",
		"  Reminders: full quest log, food and water, ammo, bags, rested XP.",
		"  Flight paths you're missing and when to hearth back.",
		"  " .. Y .. "/nq session" .. E .. " for a session summary, " .. Y .. "/nq lfg" .. E .. " to ask for a group.",
		"  The TARGET button is off by default (" .. Y .. "/nq buttons target" .. E .. ").",
		"",
		Y .. "1.11" .. E,
		"  Setup wizard, this help window, auto loot and junk selling, hand-ins in other zones, a smaller button bar.")
	end },
	{ key = "trouble", title = "Troubleshooting", text = function() return Lines(
		Y .. "Something isn't working" .. E,
		"  " .. Y .. "/nq check" .. E .. " runs a self-test on your client and shows what's working, in a window you can copy.",
		"  " .. Y .. "/nq report" .. E .. " gives a copyable bug report with recent errors.",
		"  " .. Y .. "/nq debug" .. E .. " shows what NeverQuest is doing in chat.",
		"",
		Y .. "Common fixes" .. E,
		"  The guide is empty: open the world map for a moment so your zone's quests load, or check the Nearby tab.",
		"  A panel is off screen: " .. Y .. "/nq reset" .. E .. " puts panels back.",
		"  A feature stopped: if it hit repeated errors NeverQuest pauses just that feature and tells you; " .. Y .. "/reload" .. E .. " brings it back.",
		"  Dots or steps point somewhere odd: right-click the spot and forget it; spots improve as you play.",
		"",
		Y .. "Settings" .. E .. " are saved per account (" .. Y .. "NeverQuestDB" .. E .. ") and per character (" .. Y .. "NeverQuestCharDB" .. E .. ").")
	end },
}

function Help:Find(query)
	query = (query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if query == "" then return self.TOPICS[1] end
	for _, t in ipairs(self.TOPICS) do if t.key == query then return t end end
	for _, t in ipairs(self.TOPICS) do if t.title:lower():find(query, 1, true) then return t end end
	-- Any word of the query in a topic's text.
	for _, t in ipairs(self.TOPICS) do
		if t.text():lower():find(query, 1, true) then return t end
	end
end

function Help:Create()
	if self.frame then return self.frame end
	local U = ns.UI
	local f = CreateFrame("Frame", "NeverQuestHelp", UIParent, "BackdropTemplate")
	f:SetSize(W, H)
	f:SetPoint("CENTER", 0, 40)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	ns.ApplyBackdrop(f, 0.97)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	table.insert(UISpecialFrames, "NeverQuestHelp")
	self.frame = f

	local logo = f:CreateTexture(nil, "ARTWORK")
	logo:SetTexture(ns.LOGO)
	logo:SetSize(40, 40)
	logo:SetPoint("TOPLEFT", 14, -10)
	f.logo = logo
	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -4)
	title:SetText("NeverQuest Help")
	local by = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	by:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	by:SetText("v" .. ns.version .. "  ·  by " .. ns.AUTHOR)
	f.by = by
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	-- Topic list
	f.buttons = {}
	for i, t in ipairs(self.TOPICS) do
		local b = U.Button(f, t.title, LIST_W, function() Help:Show(t.key) end)
		b:SetPoint("TOPLEFT", 14, -62 - (i - 1) * 25)
		f.buttons[t.key] = b
	end

	-- Text, scrolling
	local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", LIST_W + 30, -62)
	scroll:SetPoint("BOTTOMRIGHT", -34, 48)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(W - LIST_W - 70, 400)
	scroll:SetScrollChild(content)
	local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("TOPLEFT", 4, -4)
	text:SetWidth(W - LIST_W - 78)
	text:SetJustifyH("LEFT")
	text:SetJustifyV("TOP")
	text:SetSpacing(3)
	f.scroll, f.content, f.text = scroll, content, text

	local setup = U.Button(f, "Setup wizard", 120, function() f:Hide() ns.Setup:Open() end)
	setup:SetPoint("BOTTOMRIGHT", -16, 14)
	local opts = U.Button(f, "Options", 90, function() f:Hide() ns.UI:OpenOptions() end)
	opts:SetPoint("RIGHT", setup, "LEFT", -8, 0)
	local check = U.Button(f, "Self-test", 90, function() ns.slash.check() end)
	check:SetPoint("RIGHT", opts, "LEFT", -8, 0)
	return f
end

function Help:Show(key)
	local f = self:Create()
	local topic = self:Find(key) or self.TOPICS[1]
	self.current = topic.key
	for k, b in pairs(f.buttons) do
		if k == topic.key then b:LockHighlight() else b:UnlockHighlight() end
	end
	f.text:SetText(topic.text())
	local h = (f.text.GetStringHeight and f.text:GetStringHeight()) or 400
	f.content:SetHeight(math.max(400, (h or 0) + 16))
	if f.scroll.SetVerticalScroll then f.scroll:SetVerticalScroll(0) end
	return topic
end

function Help:Open(key)
	local f = self:Create()
	local topic = self:Show(key)
	f:Show()
	return topic
end

local function PrintCommands()
	ns.Print("commands (" .. Y .. "/nq help" .. E .. " explains them):")
	for _, line in ipairs(ns.slashHelp) do DEFAULT_CHAT_FRAME:AddMessage("   " .. line) end
end

-- /nq help [topic]: replaces the plain chat list with the help window.
ns.slash.help = function(arg)
	local topic = Help:Find(arg)
	if not topic then
		ns.Print("no help topic matches \"" .. tostring(arg) .. "\"; showing the topics instead.")
	end
	Help:Open(topic and topic.key or nil)
end
table.insert(ns.slashHelp, "/nq help [topic] - how everything works (topics: start, guide, plan, arrow, maps, tracker, raids, party, buttons, automation, upkeep, database, commands, keys, news, trouble)")
ns:AddSlash("news", function() Help:Open("news") end, "/nq news - what changed in recent versions")
ns:AddSlash("commands", PrintCommands, "/nq commands - list every command in chat")
