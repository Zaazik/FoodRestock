-- Item lists for WoW Forever. Pure Lua 5.1: no WoW API here.
-- Sources (checked 2026-11-16): restore values and required levels from Wowhead Forever tooltips
-- (nether.wowhead.com/forever/tooltip/item/<id>); Innkeeper Gryshka's goods (Orgrimmar, NPC 6929)
-- from the Wowhead Forever NPC page; combo items from a sweep of QuestieDB Forever consumables.
-- Forever values differ from Classic (e.g. Morning Glory Dew restores 2821 mana, not 2934).

local _, ns = ...
local Data = {}
ns.Data = Data

Data.STACK = 20        -- max stack of every item below (Wowhead Forever tooltips)
Data.WATER_TARGET = 20 -- one stack of water
Data.FOOD_TARGET = 20  -- one stack of food
Data.COMBO_TARGET = 40 -- two stacks of health+mana food instead of the pair
Data.BUDGET = 40000    -- 4 gold per vendor visit, in copper

-- Permanent water: mana restored, required level.
Data.WATER = {
	[159]    = { mana = 151,  level = 1 },  -- Refreshing Spring Water (Gryshka)
	[1179]   = { mana = 437,  level = 5 },  -- Ice Cold Milk (Gryshka)
	[1205]   = { mana = 835,  level = 15 }, -- Melon Juice (Gryshka)
	[1708]   = { mana = 1345, level = 25 }, -- Sweet Nectar (Gryshka)
	[1645]   = { mana = 1915, level = 35 }, -- Moonberry Juice (Gryshka)
	[8766]   = { mana = 2821, level = 45 }, -- Morning Glory Dew (Gryshka)
	[287964] = { mana = 2821, level = 1 },  -- Morning Glory Dew, Forever account-bound copy (not sold)
}

-- Permanent food without a Well Fed buff: health restored, required level.
Data.FOOD = {
	[117]    = { health = 59,   level = 1 },  -- Tough Jerky (Gryshka)
	[2287]   = { health = 234,  level = 5 },  -- Haunch of Meat (Gryshka)
	[3770]   = { health = 531,  level = 15 }, -- Mutton Chop (Gryshka)
	[3771]   = { health = 841,  level = 25 }, -- Wild Hog Shank (Gryshka)
	[4599]   = { health = 1338, level = 35 }, -- Cured Ham Steak (Gryshka)
	[8952]   = { health = 2065, level = 45 }, -- Roasted Quail (Gryshka)
	[287963] = { health = 2065, level = 1 },  -- Roasted Quail, Forever account-bound copy (not sold)
}

-- Food restoring both health and mana. full = restores 100% of both (counts as the best).
Data.COMBO = {
	[13724]  = { health = 2065, mana = 4240, level = 45 }, -- Enriched Manna Biscuit (Argent Dawn quartermasters, Friendly)
	[19301]  = { health = 4240, mana = 4240, level = 51 }, -- Alterac Manna Biscuit (Frostwolf supply officers, Honored)
	[20031]  = { health = 2452, mana = 4240, level = 55 }, -- Essence Mango (quest reward only)
	[3448]   = { health = 283,  mana = 283,  level = 1 },  -- Senggin Root (quest reward only)
	[262433] = { health = 4240, mana = 4240, level = 1 },  -- Ketharas' Hyjal Stew (quest reward only)
	[282018] = { full = true,                level = 1 },  -- Restorative Bread (100% health and mana)
	[21215]  = { full = true,                level = 40 }, -- Graccu's Mince Meat Fruitcake (5%/sec for 20 sec)
}

-- Mage food and water: never counted toward the permanent stock, never sold. Shown by /frs status.
Data.CONJURED = {
	[5350] = "water", [2288] = "water", [2136] = "water", [3772] = "water",
	[8077] = "water", [8078] = "water", [8079] = "water",
	[5349] = "food", [1113] = "food", [1114] = "food", [1487] = "food",
	[8075] = "food", [8076] = "food", [22895] = "food",
}
