# NeverQuest for WoW Forever

By NeverHeal84.

A leveling guide, raid attunement guides, route planner, quest tracker, waypoint arrow, spawn and objective maps, quest buttons and XP tracker in one addon, built for the WoW Forever client (interface 16001).

## Install

1. Close the game.
2. Unzip so you have a folder named `NeverQuest` (it holds `NeverQuest_Camelot.toc` and the `.lua` files).
3. Put that folder in your Forever client's `Interface\AddOns` folder, next to any other Forever addons you use. If you had an earlier NeverQuest, replace the whole folder; your settings and guides are kept.
4. Start the game. If it shows as out of date, tick "Load out of date AddOns" on the character select AddOns screen. You can check your client's interface number in game with `/dump select(4, GetBuildInfo())`.

## What you get

**Getting started**
- **Setup wizard (`/nq setup`):** a few short pages that pick the main settings: leveling style, maps and arrow, the quest tracker, automation, reminders, travel and the quest database, group play, and text size. It opens by itself the first time you log in with NeverQuest; "Use recommended" keeps the defaults and finishes in one click.
- **Help (`/nq help`, or the Help button in the main window):** an in-game guide to every feature, a full command list, key bindings and troubleshooting. `/nq help raids`, `/nq help tracker` and so on jump straight to a topic, and `/nq commands` lists every command in chat.

**Guiding**
- **Two leveling styles (Guide tab > 1-60 plan, `/nq style`, or Options > Guide & Routes):**
  - **Optimized 1-60** (default): a zone-hopping route with exact level windows, built from where current published Forever leveling guides agree. You leave a zone when its window ends, even with quests left, and some legs come back later for the leftovers when they're worth more (Westfall at 18, upper Redridge at 20, the northern Barrens at 22, Duskwood at 30, Stranglethorn at 43). Riverglades sits in the late 30s, then Tanaris, Feralas, Un'Goro, Felwood, the Plaguelands and Winterspring, with Mount Hyjal at 60.
  - **Zone by zone:** stay in a zone until its useful quests run out, then move to the next zone in your race's plan.
  - Either way, quests in the zones your style wants you in count for more in the route and the guide, quests elsewhere count for less (finished quests still get handed in when they're near), and a "Time to move on" or "Zone done" step points the arrow at the next zone at the right moment. Near the end of a leg, quests that are handed in at your next zone count for more, and follow-ups of quests you've finished count for more so chains you've started get finished.
  - The plan view shows your route leg by leg (or band by band) with your class quests, talents, riding, dual spec and dungeon windows. Browse any of the 56 race and class combinations with the Race and Class buttons. Levels 31-60 weren't part of Forever's beta, so those legs may get tuned.
- **Route planner (Guide tab):** your objectives, turn-ins and nearby quest pickups are put into one short route so you aren't walking back and forth. Each quest is planned as "do the objective, then hand it in", using where any of your characters handed that quest in before, or where you picked it up (usually the same NPC). Turn-ins and pickups that are on the way get folded in. Quests worth too little XP for the walk are left for later, so the route keeps your XP per hour high. Finished quests handed in near each other are judged as one trip, so a pile of them in a zone you've moved on from sends you back to cash them in, and each moves up the list the further you out-level it, because quest XP shrinks as you go. A summary row shows the trip's time, XP and XP per hour, and `/nq route` lists it in chat. The first stop stays put unless a new plan is clearly better, so the arrow doesn't flip around. Turn it off for the simple order (nearest best-XP quest first).
- **Quest chains:** quests that open up follow-ups are worth more, so the guide does them sooner and grabs the follow-up while you're standing at the NPC. Chains come from the game's own quest lines and from what NeverQuest sees after your turn-ins (a quest offered right after you hand one in, by the same NPC). Steps and the tracker show "chain: Name 3/7" or "leads to 2 more quests". Learned chains are shared by all your characters.
- **Live guide (Guide tab):** always shows your best next move, in route order. When your zone runs dry or goes gray, it suggests zones in your level range. The arrow follows the top step.
- **Recorded guides (Guides tab):** record a run and replay it on alts. Steps tick off on their own, including trainer, vendor, hearth and flight master visits, and "grind to X%" steps. Export and import guides as plain text.

**Where quests are handed in**
- When a quest ends in another zone, NeverQuest asks the game which map the quest points to and reads its marker there. Without a marker it goes by, in order: where any of your characters handed it in, the NPC the quest text names (if you've met them), and the zone the text names. It only falls back to where you picked the quest up when nothing says otherwise, and it never does when the text sends you to someone other than the quest giver. Steps say "somewhere in Elwynn Forest" or "where they are isn't known yet" instead of pointing at the wrong place, and the tracker files finished quests under the zone you hand them in. Pickup and hand-in spots are only saved when you were actually at that quest's NPC (not for quests shared by a party member, started from an item, or handed in through a pop-up), and a saved spot that contradicts the quest text is ignored. Clicking a finished quest in the tracker points the arrow at its hand-in.

**Scavenger-hunt quests**
- Some quests have no objectives and no map marker: the quest text is the only clue (the Cozy Sleeping Bag chain that starts with "...and that note you found" is one). NeverQuest carries its own hand-checked spots for these, so the arrow, map and tracker point at the right object in the right zone (for Alliance, the Burned-Out Remains in The Barrens, not back in Westfall), the step says what to click and how to get there, and the chain shows as "Cozy Sleeping Bag 1/6". Text-only quests without a known spot say so instead of sending you back to where you picked them up.

**Raid attunements (Raids tab, `/nq raids`)**
- **What Forever needs:** Onyxia's Lair asks every raid member to carry the Drakefire Amulet, earned through a long quest chain that's different for each faction (16 quests for Alliance, 15 for Horde, counting The True Masters and the Tests of Skulls one by one). The Barrow Deeps and Hyjal Summit have no attunement; they're listed so you know you're set.
- **Every step:** who gives it, where, what to do, and whether you need a group or a dungeon (Blackrock Depths, Lower or Upper Blackrock Spire). Where Blizzard hasn't published something yet (minimum levels, where the four drakes for the Test of Skulls are, whether Upper Blackrock Spire needs a key in Forever), the step says so instead of guessing.
- **Ticks itself off:** a step is done when the game reports its quest finished, when you turn it in, when you're on a later quest in the chain (everything before it is done), or when the amulet is in your bags. Right-click a step to mark it done or not done yourself.
- **Follow it in the guide:** click the raid row (or the reminder the guide shows from level 50) and the chain's next step joins your guide: right after your next leveling step while you level, first once you're at the level cap. The arrow goes where the game puts the quest, or to a spot NeverQuest has learned for the NPC, and the target button targets who you need to talk to. Browse the other faction's chain with the button at the bottom.
- Settings: Options > Guide & Routes ("Raid attunements in the guide", and the level the reminder starts at).

**Maps and navigation**
- **Waypoint arrow:** rotating arrow with distance, ETA and coordinates, plus Blizzard's in-world marker. Adjustable size, compact mode. When you die and release, it points to your corpse (and says when you're close enough to resurrect), then goes back to your route once you're alive.
- **Routes, not straight lines:** when a target needs a special path, the arrow goes there first and tells you what to do ("Enter Fargodeep Mine", "Take the tunnel...", "Fly from Goldshire to Lakeshire"), with a "then:" line for the final target. It uses, in order: a flight between flight masters you've discovered, when that's clearly faster; the game's own route for quests and for map pins (caves, buildings, tunnels, zone exits); and map links to cave or building entrances. Quest distances in the guide follow the route too, so a quest at the back of a mine ranks by how far it really is. Turn either part off under Options > NeverQuest > Routes.
- **Minimap pins:** quest givers, objectives, turn-ins and your waypoints. Your current target clings to the minimap edge when it's out of range. Works with a rotating minimap.
- **World map:** all your waypoints, numbered, plus a route preview of the guide's next steps joined by a line from where you stand (the line can be turned off or made thinner or thicker; the numbered pins stay). The route goes to objectives, finished turn-ins and pickups; where an unfinished quest will be handed in is left off the line unless you turn on "Include turn-ins for unfinished quests". When the game only marks a quest's NPC rather than its objective area, NeverQuest treats that spot as the NPC: a learned spawn spot takes over, the step says so, and the quest waits instead of sending you to the NPC early. **Alt+click** the map to drop a waypoint. Blizzard's own map pin (Ctrl+click) is picked up by the arrow too.

**Quest givers on the maps**
- **Level-appropriate pickups:** the world map shows "!" for quests you can pick up, each with its level in the quest's difficulty color (green, yellow, orange). Gray (low level) and red (too high) quests are left off unless you turn them on, and red quests also stay out of the guide and route. Dailies, story and legendary quests get their own icons.
- **Any zone:** open another zone on the world map and its quest givers show too, so you can plan where to go next. The minimap shows the ones near you, with the same filter.
- Hover a quest giver for its level, XP, who gives it (once any of your characters has taken it) and its quest chain. Click for a waypoint, Shift+click to point the arrow there.
- **Turn-in spots** ("?" for finished quests) can be added to the world map too; they're off by default because Blizzard's map usually shows them.
- Settings: Options > Display & Maps > Quest givers.

**Spawns and objectives on the maps**
- **Learned as you play:** NeverQuest ships no spawn database. It remembers where things are from your own play: where a quest mob died when you got kill credit, which corpse or object a quest item came from, where "explore" and "use" objectives ticked over, and where mobs tied to your quests came close to you (best with enemy nameplates on). Spots close together merge into one and get stronger each time.
- **Drawn for your quests:** the world map shows colored dots for the open objectives of the quests in your log (one color per quest; bigger, brighter dots have been seen more often). The minimap can show the ones near you too (off by default to keep it clear; turn it on under Spawns & Objectives, where there's also a dot size setting). Hover a dot to see the mob, the quest and objective it counts for, and how often and how recently it was seen. Turn on "Show every known spawn" to see all of them, with spots your quests don't need in gray.
- **Guide goes to real spawns:** when a known spot is closer than the game's quest area, the arrow goes there and the guide step says "known spot". Spots you've just visited are skipped for a few minutes, so the arrow tours the spawn points instead of parking on an empty one. The target button also learns which mob drops a quest item.
- **Mark spots yourself:** **Alt+right-click** the world map to mark a spot: your target's spawn, any open quest objective, a mob by name, or a note. `/nq mark` marks your target's spawn where you stand (or `/nq mark Hogger`), `/nq mapnote` leaves a note, and there's a key binding. Right-click a spot to set a waypoint, forget it, or remove a mark; Shift+click removes a mark.
- **Rares and treasures** the game shows on your minimap are remembered on the world map, with when you last saw them.
- **Share:** new spots and marks go to party members who run NeverQuest. **Export** and **Import** (Options > Spawns & Objectives, or `/nq spawns export`) pass everything to friends or alts on another account as one text string.

**Quest tracker (right side)**
- **Sorted by priority, grouped by zone:** the NeverQuest tracker lists your quests in the order the guide will do them, numbered, grouped under zone headers with your current zone first. Each quest shows its level, distance, objectives, "Ready to turn in (to NPC)", its chain and party progress. Click a quest to point the arrow at it, Shift+click to link it, right-click to pin it to the top, hide it or open it in the quest log. Click a zone header to collapse it; right-click the tracker header for sorting (priority, distance, level) and quick options.
- **Blizzard's quest list:** by default it's emptied while the NeverQuest tracker shows (your quests are untracked, so Blizzard's objective tracker keeps only its other sections, like bonus objectives). Or choose "Sort by priority" to keep Blizzard's list in NeverQuest's order, or "Leave it alone". Turning the hide option off gives your tracked quests back. NeverQuest only changes which quests are tracked, out of combat, and never edits Blizzard's frames.

**Buttons**
- **Quest item bar:** a slim bar with the NeverQuest logo as its drag handle, holding usable quest items for your next steps (rounded buttons with cooldowns and key labels). Keybindable.
- **Target button (off by default):** targets the NPC or mob for your next step. NPC names are learned from your own quest conversations and shared by all your characters, so alts get smarter over time. Bind it under Esc > Options > Keybindings > AddOns > NeverQuest ("Target next NPC or mob"); the key works even with the button hidden. To show the "TARGET" pill on the quest item bar, turn it on under Options > Display & Maps > Buttons or type `/nq buttons target`. `/nq buttons` hides the quest item bar; its size is under Scale & Text.

**Tracking**
- **XP panel:** XP/hour, time to level, quests or kills to level, rested XP. Right-click it to open the main window.
- **Quests and Nearby tabs:** your quest log ranked by XP per distance, and quests you can pick up nearby.
- **Journal tab:** every quest you turn in, plus **level splits** that compare each level's time with your fastest character.
- **Party sync:** party members who also run NeverQuest see each other's progress on shared quests.
- **Party announcements (toggle):** when you finish something, your group hears about it in party chat (instance chat in a dungeon finder group): "NeverQuest: [Quest] objective done: Boar Meat: 4/4", "NeverQuest: [Quest] complete, ready to turn in.", and raid attunement progress. Turn-ins (with the XP) can be added. Each kind has its own switch, and you can limit it to quests someone else in the group is also on, allow raid groups, drop the clickable links or the "NeverQuest:" tag. Repeats within 30 seconds are skipped, a burst of completions goes out a second apart, and nothing is sent while the game locks chat for addons. `/nq announce off` turns it all off; `/nq announce test` sends a test line. Settings: Options > NeverQuest > Party announcements.
- **Party catch-up (toggle):** in a party, the guide and route adapt so everyone keeps up. Quests you share count for more. If you've finished a quest a party member hasn't, the turn-in waits and the route takes you back to its objective spot to help ("Help Anna: ..."), then you hand it in together. Quest givers for quests a party member is on count for more, and the guide suggests quests to share (click to share) or to ask them for. Zones are picked for the lowest level in the party, and a "Regroup" step points the arrow at anyone more than 300 yards away. Levels and positions work for everyone in the party; quest lists come from members running NeverQuest. Settings: Options > NeverQuest > Party.

**Minimap button:** a round NeverQuest button on the edge of the minimap. Click to open NeverQuest, Shift+click to show or hide the tracker, right-click for quick settings (raid attunements, help, setup wizard, session summary, tracker, known quests on the world map, XP panel, arrow, party announcements, party catch-up, leveling style, options), and drag it anywhere around the minimap. Hide or lock it under Options > Display & Maps > Minimap, or with `/nq minimap`.

**Automation:** auto accept and turn in. **Hold Shift** when talking to an NPC to skip it.

**Reward upgrades:** with several quest rewards to choose from, each is compared with what you're wearing, using the stats your class cares about (and the armor and weapons it can use at your level). The best one gets a green arrow in the quest window and chat says why ("+4 Strength, +3 Stamina over [Old Belt]"). With no upgrade, the highest vendor value is marked. Options can take upgrades for you, or always take the highest vendor value.

**Auto repair (on by default):** opening a vendor that can repair fixes all your gear and says what it cost. It can use guild funds first when your rank allows it and the daily limit covers it. Hold Shift while opening the vendor to skip it. `/nq repair` repairs now, `/nq repair guild` switches guild funds.

**Auto loot (on by default):** takes everything from a loot window at once. Hold Shift (the game's auto-loot key) to look first. Items waiting on a group roll are left alone, and bind-on-pickup items still ask you. `/nq loot` turns it on or off.

**Sell junk (on by default):** gray items are sold when you open a vendor, and chat says what they brought in (the vendor's Buyback tab has the most recent ones if you change your mind). Hold Shift while opening the vendor to skip it. It uses the game's own sell-all-junk when the client has it, otherwise one item at a time and only while the vendor is open. `/nq junk` sells now at a vendor, or tells you what your junk is worth anywhere else.

**Quest database (`/nq db`):** every quest the game has shown any of your characters, with its level, zone and where the quest giver stands. It's built only from the game itself: a slow background scan asks the game which quests each zone offers (one zone every couple of seconds, paused in combat, again after you level), and quests you see or accept are added as you play. Alts benefit from what your other characters have seen. `/nq db` lists your zone (done, in your log, available, for later levels), `/nq db <name>` searches by name or quest ID, `/nq db zone <zone>` lists another zone, and `/nq db way <id>` points the arrow at the giver. The world map shows known quests that aren't on offer to you yet as faded markers with the level they open at.

**Questie:** if you also run Questie, NeverQuest leaves quest givers and spawn spots on the maps to it so nothing is drawn twice. Your guide, route and arrow keep working. `/nq questie` switches this.

**Reminders (guide rows):** a full quest log, with which quests to drop first (failed, gray, far away or little XP for the walk; never ones ready to hand in or your attunement chain); low food and water, or a hunter's ammo; nearly full bags, with quest items you can safely delete because their quest is done. Logging out away from an inn or city reminds you there's no rested XP there (and mentions your Cozy Sleeping Bag if you carry one). Right-click any reminder row (these, flight paths, hearth) to hide it until you log in again.

**Flight paths and hearthstone:** a guide step points to any flight master in your zone you haven't talked to yet. NeverQuest notes where you bind your hearthstone; when it's ready, nothing is left near you, and finished quests are handed in near your inn, the guide's first step says to hearth back and the hearthstone appears on the quest item bar. At an inn far from your hearth spot with quests around, it says once that you could bind there.

**Session summary (`/nq session`):** time played, XP and XP per hour, levels, quests, kills, gold and deaths since you logged in. Optionally shown when you log out.

**Asking for a group:** Ctrl-click an elite or group quest in the guide, or pick "Ask for a group" in its tracker menu, to put an LFG message with the quest link in your chat box. Nothing is sent until you press Enter. `/nq lfg` does it for your next elite quest.

## Commands

| Command | What it does |
|---|---|
| `/nq` | Open or close the window |
| `/nq setup` | The setup wizard |
| `/nq help [topic]` | In-game help (topics: start, guide, plan, arrow, maps, tracker, raids, party, buttons, automation, upkeep, database, commands, keys, news, trouble) |
| `/nq commands` | List every command in chat |
| `/nq loot [on \| off]` | Auto loot on or off |
| `/nq junk` | Sell gray items now (at a vendor), or see what they're worth |
| `/nq repair [on \| off \| guild]` | Repair now at a vendor, switch auto repair, or switch guild-funded repairs |
| `/nq db [name \| zone <zone> \| way <id> \| scan \| map]` | The quest database: your zone's quests, search, another zone, point the arrow, scan again, world map markers |
| `/nq session` | What this play session brought in |
| `/nq news` | What changed in recent versions (also offered once in chat after an update) |
| `/nq lfg` | Put an LFG message for your next elite quest in the chat box |
| `/nq questie` | With Questie running, hide or show NeverQuest's quest giver and spawn pins |
| `/nq guide`, `quests`, `nearby`, `journal`, `guides` | Open a tab |
| `/nq raids [follow \| unfollow]` | Raid attunement guides and your progress; follow your faction's chain in the guide |
| `/nq announce [on \| off \| test]` | Party announcements on or off, or send a test line; `objectives`, `quests`, `turnins`, `attunements`, `raid`, `shared` switch one part |
| `/nq plan` | Your 1-60 leveling plan (browse other races and classes too) |
| `/nq options` | Settings (also Esc > Options > AddOns > NeverQuest, six pages) |
| `/nq route` | List the planned route in chat |
| `/nq style [optimized \| zone]` | Switch leveling style |
| `/nq minimap [lock]` | Show or hide the minimap button, or lock it |
| `/nq tracker` | Show or hide the NeverQuest tracker; `lock` locks it, `blizzard` changes what happens to Blizzard's quest list |
| `/way 45.2 63.8 Innkeeper` | Waypoint in your current zone |
| `/way Westfall 52 30` | Waypoint in another zone |
| `/way list`, `clear`, `next`, `closest`, `here` | Manage waypoints |
| `/nq record [name]`, `/nq stop` | Record a route, then save it |
| `/nq note <text>` | Add a note at your spot while recording |
| `/nq mark [mob name]` | Mark a mob spawn where you stand (your target if no name) |
| `/nq mapnote [text]` | Leave a note on the map where you stand |
| `/nq spawns` | Spawn memory summary; `export`, `import`, `all` (show every known spawn), `forget <mob>`, `clear learned/marks/rares/all` |
| `/nq grind [note]` | While recording: you ground here up to your current XP |
| `/nq load <name>`, `/nq live` | Load a saved guide, or go back to the live guide |
| `/nq hud`, `arrow`, `buttons`, `lock`, `reset` | Show/hide, lock, or reset panels (`/nq buttons target` shows or hides the TARGET button) |
| `/nq xp` | XP stats in chat |
| `/nq check` | Self-test on your client, in a copyable window |
| `/nq report` | Copyable bug report with recent errors |
| `/nq debug` | Show what NeverQuest is doing in chat |

If another addon already owns `/way`, use `/nqway`.

**Keybindings** (Esc > Options > Keybindings > AddOns > NeverQuest): open NeverQuest, use quest item 1 and 2, target next NPC or mob, skip guide step, mark a spawn where I stand.

Arrow: right-click clears the current waypoint, Shift+right-click clears all, drag to move. World map waypoint pins: click to make active, Shift+click to remove. Spawn dots and marks: click for a waypoint, right-click for options, Shift+click removes a mark.

## Settings

Esc > Options > AddOns > NeverQuest has six pages, and almost everything can be switched on or off:

- **NeverQuest:** automation (quests, reward choice, auto loot, sell junk, repairs and guild funds), reminders (full quest log, supplies, bags, rested XP, session summary), travel (flight paths, hearthstone, home inn), the quest database (background scan, world map markers, Questie), alerts, party sharing, party announcements (objectives, quests, turn-ins, attunements, shared quests only, raids, links, tag) and party catch-up (group level, regroup, share suggestions), chat messages.
- **Guide & Routes:** leveling style (optimized 1-60 or zone by zone), raid attunement steps and reminder level, following your 1-60 plan, move-on reminders, route planning, quest chains, pickups along the way, "then turn in" steps, the route summary, zone and plan advice, rested and outleveled tips, what each step shows (XP, directions, party), paths and flights.
- **Tracker:** show it, what happens to Blizzard's list, sort order, group by zone, current zone first, collapse other zones, finished quests first, gray quests, each line it shows (objectives, finished objectives, numbers, level, distance, chain, party), how many quests, width, height, background and size.
- **Display & Maps:** the minimap button, each XP panel line, the arrow's lines (coordinates, ETA, "then:"), arrival sound and distance, quest buttons, minimap and world map pins, and quest givers (world map, other zones, minimap, levels, gray, red, dailies, turn-in spots).
- **Spawns & Objectives:** spawn learning, maps, sharing and your spawn data.
- **Scale & Text:** font, text size (Small to Huge), outline and shadow for every NeverQuest panel, plus separate sizes for the main window, tracker, XP panel, arrow, quest buttons, minimap pins and world map pins.

## Making guides for every race

The live guide works for any race from level 1. For a curated route:

1. On the character, `/nq record Dwarf Hunter 1-12` and play normally.
2. Pickups, completions, turn-ins (with NPC names), flights, hearths, trainers, vendors and level-ups are saved with coordinates. Use `/nq grind` after grinding and `/nq note` for tips.
3. `/nq stop`. The guide appears in the Guides tab on all your characters.
4. **Export** gives you text to share. **Import** loads someone else's. Guides from version 1.0 still import.

## Notes

- Forever runs addons under the Midnight rules, so nothing here reads combat data or makes combat decisions. Buttons only change outside combat; changes made during a fight apply when it ends.
- The plan matches zones by their English names. On other game languages the plan still shows, but zone navigation from it may not work; `/nq check` reports how many plan zones it found.
- Party sync works in parties, not raids, and pauses in content where the game blocks addon messages.
- Spawn learning stays off inside dungeons and on flights. Nearby-mob learning only checks range outside combat (the game blocks that check in a fight), so kill credit and loot do the work during fights. Spot positions are where you stood, so ranged kills land up to about 40 yards from the mob.
- Routes to `/way` waypoints use the in-world waypoint marker setting (on by default), because the game only plans a route for the pin it's tracking.
- Quest difficulty comes from the game's own rating for your level. Blizzard's map shows its own "!" too; NeverQuest's sit on top with the level added.
- The route planner uses straight-line distances with an allowance for real paths, and guesses time per objective from its type and count. Its XP per hour is an estimate for comparing routes, not a promise.
- Turn-in spots for quests you're still doing are guesses until one of your characters has handed that quest in; the first time through, the pickup spot stands in.
- Raid attunement steps follow Blizzard's raid overview (November 2026); NPCs and places come from published guides, and some quest IDs come from original Classic. Raid details may change before or after the raids open on December 9. If a step ticks off wrongly, right-click it.
- Party announcements use the game's normal chat (party or instance chat); addons can't post there while the game locks chat for them, so those messages are skipped rather than sent late.
- A two-handed reward is compared with your main hand and off-hand together, and no reward is judged or taken while the game is still loading its stats.
- Reward upgrades use simple stat weights per class (the main stats, armor and weapon damage). They're good at spotting a clear upgrade, not a replacement for a gear planner, and the weights don't know your talents.
- The quest database only knows what the game has shown one of your characters, so it fills in as you and your alts play. It contains nothing copied from other addons or websites. Class and race quests seen by another character can show on the map until this character's scan of that zone confirms they aren't for it.
- Text matching for reminders (food and drink detection by spell name, the Cozy Sleeping Bag) is in English.
- Saved settings: `NeverQuestDB` (account) and `NeverQuestCharDB` (per character).
- If a feature hits repeated errors, NeverQuest pauses just that feature and tells you; `/reload` brings it back. `/nq report` collects the details.
- Testing a new build? Follow TESTING.md.
