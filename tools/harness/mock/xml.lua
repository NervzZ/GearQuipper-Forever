-- xml.lua: builds widgets from the addon's XML (parsed by run.py into {tag, attr, kids, text, line, file} tables).
-- Supports: virtual templates (incl. inheritance chains), $parent names, parentKey/parentArray, Size/Anchors,
-- Layers (Texture/FontString), Frames, ScrollChild, button textures, KeyValues, Attributes, Animations,
-- and <Scripts> (inline bodies compiled as functions, function="Global", method="Name", inherit=prepend/append).
-- OnLoad runs once the element and all its children are built (children first), like the client.
local H = ...;
local P = H.widgetState;

H.xml = {};

local REGION_TAGS = {Texture = "Texture", FontString = "FontString", MaskTexture = "MaskTexture", Line = "Line"};

-- Named parameters the client gives inline handlers (the rest stays reachable through ...).
local HANDLER_PARAMS = {
    OnClick = "self, button, down", PreClick = "self, button, down", PostClick = "self, button, down",
    OnDoubleClick = "self, button", OnEvent = "self, event", OnUpdate = "self, elapsed",
    OnMouseWheel = "self, delta", OnValueChanged = "self, value, userInput", OnEnter = "self, motion",
    OnLeave = "self, motion", OnMouseDown = "self, button", OnMouseUp = "self, button, upInside",
    OnKeyDown = "self, key", OnKeyUp = "self, key", OnChar = "self, text", OnTextChanged = "self, userInput",
    OnDragStart = "self, button", OnDragStop = "self", OnAttributeChanged = "self, name, value",
    OnSizeChanged = "self, width, height", OnVerticalScroll = "self, offset", OnHorizontalScroll = "self, offset",
    OnHyperlinkClick = "self, link, text, button", OnHyperlinkEnter = "self, link, text",
    OnScrollRangeChanged = "self, xrange, yrange", OnMinMaxChanged = "self, min, max",
    OnFinished = "self, requested", OnStop = "self, requested",
};

local function globalString(s)
    local v = rawget(_G, s);
    if type(v) == "string" then
        return v;
    end
    return s;
end

local function compileHandler(hnode)
    if hnode.compiled ~= nil then
        return hnode.compiled;
    end
    local params = (HANDLER_PARAMS[hnode.tag] or "self") .. ", ...";
    local src = string.rep("\n", (hnode.line or 1) - 1) .. "return function(" .. params .. ") " .. (hnode.text or "") ..
                    "\nend";
    local chunk, err = loadstring(src, "@" .. hnode.file);
    if not chunk then
        H.recordError(hnode.file .. " <" .. hnode.tag .. ">", {msg = err, trace = ""});
        hnode.compiled = false;
        return false;
    end
    hnode.compiled = chunk();
    return hnode.compiled;
end

local function scriptFunction(obj, hnode)
    local a = hnode.attr;
    if a["function"] then
        local fn = rawget(_G, a["function"]);
        if type(fn) ~= "function" then
            H.warn(hnode.file .. ": <" .. hnode.tag .. " function=\"" .. a["function"] .. "\"> not found at load time");
            return nil;
        end
        return fn;
    elseif a.method then
        local method = a.method;
        return function(self, ...)
            local m = self[method];
            if m then
                return m(self, ...);
            end
        end;
    end
    return compileHandler(hnode) or nil;
end

local function dims(node)
    local x, y = tonumber(node.attr.x), tonumber(node.attr.y);
    for _, k in ipairs(node.kids or {}) do
        if k.tag == "AbsDimension" or k.tag == "RelDimension" then
            x, y = tonumber(k.attr.x) or x, tonumber(k.attr.y) or y;
        end
    end
    return x, y;
end

local function applyAnchors(obj, node)
    for _, anchor in ipairs(node.kids or {}) do
        if anchor.tag == "Anchor" then
            local a = anchor.attr;
            local x, y = tonumber(a.x), tonumber(a.y);
            for _, k in ipairs(anchor.kids or {}) do
                if k.tag == "Offset" then
                    x, y = dims(k);
                end
            end
            local rel = a.relativeTo and rawget(_G, H.resolveName(a.relativeTo, P[obj].parent) or "") or nil;
            table.insert(P[obj].points, {a.point or "TOPLEFT", rel, a.relativePoint, x or 0, y or 0});
        end
    end
end

local function setKeys(obj, owner, a)
    if not owner then
        return;
    end
    if a.parentKey then
        owner[a.parentKey] = obj;
    end
    if a.parentArray then
        local arr = rawget(owner, a.parentArray) or {};
        owner[a.parentArray] = arr;
        arr[#arr + 1] = obj;
    end
end

local applyBody;

local function buildRegion(owner, rnode, layer)
    local cls = REGION_TAGS[rnode.tag] or "Texture";
    local region = H.newObject(cls, H.resolveName(rnode.attr.name, owner), owner, true);
    P[region].layer = layer;
    setKeys(region, owner, rnode.attr);
    if rnode.attr.inherits then
        H.applyRegionTemplates(region, rnode.attr.inherits);
    end
    applyBody(region, rnode);
    H.fireScript(region, "OnLoad");
    return region;
end

function H.xml.buildFrame(node, parent)
    local a = node.attr;
    if not H.FRAME_TYPES[node.tag] then
        H.warn(node.file .. ": unsupported frame element <" .. node.tag .. ">");
        return nil;
    end
    if a.parent then
        local p = rawget(_G, a.parent);
        if p then
            parent = p;
        else
            H.warn(node.file .. ": parent \"" .. a.parent .. "\" of " .. tostring(a.name) .. " does not exist");
        end
    end
    local obj = H.newObject(node.tag, H.resolveName(a.name, parent), parent);
    setKeys(obj, parent, a);
    H.applyIntrinsic(obj, node.tag);
    if a.inherits then
        H.applyTemplates(obj, a.inherits);
    end
    applyBody(obj, node);
    H.fireScript(obj, "OnLoad");
    return obj;
end

function H.applyXmlTemplate(obj, tnode)
    if tnode.attr.inherits then
        H.applyTemplates(obj, tnode.attr.inherits);
    end
    applyBody(obj, tnode);
end

local BUTTON_TEXTURES = {
    NormalTexture = "normalTexture", PushedTexture = "pushedTexture", DisabledTexture = "disabledTexture",
    HighlightTexture = "highlightTexture", CheckedTexture = "checkedTexture",
    DisabledCheckedTexture = "disabledCheckedTexture", ThumbTexture = "thumbTexture", BarTexture = "barTexture",
};

local IGNORED = {HitRectInsets = true, ResizeBounds = true, TitleRegion = true, NormalFont = true,
    HighlightFont = true, DisabledFont = true, PushedTextOffset = true, BarColor = true, Gradient = true,
    TexCoords = true, Shadow = true, Color = true, FontHeight = true, Inset = true, TextInsets = true};

function applyBody(obj, node)
    local a, p = node.attr, P[obj];
    if a.hidden == "true" then
        p.shown = false;
    elseif a.hidden == "false" then
        p.shown = true;
    end
    if a.id then
        p.id = tonumber(a.id) or p.id;
    end
    if a.mixin then
        for m in a.mixin:gmatch("[^,%s]+") do
            local mixin = rawget(_G, m);
            if type(mixin) == "table" then
                Mixin(obj, mixin);
            else
                H.warn(node.file .. ": mixin " .. m .. " not found");
            end
        end
    end
    if a.text then
        obj:SetText(globalString(a.text));
    end
    if a.checked == "true" then
        p.checked = true;
    end
    if a.setAllPoints == "true" then
        obj:SetAllPoints();
    end
    if a.frameStrata then
        p.strata = a.frameStrata;
    end
    if a.frameLevel then
        p.frameLevel = tonumber(a.frameLevel) or p.frameLevel;
    end
    if a.file then
        p.texture = a.file;
    end
    if a.atlas then
        p.atlas = a.atlas;
    end

    for _, kid in ipairs(node.kids or {}) do
        local tag = kid.tag;
        if tag == "Size" then
            local x, y = dims(kid);
            p.width, p.height = x or p.width, y or p.height;
        elseif tag == "Anchors" then
            applyAnchors(obj, kid);
        elseif tag == "Layers" then
            for _, layer in ipairs(kid.kids or {}) do
                for _, rnode in ipairs(layer.kids or {}) do
                    buildRegion(obj, rnode, layer.attr.level or "ARTWORK");
                end
            end
        elseif tag == "Frames" then
            for _, child in ipairs(kid.kids or {}) do
                H.xml.buildFrame(child, obj);
            end
        elseif tag == "ScrollChild" then
            for _, child in ipairs(kid.kids or {}) do
                local c = H.xml.buildFrame(child, obj);
                if c and obj.SetScrollChild then
                    obj:SetScrollChild(c);
                end
            end
        elseif tag == "Scripts" then
            for _, hnode in ipairs(kid.kids or {}) do
                if H.VALID_SCRIPTS[hnode.tag] then
                    local fn = scriptFunction(obj, hnode);
                    if fn then
                        H.setXmlScript(obj, hnode.tag, fn, hnode.attr.inherit);
                    end
                else
                    H.warn(hnode.file .. ":" .. tostring(hnode.line) .. ": <" .. hnode.tag ..
                               "> is not a script type of the modern client");
                end
            end
        elseif tag == "KeyValues" then
            for _, kv in ipairs(kid.kids or {}) do
                local v, t = kv.attr.value, kv.attr.type or "string";
                if t == "number" then
                    v = tonumber(v);
                elseif t == "boolean" then
                    v = v == "true";
                elseif t == "global" then
                    local g = rawget(_G, v);
                    if g == nil then
                        H.warn(kv.file .. ": KeyValue " .. kv.attr.key .. " refers to missing global " .. tostring(v));
                    end
                    v = g;
                elseif t == "nil" then
                    v = nil;
                end
                obj[kv.attr.key] = v;
            end
        elseif tag == "Attributes" then
            for _, at in ipairs(kid.kids or {}) do
                local v, t = at.attr.value, at.attr.type or "string";
                if t == "number" then
                    v = tonumber(v);
                elseif t == "boolean" then
                    v = v == "true";
                end
                p.attributes[at.attr.name] = v;
            end
        elseif BUTTON_TEXTURES[tag] then
            p[BUTTON_TEXTURES[tag]] = buildRegion(obj, kid, "ARTWORK");
        elseif tag == "ButtonText" or (tag == "FontString" and P[obj].type == "EditBox") then
            p.fontString = buildRegion(obj, {tag = "FontString", attr = kid.attr, kids = kid.kids, file = kid.file}, "ARTWORK");
        elseif tag == "Animations" then
            for _, gnode in ipairs(kid.kids or {}) do
                local group = obj:CreateAnimationGroup(gnode.attr.name);
                setKeys(group, obj, gnode.attr);
                for _, anode in ipairs(gnode.kids or {}) do
                    if anode.tag == "Scripts" then
                        applyBody(group, {attr = {}, kids = {anode}, file = gnode.file});
                    else
                        local anim = group:CreateAnimation(anode.tag, anode.attr.name);
                        anim:SetDuration(tonumber(anode.attr.duration) or 0);
                        setKeys(anim, group, anode.attr);
                    end
                end
            end
        elseif tag == "Backdrop" then
            H.warn(kid.file .. ": <Backdrop> element is ignored by the modern client (use BackdropTemplate + KeyValues)");
        elseif not IGNORED[tag] then
            H.warn(kid.file .. ": XML element <" .. tag .. "> not handled by the mock");
        end
    end
end

-- Top-level element of an XML file (Script/Include are handled by run.py, in document order).
function H.xml.loadTop(node)
    local a = node.attr;
    if a.virtual == "true" then
        if a.name then
            H.xmlTemplates[a.name] = node;
        end
        return;
    end
    if H.FRAME_TYPES[node.tag] then
        return H.xml.buildFrame(node, nil);
    elseif node.tag == "Font" or node.tag == "FontFamily" then
        if a.name then
            rawset(_G, a.name, H.newFont(a.name));
        end
    else
        H.warn(node.file .. ": unsupported top-level element <" .. node.tag .. ">");
    end
end
