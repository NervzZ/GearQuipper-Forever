-- wowmock.lua: a believable WoW Forever (client 1.60.1, Interface 16001, game type "camelot") for offline tests.
-- Loaded by run.py into a fresh Lua 5.1 state before the addon. `H` is the harness table: it holds the
-- simulated world (clock, events, inventory, unit state) and the helpers scenarios use.
--
-- Layout (each part receives H):
--   mock/env.lua        Lua sandbox, WoW global helpers, error trap, clock, C_Timer, events
--   mock/shared.lua     Blizzard SharedXML utilities: CallbackRegistryMixin, table enumerators, AnchorUtil, Round...
--   mock/widgets.lua    widgets (CreateFrame), scripts (+ intrinsic handlers), events, visibility, template registry
--                       (an unknown template or font object is a recorded Lua error: the scenario fails)
--   mock/fonts.lua      font objects of the Forever client (data)
--   mock/xml.lua        XML loader: frames, $parent, parentKey, inherits, layers, inline scripts
--   mock/items.lua      item database, links, C_Item
--   mock/inventory.lua  equipment, bags, bank tabs, cursor, equip rules, C_Container, C_Bank
--   mock/world.lua      unit state, combat, secrets, specs, zones/maps, spells, misc APIs
--   mock/soundkit.lua   SOUNDKIT of the Forever client (data)
--   mock/intrinsics.lua EventFrame/EventButton, ItemButton (+ SetItemButton* globals), DropdownButton structure,
--                       builders for template mocks (H.addTexture / addFontString / addChild)
--   mock/blizzui.lua    Blizzard frames, GameTooltip, StaticPopup, Settings, legacy dropdowns, strings
--   mock/templates.lua  modern panel templates: DefaultPanel*, InsetFrame, NineSlice, close buttons, tabs +
--                       PanelTemplates_*, SharedButton*, UIPanelButton, UICheckButton, MinimalCheckbox
--   mock/scroll.lua     DataProvider, WowScrollBoxList + linear view, MinimalScrollBar, ScrollUtil
--   mock/menu.lua       MenuUtil, Menu manager, DropdownButton, WowStyle1/2 dropdown templates
--   mock/colorpicker.lua ColorPickerFrame (Blizzard_ColorPickerFrame, Mainline)
--   mock/merchant.lua   buyback list + sell paths, money, item GUIDs / ItemLocation / C_Cursor, Blizzard's
--                       delete / refund / trade-timer popups (StaticPopup2-4) + PopupEventManager
--   mock/gamepad.lua    the popups' gamepad button sequence (one-shot per popup frame, as on Forever)
--   mock/suites.lua     EllesmereUI / ElvUI stubs (scenario field `suites`, or H.installSuites from setup)
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
--   widgets      mouseEnter mouseLeave mouseDown(frame) mouseWheel(frame, delta) fireScript state(obj) templateInfo
--   lists        scrollBoxFrames(box) scrollBoxFrameFor(box, pred|elementData) scrollStep(bar, "Forward"|"Back")
--   menus        openDropdown(dd) pickDropdown(dd, text[, subtext...]) dropdownText(dd) dropdownEntries(dd)
--                menuEntries() clickMenuEntry(text) closeMenus()
--   suites       installSuites{EllesmereUI=opts, ElvUI=opts} suiteCalls suiteCallsFor(w) countSuiteCalls(p, w)
--                clearSuiteCalls suiteFail(p, on) euiToggleOn() euiRestrip() euiItemBorder(button)
--   asserts      assertEq/True/False assertEquipped(slot, key|nil) assertWearing(map) assertInBags(key, n)
--                assertInBank assertNoGearInSpecialBags assertCursorEmpty assertTotalItems assertNoUiErrors
--                assertSetMatchesGear(gq, set) assertChat/assertChatAny/assertNoChat assertNoErrors fail log
--   knobs        latency blockCombatPickups strictSecrets syncCursorLockEvents player.* zone
--   logs         errors warnings chat uiErrors blocked secretReads eventLog sounds popups
--   merchant     sellBagItem dragToMerchant sellAllJunk closeMerchant bagSlotOf buyback buybackCalls money
--   popups       blizzPopup clickPopup typeInPopup enterInPopup deleteItem gamepadDeleteItem gamepadConfirm
--                simulateAutoFillDelete simulateLeatrixEasyDestroy deleted refunded (mock/merchant.lua)
local H = ...;

H.include("mock/env.lua");
H.include("mock/shared.lua");
H.include("mock/widgets.lua");
H.include("mock/xml.lua");
H.include("mock/items.lua");
H.include("mock/inventory.lua");
H.include("mock/world.lua");
H.include("mock/soundkit.lua");
H.include("mock/intrinsics.lua");
H.include("mock/blizzui.lua");
H.include("mock/templates.lua");
H.include("mock/scroll.lua");
H.include("mock/menu.lua");
H.include("mock/colorpicker.lua");
H.include("mock/merchant.lua");
H.include("mock/gamepad.lua");
H.include("mock/suites.lua");
H.include("mock/assert.lua");

return H;
