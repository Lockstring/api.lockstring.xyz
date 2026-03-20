local json = (function()
    local json = { _version = "0.1.2" }
    local encode
    local escape_char_map = {
        ["\\"] = "\\", ['"'] = '"', ["\b"] = "b",
        ["\f"] = "f", ["\n"] = "n", ["\r"] = "r", ["\t"] = "t",
    }
    local escape_char_map_inv = { ["/"] = "/" }
    for k, v in pairs(escape_char_map) do escape_char_map_inv[v] = k end
    local function escape_char(c)
        return "\\" .. (escape_char_map[c] or string.format("u%04x", c:byte()))
    end
    local function encode_nil() return "null" end
    local function encode_table(val, stack)
        local res = {}
        stack = stack or {}
        if stack[val] then error("circular reference") end
        stack[val] = true
        if rawget(val, 1) ~= nil or next(val) == nil then
            local n = 0
            for k in pairs(val) do
                if type(k) ~= "number" then error("invalid table: mixed or invalid key types") end
                n = n + 1
            end
            if n ~= #val then error("invalid table: sparse array") end
            for i, v in ipairs(val) do table.insert(res, encode(v, stack)) end
            stack[val] = nil
            return "[" .. table.concat(res, ",") .. "]"
        else
            for k, v in pairs(val) do
                if type(k) ~= "string" then error("invalid table: mixed or invalid key types") end
                table.insert(res, encode(k, stack) .. ":" .. encode(v, stack))
            end
            stack[val] = nil
            return "{" .. table.concat(res, ",") .. "}"
        end
    end
    local function encode_string(val)
        return '"' .. val:gsub('[%z\1-\31\\"]', escape_char) .. '"'
    end
    local function encode_number(val)
        if val ~= val or val <= -math.huge or val >= math.huge then
            error("unexpected number value '" .. tostring(val) .. "'")
        end
        return string.format("%.14g", val)
    end
    local type_func_map = {
        ["nil"] = encode_nil, ["table"] = encode_table,
        ["string"] = encode_string, ["number"] = encode_number,
        ["boolean"] = tostring,
    }
    encode = function(val, stack)
        local t = type(val)
        local f = type_func_map[t]
        if f then return f(val, stack) end
        error("unexpected type '" .. t .. "'")
    end
    function json.encode(val) return (encode(val)) end
    local parse
    local function create_set(...)
        local res = {}
        for i = 1, select("#", ...) do res[select(i, ...)] = true end
        return res
    end
    local space_chars = create_set(" ", "\t", "\r", "\n")
    local delim_chars = create_set(" ", "\t", "\r", "\n", "]", "}", ",")
    local escape_chars = create_set("\\", "/", '"', "b", "f", "n", "r", "t", "u")
    local literals = create_set("true", "false", "null")
    local literal_map = { ["true"] = true, ["false"] = false, ["null"] = nil }
    local function next_char(str, idx, set, negate)
        for i = idx, #str do
            if set[str:sub(i, i)] ~= negate then return i end
        end
        return #str + 1
    end
    local function decode_error(str, idx, msg)
        local line_count, col_count = 1, 1
        for i = 1, idx - 1 do
            col_count = col_count + 1
            if str:sub(i, i) == "\n" then line_count = line_count + 1; col_count = 1 end
        end
        error(string.format("%s at line %d col %d", msg, line_count, col_count))
    end
    local function codepoint_to_utf8(n)
        local f = math.floor
        if n <= 0x7f then return string.char(n)
        elseif n <= 0x7ff then return string.char(f(n / 64) + 192, n % 64 + 128)
        elseif n <= 0xffff then return string.char(f(n / 4096) + 224, f(n % 4096 / 64) + 128, n % 64 + 128)
        elseif n <= 0x10ffff then return string.char(f(n / 262144) + 240, f(n % 262144 / 4096) + 128, f(n % 4096 / 64) + 128, n % 64 + 128)
        end
        error(string.format("invalid unicode codepoint '%x'", n))
    end
    local function parse_unicode_escape(s)
        local n1 = tonumber(s:sub(1, 4), 16)
        local n2 = tonumber(s:sub(7, 10), 16)
        if n2 then return codepoint_to_utf8((n1 - 0xd800) * 0x400 + (n2 - 0xdc00) + 0x10000)
        else return codepoint_to_utf8(n1) end
    end
    local function parse_string(str, i)
        local res, j, k = "", i + 1, i + 1
        while j <= #str do
            local x = str:byte(j)
            if x < 32 then decode_error(str, j, "control character in string")
            elseif x == 92 then
                res = res .. str:sub(k, j - 1); j = j + 1
                local c = str:sub(j, j)
                if c == "u" then
                    local hex = str:match("^[dD][89aAbB]%x%x\\u%x%x%x%x", j + 1) or str:match("^%x%x%x%x", j + 1) or decode_error(str, j - 1, "invalid unicode escape in string")
                    res = res .. parse_unicode_escape(hex); j = j + #hex
                else
                    if not escape_chars[c] then decode_error(str, j - 1, "invalid escape char '" .. c .. "' in string") end
                    res = res .. escape_char_map_inv[c]
                end
                k = j + 1
            elseif x == 34 then res = res .. str:sub(k, j - 1); return res, j + 1 end
            j = j + 1
        end
        decode_error(str, i, "expected closing quote for string")
    end
    local function parse_number(str, i)
        local x = next_char(str, i, delim_chars)
        local s = str:sub(i, x - 1)
        local n = tonumber(s)
        if not n then decode_error(str, i, "invalid number '" .. s .. "'") end
        return n, x
    end
    local function parse_literal(str, i)
        local x = next_char(str, i, delim_chars)
        local word = str:sub(i, x - 1)
        if not literals[word] then decode_error(str, i, "invalid literal '" .. word .. "'") end
        return literal_map[word], x
    end
    local function parse_array(str, i)
        local res, n = {}, 1; i = i + 1
        while 1 do
            local x; i = next_char(str, i, space_chars, true)
            if str:sub(i, i) == "]" then i = i + 1; break end
            x, i = parse(str, i); res[n] = x; n = n + 1
            i = next_char(str, i, space_chars, true)
            local chr = str:sub(i, i); i = i + 1
            if chr == "]" then break end
            if chr ~= "," then decode_error(str, i, "expected ']' or ','") end
        end
        return res, i
    end
    local function parse_object(str, i)
        local res = {}; i = i + 1
        while 1 do
            local key, val; i = next_char(str, i, space_chars, true)
            if str:sub(i, i) == "}" then i = i + 1; break end
            if str:sub(i, i) ~= '"' then decode_error(str, i, "expected string for key") end
            key, i = parse(str, i)
            i = next_char(str, i, space_chars, true)
            if str:sub(i, i) ~= ":" then decode_error(str, i, "expected ':' after key") end
            i = next_char(str, i + 1, space_chars, true)
            val, i = parse(str, i); res[key] = val
            i = next_char(str, i, space_chars, true)
            local chr = str:sub(i, i); i = i + 1
            if chr == "}" then break end
            if chr ~= "," then decode_error(str, i, "expected '}' or ','") end
        end
        return res, i
    end
    local char_func_map = {
        ['"'] = parse_string, ["0"] = parse_number, ["1"] = parse_number,
        ["2"] = parse_number, ["3"] = parse_number, ["4"] = parse_number,
        ["5"] = parse_number, ["6"] = parse_number, ["7"] = parse_number,
        ["8"] = parse_number, ["9"] = parse_number, ["-"] = parse_number,
        ["t"] = parse_literal, ["f"] = parse_literal, ["n"] = parse_literal,
        ["["] = parse_array, ["{"] = parse_object,
    }
    parse = function(str, idx)
        local chr = str:sub(idx, idx)
        local f = char_func_map[chr]
        if f then return f(str, idx) end
        decode_error(str, idx, "unexpected character '" .. chr .. "'")
    end
    function json.decode(str)
        if type(str) ~= "string" then error("expected argument of type string, got " .. type(str)) end
        local res, idx = parse(str, next_char(str, 1, space_chars, true))
        idx = next_char(str, idx, space_chars, true)
        if idx <= #str then decode_error(str, idx, "trailing garbage") end
        return res
    end
    return json
end)()

do
    local bit = bit32 or bit
    local byte = string.byte
    local char = string.char
    local rep = string.rep
    local len = string.len
    local format = string.format
    local concat = table.concat
    local load = loadstring
    local type = type
    local pcall = pcall
    local setfenv = setfenv
    local ipairs = ipairs
    local tostring = tostring
    local error = error
    local unpack = table.unpack or unpack
    local rawget = rawget
    local rawset = rawset
    local getmetatable = getmetatable
    local setmetatable = setmetatable
    local select = select
    local getfenv = getfenv
    local debug = debug
    local pairs = pairs
    local next = next
    local coroutine_wrap = coroutine.wrap
    local coroutine_yield = coroutine.yield
    local coroutine_create = coroutine.create
    local coroutine_resume = coroutine.resume

    local function _die()
        if IB_CRASH then
            pcall(IB_CRASH)
        end
        local t = {}
        setmetatable(t, {__index = function(s, k) while true do end end})
        local _ = t[1]
        while true do end
    end

    local function IsCClosure(fn)
        if type(fn) ~= "function" then return false end
        return not pcall(setfenv, fn, {})
    end

    if ... then
        for _ = nil, nil do
            for _ = nil, nil do
                for _ = nil, nil do
                    continue;
                end;
                return;
            end;
            break;
        end;
        repeat
            while ... do
                for _ = nil, nil do
                    repeat
                        if ... then
                            return;
                        end;
                        continue;
                    until ...;
                    break;
                end;
                if ... then
                    return;
                end;
                break;
            end;
            if not ... then
                break;
            end;
            return;
        until not ...;
        for _ = 1, -1 do
            for _ = nil, nil do
                repeat
                    for _ = 1, -1 do
                        return;
                    end;
                    break;
                until ...;
                return;
            end;
            break;
        end;
        for _ = nil, nil do
            repeat
                while ... do
                    for _ = nil, nil do
                        continue;
                    end;
                    for _ = 1, -1 do
                        return;
                    end;
                    break;
                end;
                for _ = nil, nil do
                    return;
                end;
                break;
            until ...;
            return;
        end;
        if ... then
            if not ... then
                if ... then
                    return;
                end;
            end;
            for _ = nil, nil do
                while ... do
                    repeat
                        continue;
                    until ...;
                    return;
                end;
                break;
            end;
        end;
        while ... do
            repeat
                for _ = nil, nil do
                    while ... do
                        for _ = 1, -1 do
                            repeat
                                continue;
                            until ...;
                            return;
                        end;
                        break;
                    end;
                    return;
                end;
                break;
            until ...;
            break;
        end;
        for _ = nil, nil do
            break;
        end;
    end;

    local _upv_a, _upv_b, _upv_c = nil, nil, nil
    local _upv_d, _upv_e = nil, nil

    if ... then
        local _r0 = ...
        local _r1 = select(1, ...)
        local _r2, _r3, _r4 = select(2, ...)
        _upv_a = function()
            _upv_b = _r0
            return function()
                _upv_c = _r1
                return function()
                    return _r2, _r3, _r4, _upv_a, _upv_b, _upv_c
                end
            end
        end
        _upv_d = coroutine_wrap(function(...)
            local _x = select("#", ...)
            coroutine_yield(_upv_a, _upv_e)
            for _ = nil, nil do
                coroutine_yield(select(_x, ...))
                continue
            end
            return ...
        end)
        _upv_e = setmetatable({}, {
            __index = function(_, k)
                return _upv_a and _upv_a() or k
            end,
            __newindex = function(_, k, v)
                _upv_b = v
            end,
            __len = function()
                return _upv_d and 0 or 1
            end,
            __call = function(_, ...)
                return ...
            end,
        })
    end

    if ... then
        local _z = function(...) return function(...) return ... end end
        local _y = _z(...)(_z)
        if _y == _z then
            (function(...)
                local a, b, c = ...
                return (function(...)
                    return a, b, c, ...
                end)(select(2, ...))
            end)(nil, _y, nil, _z)
        end
        for _ = nil, nil do
            local _ = _z
            repeat
                _ = nil
                break
            until not _
            break
        end
    end

    local dinfo
    do
        local ok, di = pcall(rawget, debug, "info")
        if not ok or not di then return _die() end
        dinfo = di
    end

    local function _verify_c(fn, check_name)
        if not IsCClosure(fn) then return false end
        if dinfo(fn, "s") ~= "[C]" then return false end
        if check_name and #(dinfo(fn, "n")) <= 1 then return false end
        return true
    end

    local function _verify_l(fn)
        if type(fn) ~= "function" then return false end
        if dinfo(fn, "s") == "[C]" then return false end
        return true
    end

    if not _verify_c(getmetatable, true) then return _die() end
    if not _verify_c(setmetatable, true) then return _die() end
    if not _verify_c(type, true) then return _die() end
    if not _verify_c(select, true) then return _die() end
    if not _verify_c(pcall, true) then return _die() end
    if not _verify_c(rawget, true) then return _die() end
    if not _verify_c(rawset, true) then return _die() end
    if not _verify_c(getfenv, true) then return _die() end
    if not _verify_c(print, true) then return _die() end
    if not _verify_c(require, true) then return _die() end
    if not _verify_c(tostring, true) then return _die() end
    if not _verify_c(string.byte, false) then return _die() end
    if not _verify_c(string.char, false) then return _die() end
    if not _verify_c(string.len, false) then return _die() end
    if not _verify_c(string.format, false) then return _die() end
    if not _verify_c(string.sub, false) then return _die() end
    if not _verify_c(string.gsub, false) then return _die() end
    if not _verify_c(table.concat, false) then return _die() end
    if not _verify_c(table.insert, false) then return _die() end
    if not _verify_c(math.random, false) then return _die() end
    if not _verify_c(coroutine_wrap, false) then return _die() end
    if not _verify_c(coroutine_yield, false) then return _die() end
    if not _verify_c(coroutine_create, false) then return _die() end
    if not _verify_c(coroutine_resume, false) then return _die() end
    if not _verify_c(pairs, true) then return _die() end
    if not _verify_c(next, true) then return _die() end
    if not _verify_c(error, true) then return _die() end

    if ... then
        local _p0 = select(1, ...)
        local _p1 = function(...)
            local _inner = function(a, b, ...)
                if a then
                    return b, ...
                end
                return ...
            end
            return _inner(false, nil, _inner(true, ...))
        end
        local _p2 = {
            [function() end] = function() end,
            [tostring] = select,
            [_p1] = _p0,
        }
        for _k, _v in next, _p2 do
            if _v == _p0 then
                _p2[_k] = nil
                _p2[_v] = _k
            end
        end
        setmetatable(_p2, {
            __index = _p2,
            __newindex = function(t, k, v)
                rawset(t, v, k)
            end,
        })
        _p2[_p1] = _p2
    end

    do
        local ok, mt = pcall(getmetatable, setmetatable({}, {
            __index = function(self, ...) while true do end end
        }))
        if not ok or type(mt) ~= "table" or type(mt["__index"]) ~= "function" then
            return _die()
        end
    end

    if not pcall(rawset, {}, " ", " ") then return _die() end
    if select(1, pcall(getfenv, 69)) == true then return _die() end

    do
        if (function() end) == (function() end) then return _die() end
    end

    if not _verify_l(function() end) then return _die() end

    do
        local ok1, r1 = pcall(rawget, {}, 1)
        if not ok1 or r1 ~= nil then return _die() end
        local t = {abc = 123}
        local ok2, r2 = pcall(rawget, t, "abc")
        if not ok2 or r2 ~= 123 then return _die() end
    end

    do
        local ok, r = pcall(tostring, 12345)
        if not ok or r ~= "12345" then return _die() end
    end

    do
        local ok, r = pcall(type, "test")
        if not ok or r ~= "string" then return _die() end
        local ok2, r2 = pcall(type, 123)
        if not ok2 or r2 ~= "number" then return _die() end
        local ok3, r3 = pcall(type, true)
        if not ok3 or r3 ~= "boolean" then return _die() end
    end

    do
        local ok, r = pcall(select, "#", 1, 2, 3)
        if not ok or r ~= 3 then return _die() end
    end

    do
        local t = {}
        local ok = pcall(rawset, t, "x", 99)
        if not ok or t.x ~= 99 then return _die() end
    end

    do
        local ok, r = pcall(string.byte, "A")
        if not ok or r ~= 65 then return _die() end
    end

    do
        local ok, r = pcall(string.char, 65)
        if not ok or r ~= "A" then return _die() end
    end

    do
        local ok, r = pcall(string.len, "test")
        if not ok or r ~= 4 then return _die() end
    end

    do
        local ok, r = pcall(string.sub, "hello", 1, 3)
        if not ok or r ~= "hel" then return _die() end
    end

    do
        local ok, r = pcall(string.format, "%d", 42)
        if not ok or r ~= "42" then return _die() end
    end

    do
        local ok, r = pcall(table.concat, {"a", "b"}, ",")
        if not ok or r ~= "a,b" then return _die() end
    end

    do
        local t = {}
        local ok = pcall(table.insert, t, "x")
        if not ok or t[1] ~= "x" then return _die() end
    end

    do
        local ok, r = pcall(math.random, 1, 1)
        if not ok or r ~= 1 then return _die() end
    end

    do
        local co = coroutine_wrap(function() coroutine_yield(777) end)
        if co() ~= 777 then return _die() end
    end

    do
        local count = 0
        for k, v in pairs({a = 1, b = 2}) do count = count + 1 end
        if count ~= 2 then return _die() end
    end

    do
        local t = {10, 20, 30}
        if next(t) == nil then return _die() end
        if next({}) ~= nil then return _die() end
    end

    do
        local ok, err = pcall(error, "test_err")
        if ok or not err or not tostring(err):find("test_err") then return _die() end
    end

    do
        local ok, r = pcall(string.gsub, "aaa", "a", "b")
        if not ok or r ~= "bbb" then return _die() end
    end

    do
        local g = getfenv(0)
        if type(g) ~= "table" then return _die() end
        if g.game == nil then return _die() end
        if g.workspace == nil then return _die() end
        if g.Instance == nil then return _die() end
    end

    do
        local game = game
        if type(game) ~= "userdata" then return _die() end
        local ok, rs = pcall(game.GetService, game, "RunService")
        if not ok or not rs then return _die() end
        local ok2, ps = pcall(game.GetService, game, "Players")
        if not ok2 or not ps then return _die() end
    end

    if ... then
        repeat
            local _q = coroutine_create(function(...)
                local x, y = coroutine_yield(...)
                for _ = nil, nil do
                    x, y = coroutine_yield(y, x)
                    continue
                end
                return x
            end)
            local _, _a, _b = coroutine_resume(_q, ...)
            for _ = nil, nil do
                _, _a, _b = coroutine_resume(_q, _b, _a)
                if not _ then break end
                continue
            end
            break
        until true
    end

    local _snapshot = {}
    local _critical = {
        getmetatable, setmetatable, type, select, pcall, rawget,
        rawset, getfenv, print, require, tostring, load,
        string.byte, string.char, string.len, string.format,
        string.sub, string.gsub, table.concat, table.insert, math.random,
        pairs, next, error, coroutine_wrap, coroutine_yield,
        coroutine_create, coroutine_resume,
    }
    for i, fn in ipairs(_critical) do
        _snapshot[i] = fn
    end

    local function _integrity()
        local current = {
            getmetatable, setmetatable, type, select, pcall, rawget,
            rawset, getfenv, print, require, tostring, load,
            string.byte, string.char, string.len, string.format,
            string.sub, string.gsub, table.concat, table.insert, math.random,
            pairs, next, error, coroutine_wrap, coroutine_yield,
            coroutine_create, coroutine_resume,
        }
        for i = 1, #_snapshot do
            if _snapshot[i] ~= current[i] then return false end
            if not IsCClosure(current[i]) then return false end
        end
        return true
    end

    if not _integrity() then return _die() end

    if not skey then return _die() end
    if type(skey) ~= "string" or #skey == 0 then return _die() end

    local script_code = [=[
%SCRIPT%
]=]

    if type(gethwid) ~= "function" then return _die() end
    if not IsCClosure(gethwid) then return _die() end

    local hwid = gethwid()
    if type(hwid) ~= "string" or #hwid == 0 then return _die() end

    if ... then
        local _w = select("#", ...)
        local _x = {select(1, ...)}
        for _i = _w, 1, -1 do
            local _v = _x[_i]
            if type(_v) == "function" then
                local _ok, _r = pcall(_v, unpack(_x, 1, _w))
                if _ok then
                    _x[_i] = _r
                else
                    for _ = nil, nil do
                        _x[_i] = nil
                        continue
                    end
                end
            end
            for _ = 1, -1 do
                repeat
                    return _v
                until true
                break
            end
        end
        if _x[1] then
            local _mt = {
                __index = function(_, k)
                    return _x[k % _w + 1]
                end,
                __len = function()
                    return _w
                end,
            }
            setmetatable(_x, _mt)
            for _ = nil, nil do
                _mt.__newindex = function(t, k, v)
                    rawset(t, k + _w, v)
                end
                break
            end
        end
    end

    local s1 = "%PLACEHOLDER0%"
    local s2 = "%PLACEHOLDER1%"
    local s3 = "%PLACEHOLDER2%"
    local s4 = "%PLACEHOLDER3%"
    local secret_hex = s1 .. s2 .. s3 .. s4
    s1, s2, s3, s4 = nil, nil, nil, nil

    local key_bytes = {}
    for i = 1, #secret_hex, 2 do
        key_bytes[#key_bytes + 1] = char(tonumber(secret_hex:sub(i, i + 1), 16))
    end
    local base_key = concat(key_bytes)
    secret_hex = nil
    key_bytes = nil

    local K = {
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    }

    local function sha256(msg)
        local H = {
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
        }
        local ml = len(msg) * 8
        msg = msg .. char(0x80)
        while (len(msg) % 64) ~= 56 do msg = msg .. "\0" end
        msg = msg .. char(
            0, 0, 0, 0,
            bit.band(bit.rshift(ml, 24), 255),
            bit.band(bit.rshift(ml, 16), 255),
            bit.band(bit.rshift(ml, 8), 255),
            bit.band(ml, 255)
        )
        for i = 1, len(msg), 64 do
            local w = {}
            for j = 0, 15 do
                local a, b, c, d = byte(msg, i + j * 4, i + j * 4 + 3)
                w[j] = bit.lshift(a, 24) + bit.lshift(b, 16) + bit.lshift(c, 8) + d
            end
            for j = 16, 63 do
                local s0 = bit.bxor(bit.rrotate(w[j - 15], 7), bit.rrotate(w[j - 15], 18), bit.rshift(w[j - 15], 3))
                local s1 = bit.bxor(bit.rrotate(w[j - 2], 17), bit.rrotate(w[j - 2], 19), bit.rshift(w[j - 2], 10))
                w[j] = bit.band(w[j - 16] + s0 + w[j - 7] + s1, 0xffffffff)
            end
            local a, b, c, d, e, f, g, h = unpack(H)
            for j = 0, 63 do
                local S1 = bit.bxor(bit.rrotate(e, 6), bit.rrotate(e, 11), bit.rrotate(e, 25))
                local ch = bit.bxor(bit.band(e, f), bit.band(bit.bnot(e), g))
                local temp1 = bit.band(h + S1 + ch + K[j + 1] + w[j], 0xffffffff)
                local S0 = bit.bxor(bit.rrotate(a, 2), bit.rrotate(a, 13), bit.rrotate(a, 22))
                local maj = bit.bxor(bit.band(a, b), bit.band(a, c), bit.band(b, c))
                local temp2 = bit.band(S0 + maj, 0xffffffff)
                h, g, f, e, d, c, b, a = g, f, e, bit.band(d + temp1, 0xffffffff), c, b, a, bit.band(temp1 + temp2, 0xffffffff)
            end
            for j = 1, 8 do
                H[j] = bit.band(H[j] + ({a, b, c, d, e, f, g, h})[j], 0xffffffff)
            end
        end
        local out = {}
        for i = 1, 8 do
            local v = H[i]
            out[#out + 1] = char(
                bit.band(bit.rshift(v, 24), 255),
                bit.band(bit.rshift(v, 16), 255),
                bit.band(bit.rshift(v, 8), 255),
                bit.band(v, 255)
            )
        end
        return concat(out)
    end

    local BLOCK_SIZE = 64

    local function hmac_sha256(key_raw, message)
        local k = key_raw
        if #k > BLOCK_SIZE then k = sha256(k) end
        if #k < BLOCK_SIZE then k = k .. rep("\0", BLOCK_SIZE - #k) end
        local ipad, opad = {}, {}
        for i = 1, BLOCK_SIZE do
            local kb = byte(k, i)
            ipad[i] = char(bit.bxor(kb, 0x36))
            opad[i] = char(bit.bxor(kb, 0x5c))
        end
        local inner = sha256(concat(ipad) .. message)
        local final = sha256(concat(opad) .. inner)
        return final:gsub(".", function(c)
            return format("%02x", byte(c))
        end)
    end

    local function xor_decode(encoded_bytes, xor_key)
        local out = {}
        local kl = #xor_key
        for i = 1, #encoded_bytes do
            local ki = ((i - 1) % kl) + 1
            out[i] = char(bit.bxor(byte(encoded_bytes, i), byte(xor_key, ki)))
        end
        return concat(out)
    end

    local URL_XOR_KEY = "%URL_XOR_KEY%"
    local URL1_ENCODED = "%URL1_ENCODED%"
    local URL2_ENCODED = "%URL2_ENCODED%"
    local URL_CHECK1 = xor_decode(URL1_ENCODED, URL_XOR_KEY)
    local URL_CHECK2 = xor_decode(URL2_ENCODED, URL_XOR_KEY)

    local HttpRequest = http_request or request or (http and http.request)
    if not HttpRequest then return _die() end
    if not IsCClosure(HttpRequest) then return _die() end

    local function safe_request(url, body, max_retries)
        max_retries = max_retries or 2
        local last_err
        for attempt = 1, max_retries do
            local ok, response = pcall(HttpRequest, {
                Url = url,
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = body,
            })
            if ok and response and response.Body then
                local decode_ok, data = pcall(json.decode, response.Body)
                if decode_ok and data then
                    return data
                end
                last_err = "decode"
            else
                last_err = tostring(response)
            end
            if attempt < max_retries then
                local tw = task and task.wait
                if tw then tw(0.5) end
            end
        end
        return nil, last_err
    end

    if not _integrity() then return _die() end

    local hwid_hmac = hmac_sha256(base_key, hwid)
    local signed_check1 = hmac_sha256(base_key, skey .. "|" .. hwid_hmac)

    if ... then
        local _h0 = function(...) return function() return ... end end
        local _h1 = _h0(hwid_hmac, signed_check1)
        local _h2 = _h0(_h1, _h0)
        local _h3 = {_h2, _h1, _h0, [_h0] = _h2, [_h1] = _h0}
        for _ = nil, nil do
            _h3[_h2] = setmetatable({}, {
                __call = function(_, ...)
                    return _h1()
                end,
                __index = function(_, k)
                    return _h3[k] or _h0(k)
                end,
            })
            break
        end
    end

    local body1 = json.encode({
        a = skey,
        b = hwid_hmac,
        c = signed_check1,
    })

    local data, err = safe_request(URL_CHECK1, body1)
    body1 = nil
    signed_check1 = nil

    if not data then return _die() end
    if data.error then return load(data.error)() end
    if not data.responses or type(data.responses) ~= "table" then return _die() end

    if not _integrity() then return _die() end

    local real_session = nil
    for _, entry in ipairs(data.responses) do
        if type(entry) == "table" and entry.a and entry.b then
            local expected_sig = hmac_sha256(base_key, entry.a)
            if expected_sig == entry.b then
                real_session = entry.a
                break
            end
        end
    end
    data = nil

    if not real_session then return _die() end

    if ... then
        local _s0 = real_session
        local _s1 = function() return _s0 end
        local _s2 = coroutine_wrap(function()
            while true do
                _s0 = coroutine_yield(_s1)
                _s1 = function() return _s0 end
            end
        end)
        for _ = nil, nil do
            _s2()
            break
        end
        repeat
            for _ = 1, -1 do
                _s2(_s1())
                continue
            end
            break
        until true
    end

    local session_sig = hmac_sha256(base_key, real_session .. "|" .. hwid_hmac)

    local body2 = json.encode({
        a = skey,
        b = session_sig,
        c = tostring(math.random(1000, 9999)),
    })

    session_sig = nil
    real_session = nil

    local data2, err2 = safe_request(URL_CHECK2, body2)
    body2 = nil

    if not data2 then return _die() end
    if data2.error then return _die() end
    if type(data2) ~= "table" then return _die() end

    if not _integrity() then return _die() end

    local authenticated = false
    for _, entry in ipairs(data2) do
        if type(entry) == "table" and entry.a and entry.b then
            local expected = hmac_sha256(base_key, entry.b)
            if expected == entry.a then
                authenticated = true
                break
            end
        end
    end
    data2 = nil

    if not authenticated then return _die() end

    if not _integrity() then return _die() end
    if not IsCClosure(load) then return _die() end

    local fn = load(script_code)
    if not fn then return _die() end
    if not _verify_l(fn) then return _die() end

    if ... then
        local _f0 = fn
        local _f1, _f2
        _f1 = function(n)
            if n <= 0 then return _f0 end
            return function() return _f1(n - 1) end
        end
        _f2 = setmetatable({}, {
            __index = function(_, k)
                if type(k) == "number" then
                    return _f1(k)
                end
                return _f0
            end,
            __call = function(_, ...)
                local _r = {pcall(_f1(0), ...)}
                for _ = nil, nil do
                    return unpack(_r)
                end
            end,
        })
        for _ = nil, nil do
            repeat
                while ... do
                    for _ = 1, -1 do
                        _f2(select(1, ...))
                        continue
                    end
                    break
                end
                break
            until not ...
            break
        end
    end

    print("Authenticated successfully with lockstring.xyz")

    local exec_ok, exec_err = pcall(fn)
    if not exec_ok then _die() end

    base_key = nil
    hwid = nil
    hwid_hmac = nil
    script_code = nil
    sha256 = nil
    hmac_sha256 = nil
    _snapshot = nil
    _critical = nil
    _integrity = nil
    fn = nil
end