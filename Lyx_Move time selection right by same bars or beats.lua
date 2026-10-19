-- Move the time selection by its own length, next to where it was.
--   Both edges on bar lines  -> move by the same number of bars (follows time-signature changes)
--   Both edges on grid lines -> move by the same length in quarter notes (follows tempo changes)
--   Otherwise                -> move by the same length in seconds
-- The left and right scripts are identical except for DIR.
local DIR = 1 -- -1 = left, 1 = right

-- "On the line" = within 1 pixel at the current arrange zoom (absorbs floating-point error
-- and hand-placed edges that look snapped). Edges counted as on a line are moved from the line itself.
local PX  = 1
local TOL = PX / reaper.GetHZoomLevel() -- seconds per pixel

local function near(x, y) return math.abs(x - y) <= TOL end

local function closest_grid(pos)
    if reaper.BR_GetClosestGridDivision then return reaper.BR_GetClosestGridDivision(pos) end -- SWS: ignores snap/zoom
    -- No SWS: SnapToGrid only works while snap is enabled, so enable it briefly
    reaper.Main_OnCommand(40755, 0) -- Snapping: Save snap state
    reaper.Main_OnCommand(40754, 0) -- Snapping: Enable snap
    local g = reaper.SnapToGrid(0, pos)
    reaper.Main_OnCommand(40756, 0) -- Snapping: Restore snap state
    return g
end

local function bar_at(pos) -- measure index if pos sits on a bar line, else nil
    local _, m = reaper.TimeMap2_timeToBeats(0, pos)
    for i = m, m + 1 do -- pos may be a hair before the next bar line
        if i >= 0 and near(reaper.TimeMap_GetMeasureInfo(0, i), pos) then return i end
    end
end

local function main()
    local a, b = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    if b - a < 1e-9 then return end -- no time selection

    local new_a, new_b
    local bar_a, bar_b = bar_at(a), bar_at(b)
    if bar_a and bar_b then
        local n = (bar_b - bar_a) * DIR
        if bar_a + n < 0 then return end -- would start before the project start
        new_a = reaper.TimeMap_GetMeasureInfo(0, bar_a + n)
        new_b = reaper.TimeMap_GetMeasureInfo(0, bar_b + n)
    end
    local ga, gb = closest_grid(a), closest_grid(b)
    if new_a then -- bars
    elseif near(a, ga) and near(b, gb) and gb > ga then
        local qa, qb = reaper.TimeMap2_timeToQN(0, ga), reaper.TimeMap2_timeToQN(0, gb)
        local d = (qb - qa) * DIR
        if qa + d < -1e-6 then return end
        new_a = reaper.TimeMap2_QNToTime(0, qa + d)
        new_b = reaper.TimeMap2_QNToTime(0, qb + d)
    else
        local d = (b - a) * DIR
        if a + d < -1e-6 then return end
        new_a, new_b = a + d, b + d
    end

    -- the touching edge stays exactly where the old selection was (no round-trip drift);
    -- in bars/beats mode that is the line the old edge sat on
    local touch = (DIR < 0) and a or b
    if bar_a and bar_b then touch = reaper.TimeMap_GetMeasureInfo(0, DIR < 0 and bar_a or bar_b)
    elseif near(a, ga) and near(b, gb) and gb > ga then touch = (DIR < 0) and ga or gb end
    if DIR < 0 then new_b = touch else new_a = touch end
    reaper.GetSet_LoopTimeRange2(0, true, false, math.max(new_a, 0), new_b, false)
end

reaper.defer(main) -- defer = no undo point (time selection changes are not undoable by default)
