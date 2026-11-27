-- (x) Sell guard, before the sale: while a merchant is open, GQ lays its own button over every bag slot holding a set
-- item the player cannot spare, in Blizzard's bags (combined and separate) and in EllesmereUIBags (grid and list).
-- A right-click there sells nothing: GQ asks "Are you sure you want to sell ...?", No keeps the item, Yes sells that
-- copy once and the buy-back watcher leaves it sold; the item never reaches the buyback list without a Yes, gold is
-- untouched until then. A left-click or a drag moves the item as usual (a drop onto a guarded slot too); dropped onto
-- the merchant it is sold and the sell guard's buy-back + question catch it. A modified click links it and never
-- sells; hovering shows the item's tooltip with other add-ons' lines. A spare copy, an item in no set and a
-- refundable item get no GQ button and behave as without GQ; when a copy is sold the last ones get one. The buttons go
-- with the merchant and with the option, follow an item to another slot and to another (recycled) slot button (at
-- once, also after EllesmereUIBags' redraw 0.1 s after the bag events), a stale one swallows one click and goes; they
-- are never made in combat (the buy-back stays the fallback) and keep asking in combat (Yes waits for its end). A Yes
-- while another copy is being bought back waits for it to land, and that sale is not bought back. GQ never replaces a
-- slot button's scripts or writes on it (H.assertSlotButtonsUntouched).

local function settle(H, seconds)
    H.advance((seconds or 1) + 3 * H.latency);
end

-- runs frame by frame until fn() holds (at most 3 s); true when it does
local function framesUntil(H, fn)
    for _ = 1, 60 do
        if fn() then
            return true;
        end
        H.advance(H.frameMs / 1000);
    end
    return fn() and true or false;
end

local function dialogShown()
    return GqSellGuardDialog ~= nil and GqSellGuardDialog:IsShown();
end

local function assertAsked(H, itemName, setText, msg)
    H.assertTrue(dialogShown(), msg .. ": GQ asks");
    local text = H.stripColors(GqSellGuardDialogText:GetText() or "");
    for _, part in ipairs({"Are you sure you want to sell", itemName, "This item is saved in " .. setText .. "."}) do
        H.assertTrue(text:find(part, 1, true), msg .. ": question mentions '" .. part .. "' (" .. text .. ")");
    end
end

local function answer(yes)
    (yes and GqSellGuardDialogButton1 or GqSellGuardDialogButton2):Click("LeftButton");
end

local function buybackCount(H, key)
    local n = 0;
    for _, entry in ipairs(H.buyback) do
        if entry.inst.key == key then
            n = n + 1;
        end
    end
    return n;
end

-- GQ's button on top of the slot, or nil when a click reaches the slot itself
local function overlayAt(H, bag, slot)
    local button, frame = H.bagSlotButton(bag, slot), H.frameAtBagSlot(bag, slot);
    if frame ~= button then
        H.assertEq(frame:GetParent(), button, "the frame on top of the slot is a child of it");
        return frame;
    end
end

-- the (first) copy of key in the bags has GQ's button on top; returns it, bag, slot
local function assertGuarded(H, key, msg)
    local bag, slot = H.bagSlotOf(key);
    local overlay = overlayAt(H, bag, slot);
    H.assertTrue(overlay, msg .. ": GQ's button over " .. key);
    local button = H.bagSlotButton(bag, slot);
    H.assertTrue(overlay:GetFrameLevel() > button:GetFrameLevel(), msg .. ": above the slot");
    return overlay, bag, slot;
end

local function assertOpen(H, bag, slot, msg)
    H.assertFalse(overlayAt(H, bag, slot), msg .. ": no GQ button over bag " .. bag .. " slot " .. slot);
end

-- after prepare: set A's pieces in the bags are single copies saved in Default and Tank
local GUARDED = {headA = true, chestA = true, legsA = true, feetA = true, handsA = true, backA = true, ringA = true,
    trinketA = true, sword = true, shield = true};

-- every visible slot: GQ's button on top exactly when it holds a guarded item
local function assertOverlaysMatch(H, msg, guarded)
    guarded = guarded or GUARDED;
    local checked = 0;
    for _, button in ipairs(H.allSlotButtons()) do
        if H.isVisible(button) then
            local bag, slot = button:GetBagID(), button:GetID();
            local inst = H.bags[bag] and H.bags[bag].slots[slot];
            local hit = H.frameAtBagSlot(bag, slot);
            H.assertEq(hit ~= button, inst ~= nil and guarded[inst.key] == true, string.format(
                "%s: GQ's button over bag %d slot %d (%s)", msg, bag, slot, inst and inst.key or "empty"));
            checked = checked + 1;
        end
    end
    H.assertTrue(checked > 0, msg .. ": slots checked");
end

local function tooltipHas(text)
    for i = 1, GameTooltip:NumLines() do
        local line = _G["GameTooltipTextLeft" .. i];
        if line and (line:GetText() or ""):find(text, 1, true) then
            return true;
        end
    end
    return false;
end

local function optionBox(H, text)
    for _, frame in ipairs(H.allFrames) do
        if frame:GetObjectType() == "CheckButton" and rawget(frame, "fontString") and frame.fontString:GetText() == text then
            return frame;
        end
    end
    H.fail("no option checkbox '" .. text .. "'", 2);
end

-- Tank = set A as worn at login; DPS = set B. Set A's displaced pieces end up in the bags.
local function prepare(H, gq, kind)
    H.advance(1);
    gq:SaveSet("Tank", false);
    H.wearSetBPieces();
    gq:SaveSet("DPS", false);
    H.openMerchant();
    H.openBags(kind);
    H.advance(0.2);
end

local function rightClick(kind)
    return function(H, gq)
        prepare(H, gq, kind);
        assertOverlaysMatch(H, "merchant open");
        local start, sales = H.money, #H.sold;
        local overlay, bag, slot = assertGuarded(H, "headA", "helm");
        local helm = H.bags[bag].slots[slot];
        local state = H.state(overlay);
        H.assertEq(overlay:GetObjectType(), "Button", "a plain button");
        H.assertEq(table.concat(state.clicks or {}, ","), "AnyUp", "takes every click");
        H.assertEq(table.concat(state.drag or {}, ","), "LeftButton", "takes the drag");

        -- a right-click asks; nothing is sold
        H.assertEq(H.clickBagSlot(bag, slot, "RightButton"), overlay, "GQ's button takes the right-click");
        assertAsked(H, "Helm of the Bastion", "sets Default, Tank", "right-click");
        H.assertFalse(C_Container.GetContainerItemInfo(bag, slot).isLocked, "the slot is not even locked");
        settle(H);
        H.assertEq(H.bags[bag].slots[slot], helm, "still in its slot");
        H.assertEq(#H.sold, sales, "nothing sold");
        H.assertEq(#H.buyback, 0, "the buyback list stays empty");
        H.assertEq(H.money, start, "gold unchanged");
        H.assertEq(#H.buybackCalls, 0, "nothing to buy back");

        -- No keeps it
        answer(false);
        settle(H);
        H.assertFalse(dialogShown(), "No closes the question");
        H.assertEq(H.bags[bag].slots[slot], helm, "kept");
        H.assertEq(#H.sold, sales, "still nothing sold");
        H.assertEq(H.money, start, "gold still unchanged");
        assertGuarded(H, "headA", "after No");

        -- asked again; Yes sells that copy once and it stays sold
        H.clickBagSlot(bag, slot, "RightButton");
        assertAsked(H, "Helm of the Bastion", "sets Default, Tank", "second right-click");
        answer(true);
        settle(H, 2);
        H.assertEq(H.countItem("headA"), 0, "sold after Yes");
        H.assertEq(#H.sold, sales + 1, "one sale");
        H.assertEq(H.sold[#H.sold], helm, "that copy");
        H.assertEq(buybackCount(H, "headA"), 1, "in the buyback list once");
        H.assertEq(#H.buybackCalls, 0, "the confirmed sale is not bought back");
        H.assertFalse(dialogShown(), "no question after the sale");
        H.assertEq(H.money, start + H.sellPrice(helm), "paid once");
        assertOverlaysMatch(H, "after the sale");

        -- an item in no set: Blizzard's own right-click sells it
        local mbag, mslot = H.bagSlotOf("mace");
        local mace = H.bags[mbag].slots[mslot];
        H.assertEq(H.clickBagSlot(mbag, mslot, "RightButton"), H.bagSlotButton(mbag, mslot), "the slot takes the click");
        settle(H);
        H.assertEq(H.countItem("mace"), 0, "mace sold");
        H.assertFalse(dialogShown(), "no question for an item in no set");
        H.assertEq(#H.buybackCalls, 0, "not bought back");
        H.assertEq(H.money, start + H.sellPrice(helm) + H.sellPrice(mace), "paid for the mace");

        -- the next set item is guarded as before
        local _, cbag, cslot = assertGuarded(H, "chestA", "chest");
        H.clickBagSlot(cbag, cslot, "RightButton");
        assertAsked(H, "Bastion Breastplate", "sets Default, Tank", "chest");
        answer(false);
        settle(H);
        H.assertInBags("chestA", 1, "chest kept");
        H.assertEq(#H.blocked, 0, "no blocked call");
        H.assertCursorEmpty();
        H.assertSlotButtonsUntouched();
    end;
end

-- left-click, drag, drop, modified clicks, tooltip
local function moving(H, gq)
    prepare(H, gq, "combined");
    local overlay, bag, slot = assertGuarded(H, "headA", "helm");
    local helm = H.bags[bag].slots[slot];
    H.assertEq(H.bags[4].slots[16], nil, "bag 4 slot 16 is free");

    -- a left-click picks it up, a click on a free slot puts it down there
    H.assertEq(H.clickBagSlot(bag, slot, "LeftButton"), overlay, "GQ's button takes the left-click");
    H.assertEq(H.cursorItem(), helm, "the helm is on the cursor");
    H.clickBagSlot(4, 16, "LeftButton");
    settle(H);
    H.assertCursorEmpty();
    H.assertEq(H.bags[4].slots[16], helm, "moved");
    H.assertEq(H.bags[bag].slots[slot], nil, "the old slot is empty");
    assertOpen(H, bag, slot, "the old slot");
    assertGuarded(H, "headA", "the GQ button follows the helm");

    -- a drag works the same; a drop onto a guarded slot swaps the items
    H.dragBagSlot(4, 16);
    H.assertEq(H.cursorItem(), helm, "dragged");
    H.dropOnBagSlot(4, 15);
    settle(H);
    H.assertEq(H.bags[4].slots[15], helm, "dropped on a free slot");
    local mbag, mslot = H.bagSlotOf("mace");
    local mace = H.bags[mbag].slots[mslot];
    H.dragBagSlot(mbag, mslot);
    H.assertEq(H.cursorItem(), mace, "the mace is dragged");
    H.assertEq(H.dropOnBagSlot(4, 15), overlayAt(H, 4, 15), "GQ's button takes the drop");
    settle(H);
    H.assertEq(H.bags[4].slots[15], mace, "swapped: the mace");
    H.assertEq(H.bags[mbag].slots[mslot], helm, "swapped: the helm");
    assertOverlaysMatch(H, "after the moves");
    H.assertEq(#H.sold, 0, "moving sells nothing");

    -- dropped onto the merchant it is sold: the sell guard buys it back and asks
    local hbag, hslot = H.bagSlotOf("headA");
    H.clickBagSlot(hbag, hslot, "LeftButton");
    H.dropOnMerchant();
    settle(H);
    H.assertInBags("headA", 1, "bought back");
    H.assertEq(#H.buybackCalls, 1, "the fallback buy-back");
    assertAsked(H, "Helm of the Bastion", "sets Default, Tank", "drop on the merchant");
    answer(false);
    settle(H);
    assertGuarded(H, "headA", "guarded again after the buy-back");

    -- modified clicks link the item and never sell it
    hbag, hslot = H.bagSlotOf("headA");
    local before = #H.modifiedClicks;
    H.clickBagSlot(hbag, hslot, "RightButton", {shift = true});
    H.clickBagSlot(hbag, hslot, "LeftButton", {ctrl = true});
    H.clickBagSlot(hbag, hslot, "RightButton", {alt = true});
    settle(H);
    H.assertEq(#H.modifiedClicks, before + 3, "three modified clicks handled");
    H.assertEq(H.modifiedClicks[before + 1].action, "CHATLINK", "shift links");
    H.assertTrue(H.modifiedClicks[before + 1].link:find("Helm of the Bastion", 1, true), "the helm's link");
    H.assertEq(H.modifiedClicks[before + 2].action, "DRESSUP", "ctrl tries it on");
    H.assertFalse(dialogShown(), "no question");
    H.assertInBags("headA", 1, "not sold");
    H.assertCursorEmpty();
    H.assertEq(#H.buybackCalls, 1, "no buy-back");

    -- hovering shows the bag item's tooltip, other add-ons' lines included (GQ's own set line)
    local hovered = H.hoverBagSlot(hbag, hslot);
    H.assertEq(hovered, overlayAt(H, hbag, hslot), "GQ's button is hovered");
    H.assertTrue(GameTooltip:IsShown(), "tooltip shown");
    H.assertEq(GameTooltip:GetOwner(), hovered, "owned by GQ's button");
    H.assertEq(select(3, GameTooltip:GetItem()), helm.id, "the helm's tooltip");
    H.assertTrue(tooltipHas("GearQuipper set(s):"), "set line in the tooltip");
    H.leaveBagSlot();
    H.assertFalse(GameTooltip:IsShown(), "hidden on leave");

    -- asked, then moved before the answer: Yes sells the helm from where it is now
    H.clickBagSlot(hbag, hslot, "RightButton");
    assertAsked(H, "Helm of the Bastion", "sets Default, Tank", "before the move");
    H.clickBagSlot(hbag, hslot, "LeftButton");
    H.clickBagSlot(4, 14, "LeftButton");
    settle(H);
    H.assertEq(H.bags[4].slots[14], helm, "moved while asked");
    answer(true);
    settle(H, 2);
    H.assertEq(H.countItem("headA"), 0, "sold after Yes");
    H.assertEq(buybackCount(H, "headA"), 1, "in the buyback list");
    H.assertEq(#H.buybackCalls, 1, "the confirmed sale is not bought back");
    H.assertEq(#H.blocked, 0, "no blocked call");
    H.assertSlotButtonsUntouched();
end

-- three copies of a ring the set needs twice: spares sell as usual until only the needed copies are left
local function spares(H, gq)
    H.advance(1);
    gq:SaveSet("Tank", false); -- two Signets of Twins
    H.playerEquip("ringA", 11);
    H.playerEquip("ringB", 12);
    H.advance(0.5);
    H.assertInBags("twinRing", 3);
    H.openMerchant();
    H.openBags("combined");
    H.advance(0.2);
    local guarded = {};
    assertOverlaysMatch(H, "three copies", guarded);

    local bag, slot = H.bagSlotOf("twinRing");
    H.clickBagSlot(bag, slot, "RightButton");
    settle(H);
    H.assertInBags("twinRing", 2, "a spare copy is sold as usual");
    H.assertEq(#H.buybackCalls, 0, "not bought back");
    H.assertFalse(dialogShown(), "no question for a spare copy");
    guarded.twinRing = true;
    assertOverlaysMatch(H, "two copies left", guarded);

    bag, slot = H.bagSlotOf("twinRing");
    H.clickBagSlot(bag, slot, "RightButton");
    assertAsked(H, "Signet of Twins", "sets Default, Tank", "needed copy");
    answer(false);
    settle(H);
    H.assertInBags("twinRing", 2, "kept");
    H.assertEq(buybackCount(H, "twinRing"), 1, "only the spare in the buyback list");

    -- a refundable copy: Blizzard's refund popup comes first, and the refund guard watches it
    local first = H.bags[bag].slots[slot];
    first.refundable = true;
    gq:RefreshSellBlock();
    assertOpen(H, bag, slot, "refundable");
    H.clickBagSlot(bag, slot, "RightButton");
    H.advance(0.1);
    local popup = H.blizzPopup("CONFIRM_REFUND_TOKEN_ITEM");
    H.assertTrue(popup, "Blizzard's refund popup");
    H.assertFalse(dialogShown(), "GQ does not ask in its place");
    H.assertTrue(H.clickPopup(popup, 2), "the player says No");
    settle(H);
    H.assertInBags("twinRing", 2, "not refunded");
    H.assertEq(#H.refunded, 0);

    -- Yes on the other copy sells exactly that one
    local other = H.find("twinRing");
    local obag, oslot;
    for _, loc in ipairs(other) do
        if loc.kind == "bag" and H.bags[loc.bag].slots[loc.slot] ~= first then
            obag, oslot = loc.bag, loc.slot;
        end
    end
    local second = H.bags[obag].slots[oslot];
    H.assertEq(H.clickBagSlot(obag, oslot, "RightButton"), overlayAt(H, obag, oslot), "GQ's button");
    assertAsked(H, "Signet of Twins", "sets Default, Tank", "the other copy");
    answer(true);
    settle(H, 2);
    H.assertEq(H.sold[#H.sold], second, "that copy sold");
    H.assertEq(H.bags[bag].slots[slot], first, "the refundable copy kept");
    H.assertEq(#H.buybackCalls, 0, "not bought back");
    H.assertSlotButtonsUntouched();
end

local function twinsSetup(H)
    H.equip("twinRing", 11);
    H.equip("twinRing", 12);
    H.give("twinRing");
    H.give("ringA");
    H.give("ringB");
end

-- two copies, both needed
local function twoTwinsSetup(H)
    H.equip("twinRing", 11);
    H.equip("twinRing", 12);
    H.give("ringA");
    H.give("ringB");
end

local function merchantAndOption(H, gq)
    prepare(H, gq, "combined");
    local overlay, bag, slot = assertGuarded(H, "headA", "merchant open");
    H.closeMerchant();
    H.advance(0.2);
    H.assertFalse(overlay:IsShown(), "GQ's button goes with the merchant");
    assertOverlaysMatch(H, "merchant closed", {});
    H.openMerchant();
    H.advance(0.2);
    assertOverlaysMatch(H, "next merchant");

    -- option off: GQ's buttons go at once, the item sells as without GQ
    local box = optionBox(H, "Protect set items from selling");
    box:Click("LeftButton");
    H.assertEq(GQ_OPTIONS[gq.OPT_PROTECT_SELL], false, "option off");
    assertOverlaysMatch(H, "option off", {});
    H.clickBagSlot(bag, slot, "RightButton");
    settle(H);
    H.assertEq(H.countItem("headA"), 0, "sold with the guard off");
    H.assertEq(#H.buybackCalls, 0, "not bought back");
    H.assertFalse(dialogShown(), "no question");
    settle(H);
    assertOverlaysMatch(H, "option still off", {});

    box:Click("LeftButton");
    H.assertEq(GQ_OPTIONS[gq.OPT_PROTECT_SELL], true, "option on again");
    assertOverlaysMatch(H, "option on again");
    local _, cbag, cslot = assertGuarded(H, "chestA", "option on again");
    H.clickBagSlot(cbag, cslot, "RightButton");
    assertAsked(H, "Bastion Breastplate", "sets Default, Tank", "option on again");
    answer(false);
    settle(H);
    H.assertInBags("chestA", 1, "kept");

    -- sets deleted at the merchant (no bag event): a GQ button left over the chest until GQ's next look swallows that
    -- one click and goes, the rescan takes the others away
    gq:RemoveSet("Tank");
    gq:RemoveSet(DEFAULT);
    H.assertTrue(overlayAt(H, cbag, cslot), "GQ's button still over the chest");
    H.clickBagSlot(cbag, cslot, "RightButton");
    H.assertFalse(dialogShown(), "no question for an item in no set");
    H.assertInBags("chestA", 1, "nothing sold by the stale button");
    assertOpen(H, cbag, cslot, "the stale button went");
    H.advance(0.6);
    assertOverlaysMatch(H, "sets deleted", {});
    H.assertSlotButtonsUntouched();
end

-- Blizzard's pool hands its buttons out again on every show: GQ's buttons follow the slots at once
local function blizzardRecycled(H, gq)
    prepare(H, gq, "combined");
    local bag, slot = H.bagSlotOf("headA");
    local button = H.bagSlotButton(bag, slot);
    H.closeBags();
    H.openBags("combined");
    H.assertTrue(H.bagSlotButton(bag, slot) ~= button, "another slot button shows the helm now");
    assertOverlaysMatch(H, "right after reopening");
    H.clickBagSlot(bag, slot, "RightButton");
    assertAsked(H, "Helm of the Bastion", "sets Default, Tank", "after reopening");
    answer(false);
    settle(H);
    assertOverlaysMatch(H, "later");

    -- an item landing in the bags (loot, mail): GQ's button is on it from the frame Blizzard paints it (the slot's own
    -- icon method is hooked), a frame before GQ's look at BAG_UPDATE_DELAYED
    H.clickBagSlot(bag, slot, "RightButton");
    answer(true);
    settle(H, 2);
    H.assertEq(H.countItem("headA"), 0, "sold after Yes");
    H.give("headA");
    H.advance(0);
    local nbag, nslot = H.bagSlotOf("headA");
    H.assertEq(H.bagSlotButton(nbag, nslot).icon:GetTexture(), H.items.headA.icon, "Blizzard shows the new helm");
    H.assertTrue(overlayAt(H, nbag, nslot), "GQ's button is on it in that frame");
    settle(H);
    assertOverlaysMatch(H, "after the landing");
    H.assertSlotButtonsUntouched();
end

local function euiSetup(view)
    return function(H)
        H.installEuiBags({view = view});
        H.defineItem({key = "amulet", name = "Amber Amulet", equipLoc = "INVTYPE_NECK", quality = 2});
        H.give("gun");
    end;
end

-- EllesmereUIBags sorts by name: a sale or a new item moves every later item to another slot button
local function euiRecycled(H, gq)
    prepare(H, gq, "eui");
    assertOverlaysMatch(H, "opened");
    local bag, slot = H.bagSlotOf("headA");
    local button = H.bagSlotButton(bag, slot);
    local gbag, gslot = H.bagSlotOf("gun"); -- "Gun of Testing" is listed right before the helm
    local gunButton = H.bagSlotButton(gbag, gslot);
    H.clickBagSlot(gbag, gslot, "RightButton");
    -- EllesmereUIBags redraws 0.1 s after the bag event, after GQ's look at that event: GQ's buttons follow the redraw
    -- at once, so the next right-click on the gun's row (spam-vendoring) asks about the helm listed there now
    H.assertTrue(framesUntil(H, function()
        return H.bagSlotButton(bag, slot) ~= button;
    end), "another slot button shows the helm now");
    H.assertEq(H.bagSlotButton(bag, slot), gunButton, "the helm moved into the gun's row");
    H.assertEq(H.countItem("gun"), 0, "gun sold");
    assertOverlaysMatch(H, "right after the redraw");
    H.clickBagSlot(bag, slot, "RightButton");
    assertAsked(H, "Helm of the Bastion", "sets Default, Tank", "right after the redraw");
    answer(false);
    settle(H);
    H.assertInBags("headA", 1, "kept");
    H.assertEq(#H.buybackCalls, 0, "never sold, nothing to buy back");
    assertOverlaysMatch(H, "after the sale");

    -- a new item listed first, redrawn before GQ's next look: GQ's buttons follow at once (the grid sets each slot's
    -- icon, the list paints its own: GQ follows the window's redraw)
    H.give("amulet");
    H.euiBags.window:RefreshInventory();
    local abag, aslot = H.bagSlotOf("amulet");
    assertOverlaysMatch(H, "redrawn");
    settle(H);
    assertOverlaysMatch(H, "after the next look");
    H.clickBagSlot(abag, aslot, "RightButton");
    settle(H);
    H.assertEq(H.countItem("amulet"), 0, "the amulet sells as usual");
    H.assertFalse(dialogShown(), "no question");

    -- EllesmereUIBags raises its window: its slots follow, so do GQ's buttons
    H.euiBags.raise(30);
    H.euiBags.window:RefreshInventory();
    settle(H);
    assertOverlaysMatch(H, "window raised");
    local _, hbag, hslot = assertGuarded(H, "headA", "window raised");
    H.clickBagSlot(hbag, hslot, "RightButton");
    assertAsked(H, "Helm of the Bastion", "sets Default, Tank", "window raised");
    answer(true);
    settle(H, 2);
    H.assertEq(H.countItem("headA"), 0, "sold after Yes");
    H.assertEq(#H.buybackCalls, 0, "nothing bought back");
    assertOverlaysMatch(H, "the end");
    H.assertSlotButtonsUntouched();
end

local function combat(H, gq)
    H.advance(1);
    gq:SaveSet("Tank", false);
    H.wearSetBPieces();
    gq:SaveSet("DPS", false);
    H.setCombat(true);
    H.openMerchant();
    H.openBags("combined");
    H.advance(0.2);

    -- nothing is added to a secure slot in combat: the sale goes through, the buy-back follows after combat
    local bag, slot = H.bagSlotOf("headA");
    assertOverlaysMatch(H, "in combat, first look", {});
    H.clickBagSlot(bag, slot, "RightButton");
    settle(H, 2);
    H.assertEq(H.countItem("headA"), 0, "sold in combat");
    H.assertEq(#H.buybackCalls, 0, "no buy-back in combat");
    H.setCombat(false);
    settle(H);
    H.assertInBags("headA", 1, "bought back after combat");
    assertAsked(H, "Helm of the Bastion", "sets Default, Tank", "after combat");
    answer(false);
    settle(H);
    assertOverlaysMatch(H, "after combat");

    -- a GQ button made before combat keeps asking in combat; Yes waits for the end of combat
    H.setCombat(true);
    H.advance(0.6);
    local _, cbag, cslot = assertGuarded(H, "chestA", "in combat");
    H.clickBagSlot(cbag, cslot, "RightButton");
    assertAsked(H, "Bastion Breastplate", "sets Default, Tank", "in combat");
    answer(true);
    settle(H, 2);
    H.assertInBags("chestA", 1, "not sold in combat");
    H.assertEq(buybackCount(H, "chestA"), 0, "not in the buyback list");
    H.setCombat(false);
    settle(H, 2);
    H.assertEq(H.countItem("chestA"), 0, "sold after combat");
    H.assertEq(buybackCount(H, "chestA"), 1, "once");
    H.assertEq(#H.buybackCalls, 1, "the confirmed sale is not bought back");
    H.assertEq(#H.blocked, 0, "no blocked call");
    H.assertSlotButtonsUntouched();
end

-- Yes before the sale while another copy of that item is being bought back: the copy bought back lands first, then
-- the asked copy is sold, and the buy-back never takes that confirmed sale back
local function yesDuringBuyback(H, gq)
    H.advance(1);
    gq:SaveSet("Tank", false); -- two Signets of Twins
    H.playerEquip("ringA", 11);
    H.playerEquip("ringB", 12);
    H.advance(0.5);
    H.assertInBags("twinRing", 2);
    H.openMerchant();
    H.openBags("combined");
    H.advance(0.2);
    local copies = {};
    for _, loc in ipairs(H.find("twinRing")) do
        if loc.kind == "bag" then
            copies[#copies + 1] = loc;
        end
    end
    local a, b = copies[1], copies[2];
    local copyA, copyB = H.bags[a.bag].slots[a.slot], H.bags[b.bag].slots[b.slot];
    local start = H.money;
    H.clickBagSlot(a.bag, a.slot, "RightButton");
    assertAsked(H, "Signet of Twins", "sets Default, Tank", "copy A");

    -- copy B leaves another way while GQ asks: dropped onto the merchant, GQ buys it back
    H.dragBagSlot(b.bag, b.slot);
    H.dropOnMerchant();
    H.assertTrue(framesUntil(H, function()
        return #H.buybackCalls == 1;
    end), "GQ buys copy B back");
    H.assertEq(H.countItem("twinRing"), 1, "copy B is not back yet");
    answer(true);
    settle(H, 4);
    H.assertEq(H.countItem("twinRing"), 1, "copy A sold, copy B back");
    H.assertEq(H.sold[#H.sold], copyA, "copy A was sold last");
    H.assertEq(#H.buybackCalls, 1, "only copy B bought back");
    H.assertEq(buybackCount(H, "twinRing"), 1, "copy A stays in the buyback list");
    H.assertFalse(dialogShown(), "nothing else asked");
    H.assertEq(H.money, start + H.sellPrice(copyA), "paid for copy A once, copy B paid back");
    H.assertEq(#H.blocked, 0, "no blocked call");
    H.assertSlotButtonsUntouched();
end

return {
    variants = {
        {name = "right-click asks first: Blizzard's combined bags", run = rightClick("combined")},
        {name = "right-click asks first: Blizzard's separate bags", run = rightClick("separate")},
        {name = "right-click asks first: EllesmereUIBags grid", run = rightClick("eui"), setup = euiSetup("grid")},
        {name = "right-click asks first: EllesmereUIBags list", run = rightClick("eui"), setup = euiSetup("list")},
        {name = "left-click, drag, drop on the merchant, modified clicks, tooltip", run = moving},
        {name = "spare copies and a refundable copy", run = spares, setup = twinsSetup},
        {name = "merchant closed and option off", run = merchantAndOption},
        {name = "recycled buttons: Blizzard's bags reopened", run = blizzardRecycled},
        {name = "recycled buttons: EllesmereUIBags grid", run = euiRecycled, setup = euiSetup("grid")},
        {name = "recycled buttons: EllesmereUIBags list", run = euiRecycled, setup = euiSetup("list")},
        {name = "combat", run = combat},
        -- the buy-back has to be in flight when Yes is given: a latency of its own
        {name = "Yes while another copy is bought back (latency 0.3)", run = yesDuringBuyback, setup = twoTwinsSetup,
            latency = 0.3},
        {name = "Yes while another copy is bought back (latency 0.15)", run = yesDuringBuyback, setup = twoTwinsSetup,
            latency = 0.15},
    },
};
