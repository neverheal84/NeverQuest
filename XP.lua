-- NeverQuest XP: XP/hour, time to level, quests or kills to level, and the rested pool.

local ADDON, ns = ...
local XP = {}
ns.XP = XP

local WINDOW = 30 * 60          -- rolling window for XP/hour
local SAMPLE_LIMIT = 25         -- recent quest/kill XP values kept for averages

XP.gains = {}                   -- { t = GetTime(), xp = n }
XP.questSamples, XP.killSamples = {}, {}
XP.pendingTurnIns = {}          -- { t = GetTime(), xp = n } from QUEST_TURNED_IN
XP.session = { start = 0, total = 0, quest = 0, kill = 0, quests = 0, kills = 0 }

local function PushSample(list, v)
	table.insert(list, v)
	if #list > SAMPLE_LIMIT then table.remove(list, 1) end
end

local function Average(list)
	if #list == 0 then return nil end
	local sum = 0
	for _, v in ipairs(list) do sum = sum + v end
	return sum / #list
end

function XP:IsMaxLevel()
	if IsXPUserDisabled and IsXPUserDisabled() then return true end
	local maxLevel = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or 60
	return UnitLevel("player") >= maxLevel
end

function XP:LevelRecord(level)
	local levels = ns.char.levels
	if not levels[level] then
		local rec = { time = 0, quest = 0, kill = 0 }
		-- If we first see a level part-way through, its time can't count as a split record.
		if level == UnitLevel("player") then
			local cur, max = ns.Num(UnitXP("player")) or 0, ns.Num(UnitXPMax("player")) or 1
			if max > 0 and cur / max > 0.03 then rec.partial = true end
		end
		levels[level] = rec
	end
	return levels[level]
end

-- Decides whether an XP gain came from a quest turn-in or from kills/exploration.
function XP:Classify(delta, when)
	local level = UnitLevel("player")
	for i, p in ipairs(self.pendingTurnIns) do
		if math.abs(p.t - when) <= 2 and math.abs(p.xp - delta) <= math.max(2, p.xp * 0.03) then
			table.remove(self.pendingTurnIns, i)
			ns.Debug("+" .. delta .. " XP from a quest")
			self.session.quest = self.session.quest + delta
			self.session.quests = self.session.quests + 1
			PushSample(self.questSamples, delta)
			local rec = self:LevelRecord(level)
			rec.quest = rec.quest + delta
			return
		end
	end
	self.session.kill = self.session.kill + delta
	self.session.kills = self.session.kills + 1
	PushSample(self.killSamples, delta)
	local rec = self:LevelRecord(level)
	rec.kill = rec.kill + delta
	ns:SendMessage("KILL_XP", delta)
end

function XP:OnXPUpdate()
	local cur, max = ns.Num(UnitXP("player")), ns.Num(UnitXPMax("player"))
	local level = UnitLevel("player")
	if not cur or not max then return end
	local delta = 0
	if self.lastXP then
		if level > (self.lastLevel or level) then
			delta = ((self.lastMax or 0) - self.lastXP) + cur
		elseif level == self.lastLevel then
			delta = cur - self.lastXP
		end
	end
	self.lastXP, self.lastMax, self.lastLevel = cur, max, level
	if delta > 0 then
		local now = GetTime()
		table.insert(self.gains, { t = now, xp = delta })
		self.session.total = self.session.total + delta
		-- QUEST_TURNED_IN can arrive just before or just after the XP update.
		ns.After(0.4, function() XP:Classify(delta, now) end)
	end
	self:Refresh()
end

function XP:XPPerHour()
	local now = GetTime()
	while self.gains[1] and now - self.gains[1].t > WINDOW do
		table.remove(self.gains, 1)
	end
	local sum = 0
	for _, g in ipairs(self.gains) do sum = sum + g.xp end
	local span = math.min(WINDOW, now - self.session.start)
	if span < 120 or sum == 0 then return nil end
	return sum / span * 3600
end

-- Average XP of quests: recent turn-ins first, then rewards of quests in the log.
function XP:AverageQuestXP()
	local avg = Average(self.questSamples)
	if avg then return avg end
	if ns.Quests and ns.Quests.log then
		local sum, n = 0, 0
		for _, e in ipairs(ns.Quests.log) do
			if e.xp and e.xp > 0 then sum, n = sum + e.xp, n + 1 end
		end
		if n > 0 then return sum / n end
	end
end

function XP:Stats()
	local cur, max = ns.Num(UnitXP("player")) or 0, ns.Num(UnitXPMax("player")) or 1
	local remaining = math.max(0, max - cur)
	local rested = ns.Num(GetXPExhaustion()) or 0
	local perHour = self:XPPerHour()
	local avgQuest, avgKill = self:AverageQuestXP(), Average(self.killSamples)
	return {
		level = UnitLevel("player"), cur = cur, max = max, remaining = remaining,
		pct = max > 0 and cur / max * 100 or 0,
		rested = rested, restedPct = max > 0 and rested / max * 100 or 0,
		resting = IsResting(),
		perHour = perHour,
		toLevel = perHour and remaining / perHour * 3600 or nil,
		questsToLevel = avgQuest and avgQuest > 0 and math.ceil(remaining / avgQuest) or nil,
		killsToLevel = avgKill and avgKill > 0 and math.ceil(remaining / avgKill) or nil,
		avgQuest = avgQuest, avgKill = avgKill,
	}
end

---------------------------------------------------------------------------
-- HUD
---------------------------------------------------------------------------
local function CreateHUD()
	local f = CreateFrame("Frame", "NeverQuestHUD", UIParent, "BackdropTemplate")
	f:SetSize(250, 92)
	f:SetFrameStrata("LOW")
	ns.ApplyBackdrop(f, 0.75)
	ns.MakeMovable(f, "hud", function() return ns.db.hud.locked end, { "TOPRIGHT", UIParent, "TOPRIGHT", -240, -210 })

	f.lines = {}
	for i = 1, 5 do
		local fs = f:CreateFontString(nil, "OVERLAY", i == 1 and "NeverQuestFontNormal" or "NeverQuestFontSmall")
		fs:SetPoint("TOPLEFT", 9, -8 - (i - 1) * 15)
		fs:SetPoint("RIGHT", -9, 0)
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(false)
		f.lines[i] = fs
	end

	f.bar = f:CreateTexture(nil, "ARTWORK")
	f.bar:SetPoint("BOTTOMLEFT", 5, 5)
	f.bar:SetHeight(3)
	f.bar:SetColorTexture(0.58, 0.0, 0.55, 0.9)
	f.restBar = f:CreateTexture(nil, "BORDER")
	f.restBar:SetPoint("BOTTOMLEFT", 5, 5)
	f.restBar:SetHeight(3)
	f.restBar:SetColorTexture(0.0, 0.39, 0.88, 0.6)

	f:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" and ns.UI then ns.UI:Toggle() end
	end)
	f:SetScript("OnEnter", function(self)
		local s = XP:Stats()
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("NeverQuest XP")
		GameTooltip:AddDoubleLine("Session XP", ns.Comma(XP.session.total), 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine("  from quests", string.format("%s (%d turn-ins)", ns.Comma(XP.session.quest), XP.session.quests), 0.8, 0.8, 0.8, 1, 1, 1)
		GameTooltip:AddDoubleLine("  kills & exploring", string.format("%s (%d)", ns.Comma(XP.session.kill), XP.session.kills), 0.8, 0.8, 0.8, 1, 1, 1)
		if s.avgQuest then GameTooltip:AddDoubleLine("Avg quest XP", ns.Comma(s.avgQuest), 1, 1, 1, 1, 1, 1) end
		if s.avgKill then GameTooltip:AddDoubleLine("Avg kill XP", ns.Comma(s.avgKill), 1, 1, 1, 1, 1, 1) end
		local rec = ns.char.levels[s.level]
		if rec and rec.time > 0 then GameTooltip:AddDoubleLine("Time on this level", ns.Duration(rec.time), 1, 1, 1, 1, 1, 1) end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Rested XP doubles XP from kills only, not quest turn-ins.", 0.6, 0.8, 1, true)
		GameTooltip:AddLine("Right-click: open NeverQuest. Drag: move.", 0.7, 0.7, 0.7)
		ns.TipShow("Session XP: " .. ns.Comma(XP.session.total) .. (s.perHour and ("  ·  " .. ns.Comma(s.perHour) .. " XP/hour") or ""))
	end)
	f:SetScript("OnLeave", GameTooltip_Hide)
	return f
end

function XP:Refresh()
	local f = self.hud
	if not f then return end
	if not ns.db.hud.shown or self:IsMaxLevel() then
		f:Hide()
		return
	end
	f:Show()
	f:SetScale(ns.db.hud.scale or 1)
	local s = self:Stats()
	local L = f.lines
	L[1]:SetFormattedText("Level %d  |cffffffff%.1f%%|r  (%s / %s)", s.level, s.pct, ns.Comma(s.cur), ns.Comma(s.max))
	if s.rested > 0 then
		L[2]:SetFormattedText("|cff4d9fffRested: %s (%.0f%% of level)|r%s", ns.Comma(s.rested), s.restedPct, s.resting and "  |cff88ff88resting|r" or "")
	else
		L[2]:SetText(s.resting and "|cff888888No rested XP yet|r  |cff88ff88resting|r" or "|cff888888No rested XP|r")
	end
	if s.perHour then
		L[3]:SetFormattedText("XP/hr: |cffffffff%s|r   Level in: |cffffffff%s|r", ns.Comma(s.perHour), ns.Duration(s.toLevel))
	else
		L[3]:SetText("XP/hr: |cff888888gathering data...|r")
	end
	local parts = {}
	if s.questsToLevel then table.insert(parts, "~" .. s.questsToLevel .. " quests") end
	if s.killsToLevel then table.insert(parts, "~" .. s.killsToLevel .. " kills") end
	L[4]:SetText("To level: " .. (#parts > 0 and ("|cffffffff" .. table.concat(parts, "|r or |cffffffff") .. "|r") or "|cff888888--|r") .. "  (" .. ns.Comma(s.remaining) .. " XP)")
	local ready, readyXP = 0, 0
	if ns.Quests then
		for _, e in ipairs(ns.Quests.log) do
			if e.complete then ready, readyXP = ready + 1, readyXP + (e.xp or 0) end
		end
	end
	if ready > 0 then
		L[5]:SetFormattedText("|cff88ff88Ready to turn in: %d quest%s (+%s XP)|r", ready, ready == 1 and "" or "s", ns.Comma(readyXP))
	else
		L[5]:SetFormattedText("Session: +%s XP", ns.Comma(self.session.total))
	end

	-- Lines you've turned off are hidden and the rest move up; spacing follows the text size.
	local cfg = ns.db.hud
	local show = { true, cfg.showRested, cfg.showRate, cfg.showToLevel, cfg.showFooter }
	local y = 8
	for i, fs in ipairs(L) do
		if show[i] then
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", 9, -y)
			fs:SetPoint("RIGHT", -9, 0)
			fs:Show()
			y = y + ns.Style:LineHeight(i == 1 and "NeverQuestFontNormal" or "NeverQuestFontSmall")
		else
			fs:Hide()
		end
	end
	f:SetWidth(250 * math.max(1, ns.db.style.textScale or 1))
	f:SetHeight(y + 9)

	local width = f:GetWidth() - 10
	f.bar:SetWidth(math.max(1, width * s.cur / math.max(1, s.max)))
	local restEnd = math.min(s.max, s.cur + s.rested)
	f.restBar:SetWidth(math.max(1, width * restEnd / math.max(1, s.max)))
	f.restBar:SetShown(s.rested > 0)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns:OnInit(function()
	XP.hud = CreateHUD()
	XP.session.start = GetTime()
end)

ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
	XP.lastXP, XP.lastMax, XP.lastLevel = ns.Num(UnitXP("player")), ns.Num(UnitXPMax("player")), UnitLevel("player")
	XP:Refresh()
end)

ns:RegisterEvent("PLAYER_XP_UPDATE", function(_, unit)
	if unit == nil or unit == "player" then XP:OnXPUpdate() end
end)

ns:RegisterMessage("STYLE_CHANGED", function() XP:Refresh() end)

ns:RegisterEvent("QUEST_TURNED_IN", function(_, questID, xpReward)
	local xp = ns.Num(xpReward)
	if xp and xp > 0 then
		table.insert(XP.pendingTurnIns, { t = GetTime(), xp = xp })
		while #XP.pendingTurnIns > 10 do table.remove(XP.pendingTurnIns, 1) end
	end
end)

ns:RegisterEvent("UPDATE_EXHAUSTION", function() XP:Refresh() end)
ns:RegisterEvent("PLAYER_UPDATE_RESTING", function() XP:Refresh() end)
ns:RegisterEvent("PLAYER_LEVEL_UP", function(_, level)
	-- A level we saw start is a full split, even if the turn-in that leveled us overflowed into it.
	if ns.ready and level and not ns.char.levels[level] then
		ns.char.levels[level] = { time = 0, quest = 0, kill = 0 }
	end
	ns.After(0.5, function() XP:Refresh() end)
end)
ns:RegisterMessage("QUESTS_UPDATED", function() XP:Refresh() end)
ns:RegisterMessage("POSITIONS_RESET", function() if XP.hud then XP.hud:RestorePosition() end end)

-- Time-based numbers refresh every few seconds; time per level is saved per character.
local lastTick
ns.Ticker(5, "XP tracking", function()
	if not ns.ready then return end
	local now = GetTime()
	if lastTick and not XP:IsMaxLevel() then
		local rec = XP:LevelRecord(UnitLevel("player"))
		rec.time = rec.time + (now - lastTick)
	end
	lastTick = now
	XP:Refresh()
end)

ns:AddSlash("hud", function()
	ns.db.hud.shown = not ns.db.hud.shown
	XP:Refresh()
	ns.Print(ns.db.hud.shown and "XP panel shown." or "XP panel hidden.")
end, "/nq hud - show or hide the XP panel")

ns:AddSlash("xp", function()
	local s = XP:Stats()
	ns.Print(string.format("Level %d %.1f%%, %s XP to go. XP/hr %s, level in %s. Rested %s.",
		s.level, s.pct, ns.Comma(s.remaining), s.perHour and ns.Comma(s.perHour) or "--", ns.Duration(s.toLevel), ns.Comma(s.rested)))
end, "/nq xp - print XP stats to chat")
