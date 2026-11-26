-- gq_panel.lua: helpers for scenarios that use the GearQuipper panel (GqUiFrame: Sets / Events tabs).
-- Usage inside run (H.include runs it with H and returns the table):
--     local panel = H.include("helpers/gq_panel.lua");
--     panel.open(); panel.setRow("Tank"):Click("LeftButton");
-- Rows live in WowScrollBoxLists: GqUiFrameSetList (element data {setName}) and GqUiFrameBindingList
-- ({index, binding}); recycled frames answer :GetElementData() for the element they show now.
local H = ...;
local P = {};

-- Opens the character sheet and the GQ panel the way a player does (the GQ button on the paper doll).
function P.open()
    if not CharacterFrame:IsShown() then
        H.openCharacterFrame();
        H.advance(0.2);
    end
    if not GqUiFrame:IsShown() then
        H.assertTrue(GQ_PaperDollButton and GQ_PaperDollButton:IsEnabled(), "GQ button usable");
        GQ_PaperDollButton:Click("LeftButton");
        H.advance(0.2);
    end
    H.assertTrue(GqUiFrame:IsVisible(), "GQ panel open");
end

function P.close()
    H.closeCharacterFrame();
    H.advance(0.2);
end

-- "Sets" or "Events": clicks the tab (a selected tab is disabled, like in game).
function P.tab(name)
    local tab = name == "Events" and GqUiFrameTab2 or GqUiFrameTab1;
    if tab:IsEnabled() then
        tab:Click("LeftButton");
    end
    return tab;
end

function P.selectedTab()
    return PanelTemplates_GetSelectedTab(GqUiFrame) == 2 and "Events" or "Sets";
end

function P.setRows()
    return H.scrollBoxFrames(GqUiFrameSetList);
end

-- set names in list order
function P.setNames()
    local names = {};
    for _, row in ipairs(P.setRows()) do
        names[#names + 1] = row:GetElementData().setName;
    end
    return names;
end

function P.setRow(name)
    return H.scrollBoxFrameFor(GqUiFrameSetList, function(data)
        return data.setName == name;
    end);
end

function P.bindingRows()
    return H.scrollBoxFrames(GqUiFrameBindingList);
end

function P.bindingRow(index)
    return H.scrollBoxFrameFor(GqUiFrameBindingList, function(data)
        return data.index == index;
    end);
end

-- Right-clicks a row and returns the context menu's entries ({text, enabled, selected, checkbox, title, ...}).
function P.openMenu(row)
    H.closeMenus();
    row:Click("RightButton");
    local entries = H.menuEntries();
    H.assertTrue(entries, "context menu open");
    return entries;
end

function P.menuEntry(entries, text)
    for _, entry in ipairs(entries) do
        if entry.text == text then
            return entry;
        end
    end
end

return P;
