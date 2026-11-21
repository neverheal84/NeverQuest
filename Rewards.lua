-- NeverQuest Rewards: which quest reward is a real upgrade for your class, compared with what
-- you're wearing. Falls back to the highest vendor value when nothing is an upgrade.
--
-- The score is simple on purpose: the stats your class cares about, weighted, plus armor and
-- weapon damage. Good enough to spot "+8 Agility over a gray belt"; not a theorycrafting tool.

local ADDON, ns = ...
local R = {}
ns.Rewards = R

-- Stat weights by class (keys are the game's stat names from C_Item.GetItemStats).
local W = {
	WARRIOR = { STR = 2, AGI = 1, STA = 1.2, AP = 0.5, dps = 3 },
	PALADIN = { STR = 2, INT = 1, STA = 1.2, SPI = 0.3, AP = 0.5, dps = 2.5 },
	HUNTER  = { AGI = 2, INT = 0.5, STA = 1, AP = 0.5, dps = 2, ranged = 3 },
	ROGUE   = { AGI = 2, STR = 1, STA = 1, AP = 0.5, dps = 3 },
	PRIEST  = { INT = 2, SPI = 1.5, STA = 1, SP = 1.2, dps = 0.2 },
	MAGE    = { INT = 2, SPI = 1, STA = 1, SP = 1.2, dps = 0.2 },
	WARLOCK = { INT = 1.8, SPI = 0.8, STA = 1.3, SP = 1.2, dps = 0.2 },
	DRUID   = { INT = 1.2, STR = 1, AGI = 1, SPI = 1, STA = 1, SP = 0.8, AP = 0.4, dps = 1 },
	SHAMAN  = { INT = 1.5, STR = 1, AGI = 0.6, SPI = 0.6, STA = 1, SP = 0.8, AP = 0.4, dps = 2 },
}
local STAT_KEYS = {
	ITEM_MOD_STRENGTH_SHORT = "STR", ITEM_MOD_AGILITY_SHORT = "AGI", ITEM_MOD_STAMINA_SHORT = "STA",
	ITEM_MOD_INTELLECT_SHORT = "INT", ITEM_MOD_SPIRIT_SHORT = "SPI", ITEM_MOD_ATTACK_POWER_SHORT = "AP",
	ITEM_MOD_SPELL_POWER_SHORT = "SP", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SP", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "SP",
	ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps", RESISTANCE0_NAME = "armor",
}
local STAT_LABEL = { STR = "Strength", AGI = "Agility", STA = "Stamina", INT = "Intellect", SPI = "Spirit",
	AP = "Attack Power", SP = "Spell Power", dps = "damage per second", armor = "Armor" }

-- Armor each class can wear (subclass IDs: 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield),
-- with the level the heavier type opens up.
local ARMOR = {
	WARRIOR = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 }, PALADIN = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 },
	HUNTER = { [1] = 1, [2] = 1, [3] = 40 }, SHAMAN = { [1] = 1, [2] = 1, [3] = 40, [6] = 1 },
	ROGUE = { [1] = 1, [2] = 1 }, DRUID = { [1] = 1, [2] = 1 },
	PRIEST = { [1] = 1 }, MAGE = { [1] = 1 }, WARLOCK = { [1] = 1 },
}
-- Weapon types each class can learn (weapon subclass IDs).
local WEAPONS = {
	WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }, PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
	HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }, ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
	PRIEST = { 4, 10, 15, 19 }, MAGE = { 7, 10, 15, 19 }, WARLOCK = { 7, 10, 15, 19 },
	DRUID = { 4, 5, 10, 13, 15 }, SHAMAN = { 0, 1, 4, 5, 10, 13, 15 },
}
local canUseWeapon = {}
for class, list in pairs(WEAPONS) do
	canUseWeapon[class] = {}
	for _, id in ipairs(list) do canUseWeapon[class][id] = true end
end

-- Equip slot(s) an item goes in; two slots means compare with the weaker of the two.
local SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
	INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

local function Class() return select(2, UnitClass("player")) or "WARRIOR" end

-- Item details, or nil while the game is still loading them.
local function Info(link)
	if not link then return nil end
	local ok, name, _, quality, itemLevel, minLevel, _, _, _, equipLoc, _, sellPrice, classID, subclassID = pcall(C_Item.GetItemInfo, link)
	if not ok or not name then return nil end
	return { name = name, link = link, quality = quality, ilvl = ns.Num(itemLevel) or 0, minLevel = ns.Num(minLevel) or 0,
		equipLoc = equipLoc, sell = ns.Num(sellPrice) or 0, classID = classID, subclassID = subclassID }
end

local function Stats(link)
	local ok, raw = pcall(C_Item.GetItemStats, link)
	local out = {}
	if ok and type(raw) == "table" then
		for k, v in pairs(raw) do
			local key = STAT_KEYS[k]
			if key and ns.Num(v) then out[key] = (out[key] or 0) + v end
		end
	end
	return out
end
R.Stats = Stats

function R.CanUse(info, class, level)
	class, level = class or Class(), level or UnitLevel("player")
	if not info or not info.equipLoc or info.equipLoc == "" or not SLOTS[info.equipLoc] then return false end
	if info.minLevel > level then return false end
	if info.classID == 4 and info.subclassID and info.subclassID > 0 and info.equipLoc ~= "INVTYPE_CLOAK" then
		local from = (ARMOR[class] or {})[info.subclassID]
		if not from or level < from then return false end
	end
	if info.classID == 2 and info.subclassID then
		local allowed = canUseWeapon[class]
		if allowed and not allowed[info.subclassID] then return false end
	end
	return true
end

function R.Score(stats, class, slots)
	local w = W[class or Class()] or W.WARRIOR
	local s = 0
	for k, v in pairs(stats) do
		if k == "dps" then
			s = s + v * ((slots and slots[1] == 18) and (w.ranged or 0.3) or w.dps or 1)
		elseif k == "armor" then
			s = s + v * 0.02
		else
			s = s + v * (w[k] or 0)
		end
	end
	return s
end

-- Compares a reward with what's equipped in its slot(s).
-- Returns { gain, against = equipped link or nil, diff = { key = delta } } or nil if unusable.
function R:Compare(link, class, level)
	local info = Info(link)
	if not info then return nil, true end
	if not R.CanUse(info, class, level) then return nil end
	local slots = SLOTS[info.equipLoc]
	-- Weapons and off-hands depend on what's in your hands now.
	local mainLink = GetInventoryItemLink("player", 16)
	local mainInfo = mainLink and Info(mainLink)
	local twoHanded = mainInfo and mainInfo.equipLoc == "INVTYPE_2HWEAPON"
	if info.equipLoc == "INVTYPE_WEAPON" then
		local lvl = level or UnitLevel("player")
		local c = class or Class()
		local dual = c == "ROGUE" or ((c == "WARRIOR" or c == "HUNTER") and lvl >= 20)
		slots = (dual and not twoHanded) and { 16, 17 } or { 16 }
	elseif slots[1] == 17 and #slots == 1 and twoHanded then
		return nil   -- an off-hand item would mean giving up your two-hander: not a simple upgrade
	end
	local mine = R.Score(Stats(link), class, slots)
	local worst, worstLink, worstStats
	for _, slot in ipairs(slots) do
		local eq = GetInventoryItemLink("player", slot)
		local st = eq and Stats(eq) or {}
		local sc = eq and R.Score(st, class, slots) or 0
		if not worst or sc < worst then worst, worstLink, worstStats = sc, eq, st end
	end
	local rs = Stats(link)
	local diff = {}
	for k, v in pairs(rs) do diff[k] = v - ((worstStats or {})[k] or 0) end
	for k, v in pairs(worstStats or {}) do if rs[k] == nil then diff[k] = -v end end
	return { gain = mine - (worst or 0), against = worstLink, diff = diff, info = info }
end

-- Best reward choice: an upgrade if there is one, else the highest vendor value.
-- Returns { index, link, upgrade = Compare result or nil, value } or nil while items load.
function R:Best(count, getLink, getNum)
	getLink = getLink or function(i) return GetQuestItemLink("choice", i) end
	getNum = getNum or function(i) return select(3, GetQuestItemInfo("choice", i)) end
	local bestUp, bestUpIndex, bestValue, bestValueIndex = nil, nil, -1, nil
	for i = 1, count do
		local link = getLink(i)
		if not link then return nil end
		local info = Info(link)
		if not info then return nil end
		local value = info.sell * math.max(1, ns.Num(getNum(i)) or 1)
		if value > bestValue then bestValue, bestValueIndex = value, i end
		local cmp = self:Compare(link)
		if cmp and cmp.gain > 0.5 and (not bestUp or cmp.gain > bestUp.gain) then bestUp, bestUpIndex = cmp, i end
	end
	if bestUp then return { index = bestUpIndex, link = getLink(bestUpIndex), upgrade = bestUp, value = nil } end
	if bestValueIndex then return { index = bestValueIndex, link = getLink(bestValueIndex), value = bestValue } end
end

-- "+8 Agility, +3 Stamina" from a comparison.
function R.DiffText(diff)
	local parts = {}
	for _, k in ipairs({ "STR", "AGI", "INT", "SPI", "STA", "AP", "SP", "dps", "armor" }) do
		local v = diff[k]
		if v and math.abs(v) >= 0.5 then
			local n = (k == "dps") and string.format("%.1f", v) or tostring(math.floor(v + 0.5))
			table.insert(parts, (v > 0 and "+" or "") .. n .. " " .. STAT_LABEL[k])
		end
		if #parts >= 4 then break end
	end
	return table.concat(parts, ", ")
end

-- A small green arrow on the chosen reward in the quest window.
function R:MarkButton(index)
	if not (QuestInfoFrame and QuestInfoFrame.rewardsFrame and QuestInfo_GetRewardButton) then return end
	local ok, btn = pcall(QuestInfo_GetRewardButton, QuestInfoFrame.rewardsFrame, index)
	if not ok or not btn then return end
	if not self.arrow then
		self.arrow = UIParent:CreateTexture(nil, "OVERLAY")
		self.arrow:SetAtlas("bags-greenarrow", false)
		self.arrow:SetSize(16, 16)
	end
	self.arrow:SetParent(btn)
	self.arrow:ClearAllPoints()
	self.arrow:SetPoint("TOPLEFT", btn, "TOPLEFT", -2, 2)
	self.arrow:SetDrawLayer("OVERLAY", 7)
	self.arrow:Show()
end

function R:ClearMark()
	if self.arrow then self.arrow:Hide() end
end

ns:RegisterEvent("QUEST_FINISHED", function() R:ClearMark() end)
