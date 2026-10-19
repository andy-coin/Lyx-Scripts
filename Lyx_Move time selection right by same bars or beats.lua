-- Move the time selection by its own length, next to where it was.
--   Both edges on bar lines  -> move by the same number of bars (follows time-signature changes)
--   Both edges on grid lines -> move by the same length in quarter notes (follows tempo changes)
--   Otherwise                -> move by the same length in seconds
-- The left and right scripts are identical except for DIR.
local DIR = 1 -- -1 = left, 1 = right

local TOL = 1e-5 -- seconds (~half a sample at 48 kHz): absorbs floating-point error in "is it on the line?"

local function near(x, y) return math.abs(x - y) < TOL end

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
        if near(reaper.TimeMap_GetMeasureInfo(0, i), pos) then return i end
    end
end

local function main()
    local a, b = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    if b - a < TOL then return end -- no time selection

    local new_a, new_b
    local bar_a, bar_b = bar_at(a), bar_at(b)
    if bar_a and bar_b then
        local n = (bar_b - bar_a) * DIR
        if bar_a + n < 0 then return end -- would start before the project start
        new_a = reaper.TimeMap_GetMeasureInfo(0, bar_a + n)
        new_b = reaper.TimeMap_GetMeasureInfo(0, bar_b + n)
    elseif near(a, closest_grid(a)) and near(b, closest_grid(b)) then
        local qa, qb = reaper.TimeMap2_timeToQN(0, a), reaper.TimeMap2_timeToQN(0, b)
        local d = (qb - qa) * DIR
        if qa + d < -1e-9 then return end
        new_a = reaper.TimeMap2_QNToTime(0, qa + d)
        new_b = reaper.TimeMap2_QNToTime(0, qb + d)
    else
        local d = (b - a) * DIR
        if a + d < -TOL then return end
        new_a, new_b = a + d, b + d
    end

    -- the touching edge stays exactly where the old selection was (no round-trip drift)
    if DIR < 0 then new_b = a else new_a = b end
    reaper.GetSet_LoopTimeRange2(0, true, false, math.max(new_a, 0), new_b, false)
end

reaper.defer(main) -- defer = no undo point (time selection changes are not undoable by default)
