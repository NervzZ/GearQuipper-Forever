-- items.lua: fake item database, item instances, Forever-format links, C_Item (except EquipItemByName).
-- Link format (Mainline, as seen in Forever SavedVariables):
--   |cffa335ee|Hitem:ID:ENCH:::::::LEVEL:SPECID::1:::::::|h[Name]|h|r
-- linkLevel and specID come from the player NOW, so a spec swap or level-up changes every link (like the client).
local H = ...;

H.items = {};      -- key -> definition
H.itemsById = {};
H.itemsByName = {};
H.uncached = {};   -- itemID -> true: C_Item.GetItemInfo returns nothing until the data "arrives"

local QUALITY_HEX = {[0] = "ff9d9d9d", [1] = "ffffffff", [2] = "ff1eff00", [3] = "ff0070dd", [4] = "ffa335ee",
    [5] = "ffff8000", [6] = "ffe6cc80", [7] = "ff00ccff"};
H.QUALITY_HEX = QUALITY_HEX;

-- equipLoc -> inventory slots it may occupy (17 for INVTYPE_WEAPON needs dual wield)
H.EQUIP_SLOTS = {
    INVTYPE_HEAD = {1}, INVTYPE_NECK = {2}, INVTYPE_SHOULDER = {3}, INVTYPE_BODY = {4}, INVTYPE_CHEST = {5},
    INVTYPE_ROBE = {5}, INVTYPE_WAIST = {6}, INVTYPE_LEGS = {7}, INVTYPE_FEET = {8}, INVTYPE_WRIST = {9},
    INVTYPE_HAND = {10}, INVTYPE_FINGER = {11, 12}, INVTYPE_TRINKET = {13, 14}, INVTYPE_CLOAK = {15},
    INVTYPE_WEAPON = {16, 17}, INVTYPE_2HWEAPON = {16}, INVTYPE_WEAPONMAINHAND = {16},
    INVTYPE_WEAPONOFFHAND = {17}, INVTYPE_SHIELD = {17}, INVTYPE_HOLDABLE = {17}, INVTYPE_RANGED = {18},
    INVTYPE_RANGEDRIGHT = {18}, INVTYPE_THROWN = {18}, INVTYPE_RELIC = {18}, INVTYPE_TABARD = {19},
    INVTYPE_AMMO = {0},
};

local INVENTORY_TYPE = {
    [""] = 0, INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_BODY = 4, INVTYPE_CHEST = 5,
    INVTYPE_WAIST = 6, INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WRIST = 9, INVTYPE_HAND = 10, INVTYPE_FINGER = 11,
    INVTYPE_TRINKET = 12, INVTYPE_WEAPON = 13, INVTYPE_SHIELD = 14, INVTYPE_RANGED = 15, INVTYPE_CLOAK = 16,
    INVTYPE_2HWEAPON = 17, INVTYPE_BAG = 18, INVTYPE_TABARD = 19, INVTYPE_ROBE = 20, INVTYPE_WEAPONMAINHAND = 21,
    INVTYPE_WEAPONOFFHAND = 22, INVTYPE_HOLDABLE = 23, INVTYPE_AMMO = 24, INVTYPE_THROWN = 25,
    INVTYPE_RANGEDRIGHT = 26, INVTYPE_QUIVER = 27, INVTYPE_RELIC = 28,
};

local CLASS_OF = { -- equipLoc -> itemType, subType, classID, subclassID
    INVTYPE_WEAPON = {"Weapon", "One-Handed Swords", 2, 7}, INVTYPE_2HWEAPON = {"Weapon", "Two-Handed Swords", 2, 8},
    INVTYPE_WEAPONMAINHAND = {"Weapon", "One-Handed Maces", 2, 4}, INVTYPE_WEAPONOFFHAND = {"Weapon", "Daggers", 2, 15},
    INVTYPE_RANGED = {"Weapon", "Bows", 2, 2}, INVTYPE_RANGEDRIGHT = {"Weapon", "Guns", 2, 3},
    INVTYPE_THROWN = {"Weapon", "Thrown", 2, 16}, INVTYPE_SHIELD = {"Armor", "Shields", 4, 6},
    INVTYPE_AMMO = {"Projectile", "Arrow", 6, 2}, INVTYPE_BAG = {"Container", "Bag", 1, 0},
    INVTYPE_QUIVER = {"Quiver", "Quiver", 11, 2},
};

local nextAutoId = 90001;

-- Defines an item. def: key, name, equipLoc ("" = not equippable), quality, plus optional
-- id, icon, stack, family (bag family bits it belongs to: 1 arrows, 256 keys), bagSize/bagFamily (for bags),
-- unique (unique-equipped), reagent (fits the reagent bag).
function H.defineItem(def)
    def.id = def.id or nextAutoId;
    nextAutoId = math.max(nextAutoId, def.id) + 1;
    def.equipLoc = def.equipLoc or "";
    def.quality = def.quality or 1;
    def.icon = def.icon or (130000 + def.id % 1000);
    def.stack = def.stack or 1;
    def.level = def.level or 60;
    local c = CLASS_OF[def.equipLoc] or (def.equipLoc ~= "" and {"Armor", "Plate", 4, 4}) or {"Trade Goods", "Cloth", 7, 5};
    def.itemType, def.subType, def.classID, def.subclassID = def.itemType or c[1], def.subType or c[2], c[3], c[4];
    H.items[def.key] = def;
    H.itemsById[def.id] = def;
    H.itemsByName[def.name] = def;
    return def;
end

local nextUid = 0;
-- A physical item. Identical copies are separate instances with identical links (uniqueID is empty on Forever).
function H.newItem(key, opts)
    local def = H.items[key];
    if not def then
        error("harness: unknown item key " .. tostring(key), 2);
    end
    nextUid = nextUid + 1;
    opts = opts or {};
    return {item = def, id = def.id, key = key, enchant = opts.enchant, count = opts.count or 1, uid = nextUid};
end

function H.specId()
    local ids = H.player.specIds;
    return ids[H.player.specGroup] or ids[1];
end

function H.itemString(inst)
    -- field 14 = numBonusIDs followed by the bonus ids (def.bonus), empty when the item has none
    local bonus = inst.item.bonus;
    local bonusPart = (bonus and #bonus > 0) and (#bonus .. ":" .. table.concat(bonus, ":")) or "";
    return string.format("item:%d:%s:::::::%d:%d::1:%s::::::", inst.id, inst.enchant and tostring(inst.enchant) or "",
        H.player.level, H.specId(), bonusPart);
end

function H.itemLink(inst)
    local def = inst.item;
    return "|c" .. QUALITY_HEX[def.quality] .. "|H" .. H.itemString(inst) .. "|h[" .. def.name .. "]|h|r";
end

-- Resolves an item argument (id, "item:..." string, link, or name) -> definition, enchant (nil = any/none given).
function H.parseItemArg(item)
    if type(item) == "number" then
        return H.itemsById[item], nil, false;
    elseif type(item) == "string" then
        local id, enchant = item:match("item:(%-?%d+):?(%-?%d*)");
        if id then
            return H.itemsById[tonumber(id)], tonumber(enchant), true;
        end
        return H.itemsByName[item], nil, false;
    end
    return nil;
end

local function loadLater(id)
    if H.uncached[id] and not H.uncached[id .. ":loading"] then
        H.uncached[id .. ":loading"] = true;
        C_Timer.After(0.2, function()
            H.uncached[id], H.uncached[id .. ":loading"] = nil, nil;
            H.queueEvent("GET_ITEM_INFO_RECEIVED", id, true);
            H.queueEvent("ITEM_DATA_LOAD_RESULT", id, true);
        end);
    end
end

local function itemInfo(item)
    local def, enchant, isLink = H.parseItemArg(item);
    if not def then
        return nil;
    end
    if H.uncached[def.id] then
        loadLater(def.id);
        return nil;
    end
    local link = H.itemLink({item = def, id = def.id, enchant = isLink and enchant or nil});
    return def.name, link, def.quality, def.level, def.reqLevel or 1, def.itemType, def.subType, def.stack,
        def.equipLoc, def.icon, 100, def.classID, def.subclassID, def.bind or 0, 0, nil, def.reagent or false;
end

local function qualityColor(q)
    local hex = QUALITY_HEX[q];
    if not hex then
        return 1, 1, 1, "ffffffff";
    end
    local r, g, b = tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16), tonumber(hex:sub(7, 8), 16);
    return r / 255, g / 255, b / 255, hex;
end

C_Item = {
    GetItemInfo = itemInfo,
    GetItemInfoInstant = function(item)
        local def = H.parseItemArg(item);
        if not def then
            return nil;
        end
        return def.id, def.itemType, def.subType, def.equipLoc, def.icon, def.classID, def.subclassID;
    end,
    GetItemQualityColor = qualityColor,
    GetItemNameByID = function(id)
        local def = H.itemsById[id];
        if def and not H.uncached[id] then
            return def.name;
        end
        loadLater(id);
    end,
    GetItemIconByID = function(id)
        local def = H.itemsById[id];
        return def and def.icon;
    end,
    GetItemQualityByID = function(id)
        local def = H.itemsById[id];
        return def and def.quality;
    end,
    GetItemIDForItemInfo = function(item)
        local def = H.parseItemArg(item);
        return def and def.id;
    end,
    DoesItemExistByID = function(id)
        return H.itemsById[id] ~= nil;
    end,
    IsItemDataCachedByID = function(id)
        return H.itemsById[id] ~= nil and not H.uncached[id];
    end,
    RequestLoadItemDataByID = function(id)
        if type(id) ~= "number" then
            error("Usage: C_Item.RequestLoadItemDataByID(itemID)", 2);
        end
        if H.uncached[id] then
            loadLater(id);
        elseif H.itemsById[id] then
            H.queueEvent("ITEM_DATA_LOAD_RESULT", id, true);
        end
    end,
    IsEquippableItem = function(item)
        local def = H.parseItemArg(item);
        return def ~= nil and def.equipLoc ~= "";
    end,
    GetItemInventoryTypeByID = function(item)
        local def = H.parseItemArg(item);
        return def and INVENTORY_TYPE[def.equipLoc];
    end,
    GetItemFamily = function(item)
        local def = H.parseItemArg(item);
        return def and (def.family or def.bagFamily or 0);
    end,
    GetItemMaxStackSizeByID = function(id)
        local def = H.itemsById[id];
        return def and def.stack;
    end,
    GetItemCount = function(item, includeBank)
        local def = H.parseItemArg(item);
        return def and H.countItem(def.key, not includeBank) or 0;
    end,
    IsEquippedItem = function(item)
        local def = H.parseItemArg(item);
        if not def then
            return false;
        end
        for slot = 1, 19 do
            local inst = H.inv[slot];
            if inst and inst.id == def.id then
                return true;
            end
        end
        return false;
    end,
    GetItemSpell = function()
        return nil;
    end,
    -- C_Item.EquipItemByName is defined in inventory.lua
};

---------------------------------------------------------------------------
-- default database: two armour sets, weapons for every hand combination, ammo, bags and junk
---------------------------------------------------------------------------
local function armor(key, name, loc, quality, extra)
    local def = {key = key, name = name, equipLoc = loc, quality = quality or 3};
    for k, v in pairs(extra or {}) do
        def[k] = v;
    end
    return H.defineItem(def);
end

-- set A ("Tank")
armor("headA", "Helm of the Bastion", "INVTYPE_HEAD", 4);
armor("neckA", "Bastion Choker", "INVTYPE_NECK");
armor("shoulderA", "Bastion Pauldrons", "INVTYPE_SHOULDER");
armor("chestA", "Bastion Breastplate", "INVTYPE_CHEST", 4);
armor("waistA", "Bastion Girdle", "INVTYPE_WAIST");
armor("legsA", "Bastion Legplates", "INVTYPE_LEGS");
armor("feetA", "Bastion Sabatons", "INVTYPE_FEET");
armor("wristA", "Bastion Bracers", "INVTYPE_WRIST");
armor("handsA", "Bastion Gauntlets", "INVTYPE_HAND");
armor("backA", "Bastion Cloak", "INVTYPE_CLOAK");
armor("ringA", "Band of Stone", "INVTYPE_FINGER");
armor("ringB", "Band of Iron", "INVTYPE_FINGER");
armor("trinketA", "Stone Idol", "INVTYPE_TRINKET");
armor("trinketB", "Iron Idol", "INVTYPE_TRINKET");
-- set B ("DPS")
armor("headB", "Helm of Fury", "INVTYPE_HEAD", 4);
armor("chestB", "Robe of Fury", "INVTYPE_ROBE", 4);
armor("legsB", "Legguards of Fury", "INVTYPE_LEGS");
armor("feetB", "Boots of Fury", "INVTYPE_FEET");
armor("handsB", "Gloves of Fury", "INVTYPE_HAND");
armor("backB", "Cape of Fury", "INVTYPE_CLOAK");
armor("ringC", "Band of Fury", "INVTYPE_FINGER", 3, {bonus = {6623, 1700}}); -- link carries bonus ids
armor("twinRing", "Signet of Twins", "INVTYPE_FINGER"); -- two identical copies exist in tests
armor("uniqueRing", "Unique Signet", "INVTYPE_FINGER", 4, {unique = true});
armor("trinketC", "Fury Idol", "INVTYPE_TRINKET");
-- always worn
armor("shirt", "Fine White Shirt", "INVTYPE_BODY", 1);
armor("tabard", "Tabard of the Test", "INVTYPE_TABARD", 1);
-- weapons
armor("sword", "Blade of Testing", "INVTYPE_WEAPON", 3);
armor("mace", "Mace of Testing", "INVTYPE_WEAPON", 3);
armor("twinBlade", "Twin Blade", "INVTYPE_WEAPON", 3); -- two identical copies exist in tests
armor("mainhand", "Main-Hand Hammer", "INVTYPE_WEAPONMAINHAND", 3);
armor("offhandBlade", "Off-Hand Dirk", "INVTYPE_WEAPONOFFHAND", 3);
armor("shield", "Wall of Testing", "INVTYPE_SHIELD", 3);
armor("orb", "Orb of Testing", "INVTYPE_HOLDABLE", 3);
armor("greatsword", "Greatsword of Testing", "INVTYPE_2HWEAPON", 4);
armor("bow", "Bow of Testing", "INVTYPE_RANGED", 3);
armor("gun", "Gun of Testing", "INVTYPE_RANGEDRIGHT", 3);
armor("thrown", "Throwing Knives", "INVTYPE_THROWN", 2);
-- ammo, bags, misc
H.defineItem({key = "arrows", name = "Jagged Arrow", equipLoc = "INVTYPE_AMMO", quality = 1, stack = 200, family = 1});
H.defineItem({key = "bullets", name = "Heavy Shot", equipLoc = "INVTYPE_AMMO", quality = 1, stack = 200, family = 2});
H.defineItem({key = "bag16", name = "Traveler's Backpack", equipLoc = "INVTYPE_BAG", quality = 1, bagSize = 16,
    bagFamily = 0});
H.defineItem({key = "quiver", name = "Light Quiver", equipLoc = "INVTYPE_QUIVER", quality = 1, bagSize = 16,
    bagFamily = 1});
H.defineItem({key = "reagentBag", name = "Reagent Satchel", equipLoc = "INVTYPE_BAG", quality = 1, bagSize = 16,
    bagFamily = 2048});
H.defineItem({key = "linen", name = "Linen Cloth", quality = 1, stack = 20, reagent = true});
H.defineItem({key = "junk", name = "Broken Fang", quality = 0, stack = 1});
H.defineItem({key = "key", name = "Test Key", quality = 1, family = 256, itemType = "Key", subType = "Key"});
