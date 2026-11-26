-- assert.lua: assertions, the default test character, and logout checks.
-- Assertions raise an error pointing at the scenario line; run.py reports it as the failure reason.
local H = ...;

local function fmt(v)
    if type(v) == "string" then
        return string.format("%q", v);
    end
    return tostring(v);
end

function H.fail(msg, level)
    error(msg, (level or 1) + 1);
end

function H.assertEq(actual, expected, msg)
    if actual ~= expected then
        error((msg and (msg .. ": ") or "") .. "expected " .. fmt(expected) .. ", got " .. fmt(actual), 2);
    end
end

function H.assertTrue(v, msg)
    if not v then
        error(msg or "expected a true value", 2);
    end
end

function H.assertFalse(v, msg)
    if v then
        error((msg or "expected a false value") .. " (got " .. fmt(v) .. ")", 2);
    end
end

local function itemAt(slot)
    if slot == 0 then
        return H.ammo and H.itemsById[H.ammo].key;
    end
    return H.inv[slot] and H.inv[slot].key;
end

-- itemKey nil = the slot must be empty. itemKey may also be an instance (exact physical copy).
function H.assertEquipped(slot, itemKey, msg)
    local actual = itemAt(slot);
    local ok;
    if type(itemKey) == "table" then
        ok = H.inv[slot] == itemKey;
        itemKey = itemKey.key .. " (that exact copy)";
    else
        ok = actual == itemKey;
    end
    if not ok then
        error(string.format("%sslot %d: expected %s, got %s\n%s", msg and (msg .. ": ") or "", slot,
            fmt(itemKey), fmt(actual), H.dumpInventory()), 2);
    end
end

-- The item is in the player's bags (0..4, not bank), `count` copies if given (default: at least one).
function H.assertInBags(itemKey, count, msg)
    local n = 0;
    for _, loc in ipairs(H.find(itemKey)) do
        if loc.kind == "bag" and loc.bag >= 0 and loc.bag <= 4 then
            n = n + 1;
        end
    end
    if (count and n ~= count) or (not count and n == 0) then
        error(string.format("%s%s: expected %s in bags, found %d\n%s", msg and (msg .. ": ") or "", itemKey,
            count and tostring(count) or "at least 1", n, H.dumpInventory()), 2);
    end
end

function H.assertInBank(itemKey, msg)
    for _, loc in ipairs(H.find(itemKey)) do
        if loc.kind == "bag" and H.bags[loc.bag].bank then
            return;
        end
    end
    error((msg and (msg .. ": ") or "") .. itemKey .. " is not in a bank tab\n" .. H.dumpInventory(), 2);
end

-- No equippable item may sit in the quiver, keyring or reagent bag.
function H.assertNoGearInSpecialBags(msg)
    for bagId, bag in pairs(H.bags) do
        if bag.family ~= 0 or bag.keyring or bag.reagent then
            for slot = 1, bag.size do
                local inst = bag.slots[slot];
                if inst and inst.item.equipLoc ~= "" and inst.item.equipLoc ~= "INVTYPE_AMMO" then
                    error(string.format("%s%s ended up in special bag %d (family %d)\n%s", msg and (msg .. ": ") or "",
                        inst.key, bagId, bag.family, H.dumpInventory()), 2);
                end
            end
        end
    end
end

-- No request was refused by the client (wrong slot, wrong bag, bag full, busy, combat...).
function H.assertNoUiErrors(msg)
    if #H.uiErrors > 0 then
        local list = {};
        for _, e in ipairs(H.uiErrors) do
            list[#list + 1] = string.format("%s (t=%.2f)", e.key, e.t);
        end
        error((msg and (msg .. ": ") or "") .. "the client refused requests: " .. table.concat(list, ", "), 2);
    end
end

function H.assertCursorEmpty(msg)
    local inst = H.cursorItem();
    if inst then
        error((msg and (msg .. ": ") or "") .. "an item is still on the cursor: " .. inst.key, 2);
    end
end

function H.assertTotalItems(expected, msg)
    local n = H.totalItems();
    if n ~= expected then
        error(string.format("%sitem count changed: expected %d, have %d (items lost or duplicated)\n%s",
            msg and (msg .. ": ") or "", expected, n, H.dumpInventory()), 2);
    end
end

function H.chatContains(pattern)
    for _, line in ipairs(H.chat) do
        if H.stripColors(line):find(pattern) then
            return true, line;
        end
    end
    return false;
end

function H.assertChat(pattern, msg)
    if not H.chatContains(pattern) then
        error((msg and (msg .. ": ") or "") .. "no chat line matches " .. fmt(pattern) .. "\nchat:\n  " ..
                  table.concat(H.chat, "\n  "), 2);
    end
end

function H.assertChatAny(patterns, msg)
    for _, pattern in ipairs(patterns) do
        if H.chatContains(pattern) then
            return;
        end
    end
    error((msg and (msg .. ": ") or "") .. "no chat line matches any of " .. table.concat(patterns, " | ") ..
              "\nchat:\n  " .. table.concat(H.chat, "\n  "), 2);
end

function H.assertNoChat(pattern, msg)
    local found, line = H.chatContains(pattern);
    if found then
        error((msg and (msg .. ": ") or "") .. "unexpected chat line: " .. H.stripColors(line), 2);
    end
end

function H.clearChat()
    H.chat = {};
end

-- Fails right away if Lua errors were recorded (useful mid-scenario to stop at the first problem).
function H.assertNoErrors(msg)
    if #H.errors > 0 then
        error((msg and (msg .. ": ") or "") .. #H.errors .. " Lua error(s) recorded, first: " .. H.errors[1].msg, 2);
    end
end

function H.log(...)
    local parts = H.pack(...);
    for i = 1, parts.n do
        parts[i] = tostring(parts[i]);
    end
    H.notes[#H.notes + 1] = table.concat(parts, " ", 1, parts.n);
end
H.notes = {};

-- Runs H.advance in small steps until fn() is true or `timeout` seconds passed. Returns fn()'s result.
function H.waitFor(fn, timeout)
    local deadline = H.nowMs + math.floor((timeout or 10) * 1000);
    while H.nowMs < deadline do
        if fn() then
            return true;
        end
        H.advance(0.1);
    end
    return fn();
end

---------------------------------------------------------------------------
-- default character: a level 60 warrior wearing set A, with set B pieces and spare weapons in the bags
---------------------------------------------------------------------------
H.SET_A = {[1] = "headA", [2] = "neckA", [3] = "shoulderA", [4] = "shirt", [5] = "chestA", [6] = "waistA",
    [7] = "legsA", [8] = "feetA", [9] = "wristA", [10] = "handsA", [11] = "ringA", [12] = "ringB", [13] = "trinketA",
    [14] = "trinketB", [15] = "backA", [16] = "sword", [17] = "shield", [18] = "bow", [19] = "tabard"};
H.SET_B_PIECES = {[1] = "headB", [5] = "chestB", [7] = "legsB", [8] = "feetB", [10] = "handsB", [15] = "backB",
    [11] = "ringC", [13] = "trinketC", [16] = "greatsword"};

-- Set B as worn after equipping its pieces over set A: the greatsword (2H) leaves the off-hand empty.
H.SET_B = {};
for slot, itemKey in pairs(H.SET_A) do
    H.SET_B[slot] = itemKey;
end
for slot, itemKey in pairs(H.SET_B_PIECES) do
    H.SET_B[slot] = itemKey;
end
H.SET_B[17] = nil;

-- expected: slot -> item key (missing = empty). Checks slots 1..19.
function H.assertWearing(expected, msg)
    for slot = 1, 19 do
        local actual = H.inv[slot] and H.inv[slot].key;
        if actual ~= expected[slot] then
            error(string.format("%sslot %d: expected %s, got %s\n%s", msg and (msg .. ": ") or "", slot,
                fmt(expected[slot]), fmt(actual), H.dumpInventory()), 2);
        end
    end
end

-- The player drags the set B pieces onto the character sheet.
function H.wearSetBPieces()
    for _, slot in ipairs({1, 5, 7, 8, 10, 11, 13, 15, 16}) do
        H.playerEquip(H.SET_B_PIECES[slot], slot);
    end
    H.advance(0.5);
end

-- gq:QueueSwitch(name), then lets the switch and GQ's clean-up timers run.
function H.switchTo(gq, setName, seconds)
    gq:QueueSwitch(setName);
    H.advance(seconds or 3);
end

-- Map of the item strings GQ stored for a set, checked against what is worn now (normalised strings).
function H.assertSetMatchesGear(gq, setName, msg)
    for slot = 1, 19 do
        local stored, worn = gq:LoadSlot(slot, setName), gq:GetItemString(slot);
        if stored ~= nil and stored ~= worn then
            error(string.format("%sset %s slot %d: stored %s, worn %s", msg and (msg .. ": ") or "", setName, slot,
                fmt(stored), fmt(worn)), 2);
        end
    end
end

function H.setupDefaultCharacter(bagConfig)
    H.setupBags(bagConfig);
    for slot, itemKey in pairs(H.SET_A) do
        H.equip(itemKey, slot);
    end
    H.equip("arrows", 0);
    for bagId = 1, 4 do
        if H.bags[bagId] and H.bags[bagId].family == 1 then
            H.give("arrows", {bag = bagId});
        end
    end
    for _, itemKey in pairs(H.SET_B_PIECES) do
        H.give(itemKey);
    end
    H.give("mace");
    H.give("orb");
    H.give("linen");
    H.give("key", {bag = -1});
end

---------------------------------------------------------------------------
-- logout: SavedVariables must be serialisable and must never contain a secret
---------------------------------------------------------------------------
function H.checkSavedVariables(names)
    local seen = {};
    local function walk(v, path, depth)
        if rawequal(v, H.SECRET) then
            H.recordError("SavedVariables", {msg = "secret value stored in " .. path, trace = ""});
        elseif type(v) == "table" then
            if seen[v] or depth > 40 then
                return;
            end
            seen[v] = true;
            for k, child in pairs(v) do
                if rawequal(k, H.SECRET) then
                    H.recordError("SavedVariables", {msg = "secret used as a key in " .. path, trace = ""});
                else
                    walk(child, path .. "[" .. (type(k) == "string" and string.format("%q", k) or tostring(k)) .. "]",
                        depth + 1);
                end
            end
        elseif type(v) == "function" or type(v) == "userdata" or type(v) == "thread" then
            H.warn("SavedVariables " .. path .. " holds a " .. type(v) .. " (dropped by the client on logout)");
        end
    end
    for _, name in ipairs(names) do
        walk(rawget(_G, name), name, 0);
    end
end

-- Writes the SavedVariables like the client does on logout (Lua source; functions/userdata/secrets dropped).
-- run.py feeds the result to the next session of a scenario with `relog`.
function H.serializeSavedVariables(names)
    local out = {"return {\n"};
    local function value(v, indent)
        local t = type(v);
        if t == "string" then
            return string.format("%q", v);
        elseif t == "number" or t == "boolean" then
            return tostring(v);
        elseif t == "table" then
            local keys = {};
            for k in pairs(v) do
                local kt = type(k);
                if kt == "string" or kt == "number" or kt == "boolean" then
                    keys[#keys + 1] = k;
                end
            end
            table.sort(keys, function(a, b)
                if type(a) == type(b) and type(a) ~= "boolean" then
                    return a < b;
                end
                return type(a) < type(b);
            end);
            local parts = {"{\n"};
            for _, k in ipairs(keys) do
                local s = value(v[k], indent .. "  ");
                if s then
                    local ks = type(k) == "string" and string.format("%q", k) or tostring(k);
                    parts[#parts + 1] = indent .. "  [" .. ks .. "] = " .. s .. ",\n";
                end
            end
            parts[#parts + 1] = indent .. "}";
            return table.concat(parts);
        end
        return nil;
    end
    for _, name in ipairs(names) do
        local v = rawget(_G, name);
        if v ~= nil and not rawequal(v, H.SECRET) then
            out[#out + 1] = "  " .. name .. " = " .. (value(v, "  ") or "nil") .. ",\n";
        end
    end
    out[#out + 1] = "}\n";
    return table.concat(out);
end
