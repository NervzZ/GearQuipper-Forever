-- (g) Combat: an armour set requested in combat is queued and applied when combat ends; a weapons-only set swaps
-- in combat; when the game blocks item pickups in combat (H.blockCombatPickups), the weapons-only switch is queued
-- and applied after combat, with no Lua errors and without saving the wrong items into the sets.
return function(H, gq)
    H.advance(1);
    gq:SaveSet("Tank", false);
    H.wearSetBPieces();
    gq:SaveSet("DPS", false);
    H.switchTo(gq, "Tank");
    H.playerEquip("mace", 16);
    H.advance(0.5);
    gq:SaveSet("TankMace", false); -- differs from Tank in the main hand only
    H.switchTo(gq, "Tank");
    H.assertWearing(H.SET_A, "start");
    local tankSword, maceString = gq:LoadSlot(16, "Tank"), gq:LoadSlot(16, "TankMace");

    -- armour set in combat: queued
    H.setCombat(true);
    gq:QueueSwitch("DPS");
    H.advance(2);
    H.assertWearing(H.SET_A, "nothing changes in combat");
    H.setCombat(false);
    H.advance(4);
    H.assertWearing(H.SET_B, "DPS applied after combat");
    H.assertEq(gq:LoadCurrentSetName(), "DPS");
    H.switchTo(gq, "Tank");

    -- weapons-only set in combat: swaps right away
    H.setCombat(true);
    gq:QueueSwitch("TankMace");
    H.advance(2);
    H.assertEquipped(16, "mace", "weapon swap in combat");
    H.assertEquipped(1, "headA");
    H.setCombat(false);
    H.advance(3);
    H.assertEq(gq:LoadCurrentSetName(), "TankMace");

    -- the game blocks item pickups by addons in combat
    H.blockCombatPickups = true;
    H.setCombat(true);
    gq:QueueSwitch("Tank");
    H.advance(2);
    H.assertTrue(#H.blocked > 0, "the mock blocked a pickup");
    H.assertEquipped(16, "mace", "nothing moved while blocked");
    H.assertCursorEmpty("blocked switch");
    gq:QueueSwitch("TankMace"); -- a second request while blocked is harmless
    gq:QueueSwitch("Tank");
    H.advance(1);
    H.setCombat(false);
    H.advance(4);
    H.assertEquipped(16, "sword", "Tank applied after combat");
    H.assertWearing(H.SET_A, "Tank after the blocked combat switch");
    H.assertEq(gq:LoadCurrentSetName(), "Tank");
    H.assertTrue(gq.combatEquipBlocked, "GQ remembered that combat swaps are blocked");
    H.assertEq(gq:LoadSlot(16, "Tank"), tankSword, "Tank's main hand not overwritten by the failed switch");
    H.assertEq(gq:LoadSlot(16, "TankMace"), maceString, "TankMace's main hand not overwritten");

    -- once known blocked, weapons-only switches in combat are queued without trying
    local blockedBefore = #H.blocked;
    H.setCombat(true);
    gq:QueueSwitch("TankMace");
    H.advance(2);
    H.assertEquipped(16, "sword", "queued, not attempted");
    H.assertEq(#H.blocked, blockedBefore, "no further blocked pickups");
    H.setCombat(false);
    H.advance(4);
    H.assertEquipped(16, "mace", "applied after combat");
    H.assertCursorEmpty();
end
