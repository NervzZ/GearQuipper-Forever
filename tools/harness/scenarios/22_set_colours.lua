-- (r) Per-set colours. The set menu's "Colour" submenu: palette radios (each name in its colour; no red, no gold, no
-- item-quality colour), "Custom..." (colour picker with live preview; Cancel, Escape and a click outside put the old
-- colour back, Okay keeps the new one) and "None"; entries do nothing while the panel is locked. The colour shows on
-- the set row (gold without one, white while hovered; missing items add a red tag instead of a red name), in the item
-- tooltip's set line for bag AND worn items ("Expected Item" kept), on the paper-doll label (only the name; the prefix
-- keeps its state colour), in the data broker (text, tooltip, menu) and the menu title. SaveSet keeps the colour,
-- deleting the set drops it, the previous-equipment set and invalid stored values never colour anything.
-- Relog: the colours persist.

local SKY, MINT, PINK = "66b3ff", "7ff0a8", "ff85c8";

local function sets(gq)
    return GQ_DATA[gq:GetRealmName()][gq:GetCharName()].FIELD_SETS;
end

local function hexOf(r, g, b)
    return string.format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5));
end

local function rgbOf(hex)
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255;
end

local function distance(hexA, hexB)
    local r1, g1, b1 = rgbOf(hexA);
    local r2, g2, b2 = rgbOf(hexB);
    return math.sqrt((r1 - r2) ^ 2 + (g1 - g2) ^ 2 + (b1 - b2) ^ 2);
end

local function nameHex(row)
    return hexOf(row.Name:GetTextColor());
end

local GOLD = hexOf(1, 0.82, 0);

-- right text of the tooltip line whose left text is `left`, and the line index
local function tooltipLine(left)
    for i = 1, GameTooltip:NumLines() do
        if _G["GameTooltipTextLeft" .. i]:GetText() == left then
            return _G["GameTooltipTextRight" .. i]:GetText(), i;
        end
    end
end

local function tooltipTexts()
    local texts = {};
    for i = 1, GameTooltip:NumLines() do
        texts[i] = _G["GameTooltipTextLeft" .. i]:GetText() or "";
    end
    return texts;
end

local function hoverWorn(H, slotButton)
    H.mouseEnter(slotButton);
    H.advance(0.05);
end

local function leaveWorn(H, slotButton)
    H.mouseLeave(slotButton);
    GameTooltip:Hide();
    H.advance(0.3);
end

local function hoverBag(H, itemKey)
    for _, loc in ipairs(H.find(itemKey)) do
        if loc.kind == "bag" then
            H.hoverBagItem(loc.bag, loc.slot);
            return;
        end
    end
    error("not in the bags: " .. itemKey, 2);
end

-- the "Colour" submenu of a set row: entries by plain text
local function colourMenu(H, gq, panel, setName)
    local entries = panel.openMenu(panel.setRow(setName));
    local colour = panel.menuEntry(entries, "Colour");
    H.assertTrue(colour and colour.submenu, "Colour submenu");
    local list = {};
    for _, d in colour.description:EnumerateElementDescriptions() do
        local text = MenuUtil.GetElementText(d);
        list[#list + 1] = {text = text, plain = text and text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""),
            description = d, selected = d:IsSelected(), radio = d:IsRadio(), enabled = d:IsEnabled(),
            divider = d.isDivider == true};
    end
    return list, entries;
end

local function entryByPlain(list, plain)
    for _, e in ipairs(list) do
        if e.plain == plain then
            return e;
        end
    end
end

local function pickColour(H, gq, panel, setName, plain)
    local list = colourMenu(H, gq, panel, setName);
    local entry = entryByPlain(list, plain);
    H.assertTrue(entry, "colour entry " .. plain);
    H.clickMenuEntry("Colour", entry.text);
end

local function ldb()
    return LibStub("LibDataBroker-1.1"):GetDataObjectByName("GearQuipper");
end

local function brokerTooltip()
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE");
    ldb().OnTooltipShow(GameTooltip);
    return tooltipTexts();
end

-- the label shows <prefix>Current set: "<|cff..name|r><prefix>"
local function assertLabel(H, gq, setName, hex, msg)
    local text = GQ_PaperDollLabel.text:GetText();
    local prefix = text:match("^(|cff%x%x%x%x%x%x)");
    H.assertTrue(prefix, msg .. ": label starts with its state colour");
    if hex then
        H.assertEq(text, prefix .. "Current set: \"|cff" .. hex .. setName .. "|r" .. prefix .. "\"", msg);
    else
        H.assertEq(text, prefix .. "Current set: \"" .. setName .. "\"", msg);
    end
    return prefix;
end

return {
    run = function(H, gq)
        local panel = H.include("helpers/gq_panel.lua");
        H.advance(1);
        gq:SaveSet("Tank", false);
        gq:SaveSet("Lost", false);
        gq:SaveSlot(11, "Lost", false, gq:GetItemString(H.itemLink(H.newItem("uniqueRing"))));
        H.wearSetBPieces();
        gq:SaveSet("DPS", false);
        H.switchTo(gq, "Tank");
        H.assertWearing(H.SET_A, "start");

        -- palette: about 8 light colours, distinct, none red, gold or an item-quality colour
        local palette = gq:GetSetColorPalette();
        H.assertTrue(#palette >= 6 and #palette <= 10, "about 8 palette colours");
        local avoid = {red = "ff0000", redFont = "ff1a1a", redTag = "ff2020", gold = "ffd100", goldLabel = "ffcc00"};
        for q, argb in pairs(H.QUALITY_HEX) do
            avoid["quality" .. q] = argb:sub(3);
        end
        for i, entry in ipairs(palette) do
            H.assertTrue(entry.hex:match("^%x%x%x%x%x%x$") and entry.name ~= "", "palette entry " .. i);
            for what, hex in pairs(avoid) do
                H.assertTrue(distance(entry.hex, hex) > 0.2, entry.name .. " is not " .. what);
            end
            for j = i + 1, #palette do
                H.assertTrue(distance(entry.hex, palette[j].hex) > 0.2, entry.name .. " vs " .. palette[j].name);
            end
            local r, g, b = rgbOf(entry.hex);
            H.assertTrue(0.2126 * r + 0.7152 * g + 0.0722 * b > 0.45, entry.name .. " reads on a dark tooltip");
        end

        -- API: no colour yet; invalid input refused; the previous-equipment set never takes one
        H.assertEq(gq:LoadSetColor("Tank"), nil);
        H.assertEq(gq:ColorizeSetName("Tank"), "Tank", "plain name without a colour");
        H.assertEq(gq:GetSetColorRGB("Tank"), nil);
        H.assertFalse(gq:SaveSetColor("Tank", "zzzzzz"), "invalid hex refused");
        H.assertFalse(gq:SaveSetColor("Tank", "#66b3ff"), "only rrggbb");
        H.assertFalse(gq:SaveSetColor("Nope", SKY), "unknown set refused");
        H.assertEq(gq:LoadSetColor("Tank"), nil);
        local previous = gq.KEYWORD_PREVIOUSEQUIPMENT;
        gq:CreatePreviousEquipmentSet();
        H.assertTrue(sets(gq)[previous], "previous-equipment set exists");
        H.assertFalse(gq:SaveSetColor(previous, SKY), "previous-equipment set refused");
        sets(gq)[previous].FIELD_COLOR = SKY;
        H.assertEq(gq:LoadSetColor(previous), nil, "previous-equipment set never coloured");
        H.assertEq(gq:ColorizeSetName(previous), previous);
        sets(gq)[previous].FIELD_COLOR = nil;
        H.assertTrue(gq:SaveSetColor("Tank", "66B3FF"), "upper case accepted");
        H.assertEq(sets(gq).Tank.FIELD_COLOR, SKY, "stored lower case");
        H.assertEq(gq:ColorizeSetName("Tank"), "|cff" .. SKY .. "Tank|r");
        local r, g, b = gq:GetSetColorRGB("Tank");
        H.assertEq(hexOf(r, g, b), SKY, "RGB");
        H.assertTrue(gq:SaveSetColor("Tank", nil), "nil clears");
        H.assertEq(sets(gq).Tank.FIELD_COLOR, nil);
        for _, bad in ipairs({"red", "12345", 123456, true}) do
            sets(gq).Tank.FIELD_COLOR = bad;
            H.assertEq(gq:LoadSetColor("Tank"), nil, "invalid stored value ignored: " .. tostring(bad));
            H.assertEq(gq:ColorizeSetName("Tank"), "Tank");
        end
        sets(gq).Tank.FIELD_COLOR = nil;

        -- the submenu: palette radios in their colours, a divider, Custom..., None (selected)
        panel.open();
        H.assertEq(nameHex(panel.setRow("DPS")), GOLD, "gold without a colour");
        local list = colourMenu(H, gq, panel, "DPS");
        H.assertEq(#list, #palette + 3, "palette + divider + Custom + None");
        for i, entry in ipairs(palette) do
            H.assertEq(list[i].text, "|cff" .. entry.hex .. entry.name .. "|r", "entry in its colour");
            H.assertTrue(list[i].radio and not list[i].selected, entry.name .. " radio, not selected");
        end
        H.assertTrue(list[#palette + 1].divider, "divider before Custom");
        H.assertEq(list[#palette + 2].text, "Custom...");
        H.assertTrue(list[#palette + 2].enabled and not list[#palette + 2].selected, "Custom enabled");
        H.assertEq(list[#palette + 3].text, "None");
        H.assertTrue(list[#palette + 3].selected, "None selected");

        -- pick Sky: stored, the menu closes, the row shows it; reopened, Sky is ticked and the title coloured
        pickColour(H, gq, panel, "DPS", "Sky");
        H.assertEq(gq:LoadSetColor("DPS"), SKY, "Sky saved");
        H.assertFalse(H.menuEntries(), "a colour pick closes the menu");
        H.assertEq(nameHex(panel.setRow("DPS")), SKY, "row in Sky");
        H.assertEq(nameHex(panel.setRow("Tank")), GOLD, "other rows unchanged");
        local entries;
        list, entries = colourMenu(H, gq, panel, "DPS");
        H.assertTrue(entryByPlain(list, "Sky").selected and not entryByPlain(list, "None").selected, "Sky ticked");
        H.assertEq(entries[1].text, "|cff" .. SKY .. "DPS|r", "menu title in the set colour");
        H.closeMenus();

        -- hover: white; leave: the set colour again
        local dpsRow = panel.setRow("DPS");
        H.mouseEnter(dpsRow);
        H.assertEq(nameHex(dpsRow), "ffffff", "hovered name white");
        H.mouseLeave(dpsRow);
        H.assertEq(nameHex(dpsRow), SKY, "set colour after hover");

        -- missing items: the name keeps its colour, a red tag tells
        pickColour(H, gq, panel, "Lost", "Pink");
        local lostRow = panel.setRow("Lost");
        H.assertEq(nameHex(lostRow), PINK, "Lost in Pink despite missing items");
        H.assertTrue(lostRow.Missing:IsShown() and lostRow.Missing:GetText() == "missing", "missing tag");
        r = lostRow.Missing:GetTextColor();
        H.assertEq(r, 1);
        H.assertFalse(dpsRow.Missing:IsShown(), "no tag on a set with every item");

        -- Tank (current set) in Mint: the label colours only the name, the prefix keeps its state colour
        assertLabel(H, gq, "Tank", nil, "plain label");
        pickColour(H, gq, panel, "Tank", "Mint");
        local completePrefix = assertLabel(H, gq, "Tank", MINT, "label with the set colour");
        H.assertEq(completePrefix, "|cffffcc00", "complete set: gold prefix");
        H.assertEq(GqUiFrameStatusText:GetText(), "Current set: |cff" .. MINT .. "Tank|r", "panel status line");

        -- bag item tooltip: coloured names (an item of DPS only)
        hoverBag(H, "headB");
        local line, index = tooltipLine("GearQuipper set(s):");
        H.assertEq(line, "|cff" .. SKY .. "DPS|r", "bag item: coloured set name");
        H.assertEq(tooltipTexts()[index - 1], " ", "spacer before the set line");
        GameTooltip:Hide();

        -- worn item tooltip: the set line too (the shared neck: every set, sorted, each in its colour)
        hoverWorn(H, CharacterNeckSlot);
        line, index = tooltipLine("GearQuipper set(s):");
        H.assertEq(line, "|cff" .. SKY .. "DPS|r, Default, |cff" .. PINK .. "Lost|r, |cff" .. MINT .. "Tank|r",
            "worn item: every set, coloured (Default has none)");
        H.assertEq(tooltipTexts()[index - 1], " ", "spacer before the set line");
        H.assertFalse(tooltipLine("|cffff0000Expected Item:|r"), "no mismatch on the neck");
        leaveWorn(H, CharacterNeckSlot);
        -- an uncoloured set reads plain
        H.assertTrue(gq:SaveSetColor("Lost", nil));
        hoverWorn(H, CharacterNeckSlot);
        H.assertEq(tooltipLine("GearQuipper set(s):"), "|cff" .. SKY .. "DPS|r, Default, Lost, |cff" .. MINT .. "Tank|r");
        leaveWorn(H, CharacterNeckSlot);
        H.assertTrue(gq:SaveSetColor("Lost", PINK));

        -- a worn item that is not the current set's: its sets AND "Expected Item" (one spacer for both)
        GQ_OPTIONS[gq.OPT_SAVECHANGES] = gq.OPTVALUE_SAVECHANGES_NEVER;
        H.playerEquip("ringC", 11);
        H.advance(0.5);
        H.assertEquipped(11, "ringC");
        hoverWorn(H, CharacterFinger0Slot);
        line, index = tooltipLine("GearQuipper set(s):");
        H.assertEq(line, "|cff" .. SKY .. "DPS|r", "worn ring of DPS");
        local expected, expectedIndex = tooltipLine("|cffff0000Expected Item:|r");
        H.assertEq(expected, gq:GetItemLink(gq:LoadSlot(11, "Tank")), "Expected Item kept");
        H.assertEq(expectedIndex, index + 1, "right below the set line");
        H.assertEq(tooltipTexts()[index - 1], " ");
        leaveWorn(H, CharacterFinger0Slot);
        -- incomplete set: red prefix, the name still in its colour (the label refreshes when the sheet opens)
        gq:SetPaperDollLabelText();
        local incompletePrefix = assertLabel(H, gq, "Tank", MINT, "incomplete set label");
        H.assertEq(incompletePrefix, "|cffff0000", "incomplete set: red prefix");
        -- an item in no set: no set line, only Expected Item
        H.playerEquip("ringA", 11);
        H.advance(0.5);
        H.give("twinRing");
        H.playerEquip("twinRing", 11);
        H.advance(0.5);
        hoverWorn(H, CharacterFinger0Slot);
        H.assertFalse(tooltipLine("GearQuipper set(s):"), "no set line for an item in no set");
        expected, expectedIndex = tooltipLine("|cffff0000Expected Item:|r");
        H.assertTrue(expected and tooltipTexts()[expectedIndex - 1] == " ", "Expected Item with its spacer");
        leaveWorn(H, CharacterFinger0Slot);
        H.playerEquip("ringA", 11);
        H.advance(0.5);
        GQ_OPTIONS[gq.OPT_SAVECHANGES] = gq.OPTVALUE_SAVECHANGES_GQMENU;
        H.assertWearing(H.SET_A, "back in Tank");

        -- data broker: text, tooltip (current set and bindings) and menu
        H.assertEq(ldb().text, "|cff" .. MINT .. "Tank|r", "broker text");
        gq:SaveEventBinding({
            [gq.FIELD_TYPE] = gq.EVENT_TALENTS_CHANGED,
            [gq.FIELD_SUBTYPE] = {name = gq:GetTalentSpecializations()[2], spellId = 2},
            [gq.FIELD_NAME] = "DPS",
            [gq.FIELD_PVE] = true,
            [gq.FIELD_PVP] = true,
        });
        gq:SetEventsEnabled(true);
        local texts = table.concat(brokerTooltip(), "\n");
        H.assertTrue(texts:find("Current set: |cff" .. MINT .. "Tank|r", 1, true), "broker tooltip: current set");
        H.assertTrue(texts:find("will switch to |cff" .. SKY .. "DPS|r", 1, true), "broker tooltip: binding");
        GameTooltip:Hide();
        gq:SetEventsEnabled(false);
        ldb().OnClick(UIParent, "RightButton");
        entries = H.menuEntries();
        H.assertTrue(panel.menuEntry(entries, "|cff" .. SKY .. "DPS|r"), "broker menu: DPS in Sky");
        H.assertTrue(panel.menuEntry(entries, "|cff" .. MINT .. "Tank|r").selected, "broker menu: Tank ticked");
        H.clickMenuEntry("|cff" .. SKY .. "DPS|r");
        H.advance(3);
        H.assertWearing(H.SET_B, "the coloured entry still switches");
        H.assertEq(ldb().text, "|cff" .. SKY .. "DPS|r", "broker text follows the current set");
        assertLabel(H, gq, "DPS", SKY, "label follows");
        H.switchTo(gq, "Tank");

        -- Custom...: the picker starts at the set's colour; live preview on the row and the label; Cancel restores
        list = colourMenu(H, gq, panel, "Tank");
        H.clickMenuEntry("Colour", entryByPlain(list, "Custom...").text);
        H.assertTrue(H.colorPickerShown(), "picker open");
        H.assertFalse(H.menuEntries(), "menu closed");
        H.assertEq(hexOf(ColorPickerFrame:GetPreviousValues()), MINT, "picker starts at the set colour");
        H.colorPickerSelect(0.2, 0.4, 0.6);
        H.assertEq(gq:LoadSetColor("Tank"), "336699", "live preview saved");
        H.assertEq(nameHex(panel.setRow("Tank")), "336699", "live preview on the row");
        assertLabel(H, gq, "Tank", "336699", "live preview on the label");
        H.colorPickerSelect(0.9, 0.5, 0.9);
        H.assertEq(nameHex(panel.setRow("Tank")), "e680e6");
        H.colorPickerCancel();
        H.assertFalse(H.colorPickerShown(), "Cancel closes the picker");
        H.assertEq(gq:LoadSetColor("Tank"), MINT, "Cancel restores Mint");
        H.assertEq(nameHex(panel.setRow("Tank")), MINT);
        assertLabel(H, gq, "Tank", MINT, "label restored");

        -- Escape and a click outside cancel too; from "no colour" they restore no colour
        H.assertTrue(gq:SaveSetColor("DPS", nil));
        for _, cancel in ipairs({H.colorPickerEscape, H.colorPickerClickOutside}) do
            list = colourMenu(H, gq, panel, "DPS");
            H.clickMenuEntry("Colour", entryByPlain(list, "Custom...").text);
            H.assertEq(hexOf(ColorPickerFrame:GetPreviousValues()), "ffffff", "no colour: the picker starts white");
            H.colorPickerSelect(0.1, 0.8, 0.3);
            H.assertEq(nameHex(panel.setRow("DPS")), hexOf(0.1, 0.8, 0.3), "preview");
            cancel();
            H.assertFalse(H.colorPickerShown(), "closed");
            H.assertEq(gq:LoadSetColor("DPS"), nil, "back to no colour");
            H.assertEq(nameHex(panel.setRow("DPS")), GOLD, "gold again");
        end

        -- Okay keeps the custom colour; the menu then ticks Custom (shown in that colour), no palette entry
        list = colourMenu(H, gq, panel, "DPS");
        H.clickMenuEntry("Colour", entryByPlain(list, "Custom...").text);
        H.colorPickerSelect(0.9, 0.5, 0.9);
        H.colorPickerOkay();
        H.assertFalse(H.colorPickerShown());
        H.assertEq(gq:LoadSetColor("DPS"), "e680e6", "Okay keeps the colour");
        list = colourMenu(H, gq, panel, "DPS");
        local custom = entryByPlain(list, "Custom...");
        H.assertTrue(custom.selected, "Custom ticked");
        H.assertEq(custom.text, "|cffe680e6Custom...|r", "Custom in its colour");
        for i = 1, #palette do
            H.assertFalse(list[i].selected, "no palette entry ticked");
        end
        -- None clears it
        H.clickMenuEntry("Colour", "None");
        H.assertEq(gq:LoadSetColor("DPS"), nil, "None clears");
        H.assertEq(sets(gq).DPS.FIELD_COLOR, nil);
        H.assertEq(nameHex(panel.setRow("DPS")), GOLD);
        H.assertEq(gq:ColorizeSetName("DPS"), "DPS");
        pickColour(H, gq, panel, "DPS", "Sky");

        -- saving keeps the colour (API, footer Save, menu "Save worn gear into this set")
        gq:SaveSet("Tank", false);
        H.assertEq(gq:LoadSetColor("Tank"), MINT, "SaveSet keeps the colour");
        GqUiFrame_BtnSaveSet:Click("LeftButton");
        H.assertEq(gq:LoadSetColor("Tank"), MINT, "footer Save keeps it");
        panel.openMenu(panel.setRow("Tank"));
        H.clickMenuEntry("Save worn gear into this set");
        H.advance(0.5);
        H.assertEq(gq:LoadSetColor("Tank"), MINT, "menu save keeps it");
        H.assertEq(nameHex(panel.setRow("Tank")), MINT);

        -- deleting a set drops its colour; a new set of that name starts without one; the picker survives a set
        -- deleted while it is open
        gq:SaveSet("Temp", false);
        H.switchTo(gq, "Tank");
        pickColour(H, gq, panel, "Temp", "Lime");
        H.assertTrue(gq:LoadSetColor("Temp"), "Temp coloured");
        list = colourMenu(H, gq, panel, "Temp");
        H.clickMenuEntry("Colour", entryByPlain(list, "Custom...").text);
        gq:RemoveSet("Temp");
        H.assertEq(sets(gq).Temp, nil, "set and colour gone");
        H.colorPickerSelect(0.5, 0.5, 0.9);
        H.colorPickerCancel();
        H.assertEq(sets(gq).Temp, nil, "no colour written for a deleted set");
        gq:SaveSet("Temp", false);
        H.assertEq(gq:LoadSetColor("Temp"), nil, "a new set of that name has no colour");
        gq:RemoveSet("Temp");
        H.switchTo(gq, "Tank");

        -- locked (a switch running): the colour entries do nothing, Custom opens no picker
        list = colourMenu(H, gq, panel, "Tank");
        local stale = {entryByPlain(list, "Sky").description, entryByPlain(list, "None").description,
            entryByPlain(list, "Custom...").description};
        gq:QueueSwitch("DPS");
        H.assertTrue(gq:IsUiLocked(), "a switch locks the panel");
        H.assertFalse(H.menuEntries(), "the lock closes the menu");
        for _, description in ipairs(stale) do
            description:Pick(MenuInputContext.MouseButton, "LeftButton");
        end
        H.assertEq(gq:LoadSetColor("Tank"), MINT, "colour unchanged while locked");
        H.assertFalse(H.colorPickerShown(), "no picker while locked");
        H.advance(3);
        H.assertWearing(H.SET_B, "only the switch ran");
        H.switchTo(gq, "Tank");

        panel.close();
        H.assertCursorEmpty();
        H.assertNoUiErrors();
    end,
    relog = function(H, gq)
        local panel = H.include("helpers/gq_panel.lua");
        H.advance(1);
        H.assertEq(gq:LoadSetColor("Tank"), MINT, "Mint persisted");
        H.assertEq(gq:LoadSetColor("DPS"), SKY, "Sky persisted");
        H.assertEq(gq:LoadSetColor("Lost"), PINK, "Pink persisted");
        panel.open();
        H.assertEq(nameHex(panel.setRow("Tank")), MINT, "row colour after relog");
        H.assertEq(nameHex(panel.setRow("DPS")), SKY);
        H.assertEq(nameHex(panel.setRow("Lost")), PINK);
        assertLabel(H, gq, "Tank", MINT, "label after relog");
        H.assertEq(ldb().text, "|cff" .. MINT .. "Tank|r", "broker text after relog");
        panel.close();
        H.assertNoUiErrors();
    end,
};
