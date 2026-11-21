-- NeverQuest Attunements: step-by-step guides for raid access in WoW Forever, with progress you
-- mostly don't have to tick off yourself.
--
-- What Forever needs (Blizzard's raid overview, November 2026): Onyxia's Lair requires the
-- Drakefire Amulet in every raid member's bags, earned through a long chain per faction. The
-- Barrow Deeps and Hyjal Summit have no attunement. Steps follow Blizzard's list; NPCs and places
-- come from published guides. Where Blizzard hasn't said something (minimum levels, the Test of
-- Skulls drake locations, whether Upper Blackrock Spire needs a key), the step says so.
--
-- Progress comes from: quest IDs known for these quests, quests you turn in while NeverQuest runs
-- (matched by name), the quest you're on now (everything before it is done), the amulet in your
-- bags, and steps you tick yourself (right-click a step in the Raids tab).

local ADDON, ns = ...
local A = { lastCount = {} }
ns.Attune = A

local AMULET_ID, AMULET_NAME = 16309, "drakefire amulet"

-- Step fields:
--   title       quest name (lower-case match), or a Lua pattern when match = true
--   alt         other names the quest may go by
--   count       quests in a row sharing the name ("The True Masters" is six)
--   ids         [part] = quest ID, where known
--   npc / npcs  who gives it (npcs: one per part); nil when it starts from a drop
--   to          who takes it in, when that's a different NPC
--   zone/zones  where the arrow points when the game hasn't placed the quest for you
--   where, what, group  shown in the step
A.LIST = {
	{
		key = "onyxia_a", faction = "Alliance", raid = "Onyxia's Lair", reward = "Drakefire Amulet", amulet = true,
		about = "40-player raid in Dustwallow Marsh. Every raid member needs the Drakefire Amulet in their bags.",
		steps = {
			{ title = "Dragonkin Menace", ids = { 4182 }, npc = "Helendis Riverhorn", zone = "Burning Steppes",
				where = "Burning Steppes", what = "Slay black dragonkin in the Burning Steppes, then report back." },
			{ title = "The True Masters", count = 6, ids = { [4] = 4186, [6] = 4224 },
				npcs = { "Helendis Riverhorn", "Magistrate Solomon", "Highlord Bolvar Fordragon", "Highlord Bolvar Fordragon", "Magistrate Solomon", "Marshal Maxwell" },
				zones = { "Burning Steppes", "Redridge Mountains", "Stormwind City", "Stormwind City", "Redridge Mountains", "Burning Steppes" },
				to = "Marshal Maxwell",
				where = "Lakeshire, Stormwind Keep and Morgan's Vigil",
				what = "Letters and reports between Magistrate Solomon in Lakeshire, Highlord Bolvar Fordragon in Stormwind Keep and Marshal Maxwell at Morgan's Vigil, ending with Ragged John in the Burning Steppes." },
			{ title = "Marshal Windsor", ids = { 4241 }, npc = "Marshal Maxwell", to = "Marshal Windsor", zone = "Burning Steppes",
				where = "Blackrock Depths", what = "Find Marshal Windsor in the Blackrock Depths prison.", group = "Blackrock Depths" },
			{ title = "Abandoned Hope", npc = "Marshal Windsor", to = "Marshal Maxwell", zone = "Burning Steppes",
				where = "Morgan's Vigil", what = "Report back to Marshal Maxwell." },
			{ title = "A Crumpled Up Note", to = "Marshal Windsor", zone = "Burning Steppes", from = "Enemies in Blackrock Depths",
				where = "Blackrock Depths", what = "Loot the note from enemies in Blackrock Depths and bring it to Windsor in his cell.", group = "Blackrock Depths" },
			{ title = "A Shred of Hope", npc = "Marshal Windsor", to = "Marshal Windsor", zone = "Burning Steppes",
				where = "Blackrock Depths", what = "Recover Windsor's information from Golem Lord Argelmach and General Angerforge.", group = "Blackrock Depths" },
			{ title = "Jail Break!", npc = "Marshal Windsor", to = "Marshal Maxwell", zone = "Burning Steppes",
				where = "Blackrock Depths", what = "Escort Windsor out of Blackrock Depths, then return to Marshal Maxwell.", group = "Blackrock Depths" },
			{ title = "Stormwind Rendezvous", npc = "Marshal Maxwell", to = "Squire Rowe", zone = "Stormwind City",
				where = "Stormwind, by the city gates", what = "Meet Squire Rowe and have him call Windsor." },
			{ title = "The Great Masquerade", npc = "Squire Rowe", zone = "Stormwind City",
				where = "Stormwind", what = "Bring allies and see the event through. If Windsor doesn't show up, talk to Squire Rowe again.", group = "a few friends" },
			{ title = "The Dragon's Eye", npc = "Highlord Bolvar Fordragon", to = "Haleh", zone = "Winterspring",
				where = "Stormwind Keep, then Haleh in Winterspring", what = "Bolvar sends you to someone who can help with the Dragon's Eye: Haleh, at the top of Mazthoril in Winterspring." },
			{ title = "Drakefire Amulet", npc = "Haleh", to = "Haleh", zone = "Burning Steppes",
				where = "Upper Blackrock Spire", what = "Defeat General Drakkisath, take the Blood of the Black Dragon Champion, and bring it back for the amulet. Blizzard hasn't said whether Upper Blackrock Spire needs an entry key in Forever.", group = "Upper Blackrock Spire" },
		},
	},
	{
		key = "onyxia_h", faction = "Horde", raid = "Onyxia's Lair", reward = "Drakefire Amulet", amulet = true,
		about = "40-player raid in Dustwallow Marsh. Every raid member needs the Drakefire Amulet in their bags.",
		steps = {
			{ title = "Blood and Thunder", npc = "Warlord Goretooth", zone = "Badlands",
				where = "Kargath, Badlands", what = "Pick up the chain from Warlord Goretooth." },
			{ title = "Warlord's Command", ids = { 4903 }, npc = "Warlord Goretooth", to = "Warlord Goretooth", zone = "Badlands",
				where = "Lower Blackrock Spire", what = "Complete Goretooth's orders inside Lower Blackrock Spire.", group = "Lower Blackrock Spire" },
			{ title = "Eitrigg's Wisdom", ids = { 4941 }, npc = "Warlord Goretooth", to = "Thrall", zone = "Orgrimmar",
				where = "Orgrimmar", what = "Report to Eitrigg in Thrall's chamber, then seek out Thrall." },
			{ title = "For The Horde!", npc = "Thrall", to = "Thrall", zone = "Orgrimmar",
				where = "Blackrock Spire", what = "Claim the head of Warchief Rend Blackhand for Thrall. Blizzard places Rend in Lower Blackrock Spire.", group = "Blackrock Spire" },
			{ title = "What the Wind Carries", npc = "Thrall", to = "Thrall", zone = "Orgrimmar",
				where = "Orgrimmar", what = "Hear what Thrall has learned." },
			{ title = "The Champion of the Horde", npc = "Thrall", to = "Rexxar", zone = "Desolace",
				where = "Desolace, along its roads", what = "Find Rexxar." },
			{ title = "The Testament of Rexxar", alt = { "Mistress of Deception" }, npc = "Rexxar", to = "Myranda the Hag", zone = "Western Plaguelands",
				where = "Western Plaguelands", what = "Deliver Rexxar's testament to Myranda the Hag." },
			{ title = "Oculus Illusions", npc = "Myranda the Hag", to = "Myranda the Hag", zone = "Western Plaguelands",
				where = "Western Plaguelands", what = "Collect Black Dragonspawn Eyes for Myranda." },
			{ title = "Emberstrife", npc = "Myranda the Hag", to = "Emberstrife", zone = "Dustwallow Marsh",
				where = "Dustwallow Marsh", what = "Use your Amulet of Draconic Subversion and find the drake Emberstrife." },
			{ title = "^the test of skulls", match = true, label = "The Test of Skulls", count = 4, npc = "Emberstrife", to = "Emberstrife", zone = "Dustwallow Marsh",
				where = "Across Kalimdor and the Eastern Kingdoms", what = "Bring Emberstrife the skulls of Scryer, Somnus, Chronalis and Axtroz. In original Classic they were in Winterspring, Swamp of Sorrows, Tanaris and Grim Batol; Blizzard hasn't confirmed Forever's spots.", group = "elite drakes, bring friends" },
			{ title = "^ascension", match = true, label = "Ascension...", npc = "Emberstrife", to = "Rexxar", zone = "Desolace",
				where = "Dustwallow Marsh, then Desolace", what = "Receive the Dull Drakefire Amulet and take it to Rexxar." },
			{ title = "Blood of the Black Dragon Champion", npc = "Rexxar", to = "Rexxar", zone = "Burning Steppes",
				where = "Upper Blackrock Spire", what = "Defeat General Drakkisath, take his blood, and return to Rexxar in Desolace for the Drakefire Amulet. Blizzard hasn't said whether Upper Blackrock Spire needs an entry key in Forever.", group = "Upper Blackrock Spire" },
		},
	},
}

-- Raids with no attunement, listed so you know you're set.
A.OPEN = {
	{ raid = "The Barrow Deeps", about = "10 players, level 60. Entrances through Mount Hyjal, Winterspring and Blackmaw Hold." },
	{ raid = "Hyjal Summit", about = "20 players, level 60. At the summit of Mount Hyjal, near the World Tree Nordrassil." },
}

local function Char() return ns.char.attune end
local function Saved(att)
	local s = Char()[att.key]
	if not s then s = {} Char()[att.key] = s end
	return s
end

local function Norm(title)
	if type(title) ~= "string" or ns.IsSecret(title) then return nil end
	return title:lower():gsub("^%s+", ""):gsub("%s+$", "")
end

local function Matches(step, title)
	title = Norm(title)
	if not title then return false end
	if step.match then return title:match(step.title) ~= nil end
	if title == step.title:lower() then return true end
	for _, a in ipairs(step.alt or {}) do
		if title == a:lower() then return true end
	end
	return false
end
A.Matches = Matches

-- One slot per quest: "The True Masters" x6 is six slots.
local function Slots(att)
	if att.slots then return att.slots end
	local slots = {}
	for si, step in ipairs(att.steps) do
		local total = step.count or 1
		for n = 1, total do
			table.insert(slots, { step = step, si = si, n = n, total = total, first = #slots + 2 - n })
		end
	end
	att.slots = slots
	return slots
end
A.Slots = Slots

function A:For(faction)
	local out = {}
	for _, att in ipairs(self.LIST) do
		if not faction or att.faction == faction then table.insert(out, att) end
	end
	return out
end

local function HasAmulet()
	local n = ns.SafeCall(C_Item and C_Item.GetItemCount, AMULET_ID, true)
	if n and n > 0 then return true end
	if not (C_Container and C_Container.GetContainerNumSlots) then return false end
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		local slots = ns.SafeCall(C_Container.GetContainerNumSlots, bag) or 0
		for slot = 1, slots do
			local info = ns.SafeCall(C_Container.GetContainerItemInfo, bag, slot)
			if info and Norm(info.itemName) == AMULET_NAME then return true end
		end
	end
	return false
end

-- { done = { [slot] = true }, current, inLog, count, total, complete, slots }
function A:Progress(att)
	local slots = Slots(att)
	local saved = Char()[att.key] or {}
	local turned = saved.turned or {}
	-- What the game confirms (the amulet, quest IDs, turn-ins) is "sure": your own unticks can't
	-- undo it. Your ticks and the quest you're on count too, but an untick wins over those.
	local highest, sure = 0, 0
	local function Upto(i) if i > highest then highest = i end end
	local function Sure(i) Upto(i) if i > sure then sure = i end end

	if att.amulet and saved.amulet then Sure(#slots) end
	for i, slot in ipairs(slots) do
		local step = slot.step
		if saved.ticks and saved.ticks[i] then Upto(i) end
		if slot.n <= (turned[slot.si] or 0) then Sure(i) end
		local id = step.ids and step.ids[slot.n]
		if id and ns.SafeCall(C_QuestLog.IsQuestFlaggedCompleted, id) == true then Sure(i) end
	end

	-- The quest you're on: everything before it is done.
	local inLog
	for _, e in ipairs(ns.Quests.log) do
		for i, slot in ipairs(slots) do
			if slot.n == 1 and Matches(slot.step, e.title) then
				local last = i + slot.total - 1
				local at = i + math.min(turned[slot.si] or 0, slot.total - 1)
				if at <= highest and highest < last then at = highest + 1 end
				if at > highest and (not inLog or at > inLog) then inLog = at end
			end
		end
	end
	if inLog then Upto(inLog - 1) end

	local done = {}
	for i = 1, highest do done[i] = true end
	for i in pairs(saved.unticks or {}) do
		if i > sure then done[i] = nil end
	end
	local count, current, last = 0, nil, nil
	for i = 1, #slots do
		if done[i] then count, last = count + 1, i elseif not current then current = i end
	end
	if inLog and done[inLog] then inLog = nil end
	return { done = done, current = current, inLog = inLog, last = last, count = count, total = #slots, complete = current == nil, slots = slots }
end

-- Right-click a step: done (with everything before it) or not done.
function A:Toggle(att, i)
	local saved = Saved(att)
	saved.ticks, saved.unticks = saved.ticks or {}, saved.unticks or {}
	if self:Progress(att).done[i] then
		saved.ticks[i] = nil
		saved.unticks[i] = true
	else
		saved.unticks[i] = nil
		saved.ticks[i] = true
	end
	self.manual = true
	ns:SendMessage("ATTUNE_UPDATED")
end

function A:Reset(att)
	Char()[att.key] = { follow = Saved(att).follow }
	self.manual = true
	ns:SendMessage("ATTUNE_UPDATED")
end

function A:Follow(att, on)
	local saved = Saved(att)
	if on == nil then on = not saved.follow end
	for _, other in ipairs(self.LIST) do
		if Char()[other.key] then Char()[other.key].follow = nil end
	end
	saved.follow = on or nil
	ns:SendMessage("ATTUNE_UPDATED")
end

function A:Following()
	for _, att in ipairs(self:For(UnitFactionGroup("player"))) do
		local saved = Char()[att.key]
		if saved and saved.follow then return att end
	end
end

-- Steps that went from not done to done, for alerts and party announcements. The first check
-- after login only sets the baseline, and your own ticks never announce.
function A:CheckProgress()
	if not ns.ready then return end
	local manual = self.manual
	self.manual = nil
	for _, att in ipairs(self:For(UnitFactionGroup("player"))) do
		local p = self:Progress(att)
		local before = self.lastCount[att.key]
		self.lastCount[att.key] = p.count
		if before and p.count > before and not manual then
			ns:SendMessage("ATTUNE_STEP", att, p, p.last and p.slots[p.last])
		end
	end
end

ns:RegisterMessage("ATTUNE_STEP", function(_, att, p, slot)
	if not ns.db.alerts.complete then return end
	if p.complete then
		ns.Alert(att.raid .. ": attuned!", 0.85, 0.7, 1)
		ns.PlaySound(SOUNDKIT.UI_70_ARTIFACT_FORGE_TRAIT_RANKUP or SOUNDKIT.IG_QUEST_LIST_COMPLETE)
	else
		ns.Alert(string.format("%s attunement: %d of %d done", att.raid, p.count, p.total), 0.85, 0.7, 1)
	end
end)

ns:RegisterEvent("QUEST_TURNED_IN", function(_, questID)
	if not ns.ready or not questID then return end
	local e = ns.Quests.byID[questID]
	local title = (e and e.title) or ns.SafeCall(C_QuestLog.GetTitleForQuestID, questID)
	for _, att in ipairs(A.LIST) do
		for si, step in ipairs(att.steps) do
			if Matches(step, title) then
				local saved = Saved(att)
				saved.turned = saved.turned or {}
				saved.turned[si] = math.min(step.count or 1, (saved.turned[si] or 0) + 1)
				ns.Debug("attunement: " .. att.key .. " step " .. si .. " turned in")
				ns:SendMessage("ATTUNE_UPDATED")
			end
		end
	end
end)

local function CheckBags()
	if not ns.ready then return end
	if HasAmulet() then
		for _, att in ipairs(A:For(UnitFactionGroup("player"))) do
			if att.amulet and not Saved(att).amulet then
				Saved(att).amulet = true
				ns:SendMessage("ATTUNE_UPDATED")
			end
		end
	end
end
ns:RegisterEvent("BAG_UPDATE_DELAYED", function() ns.Debounce("attunebags", 1, CheckBags) end)
ns:RegisterEvent("PLAYER_ENTERING_WORLD", function() ns.Debounce("attunebags", 3, CheckBags) end)
ns:RegisterMessage("QUESTS_UPDATED", function() ns.Debounce("attunecheck", 0.5, function() A:CheckProgress() end) end)
ns:RegisterMessage("ATTUNE_UPDATED", function()
	ns.Debounce("attunecheck", 0.1, function() A:CheckProgress() end)
	if ns.Guide then ns.Guide:Refresh() end
	if ns.UI then ns.UI:Refresh() end
end)

---------------------------------------------------------------------------
-- Rows for the Raids tab and the guide
---------------------------------------------------------------------------
function A.SlotTitle(slot)
	local t = slot.step.label or slot.step.title
	if slot.total > 1 then t = string.format("%s (%d of %d)", t, slot.n, slot.total) end
	return t
end

local function Giver(slot)
	local step = slot.step
	return step.npcs and step.npcs[slot.n] or step.npc
end

local function ZoneFor(slot)
	local step = slot.step
	return step.zones and step.zones[slot.n] or step.zone
end

-- Who to talk to next: the turn-in NPC while you're on the quest, else whoever gives it.
local function TargetFor(slot, onIt)
	local step = slot.step
	if onIt then
		if step.npcs and slot.n < slot.total then return step.npcs[slot.n + 1] end
		return step.to or Giver(slot)
	end
	return Giver(slot)
end

-- Where to aim: a spot NeverQuest learned for that NPC or quest, else the middle of the zone.
local function AimFor(slot, npc)
	local step = slot.step
	local id = step.ids and step.ids[slot.n]
	local at = id and ns.db.npcs.giverAt[id]
	if at and at.m then return at.m, at.x, at.y end
	if npc and ns.Spawns and ns.Spawns.NpcSpot then
		local m, x, y = ns.Spawns:NpcSpot(npc)
		if m then return m, x, y end
	end
	local zone = ZoneFor(slot)
	local m = zone and ns.Profiles and ns.Profiles.ZoneID(zone)
	if m then return m, 0.5, 0.5, true end
end

local function PlayerZone()
	local m = C_Map.GetBestMapForUnit("player")
	return m and ns.Nav.GetZoneMap(m)
end

local function Detail(slot)
	local step = slot.step
	local who = Giver(slot) or step.from or "?"
	local parts = { who .. ", " .. step.where, step.what }
	if step.group then table.insert(parts, "|cffff8040Group: " .. step.group .. "|r") end
	return table.concat(parts, "  ·  ")
end

function A:Items(faction)
	local items = {}
	for _, att in ipairs(self:For(faction)) do
		local p = self:Progress(att)
		local saved = Char()[att.key] or {}
		local mine = att.faction == UnitFactionGroup("player")
		table.insert(items, {
			key = "att:" .. att.key, attune = att, icon = "Raid",
			title = string.format("%s: %s (%s)", att.raid, att.reward, att.faction),
			sub = att.about .. (not mine and "" or saved.follow and "  ·  |cff66ff66following in the guide|r (click to stop)" or "  ·  click to follow in the guide"),
			right = p.complete and "|cff66ff66attuned|r" or string.format("%d/%d", p.count, p.total),
			color = { 0.85, 0.7, 1 },
		})
		for i, slot in ipairs(p.slots) do
			local isCurrent = i == p.current
			local state = p.done[i] and "|cff66ff66done|r" or (i == p.inLog and "|cffffd100on it|r") or (isCurrent and "|cffffd100next|r") or ""
			local npc = TargetFor(slot, i == p.inLog)
			local m, x, y = AimFor(slot, npc)
			table.insert(items, {
				key = "att:" .. att.key .. ":" .. i, attune = att, attuneStep = i,
				kind = isCurrent and "objective" or "note",
				title = string.format("%d. %s", i, A.SlotTitle(slot)),
				sub = Detail(slot), right = state, current = isCurrent and mine,
				color = p.done[i] and { 0.55, 0.55, 0.55 } or nil,
				m = m, x = x, y = y, navTitle = A.SlotTitle(slot) .. ": " .. (npc or slot.step.where),
			})
		end
	end
	for _, r in ipairs(self.OPEN) do
		table.insert(items, { key = "att:open:" .. r.raid, icon = "Raid",
			title = r.raid .. ": no attunement", sub = r.about, right = "|cff66ff66open|r", color = { 0.85, 0.7, 1 } })
	end
	return items
end

-- The followed attunement's next step, for the guide.
function A:GuideStep()
	if not ns.db.guide.attunements then return nil end
	local att = self:Following()
	if not att then return nil end
	local p = self:Progress(att)
	if p.complete then return nil end
	local slot = p.slots[p.current]
	local onIt = p.inLog == p.current
	local npc = TargetFor(slot, onIt)
	local s = { kind = "objective", key = "attune:" .. att.key .. ":" .. p.current, attuneFor = att.key,
		title = string.format("%s: %s", att.raid, A.SlotTitle(slot)),
		sub = string.format("Step %d of %d  ·  %s", p.current, p.total, Detail(slot)),
		npc = npc, color = { 0.85, 0.7, 1 } }
	-- On the quest already: aim where the game puts it.
	for _, e in ipairs(ns.Quests.log) do
		if onIt and Matches(slot.step, e.title) and e.pos then
			s.m, s.x, s.y, s.questID = e.pos.m, e.pos.x, e.pos.y, e.questID
		end
	end
	if not s.m then
		local m, x, y, wholeZone = AimFor(slot, npc)
		-- Only a zone to go on and you're in it: no arrow to the middle of nowhere.
		if m and not (wholeZone and PlayerZone() == m) then
			s.m, s.x, s.y = m, x, y
			s.navTitle = A.SlotTitle(slot) .. ": " .. (npc or slot.step.where)
		end
	end
	return s
end

-- Near the level cap, a nudge toward the attunement you haven't started following.
function A:GuideTip(level)
	local cfg = ns.db.guide
	if not cfg.attunements or self:Following() or level < (cfg.attuneAt or 50) then return nil end
	for _, att in ipairs(self:For(UnitFactionGroup("player"))) do
		local p = self:Progress(att)
		if not p.complete and not (Char()[att.key] or {}).dismissed then
			return { kind = "tip", icon = "Raid", key = "tip:attune:" .. att.key, followAttune = att.key,
				title = string.format("%s attunement: %d of %d done", att.raid, p.count, p.total),
				sub = "Click to add its next step to your guide. The Raids tab lists every step.", color = { 0.85, 0.7, 1 } }
		end
	end
end

function A:ByKey(key)
	for _, att in ipairs(self.LIST) do if att.key == key then return att end end
end

function A:StatusText()
	local out = {}
	for _, att in ipairs(self:For(UnitFactionGroup("player"))) do
		local p = self:Progress(att)
		local saved = Char()[att.key] or {}
		table.insert(out, string.format("%s %s%s", att.raid, p.complete and "attuned" or (p.count .. "/" .. p.total),
			saved.follow and " (following)" or ""))
	end
	return #out > 0 and table.concat(out, ", ") or "none for your faction"
end

ns:AddSlash("raids", function(arg)
	arg = (arg or ""):lower()
	if arg == "follow" or arg == "unfollow" then
		local att = A:For(UnitFactionGroup("player"))[1]
		if att then
			A:Follow(att, arg == "follow")
			ns.Print(att.raid .. (arg == "follow" and ": following in the guide." or ": no longer in the guide."))
		end
		return
	end
	if not ns.UI or not ns.UI.frame then return end
	ns.UI.frame:Show()
	ns.UI:SetTab("raids")
end, "/nq raids [follow|unfollow] - raid attunement guides and your progress")
