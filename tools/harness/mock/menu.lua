-- menu.lua: the Blizzard_Menu system of the forever branch (MenuUtil.lua, Menu.lua descriptions, DropdownButton.lua,
-- MenuTemplates.lua text mixins, Mainline/MenuTemplates.xml): menu descriptions (CreateButton / CreateCheckbox /
-- CreateRadio / CreateTitle / CreateDivider / CreateSpacer / CreateTemplate, SetEnabled, SetTooltip, Pick with the real
-- response rules: nil / CloseAll close every menu, Close the leaf menu, Refresh / Open keep it open), MenuUtil,
-- a Menu manager (one open menu tree at a time, nothing drawn), the DropdownButton intrinsic mixin and
-- WowStyle1DropdownTemplate / WowStyle1ArrowDropdownTemplate / WowStyle1FilterDropdownTemplate / WowStyle2DropdownTemplate.
-- The dropdown's shown text is dropdown.Text:GetText() (selection text, SetDefaultText, OverrideText as in game).
-- Scenario helpers: H.mouseDown(frame) H.openDropdown(dd) H.pickDropdown(dd, "Entry"[, "Sub entry"...])
-- H.dropdownText(dd) H.dropdownEntries(dd[, path...]) H.menuEntries() H.clickMenuEntry(text) H.closeMenus()
local H = ...;
local P = H.widgetState;

local function trap(where, fn, ...)
    return H.trap(where, fn, ...);
end

MenuConstants = {VerticalLinearDirection = 1, VerticalGridDirection = 2, HorizontalGridDirection = 3,
    ElementPollFrequencySeconds = 0.2};
MenuResponse = {Open = 1, Refresh = 2, Close = 3, CloseAll = 4};
MenuInputContext = {None = 1, MouseButton = 2, MouseWheel = 3};
MenuCloseReason = {Unspecified = 1, CloseAll = 2};

MenuStyleMixin = {};
MenuStyle1Mixin = CreateFromMixins(MenuStyleMixin);
MenuStyle2Mixin = CreateFromMixins(MenuStyleMixin);
MenuVariants = {
    GetDefaultMenuMixin = function()
        return MenuStyle1Mixin;
    end,
    GetDefaultContextMenuMixin = function()
        return MenuStyle1Mixin;
    end,
    GetDropdownOpenSoundKit = function()
        return SOUNDKIT.U_CHAT_SCROLL_BUTTON;
    end,
    GetDropdownCloseSoundKit = function()
        return SOUNDKIT.U_CHAT_SCROLL_BUTTON;
    end,
};

---------------------------------------------------------------------------
-- element descriptions
---------------------------------------------------------------------------
local Description = {};
local DescriptionMeta = {__index = Description};

local function newShared(menuMixin)
    return {menuMixin = menuMixin, responseCallbacks = {}, changedCallbacks = {}, acquiredCallbacks = {},
        releasedCallbacks = {}};
end

local function newDescription(template, initializer, data)
    local d = setmetatable({elements = {}, initializers = {}, resetters = {}, queued = {}, template = template,
        data = data}, DescriptionMeta);
    if initializer then
        d.initializers[1] = initializer;
    end
    return d;
end

function CreateMenuElementDescription(template, initializer, data)
    return newDescription(template, initializer, data);
end

local function setShared(d, shared)
    d.shared = shared;
    for _, child in ipairs(d.elements) do
        setShared(child, shared);
    end
end

function Description:Insert(description, index)
    for _, queued in ipairs(self.queued) do
        setShared(queued, self.shared);
        queued.parent = self;
        table.insert(self.elements, queued);
    end
    self.queued = {};
    setShared(description, self.shared);
    description.parent = self;
    if index then
        table.insert(self.elements, index, description);
    else
        table.insert(self.elements, description);
    end
    if self.shared then
        for _, callback in ipairs(self.shared.changedCallbacks) do
            callback();
        end
    end
    return description;
end

function Description:EnumerateElementDescriptions()
    return ipairs(self.elements);
end

function Description:HasElements()
    return #self.elements > 0;
end

function Description:CanOpenSubmenu()
    return self:HasElements() and not self.submenuDeactivated;
end

function Description:DeactivateSubmenu()
    self.submenuDeactivated = true;
end

function Description:IsSubmenuDeactivated()
    return self.submenuDeactivated == true;
end

function Description:ForceOpenSubmenu() end

function Description:AddQueuedDescription(description)
    table.insert(self.queued, description);
end

function Description:ClearQueuedDescriptions()
    self.queued = {};
end

function Description:AddInitializer(initializer, index)
    table.insert(self.initializers, index or #self.initializers + 1, initializer);
end

function Description:GetInitializers()
    return self.initializers;
end

function Description:SetFinalInitializer(initializer)
    self.finalInitializer = initializer;
end

function Description:AddResetter(resetter)
    table.insert(self.resetters, resetter);
end

function Description:SetMinimumWidth(width)
    self.minimumWidth = width;
end

function Description:GetMinimumWidth()
    return self.minimumWidth;
end

function Description:SetMaximumWidth(width)
    self.maximumWidth = width;
end

function Description:GetMaximumWidth()
    return self.maximumWidth;
end

function Description:SetScrollMode(maxScrollExtent)
    self.maxScrollExtent = maxScrollExtent;
end

function Description:IsScrollable()
    return self.maxScrollExtent ~= nil;
end

function Description:SetGridMode(direction, columns, padding, compactionMargin)
    self.gridDirection, self.gridColumns = direction, columns;
end

function Description:GetTooltipFrame()
    return GameTooltip;
end

function Description:SetTag(tag, contextData)
    self.tag, self.tagContextData = tag, contextData;
end

function Description:GetTag()
    return self.tag, self.tagContextData;
end

function Description:SetRadio(isRadio)
    self.isRadio = isRadio;
end

function Description:IsRadio()
    return self.isRadio == true;
end

function Description:SetCheckbox(isCheckbox)
    self.isCheckbox = isCheckbox;
end

function Description:IsCheckbox()
    return self.isCheckbox == true;
end

function Description:SetIsSelected(isSelected)
    self.isSelected = isSelected;
end

function Description:IsSelected()
    if self.isSelected == nil then
        return false;
    end
    return self.isSelected(self:GetData()) and true or false;
end

function Description:SetCanSelect(canSelect)
    self.canSelect = canSelect;
end

function Description:CanSelect()
    if not self:IsEnabled() then
        return false;
    end
    if self.canSelect == nil then
        return true;
    end
    if type(self.canSelect) == "boolean" then
        return self.canSelect;
    end
    return self.canSelect(self:GetData());
end

function Description:SetSelectionIgnored()
    self.isSelectionIgnored = true;
end

function Description:IsSelectionIgnored()
    return self.isSelectionIgnored == true;
end

function Description:SetSoundKit(soundKit)
    self.soundKit = soundKit;
end

function Description:GetSoundKit()
    return type(self.soundKit) == "function" and self.soundKit(self) or self.soundKit;
end

function Description:SetShouldRespondIfSubmenu(canRespond)
    self.respondIfSubmenu = canRespond;
end

function Description:SetShouldPlaySoundOnSubmenuClick(canPlay)
    self.playSoundOnSubmenuClick = canPlay;
end

function Description:SetOnEnter(onEnter)
    self.onEnter = onEnter;
end

function Description:HookOnEnter(callback)
    local old = self.onEnter;
    self.onEnter = old and function(...)
        old(...);
        callback(...);
    end or callback;
end

function Description:SetOnLeave(onLeave)
    self.onLeave = onLeave;
end

function Description:HookOnLeave(callback)
    local old = self.onLeave;
    self.onLeave = old and function(...)
        old(...);
        callback(...);
    end or callback;
end

function Description:SetEnabled(isEnabled)
    self.isEnabled = isEnabled;
end

function Description:IsEnabled()
    if self.isEnabled == nil then
        return true;
    end
    if type(self.isEnabled) == "boolean" then
        return self.isEnabled;
    end
    return self.isEnabled(self) and true or false;
end

function Description:SetData(data)
    self.data = data;
end

function Description:GetData()
    return self.data;
end

function Description:SetResponder(callback)
    self.responder = callback;
end

function Description:HasResponder()
    return self.responder ~= nil;
end

function Description:HookResponder(callback)
    local old = self.responder;
    self.responder = old and function(...)
        local r = old(...);
        callback(...);
        return r;
    end or callback;
end

function Description:SetResponse(response)
    self.defaultResponse = response;
end

function Description:GetDefaultResponse(menuInputContext, menuInputButtonName)
    if type(self.defaultResponse) == "function" then
        return self.defaultResponse(menuInputContext, menuInputButtonName);
    end
    return self.defaultResponse;
end

-- root-only API
function Description:AddMenuResponseCallback(callback)
    table.insert(self.shared.responseCallbacks, callback);
end

function Description:AddMenuChangedCallback(callback)
    table.insert(self.shared.changedCallbacks, callback);
end

function Description:AddMenuAcquiredCallback(callback)
    table.insert(self.shared.acquiredCallbacks, callback);
end

function Description:AddMenuReleasedCallback(callback)
    table.insert(self.shared.releasedCallbacks, callback);
end

function Description:SetTooltipFrame() end

function Description:GetMenuMixin()
    return self.shared and self.shared.menuMixin;
end

function Description:SendResponseToMenu(response)
    if self.menu then
        H.menuManager:Respond(self.menu, self, response);
    end
end

-- Pick: what a click on the entry does (MenuElementDescriptionProxyMixin:Pick).
function Description:Pick(menuInputContext, menuInputButtonName)
    assert(menuInputContext, "MenuElementDescriptionProxyMixin:Pick() called without an input context.");
    if not self:CanSelect() then
        return false;
    end
    local response = nil;
    local willRespond = self:HasResponder();
    if willRespond then
        response = self:GetDefaultResponse(menuInputContext, menuInputButtonName) or nil;
        local menuInputData = {context = menuInputContext, buttonName = menuInputButtonName};
        local ok, overrideResponse = trap("menu entry " .. tostring(self.text), self.responder, self:GetData(),
            menuInputData, self.menu);
        if ok and overrideResponse then
            response = overrideResponse;
        end
        self:SendResponseToMenu(response);
    end
    return willRespond, response;
end

---------------------------------------------------------------------------
-- MenuUtil
---------------------------------------------------------------------------
MenuUtil = {};

function MenuUtil.TraverseMenu(elementDescription, op, condition)
    local function traverse(d)
        if condition == nil or condition(d) then
            if op(d) then
                return true;
            end
        end
        for _, child in d:EnumerateElementDescriptions() do
            if traverse(child) then
                return true;
            end
        end
        return false;
    end
    for _, d in elementDescription:EnumerateElementDescriptions() do
        if traverse(d) then
            return true;
        end
    end
    return false;
end

function MenuUtil.GetSelections(elementDescription, condition)
    local selections = {};
    local function collect(d)
        if (condition == nil or condition(d)) and d:IsSelected() then
            table.insert(selections, d);
        end
        for _, child in d:EnumerateElementDescriptions() do
            collect(child);
        end
    end
    for _, d in elementDescription:EnumerateElementDescriptions() do
        collect(d);
    end
    return selections;
end

function MenuUtil.SetElementText(elementDescription, text)
    elementDescription.text = text;
end

function MenuUtil.GetElementText(elementDescription)
    return elementDescription.text;
end

local function textDescription(text, d)
    MenuUtil.SetElementText(d, text);
    return d;
end

function MenuUtil.CreateRootMenuDescription(menuMixin)
    local d = newDescription(nil);
    d.shared = newShared(menuMixin);
    d.isRoot = true;
    return d;
end

function MenuUtil.CreateFrame()
    return newDescription("Frame");
end

function MenuUtil.CreateTemplate(template)
    return newDescription(template);
end

function MenuUtil.CreateTitle(text, color)
    local d = textDescription(text, newDescription("Frame"));
    d.isTitle, d.color = true, color;
    return d;
end

function MenuUtil.CreateButton(text, callback, data)
    local d = textDescription(text, newDescription("Button", nil, data));
    d:SetSoundKit(SOUNDKIT.U_CHAT_SCROLL_BUTTON);
    d:SetResponder(callback);
    return d;
end

function MenuUtil.CreateCheckbox(text, isSelected, setSelected, data)
    local d = textDescription(text, newDescription("Button", nil, data));
    d:SetCheckbox(true);
    d:SetIsSelected(isSelected);
    d:SetResponder(setSelected);
    d:SetResponse(MenuResponse.Refresh);
    return d;
end

function MenuUtil.CreateRadio(text, isSelected, setSelected, data)
    local d = textDescription(text, newDescription("Button", nil, data));
    d:SetRadio(true);
    d:SetIsSelected(isSelected);
    d:SetResponder(setSelected);
    return d;
end

function MenuUtil.CreateHighlightButton(text, data, onEnter)
    local d = textDescription(text, newDescription("Button", nil, data));
    d:SetOnEnter(onEnter);
    return d;
end

function MenuUtil.CreateRedHighlightButton(text, callback, data)
    return MenuUtil.CreateButton(text, callback, data);
end

function MenuUtil.CreateHighlightRadio(text, isSelected, setSelected, data, onEnter)
    local d = MenuUtil.CreateRadio(text, isSelected, setSelected, data);
    d:SetOnEnter(onEnter);
    return d;
end

function MenuUtil.CreateDivider()
    local d = newDescription("Frame");
    d.isDivider = true;
    return d;
end

function MenuUtil.CreateSpacer(extent)
    local d = newDescription("Frame");
    d.isSpacer, d.extent = true, extent or 10;
    return d;
end

local INSERTERS = {"CreateFrame", "CreateTemplate", "CreateButton", "CreateTitle", "CreateCheckbox", "CreateRadio",
    "CreateHighlightButton", "CreateRedHighlightButton", "CreateHighlightRadio", "CreateDivider", "CreateSpacer"};
for _, key in ipairs(INSERTERS) do
    Description[key] = function(self, ...)
        return self:Insert(MenuUtil[key](...));
    end
end

function Description:SetTooltip(initializer)
    self.tooltip = initializer or function(tooltip, description)
        GameTooltip_SetTitle(tooltip, MenuUtil.GetElementText(description));
    end;
end

function Description:SetTitleAndTextTooltip(tooltipTitle, tooltipText)
    self.tooltip = function(tooltip)
        GameTooltip_SetTitle(tooltip, tooltipTitle);
        GameTooltip_AddNormalLine(tooltip, tooltipText, true);
    end;
end

function Description:QueueTitle(text, color, clearQueue)
    if clearQueue then
        self:ClearQueuedDescriptions();
    end
    self:AddQueuedDescription(MenuUtil.CreateTitle(text, color));
end

function Description:QueueDivider(clearQueue)
    if clearQueue then
        self:ClearQueuedDescriptions();
    end
    self:AddQueuedDescription(MenuUtil.CreateDivider());
end

function Description:QueueSpacer(extent, clearQueue)
    if clearQueue then
        self:ClearQueuedDescriptions();
    end
    self:AddQueuedDescription(MenuUtil.CreateSpacer(extent));
end

function MenuUtil.ShowTooltipEx(owner, tooltip, func, ...)
    tooltip:SetOwner(owner, "ANCHOR_RIGHT");
    func(tooltip, ...);
    tooltip:Show();
end

function MenuUtil.HideTooltipEx(owner, tooltip)
    if tooltip:GetOwner() == owner then
        tooltip:Hide();
    end
end

function MenuUtil.HookTooltipScripts(owner, func)
    owner:HookScript("OnEnter", function()
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT");
        func(GameTooltip);
        GameTooltip:Show();
    end);
    owner:HookScript("OnLeave", function()
        GameTooltip:Hide();
    end);
end

Menu = {};

function Menu.CreateRootMenuDescription(menuMixin)
    return MenuUtil.CreateRootMenuDescription(menuMixin);
end

function Menu.PopulateDescription(generator, owner, rootDescription, ...)
    trap("menu generator", generator, owner, rootDescription, ...);
end

function Menu.ModifyMenu() end

function MenuUtil.CreateContextMenu(ownerRegion, generator, ...)
    ownerRegion = ownerRegion or UIParent;
    local root = MenuUtil.CreateRootMenuDescription(ownerRegion.menuMixin or MenuVariants.GetDefaultContextMenuMixin());
    Menu.PopulateDescription(generator, ownerRegion, root, ...);
    local menu = H.menuManager:OpenContextMenu(ownerRegion, root);
    if menu then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON);
    end
    return menu;
end

local function variadicInsert(root, inserter, ...)
    for i = 1, select("#", ...) do
        local arg = select(i, ...);
        root:Insert(inserter(unpack(arg)));
    end
end

function MenuUtil.CreateButtonMenu(dropdown, ...)
    local args = H.pack(...);
    dropdown:SetupMenu(function(_, root)
        variadicInsert(root, function(text, onClick, data)
            return MenuUtil.CreateButton(text, onClick, data);
        end, unpack(args, 1, args.n));
    end);
end

function MenuUtil.CreateCheckboxMenu(dropdown, isSelected, setSelected, ...)
    local args = H.pack(...);
    dropdown:SetupMenu(function(_, root)
        variadicInsert(root, function(text, data)
            return MenuUtil.CreateCheckbox(text, isSelected, setSelected, data);
        end, unpack(args, 1, args.n));
    end);
end

function MenuUtil.CreateRadioMenu(dropdown, isSelected, setSelected, ...)
    local args = H.pack(...);
    dropdown:SetupMenu(function(_, root)
        variadicInsert(root, function(text, data)
            return MenuUtil.CreateRadio(text, isSelected, setSelected, data);
        end, unpack(args, 1, args.n));
    end);
end

function MenuUtil.CreateButtonContextMenu(ownerRegion, ...)
    local args = H.pack(...);
    return MenuUtil.CreateContextMenu(ownerRegion, function(_, root)
        variadicInsert(root, function(text, onClick, data)
            return MenuUtil.CreateButton(text, onClick, data);
        end, unpack(args, 1, args.n));
    end);
end

function MenuUtil.CreateRadioContextMenu(ownerRegion, isSelected, setSelected, ...)
    local args = H.pack(...);
    return MenuUtil.CreateContextMenu(ownerRegion, function(_, root)
        variadicInsert(root, function(text, data)
            return MenuUtil.CreateRadio(text, isSelected, setSelected, data);
        end, unpack(args, 1, args.n));
    end);
end

function MenuUtil.CreateCheckboxContextMenu(ownerRegion, isSelected, setSelected, ...)
    local args = H.pack(...);
    return MenuUtil.CreateContextMenu(ownerRegion, function(_, root)
        variadicInsert(root, function(text, data)
            return MenuUtil.CreateCheckbox(text, isSelected, setSelected, data);
        end, unpack(args, 1, args.n));
    end);
end

---------------------------------------------------------------------------
-- menu manager: one open menu tree; a submenu opens when a scenario walks into it (H.pickDropdown path)
---------------------------------------------------------------------------
local MenuObject = {};
local MenuObjectMeta = {__index = MenuObject};
H.menus = {open = nil};

local function assignMenu(description, menu)
    for _, child in ipairs(description.elements) do
        child.menu = menu;
    end
end

local function newMenu(owner, description, parentMenu)
    local menu = setmetatable({owner = owner, description = description, parentMenu = parentMenu,
        level = parentMenu and parentMenu.level + 1 or 0}, MenuObjectMeta);
    assignMenu(description, menu);
    return menu;
end

function MenuObject:SetClosedCallback(callback)
    self.onCloseCallback = callback;
end

function MenuObject:SetMenuDescription(description)
    self.description = description;
    assignMenu(description, self);
end

function MenuObject:GetLevel()
    return self.level;
end

function MenuObject:IsMouseOver()
    return false;
end

function MenuObject:ReinitializeAll() end

function MenuObject:Close(reason)
    if self.closed then
        return;
    end
    if self.child then
        self.child:Close(reason);
    end
    self.closed = true;
    for _, child in ipairs(self.description.elements) do
        if child.menu == self then
            child.menu = nil;
        end
    end
    if self.parentMenu then
        self.parentMenu.child = nil;
    elseif H.menus.open == self then
        H.menus.open = nil;
    end
    if self.onCloseCallback then
        trap("menu closed callback", self.onCloseCallback, self, reason or MenuCloseReason.Unspecified);
    end
end

local manager = {};
H.menuManager = manager;

function manager:OpenMenu(owner, description)
    if H.menus.open then
        H.menus.open:Close(MenuCloseReason.CloseAll);
    end
    local menu = newMenu(owner, description, nil);
    H.menus.open = menu;
    return menu;
end
manager.OpenContextMenu = manager.OpenMenu;

function manager:OpenSubmenu(parentMenu, description)
    if parentMenu.child then
        parentMenu.child:Close();
    end
    local menu = newMenu(parentMenu.owner, description, parentMenu);
    parentMenu.child = menu;
    return menu;
end

function manager:IsAnyMenuOpen()
    return H.menus.open ~= nil;
end

function manager:CloseMenus()
    if H.menus.open then
        H.menus.open:Close(MenuCloseReason.CloseAll);
    end
end

function manager:Respond(menu, description, response)
    local root = menu;
    while root.parentMenu do
        root = root.parentMenu;
    end
    if response == nil or response == MenuResponse.CloseAll then
        if not description:HasElements() or description:IsSubmenuDeactivated() then
            self:CloseMenus();
        end
    elseif response == MenuResponse.Close then
        menu:Close();
    end
    for _, callback in ipairs(root.description.shared.responseCallbacks) do
        trap("menu response callback", callback, menu, description);
    end
end

function Menu.GetManager()
    return manager;
end

---------------------------------------------------------------------------
-- DropdownButton intrinsic mixin + button-state and text mixins
---------------------------------------------------------------------------
local function collectSelectionData(menuDescription)
    if not menuDescription then
        return nil, nil, {};
    end
    local firstSelected, nextRadio = nil, nil;
    local previousDescriptions, selections = {}, {};
    MenuUtil.TraverseMenu(menuDescription, function(description)
        if description:IsSelectionIgnored() then
            return;
        end
        local selected = description:IsSelected();
        if selected then
            table.insert(selections, description);
        end
        local isRadio = description:IsRadio();
        if nextRadio == nil and firstSelected ~= nil and not selected and isRadio and description:CanSelect() then
            nextRadio = description;
        end
        if isRadio and selected and firstSelected == nil then
            firstSelected = description;
        end
        if isRadio and not firstSelected then
            table.insert(previousDescriptions, description);
        end
    end);
    local previousRadio = nil;
    for _, description in ipairs_reverse(previousDescriptions) do
        if description:CanSelect() then
            previousRadio = description;
            break;
        end
    end
    return previousRadio, nextRadio, selections;
end

DropdownButtonMixin = CreateFromMixins(CallbackRegistryMixin);
DropdownButtonMixin:GenerateCallbackEvents({"OnUpdate", "OnMenuOpen", "OnMenuClose"});

function IsDropdownButtonIntrinsic(frame)
    return frame.intrinsic == "DropdownButton";
end

function DropdownButtonMixin:OnLoad_Intrinsic()
    CallbackRegistryMixin.OnLoad(self);
    self.onMenuClosedCallback = function(menu, closeReason)
        self.menu = nil;
        self:OnMenuClosed(menu, closeReason);
    end;
    self:SetMenuAnchor(AnchorUtil.CreateAnchor(self.menuPoint, self, self.menuRelativePoint, self.menuPointX,
        self.menuPointY));
end

function DropdownButtonMixin:OnEnter_Intrinsic()
    if self.canOpenOnEnter then
        self:OpenMenu();
    end
end

function DropdownButtonMixin:OnMouseDown_Intrinsic()
    if IsShiftKeyDown() then
        return;
    end
    self:SetMenuOpen(not self:IsMenuOpen());
end

function DropdownButtonMixin:OnMouseWheel_Intrinsic(delta)
    if self:IsEnabled() then
        self:Rotate(delta < 0);
    end
end

function DropdownButtonMixin:OpenMenu()
    if not self:IsEnabled() or self:IsMenuOpen() then
        return;
    end
    self:GenerateMenu();
    if not self.menuDescription then
        return;
    end
    local menu = manager:OpenMenu(self, self.menuDescription, self.menuAnchor);
    self.menu = menu;
    if menu then
        menu:SetClosedCallback(self.onMenuClosedCallback);
        self:OnMenuOpened(menu);
    end
end

function DropdownButtonMixin:CloseMenu()
    if self.menu then
        self.menu:Close();
        self.menu = nil;
    end
    self:SignalUpdate();
end

function DropdownButtonMixin:SetMenuOpen(open)
    if open then
        self:OpenMenu();
    else
        self:CloseMenu();
    end
end

function DropdownButtonMixin:SetMenuAnchor(anchor)
    self.menuAnchor = anchor;
end

function DropdownButtonMixin:RegisterMenu(menuDescription)
    assert(type(menuDescription) == "table");
    self.menuDescription = menuDescription;
    menuDescription:AddMenuResponseCallback(function(menu, description)
        self:OnMenuResponse(menu, description);
    end);
    menuDescription:AddMenuChangedCallback(function()
        self:OnMenuChanged();
    end);
    if (menuDescription:GetMinimumWidth() or 0) == 0 then
        menuDescription:SetMinimumWidth(self:GetWidth());
    end
    if self.menu then
        self.menu:SetMenuDescription(menuDescription);
    end
    trap("dropdown OnMenuAssigned", self.OnMenuAssigned, self);
end

function DropdownButtonMixin:ClearMenuState()
    self.menuDescription = nil;
    self.menuGenerator = nil;
    self:CloseMenu();
end

function DropdownButtonMixin:GetMenuDescription()
    return self.menuDescription;
end

function DropdownButtonMixin:HasElements()
    return self.menuDescription and self.menuDescription:HasElements() or false;
end

function DropdownButtonMixin:SetupMenu(generator)
    assert(type(generator) == "function", "DropdownButtonMixin:SetupMenu(generator): argument is not a function.");
    self.menuGenerator = generator;
    if self:IsShown() then
        self:GenerateMenu();
    end
end

function DropdownButtonMixin:GenerateMenu()
    local menuGenerator = self.menuGenerator;
    if not menuGenerator then
        return;
    end
    local rootDescription = self:CreateDefaultRootMenuDescription();
    Menu.PopulateDescription(menuGenerator, self, rootDescription);
    self:RegisterMenu(rootDescription);
end

function DropdownButtonMixin:CreateDefaultRootMenuDescription()
    return self:CreateRootDescription(self.menuMixin or MenuVariants.GetDefaultMenuMixin());
end

function DropdownButtonMixin:CreateRootDescription(menuMixin)
    return MenuUtil.CreateRootMenuDescription(menuMixin);
end

function DropdownButtonMixin:IsMenuOpen()
    return self.menu ~= nil;
end

function DropdownButtonMixin:SignalUpdate()
    local previousRadio, nextRadio, selections = collectSelectionData(self:GetMenuDescription());
    self:TriggerEvent(DropdownButtonMixin.Event.OnUpdate, previousRadio, nextRadio, selections);
    self:UpdateSelections(selections);
end

function DropdownButtonMixin:OnMenuResponse()
    if self.shouldRegenerateOnResponse then
        self:GenerateMenu();
    else
        self:SignalUpdate();
    end
end

function DropdownButtonMixin:EnableRegenerateOnResponse()
    self.shouldRegenerateOnResponse = true;
end

function DropdownButtonMixin:OnMenuAssigned()
    self:SignalUpdate();
end

function DropdownButtonMixin:OnMenuChanged()
    self:SignalUpdate();
end

function DropdownButtonMixin:OnMenuOpened(menu)
    PlaySound(MenuVariants.GetDropdownOpenSoundKit());
    self:TriggerEvent(DropdownButtonMixin.Event.OnMenuOpen, self);
end

function DropdownButtonMixin:OnMenuClosed(menu, closeReason)
    PlaySound(MenuVariants.GetDropdownCloseSoundKit());
    self:TriggerEvent(DropdownButtonMixin.Event.OnMenuClose, self, menu, closeReason);
end

function DropdownButtonMixin:UpdateSelections(selections)
    self:UpdateToMenuSelections(self:GetMenuDescription(), selections);
end

function DropdownButtonMixin:Update()
    self:SignalUpdate();
end

function DropdownButtonMixin:UpdateToMenuSelections() end

function DropdownButtonMixin:Pick(description, menuInputContext, menuInputButtonName)
    if description then
        local responded = description:Pick(menuInputContext, menuInputButtonName);
        if responded then
            self:UpdateToMenuSelections(self:GetMenuDescription());
            return true;
        end
    end
    return false;
end

function DropdownButtonMixin:Rotate(forward)
    if forward then
        self:Increment();
    else
        self:Decrement();
    end
end

function DropdownButtonMixin:Increment()
    local _, nextRadio = collectSelectionData(self:GetMenuDescription());
    self:Pick(nextRadio, MenuInputContext.MouseWheel);
end

function DropdownButtonMixin:Decrement()
    local previousRadio = collectSelectionData(self:GetMenuDescription());
    self:Pick(previousRadio, MenuInputContext.MouseWheel);
end

function DropdownButtonMixin:CollectSelectionData()
    return collectSelectionData(self:GetMenuDescription());
end

function DropdownButtonMixin:HasStickyFocus()
    return false;
end

ButtonStateBehaviorMixin = {};

function ButtonStateBehaviorMixin:OnLoad()
    self.over, self.down = nil, nil;
end

function ButtonStateBehaviorMixin:OnEnter()
    if self:IsEnabled() then
        self.over = true;
        self:OnButtonStateChanged();
    end
end

function ButtonStateBehaviorMixin:OnLeave()
    if self:IsEnabled() then
        self.over = nil;
        self:OnButtonStateChanged();
    end
end

function ButtonStateBehaviorMixin:OnMouseDown()
    if self:IsEnabled() then
        self.down = true;
        self:OnButtonStateChanged();
        return true;
    end
    return false;
end

function ButtonStateBehaviorMixin:OnMouseUp()
    if self:IsEnabled() then
        self.down = nil;
        self:OnButtonStateChanged();
        return true;
    end
    return false;
end

function ButtonStateBehaviorMixin:OnEnable()
    self:OnButtonStateChanged();
end

function ButtonStateBehaviorMixin:OnDisable()
    self:OnButtonStateChanged();
end

function ButtonStateBehaviorMixin:IsDown()
    return self.down;
end

function ButtonStateBehaviorMixin:IsOver()
    return self.over;
end

function ButtonStateBehaviorMixin:IsDownOver()
    return self.down and self.over;
end

function ButtonStateBehaviorMixin:OnButtonStateChanged() end

DropdownTextMixin = {};

function DropdownTextMixin:OnLoad()
    if self.text then
        self:SetText(self.text);
    end
end

function DropdownTextMixin:GetText()
    return self.text;
end

function DropdownTextMixin:SetText(text)
    self.text = text;
    self:UpdateText();
end

function DropdownTextMixin:GetUpdateText()
    return self.text;
end

function DropdownTextMixin:UpdateText()
    self.Text:SetText(self:GetUpdateText());
    if self.resizeToText then
        local newWidth = self.Text:GetUnboundedStringWidth() + (self.resizeToTextPadding or 0);
        if self.resizeToTextMaxWidth then
            newWidth = math.min(self.resizeToTextMaxWidth, newWidth);
        end
        if self.resizeToTextMinWidth then
            newWidth = math.max(self.resizeToTextMinWidth, newWidth);
        end
        self:SetWidth(newWidth);
    end
end

function DropdownTextMixin:UpdateToMenuSelections()
    self:UpdateText();
end

DropdownSelectionTextMixin = CreateFromMixins(DropdownTextMixin);

local function defaultSelectionTranslator(selection)
    return MenuUtil.GetElementText(selection);
end

function DropdownSelectionTextMixin:OnLoad()
    DropdownTextMixin.OnLoad(self);
    self:SetSelectionTranslator(defaultSelectionTranslator);
end

function DropdownSelectionTextMixin:GetUpdateText()
    return self.text or self.defaultText;
end

function DropdownSelectionTextMixin:GetDefaultText()
    return self.defaultText;
end

function DropdownSelectionTextMixin:SetDefaultText(text)
    self.defaultText = text;
    self:UpdateText();
end

function DropdownSelectionTextMixin:SetSelectionTranslator(translator)
    self.selectionTranslator = translator;
end

function DropdownSelectionTextMixin:SetSelectionText(selectionFunc)
    self.selectionFunc = selectionFunc;
end

function DropdownSelectionTextMixin:OverrideText(text)
    if not text then
        return;
    end
    self.disableSelectionText = true;
    self:SetText(text);
end

function DropdownSelectionTextMixin:UpdateToMenuSelections(menuDescription, currentSelections)
    if self.disableSelectionText then
        return;
    end
    if not currentSelections and menuDescription then
        currentSelections = MenuUtil.GetSelections(menuDescription);
    end
    local text = nil;
    if self.selectionFunc then
        text = self.selectionFunc(currentSelections);
    end
    if text == nil and currentSelections then
        local texts = {};
        for _, selection in ipairs(currentSelections) do
            if not selection:IsSelectionIgnored() then
                table.insert(texts, self.selectionTranslator(selection));
            end
        end
        if #texts > 0 then
            text = self.dontConcatenateText and texts[1] or table.concat(texts, LIST_DELIMITER);
        end
    end
    self:SetText(text or self.defaultText);
end

function DropdownSelectionTextMixin:OnShow()
    self:GenerateMenu();
end

function DropdownSelectionTextMixin:OnEnter()
    ButtonStateBehaviorMixin.OnEnter(self);
end

function DropdownSelectionTextMixin:OnLeave()
    ButtonStateBehaviorMixin.OnLeave(self);
end

function DropdownSelectionTextMixin:SetTooltip(tooltipFunc)
    self.tooltipFunc = tooltipFunc;
end

local function arrowState(button, shadowless)
    local suffix = shadowless and "-shadowless" or "";
    if button:IsEnabled() then
        if button:IsDownOver() then
            return "common-dropdown-a-button-pressedhover" .. suffix;
        elseif button:IsOver() then
            return "common-dropdown-a-button-hover" .. suffix;
        elseif button:IsDown() then
            return "common-dropdown-a-button-pressed" .. suffix;
        elseif button:IsMenuOpen() then
            return "common-dropdown-a-button-open" .. suffix;
        end
        return "common-dropdown-a-button" .. suffix;
    end
    return "common-dropdown-a-button-disabled" .. suffix;
end

WowStyle1DropdownMixin = CreateFromMixins(ButtonStateBehaviorMixin, DropdownSelectionTextMixin);

function WowStyle1DropdownMixin:OnLoad()
    if not IsDropdownButtonIntrinsic(self) then
        H.recordError("WowStyle1DropdownMixin:OnLoad", {msg = H.describe(self) ..
            " element is not a DropdownButton (create it with CreateFrame(\"DropdownButton\", ...))", trace = ""});
    end
    ButtonStateBehaviorMixin.OnLoad(self);
    DropdownSelectionTextMixin.OnLoad(self);
end

function WowStyle1DropdownMixin:GetArrowAtlas()
    return arrowState(self);
end

function WowStyle1DropdownMixin:OnButtonStateChanged()
    if self:IsEnabled() then
        self.Text:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB());
    else
        self.Text:SetTextColor(DISABLED_FONT_COLOR:GetRGB());
    end
    self.Arrow:SetAtlas(self:GetArrowAtlas(), true);
end

WowStyle1ArrowDropdownMixin = CreateFromMixins(ButtonStateBehaviorMixin);

function WowStyle1ArrowDropdownMixin:OnButtonStateChanged()
    self.Arrow:SetAtlas(arrowState(self, not self.hasShadow), true);
end

WowStyle1FilterDropdownMixin = CreateFromMixins(ButtonStateBehaviorMixin, DropdownTextMixin);

function WowStyle1FilterDropdownMixin:OnLoad()
    ButtonStateBehaviorMixin.OnLoad(self);
    DropdownTextMixin.OnLoad(self);
end

function WowStyle1FilterDropdownMixin:OnButtonStateChanged()
    self.Background:SetAtlas(self:IsEnabled() and "common-dropdown-b-button" or "common-dropdown-b-button-disabled",
        true);
end

WowStyle2DropdownMixin = CreateFromMixins(ButtonStateBehaviorMixin, DropdownSelectionTextMixin);

function WowStyle2DropdownMixin:OnLoad()
    ButtonStateBehaviorMixin.OnLoad(self);
    DropdownSelectionTextMixin.OnLoad(self);
end

function WowStyle2DropdownMixin:OnButtonStateChanged()
    self.Text:SetTextColor((self:IsEnabled() and HIGHLIGHT_FONT_COLOR or DISABLED_FONT_COLOR):GetRGB());
end

local function method(name)
    return function(self, ...)
        local m = self[name];
        if m then
            return m(self, ...);
        end
    end
end

local function dropdownScripts(f, scripts)
    for _, s in ipairs(scripts) do
        H.setXmlScript(f, s, method(s));
    end
end

H.defineTemplate("WowStyle1DropdownTemplate", "DropdownButton", 120, 25, function(f)
    P[f].width, P[f].height = 120, 25;
    H.addTexture(f, {key = "Background", layer = "BACKGROUND", atlas = "common-dropdown-textholder",
        anchors = {{"TOPLEFT", nil, nil, -8, 7}, {"BOTTOMRIGHT", nil, nil, 8, -9}}});
    H.addTexture(f, {key = "Arrow", layer = "OVERLAY", atlas = "common-dropdown-a-button",
        anchors = {{"RIGHT", nil, "RIGHT", 1, -3}}});
    H.addFontString(f, {key = "Text", layer = "OVERLAY", font = "GameFontHighlight", size = {0, 10},
        anchors = {{"TOPRIGHT", f.Arrow, "LEFT"}, {"TOPLEFT", nil, nil, 8, -8}}});
    Mixin(f, WowStyle1DropdownMixin);
    dropdownScripts(f, {"OnLoad", "OnShow", "OnMouseDown", "OnMouseUp", "OnEnter", "OnLeave", "OnEnable", "OnDisable"});
end);

H.defineTemplate("WowStyle1ArrowDropdownTemplate", "DropdownButton", 25, 25, function(f)
    P[f].width, P[f].height = 25, 25;
    f.hasShadow = true;
    H.addTexture(f, {key = "Arrow", layer = "OVERLAY", anchors = {{"CENTER", nil, nil, 0, -2}}});
    Mixin(f, WowStyle1ArrowDropdownMixin);
    dropdownScripts(f, {"OnLoad", "OnMouseDown", "OnMouseUp", "OnEnter", "OnLeave", "OnEnable", "OnDisable"});
end);

H.defineTemplate("WowStyle1FilterDropdownTemplate", "DropdownButton", 135, 18, function(f)
    P[f].width, P[f].height = 135, 18;
    f.text, f.disableFontObject, f.menuRelativePoint = FILTER, "GameFontDisable", "BOTTOMLEFT";
    f.menuPointX, f.menuPointY, f.resizeToText, f.resizeToTextPadding = 6, 2, true, 60;
    H.addTexture(f, {key = "Background", layer = "BACKGROUND", atlas = "common-dropdown-b-button",
        anchors = {{"TOPLEFT", nil, nil, -4, 4}, {"BOTTOMRIGHT", nil, nil, 4, -4}}});
    H.addFontString(f, {key = "Text", layer = "OVERLAY", font = "GameFontNormal", size = {0, 20}, anchors = {{"TOP"}}});
    local reset = H.addChild(f, "Button", {key = "ResetButton", hidden = true,
        anchors = {{"CENTER", nil, "TOPRIGHT", -3, 0}}});
    P[reset].width, P[reset].height = 16, 16;
    Mixin(f, WowStyle1FilterDropdownMixin);
    dropdownScripts(f, {"OnLoad", "OnMouseDown", "OnMouseUp", "OnShow", "OnEnter", "OnLeave", "OnEnable", "OnDisable"});
end);

H.defineTemplate("WowStyle2DropdownTemplate", "DropdownButton", 120, 25, function(f)
    P[f].width, P[f].height = 120, 25;
    H.addTexture(f, {key = "Background", layer = "BACKGROUND", atlas = "common-dropdown-c-button",
        setAllPoints = true});
    H.addTexture(f, {key = "Arrow", layer = "OVERLAY", atlas = "common-dropdown-c-button-arrow",
        anchors = {{"RIGHT", nil, nil, -6, 0}}});
    H.addFontString(f, {key = "Text", layer = "OVERLAY", font = "GameFontHighlight", size = {0, 10},
        anchors = {{"LEFT", nil, nil, 9, 0}, {"RIGHT", f.Arrow, "LEFT"}}});
    Mixin(f, WowStyle2DropdownMixin);
    dropdownScripts(f, {"OnLoad", "OnShow", "OnMouseDown", "OnMouseUp", "OnEnter", "OnLeave", "OnEnable", "OnDisable"});
end);

---------------------------------------------------------------------------
-- tooltip helpers used by menu tooltips (GameTooltip_* exist on Forever)
---------------------------------------------------------------------------
function GameTooltip_SetTitle(tooltip, text)
    tooltip:SetText(text);
end

function GameTooltip_AddNormalLine(tooltip, text)
    tooltip:AddLine(text);
end

function GameTooltip_AddHighlightLine(tooltip, text)
    tooltip:AddLine(text);
end

function GameTooltip_AddErrorLine(tooltip, text)
    tooltip:AddLine(text);
end

function GameTooltip_AddInstructionLine(tooltip, text)
    tooltip:AddLine(text);
end

function GameTooltip_AddColoredLine(tooltip, text)
    tooltip:AddLine(text);
end

function GameTooltip_AddBlankLineToTooltip(tooltip)
    tooltip:AddLine(" ");
end

---------------------------------------------------------------------------
-- scenario helpers
---------------------------------------------------------------------------
-- The player presses and releases a mouse button on a frame (OnMouseDown, then OnMouseUp).
function H.mouseDown(frame, button)
    H.fireScript(frame, "OnMouseDown", button or "LeftButton");
    H.fireScript(frame, "OnMouseUp", button or "LeftButton", true);
end

local function entryList(description)
    local list = {};
    for _, d in description:EnumerateElementDescriptions() do
        list[#list + 1] = {text = MenuUtil.GetElementText(d), selected = d:IsSelected(), enabled = d:IsEnabled(),
            radio = d:IsRadio(), checkbox = d:IsCheckbox(), title = d.isTitle == true, divider = d.isDivider == true,
            submenu = d:HasElements(), description = d};
    end
    return list;
end

local function findEntry(description, text, path)
    local available = {};
    for _, d in description:EnumerateElementDescriptions() do
        local t = MenuUtil.GetElementText(d);
        if t == text then
            return d;
        end
        if t then
            available[#available + 1] = t;
        end
    end
    error("harness: no menu entry '" .. tostring(text) .. "' at " .. path .. " (entries: " ..
        table.concat(available, ", ") .. ")", 4);
end

-- The player clicks the dropdown open (it must be visible and enabled). Returns the root menu description.
function H.openDropdown(dd)
    if not (dd and dd.SetupMenu) then
        error("harness: not a dropdown button", 2);
    end
    if not dd:IsVisible() then
        error("harness: dropdown " .. H.describe(dd) .. " is not visible", 2);
    end
    if not dd:IsEnabled() then
        error("harness: dropdown " .. H.describe(dd) .. " is disabled", 2);
    end
    if not dd:IsMenuOpen() then
        H.mouseDown(dd);
    end
    if not dd:IsMenuOpen() then
        error("harness: dropdown " .. H.describe(dd) .. " did not open (no menu set up?)", 2);
    end
    return dd:GetMenuDescription();
end

local function pickPath(menu, ...)
    local description = menu.description;
    local path = "root";
    local count = select("#", ...);
    for i = 1, count do
        local text = select(i, ...);
        local entry = findEntry(description, text, path);
        path = path .. " > " .. text;
        if i < count then
            if not entry:HasElements() then
                error("harness: menu entry '" .. text .. "' has no submenu", 3);
            end
            menu = manager:OpenSubmenu(menu, entry);
            description = entry;
        else
            if not entry:CanSelect() then
                error("harness: menu entry '" .. path .. "' is disabled", 3);
            end
            local _, response = entry:Pick(MenuInputContext.MouseButton, "LeftButton");
            return response;
        end
    end
end

-- The player opens the dropdown and clicks the entry with this text (more texts walk into submenus).
-- Returns the menu response of the entry (nil = the menu closed).
function H.pickDropdown(dd, ...)
    H.openDropdown(dd);
    return pickPath(dd.menu, ...);
end

-- The text the dropdown shows.
function H.dropdownText(dd)
    return dd.Text and dd.Text:GetText();
end

-- The entries of the dropdown's menu (generated fresh, like opening it), optionally of a submenu path:
-- {text, selected, enabled, radio, checkbox, title, divider, submenu, description}.
function H.dropdownEntries(dd, ...)
    dd:GenerateMenu();
    local description = dd:GetMenuDescription();
    if not description then
        return {};
    end
    for i = 1, select("#", ...) do
        description = findEntry(description, (select(i, ...)), "root");
    end
    return entryList(description);
end

-- The entries of the open menu (a context menu or an open dropdown), nil when none is open.
function H.menuEntries()
    return H.menus.open and entryList(H.menus.open.description);
end

function H.closeMenus()
    manager:CloseMenus();
end

-- The player clicks the entry with this text in the open MenuUtil menu, or else in the legacy UIDropDownMenu built
-- last.
local legacyClickMenuEntry = H.clickMenuEntry;
function H.clickMenuEntry(text, ...)
    if H.menus.open then
        return pickPath(H.menus.open, text, ...);
    end
    return legacyClickMenuEntry(text);
end
