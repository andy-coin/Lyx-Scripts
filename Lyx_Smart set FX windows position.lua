local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
package.path = package.path..";"..script_path.."?.lua"
local r = require("_Lyx_HOME")

-- ── Config ────────────────────────────────────────────────────────────────────
local Config = {
    start_x     = 525,   -- first window X (px from screen left)
    start_y     = 1325,  -- first window Y (px from screen bottom; clears macOS menubar)
    gap         = 2,  -- shelf mode spacing (px)
    title_bar_h = 16,  -- stagger step per window (px)
}

local NS        = "Lyx_FX_Cycle"
local KEY_STATE = "state"
local KEY_COUNT = "count"

-- ── Collect open floating FX windows ─────────────────────────────────────────
local function collect_fx_windows()
    local wins = {}
    local function add(hwnd)
        if not hwnd then return end
        local _, l, t, rr, b = reaper.JS_Window_GetRect(hwnd)
        wins[#wins+1] = { hwnd = hwnd, w = rr - l, h = t - b }  -- t > b (macOS Y 向上)
    end
    local master = reaper.GetMasterTrack(0)
    for fx = 0, reaper.TrackFX_GetCount(master) - 1 do
        add(reaper.TrackFX_GetFloatingWindow(master, fx))
    end
    for ti = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, ti)
        for fx = 0, reaper.TrackFX_GetCount(track) - 1 do
            add(reaper.TrackFX_GetFloatingWindow(track, fx))
        end
    end
    return wins
end

-- ── Shelf layout (skyline / masonry, no resize) ──────────────────────────────
-- Each window's Y = bottom of the window directly above it + gap (skyline packing).
-- Windows in the first row start at oy. Gap-fill lookahead fills horizontal remnants.
local function shelf_layout(wins, sw, sh)
    local gap    = Config.gap
    local ox, oy = Config.start_x, Config.start_y
    local pos    = {}
    local placed = {}  -- {x, y (top), w, h} of all placed windows

    -- Find the top-Y for a new window at horizontal range [wx, wx+ww].
    -- = (lowest bottom among overlapping placed windows) - gap
    -- = oy if nothing placed above yet.
    local function get_y(wx, ww)
        local min_bot = nil
        for _, p in ipairs(placed) do
            if p.x < wx + ww and p.x + p.w > wx then
                local bot = p.y - p.h
                if min_bot == nil or bot < min_bot then min_bot = bot end
            end
        end
        return (min_bot == nil) and oy or (min_bot - gap)
    end

    local function place(idx, x)
        local win = wins[idx]
        local y   = get_y(x, win.w)
        pos[idx]  = { x = x, y = y }
        placed[#placed+1] = { x = x, y = y, w = win.w, h = win.h }
        return x + win.w + gap
    end

    local queue = {}
    for i = 1, #wins do queue[#queue+1] = i end

    local x = ox
    while #queue > 0 do
        local idx = queue[1]
        local win = wins[idx]

        if x + win.w > sw and x > ox then
            -- Current window doesn't fit; try gap-fill lookahead before wrapping
            local rem = sw - x
            local j   = 2
            while j <= #queue and rem > gap do
                local jidx = queue[j]
                local jwin = wins[jidx]
                if jwin.w <= rem - gap then
                    x   = place(jidx, x)
                    rem = sw - x
                    table.remove(queue, j)
                else
                    j = j + 1
                end
            end
            x = ox  -- wrap to next row
        end

        x = place(idx, x)
        table.remove(queue, 1)
    end

    return pos
end

-- ── Stagger order for cycle state k ──────────────────────────────────────────
-- TL→BR placement: [k-1, k-2, ..., 1,  N, N-1, ..., k]
--   • Windows k-1..1  fill the left/top (previous featured slides left each cycle)
--   • Windows N..k+1  fill the middle in descending order
--   • Window k        is featured at the bottom-right (最前)
local function stagger_order(N, k)
    local order = {}
    for i = k - 1, 1, -1 do order[#order+1] = i end
    for i = N, k,   -1 do order[#order+1] = i end
    return order
end

-- ── Apply stagger positions ───────────────────────────────────────────────────
local function apply_stagger(wins, k)
    local step   = Config.title_bar_h
    local ox, oy = Config.start_x, Config.start_y
    local order  = stagger_order(#wins, k)
    local pos    = {}
    for p, win_idx in ipairs(order) do
        pos[win_idx] = { x = ox + (p-1)*step, y = oy - (p-1)*step }
    end
    return pos, order
end

-- ── Main ──────────────────────────────────────────────────────────────────────
local function main()
    local sw, sh = r.GetScreenResolution()
    local wins   = collect_fx_windows()

    if #wins == 0 then
        reaper.SetExtState(NS, KEY_STATE, "0", false)
        reaper.SetExtState(NS, KEY_COUNT, "0", false)
        api.cmd(api.name('_RS52f724102d8619b6f87ef3a978e4adb0537d364d'),0)
        return
    end

    local N     = #wins
    local state = tonumber(reaper.GetExtState(NS, KEY_STATE)) or 0
    local count = tonumber(reaper.GetExtState(NS, KEY_COUNT)) or 0

    if count ~= N then state = 0 end  -- window count changed → restart cycle

    local positions, next_state, zorder

    if state == 0 then
        positions = shelf_layout(wins, sw, sh)
        -- Strict bounds check: any window off screen → skip shelf, go to stagger
        local fits = true
        for i, win in ipairs(wins) do
            local p = positions[i]
            if p.x + win.w > sw or p.y - win.h < 0 then
                fits = false; break
            end
        end
        if fits then
            next_state = 1
        else
            positions, zorder = apply_stagger(wins, 1)
            next_state = 2
        end
    else
        positions, zorder = apply_stagger(wins, state)
        next_state = (state >= N) and 0 or (state + 1)
    end

    reaper.SetExtState(NS, KEY_STATE, tostring(next_state), false)
    reaper.SetExtState(NS, KEY_COUNT, tostring(N), false)

    for i, win in ipairs(wins) do
        local p = positions[i]
        -- p.y = top 錨點；JS_Window_SetPosition 需要 bottom (= top - height)
        reaper.JS_Window_SetPosition(win.hwnd, p.x, p.y - win.h, win.w, win.h)
    end

    -- z-order: call "TOP" bottom→top so featured window ends up on top
    if zorder then
        for _, win_idx in ipairs(zorder) do
            reaper.JS_Window_SetZOrder(wins[win_idx].hwnd, "TOP")
        end
    end
end

reaper.defer(main)
