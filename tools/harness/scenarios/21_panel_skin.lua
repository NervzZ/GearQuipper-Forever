-- (t) The panel and its paper doll parts go through the skin adapter: with EllesmereUI (character sheet style
-- "eui") every widget, including rows created after login and recycled rows, is skinned exactly once with the right
-- primitive, the rows switch from Blizzard's card art to flat bars on child frames (EllesmereUI's restrip leaves
-- them), and a live toggle-on skins everything built so far; with the sheet left "blizzard", or no suite, nothing is
-- skinned. ElvUI gets its Handle* calls. An unknown remembered tab falls back to Sets.
-- frameinset / frameclose: the panel's own Inset and CloseButton, which the frame kind covers
local EUI = {frame = {"Shell"}, frameinset = {"Inset"}, frameclose = {"CloseButton"}, close = {"CloseButton"}, button = {"Button", "StateButtonLabel"},
    checkbox = {"Checkbox"}, dropdown = {"Dropdown"}, scrollbar = {"ScrollBar"}, tab = {"Tab"}, font = {"Font"},
    panel = {"Panel"}};
local ELV = {frame = {"HandleFrame"}, frameinset = {}, frameclose = {}, close = {"HandleCloseButton"}, button = {"HandleButton"}, checkbox = {"HandleCheckBox"},
    dropdown = {"HandleDropDownBox"}, scrollbar = {"HandleTrimScrollBar"}, tab = {"HandleTab"}, font = {},
    panel = {"HandleFrame"}};

-- sets, bindings and an open panel: rows exist (built after login)
local function prepare(H, gq, panel)
    H.advance(1);
    gq:SaveSet("Tank", false);
    H.wearSetBPieces();
    gq:SaveSet("DPS", false);
    gq:SetEventsEnabled(true);
    gq:SaveEventBinding({[gq.FIELD_TYPE] = gq.EVENT_TALENTS_CHANGED,
        [gq.FIELD_SUBTYPE] = {name = gq:GetTalentSpecializations()[1], spellId = 1}, [gq.FIELD_NAME] = "Tank",
        [gq.FIELD_PVE] = true, [gq.FIELD_PVP] = true});
    gq:SaveEventBinding({[gq.FIELD_TYPE] = gq.EVENT_MOUNT, [gq.FIELD_NAME] = "DPS", [gq.FIELD_PVE] = true});
    H.switchTo(gq, "Tank");
    panel.open();
    gq:SavePartialOption("Tank", true);
    gq:ShowSlotStateBoxes();
    gq:SavePartialOption("Tank", false);
    gq:HideSlotStateBoxes();
    panel.tab("Events");
    panel.tab("Sets");
end

-- every widget of the panel (and the paper doll parts) with its kind
local function widgets(gq, panel)
    local list = {
        {GqUiFrame, "frame"}, {GqUiFrame.Inset, "frameinset"}, {GqUiFrame.CloseButton, "frameclose"},
        {GqUiFrame:GetTitleText(), "font"}, {GqUiFrame_BtnOptions, "button"}, {GqUiFrameTab1, "tab"},
        {GqUiFrameTab2, "tab"}, {GqUiFrameSetListScrollBar, "scrollbar"}, {GqUiFrameBindingListScrollBar, "scrollbar"},
        {GqUiFrameStatusText, "font"}, {GqAddSetButton, "button"}, {GqUiFrame_BtnSaveSet, "button"},
        {GqUiFrame_CbEnableEvents, "checkbox"}, {GqUiFrame_CbEnableEvents.Text, "font"}, {GqAddEventBinding, "button"},
        {GqUiFrameBindingForm_EventPicker, "dropdown"}, {GqUiFrameBindingForm_DetailPicker, "dropdown"},
        {GqUiFrameBindingForm_Detail2Picker, "dropdown"}, {GqUiFrameBindingForm_SetPicker, "dropdown"},
        {GqUiFrameBindingForm_CbPVE, "checkbox"}, {GqUiFrameBindingForm_CbPVP, "checkbox"},
        {GqUiFrameBindingForm_CbPVE.Text, "font"}, {GqUiFrameBindingForm.Title, "font"},
        {GqUiFrameBindingForm.Warning, "font"}, {GqUiFrameBindingForm.Error, "font"},
        {GqUiFrameBindingForm_BtnAdd, "button"}, {GqUiFrameBindingForm_BtnCancel, "button"},
        {GQ_PaperDollButton, "button"}, {GQ_PaperDollLabel.text, "font"}, {HeadSlotStateBox, "checkbox"},
        {MainHandSlotStateBox, "checkbox"},
    };
    for _, row in ipairs(panel.setRows()) do
        for _, part in ipairs({{row, "panel"}, {row.Name, "font"}, {row.Partial, "font"}, {row.SpecText, "font"},
            {row.ToBank, "button"}, {row.ToBags, "button"}}) do
            list[#list + 1] = part;
        end
    end
    for _, row in ipairs(panel.bindingRows()) do
        for _, part in ipairs({{row, "panel"}, {row.Event, "font"}, {row.Info, "font"}, {row.SetPicker, "dropdown"},
            {row.Delete, "close"}}) do
            list[#list + 1] = part;
        end
    end
    return list;
end

local function assertSkinnedOnce(H, gq, panel, map, msg)
    for i, entry in ipairs(widgets(gq, panel)) do
        local widget, kind = entry[1], entry[2];
        H.assertTrue(widget, msg .. ": widget #" .. i .. " exists");
        H.assertEq(table.concat(H.suiteCallsFor(widget), ","), table.concat(map[kind], ","),
            msg .. ": widget #" .. i .. " (" .. kind .. ")");
    end
end

local function assertStockLook(H, gq, panel)
    H.assertEq(#H.suiteCalls, 0, "nothing skinned");
    H.assertEq(gq:GetSkinBackend(), nil);
    for _, row in ipairs(panel.setRows()) do
        local current = row:GetElementData().setName == gq:LoadCurrentSetName();
        H.assertTrue(row.Card:IsShown() and row.Card:GetAlpha() == 1, "Blizzard card art");
        H.assertTrue(row.IconBorder:IsShown(), "icon frame");
        H.assertEq(row.SelectedBar:IsShown(), current, "selected card on the current set");
        H.assertFalse(row.FlatSelected:IsShown(), "no flat bar");
    end
    H.assertTrue(panel.setRow("Tank").SpecRing:IsShown() and not panel.setRow("Tank").SpecPlate:IsShown(),
        "spec ring");
    H.assertTrue(panel.bindingRow(1).Separator:IsShown(), "stock separator");
    H.assertEq(GqUiFrame.Bg:GetAlpha(), 1, "panel art");
end

local function stockRun(H, gq)
    local panel = H.include("helpers/gq_panel.lua");
    prepare(H, gq, panel);
    assertStockLook(H, gq, panel);
    panel.close();
end

-- under a skin: flat bars instead of the cards; the dynamic art sits on child frames and survives a restrip
local function assertFlatLook(H, gq, panel)
    for _, row in ipairs(panel.setRows()) do
        local current = row:GetElementData().setName == gq:LoadCurrentSetName();
        H.assertFalse(row.Card:IsShown() or row.SelectedBar:IsShown() or row.IconBorder:IsShown(), "no card art");
        H.assertEq(row.FlatSelected:IsShown(), current, "flat bar on the current set");
    end
    local tank = panel.setRow("Tank");
    H.assertTrue(tank.SpecPlate:IsShown() and not tank.SpecRing:IsShown(), "flat spec badge");
    H.assertFalse(panel.bindingRow(1).Separator:IsShown(), "no stock separator");
    H.mouseEnter(tank);
    H.assertTrue(tank.FlatHover:IsShown() and not tank.HighlightBar:IsShown(), "flat hover");
    H.euiRestrip();
    for _, tex in ipairs({tank.FlatSelected, tank.FlatHover, tank.Icon, tank.Tick, tank.SpecPlate,
        GqUiFrame_BtnOptions.Icon}) do
        H.assertTrue(tex:GetAlpha() > 0, "dynamic art survives EllesmereUI's restrip");
    end
    H.mouseLeave(tank);
    for _, row in ipairs({tank, panel.bindingRow(1)}) do
        for _, region in ipairs({row:GetRegions()}) do
            H.assertFalse(region:IsObjectType("Texture") and not H.euiState.owned[region],
                "a skinned row carries no GQ texture of its own (they sit on child frames)");
        end
    end
    H.assertFalse(tank.Card:IsShown(), "the card is hidden, not faded");
end

return {
    variants = {
        {name = "EllesmereUI eui", suites = {EllesmereUI = {charsheetStyle = "eui"}}, run = function(H, gq)
            local panel = H.include("helpers/gq_panel.lua");
            prepare(H, gq, panel);
            H.assertEq(gq:GetSkinBackend(), "EllesmereUI");
            assertSkinnedOnce(H, gq, panel, EUI, "after login");
            assertFlatLook(H, gq, panel);

            -- refreshes recycle the rows (no second skin); a new set gets a new row, skinned once
            local rowsBefore = panel.setRows();
            gq:RefreshSetList();
            gq:RefreshEventEntries();
            H.assertTrue(panel.setRows()[1] == rowsBefore[1], "recycled");
            GqAddSetButton:Click("LeftButton");
            H.acceptPopup("Heal");
            H.advance(0.5);
            H.assertEq(#panel.setRows(), #rowsBefore + 1, "a row more");
            assertSkinnedOnce(H, gq, panel, EUI, "after refreshes");
            panel.close();
            panel.open();
            assertSkinnedOnce(H, gq, panel, EUI, "after reopening");
            H.assertNoErrors();
        end},

        {name = "EllesmereUI blizzard sheet", suites = {EllesmereUI = {charsheetStyle = "blizzard"}}, run = stockRun},

        {name = "no suite", run = stockRun},

        {name = "EllesmereUI live toggle-on", suites = {EllesmereUI = {thirdPartySkinsOff = true}},
            run = function(H, gq)
                local panel = H.include("helpers/gq_panel.lua");
                prepare(H, gq, panel);
                assertStockLook(H, gq, panel);
                H.euiToggleOn();
                H.assertEq(gq:GetSkinBackend(), "EllesmereUI");
                assertSkinnedOnce(H, gq, panel, EUI, "after the toggle");
                gq:RefreshSetList();
                gq:RefreshEventEntries();
                assertFlatLook(H, gq, panel);
                assertSkinnedOnce(H, gq, panel, EUI, "after the refresh");
            end},

        {name = "ElvUI", suites = {ElvUI = {}}, run = function(H, gq)
            local panel = H.include("helpers/gq_panel.lua");
            prepare(H, gq, panel);
            H.assertEq(gq:GetSkinBackend(), "ElvUI");
            assertSkinnedOnce(H, gq, panel, ELV, "ElvUI");
            for _, call in ipairs(H.suiteCalls) do
                if call.primitive == "HandleDropDownBox" then
                    H.assertEq(call.args[1], call.widget:GetWidth(), "dropdowns keep their width");
                end
            end
        end},

        {name = "unknown remembered tab", savedVariables = {GQ_OPTIONS = {OPT_PANELTAB = "bogus"}},
            run = function(H, gq)
                local panel = H.include("helpers/gq_panel.lua");
                H.assertEq(GQ_OPTIONS[gq.OPT_PANELTAB], "SETS", "migrated to Sets");
                panel.open();
                H.assertEq(panel.selectedTab(), "Sets");
                H.assertTrue(GqUiFrameSetsPage:IsVisible() and not GqUiFrameEventsPage:IsShown());
            end},
    },
};
