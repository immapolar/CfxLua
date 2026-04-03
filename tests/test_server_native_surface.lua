-- =============================================================================
-- test_server_native_surface.lua
-- =============================================================================

T.suite("Server Native Surface")

local testPath = arg and arg[0] or "tests/test_server_native_surface.lua"
local testDir = testPath:match("(.+[\\/])") or "tests/"
local stubsPath = testDir .. "../runtime/stubs_fivem_server.lua"

local fh = io.open(stubsPath, "r")
if not fh then
    T.skip("runtime/stubs_fivem_server.lua not found")
    return
end

local content = fh:read("*a")
fh:close()

local names = {}
for fnName in content:gmatch("_G%['([A-Za-z_][A-Za-z0-9_]*)'%]%s*=") do
    names[#names + 1] = fnName
end

T.ok(#names >= 200, "Generated native surface has at least 200 functions")

local missing = 0
for _, fnName in ipairs(names) do
    if type(_G[fnName]) ~= "function" then
        missing = missing + 1
    end
end

T.eq(missing, 0, "All generated server native globals are callable functions")

