-- (m) Switch speed with a realistic server latency: how long until the whole set is worn, and until the switch is
-- reported finished. Guards against slow, timer-driven switching: a pass must start as soon as the server has
-- answered the previous one, and the switch must end as soon as its own actions have landed. The switching flag must
-- still stay up until the switch's own equip events are in (they are never recorded as manual changes).
-- Targets for latency L: Tank (two passes: two-hander -> sword + shield) worn <= 2L + 0.15 s, DPS (one pass) worn
-- <= L + 0.10 s, finished <= worn + 0.35 s; a spec change sets the spec's set worn <= 2L + 0.5 s after
-- ACTIVE_TALENT_GROUP_CHANGED. At L = 0.15: 0.45 s, 0.25 s, +0.35 s and 0.8 s.
local LATENCY = 0.15;
local MORE_LATENCIES = {0.25, 0.5};
local STEP = 0.02;

local function wearingAll(H, expected)
    for slot = 1, 19 do
        local actual = H.inv[slot] and H.inv[slot].key;
        if actual ~= expected[slot] then
            return false;
        end
    end
    return true;
end

local function snapshotSlots(gq, setName)
    local stored = {};
    for slot = 0, 19 do
        stored[slot] = gq:LoadSlot(slot, setName) or false;
    end
    return stored;
end

local function assertSlotsUnchanged(H, gq, setName, before, msg)
    for slot = 0, 19 do
        H.assertEq(gq:LoadSlot(slot, setName) or false, before[slot],
            string.format("%s: %s slot %d unchanged", msg, setName, slot));
    end
end

-- Advances in small steps until `expected` is worn and the switch has finished; times are seconds since t0.
local function measure(H, gq, t0, expected, what)
    local tWorn, tDone;
    for _ = 1, 400 do
        H.advance(STEP);
        if not tWorn and wearingAll(H, expected) then
            tWorn = GetTime() - t0;
        end
        if tWorn and not gq:IsSwitching() then
            tDone = GetTime() - t0;
            break;
        end
    end
    H.assertTrue(tWorn, what .. " worn");
    H.assertTrue(tDone, what .. " finished");
    return tWorn, tDone;
end

local function timeSwitch(H, gq, setName, expected, maxWorn)
    -- the switch's own equip events must not reach the auto-save / previous-equipment bookkeeping
    local previousBefore = snapshotSlots(gq, gq.KEYWORD_PREVIOUSEQUIPMENT);
    local setsBefore = {Tank = snapshotSlots(gq, "Tank"), DPS = snapshotSlots(gq, "DPS")};

    local t0 = GetTime();
    gq:QueueSwitch(setName);
    local tWorn, tDone = measure(H, gq, t0, expected, setName);
    print(string.format("SPEED %-6s worn after %.2fs, finished after %.2fs (latency %.2fs%s)", setName, tWorn, tDone,
        H.latency, H.replySpread > 0 and string.format(", replies %.2fs apart", H.replySpread) or ""));
    H.assertTrue(tWorn <= maxWorn + 1e-6,
        string.format("%s worn after %.2fs at latency %.2fs (target <= %.2fs)", setName, tWorn, H.latency, maxWorn));
    H.assertTrue(tDone <= tWorn + 0.35 + 1e-6,
        string.format("%s finished %.2fs after it was worn (target <= 0.35s)", setName, tDone - tWorn));

    H.advance(1); -- late events, if any, would arrive now
    assertSlotsUnchanged(H, gq, gq.KEYWORD_PREVIOUSEQUIPMENT, previousBefore, setName .. " switch");
    for name, before in pairs(setsBefore) do
        assertSlotsUnchanged(H, gq, name, before, setName .. " switch");
    end
    for slot = 0, 19 do
        H.assertFalse(gq:IsIgnoredItem(slot), setName .. " switch: own change not taken as manual, slot " .. slot);
    end
    H.assertEq(gq:LoadCurrentSetName(), setName);
end

local function bindTalents(gq, specGroup, setName)
    gq:SaveEventBinding({
        [gq.FIELD_TYPE] = gq.EVENT_TALENTS_CHANGED,
        [gq.FIELD_SUBTYPE] = {name = gq:GetTalentSpecializations()[specGroup], spellId = specGroup},
        [gq.FIELD_NAME] = setName,
        [gq.FIELD_PVE] = true,
        [gq.FIELD_PVP] = true,
    });
end

-- Spec change (optionally with the 5 s spec cast): time from ACTIVE_TALENT_GROUP_CHANGED to the spec's set worn.
local function timeSpecSwap(H, gq, specGroup, setName, expected, withCast)
    local tChanged;
    local f = CreateFrame("Frame");
    f:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED");
    f:SetScript("OnEvent", function()
        tChanged = tChanged or GetTime();
    end);
    H.setSpecGroup(specGroup, withCast and {cast = true} or nil);
    if withCast then
        H.assertTrue(H.waitFor(function()
            return tChanged ~= nil;
        end, 6), "spec cast finished");
    end
    f:UnregisterAllEvents();
    H.assertTrue(tChanged, "ACTIVE_TALENT_GROUP_CHANGED fired");

    local what = string.format("spec %d -> %s%s", specGroup, setName, withCast and " (cast)" or "");
    local tWorn, tDone = measure(H, gq, tChanged, expected, what);
    local maxWorn = 2 * H.latency + 0.5;
    print(string.format("SPEED %-22s worn %.2fs after ACTIVE_TALENT_GROUP_CHANGED, finished after %.2fs " ..
                            "(latency %.2fs)", what, tWorn, tDone, H.latency));
    H.assertTrue(tWorn <= maxWorn + 1e-6,
        string.format("%s worn after %.2fs at latency %.2fs (target <= %.2fs)", what, tWorn, H.latency, maxWorn));
    H.assertEq(gq:LoadCurrentSetName(), setName);
    H.advance(1);
end

-- With H.replySpread the 9 replies of a full pass land one after the other: the next pass (and the end) must wait
-- for the last one, so the targets grow by the spread of 8 replies.
local function roundTrip(H, gq)
    local L, spread = H.latency, 8 * H.replySpread;
    timeSwitch(H, gq, "Tank", H.SET_A, 2 * L + 0.15 + spread);
    timeSwitch(H, gq, "DPS", H.SET_B, L + 0.10 + spread);
end

return {
    latency = LATENCY,
    -- an install from before v56 with the old default switch delay (600 ms): migrated to the new default (200 ms)
    savedVariables = {GQ_OPTIONS = {OPT_VERSION = 55, OPT_SWITCHDELAY = 600}},
    run = function(H, gq)
        H.assertEq(GQ_OPTIONS[gq.OPT_VERSION], 56, "options updated to v56");
        H.assertEq(GQ_OPTIONS[gq.OPT_SWITCHDELAY], 200, "old default switch delay migrated");
        H.advance(1);
        gq:SaveSet("Tank", false);
        H.wearSetBPieces();
        H.advance(1);
        gq:SaveSet("DPS", false);
        H.advance(1);
        local total = H.totalItems();
        -- every equip event GQ handles as a manual change would now be saved into the current set or ignored
        GQ_OPTIONS[gq.OPT_SAVECHANGES] = gq.OPTVALUE_SAVECHANGES_ALWAYS;
        GQ_OPTIONS[gq.OPT_IGNOREMANUALITEMS] = true;

        for _ = 1, 2 do
            roundTrip(H, gq);
        end

        -- a set per spec: spec 1 -> Tank, spec 2 -> DPS (currently DPS worn, spec 1 active)
        gq:SetEventsEnabled(true);
        bindTalents(gq, 1, "Tank");
        bindTalents(gq, 2, "DPS");
        timeSwitch(H, gq, "Tank", H.SET_A, 2 * H.latency + 0.15);
        timeSpecSwap(H, gq, 2, "DPS", H.SET_B);
        timeSpecSwap(H, gq, 1, "Tank", H.SET_A);
        timeSpecSwap(H, gq, 2, "DPS", H.SET_B, true);
        gq:SetEventsEnabled(false);

        -- the same targets, scaled, at higher latencies
        for _, latency in ipairs(MORE_LATENCIES) do
            H.latency = latency;
            roundTrip(H, gq);
        end
        H.latency = LATENCY;

        -- replies spread over several frames
        H.replySpread = 0.03;
        roundTrip(H, gq);
        H.replySpread = 0;

        H.assertCursorEmpty();
        H.assertTotalItems(total);
        H.assertNoUiErrors();
    end
};
