-- Game/Main.lua against a mocked WoW API: event timing, buying and selling.
return function(_, T)
	local root = (arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]run%.lua$")) or "."

	-- Builds a fresh mocked client and loads the addon into it. Returns the mock.
	local function client(opts)
		local m = { timers = {}, now = 0, chat = {}, bought = {}, used = {}, ready = opts.ready ~= false }
		local env = setmetatable({}, { __index = _G })
		m.env = env
		env.NUM_BAG_SLOTS = 0
		env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) m.chat[#m.chat + 1] = msg end }
		env.C_Timer = { After = function(d, fn) m.timers[#m.timers + 1] = { at = m.now + d, fn = fn } end }
		env.UnitLevel = function() return opts.level or 50 end
		env.GetMoney = function() return opts.money or 1000000 end
		env.GetMerchantNumItems = function() return #opts.goods end
		env.GetMerchantItemID = function(i) return m.ready and opts.goods[i].id or nil end
		env.GetMerchantItemMaxStack = function() return 20 end
		env.C_MerchantFrame = { GetItemInfo = function(i)
			local g = opts.goods[i]
			if not m.ready then return nil end
			return { name = "n" .. g.id, price = g.price, stackCount = 5, numAvailable = -1,
				isPurchasable = true, isUsable = true, hasExtendedCost = false }
		end }
		env.BuyMerchantItem = function(i, n) m.bought[#m.bought + 1] = { id = opts.goods[i].id, n = n } end
		local slots = opts.slots or {}
		env.C_Container = {
			GetContainerNumSlots = function() return 16 end,
			GetContainerItemInfo = function(_, s) local x = slots[s]; return x and { itemID = x[1], stackCount = x[2] } end,
			GetContainerNumFreeSlots = function() local n = 16; for _ in pairs(slots) do n = n - 1 end return n, 0 end,
			UseContainerItem = function(_, s) m.used[#m.used + 1] = slots[s][1] end,
		}
		env.C_Item = { IsUsableItem = function() return true end, GetItemNameByID = function(id) return "n" .. id end }
		local handler
		env.CreateFrame = function()
			return { RegisterEvent = function() end, SetScript = function(_, _, fn) handler = fn end }
		end
		env.SlashCmdList = {}
		env.FoodRestockDB = nil
		local ns = {}
		for _, f in ipairs({ "Core/Data.lua", "Core/Plan.lua", "Game/Main.lua" }) do
			local chunk = assert(loadfile(root .. "/" .. f, "t", env))
			chunk("FoodRestock", ns)
		end
		function m.event(e, a) handler(nil, e, a) end
		function m.advance(sec)
			local stop = m.now + sec
			while true do
				table.sort(m.timers, function(a, b) return a.at < b.at end)
				local t = m.timers[1]
				if not t or t.at > stop then break end
				table.remove(m.timers, 1)
				m.now = t.at
				t.fn()
			end
			m.now = stop
		end
		m.event("ADDON_LOADED", "FoodRestock")
		return m
	end

	local GRYSHKA = { { id = 1645, price = 1900 }, { id = 8766, price = 3800 }, { id = 4599, price = 1900 }, { id = 8952, price = 3800 } }

	return {
		{ "game: buys water and food on vendor open", function()
			local m = client({ goods = GRYSHKA })
			m.event("MERCHANT_SHOW")
			m.advance(0.1)
			T.eq(#m.bought, 2, "two purchases")
			T.eq(m.bought[1].id, 8766, "water")
			T.eq(m.bought[1].n, 20, "item count, not bundles")
			T.eq(m.bought[2].id, 8952, "food")
		end },
		{ "game: sells the old tier", function()
			local m = client({ goods = GRYSHKA, slots = { [1] = { 1645, 12 }, [2] = { 8952, 20 } } })
			m.event("MERCHANT_SHOW")
			m.advance(0.1)
			T.eq(#m.used, 1, "one stack sold")
			T.eq(m.used[1], 1645, "Moonberry Juice sold")
		end },
		{ "game: MERCHANT_UPDATE spam while loading does not use up the retries", function()
			local m = client({ goods = GRYSHKA, ready = false })
			m.event("MERCHANT_SHOW")
			for _ = 1, 30 do m.event("MERCHANT_UPDATE") end
			m.advance(2)
			for _ = 1, 30 do m.event("MERCHANT_UPDATE") end
			m.ready = true
			m.advance(0.5)
			T.eq(#m.bought, 2, "bought once the list loaded")
			for _, c in ipairs(m.chat) do
				T.truthy(not c:find("не загрузился"), "no load error: " .. c)
			end
		end },
		{ "game: a list that never loads is reported after the retries", function()
			local m = client({ goods = GRYSHKA, ready = false })
			m.event("MERCHANT_SHOW")
			m.advance(5)
			local reported = false
			for _, c in ipairs(m.chat) do if c:find("не загрузился") then reported = true end end
			T.truthy(reported, "error printed")
			T.eq(#m.bought, 0, "nothing bought")
		end },
		{ "game: an old visit's retry timer does not run into a new visit", function()
			local m = client({ goods = GRYSHKA, ready = false })
			m.event("MERCHANT_SHOW")
			m.advance(0.4)
			m.event("MERCHANT_CLOSED")
			m.event("MERCHANT_SHOW")
			m.advance(2.5)
			for _, c in ipairs(m.chat) do
				T.truthy(not c:find("не загрузился"), "only ~2.5 s into the new visit: " .. c)
			end
			T.eq(#m.timers, 1, "a single retry chain")
		end },
		{ "game: /frs off stops purchases", function()
			local m = client({ goods = GRYSHKA })
			m.env.SlashCmdList.FOODRESTOCK("off")
			m.event("MERCHANT_SHOW")
			m.advance(0.1)
			T.eq(#m.bought, 0, "off: nothing bought")
			m.event("MERCHANT_CLOSED")
			m.env.SlashCmdList.FOODRESTOCK("on")
			m.event("MERCHANT_SHOW")
			m.advance(0.1)
			T.eq(#m.bought, 2, "on again: bought")
		end },
	}
end
