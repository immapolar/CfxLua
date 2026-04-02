-- =============================================================================
-- examples/hello.lua  —  Minimal CfxLua resource example
-- Run: cfxlua examples/hello.lua
-- =============================================================================

print("Resource started:", GetCurrentResourceName())

-- Basic thread
CreateThread(function()
    print("Thread 1: waiting 100ms...")
    Wait(100)
    print("Thread 1: done.")
end)

-- Concurrent thread
CreateThread(function()
    print("Thread 2: started simultaneously")
    Wait(50)
    print("Thread 2: finished at 50ms")
end)

-- Event roundtrip
AddEventHandler("hello:ping", function(msg)
    print("Received ping:", msg, "from source:", tostring(source))
    TriggerEvent("hello:pong", "pong back to " .. tostring(msg))
end)

AddEventHandler("hello:pong", function(reply)
    print("Received pong:", reply)
end)

CreateThread(function()
    Wait(10)
    TriggerEvent("hello:ping", "world")
end)

-- GlobalState usage
GlobalState.serverReady = false
Citizen.SetTimeout(200, function()
    GlobalState.serverReady = true
    print("GlobalState.serverReady =", GlobalState.serverReady)
end)

-- Promise example
local function asyncAdd(a, b)
    local p = Promise.new()
    Citizen.SetTimeout(30, function()
        p:resolve(a + b)
    end)
    return p
end

CreateThread(function()
    local result = Citizen.Await(asyncAdd(10, 32))
    print("Async addition result:", result)
end)

-- JSON example
local data = { resource = GetCurrentResourceName(), timestamp = GetGameTimer() }
print("JSON:", json.encode(data))
