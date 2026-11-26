-- (e) Full bags: a switch that needs free bag slots is reported and refused (or stopped) without Lua errors,
-- without leaving an item on the cursor, without losing items and without leaving GQ stuck "switching".
return function(H, gq)
    H.advance(1);
    gq:SaveSet("Tank", false);
    H.wearSetBPieces();
    gq:SaveSet("DPS", false);
    H.switchTo(gq, "Tank");
    H.assertWearing(H.SET_A);

    -- a set without helmet and cloak (needs two free bag slots)
    PickupInventoryItem(1);
    PutItemInBackpack();
    PickupInventoryItem(15);
    PutItemInBackpack();
    H.advance(0.5);
    gq:SaveSet("Bareheaded", false);
    H.switchTo(gq, "Tank");
    H.assertWearing(H.SET_A, "back to Tank");

    local filled = H.fillBags("junk");
    H.advance(0.5);
    local total = H.totalItems();
    H.clearChat();

    gq:QueueSwitch("Bareheaded");
    H.advance(3);
    H.assertChat("[Bb]ag space", "the missing bag space is reported");
    H.assertEquipped(1, "headA", "helmet kept");
    H.assertEquipped(15, "backA", "cloak kept");
    H.assertFalse(gq:IsSwitching(), "not stuck switching");
    H.assertCursorEmpty();
    H.assertTotalItems(total);

    -- piece-for-piece swaps need no free slot, but the two-hander must store the shield somewhere
    H.clearChat();
    gq:QueueSwitch("DPS");
    H.advance(4);
    H.assertFalse(gq:IsSwitching(), "not stuck switching after DPS attempt");
    H.assertCursorEmpty("DPS attempt with full bags");
    H.assertTotalItems(total, "DPS attempt with full bags");
    H.assertNoGearInSpecialBags();
    if gq:IsSetComplete("DPS") then
        H.fail("DPS cannot be complete: the shield has nowhere to go");
    end
    H.assertChatAny({"[Bb]ag space", "[Ii]ncomplete", "could not"}, "the failed switch is reported");

    -- free one slot: now it works
    H.removeFromBags("junk");
    H.advance(0.5);
    H.switchTo(gq, "DPS", 4);
    H.assertWearing(H.SET_B, "DPS after freeing a slot");
    H.assertTrue(filled > 0);
end
