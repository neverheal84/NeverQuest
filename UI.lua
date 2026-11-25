-- NeverQuest UI: main window (Guide / Quests / Nearby / Guides tabs), import-export box and options panel.

local ADDON, ns = ...
local UI = {}
ns.UI = UI

local WIDTH, ROWS, ROW_H = 430, 11, 34

---------------------------------------------------------------------------
-- Scrolling list widget
---------------------------------------------------------------------------
local function SetIcon(tex, atlas)
	if ns.SetIcon(tex, atlas) then
		tex:Show()
	else
		tex:Hide()
	end
end

function UI.CreateList(parent, numRows, rowHeight, width)
	local list = CreateFrame("Frame", nil, parent)
	list:SetSize(width, numRows * rowHeight)
	list.rows, list.items, list.offset, list.numRows = {}, {}, 0, numRows
	list.baseHeight, list.visibleRows, list.rowH, list.width = numRows * rowHeight, numRows, rowHeight, width

	-- Rows are made as they're needed, so the list can grow with its window.
	local function MakeRow(i)
		local row = CreateFrame("Button", nil, list)
		row:SetSize(list.width, list.rowH)
		row:SetPoint("TOPLEFT", 0, -(i - 1) * list.rowH)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

		row.sel = row:CreateTexture(nil, "BACKGROUND")
		row.sel:SetAllPoints()
		row.sel:SetColorTexture(1, 0.82, 0, 0.13)
		row.sel:Hide()
		local hl = row:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.07)

		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(20, 20)
		row.icon:SetPoint("LEFT", 4, 0)

		row.right = row:CreateFontString(nil, "ARTWORK", "NeverQuestFontSmall")
		row.right:SetPoint("TOPRIGHT", -6, -4)
		row.right:SetJustifyH("RIGHT")

		row.title = row:CreateFontString(nil, "ARTWORK", "NeverQuestFontNormal")
		row.title:SetPoint("TOPLEFT", 30, -3)
		row.title:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
		row.title:SetJustifyH("LEFT")
		row.title:SetWordWrap(false)

		row.sub = row:CreateFontString(nil, "ARTWORK", "NeverQuestFontSmall")
		row.sub:SetPoint("BOTTOMLEFT", 30, 4)
		row.sub:SetPoint("RIGHT", -6, 0)
		row.sub:SetJustifyH("LEFT")
		row.sub:SetWordWrap(false)
		row.sub:SetTextColor(0.75, 0.75, 0.75)

		row:SetScript("OnClick", function(self, button)
			if self.item and list.onClick then list.onClick(self.item, button) end
		end)
		row:SetScript("OnEnter", function(self)
			if not self.item then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(self.item.title or "", 1, 0.82, 0, true)
			if self.item.sub and self.item.sub ~= "" then GameTooltip:AddLine(self.item.sub, 1, 1, 1, true) end
			if self.item.right and self.item.right ~= "" then GameTooltip:AddLine(self.item.right, 0.8, 0.8, 0.8) end
			if list.hint then GameTooltip:AddLine(list.hint, 0.5, 0.8, 1, true) end
			ns.TipShow()
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)
		list.rows[i] = row
		return row
	end
	for i = 1, numRows do MakeRow(i) end

	list.more = list:CreateFontString(nil, "OVERLAY", "NeverQuestFontSmallGray")
	list.more:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", -4, -2)

	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(self, delta)
		local maxOffset = math.max(0, #self.items - self.visibleRows)
		self.offset = math.min(maxOffset, math.max(0, self.offset - delta * 2))
		self:Render()
	end)

	function list:SetItems(items)
		self.items = items or {}
		local maxOffset = math.max(0, #self.items - self.visibleRows)
		if self.offset > maxOffset then self.offset = maxOffset end
		self:Render()
	end

	function list:Render()
		for i, row in ipairs(self.rows) do
			local item = (i <= self.visibleRows) and self.items[i + self.offset] or nil
			row.item = item
			if item then
				SetIcon(row.icon, item.icon or ns.Guide.ICONS[item.kind])
				row.title:SetText(item.title or "")
				local c = item.color
				if c then row.title:SetTextColor(c[1], c[2], c[3]) else row.title:SetTextColor(1, 0.82, 0) end
				row.sub:SetText(item.sub or "")
				row.right:SetText(item.right or "")
				row.sel:SetShown(item.current or (self.selectedKey and item.key == self.selectedKey) or false)
				row:Show()
			else
				row:Hide()
			end
		end
		if #self.items > self.visibleRows then
			self.more:SetFormattedText("%d-%d of %d  (scroll)", self.offset + 1, math.min(#self.items, self.offset + self.visibleRows), #self.items)
		else
			self.more:SetText("")
		end
	end

	-- Taller rows for bigger text; fewer of them fit in the same space.
	function list:Relayout(h)
		h = math.max(rowHeight, math.floor((h or self.rowH) + 0.5))
		self.rowH = h
		self.visibleRows = math.max(1, math.floor(self.baseHeight / h))
		for i = #self.rows + 1, self.visibleRows do MakeRow(i) end
		for i, row in ipairs(self.rows) do
			row:SetSize(self.width, h)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 0, -(i - 1) * h)
		end
		self:SetItems(self.items)
	end

	-- A new size from its window: as many rows as fit.
	function list:Resize(w, h)
		self.width, self.baseHeight = math.floor(w), math.max(rowHeight, math.floor(h))
		self:SetSize(self.width, self.baseHeight)
		self:Relayout(self.rowH)
	end

	return list
end

local function Button(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 90, 22)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

-- Dropdowns. A button with choices opens a menu of them; it never steps through them on click.
local function AddArrow(b)
	if b.nqArrow then return end
	local a = b:CreateTexture(nil, "OVERLAY")
	a:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
	a:SetSize(12, 12)
	a:SetPoint("RIGHT", -6, -2)
	b.nqArrow = a
	local fs = b.GetFontString and b:GetFontString()
	if fs then
		fs:ClearAllPoints()
		fs:SetPoint("LEFT", 8, 0)
		fs:SetPoint("RIGHT", -18, 0)
		fs:SetWordWrap(false)
	end
end
UI.AddArrow = AddArrow

-- A menu of { value, label } choices at the cursor; picking one calls set(value). Without the
-- game's menu system it falls back to the next choice.
function UI.Choose(owner, title, values, get, set)
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(owner, function(_, root)
			if title and title ~= "" then root:CreateTitle(title) end
			for _, v in ipairs(values) do
				root:CreateRadio(v[2], function() return get() == v[1] end, function() set(v[1]) end)
			end
		end)
		return true
	end
	local cur, nextIndex = get(), 1
	for i, v in ipairs(values) do
		if v[1] == cur then nextIndex = (i % #values) + 1 end
	end
	set(values[nextIndex][1])
	return false
end

-- A dropdown button. values: a list, or a function returning one (choices that change).
-- text(value) gives the button's label; by default the chosen value's label.
local function Dropdown(parent, width, title, values, get, set, text)
	local b = Button(parent, "", width, nil)
	AddArrow(b)
	local function Values() return type(values) == "function" and values() or values end
	function b:Update()
		local cur = get()
		if text then self:SetText(text(cur)) return end
		for _, v in ipairs(Values()) do
			if v[1] == cur then self:SetText(v[2]) return end
		end
		self:SetText("")
	end
	b:SetScript("OnClick", function(self)
		UI.Choose(self, title, Values(), get, function(v) set(v) self:Update() end)
	end)
	b:Update()
	return b
end
UI.Dropdown = Dropdown

local function EditBox(parent, width)
	local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	e:SetSize(width, 20)
	e:SetAutoFocus(false)
	e:SetScript("OnEscapePressed", e.ClearFocus)
	e:SetScript("OnEnterPressed", e.ClearFocus)
	return e
end

---------------------------------------------------------------------------
-- Item builders for each tab
---------------------------------------------------------------------------
local function QuestItems()
	local log = {}
	for _, e in ipairs(ns.Quests.log) do table.insert(log, e) end
	local function Score(e)
		return ((e.xp and e.xp > 0) and e.xp or 150) / ((e.dist or 2500) + 250) * (e.trivial and 0.15 or 1)
	end
	table.sort(log, function(a, b)
		if a.complete ~= b.complete then return a.complete end
		if a.complete then return (a.dist or 1e9) < (b.dist or 1e9) end
		return Score(a) > Score(b)
	end)
	local items = {}
	for _, e in ipairs(log) do
		local parts = {}
		if e.complete then
			table.insert(parts, "|cff66ff66Ready to turn in|r")
		elseif e.failed then
			table.insert(parts, "|cffff4444Failed|r")
		else
			table.insert(parts, string.format("%d%%", math.floor((e.progress or 0) * 100 + 0.5)))
			if e.objective then table.insert(parts, e.objective) end
		end
		if e.xp and e.xp > 0 then table.insert(parts, "+" .. ns.Comma(e.xp) .. " XP") end
		if e.trivial then table.insert(parts, "|cff999999gray|r") end
		if e.elite then table.insert(parts, "|cffff8040elite|r") end
		if e.leg and e.leg.text then table.insert(parts, "|cff99ccffvia: " .. e.leg.text .. "|r") end
		local party = ns.Party and ns.Party:Summary(e.questID)
		if party then table.insert(parts, "|cff66ccffparty: " .. party .. "|r") end
		local item = {
			key = "quest:" .. e.questID, questID = e.questID,
			icon = e.complete and "QuestTurnin" or ns.ObjectiveIcon(e),
			title = (e.level and ("[" .. e.level .. (e.elite and "+" or "") .. "] ") or "") .. e.title,
			color = { ns.QuestColor(e.questID) },
			sub = table.concat(parts, "  ·  "),
			right = e.dist and ns.Yards(e.dist) or (e.zone or ""),
		}
		if e.pos then
			item.m, item.x, item.y = e.pos.m, e.pos.x, e.pos.y
			item.navTitle = (e.complete and "Turn in: " or "") .. e.title
		end
		table.insert(items, item)
	end
	return items
end

local function OfferItems()
	local offers = {}
	for _, o in ipairs(ns.Quests.offers) do
		if ns.Quests:OfferShown(o, true) then table.insert(offers, o) end
	end
	table.sort(offers, function(a, b) return (a.dist or 1e9) < (b.dist or 1e9) end)
	local items = {}
	for _, o in ipairs(offers) do
		local parts = {}
		if o.xp then table.insert(parts, "+" .. ns.Comma(o.xp) .. " XP") end
		if o.trivial then table.insert(parts, "|cff999999gray: low XP|r") end
		if o.difficulty == 4 then table.insert(parts, "|cffff4040too high for now|r") end
		local chain = ns.Chains and ns.db.guide.chains and ns.Chains:Label(o.questID)
		if chain then table.insert(parts, "|cffc8a2ff" .. chain .. "|r") end
		if o.daily then table.insert(parts, "daily") end
		if o.important then table.insert(parts, "story") end
		table.insert(parts, string.format("%.1f, %.1f", o.x * 100, o.y * 100))
		table.insert(items, {
			key = "pickup:" .. o.questID, questID = o.questID, icon = "QuestNormal",
			title = (o.level and ("[" .. o.level .. "] ") or "") .. o.title,
			color = { ns.QuestColor(o.questID) },
			sub = table.concat(parts, "  ·  "),
			right = ns.Yards(o.dist),
			m = o.m, x = o.x, y = o.y, navTitle = "Pick up: " .. o.title,
		})
	end
	return items
end

local function GuideItems()
	local items = {}
	for _, s in ipairs(ns.Guide.steps) do table.insert(items, s) end
	return items
end

---------------------------------------------------------------------------
-- Main window
---------------------------------------------------------------------------
local TABS = { { "guide", "Guide" }, { "quests", "Quests" }, { "nearby", "Nearby" }, { "raids", "Raids" }, { "class", "Class" }, { "journal", "Journal" }, { "guides", "Guides" } }

function UI:Create()
	local f = CreateFrame("Frame", "NeverQuestFrame", UIParent, "BackdropTemplate")
	local win = ns.db.window
	f:SetSize(win.w or WIDTH, win.h or (92 + ROWS * ROW_H + 46))
	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	ns.ApplyBackdrop(f, 0.95)
	ns.MakeMovable(f, "window", nil, { "CENTER", UIParent, "CENTER", 320, 40 })
	f:Hide()
	table.insert(UISpecialFrames, "NeverQuestFrame")
	self.frame = f

	local logo = f:CreateTexture(nil, "ARTWORK")
	logo:SetTexture(ns.LOGO)
	logo:SetSize(24, 24)
	logo:SetPoint("TOPLEFT", 10, -7)
	self.logo = logo
	local title = f:CreateFontString(nil, "OVERLAY", "NeverQuestFontTitle")
	title:SetPoint("LEFT", logo, "RIGHT", 6, 0)
	title:SetText("NeverQuest")
	local ver = f:CreateFontString(nil, "OVERLAY", "NeverQuestFontSmallGray")
	ver:SetPoint("LEFT", title, "RIGHT", 6, -1)
	ver:SetText("v" .. ns.version .. "  ·  by " .. ns.AUTHOR)

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)
	local opts = Button(f, "Options", 70, function() UI:OpenOptions() end)
	opts:SetPoint("TOPRIGHT", -32, -8)
	local help = Button(f, "Help", 50, function() if ns.Help then ns.Help:Open() end end)
	help:SetPoint("RIGHT", opts, "LEFT", -4, 0)
	self.btnHelp = help
	local disc = Button(f, "Discord", 62, function() UI:ShowDiscord() end)
	disc:SetPoint("RIGHT", help, "LEFT", -4, 0)
	self.btnDiscord = disc

	self.tabs = {}
	for i, t in ipairs(TABS) do
		local b = Button(f, t[2], 57, function() UI:SetTab(t[1]) end)
		b:SetPoint("TOPLEFT", 10 + (i - 1) * 59, -36)
		self.tabs[t[1]] = b
	end
	self:LayoutTabs()

	self.header = f:CreateFontString(nil, "OVERLAY", "NeverQuestFontSmall")
	self.header:SetPoint("TOPLEFT", 14, -66)
	self.header:SetPoint("RIGHT", -14, 0)
	self.header:SetJustifyH("LEFT")
	self.header:SetWordWrap(false)

	self.list = UI.CreateList(f, ROWS, ROW_H, WIDTH - 20)
	self.list:SetPoint("TOPLEFT", 10, -84)
	self.list.onClick = function(item, button) UI:OnItemClick(item, button) end

	self.footer = f:CreateFontString(nil, "OVERLAY", "NeverQuestFontSmall")
	self.footer:SetPoint("BOTTOMLEFT", 14, 16)
	self.footer:SetJustifyH("LEFT")

	-- Footer buttons (shown per tab).
	self.btnBack = Button(f, "< Back", 70, function() ns.Guide:StepBack() end)
	self.btnSkip = Button(f, "Skip >", 70, function() ns.Guide:StepSkip() end)
	self.btnLive = Button(f, "Live guide", 90, function() ns.Guide:UseLive() end)
	self.btnFaction = Dropdown(f, 130, "Attunement chain for", { { "Alliance", "Alliance" }, { "Horde", "Horde" } },
		function() return UI.attuneFaction or UnitFactionGroup("player") end,
		function(v) UI.attuneFaction = v UI.list.offset = 0 UI:Refresh() end,
		function(v) return "Faction: " .. (v or "?") end)
	self.btnFaction:SetPoint("BOTTOMRIGHT", -10, 10)
	self.btnFaction:Hide()

	local GRAY = { { false, "Hide gray quests" }, { true, "Show gray quests" } }
	local function GrayText(v) return v and "Gray: shown" or "Gray: hidden" end
	self.btnGray = Dropdown(f, 110, "Gray (low level) quests", GRAY, function() return ns.db.guide.showGray and true or false end,
		function(v) ns.db.guide.showGray = v ns.Guide:Refresh() UI:Refresh() end, GrayText)
	self.btnSplits = Button(f, "Splits", 70, function() ns.db.window.journalView = "splits" UI:Refresh() end)
	self.btnHistory = Button(f, "History", 70, function() ns.db.window.journalView = "history" UI:Refresh() end)
	self.btnSplits:SetPoint("BOTTOMRIGHT", -10, 10)
	self.btnHistory:SetPoint("RIGHT", self.btnSplits, "LEFT", -4, 0)
	self.btnProfs = Button(f, "Professions", 90, function() ns.db.window.classView = "professions" UI.list.offset = 0 UI:Refresh() end)
	self.btnClassQ = Button(f, "Class quests", 90, function() ns.db.window.classView = "class" UI.list.offset = 0 UI:Refresh() end)
	self.btnProfs:SetPoint("BOTTOMRIGHT", -10, 10)
	self.btnClassQ:SetPoint("RIGHT", self.btnProfs, "LEFT", -4, 0)
	self.btnProfs:Hide()
	self.btnClassQ:Hide()
	-- Quests tab: your log, or the quests you skipped, dropped or left behind (Advisor.lua).
	local function MissedN() return ns.Advisor and ns.Advisor:MissedCount() or 0 end
	self.btnMissed = Dropdown(f, 130, "Show",
		function()
			local n = MissedN()
			return { { "log", "Your quest log" }, { "missed", n > 0 and ("Missed list (" .. n .. ")") or "Missed list" } }
		end,
		function() return ns.db.window.questsView == "missed" and "missed" or "log" end,
		function(v) ns.db.window.questsView = v UI.list.offset = 0 UI:Refresh() end,
		function(v)
			if v == "missed" then return "Missed list" end
			local n = MissedN()
			return n > 0 and ("Quest log (" .. n .. " missed)") or "Quest log"
		end)
	self.btnMissed:SetPoint("BOTTOMRIGHT", -10, 10)
	self.btnMissed:Hide()
	self.btnMissedGray = Dropdown(f, 110, "Gray (low level) quests", GRAY, function() return UI.missedGray and true or false end,
		function(v) UI.missedGray = v UI:Refresh() end, GrayText)
	self.btnMissedGray:SetPoint("RIGHT", self.btnMissed, "LEFT", -4, 0)
	self.btnMissedGray:Hide()
	self.btnLive:SetPoint("BOTTOMRIGHT", -10, 10)
	self.btnSkip:SetPoint("RIGHT", self.btnLive, "LEFT", -4, 0)
	self.btnBack:SetPoint("RIGHT", self.btnSkip, "LEFT", -4, 0)
	self.btnGray:SetPoint("BOTTOMRIGHT", -10, 10)

	-- 1-60 plan view (Guide tab) and its race/class browser.
	self.btnPlan = Button(f, "1-60 plan", 90, function() UI:TogglePlan() end)
	self.btnPlan:SetPoint("BOTTOMLEFT", 10, 10)
	local P = ns.Profiles
	self.btnRace = Dropdown(f, 140, "Race",
		function()
			local out = {}
			for i, r in ipairs(P.RACE_LIST) do out[#out + 1] = { i, P.RaceName(r.token, r.faction) .. "  |cff999999" .. r.faction .. "|r" } end
			return out
		end,
		function() return (UI:PlanSelection()) end,
		function(i) UI:SelectPlanRace(i) end,
		function(i) local r = P.RACE_LIST[i] return r and P.RaceName(r.token, r.faction) or "?" end)
	self.btnClass = Dropdown(f, 100, "Class",
		function()
			local idx = UI:PlanSelection()
			local r, out = P.RACE_LIST[idx], {}
			for _, c in ipairs(P.CLASS_ORDER) do
				if r and P.IsPlayable(r.token, r.faction, c) then out[#out + 1] = { c, P.CLASS_NAMES[c] or c } end
			end
			return out
		end,
		function() return select(2, UI:PlanSelection()) end,
		function(c) UI:SelectPlanClass(c) end,
		function(c) return P.CLASS_NAMES[c] or "?" end)
	self.btnMine = Button(f, "Mine", 52, function() UI.planSel = nil UI.planScrollPending = true UI:Refresh() end)
	-- Leveling style switch, top right of the plan view.
	self.btnStyle = Dropdown(f, 150, "Leveling style", P.STYLES, function() return P:Style() end, function(v) UI:SetStyle(v) end)
	self.btnStyle:SetPoint("TOPRIGHT", -10, -58)
	self.btnStyle:SetScript("OnEnter", function(btn)
		GameTooltip:SetOwner(btn, "ANCHOR_TOP")
		GameTooltip:AddLine("Leveling style")
		GameTooltip:AddLine("Optimized 1-60: the zone with the most XP per hour, with your plan as the fallback.", 1, 1, 1, true)
		GameTooltip:AddLine("Zone by zone: every quest in a zone, then the next one in your plan.", 1, 1, 1, true)
		ns.TipShow(false)
	end)
	self.btnStyle:SetScript("OnLeave", GameTooltip_Hide)
	self.btnRace:SetPoint("LEFT", self.btnPlan, "RIGHT", 4, 0)
	self.btnClass:SetPoint("LEFT", self.btnRace, "RIGHT", 4, 0)
	self.btnMine:SetPoint("LEFT", self.btnClass, "RIGHT", 4, 0)

	self:CreateGuidesPanel()
	-- Drag the bottom right corner to resize; the list shows as many rows as fit.
	ns.MakeResizable(f, { minW = WIDTH, minH = 92 + 6 * ROW_H + 46, maxW = 900, maxH = 1200,
		corner = function() return "BOTTOMRIGHT" end,
		onSize = function(w, h) UI:Layout(w, h) end,
		onDone = function(w, h) ns.db.window.w, ns.db.window.h = w, h UI:Refresh() end })
	self:Layout()
	f:SetScript("OnShow", function() UI:Refresh() end)
	self:SetTab(ns.db.window.tab or "guide")
end

-- The Class tab holds class quests and profession quests, each of which can be switched off.
-- With both off the tab goes, and the ones after it close the gap.
function UI:ClassTabShown()
	return ns.db.guide.classTab or ns.db.guide.profQuests
end

function UI:LayoutTabs()
	if not self.tabs then return end
	local n = 0
	for _, t in ipairs(TABS) do
		local b = self.tabs[t[1]]
		if b then
			if t[1] == "class" and not self:ClassTabShown() then
				b:Hide()
			else
				if t[1] == "class" then b:SetText(ns.db.guide.classTab and "Class" or "Trades") end
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", 10 + n * 59, -36)
				b:Show()
				n = n + 1
			end
		end
	end
	if self.tab == "class" and not self:ClassTabShown() then self:SetTab("guide") end
end

function UI:SetTab(tab)
	if tab == "class" and not self:ClassTabShown() then tab = "guide" end
	self.tab = tab
	ns.db.window.tab = tab
	for key, b in pairs(self.tabs) do
		if key == tab then b:LockHighlight() else b:UnlockHighlight() end
	end
	self.list.offset = 0
	self:Refresh()
end

function UI:TogglePlan(on)
	if on == nil then on = not self.planView end
	self.planView = on
	self.planScrollPending = on
	self.list.offset = 0
	self:Refresh()
end

-- Which race entry and class the plan view is showing (nil = your own character).
function UI:PlanSelection()
	local P = ns.Profiles
	if self.planSel then return self.planSel.race, self.planSel.class end
	local _, token = UnitRace("player")
	local _, class = UnitClass("player")
	local faction = UnitFactionGroup("player")
	for i, r in ipairs(P.RACE_LIST) do
		if r.token == token and r.faction == faction then return i, class end
	end
	return 1, class
end

function UI:CyclePlanRace(dir)
	local P = ns.Profiles
	local idx, class = self:PlanSelection()
	idx = (idx - 1 + dir) % #P.RACE_LIST + 1
	local r = P.RACE_LIST[idx]
	if not P.IsPlayable(r.token, r.faction, class) then
		for _, c in ipairs(P.CLASS_ORDER) do
			if P.IsPlayable(r.token, r.faction, c) then class = c break end
		end
	end
	self.planSel = { race = idx, class = class }
	self.planScrollPending = true
	self:Refresh()
end

-- The plan view's Race and Class dropdowns.
function UI:SelectPlanRace(idx)
	local P = ns.Profiles
	local r = P.RACE_LIST[idx]
	if not r then return end
	local _, class = self:PlanSelection()
	if not P.IsPlayable(r.token, r.faction, class) then
		for _, c in ipairs(P.CLASS_ORDER) do
			if P.IsPlayable(r.token, r.faction, c) then class = c break end
		end
	end
	self.planSel = { race = idx, class = class }
	self.planScrollPending = true
	self:Refresh()
end

function UI:SelectPlanClass(class)
	local idx = self:PlanSelection()
	self.planSel = { race = idx, class = class }
	self.planScrollPending = true
	self:Refresh()
end

function UI:CyclePlanClass(dir)
	local P = ns.Profiles
	local idx, class = self:PlanSelection()
	local r = P.RACE_LIST[idx]
	local options = {}
	for _, c in ipairs(P.CLASS_ORDER) do
		if P.IsPlayable(r.token, r.faction, c) then table.insert(options, c) end
	end
	if #options == 0 then return end
	local pos = 1
	for i, c in ipairs(options) do if c == class then pos = i end end
	pos = (pos - 1 + dir) % #options + 1
	self.planSel = { race = idx, class = options[pos] }
	self.planScrollPending = true
	self:Refresh()
end

-- Right-click on a quest anywhere in the window: open it, skip it, drop it, go back for it.
function UI:QuestMenu(item)
	local qid = item.questID or item.missedQuest
	if not (qid and MenuUtil and MenuUtil.CreateContextMenu) then return false end
	MenuUtil.CreateContextMenu(self.frame, function(_, root)
		root:CreateTitle(ns.Advisor and ns.Advisor.Title(qid) or (item.title or "Quest"))
		local inLog = ns.SafeCall(C_QuestLog.IsOnQuest, qid) == true
		if inLog and QuestMapFrame_OpenToQuestDetails then
			root:CreateButton("Open in quest log", function() QuestMapFrame_OpenToQuestDetails(qid) end)
		end
		if inLog then
			local share = root:CreateButton("Share with party", function() if ns.Catchup then ns.Catchup:Share(qid) end end)
			if not (IsInGroup() and ns.SafeCall(C_QuestLog.IsPushableQuest, qid) == true) and share and share.SetEnabled then
				share:SetEnabled(false)
			end
		end
		if item.m and item.x then
			root:CreateButton("Point the arrow here", function() ns.Guide:Pin(item) end)
		end
		if item.missedQuest and ns.Advisor then
			root:CreateButton("Take it off the missed list", function() ns.Advisor:Hide(qid) end)
		end
		if ns.Advisor then ns.Advisor:MenuItems(root, qid) end
	end)
	return true
end

function UI:OnItemClick(item, button)
	if item.openMissed and button ~= "RightButton" then
		ns.db.window.questsView = "missed"
		self:SetTab("quests")
		return
	end
	if item.missedQuest and button == "RightButton" then
		self:QuestMenu(item)
		return
	end
	if item.shareQuest and button ~= "RightButton" then
		ns.Catchup:Share(item.shareQuest)
		return
	end
	if item.openPlan and button ~= "RightButton" then
		self:TogglePlan(true)
		return
	end
	if item.openDungeons and button ~= "RightButton" then
		if ns.Dungeons then ns.Dungeons:OpenPicker() end
		return
	end
	if item.followAttune and button ~= "RightButton" then
		local att = ns.Attune:ByKey(item.followAttune)
		if att then ns.Attune:Follow(att, true) end
		return
	end
	if item.attune then
		local A = ns.Attune
		if not item.attuneStep then
			if button == "RightButton" then
				MenuUtil.CreateContextMenu(self.frame, function(_, root)
					root:CreateTitle(item.attune.raid .. " (" .. item.attune.faction .. ")")
					root:CreateButton("Clear my ticks and turn-ins", function() A:Reset(item.attune) end)
				end)
			elseif item.attune.faction == UnitFactionGroup("player") then
				A:Follow(item.attune)
			end
			return
		end
		if button == "RightButton" then
			if item.attune.faction == UnitFactionGroup("player") then A:Toggle(item.attune, item.attuneStep) end
			return
		end
	end
	if item.classLog then
		if ns.Tracker then ns.Tracker:Point(item.classLog) end
		return
	end
	if item.classKey then
		ns.ClassQuests:Toggle(item.classKey)
		self:Refresh()
		return
	end
	if item.profKey then
		ns.ClassQuests:ToggleProf(item.profKey)
		self:Refresh()
		return
	end
	if item.milestoneKey and button ~= "RightButton" then
		local done = ns.char.milestones
		done[item.milestoneKey] = (not done[item.milestoneKey]) or nil
		ns.Guide:Refresh()
		self:Refresh()
		return
	end
	if item.reminder then
		if button == "RightButton" then
			ns.Upkeep:Hide(item.key)
			return
		end
		if item.openQuest and QuestMapFrame_OpenToQuestDetails then
			QuestMapFrame_OpenToQuestDetails(item.openQuest)
			return
		end
	end
	if button == "RightButton" then
		-- A quest: a menu with Skip and Drop, falling back to the quest log where menus aren't there.
		if item.questID and ns.Advisor and self:QuestMenu(item) then return end
		if item.questID and C_QuestLog.IsOnQuest(item.questID) and QuestMapFrame_OpenToQuestDetails then
			QuestMapFrame_OpenToQuestDetails(item.questID)
		end
		return
	end
	if IsControlKeyDown() and item.questID and ns.Upkeep and ns.Quests.byID[item.questID] then
		ns.Upkeep:AskForGroup(ns.Quests.byID[item.questID])
		return
	end
	if IsShiftKeyDown() and item.questID and GetQuestLink then
		local link = GetQuestLink(item.questID)
		if link then
			if ChatFrameUtil and ChatFrameUtil.InsertLink then
				ChatFrameUtil.InsertLink(link)
			elseif ChatEdit_InsertLink then
				ChatEdit_InsertLink(link)
			end
		end
		return
	end
	if item.m and item.x then
		ns.Guide:Pin(item)
		self.list.selectedKey = item.key
		self.list:Render()
	end
end

function UI:Refresh()
	local f = self.frame
	if not f or not f:IsShown() then return end
	local tab = self.tab
	local G = ns.Guide
	local guidesTab = tab == "guides"
	self.list:SetShown(not guidesTab)
	self.guidesPanel:SetShown(guidesTab)
	self.btnBack:Hide()
	self.btnSkip:Hide()
	self.btnLive:Hide()
	self.btnGray:Hide()
	self.btnFaction:Hide()
	self.btnSplits:Hide()
	self.btnHistory:Hide()
	self.btnProfs:Hide()
	self.btnClassQ:Hide()
	self.btnMissed:Hide()
	self.btnMissedGray:Hide()
	self.btnPlan:Hide()
	self.btnRace:Hide()
	self.btnClass:Hide()
	self.btnMine:Hide()
	self.btnStyle:Hide()
	self.header:SetPoint("RIGHT", -14, 0)
	self.list.hint = "Click: point the arrow here.  Right-click a quest: skip it, drop it, or open it in your quest log.  Shift-click: link in chat."

	if tab == "guide" and self.planView then
		local P = ns.Profiles
		self.btnPlan:Show()
		self.btnPlan:SetText("Next steps")
		self.btnRace:Show()
		self.btnClass:Show()
		self.btnStyle:Show()
		self.btnStyle:Update()
		self.header:SetPoint("RIGHT", -166, 0)
		local plan, mine
		if self.planSel then
			local r = P.RACE_LIST[self.planSel.race]
			plan = P:Build(r.token, self.planSel.class, r.faction)
			self.btnMine:Show()
		else
			plan, mine = P:Mine(), true
		end
		self.btnRace:SetText(P.RaceName(plan.token, plan.faction))
		self.btnClass:SetText(P.CLASS_NAMES[plan.class] or "?")
		self.header:SetFormattedText("%s: |cffffffff%s|r%s", P:StyleName(), plan.title,
			mine and ("  ·  level " .. UnitLevel("player")) or "  ·  browsing")
		self.footer:SetText("")
		self.list.hint = "Zone rows: click to point the arrow there. Milestones: click when done."
		local items = P:PlanItems(plan, mine and UnitLevel("player") or 0)
		if self.planScrollPending then
			self.planScrollPending = false
			for i, it in ipairs(items) do
				if it.current then self.list.offset = math.max(0, i - 2) break end
			end
		end
		self.list:SetItems(items)
	elseif tab == "guide" then
		self.btnPlan:Show()
		self.btnPlan:SetText("1-60 plan")
		local guide = G:GetScript()
		if guide then
			self.header:SetFormattedText("Guide: |cffffffff%s|r   step %d of %d", guide.name, math.min(ns.char.script.step, #guide.steps), #guide.steps)
			self.btnBack:Show()
			self.btnSkip:Show()
			self.btnLive:Show()
			self.footer:SetText("")
		else
			local zone = G:CurrentZoneLevels()
			-- Skip the step the arrow is on: a quest goes on the missed list.
			self.btnSkip:Show()
			self.header:SetText((G:IsRecording() and ("|cffff5555Recording (" .. #ns.char.recorder.steps .. ")|r  ") or "") ..
				"Live guide: best next steps" ..
				(zone and string.format("  (|cffffffff%s %d-%d|r)", zone.name, zone.min, zone.max) or ""))
			self.footer:SetText("")
		end
		self.list:SetItems(GuideItems())
	elseif tab == "quests" and ns.db.window.questsView == "missed" and ns.Advisor then
		local AD = ns.Advisor
		self.btnMissed:Show()
		self.btnMissed:Update()
		self.btnMissedGray:Show()
		self.btnMissedGray:Update()
		self.header:SetText("Quests you skipped, dropped or left behind in zones you've moved on from.")
		self.list.hint = "Click: point the arrow at the quest giver.  Right-click: go back for it, take it back, or take it off the list."
		local items = AD:Items(self.missedGray or AD:Completionist())
		local n = (items[1] and items[1].missedQuest) and #items or 0
		self.footer:SetText(n .. (n == 1 and " quest" or " quests") .. "  ·  /nq missed lists them in chat")
		self.list:SetItems(items)
	elseif tab == "quests" then
		self.btnMissed:Show()
		self.btnMissed:Update()
		self.list.hint = "Click: point the arrow here.  Right-click: skip, drop or open in quest log.  Shift-click: link in chat."
		local n, ready, readyXP, totalXP = 0, 0, 0, 0
		for _, e in ipairs(ns.Quests.log) do
			n = n + 1
			totalXP = totalXP + (e.xp or 0)
			if e.complete then ready, readyXP = ready + 1, readyXP + (e.xp or 0) end
		end
		self.header:SetText("Quest log ranked by XP per distance. Ready-to-turn-in quests first.")
		self.footer:SetFormattedText("%d quests  ·  %d ready (+%s XP)  ·  %s XP in log", n, ready, ns.Comma(readyXP), ns.Comma(totalXP))
		self.list:SetItems(QuestItems())
	elseif tab == "nearby" then
		local m = ns.Quests.offerMap
		self.header:SetText("Quests you can pick up in " .. (m and ns.Nav.MapName(m) or "this zone") .. ", nearest first.")
		self.btnGray:Show()
		self.btnGray:Update()
		local items = OfferItems()
		self.footer:SetText(#items .. " available")
		self.list:SetItems(items)
	elseif tab == "raids" then
		local A = ns.Attune
		local mine = UnitFactionGroup("player")
		local faction = self.attuneFaction or mine
		self.btnFaction:Show()
		self.btnFaction:Update()
		self.header:SetText("Raid attunements for " .. faction .. (faction ~= mine and " (browsing)" or "") .. ". Steps tick off as you go.")
		self.list.hint = "Raid row: click to follow it in the guide.  Step: click to point the arrow there; right-click to mark done or not done."
		local items = A:Items(faction)
		local following = A:Following()
		self.footer:SetText(following and ("Following: " .. following.raid) or "Not following an attunement")
		if self.attunePending ~= faction then
			self.attunePending = faction
			for i, it in ipairs(items) do
				if it.current then self.list.offset = math.max(0, i - 3) break end
			end
		end
		self.list:SetItems(items)
	elseif tab == "class" then
		local CQ = ns.ClassQuests
		local g = ns.db.guide
		local view = ns.db.window.classView
		if view == "professions" and not g.profQuests then view = "class" end
		if view ~= "professions" and not g.classTab then view = "professions" end
		if g.classTab and g.profQuests then
			self.btnProfs:Show()
			self.btnClassQ:Show()
			if view == "professions" then self.btnProfs:LockHighlight() self.btnClassQ:UnlockHighlight()
			else self.btnClassQ:LockHighlight() self.btnProfs:UnlockHighlight() end
		end
		self.list.hint = "Click a quest in your log to point the arrow at it.  Click a checklist row to tick it off or on."
		if view == "professions" then
			self.header:SetText("The quests your professions wait on, and the skill each one needs.")
			self.footer:SetText("")
			self.list:SetItems(CQ:ProfItems())
		else
			local due = #CQ:Due()
			self.header:SetText("The quests only your class gets: what's in your log, and what's coming at which level.")
			self.footer:SetText(due > 0 and (due .. (due == 1 and " class quest" or " class quests") .. " open at your level") or "Nothing waiting at your level")
			self.list:SetItems(CQ:Items())
		end
	elseif tab == "journal" then
		local splits = ns.db.window.journalView == "splits"
		self.btnSplits:Show()
		self.btnHistory:Show()
		if splits then self.btnSplits:LockHighlight() self.btnHistory:UnlockHighlight()
		else self.btnHistory:LockHighlight() self.btnSplits:UnlockHighlight() end
		self.list.hint = nil
		if splits then
			self.header:SetText("Time on each level, compared with your fastest character.")
			self.footer:SetText("")
			self.list:SetItems(ns.Journal:SplitItems())
		else
			self.header:SetText("Quests turned in on this character, newest first.")
			self.footer:SetText(#ns.char.journal .. " turned in")
			self.list:SetItems(ns.Journal:HistoryItems())
		end
	else
		self.header:SetText("Record your route, then replay it on alts. Share guides with Export / Import.")
		self.footer:SetText("")
		self:RefreshGuidesPanel()
	end
end

function UI:Toggle()
	if not self.frame then return end
	self.frame:SetShown(not self.frame:IsShown())
end

-- Switches the leveling style everywhere: guide, route, plan view and tracker.
function UI:SetStyle(style)
	ns.db.guide.style = (style == "zone") and "zone" or "optimized"
	ns.Guide.focusKey = nil
	ns.Planner.dirty = true
	self.planScrollPending = true
	ns.Guide:Refresh()
	self:Refresh()
	ns.Print("leveling style: " .. ns.Profiles:StyleName() .. ".")
end

-- Fits the list (and the Guides tab) to the window's size.
function UI:Layout(w, h)
	local f = self.frame
	if not (f and self.list) then return end
	w, h = w or f:GetWidth(), h or f:GetHeight()
	if not (w and h) then return end
	local listH = h - 92 - 46
	self.list:Resize(w - 20, listH)
	local p = self.guidesPanel
	if p then
		p:SetSize(w - 20, listH + 30)
		if p.list then p.list:Resize(w - 20, p.list.baseHeight) end
	end
end

-- Back to the standard size.
function UI:ResetSize()
	ns.db.window.w, ns.db.window.h = nil, nil
	if self.frame then
		self.frame:SetSize(WIDTH, 92 + ROWS * ROW_H + 46)
		self:Layout()
		self:Refresh()
	end
end

function UI:ApplyScale()
	if self.frame then self.frame:SetScale(ns.db.window.scale or 1) end
end

-- Text size changed: rows grow to fit both lines.
function UI:ApplyStyle()
	if not self.list then return end
	local St = ns.Style
	self.list:Relayout(St:LineHeight("NeverQuestFontNormal") + St:LineHeight("NeverQuestFontSmall") + 6)
end

---------------------------------------------------------------------------
-- Guides tab: recorder and saved guides
---------------------------------------------------------------------------
function UI:CreateGuidesPanel()
	local p = CreateFrame("Frame", nil, self.frame)
	p:SetPoint("TOPLEFT", 10, -84)
	p:SetSize(WIDTH - 20, ROWS * ROW_H + 30)
	p:Hide()
	self.guidesPanel = p

	local recTitle = p:CreateFontString(nil, "OVERLAY", "NeverQuestFontNormal")
	recTitle:SetPoint("TOPLEFT", 4, -2)
	recTitle:SetText("Route recorder")

	p.status = p:CreateFontString(nil, "OVERLAY", "NeverQuestFontSmall")
	p.status:SetPoint("TOPLEFT", 4, -20)
	p.status:SetPoint("RIGHT", -4, 0)
	p.status:SetJustifyH("LEFT")

	p.name = EditBox(p, 230)
	p.name:SetPoint("TOPLEFT", 10, -40)
	p.recBtn = Button(p, "Start recording", 150, function()
		if ns.Guide:IsRecording() then ns.Guide:StopRecording() else ns.Guide:StartRecording(p.name:GetText()) end
		p.name:ClearFocus()
	end)
	p.recBtn:SetPoint("LEFT", p.name, "RIGHT", 10, 0)

	p.note = EditBox(p, 230)
	p.note:SetPoint("TOPLEFT", 10, -66)
	p.noteBtn = Button(p, "Add note here", 150, function()
		local text = p.note:GetText()
		if text ~= "" and ns.Guide:IsRecording() then
			ns.Guide:Record("note", { note = text })
			p.note:SetText("")
			ns.Print("note added.")
		end
		p.note:ClearFocus()
	end)
	p.noteBtn:SetPoint("LEFT", p.note, "RIGHT", 10, 0)

	local listTitle = p:CreateFontString(nil, "OVERLAY", "NeverQuestFontNormal")
	listTitle:SetPoint("TOPLEFT", 4, -96)
	listTitle:SetText("Saved guides")

	p.list = UI.CreateList(p, 7, ROW_H, WIDTH - 20)
	p.list:SetPoint("TOPLEFT", 0, -114)
	p.list.hint = "Click to select, then Load, Export or Delete."
	p.list.onClick = function(item)
		p.list.selectedKey = item.key
		p.list:Render()
	end

	local function Selected()
		return p.list.selectedKey and ns.Guide:FindGuide(p.list.selectedKey), p.list.selectedKey
	end
	local load = Button(p, "Load", 70, function()
		local g, name = Selected()
		if g then ns.Guide:LoadScript(name) UI:SetTab("guide") end
	end)
	local export = Button(p, "Export", 70, function()
		local g = Selected()
		if g then UI:ShowIO("export", ns.Guide:Serialize(g)) end
	end)
	local delete = Button(p, "Delete", 70, function()
		local g, name = Selected()
		if g and ns.db.guides[name] then
			ns.Guide:Delete(name)
			p.list.selectedKey = nil
		elseif g then
			ns.Print("bundled guides can't be deleted.")
		end
	end)
	local import = Button(p, "Import...", 80, function() UI:ShowIO("import", "") end)
	local live = Button(p, "Live guide", 90, function() ns.Guide:UseLive() UI:SetTab("guide") end)
	load:SetPoint("TOPLEFT", p.list, "BOTTOMLEFT", 2, -16)
	export:SetPoint("LEFT", load, "RIGHT", 4, 0)
	delete:SetPoint("LEFT", export, "RIGHT", 4, 0)
	import:SetPoint("LEFT", delete, "RIGHT", 4, 0)
	live:SetPoint("LEFT", import, "RIGHT", 4, 0)
end

function UI:RefreshGuidesPanel()
	local p = self.guidesPanel
	local rec = ns.char.recorder
	if rec.active then
		p.status:SetFormattedText("|cffff5555Recording|r |cffffffff%s|r: %d steps so far.", rec.name or "?", #rec.steps)
		p.recBtn:SetText("Stop and save")
		p.name:SetText(rec.name or "")
		p.name:Disable()
		p.noteBtn:Enable()
	else
		p.status:SetText("Records pickups, turn-ins, completions, flights, hearths and level-ups with coordinates.")
		p.recBtn:SetText("Start recording")
		p.name:Enable()
		if p.name:GetText() == "" then
			p.name:SetText(string.format("%s %s from %d", UnitRace("player") or "", UnitClass("player") or "", UnitLevel("player")))
		end
		p.noteBtn:Disable()
	end

	local items = {}
	for _, entry in ipairs(ns.Guide:AllGuides()) do
		local g = entry.guide
		local meta = {}
		if g.race or g.class then
			local who = ((g.race or "") .. " " .. (g.class or "")):gsub("^%s+", "")
			table.insert(meta, who)
		end
		if g.minLevel and g.maxLevel and g.maxLevel > 0 then table.insert(meta, "levels " .. g.minLevel .. "-" .. g.maxLevel) end
		table.insert(meta, #g.steps .. " steps")
		if entry.builtin then table.insert(meta, "bundled") end
		table.insert(items, {
			key = entry.name, kind = "note", icon = "Waypoint-MapPin-Tracked",
			title = entry.name, sub = table.concat(meta, "  ·  "),
			right = (ns.char.script.name == entry.name) and "|cff66ff66loaded|r" or "",
		})
	end
	if #items == 0 then
		table.insert(items, { key = "none", kind = "tip", title = "No guides yet",
			sub = "Record one above, or Import a guide someone shared." })
	end
	p.list:SetItems(items)
end

---------------------------------------------------------------------------
-- Import / export box
-- The game can't open a browser, so the invite goes in a box you can copy out of.
function UI:ShowDiscord()
	self:ShowIO("export", ns.DISCORD, "NeverQuest on Discord",
		"Press Ctrl+C to copy, then paste it into your browser. Bug reports, help and suggestions all have a channel.")
end

---------------------------------------------------------------------------
-- onImport(text) handles the Import button (default: guides) and returns true to close.
function UI:ShowIO(mode, text, title, hint, onImport)
	local io = self.io
	if not io then
		io = CreateFrame("Frame", "NeverQuestIOFrame", UIParent, "BackdropTemplate")
		io:SetSize(520, 360)
		io:SetPoint("CENTER")
		io:SetFrameStrata("DIALOG")
		ns.ApplyBackdrop(io, 0.97)
		ns.MakeMovable(io, "io", nil, { "CENTER", UIParent, "CENTER", 0, 0 })
		table.insert(UISpecialFrames, "NeverQuestIOFrame")

		io.title = io:CreateFontString(nil, "OVERLAY", "NeverQuestFontNormal")
		io.title:SetPoint("TOPLEFT", 12, -12)
		local close = CreateFrame("Button", nil, io, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -2, -2)

		local sf = CreateFrame("ScrollFrame", nil, io, "UIPanelScrollFrameTemplate")
		sf:SetPoint("TOPLEFT", 12, -36)
		sf:SetPoint("BOTTOMRIGHT", -32, 44)
		local eb = CreateFrame("EditBox", nil, sf)
		eb:SetMultiLine(true)
		eb:SetFontObject(NeverQuestFontSmall)
		eb:SetWidth(470)
		eb:SetAutoFocus(false)
		eb:SetMaxLetters(0)
		eb:SetScript("OnEscapePressed", eb.ClearFocus)
		sf:SetScrollChild(eb)
		sf:SetScript("OnMouseDown", function() eb:SetFocus() end)
		io.edit = eb

		io.action = Button(io, "Import", 100, function()
			local handler = io.onImport or function(t) return ns.Guide:Import(t) end
			if handler(io.edit:GetText()) then
				io:Hide()
				UI:Refresh()
			end
		end)
		io.action:SetPoint("BOTTOMRIGHT", -12, 12)
		io.hint = io:CreateFontString(nil, "OVERLAY", "NeverQuestFontSmallGray")
		io.hint:SetPoint("BOTTOMLEFT", 14, 18)
		self.io = io
	end
	io.edit:SetText(text or "")
	io.onImport = onImport
	if mode == "export" then
		io.title:SetText(title or "Export guide")
		io.hint:SetText(hint or "Press Ctrl+C to copy, then share the text.")
		io.action:Hide()
		io:Show()
		io.edit:SetFocus()
		io.edit:HighlightText()
	else
		io.title:SetText(title or "Import guide")
		io.hint:SetText(hint or "Paste a NeverQuest guide (starts with QMG1~) and click Import.")
		io.action:Show()
		io:Show()
		io.edit:SetFocus()
	end
end

---------------------------------------------------------------------------
-- Options panel (Esc > Options > AddOns > NeverQuest, or the Options button)
---------------------------------------------------------------------------
local function Check(parent, x, y, label, get, set, tooltip)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(26, 26)
	cb:SetPoint("TOPLEFT", x, y)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	fs:SetPoint("LEFT", cb, "RIGHT", 2, 1)
	fs:SetText(label)
	cb:SetScript("OnShow", function(self) self:SetChecked(get()) end)
	cb:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
		PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
	end)
	if tooltip then
		cb:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(label)
			GameTooltip:AddLine(tooltip, 1, 1, 1, true)
			ns.TipShow(tooltip)
		end)
		cb:SetScript("OnLeave", GameTooltip_Hide)
	end
	cb:SetChecked(get())
	return cb
end

-- A label and a dropdown of values.
local function Cycle(parent, x, y, label, values, get, set, tooltip)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	fs:SetPoint("TOPLEFT", x + 4, y - 4)
	fs:SetText(label)
	local b = Button(parent, "", 150, nil)
	b:SetPoint("TOPLEFT", x + 140, y)
	AddArrow(b)
	local function Label()
		local cur = get()
		for _, v in ipairs(values) do
			if v[1] == cur then return v[2] end
		end
		-- A size dragged with a window's corner, or a value from an older version.
		if type(cur) == "number" then
			return cur < 5 and string.format("%d%%", math.floor(cur * 100 + 0.5)) or ("Custom (" .. math.floor(cur + 0.5) .. ")")
		end
		return values[1][2]
	end
	b:SetText(Label())
	b:SetScript("OnShow", function(self) self:SetText(Label()) end)
	b:SetScript("OnClick", function(self)
		UI.Choose(self, (label:gsub(":$", "")), values, get, function(v) set(v) self:SetText(Label()) end)
	end)
	if tooltip then
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(label)
			GameTooltip:AddLine(tooltip, 1, 1, 1, true)
			ns.TipShow(tooltip)
		end)
		b:SetScript("OnLeave", GameTooltip_Hide)
	end
	return b
end

local function Heading(parent, x, y, text)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetText(text)
end

-- The same widgets for other windows (setup wizard, help).
UI.Check, UI.Cycle, UI.Heading, UI.Button = Check, Cycle, Heading, Button

-- A settings page: title and description, then a scrolling area for the controls.
-- Returns the page frame and the frame controls go in.
local function NewPanel(name, titleText, subText)
	local p = CreateFrame("Frame", nil, nil, "BackdropTemplate")
	p.name = name
	local title = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(titleText)
	local sub = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	sub:SetPoint("RIGHT", p, "RIGHT", -16, 0)
	sub:SetJustifyH("LEFT")
	sub:SetText(subText)
	local scroll = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -54)
	scroll:SetPoint("BOTTOMRIGHT", -28, 8)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(640, 600)
	scroll:SetScrollChild(content)
	p.scroll, p.content = scroll, content
	return p, content
end

-- Column layout helper: each call returns the next row's y offset.
local function Column(x)
	local col = { x = x, y = -6 }
	function col:Next(gap)
		local y = self.y
		self.y = self.y - (gap or 24)
		return y
	end
	return col
end

local function FitContent(content, ...)
	local lowest = 0
	for i = 1, select("#", ...) do lowest = math.min(lowest, (select(i, ...)).y) end
	content:SetHeight(-lowest + 20)
end

function UI:CreateOptions()
	local db = ns.db
	local St = ns.Style
	self.panels, self.pageCategories = {}, {}
	local function Page(key, name, title, sub)
		local p, c = NewPanel(name, title, sub)
		table.insert(self.panels, { key = key, panel = p, content = c, name = name })
		return p, c
	end
	local function Guide() ns.Guide:Refresh() end
	local function Track() ns.Tracker:Refresh() end

	---------------------------------------------------------------- NeverQuest (general)
	local _, p = Page("general", "NeverQuest", "NeverQuest " .. ns.version .. "  by " .. ns.AUTHOR,
		"Hold Shift while talking to an NPC to skip auto accept and turn-in for that conversation.")
	local L, R = Column(16), Column(330)

	Heading(p, L.x, L:Next(), "Automation")
	Check(p, L.x, L:Next(), "Auto-accept quests", function() return db.auto.accept end, function(v) db.auto.accept = v end)
	Cycle(p, L.x, L:Next(30), "Which quests:", { { "all", "Every quest" }, { "route", "Only ones the route will do" } },
		function() return db.auto.acceptOnly end, function(v) db.auto.acceptOnly = v end,
		"Only ones the route will do: quests the guide plans to do, class and profession quests, quests for your chosen dungeons and attunement, and others worth their time against your route. The rest you can still accept by hand.")
	Check(p, L.x, L:Next(), "Auto turn in finished quests", function() return db.auto.turnin end, function(v) db.auto.turnin = v end)
	Check(p, L.x, L:Next(), "Handle NPC dialog windows", function() return db.auto.gossip end, function(v) db.auto.gossip = v end,
		"Picks finished quests to turn in, then new quests, when an NPC offers several.")
	Check(p, L.x, L:Next(), "Don't auto-accept gray quests", function() return db.auto.skipGray end, function(v) db.auto.skipGray = v end,
		"Gray (low level) quests give little XP.")
	Check(p, L.x, L:Next(), "Don't automate repeatable quests", function() return db.auto.skipRepeatable end, function(v) db.auto.skipRepeatable = v end,
		"Avoids handing in stacks of items to repeatable quests without asking.")
	Cycle(p, L.x, L:Next(30), "Reward choice:", { { "suggest", "Mark the best one" }, { "upgrade", "Take upgrades, else value" },
		{ "value", "Take highest vendor value" }, { "off", "Do nothing" } },
		function() return db.auto.reward end, function(v) db.auto.reward = v end)
	local rewardNote = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	rewardNote:SetPoint("TOPLEFT", L.x + 4, L:Next(30))
	rewardNote:SetWidth(290)
	rewardNote:SetJustifyH("LEFT")
	rewardNote:SetText("Upgrades are judged by the stats your class uses against what you wear. Without one, the highest vendor value is picked.")
	Cycle(p, L.x, L:Next(30), "Accept group invites from:", { { "off", "Nobody" }, { "known", "Guildmates and friends" }, { "anyone", "Anyone" } },
		function() return db.auto.inviteFrom end, function(v) db.auto.inviteFrom = v end,
		"An invite is how someone pulls you into an instance, into a raid, or to wherever they are standing, so this is off until you choose otherwise. Hold Shift to let one through manually.")
	Check(p, L.x, L:Next(), "Invite anyone who whispers the keyword", function() return db.auto.inviteSend end,
		function(v) db.auto.inviteSend = v end,
		"A whisper of just the keyword gets that person an invite. At most one per person per minute.")
	local wordRow = L:Next(26)
	local wordLabel = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	wordLabel:SetPoint("TOPLEFT", L.x + 18, wordRow - 4)
	wordLabel:SetText("Keyword:")
	local wordBox = EditBox(p, 80)
	wordBox:SetPoint("TOPLEFT", L.x + 78, wordRow)
	wordBox:SetText(db.auto.inviteWord or "inv")
	wordBox:SetScript("OnEditFocusLost", function(e)
		local v = (e:GetText() or ""):lower():match("^%s*(%S*)")
		if not v or v == "" then v = "inv" end
		db.auto.inviteWord = v
		e:SetText(v)
	end)
	Check(p, L.x, L:Next(), "Auto loot everything", function() return db.loot.auto end, function(v) db.loot.auto = v end,
		"Takes everything from a loot window at once. Hold Shift (the game's auto-loot key) to look first. Items waiting on a group roll are left alone.")
	Check(p, L.x, L:Next(), "Sell junk at vendors", function() return db.loot.junk end, function(v) db.loot.junk = v end,
		"Gray items are sold when you open a vendor. Hold Shift while opening the vendor to skip it. You can buy them back from the vendor's Buyback tab.")
	Check(p, L.x + 16, L:Next(), "Say what the junk sold for", function() return db.loot.junkReport end, function(v) db.loot.junkReport = v end)
	Check(p, L.x, L:Next(), "Repair at vendors", function() return db.loot.repair end, function(v) db.loot.repair = v end,
		"Repairs everything when you open a vendor that can repair. Hold Shift while opening the vendor to skip it.")
	Check(p, L.x + 16, L:Next(), "Use guild funds when allowed", function() return db.loot.repairGuild end, function(v) db.loot.repairGuild = v end,
		"Uses your guild's repair money first if your rank allows it and the daily limit covers the cost.")

	L:Next(10)
	Heading(p, L.x, L:Next(), "Reminders")
	local up = db.upkeep
	Check(p, L.x, L:Next(), "Profession nearly capped", function() return up.training end,
		function(v) up.training = v ns.Guide:Refresh() end,
		"A reminder when a profession is within ten points of its current rank, so you train the next rank on your next trip to a town instead of grinding into the ceiling.")
	Check(p, L.x, L:Next(), "Upgrades sitting in my bags", function() return up.upgrades end,
		function(v) up.upgrades = v ns.Upkeep.bagCache = nil ns.Guide:Refresh() end,
		"A guide row when something in your bags beats what you're wearing, judged the same way as quest rewards.")
	local function Re() ns.Guide:Refresh() end
	Check(p, L.x, L:Next(), "Quest log full: say what to drop", function() return up.logFull end, function(v) up.logFull = v Re() end,
		"Suggests quests to drop (failed, gray, far away, little XP for the walk). Never ones ready to hand in or your attunement.")
	Check(p, L.x, L:Next(), "Low on food, water or ammo", function() return up.supplies end, function(v) up.supplies = v Re() end)
	Check(p, L.x, L:Next(), "Bags almost full (and leftover quest items)", function() return up.bags end, function(v) up.bags = v Re() end,
		"Lists quest items you can safely delete because their quest is done.")
	Check(p, L.x, L:Next(), "Logging out with no rested XP", function() return up.rested end, function(v) up.rested = v end,
		"Reminds you to use an inn, a city or your Cozy Sleeping Bag before you log out.")
	Check(p, L.x, L:Next(), "Session summary when logging out", function() return up.sessionAtLogout end, function(v) up.sessionAtLogout = v end,
		"XP, levels, quests, gold and time for this session. /nq session shows it any time.")

	L:Next(10)
	Heading(p, L.x, L:Next(), "Travel")
	local tr = db.travel
	Check(p, L.x, L:Next(), "Flight paths you don't have yet", function() return tr.flightPaths end, function(v) tr.flightPaths = v Re() end,
		"A guide step for the nearest flight master in your zone you haven't talked to.")
	Check(p, L.x, L:Next(), "Hearthstone: say when to hearth back", function() return tr.hearth end, function(v) tr.hearth = v Re() end,
		"When your hearthstone is ready, nothing's left nearby, and finished quests are handed in near your inn.")
	Check(p, L.x + 16, L:Next(), "Put it on the quest item bar", function() return tr.hearthButton end, function(v) tr.hearthButton = v ns.Buttons:Update() end)
	Check(p, L.x, L:Next(), "Suggest a new home inn", function() return tr.setHearth end, function(v) tr.setHearth = v end,
		"At an inn far from your hearth spot with quests around, says once that you could bind here.")

	L:Next(10)
	Heading(p, L.x, L:Next(), "Alerts")
	Check(p, L.x, L:Next(), "Alert when a quest is ready to turn in", function() return db.alerts.complete end, function(v) db.alerts.complete = v end)
	Check(p, L.x, L:Next(), "Play sounds", function() return db.alerts.sound end, function(v) db.alerts.sound = v end)
	Check(p, L.x, L:Next(), "Point arrow at turn-in when ready", function() return db.alerts.trackTurnin end, function(v) db.alerts.trackTurnin = v end,
		"Only used when the guide isn't steering the arrow.")

	Heading(p, R.x, R:Next(), "Party")
	Check(p, R.x, R:Next(), "Share quest progress with my party", function() return db.party.enabled end,
		function(v) db.party.enabled = v if v then ns.Party:SendSnapshot() end end,
		"Party members running NeverQuest see your progress on shared quests, and you see theirs. Party only, not raids.")
	local function Party() ns.Catchup:Invalidate() ns.Planner.dirty = true ns.Guide.focusKey = nil ns.Guide:Refresh() end
	Check(p, R.x, R:Next(), "Party catch-up", function() return db.party.catchUp end, function(v) db.party.catchUp = v Party() end,
		"In a party, the guide and route adapt so everyone keeps up: shared quests first, turn-ins wait (and the route takes you back to help) while someone still needs that quest, and quests a party member is on count for more.")
	Check(p, R.x + 16, R:Next(), "Plan zones for the lowest level in the party", function() return db.party.groupLevel end,
		function(v) db.party.groupLevel = v Party() end)
	Check(p, R.x + 16, R:Next(), "Regroup when someone is far away", function() return db.party.regroup end,
		function(v) db.party.regroup = v Party() end, "Adds a step that points the arrow at a party member more than 300 yards away.")
	Check(p, R.x + 16, R:Next(), "Suggest quests to share or ask for", function() return db.party.shareTips end,
		function(v) db.party.shareTips = v Party() end, "Quests lists come from party members running NeverQuest.")
	Check(p, R.x, R:Next(), "Share quests with my party as I pick them up", function() return db.party.autoShare end,
		function(v) db.party.autoShare = v end,
		"Offers each quest you take from an NPC to your party. A quest that was shared to you isn't shared back, and nothing is sent in a raid.")
	local function PartyRefresh() ns.Party:ForgetProbes() ns.Tracker:Refresh() ns.Pins:Refresh(true) end
	Check(p, R.x, R:Next(), "Party view in the tracker", function() return db.tracker.partyView ~= false end,
		function(v) db.tracker.partyView = v PartyRefresh() end,
		"A Party section at the top of the tracker: each member and how they're doing on your quests, quests to hand in together, and what someone still needs that you can help with.")
	Check(p, R.x, R:Next(), "See quests of members without NeverQuest", function() return db.party.probe ~= false end,
		function(v) db.party.probe = v PartyRefresh() end,
		"The game says which quests a party member is on even without NeverQuest (not how far along). Checked for your quests and the ones on offer near you.")
	Check(p, R.x, R:Next(), "Party alerts in chat", function() return db.party.alerts ~= false end,
		function(v) db.party.alerts = v end,
		"A line in chat when someone on a quest you share finishes an objective or the quest, and when everyone is ready to hand it in. Needs them to run NeverQuest.")
	Check(p, R.x + 16, R:Next(), "With a sound", function() return db.party.alertSound ~= false end,
		function(v) db.party.alertSound = v end)
	Check(p, R.x, R:Next(), "Map: what your party still needs", function() return db.party.mapHelp ~= false end,
		function(v) db.party.mapHelp = v PartyRefresh() end,
		"Blue markers on the world map and minimap where the work is for quests a party member is on that you've finished or don't have. Click one to point the arrow there.")

	R:Next(10)
	Heading(p, R.x, R:Next(), "Tooltips")
	local tt = db.tooltips
	Check(p, R.x, R:Next(), "Quest lines on mobs", function() return tt.units end, function(v) tt.units = v end,
		"Adds the quest and objective to mobs NeverQuest has learned drop a quest item. The game already lists objectives on mobs it knows about.")
	Check(p, R.x, R:Next(), "Party progress on mobs", function() return tt.party end, function(v) tt.party = v end,
		"How far along each party member is on the quest a mob counts for. Needs them to run NeverQuest.")
	Check(p, R.x, R:Next(), "Which quest wants an item", function() return tt.items end, function(v) tt.items = v end)

	R:Next(10)
	Heading(p, R.x, R:Next(), "Party announcements")
	local an = db.announce
	Check(p, R.x, R:Next(), "Announce completions in party chat", function() return an.enabled end, function(v) an.enabled = v end,
		"Tells your group when you finish something. Party chat, or instance chat in a dungeon finder group. /nq announce test sends a test line.")
	Check(p, R.x + 16, R:Next(), "Objectives finished", function() return an.objectives end, function(v) an.objectives = v end,
		"Only for quests with more than one objective; the last one is covered by \"quest complete\".")
	Check(p, R.x + 16, R:Next(), "Quests ready to turn in", function() return an.quests end, function(v) an.quests = v end)
	Check(p, R.x + 16, R:Next(), "Quests turned in", function() return an.turnins end, function(v) an.turnins = v end)
	Check(p, R.x + 16, R:Next(), "Raid attunement steps", function() return an.attunements end, function(v) an.attunements = v end)
	Check(p, R.x + 16, R:Next(), "Only quests someone in the group is also on", function() return an.sharedOnly end, function(v) an.sharedOnly = v end)
	Check(p, R.x + 16, R:Next(), "Also in raid groups", function() return an.raid end, function(v) an.raid = v end)
	Check(p, R.x + 16, R:Next(), "Clickable quest links", function() return an.links end, function(v) an.links = v end)
	Check(p, R.x + 16, R:Next(), "Start messages with \"NeverQuest:\"", function() return an.tag end, function(v) an.tag = v end)

	R:Next(10)
	Heading(p, R.x, R:Next(), "Quest database")
	local qd = db.questdb
	Check(p, R.x, R:Next(), "Use QuestieDB for quest data", function() return qd.bundled ~= false end,
		function(v) ns.QuestDB:SetBundled(v) end,
		"QuestieDB, the quest database the Questie team builds and keeps up to date, fills in quest givers and turn-ins NeverQuest hasn't seen yet. It's installed with NeverQuest as its own addon, and /nq credits names the people who make it. Off: build your own. NeverQuest doesn't read QuestieDB and goes by what your characters see, what it shipped of its own and what your party and guild pass on.")
	Check(p, R.x + 16, R:Next(), "Note where QuestieDB's data is wrong", function() return qd.fixes ~= false end,
		function(v) qd.fixes = v ns.QuestDB:ClearNearby() ns:SendMessage("MAP_OFFERS_UPDATED") end,
		"Standing where QuestieDB puts a quest giver, with the quest not on offer to you, or finding the giver or turn-in somewhere else: NeverQuest writes it down and stops showing the wrong place. QuestieDB itself is never changed. Ctrl+click a known quest on the world map to say so yourself. /nq db fixes lists them, and Export starts includes them.")
	Check(p, R.x, R:Next(), "Scan zones for quests in the background", function() return qd.scan end,
		function(v) qd.scan = v if not v then ns.QuestDB:StopScan() end end,
		"Asks the game which quests each zone offers, one zone every couple of seconds, paused in combat. Every character adds to one shared database. /nq db searches it.")
	Check(p, R.x, R:Next(), "Known quest starts on the world map", function() return qd.worldmap end,
		function(v) qd.worldmap = v ns.QuestDB:ClearNearby() ns:SendMessage("MAP_OFFERS_UPDATED") end,
		"Faded markers for quests you know about that aren't on offer to you yet, with the level they open at. This is where everything your alts, your party, your guild and the shipped data know shows up.")
	Check(p, R.x, R:Next(), "Known quest starts on the minimap", function() return qd.minimap end,
		function(v) qd.minimap = v ns.QuestDB:ClearNearby() ns:SendMessage("MAP_OFFERS_UPDATED") end,
		"The same, on the minimap, for starts within sight of you. Keeps you from walking past a quest giver your guild already told you about.")
	Check(p, R.x, R:Next(), "Also learn quests I can't take yet", function() return qd.deep end,
		function(v) qd.deep = v if not v then ns.QuestDB:StopScan() end end,
		"A quest you can see tells the game which chain it belongs to, so NeverQuest can ask for the names and levels of the rest of that chain, including quests above your level. This is what fills the database in before you have played the zone.")
	Check(p, R.x, R:Next(), "Share quest starts with my party", function() return qd.share end,
		function(v) qd.share = v end,
		"Party members running NeverQuest pass on the quest givers they have stood in front of, and you pass on yours. Places only, nothing about you.")
	Check(p, R.x, R:Next(), "Share quest starts with my guild", function() return qd.guild end,
		function(v) qd.guild = v end,
		"The same, across your guild, where there are far more people at more levels. This is what fills the map in for a new character. Somewhere you have been yourself is never overwritten by someone else's report.")
	Check(p, R.x, R:Next(), "Hide NeverQuest's quest pins while Questie runs", function() return db.compat.questie end,
		function(v) db.compat.questie = v ns:SendMessage("MAP_OFFERS_UPDATED") end,
		"Questie draws quest givers and objectives itself. Your guide, route and arrow stay either way.")
	local qdRow = R:Next(26)
	local qdExport = Button(p, "Export starts", 110, function()
		local text, n = ns.QuestDB:Export()
		if n == 0 then ns.Print("no quest starts with a place to export yet.") return end
		UI:ShowIO("export", text, "Export quest starts",
			n .. " quest starts. Press Ctrl+C to copy. Quests and places only: no character or realm names.")
	end)
	qdExport:SetPoint("TOPLEFT", p, "TOPLEFT", R.x, qdRow)
	local qdAsk = Button(p, "Ask my guild", 110, function()
		local ok, why = ns.QuestDB:Ask()
		ns.Print(ok and "asked your guild for quest starts." or ("can't ask: " .. (why or "?")))
	end)
	qdAsk:SetPoint("TOPLEFT", p, "TOPLEFT", R.x + 236, qdRow)
	local qdImport = Button(p, "Import starts", 110, function()
		UI:ShowIO("import", "", "Import quest starts",
			"Paste quest start data (it begins with NQQ1~) and press Import.", function(t) return ns.QuestDB:Import(t) end)
	end)
	qdImport:SetPoint("TOPLEFT", p, "TOPLEFT", R.x + 118, qdRow)

	R:Next(10)
	Heading(p, R.x, R:Next(), "Chat")
	Check(p, R.x, R:Next(), "Login message", function() return not db.quietLogin end, function(v) db.quietLogin = not v end)
	Check(p, R.x, R:Next(), "Debug messages", function() return db.debug end, function(v) db.debug = v end,
		"Prints what NeverQuest is doing (arrow targets, routes, learning). Handy when testing.")

	R:Next(10)
	Heading(p, R.x, R:Next(), "More settings")
	local more = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	more:SetPoint("TOPLEFT", R.x + 4, R:Next(60))
	more:SetWidth(290)
	more:SetJustifyH("LEFT")
	more:SetText("The pages under NeverQuest in this list: Guide & Routes, Tracker, Display & Maps, Spawns & Objectives, and Scale & Text.")
	local runSetup = Button(p, "Setup wizard", 120, function()
		ns.Setup:Open()
	end)
	runSetup:SetPoint("TOPLEFT", R.x + 4, R:Next(30))
	local openHelp = Button(p, "Help", 90, function()
		ns.Help:Open()
	end)
	openHelp:SetPoint("LEFT", runSetup, "RIGHT", 8, 0)
	FitContent(p, L, R)
	self.options = p

	---------------------------------------------------------------- Guide & Routes
	local _, g = Page("guide", "Guide & Routes", "Guide & Routes",
		"How the guide picks and orders your next steps, and what each step shows.")
	local L1, R1 = Column(16), Column(330)

	Heading(g, L1.x, L1:Next(), "Guide")
	Cycle(g, L1.x, L1:Next(30), "Leveling style:", ns.Profiles.STYLES, function() return ns.Profiles:Style() end,
		function(v) db.guide.style = v ns.Guide.focusKey = nil ns.Planner.dirty = true Guide() end,
		"Optimized 1-60: go where the XP per hour is best, from the quest data, with your plan's zones as the fallback; slow quests are left out and you're told which to drop. Zone by zone: the completionist way, every quest in a zone (gray ones too) before the next one in your plan.")
	Check(g, L1.x, L1:Next(), "Guide steers the arrow", function() return db.guide.autoTrack end, function(v) db.guide.autoTrack = v Guide() end,
		"The arrow follows the top guide step. Your own /way waypoints always come first.")
	Check(g, L1.x, L1:Next(), "Include gray quests", function() return db.guide.showGray end, function(v) db.guide.showGray = v Guide() end)
	Check(g, L1.x, L1:Next(), "Follow my 1-60 plan", function() return db.guide.profile end, function(v) db.guide.profile = v ns.Planner.dirty = true Guide() end,
		"Uses your leveling style's route for your race: quests in the zones it wants you in count for more, and the guide says when to move on. Off: no zone preference.")
	Check(g, L1.x, L1:Next(), "Class milestones and trainer reminders", function() return db.guide.milestones end, function(v) db.guide.milestones = v Guide() end)
	local function Tabs() UI:LayoutTabs() UI:Refresh() end
	Check(g, L1.x, L1:Next(), "Class quests section", function() return db.guide.classTab end, function(v) db.guide.classTab = v Tabs() end,
		"The Class tab: class quests in your log and a checklist of what your class has coming.")
	Check(g, L1.x, L1:Next(), "Profession quests section", function() return db.guide.profQuests end, function(v) db.guide.profQuests = v Tabs() end,
		"The quests your professions wait on, in the same tab. With both sections off the tab is removed.")
	Check(g, L1.x + 16, L1:Next(), "Only my professions", function() return db.guide.profMine end, function(v) db.guide.profMine = v Tabs() end,
		"Off lists every profession, to plan what to pick up.")
	Check(g, L1.x, L1:Next(), "Dungeons for my level", function() return db.guide.dungeonTips end, function(v) db.guide.dungeonTips = v Guide() end)
	Check(g, L1.x, L1:Next(), "Get dungeon quests and their pre-quests first", function() return db.guide.dungeonQuests ~= false end,
		function(v) ns.Dungeons:SetOn(v) end,
		"For the dungeons you tick, the route picks up their quests a couple of levels before you're ready, and the quests that have to be done first to open them. These count for a lot more than ordinary quests. Dungeon quests in your log wait for the dungeon instead of sending you to its entrance alone.")
	local dqRow = L1:Next(26)
	local dqPick = Button(g, "Choose dungeons...", 150, function() ns.Dungeons:OpenPicker() end)
	dqPick:SetPoint("TOPLEFT", g, "TOPLEFT", L1.x + 16, dqRow)
	Check(g, L1.x + 16, L1:Next(), "Choose zones from the quest data (follows you)", function() return db.guide.smartZones ~= false end,
		function(v) db.guide.smartZones = v ns.Guide.focusKey = nil ns.Planner.dirty = true Guide() end,
		"At every level and in both styles: works from wherever you are, stays while your zone has quests for you, and picks the next zone by XP per hour from every quest you can take there (its XP, where its work is, and the trip). Your 1-60 plan breaks ties and takes over when too little is known. /nq zones lists the zones.")
	Check(g, L1.x + 16, L1:Next(), "Optimized: suggest quests to drop", function() return db.guide.dropAdvice ~= false end,
		function(v) db.guide.dropAdvice = v Guide() end,
		"A note in the guide names quests in your log that aren't worth finishing: gray, too slow for their XP, or in a zone you've outleveled. Never finished quests, class or profession quests, your attunement or dungeon quests you're gathering. Nothing is dropped unless you confirm it.")
	Check(g, L1.x + 16, L1:Next(), "Zone by zone: finish every quest in a zone", function() return db.guide.completionist ~= false end,
		function(v) db.guide.completionist = v ns.Guide.focusKey = nil ns.Planner.dirty = true Guide() end,
		"The completionist way: every quest in the zone goes on the route, gray ones included, nothing is left out for being slow, and the zone is done before you move on (unless you're four levels past it).")
	Check(g, L1.x, L1:Next(), "Keep a list of quests I skip, drop or leave behind", function() return db.guide.missedList ~= false end,
		function(v) db.guide.missedList = v Guide() end,
		"Quests tab > Missed. Right-click any quest in the guide or tracker to skip it; right-click one on the list to go back for it.")
	Check(g, L1.x, L1:Next(), "Tell me when to move to the next zone", function() return db.guide.zoneAdvice end, function(v) db.guide.zoneAdvice = v Guide() end)
	Check(g, L1.x, L1:Next(), "Tell me when I've outleveled a zone", function() return db.guide.outleveledTip end, function(v) db.guide.outleveledTip = v Guide() end)
	Check(g, L1.x, L1:Next(), "Rested XP reminder", function() return db.guide.restedTip end, function(v) db.guide.restedTip = v Guide() end)
	Check(g, L1.x, L1:Next(), "Raid attunements in the guide", function() return db.guide.attunements end, function(v) db.guide.attunements = v Guide() end,
		"The attunement you follow (Raids tab) adds its next step to the guide: right after your next leveling step, or first once you hit the level cap. Near the cap, a reminder offers to follow one.")
	Cycle(g, L1.x + 16, L1:Next(30), "Remind me from level:", { { 45, "45" }, { 50, "50" }, { 55, "55" }, { 60, "60" } },
		function() return db.guide.attuneAt end, function(v) db.guide.attuneAt = v Guide() end)

	L1:Next(10)
	Heading(g, L1.x, L1:Next(), "What each step shows")
	Check(g, L1.x, L1:Next(), "Quest XP", function() return db.guide.xpInSteps end, function(v) db.guide.xpInSteps = v Guide() end)
	Check(g, L1.x, L1:Next(), "Route directions (\"via\")", function() return db.guide.viaInSteps end, function(v) db.guide.viaInSteps = v Guide() end)
	Check(g, L1.x, L1:Next(), "Party progress", function() return db.guide.partyInSteps end, function(v) db.guide.partyInSteps = v Guide() end)

	Heading(g, R1.x, R1:Next(), "Route planning")
	Check(g, R1.x, R1:Next(), "Plan one short route through my quests", function() return db.guide.planner end,
		function(v) db.guide.planner = v ns.Planner.dirty = true Guide() end,
		"Orders objectives, turn-ins and quest pickups to save backtracking, and leaves out quests worth too little XP for the trip. Off: nearest best-XP quest first.")
	Check(g, R1.x, R1:Next(), "Favor quest chains", function() return db.guide.chains end,
		function(v) db.guide.chains = v ns.Planner.dirty = true Guide() end,
		"Quests that open up follow-ups are worth more, and steps show where a quest sits in its chain. Chains come from the game's quest lines and from what you've seen after turn-ins.")
	Check(g, R1.x, R1:Next(), "Pick up quests along the way", function() return db.guide.planPickups end,
		function(v) db.guide.planPickups = v ns.Planner.dirty = true Guide() end)
	Check(g, R1.x, R1:Next(), "Show where each quest will be turned in", function() return db.guide.showPredicted end,
		function(v) db.guide.showPredicted = v Guide() end,
		"\"Then turn in\" steps, from where you (or another of your characters) handed the quest in or picked it up.")
	Check(g, R1.x, R1:Next(), "Route summary (time, XP, XP per hour)", function() return db.guide.routeSummary end, function(v) db.guide.routeSummary = v Guide() end)
	Check(g, R1.x, R1:Next(), "Without route planning: nearby turn-ins first", function() return db.guide.nearbyFirst end, function(v) db.guide.nearbyFirst = v Guide() end)
	Cycle(g, R1.x, R1:Next(30), "Nearby radius:", { { 100, "100 yards" }, { 200, "200 yards" }, { 350, "350 yards" } },
		function() return db.guide.nearbyYards end, function(v) db.guide.nearbyYards = v Guide() end)
	Cycle(g, R1.x, R1:Next(30), "Quest givers listed:", { { 2, "2" }, { 4, "4" }, { 6, "6" }, { 10, "10" } },
		function() return db.guide.maxOffers end, function(v) db.guide.maxOffers = v Guide() end)

	R1:Next(10)
	Heading(g, R1.x, R1:Next(), "Paths")
	Check(g, R1.x, R1:Next(), "Follow the game's paths", function() return db.nav.paths end,
		function(v) db.nav.paths = v ns.Route:Invalidate() ns.Quests:RequestScan() end,
		"Caves, buildings, tunnels and zone exits: the arrow goes to the entrance first, with the game's directions.")
	Check(g, R1.x, R1:Next(), "Suggest flight paths for long trips", function() return db.nav.flights end,
		function(v) db.nav.flights = v ns.Route.flight = nil ns.Route.plannedFor = nil ns.Route:Invalidate() end,
		"Only flight masters you've discovered, and only when flying is clearly faster.")
	FitContent(g, L1, R1)
	self.guideOptions = g

	---------------------------------------------------------------- Tracker
	local _, t = Page("tracker", "Tracker", "Quest tracker",
		"The quest list on the right side of the screen. Right-click its header for quick sorting options.")
	local Lt, Rt = Column(16), Column(330)
	local tc = db.tracker

	Heading(t, Lt.x, Lt:Next(), "Tracker")
	Check(t, Lt.x, Lt:Next(), "Show the NeverQuest tracker", function() return tc.shown end,
		function(v) tc.shown = v Track() ns.Tracker:ControlBlizzard() end)
	Cycle(t, Lt.x, Lt:Next(30), "Blizzard's quest list:", { { "hide", "Hide it" }, { "sort", "Sort by priority" }, { "leave", "Leave it alone" } },
		function() return tc.blizzard end, function(v) tc.blizzard = v ns.Tracker:ControlBlizzard() end,
		"Hide: while the NeverQuest tracker shows, your quests are untracked so Blizzard's quest list is empty. Sort: Blizzard's list stays, in NeverQuest's priority order.")
	Check(t, Lt.x + 14, Lt:Next(), "Also keep Blizzard's tracker frame out of sight", function() return tc.hideFrame end,
		function(v) tc.hideFrame = v if not v then ns.Tracker:UnparkBlizzardFrame() end ns.Tracker:ControlBlizzard() end,
		"Without this, emptying the list isn't enough: the game shows its tracker again whenever you accept or finish a quest, so it flashes up. With it, the frame is parked out of sight while \"Hide it\" is on, and handed straight back when it isn't. Never changed during combat. Turn this off if you want Blizzard's bonus objectives or scenario text visible.")
	Cycle(t, Lt.x, Lt:Next(30), "Sort by:", { { "priority", "Priority" }, { "distance", "Distance" }, { "level", "Level" } },
		function() return tc.sort end, function(v) tc.sort = v Track() end,
		"Priority is the order the guide (and route planner) will do things in.")
	Check(t, Lt.x, Lt:Next(), "Group by zone", function() return tc.groupByZone end, function(v) tc.groupByZone = v Track() end)
	Check(t, Lt.x, Lt:Next(), "Current zone first", function() return tc.currentZoneFirst end, function(v) tc.currentZoneFirst = v Track() end)
	Check(t, Lt.x, Lt:Next(), "Collapse other zones", function() return tc.collapseOther end, function(v) tc.collapseOther = v Track() end,
		"Only your current zone starts open. Click a zone header to open or close it.")
	Check(t, Lt.x, Lt:Next(), "Finished quests first", function() return tc.finishedFirst end, function(v) tc.finishedFirst = v Track() end)
	Check(t, Lt.x, Lt:Next(), "Include gray quests", function() return tc.showGray end, function(v) tc.showGray = v Track() end)
	Check(t, Lt.x, Lt:Next(), "Lock position", function() return tc.locked end, function(v) tc.locked = v end)

	Heading(t, Rt.x, Rt:Next(), "Each quest shows")
	Check(t, Rt.x, Rt:Next(), "Objectives", function() return tc.showObjectives end, function(v) tc.showObjectives = v Track() end)
	Check(t, Rt.x, Rt:Next(), "Hide finished objectives", function() return tc.hideDoneObjectives end, function(v) tc.hideDoneObjectives = v Track() end)
	Check(t, Rt.x, Rt:Next(), "Priority numbers", function() return tc.showNumbers end, function(v) tc.showNumbers = v Track() end)
	Check(t, Rt.x, Rt:Next(), "Quest level", function() return tc.showLevel end, function(v) tc.showLevel = v Track() end)
	Check(t, Rt.x, Rt:Next(), "Distance", function() return tc.showDistance end, function(v) tc.showDistance = v Track() end)
	Check(t, Rt.x, Rt:Next(), "Quest chain", function() return tc.showChains end, function(v) tc.showChains = v Track() end)
	Check(t, Rt.x, Rt:Next(), "Party progress", function() return tc.showParty end, function(v) tc.showParty = v Track() end)

	Rt:Next(10)
	Heading(t, Rt.x, Rt:Next(), "Size")
	Cycle(t, Rt.x, Rt:Next(30), "Quests shown:", { { 10, "10" }, { 15, "15" }, { 25, "25" }, { 35, "All" } },
		function() return tc.maxQuests end, function(v) tc.maxQuests = v Track() end)
	Cycle(t, Rt.x, Rt:Next(30), "Width:", { { 220, "Narrow" }, { 270, "Normal" }, { 320, "Wide" }, { 380, "Wider" } },
		function() return tc.width end, function(v) tc.width = v Track() end)
	Cycle(t, Rt.x, Rt:Next(30), "Height limit:", { { 320, "Short" }, { 520, "Normal" }, { 720, "Tall" }, { 950, "Taller" } },
		function() return tc.maxHeight end, function(v) tc.maxHeight = v Track() end)
	Cycle(t, Rt.x, Rt:Next(30), "Background:", { { 0, "None" }, { 0.25, "Light" }, { 0.45, "Medium" }, { 0.75, "Dark" } },
		function() return tc.bgAlpha end, function(v) tc.bgAlpha = v Track() end)
	Cycle(t, Rt.x, Rt:Next(30), "Tracker size:", St.SCALES, function() return tc.scale end, function(v) tc.scale = v Track() end)

	local dc = db.drops
	local function Drop() ns.Drops:Refresh() end
	Lt:Next(10)
	Heading(t, Lt.x, Lt:Next(), "Drops window")
	Check(t, Lt.x, Lt:Next(), "Show the drops window", function() return dc.shown end, function(v) dc.shown = v Drop() end,
		"A separate list of the quest items you still have to collect, how many you have, and which mobs you have seen them drop from.")
	Check(t, Lt.x, Lt:Next(), "Show where it drops", function() return dc.showSource end, function(v) dc.showSource = v Drop() end,
		"The gray line under each item: the mobs NeverQuest has watched you get it from, and the distance to the nearest spot it knows.")
	Cycle(t, Lt.x, Lt:Next(30), "Sort by:", { { "progress", "Closest to done" }, { "remaining", "Fewest left" }, { "distance", "Nearest" } },
		function() return dc.sort end, function(v) dc.sort = v Drop() end)
	Check(t, Lt.x, Lt:Next(), "Lock position", function() return dc.locked end, function(v) dc.locked = v end)
	Cycle(t, Lt.x, Lt:Next(30), "Width:", { { 210, "Narrow" }, { 250, "Normal" }, { 300, "Wide" }, { 360, "Wider" } },
		function() return dc.width end, function(v) dc.width = v Drop() end)
	Cycle(t, Lt.x, Lt:Next(30), "Height limit:", { { 240, "Short" }, { 420, "Normal" }, { 600, "Tall" } },
		function() return dc.maxHeight end, function(v) dc.maxHeight = v Drop() end)
	Cycle(t, Lt.x, Lt:Next(30), "Background:", { { 0, "None" }, { 0.25, "Light" }, { 0.45, "Medium" }, { 0.75, "Dark" } },
		function() return dc.bgAlpha end, function(v) dc.bgAlpha = v Drop() end)
	Cycle(t, Lt.x, Lt:Next(30), "Drops size:", St.SCALES, function() return dc.scale end, function(v) dc.scale = v Drop() end)
	FitContent(t, Lt, Rt)
	self.trackerOptions = t

	---------------------------------------------------------------- Display & Maps
	local _, d = Page("display", "Display & Maps", "Display & Maps", "The XP panel, the waypoint arrow, quest buttons and map pins.")
	local L2, R2 = Column(16), Column(330)

	Heading(d, L2.x, L2:Next(), "Tooltips")
	Cycle(d, L2.x, L2:Next(30), "Hover tooltips:", { { "line", "One line" }, { "off", "Off" }, { "full", "Full" } },
		function() return ns.TipMode() end, function(v) db.window.tips = v end,
		"What NeverQuest's own tooltips show when you hover the arrow, the guide, the tracker, pins and buttons: one line, nothing, or every detail.")

	Heading(d, L2.x, L2:Next(), "XP panel")
	Check(d, L2.x, L2:Next(), "Show XP panel", function() return db.hud.shown end, function(v) db.hud.shown = v ns.XP:Refresh() end)
	Check(d, L2.x, L2:Next(), "Rested XP line", function() return db.hud.showRested end, function(v) db.hud.showRested = v ns.XP:Refresh() end)
	Check(d, L2.x, L2:Next(), "XP per hour line", function() return db.hud.showRate end, function(v) db.hud.showRate = v ns.XP:Refresh() end)
	Check(d, L2.x, L2:Next(), "Quests or kills to level line", function() return db.hud.showToLevel end, function(v) db.hud.showToLevel = v ns.XP:Refresh() end)
	Check(d, L2.x, L2:Next(), "Ready to turn in / session line", function() return db.hud.showFooter end, function(v) db.hud.showFooter = v ns.XP:Refresh() end)
	Check(d, L2.x, L2:Next(), "Lock XP panel and arrow", function() return db.hud.locked end, function(v) db.hud.locked, db.arrow.locked = v, v end)

	L2:Next(6)
	Heading(d, L2.x, L2:Next(), "Waypoint arrow")
	Check(d, L2.x, L2:Next(), "Show waypoint arrow", function() return db.arrow.shown end, function(v) db.arrow.shown = v ns.Nav:Update() end)
	Check(d, L2.x, L2:Next(), "Keep it visible with no waypoint", function() return db.arrow.alwaysShow end, function(v) db.arrow.alwaysShow = v ns.Nav:Update() end)
	Check(d, L2.x, L2:Next(), "Coordinates line", function() return not db.arrow.compact end, function(v) db.arrow.compact = not v ns.Nav:Update() end)
	Check(d, L2.x, L2:Next(), "Arrival time (ETA)", function() return db.arrow.showETA end, function(v) db.arrow.showETA = v end)
	Check(d, L2.x, L2:Next(), "\"then:\" line for the final target", function() return db.arrow.showThen end, function(v) db.arrow.showThen = v ns.Nav:Update() end)
	local pl = db.plates
	local function Plates() ns.Plates:RefreshAll() end
	Check(d, L2.x, L2:Next(), "Hide spots well below my level", function() return db.spawns.levelFilter end,
		function(v) db.spawns.levelFilter = v ns.Spawns:Invalidate() ns.Pins:Refresh(true) end,
		"Learned spots for mobs far below you are left off the map. Anything a quest in your log points at is always shown, whatever its level.")
	Cycle(d, L2.x + 16, L2:Next(30), "Hide below:", { { 5, "5 levels" }, { 8, "8 levels" }, { 12, "12 levels" }, { 20, "20 levels" } },
		function() return db.spawns.levelBand end, function(v) db.spawns.levelBand = v ns.Spawns:Invalidate() ns.Pins:Refresh(true) end)
	Check(d, L2.x, L2:Next(), "Quest icons on nameplates", function() return pl.enabled end, function(v) pl.enabled = v Plates() end,
		"A small icon on the nameplate of every mob your quests want: a sword to kill, a bag when it drops something you need. Drawn on your screen only; these are not raid markers.")
	Check(d, L2.x + 16, L2:Next(), "Skull on the mob the guide sends me at", function() return pl.skull end, function(v) pl.skull = v Plates() end)
	Check(d, L2.x + 16, L2:Next(), "Progress under the icon", function() return pl.count end, function(v) pl.count = v Plates() end)
	Cycle(d, L2.x + 16, L2:Next(30), "Icon position:", { { "left", "Left" }, { "right", "Right" }, { "top", "Above" } },
		function() return pl.side end, function(v) pl.side = v Plates() end)
	Cycle(d, L2.x + 16, L2:Next(30), "Icon size:", { { 0.8, "Small" }, { 1, "Normal" }, { 1.3, "Large" }, { 1.6, "Larger" } },
		function() return pl.scale end, function(v) pl.scale = v Plates() end)
	Cycle(d, L2.x, L2:Next(30), "Arrow size:", { { 42, "Small" }, { 54, "Normal" }, { 68, "Large" }, { 88, "Larger" } },
		function() return db.arrow.size end, function(v) db.arrow.size = v ns.Nav:Update() end,
		"The arrow art is drawn at 256 pixels, so it stays sharp at every size here.")
	Check(d, L2.x, L2:Next(), "Sound on arrival", function() return db.arrow.sound end, function(v) db.arrow.sound = v end)
	Check(d, L2.x, L2:Next(), "Point to my corpse when I die", function() return db.arrow.corpse end,
		function(v) db.arrow.corpse = v ns.Nav.corpseCheck = nil ns.Nav:Update() end,
		"After you release your spirit, the arrow leads you back to your body, then returns to your route once you're alive.")
	Cycle(d, L2.x, L2:Next(30), "Arrival distance:", { { 5, "5 yards" }, { 10, "10 yards" }, { 20, "20 yards" }, { 30, "30 yards" } },
		function() return db.arrow.arrival end, function(v) db.arrow.arrival = v end)

	L2:Next(6)
	Heading(d, L2.x, L2:Next(), "Buttons")
	Check(d, L2.x, L2:Next(), "Quest item buttons", function() return db.buttons.items end, function(v) db.buttons.items = v ns.Buttons:Update() end,
		"Usable quest items for your next steps. Keys: Options > Keybindings > AddOns.")
	Check(d, L2.x, L2:Next(), "Target button", function() return db.buttons.target end, function(v) db.buttons.target = v ns.Buttons:Update() end,
		"A TARGET button on the quest item bar that targets the NPC or mob for your next step, using names learned from your quests. Off by default; its key binding (Target next NPC or mob) works even while it's hidden.")
	Check(d, L2.x, L2:Next(), "Lock the button bar", function() return db.buttons.locked end, function(v) db.buttons.locked = v end)

	Heading(d, R2.x, R2:Next(), "Minimap")
	Check(d, R2.x, R2:Next(), "NeverQuest button on the minimap", function() return db.minimapButton.shown end,
		function(v) db.minimapButton.shown = v ns.MinimapButton:Refresh() end,
		"Click: open NeverQuest. Shift+click: tracker. Right-click: quick settings. Drag it around the minimap's edge.")
	Check(d, R2.x, R2:Next(), "Lock the minimap button", function() return db.minimapButton.locked end, function(v) db.minimapButton.locked = v end)
	Check(d, R2.x, R2:Next(), "Show NeverQuest pins on the minimap", function() return db.pins.minimap end, function(v) db.pins.minimap = v ns.Pins:Refresh(true) end)
	Check(d, R2.x, R2:Next(), "Objectives and turn-ins", function() return db.pins.mmQuests end, function(v) db.pins.mmQuests = v ns.Pins:Refresh(true) end,
		"Turn this off if your minimap already shows quest areas.")
	Check(d, R2.x, R2:Next(), "Waypoints", function() return db.pins.mmWaypoints end, function(v) db.pins.mmWaypoints = v ns.Pins:Refresh(true) end)

	R2:Next(6)
	Heading(d, R2.x, R2:Next(), "World map")
	Check(d, R2.x, R2:Next(), "Show waypoints on the world map", function() return db.pins.worldmap end, function(v) db.pins.worldmap = v ns.Pins:Refresh(true) end)
	Check(d, R2.x, R2:Next(), "Route preview of the next guide steps", function() return db.pins.route end, function(v) db.pins.route = v ns.Pins:Refresh(true) end,
		"Numbered pins for the guide's next steps.")
	Check(d, R2.x, R2:Next(), "Lines joining the route steps", function() return db.pins.routeLine end, function(v) db.pins.routeLine = v ns.Pins:Refresh(true) end,
		"The line from where you stand through each numbered step. Off: just the numbered pins.")
	Check(d, R2.x, R2:Next(), "Include turn-ins for unfinished quests", function() return db.pins.routeTurnins end, function(v) db.pins.routeTurnins = v ns.Pins:Refresh(true) end,
		"Off (default): the map route goes to objectives, finished turn-ins and pickups only. On: it also shows where each unfinished quest will be handed in.")
	Cycle(d, R2.x, R2:Next(30), "Line thickness:", { { 1.5, "Thin" }, { 3, "Normal" }, { 5, "Thick" } },
		function() return db.pins.lineWidth end, function(v) db.pins.lineWidth = v ns.Pins:Refresh(true) end)
	Cycle(d, R2.x, R2:Next(30), "Route length:", { { 3, "3 steps" }, { 5, "5 steps" }, { 8, "8 steps" }, { 12, "12 steps" } },
		function() return db.pins.routeSteps end, function(v) db.pins.routeSteps = v ns.Pins:Refresh(true) end)
	Check(d, R2.x, R2:Next(), "Alt+click the map to add a waypoint", function() return db.pins.altClick end, function(v) db.pins.altClick = v end)
	Check(d, R2.x, R2:Next(), "Follow Blizzard map pins (Ctrl+click)", function() return db.nav.adoptMapPins end, function(v) db.nav.adoptMapPins = v end,
		"When you place Blizzard's own map pin, the NeverQuest arrow follows it too.")
	Check(d, R2.x, R2:Next(), "Coordinates on the world map", function() return db.nav.mapCoords end, function(v) db.nav.mapCoords = v ns.Nav.ApplyMapCoords(v) end)
	Check(d, R2.x, R2:Next(), "In-world waypoint marker", function() return db.nav.nativeWaypoint end,
		function(v) db.nav.nativeWaypoint = v ns.Nav.appliedKey = nil ns.Nav:Update() end,
		"Also shows Blizzard's navigation marker and distance in the 3D world. Needed for routes to /way waypoints.")

	R2:Next(6)
	Heading(d, R2.x, R2:Next(), "Quest givers")
	local gv = db.givers
	local function Givers() ns.Pins:Refresh(true) ns.Guide:Refresh() ns.Planner.dirty = true end
	Check(d, R2.x, R2:Next(), "Quest givers on the world map", function() return gv.worldmap end, function(v) gv.worldmap = v Givers() end,
		"\"!\" for quests you can pick up, with the quest's level in its difficulty color. Click one for a waypoint.")
	Check(d, R2.x, R2:Next(), "In any zone I look at, not just mine", function() return gv.otherZones end, function(v) gv.otherZones = v Givers() end)
	Check(d, R2.x, R2:Next(), "Quest givers on the minimap", function() return db.pins.mmGivers end, function(v) db.pins.mmGivers = v Givers() end)
	Check(d, R2.x, R2:Next(), "Show quest levels", function() return gv.levels end, function(v) gv.levels = v Givers() end,
		"The quest's level beside its marker on the world map and the minimap, in its difficulty color.")
	Check(d, R2.x, R2:Next(), "Include gray (low level) quests", function() return gv.gray end, function(v) gv.gray = v Givers() end,
		"Off: only level-appropriate quests (green, yellow and orange) show on the maps. The guide has its own gray setting.")
	Check(d, R2.x, R2:Next(), "Include red (too high) quests", function() return gv.red end, function(v) gv.red = v Givers() end,
		"Quests five or more levels above you. Off, they also stay out of the guide and route.")
	Check(d, R2.x, R2:Next(), "Include daily quests", function() return gv.dailies end, function(v) gv.dailies = v Givers() end)
	Check(d, R2.x, R2:Next(), "Turn-in spots on the world map", function() return gv.turnins end, function(v) gv.turnins = v Givers() end,
		"\"?\" where finished quests are handed in. Blizzard's map may show these already.")
	FitContent(d, L2, R2)
	self.displayOptions = d

	---------------------------------------------------------------- Spawns & Objectives
	local _, sp = Page("spawns", "Spawns & Objectives", "Spawns & Objectives",
		"NeverQuest learns where quest mobs and objectives are while you play. You can mark spots yourself too.")
	local L3, R3 = Column(16), Column(330)
	local sc = db.spawns
	local function Redraw() ns.Spawns:Refresh() ns.Quests:RequestScan() end

	Heading(sp, L3.x, L3:Next(), "Learning")
	Check(sp, L3.x, L3:Next(), "Learn spawns and objective spots", function() return sc.learn end, function(v) sc.learn = v end,
		"Kill credit, quest loot and other objective progress are remembered where they happen.")
	Check(sp, L3.x, L3:Next(), "Also learn from quest mobs nearby", function() return sc.nameplates end, function(v) sc.nameplates = v end,
		"Mobs tied to your quests are remembered when they come close (nameplate, target or mouseover). Works best with enemy nameplates on.")
	Check(sp, L3.x, L3:Next(), "Remember rares and treasures I spot", function() return sc.rares end, function(v) sc.rares = v Redraw() end)
	Check(sp, L3.x, L3:Next(), "Share new spots and marks with my party", function() return sc.share end, function(v) sc.share = v end,
		"Party members running NeverQuest learn your new spots and marks, and you learn theirs. Party sharing must be on too (NeverQuest page).")

	L3:Next(10)
	Heading(sp, L3.x, L3:Next(), "Guide")
	Check(sp, L3.x, L3:Next(), "Arrow goes to the nearest known spawn", function() return sc.aim end, function(v) sc.aim = v Redraw() end,
		"Used when a known spot is closer than the game's quest area. Spots you've just been to are skipped for a few minutes, so the arrow moves on to the next one.")

	L3:Next(10)
	Heading(sp, L3.x, L3:Next(), "Marking spots")
	local how = sp:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	how:SetPoint("TOPLEFT", L3.x + 4, L3:Next(70))
	how:SetWidth(290)
	how:SetJustifyH("LEFT")
	how:SetText("Alt+right-click the world map, type /nq mark (your target, or a name) or /nq mapnote, " ..
		"or set a key under Keybindings > AddOns. Right-click a spot on the world map to forget or remove it.")

	Heading(sp, R3.x, R3:Next(), "Maps")
	Check(sp, R3.x, R3:Next(), "Show on the world map", function() return sc.worldmap end, function(v) sc.worldmap = v ns.Pins:Refresh(true) end)
	Check(sp, R3.x, R3:Next(), "Show on the minimap", function() return sc.minimap end, function(v) sc.minimap = v ns.Pins:Refresh(true) end,
		"Tiny dots for where your quests' mobs, objects and item drops are, and your own marks. Other learned spots and rares stay on the world map.")
	Check(sp, R3.x, R3:Next(), "Include QuestieDB's spots for my quests", function() return sc.library ~= false end, function(v) ns.Spawns:SetLibrary(v) end,
		"Where QuestieDB says the mobs to kill, the mobs and objects that drop your quest items, and the objects to use are, before you've learned them yourself. Not with \"Build my own\".")
	Cycle(sp, R3.x, R3:Next(30), "Dot size:", { { 0.75, "Tiny" }, { 1, "Small" }, { 1.4, "Medium" }, { 1.8, "Large" } },
		function() return sc.dotSize end, function(v) sc.dotSize = v ns.Pins:Refresh(true) end)
	Check(sp, R3.x, R3:Next(), "Show every known spawn, not just my quests", function() return sc.showAll end, function(v) sc.showAll = v Redraw() end,
		"Spots for mobs your current quests don't need are drawn in gray.")
	Check(sp, R3.x, R3:Next(), "Alt+right-click the world map to mark", function() return sc.markClick end, function(v) sc.markClick = v end)

	R3:Next(10)
	Heading(sp, R3.x, R3:Next(), "Your spawn data")
	local stats = sp:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	stats:SetPoint("TOPLEFT", R3.x + 4, R3:Next(40))
	stats:SetWidth(290)
	stats:SetJustifyH("LEFT")
	local function ShowStats() stats:SetText(ns.Spawns:StatsText() .. ".") end
	sp:SetScript("OnShow", ShowStats)
	ns:RegisterMessage("SPAWNS_UPDATED", function() if sp:IsShown() then ShowStats() end end)

	-- Destructive buttons ask for a second click.
	local function ConfirmButton(parent, text, width, action, after)
		local b = Button(parent, text, width, nil)
		b:SetScript("OnClick", function(self)
			if self.armed then
				self.armed = false
				self:SetText(text)
				action()
				if after then after() end
			else
				self.armed = true
				self:SetText("Click again")
				ns.After(4, function() if self.armed then self.armed = false self:SetText(text) end end)
			end
		end)
		return b
	end
	local row = R3:Next(30)
	local exportBtn = Button(sp, "Export...", 100, function() ns.slash.spawns("export") end)
	exportBtn:SetPoint("TOPLEFT", R3.x, row)
	local importBtn = Button(sp, "Import...", 100, function() ns.slash.spawns("import") end)
	importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
	row = R3:Next(30)
	local forgetBtn = ConfirmButton(sp, "Forget learned spots", 150, function() ns.Spawns:Clear("learned") end, ShowStats)
	forgetBtn:SetPoint("TOPLEFT", R3.x, row)
	local marksBtn = ConfirmButton(sp, "Remove all marks", 130, function() ns.Spawns:Clear("marks") end, ShowStats)
	marksBtn:SetPoint("LEFT", forgetBtn, "RIGHT", 8, 0)
	FitContent(sp, L3, R3)
	self.spawnOptions = sp

	---------------------------------------------------------------- Scale & Text
	local _, st = Page("style", "Scale & Text", "Scale & Text",
		"Text and size for every NeverQuest panel. Settings pages like this one keep the game's own text.")
	local L4, R4 = Column(16), Column(330)
	local sty = db.style
	local function Restyle() St:Apply() end

	Heading(st, L4.x, L4:Next(), "Text")
	Cycle(st, L4.x, L4:Next(30), "Font:", St.FONTS, function() return sty.font end, function(v) sty.font = v Restyle() end)
	Cycle(st, L4.x, L4:Next(30), "Text size:", St.TEXT_SIZES, function() return sty.textScale end, function(v) sty.textScale = v Restyle() end,
		"Changes text only; panels grow to fit. Use the sizes on the right to scale whole panels.")
	Cycle(st, L4.x, L4:Next(30), "Outline:", St.OUTLINES, function() return sty.outline end, function(v) sty.outline = v Restyle() end)
	Check(st, L4.x, L4:Next(), "Text shadow", function() return sty.shadow end, function(v) sty.shadow = v Restyle() end)

	L4:Next(10)
	Heading(st, L4.x, L4:Next(), "Positions")
	local resetBtn = ConfirmButton(st, "Reset panel positions", 170, function()
		wipe(ns.db.positions)
		ns:SendMessage("POSITIONS_RESET")
	end)
	resetBtn:SetPoint("TOPLEFT", L4.x, L4:Next(30))

	Heading(st, R4.x, R4:Next(), "Panel sizes")
	Cycle(st, R4.x, R4:Next(30), "Main window:", St.SCALES, function() return db.window.scale end, function(v) db.window.scale = v UI:ApplyScale() end)
	Cycle(st, R4.x, R4:Next(30), "Quest tracker:", St.SCALES, function() return tc.scale end, function(v) tc.scale = v Track() end)
	Cycle(st, R4.x, R4:Next(30), "XP panel:", St.SCALES, function() return db.hud.scale end, function(v) db.hud.scale = v ns.XP:Refresh() end)
	Cycle(st, R4.x, R4:Next(30), "Waypoint arrow:", St.SCALES, function() return db.arrow.scale end, function(v) db.arrow.scale = v ns.Nav:Update() end)
	Cycle(st, R4.x, R4:Next(30), "Quest buttons:", St.SCALES, function() return db.buttons.scale end, function(v) db.buttons.scale = v ns.Buttons:Update() end)
	Cycle(st, R4.x, R4:Next(30), "Minimap pins:", { { 0.5, "Tiny" }, { 0.6, "Small (default)" }, { 0.8, "80%" }, { 1, "100%" }, { 1.25, "125%" }, { 1.5, "150%" } },
		function() return db.pins.mmScale end, function(v) db.pins.mmScale = v ns.Pins:Refresh(true) end)
	Cycle(st, R4.x, R4:Next(30), "World map pins:", St.SCALES, function() return db.pins.wmScale end, function(v) db.pins.wmScale = v ns.Pins:Refresh(true) end)
	FitContent(st, L4, R4)
	self.styleOptions = st

	---------------------------------------------------------------- Register
	if Settings and Settings.RegisterCanvasLayoutCategory then
		local first = self.panels[1]
		local category = Settings.RegisterCanvasLayoutCategory(first.panel, first.name)
		self.pageCategories[first.key] = category
		if Settings.RegisterCanvasLayoutSubcategory then
			for i = 2, #self.panels do
				local page = self.panels[i]
				self.pageCategories[page.key] = Settings.RegisterCanvasLayoutSubcategory(category, page.panel, page.name)
			end
		end
		Settings.RegisterAddOnCategory(category)
		self.category = category
	else
		-- Fallback: each page as its own window, with a button to the next one.
		for i, page in ipairs(self.panels) do
			local panel = page.panel
			panel:SetParent(UIParent)
			panel:SetSize(680, 600)
			panel:SetPoint("CENTER")
			panel:SetFrameStrata("DIALOG")
			ns.ApplyBackdrop(panel, 0.97)
			panel:Hide()
			local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
			close:SetPoint("TOPRIGHT", -2, -2)
			local nextPage = self.panels[i % #self.panels + 1]
			local nextBtn = Button(panel, nextPage.name .. " >", 190, function() panel:Hide() nextPage.panel:Show() end)
			nextBtn:SetPoint("BOTTOMRIGHT", -12, 12)
		end
	end
end

function UI:OpenOptions(pageKey)
	local category = self.pageCategories and self.pageCategories[pageKey or "general"] or self.category
	if category and Settings and Settings.OpenToCategory and category.GetID then
		Settings.OpenToCategory(category:GetID())
	elseif self.panels then
		local page = self.panels[1]
		for _, pg in ipairs(self.panels) do
			if pg.key == pageKey then page = pg end
		end
		page.panel:Show()
	end
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
ns:OnInit(function()
	UI:Create()
	UI:CreateOptions()
	UI:ApplyScale()
	UI:ApplyStyle()
end)
ns:RegisterMessage("STYLE_CHANGED", function() UI:ApplyStyle() UI:Refresh() end)

for _, msg in ipairs({ "GUIDE_UPDATED", "QUESTS_UPDATED", "OFFERS_UPDATED", "RECORDER_UPDATED", "JOURNAL_UPDATED", "PARTY_UPDATED" }) do
	ns:RegisterMessage(msg, function() ns.Debounce("uirefresh", 0.1, function() UI:Refresh() end) end)
end
ns:RegisterMessage("POSITIONS_RESET", function() if UI.frame then UI.frame:RestorePosition() end end)

local function OpenTab(tab)
	return function()
		if not UI.frame then return end
		UI.frame:Show()
		UI:SetTab(tab)
	end
end
ns:AddSlash("guide", OpenTab("guide"), "/nq guide | quests | nearby | journal | guides - open a tab")
ns:AddSlash("quests", OpenTab("quests"))
ns:AddSlash("nearby", OpenTab("nearby"))
ns:AddSlash("guides", OpenTab("guides"))
ns:AddSlash("journal", OpenTab("journal"), "/nq journal - quest history and level splits")
ns:AddSlash("plan", function()
	if not UI.frame then return end
	UI.frame:Show()
	UI:SetTab("guide")
	UI:TogglePlan(true)
end, "/nq plan - your 1-60 leveling plan (browse other races and classes too)")
ns:AddSlash("style", function(rest)
	rest = (rest or ""):lower()
	if rest:match("^zone") then UI:SetStyle("zone")
	elseif rest:match("^opt") or rest:match("^fast") then UI:SetStyle("optimized")
	else UI:SetStyle(ns.Profiles:Style() == "optimized" and "zone" or "optimized") end
end, "/nq style [optimized | zone] - leveling style: optimized 1-60 zone hopping, or zone by zone")
ns:AddSlash("options", function() UI:OpenOptions() end, "/nq options - open settings")
ns:AddSlash("config", function() UI:OpenOptions() end)

-- Minimap AddOns menu (if this client has it).
function NeverQuest_OnAddonCompartmentClick()
	UI:Toggle()
end
