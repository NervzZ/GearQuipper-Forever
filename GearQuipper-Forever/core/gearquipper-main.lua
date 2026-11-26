-- scope stuff
gearquipper = gearquipper or {};
local c = gearquipper;

local switchId, switchQueue, switching, bankAction = 0, {};
local inCombat, notifyInventoryError, actionBlocked, combatEquipBlockedNotified;

local lastMapId, lastDruidForm, lastPaladinAura, lastWarriorStance, lastSpecGroup;
local druidShapeshiftPending, paladinAuraPending, warriorStancePending, unitAuraPending;
local lastGearAndBagsCache, enchantSnapshotPinned, enchantCheckPending;
local talentChangeId = 0;
local charName;

local timeoutHighlightButtons = 1;

local BLIZZARD_UI_ADDONS = {"Blizzard_AchievementUI", "Blizzard_TalentUI", "Blizzard_TradeSkillUI",
                            "Blizzard_PlayerSpells", "Blizzard_Professions"};

local QUEUE_CAUSE_COMBAT = "combat";
local QUEUE_CAUSE_ACTION = "action";
local QUEUE_CAUSE_INVENTORY = "inventory";

-- edge detector keys (c:InitState / c:UpdateState)
local STATE_MOUNT, STATE_STEALTH, STATE_PVP, STATE_AFK = "mount", "stealth", "pvp", "afk";
local STATE_PARTY, STATE_RAID, STATE_SWIM = "party", "raid", "swim";

local AZEROTH_MAP_ID = 947;

-- the game allows only these slots to change in combat
local COMBAT_EQUIP_SLOTS = {
    [INVSLOT_MAINHAND] = true,
    [INVSLOT_OFFHAND] = true,
    [INVSLOT_RANGED] = true
};

-- A locked item, or an item still moving from an earlier action, can only be equipped once the server has answered;
-- a switch therefore takes up to this many passes.
local MAX_SWITCH_PASSES = 3;

local PASS_DONE, PASS_ERROR, PASS_COMBAT, PASS_ACTION, PASS_BLOCKED = 1, 2, 3, 4, 5;
local SLOT_OK, SLOT_WAIT, SLOT_FAILED, SLOT_MISSING, SLOT_ERROR = 1, 2, 3, 4, 5;

-- A switch moves on as soon as the server has answered its actions (see AwaitLanding). These fallbacks (ms, plus home
-- latency and the switch delay) only cover events that never come; while the server has not answered at all they
-- keep waiting, for at most MAX_LANDING_WAIT seconds.
local PASS_FALLBACK_MS, FINISH_FALLBACK_MS = 100, 500;
local MAX_LANDING_WAIT = 5;

-- A spec change is done when ACTIVE_TALENT_GROUP_CHANGED fires; this settle (ms, plus home latency) only lets quick
-- double changes collapse into the last one.
local TALENT_SETTLE_MS = 200;
local TALENT_CAST_WAIT, TALENT_CAST_WAIT_TRIES = 0.1, 50;

c.SWITCHARG_FIRST = "SWITCHARG_FIRST";
c.SWITCHARG_ID = "SWITCHARG_ID";
c.SWITCHARG_NOTIFY = "SWITCHARG_NOTIFY";
c.SWITCHARG_ONFINISHED = "SWITCHARG_ONFINISHED";
c.SWITCHARG_SETNAME = "SWITCHARG_SETNAME";
c.SWITCHARG_QUEUE_CAUSE = "SWITCHARG_QUEUE_CAUSE";

function c:GetCharName()
    if not charName then
        local name = c:SafeCall(UnitName, "player");
        if name and name ~= UNKNOWNOBJECT then
            charName = name;
        end
        return name;
    end
    return charName;
end

function c:GetRealmName()
    return GetRealmName();
end

local function GetNextSwitchId()
    switchId = switchId + 1;
    return switchId;
end

-- only feeds fallbacks and debounces
local function SwitchDelay()
    return GQ_OPTIONS[c.OPT_SWITCHDELAY] or 200;
end

function c:NotifyInChat(msg)
    if GQ_OPTIONS[c.OPT_NOTIFYCHANGES] then
        c:Println(msg);
    end
end

-- ActionButton_ShowOverlayGlow does not exist on WoW Forever
local function HighlightButton(button)
    if button and button.CreateTexture then
        if not button.gqHighlight then
            button.gqHighlight = button:CreateTexture(nil, "OVERLAY");
            button.gqHighlight:SetTexture("Interface\\Buttons\\CheckButtonHilight");
            button.gqHighlight:SetBlendMode("ADD");
            button.gqHighlight:SetAllPoints(button);
        end
        local highlight = button.gqHighlight;
        highlight.token = (highlight.token or 0) + 1;
        local token = highlight.token;
        highlight:Show();
        C_Timer.After(timeoutHighlightButtons, function()
            if highlight.token == token then
                highlight:Hide();
            end
        end);
    end
end

function c:HighlightInventorySlot(slotId)
    if GQ_OPTIONS[c.OPT_HIGHLIGHTCHANGES] then
        if c:GetSlotInfo()[slotId] then
            HighlightButton(_G["Character" .. c:GetSlotInfo()[slotId]]);
        end
    end
end

function c:IsSwitching()
    return switching;
end

-- Gear slots the running (or last) switch changed -> item string it put there. For a short while after the switch an
-- equip event that only repeats that state is the switch's own late echo, not a manual change (see EquipmentChanged).
local switchEchoSlots, switchEchoUntil = {}, 0;
local SWITCH_ECHO_SECONDS = 2;

function c:SetSwitching(value)
    switching = value;
    if value then
        wipe(switchEchoSlots);
        c:DebugPrint("Switching: true");
    else
        switchEchoUntil = GetTime() + SWITCH_ECHO_SECONDS;
        c:DebugPrint("Switching: false");
    end
end

local function IsSwitchEcho(slotId)
    return GetTime() <= switchEchoUntil and switchEchoSlots[slotId] ~= nil and
               c:GetItemString(slotId) == switchEchoSlots[slotId];
end

function c:GetNextSetName(seedName)
    local setNames = c:LoadSetNames();
    if setNames then
        if not seedName then
            return setNames[1];
        end

        for i, setName in ipairs(setNames) do
            if setName == seedName then
                local result;
                if i == #setNames then
                    result = nil;
                else
                    result = setNames[i + 1];
                end
                if result == c:LoadCurrentSetName() then
                    return c:GetNextSetName(result);
                end
                return result;
            end
        end
    end
end

-- command handling
SLASH_GEARQUIPPER1 = "/gq";
local CMD_DEBUG = "debug";
local CMD_RESET = "reset";
local CMD_SAVE = "save";
local CMD_SWITCH = "switch";
local CMD_SWITCHWAIT = "switchwait";
local CMD_TOGGLEEVENTS = "toggleevents";

local CMD_AFFECTSHELMET = "affectshelmet";
local CMD_AFFECTSCLOAK = "affectscloak";

-- removes the leading command word only (a set name may contain the command word)
local function RemoveCommand(msg, command)
    return (c:Trim(string.sub(msg, string.len(command) + 1)));
end

SlashCmdList["GEARQUIPPER"] = function(msg)
    if msg then
        if c.initFinished then
            msg = c:Trim(msg);

            if msg == CMD_DEBUG then
                c.debugMode = not c.debugMode;
                if c.debugMode then
                    c:Println("Debug mode enabled. Type '/gq debug' or relog/reload to disable.");
                else
                    c:Println("Debug mode disabled.");
                end
                return;
            elseif msg == CMD_RESET then
                c:ShowResetDialog();
                return;
            elseif c:StartsWith(msg, CMD_SWITCHWAIT, true) then
                msg = RemoveCommand(msg, CMD_SWITCHWAIT);

                if msg ~= "" then
                    local args = c:ExtractArguments(msg);

                    if args and #args == 2 then
                        local setName, onFinished = args[1], args[2];

                        local existingSetName = c:TableContains(c:LoadSetNames(), setName, true);
                        if existingSetName then
                            c:QueueSwitch({
                                [c.SWITCHARG_SETNAME] = existingSetName,
                                [c.SWITCHARG_ONFINISHED] = onFinished
                            });
                            return;
                        else
                            c:Println(c:GetText("Macro warning: There is no set named \"%s\".", setName));
                        end
                    end
                end
            elseif c:StartsWith(msg, CMD_SWITCH, true) then
                msg = RemoveCommand(msg, CMD_SWITCH);
                local existingSets, setNames = c:LoadSetNames(), {};

                if msg ~= "" then
                    for _, v in ipairs(c:ExtractArguments(msg)) do
                        if string.upper(v) == c.KEYWORD_PREVIOUS then
                            table.insert(setNames, c.KEYWORD_PREVIOUS);
                        elseif string.upper(v) == c.KEYWORD_PREVIOUSEQUIPMENT then
                            table.insert(setNames, c.KEYWORD_PREVIOUSEQUIPMENT);
                        else
                            local existingSetName = c:TableContains(existingSets, v, true);
                            if existingSetName then
                                table.insert(setNames, existingSetName);
                            else
                                c:Println(c:GetText("Macro warning: There is no set named \"%s\".", v));
                            end
                        end
                    end
                else
                    setNames = c:Deepcopy(existingSets);
                end

                local noSets = #setNames;
                if noSets == 1 then
                    c:QueueSwitch({
                        [c.SWITCHARG_SETNAME] = setNames[1]
                    });
                elseif noSets > 1 then
                    local currentSet = c:LoadCurrentSetName();
                    for k, v in ipairs(setNames) do
                        if v == currentSet then
                            local index = k + 1;
                            if index > noSets then
                                index = 1;
                            end
                            c:QueueSwitch({
                                [c.SWITCHARG_SETNAME] = setNames[index]
                            });
                            return;
                        end
                    end

                    c:ResetIgnoredSlots();
                    c:QueueSwitch({
                        [c.SWITCHARG_SETNAME] = setNames[1]
                    });
                end
                return;
            elseif c:StartsWith(msg, CMD_SAVE, true) then
                msg = RemoveCommand(msg, CMD_SAVE);

                if msg ~= "" then
                    local existingSetName = c:TableContains(c:LoadSetNames(), msg, true);
                    if existingSetName then
                        c:SaveSet(existingSetName);
                    else
                        c:Println(c:GetText("Macro warning: There is no set named \"%s\".", msg));
                    end
                else
                    local currentSetName = c:LoadCurrentSetName();
                    if currentSetName then
                        c:SaveSet(currentSetName);
                    end
                end
                return;
            elseif msg == CMD_TOGGLEEVENTS then
                local newVal = not c:IsEventsEnabled();
                c:SetEventsEnabled(newVal);
                c:ToggleEvents(newVal);
                c:Println(c:GetText("Event bindings %s.",
                    c:BoolToText(newVal, c:GetText("enabled"), c:GetText("disabled"))));
                return;
            elseif msg == CMD_AFFECTSHELMET then
                local setName = c:LoadCurrentSetName();
                c:SetAffectsHelmet(not c:GetAffectsHelmet(setName), setName);
                return;
            elseif msg == CMD_AFFECTSCLOAK then
                local setName = c:LoadCurrentSetName();
                c:SetAffectsCloak(not c:GetAffectsCloak(setName), setName);
                return;
            end

            c:Println(c:GetText("Unknown command. Possible parameters are: /gq ..."));
            c:Println(c:GetText("affectscloak -> Toggles whether your current set affects cloak visibility or not."));
            c:Println(c:GetText("affectshelmet -> Toggles whether your current set affects helmet visibility or not."));
            c:Println(c:GetText("reset -> Resets the GearQuipper addon (e.g. in case of errors)."));
            c:Println(c:GetText("save [setname] -> Saves the specified set or the current set if omitted."));
            c:Println(c:GetText("switch [setname1] [setname2] ... -> Switches between specified sets. For macro use."));
            c:Println(c:GetText("toggleevents -> Toggles event bindings enabled or disabled."));
        else
            c:Println(c:GetText("The AddOn has not been initialized due to an error. Please relog and try again."));
        end
    end
end

----- [ state reading ] -----

local function IsAmmoNeeded()
    return C_PaperDollInfo ~= nil and c:ReadState(C_PaperDollInfo.AmmoNeeded) == true;
end

local function IsSlotLocked(slotId)
    return c:ReadState(IsInventoryItemLocked, slotId) == true;
end

local function IsBagSlotLocked(bagId, slotId)
    local _, _, locked = c:GetContainerItemInfo(bagId, slotId);
    return locked == true;
end

local function CursorCanGoInSlot(slotId)
    if C_PaperDollInfo and C_PaperDollInfo.CursorCanGoInSlot then
        return c:ReadState(C_PaperDollInfo.CursorCanGoInSlot, slotId) ~= false;
    end
    return true;
end

local function CellKey(bagId, slotId)
    return bagId .. ":" .. slotId;
end

local function GetEquipLoc(itemString)
    if type(itemString) == "string" and itemString ~= c.VALUE_NONE then
        local itemId = tonumber(c:GetItemId(itemString));
        if itemId then
            local _, _, _, equipLoc = c:GetItemInfoInstant(itemId);
            return equipLoc;
        end
    end
end

local function IsTwoHandItem(itemString)
    return GetEquipLoc(itemString) == "INVTYPE_2HWEAPON";
end

-- Whether an equipped weapon may change places with the other hand (rings and trinkets always may).
local function CanMoveToSlot(itemString, slotId)
    if slotId ~= INVSLOT_MAINHAND and slotId ~= INVSLOT_OFFHAND then
        return true;
    end
    local equipLoc = GetEquipLoc(itemString);
    if not equipLoc then
        return true;
    end
    if slotId == INVSLOT_MAINHAND then
        return equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_2HWEAPON" or equipLoc == "INVTYPE_WEAPONMAINHAND";
    end
    if equipLoc == "INVTYPE_WEAPON" then
        return c:ReadState(CanDualWield) ~= false;
    end
    return equipLoc == "INVTYPE_WEAPONOFFHAND" or equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE";
end

-- true/false, or nil when unknown; a taxi flight counts as not mounted
local function ReadMountState()
    local mounted = c:ReadState(IsMounted);
    if mounted == nil or mounted == false then
        return mounted;
    end
    local onTaxi = c:ReadState(UnitOnTaxi, "player");
    if onTaxi == nil then
        return nil;
    end
    return not onTaxi;
end

-- Spell id of the active stance bar entry, false when none is active, nil when unknown.
local function ReadActiveShapeshift()
    local formIndex = c:SafeCall(GetShapeshiftForm);
    if formIndex == nil then
        return nil;
    end
    if formIndex == 0 then
        return false;
    end
    return c:GetActiveShapeshiftSpellId();
end

-- Ranked spells (auras, stances) match by name, so every rank maps to the table's entry.
local function MatchSpellByName(spells, spellId)
    if not spellId then
        return nil;
    end
    if spells[spellId] then
        return spellId;
    end
    local spellName = c:GetSpellName(spellId);
    if spellName and not c:IsSecret(spellName) then
        for id, name in pairs(spells) do
            if id ~= c.VALUE_NONE and name == spellName then
                return id;
            end
        end
    end
end

local function GetCurrentWarriorStance()
    local spellId = ReadActiveShapeshift();
    if spellId == nil then
        return nil;
    end
    return (spellId and MatchSpellByName(c:GetWarriorStances(), spellId)) or c.VALUE_NONE;
end

local function FireEdge(edge, enableEvent, disableEvent)
    if edge == true then
        c:HandleEvent(enableEvent);
    elseif edge == false then
        c:HandleEvent(disableEvent);
    end
end

local function CheckMountState()
    local edge = c:UpdateState(STATE_MOUNT, ReadMountState());
    if edge == true then
        c:Mounting();
    elseif edge == false then
        c:Dismounting();
    end
end

local function InitEventStates()
    c:InitState(STATE_MOUNT, ReadMountState());
    c:InitState(STATE_STEALTH, c:ReadState(IsStealthed));
    c:InitState(STATE_PARTY, c:ReadState(IsInGroup));
    c:InitState(STATE_RAID, c:ReadState(IsInRaid));
    c:InitState(STATE_PVP, c:ReadState(UnitIsPVP, "player"));
    c:InitState(STATE_AFK, c:ReadState(UnitIsAFK, "player"));
    c:InitState(STATE_SWIM, c:ReadState(IsSwimming));

    lastMapId = c:SafeCall(C_Map.GetBestMapForUnit, "player");
    c:IsZoneBattleground(lastMapId); -- remembers the map when logging in inside a battleground

    lastDruidForm = c:GetCurrentDruidForm();
    druidShapeshiftPending = false;
    lastPaladinAura = c:GetCurrentPaladinAura();
    paladinAuraPending = false;
    lastWarriorStance = GetCurrentWarriorStance();
    warriorStancePending = false;

    lastSpecGroup = c:GetActiveSpecGroup();
end

-- UNIT_AURA is only a "something changed" ping; its payload is never read (secret in combat and PvP).
local function ScheduleAuraCheck()
    if not unitAuraPending then
        unitAuraPending = true;
        C_Timer.After(c:GetHomeLatency(SwitchDelay()) / 1000, function()
            unitAuraPending = false;
            CheckMountState();
            FireEdge(c:UpdateState(STATE_STEALTH, c:ReadState(IsStealthed)), c.EVENT_STEALTH, c.EVENT_UNSTEALTH);
            c:SpellAuraApplied();
        end);
    end
end

local function ScheduleEnchantCheck()
    if not enchantCheckPending then
        enchantCheckPending = true;
        C_Timer.After(c:GetHomeLatency(100 + SwitchDelay()) / 1000, function()
            enchantCheckPending = false;
            c:CheckForNewEnchantment();
            enchantSnapshotPinned = false;
        end);
    end
end

local function ReleaseEnchantSnapshot()
    if not enchantCheckPending then
        enchantSnapshotPinned = false;
    end
end

local function FireTalentsChanged(changeId, newGroup, triesLeft)
    if changeId ~= talentChangeId then
        return;
    end
    if triesLeft > 0 and c:IsCastingSpell() then
        -- the spec change's own cast may still be ending: switch right after it instead of queueing behind it
        C_Timer.After(TALENT_CAST_WAIT, function()
            FireTalentsChanged(changeId, newGroup, triesLeft - 1);
        end);
        return;
    end
    c:HandleEvent(c.EVENT_TALENTS_CHANGED, c:GetActiveSpecGroup() or newGroup);
end

local function TalentGroupChanged(newGroup, oldGroup)
    newGroup = (not c:IsSecret(newGroup) and tonumber(newGroup)) or c:GetActiveSpecGroup();
    oldGroup = not c:IsSecret(oldGroup) and tonumber(oldGroup);
    if oldGroup ~= 1 and oldGroup ~= 2 then
        oldGroup = nil;
    end

    local previousGroup = lastSpecGroup or oldGroup;
    lastSpecGroup = newGroup or lastSpecGroup;
    if not newGroup or not previousGroup or newGroup == previousGroup then
        return;
    end

    -- only the last of several quick spec changes counts
    talentChangeId = talentChangeId + 1;
    local changeId = talentChangeId;
    C_Timer.After(c:GetHomeLatency(TALENT_SETTLE_MS) / 1000, function()
        FireTalentsChanged(changeId, newGroup, TALENT_CAST_WAIT_TRIES);
    end);
end

----- [ waiting for the server ] -----

-- After a switch pass, the next pass and the end of the switch wait until the server has answered the pass's actions:
-- until then the touched items stay locked and reads show the old gear and bags. The actions have landed when every
-- touched gear slot and bag cell is unlocked, every touched gear slot has had its PLAYER_EQUIPMENT_CHANGED and holds
-- the item the pass expects, and the slots that waited for a lock this pass did not cause are free. The check runs one
-- frame after any inventory event, so all events of a server reply have been handled by then.
local landing, landingCheckPending;

local function NewWatch()
    return {
        slots = {}, -- gear slot the pass changed -> item string it expects there (VALUE_NONE = empty)
        cells = {}, -- cell key -> location {bagId, slotId} the pass took an item from (bags and bank)
        lockedSlots = {}, -- gear slots that waited for someone else's lock
        lockedCells = {}, -- cell key -> location, same for bag cells
        equipChanged = {} -- gear slots whose PLAYER_EQUIPMENT_CHANGED arrived
        -- ammo: ammo item id the pass equipped; final: the switch ends with this watch; inventoryChanged
    };
end

local function IsWatchEmpty(watch)
    return not (next(watch.slots) or next(watch.cells) or next(watch.lockedSlots) or next(watch.lockedCells) or
               watch.ammo);
end

-- false while the server has not answered the pass's own actions
local function OwnLocationsUnlocked(watch)
    for slotId in pairs(watch.slots) do
        if IsSlotLocked(slotId) then
            return false;
        end
    end
    for _, location in pairs(watch.cells) do
        if IsBagSlotLocked(location.bagId, location.slotId) then
            return false;
        end
    end
    return true;
end

local function HasLanded(watch)
    if not OwnLocationsUnlocked(watch) then
        return false;
    end
    for slotId in pairs(watch.lockedSlots) do
        if IsSlotLocked(slotId) then
            return false;
        end
    end
    for _, location in pairs(watch.lockedCells) do
        if IsBagSlotLocked(location.bagId, location.slotId) then
            return false;
        end
    end
    for slotId, itemString in pairs(watch.slots) do
        if not watch.equipChanged[slotId] or c:GetItemString(slotId) ~= itemString then
            return false;
        end
    end
    if watch.ammo and not c:Equals(c:GetItemString(INVSLOT_AMMO), watch.ammo) then
        return false;
    end
    -- the switch's own UNIT_INVENTORY_CHANGED (ammo auto-save) must also arrive while the switching flag is up
    if watch.final and (next(watch.slots) or watch.ammo) and not watch.inventoryChanged then
        return false;
    end
    return true;
end

local function CheckLanding()
    landingCheckPending = false;
    if landing and HasLanded(landing) then
        landing.land();
    end
end

-- on every inventory event: check once, on the next frame
local function ScheduleLandingCheck()
    if landing and not landingCheckPending then
        landingCheckPending = true;
        C_Timer.After(0, CheckLanding);
    end
end

-- Runs onLanded once the watched actions have landed. The fallback covers events that never come (a refused move
-- unlocks without an equip event); it keeps waiting while the own locations are still locked (no server answer yet),
-- up to MAX_LANDING_WAIT.
local function AwaitLanding(watch, fallbackMs, onLanded)
    local deadline = GetTime() + MAX_LANDING_WAIT;
    watch.land = function()
        if landing == watch then
            landing = nil;
            onLanded();
        end
    end;
    local function Fallback()
        if landing ~= watch then
            return;
        end
        if OwnLocationsUnlocked(watch) or GetTime() >= deadline then
            c:DebugPrint("Switch: moving on without all server events (fallback)");
            -- one more frame for the events of a reply that is being handled right now
            C_Timer.After(0, watch.land);
        else
            C_Timer.After(c:GetHomeLatency(fallbackMs) / 1000, Fallback);
        end
    end
    landing = watch;
    C_Timer.After(c:GetHomeLatency(fallbackMs) / 1000, Fallback);
    ScheduleLandingCheck(); -- a watch with nothing to wait for lands on the next frame
end

local function NotifyCombatEquipBlocked()
    if not combatEquipBlockedNotified then
        combatEquipBlockedNotified = true;
        c:Println(c:GetText("Weapon swaps in combat are blocked by the game; the switch will happen when combat ends."));
    end
end

-- event handling
c.eventFrame = c.eventFrame or CreateFrame("Frame");

local function RegisterEvents(...)
    for i = 1, select("#", ...) do
        pcall(c.eventFrame.RegisterEvent, c.eventFrame, (select(i, ...)));
    end
end

-- unit events fire for every unit (party, raid, nameplates); only the player's are wanted
local function RegisterPlayerEvents(...)
    for i = 1, select("#", ...) do
        pcall(c.eventFrame.RegisterUnitEvent, c.eventFrame, (select(i, ...)), "player");
    end
end

RegisterEvents("ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "TRADE_SKILL_SHOW", "MODIFIER_STATE_CHANGED");

-- event bindings
RegisterEvents("PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "SPELL_UPDATE_USABLE", "MIRROR_TIMER_START",
    "MIRROR_TIMER_STOP", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE",
    "RAID_ROSTER_UPDATE", "PLAYER_MOUNT_DISPLAY_CHANGED", "UPDATE_STEALTH", "UPDATE_SHAPESHIFT_FORM",
    "UPDATE_SHAPESHIFT_FORMS", "ACTIVE_TALENT_GROUP_CHANGED");
RegisterPlayerEvents("PLAYER_FLAGS_CHANGED", "UNIT_FACTION", "UNIT_AURA");

-- core features
RegisterEvents("PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "ITEM_LOCKED", "ITEM_UNLOCKED",
    "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN");
RegisterPlayerEvents("UNIT_INVENTORY_CHANGED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP");

c.eventFrame:HookScript("OnEvent", function(self, event, arg1, arg2, arg3)
    if not event then
        return;
    end

    if event == "ADDON_LOADED" then
        if arg1 == c.addonName and not c.initFinished then
            c:Init();
        elseif c:TableContains(BLIZZARD_UI_ADDONS, arg1) then
            c:HookBlizzardFrameScripts();
        end
        return;
    end

    if not c.initFinished then
        return;
    end

    if event == "PLAYER_LOGIN" then
        c.playerLogin = true;
    elseif event == "PLAYER_ENTERING_WORLD" then
        c:SetBankOpen(false);
        local currentRealmName, currentCharName = c:GetRealmName(), c:GetCharName();
        if not c.currentSession or c.currentSession["realmName"] ~= currentRealmName or c.currentSession["charName"] ~=
            currentCharName then
            c:CreateDefaultSet();
            c:CreatePreviousEquipmentSet();

            -- set initial states
            InitEventStates();

            c:LoadCloakAndHelmet();
            c.currentSession = {
                ["realmName"] = currentRealmName,
                ["charName"] = currentCharName
            };
        else
            CheckMountState();
            c:NewZone();
        end
    elseif event == "PLAYER_FLAGS_CHANGED" or event == "UNIT_FACTION" then
        FireEdge(c:UpdateState(STATE_PVP, c:ReadState(UnitIsPVP, "player")), c.EVENT_PVP_ENABLE, c.EVENT_PVP_DISABLE);
        FireEdge(c:UpdateState(STATE_AFK, c:ReadState(UnitIsAFK, "player")), c.EVENT_AFK_ENABLE, c.EVENT_AFK_DISABLE);
    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        c:SpellCastStart();
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        c:SpellCastSuccess(not c:IsSecret(arg3) and arg3 or nil);
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" or event ==
        "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        ReleaseEnchantSnapshot();
        c:SpellCastEnd();
    elseif event == "MODIFIER_STATE_CHANGED" then
        if arg1 == "LALT" and GQ_OPTIONS[c.OPT_SET_ITEM_COMPARISON] and not c:IsSwitching() then
            if GameTooltip:IsVisible() and arg2 == 1 then
                local ok, _, itemLink = pcall(GameTooltip.GetItem, GameTooltip);
                if ok and itemLink and not c:IsSecret(itemLink) then
                    local comparisonSetName = c:LoadComparisonSetName();
                    if not comparisonSetName or c:GetGqTooltip():IsVisible() then
                        comparisonSetName = c:GetNextSetName(comparisonSetName);
                    end
                    if comparisonSetName then
                        if c:ShowSetItemComparison(itemLink, comparisonSetName) then
                            c:SaveComparisonSetName(comparisonSetName);
                        end
                    else
                        c:HideGqTooltips();
                        if c:GetItemSlots(itemLink) then
                            c:SaveComparisonSetName(comparisonSetName);
                        end
                    end
                end
            end
        end
    elseif event == "UNIT_INVENTORY_CHANGED" then
        if landing then
            landing.inventoryChanged = true;
        end
        ScheduleLandingCheck();
        -- ammo slot workaround
        c:EquipmentChanged(INVSLOT_AMMO);
        ScheduleEnchantCheck();
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        if landing and not c:IsSecret(arg1) and arg1 then
            landing.equipChanged[arg1] = true;
        end
        ScheduleLandingCheck();
        if arg1 ~= INVSLOT_AMMO then
            c:EquipmentChanged(arg1);
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        ScheduleLandingCheck();
        ScheduleEnchantCheck();
    elseif event == "ITEM_LOCK_CHANGED" then
        ScheduleLandingCheck();
        if not enchantSnapshotPinned and not c:IsInCombat() and not c:IsDead() and not c:IsSwitching() and
            not bankAction then
            lastGearAndBagsCache = c:CacheCurrentGearAndBags();
        end
    elseif event == "ITEM_LOCKED" then
        if not c:IsSwitching() and not bankAction then
            local bagOrCharacterSlotId, bagSlotId = tonumber(arg1), tonumber(arg2);
            if bagOrCharacterSlotId and not bagSlotId and c:GetSlotInfo(bagOrCharacterSlotId) then
                c:OpenQuickBar(bagOrCharacterSlotId);
            end
        end
    elseif event == "ITEM_UNLOCKED" then
        ScheduleLandingCheck();
        c:CloseQuickBars();
        if GqUiFrame and GqUiFrame:IsVisible() and not c:IsSwitching() then
            c:RefreshSetList();
        end
    elseif event == "UNIT_AURA" or event == "PLAYER_MOUNT_DISPLAY_CHANGED" or event == "UPDATE_STEALTH" then
        ScheduleAuraCheck();
    elseif event == "UPDATE_SHAPESHIFT_FORM" or event == "UPDATE_SHAPESHIFT_FORMS" then
        c:SpellAuraApplied();
    elseif event == "BANKFRAME_OPENED" or event == "BANKFRAME_CLOSED" then
        c:SetBankOpen(event == "BANKFRAME_OPENED");
        if GqUiFrame and GqUiFrame:IsVisible() then
            -- timeout neccessary for closing event
            C_Timer.After(c:GetLatency(SwitchDelay()) / 1000, function()
                c:RefreshSetList(true);
            end);
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        c:LeaveCombat();
    elseif event == "PLAYER_REGEN_DISABLED" then
        c:EnterCombat();
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if arg1 == c.addonName and c:IsSwitching() and c:IsInCombat() then
            c.combatEquipBlocked = true;
            actionBlocked = true;
        end
    elseif event == "ACTIVE_TALENT_GROUP_CHANGED" then
        if c.playerLogin then
            TalentGroupChanged(arg1, arg2);
        end
    elseif event == "TRADE_SKILL_SHOW" then
        c:HookBlizzardFrameScripts();
        c:HookCharacterStatsFrameScripts();
        c:SetFramePositions();
    elseif event == "GROUP_ROSTER_UPDATE" or event == "RAID_ROSTER_UPDATE" then
        FireEdge(c:UpdateState(STATE_PARTY, c:ReadState(IsInGroup)), c.EVENT_PARTY_JOIN, c.EVENT_PARTY_LEAVE);
        FireEdge(c:UpdateState(STATE_RAID, c:ReadState(IsInRaid)), c.EVENT_RAID_JOIN, c.EVENT_RAID_LEAVE);
    elseif event == "SPELL_UPDATE_USABLE" or event == "MIRROR_TIMER_START" or event == "MIRROR_TIMER_STOP" then
        FireEdge(c:UpdateState(STATE_SWIM, c:ReadState(IsSwimming)), c.EVENT_SUBMERGE, c.EVENT_EMERGE);
    elseif c:StartsWith(event, "ZONE_CHANGED") then
        if c.firstZoneEntered then
            c:NewZone();
        else
            c.firstZoneEntered = true;
        end
    end
end);

function c:EquipmentChanged(slotId)
    -- slot ids beyond the gear slots (bags, bank tabs) are not ours
    if c:IsSwitching() or not slotId or not c:GetSlotInfo(slotId) or IsSwitchEcho(slotId) then
        return;
    end
    if slotId == INVSLOT_AMMO and not IsAmmoNeeded() then
        return;
    end

    if not bankAction then
        local currentSetName = c:LoadCurrentSetName();
        if currentSetName then
            -- a set whose switch is still queued keeps its items until that switch has run
            if c:SaveConditionsMet() and not c:IsSetQueued(currentSetName) and
                (not c:LoadPartialOption() or c:LoadSlotState(slotId)) and
                (slotId == INVSLOT_AMMO or not c:IsSetItemOnSlot(slotId, c:LoadSlot(slotId, currentSetName))) then
                c:SaveSlot(slotId, currentSetName);
            elseif GQ_OPTIONS[c.OPT_IGNOREMANUALITEMS] then
                c:AddIgnoredSlot(slotId);
            end

            c:SetSlotInfo(slotId);
        end
    end

    if slotId == INVSLOT_AMMO or not c:IsSetItemOnSlot(slotId, c:LoadSlot(slotId, c.KEYWORD_PREVIOUSEQUIPMENT)) then
        c:SaveSlot(slotId, c.KEYWORD_PREVIOUSEQUIPMENT, false);
    end
end

function c:HandleEvent(eventType, eventSubType)
    if eventType == c.EVENT_MOUNT then
        c:InitState(STATE_MOUNT, true);
    elseif eventType == c.EVENT_DISMOUNT then
        c:InitState(STATE_MOUNT, false);
    elseif eventType == c.EVENT_STEALTH then
        c:InitState(STATE_STEALTH, true);
    elseif eventType == c.EVENT_UNSTEALTH then
        c:InitState(STATE_STEALTH, false);
    end

    if c:IsEventsEnabled() then
        local filter = {
            [c.FIELD_TYPE] = eventType
        };
        if eventType == c.EVENT_ZONE_ENTER or eventType == c.EVENT_ZONE_LEAVE then
            filter[c.FIELD_SUBTYPE] = c:GetZoneInfo(eventSubType);
        elseif eventType == c.EVENT_SHAPESHIFT_IN or eventType == c.EVENT_SHAPESHIFT_OUT then
            -- druid shapes
            filter[c.FIELD_SUBTYPE] = {
                name = c:GetDruidForms()[eventSubType],
                spellId = eventSubType
            };
        elseif eventType == c.EVENT_AURA_CHANGED then
            -- paladin auras
            filter[c.FIELD_SUBTYPE] = {
                name = c:GetPaladinAuras()[eventSubType],
                spellId = eventSubType
            };
        elseif eventType == c.EVENT_STANCE_CHANGED then
            -- warrior stances
            filter[c.FIELD_SUBTYPE] = {
                name = c:GetWarriorStances()[eventSubType],
                spellId = eventSubType
            };
        elseif eventType == c.EVENT_TALENTS_CHANGED then
            -- spec group (1 or 2)
            filter[c.FIELD_SUBTYPE] = {
                name = c:GetTalentSpecializations()[eventSubType],
                spellId = eventSubType
            };
        end

        local setBindings = c:LoadEventBindings(filter);
        if setBindings then
            local currentPvPState = c:ReadState(UnitIsPVP, "player");
            if currentPvPState == nil then
                currentPvPState = c:GetState(STATE_PVP) == true;
            end
            for index, binding in pairs(setBindings) do
                if (binding[c.FIELD_ENABLED] == nil or binding[c.FIELD_ENABLED]) and
                    ((binding[c.FIELD_PVE] and not currentPvPState) or (binding[c.FIELD_PVP] and currentPvPState)) then
                    c:QueueSwitch({
                        [c.SWITCHARG_SETNAME] = binding[c.FIELD_NAME]
                    });
                    return true;
                end
            end
        end
    end
end

function c:Mounting()
    c:HandleEvent(c.EVENT_MOUNT);
end

function c:Dismounting()
    c:HandleEvent(c.EVENT_DISMOUNT);
end

function c:NewZone()
    local currentMapId = c:SafeCall(C_Map.GetBestMapForUnit, "player");
    if currentMapId ~= lastMapId then
        local previousMapId = lastMapId;
        local previousZoneInfo, currentZoneInfo = c:GetZoneInfo(previousMapId), c:GetZoneInfo(currentMapId);
        local previousParentMapId = previousZoneInfo and previousZoneInfo["parentMapID"];
        local currentParentMapId = currentZoneInfo and currentZoneInfo["parentMapID"];
        if previousParentMapId == AZEROTH_MAP_ID then
            previousParentMapId = nil;
        end
        if currentParentMapId == AZEROTH_MAP_ID then
            currentParentMapId = nil;
        end

        if previousMapId then
            -- leave bg
            if c:IsZoneBattleground(previousMapId) then
                c:HandleEvent(c.EVENT_BG_LEAVE);
            end

            -- leave parent zone, unless the new map is in it as well
            if previousParentMapId and previousParentMapId ~= currentMapId and previousParentMapId ~=
                currentParentMapId then
                c:HandleEvent(c.EVENT_ZONE_LEAVE, previousParentMapId);
            end
            -- leave zone
            c:HandleEvent(c.EVENT_ZONE_LEAVE, previousMapId);
        end
        lastMapId = currentMapId;

        if currentMapId then
            -- enter bg
            if c:IsZoneBattleground(currentMapId) then
                c:HandleEvent(c.EVENT_BG_ENTER);
            end

            -- enter parent zone, unless the old map was in it already
            if currentParentMapId and currentParentMapId ~= previousMapId and currentParentMapId ~=
                previousParentMapId then
                c:HandleEvent(c.EVENT_ZONE_ENTER, currentParentMapId);
            end
            -- enter zone
            c:HandleEvent(c.EVENT_ZONE_ENTER, currentMapId);
        end
    end
end

-- druid form spell id, VALUE_NONE when in no form, nil when unknown
function c:GetCurrentDruidForm()
    local spellId = ReadActiveShapeshift();
    if spellId == nil then
        return nil;
    end
    if spellId and c:GetDruidForms()[spellId] then
        return spellId;
    end
    return c.VALUE_NONE;
end

-- paladin aura spell id (the table's key), VALUE_NONE when none, nil when unknown
function c:GetCurrentPaladinAura()
    local spellId = ReadActiveShapeshift();
    if spellId == nil then
        return nil;
    end
    return (spellId and MatchSpellByName(c:GetPaladinAuras(), spellId)) or c.VALUE_NONE;
end

function c:EnterCombat()
    inCombat = true;
    c:HandleEvent(c.EVENT_COMBAT_ENTER);
    c:LockUI();
end

function c:LeaveCombat()
    inCombat = false;
    lastGearAndBagsCache = nil;
    enchantSnapshotPinned = false;
    c:HandleEvent(c.EVENT_COMBAT_LEAVE);

    if #switchQueue > 0 then
        c:RequeueFirst();
    elseif not c:IsSwitching() then
        c:UnlockUI();
    end
end

function c:IsInCombat()
    return c:ReadState(InCombatLockdown) == true or inCombat == true;
end

function c:IsDead()
    return c:ReadState(UnitIsDeadOrGhost, "player") == true;
end

function c:IsOnBattleground()
    return C_PvP ~= nil and c:ReadState(C_PvP.IsBattleground) == true;
end

-- channels do not count (as before)
function c:IsCastingSpell()
    return c:SafeCall(UnitCastingInfo, "player") ~= nil;
end

function c:SpellCastStart(spellId)
    -- remember the items before a cast that may enchant one of them
    if not c:IsInCombat() and not c:IsDead() and not c:IsSwitching() and not bankAction then
        lastGearAndBagsCache = c:CacheCurrentGearAndBags();
        enchantSnapshotPinned = true;
    end
end

function c:SpellCastSuccess(spellId)
    -- check for enchanted items
    if not c:IsInCombat() and not c:IsDead() then
        ScheduleEnchantCheck();
    end

    -- paladin auras that are not on the stance bar: the player's own aura cast (lastPaladinAura keeps tracking the
    -- stance bar, which then never changes)
    if spellId and (c:SafeCall(GetNumShapeshiftForms) or 0) == 0 then
        local auraSpellId = MatchSpellByName(c:GetPaladinAuras(), spellId);
        if auraSpellId then
            c:HandleEvent(c.EVENT_AURA_CHANGED, auraSpellId);
        end
    end

    c:SpellCastEnd();
end

-- druid forms, paladin auras and warrior stances, read from the stance bar
function c:SpellAuraApplied()
    c:CheckDruidFormChanged(c.EVENT_SHAPESHIFT_IN);
    c:CheckPaladinAuraChanged(c.EVENT_AURA_CHANGED);

    if not warriorStancePending then
        warriorStancePending = true;
        C_Timer.After(c:GetHomeLatency(SwitchDelay()) / 1000, function()
            warriorStancePending = false;
            local currentStance = GetCurrentWarriorStance();
            if currentStance ~= nil then
                local changed = lastWarriorStance ~= nil and currentStance ~= lastWarriorStance;
                lastWarriorStance = currentStance;
                if changed and currentStance ~= c.VALUE_NONE then
                    c:HandleEvent(c.EVENT_STANCE_CHANGED, currentStance);
                end
            end
        end);
    end
end

function c:SpellCastEnd()
    if not c:IsInCombat() and not c:IsDead() then
        C_Timer.After(c:GetHomeLatency(100 + SwitchDelay()) / 1000, function()
            if not c:IsSwitching() and not c:IsInCombat() and not c:IsCastingSpell() then
                if #switchQueue > 0 then
                    c:RequeueFirst();
                else
                    c:UnlockUI();
                end
            end
        end);
    end
end

function c:CheckDruidFormChanged(eventType)
    c:DebugPrint("CheckDruidFormChanged", eventType);

    if not druidShapeshiftPending then
        druidShapeshiftPending = true;

        C_Timer.After(c:GetHomeLatency(SwitchDelay()) / 1000, function()
            druidShapeshiftPending = false;
            local currentFormSpellId = c:GetCurrentDruidForm();
            if currentFormSpellId ~= nil then
                local previousFormSpellId = lastDruidForm;
                lastDruidForm = currentFormSpellId;
                if previousFormSpellId ~= nil and currentFormSpellId ~= previousFormSpellId then
                    c:DebugPrint("lastform, currentform: ", previousFormSpellId, currentFormSpellId);
                    c:HandleEvent(c.EVENT_SHAPESHIFT_OUT, previousFormSpellId);
                    c:HandleEvent(c.EVENT_SHAPESHIFT_IN, currentFormSpellId);
                end
            end
        end);
    end
end

function c:CheckPaladinAuraChanged(eventType)
    c:DebugPrint("CheckPaladinAuraChanged", eventType);

    if not paladinAuraPending then
        paladinAuraPending = true;

        C_Timer.After(c:GetHomeLatency(SwitchDelay()) / 1000, function()
            paladinAuraPending = false;
            local currentAuraSpellId = c:GetCurrentPaladinAura();
            if currentAuraSpellId ~= nil then
                local previousAuraSpellId = lastPaladinAura;
                lastPaladinAura = currentAuraSpellId;
                if previousAuraSpellId ~= nil and currentAuraSpellId ~= previousAuraSpellId then
                    c:DebugPrint("lastaura, currentaura: ", previousAuraSpellId, currentAuraSpellId);
                    c:HandleEvent(c.EVENT_AURA_CHANGED, currentAuraSpellId);
                end
            end
        end);
    end
end

function c:CheckForNewEnchantment()
    if not c:IsInCombat() and not c:IsDead() and not c:IsSwitching() and not bankAction and lastGearAndBagsCache then
        -- several items may have changed (e.g. a trade); each one found is recorded so the next one shows up
        for _ = 1, 20 do
            local cacheType, bagId, slotId, oldItemString, newItemString = c:GetFirstChangedItem(lastGearAndBagsCache);
            c:DebugPrint("CheckForNewEnchantment", cacheType, bagId, slotId, oldItemString, newItemString);

            -- check for equal item names in case player moved items while another player casted the enchantment - just to be sure
            if not oldItemString or not newItemString then
                return;
            end
            c:ReplaceItemStringInAllSets(oldItemString, newItemString, true);
            lastGearAndBagsCache[cacheType][bagId][slotId] = newItemString;
        end
    end
end

----- [ switch queue ] -----

local RunSwitchPass, DrainQueue;

local function ResolveSetName(setName)
    if setName == c.KEYWORD_PREVIOUS then
        return c:LoadPreviousSetName();
    end
    return setName;
end

local function AddToQueue(switchArgs)
    if not switchArgs[c.SWITCHARG_QUEUE_CAUSE] then
        if c:IsInCombat() then
            switchArgs[c.SWITCHARG_QUEUE_CAUSE] = QUEUE_CAUSE_COMBAT;
        elseif c:IsCastingSpell() then
            switchArgs[c.SWITCHARG_QUEUE_CAUSE] = QUEUE_CAUSE_ACTION;
        end
    end

    -- queue switch
    if switchArgs[c.SWITCHARG_FIRST] then
        if not switchQueue[1] or switchQueue[1][c.SWITCHARG_SETNAME] ~= switchArgs[c.SWITCHARG_SETNAME] then
            -- as first (priority) switch
            table.insert(switchQueue, 1, switchArgs);
            c:DebugPrint("Switch request queued first.");
        else
            switchQueue[1][c.SWITCHARG_QUEUE_CAUSE] = switchQueue[1][c.SWITCHARG_QUEUE_CAUSE] or
                                                          switchArgs[c.SWITCHARG_QUEUE_CAUSE];
            c:DebugPrint("Switch request already queued first. Nothing to do.");
        end
    elseif not c:IsSetLastQueued(switchArgs[c.SWITCHARG_SETNAME]) then
        -- normal queue
        table.insert(switchQueue, switchArgs);
        c:DebugPrint("Switch request queued.");
    else
        -- dont queue if already queued last
        c:DebugPrint("Switch request not queued.");
        return;
    end

    if switchArgs[c.SWITCHARG_NOTIFY] == nil or switchArgs[c.SWITCHARG_NOTIFY] then
        if switchArgs[c.SWITCHARG_SETNAME] == c.KEYWORD_PREVIOUS then
            switchArgs[c.SWITCHARG_SETNAME] = c:LoadPreviousSetName() or c.KEYWORD_PREVIOUS;
        end

        if GQ_OPTIONS[c.OPT_NOTIFYQUEUES] then
            c:Println(c:GetText("Switch to \"%s\" queued.", switchArgs[c.SWITCHARG_SETNAME]));
        end
    end
end

-- starts the next queued switch if nothing keeps it waiting (combat end and cast end resume the others)
DrainQueue = function()
    local nextSwitch = switchQueue[1];
    if nextSwitch and not c:IsSwitching() then
        if c:IsInCombat() and nextSwitch[c.SWITCHARG_QUEUE_CAUSE] == QUEUE_CAUSE_COMBAT then
            return;
        end
        if c:IsCastingSpell() and nextSwitch[c.SWITCHARG_QUEUE_CAUSE] == QUEUE_CAUSE_ACTION then
            return;
        end
        c:RequeueFirst();
    end
end

-- watch: the actions of the switch's last pass. The switching flag stays up until they have landed, so the switch's own
-- equip events are never auto-saved.
function c:FinishSwitch(switchArgs, watch)
    watch = watch or NewWatch();
    watch.final = true;
    AwaitLanding(watch, FINISH_FALLBACK_MS + SwitchDelay(), function()
        local setName = switchArgs[c.SWITCHARG_SETNAME];

        if actionBlocked then
            -- the game refused a weapon pickup in combat after the pass had finished
            actionBlocked = false;
            NotifyCombatEquipBlocked();
            AddToQueue({
                [c.SWITCHARG_SETNAME] = setName,
                [c.SWITCHARG_FIRST] = true,
                [c.SWITCHARG_QUEUE_CAUSE] = QUEUE_CAUSE_COMBAT,
                [c.SWITCHARG_NOTIFY] = false
            });
        elseif notifyInventoryError or switchArgs[c.SWITCHARG_QUEUE_CAUSE] == QUEUE_CAUSE_INVENTORY then
            c:Println(c:GetText("Action could not be finished. Switch to set \"%s\" incomplete.", setName));
            notifyInventoryError = false;
        elseif #switchQueue == 0 and c:IsSetComplete(setName) and GQ_OPTIONS[c.OPT_NOTIFYQUEUES] then
            if switchArgs[c.SWITCHARG_QUEUE_CAUSE] == QUEUE_CAUSE_COMBAT then
                c:Println(c:GetText("Combat ended. Switch to set \"%s\" complete.", setName));
            elseif switchArgs[c.SWITCHARG_QUEUE_CAUSE] == QUEUE_CAUSE_ACTION then
                c:Println(c:GetText("Action finished. Switch to set \"%s\" complete.", setName));
            end
        end

        c:ResetIgnoredSlots();
        c:LoadCloakAndHelmet(setName);
        c:UpdateBroker();
        c:UnlockUI();
        if c.paperDollFrame and c.paperDollFrame:IsVisible() then
            c:SetPaperDollLabelText();
            c:SetSlotInfo();
            c:ShowSlotStateBoxes();
            c:RefreshSetList(setName);
        end

        c:CloseContextMenu();
        PlaySound(1264);

        c:SetSwitching();
        DrainQueue();
    end);
end

function c:QueueSwitch(switchArgs)
    -- for simple set name string call
    if type(switchArgs) == "string" then
        switchArgs = {
            [c.SWITCHARG_SETNAME] = switchArgs
        };
    end
    if type(switchArgs) ~= "table" then
        return;
    end

    local setName = ResolveSetName(switchArgs[c.SWITCHARG_SETNAME]);
    c:DebugPrint("Switch request for:", switchArgs[c.SWITCHARG_SETNAME]);
    if not setName then
        -- "$PREVIOUS" without a previous set
        return;
    end

    switchArgs[c.SWITCHARG_ID] = switchArgs[c.SWITCHARG_ID] or GetNextSwitchId();
    if not c:IsSwitching() and not c:IsCastingSpell() and not c:IsDead() and
        (not c:IsInCombat() or (not c.combatEquipBlocked and c:AffectsOnlyWeapons(setName))) then
        -- switch immediately
        c:SwitchToSet(switchArgs);
        c:DebugPrint("Switch request applied immediately.");
        return;
    end

    AddToQueue(switchArgs);
end

function c:RequeueFirst()
    -- when combat ends etc.
    -- essentially equals "start working on queue again"
    local nextSet = table.remove(switchQueue, 1);
    if nextSet then
        nextSet[c.SWITCHARG_FIRST] = true;
        nextSet[c.SWITCHARG_NOTIFY] = false;
        c:QueueSwitch(nextSet);
    end
end

function c:IsSetQueued(setName)
    if setName then
        for _, switchArgs in ipairs(switchQueue) do
            if switchArgs[c.SWITCHARG_SETNAME] == setName then
                return true;
            end
        end
    end
end

function c:IsSetLastQueued(setName)
    if setName then
        local lastQueuedSet = switchQueue[#switchQueue];
        if lastQueuedSet and lastQueuedSet[c.SWITCHARG_SETNAME] == setName then
            return true;
        end
    end
end

----- [ equipping ] -----

local function NormalizeTarget(slotId, value)
    if slotId == INVSLOT_AMMO then
        return tonumber(value) or c.VALUE_NONE;
    end
    if c:IsEmpty(value) then
        return c.VALUE_NONE;
    end
    return c:GetItemString(value);
end

-- first copy of the item in the bags that is neither locked nor taken already; also tells whether a copy was busy
-- (lockedCells, optional, collects the locked copies)
local function FindBagCopy(itemString, usedCells, lockedCells)
    local busy;
    local list = c:FindItemInBags(itemString);
    if list then
        for _, location in ipairs(list) do
            local key = CellKey(location.bagId, location.slotId);
            if not usedCells[key] then
                if IsBagSlotLocked(location.bagId, location.slotId) then
                    busy = true;
                    if lockedCells then
                        lockedCells[key] = location;
                    end
                else
                    return location, key;
                end
            end
        end
    end
    return nil, nil, busy;
end

local function FindItemInBankUnused(itemString, usedCells)
    local bagId, slotId = c:FindItemInBank(itemString);
    if not bagId or not slotId or not usedCells or not usedCells[CellKey(bagId, slotId)] then
        return bagId, slotId;
    end
    -- identical copies: the first one is already on its way
    local wantedItemString = c:GetItemString(itemString);
    for _, bankBagId in ipairs(c:GetBankBagIds()) do
        for bankSlotId = 1, c:GetContainerNumSlots(bankBagId) do
            if not usedCells[CellKey(bankBagId, bankSlotId)] and
                c:GetItemString(c:GetContainerItemLink(bankBagId, bankSlotId)) == wantedItemString then
                return bankBagId, bankSlotId;
            end
        end
    end
end

local function PullItemFromBank(itemString, bagSpaceCache, usedCells)
    ClearCursor();

    local containerId, containerSlotId = FindItemInBankUnused(itemString, usedCells);
    if containerId and containerSlotId then
        if usedCells then
            usedCells[CellKey(containerId, containerSlotId)] = {
                bagId = containerId,
                slotId = containerSlotId
            };
        end
        c:SaveLastBankLocation(itemString, containerId, containerSlotId);
        c:PickupContainerItem(containerId, containerSlotId);
    end

    if CursorHasItem() then
        if c:PutInBag(bagSpaceCache, itemString) then
            return true;
        end
        ClearCursor();
    end
    return false;
end

-- One pass over the set's slots. Every slot and every item is moved at most once per pass, because the game locks both
-- until the server has answered; what is left (pending) is done by the next pass.
local function EquipSetPass(session)
    local setName, bagSpaceCache = session.setName, session.bagSpaceCache;
    local desiredSet = c:LoadSet(setName) or {};
    local partial = c:LoadPartialOption(setName);
    local ignoreManualItems = GQ_OPTIONS[c.OPT_IGNOREMANUALITEMS];
    local ammoNeeded = IsAmmoNeeded();

    -- targets[slot]: wanted item (VALUE_NONE = empty) of every active slot; ignored slots are never touched
    local targets, ignored = {}, {};
    for _, slotId in ipairs(c:GetSlotSwitchOrder(setName)) do
        if ignoreManualItems and c:IsIgnoredItem(slotId) then
            ignored[slotId] = true;
        elseif (not partial or c:LoadSlotState(slotId, setName)) and (slotId ~= INVSLOT_AMMO or ammoNeeded) then
            targets[slotId] = NormalizeTarget(slotId, desiredSet[slotId]);
        end
    end

    -- equipped[slot]: the gear as it will be once the actions of this pass are done
    local equipped = {};
    for slotId = 1, 19 do
        equipped[slotId] = c:GetItemString(slotId);
    end
    local mainHandWasTwoHand = IsTwoHandItem(equipped[INVSLOT_MAINHAND]);
    -- usedCells: cell key -> location the pass took an item from (true: tried, nothing picked up)
    local touched, usedCells, displaced = {}, {}, {};
    local pending = 0;
    local watch = NewWatch();

    -- a gear slot this pass has not touched but finds locked: the next pass waits for it as well
    local function IsLockedElsewhere(slotId)
        if IsSlotLocked(slotId) then
            watch.lockedSlots[slotId] = true;
            return true;
        end
        return false;
    end

    local function IsOnTarget(slotId, target)
        if slotId == INVSLOT_AMMO then
            -- ammo is never taken off
            return target == c.VALUE_NONE or c:Equals(c:GetItemString(INVSLOT_AMMO), target);
        end
        return equipped[slotId] == target;
    end

    -- another slot holding the item that does not need it: an active slot that changes anyway, or (allowInactive)
    -- a slot the set does not manage. Swapping puts this slot's item there, so that item must fit (main hand only
    -- weapons, two-handers); otherwise the item is freed once the other slot changes.
    local function FindDonor(slotId, itemString, allowInactive)
        local busy;
        for otherSlotId = 1, 19 do
            if otherSlotId ~= slotId and not ignored[otherSlotId] and equipped[otherSlotId] == itemString then
                local otherTarget = targets[otherSlotId];
                if (otherTarget ~= nil and otherTarget ~= itemString) or (otherTarget == nil and allowInactive) then
                    if touched[otherSlotId] or IsLockedElsewhere(otherSlotId) then
                        busy = true;
                    elseif not CanMoveToSlot(equipped[slotId], otherSlotId) then
                        if otherTarget ~= nil then
                            busy = true;
                        end
                    else
                        return otherSlotId;
                    end
                end
            end
        end
        return nil, busy;
    end

    local function ConsumeBagSpace()
        for _, bagId in ipairs(c:GetBagIds()) do
            if (bagSpaceCache[bagId] or 0) > 0 then
                bagSpaceCache[bagId] = bagSpaceCache[bagId] - 1;
                return;
            end
        end
    end

    -- The client itself moves the off hand into the bags when a two-hander is equipped, and a two-hander when an
    -- off-hand item is equipped. Returns that other weapon slot.
    local function GetDisplacedWeaponSlot(slotId, itemString)
        if slotId == INVSLOT_MAINHAND and equipped[INVSLOT_OFFHAND] ~= c.VALUE_NONE and IsTwoHandItem(itemString) then
            return INVSLOT_OFFHAND;
        elseif slotId == INVSLOT_OFFHAND and IsTwoHandItem(equipped[INVSLOT_MAINHAND]) then
            return INVSLOT_MAINHAND;
        end
    end

    local function SwapWith(slotId, donorSlotId)
        ClearCursor();
        PickupInventoryItem(donorSlotId);
        if not CursorHasItem() then
            watch.lockedSlots[donorSlotId] = true;
            return SLOT_WAIT;
        end
        if not CursorCanGoInSlot(slotId) then
            ClearCursor();
            return SLOT_FAILED;
        end
        PickupInventoryItem(slotId);
        if CursorHasItem() then
            ClearCursor();
            return SLOT_FAILED;
        end
        equipped[slotId], equipped[donorSlotId] = equipped[donorSlotId], equipped[slotId];
        touched[slotId], touched[donorSlotId] = true, true;
        return SLOT_OK;
    end

    local function EquipFromBag(slotId, itemString, location, key)
        local displacedSlotId = GetDisplacedWeaponSlot(slotId, itemString);
        if displacedSlotId and (touched[displacedSlotId] or IsLockedElsewhere(displacedSlotId)) then
            return SLOT_WAIT;
        end

        ClearCursor();
        c:PickupContainerItem(location.bagId, location.slotId);
        if not CursorHasItem() then
            usedCells[key] = true;
            watch.lockedCells[key] = location;
            return SLOT_WAIT;
        end
        usedCells[key] = location;
        if not CursorCanGoInSlot(slotId) then
            ClearCursor();
            return SLOT_FAILED;
        end
        -- the replaced item goes to the bag slot the new one came from
        PickupInventoryItem(slotId);
        if CursorHasItem() then
            ClearCursor();
            return SLOT_FAILED;
        end

        c:SaveLastBagLocation(itemString, location.bagId, location.slotId);
        if equipped[slotId] ~= c.VALUE_NONE then
            displaced[equipped[slotId]] = true;
        end
        equipped[slotId] = itemString;
        touched[slotId] = true;
        if displacedSlotId then
            displaced[equipped[displacedSlotId]] = true;
            equipped[displacedSlotId] = c.VALUE_NONE;
            touched[displacedSlotId] = true;
            ConsumeBagSpace();
        end
        return SLOT_OK;
    end

    local function Unequip(slotId)
        local itemString = equipped[slotId];
        local unequipped, nothingPickedUp = c:UnequipItem(slotId, bagSpaceCache, itemString);
        if unequipped then
            displaced[itemString] = true;
            equipped[slotId] = c.VALUE_NONE;
            touched[slotId] = true;
            return SLOT_OK;
        elseif nothingPickedUp then
            watch.lockedSlots[slotId] = true;
            return SLOT_WAIT;
        end
        return SLOT_ERROR;
    end

    local function ProcessSlot(slotId, target)
        if touched[slotId] or IsLockedElsewhere(slotId) then
            return SLOT_WAIT;
        end

        if target == c.VALUE_NONE then
            return Unequip(slotId);
        end

        if slotId == INVSLOT_AMMO then
            -- ammo workaround
            if c:SafeCall(C_Item.GetItemCount, target) == 0 then
                return SLOT_MISSING;
            end
            ClearCursor();
            c:EquipItemByName(target);
            watch.ammo = target;
            return SLOT_OK;
        end

        -- the client still sees the two-hander this pass replaces; equip the off hand once that swap is done
        if slotId == INVSLOT_OFFHAND and mainHandWasTwoHand and touched[INVSLOT_MAINHAND] then
            return SLOT_WAIT;
        end

        -- rings, trinkets and weapons that only change places
        local donorSlotId, donorBusy = FindDonor(slotId, target, false);
        if donorSlotId then
            return SwapWith(slotId, donorSlotId);
        end

        local location, key, copyBusy = FindBagCopy(target, usedCells, watch.lockedCells);
        if location then
            return EquipFromBag(slotId, target, location, key);
        end

        local inactiveDonorSlotId, inactiveDonorBusy = FindDonor(slotId, target, true);
        if inactiveDonorSlotId then
            return SwapWith(slotId, inactiveDonorSlotId);
        end

        if donorBusy or copyBusy or inactiveDonorBusy or displaced[target] then
            -- locked, or still on its way to the bags
            return SLOT_WAIT;
        end

        if c:IsAtBank() then
            -- item not in bag -> check in bank; the next pass equips it
            if PullItemFromBank(target, bagSpaceCache, session.usedBankCells) then
                return SLOT_WAIT;
            end
            return SLOT_ERROR;
        end

        return SLOT_MISSING;
    end

    -- outcome, number of slots left for the next pass, and what to wait for before that pass (see AwaitLanding)
    local function EndPass(outcome)
        for slotId in pairs(touched) do
            watch.slots[slotId] = equipped[slotId];
            switchEchoSlots[slotId] = equipped[slotId];
        end
        for _, cells in ipairs({usedCells, session.usedBankCells}) do
            for key, location in pairs(cells) do
                if type(location) == "table" then
                    watch.cells[key] = location;
                end
            end
        end
        return outcome, pending, watch;
    end

    for _, slotId in ipairs(c:GetSlotSwitchOrder(setName)) do
        local target = targets[slotId];
        if target ~= nil and not IsOnTarget(slotId, target) then
            if c:IsInCombat() and (c.combatEquipBlocked or not COMBAT_EQUIP_SLOTS[slotId]) then
                return EndPass(PASS_COMBAT);
            end
            if c:IsCastingSpell() then
                return EndPass(PASS_ACTION);
            end

            local result = ProcessSlot(slotId, target);
            if actionBlocked then
                return EndPass(PASS_BLOCKED);
            end
            if result == SLOT_ERROR then
                return EndPass(PASS_ERROR);
            elseif result == SLOT_WAIT or result == SLOT_FAILED then
                pending = pending + 1;
            elseif result == SLOT_OK then
                c:HighlightInventorySlot(slotId);
            end
        end
    end

    return EndPass(PASS_DONE);
end

local function InterruptSwitch(session, outcome, watch)
    local cause, notify = QUEUE_CAUSE_COMBAT, nil;
    if outcome == PASS_BLOCKED then
        actionBlocked = false;
        NotifyCombatEquipBlocked();
        notify = false;
    elseif outcome == PASS_ACTION then
        cause = QUEUE_CAUSE_ACTION;
        if GQ_OPTIONS[c.OPT_NOTIFYQUEUES] then
            c:Println(c:GetText(
                "Switching interrupted by action. It will be re-attempted once the action is finished."));
        end
    elseif GQ_OPTIONS[c.OPT_NOTIFYQUEUES] then
        c:Println(c:GetText("Switching interrupted by combat. It will be re-attempted once combat is over."));
    end

    AddToQueue({
        [c.SWITCHARG_SETNAME] = session.setName,
        [c.SWITCHARG_FIRST] = true,
        [c.SWITCHARG_QUEUE_CAUSE] = cause,
        [c.SWITCHARG_NOTIFY] = notify
    });

    -- the switching flag stays until the actions issued so far have landed (no auto-save of their equip events)
    watch.final = true;
    AwaitLanding(watch, FINISH_FALLBACK_MS + SwitchDelay(), function()
        c:SetSwitching();
        if not c:IsInCombat() then
            c:UnlockUI();
        end
        if c.paperDollFrame and c.paperDollFrame:IsVisible() then
            c:SetSlotInfo();
        end
        DrainQueue();
    end);
end

RunSwitchPass = function(session)
    session.pass = session.pass + 1;
    local outcome, pending, watch = EquipSetPass(session);

    if outcome == PASS_COMBAT or outcome == PASS_ACTION or outcome == PASS_BLOCKED then
        InterruptSwitch(session, outcome, watch);
        return;
    end

    if outcome == PASS_ERROR then
        notifyInventoryError = true;
    elseif pending > 0 then
        if session.pass < MAX_SWITCH_PASSES then
            local function NextPass()
                session.bagSpaceCache = c:GetBagSpace();
                RunSwitchPass(session);
            end
            if IsWatchEmpty(watch) then
                -- nothing moved and nothing locked (e.g. a refused move): retry after the delay
                C_Timer.After(c:GetHomeLatency(PASS_FALLBACK_MS + SwitchDelay()) / 1000, NextPass);
            else
                -- as soon as the server has answered this pass
                AwaitLanding(watch, PASS_FALLBACK_MS + SwitchDelay(), NextPass);
            end
            return;
        end
        notifyInventoryError = true;
    end

    if session.setName ~= c.KEYWORD_PREVIOUSEQUIPMENT then
        c:SaveCurrentSetName(session.setName);
    else
        c:SaveCurrentSetName(c:LoadPreviousSetName());
    end

    c:FinishSwitch(session.args, watch);
end

function c:SwitchToSet(switchArgs)
    if type(switchArgs) ~= "table" then
        return;
    end
    if c:IsSwitching() then
        AddToQueue(switchArgs);
        return;
    end

    local setName = ResolveSetName(switchArgs[c.SWITCHARG_SETNAME]);
    setName = setName and c:TableContains(c:LoadSetNames(true), setName, true); -- case insensitive
    if not setName then
        DrainQueue();
        return;
    end

    local freeSpace, neededSpace, bagSpaceCache = c:CheckNeccessaryBagSpace(setName);
    if freeSpace and neededSpace and neededSpace > freeSpace then
        c:Println(c:GetText("Not enough bag space. Current space: %s, needed: %s", freeSpace, neededSpace));
        c:RefreshSetList();
        DrainQueue();
        return;
    end

    switchArgs[c.SWITCHARG_SETNAME] = setName;
    c:SetSwitching(setName);
    actionBlocked = false;
    -- items move around now; an old snapshot would read as an enchant
    lastGearAndBagsCache = nil;
    enchantSnapshotPinned = false;
    if CloseMerchant then
        CloseMerchant();
    end
    c:LockUI(setName);
    PlaySound(1264);

    RunSwitchPass({
        args = switchArgs,
        setName = setName,
        pass = 0,
        bagSpaceCache = bagSpaceCache or c:GetBagSpace(),
        usedBankCells = {}
    });
end

-- Returns true, or false plus true when nothing could be picked up (empty or locked slot).
function c:UnequipItem(slotId, bagSpaceCache, itemString)
    ClearCursor();
    PickupInventoryItem(slotId);
    if not CursorHasItem() then
        return false, true;
    end
    if not c:PutInBag(bagSpaceCache, itemString) then
        -- the item goes back to its slot
        ClearCursor();
        c:Println(c:GetText("Not enough bag space. Switching aborted."));
        return false;
    end
    return true;
end

----- [ bags and bank ] -----

-- cursor item -> the bag it came from if that has space, else the first bag with space
function c:PutInBag(bagSpaceCache, itemString)
    if not CursorHasItem() then
        return false;
    end
    local tried = {};

    if itemString then
        local lastBagId = c:LoadLastBagLocation(itemString);
        if lastBagId and (bagSpaceCache[lastBagId] or 0) > 0 then
            tried[lastBagId] = true;
            if c:PutInBackpack(bagSpaceCache, lastBagId) then
                return true;
            end
        end
    end

    local bagIdsSorted = {};
    for bagId in pairs(bagSpaceCache) do
        table.insert(bagIdsSorted, bagId);
    end
    table.sort(bagIdsSorted);

    for _, bagId in ipairs(bagIdsSorted) do
        if not tried[bagId] and bagSpaceCache[bagId] > 0 and c:PutInBackpack(bagSpaceCache, bagId) then
            return true;
        end
    end
    return false;
end

function c:PutInBackpack(bagSpaceCache, bagId, slotId)
    if CursorHasItem() then
        if bagId == c.BACKPACK_CONTAINER then
            PutItemInBackpack();
        else
            PutItemInBag(c:ContainerIDToInventoryID(bagId));
        end

        if not CursorHasItem() then
            bagSpaceCache[bagId] = (bagSpaceCache[bagId] or 1) - 1;
            return true;
        end
    end
end

-- First free bank tab slot that is not already taken by an item moved in this action.
local function FindFreeBankSlot(preferredBagId, usedCells)
    local bankBagIds = c:GetBankBagIds();
    if preferredBagId and not tContains(bankBagIds, preferredBagId) then
        preferredBagId = nil;
    end

    local bagId, slotId = c:FindFreeContainerSlot(bankBagIds, preferredBagId);
    if not bagId or not slotId or not usedCells or not usedCells[CellKey(bagId, slotId)] then
        return bagId, slotId;
    end

    local orderedBagIds = {};
    if preferredBagId then
        table.insert(orderedBagIds, preferredBagId);
    end
    for _, bankBagId in ipairs(bankBagIds) do
        if bankBagId ~= preferredBagId then
            table.insert(orderedBagIds, bankBagId);
        end
    end
    for _, bankBagId in ipairs(orderedBagIds) do
        if c:IsGenericBag(bankBagId) then
            for bankSlotId = 1, c:GetContainerNumSlots(bankBagId) do
                if not usedCells[CellKey(bankBagId, bankSlotId)] and not c:GetContainerItemLink(bankBagId, bankSlotId) then
                    return bankBagId, bankSlotId;
                end
            end
        end
    end
end

-- cursor item -> the bank tab it came from if that has space, else the first tab with space
function c:PutInBank(bankSpaceCache, itemString, usedCells)
    if not CursorHasItem() then
        return false;
    end

    local preferredBagId = itemString and c:LoadLastBankLocation(itemString);
    local bagId, slotId = FindFreeBankSlot(preferredBagId, usedCells);
    if not bagId or not slotId then
        return false;
    end

    c:PickupContainerItem(bagId, slotId);
    if CursorHasItem() then
        return false;
    end

    if usedCells then
        usedCells[CellKey(bagId, slotId)] = true;
    end
    if bankSpaceCache and bankSpaceCache[bagId] then
        bankSpaceCache[bagId] = bankSpaceCache[bagId] - 1;
    end
    return true;
end

function c:PushSetToBank(setName)
    if setName and not bankAction then
        local error = false;
        local freeSpace, items, bankSpaceCache = c:CheckNeccessaryPushSpace(setName);
        if not freeSpace or not items then
            return;
        end
        if freeSpace >= c:GetTableSize(items) then
            if CloseMerchant then
                CloseMerchant();
            end
            bankAction = "push";
            lastGearAndBagsCache = nil;
            local usedBagCells, usedBankCells = {}, {};
            for slotId, itemString in pairs(items) do
                if not c:IsEmpty(itemString) and (not c:LoadPartialOption(setName) or c:LoadSlotState(slotId, setName)) and
                    not c:IsSetCurrentSetItem(itemString) then

                    ClearCursor();
                    if c:IsSetItemOnSlot(slotId, itemString) then
                        PickupInventoryItem(slotId);
                    else
                        local location, key = FindBagCopy(itemString, usedBagCells);
                        if location then
                            usedBagCells[key] = true;
                            c:PickupContainerItem(location.bagId, location.slotId);
                        end
                    end

                    if not (CursorHasItem() and c:PutInBank(bankSpaceCache, itemString, usedBankCells)) then
                        ClearCursor();
                        c:Println(c:GetText("%s could not be found or pushed to bank.", c:GetItemLink(itemString)));
                        error = true;
                    end
                end
            end

            C_Timer.After(c:GetLatency(1000 + SwitchDelay()) / 1000, function()
                c:SetSlotInfo();
                bankAction = nil;
            end);

            if error then
                c:Println(c:GetText("Set \"%s\" was incompletely pushed to bank.", setName));
            end

            ClearCursor();
            return not error;
        else
            c:Println(c:GetText("Not enough bank space to push \"%s\" to bank. Free: %s, needed: %s.", setName,
                freeSpace, c:GetTableSize(items)));
        end
    end
end

function c:PullSetFromBank(setName)
    if setName and not bankAction then
        local error = false;
        local freeSpace, items, bagSpaceCache = c:CheckNeccessaryPullSpace(setName);
        if not freeSpace or not items then
            return;
        end
        if freeSpace >= c:GetTableSize(items) then
            if CloseMerchant then
                CloseMerchant();
            end
            bankAction = "pull";
            lastGearAndBagsCache = nil;
            local usedBankCells = {};
            for slotId, itemString in pairs(items) do
                if not c:IsEmpty(itemString) and (not c:LoadPartialOption(setName) or c:LoadSlotState(slotId, setName)) then

                    if not PullItemFromBank(itemString, bagSpaceCache, usedBankCells) then
                        c:Println(c:GetText("%s could not be found or pulled from bank.", c:GetItemLink(itemString)));
                        error = true;
                    end
                end
            end

            C_Timer.After(c:GetLatency(1000 + SwitchDelay()) / 1000, function()
                c:SetSlotInfo();
                bankAction = nil;
            end);

            if error then
                c:Println(c:GetText("Set \"%s\" was incompletely pulled from bank.", setName));
            end

            ClearCursor();
            return not error;
        else
            c:Println(c:GetText("Not enough bag space to pull \"%s\" from bank. Free: %s, needed: %s.", setName,
                freeSpace, c:GetTableSize(items)));
        end
    end
end

function c:GetItemFromBank(itemString, bagSpaceCache)
    return PullItemFromBank(itemString, bagSpaceCache or c:GetBagSpace());
end
