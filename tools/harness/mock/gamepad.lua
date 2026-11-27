-- gamepad.lua: the button sequence of Blizzard's popups on the forever branch
-- (Blizzard_GamepadSharedUtility/InputSequence/InputSequence.lua, Blizzard_StaticPopup_Game/GameDialog.lua:30-36,
-- 437-445). Each popup frame StaticPopup2..4 (mock/merchant.lua) has its GamepadSequence. Completing the sequence
-- enables Yes (OnSequenceComplete) and turns the sequence's bindings off. The index is never reset (ResetButtons runs
-- only on a wrong button, and on the real client a press after completion is a Lua error in Blizzard's binding), so
-- the sequence works once per popup frame and IsSequenceValid() stays true for later popups on that frame. Its bindings
-- are on while a requiresConfirmation popup is shown with H.gamepadUI (OnGainGamepadFocus), off once it hides.
--   H.gamepadConfirm(dialog)  the player enters the sequence; true when that completed it (replaces merchant.lua's)
local H = ...;

local SEQUENCE = {"PADFUP", "PADLSHOULDER", "PADFDOWN", "PADFLEFT", "PADRSHOULDER"};

local SequenceMixin = {};

function SequenceMixin:EnableBindings()
    self.bindingsActive = true;
end

function SequenceMixin:DisableBindings()
    self.bindingsActive = false;
end

function SequenceMixin:ResetButtons()
    self.currentSequenceIndex = 1;
end

function SequenceMixin:ProcessButton(buttonName)
    if self.sequenceButtonNames[self.currentSequenceIndex] == buttonName then
        self.currentSequenceIndex = self.currentSequenceIndex + 1;
    else
        self:ResetButtons();
    end
    if self:IsSequenceValid() then
        self:DisableBindings();
        if self.onSequenceComplete then
            self.onSequenceComplete();
        end
    end
end

function SequenceMixin:IsSequenceValid()
    return self.currentSequenceIndex > #self.sequenceButtonNames;
end

for i = 2, 4 do
    local dialog = _G["StaticPopup" .. i];
    local sequence = Mixin(CreateFrame("Frame", nil, dialog), SequenceMixin);
    sequence.currentSequenceIndex, sequence.sequenceButtonNames = 1, SEQUENCE;
    sequence.onSequenceComplete = function()
        dialog:GetButton1():Enable();
    end;
    sequence:Hide();
    dialog.GamepadSequence = sequence;
    dialog:HookScript("OnShow", function(self)
        local info = self.which and StaticPopupDialogs[self.which];
        local confirm = info and info.requiresConfirmation and H.gamepadUI;
        sequence:SetShown(confirm and true or false);
        if confirm then
            sequence:EnableBindings();
        end
    end);
    dialog:HookScript("OnHide", function()
        sequence:DisableBindings();
    end);
end

function H.gamepadConfirm(dialog)
    local sequence = dialog.GamepadSequence;
    if not dialog:IsShown() or not sequence.bindingsActive or sequence:IsSequenceValid() then
        return false;
    end
    for _, buttonName in ipairs(sequence.sequenceButtonNames) do
        sequence:ProcessButton(buttonName);
    end
    return sequence:IsSequenceValid();
end
