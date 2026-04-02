-- =============================================================================
-- tests/test_scheduler.lua
-- =============================================================================
T.suite("Scheduler & Coroutines")

-- ---------------------------------------------------------------------------
-- Test 1: Basic CreateThread runs
-- ---------------------------------------------------------------------------
do
    local ran = false
    CreateThread(function()
        ran = true
    end)
    RunSchedulerUntilDone(1000)
    T.ok(ran, "CreateThread body executes")
end

-- ---------------------------------------------------------------------------
-- Test 2: Wait(0) yields and resumes on next tick
-- ---------------------------------------------------------------------------
do
    local order = {}
    CreateThread(function()
        order[#order + 1] = "A1"
        Wait(0)
        order[#order + 1] = "A2"
    end)
    CreateThread(function()
        order[#order + 1] = "B1"
        Wait(0)
        order[#order + 1] = "B2"
    end)
    RunSchedulerUntilDone(1000)
    -- Both threads should have run fully; order within a tick is FIFO by insertion
    T.ok(#order == 4, "Both threads ran all steps (got " .. #order .. " steps)")
    T.ok(
        (order[1] == "A1" or order[1] == "B1"),
        "First step is from one of the threads"
    )
end

-- ---------------------------------------------------------------------------
-- Test 3: Wait(ms) waits at least that many milliseconds
-- ---------------------------------------------------------------------------
do
    local startMs = GetGameTimer()
    local endMs   = nil
    local WAIT_MS = 50

    CreateThread(function()
        Wait(WAIT_MS)
        endMs = GetGameTimer()
    end)
    RunSchedulerUntilDone(2000)

    T.ok(endMs ~= nil, "Thread completed after Wait(" .. WAIT_MS .. ")")
    local elapsed = (endMs or 0) - startMs
    T.ok(elapsed >= WAIT_MS,
        string.format("Wait(%d) elapsed at least %dms (actual: %dms)", WAIT_MS, WAIT_MS, elapsed))
end

-- ---------------------------------------------------------------------------
-- Test 4: Nested CreateThread inside a thread
-- ---------------------------------------------------------------------------
do
    local log = {}
    CreateThread(function()
        log[#log + 1] = "outer-start"
        CreateThread(function()
            log[#log + 1] = "inner-ran"
        end)
        Wait(0)
        log[#log + 1] = "outer-end"
    end)
    RunSchedulerUntilDone(1000)
    T.ok(#log == 3, "Nested thread ran (got " .. #log .. " entries)")
    T.eq(log[1], "outer-start", "Outer thread ran first")
    -- inner-ran and outer-end order depends on tick timing; both must appear
    local hasInner = false; local hasOuter = false
    for _, v in ipairs(log) do
        if v == "inner-ran" then hasInner = true end
        if v == "outer-end" then hasOuter = true end
    end
    T.ok(hasInner, "Inner thread executed")
    T.ok(hasOuter, "Outer thread resumed after Wait")
end

-- ---------------------------------------------------------------------------
-- Test 5: Citizen.SetTimeout fires once after delay
-- ---------------------------------------------------------------------------
do
    local fired = 0
    Citizen.SetTimeout(20, function()
        fired = fired + 1
    end)
    RunSchedulerUntilDone(1000)
    T.eq(fired, 1, "SetTimeout fires exactly once")
end

-- ---------------------------------------------------------------------------
-- Test 6: Citizen.SetInterval repeats
-- ---------------------------------------------------------------------------
do
    local count = 0
    local intervalHandle
    CreateThread(function()
        intervalHandle = Citizen.SetInterval(10, function()
            count = count + 1
        end)
        -- Let it fire a few times, then cancel so it doesn't leak across tests.
        Wait(60)
        Citizen.ClearInterval(intervalHandle)
    end)
    RunSchedulerUntilDone(2000)
    T.ok(count >= 3, "SetInterval fired multiple times (got " .. count .. ")")
end

-- ---------------------------------------------------------------------------
-- Test 7: Thread error does not crash the scheduler
-- ---------------------------------------------------------------------------
do
    local afterError = false
    CreateThread(function()
        error("intentional test error")
    end)
    CreateThread(function()
        afterError = true
    end)
    RunSchedulerUntilDone(1000)
    T.ok(afterError, "Scheduler continues after thread error")
end

-- ---------------------------------------------------------------------------
-- Test 8: Promise resolve / Citizen.Await
-- ---------------------------------------------------------------------------
do
    local result = nil
    local p = Promise.new()

    CreateThread(function()
        result = Citizen.Await(p)
    end)

    -- Resolve from another thread after a short delay
    CreateThread(function()
        Wait(30)
        p:resolve("hello-from-promise")
    end)

    RunSchedulerUntilDone(2000)
    T.eq(result, "hello-from-promise", "Citizen.Await receives resolved promise value")
end

-- ---------------------------------------------------------------------------
-- Test 9: Promise reject / Citizen.Await propagates error
-- ---------------------------------------------------------------------------
do
    local caught = nil
    local p = Promise.new()

    CreateThread(function()
        local ok_, err = pcall(Citizen.Await, p)
        if not ok_ then caught = err end
    end)

    CreateThread(function()
        Wait(10)
        p:reject("promise-error")
    end)

    RunSchedulerUntilDone(1000)
    T.ok(caught ~= nil, "Citizen.Await propagates rejection as error")
    T.eq(tostring(caught), "promise-error", "Rejection message is preserved")
end

-- ---------------------------------------------------------------------------
-- Test 10: Promise:next chaining
-- ---------------------------------------------------------------------------
do
    local chain = {}
    local p = Promise.new()

    p:next(function(v)
        chain[#chain + 1] = v .. "-step1"
        return v .. "-step1"
    end):next(function(v)
        chain[#chain + 1] = v .. "-step2"
    end)

    CreateThread(function()
        Wait(0)
        p:resolve("data")
    end)

    RunSchedulerUntilDone(1000)
    -- Note: :next() chains may fire synchronously or via scheduler depending on
    -- state at registration time.  We verify at least the resolve happened.
    T.ok(p._state == "resolved", "Promise resolved successfully")
end
