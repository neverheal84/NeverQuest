-- NeverQuest Plates: a small icon on the nameplate of every mob your quests want, so the ones
-- that count stand out in a pack. The mob the guide is sending you at wears a skull.
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
	local refs = name and ns.Tooltips:ForMob(name) or nil
	local related = SafeCall(C_QuestLog.UnitIsRelatedToActiveQuest, unit) == true
	if not refs and not related then return nil end
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
	f.tex:SetTexture(ICON[want.icon])
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
for _, msg in ipairs({ "QUESTS_UPDATED", "SPAWNS_UPDATED", "GUIDE_UPDATED" }) do
	ns:RegisterMessage(msg, Later)
end

ns:AddSlash("plates", function(rest)
	local cfg = Cfg()
	rest = (rest or ""):lower()
	if rest == "on" or rest == "off" then cfg.enabled = (rest == "on") else cfg.enabled = not cfg.enabled end
	P:RefreshAll()
	ns.Print(cfg.enabled and "quest icons on nameplates: on (enemy nameplates have to be showing: V by default)."
		or "quest icons on nameplates: off.")
end, "/nq plates [on | off] - quest icons on the nameplates of mobs your quests want")
