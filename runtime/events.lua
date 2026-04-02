-- =============================================================================
-- events.lua  —  CfxLua Standalone Runtime
-- =============================================================================
-- SHIM: In FXServer the event system is split between Lua and C++:
--   - AddEventHandler / TriggerEvent are thin wrappers around
--     msgpack-serialised calls into citizen-scripting-core.
--   - Net events (TriggerNetEvent / TriggerServerEvent) cross the
--     network boundary via ENet packets, serialised with msgpack.
--   - Event source (__cfx_gen_eventId) and player source (__cfx_gen_source)
--     are injected by the C runtime per-invocation.
-- Here everything stays in-process; net events fire locally with a stub
-- source so resources that inspect `source` don't crash.
-- =============================================================================

local _handlers = {}   -- { [eventName] = { [handle_id] = fn } }
local _nextId   = 1

-- ---------------------------------------------------------------------------
-- Internal: fire all handlers registered for `name`
-- Returns the number of handlers invoked.
-- ---------------------------------------------------------------------------
local function _fireEvent(name, src, ...)
    local bucket = _handlers[name]
    if not bucket then return 0 end

    -- SHIM: FXServer sets the global `source` to the invoking player's net-id
    -- for net events. We expose it as a global for compatibility.
    local prevSource = _G.source
    _G.source = src

    local count = 0
    -- Snapshot keys to allow handlers to RemoveEventHandler themselves
    local keys = {}
    for id in pairs(bucket) do keys[#keys + 1] = id end

    for _, id in ipairs(keys) do
        local fn = bucket[id]
        if fn then
            count = count + 1
            local ok, err = xpcall(fn, debug.traceback, ...)
            if not ok then
                print(string.format(
                    "[cfxlua] event handler error in '%s': %s",
                    name, tostring(err)
                ))
            end
        end
    end

    _G.source = prevSource
    return count
end

-- ---------------------------------------------------------------------------
-- Public: AddEventHandler(name, fn) → handle
-- SHIM: FXServer returns an opaque userdata handle. We return a table.
-- The table is the canonical handle — store it to call RemoveEventHandler.
-- ---------------------------------------------------------------------------
function AddEventHandler(name, fn)
    assert(type(name) == "string", "AddEventHandler: name must be a string")
    assert(type(fn)   == "function", "AddEventHandler: callback must be a function")

    if not _handlers[name] then _handlers[name] = {} end

    local id = _nextId
    _nextId = _nextId + 1
    _handlers[name][id] = fn

    -- Return a handle table (mimics FXServer opaque handle)
    return { __cfx_event = true, name = name, id = id }
end

-- ---------------------------------------------------------------------------
-- Public: RemoveEventHandler(handle)
-- SHIM: FXServer's handle is a userdata with a C-side __gc that unregisters.
-- Here we just nil out the slot.
-- ---------------------------------------------------------------------------
function RemoveEventHandler(handle)
    if type(handle) ~= "table" or not handle.__cfx_event then
        error("RemoveEventHandler: invalid handle", 2)
    end
    local bucket = _handlers[handle.name]
    if bucket then
        bucket[handle.id] = nil
        -- Clean up empty buckets to avoid memory growth
        if next(bucket) == nil then
            _handlers[handle.name] = nil
        end
    end
end

-- ---------------------------------------------------------------------------
-- Public: TriggerEvent(name, ...)
-- Fires a local (same-resource) event.
-- SHIM: In FXServer this can also reach other resources on the same server
-- if they have registered handlers for the same name; event routing is done
-- by citizen-scripting-core. Here all handlers in-process receive it.
-- ---------------------------------------------------------------------------
function TriggerEvent(name, ...)
    assert(type(name) == "string", "TriggerEvent: name must be a string")
    -- SHIM: local events have source = "" (empty string) in FXServer.
    _fireEvent(name, "", ...)
end

-- ---------------------------------------------------------------------------
-- Public: TriggerNetEvent(name, ...)
-- Server→client broadcast. In FXServer this crosses the network.
-- SHIM: We fire it locally with source = -1 (server source convention).
-- The optional first extra argument can be a target player id; we ignore it
-- for stub purposes but accept the arity.
-- ---------------------------------------------------------------------------
function TriggerNetEvent(name, ...)
    assert(type(name) == "string", "TriggerNetEvent: name must be a string")
    -- SHIM: Real FXServer serialises args via msgpack and queues them for
    -- the ENet send thread. Here we fire locally for single-resource testing.
    print(string.format(
        "[cfxlua][STUB] TriggerNetEvent('%s') — no network; firing locally", name
    ))
    _fireEvent(name, -1, ...)
end

-- ---------------------------------------------------------------------------
-- Public: TriggerServerEvent(name, ...)
-- Client→server. In FXServer the client sends an ENet packet; the server
-- resource's AddEventHandler for that name receives it with `source` set to
-- the player's net-id.
-- SHIM: We fire locally with source = 1 (stub player 1).
-- ---------------------------------------------------------------------------
function TriggerServerEvent(name, ...)
    assert(type(name) == "string", "TriggerServerEvent: name must be a string")
    print(string.format(
        "[cfxlua][STUB] TriggerServerEvent('%s') — no network; firing locally", name
    ))
    _fireEvent(name, 1, ...)
end

-- ---------------------------------------------------------------------------
-- Public: TriggerLatentNetEvent(name, bps, ...) / TriggerLatentServerEvent
-- SHIM: Latent events in FXServer use a bandwidth-throttled send queue.
-- We simply forward to the normal stubs.
-- ---------------------------------------------------------------------------
function TriggerLatentNetEvent(name, bps, ...)
    TriggerNetEvent(name, ...)
end

function TriggerLatentServerEvent(name, bps, ...)
    TriggerServerEvent(name, ...)
end

-- ---------------------------------------------------------------------------
-- Internal helper: allow bootstrap.lua to emit synthetic events
-- (e.g. onResourceStart, onServerResourceStart)
-- ---------------------------------------------------------------------------
function __cfx_internal_triggerEvent(name, src, ...)
    _fireEvent(name, src, ...)
end

-- ---------------------------------------------------------------------------
-- Debug helper: list all registered handlers (useful in tests)
-- ---------------------------------------------------------------------------
function __cfx_debugHandlers()
    local out = {}
    for name, bucket in pairs(_handlers) do
        local count = 0
        for _ in pairs(bucket) do count = count + 1 end
        out[#out + 1] = string.format("  '%s': %d handler(s)", name, count)
    end
    if #out == 0 then return "(no handlers registered)" end
    return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- Initialise global `source` to empty string (server-side default)
-- SHIM: FXServer sets source per-event-dispatch. We pre-set it so resources
-- that read source unconditionally don't error on startup.
-- ---------------------------------------------------------------------------
_G.source = ""
