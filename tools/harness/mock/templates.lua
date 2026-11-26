-- templates.lua: the modern Blizzard frame templates GQ's own widgets use, with the parentKeys, names, mixins and
-- scripts of the forever branch (Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml/.lua,
-- Shared/Button/ThreeSliceButtonTemplate.xml/.lua, Shared/Button/CheckButtonTemplates.xml, NineSlice.lua):
--   DefaultPanelBaseTemplate / DefaultPanelTemplate / DefaultPanelFlatTemplate (NineSlice, Bg, TitleContainer.TitleText)
--   NineSlicePanelTemplate + NineSliceUtil, InsetFrameTemplate, FlatPanelBackgroundTemplate
--   UIPanelCloseButton / UIPanelCloseButtonNoScripts / UIPanelCloseButtonDefaultAnchors (Camelot: 28x28 at TOPRIGHT 0,3)
--   PanelTabButtonTemplate / PanelTopTabButtonTemplate + PanelTemplates_* (tabs join the parent's .Tabs array)
--   ThreeSliceButtonTemplate / BigRedThreeSliceButtonTemplate / SharedButton(Small|Large|ExtraSmall)Template
--   UICheckButtonTemplate / UICheckButtonArtTemplate / MinimalCheckboxTemplate / CheckboxWithLabelTemplate
--   UIPanelButtonTemplate (gold button art, HighlightTexture, state art on enable/disable)
-- Art is recorded (file / atlas / colour) but nothing is drawn: scenarios assert structure, keys and art names.
local H = ...;
local P = H.widgetState;
local T = H.blizzTemplates;

local function method(name)
    return function(self, ...)
        local m = self[name];
        if m then
            return m(self, ...);
        end
    end
end

local function xmlScript(obj, scriptName, fn)
    H.setXmlScript(obj, scriptName, fn);
end

H.extendClass("Button", {
    GetButtonState = function(self)
        return P[self].buttonState or "NORMAL";
    end,
    SetButtonState = function(self, state, locked)
        P[self].buttonState = state;
    end,
    SetDisabledFontObject = function(self, font)
        P[self].disabledFont = font;
    end,
    SetNormalFontObject = function(self, font)
        P[self].normalFont = font;
    end,
    SetHighlightFontObject = function(self, font)
        P[self].highlightFont = font;
    end,
});

---------------------------------------------------------------------------
-- NineSlice
---------------------------------------------------------------------------
local PIECES = {"TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "TopEdge", "BottomEdge",
    "LeftEdge", "RightEdge", "Center"};

local LAYOUT_NAMES = {"SimplePanelTemplate", "PortraitFrameTemplate", "PortraitFrameTemplateMinimizable",
    "ButtonFrameTemplateNoPortrait", "ButtonFrameTemplateNoPortraitMinimizable",
    "ButtonFrameTemplateNoPortraitLessPadding", "InsetFrameTemplate", "BFAMissionHorde", "BFAMissionAlliance",
    "CovenantMissionFrame", "DragonflightMissionFrame", "GenericMetal", "Dialog", "WoodenNeutralFrameTemplate",
    "Runeforge", "AdventuresMissionComplete", "CharacterCreateDropdown", "ChatBubble", "SelectionFrameTemplate",
    "GMChatRequest", "TooltipDefaultLayout", "TooltipDefaultDarkLayout", "TooltipAzeriteLayout",
    "TooltipCorruptedLayout", "TooltipMawLayout", "TooltipGluesLayout", "DarkmoonBasicSmallContainerLayout",
    "TooltipMixedLayout", "HeldBagLayout", "IdenticalCornersLayoutNoCenter", "IdenticalCornersLayout",
    "UniqueCornersLayout", "PerksProgramProductsPanelTemplate", "PerksProgramHoldPanelTemplate",
    "BankTabSettingsMenuLayout", "ThreeSliceVerticalLayout", "ThreeSliceHorizontalLayout"};

-- piece atlases of the layouts GQ is likely to use (Mainline/NineSliceLayouts.lua); other layouts get bare pieces
local LAYOUT_ATLASES = {
    ButtonFrameTemplateNoPortrait = {TopLeftCorner = "UI-Frame-Metal-CornerTopLeft",
        TopRightCorner = "UI-Frame-Metal-CornerTopRight", BottomLeftCorner = "UI-Frame-Metal-CornerBottomLeft",
        BottomRightCorner = "UI-Frame-Metal-CornerBottomRight", TopEdge = "_UI-Frame-Metal-EdgeTop",
        BottomEdge = "_UI-Frame-Metal-EdgeBottom", LeftEdge = "!UI-Frame-Metal-EdgeLeft",
        RightEdge = "!UI-Frame-Metal-EdgeRight"},
    InsetFrameTemplate = {TopLeftCorner = "UI-Frame-InnerTopLeft", TopRightCorner = "UI-Frame-InnerTopRight",
        BottomLeftCorner = "UI-Frame-InnerBotLeftCorner", BottomRightCorner = "UI-Frame-InnerBotRight",
        TopEdge = "_UI-Frame-InnerTopTile", BottomEdge = "_UI-Frame-InnerBotTile", LeftEdge = "!UI-Frame-InnerLeftTile",
        RightEdge = "!UI-Frame-InnerRightTile"},
    SimplePanelTemplate = {TopLeftCorner = "UI-Frame-SimpleMetal-CornerTopLeft",
        TopRightCorner = "UI-Frame-SimpleMetal-CornerTopLeft", BottomLeftCorner = "UI-Frame-SimpleMetal-CornerTopLeft",
        BottomRightCorner = "UI-Frame-SimpleMetal-CornerTopLeft", TopEdge = "_UI-Frame-SimpleMetal-EdgeTop",
        BottomEdge = "_UI-Frame-SimpleMetal-EdgeTop", LeftEdge = "!UI-Frame-SimpleMetal-EdgeLeft",
        RightEdge = "!UI-Frame-SimpleMetal-EdgeLeft"},
    GenericMetal = {TopLeftCorner = "UI-Frame-GenericMetal-Corner", TopRightCorner = "UI-Frame-GenericMetal-Corner",
        BottomLeftCorner = "UI-Frame-GenericMetal-Corner", BottomRightCorner = "UI-Frame-GenericMetal-Corner",
        TopEdge = "_UI-Frame-GenericMetal-EdgeTop", BottomEdge = "_UI-Frame-GenericMetal-EdgeBottom",
        LeftEdge = "!UI-Frame-GenericMetal-EdgeLeft", RightEdge = "!UI-Frame-GenericMetal-EdgeRight"},
    Dialog = {TopLeftCorner = "UI-Frame-DiamondMetal-CornerTopLeft",
        TopRightCorner = "UI-Frame-DiamondMetal-CornerTopRight",
        BottomLeftCorner = "UI-Frame-DiamondMetal-CornerBottomLeft",
        BottomRightCorner = "UI-Frame-DiamondMetal-CornerBottomRight", TopEdge = "_UI-Frame-DiamondMetal-EdgeTop",
        BottomEdge = "_UI-Frame-DiamondMetal-EdgeBottom", LeftEdge = "!UI-Frame-DiamondMetal-EdgeLeft",
        RightEdge = "!UI-Frame-DiamondMetal-EdgeRight"},
    TooltipDefaultLayout = {TopLeftCorner = "Tooltip-NineSlice-CornerTopLeft",
        TopRightCorner = "Tooltip-NineSlice-CornerTopRight", BottomLeftCorner = "Tooltip-NineSlice-CornerBottomLeft",
        BottomRightCorner = "Tooltip-NineSlice-CornerBottomRight", TopEdge = "_Tooltip-NineSlice-EdgeTop",
        BottomEdge = "_Tooltip-NineSlice-EdgeBottom", LeftEdge = "!Tooltip-NineSlice-EdgeLeft",
        RightEdge = "!Tooltip-NineSlice-EdgeRight", Center = "Tooltip-NineSlice-Center"},
};

local layouts = {};
for _, name in ipairs(LAYOUT_NAMES) do
    layouts[name] = {atlases = LAYOUT_ATLASES[name] or {}};
end

NineSliceUtil = {};

function NineSliceUtil.GetLayout(layoutName)
    return layouts[layoutName];
end

function NineSliceUtil.AddLayout(layoutName, layout)
    layouts[layoutName] = {atlases = {}, userLayout = layout};
end

function NineSliceUtil.ApplyLayout(container, userLayout, textureKit)
    if type(userLayout) ~= "table" then
        error("NineSliceUtil.ApplyLayout: layout required", 2);
    end
    for _, piece in ipairs(PIECES) do
        local atlas = userLayout.atlases and userLayout.atlases[piece];
        if piece ~= "Center" or atlas then
            local t = rawget(container, piece) or H.addTexture(container, {key = piece, layer = "BORDER"});
            if atlas then
                t:SetAtlas(atlas);
            end
        end
    end
    container.layoutApplied = true;
end

function NineSliceUtil.ApplyLayoutByName(container, userLayoutName, textureKit)
    local layout = layouts[userLayoutName];
    if not layout then
        error("NineSliceUtil.ApplyLayoutByName: unknown layout '" .. tostring(userLayoutName) .. "'", 2);
    end
    container.layoutType = userLayoutName;
    return NineSliceUtil.ApplyLayout(container, layout, textureKit);
end

function NineSliceUtil.DisableSharpening() end

NineSlicePanelMixin = {};

function NineSlicePanelMixin:GetFrameLayoutType()
    return self.layoutType or self:GetParent().layoutType;
end

function NineSlicePanelMixin:GetFrameLayoutTextureKit()
    return self.layoutTextureKit or self:GetParent().layoutTextureKit;
end

function NineSlicePanelMixin:OnLoad()
    local layoutType = self:GetFrameLayoutType();
    if layoutType then
        NineSliceUtil.ApplyLayoutByName(self, layoutType, self:GetFrameLayoutTextureKit());
    end
end

function NineSlicePanelMixin:SetCenterColor(r, g, b, a)
    if self.Center then
        self.Center:SetVertexColor(r, g, b, a);
    end
end

function NineSlicePanelMixin:SetBorderColor(r, g, b, a)
    for _, piece in ipairs(PIECES) do
        if piece ~= "Center" and self[piece] then
            self[piece]:SetVertexColor(r, g, b, a);
        end
    end
end

function NineSlicePanelMixin:SetVertexColor(r, g, b, a)
    self:SetCenterColor(r, g, b, a);
    self:SetBorderColor(r, g, b, a);
end

H.defineTemplate("NineSliceCodeTemplate", "Frame", 0, 0, function(f)
    Mixin(f, NineSlicePanelMixin);
    xmlScript(f, "OnLoad", method("OnLoad"));
end);
H.defineTemplate("NineSlicePanelTemplate", "Frame", 0, 0, function(f)
    T.NineSliceCodeTemplate(f);
    P[f].frameLevel = 500;
    P[f].points = {{"TOPLEFT", P[f].parent}, {"BOTTOMRIGHT", P[f].parent}};
end);

---------------------------------------------------------------------------
-- panels
---------------------------------------------------------------------------
TitledPanelMixin = {};

function TitledPanelMixin:GetTitleText()
    return self.TitleContainer.TitleText;
end

function TitledPanelMixin:SetTitleColor(color)
    self:GetTitleText():SetTextColor(color:GetRGBA());
end

function TitledPanelMixin:SetTitle(title)
    self:GetTitleText():SetText(title);
end

function TitledPanelMixin:SetTitleFormatted(fmt, ...)
    self:GetTitleText():SetFormattedText(fmt, ...);
end

function TitledPanelMixin:SetTitleOffsets(leftOffset, rightOffset)
    self.TitleContainer:SetPoint("TOPLEFT", self, "TOPLEFT", leftOffset or 58, -1);
    self.TitleContainer:SetPoint("TOPRIGHT", self, "TOPRIGHT", rightOffset or -24, -1);
end

DefaultPanelMixin = CreateFromMixins(TitledPanelMixin);

FocusFramesInterfaceMixin = {};

function FocusFramesInterfaceMixin:GetFocusFrameGlow()
    return self.FrameGlow;
end

H.defineTemplate("DefaultPanelBaseTemplate", "Frame", 338, 424, function(f)
    f.layoutType = "ButtonFrameTemplateNoPortrait";
    P[f].width, P[f].height = 338, 424;
    H.addChild(f, "Frame", {key = "NineSlice"}, "NineSlicePanelTemplate");
    H.addChild(f, "Frame", {key = "FrameGlow", hidden = true, frameLevel = 505});
    local title = H.addChild(f, "Frame", {key = "TitleContainer", frameLevel = 510, size = {0, 20},
        anchors = {{"TOPLEFT", nil, nil, 30, -1}, {"TOPRIGHT", nil, nil, -24, -1}}});
    H.addFontString(title, {name = "$parentTitleText", key = "TitleText", layer = "OVERLAY", font = "GameFontNormal",
        anchors = {{"TOP", nil, nil, 0, -5}, {"LEFT"}, {"RIGHT"}}});
    H.addChild(f, "Frame", {key = "LeftJumpHint", hidden = true, frameLevel = 515});
    H.addChild(f, "Frame", {key = "RightJumpHint", hidden = true, frameLevel = 515});
    H.addChild(f, "Frame", {key = "FocusJumpHint", hidden = true, frameLevel = 515});
    Mixin(f, DefaultPanelMixin, FocusFramesInterfaceMixin);
end);

H.defineTemplate("DefaultPanelTemplate", "Frame", 338, 424, function(f)
    T.DefaultPanelBaseTemplate(f);
    H.addTexture(f, {name = "$parentBg", key = "Bg", layer = "BACKGROUND", subLevel = -6,
        file = "Interface\\FrameGeneral\\UI-Background-Rock",
        anchors = {{"TOPLEFT", nil, nil, 6, -21}, {"BOTTOMRIGHT", nil, nil, -2, 2}}});
    H.addTexture(f, {name = "$parentTopTileStreaks", key = "TopTileStreaks", layer = "BACKGROUND", subLevel = -5,
        atlas = "_UI-Frame-TopTileStreaks", anchors = {{"TOPLEFT", nil, nil, 6, -21}, {"TOPRIGHT", nil, nil, -2, -21}}});
end);

H.defineTemplate("FlatPanelBackgroundTemplate", "Frame", 0, 0, function(f)
    H.addTexture(f, {key = "BottomLeft", layer = "BACKGROUND", atlas = "uiframebackground-nineslice-cornerbottomleft"});
    H.addTexture(f, {key = "BottomRight", layer = "BACKGROUND", atlas = "uiframebackground-nineslice-cornerbottomright"});
    H.addTexture(f, {key = "BottomEdge", layer = "BACKGROUND"});
    H.addTexture(f, {key = "TopSection", layer = "BACKGROUND"});
end);

H.defineTemplate("DefaultPanelFlatTemplate", "Frame", 338, 424, function(f)
    T.DefaultPanelBaseTemplate(f);
    H.addChild(f, "Frame", {name = "$parentBg", key = "Bg", frameLevel = 0,
        anchors = {{"TOPLEFT", nil, nil, 6, -20}, {"BOTTOMRIGHT", nil, nil, -2, 2}}}, "FlatPanelBackgroundTemplate");
end);

H.defineTemplate("InsetFrameTemplate", "Frame", 0, 0, function(f)
    f.layoutType = "InsetFrameTemplate";
    H.addTexture(f, {key = "Bg", layer = "BACKGROUND", subLevel = -5,
        file = "Interface\\FrameGeneral\\UI-Background-Marble", setAllPoints = true});
    H.addChild(f, "Frame", {key = "NineSlice"}, "NineSlicePanelTemplate");
end);

---------------------------------------------------------------------------
-- close buttons (Camelot override of UIPanelCloseButtonDefaultAnchorsMixin:OnLoad)
---------------------------------------------------------------------------
function UIPanelCloseButton_OnClick(self)
    local parent = self:GetParent();
    if parent then
        local continueHide = true;
        if parent.onCloseCallback then
            continueHide = parent.onCloseCallback(self);
        end
        if continueHide then
            HideUIPanel(parent);
        end
    end
end

UIPanelCloseButtonDefaultAnchorsMixin = {};

function UIPanelCloseButtonDefaultAnchorsMixin:OnLoad()
    self:SetSize(28, 28);
    self:ClearAllPoints();
    self:SetPoint("TOPRIGHT", 0, 3);
end

H.defineTemplate("UIPanelCloseButtonNoScripts", "Button", 24, 24, function(f)
    P[f].width, P[f].height, P[f].frameLevel = 24, 24, 510;
    H.addButtonTexture(f, "disabledTexture", {atlas = "RedButton-Exit-Disabled"});
    H.addButtonTexture(f, "normalTexture", {atlas = "RedButton-Exit"});
    H.addButtonTexture(f, "pushedTexture", {atlas = "RedButton-exit-pressed"});
    H.addButtonTexture(f, "highlightTexture", {atlas = "RedButton-Highlight", blend = "ADD"});
end);
H.defineTemplate("UIPanelCloseButton", "Button", 24, 24, function(f)
    T.UIPanelCloseButtonNoScripts(f);
    xmlScript(f, "OnClick", UIPanelCloseButton_OnClick);
end);
H.defineTemplate("UIPanelCloseButtonDefaultAnchors", "Button", 24, 24, function(f)
    T.UIPanelCloseButton(f);
    Mixin(f, UIPanelCloseButtonDefaultAnchorsMixin);
    H.setXmlScript(f, "OnLoad", method("OnLoad"), "append");
end);

---------------------------------------------------------------------------
-- tabs
---------------------------------------------------------------------------
PanelTabButtonMixin = {};

function PanelTabButtonMixin:OnLoad()
    self:SetFrameLevel(self:GetFrameLevel() + 4);
    self:RegisterEvent("DISPLAY_SIZE_CHANGED");
end

function PanelTabButtonMixin:OnEvent()
    if self:IsVisible() then
        local parent = self:GetParent();
        PanelTemplates_TabResize(self, parent.tabPadding, nil, parent.minTabWidth, parent.maxTabWidth);
    end
end

function PanelTabButtonMixin:OnShow()
    local parent = self:GetParent();
    PanelTemplates_TabResize(self, parent.tabPadding, nil, parent.minTabWidth, parent.maxTabWidth);
end

function PanelTabButtonMixin:OnEnter()
    GetAppropriateTooltip():Hide();
end

function PanelTabButtonMixin:OnLeave()
    GetAppropriateTooltip():Hide();
end

PanelTopTabButtonMixin = {};

function PanelTopTabButtonMixin:OnLoad()
    PanelTabButtonMixin.OnLoad(self);
    self.Left:ClearAllPoints();
    self.Left:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", -3, 0);
    self.Right:ClearAllPoints();
    self.Right:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 7, 0);
    self.LeftActive:ClearAllPoints();
    self.LeftActive:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", -1, 0);
    self.RightActive:ClearAllPoints();
    self.RightActive:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 8, 0);
    self.isTopTab = true;
end

H.defineTemplate("PanelTabButtonTemplate", "Button", 10, 32, function(f)
    P[f].width, P[f].height = 10, 32;
    -- parentArray="Tabs" (once, also when the XML instance repeats the attribute)
    local parent = P[f].parent;
    if parent then
        local tabs = rawget(parent, "Tabs") or {};
        parent.Tabs = tabs;
        if not tContains(tabs, f) then
            tabs[#tabs + 1] = f;
        end
    end
    for _, t in ipairs({{"LeftActive", "uiframe-activetab-left"}, {"RightActive", "uiframe-activetab-right"},
        {"MiddleActive", "_uiframe-activetab-center"}, {"Left", "uiframe-tab-left"}, {"Right", "uiframe-tab-right"},
        {"Middle", "_uiframe-tab-center"}}) do
        H.addTexture(f, {key = t[1], array = "TabTextures", layer = "BACKGROUND", atlas = t[2]});
    end
    for _, t in ipairs({{"LeftHighlight", "uiframe-tab-left"}, {"MiddleHighlight", "_uiframe-tab-center"},
        {"RightHighlight", "uiframe-tab-right"}}) do
        H.addTexture(f, {key = t[1], array = "TabTextures", layer = "HIGHLIGHT", atlas = t[2], blend = "ADD",
            alpha = 0.4});
    end
    P[f].fontString = H.addFontString(f, {key = "Text", layer = "ARTWORK", font = "GameFontNormalSmall",
        size = {0, 10}, anchors = {{"CENTER", nil, nil, 0, 2}}});
    P[f].normalFont, P[f].highlightFont, P[f].disabledFont = "GameFontNormalSmall", "GameFontHighlightSmall",
        "GameFontHighlightSmall";
    Mixin(f, PanelTabButtonMixin);
    for _, s in ipairs({"OnLoad", "OnEvent", "OnShow", "OnEnter", "OnLeave"}) do
        xmlScript(f, s, method(s));
    end
end);
H.defineTemplate("PanelTopTabButtonTemplate", "Button", 10, 32, function(f)
    T.PanelTabButtonTemplate(f);
    Mixin(f, PanelTopTabButtonMixin);
end);

local function tabByIndex(frame, index)
    return (frame.Tabs and frame.Tabs[index]) or _G[frame:GetName() .. "Tab" .. index];
end

function PanelTemplates_Tab_OnClick(self, frame)
    PanelTemplates_SetTab(frame, self:GetID());
end

function PanelTemplates_SetTab(frame, id)
    frame.selectedTab = id;
    PanelTemplates_UpdateTabs(frame);
end

function PanelTemplates_GetSelectedTab(frame)
    return frame.selectedTab;
end

function PanelTemplates_UpdateTabs(frame)
    if frame.selectedTab then
        for i = 1, frame.numTabs do
            local tab = tabByIndex(frame, i);
            if tab.isDisabled then
                PanelTemplates_SetDisabledTabState(tab);
            elseif i == frame.selectedTab then
                PanelTemplates_SelectTab(tab);
            else
                PanelTemplates_DeselectTab(tab);
            end
        end
    end
end

function PanelTemplates_GetTabWidth(tab)
    return tab:GetTextWidth() + tab.Left:GetWidth() + tab.Right:GetWidth();
end

function PanelTemplates_TabResize(tab, padding, absoluteSize, minWidth, maxWidth, absoluteTextSize)
    tab.Text:SetWidth(absoluteTextSize or 0);
    local textWidth = tab.Text:GetStringWidth();
    local width = textWidth + 20 + (padding or 0);
    local sideWidths = tab.Left:GetWidth() + tab.Right:GetWidth();
    minWidth = minWidth or sideWidths;
    if absoluteSize then
        width = absoluteSize < sideWidths and sideWidths or absoluteSize;
        textWidth = width - 20 - (padding or 0);
    elseif maxWidth and width > maxWidth then
        width = maxWidth;
        textWidth = width - 20 - (padding or 0);
    elseif minWidth and width < minWidth then
        width = minWidth;
        textWidth = width - 20 - (padding or 0);
    end
    tab.Text:SetWidth(textWidth);
    tab:SetWidth(width);
end

function PanelTemplates_ResizeTabsToFit(frame, maxWidthForAllTabs)
    local selectedIndex = PanelTemplates_GetSelectedTab(frame);
    if not selectedIndex then
        return;
    end
    local currentWidth = 0;
    for i = 1, frame.numTabs do
        currentWidth = currentWidth + tabByIndex(frame, i):GetWidth();
    end
    if currentWidth <= maxWidthForAllTabs then
        return;
    end
    local currentTab = tabByIndex(frame, selectedIndex);
    PanelTemplates_TabResize(currentTab, 0);
    local widthPerTab = (maxWidthForAllTabs - currentTab:GetWidth()) / (frame.numTabs - 1);
    for i = 1, frame.numTabs do
        if i ~= selectedIndex then
            PanelTemplates_TabResize(tabByIndex(frame, i), 0, widthPerTab);
        end
    end
end

function PanelTemplates_SetNumTabs(frame, numTabs)
    frame.numTabs = numTabs;
    PanelTemplates_AnchorTabs(frame);
    if frame.GetFocusFrameGlow and frame.numTabs > 0 then
        local frameGlow = frame:GetFocusFrameGlow();
        local firstTab = tabByIndex(frame, 1);
        if frameGlow and frame:GetFrameStrata() == frameGlow:GetFrameStrata()
            and frame:GetFrameStrata() == firstTab:GetFrameStrata() then
            frameGlow:SetFrameLevel(firstTab:GetFrameLevel() - 1);
        end
    end
end

function PanelTemplates_AnchorTabs(frame)
    for i = 2, frame.numTabs do
        tabByIndex(frame, i):SetPoint("TOPLEFT", tabByIndex(frame, i - 1), "TOPRIGHT", 3, 0);
    end
end

function PanelTemplates_SetTabEnabled(frame, index, enabled)
    if enabled then
        PanelTemplates_EnableTab(frame, index);
    else
        PanelTemplates_DisableTab(frame, index);
    end
end

function PanelTemplates_DisableTab(frame, index)
    tabByIndex(frame, index).isDisabled = 1;
    PanelTemplates_UpdateTabs(frame);
end

function PanelTemplates_EnableTab(frame, index)
    local tab = tabByIndex(frame, index);
    tab.isDisabled = nil;
    tab:SetDisabledFontObject(GameFontHighlightSmall);
    PanelTemplates_UpdateTabs(frame);
end

function PanelTemplates_HideTab(frame, index)
    tabByIndex(frame, index):Hide();
end

function PanelTemplates_ShowTab(frame, index)
    tabByIndex(frame, index):Show();
end

function PanelTemplates_SetTabShown(frame, index, shown)
    tabByIndex(frame, index):SetShown(shown);
end

function PanelTemplates_DeselectTab(tab)
    tab.Left:Show();
    tab.Middle:Show();
    tab.Right:Show();
    tab:Enable();
    local offsetY = tab.deselectedTextY or 2;
    if tab.isTopTab then
        offsetY = -offsetY - 6;
    end
    tab.Text:SetPoint("CENTER", tab, "CENTER", tab.deselectedTextX or 0, offsetY);
    tab.LeftActive:Hide();
    tab.MiddleActive:Hide();
    tab.RightActive:Hide();
end

function PanelTemplates_SelectTab(tab)
    tab.Left:Hide();
    tab.Middle:Hide();
    tab.Right:Hide();
    tab:Disable();
    tab:SetDisabledFontObject(GameFontHighlightSmall);
    local offsetY = tab.selectedTextY or -3;
    if tab.isTopTab then
        offsetY = -offsetY - 7;
    end
    tab.Text:SetPoint("CENTER", tab, "CENTER", tab.selectedTextX or 0, offsetY);
    tab.LeftActive:Show();
    tab.MiddleActive:Show();
    tab.RightActive:Show();
    local tooltip = GetAppropriateTooltip();
    if tooltip:IsOwned(tab) then
        tooltip:Hide();
    end
end

function PanelTemplates_SetDisabledTabState(tab)
    tab.Left:Show();
    tab.Middle:Show();
    tab.Right:Show();
    tab:Disable();
    tab:SetDisabledFontObject(GameFontDisableSmall);
    tab.LeftActive:Hide();
    tab.MiddleActive:Hide();
    tab.RightActive:Hide();
end

---------------------------------------------------------------------------
-- three-slice buttons (SharedButtonSmallTemplate: what Blizzard's Forever panes use)
---------------------------------------------------------------------------
ThreeSliceButtonMixin = {};

function ThreeSliceButtonMixin:GetLeftAtlasName()
    return self.atlasName .. "-Left";
end

function ThreeSliceButtonMixin:GetRightAtlasName()
    return self.atlasName .. "-Right";
end

function ThreeSliceButtonMixin:GetCenterAtlasName()
    return "_" .. self.atlasName .. "-Center";
end

function ThreeSliceButtonMixin:GetHighlightAtlasName()
    return self.atlasName .. "-Highlight";
end

function ThreeSliceButtonMixin:InitButton()
    self:SetHighlightAtlas(self:GetHighlightAtlasName());
end

function ThreeSliceButtonMixin:UpdateScale() end

function ThreeSliceButtonMixin:UpdateButton(buttonState)
    buttonState = buttonState or self:GetButtonState();
    if not self:IsEnabled() then
        buttonState = "DISABLED";
    end
    local postfix = buttonState == "DISABLED" and "-Disabled" or (buttonState == "PUSHED" and "-Pressed" or "");
    self.Left:SetAtlas(self:GetLeftAtlasName() .. postfix, true);
    self.Center:SetAtlas(self:GetCenterAtlasName() .. postfix);
    self.Right:SetAtlas(self:GetRightAtlasName() .. postfix, true);
end

function ThreeSliceButtonMixin:OnMouseDown()
    self:UpdateButton("PUSHED");
end

function ThreeSliceButtonMixin:OnMouseUp()
    self:UpdateButton("NORMAL");
end

function ThreeSliceButtonMixin:OnEnter()
    if self.tooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:SetText(type(self.tooltip) == "function" and self.tooltip() or self.tooltip);
        GameTooltip:Show();
    end
end

function ThreeSliceButtonMixin:OnLeave()
    if self.tooltip then
        GameTooltip:Hide();
    end
end

UIButtonFitToTextBehaviorMixin = {};

function UIButtonFitToTextBehaviorMixin:SetTextToFit(text)
    self:SetText(text);
    self:FitToText();
end

function UIButtonFitToTextBehaviorMixin:FitToText()
    local width = self:GetTextWidth() + (self.fitTextWidthPadding or 0);
    if self.fitTextCanWidthDecrease or width > self:GetWidth() then
        self:SetWidth(width);
    end
end

H.defineTemplate("ThreeSliceButtonTemplate", "Button", 20, 20, function(f)
    P[f].width, P[f].height = 20, 20;
    H.addTexture(f, {key = "Left", layer = "BACKGROUND", anchors = {{"TOPLEFT"}}});
    H.addTexture(f, {key = "Right", layer = "BACKGROUND", anchors = {{"TOPRIGHT"}}});
    H.addTexture(f, {key = "Center", layer = "BACKGROUND"});
    Mixin(f, ThreeSliceButtonMixin);
    -- ButtonControllerMixin: InitButton at load, the state art on every show (none before the first show)
    local controller = H.newObject("Frame", nil, f);
    f.Controller = controller;
    xmlScript(controller, "OnLoad", function(self)
        if self:GetParent().InitButton then
            self:GetParent():InitButton();
        end
    end);
    xmlScript(controller, "OnShow", function(self)
        if self:GetParent().UpdateButton then
            self:GetParent():UpdateButton();
        end
    end);
    H.fireScript(controller, "OnLoad");
    xmlScript(f, "OnMouseDown", method("OnMouseDown"));
    xmlScript(f, "OnMouseUp", method("OnMouseUp"));
    xmlScript(f, "OnShow", method("UpdateButton"));
    xmlScript(f, "OnDisable", method("UpdateButton"));
    xmlScript(f, "OnEnable", method("UpdateButton"));
    xmlScript(f, "OnEnter", method("OnEnter"));
    xmlScript(f, "OnLeave", method("OnLeave"));
    xmlScript(f, "OnSizeChanged", method("UpdateScale"));
end);

-- KeyValues of the whole template chain are set before its children load (the Controller's OnLoad reads atlasName)
local function bigRed(f, atlasName)
    f.fitTextCanWidthDecrease, f.fitTextWidthPadding, f.atlasName = false, 30, atlasName;
    Mixin(f, UIButtonFitToTextBehaviorMixin);
    T.ThreeSliceButtonTemplate(f);
    P[f].width, P[f].height = 441, 128;
end
H.defineTemplate("BigRedThreeSliceButtonTemplate", "Button", 441, 128, function(f)
    bigRed(f, "128-RedButton");
end);
for name, def in pairs({SharedButtonTemplate = {200, 30, "GameFontNormal"},
    SharedButtonLargeTemplate = {200, 30, "GameFontNormalMed3"}, SharedButtonSmallTemplate = {138, 28, "GameFontNormal"},
    SharedButtonExtraSmallTemplate = {50, 20, "GameFontNormalSmall"}}) do
    H.defineTemplate(name, "Button", def[1], def[2], function(f)
        bigRed(f, "128-RedButton");
        P[f].width, P[f].height, P[f].normalFont = def[1], def[2], def[3];
    end);
end

---------------------------------------------------------------------------
-- check buttons (CheckButtonTemplates.xml): the label is .Text (also .text through the OnLoad alias)
---------------------------------------------------------------------------
H.defineTemplate("UICheckButtonArtTemplate", "CheckButton", 0, 0, function(f)
    H.addButtonTexture(f, "normalTexture", {file = "Interface\\Buttons\\UI-CheckBox-Up"});
    H.addButtonTexture(f, "pushedTexture", {file = "Interface\\Buttons\\UI-CheckBox-Down"});
    H.addButtonTexture(f, "highlightTexture", {file = "Interface\\Buttons\\UI-CheckBox-Highlight", blend = "ADD"});
    H.addButtonTexture(f, "checkedTexture", {file = "Interface\\Buttons\\UI-CheckBox-Check"});
    H.addButtonTexture(f, "disabledCheckedTexture", {file = "Interface\\Buttons\\UI-CheckBox-Check-Disabled"});
end);
H.defineTemplate("UICheckButtonTemplate", "CheckButton", 32, 32, function(f)
    T.UICheckButtonArtTemplate(f);
    P[f].width, P[f].height = 32, 32;
    local text = H.addFontString(f, {name = "$parentText", key = "Text", layer = "ARTWORK", font = "GameFontNormalSmall",
        anchors = {{"LEFT", nil, "RIGHT", -2, 0}}});
    f.text = text;
    P[f].fontString = text;
end);
H.defineTemplate("MinimalCheckboxArtTemplate", "CheckButton", 0, 0, function(f)
    H.addButtonTexture(f, "normalTexture", {key = "NormalTexture", atlas = "checkbox-minimal"});
    H.addButtonTexture(f, "pushedTexture", {key = "PushedTexture", atlas = "checkbox-minimal"});
    H.addButtonTexture(f, "highlightTexture", {key = "HighlightTexture", atlas = "checkbox-minimal", blend = "ADD"});
    H.addButtonTexture(f, "checkedTexture", {key = "CheckedTexture", atlas = "checkmark-minimal"});
    H.addButtonTexture(f, "disabledCheckedTexture", {key = "DisabledCheckedTexture", atlas = "checkmark-minimal-disabled"});
end);
H.defineTemplate("MinimalCheckboxTemplate", "CheckButton", 30, 29, function(f)
    T.MinimalCheckboxArtTemplate(f);
    P[f].width, P[f].height = 30, 29;
end);
H.defineTemplate("CheckboxWithLabelTemplate", "CheckButton", 30, 29, function(f)
    T.MinimalCheckboxTemplate(f);
    P[f].fontString = H.addFontString(f, {key = "Text", layer = "ARTWORK", font = "GameFontNormalSmall",
        anchors = {{"LEFT", nil, "RIGHT", 3, 0}}});
end);

---------------------------------------------------------------------------
-- UIPanelButtonTemplate (gold dialog-box button; the template swaps its art on enable/disable/press)
---------------------------------------------------------------------------
local GOLD = "Interface\\Buttons\\UI-DialogBox-goldbutton-";

local function goldArt(self, state)
    self.Left:SetTexture(GOLD .. state .. "-left");
    self.Middle:SetTexture(GOLD .. state .. "-middle");
    self.Right:SetTexture(GOLD .. state .. "-right");
end

-- Left/Middle/Right have only parentKeys in the real XML; the unnamed <ButtonText> is named $parentText by the client.
local function panelButton(f)
    H.addTexture(f, {key = "Left", layer = "BACKGROUND", file = GOLD .. "up-left", size = {12, 0}});
    H.addTexture(f, {key = "Right", layer = "BACKGROUND", file = GOLD .. "up-right", size = {32, 32}});
    H.addTexture(f, {key = "Middle", layer = "BACKGROUND", file = GOLD .. "up-middle"});
    P[f].fontString = H.addFontString(f, {name = "$parentText", key = "Text", layer = "ARTWORK",
        font = "GameFontNormalOutline"});
    H.addButtonTexture(f, "highlightTexture", {file = "Interface\\Buttons\\UI-Panel-Button-Highlight", blend = "ADD"});
    xmlScript(f, "OnLoad", function(self)
        if not self:IsEnabled() then
            goldArt(self, "disabled");
        end
    end);
    xmlScript(f, "OnMouseDown", function(self)
        if self:IsEnabled() then
            goldArt(self, "down");
        end
    end);
    xmlScript(f, "OnMouseUp", function(self)
        if self:IsEnabled() then
            goldArt(self, "up");
        end
    end);
    xmlScript(f, "OnShow", function(self)
        if self:IsEnabled() then
            goldArt(self, "up");
        end
    end);
    xmlScript(f, "OnDisable", function(self)
        goldArt(self, "disabled");
    end);
    xmlScript(f, "OnEnable", function(self)
        goldArt(self, "up");
    end);
end
for _, name in ipairs({"UIPanelButtonNoTooltipTemplate", "UIPanelButtonTemplate", "UIPanelDynamicResizeButtonTemplate",
    "GameMenuButtonTemplate"}) do
    H.defineTemplate(name, "Button", 0, 0, panelButton);
end
