-- =============================================================================
-- citizen.lua  —  CfxLua Standalone Runtime
-- =============================================================================
-- SHIM: FXServer exposes the Citizen table via LuaScriptRuntime.cpp's
-- lua_cfx_* C functions, each registered via lua_register(). Here we build
-- an equivalent Lua-native table. Scheduler functions (Wait, CreateThread,
-- SetTimeout, Await) are populated by scheduler.lua which must be loaded
-- first; this file augments Citizen with the remaining surface area.
-- =============================================================================

Citizen = Citizen or {}

-- ---------------------------------------------------------------------------
-- Resource identity
-- SHIM: FXServer sets GetCurrentResourceName from the resource manifest and
-- GetInvokingResource from the call stack of native invocations.
-- We derive them from arg[0] (script path stripped to basename).
-- ---------------------------------------------------------------------------
local function _basename(path)
    return (path or ""):match("[^/\\]+$") or "standalone"
end

-- SHIM: arg[0] in the standalone runner is the bootstrap.lua path, but we
-- re-set CFXLUA_RESOURCE_NAME in bootstrap.lua after parsing argv, so we
-- check that env var first for a cleaner resource name.
local _resourceName = os.getenv("CFXLUA_RESOURCE_NAME")
    or _basename(arg and arg[0] or "standalone")

function GetCurrentResourceName()
    return _resourceName
end

-- SHIM: GetInvokingResource() in FXServer returns the resource that triggered
-- the currently-executing event handler. Without a real call-stack tracker we
-- return nil, which is what non-event contexts return anyway.
function GetInvokingResource()
    return nil
end

-- ---------------------------------------------------------------------------
-- Citizen.InvokeNative / Citizen.InvokeNativeByHash
-- SHIM: Real FXServer routes these through NativeHandler → game engine or
-- scripting runtime. We log and return nil so resources that gate on the
-- return value work correctly.
-- ---------------------------------------------------------------------------
function Citizen.InvokeNative(hash, ...)
    -- hash can be a string (0xABCD...) or integer
    print(string.format(
        "[cfxlua][STUB] InvokeNative(0x%s) — not implemented in standalone",
        type(hash) == "number" and string.format("%X", hash) or tostring(hash)
    ))
    return nil
end

Citizen.InvokeNativeByHash = Citizen.InvokeNative

-- ---------------------------------------------------------------------------
-- Citizen.Trace / print shims
-- SHIM: Citizen.Trace writes to the FXServer structured log. We forward to
-- print with an optional prefix.
-- ---------------------------------------------------------------------------
function Citizen.Trace(msg)
    io.write(tostring(msg))
    io.flush()
end

-- SHIM: FXServer's print is overridden to write to the resource log stream.
-- We leave the standard print in place and alias it.
Citizen.Log = print

-- ---------------------------------------------------------------------------
-- Citizen.GetTickCount
-- SHIM: Returns milliseconds since resource start. Identical to GetGameTimer.
-- ---------------------------------------------------------------------------
function Citizen.GetTickCount()
    return GetGameTimer()
end

-- ---------------------------------------------------------------------------
-- Citizen.SubmitBoundaryStart / SubmitBoundaryEnd
-- SHIM: FXServer uses these for structured profiling. No-op here.
-- ---------------------------------------------------------------------------
function Citizen.SubmitBoundaryStart(a, b) end
function Citizen.SubmitBoundaryEnd(a, b)   end

-- ---------------------------------------------------------------------------
-- Citizen.RegisterResourceAsEventHandler / TriggerEventInternal
-- SHIM: Used internally by AddEventHandler to register interest on the C++
-- side. Stubbed to no-ops so scripts that call them directly don't error.
-- ---------------------------------------------------------------------------
function Citizen.RegisterResourceAsEventHandler(name) end
function Citizen.TriggerEventInternal(name, data, len)
    -- SHIM: In FXServer this calls the C native to deserialise msgpack and
    -- dispatch the event. We parse data as a raw string and call TriggerEvent.
    -- In practice standalone scripts won't hit this path.
end

-- ---------------------------------------------------------------------------
-- exports proxy
-- SHIM: FXServer's exports table is a C userdata with __index that performs
-- a cross-resource native call. Here we use a two-level Lua proxy table.
-- Writing: exports["myResource"] = { myFunc = fn }
-- Reading: exports["myResource"].myFunc(...)
--
-- Resources that want to expose exports call:
--   exports("myResource", { fn1 = ..., fn2 = ... })
-- OR assign to exports directly.
-- ---------------------------------------------------------------------------
local _exportRegistry = {}   -- { [resourceName] = { [fnName] = fn } }

exports = setmetatable({}, {
    __index = function(_, resourceName)
        -- Return a proxy that resolves function names on access
        local reg = _exportRegistry[resourceName]
        if not reg then
            -- Return an empty proxy rather than erroring — FXServer behaviour
            -- when a resource isn't started yet.
            return setmetatable({}, {
                __index = function(_, fnName)
                    print(string.format(
                        "[cfxlua][STUB] exports['%s']['%s'] — resource not loaded",
                        resourceName, fnName
                    ))
                    return function() return nil end
                end,
                __newindex = function(_, fnName, fn)
                    if not _exportRegistry[resourceName] then
                        _exportRegistry[resourceName] = {}
                    end
                    _exportRegistry[resourceName][fnName] = fn
                end
            })
        end
        return setmetatable({}, {
            __index = function(_, fnName)
                local fn = reg[fnName]
                if not fn then
                    error(string.format(
                        "export '%s' does not exist on resource '%s'",
                        fnName, resourceName
                    ), 2)
                end
                return fn
            end
        })
    end,

    -- exports["resourceName"] = { fn = ... }   (registration shorthand)
    __newindex = function(_, resourceName, tbl)
        if type(tbl) ~= "table" then
            error("exports: value must be a table of functions", 2)
        end
        _exportRegistry[resourceName] = tbl
    end,

    -- exports(resourceName, tbl)   (callable registration)
    __call = function(_, resourceName, tbl)
        if type(tbl) ~= "table" then
            error("exports(): second argument must be a table of functions", 2)
        end
        _exportRegistry[resourceName] = tbl
    end
})

-- Helper for tests / introspection
function __cfx_getExportRegistry()
    return _exportRegistry
end

-- ---------------------------------------------------------------------------
-- StateBags
-- SHIM: FXServer's statebags are networked key/value stores backed by the
-- state-bag replication system (C++). Each entity (player, vehicle, global)
-- has its own bag. Here we use nested Lua tables with __index/__newindex
-- metamethods. Changes are NOT replicated (single-process).
--
-- API surface:
--   GlobalState.key = value          — write global state
--   GlobalState.key                  — read global state
--   Player(id).state.key = value     — write player state
--   Entity(ent).state.key = value    — write entity state
-- ---------------------------------------------------------------------------
local _bagStore = {}  -- { [bagId] = { [key] = value } }

local function _makeBag(bagId)
    if not _bagStore[bagId] then _bagStore[bagId] = {} end
    return setmetatable({}, {
        __index = function(_, key)
            return _bagStore[bagId][key]
        end,
        __newindex = function(_, key, value)
            -- SHIM: Real FXServer serialises to msgpack and broadcasts to
            -- all subscribed clients/server. Here we write to local table.
            _bagStore[bagId][key] = value
        end,
        __tostring = function(_)
            return string.format("StateBag(%s)", bagId)
        end
    })
end

-- Global state bag (accessible as GlobalState.x)
GlobalState = _makeBag("__global__")

-- Player state: Player(netId).state
-- SHIM: FXServer's Player() returns a playerHandle userdata.
-- We return a table with a .state field.
local _playerHandles = {}
function Player(netId)
    if not _playerHandles[netId] then
        _playerHandles[netId] = {
            state = _makeBag("player:" .. tostring(netId))
        }
    end
    return _playerHandles[netId]
end

-- Entity state: Entity(entityId).state
local _entityHandles = {}
function Entity(entityId)
    if not _entityHandles[entityId] then
        _entityHandles[entityId] = {
            state = _makeBag("entity:" .. tostring(entityId))
        }
    end
    return _entityHandles[entityId]
end

-- ---------------------------------------------------------------------------
-- KVP (Key-Value Persistence)
-- SHIM: FXServer stores KVP in a SQLite database per-resource (kvs.db).
-- Here we use an in-memory table. Data does NOT persist across runs.
-- ---------------------------------------------------------------------------
local _kvp = {}

function GetResourceKvpString(key)
    local v = _kvp[key]
    return (type(v) == "string") and v or nil
end

function GetResourceKvpInt(key)
    local v = _kvp[key]
    return (type(v) == "number") and math.floor(v) or nil
end

function GetResourceKvpFloat(key)
    local v = _kvp[key]
    return (type(v) == "number") and v or nil
end

function SetResourceKvp(key, value)
    assert(type(key) == "string", "SetResourceKvp: key must be string")
    _kvp[key] = value
end

SetResourceKvpInt   = SetResourceKvp
SetResourceKvpFloat = SetResourceKvp

function DeleteResourceKvp(key)
    _kvp[key] = nil
end

-- KVP enumerator (returns an iterator)
function StartFindKvp(prefix)
    local keys = {}
    for k in pairs(_kvp) do
        if k:sub(1, #prefix) == prefix then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys)
    local i = 0
    return function()
        i = i + 1
        return keys[i]
    end
end

-- ---------------------------------------------------------------------------
-- Convar access
-- SHIM: FXServer convars are server config variables (server.cfg).
-- We read from environment variables as a reasonable standalone equivalent.
-- ---------------------------------------------------------------------------
function GetConvar(name, default)
    return os.getenv(name) or default
end

function GetConvarInt(name, default)
    local v = os.getenv(name)
    return v and tonumber(v) or default
end

-- SetConvar is server-only; stub for compatibility
function SetConvar(name, value)
    -- SHIM: In FXServer this broadcasts to clients. No-op here.
end

-- ---------------------------------------------------------------------------
-- PerformHttpRequest
-- SHIM: FXServer routes this through libcurl. Here we emit a warning and call
-- the callback with an error so callers can handle it gracefully.
-- ---------------------------------------------------------------------------
function PerformHttpRequest(url, callback, method, data, headers)
    method  = method  or "GET"
    headers = headers or {}
    print(string.format(
        "[cfxlua][STUB] PerformHttpRequest('%s %s') — no HTTP in standalone",
        method, url
    ))
    -- Schedule callback asynchronously to match real async behaviour
    Citizen.SetTimeout(0, function()
        callback(0, nil, {}, "standalone: HTTP not available")
    end)
end

-- ---------------------------------------------------------------------------
-- print override
-- SHIM: FXServer prepends the resource name to all print() output.
-- We do the same for consistency.
-- ---------------------------------------------------------------------------
local _rawPrint = print
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end
    _rawPrint(string.format("[%s] %s", GetCurrentResourceName(), table.concat(parts, "\t")))
end

-- Restore raw print access if needed
rawprint = _rawPrint
