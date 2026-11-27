-- (x) Sell guard: a set item the player cannot spare is bought back as soon as it shows up in the merchant's buyback
-- list, then GQ asks "Are you sure you want to sell ...? This item is saved in set ...". No keeps it; Yes sells it
-- again, once. Every sell path is covered (right-click, drag, the trade-timer popup, another add-on's burst of
-- UseContainerItem calls, a junk-selling ticker, Sell All Junk) because GQ only reads the buyback list. A spare copy,
-- an item in no set and a sale with the option off stay sold; nothing is bought back or sold again in combat; a full
-- buyback list (the oldest entry drops out, even with the same link) is handled; closing the merchant drops the
-- questions; a junk seller that keeps selling the item is given up after 3 buy-backs with one chat hint; gold ends
-- where it would without the guard. A spec swap (it changes every buyback link) neither undoes a confirmed sale nor
-- loses an item waiting for the next merchant.
-- No bag window is open here, so GQ has no button over the slots: H.sellBagItem is the slot's own right-click, as on a
-- slot GQ does not cover (a bag add-on it does not know, a slot first seen in combat). The right-click GQ catches
-- before the sale is scenario 26.

local function settle(H, seconds)
    H.advance((seconds or 1) + 3 * H.latency);
end

local function dialogShown()
    return GqSellGuardDialog ~= nil and GqSellGuardDialog:IsShown();
end

local function dialogText(H)
    return H.stripColors(GqSellGuardDialogText:GetText() or "");
end

local function assertAsked(H, itemName, setText, msg)
    H.assertTrue(dialogShown(), msg .. ": GQ asks");
    local text = dialogText(H);
    for _, part in ipairs({"Are you sure you want to sell", itemName, "This item is saved in " .. setText .. "."}) do
        H.assertTrue(text:find(part, 1, true), msg .. ": question mentions '" .. part .. "' (" .. text .. ")");
    end
end

local function answer(yes)
    (yes and GqSellGuardDialogButton1 or GqSellGuardDialogButton2):Click("LeftButton");
end

local function instAt(H, bag, slot)
    return H.bags[bag].slots[slot];
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

local function callsFor(H, key)
    local n = 0;
    for _, call in ipairs(H.buybackCalls) do
        if call.inst.key == key then
            H.assertEq(call.by, "addon", "buy-backs are GQ's");
            n = n + 1;
        end
    end
    return n;
end

local function chatCount(H, text)
    local n = 0;
    for _, line in ipairs(H.chat) do
        if H.stripColors(line):find(text, 1, true) then
            n = n + 1;
        end
    end
    return n;
end

-- Tank = set A as worn at login; DPS = set B. Set A's displaced pieces end up in the bags.
local function prepare(H, gq)
    H.advance(1);
    gq:SaveSet("Tank", false);
    H.wearSetBPieces();
    gq:SaveSet("DPS", false);
    H.openMerchant();
    H.advance(0.2);
end

local function optionBox(H, text)
    for _, frame in ipairs(H.allFrames) do
        if frame:GetObjectType() == "CheckButton" and rawget(frame, "fontString") and frame.fontString:GetText() == text then
            return frame;
        end
    end
    H.fail("no option checkbox '" .. text .. "'", 2);
end

local function rightClickConfirm(H, gq)
    prepare(H, gq);
    gq:RemoveSet(DEFAULT); -- set A is only in Tank now
    local start = H.money;

    -- an item in no set is sold as usual
    local bag, slot = H.bagSlotOf("mace");
    local mace = instAt(H, bag, slot);
    H.sellBagItem(bag, slot);
    settle(H);
    H.assertEq(H.countItem("mace"), 0, "mace sold");
    H.assertEq(#H.buybackCalls, 0, "an item in no set is not bought back");
    H.assertFalse(dialogShown(), "no question for an item in no set");
    H.assertEq(H.money, start + H.sellPrice(mace), "paid for the mace");
    local afterMace = H.money;

    -- a set item: sold, bought back at once, then GQ asks
    bag, slot = H.bagSlotOf("headA");
    local helm = instAt(H, bag, slot);
    H.sellBagItem(bag, slot);
    settle(H);
    H.assertInBags("headA", 1, "the helm is back");
    H.assertEq(callsFor(H, "headA"), 1, "one buy-back");
    H.assertEq(buybackCount(H, "headA"), 0, "not in the buyback list any more");
    assertAsked(H, "Helm of the Bastion", "set Tank", "right-click sale");
    H.assertEq(H.money, afterMace, "gold net zero after the buy-back");

    -- No: kept, nothing else happens
    answer(false);
    settle(H, 2);
    H.assertFalse(dialogShown(), "No closes the question");
    H.assertInBags("headA", 1, "kept");
    H.assertEq(#H.buybackCalls, 1, "no further buy-back");
    H.assertEq(H.money, afterMace, "gold unchanged");

    -- sold again: asked again; Yes sells it once and it stays sold
    H.sellBagItem(H.bagSlotOf("headA"));
    settle(H);
    H.assertInBags("headA", 1, "bought back again");
    assertAsked(H, "Helm of the Bastion", "set Tank", "second sale");
    answer(true);
    settle(H, 3);
    H.assertEq(H.countItem("headA"), 0, "sold after Yes");
    H.assertEq(buybackCount(H, "headA"), 1, "in the buyback list once");
    H.assertEq(callsFor(H, "headA"), 2, "the confirmed sale is not undone");
    H.assertFalse(dialogShown(), "no question for the confirmed sale");
    H.assertEq(H.money, afterMace + H.sellPrice(helm), "gold as if sold once");

    -- the confirmation was for that one sale: the next set item is guarded again; the set shows in its colour
    H.assertTrue(gq:SaveSetColor("Tank", "33ccff"), "Tank coloured");
    H.sellBagItem(H.bagSlotOf("chestA"));
    settle(H);
    H.assertInBags("chestA", 1, "chest bought back");
    assertAsked(H, "Bastion Breastplate", "set Tank", "after a confirmed sale");
    H.assertTrue(GqSellGuardDialogText:GetText():find("set |cff33ccffTank|r.", 1, true), "set name in its colour");
    answer(false);
    settle(H);
    H.assertEq(#H.blocked, 0, "no blocked call");
    H.assertCursorEmpty();
end

local function dragAndTradeTimer(H, gq)
    prepare(H, gq);
    local start = H.money;

    H.dragToMerchant(H.bagSlotOf("legsA"));
    settle(H);
    H.assertInBags("legsA", 1, "dragged legs bought back");
    assertAsked(H, "Bastion Legplates", "sets Default, Tank", "drag sale");
    answer(false);
    settle(H);

    -- an item still tradable with the group: Blizzard asks first, its Yes calls SellCursorItem
    local bag, slot = H.bagSlotOf("feetA");
    instAt(H, bag, slot).tradeTimer = true;
    H.dragToMerchant(bag, slot);
    H.advance(0.1);
    local popup = H.blizzPopup("CONFIRM_MERCHANT_TRADE_TIMER_REMOVAL");
    H.assertTrue(popup, "Blizzard's trade-timer popup");
    H.assertFalse(dialogShown(), "nothing sold yet");
    H.assertTrue(H.clickPopup(popup, 1), "the player confirms Blizzard's popup");
    settle(H);
    H.assertInBags("feetA", 1, "feet bought back after SellCursorItem");
    H.assertEq(#H.buybackCalls, 2);
    assertAsked(H, "Bastion Sabatons", "sets Default, Tank", "trade-timer sale");
    answer(false);
    settle(H);
    H.assertEq(H.money, start, "gold net zero");
    H.assertCursorEmpty();
end

-- another add-on (TSM style) sells several items in one frame
local function burst(H, gq)
    prepare(H, gq);
    local start, earned = H.money, 0;
    local slots = {};
    for _, key in ipairs({"headA", "mace", "chestA", "orb"}) do
        local bag, slot = H.bagSlotOf(key);
        slots[#slots + 1] = {bag, slot};
        if key == "mace" or key == "orb" then
            earned = earned + H.sellPrice(instAt(H, bag, slot));
        end
    end
    for _, s in ipairs(slots) do
        C_Container.UseContainerItem(s[1], s[2]);
    end
    settle(H, 1.5);
    H.assertInBags("headA", 1, "helm back");
    H.assertInBags("chestA", 1, "chest back");
    H.assertEq(H.countItem("mace") + H.countItem("orb"), 0, "items in no set stay sold");
    H.assertEq(#H.buybackCalls, 2, "two buy-backs");
    H.assertEq(H.money, start + earned, "gold: only the items in no set were sold");

    -- one question at a time, in sale order
    assertAsked(H, "Helm of the Bastion", "sets Default, Tank", "first question");
    answer(false);
    H.advance(0.1);
    assertAsked(H, "Bastion Breastplate", "sets Default, Tank", "second question");
    local bag, slot = H.bagSlotOf("chestA");
    local chestPrice = H.sellPrice(instAt(H, bag, slot));
    answer(true);
    settle(H, 2);
    H.assertFalse(dialogShown(), "all answered");
    H.assertInBags("headA", 1, "helm kept");
    H.assertEq(H.countItem("chestA"), 0, "chest sold after Yes");
    H.assertEq(#H.buybackCalls, 2, "no buy-back of the confirmed sale");
    H.assertEq(H.money, start + earned + chestPrice);
end

-- Leatrix Plus style: a ticker sells every grey item in the bags while the merchant is open
local function junkTicker(H, gq)
    H.advance(1);
    gq:SaveSet("Tank", false); -- the grey shirt is part of it
    H.assertEq(gq:LoadSlot(4, "Tank"), gq:GetItemString(4), "grey shirt saved");
    H.playerEquip("shirt", 4);
    H.advance(0.5);
    H.assertInBags("greyShirt", 1);
    H.openMerchant();
    H.advance(0.2);
    local ticker = C_Timer.NewTicker(0.2, function()
        for _, bagId in ipairs({0, 1, 2, 3, 4}) do
            for slot = 1, C_Container.GetContainerNumSlots(bagId) do
                local info = C_Container.GetContainerItemInfo(bagId, slot);
                if info and info.quality == 0 and not info.isLocked then
                    C_Container.UseContainerItem(bagId, slot);
                end
            end
        end
    end, 500);
    settle(H, 8);
    ticker:Cancel();
    H.assertEq(callsFor(H, "greyShirt"), 3, "bought back 3 times, then given up");
    H.assertEq(H.countItem("greyShirt"), 0, "the junk seller won");
    H.assertEq(H.countItem("junk"), 0, "junk sold");
    H.assertEq(chatCount(H, "keeps selling [Frayed Shirt] (saved in sets Default, Tank)"), 1, "one chat hint");
    H.assertFalse(dialogShown(), "no question left for an item that is gone");
    settle(H, 3);
    H.assertEq(callsFor(H, "greyShirt"), 3, "no further buy-back at this merchant");

    -- a new visit starts a new count
    H.closeMerchant();
    H.advance(0.2);
    H.openMerchant();
    H.advance(0.2);
    H.assertEq(callsFor(H, "greyShirt"), 3, "an old sale is not bought back at the next merchant");
end

local function sellAllJunk(H, gq)
    H.advance(1);
    gq:SaveSet("Tank", false);
    H.playerEquip("shirt", 4);
    H.advance(0.5);
    H.openMerchant();
    H.advance(0.2);
    H.sellAllJunk();
    settle(H);
    H.assertInBags("greyShirt", 1, "Sell All Junk undone for the set item");
    H.assertEq(H.countItem("junk"), 0, "the rest of the junk sold");
    assertAsked(H, "Frayed Shirt", "sets Default, Tank", "Sell All Junk");
    answer(true);
    settle(H, 2);
    H.assertEq(H.countItem("greyShirt"), 0, "sold after Yes");
    H.assertEq(callsFor(H, "greyShirt"), 1);
end

local function greySetup(H)
    H.defineItem({key = "greyShirt", name = "Frayed Shirt", equipLoc = "INVTYPE_BODY", quality = 0});
    H.equip("greyShirt", 4);
    H.give("shirt");
    for _ = 1, 3 do
        H.give("junk");
    end
end

-- a spare copy stays sold; with the buyback list full the oldest entry drops out, here with the same link
local function spareAndFullList(H, gq)
    H.advance(1);
    gq:SaveSet("Tank", false); -- needs one Signet of Twins (slot 12)
    H.openMerchant();
    H.advance(0.2);
    H.sellBagItem(H.bagSlotOf("twinRing"));
    settle(H);
    H.assertEq(H.countItem("twinRing"), 1, "the spare copy is sold");
    H.assertEq(#H.buybackCalls, 0, "a spare copy is not bought back");
    H.assertFalse(dialogShown(), "no question for a spare copy");

    for _ = 1, 11 do
        H.sellBagItem(H.bagSlotOf("junk"));
        H.advance(0.05 + H.latency);
    end
    settle(H);
    H.assertEq(#H.buyback, 12, "buyback list full");
    H.assertEq(H.buyback[1].inst.key, "twinRing", "the spare ring is the oldest entry");

    H.playerEquip("ringB", 12); -- the worn ring goes to the bags
    H.advance(0.5);
    local before = H.money;
    H.sellBagItem(H.bagSlotOf("twinRing"));
    settle(H);
    H.assertInBags("twinRing", 1, "the last copy is bought back");
    H.assertEq(#H.buybackCalls, 1);
    H.assertEq(H.buybackCalls[1].index, 12, "the newest entry");
    assertAsked(H, "Signet of Twins", "sets Default, Tank", "full list");
    H.assertEq(H.money, before, "gold net zero");
    H.assertEq(#H.buyback, 11);
    answer(false);
end

local function ringSetup(H)
    H.equip("twinRing", 12);
    H.give("twinRing");
    H.give("ringB");
    for _ = 1, 11 do
        H.give("junk");
    end
end

-- a set wearing two identical rings: Yes while the buy-back is still on its way sells one copy, not the other one
local function twinsYesEarly(H, gq)
    H.advance(1);
    gq:SaveSet("Tank", false); -- two Signets of Twins
    H.playerEquip("ringA", 11);
    H.playerEquip("ringB", 12);
    H.advance(0.5);
    H.assertInBags("twinRing", 2);
    H.openMerchant();
    H.advance(0.2);
    H.sellBagItem(H.bagSlotOf("twinRing"));
    H.assertTrue(H.waitFor(dialogShown, 3), "asked");
    H.assertEq(H.countItem("twinRing"), 1, "the bought-back copy is still on its way");
    answer(true);
    settle(H, 3);
    H.assertEq(H.countItem("twinRing"), 1, "one copy sold, one kept");
    H.assertEq(callsFor(H, "twinRing"), 1, "bought back once");
    H.assertEq(buybackCount(H, "twinRing"), 1);
    H.assertFalse(dialogShown());
end

local function twinsSetup(H)
    H.equip("twinRing", 11);
    H.equip("twinRing", 12);
    H.give("ringA");
    H.give("ringB");
end

-- the player may sell in combat; GQ buys back and sells again only out of combat
local function combat(H, gq)
    prepare(H, gq);
    H.setCombat(true);
    H.sellBagItem(H.bagSlotOf("headA"));
    settle(H, 2);
    H.assertEq(H.countItem("headA"), 0, "not bought back in combat");
    H.assertEq(#H.buybackCalls, 0, "no buy-back tried in combat");
    H.assertEq(#H.blocked, 0, "no blocked call");
    H.assertFalse(dialogShown(), "no question before the buy-back");
    H.setCombat(false);
    settle(H);
    H.assertInBags("headA", 1, "bought back after combat");
    assertAsked(H, "Helm of the Bastion", "sets Default, Tank", "after combat");

    -- Yes in combat: sold again when combat ends
    H.setCombat(true);
    answer(true);
    settle(H, 2);
    H.assertInBags("headA", 1, "not sold again in combat");
    H.assertEq(#H.blocked, 0, "no blocked call");
    H.setCombat(false);
    settle(H, 2);
    H.assertEq(H.countItem("headA"), 0, "sold after combat");
    H.assertEq(#H.buybackCalls, 1);
end

local function merchantClosed(H, gq)
    prepare(H, gq);
    H.sellBagItem(H.bagSlotOf("headA"));
    settle(H);
    assertAsked(H, "Helm of the Bastion", "sets Default, Tank", "before closing");
    H.closeMerchant();
    H.advance(0.2);
    H.assertFalse(dialogShown(), "the question goes with the merchant");
    H.assertInBags("headA", 1, "the item is back anyway");
    H.openMerchant();
    settle(H);
    H.assertFalse(dialogShown(), "not asked again");
    H.assertEq(#H.buybackCalls, 1);

    -- sold in combat and the merchant closed before combat ended: bought back at the next merchant
    H.setCombat(true);
    H.sellBagItem(H.bagSlotOf("chestA"));
    settle(H);
    H.closeMerchant();
    H.advance(0.2);
    H.assertEq(chatCount(H, "[Bastion Breastplate] (saved in sets Default, Tank) is still in the merchant's buyback list"), 1,
        "GQ says it buys the item back later");
    H.setCombat(false);
    settle(H);
    H.assertEq(H.countItem("chestA"), 0, "no merchant, no buy-back");
    H.openMerchant();
    settle(H);
    H.assertInBags("chestA", 1, "bought back at the next merchant");
    assertAsked(H, "Bastion Breastplate", "sets Default, Tank", "next merchant");
end

-- buyback links carry the player's spec (and level): a spec swap changes every link in the list, not the items
local function specSwap(H, gq)
    prepare(H, gq);
    H.sellBagItem(H.bagSlotOf("headA"));
    settle(H);
    assertAsked(H, "Helm of the Bastion", "sets Default, Tank", "before the swap");
    answer(true);
    settle(H, 3);
    H.assertEq(H.countItem("headA"), 0, "sold after Yes");
    local link = GetBuybackItemLink(#H.buyback);
    H.setSpecGroup(2);
    settle(H);
    H.assertTrue(GetBuybackItemLink(#H.buyback) ~= link, "the buyback link changed with the spec");

    -- the next sale: the old entries are not new sales
    H.sellBagItem(H.bagSlotOf("mace"));
    settle(H);
    H.assertEq(H.countItem("mace"), 0, "mace sold");
    H.assertEq(H.countItem("headA"), 0, "the confirmed helm stays sold");
    H.assertEq(callsFor(H, "headA"), 1, "the confirmed helm is not bought back again");
    H.assertFalse(dialogShown(), "not asked again");

    -- sold in combat, the merchant closed, then a spec swap: still bought back at the next merchant
    H.setCombat(true);
    H.sellBagItem(H.bagSlotOf("chestA"));
    settle(H);
    H.closeMerchant();
    H.advance(0.2);
    H.assertEq(chatCount(H, "[Bastion Breastplate] (saved in sets Default, Tank) is still in the merchant's buyback list"), 1,
        "GQ says it buys the item back later");
    H.setCombat(false);
    settle(H);
    H.setSpecGroup(1);
    settle(H);
    H.openMerchant();
    settle(H);
    H.assertInBags("chestA", 1, "bought back at the next merchant after a spec swap");
    H.assertEq(callsFor(H, "chestA"), 1);
    assertAsked(H, "Bastion Breastplate", "sets Default, Tank", "after a spec swap");
    answer(false);
    settle(H);
    H.assertEq(callsFor(H, "headA"), 1, "the confirmed helm still not bought back");
end

local function optionOff(H, gq)
    prepare(H, gq);
    local box = optionBox(H, "Protect set items from selling");
    H.assertTrue(box:GetChecked(), "on by default");
    -- the Settings panel's canvas is about 600 px tall: the options still fit
    local _, _, _, _, y = GqResetButton:GetPoint(1);
    H.assertTrue(y - 24 >= -600, "reset button inside the canvas (" .. y .. ")");
    box:Click("LeftButton");
    H.assertEq(GQ_OPTIONS[gq.OPT_PROTECT_SELL], false, "option off");
    H.sellBagItem(H.bagSlotOf("headA"));
    settle(H);
    H.assertEq(H.countItem("headA"), 0, "sold with the guard off");
    H.assertEq(#H.buybackCalls, 0);
    H.assertFalse(dialogShown());

    box:Click("LeftButton");
    H.assertEq(GQ_OPTIONS[gq.OPT_PROTECT_SELL], true, "option on again");
    settle(H);
    H.assertEq(#H.buybackCalls, 0, "a sale from while it was off is not undone later");
    H.sellBagItem(H.bagSlotOf("chestA"));
    settle(H);
    H.assertInBags("chestA", 1, "guarded again");
    assertAsked(H, "Bastion Breastplate", "sets Default, Tank", "option on again");
end

-- full bags: the sale's own slot is the one the item comes back to; a buy-back the server refuses is tried again
local function bagsFull(H, gq)
    prepare(H, gq);
    H.buybackBeforeBags = true; -- the sold item leaves its slot a frame after the buyback list changes
    H.fillBags("junk");
    H.assertEq(H.freeGenericSlots(), 0, "bags full");
    H.sellBagItem(H.bagSlotOf("headA"));
    settle(H, 2);
    H.assertInBags("headA", 1, "bought back into the freed slot");
    H.assertEq(#H.buybackCalls, 1, "no buy-back tried while the bags were full");
    H.assertEq(#H.uiErrors, 0, "no error messages");
    assertAsked(H, "Helm of the Bastion", "sets Default, Tank", "full bags");
    answer(false);

    H.buybackBeforeBags = false;
    H.removeFromBags("junk");
    settle(H);
    H.failNextBuyback = true;
    H.sellBagItem(H.bagSlotOf("chestA"));
    H.assertTrue(H.waitFor(function()
        return #H.uiErrors > 0;
    end, 3), "the server refuses the buy-back");
    H.assertEq(H.countItem("chestA"), 0, "the first buy-back failed");
    H.assertEq(#H.buybackCalls, 2);
    settle(H, 2);
    H.assertInBags("chestA", 1, "retried");
    H.assertEq(#H.buybackCalls, 3, "one retry");
    assertAsked(H, "Bastion Breastplate", "sets Default, Tank", "after the retry");
    answer(false);
    settle(H);
    H.assertFalse(dialogShown(), "asked once");
end

-- the question's frame and buttons go through the skin adapter
local function skinned(H, gq)
    prepare(H, gq);
    H.sellBagItem(H.bagSlotOf("headA"));
    settle(H);
    H.assertTrue(dialogShown());
    H.assertEq(table.concat(H.suiteCallsFor(GqSellGuardDialog.border), ","), "Panel", "panel");
    H.assertEq(table.concat(H.suiteCallsFor(GqSellGuardDialogText), ","), "Font", "text");
    H.assertEq(table.concat(H.suiteCallsFor(GqSellGuardDialogButton1), ","), "Button,StateButtonLabel", "Yes");
    H.assertEq(table.concat(H.suiteCallsFor(GqSellGuardDialogButton2), ","), "Button,StateButtonLabel", "No");
    H.assertEq(#H.suiteCallsFor(GqSellGuardDialog), 0, "the shell itself is not handed to the skin");
end

return {
    variants = {
        {name = "right-click, No keeps, Yes sells once", run = rightClickConfirm},
        {name = "drag and trade-timer popup", run = dragAndTradeTimer},
        {name = "add-on burst", run = burst},
        {name = "add-on burst, buyback list before bags", run = burst, setup = function(H)
            H.buybackBeforeBags = true;
        end},
        {name = "junk-selling ticker capped", run = junkTicker, setup = greySetup},
        {name = "Sell All Junk", run = sellAllJunk, setup = greySetup},
        {name = "spare copy and full buyback list", run = spareAndFullList, setup = ringSetup},
        {name = "bags full and a failed buy-back", run = bagsFull},
        {name = "two identical copies, Yes before the buy-back lands", run = twinsYesEarly, setup = twinsSetup,
            latency = 0.3},
        {name = "combat", run = combat},
        {name = "merchant closed before the answer", run = merchantClosed},
        {name = "spec swap between the sale and the next scan", run = specSwap},
        {name = "option off", run = optionOff},
        {name = "skinned", run = skinned, suites = {EllesmereUI = {}}},
    },
};
