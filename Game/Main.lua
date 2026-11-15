-- Events, game state, purchase and sale. Uses the WoW Forever (1.60.1, modern client) API.
local addonName, ns = ...
local Data, Plan = ns.Data, ns.Plan

local PREFIX = "|cff33ff99FoodRestock|r: "
local function say(msg) DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg) end
local function fail(msg) DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. "|cffff4040" .. msg .. "|r") end

local VERIFY_DELAY = 2     -- seconds before bag counts are checked after buying/selling
local LOAD_RETRY_DELAY = 0.3
local LOAD_RETRIES = 10    -- vendor item list not loaded after ~3 s = reported as an error

-- gen changes on every vendor open, so a retry timer left from an earlier visit stops itself.
local visit = { open = false, done = false, tries = 0, gen = 0, timerPending = false }

-- Merchant item info: C_MerchantFrame.GetItemInfo in Forever, GetMerchantItemInfo elsewhere.
local function merchantInfo(i)
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then return C_MerchantFrame.GetItemInfo(i) end
	local name, texture, price, stackCount, numAvailable, isPurchasable, isUsable, hasExtendedCost = GetMerchantItemInfo(i)
	if not name then return nil end
	return { name = name, texture = texture, price = price, stackCount = stackCount, numAvailable = numAvailable,
		isPurchasable = isPurchasable, isUsable = isUsable, hasExtendedCost = hasExtendedCost }
end

local function merchantItemID(i)
	if GetMerchantItemID then return GetMerchantItemID(i) end
	local link = GetMerchantItemLink(i)
	return link and tonumber(link:match("item:(%d+)"))
end

local function isListed(id)
	return Data.WATER[id] or Data.FOOD[id] or Data.COMBO[id] or Data.CONJURED[id]
end

-- Vendor goods; nil while the list is still loading (an item without ID, or a listed item
-- without info or name). Unlisted items only need their ID.
local function readOffers()
	local offers = {}
	for i = 1, GetMerchantNumItems() do
		local id = merchantItemID(i)
		if not id then return nil end
		if isListed(id) then
			local info = merchantInfo(i)
			if not info or not info.name then return nil end
			offers[#offers + 1] = {
				index = i, id = id, name = info.name, price = info.price, stackCount = info.stackCount,
				numAvailable = info.numAvailable, isPurchasable = info.isPurchasable, isUsable = info.isUsable,
				hasExtendedCost = info.hasExtendedCost or info.currencyID ~= nil,
			}
		end
	end
	return offers
end

local function eachBagSlot(fn)
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info then fn(bag, slot, info) end
		end
	end
end

local function readBags()
	local bag, room, freeSlots = {}, {}, 0
	for b = 0, NUM_BAG_SLOTS do
		local free, family = C_Container.GetContainerNumFreeSlots(b)
		if family == 0 then freeSlots = freeSlots + free end
	end
	eachBagSlot(function(_, _, info)
		local id = info.itemID
		if isListed(id) then
			bag[id] = (bag[id] or 0) + info.stackCount
			room[id] = (room[id] or 0) + math.max(0, Data.STACK - info.stackCount)
		end
	end)
	return bag, room, freeSlots
end

local function usableNow(id)
	local f = (C_Item and C_Item.IsUsableItem) or IsUsableItem
	return f(id) and true or false
end

local function itemName(id)
	local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or GetItemInfo(id)
	return name or ("item:" .. id)
end

local function bagCount(id)
	local n = 0
	eachBagSlot(function(_, _, info) if info.itemID == id then n = n + info.stackCount end end)
	return n
end

-- Sells every stack of `id`; returns how many items were sent for sale.
local function sell(id)
	local n = 0
	eachBagSlot(function(bag, slot, info)
		if info.itemID == id and not info.isLocked then
			C_Container.UseContainerItem(bag, slot)
			n = n + info.stackCount
		end
	end)
	return n
end

-- Buys `count` items in calls no larger than the vendor allows, each a whole number of bundles.
local function buy(b, stackCount)
	local maxPerCall = GetMerchantItemMaxStack(b.index)
	if not maxPerCall or maxPerCall <= 0 then maxPerCall = b.count end
	local chunk = math.max(stackCount, math.floor(maxPerCall / stackCount) * stackCount)
	local left = b.count
	while left > 0 do
		local n = math.min(chunk, left)
		BuyMerchantItem(b.index, n)
		left = left - n
	end
end

-- fromTimer: true on the retry timer path. Only that path counts tries and schedules the next
-- retry; MERCHANT_UPDATE just attempts a read, so there is one retry chain per visit.
local run
local function scheduleRetry()
	if visit.timerPending then return end
	visit.timerPending = true
	local gen = visit.gen
	C_Timer.After(LOAD_RETRY_DELAY, function()
		if gen ~= visit.gen then return end
		visit.timerPending = false
		run(true)
	end)
end

run = function(fromTimer)
	if not visit.open or visit.done then return end
	if not FoodRestockDB.enabled then visit.done = true return end

	local offers = readOffers()
	if not offers then
		if fromTimer then
			visit.tries = visit.tries + 1
			if visit.tries >= LOAD_RETRIES then
				visit.done = true
				fail("список товаров торговца не загрузился, покупка пропущена")
				return
			end
		end
		scheduleRetry()
		return
	end
	visit.done = true

	local bag, room, freeSlots = readBags()
	local usable = {}
	for id in pairs(Data.COMBO) do if bag[id] then usable[id] = usableNow(id) end end

	local plan = Plan.Make({
		level = UnitLevel("player"), money = GetMoney(), freeSlots = freeSlots,
		bag = bag, room = room, usable = usable, offers = offers,
	})
	for _, note in ipairs(plan.notes) do say(note) end
	if #plan.buys == 0 and #plan.sells == 0 then return end

	local stackOf = {}
	for _, o in ipairs(offers) do stackOf[o.index] = o.stackCount end

	local expect = {} -- id -> bag count expected after the purchase
	local lines = {}
	for _, s in ipairs(plan.sells) do
		local before = bagCount(s.id)
		local sent = sell(s.id)
		expect[s.id] = before - sent
		lines[#lines + 1] = string.format("продаю %d × %s", sent, itemName(s.id))
	end
	for _, b in ipairs(plan.buys) do
		expect[b.id] = (expect[b.id] or bagCount(b.id)) + b.count
		buy(b, stackOf[b.index])
		lines[#lines + 1] = string.format("покупаю %d × %s (%s)", b.count, b.name, Plan.Money(b.cost))
	end
	say(table.concat(lines, "; "))

	C_Timer.After(VERIFY_DELAY, function()
		for id, want in pairs(expect) do
			local got = bagCount(id)
			if got ~= want then
				fail(string.format("%s: в сумках %d, ожидалось %d — покупка или продажа не прошла", itemName(id), got, want))
			end
		end
	end)
end

local function status()
	local bag = readBags()
	local function sum(list)
		local n = 0
		for id, c in pairs(bag) do if list[id] then n = n + c end end
		return n
	end
	local conjured = 0
	for id, c in pairs(bag) do if Data.CONJURED[id] then conjured = conjured + c end end
	say(string.format("%s. В сумках: вода %d, еда %d, здоровье+мана %d, магическая %d (не считается).",
		FoodRestockDB.enabled and "включён" or "выключен", sum(Data.WATER), sum(Data.FOOD), sum(Data.COMBO), conjured))
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("MERCHANT_UPDATE")
frame:RegisterEvent("MERCHANT_CLOSED")
frame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == addonName then
			FoodRestockDB = FoodRestockDB or {}
			if FoodRestockDB.enabled == nil then FoodRestockDB.enabled = true end
		end
	elseif event == "MERCHANT_SHOW" then
		visit.gen = visit.gen + 1
		visit.open, visit.done, visit.tries, visit.timerPending = true, false, 0, false
		-- MERCHANT_SHOW can come before item data is cached; the first read is on the next frame.
		local gen = visit.gen
		C_Timer.After(0, function() if gen == visit.gen then run(false) end end)
	elseif event == "MERCHANT_UPDATE" then
		if visit.open and not visit.done then run(false) end
	elseif event == "MERCHANT_CLOSED" then
		visit.open = false
		visit.gen = visit.gen + 1
	end
end)

SLASH_FOODRESTOCK1 = "/frs"
SlashCmdList.FOODRESTOCK = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "on" then
		FoodRestockDB.enabled = true
		say("включён")
	elseif msg == "off" then
		FoodRestockDB.enabled = false
		say("выключен")
	elseif msg == "status" or msg == "" then
		status()
	else
		say("команды: /frs on, /frs off, /frs status")
	end
end
