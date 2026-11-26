-- scope stuff
gearquipper = gearquipper or {};
local c = gearquipper;

local quickBars;

-- Geometry of Blizzard's equipment flyout (Blizzard_FrameXML/Camelot/EquipmentFlyout.lua, forever branch: EFITEM_*,
-- EQUIPMENTFLYOUT_BORDERWIDTH): 37 px item buttons, 4 px apart in a row, rows 42 px apart, 3 px border.
local BUTTON_SIZE, BUTTON_SPACING, ROW_SPACING, BAR_PADDING = 37, 4, 5, 3;
local BAR_GAP = 4; -- between the paper-doll slot and its bar
local MOUSE_SLACK = BAR_GAP + 4; -- the bar stays open while the mouse crosses the gap
local AMMO_SCALE = 26 / 37; -- the ammo bar keeps its smaller (26 px) buttons

-- Stock look: the flyout background, cut like EquipmentFlyout_Show does. Pieces are {left, right, top, bottom, width,
-- height}; the first one sits 5 px left of and 4 px above the bar.
local FLYOUT_TEXTURE = "Interface\\PaperDollInfoFrame\\UI-GearManager-Flyout";
local FLYOUT_OFFSET_X, FLYOUT_OFFSET_Y = -5, 4;
local FLYOUT_ONESLOT = {{0, 0.09765625, 0.5546875, 0.77734375, 25, 54},
    {0.41796875, 0.51171875, 0.5546875, 0.77734375, 24, 54}};
local FLYOUT_ROW_LEFT = {0, 0.16796875, 0.5546875, 0.77734375, 43, 54};
local FLYOUT_ROW_CENTER = {0.16796875, 0.328125, 0.5546875, 0.77734375, 41, 54};
local FLYOUT_ROW_RIGHT = {0.328125, 0.51171875, 0.5546875, 0.77734375, 47, 54};
-- Blizzard stacks rows of five (214 px wide multirow pieces); GQ's one-button columns take the left and the right
-- 25 px of each row piece, as the one-slot piece does with the one-row strip.
local FLYOUT_COLUMN_TOP = {{0, 0.09765625, 0, 0.19140625, 25, 49}, {0.73828125, 0.8359375, 0, 0.19140625, 25, 49}};
local FLYOUT_COLUMN_MIDDLE = {{0, 0.09765625, 0.19140625, 0.35546875, 25, 42},
    {0.73828125, 0.8359375, 0.19140625, 0.35546875, 25, 42}};
local FLYOUT_COLUMN_BOTTOM = {{0, 0.09765625, 0.35546875, 0.546875, 25, 49},
    {0.73828125, 0.8359375, 0.35546875, 0.546875, 25, 49}};
-- the glow Blizzard's flyout puts on the paper-doll slot it belongs to
local SLOT_GLOW_TEXTURE = "Interface\\PaperDollInfoFrame\\UI-GearManager-ItemButton-Highlight";
local SLOT_GLOW_SIZE, SLOT_GLOW_COORD = 50, 0.78125;

-- Slots the game lets you change in combat (Blizzard's INVSLOTS_EQUIPABLE_IN_COMBAT: main hand, off hand, ranged).
local combatSlots = INVSLOTS_EQUIPABLE_IN_COMBAT or {
    [INVSLOT_MAINHAND] = true,
    [INVSLOT_OFFHAND] = true,
    [INVSLOT_RANGED] = true
};

local queuedEquips = {}; -- [slotId] = {itemString, link}: quick-slot clicks waiting for the end of combat
local lastCombatEquip; -- last in-combat quick-slot equip, re-queued if the game blocks it (ADDON_ACTION_BLOCKED)

-- Blizzard's own equipment flyout on the Forever paper doll (Alt + hover, or the Equipment Manager's arrow buttons).
local function IsBlizzardFlyoutShown()
    return EquipmentFlyoutFrame and EquipmentFlyoutFrame:IsShown();
end

-- Mouse on the paper-doll slot, the bar (with a little slack for the gap between them) or one of its buttons.
local function IsMouseOverBar(bar)
    if bar.parent:IsMouseOver() or bar:IsMouseOver(MOUSE_SLACK, -MOUSE_SLACK, -MOUSE_SLACK, MOUSE_SLACK) then
        return true;
    end
    for _, quickSlot in pairs(bar.slots or {}) do
        if quickSlot:IsShown() and quickSlot:IsMouseOver() then
            return true;
        end
    end
    return false;
end

local function IsBlizzardFlyoutModifierDown()
    if IsModifiedClick then
        return IsModifiedClick("SHOWITEMFLYOUT");
    end
    return IsAltKeyDown();
end

local function IsPlayerBag(bagId)
    for _, id in ipairs(c:GetBagIds()) do
        if id == bagId then
            return true;
        end
    end
end

local function IsEquippedIn(slotId, itemString)
    if slotId == INVSLOT_AMMO then
        return GetInventoryItemID("player", INVSLOT_AMMO) == tonumber(c:GetItemId(itemString));
    end
    return c:GetItemString(slotId) == itemString;
end

-- Bag location of itemString: the remembered bag slot if it still holds the item, else the first match in the bags.
local function FindBagLocation(itemString, bagId, bagSlotId)
    if bagId and bagSlotId and IsPlayerBag(bagId) and
        c:GetItemString(c:GetContainerItemLink(bagId, bagSlotId)) == itemString then
        return bagId, bagSlotId;
    end
    local list = c:FindItemInBags(itemString);
    if list and list[1] then
        return list[1].bagId, list[1].slotId;
    end
end

-- Other equipped slot holding itemString (ring, trinket or one-hander swaps).
local function FindEquippedSlot(itemString, slotId, hintSlotId)
    if hintSlotId and hintSlotId ~= slotId and c:GetItemString(hintSlotId) == itemString then
        return hintSlotId;
    end
    for equippedSlotId = INVSLOT_FIRST_EQUIPPED or 1, INVSLOT_LAST_EQUIPPED or 19 do
        if equippedSlotId ~= slotId and c:GetItemString(equippedSlotId) == itemString then
            return equippedSlotId;
        end
    end
end

-- Equips itemString into slotId the way Blizzard's equipment flyout does: pick up the exact bag slot (or the other
-- equipped slot) and drop it on the paper-doll slot, so identical copies and uncached items work.
local function EquipItemToSlot(slotId, itemString, bagId, bagSlotId, equippedSlotId)
    ClearCursor();

    if slotId == INVSLOT_AMMO then
        -- ammo workaround (stacks)
        c:EquipItemByName(tonumber(c:GetItemId(itemString)) or itemString);
        return true;
    end

    local fromSlotId = equippedSlotId and FindEquippedSlot(itemString, slotId, equippedSlotId);
    if fromSlotId then
        PickupInventoryItem(fromSlotId);
    else
        bagId, bagSlotId = FindBagLocation(itemString, bagId, bagSlotId);
        if not bagId then
            fromSlotId = FindEquippedSlot(itemString, slotId);
            if not fromSlotId then
                return false;
            end
            PickupInventoryItem(fromSlotId);
        else
            c:PickupContainerItem(bagId, bagSlotId);
        end
    end

    if CursorHasItem() then
        PickupInventoryItem(slotId);
    end
    -- a refused equip leaves the item on the cursor; the client already showed its error
    if CursorHasItem() then
        ClearCursor();
    end
    return true;
end

local function QueueEquip(slotId, itemString, link, notify)
    queuedEquips[slotId] = {
        itemString = itemString,
        link = link
    };
    if notify and GQ_OPTIONS[c.OPT_NOTIFYQUEUES] then
        c:Println(c:GetText("Switch to \"%s\" queued.", link or itemString));
    end
end

local function EquipQueuedItems()
    if c:IsInCombat() then
        return; -- the next PLAYER_REGEN_ENABLED retries
    end
    if c:IsSwitching() then
        C_Timer.After(0.5, EquipQueuedItems);
        return;
    end

    local queued = queuedEquips;
    queuedEquips = {};
    for slotId, entry in pairs(queued) do
        if not IsEquippedIn(slotId, entry.itemString) then
            EquipItemToSlot(slotId, entry.itemString);
        end
    end
end

-- Engine combat rule: out of combat anything, in combat only weapons, and nothing once the game blocked an
-- in-combat equip (c.combatEquipBlocked). Everything else waits for the end of combat.
local function EquipQuickSlotItem(slotId, itemString, link, bagId, bagSlotId, equippedSlotId)
    if c:IsInCombat() then
        if not combatSlots[slotId] or c.combatEquipBlocked then
            QueueEquip(slotId, itemString, link, true);
            return;
        end
        lastCombatEquip = {
            slotId = slotId,
            itemString = itemString,
            link = link,
            time = GetTime()
        };
    end
    EquipItemToSlot(slotId, itemString, bagId, bagSlotId, equippedSlotId);
end

local eventFrame = CreateFrame("Frame");
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED");
eventFrame:RegisterEvent("ADDON_ACTION_BLOCKED");
eventFrame:RegisterEvent("ADDON_ACTION_FORBIDDEN");
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_REGEN_ENABLED" then
        lastCombatEquip = nil;
        if next(queuedEquips) then
            C_Timer.After(c:GetHomeLatency(100) / 1000, EquipQueuedItems);
        end
    elseif arg1 == c.addonName and lastCombatEquip and GetTime() - lastCombatEquip.time < 1 then
        -- ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN caused by an in-combat quick-slot equip
        if not c.combatEquipBlocked then
            c.combatEquipBlocked = true;
            c:Println(c:GetText(
                "Weapon swaps in combat are blocked by the game; the switch will happen when combat ends."));
        end
        QueueEquip(lastCombatEquip.slotId, lastCombatEquip.itemString, lastCombatEquip.link, false);
        lastCombatEquip = nil;
    end
end);

-- Only one flyout at a time: Blizzard's flyout is opened on purpose (Alt or the arrow buttons), so GQ's bars yield.
if EquipmentFlyoutFrame then
    EquipmentFlyoutFrame:HookScript("OnShow", function()
        c:CloseQuickBars();
    end);
end

function c:CreateQuickBar(slotId)
    local parent = _G["Character" .. c:GetSlotInfo(slotId)];
    if not parent then
        return;
    end
    local frame = CreateFrame("Frame", "GQ_QuickBar_" .. slotId, parent);

    frame:SetFrameStrata("HIGH");
    frame:SetScript("OnHide", function(self)
        c:HighlightItemsInBags();
        -- a hover bar never owned the cursor; clearing it would drop whatever the player is holding
        if not self.hoverOpened then
            ClearCursor();
        end
        self.hoverOpened = nil;
    end);
    frame:SetScript("OnUpdate", function(self, elapsed)
        if not self.hoverOpened then
            return;
        end
        self.hoverElapsed = (self.hoverElapsed or 0) + elapsed;
        if self.hoverElapsed >= 0.1 then
            self.hoverElapsed = 0;
            if not IsMouseOverBar(self) then
                c:CloseQuickBar(self.slotId);
            end
        end
    end);

    frame.parent = parent;
    frame.slotId = slotId;
    frame.vertical = c:IsWeaponSlot(slotId);

    -- The background is a child frame: skins restyle (and later re-strip) the frames handed to them, and this one
    -- only ever holds the flyout pieces. Under a skin it becomes an opaque panel over EllesmereUI's slot texts.
    frame.border = CreateFrame("Frame", nil, frame);
    frame.border:SetAllPoints(frame);
    frame.border:SetFrameLevel(frame:GetFrameLevel());
    frame.flyoutPieces = {};
    c:Skin("panel", frame.border);

    frame.slotGlowFrame = CreateFrame("Frame", nil, frame);
    frame.slotGlowFrame:SetAllPoints(parent);
    frame.slotGlow = frame.slotGlowFrame:CreateTexture(nil, "OVERLAY");
    frame.slotGlow:SetTexture(SLOT_GLOW_TEXTURE);
    frame.slotGlow:SetTexCoord(0, SLOT_GLOW_COORD, 0, SLOT_GLOW_COORD);
    frame.slotGlow:SetSize(SLOT_GLOW_SIZE, SLOT_GLOW_SIZE);
    frame.slotGlow:SetPoint("CENTER");

    -- weapon slots (and ammo) open downward, the others to the right; the buttons line up with the slot's edge
    if frame.vertical then
        frame:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", -BAR_PADDING, -BAR_GAP);
    else
        frame:SetPoint("TOPLEFT", parent, "TOPRIGHT", BAR_GAP, BAR_PADDING);
    end
    if slotId == INVSLOT_AMMO then
        frame:SetScale(AMMO_SCALE);
    end

    return frame;
end

local function FlyoutRows(count, vertical)
    if count == 1 then
        return {FLYOUT_ONESLOT};
    end
    local rows, row = {}, {};
    if vertical then
        rows[1] = FLYOUT_COLUMN_TOP;
        for i = 2, count - 1 do
            rows[i] = FLYOUT_COLUMN_MIDDLE;
        end
        rows[count] = FLYOUT_COLUMN_BOTTOM;
        return rows;
    end
    row[1] = FLYOUT_ROW_LEFT;
    for i = 2, count - 1 do
        row[i] = FLYOUT_ROW_CENTER;
    end
    row[count] = FLYOUT_ROW_RIGHT;
    return {row};
end

-- Stock look only: a skin backend draws its own panel on .border, so the flyout pieces and the slot glow stay
-- hidden (checked on every show, as a skin can switch on after the bar was built).
local function LayoutFlyoutBackground(quickBar, count)
    local skinned = c:GetSkinBackend() ~= nil;
    local pieces, used = quickBar.flyoutPieces, 0;
    if not skinned then
        local rowStart;
        for _, row in ipairs(FlyoutRows(count, quickBar.vertical)) do
            local previous;
            for _, piece in ipairs(row) do
                used = used + 1;
                local texture = pieces[used];
                if not texture then
                    texture = quickBar.border:CreateTexture(nil, "BACKGROUND");
                    texture:SetTexture(FLYOUT_TEXTURE);
                    pieces[used] = texture;
                end
                texture:ClearAllPoints();
                texture:SetTexCoord(piece[1], piece[2], piece[3], piece[4]);
                texture:SetSize(piece[5], piece[6]);
                if previous then
                    texture:SetPoint("TOPLEFT", previous, "TOPRIGHT");
                elseif rowStart then
                    texture:SetPoint("TOPLEFT", rowStart, "BOTTOMLEFT");
                else
                    texture:SetPoint("TOPLEFT", quickBar.border, "TOPLEFT", FLYOUT_OFFSET_X, FLYOUT_OFFSET_Y);
                end
                texture:Show();
                rowStart = previous and rowStart or texture;
                previous = texture;
            end
        end
    end
    for i = used + 1, #pieces do
        pieces[i]:Hide();
    end
    quickBar.slotGlowFrame:SetShown(not skinned);
end

local function LayoutQuickBar(quickBar, count)
    local columns, rows = count, 1;
    if quickBar.vertical then
        columns, rows = 1, count;
    end
    quickBar:SetSize(BAR_PADDING * 2 + columns * BUTTON_SIZE + (columns - 1) * BUTTON_SPACING,
        BAR_PADDING * 2 + rows * BUTTON_SIZE + (rows - 1) * ROW_SPACING);
    LayoutFlyoutBackground(quickBar, count);
end

-- Quick slots are the intrinsic ItemButton (not secure: they equip from Lua and must hide in combat).
function c:CreateQuickSlot(slotId, index)
    local quickBar = quickBars[slotId];
    local frame = CreateFrame("ItemButton", "GQ_QuickSlot_" .. slotId .. "_" .. index, quickBar);
    -- no quick-slot frame art: the bar's background holds the buttons, the rarity ring (IconBorder) marks them
    frame:ClearNormalTexture();
    frame:ClearPushedTexture();

    if quickBar.vertical then
        frame:SetPoint("TOPLEFT", quickBar, "TOPLEFT", BAR_PADDING,
            -BAR_PADDING - (index - 1) * (BUTTON_SIZE + ROW_SPACING));
    else
        frame:SetPoint("TOPLEFT", quickBar, "TOPLEFT", BAR_PADDING + (index - 1) * (BUTTON_SIZE + BUTTON_SPACING),
            -BAR_PADDING);
    end

    frame:SetScript("OnEnter", function(self)
        if self.link or self.itemString then
            GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT");
            GameTooltip:SetHyperlink(self.link or self.itemString);
            GameTooltip:Show();
        end
    end);
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide();
    end);
    frame:SetScript("OnClick", function(self, button)
        if button == "LeftButton" and self.itemString then
            -- read the slot first: ClearCursor fires ITEM_UNLOCKED synchronously, which closes (and clears) the bar
            local itemString, link = self.itemString, self.link;
            local bagId, bagSlotId, equippedSlotId = self.bagId, self.bagSlotId, self.equippedSlotId;
            ClearCursor();

            if not equippedSlotId and not FindBagLocation(itemString, bagId, bagSlotId) and c:IsAtBank() then
                -- item not in bag -> check in bank
                local bagSpaceCache = c:GetBagSpace();
                if c:GetItemFromBank(itemString, bagSpaceCache) then
                    C_Timer.After(c:GetHomeLatency(100) / 1000, function()
                        EquipQuickSlotItem(slotId, itemString, link);
                    end);
                end
            else
                EquipQuickSlotItem(slotId, itemString, link, bagId, bagSlotId, equippedSlotId);
            end

            c:CloseQuickBar(slotId);
            GameTooltip:Hide();
        end
    end);

    return frame;
end

function c:AddQuickSlot(slotId, slotIndex, itemEntry)
    local quickBar = quickBars[slotId];
    quickBar.slots[slotIndex] = quickBar.slots[slotIndex] or c:CreateQuickSlot(slotId, slotIndex);
    local quickSlot = quickBar.slots[slotIndex];

    local itemString = c:GetItemString(itemEntry[c.ITEM_STRING]);
    local bagId, bagSlotId, equippedSlotId;
    local _, link, quality, count, texture;
    if itemEntry[c.ITEM_BAG_ID] then
        bagId, bagSlotId = itemEntry[c.ITEM_BAG_ID], itemEntry[c.ITEM_SLOT_ID];
        texture, count, _, quality, _, _, link = c:GetContainerItemInfo(bagId, bagSlotId);
    else
        -- equipped in another slot
        equippedSlotId = itemEntry[c.ITEM_SLOT_ID];
        if equippedSlotId and GetInventoryItemLink("player", equippedSlotId) then
            link = GetInventoryItemLink("player", equippedSlotId);
            texture = GetInventoryItemTexture("player", equippedSlotId);
            quality = GetInventoryItemQuality("player", equippedSlotId);
        else
            _, link, quality, _, _, _, _, _, _, texture = c:GetItemInfo(itemString);
            if not link then
                c:RequestItemData(itemString);
            end
        end
        count = 1;
    end

    quickSlot.link = link;
    quickSlot.itemString = itemString;
    quickSlot.bagId, quickSlot.bagSlotId, quickSlot.equippedSlotId = bagId, bagSlotId, equippedSlotId;
    SetItemButtonTexture(quickSlot, texture);
    SetItemButtonCount(quickSlot, count);
    SetItemButtonQuality(quickSlot, quality, link);
    -- after the quality: a skin re-reads the rarity border from it
    c:Skin("itembutton", quickSlot);

    quickSlot:Show();
end

local function ClearQuickSlots(quickBar)
    for index, slot in pairs(quickBar.slots) do
        slot.itemString = nil;
        slot.link = nil;
        slot.bagId, slot.bagSlotId, slot.equippedSlotId = nil, nil, nil;
        slot:Hide();
    end
end

local function CanOpenQuickBar(slotId)
    -- Blizzard's flyout has priority while it is open (see the OnShow hook above).
    return slotId and c:GetSlotInfo(slotId) and not c:IsInCombat() and not c:IsDead() and not IsBlizzardFlyoutShown();
end

-- hover: opened by mouse-over (closes when the mouse leaves, keeps the slot's tooltip, no bag dimming);
-- otherwise opened by a click or a pick-up and stays until GQ's usual close triggers.
local function ShowQuickBar(slotId, hover)
    -- each item once (identical copies, ammo stacks); the ammo bar skips the ammo type that is already equipped
    local entries, itemStrings = {}, {};
    local equippedAmmoId = slotId == INVSLOT_AMMO and GetInventoryItemID("player", INVSLOT_AMMO);
    for _, itemEntry in ipairs(c:GetMatchingItems(slotId) or {}) do
        local itemString = c:GetItemString(itemEntry[c.ITEM_STRING]);
        if itemString ~= c.VALUE_NONE and not tContains(itemStrings, itemString) and
            not (equippedAmmoId and tonumber(c:GetItemId(itemString)) == equippedAmmoId) then
            tinsert(entries, itemEntry);
            tinsert(itemStrings, itemString);
        end
    end

    local index = #entries;
    if index > 0 then
        quickBars = quickBars or {};
        quickBars[slotId] = quickBars[slotId] or c:CreateQuickBar(slotId);
        if not quickBars[slotId] then
            return;
        end
        quickBars[slotId].slots = quickBars[slotId].slots or {};
        ClearQuickSlots(quickBars[slotId]);

        for slotIndex, itemEntry in ipairs(entries) do
            c:AddQuickSlot(slotId, slotIndex, itemEntry);
        end

        LayoutQuickBar(quickBars[slotId], index);
        quickBars[slotId].hoverOpened = hover and true or nil;
        quickBars[slotId].hoverElapsed = 0;
        quickBars[slotId]:Show();

        if not hover then
            c:HighlightItemsInBags(itemStrings);
            GameTooltip:Hide();
        end

        return quickBars[slotId];
    end
end

-- Keeps the slot's tooltip clear of its open hover bar, the way Blizzard moves it beside its own flyout
-- (EquipmentFlyout_SetTooltipAnchor): bottom-left corner just past the bar's far end.
local function AnchorTooltipBesideBar(slotButton)
    if not quickBars or not slotButton or not GameTooltip:IsOwned(slotButton) then
        return;
    end
    for _, quickBar in pairs(quickBars) do
        if quickBar.parent == slotButton and quickBar.hoverOpened and quickBar:IsShown() then
            GameTooltip:ClearAllPoints();
            GameTooltip:SetPoint("BOTTOMLEFT", quickBar.border, "BOTTOMRIGHT", 6, -6);
            return;
        end
    end
end

-- The slot re-runs PaperDollItemSlotButton_OnEnter several times a second (its UpdateTooltip), which re-anchors the
-- tooltip on the slot; a post-hook puts it back beside the bar each time.
local tooltipHookInstalled;
local function InstallTooltipHook()
    if not tooltipHookInstalled and type(PaperDollItemSlotButton_OnEnter) == "function" then
        hooksecurefunc("PaperDollItemSlotButton_OnEnter", AnchorTooltipBesideBar);
        tooltipHookInstalled = true;
    end
end
InstallTooltipHook();

-- Hovering a paper-doll slot shows its bar (as EqManager does); click and pick-up keep working as in GQ.
-- Holding the flyout modifier (Alt) leaves the slot to Blizzard's own flyout.
function c:HoverQuickBar(slotId)
    if not CanOpenQuickBar(slotId) or IsBlizzardFlyoutModifierDown() or CursorHasItem() or c:IsSwitching() then
        return;
    end
    if quickBars and quickBars[slotId] and quickBars[slotId]:IsShown() then
        return;
    end
    if quickBars then
        for otherSlotId in pairs(quickBars) do
            if otherSlotId ~= slotId then
                c:CloseQuickBar(otherSlotId);
            end
        end
    end
    local quickBar = ShowQuickBar(slotId, true);
    if quickBar then
        InstallTooltipHook();
        AnchorTooltipBesideBar(quickBar.parent);
    end
end

local pendingOpens = {};

-- An empty slot opens at once (click on the slot). A filled slot opens when the player picks its item up
-- (ITEM_LOCKED). That event is synchronous and also fires inside every swap made by GQ, Blizzard's flyout or the
-- Equipment Manager, so the decision waits one frame: only a pick-up still holds the slot's item on the cursor.
function c:OpenQuickBar(slotId)
    if not CanOpenQuickBar(slotId) then
        return;
    end
    if not GetInventoryItemID("player", slotId) then
        return ShowQuickBar(slotId);
    end
    if not pendingOpens[slotId] then
        pendingOpens[slotId] = true;
        C_Timer.After(0, function()
            pendingOpens[slotId] = nil;
            local cursorType, cursorItemId = GetCursorInfo();
            if CanOpenQuickBar(slotId) and cursorType == "item" and cursorItemId ==
                GetInventoryItemID("player", slotId) then
                ShowQuickBar(slotId);
            end
        end);
    end
end

-- Quick slots are plain (not secure) buttons, so bars can also close in combat and after death.
function c:CloseQuickBars()
    if quickBars then
        for slotId, quickBar in pairs(quickBars) do
            c:CloseQuickBar(slotId);
        end
    end
end

function c:CloseQuickBar(slotId)
    if quickBars and quickBars[slotId] then
        quickBars[slotId]:Hide();
        ClearQuickSlots(quickBars[slotId]);
        quickBars[slotId].parent.quickbar = nil;
    end
end
