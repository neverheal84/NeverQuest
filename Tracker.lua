-- NeverQuest Tracker: the quest list on the right side of the screen, sorted by priority (the
-- order the guide and route planner will do things in) and grouped by zone.
--
-- It also decides what happens to Blizzard's own quest list in the objective tracker:
--   hide   while the NeverQuest tracker is shown, quests are untracked so Blizzard's list is
--          empty, the two settings that make the game track quests by itself are switched
--          off, and (unless turned off) Blizzard's tracker frame is parked on a hidden parent
--          so it cannot flash up. Inside a dungeon, raid or scenario the frame is given back,
--          because that is where the game shows boss and scenario objectives.
--   sort   Blizzard's list stays, with quests tracked in NeverQuest's priority order.
--   leave  NeverQuest doesn't touch it.
-- Everything changed is put back when you choose another mode, and again every time you log
-- out, so removing the addon never leaves quests untracked or a setting switched off. All of
-- it happens out of combat only.

local ADDON, ns = ...
local T = {}
ns.Tracker = T

local PAD = 8
local INDENT = 12
local MAX_WATCH = (Constants and Constants.QuestWatchConsts and Constants.QuestWatchConsts.MAX_QUEST_WATCHES) or 25

local function Cfg() return ns.db.tracker end

---------------------------------------------------------------------------
-- What to show, in what order
---------------------------------------------------------------------------
-- Priority: where the quest first appears in the guide's steps (the planned route when route
-- planning is on). Lower is sooner.
function T:Priorities()
	local rank = {}
	for i, s in ipairs(ns.Guide.steps or {}) do
		if s.questID and not rank[s.questID] then rank[s.questID] = i end
	end
	return rank
end

local function CurrentZone()
	local m = C_Map.GetBestMapForUnit("player")
	return m and ns.Nav.MapName(ns.Nav.GetZoneMap(m)) or nil
end

function T:Entries(mode)
	local cfg = Cfg()
	mode = mode or cfg.sort
	local rank = self:Priorities()
	local pinned, hidden = ns.char.trackerPinned, ns.char.trackerHidden
	local list = {}
	for _, e in ipairs(ns.Quests.log) do
		if not hidden[e.questID] and (cfg.showGray or not e.trivial or e.complete) then
			e.trackRank = rank[e.questID]
			table.insert(list, e)
		end
	end
	local function Key(e)
		if mode == "distance" then return e.dist or 1e9 end
		if mode == "level" then return e.level or 0 end
		return e.trackRank or (1000 + (e.dist or 1e6) / 1000)
	end
	table.sort(list, function(a, b)
		local pa, pb = pinned[a.questID] and 1 or 0, pinned[b.questID] and 1 or 0
		if pa ~= pb then return pa > pb end
		if cfg.finishedFirst and a.complete ~= b.complete then return a.complete end
		local ka, kb = Key(a), Key(b)
		if ka ~= kb then return ka < kb end
		return (a.title or "") < (b.title or "")
	end)
	return list
end

-- Groups of { zone, quests, best } with your current zone first.
function T:Groups(list)
	local cfg = Cfg()
	if not cfg.groupByZone then return { { zone = nil, quests = list } } end
	local here = CurrentZone()
	local byZone, groups = {}, {}
	for i, e in ipairs(list) do
		local z = e.zone or "Other"
		local g = byZone[z]
		if not g then
			g = { zone = z, quests = {}, best = i }
			byZone[z] = g
			table.insert(groups, g)
		end
		table.insert(g.quests, e)
	end
	table.sort(groups, function(a, b)
		if cfg.currentZoneFirst and here then
			local ha, hb = a.zone == here, b.zone == here
			if ha ~= hb then return ha end
		end
		return a.best < b.best
	end)
	return groups, here
end

local function ZoneCollapsed(zone, here)
	local state = ns.char.trackerZones[zone]
	if state ~= nil then return state end
	return Cfg().collapseOther and zone ~= here or false
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
local function OpenSettings()
	if ns.UI and ns.UI.OpenOptions then ns.UI:OpenOptions("tracker") end
end

function T:HeaderMenu(owner)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
	local cfg = Cfg()
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("NeverQuest tracker")
		local function Sort(value, label)
			root:CreateRadio(label, function() return cfg.sort == value end, function() cfg.sort = value T:Refresh() end)
		end
		Sort("priority", "Sort by priority (route order)")
		Sort("distance", "Sort by distance")
		Sort("level", "Sort by level")
		root:CreateDivider()
		local function Toggle(key, label)
			root:CreateCheckbox(label, function() return cfg[key] end, function() cfg[key] = not cfg[key] T:Refresh() end)
		end
		Toggle("groupByZone", "Group by zone")
		Toggle("collapseOther", "Collapse other zones")
		Toggle("showObjectives", "Show objectives")
		Toggle("finishedFirst", "Finished quests first")
		Toggle("locked", "Lock position")
		local hidden = 0
		for _ in pairs(ns.char.trackerHidden) do hidden = hidden + 1 end
		if hidden > 0 then
			root:CreateButton("Show " .. hidden .. " hidden " .. (hidden == 1 and "quest" or "quests"), function()
				wipe(ns.char.trackerHidden)
				T:Refresh()
			end)
		end
		root:CreateDivider()
		root:CreateButton("Tracker settings...", OpenSettings)
	end)
end

function T:QuestMenu(owner, e)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
	local qid = e.questID
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(e.title or "Quest")
		if T.Target(e) then root:CreateButton("Point the arrow here", function() T:Point(e) end) end
		if QuestMapFrame_OpenToQuestDetails then
			root:CreateButton("Open in quest log", function() QuestMapFrame_OpenToQuestDetails(qid) end)
		end
		local pinned = ns.char.trackerPinned
		root:CreateButton(pinned[qid] and "Unpin" or "Pin to the top", function()
			pinned[qid] = (not pinned[qid]) or nil
			T:Refresh()
		end)
		if IsInGroup() and ns.SafeCall(C_QuestLog.IsPushableQuest, qid) == true then
			root:CreateButton("Share with party", function() ns.Catchup:Share(qid) end)
		end
		if (e.elite or e.group) and not e.complete and ns.Upkeep then
			root:CreateButton("Ask for a group (LFG message)", function() ns.Upkeep:AskForGroup(e) end)
		end
		root:CreateButton("Hide from the tracker", function()
			ns.char.trackerHidden[qid] = true
			T:Refresh()
		end)
	end)
end

-- Where clicking a quest points the arrow: its marker, or for a finished quest its hand-in.
function T.Target(e)
	if e.pos then return e.pos end
	local t = e.complete and e.turnin
	if t and t.m then return t end
end

function T:Point(e)
	local p = T.Target(e)
	if not p then return end
	local who = e.complete and e.turnin and e.turnin.npc
	ns.Guide:Pin({ key = (e.complete and "turnin:" or "objective:") .. e.questID, m = p.m, x = p.x, y = p.y,
		title = (e.complete and "Turn in: " or "") .. (e.title or "") .. (who and (" (" .. who .. ")") or ""), questID = e.questID })
end

local function InsertLink(questID)
	local link = GetQuestLink and GetQuestLink(questID)
	if not link then return end
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		ChatFrameUtil.InsertLink(link)
	elseif ChatEdit_InsertLink then
		ChatEdit_InsertLink(link)
	end
end

local function RowClick(row, button)
	local d = row.data
	if not d then return end
	if d.kind == "zone" then
		local collapsed = ZoneCollapsed(d.zone, d.here)
		ns.char.trackerZones[d.zone] = not collapsed
		T:Refresh()
	elseif d.e then
		if button == "RightButton" then
			T:QuestMenu(row, d.e)
		elseif IsShiftKeyDown() then
			InsertLink(d.e.questID)
		else
			T:Point(d.e)
		end
	end
end

local function RowEnter(row)
	local d = row.data
	if not d or not d.e then return end
	local e = d.e
	GameTooltip:SetOwner(row, "ANCHOR_LEFT")
	GameTooltip:AddLine(e.title or "", 1, 0.82, 0, true)
	if e.complete then
		GameTooltip:AddLine("Ready to turn in" .. (ns.Quests:TurnInName(e.questID) and (" to " .. ns.Quests:TurnInName(e.questID)) or ""), 0.4, 1, 0.4)
	end
	for _, o in ipairs(C_QuestLog.GetQuestObjectives(e.questID) or {}) do
		if o.text and o.text ~= "" and not ns.IsSecret(o.text) then
			if o.finished then GameTooltip:AddLine("- " .. o.text, 0.5, 0.5, 0.5, true) else GameTooltip:AddLine("- " .. o.text, 1, 1, 1, true) end
		end
	end
	if e.xp and e.xp > 0 then GameTooltip:AddLine("+" .. ns.Comma(e.xp) .. " XP", 0.8, 0.8, 0.8) end
	local chain = ns.Chains and ns.Chains:Label(e.questID)
	if chain then GameTooltip:AddLine(chain, 0.78, 0.64, 1) end
	if e.trackRank then GameTooltip:AddLine("Guide order: " .. e.trackRank, 0.6, 0.85, 1) end
	GameTooltip:AddLine("Click: point the arrow.  Shift+click: link.  Right-click: options.", 0.5, 0.8, 1, true)
	GameTooltip:Show()
end

function T:Row(i)
	local f = self.frame
	local row = f.rows[i]
	if row then return row end
	row = CreateFrame("Button", nil, f.content)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.right = row:CreateFontString(nil, "OVERLAY", "NeverQuestFontSmall")
	row.right:SetPoint("RIGHT", -2, 0)
	row.right:SetJustifyH("RIGHT")
	row.text = row:CreateFontString(nil, "OVERLAY", "NeverQuestFontHighlight")
	row.text:SetPoint("LEFT", 0, 0)
	row.text:SetPoint("RIGHT", row.right, "LEFT", -4, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.06)
	row:SetScript("OnClick", RowClick)
	row:SetScript("OnEnter", RowEnter)
	row:SetScript("OnLeave", GameTooltip_Hide)
	f.rows[i] = row
	return row
end

function T:Create()
	if self.frame then return self.frame end
	local cfg = Cfg()
	local f = CreateFrame("Frame", "NeverQuestTracker", UIParent, "BackdropTemplate")
	f:SetSize(cfg.width or 270, 60)
	f:SetFrameStrata("LOW")
	f.rows = {}
	ns.MakeMovable(f, "tracker", function() return Cfg().locked end, { "TOPRIGHT", UIParent, "TOPRIGHT", -40, -250 })

	local header = CreateFrame("Button", nil, f)
	header:SetPoint("TOPLEFT", PAD, -PAD + 2)
	header:SetPoint("TOPRIGHT", -PAD, -PAD + 2)
	header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function() if not Cfg().locked then f:StartMoving() end end)
	header:SetScript("OnDragStop", function() f:GetScript("OnDragStop")(f) end)
	header.text = header:CreateFontString(nil, "OVERLAY", "NeverQuestFontNormal")
	header.text:SetPoint("LEFT", 0, 0)
	header.count = header:CreateFontString(nil, "OVERLAY", "NeverQuestFontSmallGray")
	header.count:SetPoint("RIGHT", 0, 0)
	header:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			T:HeaderMenu(self)
		else
			Cfg().collapsed = not Cfg().collapsed
			T:Refresh()
		end
	end)
	header:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("NeverQuest quests")
		GameTooltip:AddLine("Click: collapse or expand.  Right-click: sort and options.  Drag: move.", 0.5, 0.8, 1, true)
		GameTooltip:Show()
	end)
	header:SetScript("OnLeave", GameTooltip_Hide)
	f.header = header

	f.content = CreateFrame("Frame", nil, f)
	f.content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
	f.content:SetPoint("RIGHT", -PAD, 0)
	f.content:SetHeight(1)

	f.more = f:CreateFontString(nil, "OVERLAY", "NeverQuestFontSmallGray")
	f.more:SetPoint("BOTTOMLEFT", PAD, PAD - 2)
	self.frame = f
	return f
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function Lines(self)
	local cfg = Cfg()
	local out = {}
	local list = self:Entries()
	local groups, here = self:Groups(list)
	local shown, n = 0, 0
	for _, g in ipairs(groups) do
		local collapsed = g.zone and ZoneCollapsed(g.zone, here)
		if g.zone then
			local focus = ns.Guide.focus
			local planned = focus and focus.zones and ns.Profiles.SameZone and (function()
				for name in pairs(focus.zones) do if ns.Profiles.SameZone(name, g.zone) then return true end end
			end)()
			table.insert(out, { kind = "zone", zone = g.zone, here = here,
				text = (collapsed and "+ " or "- ") .. g.zone .. (planned and "  |cff66ff66(your route)|r" or ""), right = tostring(#g.quests) })
		end
		if not collapsed then
			for _, e in ipairs(g.quests) do
				if shown >= (cfg.maxQuests or 25) then break end
				shown = shown + 1
				n = n + 1
				local title = e.title or "?"
				if cfg.showLevel and e.level then title = "[" .. e.level .. (e.elite and "+" or "") .. "] " .. title end
				if cfg.showNumbers and cfg.sort == "priority" and e.trackRank then title = n .. ". " .. title end
				if ns.char.trackerPinned[e.questID] then title = "* " .. title end
				local right = ""
				if e.complete then
					right = "|cff66ff66done|r"
				elseif cfg.showDistance and e.dist then
					right = ns.Yards(e.dist)
				end
				table.insert(out, { kind = "quest", e = e, text = title, right = right, color = { ns.QuestColor(e.questID) } })
				if e.complete then
					local npc = ns.Quests:TurnInName(e.questID)
					table.insert(out, { kind = "info", e = e, text = "Ready to turn in" .. (npc and (" to " .. npc) or ""),
						color = { 0.4, 1, 0.4 } })
				elseif cfg.showObjectives then
					for _, o in ipairs(C_QuestLog.GetQuestObjectives(e.questID) or {}) do
						if o.text and o.text ~= "" and not ns.IsSecret(o.text) and not (o.finished and cfg.hideDoneObjectives) then
							table.insert(out, { kind = "objective", e = e, text = "- " .. o.text,
								color = o.finished and { 0.5, 0.5, 0.5 } or { 0.9, 0.9, 0.9 } })
						end
					end
				end
				if cfg.showChains and ns.Chains then
					local chain = ns.Chains:Label(e.questID)
					if chain then table.insert(out, { kind = "info", e = e, text = chain, color = { 0.78, 0.64, 1 } }) end
				end
				if cfg.showParty and ns.Party then
					local party = ns.Party:Summary(e.questID)
					if party then table.insert(out, { kind = "info", e = e, text = "party: " .. party, color = { 0.4, 0.8, 1 } }) end
				end
			end
		end
	end
	return out, #list, shown
end

local FONT = { zone = "NeverQuestFontNormal", quest = "NeverQuestFontHighlight", objective = "NeverQuestFontSmall", info = "NeverQuestFontSmall" }

function T:Refresh()
	if not ns.ready then return end
	local cfg = Cfg()
	if not cfg.shown then
		if self.frame then self.frame:Hide() end
		return
	end
	local f = self:Create()
	f:SetScale(cfg.scale or 1)
	f:SetWidth(cfg.width or 270)
	local alpha = cfg.bgAlpha or 0.45
	if f.appliedAlpha ~= alpha then
		f.appliedAlpha = alpha
		ns.ApplyBackdrop(f, alpha)
		if alpha <= 0 then f:SetBackdropBorderColor(0, 0, 0, 0) end
	end
	f:Show()

	local St = ns.Style
	local headerH = St:LineHeight("NeverQuestFontNormal")
	f.header:SetHeight(headerH)
	f.header.text:SetText(cfg.collapsed and "+ Quests" or "Quests")
	local lines, total, shown = Lines(self)
	f.header.count:SetText(string.format("%d/%d", C_QuestLog.GetNumQuestLogEntries and select(2, C_QuestLog.GetNumQuestLogEntries()) or total,
		(C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept()) or 35))

	local y, used = 0, 0
	local maxH = (cfg.maxHeight or 520) - headerH - PAD * 2 - 16
	local hiddenLines = 0
	if not cfg.collapsed then
		for _, line in ipairs(lines) do
			local h = St:LineHeight(FONT[line.kind])
			if line.kind == "zone" and used > 0 then y = y + 4 end
			if y + h > maxH then
				hiddenLines = hiddenLines + 1
			else
				used = used + 1
				local row = self:Row(used)
				row.data = line
				row.text:SetFontObject(FONT[line.kind])
				row.right:SetFontObject("NeverQuestFontSmall")
				row.text:SetText(line.text or "")
				local c = line.color
				if c then row.text:SetTextColor(c[1], c[2], c[3]) elseif line.kind == "zone" then row.text:SetTextColor(1, 0.82, 0) end
				row.right:SetText(line.right or "")
				row:ClearAllPoints()
				local indent = (line.kind == "objective" or line.kind == "info") and INDENT or ((line.kind == "quest" and cfg.groupByZone) and 4 or 0)
				row:SetPoint("TOPLEFT", f.content, "TOPLEFT", indent, -y)
				row:SetPoint("RIGHT", f.content, "RIGHT", 0, 0)
				row:SetHeight(h)
				row:Show()
				y = y + h
			end
		end
	end
	for i = used + 1, #f.rows do
		f.rows[i]:Hide()
		f.rows[i].data = nil
	end
	local moreQuests = math.max(0, total - shown)
	local moreText = ""
	if hiddenLines > 0 or moreQuests > 0 then
		moreText = moreQuests > 0 and ("+" .. moreQuests .. " more quests") or "more below (raise the height)"
	end
	f.more:SetText(cfg.collapsed and "" or moreText)
	local bottom = (moreText ~= "" and not cfg.collapsed) and (St:LineHeight("NeverQuestFontSmallGray") + 2) or 0
	f.content:SetHeight(math.max(1, y))
	f:SetHeight(PAD + headerH + 4 + y + bottom + PAD)
end

---------------------------------------------------------------------------
-- Blizzard's quest list
---------------------------------------------------------------------------
local lastApply = 0

function T:BlizzardMode()
	local cfg = Cfg()
	if cfg.blizzard == "hide" then return cfg.shown and "hide" or "leave" end
	if cfg.blizzard == "sort" then return "sort" end
	return "leave"
end

-- Blizzard re-watches a quest the moment you accept one or make progress on one, so its
-- tracker flashes into view before we can untrack it again. Untracking after the fact can
-- only ever clean up behind that; stopping the auto-watch is what actually prevents it.
--
-- The player's own values are kept and handed back when we stop hiding, because a CVar change
-- outlives the addon: it would otherwise sit on their character after NeverQuest was gone.
local AUTO_CVARS = { "autoQuestWatch", "autoQuestProgress" }

local function GetCVarValue(name)
	local v = ns.SafeCall(GetCVar, name)
	if v == nil and C_CVar and C_CVar.GetCVar then v = ns.SafeCall(C_CVar.GetCVar, name) end
	return v
end

local function SetCVarValue(name, value)
	if ns.SafeCall(SetCVar, name, value) ~= nil then return true end
	if C_CVar and C_CVar.SetCVar then return ns.SafeCall(C_CVar.SetCVar, name, value) ~= nil end
	return false
end

-- Keeping Blizzard's tracker out of sight.
--
-- Emptying its list and stopping the auto-watch removes the reasons it appears, but neither
-- stops the game showing the frame itself, so anything we miss still flashes up. Parking it
-- on a hidden parent does: a child of a hidden frame never draws, however many times the game
-- calls Show on it.
--
-- Only ever out of combat. That frame holds secure quest item buttons, and reparenting it
-- mid-fight would block them. Anything deferred is picked up again when combat ends.
local parked, parkedTo, parkedShown

local function Holder()
	if not T.parkHolder then
		T.parkHolder = CreateFrame("Frame", nil, UIParent)
		T.parkHolder:Hide()
	end
	return T.parkHolder
end

-- Whichever one this client has. Named outright rather than guessed at, and nil is fine:
-- a client without any of them simply gets the watch-list handling on its own.
local function TrackerFrame()
	local f = ObjectiveTrackerFrame or QuestWatchFrame or WatchFrame
	if type(f) == "table" and f.SetParent and f.GetParent and f.IsShown then return f end
	return nil
end

function T:ParkBlizzardFrame()
	if not Cfg().hideFrame or parked then return end
	if InCombatLockdown and InCombatLockdown() then return end
	local f = TrackerFrame()
	if not f then return end
	local parent = ns.SafeCall(f.GetParent, f)
	if not parent then return end
	parkedShown = ns.SafeCall(f.IsShown, f) and true or false
	parkedTo = parent
	if ns.SafeCall(f.SetParent, f, Holder()) == nil and not pcall(f.SetParent, f, Holder()) then
		parkedTo, parkedShown = nil, nil
		return
	end
	parked = f
	ns.Debug("tracker: Blizzard's tracker parked out of sight")
end

function T:UnparkBlizzardFrame()
	if not parked then return end
	if InCombatLockdown and InCombatLockdown() then return end
	local f = parked
	pcall(f.SetParent, f, parkedTo or UIParent)
	if parkedShown then pcall(f.Show, f) end
	parked, parkedTo, parkedShown = nil, nil, nil
	ns.Debug("tracker: Blizzard's tracker given back")
end

function T:SuppressAutoWatch()
	local backup = ns.char.cvarBackup
	for _, name in ipairs(AUTO_CVARS) do
		local now = GetCVarValue(name)
		if now ~= nil and now ~= "0" then
			if backup[name] == nil then backup[name] = now end
			SetCVarValue(name, "0")
			ns.Debug("tracker: " .. name .. " off while Blizzard's list is hidden (was " .. tostring(now) .. ")")
		end
	end
end

function T:RestoreAutoWatch()
	local backup = ns.char.cvarBackup
	for _, name in ipairs(AUTO_CVARS) do
		if backup[name] ~= nil then
			SetCVarValue(name, backup[name])
			ns.Debug("tracker: " .. name .. " back to " .. tostring(backup[name]))
			backup[name] = nil
		end
	end
end

local function Watched()
	local out = {}
	for i = 1, C_QuestLog.GetNumQuestWatches() do
		local id = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
		if id then table.insert(out, id) end
	end
	return out
end

local function GiveBack()
	local untracked = ns.char.trackerUntracked
	if not next(untracked) then return end
	for id in pairs(untracked) do
		if C_QuestLog.IsOnQuest(id) and C_QuestLog.GetNumQuestWatches() < MAX_WATCH then
			C_QuestLog.AddQuestWatch(id)
		end
	end
	wipe(untracked)
end

function T:ControlBlizzard()
	if not ns.ready or InCombatLockdown() then return end
	local mode = self:BlizzardMode()
	if mode == "hide" then
		self:SuppressAutoWatch()
		-- In an instance that frame is where boss, scenario and challenge objectives are
		-- shown, and NeverQuest has no list of its own for those. It stays in view there.
		local inside = IsInInstance and ns.SafeCall(IsInInstance)
		if inside == true then self:UnparkBlizzardFrame() else self:ParkBlizzardFrame() end
		local watched = Watched()
		for _, id in ipairs(watched) do
			ns.char.trackerUntracked[id] = true
			C_QuestLog.RemoveQuestWatch(id)
		end
		if #watched > 0 then ns.Debug("tracker: untracked " .. #watched .. " quests in Blizzard's list") end
	elseif mode == "sort" then
		self:RestoreAutoWatch()
		self:UnparkBlizzardFrame()
		GiveBack()
		local want = {}
		for _, e in ipairs(self:Entries("priority")) do
			if #want >= MAX_WATCH then break end
			table.insert(want, e.questID)
		end
		local watched = Watched()
		local same = #watched == #want
		if same then
			for i = 1, #want do
				if watched[i] ~= want[i] then same = false break end
			end
		end
		if same then return end
		if GetTime() - lastApply < 15 then
			ns.Debounce("trackersort", 15 - (GetTime() - lastApply) + 0.5, function() T:ControlBlizzard() end)
			return
		end
		lastApply = GetTime()
		for _, id in ipairs(watched) do C_QuestLog.RemoveQuestWatch(id) end
		for _, id in ipairs(want) do C_QuestLog.AddQuestWatch(id) end
		ns.Debug("tracker: Blizzard's list sorted by NeverQuest priority")
	else
		self:RestoreAutoWatch()
		self:UnparkBlizzardFrame()
		GiveBack()
	end
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
local function Redraw() ns.Debounce("tracker", 0.15, function() T:Refresh() end) end
for _, msg in ipairs({ "GUIDE_UPDATED", "PARTY_UPDATED", "STYLE_CHANGED", "CHAINS_UPDATED" }) do
	ns:RegisterMessage(msg, Redraw)
end
ns:RegisterMessage("POSITIONS_RESET", function() if T.frame then T.frame:RestorePosition() end end)
ns:RegisterEvent("ZONE_CHANGED_NEW_AREA", Redraw)
ns:RegisterEvent("PLAYER_LOGIN", Redraw)

local function Control(delay)
	ns.Debounce("trackercontrol", delay or 1, function() T:ControlBlizzard() end)
end
ns:RegisterEvent("QUEST_WATCH_LIST_CHANGED", function() Control(1) end)
-- If a quest is watched despite the above (another addon, or a CVar the client ignores), take
-- it off on the next frame rather than a second later, so any flash is as short as possible.
ns:RegisterEvent("QUEST_ACCEPTED", function() if Cfg().blizzard == "hide" then Control(0.05) end end)
ns:RegisterEvent("QUEST_TURNED_IN", function() if Cfg().blizzard == "hide" then Control(0.05) end end)
ns:RegisterEvent("PLAYER_REGEN_ENABLED", function() Control(1) end)
-- Straight away on the way in (so the list is not there to be seen), and once more when the
-- game has finished filling the quest log, which on a slow login is a few seconds later.
ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
	Control(0.4)
	ns.After(3.5, function() Control(0.1) end)
end)

-- Logging out puts back everything that was changed: your own auto-track settings, and your
-- quests in Blizzard's list. They are taken away again on the way back in. That way an addon
-- that is switched off or removed between sessions leaves nothing behind it.
function T:HandBack()
	if not ns.char then return end
	self:RestoreAutoWatch()
	GiveBack()
end
ns:RegisterEvent("PLAYER_LOGOUT", function() T:HandBack() end)
ns:RegisterMessage("GUIDE_UPDATED", function() if Cfg().blizzard == "sort" then Control(3) end end)

ns:AddSlash("tracker", function(rest)
	local cfg = Cfg()
	rest = (rest or ""):lower()
	if rest == "lock" then
		cfg.locked = not cfg.locked
		ns.Print(cfg.locked and "tracker locked." or "tracker unlocked (drag the header to move).")
	elseif rest == "blizzard" then
		local order = { hide = "sort", sort = "leave", leave = "hide" }
		cfg.blizzard = order[cfg.blizzard] or "hide"
		ns.Print("Blizzard's quest list: " .. ({ hide = "hidden while the NeverQuest tracker shows",
			sort = "kept, sorted by NeverQuest priority", leave = "left alone" })[cfg.blizzard] .. ".")
		T:ControlBlizzard()
	else
		cfg.shown = not cfg.shown
		ns.Print(cfg.shown and "tracker shown." or "tracker hidden.")
		T:ControlBlizzard()
	end
	T:Refresh()
end, "/nq tracker [lock | blizzard] - show or hide the NeverQuest quest tracker, lock it, or change what happens to Blizzard's quest list")
