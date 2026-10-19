--[[
    Create fade or crossfade
      * Razor areas : fade-in / fade-out at the razor edges, crossfade when the
                      area spans a junction of two items in the same lane.
      * No razor    : selected items get fade-in / fade-out of the length set by
                      "Lyx_Adjust fade length" (ExtState fade_length); touching
                      neighbours in the same lane become a crossfade.
    Only items visible on screen are processed.  Engine: _Lyx_Fade.lua
]]
local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
package.path = package.path .. ";" .. script_path .. "?.lua"
require("_lib._Lyx_HOME")
local F = require("_lib._Lyx_Fade")
local R = reaper

local TOUCH = 0.001 -- gap (s) still treated as "touching"

---------------------------------------------------------------------------
-- Razor
---------------------------------------------------------------------------
local function razor_area(a)
    local s, e = a.s, a.e
    local lanes, all = F.area_lanes(a)
    local crossed = {}

    for _, items in ipairs(lanes) do
        for i = 2, #items do
            local A, B = items[i - 1], items[i]
            local a_pos, a_end = F.bounds(A)
            local b_pos, b_end = F.bounds(B)
            if s >= a_pos and s <= a_end and e >= b_pos and e <= b_end then
                local target
                if a_end + TOUCH >= b_pos then
                    -- already overlapping: use the natural crossing point
                    local nat = F.crossover(A, B, a_end, b_pos)
                    local skip = (s < a_pos and e > nat) or (s < nat and e > b_end)
                              or (s > a_pos and e < nat) or (s > nat and e < b_end)
                    if skip then
                        target = nil
                    elseif e < nat then                     -- fade-in only
                        F.fade_in(A, e - a_pos)
                        if b_pos < e then F.edges(B, e, b_end) end
                        target = nat
                    elseif s > nat then                     -- fade-out only
                        F.fade_out(B, b_end - s)
                        if a_end > s then F.edges(A, a_pos, s) end
                        target = nat
                    else                                    -- real crossfade over the area
                        if s < a_pos + F.max_in(A) then F.fade_in(A, s - a_pos) end
                        if e > b_end - F.max_out(B) then F.fade_out(B, b_end - e) end
                        F.edges(A, a_pos, e)
                        F.edges(B, s, b_end)
                        F.fade_out(A, e - s)
                        F.fade_in(B, e - s)
                        target = F.crossover(A, B, a_end, b_pos)
                    end
                elseif (b_pos - a_end) * R.GetHZoomLevel() <= 2 then
                    -- gap of ≤2 px counts as butted: build the overlap
                    F.edges(A, a_pos, e)
                    F.edges(B, s, b_end)
                    F.fade_out(A, e - s)
                    F.fade_in(B, e - s)
                    target = F.crossover(A, B, a_end, b_pos)
                end
                if target then
                    F.set_dir(A, B, target)
                    crossed[A], crossed[B] = true, true
                end
            end
        end
    end

    for _, it in ipairs(all) do
        if not crossed[it] then
            local p, ep = F.bounds(it)
            local p_in, e_in = p >= s and p <= e, ep >= s and ep <= e
            if p_in and not e_in then
                F.fade_in(it, e - p)
            elseif e_in and not p_in then
                F.fade_out(it, ep - s)
            end
        end
    end
end

---------------------------------------------------------------------------
-- No razor
---------------------------------------------------------------------------
local function fade_size()
    local v = tonumber(R.GetExtState("fade_length", "fade_length")) or 10
    return (R.GetExtState("fade_length", "length_unit") == "s") and v or v / 1000
end

-- a's end and b's start meet in the middle with an overlap of 2*fs
local function crossfade(a, b, fs)
    local ap, ae = F.bounds(a)
    local bp, be = F.bounds(b)
    local c = (ae + bp) / 2
    R.SetMediaItemInfo_Value(a, "D_LENGTH", c + fs - ap)
    F.edges(b, c - fs, be)
    R.SetMediaItemInfo_Value(a, "D_FADEOUTLEN_AUTO", fs * 2)
    R.SetMediaItemInfo_Value(b, "D_FADEINLEN_AUTO",  fs * 2)
end

local function normal(items)
    local fs = fade_size()
    local m, M = F.view()
    local function vis(t) return t > m and t < M end
    local joined = {} -- joined[a] = b once a|b crossfaded

    for _, it in ipairs(items) do
        local P, E, L = F.bounds(it)
        if F.visible_y(it) and fs <= L / 2 then
            if vis(P) then
                local pre = F.neighbor(it, -1)
                local pre_e = pre and select(2, F.bounds(pre))
                if pre and P <= pre_e + TOUCH then
                    if joined[pre] ~= it then crossfade(pre, it, fs); joined[pre] = it end
                else
                    F.fade_in(it, fs)
                end
            end
            P, E = F.bounds(it)
            if vis(E) then
                local nxt = F.neighbor(it, 1)
                local nxt_p = nxt and F.bounds(nxt)
                if nxt and E >= nxt_p - TOUCH then
                    if joined[it] ~= nxt then crossfade(it, nxt, fs); joined[it] = nxt end
                else
                    F.fade_out(it, fs)
                end
            end
        end
    end
end

---------------------------------------------------------------------------
F.wrap("Create fade or crossfade to selected item(s)", function()
    local areas = F.razor_areas()
    if #areas > 0 then
        for _, a in ipairs(areas) do razor_area(a) end
        R.Main_OnCommand(42406, 0) -- clear razor edits
    else
        normal(F.selected_items())
    end
end)
