-- =============================================================================
-- tests/test_msgpack.lua
-- =============================================================================
T.suite("MessagePack (lua-MessagePack)")

local function rt(val, label)
    local packed   = msgpack.pack(val)
    local unpacked = msgpack.unpack(packed)
    local match
    if type(val) == "table" then
        -- Deep comparison for tables
        local encOrig = json.encode(val)
        local encRt   = json.encode(unpacked)
        match = (encOrig == encRt)
    elseif val ~= val then  -- NaN
        match = (unpacked ~= unpacked)
    else
        match = (unpacked == val)
    end
    T.ok(match, label or
        string.format("round-trip: %s → packed(%d bytes) → %s",
            tostring(val), #packed, tostring(unpacked)))
end

-- ---------------------------------------------------------------------------
-- Test 1: Nil
-- ---------------------------------------------------------------------------
do
    rt(nil, "nil round-trips as nil")
end

-- ---------------------------------------------------------------------------
-- Test 2: Booleans
-- ---------------------------------------------------------------------------
do
    rt(true,  "true round-trips")
    rt(false, "false round-trips")
end

-- ---------------------------------------------------------------------------
-- Test 3: Integers (all msgpack integer format ranges)
-- ---------------------------------------------------------------------------
do
    rt(0,   "zero")
    rt(127, "positive fixint max (127)")
    rt(128, "uint8 boundary (128)")
    rt(255, "uint8 max (255)")
    rt(256, "uint16 boundary (256)")
    rt(65535, "uint16 max")
    rt(65536, "uint32 boundary")
    rt(-1,   "negative fixint (-1)")
    rt(-32,  "negative fixint min (-32)")
    rt(-33,  "int8 boundary (-33)")
    rt(-128, "int8 min (-128)")
    rt(-129, "int16 boundary (-129)")
    rt(-32768, "int16 min")
    rt(-32769, "int32 boundary")
end

-- ---------------------------------------------------------------------------
-- Test 4: Floats
-- ---------------------------------------------------------------------------
do
    rt(3.14,  "float 3.14")
    rt(-0.5,  "float -0.5")
    rt(1e10,  "float 1e10")
    rt(1e-10, "float 1e-10")
end

-- ---------------------------------------------------------------------------
-- Test 5: Strings (all length ranges)
-- ---------------------------------------------------------------------------
do
    rt("",     "empty string")
    rt("hello","fixstr")
    rt(string.rep("x", 31), "fixstr max (31 chars)")
    rt(string.rep("y", 32), "str8 boundary (32 chars)")
    rt(string.rep("z", 255),"str8 max")
    rt(string.rep("w", 256),"str16 boundary")
end

-- ---------------------------------------------------------------------------
-- Test 6: Arrays
-- ---------------------------------------------------------------------------
do
    rt({},           "empty array")
    rt({1, 2, 3},    "int array")
    rt({"a", "b"},   "string array")
    rt({true, false},"bool array")
end

-- ---------------------------------------------------------------------------
-- Test 7: Maps (objects)
-- ---------------------------------------------------------------------------
do
    rt({ key = "value" }, "simple map")
    rt({ a = 1, b = 2, c = 3 }, "three-key map")
end

-- ---------------------------------------------------------------------------
-- Test 8: Nested structures
-- ---------------------------------------------------------------------------
do
    local nested = {
        players = {
            { id = 1, name = "Alice", active = true },
            { id = 2, name = "Bob",   active = false },
        },
        count = 2,
    }
    rt(nested, "nested map/array structure")
end

-- ---------------------------------------------------------------------------
-- Test 9: pack returns a string
-- ---------------------------------------------------------------------------
do
    local packed = msgpack.pack({ test = true })
    T.ok(type(packed) == "string", "pack() returns a string")
    T.ok(#packed > 0, "packed string is non-empty")
end

-- ---------------------------------------------------------------------------
-- Test 10: unpack on reserved/invalid format byte raises error
-- 0xC1 is the only permanently reserved byte in the msgpack spec.
-- 0xFF is valid: it's negative fixint -1.
-- ---------------------------------------------------------------------------
do
    T.throws(
        function() msgpack.unpack("\xC1") end,
        "unpack with reserved format byte 0xC1 raises error"
    )
end

-- ---------------------------------------------------------------------------
-- Test 11: decode alias works
-- ---------------------------------------------------------------------------
do
    local val = msgpack.decode(msgpack.encode(99))
    T.eq(val, 99, "msgpack.decode alias works")
end
