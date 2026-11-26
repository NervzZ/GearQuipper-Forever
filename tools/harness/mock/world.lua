-- world.lua: the player and other units, combat lockdown, secret values, spec groups, casting, shapeshift forms,
-- zones/maps/instances, spells, add-on metadata, and the scenario helpers that change them (firing the events the
-- client fires).
local H = ...;

H.player = {
    name = "Testchar", realm = "Testrealm", class = "WARRIOR", className = "Warrior", classId = 1,
    race = "Human", level = 60, faction = "Alliance", specGroup = 1, numSpecGroups = 2,
    specIds = {1482, 1483}, -- spec id written into item links, per spec group
    afk = false, dnd = false, pvp = false, dead = false, mounted = false, taxi = false, stealthed = false,
    swimming = false, inGroup = false, inRaid = false, casting = nil, form = 0, canDualWield = true,
    ammoNeeded = true, showHelm = true, showCloak = true,
};
H.combat = false;          -- InCombatLockdown()
H.affectingCombat = false; -- UnitAffectingCombat("player")
H.restricted = false;      -- an addon restriction (PvP match / instance) is active: some APIs return secrets
H.strictSecrets = true;    -- a secret handed to addon code outside the compat layer is recorded as an error
H.secretReads = {};        -- {api, where}
H.nameplates = {};
H.modifiers = {shift = false, ctrl = false, alt = false};
H.latencyHome, H.latencyWorld = 50, 60;

---------------------------------------------------------------------------
-- secret values
---------------------------------------------------------------------------
-- Stock Lua 5.1 cannot trap boolean tests or ==/~= against a non-secret; those are covered by the
-- "secret escaped" check below (H.strictSecrets). type() returns "userdata" here ("boolean" in game).
local SECRET = newproxy(true);
do
    local mt = getmetatable(SECRET);
    local function boom(what)
        return function()
            error("attempt to " .. what .. " a secret value", 2);
        end
    end
    mt.__index, mt.__newindex, mt.__call = boom("index"), boom("index"), boom("call");
    mt.__eq, mt.__lt, mt.__le = boom("compare"), boom("compare"), boom("compare");
    mt.__concat, mt.__len, mt.__unm = boom("concatenate"), boom("get the length of"), boom("perform arithmetic on");
    mt.__add, mt.__sub, mt.__mul, mt.__div, mt.__mod, mt.__pow = boom("perform arithmetic on"),
        boom("perform arithmetic on"), boom("perform arithmetic on"), boom("perform arithmetic on"),
        boom("perform arithmetic on"), boom("perform arithmetic on");
    mt.__tostring = function()
        return "<secret>";
    end
end
H.SECRET = SECRET;

function issecretvalue(v)
    return rawequal(v, SECRET);
end
function canaccessvalue(v)
    return not rawequal(v, SECRET);
end
function issecrettable()
    return false;
end
function canaccesstable()
    return true;
end
function scrubsecretvalues(...)
    local t = H.pack(...);
    for i = 1, t.n do
        if rawequal(t[i], SECRET) then
            t[i] = nil;
        end
    end
    return unpack(t, 1, t.n);
end

-- Returns the secret and checks who receives it: only the compat layer may touch unit state directly.
local function secret(api)
    local where, compat = "?", false;
    for level = 3, 12 do
        local info = H.getinfo(level, "Sl");
        if not info then
            break;
        end
        if info.what ~= "C" then
            where = info.short_src .. ":" .. (info.currentline or 0);
            compat = info.source:find("gearquipper%-compatibility%.lua$") ~= nil;
            break;
        end
    end
    H.secretReads[#H.secretReads + 1] = {api = api, where = where};
    if H.strictSecrets and not compat and where:find(H.addonDir or "\0", 1, true) then
        H.recordError("secret value", {msg = "[secret-escape check] " .. api .. " returned a secret to " .. where ..
            " outside c:ReadState/c:SafeCall (in game, testing or comparing it errors)", trace = ""});
    end
    return SECRET;
end

---------------------------------------------------------------------------
-- units
---------------------------------------------------------------------------
local function isPlayer(unit)
    return unit == "player";
end

function UnitName(unit)
    if isPlayer(unit) then
        return H.player.name, nil;
    end
    if H.nameplates[unit] or unit == "target" or unit == "mouseover" then
        if H.restricted then
            return secret("UnitName"), nil;
        end
        return "Enemy Player", nil;
    end
end
function UnitExists(unit)
    return isPlayer(unit) or H.nameplates[unit] == true;
end
function UnitIsUnit(a, b)
    return a == b;
end
function UnitGUID(unit)
    return isPlayer(unit) and "Player-4395-0ABCDEF0" or nil;
end
function UnitClass(unit)
    if isPlayer(unit) then
        return H.player.className, H.player.class, H.player.classId;
    end
end
function UnitRace(unit)
    if isPlayer(unit) then
        return H.player.race, H.player.race, 1;
    end
end
function UnitLevel(unit)
    return isPlayer(unit) and H.player.level or 1;
end
function UnitFactionGroup(unit)
    return H.player.faction, H.player.faction;
end
function UnitIsAFK(unit)
    if H.restricted then
        return secret("UnitIsAFK");
    end
    return isPlayer(unit) and H.player.afk or false;
end
function UnitIsDND(unit)
    if H.restricted then
        return secret("UnitIsDND");
    end
    return isPlayer(unit) and H.player.dnd or false;
end
function UnitIsPVP(unit)
    if isPlayer(unit) then
        return H.player.pvp;
    end
    if H.restricted then
        return secret("UnitIsPVP");
    end
    return false;
end
function UnitIsDeadOrGhost(unit)
    return isPlayer(unit) and H.player.dead or false;
end
function UnitAffectingCombat(unit)
    return isPlayer(unit) and H.affectingCombat or false;
end
function UnitOnTaxi(unit)
    return isPlayer(unit) and H.player.taxi or false;
end
function UnitInBattleground(unit)
    return (isPlayer(unit) and H.zone.bg) and 1 or nil;
end
function CanDualWield()
    return H.player.canDualWield;
end
function IsDualWielding()
    local oh = H.inv[17];
    return oh ~= nil and (oh.item.equipLoc == "INVTYPE_WEAPON" or oh.item.equipLoc == "INVTYPE_WEAPONOFFHAND");
end
function UnitHealth()
    return 100;
end
function UnitHealthMax()
    return 100;
end
function UnitCastingInfo(unit)
    local c = isPlayer(unit) and H.player.casting;
    if c then
        return c.name, c.name, c.icon, c.startMs, c.endMs, false, c.castId, false, c.spellId;
    end
end
function UnitChannelInfo()
    return nil;
end

function IsMounted()
    return H.player.mounted;
end
function IsStealthed()
    return H.player.stealthed;
end
function IsSwimming()
    return H.player.swimming;
end
function IsSubmerged()
    return H.player.swimming;
end
function IsFlying()
    return false;
end
function IsFalling()
    return false;
end
function IsResting()
    return H.zone.resting == true;
end
function IsIndoors()
    return false;
end
function IsOutdoors()
    return true;
end
function IsInGroup()
    return H.player.inGroup;
end
function IsInRaid()
    return H.player.inRaid;
end
function GetNumGroupMembers()
    return H.player.inRaid and 10 or (H.player.inGroup and 3 or 0);
end
function InCombatLockdown()
    return H.combat;
end
function IsLoggedIn()
    return H.loggedIn == true;
end
function GetMoney()
    return 1234567;
end
function GetRealmName()
    return H.player.realm;
end
function GetNormalizedRealmName()
    return H.player.realm;
end
function GetNetStats()
    return 0, 0, H.latencyHome, H.latencyWorld;
end
function IsShiftKeyDown()
    return H.modifiers.shift;
end
function IsControlKeyDown()
    return H.modifiers.ctrl;
end
function IsAltKeyDown()
    return H.modifiers.alt;
end
function IsLeftAltKeyDown()
    return H.modifiers.alt;
end
function IsModifierKeyDown()
    return H.modifiers.shift or H.modifiers.ctrl or H.modifiers.alt;
end
function GetCursorPosition()
    return 0, 0;
end
function GetScreenWidth()
    return 1920;
end
function GetScreenHeight()
    return 1080;
end
H.sounds = {};
function PlaySound(soundKitId, channel)
    if type(soundKitId) ~= "number" then
        error("Usage: PlaySound(soundKitID [, channel])", 2);
    end
    H.sounds[#H.sounds + 1] = soundKitId;
    return true, 1;
end
function PlaySoundFile()
    return true, 1;
end
function ShowHelm(v)
    H.player.showHelm = v and true or false;
end
function ShowCloak(v)
    H.player.showCloak = v and true or false;
end
function ShowingHelm()
    return H.player.showHelm;
end
function ShowingCloak()
    return H.player.showCloak;
end

C_PaperDollInfo = {
    AmmoNeeded = function()
        return H.player.ammoNeeded;
    end,
    GetInventorySlotInfo = function(slotName)
        local id = H.SLOT_IDS[slotName];
        if not id then
            error("C_PaperDollInfo.GetInventorySlotInfo: invalid slot name " .. tostring(slotName), 2);
        end
        return id, 136516, id == 18;
    end,
    CanAutoEquipCursorItem = function()
        return H.cursorItem() ~= nil;
    end,
    IsRangedSlotShown = function()
        return true;
    end,
};

H.SLOT_IDS = {AmmoSlot = 0, HeadSlot = 1, NeckSlot = 2, ShoulderSlot = 3, ShirtSlot = 4, ChestSlot = 5,
    WaistSlot = 6, LegsSlot = 7, FeetSlot = 8, WristSlot = 9, HandsSlot = 10, Finger0Slot = 11, Finger1Slot = 12,
    Trinket0Slot = 13, Trinket1Slot = 14, BackSlot = 15, MainHandSlot = 16, SecondaryHandSlot = 17,
    RangedSlot = 18, TabardSlot = 19};

---------------------------------------------------------------------------
-- spells, casting, shapeshift forms
---------------------------------------------------------------------------
H.spells = {
    [768] = "Cat Form", [5487] = "Bear Form", [9634] = "Dire Bear Form", [783] = "Travel Form",
    [1066] = "Aquatic Form", [24858] = "Moonkin Form", [2457] = "Battle Stance", [71] = "Defensive Stance",
    [2458] = "Berserker Stance", [465] = "Devotion Aura", [10290] = "Devotion Aura", [7294] = "Retribution Aura",
    [19746] = "Concentration Aura", [19876] = "Shadow Resistance Aura", [19888] = "Frost Resistance Aura",
    [19891] = "Fire Resistance Aura", [20218] = "Sanctity Aura", [1784] = "Stealth", [8690] = "Hearthstone",
    [63644] = "Activate Secondary Spec", [63645] = "Activate Primary Spec", [7620] = "Fishing",
};
H.shapeshiftForms = {2457, 71, 2458}; -- the stance bar of the current class (warrior)

C_Spell = {
    GetSpellName = function(id)
        return H.spells[id];
    end,
    GetSpellTexture = function(id)
        return H.spells[id] and (136000 + id % 1000) or nil;
    end,
    GetSpellInfo = function(id)
        local name = H.spells[id];
        if name then
            return {name = name, iconID = 136000 + id % 1000, castTime = 0, minRange = 0, maxRange = 0, spellID = id,
                originalIconID = 136000 + id % 1000};
        end
    end,
    GetSpellLink = function(id)
        local name = H.spells[id];
        return name and ("|cff71d5ff|Hspell:" .. id .. ":0|h[" .. name .. "]|h|r") or nil;
    end,
    GetSpellSubtext = function()
        return "";
    end,
    DoesSpellExist = function(id)
        return H.spells[id] ~= nil;
    end,
};

function GetShapeshiftForm()
    return H.player.form;
end
function GetNumShapeshiftForms()
    return #H.shapeshiftForms;
end
function GetShapeshiftFormInfo(index)
    local spellId = H.shapeshiftForms[index];
    if spellId then
        return C_Spell.GetSpellTexture(spellId), H.player.form == index, true, spellId;
    end
end

local castCounter = 0;
-- The player casts spellId for `seconds` (UnitCastingInfo returns it meanwhile). onSuccess runs before the
-- UNIT_SPELLCAST_SUCCEEDED/STOP events.
function H.cast(spellId, seconds, onSuccess)
    castCounter = castCounter + 1;
    local guid = "Cast-3-0-0-" .. spellId .. "-" .. castCounter;
    H.player.casting = {name = H.spells[spellId] or "Spell", spellId = spellId, startMs = H.nowMs,
        endMs = H.nowMs + seconds * 1000, castId = guid, icon = 136000};
    H.fireUnit("UNIT_SPELLCAST_START", "player", guid, spellId, castCounter);
    C_Timer.After(seconds, function()
        H.player.casting = nil;
        if onSuccess then
            onSuccess();
        end
        H.fireUnit("UNIT_SPELLCAST_SUCCEEDED", "player", guid, spellId, castCounter);
        H.fireUnit("UNIT_SPELLCAST_STOP", "player", guid, spellId, castCounter);
    end);
end

-- Activates a stance-bar entry by spell id (nil = no form).
function H.setForm(spellId)
    local index = 0;
    for i, id in ipairs(H.shapeshiftForms) do
        if id == spellId then
            index = i;
        end
    end
    H.player.form = index;
    H.fire("UPDATE_SHAPESHIFT_FORM");
end

---------------------------------------------------------------------------
-- spec groups
---------------------------------------------------------------------------
C_SpecializationInfo = {
    GetActiveSpecGroup = function(isInspect, isPet)
        return H.player.specGroup;
    end,
    SetActiveSpecGroup = function(group)
        H.setSpecGroup(group, {cast = true});
    end,
};
function GetNumSpecGroups()
    return H.player.numSpecGroups;
end

-- Switches the active spec group. Every item link's spec id changes with it (like the client).
-- opts.cast = true: a 5 s "Activate ... Spec" cast first (UNIT_SPELLCAST_START ... SUCCEEDED/STOP).
function H.setSpecGroup(group, opts)
    local prev = H.player.specGroup;
    if group == prev then
        return;
    end
    local function activate()
        H.player.specGroup = group;
        H.fire("ACTIVE_TALENT_GROUP_CHANGED", group, prev);
        H.fire("PLAYER_TALENT_UPDATE");
        H.fireUnit("PLAYER_SPECIALIZATION_CHANGED", "player");
    end
    if opts and opts.cast then
        H.cast(group == 1 and 63645 or 63644, 5, activate);
    else
        activate();
    end
end

---------------------------------------------------------------------------
-- combat and restrictions
---------------------------------------------------------------------------
-- PLAYER_REGEN_DISABLED fires just before lockdown starts; PLAYER_REGEN_ENABLED right after it ends.
function H.setCombat(on)
    if on and not H.combat then
        H.affectingCombat = true;
        H.fire("PLAYER_REGEN_DISABLED");
        H.combat = true;
    elseif not on and H.combat then
        H.combat = false;
        H.affectingCombat = false;
        H.fire("PLAYER_REGEN_ENABLED");
    end
end

H.restrictions = {};
-- An addon restriction (default PvPMatch) makes UnitIsAFK/UnitIsDND and non-group unit identity secret.
function H.setRestricted(on, restrictionType)
    restrictionType = restrictionType or Enum.AddOnRestrictionType.PvPMatch;
    if on then
        H.fire("ADDON_RESTRICTION_STATE_CHANGED", restrictionType, Enum.AddOnRestrictionState.Activating);
        H.restrictions[restrictionType] = true;
        H.restricted = true;
    else
        H.restrictions[restrictionType] = nil;
        H.restricted = next(H.restrictions) ~= nil;
        H.fire("ADDON_RESTRICTION_STATE_CHANGED", restrictionType, Enum.AddOnRestrictionState.Inactive);
    end
end

C_RestrictedActions = {
    IsAddOnRestrictionActive = function(restrictionType)
        return H.restrictions[restrictionType] == true;
    end,
    GetAddOnRestrictionState = function(restrictionType)
        return H.restrictions[restrictionType] and Enum.AddOnRestrictionState.Active or
                   Enum.AddOnRestrictionState.Inactive;
    end,
};

---------------------------------------------------------------------------
-- unit state helpers (fire the events the client fires)
---------------------------------------------------------------------------
function H.setAFK(v)
    H.player.afk = v;
    H.fireUnit("PLAYER_FLAGS_CHANGED", "player");
end
function H.setPvP(v)
    H.player.pvp = v;
    H.fireUnit("PLAYER_FLAGS_CHANGED", "player");
    H.fireUnit("UNIT_FACTION", "player");
end
function H.setMounted(v)
    H.player.mounted = v;
    H.fire("PLAYER_MOUNT_DISPLAY_CHANGED");
    H.fireUnit("UNIT_AURA", "player", {isFullUpdate = true});
end
function H.setStealthed(v)
    H.player.stealthed = v;
    H.fire("UPDATE_STEALTH");
    H.fireUnit("UNIT_AURA", "player", {isFullUpdate = true});
end
function H.setSwimming(v)
    H.player.swimming = v;
    H.fire(v and "MIRROR_TIMER_START" or "MIRROR_TIMER_STOP", "BREATH", 60000, 60000, -1, false, "Breath");
end
function H.setDead(v)
    H.player.dead = v;
    H.fire(v and "PLAYER_DEAD" or "PLAYER_ALIVE");
end
function H.setGroup(inGroup, inRaid)
    H.player.inGroup, H.player.inRaid = inGroup, inRaid;
    H.fire("GROUP_ROSTER_UPDATE");
end
function H.addNameplate(unit)
    H.nameplates[unit] = true;
    H.fireUnit("NAME_PLATE_UNIT_ADDED", unit);
end

---------------------------------------------------------------------------
-- maps, zones, instances
---------------------------------------------------------------------------
H.maps = {
    [947] = {mapID = 947, name = "Azeroth", mapType = 0, parentMapID = 0, flags = 0},
    [1414] = {mapID = 1414, name = "Kalimdor", mapType = 2, parentMapID = 947, flags = 0},
    [1415] = {mapID = 1415, name = "Eastern Kingdoms", mapType = 2, parentMapID = 947, flags = 0},
    [1429] = {mapID = 1429, name = "Elwynn Forest", mapType = 3, parentMapID = 1415, flags = 0},
    [1453] = {mapID = 1453, name = "Stormwind City", mapType = 3, parentMapID = 1415, flags = 0},
    [1411] = {mapID = 1411, name = "Durotar", mapType = 3, parentMapID = 1414, flags = 0},
    [1454] = {mapID = 1454, name = "Orgrimmar", mapType = 3, parentMapID = 1414, flags = 0},
    [1459] = {mapID = 1459, name = "Alterac Valley", mapType = 3, parentMapID = 1415, flags = 0},
    [1460] = {mapID = 1460, name = "Warsong Gulch", mapType = 3, parentMapID = 1414, flags = 0},
    [1461] = {mapID = 1461, name = "Arathi Basin", mapType = 3, parentMapID = 1415, flags = 0},
};
H.zones = {
    stormwind = {mapId = 1453, zone = "Stormwind City", subzone = "Trade District", resting = true},
    elwynn = {mapId = 1429, zone = "Elwynn Forest", subzone = "Goldshire"},
    orgrimmar = {mapId = 1454, zone = "Orgrimmar", subzone = "Valley of Strength", resting = true},
    wsg = {mapId = 1460, zone = "Warsong Gulch", subzone = "", instance = "pvp", bg = true},
    ab = {mapId = 1461, zone = "Arathi Basin", subzone = "", instance = "pvp", bg = true},
    av = {mapId = 1459, zone = "Alterac Valley", subzone = "", instance = "pvp", bg = true},
};
H.zone = H.zones.stormwind;

local function copyMap(info)
    return info and {mapID = info.mapID, name = info.name, mapType = info.mapType, parentMapID = info.parentMapID,
        flags = info.flags} or nil;
end

C_Map = {
    GetBestMapForUnit = function(unit)
        return isPlayer(unit) and H.zone.mapId or nil;
    end,
    GetMapInfo = function(mapId)
        return copyMap(H.maps[mapId]);
    end,
    GetMapChildrenInfo = function(mapId, mapType, allDescendants)
        local list = {};
        for _, info in pairs(H.maps) do
            local p, match = info.parentMapID, false;
            while p and p ~= 0 do
                if p == mapId then
                    match = true;
                    break;
                end
                p = allDescendants and H.maps[p] and H.maps[p].parentMapID or nil;
            end
            if match and (not mapType or info.mapType == mapType) then
                list[#list + 1] = copyMap(info);
            end
        end
        table.sort(list, function(a, b)
            return a.mapID < b.mapID;
        end);
        return list;
    end,
};

C_PvP = {
    IsBattleground = function()
        return H.zone.bg == true;
    end,
    IsArena = function()
        return false;
    end,
    IsPVPMap = function()
        return H.zone.bg == true;
    end,
};

function IsInInstance()
    if H.zone.instance then
        return true, H.zone.instance;
    end
    return false, "none";
end
function GetInstanceInfo()
    return H.zone.zone, H.zone.instance or "none", 0, "", 40, 0, false, H.zone.mapId, 0, nil;
end
function GetZoneText()
    return H.zone.zone;
end
GetRealZoneText = GetZoneText;
function GetSubZoneText()
    return H.zone.subzone or "";
end
function GetMinimapZoneText()
    return (H.zone.subzone ~= "" and H.zone.subzone) or H.zone.zone;
end

-- Moves the player to a zone (key of H.zones). Entering or leaving an instance goes through a loading screen
-- (PLAYER_ENTERING_WORLD(false, false)); battlegrounds also switch the PvP-match addon restriction on.
function H.setZone(zoneKey)
    local new = H.zones[zoneKey] or error("harness: unknown zone " .. tostring(zoneKey), 2);
    local old = H.zone;
    local loading = (old.instance ~= nil) ~= (new.instance ~= nil) or (old.instance and old ~= new);
    if old.bg and not new.bg then
        H.setRestricted(false);
    end
    H.zone = new;
    if new.bg and not old.bg then
        H.setRestricted(true);
    end
    if loading then
        H.fire("PLAYER_ENTERING_WORLD", false, false);
    end
    H.fire("ZONE_CHANGED_NEW_AREA");
    H.fire("ZONE_CHANGED");
end

---------------------------------------------------------------------------
-- add-ons
---------------------------------------------------------------------------
H.loadedAddons = {};
C_AddOns = {
    GetAddOnMetadata = function(name, field)
        if name == H.addonName then
            return H.tocFields[field];
        end
    end,
    IsAddOnLoaded = function(name)
        return H.loadedAddons[name] == true, H.loadedAddons[name] == true;
    end,
    GetAddOnInfo = function(name)
        if name == H.addonName or name == 1 then
            return H.addonName, H.tocFields.Title, H.tocFields.Notes, true, nil, "INSECURE", false;
        end
        return nil, nil, nil, false, "MISSING", "INSECURE", false;
    end,
    GetNumAddOns = function()
        return 1;
    end,
    LoadAddOn = function(name)
        if name == H.addonName then
            return true;
        end
        return false, "MISSING";
    end,
    GetAddOnEnableState = function(name)
        return name == H.addonName and 2 or 0;
    end,
};
