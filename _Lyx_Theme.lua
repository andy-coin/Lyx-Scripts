--[[
    _Lyx_Theme.lua  —  Lyx global theme storage (pure data, no ImGui).

    File: <REAPER resource>/Data/Lyx/themes.lua
          return { current = "Lyx Dark", themes = { ["Lyx Dark"] = {...}, ... } }
    Colours are 0xRRGGBB integers. The built-in "Lyx Dark" always exists and is read-only.
    Every T.save() bumps ExtState "Lyx_Theme"/"rev" so running GUIs reload (see T.changed).

    usage:
        local T  = require("_Lyx_Theme")
        local th = T.get()          -- current theme, every field filled
]]

local R = reaper
local T = {}
local SECTION = "Lyx_Theme"

T.BUILTIN = "Lyx Dark"
T.dir  = R.GetResourcePath() .. "/Data/Lyx"
T.path = T.dir .. "/themes.lua"
local HERE = debug.getinfo(1, "S").source:match("@?(.*[/\\])") or "./"

function T.mix(a, b, t)
    local function ch(x, s) return (x >> s) & 0xFF end
    local function m(s) return math.floor(ch(a, s) + (ch(b, s) - ch(a, s)) * t + 0.5) end
    return (m(16) << 16) | (m(8) << 8) | m(0)
end

-- 0xRRGGBB + alpha 0..1 (default 1) -> ImGui 0xRRGGBBAA
function T.to_imgui(rgb, a)
    return ((rgb & 0xFFFFFF) << 8) | math.floor((a or 1) * 255 + 0.5)
end

-- Theme built from three base colours (also used for the old "Lyx_GetUserInputs" colours).
function T.derive(bg, fg, accent, scale)
    return {
        name = T.BUILTIN,
        colors = {
            bg = bg, bg2 = T.mix(bg, 0x000000, 0.25), base = T.mix(bg, fg, 0.3),
            title = fg, subtitle = accent, accent = accent, text = fg,
        },
        button   = { color = T.mix(bg, fg, 0.15), border = 0 },
        frame    = { color = T.mix(bg, 0x000000, 0.25), border = 0 },
        font     = { name = "", size = 14 },
        rounding = { window = 8, button = 6, frame = 6 },
        alpha = 1, spacing = 8, scale = scale or 1,
    }
end

T.default = T.derive(0x1E1E2E, 0xCDD6F4, 0x89B4FA)

local function copy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = copy(v) end
    return o
end
T.copy = copy

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Returns a new theme: every field of T.default present with the right type, numbers clamped.
function T.fill(th, name)
    th = type(th) == "table" and th or {}
    local function merge(def, src)
        local o = {}
        for k, d in pairs(def) do
            local v = type(src) == "table" and src[k] or nil
            if type(d) == "table" then o[k] = merge(d, v)
            elseif type(v) == type(d) then o[k] = v
            else o[k] = d end
        end
        return o
    end
    local o = merge(T.default, th)
    o.name = name or o.name
    for k, v in pairs(o.colors) do o.colors[k] = math.floor(v) & 0xFFFFFF end
    o.button.color = math.floor(o.button.color) & 0xFFFFFF
    o.frame.color  = math.floor(o.frame.color) & 0xFFFFFF
    o.button.border = clamp(math.floor(o.button.border), 0, 3)
    o.frame.border  = clamp(math.floor(o.frame.border), 0, 3)
    o.font.size = clamp(o.font.size, 8, 40)
    for k, v in pairs(o.rounding) do o.rounding[k] = clamp(v, 0, 24) end
    o.alpha   = clamp(o.alpha, 0.3, 1)
    o.spacing = clamp(o.spacing, 0, 32)
    o.scale   = clamp(o.scale, 0.75, 2)
    return o
end

local function builtin() return T.fill(T.default, T.BUILTIN) end

-- Always returns a valid db; missing / corrupt file -> built-in only.
function T.load()
    local db
    local f = io.open(T.path, "r")
    if f then
        local src = f:read("a"); f:close()
        local ok, chunk = pcall(load, src, "themes", "t", {})
        if ok and chunk then
            local ok2, res = pcall(chunk)
            if ok2 and type(res) == "table" then db = res end
        end
    end
    local out = { current = T.BUILTIN, themes = {} }
    if db and type(db.themes) == "table" then
        for name, th in pairs(db.themes) do
            if type(name) == "string" and name ~= "" then out.themes[name] = T.fill(th, name) end
        end
        if type(db.current) == "string" then out.current = db.current end
    end
    out.themes[T.BUILTIN] = builtin()
    if not out.themes[out.current] then out.current = T.BUILTIN end
    return out
end

local function is_colour_key(path) return path:find("colors%.") or path:find("%.color$") end

local function ser(v, ind, path)
    if type(v) == "table" then
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys)
        local lines = {}
        for _, k in ipairs(keys) do
            local key = k:match("^[%a_][%w_]*$") and k or ("[%q]"):format(k)
            lines[#lines + 1] = ind .. "  " .. key .. " = " .. ser(v[k], ind .. "  ", path .. "." .. k) .. ","
        end
        return "{\n" .. table.concat(lines, "\n") .. "\n" .. ind .. "}"
    elseif type(v) == "string" then
        return ("%q"):format(v)
    elseif math.type(v) == "integer" and is_colour_key(path) then
        return ("0x%06X"):format(v)
    end
    return tostring(v)
end

-- Writes db atomically (tmp + rename) and bumps the live-reload rev. Returns true or nil, err.
function T.save(db)
    local out = { current = db.current, themes = {} }
    for name, th in pairs(db.themes or {}) do
        if name ~= T.BUILTIN then out.themes[name] = T.fill(th, name) end
    end
    out.themes[T.BUILTIN] = builtin()
    if not out.themes[out.current] then out.current = T.BUILTIN end

    R.RecursiveCreateDirectory(T.dir, 0)
    local tmp = T.path .. ".tmp"
    local f, err = io.open(tmp, "w")
    if not f then return nil, err end
    f:write("-- Lyx global themes (written by Lyx_Global theme manager)\nreturn ", ser(out, "", ""), "\n")
    f:close()
    local ok, err2 = os.rename(tmp, T.path)
    if not ok then -- Windows: rename does not overwrite
        os.remove(T.path)
        ok, err2 = os.rename(tmp, T.path)
        if not ok then return nil, err2 end
    end
    R.SetExtState(SECTION, "rev", os.time() .. "." .. math.random(1, 1e9), false)
    return true
end

-- Theme by name (current when nil), filled with defaults.
function T.get(name)
    local db = T.load()
    return db.themes[name or db.current] or db.themes[db.current]
end

function T.inherit(key) return R.GetExtState(SECTION, "inherit:" .. key) ~= "0" end
function T.set_inherit(key, on) R.SetExtState(SECTION, "inherit:" .. key, on and "1" or "0", true) end

-- True once each time another script saved the themes (first call only primes).
local last_rev
function T.changed()
    local rev = R.GetExtState(SECTION, "rev")
    if last_rev == nil then last_rev = rev; return false end
    if rev == last_rev then return false end
    last_rev = rev
    return true
end

function T.open_manager()
    local id = R.AddRemoveReaScript(true, 0, HERE .. "Lyx_Global theme manager.lua", true)
    if id ~= 0 then R.Main_OnCommand(id, 0) end
end

return T
