-- scope stuff
gearquipper = gearquipper or {};
local c = gearquipper;
local LDB;

local eventListeners = {};

GQ_EVENT_EVENT_BINDING_REMOVED = "GQ_EVENT_EVENT_BINDING_REMOVED";
GQ_EVENT_EVENT_BINDING_SAVED = "GQ_EVENT_EVENT_BINDING_SAVED";
GQ_EVENT_SET_REMOVED = "GQ_EVENT_SET_REMOVED";
GQ_EVENT_SET_SAVED = "GQ_EVENT_SET_SAVED";
GQ_EVENT_SLOT_SAVED = "GQ_EVENT_SLOT_SAVED";
GQ_EVENT_SLOT_STATE_SAVED = "GQ_EVENT_SLOT_STATE_SAVED";

-- set names in the broker tooltip: their set colour, white without one
local function SetNameText(setName)
    return c:FormatTextWithColor(setName, c:LoadSetColor(setName) or "FFFFFF");
end

function c:InitBroker()
    if LibStub and not LDB then
        local libDataBroker = LibStub('LibDataBroker-1.1', true);
        if not libDataBroker then
            c:Println(c:GetText("Error while initializing data broker!"));
            return;
        end

        LDB = libDataBroker:NewDataObject('GearQuipper', {
            label = 'GearQuipper',
            type = 'data source',
            icon = "Interface\\Icons\\Ability_warrior_defensivestance",
            OnTooltipShow = function(self)
                if GQ_OPTIONS[c.OPT_SHOWBROKERTOOLTIP] then
                    self:AddLine("|cFFFFFFFFGearQuipper|r");
                    self:AddLine(" ");

                    local currentSet = c:LoadCurrentSetName();
                    self:AddLine(c:GetText("%s: %s", c:GetText("Current set"),
                        currentSet and SetNameText(currentSet) or c:FormatTextWithColor(UNKNOWN, "FFFFFF")));

                    self:AddLine(" ");
                    if c:IsEventsEnabled() then
                        local eventBindings = c:LoadEventBindings();
                        if eventBindings and c:GetTableSize(eventBindings) > 0 then
                            self:AddLine(c:GetText("Active event bindings:"));
                            for index, binding in pairs(eventBindings) do
                                local type = binding[c.FIELD_TYPE];
                                local environment;
                                if binding[c.FIELD_PVE] then
                                    environment = "( " .. c:FormatTextWithColor("PvE", "00FF00");
                                end
                                if binding[c.FIELD_PVP] then
                                    if environment then
                                        environment = environment .. " / " .. c:FormatTextWithColor("PvP", "FF0000") ..
                                                          " )";
                                    else
                                        environment = "( " .. c:FormatTextWithColor("PvP", "FF0000") .. " )";
                                    end
                                elseif environment then
                                    environment = environment .. " )";
                                end
                                local setName = binding[c.FIELD_NAME] or UNKNOWN;
                                local setText;
                                if setName == c.KEYWORD_PREVIOUS then
                                    setText = c:FormatTextWithColor(c:GetText("[Previous equipment]"), "FFFFFF");
                                else
                                    setText = SetNameText(setName);
                                end
                                local eventName = c:GetEvents()[binding[c.FIELD_TYPE]] or tostring(type or UNKNOWN);
                                self:AddLine(c:GetText("%s will switch to %s %s",
                                    c:FormatTextWithColor(eventName, "FFFFFF"), setText, environment or ""));
                            end
                        else
                            self:AddLine(c:GetText("Active event bindings:") .. " " ..
                                             c:FormatTextWithColor(NONE_KEY, "FFFFFF"));
                        end

                    else
                        self:AddLine(c:GetText("Event bindings disabled."));
                    end
                end
            end,
            OnClick = function(self, button)
                if button == "RightButton" then
                    c:OpenContextMenu("broker", self, function(owner, root)
                        c:PopulateBrokerMenu(root);
                    end);
                end
            end,
            OnDoubleClick = function(self, button)
                if button == "LeftButton" then
                    c:QueueSwitch({
                        [c.SWITCHARG_SETNAME] = c.KEYWORD_PREVIOUS
                    });
                end
            end
        });

        if not LDB then
            c:Println(c:GetText("Error while initializing data broker!"));
            return;
        end

        c:UpdateBroker();
        c:Println(c:GetText("Data broker initialized."));
    end
end

-- right-click menu of the data broker: the sets, the current one ticked
function c:PopulateBrokerMenu(root)
    if c:IsSwitching() then
        root:CreateTitle(c:GetText("- Currently Switching -"));
        return;
    end

    root:CreateTitle(c:GetText("Switch to set:"));
    local currentSet = c:LoadCurrentSetName();
    local function isSelected(setName)
        return setName == currentSet;
    end
    local function setSelected(setName)
        if setName ~= currentSet then
            c:QueueSwitch({
                [c.SWITCHARG_SETNAME] = setName
            });
        end
    end
    for _, setName in ipairs(c:LoadSetNames(false)) do
        root:CreateRadio(c:ColorizeSetName(setName), isSelected, setSelected, setName);
    end
end

function c:UpdateBroker()
    if LDB then
        local currentSet = c:LoadCurrentSetName();
        LDB.text = currentSet and c:ColorizeSetName(currentSet) or UNKNOWN;
    end
end

--- Returns a list of valid GearQuipper events.
function c:GetEventListenerEvents()
    return {GQ_EVENT_EVENT_BINDING_REMOVED, GQ_EVENT_EVENT_BINDING_SAVED, GQ_EVENT_SET_REMOVED, GQ_EVENT_SET_SAVED,
            GQ_EVENT_SLOT_SAVED, GQ_EVENT_SLOT_STATE_SAVED};
end

--- Registers event listener for given event. See gearquipper:GetEventListenerEvents() for list of valid events.
---@param event string event
---@param func function function which will be called upon event
---@param o any (optional) custom existing object which will get :OnEvent(event, ...) and :GetGqEventListenerId() methods attached
---@return any listener object with :OnEvent(event, ...) and :GetGqEventListenerId() methods
function c:RegisterEventListener(event, func, o)
    if event and func then
        local listener = o or {};

        listener.gqEventListenerId = listener.gqEventListenerId or c:uuid();
        listener.GetGqEventListenerId = function(self)
            return self.gqEventListenerId;
        end;

        listener.gqEventListenerEvents = listener.gqEventListenerEvents or {};
        listener.gqEventListenerEvents[event] = func;
        listener.OnEvent = function(self, event, ...)
            self.gqEventListenerEvents[event](self, ...);
        end;

        eventListeners[event] = eventListeners[event] or {};
        eventListeners[event][listener:GetGqEventListenerId()] = listener;
        return listener;
    end
end

--- Removes registered event listener.
---@param listener any listener object with :OnEvent(event, ...) and :GetGqEventListenerId() methods
---@param event string (optional) event. if omitted, the listener will be removed from all events
function c:RemoveEventListener(listener, event)
    if listener and listener:GetGqEventListenerId() then
        if event then
            if eventListeners[event] then
                eventListeners[event][listener:GetGqEventListenerId()] = nil;
            end
            listener.gqEventListenerEvents[event] = nil;
        else
            for event, _ in pairs(listener.gqEventListenerEvents) do
                if eventListeners[event] then
                    eventListeners[event][listener:GetGqEventListenerId()] = nil;
                end
            end
            listener.gqEventListenerEvents = {};
        end
        eventListeners[listener:GetGqEventListenerId()] = nil;
    end
    return listener;
end

--- Notifies registered event listeners about the given event.
---@param event string
function c:NotifyEventListeners(event, ...)
    if event and eventListeners[event] then
        for _, listener in pairs(eventListeners[event]) do
            local ok, err = pcall(listener.OnEvent, listener, event, ...);
            if not ok then
                geterrorhandler()(err);
            end
        end
    end
end
