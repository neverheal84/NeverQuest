# LibQuestDB, embedded in NeverQuest

This folder is LibQuestDB v0.1.0 by Pimptasty, from https://www.curseforge.com/wow/addons/questdb
(CurseForge project 1700352), included under its MIT licence. See LICENSE in this folder.

What was changed: nothing in any file. Two things were left out because NeverQuest only runs on
WoW Forever: the Data/Vanilla and Data/TBC folders, and the library's own TOC files (NeverQuest's
TOC loads the files in the same order the library's Forever TOC does).

Where its data comes from, in its author's words (see README.md): server-side facts are generated
from the CMaNGOS classic world database, client-side facts from the game's own tables, and WoW
Forever's own quests from an in-game walk.

NeverQuest reads this library through its published functions. It does not copy the library's
data into NeverQuest's own database, saved variables, exports or shared messages.
