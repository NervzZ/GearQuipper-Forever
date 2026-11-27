-- colorpicker.lua: Blizzard_ColorPickerFrame of the forever branch (Mainline/ColorPickerFrame.lua; not load-on-demand).
-- ColorPickerFrame with Content.ColorPicker (a ColorSelect: SetColorRGB fires OnColorSelect like a drag on the wheel),
-- Content.ColorSwatchCurrent / ColorSwatchOriginal, Footer.OkayButton / CancelButton and the mixin API:
-- SetupColorPickerAndShow{r, g, b, swatchFunc, cancelFunc, hasOpacity, opacityFunc, opacity, extraInfo, swatch},
-- GetColorRGB, GetColorAlpha, GetPreviousValues, GetExtraInfo.
-- As in game: every colour change runs swatchFunc (also the initial colour the setup puts on the wheel); Okay runs
-- swatchFunc once more and hides; Cancel, Escape and a mouse click outside the frame (GLOBAL_MOUSE_DOWN) run
-- cancelFunc(previousValues) and hide.
-- Scenario helpers: H.colorPickerShown() H.colorPickerSelect(r, g, b) H.colorPickerOkay() H.colorPickerCancel()
-- H.colorPickerEscape() H.colorPickerClickOutside()
local H = ...;
local P = H.widgetState;

H.extendClass("ColorSelect", {
    SetColorRGB = function(self, r, g, b)
        P[self].colorRGB = {r, g, b};
        H.fireScript(self, "OnColorSelect", r, g, b);
    end,
    GetColorRGB = function(self)
        local rgb = P[self].colorRGB or {1, 1, 1};
        return rgb[1], rgb[2], rgb[3];
    end,
    SetColorAlpha = function(self, a)
        P[self].colorAlpha = a;
    end,
    GetColorAlpha = function(self)
        return P[self].colorAlpha or 1;
    end,
});

local f = CreateFrame("Frame", "ColorPickerFrame", UIParent);
f:SetFrameStrata("DIALOG");
f:Hide();
f.Content = CreateFrame("Frame", nil, f);
f.Content.ColorPicker = CreateFrame("ColorSelect", nil, f.Content);
f.Content.ColorSwatchCurrent = f.Content:CreateTexture(nil, "ARTWORK");
f.Content.ColorSwatchOriginal = f.Content:CreateTexture(nil, "ARTWORK");
f.Footer = CreateFrame("Frame", nil, f);
f.Footer.OkayButton = CreateFrame("Button", nil, f.Footer, "UIPanelButtonTemplate");
f.Footer.CancelButton = CreateFrame("Button", nil, f.Footer, "UIPanelButtonTemplate");

ColorPickerFrameMixin = {};

function ColorPickerFrameMixin:OnOkay()
    self.swatchFunc();
    if self.opacityFunc then
        self.opacityFunc();
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON);
    self:Hide();
end

function ColorPickerFrameMixin:OnCancel()
    if self.cancelFunc then
        self.cancelFunc(self.previousValues);
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON);
    self:Hide();
end

function ColorPickerFrameMixin:GetColorRGB()
    return self.Content.ColorPicker:GetColorRGB();
end

function ColorPickerFrameMixin:GetColorAlpha()
    return self.Content.ColorPicker:GetColorAlpha();
end

function ColorPickerFrameMixin:GetExtraInfo()
    return self.extraInfo;
end

function ColorPickerFrameMixin:GetPreviousValues()
    return self.previousValues.r, self.previousValues.g, self.previousValues.b, self.previousValues.a;
end

function ColorPickerFrameMixin:SetupColorPickerAndShow(info)
    self.swatchFunc = info.swatchFunc;
    self.hasOpacity = info.hasOpacity;
    self.opacityFunc = info.opacityFunc;
    self.opacity = info.opacity;
    self.previousValues = {r = info.r, g = info.g, b = info.b, a = info.opacity};
    self.cancelFunc = info.cancelFunc;
    self.extraInfo = info.extraInfo;
    self.swatch = info.swatch;

    self.Content.ColorSwatchOriginal:SetColorTexture(info.r, info.g, info.b);
    self.Content.ColorPicker:SetColorRGB(info.r, info.g, info.b);
    self:Show();
end

Mixin(f, ColorPickerFrameMixin);

f.Content.ColorPicker:SetScript("OnColorSelect", function(_, r, g, b)
    f.Content.ColorSwatchCurrent:SetColorTexture(r, g, b);
    if f.swatchFunc then
        f.swatchFunc();
    end
    if f.swatch then
        f.swatch:SetColorRGB(r, g, b);
    end
    if f.opacityFunc then
        f.opacityFunc();
    end
end);
f.Footer.OkayButton:SetScript("OnClick", function()
    f:OnOkay();
end);
f.Footer.CancelButton:SetScript("OnClick", function()
    f:OnCancel();
end);
f:SetScript("OnShow", function(self)
    self:RegisterEvent("GLOBAL_MOUSE_DOWN");
end);
f:SetScript("OnHide", function(self)
    self:UnregisterEvent("GLOBAL_MOUSE_DOWN");
end);
-- the mock has no hit testing: H.colorPickerClickOutside marks the click as outside
f:SetScript("OnEvent", function(self, event)
    if event == "GLOBAL_MOUSE_DOWN" and self:IsShown() and H.colorPickerClickIsOutside then
        if self.cancelFunc then
            self.cancelFunc(self.previousValues);
        end
        self:Hide();
    end
end);
f:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then
        if self.cancelFunc then
            self.cancelFunc(self.previousValues);
        end
        self:Hide();
    end
end);

local function requireShown(what)
    if not f:IsShown() then
        error("harness: " .. what .. ": the colour picker is not open", 3);
    end
end

function H.colorPickerShown()
    return f:IsShown();
end

-- The player drags on the colour wheel / value bar until it shows this colour.
function H.colorPickerSelect(r, g, b)
    requireShown("colorPickerSelect");
    f.Content.ColorPicker:SetColorRGB(r, g, b);
end

function H.colorPickerOkay()
    requireShown("colorPickerOkay");
    f.Footer.OkayButton:Click("LeftButton");
end

function H.colorPickerCancel()
    requireShown("colorPickerCancel");
    f.Footer.CancelButton:Click("LeftButton");
end

function H.colorPickerEscape()
    requireShown("colorPickerEscape");
    H.fireScript(f, "OnKeyDown", "ESCAPE");
end

function H.colorPickerClickOutside()
    H.colorPickerClickIsOutside = true;
    H.fire("GLOBAL_MOUSE_DOWN", "LeftButton");
    H.colorPickerClickIsOutside = false;
end
