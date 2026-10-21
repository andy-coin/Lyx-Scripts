--[[
    _Lyx_Theme.lua  —  Lyx global theme storage (pure data, no ImGui).

    File: <REAPER resource>/Data/Lyx/themes.lua
          return { current = "Lyx Lake", themes = { ["Lyx Midnight"] = {...}, ... } }
    Colours are 0xRRGGBB integers. The presets in T.PRESETS (Moon, Forest, Lake, City, Midnight, Plain) always exist and are read-only.
    Every T.save() bumps ExtState "Lyx_Theme"/"rev" so running GUIs reload (see T.changed).

    usage:
        local T  = require("_lib._Lyx_Theme")
        local th = T.get()          -- current theme, every field filled
]]

local R = reaper
local T = {}
local SECTION = "Lyx_Theme"

T.BUILTIN = "Lyx Midnight"
local RENAMED = { ["Lyx Dark"] = "Lyx Midnight" } -- old preset names -> new
T.DEFAULT = "Lyx Lake"   -- theme used when none is chosen yet (or the chosen one was deleted)
T.dir  = R.GetResourcePath() .. "/Data/Lyx"
T.path = T.dir .. "/themes.lua"
local HERE = (debug.getinfo(1, "S").source:match("@?(.*[/\\])") or "./"):gsub("_lib[/\\]$", "") -- scripts live one folder up
repeat local n; HERE, n = HERE:gsub("[^/\\]+[/\\]%.%.[/\\]", "", 1) until n == 0 -- "X/../" -> "", so the Action List sees one path

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

T.default = T.derive(0x020B17, 0xC1CCDD, 0x6C89C7)

-- Read-only presets shipped with the scripts. Duplicate one to edit it.
T.PRESETS = { "Lyx Moon", "Lyx Forest", "Lyx Lake", "Lyx City", T.BUILTIN, "Lyx Plain" }
local preset_data = {
    -- Moon / Midnight / City / Plain: taken from Andy's VS Code screenshots
    ["Lyx Moon"] = {   -- light: cream paper, blue / olive ink, gold accent
        colors   = { bg = 0xFCF6E5, bg2 = 0xEDE8D7, base = 0xD8D2C4, title = 0x448BCD,
                     subtitle = 0x89972E, accent = 0xC1A44B, text = 0x3C7790 },
        button   = { color = 0xD8D2C4, border = 1 },
        frame    = { color = 0xEDE8D7, border = 1 },
        font     = { name = "", size = 15 },
        rounding = { window = 6, button = 3, frame = 3 },
        alpha = 1, spacing = 9, scale = 0.9,
    },
    ["Lyx Midnight"] = {   -- near-black navy, sand title, soft blue accent
        colors   = { bg = 0x020B17, bg2 = 0x071434, base = 0x2E3C5B, title = 0xD8BC8F,
                     subtitle = 0x52A751, accent = 0x6C89C7, text = 0xC1CCDD },
        button   = { color = 0x0F2A67, border = 1 },
        frame    = { color = 0x0D214D, border = 1 },
        font     = { name = "", size = 14 },
        rounding = { window = 8, button = 6, frame = 6 },
        alpha = 1, spacing = 8, scale = 1,
    },
    ["Lyx City"] = {   -- denim blue, pastel peach / lilac
        colors   = { bg = 0x09254E, bg2 = 0x041731, base = 0x0F356A, title = 0xF7C797,
                     subtitle = 0xE3BEFB, accent = 0x2B6398, text = 0xC1DAFC },
        button   = { color = 0x2B6398, border = 1 },
        frame    = { color = 0x041731, border = 1 },
        font     = { name = "", size = 15 },
        rounding = { window = 6, button = 3, frame = 3 },
        alpha = 1, spacing = 9, scale = 0.9,
    },
    ["Lyx Plain"] = {   -- neutral greys, burnt orange title
        colors   = { bg = 0x1E1E1E, bg2 = 0x282828, base = 0x353535, title = 0xC26C27,
                     subtitle = 0x9DA74C, accent = 0x6889B1, text = 0xD4D4D4 },
        button   = { color = 0x505050, border = 0 },
        frame    = { color = 0x303030, border = 0 },
        font     = { name = "", size = 15 },
        rounding = { window = 6, button = 3, frame = 3 },
        alpha = 1, spacing = 9, scale = 0.9,
    },
    ["Lyx Lake"] = {
        colors   = { bg = 0x0C2C42, bg2 = 0x172B3A, base = 0x195172, title = 0xE1BB48,
                     subtitle = 0x1CD7D5, accent = 0xB5973C, text = 0xE6ECFF },
        button   = { color = 0xA27E11, border = 1 },
        frame    = { color = 0x414B5A, border = 1 },
        font     = { name = "", size = 15 },
        rounding = { window = 11, button = 5, frame = 5 },
        alpha = 0.95, spacing = 10, scale = 0.9,
    },
    -- ReaLauncher (Lyx mod) colours: deep teal ground, olive fill, amber text
    ["Lyx Forest"] = {
        colors   = { bg = 0x022028, bg2 = 0x03272F, base = 0x3D4A3C, title = 0xE0952A,
                     subtitle = 0xB5A971, accent = 0x79714F, text = 0xE0952A },
        button   = { color = 0x0B3A44, border = 1 },
        frame    = { color = 0x03272F, border = 1 },
        font     = { name = "", size = 15 },
        rounding = { window = 6, button = 3, frame = 3 },
        alpha = 1, spacing = 9, scale = 0.9,
    },
}
function T.preset(name) return T.fill(preset_data[name] or T.default, name) end

function T.is_builtin(name)
    for _, n in ipairs(T.PRESETS) do if n == name then return true end end
    return false
end

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

local function add_presets(themes)
    for _, n in ipairs(T.PRESETS) do themes[n] = T.fill(preset_data[n] or T.default, n) end
end

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
    local out = { current = T.DEFAULT, themes = {} }
    if db and type(db.themes) == "table" then
        for name, th in pairs(db.themes) do
            if type(name) == "string" and name ~= "" and not RENAMED[name] then out.themes[name] = T.fill(th, name) end
        end
        if type(db.current) == "string" then out.current = RENAMED[db.current] or db.current end
    end
    add_presets(out.themes)
    if not out.themes[out.current] then out.current = T.DEFAULT end
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
        if not T.is_builtin(name) then out.themes[name] = T.fill(th, name) end
    end
    add_presets(out.themes)
    if not out.themes[out.current] then out.current = T.DEFAULT end

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
