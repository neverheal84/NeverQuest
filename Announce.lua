-- NeverQuest Announce: tells your group in chat when you finish something. Each kind can be
-- turned off, and the whole thing with one switch (Options, or /nq announce off).
--
--   objectives   "NeverQuest: [Quest] objective done: Prairie Wolf slain: 8/8"
--   quests       "NeverQuest: [Quest] complete, ready to turn in."
--   turn-ins     "NeverQuest: turned in [Quest] (+1,250 XP)."              (off by default)
--   attunements  "NeverQuest: Onyxia's Lair attunement 5/16 (A Crumpled Up Note)."
--
-- Goes to party chat, or instance chat in a dungeon finder group; raids only when allowed.
-- Messages wait in a short queue so a burst of completions doesn't flood the chat, repeats
-- within 30 seconds are dropped, and nothing is sent while the game locks chat for addons.

local ADDON, ns = ...
local Ann = { queue = {}, sent = {}, objState = {} }
ns.Announce = Ann

local SPACING, REPEAT_WINDOW, MAX_QUEUE = 1.2, 30, 8
local HOME = LE_PARTY_CATEGORY_HOME or 1
local INSTANCE = LE_PARTY_CATEGORY_INSTANCE or 2

local function Cfg() return ns.db.announce end

-- Where messages go right now, or nil when there's nobody to tell.
function Ann:Channel()
	local cfg = Cfg()
	if IsInGroup(INSTANCE) and not IsInGroup(HOME) then
		if IsInRaid(INSTANCE) and not cfg.raid then return nil end
		return "INSTANCE_CHAT"
	end
	if IsInRaid() then return cfg.raid and "RAID" or nil end
	if IsInGroup() then return "PARTY" end
	return nil
end

function Ann:Locked()
	return ns.SafeCall(C_ChatInfo and C_ChatInfo.InChatMessagingLockdown) == true
end

local function RawSend(text, channel)
	local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	if type(send) ~= "function" then return false end
	local ok, err = pcall(send, text, channel)
	if not ok then ns.Debug("announce failed: " .. tostring(err)) end
	return ok
end

function Ann:Drain()
	self.draining = nil
	local item = table.remove(self.queue, 1)
	if not item then return end
	local channel = self:Channel()
	if channel and not self:Locked() then
		RawSend(item, channel)
	end
	if #self.queue > 0 then
		self.draining = true
		C_Timer.After(SPACING, function() Ann:Drain() end)
	end
end

-- Queues a message for the group. kind matches a setting; force skips it (for /nq announce test).
function Ann:Say(kind, text, force)
	local cfg = Cfg()
	if not force and (not cfg.enabled or not cfg[kind]) then return false end
	if type(text) ~= "string" or ns.IsSecret(text) or text == "" then return false end
	if not self:Channel() then return false end
	local now = GetTime()
	if not force and self.sent[text] and now - self.sent[text] < REPEAT_WINDOW then return false end
	self.sent[text] = now
	if #self.queue >= MAX_QUEUE then table.remove(self.queue, 1) end
	if cfg.tag then text = "NeverQuest: " .. text end
	if #text > 255 then text = text:sub(1, 252) .. "..." end
	table.insert(self.queue, text)
	if not self.draining then
		self.draining = true
		C_Timer.After(0.2, function() Ann:Drain() end)
	end
	return true
end

-- A quest's name for chat: its clickable link when the game gives one.
function Ann:QuestText(questID, title)
	if Cfg().links and questID and GetQuestLink then
		local link = ns.SafeCall(GetQuestLink, questID)
		if type(link) == "string" and link ~= "" then return link end
	end
	return "[" .. (title or ("Quest " .. tostring(questID))) .. "]"
end

-- Only quests someone else in the group is also on, when that's how you like it.
function Ann:Relevant(questID)
	if not Cfg().sharedOnly then return true end
	if not questID or not (C_QuestLog and C_QuestLog.IsUnitOnQuest) then return true end
	local prefix, n = IsInRaid() and "raid" or "party", IsInRaid() and 40 or 4
	for i = 1, n do
		local unit = prefix .. i
		if UnitExists(unit) and not UnitIsUnit(unit, "player")
			and ns.SafeCall(C_QuestLog.IsUnitOnQuest, unit, questID) == true then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------
-- What gets announced
---------------------------------------------------------------------------

-- Objectives finished since the last scan. The first scan after login only records states.
function Ann:ScanObjectives()
	local seen = {}
	for _, e in ipairs(ns.Quests.log) do
		local qid = e.questID
		seen[qid] = true
		local objectives = ns.SafeCall(C_QuestLog.GetQuestObjectives, qid)
		local before = self.objState[qid]
		local now = {}
		if type(objectives) == "table" then
			for i, o in ipairs(objectives) do
				local finished = o.finished
				if ns.IsSecret(finished) then finished = nil end
				now[i] = finished == true
				-- The quest itself finishing is its own message; don't send both.
				if before and now[i] and before[i] == false and not e.complete and #objectives > 1
					and self:Relevant(qid) then
					local text = o.text
					if ns.IsSecret(text) or type(text) ~= "string" or text == "" then text = "objective " .. i end
					self:Say("objectives", string.format("%s objective done: %s", self:QuestText(qid, e.title), text))
				end
			end
		end
		self.objState[qid] = now
	end
	for qid in pairs(self.objState) do
		if not seen[qid] then self.objState[qid] = nil end
	end
end

ns:RegisterMessage("QUESTS_UPDATED", function()
	if not ns.ready then return end
	Ann:ScanObjectives()
end)

ns:RegisterMessage("QUEST_READY", function(_, e)
	if not e or not Ann:Relevant(e.questID) then return end
	Ann:Say("quests", string.format("%s complete, ready to turn in.", Ann:QuestText(e.questID, e.title)))
end)

ns:RegisterEvent("QUEST_TURNED_IN", function(_, questID, xp)
	if not ns.ready or not questID or not Cfg().turnins then return end
	local e = ns.Quests.byID[questID]
	local title = (e and e.title) or ns.SafeCall(C_QuestLog.GetTitleForQuestID, questID)
	xp = ns.Num(xp)
	Ann:Say("turnins", string.format("turned in %s%s.", Ann:QuestText(questID, title),
		(xp and xp > 0) and (" (+" .. ns.Comma(xp) .. " XP)") or ""))
end)

ns:RegisterMessage("ATTUNE_STEP", function(_, att, p, slot)
	if p.complete then
		Ann:Say("attunements", string.format("attuned to %s (%s)!", att.raid, att.reward))
	else
		Ann:Say("attunements", string.format("%s attunement %d/%d (%s).", att.raid, p.count, p.total,
			slot and ns.Attune.SlotTitle(slot) or "step done"))
	end
end)

function Ann:StatusText()
	local cfg = Cfg()
	if not cfg.enabled then return "off" end
	local kinds = {}
	for _, k in ipairs({ "objectives", "quests", "turnins", "attunements" }) do
		if cfg[k] then table.insert(kinds, k == "turnins" and "turn-ins" or k) end
	end
	local where = self:Channel()
	return string.format("on (%s)%s, %s", #kinds > 0 and table.concat(kinds, ", ") or "nothing selected",
		cfg.sharedOnly and ", shared quests only" or "",
		where and ("sending to " .. where:lower():gsub("_", " ")) or "not in a group")
end

ns:AddSlash("announce", function(arg)
	arg = (arg or ""):lower()
	local cfg = Cfg()
	if arg == "on" or arg == "off" then
		cfg.enabled = arg == "on"
	elseif arg == "test" then
		if not Ann:Channel() then
			ns.Print("join a group first; announcements only go to your party or instance group.")
		else
			Ann:Say("quests", "announcements are working.", true)
		end
		return
	elseif arg ~= "" then
		local key = ({ objectives = "objectives", quests = "quests", turnins = "turnins", ["turn-ins"] = "turnins",
			attunements = "attunements", raid = "raid", shared = "sharedOnly", links = "links", tag = "tag" })[arg]
		if not key then
			ns.Print("/nq announce on | off | test | objectives | quests | turnins | attunements | raid | shared")
			return
		end
		cfg[key] = not cfg[key]
	end
	ns.Print("party announcements: " .. Ann:StatusText() .. ".")
	if ns.UI and ns.UI.RefreshOptions then ns.UI:RefreshOptions() end
end, "/nq announce [on|off|test|objectives|quests|turnins|attunements|raid|shared] - completion messages in party chat")
