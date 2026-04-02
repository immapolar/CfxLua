-- =============================================================================
-- scheduler.lua  —  CfxLua Standalone Runtime
-- =============================================================================
-- SHIM: In FXServer this file lives at
--   data/shared/citizen/scripting/lua/scheduler.lua
-- and is loaded by LuaScriptRuntime.cpp via lua_dofile().
-- The C runtime calls ScheduleResourceTick() on every game frame (~60 Hz).
-- Here we drive it from bootstrap.lua's main loop with os.clock()-based timing.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- GetGameTimer shim (defined here so scheduler.lua is self-contained)
-- SHIM: Real FXServer maps GetGameTimer to a C native returning the game
-- engine's internal millisecond clock. We use process-elapsed wall time.
-- os.clock() is POSIX CPU time (adequate for single-threaded test workloads).
-- ---------------------------------------------------------------------------
if not GetGameTimer then
    local _t0 = os.clock()
    GetGameTimer = function()
        return math.floor((os.clock() - _t0) * 1000)
    end
end

-- ---------------------------------------------------------------------------
-- Internal state
-- ---------------------------------------------------------------------------

-- Min-heap of { wakeTime, co, isThreadPool } entries.
-- We use a simple sorted-insert; for realistic resource sizes (< ~200 threads)
-- this is more than fast enough.
local _threads = {}        -- { { wakeTime=n, co=coroutine } , ... }
local _current  = nil      -- coroutine currently executing (for Wait())
local _frame    = 0        -- monotonic frame counter
local _awaitYield = {}     -- sentinel: coroutine yielded by Citizen.Await

-- ---------------------------------------------------------------------------
-- Min-heap helpers (by wakeTime)
-- ---------------------------------------------------------------------------
local function _heapPush(t, entry)
    t[#t + 1] = entry
    -- bubble up
    local i = #t
    while i > 1 do
        local parent = math.floor(i / 2)
        if t[parent].wakeTime > t[i].wakeTime then
            t[parent], t[i] = t[i], t[parent]
            i = parent
        else
            break
        end
    end
end

local function _heapPop(t)
    if #t == 0 then return nil end
    local top = t[1]
    local last = table.remove(t)
    if #t > 0 then
        t[1] = last
        -- sift down
        local i = 1
        local n = #t
        while true do
            local l, r = 2 * i, 2 * i + 1
            local smallest = i
            if l <= n and t[l].wakeTime < t[smallest].wakeTime then smallest = l end
            if r <= n and t[r].wakeTime < t[smallest].wakeTime then smallest = r end
            if smallest == i then break end
            t[i], t[smallest] = t[smallest], t[i]
            i = smallest
        end
    end
    return top
end

local function _heapPeek(t)
    return t[1]
end

-- ---------------------------------------------------------------------------
-- Public: CreateThread
-- SHIM: Real FXServer calls into C via msgpack-wrapped native invocations.
-- Here we create a native Lua coroutine and push it onto the heap immediately.
-- ---------------------------------------------------------------------------
function CreateThread(fn)
    local co = coroutine.create(function()
        local ok, err = xpcall(fn, debug.traceback)
        if not ok then
            print("[cfxlua] thread error: " .. tostring(err))
        end
    end)
    _heapPush(_threads, { wakeTime = GetGameTimer(), co = co })
    return co
end

-- Alias used by some resources
Citizen = Citizen or {}
Citizen.CreateThread = CreateThread

-- ---------------------------------------------------------------------------
-- Public: Wait(ms)
-- Must be called from inside a CreateThread body.
-- SHIM: Real FXServer suspends the Lua coroutine and wakes it via the C
-- tick scheduler.  Here we yield back to ScheduleResourceTick().
-- ---------------------------------------------------------------------------
function Wait(ms)
    assert(_current, "Wait() called outside of a CreateThread context")
    local wakeAt = GetGameTimer() + (ms or 0)
    coroutine.yield(wakeAt)
end

Citizen.Wait = Wait

-- ---------------------------------------------------------------------------
-- Public: Citizen.SetTimeout(ms, fn)
-- SHIM: FXServer uses the same coroutine scheduler internally.
-- We implement it as a single-fire CreateThread that waits first.
-- ---------------------------------------------------------------------------
function Citizen.SetTimeout(ms, fn)
    CreateThread(function()
        Wait(ms)
        fn()
    end)
end

-- ---------------------------------------------------------------------------
-- Promise / Citizen.Await
-- SHIM: FXServer ships a full Promise implementation backed by V8 micro-tasks
-- on the JS side. Here we implement a minimal Lua-native promise that works
-- with the coroutine scheduler.
-- ---------------------------------------------------------------------------

local Promise = {}
Promise.__index = Promise

function Promise.new()
    local p = setmetatable({
        _state    = "pending",   -- "pending" | "resolved" | "rejected"
        _value    = nil,
        _err      = nil,
        _waiters  = {},          -- coroutines blocked on Await
    }, Promise)
    return p
end

function Promise:resolve(value)
    if self._state ~= "pending" then return end
    self._state = "resolved"
    self._value = value
    for _, co in ipairs(self._waiters) do
        _heapPush(_threads, { wakeTime = GetGameTimer(), co = co })
    end
    self._waiters = {}
end

function Promise:reject(err)
    if self._state ~= "pending" then return end
    self._state = "rejected"
    self._err   = err
    for _, co in ipairs(self._waiters) do
        _heapPush(_threads, { wakeTime = GetGameTimer(), co = co })
    end
    self._waiters = {}
end

function Promise:next(onResolve, onReject)
    local p2 = Promise.new()
    local function handle()
        if self._state == "resolved" then
            local ok, v = pcall(onResolve, self._value)
            if ok then p2:resolve(v) else p2:reject(v) end
        elseif self._state == "rejected" then
            if onReject then
                local ok, v = pcall(onReject, self._err)
                if ok then p2:resolve(v) else p2:reject(v) end
            else
                p2:reject(self._err)
            end
        end
    end
    if self._state ~= "pending" then
        handle()
    else
        local co = coroutine.running()
        if co then
            -- wrap handle in a waker
            local wrapCo = coroutine.create(handle)
            table.insert(self._waiters, wrapCo)
        end
    end
    return p2
end

-- Citizen.Await(promise) — blocks the current thread until promise settles
function Citizen.Await(promise)
    assert(_current, "Citizen.Await() called outside of a CreateThread context")
    if promise._state == "resolved" then return promise._value end
    if promise._state == "rejected" then
        -- SHIM: Use error level 0 so the raw rejection message is preserved
        -- without a source-location prefix being added by the Lua VM.
        -- Real FXServer uses V8 promise rejection propagation (no level issue).
        error(promise._err, 0)
    end
    -- park this coroutine in the promise waiters
    table.insert(promise._waiters, _current)
    -- Yield with a private sentinel so ScheduleResourceTick does not auto re-queue.
    coroutine.yield(_awaitYield)
    if promise._state == "resolved" then return promise._value end
    -- Rejection: propagate the error value; level 0 preserves the raw message
    error(promise._err, 0)
end

-- Expose globally (resources use `promise:resolve` directly)
_G.Promise = Promise

-- ---------------------------------------------------------------------------
-- Public: ScheduleResourceTick()
-- Called by bootstrap.lua's main loop.
-- Returns the timestamp of the next scheduled wakeup, or nil if queue empty.
-- SHIM: In real FXServer this is called by the C++ game loop every frame.
-- ---------------------------------------------------------------------------
function ScheduleResourceTick()
    _frame = _frame + 1
    local now = GetGameTimer()

    while true do
        local top = _heapPeek(_threads)
        if not top then break end                      -- nothing queued
        if top.wakeTime > now then break end           -- next wakeup is in the future

        _heapPop(_threads)
        local co = top.co
        _current = co

        if coroutine.status(co) == "dead" then
            _current = nil
            -- do not re-queue
        else
            local ok, yieldValue = coroutine.resume(co)
            _current = nil

            if not ok then
                print("[cfxlua] coroutine error: " .. tostring(yieldValue))
                -- thread dies; don't re-queue
            elseif coroutine.status(co) ~= "dead" then
                if yieldValue ~= _awaitYield then
                    -- yielded: numeric yieldValue is requested wakeTime
                    local wakeAt = (type(yieldValue) == "number") and yieldValue or (now + 0)
                    _heapPush(_threads, { wakeTime = wakeAt, co = co })
                end
            end
            -- if dead: natural termination, discard
        end
    end

    -- Return time of next wake, so bootstrap can sleep accurately
    local next = _heapPeek(_threads)
    return next and next.wakeTime or nil
end

-- ---------------------------------------------------------------------------
-- Public: HasPendingThreads()
-- bootstrap.lua uses this to decide when to exit the loop.
-- ---------------------------------------------------------------------------
function HasPendingThreads()
    return #_threads > 0
end

-- ---------------------------------------------------------------------------
-- Convenience: run scheduler until all threads finish or timeout
-- Used directly in tests without bootstrap.lua
-- ---------------------------------------------------------------------------
function RunSchedulerUntilDone(maxMs)
    maxMs = maxMs or 10000
    local deadline = GetGameTimer() + maxMs
    while HasPendingThreads() do
        if GetGameTimer() > deadline then
            print("[cfxlua] WARNING: scheduler timed out after " .. maxMs .. "ms")
            break
        end
        local next = ScheduleResourceTick()
        if next then
            -- sleep until next wakeup (portable busy-wait for sub-10ms granularity)
            -- SHIM: Real FXServer sleeps at the C++ game-loop level.
            -- os.execute("sleep 0.001") is too coarse on some platforms.
            -- We busy-wait with a tight loop for accuracy in tests.
            local sleepMs = math.max(0, next - GetGameTimer())
            if sleepMs > 10 then
                -- For longer waits, use os.execute sleep
                os.execute("sleep " .. string.format("%.4f", sleepMs / 1000))
            end
            -- else: busy-wait (tight loop) for sub-10ms precision
        end
    end
end
