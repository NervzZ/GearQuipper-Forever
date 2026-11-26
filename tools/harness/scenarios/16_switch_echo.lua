-- (o) Switches now finish as soon as their own actions have landed, so a late duplicate PLAYER_EQUIPMENT_CHANGED from
-- the client must not be taken for a manual change: it may not overwrite the previous-equipment set nor mark slots as
-- ignored. A real manual change right after a switch (a different item) is still recorded.
local function snapshot(gq, setName)
    local stored = {};
    for slot = 0, 19 do
        stored[slot] = gq:LoadSlot(slot, setName) or false;
    end
    return stored;
end

return {
    latency = 0.15,
    run = function(H, gq)
        H.advance(1);
        gq:SaveSet("Tank", false);
        H.wearSetBPieces();
        H.advance(1);
        gq:SaveSet("DPS", false);
        H.advance(1);
        GQ_OPTIONS[gq.OPT_SAVECHANGES] = gq.OPTVALUE_SAVECHANGES_ALWAYS;
        GQ_OPTIONS[gq.OPT_IGNOREMANUALITEMS] = true;

        -- DPS -> Tank: head, chest, legs, feet, hands, back, ring, trinket, main hand and off hand change
        gq:QueueSwitch("Tank");
        for _ = 1, 200 do
            H.advance(0.02);
            if not gq:IsSwitching() then
                break;
            end
        end
        H.assertFalse(gq:IsSwitching(), "switch finished");
        H.assertWearing(H.SET_A, "Tank worn");
        local previous = snapshot(gq, gq.KEYWORD_PREVIOUSEQUIPMENT);
        local tank = snapshot(gq, "Tank");

        -- the client repeats the equip events of the switch a few frames after it finished
        H.advance(0.05);
        for _, slot in ipairs({1, 5, 7, 8, 10, 11, 13, 15, 16, 17}) do
            H.fire("PLAYER_EQUIPMENT_CHANGED", slot, true);
        end
        H.advance(0.3);
        for slot = 0, 19 do
            H.assertEq(gq:LoadSlot(slot, gq.KEYWORD_PREVIOUSEQUIPMENT) or false, previous[slot],
                "previous equipment untouched by echoes, slot " .. slot);
            H.assertEq(gq:LoadSlot(slot, "Tank") or false, tank[slot], "Tank untouched by echoes, slot " .. slot);
            H.assertFalse(gq:IsIgnoredItem(slot), "echo not taken as a manual change, slot " .. slot);
        end

        -- a real hand change right after the switch: still saved into the current set (auto-save: Always)
        H.playerEquip("headB", 1);
        H.advance(0.5);
        H.assertEq(gq:LoadSlot(1, "Tank"), gq:GetItemString(1), "manual helmet change saved into Tank");
        H.assertTrue(gq:LoadSlot(1, "Tank") ~= tank[1], "Tank's helmet really changed");
    end
};
