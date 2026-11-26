-- widgets.lua: widget objects (CreateFrame), script handlers, event registration, visibility.
-- A widget method the mock does not model is a harmless no-op (recorded in H.noopMethods) when it is a
-- documented widget method of the Forever client; any other missing key is nil, like in game (so
-- frame.SomeChildKey is nil unless built, and SetBackdrop is nil without BackdropTemplate).
local H = ...;

local P = {}; -- widget -> private state
H.widgetState = P;
H.noopMethods = {}; -- "Type:Method" -> count
H.allFrames = {};

local NOOP = function() end;

local function set(list)
    local s = {};
    for _, v in ipairs(list) do
        s[v] = true;
    end
    return s;
end

-- Script types that exist on the modern client (OnTooltipSetItem & co were removed in 10.0.2).
local VALID_SCRIPTS = set({"OnLoad", "OnShow", "OnHide", "OnEvent", "OnUpdate", "OnSizeChanged", "OnEnter", "OnLeave",
    "OnMouseDown", "OnMouseUp", "OnMouseWheel", "OnDragStart", "OnDragStop", "OnReceiveDrag", "OnKeyDown", "OnKeyUp",
    "OnChar", "OnAttributeChanged", "OnEnable", "OnDisable", "OnClick", "PreClick", "PostClick", "OnDoubleClick",
    "OnValueChanged", "OnMinMaxChanged", "OnTextChanged", "OnEnterPressed", "OnEscapePressed", "OnTabPressed",
    "OnSpacePressed", "OnEditFocusGained", "OnEditFocusLost", "OnCursorChanged", "OnTextSet", "OnHyperlinkClick",
    "OnHyperlinkEnter", "OnHyperlinkLeave", "OnScrollRangeChanged", "OnVerticalScroll", "OnHorizontalScroll",
    "OnTooltipCleared", "OnTooltipAddMoney", "OnTooltipSetDefaultAnchor", "OnPlay", "OnFinished", "OnStop", "OnLoop",
    "OnPause", "OnArrowPressed", "OnInputLanguageChanged", "OnMouseMotion", "OnGamePadButtonDown",
    "OnGamePadButtonUp", "OnGamePadStick", "OnColorSelect", "OnCooldownDone", "OnModelLoaded", "OnAnimFinished"});
H.VALID_SCRIPTS = VALID_SCRIPTS;

local DOCUMENTED_METHODS = H.api.widgetMethods;

local FRAME_TYPES = set({"Frame", "Button", "CheckButton", "EditBox", "ScrollFrame", "Slider", "StatusBar",
    "GameTooltip", "Cooldown", "Model", "PlayerModel", "DressUpModel", "ModelScene", "MessageFrame",
    "ScrollingMessageFrame", "SimpleHTML", "ColorSelect", "Minimap", "ItemButton", "DropdownButton"});
H.FRAME_TYPES = FRAME_TYPES;

---------------------------------------------------------------------------
-- classes
---------------------------------------------------------------------------
local M = {};   -- className -> methods (flattened)
local META = {};
local PARENT_CLASS = {};
H.widgetMethods = M;

local function makeMeta(className)
    local methods = M[className];
    META[className] = {
        __index = function(_, key)
            local m = methods[key];
            if m ~= nil then
                return m;
            end
            if DOCUMENTED_METHODS[key] then
                local k = className .. ":" .. key;
                H.noopMethods[k] = (H.noopMethods[k] or 0) + 1;
                return NOOP;
            end
            return nil;
        end
    };
end

local function class(name, parentName, methods)
    local flat = {};
    if parentName then
        for k, v in pairs(M[parentName]) do
            flat[k] = v;
        end
    end
    for k, v in pairs(methods) do
        flat[k] = v;
    end
    M[name] = flat;
    PARENT_CLASS[name] = parentName;
    makeMeta(name);
    return flat;
end
H.class = class;

-- Adds methods to a class (and every class that inherits it) after creation (e.g. GameTooltip in blizzui).
function H.extendClass(name, methods)
    for cls in pairs(M) do
        local c = cls;
        while c do
            if c == name then
                for k, v in pairs(methods) do
                    M[cls][k] = v;
                end
                break;
            end
            c = PARENT_CLASS[c];
        end
    end
end

local function isA(obj, typeName)
    local c = P[obj] and P[obj].type;
    while c do
        if c == typeName then
            return true;
        end
        c = PARENT_CLASS[c];
    end
    return false;
end

local function describe(obj)
    local p = P[obj];
    if not p then
        return tostring(obj);
    end
    return p.name or ("<unnamed " .. p.type .. ">");
end
H.describe = describe;

---------------------------------------------------------------------------
-- object creation
---------------------------------------------------------------------------
local function nearestName(obj)
    while obj do
        local p = P[obj];
        if p and p.name then
            return p.name;
        end
        obj = p and p.parent;
    end
    return nil;
end

function H.resolveName(name, parent)
    if type(name) ~= "string" then
        return nil;
    end
    if name:find("%$[pP]arent") then
        local pn = nearestName(parent) or "";
        name = name:gsub("%$[pP]arent", function()
            return pn;
        end);
    end
    return name;
end

local function setParentInternal(obj, parent)
    local p = P[obj];
    if p.parent then
        local list = P[p.parent][p.region and "regions" or "children"];
        for i, o in ipairs(list) do
            if o == obj then
                table.remove(list, i);
                break;
            end
        end
    end
    p.parent = parent;
    if parent then
        local pp = P[parent];
        if not pp then
            error("SetParent: parent is not a widget", 3);
        end
        local list = pp[p.region and "regions" or "children"];
        list[#list + 1] = obj;
    end
end

function H.newObject(className, name, parent, isRegion)
    local obj = {};
    P[obj] = {type = className, name = name, shown = true, children = {}, regions = {}, scripts = {}, hooks = {},
        events = {}, points = {}, attributes = {}, text = nil, checked = false, enabled = true, value = 0,
        minValue = 0, maxValue = 0, alpha = 1, width = 0, height = 0, id = 0, region = isRegion,
        frameLevel = 1, strata = "MEDIUM", scale = 1};
    setmetatable(obj, META[className]);
    if parent then
        setParentInternal(obj, parent);
    end
    if name then
        rawset(_G, name, obj);
    end
    if not isRegion then
        H.allFrames[#H.allFrames + 1] = obj;
    end
    return obj;
end

---------------------------------------------------------------------------
-- scripts
---------------------------------------------------------------------------
-- Runs a script handler and its hooks, each in its own error trap (like the client).
function H.fireScript(obj, scriptName, ...)
    local p = P[obj];
    if not p then
        return;
    end
    local where = describe(obj) .. ":" .. scriptName;
    if scriptName == "OnEvent" then
        where = where .. " " .. tostring((...));
    end
    local fn = p.scripts[scriptName];
    if fn then
        H.trap(where, fn, obj, ...);
    end
    local hooks = p.hooks[scriptName];
    if hooks then
        for _, hook in ipairs(hooks) do
            H.trap(where .. " (hook)", hook, obj, ...);
        end
    end
end

-- The mouse enters / leaves a frame: IsMouseOver follows, OnEnter / OnLeave fire (motion = true).
function H.mouseEnter(obj)
    P[obj].mouseOver = true;
    H.fireScript(obj, "OnEnter", true);
end
function H.mouseLeave(obj)
    P[obj].mouseOver = false;
    H.fireScript(obj, "OnLeave", true);
end

local function checkScript(obj, method, scriptName)
    if not VALID_SCRIPTS[scriptName] then
        error(string.format('%s:%s(): Doesn\'t have a "%s" script', describe(obj), method, tostring(scriptName)), 3);
    end
end

-- Sets a script handler from XML (keeps hooks; "inherit" prepend/append chains with the existing one).
function H.setXmlScript(obj, scriptName, fn, inherit)
    local p = P[obj];
    local old = p.scripts[scriptName];
    if old and inherit == "prepend" then
        p.scripts[scriptName] = function(...)
            fn(...);
            return old(...);
        end
    elseif old and inherit == "append" then
        p.scripts[scriptName] = function(...)
            old(...);
            return fn(...);
        end
    else
        p.scripts[scriptName] = fn;
    end
end

---------------------------------------------------------------------------
-- visibility
---------------------------------------------------------------------------
local function isVisible(obj)
    while obj do
        local p = P[obj];
        if not p.shown then
            return false;
        end
        obj = p.parent;
    end
    return true;
end
H.isVisible = isVisible;

local function propagate(obj, visible)
    H.fireScript(obj, visible and "OnShow" or "OnHide");
    for _, child in ipairs(P[obj].children) do
        if P[child].shown then
            propagate(child, visible);
        end
    end
end

local function setShown(obj, shown)
    local p = P[obj];
    shown = shown and true or false;
    if p.shown == shown then
        return;
    end
    local was = isVisible(obj);
    p.shown = shown;
    local now = isVisible(obj);
    if was ~= now and not p.region then
        propagate(obj, now);
    end
end

---------------------------------------------------------------------------
-- event registration
---------------------------------------------------------------------------
local registry = {}; -- event -> frames in registration order

local function register(frame, event, units, method)
    if type(event) ~= "string" then
        error(describe(frame) .. ":" .. method .. "(): Usage: " .. method .. "(event[, unit...])", 3);
    end
    local doc = H.api.events[event];
    if not doc and not H.extraEvents[event] then
        error(string.format('%s:%s(): Attempt to register unknown event "%s"', describe(frame), method, event), 3);
    end
    if doc and doc.flags and doc.flags:find("HasRestrictions") then
        H.recordError(describe(frame) .. ":" .. method,
            {msg = "registers restricted event " .. event .. " (HasRestrictions on Forever; addons must not use it)",
             trace = H.traceback("", 3)});
    end
    local p = P[frame];
    if not p.events[event] then
        local list = registry[event] or {};
        registry[event] = list;
        list[#list + 1] = frame;
    end
    p.events[event] = units or true;
    return true;
end

local function unregister(frame, event)
    local p = P[frame];
    if p.events[event] then
        p.events[event] = nil;
        local list = registry[event];
        for i, f in ipairs(list) do
            if f == frame then
                table.remove(list, i);
                break;
            end
        end
    end
end

function H.dispatch(event, ...)
    local list = registry[event];
    if not list then
        return;
    end
    local snapshot = {unpack(list)};
    local unit = ...;
    for _, frame in ipairs(snapshot) do
        local reg = P[frame].events[event];
        if reg and (reg == true or reg[unit]) then
            H.fireScript(frame, "OnEvent", event, ...);
        end
    end
end

function H.framesRegisteredFor(event)
    return registry[event] or {};
end

---------------------------------------------------------------------------
-- method tables
---------------------------------------------------------------------------
local function regionCommon()
    return {
        GetName = function(self)
            return P[self].name;
        end,
        GetDebugName = function(self)
            return describe(self);
        end,
        GetObjectType = function(self)
            return P[self].type;
        end,
        IsObjectType = function(self, t)
            return isA(self, t);
        end,
        GetParent = function(self)
            return P[self].parent;
        end,
        SetParent = function(self, parent)
            local was = isVisible(self);
            setParentInternal(self, parent);
            local now = isVisible(self);
            if was ~= now and not P[self].region then
                propagate(self, now);
            end
        end,
        IsForbidden = function()
            return false;
        end,
        IsProtected = function()
            return false, false;
        end,
        Show = function(self)
            setShown(self, true);
        end,
        Hide = function(self)
            setShown(self, false);
        end,
        SetShown = function(self, shown)
            setShown(self, shown);
        end,
        IsShown = function(self)
            return P[self].shown;
        end,
        IsVisible = function(self)
            return isVisible(self);
        end,
        SetPoint = function(self, point, relativeTo, relativePoint, x, y)
            if type(point) ~= "string" then
                error(describe(self) .. ":SetPoint(): Usage: SetPoint(point [, relativeTo [, relativePoint]] [, x, y])", 2);
            end
            if type(relativeTo) == "string" then
                relativeTo = _G[relativeTo];
            end
            local points = P[self].points;
            for i, pt in ipairs(points) do
                if pt[1] == point then
                    table.remove(points, i);
                    break;
                end
            end
            points[#points + 1] = {point, relativeTo, relativePoint, x, y};
        end,
        GetPoint = function(self, index)
            local pt = P[self].points[index or 1];
            if pt then
                return pt[1], pt[2], pt[3] or pt[1], pt[4] or 0, pt[5] or 0;
            end
        end,
        GetNumPoints = function(self)
            return #P[self].points;
        end,
        ClearAllPoints = function(self)
            P[self].points = {};
        end,
        SetAllPoints = function(self, relativeTo)
            P[self].points = {{"TOPLEFT", relativeTo}, {"BOTTOMRIGHT", relativeTo}};
        end,
        SetSize = function(self, w, h)
            P[self].width, P[self].height = w or 0, h or w or 0;
        end,
        GetSize = function(self)
            return P[self].width, P[self].height;
        end,
        SetWidth = function(self, w)
            P[self].width = w;
        end,
        GetWidth = function(self)
            return P[self].width;
        end,
        SetHeight = function(self, h)
            P[self].height = h;
        end,
        GetHeight = function(self)
            return P[self].height;
        end,
        SetAlpha = function(self, a)
            P[self].alpha = a;
        end,
        GetAlpha = function(self)
            return P[self].alpha;
        end,
        GetEffectiveAlpha = function(self)
            return P[self].alpha;
        end,
        SetScale = function(self, s)
            P[self].scale = s;
        end,
        GetScale = function(self)
            return P[self].scale;
        end,
        GetEffectiveScale = function(self)
            return P[self].scale;
        end,
        IsMouseOver = function(self)
            return P[self] ~= nil and P[self].mouseOver == true;
        end,
        GetCenter = function()
            return 0, 0;
        end,
        GetLeft = function()
            return 0;
        end,
        GetRight = function()
            return 0;
        end,
        GetTop = function()
            return 0;
        end,
        GetBottom = function()
            return 0;
        end,
        GetRect = function(self)
            return 0, 0, P[self].width, P[self].height;
        end,
        SetParentKey = function(self, key)
            local parent = P[self].parent;
            if parent then
                parent[key] = self;
            end
        end,
    };
end

class("Region", nil, regionCommon());

class("Texture", "Region", {
    SetTexture = function(self, tex)
        P[self].texture = tex;
        return true;
    end,
    GetTexture = function(self)
        return P[self].texture;
    end,
    SetAtlas = function(self, atlas)
        P[self].atlas = atlas;
        return true;
    end,
    GetAtlas = function(self)
        return P[self].atlas;
    end,
    SetColorTexture = function(self, r, g, b, a)
        P[self].color = {r, g, b, a};
    end,
    SetVertexColor = function(self, r, g, b, a)
        P[self].vertexColor = {r, g, b, a};
    end,
    GetVertexColor = function(self)
        local c = P[self].vertexColor or {1, 1, 1, 1};
        return c[1], c[2], c[3], c[4] or 1;
    end,
    SetDesaturated = function(self, v)
        P[self].desaturated = v;
    end,
    IsDesaturated = function(self)
        return P[self].desaturated and true or false;
    end,
    SetDrawLayer = function(self, layer)
        P[self].layer = layer;
    end,
    GetDrawLayer = function(self)
        return P[self].layer or "ARTWORK", 0;
    end,
});
class("MaskTexture", "Texture", {});
class("Line", "Texture", {});

class("FontString", "Region", {
    SetText = function(self, text)
        P[self].text = text ~= nil and tostring(text) or nil;
    end,
    GetText = function(self)
        return P[self].text;
    end,
    SetFormattedText = function(self, fmt, ...)
        P[self].text = string.format(fmt, ...);
    end,
    SetTextColor = function(self, r, g, b, a)
        P[self].textColor = {r, g, b, a or 1};
    end,
    GetTextColor = function(self)
        local c = P[self].textColor or {1, 0.82, 0, 1};
        return c[1], c[2], c[3], c[4];
    end,
    SetFontObject = function(self, font)
        P[self].fontObject = font;
    end,
    GetFontObject = function(self)
        return P[self].fontObject;
    end,
    SetFont = function(self, path, size, flags)
        P[self].font = {path, size, flags};
        return true;
    end,
    GetFont = function(self)
        local f = P[self].font or {"Fonts\\FRIZQT__.TTF", 12, ""};
        return f[1], f[2], f[3];
    end,
    GetStringWidth = function(self)
        return #(P[self].text or "") * 6;
    end,
    GetUnboundedStringWidth = function(self)
        return #(P[self].text or "") * 6;
    end,
    GetStringHeight = function()
        return 12;
    end,
    IsTruncated = function()
        return false;
    end,
});

local frameMethods = {
    SetScript = function(self, scriptName, fn)
        checkScript(self, "SetScript", scriptName);
        if fn ~= nil and type(fn) ~= "function" then
            error(describe(self) .. ":SetScript(): Usage: SetScript(\"type\", function)", 2);
        end
        P[self].scripts[scriptName] = fn;
        P[self].hooks[scriptName] = nil;
    end,
    GetScript = function(self, scriptName)
        checkScript(self, "GetScript", scriptName);
        return P[self].scripts[scriptName];
    end,
    HookScript = function(self, scriptName, fn)
        checkScript(self, "HookScript", scriptName);
        if type(fn) ~= "function" then
            error(describe(self) .. ":HookScript(): Usage: HookScript(\"type\", function)", 2);
        end
        local hooks = P[self].hooks[scriptName] or {};
        P[self].hooks[scriptName] = hooks;
        hooks[#hooks + 1] = fn;
    end,
    HasScript = function(self, scriptName)
        return VALID_SCRIPTS[scriptName] == true;
    end,
    RegisterEvent = function(self, event)
        return register(self, event, nil, "RegisterEvent");
    end,
    RegisterUnitEvent = function(self, event, ...)
        local units = {};
        for i = 1, select("#", ...) do
            local u = select(i, ...);
            if u then
                units[u] = true;
            end
        end
        return register(self, event, units, "RegisterUnitEvent");
    end,
    UnregisterEvent = function(self, event)
        unregister(self, event);
    end,
    UnregisterAllEvents = function(self)
        for event in pairs(P[self].events) do
            unregister(self, event);
        end
    end,
    IsEventRegistered = function(self, event)
        local reg = P[self].events[event];
        if not reg then
            return false;
        end
        if reg == true then
            return true;
        end
        local units = {};
        for u in pairs(reg) do
            units[#units + 1] = u;
        end
        return true, unpack(units);
    end,
    CreateTexture = function(self, name, layer, template)
        local tex = H.newObject("Texture", H.resolveName(name, self), self, true);
        P[tex].layer = layer;
        if template then
            H.applyTemplates(tex, template);
        end
        return tex;
    end,
    CreateMaskTexture = function(self, name, layer)
        return H.newObject("MaskTexture", H.resolveName(name, self), self, true);
    end,
    CreateLine = function(self, name, layer)
        return H.newObject("Line", H.resolveName(name, self), self, true);
    end,
    CreateFontString = function(self, name, layer, template)
        local fs = H.newObject("FontString", H.resolveName(name, self), self, true);
        P[fs].layer = layer;
        if template and H.xmlTemplates[template] then
            H.applyTemplates(fs, template);
        end
        return fs;
    end,
    CreateAnimationGroup = function(self, name, template)
        return H.newObject("AnimationGroup", H.resolveName(name, self), self, true);
    end,
    GetChildren = function(self)
        return unpack(P[self].children);
    end,
    GetNumChildren = function(self)
        return #P[self].children;
    end,
    GetRegions = function(self)
        return unpack(P[self].regions);
    end,
    GetNumRegions = function(self)
        return #P[self].regions;
    end,
    SetAttribute = function(self, name, value)
        P[self].attributes[name] = value;
        H.fireScript(self, "OnAttributeChanged", name, value);
    end,
    GetAttribute = function(self, name)
        return P[self].attributes[name];
    end,
    SetID = function(self, id)
        P[self].id = id;
    end,
    GetID = function(self)
        return P[self].id;
    end,
    SetFrameLevel = function(self, level)
        P[self].frameLevel = level;
    end,
    GetFrameLevel = function(self)
        return P[self].frameLevel;
    end,
    SetFrameStrata = function(self, strata)
        P[self].strata = strata;
    end,
    GetFrameStrata = function(self)
        return P[self].strata;
    end,
    EnableMouse = function(self, v)
        P[self].mouse = v;
    end,
    IsMouseEnabled = function(self)
        return P[self].mouse and true or false;
    end,
    IsEnabled = function(self)
        return P[self].enabled;
    end,
};

class("Frame", "Region", frameMethods);

local function buttonText(self)
    local p = P[self];
    if not p.fontString then
        p.fontString = H.newObject("FontString", nil, self, true);
    end
    return p.fontString;
end

local function textureSetter(field)
    return function(self, tex)
        if type(tex) == "table" and P[tex] then
            P[self][field] = tex;
        else
            local t = P[self][field] or H.newObject("Texture", nil, self, true);
            P[t].texture = tex;
            P[self][field] = t;
        end
    end, function(self)
        return P[self][field];
    end
end

local buttonMethods = {
    Click = function(self, button, down)
        local p = P[self];
        if not p.enabled then
            return;
        end
        button = button or "LeftButton";
        if p.type == "CheckButton" then
            p.checked = not p.checked;
        end
        H.fireScript(self, "PreClick", button, down);
        H.fireScript(self, "OnClick", button, down);
        H.fireScript(self, "PostClick", button, down);
    end,
    SetText = function(self, text)
        buttonText(self):SetText(text);
    end,
    GetText = function(self)
        return P[self].fontString and P[self].fontString:GetText();
    end,
    SetFormattedText = function(self, fmt, ...)
        buttonText(self):SetText(string.format(fmt, ...));
    end,
    GetFontString = function(self)
        return buttonText(self);
    end,
    SetFontString = function(self, fs)
        P[self].fontString = fs;
    end,
    GetTextWidth = function(self)
        return buttonText(self):GetStringWidth();
    end,
    Enable = function(self)
        if not P[self].enabled then
            P[self].enabled = true;
            H.fireScript(self, "OnEnable");
        end
    end,
    Disable = function(self)
        if P[self].enabled then
            P[self].enabled = false;
            H.fireScript(self, "OnDisable");
        end
    end,
    SetEnabled = function(self, v)
        if v then
            self:Enable();
        else
            self:Disable();
        end
    end,
    RegisterForClicks = function(self, ...)
        P[self].clicks = {...};
    end,
    ClearNormalTexture = function(self)
        P[self].normalTexture = nil;
    end,
    ClearPushedTexture = function(self)
        P[self].pushedTexture = nil;
    end,
    ClearHighlightTexture = function(self)
        P[self].highlightTexture = nil;
    end,
    ClearDisabledTexture = function(self)
        P[self].disabledTexture = nil;
    end,
};
buttonMethods.SetNormalTexture, buttonMethods.GetNormalTexture = textureSetter("normalTexture");
buttonMethods.SetPushedTexture, buttonMethods.GetPushedTexture = textureSetter("pushedTexture");
buttonMethods.SetHighlightTexture, buttonMethods.GetHighlightTexture = textureSetter("highlightTexture");
buttonMethods.SetDisabledTexture, buttonMethods.GetDisabledTexture = textureSetter("disabledTexture");
class("Button", "Frame", buttonMethods);
class("ItemButton", "Button", {});
class("DropdownButton", "Button", {});

local checkMethods = {
    SetChecked = function(self, v)
        P[self].checked = v and true or false;
    end,
    GetChecked = function(self)
        return P[self].checked;
    end,
};
checkMethods.SetCheckedTexture, checkMethods.GetCheckedTexture = textureSetter("checkedTexture");
checkMethods.SetDisabledCheckedTexture, checkMethods.GetDisabledCheckedTexture = textureSetter("disabledCheckedTexture");
class("CheckButton", "Button", checkMethods);

class("EditBox", "Frame", {
    SetText = function(self, text)
        P[self].text = tostring(text or "");
        H.fireScript(self, "OnTextChanged", false);
    end,
    GetText = function(self)
        return P[self].text or "";
    end,
    SetNumber = function(self, n)
        self:SetText(tostring(n));
    end,
    GetNumber = function(self)
        return tonumber(P[self].text) or 0;
    end,
    Insert = function(self, text)
        self:SetText((P[self].text or "") .. text);
    end,
    SetFocus = function(self)
        P[self].focus = true;
        H.fireScript(self, "OnEditFocusGained");
    end,
    ClearFocus = function(self)
        if P[self].focus then
            P[self].focus = false;
            H.fireScript(self, "OnEditFocusLost");
        end
    end,
    HasFocus = function(self)
        return P[self].focus and true or false;
    end,
    Enable = function(self)
        P[self].enabled = true;
    end,
    Disable = function(self)
        P[self].enabled = false;
    end,
    SetEnabled = function(self, v)
        P[self].enabled = v and true or false;
    end,
    GetMaxLetters = function(self)
        return P[self].maxLetters or 0;
    end,
    SetMaxLetters = function(self, n)
        P[self].maxLetters = n;
    end,
});

local function valueMethods()
    return {
        SetValue = function(self, v, userInput)
            local p = P[self];
            v = math.max(p.minValue, math.min(p.maxValue, tonumber(v) or 0));
            if v ~= p.value then
                p.value = v;
                H.fireScript(self, "OnValueChanged", v, userInput and true or false);
            end
        end,
        GetValue = function(self)
            return P[self].value;
        end,
        SetMinMaxValues = function(self, lo, hi)
            local p = P[self];
            p.minValue, p.maxValue = lo, hi;
            H.fireScript(self, "OnMinMaxChanged", lo, hi);
            if p.value < lo or p.value > hi then
                self:SetValue(p.value);
            end
        end,
        GetMinMaxValues = function(self)
            return P[self].minValue, P[self].maxValue;
        end,
        SetValueStep = function(self, step)
            P[self].step = step;
        end,
        GetValueStep = function(self)
            return P[self].step or 0;
        end,
        Enable = function(self)
            P[self].enabled = true;
        end,
        Disable = function(self)
            P[self].enabled = false;
        end,
        SetEnabled = function(self, v)
            P[self].enabled = v and true or false;
        end,
    };
end
local sliderMethods = valueMethods();
sliderMethods.SetThumbTexture, sliderMethods.GetThumbTexture = textureSetter("thumbTexture");
class("Slider", "Frame", sliderMethods);
local barMethods = valueMethods();
barMethods.SetStatusBarTexture, barMethods.GetStatusBarTexture = textureSetter("barTexture");
class("StatusBar", "Frame", barMethods);

class("ScrollFrame", "Frame", {
    SetScrollChild = function(self, child)
        P[self].scrollChild = child;
        if child and P[child].parent ~= self then
            setParentInternal(child, self);
        end
    end,
    GetScrollChild = function(self)
        return P[self].scrollChild;
    end,
    SetVerticalScroll = function(self, offset)
        P[self].vscroll = offset;
        H.fireScript(self, "OnVerticalScroll", offset);
    end,
    GetVerticalScroll = function(self)
        return P[self].vscroll or 0;
    end,
    SetHorizontalScroll = function(self, offset)
        P[self].hscroll = offset;
    end,
    GetHorizontalScroll = function(self)
        return P[self].hscroll or 0;
    end,
    GetVerticalScrollRange = function()
        return 0;
    end,
    GetHorizontalScrollRange = function()
        return 0;
    end,
});

for _, t in ipairs({"Cooldown", "Model", "ModelScene", "SimpleHTML", "ColorSelect", "Minimap"}) do
    class(t, "Frame", {});
end
class("PlayerModel", "Model", {});
class("DressUpModel", "PlayerModel", {});
class("MessageFrame", "Frame", {
    AddMessage = function(self, text)
        if P[self].chat then
            H.addChat(text);
        end
        P[self].lastMessage = text;
    end,
    Clear = NOOP,
});
class("ScrollingMessageFrame", "MessageFrame", {});
class("GameTooltip", "Frame", {}); -- filled in by blizzui.lua

class("AnimationGroup", "Region", {
    Play = function(self)
        P[self].playing = true;
        H.fireScript(self, "OnPlay");
        local duration = 0;
        for _, a in ipairs(P[self].anims or {}) do
            duration = math.max(duration, (P[a].duration or 0) + (P[a].delay or 0));
        end
        C_Timer.After(duration, function()
            if P[self].playing then
                P[self].playing = false;
                H.fireScript(self, "OnFinished", false);
            end
        end);
    end,
    Stop = function(self)
        if P[self].playing then
            P[self].playing = false;
            H.fireScript(self, "OnStop", true);
        end
    end,
    Finish = function(self)
        self:Stop();
    end,
    IsPlaying = function(self)
        return P[self].playing and true or false;
    end,
    CreateAnimation = function(self, animType, name)
        local a = H.newObject("Animation", H.resolveName(name, self), self, true);
        P[self].anims = P[self].anims or {};
        table.insert(P[self].anims, a);
        return a;
    end,
    SetScript = frameMethods.SetScript,
    GetScript = frameMethods.GetScript,
    HookScript = frameMethods.HookScript,
});
class("Animation", "Region", {
    SetDuration = function(self, d)
        P[self].duration = d;
    end,
    GetDuration = function(self)
        return P[self].duration or 0;
    end,
    SetStartDelay = function(self, d)
        P[self].delay = d;
    end,
    SetScript = frameMethods.SetScript,
    GetScript = frameMethods.GetScript,
    HookScript = frameMethods.HookScript,
});
-- regions also take scripts (OnLoad from XML etc.) through the same table
M.Region.SetScript, M.Region.GetScript, M.Region.HookScript = frameMethods.SetScript, frameMethods.GetScript,
    frameMethods.HookScript;
for _, cls in ipairs({"Texture", "MaskTexture", "Line", "FontString"}) do
    M[cls].SetScript, M[cls].GetScript, M[cls].HookScript = frameMethods.SetScript, frameMethods.GetScript,
        frameMethods.HookScript;
end

---------------------------------------------------------------------------
-- OnUpdate every simulated frame (visible frames only, like the client)
---------------------------------------------------------------------------
table.insert(H.frameHooks, function(dtMs)
    if dtMs <= 0 then
        return;
    end
    for _, frame in ipairs(H.allFrames) do
        local p = P[frame];
        if (p.scripts.OnUpdate or p.hooks.OnUpdate) and isVisible(frame) then
            H.fireScript(frame, "OnUpdate", dtMs / 1000);
        end
    end
end);

---------------------------------------------------------------------------
-- CreateFrame and templates
---------------------------------------------------------------------------
H.xmlTemplates = {};    -- virtual templates defined by the addon's XML
H.blizzTemplates = {};  -- Blizzard templates (Lua builders, see blizzui.lua)

function H.applyTemplates(obj, templates)
    for template in tostring(templates):gmatch("[^,%s]+") do
        local xml = H.xmlTemplates[template];
        local blizz = H.blizzTemplates[template];
        if xml then
            H.applyXmlTemplate(obj, xml);
        elseif blizz then
            blizz(obj);
        else
            H.warn("unknown template '" .. template .. "' (not defined by the addon and not mocked; may not exist on Forever)");
        end
    end
end

function CreateFrame(frameType, name, parent, template, id)
    if type(frameType) ~= "string" or not FRAME_TYPES[frameType] then
        error("CreateFrame: Unknown frame type '" .. tostring(frameType) .. "'", 2);
    end
    if parent ~= nil and (type(parent) ~= "table" or not P[parent]) then
        error("CreateFrame: parent must be a frame", 2);
    end
    local frame = H.newObject(frameType, H.resolveName(name, parent), parent);
    if id then
        P[frame].id = id;
    end
    if template then
        H.applyTemplates(frame, template);
        H.fireScript(frame, "OnLoad");
    end
    return frame;
end

function H.state(obj)
    return P[obj];
end
