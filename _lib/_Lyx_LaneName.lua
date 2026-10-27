-- Track versions: show the playing lane's name in the track name.
-- Position is set only by "Lyx_Track versions alternatve-create new version.lua"
-- (ExtState "Lyx" / "lane_name_position"); every other script just reads it.
--   -1 = hidden, 0 = "[ 2 ]   Vox", 1 = "Vox   [ 2 ]" (default)
local L = {}

function L.position()
    local p = tonumber(reaper.GetExtState("Lyx", "lane_name_position"))
    return (p == -1 or p == 0) and p or 1
end

function L.strip(name) -- remove a lane tag at either end (\30 = left by an older version)
    name = name:gsub("^%[ .- %]   ", ""):gsub("\30?   %[ .* %]$", "")
    return name
end

function L.playing(tr) -- 0-based, nil if no lane plays
    for i = 0, reaper.GetMediaTrackInfo_Value(tr, "I_NUMFIXEDLANES") - 1 do
        if reaper.GetMediaTrackInfo_Value(tr, "C_LANEPLAYS:" .. i) > 0 then return i end
    end
end

-- lane: 0-based lane to show; nil = only remove the tag
function L.show(tr, lane)
    local _, name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    name = L.strip(name)
    local p = L.position()
    if lane and p ~= -1 then
        local _, ln = reaper.GetSetMediaTrackInfo_String(tr, "P_LANENAME:" .. lane, "", false)
        if ln == "" then ln = tostring(lane + 1) end -- unnamed lane counts as its number
        name = (p == 0) and ("[ " .. ln .. " ]   " .. name) or (name .. "   [ " .. ln .. " ]")
    end
    reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true)
end

-- all tracks with lanes: show = true puts the tag back, false removes it (render / record)
function L.all(show)
    for i = 0, reaper.CountTracks(0) - 1 do
        local tr = reaper.GetTrack(0, i)
        if reaper.GetMediaTrackInfo_Value(tr, "I_NUMFIXEDLANES") > 1 then
            L.show(tr, show and L.playing(tr) or nil)
        end
    end
end

return L
