-- merchant.lua: the merchant's buyback list and every sell path, money, item GUIDs + ItemLocation + C_Cursor, and
-- Blizzard's delete / refund / trade-timer popups with PopupEventManager. Modelled on the forever branch:
-- Blizzard_UIPanels_Game/Mainline/MerchantFrame.lua/.xml, ContainerFrame.lua (right-click: refund popup or
-- C_Container.UseContainerItem), Blizzard_StaticPopup/StaticPopup.lua (PopupEventManager; OnShow, then "PopupOpened";
-- OnHide, then "PopupClosed"), Blizzard_StaticPopup_Game/GameDialogDefs.lua + Mainline/GameDialogDefs.lua (DELETE_*,
-- CONFIRM_REFUND_TOKEN_ITEM, CONFIRM_MERCHANT_TRADE_TIMER_REMOVAL), Blizzard_Game/Camelot/EventImplementation.lua
-- (DELETE_ITEM_CONFIRM picks the popup).
--
-- Buyback list: H.buyback = {{inst, price}}, newest last, at most H.BUYBACK_MAX (12; the oldest drops out). A sale
-- locks the bag slot; the server (H.latency) then empties the slot, appends the item to the list, adds the money and
-- queues MERCHANT_UPDATE, PLAYER_MONEY and the bag events. H.buybackBeforeBags = true: the list (and MERCHANT_UPDATE)
-- changes one frame before the bag slot empties (the real order is unknown). BuybackItem(index) needs the merchant,
-- money and a free generic bag slot (else ERR_INV_FULL) and moves the entry into the bags when the server answers;
-- H.failNextBuyback = true makes the next answer an ERR_INV_FULL (another add-on filled the slot meanwhile).
-- Combat (assumed): addon calls (not H.secureCall) of BuybackItem, of a sale through C_Container.UseContainerItem and of
-- PickupMerchantItem / SellCursorItem are blocked (H.blocked, ADDON_ACTION_BLOCKED).
--
-- Player actions (secure): H.sellBagItem(bag, slot) right-click (a refundable item, inst.refundable, opens
-- CONFIRM_REFUND_TOKEN_ITEM instead), H.dragToMerchant(bag, slot) (an item with inst.tradeTimer raises
-- MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL; its popup's Yes calls SellCursorItem), H.sellAllJunk(), H.closeMerchant().
-- Other add-ons (not secure) sell with C_Container.UseContainerItem(bag, slot) while a merchant is open.
-- H.bagSlotOf(itemKeyOrInst) -> bag, slot of the first copy in the player's bags.
--
-- Popups: the dialogs of this file live on their own frames StaticPopup2..StaticPopup4 (StaticPopup1 stays the simple
-- frame of blizzui.lua that GQ's own dialogs use); StaticPopup_Show / _Hide / _Visible / _FindVisible route by
-- `which`. Show sets which/data, resets the edit box and buttons, then dialog:Show() runs OnShow (dialogInfo.OnShow,
-- then "PopupOpened"); hooks on dialog:Show run after that. OnUpdate runs dialogInfo.OnUpdate (the delete popups close
-- once the cursor is empty); OnHide runs dialogInfo.OnHide, clears the edit box, then "PopupClosed". An exclusive
-- dialog cancels the other shown exclusive one (OnCancel).
--   H.blizzPopup(which)        the shown dialog for which, or nil
--   H.clickPopup(dialog, n)    the player clicks Button n, only when it is enabled; returns true when clicked
--   H.typeInPopup(dialog, s)   the player types s into the edit box (OnTextChanged runs)
--   H.enterInPopup(dialog)     the player presses Enter in the edit box
-- Deleting: H.deleteItem(loc[, {noGUID = true}]) picks up the item at loc (from H.find) and drops it on the world:
-- DELETE_ITEM_CONFIRM(name, quality, bonding, questWarn, itemGUID) -> the Camelot handler shows the popup; returns it.
-- H.gamepadUI picks the _GAMEPAD popups; H.gamepadDeleteItem(loc) is the gamepad bag action (no cursor),
-- H.gamepadConfirm(dialog) the button sequence that enables Yes. Yes deletes through C_Item.DeleteItem (H.deleted).
-- C_Item.DeleteItem / C_Item.ConfirmDeleteItem (HasRestrictions) raise an error unless the player's own click runs
-- them, and DeleteCursorItem always does (inventory.lua): GQ provably never calls them.
-- Auto-fill add-ons: H.simulateAutoFillDelete() (EllesmereUIQoL autoFillDelete: hooks StaticPopup1-4:Show and types
-- DELETE into DELETE_GOOD_* popups), H.simulateLeatrixEasyDestroy() (on DELETE_ITEM_CONFIRM it hides the edit box and
-- enables Button1).
-- Money: H.money (GetMoney); PLAYER_MONEY on every change. Logs: H.sold, H.buybackCalls {inst, index, by, t},
-- H.deleted, H.refunded.
local H = ...;
local I = H.inventoryInternals;

local function default(name, value)
    if rawget(_G, name) == nil then
        rawset(_G, name, value);
    end
end
default("DELETE_ITEM", "Do you want to destroy %s?");
default("DELETE_QUEST_ITEM", "Do you want to destroy %s?\n\nDestroying this item will also abandon any related quests.");
default("DELETE_GOOD_ITEM", "Do you want to destroy %s?\n\nType \"DELETE\" into the field to confirm.");
default("DELETE_GOOD_QUEST_ITEM",
    "Do you want to destroy %s?\nDestroying this item will also abandon any related quests.\n\nType \"DELETE\" into the field to confirm.");
default("DELETE_GOOD_ITEM_GAMEPAD", "Do you want to destroy %s?");
default("DELETE_GOOD_QUEST_ITEM_GAMEPAD", "Do you want to destroy %s?");
default("DELETE_ITEM_CONFIRM_STRING", "DELETE");
default("CONFIRM_REFUND_TOKEN_ITEM", "Do you want to refund this item for %s?%s");
default("CONFIRM_MERCHANT_TRADE_TIMER_REMOVAL",
    "You can no longer trade %s with others who were eligible to loot it if you sell it.");
default("ERR_INV_FULL", "Inventory is full.");
default("ERR_NOT_ENOUGH_MONEY", "You don't have enough money.");

if not ConfirmationStringMatches then
    function ConfirmationStringMatches(userInput, expectedText)
        return strupper(userInput) == strupper(expectedText);
    end
end
if not ConfirmationEditBoxMatches then
    function ConfirmationEditBoxMatches(editBox, expectedText)
        return ConfirmationStringMatches(editBox:GetText(), expectedText);
    end
end
if not StaticPopup_StandardConfirmationTextHandler then
    function StaticPopup_StandardConfirmationTextHandler(editBox, expectedText)
        editBox:GetParent():GetButton1():SetEnabled(ConfirmationEditBoxMatches(editBox, expectedText));
    end
end

-- Blizzard_SharedXML/Shared/Dialog/DialogTemplates.xml (the border of Blizzard's dialogs)
local T = H.blizzTemplates;
if not T.DialogBorderTemplate then
    H.defineTemplate("DialogBorderNoCenterTemplate", "Frame", 0, 0, function(f)
        f.layoutType = "Dialog";
        T.NineSlicePanelTemplate(f);
    end);
    H.defineTemplate("DialogBorderTemplate", "Frame", 0, 0, function(f)
        T.DialogBorderNoCenterTemplate(f);
        H.addTexture(f, {key = "Bg", layer = "BACKGROUND", subLevel = -5,
            file = "Interface\\DialogFrame\\UI-DialogBox-Background",
            anchors = {{"TOPLEFT", nil, nil, 7, -7}, {"BOTTOMRIGHT", nil, nil, -7, 7}}});
    end);
end

H.buyback, H.buybackCalls, H.deleted, H.refunded = {}, {}, {}, {};
H.BUYBACK_MAX = 12;
H.buybackBeforeBags = false;
H.failNextBuyback = false;
H.gamepadUI = false;

local function asPlayer(fn, ...)
    local was = H.secureCall;
    H.secureCall = true;
    local res = H.pack(pcall(fn, ...));
    H.secureCall = was;
    if not res[1] then
        error(res[2], 0);
    end
    return unpack(res, 2, res.n);
end

local function combatBlocked(fname)
    if H.combat and not H.secureCall then
        H.blocked[#H.blocked + 1] = {fn = fname, t = H.now};
        H.fire("ADDON_ACTION_BLOCKED", H.addonName, fname .. "()");
        return true;
    end
    return false;
end

local function restricted(fname)
    if not H.secureCall then
        error(fname .. " is restricted (HasRestrictions)", 3);
    end
end

---------------------------------------------------------------------------
-- money
---------------------------------------------------------------------------
H.money = GetMoney();
function GetMoney()
    return H.money;
end

function H.addMoney(delta)
    if delta ~= 0 then
        H.money = H.money + delta;
        H.queueEvent("PLAYER_MONEY");
    end
end

local function priceOf(inst)
    return inst.item.sellPrice or 100 * ((inst.item.quality or 1) + 1);
end
H.sellPrice = priceOf;

---------------------------------------------------------------------------
-- server replies (H.latency; extraMs delays further)
---------------------------------------------------------------------------
local ops = {};

local function server(fn, extraMs)
    local dueMs = H.nowMs + math.floor(H.latency * 1000 + 0.5) + (extraMs or 0);
    if dueMs <= H.nowMs then
        fn();
    else
        ops[#ops + 1] = {dueMs = dueMs, fn = fn};
    end
end

table.insert(H.frameHooks, function()
    local i = 1;
    while ops[i] do
        if ops[i].dueMs <= H.nowMs then
            table.remove(ops, i).fn();
        else
            i = i + 1;
        end
    end
end);

---------------------------------------------------------------------------
-- item GUIDs, ItemLocation, C_Cursor
---------------------------------------------------------------------------
local function guidOf(inst)
    inst.guid = inst.guid or string.format("Item-4200-0-%016X", inst.uid);
    return inst.guid;
end
H.itemGUID = guidOf;

-- equipment and every container (bank tabs too)
local function findInst(match)
    for slot = 1, 19 do
        if H.inv[slot] and match(H.inv[slot]) then
            return H.inv[slot], I.equipLoc(slot);
        end
    end
    for _, bagId in ipairs(I.sortedKeys(H.bags)) do
        local bag = H.bags[bagId];
        for slot = 1, bag.size do
            local inst = bag.slots[slot];
            if inst and match(inst) then
                return inst, I.bagLoc(bagId, slot);
            end
        end
    end
end

local function findByGUID(guid)
    if type(guid) ~= "string" then
        return nil;
    end
    return findInst(function(inst)
        return inst.guid == guid;
    end);
end

if not ItemLocationMixin then
    ItemLocationMixin = {};
    function ItemLocationMixin:Clear()
        self.bagID, self.slotIndex, self.equipmentSlotIndex = nil, nil, nil;
    end
    function ItemLocationMixin:SetBagAndSlot(bagID, slotIndex)
        self:Clear();
        self.bagID, self.slotIndex = bagID, slotIndex;
    end
    function ItemLocationMixin:SetEquipmentSlot(slot)
        self:Clear();
        self.equipmentSlotIndex = slot;
    end
    function ItemLocationMixin:IsBagAndSlot()
        return self.bagID ~= nil and self.slotIndex ~= nil;
    end
    function ItemLocationMixin:IsEquipmentSlot()
        return self.equipmentSlotIndex ~= nil;
    end
    function ItemLocationMixin:GetBagAndSlot()
        return self.bagID, self.slotIndex;
    end
    function ItemLocationMixin:GetEquipmentSlot()
        return self.equipmentSlotIndex;
    end
    function ItemLocationMixin:IsValid()
        return self:IsBagAndSlot() or self:IsEquipmentSlot();
    end
    ItemLocation = {};
    function ItemLocation:CreateFromBagAndSlot(bagID, slotIndex)
        local location = CreateFromMixins(ItemLocationMixin);
        location:SetBagAndSlot(bagID, slotIndex);
        return location;
    end
    function ItemLocation:CreateFromEquipmentSlot(slot)
        local location = CreateFromMixins(ItemLocationMixin);
        location:SetEquipmentSlot(slot);
        return location;
    end
    function ItemLocation:CreateEmpty()
        return CreateFromMixins(ItemLocationMixin);
    end
end

local function fromItemLocation(location, api)
    if type(location) ~= "table" or type(location.IsValid) ~= "function" then
        error("Usage: " .. api .. "(itemLocation)", 3);
    end
    if location:IsEquipmentSlot() then
        return I.equipLoc(location:GetEquipmentSlot());
    elseif location:IsBagAndSlot() then
        return I.bagLoc(location:GetBagAndSlot());
    end
end

local function toItemLocation(loc)
    if loc.kind == "equip" then
        return ItemLocation:CreateFromEquipmentSlot(loc.slot);
    end
    return ItemLocation:CreateFromBagAndSlot(loc.bag, loc.slot);
end

local function instAt(location, api)
    local loc = fromItemLocation(location, api);
    return loc and I.getAt(loc), loc;
end

C_Item.DoesItemExist = function(location)
    return instAt(location, "C_Item.DoesItemExist") ~= nil;
end
C_Item.GetItemLink = function(location)
    local inst = instAt(location, "C_Item.GetItemLink");
    return inst and H.itemLink(inst);
end
C_Item.GetItemID = function(location)
    local inst = instAt(location, "C_Item.GetItemID");
    return inst and inst.id;
end
C_Item.GetItemGUID = function(location)
    local inst = instAt(location, "C_Item.GetItemGUID");
    return inst and guidOf(inst);
end
C_Item.IsLocked = function(location)
    local inst, loc = instAt(location, "C_Item.IsLocked");
    return inst ~= nil and I.isLocked(loc);
end
C_Item.GetItemLinkByGUID = function(guid)
    local inst = findByGUID(guid);
    return inst and H.itemLink(inst);
end
C_Item.GetItemLocation = function(guid)
    local _, loc = findByGUID(guid);
    return loc and toItemLocation(loc);
end

C_Cursor = rawget(_G, "C_Cursor") or {};
C_Cursor.GetCursorItem = function()
    local cursor = I.getCursor();
    return cursor and toItemLocation(cursor.from) or nil;
end

---------------------------------------------------------------------------
-- deleting
---------------------------------------------------------------------------
local function destroy(inst, loc)
    if not inst or I.getAt(loc) ~= inst then
        return;
    end
    local cursor = I.getCursor();
    if cursor and cursor.inst == inst then
        I.setCursor(nil);
    end
    I.setAt(loc, nil);
    I.noteChange(loc);
    I.unlock(loc, true);
    I.emitChanges();
    H.deleted[#H.deleted + 1] = inst;
end

C_Item.DeleteItem = function(guid)
    restricted("C_Item.DeleteItem");
    destroy(findByGUID(guid));
end

local function fireDeleteConfirm(inst, guid)
    local def = inst.item;
    H.fire("DELETE_ITEM_CONFIRM", def.name, def.quality, def.bind or 0, def.questItem and 1 or 0, guid);
end

C_Item.ConfirmDeleteItem = function(guid)
    restricted("C_Item.ConfirmDeleteItem");
    local inst = findByGUID(guid);
    if inst then
        fireDeleteConfirm(inst, guid);
    end
end

---------------------------------------------------------------------------
-- popups
---------------------------------------------------------------------------
local OWN = {};  -- which -> true: dialogs that live on this file's frames
local pool = {}; -- StaticPopup2..4

local function dialogInfo(dialog)
    return dialog.which and StaticPopupDialogs[dialog.which];
end

local function triggerPopupEvent(event, dialog)
    -- Blizzard calls the callbacks through securecallfunction: an error is reported, the popup carries on
    H.trap("PopupEventManager " .. event, PopupEventManager.TriggerEvent, PopupEventManager, event, dialog);
end

local function popupClick(dialog, index)
    local info = dialogInfo(dialog);
    if info then
        if index == 1 and info.OnAccept then
            info.OnAccept(dialog, dialog.data);
        elseif index == 2 and info.OnCancel then
            info.OnCancel(dialog, dialog.data);
        end
    end
    dialog:Hide();
end

local function newDialog(i)
    local name = "StaticPopup" .. i;
    local dialog = CreateFrame("Frame", name, UIParent);
    dialog:Hide();
    dialog.Text = dialog:CreateFontString(name .. "Text", "ARTWORK", "GameFontHighlight");
    dialog.Button1 = CreateFrame("Button", name .. "Button1", dialog);
    dialog.Button2 = CreateFrame("Button", name .. "Button2", dialog);
    dialog.EditBox = CreateFrame("EditBox", name .. "EditBox", dialog);
    dialog.editBox = dialog.EditBox;
    function dialog:GetButton1()
        return self.Button1;
    end
    function dialog:GetButton2()
        return self.Button2;
    end
    function dialog:GetEditBox()
        return self.EditBox;
    end
    function dialog:GetTextFontString()
        return self.Text;
    end
    dialog.Button1:SetScript("OnClick", function()
        popupClick(dialog, 1);
    end);
    dialog.Button2:SetScript("OnClick", function()
        popupClick(dialog, 2);
    end);
    dialog.EditBox:SetScript("OnTextChanged", function(editBox)
        local info = dialogInfo(dialog);
        if info and info.EditBoxOnTextChanged then
            info.EditBoxOnTextChanged(editBox, dialog.data);
        end
    end);
    dialog.EditBox:SetScript("OnEnterPressed", function(editBox)
        local info = dialogInfo(dialog);
        if info and info.EditBoxOnEnterPressed then
            info.EditBoxOnEnterPressed(editBox, dialog.data);
        end
    end);
    dialog:SetScript("OnShow", function(self)
        local info = dialogInfo(self);
        if info and info.OnShow then
            info.OnShow(self, self.data);
        end
        triggerPopupEvent("PopupOpened", self);
    end);
    dialog:SetScript("OnHide", function(self)
        local info = dialogInfo(self);
        if info and info.OnHide then
            info.OnHide(self, self.data);
        end
        self.EditBox:SetText("");
        triggerPopupEvent("PopupClosed", self);
    end);
    dialog:SetScript("OnUpdate", function(self, elapsed)
        local info = dialogInfo(self);
        if info and info.OnUpdate then
            info.OnUpdate(self, elapsed, self.data);
        end
    end);
    return dialog;
end

for i = 2, 4 do
    pool[#pool + 1] = newDialog(i);
end

local function cancelAndHide(dialog)
    local info = dialogInfo(dialog);
    if info and info.OnCancel then
        info.OnCancel(dialog, dialog.data, "override");
    end
    dialog:Hide();
end

local function showDialog(which, text1, text2, data)
    local info = StaticPopupDialogs[which];
    if info.exclusive then
        for _, d in ipairs(pool) do
            local other = d:IsShown() and dialogInfo(d);
            if other and other.exclusive then
                cancelAndHide(d);
                break;
            end
        end
    end
    local dialog;
    for _, d in ipairs(pool) do
        if d:IsShown() and d.which == which then
            cancelAndHide(d);
            dialog = d;
            break;
        end
    end
    if not dialog then
        for _, d in ipairs(pool) do
            if not d:IsShown() then
                dialog = d;
                break;
            end
        end
    end
    if not dialog then
        return nil;
    end
    dialog.which, dialog.data = which, data;
    dialog.Text:SetText(string.format(info.text or "", text1 or "", text2 or ""));
    dialog.EditBox:SetShown(info.hasEditBox and true or false);
    dialog.EditBox:SetText("");
    dialog.Button1:Enable();
    dialog.Button2:Enable();
    H.popups[#H.popups + 1] = {which = which, text = dialog.Text:GetText(), data = data};
    dialog:Show();
    return dialog;
end

local legacyShow, legacyHide, legacyVisible = StaticPopup_Show, StaticPopup_Hide, StaticPopup_Visible;

function StaticPopup_Show(which, text1, text2, data, insertedFrame)
    if OWN[which] then
        return showDialog(which, text1, text2, data);
    end
    return legacyShow(which, text1, text2, data, insertedFrame);
end

function StaticPopup_Hide(which, data)
    for _, d in ipairs(pool) do
        if d:IsShown() and d.which == which then
            d:Hide();
        end
    end
    return legacyHide(which, data);
end

function StaticPopup_Visible(which)
    for _, d in ipairs(pool) do
        if d:IsShown() and d.which == which then
            return d:GetName(), d;
        end
    end
    return legacyVisible(which);
end

function StaticPopup_FindVisible(which)
    local _, dialog = StaticPopup_Visible(which);
    return dialog;
end

function H.blizzPopup(which)
    return StaticPopup_FindVisible(which);
end

function H.clickPopup(dialog, index)
    local button = index == 2 and dialog:GetButton2() or dialog:GetButton1();
    if not dialog:IsShown() or not button:IsEnabled() then
        return false;
    end
    asPlayer(button.Click, button, "LeftButton");
    return true;
end

function H.typeInPopup(dialog, text)
    asPlayer(dialog.EditBox.SetText, dialog.EditBox, text);
end

function H.enterInPopup(dialog)
    asPlayer(H.fireScript, dialog.EditBox, "OnEnterPressed");
end

PopupEventManager = CreateFromMixins(CallbackRegistryMixin);
PopupEventManager:OnLoad();
PopupEventManager:GenerateCallbackEvents({"PopupOpened", "PopupClosed"});

---------------------------------------------------------------------------
-- Blizzard's dialogs
---------------------------------------------------------------------------
local function define(which, info)
    OWN[which] = true;
    StaticPopupDialogs[which] = info;
end

local function deleteCursorItemAsPlayer()
    local cursor = I.getCursor();
    if cursor then
        destroy(cursor.inst, cursor.from);
    end
end

local function deleteAccept(dialog, data)
    if data and data.itemGUID then
        C_Item.DeleteItem(data.itemGUID);
    else
        deleteCursorItemAsPlayer();
    end
end

local function deleteOnUpdate(dialog)
    -- gamepad deletes do not depend on the cursor
    if not CursorHasItem() and not H.gamepadUI then
        dialog:Hide();
    end
end

local function plainDelete(text)
    return {text = text, button1 = YES, button2 = NO, OnAccept = deleteAccept, OnCancel = function()
        ClearCursor();
    end, OnUpdate = deleteOnUpdate, timeout = 0, whileDead = 1, exclusive = 1, showAlert = 1, hideOnEscape = 1};
end

local function typedDelete(text)
    local info = plainDelete(text);
    info.hasEditBox, info.maxLetters = 1, 32;
    info.OnShow = function(dialog)
        dialog:GetButton1():Disable();
        dialog:GetButton2():Enable();
        dialog:GetEditBox():SetFocus();
    end;
    info.OnHide = function(dialog)
        dialog:GetEditBox():SetText("");
    end;
    info.EditBoxOnEnterPressed = function(editBox, data)
        if editBox:GetParent():GetButton1():IsEnabled() then
            deleteAccept(nil, data);
            editBox:GetParent():Hide();
        end
    end;
    info.EditBoxOnTextChanged = function(editBox)
        StaticPopup_StandardConfirmationTextHandler(editBox, DELETE_ITEM_CONFIRM_STRING);
    end;
    info.EditBoxOnEscapePressed = function(editBox)
        editBox:GetParent():Hide();
        ClearCursor();
    end;
    return info;
end

local function gamepadDelete(text)
    local info = plainDelete(text);
    info.requiresConfirmation = 1;
    info.OnShow = function(dialog)
        dialog:GetButton1():Disable();
        dialog:GetButton2():Enable();
    end;
    return info;
end

define("DELETE_ITEM", plainDelete(DELETE_ITEM));
define("DELETE_QUEST_ITEM", plainDelete(DELETE_QUEST_ITEM));
define("DELETE_GOOD_ITEM", typedDelete(DELETE_GOOD_ITEM));
define("DELETE_GOOD_QUEST_ITEM", typedDelete(DELETE_GOOD_QUEST_ITEM));
define("DELETE_GOOD_ITEM_GAMEPAD", gamepadDelete(DELETE_GOOD_ITEM_GAMEPAD));
define("DELETE_GOOD_QUEST_ITEM_GAMEPAD", gamepadDelete(DELETE_GOOD_QUEST_ITEM_GAMEPAD));

local refundTarget; -- MerchantFrame.refundBag / refundSlot

define("CONFIRM_REFUND_TOKEN_ITEM", {text = CONFIRM_REFUND_TOKEN_ITEM, button1 = YES, button2 = NO,
    OnAccept = function()
        if refundTarget then
            C_Container.ContainerRefundItemPurchase(refundTarget.bag, refundTarget.slot);
        end
    end,
    OnCancel = function()
        ClearCursor();
    end,
    OnHide = function()
        refundTarget = nil; -- MerchantFrame_ResetRefundItem
    end,
    timeout = 0, hideOnEscape = 1, hasItemFrame = 1});

define("CONFIRM_MERCHANT_TRADE_TIMER_REMOVAL", {text = CONFIRM_MERCHANT_TRADE_TIMER_REMOVAL, button1 = OKAY,
    button2 = CANCEL,
    OnAccept = function()
        SellCursorItem();
    end,
    OnCancel = function()
        ClearCursor();
    end,
    OnUpdate = function(dialog)
        if not CursorHasItem() then
            dialog:Hide();
        end
    end,
    timeout = 0, hideOnEscape = 1});

-- the game's handlers, registered before any add-on frame
local blizzardEvents = CreateFrame("Frame");
blizzardEvents:RegisterEvent("DELETE_ITEM_CONFIRM");
blizzardEvents:RegisterEvent("MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL");
blizzardEvents:SetScript("OnEvent", function(_, event, arg1, arg2, _, arg4, arg5)
    if event == "DELETE_ITEM_CONFIRM" then
        -- Enum.ItemQuality.Rare = 3, Heirloom = 7
        local which;
        if arg2 >= 3 and arg2 ~= 7 then
            which = arg4 == 1 and "DELETE_GOOD_QUEST_ITEM" or "DELETE_GOOD_ITEM";
            if H.gamepadUI then
                which = which .. "_GAMEPAD";
            end
        else
            which = arg4 == 1 and "DELETE_QUEST_ITEM" or "DELETE_ITEM";
        end
        StaticPopup_Show(which, arg1, nil, {itemGUID = arg5});
    elseif event == "MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL" then
        StaticPopup_Show("CONFIRM_MERCHANT_TRADE_TIMER_REMOVAL", arg1);
    end
end);

function H.visibleDeletePopup()
    for _, d in ipairs(pool) do
        if d:IsShown() and d.which and d.which:find("^DELETE_") then
            return d;
        end
    end
end

-- The player drops the item at loc (from H.find) on the world. Returns the delete popup.
function H.deleteItem(loc, opts)
    opts = opts or {};
    asPlayer(function()
        ClearCursor();
        if loc.kind == "equip" then
            PickupInventoryItem(loc.slot);
        else
            C_Container.PickupContainerItem(loc.bag, loc.slot);
        end
    end);
    local cursor = I.getCursor();
    if not cursor then
        error("harness: could not pick up the item at " .. H.describeLoc(loc), 2);
    end
    fireDeleteConfirm(cursor.inst, not opts.noGUID and guidOf(cursor.inst) or nil);
    return H.visibleDeletePopup();
end

-- The gamepad bag action "Destroy" (no cursor involved).
function H.gamepadDeleteItem(loc)
    local inst = I.getAt(loc);
    if not inst then
        error("harness: nothing at " .. H.describeLoc(loc), 2);
    end
    asPlayer(C_Item.ConfirmDeleteItem, guidOf(inst));
    return H.visibleDeletePopup();
end

-- replaced by mock/gamepad.lua (Blizzard's button sequence, one-shot per popup frame)
function H.gamepadConfirm(dialog)
    dialog:GetButton1():Enable();
end

function H.simulateAutoFillDelete()
    for i = 1, 4 do
        local popup = rawget(_G, "StaticPopup" .. i);
        if popup then
            hooksecurefunc(popup, "Show", function(self)
                if self.which ~= "DELETE_GOOD_ITEM" and self.which ~= "DELETE_GOOD_QUEST_ITEM" then
                    return;
                end
                local editBox = self.editBox or (self.GetEditBox and self:GetEditBox());
                if editBox then
                    editBox:SetText(DELETE_ITEM_CONFIRM_STRING);
                    editBox:SetFocus();
                end
            end);
        end
    end
end

function H.simulateLeatrixEasyDestroy()
    local f = CreateFrame("Frame");
    f:RegisterEvent("DELETE_ITEM_CONFIRM");
    f:SetScript("OnEvent", function()
        local dialog = H.visibleDeletePopup();
        if dialog then
            if dialog.EditBox:IsShown() then
                dialog.EditBox:Hide();
            end
            dialog.Button1:Enable();
        end
    end);
    return f;
end

---------------------------------------------------------------------------
-- merchant: buyback list and sell paths
---------------------------------------------------------------------------
local function sell(loc)
    local inst = I.getAt(loc);
    if not inst then
        return false;
    end
    I.lock(loc);
    server(function()
        if I.getAt(loc) ~= inst then
            I.unlock(loc);
            return;
        end
        local function leaveBag()
            if I.getAt(loc) == inst then
                I.setAt(loc, nil);
                I.noteChange(loc);
            end
            I.unlock(loc);
            I.emitChanges();
        end
        H.sold[#H.sold + 1] = inst;
        H.buyback[#H.buyback + 1] = {inst = inst, price = priceOf(inst)};
        while #H.buyback > H.BUYBACK_MAX do
            table.remove(H.buyback, 1);
        end
        H.addMoney(priceOf(inst));
        H.queueEvent("MERCHANT_UPDATE");
        if H.buybackBeforeBags then
            server(leaveBag, H.frameMs);
        else
            leaveBag();
        end
    end);
    return true;
end

local useContainerItem = C_Container.UseContainerItem;
C_Container.UseContainerItem = function(bagId, slot, ...)
    if H.merchant.open and type(bagId) == "number" and type(slot) == "number" and I.accessible(bagId) then
        local loc = I.bagLoc(bagId, slot);
        if I.getAt(loc) then
            if combatBlocked("UseContainerItem") or I.isLocked(loc) then
                return;
            end
            sell(loc);
            return;
        end
    end
    return useContainerItem(bagId, slot, ...);
end

C_Container.ContainerRefundItemPurchase = function(bagId, slot)
    local loc = I.bagLoc(bagId, slot);
    local inst = I.getAt(loc);
    if not inst then
        return;
    end
    I.lock(loc);
    server(function()
        I.unlock(loc);
        if I.getAt(loc) == inst then
            I.setAt(loc, nil);
            I.noteChange(loc);
            H.refunded[#H.refunded + 1] = inst;
            H.addMoney(priceOf(inst));
            I.emitChanges();
        end
    end);
end

function GetNumBuybackItems()
    return #H.buyback;
end

function GetBuybackItemLink(index)
    local entry = H.buyback[index];
    return entry and H.itemLink(entry.inst);
end

function GetBuybackItemInfo(index)
    local entry = H.buyback[index];
    if entry then
        local def = entry.inst.item;
        return def.name, def.icon, entry.price, entry.inst.count or 1, -1, true, true;
    end
end

function BuybackItem(index)
    if type(index) ~= "number" then
        error("Usage: BuybackItem(index)", 2);
    end
    if not H.merchant.open or combatBlocked("BuybackItem") then
        return;
    end
    local entry = H.buyback[index];
    if not entry then
        return;
    end
    H.buybackCalls[#H.buybackCalls + 1] = {inst = entry.inst, index = index, t = H.now,
        by = H.secureCall and "player" or "addon"};
    if H.money < entry.price then
        H.uiError("ERR_NOT_ENOUGH_MONEY");
        return;
    end
    local dest = I.firstFreeBagSlot();
    if not dest then
        H.uiError("ERR_INV_FULL");
        return;
    end
    I.lock(dest);
    server(function()
        I.unlock(dest);
        local position;
        for i, e in ipairs(H.buyback) do
            if e == entry then
                position = i;
                break;
            end
        end
        if not position then
            return;
        end
        if H.failNextBuyback then
            H.failNextBuyback = false;
            H.uiError("ERR_INV_FULL");
            return;
        end
        if I.getAt(dest) then
            dest = I.firstFreeBagSlot();
            if not dest then
                H.uiError("ERR_INV_FULL");
                return;
            end
        end
        table.remove(H.buyback, position);
        I.setAt(dest, entry.inst);
        I.noteChange(dest);
        H.addMoney(-entry.price);
        H.queueEvent("MERCHANT_UPDATE");
        I.emitChanges();
    end);
end

-- Dropping the cursor item on the merchant frame (MerchantFrame OnMouseUp / OnReceiveDrag).
function PickupMerchantItem(index)
    local cursor = I.getCursor();
    if not H.merchant.open or not cursor or cursor.from.kind ~= "bag" then
        return;
    end
    if combatBlocked("PickupMerchantItem") then
        return;
    end
    if cursor.inst.tradeTimer then
        H.fire("MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL", H.itemLink(cursor.inst));
        return;
    end
    I.setCursor(nil); -- the slot stays locked until the server answers
    sell(cursor.from);
end

function SellCursorItem()
    local cursor = I.getCursor();
    if not H.merchant.open or not cursor or cursor.from.kind ~= "bag" or combatBlocked("SellCursorItem") then
        return;
    end
    I.setCursor(nil);
    sell(cursor.from);
end

local function junkLocations()
    local list = {};
    for _, bagId in ipairs(H.GENERIC_BAG_IDS) do
        local bag = H.bags[bagId];
        if bag then
            for slot = 1, bag.size do
                local inst = bag.slots[slot];
                if inst and inst.item.quality == 0 and not I.isLocked(I.bagLoc(bagId, slot)) then
                    list[#list + 1] = I.bagLoc(bagId, slot);
                end
            end
        end
    end
    return list;
end

C_MerchantFrame = rawget(_G, "C_MerchantFrame") or {};
C_MerchantFrame.GetBuybackItemID = function(index)
    local entry = H.buyback[index];
    return entry and entry.inst.id;
end
C_MerchantFrame.IsSellAllJunkEnabled = function()
    return true;
end
C_MerchantFrame.GetNumJunkItems = function()
    return #junkLocations();
end
C_MerchantFrame.SellAllJunkItems = function()
    if not H.merchant.open then
        return;
    end
    for _, loc in ipairs(junkLocations()) do
        sell(loc);
    end
end

local openMerchant, closeMerchant = H.openMerchant, CloseMerchant;
function H.openMerchant()
    openMerchant();
    MerchantFrame:Show();
end

function CloseMerchant()
    local wasOpen = H.merchant.open;
    closeMerchant();
    if wasOpen then
        MerchantFrame:Hide();
        StaticPopup_Hide("CONFIRM_REFUND_TOKEN_ITEM"); -- MerchantFrame_OnHide
    end
end

function H.closeMerchant()
    asPlayer(CloseMerchant);
end

function H.bagSlotOf(itemKeyOrInst)
    for _, loc in ipairs(H.find(itemKeyOrInst)) do
        if loc.kind == "bag" and not H.bags[loc.bag].bank then
            return loc.bag, loc.slot;
        end
    end
    error("harness: not in the bags: " .. tostring(type(itemKeyOrInst) == "table" and itemKeyOrInst.key or itemKeyOrInst),
        2);
end

-- Right-click on a bag item with the merchant open (ContainerFrameItemButton_OnClick).
function H.sellBagItem(bagId, slot)
    if not H.merchant.open then
        error("harness: no merchant is open", 2);
    end
    local inst = I.getAt(I.bagLoc(bagId, slot));
    if not inst then
        error("harness: nothing at bag " .. bagId .. " slot " .. slot, 2);
    end
    if inst.refundable then
        refundTarget = {bag = bagId, slot = slot};
        return StaticPopup_Show("CONFIRM_REFUND_TOKEN_ITEM", priceOf(inst) .. " copper", "",
            {texture = inst.item.icon, name = inst.item.name, color = {1, 1, 1, 1}, link = H.itemLink(inst), count = 1});
    end
    asPlayer(C_Container.UseContainerItem, bagId, slot);
end

-- Drag from the bag onto the merchant frame.
function H.dragToMerchant(bagId, slot)
    asPlayer(function()
        ClearCursor();
        C_Container.PickupContainerItem(bagId, slot);
        PickupMerchantItem(0);
    end);
end

-- Sell All Junk, confirmed in Blizzard's popup.
function H.sellAllJunk()
    asPlayer(C_MerchantFrame.SellAllJunkItems);
end
