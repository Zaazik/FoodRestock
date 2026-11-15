-- Plan.Make: what to sell and buy at a vendor.
return function(ns, T)
	local Plan = ns.Plan

	-- Innkeeper Gryshka's goods in WoW Forever: price per bundle of 5, in copper.
	local function gryshka()
		local list = {
			{ 117, 27 }, { 159, 27 }, { 1179, 118 }, { 1205, 475 }, { 1645, 1900 }, { 1708, 950 },
			{ 2287, 118 }, { 3770, 475 }, { 3771, 950 }, { 4599, 1900 }, { 8766, 3800 }, { 8952, 3800 },
		}
		local offers = {}
		for i, e in ipairs(list) do
			offers[i] = { index = i, id = e[1], name = "item" .. e[1], price = e[2], stackCount = 5,
				numAvailable = -1, isPurchasable = true, isUsable = true, hasExtendedCost = false }
		end
		return offers
	end

	local function state(over)
		local s = { level = 50, money = 1000000, freeSlots = 10, bag = {}, room = {}, usable = {}, offers = gryshka() }
		for k, v in pairs(over or {}) do s[k] = v end
		return s
	end

	local function buyOf(plan, id)
		for _, b in ipairs(plan.buys) do if b.id == id then return b end end
	end
	local function sellOf(plan, id)
		for _, s in ipairs(plan.sells) do if s.id == id then return s end end
	end

	return {
		{ "empty bags at level 50: a stack of the best water and of the best food", function()
			local p = Plan.Make(state())
			T.eq(#p.buys, 2, "two buys")
			T.eq(p.buys[1].id, 8766, "water first")
			T.eq(p.buys[1].count, 20, "water count")
			T.eq(p.buys[1].cost, 15200, "water cost")
			T.eq(p.buys[2].id, 8952, "then food")
			T.eq(p.buys[2].count, 20, "food count")
			T.eq(#p.sells, 0, "nothing to sell")
		end },
		{ "a partial stack is topped up, rounded up to the bundle of 5", function()
			local p = Plan.Make(state({ bag = { [8766] = 7, [8952] = 20 } }))
			T.eq(#p.buys, 1, "only water")
			T.eq(p.buys[1].count, 15, "13 missing -> 15")
			T.eq(p.buys[1].cost, 3 * 3800, "three bundles")
		end },
		{ "full stacks: nothing to do", function()
			local p = Plan.Make(state({ bag = { [8766] = 20, [8952] = 25 } }))
			T.eq(#p.buys, 0, "no buys")
			T.eq(#p.sells, 0, "no sells")
		end },
		{ "older water is sold when the new stack will be full", function()
			local p = Plan.Make(state({ bag = { [1645] = 12, [159] = 3, [8952] = 20 } }))
			T.eq(buyOf(p, 8766).count, 20, "buy new water")
			T.eq(sellOf(p, 1645).count, 12, "sell old water")
			T.eq(sellOf(p, 159).count, 3, "sell oldest water")
			T.eq(sellOf(p, 8952), nil, "current food kept")
		end },
		{ "budget: 4 gold cap, water before food, old food kept when the new stack stays short", function()
			local p = Plan.Make(state({ budget = 20000, bag = { [4599] = 10 } }))
			T.eq(buyOf(p, 8766).count, 20, "water fits")
			T.eq(buyOf(p, 8952).count, 5, "food: 4800 left buys one bundle")
			T.eq(sellOf(p, 4599), nil, "old food not sold: only 5 of the new")
			T.truthy(#p.notes > 0, "the cut is reported")
		end },
		{ "the default budget is 4 gold", function()
			local s = state()
			s.offers[11].price = 9000 -- Morning Glory Dew made expensive: 36000 for a stack
			local p = Plan.Make(s)
			T.eq(buyOf(p, 8766).count, 20, "water 36000")
			T.eq(buyOf(p, 8952).count, 5, "4000 left of 40000: one food bundle of 3800")
		end },
		{ "player money caps the spend", function()
			local p = Plan.Make(state({ money = 7700 }))
			T.eq(buyOf(p, 8766).count, 10, "two bundles of water")
			T.eq(buyOf(p, 8952), nil, "no money left for food")
		end },
		{ "mage water does not count toward the permanent stack and is not sold", function()
			local p = Plan.Make(state({ bag = { [8078] = 20, [8076] = 20 } }))
			T.eq(buyOf(p, 8766).count, 20, "water bought anyway")
			T.eq(buyOf(p, 8952).count, 20, "food bought anyway")
			T.eq(#p.sells, 0, "conjured not sold")
		end },
		{ "level 30: items above the level are skipped", function()
			local p = Plan.Make(state({ level = 30 }))
			T.eq(buyOf(p, 1708).count, 20, "Sweet Nectar")
			T.eq(buyOf(p, 3771).count, 20, "Wild Hog Shank")
			T.eq(buyOf(p, 8766), nil, "no Dew at 30")
		end },
		{ "better water in the bags than the vendor sells counts and is not sold", function()
			local s = state()
			local small = {}
			for _, o in ipairs(s.offers) do if o.id == 1708 or o.id == 3771 then small[#small + 1] = o end end
			s.offers = small
			s.bag = { [8766] = 20, [3771] = 20 }
			local p = Plan.Make(s)
			T.eq(#p.buys, 0, "nothing bought")
			T.eq(#p.sells, 0, "Dew kept")
		end },
		{ "the account-bound Morning Glory Dew counts as the water stack", function()
			local p = Plan.Make(state({ bag = { [287964] = 20, [8952] = 20 } }))
			T.eq(#p.buys, 0, "no buys")
		end },
		{ "40 usable combos in the bags replace water and food", function()
			local p = Plan.Make(state({ level = 55, bag = { [19301] = 40 }, usable = { [19301] = true } }))
			T.eq(#p.buys, 0, "no buys")
			T.eq(#p.sells, 0, "no sells")
		end },
		{ "combos that cannot be used (reputation) do not count", function()
			local p = Plan.Make(state({ bag = { [13724] = 40 }, usable = { [13724] = false } }))
			T.eq(#p.buys, 2, "water and food bought")
		end },
		{ "weak combos do not replace better water and food", function()
			local p = Plan.Make(state({ bag = { [3448] = 40 }, usable = { [3448] = true } }))
			T.eq(#p.buys, 2, "Senggin Root does not replace level 45 water and food")
		end },
		{ "full-restore combos always count", function()
			local p = Plan.Make(state({ bag = { [282018] = 40 }, usable = { [282018] = true } }))
			T.eq(#p.buys, 0, "Restorative Bread replaces the pair")
		end },
		{ "combo vendor: two stacks of the best usable combo", function()
			local offers = {
				{ index = 3, id = 13724, name = "biscuit", price = 1200, stackCount = 5, numAvailable = -1,
					isPurchasable = true, isUsable = true, hasExtendedCost = false },
			}
			local p = Plan.Make(state({ offers = offers, bag = { [13724] = 12 }, usable = { [13724] = true } }))
			T.eq(#p.buys, 1, "one buy")
			T.eq(p.buys[1].index, 3, "merchant index")
			T.eq(p.buys[1].count, 30, "28 missing -> 30")
			T.eq(p.buys[1].cost, 6 * 1200, "six bundles")
		end },
		{ "combo vendor: an unusable combo (no reputation) is not bought", function()
			local offers = {
				{ index = 1, id = 13724, name = "biscuit", price = 1200, stackCount = 5, numAvailable = -1,
					isPurchasable = true, isUsable = false, hasExtendedCost = false },
			}
			local p = Plan.Make(state({ offers = offers }))
			T.eq(#p.buys, 0, "nothing bought")
		end },
		{ "combo above the level is not bought", function()
			local offers = {
				{ index = 1, id = 19301, name = "alterac", price = 1200, stackCount = 5, numAvailable = -1,
					isPurchasable = true, isUsable = true, hasExtendedCost = false },
			}
			local p = Plan.Make(state({ level = 50, offers = offers }))
			T.eq(#p.buys, 0, "19301 needs level 51")
		end },
		{ "no free bag space: nothing bought, reported", function()
			local p = Plan.Make(state({ freeSlots = 0 }))
			T.eq(#p.buys, 0, "no buys")
			T.truthy(#p.notes > 0, "reported")
		end },
		{ "room in an existing stack is used before free slots", function()
			local p = Plan.Make(state({ freeSlots = 0, bag = { [8766] = 10, [8952] = 20 }, room = { [8766] = 10 } }))
			T.eq(buyOf(p, 8766).count, 10, "fills the partial stack")
		end },
		{ "one free slot is shared: water takes it, food is cut", function()
			local p = Plan.Make(state({ freeSlots = 1 }))
			T.eq(buyOf(p, 8766).count, 20, "water")
			T.eq(buyOf(p, 8952), nil, "no slot left for food")
		end },
		{ "limited vendor stock", function()
			local s = state()
			s.offers[11].numAvailable = 2
			local p = Plan.Make(s)
			T.eq(buyOf(p, 8766).count, 10, "two bundles available")
		end },
		{ "items not sold for gold or not purchasable are ignored", function()
			local s = state({ level = 50 })
			s.offers[11].hasExtendedCost = true
			s.offers[12].isPurchasable = false
			local p = Plan.Make(s)
			T.eq(buyOf(p, 1645).count, 20, "falls back to Moonberry Juice")
			T.eq(buyOf(p, 4599).count, 20, "falls back to Cured Ham Steak")
		end },
		{ "a vendor with none of the listed items: nothing to do, nothing reported", function()
			local p = Plan.Make(state({ offers = {} }))
			T.eq(#p.buys, 0, "no buys")
			T.eq(#p.sells, 0, "no sells")
			T.eq(#p.notes, 0, "silent at unrelated vendors")
		end },
	}
end
