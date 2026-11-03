-- Track versions: show the playing lane's name in the track name.
-- Position / style are set only by "Lyx_Track versions alternatve-create new version.lua"
-- (ExtState "Lyx" / "lane_name_position", "lane_name_style"); every other script just reads them.
--   position: -1 = hidden, 0 = at the start, 1 = at the end (default)
--   style:    "｜" = "Vox ｜ 2" (default), "()" = "Vox   ( 2 )", "[]" = "Vox   [ 2 ]"
local L = {}

function L.position()
    local p = tonumber(reaper.GetExtState("Lyx", "lane_name_position"))
    return (p == -1 or p == 0) and p or 1
end

function L.style()
    local s = reaper.GetExtState("Lyx", "lane_name_style")
    return (s == "()" or s == "[]") and s or "｜"
end

local function tag(ln, p, s)
    if s == "｜" then return (p == 0) and (ln .. " ｜ ") or (" ｜ " .. ln) end
    local o, c = s:sub(1, 1), s:sub(2, 2)
    return (p == 0) and (o .. " " .. ln .. " " .. c .. "   ") or ("   " .. o .. " " .. ln .. " " .. c)
end

-- remove a lane tag: () / [] at either end (\30 = left by an older version);
-- "｜" only on the current position's side (a bar alone can't tell start from end)
function L.strip(name)
    name = name:gsub("^[%[%(] .- [%]%)]   ", ""):gsub("\30?   [%[%(] .* [%]%)]$", "")
    if L.position() == 0 then
        name = name:gsub("^.- ｜ ", "", 1)
    else
        name = name:match("^(.*) ｜ ") or name
    end
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
        local t = tag(ln, p, L.style())
        name = (p == 0) and (t .. name) or (name .. t)
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
