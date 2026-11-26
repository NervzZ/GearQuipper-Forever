-- (b) Save two full sets and switch back and forth. Worn items go back to generic bags only: the quiver sits in
-- bag slot 1 and the backpack is full, so "first bag with room" would be the quiver if bag families were ignored;
-- the keyring and the reagent bag have room too.
return {
    noDefaultCharacter = true,
    setup = function(H)
        H.setupDefaultCharacter({bags = {"quiver", "bag16", "bag16", "bag16"}});
        H.fillBags("junk");
        for _ = 1, 40 do -- leave bags 2..4 partly free, backpack stays full
            if not H.removeFromBags("junk") then
                break;
            end
        end
        for bagId = 0, 0 do
            for slot = 1, H.bags[bagId].size do
                if not H.bags[bagId].slots[slot] then
                    H.give("junk", {bag = bagId, slot = slot});
                end
            end
        end
    end,
    run = function(H, gq)
        H.advance(1);
        local total = H.totalItems();

        gq:SaveSet("Tank", false);
        -- Tank without tabard: the tabard was never in a bag, so GQ must pick a bag for it (not the quiver)
        PickupInventoryItem(19);
        PutItemInBag(C_Container.ContainerIDToInventoryID(2));
        H.advance(0.5);
        gq:SaveSet("NoTabard", false);
        H.playerEquip("tabard", 19);
        H.wearSetBPieces();
        gq:SaveSet("DPS", false);
        H.assertEq(gq:LoadCurrentSetName(), "DPS", "saving makes the set current");
        H.assertTrue(gq:IsSetComplete("DPS"));
        local noTabard = {};
        for slot, itemKey in pairs(H.SET_A) do
            noTabard[slot] = itemKey;
        end
        noTabard[19] = nil;

        for round = 1, 2 do
            H.switchTo(gq, "NoTabard");
            H.assertWearing(noTabard, "NoTabard, round " .. round);
            H.assertInBags("tabard", 1, "tabard stored in a generic bag");
            H.assertNoGearInSpecialBags("NoTabard round " .. round);
            H.switchTo(gq, "Tank");
            H.assertWearing(H.SET_A, "Tank, round " .. round);
            H.assertFalse(gq:IsSwitching(), "switch finished");
            H.assertEq(gq:LoadCurrentSetName(), "Tank");
            H.assertTrue(gq:IsSetComplete("Tank"), "Tank complete");
            for _, itemKey in pairs(H.SET_B_PIECES) do
                H.assertInBags(itemKey, 1, "DPS piece back in a generic bag");
            end

            H.switchTo(gq, "DPS");
            H.assertWearing(H.SET_B, "DPS, round " .. round);
            H.assertEq(gq:LoadCurrentSetName(), "DPS");
            H.assertTrue(gq:IsSetComplete("DPS"), "DPS complete");
            H.assertInBags("shield", 1, "off-hand stored when the two-hander comes in");

            H.assertNoGearInSpecialBags("round " .. round);
            H.assertCursorEmpty();
            H.assertTotalItems(total);
        end
        H.assertNoChat("Not enough bag space", "enough room in bags 2..4");
        H.assertNoUiErrors("no request refused (e.g. gear sent to the quiver)");
    end,
};
