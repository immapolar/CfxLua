-- =============================================================================
-- stubs.lua  —  CfxLua Standalone Runtime
-- =============================================================================
-- Pre-generated server-side native stubs. Every stub follows the contract:
--   - Exists so the function call doesn't produce a nil-call error
--   - Returns a sensible default (nil, false, 0, "" or {})
--   - Prints a [STUB] warning if the native is *expected* to produce
--     meaningful side effects (e.g. network operations, player kicks)
--
-- SHIM: Real FXServer resolves these from the native export tables built by
-- citizen-scripting-core's NativeHandler infrastructure. Each hash maps to
-- either a game-engine function (client) or a scripting runtime function
-- (server). Stubs are purely Lua-side no-ops.
--
-- Override individual stubs in your test file:
--   GetPlayerName = function(src) return "TestPlayer" end
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Player / Client management
-- ---------------------------------------------------------------------------

-- SHIM: Returns a table of current player source IDs (strings).
-- Real FXServer returns the networked player list.
local _mockPlayers = {}
function GetPlayers()
    local out = {}
    for k in pairs(_mockPlayers) do out[#out + 1] = tostring(k) end
    return out
end

-- Add/remove mock players (test helper, not a real native)
function __cfx_addMockPlayer(src, name, ident)
    _mockPlayers[src] = { name = name or ("Player" .. src), ident = ident or ("steam:0000" .. src) }
end
function __cfx_removeMockPlayer(src)
    _mockPlayers[src] = nil
end

function GetPlayerName(playerSrc)
    local p = _mockPlayers[tonumber(playerSrc)]
    return p and p.name or "Unknown"
end

function GetPlayerPing(playerSrc)
    return 0  -- SHIM: network ping; always 0 in standalone
end

function GetPlayerEndpoint(playerSrc)
    return "127.0.0.1:30120"  -- SHIM: fake IP
end

function GetPlayerIdentifier(playerSrc, identType)
    local p = _mockPlayers[tonumber(playerSrc)]
    if not p then return nil end
    identType = identType or "steam"
    if identType == "steam" then return p.ident end
    if identType == "license" then return "license:abc" .. tostring(playerSrc) end
    if identType == "ip" then return "ip:127.0.0.1" end
    return nil
end

function GetNumPlayerIdentifiers(playerSrc)
    return 3  -- steam, license, ip
end

function GetPlayerToken(playerSrc, index)
    return "token_" .. tostring(playerSrc) .. "_" .. tostring(index)
end

function IsPlayerAceAllowed(playerSrc, object)
    -- SHIM: ACE (Access Control Entries) always returns false in standalone.
    return false
end

function IsPrincipalAceAllowed(principal, object)
    return false
end

-- SHIM: Player ped tracking. Real FXServer queries GTA V server state.
local _playerPeds = {}
function GetPlayerPed(playerSrc)
    return _playerPeds[tonumber(playerSrc)] or 0
end
function SetPlayerPed(playerSrc, ped)  -- test helper
    _playerPeds[tonumber(playerSrc)] = ped
end

function GetPlayerGuid(playerSrc)
    return "guid:" .. tostring(playerSrc)
end

function GetNumPlayers()
    local n = 0
    for _ in pairs(_mockPlayers) do n = n + 1 end
    return n
end

function DropPlayer(playerSrc, reason)
    print(string.format("[cfxlua][STUB] DropPlayer(%s, '%s')", playerSrc, reason or ""))
    _mockPlayers[tonumber(playerSrc)] = nil
end

function TempBanPlayer(playerSrc, reason)
    print(string.format("[cfxlua][STUB] TempBanPlayer(%s, '%s')", playerSrc, reason or ""))
end

-- ---------------------------------------------------------------------------
-- Entity / Object management (server-side)
-- ---------------------------------------------------------------------------

local _entities  = {}
local _nextNetId = 1000

function DoesEntityExist(entity)
    return _entities[entity] ~= nil
end

function GetEntityType(entity)
    local e = _entities[entity]
    return e and e.type or 0
end

function GetEntityCoords(entity)
    local e = _entities[entity]
    return e and e.x or 0.0, e and e.y or 0.0, e and e.z or 0.0
end

function SetEntityCoords(entity, x, y, z)
    if _entities[entity] then
        _entities[entity].x = x
        _entities[entity].y = y
        _entities[entity].z = z
    end
end

function GetEntityHeading(entity)
    return _entities[entity] and _entities[entity].heading or 0.0
end

function SetEntityHeading(entity, heading)
    if _entities[entity] then _entities[entity].heading = heading end
end

function NetworkGetNetworkIdFromEntity(entity)
    return _entities[entity] and _entities[entity].netId or 0
end

function NetworkGetEntityFromNetworkId(netId)
    for id, e in pairs(_entities) do
        if e.netId == netId then return id end
    end
    return 0
end

-- Test helper: create a stub entity
function __cfx_createMockEntity(type_, x, y, z)
    local id = _nextNetId
    _nextNetId = _nextNetId + 1
    _entities[id] = { type = type_ or 1, x = x or 0, y = y or 0, z = z or 0,
                      heading = 0, netId = id }
    return id
end

-- ---------------------------------------------------------------------------
-- Resource management
-- ---------------------------------------------------------------------------

function GetResourceState(resourceName)
    -- SHIM: always "started" for the running resource, "missing" for others
    if resourceName == GetCurrentResourceName() then return "started" end
    return "missing"
end

function StartResource(resourceName)
    print("[cfxlua][STUB] StartResource('" .. resourceName .. "')")
    return false
end

function StopResource(resourceName)
    print("[cfxlua][STUB] StopResource('" .. resourceName .. "')")
    return false
end

function GetResourcePath(resourceName)
    return "./" .. resourceName
end

function GetNumResources()
    return 1
end

function GetResourceByFindIndex(index)
    return index == 0 and GetCurrentResourceName() or nil
end

function GetResourceMetadata(resource, field, index)
    return nil
end

-- ---------------------------------------------------------------------------
-- Server utility natives
-- ---------------------------------------------------------------------------

function GetServerName()
    return "CfxLua Standalone"
end

function GetMaxPlayers()
    return 32
end

function GetGamePool(poolName)
    return {}
end

-- SHIM: ExecuteCommand dispatches to command handlers. No-op here.
function ExecuteCommand(command)
    print("[cfxlua][STUB] ExecuteCommand('" .. command .. "')")
end

function RegisterCommand(name, handler, restricted)
    -- SHIM: FXServer registers commands in the global command registry.
    -- We store them locally and allow manual dispatch via __cfx_runCommand.
    if not _G.__cfx_commands then _G.__cfx_commands = {} end
    _G.__cfx_commands[name] = { handler = handler, restricted = restricted or false }
end

function __cfx_runCommand(name, source, args, rawCommand)
    local cmds = _G.__cfx_commands or {}
    local cmd = cmds[name]
    if cmd then
        cmd.handler(source or 0, args or {}, rawCommand or name)
        return true
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Network / sync
-- ---------------------------------------------------------------------------

function GetHostId()
    return 0
end

function GetPlayerRoutingBucket(playerSrc)
    return 0
end

function SetPlayerRoutingBucket(playerSrc, bucket)
end

function GetEntityRoutingBucket(entity)
    return 0
end

function SetEntityRoutingBucket(entity, bucket)
end

-- ---------------------------------------------------------------------------
-- Chat (ox_lib / chat resource integration)
-- ---------------------------------------------------------------------------

function TriggerClientEvent(name, target, ...)
    print(string.format("[cfxlua][STUB] TriggerClientEvent('%s', %s)", name, tostring(target)))
    -- SHIM: fire locally so scripts that listen for their own events work
    TriggerEvent(name, ...)
end

function TriggerLatentClientEvent(name, target, bps, ...)
    TriggerClientEvent(name, target, ...)
end

-- ---------------------------------------------------------------------------
-- Scheduling / timing natives not covered by scheduler.lua
-- ---------------------------------------------------------------------------

-- SHIM: FXServer's Citizen.SetInterval is a repeating timer.
function Citizen.SetInterval(ms, fn)
    local handle = { _cancelled = false }
    CreateThread(function()
        while true do
            Wait(ms)
            if handle._cancelled then
                break
            end
            local ok, err = xpcall(fn, debug.traceback)
            if not ok then
                print("[cfxlua] SetInterval callback error: " .. tostring(err))
                break
            end
        end
    end)
    return handle
end

function Citizen.ClearInterval(handle)
    if type(handle) ~= "table" then
        return false
    end
    handle._cancelled = true
    return true
end

-- ---------------------------------------------------------------------------
-- Weapon / vehicle / blip (client-side stubs included for shared scripts)
-- ---------------------------------------------------------------------------
-- Most client-side natives are omitted; these are the ones that commonly
-- appear in shared or server-side scripts by mistake.

function AddBlipForCoord(x, y, z)          return 0 end
function SetBlipSprite(blip, sprite)       end
function SetBlipColour(blip, colour)       end
function SetBlipScale(blip, scale)         end
function BeginTextCommandSetBlipName(text) end
function EndTextCommandSetBlipName(blip)   end
function RemoveBlip(blip)                  end

-- ---------------------------------------------------------------------------
-- MySQL / oxmysql stubs (very common dependency)
-- SHIM: These are not FXServer builtins; they come from oxmysql resource.
-- Provided here because almost every ox_lib-based resource needs them.
-- ---------------------------------------------------------------------------
-- SHIM: oxmysql's MySQL.query, MySQL.single, etc. are callable tables that
-- also expose a .await method (synchronous variant via Citizen.Await).
-- We implement each as a table with __call so both syntaxes work:
--   MySQL.query(sql, params, cb)        -- async with callback
--   MySQL.query.await(sql, params)      -- sync (blocks thread)
local function _mysqlCallable(asyncFn, awaitDefault)
    local t = {}
    t.await = function(query, params)
        -- SHIM: In real oxmysql this blocks via Citizen.Await.
        -- Here we return the default value immediately.
        return awaitDefault
    end
    return setmetatable(t, { __call = function(_, ...) return asyncFn(...) end })
end

MySQL = MySQL or {}

MySQL.ready = function(fn)
    -- SHIM: fires the callback immediately since there's no real DB
    Citizen.SetTimeout(0, fn)
end

MySQL.query = _mysqlCallable(function(query, params, cb)
    if cb then Citizen.SetTimeout(0, function() cb({}) end) end
    local p = Promise.new()
    Citizen.SetTimeout(0, function() p:resolve({}) end)
    return p
end, {})

MySQL.single = _mysqlCallable(function(query, params, cb)
    if cb then Citizen.SetTimeout(0, function() cb(nil) end) end
    local p = Promise.new()
    Citizen.SetTimeout(0, function() p:resolve(nil) end)
    return p
end, nil)

MySQL.scalar = _mysqlCallable(function(query, params, cb)
    if cb then Citizen.SetTimeout(0, function() cb(nil) end) end
    local p = Promise.new()
    Citizen.SetTimeout(0, function() p:resolve(nil) end)
    return p
end, nil)

MySQL.insert = _mysqlCallable(function(query, params, cb)
    if cb then Citizen.SetTimeout(0, function() cb(0) end) end
    local p = Promise.new()
    Citizen.SetTimeout(0, function() p:resolve(0) end)
    return p
end, 0)

MySQL.update = _mysqlCallable(function(query, params, cb)
    if cb then Citizen.SetTimeout(0, function() cb(0) end) end
    local p = Promise.new()
    Citizen.SetTimeout(0, function() p:resolve(0) end)
    return p
end, 0)

-- ---------------------------------------------------------------------------
-- Misc commonly-used globals
-- ---------------------------------------------------------------------------

-- NOTE: Wait() is defined by scheduler.lua and must NOT be overridden here.
-- Calling Wait() outside a CreateThread body will raise an assertion error,
-- matching FXServer's behaviour (calling Wait outside a thread hangs the
-- resource on real FXServer; here we surface it as an error immediately).
-- SHIM: __cfx_scheduler_wait is saved by bootstrap.lua for introspection only.
