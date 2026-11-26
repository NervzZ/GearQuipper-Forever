-- (k) Swapping from the character sheet, the way a player does it: GQ panel, "New set" dialog, clicking a set
-- in the list, and the quick-slot bar that opens when an equipped item is picked up.
return function(H, gq)
    local panel = H.include("helpers/gq_panel.lua");
    H.advance(1);
    panel.open();
    H.assertEq(panel.selectedTab(), "Sets", "the panel opens on the Sets tab");

    -- "New set" -> name dialog -> set saved from the worn gear
    H.assertTrue(GqAddSetButton and GqAddSetButton:IsEnabled(), "New set button");
    GqAddSetButton:Click("LeftButton");
    H.acceptPopup("Tank");
    H.advance(0.5);
    H.assertTrue(panel.setRow("Tank"), "Tank listed");
    -- with the panel open, gear changed by hand is saved into the current set: create DPS, then dress it
    GqAddSetButton:Click("LeftButton");
    H.acceptPopup("DPS");
    H.advance(0.5);
    H.assertTrue(panel.setRow("DPS"), "DPS listed");
    H.assertEq(gq:LoadCurrentSetName(), "DPS");
    H.assertTrue(panel.setRow("DPS").Tick:IsShown(), "the new set is ticked");
    H.wearSetBPieces();
    H.advance(0.5);
    H.assertChat("<DPS> Saved slot 1", "hand-equipped helmet auto-saved into DPS");
    H.assertSetMatchesGear(gq, "DPS", "auto-saved");
    H.assertEq(gq:LoadSlot(1, "Tank"), gq:GetItemString(H.find("headA")[1].kind == "equip" and 1 or
        C_Container.GetContainerItemLink(H.find("headA")[1].bag, H.find("headA")[1].slot)), "Tank untouched");

    -- click a set in the list
    panel.setRow("Tank"):Click("LeftButton");
    H.advance(3);
    H.assertWearing(H.SET_A, "clicked Tank");
    H.assertTrue(panel.setRow("Tank").Tick:IsShown(), "Tank ticked in the list");
    H.assertFalse(panel.setRow("DPS").Tick:IsShown(), "DPS no longer ticked");
    panel.setRow("DPS"):Click("LeftButton");
    H.advance(3);
    H.assertWearing(H.SET_B, "clicked DPS");

    -- quick slots: pick up the worn helmet, the bar lists the other helmet, click it
    H.secureCall = true;
    PickupInventoryItem(1);
    H.secureCall = false;
    H.advance(0.2);
    local quick = GQ_QuickSlot_1_1;
    H.assertTrue(quick and quick:IsVisible(), "quick-slot bar opened for the head slot");
    H.assertTrue(quick.itemString == gq:LoadSlot(1, "Tank"), "quick slot offers the Tank helmet");
    quick:Click("LeftButton");
    H.advance(1);
    H.assertEquipped(1, "headA", "quick slot equipped the helmet");
    H.assertCursorEmpty();
    panel.close();
end
