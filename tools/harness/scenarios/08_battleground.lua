-- (h) Battleground restrictions: inside a BG UnitIsAFK/UnitIsDND and non-group unit identity are secret and
-- PLAYER_FLAGS_CHANGED fires for nameplates. No Lua error, no secret escaping the compat layer, no AFK binding
-- fired - while the BG-enter binding still works.
return function(H, gq)
    H.advance(1);
    gq:SaveSet("Tank", false);
    H.playerEquip("orb", 17);
    H.advance(0.5);
    gq:SaveSet("PvP", false); -- Tank with the orb
    H.wearSetBPieces();
    gq:SaveSet("DPS", false);
    H.switchTo(gq, "Tank");
    H.assertWearing(H.SET_A, "start");

    gq:SetEventsEnabled(true);
    local function bind(eventType, setName)
        gq:SaveEventBinding({[gq.FIELD_TYPE] = eventType, [gq.FIELD_NAME] = setName, [gq.FIELD_PVE] = true,
            [gq.FIELD_PVP] = true});
    end
    bind(gq.EVENT_AFK_ENABLE, "DPS");
    bind(gq.EVENT_BG_ENTER, "PvP");

    H.setZone("wsg"); -- loading screen, PvP-match restriction on
    H.addNameplate("nameplate4");
    H.fireUnit("PLAYER_FLAGS_CHANGED", "nameplate4");
    H.fireUnit("UNIT_AURA", "nameplate4", {isFullUpdate = true});
    H.fireUnit("UNIT_FACTION", "nameplate4");
    H.player.afk = true; -- the server flags the player AFK; inside the BG the client only shows a secret
    H.fireUnit("PLAYER_FLAGS_CHANGED", "player");
    H.fireUnit("UNIT_AURA", "player", {isFullUpdate = true});
    H.advance(4);

    H.assertEquipped(17, "orb", "BG-enter binding switched to PvP");
    H.assertFalse(H.inv[16] and H.inv[16].key == "greatsword", "AFK binding must not fire inside the BG");
    H.log("secret values handed out inside the BG:", #H.secretReads);

    -- leave the BG: restriction off; the (now readable) AFK flag may fire the binding - no errors either way
    H.player.afk = false;
    H.setZone("stormwind");
    H.fireUnit("PLAYER_FLAGS_CHANGED", "player");
    H.advance(4);
    H.assertCursorEmpty();
end
