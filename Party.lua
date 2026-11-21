-- NeverQuest Party: shares quest progress with party members who also run NeverQuest, so the
-- Quests tab and guide can show where everyone is on a shared quest.
-- Message format (prefix "NeverQuest"): "H" hello, "S!" / "S" snapshot chunks, "U" updates,
-- "X" removals; entries are questID:state where state is a percent or "c" for complete.
-- "P" carries spawn spots and marks (see Spawns.lua), "Q" quest start locations, "R" a request
-- for quest starts and "B" a batch answering one (all QuestDB.lua).
--
-- Progress sharing ("H", "S", "U", "X") is party only: it's about who is where on a quest you
-- are doing together. Quest start locations also go to the guild, where there are far more
-- people at more levels, which is what makes the database fill in.

local ADDON, ns = ...
local Party = { members = {} }
ns.Party = Party

local PREFIX = "NeverQuest"
local MAX_LEN = 240
local lastSent = {}

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
end

local function Apply(member, body)
	for entry in body:gmatch("[^,]+") do
		local qid, st = entry:match("^(%d+):(%w+)$")
		qid = tonumber(qid)
		if qid then member.quests[qid] = st end
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
	local member = Party.members[name] or { quests = {} }
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
		for qid in body:gmatch("%d+") do member.quests[tonumber(qid)] = nil end
	elseif kind == "P" then
		if ns.Spawns then ns.Spawns:FromParty(name, body) end
	elseif kind == "Q" then
		if ns.QuestDB then ns.QuestDB:FromParty(name, body) end
	end
	ns.Debug("party: update from " .. name)
	ns:SendMessage("PARTY_UPDATED")
end)

-- "Anna 40%, Tom done" for everyone else on this quest.
function Party:Summary(questID)
	local parts = {}
	for name, member in pairs(self.members) do
		local st = member.quests[questID]
		if st then table.insert(parts, name .. " " .. (st == "c" and "done" or (st .. "%"))) end
	end
	if #parts == 0 then return nil end
	table.sort(parts)
	return table.concat(parts, ", ")
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
		ns:SendMessage("PARTY_UPDATED")
	end
	wasInGroup = inGroup
end)

ns:RegisterMessage("QUESTS_UPDATED", function()
	ns.Debounce("partychanges", 1.5, function() Party:SendChanges() end)
end)

-- Forget members who have gone quiet for 15 minutes.
ns.Ticker(60, "Party sync", function()
	local now = GetTime()
	for name, member in pairs(Party.members) do
		if now - (member.t or 0) > 900 then Party.members[name] = nil end
	end
end)
