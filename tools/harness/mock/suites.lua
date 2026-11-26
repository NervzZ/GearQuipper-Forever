-- suites.lua: UI-suite stubs, installed per scenario BEFORE the addon loads (like an optional dependency that loads
-- first), so the skin adapter sees them at file load.
--
-- Selecting a suite (pick one):
--   * scenario field   suites = {EllesmereUI = {charsheetStyle = "eui"}, ElvUI = {}}   (run.py installs it before
--     `setup`; works per variant too)
--   * from setup(H):   H.installSuites({EllesmereUI = {...}})
--
-- EllesmereUI options (defaults in brackets), modelled on EllesmereUI 9.9.5 (EllesmereUI_SharedHelpers.lua,
-- EllesmereUIBlizzardSkin_SkinAPI.lua, EllesmereUIBlizzardSkin.lua, ..._WindowEngine.lua):
--   charsheetStyle ["eui"]   what EllesmereUI.GetBlizzWindowStyle("charsheet") returns: "eui" | "modern" |
--                            "blizzard" | "off"
--   styleApi ["present"]     "missing" (no GetBlizzWindowStyle) | "error" (it errors)
--   thirdPartySkinsOff       master toggle off: callbacks do not fire at login (H.euiToggleOn() fires them later)
--   addonOff                 the per-addon toggle of every registration is off (same)
--   childLoaded [true]       false: the Blizzard Skins+ child addon is disabled, RegisterSkin only queues
--   thirdPartyStyle ["eui"]  what S.GetStyle() returns
--   fail = {Button = true}   those primitives raise an error (H.suiteFail(name, on) at run time)
-- The facade S records every primitive call in H.suiteCalls as {suite, primitive, widget, args} and mimics the
-- art changes GQ cares about: Shell / Panel / Inset / Button fade the widget's own textures (alpha 0) and register
-- it for EllesmereUI's global Restrip; their own textures (backdrop, fill, hover, border) are EUI-owned; ItemButton
-- fades NormalTexture and IconBorder and keeps the rarity colour it read in H.euiItemBorder(button).
--   H.euiToggleOn()   live toggle-on after login: fires every eligible registration that has not fired yet
--   H.euiRestrip()    EllesmereUI's global Restrip: re-fades every non-EUI texture on Shell/Panel/Inset/Button frames
--
-- ElvUI options (modelled on tukui-org/ElvUI main, Game/Shared/Modules/Skins/Skins.lua; untested in game):
--   blizzardEnable [true], character [true]   E.private.skins.blizzard.enable / .character (the toggle GQ passes)
--   fail = {HandleButton = true}
-- unpack(ElvUI) gives E; E:GetModule("Skins") the recording S (Handle* calls recorded the same way);
-- S:AddCallbackForAddon(addon, name, func, forceLoad, bypass, position, toggle) runs func(S, data) at PLAYER_LOGIN
-- (ElvUI's own initialisation) when the addon is loaded and the toggle passes.
-- Helpers: H.suiteCallsFor(widget) H.countSuiteCalls(primitive[, widget]) H.clearSuiteCalls() H.suiteFail(name, on)
local H = ...;
local P = H.widgetState;

H.suiteCalls = {};
local failures = {};

local function record(suite, primitive, widget, ...)
    H.suiteCalls[#H.suiteCalls + 1] = {suite = suite, primitive = primitive, widget = widget, args = H.pack(...),
        t = H.now};
    if failures[primitive] then
        error(suite .. " stub: " .. primitive .. " failed (injected)", 3);
    end
end

function H.suiteFail(primitive, on)
    failures[primitive] = on ~= false and true or nil;
end

function H.clearSuiteCalls()
    H.suiteCalls = {};
end

-- Primitive names called for this widget, in call order.
function H.suiteCallsFor(widget)
    local list = {};
    for _, c in ipairs(H.suiteCalls) do
        if c.widget == widget then
            list[#list + 1] = c.primitive;
        end
    end
    return list;
end

function H.countSuiteCalls(primitive, widget)
    local n = 0;
    for _, c in ipairs(H.suiteCalls) do
        if c.primitive == primitive and (widget == nil or c.widget == widget) then
            n = n + 1;
        end
    end
    return n;
end

---------------------------------------------------------------------------
-- EllesmereUI
---------------------------------------------------------------------------
local eui = {owned = setmetatable({}, {__mode = "k"}), data = setmetatable({}, {__mode = "k"}),
    restrip = setmetatable({}, {__mode = "k"})};
H.euiState = eui;

local function d(frame)
    local t = eui.data[frame];
    if not t then
        t = {};
        eui.data[frame] = t;
    end
    return t;
end

local function own(parent, layer, subLevel)
    local t = parent:CreateTexture(nil, layer, nil, subLevel);
    eui.owned[t] = true;
    return t;
end

local function fade(frame, keep)
    if not frame then
        return;
    end
    for _, r in ipairs({frame:GetRegions()}) do
        if r:IsObjectType("Texture") and not eui.owned[r] and not (keep and keep[r]) then
            r:SetAlpha(0);
        end
    end
    if rawget(frame, "NineSlice") then
        fade(frame.NineSlice, keep);
    end
end

local function register(frame, keep)
    eui.restrip[frame] = keep or true;
end

local function border(frame)
    d(frame).border = true;
end

local prim = {};

function prim.Shell(frame, opts)
    local s = d(frame);
    fade(frame);
    register(frame);
    if not s.bg then
        s.bg = own(frame, "BACKGROUND", -8);
        s.bg:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png");
        s.overlay = own(frame, "BACKGROUND", -7);
        s.overlay:SetColorTexture(0, 0, 0, 0.62);
        if not (opts and opts.noTopBar) then
            s.topBar = own(frame, "BACKGROUND", -5);
            s.topBar:SetColorTexture(0, 0, 0, 0.5);
        end
        if opts and opts.bottomBar then
            s.bottomBar = own(frame, "BACKGROUND", -5);
            s.bottomBar:SetColorTexture(0, 0, 0, 0.5);
        end
    end
    if not (opts and opts.noBorder) and not s.borderFrame then
        s.borderFrame = CreateFrame("Frame", nil, frame);
        s.borderFrame:SetFrameLevel(frame:GetFrameLevel() + 6);
        local tex = own(s.borderFrame, "OVERLAY", 7);
        tex:SetAtlas("AdventureMap_TopBorder");
    end
    s.shell = opts or {};
end

function prim.Panel(frame, opts)
    local s = d(frame);
    fade(frame);
    register(frame);
    if not s.bg and not (opts and opts.noBg) then
        s.bg = own(frame, "BACKGROUND", -6);
        s.bg:SetColorTexture(0.08, 0.08, 0.08, (opts and opts.inset) and 0.85 or 0.92);
    end
    if not (opts and opts.noBorder) then
        border(frame);
    end
end

function prim.Inset(inset)
    fade(inset);
    if rawget(inset, "Bg") then
        inset.Bg:SetAlpha(0);
    end
    register(inset);
end

function prim.FadeRegions(frame)
    fade(frame);
end

function prim.FadeNineSlice(nineSlice)
    fade(nineSlice);
    if nineSlice then
        nineSlice:SetAlpha(0);
    end
end

function prim.Button(btn, keepKeys)
    local s = d(btn);
    if s.skinned then
        return;
    end
    s.skinned = true;
    local keep = {};
    for _, k in ipairs(keepKeys or {}) do
        if rawget(btn, k) then
            keep[btn[k]] = true;
        end
    end
    fade(btn, keep);
    for _, getter in ipairs({"GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture"}) do
        local t = btn[getter] and btn[getter](btn);
        if t and not keep[t] then
            t:SetAlpha(0);
        end
    end
    for _, k in ipairs({"Left", "Middle", "Right", "LeftSeparator", "RightSeparator"}) do
        local r = rawget(btn, k);
        if r and not keep[r] then
            r:SetAlpha(0);
        end
    end
    s.bg = own(btn, "BACKGROUND");
    s.bg:SetColorTexture(0.08, 0.08, 0.08, 0.92);
    s.hover = own(btn, "HIGHLIGHT");
    s.hover:SetColorTexture(1, 1, 1, 0.1);
    border(btn);
    register(btn, keep);
end

local function label(btn)
    return rawget(btn, "Text") or (btn.GetFontString and btn:GetFontString());
end

function prim.WhiteButtonLabel(btn)
    local lab = label(btn);
    if lab then
        lab:SetTextColor(1, 1, 1);
    end
end

function prim.StateButtonLabel(btn)
    local lab = label(btn);
    if lab then
        if btn:IsEnabled() then
            lab:SetTextColor(1, 1, 1);
        else
            lab:SetTextColor(0.5, 0.5, 0.5);
        end
    end
end

function prim.EditBox(eb, opts)
    local s = d(eb);
    if s.bg then
        return;
    end
    fade(eb);
    for _, k in ipairs({"Left", "Right", "Middle", "Mid"}) do
        local r = rawget(eb, k);
        if r then
            r:SetAlpha(0);
        end
    end
    s.bg = own(eb, "BACKGROUND");
    s.bg:SetColorTexture(0.02, 0.02, 0.02, 1);
end

function prim.Checkbox(cb, opts)
    local s = d(cb);
    if s.skinned then
        return;
    end
    s.skinned = true;
    cb:SetNormalTexture("");
    cb:SetPushedTexture("");
    cb:SetHighlightTexture("");
    local keep = {};
    if cb.GetCheckedTexture and cb:GetCheckedTexture() then
        keep[cb:GetCheckedTexture()] = true;
    end
    if cb.GetDisabledCheckedTexture and cb:GetDisabledCheckedTexture() then
        keep[cb:GetDisabledCheckedTexture()] = true;
    end
    fade(cb, keep);
    s.bg = own(cb, "BACKGROUND");
    s.bg:SetColorTexture(0.02, 0.02, 0.02, 1);
end

function prim.Dropdown(dd)
    local s = d(dd);
    if s.skinned then
        return;
    end
    s.skinned = true;
    fade(dd);
    for _, k in ipairs({"Background", "Texture"}) do
        if rawget(dd, k) then
            dd[k]:SetAlpha(0);
        end
    end
    s.bg = own(dd, "BACKGROUND");
    s.bg:SetColorTexture(0.08, 0.08, 0.08, 0.92);
    s.arrow = own(dd, "OVERLAY");
    s.arrow:SetAtlas("Azerite-PointingArrow");
    local lab = rawget(dd, "Text") or (dd.GetFontString and dd:GetFontString());
    if lab then
        lab:SetTextColor(1, 1, 1);
    end
end

function prim.ScrollBar(sb, keepSteppers)
    local s = d(sb);
    if s.skinned then
        return;
    end
    s.skinned = true;
    if not keepSteppers then
        for _, k in ipairs({"Back", "Forward"}) do
            local b = rawget(sb, k);
            if b then
                fade(b);
                if rawget(b, "Texture") then
                    b.Texture:SetAlpha(0);
                end
            end
        end
    end
    local track = rawget(sb, "Track");
    if track then
        fade(track);
        local thumb = rawget(track, "Thumb");
        if thumb then
            fade(thumb);
            s.strip = own(thumb, "ARTWORK");
            s.strip:SetColorTexture(1, 1, 1, 0.3);
        end
    end
end

function prim.CloseButton(btn)
    local s = d(btn);
    if s.x then
        return;
    end
    btn:SetNormalTexture("");
    btn:SetPushedTexture("");
    btn:SetHighlightTexture("");
    btn:SetDisabledTexture("");
    fade(btn);
    s.x = own(btn, "OVERLAY");
    s.x:SetAtlas("uitools-icon-close");
end

function prim.Tab(tab, opts)
    local s = d(tab);
    if s.bg then
        return;
    end
    for _, r in ipairs({tab:GetRegions()}) do
        if r:IsObjectType("Texture") and r ~= rawget(tab, "Icon") and r ~= rawget(tab, "IconMask") then
            r:SetTexture("");
        end
    end
    s.bg = own(tab, "BACKGROUND");
    s.bg:SetColorTexture(0.08, 0.08, 0.08, 0.92);
end

function prim.SetTabSelection(tab, selected)
    d(tab).selectedOverride = selected;
end

function prim.PageButton() end

function prim.SquareIcon(icon, parent, quality)
    if icon then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92);
    end
end

-- the rarity colour EUI reads off the item button's quality ring (black when the ring is hidden or grey)
local function ringColor(btn)
    local ring = rawget(btn, "IconBorder");
    if ring and ring:IsShown() then
        local r, g, b = ring:GetVertexColor();
        if math.max(r, g, b) - math.min(r, g, b) > 0.1 then
            return {r, g, b};
        end
    end
    return {0, 0, 0};
end

function prim.ItemButton(btn, opts)
    local icon = (opts and opts.icon) or rawget(btn, "Icon") or rawget(btn, "icon") or
        (btn:GetName() and _G[btn:GetName() .. "IconTexture"]);
    if not icon then
        return;
    end
    local s = d(btn);
    if not s.itemSlot then
        s.itemSlot = true;
        local nt = btn:GetNormalTexture();
        if nt then
            nt:SetAlpha(0);
        end
        if rawget(btn, "IconBorder") then
            btn.IconBorder:SetAlpha(0);
        end
        s.plate = own(btn, "BACKGROUND", -7);
        s.plate:SetColorTexture(0.04, 0.04, 0.04, 1);
    end
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92);
    s.qualityBorder = ringColor(btn);
end

function H.euiItemBorder(btn)
    local s = eui.data[btn];
    return s and s.qualityBorder;
end

function prim.SortHeaderBar() end

function prim.Font(fs, r, g, b, size)
    local _, cur = fs:GetFont();
    fs:SetFont("Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf", size or cur or 12, "");
    if r then
        fs:SetTextColor(r, g, b or r);
    end
end

function prim.White(fs, r, g, b)
    if fs and fs.SetTextColor then
        fs:SetTextColor(r or 1, g or 1, b or 1);
    end
end

function prim.ApplyBarFill() end

function H.euiRestrip()
    for frame, keep in pairs(eui.restrip) do
        fade(frame, type(keep) == "table" and keep or nil);
    end
end

local function installEllesmereUI(opts)
    opts = opts or {};
    for name in pairs(opts.fail or {}) do
        failures[name] = true;
    end
    eui.opts = opts;
    eui.fired, eui.loginDone = {}, false;
    EllesmereUI = {IS_FOREVER = true, _skinRegistry = {}};
    function EllesmereUI.RegisterSkin(name, applyFn)
        if type(name) ~= "string" or name == "" or type(applyFn) ~= "function" then
            return;
        end
        local reg = EllesmereUI._skinRegistry;
        for i = 1, #reg do
            if reg[i].name == name then
                return;
            end
        end
        local entry = {name = name, apply = applyFn};
        reg[#reg + 1] = entry;
        if EllesmereUI._DispatchSkinRegistration then
            EllesmereUI._DispatchSkinRegistration(entry);
        end
        return true;
    end
    if opts.childLoaded == false then
        return;
    end
    function EllesmereUI.GetThirdPartySkinStyle()
        return opts.thirdPartyStyle or "eui";
    end
    if opts.styleApi ~= "missing" then
        function EllesmereUI.GetBlizzWindowStyle(winKey)
            if opts.styleApi == "error" then
                error("EllesmereUI stub: GetBlizzWindowStyle failed (injected)");
            end
            if type(winKey) == "string" and winKey:sub(1, 3) == "tp:" then
                return EllesmereUI.GetThirdPartySkinStyle();
            end
            if winKey == "charsheet" then
                return opts.charsheetStyle or "eui";
            end
            return "eui";
        end
    end
    local function eligible(name)
        return not opts.thirdPartySkinsOff and not opts.addonOff;
    end
    local function facade(name)
        local S = {apiVersion = 4};
        for primName, fn in pairs(prim) do
            S[primName] = function(widget, ...)
                record("EllesmereUI", primName, widget, ...);
                return fn(widget, ...);
            end;
        end
        S.IsEnabled = function()
            return eligible(name);
        end;
        S.GetStyle = function()
            return opts.thirdPartyStyle or "eui";
        end;
        S.GetAccentColor = function()
            return 0.047, 0.824, 0.616;
        end;
        S.GetPanelColor = function()
            return 0.08, 0.08, 0.08, 0.92;
        end;
        S.GetFont = function()
            return "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf", "";
        end;
        S.OnLooksChanged = function() end;
        return S;
    end
    local function dispatch(entry)
        if eui.fired[entry.name] or not eligible(entry.name) then
            return;
        end
        eui.fired[entry.name] = true;
        local ok, err = pcall(entry.apply, facade(entry.name));
        if not ok and err then
            geterrorhandler()(err);
        end
    end
    EllesmereUI._DispatchSkinRegistration = function(entry)
        if eui.loginDone then
            dispatch(entry);
        end
    end
    function H.euiToggleOn()
        opts.thirdPartySkinsOff, opts.addonOff = false, false;
        if not eui.loginDone then
            return;
        end
        for _, entry in ipairs(EllesmereUI._skinRegistry) do
            dispatch(entry);
        end
    end
    local boot = CreateFrame("Frame");
    boot:RegisterEvent("PLAYER_LOGIN");
    boot:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN");
        eui.loginDone = true;
        for _, entry in ipairs(EllesmereUI._skinRegistry) do
            dispatch(entry);
        end
    end);
end

function H.euiToggleOn()
    error("harness: EllesmereUI is not installed in this scenario", 2);
end

---------------------------------------------------------------------------
-- ElvUI
---------------------------------------------------------------------------
local HANDLERS = {"HandleFrame", "HandlePortraitFrame", "HandleInsetFrame", "HandleButton", "HandleCheckBox",
    "HandleRadioButton", "HandleDropDownBox", "HandleTrimScrollBar", "HandleScrollBar", "HandleItemButton",
    "HandleIconBorder", "HandleIcon", "HandleCloseButton", "HandleTab", "HandleEditBox", "HandleSliderFrame",
    "HandleNextPrevButton"};

local function installElvUI(opts)
    opts = opts or {};
    for name in pairs(opts.fail or {}) do
        failures[name] = true;
    end
    local S = {Initialized = false, addonsToLoad = {}, addonStorage = {}, nonAddonsToLoad = {}};
    local E = {Forever = true, Initialized = false, private = {skins = {blizzard = {
        enable = opts.blizzardEnable ~= false, character = opts.character ~= false}}}};
    E.ErrorHandler = function(err)
        geterrorhandler()(err);
    end;
    function E:CallLoadFunc(func, ...)
        local args = H.pack(...);
        return xpcall(function()
            return func(unpack(args, 1, args.n));
        end, E.ErrorHandler);
    end
    function E:GetModule(name, silent)
        if name == "Skins" then
            return S;
        end
        if not silent then
            error("Cannot find module '" .. tostring(name) .. "'", 2);
        end
    end
    for _, name in ipairs(HANDLERS) do
        S[name] = function(self, widget, ...)
            record("ElvUI", name, widget, ...);
        end;
    end
    function S:RegisterSkin(addonName, func, forceLoad, bypass, position, name, toggle)
        local info = {addonName = addonName, func = func, name = name, data = {},
            check = type(toggle) == "function" and toggle or nil, toggle = type(toggle) ~= "function" and toggle or nil};
        S.addonStorage[name or addonName] = info;
        if forceLoad then
            S:LoadSkin(info);
        else
            S.addonsToLoad[addonName] = S.addonsToLoad[addonName] or {};
            table.insert(S.addonsToLoad[addonName], info);
        end
        return info.data;
    end
    function S:AddCallbackForAddon(addonName, name, func, forceLoad, bypass, position, toggle)
        if type(name) == "function" then
            return S:RegisterSkin(addonName, name, forceLoad, bypass, position, nil, toggle);
        end
        return S:RegisterSkin(addonName, func, forceLoad, bypass, position, name, toggle);
    end
    function S:LoadSkin(info)
        if info.check then
            local ok, allow = E:CallLoadFunc(info.check);
            if not (ok and allow) then
                return;
            end
        elseif info.toggle then
            local blizzard = E.private.skins.blizzard;
            if not (blizzard.enable and blizzard[info.toggle]) then
                return;
            end
        end
        E:CallLoadFunc(info.func, S, info.data);
    end
    function S:Initialize()
        S.Initialized = true;
        for addonName, list in pairs(S.addonsToLoad) do
            if H.loadedAddons[addonName] then
                for _, info in ipairs(list) do
                    S:LoadSkin(info);
                end
                S.addonsToLoad[addonName] = nil;
            end
        end
    end
    ElvUI = {E, {}, {}, {}, {}};
    H.elv = {E = E, S = S};
    local boot = CreateFrame("Frame");
    boot:RegisterEvent("PLAYER_LOGIN");
    boot:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN");
        S:Initialize();
        E.Initialized = true;
    end);
end

---------------------------------------------------------------------------
-- installation
---------------------------------------------------------------------------
-- suites = {EllesmereUI = opts, ElvUI = opts} (either may be omitted; opts may be true for the defaults). They are
-- installed in load order (EllesmereUI before ElvUI, both before the addon), which fixes their PLAYER_LOGIN order.
function H.installSuites(suites)
    suites = suites or {};
    for name in pairs(suites) do
        if name ~= "EllesmereUI" and name ~= "ElvUI" then
            error("harness: unknown suite " .. tostring(name), 2);
        end
    end
    if suites.EllesmereUI then
        installEllesmereUI(type(suites.EllesmereUI) == "table" and suites.EllesmereUI or {});
    end
    if suites.ElvUI then
        installElvUI(type(suites.ElvUI) == "table" and suites.ElvUI or {});
    end
end
