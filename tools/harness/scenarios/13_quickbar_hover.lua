-- (l) Quick bars on mouse-over: hovering a paper-doll slot shows the items that fit it; the bar stays while the mouse
-- is on the slot or the bar, closes when it leaves both, and never opens with Alt (Blizzard's flyout), in combat,
-- or while the player holds an item. Closing a hover bar must not drop the item on the cursor.
local function bar(slotId)
    return _G["GQ_QuickBar_" .. slotId];
end

local function barShown(slotId)
    return bar(slotId) ~= nil and bar(slotId):IsVisible();
end

return function(H, gq)
    H.advance(1);
    H.openCharacterFrame();
    H.advance(0.5);

    -- hover the head slot: the bar lists the other helmet
    H.mouseEnter(CharacterHeadSlot);
    H.advance(0.05);
    H.assertTrue(barShown(1), "hovering the head slot opens its bar");
    local quick = GQ_QuickSlot_1_1;
    H.assertTrue(quick and quick:IsShown() and quick.itemString ~= nil, "bar lists a helmet");

    -- slot -> bar: stays open
    H.mouseLeave(CharacterHeadSlot);
    H.mouseEnter(quick);
    H.advance(0.3);
    H.assertTrue(barShown(1), "moving onto the bar keeps it open");

    -- leaving both closes it
    H.mouseLeave(quick);
    H.advance(0.3);
    H.assertTrue(not barShown(1), "leaving slot and bar closes it");

    -- hover, move to the bar, click the helmet: equipped
    H.mouseEnter(CharacterHeadSlot);
    H.advance(0.05);
    H.mouseLeave(CharacterHeadSlot);
    H.mouseEnter(GQ_QuickSlot_1_1);
    GQ_QuickSlot_1_1:Click("LeftButton");
    H.mouseLeave(GQ_QuickSlot_1_1);
    H.advance(1);
    H.assertEquipped(1, "headB", "hover bar equipped the helmet");
    H.assertCursorEmpty();
    H.assertTrue(not barShown(1), "bar closed after the click");

    -- hovering another slot closes the previous bar; weapon bars work too
    H.mouseEnter(CharacterHeadSlot);
    H.advance(0.05);
    H.assertTrue(barShown(1), "head bar open again");
    H.mouseEnter(CharacterMainHandSlot);
    H.advance(0.05);
    H.assertTrue(barShown(16), "main-hand bar opens on hover");
    H.assertTrue(not barShown(1), "head bar closed when another slot is hovered");
    H.mouseLeave(CharacterMainHandSlot);
    H.mouseLeave(CharacterHeadSlot);
    H.advance(0.3);
    H.assertTrue(not barShown(16), "main-hand bar closed");

    -- Alt = Blizzard's flyout: GQ stays out of the way
    H.modifiers.alt = true;
    H.mouseEnter(CharacterHeadSlot);
    H.advance(0.05);
    H.assertTrue(not barShown(1), "no GQ bar while Alt is held");
    H.mouseLeave(CharacterHeadSlot);
    H.modifiers.alt = false;

    -- in combat: no bars (as in GQ)
    H.setCombat(true);
    H.advance(0.1);
    H.mouseEnter(CharacterHeadSlot);
    H.advance(0.05);
    H.assertTrue(not barShown(1), "no bar in combat");
    H.mouseLeave(CharacterHeadSlot);
    H.setCombat(false);
    H.advance(1);

    -- closing a hover bar keeps whatever the player picked up meanwhile
    H.mouseEnter(CharacterHeadSlot);
    H.advance(0.05);
    H.assertTrue(barShown(1), "head bar open before the pick-up");
    local linen = H.find("linen")[1];
    H.secureCall = true;
    C_Container.PickupContainerItem(linen.bag, linen.slot);
    H.secureCall = false;
    H.mouseLeave(CharacterHeadSlot);
    H.advance(0.3);
    H.assertTrue(not barShown(1), "bar closed after the mouse left");
    H.assertTrue(CursorHasItem(), "item on the cursor survived the bar closing");
    ClearCursor();
    H.advance(0.2);

    -- a hovered empty slot still pins its bar on click (GQ behaviour): it then stays when the mouse leaves
    H.closeCharacterFrame();
    H.advance(0.5);
end
