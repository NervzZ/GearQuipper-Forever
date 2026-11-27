-- Players see the release version from the TOC (## Version), never GQ_VERSION (56): that number only versions the
-- saved data and drives the migrations in Init. Covered: the load line, the update line after a migration, the
-- options gear's tooltip, the fallback to the data version when the TOC has no version, the German texts.
-- The old pointer to the original addon's CurseForge page is gone.
local DATA_VERSION = 56;

local function pat(s)
    return (tostring(s):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"));
end

-- left texts of the tooltip the options gear shows in the docked panel
local function optionsTooltip(H)
    H.openCharacterFrame();
    H.advance(0.5);
    if not GqUiFrame:IsVisible() then
        GQ_PaperDollButton:Click("LeftButton");
        H.advance(0.2);
    end
    H.mouseEnter(GqUiFrame_BtnOptions);
    H.advance(0.05);
    local texts = {};
    for i = 1, GameTooltip:NumLines() do
        texts[i] = _G["GameTooltipTextLeft" .. i]:GetText() or "";
    end
    H.mouseLeave(GqUiFrame_BtnOptions);
    H.closeCharacterFrame();
    H.advance(0.5);
    return texts;
end

local function assertTooltipVersion(H, version)
    local texts = optionsTooltip(H);
    H.assertEq(texts[2], "GearQuipper Forever v" .. version, "options gear tooltip shows the version");
end

local function assertNoOldPage(H)
    H.assertNoChat("curseforge", "no pointer to the original addon's page");
    H.assertNoChat("Visit ", "no visit line");
end

local function releaseVersion(H, gq)
    local version = H.tocFields.Version;
    H.assertTrue(version and version:find("^%d+%.%d+%.%d+$"), "the TOC has a release version like 1.2.3");
    H.assertTrue(version ~= tostring(DATA_VERSION), "release version is not the data version");
    H.assertEq(gq:GetVersion(), version, "GetVersion returns the TOC version");
    return version;
end

return {
    variants = {
        {
            name = "first install",
            run = function(H, gq)
                local version = releaseVersion(H, gq);
                H.assertChat("^%[GearQuipper%] AddOn loaded: Version: " .. pat(version) .. "%. Type /gq for options%.$",
                    "load line with the TOC version");
                -- a first install runs the migrations from data version 0
                H.assertChat("^%[GearQuipper%] Update to version " .. pat(version) .. " complete%.$",
                    "update line with the TOC version");
                H.assertNoChat("ersion:? " .. DATA_VERSION, "the data version is not shown");
                H.assertEq(GQ_OPTIONS[gq.OPT_VERSION], DATA_VERSION, "saved data carries the data version");
                assertNoOldPage(H);
                assertTooltipVersion(H, version);
                H.advance(1);
            end
        },
        {
            name = "update from data v55",
            savedVariables = {GQ_OPTIONS = {OPT_VERSION = 55}},
            run = function(H, gq)
                local version = releaseVersion(H, gq);
                H.assertChat("^%[GearQuipper%] Update to version " .. pat(version) .. " complete%.$",
                    "update line with the TOC version");
                H.assertNoChat("version " .. DATA_VERSION, "the data version is not shown");
                H.assertEq(GQ_OPTIONS[gq.OPT_VERSION], DATA_VERSION, "data migrated to the data version");
                assertNoOldPage(H);
                H.advance(1);
            end
        },
        {
            name = "data already current",
            savedVariables = {GQ_OPTIONS = {OPT_VERSION = DATA_VERSION}},
            run = function(H, gq)
                local version = releaseVersion(H, gq);
                H.assertNoChat("Update to version", "no migration, no update line");
                H.assertChat("AddOn loaded: Version: " .. pat(version) .. "%.", "load line with the TOC version");
                assertNoOldPage(H);
                H.advance(1);
            end
        },
        {
            name = "TOC without a version",
            setup = function(H)
                H.tocFields.Version = nil;
            end,
            run = function(H, gq)
                H.assertEq(gq:GetVersion(), DATA_VERSION, "falls back to the data version");
                H.assertChat("AddOn loaded: Version: " .. DATA_VERSION .. "%.", "load line with the fallback");
                assertNoOldPage(H);
                assertTooltipVersion(H, DATA_VERSION);
                H.advance(1);
            end
        },
        {
            name = "German client",
            setup = function(H)
                -- the localization file reads the locale while it loads
                GetLocale = function()
                    return "deDE";
                end;
            end,
            run = function(H, gq)
                local version = releaseVersion(H, gq);
                H.assertChat("^%[GearQuipper%] AddOn geladen: Version " .. pat(version) .. "%. Tippe /gq für Optionen%.$",
                    "German load line with the TOC version");
                H.assertChat("^%[GearQuipper%] Update auf Version " .. pat(version) .. " komplett%.$",
                    "German update line with the TOC version");
                H.assertNoChat("Version " .. DATA_VERSION, "the data version is not shown");
                H.assertNoChat("Besuche", "no German visit line");
                assertNoOldPage(H);
                assertTooltipVersion(H, version);
                H.advance(1);
            end
        }
    }
};
