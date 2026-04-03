-- =============================================================================
-- tests/test_fxserver_sim.lua
-- =============================================================================
T.suite("FXServer Internals Simulation")

-- Reset simulation state for deterministic assertions.
__cfx_resetServerSim()

-- ---------------------------------------------------------------------------
-- Test 0: Runtime side identity
-- ---------------------------------------------------------------------------
do
    T.ok(IsDuplicityVersion(), "IsDuplicityVersion reports server-side runtime")
end

-- ---------------------------------------------------------------------------
-- Test 1: Player registry + connect/disconnect lifecycle
-- ---------------------------------------------------------------------------
do
    local connected = {}
    local dropped = {}

    RegisterNetEvent("test:client:event")

    local hConn = AddEventHandler("playerConnecting", function(name)
        connected[#connected + 1] = { src = tonumber(source), name = name }
    end)
    local hDrop = AddEventHandler("playerDropped", function(reason)
        dropped[#dropped + 1] = { src = tonumber(source), reason = tostring(reason) }
    end)

    __cfx_connectPlayer(11, { name = "Alice" })
    __cfx_connectPlayer(22, { name = "Bob" })

    T.eq(GetNumPlayers(), 2, "Two players connected")
    T.eq(GetNumPlayerIndices(), 2, "Two player indices available")
    T.eq(GetPlayerFromIndex(0), "11", "Player index 0 is first connected source")
    T.eq(GetPlayerFromIndex(1), "22", "Player index 1 is second connected source")
    T.eq(GetPlayerName(11), "Alice", "GetPlayerName uses connected player data")
    T.ok(DoesPlayerExist(22), "DoesPlayerExist reports connected player")
    T.eq(#connected, 2, "playerConnecting fired for each connection")

    __cfx_disconnectPlayer(11, "Quit")
    T.eq(GetNumPlayers(), 1, "Disconnect removes player from registry")
    T.eq(#dropped, 1, "playerDropped fired on disconnect")
    T.eq(dropped[1].src, 11, "playerDropped source is disconnecting player")

    RemoveEventHandler(hConn)
    RemoveEventHandler(hDrop)
end

-- ---------------------------------------------------------------------------
-- Test 2: Routing bucket semantics
-- ---------------------------------------------------------------------------
do
    __cfx_connectPlayer(33, { name = "Carol" })

    T.eq(GetPlayerRoutingBucket(33), 0, "Player default routing bucket is 0")
    SetPlayerRoutingBucket(33, 7)
    T.eq(GetPlayerRoutingBucket(33), 7, "Player routing bucket updates")

    local veh = CreateVehicleServerSetter(1234, "automobile", 1.0, 2.0, 3.0, 90.0)
    T.ok(DoesEntityExist(veh), "Created vehicle exists")
    T.eq(GetEntityRoutingBucket(veh), 0, "Entity default bucket is 0")
    SetEntityRoutingBucket(veh, 5)
    T.eq(GetEntityRoutingBucket(veh), 5, "Entity routing bucket updates")
end

-- ---------------------------------------------------------------------------
-- Test 3: State bag change handlers (OneSync-style callback)
-- ---------------------------------------------------------------------------
do
    local changes = {}
    local cookie = AddStateBagChangeHandler("hp", nil, function(bagName, key, value, _, replicated)
        changes[#changes + 1] = {
            bag = bagName,
            key = key,
            value = value,
            replicated = replicated,
        }
    end)

    Player(33).state.hp = 150
    Entity(2001).state.hp = 800
    GlobalState.hp = 1

    T.eq(#changes, 3, "State bag handler sees player/entity/global writes")
    T.eq(changes[1].bag, "player:33", "Player bag name format")
    T.eq(changes[2].bag, "entity:2001", "Entity bag name format")
    T.eq(changes[3].bag, "__global__", "Global bag name format")
    T.ok(changes[1].replicated, "State bag write marked replicated")

    T.eq(GetPlayerFromStateBagName("player:33"), "33", "Resolve player from state bag name")
    T.eq(GetEntityFromStateBagName("entity:2001"), 2001, "Resolve entity from state bag name")

    T.ok(RemoveStateBagChangeHandler(cookie), "RemoveStateBagChangeHandler removes cookie")
end

-- ---------------------------------------------------------------------------
-- Test 4: TriggerClientEvent dispatches net-safe handlers with source
-- ---------------------------------------------------------------------------
do
    RegisterNetEvent("test:client:event")
    local seen = {}
    local h = AddEventHandler("test:client:event", function(payload)
        seen[#seen + 1] = { src = tonumber(source), payload = payload }
    end)

    TriggerClientEvent("test:client:event", 22, "single")
    T.eq(#seen, 1, "Targeted TriggerClientEvent dispatched once")
    T.eq(seen[1].src, 22, "Targeted TriggerClientEvent source matches target player")
    T.eq(seen[1].payload, "single", "Targeted TriggerClientEvent payload propagated")

    TriggerClientEvent("test:client:event", -1, "broadcast")
    T.ok(#seen >= 2, "Broadcast TriggerClientEvent dispatched to connected players")

    RemoveEventHandler(h)
end

-- ---------------------------------------------------------------------------
-- Test 5: Convar write/read path
-- ---------------------------------------------------------------------------
do
    SetConvar("sv_hostname", "CfxLua Test")
    SetConvarReplicated("sv_maxclients", "64")

    T.eq(GetConvar("sv_hostname", "x"), "CfxLua Test", "SetConvar value round-trip")
    T.eq(GetConvarInt("sv_maxclients", 1), 64, "SetConvarReplicated visible via GetConvarInt")
end

-- ---------------------------------------------------------------------------
-- Test 6: PerformHttpRequest frontend uses backend native bridge
-- ---------------------------------------------------------------------------
do
    local original = PerformHttpRequestInternalEx
    local nativeCalled = false
    local callbackCalled = false
    local callbackStatus = nil

    PerformHttpRequestInternalEx = function(req)
        nativeCalled = true
        local token = 99991
        Citizen.SetTimeout(0, function()
            __cfx_internal_triggerEvent(
                "__cfx_internal:httpResponse",
                "",
                token,
                204,
                "",
                { ["content-type"] = "text/plain" },
                nil
            )
        end)
        return token
    end

    PerformHttpRequest("https://example.invalid", function(status, body, headers, err)
        callbackCalled = true
        callbackStatus = status
    end, "GET")

    RunSchedulerUntilDone(1000)

    T.ok(nativeCalled, "PerformHttpRequest routed through PerformHttpRequestInternalEx")
    T.ok(callbackCalled, "PerformHttpRequest callback invoked via internal response dispatch")
    T.eq(callbackStatus, 204, "PerformHttpRequest callback receives bridged status")

    PerformHttpRequestInternalEx = original
end
