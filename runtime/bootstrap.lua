-- =============================================================================
-- bootstrap.lua  —  CfxLua Standalone Runtime Entry Point
-- =============================================================================
-- Usage:
--   cfxlua-vm bootstrap.lua <script.lua> [arg1 arg2 ...]
--   (via wrapper: cfxlua <script.lua> [arg1 arg2 ...])
--
-- Load order (dependency-driven):
--   1. scheduler.lua  — GetGameTimer shim, CreateThread, Wait, promises
--   2. events.lua     — AddEventHandler, TriggerEvent, net stubs
--   3. json.lua       — pure-Lua JSON (no deps)
--   4. msgpack.lua    — pure-Lua MessagePack (no deps)
--   5. citizen.lua    — Citizen.*, exports, statebags, KVP, convars
--   6. stubs.lua      — server native no-ops (deps: scheduler, citizen)
--   7. user script    — arg[1]
--   8. tick loop      — drives scheduler until all threads finish
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Resolve runtime directory
-- SHIM: __cfx_bootstrapPath is set by the shell wrapper so bootstrap.lua
-- knows where the runtime/ directory lives regardless of CWD.
-- ---------------------------------------------------------------------------
local _runtimeDir
if __cfx_bootstrapPath then
    -- Injected by wrapper: the directory containing bootstrap.lua
    _runtimeDir = __cfx_bootstrapPath .. "/runtime/"
else
    -- Fallback: derive from arg[0] (the path used to invoke this script)
    local self = arg and arg[0] or "bootstrap.lua"
    _runtimeDir = self:match("(.+[\\/])") or "./"
    -- If arg[0] is just "bootstrap.lua" (no path), assume we're IN runtime/
    -- and step up one level if needed.
    if _runtimeDir == "./" then
        -- Try to find scheduler.lua relative to us
        local f = io.open(_runtimeDir .. "scheduler.lua", "r")
        if not f then
            _runtimeDir = "./runtime/"
        else
            f:close()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Module loader
-- ---------------------------------------------------------------------------
local function _load(name)
    local path = _runtimeDir .. name
    local fn, err = loadfile(path)
    if not fn then
        io.stderr:write(string.format(
            "[cfxlua] FATAL: could not load runtime module '%s': %s\n", path, err
        ))
        os.exit(1)
    end
    local ok, result = xpcall(fn, debug.traceback)
    if not ok then
        io.stderr:write(string.format(
            "[cfxlua] FATAL: error executing runtime module '%s':\n%s\n", name, result
        ))
        os.exit(1)
    end
    return result
end

-- ---------------------------------------------------------------------------
-- Phase 1: Parse argv
-- The shell wrapper execs:   cfxlua-vm bootstrap.lua <userscript> [args...]
-- Inside Lua:  arg[0] = "bootstrap.lua",  arg[1] = "<userscript>",  ...
-- If the first arg is "--", skip it (POSIX convention from the wrapper).
-- ---------------------------------------------------------------------------
local _userScriptIdx = 1
if arg and arg[1] == "--" then _userScriptIdx = 2 end
local _userScript = arg and arg[_userScriptIdx]

-- Derive resource name from script filename (strip path and extension)
local _resourceName = "standalone"
if _userScript then
    _resourceName = _userScript:match("[^/\\]+$") or _userScript
    _resourceName = _resourceName:match("^(.+)%.[^%.]+$") or _resourceName
end

-- Expose for citizen.lua's GetCurrentResourceName() (loaded after this)
os.getenv = os.getenv or function() return nil end  -- safety
-- We set via rawset on the env table equivalent; citizen.lua checks this var:
-- CFXLUA_RESOURCE_NAME env var (set by shell wrapper from the script filename)
-- If not set, we patch after citizen.lua loads.

-- ---------------------------------------------------------------------------
-- Phase 2: Load runtime modules in dependency order
-- ---------------------------------------------------------------------------

-- 1. Scheduler (defines GetGameTimer, CreateThread, Wait, Citizen table skeleton)
_load("scheduler.lua")

-- 2. Events (depends on: print, Citizen.SetTimeout from scheduler)
_load("events.lua")

-- 3. JSON (no dependencies)
_load("json.lua")

-- 4. MessagePack (no dependencies)
_load("msgpack.lua")

-- 5. Citizen namespace (depends on: scheduler for Wait/CreateThread, events)
_load("citizen.lua")

-- Patch resource name now that citizen.lua has set up GetCurrentResourceName
-- citizen.lua reads the env var; if that's not set, override the internal var directly
if not os.getenv("CFXLUA_RESOURCE_NAME") then
    -- Re-declare the closure variable by re-registering the function
    local _rn = _resourceName
    GetCurrentResourceName = function() return _rn end
end

-- 6. Native stubs (depends on: scheduler for SetTimeout/CreateThread, citizen)
-- Save the real Wait before stubs.lua may try to override it
_G.__cfx_scheduler_wait = Wait
_G.__cfx_in_thread = false
_load("stubs.lua")
_load("stubs_fivem_server.lua")
_load("fxserver.lua")

-- ---------------------------------------------------------------------------
-- Phase 3: Emit synthetic lifecycle events
-- SHIM: FXServer fires onResourceStart, onServerResourceStart before running
-- the resource's main file. Resources hook these to do init work.
-- ---------------------------------------------------------------------------
local function _fireLifecycle(name)
    __cfx_internal_triggerEvent(name, "", _resourceName)
end

_fireLifecycle("onResourceStart")
_fireLifecycle("onServerResourceStart")

-- ---------------------------------------------------------------------------
-- Phase 4: Load and execute the user script
-- ---------------------------------------------------------------------------
if not _userScript then
    io.stderr:write(
        "[cfxlua] ERROR: no script specified.\n" ..
        "Usage: cfxlua <script.lua> [args...]\n"
    )
    os.exit(1)
end

-- Rebuild arg table so user script sees clean args (arg[0] = script path)
local _userArgs = {}
_userArgs[0] = _userScript
for i = _userScriptIdx + 1, #arg do
    _userArgs[i - _userScriptIdx] = arg[i]
end
arg = _userArgs

local fn, loadErr = loadfile(_userScript)
if not fn then
    io.stderr:write("[cfxlua] ERROR: could not load script '" .. _userScript .. "': " .. tostring(loadErr) .. "\n")
    os.exit(1)
end

-- SHIM: FXServer wraps the resource main file in a protected coroutine so
-- that errors in the top-level body don't crash the scheduler. We do the same.
-- The main file runs inside a CreateThread so that:
--   (a) it has access to Wait() / Citizen.Await()
--   (b) any threads it spawns are already in the queue when the loop starts
CreateThread(function()
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
        io.stderr:write("[cfxlua] Script error: " .. tostring(err) .. "\n")
    end
end)

-- ---------------------------------------------------------------------------
-- Phase 5: Main scheduler tick loop
-- SHIM: FXServer calls ScheduleResourceTick() from its C++ game loop at
-- ~60 Hz. We drive it here with accurate millisecond-level sleeping.
-- The loop exits when all threads have completed (no more pending work).
-- ---------------------------------------------------------------------------
local MAX_IDLE_MS   = 30000   -- exit if no threads for 30 s (deadlock guard)
local TICK_FLOOR_MS = 1       -- minimum sleep between ticks (prevents busy-spin)
local idleStart     = nil
local _isWindows = package.config:sub(1, 1) == "\\"

local function _sleepMs(ms)
    if ms <= 0 then return end

    if _isWindows then
        -- Use PowerShell sleep for millisecond precision on Windows.
        local cmd = string.format(
            'powershell -NoProfile -NonInteractive -Command "Start-Sleep -Milliseconds %d"',
            math.floor(ms)
        )
        local ok = os.execute(cmd)
        if not ok then
            -- Fallback: busy-wait if PowerShell isn't available.
            local t0 = GetGameTimer()
            while (GetGameTimer() - t0) < ms do end
        end
        return
    end

    local sleepSec = ms / 1000
    local ok = os.execute(string.format("sleep %.4f 2>/dev/null", sleepSec))
    if not ok then
        -- Fallback for minimal environments.
        local t0 = GetGameTimer()
        while (GetGameTimer() - t0) < ms do end
    end
end

while true do
    local nextWake = ScheduleResourceTick()

    if not HasPendingThreads() then
        -- No threads: give a short grace period for SetTimeout(0) callbacks
        -- that were just registered by the script's top-level code.
        if not idleStart then
            idleStart = GetGameTimer()
        elseif GetGameTimer() - idleStart > 100 then
            -- 100 ms grace with no new threads → done
            break
        end
        -- Tight-loop for 100 ms grace period
    else
        idleStart = nil   -- reset idle timer when threads exist
    end

    if nextWake then
        local sleepMs = math.max(TICK_FLOOR_MS, nextWake - GetGameTimer())
        if sleepMs > 2 then
            -- SHIM: Real FXServer sleeps in the C++ event loop (libuv).
            -- Use platform-appropriate sleep without shell-error spam.
            _sleepMs(sleepMs)
        end
        -- For sub-2ms sleeps: busy-wait (acceptable for test workloads)
    end
end

-- ---------------------------------------------------------------------------
-- Phase 6: Teardown lifecycle events
-- ---------------------------------------------------------------------------
_fireLifecycle("onResourceStop")
_fireLifecycle("onServerResourceStop")
