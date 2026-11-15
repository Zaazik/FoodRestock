# FoodRestock: design

## Why

When the player opens a vendor window, the addon itself (no clicks) keeps a stock of
permanent (non-conjured) water and food for the character's level. Mage water vanishes after a
relog, so a bought stack must always be in the bags.

## Rules (from the user)

- Target: 1 stack (20) of the best water and 1 stack (20) of the best food for the level.
- Food that restores both health and mana ("combo") replaces the pair: 2 stacks (40).
- A newer (better) water or food at the vendor means the old one is sold.
- Mage (conjured) water and food never count toward the permanent stack; they are never sold.
- Spend at most 4 gold per vendor visit, and never more than the player has.
- Item IDs come from a list built in advance; the reference vendor is Innkeeper Gryshka
  (Orgrimmar, NPC 6929).

## Approaches

1. Read tooltips of vendor goods at run time (rejected by the user).
2. **A prebuilt ID list (picked by the user).** Exact, no tooltip parsing; vendors outside the
   list are ignored.
3. List + tooltip fallback (more code, not needed).

## Data (WoW Forever, checked 2026-11-16)

- Gryshka's goods: Wowhead Forever NPC page (`g_listviews.sells`), 12 items, sold in bundles of 5.
- Restore values and required levels: Wowhead Forever tooltips
  (`nether.wowhead.com/forever/tooltip/item/<id>`). Forever values differ from Classic.
- Combo items: a sweep of all 829 Food & Drink / consumable items of QuestieDB Forever against
  Wowhead Forever tooltips. No cooked combo food exists in Forever. Buyable combos:
  13724 (Argent Dawn, Friendly) and 19301 (Frostwolf, Honored). The rest (20031, 3448, 262433,
  282018, 21215) are only counted when already in the bags.
- Buff foods (Well Fed) and raw fish are not in the lists: they are never bought, counted or sold.

## Behaviour

On vendor open (once per visit, after the vendor's item list has loaded):

1. Combo vendor (sells a usable combo for the level): buy the best combo up to 40 counting combos
   in the bags that are at least as good. Water and food are not touched there.
2. Any other vendor: pick the best water and the best food this vendor sells for the level
   ("best" = largest restore value).
   - If the bags hold 40+ usable combos at least as good as that water and food, buy nothing.
   - Otherwise, per category (water first, then food): permanent items in the bags restoring at
     least as much count toward 20; buy the rest of the best item.
   - Sell permanent items of the category that restore less, but only when the stack of the new
     tier will be full after buying (so selling never leaves the player short).
3. Limits, in order: 4 g budget and player money (water bought before food), vendor stock,
   free bag space. Every cut is reported in chat.
4. Purchase: `BuyMerchantItem(index, count)` with an item count (Forever 1.60.1: a given quantity
   buys exactly that many items; warcraft.wiki.gg `API_BuyMerchantItem`), rounded up to the
   bundle size and capped by `GetMerchantItemMaxStack`. Two seconds later the bag counts are
   checked; a shortfall is printed as an error.

## Calls made by the builder (not decided by the user)

- Selling the old tier waits until the new stack will be full.
- If the bags already hold better permanent water/food than the vendor sells, it counts toward
  the stack and nothing worse is bought on top of it beyond the missing amount.
- Slash command `/frs` (`on`, `off`, `status`) to switch it off without disabling the addon.
- Addon name `FoodRestock`, repo `C:\Users\Admin\WowProjects\FoodRestock`, junction into
  `Interface\AddOns` like the sibling addons.
