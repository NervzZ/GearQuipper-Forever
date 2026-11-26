-- scope stuff
gearquipper = gearquipper or {};
local c = gearquipper;

local defaultMargin = 10;
local defaultYOffset = 22;

local optionsPanel;

-- The modern Settings panel has no okay button, so every control writes its option on change. This is true while the
-- controls are built or synced from GQ_OPTIONS, when the slider's OnValueChanged must not write back.
local syncing = false;

local lblFeatures;
local lblSaveChanges, chSaveAlways, chSaveCharMenu, chSaveGqMenu, chSaveNever;
local saveChangesButtons = {};
local chIgnoreManuallySwitchedItems;
local chSetItemComparison, chSetItemComparison_ShowHint;

local lblVisualSettings;
local chHighlightChanges, chConfirmChangesInChat, chShowCurrentSetLabel, chShowItemTooltip, chShowSlotBackgroundColors,
    chShowBrokerTooltip;
local chNotifyQueues;

local lblSwitchDelay, sldSwitchDelay, lblSwitchDelayHint;

local btnReset;

-- options of GearQuipper v54 features that do not exist on Forever (action bars, spell upranking, user scripts) and
-- dead options
local OBSOLETE_OPTIONS = {"OPT_SAVECHANGES_ACTIONSLOTS", "OPT_AUTOUPRANKSPELLS", "OPT_AUTOUPRANKSPELLS_ALLRANKS",
                          "OPT_SCRIPTEDITORENABLED", "OPT_ACTIONBARS", "OPT_MOUNTING_CRUSADER_AURA", "OPT_SLOTSTATES",
                          "OPT_ACTIONBARS_SHOW_CONFIRMATION_ON_FIRST_TALENT_CHANGE"};

local function RefreshOptionsPanel()
    syncing = true;

    for _, button in ipairs(saveChangesButtons) do
        button:SetChecked(GQ_OPTIONS[c.OPT_SAVECHANGES] == button.optionValue);
    end

    chIgnoreManuallySwitchedItems:SetChecked(GQ_OPTIONS[c.OPT_IGNOREMANUALITEMS]);
    chSetItemComparison:SetChecked(GQ_OPTIONS[c.OPT_SET_ITEM_COMPARISON]);
    chSetItemComparison_ShowHint:SetChecked(GQ_OPTIONS[c.OPT_SET_ITEM_COMPARISON_SHOW_HINT]);
    c:SetCheckboxEnabled(chSetItemComparison_ShowHint, GQ_OPTIONS[c.OPT_SET_ITEM_COMPARISON] and true or false);

    lblSwitchDelay.fontString:SetText(c:GetText("Set switch delay: %sms", tostring(GQ_OPTIONS[c.OPT_SWITCHDELAY])));
    sldSwitchDelay:SetValue(GQ_OPTIONS[c.OPT_SWITCHDELAY]);

    chNotifyQueues:SetChecked(GQ_OPTIONS[c.OPT_NOTIFYQUEUES]);
    chHighlightChanges:SetChecked(GQ_OPTIONS[c.OPT_HIGHLIGHTCHANGES]);
    chConfirmChangesInChat:SetChecked(GQ_OPTIONS[c.OPT_NOTIFYCHANGES]);
    chShowCurrentSetLabel:SetChecked(GQ_OPTIONS[c.OPT_SHOWCURRENTSET]);
    chShowItemTooltip:SetChecked(GQ_OPTIONS[c.OPT_SHOWITEMTOOLTIP]);
    chShowSlotBackgroundColors:SetChecked(GQ_OPTIONS[c.OPT_SHOWSLOTBACKDROPS]);
    chShowBrokerTooltip:SetChecked(GQ_OPTIONS[c.OPT_SHOWBROKERTOOLTIP]);

    syncing = false;
end

-- checkbox that stores its checked state in GQ_OPTIONS[optionKey] when clicked
local function CreateOptionToggle(optionKey, text, xOffset, onChanged)
    local element = c:CreateOptionCheckButton(text, xOffset);
    element:SetScript("OnClick", function(self)
        GQ_OPTIONS[optionKey] = self:GetChecked();
        if onChanged then
            onChanged(self);
        end
    end);
    return element;
end

-- "Save gear when:" radio group made of checkboxes: clicking a checked box keeps it checked
local function CreateSaveChangesButton(text, optionValue)
    local element = c:CreateOptionCheckButton(text, optionsPanel.margin);
    element.optionValue = optionValue;
    element:SetScript("OnClick", function(self)
        if self:GetChecked() then
            for _, button in ipairs(saveChangesButtons) do
                if button ~= self then
                    button:SetChecked(false);
                end
            end
            GQ_OPTIONS[c.OPT_SAVECHANGES] = self.optionValue;
        else
            self:SetChecked(true);
        end
    end);
    table.insert(saveChangesButtons, element);
    return element;
end

local function BuildOptionsPanel()
    -- FEATURES

    lblFeatures = CreateFrame("Frame", "GqUiOptionElement_lblFeatures", optionsPanel);
    lblFeatures:SetPoint("TOPLEFT", optionsPanel.margin,
        -(optionsPanel.elementIndex - 1) * optionsPanel.checkboxYOffset - optionsPanel.margin);
    lblFeatures:SetWidth(550);
    lblFeatures:SetHeight(23);
    lblFeatures.fontString = lblFeatures:CreateFontString("GqUiOptionElement_lblFeatures_FontString", "ARTWORK",
        "GameFontNormalLarge");
    lblFeatures.fontString:SetPoint("CENTER");
    lblFeatures.fontString:SetText(c:GetText("Features"));
    optionsPanel.elementIndex = optionsPanel.elementIndex + 1;

    lblSaveChanges = CreateFrame("Frame", "GqUiOptionElement_lblSaveChanges", optionsPanel);
    lblSaveChanges:SetPoint("TOPLEFT", optionsPanel.margin,
        -(optionsPanel.elementIndex - 1) * optionsPanel.checkboxYOffset - optionsPanel.margin);
    lblSaveChanges:SetWidth(100);
    lblSaveChanges:SetHeight(23);
    lblSaveChanges.fontString = lblSaveChanges:CreateFontString("GqUiOptionElement_lblSaveChanges_FontString",
        "ARTWORK", "GameFontNormal");
    lblSaveChanges.fontString:SetPoint("LEFT", 3, 0);
    lblSaveChanges.fontString:SetText(c:GetText("Save gear when:"));
    optionsPanel.elementIndex = optionsPanel.elementIndex + 1; -- spacing

    chSaveAlways = CreateSaveChangesButton(ALWAYS or c:GetText("Always"), c.OPTVALUE_SAVECHANGES_ALWAYS);
    optionsPanel.elementIndex = optionsPanel.elementIndex + 1; -- spacing

    chSaveCharMenu = CreateSaveChangesButton(c:GetText("Character menu open"), c.OPTVALUE_SAVECHANGES_CHARMENU);
    optionsPanel.elementIndex = optionsPanel.elementIndex + 1; -- spacing

    chSaveGqMenu = CreateSaveChangesButton(c:GetText("GearQuipper menu open"), c.OPTVALUE_SAVECHANGES_GQMENU);
    optionsPanel.elementIndex = optionsPanel.elementIndex + 1; -- spacing

    chSaveNever = CreateSaveChangesButton(NEVER or c:GetText("Never"), c.OPTVALUE_SAVECHANGES_NEVER);
    optionsPanel.elementIndex = optionsPanel.elementIndex + 1; -- spacing
    optionsPanel.elementIndex = optionsPanel.elementIndex + 1; -- spacing

    chIgnoreManuallySwitchedItems = CreateOptionToggle(c.OPT_IGNOREMANUALITEMS,
        c:GetText("Ignore manually switched items for the next event triggered set switch"), nil, function(self)
            if not self:GetChecked() then
                c:ResetIgnoredSlots();
            end
        end);
    optionsPanel.elementIndex = optionsPanel.elementIndex + 1;

    chSetItemComparison = CreateOptionToggle(c.OPT_SET_ITEM_COMPARISON,
        c:GetText("Set item comparison tooltips (L-Alt)"), nil, function(self)
            c:SetCheckboxEnabled(chSetItemComparison_ShowHint, self:GetChecked(), true);
            if not self:GetChecked() then
                GQ_OPTIONS[c.OPT_SET_ITEM_COMPARISON_SHOW_HINT] = false;
            end
        end);
    optionsPanel.elementIndex = optionsPanel.elementIndex + 1;

    chSetItemComparison_ShowHint = CreateOptionToggle(c.OPT_SET_ITEM_COMPARISON_SHOW_HINT,
        c:GetText("Show hint on item tooltip (\"%s\")", c:GetText("Press L-Alt to cycle through sets.")),
        optionsPanel.margin);
    optionsPanel.elementIndex = optionsPanel.elementIndex + 1;

    lblSwitchDelay = CreateFrame("Frame", "GqUiOptionElement_lblSwitchDelay", optionsPanel);
    lblSwitchDelay:SetPoint("TOPLEFT", optionsPanel.margin, -(optionsPanel.elementIndex - 1) *
        optionsPanel.checkboxYOffset - optionsPanel.margin - 10);
    lblSwitchDelay:SetWidth(100);
    lblSwitchDelay:SetHeight(23);
    lblSwitchDelay.fontString = lblSwitchDelay:CreateFontString("GqUiOptionElement_lblSwitchDelay_FontString",
        "ARTWORK", "GameFontNormal");
    lblSwitchDelay.fontString:SetPoint("LEFT", 3, 0);

    sldSwitchDelay = c:CreateOptionsSlider(0, 1000, function(self, value)
        value = math.floor((value or self:GetValue()) + 0.5);
        lblSwitchDelay.fontString:SetText(c:GetText("Set switch delay: %sms", tostring(value)));
        if not syncing then
            GQ_OPTIONS[c.OPT_SWITCHDELAY] = value;
        end
    end, 205, 10, 150, 50, "0ms", "1000ms");

    lblSwitchDelayHint = CreateFrame("Frame", "GqUiOptionElement_lblSwitchDelayHint", optionsPanel);
    lblSwitchDelayHint:SetPoint("TOPLEFT", 375, -(optionsPanel.elementIndex - 1) * optionsPanel.checkboxYOffset -
        optionsPanel.margin - 10);
    lblSwitchDelayHint:SetWidth(100);
    lblSwitchDelayHint:SetHeight(23);
    lblSwitchDelayHint.fontString = lblSwitchDelayHint:CreateFontString(
        "GqUiOptionElement_lblSwitchDelayHint_FontString", "ARTWORK", "GameFontNormal");
    lblSwitchDelayHint.fontString:SetPoint("TOPLEFT", 3, 0);
    lblSwitchDelayHint.fontString:SetJustifyH("LEFT");
    lblSwitchDelayHint.fontString:SetText(c:GetText(
        "(Increase if you experience issues with\n automated event switches)"));

    optionsPanel.elementIndex = optionsPanel.elementIndex + 1; -- spacing
    optionsPanel.elementIndex = optionsPanel.elementIndex + 1; -- spacing

    -- VISUAL SETTINGS

    optionsPanel.elementIndex = optionsPanel.elementIndex + 1; -- spacing

    lblVisualSettings = CreateFrame("Frame", "GqUiOptionElement_lblVisualSettings", optionsPanel);
    lblVisualSettings:SetPoint("TOPLEFT", optionsPanel.margin, -(optionsPanel.elementIndex - 1) *
        optionsPanel.checkboxYOffset - optionsPanel.margin);
    lblVisualSettings:SetWidth(550);
    lblVisualSettings:SetHeight(23);
    lblVisualSettings.fontString = lblVisualSettings:CreateFontString("GqUiOptionElement_lblVisualSettings_FontString",
        "ARTWORK", "GameFontNormalLarge");
    lblVisualSettings.fontString:SetPoint("CENTER");
    lblVisualSettings.fontString:SetText(c:GetText("Visual Settings"));
    optionsPanel.elementIndex = optionsPanel.elementIndex + 1;

    chNotifyQueues = CreateOptionToggle(c.OPT_NOTIFYQUEUES, c:GetText("Queue/combat chat notifications"));
    optionsPanel.elementIndex = optionsPanel.elementIndex + 1;

    chHighlightChanges = CreateOptionToggle(c.OPT_HIGHLIGHTCHANGES, c:GetText("Highlight switched slots"));
    optionsPanel.elementIndex = optionsPanel.elementIndex + 1;

    chConfirmChangesInChat = CreateOptionToggle(c.OPT_NOTIFYCHANGES, c:GetText("Confirm changes in chat (gear)"));
    optionsPanel.elementIndex = optionsPanel.elementIndex + 1;

    chShowCurrentSetLabel = CreateOptionToggle(c.OPT_SHOWCURRENTSET, c:GetText("Show \"current set\" label"));
    optionsPanel.elementIndex = optionsPanel.elementIndex + 1;

    chShowItemTooltip = CreateOptionToggle(c.OPT_SHOWITEMTOOLTIP, c:GetText("Show item tooltips"));
    optionsPanel.elementIndex = optionsPanel.elementIndex + 1;

    chShowSlotBackgroundColors = CreateOptionToggle(c.OPT_SHOWSLOTBACKDROPS, c:GetText("Show slot background colors"));
    optionsPanel.elementIndex = optionsPanel.elementIndex + 1;

    chShowBrokerTooltip = CreateOptionToggle(c.OPT_SHOWBROKERTOOLTIP, c:GetText("Show data broker tooltip"));

    -- RESET BUTTON

    btnReset = CreateFrame("Button", "GqResetButton", optionsPanel, "UIPanelButtonTemplate");
    btnReset:SetSize(180, 24);
    btnReset:SetPoint("TOPRIGHT", -10, -optionsPanel.elementIndex * optionsPanel.checkboxYOffset - optionsPanel.margin);
    btnReset:SetText(c:GetText("Reset GearQuipper"));
    btnReset:SetScript("OnClick", function()
        c:ShowResetDialog();
    end);
end

function c:InitOptions()
    c.OPT_VERSION = "OPT_VERSION";

    c.OPT_IGNOREMANUALITEMS = "OPT_IGNOREMANUALITEMS";
    c.OPT_SET_ITEM_COMPARISON = "OPT_SET_ITEM_COMPARISON";
    c.OPT_SET_ITEM_COMPARISON_SHOW_HINT = "OPT_SET_ITEM_COMPARISON_SHOW_HINT";

    c.OPT_SWITCHDELAY = "OPT_SWITCHDELAY";

    c.OPT_NOTIFYCHANGES = "OPT_NOTIFYCHANGES";
    c.OPT_NOTIFYQUEUES = "OPT_NOTIFYQUEUES";
    c.OPT_HIGHLIGHTCHANGES = "OPT_HIGHLIGHTCHANGES";
    c.OPT_SAVECHANGES = "OPT_SAVECHANGES";
    c.OPT_SHOWCURRENTSET = "OPT_SHOWCURRENTSET";
    c.OPT_SHOWITEMTOOLTIP = "OPT_SHOWITEMTOOLTIP";
    c.OPT_SHOWSLOTBACKDROPS = "OPT_SHOWSLOTBACKDROPS";

    c.OPT_SHOWBROKERTOOLTIP = "OPT_SHOWBROKERTOOLTIP";

    c.OPT_MENUOPEN = "OPT_MENUOPEN";
    c.OPT_SHOW_WATERMARK = "OPT_SHOW_WATERMARK";

    c.OPTVALUE_SAVECHANGES_ALWAYS = "OPTVALUE_SAVECHANGES_ALWAYS";
    c.OPTVALUE_SAVECHANGES_CHARMENU = "OPTVALUE_SAVECHANGES_CHARMENU";
    c.OPTVALUE_SAVECHANGES_GQMENU = "OPTVALUE_SAVECHANGES_GQMENU";
    c.OPTVALUE_SAVECHANGES_NEVER = "OPTVALUE_SAVECHANGES_NEVER";

    for _, optionKey in ipairs(OBSOLETE_OPTIONS) do
        GQ_OPTIONS[optionKey] = nil;
    end
    GQ_OPTIONS[true] = nil; -- v54 stored its talent-change confirmation flag under the key true

    if GQ_OPTIONS[c.OPT_NOTIFYCHANGES] == nil then
        GQ_OPTIONS[c.OPT_NOTIFYCHANGES] = true;
    end

    if GQ_OPTIONS[c.OPT_NOTIFYQUEUES] == nil then
        GQ_OPTIONS[c.OPT_NOTIFYQUEUES] = true;
    end

    if GQ_OPTIONS[c.OPT_HIGHLIGHTCHANGES] == nil then
        GQ_OPTIONS[c.OPT_HIGHLIGHTCHANGES] = true;
    end

    if GQ_OPTIONS[c.OPT_SHOWCURRENTSET] == nil then
        GQ_OPTIONS[c.OPT_SHOWCURRENTSET] = true;
    end

    if GQ_OPTIONS[c.OPT_SHOWITEMTOOLTIP] == nil then
        GQ_OPTIONS[c.OPT_SHOWITEMTOOLTIP] = true;
    end

    if GQ_OPTIONS[c.OPT_SHOWSLOTBACKDROPS] == nil then
        GQ_OPTIONS[c.OPT_SHOWSLOTBACKDROPS] = true;
    end

    if GQ_OPTIONS[c.OPT_SHOWBROKERTOOLTIP] == nil then
        GQ_OPTIONS[c.OPT_SHOWBROKERTOOLTIP] = true;
    end

    if GQ_OPTIONS[c.OPT_IGNOREMANUALITEMS] == nil then
        GQ_OPTIONS[c.OPT_IGNOREMANUALITEMS] = false;
    end

    if GQ_OPTIONS[c.OPT_SET_ITEM_COMPARISON] == nil then
        GQ_OPTIONS[c.OPT_SET_ITEM_COMPARISON] = true;
    end

    if GQ_OPTIONS[c.OPT_SET_ITEM_COMPARISON_SHOW_HINT] == nil then
        GQ_OPTIONS[c.OPT_SET_ITEM_COMPARISON_SHOW_HINT] = true;
    end

    GQ_OPTIONS[c.OPT_SAVECHANGES] = GQ_OPTIONS[c.OPT_SAVECHANGES] or c.OPTVALUE_SAVECHANGES_GQMENU;
    GQ_OPTIONS[c.OPT_SWITCHDELAY] = GQ_OPTIONS[c.OPT_SWITCHDELAY] or 600;

    -- main panel: built and registered only once (c:Init() runs again after a reset)
    if not optionsPanel then
        optionsPanel = CreateFrame("Frame", "GearQuipper_Options_Main");
        optionsPanel.name = "GearQuipper";
        optionsPanel.margin = defaultMargin;
        optionsPanel.elementIndex = 1;
        optionsPanel.checkboxYOffset = defaultYOffset;
        optionsPanel:Hide(); -- the Settings panel shows it, which fires OnShow
        syncing = true;
        BuildOptionsPanel();
        syncing = false;
        optionsPanel:SetScript("OnShow", RefreshOptionsPanel);
        c:RegisterSettingsPanel(optionsPanel, optionsPanel.name);
    end
    RefreshOptionsPanel();
end

function c:SetCheckboxEnabled(frame, value, uncheckIfDisabled)
    if frame and frame.fontString then
        if uncheckIfDisabled and not value then
            frame:SetChecked(false);
        end
        frame:SetEnabled(value);

        if not frame.fontString.defaultColor then
            frame.fontString.defaultColor = {frame.fontString:GetTextColor()};
        end

        if value then
            frame.fontString:SetTextColor(unpack(frame.fontString.defaultColor));
        else
            frame.fontString:SetTextColor(0.7, 0.7, 0.7);
        end
    end
end

function c:CreateOptionCheckButton(text, xOffset)
    xOffset = xOffset or 0;

    local element = CreateFrame("CheckButton", "GqUiOptionElement_" .. optionsPanel.elementIndex, optionsPanel,
        "UICheckButtonTemplate");
    -- size and clickable label area of GQ's original ChatConfigCheckButtonTemplate
    element:SetSize(24, 24);
    element:SetHitRectInsets(0, -145, 0, 0);
    element:SetPoint("TOPLEFT", 10 + xOffset,
        -(optionsPanel.elementIndex - 1) * optionsPanel.checkboxYOffset - optionsPanel.margin);
    element.fontString = element:CreateFontString("GqUiOptionElement_" .. optionsPanel.elementIndex .. "_FontString",
        "ARTWORK", "GameFontNormal");
    element.fontString:SetPoint("LEFT", 30, 0);
    element.fontString:SetText(text);

    return element;
end

function c:CreateOptionsSlider(min, max, func, xOffset, yOffset, width, valueStep, minText, maxText)
    xOffset = xOffset or 0;
    yOffset = yOffset or 0;
    min = min or 0;
    max = max or 100;
    valueStep = valueStep or 1;
    minText = minText or min;
    maxText = maxText or max;
    width = width or 160;

    local element = CreateFrame("Slider", "GqUiOptionElement_" .. optionsPanel.elementIndex, optionsPanel,
        "UISliderTemplateWithLabels");
    element.frameType = "Slider";
    element:SetPoint("TOPLEFT", 10 + xOffset,
        -(optionsPanel.elementIndex - 1) * optionsPanel.checkboxYOffset - optionsPanel.margin - yOffset);
    element:SetOrientation("HORIZONTAL");
    element:SetWidth(width);
    element:SetHeight(23);
    element:SetScript("OnValueChanged", func);
    element:SetMinMaxValues(min, max);
    element:SetValueStep(valueStep);
    element:SetObeyStepOnDrag(true);

    -- min text
    element.minText = element.Low or _G[element:GetName() .. "Low"];
    element.SetMinText = function(self, text)
        self.minText:SetText(text);
    end
    element:SetMinText(minText);

    -- max text
    element.maxText = element.High or _G[element:GetName() .. "High"];
    element.SetMaxText = function(self, text)
        self.maxText:SetText(text);
    end
    element:SetMaxText(maxText);

    return element;
end
