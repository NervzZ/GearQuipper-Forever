-- scope stuff
gearquipper = gearquipper or {};
local c = gearquipper;
c.isFrameHooked = {};

-- last open panel tab (GQ_OPTIONS)
c.OPT_PANELTAB = "OPT_PANELTAB";
local PANELTAB_SETS, PANELTAB_EVENTS = "SETS", "EVENTS";
local TAB_IDS = {[PANELTAB_SETS] = 1, [PANELTAB_EVENTS] = 2};
local TAB_KEYS = {PANELTAB_SETS, PANELTAB_EVENTS};

-- panel geometry; the panel is as tall as the character window
local DEFAULT_PANEL_HEIGHT = CHARACTER_FRAME_HEIGHT or 484;
local INSET_TOP, INSET_BOTTOM = 56, 58;
local LIST_INSET, SCROLLBAR_SPACE = 4, 18;

local SET_ROW_HEIGHT, SET_ROW_SPACING = 44, 2;
local ICON_FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark";
local ICON_CROP_STOCK, ICON_CROP_SKINNED = 0.03125, 0.08;

local built;
local setsPage, setList, statusText, emptySetsText, btnAddSet, btnSaveSet;
local panelLists = {};
-- rows of the switching set stay bright while the others dim; kept here so recycled rows get it too
local lockState = {locked = false, setName = nil};

----- shared panel building blocks -----

-- A list inside the panel's inset: WowScrollBoxList + MinimalScrollBar (hidden while everything fits).
function c:CreatePanelList(parent, name, extent, spacing, initializer)
    local inset = GqUiFrame.Inset;
    local box = CreateFrame("Frame", name, parent, "WowScrollBoxList");
    local bar = CreateFrame("EventFrame", name .. "ScrollBar", parent, "MinimalScrollBar");
    bar:SetPoint("TOPLEFT", inset, "TOPRIGHT", -14, -6);
    bar:SetPoint("BOTTOMLEFT", inset, "BOTTOMRIGHT", -14, 6);

    local view = CreateScrollBoxListLinearView(0, 0, 0, 0, spacing);
    view:SetElementExtent(extent);
    view:SetElementInitializer("Button", initializer);
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view);

    local withBar = {CreateAnchor("TOPLEFT", inset, "TOPLEFT", LIST_INSET, -LIST_INSET),
        CreateAnchor("TOPRIGHT", inset, "TOPRIGHT", -SCROLLBAR_SPACE, -LIST_INSET)};
    local withoutBar = {CreateAnchor("TOPLEFT", inset, "TOPLEFT", LIST_INSET, -LIST_INSET),
        CreateAnchor("TOPRIGHT", inset, "TOPRIGHT", -LIST_INSET, -LIST_INSET)};
    ScrollUtil.AddManagedScrollBarVisibilityBehavior(box, bar, withBar, withoutBar);

    c:Skin("scrollbar", bar);
    table.insert(panelLists, box);
    box:SetHeight(GqUiFrame:GetHeight() - INSET_TOP - INSET_BOTTOM - 2 * LIST_INSET);
    return box, bar;
end

-- Hint centred in the inset while a list is empty.
function c:CreatePanelEmptyText(parent, text)
    local fontString = parent:CreateFontString(nil, "ARTWORK", "GameFontDisable");
    fontString:SetPoint("CENTER", GqUiFrame.Inset, "CENTER", 0, 0);
    fontString:SetText(text);
    fontString:Hide();
    c:Skin("font", fontString);
    return fontString;
end

function c:IsUiLocked()
    return lockState.locked;
end

-- the panel follows the character window's height (lists get an explicit height: they scroll by it)
local function SyncPanelHeight()
    local height = c.paperDollFrame and c.paperDollFrame:GetHeight();
    if not height or height < 200 then
        height = DEFAULT_PANEL_HEIGHT;
    end
    if GqUiFrame:GetHeight() ~= height then
        GqUiFrame:SetHeight(height);
    end
    for _, box in ipairs(panelLists) do
        box:SetHeight(height - INSET_TOP - INSET_BOTTOM - 2 * LIST_INSET);
    end
end

----- tabs -----

local function GetSavedTab()
    local tab = GQ_OPTIONS[c.OPT_PANELTAB];
    if TAB_IDS[tab] then
        return tab;
    end
    return PANELTAB_SETS;
end

local function SelectTab(tab, byClick)
    GQ_OPTIONS[c.OPT_PANELTAB] = tab;
    PanelTemplates_SetTab(GqUiFrame, TAB_IDS[tab]);
    setsPage:SetShown(tab == PANELTAB_SETS);
    c:ShowEventsPage(tab == PANELTAB_EVENTS);
    if byClick then
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB);
    end
end

----- sets page -----

local function GetSetIcon(setName)
    local function IconOf(slotId)
        local itemString = c:LoadSlot(slotId, setName);
        if type(itemString) == "string" and not c:IsEmpty(itemString) then
            return (select(5, c:GetItemInfoInstant(itemString)));
        end
    end

    local icon = IconOf(INVSLOT_MAINHAND) or IconOf(INVSLOT_CHEST);
    for slotId = 1, 19 do
        if icon then
            break
        end
        icon = IconOf(slotId);
    end
    return icon or ICON_FALLBACK;
end

-- spec groups whose "on talents change" binding switches to this set
local function GetBoundSpecGroups(setName)
    local groups, seen = {}, {};
    for _, binding in ipairs(c:LoadEventBindings() or {}) do
        local subType = binding[c.FIELD_SUBTYPE];
        if binding[c.FIELD_TYPE] == c.EVENT_TALENTS_CHANGED and binding[c.FIELD_NAME] == setName and
            type(subType) == "table" then
            local group = tonumber(subType.spellId);
            if group and not seen[group] then
                seen[group] = true;
                table.insert(groups, group);
            end
        end
    end
    table.sort(groups);
    return groups;
end

local function SetStatusText(text)
    if statusText then
        statusText:SetText(text);
    end
end

local function ShowCurrentSetStatus()
    local currentSet = c:LoadCurrentSetName();
    SetStatusText(c:GetText("%s: %s", c:GetText("Current set"),
        currentSet and c:ColorizeSetName(currentSet) or UNKNOWN));
end

local function SetNameColor(row, setName)
    local r, g, b = c:GetSetColorRGB(setName);
    if r then
        row.Name:SetTextColor(r, g, b);
    else
        row.Name:SetTextColor(unpack(row.nameColor));
    end
end

local function ShowSetTooltip(row, setName)
    local isSetAvailable, missingItems = c:IsSetAvailable(setName);
    if not isSetAvailable then
        local tt = c:GetGqTooltip();
        tt:SetOwner(row, "ANCHOR_RIGHT");
        tt:AddLine(c:GetText("Missing Items: %s", c:GetTableSize(missingItems)));
        tt:AddLine(" ");
        for slotId, itemString in pairs(missingItems) do
            tt:AddLine(c:GetDisplaySlotName(slotId) .. ": " .. c:GetItemLink(itemString));
        end
        tt:Show();
    end
end

local function SetHoverShown(row, shown)
    local skinned = c:GetSkinBackend() ~= nil;
    row.HighlightBar:SetShown(shown and not skinned);
    row.FlatHover:SetShown(shown and skinned);
end

local function EquipSet(setName)
    c:ResetIgnoredSlots();
    c:QueueSwitch({
        [c.SWITCHARG_SETNAME] = setName
    });
end

local function SaveWornGear(setName)
    if setName then
        c:SaveSet(setName);
        c:SetPaperDollLabelText();
        c:SetSlotInfo();
        c:UpdateBroker();
    end
end

local function SetPartial(setName, value)
    c:SavePartialOption(setName, value);
    if setName == c:LoadCurrentSetName() then
        if value then
            c:ShowSlotStateBoxes();
        else
            c:HideSlotStateBoxes();
        end
    end
    c:SetSlotInfo();
    c:RefreshSetList(true);
end

-- menu entries act only while the panel is unlocked, like the rows and buttons (LockUI also closes the menu)
local function WhenUnlocked(func)
    return function(...)
        if not lockState.locked then
            return func(...);
        end
    end;
end

local function IsPaletteColor(hex)
    for _, entry in ipairs(c:GetSetColorPalette()) do
        if entry.hex == hex then
            return true;
        end
    end
    return false;
end

local function ToHex(r, g, b)
    return string.format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5));
end

-- live preview while the picker is open; Cancel, Escape or a click outside puts the old colour back
local function PickCustomColor(setName)
    local previous = c:LoadSetColor(setName);
    local r, g, b = 1, 1, 1;
    if previous then
        r, g, b = c:GetSetColorRGB(setName);
    end
    ColorPickerFrame:SetupColorPickerAndShow({
        r = r,
        g = g,
        b = b,
        swatchFunc = function()
            c:SaveSetColor(setName, ToHex(ColorPickerFrame:GetColorRGB()));
        end,
        cancelFunc = function()
            c:SaveSetColor(setName, previous);
        end
    });
end

-- "Colour" submenu: the palette (each name in its colour), Custom... (in the custom colour once one is set), None
local function AddColorMenu(root, setName)
    local colorMenu = root:CreateButton(c:GetText("Colour"));
    local function IsSelected(hex)
        return c:LoadSetColor(setName) == hex;
    end
    local function SetSelected(hex)
        c:SaveSetColor(setName, hex);
    end
    for _, entry in ipairs(c:GetSetColorPalette()) do
        colorMenu:CreateRadio(c:FormatTextWithColor(c:GetText(entry.name), entry.hex), IsSelected,
            WhenUnlocked(SetSelected), entry.hex);
    end

    colorMenu:CreateDivider();
    local current = c:LoadSetColor(setName);
    local isCustom = current ~= nil and not IsPaletteColor(current);
    local customText = c:GetText("Custom...");
    if isCustom then
        customText = c:FormatTextWithColor(customText, current);
    end
    local custom = colorMenu:CreateRadio(customText, function()
        return isCustom;
    end, WhenUnlocked(function()
        PickCustomColor(setName);
    end));
    custom:SetEnabled(ColorPickerFrame ~= nil and ColorPickerFrame.SetupColorPickerAndShow ~= nil);
    colorMenu:CreateRadio(c:GetText("None"), IsSelected, WhenUnlocked(SetSelected));
end

local function OpenSetMenu(row, setName)
    c:OpenContextMenu("set", row, function(owner, root)
        root:CreateTitle(c:ColorizeSetName(setName));
        root:CreateButton(c:GetText("Equip"), WhenUnlocked(function()
            EquipSet(setName);
        end));
        root:CreateButton(c:GetText("Save worn gear into this set"), WhenUnlocked(function()
            SaveWornGear(setName);
        end));

        -- the slot boxes on the character sheet edit the current set only
        local isCurrent = setName == c:LoadCurrentSetName();
        local partial = root:CreateCheckbox(c:GetText("Partial set"), function()
            return c:LoadPartialOption(setName) == true;
        end, WhenUnlocked(function()
            SetPartial(setName, not c:LoadPartialOption(setName));
        end));
        partial:SetEnabled(isCurrent);
        if not isCurrent then
            partial:SetTooltip(function(tooltip)
                GameTooltip_SetTitle(tooltip, c:GetText("Partial set"));
                GameTooltip_AddNormalLine(tooltip, c:GetText("Equip the set to choose its slots."));
            end);
        end
        AddColorMenu(root, setName);

        root:CreateDivider();
        local atBank = c:IsAtBank() == true;
        root:CreateButton(c:GetText("Put in bank"), WhenUnlocked(function()
            c:PushSetToBank(setName);
        end)):SetEnabled(atBank);
        root:CreateButton(c:GetText("Take from bank"), WhenUnlocked(function()
            c:PullSetFromBank(setName);
        end)):SetEnabled(atBank);

        root:CreateDivider();
        root:CreateButton(c:GetText("Delete..."), WhenUnlocked(function()
            c:ShowRemoveSetDialog(setName);
        end));
    end);
end

local function GetRowSetName(row)
    local data = row:GetElementData();
    return data and data.setName;
end

local function ApplySetRowLock(row)
    local locked = lockState.locked;
    row:SetEnabled(not locked);
    row:SetAlpha((locked and GetRowSetName(row) ~= lockState.setName) and 0.5 or 1);
    row.ToBank:SetEnabled(not locked);
    row.ToBags:SetEnabled(not locked);
end

local function CreateBankButton(row, text, onClick)
    local button = CreateFrame("Button", nil, row, "SharedButtonExtraSmallTemplate");
    button:SetSize(46, 20);
    button:SetText(text);
    button:SetFrameLevel(row:GetFrameLevel() + 3);
    button:SetScript("OnClick", function()
        local setName = GetRowSetName(row);
        if setName then
            onClick(setName);
        end
    end);
    button:Hide();
    return button;
end

-- One-time parts of a set row (Blizzard's gear set card). Every texture lives on a child frame: EllesmereUI fades
-- the own textures of the frames it skinned (rows are skinned as panels) again and again.
local function BuildSetRow(row)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp");

    -- stock look: the outfit card of Blizzard's equipment manager
    row.Art = CreateFrame("Frame", nil, row);
    row.Art:SetAllPoints();
    row.Art:SetFrameLevel(row:GetFrameLevel() + 1);
    row.Card = row.Art:CreateTexture(nil, "BACKGROUND", nil, 0);
    row.Card:SetAtlas("UI-Character-Info-OutfitCard");
    row.Card:SetPoint("TOPLEFT", 42, 0);
    row.Card:SetPoint("TOPRIGHT", 0, 0);
    row.Card:SetHeight(SET_ROW_HEIGHT + 5);
    row.HighlightBar = row.Art:CreateTexture(nil, "BACKGROUND", nil, 1);
    row.HighlightBar:SetAtlas("UI-Character-Info-OutfitCard-Hover");
    row.HighlightBar:SetAllPoints(row.Card);
    row.HighlightBar:Hide();
    row.SelectedBar = row.Art:CreateTexture(nil, "BACKGROUND", nil, 2);
    row.SelectedBar:SetAtlas("UI-Character-Info-OutfitCard-Selected");
    row.SelectedBar:SetAllPoints(row.Card);
    row.SelectedBar:Hide();

    -- skinned look: flat bars
    row.Flat = CreateFrame("Frame", nil, row);
    row.Flat:SetAllPoints();
    row.Flat:SetFrameLevel(row:GetFrameLevel() + 1);
    row.FlatSelected = row.Flat:CreateTexture(nil, "BACKGROUND");
    row.FlatSelected:SetColorTexture(1, 1, 1, 0.12);
    row.FlatSelected:SetAllPoints();
    row.FlatSelected:Hide();
    row.FlatHover = row.Flat:CreateTexture(nil, "BORDER");
    row.FlatHover:SetColorTexture(1, 1, 1, 0.08);
    row.FlatHover:SetAllPoints();
    row.FlatHover:Hide();

    row.Content = CreateFrame("Frame", nil, row);
    row.Content:SetAllPoints();
    row.Content:SetFrameLevel(row:GetFrameLevel() + 2);
    row.Icon = row.Content:CreateTexture(nil, "ARTWORK");
    row.Icon:SetSize(36, 36);
    row.Icon:SetPoint("LEFT", 4, 0);
    row.IconBorder = row.Content:CreateTexture(nil, "OVERLAY", nil, 0);
    row.IconBorder:SetAtlas("UI-Character-Info-OutfitIcon-Frame", true);
    row.IconBorder:SetPoint("CENTER", row.Icon, "CENTER");

    row.Name = row.Content:CreateFontString(nil, "ARTWORK", "GameFontNormalLeft");
    row.Name:SetWordWrap(false);
    row.nameColor = {row.Name:GetTextColor()};
    row.Partial = row.Content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmallLeft");
    row.Partial:SetPoint("TOPLEFT", row.Name, "BOTTOMLEFT", 0, -2);
    row.Partial:SetText(c:GetText("partial"));
    row.Missing = row.Content:CreateFontString(nil, "ARTWORK", "GameFontRedSmall");
    row.Missing:SetTextColor(RED_FONT_COLOR:GetRGB());
    row.Missing:SetText(c:GetText("missing"));

    row.Tick = row.Content:CreateTexture(nil, "OVERLAY");
    row.Tick:SetAtlas("UI-Character-Info-Icon-Tick", true);
    row.Tick:SetPoint("RIGHT", -8, 0);

    -- spec badge on the icon's corner, like Blizzard's spec ring
    row.SpecBadge = CreateFrame("Frame", nil, row.Content);
    row.SpecBadge:SetSize(20, 20);
    row.SpecBadge:SetPoint("CENTER", row.Icon, "BOTTOMRIGHT", -3, 3);
    row.SpecRing = row.SpecBadge:CreateTexture(nil, "ARTWORK");
    row.SpecRing:SetAtlas("equipmentmanager-spec-border", true);
    row.SpecRing:SetPoint("CENTER");
    row.SpecPlate = row.SpecBadge:CreateTexture(nil, "BACKGROUND");
    row.SpecPlate:SetColorTexture(0, 0, 0, 0.75);
    row.SpecPlate:SetAllPoints();
    row.SpecText = row.SpecBadge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    row.SpecText:SetPoint("CENTER", 0, 0);

    row.ToBags = CreateBankButton(row, c:GetText("-> Bag"), function(setName)
        c:PullSetFromBank(setName);
    end);
    row.ToBags:SetPoint("RIGHT", row.Tick, "LEFT", -4, 0);
    row.ToBank = CreateBankButton(row, c:GetText("-> Bank"), function(setName)
        c:PushSetToBank(setName);
    end);
    row.ToBank:SetPoint("RIGHT", row.ToBags, "LEFT", -2, 0);

    row:SetScript("OnClick", function(self, button)
        local setName = GetRowSetName(self);
        if not setName then
            return;
        end
        if button == "RightButton" then
            OpenSetMenu(self, setName);
        else
            EquipSet(setName);
        end
    end);
    row:SetScript("OnEnter", function(self)
        local setName = GetRowSetName(self);
        if not setName then
            return;
        end
        local setItems = c:LoadSet(setName);
        c:HighlightItemsEquipped(setItems, setName);
        c:HighlightItemsInBags(setItems);
        self.Name:SetTextColor(1, 1, 1, 1);
        SetHoverShown(self, true);
        ShowSetTooltip(self, setName);
        SetStatusText(c:GetText("Left-click: equip. Right-click: more."));
    end);
    row:SetScript("OnLeave", function(self)
        c:HighlightItemsEquipped();
        c:HighlightItemsInBags();
        local setName = GetRowSetName(self);
        if setName then
            SetNameColor(self, setName);
        end
        SetHoverShown(self, false);
        c:HideGqTooltips();
        ShowCurrentSetStatus();
    end);
end

local function InitSetRow(row, data)
    if not row.Content then
        BuildSetRow(row);
    end
    c:Skin("panel", row);
    c:Skin("font", row.Name);
    c:Skin("font", row.Partial);
    c:Skin("font", row.Missing);
    c:Skin("font", row.SpecText);
    c:Skin("button", row.ToBank);
    c:Skin("button", row.ToBags);

    local setName = data.setName;
    local skinned = c:GetSkinBackend() ~= nil;
    local isCurrent = setName == c:LoadCurrentSetName();

    row.Icon:SetTexture(GetSetIcon(setName));
    local crop = skinned and ICON_CROP_SKINNED or ICON_CROP_STOCK;
    row.Icon:SetTexCoord(crop, 1 - crop, crop, 1 - crop);
    row.IconBorder:SetShown(not skinned);

    row.Card:SetShown(not skinned);
    row.SelectedBar:SetShown(isCurrent and not skinned);
    row.FlatSelected:SetShown(isCurrent and skinned);
    SetHoverShown(row, false);
    row.Tick:SetShown(isCurrent);

    local groups = GetBoundSpecGroups(setName);
    row.SpecBadge:SetShown(#groups > 0);
    row.SpecText:SetText(table.concat(groups, "/"));
    row.SpecRing:SetShown(not skinned);
    row.SpecPlate:SetShown(skinned);

    local atBank = c:IsAtBank() == true;
    row.ToBank:SetShown(atBank);
    row.ToBags:SetShown(atBank);

    local isPartial = c:LoadPartialOption(setName) == true;
    local isMissing = not c:IsSetAvailable(setName);
    local nameOffset = (isPartial or isMissing) and 6 or 0;
    row.Partial:SetShown(isPartial);
    row.Missing:SetShown(isMissing);
    row.Missing:ClearAllPoints();
    if isPartial then
        row.Missing:SetPoint("LEFT", row.Partial, "RIGHT", 6, 0);
    else
        row.Missing:SetPoint("TOPLEFT", row.Name, "BOTTOMLEFT", 0, -2);
    end
    row.Name:SetText(setName);
    row.Name:ClearAllPoints();
    row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 10, nameOffset);
    row.Name:SetPoint("RIGHT", atBank and row.ToBank or row.Tick, "LEFT", -4, nameOffset);
    SetNameColor(row, setName);

    ApplySetRowLock(row);
end

local function BuildSetsPage(f)
    setsPage = CreateFrame("Frame", "GqUiFrameSetsPage", f);
    setsPage:SetAllPoints();
    setsPage:SetFrameLevel(f.Inset:GetFrameLevel() + 2);

    setList = c:CreatePanelList(setsPage, "GqUiFrameSetList", SET_ROW_HEIGHT, SET_ROW_SPACING, InitSetRow);
    emptySetsText = c:CreatePanelEmptyText(setsPage, c:GetText("No sets yet."));

    statusText = setsPage:CreateFontString("GqUiFrameStatusText", "ARTWORK", "GameFontHighlightSmall");
    statusText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 40);
    statusText:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 40);
    statusText:SetJustifyH("LEFT");
    statusText:SetWordWrap(false);
    c:Skin("font", statusText);

    btnAddSet = CreateFrame("Button", "GqAddSetButton", setsPage, "SharedButtonSmallTemplate");
    btnAddSet:SetSize(130, 28);
    btnAddSet:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 8);
    btnAddSet:SetText(c:GetText("New set"));
    btnAddSet:SetScript("OnClick", function()
        c:ShowAddSetDialog();
    end);
    c:Skin("button", btnAddSet);

    btnSaveSet = CreateFrame("Button", "GqUiFrame_BtnSaveSet", setsPage, "SharedButtonSmallTemplate");
    btnSaveSet:SetSize(130, 28);
    btnSaveSet:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8);
    btnSaveSet:SetText(c:GetText("Save"));
    btnSaveSet:SetScript("OnClick", function()
        SaveWornGear(c:LoadCurrentSetName());
    end);
    -- hooked: the three-slice template draws its hover state in its own OnEnter / OnLeave
    btnSaveSet:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip_SetTitle(GameTooltip, c:GetText("Save"));
        GameTooltip_AddNormalLine(GameTooltip, c:GetText("Saves the worn gear into the current set."));
        GameTooltip:Show();
    end);
    btnSaveSet:HookScript("OnLeave", function()
        GameTooltip:Hide();
    end);
    c:Skin("button", btnSaveSet);
end

----- ui frame general stuff -----

local function BuildShell(f)
    f:SetTitle("GearQuipper");
    f.onCloseCallback = function()
        c:ToggleUI(false);
        return false;
    end;

    -- options: a small gear left of the close button (the icon sits on a child frame so skins keep it)
    local options = CreateFrame("Button", "GqUiFrame_BtnOptions", f);
    options:SetSize(18, 18);
    options:SetPoint("RIGHT", f.CloseButton, "LEFT", -2, 0);
    options:SetFrameLevel(f.CloseButton:GetFrameLevel());
    options.IconHolder = CreateFrame("Frame", nil, options);
    options.IconHolder:SetAllPoints();
    options.Icon = options.IconHolder:CreateTexture(nil, "ARTWORK");
    options.Icon:SetTexture("Interface\\WorldMap\\GEAR_64GREY");
    options.Icon:SetPoint("TOPLEFT", 1, -1);
    options.Icon:SetPoint("BOTTOMRIGHT", -1, 1);
    options.Icon:SetAlpha(0.6);
    options:SetScript("OnClick", function()
        c:OpenSettingsPanel();
    end);
    options:SetScript("OnEnter", function(self)
        self.Icon:SetAlpha(1);
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip_SetTitle(GameTooltip, c:GetText("Options"));
        GameTooltip_AddNormalLine(GameTooltip, "GearQuipper Forever v" .. c:GetVersion());
        GameTooltip:Show();
    end);
    options:SetScript("OnLeave", function(self)
        self.Icon:SetAlpha(0.6);
        GameTooltip:Hide();
    end);

    local tabs = {};
    for index, key in ipairs(TAB_KEYS) do
        local tab = CreateFrame("Button", "GqUiFrameTab" .. index, f, "PanelTopTabButtonTemplate");
        tab:SetID(index);
        tab:SetText(key == PANELTAB_SETS and c:GetText("Sets") or c:GetText("Events"));
        tab:SetScript("OnClick", function()
            SelectTab(key, true);
        end);
        PanelTemplates_TabResize(tab, 0);
        tabs[index] = tab;
    end
    tabs[1]:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -24);
    PanelTemplates_SetNumTabs(f, #tabs);

    local inset = CreateFrame("Frame", "GqUiFrameInset", f, "InsetFrameTemplate");
    inset:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -INSET_TOP);
    inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, INSET_BOTTOM);
    f.Inset = inset;

    -- after CloseButton and Inset exist: the frame kind covers both
    c:Skin("frame", f);
    c:Skin("inset", inset);
    c:Skin("font", f:GetTitleText());
    c:Skin("button", options);
    for _, tab in ipairs(tabs) do
        c:Skin("tab", tab);
    end
end

function c:InitUiFrame()
    -- default and migration: anything but a known tab opens the sets
    GQ_OPTIONS[c.OPT_PANELTAB] = GetSavedTab();

    if not built then
        built = true;
        local f = GqUiFrame;
        f:SetHeight(DEFAULT_PANEL_HEIGHT);
        BuildShell(f);
        BuildSetsPage(f);
        c:BuildEventsPage(f);
        SelectTab(GetSavedTab());
    end
end

function c:ToggleUI(value)
    if c.initFinished then
        c:HookBlizzardFrameScripts(); -- make sure hooks are working ...
        c:HookCharacterStatsFrameScripts();
        c:SetFramePositions(); -- ... and move frames if needed

        if value == nil then
            value = not GqUiFrame:IsVisible();
        end
        if value then
            GqUiFrame:Show();
            GqUiFrame.isOpen = true;
        else
            GqUiFrame:Hide();
            GqUiFrame.isOpen = false;
        end
        GQ_OPTIONS[c.OPT_MENUOPEN] = GqUiFrame.isOpen;
    end
end

function c:LockUI(setName)
    c:DebugPrint("UI lock");
    lockState.locked, lockState.setName = true, setName;
    c:CloseContextMenu("set");
    if c.paperDollFrame:IsVisible() then
        c:DisablePaperDollButton();
        c:HideSlotStateBoxes();
    end

    if GqUiFrame:IsVisible() and built then
        setList:ForEachFrame(ApplySetRowLock);
        btnSaveSet:SetEnabled(false);
        btnAddSet:SetEnabled(false);
        c:ToggleEvents(false);
    end
end

function c:UnlockUI()
    c:DebugPrint("UI unlock");
    lockState.locked, lockState.setName = false, nil;
    if c.paperDollFrame:IsVisible() then
        c:EnablePaperDollButton();
        c:ShowSlotStateBoxes();
    end

    if GqUiFrame:IsVisible() and built then
        setList:ForEachFrame(ApplySetRowLock);
        btnSaveSet:SetEnabled(c:LoadCurrentSetName() ~= nil);
        btnAddSet:SetEnabled(true);
        c:ToggleEvents(c:IsEventsEnabled());
    end
end

-- scrollIntoView: scroll the current set into view (only as far as needed); otherwise the list keeps its position
function c:RefreshSetList(scrollIntoView)
    if not built or not GqUiFrame:IsVisible() then
        -- refreshed when the panel opens
        return;
    end

    local currentSet = c:LoadCurrentSetName();
    local entries, currentEntry = {};
    for _, setName in ipairs(c:LoadSetNames()) do
        local entry = {
            setName = setName
        };
        table.insert(entries, entry);
        if setName == currentSet then
            currentEntry = entry;
        end
    end
    setList:SetDataProvider(CreateDataProvider(entries), ScrollBoxConstants.RetainScrollPosition);
    emptySetsText:SetShown(#entries == 0);

    if scrollIntoView and currentEntry then
        setList:ScrollToElementData(currentEntry, ScrollBoxConstants.AlignNearest, 0,
            ScrollBoxConstants.NoScrollInterpolation);
    end

    c:ShowSetInfo(currentSet);
end

-- a set colour changed: cheap enough for the picker's live preview (no list rebuild)
function c:RefreshSetColors()
    if built and GqUiFrame:IsVisible() then
        setList:ForEachFrame(function(row)
            local setName = GetRowSetName(row);
            if setName then
                SetNameColor(row, setName);
            end
        end);
        ShowCurrentSetStatus();
    end
    if c.paperDollFrame then
        c:SetPaperDollLabelText();
    end
    c:UpdateBroker();
end

-- footer state for the current set (Save needs one)
function c:ShowSetInfo(setName)
    if not built then
        return;
    end
    btnSaveSet:SetEnabled(setName ~= nil and not lockState.locked);
    ShowCurrentSetStatus();
end

----- ui frame interaction -----

-- Width of the character window's side tabs (Character / Reputation / Skills ...), which stick out of its right edge.
local function GetCharacterFrameTabsWidth()
    local characterFrame = _G["CharacterFrame"];
    local tabs = characterFrame and characterFrame.ModeTabs;
    if not (tabs and tabs:IsShown()) then
        return 0;
    end

    local frameRight = c:SafeCall(characterFrame.GetRight, characterFrame);
    local tabsRight;
    if frameRight then
        for _, tab in ipairs(tabs.Tabs or {}) do
            local right = tab:IsShown() and c:SafeCall(tab.GetRight, tab);
            if right then
                right = right * tab:GetEffectiveScale() / characterFrame:GetEffectiveScale();
                if not tabsRight or right > tabsRight then
                    tabsRight = right;
                end
            end
        end
    end
    if tabsRight and tabsRight > frameRight then
        return tabsRight - frameRight;
    end
    return tabs:GetWidth();
end

function c:SetGqUiFramePosition()
    -- beside the character window, right of its side tabs (the Forever window has no transparent art margin)
    local xOffset, yOffset = GetCharacterFrameTabsWidth() + 2, 0;

    local ecsFrame = _G[c:GetCharacterStatsFrameNames()[1]];
    if ecsFrame and ecsFrame:IsVisible() then
        xOffset = xOffset + ecsFrame:GetWidth();
    end

    GqUiFrame:ClearAllPoints();
    GqUiFrame:SetPoint("TOPLEFT", c.paperDollFrame, "TOPRIGHT", xOffset, yOffset);
end

function GqUiFrame_OnShow(gqFrame)
    c:SetGqUiFramePosition();
    SyncPanelHeight();
    c:HookBlizzardFrameScripts();
    c:HookCharacterStatsFrameScripts()
    c:SetFramePositions();

    if built then
        SelectTab(GetSavedTab());
        c:RefreshSetList(true);
        c:RefreshEventEntries();
    end

    if c:IsSwitching() or c:IsInCombat() or c:IsDead() then
        c:LockUI();
    else
        c:UnlockUI();
    end
end

function GqUiFrame_OnHide(self)
    c:HideSlotStateBoxes();
    c:SetFramePositions();
    if built then
        c:CloseBindingForm();
    end
end
