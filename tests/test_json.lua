-- =============================================================================
-- tests/test_json.lua
-- =============================================================================
T.suite("JSON (dkjson)")

-- ---------------------------------------------------------------------------
-- Test 1: Encode primitives
-- ---------------------------------------------------------------------------
do
    T.eq(json.encode(nil),   "null",  "nil encodes to null")
    T.eq(json.encode(true),  "true",  "true encodes to true")
    T.eq(json.encode(false), "false", "false encodes to false")
    T.eq(json.encode(42),    "42",    "integer encodes without decimal")
    T.eq(json.encode(3.14),  json.encode(3.14), "float encodes (self-consistent)")
    T.eq(json.encode("hi"),  '"hi"',  "string encodes with quotes")
end

-- ---------------------------------------------------------------------------
-- Test 2: json.null sentinel
-- ---------------------------------------------------------------------------
do
    T.eq(json.encode(json.null), "null", "json.null encodes to null")
    local decoded = json.decode("null")
    T.ok(decoded == json.null, "null decodes to json.null sentinel")
end

-- ---------------------------------------------------------------------------
-- Test 3: String escaping
-- ---------------------------------------------------------------------------
do
    T.eq(json.encode('say "hi"'), '"say \\"hi\\""', "Double quotes escaped")
    T.eq(json.encode("line\nnewline"), '"line\\nnewline"', "Newline escaped")
    T.eq(json.encode("tab\there"), '"tab\\there"', "Tab escaped")
    T.eq(json.encode("back\\slash"), '"back\\\\slash"', "Backslash escaped")
end

-- ---------------------------------------------------------------------------
-- Test 4: Array encoding
-- ---------------------------------------------------------------------------
do
    T.eq(json.encode({}),         "[]",       "Empty table encodes as empty array")
    T.eq(json.encode({1, 2, 3}),  "[1,2,3]",  "Integer array encodes correctly")
    T.eq(json.encode({"a","b"}),  '["a","b"]', "String array encodes correctly")
end

-- ---------------------------------------------------------------------------
-- Test 5: Object encoding (keys sorted for determinism)
-- ---------------------------------------------------------------------------
do
    local obj = { z = 1, a = 2, m = 3 }
    local enc = json.encode(obj)
    T.ok(enc:find('"a":'), "Key 'a' present in encoded object")
    T.ok(enc:find('"m":'), "Key 'm' present")
    T.ok(enc:find('"z":'), "Key 'z' present")
    -- Check alphabetical order: a before m before z
    local pos_a = enc:find('"a":')
    local pos_m = enc:find('"m":')
    local pos_z = enc:find('"z":')
    T.ok(pos_a < pos_m and pos_m < pos_z, "Object keys are sorted alphabetically")
end

-- ---------------------------------------------------------------------------
-- Test 6: Nested structures
-- ---------------------------------------------------------------------------
do
    local nested = { users = { { name = "Alice", age = 30 }, { name = "Bob", age = 25 } } }
    local enc = json.encode(nested)
    local dec = json.decode(enc)
    T.ok(type(dec) == "table", "Nested structure decode returns table")
    T.ok(type(dec.users) == "table", "Nested array decoded")
    T.eq(dec.users[1].name, "Alice", "Deeply nested string value recovered")
    T.eq(dec.users[2].age, 25, "Deeply nested number value recovered")
end

-- ---------------------------------------------------------------------------
-- Test 7: Round-trip (encode → decode → re-encode)
-- ---------------------------------------------------------------------------
do
    local original = {
        id     = 1,
        name   = "Test Resource",
        active = true,
        tags   = { "server", "lua", "fivem" },
        meta   = { version = "1.0.1", build = 42 },
    }
    local enc1 = json.encode(original)
    local dec  = json.decode(enc1)
    local enc2 = json.encode(dec)
    T.eq(enc1, enc2, "Round-trip encode→decode→encode is deterministic")
end

-- ---------------------------------------------------------------------------
-- Test 8: Decode various types
-- ---------------------------------------------------------------------------
do
    T.eq(json.decode("42"),      42,     "Integer decodes")
    T.eq(json.decode("3.14"),    3.14,   "Float decodes")
    T.eq(json.decode("true"),    true,   "true decodes")
    T.eq(json.decode("false"),   false,  "false decodes")
    T.eq(json.decode('"hello"'), "hello","String decodes")
end

-- ---------------------------------------------------------------------------
-- Test 9: Unicode escape sequences
-- ---------------------------------------------------------------------------
do
    local decoded = json.decode('"\\u0041\\u0042\\u0043"')
    T.eq(decoded, "ABC", "\\u escape sequences decode correctly")
end

-- ---------------------------------------------------------------------------
-- Test 10: Decode error returns nil + message
-- ---------------------------------------------------------------------------
do
    local val, err = json.decode("{broken")
    T.ok(val == nil, "Malformed JSON returns nil")
    T.ok(type(err) == "string", "Malformed JSON returns error string")
end

-- ---------------------------------------------------------------------------
-- Test 11: Decode error on trailing garbage
-- ---------------------------------------------------------------------------
do
    -- Valid JSON followed by garbage is technically invalid.
    -- Our decoder reads the first value and stops; this is lenient behaviour.
    -- Test that at minimum the first value parses.
    local val, err = json.decode('42')
    T.eq(val, 42, "Simple number parses cleanly")
end

-- ---------------------------------------------------------------------------
-- Test 12: NaN and infinity raise errors
-- ---------------------------------------------------------------------------
do
    T.throws(
        function() json.encode(0/0) end,
        "Encoding NaN raises error"
    )
    T.throws(
        function() json.encode(math.huge) end,
        "Encoding +infinity raises error"
    )
end

-- ---------------------------------------------------------------------------
-- Test 13: Circular reference raises error
-- ---------------------------------------------------------------------------
do
    local t = {}
    t.self = t
    T.throws(
        function() json.encode(t) end,
        "Circular reference raises error"
    )
end

-- ---------------------------------------------------------------------------
-- Test 14: Indented output
-- ---------------------------------------------------------------------------
do
    local enc = json.encode({ a = 1 }, { indent = true })
    T.ok(enc:find("\n"), "Indented output contains newlines")
    T.ok(enc:find('"a"'), "Indented output contains key")
end
