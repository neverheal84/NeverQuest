-- NeverQuest Drops: a window for the things you still have to collect. Where the TARGET button
-- answers "who am I looking for", this answers "what am I still short of, and what drops it".
--
-- Everything here comes from your own game client: the quest log says what you need and how far
-- along you are, your bags supply the icon once you hold one, and the mob names come from the
-- spots NeverQuest has watched you earn credit at. Nothing ships with the addon.

local ADDON, ns = ...
local D = {}
ns.Drops = D

local PAD, INDENT, ICON = 6, 14, 14
local MAX_SOURCES = 3       -- mob names listed on the source line before "and N more"

-- Objective kinds that mean "collect some number of these". A kill objective is the TARGET
-- button's job, not this window's.
local COLLECT = { item = true, object = true }

local function Cfg() return ns.db.drops end

---------------------------------------------------------------------------
-- What you are short of
---------------------------------------------------------------------------
-- Name -> icon and link for the quest items already in your bags, so a thing you hold one of
-- shows its real icon. Rebuilt only when the bags change.
local bagCache, bagDirty = {}, true

local function BagIndex()
	if not bagDirty then return bagCache end
	bagDirty = false
	wipe(bagCache)
	local each = ns.Upkeep and ns.Upkeep.EachBagItem
	if not each then return bagCache end
	each(function(bag, slot, info)
		local name = info.hyperlink and info.hyperlink:match("%[(.-)%]")
		if name and not bagCache[name] then
			bagCache[name] = { icon = info.iconFileID, link = info.hyperlink, id = info.itemID }
		end
	end)
	return bagCache
end

function D:ForgetBags() bagDirty = true end

-- Mob names per objective, and the nearest learned spot for it, from what NeverQuest has
-- watched you do. Built in one pass over the spawn index rather than once per row.
local function Sources()
	local byObj = {}
	if not ns.Spawns or not ns.db.spawns.learn then return byObj end
	local idx = ns.Spawns:Index()
	for _, ent in ipairs(idx.entries or {}) do
		if ent.kind == "npc" and ent.name then
			for _, r in ipairs(ent.refs or {}) do
				if r.i then
					local key = r.q .. ":" .. r.i
					local list = byObj[key]
					if not list then list = {} byObj[key] = list end
					local seen = false
					for _, n in ipairs(list) do if n == ent.name then seen = true break end end
					if not seen then table.insert(list, ent.name) end
				end
			end
		end
	end
	return byObj
end

-- Nearest known spot for one objective of one quest.
local function NearestSpot(questID, index)
	if not ns.Spawns then return nil end
	local list = ns.Spawns:Index().byQuest[questID]
	if not list then return nil end
	local best, bestD
	for _, p in ipairs(list) do
		local wanted = false
		for _, r in ipairs(p.ent and p.ent.refs or {}) do
			if r.q == questID and r.i == index then wanted = true break end
		end
		if wanted then
			local d = ns.Nav.Distance(p.m, p.x, p.y)
			if d and (not bestD or d < bestD) then best, bestD = p, d end
		end
	end
	if not best then return nil end
	return { m = best.m, x = best.x, y = best.y, dist = bestD, label = best.ent.name }
end

-- Every unfinished collect-this objective in your log, nearest known source first.
function D:Items()
	local out = {}
	if not ns.Quests then return out end
	local bags, sources = BagIndex(), Sources()
	for _, e in ipairs(ns.Quests.log) do
		if not e.failed and not e.complete then
			for i, o in ipairs(C_QuestLog.GetQuestObjectives(e.questID) or {}) do
				if not o.finished and COLLECT[o.type] and o.text and o.text ~= "" and not ns.IsSecret(o.text) then
					local need = ns.Num(o.numRequired) or 0
					local have = ns.Num(o.numFulfilled) or 0
					local name = ns.Spawns and ns.Spawns.ObjectiveName(o.text) or o.text
					local bag = name and bags[name]
					local spot = NearestSpot(e.questID, i)
					table.insert(out, {
						questID = e.questID, index = i, quest = e.title, e = e,
						name = name or o.text, text = o.text, kind = o.type,
						have = have, need = need,
						icon = bag and bag.icon, link = bag and bag.link,
						sources = sources[e.questID .. ":" .. i],
						spot = spot, dist = spot and spot.dist,
					})
				end
			end
		end
	end
	local sort = Cfg().sort
	table.sort(out, function(a, b)
		if sort == "progress" then
			local pa = a.need > 0 and a.have / a.need or 0
			local pb = b.need > 0 and b.have / b.need or 0
			if pa ~= pb then return pa > pb end
		elseif sort == "remaining" then
			local ra, rb = a.need - a.have, b.need - b.have
			if ra ~= rb then return ra < rb end
		end
		local da, db = a.dist or 1e9, b.dist or 1e9
		if da ~= db then return da < db end
		return (a.name or "") < (b.name or "")
	end)
	return out
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function SourceText(d)
	local bits = {}
	if d.sources and #d.sources > 0 then
		local names = {}
		for i = 1, math.min(MAX_SOURCES, #d.sources) do table.insert(names, d.sources[i]) end
		local extra = #d.sources - #names
		table.insert(bits, "from " .. table.concat(names, ", ") .. (extra > 0 and (" and " .. extra .. " more") or ""))
	elseif d.kind == "object" then
		table.insert(bits, "found in the world")
	end
	if d.dist then table.insert(bits, ns.Yards(d.dist)) end
	if #bits == 0 then return nil end
	return table.concat(bits, "  ")
end

local function LinkIt(d)
	if not d.link then return end
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		ChatFrameUtil.InsertLink(d.link)
	elseif ChatEdit_InsertLink then
		ChatEdit_InsertLink(d.link)
	end
end

local function PointAt(d)
	if not d.spot then
		ns.Print("no spot learned for " .. d.name .. " yet. It gets remembered the first time one drops for you.")
		return
	end
	ns.Guide:Pin({ key = "drop:" .. d.questID .. ":" .. d.index, m = d.spot.m, x = d.spot.x, y = d.spot.y,
		title = d.name .. (d.spot.label and (" (" .. d.spot.label .. ")") or ""), questID = d.questID })
end

local function RowClick(row, button)
	local d = row.data
	if not d then return end
	if button == "RightButton" then
		D:RowMenu(row, d)
	elseif IsShiftKeyDown() then
		LinkIt(d)
	else
		PointAt(d)
	end
end

local function RowEnter(row)
	local d = row.data
	if not d then return end
	GameTooltip:SetOwner(row, "ANCHOR_LEFT")
	GameTooltip:AddLine(d.name, 1, 0.82, 0, true)
	GameTooltip:AddLine(d.text, 1, 1, 1, true)
	GameTooltip:AddLine(d.quest or "", 0.7, 0.7, 0.7, true)
	if d.sources and #d.sources > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Dropped by, going on what you have seen:", 0.6, 0.85, 1)
		for i, n in ipairs(d.sources) do
			if i > 8 then GameTooltip:AddLine("...and " .. (#d.sources - 8) .. " more", 0.6, 0.6, 0.6) break end
			GameTooltip:AddLine("- " .. n, 1, 1, 1)
		end
	elseif d.kind == "item" then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("No source learned yet. The first one that drops for you is remembered.", 0.6, 0.6, 0.6, true)
	end
	if d.spot then GameTooltip:AddLine("Nearest spot you know: " .. ns.Yards(d.spot.dist), 0.5, 1, 0.5) end
	GameTooltip:AddLine(d.spot and "Click: point the arrow.  Shift+click: link.  Right-click: options."
		or "Shift+click: link.  Right-click: options.", 0.5, 0.8, 1, true)
	ns.TipShow()
end

local function OpenSettings()
	if ns.UI and ns.UI.OpenOptions then ns.UI:OpenOptions("tracker") end
end

function D:RowMenu(owner, d)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(d.name)
		if d.spot then
			root:CreateButton("Point the arrow here", function() PointAt(d) end)
		end
		root:CreateButton("Point the arrow at the quest", function()
			local e = ns.Quests.byID[d.questID]
			if e and ns.Tracker then ns.Tracker:Point(e) end
		end)
		if d.link then
			root:CreateButton("Link it in chat", function() LinkIt(d) end)
		end
		if d.sources and #d.sources > 0 then
			root:CreateDivider()
			root:CreateButton("Forget the spots for this", function()
				for _, n in ipairs(d.sources) do ns.Spawns:ForgetName(n) end
				D:Refresh()
			end)
		end
		root:CreateDivider()
		root:CreateButton("Drops settings...", OpenSettings)
	end)
end

function D:Row(i)
	local f = self.frame
	local row = f.rows[i]
	if row then return row end
	row = CreateFrame("Button", nil, f.content)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON, ICON)
	row.icon:SetPoint("LEFT", 0, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.right = row:CreateFontString(nil, "OVERLAY", "NeverQuestFontSmall")
	row.right:SetPoint("RIGHT", -2, 0)
	row.right:SetJustifyH("RIGHT")
	row.text = row:CreateFontString(nil, "OVERLAY", "NeverQuestFontHighlight")
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
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

local function ProgressColor(have, need)
	if need <= 0 then return 1, 1, 1 end
	local p = have / need
	if p >= 1 then return 0.4, 1, 0.4 end
	if p >= 0.5 then return 1, 0.9, 0.4 end
	return 1, 1, 1
end

-- Lays one line out. A row is either the item itself (icon, name, count) or the gray line
-- under it saying where it comes from, and every part that differs is set here, because rows
-- are reused for both. Returns the height used.
function D:Place(row, d, kind, y, h, text)
	local f = self.frame
	row.data = d
	row.kind = kind
	if kind == "item" then
		row.icon:SetTexture(d.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
		row.icon:Show()
		row.text:ClearAllPoints()
		row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
		row.text:SetPoint("RIGHT", row.right, "LEFT", -4, 0)
		row.text:SetFontObject("NeverQuestFontHighlight")
		row.text:SetText(d.name)
		row.right:SetText(d.need > 0 and (d.have .. "/" .. d.need) or "")
		row.right:SetTextColor(ProgressColor(d.have, d.need))
	else
		row.icon:Hide()
		row.text:ClearAllPoints()
		row.text:SetPoint("LEFT", INDENT, 0)
		row.text:SetPoint("RIGHT", row.right, "LEFT", -4, 0)
		row.text:SetFontObject("NeverQuestFontSmallGray")
		row.text:SetText(text or "")
		row.right:SetText("")
	end
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y)
	row:SetPoint("RIGHT", f.content, "RIGHT", 0, 0)
	row:SetHeight(h)
	row:Show()
	return h
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
function D:Create()
	if self.frame then return self.frame end
	local cfg = Cfg()
	local f = CreateFrame("Frame", "NeverQuestDrops", UIParent, "BackdropTemplate")
	f:SetSize(cfg.width or 250, 60)
	f:SetFrameStrata("LOW")
	f.rows = {}
	ns.MakeMovable(f, "drops", function() return Cfg().locked end, { "TOPRIGHT", UIParent, "TOPRIGHT", -40, -520 }, { top = true })

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
			D:HeaderMenu(self)
		else
			Cfg().collapsed = not Cfg().collapsed
			D:Refresh()
		end
	end)
	header:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("NeverQuest drops")
		GameTooltip:AddLine("What you still have to collect, and what drops it.", 0.8, 0.8, 0.8, true)
		GameTooltip:AddLine("Click: collapse or expand.  Right-click: options.  Drag: move.", 0.5, 0.8, 1, true)
		ns.TipShow(false)
	end)
	header:SetScript("OnLeave", GameTooltip_Hide)
	f.header = header

	f.content = CreateFrame("Frame", nil, f)
	f.content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
	f.content:SetPoint("RIGHT", -PAD, 0)
	f.content:SetHeight(1)

	f.empty = f:CreateFontString(nil, "OVERLAY", "NeverQuestFontSmallGray")
	f.empty:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, 0)
	f.empty:SetPoint("RIGHT", f.content, "RIGHT", 0, 0)
	f.empty:SetJustifyH("LEFT")
	f.empty:SetWordWrap(true)
	self.frame = f
	return f
end

function D:HeaderMenu(owner)
	local cfg = Cfg()
	local function Sort(value, label)
		return { text = label, checked = cfg.sort == value, func = function() cfg.sort = value D:Refresh() end }
	end
	ns.ShowMenu({
		{ text = "Drops", isTitle = true, notCheckable = true },
		Sort("progress", "Closest to done first"),
		Sort("remaining", "Fewest left first"),
		Sort("distance", "Nearest first"),
		{ text = "Show where it drops", checked = cfg.showSource,
		  func = function() cfg.showSource = not cfg.showSource D:Refresh() end },
		{ text = "Lock in place", checked = cfg.locked,
		  func = function() cfg.locked = not cfg.locked end },
		{ text = "Hide this window", notCheckable = true, func = function()
			cfg.shown = false
			D:Refresh()
			ns.Print("drops window hidden. /nq drops brings it back.")
		end },
		{ text = "Settings", notCheckable = true, func = function() ns.UI:Open("options") end },
	}, owner)
end

function D:Refresh()
	if not ns.ready then return end
	local cfg = Cfg()
	if not cfg.shown then
		if self.frame then self.frame:Hide() end
		return
	end
	local f = self:Create()
	f:SetScale(cfg.scale or 1)
	f:SetWidth(cfg.width or 250)
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
	local list = self:Items()
	f.header.text:SetText(cfg.collapsed and "+ Drops" or "Drops")
	f.header.count:SetText(#list > 0 and (#list .. (#list == 1 and " item" or " items")) or "")

	local y, used, hidden = 0, 0, 0
	local maxH = (cfg.maxHeight or 420) - headerH - PAD * 2
	if not cfg.collapsed then
		for _, d in ipairs(list) do
			local lineH = St:LineHeight("NeverQuestFontHighlight")
			local sub = cfg.showSource and SourceText(d) or nil
			local subH = sub and St:LineHeight("NeverQuestFontSmallGray") or 0
			if y + lineH + subH > maxH then
				hidden = hidden + 1
			else
				used = used + 1
				y = y + self:Place(self:Row(used), d, "item", y, lineH)
				if sub then
					used = used + 1
					y = y + self:Place(self:Row(used), d, "source", y, subH, sub)
				end
			end
		end
	end
	for i = used + 1, #f.rows do
		f.rows[i]:Hide()
		f.rows[i].data = nil
	end

	local note = ""
	if #list == 0 then
		note = cfg.collapsed and "" or "Nothing to collect right now. Quest items you need show up here."
	elseif hidden > 0 then
		note = "+" .. hidden .. " more (raise the height)"
	end
	f.empty:SetText(cfg.collapsed and "" or note)
	local noteH = (note ~= "" and not cfg.collapsed) and (St:LineHeight("NeverQuestFontSmallGray") + 2) or 0
	f.empty:ClearAllPoints()
	f.empty:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y)
	f.empty:SetPoint("RIGHT", f.content, "RIGHT", 0, 0)
	f.content:SetHeight(math.max(1, y + noteH))
	f:SetHeight(PAD + headerH + 4 + y + noteH + PAD)
	if f.KeepTop then f:KeepTop() end
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
local function Redraw() ns.Debounce("drops", 0.2, function() D:Refresh() end) end

for _, msg in ipairs({ "QUESTS_UPDATED", "SPAWNS_UPDATED", "STYLE_CHANGED" }) do
	ns:RegisterMessage(msg, Redraw)
end
ns:RegisterMessage("POSITIONS_RESET", function() if D.frame then D.frame:RestorePosition() end end)
ns:RegisterEvent("BAG_UPDATE_DELAYED", function() D:ForgetBags() Redraw() end)
ns:RegisterEvent("QUEST_LOG_UPDATE", Redraw)
ns:RegisterEvent("PLAYER_LOGIN", Redraw)

function D:Toggle(on)
	local cfg = Cfg()
	if on == nil then on = not cfg.shown end
	cfg.shown = on and true or false
	self:Refresh()
	return cfg.shown
end

BINDING_NAME_NEVERQUEST_TOGGLEDROPS = "Open or close the drops window"

ns:AddSlash("drops", function(rest)
	local cfg = Cfg()
	rest = (rest or ""):lower()
	if rest == "lock" then
		cfg.locked = not cfg.locked
		ns.Print(cfg.locked and "drops window locked." or "drops window unlocked (drag the header to move).")
	elseif rest == "list" then
		local list = D:Items()
		if #list == 0 then
			ns.Print("nothing to collect right now.")
		else
			ns.Print("still to collect:")
			for _, d in ipairs(list) do
				local src = SourceText(d)
				DEFAULT_CHAT_FRAME:AddMessage(string.format("   %s  %d/%d%s", d.name, d.have, d.need,
					src and ("  |cff808080" .. src .. "|r") or ""))
			end
		end
		return
	else
		D:Toggle()
		ns.Print(cfg.shown and "drops window shown." or "drops window hidden.")
	end
	D:Refresh()
end, "/nq drops [lock | list] - show or hide the window of quest items you still have to collect")
