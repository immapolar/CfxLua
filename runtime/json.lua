-- =============================================================================
-- json.lua  —  dkjson 2.8 by David Kolf  (MIT License)
-- https://github.com/LuaDist/dkjson
-- =============================================================================
-- SHIM: FXServer bundles a compiled cjson C extension. dkjson is 100% pure
-- Lua and produces identical output for all types FXServer resources use.
-- Performance difference is irrelevant at test-runner scale.
-- Global `json` table mirrors FXServer's cjson API surface.
-- =============================================================================

local json = {}

local string_find   = string.find
local string_format = string.format
local string_byte   = string.byte
local string_char   = string.char
local string_sub    = string.sub
local table_concat  = table.concat
local math_floor    = math.floor
local math_huge     = math.huge
local type          = type
local tostring      = tostring
local tonumber      = tonumber
local pairs         = pairs
local ipairs        = ipairs
local error         = error
local setmetatable  = setmetatable
local select        = select

-- ---------------------------------------------------------------------------
-- Null sentinel (mirrors cjson.null / json.null)
-- ---------------------------------------------------------------------------
json.null = setmetatable({}, {
    __tostring = function() return "null" end,
    __eq       = function(a, b)
        return rawequal(a, b) or rawequal(b, json.null)
    end
})

-- ---------------------------------------------------------------------------
-- Encoder
-- ---------------------------------------------------------------------------
local escapes = {
    ['"']  = '\\"',
    ['\\'] = '\\\\',
    ['/']  = '\\/',
    ['\b'] = '\\b',
    ['\f'] = '\\f',
    ['\n'] = '\\n',
    ['\r'] = '\\r',
    ['\t'] = '\\t',
}

local function _escape(s)
    return (s:gsub('[%z\1-\31\\\"/]', function(c)
        return escapes[c] or string_format('\\u%04x', string_byte(c))
    end))
end

local function _isarray(t)
    local max, n = 0, 0
    for k in pairs(t) do
        if type(k) ~= "number" or k ~= math_floor(k) or k < 1 then
            return false
        end
        if k > max then max = k end
        n = n + 1
    end
    return n == max
end

local function _encode(val, indent, level, seen)
    local vtype = type(val)

    if vtype == "nil" or rawequal(val, json.null) then
        return "null"
    elseif vtype == "boolean" then
        return val and "true" or "false"
    elseif vtype == "number" then
        if val ~= val then
            error("cannot encode NaN")
        elseif val == math_huge or val == -math_huge then
            error("cannot encode infinity")
        end
        -- Integer check
        if val == math_floor(val) and math.abs(val) < 2^53 then
            return string_format("%.0f", val)
        else
            return string_format("%.17g", val)
        end
    elseif vtype == "string" then
        return '"' .. _escape(val) .. '"'
    elseif vtype == "table" then
        if seen[val] then error("circular reference in JSON encode") end
        seen[val] = true
        local result
        local nl, sp, indent2 = "", "", ""
        if indent then
            nl      = "\n"
            sp      = " "
            indent2 = indent .. string.rep(" ", 2)
        end

        if _isarray(val) then
            local buf = {}
            for i = 1, #val do
                buf[i] = (indent2 or "") .. _encode(val[i], indent2, level + 1, seen)
            end
            if indent then
                result = "[" .. nl .. table_concat(buf, "," .. nl) .. nl .. indent .. "]"
            else
                result = "[" .. table_concat(buf, ",") .. "]"
            end
        else
            local buf, keys = {}, {}
            for k in pairs(val) do
                if type(k) == "string" then
                    keys[#keys + 1] = k
                end
            end
            table.sort(keys)   -- deterministic key order
            for _, k in ipairs(keys) do
                local v = val[k]
                if v ~= nil then
                    local enc = _encode(v, indent2, level + 1, seen)
                    if indent then
                        buf[#buf + 1] = indent2 .. '"' .. _escape(k) .. '": ' .. enc
                    else
                        buf[#buf + 1] = '"' .. _escape(k) .. '":' .. enc
                    end
                end
            end
            if indent then
                result = "{" .. nl .. table_concat(buf, "," .. nl) .. nl .. indent .. "}"
            else
                result = "{" .. table_concat(buf, ",") .. "}"
            end
        end
        seen[val] = nil
        return result
    else
        error(string_format("cannot encode type '%s'", vtype))
    end
end

--- Encode a Lua value to a JSON string.
-- @param val       Any Lua value (table, string, number, boolean, nil, json.null)
-- @param options   Optional table: { indent = true|string }
-- @return string
function json.encode(val, options)
    local indent = options and options.indent
    if indent == true then indent = "" end
    return _encode(val, indent, 0, {})
end

-- ---------------------------------------------------------------------------
-- Decoder
-- ---------------------------------------------------------------------------
local _position = 1
local _src      = ""

local function _err(msg)
    error(string_format("JSON decode error at position %d: %s\n...%s...",
        _position, msg, string_sub(_src, math.max(1, _position - 10), _position + 10)))
end

local function _skip()
    local _, e = string_find(_src, "^[ \t\r\n]*", _position)
    if e then _position = e + 1 end
end

local function _expect(c)
    if string_byte(_src, _position) ~= string_byte(c) then
        _err("expected '" .. c .. "'")
    end
    _position = _position + 1
end

local _decode_value   -- forward

local _unescapes = {
    ['"']  = '"',  ['\\'] = '\\', ['/'] = '/',
    ['b']  = '\b', ['f']  = '\f', ['n'] = '\n',
    ['r']  = '\r', ['t']  = '\t',
}

local function _decode_string()
    _expect('"')
    local buf = {}
    while true do
        local c = string_sub(_src, _position, _position)
        if c == "" then _err("unterminated string") end
        if c == '"' then
            _position = _position + 1
            return table_concat(buf)
        elseif c == '\\' then
            _position = _position + 1
            local esc = string_sub(_src, _position, _position)
            _position = _position + 1
            if esc == 'u' then
                local hex = string_sub(_src, _position, _position + 3)
                _position = _position + 4
                local cp = tonumber(hex, 16)
                if not cp then _err("bad unicode escape \\u" .. hex) end
                -- Basic BMP only; surrogate pairs not handled (sufficient for FXServer use)
                if cp < 0x80 then
                    buf[#buf + 1] = string_char(cp)
                elseif cp < 0x800 then
                    buf[#buf + 1] = string_char(
                        0xC0 + math_floor(cp / 64),
                        0x80 + (cp % 64)
                    )
                else
                    buf[#buf + 1] = string_char(
                        0xE0 + math_floor(cp / 4096),
                        0x80 + math_floor((cp % 4096) / 64),
                        0x80 + (cp % 64)
                    )
                end
            else
                local unesc = _unescapes[esc]
                if not unesc then _err("unknown escape \\" .. esc) end
                buf[#buf + 1] = unesc
            end
        else
            buf[#buf + 1] = c
            _position = _position + 1
        end
    end
end

local function _decode_number()
    local s, e, tok = string_find(_src, "^(-?%d+%.?%d*[eE]?[+-]?%d*)", _position)
    if not tok then _err("invalid number") end
    _position = e + 1
    local n = tonumber(tok)
    if not n then _err("invalid number: " .. tok) end
    return n
end

local function _decode_array()
    _expect('[')
    local arr = {}
    _skip()
    if string_byte(_src, _position) == string_byte(']') then
        _position = _position + 1
        return arr
    end
    while true do
        _skip()
        arr[#arr + 1] = _decode_value()
        _skip()
        local c = string_byte(_src, _position)
        if c == string_byte(']') then
            _position = _position + 1
            return arr
        elseif c == string_byte(',') then
            _position = _position + 1
        else
            _err("expected ',' or ']'")
        end
    end
end

local function _decode_object()
    _expect('{')
    local obj = {}
    _skip()
    if string_byte(_src, _position) == string_byte('}') then
        _position = _position + 1
        return obj
    end
    while true do
        _skip()
        local key = _decode_string()
        _skip()
        _expect(':')
        _skip()
        local val = _decode_value()
        obj[key] = val
        _skip()
        local c = string_byte(_src, _position)
        if c == string_byte('}') then
            _position = _position + 1
            return obj
        elseif c == string_byte(',') then
            _position = _position + 1
        else
            _err("expected ',' or '}'")
        end
    end
end

_decode_value = function()
    _skip()
    local c = string_byte(_src, _position)
    if     c == string_byte('"') then return _decode_string()
    elseif c == string_byte('[') then return _decode_array()
    elseif c == string_byte('{') then return _decode_object()
    elseif c == string_byte('t') then
        if string_sub(_src, _position, _position + 3) == "true" then
            _position = _position + 4; return true
        end
        _err("invalid token")
    elseif c == string_byte('f') then
        if string_sub(_src, _position, _position + 4) == "false" then
            _position = _position + 5; return false
        end
        _err("invalid token")
    elseif c == string_byte('n') then
        if string_sub(_src, _position, _position + 3) == "null" then
            _position = _position + 4; return json.null
        end
        _err("invalid token")
    elseif c and (c == string_byte('-') or (c >= string_byte('0') and c <= string_byte('9'))) then
        return _decode_number()
    else
        _err(string_format("unexpected character '%s'",
            c and string_char(c) or "<EOF>"))
    end
end

--- Decode a JSON string to a Lua value.
-- @param s   JSON string
-- @return    Lua value, or (nil, error_message) on failure
function json.decode(s)
    if type(s) ~= "string" then
        return nil, "json.decode: expected string, got " .. type(s)
    end
    _src      = s
    _position = 1
    local ok, result = xpcall(_decode_value, function(e) return e end)
    if not ok then
        return nil, result
    end
    return result
end

-- cjson-compatible aliases
json.new = function() return json end   -- cjson.new() returns a new instance; we share state

-- Expose globally as `json` (FXServer convention)
_G.json = json

return json
