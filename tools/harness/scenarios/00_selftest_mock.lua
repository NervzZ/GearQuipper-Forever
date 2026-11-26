-- Self-test of the mock (no addon): cursor/equip semantics, events, links, combat, secrets, timers, XML, bank.
return {
    noAddon = true,
    latency = 0, -- the latency section below switches it on by itself
    run = function(H)
        local total = H.totalItems();

        -- links: Forever format, spec id follows the active spec group
        local link = GetInventoryItemLink("player", 1);
        H.assertTrue(link:find("|Hitem:%d+::::::::60:1482::1:::::::|h%[Helm of the Bastion%]|h|r$"), "link format: " .. link);
        local seen = {};
        local f = CreateFrame("Frame");
        f:SetScript("OnEvent", function(self, event, ...)
            seen[#seen + 1] = event .. ":" .. table.concat({tostringall(...)}, ",");
        end);
        f:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED");
        f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED");
        f:RegisterEvent("BAG_UPDATE_DELAYED");
        f:RegisterEvent("UI_ERROR_MESSAGE");
        f:RegisterEvent("ADDON_ACTION_BLOCKED");
        f:RegisterUnitEvent("PLAYER_FLAGS_CHANGED", "player");
        H.setSpecGroup(2);
        H.assertTrue(GetInventoryItemLink("player", 1):find(":60:1483:"), "spec id changes with the spec group");
        H.assertEq(seen[1], "ACTIVE_TALENT_GROUP_CHANGED:2,1");
        H.setSpecGroup(1);

        -- unit-event filter
        seen = {};
        H.fireUnit("PLAYER_FLAGS_CHANGED", "nameplate4");
        H.fireUnit("PLAYER_FLAGS_CHANGED", "player");
        H.assertEq(#seen, 1, "RegisterUnitEvent filters by unit");

        -- cursor: pick up locks the item in place; clearing unlocks it
        PickupInventoryItem(1);
        H.assertTrue(CursorHasItem(), "cursor has the helm");
        H.assertTrue(IsInventoryItemLocked(1), "helm locked while on the cursor");
        H.assertEquipped(1, "headA", "item stays in its slot while on the cursor");
        ClearCursor();
        H.assertFalse(IsInventoryItemLocked(1), "unlocked after ClearCursor");

        -- equip from the bags swaps with the worn item; events arrive on the next frame
        seen = {};
        local bagOfHeadB = H.find("headB")[1];
        C_Item.EquipItemByName(H.itemLink({item = H.items.headB, id = H.items.headB.id}), 1);
        H.assertEquipped(1, "headB");
        H.assertTrue(H.bags[bagOfHeadB.bag].slots[bagOfHeadB.slot].key == "headA", "worn helm goes to the freed cell");
        H.assertEq(#seen, 0, "events are not dispatched synchronously");
        H.advance(0);
        H.assertEq(seen[1], "PLAYER_EQUIPMENT_CHANGED:1,false");
        H.advance(0);
        H.assertEq(seen[#seen], "BAG_UPDATE_DELAYED:", "BAG_UPDATE_DELAYED one frame later");

        -- two-hander: the off-hand goes to a free bag slot
        C_Item.EquipItemByName("Greatsword of Testing", 16);
        H.assertEquipped(16, "greatsword");
        H.assertEquipped(17, nil);
        H.assertInBags("sword");
        H.assertInBags("shield");
        -- off-hand while wielding a 2H: the 2H goes to the bags (into the shield's freed cell)
        C_Item.EquipItemByName("Wall of Testing", 17);
        H.assertEquipped(17, "shield");
        H.assertEquipped(16, nil);
        H.assertInBags("greatsword");
        C_Item.EquipItemByName("Blade of Testing", 16);
        H.assertEquipped(16, "sword");
        -- 2H with full bags: refused with "Inventory is full."
        local added = H.fillBags();
        H.advance(0);
        C_Item.EquipItemByName("Greatsword of Testing", 16);
        H.assertEquipped(16, "sword", "2H refused when the off-hand has nowhere to go");
        H.assertEquipped(17, "shield");
        H.assertEq(H.uiErrors[#H.uiErrors].key, "ERR_INV_FULL");
        H.assertCursorEmpty();
        for _ = 1, added do
            H.removeFromBags("junk");
        end

        -- gear never goes into the quiver
        PickupInventoryItem(1);
        C_Container.PickupContainerItem(3, 5);
        H.assertEq(H.uiErrors[#H.uiErrors].key, "ERR_ITEM_DOESNT_GO_INTO_BAG");
        ClearCursor();
        PickupInventoryItem(1);
        PutItemInBag(C_Container.ContainerIDToInventoryID(3));
        H.assertEquipped(1, "headB", "quiver refuses gear");
        ClearCursor();
        H.assertNoGearInSpecialBags();

        -- MH <-> OH swap of two one-handers
        H.playerEquip("mace", 17);
        H.assertEquipped(17, "mace");
        C_Item.EquipItemByName("Mace of Testing", 16);
        H.assertEquipped(16, "mace");
        H.assertEquipped(17, "sword");

        -- combat: armour refused, weapons allowed; blocked pickups fire ADDON_ACTION_BLOCKED
        H.setCombat(true);
        C_Item.EquipItemByName("Helm of the Bastion", 1);
        H.assertEquipped(1, "headB", "no armour swap in combat");
        H.assertEq(H.uiErrors[#H.uiErrors].key, "ERR_NOT_IN_COMBAT");
        C_Item.EquipItemByName("Blade of Testing", 16);
        H.assertEquipped(16, "sword", "weapon swap allowed in combat");
        H.blockCombatPickups = true;
        seen = {};
        C_Item.EquipItemByName("Mace of Testing", 16);
        H.assertEquipped(16, "sword", "blocked");
        H.assertEq(seen[1], "ADDON_ACTION_BLOCKED:" .. H.addonName .. ",EquipItemByName()");
        H.blockCombatPickups = false;
        H.setCombat(false);

        -- secrets
        H.setRestricted(true);
        local afk = UnitIsAFK("player");
        H.assertTrue(issecretvalue(afk), "UnitIsAFK is secret in a restricted zone");
        H.assertFalse(pcall(function() return afk < 1 end), "ordering a secret errors");
        H.assertFalse(pcall(function() return "x" .. afk end), "concatenating a secret errors");
        H.setRestricted(false);
        H.assertFalse(UnitIsAFK("player"));

        -- timers and the error trap
        local fired = false;
        C_Timer.After(1, function() fired = true; error("boom"); end);
        H.advance(0.9);
        H.assertFalse(fired, "timer not due yet");
        H.advance(0.2);
        H.assertTrue(fired, "timer ran");
        H.assertEq(#H.errors, 1, "timer error recorded");
        H.errors = {};

        -- XML builder: template with $parent names, parentKey, inline handlers, OnLoad order
        H.xml.loadTop({tag = "Button", file = "selftest.xml", line = 1, attr = {name = "SelfTestTemplate", virtual = "true"},
            kids = {
                {tag = "Layers", attr = {}, kids = {{tag = "Layer", attr = {level = "ARTWORK"}, kids = {
                    {tag = "FontString", attr = {name = "$parentLabel", parentKey = "label"}, kids = {}}}}}},
                {tag = "Scripts", attr = {}, kids = {
                    {tag = "OnLoad", file = "selftest.xml", line = 5, attr = {}, kids = {}, text = "self.loaded = (self.loaded or 0) + 1"},
                    {tag = "OnClick", file = "selftest.xml", line = 6, attr = {}, kids = {}, text = "self.clickedWith = button"}}}}});
        local b = CreateFrame("Button", "SelfTestButton", UIParent, "SelfTestTemplate");
        H.assertEq(b.loaded, 1, "OnLoad ran once");
        H.assertTrue(b.label == SelfTestButtonLabel and b.label ~= nil, "$parent name + parentKey");
        b:Click("RightButton");
        H.assertEq(b.clickedWith, "RightButton", "inline handler parameters");
        H.assertFalse(pcall(f.RegisterEvent, f, "NOT_AN_EVENT"), "unknown events are rejected");
        H.assertFalse(pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", print), "removed script types are rejected");
        H.assertTrue(f.SetBackdrop == nil, "SetBackdrop needs BackdropTemplate");

        -- latency mode: reads show the old state until the server answers
        H.latency = 0.2;
        C_Item.EquipItemByName("Helm of the Bastion", 1);
        H.assertEquipped(1, "headB", "not applied yet");
        H.assertTrue(IsInventoryItemLocked(1), "locked while pending");
        H.advance(0.3);
        H.assertEquipped(1, "headA", "applied after the latency");
        H.latency = 0;

        -- bank tabs: only while the bank is open
        H.assertEq(C_Container.GetContainerNumSlots(6), 0, "bank tab closed");
        H.openBank();
        H.assertEq(table.concat(C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Character), ","), "6,7");
        PickupInventoryItem(1);
        C_Container.PickupContainerItem(6, 1);
        H.assertInBank("headA");
        H.assertEquipped(1, nil);
        H.assertEq(C_Container.ContainerIDToInventoryID(6), nil, "bank tabs are not inventory bags");
        H.assertFalse(pcall(PutItemInBag, nil), "PutItemInBag(nil) is a usage error");
        H.closeBank();
        H.assertEq(C_Container.GetContainerNumSlots(6), 0);

        H.assertTotalItems(total, "no item lost or duplicated");
        H.assertCursorEmpty();
        H.log("self-test reached the end; uiErrors:", #H.uiErrors, "events:", #H.eventLog);
    end,
};
