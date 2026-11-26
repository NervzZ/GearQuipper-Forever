-- env.lua: Lua sandbox, WoW global helpers, BugGrabber-like error trap, virtual clock, C_Timer, event queue.
local H = ...;

-- Keep what the harness itself needs before the sandbox removes it (WoW has no io/os/debug/require).
local traceback, getinfo = debug.traceback, debug.getinfo;
local os_date = os.date;
H.traceback, H.getinfo = traceback, getinfo;

H.api = H.include("data/apidata.lua"); -- documented events, functions and enums of the Forever client

local function pack(...)
    return {n = select("#", ...), ...};
end
H.pack = pack;

---------------------------------------------------------------------------
-- error trap
---------------------------------------------------------------------------
H.errors = {};   -- {where, msg, trace, count, time}
H.warnings = {}; -- unique model warnings (unknown templates, unverified behaviour hit, ...)
local warned = {};

function H.warn(msg)
    if not warned[msg] then
        warned[msg] = true;
        H.warnings[#H.warnings + 1] = msg;
    end
end

local function errorHandler(e)
    return {msg = tostring(e), trace = traceback("", 2)};
end

function H.recordError(where, err)
    local msg = type(err) == "table" and err.msg or tostring(err);
    local trace = type(err) == "table" and err.trace or "";
    for _, e in ipairs(H.errors) do
        if e.msg == msg and e.where == where then
            e.count = e.count + 1;
            return;
        end
    end
    H.errors[#H.errors + 1] = {where = where, msg = msg, trace = trace, count = 1, time = H.now};
end

-- Runs fn(...) like the client runs a script handler: an error is recorded (BugGrabber) and does not propagate.
-- Returns true plus fn's results, or false.
function H.trap(where, fn, ...)
    local args = pack(...);
    local res = pack(xpcall(function()
        return fn(unpack(args, 1, args.n));
    end, errorHandler));
    if res[1] then
        return unpack(res, 1, res.n);
    end
    H.recordError(where, res[2]);
    return false;
end

---------------------------------------------------------------------------
-- undefined global reads from addon code (reported, never auto-created)
---------------------------------------------------------------------------
H.undefinedGlobals = {}; -- name -> {count, where}

local function addonSource(level)
    local info = getinfo(level, "Sl");
    if info and info.source and H.addonDir and info.source:sub(2, #H.addonDir + 1) == H.addonDir then
        return info.short_src .. ":" .. (info.currentline or 0);
    end
end

setmetatable(_G, {
    __index = function(_, key)
        local where = addonSource(3);
        if where then
            local entry = H.undefinedGlobals[key];
            if entry then
                entry.count = entry.count + 1;
            else
                H.undefinedGlobals[key] = {count = 1, where = where};
            end
        end
        return nil;
    end
});

---------------------------------------------------------------------------
-- sandbox: WoW's Lua has none of these
---------------------------------------------------------------------------
io, os, debug, require, package, dofile, loadfile, module = nil, nil, nil, nil, nil, nil, nil, nil;

---------------------------------------------------------------------------
-- WoW global helpers
---------------------------------------------------------------------------
strbyte, strchar, strfind, strlen, strlower = string.byte, string.char, string.find, string.len, string.lower;
strmatch, strrep, strrev, strsub, strupper = string.match, string.rep, string.reverse, string.sub, string.upper;
format, gmatch, gsub = string.format, string.gmatch, string.gsub;
abs, ceil, floor, max, min, sqrt, exp = math.abs, math.ceil, math.floor, math.max, math.min, math.sqrt, math.exp;
log, log10, mod, random, fastrandom = math.log, math.log10, math.fmod, math.random, math.random;
sin, cos, tan, asin, acos, atan, atan2, deg, rad = math.sin, math.cos, math.tan, math.asin, math.acos, math.atan,
    math.atan2, math.deg, math.rad;
PI = math.pi;
tinsert, tremove, sort, getn = table.insert, table.remove, table.sort, table.getn;

function strsplit(delimiter, str, pieces)
    if type(delimiter) ~= "string" or type(str) ~= "string" then
        error("Usage: strsplit(delimiter, str[, pieces])", 2);
    end
    local result, start = {}, 1;
    local pattern = "[" .. delimiter:gsub("[%]%^%-%%]", "%%%0") .. "]";
    while true do
        if pieces and #result == pieces - 1 then
            result[#result + 1] = str:sub(start);
            break;
        end
        local s, e = str:find(pattern, start);
        if not s then
            result[#result + 1] = str:sub(start);
            break;
        end
        result[#result + 1] = str:sub(start, s - 1);
        start = e + 1;
    end
    return unpack(result);
end
string.split = strsplit;

function strtrim(str, chars)
    if type(str) ~= "string" then
        error("Usage: strtrim(str[, chars])", 2);
    end
    chars = chars and ("[" .. chars:gsub("[%]%^%-%%]", "%%%0") .. "]") or "%s";
    return (str:gsub("^" .. chars .. "+", ""):gsub(chars .. "+$", ""));
end
string.trim = strtrim;

function strjoin(delimiter, ...)
    return table.concat({...}, delimiter);
end
string.join = strjoin;

function strconcat(...)
    return table.concat({...});
end

function tostringall(...)
    local t = pack(...);
    for i = 1, t.n do
        t[i] = tostring(t[i]);
    end
    return unpack(t, 1, t.n);
end

function wipe(t)
    for k in pairs(t) do
        t[k] = nil;
    end
    return t;
end
table.wipe = wipe;

function foreach(t, fn)
    for k, v in pairs(t) do
        local r = fn(k, v);
        if r ~= nil then
            return r;
        end
    end
end

function foreachi(t, fn)
    for i, v in ipairs(t) do
        local r = fn(i, v);
        if r ~= nil then
            return r;
        end
    end
end

function tContains(t, value)
    for _, v in pairs(t) do
        if v == value then
            return true;
        end
    end
    return false;
end

function tIndexOf(t, value)
    for i, v in ipairs(t) do
        if v == value then
            return i;
        end
    end
end

function tInvert(t)
    local r = {};
    for k, v in pairs(t) do
        r[v] = k;
    end
    return r;
end

function CopyTable(t, shallow)
    local r = {};
    for k, v in pairs(t) do
        r[k] = (type(v) == "table" and not shallow) and CopyTable(v) or v;
    end
    return r;
end

function Mixin(object, ...)
    for i = 1, select("#", ...) do
        local mixin = select(i, ...);
        for k, v in pairs(mixin) do
            object[k] = v;
        end
    end
    return object;
end

function CreateFromMixins(...)
    return Mixin({}, ...);
end

function CreateAndInitFromMixin(mixin, ...)
    local object = CreateFromMixins(mixin);
    object:Init(...);
    return object;
end

-- bit library (pure Lua, 32-bit)
local function tobits(n)
    n = n % 4294967296;
    return n;
end
local function bitop(a, b, op)
    local r, p = 0, 1;
    a, b = tobits(a), tobits(b);
    for _ = 1, 32 do
        local x, y = a % 2, b % 2;
        if op(x, y) then
            r = r + p;
        end
        a, b, p = (a - x) / 2, (b - y) / 2, p * 2;
    end
    return r;
end
bit = {
    band = function(a, b) return bitop(a, b, function(x, y) return x == 1 and y == 1 end) end,
    bor = function(a, b) return bitop(a, b, function(x, y) return x == 1 or y == 1 end) end,
    bxor = function(a, b) return bitop(a, b, function(x, y) return x ~= y end) end,
    bnot = function(a) return 4294967295 - tobits(a) end,
    lshift = function(a, n) return tobits(a * 2 ^ n) end,
    rshift = function(a, n) return math.floor(tobits(a) / 2 ^ n) end,
};

---------------------------------------------------------------------------
-- secure environment helpers
---------------------------------------------------------------------------
function hooksecurefunc(tableOrName, nameOrHook, hook)
    local t, name = tableOrName, nameOrHook;
    if type(tableOrName) == "string" then
        t, name, hook = _G, tableOrName, nameOrHook;
    end
    local original = rawget(t, name) or t[name];
    if type(original) ~= "function" or type(hook) ~= "function" then
        error("Usage: hooksecurefunc([table,] \"functionName\", hookfunc)", 2);
    end
    t[name] = function(...)
        local res = pack(original(...));
        H.trap("hooksecurefunc " .. tostring(name), hook, ...);
        return unpack(res, 1, res.n);
    end
end

function securecall(fn, ...)
    if type(fn) == "string" then
        fn = _G[fn];
    end
    return select(2, H.trap("securecall", fn, ...));
end
securecallfunction = securecall;

function issecure()
    return false;
end

function issecurevariable()
    return false, H.addonName;
end

local errorHandlerFn = function(msg)
    H.recordError("geterrorhandler()", {msg = tostring(msg), trace = traceback("", 2)});
end
function geterrorhandler()
    return errorHandlerFn;
end
function seterrorhandler(fn)
    errorHandlerFn = fn;
end

function debugstack(start, count1, count2)
    return traceback("", (start or 1) + 1);
end
function debugprofilestart() end
function debugprofilestop()
    return H.nowMs;
end

function GetLocale()
    return "enUS";
end

function GetBuildInfo()
    return "1.60.1", "71139", "Nov 1 2025", 16001, "", "", 16001;
end

-- Enum, exactly as documented for the Forever client
Enum = {};
for name, fields in pairs(H.api.enums) do
    Enum[name] = fields;
end

---------------------------------------------------------------------------
-- chat capture
---------------------------------------------------------------------------
H.chat = {}; -- every line printed to the chat frame (print, DEFAULT_CHAT_FRAME:AddMessage)

function H.addChat(text)
    H.chat[#H.chat + 1] = tostring(text);
    if H.echoChat then
        H.pyprint("    [chat] " .. H.stripColors(tostring(text)));
    end
end

function H.stripColors(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"));
end

function print(...)
    local parts = pack(...);
    for i = 1, parts.n do
        parts[i] = tostring(parts[i]);
    end
    H.addChat(table.concat(parts, " ", 1, parts.n));
end

---------------------------------------------------------------------------
-- virtual clock and C_Timer
---------------------------------------------------------------------------
H.nowMs = 0;         -- milliseconds since login
H.now = 0;           -- seconds since login
H.frameMs = 50;      -- one simulated frame
local TIME_BASE = 1764140000; -- time() at login (Nov 2025)
local GETTIME_BASE = 5000.0;  -- GetTime() at login (seconds of client uptime)

function GetTime()
    return GETTIME_BASE + H.nowMs / 1000;
end
GetTimePreciseSec = GetTime;

function time(t)
    if t then
        return TIME_BASE;
    end
    return TIME_BASE + math.floor(H.nowMs / 1000);
end

function date(fmt, t)
    return os_date(fmt, t or time());
end

local timers, timerSeq = {}, 0;

local function timerWhere()
    local info = getinfo(4, "Sl");
    return info and (info.short_src .. ":" .. (info.currentline or 0)) or "?";
end

local TimerHandle = {};
TimerHandle.__index = TimerHandle;
function TimerHandle:Cancel()
    self.cancelled = true;
end
function TimerHandle:IsCancelled()
    return self.cancelled == true;
end

local function addTimer(api, seconds, fn, handle, iterations)
    if type(seconds) ~= "number" or type(fn) ~= "function" then
        error("Usage: C_Timer." .. api .. "(seconds, callback)", 3);
    end
    timerSeq = timerSeq + 1;
    local t = handle or setmetatable({}, TimerHandle);
    t.dueMs = H.nowMs + math.max(0, math.floor(seconds * 1000 + 0.5));
    t.seq, t.fn, t.interval, t.iterations = timerSeq, fn, seconds, iterations;
    t.where = t.where or ("C_Timer." .. api .. " from " .. timerWhere());
    timers[#timers + 1] = t;
    return t;
end

C_Timer = {
    After = function(seconds, fn)
        addTimer("After", seconds, fn);
    end,
    NewTimer = function(seconds, fn)
        local t = addTimer("NewTimer", seconds, fn);
        t.passHandle = true;
        return t;
    end,
    NewTicker = function(seconds, fn, iterations)
        local t = addTimer("NewTicker", seconds, fn, nil, iterations);
        t.passHandle, t.ticker = true, true;
        return t;
    end,
};

function H.pendingTimers()
    return #timers;
end

local function runDueTimers()
    local due = {};
    for i = #timers, 1, -1 do
        if timers[i].dueMs <= H.nowMs then
            due[#due + 1] = table.remove(timers, i);
        end
    end
    table.sort(due, function(a, b)
        if a.dueMs ~= b.dueMs then
            return a.dueMs < b.dueMs;
        end
        return a.seq < b.seq;
    end);
    for _, t in ipairs(due) do
        if not t.cancelled then
            if t.passHandle then
                H.trap(t.where, t.fn, t);
            else
                H.trap(t.where, t.fn);
            end
            if t.ticker and not t.cancelled then
                if t.iterations then
                    t.iterations = t.iterations - 1;
                end
                if not t.iterations or t.iterations > 0 then
                    addTimer("NewTicker", t.interval, t.fn, t, t.iterations);
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- events: the client queues most events and dispatches them on the next frame
---------------------------------------------------------------------------
H.eventLog = {};  -- {t, event, args}
H.extraEvents = {}; -- events that exist but are missing from the documentation
H.frameNo = 0;
local queue = {};   -- {due = frame number, args = packed event + payload}

local function checkEvent(event)
    if not (H.api.events[event] or H.extraEvents[event]) then
        error("harness: unknown event " .. tostring(event), 3);
    end
end

-- Dispatches an event right now (to frames, in registration order). Used for events the scenario raises
-- at a frame boundary and for the few events the client fires synchronously (ADDON_ACTION_BLOCKED).
function H.fire(event, ...)
    checkEvent(event);
    H.eventLog[#H.eventLog + 1] = {t = H.now, event = event, args = pack(...)};
    H.dispatch(event, ...);
end

-- Unit events: same as H.fire, the unit is the first payload value.
function H.fireUnit(event, unit, ...)
    H.fire(event, unit, ...);
end

-- Queued events are dispatched at the start of the next frame (H.advance).
function H.queueEvent(event, ...)
    checkEvent(event);
    queue[#queue + 1] = {due = H.frameNo + 1, args = pack(event, ...)};
end

-- Dispatched one frame later than regular queued events, once per frame (BAG_UPDATE_DELAYED).
function H.queueNextFrame(event, ...)
    checkEvent(event);
    for _, e in ipairs(queue) do
        if e.args[1] == event and e.due == H.frameNo + 2 then
            return;
        end
    end
    queue[#queue + 1] = {due = H.frameNo + 2, args = pack(event, ...)};
end

function H.flushEvents()
    local i, guard = 1, 0;
    while i <= #queue do
        local e = queue[i];
        if e.due <= H.frameNo then
            table.remove(queue, i);
            H.fire(unpack(e.args, 1, e.args.n));
            guard = guard + 1;
            if guard > 10000 then
                error("harness: event storm (more than 10000 queued events in one frame)");
            end
        else
            i = i + 1;
        end
    end
end

function H.pendingEvents()
    return #queue;
end

---------------------------------------------------------------------------
-- frames and time
---------------------------------------------------------------------------
H.frameHooks = {}; -- functions(dtMs) run every frame (server ops, OnUpdate)

-- One client frame: events queued in earlier frames, then time passes, server replies, OnUpdate, due timers.
-- Events those produce are dispatched on the next frame.
function H.step(dtMs)
    H.frameNo = H.frameNo + 1;
    H.flushEvents();
    H.nowMs = H.nowMs + dtMs;
    H.now = H.nowMs / 1000;
    for _, hook in ipairs(H.frameHooks) do
        hook(dtMs);
    end
    runDueTimers();
end

-- Advances the virtual clock frame by frame (H.frameMs each). H.advance(0) runs one frame without time passing.
function H.advance(seconds)
    local targetMs = H.nowMs + math.floor((seconds or 0) * 1000 + 0.5);
    repeat
        H.step(math.min(H.frameMs, targetMs - H.nowMs));
    until H.nowMs >= targetMs;
end
