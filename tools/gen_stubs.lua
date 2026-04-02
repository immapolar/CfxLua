-- =============================================================================
-- tools/gen_stubs.lua  —  CfxLua Standalone Runtime
-- =============================================================================
-- Usage:
--   lua gen_stubs.lua <path-to-cfxlua-vscode/> [--side server|client|shared]
--
-- Parses all *.lua annotation files from the cfxlua-vscode extension and
-- emits a stubs.lua file containing typed no-op stubs for every native and
-- Citizen global found.
--
-- The cfxlua-vscode extension lives at:
--   https://github.com/overextended/cfxlua-vscode
-- Clone it and pass the path as the first argument.
--
-- Output is written to stdout; redirect to runtime/stubs.lua:
--   lua tools/gen_stubs.lua ../cfxlua-vscode/ > runtime/stubs.lua
-- =============================================================================

local side = "server"
local vscode_path = arg[1]

if not vscode_path then
    io.stderr:write("Usage: lua gen_stubs.lua <cfxlua-vscode-path> [server|client|shared]\n")
    os.exit(1)
end

for i = 2, #arg do
    if arg[i] == "server" or arg[i] == "client" or arg[i] == "shared" then
        side = arg[i]
    end
end

-- Normalise path (ensure trailing slash)
if vscode_path:sub(-1) ~= "/" then vscode_path = vscode_path .. "/" end

-- ---------------------------------------------------------------------------
-- File discovery: find all .lua files under the vscode extension's library
-- directories that match our target side.
-- cfxlua-vscode structure (as of 2024):
--   library/
--     shared/     — functions available on both sides
--     server/     — server-only natives
--     client/     — client-only natives
-- ---------------------------------------------------------------------------
local function listFiles(dir)
    local files = {}
    -- Use find via os.execute piped through a temp file
    local tmpfile = os.tmpname()
    os.execute(string.format('find "%s" -name "*.lua" 2>/dev/null > "%s"', dir, tmpfile))
    local f = io.open(tmpfile, "r")
    if f then
        for line in f:lines() do
            files[#files + 1] = line
        end
        f:close()
    end
    os.remove(tmpfile)
    return files
end

local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

-- ---------------------------------------------------------------------------
-- Parser: extract function signatures from LLS annotation format
-- Pattern: ---@type fun(arg: type, ...): returntype
--          function FunctionName(...) end
--
-- We look for the common patterns:
--   1. `function Name(args)` declarations
--   2. `---@param` blocks followed by function declarations
--   3. `Name = function(args)` assignments
-- ---------------------------------------------------------------------------

local stubs = {}       -- { [name] = { params = {...}, returns = {...}, source = file } }
local seen  = {}       -- dedup

local function extractFunctions(content, filename)
    -- Pattern 1: top-level function declarations
    -- function FunctionName(param1, param2, ...)
    for name, params in content:gmatch("\nfunction%s+([A-Z][%w_%.]+)%s*%(([^)]*)%)") do
        if not seen[name] then
            seen[name] = true
            local paramList = {}
            for p in params:gmatch("[%w_%.]+") do
                paramList[#paramList + 1] = p
            end
            stubs[#stubs + 1] = {
                name    = name,
                params  = paramList,
                source  = filename:match("[^/]+$") or filename,
            }
        end
    end

    -- Pattern 2: assignments `Name = function(...)` at global scope
    for name, params in content:gmatch("\n([A-Z][%w_%.]+)%s*=%s*function%s*%(([^)]*)%)") do
        if not seen[name] then
            seen[name] = true
            local paramList = {}
            for p in params:gmatch("[%w_%.]+") do
                paramList[#paramList + 1] = p
            end
            stubs[#stubs + 1] = {
                name    = name,
                params  = paramList,
                source  = filename:match("[^/]+$") or filename,
            }
        end
    end
end

-- ---------------------------------------------------------------------------
-- Discover and parse files
-- ---------------------------------------------------------------------------
local dirs = { vscode_path .. "library/shared/" }
if side == "server" or side == "server" then
    dirs[#dirs + 1] = vscode_path .. "library/server/"
end
if side == "client" then
    dirs[#dirs + 1] = vscode_path .. "library/client/"
end

local totalFiles = 0
for _, dir in ipairs(dirs) do
    local files = listFiles(dir)
    for _, f in ipairs(files) do
        local content = readFile(f)
        if content then
            extractFunctions(content, f)
            totalFiles = totalFiles + 1
        end
    end
end

io.stderr:write(string.format(
    "[gen_stubs] Scanned %d files, found %d unique function names\n",
    totalFiles, #stubs
))

-- ---------------------------------------------------------------------------
-- Emit stubs.lua
-- ---------------------------------------------------------------------------
io.write("-- AUTO-GENERATED by tools/gen_stubs.lua — DO NOT EDIT\n")
io.write("-- Source: cfxlua-vscode library annotations\n")
io.write("-- Side: " .. side .. "\n")
io.write("-- Run: lua tools/gen_stubs.lua <cfxlua-vscode-path> > runtime/stubs.lua\n\n")

io.write("-- SHIM: All stubs below are no-ops that return nil.\n")
io.write("-- They exist so scripts that call natives don't crash at load time.\n")
io.write("-- Replace individual stubs with test doubles in your test files.\n\n")

-- Sort for deterministic output
table.sort(stubs, function(a, b) return a.name < b.name end)

for _, stub in ipairs(stubs) do
    -- Skip if it already looks like it was defined by our runtime
    local skip = {
        -- scheduler
        CreateThread=1, Wait=1, HasPendingThreads=1, ScheduleResourceTick=1,
        -- events
        AddEventHandler=1, RemoveEventHandler=1, TriggerEvent=1,
        TriggerNetEvent=1, TriggerServerEvent=1, TriggerLatentNetEvent=1,
        TriggerLatentServerEvent=1,
        -- citizen
        GetCurrentResourceName=1, GetInvokingResource=1,
        GetResourceKvpString=1, GetResourceKvpInt=1, GetResourceKvpFloat=1,
        SetResourceKvp=1, SetResourceKvpInt=1, SetResourceKvpFloat=1,
        DeleteResourceKvp=1, StartFindKvp=1,
        GetConvar=1, GetConvarInt=1, SetConvar=1,
        PerformHttpRequest=1, Player=1, Entity=1,
    }
    if not skip[stub.name] then
        local paramStr = #stub.params > 0 and table.concat(stub.params, ", ") or ""
        io.write(string.format(
            "-- from: %s\n_G['%s'] = _G['%s'] or function(%s) end\n",
            stub.source, stub.name, stub.name, paramStr
        ))
    end
end

io.write("\n-- End of generated stubs\n")
