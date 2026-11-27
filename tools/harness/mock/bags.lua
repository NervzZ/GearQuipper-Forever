-- bags.lua: Blizzard's bag windows, the slot button bag add-ons share (ContainerFrameItemButtonTemplate) and an
-- EllesmereUIBags-style window. Modelled on the forever branch: Blizzard_UIPanels_Game/Mainline/ContainerFrame.xml
-- (the template: frameLevel 10, hidden, its scripts), ContainerFrame.lua (ContainerFrameItemButtonMixin,
-- ContainerFrameItemButton_OnClick, ContainerFrameMixin:UpdateItemSlots / UpdateItems, the frame pool of item buttons),
-- Blizzard_ItemButton/Mainline/ItemButtonTemplate.lua (a slot's icon is set through the button's own
-- SetItemButtonTexture method, which does not call the global), and on EllesmereUIBags 9.9.5 (EUI_Bags_Slots.lua: each
-- slot button sits in a plain parent frame whose id is the bag, at its window's level + 9, with a text overlay frame at
-- + 3; the grid view sets the icon with btn:SetItemButtonTexture, the list view paints its own icon and never calls it).
--
-- Slot buttons (ItemButton + ContainerFrameItemButtonTemplate): GetBagID() = self.bagID (Initialize sets it through the
-- "bagid" attribute) or the parent's id (EllesmereUIBags). Blizzard's scripts: OnClick (any modifier:
-- HandleModifiedItemClick; left: C_Container.PickupContainerItem = pick up / place; right with the merchant open:
-- H.sellBagItem = the refund popup or a sale; right otherwise: UseContainerItem), OnEnter (GameTooltip:SetBagItem),
-- OnLeave, OnDragStart / OnReceiveDrag (= a left click). The scripts and fields a slot button has from Blizzard and its
-- bag window are recorded: H.slotButtonTampering(button) lists every script replaced or hooked and every field
-- written by anyone else (a hooksecurefunc wrapper excepted); H.assertSlotButtonsUntouched() checks them all.
--
-- Windows (each refreshes on show and on bag events; EUI_Bags 0.1 s after them, as EllesmereUIBags' debounce):
--   ContainerFrameCombinedBags  Blizzard's combined bags (bags 0..4); its pool hands the buttons out again on every
--                               show, the last released first, so a button shows another slot after a reopen
--   ContainerFrame1..6          Blizzard's separate bags (ContainerFrameN = bag N-1), a pool each
--   EUI_Bags, EUI_BagsReagent   H.installEuiBags({view = "grid"|"list"}) (EllesmereUIBags loaded; from a scenario's
--                               setup, so it loads before GQ): EUI_Bags shows bags 0..4, items sorted by name, then the
--                               empty slots; a refresh hands the buttons out in that order (an item moves to another
--                               button when the list changes); EUI_BagsReagent shows bag 5. H.euiBags.raise(n) lifts
--                               the window n levels (its slots follow at the next refresh).
--
-- Player actions: a click lands on the TOPMOST visible, mouse-enabled frame over the slot (the slot button and the
-- frames lying over all of it: anchored with both corners to it; Buttons take the mouse unless EnableMouse(false)),
-- highest frame level first, then the deeper frame. A Button only clicks for the buttons it registered. A click on the
-- slot button runs Blizzard's secure code (H.secureCall); a click on an add-on's frame runs that add-on's code.
--   H.openBags([kind]) kind "combined" (default), "separate" or "eui"; H.closeBags()
--   H.bagSlotButton(bag, slot)   the visible slot button showing that slot (error when no open window shows it)
--   H.frameAtBagSlot(bag, slot)  the frame a click there hits
--   H.clickBagSlot(bag, slot[, mouseButton[, mods]])  mouseButton "LeftButton" (default) / "RightButton",
--                                mods {shift =, ctrl =, alt =}; returns the frame clicked
--   H.dragBagSlot(bag, slot)     drag start (left button); H.dropOnBagSlot(bag, slot) releases it over a slot
--   H.dropOnMerchant()           releases the cursor item over the merchant window (sells it)
--   H.hoverBagSlot(bag, slot)    the mouse moves onto the slot (OnLeave on the last hovered frame, OnEnter); returns it
--   H.leaveBagSlot()
-- Logs: H.modifiedClicks {link, action = "CHATLINK" (shift) / "DRESSUP" (ctrl) / nil, itemLocation}.
local H = ...;
local P = H.widgetState;

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

if not rawget(_G, "SpellIsTargeting") then
    function SpellIsTargeting()
        return false;
    end
end

H.modifiedClicks = {};
function HandleModifiedItemClick(link, itemLocation)
    if not link then
        return false;
    end
    local action = (H.modifiers.shift and "CHATLINK") or (H.modifiers.ctrl and "DRESSUP") or nil;
    H.modifiedClicks[#H.modifiedClicks + 1] = {link = link, action = action, itemLocation = itemLocation};
    return action ~= nil;
end

-- MerchantFrame.lua / ContainerFrame_GetExtendedPriceString: a refundable item (inst.refundable) has a refund timer
C_Container.GetContainerItemPurchaseInfo = function(bagId, slot, isEquipped)
    local bag = H.bags[bagId];
    local inst = bag and not isEquipped and bag.slots[slot];
    if inst and inst.refundable then
        return {money = H.sellPrice(inst), itemCount = 0, refundSeconds = 7200, currencyCount = 0, hasEnchants = false};
    end
end

H.extendClass("Frame", {
    RegisterForDrag = function(self, ...)
        P[self].drag = {...};
    end,
});

---------------------------------------------------------------------------
-- what Blizzard and the bag window gave a slot button (tampering check)
---------------------------------------------------------------------------
local slotButtons = {};
local baseline = {};       -- button -> {fields, scripts, hooks}
local ownWrites = {};      -- button -> {key = true}: fields Blizzard's or the bag window's code wrote after the baseline
local secureWrappers = setmetatable({}, {__mode = "k"}); -- functions hooksecurefunc put in place of a method
-- written by ItemButtonMixin (intrinsics.lua) as the slot changes
local ITEMBUTTON_FIELDS = {count = true, matchesSearch = true, item = true, itemLink = true, itemLocation = true,
    isProfessionItem = true, isCraftedItem = true};

local baseHooksecurefunc = hooksecurefunc;
function hooksecurefunc(tableOrName, nameOrHook, hook)
    baseHooksecurefunc(tableOrName, nameOrHook, hook);
    if type(tableOrName) == "table" then
        secureWrappers[rawget(tableOrName, nameOrHook)] = true;
    end
end

local function ownSet(button, key, value)
    ownWrites[button] = ownWrites[button] or {};
    ownWrites[button][key] = true;
    rawset(button, key, value);
end

local function registerSlotButton(button)
    local fields, scripts, hooks = {}, {}, {};
    for k, v in pairs(button) do
        fields[k] = v;
    end
    for name, fn in pairs(P[button].scripts) do
        scripts[name] = fn;
    end
    for name, list in pairs(P[button].hooks) do
        hooks[name] = #list;
    end
    baseline[button] = {fields = fields, scripts = scripts, hooks = hooks};
    slotButtons[#slotButtons + 1] = button;
end

function H.slotButtonTampering(button)
    local base, problems = baseline[button], {};
    local own = ownWrites[button] or {};
    for k, v in pairs(button) do
        local was = base.fields[k];
        if v ~= was and not own[k] and not ITEMBUTTON_FIELDS[k] then
            if was == nil then
                problems[#problems + 1] = "field " .. tostring(k) .. " written";
            elseif not (type(v) == "function" and secureWrappers[v]) then
                problems[#problems + 1] = "field " .. tostring(k) .. " replaced";
            end
        end
    end
    local p = P[button];
    for name, fn in pairs(base.scripts) do
        if p.scripts[name] ~= fn then
            problems[#problems + 1] = "script " .. name .. " replaced";
        end
    end
    for name in pairs(p.scripts) do
        if not base.scripts[name] then
            problems[#problems + 1] = "script " .. name .. " set";
        end
    end
    for name, list in pairs(p.hooks) do
        if #list ~= (base.hooks[name] or 0) then
            problems[#problems + 1] = "script " .. name .. " hooked";
        end
    end
    return problems;
end

function H.allSlotButtons()
    return slotButtons;
end

function H.assertSlotButtonsUntouched(msg)
    H.assertTrue(#slotButtons > 0, (msg and (msg .. ": ") or "") .. "slot buttons exist");
    for _, button in ipairs(slotButtons) do
        local problems = H.slotButtonTampering(button);
        if #problems > 0 then
            error(string.format("%sslot button (bag %s slot %s): %s", msg and (msg .. ": ") or "",
                tostring(button:GetBagID()), tostring(button:GetID()), table.concat(problems, "; ")), 2);
        end
    end
end

---------------------------------------------------------------------------
-- ContainerFrameItemButtonTemplate
---------------------------------------------------------------------------
ContainerFrameItemButtonMixin = {};

function ContainerFrameItemButtonMixin:OnLoad()
    self:RegisterForClicks("LeftButtonUp", "RightButtonUp");
    self:RegisterForDrag("LeftButton");
end

function ContainerFrameItemButtonMixin:SetBagID(id)
    if self.bagID ~= id then
        self:SetAttribute("bagid", id);
    end
end

function ContainerFrameItemButtonMixin:GetBagID()
    return self.bagID or self:GetParent():GetID();
end

function ContainerFrameItemButtonMixin:GetSlotAndBagID()
    return self:GetID(), self:GetBagID();
end

function ContainerFrameItemButtonMixin:OnAttributeChanged(name, value)
    if name == "bagid" then
        ownSet(self, "bagID", value);
    end
end

function ContainerFrameItemButtonMixin:Initialize(containerFrame, bag, slot)
    ownSet(self, "containerFrame", containerFrame);
    self:SetBagID(bag);
    self:SetID(slot);
    self:Show();
end

function ContainerFrameItemButton_OnClick(self, button)
    local bag, slot = self:GetBagID(), self:GetID();
    if button == "LeftButton" then
        C_Container.PickupContainerItem(bag, slot);
    elseif MerchantFrame:IsShown() and C_Container.GetContainerItemLink(bag, slot) then
        H.sellBagItem(bag, slot);
    else
        C_Container.UseContainerItem(bag, slot);
    end
end

function ContainerFrameItemButtonMixin:OnModifiedClick()
    local bag, slot = self:GetBagID(), self:GetID();
    HandleModifiedItemClick(C_Container.GetContainerItemLink(bag, slot), ItemLocation:CreateFromBagAndSlot(bag, slot));
end

-- IsModifiedClick() on the client; the mock binds every modifier to a modified click
function ContainerFrameItemButtonMixin:OnClick(button)
    if IsModifierKeyDown() then
        self:OnModifiedClick(button);
    else
        ContainerFrameItemButton_OnClick(self, button);
    end
end

function ContainerFrameItemButtonMixin:OnEnter()
    GameTooltip:SetOwner(self, "ANCHOR_NONE");
    GameTooltip:SetBagItem(self:GetBagID(), self:GetID());
    GameTooltip:Show();
end

function ContainerFrameItemButtonMixin:OnLeave()
    GameTooltip:Hide();
end

function ContainerFrameItemButtonMixin:OnHide() end

function ContainerFrameItemButtonMixin:OnDragStart()
    self:OnClick("LeftButton");
end

function ContainerFrameItemButtonMixin:OnReceiveDrag()
    self:OnDragStart();
end

H.defineTemplate("ContainerFrameItemButtonTemplate", "ItemButton", 37, 37, function(b)
    b.buttonContext = "ButtonContext_ContainerFrameItemButton";
    H.addTexture(b, {name = "$parentIconQuestTexture", key = "IconQuestTexture", layer = "OVERLAY", subLevel = 2});
    H.addTexture(b, {key = "UpgradeIcon", layer = "OVERLAY", subLevel = 1, atlas = "bags-greenarrow", hidden = true});
    H.addTexture(b, {key = "flash", layer = "OVERLAY", subLevel = 2, atlas = "bags-glow-flash", alpha = 0});
    H.addTexture(b, {key = "NewItemTexture", layer = "OVERLAY", subLevel = 2, atlas = "bags-glow-green", alpha = 0});
    H.addTexture(b, {key = "BattlepayItemTexture", layer = "OVERLAY", subLevel = 2,
        file = "Interface\\Store\\store-item-highlight"});
    H.addTexture(b, {key = "BagIndicator", layer = "OVERLAY", subLevel = 2, hidden = true});
    H.addTexture(b, {key = "ExtendedSlot", layer = "OVERLAY", subLevel = 2, hidden = true});
    H.addTexture(b, {key = "JunkIcon", layer = "OVERLAY", subLevel = 5, atlas = "bags-junkcoin", hidden = true});
    H.addTexture(b, {key = "Highlight", layer = "HIGHLIGHT", hidden = true});
    H.addTexture(b, {key = "EmptyBagIcon", layer = "ARTWORK", setAllPoints = true, hidden = true});
    H.addChild(b, "Cooldown", {name = "$parentCooldown", key = "Cooldown"});
    Mixin(b, ContainerFrameItemButtonMixin);
    P[b].frameLevel = 10;
    P[b].shown = false;
    P[b].points = {{"BOTTOMRIGHT", nil, nil, 0, 0}};
    for _, script in ipairs({"OnClick", "OnLoad", "OnLeave", "OnHide", "OnDragStart", "OnReceiveDrag",
        "OnAttributeChanged"}) do
        b:SetScript(script, b[script]);
    end
    b:SetScript("OnEnter", function(self)
        self:OnEnter();
    end);
end);

local function newSlotButton(parent)
    return CreateFrame("ItemButton", nil, parent, "ContainerFrameItemButtonTemplate");
end

-- ContainerFrameMixin:UpdateItems, for one button
local function refreshSlot(button, info)
    button:SetItemButtonTexture(info and info.iconFileID);
    SetItemButtonCount(button, info and info.stackCount);
    SetItemButtonDesaturated(button, info and info.isLocked);
end

---------------------------------------------------------------------------
-- Blizzard's bag windows
---------------------------------------------------------------------------
local function newPool(parent)
    return {parent = parent, active = {}, inactive = {}};
end

local function acquire(pool)
    local button = table.remove(pool.inactive);
    if not button then
        button = newSlotButton(pool.parent);
        registerSlotButton(button);
    end
    pool.active[#pool.active + 1] = button;
    return button;
end

local function releaseAll(pool)
    for _, button in ipairs(pool.active) do
        button:Hide();
        button:ClearAllPoints();
        pool.inactive[#pool.inactive + 1] = button;
    end
    pool.active = {};
end

local function heldBag(bagId)
    local bag = H.bags[bagId];
    return bag ~= nil and not bag.bank and not bag.keyring;
end

local blizzardWindows = {};

local function newContainerWindow(name, bagIds)
    local window = CreateFrame("Frame", name, UIParent);
    window:Hide();
    local pool = newPool(window);
    local function updateItems()
        for _, button in ipairs(pool.active) do
            refreshSlot(button, C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID()));
        end
    end
    window:SetScript("OnShow", function(self)
        releaseAll(pool);
        for _, bagId in ipairs(bagIds) do
            if heldBag(bagId) then
                local size = C_Container.GetContainerNumSlots(bagId);
                for i = 1, size do
                    acquire(pool):Initialize(self, bagId, size - i + 1);
                end
            end
        end
        updateItems();
    end);
    window:SetScript("OnEvent", function(self, event, bagId, slot)
        if not self:IsShown() then
            return;
        end
        if event == "BAG_UPDATE" then
            updateItems();
        elseif event == "ITEM_LOCK_CHANGED" and slot then
            for _, button in ipairs(pool.active) do
                if button:GetBagID() == bagId and button:GetID() == slot then
                    local info = C_Container.GetContainerItemInfo(bagId, slot);
                    SetItemButtonDesaturated(button, info and info.isLocked);
                end
            end
        end
    end);
    window:RegisterEvent("BAG_UPDATE");
    window:RegisterEvent("ITEM_LOCK_CHANGED");
    blizzardWindows[#blizzardWindows + 1] = window;
    return window;
end

newContainerWindow("ContainerFrameCombinedBags", {0, 1, 2, 3, 4});
for i = 1, 6 do
    newContainerWindow("ContainerFrame" .. i, {i - 1}):SetID(i - 1);
end

---------------------------------------------------------------------------
-- EllesmereUIBags
---------------------------------------------------------------------------
local function euiWindow(name, bagIds, view, sorted, debounced)
    local window = CreateFrame("Frame", name, UIParent);
    window:Hide();
    window:EnableMouse(true);
    local scrollChild = CreateFrame("Frame", nil, window);
    local slots = {};

    local function getOrCreateSlot(i)
        if slots[i] then
            return slots[i];
        end
        -- EllesmereUIBags never creates a secure item button in combat
        if InCombatLockdown() then
            return nil;
        end
        local slotParent = CreateFrame("Frame", nil, scrollChild);
        local button = newSlotButton(slotParent);
        button:SetAllPoints(slotParent);
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp");
        button:RegisterForDrag("LeftButton");
        local textOverlay = CreateFrame("Frame", nil, button);
        textOverlay:SetAllPoints();
        button._textOverlay = textOverlay;
        if view == "list" then
            button._lvIcon = button:CreateTexture(nil, "ARTWORK");
        end
        registerSlotButton(button);
        slots[i] = button;
        return button;
    end

    function window:RefreshInventory()
        if not self:IsVisible() then
            return;
        end
        local items, empties = {}, {};
        for _, bagId in ipairs(bagIds) do
            if heldBag(bagId) then
                for slot = 1, C_Container.GetContainerNumSlots(bagId) do
                    local info = C_Container.GetContainerItemInfo(bagId, slot);
                    local list = info and items or empties;
                    list[#list + 1] = {bag = bagId, slot = slot, info = info};
                end
            end
        end
        if sorted then
            table.sort(items, function(a, b)
                if a.info.itemName ~= b.info.itemName then
                    return a.info.itemName < b.info.itemName;
                elseif a.bag ~= b.bag then
                    return a.bag < b.bag;
                end
                return a.slot < b.slot;
            end);
        end
        for _, entry in ipairs(empties) do
            items[#items + 1] = entry;
        end
        for _, button in ipairs(slots) do
            button:GetParent():Hide();
        end
        for i, data in ipairs(items) do
            local button = getOrCreateSlot(i);
            if button then
                local parent = button:GetParent();
                parent:Show();
                button:Show();
                button:SetID(data.slot);
                parent:SetID(data.bag);
                -- PinItemButtonLevel: the window's level + 9, its text overlay + 3
                button:SetFrameLevel(self:GetFrameLevel() + 9);
                button._textOverlay:SetFrameLevel(button:GetFrameLevel() + 3);
                if view == "list" then
                    button._lvIcon:SetTexture(data.info and data.info.iconFileID);
                    SetItemButtonDesaturated(button, data.info and data.info.isLocked);
                else
                    refreshSlot(button, data.info);
                end
            end
        end
    end

    window:SetScript("OnShow", function(self)
        self:RefreshInventory();
    end);
    -- EUI_Bags_Start.lua ScheduleRefresh: EUI_Bags redraws 0.1 s after a bag event, once per burst; the reagent
    -- window and the replay at the end of combat redraw at once
    local pending = false;
    window:SetScript("OnEvent", function(self, event)
        if not debounced or event == "PLAYER_REGEN_ENABLED" then
            self:RefreshInventory();
        elseif not pending then
            pending = true;
            C_Timer.After(0.1, function()
                pending = false;
                self:RefreshInventory();
            end);
        end
    end);
    window:RegisterEvent("BAG_UPDATE_DELAYED");
    window:RegisterEvent("PLAYER_REGEN_ENABLED");
    return window;
end

function H.installEuiBags(opts)
    opts = opts or {};
    local view = opts.view or "grid";
    local bags = euiWindow("EUI_Bags", {0, 1, 2, 3, 4}, view, true, true);
    local reagent = euiWindow("EUI_BagsReagent", {5}, "grid", false);
    H.euiBags = {window = bags, reagent = reagent, view = view};
    function H.euiBags.raise(levels)
        bags:SetFrameLevel(bags:GetFrameLevel() + levels);
    end
    return H.euiBags;
end

---------------------------------------------------------------------------
-- opening and closing
---------------------------------------------------------------------------
function H.openBags(kind)
    kind = kind or "combined";
    asPlayer(function()
        if kind == "combined" then
            ContainerFrameCombinedBags:Show();
        elseif kind == "separate" then
            for i = 1, 6 do
                if heldBag(i - 1) then
                    _G["ContainerFrame" .. i]:Show();
                end
            end
        elseif kind == "eui" then
            if not H.euiBags then
                error("harness: EllesmereUIBags is not installed (H.installEuiBags from setup)", 3);
            end
            H.euiBags.window:Show();
            if heldBag(5) then
                H.euiBags.reagent:Show();
            end
        else
            error("harness: unknown bag window kind " .. tostring(kind), 3);
        end
    end);
end

function H.closeBags()
    asPlayer(function()
        for _, window in ipairs(blizzardWindows) do
            window:Hide();
        end
        if H.euiBags then
            H.euiBags.window:Hide();
            H.euiBags.reagent:Hide();
        end
    end);
end

---------------------------------------------------------------------------
-- the mouse over a slot
---------------------------------------------------------------------------
local CLICKABLE = {Button = true, ItemButton = true, CheckButton = true, DropdownButton = true, EventButton = true};

local function mouseEnabled(frame)
    local p = P[frame];
    if p.mouse ~= nil then
        return p.mouse and true or false;
    end
    return CLICKABLE[p.type] == true;
end

-- the frame lies over the whole slot: anchored with both corners to it, or to a frame that does
local function covers(frame, slot, guard)
    if frame == slot then
        return true;
    end
    if (guard or 0) > 10 then
        return false;
    end
    local p = P[frame];
    local topLeft, bottomRight;
    for _, pt in ipairs(p.points) do
        local relativeTo = pt[2] or p.parent;
        if pt[1] == "TOPLEFT" and (pt[3] == nil or pt[3] == "TOPLEFT") then
            topLeft = relativeTo;
        elseif pt[1] == "BOTTOMRIGHT" and (pt[3] == nil or pt[3] == "BOTTOMRIGHT") then
            bottomRight = relativeTo;
        end
    end
    return topLeft ~= nil and topLeft == bottomRight and P[topLeft] ~= nil and covers(topLeft, slot, (guard or 0) + 1);
end

local function frameAt(slot)
    local best, bestLevel, bestDepth, order = nil, nil, nil, 0;
    local function visit(frame, depth)
        local p = P[frame];
        order = order + 1;
        if H.isVisible(frame) and mouseEnabled(frame) and covers(frame, slot) then
            if not best or p.frameLevel > bestLevel or (p.frameLevel == bestLevel and depth >= bestDepth) then
                best, bestLevel, bestDepth = frame, p.frameLevel, depth;
            end
        end
        for _, child in ipairs(p.children) do
            visit(child, depth + 1);
        end
    end
    visit(slot, 0);
    return best;
end

function H.bagSlotButton(bag, slot)
    for _, button in ipairs(slotButtons) do
        if H.isVisible(button) and button:GetID() == slot and button:GetBagID() == bag then
            return button;
        end
    end
    error("harness: no open bag window shows bag " .. tostring(bag) .. " slot " .. tostring(slot), 2);
end

function H.frameAtBagSlot(bag, slot)
    return frameAt(H.bagSlotButton(bag, slot));
end

local function clicksFor(frame, mouseButton)
    for _, registered in ipairs(P[frame].clicks or {"LeftButtonUp"}) do
        if registered == "AnyUp" or registered == mouseButton .. "Up" then
            return true;
        end
    end
    return false;
end

local function dragsWith(frame, mouseButton)
    for _, registered in ipairs(P[frame].drag or {}) do
        if registered == mouseButton then
            return true;
        end
    end
    return false;
end

-- runs fn as the player's input on frame: Blizzard's secure code for a slot button, the add-on's code otherwise
local function input(frame, fn, ...)
    if baseline[frame] then
        return asPlayer(fn, ...);
    end
    return fn(...);
end

local function withModifiers(mods, fn)
    local saved = {shift = H.modifiers.shift, ctrl = H.modifiers.ctrl, alt = H.modifiers.alt};
    for key in pairs(saved) do
        H.modifiers[key] = (mods and mods[key]) and true or false;
    end
    local ok, err = pcall(fn);
    for key, value in pairs(saved) do
        H.modifiers[key] = value;
    end
    if not ok then
        error(err, 0);
    end
end

function H.clickBagSlot(bag, slot, mouseButton, mods)
    mouseButton = mouseButton or "LeftButton";
    local target = frameAt(H.bagSlotButton(bag, slot));
    if target then
        withModifiers(mods, function()
            if clicksFor(target, mouseButton) then
                input(target, target.Click, target, mouseButton);
            end
        end);
    end
    return target;
end

function H.dragBagSlot(bag, slot)
    local target = frameAt(H.bagSlotButton(bag, slot));
    if target and dragsWith(target, "LeftButton") then
        input(target, H.fireScript, target, "OnDragStart", "LeftButton");
    end
    return target;
end

function H.dropOnBagSlot(bag, slot)
    local target = frameAt(H.bagSlotButton(bag, slot));
    if target then
        input(target, H.fireScript, target, "OnReceiveDrag");
    end
    return target;
end

function H.dropOnMerchant()
    asPlayer(PickupMerchantItem, 0);
end

local hovered;
function H.leaveBagSlot()
    if hovered then
        local frame = hovered;
        hovered = nil;
        input(frame, H.mouseLeave, frame);
    end
end

function H.hoverBagSlot(bag, slot)
    H.leaveBagSlot();
    local target = frameAt(H.bagSlotButton(bag, slot));
    if target then
        hovered = target;
        input(target, H.mouseEnter, target);
    end
    return target;
end
