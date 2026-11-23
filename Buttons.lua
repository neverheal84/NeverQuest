-- NeverQuest Buttons: a quest item bar and a "target next" button, both keybindable.
-- Secure buttons can only be reconfigured out of combat, so changes made during a fight wait
-- until it ends.

local ADDON, ns = ...
local B = {}
ns.Buttons = B

local NUM_ITEMS = 4
local SIZE = 28

BINDING_HEADER_NEVERQUEST = "NeverQuest"
_G["BINDING_NAME_CLICK NeverQuestItemButton1:LeftButton"] = "Use quest item 1"
_G["BINDING_NAME_CLICK NeverQuestItemButton2:LeftButton"] = "Use quest item 2"
_G["BINDING_NAME_CLICK NeverQuestTargetButton:LeftButton"] = "Target next NPC or mob"
BINDING_NAME_NEVERQUEST_TOGGLE = "Open or close NeverQuest"
BINDING_NAME_NEVERQUEST_SKIPSTEP = "Skip guide step"
BINDING_NAME_NEVERQUEST_MARKSPAWN = "Mark a spawn where I stand"

---------------------------------------------------------------------------
-- Picking what to show
---------------------------------------------------------------------------
-- Quests with a usable item: guide order first, then nearest.
function B:ItemQuests()
	local list, seen = {}, {}
	for _, s in ipairs(ns.Guide.steps) do
		local e = s.questID and ns.Quests.byID[s.questID]
		if e and e.item and e.item.id and not seen[e.questID] then
			table.insert(list, e)
			seen[e.questID] = true
		end
	end
	local rest = {}
	for _, e in ipairs(ns.Quests.log) do
		if e.item and e.item.id and not seen[e.questID] then table.insert(rest, e) end
	end
	table.sort(rest, function(a, b) return (a.dist or 1e9) < (b.dist or 1e9) end)
	for _, e in ipairs(rest) do table.insert(list, e) end
	-- Your hearthstone, first, while the guide says hearthing is the way back.
	if ns.db.travel.hearthButton and ns.Travel and ns.Travel:HearthPlan() then
		table.insert(list, 1, { questID = 0, hearth = true, title = "Hearth back to hand in quests",
			item = { id = 6948, link = "item:6948" } })
	end
	return list
end

-- Who to target: the NPC for the current step if we know the name, else the mob for the best objective.
function B:TargetName()
	for i, s in ipairs(ns.Guide.steps) do
		if i > 3 then break end
		if s.npc then return s.npc, s end
		local e = s.questID and ns.Quests.byID[s.questID]
		local mob = e and (e.mob or e.dropMob)
		if mob and not e.complete and (s.kind == "objective" or s.kind == "complete") then return mob, s end
	end
	for _, s in ipairs(ns.Guide.steps) do
		local e = s.questID and ns.Quests.byID[s.questID]
		if e and not e.complete and (e.mob or e.dropMob) then return e.mob or e.dropMob, s end
	end
end

---------------------------------------------------------------------------
-- Frames: a slim rounded bar with the logo as its handle, rounded item buttons, and a
-- "Target" pill that says who it targets.
---------------------------------------------------------------------------
local PAD, GAP, LOGO = 5, 4, 16
local PILL_MIN, PILL_MAX = 74, 168

local function HasAtlas(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local PILL_BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 10,
	insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

local function StyleButton(btn)
	btn:SetSize(SIZE, SIZE)
	btn:RegisterForClicks("AnyUp", "AnyDown")
	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetAllPoints()
	btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	if HasAtlas("UI-HUD-ActionBar-IconFrame") then
		-- The game's own rounded action button look.
		local mask = btn:CreateMaskTexture()
		mask:SetAtlas("UI-HUD-ActionBar-IconFrame-Mask", false)
		mask:SetPoint("TOPLEFT", -1, 1)
		mask:SetPoint("BOTTOMRIGHT", 1, -1)
		btn.icon:AddMaskTexture(mask)
		btn.mask = mask
		local border = btn:CreateTexture(nil, "OVERLAY")
		border:SetAtlas("UI-HUD-ActionBar-IconFrame", false)
		border:SetPoint("TOPLEFT", -2, 2)
		border:SetPoint("BOTTOMRIGHT", 2, -2)
		btn.border = border
		local hl = btn:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover", false)
		hl:SetPoint("TOPLEFT", -2, 2)
		hl:SetPoint("BOTTOMRIGHT", 2, -2)
		local pushed = btn:CreateTexture(nil, "OVERLAY", nil, 2)
		pushed:SetAtlas("UI-HUD-ActionBar-IconFrame-Down", false)
		pushed:SetPoint("TOPLEFT", -2, 2)
		pushed:SetPoint("BOTTOMRIGHT", 2, -2)
		btn:SetPushedTexture(pushed)
	else
		local bg = btn:CreateTexture(nil, "BACKGROUND")
		bg:SetPoint("TOPLEFT", -1, 1)
		bg:SetPoint("BOTTOMRIGHT", 1, -1)
		bg:SetColorTexture(0, 0, 0, 0.8)
		local hl = btn:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.18)
		local pushed = btn:CreateTexture(nil, "OVERLAY")
		pushed:SetAllPoints()
		pushed:SetColorTexture(0, 0, 0, 0.35)
		btn:SetPushedTexture(pushed)
	end
	btn.count = btn:CreateFontString(nil, "OVERLAY", "NeverQuestFontNumber")
	btn.count:SetPoint("BOTTOMRIGHT", -1, 1)
	btn.hotkey = btn:CreateFontString(nil, "OVERLAY", "NeverQuestFontSmallGray")
	btn.hotkey:SetPoint("TOPRIGHT", -1, -2)
end

local function HotkeyText(binding)
	local key = GetBindingKey(binding)
	if not key then return "" end
	return GetBindingText and GetBindingText(key, true) or key
end

local function BarTooltip(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_TOP")
	GameTooltip:AddLine("NeverQuest buttons")
	GameTooltip:AddLine("Quest items for your next steps, and a Target button for the next NPC or mob.", 1, 1, 1, true)
	GameTooltip:AddLine("Drag the logo to move the bar. Keys: Esc > Options > Keybindings > AddOns > NeverQuest. /nq buttons hides it.", 0.7, 0.7, 0.7, true)
	ns.TipShow(false)
end

local function CreateBar()
	local bar = CreateFrame("Frame", "NeverQuestButtonBar", UIParent, "BackdropTemplate")
	bar:SetSize(PAD * 2 + LOGO + 6 + SIZE, SIZE + PAD * 2)
	bar:SetFrameStrata("MEDIUM")
	bar:SetBackdrop(PILL_BACKDROP)
	bar:SetBackdropColor(0.04, 0.05, 0.08, 0.72)
	bar:SetBackdropBorderColor(0.55, 0.45, 0.2, 0.8)
	ns.MakeMovable(bar, "buttons", function() return ns.db.buttons.locked or InCombatLockdown() end,
		{ "BOTTOM", UIParent, "BOTTOM", 0, 190 })

	-- The logo is the handle.
	local logo = bar:CreateTexture(nil, "ARTWORK")
	logo:SetTexture(ns.ICON)
	logo:SetTexCoord(0.06, 0.94, 0.06, 0.94)
	logo:SetSize(LOGO, LOGO)
	logo:SetPoint("LEFT", PAD, 0)
	logo:SetAlpha(0.85)
	bar.logo = logo
	local div = bar:CreateTexture(nil, "ARTWORK")
	div:SetColorTexture(1, 1, 1, 0.12)
	div:SetSize(1, SIZE - 6)
	div:SetPoint("LEFT", logo, "RIGHT", 4, 0)
	bar:SetScript("OnEnter", function(self) logo:SetAlpha(1) BarTooltip(self) end)
	bar:SetScript("OnLeave", function() logo:SetAlpha(0.85) GameTooltip_Hide() end)
	bar.first = PAD + LOGO + 6

	bar.items = {}
	for i = 1, NUM_ITEMS do
		local btn = CreateFrame("Button", "NeverQuestItemButton" .. i, bar, "SecureActionButtonTemplate")
		StyleButton(btn)
		btn:SetPoint("LEFT", bar.first + (i - 1) * (SIZE + GAP), 0)
		btn:SetAttribute("type", "item")
		btn.cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
		btn.cooldown:SetAllPoints(btn.icon)
		btn:SetScript("OnEnter", function(self)
			if not self.quest then return end
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			if self.quest.logIndex then
				GameTooltip:SetQuestLogSpecialItem(self.quest.logIndex)
			else
				GameTooltip:SetHyperlink(self.quest.item.link)
			end
			GameTooltip:AddLine("For: " .. self.quest.title, 0.5, 0.8, 1, true)
			ns.TipShow(nil, true)
		end)
		btn:SetScript("OnLeave", GameTooltip_Hide)
		btn:Hide()
		bar.items[i] = btn
	end

	-- Target pill: magnifying glass, a small "Target" caption and the name.
	local t = CreateFrame("Button", "NeverQuestTargetButton", bar, "SecureActionButtonTemplate, BackdropTemplate")
	t:SetSize(PILL_MIN, SIZE)
	t:RegisterForClicks("AnyUp", "AnyDown")
	t:SetAttribute("type", "macro")
	t:SetBackdrop(PILL_BACKDROP)
	t:SetBackdropColor(0.12, 0.13, 0.18, 0.95)
	t:SetBackdropBorderColor(0.4, 0.4, 0.45, 0.9)
	t.icon = t:CreateTexture(nil, "ARTWORK")
	t.icon:SetAtlas("common-search-magnifyingglass", false)
	t.icon:SetSize(14, 14)
	t.icon:SetPoint("LEFT", 8, 0)
	t.caption = t:CreateFontString(nil, "OVERLAY", "NeverQuestFontTiny")
	t.caption:SetPoint("TOPLEFT", t.icon, "TOPRIGHT", 6, 5)
	t.caption:SetText("TARGET")
	t.label = t:CreateFontString(nil, "OVERLAY", "NeverQuestFontHighlight")
	t.label:SetPoint("BOTTOMLEFT", t.icon, "BOTTOMRIGHT", 6, -4)
	t.label:SetJustifyH("LEFT")
	t.label:SetWordWrap(false)
	t.hotkey = t:CreateFontString(nil, "OVERLAY", "NeverQuestFontSmallGray")
	t.hotkey:SetPoint("TOPRIGHT", -5, -4)
	local hl = t:CreateTexture(nil, "HIGHLIGHT")
	hl:SetPoint("TOPLEFT", 3, -3)
	hl:SetPoint("BOTTOMRIGHT", -3, 3)
	hl:SetColorTexture(1, 1, 1, 0.08)
	t:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Target: " .. (self.targetName or "nothing yet"))
		if self.forStep then GameTooltip:AddLine("For: " .. self.forStep, 0.5, 0.8, 1, true) end
		local key = HotkeyText("CLICK NeverQuestTargetButton:LeftButton")
		GameTooltip:AddLine(key ~= "" and ("Click or press " .. key .. " to target it.") or
			"Click to target it. Bind a key: Esc > Options > Keybindings > AddOns > NeverQuest.", 0.7, 0.7, 0.7, true)
		ns.TipShow()
	end)
	t:SetScript("OnLeave", GameTooltip_Hide)
	t:Hide()
	bar.target = t
	return bar
end

-- The pill grows with the name, within limits; long names are cut.
local function SizePill(t)
	local w = t.label.GetStringWidth and ns.Num(t.label:GetStringWidth()) or 0
	local width = math.max(PILL_MIN, math.min(PILL_MAX, 8 + 14 + 6 + (w or 0) + 12 + (t.hotkey:GetText() ~= "" and 14 or 0)))
	t:SetWidth(width)
	t.label:SetWidth(width - 8 - 14 - 6 - 8)
	return width
end
B.SizePill = SizePill

---------------------------------------------------------------------------
-- Updating (secure attributes only out of combat)
---------------------------------------------------------------------------
function B:Update()
	local bar = self.bar
	if not bar or not ns.ready then return end
	if InCombatLockdown() then
		self.pending = true
		self:UpdateCooldowns()
		return
	end
	self.pending = false
	local cfg = ns.db.buttons
	bar:SetScale(cfg.scale or 1)

	local shown = 0
	local quests = cfg.items and self:ItemQuests() or {}
	for i, btn in ipairs(bar.items) do
		local e = quests[i]
		if e then
			btn.quest = e
			btn:SetAttribute("item", "item:" .. e.item.id)
			btn.icon:SetTexture(e.item.icon or C_Item.GetItemIconByID(e.item.id))
			local count = e.item.charges and e.item.charges > 1 and e.item.charges or C_Item.GetItemCount(e.item.id)
			btn.count:SetText((count and count > 1) and count or "")
			btn.hotkey:SetText(i <= 2 and HotkeyText("CLICK NeverQuestItemButton" .. i .. ":LeftButton") or "")
			btn:Show()
			shown = shown + 1
		else
			btn.quest = nil
			btn:SetAttribute("item", nil)
			btn:Hide()
		end
	end

	-- The TARGET pill. With it hidden, its key binding (if you set one) still targets the
	-- next NPC or mob.
	local t = bar.target
	local width
	local name, step = nil, nil
	local bound = GetBindingKey and GetBindingKey("CLICK NeverQuestTargetButton:LeftButton") ~= nil
	if cfg.target or bound then name, step = self:TargetName() end
	if name and not name:find("[\r\n]") then
		t.targetName = name
		t.forStep = step and step.title or nil
		t:SetAttribute("macrotext", "/targetexact " .. name)
		t.label:SetText(name)
		t.hotkey:SetText(HotkeyText("CLICK NeverQuestTargetButton:LeftButton"))
		if cfg.target then
			local pill = SizePill(t)
			t:ClearAllPoints()
			t:SetPoint("LEFT", bar.first + shown * (SIZE + GAP), 0)
			t:Show()
			width = bar.first + shown * (SIZE + GAP) + pill + PAD
			shown = shown + 1
		else
			t:Hide()
		end
	else
		t.targetName = nil
		t:SetAttribute("macrotext", nil)
		t:Hide()
	end

	bar:SetWidth(width or (bar.first + math.max(1, shown) * (SIZE + GAP) - GAP + PAD))
	bar:SetShown(shown > 0)
	self:UpdateCooldowns()
end

function B:UpdateCooldowns()
	if not self.bar then return end
	for _, btn in ipairs(self.bar.items) do
		local e = btn.quest
		if e and e.hearth and btn:IsShown() then
			local fn = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
			local ok, start, duration = pcall(fn, 6948)
			start, duration = ok and ns.Num(start), ok and ns.Num(duration)
			if start and duration and duration > 0 then btn.cooldown:SetCooldown(start, duration) else btn.cooldown:Clear() end
		elseif e and e.logIndex and btn:IsShown() then
			local start, duration, enable = GetQuestLogSpecialItemCooldown(e.logIndex)
			start, duration = ns.Num(start), ns.Num(duration)
			if start and duration and duration > 0 and enable ~= 0 then
				btn.cooldown:SetCooldown(start, duration)
			else
				btn.cooldown:Clear()
			end
		end
	end
end

ns:OnInit(function()
	B.bar = CreateBar()
	B.bar:Hide()
end)

for _, msg in ipairs({ "QUESTS_UPDATED", "GUIDE_UPDATED" }) do
	ns:RegisterMessage(msg, function() ns.Debounce("buttons", 0.3, function() B:Update() end) end)
end
ns:RegisterEvent("PLAYER_REGEN_ENABLED", function() if B.pending then B:Update() end end)
ns:RegisterEvent("BAG_UPDATE_COOLDOWN", function() B:UpdateCooldowns() end)
ns:RegisterEvent("BAG_UPDATE_DELAYED", function() ns.Debounce("buttons", 0.3, function() B:Update() end) end)
ns:RegisterEvent("UPDATE_BINDINGS", function() ns.Debounce("buttons", 0.3, function() B:Update() end) end)
ns:RegisterMessage("POSITIONS_RESET", function()
	if B.bar and not InCombatLockdown() then B.bar:RestorePosition() end
end)

ns:AddSlash("buttons", function(arg)
	local cfg = ns.db.buttons
	arg = (arg or ""):lower():gsub("%s+", "")
	if arg == "target" then
		cfg.target = not cfg.target
		B:Update()
		ns.Print(cfg.target and "TARGET button shown on the quest item bar." or "TARGET button hidden (its key binding still works if you set one).")
		return
	end
	local on = not cfg.items
	cfg.items = on
	B:Update()
	ns.Print(on and "quest item buttons on." or "quest item buttons off.")
end, "/nq buttons [target] - turn the quest item bar on or off, or show/hide its TARGET button")

-- 1.12.1: the TARGET button is off by default; switch it off once for saved settings too.
ns:OnInit(function()
	local done = ns.db.migrated
	if not done.targetButtonOff then
		done.targetButtonOff = true
		ns.db.buttons.target = false
	end
end)
