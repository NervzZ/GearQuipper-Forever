-- GearQuipper Forever: stops the sale of a set item before it happens (the sell guard's first line).
--
-- While a merchant is open, every bag slot holding a set item the player cannot spare gets a plain GQ button on top.
-- The slot buttons are secure: GQ never changes their scripts or writes on them, its button takes the clicks instead
-- (as BagItemLock does). A right-click asks the sell guard's question and sells nothing until Yes; a left-click or a
-- drag picks the item up or drops the cursor item there, as the slot would; a modified click links the item. A sale
-- GQ does not see coming (a drop onto the merchant, another add-on, a slot first seen in combat) is still bought back
-- by the sell guard.
--
-- Blizzard's bags and bag add-ons (EllesmereUIBags and others) build their slots from ContainerFrameItemButtonTemplate:
-- the slot is the button's id, the bag GetBagID() or the parent's id. The known bag windows are walked for such
-- buttons. A slot is looked at again as soon as it gets its icon: Blizzard and EllesmereUIBags set it through the
-- button's own SetItemButtonTexture method, which does not call the global, so both are hooked. EllesmereUIBags redraws
-- 0.1 s or more after the bag events, and its list paints its own icons: its windows' RefreshInventory is hooked too.
-- The bag events and a light rescan while the merchant is open catch the rest.
gearquipper = gearquipper or {};
local c = gearquipper;

local OVERLAY_LEVELS = 5; -- above the slot and a bag add-on's text overlay on it
local SCAN_INTERVAL = 0.5;
local MAX_DEPTH = 8;
local HIGHLIGHT_TEXTURE = "Interface\\Buttons\\ButtonHilight-Square";

-- bag windows by global name, looked up when needed (bag add-ons create theirs late)
local WINDOWS = {"ContainerFrameCombinedBags", "EUI_Bags", "EUI_BagsReagent"};
for i = 1, 13 do
    WINDOWS[#WINDOWS + 1] = "ContainerFrame" .. i;
end

local seen = setmetatable({}, {__mode = "k"});     -- slot button -> true once its icon method is hooked
local overlays = setmetatable({}, {__mode = "k"}); -- slot button -> GQ's button on top of it
local shownHooked = setmetatable({}, {__mode = "k"}); -- bag window -> true once its OnShow and redraw are hooked
local ticker, scheduled;
local protectedCache, protectedCacheTime;

local function IsSlotButton(frame)
    return type(frame) == "table" and frame.IconBorder ~= nil and (frame.NewItemTexture ~= nil or frame.JunkIcon ~= nil)
        and type(frame.GetID) == "function" and type(frame.GetParent) == "function";
end

local function IsPlayerBag(bagId)
    for _, id in ipairs(c:GetBagIds()) do
        if id == bagId then
            return true;
        end
    end
    return false;
end

-- bagId, slotId the slot button shows, or nil
local function SlotOf(button)
    local bagId;
    if type(button.GetBagID) == "function" then
        bagId = c:SafeCall(button.GetBagID, button);
    end
    if bagId == nil then
        local parent = button:GetParent();
        bagId = parent and type(parent.GetID) == "function" and c:SafeCall(parent.GetID, parent);
    end
    local slotId = c:SafeCall(button.GetID, button);
    if type(bagId) ~= "number" or type(slotId) ~= "number" or slotId < 1 or not IsPlayerBag(bagId) then
        return nil;
    end
    return bagId, slotId;
end

-- the set items the guard protects, read once per frame (a bag window refresh sets many icons in one frame)
local function ProtectedItems(fresh)
    local now = GetTime();
    if fresh or not protectedCache or protectedCacheTime ~= now then
        protectedCache, protectedCacheTime = c:GetSellProtectedItems(), now;
    end
    return protectedCache;
end

-- bagId, slotId when a right-click on the slot must ask before selling
local function GuardedSlot(button, protectedItems)
    local bagId, slotId = SlotOf(button);
    local link = bagId and c:GetContainerItemLink(bagId, slotId);
    if not link or not protectedItems[c:GetItemString(link)] then
        return nil;
    end
    local noValue = select(9, c:GetContainerItemInfo(bagId, slotId));
    -- nothing to sell; or Blizzard's refund popup comes first (the delete and refund guard watches that one)
    if noValue or c:IsRefundableContainerItem(bagId, slotId) then
        return nil;
    end
    return bagId, slotId;
end

local UpdateButton;

-- left-click, drag start and drop: what the slot's own left-click does with an item or an empty cursor
local function PickUp(bagId, slotId)
    if c:ReadState(SpellIsTargeting) then
        return;
    end
    -- money or a merchant's item on the cursor: the slot would buy or drop it with Blizzard's confirmations
    local cursorType = c:SafeCall(GetCursorInfo);
    if cursorType == nil or cursorType == "item" then
        c:PickupContainerItem(bagId, slotId);
    end
end

local function OnOverlayClick(overlay, mouseButton)
    local button = overlay:GetParent();
    local bagId, slotId = SlotOf(button);
    if not bagId then
        return;
    end
    if IsModifierKeyDown() then
        local link = c:GetContainerItemLink(bagId, slotId);
        if link and HandleModifiedItemClick then
            HandleModifiedItemClick(link, ItemLocation and ItemLocation:CreateFromBagAndSlot(bagId, slotId));
        end
    elseif mouseButton == "LeftButton" then
        PickUp(bagId, slotId);
    elseif mouseButton == "RightButton" then
        -- a button reused for another slot since the last look: nothing happens, the next click reaches the slot
        if c:IsSellGuardActive() and GuardedSlot(button, ProtectedItems(true)) then
            c:AskBeforeSale(bagId, slotId);
        else
            UpdateButton(button, ProtectedItems(true));
        end
    end
end

local function OnOverlayDrag(overlay)
    local bagId, slotId = SlotOf(overlay:GetParent());
    if bagId then
        PickUp(bagId, slotId);
    end
end

local function OnOverlayEnter(overlay)
    local bagId, slotId = SlotOf(overlay:GetParent());
    if bagId then
        GameTooltip:SetOwner(overlay, "ANCHOR_RIGHT");
        GameTooltip:SetBagItem(bagId, slotId);
        GameTooltip:Show();
    end
end

local function OnOverlayLeave(overlay)
    if GameTooltip:IsOwned(overlay) then
        GameTooltip:Hide();
    end
end

local function CreateOverlay(button)
    local overlay = CreateFrame("Button", nil, button);
    overlay:SetAllPoints(button);
    overlay:RegisterForClicks("AnyUp");
    overlay:RegisterForDrag("LeftButton");
    local highlight = overlay:CreateTexture(nil, "HIGHLIGHT");
    highlight:SetAllPoints();
    highlight:SetTexture(HIGHLIGHT_TEXTURE);
    highlight:SetBlendMode("ADD");
    overlay:SetScript("OnClick", OnOverlayClick);
    overlay:SetScript("OnDragStart", OnOverlayDrag);
    overlay:SetScript("OnReceiveDrag", OnOverlayDrag);
    overlay:SetScript("OnEnter", OnOverlayEnter);
    overlay:SetScript("OnLeave", OnOverlayLeave);
    overlay:Hide();
    overlays[button] = overlay;
    return overlay;
end

local function OnSlotTexture(button)
    if not c:IsSellGuardActive() then
        return;
    end
    if seen[button] then
        UpdateButton(button, ProtectedItems());
    elseif IsSlotButton(button) then
        -- a slot outside the known bag windows (a guild bank's) is left to the walk
        c:ScheduleSellBlockRefresh();
    end
end

UpdateButton = function(button, protectedItems)
    if not seen[button] then
        -- nothing is added to a secure slot in combat: the next pass after combat does it
        if InCombatLockdown() then
            return;
        end
        seen[button] = true;
        if type(button.SetItemButtonTexture) == "function" and button.SetItemButtonTexture ~= SetItemButtonTexture then
            hooksecurefunc(button, "SetItemButtonTexture", OnSlotTexture);
        end
    end
    local overlay = overlays[button];
    local guarded = c:IsSellGuardActive() and GuardedSlot(button, protectedItems) ~= nil;
    if guarded and not overlay and not InCombatLockdown() then
        overlay = CreateOverlay(button);
    end
    if overlay then
        if guarded then
            -- bag add-ons move their slots to other levels as their windows rise
            overlay:SetFrameLevel(button:GetFrameLevel() + OVERLAY_LEVELS);
        end
        overlay:SetShown(guarded);
    end
end

local function Walk(frame, depth, protectedItems)
    if frame.IsForbidden and frame:IsForbidden() then
        return;
    end
    if IsSlotButton(frame) then
        UpdateButton(frame, protectedItems);
        return;
    end
    if depth >= MAX_DEPTH or type(frame.GetChildren) ~= "function" then
        return;
    end
    for _, child in ipairs({frame:GetChildren()}) do
        Walk(child, depth + 1, protectedItems);
    end
end

local function HideAll()
    for _, overlay in pairs(overlays) do
        overlay:Hide();
    end
end

local Refresh;

local function OnWindowShown()
    if c:IsSellGuardActive() then
        Refresh();
        c:ScheduleSellBlockRefresh(); -- what the window lays out later this frame
    end
end

-- EllesmereUIBags hands its slot buttons to other slots only here, 0.1 s or more after the bag events GQ looks at
local function OnWindowRedrawn()
    if c:IsSellGuardActive() then
        Refresh();
    end
end

Refresh = function()
    if not c:IsSellGuardActive() then
        HideAll();
        return;
    end
    local protectedItems;
    for _, name in ipairs(WINDOWS) do
        local window = rawget(_G, name);
        if type(window) == "table" and type(window.IsVisible) == "function" then
            if not shownHooked[window] then
                shownHooked[window] = true;
                window:HookScript("OnShow", OnWindowShown);
                if type(window.RefreshInventory) == "function" then
                    hooksecurefunc(window, "RefreshInventory", OnWindowRedrawn);
                end
            end
            if window:IsVisible() then
                protectedItems = protectedItems or ProtectedItems(true);
                Walk(window, 0, protectedItems);
            end
        end
    end
end

function c:RefreshSellBlock()
    Refresh();
end

function c:ScheduleSellBlockRefresh()
    if scheduled then
        return;
    end
    scheduled = true;
    C_Timer.After(0, function()
        scheduled = false;
        Refresh();
    end);
end

if SetItemButtonTexture then
    hooksecurefunc("SetItemButtonTexture", OnSlotTexture);
end

local events = CreateFrame("Frame");
for _, event in ipairs({"MERCHANT_SHOW", "MERCHANT_CLOSED", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED",
    "PLAYER_REGEN_ENABLED"}) do
    events:RegisterEvent(event);
end
events:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then
        if not ticker then
            -- bag add-ons redraw their slots on their own
            ticker = C_Timer.NewTicker(SCAN_INTERVAL, Refresh);
        end
        Refresh();
    elseif event == "MERCHANT_CLOSED" then
        if ticker then
            ticker:Cancel();
            ticker = nil;
        end
        HideAll();
    elseif c:IsSellGuardActive() then
        c:ScheduleSellBlockRefresh();
    end
end);
