-- NeverQuest Buttons: a quest item bar and a "target next" button, both keybindable.
-- Secure buttons can only be reconfigured out of combat, so changes made during a fight wait
-- until it ends.

local ADDON, ns = ...
local B = {}
ns.Buttons = B

local NUM_ITEMS = 4
local SIZE = 34

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
-- Frames
---------------------------------------------------------------------------
local function StyleButton(btn)
	btn:SetSize(SIZE, SIZE)
	btn:RegisterForClicks("AnyUp", "AnyDown")
	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetPoint("TOPLEFT", 2, -2)
	btn.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local bg = btn:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.7)
	local hl = btn:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.2)
	local pushed = btn:CreateTexture(nil, "OVERLAY")
	pushed:SetAllPoints()
	pushed:SetColorTexture(0, 0, 0, 0.35)
	btn:SetPushedTexture(pushed)
	btn.count = btn:CreateFontString(nil, "OVERLAY", "NeverQuestFontNumber")
	btn.count:SetPoint("BOTTOMRIGHT", -2, 2)
	btn.hotkey = btn:CreateFontString(nil, "OVERLAY", "NeverQuestFontSmall")
	btn.hotkey:SetPoint("TOPRIGHT", -2, -2)
end

local function HotkeyText(binding)
	local key = GetBindingKey(binding)
	if not key then return "" end
	return GetBindingText and GetBindingText(key, true) or key
end

local function CreateBar()
	local bar = CreateFrame("Frame", "NeverQuestButtonBar", UIParent, "BackdropTemplate")
	bar:SetSize(16 + (SIZE + 4) * (NUM_ITEMS + 1) + 4, SIZE + 10)
	bar:SetFrameStrata("MEDIUM")
	ns.ApplyBackdrop(bar, 0.6)
	ns.MakeMovable(bar, "buttons", function() return ns.db.buttons.locked or InCombatLockdown() end,
		{ "BOTTOM", UIParent, "BOTTOM", 0, 190 })

	local grip = bar:CreateTexture(nil, "ARTWORK")
	grip:SetAtlas("QuestNormal", false)
	grip:SetSize(12, 18)
	grip:SetPoint("LEFT", 4, 0)
	bar:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("NeverQuest buttons")
		GameTooltip:AddLine("Quest items for your next steps, plus a button that targets the next NPC or mob.", 1, 1, 1, true)
		GameTooltip:AddLine("Drag the edge to move. Set keys in Options > Keybindings > AddOns.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	bar:SetScript("OnLeave", GameTooltip_Hide)

	bar.items = {}
	for i = 1, NUM_ITEMS do
		local btn = CreateFrame("Button", "NeverQuestItemButton" .. i, bar, "SecureActionButtonTemplate")
		StyleButton(btn)
		btn:SetPoint("LEFT", 18 + (i - 1) * (SIZE + 4), 0)
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
			GameTooltip:Show()
		end)
		btn:SetScript("OnLeave", GameTooltip_Hide)
		btn:Hide()
		bar.items[i] = btn
	end

	local t = CreateFrame("Button", "NeverQuestTargetButton", bar, "SecureActionButtonTemplate")
	StyleButton(t)
	t:SetAttribute("type", "macro")
	t.icon:SetAtlas("common-search-magnifyingglass", false)
	t.icon:SetTexCoord(0, 1, 0, 1)
	t.label = t:CreateFontString(nil, "OVERLAY", "NeverQuestFontNormalSmall")
	t.label:SetPoint("BOTTOM", t, "TOP", 0, 6)
	t.label:SetWidth(160)
	t.label:SetWordWrap(false)
	t:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Target: " .. (self.targetName or "nothing yet"))
		if self.forStep then GameTooltip:AddLine(self.forStep, 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	t:SetScript("OnLeave", GameTooltip_Hide)
	t:Hide()
	bar.target = t
	return bar
end

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

	local t = bar.target
	local name, step = nil, nil
	if cfg.target then name, step = self:TargetName() end
	if name and not name:find("[\r\n]") then
		t.targetName = name
		t.forStep = step and step.title or nil
		t:SetAttribute("macrotext", "/targetexact " .. name)
		t.label:SetText(name)
		t.hotkey:SetText(HotkeyText("CLICK NeverQuestTargetButton:LeftButton"))
		t:ClearAllPoints()
		t:SetPoint("LEFT", 18 + shown * (SIZE + 4), 0)
		t:Show()
		shown = shown + 1
	else
		t.targetName = nil
		t:SetAttribute("macrotext", nil)
		t:Hide()
	end

	bar:SetWidth(22 + shown * (SIZE + 4))
	bar:SetShown(shown > 0)
	self:UpdateCooldowns()
end

function B:UpdateCooldowns()
	if not self.bar then return end
	for _, btn in ipairs(self.bar.items) do
		local e = btn.quest
		if e and e.logIndex and btn:IsShown() then
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

ns:AddSlash("buttons", function()
	local cfg = ns.db.buttons
	local on = not (cfg.items or cfg.target)
	cfg.items, cfg.target = on, on
	B:Update()
	ns.Print(on and "quest item and target buttons on." or "quest item and target buttons off.")
end, "/nq buttons - turn the quest item and target buttons on or off")
