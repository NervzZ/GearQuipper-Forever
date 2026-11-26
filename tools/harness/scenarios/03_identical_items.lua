-- (c) Identical copies: twin one-handers (MH + OH) and two identical rings. Their links are identical on Forever
-- (uniqueID is empty), so GQ must equip both copies and never take one copy for "already equipped".
return {
    setup = function(H)
        H.give("twinBlade");
        H.give("twinBlade");
        H.give("twinRing");
        H.give("twinRing");
    end,
    run = function(H, gq)
        H.advance(1);
        local total = H.totalItems();
        gq:SaveSet("Tank", false);

        H.playerEquip("twinBlade", 16);
        H.playerEquip("twinBlade", 17);
        H.playerEquip("twinRing", 11);
        H.playerEquip("twinRing", 12);
        H.advance(0.5);
        H.assertEquipped(16, "twinBlade");
        H.assertEquipped(17, "twinBlade");
        gq:SaveSet("Twins", false);
        H.assertEq(gq:LoadSlot(16, "Twins"), gq:LoadSlot(17, "Twins"), "both hands store the same string");

        local twins = {};
        for slot, itemKey in pairs(H.SET_A) do
            twins[slot] = itemKey;
        end
        twins[11], twins[12], twins[16], twins[17] = "twinRing", "twinRing", "twinBlade", "twinBlade";

        for round = 1, 2 do
            H.switchTo(gq, "Tank");
            H.assertWearing(H.SET_A, "Tank, round " .. round);
            H.assertInBags("twinBlade", 2);
            H.assertInBags("twinRing", 2);

            H.switchTo(gq, "Twins");
            H.assertWearing(twins, "Twins, round " .. round);
            H.assertTrue(gq:IsSetComplete("Twins"));
            H.assertInBags("twinBlade", 0);
            H.assertInBags("twinRing", 0);
            H.assertTotalItems(total);
        end

        -- one copy already worn (by hand), the other in the bags
        H.switchTo(gq, "Tank");
        H.playerEquip("twinBlade", 16);
        H.playerEquip("twinRing", 12);
        H.advance(0.5);
        H.switchTo(gq, "Twins");
        H.assertWearing(twins, "Twins from a half-equipped state");
        H.assertNoUiErrors();
        H.assertCursorEmpty();
        H.assertTotalItems(total);
    end,
};
