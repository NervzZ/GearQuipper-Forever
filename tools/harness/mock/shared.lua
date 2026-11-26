-- shared.lua: Blizzard SharedXML utilities the modern templates are built on (ports of the forever branch:
-- Blizzard_SharedXMLBase/CallbackRegistry.lua, TableUtil, MathUtil, AnchorUtil, FunctionUtil). Global, like in game.
local H = ...;

function nop() end

MathUtil = {Epsilon = 0.000001};

function Round(value)
    if value < 0 then
        return math.ceil(value - 0.5);
    end
    return math.floor(value + 0.5);
end

function Clamp(value, minValue, maxValue)
    if value > maxValue then
        return maxValue;
    elseif value < minValue then
        return minValue;
    end
    return value;
end

function Saturate(value)
    return Clamp(value, 0, 1);
end

function ApproximatelyEqual(v1, v2, epsilon)
    return math.abs(v1 - v2) < (epsilon or MathUtil.Epsilon);
end

function WithinRange(value, minValue, maxValue)
    return value >= minValue and value <= maxValue;
end

function WithinRangeExclusive(value, minValue, maxValue)
    return value > minValue and value < maxValue;
end

function GenerateClosure(f, ...)
    local captured = H.pack(...);
    return function(...)
        local args = {};
        for i = 1, captured.n do
            args[i] = captured[i];
        end
        local n = captured.n;
        for i = 1, select("#", ...) do
            args[n + i] = select(i, ...);
        end
        return f(unpack(args, 1, n + select("#", ...)));
    end
end

function ipairs_reverse(tbl)
    local function iter(t, index)
        index = index - 1;
        if index > 0 then
            return index, t[index];
        end
    end
    return iter, tbl, #tbl + 1;
end

function tDeleteItem(tbl, item)
    local size = #tbl;
    local index = size;
    while index > 0 do
        if item == tbl[index] then
            table.remove(tbl, index);
        end
        index = index - 1;
    end
    return size - #tbl;
end

function CopyValuesAsKeys(tbl)
    local output = {};
    for _, value in ipairs(tbl) do
        output[value] = value;
    end
    return output;
end

EnumUtil = {
    MakeEnum = function(...)
        local enum = {};
        for i = 1, select("#", ...) do
            enum[select(i, ...)] = i;
        end
        return enum;
    end,
};

function CreateTableEnumerator(tbl, minIndex, maxIndex)
    minIndex = minIndex and (minIndex - 1) or 0;
    maxIndex = maxIndex or math.huge;
    local function Enumerator(t, index)
        index = index + 1;
        if index <= maxIndex then
            local value = t[index];
            if value ~= nil then
                return index, value;
            end
        end
    end
    return Enumerator, tbl, minIndex;
end

function CreateTableReverseEnumerator(tbl, minIndex, maxIndex)
    minIndex = minIndex or 1;
    maxIndex = (maxIndex or #tbl) + 1;
    local function Enumerator(t, index)
        index = index - 1;
        if index >= minIndex then
            local value = t[index];
            if value ~= nil then
                return index, value;
            end
        end
    end
    return Enumerator, tbl, maxIndex;
end

function secureexecuterange(tbl, func, ...)
    local keys = {};
    for k in pairs(tbl) do
        keys[#keys + 1] = k;
    end
    for _, k in ipairs(keys) do
        if tbl[k] ~= nil then
            func(k, tbl[k], ...);
        end
    end
end

function securecallmethod(object, methodName, ...)
    return object[methodName](object, ...);
end

---------------------------------------------------------------------------
-- CallbackRegistryMixin (owner semantics as in game: a table owner is passed as the first argument,
-- a generated numeric owner is not; capture arguments go before the event payload)
---------------------------------------------------------------------------
local ownerSeq = 0;

CallbackRegistryMixin = {};

function CallbackRegistryMixin:OnLoad()
    self.callbackTables = {};
end

function CallbackRegistryMixin:SetUndefinedEventsAllowed(allowed)
    self.isUndefinedEventAllowed = allowed;
end

function CallbackRegistryMixin:GenerateCallbackEvents(events)
    self.Event = self.Event or {};
    for _, event in ipairs(events) do
        self.Event[event] = event;
    end
end

local function checkEvent(self, event, method)
    if type(event) ~= "string" then
        error("CallbackRegistryMixin:" .. method .. " 'event' requires string type.", 3);
    end
    if not self.isUndefinedEventAllowed and not (self.Event and self.Event[event]) then
        error("CallbackRegistryMixin:" .. method .. " event '" .. event .. "' doesn't exist.", 3);
    end
end

function CallbackRegistryMixin:RegisterCallback(event, func, owner, ...)
    checkEvent(self, event, "RegisterCallback");
    if type(func) ~= "function" then
        error("CallbackRegistryMixin:RegisterCallback 'func' requires function type.", 2);
    end
    if owner == nil then
        ownerSeq = ownerSeq + 1;
        owner = ownerSeq;
    elseif type(owner) == "number" then
        error("CallbackRegistryMixin:RegisterCallback 'owner' as number is reserved internally.", 2);
    end
    if not self.callbackTables then
        -- in game this indexes nil: CallbackRegistryMixin.OnLoad never ran (e.g. an EventFrame template such as
        -- MinimalScrollBar created as a plain "Frame")
        error("CallbackRegistryMixin:RegisterCallback on an uninitialized registry (attempt to index field " ..
            "'callbackTables' (a nil value))", 2);
    end
    local list = self.callbackTables[event] or {};
    self.callbackTables[event] = list;
    local captured = H.pack(...);
    for i, entry in ipairs(list) do
        if entry.owner == owner then
            table.remove(list, i);
            break;
        end
    end
    list[#list + 1] = {owner = owner, func = func, captured = captured.n > 0 and captured or nil};
    return owner;
end

function CallbackRegistryMixin:RegisterCallbackWithHandle(event, func, owner, ...)
    owner = self:RegisterCallback(event, func, owner, ...);
    local registry = self;
    return {Unregister = function()
        registry:UnregisterCallback(event, owner);
    end};
end

function CallbackRegistryMixin:UnregisterCallback(event, owner)
    if owner == nil then
        error("CallbackRegistryMixin:UnregisterCallback 'owner' is required.", 2);
    end
    local list = self.callbackTables and self.callbackTables[event];
    if list then
        for i, entry in ipairs(list) do
            if entry.owner == owner then
                table.remove(list, i);
                return;
            end
        end
    end
end

function CallbackRegistryMixin:UnregisterEvents(eventTable)
    if self.callbackTables then
        for _, event in pairs(eventTable or self.Event or {}) do
            self.callbackTables[event] = nil;
        end
    end
end

function CallbackRegistryMixin:HasRegistrantsForEvent(event)
    local list = self.callbackTables and self.callbackTables[event];
    return list ~= nil and #list > 0;
end

function CallbackRegistryMixin:TriggerEvent(event, ...)
    checkEvent(self, event, "TriggerEvent");
    local list = self.callbackTables and self.callbackTables[event];
    if not list then
        return;
    end
    local snapshot = {unpack(list)};
    for _, entry in ipairs(snapshot) do
        local args = {};
        local n = 0;
        if type(entry.owner) ~= "number" then
            n = 1;
            args[1] = entry.owner;
        end
        if entry.captured then
            for i = 1, entry.captured.n do
                args[n + i] = entry.captured[i];
            end
            n = n + entry.captured.n;
        end
        local count = select("#", ...);
        for i = 1, count do
            args[n + i] = select(i, ...);
        end
        entry.func(unpack(args, 1, n + count));
    end
end

---------------------------------------------------------------------------
-- AnchorUtil
---------------------------------------------------------------------------
AnchorMixin = {};

function AnchorMixin:Init(point, relativeTo, relativePoint, x, y)
    self:Set(point, relativeTo, relativePoint, x, y);
end

function AnchorMixin:Set(point, relativeTo, relativePoint, x, y)
    self.point = point;
    self.relativeTo = relativeTo;
    self.relativePoint = relativePoint;
    self.x = x or 0;
    self.y = y or 0;
end

function AnchorMixin:Get()
    return self.point, self.relativeTo, self.relativePoint or self.point, self.x, self.y;
end

function AnchorMixin:SetPoint(region, clearAllPoints)
    if clearAllPoints then
        region:ClearAllPoints();
    end
    local point, relativeTo, relativePoint, x, y = self:Get();
    region:SetPoint(point, relativeTo or region:GetParent(), relativePoint, x, y);
end

function CreateAnchor(point, relativeTo, relativePoint, x, y)
    return CreateAndInitFromMixin(AnchorMixin, point, relativeTo, relativePoint, x, y);
end

AnchorUtil = {CreateAnchor = CreateAnchor};

---------------------------------------------------------------------------
-- tooltips and top-level helpers used by Blizzard mixins
---------------------------------------------------------------------------
function GetAppropriateTooltip()
    return GameTooltip;
end

function GetAppropriateTopLevelParent()
    return UIParent;
end
