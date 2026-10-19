--[[
    _Lyx_FXState.lua — engine for "Lyx_Copy focus FX state" / "Lyx_Paste focus FX state".

    Works on the focused FX in any location: track FX, take FX, master FX,
    monitor FX, record-input FX.

    Paste strategy (best first):
      1. same plugin + same format, VST/VST3/CLAP  -> full plugin chunk (vst_chunk / clap_chunk)
      2. same plugin + same format, AU/LV2/JS...   -> swap FX block inside track/item chunk
                                                      (not possible for monitor FX -> step 3)
      3. anything else (cross-format, other name)  -> match parameters by name (normalized values)
                                                      fallback: by index when counts match
]]

local R = reaper
local M = {}
local SEC = "LYX_Copy_FX_Data"

local function say(s, sec) if BBB then BBB(s, sec or 1.5) else R.ShowConsoleMsg(s .. "\n") end end

-- "VST3: Pro-Q 3 (FabFilter)" -> "proq3"
local function norm_name(n)
    n = n:gsub("^%u+%d?i?:%s*", "")
    n = n:gsub("%s*%b()%s*$", "")
    n = n:gsub("%s*%b()%s*$", "")
    return (n:lower():gsub("[^%w]", ""))
end

local function family(t) return (t or ""):gsub("i$", "") end

local function chunk_key(fam)
    if fam == "VST" or fam == "VST3" then return "vst_chunk" end
    if fam == "CLAP" then return "clap_chunk" end
end

---------------------------------------------------------------------------
-- Focused FX handle
---------------------------------------------------------------------------
local FN = { "GetNumParams", "GetParamName", "GetParamNormalized", "SetParamNormalized",
             "GetNamedConfigParm", "SetNamedConfigParm", "GetFXGUID" }

local function focused()
    local ok, tri, iti, tki, fx = R.GetTouchedOrFocusedFX(1)
    if not ok or fx < 0 then return end
    local tr = (tri == -1) and R.GetMasterTrack(0) or R.GetTrack(0, tri)
    if not tr then return end

    local o = { fx = fx, track = tr }
    local prefix, obj
    if iti >= 0 then
        local it = R.GetTrackMediaItem(tr, iti)
        local tk = it and R.GetMediaItemTake(it, tki)
        if not tk then return end
        o.item, o.take, obj, prefix = it, tk, tk, "TakeFX_"
    else
        obj, prefix = tr, "TrackFX_"
    end
    for _, f in ipairs(FN) do
        local api = R[prefix .. f]
        o[f] = function(...) return api(obj, fx, ...) end
    end

    local _, name = o.GetNamedConfigParm("fx_name")
    local _, ftype = o.GetNamedConfigParm("fx_type")
    o.name, o.key, o.family = name, norm_name(name), family(ftype)
    o.in_container = (fx & 0x2000000) ~= 0 or ftype == "Container"
    -- monitor FX live outside the project chunk
    o.chunk_ok = not o.in_container and not (tri == -1 and iti < 0 and (fx & 0x1000000) ~= 0)
    return o
end

---------------------------------------------------------------------------
-- FX block inside a track / item state chunk (anchored on "FXID {guid}")
---------------------------------------------------------------------------
local function get_chunk(o)
    if o.item then return select(2, R.GetItemStateChunk(o.item, "", false)) end
    return select(2, R.GetTrackStateChunk(o.track, "", false))
end

local function set_chunk(o, c)
    if o.item then return R.SetItemStateChunk(o.item, c, false) end
    return R.SetTrackStateChunk(o.track, c, false)
end

-- returns start, end (inclusive) of the "<PLUGIN ... >" block of this FX
local function find_block(chunk, guid)
    local g = chunk:find("FXID " .. guid, 1, true)
    if not g then return end
    local b, pos = nil, 1
    while true do
        local s = chunk:find("\nBYPASS ", pos, true)
        if not s or s > g then break end
        b, pos = s, s + 1
    end
    if not b then return end
    local s = chunk:find("\n<", b, true)
    if not s or s > g then return end
    local e = chunk:find("\n>", s + 1, true)
    if not e or e > g then return end
    return s + 1, e + 1
end

---------------------------------------------------------------------------
-- Parameters (REAPER appends Wet / Bypass / Delta as the last 3 params)
---------------------------------------------------------------------------
local REAPER_EXTRA = { Bypass = true, Wet = true, Delta = true }

local function read_params(o)
    local cnt = o.GetNumParams()
    local t = {}
    for i = 0, cnt - 1 do
        local _, pn = o.GetParamName(i)
        if not (i >= cnt - 3 and REAPER_EXTRA[pn]) then
            t[#t + 1] = { name = pn, val = o.GetParamNormalized(i) }
        end
    end
    return t
end

local function serialize_params(t)
    local out = {}
    for i, p in ipairs(t) do out[i] = p.name:gsub("[\t\n]", " ") .. "\t" .. string.format("%.10f", p.val) end
    return table.concat(out, "\n")
end

local function parse_params(s)
    local t = {}
    for line in s:gmatch("[^\n]+") do
        local n, v = line:match("^(.-)\t([%d%.%-eE]+)$")
        if n then t[#t + 1] = { name = n, val = tonumber(v) } end
    end
    return t
end

local function apply_params(o, src)
    local dst = read_params(o)
    local idx = {}
    for i, p in ipairs(dst) do
        local k = p.name:lower()
        if idx[k] == nil then idx[k] = i - 1 end
    end
    local hit = 0
    for _, p in ipairs(src) do
        local i = idx[p.name:lower()]
        if i then o.SetParamNormalized(i, p.val); hit = hit + 1 end
    end
    if hit == 0 and #src == #dst then
        for i, p in ipairs(src) do o.SetParamNormalized(i - 1, p.val) end
        return #src, #src, "by index"
    end
    return hit, #src, "by name"
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------
function M.copy()
    local o = focused()
    if not o then return say("No focused FX.") end

    R.SetExtState(SEC, "name", o.name, false)
    R.SetExtState(SEC, "key", o.key, false)
    R.SetExtState(SEC, "family", o.family, false)
    R.SetExtState(SEC, "params", serialize_params(read_params(o)), false)

    local kind, data = "", ""
    local ck = chunk_key(o.family)
    if ck and not o.in_container then
        local ok, c = o.GetNamedConfigParm(ck)
        if ok and c ~= "" then kind, data = ck, c end
    end
    if kind == "" and o.chunk_ok then
        local chunk = get_chunk(o)
        local s, e = find_block(chunk, o.GetFXGUID())
        if s then kind, data = "block", chunk:sub(s, e) end
    end
    R.SetExtState(SEC, "kind", kind, false)
    R.SetExtState(SEC, "chunk", data, false)
    R.DeleteExtState(SEC, "buf_params", false) -- legacy key from v1

    local short = o.name:gsub("^%u+%d?i?:%s*", "")
    say("Copied: " .. short .. ((kind ~= "" and "  (full state)") or "  (parameters)"))
end

function M.paste()
    local src_name = R.GetExtState(SEC, "name")
    if src_name == "" then return say("Nothing copied yet.") end
    local o = focused()
    if not o then return say("No focused FX.") end

    local src_key, src_fam = R.GetExtState(SEC, "key"), R.GetExtState(SEC, "family")
    local kind, data = R.GetExtState(SEC, "kind"), R.GetExtState(SEC, "chunk")
    local params = parse_params(R.GetExtState(SEC, "params"))

    if src_key ~= o.key then
        local q = ("Source:  %s\nTarget:  %s\n\nDifferent plug-ins. Paste parameters with matching names anyway?")
                  :format(src_name, o.name)
        if R.MB(q, "Paste FX state", 4) ~= 6 then return end
    end

    R.Undo_BeginBlock()
    local done
    if src_key == o.key and src_fam == o.family and data ~= "" then
        if kind ~= "block" and not o.in_container then
            done = o.SetNamedConfigParm(kind, data)
        elseif kind == "block" and o.chunk_ok then
            local chunk = get_chunk(o)
            local s, e = find_block(chunk, o.GetFXGUID())
            if s then done = set_chunk(o, chunk:sub(1, s - 1) .. data .. chunk:sub(e + 1)) end
        end
    end

    local short = o.name:gsub("^%u+%d?i?:%s*", "")
    if done then
        say("Pasted full state → " .. short)
    else
        local hit, total, how = apply_params(o, params)
        say(("Pasted %d/%d params %s → %s"):format(hit, total, how, short), 2)
    end
    R.Undo_EndBlock("Paste FX state", -1)
end

-- self-check (run with plain Lua): lua _Lyx_FXState.lua
if not R then
    assert(norm_name("VST3: Pro-Q 3 (FabFilter)") == "proq3")
    assert(norm_name("AUi: Kontakt 8 (Native Instruments)") == "kontakt8")
    assert(norm_name("CLAP: Pro-Q 3 (FabFilter) (x64)") == "proq3")
    assert(family("VST3i") == "VST3" and family("AU") == "AU")
    local c = "X\nBYPASS 0 0 0\n<AU \"AU: A\"\nQUJD\n>\nFLOATPOS 0 0 0 0\nFXID {G1}\nWAK 0 0\nBYPASS 0 0 0\n<JS foo\n1 2\n>\nFXID {G2}\n"
    local s, e = find_block(c, "{G2}")
    assert(c:sub(s, e) == "<JS foo\n1 2\n>")
    s, e = find_block(c, "{G1}")
    assert(c:sub(s, e) == "<AU \"AU: A\"\nQUJD\n>")
    local p = parse_params(serialize_params({ { name = "Gain", val = 0.25 }, { name = "Q\tx", val = 1 } }))
    assert(#p == 2 and p[1].val == 0.25 and p[2].name == "Q x")
    print("FXState self-check OK")
end

return M
