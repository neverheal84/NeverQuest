-- NeverQuest: leveling guide, waypoint arrow, quest planner and XP tracker for WoW Forever.
-- Core: saved variables, event/message dispatch, shared helpers, slash commands.

local ADDON, ns = ...
_G.NeverQuest = ns

ns.name = ADDON
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "1.0.0"
ns.AUTHOR = "NeverHeal84"
ns.DISCORD = "https://discord.gg/mmCB2teWvf"   -- never-expiring invite; bug reports, help and suggestions
ns.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
ns.LOGO = ns.MEDIA .. "Logo"   -- 256x256 TGA
ns.ICON = ns.MEDIA .. "Icon"   -- 64x64 TGA

local DEFAULTS = {
	hud    = { shown = true, locked = false, scale = 1, showRested = true, showRate = true, showToLevel = true, showFooter = true },
	arrow  = { shown = true, locked = false, arrival = 10, alwaysShow = false, scale = 1, compact = false,
	           size = 54, showETA = true, showThen = true, sound = true, corpse = true },
	window = { tab = "guide", journalView = "history", classView = "class", scale = 1 },
	style  = { font = "default", textScale = 1, outline = "", shadow = true },
	tracker = { shown = true, blizzard = "hide", hideFrame = true, locked = false, scale = 1, width = 270, maxHeight = 520, bgAlpha = 0.45,
	            sort = "priority", groupByZone = true, currentZoneFirst = true, collapseOther = false, collapsed = false,
	            showObjectives = true, hideDoneObjectives = false, finishedFirst = true, showNumbers = true,
	            showLevel = true, showDistance = true, showChains = true, showParty = true, showGray = true, maxQuests = 25 },
	drops  = { shown = false, locked = false, scale = 1, width = 250, maxHeight = 420, bgAlpha = 0.45,
	           collapsed = false, showSource = true, sort = "progress" },  -- sort: progress | remaining | distance
	auto   = { accept = true, turnin = true, gossip = true, skipGray = true, skipRepeatable = true, reward = "suggest",  -- reward: suggest | upgrade | value | off
	           inviteFrom = "off", inviteSend = false, inviteWord = "inv" },  -- group invites: off | known | anyone
	loot   = { auto = true, junk = true, junkReport = true, repair = true, repairGuild = false },  -- auto loot; sell grays; repair at vendors
	upkeep = { logFull = true, supplies = true, foodMin = 10, ammoMin = 200, bags = true, bagsMin = 3,
	           rested = true, sessionAtLogout = false, upgrades = true, training = true },
	travel = { flightPaths = true, hearth = true, hearthButton = true, hearthMinYards = 1500, setHearth = true },
	questdb = { scan = true, worldmap = true, minimap = true, ahead = 3, grayBelow = 6, share = true, deep = true, guild = true },
	compat = { questie = true, questieNoted = false },   -- hide our quest giver and spawn pins while Questie runs
	alerts = { complete = true, sound = true, trackTurnin = false },
	announce = { enabled = true, objectives = true, quests = true, turnins = false, attunements = true,
	             raid = false, sharedOnly = false, links = true, tag = true },
	guide  = { autoTrack = true, showGray = false, nearbyYards = 200, maxOffers = 4,
	           profile = true, milestones = true, dungeonTips = true,
	           style = "optimized", planner = true, chains = true, planPickups = true, showPredicted = true, routeSummary = true,
	           nearbyFirst = true, zoneAdvice = true, outleveledTip = true, restedTip = true,
	           partyInSteps = true, xpInSteps = true, viaInSteps = true, attunements = true, attuneAt = 50,
	           classTab = true, profQuests = true, profMine = true },
	nav    = { mapCoords = true, nativeWaypoint = true, adoptMapPins = true, paths = true, flights = true },
	pins   = { minimap = true, mmGivers = true, mmQuests = true, mmWaypoints = true,
	           worldmap = true, route = true, routeLine = true, routeTurnins = false, lineWidth = 3, routeSteps = 5, altClick = true, mmScale = 1, wmScale = 1 },
	buttons = { items = true, target = false, locked = false, scale = 1 },  -- target: the TARGET pill (off by default; its key binding works either way)
	party  = { enabled = true, catchUp = true, groupLevel = true, regroup = true, shareTips = true, autoShare = false },
	tooltips = { units = true, items = true, party = true },   -- quest lines on mob and item tooltips
	plates = { enabled = true, count = true, skull = true, scale = 1, side = "left" },   -- quest icons on nameplates (drawn by us; not raid markers)
	flightTimes = {},   -- seconds each flight took, learned from your own flights
	minimapButton = { shown = true, locked = false, angle = 210 },
	givers = { worldmap = true, otherZones = true, gray = false, red = false, dailies = true, levels = true, turnins = false },
	spawns = { learn = true, nameplates = true, rares = true, share = true, worldmap = true, minimap = false, dotSize = 1,
	           showAll = false, aim = true, markClick = true, levelFilter = true, levelBand = 8 },
	spawnData = { npcs = {}, objs = {}, marks = {}, rares = {} },  -- learned spots and your marks, all characters
	questDB = { q = {}, scan = {}, chars = {} },  -- quests the game has shown any of your characters (QuestDB.lua)
	guides = {},       -- recorded or imported guides, shared by all characters
	setupDone = false, setupHinted = false,  -- setup wizard finished or skipped; one-time hint about it shown
	positions = {},    -- saved frame positions
	npcs = { giver = {}, turnin = {}, giverAt = {}, turninAt = {} },  -- NPC names and spots learned from your own quest dialogs
	chains = { next = {}, prev = {} },   -- quest follow-ups seen right after a turn-in
	bestLevels = {},   -- [level] = { time = seconds, who = "Name" } fastest level across your characters
	errors = {},       -- recent errors for /nq report
	migrated = {},     -- one-time changes to older saved settings
	debug = false,
	quietLogin = false,
}

local CHAR_DEFAULTS = {
	waypoints = {},                          -- user waypoint queue
	script = { name = nil, step = 1, flags = {} },  -- loaded scripted guide
	recorder = { active = false, steps = {} },
	levels = {},                             -- [level] = { time = seconds, quest = xp, kill = xp }
	journal = {},                            -- turned-in quests, newest last
	milestones = {},                         -- plan milestones ticked off
	classQuests = {},                        -- class quest checklist rows ticked off
	profQuests = {},                         -- profession quest rows ticked off
	trainedLevel = 0,                        -- level at your last class trainer visit
	trackerHidden = {},                      -- quests hidden from the NeverQuest tracker
	trackerPinned = {},                      -- quests pinned to its top
	trackerZones = {},                       -- [zone] = true collapsed / false expanded
	trackerUntracked = {},                   -- quests NeverQuest untracked in Blizzard's list, to give back
	cvarBackup = {},                         -- the player's own auto-watch settings, to hand back when we stop hiding
	attune = {},                             -- [attunement] = { follow, turned, ticks, unticks }
	hearth = false,                          -- { name, m, x, y, zone } where you bound your hearthstone
}

local function Merge(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			Merge(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

---------------------------------------------------------------------------
-- Events and internal messages
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local eventHandlers, messageHandlers = {}, {}

---------------------------------------------------------------------------
-- Error safety: every handler runs protected; errors are logged for /nq report and
-- still passed to the game's error handler (BugSack shows them).
---------------------------------------------------------------------------
ns.paused = {}
local pendingErrors = {}

local function RecordError(where, err, stack)
	local entry = { msg = tostring(err), where = where, stack = stack, version = ns.version }
	local list = ns.db and ns.db.errors
	if not list then
		table.insert(pendingErrors, entry)
		return
	end
	for _, e in ipairs(list) do
		if e.msg == entry.msg then
			e.count, e.last = (e.count or 1) + 1, time()
			return
		end
	end
	entry.count, entry.first, entry.last = 1, time(), time()
	table.insert(list, entry)
	while #list > 30 do table.remove(list, 1) end
end

local function Trace(err)
	return { err = err, stack = debugstack and debugstack(2, 8, 0) or nil }
end

-- Runs fn(...) protected. Returns true when it worked.
function ns.Call(where, fn, ...)
	local n, args = select("#", ...), { ... }
	local ok, res = xpcall(function() return fn(unpack(args, 1, n)) end, Trace)
	if not ok then
		local err = type(res) == "table" and res.err or res
		RecordError(where, err, type(res) == "table" and res.stack or nil)
		local handler = geterrorhandler and geterrorhandler()
		if handler then handler(err) end
	end
	return ok
end

-- For code that runs over and over (OnUpdate, tickers): after 3 errors within a minute the
-- feature pauses instead of flooding errors, and says so once.
function ns.Guard(name, fn)
	local fails, since, paused = 0, 0, false
	return function(...)
		if paused then return end
		if not ns.Call(name, fn, ...) then
			local now = GetTime()
			if now - since > 60 then fails, since = 0, now end
			fails = fails + 1
			if fails >= 3 then
				paused = true
				ns.paused[name] = true
				ns.Print(name .. " hit repeated errors and was paused. /nq report shows details; /reload resumes it.")
			end
		end
	end
end

-- C_Timer.After with protection.
function ns.After(delay, fn)
	C_Timer.After(delay, function() ns.Call("timer", fn) end)
end

-- C_Timer.NewTicker with protection and pausing.
function ns.Ticker(interval, name, fn)
	return C_Timer.NewTicker(interval, ns.Guard(name, fn))
end

function ns.Debug(msg)
	if ns.db and ns.db.debug then
		DEFAULT_CHAT_FRAME:AddMessage("|cff888888NeverQuest debug:|r " .. tostring(msg))
	end
end

local function Dispatch(where, list, ...)
	if not list then return end
	for i = 1, #list do ns.Call(where, list[i], ...) end
end

function ns:RegisterEvent(event, fn)
	if not eventHandlers[event] then
		eventHandlers[event] = {}
		eventFrame:RegisterEvent(event)
	end
	table.insert(eventHandlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	Dispatch(event, eventHandlers[event], event, ...)
end)

function ns:RegisterMessage(msg, fn)
	messageHandlers[msg] = messageHandlers[msg] or {}
	table.insert(messageHandlers[msg], fn)
end

function ns:SendMessage(msg, ...)
	Dispatch(msg, messageHandlers[msg], msg, ...)
end

-- Modules add functions here; they run once saved variables are ready.
ns.inits = {}
function ns:OnInit(fn) table.insert(self.inits, fn) end

-- Moving from this addon's old name: when the old addon is still installed, its saved settings
-- are copied over once (account settings once, each character's on its first login), and the
-- old addon is switched off for that character. It may load before or after this one.
local OLD_NAME = "QuestMax"
local function DeepCopy(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = DeepCopy(x) end
	return t
end

function ns.MigrateFromOldName()
	local oldDB, oldChar = _G[OLD_NAME .. "DB"], _G[OLD_NAME .. "CharDB"]
	local moved = false
	if type(oldDB) == "table" and type(NeverQuestDB) ~= "table" then
		NeverQuestDB = DeepCopy(oldDB)
		moved = true
	end
	if type(oldChar) == "table" and type(NeverQuestCharDB) ~= "table" then
		NeverQuestCharDB = DeepCopy(oldChar)
		moved = true
	end
	local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(OLD_NAME)
	if loaded and C_AddOns.DisableAddOn then
		pcall(C_AddOns.DisableAddOn, OLD_NAME, UnitName("player"))
		ns.oldAddonRunning = true
	end
	ns.migrated = moved
	return moved, loaded
end

-- The old addon loading after this one: its settings arrive now. Copy them into the (still
-- empty) saved tables in place, so every module keeps the same tables; the reload offered at
-- login saves them.
local function CopyInto(dst, src, defaults)
	for k in pairs(dst) do dst[k] = nil end
	for k, v in pairs(DeepCopy(src)) do dst[k] = v end
	Merge(dst, defaults)
end

function ns.LateMigrate()
	local oldDB, oldChar = _G[OLD_NAME .. "DB"], _G[OLD_NAME .. "CharDB"]
	local moved = false
	if ns.freshInstall and type(oldDB) == "table" and type(NeverQuestDB) == "table" then
		CopyInto(NeverQuestDB, oldDB, DEFAULTS)
		ns.freshInstall = false
		moved = true
	end
	if ns.freshChar and type(oldChar) == "table" and type(NeverQuestCharDB) == "table" then
		CopyInto(NeverQuestCharDB, oldChar, CHAR_DEFAULTS)
		ns.freshChar = false
		moved = true
	end
	if C_AddOns and C_AddOns.DisableAddOn then pcall(C_AddOns.DisableAddOn, OLD_NAME, UnitName("player")) end
	ns.oldAddonRunning = true
	ns.migrated = ns.migrated or moved
	return moved
end

ns:RegisterEvent("ADDON_LOADED", function(_, name)
	if name == OLD_NAME and ns.ready then
		ns.LateMigrate()
		return
	end
	if name ~= ADDON then return end
	ns.MigrateFromOldName()
	-- Nothing saved yet: a new install, which gets the setup wizard.
	ns.freshInstall = type(NeverQuestDB) ~= "table" or next(NeverQuestDB) == nil
	ns.freshChar = type(NeverQuestCharDB) ~= "table" or next(NeverQuestCharDB) == nil
	NeverQuestDB = Merge(type(NeverQuestDB) == "table" and NeverQuestDB or {}, DEFAULTS)
	NeverQuestCharDB = Merge(type(NeverQuestCharDB) == "table" and NeverQuestCharDB or {}, CHAR_DEFAULTS)
	ns.db, ns.char = NeverQuestDB, NeverQuestCharDB
	for _, e in ipairs(pendingErrors) do RecordError(e.where, e.msg, e.stack) end
	wipe(pendingErrors)
	for i, fn in ipairs(ns.inits) do ns.Call("startup " .. i, fn) end
	ns.ready = true
end)

-- QuestMax ran alongside this session: say what happened and offer the reload that turns it off.
local function OfferReload()
	local f = CreateFrame("Frame", "NeverQuestMoveDialog", UIParent, "BackdropTemplate")
	f:SetSize(380, 120)
	f:SetPoint("TOP", 0, -160)
	f:SetFrameStrata("DIALOG")
	if ns.ApplyBackdrop then ns.ApplyBackdrop(f, 0.95) end
	local t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	t:SetPoint("TOPLEFT", 14, -14)
	t:SetPoint("TOPRIGHT", -14, -14)
	t:SetJustifyH("LEFT")
	t:SetText((ns.migrated and "QuestMax is now NeverQuest. Your settings, guides and learned spots came over. " or "QuestMax is now NeverQuest. ") ..
		"QuestMax has been switched off for this character; reload once so only NeverQuest runs.")
	local ok = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	ok:SetSize(120, 22)
	ok:SetPoint("BOTTOMLEFT", 14, 12)
	ok:SetText("Reload now")
	ok:SetScript("OnClick", function() if C_UI and C_UI.Reload then C_UI.Reload() elseif ReloadUI then ReloadUI() end end)
	local later = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	later:SetSize(90, 22)
	later:SetPoint("BOTTOMRIGHT", -14, 12)
	later:SetText("Later")
	later:SetScript("OnClick", function() f:Hide() end)
	f:Show()
	return f
end
ns.OfferReload = OfferReload

ns:RegisterEvent("PLAYER_LOGIN", function()
	if ns.oldAddonRunning then
		ns.Print("QuestMax is now NeverQuest" .. (ns.migrated and "; your settings came over" or "") .. ". QuestMax is switched off for this character from your next reload.")
		ns.Call("rename dialog", OfferReload)
	end
	if not ns.db.quietLogin then
		ns.Print(ns.version .. " by " .. ns.AUTHOR .. " loaded. /nq opens it, /nq help explains everything.")
	end
	-- After an update: one line pointing at what changed.
	if ns.db.lastVersion ~= ns.version then
		if ns.db.lastVersion or not ns.freshInstall then
			ns.Print("updated to " .. ns.version .. ". /nq news shows what's new.")
		end
		ns.db.lastVersion = ns.version
	end
	if ns.QuestieOverlap() and not ns.db.compat.questieNoted then
		ns.db.compat.questieNoted = true
		ns.Print("Questie is running, so NeverQuest leaves quest givers and spawn spots on the maps to it. Your guide, route and arrow stay. /nq questie switches this.")
	end
end)


---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local issecret = _G.issecretvalue

-- Questie draws its own quest givers and objective spots on the maps. While it runs, ours
-- step aside (setting: compat.questie); the route, arrow and guide stay.
function ns.QuestieOverlap()
	if not (ns.db and ns.db.compat and ns.db.compat.questie) then return false end
	local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	return f and f("Questie") and true or false
end

function ns.IsSecret(v)
	return issecret ~= nil and issecret(v) or false
end

-- Returns v if it is a usable (non-secret) number, else nil.
function ns.Num(v)
	if v == nil or ns.IsSecret(v) or type(v) ~= "number" then return nil end
	return v
end

-- Calls a game function and returns its first result, or nil when it errors or the game
-- hides the answer (a secret value can't even be tested, so this checks first).
function ns.SafeCall(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn, ...)
	if not ok or v == nil or ns.IsSecret(v) then return nil end
	return v
end

-- Unit name, or nil when the game hides it (restricted content) or the unit doesn't exist.
function ns.SafeName(unit)
	if not UnitExists(unit) then return nil end
	local name = UnitName(unit)
	if name == nil or ns.IsSecret(name) or name == "" then return nil end
	return name
end

-- The mob in a kill objective, read with the client's own wording for it. The game formats
-- these lines from QUEST_MONSTERS_KILLED ("%s slain: %d/%d" in English, something else in
-- every other language), so that string is turned into a pattern rather than matching the
-- English word. The English forms stay as a fallback for clients that don't expose it.
local killPatterns = {}
local function KillPattern()
	local fmt = QUEST_MONSTERS_KILLED
	if type(fmt) ~= "string" or fmt == "" then return nil end
	local p = killPatterns[fmt]
	if p == nil then
		p = fmt:gsub("%%%d+%$", "%%")                          -- %1$s -> %s
		p = p:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")       -- the rest is literal text
		p = p:gsub("%%s", "(.-)"):gsub("%%d", "%%d+")
		p = "^" .. p .. "$"
		killPatterns[fmt] = p
	end
	return p
end

function ns.KillName(text)
	if type(text) ~= "string" or ns.IsSecret(text) then return nil end
	local p = KillPattern()
	local name = p and text:match(p)
	if not name or name == "" then
		name = text:match("^(.-) slain: %d+/%d+") or text:match("^%d+/%d+ (.-) slain")
	end
	return (name and name ~= "") and name or nil
end

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99NeverQuest|r: " .. tostring(msg))
end

function ns.Comma(n)
	n = math.floor((n or 0) + 0.5)
	local s, k = tostring(n), nil
	repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
	return s
end

function ns.Duration(sec)
	if not sec or sec ~= sec or sec == math.huge or sec < 0 or sec > 360000 then return "--" end
	sec = math.floor(sec + 0.5)
	if sec >= 3600 then
		return string.format("%dh %02dm", math.floor(sec / 3600), math.floor((sec % 3600) / 60))
	elseif sec >= 60 then
		return string.format("%dm %02ds", math.floor(sec / 60), sec % 60)
	end
	return string.format("%ds", sec)
end

function ns.Yards(y)
	if not y then return "" end
	if y >= 1000 then return string.format("%.1fk yd", y / 1000) end
	return string.format("%d yd", math.floor(y + 0.5))
end

function ns.Money(copper)
	copper = math.floor(copper or 0)
	local g, s, c = math.floor(copper / 10000), math.floor((copper % 10000) / 100), copper % 100
	if g > 0 then return string.format("%dg %ds", g, s) end
	if s > 0 then return string.format("%ds %dc", s, c) end
	return string.format("%dc", c)
end

function ns.Hex(r, g, b)
	return string.format("|cff%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

-- Quest difficulty color (gray / green / yellow / orange / red) for a quest ID.
function ns.QuestColor(questID)
	if questID and C_PlayerInfo and C_PlayerInfo.GetContentDifficultyQuestForPlayer and GetDifficultyColor then
		local diff = C_PlayerInfo.GetContentDifficultyQuestForPlayer(questID)
		local c = diff and GetDifficultyColor(diff)
		if c and c.r then return c.r, c.g, c.b end
	end
	return 1, 0.82, 0
end

-- Runs fn once after `delay` seconds, collapsing repeated calls with the same key.
local pendingDebounce = {}
function ns.Debounce(key, delay, fn)
	if pendingDebounce[key] then return end
	pendingDebounce[key] = true
	C_Timer.After(delay, function()
		pendingDebounce[key] = nil
		ns.Call(key, fn)
	end)
end

function ns.PlaySound(kit)
	if ns.db and ns.db.alerts.sound and kit then PlaySound(kit) end
end

ns.BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 14,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

function ns.ApplyBackdrop(frame, alpha)
	frame:SetBackdrop(ns.BACKDROP)
	frame:SetBackdropColor(0.04, 0.04, 0.06, alpha or 0.88)
	frame:SetBackdropBorderColor(0.55, 0.45, 0.2, 1)
end

-- Makes a frame draggable and remembers where it was left.
function ns.MakeMovable(frame, key, isLocked, defaultPoint)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if not (isLocked and isLocked()) then self:StartMoving() end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint(1)
		ns.db.positions[key] = { point, relPoint, x, y }
	end)
	frame.RestorePosition = function(self)
		self:ClearAllPoints()
		local p = ns.db.positions[key]
		if p then
			self:SetPoint(p[1], UIParent, p[2], p[3], p[4])
		else
			self:SetPoint(unpack(defaultPoint))
		end
	end
	frame:RestorePosition()
end

-- Alert text in the upper middle of the screen.
local alertFrame
function ns.Alert(text, r, g, b)
	if not alertFrame then
		alertFrame = CreateFrame("Frame", nil, UIParent)
		alertFrame:SetSize(600, 40)
		alertFrame:SetPoint("TOP", UIParent, "TOP", 0, -170)
		alertFrame:SetFrameStrata("HIGH")
		alertFrame.text = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
		alertFrame.text:SetPoint("CENTER")
		alertFrame:SetScript("OnUpdate", ns.Guard("Alerts", function(self, elapsed)
			self.t = self.t + elapsed
			if self.t > 4 then self:Hide()
			elseif self.t > 3 then self:SetAlpha(4 - self.t) end
		end))
	end
	alertFrame.text:SetText(text)
	alertFrame.text:SetTextColor(r or 1, g or 0.82, b or 0)
	alertFrame.t = 0
	alertFrame:SetAlpha(1)
	alertFrame:Show()
end

---------------------------------------------------------------------------
-- Slash commands (modules add entries to ns.slash)
---------------------------------------------------------------------------
ns.slash = {}
ns.slashHelp = {}

function ns:AddSlash(cmd, fn, help)
	self.slash[cmd] = fn
	if help then table.insert(self.slashHelp, help) end
end

SLASH_NEVERQUEST1 = "/nq"
SLASH_NEVERQUEST2 = "/neverquest"
-- The old command keeps working, unless QuestMax itself is still running this session.
if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("QuestMax")) then
	SLASH_NEVERQUEST3 = "/qmax"
end
SlashCmdList["NEVERQUEST"] = function(msg)
	msg = msg or ""
	local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()
	if cmd == "" then
		if ns.UI then ns.UI:Toggle() end
		return
	end
	local fn = ns.slash[cmd]
	if fn then
		ns.Call("/nq " .. cmd, fn, rest or "")
	else
		ns.Print("commands:")
		for _, line in ipairs(ns.slashHelp) do
			DEFAULT_CHAT_FRAME:AddMessage("   " .. line)
		end
	end
end

ns:AddSlash("questie", function()
	ns.db.compat.questie = not ns.db.compat.questie
	ns.Print(ns.db.compat.questie and "with Questie running, NeverQuest's quest giver and spawn pins stay hidden."
		or "NeverQuest shows its quest giver and spawn pins even with Questie running.")
	ns:SendMessage("MAP_OFFERS_UPDATED")
end, "/nq questie - with Questie running, hide or show NeverQuest's own quest giver and spawn pins")

ns:AddSlash("help", function()
	ns.Print("commands:")
	for _, line in ipairs(ns.slashHelp) do DEFAULT_CHAT_FRAME:AddMessage("   " .. line) end
end)

ns:AddSlash("reset", function()
	wipe(ns.db.positions)
	ns:SendMessage("POSITIONS_RESET")
	ns.Print("frame positions reset.")
end, "/nq reset - move all NeverQuest frames back to their default spots")

ns:AddSlash("debug", function()
	ns.db.debug = not ns.db.debug
	ns.Print(ns.db.debug and "debug messages on." or "debug messages off.")
end, "/nq debug - show what NeverQuest is doing in chat (for testing)")

ns:AddSlash("quiet", function()
	ns.db.quietLogin = not ns.db.quietLogin
	ns.Print(ns.db.quietLogin and "login message off." or "login message on.")
end)

ns:AddSlash("lock", function()
	local lock = not ns.db.hud.locked
	ns.db.hud.locked, ns.db.arrow.locked = lock, lock
	ns.Print(lock and "frames locked." or "frames unlocked (drag to move).")
end, "/nq lock - lock or unlock the XP panel and arrow")
