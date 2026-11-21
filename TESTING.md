# NeverQuest first test session

About 75 minutes. Do the steps in order; skip any that don't apply to where you are.

## Before you start

1. Install **BugSack** and **BugGrabber** (they catch and show errors).
2. Replace your `NeverQuest` folder with the new one, then log in.

## The checklist

1. **Login.** Chat says "NeverQuest 1.11.4 by NeverHeal84 loaded". Stand somewhere outdoors and run `/nq check`. Copy the window text (Ctrl+C) and save it to send later.
2. **Panels.** `/nq` opens the window and all six tabs switch. The XP panel and arrow show up. Drag them where you like, then `/nq lock`.
3. **Options.** Esc > Options > AddOns > NeverQuest. All six pages open (NeverQuest, Guide & Routes, Tracker, Display & Maps, Spawns & Objectives, Scale & Text) and scroll if they're long. Flip a couple of settings and back. On Scale & Text, try a bigger text size and a different font: the main window, tracker, XP panel and arrow should all change.
4. **Quests and Nearby tabs.** Your quest log shows XP and distances. Nearby lists quests to pick up (open the world map once if it's empty).
5. **Guide and arrow.** The Guide tab's top step matches where the arrow points. Walk toward it: the distance drops and the arrow turns green when you face it. **Check the arrow isn't mirrored** (it should point left when the target is on your left).
6. **Quest NPCs.** Talking to a quest giver auto-accepts; holding Shift skips that. Finished quests turn in by themselves. With several reward choices, chat suggests the highest vendor value.
7. **Waypoints.** `/way 50 50 Test`: the arrow, a minimap pin and a world map pin appear. Walk there and chat says "arrived". Alt+click the world map to add one. Ctrl+click (Blizzard's pin) and the arrow follows it too.
8. **Routes.** Target something inside a cave or building, or in another zone. The arrow should send you to the entrance or exit first and show the game's directions, and the Guide tab shows "via:". If you have two or more flight points and pick a far target, it should say "Fly from ... to ...".
9. **Minimap pins.** Quest givers and turn-ins appear at the right spots. If you use a rotating minimap (Blizzard setting), check that the pins rotate with it.
10. **World map.** You see numbered guide steps joined by a line from where you stand. Turn off "Lines joining the route steps" (Display & Maps > World map): the line goes, the numbers stay.
11. **Quest item button.** On a quest with a usable item, a button appears and works. Bind it under Options > Keybindings > AddOns > NeverQuest.
12. **Target button.** It's off by default now: the quest item bar shows no TARGET pill. Turn it on with `/nq buttons target`; on a kill quest it shows the mob's name and clicking it targets one nearby. With the pill off, the "Target next NPC or mob" key binding still targets.
13. **Combat.** Fight with the item button showing: no errors, and the buttons update after the fight. If you die, release: the arrow should point to your corpse, and switch back to your route after you resurrect.
14. **Recorder.** `/nq record Test`, do two or three quests, visit a vendor, `/nq note hello`, then `/nq stop`. The Guides tab lists it and Export shows text.
15. **Journal.** Turn-ins show under Journal > History. After a level-up, Splits shows the level time.
16. **1-60 plan.** `/nq plan` shows your race and class route (Optimized 1-60 by default) with your current leg marked. Click the style button at the top right to switch to Zone by zone and back. Try the Race and Class buttons, then Mine. In `/nq check`, the "Leveling plan" line should find all (or nearly all) zones. At an even level, the guide shows a trainer reminder that clears when you visit your trainer.
17. **Spawns and objectives.** Turn on enemy nameplates. On a kill quest, kill two or three mobs, then open the world map: colored dots appear where they died, and hovering one names the mob and quest. On a drop quest, loot a quest item and check the dot names the mob that dropped it. Walk near other quest mobs out of combat and dots should appear for them too. The guide step should say "known spot", and once you reach a spot the arrow moves on to the next one.
18. **Marks.** Alt+right-click the world map: the menu lists your target (if any), your open objectives, a typed name and a note. Make one of each kind you like, then right-click a dot and pick "Forget this spot", and Shift+click a mark to remove it. Try `/nq mark` with a mob targeted. In `/nq check`, the "Spawn learning" line should say "all game functions present".
19. **Route planner.** With four or more quests in one zone, the Guide tab's steps should follow one route (numbered, with "Then turn in" steps and a "Route:" summary row), and `/nq route` should list it. Turn-ins near an objective should come right before or after it, not after a trip across the zone. Far, low-XP quests show as "later".
20. **Quest chains.** Turn in a quest whose NPC immediately offers the next one: the next quest's step or tracker line should say "chain" or "follow-up". In `/nq check`, the "Quest chains" line shows how many of your quests are in a game quest line.
21. **Tracker.** The NeverQuest tracker is on the right, grouped by zone (current zone first) and numbered in guide order. Blizzard's quest list should be empty (its bonus objectives and other sections stay). Click a zone header, right-click the tracker header and a quest, and drag the header to move it. Try "Sort by priority" and "Leave it alone" for Blizzard's list on the Tracker page: Leave should give your tracked quests back.
22. **Quest givers.** Open the world map in your zone: quest givers show "!" with a colored level number, and gray or red quests aren't there. Open a neighboring zone: its quest givers appear after a moment. Turn on "Include gray" and "Include red" under Display & Maps > Quest givers and check they appear. Click a quest giver for a waypoint. In `/nq check`, the "Quest givers on maps" line counts them by color.
23. **Leveling styles.** On Optimized, level past your current leg's window while still in that zone: a "Time to move on: head to ..." step should appear after any turn-ins next to you, and the arrow should go there. On Zone by zone, the guide should keep you in your zone until its quests are done, then show "Zone done: head to ...". In `/nq check`, the "Leveling style" line says where it wants you.
24. **Minimap button.** The NeverQuest button sits on the minimap's edge. Click it (window opens), Shift+click (tracker toggles), right-click (quick settings), and drag it around the edge. `/reload` keeps its spot.
25. **Party (optional).** With a friend who also runs NeverQuest, the Quests tab shows their progress on shared quests, and a spot one of you learns or marks shows up for the other. With party catch-up on: the guide shows a "Party catch-up" row, quests you share come first, a quest you've finished that your friend hasn't shows "waiting for ..." on its turn-in (and a "Help ..." step if a spot is known), "Share with your party" rows share when clicked, and a "Regroup" step appears when you're far apart.

26. **Raid attunements.** Open the Raids tab (`/nq raids`): your faction's Onyxia's Lair chain, The Barrow Deeps and Hyjal Summit (no attunement). Click "Show Horde/Alliance" to browse the other one. Right-click a step to mark it done, again to undo. Click the raid row: the footer says "Following", and the guide shows the chain's next step (second while leveling, first at 60). If you're on a chain quest already, that step says "on it" and everything before it is done. In `/nq check`, the "Raid attunements" line shows your progress.
27. **Party announcements.** In a party, `/nq announce test` posts "NeverQuest: announcements are working." in party chat. Finish one objective of a quest with two or more objectives (party chat shows "objective done"), then finish the quest ("complete, ready to turn in"). Turn on "Quests turned in" under Options > NeverQuest > Party announcements and hand something in. `/nq announce off` should stop all of it. In `/nq check`, the "Party announcements" line says where messages go.

28. **Map route.** With a few unfinished quests, open the world map: the numbered route and its line go to quest objectives (and finished turn-ins and pickups), not to the NPCs where unfinished quests get handed in. Turn on "Include turn-ins for unfinished quests" under Display & Maps > World map and the "Then turn in" stops join the line. If a step says "the map only marks the quest NPC", tell me which quest.
29. **Setup wizard.** `/nq setup` opens the wizard with the NeverQuest logo and "by NeverHeal84" at the top. Step through every page with Next and Back, change a setting or two (they should take effect straight away), and Finish. "Use recommended" on the first page jumps to the last page. On a fresh install (no NeverQuest settings saved yet) it opens by itself a few seconds after login; an existing install just gets a one-time chat note about it.
30. **Help.** `/nq help` opens the help window; click through the topics on the left and scroll a long one. `/nq help raids` opens the raid topic, `/nq commands` lists commands in chat, and the Help button in the main window and the minimap menu open it too. The main window title and the minimap button show the logo.

31. **Auto loot.** Kill something and loot it: the window empties at once. Hold Shift while looting the next one: the window stays open. In a group with roll items, those are left for the roll. `/nq loot off` turns it off.
32. **Sell junk.** With a few gray items in your bags, open a vendor: they sell and chat says "sold N junk items for ...". Check the Buyback tab. Open a vendor again holding Shift with junk in your bags: nothing sells. Away from a vendor, `/nq junk` says what your junk is worth. In `/nq check`, the "Sell junk" line says which way it sells on your client.

33. **Button bar.** With a quest that needs a mob killed, the bar near the bottom of the screen shows the NeverQuest logo on the left and a "TARGET" pill with the mob's name (no floating name above it). Click the pill to target the mob; bind "Target next NPC or mob" and the key shows on the pill. Quest item buttons are rounded with a gold frame. Drag the logo to move the bar. Send a screenshot if anything looks off.

34. **"...and that note you found".** With it in your log (Alliance), the guide's turn-in step says "at the Burned-Out Remains, The Barrens" with directions and "Cozy Sleeping Bag 1/6"; the arrow and world map point to the ruined tower south of Camp Taurajo, and the tracker lists it under The Barrens. Each later step (Stepping Stones, Scramble, Wet Job, Eagle's Fist, This Must Be The Place) should point at its spot too. Tell me if any spot is off.

35. **Hand-ins in another zone.** Finish a quest that's handed in somewhere other than where you got it (like the Stonetalon/Barrens one in your screenshot). The world map's numbered "?" and the guide step should point at the real hand-in, or say "somewhere in <zone>" / "where they are isn't known yet"; never back at the pickup spot. If one still points at the pickup spot, send the quest name and what its quest log text says.

36. **Shared and remote quests.** Accept a quest a party member shares, and hand in a quest through a pop-up (if you find one): neither should leave a "?" at the spot where you were standing. Click a finished quest in the tracker: the arrow goes to its hand-in, with the NPC's name when NeverQuest knows it.

37. **Reward upgrades.** Hand in a quest with a choice of rewards. A green arrow marks one and chat says why ("... is an upgrade over [your item] (+3 Agility, ...)" or "no upgrade here; highest vendor value: ..."). Check the pick makes sense for your class; send the quest name and rewards if it doesn't. Under Options > NeverQuest, "Take upgrades, else value" should take it for you.

38. **Repairs.** With damaged gear, open a vendor that repairs (a blacksmith or armorer): chat says "repaired everything for ...". Open one holding Shift: nothing happens. In a guild that pays repairs, `/nq repair guild` and repair again: chat says "(guild funds)".

39. **Reminders.** Fill your quest log to the limit: a guide row says it's full and names quests to drop, and talking to a quest giver says it in chat. Drop to under 10 food and water: a row says so. With 3 or fewer free bag slots: a row says so and names quest items you can delete. Start a logout in the open world: chat reminds you about rested XP.

40. **Flight paths and hearth.** In a zone with a flight master you haven't met, a "Get the flight path" step appears (near the top when you're close); click it and the arrow points there. Bind your hearthstone at an inn, quest somewhere far away, and finish a quest handed in near that inn: once nothing is left near you and your hearthstone is ready, the guide's first step says to hearth back and the hearthstone shows on the quest item bar.

41. **Quest database.** About a minute after logging in, `/nq check` shows "Quest database: N quests known" (and "scanning" while it works). `/nq db` lists your zone; `/nq db <part of a quest name>` finds it; `/nq db way <id>` points the arrow. Open the world map on a zone a few levels above you: faded "!" markers with levels show quests that open later. On an alt, quests your main has seen show up there too.

42. **Session and group.** `/nq session` shows this session's XP, quests and gold. Ctrl-click an elite quest in the guide: an LFG message with the quest link appears in your chat box (nothing is sent until you press Enter).

43. **1.13 checks.** Right-click a reminder row in the guide (for example "Bags almost full"): it disappears until your next login. Learn a new flight path: its "Get the flight path" step goes away at once. After updating, chat says "updated to 1.13.0. /nq news shows what's new" once, and `/nq news` opens that page. During the first minutes after login (while the quest database scans), the guide and tracker should not flicker or stutter; say so if they do.

44. **Finished quests you have levelled past (1.13.2).** Carry a few completed quests whose turn-in is in a zone you have left, far enough that they have gone gray in your log, and leave "Include gray quests" off. `/nq route` should list every one of them, the guide should show the trip, and the tracker should agree. One gray hand-in on its own, with nothing else near it, should stay off the route and be listed as "later" instead. An unfinished gray quest should still be hidden while that option is off.

45. **Drops window (1.14.0).** With a couple of "collect N of these" quests in your log, run `/nq drops`. Every item you're short of should be listed with its count, and a kill-only quest should not be. Kill something that drops one: its name should appear on the gray line under that item, with a distance. Click the item to point the arrow at it, Shift+click to link it. Right-click the header to change the sorting and to turn the source line off. Check the key binding (Open or close the drops window) under Esc > Options > Keybindings > AddOns > NeverQuest, and that the window stays where you drag it after a reload.

46. **Arrow quality (1.14.0).** Watch the waypoint arrow while you turn on the spot. The edges should stay clean rather than crawling or stepping, and the outline should stay dark while the fill goes green, yellow or orange. Try each of the four sizes under Options > Display & Maps: the largest should be just as sharp as the smallest, and the title line should sit right under the arrow at every size, not float below a gap.

47. **Nameplate icons and tooltips (1.14.0).** Turn enemy nameplates on (V). Mobs for a kill quest should show a sword, the mob the guide's top step names should show a skull, and each should have your count under it; a mob no quest wants should show nothing. Loot a quest item from a mob, then look at another of the same kind: it should now show a bag, and its tooltip should name the quest and your count. Finish the objective and the icons should go. Hover a quest item in your bags for its "Quest:" line. In a party with another NeverQuest user, mob tooltips should show their progress. Try `/nq plates off`.
48. **Bag finds, sharing, flights (1.14.0).** Put a piece of gear better than what you're wearing in your bags: the guide should add an "Upgrade in your bags" row. Fill your bags with some gray items in them: the bags row should name the cheapest. Turn on "Share quests with my party as I pick them up" and accept a quest in a party: the others should be offered it. Take a flight the guide planned twice: the second time the arrow should count down.
49. **Other languages (1.14.0).** On a non-English client, a kill quest should still give the TARGET button a mob name, and `/nq check` should report the Language line as OK.

50. **Class tab (1.15.0).** `/nq class` should open a seventh tab that still fits the window. The checklist should be for your class, rows at or below your level should say "now", and clicking one should tick it to "done" and back. With a class quest in your log it should appear at the top, and clicking it should point the arrow.

51. **Profession quests and the options (1.15.0).** In the Class tab, the Professions button should list your own professions with your skill beside each, and rows should say "now" only when you have both the skill and the level. Under Options > Guide & Routes, turning "Profession quests section" off should leave the tab with class quests only; turning "Class quests section" off instead should rename the tab to Trades; turning both off should remove the tab and close the gap.

52. **Finished quests and travel (1.16.0).** Complete a few quests whose hand-in spot NeverQuest hasn't learned (pick them up before installing, or use `/nq forget`), then stand in their zone with work waiting elsewhere. The guide should open with "N finished quests waiting in this zone" and list them above anything that takes you out of the zone, not under "later".
53. **Profession cap (1.16.0).** Get a profession within ten points of its rank cap (75, 150 or 225). The guide should say "Nearly capped" with the numbers, and the wording should change to "You're in a town" when you're in one. A profession at 300 should never be mentioned.

## Afterwards, send

- The `/nq check` text from step 1.
- `/nq report` text (open it at the end of the session and copy it).
- Anything that looked wrong or felt clumsy, even if there was no error.

## Tips

- `/nq debug` prints what NeverQuest is doing (arrow target changes, route steps, automation). Turn it off the same way.
- If a feature hits repeated errors, NeverQuest pauses just that feature and tells you. `/reload` brings it back.
- `/nq reset` puts every panel back in its default spot.
