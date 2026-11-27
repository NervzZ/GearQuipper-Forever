-- scope stuff
gearquipper = gearquipper or {};
local c = gearquipper;

----- [ general ] -----

-- character fields
local FIELD_CURRENTSET = "FIELD_CURRENTSET";
local FIELD_LASTSET = "FIELD_LASTSET";
local FIELD_SETS = "FIELD_SETS";
local FIELD_EVENTS = "FIELD_EVENTS";
local FIELD_EVENTS_ENABLED = "FIELD_EVENTS_ENABLED";
local FIELD_INVENTORY = "FIELD_INVENTORY";
local FIELD_BANK = "FIELD_BANK";
local FIELD_IGNOREDSLOTS = "FIELD_IGNOREDSLOTS";
local FIELD_COMPARISON_SETNAME = "FIELD_COMPARISON_SETNAME";

-- set fields
local FIELD_SHOWCLOAK = "FIELD_SHOWCLOAK";
local FIELD_SHOWHELMET = "FIELD_SHOWHELMET";
local FIELD_SLOTS = "FIELD_SLOTS";
local FIELD_SLOTSTATES = "FIELD_SLOTSTATES";

-- additional set fields
local FIELD_AFFECTS_HELMET = "FIELD_AFFECTS_HELMET";
local FIELD_AFFECTS_CLOAK = "FIELD_AFFECTS_CLOAK";

local FIELD_OPT_PARTIAL = "FIELD_OPT_PARTIAL";
local FIELD_COLOR = "FIELD_COLOR"; -- "rrggbb"

-- set fields written by GearQuipper v54 for features that do not exist on Forever (action bars, key bindings)
local OBSOLETE_SET_FIELDS = {"FIELD_ACTIONSLOTS", "FIELD_OPT_ACTIONSLOTS", "FIELD_KEYBINDINGS"};

-- misc fields
c.FIELD_ID = "FIELD_ID";
c.FIELD_TYPE = "FIELD_TYPE";
c.FIELD_SUBTYPE = "FIELD_SUBTYPE";
c.FIELD_SUBSUBTYPE = "FIELD_SUBSUBTYPE"; -- transient
c.FIELD_NAME = "FIELD_NAME";
c.FIELD_PVE = "FIELD_PVE";
c.FIELD_PVP = "FIELD_PVP";
c.FIELD_ENABLED = "FIELD_ENABLED";

function c:InitDatabase()
    GQ_DATA[c:GetRealmName()] = GQ_DATA[c:GetRealmName()] or {};
    GQ_DATA[c:GetRealmName()][c:GetCharName()] = GQ_DATA[c:GetRealmName()][c:GetCharName()] or {};
    GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS] =
        GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS] or {};
    GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_EVENTS] =
        GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_EVENTS] or {};
    GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_INVENTORY] =
        GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_INVENTORY] or {};
    GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_BANK] =
        GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_BANK] or {};
    GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_IGNOREDSLOTS] =
        GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_IGNOREDSLOTS] or {};

    -- every set needs its slot tables; sets saved by v54 may also carry data of dropped features
    local sets = GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS];
    for setName, set in pairs(sets) do
        if type(set) ~= "table" then
            sets[setName] = nil;
        else
            set[FIELD_SLOTS] = set[FIELD_SLOTS] or {};
            set[FIELD_SLOTSTATES] = set[FIELD_SLOTSTATES] or {};
            for _, field in ipairs(OBSOLETE_SET_FIELDS) do
                set[field] = nil;
            end
        end
    end
end

----- [ sets ] -----

function c:LoadSetNames(includePrevious)
    local setNames = {};
    for setName in pairs(GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS]) do
        if setName ~= c.KEYWORD_PREVIOUSEQUIPMENT or includePrevious then
            table.insert(setNames, setName);
        end
    end

    table.sort(setNames);
    return setNames;
end

function c:LoadCurrentSetName()
    return GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_CURRENTSET];
end

function c:LoadPreviousSetName()
    return GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_LASTSET];
end

function c:SaveCurrentSetName(setName)
    c:DebugPrint("SaveCurrentSetName", setName);
    if GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_CURRENTSET] ~= setName then
        GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_LASTSET] =
            GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_CURRENTSET];
        GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_CURRENTSET] = setName;
    end
end

function c:SaveSet(setName, notifyInChat)
    c:DebugPrint("SaveSet", setName);
    if setName then
        if notifyInChat == nil then
            notifyInChat = true;
        end

        GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName] =
            GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName] or {};
        GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_SLOTS] =
            GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_SLOTS] or {};
        GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_SLOTSTATES] =
            GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_SLOTSTATES] or {};

        for slotId, slotName in pairs(c:GetSlotInfo()) do
            local slotState = c:LoadSlotState(slotId, setName);
            if not c:LoadPartialOption(setName) or slotState == nil or slotState then
                c:SaveSlot(slotId, setName, notifyInChat);
            end
        end

        if setName ~= c.KEYWORD_PREVIOUSEQUIPMENT then
            if GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_OPT_PARTIAL] == nil then
                GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_OPT_PARTIAL] = false;
            end

            c:SaveCloakAndHelmet(setName, notifyInChat);
            c:SaveCurrentSetName(setName);

            c:RefreshSetList(setName);
            c:SetPaperDollLabelText();

            if notifyInChat then
                c:Println(c:GetText("Set \"%s\" has been saved.", setName));
            end
        else
            GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_OPT_PARTIAL] = false;
        end

        c:NotifyEventListeners(GQ_EVENT_SET_SAVED, setName);
    end
end

function c:LoadSet(setName)
    setName = setName or c:LoadCurrentSetName();
    if setName then
        local result = {};
        for slotId, slotName in pairs(c:GetSlotInfo()) do
            result[slotId] = c:LoadSlot(slotId, setName);
        end
        return result;
    end
end

function c:CreateDefaultSet()
    if #c:LoadSetNames() == 0 then
        c:SaveSet(DEFAULT, false);
    end
end

function c:CreatePreviousEquipmentSet()
    c:DebugPrint("CreatePreviousEquipmentSet");
    if not GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][c.KEYWORD_PREVIOUSEQUIPMENT] then
        c:SaveSet(c.KEYWORD_PREVIOUSEQUIPMENT, false);
    end
end

function c:RemoveSet(setName)
    c:DebugPrint("RemoveSet", setName);
    GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName] = nil;

    if c:LoadCurrentSetName() == setName then
        c:SaveCurrentSetName(nil);
    end

    -- remove the event bindings that switch to this set (backwards: DeleteEventBinding shifts the indices)
    local bindings = c:LoadEventBindings();
    for index = #bindings, 1, -1 do
        if bindings[index][c.FIELD_NAME] == setName then
            c:DeleteEventBinding(index);
        end
    end

    CloseDropDownMenus();
    c:RefreshSetList();
    c:RefreshEventEntries();
    c:SetPaperDollLabelText();
    c:HideSlotStateBoxes();
    c:NotifyEventListeners(GQ_EVENT_SET_REMOVED, setName, setName);
end

----- [ set colours ] -----

-- Light colours that read on dark tooltips and on the panel. No red (missing items, "Expected Item") and no gold
-- (default text); none is an item-quality colour.
local SET_COLOR_PALETTE = {
    {name = "Sky", hex = "66b3ff"},
    {name = "Teal", hex = "33d6c2"},
    {name = "Mint", hex = "7ff0a8"},
    {name = "Lime", hex = "c2f060"},
    {name = "Apricot", hex = "ff9e6b"},
    {name = "Pink", hex = "ff85c8"},
    {name = "Lavender", hex = "b8a1ff"},
    {name = "Silver", hex = "c9d1dc"}
};

function c:GetSetColorPalette()
    return SET_COLOR_PALETTE;
end

local function NormalizeHex(hex)
    if type(hex) == "string" and hex:match("^%x%x%x%x%x%x$") then
        return hex:lower();
    end
end

local function GetColorableSet(setName)
    if setName and setName ~= c.KEYWORD_PREVIOUSEQUIPMENT then
        return GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName];
    end
end

-- "rrggbb", or nil when the set has no (valid) colour
function c:LoadSetColor(setName)
    local set = GetColorableSet(setName);
    return set and NormalizeHex(set[FIELD_COLOR]);
end

-- hex "rrggbb" or nil (no colour); returns true when saved
function c:SaveSetColor(setName, hex)
    c:DebugPrint("SaveSetColor", setName, hex);
    local set = GetColorableSet(setName);
    if not set or (hex ~= nil and not NormalizeHex(hex)) then
        return false;
    end
    set[FIELD_COLOR] = NormalizeHex(hex);
    c:RefreshSetColors();
    return true;
end

function c:GetSetColorRGB(setName)
    local hex = c:LoadSetColor(setName);
    if hex then
        return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255;
    end
end

-- the set name wrapped in its colour; plain without one
function c:ColorizeSetName(setName)
    local hex = c:LoadSetColor(setName);
    if hex then
        return c:FormatTextWithColor(setName, hex);
    end
    return setName;
end

----- [ slots ] -----

function c:SaveSlot(slotId, setName, notifyInChat, itemString)
    c:DebugPrint("SaveSlot", slotId, setName, notifyInChat, itemString);
    setName = setName or c:LoadCurrentSetName();
    if notifyInChat == nil then
        notifyInChat = true;
    end

    if setName and GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName] then
        itemString = itemString or c:GetItemString(slotId);
        if GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_SLOTS][slotId] ~= itemString then
            GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_SLOTS][slotId] = itemString;
            if notifyInChat then
                c:NotifyInChat(c:GetText("<%s> Saved slot %s (%s): %s", setName, slotId, c:GetDisplaySlotName(slotId),
                    c:GetItemLink(itemString)));
            end

            c:NotifyEventListeners(GQ_EVENT_SLOT_SAVED, setName, slotId);
            return true;
        end
    end
end

function c:LoadSlot(slotId, setName)
    setName = setName or c:LoadCurrentSetName();
    if setName and GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName] then
        return GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_SLOTS][slotId];
    end
end

function c:LoadSlotState(slotId, setName)
    setName = setName or c:LoadCurrentSetName();
    if setName and GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName] then
        return GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_SLOTSTATES][slotId];
    end
end

function c:SaveSlotState(slotId, active, notify, setName)
    c:DebugPrint("SaveSlotState", slotId, active, notify, setName);
    setName = setName or c:LoadCurrentSetName();
    if setName and GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName] then
        GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_SLOTSTATES] =
            GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_SLOTSTATES] or {};
        if GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_SLOTSTATES][slotId] ~= active then
            GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_SLOTSTATES][slotId] = active;
            if notify then
                c:NotifyInChat(c:GetText("<%s> Saved slot state for %s (%s): %s", setName, slotId,
                    c:GetDisplaySlotName(slotId), c:BoolToText(active, c:GetText("active"), c:GetText("not active"))));
            end
        end

        c:NotifyEventListeners(GQ_EVENT_SLOT_STATE_SAVED, setName, slotId);
        return true;
    end
end

function c:ReplaceItemStringInAllSets(oldString, newString, notify)
    c:DebugPrint("ReplaceItemStringInAllSets", oldString, newString, notify);
    for _, setName in ipairs(c:LoadSetNames()) do
        for slotId, itemString in pairs(c:LoadSet(setName)) do
            if itemString == oldString and (not c:LoadPartialOption(setName) or c:LoadSlotState(slotId, setName)) then
                c:SaveSlot(slotId, setName, notify, newString);
            end
        end
    end
end

----- [ event ] -----

function c:SaveEventBinding(binding, index)
    c:DebugPrint("SaveEventBinding", binding, index);
    if index then
        GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_EVENTS][index] = binding;
    else
        if binding[c.FIELD_SUBSUBTYPE] then
            binding[c.FIELD_SUBTYPE] = binding[c.FIELD_SUBSUBTYPE];
            binding[c.FIELD_SUBSUBTYPE] = nil;
        end
        table.insert(GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_EVENTS], binding);
    end

    -- notification
    local event = c:GetEvents()[binding[c.FIELD_TYPE]];
    if event and binding[c.FIELD_SUBTYPE] and binding[c.FIELD_SUBTYPE]["mapID"] then
        -- zone
        event = event .. " (" .. c:GetZoneDisplayName(binding[c.FIELD_SUBTYPE]["mapID"]) .. ")";
    end

    local setName = binding[c.FIELD_NAME];
    if setName == c.KEYWORD_PREVIOUS then
        setName = c:GetText("[Previous set]");
    end
    c:NotifyInChat(string.format("%s %s -> %s", c:GetText("Saved event:"), event, setName));

    c:NotifyEventListeners(GQ_EVENT_EVENT_BINDING_SAVED, setName, event);
    return true;
end

function c:LoadEventBindings(filter)
    if filter then
        local result = {};
        for index, binding in ipairs(c:LoadEventBindings()) do
            local applies = true;
            for filterName, filterValue in pairs(filter) do
                if not c:Equals(filterValue, binding[filterName]) then
                    applies = false;
                    break
                end
            end
            if applies then
                result[index] = binding;
            end
        end
        return result;
    else
        return GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_EVENTS];
    end
end

function c:DeleteEventBinding(index)
    c:DebugPrint("DeleteEventBinding", index);
    if index and GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_EVENTS][index] then
        local binding = c:Deepcopy(GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_EVENTS][index]);
        table.remove(GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_EVENTS], index);

        -- notification
        local event = c:GetEvents()[binding[c.FIELD_TYPE]];
        if event and binding[c.FIELD_SUBTYPE] and binding[c.FIELD_SUBTYPE]["mapID"] then
            -- zone
            event = event .. " (" .. c:GetZoneDisplayName(binding[c.FIELD_SUBTYPE]["mapID"]) .. ")";
        end

        local setName = binding[c.FIELD_NAME];
        if setName == c.KEYWORD_PREVIOUS then
            setName = c:GetText("[Previous set]");
        end
        c:NotifyInChat(string.format("%s %s -> %s", c:GetText("Removed event:"), event or c:GetText("Deprecated event"),
            setName));

        c:NotifyEventListeners(GQ_EVENT_EVENT_BINDING_REMOVED, setName, event);
        return true;
    end
end

function c:BindingExists(binding)
    -- subsubtype gets persisted as subtype (existing bindings do not have a subsubtype)
    local setBindings = c:LoadEventBindings();
    if setBindings then
        for index, b in pairs(setBindings) do
            if b[c.FIELD_TYPE] == binding[c.FIELD_TYPE] then
                if (binding[c.FIELD_SUBSUBTYPE] == nil and c:Equals(b[c.FIELD_SUBTYPE], binding[c.FIELD_SUBTYPE])) or
                    (binding[c.FIELD_SUBSUBTYPE] ~= nil and c:Equals(b[c.FIELD_SUBTYPE], binding[c.FIELD_SUBSUBTYPE])) then
                    return true;
                end
            end
        end
    end
end

local function SetBindingEnabled(setName, value)
    c:DebugPrint("SetBindingEnabled", setName, value);
    local setBindings = c:LoadEventBindings();
    if setBindings then
        for index, binding in pairs(setBindings) do
            if binding[c.FIELD_NAME] == setName then
                GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_EVENTS][index][c.FIELD_ENABLED] = value;
            end
        end
    end
end

function c:EnableBindings(setName)
    c:DebugPrint("EnableBindings", setName);
    SetBindingEnabled(setName, true);
end

function c:DisableBindings(setName)
    c:DebugPrint("DisableBindings", setName);
    SetBindingEnabled(setName, false);
end

----- [ other ] -----

function c:SaveComparisonSetName(setName)
    GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_COMPARISON_SETNAME] = setName;
end

function c:LoadComparisonSetName()
    return GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_COMPARISON_SETNAME];
end

function c:SaveCloakAndHelmet(setName, notify)
    c:DebugPrint("SaveCloakAndHelmet", setName, notify);
    setName = setName or c:LoadCurrentSetName();
    if notify == nil then
        notify = true;
    end

    if setName and GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName] then
        if ShowingHelm() ~= GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_SHOWHELMET] then
            GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_SHOWHELMET] = ShowingHelm();
            if notify then
                c:NotifyInChat(string.format("<%s> %s %s", setName, c:GetText("Saved helmet visibility:"), c:BoolToText(
                    ShowingHelm(), c:GetText("visible"), c:GetText("not visible"))));
            end
        end

        if ShowingCloak() ~= GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_SHOWCLOAK] then
            GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_SHOWCLOAK] = ShowingCloak();
            if notify then
                c:NotifyInChat(string.format("<%s> %s %s", setName, c:GetText("Saved cloak visibility:"), c:BoolToText(
                    ShowingCloak(), c:GetText("visible"), c:GetText("not visible"))));
            end
        end
    end
end

function c:LoadCloakAndHelmet(setName)
    setName = setName or c:LoadCurrentSetName();
    if setName and GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName] then
        if c:GetAffectsHelmet(setName) and
            GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_SHOWHELMET] ~= nil then
            ShowHelm(GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_SHOWHELMET]);
        end
        if c:GetAffectsCloak(setName) and
            GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_SHOWCLOAK] ~= nil then
            ShowCloak(GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_SHOWCLOAK]);
        end
    end
end

function c:SetAffectsHelmet(value, setName, notify)
    c:DebugPrint("SaveAffectsHelmet", value, setName, notify);
    setName = setName or c:LoadCurrentSetName();
    if notify == nil then
        notify = true;
    end

    if setName and GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName] then
        GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_AFFECTS_HELMET] = value;
        if notify then
            c:NotifyInChat(string.format("<%s> %s %s", setName, c:GetText("Affects helmet visibility:"),
                c:BoolToText(value, YES, NO)));
        end
    end
end

function c:GetAffectsHelmet(setName)
    setName = setName or c:LoadCurrentSetName();
    if setName and GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName] then
        -- weird syntax for backwards compatibility
        if GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_AFFECTS_HELMET] == false then
            return false;
        end
        return true;
    end
end

function c:SetAffectsCloak(value, setName, notify)
    c:DebugPrint("SaveAffectsCloak", value, setName, notify);
    setName = setName or c:LoadCurrentSetName();
    if notify == nil then
        notify = true;
    end

    if setName and GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName] then
        GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_AFFECTS_CLOAK] = value;
        if notify then
            c:NotifyInChat(string.format("<%s> %s %s", setName, c:GetText("Affects cloak visibility:"),
                c:BoolToText(value, YES, NO)));
        end
    end
end

function c:GetAffectsCloak(setName)
    setName = setName or c:LoadCurrentSetName();
    if setName and GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName] then
        -- weird syntax for backwards compatibility
        if GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_AFFECTS_CLOAK] == false then
            return false;
        end
        return true;
    end
end

function c:IsEventsEnabled()
    if GQ_DATA[c:GetRealmName()][c:GetCharName()] then
        return GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_EVENTS_ENABLED];
    end
end

function c:SetEventsEnabled(value)
    if GQ_DATA[c:GetRealmName()][c:GetCharName()] then
        GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_EVENTS_ENABLED] = value;
    end
end

function c:LoadPartialOption(setName)
    setName = setName or c:LoadCurrentSetName();
    if setName and GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName] then
        return GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_OPT_PARTIAL];
    end
end

function c:SavePartialOption(setName, value)
    c:DebugPrint("SavePartialOption", setName, value);
    if setName and GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName] then
        GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_SETS][setName][FIELD_OPT_PARTIAL] = value;
    end
end

function c:SaveLastBagLocation(itemString, bagId, slotId)
    c:DebugPrint("SaveLastBagLocation", itemString, bagId, slotId);
    if itemString and bagId and slotId then
        GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_INVENTORY][itemString] = {
            [c.ITEM_BAG_ID] = bagId,
            [c.ITEM_SLOT_ID] = slotId
        };
    end
end

function c:LoadLastBagLocation(itemString)
    if itemString and GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_INVENTORY][itemString] then
        return GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_INVENTORY][itemString][c.ITEM_BAG_ID],
            GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_INVENTORY][itemString][c.ITEM_SLOT_ID];
    end
end

function c:SaveLastBankLocation(itemString, bagId, slotId)
    c:DebugPrint("SaveLastBankLocation", itemString, bagId, slotId);
    if itemString and bagId and slotId then
        GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_BANK][itemString] = {
            [c.ITEM_BAG_ID] = bagId,
            [c.ITEM_SLOT_ID] = slotId
        };
    end
end

function c:LoadLastBankLocation(itemString)
    if itemString and GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_BANK][itemString] then
        return GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_BANK][itemString][c.ITEM_BAG_ID],
            GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_BANK][itemString][c.ITEM_SLOT_ID];
    end
end

function c:ResetBagLocationIndex(characterName)
    if characterName then
        GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_INVENTORY] = {};
        return;
    end
    for characterName, _ in pairs(GQ_DATA[c:GetRealmName()]) do
        GQ_DATA[c:GetRealmName()][characterName][FIELD_INVENTORY] = {};
    end
end

function c:ResetBankLocationIndex(characterName)
    if characterName then
        GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_BANK] = {};
        return;
    end
    for characterName, _ in pairs(GQ_DATA[c:GetRealmName()]) do
        GQ_DATA[c:GetRealmName()][characterName][FIELD_BANK] = {};
    end
end

function c:AddIgnoredSlot(slotId)
    c:DebugPrint("AddIgnoredSlot", slotId);
    GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_IGNOREDSLOTS][slotId] = not c:IsSetItemOnSlot(slotId);
end

function c:GetIgnoredItems()
    return GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_IGNOREDSLOTS];
end

function c:IsIgnoredItem(slotId)
    return GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_IGNOREDSLOTS][slotId];
end

function c:ResetIgnoredSlots()
    c:DebugPrint("ResetIgnoredSlots");
    GQ_DATA[c:GetRealmName()][c:GetCharName()][FIELD_IGNOREDSLOTS] = {};
end
