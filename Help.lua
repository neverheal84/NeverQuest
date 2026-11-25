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
		Y .. "Discord" .. E .. ": the Discord button at the top of the main window, or " .. Y .. "/nq discord" .. E ..
			", gives you a link you can copy. Bug reports, help and suggestions each have a channel.",
		"",
		"Pick a topic on the left to learn more.")
	end },
	{ key = "guide", title = "Guide and route", text = function() return Lines(
		Y .. "The guide" .. E,
		"The Guide tab always shows your best next move. Steps are objectives, turn-ins, quest pickups and tips such as \"Time to move on\".",
		"",
		Y .. "Route planner" .. E,
		"Your objectives, turn-ins and nearby pickups are put into one short route so you don't walk back and forth. Quests worth too little XP for the trip wait for later, while a worthwhile quest right on the way is done on the same visit. Quests more than 3 levels above you wait until you're within 3 levels (the guide lists them for later with the level they open at); finished ones are handed in whatever their level. Stops are put in the shortest order that keeps every turn-in after its objective. The \"Route:\" row shows the trip's time, XP and XP per hour; " .. Y .. "/nq route" .. E .. " lists it in chat.",
		"",
		Y .. "Quest chains" .. E,
		"Quests that open follow-ups count for more, so chains you start get finished. Steps show \"chain: Name 3/7\".",
		"",
		Y .. "Clicking steps" .. E,
		"  Click: point the arrow at it.",
		"  Right-click: a menu with Skip, Drop, Go back for it and Open in quest log.",
		"  Shift+click: link the quest in chat.",
		"",
		Y .. "Skipping and going back" .. E,
		"The Skip button (or " .. Y .. "/nq skip" .. E .. ") skips the quest the arrow is on. Skipped quests, quests you drop and quests you leave open in zones you've moved on from all go on your " .. Y .. "missed list" .. E .. ": the Quests tab > Missed, or " .. Y .. "/nq missed" .. E .. ". Pick one there and choose Go back for it, and the route sends you there first. Gray quests show too when you tick Gray.",
		"",
		Y .. "Grab and drop" .. E,
		"Pickups go on the route when they're worth the walk, valued by how much XP the quest gives and how long its objectives take. In the Optimized style the guide also says which quests in your log aren't worth finishing (too slow, gone gray, in a zone you've outleveled, or needing a group); " .. Y .. "/nq drop" .. E .. " lists them. Class, profession and dungeon quests and long chains are never suggested.",
		"",
		Y .. "Recorded guides" .. E,
		Y .. "/nq record Name" .. E .. " records your route; " .. Y .. "/nq stop" .. E .. " saves it. Replay it on alts from the Guides tab, and share it with Export and Import.")
	end },
	{ key = "plan", title = "Leveling styles", text = function() return Lines(
		Y .. "Two leveling styles" .. E,
		"  " .. Y .. "Optimized 1-60" .. E .. ": at every level the guide picks the zone with the most XP per hour from the quests you can take there, travel included, and stays until another zone is clearly better. Your 1-60 plan's zones get a small edge and take over when the data is thin. Slow quests are left out and you're told which to drop.",
		"  " .. Y .. "Zone by zone" .. E .. ": the completionist way. Every quest in a zone goes on the route, gray ones too, and nothing is left out for being slow. You move on when the zone is done, or when you're four levels past it, to the best zone from where you are.",
		"",
		Y .. "It follows you" .. E,
		"Go somewhere the plan didn't say (another race's starting zone, the Barrens instead of Silverpine, a boat to the other continent) and the guide works from there: it stays while that zone has quests for you, then picks the next zone from where you are. Your plan is a tiebreaker, not a leash.",
		"",
		Y .. "/nq zones" .. E .. " lists the zones that fit your level by XP per hour. Both halves can be switched off under Options > Guide & Routes.",
		"",
		"Switch with " .. Y .. "/nq style" .. E .. ", the style button in the plan view, or Options > Guide & Routes.",
		"",
		Y .. "The 1-60 plan" .. E,
		Y .. "/nq plan" .. E .. " (or the 1-60 plan button) shows your route leg by leg with class quests, talents, riding, dual spec and dungeon windows. Browse any race and class with the Race and Class buttons; Mine goes back to yours.",
		"",
		"The Optimized routes are worked out from QuestieDB's quest data: every quest your race can take was levelled 1-60 in a simulator, and the route is the order of zones and level windows that kept you questing with the least time spent with nothing to do. Every leg is at least two levels in a zone that fits them.",
		"",
		"Quests in the zones your plan wants count for more, and a \"Time to move on\" or \"Zone done\" step points the arrow at the next zone.",
		"",
		Y .. "Dungeon quests" .. E,
		"With \"Get dungeon quests and their pre-quests first\" on (Options > Guide & Routes, or the setup wizard), the route picks up the quests for each dungeon you've ticked a couple of levels before its window. A quest that isn't open to you yet sends you to the first quest of the chain that opens it. These count for a lot more on the route than ordinary quests, and the steps say what they're for (\"pre-quest for Red Silk Bandanas (The Deadmines)\"). Dungeon quests in your log wait for the dungeon instead of sending you to its entrance alone.",
		"Choose dungeons with " .. Y .. "/nq dungeons pick" .. E .. ", the Choose dungeons button in Options, or the wizard page. " .. Y .. "/nq dungeons" .. E .. " lists them with what's waiting, and " .. Y .. "/nq dungeons <name>" .. E .. " ticks or unticks one.")
	end },
	{ key = "arrow", title = "Arrow and waypoints", text = function() return Lines(
		Y .. "Waypoint arrow" .. E,
		"Points at the guide's top step, your own waypoints (they come first), or your corpse after you release. It shows distance, ETA and coordinates, and when a target needs a special path it says what to do (enter a cave, take a tunnel, fly).",
		"The arrow itself is NeverQuest's own art, drawn well above the size it shows at, so it stays clean at any size and at every angle. Four sizes under Options > Display & Maps, and the whole panel scales separately under Scale & Text.",
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
		"Your waypoints, numbered, and a route preview of the guide's next steps joined by a line. The line goes through every stop on the route in order; turn-ins for quests you haven't finished yet are small unnumbered markers on it. The line and its thickness are under Options > Display & Maps.",
		"",
		Y .. "Quest givers" .. E,
		"Quests you can pick up show on the world map with their level in the difficulty color (green, yellow, orange). Open another zone to plan ahead. Click one for a waypoint.",
		"Hover any quest icon on either map for the quest's name and level. Dungeon, raid, elite, group and PvP quests say so; ordinary ones show nothing more.",
		"",
		Y .. "Spawns and objectives" .. E,
		"NeverQuest learns as you play: where quest mobs died, what dropped quest items, and where explore objectives ticked over. Colored dots on the world map show the spots for your open objectives; hover one for details. The guide sends you to known spots and tours them.",
		"With QuestieDB, the dots also show where your open objectives' mobs are, which mobs and objects drop your quest items, and which objects to use, before you've been there (they say \"From QuestieDB\"; spots you learn yourself replace them).",
		"The minimap shows tiny dots for your quests' spots (and your own marks), known quests near you, and NeverQuest's pins, small. All on by default. Sizes: Options > Scale & Text > Minimap pins.",
		"",
		Y .. "Marking spots" .. E,
		"  Alt+right-click the world map to mark a spawn, an objective, a mob by name or a note.",
		"  Hover a spawn dot: the first line says what it is (quest mob, drops something you need, quest object, rare) and its level if NeverQuest saw it, then the quests it belongs to and how often you've seen it there.",
		"  Dots for mobs far below you are hidden, so an old zone isn't buried under spots you've outgrown. Anything a quest in your log points at always shows, whatever its level.",
		"",
		Y .. "Nameplates and tooltips" .. E,
		"Every mob your quests want gets a small icon on its nameplate: a sword to kill, a bag when it drops something you need, and a skull on the one the guide is sending you at, with your count underneath. They are drawn on your screen only (the game no longer lets addons place raid markers) and need enemy nameplates showing. Hover a mob NeverQuest has learned as a drop source and its tooltip says which quest and how far along; in a party it shows everyone's progress. Items say which quest wants them. Options > Display & Maps and Options > NeverQuest > Tooltips.",
		"  " .. Y .. "/nq mark" .. E .. " marks your target's spawn where you stand; " .. Y .. "/nq mapnote" .. E .. " leaves a note.",
		"  Right-click a spot to set a waypoint or forget it; Shift+click removes a mark.",
		"",
		Y .. "/nq spawns" .. E .. " shows a summary; " .. Y .. "/nq spawns export" .. E .. " and " .. Y .. "import" .. E .. " share everything as text.")
	end },
	{ key = "tracker", title = "Quest tracker", text = function() return Lines(
		Y .. "Quest tracker" .. E,
		"Lists your quests on the right side of the screen, grouped by zone (your zone first) and numbered in the order the guide will do them. Each quest shows level, distance, objectives, who to turn it in to, its chain and party progress.",
		"",
		"  Click a quest: point the arrow at it.  Shift+click: link it in chat.",
		"  Right-click a quest: point the arrow, open it in the quest log, show it on the map, link it, share it with your party, abandon it, pin it, skip it or hide it.",
		"  Click a zone header: fold it up. The tracker shrinks up towards its top edge.",
		"  Right-click the tracker header: sorting and quick options. Drag the header to move it.",
		"  Drag the bottom corner to size it. It lists every quest and scrolls (mouse wheel) when they don't all fit.",
		"",
		Y .. "Blizzard's quest list" .. E,
		"By default it's emptied while NeverQuest's tracker shows. You can keep it in NeverQuest's order or leave it alone instead (Options > Tracker). " .. Y .. "/nq tracker" .. E .. " shows or hides the tracker.",
		"While it's emptied, NeverQuest also turns off the game's automatic quest watching and parks Blizzard's tracker frame out of sight, because emptying the list alone doesn't stop the game showing that frame again each time you accept or finish a quest. Both are undone the moment you stop hiding the list, and neither is ever changed during combat. If you want Blizzard's bonus objectives or scenario text visible, turn off \"Also keep Blizzard's tracker frame out of sight\" under Options > Tracker.")
	end },
	{ key = "drops", title = "Drops window", text = function() return Lines(
		Y .. "Drops window" .. E,
		"A second, smaller window for the things you still have to collect: quest item drops and anything you pick up off the ground. Each one shows the item, how many you have of how many you need, and under it the mobs you have seen it drop from with the distance to the nearest one NeverQuest knows about. Mobs you only have to kill stay with the TARGET button; this window is for what you are short of.",
		"",
		"  Click an item: point the arrow at the nearest spot you know.",
		"  Shift+click: put the item in chat.",
		"  Right-click an item: point the arrow, link it, or forget its spots.",
		"  Right-click the header: sorting, the source line, lock and hide. Drag the header to move it.",
		"",
		"It's off until you turn it on, with " .. Y .. "/nq drops" .. E .. ", the key binding, or Options > Tracker > Drops window. " .. Y .. "/nq drops list" .. E .. " prints the same list in chat.",
		"",
		"The drop sources are yours, not a shipped database: a mob is listed once you have earned credit from it, so a brand new item shows nothing until the first one drops for you.")
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
	{ key = "class", title = "Class quests", text = function() return Lines(
		Y .. "Class quests" .. E,
		"The Class tab (" .. Y .. "/nq class" .. E .. ") gathers the quests only your class gets.",
		"",
		"  At the top: any class quests in your quest log right now, read from the game. Click one to point the arrow at it. Quests Forever has added for your class show here too.",
		"  Below: a checklist of what your class has coming and at which level, what each one gives you and where it starts. Rows you have the level for say \"now\". Click a row to tick it off, and again to untick it.",
		"",
		"Every class also gets a quest at 50 that sends it into the Sunken Temple for a pick of three rare items.",
		"",
		Y .. "Profession quests" .. E,
		"The Professions button at the bottom of the tab (" .. Y .. "/nq professions" .. E .. ") lists the places a profession waits on a quest instead of a trainer: Artisan First Aid, Cooking and Fishing, the blacksmithing, leatherworking and engineering paths, and smelting dark iron. Each row shows the skill it needs against the skill you have, and says \"now\" when you have both the skill and the level. Only your own professions are listed unless you turn that off.",
		"",
		"Both sections are options under Options > Guide & Routes. Turn one off and the tab keeps the other; turn both off and the tab is removed.",
		"The checklist is written for this addon from how the classes work. Your trainer is the authority: if Forever has moved something, the quest your trainer offers is the one to follow.")
	end },
	{ key = "party", title = "Playing in a group", text = function() return Lines(
		Y .. "Party view" .. E,
		"In a party, the tracker opens with a Party section: a line for each member (how many quests you share, how many they've finished, how far away they are), quests ready to hand in together, quests they need that you can help with (\"Help:\") and quests they're on that you lack (\"They're on:\"). Click a member to point the arrow at them, click a Help line to point it at the work, click the Party header to fold it.",
		"Members without NeverQuest are included too: the game says which of your quests and nearby offers they're on, though not how far along.",
		"",
		Y .. "Party alerts" .. E,
		"A short line in your chat (with a sound) when a party member finishes an objective of a quest you share, is ready to hand one in, or when everyone is ready to hand in together. Only you see these. On by default.",
		"To turn them off: right-click the tracker's Party header, or " .. Y .. "/nq party alerts off" .. E .. " (" .. Y .. "/nq party sound off" .. E .. " for just the sound).",
		"",
		Y .. "Map help" .. E,
		"Party icons on the minimap and the zoomed-in world map mark where the work is for quests your party still needs and you can help with. Click one to point the arrow there.",
		"",
		Y .. "Party sync" .. E,
		"Party members who also run NeverQuest see each other's progress on shared quests, which objectives are done, and spawn spots one of you learns show up for the other.",
		"Switches for all of this: Options > NeverQuest > Party, right-click the tracker's Party header, or " .. Y .. "/nq party" .. E .. ".",
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
		"Quests ranks your log by XP per distance. Nearby lists quests you can pick up close by. Journal lists every quest you've turned in, and Splits compares each level's time with your fastest character.",
		"",
		Y .. "The main window" .. E,
		"Drag its bottom right corner to make it bigger or smaller; the lists show as many rows as fit. " .. Y .. "/nq reset" .. E .. " puts it back to its standard size. Buttons with a down arrow open a menu of choices.",
		"",
		Y .. "Tooltips" .. E,
		"NeverQuest's own tooltips show one line by default. Options > Display & Maps > Hover tooltips switches them off, or to every detail.")
	end },
	{ key = "automation", title = "Automation", text = function() return Lines(
		Y .. "Quests" .. E,
		"NeverQuest can accept quests and turn in finished ones for you, and pick quests in NPC dialog windows. Gray and repeatable quests are skipped by default.",
		"\"Which quests\" can be set to only the ones the route will do: quests the guide plans to do, class and profession quests, quests for your chosen dungeons and attunement, and others worth their time against your route. Elite and group quests wait for a group. Anything else you can still accept by hand.",
		"",
		Y .. "Quest rewards" .. E,
		"With several rewards to choose from, NeverQuest checks each one against what you're wearing, using the stats your class cares about, and marks the best with a green arrow. Chat says why (for example \"+6 Agility, +2 Stamina over your old belt\"). With no upgrade it marks the one that sells for the most. Under Options you can let it take upgrades, or always take the highest vendor value.",
		"",
		Y .. "Auto loot" .. E,
		"Takes everything from a loot window at once. Items waiting on a group roll are left alone, and bind-on-pickup items still ask you. " .. Y .. "/nq loot" .. E .. " turns it on or off.",
		"",
		Y .. "Group invites" .. E,
		"NeverQuest can accept group invites for you, and invite anyone who whispers a keyword. Accepting is off until you choose otherwise, and you can limit it to guildmates and friends rather than anyone: an invite is how someone pulls you into an instance, into a raid, or to wherever they are standing. Hold Shift to answer one yourself. " .. Y .. "/nq invites" .. E .. " sets both, or use Options > Automation.",
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
		"A list of every quest the game has shown any of your characters: name, level, zone, and where the quest giver stands. It's built only from the game itself, never copied from another addon or website. A slow background scan asks which quests each zone offers (one zone every couple of seconds, paused in combat), and quests you see or accept as you play are added too. Alts benefit from what your other characters have seen.",
		"",
		Y .. "Quests you can't take yet" .. E,
		"The zone scan only sees what the game would offer you right now, so on its own a low-level character would know almost nothing. A quest you can see tells the game which chain it belongs to, so NeverQuest asks for the names and levels of the rest of that chain, quests well above your level included. Asks are spread out and paused in combat. This is what fills the map in before you've played a zone.",
		"",
		Y .. "Where the data comes from" .. E,
		"NeverQuest's own data, and your own client always wins: what you have seen, what your other characters have seen, what your party and guild pass on, and the quest starts built into the addon, gathered the same way by NeverQuest's own scan. If one of them is wrong, the first time you walk past the real giver your own client corrects it, for good.",
		"Then QuestieDB fills in what NeverQuest hasn't seen yet. QuestieDB is the quest database the Questie team builds and keeps up to date. It's an addon of its own, installed with NeverQuest (the CurseForge app does that for you), and NeverQuest reads it without copying it: nothing from it is ever saved, exported or shared as NeverQuest's own. Thanks to the Questie team for it.",
		"A QuestieDB quest only gets a marker when this character can take it now or on level alone: not another race's or class's, not a profession quest without the profession and skill, not a part of a quest you aren't on, and not one behind an earlier quest you haven't done.",
		"",
		Y .. "QuestieDB, or build your own" .. E,
		"With QuestieDB (the default) the map is full from your first login, and each QuestieDB update reaches you through the CurseForge app. " .. Y .. "Build my own" .. E .. " leaves QuestieDB alone, even when it's installed, and goes by NeverQuest's own data only, so the map starts emptier and fills in as you play. The setup wizard asks; " .. Y .. "/nq db bundled on" .. E .. " or " .. Y .. "off" .. E .. " and the Options switch change it any time. " .. Y .. "/nq lib" .. E .. " says whether QuestieDB is in use.",
		"",
		Y .. "When QuestieDB's data is wrong" .. E,
		"NeverQuest notices and writes it down. Stand where QuestieDB puts a quest giver, and if the game, asked again, doesn't offer you that quest, the place is dropped for characters of your race and class (some quests are for certain races or classes only). Take a quest or hand it in well away from where QuestieDB said, and a note keeps where it really was. " .. Y .. "Ctrl+click" .. E .. " a known quest on the world map to say it isn't there yourself; that hides it for all your characters. QuestieDB itself is never changed.",
		"If the game later offers you the quest, the note settles itself. " .. Y .. "/nq db fixes" .. E .. " lists the notes, and they go out with " .. Y .. "/nq db export" .. E .. " (places only) so they can be reported to the Questie team.",
		"",
		Y .. "Building it from other players" .. E,
		"Quest starts pass between NeverQuest users in your party and your guild as they're learned. A guild is the useful one: fifty people at fifty levels across both factions know most of the world between them, and a new character inherits it over a few sessions. " .. Y .. "/nq db ask" .. E .. " asks your guild outright and gets a bounded answer from a few of them.",
		"Somewhere you have been yourself is never overwritten by someone else's report. Reports fill gaps and correct each other: two people agreeing on a spot outweighs one who disagrees, and the moment your own client sees the giver, that becomes the answer for good.",
		"",
		Y .. "Sharing it" .. E,
		Y .. "/nq db export" .. E .. " gives you a text string of the quest starts you know. Paste it to a friend, who imports it with " .. Y .. "/nq db import" .. E .. ", or send it in on Discord to be built into the addon for everyone. It carries quests and places only: no character names, no realm, nothing about you. " .. Y .. "/nq db share" .. E .. " turns party sharing on and off.",
		"",
		Y .. "Using it" .. E,
		"  " .. Y .. "/nq db" .. E .. "  your zone: known quests, how many are done, in your log, available, or for later levels",
		"  " .. Y .. "/nq db <name>" .. E .. "  find quests by name (or quest ID)",
		"  " .. Y .. "/nq db zone <zone>" .. E .. "  the same list for another zone",
		"  " .. Y .. "/nq db way <id>" .. E .. "  point the arrow at a quest's giver",
		"  " .. Y .. "/nq db scan" .. E .. "  scan every zone again now",
		"  " .. Y .. "/nq db export" .. E .. "  the quest starts you know, as text to share",
		"  " .. Y .. "/nq db import" .. E .. "  take in quest starts from someone else",
		"  " .. Y .. "/nq db ask" .. E .. "  ask your guild for the quest starts they know",
		"  " .. Y .. "/nq db map" .. E .. "  known quest starts on the world map, on or off",
		"  " .. Y .. "/nq db minimap" .. E .. "  known quest starts on the minimap, on or off",
		"  " .. Y .. "/nq db sources" .. E .. "  say in each known quest's map tooltip where its place came from (off for now)",
		"  " .. Y .. "/nq db bundled on|off" .. E .. "  use QuestieDB, or build your own",
		"  " .. Y .. "/nq lib" .. E .. "  whether QuestieDB is in use; " .. Y .. "/nq lib <id>" .. E .. " shows what it says about a quest and where that quest stands for this character",
		"  " .. Y .. "/nq db fixes" .. E .. "  where QuestieDB's data was wrong; " .. Y .. "undo <id>" .. E .. " brings one back, " .. Y .. "clear" .. E .. " forgets them all",
		"  " .. Y .. "/nq db ready" .. E .. "  whether anything is still running, and how much is known",
		"",
		Y .. "On the world map" .. E,
		"Quests you know about that aren't on offer to you right now show as faded markers with their level: ones that open in a few levels, or ones after an earlier quest. Click one for a waypoint, Ctrl+click one that isn't there to hide it. " .. Y .. "/nq db map" .. E .. " turns them off.",
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
		"  Open or close the drops window",
		"  Skip guide step",
		"  Mark a spawn where I stand")
	end },
	{ key = "news", title = "What's new", text = function() return Lines(
		Y .. "1.27.0" .. E,
		"  " .. Y .. "Route order" .. E .. ": stops go in the shortest order that keeps every turn-in after its objective. Besides reversing stretches, the route now moves single stops or runs of up to three to wherever they save walking, so it doesn't zigzag across a zone when a straighter order covers the same stops.",
		"  " .. Y .. "While you're there" .. E .. ": a worthwhile quest right on the way is done on the same visit, even when the route already fills its half hour.",
		"  " .. Y .. "Not too high" .. E .. ": quests more than 3 levels above you stay off the route until you're within 3 levels, and quests above your level count as taking longer. The guide lists them for later with the level they join at. Finished quests are handed in whatever their level.",
		"  " .. Y .. "The map line" .. E .. ": the yellow line goes through every stop on the route in order, with small unnumbered markers where unfinished quests get handed in. Before, it skipped those turn-ins and could cut straight across the map between stops the route doesn't join.",
		"  " .. Y .. "Auto-accept only the route's quests" .. E .. ": Options > NeverQuest > Which quests. Quests the guide plans to do, class and profession quests, quests for your chosen dungeons and attunement, and others worth their time are accepted; the rest you can accept by hand.",
		"  " .. Y .. "New 1-60 plans" .. E .. ": the Optimized routes for Human, Dwarf and Gnome, Night Elf, Orc and Troll, Tauren and Undead are now worked out from QuestieDB's quest data: every quest your race can take, with its level, where it's given, where its work is and where it's handed in, levelled 1-60 in a simulator that routes each zone the way the guide does. The routes keep you questing instead of sending you to zones that have run dry. Skyborne keep their route.",
		"",
		Y .. "1.26.1" .. E,
		"  " .. Y .. "Quest icon tooltips" .. E .. ": hover a quest icon on the world map or the minimap (quest givers, known quests, objectives, turn-ins, party icons) and you get the quest's name and level, plus Dungeon, Raid, Elite, Group or PvP when it's one of those. Nothing else, whatever the tooltip setting; party icons also say who needs it.",
		"",
		Y .. "1.26.0" .. E,
		"  " .. Y .. "Party view" .. E .. ": in a party, the tracker opens with a Party section: each member with how many quests you share and they've finished and how far away they are, quests to hand in together, and what they need that you can help with. Click a member to point the arrow at them, or a Help line to point it at the work.",
		"  " .. Y .. "Works without NeverQuest" .. E .. ": party members who don't run NeverQuest are included. The game says which of your quests and nearby offers they're on, though not how far along.",
		"  " .. Y .. "Party alerts" .. E .. ": a short line in your chat, with a sound, when a member finishes an objective of a quest you share, is ready to hand one in, or when everyone is ready to hand in together. Only you see these. On by default; right-click the tracker's Party header or type " .. Y .. "/nq party alerts off" .. E .. " to turn them off.",
		"  " .. Y .. "Map help" .. E .. ": party icons on the minimap and the zoomed-in world map mark where the work is for quests your party still needs.",
		"  The tracker's right-click menu on a party quest, and the guide's quest menu, have Share with party. Switches for all of it are under Options > NeverQuest > Party, and " .. Y .. "/nq party" .. E .. ".",
		"  " .. Y .. "Mobs, drops and objects from QuestieDB" .. E .. ": the spawn dots on the minimap and the world map now show where QuestieDB says your open objectives' mobs are, which mobs and objects drop your quest items, and which objects to use, before you've been there. Spots you learn yourself replace them.",
		"  " .. Y .. "On by default" .. E .. ": the minimap's dots for your quests' mobs, objects and drops, and known quests near you, are switched on for everyone with this update. Turn them off under Options > Spawns & Objectives and Options > NeverQuest.",
		"",
		Y .. "1.25.0" .. E,
		"  " .. Y .. "Truly adaptive zones" .. E .. ": the guide chooses zones from the quest data at every level now, not just from 10, and in both styles. Wherever you go (another race's starting zone on your continent, the Barrens instead of Silverpine, a boat across the sea), it works from there: it stays while that zone has quests for you, then picks the next zone from where you are. The 1-60 plan only breaks ties, or takes over when too little is known.",
		"  Zone by zone stays in whatever zone you're in until it's done, and picks the next zone by the quest data instead of strictly following the plan. A character who sails to Teldrassil at level 5 now stays and carries on to Darkshore instead of being sent home.",
		"",
		Y .. "1.24.0" .. E,
		"  " .. Y .. "Dropdowns" .. E .. ": every button and setting with choices opens a menu of them instead of stepping through them on click (leveling style, Race and Class in the plan view, gray quests, the Quests tab's view, the raid faction, and every setting in Options and the setup wizard).",
		"  " .. Y .. "Resize by dragging" .. E .. ": the main window and the quest tracker have a corner to drag. The tracker lists every quest and scrolls when they don't all fit. " .. Y .. "/nq reset" .. E .. " puts the main window back to its standard size.",
		"  " .. Y .. "Folds to the top" .. E .. ": folding the tracker or a zone in it (and the drops window) shrinks it up towards its top edge instead of the middle.",
		"  " .. Y .. "Tracker right-click" .. E .. ": Share with party and Abandon quest are always there, with Show on the map and Link in chat. Share is greyed out when you can't share.",
		"  " .. Y .. "Fewer tooltips" .. E .. ": NeverQuest's tooltips show one line by default, and none on the arrow. Options > Display & Maps > Hover tooltips: Off, One line or Full.",
		"  " .. Y .. "Minimap" .. E .. ": tiny dots for your quests' mobs and objects are on by default, and NeverQuest's minimap pins are smaller.",
		"",
		Y .. "1.23.0" .. E,
		"  " .. Y .. "Smarter zones" .. E .. ": in the Optimized style, from level 10 the guide reads every quest you can take in each zone (its XP, where its objectives are, how much there is to kill or collect) and sends you where the XP per hour is best, travel included. It stays put until another zone is clearly better and leans away from zones across the sea. " .. Y .. "/nq zones" .. E .. " shows the scores.",
		"  " .. Y .. "Skip and go back" .. E .. ": the Skip button now works on any quest step. Quests you skip, drop or leave behind in a zone go on a missed list (Quests tab > Missed, or " .. Y .. "/nq missed" .. E .. "). Choose Go back for it and the route takes you there first.",
		"  " .. Y .. "Grab and drop" .. E .. ": pickups are valued by the quest's real XP and how long it takes, and the Optimized style suggests quests worth dropping (" .. Y .. "/nq drop" .. E .. "). Right-click a quest in the guide or tracker for Skip, Drop or Go back for it.",
		"  " .. Y .. "Zone by zone is completionist" .. E .. ": every quest in the zone goes on the route, gray ones included, before you move on. Untick it under Options > Guide & Routes for the old behaviour.",
		"",
		Y .. "1.22.2" .. E,
		"  A Credits page in this window (" .. Y .. "/nq credits" .. E .. ") names QuestieDB and the people who build it. The quest database option and the login line say where the quest data comes from too.",
		"",
		Y .. "1.22.1" .. E,
		"  The new WoW Forever races are read correctly: they were being told that every race-limited quest wasn't for them.",
		"  A quest that opens after any one of several earlier quests (the same step under another race's or class's number) now opens when you've done one of them. It used to wait for all of them, which never came.",
		"  Fewer markers for quests you can't take: profession quests only show for characters with that profession and enough skill, battleground quests stop showing once you're past their level bracket, parts of a bigger quest wait until that quest is in your log, and placeholder quests the game never offers are gone.",
		"  What a quest asks of you (an earlier quest, a profession, your race) now also holds for quests NeverQuest has its own place for, so a quest another of your characters saw no longer shows as open when it isn't yet.",
		"  Dungeon quests are found by QuestieDB's own dungeon list, which catches the ones filed under a dungeon's other area number: most of Gnomeregan's, Uldaman's and Zul'Farrak's, and the new WoW Forever dungeons.",
		"  Loading QuestieDB's quests after login is spread out by time, so slower machines don't hitch, and the memory used for it is handed back once the list is built.",
		"  " .. Y .. "/nq lib <quest id>" .. E .. " now ends with where that quest stands for this character and why. " .. Y .. "/nq questiedb" .. E .. " is another name for " .. Y .. "/nq lib" .. E .. ".",
		"  The setup wizard's Quest database page says whether QuestieDB is installed. If you had switched the old library off with " .. Y .. "/nq lib off" .. E .. ", you stay on Build my own.",
		"",
		Y .. "1.22.0" .. E,
		"  Quest data now comes from QuestieDB, the quest database the Questie team builds and keeps up to date. It's installed as its own addon next to NeverQuest (the CurseForge app does that for you), so each QuestieDB update reaches you without waiting for a NeverQuest release. Thanks to the Questie team.",
		"  NeverQuest no longer ships quest data from anywhere else: the LibQuestDB library, the copy of QuestieDB's WoW Forever data and the Warcraft Wiki lookups are gone, and the download is a fraction of the size.",
		"  " .. Y .. "Build my own" .. E .. " is unchanged and never reads QuestieDB, even when it's installed. Choose it in the setup wizard, under Options > Quest database, or with " .. Y .. "/nq db bundled off" .. E .. ".",
		"  Without QuestieDB installed, NeverQuest says so once at login and works from what it has learned itself. " .. Y .. "/nq lib" .. E .. " and " .. Y .. "/nq check" .. E .. " show whether it's in use.",
		"",
		Y .. "1.21.7" .. E,
		"  New option: get dungeon quests and their pre-quests first. For each dungeon you tick, the route picks up its quests a couple of levels early, and the quests that have to come before them. They count for a lot more than ordinary quests. Choose dungeons in the setup wizard, in Options (Choose dungeons), or with " .. Y .. "/nq dungeons" .. E .. ".",
		"  Dungeon quests in your log wait for the dungeon instead of sending you to its entrance alone.",
		"  Fixed: being on the first part of a chain whose parts all share a title and giver (The Defias Brotherhood) no longer marks the later parts as done.",
		"",
		Y .. "1.21.6" .. E,
		"  Choose where quest data comes from: the bundled database (the default, a full map from your first login) or " .. Y .. "Build my own" .. E .. " from what you see in the game. The setup wizard has a page for it, Options has the switch, and " .. Y .. "/nq db bundled on|off" .. E .. " works too.",
		"  Where the bundled data is wrong, NeverQuest notes it and stops showing the wrong place: a quest giver you stood in front of that the game didn't offer, or a giver or turn-in somewhere else. Ctrl+click a known quest on the world map to say so yourself. " .. Y .. "/nq db fixes" .. E .. " lists the notes, and Export starts sends them in.",
		"",
		Y .. "1.21.5" .. E,
		"  Quests on the minimap show their level beside the marker, in its difficulty color: quests to pick up, quests you are working on and turn-ins. Known quests on the world map now use difficulty colors too. Both follow the \"Show quest levels\" option.",
		"",
		Y .. "1.21.4" .. E,
		"  NeverQuest is now free software under the GNU General Public License v3, because it includes GPLv3 quest data. LICENSE.md in the addon folder has the details and the credits.",
		"",
		Y .. "1.21.3" .. E,
		"  No more being sent to fly somewhere with no flight master. The world map's list of flight masters includes places you cannot fly to, and the route trusted it. Flights are now planned only between flight masters your own flight map has shown as reachable: open the flight map at any flight master once and flights come back, and a flight path you discover is added on the spot.",
		"",
		Y .. "1.21.2" .. E,
		"  No more being told to kill mobs you don't need. Picking a quest item off the ground while a dead mob was still targeted recorded that mob as the item's source, and from then on its nameplate, tooltip and the guide sent you after it. Loot is now matched to where the game says it came from, and the bad links learned before are cleared once.",
		"  Friendly NPCs the game links to a quest (the people you hand in to) never get a sword on their nameplate.",
		"  A mob whose tooltip once named a quest is only marked while the game still says it is part of that quest.",
		"",
		Y .. "1.21.1" .. E,
		"  A test build. A known quest's map tooltip no longer says where its place came from; " .. Y .. "/nq db sources" .. E .. " brings that line back.",
		"",
		Y .. "1.21.0" .. E,
		"  The people your quests send you to are marked. A question mark sits on the nameplate of whoever a finished quest is handed to, and an exclamation mark on someone with a quest for you, next to the sword, bag and skull that quest mobs already wear.",
		"  Point at them and the tooltip says which quest, with the same icon. That works with nameplates off.",
		"  " .. Y .. "/nq db harvest" .. E .. " asks the game about every quest the library lists, the new WoW Forever ones included: name, level, zone, and the starting place if the game will give one. About twenty minutes in the background, and it carries on where it left off. What the game answers becomes NeverQuest's own data.",
		"  The map starts full. NeverQuest now includes the LibQuestDB quest library (by Pimptasty, MIT licence), which knows where about four thousand quests start and end. Givers you can take a quest from show on the world map from your first login, and turn-ins are found even for quests nobody has handed in yet.",
		"  Places for about 730 of the quests that are new in WoW Forever, from QuestieDB's data (GPLv3, by the Questie contributors), checked against what the game told NeverQuest. They are marked as not yet seen in game and give way to anything NeverQuest sees for itself.",
		"  Routes look past the zone you are in: the next zone is chosen by how many quests are open to you there, the route picks up quests in it before you arrive, and quests that start chains count for more even on a first character.",
		"  Quests you could pick up are off the minimap now unless you ask for them: " .. Y .. "/nq db minimap" .. E .. ". The world map is the place for those.",
		"  Anything NeverQuest has seen in the game for itself still wins, and the library's data is kept apart from NeverQuest's own: it is never saved, exported or shared. " .. Y .. "/nq lib" .. E .. " shows what is loaded; " .. Y .. "/nq lib off" .. E .. " goes back to NeverQuest's own data only.",
		"  The icons sit on nameplates, so the game has to be drawing them. " .. Y .. "/nq plates show" .. E .. " turns them on for enemies and friendly NPCs. " .. Y .. "/nq plates npcs" .. E .. " turns the new icons off.",
		"",
		Y .. "1.20.1" .. E,
		"  A yellow question mark now only ever means \"hand a quest in here\". Quests you are still working on were drawn with one too, on the map, the minimap and in the guide, so the route looked as if it wanted you to turn in where the work is. They now show a sword (kill), a bag (collect) or a cog (anything else).",
		"",
		Y .. "1.20.0" .. E,
		"  A top to bottom review of the addon. Nothing new to learn; a lot that now behaves.",
		"  What other players send is checked before it is kept: quest starts and spawn spots from your party and guild must look real, titles are cleaned, and nobody can flood your saved data.",
		"  " .. Y .. "/nq db ask" .. E .. " answers arrive whole. They used to be sent faster than the game allows, so about a third of every answer was dropped. Only a few guildmates answer each ask now.",
		"  Auto-accepting invites from \"people I know\" goes by who the inviter really is, so a stranger with a guildmate's name on another realm is not let in, and Battle.net friends are recognised.",
		"  Right-click the arrow to dismiss a step and it moves to the next one instead of going blank.",
		"  Blizzard's tracker comes back inside dungeons and raids, where it shows boss objectives. Your quests and settings are handed back at logout, so removing NeverQuest leaves nothing switched off.",
		"  No more \"ready to turn in\" the moment you accept a talk-to quest.",
		"  Lighter: nothing is rebuilt while you stand still, and the arrow and minimap do far less work each frame.",
		"",
		Y .. "1.19.0" .. E,
		"  Group invites: accept automatically from guildmates and friends, and invite whoever whispers a keyword. Both off until you turn them on. " .. Y .. "/nq invites" .. E .. ".",
		"",
		Y .. "1.18.0 to 1.18.4" .. E,
		"  Quest starts ship with the addon, pass between NeverQuest users in your party and guild, and draw on the minimap as well as the world map. " .. Y .. "/nq db" .. E .. ".",
		"  NeverQuest learns quests you cannot take yet by asking the game for the rest of a chain you can see.",
		"  Blizzard's tracker no longer flashes up when you accept or finish a quest with its list hidden.",
		"  The arrow no longer tells you to fly out of a town you have already left.",
		"",
		Y .. "1.17.0" .. E,
		"  Spawn dots say what they are: hover one and the first line now says whether it's a quest mob, something that drops what you need, a quest object or a rare, with its level when NeverQuest saw it.",
		"  Mobs you have long outgrown are left off the map. Anything a quest in your log points at is always shown, whatever its level, and so is anything above you. Options > Display & Maps sets how far below to cut.",
		"",
		Y .. "1.16.1" .. E,
		"  Fixes 1.16.0: finished quests whose hand-in is only known as a zone were put above everything, so they outranked work at your feet and the arrow followed one to the middle of a zone. They now sit above travel but below what is in front of you, and never steer the arrow on their own.",
		"",
		Y .. "1.16.0" .. E,
		"  Finished quests are never left behind. One NeverQuest has no hand-in spot for used to drop to the bottom of the guide under \"later\", so the route would send you out of the zone past it. They now sit at the top, with a count of the ones waiting where you are standing.",
		"  A reminder when a profession is within ten points of its current rank, so you train the next rank on your next trip to a town instead of grinding into the ceiling.",
		"",
		Y .. "1.15.0" .. E,
		"  New Class tab: the class quests in your log, and a checklist of what your class has coming at which level, what it gives you and where it starts. " .. Y .. "/nq class" .. E .. " opens it.",
		"  Profession quests in the same tab: the quests your professions wait on, with the skill each needs against the skill you have. " .. Y .. "/nq professions" .. E .. ".",
		"  Both are options (Options > Guide & Routes); with both off the tab is removed.",
		"",
		Y .. "1.14.0" .. E,
		"  New drops window: the quest items you still have to collect, how far along each one is, and the mobs you have seen them drop from. " .. Y .. "/nq drops" .. E .. " opens it.",
		"  Quest icons on nameplates: a sword on mobs to kill, a bag on mobs that drop something you need, and a skull on the one the guide is sending you at. Drawn on your screen only. " .. Y .. "/nq plates" .. E .. " switches them.",
		"  Tooltips: mobs learned as a drop source say which quest and how far along, mobs show your party's progress, and items say which quest wants them.",
		"  The guide tells you when something in your bags beats what you're wearing, and which junk is cheapest when your bags are full.",
		"  Flights are timed the first time you take them, and counted down on the arrow after that.",
		"  New option: share each quest with your party as you pick it up (Options > NeverQuest > Party).",
		"  Kill objectives are read with your client's own wording, so the target button and spawn maps work in every language.",
		"  The waypoint arrow is NeverQuest's own art now, drawn at 256 pixels instead of borrowing the game's small one, so it stays sharp at any size and while it turns. Options > Display & Maps sets how big it is.",
		"  NeverQuest has a Discord now: the button at the top of the main window, or " .. Y .. "/nq discord" .. E .. ". Bug reports, help and suggestions each have a channel.",
		"",
		Y .. "1.13.2" .. E,
		"  A finished quest is never hidden for being gray. It was worth its XP when you did the work, so the route sends you to collect it however far you have levelled past it.",
		"  Once a pile of hand-ins is judged worth the trip, the whole pile goes on the route, instead of one quest at the end of a long walk.",
		"",
		Y .. "1.13.1" .. E,
		"  Finished quests waiting in another zone are now judged as one trip, so a pile of them gets you sent back to hand them in. One on its own still waits its turn.",
		"  A finished quest moves up the list the further you out-level it, because its XP shrinks as you go.",
		"",
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
	{ key = "credits", title = "Credits", text = function()
		-- The names come from QuestieDB's own author line when it is installed, so they stay
		-- theirs to keep up to date.
		local who = ns.Library and ns.Library:Authors()
		return Lines(
		Y .. "Quest data: QuestieDB" .. E,
		"Where quests start and end, what has to be done first, and which quests belong to which dungeon come from " .. Y .. "QuestieDB" .. E .. ", the quest database built and curated by the Questie team over many years. NeverQuest reads it as a separate addon and ships no copy of it.",
		who and ("QuestieDB's authors, in their own words: " .. who .. ".") or "Code by Logonz; data by Muehe, TheCrux (BreakBB), Drejjmit, Dyaxler, Cheeq, TechnoHunter, Yttrium and everyone else who has contributed to Questie.",
		"QuestieDB is free software under the GNU General Public License v3: github.com/Questie/QuestieDB",
		"NeverQuest is not affiliated with or endorsed by Questie. If the quest data helps you, the thanks belong to them.",
		"",
		Y .. "NeverQuest" .. E,
		"By NeverHeal84, free software under the GNU General Public License v3. Source: github.com/neverheal84/NeverQuest",
		"NeverQuest's own quest starts were gathered in game by NeverQuest and the players who sent theirs in. Thank you to everyone who tests it and reports what's wrong.")
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
		Y .. "Settings" .. E .. " are saved per account (" .. Y .. "NeverQuestDB" .. E .. ") and per character (" .. Y .. "NeverQuestCharDB" .. E .. ").",
		"",
		Y .. "Still stuck?" .. E .. " " .. Y .. "/nq discord" .. E .. " gives you a link you can copy. Paste the output of " ..
			Y .. "/nq report" .. E .. " in the bug reports channel and say what you were doing; that report has your version, client and recent errors in it.")
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
ns:AddSlash("discord", function()
	if ns.UI and ns.UI.ShowDiscord then ns.UI:ShowDiscord() end
	ns.Print("Discord: " .. ns.DISCORD)
end, "/nq discord - the NeverQuest Discord: bug reports, help and suggestions")
ns:AddSlash("news", function() Help:Open("news") end, "/nq news - what changed in recent versions")
ns:AddSlash("credits", function() Help:Open("credits") end, "/nq credits - who made the quest data NeverQuest reads, and NeverQuest itself")
ns:AddSlash("commands", PrintCommands, "/nq commands - list every command in chat")
