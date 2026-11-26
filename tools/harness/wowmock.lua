-- wowmock.lua: a believable WoW Forever (client 1.60.1, Interface 16001, game type "camelot") for offline tests.
-- Loaded by run.py into a fresh Lua 5.1 state before the addon. `H` is the harness table: it holds the
-- simulated world (clock, events, inventory, unit state) and the helpers scenarios use.
--
-- Layout (each part receives H):
--   mock/env.lua        Lua sandbox, WoW global helpers, error trap, clock, C_Timer, events
--   mock/widgets.lua    widgets (CreateFrame), scripts, event registration, visibility
--   mock/xml.lua        XML loader: frames, $parent, parentKey, inherits, layers, inline scripts
--   mock/items.lua      item database, links, C_Item
--   mock/inventory.lua  equipment, bags, bank tabs, cursor, equip rules, C_Container, C_Bank
--   mock/world.lua      unit state, combat, secrets, specs, zones/maps, spells, misc APIs
--   mock/blizzui.lua    Blizzard frames, GameTooltip, StaticPopup, Settings, dropdowns, strings
--   mock/assert.lua     assertions and scenario helpers
--
-- Scenario API (H.*), by topic:
--   time/events  advance(sec) step fire(event, ...) fireUnit(event, unit, ...) waitFor(fn, timeout)
--   player       setCombat setRestricted setSpecGroup(n, {cast=true}) cast setAFK setPvP setMounted
--                setStealthed setSwimming setDead setGroup setForm addNameplate setZone(key)
--   items        give(key|inst, {bag, slot}) equip(key, slot) playerEquip(key|inst, slot) fillBags removeFromBags
--                find(key) countItem totalItems itemLink(inst) dumpInventory newItem(key, {enchant})
--   places       openBank closeBank openMerchant openCharacterFrame closeCharacterFrame hoverInventorySlot
--                hoverBagItem acceptPopup cancelPopup clickMenuEntry slash("/gq ...")
--   switches     switchTo(gq, set) wearSetBPieces SET_A SET_B SET_B_PIECES
--   asserts      assertEq/True/False assertEquipped(slot, key|nil) assertWearing(map) assertInBags(key, n)
--                assertInBank assertNoGearInSpecialBags assertCursorEmpty assertTotalItems assertNoUiErrors
--                assertSetMatchesGear(gq, set) assertChat/assertChatAny/assertNoChat assertNoErrors fail log
--   knobs        latency blockCombatPickups strictSecrets syncCursorLockEvents player.* zone
--   logs         errors warnings chat uiErrors blocked secretReads eventLog sounds popups
local H = ...;

H.include("mock/env.lua");
H.include("mock/widgets.lua");
H.include("mock/xml.lua");
H.include("mock/items.lua");
H.include("mock/inventory.lua");
H.include("mock/world.lua");
H.include("mock/blizzui.lua");
H.include("mock/assert.lua");

return H;
