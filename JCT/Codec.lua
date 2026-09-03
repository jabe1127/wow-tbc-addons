--[[--------------------------------------------------------------------------
    JCT - Codec.lua
    Export and import of settings as a shareable text string.

    Three deliberate choices here.

    1. NO loadstring. The obvious way to read a settings string back is to
       serialise it as Lua and run it. That would make importing a string
       someone handed you equivalent to running their code. Everything below
       is a hand-written parser over a tiny grammar: it can only ever produce
       data, never behaviour, and malformed input returns an error rather
       than throwing.

    2. Only the DIFFERENCES from the defaults are exported. A full config is
       several hundred values; almost all of them are untouched. Diffing
       turns a typical export from tens of kilobytes into a few hundred
       characters, which matters when the transport is a text box you have to
       select and copy by hand.

       Absence has to be encoded explicitly: a frame with no font size is
       inheriting from General, and that is different from "key missing", so
       deliberate nils get a marker rather than being dropped.

    3. Base64 on the way out. The payload contains colour escapes and other
       characters that chat frames, Discord and forums all mangle in their
       own ways. Base64 output is letters, digits and three punctuation marks,
       which survives being pasted anywhere.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

local Codec = {}
ns.Codec = Codec

Codec.PREFIX   = "JCT1!"
Codec.NILMARK  = "\1"          -- "this key is deliberately absent"
Codec.MAX_DEPTH = 32
Codec.MAX_KEYS  = 8000

local format, floor, concat = string.format, math.floor, table.concat

--------------------------------------------------------------------------
-- Base64
--------------------------------------------------------------------------

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64R = {}
for i = 1, #B64 do B64R[B64:sub(i, i)] = i - 1 end

function Codec.EncodeBase64(data)
    local out, n, i = {}, #data, 1
    while i <= n do
        local a = data:byte(i)
        local b = data:byte(i + 1)
        local c = data:byte(i + 2)
        local n1 = floor(a / 4)
        local n2 = (a % 4) * 16 + floor((b or 0) / 16)
        local n3 = ((b or 0) % 16) * 4 + floor((c or 0) / 64)
        local n4 = (c or 0) % 64
        out[#out + 1] = B64:sub(n1 + 1, n1 + 1)
        out[#out + 1] = B64:sub(n2 + 1, n2 + 1)
        out[#out + 1] = b and B64:sub(n3 + 1, n3 + 1) or "="
        out[#out + 1] = c and B64:sub(n4 + 1, n4 + 1) or "="
        i = i + 3
    end
    return concat(out)
end

function Codec.DecodeBase64(s)
    s = s:gsub("[^A-Za-z0-9%+/=]", "")
    if #s == 0 then return nil, "nothing to decode" end
    local out, i = {}, 1
    while i <= #s do
        local c1, c2 = s:sub(i, i), s:sub(i + 1, i + 1)
        local c3, c4 = s:sub(i + 2, i + 2), s:sub(i + 3, i + 3)
        local n1, n2 = B64R[c1], B64R[c2]
        if not n1 or not n2 then return nil, "corrupt data" end
        out[#out + 1] = string.char(n1 * 4 + floor(n2 / 16))
        local n3 = B64R[c3]
        if c3 ~= "=" and c3 ~= "" and n3 then
            out[#out + 1] = string.char((n2 % 16) * 16 + floor(n3 / 4))
            local n4 = B64R[c4]
            if c4 ~= "=" and c4 ~= "" and n4 then
                out[#out + 1] = string.char((n3 % 4) * 64 + n4)
            end
        end
        i = i + 4
    end
    return concat(out)
end

--------------------------------------------------------------------------
-- Serialise
--
-- Grammar, deliberately tiny:
--   T                       true
--   F                       false
--   N<number>;              number
--   S<length>:<bytes>       string, length-prefixed so nothing needs escaping
--   { <key><value> ... }    table
--------------------------------------------------------------------------

local function serialisable(v)
    local t = type(v)
    return t == "number" or t == "string" or t == "boolean" or t == "table"
end

local function serialise(v, buf, depth)
    local t = type(v)
    if t == "number" then
        -- inf and nan format as "inf"/"nan"/"1.#INF", none of which tonumber
        -- will read back. Refuse at export rather than handing out a string
        -- that silently fails to import.
        if v ~= v or v == math.huge or v == -math.huge then
            error("cannot export a non-finite number")
        end
        buf[#buf + 1] = "N" .. format("%.14g", v) .. ";"
    elseif t == "string" then
        buf[#buf + 1] = "S" .. #v .. ":" .. v
    elseif t == "boolean" then
        buf[#buf + 1] = v and "T" or "F"
    elseif t == "table" then
        if depth > Codec.MAX_DEPTH then error("nesting too deep") end
        buf[#buf + 1] = "{"
        -- Sorted, so the same settings always produce the same string and
        -- two exports can be compared by eye.
        local nkeys, skeys = {}, {}
        for k in pairs(v) do
            if type(k) == "number" then nkeys[#nkeys + 1] = k
            elseif type(k) == "string" then skeys[#skeys + 1] = k end
        end
        table.sort(nkeys)
        table.sort(skeys)
        for i = 1, #nkeys do
            local key = nkeys[i]
            if serialisable(v[key]) then
                serialise(key, buf, depth + 1)
                serialise(v[key], buf, depth + 1)
            end
        end
        for i = 1, #skeys do
            local key = skeys[i]
            if serialisable(v[key]) then
                serialise(key, buf, depth + 1)
                serialise(v[key], buf, depth + 1)
            end
        end
        buf[#buf + 1] = "}"
    end
end

function Codec.Serialise(t)
    local buf = {}
    local ok, err = pcall(serialise, t, buf, 0)
    if not ok then return nil, tostring(err) end
    return concat(buf)
end

--------------------------------------------------------------------------
-- Parse. Returns value, nextPosition or nil, position, error.
--------------------------------------------------------------------------

local function parse(s, pos, depth)
    local c = s:sub(pos, pos)
    if c == "" then return nil, pos, "ended unexpectedly" end

    if c == "T" then return true, pos + 1 end
    if c == "F" then return false, pos + 1 end

    if c == "N" then
        local stop = s:find(";", pos + 1, true)
        if not stop then return nil, pos, "unterminated number" end
        local num = tonumber(s:sub(pos + 1, stop - 1))
        if not num then return nil, pos, "not a number" end
        return num, stop + 1
    end

    if c == "S" then
        local colon = s:find(":", pos + 1, true)
        if not colon then return nil, pos, "unterminated string" end
        local len = tonumber(s:sub(pos + 1, colon - 1))
        -- len > #s rejects both a garbage length and 1e999, which would
        -- otherwise reach string.sub as a non-representable double.
        if not len or len < 0 or len ~= floor(len) or len > #s then
            return nil, pos, "bad string length"
        end
        local str = s:sub(colon + 1, colon + len)
        if #str ~= len then return nil, pos, "string is truncated" end
        return str, colon + 1 + len
    end

    if c == "{" then
        if depth > Codec.MAX_DEPTH then return nil, pos, "nesting too deep" end
        local t = {}
        local p = pos + 1
        local count = 0
        while true do
            if p > #s then return nil, p, "unterminated table" end
            if s:sub(p, p) == "}" then return t, p + 1 end
            count = count + 1
            if count > Codec.MAX_KEYS then return nil, p, "too many entries" end

            local k, np, err = parse(s, p, depth + 1)
            if err then return nil, np, err end
            if type(k) ~= "number" and type(k) ~= "string" then
                return nil, np, "invalid key"
            end
            local v, np2, err2 = parse(s, np, depth + 1)
            if err2 then return nil, np2, err2 end

            t[k] = v
            p = np2
        end
    end

    return nil, pos, "unexpected character at position " .. pos
end

function Codec.Deserialise(s)
    local value, pos, err = parse(s, 1, 0)
    if err then return nil, err end
    if type(value) ~= "table" then return nil, "not a settings table" end
    return value
end

--------------------------------------------------------------------------
-- Diff against the defaults, and merge back
--------------------------------------------------------------------------

function Codec.Diff(cfg, def)
    local out = {}
    for k, v in pairs(cfg) do
        local d = def[k]
        if type(v) == "table" then
            if type(d) == "table" then
                local sub = Codec.Diff(v, d)
                if next(sub) ~= nil then out[k] = sub end
            else
                out[k] = ns.deepCopy(v)
            end
        elseif v ~= d then
            out[k] = v
        end
    end
    -- A key the defaults define but this config does not is meaningful: a
    -- frame with no fontSize is inheriting, which is not the same as the
    -- default size. Record it, or the import would silently pin it.
    for k in pairs(def) do
        if cfg[k] == nil then out[k] = Codec.NILMARK end
    end
    return out
end

function Codec.Apply(def, diff)
    local out = ns.deepCopy(def)
    local function overlay(dst, src, depth)
        if depth > Codec.MAX_DEPTH then return end
        for k, v in pairs(src) do
            if v == Codec.NILMARK then
                dst[k] = nil
            elseif type(v) == "table" then
                if type(dst[k]) ~= "table" then dst[k] = {} end
                overlay(dst[k], v, depth + 1)
            else
                dst[k] = v
            end
        end
    end
    overlay(out, diff, 0)
    return out
end

--------------------------------------------------------------------------
-- Top level
--------------------------------------------------------------------------

-- Things that are about this machine or this session rather than about how
-- combat text looks, and so have no business travelling to someone else.
local function stripForExport(cfg)
    cfg.savedCVars     = nil
    cfg.currentProfile = nil
    cfg.initialised    = nil
    cfg.ui             = nil
    if cfg.filters then
        cfg.filters.seenSpells = nil
        cfg.filters.seenCount  = nil
    end
    return cfg
end

function Codec.Export(cfg)
    if type(cfg) ~= "table" then return nil, "nothing to export" end
    local diff = Codec.Diff(stripForExport(ns.deepCopy(cfg)), ns.defaults)
    local body, err = Codec.Serialise(diff)
    if not body then return nil, err end
    return Codec.PREFIX .. Codec.EncodeBase64(body)
end

function Codec.Import(str)
    if type(str) ~= "string" then return nil, "nothing to import" end
    str = str:gsub("%s", "")
    if str == "" then return nil, "nothing to import" end

    if str:sub(1, #Codec.PREFIX) ~= Codec.PREFIX then
        return nil, "that does not look like a JCT settings string (it should start with "
                    .. Codec.PREFIX .. ")"
    end

    local raw, b64err = Codec.DecodeBase64(str:sub(#Codec.PREFIX + 1))
    if not raw then return nil, b64err or "corrupt data" end

    local diff, err = Codec.Deserialise(raw)
    if not diff then return nil, err end

    return Codec.Apply(ns.defaults, diff)
end
