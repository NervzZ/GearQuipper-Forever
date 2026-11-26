-- (f) A set per spec: "on talents change" bindings spec 1 -> Tank, spec 2 -> DPS. A spec swap changes the spec id
-- inside every item link (like the client); stored sets must keep matching the gear (normalised strings), the
-- current-set label must follow, and gear changed by hand on the character sheet while a spec's set is current
-- is saved into that set only.
local function bindTalents(H, gq, specGroup, setName)
    gq:SaveEventBinding({
        [gq.FIELD_TYPE] = gq.EVENT_TALENTS_CHANGED,
        [gq.FIELD_SUBTYPE] = {name = gq:GetTalentSpecializations()[specGroup], spellId = specGroup},
        [gq.FIELD_NAME] = setName,
        [gq.FIELD_PVE] = true,
        [gq.FIELD_PVP] = true,
    });
end

return {
    setup = function(H)
        H.give("twinRing");
    end,
    run = function(H, gq)
        H.advance(1);
        local total = H.totalItems();
        gq:SaveSet("Tank", false);
        H.wearSetBPieces();
        gq:SaveSet("DPS", false);
        H.switchTo(gq, "Tank");
        H.assertWearing(H.SET_A, "start in Tank");

        gq:SetEventsEnabled(true);
        bindTalents(H, gq, 1, "Tank");
        bindTalents(H, gq, 2, "DPS");

        -- the panel shows the bindings: a spec badge on each set, a row per binding on the Events tab
        local panel = H.include("helpers/gq_panel.lua");
        panel.open();
        H.assertTrue(panel.setRow("Tank").SpecBadge:IsShown(), "spec badge on Tank");
        H.assertEq(panel.setRow("Tank").SpecText:GetText(), "1", "Tank: spec 1");
        H.assertEq(panel.setRow("DPS").SpecText:GetText(), "2", "DPS: spec 2");
        panel.tab("Events");
        H.assertEq(#panel.bindingRows(), 2, "a row per binding");
        H.assertEq(panel.bindingRow(1).Event:GetText(), "On talents change: " .. gq:GetTalentSpecializations()[1]);
        H.assertEq(panel.bindingRow(1).Info:GetText(), "PvE + PvP");
        H.assertEq(H.dropdownText(panel.bindingRow(1).SetPicker), "Tank", "spec 1 picker shows Tank");
        H.assertEq(H.dropdownText(panel.bindingRow(2).SetPicker), "DPS", "spec 2 picker shows DPS");
        H.assertTrue(GqUiFrame_CbEnableEvents:GetChecked(), "events on");
        panel.tab("Sets");
        panel.close();

        local tankHelm = gq:LoadSlot(1, "Tank");
        local linkBefore = GetInventoryItemLink("player", 1);

        -- spec 1 -> 2
        H.setSpecGroup(2);
        H.assertTrue(GetInventoryItemLink("player", 1) ~= linkBefore, "the link's spec id changed");
        H.assertEq(gq:GetItemString(1), tankHelm, "normalised string unchanged by the spec swap");
        H.advance(5);
        H.assertWearing(H.SET_B, "spec 2 -> DPS");
        H.assertEq(gq:LoadCurrentSetName(), "DPS", "current set follows the spec");
        H.assertTrue(gq:IsSetComplete("DPS"), "DPS complete after the swap");
        H.assertSetMatchesGear(gq, "DPS", "spec 2");
        H.assertTrue(gq:FindItemInBags(tankHelm), "Tank's stored helm string still finds the helm in the bags");

        -- spec 2 -> 1
        H.setSpecGroup(1);
        H.advance(5);
        H.assertWearing(H.SET_A, "spec 1 -> Tank");
        H.assertEq(gq:LoadCurrentSetName(), "Tank");
        H.assertSetMatchesGear(gq, "Tank", "spec 1");

        -- with the real 5 s "Activate ... Spec" cast before the change
        H.setSpecGroup(2, {cast = true});
        H.advance(2);
        H.assertWearing(H.SET_A, "nothing happens during the cast");
        H.advance(6);
        H.assertWearing(H.SET_B, "DPS after the spec cast");

        -- a ring changed on the character sheet while DPS (spec 2) is current goes into DPS only
        H.openCharacterFrame();
        if GqUiFrame and not GqUiFrame:IsShown() then
            GqUiFrame:Show(); -- default "save gear when: GearQuipper menu open"
        end
        H.advance(0.5);
        H.playerEquip("twinRing", 12);
        H.advance(1);
        H.assertEq(gq:LoadSlot(12, "DPS"), gq:GetItemString(12), "hand-equipped ring saved into the spec 2 set");
        H.assertTrue(gq:LoadSlot(12, "Tank") ~= gq:GetItemString(12), "spec 1 set untouched");
        H.closeCharacterFrame();
        H.advance(0.5);

        H.setSpecGroup(1);
        H.advance(5);
        H.assertWearing(H.SET_A, "spec 1 -> Tank again");
        H.setSpecGroup(2);
        H.advance(5);
        H.assertEquipped(12, "twinRing", "spec 2 brings the ring saved into DPS");
        H.assertEq(gq:LoadCurrentSetName(), "DPS");
        H.assertSetMatchesGear(gq, "DPS", "final");
        H.assertCursorEmpty();
        H.assertTotalItems(total);
        H.assertNoUiErrors();
    end,
};
