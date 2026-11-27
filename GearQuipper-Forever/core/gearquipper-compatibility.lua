-- GearQuipper Forever: client compatibility and secret-value safety layer.
-- WoW Forever (game type "camelot") runs the modern client: C_* namespaces only, tabbed bank,
-- modern item links, and "secret values" that error when addon code compares or tests them.
-- Every other file goes through these helpers instead of touching those APIs directly.
local addonName = ...;
gearquipper = gearquipper or {};
local c = gearquipper;

c.addonName = addonName or "GearQuipper-Forever";

---------------------------------------------------------------------------
-- secret values
---------------------------------------------------------------------------
local issecretvalue = issecretvalue or function()
    return false;
end

function c:IsSecret(value)
    return issecretvalue(value);
end

-- Calls fn(...) and returns its first result, or nil when the API is missing, errors, or returns a secret.
function c:SafeCall(fn, ...)
    if type(fn) ~= "function" then
        return nil;
    end
    local ok, value = pcall(fn, ...);
    if not ok or issecretvalue(value) then
        return nil;
    end
    return value;
end

-- Reads a boolean-ish state. Returns true/false, or nil when unknown (API missing, error, secret).
-- Legacy APIs that return 1/nil are mapped to true/false.
function c:ReadState(fn, ...)
    if type(fn) ~= "function" then
        return nil;
    end
    local ok, value = pcall(fn, ...);
    if not ok or issecretvalue(value) then
        return nil;
    end
    if value then
        return true;
    end
    return false;
end

-- Tri-state edge detector for event bindings.
-- c:UpdateState(key, state): state is true/false/nil (nil = unknown, keeps the last known state).
-- Returns true on a false->true edge, false on a true->false edge, nil when nothing changed or nothing is known.
-- The first known reading only initialises the state and never reports an edge.
local knownStates = {};

function c:InitState(key, state)
    knownStates[key] = state;
end

function c:GetState(key)
    return knownStates[key];
end

function c:UpdateState(key, state)
    if state == nil then
        return nil;
    end
    local old = knownStates[key];
    knownStates[key] = state;
    if old == nil or old == state then
        return nil;
    end
    return state;
end

---------------------------------------------------------------------------
-- flavor
---------------------------------------------------------------------------
function c:IsForever()
    return WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT;
end

---------------------------------------------------------------------------
-- items
---------------------------------------------------------------------------
-- Canonical item string used for storage and every comparison:
--   item:itemID:enchantID:gem1:gem2:gem3:gem4:suffixID:uniqueID[:::::numBonusIDs:bonusID...]
-- Drops linkLevel, specializationID (changes on every spec swap), modifiers and context, so the same
-- physical item keeps the same key across level-ups and spec swaps. "0" fields are written as "".
-- Bonus ids stay at their link positions, so normalising a normalised string returns it unchanged (stored
-- strings are normalised again before every comparison).
local function SplitItemString(itemString)
    local fields = {};
    for field in (itemString .. ":"):gmatch("([^:]*):") do
        fields[#fields + 1] = field;
    end
    return fields;
end

function c:NormalizeItemString(linkOrString)
    if type(linkOrString) ~= "string" or issecretvalue(linkOrString) then
        return nil;
    end
    local itemString = linkOrString:match("item[%-?%d:]+");
    if not itemString then
        return nil;
    end

    local fields = SplitItemString(itemString); -- fields[1] == "item"
    if not tonumber(fields[2]) then
        return nil;
    end

    local parts = {"item"};
    for i = 2, 9 do
        local field = fields[i];
        if not field or field == "0" then
            field = "";
        end
        parts[#parts + 1] = field;
    end

    -- fields[14] = numBonusIDs, followed by that many bonus ids
    local numBonusIds = tonumber(fields[14]);
    if numBonusIds and numBonusIds > 0 then
        local bonusIds = {};
        for i = 15, 14 + numBonusIds do
            if fields[i] and fields[i] ~= "" then
                bonusIds[#bonusIds + 1] = fields[i];
            end
        end
        if #bonusIds > 0 then
            -- fields 10..13 (linkLevel, specID, modifiers mask, context) stay empty
            parts[#parts + 1] = "";
            parts[#parts + 1] = "";
            parts[#parts + 1] = "";
            parts[#parts + 1] = "";
            parts[#parts + 1] = tostring(#bonusIds);
            for _, bonusId in ipairs(bonusIds) do
                parts[#parts + 1] = bonusId;
            end
        end
    end

    return table.concat(parts, ":");
end

function c:GetItemInfo(item)
    if item == nil then
        return nil;
    end
    return C_Item.GetItemInfo(item);
end

function c:GetItemInfoInstant(item)
    if item == nil then
        return nil;
    end
    return C_Item.GetItemInfoInstant(item);
end

function c:GetItemQualityColor(quality)
    return C_Item.GetItemQualityColor(quality);
end

function c:EquipItemByName(item, slotId)
    return C_Item.EquipItemByName(item, slotId);
end

-- Requests item data so a later GetItemInfo call returns it (GET_ITEM_INFO_RECEIVED / ITEM_DATA_LOAD_RESULT fire).
function c:RequestItemData(item)
    local itemId = type(item) == "number" and item or (type(item) == "string" and tonumber(item:match("item:(%-?%d+)")));
    if itemId and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemId);
    end
end

---------------------------------------------------------------------------
-- spells
---------------------------------------------------------------------------
function c:GetSpellName(spellId)
    if not spellId then
        return nil;
    end
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellId);
    end
    return GetSpellInfo and (GetSpellInfo(spellId)) or nil;
end

function c:GetSpellTexture(spellId)
    if not spellId then
        return nil;
    end
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellId);
    end
    return GetSpellTexture and GetSpellTexture(spellId) or nil;
end

---------------------------------------------------------------------------
-- shapeshift forms / stances / paladin auras (stance bar; no aura or combat-log reading)
---------------------------------------------------------------------------
-- Returns the spell id of the active stance-bar entry, or nil (no form, unknown, or secret).
function c:GetActiveShapeshiftSpellId()
    local index = c:SafeCall(GetShapeshiftForm);
    if not index or index == 0 then
        return nil;
    end
    local ok, _, active, _, spellId = pcall(GetShapeshiftFormInfo, index);
    if not ok or issecretvalue(spellId) then
        return nil;
    end
    return spellId;
end

---------------------------------------------------------------------------
-- specs (Forever has two spec groups, like WotLK dual spec)
---------------------------------------------------------------------------
function c:GetActiveSpecGroup()
    if C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup then
        return c:SafeCall(C_SpecializationInfo.GetActiveSpecGroup);
    end
    return c:SafeCall(GetActiveTalentGroup);
end

function c:GetNumSpecGroups()
    return c:SafeCall(GetNumSpecGroups) or c:SafeCall(GetNumTalentGroups) or 1;
end

---------------------------------------------------------------------------
-- containers
---------------------------------------------------------------------------
c.BACKPACK_CONTAINER = (Enum and Enum.BagIndex and Enum.BagIndex.Backpack) or 0;

-- Returns the same values as the legacy global GetContainerItemInfo, or nothing for an empty slot.
function c:GetContainerItemInfo(bagId, slotId)
    local info = C_Container.GetContainerItemInfo(bagId, slotId);
    if not info then
        return nil;
    end
    return info.iconFileID, info.stackCount, info.isLocked, info.quality, info.isReadable, info.hasLoot,
        info.hyperlink, info.isFiltered, info.hasNoValue, info.itemID, info.isBound;
end

function c:GetContainerItemLink(bagId, slotId)
    return C_Container.GetContainerItemLink(bagId, slotId);
end

function c:GetContainerNumSlots(bagId)
    return C_Container.GetContainerNumSlots(bagId) or 0;
end

-- Returns numFree, bagFamily (0 = generic bag that may hold gear).
function c:GetContainerNumFreeSlots(bagId)
    return C_Container.GetContainerNumFreeSlots(bagId);
end

function c:PickupContainerItem(bagId, slotId)
    return C_Container.PickupContainerItem(bagId, slotId);
end

function c:ContainerIDToInventoryID(bagId)
    return C_Container.ContainerIDToInventoryID(bagId);
end

-- True when the bag accepts any item (excludes quivers, ammo pouches, soul bags, reagent bag, keyring).
function c:IsGenericBag(bagId)
    local _, bagFamily = C_Container.GetContainerNumFreeSlots(bagId);
    return bagFamily == 0;
end

-- Player bags that may hold gear: backpack plus the equipped bags. Keyring and reagent bag are excluded.
function c:GetBagIds()
    local ids = {c.BACKPACK_CONTAINER};
    for bagId = 1, NUM_BAG_SLOTS or 4 do
        ids[#ids + 1] = bagId;
    end
    return ids;
end

-- Bank state is tracked from BANKFRAME_OPENED / BANKFRAME_CLOSED (see main).
function c:SetBankOpen(value)
    c.bankOpen = value and true or false;
end

function c:IsAtBank()
    if not c.bankOpen then
        return false;
    end
    if C_Bank and C_Bank.CanUseBank and Enum and Enum.BankType then
        local canUse = c:SafeCall(C_Bank.CanUseBank, Enum.BankType.Character);
        if canUse == false then
            return false;
        end
    end
    return true;
end

-- Character bank tab container ids (purchased tabs), only while the bank is open. Account (warband) tabs are not used.
function c:GetBankBagIds()
    local ids = {};
    if not c:IsAtBank() then
        return ids;
    end
    if C_Bank and C_Bank.FetchPurchasedBankTabIDs and Enum and Enum.BankType then
        local tabIds = c:SafeCall(C_Bank.FetchPurchasedBankTabIDs, Enum.BankType.Character);
        if type(tabIds) == "table" then
            for _, bagId in ipairs(tabIds) do
                ids[#ids + 1] = bagId;
            end
        end
    end
    return ids;
end

-- First free slot in the given containers that may hold gear. Returns bagId, slotId or nil.
function c:FindFreeContainerSlot(bagIds, preferredBagId)
    local function FreeSlotIn(bagId)
        if not c:IsGenericBag(bagId) then
            return nil;
        end
        local freeSlots = C_Container.GetContainerFreeSlots(bagId);
        if freeSlots and freeSlots[1] then
            return freeSlots[1];
        end
        return nil;
    end

    if preferredBagId then
        for _, bagId in ipairs(bagIds) do
            if bagId == preferredBagId then
                local slotId = FreeSlotIn(bagId);
                if slotId then
                    return bagId, slotId;
                end
            end
        end
    end
    for _, bagId in ipairs(bagIds) do
        local slotId = FreeSlotIn(bagId);
        if slotId then
            return bagId, slotId;
        end
    end
    return nil;
end

---------------------------------------------------------------------------
-- merchant (sell guard)
---------------------------------------------------------------------------
-- The buyback list has no C_ API on Forever; Blizzard's MerchantFrame uses these globals. Index 1 is the oldest entry,
-- GetNumBuybackItems() the newest.
function c:GetNumBuybackItems()
    return c:SafeCall(GetNumBuybackItems) or 0;
end

function c:GetBuybackItemLink(index)
    return c:SafeCall(GetBuybackItemLink, index);
end

function c:BuybackItem(index)
    return BuybackItem(index);
end

-- Sells a bag item, only meant while a merchant is open (anywhere else UseContainerItem uses, equips or banks it).
function c:SellContainerItem(bagId, slotId)
    return C_Container.UseContainerItem(bagId, slotId);
end

---------------------------------------------------------------------------
-- cursor and item GUIDs (delete guard)
---------------------------------------------------------------------------
function c:GetItemLinkByGUID(itemGUID)
    if not itemGUID or not C_Item.GetItemLinkByGUID then
        return nil;
    end
    return c:SafeCall(C_Item.GetItemLinkByGUID, itemGUID);
end

-- Link of the item on the cursor, or nil.
function c:GetCursorItemLink()
    local location = C_Cursor and C_Cursor.GetCursorItem and c:SafeCall(C_Cursor.GetCursorItem);
    if location and c:ReadState(C_Item.DoesItemExist, location) then
        local link = c:SafeCall(C_Item.GetItemLink, location);
        if link then
            return link;
        end
    end
    local ok, kind, _, link = pcall(GetCursorInfo);
    if ok and kind == "item" and not issecretvalue(link) then
        return link;
    end
    return nil;
end

---------------------------------------------------------------------------
-- add-ons, settings, tooltips
---------------------------------------------------------------------------
function c:GetAddOnInfo(nameOrIndex)
    return C_AddOns.GetAddOnInfo(nameOrIndex);
end

function c:IsAddOnLoaded(name)
    return C_AddOns.IsAddOnLoaded(name);
end

function c:GetAddOnMetadata(field)
    return C_AddOns.GetAddOnMetadata(c.addonName, field);
end

-- Registers a canvas panel in the game's Settings window. Returns the category.
function c:RegisterSettingsPanel(frame, title)
    local category = Settings.RegisterCanvasLayoutCategory(frame, title);
    Settings.RegisterAddOnCategory(category);
    c.settingsCategory = category;
    return category;
end

function c:OpenSettingsPanel()
    if InCombatLockdown() then
        return false;
    end
    if c.settingsCategory then
        Settings.OpenToCategory(c.settingsCategory:GetID());
        return true;
    end
    return false;
end

-- Calls fn(tooltip, data) after an item tooltip is built (replaces OnTooltipSetItem).
function c:AddItemTooltipPostCall(fn)
    if TooltipDataProcessor and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, fn);
        return true;
    end
    return false;
end

---------------------------------------------------------------------------
-- frames
---------------------------------------------------------------------------
function c:ClearPushedTexture(frame)
    if frame.ClearPushedTexture then
        frame:ClearPushedTexture();
    else
        frame:SetPushedTexture(nil);
    end
end
