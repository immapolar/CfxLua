-- =============================================================================
-- examples/player_manager.lua  —  Realistic server resource example
-- Run: cfxlua examples/player_manager.lua
-- =============================================================================
-- Demonstrates:
--   - onResourceStart lifecycle hook
--   - playerConnecting / playerDropped handlers
--   - StateBags for player data storage
--   - KVP for persistent account data
--   - Exports for cross-resource data access
--   - RegisterCommand with Citizen.Await
--   - Promise-based "database" simulation
--   - Periodic background thread
-- =============================================================================

local resourceName = GetCurrentResourceName()
print("=== Player Manager starting on resource:", resourceName)

-- ---------------------------------------------------------------------------
-- "Database" layer (would use MySQL in production; simulated here)
-- ---------------------------------------------------------------------------
local _db = {
    accounts = {
        ["steam:00001"] = { name = "Alice",   cash = 10000, level = 15 },
        ["steam:00002"] = { name = "Bob",     cash = 5000,  level = 8  },
        ["steam:00003"] = { name = "Charlie", cash = 25000, level = 42 },
    }
}

local function db_getAccount(identifier)
    local p = Promise.new()
    -- Simulate 20ms database latency
    Citizen.SetTimeout(20, function()
        p:resolve(_db.accounts[identifier])
    end)
    return p
end

local function db_saveAccount(identifier, data)
    local p = Promise.new()
    Citizen.SetTimeout(10, function()
        _db.accounts[identifier] = data
        p:resolve(true)
    end)
    return p
end

-- ---------------------------------------------------------------------------
-- Player session tracking
-- ---------------------------------------------------------------------------
local sessions = {}  -- [src] = { identifier, name, account }

-- ---------------------------------------------------------------------------
-- Lifecycle: resource start
-- ---------------------------------------------------------------------------
AddEventHandler("onResourceStart", function(res)
    if res ~= resourceName then return end
    print("Player Manager initialised. Accounts loaded:", (function()
        local n = 0
        for _ in pairs(_db.accounts) do n = n + 1 end
        return n
    end)())
end)

-- ---------------------------------------------------------------------------
-- playerConnecting: load account data, populate statebag
-- ---------------------------------------------------------------------------
AddEventHandler("playerConnecting", function(name, setKick, deferrals)
    local src = source

    -- Use deferrals to hold the connection while we load data
    deferrals.defer()
    deferrals.update("Loading your account...")

    CreateThread(function()
        -- Build a stub identifier (real servers use GetPlayerIdentifier)
        local identifier = "steam:" .. string.format("%05d", src)

        local account = Citizen.Await(db_getAccount(identifier))

        if not account then
            -- New player: create account
            account = { name = name, cash = 1000, level = 1 }
            Citizen.Await(db_saveAccount(identifier, account))
            print(string.format("[PM] New player: %s (%s)", name, identifier))
        else
            print(string.format("[PM] Returning player: %s (%s) — Level %d",
                name, identifier, account.level))
        end

        -- Store session
        sessions[src] = { identifier = identifier, name = name, account = account }

        -- Populate statebag so other resources can read player data
        Player(src).state.playerName   = name
        Player(src).state.playerLevel  = account.level
        Player(src).state.playerCash   = account.cash
        Player(src).state.identifier   = identifier

        -- Also store in KVP as a cache
        SetResourceKvp("cache:" .. identifier, json.encode(account))

        deferrals.done()  -- allow connection to proceed
    end)
end)

-- ---------------------------------------------------------------------------
-- playerDropped: save account, clean up session
-- ---------------------------------------------------------------------------
AddEventHandler("playerDropped", function(reason)
    local src = source
    local session = sessions[src]
    if not session then return end

    print(string.format("[PM] Player dropped: %s — Reason: %s", session.name, reason or "unknown"))

    CreateThread(function()
        -- Save final account state
        local account = session.account
        account.cash  = Player(src).state.playerCash or account.cash
        account.level = Player(src).state.playerLevel or account.level
        Citizen.Await(db_saveAccount(session.identifier, account))
        print(string.format("[PM] Saved account for %s", session.name))
    end)

    sessions[src] = nil
end)

-- ---------------------------------------------------------------------------
-- Command: /cash — show player's current cash
-- ---------------------------------------------------------------------------
RegisterCommand("cash", function(src, args, raw)
    local session = sessions[src]
    if not session then
        print("[PM] /cash: unknown player source " .. src)
        return
    end
    local cash = Player(src).state.playerCash or 0
    print(string.format("[PM] Player %s has $%d", session.name, cash))
    TriggerClientEvent("chat:addMessage", src, {
        args = { "^2Cash", string.format("You have $%d", cash) }
    })
end, false)

-- ---------------------------------------------------------------------------
-- Command: /givecash <target> <amount>
-- ---------------------------------------------------------------------------
RegisterCommand("givecash", function(src, args, raw)
    local targetSrc = tonumber(args[1])
    local amount    = tonumber(args[2])

    if not targetSrc or not amount or amount <= 0 then
        print("[PM] Usage: /givecash <playerSrc> <amount>")
        return
    end

    local giver    = sessions[src]
    local receiver = sessions[targetSrc]

    if not giver or not receiver then
        print("[PM] /givecash: invalid source or target")
        return
    end

    local giverCash = Player(src).state.playerCash or 0
    if giverCash < amount then
        print(string.format("[PM] %s doesn't have enough cash", giver.name))
        return
    end

    -- Deduct and credit
    Player(src).state.playerCash       = giverCash - amount
    Player(targetSrc).state.playerCash = (Player(targetSrc).state.playerCash or 0) + amount

    -- Also update the in-memory account object
    giver.account.cash    = Player(src).state.playerCash
    receiver.account.cash = Player(targetSrc).state.playerCash

    print(string.format("[PM] %s gave $%d to %s", giver.name, amount, receiver.name))
end, false)

-- ---------------------------------------------------------------------------
-- Exports: allow other resources to query player data
-- ---------------------------------------------------------------------------
exports(resourceName, {
    getPlayerSession = function(src)
        return sessions[src]
    end,

    getPlayerCash = function(src)
        return Player(src).state.playerCash or 0
    end,

    setPlayerCash = function(src, amount)
        Player(src).state.playerCash = amount
        if sessions[src] then
            sessions[src].account.cash = amount
        end
    end,

    getPlayerLevel = function(src)
        return Player(src).state.playerLevel or 1
    end,

    isPlayerLoaded = function(src)
        return sessions[src] ~= nil
    end,
})

-- ---------------------------------------------------------------------------
-- Background: periodic session heartbeat
-- ---------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(5000)  -- every 5 seconds
        local count = 0
        for src, session in pairs(sessions) do
            count = count + 1
            -- Auto-save each active session
            CreateThread(function()
                local account = session.account
                account.cash  = Player(src).state.playerCash or account.cash
                Citizen.Await(db_saveAccount(session.identifier, account))
            end)
        end
        if count > 0 then
            print(string.format("[PM] Heartbeat: %d active sessions auto-saved", count))
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Simulation: run a demo scenario in standalone mode
-- ---------------------------------------------------------------------------
CreateThread(function()
    print("\n--- Simulating player connections ---")

    -- Simulate 3 players connecting
    for i = 1, 3 do
        local src  = i
        local name = ({ "Alice", "Bob", "Charlie" })[i]
        __cfx_addMockPlayer(src, name, "steam:" .. string.format("%05d", src))
        __cfx_internal_triggerEvent("playerConnecting", src, name,
            function() end,    -- setKick
            { ["defer"] = function() end,   -- deferrals mock
              update    = function(msg) print("[PM] Deferral:", msg) end,
              done      = function() print("[PM] Connection allowed for", name) end,
            }
        )
    end

    -- Wait for async loads
    Wait(200)

    -- Show state
    print("\n--- Player state bags ---")
    for i = 1, 3 do
        print(string.format("  Player %d: name=%s level=%s cash=%s",
            i,
            tostring(Player(i).state.playerName),
            tostring(Player(i).state.playerLevel),
            tostring(Player(i).state.playerCash)
        ))
    end

    -- Test /cash command
    print("\n--- Simulating /cash command ---")
    __cfx_runCommand("cash", 1, {}, "cash")

    -- Test /givecash command
    print("\n--- Simulating /givecash 2 500 ---")
    __cfx_runCommand("givecash", 1, { "2", "500" }, "givecash 2 500")

    Wait(100)

    -- Verify export works from "another resource"
    print("\n--- Testing exports ---")
    local cash1 = exports[resourceName].getPlayerCash(1)
    local cash2 = exports[resourceName].getPlayerCash(2)
    print(string.format("  Player 1 cash (via export): $%d", cash1))
    print(string.format("  Player 2 cash (via export): $%d", cash2))

    -- Simulate disconnect
    print("\n--- Simulating player 2 disconnect ---")
    __cfx_internal_triggerEvent("playerDropped", 2, "Quit")
    Wait(100)

    print("\n--- Player Manager demo complete ---")
end)
