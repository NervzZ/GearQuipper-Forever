-- (s) The panel's Events tab: the "Enable event bindings" box is not inverted and drives c:IsEventsEnabled; "Add
-- binding" swaps the list for an inline form whose pickers depend on each other like the old dialog (event ->
-- detail -> optional detail 2, set, PvE/PvP, warning and error texts); a row's set picker saves the binding; the
-- delete button removes it; pickers, delete and Add are disabled while events are off, while switching and (Add)
-- in combat.
local function controlsEnabled(panel)
    for _, row in ipairs(panel.bindingRows()) do
        if row.SetPicker:IsShown() and row.SetPicker:IsEnabled() or row.Delete:IsEnabled() then
            return true;
        end
    end
    return false;
end

local function controlsDisabled(panel)
    for _, row in ipairs(panel.bindingRows()) do
        if row.SetPicker:IsEnabled() or row.Delete:IsEnabled() then
            return false;
        end
    end
    return not GqAddEventBinding:IsEnabled();
end

return function(H, gq)
    local panel = H.include("helpers/gq_panel.lua");
    H.advance(1);
    gq:SaveSet("Tank", false);
    H.wearSetBPieces();
    gq:SaveSet("DPS", false);
    H.switchTo(gq, "Tank");

    panel.open();
    panel.tab("Events");
    H.assertTrue(GqUiFrameEventsPage:IsVisible() and not GqUiFrameSetsPage:IsShown(), "events page");
    H.assertEq(#panel.bindingRows(), 0, "no bindings");
    H.assertTrue(GqUiFrameEventsPage and GqUiFrameBindingList:IsVisible(), "list shown");

    -- the box shows the option itself (off by default), not inverted
    H.assertFalse(gq:IsEventsEnabled(), "events off by default");
    H.assertFalse(GqUiFrame_CbEnableEvents:GetChecked(), "box unchecked = off");
    H.assertEq(GqUiFrame_CbEnableEvents.Text:GetText(), "Enable event bindings");
    H.assertFalse(GqAddEventBinding:IsEnabled(), "Add binding needs events on");
    GqUiFrame_CbEnableEvents:Click("LeftButton");
    H.assertTrue(gq:IsEventsEnabled(), "checked = on");
    H.assertTrue(GqAddEventBinding:IsEnabled(), "Add binding enabled");
    GqUiFrame_CbEnableEvents:Click("LeftButton");
    H.assertFalse(gq:IsEventsEnabled(), "unchecked = off");
    H.assertFalse(GqAddEventBinding:IsEnabled());
    GqUiFrame_CbEnableEvents:Click("LeftButton");
    H.slash("/gq toggleevents");
    H.assertFalse(gq:IsEventsEnabled(), "slash toggled off");
    H.assertFalse(GqUiFrame_CbEnableEvents:GetChecked(), "the box follows the slash command");
    H.slash("/gq toggleevents");
    H.assertTrue(GqUiFrame_CbEnableEvents:GetChecked() and GqAddEventBinding:IsEnabled(), "on again");

    -- the form: a zone binding with a subzone
    GqAddEventBinding:Click("LeftButton");
    local form = GqUiFrameBindingForm;
    H.assertTrue(form:IsVisible(), "form shown");
    H.assertFalse(GqUiFrameBindingList:IsVisible() or GqAddEventBinding:IsVisible(), "list and its footer hidden");
    local eventPicker, detailPicker = GqUiFrameBindingForm_EventPicker, GqUiFrameBindingForm_DetailPicker;
    local detail2Picker, setPicker = GqUiFrameBindingForm_Detail2Picker, GqUiFrameBindingForm_SetPicker;
    H.assertEq(H.dropdownText(eventPicker), "on < choose event >");
    H.assertEq(H.dropdownText(setPicker), "< choose set >");
    H.assertFalse(detailPicker:IsShown() or detail2Picker:IsShown(), "detail pickers hidden");
    H.assertTrue(GqUiFrameBindingForm_CbPVE:GetChecked() and GqUiFrameBindingForm_CbPVP:GetChecked(), "PvE + PvP");
    H.assertFalse(GqUiFrameBindingForm_BtnAdd:IsEnabled(), "Add needs a choice");
    local events = H.dropdownEntries(eventPicker);
    H.assertEq(#events, #gq:GetEventNamesSorted(), "every event");
    H.assertEq(events[1].text, gq:GetEvents()[gq.EVENT_MOUNT], "the old order (mount first)");
    H.assertTrue(events[1].radio, "radio entries");

    H.pickDropdown(eventPicker, "on entering zone");
    H.assertEq(H.dropdownText(eventPicker), "on entering zone");
    H.assertTrue(detailPicker:IsShown(), "zone events need a zone");
    H.assertEq(H.dropdownText(detailPicker), "< choose zone >");
    H.assertFalse(detail2Picker:IsShown());
    H.pickDropdown(detailPicker, "Eastern Kingdoms");
    H.assertTrue(detail2Picker:IsShown(), "a zone with subzones offers them");
    H.assertEq(H.dropdownText(detail2Picker), "< subzone (optional) >");
    H.assertFalse(GqUiFrameBindingForm_BtnAdd:IsEnabled(), "still no set");
    H.pickDropdown(detail2Picker, "Elwynn Forest");
    H.pickDropdown(setPicker, "Tank");
    H.assertTrue(GqUiFrameBindingForm_BtnAdd:IsEnabled(), "complete");
    local setEntries = H.dropdownEntries(setPicker);
    H.assertEq(setEntries[1].text, "[Previous set]");
    H.assertEq(setEntries[2].text, "[Previous equipment]");
    H.assertEq(#setEntries, 2 + #gq:LoadSetNames(), "every set plus the two keywords");
    GqUiFrameBindingForm_BtnAdd:Click("LeftButton");
    H.assertFalse(form:IsShown(), "form closed after Add");
    H.assertTrue(GqUiFrameBindingList:IsVisible(), "back to the list");
    local bindings = gq:LoadEventBindings();
    H.assertEq(#bindings, 1, "binding saved");
    H.assertEq(bindings[1][gq.FIELD_TYPE], gq.EVENT_ZONE_ENTER);
    H.assertEq(bindings[1][gq.FIELD_SUBTYPE].name, "Elwynn Forest", "the subzone is stored as the zone");
    H.assertEq(bindings[1][gq.FIELD_NAME], "Tank");
    local row = panel.bindingRow(1);
    H.assertEq(row.Event:GetText(), "On entering zone: Elwynn Forest");
    H.assertEq(row.Info:GetText(), "PvE + PvP");
    H.assertEq(H.dropdownText(row.SetPicker), "Tank");

    -- the same event again: error, Add disabled; Cancel leaves everything as it was
    GqAddEventBinding:Click("LeftButton");
    H.assertEq(H.dropdownText(eventPicker), "on < choose event >", "the form starts empty again");
    H.assertFalse(detailPicker:IsShown(), "detail hidden again");
    H.pickDropdown(eventPicker, "on entering zone");
    H.pickDropdown(detailPicker, "Eastern Kingdoms");
    H.pickDropdown(detail2Picker, "Elwynn Forest");
    H.pickDropdown(setPicker, "DPS");
    H.assertTrue(GqUiFrameBindingForm.Error:GetText():find("This event already exists."), "duplicate error");
    H.assertFalse(GqUiFrameBindingForm_BtnAdd:IsEnabled(), "no duplicate");
    -- changing the event resets the details
    H.pickDropdown(eventPicker, "on enter combat");
    H.assertFalse(detailPicker:IsShown() or detail2Picker:IsShown(), "combat has no detail");
    H.assertTrue(GqUiFrameBindingForm.Warning:GetText():find("WARNING!"), "combat warning");
    H.assertTrue(GqUiFrameBindingForm.Error:GetText():find("Set does not match conditions."), "DPS is no weapon set");
    H.assertFalse(GqUiFrameBindingForm_BtnAdd:IsEnabled());
    GqUiFrameBindingForm_BtnCancel:Click("LeftButton");
    H.assertFalse(form:IsShown(), "cancelled");
    H.assertEq(#gq:LoadEventBindings(), 1, "nothing added");

    -- a spec binding, PvE only
    GqAddEventBinding:Click("LeftButton");
    H.pickDropdown(eventPicker, "on talents change");
    H.assertEq(H.dropdownText(detailPicker), "< choose talents >");
    H.assertFalse(GqUiFrameBindingForm.Warning:GetText(), "no combat warning any more");
    H.pickDropdown(detailPicker, gq:GetTalentSpecializations()[1]);
    H.pickDropdown(setPicker, "DPS");
    GqUiFrameBindingForm_CbPVP:Click("LeftButton");
    H.assertTrue(GqUiFrameBindingForm_BtnAdd:IsEnabled(), "PvE alone is enough");
    GqUiFrameBindingForm_CbPVE:Click("LeftButton");
    H.assertFalse(GqUiFrameBindingForm_BtnAdd:IsEnabled(), "needs PvE or PvP");
    GqUiFrameBindingForm_CbPVE:Click("LeftButton");
    GqUiFrameBindingForm_BtnAdd:Click("LeftButton");
    bindings = gq:LoadEventBindings();
    H.assertEq(#bindings, 2);
    H.assertTrue(bindings[2][gq.FIELD_PVE] and not bindings[2][gq.FIELD_PVP], "PvE only");
    H.assertEq(bindings[2][gq.FIELD_SUBTYPE].spellId, 1, "spec group 1");
    row = panel.bindingRow(2);
    H.assertEq(row.Event:GetText(), "On talents change: " .. gq:GetTalentSpecializations()[1]);
    H.assertEq(row.Info:GetText(), "PvE");
    panel.tab("Sets");
    H.assertEq(panel.setRow("DPS").SpecText:GetText(), "1", "spec badge on the bound set");
    H.assertFalse(panel.setRow("Tank").SpecBadge:IsShown());
    panel.tab("Events");

    -- the row's set picker saves the binding (through SaveEventBinding: listeners are told)
    local saved = {};
    gq:RegisterEventListener(GQ_EVENT_EVENT_BINDING_SAVED, function(listener, setName)
        saved[#saved + 1] = setName;
    end);
    H.pickDropdown(panel.bindingRow(1).SetPicker, "DPS");
    H.assertEq(gq:LoadEventBindings()[1][gq.FIELD_NAME], "DPS", "picker saved");
    H.assertEq(saved[#saved], "DPS", "saved through SaveEventBinding");
    H.assertEq(H.dropdownText(panel.bindingRow(1).SetPicker), "DPS");
    H.pickDropdown(panel.bindingRow(1).SetPicker, "[Previous set]");
    H.assertEq(gq:LoadEventBindings()[1][gq.FIELD_NAME], gq.KEYWORD_PREVIOUS, "keyword saved");
    H.assertEq(H.dropdownText(panel.bindingRow(1).SetPicker), "[Previous set]");
    H.pickDropdown(panel.bindingRow(2).SetPicker, "Tank");
    panel.tab("Sets");
    H.assertEq(panel.setRow("Tank").SpecText:GetText(), "1", "badge follows the picker");
    H.assertFalse(panel.setRow("DPS").SpecBadge:IsShown(), "and leaves DPS");
    panel.tab("Events");

    -- switching: pickers, delete and Add disabled; the box keeps showing the option
    H.assertTrue(controlsEnabled(panel), "controls enabled");
    gq:QueueSwitch("DPS");
    H.assertTrue(gq:IsSwitching());
    H.assertTrue(controlsDisabled(panel), "disabled while switching");
    H.assertTrue(GqUiFrame_CbEnableEvents:GetChecked(), "box still shows events on");
    H.advance(3);
    H.assertWearing(H.SET_B, "switched");
    H.assertTrue(controlsEnabled(panel) and GqAddEventBinding:IsEnabled(), "enabled after the switch");

    -- events off: everything disabled, also inside an open form
    GqUiFrame_CbEnableEvents:Click("LeftButton");
    H.assertTrue(controlsDisabled(panel), "disabled with events off");
    H.assertFalse(pcall(H.openDropdown, panel.bindingRow(1).SetPicker), "a disabled picker does not open");
    GqUiFrame_CbEnableEvents:Click("LeftButton");
    GqAddEventBinding:Click("LeftButton");
    H.pickDropdown(eventPicker, "on mount");
    H.pickDropdown(setPicker, "Tank");
    H.assertTrue(GqUiFrameBindingForm_BtnAdd:IsEnabled());
    H.slash("/gq toggleevents");
    H.assertFalse(eventPicker:IsEnabled() or setPicker:IsEnabled(), "form pickers disabled with events off");
    H.assertFalse(GqUiFrameBindingForm_BtnAdd:IsEnabled() or GqUiFrameBindingForm_CbPVE:IsEnabled());
    H.assertTrue(GqUiFrameBindingForm_BtnCancel:IsEnabled(), "Cancel always works");
    H.slash("/gq toggleevents");
    H.assertTrue(eventPicker:IsEnabled() and GqUiFrameBindingForm_BtnAdd:IsEnabled(), "form usable again");
    GqUiFrameBindingForm_BtnAdd:Click("LeftButton");
    H.assertEq(#gq:LoadEventBindings(), 3, "mount binding added");

    -- combat: Add binding disabled, re-enabled after combat
    H.setCombat(true);
    H.advance(0.2);
    H.assertTrue(controlsDisabled(panel), "disabled in combat");
    H.setCombat(false);
    H.advance(0.5);
    H.assertTrue(GqAddEventBinding:IsEnabled() and controlsEnabled(panel), "enabled after combat");

    -- delete the first binding: the rows move up
    panel.bindingRow(1).Delete:Click("LeftButton");
    bindings = gq:LoadEventBindings();
    H.assertEq(#bindings, 2, "deleted");
    H.assertEq(bindings[1][gq.FIELD_TYPE], gq.EVENT_TALENTS_CHANGED, "the next binding moved up");
    H.assertEq(#panel.bindingRows(), 2);
    H.assertEq(panel.bindingRow(1).Event:GetText(), "On talents change: " .. gq:GetTalentSpecializations()[1]);
    H.assertEq(H.dropdownText(panel.bindingRow(1).SetPicker), "Tank", "the recycled row shows its own binding");

    -- a binding of an event this version does not know
    table.insert(gq:LoadEventBindings(), {[gq.FIELD_TYPE] = "EVENT_GONE", [gq.FIELD_NAME] = "Tank"});
    gq:RefreshEventEntries();
    row = panel.bindingRow(3);
    H.assertEq(row.Event:GetText(), "Deprecated event");
    H.assertFalse(row.SetPicker:IsShown(), "no picker for it");
    H.assertTrue(row.Delete:IsEnabled(), "but it can be deleted");
    row.Delete:Click("LeftButton");
    H.assertEq(#gq:LoadEventBindings(), 2);

    -- removing a set removes its bindings from the list
    panel.tab("Sets");
    panel.openMenu(panel.setRow("Tank"));
    H.clickMenuEntry("Delete...");
    H.acceptPopup();
    panel.tab("Events");
    H.assertEq(#panel.bindingRows(), 0, "Tank's bindings gone");
    H.assertTrue(GqUiFrameBindingList:IsVisible(), "list");
    panel.close();
    H.assertNoUiErrors();
end
