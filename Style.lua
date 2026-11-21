-- NeverQuest Style: text settings shared by every NeverQuest panel (main window, tracker, XP
-- panel, arrow, buttons). Panels use these font objects instead of the game's, so one change
-- here restyles them all. Sizes of whole panels are separate settings on each panel.

local ADDON, ns = ...
local St = {}
ns.Style = St

St.FONTS = {
	{ "default", "Game default" },
	{ "Fonts\\FRIZQT__.TTF", "Friz Quadrata" },
	{ "Fonts\\ARIALN.TTF", "Arial Narrow" },
	{ "Fonts\\MORPHEUS.ttf", "Morpheus" },
	{ "Fonts\\skurri.ttf", "Skurri" },
	{ "Fonts\\2002.TTF", "2002" },
}
St.OUTLINES = { { "", "None" }, { "OUTLINE", "Outline" }, { "THICKOUTLINE", "Thick outline" } }
St.TEXT_SIZES = { { 0.85, "Small" }, { 1, "Normal" }, { 1.15, "Large" }, { 1.3, "Larger" }, { 1.5, "Huge" } }
St.SCALES = { { 0.7, "70%" }, { 0.8, "80%" }, { 0.9, "90%" }, { 1, "100%" }, { 1.1, "110%" }, { 1.25, "125%" }, { 1.5, "150%" } }

-- NeverQuest font object -> the game font it starts from.
local OBJECTS = {
	{ "NeverQuestFontTitle", "GameFontNormalLarge" },
	{ "NeverQuestFontNormal", "GameFontNormal" },
	{ "NeverQuestFontHighlight", "GameFontHighlight" },
	{ "NeverQuestFontSmall", "GameFontHighlightSmall" },
	{ "NeverQuestFontSmallGray", "GameFontDisableSmall" },
	{ "NeverQuestFontNormalSmall", "GameFontNormalSmall" },
	{ "NeverQuestFontNumber", "NumberFontNormal" },
	{ "NeverQuestFontTiny", "GameFontNormalSmall", 0.8 },   -- small captions (third field: size factor)
}
local FALLBACK_FILE = "Fonts\\FRIZQT__.TTF"
St.base, St.objects = {}, {}

for _, def in ipairs(OBJECTS) do
	local name, from = def[1], def[2]
	local obj = CreateFont(name)
	St.objects[name] = obj
	local src = _G[from]
	local file, size, flags
	if src and src.GetFont then
		obj:CopyFontObject(src)
		file, size, flags = src:GetFont()
	end
	St.base[name] = { file = file or FALLBACK_FILE, size = (size or 12) * (def[3] or 1), flags = flags or "" }
	if not src then
		pcall(obj.SetFont, obj, FALLBACK_FILE, 12 * (def[3] or 1), "")
	elseif def[3] then
		pcall(obj.SetFont, obj, file or FALLBACK_FILE, (size or 12) * def[3], flags or "")
	end
end

local function Cfg() return ns.db.style end

function St:Size(name)
	local base = self.base[name]
	return math.floor((base and base.size or 12) * (Cfg().textScale or 1) + 0.5)
end

-- Height for one line of this font, with a little spacing.
function St:LineHeight(name)
	return self:Size(name) + math.max(2, math.floor(self:Size(name) * 0.25))
end

function St:Apply()
	local cfg = Cfg()
	for name, base in pairs(self.base) do
		local obj = self.objects[name]
		if obj then
			local size = self:Size(name)
			local flags = cfg.outline or ""
			local file = (cfg.font and cfg.font ~= "default") and cfg.font or base.file
			if not pcall(obj.SetFont, obj, file, size, flags) then
				pcall(obj.SetFont, obj, base.file, size, flags)
			end
			if cfg.shadow then
				obj:SetShadowOffset(1, -1)
			else
				obj:SetShadowOffset(0, 0)
			end
		end
	end
	ns:SendMessage("STYLE_CHANGED")
end

ns:OnInit(function() St:Apply() end)
