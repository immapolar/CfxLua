-- =============================================================================
-- fxserver.lua  —  CfxLua FXServer Internal Simulation Layer
-- =============================================================================
-- Provides deterministic in-process simulation for key FXServer internals:
--   - player/session registry
--   - entity registry and network IDs
--   - routing buckets
--   - state bags + change handlers
--   - server convars (runtime-local)
-- =============================================================================

local _players = {}        -- [src:number] = player
local _entities = {}       -- [entity:number] = entity
local _nextEntity = 1000
local _convars = {}        -- [name] = string

local _stateBags = {}      -- [bagName] = { [key] = value }
local _bagHandlers = {}    -- [cookie] = { keyFilter, bagFilter, cb }
local _nextBagCookie = 1

-- Standalone interpreter models server-side runtime semantics.
function IsDuplicityVersion()
    return true
end

local function _toNum(v)
    local n = tonumber(v)
    if n then
        return math.floor(n)
    end
    return nil
end

local function _sortedPlayerIds()
    local ids = {}
    for src in pairs(_players) do
        ids[#ids + 1] = src
    end
    table.sort(ids)
    return ids
end

local function _ensureBag(name)
    if not _stateBags[name] then
        _stateBags[name] = {}
    end
    return _stateBags[name]
end

local function _dispatchBagHandlers(bagName, key, value, replicated)
    for _, h in pairs(_bagHandlers) do
        local keyOk = (h.keyFilter == nil) or (h.keyFilter == key)
        local bagOk = (h.bagFilter == nil) or (h.bagFilter == bagName)
        if keyOk and bagOk then
            local ok, err = xpcall(h.cb, debug.traceback, bagName, key, value, nil, replicated and true or false)
            if not ok then
                print("[cfxlua] state bag handler error: " .. tostring(err))
            end
        end
    end
end

local function _setBagValue(bagName, key, value, replicated)
    local bag = _ensureBag(bagName)
    bag[key] = value
    _dispatchBagHandlers(bagName, key, value, replicated)
end

local function _getBagValue(bagName, key)
    local bag = _stateBags[bagName]
    return bag and bag[key] or nil
end

local function _makeBagProxy(bagName)
    _ensureBag(bagName)
    return setmetatable({}, {
        __index = function(_, key)
            return _getBagValue(bagName, key)
        end,
        __newindex = function(_, key, value)
            _setBagValue(bagName, key, value, true)
        end,
        __tostring = function()
            return string.format("StateBag(%s)", bagName)
        end
    })
end

local function _ensurePlayer(src)
    if not _players[src] then
        _players[src] = {
            src = src,
            name = ("Player%d"):format(src),
            endpoint = "127.0.0.1:30120",
            ping = 0,
            identifiers = {
                ("steam:0000%d"):format(src),
                ("license:abc%d"):format(src),
                ("ip:127.0.0.1"):format(src),
            },
            tokens = {
                ("token_%d_0"):format(src),
                ("token_%d_1"):format(src),
                ("token_%d_2"):format(src),
            },
            bucket = 0,
            ped = 0,
            state = _makeBagProxy("player:" .. tostring(src)),
        }
    end
    return _players[src]
end

local function _entityTypeNum(kind)
    if kind == "ped" then
        return 1
    elseif kind == "vehicle" then
        return 2
    elseif kind == "object" then
        return 3
    end
    return 0
end

local function _createEntity(kind, x, y, z, heading, model)
    local id = _nextEntity
    _nextEntity = _nextEntity + 1
    _entities[id] = {
        id = id,
        kind = kind,
        type = _entityTypeNum(kind),
        x = x or 0.0,
        y = y or 0.0,
        z = z or 0.0,
        heading = heading or 0.0,
        model = model or 0,
        bucket = 0,
        owner = 0,
        state = _makeBagProxy("entity:" .. tostring(id)),
    }
    return id
end

local function _createEntityWithId(id, kind, x, y, z, heading, model)
    if id >= _nextEntity then
        _nextEntity = id + 1
    end
    _entities[id] = {
        id = id,
        kind = kind,
        type = _entityTypeNum(kind),
        x = x or 0.0,
        y = y or 0.0,
        z = z or 0.0,
        heading = heading or 0.0,
        model = model or 0,
        bucket = 0,
        owner = 0,
        state = _makeBagProxy("entity:" .. tostring(id)),
    }
    return id
end

local function _getEntity(entity)
    return _entities[_toNum(entity) or -1]
end

-- ---------------------------------------------------------------------------
-- FXServer simulation helpers (explicitly non-native)
-- ---------------------------------------------------------------------------
function __cfx_connectPlayer(src, opts)
    local nsrc = _toNum(src)
    if not nsrc then
        error("__cfx_connectPlayer: src must be numeric", 2)
    end

    local p = _ensurePlayer(nsrc)
    opts = opts or {}
    if opts.name then p.name = tostring(opts.name) end
    if opts.endpoint then p.endpoint = tostring(opts.endpoint) end
    if opts.ping then p.ping = _toNum(opts.ping) or p.ping end
    if type(opts.identifiers) == "table" then p.identifiers = opts.identifiers end
    if type(opts.tokens) == "table" then p.tokens = opts.tokens end
    if opts.bucket then p.bucket = _toNum(opts.bucket) or 0 end

    __cfx_internal_triggerEvent("playerConnecting", nsrc, p.name, function() end, {})
    __cfx_internal_triggerEvent("playerJoining", nsrc)
    return true
end

function __cfx_disconnectPlayer(src, reason)
    local nsrc = _toNum(src)
    if not nsrc or not _players[nsrc] then
        return false
    end

    __cfx_internal_triggerEvent("playerDropped", nsrc, reason or "Disconnected")
    _players[nsrc] = nil
    return true
end

function __cfx_resetServerSim()
    for k in pairs(_players) do _players[k] = nil end
    for k in pairs(_entities) do _entities[k] = nil end
    for k in pairs(_convars) do _convars[k] = nil end
    for k in pairs(_stateBags) do _stateBags[k] = nil end
    for k in pairs(_bagHandlers) do _bagHandlers[k] = nil end
    _nextEntity = 1000
    _nextBagCookie = 1
end

-- ---------------------------------------------------------------------------
-- Player natives
-- ---------------------------------------------------------------------------
function GetPlayers()
    local out = {}
    for _, src in ipairs(_sortedPlayerIds()) do
        out[#out + 1] = tostring(src)
    end
    return out
end

function GetNumPlayers()
    return #_sortedPlayerIds()
end

function GetNumPlayerIndices()
    return #_sortedPlayerIds()
end

function GetPlayerFromIndex(index)
    local idx = (_toNum(index) or 0) + 1
    local ids = _sortedPlayerIds()
    local src = ids[idx]
    return src and tostring(src) or nil
end

function DoesPlayerExist(playerSrc)
    return _players[_toNum(playerSrc) or -1] ~= nil
end

function GetPlayerName(playerSrc)
    local p = _players[_toNum(playerSrc) or -1]
    return p and p.name or "Unknown"
end

function GetPlayerPing(playerSrc)
    local p = _players[_toNum(playerSrc) or -1]
    return p and p.ping or 0
end

function GetPlayerEndpoint(playerSrc)
    local p = _players[_toNum(playerSrc) or -1]
    return p and p.endpoint or "127.0.0.1:30120"
end

function GetNumPlayerIdentifiers(playerSrc)
    local p = _players[_toNum(playerSrc) or -1]
    return p and #p.identifiers or 0
end

function GetPlayerIdentifier(playerSrc, index)
    local p = _players[_toNum(playerSrc) or -1]
    if not p then return nil end

    if type(index) == "string" then
        return GetPlayerIdentifierByType(playerSrc, index)
    end

    local i = (_toNum(index) or 0) + 1
    return p.identifiers[i]
end

function GetPlayerIdentifierByType(playerSrc, identType)
    local p = _players[_toNum(playerSrc) or -1]
    if not p then return nil end

    local prefix = tostring(identType) .. ":"
    for _, ident in ipairs(p.identifiers) do
        if ident:sub(1, #prefix) == prefix then
            return ident
        end
    end
    return nil
end

function GetNumPlayerTokens(playerSrc)
    local p = _players[_toNum(playerSrc) or -1]
    return p and #p.tokens or 0
end

function GetPlayerToken(playerSrc, index)
    local p = _players[_toNum(playerSrc) or -1]
    if not p then return nil end
    local i = (_toNum(index) or 0) + 1
    return p.tokens[i]
end

function GetHostId()
    return 0
end

function DropPlayer(playerSrc, reason)
    return __cfx_disconnectPlayer(playerSrc, reason or "Dropped by server")
end

function GetPlayerPed(playerSrc)
    local p = _players[_toNum(playerSrc) or -1]
    return p and p.ped or 0
end

function SetPlayerPed(playerSrc, ped)
    local p = _ensurePlayer(_toNum(playerSrc) or 0)
    p.ped = _toNum(ped) or 0
end

-- ---------------------------------------------------------------------------
-- Entity + OneSync-like registry
-- ---------------------------------------------------------------------------
function CreatePed(pedType, modelHash, x, y, z, heading, isNetwork, bScriptHostPed)
    return _createEntity("ped", x, y, z, heading, modelHash)
end

function CreateObjectNoOffset(modelHash, x, y, z, isNetwork, netMissionEntity, doorFlag)
    return _createEntity("object", x, y, z, 0.0, modelHash)
end

function CreateAutomobile(modelHash, x, y, z, heading)
    return _createEntity("vehicle", x, y, z, heading, modelHash)
end

function CreateVehicleServerSetter(modelHash, vehicleType, x, y, z, heading)
    return _createEntity("vehicle", x, y, z, heading, modelHash)
end

function DeleteEntity(entity)
    local n = _toNum(entity)
    if n and _entities[n] then
        _entities[n] = nil
    end
end

function DoesEntityExist(entity)
    return _getEntity(entity) ~= nil
end

function GetEntityType(entity)
    local e = _getEntity(entity)
    return e and e.type or 0
end

function GetEntityCoords(entity)
    local e = _getEntity(entity)
    return e and e.x or 0.0, e and e.y or 0.0, e and e.z or 0.0
end

function SetEntityCoords(entity, x, y, z)
    local e = _getEntity(entity)
    if e then
        e.x, e.y, e.z = x or e.x, y or e.y, z or e.z
    end
end

function GetEntityHeading(entity)
    local e = _getEntity(entity)
    return e and e.heading or 0.0
end

function SetEntityHeading(entity, heading)
    local e = _getEntity(entity)
    if e then
        e.heading = heading or e.heading
    end
end

function NetworkGetNetworkIdFromEntity(entity)
    local e = _getEntity(entity)
    return e and e.id or 0
end

function NetworkGetEntityFromNetworkId(netId)
    local e = _getEntity(netId)
    return e and e.id or 0
end

function GetAllVehicles()
    local out = {}
    for id, e in pairs(_entities) do
        if e.kind == "vehicle" then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end

function GetAllPeds()
    local out = {}
    for id, e in pairs(_entities) do
        if e.kind == "ped" then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end

function GetAllObjects()
    local out = {}
    for id, e in pairs(_entities) do
        if e.kind == "object" then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end

function GetGamePool(poolName)
    if poolName == "CVehicle" then return GetAllVehicles() end
    if poolName == "CPed" then return GetAllPeds() end
    if poolName == "CObject" then return GetAllObjects() end
    return {}
end

-- ---------------------------------------------------------------------------
-- Routing buckets
-- ---------------------------------------------------------------------------
function GetPlayerRoutingBucket(playerSrc)
    local p = _players[_toNum(playerSrc) or -1]
    return p and p.bucket or 0
end

function SetPlayerRoutingBucket(playerSrc, bucket)
    local p = _ensurePlayer(_toNum(playerSrc) or 0)
    p.bucket = _toNum(bucket) or 0
end

function GetEntityRoutingBucket(entity)
    local e = _getEntity(entity)
    return e and e.bucket or 0
end

function SetEntityRoutingBucket(entity, bucket)
    local e = _getEntity(entity)
    if e then
        e.bucket = _toNum(bucket) or 0
    end
end

-- ---------------------------------------------------------------------------
-- Convars
-- ---------------------------------------------------------------------------
function SetConvar(name, value)
    _convars[tostring(name)] = tostring(value)
end

function SetConvarReplicated(name, value)
    SetConvar(name, value)
end

function SetConvarServerInfo(name, value)
    SetConvar(name, value)
end

function GetConvar(name, default)
    local key = tostring(name)
    local v = _convars[key]
    if v ~= nil then return v end
    return os.getenv(key) or default
end

function GetConvarInt(name, default)
    local v = GetConvar(name, nil)
    if v == nil then return default end
    local n = tonumber(v)
    if not n then return default end
    return math.floor(n)
end

-- ---------------------------------------------------------------------------
-- State bags + handlers
-- ---------------------------------------------------------------------------
GlobalState = _makeBagProxy("__global__")

local _playerHandles = {}
function Player(netId)
    local src = _toNum(netId) or 0
    local p = _ensurePlayer(src)
    if not _playerHandles[src] then
        _playerHandles[src] = { state = p.state }
    end
    return _playerHandles[src]
end

local _entityHandles = {}
function Entity(entityId)
    local id = _toNum(entityId) or 0
    if not _entities[id] then
        _createEntityWithId(id, "object", 0, 0, 0, 0, 0)
    end
    local e = _getEntity(id)
    if not _entityHandles[id] then
        _entityHandles[id] = { state = e.state }
    end
    return _entityHandles[id]
end

function AddStateBagChangeHandler(keyFilter, bagFilter, handler)
    local cookie = _nextBagCookie
    _nextBagCookie = _nextBagCookie + 1
    _bagHandlers[cookie] = {
        keyFilter = keyFilter,
        bagFilter = bagFilter,
        cb = handler,
    }
    return cookie
end

function RemoveStateBagChangeHandler(cookie)
    if _bagHandlers[cookie] then
        _bagHandlers[cookie] = nil
        return true
    end
    return false
end

function GetEntityFromStateBagName(bagName)
    local id = tostring(bagName):match("^entity:(%d+)$")
    return id and tonumber(id) or 0
end

function GetPlayerFromStateBagName(bagName)
    local id = tostring(bagName):match("^player:(%d+)$")
    return id and tostring(id) or nil
end

-- ---------------------------------------------------------------------------
-- HTTP runtime internals (backend natives for PerformHttpRequest frontend)
-- ---------------------------------------------------------------------------
local _httpToken = 1
local _isWindows = (package.config:sub(1, 1) == "\\") or (os.getenv("OS") == "Windows_NT")

local function _fileExists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function _tempPath(ext)
    ext = ext or ".tmp"
    if _isWindows then
        local base = os.getenv("TEMP") or os.getenv("TMP") or "."
        local seed = tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
        return base .. "\\cfxlua_" .. seed .. ext
    end

    local p = os.tmpname()
    if ext and ext ~= "" and not p:match("%.[^/\\]+$") then
        p = p .. ext
    end
    return p
end

local function _commandExists(cmd)
    local probe
    if _isWindows then
        probe = io.popen(('cmd /c "where %s >NUL 2>NUL && echo 1 || echo 0"'):format(cmd), "r")
    else
        probe = io.popen(('command -v %s >/dev/null 2>&1; echo $?'):format(cmd), "r")
    end
    if not probe then return false end
    local out = probe:read("*l")
    probe:close()
    if _isWindows then
        return out == "1"
    end
    return tonumber(out) == 0
end

local function _qPosix(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function _qWin(s)
    return '"' .. tostring(s):gsub('"', '""') .. '"'
end

local function _parseHeaders(path)
    local headers = {}
    local f = io.open(path, "r")
    if not f then return headers end
    for line in f:lines() do
        local k, v = line:match("^([^:]+):%s*(.*)$")
        if k and v then
            headers[k:lower()] = v
        end
    end
    f:close()
    return headers
end

local function _readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local c = f:read("*a")
    f:close()
    return c
end

local function _psQuote(s)
    return "'" .. tostring(s):gsub("'", "''") .. "'"
end

local function _doWindowsHttpRequest(req)
    local psExe = (os.getenv("SystemRoot") or "C:\\Windows") .. "\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"
    if not _fileExists(psExe) then
        return 0, nil, {}, "standalone: powershell not available"
    end

    local bodyFile = _tempPath(".body")
    local headFile = _tempPath(".head")
    local scriptFile = _tempPath(".ps1")

    local lines = {
        "$ErrorActionPreference = 'Stop'",
        "$ProgressPreference = 'SilentlyContinue'",
        "$method = " .. _psQuote(req.method or "GET"),
        "$url = " .. _psQuote(req.url or ""),
        "$bodyPath = " .. _psQuote(bodyFile),
        "$headPath = " .. _psQuote(headFile),
        "$headers = @{}",
    }

    if type(req.headers) == "table" then
        for k, v in pairs(req.headers) do
            lines[#lines + 1] = "$headers[" .. _psQuote(tostring(k)) .. "] = " .. _psQuote(tostring(v))
        end
    end

    local timeout = tonumber(req.timeout) or 30
    local maxRedirect = (req.followLocation == false) and 0 or 10
    local body = req.data and tostring(req.data) or ""

    lines[#lines + 1] = "$bodyData = " .. _psQuote(body)
    lines[#lines + 1] = "$params = @{ Method = $method; Uri = $url; Headers = $headers; TimeoutSec = " .. tostring(timeout) .. "; MaximumRedirection = " .. tostring(maxRedirect) .. " }"
    lines[#lines + 1] = "if ($bodyData.Length -gt 0) { $params['Body'] = $bodyData }"
    lines[#lines + 1] = "$status = 0"
    lines[#lines + 1] = "$content = ''"
    lines[#lines + 1] = "try {"
    lines[#lines + 1] = "  $resp = Invoke-WebRequest @params -UseBasicParsing"
    lines[#lines + 1] = "  $status = [int]$resp.StatusCode"
    lines[#lines + 1] = "  $content = [string]$resp.Content"
    lines[#lines + 1] = "  $resp.Headers.GetEnumerator() | ForEach-Object { \"{0}: {1}\" -f $_.Key, $_.Value } | Set-Content -LiteralPath $headPath -Encoding UTF8"
    lines[#lines + 1] = "} catch {"
    lines[#lines + 1] = "  $exResp = $_.Exception.Response"
    lines[#lines + 1] = "  if ($exResp -ne $null) {"
    lines[#lines + 1] = "    try { $status = [int]$exResp.StatusCode.value__ } catch { $status = 0 }"
    lines[#lines + 1] = "    try {"
    lines[#lines + 1] = "      $sr = New-Object System.IO.StreamReader($exResp.GetResponseStream())"
    lines[#lines + 1] = "      $content = $sr.ReadToEnd()"
    lines[#lines + 1] = "      $sr.Close()"
    lines[#lines + 1] = "    } catch {}"
    lines[#lines + 1] = "    try { $exResp.Headers.GetEnumerator() | ForEach-Object { \"{0}: {1}\" -f $_.Key, $_.Value } | Set-Content -LiteralPath $headPath -Encoding UTF8 } catch {}"
    lines[#lines + 1] = "  } else {"
    lines[#lines + 1] = "    $status = 0"
    lines[#lines + 1] = "  }"
    lines[#lines + 1] = "}"
    lines[#lines + 1] = "Set-Content -LiteralPath $bodyPath -Value $content -NoNewline -Encoding UTF8"
    lines[#lines + 1] = "Write-Output $status"

    local sf = io.open(scriptFile, "w")
    if not sf then
        return 0, nil, {}, "standalone: failed to create temporary powershell script"
    end
    sf:write(table.concat(lines, "\r\n"))
    sf:close()

    local p = io.popen(_qWin(psExe) .. " -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " .. _qWin(scriptFile) .. " 2>NUL", "r")
    local statusRaw = p and p:read("*a") or ""
    if p then p:close() end
    os.remove(scriptFile)

    local status = tonumber((statusRaw or ""):match("(%d+)")) or 0
    local bodyOut = _readFile(bodyFile)
    local headersOut = _parseHeaders(headFile)
    os.remove(bodyFile)
    os.remove(headFile)

    if status == 0 then
        return 0, bodyOut, headersOut, "standalone: HTTP request failed"
    end
    return status, bodyOut, headersOut, nil
end

local function _doCurlRequest(req)
    if _isWindows then
        return _doWindowsHttpRequest(req)
    end

    if not _commandExists("curl") then
        return 0, nil, {}, "standalone: curl not available"
    end

    local quote = _isWindows and _qWin or _qPosix
    local bodyFile = os.tmpname()
    local headFile = os.tmpname()

    local cmd = {
        "curl -sS",
        "-X " .. quote(req.method or "GET"),
        "-D " .. quote(headFile),
        "-o " .. quote(bodyFile),
        "--max-time " .. tostring(tonumber(req.timeout) or 30),
    }

    if req.followLocation ~= false then
        cmd[#cmd + 1] = "-L"
    end

    if type(req.headers) == "table" then
        for k, v in pairs(req.headers) do
            cmd[#cmd + 1] = "-H " .. quote(tostring(k) .. ": " .. tostring(v))
        end
    end

    if req.data ~= nil and req.data ~= "" then
        cmd[#cmd + 1] = "--data-binary " .. quote(tostring(req.data))
    end

    cmd[#cmd + 1] = quote(req.url or "")
    if _isWindows then
        cmd[#cmd + 1] = "-w " .. quote("%%{http_code}")
    else
        cmd[#cmd + 1] = "-w " .. quote("%{http_code}")
    end

    local full = table.concat(cmd, " ")
    if _isWindows then
        full = full .. " 2>NUL"
    else
        full = full .. " 2>/dev/null"
    end

    local p = io.popen(full, "r")
    local statusRaw = p and p:read("*a") or ""
    if p then p:close() end

    local status = tonumber((statusRaw or ""):match("(%d%d%d)")) or 0
    local body = _readFile(bodyFile)
    local headers = _parseHeaders(headFile)
    os.remove(bodyFile)
    os.remove(headFile)

    if status == 0 then
        return 0, body, headers, "standalone: HTTP request failed"
    end
    return status, body, headers, nil
end

local function _dispatchHttpResponse(token, status, body, headers, err)
    __cfx_internal_triggerEvent("__cfx_internal:httpResponse", "", token, status, body, headers, err)
end

function PerformHttpRequestInternalEx(req)
    if type(req) ~= "table" then
        return -1
    end
    if type(req.url) ~= "string" or req.url == "" then
        return -1
    end

    local token = _httpToken
    _httpToken = _httpToken + 1

    Citizen.SetTimeout(0, function()
        local status, body, headers, err = _doCurlRequest(req)
        _dispatchHttpResponse(token, status, body, headers, err)
    end)

    return token
end

function PerformHttpRequestInternal(url, method, data, headers)
    return PerformHttpRequestInternalEx({
        url = url,
        method = method or "GET",
        data = data or "",
        headers = headers or {},
        followLocation = true,
    })
end

-- ---------------------------------------------------------------------------
-- Network event internals (simulated in-process)
-- ---------------------------------------------------------------------------
function TriggerClientEventInternal(eventName, playerId, payload, payloadLen)
    if playerId == -1 then
        for _, src in ipairs(_sortedPlayerIds()) do
            __cfx_internal_triggerNetEvent(eventName, src, payload)
        end
        return true
    end

    local src = _toNum(playerId)
    if src and _players[src] then
        __cfx_internal_triggerNetEvent(eventName, src, payload)
        return true
    end
    return false
end

function TriggerLatentClientEventInternal(eventName, playerId, payload, payloadLen, bps)
    return TriggerClientEventInternal(eventName, playerId, payload, payloadLen)
end

function TriggerClientEvent(eventName, playerId, ...)
    if playerId == -1 then
        for _, src in ipairs(_sortedPlayerIds()) do
            __cfx_internal_triggerNetEvent(eventName, src, ...)
        end
        return true
    end

    local src = _toNum(playerId)
    if src and _players[src] then
        __cfx_internal_triggerNetEvent(eventName, src, ...)
        return true
    end
    return false
end

function TriggerLatentClientEvent(eventName, playerId, bps, ...)
    return TriggerClientEvent(eventName, playerId, ...)
end
