-- (r) A quick bar offers only items that fit its slot. Besides the bags it lists what the paired slot wears when that
-- fits too (one-hand weapons between main and off hand, rings, trinkets), but never the off-hand shield, off-hand
-- weapon or held item on the main-hand bar. Clicking a worn one-hander on the main-hand bar swaps the hands.

-- "key" for a bag item, "key@slot" for a worn one; sorted
local function barItems(H, slotButton, slotId)
    H.mouseEnter(slotButton);
    H.advance(0.05);
    local items = {};
    local bar = _G["GQ_QuickBar_" .. slotId];
    if bar and bar:IsVisible() then
        local index = 1;
        while _G["GQ_QuickSlot_" .. slotId .. "_" .. index] do
            local quick = _G["GQ_QuickSlot_" .. slotId .. "_" .. index];
            if quick:IsShown() then
                local id = tonumber(quick.itemString:match("item:(%d+)"));
                local key = H.itemsById[id].key;
                items[#items + 1] = quick.equippedSlotId and (key .. "@" .. quick.equippedSlotId) or key;
            end
            index = index + 1;
        end
    end
    H.mouseLeave(slotButton);
    H.advance(0.3);
    table.sort(items);
    return table.concat(items, ",");
end

local function quickSlotFor(slotId, key, H)
    local index = 1;
    while _G["GQ_QuickSlot_" .. slotId .. "_" .. index] do
        local quick = _G["GQ_QuickSlot_" .. slotId .. "_" .. index];
        if quick:IsShown() and H.itemsById[tonumber(quick.itemString:match("item:(%d+)"))].key == key then
            return quick;
        end
        index = index + 1;
    end
end

return function(H, gq)
    H.advance(1);
    H.openCharacterFrame();
    H.advance(0.5);
    H.assertEquipped(16, "sword");
    H.assertEquipped(17, "shield");

    -- sword + shield: the main-hand bar has the bag weapons only, not the worn shield
    H.assertEq(barItems(H, CharacterMainHandSlot, 16), "greatsword,mace", "main hand: no shield");
    H.assertEq(barItems(H, CharacterSecondaryHandSlot, 17), "mace,orb", "off hand: bag items that fit");

    -- rings and trinkets: the other worn one is offered
    H.assertEq(barItems(H, CharacterFinger0Slot, 11), "ringB@12,ringC", "ring 1: the other worn ring");
    H.assertEq(barItems(H, CharacterFinger1Slot, 12), "ringA@11,ringC", "ring 2");
    H.assertEq(barItems(H, CharacterTrinket0Slot, 13), "trinketB@14,trinketC", "trinket 1");
    H.assertEq(barItems(H, CharacterTrinket1Slot, 14), "trinketA@13,trinketC", "trinket 2");

    -- an off-hand-only weapon and a held item stay off the main-hand bar too
    H.give("offhandBlade");
    H.playerEquip("offhandBlade", 17);
    H.advance(0.5);
    H.assertEquipped(17, "offhandBlade");
    H.assertEq(barItems(H, CharacterMainHandSlot, 16), "greatsword,mace", "main hand: no off-hand dirk");
    H.playerEquip("orb", 17);
    H.advance(0.5);
    H.assertEq(barItems(H, CharacterMainHandSlot, 16), "greatsword,mace", "main hand: no held orb");

    -- dual wield: the worn one-handers are offered between the hands, and the click swaps them
    H.playerEquip("mace", 17);
    H.advance(0.5);
    H.assertEquipped(17, "mace");
    H.assertEq(barItems(H, CharacterMainHandSlot, 16), "greatsword,mace@17", "main hand: the off-hand mace");
    H.assertEq(barItems(H, CharacterSecondaryHandSlot, 17), "offhandBlade,orb,shield,sword@16",
        "off hand: the main-hand sword");
    H.mouseEnter(CharacterMainHandSlot);
    H.advance(0.05);
    local quick = quickSlotFor(16, "mace", H);
    H.assertTrue(quick, "mace on the bar");
    H.mouseLeave(CharacterMainHandSlot);
    H.mouseEnter(quick);
    quick:Click("LeftButton");
    H.mouseLeave(quick);
    H.advance(1);
    H.assertEquipped(16, "mace", "mace in the main hand");
    H.assertEquipped(17, "sword", "sword swapped into the off hand");

    -- the API agrees: nothing it returns for the main hand is an off-hand-only item
    H.playerEquip("shield", 17);
    H.advance(0.5);
    for _, entry in ipairs(gq:GetMatchingItems(16)) do
        local equipLoc = select(4, C_Item.GetItemInfoInstant(entry[gq.ITEM_STRING]));
        H.assertTrue(equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_2HWEAPON" or
            equipLoc == "INVTYPE_WEAPONMAINHAND", "main hand fits: " .. tostring(equipLoc));
    end
    H.assertCursorEmpty();
    H.assertNoUiErrors();
end
