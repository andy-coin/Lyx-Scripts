--[[
    Track versions (fixed lanes) — create new version

    Naming of the new lane:
      "3"  (and "4" unused)       -> "4"
      "2"  (but "3" exists)       -> "2 - a", then "2 - b", ...
      "2 - a"                     -> next free letter of 2 ("2 - b" / "2 - c" ...)
      "Verse"  (not a number)     -> "Verse*", "Verse**", ...
      new empty lane at bottom    -> highest number + 1
]]
local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
package.path = package.path .. ";" .. script_path .. "?.lua"
local r = reaper and require("_Lyx_HOME")

---------------------------------------------------------------------------
-- Naming (pure)
---------------------------------------------------------------------------
local function next_name(src, names)
    local used = {}
    for _, n in ipairs(names) do used[n] = true end

    local function free_letter(n)
        for c = string.byte("a"), string.byte("z") do
            local s = n .. " - " .. string.char(c)
            if not used[s] then return s end
        end
        local s = n .. " - z*"
        while used[s] do s = s .. "*" end
        return s
    end

    local num = src:match("^%s*(%d+)%s*$")
    if num then
        local nxt = tostring(tonumber(num) + 1)
        if not used[nxt] then return nxt end
        return free_letter(tonumber(num))
    end
    local base = src:match("^%s*(%d+)%s*%-%s*%a+%s*$")
    if base then return free_letter(tonumber(base)) end

    local s = src .. "*"
    while used[s] do s = s .. "*" end
    return s
end

local function next_number(names)
    local mx = 0
    for _, n in ipairs(names) do
        local v = tonumber(n:match("^%s*(%d+)"))
        if v and v > mx then mx = v end
    end
    return tostring(mx + 1)
end

if not reaper then -- self-check: lua "Lyx_Track versions alternatve-create new version.lua"
    assert(next_name("3", { "1", "2", "3" }) == "4")
    assert(next_name("2", { "1", "2", "3" }) == "2 - a")
    assert(next_name("2", { "1", "2", "2 - a", "3" }) == "2 - b")
    assert(next_name("2 - a", { "2", "2 - a", "2 - b", "3" }) == "2 - c")
    assert(next_name("1", { "1", "3" }) == "2")
    assert(next_name("Verse", { "Verse" }) == "Verse*")
    assert(next_name("Verse", { "Verse", "Verse*" }) == "Verse**")
    assert(next_number({ "1", "2 - a", "Verse", "4" }) == "5")
    assert(next_number({}) == "1")
    return print("Track versions self-check OK")
end

---------------------------------------------------------------------------
local R = reaper
if not r.Need("SWS") then return end

local function lane_names(tr)
    local t = {}
    for i = 0, R.GetMediaTrackInfo_Value(tr, "I_NUMFIXEDLANES") - 1 do
        local _, n = R.GetSetMediaTrackInfo_String(tr, "P_LANENAME:" .. i, "", false)
        t[#t + 1] = n
    end
    return t
end

local function lane_label(names, i) -- 0-based; unnamed lanes count as their number
    local n = names[i + 1] or ""
    return (n ~= "") and n or tostring(i + 1)
end

local function playing_lane(tr)
    for i = 0, R.GetMediaTrackInfo_Value(tr, "I_NUMFIXEDLANES") - 1 do
        if R.GetMediaTrackInfo_Value(tr, "C_LANEPLAYS:" .. i) > 0 then return i end
    end
    return 0
end

local function set_lane_name(tr, i, name)
    R.GetSetMediaTrackInfo_String(tr, "P_LANENAME:" .. i, name, true)
end

local function show_in_track_name(tr, lane_name)
    local _, n = R.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    n = n:gsub("\30?   %[ .* %]", "") .. "\30   [ " .. lane_name .. " ]"
    R.GetSetMediaTrackInfo_String(tr, "P_NAME", n, true)
end

-- duplicate the lane under the mouse (new lane appears right below it)
local function duplicate_lane(tr)
    R.Main_OnCommand(42478, 0) -- play lane under mouse
    local src = playing_lane(tr)
    local before = lane_names(tr)
    R.Main_OnCommand(42505, 0) -- duplicate items to new lane
    R.Main_OnCommand(40421, 0) -- select all items on track
    R.Main_OnCommand(41613, 0) -- unpool
    R.Main_OnCommand(42469, 0) -- select item under mouse
    local new = src + 1
    local name = next_name(lane_label(before, src), before)
    set_lane_name(tr, new, name)
    R.SetMediaTrackInfo_Value(tr, "C_LANEPLAYS:" .. new, 1)
    return name
end

local function add_empty_lane(tr)
    local before = lane_names(tr)
    R.Main_OnCommand(42647, 0) -- add empty lane at bottom
    local n = R.GetMediaTrackInfo_Value(tr, "I_NUMFIXEDLANES")
    set_lane_name(tr, n - 1, next_number(before))
end

local function main()
    if R.CountSelectedTracks(0) > 1 then
        R.Main_OnCommand(42647, 0)
        return
    end
    local tr = R.GetSelectedTrack(0, 0)
    if not tr then return end

    R.BR_GetMouseCursorContext()
    local item = R.BR_GetMouseCursorContext_Item()
    local collapsed = R.GetMediaTrackInfo_Value(tr, "C_LANESCOLLAPSED") == 1
    local is_audio_input = R.GetMediaTrackInfo_Value(tr, "I_RECINPUT") < 4096

    if item and R.GetMediaItem_Track(item) == tr then
        if r.isMIDI(item) then
            R.Main_OnCommand(40639, 0) -- duplicate active take
            if R.GetToggleCommandState(40435) == 1 then R.Main_OnCommand(40435, 0) end
            return
        end
        show_in_track_name(tr, duplicate_lane(tr))
        return
    end

    if collapsed and not is_audio_input then
        show_in_track_name(tr, duplicate_lane(tr))
    else
        add_empty_lane(tr)
        show_in_track_name(tr, lane_label(lane_names(tr), playing_lane(tr)))
    end
end

R.Undo_BeginBlock2(0)
R.PreventUIRefresh(1)
main()
R.PreventUIRefresh(-1)
R.UpdateArrange()
R.Undo_EndBlock2(0, "Create new track version", -1)
