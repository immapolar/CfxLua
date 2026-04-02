-- =============================================================================
-- tests/test_kvp.lua
-- =============================================================================
T.suite("KVP (Key-Value Persistence)")

-- ---------------------------------------------------------------------------
-- Test 1: SetResourceKvp / GetResourceKvpString
-- ---------------------------------------------------------------------------
do
    SetResourceKvp("test:str", "hello")
    T.eq(GetResourceKvpString("test:str"), "hello", "String KVP round-trip")
end

-- ---------------------------------------------------------------------------
-- Test 2: SetResourceKvpInt / GetResourceKvpInt
-- ---------------------------------------------------------------------------
do
    SetResourceKvpInt("test:int", 42)
    T.eq(GetResourceKvpInt("test:int"), 42, "Int KVP round-trip")
end

-- ---------------------------------------------------------------------------
-- Test 3: SetResourceKvpFloat / GetResourceKvpFloat
-- ---------------------------------------------------------------------------
do
    SetResourceKvpFloat("test:float", 3.14)
    local v = GetResourceKvpFloat("test:float")
    T.ok(math.abs(v - 3.14) < 0.001, "Float KVP round-trip (within tolerance)")
end

-- ---------------------------------------------------------------------------
-- Test 4: GetResourceKvpString for unset key returns nil
-- ---------------------------------------------------------------------------
do
    T.ok(GetResourceKvpString("test:unset") == nil, "Unset key returns nil")
end

-- ---------------------------------------------------------------------------
-- Test 5: DeleteResourceKvp removes a key
-- ---------------------------------------------------------------------------
do
    SetResourceKvp("test:delete", "exists")
    T.eq(GetResourceKvpString("test:delete"), "exists", "Key exists before delete")
    DeleteResourceKvp("test:delete")
    T.ok(GetResourceKvpString("test:delete") == nil, "Key gone after DeleteResourceKvp")
end

-- ---------------------------------------------------------------------------
-- Test 6: Overwrite existing value
-- ---------------------------------------------------------------------------
do
    SetResourceKvp("test:overwrite", "v1")
    SetResourceKvp("test:overwrite", "v2")
    T.eq(GetResourceKvpString("test:overwrite"), "v2", "KVP overwrite works")
end

-- ---------------------------------------------------------------------------
-- Test 7: StartFindKvp iterator finds keys by prefix
-- ---------------------------------------------------------------------------
do
    SetResourceKvp("prefix:a", "1")
    SetResourceKvp("prefix:b", "2")
    SetResourceKvp("prefix:c", "3")
    SetResourceKvp("other:x",  "4")  -- should NOT appear

    local found = {}
    local iter = StartFindKvp("prefix:")
    for key in iter do
        found[#found + 1] = key
    end

    T.eq(#found, 3, "StartFindKvp finds 3 keys with prefix 'prefix:'")
    -- Check all three are there
    local set = {}
    for _, k in ipairs(found) do set[k] = true end
    T.ok(set["prefix:a"], "prefix:a found")
    T.ok(set["prefix:b"], "prefix:b found")
    T.ok(set["prefix:c"], "prefix:c found")
    T.ok(not set["other:x"], "other:x not included in prefix search")
end

-- ---------------------------------------------------------------------------
-- Test 8: StartFindKvp with no matches returns empty iterator
-- ---------------------------------------------------------------------------
do
    local count = 0
    for _ in StartFindKvp("__nonexistent_prefix__:") do
        count = count + 1
    end
    T.eq(count, 0, "Empty prefix search returns no results")
end

-- ---------------------------------------------------------------------------
-- Test 9: GetConvar returns environment variable or default
-- ---------------------------------------------------------------------------
do
    -- Set an env var the test can reliably check
    local val = GetConvar("PATH", "default")
    -- PATH should exist on any POSIX system; if not, default is returned
    T.ok(type(val) == "string", "GetConvar returns a string")
end

-- ---------------------------------------------------------------------------
-- Test 10: GetConvarInt returns numeric value or default
-- ---------------------------------------------------------------------------
do
    local val = GetConvarInt("__CFXLUA_NONEXISTENT__", 99)
    T.eq(val, 99, "GetConvarInt returns default for missing variable")
end
