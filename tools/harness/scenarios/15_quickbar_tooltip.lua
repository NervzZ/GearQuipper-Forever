-- (n) The slot's tooltip moves out of the way of an open hover bar (bottom-left corner just past the bar's far end,
-- like Blizzard does for its own flyout), stays there when Blizzard refreshes the tooltip, and is left alone when no
-- GQ bar is open. The bar's background (.border) is a child frame (the stock flyout art or a suite's panel); runs
-- stock and under EllesmereUI.
local function anchorOf(tooltip)
    local point, relativeTo, relativePoint = tooltip:GetPoint(1);
    return point, relativeTo, relativePoint;
end

local function run(H, gq)
    H.advance(1);
    H.openCharacterFrame();
    H.advance(0.5);

    -- head slot has another helmet in the bags: bar opens, tooltip goes beside it
    H.mouseEnter(CharacterHeadSlot);
    H.advance(0.05);
    local bar = GQ_QuickBar_1;
    H.assertTrue(bar and bar:IsVisible(), "head bar open");
    H.assertTrue(bar.border:IsObjectType("Frame") and bar.border:GetParent() == bar, "background frame of the bar");
    H.assertTrue(GameTooltip:IsShown() and GameTooltip:IsOwned(CharacterHeadSlot), "slot tooltip shown");
    local point, relativeTo, relativePoint = anchorOf(GameTooltip);
    H.assertEq(relativeTo, bar.border, "tooltip anchored to the bar");
    H.assertEq(point, "BOTTOMLEFT");
    H.assertEq(relativePoint, "BOTTOMRIGHT");

    -- Blizzard refreshes the slot tooltip (UpdateTooltip re-runs PaperDollItemSlotButton_OnEnter): still beside the bar
    CharacterHeadSlot:UpdateTooltip();
    H.advance(0.25);
    CharacterHeadSlot:UpdateTooltip();
    local _, relativeAfterRefresh = anchorOf(GameTooltip);
    H.assertEq(relativeAfterRefresh, bar.border, "tooltip stays beside the bar after a refresh");

    -- leaving: bar and tooltip gone
    H.mouseLeave(CharacterHeadSlot);
    H.advance(0.3);
    H.assertTrue(not bar:IsVisible(), "bar closed");
    H.assertTrue(not GameTooltip:IsShown(), "tooltip hidden");

    -- a slot with nothing to swap in: no bar, tooltip stays on the slot
    H.mouseEnter(CharacterNeckSlot);
    H.advance(0.05);
    H.assertTrue(not (GQ_QuickBar_2 and GQ_QuickBar_2:IsVisible()), "no neck bar");
    local _, neckRelative = anchorOf(GameTooltip);
    H.assertEq(neckRelative, CharacterNeckSlot, "tooltip on the slot when no bar is open");
    H.mouseLeave(CharacterNeckSlot);

    -- Alt (Blizzard's flyout): GQ does not move the tooltip
    H.modifiers.alt = true;
    H.mouseEnter(CharacterHeadSlot);
    H.advance(0.05);
    local _, altRelative = anchorOf(GameTooltip);
    H.assertEq(altRelative, CharacterHeadSlot, "tooltip left to Blizzard while Alt is held");
    CharacterHeadSlot:UpdateTooltip();
    local _, altRelative2 = anchorOf(GameTooltip);
    H.assertEq(altRelative2, CharacterHeadSlot, "refresh does not move it either");
    H.mouseLeave(CharacterHeadSlot);
    H.modifiers.alt = false;

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
