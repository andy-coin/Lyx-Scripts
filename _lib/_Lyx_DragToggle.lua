--[[
    _Lyx_DragToggle.lua  —  "drag to toggle" for any row / column of checkboxes
    (like holding solo or mute in a DAW mixer and sweeping across tracks).

    The rule (Andy's spec, see memory "drag-toggle-checkboxes"):
      1. Press on a box: remember EVERY box's state (snapshot), remember the
         box pressed (the lead) and its target = the opposite of its state.
         The lead flips at once.
      2. While the button is held, only the mouse coordinate along the axis
         matters (Y for a column, X for a row) - not whether the mouse is on
         a box, nor inside the window.
      3. Every frame the result is recomputed FROM THE SNAPSHOT: boxes whose
         span on the axis lies between the lead and the mouse take the
         target; every other box shows its snapshot state. So dragging back
         restores what was there, the lead stays flipped, and nothing ever
         toggles back and forth.
      4. Release: commit the last preview.
    No "which boxes have I passed" bookkeeping - that is what kept going wrong.

    usage:
        local DT = require("_lib._Lyx_DragToggle")
        -- on press over box `key` (states = {[key] = bool, ...}):
        drag = DT.begin(states, key)
        -- each frame while held; items = boxes taking part, in any order:
        --   { {key = k, lo = top_or_left, hi = bottom_or_right}, ... }
        local preview = DT.preview(drag, items, mouse_coord)
        -- on release: apply `preview`, then drag = nil
]]

local DT = {}

function DT.begin(states, lead)
    local orig = {}
    for k, v in pairs(states) do orig[k] = v and true or false end
    return {orig = orig, lead = lead, target = not orig[lead]}
end

-- Returns a full state table: snapshot, with the lead..mouse span set to the
-- target. The lead's position is read from `items` every frame, so it stays
-- right if the list scrolls during the drag.
function DT.preview(drag, items, mouse)
    local out = {}
    for k, v in pairs(drag.orig) do out[k] = v end
    out[drag.lead] = drag.target

    local lead_c
    for _, it in ipairs(items) do
        if it.key == drag.lead then lead_c = (it.lo + it.hi) / 2 break end
    end
    if not lead_c or not mouse then return out end

    local lo, hi = math.min(lead_c, mouse), math.max(lead_c, mouse)
    for _, it in ipairs(items) do
        if it.hi >= lo and it.lo <= hi then out[it.key] = drag.target end
    end
    return out
end

-- Self-check with the example from the spec: ten boxes on x = 1..10,
-- 1 / 4 / 7 on; press 3, drag to 8, back past 1, then to 6, release.
-- Run: lua _Lyx_DragToggle.lua
if not ... then
    local items, states = {}, {}
    for i = 1, 10 do
        items[#items + 1] = {key = i, lo = i - 0.5, hi = i + 0.5}
        states[i] = (i == 1 or i == 4 or i == 7)
    end
    local function on(t)
        local r = {}
        for i = 1, 10 do if t[i] then r[#r + 1] = i end end
        return table.concat(r, ',')
    end
    local d = DT.begin(states, 3)
    assert(on(DT.preview(d, items, 3)) == '1,3,4,7')        -- press: 3 on
    assert(on(DT.preview(d, items, 8)) == '1,3,4,5,6,7,8')  -- 5 6 8 on
    assert(on(DT.preview(d, items, -1)) == '1,2,3,4,7')     -- 8 6 5 off, 2 on
    local final = DT.preview(d, items, 6)                    -- 2 off, 5 6 on
    assert(on(final) == '1,3,4,5,6,7')
    -- lead in the middle, drag the other way: mirror image
    d = DT.begin(states, 5)
    assert(on(DT.preview(d, items, 2)) == '1,2,3,4,5,7')
    assert(on(DT.preview(d, items, 9)) == '1,4,5,6,7,8,9')
    -- turning off works the same way
    d = DT.begin(states, 4)
    assert(on(DT.preview(d, items, 8)) == '1')
    assert(on(DT.preview(d, items, 4)) == '1,7')
    print('_Lyx_DragToggle self-check ok')
end

return DT
