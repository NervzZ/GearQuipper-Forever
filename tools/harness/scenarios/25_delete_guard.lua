-- (y) Delete guard: when Blizzard's delete popup opens for a set item the player cannot spare, its Yes button stays
-- disabled and GQ shows "This item is saved in set ... Destroy it anyway?" under it. Only [Destroy anyway] gives Yes
-- back, by Blizzard's own rule (the DELETE_GOOD_* popups still need DELETE typed, the gamepad ones the button sequence
-- entered in this popup, before or after); [Keep] empties the cursor, which closes the popup (a gamepad popup stays
-- open with Yes locked). Add-ons that type DELETE or enable Yes (EllesmereUIQoL autoFillDelete, Leatrix Plus) cannot
-- unlock it. The plain, typed and gamepad popups are covered, also without an item GUID; a spare copy, an item in no
-- set and the option off are left alone. The refund popup (a refund cannot be bought back) gets the same lock; two
-- guarded popups at once each get their own warning. GQ never writes a field on the popups and never deletes (the
-- mock's delete functions raise an error for anything but the player's own click).

local function settle(H, seconds)
    H.advance((seconds or 0.3) + 3 * H.latency);
end

local function warningFor(dialog)
    for i = 1, 6 do
        local warning = rawget(_G, "GqDeleteGuardWarning" .. i);
        if warning and warning:IsShown() and warning.dialog == dialog then
            return warning;
        end
    end
end

local function shownWarnings()
    local n = 0;
    for i = 1, 6 do
        local warning = rawget(_G, "GqDeleteGuardWarning" .. i);
        if warning and warning:IsShown() then
            n = n + 1;
        end
    end
    return n;
end

local function assertLocked(H, dialog, question, setText, msg)
    H.assertTrue(dialog and dialog:IsShown(), msg .. ": popup shown");
    H.assertFalse(dialog:GetButton1():IsEnabled(), msg .. ": Yes disabled");
    local warning = warningFor(dialog);
    H.assertTrue(warning, msg .. ": GQ's warning under the popup");
    local text = H.stripColors(warning.text:GetText());
    H.assertEq(text, "This item is saved in " .. setText .. ". " .. question, msg .. ": warning text");
    local point, relativeTo, relativePoint = warning:GetPoint(1);
    H.assertEq(relativeTo, dialog, msg .. ": anchored to its popup");
    H.assertEq(point .. ">" .. relativePoint, "TOP>BOTTOM", msg .. ": under the popup");
    H.assertFalse(H.clickPopup(dialog, 1), msg .. ": Yes cannot be clicked");
    return warning;
end

local function bagLoc(H, key)
    for _, loc in ipairs(H.find(key)) do
        if loc.kind == "bag" then
            return loc;
        end
    end
    H.fail("not in the bags: " .. key, 2);
end

local function optionBox(H, text)
    for _, frame in ipairs(H.allFrames) do
        if frame:GetObjectType() == "CheckButton" and rawget(frame, "fontString") and frame.fontString:GetText() == text then
            return frame;
        end
    end
    H.fail("no option checkbox '" .. text .. "'", 2);
end

-- raw keys of Blizzard's popup frames, their buttons and edit boxes: GQ must not add any
local function popupKeys()
    local snapshot = {};
    for i = 2, 4 do
        local dialog = rawget(_G, "StaticPopup" .. i);
        for _, t in ipairs({dialog, dialog.Button1, dialog.Button2, dialog.EditBox}) do
            local keys = {};
            for k in pairs(t) do
                keys[k] = true;
            end
            snapshot[t] = keys;
        end
    end
    return snapshot;
end

local function assertNoFieldsWritten(H, before, allowed)
    for t, keys in pairs(before) do
        for k in pairs(t) do
            if not keys[k] and not allowed[k] then
                H.fail("a field was written on a Blizzard popup: " .. tostring(k), 2);
            end
        end
    end
end

-- Tank = set A as worn at login (Default too); DPS = set B. Set A's displaced pieces end up in the bags.
local function prepare(H, gq)
    H.advance(1);
    gq:SaveSet("Tank", false);
    H.wearSetBPieces();
    gq:SaveSet("DPS", false);
    H.advance(0.2);
end

local SETS = "sets Default, Tank";
local DESTROY = "Destroy it anyway?";

local function plainAndTyped(H, gq)
    local keys = popupKeys();
    prepare(H, gq);

    -- plain popup (a common item): the worn shirt
    local dialog = H.deleteItem(H.find("shirt")[1]);
    H.assertEq(dialog.which, "DELETE_ITEM");
    local warning = assertLocked(H, dialog, DESTROY, "sets DPS, Default, Tank", "plain");
    H.assertEq(warning.button1:GetText(), "Destroy anyway");
    H.assertEq(warning.button2:GetText(), "Keep");
    settle(H, 1);
    H.assertFalse(dialog:GetButton1():IsEnabled(), "plain: still locked a second later");
    warning.button1:Click("LeftButton");
    H.assertTrue(dialog:GetButton1():IsEnabled(), "plain: Destroy anyway gives Yes back");
    H.assertFalse(warningFor(dialog), "plain: warning gone");
    settle(H);
    H.assertTrue(dialog:GetButton1():IsEnabled(), "plain: stays unlocked");
    H.assertTrue(H.clickPopup(dialog, 1), "plain: the player clicks Yes");
    settle(H);
    H.assertEq(H.countItem("shirt"), 0, "plain: deleted by Blizzard's Yes");
    H.assertEq(#H.deleted, 1);
    H.assertFalse(dialog:IsShown(), "plain: popup closed");

    -- typed popup (a rare item): typing DELETE does not unlock it
    dialog = H.deleteItem(bagLoc(H, "headA"));
    H.assertEq(dialog.which, "DELETE_GOOD_ITEM");
    warning = assertLocked(H, dialog, DESTROY, SETS, "typed");
    H.typeInPopup(dialog, "DELETE");
    H.assertFalse(dialog:GetButton1():IsEnabled(), "typed: DELETE typed, still locked");
    H.enterInPopup(dialog);
    settle(H, 1);
    H.assertInBags("headA", 1, "typed: Enter does nothing while locked");
    H.assertTrue(dialog:IsShown());
    -- Destroy anyway follows Blizzard's rule: Yes only with DELETE typed
    H.typeInPopup(dialog, "");
    warning.button1:Click("LeftButton");
    H.assertFalse(dialog:GetButton1():IsEnabled(), "typed: unlocked, but nothing typed");
    H.typeInPopup(dialog, "delete");
    H.assertTrue(dialog:GetButton1():IsEnabled(), "typed: unlocked and typed");
    H.enterInPopup(dialog);
    settle(H);
    H.assertEq(H.countItem("headA"), 0, "typed: deleted");
    H.assertFalse(dialog:IsShown());
    H.assertEq(shownWarnings(), 0);

    -- Keep: the cursor is emptied, Blizzard's popup closes itself
    dialog = H.deleteItem(bagLoc(H, "chestA"));
    warning = assertLocked(H, dialog, DESTROY, SETS, "keep");
    warning.button2:Click("LeftButton");
    H.assertCursorEmpty("keep: cursor emptied");
    settle(H);
    H.assertFalse(dialog:IsShown(), "keep: popup closed");
    H.assertEq(shownWarnings(), 0, "keep: warning gone");
    H.assertInBags("chestA", 1, "keep: kept");
    H.assertEq(#H.deleted, 2);

    -- the No button: the warning goes with the popup
    dialog = H.deleteItem(bagLoc(H, "legsA"));
    assertLocked(H, dialog, DESTROY, SETS, "no");
    H.assertTrue(H.clickPopup(dialog, 2), "the player clicks No");
    H.assertEq(shownWarnings(), 0, "no: warning gone with the popup");
    settle(H);
    H.assertInBags("legsA", 1);
    H.assertCursorEmpty();
    assertNoFieldsWritten(H, keys, {which = true, data = true});
end

local function autofill(H, gq)
    H.simulateAutoFillDelete();
    local keys = popupKeys();
    prepare(H, gq);
    -- EllesmereUIQoL types DELETE as soon as the popup shows
    local dialog = H.deleteItem(bagLoc(H, "headA"));
    H.assertEq(dialog:GetEditBox():GetText(), "DELETE", "auto-filled");
    local warning = assertLocked(H, dialog, DESTROY, SETS, "auto-fill");
    settle(H, 1);
    H.assertFalse(dialog:GetButton1():IsEnabled(), "auto-fill: still locked");
    warning.button1:Click("LeftButton");
    H.assertTrue(dialog:GetButton1():IsEnabled(), "auto-fill: Destroy anyway, DELETE is typed");
    H.assertTrue(H.clickPopup(dialog, 1));
    settle(H);
    H.assertEq(H.countItem("headA"), 0, "auto-fill: deleted");
    assertNoFieldsWritten(H, keys, {which = true, data = true, Show = true});
end

-- Leatrix Plus hides the edit box and enables Yes on DELETE_ITEM_CONFIRM
local function leatrix(H, gq)
    local keys = popupKeys();
    prepare(H, gq);
    H.simulateLeatrixEasyDestroy();
    local dialog = H.deleteItem(bagLoc(H, "chestA"));
    H.assertFalse(dialog:GetEditBox():IsShown(), "leatrix: no edit box");
    H.assertTrue(warningFor(dialog), "leatrix: warning");
    settle(H, 0.1);
    H.assertFalse(dialog:GetButton1():IsEnabled(), "leatrix: locked again on the next frame");
    H.assertFalse(H.clickPopup(dialog, 1));
    warningFor(dialog).button1:Click("LeftButton");
    H.assertTrue(dialog:GetButton1():IsEnabled(), "leatrix: Destroy anyway (no edit box to type in)");
    H.assertTrue(H.clickPopup(dialog, 1));
    settle(H);
    H.assertEq(H.countItem("chestA"), 0, "leatrix: deleted");
    assertNoFieldsWritten(H, keys, {which = true, data = true});
end

local function leftAlone(H, gq)
    prepare(H, gq);
    -- an item in no set
    local dialog = H.deleteItem(bagLoc(H, "linen"));
    H.assertEq(dialog.which, "DELETE_ITEM");
    H.assertTrue(dialog:GetButton1():IsEnabled(), "no set: Yes as usual");
    H.assertEq(shownWarnings(), 0, "no set: no warning");
    H.assertTrue(H.clickPopup(dialog, 1));
    settle(H);
    H.assertEq(H.countItem("linen"), 0);
    dialog = H.deleteItem(bagLoc(H, "mace"));
    H.assertEq(dialog.which, "DELETE_GOOD_ITEM");
    H.typeInPopup(dialog, "DELETE");
    H.assertTrue(dialog:GetButton1():IsEnabled(), "no set: typing works as usual");
    H.assertEq(shownWarnings(), 0);
    H.assertTrue(H.clickPopup(dialog, 1));
    settle(H);

    -- a spare copy: the sets need one Signet of Twins, the player has two
    dialog = H.deleteItem(bagLoc(H, "twinRing"));
    H.typeInPopup(dialog, "DELETE");
    H.assertTrue(dialog:GetButton1():IsEnabled(), "spare copy: not locked");
    H.assertEq(shownWarnings(), 0, "spare copy: no warning");
    H.assertTrue(H.clickPopup(dialog, 1));
    settle(H);
    H.assertEq(H.countItem("twinRing"), 1);
    -- the last copy (worn) is guarded
    dialog = H.deleteItem(H.find("twinRing")[1]);
    assertLocked(H, dialog, DESTROY, "sets DPS, Default, Tank", "last copy");
    H.assertTrue(H.clickPopup(dialog, 2));
    settle(H);

    -- option off
    local box = optionBox(H, "Protect set items from deleting");
    H.assertTrue(box:GetChecked(), "on by default");
    box:Click("LeftButton");
    H.assertEq(GQ_OPTIONS[gq.OPT_PROTECT_DELETE], false);
    dialog = H.deleteItem(bagLoc(H, "headA"));
    H.typeInPopup(dialog, "DELETE");
    H.assertTrue(dialog:GetButton1():IsEnabled(), "option off: not locked");
    H.assertEq(shownWarnings(), 0, "option off: no warning");
    H.assertTrue(H.clickPopup(dialog, 2));
    settle(H);
    box:Click("LeftButton");
    dialog = H.deleteItem(bagLoc(H, "headA"));
    assertLocked(H, dialog, DESTROY, SETS, "option on again");
    H.assertTrue(H.clickPopup(dialog, 2));
    settle(H);
    H.assertInBags("headA", 1);

    -- the same popup frame, now for an item in no set: GQ's edit-box hook stays out of the way
    local reused = H.deleteItem(bagLoc(H, "orb"));
    H.assertEq(reused, dialog, "Blizzard reuses the popup frame");
    H.typeInPopup(reused, "DELETE");
    H.assertTrue(reused:GetButton1():IsEnabled(), "reused popup: not locked");
    H.assertEq(shownWarnings(), 0);
    H.assertTrue(H.clickPopup(reused, 1));
    settle(H);
    H.assertEq(H.countItem("orb"), 0);
end

local function ringSetup(H)
    H.equip("twinRing", 12);
    H.give("twinRing");
end

-- without an item GUID GQ reads the cursor (C_Cursor, then GetCursorInfo); the gamepad popups have no cursor
local function noGuidAndGamepad(H, gq)
    prepare(H, gq);
    local dialog = H.deleteItem(bagLoc(H, "headA"), {noGUID = true});
    H.assertEq(dialog.data.itemGUID, nil);
    assertLocked(H, dialog, DESTROY, SETS, "C_Cursor");
    H.assertTrue(H.clickPopup(dialog, 2));
    settle(H);

    local getCursorItem = C_Cursor.GetCursorItem;
    C_Cursor.GetCursorItem = nil;
    dialog = H.deleteItem(bagLoc(H, "headA"), {noGUID = true});
    assertLocked(H, dialog, DESTROY, SETS, "GetCursorInfo");
    H.assertTrue(H.clickPopup(dialog, 2));
    settle(H);
    C_Cursor.GetCursorItem = getCursorItem;

    -- Blizzard's button sequence works once per popup frame: one entered while Yes was locked counts
    H.gamepadUI = true;
    dialog = H.gamepadDeleteItem(bagLoc(H, "headA"));
    H.assertEq(dialog.which, "DELETE_GOOD_ITEM_GAMEPAD");
    H.assertCursorEmpty("gamepad: no cursor");
    local warning = assertLocked(H, dialog, DESTROY, SETS, "gamepad");
    H.assertTrue(H.gamepadConfirm(dialog), "gamepad: the player enters the button sequence");
    settle(H, 0.1);
    H.assertFalse(dialog:GetButton1():IsEnabled(), "gamepad: the button sequence does not unlock it");
    H.assertFalse(H.gamepadConfirm(dialog), "gamepad: the sequence cannot be entered again");
    warning.button1:Click("LeftButton");
    H.assertTrue(dialog:GetButton1():IsEnabled(), "gamepad: Destroy anyway after the sequence gives Yes back");
    settle(H);
    H.assertTrue(dialog:GetButton1():IsEnabled(), "gamepad: stays unlocked");
    H.assertTrue(H.clickPopup(dialog, 1));
    settle(H);
    H.assertEq(H.countItem("headA"), 0, "gamepad: deleted");

    -- the same popup frame again: its sequence is used up, so Yes stays off as it would without GQ
    local reused = H.gamepadDeleteItem(bagLoc(H, "chestA"));
    H.assertEq(reused, dialog, "Blizzard reuses the popup frame");
    warning = assertLocked(H, reused, DESTROY, SETS, "used-up sequence");
    H.assertFalse(H.gamepadConfirm(reused), "used-up sequence: cannot be entered");
    warning.button1:Click("LeftButton");
    H.assertFalse(reused:GetButton1():IsEnabled(), "used-up sequence: not entered in this popup, Yes stays off");
    H.assertTrue(H.clickPopup(reused, 2));
    settle(H);
    H.assertInBags("chestA", 1);
end

-- gamepad, [Destroy anyway] first: Yes is left to Blizzard's button sequence
local function gamepadDestroyFirst(H, gq)
    prepare(H, gq);
    H.gamepadUI = true;
    local dialog = H.gamepadDeleteItem(bagLoc(H, "headA"));
    local warning = assertLocked(H, dialog, DESTROY, SETS, "gamepad");
    warning.button1:Click("LeftButton");
    H.assertFalse(dialog:GetButton1():IsEnabled(), "Destroy anyway leaves Yes to the button sequence");
    H.assertFalse(warningFor(dialog), "warning gone");
    settle(H);
    H.assertTrue(H.gamepadConfirm(dialog), "the player enters the button sequence");
    H.assertTrue(dialog:GetButton1():IsEnabled(), "the sequence gives Yes back");
    settle(H);
    H.assertTrue(dialog:GetButton1():IsEnabled(), "GQ leaves it unlocked");
    H.assertTrue(H.clickPopup(dialog, 1));
    settle(H);
    H.assertEq(H.countItem("headA"), 0, "deleted");
end

-- gamepad, [Keep]: gamepad deletes do not depend on the cursor, so Blizzard's popup stays open; Yes stays locked,
-- also when the player enters the button sequence afterwards
local function gamepadKeep(H, gq)
    prepare(H, gq);
    H.gamepadUI = true;
    local dialog = H.gamepadDeleteItem(bagLoc(H, "headA"));
    local warning = assertLocked(H, dialog, DESTROY, SETS, "gamepad keep");
    warning.button2:Click("LeftButton");
    settle(H);
    H.assertTrue(dialog:IsShown(), "keep: Blizzard's popup stays open");
    H.assertEq(shownWarnings(), 0, "keep: warning gone");
    H.assertTrue(H.gamepadConfirm(dialog), "keep: the player enters the button sequence");
    settle(H, 0.1);
    H.assertFalse(dialog:GetButton1():IsEnabled(), "keep: Yes stays locked");
    H.assertFalse(H.clickPopup(dialog, 1), "keep: Yes cannot be clicked");
    settle(H, 1);
    H.assertFalse(dialog:GetButton1():IsEnabled(), "keep: still locked a second later");
    H.assertTrue(H.clickPopup(dialog, 2), "the player clicks No");
    settle(H);
    H.assertInBags("headA", 1, "kept");

    -- the lock ends with the popup: the next one on that frame, for an item in no set, is left alone
    H.gamepadUI = false;
    local reused = H.deleteItem(bagLoc(H, "linen"));
    H.assertEq(reused, dialog, "Blizzard reuses the popup frame");
    settle(H, 0.5);
    H.assertTrue(reused:GetButton1():IsEnabled(), "a later popup: Yes as usual");
    H.assertTrue(H.clickPopup(reused, 1));
    settle(H);
    H.assertEq(H.countItem("linen"), 0);
end

-- a refund cannot be bought back: Blizzard's refund popup gets the lock; with a delete popup open as well, each
-- popup has its own warning
local function refund(H, gq)
    local keys = popupKeys();
    prepare(H, gq);
    H.openMerchant();
    H.advance(0.2);
    local bag, slot = H.bagSlotOf("headA");
    H.bags[bag].slots[slot].refundable = true;
    local linenBag, linenSlot = H.bagSlotOf("linen");
    H.bags[linenBag].slots[linenSlot].refundable = true;
    local start = H.money;

    -- an item in no set is not locked
    local dialog = H.sellBagItem(linenBag, linenSlot);
    H.assertEq(dialog.which, "CONFIRM_REFUND_TOKEN_ITEM");
    H.assertTrue(dialog:GetButton1():IsEnabled(), "no set: Yes as usual");
    H.assertEq(shownWarnings(), 0);
    H.assertTrue(H.clickPopup(dialog, 1));
    settle(H);
    H.assertEq(#H.refunded, 1);

    dialog = H.sellBagItem(bag, slot);
    local warning = assertLocked(H, dialog, "Refund it anyway?", SETS, "refund");
    H.assertEq(warning.button1:GetText(), "Refund anyway");
    -- Keep: the warning goes, Yes stays locked, the player says No
    warning.button2:Click("LeftButton");
    settle(H);
    H.assertTrue(dialog:IsShown(), "keep: Blizzard's popup stays");
    H.assertFalse(dialog:GetButton1():IsEnabled(), "keep: Yes stays locked");
    H.assertEq(shownWarnings(), 0, "keep: warning gone");
    H.assertTrue(H.clickPopup(dialog, 2));
    settle(H);
    H.assertInBags("headA", 1, "kept");
    H.assertEq(#H.buybackCalls, 0, "a refund popup is not a sale");

    -- two guarded popups: the refund and a delete
    local refundDialog = H.sellBagItem(bag, slot);
    local deleteDialog = H.deleteItem(bagLoc(H, "chestA"));
    H.assertTrue(refundDialog ~= deleteDialog, "two popups");
    H.assertTrue(refundDialog:IsShown(), "the refund popup stays with the delete popup");
    local refundWarning = assertLocked(H, refundDialog, "Refund it anyway?", SETS, "two popups, refund");
    local deleteWarning = assertLocked(H, deleteDialog, DESTROY, SETS, "two popups, delete");
    H.assertTrue(refundWarning ~= deleteWarning, "a warning each");
    deleteWarning.button1:Click("LeftButton");
    H.typeInPopup(deleteDialog, "DELETE");
    H.assertTrue(deleteDialog:GetButton1():IsEnabled(), "delete unlocked");
    settle(H);
    H.assertFalse(refundDialog:GetButton1():IsEnabled(), "the refund stays locked");
    H.assertTrue(warningFor(refundDialog), "and keeps its warning");
    H.assertTrue(H.clickPopup(deleteDialog, 1));
    settle(H);
    H.assertEq(H.countItem("chestA"), 0, "deleted");
    H.assertTrue(warningFor(refundDialog), "refund warning still there");
    -- Refund anyway
    warningFor(refundDialog).button1:Click("LeftButton");
    H.assertTrue(refundDialog:GetButton1():IsEnabled(), "refund unlocked");
    H.assertTrue(H.clickPopup(refundDialog, 1));
    settle(H);
    H.assertEq(H.countItem("headA"), 0, "refunded");
    H.assertEq(#H.refunded, 2);
    H.assertTrue(H.money > start, "refund paid");

    -- the merchant closes with a guarded refund popup open: popup and warning go
    bag, slot = H.bagSlotOf("legsA");
    H.bags[bag].slots[slot].refundable = true;
    refundDialog = H.sellBagItem(bag, slot);
    assertLocked(H, refundDialog, "Refund it anyway?", SETS, "before closing");
    H.closeMerchant();
    settle(H);
    H.assertFalse(refundDialog:IsShown());
    H.assertEq(shownWarnings(), 0, "warning gone with the merchant");
    assertNoFieldsWritten(H, keys, {which = true, data = true});
end

local function refundOptionOff(H, gq)
    prepare(H, gq);
    GQ_OPTIONS[gq.OPT_PROTECT_SELL] = false; -- the refund lock belongs to the sell protection
    H.openMerchant();
    H.advance(0.2);
    local bag, slot = H.bagSlotOf("headA");
    H.bags[bag].slots[slot].refundable = true;
    local dialog = H.sellBagItem(bag, slot);
    H.assertTrue(dialog:GetButton1():IsEnabled(), "sell protection off: refund not locked");
    H.assertEq(shownWarnings(), 0);
    -- the delete protection is a separate option
    H.assertTrue(H.clickPopup(dialog, 2));
    dialog = H.deleteItem(bagLoc(H, "headA"));
    assertLocked(H, dialog, DESTROY, SETS, "delete still guarded");
    H.assertTrue(H.clickPopup(dialog, 2));
    settle(H);
end

local function skinned(H, gq)
    prepare(H, gq);
    local dialog = H.deleteItem(bagLoc(H, "headA"));
    local warning = assertLocked(H, dialog, DESTROY, SETS, "skinned");
    H.assertEq(table.concat(H.suiteCallsFor(warning.border), ","), "Panel", "panel");
    H.assertEq(table.concat(H.suiteCallsFor(warning.text), ","), "Font", "text");
    H.assertEq(table.concat(H.suiteCallsFor(warning.button1), ","), "Button,StateButtonLabel", "Destroy anyway");
    H.assertEq(table.concat(H.suiteCallsFor(warning.button2), ","), "Button,StateButtonLabel", "Keep");
    H.assertEq(#H.suiteCallsFor(warning), 0, "the shell itself is not handed to the skin");
    H.assertTrue(H.clickPopup(dialog, 2));
    settle(H);
end

return {
    variants = {
        {name = "plain and typed popups, Destroy anyway, Keep", run = plainAndTyped},
        {name = "EllesmereUIQoL auto-fill", run = autofill},
        {name = "Leatrix Plus easy destroy", run = leatrix},
        {name = "no set, spare copy, option off", run = leftAlone, setup = ringSetup},
        {name = "no item GUID and gamepad", run = noGuidAndGamepad},
        {name = "gamepad, Destroy anyway first", run = gamepadDestroyFirst},
        {name = "gamepad, Keep", run = gamepadKeep},
        {name = "refund and two popups", run = refund},
        {name = "refund with the sell protection off", run = refundOptionOff},
        {name = "skinned", run = skinned, suites = {EllesmereUI = {}}},
    },
};
