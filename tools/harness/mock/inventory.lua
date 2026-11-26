-- inventory.lua: equipment slots 0..19, bags, keyring, reagent bag, character bank tabs, the cursor, equip rules.
--
-- Cursor semantics (like the client): picking an item up does NOT move it; it stays in its slot, locked, and the
-- cursor remembers its origin. Placing it somewhere sends one "server" request that swaps the item with whatever
-- is at the destination (the destination item goes to the origin). Requests are validated first (slot/INVTYPE,
-- bag family, combat, unique-equipped, 2H vs off-hand needing a free bag slot); a refused request raises
-- UI_ERROR_MESSAGE and leaves the cursor as it was.
-- H.latency = 0 (default): the server applies a request immediately. H.latency > 0: it applies it that many
-- seconds later; meanwhile both locations stay locked and reads (GetInventoryItemLink, bag scans) show the old
-- state, which is what an addon issuing many equips in one frame really sees.
-- Events (PLAYER_EQUIPMENT_CHANGED, UNIT_INVENTORY_CHANGED, BAG_UPDATE, ITEM_LOCK_CHANGED/ITEM_LOCKED/ITEM_UNLOCKED,
-- UI_ERROR_MESSAGE) are queued and dispatched on the next frame; BAG_UPDATE_DELAYED one frame later.
local H = ...;

local inv = {};       -- slot 1..19 -> item instance
local bags = {};      -- bagId -> {id, size, family, slots = {}, bagItem, bank, keyring, reagent}
local locks = {};     -- location key -> true
local pending = {};   -- server requests not applied yet (latency mode)
local cursor = nil;   -- {inst, from = location}
H.inv, H.bags = inv, bags;
H.ammo = nil;         -- item id referenced by the ammo slot (ammo stays in the bags, as in vanilla)
H.latency = 0;
H.blockCombatPickups = false;
H.blocked = {};       -- ADDON_ACTION_BLOCKED log
H.uiErrors = {};      -- UI_ERROR_MESSAGE log
H.sold = {};          -- items sold by UseContainerItem at a merchant
H.bank = {open = false, tabs = {}};
H.merchant = {open = false};

local GENERIC_BAGS = {0, 1, 2, 3, 4};
H.GENERIC_BAG_IDS = GENERIC_BAGS;

---------------------------------------------------------------------------
-- locations
---------------------------------------------------------------------------
local function equipLoc(slot)
    return {kind = "equip", slot = slot};
end
local function bagLoc(bag, slot)
    return {kind = "bag", bag = bag, slot = slot};
end
local function key(loc)
    return loc.kind == "equip" and ("e" .. loc.slot) or ("b" .. loc.bag .. ":" .. loc.slot);
end
local function same(a, b)
    return key(a) == key(b);
end
local function getAt(loc)
    if loc.kind == "equip" then
        return inv[loc.slot];
    end
    local bag = bags[loc.bag];
    return bag and bag.slots[loc.slot];
end
local function setAt(loc, inst)
    if loc.kind == "equip" then
        inv[loc.slot] = inst;
    else
        bags[loc.bag].slots[loc.slot] = inst;
    end
end
local function describeLoc(loc)
    return loc.kind == "equip" and ("slot " .. loc.slot) or ("bag " .. loc.bag .. " slot " .. loc.slot);
end
H.describeLoc = describeLoc;

local function accessible(bagId)
    local bag = bags[bagId];
    return bag ~= nil and (not bag.bank or H.bank.open);
end

local function lockArgs(loc)
    if loc.kind == "equip" then
        return loc.slot, nil;
    end
    return loc.bag, loc.slot;
end

-- Client-side cursor locks (pick up / ClearCursor) fire their events synchronously, inside the API call
-- (H.syncCursorLockEvents, assumed); locks ending with a server reply fire on the next frame.
H.syncCursorLockEvents = true;
local function lockEvent(event, loc, sync)
    if sync and H.syncCursorLockEvents then
        H.fire(event, lockArgs(loc));
    else
        H.queueEvent(event, lockArgs(loc));
    end
end

local function lock(loc, sync)
    if not locks[key(loc)] then
        locks[key(loc)] = true;
        lockEvent("ITEM_LOCK_CHANGED", loc, sync);
        lockEvent("ITEM_LOCKED", loc, sync);
    end
end

local function unlock(loc, sync)
    if locks[key(loc)] then
        locks[key(loc)] = nil;
        lockEvent("ITEM_LOCK_CHANGED", loc, sync);
        lockEvent("ITEM_UNLOCKED", loc, sync);
    end
end

local function isLocked(loc)
    return locks[key(loc)] == true;
end

function H.uiError(globalName)
    local msg = rawget(_G, globalName) or globalName;
    H.uiErrors[#H.uiErrors + 1] = {key = globalName, msg = msg, t = H.now};
    H.queueEvent("UI_ERROR_MESSAGE", 0, msg);
end

---------------------------------------------------------------------------
-- change notification
---------------------------------------------------------------------------
local changedSlots, changedBags = {}, {};

local function noteChange(loc)
    if loc.kind == "equip" then
        changedSlots[loc.slot] = true;
    else
        changedBags[loc.bag] = true;
    end
end

local function sortedKeys(t)
    local r = {};
    for k in pairs(t) do
        r[#r + 1] = k;
    end
    table.sort(r);
    return r;
end

local function emitChanges()
    local slots, bagIds = sortedKeys(changedSlots), sortedKeys(changedBags);
    changedSlots, changedBags = {}, {};
    for _, slot in ipairs(slots) do
        H.queueEvent("PLAYER_EQUIPMENT_CHANGED", slot, inv[slot] == nil);
    end
    if #slots > 0 then
        H.queueEvent("UNIT_INVENTORY_CHANGED", "player");
    end
    for _, bag in ipairs(bagIds) do
        H.queueEvent("BAG_UPDATE", bag);
    end
    if #bagIds > 0 then
        H.queueNextFrame("BAG_UPDATE_DELAYED");
    end
end

---------------------------------------------------------------------------
-- server requests
---------------------------------------------------------------------------
local function apply(op)
    for _, mv in ipairs(op.moves) do
        setAt(mv.loc, mv.inst);
        noteChange(mv.loc);
    end
    for _, loc in ipairs(op.locs) do
        unlock(loc);
    end
    emitChanges();
end

local function commit(op)
    if H.latency > 0 then
        for _, loc in ipairs(op.locs) do
            lock(loc);
        end
        op.dueMs = H.nowMs + math.floor(H.latency * 1000 + 0.5);
        pending[#pending + 1] = op;
    else
        apply(op);
    end
end

table.insert(H.frameHooks, function()
    while pending[1] and pending[1].dueMs <= H.nowMs do
        apply(table.remove(pending, 1));
    end
end);

function H.pendingRequests()
    return #pending;
end

---------------------------------------------------------------------------
-- rules
---------------------------------------------------------------------------
local function fits(inst, slot)
    local slots = H.EQUIP_SLOTS[inst.item.equipLoc];
    if not slots then
        return false;
    end
    for _, s in ipairs(slots) do
        if s == slot then
            if slot == 17 and inst.item.equipLoc == "INVTYPE_WEAPON" and not H.player.canDualWield then
                return false;
            end
            return true;
        end
    end
    return false;
end
H.fits = fits;

local function bagAccepts(bagId, inst)
    local bag = bags[bagId];
    if not bag then
        return false;
    end
    if bag.keyring then
        return inst.item.family == 256;
    elseif bag.reagent then
        return inst.item.reagent == true;
    elseif bag.family == 0 then
        return true;
    end
    return inst.item.family ~= nil and bit.band(inst.item.family, bag.family) ~= 0;
end

local function inCombatLockdown()
    return H.combat == true;
end

local function armorLockedOut(slot)
    return inCombatLockdown() and slot ~= 16 and slot ~= 17 and slot ~= 18;
end

-- First free, unlocked slot of the generic player bags (0..4). `extra` is a location about to become free.
local function firstFreeBagSlot(extra)
    if extra and extra.kind == "bag" and bags[extra.bag] and bags[extra.bag].family == 0 then
        return extra;
    end
    for _, bagId in ipairs(GENERIC_BAGS) do
        local bag = bags[bagId];
        if bag and bag.family == 0 then
            for slot = 1, bag.size do
                local loc = bagLoc(bagId, slot);
                if not bag.slots[slot] and not isLocked(loc) then
                    return loc;
                end
            end
        end
    end
end

-- Pick up (cursor empty). The item stays where it is, locked.
local function pickup(loc)
    local inst = getAt(loc);
    if not inst or isLocked(loc) then
        return false;
    end
    if loc.kind == "equip" and armorLockedOut(loc.slot) then
        H.uiError("ERR_NOT_IN_COMBAT");
        return false;
    end
    cursor = {inst = inst, from = loc};
    lock(loc, true);
    return true;
end

local function clearCursor()
    if cursor then
        local from = cursor.from;
        cursor = nil;
        unlock(from, true);
    end
end

-- Place the cursor item at dest (swap with the origin). Returns true when the request was sent.
local function place(dest)
    local src, item = cursor.from, cursor.inst;
    if same(src, dest) then
        clearCursor();
        return true;
    end
    if isLocked(dest) then
        H.uiError("ERR_OBJECT_IS_BUSY");
        return false;
    end
    local destItem = getAt(dest);
    if dest.kind == "equip" then
        if not fits(item, dest.slot) then
            H.uiError("ERR_WRONG_SLOT");
            return false;
        elseif armorLockedOut(dest.slot) then
            H.uiError("ERR_NOT_IN_COMBAT");
            return false;
        end
    elseif not bagAccepts(dest.bag, item) then
        H.uiError("ERR_ITEM_DOESNT_GO_INTO_BAG");
        return false;
    end
    if destItem then
        if src.kind == "equip" then
            if not fits(destItem, src.slot) then
                H.uiError("ERR_WRONG_SLOT");
                return false;
            end
        elseif not bagAccepts(src.bag, destItem) then
            H.uiError("ERR_ITEM_DOESNT_GO_INTO_BAG");
            return false;
        end
    end

    local function after(slot)
        if dest.kind == "equip" and dest.slot == slot then
            return item;
        elseif src.kind == "equip" and src.slot == slot then
            return destItem;
        end
        return inv[slot];
    end

    if dest.kind == "equip" and item.item.unique then
        for slot = 1, 19 do
            local other = after(slot);
            if slot ~= dest.slot and other and other.id == item.id then
                H.uiError("ERR_ITEM_UNIQUE_EQUIPPABLE");
                return false;
            end
        end
    end

    local moves = {{loc = dest, inst = item}, {loc = src, inst = destItem}};
    local locs = {src, dest};
    -- a two-hander and an off-hand cannot be worn together: the one not being placed goes to a free bag slot
    local mh, oh = after(16), after(17);
    if mh and oh and mh.item.equipLoc == "INVTYPE_2HWEAPON" then
        local displacedSlot = (dest.kind == "equip" and dest.slot == 16) and 17 or 16;
        local freeLoc = firstFreeBagSlot((src.kind == "bag" and not destItem) and src or nil);
        if not freeLoc then
            H.uiError("ERR_INV_FULL");
            return false;
        end
        local displaced = after(displacedSlot);
        if same(freeLoc, src) then
            moves[2] = {loc = src, inst = displaced};
        else
            moves[#moves + 1] = {loc = freeLoc, inst = displaced};
            locs[#locs + 1] = freeLoc;
        end
        moves[#moves + 1] = {loc = equipLoc(displacedSlot), inst = nil};
        locs[#locs + 1] = equipLoc(displacedSlot);
    end

    cursor = nil;
    commit({moves = moves, locs = locs});
    return true;
end

local function setAmmo(inst)
    H.ammo = inst and inst.id or nil;
    H.queueEvent("UNIT_INVENTORY_CHANGED", "player");
end

---------------------------------------------------------------------------
-- addon-facing API
---------------------------------------------------------------------------
-- With H.blockCombatPickups, item moves by addon code in combat are blocked like protected calls.
local function blocked(fname)
    if H.blockCombatPickups and inCombatLockdown() and not H.secureCall then
        H.blocked[#H.blocked + 1] = {fn = fname, t = H.now};
        H.fire("ADDON_ACTION_BLOCKED", H.addonName, fname .. "()");
        return true;
    end
    return false;
end

local function checkNumber(v, usage)
    if type(v) ~= "number" then
        error("Usage: " .. usage, 3);
    end
end

function PickupInventoryItem(slot)
    checkNumber(slot, "PickupInventoryItem(slot)");
    if blocked("PickupInventoryItem") then
        return;
    end
    if slot == 0 then
        if cursor then
            if cursor.inst.item.equipLoc == "INVTYPE_AMMO" then
                setAmmo(cursor.inst);
            end
            clearCursor();
        elseif H.ammo then
            setAmmo(nil);
        end
        return;
    end
    if slot < 1 or slot > 19 then
        return;
    end
    if cursor then
        place(equipLoc(slot));
    else
        pickup(equipLoc(slot));
    end
end

function EquipCursorItem(slot)
    checkNumber(slot, "EquipCursorItem(slot)");
    if blocked("EquipCursorItem") or not cursor then
        return;
    end
    if slot == 0 then
        if cursor.inst.item.equipLoc == "INVTYPE_AMMO" then
            setAmmo(cursor.inst);
            clearCursor();
        else
            H.uiError("ERR_WRONG_SLOT");
        end
        return;
    end
    place(equipLoc(slot));
end

local function autoSlot(inst)
    local slots = H.EQUIP_SLOTS[inst.item.equipLoc];
    if not slots then
        return nil;
    end
    for _, s in ipairs(slots) do
        if s ~= 0 and not inv[s] and fits(inst, s) then
            return s;
        end
    end
    return slots[1];
end

function AutoEquipCursorItem()
    if blocked("AutoEquipCursorItem") or not cursor then
        return;
    end
    local slot = autoSlot(cursor.inst);
    if slot == 0 then
        setAmmo(cursor.inst);
        clearCursor();
    elseif slot then
        place(equipLoc(slot));
    else
        H.uiError("ERR_ITEM_CANT_BE_EQUIPPED");
    end
end

local function putInBag(bagId, fname)
    if blocked(fname) or not cursor then
        return;
    end
    local bag = bags[bagId];
    if not bag or not accessible(bagId) then
        return;
    end
    if not bagAccepts(bagId, cursor.inst) then
        H.uiError("ERR_ITEM_DOESNT_GO_INTO_BAG");
        return;
    end
    if cursor.from.kind == "bag" and cursor.from.bag == bagId then
        clearCursor();
        return;
    end
    for slot = 1, bag.size do
        local loc = bagLoc(bagId, slot);
        if not bag.slots[slot] and not isLocked(loc) then
            place(loc);
            return;
        end
    end
    H.uiError("ERR_BAG_FULL");
end

function PutItemInBackpack()
    putInBag(0, "PutItemInBackpack");
end

function PutItemInBag(inventoryId)
    checkNumber(inventoryId, "PutItemInBag(inventorySlot)");
    local bagId = inventoryId - (CONTAINER_BAG_OFFSET or 30);
    if bagId < 1 or bagId > 5 then
        return;
    end
    putInBag(bagId, "PutItemInBag");
end

function ClearCursor()
    clearCursor();
end

function CursorHasItem()
    return cursor ~= nil;
end

function GetCursorInfo()
    if cursor then
        return "item", cursor.inst.id, H.itemLink(cursor.inst);
    end
end

function DeleteCursorItem()
    error("DeleteCursorItem is restricted (HasRestrictions)", 2);
end

function H.cursorItem()
    return cursor and cursor.inst;
end

-- C_Item.EquipItemByName(item, dstSlot): the client searches the bags, then the other equipped slots.
-- A full link/item string must match id and enchant; an id or a name matches any copy.
local function matches(inst, def, enchant, isLink)
    if inst.id ~= def.id then
        return false;
    end
    return not isLink or (inst.enchant or 0) == (enchant or 0);
end

C_Item.EquipItemByName = function(item, dstSlot)
    if item == nil then
        error("Usage: C_Item.EquipItemByName(itemInfo [, dstSlot])", 2);
    end
    if blocked("EquipItemByName") then
        return;
    end
    local def, enchant, isLink = H.parseItemArg(item);
    if not def or def.equipLoc == "" then
        return;
    end
    if def.equipLoc == "INVTYPE_AMMO" then
        if H.countItem(def.key) > 0 then
            setAmmo({id = def.id});
        end
        return;
    end
    local candidates = {};
    for _, bagId in ipairs(GENERIC_BAGS) do
        local bag = bags[bagId];
        if bag then
            for slot = 1, bag.size do
                local inst = bag.slots[slot];
                if inst and matches(inst, def, enchant, isLink) then
                    candidates[#candidates + 1] = bagLoc(bagId, slot);
                end
            end
        end
    end
    for slot = 1, 19 do
        if slot ~= dstSlot and inv[slot] and matches(inv[slot], def, enchant, isLink) then
            candidates[#candidates + 1] = equipLoc(slot);
        end
    end
    if dstSlot and inv[dstSlot] and matches(inv[dstSlot], def, enchant, isLink) then
        return; -- already there
    end
    clearCursor();
    for _, loc in ipairs(candidates) do
        if not isLocked(loc) then
            if pickup(loc) then
                local slot = dstSlot or autoSlot(cursor.inst);
                if not slot or not place(equipLoc(slot)) then
                    clearCursor();
                end
            end
            return;
        end
    end
end

---------------------------------------------------------------------------
-- C_Container / C_Bank / inventory reads
---------------------------------------------------------------------------
local function containerInfo(bagId, slot)
    if not accessible(bagId) then
        return nil;
    end
    local inst = bags[bagId].slots[slot];
    if not inst then
        return nil;
    end
    local def = inst.item;
    return {iconFileID = def.icon, stackCount = inst.count, isLocked = isLocked(bagLoc(bagId, slot)),
        quality = def.quality, isReadable = false, hasLoot = false, hyperlink = H.itemLink(inst), isFiltered = false,
        hasNoValue = false, itemID = def.id, isBound = true, itemName = def.name};
end

local function useContainerItem(bagId, slot)
    if blocked("UseContainerItem") or not accessible(bagId) then
        return;
    end
    local inst = bags[bagId].slots[slot];
    if not inst then
        return;
    end
    if H.merchant.open then
        bags[bagId].slots[slot] = nil; -- sold!
        H.sold[#H.sold + 1] = inst;
        noteChange(bagLoc(bagId, slot));
        emitChanges();
    elseif inst.item.equipLoc ~= "" and not H.bank.open then
        clearCursor();
        if pickup(bagLoc(bagId, slot)) then
            local s = autoSlot(inst);
            if not s or not place(equipLoc(s)) then
                clearCursor();
            end
        end
    end
end

C_Container = {
    GetContainerNumSlots = function(bagId)
        return accessible(bagId) and bags[bagId].size or 0;
    end,
    GetContainerNumFreeSlots = function(bagId)
        if not accessible(bagId) then
            return 0, 0;
        end
        local bag, free = bags[bagId], 0;
        for slot = 1, bag.size do
            if not bag.slots[slot] then
                free = free + 1;
            end
        end
        return free, bag.family;
    end,
    GetContainerFreeSlots = function(bagId)
        local list = {};
        if accessible(bagId) then
            local bag = bags[bagId];
            for slot = 1, bag.size do
                if not bag.slots[slot] then
                    list[#list + 1] = slot;
                end
            end
        end
        return list;
    end,
    GetContainerItemInfo = containerInfo,
    GetContainerItemLink = function(bagId, slot)
        local info = containerInfo(bagId, slot);
        return info and info.hyperlink;
    end,
    GetContainerItemID = function(bagId, slot)
        local info = containerInfo(bagId, slot);
        return info and info.itemID;
    end,
    PickupContainerItem = function(bagId, slot)
        if type(bagId) ~= "number" or type(slot) ~= "number" then
            error("Usage: C_Container.PickupContainerItem(containerIndex, slotIndex)", 2);
        end
        if blocked("PickupContainerItem") or not accessible(bagId) or slot < 1 or slot > bags[bagId].size then
            return;
        end
        if cursor then
            place(bagLoc(bagId, slot));
        else
            pickup(bagLoc(bagId, slot));
        end
    end,
    UseContainerItem = useContainerItem,
    ContainerIDToInventoryID = function(bagId)
        if type(bagId) == "number" and bagId >= 1 and bagId <= 5 then
            return bagId + (CONTAINER_BAG_OFFSET or 30);
        end
    end,
    GetBagName = function(bagId)
        local bag = bags[bagId];
        return bag and (bag.bagItem and bag.bagItem.item.name or "Backpack");
    end,
    GetContainerItemEquipmentSetInfo = function()
        return false, "";
    end,
    IsContainerFiltered = function()
        return false;
    end,
    GetItemCooldown = function()
        return 0, 0, 0;
    end,
};

C_Bank = {
    FetchPurchasedBankTabIDs = function(bankType)
        local ids = {};
        if bankType == Enum.BankType.Character then
            for i, id in ipairs(H.bank.tabs) do
                ids[i] = id;
            end
        end
        return ids;
    end,
    FetchNumPurchasedBankTabs = function(bankType)
        return bankType == Enum.BankType.Character and #H.bank.tabs or 0;
    end,
    CanUseBank = function(bankType)
        return H.bank.open and bankType == Enum.BankType.Character;
    end,
    CanViewBank = function(bankType)
        return H.bank.open and bankType == Enum.BankType.Character;
    end,
    AreAnyBankTypesViewable = function()
        return H.bank.open;
    end,
};

local function playerSlotItem(unit, slot)
    if unit ~= "player" or type(slot) ~= "number" then
        return nil;
    end
    if slot >= 1 and slot <= 19 then
        return inv[slot];
    end
    local bag = bags[slot - (CONTAINER_BAG_OFFSET or 30)];
    if slot > 30 and bag then
        return bag.bagItem;
    end
end

function GetInventoryItemID(unit, slot)
    if unit == "player" and slot == 0 then
        return H.ammo;
    end
    local inst = playerSlotItem(unit, slot);
    return inst and inst.id;
end

function GetInventoryItemLink(unit, slot)
    if unit == "player" and slot == 0 and H.ammo then
        return H.itemLink({item = H.itemsById[H.ammo], id = H.ammo});
    end
    local inst = playerSlotItem(unit, slot);
    return inst and H.itemLink(inst);
end

function GetInventoryItemTexture(unit, slot)
    local id = GetInventoryItemID(unit, slot);
    return id and H.itemsById[id].icon;
end

function GetInventoryItemQuality(unit, slot)
    local id = GetInventoryItemID(unit, slot);
    return id and H.itemsById[id].quality;
end

function GetInventoryItemCount(unit, slot)
    if slot == 0 and H.ammo then
        return H.countItem(H.itemsById[H.ammo].key);
    end
    return GetInventoryItemID(unit, slot) and 1 or 0;
end

function GetInventoryItemDurability(slot)
    if inv[slot] then
        return 50, 50;
    end
end

function IsInventoryItemLocked(slot)
    return isLocked(equipLoc(slot));
end

---------------------------------------------------------------------------
-- bank and merchant
---------------------------------------------------------------------------
function H.openBank()
    H.bank.open = true;
    H.fire("BANKFRAME_OPENED");
    if BankFrame then
        BankFrame:Show();
    end
end

function H.closeBank()
    clearCursor();
    H.fire("BANKFRAME_CLOSED");
    H.bank.open = false;
    if BankFrame then
        BankFrame:Hide();
    end
end

function H.openMerchant()
    H.merchant.open = true;
    H.fire("MERCHANT_SHOW");
end

function CloseMerchant()
    if H.merchant.open then
        H.merchant.open = false;
        H.fire("MERCHANT_CLOSED");
    end
end

---------------------------------------------------------------------------
-- setup and inspection helpers for scenarios
---------------------------------------------------------------------------
-- cfg: {backpack = 16, bags = {"bag16", "bag16", "quiver", "bag16"}, reagentBag = true, keyring = 12,
--       bankTabs = {98, 98}}
function H.setupBags(cfg)
    cfg = cfg or {};
    for k in pairs(bags) do
        bags[k] = nil;
    end
    bags[0] = {id = 0, size = cfg.backpack or 16, family = 0, slots = {}};
    local list = cfg.bags or {"bag16", "bag16", "quiver", "bag16"};
    for i = 1, 4 do
        local itemKey = list[i];
        if itemKey then
            local bagItem = H.newItem(itemKey);
            bags[i] = {id = i, size = bagItem.item.bagSize, family = bagItem.item.bagFamily, slots = {},
                bagItem = bagItem};
        end
    end
    if cfg.reagentBag ~= false then
        local bagItem = H.newItem("reagentBag");
        bags[5] = {id = 5, size = bagItem.item.bagSize, family = bagItem.item.bagFamily, slots = {},
            bagItem = bagItem, reagent = true};
    end
    bags[-1] = {id = -1, size = cfg.keyring or 12, family = 256, slots = {}, keyring = true};
    H.bank.tabs = {};
    for i, size in ipairs(cfg.bankTabs or {98, 98}) do
        local id = 5 + i; -- Enum.BagIndex.CharacterBankTab_1 = 6
        bags[id] = {id = id, size = size, family = 0, slots = {}, bank = true};
        H.bank.tabs[i] = id;
    end
end

local function resolveInst(itemOrKey, opts)
    if type(itemOrKey) == "table" then
        return itemOrKey;
    end
    return H.newItem(itemOrKey, opts);
end

-- Puts an item into a bag (first free slot accepting it, or opts.bag / opts.slot). Returns the instance.
function H.give(itemOrKey, opts)
    opts = opts or {};
    local inst = resolveInst(itemOrKey, opts);
    local order = opts.bag and {opts.bag} or {0, 1, 2, 3, 4};
    for _, bagId in ipairs(order) do
        local bag = bags[bagId];
        if bag and (opts.bag or bagAccepts(bagId, inst)) then
            for slot = (opts.slot or 1), (opts.slot or bag.size) do
                if not bag.slots[slot] then
                    bag.slots[slot] = inst;
                    noteChange(bagLoc(bagId, slot));
                    emitChanges();
                    return inst;
                end
            end
        end
    end
    error("harness: no room to give " .. tostring(inst.key), 2);
end

-- Puts an item straight into an equipment slot (setup only, no rules). Returns the instance.
function H.equip(itemOrKey, slot, opts)
    local inst = resolveInst(itemOrKey, opts);
    if slot == 0 then
        H.ammo = inst.id;
        return inst;
    end
    if not fits(inst, slot) then
        error("harness: " .. inst.key .. " does not fit slot " .. slot, 2);
    end
    inv[slot] = inst;
    noteChange(equipLoc(slot));
    emitChanges();
    return inst;
end

-- The player drags an item from wherever it is onto an equipment slot (secure, like the character sheet).
function H.playerEquip(itemKeyOrInst, slot)
    local list = H.find(itemKeyOrInst);
    local loc = list[1];
    for _, l in ipairs(list) do
        if l.kind == "bag" and not bags[l.bag].bank then
            loc = l;
            break;
        end
    end
    if not loc then
        error("harness: item not found: " .. tostring(itemKeyOrInst), 2);
    end
    H.secureCall = true;
    clearCursor();
    local ok = pickup(loc) and place(equipLoc(slot));
    if not ok then
        clearCursor();
    end
    H.secureCall = false;
    if ok and H.latency > 0 then
        H.advance(H.latency + 0.05); -- a player waits for the item to arrive before the next drag
    end
    return ok;
end

-- Fills every free slot of the generic bags with junk. Returns the number of items added.
function H.fillBags(itemKey)
    local n = 0;
    for _, bagId in ipairs(GENERIC_BAGS) do
        local bag = bags[bagId];
        if bag and bag.family == 0 then
            for slot = 1, bag.size do
                if not bag.slots[slot] then
                    bag.slots[slot] = H.newItem(itemKey or "junk");
                    noteChange(bagLoc(bagId, slot));
                    n = n + 1;
                end
            end
        end
    end
    emitChanges();
    return n;
end

-- Removes one junk item from the first generic bag slot holding it (frees space).
function H.removeFromBags(itemKey)
    for _, bagId in ipairs(GENERIC_BAGS) do
        local bag = bags[bagId];
        if bag then
            for slot = 1, bag.size do
                local inst = bag.slots[slot];
                if inst and inst.key == itemKey then
                    bag.slots[slot] = nil;
                    noteChange(bagLoc(bagId, slot));
                    emitChanges();
                    return true;
                end
            end
        end
    end
    return false;
end

function H.freeGenericSlots()
    local n = 0;
    for _, bagId in ipairs(GENERIC_BAGS) do
        local bag = bags[bagId];
        if bag and bag.family == 0 then
            for slot = 1, bag.size do
                if not bag.slots[slot] then
                    n = n + 1;
                end
            end
        end
    end
    return n;
end

-- All locations of an item (key or instance): equipment first, then bags (incl. bank tabs, keyring, reagent bag).
function H.find(itemKeyOrInst)
    local list = {};
    local function match(inst)
        if type(itemKeyOrInst) == "table" then
            return inst == itemKeyOrInst;
        end
        return inst.key == itemKeyOrInst;
    end
    for slot = 1, 19 do
        if inv[slot] and match(inv[slot]) then
            list[#list + 1] = equipLoc(slot);
        end
    end
    for _, bagId in ipairs(sortedKeys(bags)) do
        for slot = 1, bags[bagId].size do
            local inst = bags[bagId].slots[slot];
            if inst and match(inst) then
                list[#list + 1] = bagLoc(bagId, slot);
            end
        end
    end
    return list;
end

function H.countItem(itemKey, excludeBank)
    local n = 0;
    for _, loc in ipairs(H.find(itemKey)) do
        if loc.kind == "equip" or not excludeBank or not bags[loc.bag].bank then
            n = n + 1;
        end
    end
    return n;
end

-- Total number of physical items the character owns (equipment + every container). Swaps must keep it constant.
function H.totalItems()
    local n = 0;
    for slot = 1, 19 do
        if inv[slot] then
            n = n + 1;
        end
    end
    for _, bag in pairs(bags) do
        for slot = 1, bag.size do
            if bag.slots[slot] then
                n = n + 1;
            end
        end
    end
    return n;
end

function H.dumpInventory()
    local lines = {};
    for slot = 0, 19 do
        local inst = slot == 0 and (H.ammo and {key = H.itemsById[H.ammo].key}) or inv[slot];
        lines[#lines + 1] = string.format("  slot %2d: %s%s", slot, inst and inst.key or "-",
            (slot > 0 and isLocked(equipLoc(slot))) and " (locked)" or "");
    end
    for _, bagId in ipairs(sortedKeys(bags)) do
        local bag, items = bags[bagId], {};
        for slot = 1, bag.size do
            if bag.slots[slot] then
                items[#items + 1] = slot .. "=" .. bag.slots[slot].key;
            end
        end
        lines[#lines + 1] = string.format("  bag %2d (family %d, %d slots): %s", bagId, bag.family, bag.size,
            #items > 0 and table.concat(items, " ") or "empty");
    end
    if cursor then
        lines[#lines + 1] = "  cursor: " .. cursor.inst.key .. " from " .. describeLoc(cursor.from);
    end
    return table.concat(lines, "\n");
end
