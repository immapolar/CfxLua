-- =============================================================================
-- tests/test_statebags.lua
-- =============================================================================
T.suite("StateBags")

-- ---------------------------------------------------------------------------
-- Test 1: GlobalState read/write
-- ---------------------------------------------------------------------------
do
    GlobalState.testKey = "testValue"
    T.eq(GlobalState.testKey, "testValue", "GlobalState write/read roundtrip (string)")
end

-- ---------------------------------------------------------------------------
-- Test 2: GlobalState with various types
-- ---------------------------------------------------------------------------
do
    GlobalState.numVal  = 42
    GlobalState.boolVal = true
    GlobalState.tblVal  = { a = 1, b = 2 }

    T.eq(GlobalState.numVal,  42,   "GlobalState stores numbers")
    T.eq(GlobalState.boolVal, true, "GlobalState stores booleans")
    T.ok(type(GlobalState.tblVal) == "table", "GlobalState stores tables")
    T.eq(GlobalState.tblVal.a, 1, "GlobalState table field accessible")
end

-- ---------------------------------------------------------------------------
-- Test 3: GlobalState returns nil for unset keys
-- ---------------------------------------------------------------------------
do
    T.ok(GlobalState.neverSet == nil, "Unset GlobalState key returns nil")
end

-- ---------------------------------------------------------------------------
-- Test 4: GlobalState overwrite
-- ---------------------------------------------------------------------------
do
    GlobalState.overwrite = "first"
    T.eq(GlobalState.overwrite, "first", "Initial GlobalState value set")
    GlobalState.overwrite = "second"
    T.eq(GlobalState.overwrite, "second", "GlobalState value overwritten")
end

-- ---------------------------------------------------------------------------
-- Test 5: Player state bags are per-player
-- ---------------------------------------------------------------------------
do
    Player(1).state.coins = 100
    Player(2).state.coins = 200

    T.eq(Player(1).state.coins, 100, "Player(1) state is independent")
    T.eq(Player(2).state.coins, 200, "Player(2) state is independent")
end

-- ---------------------------------------------------------------------------
-- Test 6: Player state returns nil for unset keys
-- ---------------------------------------------------------------------------
do
    T.ok(Player(99).state.neverSet == nil, "Unset player state key returns nil")
end

-- ---------------------------------------------------------------------------
-- Test 7: Player state persists across handle re-fetch
-- ---------------------------------------------------------------------------
do
    Player(5).state.level = 42
    -- Re-fetch the handle — same bag should be returned
    T.eq(Player(5).state.level, 42, "Player state persists when handle is re-fetched")
end

-- ---------------------------------------------------------------------------
-- Test 8: Entity state bags are per-entity
-- ---------------------------------------------------------------------------
do
    Entity(1001).state.health = 200
    Entity(1002).state.health = 150

    T.eq(Entity(1001).state.health, 200, "Entity(1001) health state")
    T.eq(Entity(1002).state.health, 150, "Entity(1002) health state is independent")
end

-- ---------------------------------------------------------------------------
-- Test 9: GlobalState and Player state are distinct namespaces
-- ---------------------------------------------------------------------------
do
    GlobalState.sharedKey = "global"
    Player(10).state.sharedKey = "player10"
    T.eq(GlobalState.sharedKey,        "global",   "GlobalState namespace is isolated")
    T.eq(Player(10).state.sharedKey,   "player10", "Player state namespace is isolated")
end

-- ---------------------------------------------------------------------------
-- Test 10: StateBag __tostring returns a meaningful string
-- ---------------------------------------------------------------------------
do
    local bag = GlobalState
    T.ok(
        type(tostring(bag)) == "string",
        "StateBag tostring returns a string"
    )
end

-- ---------------------------------------------------------------------------
-- Test 11: Nil assignment clears a value
-- ---------------------------------------------------------------------------
do
    GlobalState.willBeCleared = "exists"
    T.eq(GlobalState.willBeCleared, "exists", "Value exists before clear")
    GlobalState.willBeCleared = nil
    T.ok(GlobalState.willBeCleared == nil, "Value cleared after nil assignment")
end

-- ---------------------------------------------------------------------------
-- Test 12: Multiple writes to same player state key
-- ---------------------------------------------------------------------------
do
    Player(20).state.score = 0
    for i = 1, 5 do
        Player(20).state.score = Player(20).state.score + 10
    end
    T.eq(Player(20).state.score, 50, "Repeated writes to player state accumulate")
end
