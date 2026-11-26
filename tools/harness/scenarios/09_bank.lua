-- (i) Bank: push a set to the character bank tabs and pull it back; switching to a set whose items are in the
-- bank while the bank is open fetches them.
return function(H, gq)
    H.advance(1);
    gq:SaveSet("Tank", false);
    H.wearSetBPieces();
    gq:SaveSet("DPS", false);
    H.switchTo(gq, "Tank");
    H.assertWearing(H.SET_A, "start");
    local total = H.totalItems();

    local dpsOnly = {"headB", "chestB", "legsB", "feetB", "handsB", "backB", "ringC", "trinketC", "greatsword"};

    H.openBank();
    H.advance(1);
    gq:PushSetToBank("DPS");
    H.advance(3);
    for _, itemKey in ipairs(dpsOnly) do
        H.assertInBank(itemKey, "pushed");
    end
    H.assertWearing(H.SET_A, "worn Tank gear stays on");
    H.assertInBags("ringB", 0, "items shared with the current set are not pushed");
    H.assertTotalItems(total, "push");

    gq:PullSetFromBank("DPS");
    H.advance(3);
    for _, itemKey in ipairs(dpsOnly) do
        H.assertInBags(itemKey, 1, "pulled back");
    end
    H.assertNoGearInSpecialBags();
    H.assertTotalItems(total, "pull");

    -- switch to a set stored in the bank while at the bank
    gq:PushSetToBank("DPS");
    H.advance(3);
    H.assertInBank("headB");
    H.switchTo(gq, "DPS", 5);
    H.assertWearing(H.SET_B, "DPS fetched from the bank and equipped");
    H.closeBank();
    H.advance(1);
    H.assertCursorEmpty();
    H.assertTotalItems(total, "end");
    H.assertNoUiErrors();
end
