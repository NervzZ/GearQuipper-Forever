-- (a) The addon loads and initialises without Lua errors; the default set and $PREVIOUSEQUIPMENT exist;
-- the character sheet (paper doll + GQ panel) opens and closes cleanly; the panel has its modern structure;
-- the slash command answers.
local function soundPlayed(H, id, from)
    for i = from + 1, #H.sounds do
        if H.sounds[i] == id then
            return true;
        end
    end
    return false;
end

return function(H, gq)
    H.assertTrue(gq, "global gearquipper table exists");
    H.assertTrue(gq.initFinished, "Init() ran on ADDON_LOADED");
    -- the release version from the TOC, not the data version (details: 27_version_strings)
    H.assertChat("AddOn loaded: Version: " .. H.tocFields.Version:gsub("%.", "%%.") .. "%. Type /gq",
        "load line with the TOC version");
    H.assertNoChat("curseforge", "no pointer to the original addon's page");
    H.advance(2);

    local names = gq:LoadSetNames();
    H.assertEq(#names, 1, "one set after first login");
    H.assertEq(names[1], DEFAULT, "default set created on first PLAYER_ENTERING_WORLD");
    H.assertEq(gq:LoadCurrentSetName(), DEFAULT, "default set is current");
    local withPrevious = gq:LoadSetNames(true);
    H.assertEq(#withPrevious, 2, "$PREVIOUSEQUIPMENT exists (hidden)");

    -- the default set captured the worn gear with normalised item strings
    local set = gq:LoadSet(DEFAULT);
    H.assertEq(set[1], gq:GetItemString(1), "head stored as the normalised string of the worn helm");
    H.assertFalse(tostring(set[1]):find("1482"), "spec id is not part of stored strings");
    H.assertTrue(gq:IsSetComplete(DEFAULT), "default set matches the worn gear");

    -- the panel: modern Blizzard templates, docked right of the character window's side tabs
    H.assertEq(GqUiFrame.Bg:GetTexture(), "Interface\\FrameGeneral\\UI-Background-Rock", "DefaultPanelTemplate art");
    H.assertEq(GqUiFrame.NineSlice.TopEdge:GetAtlas(), "_UI-Frame-Metal-EdgeTop", "DefaultPanelTemplate border");
    H.assertEq(GqUiFrame:GetTitleText():GetText(), "GearQuipper", "title without version");
    H.assertEq(GqUiFrame.CloseButton:GetNormalTexture():GetAtlas(), "RedButton-Exit", "close button");
    H.assertEq(GqUiFrame.Inset.Bg:GetTexture(), "Interface\\FrameGeneral\\UI-Background-Marble", "InsetFrameTemplate");
    H.assertTrue(GqUiFrameTab1.isTopTab and GqUiFrameTab2.isTopTab, "PanelTopTabButtonTemplate tabs");
    H.assertEq(GqUiFrameTab1:GetText(), "Sets");
    H.assertEq(GqUiFrameTab2:GetText(), "Events");
    H.assertTrue(GqUiFrame.Tabs[1] == GqUiFrameTab1 and GqUiFrame.numTabs == 2, "PanelTemplates know both tabs");
    local point, relativeTo, relativePoint = GqUiFrameTab1:GetPoint(1);
    H.assertTrue(point == "TOPLEFT" and relativeTo == GqUiFrame and relativePoint == "TOPLEFT", "tabs at the top");
    H.assertTrue(GqUiFrameSetList.ScrollTarget and GqUiFrameSetList.GetDataProvider, "WowScrollBoxList");
    H.assertTrue(GqUiFrameSetListScrollBar.Track.Thumb and GqUiFrameSetListScrollBar.Back, "MinimalScrollBar");
    H.assertEq(GQ_PaperDollButton.Left:GetTexture(), "Interface\\Buttons\\UI-DialogBox-goldbutton-up-left",
        "GQ button is a UIPanelButtonTemplate");
    H.assertEq(GQ_PaperDollButton:GetText(), "GQ");
    H.assertTrue(GQ_PaperDollButton:GetWidth() == 50 and GQ_PaperDollButton:GetHeight() == 20, "same size");
    H.assertFalse(rawget(_G, "GqUiFrameEvents"), "no floating binding dialog any more");
    H.assertFalse(rawget(_G, "GqEventBindingFrame"), "no second window under the panel");
    local x;

    -- character sheet with the GQ side panel
    H.openCharacterFrame();
    H.advance(0.5);
    H.assertTrue(PaperDollFrame:IsVisible(), "paper doll visible");
    H.assertFalse(GqUiFrame:IsShown(), "panel closed by default");
    local sounds = #H.sounds;
    GQ_PaperDollButton:Click("LeftButton");
    H.advance(0.5);
    H.assertTrue(GqUiFrame and GqUiFrame:IsVisible(), "GQ panel visible on the character sheet");
    H.assertTrue(soundPlayed(H, 839, sounds), "open sound");
    H.assertEq(GQ_OPTIONS[gq.OPT_MENUOPEN], true, "remembered open");
    H.assertEq(GqUiFrame:GetHeight(), 484, "as tall as the character window");
    point, relativeTo, relativePoint, x = GqUiFrame:GetPoint(1);
    H.assertTrue(point == "TOPLEFT" and relativeTo == PaperDollFrame and relativePoint == "TOPRIGHT",
        "docked to the paper doll's right edge");
    H.assertEq(x, CharacterFrame.ModeTabs:GetWidth() + 2, "right of the side tabs");
    H.assertEq(#H.scrollBoxFrames(GqUiFrameSetList), 1, "one set row");

    -- the close button closes through ToggleUI (remembered closed)
    sounds = #H.sounds;
    GqUiFrame.CloseButton:Click("LeftButton");
    H.advance(0.2);
    H.assertFalse(GqUiFrame:IsShown(), "closed by its close button");
    H.assertEq(GQ_OPTIONS[gq.OPT_MENUOPEN], false, "remembered closed");
    H.assertTrue(soundPlayed(H, 840, sounds), "close sound");
    H.assertTrue(CharacterFrame:IsShown(), "the character window stays open");

    GQ_PaperDollButton:Click("LeftButton");
    H.advance(0.2);
    H.assertTrue(GqUiFrame:IsVisible(), "reopened");
    H.closeCharacterFrame();
    H.advance(0.5);
    H.assertFalse(GqUiFrame:IsVisible(), "GQ panel hidden with the character sheet");
    H.openCharacterFrame();
    H.advance(0.5);
    H.assertTrue(GqUiFrame:IsVisible(), "reopens with the sheet (option open)");

    -- the options gear opens the settings
    GqUiFrame_BtnOptions:Click("LeftButton");
    H.advance(0.2);
    H.assertTrue(SettingsPanel:IsShown(), "options opened");
    H.closeCharacterFrame();
    H.advance(0.5);

    -- hovering items runs the tooltip hook without errors
    H.hoverInventorySlot(1);
    H.hoverBagItem(0, 1);
    GameTooltip:Hide();

    H.slash("/gq");
    H.assertChat("/gq", "help text printed");
    H.advance(1);
end
