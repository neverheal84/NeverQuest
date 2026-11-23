# Notice

`Forever.lua` in this folder is a derived work of **QuestieDB**, the database of the Questie
addon, and is distributed under the **GNU General Public License, version 3**. The full licence
text is in `gpl-3.0.md`, and QuestieDB's own licensing statement is reproduced unchanged in
`LICENSE.md`.

- Source: QuestieDB 1.1.4, WoW Forever build, https://github.com/Questie/QuestieDB
- Data credit, from that build's own author line: Muehe, TheCrux (BreakBB), Drejjmit, Dyaxler,
  Cheeq, TechnoHunter, Yttrium and everyone else who has contributed to Questie. Code: Logonz.
- NeverQuest is not Questie, is not affiliated with or endorsed by the Questie team, and does
  not use the Questie name or logo as its own.

## What was taken

For quests that are new in WoW Forever and that NeverQuest knew by name but had no place for:
the NPC or object that starts and ends the quest, one map point for each, which side the giver
serves, the level needed, and the quests that must come first or that close it.

## What was changed (GPLv3 section 5a)

On 2026-11-21 the records were extracted from QuestieDB's data store by
`tools/build_questie_forever.py` (in NeverQuest's source repository) and rewritten in
NeverQuest's own table format. Changes from the original:

- only the subset described above was kept; every other field and every other quest was left out;
- quest titles and levels were not taken (NeverQuest uses the game's own answers for those);
- a quest was kept only if the game had confirmed its number and exact title to a NeverQuest
  client, and only where NeverQuest had no place of its own;
- one map point was kept per NPC or object (the first listed), rounded to a tenth of a percent
  of the map;
- NPCs whose place disagreed with one recorded in the game by a NeverQuest client were dropped.

The counts from that build are in the header of `Forever.lua`.

## Source

The script that produced the file is `tools/build_questie_forever.py` in NeverQuest's source
repository, https://github.com/neverheal84/NeverQuest. Its input is the unmodified QuestieDB
release named above.
