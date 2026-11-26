-- (a) The addon loads and initialises without Lua errors; the default set and $PREVIOUSEQUIPMENT exist;
-- the character sheet (paper doll + GQ panel) opens and closes cleanly; the slash command answers.
return function(H, gq)
    H.assertTrue(gq, "global gearquipper table exists");
    H.assertTrue(gq.initFinished, "Init() ran on ADDON_LOADED");
    H.advance(2);

    local names = gq:LoadSetNames();
    H.assertEq(#names, 1, "one set after first login");
    H.assertEq(names[1], DEFAULT, "default set created on first PLAYER_ENTERING_WORLD");
    H.assertEq(gq:LoadCurrentSetName(), DEFAULT, "default set is current");
    local withPrevious = gq:LoadSetNames(true);
    H.assertEq(#withPrevious, 2, "$PREVIOUSEQUIPMENT exists (hidden)");

    -- the default set captured the worn gear with normalised item strings
    local set = gq:LoadSet(DEFAULT);
    H.assertEq(set[1], gq:GetItemString(1), "head stored as the normalised string of the worn helm");
    H.assertFalse(tostring(set[1]):find("1482"), "spec id is not part of stored strings");
    H.assertTrue(gq:IsSetComplete(DEFAULT), "default set matches the worn gear");

    -- character sheet with the GQ side panel
    H.openCharacterFrame();
    H.advance(0.5);
    H.assertTrue(PaperDollFrame:IsVisible(), "paper doll visible");
    if GqUiFrame and not GqUiFrame:IsShown() then
        GqUiFrame:Show();
    end
    H.advance(0.5);
    H.assertTrue(GqUiFrame and GqUiFrame:IsVisible(), "GQ panel visible on the character sheet");
    H.closeCharacterFrame();
    H.advance(0.5);
    H.assertFalse(GqUiFrame:IsVisible(), "GQ panel hidden with the character sheet");

    -- hovering items runs the tooltip hook without errors
    H.hoverInventorySlot(1);
    H.hoverBagItem(0, 1);
    GameTooltip:Hide();

    H.slash("/gq");
    H.assertChat("/gq", "help text printed");
    H.advance(1);
end
