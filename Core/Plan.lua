-- What to sell and buy at a vendor. Pure Lua 5.1: no WoW API here.
--
-- Plan.Make(state) -> { sells = { {id, count} }, buys = { {index, id, name, count, cost} }, notes = { string } }
-- state:
--   level      player level
--   money      player copper
--   budget     spend cap in copper (default Data.BUDGET, 4 gold)
--   freeSlots  empty slots in general-purpose bags
--   bag        [itemID] = count in the bags
--   room       [itemID] = free space left in existing stacks of that item
--   usable     [itemID] = true when the player can use that combo item now (level, reputation)
--   offers     list of { index, id, name, price, stackCount, numAvailable, isPurchasable, isUsable, hasExtendedCost }
--              price is per bundle of stackCount items; numAvailable -1 = unlimited, else bundles left

local _, ns = ...
local Data = ns.Data
local Plan = {}
ns.Plan = Plan

local floor, ceil, min = math.floor, math.ceil, math.min

local function money(c)
	local g, s, k = floor(c / 10000), floor(c / 100) % 100, c % 100
	if g > 0 then return string.format("%dз %dс", g, s) end
	if s > 0 then return string.format("%dс %dм", s, k) end
	return string.format("%dм", k)
end
Plan.Money = money

-- A vendor item that can be bought for gold and used at this level.
local function buyable(o, info, level)
	return info ~= nil and info.level <= level and not o.hasExtendedCost and o.isPurchasable == true
		and o.isUsable == true and (o.price or 0) > 0 and (o.stackCount or 0) > 0 and o.numAvailable ~= 0
end

-- Best vendor item of a list by a value function.
local function bestOffer(offers, list, level, value)
	local best, bestValue
	for _, o in ipairs(offers) do
		local info = list[o.id]
		if buyable(o, info, level) then
			local v = value(info)
			if not best or v > bestValue then best, bestValue = o, v end
		end
	end
	return best, bestValue
end

-- Sum of bag items of a list that are usable at this level and pass a filter.
local function countBag(state, list, pass)
	local n = 0
	for id, count in pairs(state.bag) do
		local info = list[id]
		if info and info.level <= state.level and pass(id, info) then n = n + count end
	end
	return n
end

local function comboAtLeast(info, health, mana)
	if info.full then return true end
	return info.health >= health and info.mana >= mana
end

-- Buys up to `need` items of offer `o` inside money, stock and bag space; returns the count bought.
local function addBuy(plan, ctx, o, need)
	local wanted = ceil(need / o.stackCount)
	local units = wanted
	local limits = {}

	if o.numAvailable and o.numAvailable > 0 and units > o.numAvailable then
		units = o.numAvailable
		limits[#limits + 1] = "у торговца столько нет"
	end
	local affordable = floor(ctx.spendLeft / o.price)
	if units > affordable then
		units = affordable
		limits[#limits + 1] = ctx.moneyLeft < ctx.budgetLeft and "не хватает денег" or ("лимит " .. money(ctx.budget))
	end
	local fit = floor(((ctx.room[o.id] or 0) + ctx.freeSlots * Data.STACK) / o.stackCount)
	if units > fit then
		units = fit
		limits[#limits + 1] = "нет места в сумках"
	end

	if units < wanted then
		plan.notes[#plan.notes + 1] = string.format("%s: нужно %d, куплю %d (%s)",
			o.name or ("item:" .. o.id), wanted * o.stackCount, units * o.stackCount, table.concat(limits, ", "))
	end
	if units <= 0 then return 0 end

	local count, cost = units * o.stackCount, units * o.price
	plan.buys[#plan.buys + 1] = { index = o.index, id = o.id, name = o.name, count = count, cost = cost }
	ctx.spendLeft = ctx.spendLeft - cost
	ctx.budgetLeft = ctx.budgetLeft - cost
	ctx.moneyLeft = ctx.moneyLeft - cost
	local intoRoom = min(count, ctx.room[o.id] or 0)
	local rest = count - intoRoom
	local slots = ceil(rest / Data.STACK)
	ctx.freeSlots = ctx.freeSlots - slots
	ctx.room[o.id] = (ctx.room[o.id] or 0) - intoRoom + (slots * Data.STACK - rest)
	return count
end

function Plan.Make(state)
	local plan = { sells = {}, buys = {}, notes = {} }
	local budget = state.budget or Data.BUDGET
	local ctx = {
		budget = budget,
		budgetLeft = budget,
		moneyLeft = state.money,
		spendLeft = min(budget, state.money),
		freeSlots = state.freeSlots,
		room = {},
	}
	for id, r in pairs(state.room or {}) do ctx.room[id] = r end
	local level = state.level
	local function comboUsable(id) return state.usable ~= nil and state.usable[id] == true end

	-- 1. A vendor that sells a usable combo: two stacks of the best one. Water and food not touched.
	local combo = bestOffer(state.offers, Data.COMBO, level, function(info)
		if info.full then return math.huge end
		return info.health + info.mana
	end)
	if combo then
		local ci = Data.COMBO[combo.id]
		local have = countBag(state, Data.COMBO, function(id, info)
			return comboUsable(id) and comboAtLeast(info, ci.health or 0, ci.mana or 0)
		end)
		if have < Data.COMBO_TARGET then addBuy(plan, ctx, combo, Data.COMBO_TARGET - have) end
		return plan
	end

	-- 2. Water and food.
	local water, waterValue = bestOffer(state.offers, Data.WATER, level, function(info) return info.mana end)
	local food, foodValue = bestOffer(state.offers, Data.FOOD, level, function(info) return info.health end)
	if not water and not food then return plan end

	local combos = countBag(state, Data.COMBO, function(id, info)
		return comboUsable(id) and comboAtLeast(info, foodValue or 0, waterValue or 0)
	end)
	if combos >= Data.COMBO_TARGET then return plan end

	local categories = {
		{ offer = water, value = waterValue, list = Data.WATER, field = "mana", target = Data.WATER_TARGET },
		{ offer = food, value = foodValue, list = Data.FOOD, field = "health", target = Data.FOOD_TARGET },
	}
	for _, c in ipairs(categories) do
		if c.offer then
			local have = countBag(state, c.list, function(_, info) return info[c.field] >= c.value end)
			local bought = 0
			if have < c.target then bought = addBuy(plan, ctx, c.offer, c.target - have) end
			-- The old tier goes only once the new stack is full, so selling never leaves the player short.
			if have + bought >= c.target then
				for id, count in pairs(state.bag) do
					local info = c.list[id]
					if info and count > 0 and info[c.field] < c.value then
						plan.sells[#plan.sells + 1] = { id = id, count = count }
					end
				end
			end
		end
	end
	table.sort(plan.sells, function(a, b) return a.id < b.id end)
	return plan
end
