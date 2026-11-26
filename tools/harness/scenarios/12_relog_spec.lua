-- (l) Sets and spec bindings survive a logout: session 1 creates them; session 2 logs in with spec 2 already
-- active (every link carries the other spec id) and still swaps sets on spec changes.
local function bindTalents(gq, specGroup, setName)
    gq:SaveEventBinding({
        [gq.FIELD_TYPE] = gq.EVENT_TALENTS_CHANGED,
        [gq.FIELD_SUBTYPE] = {name = gq:GetTalentSpecializations()[specGroup], spellId = specGroup},
        [gq.FIELD_NAME] = setName,
        [gq.FIELD_PVE] = true,
        [gq.FIELD_PVP] = true,
    });
end

return {
    run = function(H, gq)
        H.advance(1);
        gq:SaveSet("Tank", false);
        H.wearSetBPieces();
        gq:SaveSet("DPS", false);
        gq:SetEventsEnabled(true);
        bindTalents(gq, 1, "Tank");
        bindTalents(gq, 2, "DPS");
        H.switchTo(gq, "Tank");
        H.assertWearing(H.SET_A, "session 1 ends in Tank");
    end,
    relogSetup = function(H)
        H.player.specGroup = 2; -- logged out in spec 1 gear, logs in with spec 2 active
    end,
    relog = function(H, gq)
        H.advance(3);
        H.assertEq(gq:LoadCurrentSetName(), "Tank", "current set restored from SavedVariables");
        H.assertTrue(gq:IsSetComplete("Tank"), "stored strings match the gear despite the other spec id in links");
        H.assertWearing(H.SET_A, "nothing switches on login");

        H.setSpecGroup(1);
        H.advance(5);
        H.assertWearing(H.SET_A, "spec 1 -> Tank (already worn)");
        H.setSpecGroup(2);
        H.advance(5);
        H.assertWearing(H.SET_B, "spec 2 -> DPS after relog");
        H.assertEq(gq:LoadCurrentSetName(), "DPS");
        H.assertNoUiErrors();
        H.assertCursorEmpty();
    end,
};
