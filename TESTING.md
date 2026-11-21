# NeverQuest first test session

About 75 minutes. Do the steps in order; skip any that don't apply to where you are.

## Before you start

1. Install **BugSack** and **BugGrabber** (they catch and show errors).
2. Put the `NeverQuest` folder in `Interface\AddOns`, leaving your old `QuestMax` folder there for the first login (see "Moving from QuestMax" in README.md), then log in.

## The checklist

1. **Login.** Chat says "NeverQuest 1.9.0 loaded". Stand somewhere outdoors and run `/nq check`. Copy the window text (Ctrl+C) and save it to send later.
2. **Panels.** `/nq` opens the window and all five tabs switch. The XP panel and arrow show up. Drag them where you like, then `/nq lock`.
3. **Options.** Esc > Options > AddOns > NeverQuest. All six pages open (NeverQuest, Guide & Routes, Tracker, Display & Maps, Spawns & Objectives, Scale & Text) and scroll if they're long. Flip a couple of settings and back. On Scale & Text, try a bigger text size and a different font: the main window, tracker, XP panel and arrow should all change.
4. **Quests and Nearby tabs.** Your quest log shows XP and distances. Nearby lists quests to pick up (open the world map once if it's empty).
5. **Guide and arrow.** The Guide tab's top step matches where the arrow points. Walk toward it: the distance drops and the arrow turns green when you face it. **Check the arrow isn't mirrored** (it should point left when the target is on your left).
6. **Quest NPCs.** Talking to a quest giver auto-accepts; holding Shift skips that. Finished quests turn in by themselves. With several reward choices, chat suggests the highest vendor value.
7. **Waypoints.** `/way 50 50 Test`: the arrow, a minimap pin and a world map pin appear. Walk there and chat says "arrived". Alt+click the world map to add one. Ctrl+click (Blizzard's pin) and the arrow follows it too.
8. **Routes.** Target something inside a cave or building, or in another zone. The arrow should send you to the entrance or exit first and show the game's directions, and the Guide tab shows "via:". If you have two or more flight points and pick a far target, it should say "Fly from ... to ...".
9. **Minimap pins.** Quest givers and turn-ins appear at the right spots. If you use a rotating minimap (Blizzard setting), check that the pins rotate with it.
10. **World map.** You see numbered guide steps joined by a line from where you stand. Turn off "Lines joining the route steps" (Display & Maps > World map): the line goes, the numbers stay.
11. **Quest item button.** On a quest with a usable item, a button appears and works. Bind it under Options > Keybindings > AddOns > NeverQuest.
12. **Target button.** On a kill quest it shows the mob's name; clicking it targets one nearby.
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
29. **Rename.** If you still had QuestMax installed, the first login shows the "QuestMax is now NeverQuest" box; Reload now leaves only NeverQuest running, with your old settings. `/nq` and `/qmax` both open the window.

## Afterwards, send

- The `/nq check` text from step 1.
- `/nq report` text (open it at the end of the session and copy it).
- Anything that looked wrong or felt clumsy, even if there was no error.

## Tips

- `/nq debug` prints what NeverQuest is doing (arrow target changes, route steps, automation). Turn it off the same way.
- If a feature hits repeated errors, NeverQuest pauses just that feature and tells you. `/reload` brings it back.
- `/nq reset` puts every panel back in its default spot.
