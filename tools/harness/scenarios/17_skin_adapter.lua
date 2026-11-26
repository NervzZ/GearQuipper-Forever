-- (q) Skin adapter (core/gearquipper-skin.lua): c:Skin(kind, widget) leaves stock widgets alone without a suite,
-- hands every kind to the right EllesmereUI primitive (or ElvUI handler) once, in registration order, at login or
-- at once after it, follows EllesmereUI's character-sheet style, survives a live toggle-on and a failing primitive.
-- Widgets are throwaway frames built from the real templates; the ones "registered before login" are made at
-- ADDON_LOADED (GQ's files are loaded, PLAYER_LOGIN has not fired).

-- kind, widget key, opts; registration order = the expected skinning order
local KINDS = {{"frame", "frame", {noBorder = true}}, {"panel", "panel"}, {"inset", "inset"}, {"button", "button"},
    {"button", "shared"}, {"checkbox", "checkbox"}, {"dropdown", "dropdown"}, {"scrollbar", "scrollbar"},
    {"itembutton", "item"}, {"close", "close"}, {"tab", "tab"}, {"editbox", "editbox"}, {"font", "font"}};

local EUI_PRIMITIVES = {frame = {"Shell"}, panel = {"Panel"}, inset = {"Inset"}, button = {"Button", "StateButtonLabel"},
    shared = {"Button", "StateButtonLabel"}, checkbox = {"Checkbox"}, dropdown = {"Dropdown"},
    scrollbar = {"ScrollBar"}, item = {"ItemButton"}, close = {"CloseButton"}, tab = {"Tab"}, editbox = {"EditBox"},
    font = {"Font"}};

local ELV_HANDLERS = {frame = {"HandleFrame"}, panel = {"HandleFrame"}, inset = {"HandleInsetFrame"},
    button = {"HandleButton"}, shared = {"HandleButton"}, checkbox = {"HandleCheckBox"},
    dropdown = {"HandleDropDownBox"}, scrollbar = {"HandleTrimScrollBar"}, item = {"HandleItemButton"},
    close = {"HandleCloseButton"}, tab = {"HandleTab"}, editbox = {"HandleEditBox"}, font = {}};

local function build(gq)
    local w = {};
    local frame = CreateFrame("Frame", "GqSkinTestShell", UIParent, "DefaultPanelTemplate");
    frame:Hide();
    frame.CloseButton = CreateFrame("Button", nil, frame, "UIPanelCloseButtonDefaultAnchors");
    w.frame = frame;
    w.panel = CreateFrame("Frame", nil, frame);
    w.panel.Fill = w.panel:CreateTexture(nil, "BACKGROUND");
    w.panel.Fill:SetColorTexture(0, 0, 0, 0.8);
    w.inset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate");
    w.button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
    w.shared = CreateFrame("Button", nil, frame, "SharedButtonSmallTemplate");
    w.checkbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate");
    w.dropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate");
    w.scrollbar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar");
    w.item = CreateFrame("ItemButton", nil, frame);
    w.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton");
    w.tab = CreateFrame("Button", nil, frame, "PanelTopTabButtonTemplate");
    w.editbox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate");
    w.font = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    for _, k in ipairs(KINDS) do
        gq:Skin(k[1], w[k[2]], k[3]);
    end
    frame:Show(); -- three-slice buttons draw their state art on show
    return w;
end

-- registers the "before login" widgets at ADDON_LOADED
local function setup(H)
    local f = CreateFrame("Frame");
    f:RegisterEvent("ADDON_LOADED");
    f:SetScript("OnEvent", function(self, event, name)
        if name == H.addonName then
            H.w17 = build(gearquipper);
        end
    end);
end

local function assertCalls(H, widget, expected, msg)
    local got = H.suiteCallsFor(widget);
    H.assertEq(table.concat(got, ","), table.concat(expected, ","), msg);
end

-- stock art untouched (alpha 1, original textures)
local function assertStock(H, w)
    H.assertEq(w.frame.Bg:GetAlpha(), 1, "panel background kept");
    H.assertEq(w.frame.Bg:GetTexture(), "Interface\\FrameGeneral\\UI-Background-Rock");
    H.assertEq(w.frame.NineSlice.TopEdge:GetAtlas(), "_UI-Frame-Metal-EdgeTop", "DefaultPanel NineSlice layout");
    H.assertEq(w.frame.NineSlice.TopEdge:GetAlpha(), 1);
    H.assertEq(w.button.Left:GetAlpha(), 1, "button art kept");
    H.assertEq(w.shared.Left:GetAtlas(), "128-RedButton-Left", "three-slice button art");
    H.assertEq(w.item:GetNormalTexture():GetAlpha(), 1, "item slot art kept");
    H.assertEq(w.dropdown.Background:GetAlpha(), 1, "dropdown art kept");
    H.assertEq(w.checkbox:GetNormalTexture():GetTexture(), "Interface\\Buttons\\UI-CheckBox-Up");
    H.assertEq(w.close:GetNormalTexture():GetAtlas(), "RedButton-Exit");
    H.assertEq(w.panel.Fill:GetAlpha(), 1);
end

-- every kind got its EllesmereUI primitive(s) exactly once, in registration order
local function assertEllesmereSkinned(H, w)
    H.assertEq(gearquipper:GetSkinBackend(), "EllesmereUI");
    for key, expected in pairs(EUI_PRIMITIVES) do
        assertCalls(H, w[key], expected, "EllesmereUI primitives for " .. key);
    end
    assertCalls(H, w.frame.CloseButton, {"CloseButton"}, "the shell's own close button");
    local order = {};
    for _, c in ipairs(H.suiteCalls) do
        if c.primitive ~= "StateButtonLabel" and c.widget ~= w.frame.CloseButton then
            order[#order + 1] = c.widget;
        end
    end
    for i, k in ipairs(KINDS) do
        H.assertTrue(order[i] == w[k[2]], "skinned in registration order: #" .. i .. " is " .. k[2]);
    end
    H.assertTrue(H.suiteCalls[1].args[1].noBorder, "Shell gets the frame's opts");
    H.assertEq(w.frame.Bg:GetAlpha(), 0, "Shell faded the panel art");
    H.assertEq(w.frame.NineSlice.TopEdge:GetAlpha(), 0, "Shell faded the NineSlice");
    H.assertEq(w.button.Left:GetAlpha(), 0, "Button faded the gold art");
    H.assertEq(w.item:GetNormalTexture():GetAlpha(), 0, "ItemButton faded the slot art");
    H.assertEq(w.item.IconBorder:GetAlpha(), 0, "ItemButton faded the quality ring");
    H.assertEq(w.panel.Fill:GetAlpha(), 0, "Panel faded the panel's own texture");
    H.assertTrue((w.font:GetFont()):find("EllesmereUI"), "Font re-fonted the string");
end

local function newButton(H)
    return CreateFrame("Button", nil, H.w17.frame, "UIPanelButtonTemplate");
end

-- a WowScrollBoxList whose rows are skinned in the element initializer: recycled rows are not skinned twice
local function scrollBoxRows(H, gq, expectCalls)
    local box = CreateFrame("Frame", nil, H.w17.frame, "WowScrollBoxList");
    box:SetSize(200, 100);
    local bar = CreateFrame("EventFrame", nil, H.w17.frame, "MinimalScrollBar");
    local view = CreateScrollBoxListLinearView();
    view:SetElementExtent(30);
    local inits = 0;
    view:SetElementInitializer("UIPanelButtonTemplate", function(row, data)
        inits = inits + 1;
        gq:Skin("button", row);
        row:SetText(data.name);
    end);
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view);
    local visibility = ScrollUtil.AddManagedScrollBarVisibilityBehavior(box, bar);
    box:SetDataProvider(CreateDataProvider({{name = "A"}, {name = "B"}, {name = "C"}}));
    local first = H.scrollBoxFrames(box);
    H.assertEq(#first, 3, "a frame per element");
    H.assertEq(first[2]:GetText(), "B");
    H.assertEq(inits, 3);
    H.assertFalse(bar:IsShown(), "3 x 30 fits into 100: no scroll bar");
    local function buttonCalls()
        local n = 0;
        for _, row in ipairs(H.scrollBoxFrames(box)) do
            n = n + H.countSuiteCalls("Button", row);
        end
        return n;
    end
    H.assertEq(buttonCalls(), expectCalls and 3 or 0, "rows skinned once each");

    -- new data provider: the same frames come back and are initialized again, not skinned again
    local dp = CreateDataProvider({{name = "X"}, {name = "Y"}, {name = "Z"}});
    box:SetDataProvider(dp);
    local second = H.scrollBoxFrames(box);
    H.assertEq(inits, 6, "recycled rows re-initialized");
    for i = 1, 3 do
        H.assertTrue(second[i] == first[i], "row " .. i .. " recycled");
    end
    H.assertEq(second[1]:GetText(), "X");
    H.assertEq(buttonCalls(), expectCalls and 3 or 0, "recycled rows not skinned twice");

    -- an insert keeps the existing rows (no re-init) and acquires one new frame
    dp:Insert({name = "W"});
    H.assertEq(#H.scrollBoxFrames(box), 4);
    H.assertEq(inits, 7, "only the new row initialized");
    H.assertEq(buttonCalls(), expectCalls and 4 or 0, "the new row skinned once");
    H.assertTrue(bar:IsShown(), "4 x 30 > 100: scroll bar shown");
    H.assertTrue(bar.Forward:IsEnabled() and not bar.Back:IsEnabled(), "at the top");
    H.scrollStep(bar, "Forward");
    H.assertTrue(box:GetScrollPercentage() > 0, "the stepper scrolls the list");
    H.assertTrue(H.scrollBoxFrameFor(box, function(data) return data.name == "W" end) ~= nil);
    return visibility;
end

local function stockRun(H, gq)
    H.assertEq(gq:GetSkinBackend(), nil, "no backend");
    H.assertEq(#H.suiteCalls, 0, "nothing skinned");
    assertStock(H, H.w17);
    local b = newButton(H);
    gq:Skin("button", b);
    H.assertEq(#H.suiteCalls, 0, "nothing skinned after login either");
    H.assertEq(b.Left:GetAlpha(), 1);
    scrollBoxRows(H, gq, false);
end

return {
    setup = setup,
    variants = {
        {name = "no suite", run = function(H, gq)
            H.assertEq(rawget(_G, "EllesmereUI"), nil);
            H.assertEq(rawget(_G, "ElvUI"), nil);
            stockRun(H, gq);
            H.assertFalse(pcall(gq.Skin, gq, "bogus", newButton(H)), "an unknown kind is an error");
            H.assertFalse(pcall(gq.Skin, gq, "button", nil), "a missing widget is an error");
        end},

        {name = "EllesmereUI eui", suites = {EllesmereUI = {charsheetStyle = "eui"}}, run = function(H, gq)
            local w = H.w17;
            H.assertEq(EllesmereUI._skinRegistry[1].name, H.addonName, "registered under the folder name");
            assertEllesmereSkinned(H, w);

            -- registered after login: skinned at once; a second c:Skin does nothing (except item buttons)
            local b = newButton(H);
            gq:Skin("button", b);
            assertCalls(H, b, {"Button", "StateButtonLabel"}, "skinned at once after login");
            gq:Skin("button", b);
            gq:Skin("button", w.button);
            gq:Skin("frame", w.frame);
            assertCalls(H, b, {"Button", "StateButtonLabel"}, "second c:Skin is a no-op");
            assertCalls(H, w.button, {"Button", "StateButtonLabel"});
            assertCalls(H, w.frame, {"Shell"});
            gq:Skin("close", w.frame.CloseButton);
            assertCalls(H, w.frame.CloseButton, {"CloseButton"}, "the shell's close button only once");

            SetItemButtonQuality(w.item, 4);
            gq:Skin("itembutton", w.item);
            assertCalls(H, w.item, {"ItemButton", "ItemButton"}, "item buttons re-apply");
            local border = H.euiItemBorder(w.item);
            H.assertTrue(border[1] > 0.6 and border[3] > 0.9, "rarity border follows the new quality (epic)");

            -- Restrip pitfall: a texture directly on a skinned frame is faded again, one on a child frame is not
            local direct = w.frame:CreateTexture(nil, "ARTWORK");
            local holder = CreateFrame("Frame", nil, w.frame);
            local onChild = holder:CreateTexture(nil, "ARTWORK");
            H.euiRestrip();
            H.assertEq(direct:GetAlpha(), 0, "Restrip fades textures on skinned frames");
            H.assertEq(onChild:GetAlpha(), 1, "Restrip leaves child frames alone");

            scrollBoxRows(H, gq, true);
            H.assertEq(H.countSuiteCalls("HandleButton"), 0, "no ElvUI calls");
        end},

        {name = "EllesmereUI modern", suites = {EllesmereUI = {charsheetStyle = "modern"}}, run = function(H, gq)
            assertEllesmereSkinned(H, H.w17);
        end},

        {name = "EllesmereUI style API failing", suites = {EllesmereUI = {styleApi = "error"}}, run = function(H, gq)
            assertEllesmereSkinned(H, H.w17);
        end},

        {name = "EllesmereUI without style API", suites = {EllesmereUI = {styleApi = "missing"}}, run = function(H, gq)
            H.assertEq(EllesmereUI.GetBlizzWindowStyle, nil);
            assertEllesmereSkinned(H, H.w17);
        end},

        {name = "EllesmereUI blizzard sheet", suites = {EllesmereUI = {charsheetStyle = "blizzard"}},
            run = function(H, gq)
                H.assertEq(#EllesmereUI._skinRegistry, 1, "registered");
                stockRun(H, gq);
            end},

        {name = "EllesmereUI sheet off", suites = {EllesmereUI = {charsheetStyle = "off"}}, run = stockRun},

        {name = "EllesmereUI live toggle-on", suites = {EllesmereUI = {thirdPartySkinsOff = true}},
            run = function(H, gq)
                local w = H.w17;
                H.assertEq(#H.suiteCalls, 0, "skinning off at login");
                local late = newButton(H);
                gq:Skin("button", late);
                H.assertEq(gq:GetSkinBackend(), nil);
                H.euiToggleOn();
                assertEllesmereSkinned(H, w);
                assertCalls(H, late, {"Button", "StateButtonLabel"}, "registered after login, before the toggle");
                H.assertTrue(H.suiteCalls[#H.suiteCalls].widget == late, "skinned last (registration order)");
                H.euiToggleOn();
                assertCalls(H, late, {"Button", "StateButtonLabel"}, "the callback fires once per session");
            end},

        {name = "ElvUI", suites = {ElvUI = {}}, run = function(H, gq)
            local w = H.w17;
            H.assertEq(gq:GetSkinBackend(), "ElvUI");
            for key, expected in pairs(ELV_HANDLERS) do
                assertCalls(H, w[key], expected, "ElvUI handlers for " .. key);
            end
            assertCalls(H, w.frame.CloseButton, {}, "HandleFrame skins the shell's close button itself");
            assertCalls(H, w.item.IconBorder, {"HandleIconBorder"}, "the quality ring follows the rarity");
            for _, c in ipairs(H.suiteCalls) do
                if c.primitive == "HandleDropDownBox" then
                    -- GQ's panel dropdowns are skinned too; each keeps its own width
                    H.assertEq(c.args[1], c.widget:GetWidth(), "the dropdown keeps its width");
                    if c.widget == w.dropdown then
                        H.assertEq(c.args[1], 120, "the test dropdown keeps its width");
                    end
                end
            end
            SetItemButtonQuality(w.item, 3);
            gq:Skin("itembutton", w.item);
            assertCalls(H, w.item, {"HandleItemButton"}, "item buttons are handled once");
            assertCalls(H, w.item.IconBorder, {"HandleIconBorder", "HandleIconBorder"}, "and refresh the border");
            local b = newButton(H);
            gq:Skin("button", b);
            gq:Skin("button", b);
            assertCalls(H, b, {"HandleButton"}, "after login: at once, once");
        end},

        {name = "ElvUI character skin off", suites = {ElvUI = {character = false}}, run = stockRun},

        {name = "both suites", suites = {EllesmereUI = {}, ElvUI = {}}, run = function(H, gq)
            assertEllesmereSkinned(H, H.w17);
            for _, c in ipairs(H.suiteCalls) do
                H.assertEq(c.suite, "EllesmereUI", "EllesmereUI wins");
            end
            H.assertEq(next(H.elv.S.addonStorage), nil, "GQ does not register with ElvUI");
        end},

        {name = "failing primitive", suites = {EllesmereUI = {fail = {Button = true}}}, run = function(H, gq)
            local w = H.w17;
            H.assertNoErrors("a failing primitive is not a Lua error");
            H.assertEq(gq:GetSkinBackend(), "EllesmereUI");
            assertCalls(H, w.button, {"Button"}, "Button failed, StateButtonLabel skipped");
            assertCalls(H, w.checkbox, {"Checkbox"}, "later widgets still skinned");
            assertCalls(H, w.font, {"Font"});
            gq.debugMode = true;
            local b = newButton(H);
            gq:Skin("button", b);
            H.assertChat("%[GearQuipper%]%[Debug%] Skin, EllesmereUI, button, .*injected", "failure in the debug log");
            gq:Skin("button", b);
            assertCalls(H, b, {"Button"}, "a failed widget is not retried");
            gq.debugMode = false;
            H.suiteFail("Button", false);
            local ok = newButton(H);
            gq:Skin("button", ok);
            assertCalls(H, ok, {"Button", "StateButtonLabel"});
            H.assertNoErrors();
        end},
    },
};
