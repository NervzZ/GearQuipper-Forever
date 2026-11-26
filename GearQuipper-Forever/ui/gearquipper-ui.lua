-- scope stuff
gearquipper = gearquipper or {};
local c = gearquipper;

local gqTooltips = {};
local slotStateBoxes;
local dimmedBagFrames = {};

-- frames that open beside the character window and are moved to the right of the GQ panel
local blizzardFrameNames = {"BankFrame"};

local ECS_FrameName = "ECS_StatsFrame";
local csFrameNames = {ECS_FrameName};

local MAX_ITEMS_PER_CONTAINER = MAX_CONTAINER_ITEMS or 36;
local FRAME_SPACING = 10;

-- The Forever character window has a left pane (paper doll) and an optional right pane (stats / equipment
-- manager). GQ's widgets belong to the paper doll part, so they anchor to the left pane when it exists.
local function GetPaperDollAnchor()
    local characterFrame = _G["CharacterFrame"];
    return (characterFrame and characterFrame.LeftPaneHost) or c.paperDollFrame;
end

-- Edge of a frame, converted to the units of targetFrame; nil if unknown (not laid out yet or secret).
local function GetFrameEdge(frame, edge, targetFrame)
    local value = c:SafeCall(frame[edge], frame);
    if not value then
        return nil;
    end
    if targetFrame then
        value = value * frame:GetEffectiveScale() / targetFrame:GetEffectiveScale();
    end
    return value;
end

----- general ui stuff -----

function c:InitUI(paperDollFrame)
    if paperDollFrame then
        c.paperDollFrame = paperDollFrame;
        c.paperDollFrame.paperDollButton = c.paperDollFrame.paperDollButton or c:CreatePaperDollButton();
        c.paperDollFrame.paperDollLabel = c.paperDollFrame.paperDollLabel or c:CreatePaperDollLabel();

        -- InitUI runs again after "/gq reset": every hook is added only once
        if not c.paperDollFrame.gqHooked then
            c.paperDollFrame.gqHooked = true;
            c.paperDollFrame:HookScript("OnShow", function()
                if GQ_OPTIONS[c.OPT_MENUOPEN] then
                    c:ToggleUI(true);
                end
                c:SetSlotInfo();
                c:SetPaperDollLabelText();
                c:SetGqUiFramePosition();

                if c:IsSwitching() or c:IsInCombat() or c:IsDead() then
                    c:LockUI();
                else
                    c:UnlockUI();
                end
            end);
            c.paperDollFrame:HookScript("OnHide", function()
                GQ_OPTIONS[c.OPT_MENUOPEN] = GqUiFrame.isOpen;
                c:CloseQuickBars();
            end);
        end

        if not c.uiHooked then
            c.uiHooked = true;

            local function ShowExtendedItemTooltip(tooltip)
                -- GQ's own comparison tooltips are item tooltips too
                if tooltip ~= GameTooltip then
                    return;
                end

                local _, itemLink = tooltip:GetItem();
                if c:IsSecret(itemLink) then
                    itemLink = nil;
                end

                -- extend default tooltip
                if GQ_OPTIONS[c.OPT_SHOWITEMTOOLTIP] then
                    local owner = tooltip:GetOwner();
                    local ownerName;
                    if owner and owner.GetName and not (owner.IsForbidden and owner:IsForbidden()) then
                        ownerName = owner:GetName();
                    end
                    local slotId;
                    if ownerName and ownerName:find("^Character") then
                        slotId = c:GetSlotId((ownerName:gsub("^Character", "")));
                    end

                    if slotId then
                        -- inventory slot item tooltip
                        local setName = c:LoadCurrentSetName();
                        if setName and (not c:LoadPartialOption(setName) or c:LoadSlotState(slotId, setName)) then
                            local itemString = c:LoadSlot(slotId, setName);
                            if not c:IsSetItemOnSlot(slotId, itemString) then
                                tooltip:AddLine(" ");
                                tooltip:AddDoubleLine(c:FormatTextWithColor(c:GetText("Expected Item:"), "ff0000"),
                                    c:GetItemLink(itemString));
                            end
                        end
                    elseif itemLink then
                        -- bag/bank slot item tooltip
                        local itemString = c:GetItemString(itemLink);
                        if not c:IsEmpty(itemString) then
                            local sets, spacing = c:GetItemSets(itemString);
                            if sets and getn(sets) > 0 then
                                tooltip:AddLine(" ");
                                tooltip:AddDoubleLine(c:GetText("GearQuipper set(s):"), table.concat(sets, ", "));
                                spacing = true;
                            end
                            if GQ_OPTIONS[c.OPT_SET_ITEM_COMPARISON_SHOW_HINT] then
                                local itemSlots = c:GetItemSlots(itemString);
                                if itemSlots and getn(itemSlots) > 0 then
                                    if not spacing then
                                        tooltip:AddLine(" ");
                                    end
                                    tooltip:AddLine(c:GetText("Press L-Alt to cycle through sets."));
                                end
                            end
                        end
                    end
                end

                -- load custom tooltips
                if GQ_OPTIONS[c.OPT_SET_ITEM_COMPARISON] and itemLink then
                    local comparisonSetName = c:LoadComparisonSetName();
                    if comparisonSetName then
                        c:ShowSetItemComparison(itemLink, comparisonSetName);
                    else
                        c:HideGqTooltips();
                    end
                end
            end

            c:AddItemTooltipPostCall(function(tooltip, data)
                ShowExtendedItemTooltip(tooltip);
            end);

            GameTooltip:HookScript("OnHide", function()
                c:HideGqTooltips();
            end);

            -- hook character slots for quickslots on empty slot
            for slotId, slotName in pairs(c:GetSlotInfo()) do
                local frame = _G["Character" .. slotName];
                if frame then
                    frame:HookScript("OnClick", function(self, button)
                        if button == "LeftButton" then
                            if self.quickbar then
                                self.quickbar:Hide();
                                self.quickbar = nil;
                            elseif slotId == INVSLOT_AMMO or c:GetItemString(slotId) == c.VALUE_NONE then
                                c:CloseQuickBars();
                                self.quickbar = c:OpenQuickBar(slotId);
                            end
                        end
                    end)
                    frame:HookScript("OnEnter", function()
                        c:HoverQuickBar(slotId);
                    end)
                end
            end
        end

        c:HookBlizzardFrameScripts();
        c:HookCharacterStatsFrameScripts();
        c:InitUiFrame();

        C_Timer.After(2, function()
            c:ToggleWatermark(GQ_OPTIONS[c.OPT_SHOW_WATERMARK]);
        end);
    end
end

function c:ToggleWatermark(value)
    if not c.watermark then
        local cmb = _G["CharacterMicroButton"];
        if not cmb then
            return;
        end

        c.watermark = CreateFrame("CheckButton", "GQ_Watermark", cmb);
        c.watermark:SetFrameStrata("MEDIUM");
        c.watermark:EnableMouse(false);
        c.watermark:SetAllPoints();

        c.watermark.fontString = c.watermark:CreateFontString("GQ_Watermark_FontString", "ARTWORK");
        c.watermark.fontString:SetFont("Fonts\\FRIZQT__.TTF", 7, "MONOCHROME")
        c.watermark.fontString:SetAllPoints();
        c.watermark.fontString:SetText("GQ");
    end

    if value then
        c.watermark:Show();
    else
        c.watermark:Hide();
    end
end

function c:HookBlizzardFrameScripts()
    local newFrameHasBeenHooked;
    for _, frameName in ipairs(blizzardFrameNames) do
        local frame = _G[frameName];
        if frame and not c.isFrameHooked[frameName] then
            frame:HookScript("OnShow", function()
                c:SetFramePositions();
            end);
            frame:HookScript("OnHide", function()
                c:SetFramePositions();
            end);
            c.isFrameHooked[frameName] = true;
            newFrameHasBeenHooked = true;
        end
    end
    if newFrameHasBeenHooked then
        c:SetFramePositions();
    end
end

-- Right edge of the character window including its side tabs and the GQ panel, in the units of targetFrame.
local function GetCharacterWindowRight(targetFrame)
    local right = GetFrameEdge(CharacterFrame, "GetRight", targetFrame);
    if right then
        local tabs = CharacterFrame.ModeTabs;
        if tabs and tabs:IsVisible() then
            right = right + tabs:GetWidth() * tabs:GetEffectiveScale() / targetFrame:GetEffectiveScale();
        end
        if GqUiFrame:IsVisible() then
            local gqRight = GetFrameEdge(GqUiFrame, "GetRight", targetFrame);
            if gqRight and gqRight > right then
                right = gqRight;
            end
        end
    end
    return right;
end

function c:SetFramePositions(norepeat)
    local characterFrame = _G["CharacterFrame"];
    if not (characterFrame and characterFrame:IsVisible()) or c:ReadState(InCombatLockdown) then
        return;
    end

    -- bank: moved right of the GQ panel (and back when the panel closes), only when Blizzard placed it to the
    -- right of the character window
    local bankFrame = _G["BankFrame"];
    if bankFrame and bankFrame:IsVisible() and (GqUiFrame:IsVisible() or bankFrame.gqMoved) then
        local bankLeft, bankTop = GetFrameEdge(bankFrame, "GetLeft"), GetFrameEdge(bankFrame, "GetTop");
        local characterLeft = GetFrameEdge(characterFrame, "GetLeft", bankFrame);
        local xOffset = GetCharacterWindowRight(bankFrame);
        local parentTop = GetFrameEdge(UIParent, "GetTop", bankFrame);
        if bankLeft and bankTop and characterLeft and xOffset and parentTop and bankLeft > characterLeft then
            bankFrame:ClearAllPoints();
            bankFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", xOffset + FRAME_SPACING, bankTop - parentTop);
            bankFrame.gqMoved = GqUiFrame:IsVisible();
        end
    end

    -- the UI panel manager anchors panels after their OnShow, so position once more on the next frame
    if not norepeat then
        C_Timer.After(0.001, function()
            c:SetFramePositions(true);
        end);
    end
end

function c:GetCharacterStatsFrameNames()
    return csFrameNames;
end

function c:HookCharacterStatsFrameScripts()
    -- hook character stats frame scripts
    for _, csFrameName in ipairs(csFrameNames) do
        local csFrame = _G[csFrameName];
        if csFrame and not c.isFrameHooked[csFrameName] then
            csFrame:HookScript("OnShow", function()
                c:SetGqUiFramePosition();
            end);
            csFrame:HookScript("OnHide", function()
                c:SetGqUiFramePosition();
            end);
            c.isFrameHooked[csFrameName] = true;
        end
    end
end

function c:CreatePaperDollButton()
    local button = CreateFrame("Button", "GQ_PaperDollButton", c.paperDollFrame);
    if GetPaperDollAnchor() ~= c.paperDollFrame then
        -- top right of the paper doll pane, above the right slot column and below the level strip
        button:SetPoint("TOPRIGHT", GetPaperDollAnchor(), "TOPRIGHT", -20, -38);
    else
        button:SetPoint("TOPRIGHT", c.paperDollFrame, "TOPRIGHT", -40, -45);
    end
    -- the character model scene is mouse enabled and sits above the paper doll's own level
    local itemsFrame = _G["PaperDollItemsFrame"];
    if itemsFrame then
        button:SetFrameLevel(itemsFrame:GetFrameLevel() + 1);
    end
    button:SetWidth(50);
    button:SetHeight(20);
    button:SetText("GQ");
    button:SetNormalFontObject("GameFontNormal");
    button:RegisterForClicks("LeftButtonUp");
    button:SetScript("OnClick", function()
        c:ToggleUI();
    end);

    local ntex = button:CreateTexture();
    ntex:SetTexture("Interface/Buttons/UI-Panel-Button-Up");
    ntex:SetTexCoord(0, 0.625, 0, 0.6875);
    ntex:SetAllPoints();
    button:SetNormalTexture(ntex);

    local htex = button:CreateTexture();
    htex:SetTexture("Interface/Buttons/UI-Panel-Button-Highlight");
    htex:SetTexCoord(0, 0.625, 0, 0.6875);
    htex:SetAllPoints();
    button:SetHighlightTexture(htex);

    local ptex = button:CreateTexture();
    ptex:SetTexture("Interface/Buttons/UI-Panel-Button-Down");
    ptex:SetTexCoord(0, 0.625, 0, 0.6875);
    ptex:SetAllPoints();
    button:SetPushedTexture(ptex);

    local dtex = button:CreateTexture();
    dtex:SetTexture("Interface/Buttons/UI-Panel-Button-Disabled");
    dtex:SetTexCoord(0, 0.625, 0, 0.6875);
    dtex:SetAllPoints();
    button:SetDisabledTexture(dtex);

    return button;
end

function c:DisablePaperDollButton()
    c.paperDollFrame.paperDollButton:Disable();
end

function c:EnablePaperDollButton()
    c.paperDollFrame.paperDollButton:Enable();
end

function c:CreatePaperDollLabel()
    local label = CreateFrame("Frame", "GQ_PaperDollLabel", c.paperDollFrame);
    label:SetPoint("CENTER", GetPaperDollAnchor(), "CENTER", 0, -5);
    label:SetFrameStrata("HIGH");
    label:SetWidth(200);
    label:SetHeight(20);
    label:EnableMouse();
    label:SetScript("OnEnter", function(self)
        self:SetAlpha(0);
    end);
    label:SetScript("OnLeave", function(self)
        self:SetAlpha(1);
    end);

    label.text = label:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
    label.text:SetPoint("CENTER", 0, 0);

    return label;
end

function c:SetPaperDollLabelText(setName)
    if GQ_OPTIONS[c.OPT_SHOWCURRENTSET] then
        setName = setName or c:LoadCurrentSetName();
        if not setName then
            c.paperDollFrame.paperDollLabel.text:SetFormattedText("%s%s: %s", "|cffff0000", c:GetText("Current set"),
                UNKNOWN);
        elseif c:GetTableSize(c:GetIgnoredItems()) > 0 then
            c.paperDollFrame.paperDollLabel.text:SetFormattedText("%s%s: \"%s\"", "|cff6977f0",
                c:GetText("Current set"), setName);
        elseif c:IsSetComplete() then
            c.paperDollFrame.paperDollLabel.text:SetFormattedText("%s%s: \"%s\"", "|cffffcc00",
                c:GetText("Current set"), setName);
        else
            c.paperDollFrame.paperDollLabel.text:SetFormattedText("%s%s: \"%s\"", "|cffff0000",
                c:GetText("Current set"), setName);
        end
        c.paperDollFrame.paperDollLabel:Show();
    else
        c.paperDollFrame.paperDollLabel:Hide();
    end
end

function c:HideGqTooltips()
    for _, tt in ipairs(gqTooltips) do
        tt:Hide();
    end
end

function c:GetGqTooltip(index)
    index = index or 1;
    if not gqTooltips[index] then
        gqTooltips[index] = CreateFrame("GameTooltip", "GQ_Tooltip_" .. index, UIParent, "GameTooltipTemplate");
        gqTooltips[index]:SetToplevel(true);
    end
    return gqTooltips[index];
end

function c:ShowSetItemComparison(itemLink, setName, gameTooltipOwner)
    local itemSlots = c:GetItemSlots(itemLink);
    if itemSlots then
        for i, slotId in ipairs(itemSlots) do
            local setItemLink = c:LoadSlot(slotId, setName);
            if gameTooltipOwner then
                GameTooltip:SetOwner(gameTooltipOwner, 'ANCHOR_RIGHT');
                GameTooltip:SetHyperlink(itemLink);
                GameTooltip:Show();
            end

            local tt = c:GetGqTooltip(i);
            if i == 1 then
                tt:SetOwner(GameTooltip, "ANCHOR_NONE");
            else
                tt:SetOwner(c:GetGqTooltip(i - 1), "ANCHOR_NONE");
            end

            if not c:IsEmpty(setItemLink) then
                if c:IsNumeric(setItemLink) then
                    -- ammo workaround
                    setItemLink = c:GetItemLink(setItemLink);
                end

                if not c:IsEmpty(setItemLink) then
                    if not pcall(function()
                        tt:SetHyperlink(setItemLink);
                    end) then
                        if not c.itemComparisonErrorShown then
                            c:Println(c:GetText(
                                "Error while displaying item comparison tooltip for %s. Tooltip was resetted. This message will only be shown once per session.",
                                itemLink));
                            c.itemComparisonErrorShown = true;
                        end
                        c:SaveComparisonSetName(); -- reset set item comparison on error
                    end
                end
            else
                tt:AddLine(c:GetText("Empty slot"));
            end

            tt:AddLine(" ");
            tt:AddLine(c:GetText("%s slot item in \"%s\"", c:GetDisplaySlotName(slotId), setName));
            tt:Show();

            tt:ClearAllPoints();
            local gameTooltipLeft = GetFrameEdge(GameTooltip, "GetLeft");
            if gameTooltipLeft and gameTooltipLeft < 250 then
                if i == 1 then
                    tt:SetPoint("TOPLEFT", tt:GetOwner(), "TOPRIGHT");
                else
                    tt:SetPoint("TOPLEFT", tt:GetOwner(), "BOTTOMLEFT");
                end
            else
                if i == 1 then
                    tt:SetPoint("TOPRIGHT", tt:GetOwner(), "TOPLEFT");
                else
                    tt:SetPoint("TOPRIGHT", tt:GetOwner(), "BOTTOMRIGHT");
                end
            end
        end
        return true;
    end
end

local function AddSetFromDialog(setName)
    setName = c:Trim(setName);
    if c:IsValidSetName(setName) then
        c:SaveSet(setName, false);
        c:UpdateBroker();
    else
        c:Println(c:GetText(
            "Invalid set name: \"%s\". Set names must [1] not be empty, [2] be unique (case insensitive) and [3] not contain \"$\" (reserved).",
            setName));
    end
end

function c:ShowAddSetDialog()
    StaticPopupDialogs["GQ_DIALOG_ADDSET"] = StaticPopupDialogs["GQ_DIALOG_ADDSET"] or {
        text = c:GetText("Enter a name for this set:"),
        button1 = APPLY,
        button2 = CANCEL,
        hasEditBox = true,
        maxLetters = 30,
        EditBoxOnEnterPressed = function(self)
            local parent = self:GetParent();
            AddSetFromDialog(self:GetText());
            parent:Hide();
        end,
        EditBoxOnEscapePressed = function(self)
            self:GetParent():Hide();
        end,
        OnAccept = function(self, data, data2)
            local editBox = self.GetEditBox and self:GetEditBox() or self.editBox;
            AddSetFromDialog(editBox:GetText());
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3
    };

    StaticPopup_Show("GQ_DIALOG_ADDSET");
end

function c:ShowRemoveSetDialog(setName)
    if setName then
        StaticPopupDialogs["GQ_DIALOG_REMOVESET"] = StaticPopupDialogs["GQ_DIALOG_REMOVESET"] or {
            text = c:GetText("Do you really want to remove \"%s\"?", "%s"),
            button1 = c:GetText(YES),
            button2 = c:GetText(NO),
            OnAccept = function(self, data)
                if data and tContains(c:LoadSetNames(), data) then
                    c:RemoveSet(data);
                    GqUiFrame_BtnSaveSet:Hide();
                    GqUiFrame_BtnRemoveSet:Hide();
                    c:UpdateBroker();
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3
        };

        local dialog = StaticPopup_Show("GQ_DIALOG_REMOVESET", setName, nil, setName);
        if dialog then
            dialog.data = setName;
        end
    end
end

function c:ShowResetDialog()
    StaticPopupDialogs["GQ_DIALOG_RESET"] = StaticPopupDialogs["GQ_DIALOG_RESET"] or {
        text = c:GetText("This will reset GearQuipper to defaults. All your sets will be lost.\n\nAre you sure?"),
        button1 = c:GetText("Reset"),
        button2 = c:GetText("Cancel"),
        OnAccept = function()
            GQ_OPTIONS = {};
            GQ_DATA = {};
            c:ToggleUI(false);
            c:Init();
            c:CreateDefaultSet();
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3
    };

    StaticPopup_Show("GQ_DIALOG_RESET");
end

function c:SetSlotInfo(slotId, color)
    if not slotId then
        for slotId, _ in pairs(c:GetSlotInfo()) do
            c:SetSlotInfo(slotId);
        end
        return;
    else
        local slot = _G["Character" .. c:GetSlotInfo()[slotId]];
        if not slot then
            return;
        end
        if not slot.gqTex then
            slot.slotId = slotId;
            -- unnamed: "<slot>IconTexture" is Blizzard's own icon global on the ammo slot
            slot.gqTex = slot:CreateTexture(nil, "OVERLAY");
            slot.gqTex:SetAllPoints();
        end

        if GQ_OPTIONS[c.OPT_SHOWSLOTBACKDROPS] and not color then
            local setName = c:LoadCurrentSetName();

            if c:LoadPartialOption(setName) and not c:LoadSlotState(slotId, setName) then
                color = "white";
            elseif c:IsIgnoredItem(slotId) then
                color = "blue";
            elseif c:IsSetItemOnSlot(slotId, c:LoadSlot(slotId, setName)) then
                color = "green";
            else
                color = "red";
            end
        end

        if color == "red" then
            slot.gqTex:SetColorTexture(1, 0, 0, 0.2);
        elseif color == "white" then
            slot.gqTex:SetColorTexture(1, 1, 1, 0.2);
        elseif color == "blue" then
            slot.gqTex:SetColorTexture(0, 0, 1, 0.2);
        else
            -- "green" (actually empty)
            slot.gqTex:SetColorTexture(0, 0, 0, 0);
        end
    end
end

function c:GetSlotStateBoxes()
    if not slotStateBoxes then
        slotStateBoxes = {};
        for slotId, slotName in pairs(c:GetSlotInfo()) do
            local slot = _G["Character" .. slotName];
            if slot then
                slotStateBoxes[slotId] = c:CreateSlotStateBox(slotName, slot);
            end
        end
    end
    return slotStateBoxes;
end

function c:ShowSlotStateBoxes()
    if GqUiFrame:IsVisible() and c:LoadPartialOption() then
        for slotId, checkBox in pairs(c:GetSlotStateBoxes()) do
            c:SetSlotState(slotId, c:LoadSlotState(slotId));
            checkBox:Show();
        end
    end
end

function c:HideSlotStateBoxes()
    for _, checkBox in pairs(c:GetSlotStateBoxes()) do
        checkBox:Hide();
    end
end

function c:CreateSlotStateBox(slotName, parent)
    local checkbutton = CreateFrame("CheckButton", slotName .. "StateBox", parent, "UICheckButtonTemplate");
    checkbutton:SetWidth(24);
    checkbutton:SetHeight(24);
    checkbutton:SetPoint("BOTTOMLEFT", -3, -3);
    checkbutton:RegisterForClicks("LeftButtonUp");
    checkbutton:SetScript("OnClick", function(self)
        local slotId = c:GetSlotId(slotName);
        c:SaveSlotState(slotId, self:GetChecked());
        if GqUiFrame:IsVisible() then
            c:RefreshSetList();
        end

        if not self:GetChecked() then
            c:SetSlotInfo(slotId, "white");
            return;
        elseif not c:IsSetItemOnSlot(slotId, c:LoadSlot(slotId)) then
            c:SaveSlot(slotId);
        end
        c:SetSlotInfo(slotId, "green");
    end);
    checkbutton:Hide();

    return checkbutton;
end

function c:SetSlotState(slotId, value)
    c:GetSlotStateBoxes()[slotId]:SetChecked(value);
end

function c:GetSlotState(slotId)
    return c:GetSlotStateBoxes()[slotId]:GetChecked();
end

-- adds frame to result when the container slot holds no item of the set (empty slots included)
local function AddIfNotInSet(result, frame, itemStrings, bagId, slotId)
    if frame and bagId and slotId then
        local itemString = c:GetItemString(c:GetContainerItemLink(bagId, slotId));
        if c:IsEmpty(itemString) or not c:TableContains(itemStrings, itemString) then
            tinsert(result, frame);
        end
    end
end

local function GetContainersForItems(itemStrings)
    local result = {};
    if itemStrings then
        if c:IsAddonEnabled("AdiBags") then
            for slotId = 0, 255 do
                local frame = _G["AdiBagsItemButton" .. slotId];
                if frame then
                    AddIfNotInSet(result, frame, itemStrings, frame.bag, frame.slot);
                end

                if c:IsAtBank() then
                    local bankFrame = _G["AdiBagsBankItemButton" .. slotId];
                    if bankFrame then
                        AddIfNotInSet(result, bankFrame, itemStrings, bankFrame.bag, bankFrame.slot);
                    end
                end
            end
        elseif c:IsAddonEnabled("ArkInventory") then
            -- I'm just guessing here...
            for invId = 0, 5 do
                for bagId = 0, 8 do
                    for slotId = 1, MAX_ITEMS_PER_CONTAINER do
                        local frameName = "ARKINV_Frame" .. invId .. "ScrollContainerBag" .. bagId .. "Item" .. slotId;
                        local arkFrame = _G[frameName];
                        if arkFrame and arkFrame.ARK_Data then
                            AddIfNotInSet(result, arkFrame, itemStrings, arkFrame.ARK_Data.blizzard_id,
                                arkFrame.ARK_Data.slot_id);
                        end
                    end
                end
            end
        elseif c:IsAddonEnabled("TBag") and TInvItm and TInvItm[TInvFrame.playerid] then
            -- I'm just guessing here...
            for bagId = 1, 13 do
                for slotId = 1, MAX_ITEMS_PER_CONTAINER do
                    local match = false;
                    local tbagFrame = _G["TInvainerFrame" .. bagId .. "Item" .. slotId];
                    if tbagFrame then
                        if TInvItm[TInvFrame.playerid][bagId] and TInvItm[TInvFrame.playerid][bagId][slotId] and
                            TInvItm[TInvFrame.playerid][bagId][slotId]["il"] then
                            local itemName = TInvItm[TInvFrame.playerid][bagId][slotId]["in"];
                            if not itemName then
                                break
                            end
                            for _, is in ipairs(itemStrings) do
                                if not match and c:GetItemName(is) == itemName then
                                    match = true;
                                    break
                                end
                            end
                        end

                        if not match then
                            tinsert(result, tbagFrame);
                        end
                    end
                end
            end
        elseif c:IsAddonEnabled("Bagnon") then
            for bagId = 0, NUM_BAG_SLOTS do
                for slotId = 1, MAX_ITEMS_PER_CONTAINER do
                    local frameName = "ContainerFrame" .. bagId .. "Item" .. slotId;
                    if _G[frameName] and _G[frameName].info then
                        local itemString = c:GetItemString(_G[frameName].info.link);
                        if c:IsEmpty(itemString) or not c:TableContains(itemStrings, itemString) then
                            tinsert(result, _G[frameName]);
                        end
                    end
                end
            end
        else
            -- default player bags: item buttons are pooled and unnamed, each knows its bag and slot
            if ContainerFrameUtil_EnumerateContainerFrames then
                for _, containerFrame in ContainerFrameUtil_EnumerateContainerFrames() do
                    if containerFrame:IsShown() and containerFrame.EnumerateValidItems then
                        for _, itemButton in containerFrame:EnumerateValidItems() do
                            if itemButton then
                                AddIfNotInSet(result, itemButton, itemStrings, itemButton:GetBagID(),
                                    itemButton:GetID());
                            end
                        end
                    end
                end
            end

            -- default bank (tabbed, pooled item buttons)
            local bankPanel = _G["BankFrame"] and _G["BankFrame"].BankPanel;
            if bankPanel and bankPanel:IsVisible() and bankPanel.EnumerateValidItems then
                for itemButton in bankPanel:EnumerateValidItems() do
                    if itemButton.GetBankTabID and itemButton.GetContainerSlotID then
                        AddIfNotInSet(result, itemButton, itemStrings, itemButton:GetBankTabID(),
                            itemButton:GetContainerSlotID());
                    end
                end
            end
        end
    end

    return result;
end

local function ResetFrameAlpha(frameName)
    if _G[frameName] then
        _G[frameName]:SetAlpha(1);
    end
end

function c:HighlightItemsEquipped(itemStrings, setName)
    if not itemStrings then
        -- reset
        for id, name in pairs(c:GetSlotInfo()) do
            ResetFrameAlpha("Character" .. name);
        end
    else
        -- set
        for id, name in pairs(c:GetSlotInfo()) do
            local slot = _G["Character" .. name];
            if slot then
                slot:SetAlpha(0.35);
            end
        end
        for _, itemString in pairs(itemStrings) do
            local list = c:IsItemEquipped(itemString);
            if list then
                for _, slotId in ipairs(list) do
                    if not c:LoadPartialOption(setName) or c:LoadSlotState(slotId, setName) then
                        ResetFrameAlpha("Character" .. c:GetSlotInfo()[slotId]);
                    end
                end
            end
        end
    end
end

function c:HighlightItemsInBags(itemStrings)
    -- reset alpha of every frame dimmed before (pooled buttons may have been hidden or reused since)
    for frame in pairs(dimmedBagFrames) do
        frame:SetAlpha(1);
    end
    wipe(dimmedBagFrames);

    -- set alpha
    for _, frame in ipairs(GetContainersForItems(itemStrings)) do
        frame:SetAlpha(0.35);
        dimmedBagFrames[frame] = true;
    end
end
