-- =============================================================================
-- tests/test_events.lua
-- =============================================================================
T.suite("Event System")

-- ---------------------------------------------------------------------------
-- Test 1: Basic AddEventHandler + TriggerEvent roundtrip
-- ---------------------------------------------------------------------------
do
    local received = nil
    local handle = AddEventHandler("test:basic", function(val)
        received = val
    end)
    TriggerEvent("test:basic", "hello")
    T.eq(received, "hello", "TriggerEvent delivers value to handler")
    RemoveEventHandler(handle)
end

-- ---------------------------------------------------------------------------
-- Test 2: Multiple arguments
-- ---------------------------------------------------------------------------
do
    local a_, b_, c_ = nil, nil, nil
    local handle = AddEventHandler("test:multiarg", function(a, b, c)
        a_, b_, c_ = a, b, c
    end)
    TriggerEvent("test:multiarg", 1, "two", true)
    T.eq(a_, 1,     "First arg delivered")
    T.eq(b_, "two", "Second arg delivered")
    T.eq(c_, true,  "Third arg delivered")
    RemoveEventHandler(handle)
end

-- ---------------------------------------------------------------------------
-- Test 3: Multiple handlers on the same event
-- ---------------------------------------------------------------------------
do
    local count = 0
    local h1 = AddEventHandler("test:multi-handler", function() count = count + 1 end)
    local h2 = AddEventHandler("test:multi-handler", function() count = count + 1 end)
    local h3 = AddEventHandler("test:multi-handler", function() count = count + 1 end)
    TriggerEvent("test:multi-handler")
    T.eq(count, 3, "All three handlers invoked")
    RemoveEventHandler(h1)
    RemoveEventHandler(h2)
    RemoveEventHandler(h3)
end

-- ---------------------------------------------------------------------------
-- Test 4: RemoveEventHandler stops delivery
-- ---------------------------------------------------------------------------
do
    local fired = 0
    local handle = AddEventHandler("test:remove", function()
        fired = fired + 1
    end)
    TriggerEvent("test:remove")
    RemoveEventHandler(handle)
    TriggerEvent("test:remove")
    T.eq(fired, 1, "Handler not called after RemoveEventHandler")
end

-- ---------------------------------------------------------------------------
-- Test 5: Handler can remove itself during dispatch
-- ---------------------------------------------------------------------------
do
    local fired = 0
    local handle
    handle = AddEventHandler("test:self-remove", function()
        fired = fired + 1
        RemoveEventHandler(handle)  -- remove during dispatch
    end)
    TriggerEvent("test:self-remove")
    TriggerEvent("test:self-remove")   -- should not fire again
    T.eq(fired, 1, "Self-removing handler fires exactly once")
end

-- ---------------------------------------------------------------------------
-- Test 6: source global is set during handler dispatch
-- ---------------------------------------------------------------------------
do
    local sourceInHandler = "not-set"
    local handle = AddEventHandler("test:source", function()
        sourceInHandler = tostring(source)
    end)
    -- __cfx_internal_triggerEvent lets us set the source
    __cfx_internal_triggerEvent("test:source", 42)
    T.eq(sourceInHandler, "42", "source global is set to triggering source")
    RemoveEventHandler(handle)
end

-- ---------------------------------------------------------------------------
-- Test 7: source is restored after handler returns
-- ---------------------------------------------------------------------------
do
    _G.source = "before"
    local handle = AddEventHandler("test:source-restore", function()
        -- noop
    end)
    __cfx_internal_triggerEvent("test:source-restore", 99)
    T.eq(tostring(source), "before", "source is restored after handler dispatch")
    _G.source = ""  -- reset
    RemoveEventHandler(handle)
end

-- ---------------------------------------------------------------------------
-- Test 8: TriggerEvent with no handlers is safe (no error)
-- ---------------------------------------------------------------------------
do
    local ok_ = pcall(TriggerEvent, "test:no-handlers", "data")
    T.ok(ok_, "TriggerEvent with no handlers does not error")
end

-- ---------------------------------------------------------------------------
-- Test 9: Handler error is caught; other handlers still run
-- ---------------------------------------------------------------------------
do
    local secondRan = false
    local h1 = AddEventHandler("test:handler-error", function()
        error("intentional")
    end)
    local h2 = AddEventHandler("test:handler-error", function()
        secondRan = true
    end)
    TriggerEvent("test:handler-error")
    T.ok(secondRan, "Second handler runs even when first throws")
    RemoveEventHandler(h1)
    RemoveEventHandler(h2)
end

-- ---------------------------------------------------------------------------
-- Test 10: TriggerNetEvent / TriggerServerEvent fire locally (stub behaviour)
-- ---------------------------------------------------------------------------
do
    local netReceived  = false
    local srvReceived  = false
    RegisterNetEvent("test:net")
    RegisterNetEvent("test:server")
    local h1 = AddEventHandler("test:net",    function() netReceived = true end)
    local h2 = AddEventHandler("test:server", function() srvReceived = true end)

    TriggerNetEvent("test:net")
    TriggerServerEvent("test:server")

    T.ok(netReceived,  "TriggerNetEvent fires locally in standalone")
    T.ok(srvReceived,  "TriggerServerEvent fires locally in standalone")
    RemoveEventHandler(h1)
    RemoveEventHandler(h2)
end

-- ---------------------------------------------------------------------------
-- Test 11: Invalid handle raises error
-- ---------------------------------------------------------------------------
do
    T.throws(
        function() RemoveEventHandler({}) end,
        "RemoveEventHandler with invalid handle raises error"
    )
end

-- ---------------------------------------------------------------------------
-- Test 12: AddEventHandler validates argument types
-- ---------------------------------------------------------------------------
do
    T.throws(
        function() AddEventHandler(123, function() end) end,
        "AddEventHandler rejects non-string name"
    )
    T.throws(
        function() AddEventHandler("x", "not-a-function") end,
        "AddEventHandler rejects non-function callback"
    )
end

-- ---------------------------------------------------------------------------
-- Test 13: __cfx_debugHandlers returns info string
-- ---------------------------------------------------------------------------
do
    local h = AddEventHandler("test:debug", function() end)
    local info = __cfx_debugHandlers()
    T.ok(type(info) == "string", "debugHandlers returns a string")
    T.ok(info:find("test:debug"), "debugHandlers mentions registered event")
    RemoveEventHandler(h)
end

-- ---------------------------------------------------------------------------
-- Test 14: Events fired from inside CreateThread
-- ---------------------------------------------------------------------------
do
    local asyncReceived = false
    local handle = AddEventHandler("test:async-event", function()
        asyncReceived = true
    end)
    CreateThread(function()
        Wait(0)
        TriggerEvent("test:async-event")
    end)
    RunSchedulerUntilDone(1000)
    T.ok(asyncReceived, "TriggerEvent from inside CreateThread works")
    RemoveEventHandler(handle)
end
