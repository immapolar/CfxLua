-- =============================================================================
-- tests/test_exports.lua
-- =============================================================================
T.suite("Exports Proxy")

-- ---------------------------------------------------------------------------
-- Test 1: Register exports via table assignment
-- ---------------------------------------------------------------------------
do
    exports["myResource"] = {
        getGreeting = function(name) return "Hello, " .. name end,
        add         = function(a, b) return a + b end,
    }
    local greeting = exports["myResource"].getGreeting("World")
    T.eq(greeting, "Hello, World", "Registered export function executes correctly")
end

-- ---------------------------------------------------------------------------
-- Test 2: Register exports via callable syntax
-- ---------------------------------------------------------------------------
do
    exports("mathResource", {
        multiply = function(a, b) return a * b end,
        square   = function(n) return n * n end,
    })
    T.eq(exports["mathResource"].multiply(3, 4), 12, "Callable registration: multiply")
    T.eq(exports["mathResource"].square(5),      25, "Callable registration: square")
end

-- ---------------------------------------------------------------------------
-- Test 3: Accessing a non-existent function on a registered resource errors
-- ---------------------------------------------------------------------------
do
    exports("testExportRes", { fn1 = function() return 1 end })
    T.throws(
        function()
            exports["testExportRes"].nonExistent()
        end,
        "Accessing missing export function raises error"
    )
end

-- ---------------------------------------------------------------------------
-- Test 4: Accessing an unloaded resource returns a stub that warns (not error)
-- ---------------------------------------------------------------------------
do
    -- Resources that aren't registered return a proxy with stub functions.
    -- The stub should not raise an error on access (mirrors FXServer behaviour
    -- for resources that haven't started yet).
    local result = exports["unregisteredResource"].someFunction()
    T.ok(result == nil, "Unregistered resource export returns nil (stub)")
end

-- ---------------------------------------------------------------------------
-- Test 5: Overwriting an export updates the registry
-- ---------------------------------------------------------------------------
do
    exports("overwriteTest", { fn = function() return "v1" end })
    T.eq(exports["overwriteTest"].fn(), "v1", "Initial export registered")
    exports("overwriteTest", { fn = function() return "v2" end })
    T.eq(exports["overwriteTest"].fn(), "v2", "Overwritten export is updated")
end

-- ---------------------------------------------------------------------------
-- Test 6: Export registry inspection via helper
-- ---------------------------------------------------------------------------
do
    exports("inspectTest", { a = function() end, b = function() end })
    local reg = __cfx_getExportRegistry()
    T.ok(type(reg) == "table", "Export registry is a table")
    T.ok(reg["inspectTest"] ~= nil, "inspectTest is in the registry")
    T.ok(type(reg["inspectTest"].a) == "function", "Export 'a' is a function")
end

-- ---------------------------------------------------------------------------
-- Test 7: exports table rejects non-table values
-- ---------------------------------------------------------------------------
do
    T.throws(
        function() exports["bad"] = "not a table" end,
        "Assigning non-table to exports raises error"
    )
    T.throws(
        function() exports("bad2", 42) end,
        "Calling exports() with non-table raises error"
    )
end

-- ---------------------------------------------------------------------------
-- Test 8: Export functions receive all arguments correctly
-- ---------------------------------------------------------------------------
do
    exports("argTest", {
        echo = function(...) return ... end,
    })
    local a, b, c = exports["argTest"].echo(10, "x", false)
    T.eq(a, 10,    "First variadic arg passed")
    T.eq(b, "x",   "Second variadic arg passed")
    T.eq(c, false, "Third variadic arg passed (false)")
end
