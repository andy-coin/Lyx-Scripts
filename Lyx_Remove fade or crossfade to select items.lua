--[[
    Remove fade or crossfade
      * Razor areas : crossfades whose junction the area spans are split at the
                      crossing point; fades touched by the area are cleared.
      * No razor    : selected items — their crossfades with same-lane
                      neighbours and their fades are cleared.
    Only items visible on screen are processed.  Engine: _Lyx_Fade.lua
]]
local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
package.path = package.path .. ";" .. script_path .. "?.lua"
require("_lib._Lyx_HOME")
local F = require("_lib._Lyx_Fade")
local R = reaper

-- split an overlapping pair at the crossing point and clear both fades
local function remove_crossfade(a, b)
    local a_pos, a_end = F.bounds(a)
    local b_pos, b_end = F.bounds(b)
    if a_end <= b_pos then return false end
    local x = math.max(b_pos, math.min(a_end, F.crossover(a, b, a_end, b_pos)))
    F.edges(a, a_pos, x)
    F.edges(b, x, b_end)
    F.clear_out(a)
    F.clear_in(b)
    return true
end

local function clear_touched(it, s, e)
    local pos, ep = F.bounds(it)
    local fin, fout = F.max_in(it), F.max_out(it)
    if fin > 0 and s < pos + fin and e > pos then F.clear_in(it) end
    if fout > 0 and s < ep and e > ep - fout then F.clear_out(it) end
end

local function razor_area(a)
    local s, e = a.s, a.e
    local lanes, all = F.area_lanes(a)
    local done = {}
    for _, items in ipairs(lanes) do
        for i = 2, #items do
            local A, B = items[i - 1], items[i]
            local a_pos, a_end = F.bounds(A)
            local b_pos, b_end = F.bounds(B)
            if s >= a_pos and s <= a_end and e >= b_pos and e <= b_end and remove_crossfade(A, B) then
                done[A], done[B] = true, true
            end
        end
    end
    for _, it in ipairs(all) do
        if not done[it] then clear_touched(it, s, e) end
    end
end

local function normal()
    local m, M = F.view()
    local items, done = {}, {}
    for _, it in ipairs(F.selected_items()) do
        local pos, ep = F.bounds(it)
        if ep > m and pos < M and F.visible_y(it) then items[#items + 1] = it end
    end

    local function try_pair(a, b)
        if done[a] or done[b] then return end
        local _, a_end = F.bounds(a)
        local b_pos = F.bounds(b)
        if a_end > m and b_pos < M and remove_crossfade(a, b) then done[a], done[b] = true, true end
    end
    for _, it in ipairs(items) do
        local prev, nxt = F.neighbor(it, -1), F.neighbor(it, 1)
        if prev then try_pair(prev, it) end
        if nxt then try_pair(it, nxt) end
    end

    for _, it in ipairs(items) do clear_touched(it, m, M) end
end

F.wrap("Remove fade/crossfade to selected items", function()
    local areas = F.razor_areas()
    if #areas > 0 then
        for _, a in ipairs(areas) do razor_area(a) end
        R.Main_OnCommand(42406, 0) -- clear razor edits
    else
        normal()
    end
end)
