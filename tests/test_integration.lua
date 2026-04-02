-- =============================================================================
-- tests/test_integration.lua
-- =============================================================================
-- Simulates a realistic server-side resource pattern: players "connecting",
-- their data being stored in statebags, exports being used cross-resource,
-- async operations with promises, and JSON serialisation.
-- =============================================================================
T.suite("Integration (realistic resource patterns)")

-- ---------------------------------------------------------------------------
-- Test 1: Player connect → statebag → disconnect lifecycle
-- ---------------------------------------------------------------------------
do
    local connected    = {}
    local disconnected = {}

    local h1 = AddEventHandler("playerConnecting", function(name, setKick, deferrals)
        connected[#connected + 1] = name
        -- Typical resource pattern: store data in statebag
        local src = source
        Player(src).state.playerName = name
        Player(src).state.joinTime   = GetGameTimer()
    end)

    local h2 = AddEventHandler("playerDropped", function(reason)
        disconnected[#disconnected + 1] = tostring(source)
    end)

    -- Simulate two players connecting
    __cfx_internal_triggerEvent("playerConnecting", 1, "Alice", function() end, {})
    __cfx_internal_triggerEvent("playerConnecting", 2, "Bob",   function() end, {})

    T.eq(#connected, 2, "Both playerConnecting handlers fired")
    T.eq(Player(1).state.playerName, "Alice", "Player 1 statebag populated")
    T.eq(Player(2).state.playerName, "Bob",   "Player 2 statebag populated")
    T.ok(type(Player(1).state.joinTime) == "number", "joinTime is a number")

    -- Simulate disconnect
    __cfx_internal_triggerEvent("playerDropped", 1, "Quit")
    T.eq(#disconnected, 1, "playerDropped fired")

    RemoveEventHandler(h1)
    RemoveEventHandler(h2)
end

-- ---------------------------------------------------------------------------
-- Test 2: Async data fetch via promise, consumed with Citizen.Await
-- ---------------------------------------------------------------------------
do
    -- Simulate a database lookup that resolves asynchronously
    local function fetchPlayerData(playerId)
        local p = Promise.new()
        Citizen.SetTimeout(20, function()
            p:resolve({ id = playerId, gold = 1500, level = 42 })
        end)
        return p
    end

    local fetchedData = nil
    CreateThread(function()
        local data = Citizen.Await(fetchPlayerData(7))
        fetchedData = data
    end)

    RunSchedulerUntilDone(2000)
    T.ok(fetchedData ~= nil, "Async data fetch completed")
    T.eq(fetchedData.id,    7,    "Fetched correct player id")
    T.eq(fetchedData.gold,  1500, "Fetched gold value")
    T.eq(fetchedData.level, 42,   "Fetched level value")
end

-- ---------------------------------------------------------------------------
-- Test 3: Cross-resource export pattern with JSON serialisation
-- ---------------------------------------------------------------------------
do
    -- Resource A registers an export
    exports("dataResource", {
        getPlayerData = function(src)
            return {
                name    = Player(src).state.playerName or "Unknown",
                src     = src,
                active  = true,
            }
        end,
        serializePlayer = function(src)
            local data = exports["dataResource"].getPlayerData(src)
            return json.encode(data)
        end,
    })

    -- Set up a player for this test
    Player(3).state.playerName = "Charlie"

    -- Resource B calls the export
    local data   = exports["dataResource"].getPlayerData(3)
    local serial = exports["dataResource"].serializePlayer(3)

    T.eq(data.name, "Charlie", "Export returns correct player name")
    T.eq(data.src,  3,         "Export returns correct source")
    T.ok(type(serial) == "string", "serializePlayer returns JSON string")

    local decoded = json.decode(serial)
    T.eq(decoded.name,   "Charlie", "JSON round-trip preserves name")
    T.eq(decoded.active, true,      "JSON round-trip preserves boolean")
end

-- ---------------------------------------------------------------------------
-- Test 4: Event-driven state machine (command → processing → notify)
-- ---------------------------------------------------------------------------
do
    local phases = {}

    -- Register a command handler (as some resources do)
    RegisterCommand("test_cmd", function(src, args, raw)
        phases[#phases + 1] = "command-received"
        -- Simulate async processing
        CreateThread(function()
            Wait(10)
            phases[#phases + 1] = "processing"
            TriggerEvent("test:commandComplete", src, args[1])
        end)
    end, false)

    local h = AddEventHandler("test:commandComplete", function(src, arg1)
        phases[#phases + 1] = "complete:" .. tostring(arg1)
    end)

    -- Fire the command as if a player typed it
    __cfx_runCommand("test_cmd", 5, { "payload" }, "test_cmd payload")
    RunSchedulerUntilDone(1000)

    T.eq(#phases, 3, "All three phases executed")
    T.eq(phases[1], "command-received",  "Phase 1: command received")
    T.eq(phases[2], "processing",        "Phase 2: async processing")
    T.eq(phases[3], "complete:payload",  "Phase 3: completion event with payload")
    RemoveEventHandler(h)
end

-- ---------------------------------------------------------------------------
-- Test 5: KVP + JSON for persistent resource data pattern
-- ---------------------------------------------------------------------------
do
    -- Pattern: store a Lua table as JSON in KVP
    local function saveConfig(cfg)
        SetResourceKvp("config:main", json.encode(cfg))
    end

    local function loadConfig(default)
        local raw = GetResourceKvpString("config:main")
        if raw then
            return json.decode(raw)
        end
        return default
    end

    local original = { maxPlayers = 32, pvp = true, economy = { startCash = 5000 } }
    saveConfig(original)
    local loaded = loadConfig({})

    T.eq(loaded.maxPlayers,        32,   "KVP+JSON: maxPlayers preserved")
    T.eq(loaded.pvp,               true, "KVP+JSON: pvp flag preserved")
    T.eq(loaded.economy.startCash, 5000, "KVP+JSON: nested value preserved")
end

-- ---------------------------------------------------------------------------
-- Test 6: Multiple concurrent async operations with independent promises
-- ---------------------------------------------------------------------------
do
    local results = {}

    local function asyncWork(id, delay)
        local p = Promise.new()
        Citizen.SetTimeout(delay, function()
            p:resolve(id)
        end)
        return p
    end

    -- Spawn 5 concurrent threads, each awaiting a different promise
    for i = 1, 5 do
        local capturedI = i
        CreateThread(function()
            local result = Citizen.Await(asyncWork(capturedI, capturedI * 10))
            results[#results + 1] = result
        end)
    end

    RunSchedulerUntilDone(2000)
    T.eq(#results, 5, "All 5 concurrent async operations completed")

    -- Check all IDs are present (order may vary)
    local seen = {}
    for _, v in ipairs(results) do seen[v] = true end
    for i = 1, 5 do
        T.ok(seen[i], "Result " .. i .. " received")
    end
end

-- ---------------------------------------------------------------------------
-- Test 7: onResourceStart fires before user code runs (lifecycle)
-- ---------------------------------------------------------------------------
-- NOTE: onResourceStart fires during bootstrap.lua before the test script
-- runs, so we verify the lifecycle hook machinery works by re-firing it.
do
    local startFired = false
    local h = AddEventHandler("onResourceStart", function(resourceName)
        if resourceName == GetCurrentResourceName() then
            startFired = true
        end
    end)
    -- Re-fire synthetically (bootstrap already fired once; we test the handler)
    __cfx_internal_triggerEvent("onResourceStart", "", GetCurrentResourceName())
    T.ok(startFired, "onResourceStart handler receives own resource name")
    RemoveEventHandler(h)
end
