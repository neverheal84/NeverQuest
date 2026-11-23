-- NeverQuest Plates: a small icon on the nameplate of every mob your quests want, so the ones
-- that count stand out in a pack. The mob the guide is sending you at wears a skull. The
-- people your quests send you to get one as well: a question mark on whoever a finished quest
-- is handed to, an exclamation mark on someone with a quest for you.
--
-- These are pictures NeverQuest draws on your own screen. They are not raid markers: the game
-- no longer lets an addon place those, and nobody else sees these. What earns a mob its icon
-- is your quest log (the game's own "does this unit count for a quest I'm on") and the drop
-- sources NeverQuest has learned. Nothing about a fight goes into it.
--
-- Unit names can be hidden from addons. When one is, the icon still shows, because the game
-- still answers whether the unit counts for a quest; only the count beside it is left off.

local ADDON, ns = ...
local P = {}
ns.Plates = P

local SafeCall = ns.SafeCall

local SIZE = 18
local ICON = {
	skull = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
	kill = "Interface\\CURSOR\\Attack",
	drop = "Interface\\CURSOR\\Pickup",
	turnin = "QuestTurnin",
	giver = "QuestNormal",
}

local function Cfg() return ns.db.plates end

---------------------------------------------------------------------------
-- Does this unit get an icon
---------------------------------------------------------------------------
-- nil, or { icon = "skull" | "kill" | "drop", text = "3/8" or nil }
function P:Want(unit)
	local cfg = Cfg()
	if not UnitExists(unit) or SafeCall(UnitIsPlayer, unit) ~= false then return nil end
	if SafeCall(UnitIsDead, unit) == true then return nil end
	local name = ns.SafeName(unit)
	local related = SafeCall(C_QuestLog.UnitIsRelatedToActiveQuest, unit) == true
	local refs = name and ns.Tooltips:Usable(ns.Tooltips:ForMob(name), related) or nil
	-- Someone friendly is never something to kill, whatever the game's quest flag says: the
	-- people you hand quests to are "related to an active quest" too.
	local friendly = UnitCanAttack and SafeCall(UnitCanAttack, "player", unit) == false
	if friendly then refs, related = nil, false end
	if not refs and not related then
		-- Not something to kill or loot. Someone to talk to, perhaps.
		if cfg.npcs == false then return nil end
		local role = name and ns.Quests:NpcRole(name)
		role = role and role[1]
		if role and (role.kind == "turnin" or role.kind == "giver") then return { icon = role.kind } end
		return nil
	end
	local want = { icon = "kill" }
	local ref = refs and refs[1]
	if ref then
		if ref.kind ~= "kill" then want.icon = "drop" end
		if cfg.count then
			local d = ns.Tooltips:Describe(ref)
			if d.have and d.need and d.need > 0 then want.text = d.have .. "/" .. d.need end
		end
	end
	if cfg.skull and name then
		local step = ns.Tooltips:StepMob()
		if step and name:lower() == step then want.icon = "skull" end
	end
	return want
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local shown = {}    -- [unit] = true for nameplates on screen
local icons = setmetatable({}, { __mode = "k" })   -- [nameplate] = our icon; kept here, not on the game's frame
P.icons = icons

local function PlateFor(unit)
	if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
	if not ok or not plate then return nil end
	-- Some nameplates are off limits to addons altogether; touching one is an error.
	if plate.IsForbidden and plate:IsForbidden() then return nil end
	return plate
end

local function Build(plate)
	local f = CreateFrame("Frame", nil, plate)
	f:SetSize(SIZE, SIZE)
	f.tex = f:CreateTexture(nil, "OVERLAY")
	f.tex:SetAllPoints()
	f.text = f:CreateFontString(nil, "OVERLAY", "NeverQuestFontTiny")
	f.text:SetPoint("TOP", f, "BOTTOM", 0, 1)
	return f
end

function P:Update(unit)
	local plate = PlateFor(unit)
	if not plate then return end
	local f = icons[plate]
	local want = Cfg().enabled and not ns.QuestieOverlap() and self:Want(unit) or nil
	if not want then
		if f then f:Hide() end
		return
	end
	if not f then
		f = Build(plate)
		icons[plate] = f
	end
	local scale = Cfg().scale or 1
	f:SetSize(SIZE * scale, SIZE * scale)
	f:ClearAllPoints()
	local side = Cfg().side
	if side == "right" then
		f:SetPoint("LEFT", plate, "RIGHT", -6, 0)
	elseif side == "top" then
		f:SetPoint("BOTTOM", plate, "TOP", 0, -6)
	else
		f:SetPoint("RIGHT", plate, "LEFT", 6, 0)
	end
	ns.SetIcon(f.tex, ICON[want.icon])
	f.text:SetText(want.text or "")
	f.kind = want.icon
	f:Show()
end

function P:RefreshAll()
	for unit in pairs(shown) do
		local ok = pcall(self.Update, self, unit)
		if not ok then shown[unit] = nil end
	end
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
local guarded = ns.Guard("Nameplate quest icons", function(unit) P:Update(unit) end)

ns:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, unit)
	if type(unit) ~= "string" then return end
	shown[unit] = true
	guarded(unit)
end)
ns:RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, unit)
	if type(unit) ~= "string" then return end
	shown[unit] = nil
	local plate = PlateFor(unit)
	if plate and icons[plate] then icons[plate]:Hide() end
end)

local function Later() ns.Debounce("plates", 0.3, function() P:RefreshAll() end) end
for _, msg in ipairs({ "QUESTS_UPDATED", "SPAWNS_UPDATED", "GUIDE_UPDATED", "OFFERS_UPDATED" }) do
	ns:RegisterMessage(msg, Later)
end

-- The icons sit on nameplates, so there is nothing to see while the game is not drawing any.
-- These are the game's own settings (the V and Shift-V keys); they are only changed when you
-- ask, with /nq plates show.
local SHOW_CVARS = { "nameplateShowEnemies", "nameplateShowFriends", "nameplateShowFriendlyNPCs" }

function P:Hidden()
	local enemies = GetCVar and SafeCall(GetCVar, "nameplateShowEnemies")
	local friends = GetCVar and SafeCall(GetCVar, "nameplateShowFriendlyNPCs")
	return enemies == "0", friends == "0"
end

function P:ShowNameplates()
	if InCombatLockdown() then
		ns.Print("nameplate settings can't be changed in combat. Try again after the fight.")
		return false
	end
	for _, cvar in ipairs(SHOW_CVARS) do
		if SafeCall(GetCVar, cvar) ~= nil then pcall(SetCVar, cvar, "1") end
	end
	ns.Print("nameplates switched on for enemies and friendly NPCs, so quest icons have something to sit on. V and Shift-V switch them off again.")
	return true
end

-- Said once per session, and only while there is a quest to show icons for.
local hinted
local function Hint()
	if hinted or not Cfg().enabled or ns.QuestieOverlap() or #ns.Quests.log == 0 then return end
	local noEnemies, noFriends = P:Hidden()
	if not noEnemies and not noFriends then return end
	hinted = true
	ns.Print(string.format("quest icons are drawn on nameplates, and nameplates for %s are switched off. |cffffff00/nq plates show|r turns them on.",
		noEnemies and noFriends and "enemies and friendly NPCs" or noEnemies and "enemies" or "friendly NPCs"))
end
ns:RegisterEvent("PLAYER_ENTERING_WORLD", function() ns.After(8, Hint) end)
P.Hint = Hint
function P:ResetHint() hinted = nil end

ns:AddSlash("plates", function(rest)
	local cfg = Cfg()
	rest = (rest or ""):lower()
	if rest == "show" then
		cfg.enabled = true
		P:ShowNameplates()
		P:RefreshAll()
		return
	end
	if rest == "npcs" then
		cfg.npcs = cfg.npcs == false
		P:RefreshAll()
		ns.Print(cfg.npcs and "icons on the people your quests send you to: on." or "icons on the people your quests send you to: off.")
		return
	end
	if rest == "on" or rest == "off" then cfg.enabled = (rest == "on") else cfg.enabled = not cfg.enabled end
	P:RefreshAll()
	ns.Print(cfg.enabled and "quest icons on nameplates: on."
		or "quest icons on nameplates: off.")
	if cfg.enabled then hinted = nil Hint() end
end, "/nq plates [on | off | show | npcs] - quest icons on nameplates; show turns the game's nameplates on")
