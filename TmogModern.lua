-- TmogModern.lua  (v2, written against Tmog 5.0.1 source)
-- Optional client-mod layer. Load it from Tmog.xml right AFTER Slashcmd.lua:
--     <Script file="TmogModern.lua"/>
-- (Tmog.toc only lists Tmog.xml, so do NOT add it to the .toc.)
-- Everything is capability-gated: without ClassicAPI the addon behaves exactly as before.
--
-- Overrides (all fall back to the original when data isn't available):
--   Tmog.CacheItem          -> throttled C_Item request instead of hidden-tooltip SetHyperlink
--   TmogLoadingFrame OnUpdate -> same UI, but prunes the never-cleared queueIDs table
--   Tmog.GetTransmogSlot    -> numeric class/subclass + allowableClass bitmask, no tooltip scan
--   Tmog.IsKnownAppearance  -> one flat index instead of walking ItemDB per item
-- Adds: /tmogmod  (status | groups | audit | morph | unmorph | backup | restore | dump)
--
-- UNVERIFIED (search for TEST): SetUnitVisibleItemID slot numbering / reset behaviour,
-- ExportFile/ImportFile file naming. Nothing here has been run in a real client.

Tmog = Tmog or {}
local M = {}
Tmog.Modern = M

local getn, tinsert, concat = table.getn, table.insert, table.concat
local floor, mod = math.floor, math.mod
local strfind, format = string.find, string.format
local gfind = string.gmatch or string.gfind

M.requestsPerTick = 30 -- item queries sent per 50 ms tick
M.maxInFlight = 200    -- Prefetch stops sending while this many are unanswered
M.slotOffset = 0       -- TEST: set to -1 if SetUnitVisibleItemID is 0-based

M.has = {
	classic  = (C_Item and C_Item.GetItemDataByID and C_Timer and C_Timer.NewTicker and GetItemSubClassInfo) and true or false,
	superwow = ExportFile ~= nil and ImportFile ~= nil,
	vhelpers = SetUnitVisibleItemID ~= nil,
	nampower = GetNampowerVersion ~= nil,
}

local function say(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff0070deTmog+|r " .. tostring(msg)) end
local function cfg() TmogConfig = TmogConfig or {} return TmogConfig end

------------------------------------------------------------------------
-- 1. Throttled item requests + Tmog.CacheItem
------------------------------------------------------------------------
local queue, queued, ticker = {}, 0, nil
local waiting = {} -- [itemID] = { callbacks }
local inFlight = 0

local function pump()
	local sent = 0
	for id in pairs(queue) do
		queue[id] = nil
		queued = queued - 1
		if not C_Item.IsItemDataCachedByID(id) then C_Item.RequestLoadItemDataByID(id) end
		sent = sent + 1
		if sent >= M.requestsPerTick then break end
	end
	if queued <= 0 and ticker then ticker:Cancel() ticker = nil end
end

function M.QueueRequest(id)
	if queue[id] then return end
	queue[id] = true
	queued = queued + 1
	if not ticker then ticker = C_Timer.NewTicker(0.05, pump) end
end

-- cached table or nil, never sends a request
function M.Peek(itemID)
	itemID = tonumber(itemID)
	if not itemID or not M.has.classic then return nil end
	return C_Item.GetItemDataByID(itemID)
end

-- cached table now, or nil and cb(itemID, data|nil) later
function M.GetItemData(itemID, cb)
	itemID = tonumber(itemID)
	if not itemID or not M.has.classic then return nil end
	local d = C_Item.GetItemDataByID(itemID)
	if d then return d end
	if cb then
		if not waiting[itemID] then waiting[itemID] = {} inFlight = inFlight + 1 end
		tinsert(waiting[itemID], cb)
	end
	M.QueueRequest(itemID)
	return nil
end

if M.has.classic then
	local f = CreateFrame("Frame")
	f:RegisterEvent("ITEM_DATA_LOAD_RESULT")
	f:SetScript("OnEvent", function()
		local id, ok = arg1, arg2
		local w = waiting[id]
		if not w then return end
		waiting[id] = nil
		inFlight = inFlight - 1
		local d = ok and C_Item.GetItemDataByID(id) or nil
		for i = 1, getn(w) do w[i](id, d) end
	end)

	local origCache = Tmog.CacheItem
	-- ON by default (this is what removed the ~5 s freeze). /tmogmod cache off = original hidden-tooltip method
	Tmog.CacheItem = function(linkOrID)
		if cfg().modernCache == false then return origCache(linkOrID) end
		if not linkOrID or linkOrID == 0 then return nil end
		local id = tonumber(linkOrID)
		if not id and type(linkOrID) == "string" then
			local _, _, s = strfind(linkOrID, "item:(%d+)")
			id = tonumber(s)
		end
		if not id then return nil end
		local name, _, quality, _, _, _, _, _, texture = GetItemInfo(id)
		if name then return name, quality, texture end
		M.QueueRequest(id)
		return nil
	end
end

-- Warm many items without flooding the server. onDone() when finished (or after 60 s).
function M.Prefetch(ids, onDone, onProgress)
	if not M.has.classic then if onDone then onDone() end return end
	local i, n, t0 = 1, getn(ids), GetTime()
	local t
	t = C_Timer.NewTicker(0.05, function()
		local sent = 0
		while i <= n and sent < M.requestsPerTick and inFlight < M.maxInFlight do
			local id = ids[i]
			i = i + 1
			if not C_Item.IsItemDataCachedByID(id) then
				M.GetItemData(id, function() end)
				sent = sent + 1
			end
		end
		if onProgress and mod(floor(GetTime() * 20), 40) == 0 then onProgress(i, n) end
		if (i > n and inFlight <= 0) or GetTime() - t0 > 60 then
			t:Cancel()
			if onDone then onDone() end
		end
	end)
end

------------------------------------------------------------------------
-- 2. Loading screen: same behaviour, but prune queueIDs as items arrive
--    (original never removes ids, so every later load re-scans all of them)
------------------------------------------------------------------------
local LF = TmogLoadingFrame
if LF and M.has.classic then
	LF:SetScript("OnUpdate", function(self, elapsed)
		self = self or this
		elapsed = elapsed or arg1
		if self.queueTimer == 0 then
			TmogFrameLoadingTexture:Hide()
			return
		end
		if self.dotTimer <= 0 then
			self.dotCount = self.dotCount + 1
			if self.dotCount > 3 then self.dotCount = 0 end
			TmogFrameLoadingTextureText:SetText(Tmog.L["Loading"] .. " " .. self.dotStrings[self.dotCount])
			self.dotTimer = 0.3
		else
			self.dotTimer = self.dotTimer - elapsed
		end
		local remaining = 0
		for id in pairs(self.queueIDs) do
			if GetItemInfo(id) then self.queueIDs[id] = nil else remaining = remaining + 1 end
		end
		for _, frame in pairs(Tmog.PreviewFrames) do frame.button:EnableMouse(false) end
		TmogFrameLoadingTexture:Show()
		if remaining == 0 or self.queueTimer <= 0 then
			self.queueTimer = 0
			TmogFrameLoadingTexture:Hide()
			for _, frame in pairs(Tmog.PreviewFrames) do frame.button:EnableMouse(true) end
			Tmog.UpdatePreviews()
		else
			self.queueTimer = self.queueTimer - elapsed
		end
	end)
end

------------------------------------------------------------------------
-- 3. Tmog.GetTransmogSlot without tooltip scanning
--    Proficiency sets are DERIVED from Tmog.classEquipTable (single source of truth):
--    GetItemSubClassInfo(class, sub) gives the localized name Tmog already keys on.
------------------------------------------------------------------------
local CLASS_BIT = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
	SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 } -- 2^(classID-1)
local DUAL = { WARRIOR = true, HUNTER = true, ROGUE = true }

local PROF
local function buildProf()
	PROF = {}
	for classEn, names in pairs(Tmog.classEquipTable or {}) do
		local set, n = {}, 0
		for c = 2, 4, 2 do -- weapon(2), armor(4)
			for s = 0, 20 do
				local name = GetItemSubClassInfo(c, s)
				if name and names[name] then set[c .. ":" .. s] = true n = n + 1 end
			end
		end
		if n > 0 then PROF[classEn] = set end
	end
end

-- returns handled(bool), slot
local function slotFromData(d)
	local inv = Tmog.InventoryTypeToSlot[d.equipLoc]
	if not inv then return true, nil end
	local _, classEn = UnitClass("player")
	if d.equipLoc == "INVTYPE_HOLDABLE" then return true, inv end
	if not PROF then buildProf() end
	local set = PROF[classEn]
	if not set then return false end -- unknown class table: let the original decide
	if not set[d.classID .. ":" .. d.subclassID] then return true, nil end
	if d.classID == 2 and d.subclassID == 14 then return true, nil end -- "not a real weapon"
	if not DUAL[classEn] and d.equipLoc == "INVTYPE_WEAPONOFFHAND" then return true, nil end
	local mask, bit = d.allowableClass, CLASS_BIT[classEn]
	if mask and mask > 0 and bit and mod(floor(mask / bit), 2) == 0 then return true, nil end
	return true, inv
end

if M.has.classic and Tmog.GetTransmogSlot then
	local orig = Tmog.GetTransmogSlot
	Tmog.GetTransmogSlot = function(itemID, unit, tooltip)
		if not unit or unit == "player" then
			local d = M.Peek(itemID)
			if d then
				local handled, slot = slotFromData(d)
				if handled then return slot end
			end
		end
		return orig(itemID, unit, tooltip)
	end
end

------------------------------------------------------------------------
-- 4. Tmog.IsKnownAppearance: O(1) after one index build
------------------------------------------------------------------------
if Tmog.IsKnownAppearance and Tmog.ItemDB then
	local known
	Tmog.IsKnownAppearance = function(itemID)
		itemID = tonumber(itemID)
		if not itemID then return nil end
		if not known then
			known = {}
			for _, types in pairs(Tmog.ItemDB) do
				for _, list in pairs(types) do
					for id in pairs(list) do known[id] = true end
				end
			end
		end
		return known[itemID] == true
	end
end

------------------------------------------------------------------------
-- 5. Appearance groups from the client's own display IDs
--    Tmog.DisplayGroups = array of {itemID,...}; Tmog.ItemDisplayGroup[itemID] = index
------------------------------------------------------------------------
function M.GetDisplayID(itemID)
	itemID = tonumber(itemID)
	if not itemID then return nil end
	if GetItemDisplayID then -- VanillaHelpers
		local id = GetItemDisplayID(itemID)
		if id and id > 0 then return id end
	end
	local d = M.Peek(itemID)
	return d and d.displayInfoID or nil
end

local function allDBItems()
	local ids, slotsOf, seen = {}, {}, {}
	for slot, types in pairs(Tmog.ItemDB) do
		for _, list in pairs(types) do
			for id in pairs(list) do
				if not seen[id] then seen[id] = true tinsert(ids, id) end
				slotsOf[id] = slotsOf[id] or {}
				slotsOf[id][slot] = true
			end
		end
	end
	return ids, slotsOf
end

-- Compare the author's static groups with what the client says.
function M.AuditGroups()
	local ids = {}
	for id in pairs(Tmog.ItemDisplayGroup) do tinsert(ids, id) end
	say("audit: loading " .. getn(ids) .. " grouped items...")
	M.Prefetch(ids, function()
		local first, bad, checked = {}, 0, 0
		for id, g in pairs(Tmog.ItemDisplayGroup) do
			local disp = M.GetDisplayID(id)
			if disp then
				checked = checked + 1
				if not first[g] then first[g] = { disp, id }
				elseif first[g][1] ~= disp then
					bad = bad + 1
					if bad <= 15 then
						say(format("group %d: item %d (display %d) vs item %d (display %d)", g, id, disp, first[g][2], first[g][1]))
					end
				end
			end
		end
		say(format("audit done: %d checked, %d groups disagree with client display IDs", checked, bad))
	end)
end

-- Add items that share a display ID but are missing from the static tables, then
-- credit them if a group-mate is already collected (same rule Tmog.OnEvent uses).
function M.SupplementGroups(quiet)
	if not M.has.classic then return say("ClassicAPI not loaded") end
	local ids, slotsOf = allDBItems()
	local progress
	if not quiet then
		say("groups: loading " .. getn(ids) .. " items (throttled)...")
		progress = function(i, n) say(format("  ...%d/%d", i, n)) end
	end
	M.Prefetch(ids, function()
		local byDisp = {}
		for i = 1, getn(ids) do
			local disp = M.GetDisplayID(ids[i])
			if disp then
				byDisp[disp] = byDisp[disp] or {}
				tinsert(byDisp[disp], ids[i])
			end
		end
		local added, newGroups, credited = 0, 0, 0
		for _, list in pairs(byDisp) do
			if getn(list) > 1 then
				local group
				for i = 1, getn(list) do group = group or Tmog.ItemDisplayGroup[list[i]] end
				if not group then
					group = getn(Tmog.DisplayGroups) + 1
					Tmog.DisplayGroups[group] = {}
					newGroups = newGroups + 1
				end
				local members, have = Tmog.DisplayGroups[group], {}
				for _, id in pairs(members) do have[id] = true end
				for i = 1, getn(list) do
					local id = list[i]
					if Tmog.ItemDisplayGroup[id] == nil then
						Tmog.ItemDisplayGroup[id] = group
						if not have[id] then tinsert(members, id) have[id] = true added = added + 1 end
					end
				end
			end
		end
		for id, slots in pairs(slotsOf) do
			local g = Tmog.ItemDisplayGroup[id]
			if g then
				for slot in pairs(slots) do
					if TMOG_CACHE[slot] and not TMOG_CACHE[slot][id] then
						for _, m in pairs(Tmog.DisplayGroups[g]) do
							if TMOG_CACHE[slot][m] then TMOG_CACHE[slot][id] = 1 credited = credited + 1 break end
						end
					end
				end
			end
		end
		if not quiet or added > 0 then
			say(format("groups: %d items added, %d new groups, %d newly credited as collected", added, newGroups, credited))
		end
	end, progress)
end

------------------------------------------------------------------------
-- 6. Wear a look on your real character (VanillaHelpers, client-side only)
------------------------------------------------------------------------
function M.Morph(gear)
	if not M.has.vhelpers then return say("VanillaHelpers not loaded") end
	local n = 0
	for slot, id in pairs(gear) do -- outfit tables also hold .name, skipped by the type checks
		if type(slot) == "number" and type(id) == "number" and id > 0 then
			SetUnitVisibleItemID("player", slot + M.slotOffset, id)
			n = n + 1
		end
	end
	say("morphed " .. n .. " slot(s) (local only)")
end

function M.ClearMorph()
	if not M.has.vhelpers then return end
	for _, slot in pairs(Tmog.InventorySlots) do
		pcall(SetUnitVisibleItemID, "player", slot + M.slotOffset) -- TEST: no itemID = reset?
	end
end

------------------------------------------------------------------------
-- 7. Backup / restore through SuperWoW file I/O  (files land in <WoW>\imports)
------------------------------------------------------------------------
function M.Backup()
	if not M.has.superwow then return say("SuperWoW ExportFile/ImportFile not available") end
	local lines = {}
	for _, o in ipairs(TMOG_PLAYER_OUTFITS) do
		local code = "T.O.L."
		for slot, id in pairs(o) do
			if type(slot) == "number" and type(id) == "number" then code = code .. slot .. ":" .. id .. ";" end
		end
		tinsert(lines, o.name .. "\t" .. code)
	end
	ExportFile("Tmog_outfits", concat(lines, "\n"))
	local col = {}
	for slot, items in pairs(TMOG_CACHE) do
		local ids = {}
		for id in pairs(items) do tinsert(ids, id) end
		if getn(ids) > 0 then tinsert(col, slot .. ":" .. concat(ids, ",")) end
	end
	ExportFile("Tmog_collection", concat(col, "\n"))
	say(format("backed up %d outfit(s) and %d collection slot(s)", getn(lines), getn(col))) -- TEST: name may need .txt
end

function M.Restore()
	if not M.has.superwow then return say("SuperWoW ExportFile/ImportFile not available") end
	local text, n = ImportFile("Tmog_outfits"), 0
	if text and text ~= "" then
		for line in gfind(text, "([^\n\r]+)") do
			local _, _, name, code = strfind(line, "^([^\t]+)\t(.+)$")
			local outfit = name and Tmog.ValidateOutfitCode(code)
			if outfit then
				local final, i = name, 2
				while Tmog.GetOutfitByName(final) do final = name .. " (" .. i .. ")" i = i + 1 end
				outfit.name = final
				tinsert(TMOG_PLAYER_OUTFITS, outfit)
				n = n + 1
			end
		end
	end
	local added = 0
	text = ImportFile("Tmog_collection")
	if text and text ~= "" then
		for line in gfind(text, "([^\n\r]+)") do
			local _, _, slot, list = strfind(line, "^(%d+):(.*)$")
			slot = tonumber(slot)
			if slot and TMOG_CACHE[slot] then
				for id in gfind(list, "%d+") do
					id = tonumber(id)
					if not TMOG_CACHE[slot][id] then TMOG_CACHE[slot][id] = 1 added = added + 1 end
				end
			end
		end
	end
	say(format("restored %d outfit(s), %d collection entries", n, added))
	if Tmog.UpdateOutfitButtons then Tmog.UpdateOutfitButtons() end
end

------------------------------------------------------------------------
-- 8. Optional: auto-run group supplement after login (items stay in the client cache)
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function()
	ev:UnregisterEvent("PLAYER_ENTERING_WORLD")
	if M.has.classic and cfg().modernAutoGroups then
		C_Timer.After(15, function() M.SupplementGroups(true) end)
	end
end)

------------------------------------------------------------------------
-- 9. /tmogmod
------------------------------------------------------------------------
SLASH_TMOGMOD1 = "/tmogmod"
SlashCmdList["TMOGMOD"] = function(msg)
	local _, _, cmd, rest = strfind(msg or "", "^(%S*)%s*(.-)$")
	if cmd == "" or cmd == "status" then
		for k, v in pairs(M.has) do say(k .. ": " .. (v and "yes" or "no")) end
		say("auto groups: " .. (cfg().modernAutoGroups and "on" or "off"))
		say("modern cache: " .. (cfg().modernCache == false and "off" or "on"))
	elseif cmd == "groups" then
		if rest == "auto on" then cfg().modernAutoGroups = true say("auto groups on")
		elseif rest == "auto off" then cfg().modernAutoGroups = nil say("auto groups off")
		else M.SupplementGroups() end
	elseif cmd == "cache" then
		cfg().modernCache = (rest ~= "off")
		say("ClassicAPI item cache requests: " .. (cfg().modernCache and "on" or "off (original hidden-tooltip method)"))
	elseif cmd == "audit" then M.AuditGroups()
	elseif cmd == "morph" then
		if rest == "" then M.Morph(Tmog.CurrentGear) -- what the dressing room is showing now
		else
			local o = Tmog.GetOutfitByName(rest)
			if o then M.Morph(o) else say("no outfit named '" .. rest .. "'") end
		end
	elseif cmd == "unmorph" then M.ClearMorph()
	elseif cmd == "backup" then M.Backup()
	elseif cmd == "restore" then M.Restore()
	elseif cmd == "dump" then
		local id = tonumber(rest)
		if not id then return say("/tmogmod dump <itemID>") end
		local d = M.GetItemData(id, function() say("item " .. id .. " cached, run dump again") end)
		if d then
			say(format("%s | equipLoc %s | class %s:%s | allowableClass %s | displayInfoID %s",
				tostring(d.name), tostring(d.equipLoc), tostring(d.classID), tostring(d.subclassID),
				tostring(d.allowableClass), tostring(d.displayInfoID)))
		end
		say("static group: " .. tostring(Tmog.ItemDisplayGroup[id]) .. " | GetItemDisplayID: " .. tostring(GetItemDisplayID and GetItemDisplayID(id)))
		say("slot per Tmog.GetTransmogSlot: " .. tostring(Tmog.GetTransmogSlot(id, "player")))
	else
		say("/tmogmod status | cache on|off | groups [auto on|off] | audit | morph [outfit] | unmorph | backup | restore | dump <itemID>")
	end
end
