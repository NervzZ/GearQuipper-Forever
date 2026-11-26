-- scope stuff
gearquipper = gearquipper or {};
local c = gearquipper;
c.name = "GearQuipper";

GQ_OPTIONS = GQ_OPTIONS or {};
GQ_DATA = GQ_DATA or {};

local GQ_VERSION = 56;

c.VALUE_NONE = "VALUE_NONE";
c.KEYWORD_NONE = "$NONE";
c.KEYWORD_PREVIOUS = "$PREVIOUS";
c.KEYWORD_PREVIOUSEQUIPMENT = "$PREVIOUSEQUIPMENT";
c.KEYWORD_PVE = "$PVE";
c.KEYWORD_PVP = "$PVP";

-- init
function c:Init()
    c:InitOptions();
    c:InitDatabase();
    c:InitBroker();
    c:InitUI(PaperDollFrame);

    -- updates
    if not GQ_OPTIONS[c.OPT_VERSION] then
        GQ_OPTIONS[c.OPT_VERSION] = 0;
    end
    if GQ_OPTIONS[c.OPT_VERSION] < GQ_VERSION then
        if GQ_OPTIONS[c.OPT_VERSION] < 53 then
            -- reset bag/bank location index
            c:ResetBagLocationIndex();
            c:ResetBankLocationIndex();
        end
        if GQ_OPTIONS[c.OPT_VERSION] < 56 and GQ_OPTIONS[c.OPT_SWITCHDELAY] == 600 then
            -- switches wait for the server now; the delay only feeds fallbacks and debounces (old default 600)
            GQ_OPTIONS[c.OPT_SWITCHDELAY] = 200;
        end

        GQ_OPTIONS[c.OPT_SHOW_WATERMARK] = true;
        GQ_OPTIONS[c.OPT_VERSION] = GQ_VERSION; -- finish update
        c:Println(c:GetText("Update to version %s complete.", GQ_VERSION));
    end

    c.debugMode = false;
    c.initFinished = true;
    c:Println(c:GetText("AddOn loaded: Version: %s. Type /gq for options.", GQ_VERSION));
    c:Println(c:GetText("Visit https://www.curseforge.com/wow/addons/gearquipper for support, feedback and updates."));
end

function c:GetVersion()
    return GQ_VERSION;
end

function c:GetHomeLatency(addFixed)
    -- Home sends/receives data about your chat, guild info, item tooltips, auction house.
    -- from blue post https://us.forums.blizzard.com/en/wow/t/question-world-vs-home-latency/820575/5
    local down, up, lagHome, lagWorld = GetNetStats();
    addFixed = addFixed or 0;
    return lagHome + addFixed;
end

function c:GetWorldLatency(addFixed)
    -- World sends/receives data about your spells, abilities, character/NPC movement, combat mechanics.
    -- from blue post https://us.forums.blizzard.com/en/wow/t/question-world-vs-home-latency/820575/5
    local down, up, lagHome, lagWorld = GetNetStats();
    addFixed = addFixed or 0;
    return lagWorld + addFixed;
end

function c:GetLatency(addFixed)
    local homeLatency, worldLatency = c:GetHomeLatency(addFixed), c:GetWorldLatency(addFixed);
    if homeLatency > worldLatency then
        return homeLatency;
    else
        return worldLatency;
    end
end
