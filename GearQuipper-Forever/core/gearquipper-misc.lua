-- scope stuff
gearquipper = gearquipper or {};
local c = gearquipper;

-- Stored values are compared in normalised form (see c:GetItemString); numbers (ammo item ids) pass through.
local function NormalizeStored(value)
    if type(value) == "string" then
        return c:NormalizeItemString(value) or value;
    end
    return value;
end

function c:SaveConditionsMet(type)
    type = type or c.OPT_SAVECHANGES;
    return GQ_OPTIONS[type] == c.OPTVALUE_SAVECHANGES_ALWAYS or
               (GQ_OPTIONS[type] == c.OPTVALUE_SAVECHANGES_CHARMENU and c.paperDollFrame:IsVisible()) or
               (GQ_OPTIONS[type] == c.OPTVALUE_SAVECHANGES_GQMENU and GqUiFrame:IsVisible());
end

----- [ events ] -----

c.EVENT_MOUNT = "EVENT_MOUNT";
c.EVENT_DISMOUNT = "EVENT_DISMOUNT";
c.EVENT_STEALTH = "EVENT_STEALTH";
c.EVENT_UNSTEALTH = "EVENT_UNSTEALTH";
c.EVENT_PARTY_JOIN = "EVENT_PARTY_JOIN";
c.EVENT_PARTY_LEAVE = "EVENT_PARTY_LEAVE";
c.EVENT_RAID_JOIN = "EVENT_RAID_JOIN";
c.EVENT_RAID_LEAVE = "EVENT_RAID_LEAVE";
c.EVENT_BG_ENTER = "EVENT_BG_ENTER";
c.EVENT_BG_LEAVE = "EVENT_BG_LEAVE";
c.EVENT_ZONE_ENTER = "EVENT_ZONE_ENTER";
c.EVENT_ZONE_LEAVE = "EVENT_ZONE_LEAVE";
c.EVENT_PVP_ENABLE = "EVENT_PVP_ENABLE";
c.EVENT_PVP_DISABLE = "EVENT_PVP_DISABLE";
c.EVENT_AFK_ENABLE = "EVENT_AFK_ENABLE";
c.EVENT_AFK_DISABLE = "EVENT_AFK_DISABLE";
c.EVENT_SUBMERGE = "EVENT_SUBMERGE";
c.EVENT_EMERGE = "EVENT_EMERGE";
c.EVENT_COMBAT_ENTER = "EVENT_COMBAT_ENTER";
c.EVENT_COMBAT_LEAVE = "EVENT_COMBAT_LEAVE";
-- c.EVENT_SPELLCAST_START = "EVENT_SPELLCAST_START";
c.EVENT_SHAPESHIFT_IN = "EVENT_SHAPESHIFT_IN";
c.EVENT_SHAPESHIFT_OUT = "EVENT_SHAPESHIFT_OUT";
c.EVENT_AURA_CHANGED = "EVENT_AURA_CHANGED"; -- paladin auras
c.EVENT_STANCE_CHANGED = "EVENT_STANCE_CHANGED"; -- warrior stances
c.EVENT_TALENTS_CHANGED = "EVENT_TALENTS_CHANGED"; -- spec group swap

local events, eventNamesSorted;
function c:GetEvents()
    if not events then
        events = {
            [c.EVENT_MOUNT] = c:GetText("on mount"),
            [c.EVENT_DISMOUNT] = c:GetText("on dismount"),
            [c.EVENT_STEALTH] = c:GetText("on entering stealth"),
            [c.EVENT_UNSTEALTH] = c:GetText("on leaving stealth"),
            [c.EVENT_PARTY_JOIN] = c:GetText("on joining party"),
            [c.EVENT_PARTY_LEAVE] = c:GetText("on leaving party"),
            [c.EVENT_RAID_JOIN] = c:GetText("on joining raid"),
            [c.EVENT_RAID_LEAVE] = c:GetText("on leaving raid"),
            [c.EVENT_BG_ENTER] = c:GetText("on entering battleground"),
            [c.EVENT_BG_LEAVE] = c:GetText("on leaving battleground"),
            [c.EVENT_ZONE_ENTER] = c:GetText("on entering zone"),
            [c.EVENT_ZONE_LEAVE] = c:GetText("on leaving zone"),
            [c.EVENT_PVP_ENABLE] = c:GetText("on enabling PvP"),
            [c.EVENT_PVP_DISABLE] = c:GetText("on disabling PvP"),
            [c.EVENT_AFK_ENABLE] = c:GetText("on enabling AFK"),
            [c.EVENT_AFK_DISABLE] = c:GetText("on disabling AFK"),
            [c.EVENT_SUBMERGE] = c:GetText("on submerge (water)"),
            [c.EVENT_EMERGE] = c:GetText("on emerge (water)"),
            [c.EVENT_COMBAT_ENTER] = c:GetText("on enter combat"),
            [c.EVENT_COMBAT_LEAVE] = c:GetText("on leave combat"),
            -- [c.EVENT_SPELLCAST_START] = c:GetText("on spell start"),
            [c.EVENT_SHAPESHIFT_IN] = c:GetText("on shapeshift (enter)"),
            [c.EVENT_SHAPESHIFT_OUT] = c:GetText("on shapeshift (leave)"),
            [c.EVENT_AURA_CHANGED] = c:GetText("on aura change"),
            [c.EVENT_STANCE_CHANGED] = c:GetText("on stance change"),
            [c.EVENT_TALENTS_CHANGED] = c:GetText("on talents change")
        };
    end
    return events;
end

function c:GetEventNamesSorted()
    if not eventNamesSorted then
        eventNamesSorted = {c.EVENT_MOUNT, c.EVENT_DISMOUNT};

        local tmp = {};
        for eventName, eventDisplayName in pairs(c:GetEvents()) do
            table.insert(tmp, eventDisplayName);
        end

        table.sort(tmp); -- , function(a, b) return a > b end); -- descending
        for index, sortedDisplayName in ipairs(tmp) do
            for eventName, eventDisplayName in pairs(c:GetEvents()) do
                if sortedDisplayName == eventDisplayName and not c:TableContains(eventNamesSorted, eventName) then
                    table.insert(eventNamesSorted, eventName);
                    break
                end
            end
        end
    end
    return eventNamesSorted;
end

----- [ inventory ] -----
---- [gear] ----

function c:IsItemEquipped(itemString)
    -- needed for checking swapped rings on sets
    itemString = NormalizeStored(itemString);
    local list = {};
    for _, slotId in ipairs(c:GetSlotSwitchOrder()) do
        if c:Equals(c:GetItemString(slotId), itemString) then
            tinsert(list, slotId);
        end
    end
    if getn(list) > 0 then
        return list;
    end
end

function c:GetAffectedEquipmentSlots(setName, currentSetName)
    local affectedSlots = {};
    for _, slotId in ipairs(c:GetSlotSwitchOrder()) do
        if (not c:LoadPartialOption(setName) or c:LoadSlotState(slotId, setName)) and c:LoadSlot(slotId, setName) ~=
            c:LoadSlot(slotId, currentSetName) then
            tinsert(affectedSlots, slotId);
        end
    end
    return affectedSlots;
end

function c:AffectsOnlyWeapons(setName, currentSetName)
    currentSetName = currentSetName or c:LoadCurrentSetName();
    if not currentSetName then
        return false; -- might be improved some day; this is just a workaround for a rare scenario
    end
    for _, slotId in ipairs(c:GetAffectedEquipmentSlots(setName, currentSetName)) do
        if slotId ~= INVSLOT_MAINHAND and slotId ~= INVSLOT_OFFHAND and slotId ~= INVSLOT_RANGED then
            return false;
        end
    end
    return true;
end

function c:IsWeaponsOnlySet(setName)
    if not c:LoadPartialOption(setName) then
        return false;
    end
    for _, slotId in ipairs(c:GetSlotSwitchOrder()) do
        if c:LoadSlotState(slotId, setName) and slotId ~= INVSLOT_MAINHAND and slotId ~= INVSLOT_OFFHAND and slotId ~=
            INVSLOT_RANGED then
            return false;
        end
    end
    return true;
end

---- [bank] ----

--- Returns cache, sum: cache[bankTabBagId] = free slots of that character bank tab (0 if it may not hold gear).
function c:GetBankSpace()
    if c:IsAtBank() then
        local bankSpaceCache, sum = {}, 0;
        for _, bagId in ipairs(c:GetBankBagIds()) do
            local noFreeSlots, bagType = c:GetContainerNumFreeSlots(bagId);
            if bagType == 0 and noFreeSlots then
                bankSpaceCache[bagId] = noFreeSlots;
                sum = sum + noFreeSlots;
            else
                bankSpaceCache[bagId] = 0;
            end
        end
        return bankSpaceCache, sum;
    end
end

function c:CheckNeccessaryPushSpace(setName)
    if c:IsAtBank() and setName then
        local items = {};
        for _, slotId in ipairs(c:GetSlotSwitchOrder()) do
            local itemString = c:LoadSlot(slotId, setName);
            local currentSetName = c:LoadCurrentSetName();
            if (not c:LoadPartialOption(setName) or c:LoadSlotState(slotId, setName)) and not c:IsEmpty(itemString) and
                (not currentSetName or not c:IsSetItem(itemString, currentSetName)) and
                (c:IsSetItemOnSlot(slotId, itemString) or c:FindItemInBags(itemString)) then
                items[slotId] = itemString;
            end
        end

        local bankSpaceCache, freeSpace = c:GetBankSpace();
        return freeSpace, items, bankSpaceCache;
    end
end

function c:CheckNeccessaryPullSpace(setName)
    if c:IsAtBank() and setName then
        local items = {};
        for _, slotId in ipairs(c:GetSlotSwitchOrder()) do
            local itemString = c:LoadSlot(slotId, setName);
            if (not c:LoadPartialOption(setName) or c:LoadSlotState(slotId, setName)) and not c:IsEmpty(itemString) and
                not (c:IsSetItemOnSlot(slotId, itemString) or c:FindItemInBags(itemString)) then
                items[slotId] = itemString;
            end
        end

        local bagSpaceCache, freeSpace = c:GetBagSpace();
        return freeSpace, items, bagSpaceCache;
    end
end

--- Returns bagId, slotId of the first character bank tab slot holding the item (for c:PickupContainerItem), or nil.
---@param itemString string
function c:FindItemInBank(itemString)
    itemString = NormalizeStored(itemString);
    if not itemString or itemString == c.VALUE_NONE then
        return nil;
    end

    for _, bagId in ipairs(c:GetBankBagIds()) do
        for containerSlotId = 1, c:GetContainerNumSlots(bagId) do
            local containerItemString = c:GetItemString(c:GetContainerItemLink(bagId, containerSlotId));
            if c:Equals(itemString, containerItemString) then
                return bagId, containerSlotId;
            end
        end
    end
    return nil;
end

---- [bags] ----

--- Returns cache, sum: cache[bagId] = free slots for every bag of c:GetBagIds() (0 for special bags).
function c:GetBagSpace()
    local bagSpaceCache, sum = {}, 0;
    for _, bagId in ipairs(c:GetBagIds()) do
        local noFreeSlots, bagType = c:GetContainerNumFreeSlots(bagId);
        if bagType == 0 and noFreeSlots then
            bagSpaceCache[bagId] = noFreeSlots;
            sum = sum + noFreeSlots;
        else
            bagSpaceCache[bagId] = 0;
        end
    end
    return bagSpaceCache, sum;
end

function c:CheckNeccessaryBagSpace(setName)
    if setName then
        local count, maxCount = 0, 0;
        for _, slotId in ipairs(c:GetSlotSwitchOrder()) do
            local equippedItemString, desiredItemString = c:GetItemString(slotId), c:LoadSlot(slotId, setName);
            if (not c:LoadPartialOption(setName) or c:LoadSlotState(slotId, setName)) and
                not c:IsEmpty(equippedItemString) and c:IsEmpty(desiredItemString) then
                count = count + 1;
                -- elseif c:IsEmpty(c:GetItemId(slotId)) and set[slotId] and not c:IsEmpty(set[slotId]) then
                --	count = count - 1;
            end

            if count > maxCount then
                maxCount = count;
            end
        end

        local bagSpaceCache, freeSpace = c:GetBagSpace();
        return freeSpace, maxCount, bagSpaceCache;
    end
end

function c:FindItemInBags(neededItemString)
    neededItemString = NormalizeStored(neededItemString);
    if not neededItemString or neededItemString == c.VALUE_NONE then
        return nil;
    end

    local list = {};
    for _, bagId in ipairs(c:GetBagIds()) do
        for slotId = 1, c:GetContainerNumSlots(bagId) do
            local itemString = c:GetItemString(c:GetContainerItemLink(bagId, slotId));
            if itemString == neededItemString then
                tinsert(list, {
                    bagId = bagId,
                    slotId = slotId
                });
            end
        end
    end
    if getn(list) > 0 then
        return list;
    end
end

----- [ items ] -----

--- Slot 0 (ammo): numeric item id or nil. Slot 1..19: normalised item string of the equipped item.
--- Item link or item string: normalised item string. Anything else (or an empty slot): VALUE_NONE.
--- Every item string GearQuipper stores or compares comes from here.
function c:GetItemString(value)
    if value then
        if value == INVSLOT_AMMO then
            -- ammo slot workaround
            return c:SafeCall(GetInventoryItemID, "player", INVSLOT_AMMO);
        elseif type(value) == "number" and c:GetSlotInfo(value) then
            -- slotId
            return c:NormalizeItemString(GetInventoryItemLink("player", value)) or c.VALUE_NONE;
        elseif type(value) == "string" then
            -- itemLink or itemString
            return c:NormalizeItemString(value) or c.VALUE_NONE;
        end
    end
    return c.VALUE_NONE;
end

function c:GetItemId(itemString)
    if itemString and c:StartsWith(itemString, "item:") then
        return string.match(itemString, "%d+");
    end
end

local ITEMINFO_NAME = "ITEMINFO_NAME";
local ITEMINFO_LINK = "ITEMINFO_LINK";
local ITEMINFO_RARITY = "ITEMINFO_RARITY";
local ITEMINFO_LEVEL = "ITEMINFO_LEVEL";
local ITEMINFO_MINLEVEL = "ITEMINFO_MINLEVEL";
local ITEMINFO_TYPE = "ITEMINFO_TYPE";
local ITEMINFO_SUBTYPE = "ITEMINFO_SUBTYPE";
local ITEMINFO_STACKCOUNT = "ITEMINFO_STACKCOUNT";
local ITEMINFO_EQUIPLOC = "ITEMINFO_EQUIPLOC";
local function GetItemInfos(itemString, info)
    if itemString and not c:IsEmpty(itemString) then
        local itemInfo = {};
        itemInfo[ITEMINFO_NAME], itemInfo[ITEMINFO_LINK], itemInfo[ITEMINFO_RARITY], itemInfo[ITEMINFO_LEVEL], itemInfo[ITEMINFO_MINLEVEL], itemInfo[ITEMINFO_TYPE], itemInfo[ITEMINFO_SUBTYPE], itemInfo[ITEMINFO_STACKCOUNT], itemInfo[ITEMINFO_EQUIPLOC] =
            c:GetItemInfo(itemString);
        if not itemInfo[ITEMINFO_NAME] then
            -- not cached yet; the next call after GET_ITEM_INFO_RECEIVED returns it
            c:RequestItemData(itemString);
        end

        return itemInfo[info];
    end
end

function c:GetItemName(itemString)
    local itemName = GetItemInfos(itemString, ITEMINFO_NAME);
    if itemName then
        return itemName;
    end
    return EMPTY;
end

function c:GetItemLink(itemString)
    local itemLink = GetItemInfos(itemString, ITEMINFO_LINK);
    if itemLink then
        return itemLink;
    end
    return EMPTY;
end

local slotIdToEquipLocs = {
    [INVSLOT_HEAD] = {"INVTYPE_HEAD"}, --  1
    [INVSLOT_NECK] = {"INVTYPE_NECK"}, --  2
    [INVSLOT_SHOULDER] = {"INVTYPE_SHOULDER"}, --  3
    [INVSLOT_BODY] = {"INVTYPE_BODY"}, --  4
    [INVSLOT_CHEST] = {"INVTYPE_CHEST", "INVTYPE_ROBE"}, --  5
    [INVSLOT_WAIST] = {"INVTYPE_WAIST"}, --  6
    [INVSLOT_LEGS] = {"INVTYPE_LEGS"}, -- 	7
    [INVSLOT_FEET] = {"INVTYPE_FEET"}, --  8
    [INVSLOT_WRIST] = {"INVTYPE_WRIST"}, --  9
    [INVSLOT_HAND] = {"INVTYPE_HAND"}, -- 10
    [INVSLOT_FINGER1] = {"INVTYPE_FINGER"}, -- 11
    [INVSLOT_FINGER2] = {"INVTYPE_FINGER"}, -- 12
    [INVSLOT_TRINKET1] = {"INVTYPE_TRINKET"}, -- 13
    [INVSLOT_TRINKET2] = {"INVTYPE_TRINKET"}, -- 14
    [INVSLOT_BACK] = {"INVTYPE_CLOAK"}, -- 15
    [INVSLOT_MAINHAND] = {"INVTYPE_WEAPON", "INVTYPE_2HWEAPON", "INVTYPE_WEAPONMAINHAND"}, -- 16
    [INVSLOT_OFFHAND] = {"INVTYPE_WEAPON", "INVTYPE_WEAPONOFFHAND", "INVTYPE_SHIELD", "INVTYPE_QUIVER",
                         "INVTYPE_HOLDABLE"}, -- 17
    [INVSLOT_RANGED] = {"INVTYPE_RANGED", "INVTYPE_THROWN", "INVTYPE_RANGEDRIGHT", "INVTYPE_RELIC"},
    [INVSLOT_TABARD] = {"INVTYPE_TABARD"}, -- 19
    [INVSLOT_AMMO] = {"INVTYPE_AMMO"}
}

function c:GetItemEquipLoc(value)
    if c:GetSlotInfo(value) then
        -- slotId
        return slotIdToEquipLocs[value];
    elseif not c:IsEmpty(value) then
        -- itemString, itemLink or itemId; GetItemInfoInstant does not need the item cache
        local _, _, _, equipLoc = c:GetItemInfoInstant(value);
        return equipLoc;
    end
end

function c:GetItemRarity(itemString)
    local itemRarity = GetItemInfos(itemString, ITEMINFO_RARITY);
    if itemRarity then
        return itemRarity;
    end
    return 1; -- rarity_common
end

function c:GetRarityColor(rarity)
    return ITEM_QUALITY_COLORS[rarity];
end

c.ITEM_STRING = "ITEM_STRING";
c.ITEM_SLOT_ID = "ITEM_SLOT_ID";
c.ITEM_BAG_ID = "ITEM_BAG_ID";

function c:GetMatchingItems(slotId)
    local equipLocs, result = {}, {};

    local function CreateEntry(bagId, bagSlotId, itemString)
        local newEntry = {};
        newEntry[c.ITEM_BAG_ID] = bagId;
        newEntry[c.ITEM_SLOT_ID] = bagSlotId;
        newEntry[c.ITEM_STRING] = itemString;
        return newEntry;
    end

    -- get equiplocs by slotId
    for _, equipLoc in ipairs(c:GetItemEquipLoc(slotId)) do
        table.insert(equipLocs, equipLoc);
    end
    -- end

    local function IsMatching(itemString)
        local equipLoc = c:GetItemEquipLoc(itemString);
        return equipLoc and tContains(equipLocs, equipLoc);
    end

    local function AddContainerItems(bagIds)
        for _, bagId in ipairs(bagIds) do
            for containerSlotId = 1, c:GetContainerNumSlots(bagId) do
                local itemString = c:GetItemString(c:GetContainerItemLink(bagId, containerSlotId));
                if not c:IsEmpty(itemString) and IsMatching(itemString) then
                    table.insert(result, CreateEntry(bagId, containerSlotId, itemString));
                end
            end
        end
    end

    -- bags
    AddContainerItems(c:GetBagIds());

    -- bank tabs (empty unless the bank is open)
    AddContainerItems(c:GetBankBagIds());

    -- equipped items (dual wield, rings, trinkets); the other slot may hold an item that does not fit this one
    local itemString = c:GetItemString(slotId);
    if not c:IsEmpty(itemString) and IsMatching(itemString) then
        local itemSlots = c:GetItemSlots(itemString);
        for _, equippedSlotId in ipairs(itemSlots) do
            local equippedItemString = c:GetItemString(equippedSlotId);
            if not c:IsEmpty(equippedItemString) and not c:Equals(equippedItemString, itemString) and
                IsMatching(equippedItemString) then
                table.insert(result, CreateEntry(nil, equippedSlotId, equippedItemString));
            end
        end
    end

    return result, getn(result);
end

local CACHETYPE_BAGS, CACHETYPE_GEAR = "bags", "gear";
function c:CacheCurrentGearAndBags()
    local cache = {
        [CACHETYPE_BAGS] = {},
        [CACHETYPE_GEAR] = {
            [0] = {}
        }
    };

    -- bags
    for _, bagId in ipairs(c:GetBagIds()) do
        cache[CACHETYPE_BAGS][bagId] = cache[CACHETYPE_BAGS][bagId] or {};

        for slotId = 1, c:GetContainerNumSlots(bagId) do
            local itemString = c:GetItemString(c:GetContainerItemLink(bagId, slotId));
            if itemString then
                cache[CACHETYPE_BAGS][bagId][slotId] = itemString;
            end
        end
    end

    -- gear
    for slotId, slotName in pairs(c:GetSlotInfo()) do
        local itemString = c:GetItemString(slotId);
        if itemString then
            cache[CACHETYPE_GEAR][0][slotId] = itemString;
        end
    end

    return cache;
end

--- Returns cacheType ("bags", "gear"), bagId (always 0 for gear), slotId, oldItemString, newItemString of first changed item
---@param lastGearAndBagsCache table
---@return table, string, string, string, string, string
function c:GetFirstChangedItem(lastGearAndBagsCache)
    local newCache = c:CacheCurrentGearAndBags();

    -- same item name; falls back to the item id while a name is not cached (both would read EMPTY)
    local function IsSameItem(oldItemString, newItemString)
        local oldName, newName = c:GetItemName(oldItemString), c:GetItemName(newItemString);
        if oldName ~= EMPTY and newName ~= EMPTY then
            return oldName == newName;
        end
        local oldItemId = c:GetItemId(oldItemString);
        return oldItemId ~= nil and oldItemId == c:GetItemId(newItemString);
    end

    if lastGearAndBagsCache then
        for type, typeValues in pairs(newCache) do
            for bagId, bagValues in pairs(typeValues) do
                local lastBagValues = lastGearAndBagsCache[type] and lastGearAndBagsCache[type][bagId];
                for slotId, newItemString in pairs(bagValues) do
                    local oldItemString = lastBagValues and lastBagValues[slotId];

                    -- both not empty + same slot + same itemname + different itemstring
                    if not c:IsEmpty(oldItemString) and not c:IsEmpty(newItemString) and oldItemString ~= newItemString and
                        IsSameItem(oldItemString, newItemString) then
                        return type, bagId, slotId, oldItemString, newItemString;
                    end
                end
            end
        end
    end
end

function c:GetItemSlots(itemString)
    if itemString then
        local result = {};
        local itemType = c:GetItemEquipLoc(itemString);
        for slotId, itemTypes in pairs(slotIdToEquipLocs) do
            if itemType and tContains(itemTypes, itemType) then
                tinsert(result, slotId);
            end
        end
        return result;
    end
end

----- [ sets ] -----

function c:IsValidSetName(candidate)
    return candidate and candidate ~= "" and (not c:StringContains(candidate, "$")) and
               (not c:TableContains(c:LoadSetNames(), candidate, true));
end

function c:IsSetComplete(setName)
    setName = setName or c:LoadCurrentSetName();
    if setName then
        for slotId, _ in ipairs(c:GetSlotInfo()) do
            if (not c:LoadPartialOption(setName) or c:LoadSlotState(slotId, setName)) and
                not c:IsSetItemOnSlot(slotId, c:LoadSlot(slotId, setName)) then
                return false;
            end
        end
        return true;
    end
end

function c:IsSetAvailable(setName)
    setName = setName or c:LoadCurrentSetName();
    if setName then
        local missingItems = {};
        for slotId, _ in ipairs(c:GetSlotInfo()) do
            local itemString = c:LoadSlot(slotId, setName);
            if (not c:LoadPartialOption(setName) or c:LoadSlotState(slotId, setName)) and
                (itemString ~= c.VALUE_NONE and not c:IsItemEquipped(itemString) and not c:FindItemInBags(itemString) and
                    not c:FindItemInBank(itemString)) then
                missingItems[slotId] = itemString;
            end
        end
        return c:GetTableSize(missingItems) == 0, missingItems;
    end
end

function c:IsSetCurrentSetItem(itemString)
    return c:IsSetItem(itemString, c:LoadCurrentSetName());
end

function c:IsSetItem(itemString, setName)
    if setName then
        return c:TableContains(c:LoadSet(setName), itemString);
    else
        for _, sn in ipairs(c:LoadSetNames()) do
            if c:IsSetItem(itemString, sn) then
                return true;
            end
        end
    end
end

function c:IsSetItemOnSlot(slotId, itemString)
    itemString = itemString or c:LoadSlot(slotId);
    return c:Equals(c:GetItemString(slotId), NormalizeStored(itemString));
end

function c:IsEmpty(value)
    if not value or c:Equals(value, c.VALUE_NONE) or c:Equals(value, 0) then
        return true;
    else
        local itemString;
        if c:GetSlotInfo()[value] then
            -- slotId
            itemString = c:GetItemString(value);
        else
            -- itemString or spellId
            itemString = value;
        end
        return c:Equals(itemString, c.VALUE_NONE) or c:Equals(itemString, 0);
    end
end

function c:GetItemSets(itemString)
    local result = {};
    if itemString ~= c.VALUE_NONE then
        for index, setName in ipairs(c:LoadSetNames()) do
            for slotId in pairs(c:GetSlotInfo()) do
                if (not c:LoadPartialOption(setName) or c:LoadSlotState(slotId, setName)) and
                    c:LoadSlot(slotId, setName) == itemString then
                    table.insert(result, setName);
                    break
                end
            end
        end
    end
    table.sort(result);
    return result;
end

----- [ slots ] -----

local SLOT_AMMO = "AmmoSlot"; --  0
local SLOT_HEAD = "HeadSlot"; --  1
local SLOT_NECK = "NeckSlot"; --  2
local SLOT_SHOULDER = "ShoulderSlot"; --  3
local SLOT_SHIRT = "ShirtSlot"; --  4
local SLOT_CHEST = "ChestSlot"; --  5
local SLOT_WAIST = "WaistSlot"; --  6
local SLOT_LEGS = "LegsSlot"; --  7
local SLOT_FEET = "FeetSlot"; --  8
local SLOT_WRIST = "WristSlot"; --  9
local SLOT_HANDS = "HandsSlot"; -- 10
local SLOT_FINGER1 = "Finger0Slot"; -- 11
local SLOT_FINGER2 = "Finger1Slot"; -- 12
local SLOT_TRINKET1 = "Trinket0Slot"; -- 13
local SLOT_TRINKET2 = "Trinket1Slot"; -- 14
local SLOT_BACK = "BackSlot"; -- 15
local SLOT_MAINHAND = "MainHandSlot"; -- 16
local SLOT_OFFHAND = "SecondaryHandSlot"; -- 17
local SLOT_RANGED = "RangedSlot"; -- 18
local SLOT_TABARD = "TabardSlot"; -- 19

local slotInfo = {
    [INVSLOT_AMMO] = SLOT_AMMO,
    [INVSLOT_HEAD] = SLOT_HEAD,
    [INVSLOT_NECK] = SLOT_NECK,
    [INVSLOT_SHOULDER] = SLOT_SHOULDER,
    [INVSLOT_BODY] = SLOT_SHIRT,
    [INVSLOT_CHEST] = SLOT_CHEST,
    [INVSLOT_WAIST] = SLOT_WAIST,
    [INVSLOT_LEGS] = SLOT_LEGS,
    [INVSLOT_FEET] = SLOT_FEET,
    [INVSLOT_WRIST] = SLOT_WRIST,
    [INVSLOT_HAND] = SLOT_HANDS,
    [INVSLOT_FINGER1] = SLOT_FINGER1,
    [INVSLOT_FINGER2] = SLOT_FINGER2,
    [INVSLOT_TRINKET1] = SLOT_TRINKET1,
    [INVSLOT_TRINKET2] = SLOT_TRINKET2,
    [INVSLOT_BACK] = SLOT_BACK,
    [INVSLOT_MAINHAND] = SLOT_MAINHAND,
    [INVSLOT_OFFHAND] = SLOT_OFFHAND,
    [INVSLOT_RANGED] = SLOT_RANGED,
    [INVSLOT_TABARD] = SLOT_TABARD
};

function c:GetSlotInfo(slotId)
    if slotId then
        return slotInfo[slotId];
    else
        return slotInfo;
    end
end

function c:IsWeaponSlot(slotId)
    if slotId == INVSLOT_AMMO or slotId == INVSLOT_MAINHAND or slotId == INVSLOT_OFFHAND or slotId == INVSLOT_RANGED then
        return true;
    end
end

function c:GetOtherWeaponSlot(slotId)
    if slotId == INVSLOT_MAINHAND then
        return INVSLOT_OFFHAND;
    end
    return INVSLOT_MAINHAND;
end

local defaultSlotSwitchOrder;
function c:GetDefaultSlotSwitchOrder()
    if not defaultSlotSwitchOrder then
        defaultSlotSwitchOrder = {};
        table.insert(defaultSlotSwitchOrder, INVSLOT_MAINHAND);
        table.insert(defaultSlotSwitchOrder, INVSLOT_OFFHAND);
        table.insert(defaultSlotSwitchOrder, INVSLOT_RANGED);

        for i = 0, 19 do
            if not tContains(defaultSlotSwitchOrder, i) then
                tinsert(defaultSlotSwitchOrder, i);
            end
        end
    end
    return defaultSlotSwitchOrder;
end

-- targetSetName is kept for callers; without gems the order does not depend on the set.
function c:GetSlotSwitchOrder(targetSetName)
    return c:GetDefaultSlotSwitchOrder();
end

function c:GetSlotId(slotName)
    for slotId, name in pairs(c:GetSlotInfo()) do
        if name == slotName then
            return slotId;
        end
    end
end

local displaySlotNames = {
    [0] = INVTYPE_AMMO,
    [1] = INVTYPE_HEAD,
    [2] = INVTYPE_NECK,
    [3] = INVTYPE_SHOULDER,
    [4] = INVTYPE_BODY,
    [5] = INVTYPE_CHEST,
    [6] = INVTYPE_WAIST,
    [7] = INVTYPE_LEGS,
    [8] = INVTYPE_FEET,
    [9] = INVTYPE_WRIST,
    [10] = INVTYPE_HAND,
    [11] = (INVTYPE_FINGER or "Finger") .. " 1",
    [12] = (INVTYPE_FINGER or "Finger") .. " 2",
    [13] = (INVTYPE_TRINKET or "Trinket") .. " 1",
    [14] = (INVTYPE_TRINKET or "Trinket") .. " 2",
    [15] = INVTYPE_CLOAK,
    [16] = INVTYPE_WEAPONMAINHAND,
    [17] = INVTYPE_WEAPONOFFHAND,
    [18] = INVTYPE_RANGED,
    [19] = INVTYPE_TABARD
};

function c:GetDisplaySlotName(slotId)
    if displaySlotNames[slotId] then
        return displaySlotNames[slotId];
    end
end

----- [ forms, auras, stances, specs ] -----

-- Values are spell names from c:GetSpellName; a spell this client does not know leaves no entry.
c.SPELLID_DRUID_FORM_NORMAL = c.VALUE_NONE;
c.SPELLID_DRUID_FORM_AQUATIC = 1066;
c.SPELLID_DRUID_FORM_BEAR = 5487;
c.SPELLID_DRUID_FORM_CAT = 768;
c.SPELLID_DRUID_FORM_DIRE_BEAR = 9634;
c.SPELLID_DRUID_FORM_TRAVEL = 783;
c.SPELLID_DRUID_FORM_MOONKIN = 24858;

local druidForms;
function c:GetDruidForms()
    if not druidForms then
        druidForms = {
            [c.SPELLID_DRUID_FORM_NORMAL] = c:GetText("< normal >"),
            [c.SPELLID_DRUID_FORM_AQUATIC] = c:GetSpellName(c.SPELLID_DRUID_FORM_AQUATIC),
            [c.SPELLID_DRUID_FORM_BEAR] = c:GetSpellName(c.SPELLID_DRUID_FORM_BEAR),
            [c.SPELLID_DRUID_FORM_CAT] = c:GetSpellName(c.SPELLID_DRUID_FORM_CAT),
            [c.SPELLID_DRUID_FORM_DIRE_BEAR] = c:GetSpellName(c.SPELLID_DRUID_FORM_DIRE_BEAR),
            [c.SPELLID_DRUID_FORM_TRAVEL] = c:GetSpellName(c.SPELLID_DRUID_FORM_TRAVEL),
            [c.SPELLID_DRUID_FORM_MOONKIN] = c:GetSpellName(c.SPELLID_DRUID_FORM_MOONKIN)
        };
    end
    return druidForms;
end

local druidFormsSorted;
function c:GetDruidFormsSorted()
    if not druidFormsSorted then
        druidFormsSorted = c:GetTableValuesSorted(c:GetDruidForms());
    end
    return druidFormsSorted;
end

-- Paladin auras and warrior stances: keys are rank 1 ids, and detection matches the active spell by NAME,
-- so every rank of an aura maps to its entry here.
c.SPELLID_PALADIN_AURA_NONE = c.VALUE_NONE;
c.SPELLID_PALADIN_AURA_CONCENTRATION = 19746;
c.SPELLID_PALADIN_AURA_DEVOTION = 465;
c.SPELLID_PALADIN_AURA_FIRE_RES = 19891;
c.SPELLID_PALADIN_AURA_FROST_RES = 19888;
c.SPELLID_PALADIN_AURA_RETRIBUTION = 7294;
c.SPELLID_PALADIN_AURA_SANCTITY = 20218;
c.SPELLID_PALADIN_AURA_SHADOW_RES = 19876;

local paladinAuras;
function c:GetPaladinAuras()
    if not paladinAuras then
        paladinAuras = {
            [c.SPELLID_PALADIN_AURA_NONE] = c:GetText("< " .. NONE_KEY .. " >"),
            [c.SPELLID_PALADIN_AURA_CONCENTRATION] = c:GetSpellName(c.SPELLID_PALADIN_AURA_CONCENTRATION),
            [c.SPELLID_PALADIN_AURA_DEVOTION] = c:GetSpellName(c.SPELLID_PALADIN_AURA_DEVOTION),
            [c.SPELLID_PALADIN_AURA_FIRE_RES] = c:GetSpellName(c.SPELLID_PALADIN_AURA_FIRE_RES),
            [c.SPELLID_PALADIN_AURA_FROST_RES] = c:GetSpellName(c.SPELLID_PALADIN_AURA_FROST_RES),
            [c.SPELLID_PALADIN_AURA_RETRIBUTION] = c:GetSpellName(c.SPELLID_PALADIN_AURA_RETRIBUTION),
            [c.SPELLID_PALADIN_AURA_SANCTITY] = c:GetSpellName(c.SPELLID_PALADIN_AURA_SANCTITY),
            [c.SPELLID_PALADIN_AURA_SHADOW_RES] = c:GetSpellName(c.SPELLID_PALADIN_AURA_SHADOW_RES)
        };
    end
    return paladinAuras;
end

local paladinAurasSorted;
function c:GetPaladinAurasSorted()
    if not paladinAurasSorted then
        paladinAurasSorted = c:GetTableValuesSorted(c:GetPaladinAuras());
    end
    return paladinAurasSorted;
end

c.SPELLID_WARRIOR_STANCE_BATTLE = 2457;
c.SPELLID_WARRIOR_STANCE_BERSERKER = 2458;
c.SPELLID_WARRIOR_STANCE_DEFENSIVE = 71;

local warriorStances;
function c:GetWarriorStances()
    if not warriorStances then
        warriorStances = {
            [c.SPELLID_WARRIOR_STANCE_BATTLE] = c:GetSpellName(c.SPELLID_WARRIOR_STANCE_BATTLE),
            [c.SPELLID_WARRIOR_STANCE_BERSERKER] = c:GetSpellName(c.SPELLID_WARRIOR_STANCE_BERSERKER),
            [c.SPELLID_WARRIOR_STANCE_DEFENSIVE] = c:GetSpellName(c.SPELLID_WARRIOR_STANCE_DEFENSIVE)
        };
    end
    return warriorStances;
end

local warriorStancesSorted;
function c:GetWarriorStancesSorted()
    if not warriorStancesSorted then
        warriorStancesSorted = c:GetTableValuesSorted(c:GetWarriorStances());
    end
    return warriorStancesSorted;
end

local talentSpecializations;
function c:GetTalentSpecializations()
    if not talentSpecializations then
        talentSpecializations = {
            [1] = TALENT_SPEC_PRIMARY or c:GetText("Primary"),
            [2] = TALENT_SPEC_SECONDARY or c:GetText("Secondary")
        };
    end
    return talentSpecializations;
end

local talentSpecializationSorted;
function c:GetTalentSpecializationsSorted()
    if not talentSpecializationSorted then
        talentSpecializationSorted = c:GetTableValuesSorted(c:GetTalentSpecializations());
    end
    return talentSpecializationSorted;
end

----- [ zones ] -----

local zoneCache = {};
function c:GetZoneChildrenSorted(parentMapId)
    if not zoneCache[parentMapId] then
        zoneCache[parentMapId] = {};
        for k, v in ipairs(C_Map.GetMapChildrenInfo(parentMapId) or {}) do
            table.insert(zoneCache[parentMapId], v);
        end
        table.sort(zoneCache[parentMapId], function(a, b)
            local a, b = c:ReplaceUmlauts(a["name"]), c:ReplaceUmlauts(b["name"]); -- umlaute
            return a < b
        end);
    end
    return zoneCache[parentMapId];
end

function c:GetZoneInfo(mapId)
    if mapId then
        return C_Map.GetMapInfo(mapId);
    end
end

function c:GetZoneInfoByName(zoneName)
    for i = 0, 2000 do
        local mapInfo = C_Map.GetMapInfo(i);
        if mapInfo and mapInfo["name"] == zoneName then
            return mapInfo;
        end
    end
end

function c:GetCurrentZoneInfo()
    return c:GetZoneInfoByName(GetRealZoneText());
end

function c:GetZoneDisplayName(mapId)
    local zoneInfo = c:GetZoneInfo(mapId);
    if not zoneInfo then
        return tostring(mapId or UNKNOWN);
    end
    local parentZoneEntry = c:GetZoneInfo(zoneInfo["parentMapID"]);
    if parentZoneEntry and parentZoneEntry["mapID"] ~= 947 then
        return zoneInfo["name"] .. ", " .. parentZoneEntry["name"];
    end
    return zoneInfo["name"];
end

-- Classic map ids of the vanilla battlegrounds (Alterac Valley, Warsong Gulch, Arathi Basin): fallback only.
local battlegroundMapIds = {
    [1459] = true,
    [1460] = true,
    [1461] = true
};

local function IsInBattleground()
    local instanceType = c:SafeCall(function()
        return select(2, IsInInstance());
    end);
    return instanceType == "pvp" or c:ReadState(C_PvP and C_PvP.IsBattleground) == true;
end

-- Forever's battleground map ids may differ from Classic's: the player's current map counts as a battleground
-- while the player is in a pvp instance, and is remembered so leaving it is recognised as well.
function c:IsZoneBattleground(mapId)
    if not mapId then
        return false;
    end
    if battlegroundMapIds[mapId] then
        return true;
    end
    if mapId == c:SafeCall(C_Map.GetBestMapForUnit, "player") and IsInBattleground() then
        battlegroundMapIds[mapId] = true;
        return true;
    end
    return false;
end

----- [ lua ] -----
function c:DebugPrint(...)
    if c.debugMode then
        local values = {};
        for k, v in pairs({...}) do
            tinsert(values, tostring(v));
        end
        print("[GearQuipper][Debug] " .. strjoin(", ", unpack(values)));
    end
end

function c:Println(str)
    if str then
        print("[GearQuipper] " .. str);
    end
end

function c:StartsWith(str, substr, caseInsensitive)
    if str then
        if substr and caseInsensitive then
            str = string.upper(str);
            substr = string.upper(substr);
        end

        return string.sub(str, 1, string.len(substr)) == substr;
    end
end

function c:EndsWith(str, substr, caseInsensitive)
    if str then
        if substr and caseInsensitive then
            str = string.upper(str);
            substr = string.upper(substr);
        end

        return substr == "" or str:sub(-#substr) == substr;
    end
end

function c:StringContains(str, match, caseInsensitive)
    if str and match then
        if caseInsensitive then
            str = string.upper(str);
            match = string.upper(match);
        end

        return string.find(str, match, 1, true);
    end
end

function c:StringReplace(str, find, replace)
    return str:gsub(find, replace);
end

function c:ReplaceUmlauts(str)
    str = c:StringReplace(str, "Ä", "Ae");
    str = c:StringReplace(str, "ä", "ae");
    str = c:StringReplace(str, "Ö", "Oe");
    str = c:StringReplace(str, "ö", "oe");
    str = c:StringReplace(str, "Ü", "Ue");
    str = c:StringReplace(str, "ü", "ue");
    return str;
end

function c:Trim(str)
    if str then
        return str:gsub("^%s*(.-)%s*$", "%1");
    end
    return "";
end

function c:BoolToText(value, trueText, falseText)
    if value then
        return trueText;
    end
    return falseText;
end

function c:ToBoolean(value)
    if value == nil then
        return false;
    end
    return value;
end

function c:GetTableSize(t)
    local count = 0
    for _, __ in pairs(t) do
        count = count + 1
    end
    return count
end

function c:IsTable(t)
    return type(t) == "table";
end

function c:TableIsArray(t)
    return c:IsTable(t) and t[1] and c:GetTableSize(t) == getn(t);
end

function c:TableContains(t, value, caseInsensitive)
    if caseInsensitive then
        value = string.upper(value);
    else
        value = tostring(value);
    end

    if c:TableIsArray(t) then
        for k, v in ipairs(t) do
            if (not caseInsensitive and tostring(v) == value) or (caseInsensitive and string.upper(v) == value) then
                return v;
            end
        end
    else
        for k, v in pairs(t) do
            if (not caseInsensitive and tostring(v) == value) or (caseInsensitive and string.upper(v) == value) then
                return v;
            end
        end
    end
end

function c:GetTableValuesSorted(t, descending)
    local tmp = {};
    for _, v in pairs(t) do
        table.insert(tmp, v);
    end

    if descending then
        table.sort(tmp, function(a, b)
            return a > b
        end); -- descending
    else
        table.sort(tmp);
    end

    return tmp;
end

function c:Push(t, val)
    if c:TableIsArray(t) then
        tinsert(t, val);
        return getn(t);
    end
end

function c:Pop(t)
    if c:TableIsArray(t) and getn(t) > 0 then
        local index = getn(t);
        local val = t[index];
        tremove(t, index);
        return val;
    end
end

function c:Dequeue(t)
    if c:TableIsArray(t) and getn(t) > 0 then
        local val = t[1];
        tremove(t, 1);
        return val;
    end
end

function c:RemoveValueFromArray(array, value)
    for k, v in ipairs(array) do
        if v == value then
            return table.remove(array, k);
        end
    end
end

function c:Deepcopy(orig, copies)
    copies = copies or {};
    local orig_type, copy = type(orig);
    if orig_type == "table" then
        if copies[orig] then
            copy = copies[orig];
        else
            copy = {};
            copies[orig] = copy;
            setmetatable(copy, c:Deepcopy(getmetatable(orig), copies));
            for orig_key, orig_value in next, orig, nil do
                copy[c:Deepcopy(orig_key, copies)] = c:Deepcopy(orig_value, copies);
            end
        end
    else
        copy = orig;
    end
    return copy;
end

function c:Flat(t, maxDepth)
    maxDepth = maxDepth or 10;

    local result = {};
    if c:IsTable(t) then
        if maxDepth > 0 then
            if c:TableIsArray(t) then
                for _, val in ipairs(t) do
                    for _, rVal in ipairs(c:Flat(val, maxDepth - 1)) do
                        tinsert(result, rVal);
                    end
                end
            else
                for _, val in pairs(t) do
                    for _, rVal in ipairs(c:Flat(val, maxDepth - 1)) do
                        tinsert(result, rVal);
                    end
                end
            end
        end
    else
        tinsert(result, t);
    end
    return result;
end

function c:FormatTextWithColor(text, colorHex)
    return string.format("|cff%s%s|r", colorHex, text);
end

function c:Equals(o1, o2, maxRecursion)
    maxRecursion = maxRecursion or 255;
    if o1 == o2 then
        return true;
    end

    local o1Type, o2Type = type(o1), type(o2);
    if o1Type ~= o2Type then
        local o1Num, o2Num = tonumber(o1), tonumber(o2);
        return o1Num and o1Num == o2Num;
    elseif o1Type == "string" or o1Type == "number" then
        return o1 == o2;
    elseif o1Type == "table" and maxRecursion > 0 then
        for k, v in pairs(o1) do
            if not c:Equals(v, o2[k], maxRecursion - 1) then
                return false;
            end
        end
        for k, v in pairs(o2) do
            if not c:Equals(v, o1[k], maxRecursion - 1) then
                return false;
            end
        end
        return true;
    end
end

function c:ExtractArguments(msg)
    local results, arg, quote = {}, "", false;
    for char in msg:gmatch(".") do
        if char == ' ' and not quote then
            if strlen(arg) > 0 then
                table.insert(results, arg);
                arg = "";
            end
        elseif char == '"' then
            if quote == true and strlen(arg) > 0 then
                table.insert(results, arg);
                arg = "";
            end
            quote = not quote;
        else
            arg = arg .. char;
        end
    end

    if strlen(arg) > 0 then
        table.insert(results, arg);
    end

    return results;
end

function c:IsNumeric(value)
    if not value then
        return false;
    end
    local t = type(value);
    if t == "number" then
        return true;
    elseif t ~= "string" then
        return false;
    end
    return value == tostring(tonumber(value));
end

function c:MathRound(x, decimals)
    if decimals and decimals > 0 then
        local mult = 10 ^ decimals
        return math.floor(x * mult + 0.5) / mult
    end
    return math.floor(x + 0.5);
end

function c:IsAddonEnabled(addonName)
    return c:SafeCall(c.IsAddOnLoaded, c, addonName) and true or false;
end

function c:RegisterDoubleClick(frame, func, button)
    frame.clicks = 0;
    frame:SetScript("OnMouseDown", function(self, btn)
        if not button or button == btn then
            self.clicks = self.clicks + 1;
            C_Timer.After(0.35, function()
                self.clicks = 0;
            end);
            if self.clicks == 2 then
                func();
                self.clicks = 0;
            end
        end
    end);
end

local random = math.random;
function c:uuid()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and random(0, 0xf) or random(8, 0xb)
        return string.format('%x', v)
    end);
end

-- wow

function c:GetOppositeAnchor(anchor)
    if anchor == "ANCHOR_TOP" then
        return "ANCHOR_BOTTOM";
    elseif anchor == "ANCHOR_BOTTOM" then
        return "ANCHOR_TOP";
    elseif anchor == "ANCHOR_LEFT" then
        return "ANCHOR_RIGHT";
    elseif anchor == "ANCHOR_RIGHT" then
        return "ANCHOR_LEFT";
    end
end
