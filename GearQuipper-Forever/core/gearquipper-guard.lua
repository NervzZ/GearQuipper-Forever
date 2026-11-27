-- GearQuipper Forever: sell and delete guard for items saved in a set.
--
-- Selling: nothing can cancel a sale beforehand without tainting Blizzard's bag buttons, so the guard undoes it. It
-- compares the merchant's buyback list with the last one it saw; a set item the player cannot spare is bought back at
-- once, then GQ asks. Yes lets that one copy through and sells it again. Looking only at the buyback list catches
-- every sell path (right-click, drag, the trade-timer popup, junk sellers, Sell All Junk) and hooks nothing.
--
-- Deleting and refunding: Blizzard's own popup does the work, so the delete stays untainted. The guard only disables
-- the popup's Yes button (a widget call that writes no Lua value) and shows its own warning under the popup until the
-- player confirms there. It never writes fields on the popup or calls StaticPopup_* on it.
gearquipper = gearquipper or {};
local c = gearquipper;

-- per item and merchant visit: a junk seller sells a bought-back item again and again
local MAX_AUTO_BUYBACKS = 3;
local DIALOG_WIDTH, BUTTON_WIDTH = 360, 150;

---------------------------------------------------------------------------
-- set items
---------------------------------------------------------------------------
-- Copies of itemString one set needs at most (only one set is worn at a time), and the sets holding it (sorted).
-- Ammo is left out: slot 0 stores an item id.
local function CopiesNeeded(itemString)
    local needed, setNames = 0, {};
    if type(itemString) ~= "string" or itemString == c.VALUE_NONE then
        return needed, setNames;
    end
    for _, setName in ipairs(c:LoadSetNames()) do
        local partial, count = c:LoadPartialOption(setName), 0;
        for slotId in pairs(c:GetSlotInfo()) do
            if slotId ~= INVSLOT_AMMO and (not partial or c:LoadSlotState(slotId, setName)) then
                local stored = c:LoadSlot(slotId, setName);
                if type(stored) == "string" and c:NormalizeItemString(stored) == itemString then
                    count = count + 1;
                end
            end
        end
        if count > 0 then
            setNames[#setNames + 1] = setName;
            needed = math.max(needed, count);
        end
    end
    return needed, setNames;
end

-- Copies of itemString the player carries: worn and in the bags, plus the bank tabs while the bank is open.
-- Locked copies are skipped unless countLocked: an item being sold stays in its slot, locked, until the server answers.
local function CopiesOwned(itemString, countLocked, withBank)
    local count = 0;
    for slotId = INVSLOT_FIRST_EQUIPPED or 1, INVSLOT_LAST_EQUIPPED or 19 do
        if c:GetItemString(slotId) == itemString and
            (countLocked or c:ReadState(IsInventoryItemLocked, slotId) ~= true) then
            count = count + 1;
        end
    end
    local bagIds = c:GetBagIds();
    if withBank then
        for _, bagId in ipairs(c:GetBankBagIds()) do
            bagIds[#bagIds + 1] = bagId;
        end
    end
    for _, bagId in ipairs(bagIds) do
        for slotId = 1, c:GetContainerNumSlots(bagId) do
            local link = c:GetContainerItemLink(bagId, slotId);
            if link and c:GetItemString(link) == itemString then
                local _, _, locked = c:GetContainerItemInfo(bagId, slotId);
                if countLocked or not locked then
                    count = count + 1;
                end
            end
        end
    end
    return count;
end

-- "set A" / "sets A, B", names in their set colour when the set has one
local function SetsText(setNames)
    local names = {};
    for i, setName in ipairs(setNames) do
        names[i] = c:ColorizeSetName(setName);
    end
    local list = table.concat(names, ", ");
    if #setNames > 1 then
        return c:GetText("sets %s", list);
    end
    return c:GetText("set %s", list);
end

local function SellGuardEnabled()
    return GQ_OPTIONS[c.OPT_PROTECT_SELL] ~= false;
end

local function DeleteGuardEnabled()
    return GQ_OPTIONS[c.OPT_PROTECT_DELETE] ~= false;
end

---------------------------------------------------------------------------
-- dialogs (GQ-owned frames, never StaticPopups)
---------------------------------------------------------------------------
local function CreateGuardFrame(name)
    local f = CreateFrame("Frame", name, UIParent);
    f:SetSize(DIALOG_WIDTH, 100);
    f:SetFrameStrata("DIALOG");
    f:SetToplevel(true);
    f:EnableMouse(true);
    f:SetClampedToScreen(true);
    f:Hide();

    -- the art lives on a child frame: skins restyle (and later re-strip) the frames handed to them
    f.border = CreateFrame("Frame", nil, f, "DialogBorderTemplate");
    f.border:SetAllPoints();
    c:Skin("panel", f.border);

    f.text = f:CreateFontString(name .. "Text", "ARTWORK", "GameFontHighlight");
    f.text:SetPoint("TOP", 0, -20);
    f.text:SetWidth(DIALOG_WIDTH - 40);
    c:Skin("font", f.text);

    f.button1 = CreateFrame("Button", name .. "Button1", f, "SharedButtonSmallTemplate");
    f.button1:SetSize(BUTTON_WIDTH, 26);
    f.button1:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 16);
    c:Skin("button", f.button1);

    f.button2 = CreateFrame("Button", name .. "Button2", f, "SharedButtonSmallTemplate");
    f.button2:SetSize(BUTTON_WIDTH, 26);
    f.button2:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 16);
    c:Skin("button", f.button2);
    return f;
end

local function SetDialogText(f, text, button1Text, button2Text)
    f.text:SetText(text);
    f.button1:SetText(button1Text);
    f.button2:SetText(button2Text);
    f:SetHeight(f.text:GetStringHeight() + 78);
end

---------------------------------------------------------------------------
-- sell guard
---------------------------------------------------------------------------
-- Buyback list entries whose link was not readable: one seen at MERCHANT_SHOW matches anything later (an old sale);
-- one that appeared since matches nothing, so it is looked at again once its link can be read.
local ANY_ENTRY, UNREAD_ENTRY = {}, {};

local merchantOpen = false;
local knownList = {}; -- the buyback list as last seen (item strings, oldest first)
local tries = {};     -- itemString -> BuybackItem calls this visit
local capHinted = {}; -- itemString -> true once the cap hint was printed this visit
local bypass = {};    -- itemString -> confirmed sales to let through
local rescues = {};   -- oldest sale first: {itemString, link, copies = copies to buy back, inflight = {owned, retryAt}, ask}
local resell = {};    -- itemStrings confirmed, waiting to be sold again
local askQueue = {};  -- {itemString, link}, shown one at a time
local askFrame;

-- Reads the buyback list and returns the entries added since the last read ({index, link}). Sales append (the oldest
-- entry drops out past 12), buy-backs remove entries anywhere: the old list is matched in order against the new one
-- and what is left over was sold since. This also sees a sale whose link equals the entry it pushed out.
-- Entries are compared by item string: the links carry the player's spec and level, so a spec swap changes them all.
local function ScanBuyback(snapshot)
    local list, added, j = {}, {}, 1;
    for i = 1, c:GetNumBuybackItems() do
        local link = c:GetBuybackItemLink(i);
        local itemString = link and c:GetItemString(link);
        local matched;
        for k = j, #knownList do
            local old = knownList[k];
            if old == ANY_ENTRY or old == itemString or (link == nil and old == UNREAD_ENTRY) then
                matched, j = old, k + 1;
                break;
            end
        end
        if link then
            list[i] = itemString;
            if not matched and not snapshot then
                added[#added + 1] = {index = i, link = link};
            end
        elseif matched then
            list[i] = matched;
        else
            list[i] = snapshot and ANY_ENTRY or UNREAD_ENTRY;
        end
    end
    knownList = list;
    return added;
end

local function NewestBuybackIndex(itemString)
    for index = c:GetNumBuybackItems(), 1, -1 do
        if c:GetItemString(c:GetBuybackItemLink(index)) == itemString then
            return index;
        end
    end
end

local function FindRescue(itemString)
    for _, rescue in ipairs(rescues) do
        if rescue.itemString == itemString then
            return rescue;
        end
    end
end

local function HasFreeBagSlot()
    return c:FindFreeContainerSlot(c:GetBagIds()) ~= nil;
end

-- seconds to wait for the server's answer to a buy-back before trying again
local function RetryWindow()
    return c:GetLatency(1000) / 1000;
end

local ShowNextAsk;

local function RemoveAsks(itemString)
    for i = #askQueue, 1, -1 do
        if askQueue[i].itemString == itemString then
            table.remove(askQueue, i);
        end
    end
    if askFrame and askFrame.entry and askFrame.entry.itemString == itemString then
        askFrame.entry = nil;
        askFrame:Hide();
    end
    ShowNextAsk();
end

local function QueueAsk(itemString, link)
    for _, entry in ipairs(askQueue) do
        if entry.itemString == itemString then
            return;
        end
    end
    askQueue[#askQueue + 1] = {itemString = itemString, link = link};
    ShowNextAsk();
end

local function ProcessResell()
    if #resell == 0 or not merchantOpen or c:IsAtBank() or InCombatLockdown() then
        return;
    end
    for i = #resell, 1, -1 do
        local itemString = resell[i];
        -- the copy bought back has to land first
        if not FindRescue(itemString) then
            for _, location in ipairs(c:FindItemInBags(itemString) or {}) do
                local _, _, locked = c:GetContainerItemInfo(location.bagId, location.slotId);
                if not locked then
                    table.remove(resell, i);
                    c:SellContainerItem(location.bagId, location.slotId);
                    break;
                end
            end
        end
    end
end

local CheckSales;

-- Returns true when the rescue is over.
local function ProcessRescue(rescue, now)
    local itemString = rescue.itemString;
    local owned = CopiesOwned(itemString);
    local inflight = rescue.inflight;
    if inflight then
        if owned > inflight.owned then
            rescue.copies = rescue.copies - (owned - inflight.owned);
            rescue.inflight = nil;
        elseif now >= inflight.retryAt then
            rescue.inflight = nil;
        end
    end
    if rescue.copies <= 0 then
        return true;
    end
    if rescue.inflight or not merchantOpen or InCombatLockdown() or not HasFreeBagSlot() then
        return false;
    end
    local index = NewestBuybackIndex(itemString);
    if not index then
        return true; -- bought back by hand or pushed out of the list
    end
    if (tries[itemString] or 0) >= MAX_AUTO_BUYBACKS then
        if not capHinted[itemString] then
            capHinted[itemString] = true;
            c:Println(c:GetText(
                "Something keeps selling %s (saved in %s); GearQuipper stopped buying it back at this merchant.",
                rescue.link, SetsText(select(2, CopiesNeeded(itemString)))));
        end
        RemoveAsks(itemString);
        return true;
    end
    -- every call counts, also a retry: a junk seller may sell the item again before GQ sees it land
    tries[itemString] = (tries[itemString] or 0) + 1;
    rescue.inflight = {owned = owned, retryAt = now + RetryWindow()};
    c:BuybackItem(index);
    -- an answer that never comes is retried
    C_Timer.After(RetryWindow() + 0.05, CheckSales);
    if rescue.ask then
        rescue.ask = nil;
        QueueAsk(itemString, rescue.link);
    end
    return false;
end

local function ProcessRescues()
    local now, i = GetTime(), 1;
    while rescues[i] do
        if ProcessRescue(rescues[i], now) then
            table.remove(rescues, i);
        else
            i = i + 1;
        end
    end
end

-- A new buyback entry: a set item the player cannot spare is marked for a buy-back, unless it is a confirmed sale.
local function NoteSale(link)
    local itemString = c:GetItemString(link);
    if itemString == c.VALUE_NONE then
        return;
    end
    if (bypass[itemString] or 0) > 0 then
        bypass[itemString] = bypass[itemString] - 1;
        return;
    end
    local needed = CopiesNeeded(itemString);
    local rescue = FindRescue(itemString);
    if needed == 0 or CopiesOwned(itemString) + (rescue and rescue.copies or 0) >= needed then
        return;
    end
    if not rescue then
        rescue = {itemString = itemString, copies = 0};
        rescues[#rescues + 1] = rescue;
    end
    rescue.link, rescue.copies, rescue.ask = link, rescue.copies + 1, true;
end

CheckSales = function()
    if not merchantOpen or not c.initFinished then
        return;
    end
    local added = ScanBuyback(false);
    if SellGuardEnabled() then
        for _, entry in ipairs(added) do
            NoteSale(entry.link);
        end
        ProcessRescues();
    end
    ProcessResell();
end

local function AnswerAsk(sell)
    local entry = askFrame.entry;
    askFrame.entry = nil;
    askFrame:Hide();
    if entry then
        for i, queued in ipairs(askQueue) do
            if queued == entry then
                table.remove(askQueue, i);
                break;
            end
        end
        if sell then
            bypass[entry.itemString] = (bypass[entry.itemString] or 0) + 1;
            resell[#resell + 1] = entry.itemString;
            ProcessResell();
        end
    end
    ShowNextAsk();
end

local function GetAskFrame()
    if not askFrame then
        askFrame = CreateGuardFrame("GqSellGuardDialog");
        askFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 120);
        askFrame.button1:SetScript("OnClick", function()
            AnswerAsk(true);
        end);
        askFrame.button2:SetScript("OnClick", function()
            AnswerAsk(false);
        end);
    end
    return askFrame;
end

ShowNextAsk = function()
    local entry = askQueue[1];
    if not entry or not merchantOpen or (askFrame and askFrame.entry) then
        return;
    end
    local f = GetAskFrame();
    f.entry = entry;
    SetDialogText(f, c:GetText("Are you sure you want to sell %s? This item is saved in %s.", entry.link,
        SetsText(select(2, CopiesNeeded(entry.itemString)))), YES or c:GetText("Yes"), NO or c:GetText("No"));
    f:Show();
end

local function MerchantShown()
    merchantOpen = true;
    wipe(tries);
    wipe(capHinted);
    -- an empty list may only not be loaded yet: the list from the last visit is still the better guess then
    if c:GetNumBuybackItems() > 0 then
        ScanBuyback(true);
    end
    if SellGuardEnabled() then
        ProcessRescues(); -- items sold in combat right before the last merchant closed
    end
end

local function MerchantClosed()
    if not merchantOpen then
        return;
    end
    merchantOpen = false;
    wipe(askQueue);
    wipe(resell);
    wipe(bypass);
    if askFrame then
        askFrame.entry = nil;
        askFrame:Hide();
    end
    -- never bought back (sold in combat): kept for the next merchant, the list lasts the session
    for _, rescue in ipairs(rescues) do
        if rescue.ask then
            c:Println(c:GetText(
                "%s (saved in %s) is still in the merchant's buyback list; GearQuipper buys it back at the next merchant.",
                rescue.link, SetsText(select(2, CopiesNeeded(rescue.itemString)))));
        end
    end
end

local guardEvents = CreateFrame("Frame");
-- the order of a sale's events is unknown: every one of them looks at the buyback list again
for _, event in ipairs({"MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_MONEY",
    "PLAYER_REGEN_ENABLED"}) do
    guardEvents:RegisterEvent(event);
end
guardEvents:SetScript("OnEvent", function(_, event)
    if not c.initFinished then
        return;
    end
    if event == "MERCHANT_SHOW" then
        MerchantShown();
    elseif event == "MERCHANT_CLOSED" then
        MerchantClosed();
    else
        CheckSales();
    end
end);

---------------------------------------------------------------------------
-- delete and refund guard
---------------------------------------------------------------------------
-- plain: Yes is enabled; typed: Yes needs DELETE typed; pad: a gamepad button sequence enables Yes
local LOCK_KINDS = {DELETE_ITEM = "plain", DELETE_QUEST_ITEM = "plain", DELETE_GOOD_ITEM = "typed",
    DELETE_GOOD_QUEST_ITEM = "typed", DELETE_GOOD_ITEM_GAMEPAD = "pad", DELETE_GOOD_QUEST_ITEM_GAMEPAD = "pad",
    CONFIRM_REFUND_TOKEN_ITEM = "refund"};

local locks = {};       -- popup -> {kind, locked, warning, kept, sequenceUsedUp}
local hookedBoxes = {}; -- popup edit box -> popup (Blizzard reuses its popup frames, so each box is hooked once)
local freeWarnings, warningCount = {}, 0;

local function EnforceLock(dialog)
    local entry = dialog and locks[dialog];
    if entry and entry.locked then
        local button = dialog:GetButton1();
        if button and button:IsEnabled() then
            button:Disable();
        end
    end
end

-- Blizzard's gamepad button sequence completes once per popup frame: it is never reset and turns itself off when done
local function PadSequenceDone(dialog)
    local sequence = dialog.GamepadSequence;
    return sequence ~= nil and sequence.IsSequenceValid ~= nil and sequence:IsSequenceValid() == true;
end

-- after [Keep] on a popup that stays open (gamepad UI, refund), the button sequence or an add-on may enable Yes again
local keptWatch = CreateFrame("Frame");
keptWatch:Hide();
keptWatch:SetScript("OnUpdate", function(self)
    local watching = false;
    for dialog, entry in pairs(locks) do
        if entry.kept and dialog:IsShown() then
            EnforceLock(dialog);
            watching = true;
        end
    end
    if not watching then
        self:Hide();
    end
end);

local function ReleaseWarning(entry)
    local warning = entry.warning;
    if warning then
        entry.warning = nil;
        warning.dialog = nil;
        warning:Hide();
        warning:ClearAllPoints();
        freeWarnings[#freeWarnings + 1] = warning;
    end
end

-- [Destroy anyway] / [Refund anyway]: Yes follows Blizzard's own rule again
local function Unlock(dialog)
    local entry = locks[dialog];
    if not entry then
        return;
    end
    entry.locked = false;
    ReleaseWarning(entry);
    local button = dialog:GetButton1();
    if entry.kind == "typed" then
        -- a hidden edit box: an add-on (Leatrix Plus) replaced typing DELETE with its own Yes
        local editBox = dialog:GetEditBox();
        button:SetEnabled(not editBox or not editBox:IsShown() or
            ConfirmationEditBoxMatches(editBox, DELETE_ITEM_CONFIRM_STRING));
    elseif entry.kind == "pad" then
        -- a sequence entered while Yes was locked cannot be entered again; one used up before this popup does not count
        button:SetEnabled(PadSequenceDone(dialog) and not entry.sequenceUsedUp);
    else
        button:Enable();
    end
end

-- [Keep]: an empty cursor makes Blizzard's delete popup close itself; Yes stays locked while any popup stays open
local function Keep(dialog)
    local entry = locks[dialog];
    if entry then
        entry.kept = true;
        ReleaseWarning(entry);
        keptWatch:Show();
    end
    ClearCursor();
end

local function AcquireWarning()
    local warning = table.remove(freeWarnings);
    if not warning then
        warningCount = warningCount + 1;
        warning = CreateGuardFrame("GqDeleteGuardWarning" .. warningCount);
        warning.button1:SetScript("OnClick", function(self)
            local dialog = self:GetParent().dialog;
            if dialog then
                Unlock(dialog);
            end
        end);
        warning.button2:SetScript("OnClick", function(self)
            local dialog = self:GetParent().dialog;
            if dialog then
                Keep(dialog);
            end
        end);
        -- autofill add-ons (EllesmereUIQoL, Leatrix Plus) enable Yes behind GQ's back
        warning:SetScript("OnUpdate", function(self)
            local dialog = self.dialog;
            local entry = dialog and locks[dialog];
            if not entry or entry.warning ~= self then
                self.dialog = nil;
                self:Hide();
                freeWarnings[#freeWarnings + 1] = self;
            elseif not dialog:IsShown() then
                locks[dialog] = nil;
                ReleaseWarning(entry);
            else
                EnforceLock(dialog);
            end
        end);
    end
    return warning;
end

local function GuardedItemLink(kind, data)
    if type(data) ~= "table" then
        data = nil;
    end
    if kind == "refund" then
        return data and data.link;
    end
    return (data and c:GetItemLinkByGUID(data.itemGUID)) or c:GetCursorItemLink();
end

local function PopupOpened(_, dialog)
    if not dialog then
        return;
    end
    -- Blizzard reuses its popup frames: whatever this one showed before is over
    local entry = locks[dialog];
    if entry then
        locks[dialog] = nil;
        ReleaseWarning(entry);
    end
    local kind = LOCK_KINDS[dialog.which];
    if not kind or not c.initFinished then
        return;
    end
    if (kind == "refund" and not SellGuardEnabled()) or (kind ~= "refund" and not DeleteGuardEnabled()) then
        return;
    end
    local link = GuardedItemLink(kind, dialog.data);
    local itemString = link and c:GetItemString(link);
    local needed, setNames = CopiesNeeded(itemString);
    -- the copy in question still counts as owned here
    if needed == 0 or CopiesOwned(itemString, true, true) - 1 >= needed then
        return;
    end

    entry = {kind = kind, locked = true, sequenceUsedUp = kind == "pad" and PadSequenceDone(dialog)};
    locks[dialog] = entry;

    local editBox = dialog.GetEditBox and dialog:GetEditBox();
    if editBox and not hookedBoxes[editBox] then
        hookedBoxes[editBox] = dialog;
        editBox:HookScript("OnTextChanged", function(box)
            EnforceLock(hookedBoxes[box]);
        end);
    end
    EnforceLock(dialog);

    local warning = AcquireWarning();
    warning.dialog = dialog;
    entry.warning = warning;
    if kind == "refund" then
        SetDialogText(warning, c:GetText("This item is saved in %s. Refund it anyway?", SetsText(setNames)),
            c:GetText("Refund anyway"), c:GetText("Keep"));
    else
        SetDialogText(warning, c:GetText("This item is saved in %s. Destroy it anyway?", SetsText(setNames)),
            c:GetText("Destroy anyway"), c:GetText("Keep"));
    end
    warning:SetPoint("TOP", dialog, "BOTTOM", 0, -4);
    warning:Show();
end

local function PopupClosed(_, dialog)
    local entry = dialog and locks[dialog];
    if entry then
        locks[dialog] = nil;
        ReleaseWarning(entry);
    end
end

-- Popup callbacks run through securecallfunction, so GQ's code cannot taint the popup's own path.
if PopupEventManager and PopupEventManager.RegisterCallback then
    local owner = {};
    PopupEventManager:RegisterCallback("PopupOpened", PopupOpened, owner);
    PopupEventManager:RegisterCallback("PopupClosed", PopupClosed, owner);
end
