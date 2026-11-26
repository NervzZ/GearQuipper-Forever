-- (s) Quick-bar look. Buttons are the intrinsic ItemButton: rarity ring (IconBorder) in the item's quality colour, no
-- quick-slot frame art. Stock look: Blizzard's equipment-flyout background (UI-GearManager-Flyout cut with the
-- EQUIPMENTFLYOUT_* texcoords) on the .border child frame plus the flyout's slot glow. Under a UI suite: .border is
-- skinned as a panel, every button as an item button, re-skinned each time it shows another item; no flyout art.
local FLYOUT = "Interface\\PaperDollInfoFrame\\UI-GearManager-Flyout";
local GLOW = "Interface\\PaperDollInfoFrame\\UI-GearManager-ItemButton-Highlight";

-- Blizzard_FrameXML/Camelot/EquipmentFlyout.lua (forever branch)
local ONESLOT_LEFT = {0, 0.09765625, 0.5546875, 0.77734375};
local ONESLOT_RIGHT = {0.41796875, 0.51171875, 0.5546875, 0.77734375};
local ONEROW_LEFT = {0, 0.16796875, 0.5546875, 0.77734375};
local ONEROW_CENTER = {0.16796875, 0.328125, 0.5546875, 0.77734375};
local ONEROW_RIGHT = {0.328125, 0.51171875, 0.5546875, 0.77734375};
local MULTIROW_TOP = {0, 0.8359375, 0, 0.19140625};
local MULTIROW_MIDDLE = {0, 0.8359375, 0.19140625, 0.35546875};
local MULTIROW_BOTTOM = {0, 0.8359375, 0.35546875, 0.546875};
local PIXEL = 1 / 256; -- the flyout texture is 256 px wide

local H, gq;

local function near(a, b)
    return math.abs(a - b) < 1e-6;
end

local function bar(slotId)
    return _G["GQ_QuickBar_" .. slotId];
end

local function hover(slot)
    H.mouseEnter(slot);
    H.advance(0.05);
end

local function unhover(slot)
    H.mouseLeave(slot);
    H.advance(0.3);
end

local function shownButtons(slotId)
    local list = {};
    for i = 1, 20 do
        local b = _G["GQ_QuickSlot_" .. slotId .. "_" .. i];
        if b and b:IsShown() then
            list[#list + 1] = b;
        end
    end
    return list;
end

local function shows(button, itemKey)
    return button.itemString ~= nil and tonumber(gq:GetItemId(button.itemString)) == H.items[itemKey].id;
end

local function buttonFor(slotId, itemKey)
    for _, b in ipairs(shownButtons(slotId)) do
        if shows(b, itemKey) then
            return b;
        end
    end
end

local function qualityOf(button)
    local _, _, quality = C_Item.GetItemInfo(button.link or button.itemString);
    return quality;
end

-- flyout pieces shown on the bar's background frame, in layout order
local function flyoutPieces(b)
    local list = {};
    for _, region in ipairs({b.border:GetRegions()}) do
        if region:IsObjectType("Texture") and region:GetTexture() == FLYOUT and region:IsShown() then
            list[#list + 1] = region;
        end
    end
    return list;
end

local function slotGlow(b)
    for _, child in ipairs({b:GetChildren()}) do
        for _, region in ipairs({child:GetRegions()}) do
            if region:IsObjectType("Texture") and region:GetTexture() == GLOW then
                return region, child;
            end
        end
    end
end

local function assertCoords(tex, coords, msg)
    local l, r, t, btm = tex:GetTexCoord();
    H.assertTrue(near(l, coords[1]) and near(r, coords[2]) and near(t, coords[3]) and near(btm, coords[4]),
        string.format("%s: texcoords %s,%s,%s,%s", msg, l, r, t, btm));
end

local function assertPoint(region, point, relativeTo, relativePoint, x, y, msg)
    local p, rel, relPoint, px, py = region:GetPoint(1);
    H.assertEq(region:GetNumPoints(), 1, msg .. ": one anchor");
    H.assertEq(p, point, msg .. ": point");
    H.assertEq(rel, relativeTo, msg .. ": relative to");
    H.assertEq(relPoint, relativePoint, msg .. ": relative point");
    H.assertEq(px, x or 0, msg .. ": x");
    H.assertEq(py, y or 0, msg .. ": y");
end

local function columnCut(coords, side)
    if side == "left" then
        return {coords[1], coords[1] + 25 * PIXEL, coords[3], coords[4]};
    end
    return {coords[2] - 25 * PIXEL, coords[2], coords[3], coords[4]};
end

-- Stock flyout background: a horizontal bar of n buttons, or a vertical one-button column of n rows.
local function assertFlyoutBackground(b, n, vertical, msg)
    local pieces = flyoutPieces(b);
    if n == 1 then
        H.assertEq(#pieces, 2, msg .. ": one-slot pieces");
        assertCoords(pieces[1], ONESLOT_LEFT, msg .. " one-slot left");
        assertCoords(pieces[2], ONESLOT_RIGHT, msg .. " one-slot right");
        H.assertEq(select(1, pieces[1]:GetSize()) + select(1, pieces[2]:GetSize()), 49, msg .. ": one-slot width");
        assertPoint(pieces[1], "TOPLEFT", b.border, "TOPLEFT", -5, 4, msg .. " first piece");
        assertPoint(pieces[2], "TOPLEFT", pieces[1], "TOPRIGHT", 0, 0, msg .. " second piece");
        return;
    end
    if not vertical then
        H.assertEq(#pieces, n, msg .. ": one piece per button");
        for i, piece in ipairs(pieces) do
            local coords = (i == 1 and ONEROW_LEFT) or (i == n and ONEROW_RIGHT) or ONEROW_CENTER;
            assertCoords(piece, coords, msg .. " piece " .. i);
            local w, h = piece:GetSize();
            H.assertEq(w, (i == 1 and 43) or (i == n and 47) or 41, msg .. " piece " .. i .. " width");
            H.assertEq(h, 54, msg .. " piece " .. i .. " height");
            if i == 1 then
                assertPoint(piece, "TOPLEFT", b.border, "TOPLEFT", -5, 4, msg .. " first piece");
            else
                assertPoint(piece, "TOPLEFT", pieces[i - 1], "TOPRIGHT", 0, 0, msg .. " piece " .. i);
            end
        end
        return;
    end
    H.assertEq(#pieces, 2 * n, msg .. ": two pieces per row");
    for row = 1, n do
        local coords = (row == 1 and MULTIROW_TOP) or (row == n and MULTIROW_BOTTOM) or MULTIROW_MIDDLE;
        local left, right = pieces[2 * row - 1], pieces[2 * row];
        assertCoords(left, columnCut(coords, "left"), msg .. " row " .. row .. " left");
        assertCoords(right, columnCut(coords, "right"), msg .. " row " .. row .. " right");
        local height = (row == 1 or row == n) and 49 or 42;
        H.assertEq(select(2, left:GetSize()), height, msg .. " row " .. row .. " height");
        H.assertEq(select(1, left:GetSize()) + select(1, right:GetSize()), 50, msg .. " row " .. row .. " width");
        if row == 1 then
            assertPoint(left, "TOPLEFT", b.border, "TOPLEFT", -5, 4, msg .. " first piece");
        else
            assertPoint(left, "TOPLEFT", pieces[2 * row - 3], "BOTTOMLEFT", 0, 0, msg .. " row " .. row);
        end
        assertPoint(right, "TOPLEFT", left, "TOPRIGHT", 0, 0, msg .. " row " .. row .. " right");
    end
end

local function assertNoFlyoutArt(b, msg)
    H.assertEq(#flyoutPieces(b), 0, msg .. ": no flyout pieces");
    local glow, glowFrame = slotGlow(b);
    H.assertTrue(not (glow and glowFrame:IsVisible() and glow:IsShown()), msg .. ": no slot glow");
end

-- Each shown button is an intrinsic ItemButton without quick-slot art, its ring in the item's quality colour.
local function assertButtons(slotId, msg)
    local buttons = shownButtons(slotId);
    H.assertTrue(#buttons > 0, msg .. ": buttons shown");
    for i, b in ipairs(buttons) do
        local what = msg .. " button " .. i;
        H.assertTrue(b.IconBorder ~= nil and b.SetItemButtonQuality ~= nil, what .. ": intrinsic ItemButton");
        H.assertEq(b:GetNormalTexture(), nil, what .. ": no UI-Quickslot2 frame");
        H.assertEq(b:GetPushedTexture(), nil, what .. ": no UI-Quickslot-Depress");
        if not gq:GetSkinBackend() then
            H.assertEq(b:GetHighlightTexture():GetTexture(), "Interface\\Buttons\\ButtonHilight-Square",
                what .. ": ItemButton highlight");
        end
        H.assertEq(b.icon:GetTexture(), C_Item.GetItemIconByID(C_Item.GetItemInfoInstant(b.itemString)),
            what .. ": icon");
        local w, h = b:GetSize();
        H.assertTrue(w == 37 and h == 37, what .. ": 37x37");
        local color = BAG_ITEM_QUALITY_COLORS[qualityOf(b)];
        if color then
            H.assertTrue(b.IconBorder:IsShown(), what .. ": rarity ring shown");
            local r, g, bl = b.IconBorder:GetVertexColor();
            H.assertTrue(near(r, color.r) and near(g, color.g) and near(bl, color.b),
                string.format("%s: ring %.2f,%.2f,%.2f for quality %d", what, r, g, bl, qualityOf(b)));
        else
            H.assertTrue(not b.IconBorder:IsShown(), what .. ": no ring for quality " .. tostring(qualityOf(b)));
        end
    end
    return buttons;
end

local function colorOf(button)
    local color = BAG_ITEM_QUALITY_COLORS[qualityOf(button)];
    return {color.r, color.g, color.b};
end

local function assertEuiBorder(button, msg)
    local got, want = H.euiItemBorder(button), colorOf(button);
    H.assertTrue(got and near(got[1], want[1]) and near(got[2], want[2]) and near(got[3], want[3]),
        msg .. ": EllesmereUI border follows the quality");
end

-- Hover the head bar: headB (epic), the green and the grey helmet.
local function openHead(msg)
    hover(CharacterHeadSlot);
    H.assertTrue(bar(1) and bar(1):IsVisible(), msg .. ": head bar open");
    H.assertEq(#shownButtons(1), 3, msg .. ": three helmets");
    return bar(1);
end

local function setup(h)
    H = h;
    H.defineItem({key = "headGreen", name = "Green Helm", equipLoc = "INVTYPE_HEAD", quality = 2});
    H.defineItem({key = "headGrey", name = "Grey Helm", equipLoc = "INVTYPE_HEAD", quality = 0});
    H.give("headGreen");
    H.give("headGrey");
    H.give("bullets", {count = 200});
end

local function stock(h, g)
    H, gq = h, g;
    H.advance(1);
    H.openCharacterFrame();
    H.advance(0.5);

    -- head: horizontal bar to the right of the slot, three buttons on the one-row flyout strip
    local head = openHead("stock");
    assertPoint(head, "TOPLEFT", CharacterHeadSlot, "TOPRIGHT", 4, 3, "head bar");
    H.assertTrue(head.border:GetObjectType() == "Frame" and head.border:GetParent() == head,
        "the background is a child frame of the bar");
    local w, h2 = head:GetSize();
    H.assertTrue(w == 3 * 37 + 2 * 4 + 6 and h2 == 43, "head bar size " .. w .. "x" .. h2);
    local buttons = assertButtons(1, "head");
    for i, b in ipairs(buttons) do
        assertPoint(b, "TOPLEFT", head, "TOPLEFT", 3 + (i - 1) * 41, -3, "head button " .. i);
    end
    assertFlyoutBackground(head, 3, false, "head");
    local glow, glowFrame = slotGlow(head);
    H.assertTrue(glow and glow:IsVisible(), "slot glow shown");
    assertCoords(glow, {0, 0.78125, 0, 0.78125}, "slot glow");
    H.assertEq(select(1, glow:GetSize()), 50, "slot glow size");
    for i, point in ipairs({"TOPLEFT", "BOTTOMRIGHT"}) do
        local p, rel = glowFrame:GetPoint(i);
        H.assertTrue(p == point and rel == CharacterHeadSlot, "slot glow frame covers the slot (" .. point .. ")");
    end
    H.assertEq(glow:GetPoint(1), "CENTER", "slot glow centred on the slot");
    H.assertTrue(buttonFor(1, "headGrey") and not buttonFor(1, "headGrey").IconBorder:IsShown(), "poor: no ring");
    for _, region in ipairs({head:GetRegions()}) do
        H.assertTrue(not region:IsObjectType("Texture"), "no art directly on the bar frame");
    end
    unhover(CharacterHeadSlot);

    -- the green helmet's button shows the old helmet (epic) once the green one is worn
    hover(CharacterHeadSlot);
    local greenButton = buttonFor(1, "headGreen");
    H.mouseLeave(CharacterHeadSlot);
    H.mouseEnter(greenButton);
    greenButton:Click("LeftButton");
    H.mouseLeave(greenButton);
    H.advance(1);
    H.assertEquipped(1, "headGreen", "green helmet equipped from the bar");
    hover(CharacterHeadSlot);
    H.assertTrue(shows(greenButton, "headA"), "button now shows headA");
    assertButtons(1, "head after the swap");
    unhover(CharacterHeadSlot);

    -- main hand: a column under the slot (greatsword and mace from the bags, plus the off-hand item)
    hover(CharacterMainHandSlot);
    local mh = bar(16);
    local n = #shownButtons(16);
    H.assertTrue(mh and mh:IsVisible() and n >= 2, "main-hand bar with " .. n .. " weapons");
    assertPoint(mh, "TOPLEFT", CharacterMainHandSlot, "BOTTOMLEFT", -3, -4, "main-hand bar");
    local mw, mhh = mh:GetSize();
    H.assertTrue(mw == 43 and mhh == n * 37 + (n - 1) * 5 + 6, "main-hand bar size " .. mw .. "x" .. mhh);
    for i, b in ipairs(assertButtons(16, "main hand")) do
        assertPoint(b, "TOPLEFT", mh, "TOPLEFT", 3, -3 - (i - 1) * 42, "main-hand button " .. i);
    end
    assertFlyoutBackground(mh, n, true, "main hand");
    unhover(CharacterMainHandSlot);

    -- ammo: one button, smaller (scaled bar), stack count on the button, one-slot flyout pieces
    hover(CharacterAmmoSlot);
    local ammo = bar(0);
    H.assertTrue(ammo and ammo:IsVisible(), "ammo bar open");
    H.assertTrue(near(ammo:GetScale(), 26 / 37), "ammo bar keeps its 26 px buttons");
    local bullets = assertButtons(0, "ammo")[1];
    H.assertTrue(bullets.Count:IsShown() and bullets.Count:GetText() == "200", "stack count shown");
    assertFlyoutBackground(ammo, 1, true, "ammo");
    unhover(CharacterAmmoSlot);

    -- a bar that shrinks hides the pieces it no longer needs
    hover(CharacterMainHandSlot);
    assertFlyoutBackground(bar(16), #shownButtons(16), true, "main hand again");
    unhover(CharacterMainHandSlot);

    H.assertEq(#H.suiteCalls, 0, "no suite, nothing skinned");
    H.closeCharacterFrame();
    H.advance(0.5);
end

local function eui(h, g)
    H, gq = h, g;
    H.advance(1);
    H.openCharacterFrame();
    H.advance(0.5);

    local head = openHead("eui");
    H.assertEq(H.countSuiteCalls("Panel", head.border), 1, "background skinned as a panel");
    H.assertEq(#H.suiteCallsFor(head), 0, "the bar frame itself is not skinned");
    assertNoFlyoutArt(head, "eui");
    local buttons = assertButtons(1, "eui head");
    for i, b in ipairs(buttons) do
        H.assertTrue(H.countSuiteCalls("ItemButton", b) >= 1, "button " .. i .. " skinned");
    end
    local greenButton = buttonFor(1, "headGreen");
    assertEuiBorder(greenButton, "green helmet");
    local before = H.countSuiteCalls("ItemButton", greenButton);
    unhover(CharacterHeadSlot);

    hover(CharacterHeadSlot);
    H.mouseLeave(CharacterHeadSlot);
    H.mouseEnter(greenButton);
    greenButton:Click("LeftButton");
    H.mouseLeave(greenButton);
    H.advance(1);
    H.assertEquipped(1, "headGreen", "eui: green helmet equipped");
    local calls = H.countSuiteCalls("ItemButton", greenButton);

    hover(CharacterHeadSlot);
    H.assertTrue(shows(greenButton, "headA"), "eui: button shows headA");
    H.assertTrue(H.countSuiteCalls("ItemButton", greenButton) > calls, "re-skinned when its item changed");
    H.assertTrue(H.countSuiteCalls("ItemButton", greenButton) > before, "re-skinned since the first show");
    assertEuiBorder(greenButton, "epic helmet");
    H.assertEq(H.countSuiteCalls("Panel", head.border), 1, "panel skinned once");
    assertNoFlyoutArt(head, "eui reopened");
    unhover(CharacterHeadSlot);

    hover(CharacterMainHandSlot);
    H.assertEq(H.countSuiteCalls("Panel", bar(16).border), 1, "main-hand background skinned");
    assertNoFlyoutArt(bar(16), "eui main hand");
    for _, b in ipairs(shownButtons(16)) do
        assertEuiBorder(b, "weapon");
    end
    unhover(CharacterMainHandSlot);

    -- EllesmereUI's later re-strip only fades art on the frames it skinned; the buttons keep theirs
    H.euiRestrip();
    hover(CharacterHeadSlot);
    assertButtons(1, "after a restrip");
    unhover(CharacterHeadSlot);

    H.closeCharacterFrame();
    H.advance(0.5);
end

local function euiStock(h, g)
    H, gq = h, g;
    H.advance(1);
    H.openCharacterFrame();
    H.advance(0.5);
    local head = openHead("sheet " .. H.variantName);
    assertFlyoutBackground(head, 3, false, H.variantName);
    assertButtons(1, H.variantName);
    unhover(CharacterHeadSlot);
    H.assertEq(#H.suiteCalls, 0, "EllesmereUI leaves the sheet stock: nothing skinned");
    H.closeCharacterFrame();
    H.advance(0.5);
end

-- Third-party skins switched on after login: bars built in the stock look get skinned, the flyout art goes.
local function euiLate(h, g)
    H, gq = h, g;
    H.advance(1);
    H.openCharacterFrame();
    H.advance(0.5);
    local head = openHead("before the toggle");
    assertFlyoutBackground(head, 3, false, "before the toggle");
    unhover(CharacterHeadSlot);
    H.assertEq(#H.suiteCalls, 0, "stock until the toggle");

    H.euiToggleOn();
    H.assertEq(H.countSuiteCalls("Panel", head.border), 1, "existing background skinned on the toggle");
    for i = 1, 3 do
        local b = _G["GQ_QuickSlot_1_" .. i];
        H.assertEq(H.countSuiteCalls("ItemButton", b), 1, "existing button " .. i .. " skinned");
    end
    head = openHead("after the toggle");
    assertNoFlyoutArt(head, "after the toggle");
    for _, b in ipairs(shownButtons(1)) do
        if BAG_ITEM_QUALITY_COLORS[qualityOf(b)] then
            assertEuiBorder(b, "after the toggle");
        end
    end
    unhover(CharacterHeadSlot);
    H.closeCharacterFrame();
    H.advance(0.5);
end

-- ElvUI (untested in game): HandleFrame on the background, HandleItemButton once per button, the ring every show.
local function elv(h, g)
    H, gq = h, g;
    H.advance(1);
    H.openCharacterFrame();
    H.advance(0.5);
    local head = openHead("elvui");
    unhover(CharacterHeadSlot);
    head = openHead("elvui again");
    H.assertEq(H.countSuiteCalls("HandleFrame", head.border), 1, "background handled once");
    assertNoFlyoutArt(head, "elvui");
    for i, b in ipairs(shownButtons(1)) do
        H.assertEq(H.countSuiteCalls("HandleItemButton", b), 1, "button " .. i .. " handled once");
    end
    H.assertEq(H.countSuiteCalls("HandleIconBorder"), 6, "ring refreshed on every show (3 buttons, 2 shows)");
    unhover(CharacterHeadSlot);
    H.closeCharacterFrame();
    H.advance(0.5);
end

return {
    setup = setup,
    variants = {
        {name = "stock", run = stock},
        {name = "eui", suites = {EllesmereUI = {charsheetStyle = "eui"}}, run = eui},
        {name = "blizzard", suites = {EllesmereUI = {charsheetStyle = "blizzard"}}, run = euiStock},
        {name = "off", suites = {EllesmereUI = {charsheetStyle = "off"}}, run = euiStock},
        {name = "eui-late", suites = {EllesmereUI = {thirdPartySkinsOff = true}}, run = euiLate},
        {name = "elvui", suites = {ElvUI = {}}, run = elv},
    },
};
