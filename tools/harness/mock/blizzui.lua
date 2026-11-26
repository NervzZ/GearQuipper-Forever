-- blizzui.lua: what Blizzard's FrameXML provides on Forever: constants and global strings, colours, fonts,
-- legacy templates (Lua builders; the modern ones are in templates.lua, scroll.lua and menu.lua), the character
-- sheet frames, GameTooltip + TooltipDataProcessor, StaticPopup, Settings, the legacy UIDropDownMenu, chat frames
-- and slash commands.
local H = ...;
local P = H.widgetState;

---------------------------------------------------------------------------
-- constants and global strings
---------------------------------------------------------------------------
WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC, WOW_PROJECT_CAMELOT = 1, 2, 18;
WOW_PROJECT_ID = WOW_PROJECT_CAMELOT;

INVSLOT_AMMO, INVSLOT_HEAD, INVSLOT_NECK, INVSLOT_SHOULDER, INVSLOT_BODY, INVSLOT_CHEST = 0, 1, 2, 3, 4, 5;
INVSLOT_WAIST, INVSLOT_LEGS, INVSLOT_FEET, INVSLOT_WRIST, INVSLOT_HAND = 6, 7, 8, 9, 10;
INVSLOT_FINGER1, INVSLOT_FINGER2, INVSLOT_TRINKET1, INVSLOT_TRINKET2, INVSLOT_BACK = 11, 12, 13, 14, 15;
INVSLOT_MAINHAND, INVSLOT_OFFHAND, INVSLOT_RANGED, INVSLOT_TABARD = 16, 17, 18, 19;
INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED, NUM_INVSLOTS = 1, 19, 19;
INVSLOTS_EQUIPABLE_IN_COMBAT = {[INVSLOT_MAINHAND] = true, [INVSLOT_OFFHAND] = true, [INVSLOT_RANGED] = true};
NUM_BAG_SLOTS, NUM_REAGENTBAG_SLOTS, NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4, 1, 5;
CONTAINER_BAG_OFFSET, ITEM_INVENTORY_BANK_BAG_OFFSET = 30, 5;
BACKPACK_CONTAINER, KEYRING_CONTAINER = 0, -1;
-- not defined on Forever: BANK_CONTAINER, NUM_BANKBAGSLOTS (tabbed bank)

local STRINGS = {
    ALWAYS = "Always", NEVER = "Never", YES = "Yes", NO = "No", EMPTY = "Empty", DEFAULT = "Default",
    APPLY = "Apply", CANCEL = "Cancel", SAVE = "Save", OKAY = "Okay", ACCEPT = "Accept", CLOSE = "Close",
    DELETE = "Delete", NONE = "None", NONE_KEY = "None", UNKNOWN = "Unknown", UNKNOWNOBJECT = "Unknown",
    ENABLE = "Enable", FILTER = "Filter",
    DISABLE = "Disable", ADD = "Add", REMOVE = "Remove", RESET = "Reset", OPTIONS = "Options",
    TALENT_SPEC_PRIMARY = "Primary", TALENT_SPEC_SECONDARY = "Secondary", DUAL_SPEC_PRIMARY = "Primary",
    DUAL_SPEC_SECONDARY = "Secondary", ITEM_UNIQUE_EQUIPPABLE = "Unique-Equipped", ITEM_UNIQUE = "Unique",
    INVTYPE_HEAD = "Head", INVTYPE_NECK = "Neck", INVTYPE_SHOULDER = "Shoulder", INVTYPE_BODY = "Shirt",
    INVTYPE_CHEST = "Chest", INVTYPE_ROBE = "Chest", INVTYPE_WAIST = "Waist", INVTYPE_LEGS = "Legs",
    INVTYPE_FEET = "Feet", INVTYPE_WRIST = "Wrist", INVTYPE_HAND = "Hands", INVTYPE_FINGER = "Finger",
    INVTYPE_TRINKET = "Trinket", INVTYPE_CLOAK = "Back", INVTYPE_WEAPON = "One-Hand", INVTYPE_SHIELD = "Off Hand",
    INVTYPE_2HWEAPON = "Two-Hand", INVTYPE_WEAPONMAINHAND = "Main Hand", INVTYPE_WEAPONOFFHAND = "Off Hand",
    INVTYPE_HOLDABLE = "Held In Off-hand", INVTYPE_RANGED = "Ranged", INVTYPE_RANGEDRIGHT = "Ranged",
    INVTYPE_THROWN = "Thrown", INVTYPE_RELIC = "Relic", INVTYPE_TABARD = "Tabard", INVTYPE_AMMO = "Ammo",
    INVTYPE_BAG = "Bag", INVTYPE_QUIVER = "Quiver",
    ERR_NOT_IN_COMBAT = "You can't do that while in combat", ERR_WRONG_SLOT = "Item can't go in that slot",
    ERR_ITEM_DOESNT_GO_INTO_BAG = "That item doesn't go in that container.", ERR_BAG_FULL = "That bag is full.",
    ERR_INV_FULL = "Inventory is full.", ERR_OBJECT_IS_BUSY = "That object is busy.",
    ERR_ITEM_UNIQUE_EQUIPPABLE = "You can't equip more of that.", ERR_ITEM_CANT_BE_EQUIPPED = "That item can't be equipped.",
    ERR_CLIENT_LOCKED_OUT = "You can't do that right now.",
};
for k, v in pairs(STRINGS) do
    _G[k] = v;
end

---------------------------------------------------------------------------
-- colours
---------------------------------------------------------------------------
local ColorMixin = {
    GetRGB = function(self)
        return self.r, self.g, self.b;
    end,
    GetRGBA = function(self)
        return self.r, self.g, self.b, self.a;
    end,
    GenerateHexColor = function(self)
        return string.format("ff%02x%02x%02x", self.r * 255, self.g * 255, self.b * 255);
    end,
    WrapTextInColorCode = function(self, text)
        return "|c" .. self:GenerateHexColor() .. tostring(text) .. "|r";
    end,
};
ColorMixin.GenerateHexColorMarkup = function(self)
    return "|c" .. self:GenerateHexColor();
end
function CreateColor(r, g, b, a)
    return Mixin({r = r, g = g, b = b, a = a or 1}, ColorMixin);
end
NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR = CreateColor(1, 0.82, 0), CreateColor(1, 1, 1);
GRAY_FONT_COLOR, RED_FONT_COLOR, GREEN_FONT_COLOR = CreateColor(0.5, 0.5, 0.5), CreateColor(1, 0.1, 0.1),
    CreateColor(0.1, 1, 0.1);
DISABLED_FONT_COLOR = CreateColor(0.5, 0.5, 0.5);
WHITE_FONT_COLOR, YELLOW_FONT_COLOR = CreateColor(1, 1, 1), CreateColor(1, 1, 0);
-- Blizzard_Colors (Mainline): bag/item-button border colours; Poor has none, so its border stays hidden
COMMON_GRAY_COLOR, UNCOMMON_GREEN_COLOR = CreateColor(0.65882, 0.65882, 0.65882), CreateColor(0.11765, 1, 0);
RARE_BLUE_COLOR, EPIC_PURPLE_COLOR = CreateColor(0, 0.43922, 0.86667), CreateColor(0.63922, 0.20784, 0.93333);
LEGENDARY_ORANGE_COLOR, ARTIFACT_GOLD_COLOR = CreateColor(1, 0.50196, 0), CreateColor(0.90196, 0.8, 0.50196);
HEIRLOOM_BLUE_COLOR = CreateColor(0, 0.8, 1);
BAG_ITEM_QUALITY_COLORS = {[1] = COMMON_GRAY_COLOR, [2] = UNCOMMON_GREEN_COLOR, [3] = RARE_BLUE_COLOR,
    [4] = EPIC_PURPLE_COLOR, [5] = LEGENDARY_ORANGE_COLOR, [6] = ARTIFACT_GOLD_COLOR, [7] = HEIRLOOM_BLUE_COLOR,
    [8] = HEIRLOOM_BLUE_COLOR};
ColorManager = {
    GetColorDataForBagItemQuality = function(quality)
        return BAG_ITEM_QUALITY_COLORS[quality];
    end,
    GetDefaultColorDataForBagItemQuality = function(quality)
        return BAG_ITEM_QUALITY_COLORS[quality];
    end,
};
LIST_DELIMITER = ", ";
TOOLTIP_DEFAULT_COLOR, TOOLTIP_DEFAULT_BACKGROUND_COLOR = CreateColor(1, 1, 1), CreateColor(0.09, 0.09, 0.19);
ITEM_QUALITY_COLORS = {};
for q = 0, 7 do
    local r, g, b, hex = C_Item.GetItemQualityColor(q);
    ITEM_QUALITY_COLORS[q] = {r = r, g = g, b = b, hex = "|c" .. hex, color = CreateColor(r, g, b)};
end
BACKDROP_TEXT_PANEL_0_16 = {bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeSize = 16};
BACKDROP_SLIDER_8_8 = {bgFile = "Interface\\Buttons\\UI-SliderBar-Background", edgeSize = 8};
BACKDROP_TOOLTIP_16_16_5555 = {bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeSize = 16};

---------------------------------------------------------------------------
-- fonts
---------------------------------------------------------------------------
H.class("Font", nil, {
    GetName = function(self)
        return P[self].name;
    end,
    SetFont = function(self, path, size, flags)
        P[self].font = {path, size, flags};
    end,
    GetFont = function(self)
        local f = P[self].font or {"Fonts\\FRIZQT__.TTF", 12, ""};
        return f[1], f[2], f[3];
    end,
    SetTextColor = function(self, r, g, b, a)
        P[self].textColor = {r, g, b, a};
    end,
    GetTextColor = function(self)
        local c = P[self].textColor or {1, 0.82, 0, 1};
        return c[1], c[2], c[3], c[4];
    end,
});
function H.newFont(name)
    return H.newObject("Font", name, nil, true);
end
function CreateFont(name)
    return H.newFont(name);
end
-- every font object of the Forever client (mock/fonts.lua)
for name in pairs(H.fontNames) do
    H.newFont(name);
end

---------------------------------------------------------------------------
-- Blizzard templates (only the ones that exist on Forever; children named like the real XML)
---------------------------------------------------------------------------
local T = H.blizzTemplates;

local function fs(frame, suffix, key)
    local name = frame:GetName() and (frame:GetName() .. suffix) or nil;
    local f = H.newObject("FontString", name, frame, true);
    if key then
        frame[key] = f;
    end
    return f;
end
local function tex(frame, suffix, key)
    local name = (suffix and frame:GetName()) and (frame:GetName() .. suffix) or nil;
    local t = H.newObject("Texture", name, frame, true);
    if key then
        frame[key] = t;
    end
    return t;
end
local function child(frame, frameType, suffix, key, template)
    local name = (suffix and frame:GetName()) and (frame:GetName() .. suffix) or nil;
    local c = CreateFrame(frameType, name, frame, template);
    if key then
        frame[key] = c;
    end
    return c;
end

BackdropTemplateMixin = {
    OnBackdropLoaded = function() end,
    OnBackdropSizeChanged = function() end,
    ApplyBackdrop = function() end,
    ClearBackdrop = function() end,
    SetBackdrop = function(self, info)
        self.backdropInfo = info;
    end,
    GetBackdrop = function(self)
        return self.backdropInfo;
    end,
    SetBackdropColor = function() end,
    GetBackdropColor = function()
        return 0, 0, 0, 1;
    end,
    SetBackdropBorderColor = function() end,
    GetBackdropBorderColor = function()
        return 1, 1, 1, 1;
    end,
};
T.BackdropTemplate = function(f)
    Mixin(f, BackdropTemplateMixin);
end
T.TooltipBackdropTemplate = T.BackdropTemplate;

-- legacy check button (UICheckButtonTemplate, the panel/close buttons and the modern templates: templates.lua)
local function checkButton(f)
    P[f].fontString = fs(f, "Text", "Text");
end
T.ChatConfigCheckButtonTemplate, T.ChatConfigBaseCheckButtonTemplate = checkButton, function() end;

T.BasicFrameTemplate = function(f)
    tex(f, nil, "Bg");
    tex(f, nil, "TitleBg");
    tex(f, nil, "TopTileStreaks");
    local title = fs(f, "TitleText", "TitleText");
    title:SetText("");
    child(f, "Button", "CloseButton", "CloseButton", "UIPanelCloseButton");
end
T.BasicFrameTemplateWithInset = function(f)
    T.BasicFrameTemplate(f);
    tex(f, nil, "InsetBg");
end

T.UIDropDownMenuTemplate = function(f)
    tex(f, "Left", "Left");
    tex(f, "Middle", "Middle");
    tex(f, "Right", "Right");
    fs(f, "Text", "Text");
    tex(f, "Icon", "Icon");
    child(f, "Button", "Button", "Button");
end

T.InputBoxTemplate = function(f)
    tex(f, "Left", "Left");
    tex(f, "Right", "Right");
    tex(f, "Middle", "Middle");
end
T.InputBoxInstructionsTemplate = function(f)
    T.InputBoxTemplate(f);
    fs(f, nil, "Instructions");
end

local function sliderWithLabels(f)
    fs(f, "Text", "Text");
    fs(f, "Low", "Low");
    fs(f, "High", "High");
    P[f].thumbTexture = tex(f, "Thumb", "Thumb");
end
T.UISliderTemplate = function(f)
    P[f].thumbTexture = tex(f, "Thumb", "Thumb");
end
T.UISliderTemplateWithLabels, T.OptionsSliderTemplate = sliderWithLabels, sliderWithLabels;

T.UIPanelScrollFrameTemplate = function(f)
    local bar = child(f, "Slider", "ScrollBar", "ScrollBar");
    child(bar, "Button", "ScrollUpButton", "ScrollUpButton");
    child(bar, "Button", "ScrollDownButton", "ScrollDownButton");
    P[bar].thumbTexture = tex(bar, "ThumbTexture", "ThumbTexture");
end

T.GameTooltipTemplate, T.SharedTooltipTemplate = function() end, function() end;

-- Secure action buttons: type "item" equips the item through the secure path (allowed in combat for weapons,
-- never blocked as an addon action); "macro" understands /equip and /equipslot lines.
local function secureAttr(self, name, button)
    local suffix = button == "RightButton" and "2" or (button == "MiddleButton" and "3" or "1");
    local a = P[self].attributes;
    local v = a[name .. suffix];
    if v == nil then
        v = a["*" .. name .. suffix];
    end
    if v == nil then
        v = a[name];
    end
    return v;
end
local function secureClick(self, button)
    local actionType = secureAttr(self, "type", button);
    H.secureCall = true;
    if actionType == "item" then
        local item = secureAttr(self, "item", button);
        if item then
            C_Item.EquipItemByName(item);
        end
    elseif actionType == "macro" then
        local text = secureAttr(self, "macrotext", button) or "";
        for line in text:gmatch("[^\n]+") do
            local slot, item = line:match("^/equipslot%s+(%d+)%s+(.+)$");
            if slot then
                C_Item.EquipItemByName(item, tonumber(slot));
            else
                item = line:match("^/equip%s+(.+)$");
                if item then
                    C_Item.EquipItemByName(item);
                end
            end
        end
    end
    H.secureCall = false;
end
T.SecureActionButtonTemplate = function(f)
    f:SetScript("OnClick", secureClick);
end
T.InsecureActionButtonTemplate = T.SecureActionButtonTemplate;
T.SecureHandlerBaseTemplate, T.SecureFrameTemplate = function() end, function() end;

---------------------------------------------------------------------------
-- frames of the default UI
---------------------------------------------------------------------------
local function frame(frameType, name, parent, hidden)
    local f = CreateFrame(frameType, name, parent);
    if hidden then
        P[f].shown = false;
    end
    return f;
end

UIParent = frame("Frame", "UIParent");
WorldFrame = frame("Frame", "WorldFrame");
-- Camelot CharacterFrame (Blizzard_UIPanels_Game/Camelot/CharacterFrame.xml): panes + side mode tabs
CharacterFrame = frame("Frame", "CharacterFrame", UIParent, true);
CharacterFrame.LeftPaneHost = frame("Frame", "CharacterFrameLeftPaneHost", CharacterFrame);
CharacterFrame.RightPaneHost = frame("Frame", "CharacterFrameRightPaneHost", CharacterFrame);
CharacterFrame.ModeTabs = frame("Frame", "CharacterFrameModeTabs", CharacterFrame);
CharacterFrame.ModeTabs.Tabs = {};
for i, key in ipairs({"CharacterTab", "ReputationTab", "SkillsTab", "PvPTab", "CurrencyTab", "StatisticsTab"}) do
    local tab = frame("Button", "CharacterFrameModeTab" .. i, CharacterFrame.ModeTabs);
    P[tab].id, P[tab].width = i, 40;
    CharacterFrame.ModeTabs[key] = tab;
    CharacterFrame.ModeTabs.Tabs[i] = tab;
end
P[CharacterFrame.ModeTabs].width = 40;
PaperDollFrame = frame("Frame", "PaperDollFrame", CharacterFrame);
PaperDollItemsFrame = frame("Frame", "PaperDollItemsFrame", PaperDollFrame);
CharacterModelScene = frame("ModelScene", "CharacterModelScene", PaperDollFrame);
PaperDollFrame.EquipmentManagerPane = frame("Frame", nil, PaperDollFrame, true);
EquipmentFlyoutFrame = frame("Frame", "EquipmentFlyoutFrame", UIParent, true);
GearManagerPopupFrame = frame("Frame", "GearManagerPopupFrame", PaperDollFrame, true);
-- the slots are intrinsic ItemButtons (PaperDollItemSlotButtonTemplate): icon, Count, IconBorder... come from it
for slotName, id in pairs(H.SLOT_IDS) do
    local b = frame("ItemButton", "Character" .. slotName, PaperDollItemsFrame);
    P[b].id = id;
end
CharacterMicroButton = frame("Button", "CharacterMicroButton", UIParent);
MerchantFrame = frame("Frame", "MerchantFrame", UIParent, true);
BankFrame = frame("Frame", "BankFrame", UIParent, true);
MailFrame = frame("Frame", "MailFrame", UIParent, true);
GameMenuFrame = frame("Frame", "GameMenuFrame", UIParent, true);
SettingsPanel = frame("Frame", "SettingsPanel", UIParent, true);
Minimap = frame("Minimap", "Minimap", UIParent);
UIErrorsFrame = frame("MessageFrame", "UIErrorsFrame", UIParent);
DEFAULT_CHAT_FRAME = frame("ScrollingMessageFrame", "ChatFrame1", UIParent);
P[DEFAULT_CHAT_FRAME].chat = true;
SELECTED_CHAT_FRAME = DEFAULT_CHAT_FRAME;
-- bag windows are not modelled: the enumerator exists but yields nothing
function ContainerFrameUtil_EnumerateContainerFrames()
    return ipairs({});
end
UISpecialFrames = {};

function ShowUIPanel(f)
    if f then
        f:Show();
    end
end
function HideUIPanel(f)
    if f then
        f:Hide();
    end
end
function ToggleCharacter(tab)
    CharacterFrame:SetShown(not CharacterFrame:IsShown());
end
function H.openCharacterFrame()
    CharacterFrame:Show();
end
function H.closeCharacterFrame()
    CharacterFrame:Hide();
end

---------------------------------------------------------------------------
-- tooltips
---------------------------------------------------------------------------
local postCalls = {};
TooltipDataProcessor = {
    AddTooltipPostCall = function(dataType, fn)
        if type(fn) ~= "function" then
            error("Usage: TooltipDataProcessor.AddTooltipPostCall(dataType, func)", 2);
        end
        postCalls[dataType] = postCalls[dataType] or {};
        table.insert(postCalls[dataType], fn);
    end,
    AddTooltipPreCall = function() end,
    AddLinePreCall = function() end,
    AddLinePostCall = function() end,
};
TooltipDataProcessor.AllTypes = "ALL";

local function tooltipLine(tt, i, side)
    local name = tt:GetName() and (tt:GetName() .. "Text" .. side .. i);
    local existing = name and rawget(_G, name);
    return existing or H.newObject("FontString", name, tt, true);
end

local function setTooltipItem(tt, inst)
    local p = P[tt];
    tt:ClearLines();
    p.item = inst;
    local def = inst.item;
    tt:AddLine(def.name);
    tt:AddLine(def.equipLoc ~= "" and (rawget(_G, def.equipLoc) or def.equipLoc) or def.itemType);
    local list = postCalls[Enum.TooltipDataType.Item] or {};
    local data = {type = Enum.TooltipDataType.Item, id = def.id, hyperlink = H.itemLink(inst), lines = {}};
    for _, fn in ipairs(list) do
        H.trap("TooltipDataProcessor post-call (Item)", fn, tt, data);
    end
    tt:Show();
    return true;
end

H.extendClass("GameTooltip", {
    SetOwner = function(self, owner, anchor)
        P[self].owner, P[self].anchor = owner, anchor;
        -- like the client: any anchor other than ANCHOR_NONE places the tooltip against its owner
        P[self].points = {};
        if anchor ~= "ANCHOR_NONE" then
            P[self].points[1] = {"BOTTOMLEFT", owner, "TOPRIGHT", 0, 0};
        end
        self:ClearLines();
    end,
    GetOwner = function(self)
        return P[self].owner;
    end,
    IsOwned = function(self, f)
        return P[self].owner == f;
    end,
    ClearLines = function(self)
        P[self].lines, P[self].item = {}, nil;
        H.fireScript(self, "OnTooltipCleared");
    end,
    AddLine = function(self, text, r, g, b, wrap)
        local lines = P[self].lines or {};
        P[self].lines = lines;
        local i = #lines + 1;
        local left = tooltipLine(self, i, "Left");
        left:SetText(text);
        lines[i] = {left = left, right = tooltipLine(self, i, "Right")};
    end,
    AddDoubleLine = function(self, l, r)
        self:AddLine(l);
        local lines = P[self].lines;
        lines[#lines].right:SetText(r);
    end,
    SetText = function(self, text)
        self:ClearLines();
        self:AddLine(text);
    end,
    AppendText = function(self, text)
        local lines = P[self].lines or {};
        if lines[1] then
            lines[1].left:SetText((lines[1].left:GetText() or "") .. text);
        end
    end,
    NumLines = function(self)
        return #(P[self].lines or {});
    end,
    GetItem = function(self)
        local inst = P[self].item;
        if inst then
            return inst.item.name, H.itemLink(inst), inst.id;
        end
    end,
    GetSpell = function()
        return nil;
    end,
    GetUnit = function()
        return nil;
    end,
    SetHyperlink = function(self, link)
        local def, enchant = H.parseItemArg(link);
        if def then
            return setTooltipItem(self, {item = def, id = def.id, key = def.key, enchant = enchant});
        end
    end,
    SetItemByID = function(self, id)
        local def = H.itemsById[id];
        if def then
            return setTooltipItem(self, {item = def, id = id, key = def.key});
        end
    end,
    SetInventoryItem = function(self, unit, slot)
        local inst = unit == "player" and H.inv[slot];
        if inst then
            return setTooltipItem(self, inst), false, 0;
        end
        return false, false, 0;
    end,
    SetBagItem = function(self, bag, slot)
        local b = H.bags[bag];
        local inst = b and b.slots[slot];
        if inst then
            return setTooltipItem(self, inst);
        end
    end,
    GetTooltipData = function(self)
        local inst = P[self].item;
        return inst and {type = Enum.TooltipDataType.Item, id = inst.id, hyperlink = H.itemLink(inst), lines = {}};
    end,
});

TooltipUtil = {
    GetDisplayedItem = function(tt)
        return tt:GetItem();
    end,
};

GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent, "GameTooltipTemplate");
P[GameTooltip].shown = false;
ItemRefTooltip = CreateFrame("GameTooltip", "ItemRefTooltip", UIParent, "GameTooltipTemplate");
P[ItemRefTooltip].shown = false;
ShoppingTooltip1 = CreateFrame("GameTooltip", "ShoppingTooltip1", UIParent, "GameTooltipTemplate");
ShoppingTooltip2 = CreateFrame("GameTooltip", "ShoppingTooltip2", UIParent, "GameTooltipTemplate");
P[ShoppingTooltip1].shown, P[ShoppingTooltip2].shown = false, false;
GameTooltip.shoppingTooltips = {ShoppingTooltip1, ShoppingTooltip2};

-- Blizzard's Camelot slot tooltip: the slot's OnEnter script is bound to the ORIGINAL function (XML function=), so a
-- hooksecurefunc on the global only sees the periodic refresh (UpdateTooltip -> PaperDollItemSlotButton_OnUpdate),
-- which looks the global up at run time.
function PaperDollItemSlotButton_OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip:SetInventoryItem("player", self:GetID());
end
local PaperDollItemSlotButton_OnEnter_Original = PaperDollItemSlotButton_OnEnter;
for slotName in pairs(H.SLOT_IDS) do
    local b = _G["Character" .. slotName];
    b:SetScript("OnEnter", PaperDollItemSlotButton_OnEnter_Original);
    b:SetScript("OnLeave", function()
        GameTooltip:Hide();
    end);
    b.UpdateTooltip = function(self)
        PaperDollItemSlotButton_OnEnter(self);
    end;
end

-- The player hovers an item on the character sheet / in a bag: tooltip shown with the item.
function H.hoverInventorySlot(slot)
    GameTooltip:SetOwner(UIParent, "ANCHOR_RIGHT");
    return GameTooltip:SetInventoryItem("player", slot);
end
function H.hoverBagItem(bag, slot)
    GameTooltip:SetOwner(UIParent, "ANCHOR_RIGHT");
    return GameTooltip:SetBagItem(bag, slot);
end

---------------------------------------------------------------------------
-- StaticPopup
---------------------------------------------------------------------------
StaticPopupDialogs = {};
H.popups = {};
local popupFrame = frame("Frame", "StaticPopup1", UIParent, true);
popupFrame.text = H.newObject("FontString", "StaticPopup1Text", popupFrame, true);
popupFrame.editBox = CreateFrame("EditBox", "StaticPopup1EditBox", popupFrame);
popupFrame.button1 = CreateFrame("Button", "StaticPopup1Button1", popupFrame);
popupFrame.button2 = CreateFrame("Button", "StaticPopup1Button2", popupFrame);
function popupFrame:GetEditBox()
    return self.editBox;
end

function StaticPopup_Show(which, textArg1, textArg2, data)
    local info = StaticPopupDialogs[which];
    if not info then
        return nil;
    end
    popupFrame.which, popupFrame.data = which, data;
    popupFrame.text:SetText(string.format(info.text or "", textArg1 or "", textArg2 or ""));
    popupFrame.editBox:SetText("");
    P[popupFrame].shown = true;
    H.popups[#H.popups + 1] = {which = which, text = popupFrame.text:GetText(), data = data};
    if info.OnShow then
        H.trap("StaticPopup " .. which .. " OnShow", info.OnShow, popupFrame, data);
    end
    return popupFrame;
end
function StaticPopup_Hide(which)
    if popupFrame.which == which then
        P[popupFrame].shown = false;
        popupFrame.which = nil;
    end
end
function StaticPopup_Visible(which)
    return popupFrame.which == which and "StaticPopup1" or nil, popupFrame.which == which and popupFrame or nil;
end
-- The player clicks button1 (accept) of the visible popup, optionally typing text first.
function H.acceptPopup(text)
    local which = popupFrame.which;
    local info = which and StaticPopupDialogs[which];
    if not info then
        error("harness: no popup is shown", 2);
    end
    if text then
        popupFrame.editBox:SetText(text);
    end
    if info.OnAccept then
        H.trap("StaticPopup " .. which .. " OnAccept", info.OnAccept, popupFrame, popupFrame.data, popupFrame.data2);
    end
    StaticPopup_Hide(which);
end
function H.cancelPopup()
    local which = popupFrame.which;
    local info = which and StaticPopupDialogs[which];
    if info and info.OnCancel then
        H.trap("StaticPopup " .. which .. " OnCancel", info.OnCancel, popupFrame, popupFrame.data);
    end
    StaticPopup_Hide(which);
end

---------------------------------------------------------------------------
-- Settings (canvas categories)
---------------------------------------------------------------------------
local categories, nextCategoryId = {}, 1;
local Category = {
    GetID = function(self)
        return self.ID;
    end,
    GetName = function(self)
        return self.name;
    end,
};
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name)
        if type(frame) ~= "table" or not P[frame] then
            error("Usage: Settings.RegisterCanvasLayoutCategory(frame, name)", 2);
        end
        local cat = Mixin({ID = nextCategoryId, name = name, frame = frame}, Category);
        nextCategoryId = nextCategoryId + 1;
        categories[cat.ID] = cat;
        return cat;
    end,
    RegisterVerticalLayoutCategory = function(name)
        local cat = Mixin({ID = nextCategoryId, name = name}, Category);
        nextCategoryId = nextCategoryId + 1;
        categories[cat.ID] = cat;
        return cat, {};
    end,
    RegisterCanvasLayoutSubcategory = function(parent, frame, name)
        return Settings.RegisterCanvasLayoutCategory(frame, name);
    end,
    RegisterAddOnCategory = function(cat)
        cat.registered = true;
    end,
    GetCategory = function(id)
        return categories[id];
    end,
    OpenToCategory = function(id)
        if H.combat then
            H.fire("ADDON_ACTION_BLOCKED", H.addonName, "C_SettingsUtil.OpenSettingsPanel()");
            return false;
        end
        local cat = categories[id];
        if not cat then
            return false;
        end
        SettingsPanel:Show();
        if cat.frame then
            if P[cat.frame].parent ~= SettingsPanel then
                cat.frame:SetParent(SettingsPanel);
            end
            cat.frame:Show();
        end
        return true;
    end,
};
H.settingsCategories = categories;

---------------------------------------------------------------------------
-- UIDropDownMenu (still loaded on Forever) and MenuUtil
---------------------------------------------------------------------------
H.dropdown = {open = nil, buttons = {}};
function UIDropDownMenu_CreateInfo()
    return {};
end
function UIDropDownMenu_Initialize(f, initFunction, displayMode, level, menuList)
    f.initialize, f.displayMode, f.menuList = initFunction, displayMode, menuList;
    H.dropdown.buttons = {};
    if initFunction then
        initFunction(f, level or 1, menuList);
    end
end
function UIDropDownMenu_AddButton(info, level)
    local copy = {};
    for k, v in pairs(info) do
        copy[k] = v;
    end
    table.insert(H.dropdown.buttons, copy);
end
function ToggleDropDownMenu(level, value, dropDownFrame, anchorName, xOffset, yOffset, menuList)
    if H.dropdown.open == dropDownFrame and (level or 1) == 1 then
        CloseDropDownMenus();
        return;
    end
    H.dropdown.open, H.dropdown.buttons = dropDownFrame, {};
    if dropDownFrame and dropDownFrame.initialize then
        dropDownFrame.initialize(dropDownFrame, level or 1, menuList or dropDownFrame.menuList);
    end
end
function CloseDropDownMenus()
    H.dropdown.open = nil;
end
function UIDropDownMenu_SetText(f, text)
    local label = f.Text or (f:GetName() and rawget(_G, f:GetName() .. "Text"));
    if label then
        label:SetText(text);
    end
    f.selectedText = text;
end
function UIDropDownMenu_GetText(f)
    return f.selectedText;
end
function UIDropDownMenu_SetWidth(f, width)
    P[f].width = width;
end
function UIDropDownMenu_SetButtonWidth() end
function UIDropDownMenu_JustifyText() end
function UIDropDownMenu_EnableDropDown(f)
    f.isDisabled = false;
end
function UIDropDownMenu_DisableDropDown(f)
    f.isDisabled = true;
end
function UIDropDownMenu_SetSelectedValue(f, value)
    f.selectedValue = value;
end
function UIDropDownMenu_GetSelectedValue(f)
    return f.selectedValue;
end
function UIDropDownMenu_SetSelectedName(f, name)
    f.selectedName = name;
end
function UIDropDownMenu_SetSelectedID(f, id)
    f.selectedID = id;
end
function UIDropDownMenu_GetSelectedID(f)
    return f.selectedID;
end
-- The player clicks the entry with this text in the legacy UIDropDownMenu built last (menu.lua extends it to
-- MenuUtil menus).
function H.clickMenuEntry(text)
    for _, info in ipairs(H.dropdown.buttons) do
        if info.text == text then
            if info.func then
                H.trap("dropdown entry " .. tostring(text), info.func, info, info.arg1, info.arg2, info.checked);
            end
            CloseDropDownMenus();
            return true;
        end
    end
    error("harness: no menu entry '" .. tostring(text) .. "'", 2);
end

-- MenuUtil, the Menu manager and dropdown buttons: menu.lua

---------------------------------------------------------------------------
-- slash commands
---------------------------------------------------------------------------
SlashCmdList = {};
hash_SlashCmdList = {};
-- The player types a slash command, e.g. H.slash("/gq switch Tank").
function H.slash(line)
    local cmd, msg = line:match("^(/%S+)%s*(.*)$");
    for k, v in pairs(_G) do
        if type(k) == "string" and type(v) == "string" and v:lower() == cmd:lower() then
            local key = k:match("^SLASH_(.-)%d+$");
            if key and SlashCmdList[key] then
                H.trap("slash " .. cmd, SlashCmdList[key], msg, DEFAULT_CHAT_FRAME);
                return true;
            end
        end
    end
    error("harness: unknown slash command " .. tostring(cmd), 2);
end
