-- (l) Quick bars on mouse-over: hovering a paper-doll slot shows the items that fit it; the bar stays while the mouse
-- is on the slot or the bar, closes when it leaves both, and never opens with Alt (Blizzard's flyout), in combat,
-- or while the player holds an item. Closing a hover bar must not drop the item on the cursor. Runs stock and under
-- EllesmereUI (skinned bars behave the same).
local function bar(slotId)
    return _G["GQ_QuickBar_" .. slotId];
end

local function barShown(slotId)
    return bar(slotId) ~= nil and bar(slotId):IsVisible();
end

local function run(H, gq)
    H.advance(1);
    H.openCharacterFrame();
    H.advance(0.5);

    -- hover the head slot: the bar lists the other helmet
    H.mouseEnter(CharacterHeadSlot);
    H.advance(0.05);
    H.assertTrue(barShown(1), "hovering the head slot opens its bar");
    local quick = GQ_QuickSlot_1_1;
    H.assertTrue(quick and quick:IsShown() and quick.itemString ~= nil, "bar lists a helmet");
    -- an ItemButton whose rarity ring shows the helmet's quality (epic)
    local epic = BAG_ITEM_QUALITY_COLORS[4];
    local r, g, b = quick.IconBorder:GetVertexColor();
    H.assertTrue(quick.IconBorder:IsShown() and r == epic.r and g == epic.g and b == epic.b, "epic rarity ring");
    if H.variantName == "eui" then
        H.assertTrue(H.countSuiteCalls("ItemButton", quick) >= 1, "button skinned by EllesmereUI");
        H.assertEq(H.countSuiteCalls("Panel", bar(1).border), 1, "bar background skinned by EllesmereUI");
    else
        H.assertEq(#H.suiteCalls, 0, "stock: nothing skinned");
    end

    -- slot -> bar: stays open; the bar's hover tolerance bridges the gap to the slot (recorded, the mock has no
    -- hit testing)
    local slack;
    local isMouseOver = bar(1).IsMouseOver;
    bar(1).IsMouseOver = function(self, top, bottom, left, right)
        slack = {top or 0, bottom or 0, left or 0, right or 0};
        return isMouseOver(self, top, bottom, left, right);
    end;
    H.mouseLeave(CharacterHeadSlot);
    H.mouseEnter(quick);
    H.advance(0.3);
    H.assertTrue(barShown(1), "moving onto the bar keeps it open");
    local _, slot, _, gap = bar(1):GetPoint(1);
    H.assertTrue(slot == CharacterHeadSlot and slack and -slack[3] >= gap and gap > 0,
        "hover tolerance covers the gap between slot and bar");
    bar(1).IsMouseOver = nil;

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

return {
    run = run,
    variants = {
        {name = "stock"},
        {name = "eui", suites = {EllesmereUI = {charsheetStyle = "eui"}}},
    },
};
