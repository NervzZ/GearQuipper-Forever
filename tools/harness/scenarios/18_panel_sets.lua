-- (r) The panel's Sets tab (stock look, no UI suite): Blizzard gear-set cards in a WowScrollBoxList; left-click
-- equips (rows locked and dimmed while switching), the tick follows the current set, a red tag for missing items,
-- hover dims slots and shows the missing items, the right-click menu (equip, save, partial -> slot boxes, bank
-- entries only at the bank, delete with its popup), a switch or combat closes an open set menu and its entries do
-- nothing while locked, inline bank buttons at the bank, the scroll position kept by refreshes, recycled rows without
-- stale state, the data broker's menu (closed at the end of a switch); relog: the last tab is remembered.

-- every row shows exactly its own set's state (catches stale state on recycled frames)
local function assertRowsConsistent(H, gq, panel, msg)
    local current, atBank = gq:LoadCurrentSetName(), gq:IsAtBank() == true;
    for _, row in ipairs(panel.setRows()) do
        local name = row:GetElementData().setName;
        local where = (msg or "") .. " [" .. name .. "]";
        H.assertEq(row.Name:GetText(), name, where .. " name");
        H.assertEq(row.Tick:IsShown(), name == current, where .. " tick");
        H.assertEq(row.SelectedBar:IsShown(), name == current, where .. " selected card");
        H.assertTrue(row.Card:IsShown(), where .. " stock card");
        H.assertFalse(row.FlatSelected:IsShown() or row.FlatHover:IsShown(), where .. " no flat bars without a skin");
        H.assertFalse(row.HighlightBar:IsShown(), where .. " no stale hover");
        H.assertEq(row.Partial:IsShown(), gq:LoadPartialOption(name) == true, where .. " partial tag");
        H.assertEq(row.ToBank:IsShown(), atBank, where .. " bank buttons");
        H.assertEq(row:GetAlpha(), 1, where .. " not dimmed");
        H.assertTrue(row:IsEnabled(), where .. " enabled");
        local r, g, b = row.Name:GetTextColor();
        H.assertTrue(r == 1 and g == 0.82 and b == 0, where .. " gold name (no set colour), never red");
        H.assertEq(row.Missing:IsShown(), not gq:IsSetAvailable(name),
            where .. " missing tag only when items are missing");
    end
end

local function iconOf(gq, setName, slot)
    return (select(5, C_Item.GetItemInfoInstant(gq:LoadSlot(slot, setName))));
end

return {
    run = function(H, gq)
        local panel = H.include("helpers/gq_panel.lua");
        H.advance(1);
        gq:SaveSet("Tank", false);
        H.wearSetBPieces();
        gq:SaveSet("DPS", false);
        -- a set without weapons shows its chest; one without items the question mark
        gq:SaveSet("Chest", false);
        gq:SaveSlot(16, "Chest", false, gq.VALUE_NONE);
        gq:SaveSet("Bare", false);
        for slot = 1, 19 do
            gq:SaveSlot(slot, "Bare", false, gq.VALUE_NONE);
        end
        -- a set with an item the character does not own
        gq:SaveSet("Lost", false);
        gq:SaveSlot(11, "Lost", false, gq:GetItemString(H.itemLink(H.newItem("uniqueRing"))));
        H.switchTo(gq, "Tank");
        H.assertWearing(H.SET_A, "start");

        panel.open();
        H.assertEq(table.concat(panel.setNames(), ","), table.concat(gq:LoadSetNames(), ","), "a row per set, sorted");
        H.assertFalse(GqUiFrameSetListScrollBar:IsShown(), "no scroll bar while every row fits");
        assertRowsConsistent(H, gq, panel, "open");
        H.assertEq(panel.setRow("Tank").Card:GetAtlas(), "UI-Character-Info-OutfitCard", "Blizzard card art");
        H.assertEq(panel.setRow("Tank").IconBorder:GetAtlas(), "UI-Character-Info-OutfitIcon-Frame");
        H.assertEq(panel.setRow("Tank").Tick:GetAtlas(), "UI-Character-Info-Icon-Tick");
        H.assertEq(panel.setRow("Tank").Icon:GetTexture(), iconOf(gq, "Tank", 16), "icon: main hand");
        H.assertEq(panel.setRow("DPS").Icon:GetTexture(), iconOf(gq, "DPS", 16), "DPS: its greatsword");
        H.assertEq(panel.setRow("Chest").Icon:GetTexture(), iconOf(gq, "Chest", 5), "no weapon: the chest");
        H.assertEq(panel.setRow("Bare").Icon:GetTexture(), "Interface\\Icons\\INV_Misc_QuestionMark", "no items");
        local r, g, b = panel.setRow("Lost").Name:GetTextColor();
        H.assertTrue(r == 1 and g == 0.82 and b == 0, "missing items: the name keeps its colour");
        H.assertTrue(panel.setRow("Lost").Missing:IsShown(), "missing items: red tag");
        H.assertEq(panel.setRow("Lost").Missing:GetText(), "missing");
        r, g, b = panel.setRow("Lost").Missing:GetTextColor();
        H.assertTrue(r == 1 and g < 0.2 and b < 0.2, "the tag is red");
        H.assertEq(GqUiFrameStatusText:GetText(), "Current set: Tank", "status line");
        H.assertTrue(GqUiFrame_BtnSaveSet:IsEnabled() and GqAddSetButton:IsEnabled(), "footer buttons");

        -- hover: the set's worn items stay bright, the rest dims; missing items listed; all restored on leave
        local lost = panel.setRow("Lost");
        H.mouseEnter(lost);
        H.assertTrue(lost.HighlightBar:IsShown(), "hover card");
        H.assertEq(CharacterNeckSlot.icon:GetAlpha(), 1, "Lost's neck (shared with Tank) is worn");
        H.assertEq(CharacterHeadSlot.icon:GetAlpha(), 0.35, "its DPS helm is not worn: dimmed");
        H.assertEq(CharacterFinger0Slot.icon:GetAlpha(), 0.35, "its missing ring: dimmed");
        H.assertTrue(GQ_Tooltip_1 and GQ_Tooltip_1:IsShown(), "missing items tooltip");
        H.assertEq(GqUiFrameStatusText:GetText(), "Left-click: equip. Right-click: more.", "hint while hovering");
        r, g, b = lost.Name:GetTextColor();
        H.assertTrue(r == 1 and g == 1 and b == 1, "hovered name white");
        H.mouseLeave(lost);
        H.assertEq(CharacterFinger0Slot.icon:GetAlpha(), 1, "slots restored");
        H.assertFalse(GQ_Tooltip_1:IsShown(), "tooltip hidden");
        r, g, b = lost.Name:GetTextColor();
        H.assertTrue(r == 1 and g == 0.82 and b == 0, "gold again after hover");
        H.assertTrue(lost.Missing:IsShown(), "tag stays");
        H.assertFalse(lost.HighlightBar:IsShown());
        H.assertEq(GqUiFrameStatusText:GetText(), "Current set: Tank");

        -- left-click equips; while switching every row is disabled, the others dimmed, the buttons disabled
        panel.setRow("DPS"):Click("LeftButton");
        H.assertTrue(gq:IsSwitching(), "switch started");
        for _, row in ipairs(panel.setRows()) do
            local isTarget = row:GetElementData().setName == "DPS";
            H.assertFalse(row:IsEnabled(), "rows disabled while switching");
            H.assertEq(row:GetAlpha(), isTarget and 1 or 0.5, "only the target stays bright");
        end
        H.assertFalse(GqUiFrame_BtnSaveSet:IsEnabled() or GqAddSetButton:IsEnabled(), "buttons locked");
        H.assertFalse(GQ_PaperDollButton:IsEnabled(), "GQ button locked");
        H.advance(3);
        H.assertWearing(H.SET_B, "row click equipped DPS");
        H.assertEq(gq:LoadCurrentSetName(), "DPS");
        assertRowsConsistent(H, gq, panel, "after the switch");
        H.assertTrue(GqUiFrame_BtnSaveSet:IsEnabled() and GQ_PaperDollButton:IsEnabled(), "unlocked");

        -- right-click menu of the current set; Partial (checkbox) shows the slot boxes
        local entries = panel.openMenu(panel.setRow("DPS"));
        local texts = {};
        for _, e in ipairs(entries) do
            texts[#texts + 1] = e.divider and "-" or e.text;
        end
        H.assertEq(table.concat(texts, "|"), "DPS|Equip|Save worn gear into this set|Partial set|Colour|-|" ..
            "Put in bank|Take from bank|-|Delete...", "menu entries");
        H.assertTrue(panel.menuEntry(entries, "DPS").title, "set name as title");
        H.assertTrue(panel.menuEntry(entries, "Partial set").checkbox, "partial is a checkbox");
        H.assertTrue(panel.menuEntry(entries, "Partial set").enabled, "enabled for the current set");
        H.assertFalse(panel.menuEntry(entries, "Put in bank").enabled, "bank entries disabled away from the bank");
        H.assertFalse(panel.menuEntry(entries, "Take from bank").enabled);
        H.clickMenuEntry("Partial set");
        H.assertTrue(gq:LoadPartialOption("DPS"), "partial saved");
        H.assertTrue(HeadSlotStateBox and HeadSlotStateBox:IsShown(), "slot boxes shown");
        H.assertTrue(panel.setRow("DPS").Partial:IsShown(), "partial tag");
        H.assertTrue(panel.menuEntry(H.menuEntries(), "Partial set").selected, "menu stays open, ticked");
        H.clickMenuEntry("Partial set");
        H.assertFalse(gq:LoadPartialOption("DPS"), "partial off");
        H.assertFalse(HeadSlotStateBox:IsShown(), "slot boxes hidden");
        H.closeMenus();
        assertRowsConsistent(H, gq, panel, "after partial");

        -- other sets: partial is the current set's thing; Equip from the menu
        entries = panel.openMenu(panel.setRow("Tank"));
        H.assertFalse(panel.menuEntry(entries, "Partial set").enabled, "partial only for the current set");
        H.clickMenuEntry("Equip");
        H.advance(3);
        H.assertWearing(H.SET_A, "menu Equip");
        H.assertFalse(H.menuEntries(), "menu closed after Equip");

        -- a switch that starts while a set's menu is open (event binding, macro, broker) closes the menu, and an
        -- entry that a click still reaches does nothing while the panel is locked: no half-swapped gear saved
        entries = panel.openMenu(panel.setRow("Tank"));
        local staleEntries = {};
        for _, text in ipairs({"Save worn gear into this set", "Partial set", "Delete...", "Equip"}) do
            staleEntries[#staleEntries + 1] = panel.menuEntry(entries, text).description;
        end
        local tankBefore = {};
        for slot = 1, 19 do
            tankBefore[slot] = gq:LoadSlot(slot, "Tank");
        end
        H.clearChat();
        local popupCount = #H.popups;
        gq:QueueSwitch("DPS");
        H.assertTrue(gq:IsSwitching() and gq:IsUiLocked(), "a switch locks the panel");
        H.assertFalse(H.menuEntries(), "the lock closes the set menu");
        for _, description in ipairs(staleEntries) do
            description:Pick(MenuInputContext.MouseButton, "LeftButton");
        end
        H.assertNoChat("has been saved", "nothing saved while switching");
        H.assertFalse(gq:LoadPartialOption("Tank"), "partial unchanged while locked");
        H.assertEq(#H.popups, popupCount, "no delete popup while locked");
        H.advance(3);
        H.assertWearing(H.SET_B, "only the started switch ran (no Equip queued from the menu)");
        H.assertEq(gq:LoadCurrentSetName(), "DPS");
        for slot = 1, 19 do
            H.assertEq(gq:LoadSlot(slot, "Tank"), tankBefore[slot], "Tank kept its gear, slot " .. slot);
        end
        -- combat locks the panel too: the set menu closes; the broker's menu (it only switches) stays usable
        panel.openMenu(panel.setRow("Tank"));
        H.setCombat(true);
        H.assertFalse(H.menuEntries(), "combat closes the set menu");
        H.setCombat(false);
        LibStub("LibDataBroker-1.1"):GetDataObjectByName("GearQuipper").OnClick(UIParent, "RightButton");
        H.setCombat(true);
        H.assertTrue(H.menuEntries(), "the broker menu stays open in combat");
        H.closeMenus();
        H.setCombat(false);
        H.switchTo(gq, "Tank");
        H.assertWearing(H.SET_A, "back to Tank");

        -- "Save worn gear into this set" on another set: it takes the worn gear and becomes current
        panel.openMenu(panel.setRow("Bare"));
        H.clickMenuEntry("Save worn gear into this set");
        H.advance(0.5);
        H.assertSetMatchesGear(gq, "Bare", "saved worn gear");
        H.assertEq(gq:LoadCurrentSetName(), "Bare");
        H.assertEq(panel.setRow("Bare").Icon:GetTexture(), iconOf(gq, "Tank", 16), "icon follows the saved gear");
        assertRowsConsistent(H, gq, panel, "after save");

        -- Save (footer) saves the worn gear into the current set
        gq:SaveSlot(1, "Bare", false, gq.VALUE_NONE);
        GqUiFrame_BtnSaveSet:Click("LeftButton");
        H.assertEq(gq:LoadSlot(1, "Bare"), gq:GetItemString(1), "footer Save");

        -- bank: entries and inline buttons only at the bank
        H.switchTo(gq, "Tank");
        H.openBank();
        H.advance(1);
        assertRowsConsistent(H, gq, panel, "at the bank");
        H.assertEq(panel.setRow("DPS").ToBank:GetText(), "-> Bank");
        entries = panel.openMenu(panel.setRow("DPS"));
        H.assertTrue(panel.menuEntry(entries, "Put in bank").enabled, "bank entries enabled at the bank");
        H.clickMenuEntry("Put in bank");
        H.advance(3);
        H.assertInBank("headB", "menu pushed DPS");
        H.assertInBank("greatsword");
        panel.setRow("DPS").ToBags:Click("LeftButton");
        H.advance(3);
        H.assertInBags("headB", 1, "inline button pulled DPS back");
        panel.setRow("DPS").ToBank:Click("LeftButton");
        H.advance(3);
        H.assertInBank("headB", "inline button pushed DPS");
        entries = panel.openMenu(panel.setRow("DPS"));
        H.clickMenuEntry("Take from bank");
        H.advance(3);
        H.assertInBags("headB", 1, "menu pulled DPS");
        H.closeBank();
        H.advance(1);
        assertRowsConsistent(H, gq, panel, "bank closed");

        -- delete through the menu and its popup; the frames move up without the old state
        local framesBefore = panel.setRows();
        local bareIndex;
        for i, row in ipairs(framesBefore) do
            if row:GetElementData().setName == "Bare" then
                bareIndex = i;
            end
        end
        panel.openMenu(panel.setRow("Bare"));
        H.clickMenuEntry("Delete...");
        H.assertEq(H.popups[#H.popups].which, "GQ_DIALOG_REMOVESET", "delete asks first");
        H.assertTrue(gq:TableContains(gq:LoadSetNames(), "Bare"), "not deleted before the answer");
        H.acceptPopup();
        H.advance(0.2);
        H.assertFalse(gq:TableContains(gq:LoadSetNames(), "Bare"), "deleted");
        H.assertFalse(panel.setRow("Bare"), "row gone");
        local framesAfter = panel.setRows();
        H.assertEq(#framesAfter, #framesBefore - 1);
        H.assertTrue(framesAfter[bareIndex] == framesBefore[bareIndex], "the frame is recycled for the next set");
        H.assertTrue(framesAfter[bareIndex]:GetElementData().setName ~= "Bare");
        assertRowsConsistent(H, gq, panel, "after delete");

        -- deleting the current set leaves none: Save is disabled until a set is current again
        GqAddSetButton:Click("LeftButton");
        H.acceptPopup("Temp");
        H.advance(0.2);
        H.assertTrue(panel.setRow("Temp").Tick:IsShown(), "a new set becomes current");
        panel.openMenu(panel.setRow("Temp"));
        H.clickMenuEntry("Delete...");
        H.acceptPopup();
        H.advance(0.2);
        H.assertEq(gq:LoadCurrentSetName(), nil, "no current set");
        H.assertFalse(GqUiFrame_BtnSaveSet:IsEnabled(), "Save needs a current set");
        H.assertTrue(GqUiFrame_BtnSaveSet:IsShown(), "but stays in place");
        H.assertEq(GqUiFrameStatusText:GetText(), "Current set: " .. UNKNOWN);
        assertRowsConsistent(H, gq, panel, "no current set");
        H.switchTo(gq, "Tank");
        H.assertTrue(GqUiFrame_BtnSaveSet:IsEnabled(), "Save back with a current set");

        -- many sets: the list scrolls; refreshes keep the position, scrollIntoView brings the current set
        for i = 1, 12 do
            gq:SaveSet(string.format("S%02d", i), false);
        end
        H.switchTo(gq, "Tank");
        H.assertTrue(GqUiFrameSetListScrollBar:IsShown(), "scroll bar once the rows overflow");
        GqUiFrameSetList:ScrollToBegin();
        gq:RefreshSetList();
        H.assertEq(GqUiFrameSetList:GetScrollPercentage(), 0, "plain refresh keeps the top");
        gq:RefreshSetList(true);
        local percentage = GqUiFrameSetList:GetScrollPercentage();
        H.assertTrue(percentage > 0, "scrollIntoView scrolls down to Tank (last)");
        H.scrollStep(GqUiFrameSetListScrollBar, "Back");
        percentage = GqUiFrameSetList:GetScrollPercentage();
        H.assertTrue(percentage > 0 and percentage < 1, "scrolled to the middle");
        gq:RefreshSetList();
        H.assertEq(GqUiFrameSetList:GetScrollPercentage(), percentage, "kept by a refresh");
        H.fire("ITEM_UNLOCKED", 0, 1);
        H.advance(0.2);
        H.assertEq(GqUiFrameSetList:GetScrollPercentage(), percentage, "kept by an inventory refresh");
        assertRowsConsistent(H, gq, panel, "scrolled");

        -- the data broker's right-click menu (MenuUtil, no legacy dropdown)
        local ldb = LibStub("LibDataBroker-1.1"):GetDataObjectByName("GearQuipper");
        H.assertFalse(rawget(_G, "GearQuipper_Broker_DropDownMenu"), "no legacy dropdown holder");
        ldb.OnClick(UIParent, "RightButton");
        entries = H.menuEntries();
        H.assertEq(entries[1].text, "Switch to set:", "broker title");
        H.assertTrue(panel.menuEntry(entries, "Tank").radio and panel.menuEntry(entries, "Tank").selected,
            "current set ticked");
        H.assertEq(#entries, #gq:LoadSetNames() + 1, "every set");
        H.clickMenuEntry("DPS");
        H.assertTrue(gq:IsSwitching(), "broker switch started");
        ldb.OnClick(UIParent, "RightButton");
        H.assertEq(H.menuEntries()[1].text, "- Currently Switching -", "busy title while switching");
        H.advance(3);
        H.assertWearing(H.SET_B, "broker switched to DPS");
        H.assertFalse(H.menuEntries(), "the end of the switch closes the stale broker menu");
        -- another addon's menu replaces GQ's: GQ forgets its closed menu (menu frames are pooled, a late Close could
        -- hit the other menu) and leaves the other one open
        ldb.OnClick(UIParent, "RightButton");
        local gqMenu = H.menus.open;
        MenuUtil.CreateContextMenu(UIParent, function(_, root)
            root:CreateButton("Other addon", function() end);
        end);
        local staleClose = false;
        gqMenu.Close = function()
            staleClose = true;
        end;
        H.switchTo(gq, "Tank");
        H.assertFalse(staleClose, "no Close on GQ's closed menu");
        H.assertTrue(H.menuEntries(), "another addon's menu survives the end of a switch");
        H.closeMenus();
        H.switchTo(gq, "DPS");

        -- the Events tab is remembered for the next session
        panel.tab("Events");
        H.assertEq(GQ_OPTIONS[gq.OPT_PANELTAB], "EVENTS");
        H.assertTrue(GqUiFrameEventsPage:IsVisible() and not GqUiFrameSetsPage:IsShown(), "events page shown");
        panel.close();
        H.assertCursorEmpty();
        H.assertNoUiErrors();
    end,
    relog = function(H, gq)
        local panel = H.include("helpers/gq_panel.lua");
        H.advance(1);
        H.openCharacterFrame();
        H.advance(0.5);
        H.assertTrue(GqUiFrame:IsVisible(), "the panel reopens with the sheet");
        H.assertEq(panel.selectedTab(), "Events", "on the remembered tab");
        H.assertTrue(GqUiFrameEventsPage:IsVisible() and not GqUiFrameSetsPage:IsShown());
        panel.tab("Sets");
        H.assertEq(GQ_OPTIONS[gq.OPT_PANELTAB], "SETS");
        H.assertTrue(GqUiFrameSetsPage:IsVisible() and not GqUiFrameEventsPage:IsShown());
        H.assertTrue(panel.setRow("DPS").Tick:IsShown(), "DPS still current");
        panel.close();
    end,
};
