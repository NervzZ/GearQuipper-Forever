-- (j) A partial set only touches its active slots.
return function(H, gq)
    H.advance(1);
    gq:SaveSet("Tank", false);
    H.playerEquip("trinketC", 13);
    H.playerEquip("ringC", 11);
    H.advance(0.5);
    gq:SaveSet("Trinket", false);
    gq:SavePartialOption("Trinket", true);
    for slot = 0, 19 do
        gq:SaveSlotState(slot, slot == 13, false, "Trinket");
    end
    H.switchTo(gq, "Tank");
    H.assertWearing(H.SET_A, "start");

    -- hand-made changes in slots the partial set does not own
    H.playerEquip("headB", 1);
    H.playerEquip("greatsword", 16);
    H.advance(0.5);
    local expected = {};
    for slot = 1, 19 do
        expected[slot] = H.inv[slot] and H.inv[slot].key;
    end
    expected[13] = "trinketC";

    H.switchTo(gq, "Trinket");
    H.assertWearing(expected, "only the trinket slot changed");
    H.assertEquipped(11, "ringA", "inactive ring slot untouched");
    H.assertCursorEmpty();
    H.assertNoUiErrors();
end
