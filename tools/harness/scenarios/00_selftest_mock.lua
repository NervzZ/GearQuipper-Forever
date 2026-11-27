-- Self-test of the mock (no addon): cursor/equip semantics, events, links, combat, secrets, timers, XML, bank,
-- and the modern UI pieces: template registry, panel/tab/button/checkbox templates, intrinsic ItemButton,
-- ScrollBox + DataProvider + MinimalScrollBar, dropdowns and menus, UI-suite stubs.

-- Runs fn and returns the Lua errors it recorded (then clears them): for checks that must fail.
local function errorsOf(H, fn)
    local before = #H.errors;
    fn();
    local list = {};
    for i = before + 1, #H.errors do
        list[#list + 1] = H.errors[i].msg;
    end
    for i = #H.errors, before + 1, -1 do
        table.remove(H.errors, i);
    end
    return list;
end

local function selfTestTemplates(H)
    -- unknown templates, fonts and an intrinsic template on the wrong frame type fail the run
    local errs = errorsOf(H, function()
        CreateFrame("Frame", nil, UIParent, "NoSuchTemplateAnywhere");
    end);
    H.assertTrue(errs[1] and errs[1]:find("unknown template 'NoSuchTemplateAnywhere'"), "unknown template is an error");
    errs = errorsOf(H, function()
        UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalTypo");
        UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalLeft");
    end);
    H.assertEq(#errs, 1, "unknown font is an error, a Forever font is not");
    errs = errorsOf(H, function()
        CreateFrame("Button", nil, UIParent, "WowStyle1DropdownTemplate");
    end);
    H.assertTrue(errs[1] and errs[1]:find("DropdownButton template"), "dropdown template needs a DropdownButton");
    errs = errorsOf(H, function()
        CreateFrame("Frame", nil, UIParent, "MinimalScrollBar");
    end);
    H.assertTrue(errs[1] and errs[1]:find("EventFrame template"), "MinimalScrollBar needs an EventFrame");
    H.assertEq(C_XMLUtil.GetTemplateInfo("SharedButtonSmallTemplate").height, 28);
    H.assertEq(C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate").type, "DropdownButton");
    H.assertEq(C_XMLUtil.GetTemplateInfo("NoSuchTemplateAnywhere"), nil);

    -- DefaultPanelTemplate: Bg, TopTileStreaks, NineSlice pieces, TitleContainer.TitleText ($parentTitleText)
    local panel = CreateFrame("Frame", "SelfTestPanel", UIParent, "DefaultPanelTemplate");
    H.assertTrue(panel.Bg == SelfTestPanelBg and panel.Bg:GetTexture() == "Interface\\FrameGeneral\\UI-Background-Rock");
    H.assertEq(panel.TopTileStreaks:GetAtlas(), "_UI-Frame-TopTileStreaks");
    H.assertEq(panel.NineSlice.TopLeftCorner:GetAtlas(), "UI-Frame-Metal-CornerTopLeft");
    H.assertEq(panel.NineSlice:GetFrameLevel(), 500);
    H.assertTrue(panel.TitleContainer.TitleText == SelfTestPanelTitleText, "title text named like the client");
    panel:SetTitle("Hello");
    H.assertEq(panel:GetTitleText():GetText(), "Hello");
    H.assertFalse(panel.FrameGlow:IsShown());
    local inset = CreateFrame("Frame", nil, panel, "InsetFrameTemplate");
    H.assertEq(inset.Bg:GetTexture(), "Interface\\FrameGeneral\\UI-Background-Marble");
    H.assertEq(inset.NineSlice.TopLeftCorner:GetAtlas(), "UI-Frame-InnerTopLeft");
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButtonDefaultAnchors");
    H.assertEq(close:GetWidth(), 28, "Camelot close button size");
    local point, _, _, x, y = close:GetPoint(1);
    H.assertTrue(point == "TOPRIGHT" and x == 0 and y == 3, "Camelot close button anchor");
    H.assertEq(close:GetNormalTexture():GetAtlas(), "RedButton-Exit");
    close:Click();
    H.assertFalse(panel:IsShown(), "close button hides its parent");
    panel:Show();

    -- tabs: join the parent's Tabs array; PanelTemplates select / deselect them
    local tabs = {};
    for i = 1, 3 do
        tabs[i] = CreateFrame("Button", nil, panel, "PanelTopTabButtonTemplate");
        tabs[i]:SetID(i);
        tabs[i]:SetText("Tab" .. i);
    end
    H.assertTrue(panel.Tabs and #panel.Tabs == 3 and panel.Tabs[2] == tabs[2], "parentArray Tabs");
    H.assertTrue(tabs[1].isTopTab, "top tab");
    PanelTemplates_SetNumTabs(panel, 3);
    PanelTemplates_SetTab(panel, 2);
    H.assertEq(PanelTemplates_GetSelectedTab(panel), 2);
    H.assertTrue(tabs[2].LeftActive:IsShown() and not tabs[2].Left:IsShown() and not tabs[2]:IsEnabled(), "selected");
    H.assertTrue(tabs[1].Left:IsShown() and not tabs[1].LeftActive:IsShown() and tabs[1]:IsEnabled(), "deselected");
    local p2, rel2 = tabs[2]:GetPoint(1);
    H.assertTrue(p2 == "TOPLEFT" and rel2 == tabs[1], "tabs anchored in a row");

    -- buttons and check buttons
    local shared = CreateFrame("Button", nil, panel, "SharedButtonSmallTemplate");
    H.assertEq(shared:GetWidth(), 138);
    H.assertEq(shared:GetHighlightTexture():GetAtlas(), "128-RedButton-Highlight");
    panel:Hide();
    panel:Show();
    H.assertEq(shared.Left:GetAtlas(), "128-RedButton-Left", "state art drawn on show");
    shared:Disable();
    H.assertEq(shared.Center:GetAtlas(), "_128-RedButton-Center-Disabled");
    local gold = CreateFrame("Button", "SelfTestGold", panel, "UIPanelButtonTemplate");
    gold:SetText("Go");
    H.assertTrue(gold.Text == SelfTestGoldText and gold:GetText() == "Go", "ButtonText");
    gold:Disable();
    H.assertEq(gold.Left:GetTexture(), "Interface\\Buttons\\UI-DialogBox-goldbutton-disabled-left");
    local cb = CreateFrame("CheckButton", "SelfTestCheck", panel, "UICheckButtonTemplate");
    H.assertTrue(cb.Text == cb.text and cb.Text == SelfTestCheckText, "Text + text alias");
    H.assertEq(cb:GetCheckedTexture():GetTexture(), "Interface\\Buttons\\UI-CheckBox-Check");
    cb:Click();
    H.assertTrue(cb:GetChecked());

    -- intrinsic ItemButton (also the character slots) + SetItemButton* globals
    local ib = CreateFrame("ItemButton", "SelfTestItem", panel);
    H.assertTrue(ib.icon == SelfTestItemIconTexture and ib.Count == SelfTestItemCount, "icon / Count names");
    H.assertTrue(CharacterHeadSlot.IconBorder ~= nil, "character slots are item buttons");
    H.assertEq(ib:GetNormalTexture():GetTexture(), "Interface\\Buttons\\UI-Quickslot2");
    SetItemButtonTexture(ib, 133070);
    H.assertEq(ib.icon:GetTexture(), 133070);
    SetItemButtonCount(ib, 5);
    H.assertTrue(ib.Count:IsShown() and ib.Count:GetText() == "5");
    SetItemButtonQuality(ib, 3);
    local r, g, b = ib.IconBorder:GetVertexColor();
    H.assertTrue(ib.IconBorder:IsShown() and b > 0.8 and r < 0.1, "rare border");
    SetItemButtonQuality(ib, 0);
    H.assertFalse(ib.IconBorder:IsShown(), "poor items have no border");
    ib:SetAlpha(0.35);
    H.assertTrue(ib.icon:GetAlpha() == 0.35 and ib:GetAlpha() == 1, "ItemButtonMixin:SetAlpha fades the parts");

    -- the same templates from addon XML (intrinsic element tags, parentKey / parentArray on instances)
    local function node(tag, attr, kids)
        return {tag = tag, attr = attr or {}, kids = kids or {}, file = "selftest.xml", line = 1};
    end
    local xmlFrame = H.xml.loadTop(node("Frame", {name = "SelfTestXmlPanel", inherits = "DefaultPanelTemplate"}, {
        node("Frames", {}, {
            node("Button", {parentKey = "CloseButton", inherits = "UIPanelCloseButtonDefaultAnchors"}),
            node("Frame", {parentKey = "ScrollBox", inherits = "WowScrollBoxList"}),
            node("EventFrame", {parentKey = "ScrollBar", inherits = "MinimalScrollBar"}),
            node("DropdownButton", {parentKey = "Dropdown", inherits = "WowStyle1DropdownTemplate"}),
            node("Button", {parentArray = "Tabs", inherits = "PanelTopTabButtonTemplate", id = "1", text = "Sets"}),
            node("ItemButton", {parentKey = "Slot"})})}));
    H.assertTrue(xmlFrame.CloseButton and xmlFrame.ScrollBox.ScrollTarget and xmlFrame.ScrollBar.Track.Thumb,
        "XML children from templates");
    H.assertTrue(xmlFrame.Dropdown.SetupMenu and xmlFrame.Slot.IconBorder, "intrinsic element tags");
    H.assertTrue(#xmlFrame.Tabs == 1 and xmlFrame.Tabs[1]:GetText() == "Sets" and xmlFrame.Tabs[1]:GetID() == 1,
        "tab added once to Tabs");

    -- size changes reach OnSizeChanged; EventFrames send their OnShow callback
    local sized, ev = 0, CreateFrame("EventFrame", nil, panel);
    ev:SetScript("OnSizeChanged", function()
        sized = sized + 1;
    end);
    ev:SetSize(10, 10);
    ev:SetSize(10, 10);
    H.assertEq(sized, 1, "OnSizeChanged once per change");
    local shown = 0;
    ev:RegisterCallback("OnShow", function()
        shown = shown + 1;
    end, panel);
    ev:Hide();
    ev:Show();
    H.assertEq(shown, 1, "EventFrame OnShow callback");
end

local function selfTestScrollBox(H)
    local holder = CreateFrame("Frame", nil, UIParent);
    local box = CreateFrame("Frame", nil, holder, "WowScrollBoxList");
    box:SetSize(100, 64);
    local bar = CreateFrame("EventFrame", nil, holder, "MinimalScrollBar");
    H.assertTrue(bar.Back and bar.Forward and bar.Track.Thumb, "MinimalScrollBar parts");
    local view = CreateScrollBoxListLinearView(2, 2, 0, 0, 4);
    local inits, resets = {}, 0;
    view:SetElementInitializer("UICheckButtonTemplate", function(frame, data)
        inits[#inits + 1] = data.name;
        frame.Text:SetText(data.name);
    end);
    view:SetElementResetter(function()
        resets = resets + 1;
    end);
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view);
    local behavior = ScrollUtil.AddManagedScrollBarVisibilityBehavior(box, bar);
    local acquired = 0;
    ScrollUtil.AddAcquiredFrameCallback(box, function(o, frame, data, new)
        acquired = acquired + 1;
    end, holder);
    local dp = CreateDataProvider({{name = "a"}, {name = "b"}});
    box:SetDataProvider(dp);
    local frames = H.scrollBoxFrames(box);
    H.assertEq(#frames, 2);
    H.assertEq(table.concat(inits, ","), "a,b", "initializer in data order");
    H.assertTrue(frames[1]:GetParent() == box.ScrollTarget, "rows live on the scroll target");
    H.assertEq(frames[2]:GetHeight(), 32, "extent from the template size");
    local _, rel, _, _, y = frames[2]:GetPoint(1);
    H.assertTrue(rel == box.ScrollTarget and y == -36, "row 2 below row 1 (32 + spacing 4)");
    H.assertTrue(box:FindFrame(dp:Find(2)) == frames[2] and frames[2]:GetElementData().name == "b");
    H.assertEq(box:GetExtent(), 2 + 32 + 4 + 32 + 2, "extent with padding and spacing");
    H.assertTrue(bar:IsShown() and box:HasScrollableExtent(), "72 > 64: scrollable, bar shown");
    -- row 2 ends at 2 + 32 + 4 + 32 = 70; aligned to the end of the 64 visible: offset 6 of the 8 scroll range
    box:ScrollToElementDataIndex(2, ScrollBoxConstants.AlignEnd);
    H.assertTrue(math.abs(box:GetScrollPercentage() - 0.75) < 0.001, "scrolled row 2 into view");
    H.assertTrue(math.abs(bar:GetScrollPercentage() - 0.75) < 0.001, "the bar follows the box");
    H.scrollStep(bar, "Back");
    H.assertEq(box:GetScrollPercentage(), 0, "the Back stepper scrolls the box up");

    -- recycling: reassigning re-inits the same frames; contents changes keep kept rows without re-init
    inits = {};
    box:SetDataProvider(CreateDataProvider({{name = "c"}, {name = "d"}}));
    local again = H.scrollBoxFrames(box);
    H.assertTrue(again[1] == frames[1] and again[2] == frames[2], "frames recycled");
    H.assertEq(table.concat(inits, ","), "c,d");
    H.assertEq(resets, 2, "element resetter on release");
    local dp2 = box:GetDataProvider();
    inits = {};
    dp2:InsertAtIndex({name = "e"}, 1);
    H.assertEq(table.concat(inits, ","), "e", "only the new element initialized");
    H.assertEq(H.scrollBoxFrames(box)[1]:GetElementData().name, "e", "frames follow data order");
    dp2:RemoveIndex(1);
    H.assertEq(#H.scrollBoxFrames(box), 2);
    dp2:Flush();
    H.assertEq(#H.scrollBoxFrames(box), 0, "flush releases every row");
    H.assertFalse(bar:IsShown(), "nothing to scroll: bar hidden");
    H.assertTrue(acquired >= 5, "acquired-frame callbacks");
    dp2:SetSortComparator(function(l, r)
        return l.name < r.name;
    end);
    dp2:Insert({name = "z"}, {name = "y"});
    H.assertEq(dp2:Find(1).name, "y", "sorted provider");
    H.assertEq(H.scrollBoxFrames(box)[1]:GetElementData().name, "y");
    H.mouseWheel(box, -1);

    -- selection behavior
    local selection = ScrollUtil.AddSelectionBehavior(box);
    local changed = {};
    selection:RegisterCallback(SelectionBehaviorMixin.Event.OnSelectionChanged, function(o, data, selected)
        changed[#changed + 1] = data.name .. (selected and "+" or "-");
    end, holder);
    selection:SelectElementData(dp2:Find(1));
    selection:SelectElementData(dp2:Find(2));
    -- as in game, the element that loses the selection is reported twice
    H.assertEq(table.concat(changed, ","), "y+,y-,y-,z+", "single selection moves");
    H.assertTrue(selection:IsSelected(H.scrollBoxFrameFor(box, function(d) return d.name == "z" end)));
end

local function selfTestMenus(H)
    local holder = CreateFrame("Frame", nil, UIParent);
    local dd = CreateFrame("DropdownButton", nil, holder, "WowStyle1DropdownTemplate");
    H.assertTrue(dd.Background and dd.Arrow and dd.Text, "WowStyle1 parts");
    H.assertEq(dd:GetWidth(), 120);
    local value, flags, clicked = "b", {x = false}, nil;
    dd:SetDefaultText("pick one");
    dd:SetupMenu(function(owner, root)
        root:CreateTitle("Letters");
        for _, v in ipairs({"a", "b", "c"}) do
            root:CreateRadio(v:upper(), function(d) return value == d; end, function(d) value = d; end, v);
        end
        root:CreateDivider();
        root:CreateCheckbox("Flag", function() return flags.x; end, function() flags.x = not flags.x; end);
        local sub = root:CreateButton("More");
        sub:CreateButton("Deep", function() clicked = "deep"; end);
        root:CreateButton("Off", function() end):SetEnabled(false);
    end);
    H.assertEq(H.dropdownText(dd), "B", "shows the selected radio");
    local entries = H.dropdownEntries(dd);
    H.assertEq(entries[1].text, "Letters");
    H.assertTrue(entries[3].selected and entries[3].radio, "B selected");
    H.assertEq(H.pickDropdown(dd, "C"), nil, "radio: menu closes");
    H.assertEq(value, "c");
    H.assertEq(H.dropdownText(dd), "C", "text follows the pick");
    H.assertFalse(dd:IsMenuOpen());
    H.assertEq(H.pickDropdown(dd, "Flag"), MenuResponse.Refresh, "checkbox: menu stays open");
    H.assertTrue(flags.x and dd:IsMenuOpen());
    H.assertEq(H.dropdownText(dd), "C, Flag", "every selection is listed");
    H.closeMenus();
    H.assertFalse(dd:IsMenuOpen(), "closed");
    H.pickDropdown(dd, "More", "Deep");
    H.assertEq(clicked, "deep", "submenu path");
    H.assertFalse(pcall(H.pickDropdown, dd, "Off"), "a disabled entry cannot be picked");
    H.closeMenus();
    H.assertFalse(pcall(H.pickDropdown, dd, "Nope"), "unknown entry");
    H.closeMenus();
    value, flags.x = nil, false;
    dd:GenerateMenu();
    H.assertEq(H.dropdownText(dd), "pick one", "default text without a selection");
    dd:OverrideText("fixed");
    H.pickDropdown(dd, "A");
    H.assertEq(H.dropdownText(dd), "fixed", "OverrideText wins");
    dd:SetEnabled(false);
    H.assertEq(dd.Arrow:GetAtlas(), "common-dropdown-a-button-disabled");
    H.assertFalse(pcall(H.openDropdown, dd), "a disabled dropdown does not open");
    dd:SetEnabled(true);
    H.mouseWheel(dd, -1);

    -- MenuUtil context menus and the legacy UIDropDownMenu through H.clickMenuEntry
    local got;
    MenuUtil.CreateContextMenu(holder, function(owner, root)
        root:CreateButton("Push", function(data) got = data; end, 42);
    end);
    H.assertEq(H.menuEntries()[1].text, "Push");
    H.clickMenuEntry("Push");
    H.assertEq(got, 42);
    H.assertEq(H.menuEntries(), nil, "context menu closed");
    local legacy = CreateFrame("Frame", "SelfTestLegacyDD", UIParent, "UIDropDownMenuTemplate");
    UIDropDownMenu_Initialize(legacy, function()
        local info = UIDropDownMenu_CreateInfo();
        info.text, info.func = "Old", function() got = "old"; end;
        UIDropDownMenu_AddButton(info);
    end);
    H.clickMenuEntry("Old");
    H.assertEq(got, "old", "legacy dropdown entry");
end

local function selfTestSuites(H)
    H.installSuites({EllesmereUI = {}, ElvUI = {}});
    local S, elvS;
    EllesmereUI.RegisterSkin("SelfTest", function(s) S = s; end);
    local E = unpack(ElvUI);
    E:GetModule("Skins"):AddCallbackForAddon("SelfTestAddon", "SelfTest", function(s) elvS = s; end, nil, nil, nil,
        "character");
    H.loadedAddons.SelfTestAddon = true;
    H.fire("PLAYER_LOGIN");
    H.assertTrue(S and S.apiVersion == 4, "EllesmereUI callback at login");
    H.assertTrue(elvS == E:GetModule("Skins"), "ElvUI callback at login");
    local f = CreateFrame("Frame", nil, UIParent, "DefaultPanelTemplate");
    local direct = f:CreateTexture();
    S.Shell(f, {noBorder = true});
    H.assertEq(f.Bg:GetAlpha(), 0, "Shell fades the panel art");
    local later = f:CreateTexture();
    H.euiRestrip();
    H.assertEq(later:GetAlpha(), 0, "Restrip fades textures added later");
    elvS:HandleButton(f);
    H.assertEq(table.concat(H.suiteCallsFor(f), ","), "Shell,HandleButton");
    H.suiteFail("Panel", true);
    H.assertFalse(pcall(S.Panel, f), "injected failure");
    H.suiteFail("Panel", false);
    local late;
    EllesmereUI.RegisterSkin("Late", function(s) late = s; end);
    H.assertTrue(late ~= nil, "a registration after login fires at once");
    H.assertTrue(direct ~= nil);
end

-- bag windows: slot buttons, the frame a click hits, recycled buttons, the tampering check
local function selfTestBags(H)
    H.give("twinBlade");
    H.openMerchant();
    H.openBags("combined");
    local bag, slot = H.bagSlotOf("orb");
    local orb = H.bags[bag].slots[slot];
    local button = H.bagSlotButton(bag, slot);
    H.assertEq(button:GetBagID(), bag, "Blizzard's slot knows its bag");
    H.assertEq(rawget(button, "bagID"), bag, "through the bagid attribute");
    H.assertEq(H.frameAtBagSlot(bag, slot), button, "nothing on top");
    H.assertEq(#H.slotButtonTampering(button), 0, "untouched");

    -- frames on top: a plain Frame and a lower Button do not take the mouse, a higher Button does
    local cover = CreateFrame("Frame", nil, button);
    cover:SetAllPoints();
    cover:SetFrameLevel(button:GetFrameLevel() + 3);
    local low = CreateFrame("Button", nil, button);
    low:SetAllPoints();
    low:SetFrameLevel(button:GetFrameLevel() - 1);
    H.assertEq(H.frameAtBagSlot(bag, slot), button, "a Frame and a lower Button let the click through");
    local top = CreateFrame("Button", nil, button);
    top:SetAllPoints(button);
    top:SetFrameLevel(button:GetFrameLevel() + 5);
    local clicks = {};
    top:SetScript("OnClick", function(_, mouseButton)
        clicks[#clicks + 1] = mouseButton;
    end);
    H.assertEq(H.frameAtBagSlot(bag, slot), top, "a higher Button takes the click");
    H.assertEq(H.clickBagSlot(bag, slot, "RightButton"), top, "the right-click lands on it");
    H.assertEq(#clicks, 0, "not registered for the right button: nothing happens");
    H.clickBagSlot(bag, slot, "LeftButton");
    H.assertEq(clicks[1], "LeftButton", "registered for the left button by default");
    H.assertEq(H.bags[bag].slots[slot], orb, "the frame on top kept the orb from being sold");
    top:Hide();

    -- the slot's own right-click sells at the merchant (Blizzard's secure path), a shift-click links
    H.clickBagSlot(bag, slot, "RightButton", {shift = true});
    H.assertEq(H.modifiedClicks[#H.modifiedClicks].action, "CHATLINK", "shift-click links");
    H.clickBagSlot(bag, slot, "RightButton");
    H.advance(0.1);
    H.assertEq(H.sold[#H.sold], orb, "right-click sold the orb");

    -- the pool hands its buttons out the other way round after a reopen
    bag, slot = H.bagSlotOf("twinBlade");
    button = H.bagSlotButton(bag, slot);
    H.closeBags();
    H.openBags("combined");
    H.assertTrue(H.bagSlotButton(bag, slot) ~= button, "another button shows the slot after a reopen");

    -- tampering: a field written or a script hooked shows; a hooksecurefunc on a method does not
    hooksecurefunc(button, "SetItemButtonTexture", function() end);
    H.assertEq(#H.slotButtonTampering(button), 0, "hooksecurefunc is fine");
    button.selfTestField = true;
    button:HookScript("OnClick", function() end);
    local problems = table.concat(H.slotButtonTampering(button), "; ");
    H.assertTrue(problems:find("field selfTestField written", 1, true), "field write found: " .. problems);
    H.assertTrue(problems:find("script OnClick hooked", 1, true), "hook found: " .. problems);
    H.closeBags();

    -- EllesmereUIBags: the bag is the parent's id
    H.installEuiBags({view = "list"});
    H.openBags("eui");
    bag, slot = H.bagSlotOf("twinBlade");
    button = H.bagSlotButton(bag, slot);
    H.assertEq(rawget(button, "bagID"), nil, "no bagid attribute");
    H.assertEq(button:GetParent():GetID(), bag, "the parent's id is the bag");
    H.assertEq(H.frameAtBagSlot(bag, slot), button, "the text overlay does not take the mouse");
    H.closeBags();
    H.closeMerchant();
end

return {
    noAddon = true,
    latency = 0, -- the latency section below switches it on by itself
    run = function(H)
        local total = H.totalItems();

        -- links: Forever format, spec id follows the active spec group
        local link = GetInventoryItemLink("player", 1);
        H.assertTrue(link:find("|Hitem:%d+::::::::60:1482::1:::::::|h%[Helm of the Bastion%]|h|r$"), "link format: " .. link);
        local seen = {};
        local f = CreateFrame("Frame");
        f:SetScript("OnEvent", function(self, event, ...)
            seen[#seen + 1] = event .. ":" .. table.concat({tostringall(...)}, ",");
        end);
        f:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED");
        f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED");
        f:RegisterEvent("BAG_UPDATE_DELAYED");
        f:RegisterEvent("UI_ERROR_MESSAGE");
        f:RegisterEvent("ADDON_ACTION_BLOCKED");
        f:RegisterUnitEvent("PLAYER_FLAGS_CHANGED", "player");
        H.setSpecGroup(2);
        H.assertTrue(GetInventoryItemLink("player", 1):find(":60:1483:"), "spec id changes with the spec group");
        H.assertEq(seen[1], "ACTIVE_TALENT_GROUP_CHANGED:2,1");
        H.setSpecGroup(1);

        -- unit-event filter
        seen = {};
        H.fireUnit("PLAYER_FLAGS_CHANGED", "nameplate4");
        H.fireUnit("PLAYER_FLAGS_CHANGED", "player");
        H.assertEq(#seen, 1, "RegisterUnitEvent filters by unit");

        -- cursor: pick up locks the item in place; clearing unlocks it
        PickupInventoryItem(1);
        H.assertTrue(CursorHasItem(), "cursor has the helm");
        H.assertTrue(IsInventoryItemLocked(1), "helm locked while on the cursor");
        H.assertEquipped(1, "headA", "item stays in its slot while on the cursor");
        ClearCursor();
        H.assertFalse(IsInventoryItemLocked(1), "unlocked after ClearCursor");

        -- equip from the bags swaps with the worn item; events arrive on the next frame
        seen = {};
        local bagOfHeadB = H.find("headB")[1];
        C_Item.EquipItemByName(H.itemLink({item = H.items.headB, id = H.items.headB.id}), 1);
        H.assertEquipped(1, "headB");
        H.assertTrue(H.bags[bagOfHeadB.bag].slots[bagOfHeadB.slot].key == "headA", "worn helm goes to the freed cell");
        H.assertEq(#seen, 0, "events are not dispatched synchronously");
        H.advance(0);
        H.assertEq(seen[1], "PLAYER_EQUIPMENT_CHANGED:1,false");
        H.advance(0);
        H.assertEq(seen[#seen], "BAG_UPDATE_DELAYED:", "BAG_UPDATE_DELAYED one frame later");

        -- two-hander: the off-hand goes to a free bag slot
        C_Item.EquipItemByName("Greatsword of Testing", 16);
        H.assertEquipped(16, "greatsword");
        H.assertEquipped(17, nil);
        H.assertInBags("sword");
        H.assertInBags("shield");
        -- off-hand while wielding a 2H: the 2H goes to the bags (into the shield's freed cell)
        C_Item.EquipItemByName("Wall of Testing", 17);
        H.assertEquipped(17, "shield");
        H.assertEquipped(16, nil);
        H.assertInBags("greatsword");
        C_Item.EquipItemByName("Blade of Testing", 16);
        H.assertEquipped(16, "sword");
        -- 2H with full bags: refused with "Inventory is full."
        local added = H.fillBags();
        H.advance(0);
        C_Item.EquipItemByName("Greatsword of Testing", 16);
        H.assertEquipped(16, "sword", "2H refused when the off-hand has nowhere to go");
        H.assertEquipped(17, "shield");
        H.assertEq(H.uiErrors[#H.uiErrors].key, "ERR_INV_FULL");
        H.assertCursorEmpty();
        for _ = 1, added do
            H.removeFromBags("junk");
        end

        -- gear never goes into the quiver
        PickupInventoryItem(1);
        C_Container.PickupContainerItem(3, 5);
        H.assertEq(H.uiErrors[#H.uiErrors].key, "ERR_ITEM_DOESNT_GO_INTO_BAG");
        ClearCursor();
        PickupInventoryItem(1);
        PutItemInBag(C_Container.ContainerIDToInventoryID(3));
        H.assertEquipped(1, "headB", "quiver refuses gear");
        ClearCursor();
        H.assertNoGearInSpecialBags();

        -- MH <-> OH swap of two one-handers
        H.playerEquip("mace", 17);
        H.assertEquipped(17, "mace");
        C_Item.EquipItemByName("Mace of Testing", 16);
        H.assertEquipped(16, "mace");
        H.assertEquipped(17, "sword");

        -- combat: armour refused, weapons allowed; blocked pickups fire ADDON_ACTION_BLOCKED
        H.setCombat(true);
        C_Item.EquipItemByName("Helm of the Bastion", 1);
        H.assertEquipped(1, "headB", "no armour swap in combat");
        H.assertEq(H.uiErrors[#H.uiErrors].key, "ERR_NOT_IN_COMBAT");
        C_Item.EquipItemByName("Blade of Testing", 16);
        H.assertEquipped(16, "sword", "weapon swap allowed in combat");
        H.blockCombatPickups = true;
        seen = {};
        C_Item.EquipItemByName("Mace of Testing", 16);
        H.assertEquipped(16, "sword", "blocked");
        H.assertEq(seen[1], "ADDON_ACTION_BLOCKED:" .. H.addonName .. ",EquipItemByName()");
        H.blockCombatPickups = false;
        H.setCombat(false);

        -- secrets
        H.setRestricted(true);
        local afk = UnitIsAFK("player");
        H.assertTrue(issecretvalue(afk), "UnitIsAFK is secret in a restricted zone");
        H.assertFalse(pcall(function() return afk < 1 end), "ordering a secret errors");
        H.assertFalse(pcall(function() return "x" .. afk end), "concatenating a secret errors");
        H.setRestricted(false);
        H.assertFalse(UnitIsAFK("player"));

        -- timers and the error trap
        local fired = false;
        C_Timer.After(1, function() fired = true; error("boom"); end);
        H.advance(0.9);
        H.assertFalse(fired, "timer not due yet");
        H.advance(0.2);
        H.assertTrue(fired, "timer ran");
        H.assertEq(#H.errors, 1, "timer error recorded");
        H.errors = {};

        -- XML builder: template with $parent names, parentKey, inline handlers, OnLoad order
        H.xml.loadTop({tag = "Button", file = "selftest.xml", line = 1, attr = {name = "SelfTestTemplate", virtual = "true"},
            kids = {
                {tag = "Layers", attr = {}, kids = {{tag = "Layer", attr = {level = "ARTWORK"}, kids = {
                    {tag = "FontString", attr = {name = "$parentLabel", parentKey = "label"}, kids = {}}}}}},
                {tag = "Scripts", attr = {}, kids = {
                    {tag = "OnLoad", file = "selftest.xml", line = 5, attr = {}, kids = {}, text = "self.loaded = (self.loaded or 0) + 1"},
                    {tag = "OnClick", file = "selftest.xml", line = 6, attr = {}, kids = {}, text = "self.clickedWith = button"}}}}});
        local b = CreateFrame("Button", "SelfTestButton", UIParent, "SelfTestTemplate");
        H.assertEq(b.loaded, 1, "OnLoad ran once");
        H.assertTrue(b.label == SelfTestButtonLabel and b.label ~= nil, "$parent name + parentKey");
        b:Click("RightButton");
        H.assertEq(b.clickedWith, "RightButton", "inline handler parameters");
        H.assertFalse(pcall(f.RegisterEvent, f, "NOT_AN_EVENT"), "unknown events are rejected");
        H.assertFalse(pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", print), "removed script types are rejected");
        H.assertTrue(f.SetBackdrop == nil, "SetBackdrop needs BackdropTemplate");

        -- latency mode: reads show the old state until the server answers
        H.latency = 0.2;
        C_Item.EquipItemByName("Helm of the Bastion", 1);
        H.assertEquipped(1, "headB", "not applied yet");
        H.assertTrue(IsInventoryItemLocked(1), "locked while pending");
        H.advance(0.3);
        H.assertEquipped(1, "headA", "applied after the latency");
        H.latency = 0;

        -- bank tabs: only while the bank is open
        H.assertEq(C_Container.GetContainerNumSlots(6), 0, "bank tab closed");
        H.openBank();
        H.assertEq(table.concat(C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Character), ","), "6,7");
        PickupInventoryItem(1);
        C_Container.PickupContainerItem(6, 1);
        H.assertInBank("headA");
        H.assertEquipped(1, nil);
        H.assertEq(C_Container.ContainerIDToInventoryID(6), nil, "bank tabs are not inventory bags");
        H.assertFalse(pcall(PutItemInBag, nil), "PutItemInBag(nil) is a usage error");
        H.closeBank();
        H.assertEq(C_Container.GetContainerNumSlots(6), 0);

        H.assertTotalItems(total, "no item lost or duplicated");
        H.assertCursorEmpty();

        selfTestTemplates(H);
        selfTestScrollBox(H);
        selfTestMenus(H);
        selfTestSuites(H);
        selfTestBags(H);
        H.log("self-test reached the end; uiErrors:", #H.uiErrors, "events:", #H.eventLog);
    end,
};
