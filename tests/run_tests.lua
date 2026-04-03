-- =============================================================================
-- tests/run_tests.lua  —  CfxLua Standalone Test Runner
-- =============================================================================
-- Usage:
--   cfxlua tests/run_tests.lua           (via wrapper)
--   lua -e "__cfx_bootstrapPath='.'" runtime/bootstrap.lua tests/run_tests.lua
--
-- bootstrap.lua has already loaded the full runtime by the time this file runs.
-- We implement a minimal test framework and then load each test module.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Minimal test framework
-- ---------------------------------------------------------------------------
local _pass  = 0
local _fail  = 0
local _skip  = 0
local _suite = ""

local function setSuite(name)
    _suite = name
    rawprint("\n── " .. name .. " ──────────────────────────────────")
end

local function ok(cond, label)
    if cond then
        rawprint(string.format("  ✓  %s", label))
        _pass = _pass + 1
    else
        rawprint(string.format("  ✗  FAIL: %s", label))
        _fail = _fail + 1
    end
end

local function eq(a, b, label)
    local cond = (a == b)
    if not cond then
        rawprint(string.format("  ✗  FAIL: %s\n       expected: %s\n       got:      %s",
            label, tostring(b), tostring(a)))
        _fail = _fail + 1
    else
        rawprint(string.format("  ✓  %s", label))
        _pass = _pass + 1
    end
end

local function skip(label)
    rawprint(string.format("  -  SKIP: %s", label))
    _skip = _skip + 1
end

local function throws(fn, label)
    local ok_, err = pcall(fn)
    if not ok_ then
        rawprint(string.format("  ✓  %s (threw: %s)", label, tostring(err):match("[^\n]+") or ""))
        _pass = _pass + 1
    else
        rawprint(string.format("  ✗  FAIL: %s (expected error but none was raised)", label))
        _fail = _fail + 1
    end
end

-- Expose test helpers globally so sub-files can use them
_G.T = { ok = ok, eq = eq, skip = skip, throws = throws, suite = setSuite }

-- ---------------------------------------------------------------------------
-- Test module loader
-- ---------------------------------------------------------------------------
local _testDir
do
    local self = arg and arg[0] or "tests/run_tests.lua"
    _testDir = self:match("(.+[\\/])") or "tests/"
end

local function runModule(name)
    local path = _testDir .. name
    local fn, err = loadfile(path)
    if not fn then
        rawprint("  ERROR: could not load test module '" .. path .. "': " .. tostring(err))
        _fail = _fail + 1
        return
    end
    local ok_, err2 = xpcall(fn, debug.traceback)
    if not ok_ then
        rawprint("  ERROR in test module '" .. name .. "':\n" .. tostring(err2))
        _fail = _fail + 1
    end
end

-- ---------------------------------------------------------------------------
-- Run all test modules
-- ---------------------------------------------------------------------------
rawprint("═══════════════════════════════════════════════════")
rawprint("  CfxLua Standalone — Test Suite")
rawprint("═══════════════════════════════════════════════════")

runModule("test_scheduler.lua")
runModule("test_events.lua")
runModule("test_exports.lua")
runModule("test_statebags.lua")
runModule("test_json.lua")
runModule("test_msgpack.lua")
runModule("test_kvp.lua")
runModule("test_server_native_surface.lua")
runModule("test_fxserver_sim.lua")
runModule("test_integration.lua")

-- ---------------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------------
rawprint("\n═══════════════════════════════════════════════════")
rawprint(string.format(
    "  Results: %d passed, %d failed, %d skipped",
    _pass, _fail, _skip
))
rawprint("═══════════════════════════════════════════════════")

if _fail > 0 then
    os.exit(1)
end
