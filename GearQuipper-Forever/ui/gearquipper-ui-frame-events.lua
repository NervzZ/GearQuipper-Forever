-- The panel's Events tab: the list of event bindings and the inline form that adds one.
gearquipper = gearquipper or {};
local c = gearquipper;

local BINDING_ROW_HEIGHT, BINDING_ROW_SPACING = 52, 2;
local FORM_LABEL_X, FORM_PICKER_X, FORM_ROW_STEP = 12, 96, 32;

local eventsPage, listPage, bindingList, emptyBindingsText, cbEnableEvents, btnAddBinding;
local form, formValues;
local controlsEnabled = false; -- last c:ToggleEvents value

local function HasEventSubType(value)
    return value == c.EVENT_ZONE_ENTER or value == c.EVENT_ZONE_LEAVE or value == c.EVENT_SHAPESHIFT_IN or value ==
               c.EVENT_SHAPESHIFT_OUT or value == c.EVENT_AURA_CHANGED or value == c.EVENT_STANCE_CHANGED or value ==
               c.EVENT_TALENTS_CHANGED
end

local function IsZoneEvent(value)
    return value == c.EVENT_ZONE_ENTER or value == c.EVENT_ZONE_LEAVE;
end

local function GetSetDisplayName(setName)
    if setName == c.KEYWORD_PREVIOUS then
        return c:GetText("[Previous set]");
    elseif setName == c.KEYWORD_PREVIOUSEQUIPMENT then
        return c:GetText("[Previous equipment]");
    end
    return setName;
end

-- event names are lower case ("on mount") because the old dialog read them as a sentence
local function Capitalize(text)
    return (tostring(text):gsub("^%l", string.upper));
end

-- radio entries for every set a binding can switch to
local function AddSetRadios(root, isSelected, setSelected)
    root:CreateRadio(c:GetText("[Previous set]"), isSelected, setSelected, c.KEYWORD_PREVIOUS);
    root:CreateRadio(c:GetText("[Previous equipment]"), isSelected, setSelected, c.KEYWORD_PREVIOUSEQUIPMENT);
    for _, setName in ipairs(c:LoadSetNames()) do
        root:CreateRadio(setName, isSelected, setSelected, setName);
    end
end

function c:BindEvent(bindingValues)
    if bindingValues[c.FIELD_TYPE] and bindingValues[c.FIELD_NAME] then
        if not HasEventSubType(bindingValues[c.FIELD_TYPE]) or bindingValues[c.FIELD_SUBTYPE] then
            if not c:BindingExists(bindingValues) then
                c:SaveEventBinding(bindingValues);
                return true;
            end
        end
    end
end

----- binding list -----

local function ApplyBindingRowState(row)
    row.SetPicker:SetEnabled(controlsEnabled);
    row.Delete:SetEnabled(controlsEnabled);
end

local function BuildBindingRow(row)
    -- stock look: a separator line (on a child frame: EllesmereUI fades the own textures of the skinned row)
    row.Art = CreateFrame("Frame", nil, row);
    row.Art:SetAllPoints();
    row.Separator = row.Art:CreateTexture(nil, "BACKGROUND");
    row.Separator:SetAtlas("UI-Character-Info-ScrollLine");
    row.Separator:SetPoint("BOTTOMLEFT", 4, -1);
    row.Separator:SetPoint("BOTTOMRIGHT", -4, -1);
    row.Separator:SetHeight(2);

    row.Delete = CreateFrame("Button", nil, row, "UIPanelCloseButtonNoScripts");
    row.Delete:SetSize(20, 20);
    row.Delete:SetPoint("TOPRIGHT", -4, -4);
    -- the template sits at frame level 510 (title bar close buttons); inside a list it belongs to its row
    row.Delete:SetFrameLevel(row:GetFrameLevel() + 2);
    row.Delete:SetScript("OnClick", function()
        local data = row:GetElementData();
        if data then
            c:DeleteEventBinding(data.index);
            c:RefreshEventEntries();
            c:RefreshSetList();
        end
    end);
    row.Delete:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip_SetTitle(GameTooltip, c:GetText("Delete binding"));
        GameTooltip:Show();
    end);
    row.Delete:SetScript("OnLeave", function()
        GameTooltip:Hide();
    end);

    -- line 1: the event across the row; line 2: PvE / PvP and the set picker
    row.Event = row:CreateFontString(nil, "ARTWORK", "GameFontNormalLeft");
    row.Event:SetPoint("TOPLEFT", 8, -7);
    row.Event:SetPoint("RIGHT", row.Delete, "LEFT", -4, 0);
    row.Event:SetWordWrap(false);

    row.SetPicker = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate");
    row.SetPicker:SetWidth(140);
    row.SetPicker:SetPoint("BOTTOMRIGHT", -8, 4);

    row.Info = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmallLeft");
    row.Info:SetPoint("BOTTOMLEFT", 8, 11);
    row.Info:SetPoint("BOTTOMRIGHT", row.SetPicker, "BOTTOMLEFT", -6, 7);
    row.Info:SetWordWrap(false);
end

local function InitBindingRow(row, data)
    if not row.SetPicker then
        BuildBindingRow(row);
    end
    c:Skin("panel", row);
    c:Skin("font", row.Event);
    c:Skin("font", row.Info);
    c:Skin("dropdown", row.SetPicker);
    c:Skin("close", row.Delete);
    row.Separator:SetShown(c:GetSkinBackend() == nil);

    local binding, index = data.binding, data.index;
    local eventName = c:GetEvents()[binding[c.FIELD_TYPE]];
    if eventName then
        local text = Capitalize(eventName);
        local subType = binding[c.FIELD_SUBTYPE];
        if type(subType) == "table" and subType["name"] then
            -- zone, form, aura, stance, talent specialization
            text = text .. ": " .. subType["name"];
        end
        row.Event:SetText(text);

        local infos = {};
        if binding[c.FIELD_PVE] then
            table.insert(infos, c:GetText("PvE"));
        end
        if binding[c.FIELD_PVP] then
            table.insert(infos, c:GetText("PvP"));
        end
        row.Info:SetText(table.concat(infos, " + "));

        row.SetPicker:Show();
        row.SetPicker:SetDefaultText(GetSetDisplayName(binding[c.FIELD_NAME]));
        row.SetPicker:SetupMenu(function(dropdown, root)
            AddSetRadios(root, function(value)
                return binding[c.FIELD_NAME] == value;
            end, function(value)
                binding[c.FIELD_NAME] = value;
                c:SaveEventBinding(binding, index);
                c:RefreshSetList();
            end);
        end);
        row.SetPicker:GenerateMenu();
    else
        row.Event:SetText(c:GetText("Deprecated event"));
        row.Info:SetText(tostring(binding[c.FIELD_NAME] or "") .. " - " .. c:GetText("Replace me!"));
        row.SetPicker:Hide();
    end

    ApplyBindingRowState(row);
end

----- new binding form -----

local function SetErrorMessage(text)
    form.Error:SetText(text);
end

local function CheckValues()
    SetErrorMessage();
    if formValues then
        if c:BindingExists(formValues) then
            SetErrorMessage(c:FormatTextWithColor(c:GetText("This event already exists."), "ff0000"));
            return false;
        elseif formValues[c.FIELD_TYPE] == c.EVENT_COMBAT_ENTER and not c:IsWeaponsOnlySet(formValues[c.FIELD_NAME]) then
            SetErrorMessage(c:FormatTextWithColor(c:GetText("Set does not match conditions."), "ff0000"));
            return false;
        end

        if (formValues[c.FIELD_PVE] or formValues[c.FIELD_PVP]) and formValues[c.FIELD_NAME] and
            formValues[c.FIELD_TYPE] and (not HasEventSubType(formValues[c.FIELD_TYPE]) or formValues[c.FIELD_SUBTYPE]) then
            return true;
        end
    end
    return false;
end

local function UpdateAddButton()
    form.BtnAdd:SetEnabled(controlsEnabled and CheckValues());
end

-- stacks the shown picker rows, then the checkboxes and the messages under them
local function LayoutForm()
    local y = -40;
    for _, pickerRow in ipairs(form.pickerRows) do
        if pickerRow.picker:IsShown() then
            pickerRow.label:SetPoint("TOPLEFT", form, "TOPLEFT", FORM_LABEL_X, y - 6);
            pickerRow.picker:SetPoint("TOPLEFT", form, "TOPLEFT", FORM_PICKER_X, y);
            y = y - FORM_ROW_STEP;
        end
    end
    form.CbPvE:SetPoint("TOPLEFT", form, "TOPLEFT", FORM_PICKER_X - 6, y);
    form.CbPvP:SetPoint("TOPLEFT", form.CbPvE, "BOTTOMLEFT", 0, 2);
    form.Warning:SetPoint("TOPLEFT", form.CbPvP, "BOTTOMLEFT", FORM_LABEL_X - FORM_PICKER_X + 6, -10);
end

local function SetPickerRowShown(pickerRow, shown)
    pickerRow.picker:SetShown(shown);
    pickerRow.label:SetShown(shown);
end

local function DetailPromptFor(eventType)
    if eventType == c.EVENT_AURA_CHANGED then
        return c:GetText("< choose aura >");
    elseif eventType == c.EVENT_STANCE_CHANGED then
        return c:GetText("< choose stance >");
    elseif eventType == c.EVENT_SHAPESHIFT_IN or eventType == c.EVENT_SHAPESHIFT_OUT then
        return c:GetText("< choose form >");
    elseif eventType == c.EVENT_TALENTS_CHANGED then
        return c:GetText("< choose talents >");
    end
    return c:GetText("< choose zone >");
end

-- {name, spellId} entries sorted by display name (auras, stances, forms, spec groups)
local function AddSpellRadios(root, sortedNames, byId, isSelected, setSelected)
    for _, displayName in ipairs(sortedNames) do
        for spellId, name in pairs(byId) do
            if name == displayName then
                root:CreateRadio(displayName, isSelected, setSelected, {
                    name = displayName,
                    spellId = spellId
                });
                break
            end
        end
    end
end

local function AddZoneRadios(root, parentMapId, isSelected, setSelected)
    for _, zoneValues in ipairs(c:GetZoneChildrenSorted(parentMapId)) do
        root:CreateRadio(zoneValues["name"], isSelected, setSelected, c:Deepcopy(zoneValues));
    end
end

local function OnDetail2Selected(value)
    formValues[c.FIELD_SUBSUBTYPE] = value;
    UpdateAddButton();
end

local function ShowDetail2()
    SetPickerRowShown(form.detail2Row, true);
    form.Detail2Picker:GenerateMenu();
end

local function OnDetailSelected(value)
    formValues[c.FIELD_SUBTYPE] = value;
    formValues[c.FIELD_SUBSUBTYPE] = nil;
    if IsZoneEvent(formValues[c.FIELD_TYPE]) and #c:GetZoneChildrenSorted(value["mapID"]) > 0 then
        ShowDetail2();
    else
        SetPickerRowShown(form.detail2Row, false);
    end
    LayoutForm();
    UpdateAddButton();
end

local function OnEventSelected(value)
    formValues[c.FIELD_TYPE] = value;
    formValues[c.FIELD_SUBTYPE] = nil;
    formValues[c.FIELD_SUBSUBTYPE] = nil;
    form.Warning:SetText();
    SetPickerRowShown(form.detailRow, false);
    SetPickerRowShown(form.detail2Row, false);

    if HasEventSubType(value) then
        SetPickerRowShown(form.detailRow, true);
        form.DetailPicker:SetDefaultText(DetailPromptFor(value));
        form.DetailPicker:GenerateMenu();
    elseif value == c.EVENT_COMBAT_ENTER then
        form.Warning:SetText(c:GetText(
            "WARNING! Switching will fail if target set does not match the following conditions:\n- is partial with only weapon slots enabled"));
    end
    LayoutForm();
    UpdateAddButton();
end

local function CreatePickerRow(name, labelText)
    local label = form:CreateFontString(nil, "ARTWORK", "GameFontNormalSmallLeft");
    label:SetText(labelText);
    c:Skin("font", label);
    local picker = CreateFrame("DropdownButton", name, form, "WowStyle1DropdownTemplate");
    picker:SetWidth(190);
    c:Skin("dropdown", picker);
    local pickerRow = {
        label = label,
        picker = picker
    };
    table.insert(form.pickerRows, pickerRow);
    return picker, pickerRow;
end

local function CreateFormCheckbox(name, text, field)
    local checkbox = CreateFrame("CheckButton", name, form, "UICheckButtonTemplate");
    checkbox:SetSize(26, 26);
    checkbox.Text:SetText(text);
    checkbox:SetHitRectInsets(0, -150, 0, 0);
    checkbox:SetScript("OnClick", function(self)
        formValues[field] = self:GetChecked();
        UpdateAddButton();
    end);
    c:Skin("checkbox", checkbox);
    c:Skin("font", checkbox.Text);
    return checkbox;
end

local function BuildForm(f)
    form = CreateFrame("Frame", "GqUiFrameBindingForm", eventsPage);
    form:SetPoint("TOPLEFT", f.Inset, "TOPLEFT");
    form:SetPoint("BOTTOMRIGHT", f.Inset, "BOTTOMRIGHT");
    form:Hide();
    form.pickerRows = {};

    form.Title = form:CreateFontString(nil, "ARTWORK", "GameFontNormal");
    form.Title:SetPoint("TOP", 0, -12);
    form.Title:SetText(c:GetText("New event binding"));
    c:Skin("font", form.Title);

    form.EventPicker = CreatePickerRow("GqUiFrameBindingForm_EventPicker", c:GetText("Event"));
    form.EventPicker:SetDefaultText(c:GetText("on < choose event >"));
    form.EventPicker:SetupMenu(function(dropdown, root)
        local function isSelected(value)
            return formValues and formValues[c.FIELD_TYPE] == value;
        end
        for _, eventName in ipairs(c:GetEventNamesSorted()) do
            root:CreateRadio(c:GetEvents()[eventName], isSelected, OnEventSelected, eventName);
        end
    end);

    form.DetailPicker, form.detailRow = CreatePickerRow("GqUiFrameBindingForm_DetailPicker", c:GetText("Detail"));
    form.DetailPicker:SetupMenu(function(dropdown, root)
        local eventType = formValues and formValues[c.FIELD_TYPE];
        local function isSelected(value)
            return formValues and c:Equals(formValues[c.FIELD_SUBTYPE], value);
        end
        if eventType == c.EVENT_AURA_CHANGED then
            -- paladin aura
            AddSpellRadios(root, c:GetPaladinAurasSorted(), c:GetPaladinAuras(), isSelected, OnDetailSelected);
        elseif eventType == c.EVENT_STANCE_CHANGED then
            -- warrior stance
            AddSpellRadios(root, c:GetWarriorStancesSorted(), c:GetWarriorStances(), isSelected, OnDetailSelected);
        elseif eventType == c.EVENT_TALENTS_CHANGED then
            -- talents (spec group 1 / 2)
            AddSpellRadios(root, c:GetTalentSpecializationsSorted(), c:GetTalentSpecializations(), isSelected,
                OnDetailSelected);
        elseif eventType == c.EVENT_SHAPESHIFT_IN or eventType == c.EVENT_SHAPESHIFT_OUT then
            -- druid shapeshift
            AddSpellRadios(root, c:GetDruidFormsSorted(), c:GetDruidForms(), isSelected, OnDetailSelected);
        elseif IsZoneEvent(eventType) then
            AddZoneRadios(root, 947, isSelected, OnDetailSelected);
        end
    end);

    form.Detail2Picker, form.detail2Row = CreatePickerRow("GqUiFrameBindingForm_Detail2Picker", c:GetText("Detail 2"));
    form.Detail2Picker:SetDefaultText(c:GetText("< subzone (optional) >"));
    form.Detail2Picker:SetupMenu(function(dropdown, root)
        local subType = formValues and formValues[c.FIELD_SUBTYPE];
        if subType and IsZoneEvent(formValues[c.FIELD_TYPE]) then
            AddZoneRadios(root, subType["mapID"], function(value)
                return c:Equals(formValues[c.FIELD_SUBSUBTYPE], value);
            end, OnDetail2Selected);
        end
    end);

    form.SetPicker = CreatePickerRow("GqUiFrameBindingForm_SetPicker", c:GetText("Set"));
    form.SetPicker:SetDefaultText(c:GetText("< choose set >"));
    form.SetPicker:SetupMenu(function(dropdown, root)
        AddSetRadios(root, function(value)
            return formValues and formValues[c.FIELD_NAME] == value;
        end, function(value)
            formValues[c.FIELD_NAME] = value;
            UpdateAddButton();
        end);
    end);

    form.CbPvE = CreateFormCheckbox("GqUiFrameBindingForm_CbPVE", c:GetText("in PvE situations"), c.FIELD_PVE);
    form.CbPvP = CreateFormCheckbox("GqUiFrameBindingForm_CbPVP", c:GetText("in PvP situations"), c.FIELD_PVP);

    form.Warning = form:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
    form.Warning:SetWidth(270);
    form.Warning:SetJustifyH("LEFT");
    c:Skin("font", form.Warning);
    form.Error = form:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
    form.Error:SetPoint("TOPLEFT", form.Warning, "BOTTOMLEFT", 0, -8);
    form.Error:SetJustifyH("LEFT");
    c:Skin("font", form.Error);

    form.BtnAdd = CreateFrame("Button", "GqUiFrameBindingForm_BtnAdd", form, "SharedButtonSmallTemplate");
    form.BtnAdd:SetSize(130, 28);
    form.BtnAdd:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 8);
    form.BtnAdd:SetText(c:GetText("Add"));
    form.BtnAdd:SetScript("OnClick", function()
        if c:BindEvent(formValues) then
            c:CloseBindingForm();
            c:RefreshEventEntries();
            c:RefreshSetList();
        end
    end);
    c:Skin("button", form.BtnAdd);

    form.BtnCancel = CreateFrame("Button", "GqUiFrameBindingForm_BtnCancel", form, "SharedButtonSmallTemplate");
    form.BtnCancel:SetSize(130, 28);
    form.BtnCancel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8);
    form.BtnCancel:SetText(CANCEL);
    form.BtnCancel:SetScript("OnClick", function()
        c:CloseBindingForm();
    end);
    c:Skin("button", form.BtnCancel);
end

local function ApplyFormState()
    for _, pickerRow in ipairs(form.pickerRows) do
        pickerRow.picker:SetEnabled(controlsEnabled);
    end
    form.CbPvE:SetEnabled(controlsEnabled);
    form.CbPvP:SetEnabled(controlsEnabled);
    UpdateAddButton();
end

local function OpenBindingForm()
    formValues = {
        [c.FIELD_PVE] = true,
        [c.FIELD_PVP] = true
    };
    form.CbPvE:SetChecked(true);
    form.CbPvP:SetChecked(true);
    form.Warning:SetText();
    SetErrorMessage();
    SetPickerRowShown(form.detailRow, false);
    SetPickerRowShown(form.detail2Row, false);
    listPage:Hide();
    form:Show();
    -- regenerated after the values reset: no selection shows the prompts
    form.EventPicker:GenerateMenu();
    form.SetPicker:GenerateMenu();
    LayoutForm();
    ApplyFormState();
end

function c:CloseBindingForm()
    if form and form:IsShown() then
        form:Hide();
        listPage:Show();
    end
end

----- page -----

function c:BuildEventsPage(f)
    eventsPage = CreateFrame("Frame", "GqUiFrameEventsPage", f);
    eventsPage:SetAllPoints();
    eventsPage:SetFrameLevel(f.Inset:GetFrameLevel() + 2);
    eventsPage:Hide();

    listPage = CreateFrame("Frame", nil, eventsPage);
    listPage:SetAllPoints();

    bindingList = c:CreatePanelList(listPage, "GqUiFrameBindingList", BINDING_ROW_HEIGHT, BINDING_ROW_SPACING,
        InitBindingRow);
    emptyBindingsText = c:CreatePanelEmptyText(listPage, c:GetText("No event bindings yet."));

    -- checked = event bindings on (the same option the old "Disable events" box showed inverted)
    cbEnableEvents = CreateFrame("CheckButton", "GqUiFrame_CbEnableEvents", listPage, "UICheckButtonTemplate");
    cbEnableEvents:SetSize(26, 26);
    cbEnableEvents:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 9);
    cbEnableEvents.Text:SetText(c:GetText("Enable event bindings"));
    cbEnableEvents:SetHitRectInsets(0, -140, 0, 0);
    cbEnableEvents:SetChecked(c:IsEventsEnabled() == true);
    cbEnableEvents:SetScript("OnClick", function(self)
        c:SetEventsEnabled(self:GetChecked() and true or false);
        c:ToggleEvents(c:IsEventsEnabled() and not c:IsUiLocked());
    end);
    c:Skin("checkbox", cbEnableEvents);
    c:Skin("font", cbEnableEvents.Text);

    btnAddBinding = CreateFrame("Button", "GqAddEventBinding", listPage, "SharedButtonSmallTemplate");
    btnAddBinding:SetSize(130, 28);
    btnAddBinding:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8);
    btnAddBinding:SetText(c:GetText("Add binding"));
    btnAddBinding:SetScript("OnClick", OpenBindingForm);
    c:Skin("button", btnAddBinding);

    BuildForm(f);
end

function c:ShowEventsPage(shown)
    if eventsPage then
        eventsPage:SetShown(shown);
    end
end

function c:RefreshEventEntries()
    if not bindingList or not GqUiFrame:IsVisible() then
        -- refreshed when the panel opens
        return;
    end

    local entries = {};
    for index, binding in ipairs(c:LoadEventBindings() or {}) do
        table.insert(entries, {
            index = index,
            binding = binding
        });
    end
    bindingList:SetDataProvider(CreateDataProvider(entries), ScrollBoxConstants.RetainScrollPosition);
    emptyBindingsText:SetShown(#entries == 0);
    cbEnableEvents:SetChecked(c:IsEventsEnabled() == true);
end

-- value: whether the binding controls are usable (events on, panel not locked)
function c:ToggleEvents(value)
    controlsEnabled = value and true or false;
    if not bindingList then
        return;
    end
    btnAddBinding:SetEnabled(controlsEnabled and not c:IsInCombat() and not c:IsDead());
    bindingList:ForEachFrame(ApplyBindingRowState);
    ApplyFormState();
    -- the box shows the option itself, also while a lock disables the controls
    cbEnableEvents:SetChecked(c:IsEventsEnabled() == true);
end
