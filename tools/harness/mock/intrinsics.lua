-- intrinsics.lua: region/child builders shared by the Blizzard template mocks, and the intrinsic frame types of the
-- forever branch: EventFrame / EventButton (CallbackRegistry + OnShow/OnHide/OnSizeChanged events), ItemButton
-- (Blizzard_ItemButton/Shared/ItemButtonTemplate.xml + ItemButtonMixin + the SetItemButton* globals) and the
-- DropdownButton structure (its mixin lives in menu.lua). Intrinsics are built by CreateFrame and by the XML loader
-- before any template, like in game.
local H = ...;
local P = H.widgetState;

---------------------------------------------------------------------------
-- builders (names and parentKeys follow the real XML)
---------------------------------------------------------------------------
local function nearestName(obj)
    while obj do
        local p = P[obj];
        if p and p.name then
            return p.name;
        end
        obj = p and p.parent;
    end
end

-- "$parentX" with no named ancestor gives an unnamed region (the mock never invents a global).
local function resolve(name, owner)
    if type(name) ~= "string" then
        return nil;
    end
    if name:find("%$[pP]arent") then
        local pn = nearestName(owner);
        if not pn then
            return nil;
        end
        name = name:gsub("%$[pP]arent", function()
            return pn;
        end);
    end
    return name;
end
H.resolveTemplateName = resolve;

local function place(obj, o)
    local p = P[obj];
    if o.size then
        p.width, p.height = o.size[1] or 0, o.size[2] or o.size[1] or 0;
    end
    if o.setAllPoints then
        p.points = {{"TOPLEFT", p.parent}, {"BOTTOMRIGHT", p.parent}};
    end
    for _, a in ipairs(o.anchors or {}) do
        table.insert(p.points, {a[1], a[2], a[3], a[4] or 0, a[5] or 0});
    end
    if o.hidden then
        p.shown = false;
    end
    if o.alpha then
        p.alpha = o.alpha;
    end
end

local function keys(obj, owner, o)
    if o.key then
        owner[o.key] = obj;
    end
    if o.array then
        local arr = rawget(owner, o.array) or {};
        owner[o.array] = arr;
        arr[#arr + 1] = obj;
    end
end

-- o: name ("$parentX"), key (parentKey), array (parentArray), layer, subLevel, file, atlas, color {r,g,b,a},
-- blend, size {w,h}, anchors {{point, relativeTo, relativePoint, x, y}}, setAllPoints, hidden, alpha.
function H.addTexture(owner, o)
    o = o or {};
    local t = H.newObject(o.mask and "MaskTexture" or "Texture", resolve(o.name, owner), owner, true);
    local p = P[t];
    p.layer, p.subLevel = o.layer or "ARTWORK", o.subLevel;
    if o.file then
        p.texture = o.file;
    elseif o.atlas then
        p.atlas = o.atlas;
    elseif o.color then
        p.color = o.color;
    end
    p.blendMode = o.blend;
    place(t, o);
    keys(t, owner, o);
    return t;
end

-- o: name, key, array, layer, font (font object name), text, justifyH, size, anchors, hidden.
function H.addFontString(owner, o)
    o = o or {};
    local fs = H.newObject("FontString", resolve(o.name, owner), owner, true);
    local p = P[fs];
    p.layer = o.layer or "ARTWORK";
    if o.font then
        p.fontObject = rawget(_G, o.font) or o.font;
    end
    if o.text then
        p.text = o.text;
    end
    place(fs, o);
    keys(fs, owner, o);
    return fs;
end

-- o: name, key, array, frameLevel, size, anchors, setAllPoints, hidden. The child's OnLoad runs here (before the
-- owner's, like XML children).
function H.addChild(owner, frameType, o, template)
    o = o or {};
    local c = H.newObject(frameType, resolve(o.name, owner), owner);
    keys(c, owner, o);
    H.applyIntrinsic(c, frameType);
    if template then
        H.applyTemplates(c, template);
    end
    place(c, o);
    if o.frameLevel then
        P[c].frameLevel = o.frameLevel;
    end
    H.fireScript(c, "OnLoad");
    return c;
end

-- Button state textures (NormalTexture / PushedTexture / HighlightTexture / DisabledTexture / CheckedTexture /
-- DisabledCheckedTexture), reachable through the getters and optionally a parentKey.
function H.addButtonTexture(button, which, o)
    o = o or {};
    o.layer = o.layer or (which == "highlightTexture" and "HIGHLIGHT" or "ARTWORK");
    local t = H.addTexture(button, o);
    P[button][which] = t;
    return t;
end

---------------------------------------------------------------------------
-- EventFrame / EventButton
---------------------------------------------------------------------------
EventFrameMixin = CreateFromMixins(CallbackRegistryMixin);
EventFrameMixin:GenerateCallbackEvents({"OnHide", "OnShow", "OnSizeChanged"});

function EventFrameMixin:OnLoad_Intrinsic()
    CallbackRegistryMixin.OnLoad(self);
end

function EventFrameMixin:OnShow_Intrinsic()
    self:TriggerEvent("OnShow");
end

function EventFrameMixin:OnHide_Intrinsic()
    self:TriggerEvent("OnHide");
end

function EventFrameMixin:OnSizeChanged_Intrinsic(width, height)
    self:TriggerEvent("OnSizeChanged", width, height);
end

EventButtonMixin = EventFrameMixin;

local function eventIntrinsic(obj)
    Mixin(obj, EventFrameMixin);
    H.setIntrinsicScript(obj, "OnLoad", obj.OnLoad_Intrinsic);
    H.setIntrinsicScript(obj, "OnShow", obj.OnShow_Intrinsic);
    H.setIntrinsicScript(obj, "OnHide", obj.OnHide_Intrinsic);
    H.setIntrinsicScript(obj, "OnSizeChanged", obj.OnSizeChanged_Intrinsic);
end
H.intrinsics.EventFrame = eventIntrinsic;
H.intrinsics.EventButton = eventIntrinsic;

---------------------------------------------------------------------------
-- ItemButton
---------------------------------------------------------------------------
ItemButtonMixin = {};

function ItemButtonMixin:PostOnLoad() end
function ItemButtonMixin:PostOnShow() end
function ItemButtonMixin:PostOnHide() end
function ItemButtonMixin:PostOnEvent() end
function ItemButtonMixin:UpdateItemContextMatching() end

function ItemButtonMixin:SetMatchesSearch(matchesSearch)
    self.matchesSearch = matchesSearch;
    self.searchOverlay:SetShown(not matchesSearch);
end

function ItemButtonMixin:GetMatchesSearch()
    return self.matchesSearch;
end

function ItemButtonMixin:Reset()
    self:SetItemButtonCount(nil);
    self:SetItemButtonTexture();
    self:SetItemButtonQuality();
    self.item = nil;
    self.itemLink = nil;
    self.itemLocation = nil;
    ClearItemButtonOverlay(self);
end

function ItemButtonMixin:SetItem(item)
    self.itemLocation = nil;
    self.item = item;
    if not item then
        self:Reset();
        return true;
    end
    local _, itemLink, itemQuality, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(item);
    self.itemLink = itemLink;
    self:SetItemButtonTexture(itemIcon);
    self:SetItemButtonQuality(itemQuality, itemLink);
    return true;
end

function ItemButtonMixin:GetItem()
    return self.item;
end

function ItemButtonMixin:GetItemLink()
    return self.itemLink;
end

function ItemButtonMixin:GetItemLocation()
    return self.itemLocation;
end

function ItemButtonMixin:SetItemButtonCount(count)
    SetItemButtonCount(self, count);
end

function ItemButtonMixin:GetItemButtonCount()
    return GetItemButtonCount(self);
end

-- In game the item button's SetAlpha fades its parts, not the button frame.
function ItemButtonMixin:SetAlpha(alpha)
    self.icon:SetAlpha(alpha);
    self.IconBorder:SetAlpha(alpha);
    self.IconOverlay:SetAlpha(alpha);
    self.Stock:SetAlpha(alpha);
    self.Count:SetAlpha(alpha);
end

function ItemButtonMixin:SetBagID(bagID)
    self.bagID = bagID;
end

function ItemButtonMixin:GetBagID()
    return self.bagID;
end

function ItemButtonMixin:GetSlotAndBagID()
    return self:GetID(), self:GetBagID();
end

function ItemButtonMixin:GetItemButtonIconTexture()
    return GetItemButtonIconTexture(self);
end

local function iconOf(button)
    return button.Icon or button.icon or (button:GetName() and _G[button:GetName() .. "IconTexture"]);
end

function GetItemButtonIconTexture(button)
    return iconOf(button);
end

local function setTextureBase(button, texture)
    local icon = iconOf(button);
    if icon then
        icon:SetShown(texture ~= nil);
        icon:SetTexture(texture);
        icon:SetTexCoord(0, 1, 0, 1);
    end
end

function ItemButtonMixin:SetItemButtonTexture(texture)
    setTextureBase(self, texture);
end

function SetItemButtonTexture(button, texture)
    if button then
        if button.SetItemButtonTexture then
            button:SetItemButtonTexture(texture);
        else
            setTextureBase(button, texture);
        end
    end
end

function ItemButtonMixin:SetItemButtonTextureVertexColor(r, g, b)
    local icon = iconOf(self);
    if icon then
        icon:SetVertexColor(r, g, b);
    end
end

function SetItemButtonTextureVertexColor(button, r, g, b)
    if button then
        if button.SetItemButtonTextureVertexColor then
            button:SetItemButtonTextureVertexColor(r, g, b);
        elseif iconOf(button) then
            iconOf(button):SetVertexColor(r, g, b);
        end
    end
end

function ItemButtonMixin:SetItemButtonBorderVertexColor(r, g, b)
    if self.IconBorder then
        self.IconBorder:SetVertexColor(r, g, b);
    end
end

function SetItemButtonBorderVertexColor(button, r, g, b)
    if button then
        if button.SetItemButtonBorderVertexColor then
            button:SetItemButtonBorderVertexColor(r, g, b);
        elseif button.IconBorder then
            button.IconBorder:SetVertexColor(r, g, b);
        end
    end
end

function SetItemButtonCount(button, count, abbreviate)
    if not button then
        return;
    end
    count = count or 0;
    button.count = count;
    local countString = button.Count or _G[button:GetName() .. "Count"];
    local minDisplayCount = button.minDisplayCount or 1;
    if count > minDisplayCount or (button.isBag and count > 0) then
        countString:SetText(count > (button.maxDisplayCount or 9999) and "*" or count);
        countString:SetTextColor(1, 1, 1);
        countString:Show();
    else
        countString:Hide();
    end
end

function GetItemButtonCount(button)
    return button.count;
end

function SetItemButtonDesaturated(button, desaturated)
    local icon = button and iconOf(button);
    if icon then
        icon:SetDesaturated(desaturated);
    end
end

function SetItemButtonNormalTextureVertexColor(button, r, g, b)
    if button then
        button:GetNormalTexture():SetVertexColor(r, g, b);
    end
end

local function clearOverlay(overlay)
    if overlay then
        overlay:SetVertexColor(1, 1, 1);
        overlay:SetAtlas(nil);
        overlay:SetTexture(nil);
        overlay:Hide();
    end
end

function ClearItemButtonOverlay(button)
    for _, key in ipairs({"IconOverlay", "IconOverlay2", "ProfessionQualityOverlay"}) do
        clearOverlay(button[key]);
    end
    button.isProfessionItem = false;
    button.isCraftedItem = false;
end

function SetItemButtonBorder(button, asset, isAtlas)
    if button then
        button.IconBorder:SetShown(asset ~= nil);
        if asset then
            if isAtlas then
                button.IconBorder:SetAtlas(asset);
            else
                button.IconBorder:SetTexture(asset);
            end
        end
    end
end

-- Mainline SetItemButtonQuality_Base (overlays for azerite/corrupted/conduit items are not modelled): a quality
-- with a bag colour shows the white icon frame tinted in that colour, anything else hides the border.
local function setQualityBase(button, quality, itemIDOrLink)
    ClearItemButtonOverlay(button);
    local color = quality and BAG_ITEM_QUALITY_COLORS[quality];
    if color then
        SetItemButtonBorder(button, [[Interface\Common\WhiteIconFrame]]);
        SetItemButtonBorderVertexColor(button, color.r, color.g, color.b);
    else
        SetItemButtonBorder(button);
    end
end

function ItemButtonMixin:SetItemButtonQuality(quality, itemIDOrLink)
    setQualityBase(self, quality, itemIDOrLink);
end

function SetItemButtonQuality(button, quality, itemIDOrLink, suppressOverlays, isBound, ignoreColorOverrides)
    if button then
        if button.SetItemButtonQuality then
            button:SetItemButtonQuality(quality, itemIDOrLink, suppressOverlays, isBound, ignoreColorOverrides);
        else
            setQualityBase(button, quality, itemIDOrLink);
        end
    end
end

H.intrinsics.ItemButton = function(b)
    local p = P[b];
    p.width, p.height = 37, 37;
    p.clicks = {"LeftButtonUp", "RightButtonUp"};
    b.showMatchHighlight = true;
    H.addTexture(b, {mask = true, key = "Mask", layer = "BORDER", file = "Interface\\Common\\common-iconmask",
        setAllPoints = true});
    H.addTexture(b, {name = "$parentIconTexture", key = "icon", layer = "BORDER"});
    H.addFontString(b, {name = "$parentCount", key = "Count", layer = "ARTWORK", font = "NumberFontNormal",
        hidden = true, anchors = {{"BOTTOMRIGHT", nil, nil, -5, 2}}});
    H.addFontString(b, {name = "$parentStock", key = "Stock", layer = "ARTWORK", font = "NumberFontNormalYellow",
        hidden = true, anchors = {{"TOPLEFT", nil, nil, 0, -2}}});
    H.addTexture(b, {name = "$parentSearchOverlay", key = "searchOverlay", layer = "OVERLAY", subLevel = 4,
        color = {0, 0, 0, 0.8}, setAllPoints = true, hidden = true});
    H.addTexture(b, {key = "ItemContextOverlay", layer = "OVERLAY", subLevel = 5, setAllPoints = true, hidden = true});
    H.addTexture(b, {key = "IconBorder", layer = "OVERLAY", file = "Interface\\Common\\WhiteIconFrame", hidden = true,
        size = {37, 37}, anchors = {{"CENTER"}}});
    H.addTexture(b, {key = "IconOverlay", layer = "OVERLAY", subLevel = 1, hidden = true, size = {37, 37},
        anchors = {{"CENTER"}}});
    H.addTexture(b, {key = "IconOverlay2", layer = "OVERLAY", subLevel = 2, hidden = true, size = {37, 37},
        anchors = {{"CENTER"}}});
    H.addButtonTexture(b, "normalTexture", {name = "$parentNormalTexture", key = "NormalTexture",
        file = "Interface\\Buttons\\UI-Quickslot2", size = {64, 64}, anchors = {{"CENTER", nil, nil, 0, -1}}});
    H.addButtonTexture(b, "pushedTexture", {key = "PushedTexture", file = "Interface\\Buttons\\UI-Quickslot-Depress"});
    H.addButtonTexture(b, "highlightTexture", {key = "HighlightTexture", file = "Interface\\Buttons\\ButtonHilight-Square",
        blend = "ADD"});
    Mixin(b, ItemButtonMixin);
    H.setIntrinsicScript(b, "OnLoad", b.PostOnLoad, "postcall");
    H.setIntrinsicScript(b, "OnShow", b.PostOnShow, "postcall");
    H.setIntrinsicScript(b, "OnHide", b.PostOnHide, "postcall");
    H.setIntrinsicScript(b, "OnEvent", b.PostOnEvent, "postcall");
end

---------------------------------------------------------------------------
-- DropdownButton (Blizzard_Menu/DropdownButton.xml): KeyValues + intrinsic scripts; DropdownButtonMixin is
-- defined in menu.lua and looked up when the frame is created.
---------------------------------------------------------------------------
H.intrinsics.DropdownButton = function(b)
    b.intrinsic = "DropdownButton";
    b.menuPoint, b.menuPointX, b.menuPointY, b.menuRelativePoint = "TOPLEFT", 0, 0, "BOTTOMLEFT";
    Mixin(b, DropdownButtonMixin);
    H.setIntrinsicScript(b, "OnLoad", DropdownButtonMixin.OnLoad_Intrinsic);
    H.setIntrinsicScript(b, "OnEnter", DropdownButtonMixin.OnEnter_Intrinsic);
    H.setIntrinsicScript(b, "OnMouseDown", DropdownButtonMixin.OnMouseDown_Intrinsic);
    H.setIntrinsicScript(b, "OnMouseWheel", DropdownButtonMixin.OnMouseWheel_Intrinsic);
end
