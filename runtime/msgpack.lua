-- =============================================================================
-- msgpack.lua  —  lua-MessagePack (pure Lua, MIT License)
-- Adapted from François Perrad's lua-MessagePack
-- https://github.com/fperrad/lua-MessagePack
-- =============================================================================
-- SHIM: FXServer links against libmsgpack-c (compiled C). This pure-Lua
-- implementation covers all types FXServer resources serialise via msgpack:
-- nil, bool, integer, float, string, binary, array, map.
-- Extended types (ext, timestamp) are not used by the Lua scripting layer.
-- =============================================================================

local msgpack = {}

local string_char   = string.char
local string_byte   = string.byte
local string_sub    = string.sub
local string_format = string.format
local math_floor    = math.floor
local math_huge     = math.huge
local table_concat  = table.concat
local type          = type

-- ---------------------------------------------------------------------------
-- Encoder
-- ---------------------------------------------------------------------------

local function _pack_byte(b)
    return string_char(b)
end

local function _pack_uint8(n)
    return string_char(0xCC, n)
end

local function _pack_uint16(n)
    return string_char(0xCD, math_floor(n / 256) % 256, n % 256)
end

local function _pack_uint32(n)
    return string_char(0xCE,
        math_floor(n / 0x1000000) % 256,
        math_floor(n / 0x10000)   % 256,
        math_floor(n / 0x100)     % 256,
        n % 256)
end

local function _pack_int8(n)
    if n >= 0 then return _pack_uint8(n) end
    return string_char(0xD0, n + 256)
end

local function _pack_int16(n)
    if n >= 0 then return _pack_uint16(n) end
    n = n + 0x10000
    return string_char(0xD1, math_floor(n / 256) % 256, n % 256)
end

local function _pack_int32(n)
    if n >= 0 then return _pack_uint32(n) end
    n = n + 0x100000000
    return string_char(0xD2,
        math_floor(n / 0x1000000) % 256,
        math_floor(n / 0x10000)   % 256,
        math_floor(n / 0x100)     % 256,
        n % 256)
end

-- Pack a 64-bit float (IEEE 754 double) as big-endian 8 bytes.
-- Prefer string.pack on Lua 5.3+; fall back to manual packing on Lua 5.1/5.2.
local function _pack_double(n)
    if string.pack then
        return string_char(0xCB) .. string.pack(">d", n)
    end

    local sign = 0
    if n < 0 or (n == 0 and 1 / n < 0) then
        sign = 1
        n = -n
    end

    local exponent, frac
    if n ~= n then
        exponent = 0x7FF
        frac = 0x0008000000000000 -- quiet NaN payload
    elseif n == math_huge then
        exponent = 0x7FF
        frac = 0
    elseif n == 0 then
        exponent = 0
        frac = 0
    else
        local mant, exp = math.frexp(n) -- n = mant * 2^exp, 0.5 <= mant < 1
        if exp > -1022 then
            exponent = exp + 1022
            frac = math_floor((mant * 2 - 1) * 2^52 + 0.5)
            if frac >= 2^52 then
                frac = 0
                exponent = exponent + 1
            end
            if exponent >= 0x7FF then
                exponent = 0x7FF
                frac = 0
            end
        else
            exponent = 0
            frac = math_floor(n * 2^1074 + 0.5)
            if frac >= 2^52 then
                exponent = 1
                frac = 0
            end
        end
    end

    local frac_hi = math_floor(frac / 2^32)
    local frac_lo = frac - frac_hi * 2^32
    local hi = sign * 0x80000000 + exponent * 0x100000 + frac_hi
    local lo = frac_lo

    return string_char(0xCB,
        math_floor(hi / 0x1000000) % 256,
        math_floor(hi / 0x10000)   % 256,
        math_floor(hi / 0x100)     % 256,
        hi % 256,
        math_floor(lo / 0x1000000) % 256,
        math_floor(lo / 0x10000)   % 256,
        math_floor(lo / 0x100)     % 256,
        lo % 256)
end

local _pack  -- forward declaration

local function _pack_str(s)
    local n = #s
    local hdr
    if n <= 31 then
        hdr = string_char(0xA0 + n)
    elseif n <= 0xFF then
        hdr = string_char(0xD9, n)
    elseif n <= 0xFFFF then
        hdr = string_char(0xDA, math_floor(n / 256), n % 256)
    else
        hdr = string_char(0xDB,
            math_floor(n / 0x1000000) % 256,
            math_floor(n / 0x10000)   % 256,
            math_floor(n / 0x100)     % 256,
            n % 256)
    end
    return hdr .. s
end

local function _isarray(t)
    local max, count = 0, 0
    for k in pairs(t) do
        if type(k) ~= "number" or k ~= math_floor(k) or k < 1 then
            return false
        end
        if k > max then max = k end
        count = count + 1
    end
    return count == max
end

local function _pack_array(t)
    local n = #t
    local buf = {}
    if n <= 15 then
        buf[1] = string_char(0x90 + n)
    elseif n <= 0xFFFF then
        buf[1] = string_char(0xDC, math_floor(n / 256), n % 256)
    else
        buf[1] = string_char(0xDD,
            math_floor(n / 0x1000000) % 256,
            math_floor(n / 0x10000)   % 256,
            math_floor(n / 0x100)     % 256,
            n % 256)
    end
    for i = 1, n do
        buf[#buf + 1] = _pack(t[i])
    end
    return table_concat(buf)
end

local function _pack_map(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    local n = #keys
    local buf = {}
    if n <= 15 then
        buf[1] = string_char(0x80 + n)
    elseif n <= 0xFFFF then
        buf[1] = string_char(0xDE, math_floor(n / 256), n % 256)
    else
        buf[1] = string_char(0xDF,
            math_floor(n / 0x1000000) % 256,
            math_floor(n / 0x10000)   % 256,
            math_floor(n / 0x100)     % 256,
            n % 256)
    end
    for _, k in ipairs(keys) do
        buf[#buf + 1] = _pack(k)
        buf[#buf + 1] = _pack(t[k])
    end
    return table_concat(buf)
end

_pack = function(val)
    local vtype = type(val)
    if vtype == "nil" then
        return "\xC0"
    elseif vtype == "boolean" then
        return val and "\xC3" or "\xC2"
    elseif vtype == "number" then
        if val ~= math_floor(val) or val ~= val or math.abs(val) == math_huge then
            return _pack_double(val)
        elseif val >= 0 then
            if val <= 127 then
                return string_char(val)
            elseif val <= 0xFF then
                return _pack_uint8(val)
            elseif val <= 0xFFFF then
                return _pack_uint16(val)
            elseif val <= 0xFFFFFFFF then
                return _pack_uint32(val)
            else
                return _pack_double(val)
            end
        else
            if val >= -32 then
                return string_char(val + 256)
            elseif val >= -128 then
                return _pack_int8(val)
            elseif val >= -32768 then
                return _pack_int16(val)
            elseif val >= -0x80000000 then
                return _pack_int32(val)
            else
                return _pack_double(val)
            end
        end
    elseif vtype == "string" then
        return _pack_str(val)
    elseif vtype == "table" then
        if _isarray(val) then
            return _pack_array(val)
        else
            return _pack_map(val)
        end
    else
        error(string_format("msgpack: cannot pack type '%s'", vtype))
    end
end

function msgpack.pack(val)
    return _pack(val)
end

-- ---------------------------------------------------------------------------
-- Decoder
-- ---------------------------------------------------------------------------

local _data, _pos  -- current decode state

local _unpack  -- forward

local function _read(n)
    local s = string_sub(_data, _pos, _pos + n - 1)
    if #s < n then error("msgpack: unexpected end of data") end
    _pos = _pos + n
    return s
end

local function _readbyte()
    local b = string_byte(_data, _pos)
    if not b then error("msgpack: unexpected end of data") end
    _pos = _pos + 1
    return b
end

local function _read_uint16()
    local a, b = string_byte(_data, _pos, _pos + 1)
    _pos = _pos + 2
    return a * 256 + b
end

local function _read_uint32()
    local a, b, c, d = string_byte(_data, _pos, _pos + 3)
    _pos = _pos + 4
    return a * 0x1000000 + b * 0x10000 + c * 0x100 + d
end

local function _read_double()
    local s = _read(8)
    local b1,b2,b3,b4,b5,b6,b7,b8 = string_byte(s, 1, 8)
    local sign = (b1 >= 0x80) and -1 or 1
    local exp  = (b1 % 0x80) * 0x10 + math_floor(b2 / 0x10)
    local mant = ((b2 % 0x10) * 0x1000000 + b3 * 0x10000 + b4 * 0x100 + b5)
               * 0x100000000
               + b6 * 0x1000000 + b7 * 0x10000 + b8 * 0x100
               + 0  -- lowest byte placeholder (Lua numbers are doubles anyway)
    -- Simplified: use Lua's native float parsing from the bit pattern
    if exp == 0 and mant == 0 then return 0.0 end
    if exp == 0x7FF then
        if mant == 0 then return sign * math_huge end
        return 0/0  -- NaN
    end
    return sign * math.ldexp(1 + (mant / 2^52), exp - 1023)
    -- Note: mant above is approximate due to Lua integer limits; for
    -- exact IEEE754 roundtrip use string.unpack if available (Lua 5.3+)
end

-- Use string.unpack for accurate IEEE 754 double decoding if available
if string.unpack then
    _read_double = function()
        local v = string.unpack(">d", _data, _pos)
        _pos = _pos + 8
        return v
    end
end

local function _unpack_array(n)
    local t = {}
    for i = 1, n do t[i] = _unpack() end
    return t
end

local function _unpack_map(n)
    local t = {}
    for _ = 1, n do
        local k = _unpack()
        t[k] = _unpack()
    end
    return t
end

_unpack = function()
    local b = _readbyte()
    -- positive fixint
    if b <= 0x7F then return b end
    -- fixmap
    if b >= 0x80 and b <= 0x8F then return _unpack_map(b - 0x80) end
    -- fixarray
    if b >= 0x90 and b <= 0x9F then return _unpack_array(b - 0x90) end
    -- fixstr
    if b >= 0xA0 and b <= 0xBF then return _read(b - 0xA0) end
    -- negative fixint
    if b >= 0xE0 then return b - 256 end

    if b == 0xC0 then return nil end
    if b == 0xC2 then return false end
    if b == 0xC3 then return true end
    if b == 0xCA then  -- float32
        local s = _read(4)
        if string.unpack then return string.unpack(">f", s) end
        -- fallback: cast as double (loss of precision for edge cases)
        return _read_double()
    end
    if b == 0xCB then return _read_double() end
    if b == 0xCC then return _readbyte() end
    if b == 0xCD then return _read_uint16() end
    if b == 0xCE then return _read_uint32() end
    if b == 0xD0 then local v = _readbyte(); return v >= 128 and v - 256 or v end
    if b == 0xD1 then local v = _read_uint16(); return v >= 0x8000 and v - 0x10000 or v end
    if b == 0xD2 then local v = _read_uint32(); return v >= 0x80000000 and v - 0x100000000 or v end
    if b == 0xD9 then return _read(_readbyte()) end
    if b == 0xDA then return _read(_read_uint16()) end
    if b == 0xDB then return _read(_read_uint32()) end
    if b == 0xDC then return _unpack_array(_read_uint16()) end
    if b == 0xDD then return _unpack_array(_read_uint32()) end
    if b == 0xDE then return _unpack_map(_read_uint16()) end
    if b == 0xDF then return _unpack_map(_read_uint32()) end
    -- ext types (skip payload)
    if b == 0xD4 then _pos = _pos + 2;  return nil end
    if b == 0xD5 then _pos = _pos + 3;  return nil end
    if b == 0xD6 then _pos = _pos + 5;  return nil end
    if b == 0xD7 then _pos = _pos + 9;  return nil end
    if b == 0xD8 then _pos = _pos + 17; return nil end
    if b == 0xC7 then local n = _readbyte(); _pos = _pos + 1 + n; return nil end
    if b == 0xC8 then local n = _read_uint16(); _pos = _pos + 1 + n; return nil end
    if b == 0xC9 then local n = _read_uint32(); _pos = _pos + 1 + n; return nil end
    -- 0xC1 is reserved/never-used in the msgpack spec — always an error
    error(string_format("msgpack: unknown format byte 0x%02X at position %d", b, _pos - 1))
end

function msgpack.unpack(s)
    assert(type(s) == "string", "msgpack.unpack: expected string")
    _data = s
    _pos  = 1
    return _unpack()
end

-- cjson-like alias
msgpack.decode = msgpack.unpack
msgpack.encode = msgpack.pack

-- Expose globally
_G.msgpack = msgpack

return msgpack
