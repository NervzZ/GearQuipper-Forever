-- (d) Two-hander <-> main hand + off hand, and main hand <-> off hand swaps of two one-handers.
return function(H, gq)
    H.advance(1);
    local total = H.totalItems();

    gq:SaveSet("SwordBoard", false); -- sword + shield (worn)
    H.playerEquip("greatsword", 16);
    H.advance(0.5);
    H.assertEquipped(17, nil, "the client unequips the shield for the two-hander");
    gq:SaveSet("Big", false);
    H.playerEquip("mace", 16);
    H.playerEquip("sword", 17);
    H.advance(0.5);
    gq:SaveSet("Dual", false); -- mace MH, sword OH
    H.playerEquip("sword", 16); -- swaps the two hands
    H.advance(0.5);
    H.assertEquipped(17, "mace");
    gq:SaveSet("DualSwapped", false); -- sword MH, mace OH

    local function hands(set, mh, oh)
        H.switchTo(gq, set);
        H.assertEquipped(16, mh, set .. " main hand");
        H.assertEquipped(17, oh, set .. " off hand");
        H.assertFalse(gq:IsSwitching(), set .. ": switch finished");
        H.assertTrue(gq:IsSetComplete(set), set .. " complete");
        H.assertCursorEmpty(set);
        H.assertTotalItems(total, set);
    end

    hands("Big", "greatsword", nil);         -- MH+OH -> 2H
    hands("SwordBoard", "sword", "shield");  -- 2H -> MH+OH
    hands("Big", "greatsword", nil);
    hands("Dual", "mace", "sword");          -- 2H -> dual wield
    hands("DualSwapped", "sword", "mace");   -- MH <-> OH
    hands("Dual", "mace", "sword");          -- and back
    hands("SwordBoard", "sword", "shield");  -- OH weapon -> shield
    hands("DualSwapped", "sword", "mace");
    hands("Big", "greatsword", nil);
    H.assertNoChat("Not enough bag space");
    H.assertNoUiErrors();
end
