-- GearQuipper Forever: skin adapter. GQ builds its widgets from stock Blizzard templates and hands each one to
-- c:Skin(kind, widget[, opts]) when it is created. Without a UI suite nothing changes (stock look). When a suite's
-- skinner becomes active (EllesmereUI first, ElvUI as an extra) every registered widget is skinned once, in creation
-- order, and widgets registered later are skinned at once.
--
-- kinds and opts: frame (window shell, also its .CloseButton and .Inset, so register it after building them;
-- EllesmereUI opts: noBorder, noTopBar, bottomBar), panel (flat opaque box; opts: inset, noBorder, noBg), inset, button (opts.keepKeys), checkbox
-- (opts.stockCheck), dropdown, scrollbar (opts.keepSteppers), itembutton (opts.icon; call again after the quality
-- changes to refresh the rarity border), close, tab, editbox (opts.padInput, noBorder), font.
local addonName = ...;
gearquipper = gearquipper or {};
local c = gearquipper;

addonName = addonName or c.addonName or "GearQuipper-Forever";

-- optional suites (nil when not installed); both load before GQ through OptionalDeps
local EllesmereUI = rawget(_G, "EllesmereUI");
local ElvUI = rawget(_G, "ElvUI");

local KINDS = {frame = true, panel = true, inset = true, button = true, checkbox = true, dropdown = true,
    scrollbar = true, itembutton = true, close = true, tab = true, editbox = true, font = true};

local FRAME_CHILDREN = {{"close", "CloseButton"}, {"inset", "Inset"}};

local registry = setmetatable({}, {__mode = "k"}); -- widget -> {[kind] = {opts = opts, seq = n}}
local done = setmetatable({}, {__mode = "k"});     -- widget -> {[kind] = true}, skinned by the active backend
local seq = 0;
local backend;                                       -- {name, apply = function(kind, widget, opts, again)}

local function ApplyKind(kind, widget, opts)
    local marks = done[widget];
    if not marks then
        marks = {};
        done[widget] = marks;
    end
    local again = marks[kind];
    if again and kind ~= "itembutton" then
        return;
    end
    marks[kind] = true;
    local ok, err = pcall(backend.apply, kind, widget, opts, again);
    if not ok then
        c:DebugPrint("Skin", backend.name, kind, err);
    end
    if kind == "frame" then
        -- the shell's own close button and inset belong to it (ElvUI's HandleFrame skins them itself)
        for _, pair in ipairs(FRAME_CHILDREN) do
            local childKind, child = pair[1], rawget(widget, pair[2]);
            if type(child) == "table" then
                if backend.frameSkinsChildren then
                    done[child] = done[child] or {};
                    done[child][childKind] = true;
                else
                    ApplyKind(childKind, child);
                end
            end
        end
    end
end

local function Activate(name, apply, frameSkinsChildren)
    if backend then
        return;
    end
    backend = {name = name, apply = apply, frameSkinsChildren = frameSkinsChildren};
    local list = {};
    for widget, kinds in pairs(registry) do
        for kind, entry in pairs(kinds) do
            list[#list + 1] = {widget = widget, kind = kind, opts = entry.opts, seq = entry.seq};
        end
    end
    table.sort(list, function(a, b)
        return a.seq < b.seq;
    end);
    for _, entry in ipairs(list) do
        ApplyKind(entry.kind, entry.widget, entry.opts);
    end
end

function c:Skin(kind, widget, opts)
    if not KINDS[kind] then
        error("c:Skin: unknown kind " .. tostring(kind), 2);
    end
    if type(widget) ~= "table" then
        error("c:Skin(" .. kind .. "): widget missing", 2);
    end
    local kinds = registry[widget];
    if not kinds then
        kinds = {};
        registry[widget] = kinds;
    end
    local entry = kinds[kind];
    if not entry then
        seq = seq + 1;
        entry = {opts = opts, seq = seq};
        kinds[kind] = entry;
    elseif opts then
        entry.opts = opts;
    end
    if backend then
        ApplyKind(kind, widget, entry.opts);
    end
end

-- "EllesmereUI", "ElvUI" or nil (stock look).
function c:GetSkinBackend()
    return backend and backend.name;
end

---------------------------------------------------------------------------
-- EllesmereUI (Blizzard Skins+ third-party API, SKINNING_API.md)
---------------------------------------------------------------------------
local function EllesmereApply(S)
    local map = {
        frame = function(w, opts)
            S.Shell(w, opts);
        end,
        panel = function(w, opts)
            S.Panel(w, opts);
        end,
        inset = function(w)
            S.Inset(w);
        end,
        button = function(w, opts)
            S.Button(w, opts and opts.keepKeys);
            S.StateButtonLabel(w);
        end,
        checkbox = function(w, opts)
            S.Checkbox(w, opts);
        end,
        dropdown = function(w)
            S.Dropdown(w);
        end,
        scrollbar = function(w, opts)
            S.ScrollBar(w, opts and opts.keepSteppers);
        end,
        itembutton = function(w, opts)
            if S.ItemButton then
                S.ItemButton(w, opts);
            else
                S.SquareIcon((opts and opts.icon) or rawget(w, "icon") or rawget(w, "Icon"), w, true);
            end
        end,
        close = function(w)
            S.CloseButton(w);
        end,
        tab = function(w, opts)
            S.Tab(w, opts);
        end,
        editbox = function(w, opts)
            S.EditBox(w, opts);
        end,
        font = function(w)
            S.Font(w);
        end,
    };
    return function(kind, widget, opts)
        map[kind](widget, opts);
    end;
end

-- GQ docks to the character sheet, so it follows the sheet: stock while EllesmereUI leaves the sheet stock.
-- GetBlizzWindowStyle is internal to EllesmereUI; missing or failing counts as skinned.
local function EllesmereSheetSkinned()
    local getStyle = EllesmereUI and EllesmereUI.GetBlizzWindowStyle;
    if type(getStyle) ~= "function" then
        return true;
    end
    local ok, style = pcall(getStyle, "charsheet");
    return not (ok and (style == "blizzard" or style == "off"));
end

---------------------------------------------------------------------------
-- ElvUI (untested in game: ElvUI is not installed here; written against tukui-org/ElvUI main, Skins.lua)
---------------------------------------------------------------------------
local function ElvApply(S)
    local map = {
        frame = function(w)
            S:HandleFrame(w);
        end,
        panel = function(w)
            S:HandleFrame(w);
        end,
        inset = function(w)
            S:HandleInsetFrame(w);
        end,
        button = function(w)
            S:HandleButton(w);
        end,
        checkbox = function(w)
            S:HandleCheckBox(w);
        end,
        dropdown = function(w)
            -- without a width ElvUI resizes every dropdown to 155
            S:HandleDropDownBox(w, w:GetWidth());
        end,
        scrollbar = function(w)
            S:HandleTrimScrollBar(w);
        end,
        itembutton = function(w, opts, again)
            if not again then
                S:HandleItemButton(w, true);
            end
            local border = rawget(w, "IconBorder");
            if border then
                S:HandleIconBorder(border);
            end
        end,
        close = function(w)
            S:HandleCloseButton(w);
        end,
        tab = function(w)
            S:HandleTab(w);
        end,
        editbox = function(w)
            S:HandleEditBox(w);
        end,
        -- ElvUI restyles the Blizzard font objects GQ's strings inherit
        font = function() end,
    };
    return function(kind, widget, opts, again)
        map[kind](widget, opts, again);
    end;
end

---------------------------------------------------------------------------
-- registration (file load: both suites load first through OptionalDeps)
---------------------------------------------------------------------------
if EllesmereUI and EllesmereUI.RegisterSkin then
    EllesmereUI.RegisterSkin(addonName, function(S)
        if EllesmereSheetSkinned() then
            Activate("EllesmereUI", EllesmereApply(S), false);
        else
            c:DebugPrint("Skin", "EllesmereUI leaves the character sheet stock; GearQuipper stays stock");
        end
    end);
elseif type(ElvUI) == "table" then
    local ok, err = pcall(function()
        local E = unpack(ElvUI);
        local S = E and E.GetModule and E:GetModule("Skins", true);
        if S and S.AddCallbackForAddon then
            -- the "character" toggle: ElvUI only calls back while it skins the character sheet GQ docks to
            S:AddCallbackForAddon(addonName, "GearQuipperForever", function(skins)
                Activate("ElvUI", ElvApply(skins or S), true);
            end, nil, nil, nil, "character");
        end
    end);
    if not ok then
        c:DebugPrint("Skin", "ElvUI", err);
    end
end
