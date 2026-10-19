-- Move edit cursor to next item edge.
--   several items selected : step through their edges (across tracks, by time), selection unchanged
--   one item selected      : step through edges on its track, the item(s) reached become selected
--   no item, tracks selected: step through item edges on those tracks, selection unchanged
--   same track & lane, gap/overlap < JOIN_PX : one stop at the midpoint (selects both in one-item mode)
-- "previous edge" sets DIR = -1 and runs this file.

-----CUSTOM-----
move = true     -- scroll view to cursor
seek = false    -- seek playback
JOIN_PX = 2     -- junctions narrower than this (pixels) are a single stop
----------------

local DIR = DIR or 1
local EPS = 1e-6
local join = JOIN_PX / reaper.GetHZoomLevel()

local function info(item)
    local p = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    return { item = item, p = p, e = p + reaper.GetMediaItemInfo_Value(item, "D_LENGTH"),
             tr = reaper.GetMediaItem_Track(item), lane = reaper.GetMediaItemInfo_Value(item, "I_FIXEDLANE") }
end

local function joined(a, b) -- a before b, touching within JOIN_PX on same track & lane
    return a.tr == b.tr and a.lane == b.lane and math.abs(b.p - a.e) < join
end

local sel = {}
for i = 0, reaper.CountSelectedMediaItems(0) - 1 do sel[#sel + 1] = info(reaper.GetSelectedMediaItem(0, i)) end
table.sort(sel, function(a, b) return a.p < b.p end)

-- a junction pair picked by this script counts as "one item"
local follow = #sel == 1 or (#sel == 2 and joined(sel[1], sel[2]))

local pool = {}
if #sel > 0 and not follow then
    pool = sel
else
    local tracks = {}
    if follow then
        tracks[1] = sel[1].tr
    else
        for i = 0, reaper.CountSelectedTracks(0) - 1 do tracks[#tracks + 1] = reaper.GetSelectedTrack(0, i) end
    end
    if #tracks == 0 then
        reaper.Main_OnCommand(DIR > 0 and 41168 or 41167, 0) -- move cursor to nearest item edge
        return
    end
    for _, tr in ipairs(tracks) do
        for i = 0, reaper.CountTrackMediaItems(tr) - 1 do pool[#pool + 1] = info(reaper.GetTrackMediaItem(tr, i)) end
    end
    table.sort(pool, function(a, b) return a.p < b.p end)
end

-- edges; junctions collapse into one midpoint stop
local edges, prev = {}, {}
for _, a in ipairs(pool) do
    local key = tostring(a.tr) .. ":" .. a.lane
    local b = prev[key]
    if b and joined(b, a) then
        edges[#edges + 1] = { t = (b.e + a.p) / 2, items = { b.item, a.item } }
        b.e_done, a.p_done = true, true
    end
    prev[key] = a
end
for _, a in ipairs(pool) do
    if not a.p_done then edges[#edges + 1] = { t = a.p, items = { a.item } } end
    if not a.e_done then edges[#edges + 1] = { t = a.e, items = { a.item } } end
end

local cur = reaper.GetCursorPosition()
local best
for _, ed in ipairs(edges) do
    if (ed.t - cur) * DIR > EPS and (not best or (ed.t - best.t) * DIR < 0) then best = ed end
end
if not best then return end

reaper.PreventUIRefresh(1)
reaper.SetEditCurPos(best.t, move, seek)
if follow then
    reaper.SelectAllMediaItems(0, false)
    for _, ed in ipairs(edges) do
        if math.abs(ed.t - best.t) < EPS then
            for _, it in ipairs(ed.items) do reaper.SetMediaItemSelected(it, true) end
        end
    end
end
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
