-- NeverQuest Journal: a history of the quests you've turned in, and level splits compared with
-- your fastest character for each level.

local ADDON, ns = ...
local J = {}
ns.Journal = J

local MAX_ENTRIES = 1500

ns:RegisterEvent("QUEST_TURNED_IN", function(_, questID, xpReward, moneyReward)
	if not ns.ready or not questID then return end
	local e = ns.Quests.byID[questID]
	local m = C_Map.GetBestMapForUnit("player")
	local log = ns.char.journal
	table.insert(log, {
		t = time(), q = questID,
		title = (e and e.title) or C_QuestLog.GetTitleForQuestID(questID) or ("Quest " .. questID),
		xp = ns.Num(xpReward), money = ns.Num(moneyReward),
		zone = (e and e.zone) or (m and ns.Nav.MapName(ns.Nav.GetZoneMap(m))) or nil,
		level = UnitLevel("player"),
	})
	while #log > MAX_ENTRIES do table.remove(log, 1) end
	ns:SendMessage("JOURNAL_UPDATED")
end)

-- When a level ends, its time becomes a split. Levels NeverQuest only saw part of don't count as records.
ns:RegisterEvent("PLAYER_LEVEL_UP", function(_, level)
	if not ns.ready or not level then return end
	local finished = level - 1
	local rec = ns.char.levels[finished]
	if not rec or rec.partial or (rec.time or 0) < 30 then return end
	local best = ns.db.bestLevels[finished]
	local who = ns.SafeName("player") or "?"
	if not best or rec.time < best.time then
		local beat = best and (best.time - rec.time) or nil
		ns.db.bestLevels[finished] = { time = rec.time, who = who }
		if beat then
			ns.Print(string.format("level %d in %s, a new best by %s.", finished, ns.Duration(rec.time), ns.Duration(beat)))
		end
	end
	ns:SendMessage("JOURNAL_UPDATED")
end)

local function Ago(t)
	local d = time() - (t or 0)
	if d < 3600 then return math.max(1, math.floor(d / 60)) .. "m ago" end
	if d < 86400 then return math.floor(d / 3600) .. "h ago" end
	return date("%b %d", t)
end

function J:HistoryItems()
	local items, log = {}, ns.char.journal
	for i = #log, 1, -1 do
		local e = log[i]
		local parts = {}
		if e.zone then table.insert(parts, e.zone) end
		if e.level then table.insert(parts, "level " .. e.level) end
		if e.xp and e.xp > 0 then table.insert(parts, "+" .. ns.Comma(e.xp) .. " XP") end
		if e.money and e.money > 0 then table.insert(parts, ns.Money(e.money)) end
		table.insert(items, { key = "j:" .. i, kind = "turnin", title = e.title, sub = table.concat(parts, "  ·  "), right = Ago(e.t) })
	end
	if #items == 0 then
		table.insert(items, { key = "j:none", kind = "tip", title = "No quests turned in yet", sub = "Every turn-in on this character lands here." })
	end
	return items
end

function J:SplitItems()
	local items = {}
	local current = UnitLevel("player")
	local total, bestTotal, comparable = 0, 0, true
	for level = 1, current do
		local rec = ns.char.levels[level]
		local best = ns.db.bestLevels[level]
		if rec and (rec.time or 0) > 0 then
			local parts = {}
			if level == current then table.insert(parts, "in progress") end
			if rec.partial then table.insert(parts, "|cff999999started before NeverQuest|r") end
			local q, k = rec.quest or 0, rec.kill or 0
			if q + k > 0 then table.insert(parts, string.format("%d%% from quests", math.floor(q / (q + k) * 100 + 0.5))) end
			if best then table.insert(parts, "best " .. ns.Duration(best.time) .. " (" .. (best.who or "?") .. ")") end
			local right = ns.Duration(rec.time)
			if best and level < current and not rec.partial then
				local diff = rec.time - best.time
				if math.abs(diff) >= 1 then
					right = right .. (diff <= 0 and "  |cff66ff66-" or "  |cffff6666+") .. ns.Duration(math.abs(diff)) .. "|r"
				end
			end
			table.insert(items, { key = "s:" .. level, kind = "level", title = "Level " .. level, sub = table.concat(parts, "  ·  "), right = right })
			total = total + rec.time
			if best and not rec.partial then bestTotal = bestTotal + best.time else comparable = false end
		end
	end
	if #items == 0 then
		table.insert(items, { key = "s:none", kind = "tip", title = "No level times yet", sub = "Time on each level is tracked while NeverQuest is loaded." })
	else
		table.insert(items, 1, { key = "s:total", kind = "tip", title = "Total played on tracked levels: " .. ns.Duration(total),
			sub = comparable and ("Your best characters combined: " .. ns.Duration(bestTotal)) or "Splits compare each level with your fastest character." })
	end
	return items
end
