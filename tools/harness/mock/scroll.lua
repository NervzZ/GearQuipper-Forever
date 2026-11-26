-- scroll.lua: the modern list stack of the forever branch, ported from Blizzard_SharedXML (DataProvider.lua,
-- Shared/Scroll/ScrollBox.lua, ScrollBoxListView.lua, ScrollBoxLinearView.lua, ScrollBar.lua, ScrollUtil.lua,
-- MinimalScrollBar.xml, ScrollTemplates.xml, ScrollBox.xml):
--   CreateDataProvider / DataProviderMixin (the real file, nearly verbatim)
--   WowScrollBoxList (ScrollBoxListMixin) + CreateScrollBoxListLinearView: frames come from per-template pools under
--     scrollBox.ScrollTarget; SetDataProvider releases every frame and acquires again (pool stack, so element i
--     usually gets the same frame back); a data provider change (Insert/Remove/Sort) keeps the frames of element
--     tables still present WITHOUT calling the initializer again and acquires/initializes only new ones, like in game.
--   No layout engine: every element gets a frame (the visible range is the whole list); extents come from
--     SetElementExtent / SetElementExtentCalculator / the template's <Size>; the visible extent is the ScrollBox's
--     own height (SetHeight/SetSize/XML <Size>; anchors alone give 0, so nothing scrolls).
--   MinimalScrollBar (Back / Forward steppers, Track.Thumb; ScrollBarMixin) and ScrollUtil.InitScrollBoxListWithScrollBar,
--     AddManagedScrollBarVisibilityBehavior, AddSelectionBehavior, Add*FrameCallback.
-- Helpers for scenarios: H.scrollBoxFrames(scrollBox) (frames in data order), H.scrollBoxFrameFor(scrollBox, pred),
-- H.scrollStep(scrollBar, "Forward"|"Back"), H.mouseWheel(frame, delta).
local H = ...;
local P = H.widgetState;

---------------------------------------------------------------------------
-- DataProvider
---------------------------------------------------------------------------
DataProviderMixin = CreateFromMixins(CallbackRegistryMixin);
DataProviderMixin:GenerateCallbackEvents({"OnSizeChanged", "OnInsert", "OnRemove", "OnSort", "OnMove"});

function DataProviderMixin:Init(tbl)
    CallbackRegistryMixin.OnLoad(self);
    self.collection = {};
    if tbl then
        self:InsertTable(tbl);
    end
end

function DataProviderMixin:IsVirtual()
    return false;
end

function DataProviderMixin:Enumerate(indexBegin, indexEnd)
    return CreateTableEnumerator(self.collection, indexBegin, indexEnd);
end

function DataProviderMixin:EnumerateEntireRange()
    return self:Enumerate();
end

function DataProviderMixin:ReverseEnumerate(indexBegin, indexEnd)
    return CreateTableReverseEnumerator(self.collection, indexBegin, indexEnd);
end

function DataProviderMixin:ReverseEnumerateEntireRange()
    return self:ReverseEnumerate();
end

function DataProviderMixin:GetCollection()
    return self.collection;
end

function DataProviderMixin:GetSize()
    return #self.collection;
end

function DataProviderMixin:IsEmpty()
    return self:GetSize() == 0;
end

function DataProviderMixin:InsertInternal(elementData, insertIndex)
    if insertIndex == nil then
        table.insert(self.collection, elementData);
        insertIndex = #self.collection;
    else
        table.insert(self.collection, insertIndex, elementData);
    end
    self:TriggerEvent(DataProviderMixin.Event.OnInsert, insertIndex, elementData, self:HasSortComparator());
end

function DataProviderMixin:InsertAtIndex(elementData, insertIndex)
    self:InsertInternal(elementData, insertIndex);
    self:TriggerEvent(DataProviderMixin.Event.OnSizeChanged, self:HasSortComparator());
    self:Sort();
end

function DataProviderMixin:Insert(...)
    local count = select("#", ...);
    for index = 1, count do
        self:InsertInternal((select(index, ...)));
    end
    if count > 0 then
        self:TriggerEvent(DataProviderMixin.Event.OnSizeChanged, self:HasSortComparator());
    end
    self:Sort();
end

function DataProviderMixin:InsertTable(tbl)
    self:InsertTableRange(tbl, 1, #tbl);
end

function DataProviderMixin:InsertTableRange(tbl, indexBegin, indexEnd)
    if indexEnd - indexBegin < 0 then
        return;
    end
    for index = indexBegin, indexEnd do
        self:InsertInternal(tbl[index]);
    end
    self:TriggerEvent(DataProviderMixin.Event.OnSizeChanged, self:HasSortComparator());
    self:Sort();
end

function DataProviderMixin:MoveElementDataToIndex(elementData, newIndex)
    local currentIndex = self:FindIndex(elementData);
    if not currentIndex then
        error("MoveElementDataToIndex requires elementData to exist.");
    end
    if currentIndex == newIndex then
        return;
    end
    self:RemoveIndex(currentIndex);
    self:InsertAtIndex(elementData, newIndex);
    self:TriggerEvent(DataProviderMixin.Event.OnMove, elementData, currentIndex, newIndex);
end

function DataProviderMixin:Remove(...)
    local removedIndex = nil;
    local originalSize = self:GetSize();
    local count = select("#", ...);
    while count >= 1 do
        local elementData = select(count, ...);
        local index = tIndexOf(self.collection, elementData);
        if index then
            table.remove(self.collection, index);
            self:TriggerEvent(DataProviderMixin.Event.OnRemove, elementData, index);
            removedIndex = index;
        end
        count = count - 1;
    end
    if self:GetSize() ~= originalSize then
        self:TriggerEvent(DataProviderMixin.Event.OnSizeChanged, false);
    end
    return removedIndex;
end

function DataProviderMixin:RemoveAllByPredicate(predicate)
    local index = self:GetSize();
    while index >= 1 do
        if predicate(self:Find(index)) then
            self:RemoveIndex(index);
        end
        index = index - 1;
    end
end

function DataProviderMixin:RemoveByPredicate(predicate)
    local _, elementData = self:FindByPredicate(predicate);
    if elementData then
        self:Remove(elementData);
    end
end

function DataProviderMixin:RemoveIndex(index)
    self:RemoveIndexRange(index, index);
end

function DataProviderMixin:RemoveIndexRange(indexBegin, indexEnd)
    local originalSize = self:GetSize();
    indexBegin = math.max(1, indexBegin);
    indexEnd = math.min(self:GetSize(), indexEnd);
    while indexEnd >= indexBegin do
        local elementData = self.collection[indexEnd];
        table.remove(self.collection, indexEnd);
        self:TriggerEvent(DataProviderMixin.Event.OnRemove, elementData, indexEnd);
        indexEnd = indexEnd - 1;
    end
    if self:GetSize() ~= originalSize then
        self:TriggerEvent(DataProviderMixin.Event.OnSizeChanged, false);
    end
end

function DataProviderMixin:ReplaceAtIndex(index, newElementData)
    self:RemoveIndex(index);
    self:InsertAtIndex(newElementData, index);
end

function DataProviderMixin:SetSortComparator(sortComparator, skipSort)
    self.sortComparator = sortComparator;
    if not skipSort then
        self:Sort();
    end
end

function DataProviderMixin:ClearSortComparator()
    self.sortComparator = nil;
end

function DataProviderMixin:HasSortComparator()
    return self.sortComparator ~= nil;
end

function DataProviderMixin:Sort(sortComparator)
    local comparator = self.sortComparator or sortComparator;
    if comparator then
        table.sort(self.collection, comparator);
        self:TriggerEvent(DataProviderMixin.Event.OnSort);
    end
end

function DataProviderMixin:Find(index)
    return self.collection[index];
end

function DataProviderMixin:FindLast()
    return self.collection[self:GetSize()];
end

function DataProviderMixin:FindIndex(elementData)
    for index, elementDataIter in self:Enumerate() do
        if elementDataIter == elementData then
            return index, elementDataIter;
        end
    end
end

function DataProviderMixin:FindByPredicate(predicate)
    for index, elementData in self:Enumerate() do
        if predicate(elementData) then
            return index, elementData;
        end
    end
end

function DataProviderMixin:FindElementDataByPredicate(predicate)
    local _, elementData = self:FindByPredicate(predicate);
    return elementData;
end

function DataProviderMixin:FindIndexByPredicate(predicate)
    return (self:FindByPredicate(predicate));
end

function DataProviderMixin:ContainsByPredicate(predicate)
    return self:FindByPredicate(predicate) ~= nil;
end

function DataProviderMixin:ForEach(func)
    for _, elementData in self:Enumerate() do
        func(elementData);
    end
end

function DataProviderMixin:ReverseForEach(func)
    for _, elementData in self:ReverseEnumerate() do
        func(elementData);
    end
end

function DataProviderMixin:Flush()
    local oldCollection = self.collection;
    self.collection = {};
    for index, elementData in ipairs(oldCollection) do
        self:TriggerEvent(DataProviderMixin.Event.OnRemove, elementData, index);
    end
    self:TriggerEvent(DataProviderMixin.Event.OnSizeChanged, false);
end

function CreateDataProvider(tbl)
    local dataProvider = CreateFromMixins(DataProviderMixin);
    dataProvider:Init(tbl);
    return dataProvider;
end

function CreateDataProviderByIndexCount(indexCount)
    local tbl = {};
    for index = 1, indexCount do
        table.insert(tbl, {index = index});
    end
    return CreateDataProvider(tbl);
end

function CreateDataProviderWithAssignedKey(tbl, key)
    local dataProvider = CreateDataProvider();
    for _, value in ipairs(tbl) do
        dataProvider:Insert({[key] = value});
    end
    return dataProvider;
end

---------------------------------------------------------------------------
-- ScrollController (shared by ScrollBox and ScrollBar)
---------------------------------------------------------------------------
ScrollControllerMixin = {Directions = {Increase = 1, Decrease = -1}};

function ScrollControllerMixin:OnLoad()
    self.panExtentPercentage = 0;
    self.allowScroll = true;
    self.scrollPercentage = 0;
    if not self.wheelPanScalar then
        self.wheelPanScalar = 2.0;
    end
end

function ScrollControllerMixin:IsHorizontal()
    return self.isHorizontal;
end

function ScrollControllerMixin:SetHorizontal(isHorizontal)
    self.isHorizontal = isHorizontal;
end

function ScrollControllerMixin:GetFrameExtent(frame)
    local width, height = frame:GetSize();
    return self.isHorizontal and width or height;
end

function ScrollControllerMixin:SetFrameExtent(frame, value)
    if self.isHorizontal then
        frame:SetWidth(value);
    else
        frame:SetHeight(value);
    end
end

function ScrollControllerMixin:SelectPointComponent()
    return 0;
end

function ScrollControllerMixin:GetScrollPercentage()
    return self.scrollPercentage or 0;
end

function ScrollControllerMixin:SetScrollPercentage(scrollPercentage)
    self.scrollPercentage = Saturate(scrollPercentage);
end

function ScrollControllerMixin:GetPanExtentPercentage()
    return self.panExtentPercentage or 0;
end

function ScrollControllerMixin:SetPanExtentPercentage(panExtentPercentage)
    self.panExtentPercentage = Saturate(panExtentPercentage);
end

function ScrollControllerMixin:GetWheelPanPercentage()
    return Saturate(self:GetPanExtentPercentage() * self.wheelPanScalar);
end

function ScrollControllerMixin:ScrollInDirection(scrollPercentage, direction)
    if self:IsScrollAllowed() then
        self:SetScrollPercentage(Saturate(self:GetScrollPercentage() + scrollPercentage * direction), true);
    end
end

function ScrollControllerMixin:ScrollIncrease()
    self:ScrollInDirection(self:GetWheelPanPercentage(), ScrollControllerMixin.Directions.Increase);
end

function ScrollControllerMixin:ScrollDecrease()
    self:ScrollInDirection(self:GetWheelPanPercentage(), ScrollControllerMixin.Directions.Decrease);
end

function ScrollControllerMixin:OnMouseWheel(value)
    if value < 0 then
        self:ScrollIncrease();
    else
        self:ScrollDecrease();
    end
end

function ScrollControllerMixin:IsScrollAllowed()
    return self.allowScroll;
end

function ScrollControllerMixin:SetScrollAllowed(allowScroll)
    self.allowScroll = allowScroll;
end

function ScrollControllerMixin:CanInterpolateScroll()
    return self.canInterpolateScroll;
end

function ScrollControllerMixin:SetInterpolateScroll(canInterpolateScroll)
    self.canInterpolateScroll = canInterpolateScroll;
end

function ScrollControllerMixin:EnableSnapToInterval() end
function ScrollControllerMixin:DisableSnapToInterval() end

---------------------------------------------------------------------------
-- frame pools of a view (one stack of inactive frames per template / frame type)
---------------------------------------------------------------------------
local function createFactory()
    local pools = {};
    local owner = {};
    local factory = {};
    function factory.Create(parent, templateOrType, resetter)
        local info = H.templateInfo(templateOrType);
        local frameType, template = templateOrType, nil;
        if info then
            frameType, template = info.type, templateOrType;
        end
        local key = frameType .. ":" .. (template or "");
        local pool = pools[key];
        if not pool then
            pool = {inactive = {}, frameType = frameType, template = template};
            pools[key] = pool;
        end
        local reset = resetter or function(_, frame)
            frame:Hide();
            frame:ClearAllPoints();
        end;
        local frame = table.remove(pool.inactive);
        local new = frame == nil;
        if new then
            frame = CreateFrame(frameType, nil, parent, template);
            reset(pool, frame, true);
        end
        owner[frame] = {pool = pool, reset = reset};
        return frame, new;
    end
    function factory.Release(frame)
        local o = owner[frame];
        if o then
            o.reset(o.pool, frame, false);
            table.insert(o.pool.inactive, frame);
            owner[frame] = nil;
        end
    end
    function factory.ReleaseAll()
        local frames = {};
        for frame in pairs(owner) do
            frames[#frames + 1] = frame;
        end
        for _, frame in ipairs(frames) do
            factory.Release(frame);
        end
    end
    function factory.Pools()
        return pools;
    end
    return factory;
end

---------------------------------------------------------------------------
-- ScrollBoxListLinearView
---------------------------------------------------------------------------
local InvalidationReason = EnumUtil.MakeEnum("DataProviderReassigned", "DataProviderContentsChanged");

ScrollBoxListViewMixin = CreateFromMixins(CallbackRegistryMixin);
ScrollBoxListViewMixin:GenerateCallbackEvents({"OnDataChanged", "OnDataProviderReassigned", "OnAcquiredFrame",
    "OnInitializedFrame", "OnReleasedFrame"});

ScrollBoxListLinearViewMixin = CreateFromMixins(ScrollBoxListViewMixin);

function ScrollBoxListLinearViewMixin:Init(top, bottom, left, right, spacing)
    CallbackRegistryMixin.OnLoad(self);
    self.frames = {};
    self.initializers = {};
    self.factoryObj = createFactory();
    self.extent = 0;
    self.canSignalWithoutInitializer = true;
    self:SetPadding(top, bottom, left, right, spacing);
end

function ScrollBoxListLinearViewMixin:IsInitialized()
    return true;
end

function ScrollBoxListLinearViewMixin:SetPadding(top, bottom, left, right, spacing)
    if type(top) == "table" then
        self.padding = top;
        return;
    end
    self.padding = {top = top or 0, bottom = bottom or 0, left = left or 0, right = right or 0, spacing = spacing or 0};
    local pad = self.padding;
    function pad.GetTop() return pad.top; end
    function pad.GetBottom() return pad.bottom; end
    function pad.GetLeft() return pad.left; end
    function pad.GetRight() return pad.right; end
    function pad.GetSpacing() return pad.spacing; end
end

function ScrollBoxListLinearViewMixin:GetPadding()
    return self.padding;
end

function ScrollBoxListLinearViewMixin:GetSpacing()
    return self.padding.spacing or 0;
end

function ScrollBoxListLinearViewMixin:IsHorizontal()
    return self.isHorizontal;
end

function ScrollBoxListLinearViewMixin:SetHorizontal(isHorizontal)
    self.isHorizontal = isHorizontal;
end

function ScrollBoxListLinearViewMixin:SetScrollBox(scrollBox)
    self.scrollBox = scrollBox;
end

function ScrollBoxListLinearViewMixin:GetScrollBox()
    return self.scrollBox;
end

function ScrollBoxListLinearViewMixin:GetScrollTarget()
    return self.scrollBox:GetScrollTarget();
end

function ScrollBoxListLinearViewMixin:GetFrames()
    return self.frames;
end

function ScrollBoxListLinearViewMixin:GetFrameCount()
    return #self.frames;
end

function ScrollBoxListLinearViewMixin:HasBiaxalLayout()
    return false;
end

function ScrollBoxListLinearViewMixin:SetElementInitializer(frameTemplateOrFrameType, initializer)
    self:SetElementFactory(function(factory, elementData)
        factory(frameTemplateOrFrameType, initializer);
    end);
    self.frameTemplateOrFrameType = frameTemplateOrFrameType;
end

function ScrollBoxListLinearViewMixin:SetElementFactory(elementFactory)
    self.elementFactory = elementFactory;
end

function ScrollBoxListLinearViewMixin:SetFrameFactoryResetter(resetter)
    self.frameFactoryResetter = resetter;
end

function ScrollBoxListLinearViewMixin:SetElementResetter(resetter)
    self.frameResetter = resetter;
end

function ScrollBoxListLinearViewMixin:SetVirtualized(virtualized)
    self.virtualized = virtualized;
end

function ScrollBoxListLinearViewMixin:IsVirtualized()
    return self.virtualized ~= false;
end

function ScrollBoxListLinearViewMixin:SetElementExtent(extent)
    self.elementExtent = math.max(extent, 1);
end

function ScrollBoxListLinearViewMixin:SetElementExtentCalculator(calculator)
    self.elementExtentCalculator = calculator;
end

function ScrollBoxListLinearViewMixin:GetElementExtentCalculator()
    return self.elementExtentCalculator;
end

function ScrollBoxListLinearViewMixin:SetElementIndentCalculator(calculator)
    self.elementIndentCalculator = calculator;
end

function ScrollBoxListLinearViewMixin:SetElementStretchDisabled(disabled)
    self.elementStretchDisabled = disabled;
end

function ScrollBoxListLinearViewMixin:IsElementStretchDisabled()
    return self.elementStretchDisabled;
end

function ScrollBoxListLinearViewMixin:SetPanExtent(panExtent)
    self.panExtent = panExtent;
end

do
    local template, initializer;
    local probe = function(frameTemplate, frameInitializer)
        template, initializer = frameTemplate, frameInitializer;
    end;
    function ScrollBoxListLinearViewMixin:GetFactoryDataFromElementData(elementData)
        self.elementFactory(probe, elementData);
        return template, initializer;
    end
end

function ScrollBoxListLinearViewMixin:CalculateFrameExtent(dataIndex, elementData)
    if self.elementExtent then
        return self.elementExtent;
    end
    if self.elementExtentCalculator then
        return self.elementExtentCalculator(dataIndex, elementData);
    end
    local template = self:GetFactoryDataFromElementData(elementData);
    local info = H.templateInfo(template);
    if not info then
        return 0;
    end
    return self.isHorizontal and info.width or info.height;
end

function ScrollBoxListLinearViewMixin:GetElementExtent(dataIndex)
    local elementData = self:FindElementData(dataIndex);
    if not elementData then
        return 0;
    end
    return self:CalculateFrameExtent(dataIndex, elementData);
end

function ScrollBoxListLinearViewMixin:GetExtentUntil(scrollBox, dataIndexEnd)
    local extent = 0;
    for index = 1, dataIndexEnd - 1 do
        extent = extent + self:GetElementExtent(index) + self:GetSpacing();
    end
    return extent;
end

function ScrollBoxListLinearViewMixin:GetExtentTo(scrollBox, dataIndexEnd)
    local extent = 0;
    for index = 1, dataIndexEnd do
        extent = extent + self:GetElementExtent(index);
    end
    return extent + math.max(dataIndexEnd - 1, 0) * self:GetSpacing();
end

function ScrollBoxListLinearViewMixin:RecalculateExtent(scrollBox)
    local size = self:GetDataProviderSize();
    local extent = size > 0 and self:GetExtentTo(scrollBox, size) or 0;
    self.extent = extent + scrollBox:GetExtentPadding();
end

function ScrollBoxListLinearViewMixin:GetExtent()
    return self.extent or 0;
end

function ScrollBoxListLinearViewMixin:GetPanExtent()
    if self.panExtent then
        return self.panExtent;
    end
    if self:GetDataProviderSize() > 0 then
        return self:GetElementExtent(1) + self:GetSpacing();
    end
    return 0;
end

-- no layout engine: every element is "visible"
function ScrollBoxListLinearViewMixin:CalculateDataIndices()
    local size = self:GetDataProviderSize();
    if size == 0 then
        return 0, 0;
    end
    return 1, size;
end

function ScrollBoxListLinearViewMixin:GetDataScrollOffset(scrollBox)
    return scrollBox:GetUpperPadding();
end

-- data provider
function ScrollBoxListLinearViewMixin:GetDataProvider()
    return self.dataProvider;
end

function ScrollBoxListLinearViewMixin:HasDataProvider()
    return self.dataProvider ~= nil;
end

function ScrollBoxListLinearViewMixin:GetDataProviderSize()
    return self.dataProvider and self.dataProvider:GetSize() or 0;
end

function ScrollBoxListLinearViewMixin:SetDataProvider(dataProvider)
    if dataProvider == nil then
        error("SetDataProvider() dataProvider was nil. Call RemoveDataProvider() if this was your intent.", 3);
    end
    if self.elementFactory == nil then
        error("SetDataProvider() elementFactory was nil. Call SetElementFactory() before setting the data provider.", 3);
    end
    self:RemoveDataProviderInternal();
    self.dataProvider = dataProvider;
    dataProvider:RegisterCallback(DataProviderMixin.Event.OnSizeChanged, self.OnDataProviderSizeChanged, self);
    dataProvider:RegisterCallback(DataProviderMixin.Event.OnSort, self.OnDataProviderSort, self);
    self:TriggerEvent(ScrollBoxListViewMixin.Event.OnDataProviderReassigned);
    self:SignalDataChangeEvent(InvalidationReason.DataProviderReassigned);
end

function ScrollBoxListLinearViewMixin:RemoveDataProviderInternal()
    if self.dataProvider then
        self.dataProvider:UnregisterCallback(DataProviderMixin.Event.OnSizeChanged, self);
        self.dataProvider:UnregisterCallback(DataProviderMixin.Event.OnSort, self);
    end
    self.dataProvider = nil;
end

function ScrollBoxListLinearViewMixin:RemoveDataProvider()
    self:RemoveDataProviderInternal();
    self:SignalDataChangeEvent(InvalidationReason.DataProviderReassigned);
end

function ScrollBoxListLinearViewMixin:FlushDataProvider()
    if self.dataProvider then
        self.dataProvider:Flush();
    end
end

function ScrollBoxListLinearViewMixin:OnDataProviderSizeChanged(pendingSort)
    if not pendingSort then
        self:SignalDataChangeEvent(InvalidationReason.DataProviderContentsChanged);
    end
end

function ScrollBoxListLinearViewMixin:OnDataProviderSort()
    self:SignalDataChangeEvent(InvalidationReason.DataProviderContentsChanged);
end

function ScrollBoxListLinearViewMixin:SignalDataChangeEvent(invalidationReason)
    self.invalidationReason = invalidationReason;
    self:TriggerEvent(ScrollBoxListViewMixin.Event.OnDataChanged);
end

function ScrollBoxListLinearViewMixin:EnumerateDataProvider(indexBegin, indexEnd)
    if not self.dataProvider then
        return CreateTableEnumerator({});
    end
    return self.dataProvider:Enumerate(indexBegin, indexEnd);
end

function ScrollBoxListLinearViewMixin:EnumerateDataProviderEntireRange()
    return self:EnumerateDataProvider();
end

function ScrollBoxListLinearViewMixin:ReverseEnumerateDataProviderEntireRange()
    if not self.dataProvider then
        return CreateTableReverseEnumerator({});
    end
    return self.dataProvider:ReverseEnumerate();
end

function ScrollBoxListLinearViewMixin:ForEachElementData(func)
    self.dataProvider:ForEach(func);
end

function ScrollBoxListLinearViewMixin:FindElementData(index)
    return self.dataProvider and self.dataProvider:Find(index);
end

function ScrollBoxListLinearViewMixin:FindElementDataIndex(elementData)
    return self.dataProvider and self.dataProvider:FindIndex(elementData);
end

function ScrollBoxListLinearViewMixin:FindElementDataByPredicate(predicate)
    return self.dataProvider and self.dataProvider:FindElementDataByPredicate(predicate);
end

function ScrollBoxListLinearViewMixin:FindElementDataIndexByPredicate(predicate)
    return self.dataProvider and self.dataProvider:FindIndexByPredicate(predicate);
end

function ScrollBoxListLinearViewMixin:FindByPredicate(predicate)
    if self.dataProvider then
        return self.dataProvider:FindByPredicate(predicate);
    end
end

function ScrollBoxListLinearViewMixin:ContainsElementDataByPredicate(predicate)
    return self.dataProvider ~= nil and self.dataProvider:ContainsByPredicate(predicate);
end

-- frames
function ScrollBoxListLinearViewMixin:ForEachFrame(func)
    for _, frame in ipairs({unpack(self.frames)}) do
        local result = func(frame, frame:GetElementData());
        if result then
            return result;
        end
    end
end

function ScrollBoxListLinearViewMixin:ReverseForEachFrame(func)
    for _, frame in ipairs_reverse({unpack(self.frames)}) do
        if func(frame, frame:GetElementData()) then
            return;
        end
    end
end

function ScrollBoxListLinearViewMixin:EnumerateFrames()
    return ipairs(self.frames);
end

function ScrollBoxListLinearViewMixin:FindFrame(elementData)
    for _, frame in ipairs(self.frames) do
        if frame:ElementDataMatches(elementData) then
            return frame;
        end
    end
end

function ScrollBoxListLinearViewMixin:FindFrameByPredicate(predicate)
    for _, frame in ipairs(self.frames) do
        if predicate(frame, frame:GetElementData()) then
            return frame;
        end
    end
end

function ScrollBoxListLinearViewMixin:FindFrameElementDataIndex(findFrame)
    for index, frame in ipairs(self.frames) do
        if frame == findFrame then
            return (self.dataIndexBegin or 1) + index - 1;
        end
    end
end

function ScrollBoxListLinearViewMixin:AssignAccessors(frame, elementData)
    local view = self;
    frame.GetData = function()
        return elementData;
    end;
    frame.GetElementData = function()
        return elementData;
    end;
    frame.GetElementDataIndex = function()
        return view:FindElementDataIndex(elementData);
    end;
    frame.ElementDataMatches = function(_, other)
        return elementData == other;
    end;
    local index = 1;
    frame.GetOrderIndex = function()
        return index;
    end;
    frame.SetOrderIndex = function(_, orderIndex)
        index = orderIndex;
    end;
end

function ScrollBoxListLinearViewMixin:UnassignAccessors(frame)
    frame.GetElementData, frame.GetElementDataIndex, frame.GetData = nil, nil, nil;
    frame.ElementDataMatches, frame.GetOrderIndex, frame.SetOrderIndex = nil, nil, nil;
end

function ScrollBoxListLinearViewMixin:AcquireInternal(dataIndex, elementData)
    if self.acquireLock then
        error("ScrollBoxListViewMixin:Acquire was reentrant.");
    end
    self.acquireLock = true;
    local frame, new;
    self.elementFactory(function(templateOrType, initializer)
        frame, new = self.factoryObj.Create(self:GetScrollTarget(), templateOrType, self.frameFactoryResetter);
        self.initializers[frame] = initializer or false;
    end, elementData);
    if not frame then
        self.acquireLock = false;
        error("ScrollBox: A frame was not returned from the element initializer or factory.");
    end
    table.insert(self.frames, frame);
    self.scrollBox:SetFrameExtent(frame, self:CalculateFrameExtent(dataIndex, elementData));
    self:AssignAccessors(frame, elementData);
    frame:SetOrderIndex(dataIndex);
    frame:Show();
    self:TriggerEvent(ScrollBoxListViewMixin.Event.OnAcquiredFrame, frame, elementData, new);
    self.acquireLock = false;
end

function ScrollBoxListLinearViewMixin:Release(frame)
    local elementData = frame:GetElementData();
    if self.frameResetter then
        self.frameResetter(frame, elementData);
    end
    self:TriggerEvent(ScrollBoxListViewMixin.Event.OnReleasedFrame, frame, elementData);
    tDeleteItem(self.frames, frame);
    self.factoryObj.Release(frame);
    self:UnassignAccessors(frame);
    self.initializers[frame] = nil;
end

function ScrollBoxListLinearViewMixin:Flush()
    for _, frame in ipairs_reverse({unpack(self.frames)}) do
        self:Release(frame);
    end
    self.frames = {};
    self.dataIndexBegin, self.dataIndexEnd = nil, nil;
    self:RemoveDataProviderInternal();
end

function ScrollBoxListLinearViewMixin:IsAcquireLocked()
    return self.acquireLock;
end

function ScrollBoxListLinearViewMixin:InvokeInitializer(frame, initializer)
    local elementData = frame:GetElementData();
    if initializer then
        initializer(frame, elementData);
    end
    if initializer or self.canSignalWithoutInitializer then
        self:TriggerEvent(ScrollBoxListViewMixin.Event.OnInitializedFrame, frame, elementData);
    end
end

-- in data order (the client's order is unspecified; data order keeps the mock deterministic)
function ScrollBoxListLinearViewMixin:InvokeInitializers()
    local pending = self.initializers;
    self.initializers = {};
    for _, frame in ipairs({unpack(self.frames)}) do
        local initializer = pending[frame];
        if initializer ~= nil then
            self:InvokeInitializer(frame, initializer or nil);
        end
    end
end

function ScrollBoxListLinearViewMixin:ReinitializeFrames()
    for _, frame in ipairs({unpack(self.frames)}) do
        local _, initializer = self:GetFactoryDataFromElementData(frame:GetElementData());
        self:InvokeInitializer(frame, initializer);
    end
end

function ScrollBoxListLinearViewMixin:GetDataIndexBegin()
    return self.dataIndexBegin or 0;
end

function ScrollBoxListLinearViewMixin:GetDataIndexEnd()
    return self.dataIndexEnd or 0;
end

-- ScrollBoxListViewMixin:ValidateDataRange: recycles the frames of element tables still present unless the
-- data provider was reassigned.
function ScrollBoxListLinearViewMixin:ValidateDataRange(scrollBox)
    local oldBegin, oldEnd = self.dataIndexBegin, self.dataIndexEnd;
    local dataIndexBegin, dataIndexEnd = self:CalculateDataIndices(scrollBox);
    local invalidated = self.invalidationReason ~= nil;
    if not (invalidated or oldBegin ~= dataIndexBegin or oldEnd ~= dataIndexEnd) then
        return false;
    end
    self.dataIndexBegin, self.dataIndexEnd = dataIndexBegin, dataIndexEnd;
    local canRecycle = not invalidated or self.invalidationReason ~= InvalidationReason.DataProviderReassigned;
    if canRecycle then
        for _, frame in ipairs(self.frames) do
            if type(frame:GetElementData()) ~= "table" then
                canRecycle = false;
                break;
            end
        end
    end
    if canRecycle then
        local acquireList, releaseList = {}, {};
        for _, frame in ipairs(self.frames) do
            releaseList[frame:GetElementData()] = frame;
        end
        if dataIndexBegin > 0 then
            for dataIndex, elementData in self:EnumerateDataProvider(dataIndexBegin, dataIndexEnd) do
                local frame = releaseList[elementData];
                if frame then
                    frame:SetOrderIndex(dataIndex);
                    releaseList[elementData] = nil;
                else
                    table.insert(acquireList, dataIndex);
                end
            end
        end
        local releasing = {};
        for _, frame in ipairs(self.frames) do
            if releaseList[frame:GetElementData()] == frame then
                releasing[#releasing + 1] = frame;
            end
        end
        for _, frame in ipairs(releasing) do
            self:Release(frame);
        end
        for _, dataIndex in ipairs(acquireList) do
            self:AcquireInternal(dataIndex, self:FindElementData(dataIndex));
        end
    else
        for _, frame in ipairs_reverse({unpack(self.frames)}) do
            self:Release(frame);
        end
        if dataIndexEnd > 0 then
            for dataIndex = dataIndexBegin, dataIndexEnd do
                self:AcquireInternal(dataIndex, self:FindElementData(dataIndex));
            end
        end
    end
    self.invalidationReason = nil;
    table.sort(self.frames, function(lhs, rhs)
        return lhs:GetOrderIndex() < rhs:GetOrderIndex();
    end);
    return true;
end

-- Anchors each frame below the previous one on the scroll target (stretched to its width unless disabled).
function ScrollBoxListLinearViewMixin:Layout()
    local scrollTarget = self:GetScrollTarget();
    local offset = 0;
    for _, frame in ipairs(self.frames) do
        local indent = self.elementIndentCalculator and self.elementIndentCalculator(frame:GetElementData()) or 0;
        frame:ClearAllPoints();
        if self.isHorizontal then
            frame:SetPoint("TOPLEFT", scrollTarget, "TOPLEFT", offset, -indent);
            frame:SetPoint("BOTTOMLEFT", scrollTarget, "BOTTOMLEFT", offset, 0);
        else
            frame:SetPoint("TOPLEFT", scrollTarget, "TOPLEFT", indent, -offset);
            if not self.elementStretchDisabled then
                frame:SetPoint("TOPRIGHT", scrollTarget, "TOPRIGHT", 0, -offset);
            end
        end
        offset = offset + self.scrollBox:GetFrameExtent(frame) + self:GetSpacing();
    end
end

function CreateScrollBoxListLinearView(top, bottom, left, right, spacing)
    return CreateAndInitFromMixin(ScrollBoxListLinearViewMixin, top or 0, bottom or 0, left or 0, right or 0,
        spacing or 0);
end

---------------------------------------------------------------------------
-- ScrollBox
---------------------------------------------------------------------------
BaseScrollBoxEvents = CopyValuesAsKeys({"OnAllowScrollChanged", "OnSizeChanged", "OnScroll", "OnLayout"});

ScrollBoxConstants = {UpdateQueued = false, UpdateImmediately = true, NoScrollInterpolation = true,
    RetainScrollPosition = true, DiscardScrollPosition = false, AlignBegin = 0, AlignCenter = 0.5, AlignEnd = 1,
    AlignNearest = -1, ScrollBegin = MathUtil.Epsilon, ScrollEnd = 1 - MathUtil.Epsilon, StopIteration = true,
    ContinueIteration = false, FillExtent = 0};

ScrollBoxBaseMixin = CreateFromMixins(CallbackRegistryMixin, ScrollControllerMixin);

function ScrollBoxBaseMixin:OnLoad()
    CallbackRegistryMixin.OnLoad(self);
    ScrollControllerMixin.OnLoad(self);
    if not self:GetScrollTarget() then
        error("ScrollBoxBaseMixin:OnLoad expected a scroll target frame.");
    end
end

function ScrollBoxBaseMixin:Init(view)
    self:SetView(view);
    self:ScrollToBegin();
end

function ScrollBoxBaseMixin:SetView(view)
    if not view then
        error("ScrollBoxBaseMixin:SetView requires a valid view.", 2);
    end
    if type(view.SetScrollBox) ~= "function" or type(view.IsHorizontal) ~= "function" then
        error("ScrollBoxBaseMixin:SetView requires a ScrollBoxViewMixin-compatible view.", 2);
    end
    local oldDataProvider = nil;
    local oldView = self:GetView();
    if oldView then
        oldDataProvider = oldView:GetDataProvider();
        oldView:Flush();
    end
    self.view = view;
    view:SetScrollBox(self);
    self:SetHorizontal(view:IsHorizontal());
    if oldDataProvider then
        view:SetDataProvider(oldDataProvider);
    end
    if oldView then
        self:FullUpdate(ScrollBoxConstants.UpdateImmediately);
    end
end

function ScrollBoxBaseMixin:GetView()
    return self.view;
end

function ScrollBoxBaseMixin:HasView()
    return self.view ~= nil;
end

function ScrollBoxBaseMixin:GetScrollTarget()
    return self.ScrollTarget;
end

function ScrollBoxBaseMixin:OnSizeChanged(width, height)
    self:Update(true);
    self:TriggerEvent(BaseScrollBoxEvents.OnSizeChanged, width, height, self:GetVisibleExtentPercentage());
end

-- the mock updates immediately also for queued updates (no layout pass to wait for)
function ScrollBoxBaseMixin:FullUpdate()
    self:FullUpdateInternal();
end

function ScrollBoxBaseMixin:SetUpdateLocked(locked)
    self.updateLock = locked;
end

function ScrollBoxBaseMixin:IsUpdateLocked()
    return self.updateLock;
end

function ScrollBoxBaseMixin:FullUpdateInternal()
    local oldScrollOffset = self:GetDerivedScrollOffset();
    self:GetView():RecalculateExtent(self);
    local scrollRange = self:GetDerivedScrollRange();
    if scrollRange > 0 then
        local delta = self:GetDerivedScrollOffset() - oldScrollOffset;
        ScrollControllerMixin.SetScrollPercentage(self, self:GetScrollPercentage() - delta / scrollRange);
    else
        ScrollControllerMixin.SetScrollPercentage(self, 0);
    end
    self:SetPanExtentPercentage(self:CalculatePanExtentPercentage());
    self:Update(true);
    self:TriggerEvent(BaseScrollBoxEvents.OnLayout);
end

function ScrollBoxBaseMixin:Layout()
    local view = self:GetView();
    if view then
        view:Layout(self);
    end
end

function ScrollBoxBaseMixin:SetScrollTargetOffset(offset)
    local scrollTarget = self:GetScrollTarget();
    scrollTarget:SetPoint("TOPLEFT", self, "TOPLEFT", self:GetLeftPadding(), offset);
    scrollTarget:SetPoint("TOPRIGHT", self, "TOPRIGHT", -self:GetRightPadding(), offset);
    self:TriggerEvent(BaseScrollBoxEvents.OnScroll, self:GetScrollPercentage(), self:GetVisibleExtentPercentage(),
        self:GetPanExtentPercentage());
end

function ScrollBoxBaseMixin:ScrollInDirection(scrollPercentage, direction)
    ScrollControllerMixin.ScrollInDirection(self, scrollPercentage, direction);
    self:Update();
end

function ScrollBoxBaseMixin:ScrollToBegin(noInterpolation)
    self:SetScrollPercentage(0, noInterpolation);
end

function ScrollBoxBaseMixin:ScrollToEnd(noInterpolation)
    self:SetScrollPercentage(1, noInterpolation);
end

function ScrollBoxBaseMixin:SetScrollPercentage(scrollPercentage)
    if not ApproximatelyEqual(self:GetScrollPercentage(), scrollPercentage) then
        self:SetScrollPercentageInternal(scrollPercentage);
    end
end

function ScrollBoxBaseMixin:SetScrollPercentageInternal(scrollPercentage)
    ScrollControllerMixin.SetScrollPercentage(self, scrollPercentage);
    self:Update();
end

function ScrollBoxBaseMixin:GetPanExtent()
    return self:GetView():GetPanExtent(self);
end

function ScrollBoxBaseMixin:SetPanExtent(panExtent)
    self:GetView():SetPanExtent(panExtent);
end

function ScrollBoxBaseMixin:GetExtent()
    return self:GetDerivedExtent();
end

function ScrollBoxBaseMixin:GetVisibleExtent()
    return Round(self:GetFrameExtent(self));
end

function ScrollBoxBaseMixin:GetFrames()
    return self:GetView():GetFrames();
end

function ScrollBoxBaseMixin:GetFrameCount()
    return self:GetView():GetFrameCount();
end

function ScrollBoxBaseMixin:FindFrame(elementData)
    return self:GetView():FindFrame(elementData);
end

function ScrollBoxBaseMixin:FindFrameByPredicate(predicate)
    return self:GetView():FindFrameByPredicate(predicate);
end

function ScrollBoxBaseMixin:CalculatePanExtentPercentage()
    local scrollRange = self:GetDerivedScrollRange();
    if scrollRange > 0 then
        return self:GetPanExtent() / scrollRange;
    end
    return 0;
end

function ScrollBoxBaseMixin:CalculateScrollPercentage()
    local scrollRange = self:GetDerivedScrollRange();
    if scrollRange > 0 then
        return self:GetDerivedScrollOffset() / scrollRange;
    end
    return 0;
end

function ScrollBoxBaseMixin:HasScrollableExtent()
    return WithinRangeExclusive(self:GetVisibleExtentPercentage(), MathUtil.Epsilon, 1 - MathUtil.Epsilon);
end

function ScrollBoxBaseMixin:SetScrollAllowed(allowScroll)
    local oldAllowScroll = self:IsScrollAllowed();
    ScrollControllerMixin.SetScrollAllowed(self, allowScroll);
    self:Update();
    if oldAllowScroll ~= allowScroll then
        self:TriggerEvent(BaseScrollBoxEvents.OnAllowScrollChanged, allowScroll);
    end
end

function ScrollBoxBaseMixin:GetDerivedScrollRange()
    return math.max(0, self:GetDerivedExtent() - self:GetVisibleExtent());
end

function ScrollBoxBaseMixin:GetDerivedScrollOffset()
    return self:GetDerivedScrollRange() * self:GetScrollPercentage();
end

function ScrollBoxBaseMixin:SanitizeAlignment(alignment, extent)
    if not self.alignmentOverlapIgnored and extent > self:GetVisibleExtent() then
        return 0;
    end
    return alignment and Saturate(alignment) or ScrollBoxConstants.AlignCenter;
end

function ScrollBoxBaseMixin:ScrollToOffsetWithAdjustment(offset, frameExtent, alignment, noInterpolation)
    alignment = self:SanitizeAlignment(alignment, frameExtent);
    local alignedOffset = offset + (frameExtent * alignment) - (self:GetVisibleExtent() * alignment);
    self:ScrollToOffset(alignedOffset, noInterpolation);
end

function ScrollBoxBaseMixin:ScrollToOffset(offset, noInterpolation)
    local scrollRange = self:GetDerivedScrollRange();
    if scrollRange > 0 then
        self:SetScrollPercentage(offset / scrollRange, noInterpolation);
    end
end

function ScrollBoxBaseMixin:GetVisibleExtentPercentage()
    local extent = self:GetDerivedExtent();
    if extent > 0 then
        return self:GetVisibleExtent() / extent;
    end
    return 0;
end

function ScrollBoxBaseMixin:GetDerivedExtent()
    local view = self:GetView();
    return view and view:GetExtent() or 0;
end

function ScrollBoxBaseMixin:GetUpperPadding()
    local view = self:GetView();
    return view and view:GetPadding().top or 0;
end

function ScrollBoxBaseMixin:GetLowerPadding()
    local view = self:GetView();
    return view and view:GetPadding().bottom or 0;
end

function ScrollBoxBaseMixin:GetTopPadding()
    return self:GetUpperPadding();
end

function ScrollBoxBaseMixin:GetBottomPadding()
    return self:GetLowerPadding();
end

function ScrollBoxBaseMixin:GetLeftPadding()
    local view = self:GetView();
    return view and view:GetPadding().left or 0;
end

function ScrollBoxBaseMixin:GetRightPadding()
    local view = self:GetView();
    return view and view:GetPadding().right or 0;
end

function ScrollBoxBaseMixin:GetExtentPadding()
    return self:GetUpperPadding() + self:GetLowerPadding();
end

function ScrollBoxBaseMixin:SetEdgeFadeLength() end
function ScrollBoxBaseMixin:SetUseShadowsForEdgeFade() end
function ScrollBoxBaseMixin:SetAlignmentOverlapIgnored(ignored)
    self.alignmentOverlapIgnored = ignored;
end

ScrollBoxListMixin = CreateFromMixins(ScrollBoxBaseMixin);
ScrollBoxListMixin:GenerateCallbackEvents({BaseScrollBoxEvents.OnScroll, BaseScrollBoxEvents.OnSizeChanged,
    BaseScrollBoxEvents.OnAllowScrollChanged, BaseScrollBoxEvents.OnLayout, "OnAcquiredFrame", "OnInitializedFrame",
    "OnReleasedFrame", "OnDataRangeChanged", "OnUpdate", "OnDataProviderReassigned"});

function ScrollBoxListMixin:Init(view)
    self:Flush();
    ScrollBoxBaseMixin.Init(self, view);
end

function ScrollBoxListMixin:SetView(view)
    local oldView = self:GetView();
    if oldView then
        for _, event in ipairs({"OnDataChanged", "OnDataProviderReassigned", "OnAcquiredFrame", "OnInitializedFrame",
            "OnReleasedFrame"}) do
            oldView:UnregisterCallback(event, self);
        end
    end
    ScrollBoxBaseMixin.SetView(self, view);
    view:RegisterCallback(ScrollBoxListViewMixin.Event.OnDataChanged, self.OnViewDataChanged, self);
    view:RegisterCallback(ScrollBoxListViewMixin.Event.OnDataProviderReassigned, self.OnViewDataProviderReassigned, self);
    view:RegisterCallback(ScrollBoxListViewMixin.Event.OnAcquiredFrame, self.OnViewAcquiredFrame, self);
    view:RegisterCallback(ScrollBoxListViewMixin.Event.OnInitializedFrame, self.OnViewInitializedFrame, self);
    view:RegisterCallback(ScrollBoxListViewMixin.Event.OnReleasedFrame, self.OnViewReleasedFrame, self);
end

function ScrollBoxListMixin:Flush()
    local view = self:GetView();
    if view then
        view:Flush();
    end
end

for _, name in ipairs({"ForEachFrame", "ReverseForEachFrame", "ForEachElementData", "EnumerateFrames",
    "ReinitializeFrames", "EnumerateDataProviderEntireRange", "EnumerateDataProvider",
    "ReverseEnumerateDataProviderEntireRange", "FindElementData", "FindElementDataByPredicate", "FindElementDataIndex",
    "FindElementDataIndexByPredicate", "FindByPredicate", "FindFrameElementDataIndex", "ContainsElementDataByPredicate",
    "GetDataProvider", "HasDataProvider", "RemoveDataProvider", "FlushDataProvider", "GetDataIndexBegin",
    "GetDataIndexEnd", "IsVirtualized", "GetElementExtent"}) do
    ScrollBoxListMixin[name] = function(self, ...)
        return self:GetView()[name](self:GetView(), ...);
    end
end

function ScrollBoxListMixin:GetExtentUntil(dataIndex)
    return self:GetView():GetExtentUntil(self, dataIndex) + self:GetUpperPadding();
end

function ScrollBoxListMixin:SetDataProvider(dataProvider, retainScrollPosition)
    local view = self:GetView();
    if not view then
        error("A view is required before assigning the data provider.", 2);
    end
    view:SetDataProvider(dataProvider);
    if not retainScrollPosition then
        self:ScrollToBegin(ScrollBoxConstants.NoScrollInterpolation);
    end
end

function ScrollBoxListMixin:GetDataProviderSize()
    local view = self:GetView();
    return view and view:GetDataProviderSize() or 0;
end

function ScrollBoxListMixin:OnViewDataChanged()
    self:FullUpdate(ScrollBoxConstants.UpdateImmediately);
end

function ScrollBoxListMixin:OnViewDataProviderReassigned()
    self:TriggerEvent(ScrollBoxListMixin.Event.OnDataProviderReassigned);
end

function ScrollBoxListMixin:Rebuild(retainScrollPosition)
    local view = self:GetView();
    if view then
        self:SetDataProvider(view:GetDataProvider(), retainScrollPosition);
    end
end

function ScrollBoxListMixin:OnViewAcquiredFrame(frame, elementData, new)
    self:TriggerEvent(ScrollBoxListMixin.Event.OnAcquiredFrame, frame, elementData, new);
end

function ScrollBoxListMixin:OnViewInitializedFrame(frame, elementData)
    self:TriggerEvent(ScrollBoxListMixin.Event.OnInitializedFrame, frame, elementData);
end

function ScrollBoxListMixin:OnViewReleasedFrame(frame, oldElementData)
    self:TriggerEvent(ScrollBoxListMixin.Event.OnReleasedFrame, frame, oldElementData);
end

function ScrollBoxListMixin:FullUpdateInternal()
    local view = self:GetView();
    if not view or not view:IsAcquireLocked() then
        ScrollBoxBaseMixin.FullUpdateInternal(self);
    end
end

function ScrollBoxListMixin:Update(forceLayout)
    if self:IsUpdateLocked() then
        return;
    end
    local view = self:GetView();
    if not view or view:IsAcquireLocked() then
        return;
    end
    self:SetUpdateLocked(true);
    local changed = view:ValidateDataRange(self);
    if changed or forceLayout then
        self:Layout();
    end
    self:SetScrollTargetOffset(self:GetDerivedScrollOffset() - view:GetDataScrollOffset(self));
    self:SetPanExtentPercentage(self:CalculatePanExtentPercentage());
    if changed then
        view:InvokeInitializers();
        self:TriggerEvent(ScrollBoxListMixin.Event.OnDataRangeChanged, self:GetDataIndexBegin(), self:GetDataIndexEnd());
    end
    self:TriggerEvent(ScrollBoxListMixin.Event.OnUpdate);
    self:SetUpdateLocked(false);
end

function ScrollBoxListMixin:ScrollToNearest(dataIndex, offset, noInterpolation)
    return self:ScrollToElementDataIndex(dataIndex, ScrollBoxConstants.AlignNearest, offset, noInterpolation);
end

function ScrollBoxListMixin:ScrollToElementDataIndex(dataIndex, alignment, offset, noInterpolation)
    local elementData = self:FindElementData(dataIndex);
    if not elementData then
        return nil;
    end
    offset = offset or 0;
    alignment = alignment or ScrollBoxConstants.AlignCenter;
    local extentUntil = self:GetExtentUntil(dataIndex);
    local elementExtent = self:GetElementExtent(dataIndex);
    if alignment == ScrollBoxConstants.AlignNearest then
        local scrollOffset = self:GetDerivedScrollOffset();
        if extentUntil + elementExtent > scrollOffset + self:GetVisibleExtent() then
            alignment = ScrollBoxConstants.AlignEnd;
        elseif extentUntil < scrollOffset then
            alignment = ScrollBoxConstants.AlignBegin;
        else
            return;
        end
    end
    self:ScrollToOffsetWithAdjustment(extentUntil - offset, elementExtent, alignment, noInterpolation);
    return elementData;
end

function ScrollBoxListMixin:ScrollToElementData(elementData, alignment, offset, noInterpolation)
    local dataIndex = self:FindElementDataIndex(elementData);
    if dataIndex then
        return self:ScrollToElementDataIndex(dataIndex, alignment, offset, noInterpolation);
    end
end

function ScrollBoxListMixin:ScrollToElementDataByPredicate(predicate, alignment, offset, noInterpolation)
    local dataIndex = self:FindElementDataIndexByPredicate(predicate);
    if dataIndex then
        return self:ScrollToElementDataIndex(dataIndex, alignment, offset, noInterpolation);
    end
end

---------------------------------------------------------------------------
-- ScrollBar (MinimalScrollBar)
---------------------------------------------------------------------------
ScrollBarMixin = CreateFromMixins(CallbackRegistryMixin, ScrollControllerMixin, EventFrameMixin);
ScrollBarMixin:GenerateCallbackEvents({"OnScroll", "OnAllowScrollChanged"});

function ScrollBarMixin:OnLoad()
    ScrollControllerMixin.OnLoad(self);
    self.visibleExtentPercentage = 0;
    local level = self:GetFrameLevel();
    self:GetTrack():SetFrameLevel(level + 2);
    self:GetBackStepper():SetFrameLevel(level + 3);
    self:GetForwardStepper():SetFrameLevel(level + 3);
    self:GetThumb():SetFrameLevel(level + 3);
    for _, stepper in ipairs({self:GetBackStepper(), self:GetForwardStepper()}) do
        stepper:SetScript("OnMouseDown", function(button, buttonName)
            if button:IsEnabled() and buttonName ~= "RightButton" then
                self:ScrollStepInDirection(button.direction);
            end
        end);
    end
    self:DisableControls();
end

function ScrollBarMixin:Init(visibleExtentPercentage, panExtentPercentage)
    self:SetVisibleExtentPercentage(visibleExtentPercentage);
    self:SetPanExtentPercentage(panExtentPercentage);
end

function ScrollBarMixin:GetBackStepper()
    return self.Back;
end

function ScrollBarMixin:GetForwardStepper()
    return self.Forward;
end

function ScrollBarMixin:GetTrack()
    return self.Track;
end

function ScrollBarMixin:GetThumb()
    return self.Track.Thumb;
end

function ScrollBarMixin:GetThumbAnchor()
    return self.thumbAnchor or "TOP";
end

function ScrollBarMixin:ScrollInDirection(percentage, direction)
    ScrollControllerMixin.ScrollInDirection(self, percentage, direction);
    self:Update();
    self:TriggerEvent(ScrollBarMixin.Event.OnScroll, self:GetScrollPercentage());
end

function ScrollBarMixin:ScrollStepInDirection(direction)
    self:ScrollInDirection(self:GetPanExtentPercentage(), direction);
end

function ScrollBarMixin:SetVisibleExtentPercentage(visibleExtentPercentage)
    self.visibleExtentPercentage = Saturate(visibleExtentPercentage);
    self:Update();
end

function ScrollBarMixin:GetVisibleExtentPercentage()
    return self.visibleExtentPercentage or 0;
end

function ScrollBarMixin:ScrollToBegin()
    self:SetScrollPercentage(0);
end

function ScrollBarMixin:ScrollToEnd()
    self:SetScrollPercentage(1);
end

function ScrollBarMixin:SetScrollPercentage(scrollPercentage)
    self:SetScrollPercentageInternal(scrollPercentage);
end

function ScrollBarMixin:SetScrollPercentageInternal(scrollPercentage)
    ScrollControllerMixin.SetScrollPercentage(self, scrollPercentage);
    self:Update();
    self:TriggerEvent(ScrollBarMixin.Event.OnScroll, self:GetScrollPercentage());
end

function ScrollBarMixin:HasScrollableExtent()
    return WithinRangeExclusive(self:GetVisibleExtentPercentage(), MathUtil.Epsilon, 1 - MathUtil.Epsilon);
end

function ScrollBarMixin:SetScrollAllowed(allowScroll)
    if self:IsScrollAllowed() ~= allowScroll then
        ScrollControllerMixin.SetScrollAllowed(self, allowScroll);
        self:Update();
        self:TriggerEvent(ScrollBarMixin.Event.OnAllowScrollChanged, allowScroll);
    end
end

function ScrollBarMixin:SetHideIfUnscrollable(hide)
    self.hideIfUnscrollable = hide;
    self:Update();
end

function ScrollBarMixin:Update()
    local backEnabled, forwardEnabled = ScrollUtil.GetScrollableDirections(self);
    self:GetBackStepper():SetEnabled(backEnabled);
    self:GetForwardStepper():SetEnabled(forwardEnabled);
    local hasScrollableExtent = self:HasScrollableExtent();
    local thumb = self:GetThumb();
    thumb:SetShown(hasScrollableExtent);
    thumb:SetEnabled(hasScrollableExtent and self:IsScrollAllowed());
    if self.hideIfUnscrollable then
        self:SetShown(hasScrollableExtent);
    end
end

function ScrollBarMixin:DisableControls()
    self:GetBackStepper():SetEnabled(false);
    self:GetForwardStepper():SetEnabled(false);
    self:GetThumb():Hide();
    self:GetThumb():SetEnabled(false);
end

---------------------------------------------------------------------------
-- ScrollUtil
---------------------------------------------------------------------------
ScrollUtil = {};

function ScrollUtil.GetScrollableDirections(scrollBox)
    local scrollPercentage = scrollBox:GetScrollPercentage();
    local scrollEnabled = scrollBox:HasScrollableExtent() and scrollBox:IsScrollAllowed();
    return scrollEnabled and scrollPercentage > MathUtil.Epsilon,
        scrollEnabled and scrollPercentage < (1 - MathUtil.Epsilon);
end

function ScrollUtil.AddInitializedFrameCallback(scrollBox, callback, owner, iterateExisting)
    if iterateExisting then
        scrollBox:ForEachFrame(callback);
    end
    scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnInitializedFrame, function(o, frame, elementData)
        callback(o, frame, elementData);
    end, owner);
end

function ScrollUtil.AddAcquiredFrameCallback(scrollBox, callback, owner, iterateExisting)
    if iterateExisting then
        scrollBox:ForEachFrame(callback);
    end
    scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnAcquiredFrame, function(o, frame, elementData, new)
        callback(o, frame, elementData, new);
    end, owner);
end

function ScrollUtil.AddReleasedFrameCallback(scrollBox, callback, owner)
    scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnReleasedFrame, function(o, frame, elementData)
        callback(o, frame, elementData);
    end, owner);
end

local function bind(scrollBox, scrollBar)
    if scrollBox.registeredScrollBar and scrollBox.registeredScrollBar ~= scrollBar then
        error("ScrollUtil.RegisterScrollBoxWithScrollBar expected a 1:1 pairing, but this ScrollBox is already " ..
            "registered with another ScrollBar.", 3);
    end
    if scrollBox.registeredScrollBar ~= scrollBar then
        scrollBox:RegisterCallback(BaseScrollBoxEvents.OnScroll, function(o, scrollPercentage, visibleExtentPercentage,
            panExtentPercentage)
            scrollBar:SetScrollPercentage(scrollPercentage, ScrollBoxConstants.NoScrollInterpolation);
            scrollBar:SetVisibleExtentPercentage(visibleExtentPercentage);
            scrollBar:SetPanExtentPercentage(panExtentPercentage);
        end, scrollBar);
        scrollBox:RegisterCallback(BaseScrollBoxEvents.OnSizeChanged, function(o, width, height, visibleExtentPercentage)
            scrollBar:SetVisibleExtentPercentage(visibleExtentPercentage);
        end, scrollBar);
        scrollBox:RegisterCallback(BaseScrollBoxEvents.OnAllowScrollChanged, function(o, allowScroll)
            scrollBar:SetScrollAllowed(allowScroll);
        end, scrollBar);
        scrollBox.registeredScrollBar = scrollBar;
    end
    if scrollBar.registeredScrollBox and scrollBar.registeredScrollBox ~= scrollBox then
        error("ScrollUtil.RegisterScrollBoxWithScrollBar expected a 1:1 pairing, but this ScrollBar is already " ..
            "registered with another ScrollBox.", 3);
    end
    if scrollBar.registeredScrollBox ~= scrollBox then
        scrollBar:RegisterCallback(BaseScrollBoxEvents.OnScroll, function(o, scrollPercentage)
            scrollBox:SetScrollPercentage(scrollPercentage, ScrollBoxConstants.NoScrollInterpolation);
        end, scrollBox);
        scrollBar:RegisterCallback(BaseScrollBoxEvents.OnAllowScrollChanged, function(o, allowScroll)
            scrollBox:SetScrollAllowed(allowScroll);
        end, scrollBox);
        scrollBar.registeredScrollBox = scrollBox;
    end
end

function ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, scrollBoxView)
    bind(scrollBox, scrollBar);
    scrollBox:Init(scrollBoxView);
    scrollBar:Init(scrollBox:GetVisibleExtentPercentage(), scrollBox:CalculatePanExtentPercentage());
end
ScrollUtil.InitScrollBoxWithScrollBar = ScrollUtil.InitScrollBoxListWithScrollBar;

function ScrollUtil.RegisterScrollBoxWithScrollBar(scrollBox, scrollBar)
    bind(scrollBox, scrollBar);
end

ManagedScrollBarVisibilityBehaviorMixin = CreateFromMixins(CallbackRegistryMixin);
ManagedScrollBarVisibilityBehaviorMixin:GenerateCallbackEvents({"OnVisibilityChanged"});

function ManagedScrollBarVisibilityBehaviorMixin:Init(scrollBox, scrollBar, withBar, withoutBar)
    CallbackRegistryMixin.OnLoad(self);
    self.scrollBox, self.scrollBar = scrollBox, scrollBar;
    if withBar and withoutBar then
        self.scrollBoxAnchorsWithBar, self.scrollBoxAnchorsWithoutBar = withBar, withoutBar;
    end
    scrollBox:RegisterCallback(BaseScrollBoxEvents.OnLayout, self.EvaluateVisibility, self);
    scrollBox:RegisterCallback(BaseScrollBoxEvents.OnSizeChanged, function()
        self:EvaluateVisibility();
    end, scrollBar);
    self:EvaluateVisibility(true);
end

function ManagedScrollBarVisibilityBehaviorMixin:GetScrollBox()
    return self.scrollBox;
end

function ManagedScrollBarVisibilityBehaviorMixin:GetScrollBar()
    return self.scrollBar;
end

function ManagedScrollBarVisibilityBehaviorMixin:EvaluateVisibility(force)
    local visible = self.scrollBox:HasScrollableExtent();
    if not force and visible == self.scrollBar:IsShown() then
        return;
    end
    self.scrollBar:SetShown(visible);
    if self.scrollBoxAnchorsWithBar then
        local anchors = visible and self.scrollBoxAnchorsWithBar or self.scrollBoxAnchorsWithoutBar;
        if self.appliedAnchors ~= anchors then
            self.appliedAnchors = anchors;
            self.scrollBox:ClearAllPoints();
            for _, anchor in ipairs(anchors) do
                anchor:SetPoint(self.scrollBox, false);
            end
        end
    end
    self:TriggerEvent(ManagedScrollBarVisibilityBehaviorMixin.Event.OnVisibilityChanged, visible);
end

function ScrollUtil.AddManagedScrollBarVisibilityBehavior(scrollBox, scrollBar, withBar, withoutBar)
    local behavior = CreateFromMixins(ManagedScrollBarVisibilityBehaviorMixin);
    behavior:Init(scrollBox, scrollBar, withBar, withoutBar);
    return behavior;
end

-- selection (ScrollUtil.AddSelectionBehavior); flags as in game
SelectionBehaviorFlags = {Deselectable = 1, Intrusive = 2, MultiSelect = 4};
SelectionBehaviorMixin = CreateFromMixins(CallbackRegistryMixin);
SelectionBehaviorMixin:GenerateCallbackEvents({"OnSelectionChanged"});

function SelectionBehaviorMixin.IsIntrusiveSelected(frame)
    local elementData = frame and frame.GetElementData and frame:GetElementData();
    return elementData ~= nil and not not elementData.selected;
end

function SelectionBehaviorMixin:Init(scrollBox, ...)
    CallbackRegistryMixin.OnLoad(self);
    self.scrollBox = scrollBox;
    self.flags = {};
    self:SetSelectionFlags(...);
    if not self.flags[SelectionBehaviorFlags.Intrusive] then
        self.selections = {};
    end
    scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnDataProviderReassigned, function()
        self.selections = {};
    end, self);
end

function SelectionBehaviorMixin:SetSelectionFlags(...)
    for i = 1, select("#", ...) do
        self.flags[select(i, ...)] = true;
    end
end

function SelectionBehaviorMixin:IsFlagSet(flag)
    return self.flags[flag] == true;
end

function SelectionBehaviorMixin:IsSelected(frame)
    return frame ~= nil and self:IsElementDataSelected(frame:GetElementData());
end

function SelectionBehaviorMixin:IsElementDataSelected(elementData)
    if elementData then
        return (self.selections and self.selections[elementData] == true) or (not not elementData.selected);
    end
    return false;
end

function SelectionBehaviorMixin:GetSelectedElementData()
    local selected = {};
    if self.scrollBox:HasDataProvider() then
        for _, elementData in self.scrollBox:EnumerateDataProviderEntireRange() do
            if self:IsElementDataSelected(elementData) then
                table.insert(selected, elementData);
            end
        end
    end
    return selected;
end

function SelectionBehaviorMixin:GetFirstSelectedElementData()
    return self:GetSelectedElementData()[1];
end

function SelectionBehaviorMixin:HasSelection()
    return #self:GetSelectedElementData() > 0;
end

function SelectionBehaviorMixin:DeselectByPredicate(predicate)
    local deselected = {};
    if self.scrollBox:HasDataProvider() then
        for _, elementData in self.scrollBox:EnumerateDataProviderEntireRange() do
            if predicate(elementData) then
                self:SetElementDataSelected_Internal(elementData, false);
                table.insert(deselected, elementData);
            end
        end
    end
    return deselected;
end

function SelectionBehaviorMixin:ClearSelections()
    local deselected = self:DeselectByPredicate(function(elementData)
        return self:IsElementDataSelected(elementData);
    end);
    for _, data in ipairs(deselected) do
        self:TriggerEvent(SelectionBehaviorMixin.Event.OnSelectionChanged, data, false);
    end
end

function SelectionBehaviorMixin:SetElementDataSelected_Internal(elementData, newSelected)
    local deselected;
    if newSelected and not self:IsFlagSet(SelectionBehaviorFlags.MultiSelect) then
        deselected = self:DeselectByPredicate(function(data)
            return data ~= elementData and self:IsElementDataSelected(data);
        end);
    end
    local changed = self:IsElementDataSelected(elementData) ~= newSelected;
    if self:IsFlagSet(SelectionBehaviorFlags.Intrusive) then
        elementData.selected = newSelected;
    else
        self.selections[elementData] = newSelected or nil;
    end
    for _, data in ipairs(deselected or {}) do
        self:TriggerEvent(SelectionBehaviorMixin.Event.OnSelectionChanged, data, false);
    end
    if changed then
        self:TriggerEvent(SelectionBehaviorMixin.Event.OnSelectionChanged, elementData, newSelected);
    end
end

function SelectionBehaviorMixin:SelectElementData(elementData)
    self:SetElementDataSelected_Internal(elementData, true);
end

function SelectionBehaviorMixin:DeselectElementData(elementData)
    self:SetElementDataSelected_Internal(elementData, false);
end

function SelectionBehaviorMixin:SelectElementDataByPredicate(predicate)
    local elementData = self.scrollBox:FindElementDataByPredicate(predicate);
    if elementData then
        self:SelectElementData(elementData);
    end
    return elementData;
end

function SelectionBehaviorMixin:ToggleSelectElementData(elementData)
    local oldSelected = self:IsElementDataSelected(elementData);
    if oldSelected and not (self:IsFlagSet(SelectionBehaviorFlags.Deselectable)
        or self:IsFlagSet(SelectionBehaviorFlags.MultiSelect)) then
        return;
    end
    self:SetElementDataSelected_Internal(elementData, not oldSelected);
    return not oldSelected;
end

function SelectionBehaviorMixin:Select(frame)
    return self:SelectElementData(frame:GetElementData());
end

function SelectionBehaviorMixin:Deselect(frame)
    return self:DeselectElementData(frame:GetElementData());
end

function SelectionBehaviorMixin:ToggleSelect(frame)
    return self:ToggleSelectElementData(frame:GetElementData());
end

function ScrollUtil.AddSelectionBehavior(scrollBox, ...)
    local behavior = CreateFromMixins(SelectionBehaviorMixin);
    behavior:Init(scrollBox, ...);
    return behavior;
end

---------------------------------------------------------------------------
-- templates
---------------------------------------------------------------------------
local function method(name)
    return function(self, ...)
        local m = self[name];
        if m then
            return m(self, ...);
        end
    end
end

H.defineTemplate("ScrollBoxBaseTemplate", "Frame", 0, 0, function(f)
    f.canInterpolateScroll = false;
    f.debugInspectionSystem = "ScrollBox";
    H.addChild(f, "Frame", {key = "DragDelegate"});
    H.addChild(f, "EventFrame", {key = "ScrollTarget", size = {1, 1}});
    local shadows = H.addChild(f, "Frame", {key = "Shadows", setAllPoints = true});
    H.addTexture(shadows, {key = "Lower"});
    H.addTexture(shadows, {key = "Upper"});
    H.setXmlScript(f, "OnLoad", method("OnLoad"));
    H.setXmlScript(f, "OnSizeChanged", method("OnSizeChanged"));
    H.setXmlScript(f, "OnMouseWheel", method("OnMouseWheel"));
end);
H.defineTemplate("WowScrollBoxList", "Frame", 0, 0, function(f)
    H.blizzTemplates.ScrollBoxBaseTemplate(f);
    Mixin(f, ScrollBoxListMixin);
end);

local function stepper(sb, key, direction, atlas, anchor)
    local b = H.addChild(sb, "EventButton", {key = key, size = {17, 11}, anchors = {{anchor}}});
    b.direction = direction;
    b.normalTexture, b.overTexture, b.downTexture = atlas, atlas .. "-over", atlas .. "-down";
    H.addTexture(b, {key = "Texture", layer = "BACKGROUND", atlas = atlas});
    return b;
end

H.defineTemplate("ScrollBarBaseTemplate", "EventFrame", 0, 0, function(f) end);
H.defineTemplate("VerticalScrollBarTemplate", "EventFrame", 0, 0, function(f)
    Mixin(f, ScrollBarMixin);
end);
H.defineTemplate("MinimalScrollBar", "EventFrame", 8, 560, function(f)
    P[f].width, P[f].height = 8, 560;
    f.thumbAnchor, f.minThumbExtent, f.smartNavigationIgnored = "TOP", 23, true;
    local track = H.addChild(f, "Frame", {key = "Track", size = {8, 0},
        anchors = {{"TOP", nil, nil, 0, -19}, {"BOTTOM", nil, nil, 0, 19}}});
    H.addTexture(track, {key = "Begin", layer = "ARTWORK", atlas = "minimal-scrollbar-track-top"});
    H.addTexture(track, {key = "End", layer = "ARTWORK", atlas = "minimal-scrollbar-track-bottom"});
    H.addTexture(track, {key = "Middle", layer = "ARTWORK", atlas = "!minimal-scrollbar-track-middle"});
    local thumb = H.addChild(track, "EventButton", {key = "Thumb", size = {8, 0}});
    H.addTexture(thumb, {key = "Begin", layer = "ARTWORK", atlas = "minimal-scrollbar-small-thumb-top"});
    H.addTexture(thumb, {key = "End", layer = "ARTWORK", atlas = "minimal-scrollbar-small-thumb-bottom"});
    H.addTexture(thumb, {key = "Middle", layer = "ARTWORK", atlas = "minimal-scrollbar-small-thumb-middle"});
    stepper(f, "Back", ScrollControllerMixin.Directions.Decrease, "minimal-scrollbar-arrow-top", "TOP");
    stepper(f, "Forward", ScrollControllerMixin.Directions.Increase, "minimal-scrollbar-arrow-bottom", "BOTTOM");
    Mixin(f, ScrollBarMixin);
    H.setXmlScript(f, "OnLoad", method("OnLoad"));
    H.setXmlScript(f, "OnMouseWheel", method("OnMouseWheel"));
end);

---------------------------------------------------------------------------
-- scenario helpers
---------------------------------------------------------------------------
-- The frames of a WowScrollBoxList in data order (each answers :GetElementData()).
function H.scrollBoxFrames(scrollBox)
    local frames = {};
    for _, frame in ipairs(scrollBox:GetFrames()) do
        frames[#frames + 1] = frame;
    end
    return frames;
end

-- The frame whose element data satisfies predicate(elementData, frame), or the frame of that exact element table.
function H.scrollBoxFrameFor(scrollBox, predicate)
    for _, frame in ipairs(scrollBox:GetFrames()) do
        local data = frame:GetElementData();
        if (type(predicate) == "function" and predicate(data, frame)) or data == predicate then
            return frame;
        end
    end
end

-- The player presses a scroll bar stepper ("Forward" scrolls down).
function H.scrollStep(scrollBar, which)
    local stepperButton = scrollBar[which or "Forward"];
    if not stepperButton then
        error("harness: scroll bar has no " .. tostring(which) .. " stepper", 2);
    end
    H.fireScript(stepperButton, "OnMouseDown", "LeftButton");
    H.fireScript(stepperButton, "OnMouseUp", "LeftButton", true);
end

-- The player turns the mouse wheel over a frame (delta < 0 scrolls down).
function H.mouseWheel(frame, delta)
    H.fireScript(frame, "OnMouseWheel", delta);
end
