-- NeverQuest Party: shares quest progress with party members who also run NeverQuest, so the
-- Quests tab and guide can show where everyone is on a shared quest.
-- Message format (prefix "NeverQuest"): "H" hello, "S!" / "S" snapshot chunks, "U" updates,
-- "X" removals; entries are questID:state where state is a percent or "c" for complete.
-- "P" carries spawn spots and marks (see Spawns.lua), "Q" quest start locations, "R" a request
-- for quest starts and "B" a batch answering one (all QuestDB.lua).
-- "O!" / "O" (1.26) carry which objectives are finished: questID:flags, one "1" or "0" per
-- objective, so the party view knows who still needs what. Older versions ignore them.
--
-- Party members who don't run NeverQuest still show: the game says which quests they're on
-- (not how far along), checked for your own quests and the ones on offer near you.
--
-- Progress sharing ("H", "S", "U", "X") is party only: it's about who is where on a quest you
-- are doing together. Quest start locations also go to the guild, where there are far more
-- people at more levels, which is what makes the database fill in.

local ADDON, ns = ...
local Party = { members = {} }
ns.Party = Party

local PREFIX = "NeverQuest"
local MAX_LEN = 240
local lastSent, lastObj = {}, {}
local PROBE_SECS = 5

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

local function Active()
	return ns.ready and ns.db.party.enabled and IsInGroup() and not IsInRaid()
end

-- True when the game took the message. Current clients answer with a result code (0 is
-- success, anything else is a refusal such as the per-addon throttle); older ones answer true
-- or nothing at all. Only a real refusal counts as one.
local function SendTo(msg, channel)
	local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, channel)
	local delivered = ok and (result == nil or result == true or result == 0)
	if not delivered and channel == "PARTY" then
		-- Throttled or locked down (restricted content): try a full resend later.
		Party.retry = true
	end
	return delivered
end

local function Send(msg) return SendTo(msg, "PARTY") end

local function StateOf(e)
	if e.complete then return "c" end
	return tostring(math.floor((e.progress or 0) * 100 + 0.5))
end

-- "101": the first and third objectives are finished.
local function FlagsOf(questID)
	local objs = ns.SafeCall(C_QuestLog.GetQuestObjectives, questID)
	if type(objs) ~= "table" or #objs == 0 then return nil end
	local s = {}
	for i, o in ipairs(objs) do s[i] = o.finished and "1" or "0" end
	return table.concat(s)
end
Party.FlagsOf = FlagsOf

-- Sends entries in chunks that fit an addon message.
local function SendEntries(kind, entries, firstKind)
	local chunk, prefix = {}, firstKind or kind
	local len = #prefix
	for _, entry in ipairs(entries) do
		if len + #entry + 1 > MAX_LEN and #chunk > 0 then
			Send(prefix .. table.concat(chunk, ","))
			chunk, prefix, len = {}, kind, #kind
		end
		table.insert(chunk, entry)
		len = len + #entry + 1
	end
	if #chunk > 0 or firstKind then Send(prefix .. table.concat(chunk, ",")) end
end

function Party:IsActive()
	return Active() and true or false
end

function Party:GuildActive()
	return (ns.ready and IsInGuild and IsInGuild() and true) or false
end

-- Other modules (spawn and quest start sharing) send their own message kinds through here.
-- where: "party" (the default), "guild", or "both".
function Party:SendRaw(msg, where)
	where = where or "party"
	-- Answers whether the game actually took it on at least one channel, so a caller that
	-- paces itself (or counts what it has shared) goes by what was delivered.
	local sent = false
	if (where == "party" or where == "both") and Active() then
		if Send(msg) then sent = true end
	end
	if (where == "guild" or where == "both") and self:GuildActive() then
		if SendTo(msg, "GUILD") then sent = true end
	end
	return sent
end

function Party:SendSnapshot()
	if not Active() then return end
	wipe(lastSent)
	local entries = {}
	for _, e in ipairs(ns.Quests.log) do
		local st = StateOf(e)
		lastSent[e.questID] = st
		table.insert(entries, e.questID .. ":" .. st)
	end
	SendEntries("S", entries, "S!")
	wipe(lastObj)
	local flags = {}
	for _, e in ipairs(ns.Quests.log) do
		local f = FlagsOf(e.questID)
		if f then
			lastObj[e.questID] = f
			table.insert(flags, e.questID .. ":" .. f)
		end
	end
	SendEntries("O", flags, "O!")
	self.retry = false
	ns.Debug("party: sent " .. #entries .. " quests")
end

function Party:SendChanges()
	if not Active() then return end
	if self.retry then return self:SendSnapshot() end
	local changed, removed, present = {}, {}, {}
	for _, e in ipairs(ns.Quests.log) do
		local st = StateOf(e)
		present[e.questID] = true
		if lastSent[e.questID] ~= st then
			lastSent[e.questID] = st
			table.insert(changed, e.questID .. ":" .. st)
		end
	end
	for qid in pairs(lastSent) do
		if not present[qid] then
			lastSent[qid] = nil
			table.insert(removed, tostring(qid))
		end
	end
	if #changed > 0 then SendEntries("U", changed) end
	if #removed > 0 then SendEntries("X", removed) end
	local flags = {}
	for _, e in ipairs(ns.Quests.log) do
		local f = FlagsOf(e.questID)
		if f and lastObj[e.questID] ~= f then
			lastObj[e.questID] = f
			table.insert(flags, e.questID .. ":" .. f)
		end
	end
	for qid in pairs(lastObj) do
		if not present[qid] then lastObj[qid] = nil end
	end
	if #flags > 0 then SendEntries("O", flags) end
end

local function Apply(member, body)
	for entry in body:gmatch("[^,]+") do
		local qid, st = entry:match("^(%d+):(%w+)$")
		qid = tonumber(qid)
		if qid then member.quests[qid] = st end
	end
end

local function ApplyFlags(member, body)
	for entry in body:gmatch("[^,]+") do
		local qid, flags = entry:match("^(%d+):([01]+)$")
		qid = tonumber(qid)
		if qid then member.obj[qid] = flags end
	end
end

ns:RegisterEvent("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
	if prefix ~= PREFIX or not ns.ready then return end
	if channel ~= "PARTY" and channel ~= "GUILD" then return end
	if channel == "PARTY" and not ns.db.party.enabled then return end
	if type(text) ~= "string" or type(sender) ~= "string" or ns.IsSecret(text) or ns.IsSecret(sender) then return end
	local name = Ambiguate(sender, "short")
	if name == ns.SafeName("player") then return end
	-- Guildmates trade quest starts and nothing else: progress belongs to the party you're in.
	if channel == "GUILD" then
		if not ns.QuestDB then return end
		local k, b2 = text:sub(1, 1), text:sub(2)
		if k == "Q" then ns.QuestDB:FromParty(name, b2, "guild")
		elseif k == "R" then ns.QuestDB:OnAsked(name)
		elseif k == "B" then ns.QuestDB:FromBatch(name, b2) end
		return
	end
	local member = Party.members[name] or { quests = {}, obj = {} }
	member.obj = member.obj or {}
	Party.members[name] = member
	member.t = GetTime()
	local kind, body = text:sub(1, 1), text:sub(2)
	if kind == "H" then
		ns.Debounce("partysnapshot", 1 + math.random(), function() Party:SendSnapshot() end)
	elseif kind == "S" then
		if body:sub(1, 1) == "!" then
			wipe(member.quests)
			body = body:sub(2)
		end
		Apply(member, body)
	elseif kind == "U" then
		Apply(member, body)
	elseif kind == "X" then
		for qid in body:gmatch("%d+") do
			member.quests[tonumber(qid)] = nil
			member.obj[tonumber(qid)] = nil
		end
	elseif kind == "O" then
		if body:sub(1, 1) == "!" then
			wipe(member.obj)
			body = body:sub(2)
		end
		ApplyFlags(member, body)
	elseif kind == "P" then
		if ns.Spawns then ns.Spawns:FromParty(name, body) end
	elseif kind == "Q" then
		if ns.QuestDB then ns.QuestDB:FromParty(name, body) end
	end
	ns.Debug("party: update from " .. name)
	if kind == "S" or kind == "U" or kind == "O" or kind == "X" then Party:Notice(name) end
	ns:SendMessage("PARTY_UPDATED")
end)

---------------------------------------------------------------------------
-- Everyone in the party, NeverQuest or not
---------------------------------------------------------------------------
local probes, probeT = {}, {}

-- Whether a party member is on a quest, from the game. The newer call takes any quest; the
-- older one only quests in your own log. nil when the game can't say.
local function UnitOnQuest(unit, qid)
	if C_QuestLog.IsUnitOnQuest then
		return ns.SafeCall(C_QuestLog.IsUnitOnQuest, unit, qid) == true
	end
	if IsUnitOnQuest and C_QuestLog.GetLogIndexForQuestID then
		local idx = ns.SafeCall(C_QuestLog.GetLogIndexForQuestID, qid)
		if not idx then return false end
		local on = ns.SafeCall(IsUnitOnQuest, idx, unit)
		return on == true or on == 1
	end
	return nil
end
Party.UnitOnQuest = UnitOnQuest

-- Quests a member without NeverQuest is on, as "?" (on it, progress unknown). Checked for your
-- quests and the ones on offer near you, at most every few seconds per member.
function Party:Probe(unit, name)
	local key, now = name or unit, GetTime()
	if probes[key] and now - (probeT[key] or 0) < PROBE_SECS then return probes[key] end
	local t = {}
	if UnitOnQuest(unit, 0) ~= nil then
		for _, e in ipairs(ns.Quests.log) do
			if UnitOnQuest(unit, e.questID) then t[e.questID] = "?" end
		end
		if C_QuestLog.IsUnitOnQuest then
			for _, o in ipairs(ns.Quests.offers) do
				if UnitOnQuest(unit, o.questID) then t[o.questID] = "?" end
			end
		end
	end
	probes[key], probeT[key] = t, now
	return t
end

function Party:ForgetProbes()
	wipe(probes)
	wipe(probeT)
end

-- Everyone else in the party: unit, name, level, class, whether they run NeverQuest, and their
-- quests (questID = percent, "c" done, or "?" on it) with objective flags when they run it.
function Party:Roster()
	local out = {}
	if not (ns.ready and IsInGroup() and not IsInRaid()) then return out end
	for i = 1, 4 do
		local unit = "party" .. i
		if UnitExists(unit) then
			local name = ns.SafeName(unit) or unit
			local member = self.members[name]
			local r = { unit = unit, name = name, level = ns.Num(UnitLevel(unit)), class = select(2, UnitClass(unit)),
				addon = member ~= nil }
			if member then
				r.quests, r.obj = member.quests, member.obj or {}
			elseif ns.db.party.probe ~= false then
				r.quests, r.obj = self:Probe(unit, name), {}
			else
				r.quests, r.obj = {}, {}
			end
			table.insert(out, r)
		end
	end
	return out
end

-- "done", "40%" or "on it".
local function StateText(st)
	if st == "c" then return "done" end
	if st == "?" then return "on it" end
	return st .. "%"
end
Party.StateText = StateText

-- Objectives a member hasn't finished, from their flags: "2 of 3 left".
function Party:LeftText(flags)
	if not flags or flags == "" then return nil end
	local left = 0
	for c in flags:gmatch("0") do left = left + 1 end
	if left == 0 then return nil end
	return left .. " of " .. #flags .. " left"
end

-- "Anna 40%, Bea done, Tom on it" for everyone else on this quest.
function Party:Summary(questID)
	local parts, seen = {}, {}
	for _, r in ipairs(self:Roster()) do
		seen[r.name] = true
		local st = r.quests[questID]
		if st then table.insert(parts, r.name .. " " .. StateText(st)) end
	end
	-- Anyone heard from who isn't in the party list (just left, or before the list is ready).
	for name, member in pairs(self.members) do
		local st = not seen[name] and member.quests[questID]
		if st then table.insert(parts, name .. " " .. StateText(st)) end
	end
	if #parts == 0 then return nil end
	table.sort(parts)
	return table.concat(parts, ", ")
end

-- Your finished quests that everyone else on them has finished too: hand them in together.
function Party:ReadyTogether()
	local out, roster = {}, self:Roster()
	for _, e in ipairs(ns.Quests.log) do
		if e.complete then
			local others, all = 0, true
			for _, r in ipairs(roster) do
				local st = r.quests[e.questID]
				if st then
					others = others + 1
					if st ~= "c" then all = false end
				end
			end
			if others > 0 and all then table.insert(out, e) end
		end
	end
	return out
end

-- Where a quest's work is, for helping someone with it: a spot NeverQuest learned, or one from
-- QuestieDB's objectives.
function Party:WorkSpot(questID)
	local spot = ns.Spawns and ns.Spawns:AnySpotFor(questID)
	if spot and spot.m then return spot end
	local obj = ns.Library and ns.Library.Objectives and ns.Library:Objectives(questID)
	local s = type(obj) == "table" and obj.spots and obj.spots[1]
	if s and s.m then return { m = s.m, x = s.x, y = s.y } end
	return nil
end

-- What party members still need that you can help with: quests they're working on that you've
-- finished, or aren't on, with where the work is. Your own unfinished quests are left out (their
-- spots are on the map already).
function Party:HelpList()
	local by = {}
	for _, r in ipairs(self:Roster()) do
		for qid, st in pairs(r.quests) do
			local mine = ns.Quests.byID[qid]
			if st ~= "c" and (not mine or mine.complete) then
				local h = by[qid] or { questID = qid, who = {}, mine = mine }
				by[qid] = h
				local left = self:LeftText(r.obj[qid])
				table.insert(h.who, r.name .. " " .. StateText(st) .. (left and (", " .. left) or ""))
			end
		end
	end
	local out = {}
	for qid, h in pairs(by) do
		h.spot = self:WorkSpot(qid)
		h.title = (h.mine and h.mine.title) or ns.SafeCall(C_QuestLog.GetTitleForQuestID, qid)
			or (ns.Library and ns.Library.Entry and (function() local q = ns.Library:Entry(qid) return q and q.t end)())
			or ("Quest " .. qid)
		table.sort(h.who)
		table.insert(out, h)
	end
	table.sort(out, function(a, b) return a.questID < b.questID end)
	return out
end

---------------------------------------------------------------------------
-- Alerts: a chat line (and a sound) when someone on a quest you share finishes an objective
-- or the quest, and when everyone is ready to hand it in.
---------------------------------------------------------------------------
local heard, readyTold = {}, {}

local function Alert(text, sound)
	local cfg = ns.db.party
	if cfg.alerts == false then return end
	ns.Print("|cff66ccff" .. text .. "|r")
	-- The very first alert says how to turn them off, once.
	if not cfg.alertHint then
		cfg.alertHint = true
		ns.Print("|cff999999Party alerts: right-click the tracker's Party header, or type /nq party alerts off, to turn them off.|r")
	end
	if sound and cfg.alertSound ~= false and SOUNDKIT then ns.PlaySound(sound) end
end

---------------------------------------------------------------------------
-- Switches: /nq party, the tracker's Party header menu, the minimap button
---------------------------------------------------------------------------
Party.SWITCHES = {
	{ key = "alerts", db = "party", field = "alerts", label = "Party alerts in chat" },
	{ key = "sound", db = "party", field = "alertSound", label = "With a sound" },
	{ key = "map", db = "party", field = "mapHelp", label = "Map: what your party still needs" },
	{ key = "others", db = "party", field = "probe", label = "Quests of members without NeverQuest" },
	{ key = "view", db = "tracker", field = "partyView", label = "Party view in the tracker" },
}

function Party:Get(key)
	for _, s in ipairs(self.SWITCHES) do
		if s.key == key then return ns.db[s.db][s.field] ~= false end
	end
end

function Party:Set(key, on)
	for _, s in ipairs(self.SWITCHES) do
		if s.key == key then
			if on == nil then on = ns.db[s.db][s.field] == false end
			ns.db[s.db][s.field] = on and true or false
			if key == "others" then self:ForgetProbes() end
			ns:SendMessage("PARTY_UPDATED")
			if ns.Tracker and ns.Tracker.Refresh then ns.Tracker:Refresh() end
			if ns.UI and ns.UI.RefreshOptions then ns.UI:RefreshOptions() end
			return on
		end
	end
end

local function OnOff(on) return on and "on" or "off" end

ns:AddSlash("party", function(arg)
	local key, value = (arg or ""):lower():match("^(%S*)%s*(%S*)")
	if key == "" then
		local parts = {}
		for _, s in ipairs(Party.SWITCHES) do table.insert(parts, s.key .. " " .. OnOff(Party:Get(s.key))) end
		ns.Print("party: " .. table.concat(parts, ", ") .. ". /nq party <alerts|sound|map|others|view> [on|off]")
		return
	end
	if key == "quiet" or key == "off" then key, value = "alerts", "off" end
	if Party:Get(key) == nil or (value ~= "" and value ~= "on" and value ~= "off") then
		ns.Print("/nq party [alerts|sound|map|others|view] [on|off]")
		return
	end
	local want
	if value ~= "" then want = value == "on" end
	local on = Party:Set(key, want)
	for _, s in ipairs(Party.SWITCHES) do
		if s.key == key then ns.Print(s.label .. ": " .. OnOff(on) .. ".") end
	end
end, "/nq party [alerts|sound|map|others|view] [on|off] - party alerts, their sound, map help, members without NeverQuest, the tracker's party view")

function Party:CheckReady()
	for _, e in ipairs(self:ReadyTogether()) do
		if not readyTold[e.questID] then
			readyTold[e.questID] = true
			Alert("Everyone's ready to hand in " .. (e.title or "a quest") .. ".", SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE)
		end
	end
	for qid in pairs(readyTold) do
		if not ns.Quests.byID[qid] then readyTold[qid] = nil end
	end
end

-- Called after an update from a party member. The first thing heard about a quest from someone
-- is only remembered, so joining a group doesn't flood the chat.
function Party:Notice(name)
	local member = self.members[name]
	if not member then return end
	local was = heard[name]
	local now = {}
	for qid, st in pairs(member.quests) do now[qid] = { st = st, obj = member.obj and member.obj[qid] } end
	heard[name] = now
	if not was then return self:CheckReady() end
	for qid, cur in pairs(now) do
		local mine = ns.Quests.byID[qid]
		local before = was[qid]
		if mine and before then
			if cur.st == "c" and before.st ~= "c" then
				Alert(name .. " is ready to hand in " .. (mine.title or "a quest") .. ".", SOUNDKIT and SOUNDKIT.MAP_PING)
			elseif cur.obj and before.obj and #cur.obj == #before.obj then
				local objs = ns.SafeCall(C_QuestLog.GetQuestObjectives, qid)
				for i = 1, #cur.obj do
					if cur.obj:sub(i, i) == "1" and before.obj:sub(i, i) == "0" then
						local o = type(objs) == "table" and objs[i]
						-- Your own count ("2/6") isn't theirs, so it's left off.
						local what = (o and o.text and o.text ~= "" and not ns.IsSecret(o.text)) and o.text:gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", "") or ("objective " .. i)
						if what == "" then what = "objective " .. i end
						Alert(name .. " finished " .. what .. " (" .. (mine.title or "quest") .. ").", SOUNDKIT and SOUNDKIT.MAP_PING)
					end
				end
			end
		end
	end
	self:CheckReady()
end

local wasInGroup = false
ns:RegisterEvent("GROUP_ROSTER_UPDATE", function()
	local inGroup = IsInGroup() and not IsInRaid()
	if inGroup and not wasInGroup then
		if Active() then
			Send("H")
			ns.Debounce("partysnapshot", 1, function() Party:SendSnapshot() end)
		end
	elseif not inGroup then
		wipe(Party.members)
		wipe(lastSent)
		wipe(lastObj)
		wipe(heard)
		wipe(readyTold)
		ns:SendMessage("PARTY_UPDATED")
	end
	Party:ForgetProbes()
	wasInGroup = inGroup
end)

ns:RegisterMessage("QUESTS_UPDATED", function()
	ns.Debounce("partychanges", 1.5, function() Party:SendChanges() end)
	Party:ForgetProbes()
	if IsInGroup() and not IsInRaid() then ns.Debounce("partyready", 1, function() Party:CheckReady() end) end
end)
ns:RegisterMessage("OFFERS_UPDATED", function() Party:ForgetProbes() end)

-- A party member's quest log changed (they took, finished or dropped a quest): look again.
ns:RegisterEvent("UNIT_QUEST_LOG_CHANGED", function(_, unit)
	if type(unit) ~= "string" or not unit:match("^party%d$") then return end
	local name = ns.SafeName(unit)
	if name then probes[name], probeT[name] = nil, nil end
	ns.Debounce("partyprobe", 1, function() ns:SendMessage("PARTY_UPDATED") end)
end)

-- Forget members who have gone quiet for 15 minutes.
ns.Ticker(60, "Party sync", function()
	local now = GetTime()
	for name, member in pairs(Party.members) do
		if now - (member.t or 0) > 900 then Party.members[name] = nil end
	end
end)
