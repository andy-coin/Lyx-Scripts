--[[
    Randomize...  — live-preview randomizer for selected tracks or items.

    Every change previews instantly from a snapshot of the original values.
      Apply  (Enter) -> one undo point
      Cancel (Esc / close window) -> everything restored
    Same seed = same result; "Reroll" draws a new seed. Each parameter uses its own
    random stream, so editing one parameter never re-rolls the others.
    Locked items are left untouched.
]]
local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
package.path = package.path .. ";" .. script_path .. "?.lua"

---------------------------------------------------------------------------
-- Random (pure)
---------------------------------------------------------------------------
local function rand01(seed, i, pid)
    local s = (seed * 7919 + i * 104729 + pid * 15485863) % 2147483647
    if s <= 0 then s = s + 2147483646 end
    for _ = 1, 3 do s = s * 16807 % 2147483647 end
    return (s - 1) / 2147483646
end

-- uniform or gaussian (σ = range/6, clamped) value in [lo, hi]
local function draw(lo, hi, seed, i, pid, gauss)
    local u = rand01(seed, i, pid)
    if gauss then
        local u2 = rand01(seed, i, pid + 1000)
        local z = math.sqrt(-2 * math.log(math.max(u, 1e-12))) * math.cos(2 * math.pi * u2)
        u = math.max(0, math.min(1, 0.5 + z / 6))
    end
    return lo + (hi - lo) * u
end

if not reaper then -- self-check: lua "Lyx_Randomize....lua"
    for i = 1, 200 do
        local v = draw(-6, 2, 5, i, 1, false); assert(v >= -6 and v <= 2)
        local g = draw(-6, 2, 5, i, 1, true);  assert(g >= -6 and g <= 2)
    end
    assert(draw(0, 1, 9, 3, 2) == draw(0, 1, 9, 3, 2))   -- deterministic
    assert(draw(0, 1, 9, 3, 2) ~= draw(0, 1, 9, 3, 3))   -- independent streams
    local sum = 0
    for i = 1, 2000 do sum = sum + draw(0, 1, 77, i, 4, true) end
    assert(math.abs(sum / 2000 - 0.5) < 0.05)
    return print("Randomize self-check OK")
end

---------------------------------------------------------------------------
require("_lib._Lyx_HOME")
local G = require("_lib._Lyx_GUI")
local R = reaper
local EXT = "lyx_Randomize2"

-- kind: "range" (lo..hi), "prob" (lo = %), "toggle"
local PARAMS = {
    track = {
        { id = "vol",   name = "Volume",       kind = "range", min = -48, max = 12, lo = -6, hi = 0, unit = "dB", can_rel = true,
          tip = "Absolute: set to a value in the range; Relative: add to the current volume" },
        { id = "pan",   name = "Pan",        kind = "range", min = -100, max = 100, lo = -50, hi = 50, unit = "%" },
        { id = "width", name = "Width",      kind = "range", min = -100, max = 100, lo = 60, hi = 100, unit = "%" },
        { id = "mute",  name = "Mute chance",   kind = "prob",  lo = 20 },
        { id = "sel",   name = "Keep selected",   kind = "prob",  lo = 50, tip = "Each track stays selected with this chance, the rest get unselected" },
        { id = "color", name = "Random color",   kind = "toggle" },
    },
    item = {
        { id = "vol",   name = "Volume",       kind = "range", min = -48, max = 12, lo = -6, hi = 0, unit = "dB", can_rel = true,
          tip = "Absolute: set to a value in the range; Relative: add to the current volume" },
        { id = "pan",   name = "Pan",        kind = "range", min = -100, max = 100, lo = -50, hi = 50, unit = "%" },
        { id = "pitch", name = "Pitch",       kind = "range", min = -24, max = 24, lo = -1, hi = 1, unit = "st", snap = true,
          tip = "Relative to the original pitch; tick \"Semitones\" for whole semitones only" },
        { id = "pos",   name = "Position jitter",   kind = "range", min = -200, max = 200, lo = -10, hi = 10, unit = "ms",
          tip = "Nudge items back and forth for a human feel" },
        { id = "offs",  name = "Start offset",   kind = "range", min = -2000, max = 2000, lo = 0, hi = 250, unit = "ms",
          tip = "Shift where the item content starts (great for loops / ambience)" },
        { id = "mute",  name = "Mute chance",   kind = "prob",  lo = 20 },
        { id = "sel",   name = "Keep selected",   kind = "prob",  lo = 50 },
        { id = "color", name = "Random color",   kind = "toggle" },
    },
}

-- persisted settings
local function load_cfg()
    for kind, list in pairs(PARAMS) do
        for _, p in ipairs(list) do
            p.on = false; p.rel = false; p.int = p.snap or false
            local s = R.GetExtState(EXT, kind .. "_" .. p.id)
            local on, lo, hi, rel, int = s:match("^(%d),([^,]+),([^,]+),(%d),(%d)$")
            if on then
                p.on, p.lo, p.hi, p.rel, p.int = on == "1", tonumber(lo), tonumber(hi), rel == "1", int == "1"
            end
        end
    end
end
local function save_cfg(dist)
    for kind, list in pairs(PARAMS) do
        for _, p in ipairs(list) do
            R.SetExtState(EXT, kind .. "_" .. p.id, ("%d,%s,%s,%d,%d"):format(p.on and 1 or 0,
                p.lo or 0, p.hi or 0, p.rel and 1 or 0, p.int and 1 or 0), true)
        end
    end
    R.SetExtState(EXT, "gauss", dist and "1" or "0", true)
end
load_cfg()

---------------------------------------------------------------------------
-- Targets & snapshot
---------------------------------------------------------------------------
local kind = (R.CountSelectedTracks(0) > R.CountSelectedMediaItems(0)) and "track" or "item"
local gauss = R.GetExtState(EXT, "gauss") == "1"
local seed = math.random(1, 2147483646)
local targets = {}

local function snapshot()
    targets = {}
    if kind == "track" then
        for i = 0, R.CountSelectedTracks(0) - 1 do
            local tr = R.GetSelectedTrack(0, i)
            targets[#targets + 1] = { obj = tr, o = {
                vol = R.GetMediaTrackInfo_Value(tr, "D_VOL"), pan = R.GetMediaTrackInfo_Value(tr, "D_PAN"),
                width = R.GetMediaTrackInfo_Value(tr, "D_WIDTH"), mute = R.GetMediaTrackInfo_Value(tr, "B_MUTE"),
                color = R.GetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR") } }
        end
    else
        for i = 0, R.CountSelectedMediaItems(0) - 1 do
            local it = R.GetSelectedMediaItem(0, i)
            local tk = R.GetActiveTake(it)
            targets[#targets + 1] = { obj = it, take = tk,
                locked = (R.GetMediaItemInfo_Value(it, "C_LOCK") & 1) == 1, o = {
                vol = R.GetMediaItemInfo_Value(it, "D_VOL"), pos = R.GetMediaItemInfo_Value(it, "D_POSITION"),
                mute = R.GetMediaItemInfo_Value(it, "B_MUTE"), color = R.GetMediaItemInfo_Value(it, "I_CUSTOMCOLOR"),
                pan = tk and R.GetMediaItemTakeInfo_Value(tk, "D_PAN") or 0,
                pitch = tk and R.GetMediaItemTakeInfo_Value(tk, "D_PITCH") or 0,
                offs = tk and R.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") or 0 } }
        end
    end
end

local function valid(t)
    return R.ValidatePtr2(0, t.obj, (kind == "track") and "MediaTrack*" or "MediaItem*")
end

local function restore()
    R.PreventUIRefresh(1)
    for _, t in ipairs(targets) do
        if valid(t) then
            local o = t.o
            if kind == "track" then
                local tr = t.obj
                R.SetMediaTrackInfo_Value(tr, "D_VOL", o.vol); R.SetMediaTrackInfo_Value(tr, "D_PAN", o.pan)
                R.SetMediaTrackInfo_Value(tr, "D_WIDTH", o.width); R.SetMediaTrackInfo_Value(tr, "B_MUTE", o.mute)
                R.SetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR", o.color); R.SetTrackSelected(tr, true)
            elseif not t.locked then
                local it, tk = t.obj, t.take
                R.SetMediaItemInfo_Value(it, "D_VOL", o.vol); R.SetMediaItemInfo_Value(it, "D_POSITION", o.pos)
                R.SetMediaItemInfo_Value(it, "B_MUTE", o.mute); R.SetMediaItemInfo_Value(it, "I_CUSTOMCOLOR", o.color)
                if tk then
                    R.SetMediaItemTakeInfo_Value(tk, "D_PAN", o.pan); R.SetMediaItemTakeInfo_Value(tk, "D_PITCH", o.pitch)
                    R.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", o.offs)
                end
                R.SetMediaItemSelected(it, true)
            end
        end
    end
    R.PreventUIRefresh(-1)
    R.TrackList_AdjustWindows(false)
    R.UpdateArrange()
end

local function hsv_rgb(h) -- hue 0..1 -> r,g,b 0..255 (fixed pastel saturation/value)
    local i = math.floor(h * 6)
    local f, v, s = h * 6 - i, 0.85, 0.55
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    local c = ({ { v, t, p }, { q, v, p }, { p, v, t }, { p, q, v }, { t, p, v }, { v, p, q } })[i % 6 + 1]
    return math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255)
end
local function hsv_color(h) return R.ColorToNative(hsv_rgb(h)) | 0x1000000 end

local DB = function(db) return 10 ^ (db / 20) end
local function to_db(v) return (v > 0) and 20 * math.log(v, 10) or -150 end

-- results[pid][i] = displayed value (for the strip plot)
local results = {}

local function apply()
    results = {}
    R.PreventUIRefresh(1)
    for pi, p in ipairs(PARAMS[kind]) do
        if p.on then
            local res = {}
            results[p.id] = res
            for i, t in ipairs(targets) do
                if valid(t) and not t.locked then
                    local o, obj, tk = t.o, t.obj, t.take
                    local SetV = (kind == "track") and R.SetMediaTrackInfo_Value or R.SetMediaItemInfo_Value
                    if p.kind == "prob" then
                        local hit = rand01(seed, i, pi) * 100 < p.lo
                        res[i] = hit and 1 or 0
                        if p.id == "mute" then SetV(obj, "B_MUTE", hit and 1 or 0)
                        elseif p.id == "sel" then
                            if kind == "track" then R.SetTrackSelected(obj, hit) else R.SetMediaItemSelected(obj, hit) end
                        end
                    elseif p.kind == "toggle" then
                        local h = rand01(seed, i, pi)
                        res[i] = h
                        SetV(obj, "I_CUSTOMCOLOR", hsv_color(h))
                    else
                        local v = draw(p.lo, p.hi, seed, i, pi, gauss)
                        if p.int then v = math.floor(v + 0.5) end
                        res[i] = v
                        if p.id == "vol" then
                            local db = p.rel and (to_db(o.vol) + v) or v
                            SetV(obj, "D_VOL", DB(db))
                        elseif p.id == "pan" then
                            if kind == "track" then SetV(obj, "D_PAN", v / 100)
                            elseif tk then R.SetMediaItemTakeInfo_Value(tk, "D_PAN", v / 100) end
                        elseif p.id == "width" then SetV(obj, "D_WIDTH", v / 100)
                        elseif p.id == "pitch" and tk then R.SetMediaItemTakeInfo_Value(tk, "D_PITCH", o.pitch + v)
                        elseif p.id == "pos" then SetV(obj, "D_POSITION", math.max(0, o.pos + v / 1000))
                        elseif p.id == "offs" and tk then R.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", o.offs + v / 1000)
                        end
                    end
                end
            end
        end
    end
    R.PreventUIRefresh(-1)
    R.UpdateArrange()
end

---------------------------------------------------------------------------
-- GUI
---------------------------------------------------------------------------
local ctx = G.new("Randomize", "Randomize")
if not ctx then return end
snapshot()
local applied, last_sig = false, nil

local function signature()
    local t = { kind, seed, gauss and 1 or 0, #targets }
    for _, p in ipairs(PARAMS[kind]) do
        t[#t + 1] = ("%s%s%s%s%s"):format(p.on and 1 or 0, p.lo or "", p.hi or "", p.rel and 1 or 0, p.int and 1 or 0)
    end
    return table.concat(t, "|")
end

-- range bar + one dot per target
local function strip(ctx, p)
    local dl = R.ImGui_GetWindowDrawList(ctx)
    local w = R.ImGui_GetContentRegionAvail(ctx)
    local h = G.S(14)
    local x0, y0 = R.ImGui_GetCursorScreenPos(ctx)
    R.ImGui_Dummy(ctx, w, h)
    local cy = y0 + h / 2
    R.ImGui_DrawList_AddRectFilled(dl, x0, cy - 2, x0 + w, cy + 2, G.col(G.panel), 2)
    local res = results[p.id] or {}
    if p.kind == "range" then
        local function X(v) return x0 + w * (v - p.min) / (p.max - p.min) end
        R.ImGui_DrawList_AddRectFilled(dl, X(p.lo), cy - 3, X(p.hi), cy + 3, G.col(G.accent, 0x60), 3)
        if p.min < 0 and p.max > 0 then R.ImGui_DrawList_AddLine(dl, X(0), y0, X(0), y0 + h, G.col(G.dim), 1) end
        for _, v in pairs(res) do
            R.ImGui_DrawList_AddCircleFilled(dl, X(math.max(p.min, math.min(p.max, v))), cy, G.S(3), G.col(G.accent))
        end
    elseif p.kind == "prob" then
        local n, hit = 0, 0
        for _, v in pairs(res) do n = n + 1; hit = hit + v end
        if n > 0 then
            local cw = w / n
            local k = 0
            for i = 1, #targets do
                if res[i] then
                    R.ImGui_DrawList_AddRectFilled(dl, x0 + k * cw + 1, y0 + 2, x0 + (k + 1) * cw - 1, y0 + h - 2,
                        G.col(res[i] == 1 and G.accent or G.panel), 2)
                    k = k + 1
                end
            end
        end
    else
        local n = #targets
        if n > 0 then
            local cw = w / n
            for i = 1, n do
                if res[i] then
                    R.ImGui_DrawList_AddRectFilled(dl, x0 + (i - 1) * cw + 1, y0 + 2, x0 + i * cw - 1, y0 + h - 2,
                        G.col((function() local r_, g_, b_ = hsv_rgb(res[i]); return (r_ << 16) | (g_ << 8) | b_ end)()), 2)
                end
            end
        end
    end
end

-- per-frame layout metrics: theme font / spacing / scale can change live
local L = {}
local function tw(ctx, s) return (R.ImGui_CalcTextSize(ctx, s)) end
local function measure(ctx)
    L.sp    = R.ImGui_GetStyleVar(ctx, R.ImGui_StyleVar_ItemSpacing())
    L.inner = R.ImGui_GetStyleVar(ctx, R.ImGui_StyleVar_ItemInnerSpacing())
    L.pad   = R.ImGui_GetStyleVar(ctx, R.ImGui_StyleVar_FramePadding())
    L.fh    = R.ImGui_GetFrameHeight(ctx)
    L.x0    = R.ImGui_GetCursorPosX(ctx)
    -- label column: widest of the row labels ([x] name) and the header labels
    local w = math.max(tw(ctx, "Target"), tw(ctx, "Distribution"), tw(ctx, "Theme"))
    for _, list in pairs(PARAMS) do
        for _, p in ipairs(list) do w = math.max(w, L.fh + L.sp + tw(ctx, p.name)) end
    end
    L.col = L.x0 + w + L.sp
end
local function check_w(ctx, label) return L.fh + L.inner + tw(ctx, label) end

-- SameLine when an item of width w still fits on this row, else start a new row
local function same_line_fit(ctx, w)
    R.ImGui_SameLine(ctx)
    if R.ImGui_GetContentRegionAvail(ctx) < w then R.ImGui_NewLine(ctx) end
end

-- smallest width that shows both range values in full
local function range_w(ctx, p)
    local fmt = "Max %.1f " .. p.unit:gsub("%%", "%%%%")
    local v = math.max(tw(ctx, fmt:format(p.min)), tw(ctx, fmt:format(p.max)))
    return 2 * (v + 2 * L.pad) + L.inner
end

local function param_row(ctx, p)
    R.ImGui_PushID(ctx, p.id)
    local row_w = R.ImGui_GetContentRegionAvail(ctx)
    local c, v = R.ImGui_Checkbox(ctx, "##on", p.on)
    if c then p.on = v end
    R.ImGui_SameLine(ctx)
    R.ImGui_AlignTextToFramePadding(ctx)
    if p.on then R.ImGui_Text(ctx, p.name) else G.color_text(ctx, G.dim, p.name) end
    if p.tip then R.ImGui_SetItemTooltip(ctx, p.tip) end
    -- controls next to the name when they fit, else on the next row under the name
    local extra = (p.can_rel and check_w(ctx, "Relative") + L.sp)
               or (p.snap and check_w(ctx, "Semitones") + L.sp) or 0
    local need = extra + ((p.kind == "range" and range_w(ctx, p)) or (p.kind == "prob" and G.S(80)) or 0)
    if row_w - (L.col - L.x0) >= need then
        R.ImGui_SameLine(ctx, L.col)
    else
        R.ImGui_SetCursorPosX(ctx, L.x0 + L.fh + L.sp)
    end
    R.ImGui_BeginDisabled(ctx, not p.on)
    if p.kind == "range" then
        R.ImGui_SetNextItemWidth(ctx, -extra)
        local fmt = "%.1f " .. p.unit:gsub("%%", "%%%%") -- "%" unit must be "%%" in a format
        local cc, lo, hi = R.ImGui_DragFloatRange2(ctx, "##rng", p.lo, p.hi,
            (p.max - p.min) / 400, p.min, p.max, "Min " .. fmt, "Max " .. fmt)
        if cc then p.lo, p.hi = math.min(lo, hi), math.max(lo, hi) end
        if p.can_rel then
            R.ImGui_SameLine(ctx)
            local c2, v2 = R.ImGui_Checkbox(ctx, "Relative", p.rel)
            if c2 then p.rel = v2 end
        elseif p.snap then
            R.ImGui_SameLine(ctx)
            local c2, v2 = R.ImGui_Checkbox(ctx, "Semitones", p.int)
            if c2 then p.int = v2 end
        end
    elseif p.kind == "prob" then
        R.ImGui_SetNextItemWidth(ctx, -1)
        local cc, vv = R.ImGui_SliderDouble(ctx, "##p", p.lo, 0, 100, "%.0f %%")
        if cc then p.lo = vv end
    else
        G.dim_text(ctx, "A random color for each target")
    end
    if p.on then strip(ctx, p) end
    R.ImGui_EndDisabled(ctx)
    R.ImGui_PopID(ctx)
end

local function close(do_apply)
    if do_apply then
        restore()
        R.Undo_BeginBlock()
        apply()
        R.Undo_EndBlock("Randomize " .. kind .. "s", -1)
        applied = true
    end
    save_cfg(gauss)
    return false
end

G.run(ctx, "Randomize...", function(ctx)
    -- target switch
    measure(ctx)
    local nt, ni = R.CountSelectedTracks(0), R.CountSelectedMediaItems(0)
    R.ImGui_AlignTextToFramePadding(ctx)
    R.ImGui_Text(ctx, "Target")
    R.ImGui_SameLine(ctx, L.col)
    for _, k in ipairs({ "track", "item" }) do
        local label = (k == "track") and ("Tracks (" .. (kind == "track" and #targets or nt) .. ")")
                                     or ("Item (" .. (kind == "item" and #targets or ni) .. ")")
        if R.ImGui_RadioButton(ctx, label, kind == k) and kind ~= k then
            restore(); kind = k; snapshot()
        end
        same_line_fit(ctx, k == "track" and check_w(ctx, "Item (0000)") or tw(ctx, "Reload selection") + 2 * L.pad)
    end
    if R.ImGui_SmallButton(ctx, "Reload selection") then restore(); snapshot() end
    R.ImGui_SetItemTooltip(ctx, "Click after changing the selection (the current preview is undone first)")
    same_line_fit(ctx, L.fh)
    G.align_right(ctx, R.ImGui_GetFrameHeight(ctx))
    G.pin(ctx)

    R.ImGui_AlignTextToFramePadding(ctx)
    R.ImGui_Text(ctx, "Distribution")
    R.ImGui_SameLine(ctx, L.col)
    if R.ImGui_RadioButton(ctx, "Uniform", not gauss) then gauss = false end
    same_line_fit(ctx, check_w(ctx, "Normal (centered)"))
    if R.ImGui_RadioButton(ctx, "Normal (centered)", gauss) then gauss = true end

    R.ImGui_AlignTextToFramePadding(ctx)
    R.ImGui_Text(ctx, "Theme")
    R.ImGui_SameLine(ctx, L.col)
    G.theme_row(ctx, "Randomize")

    R.ImGui_Separator(ctx)
    if #targets == 0 then
        G.color_text(ctx, G.warn, (kind == "track") and "No tracks selected" or "No items selected")
    end
    for _, p in ipairs(PARAMS[kind]) do param_row(ctx, p) end

    local locked = 0
    for _, t in ipairs(targets) do if t.locked then locked = locked + 1 end end
    if locked > 0 then G.dim_text(ctx, locked .. " locked items will be skipped") end

    -- live preview
    local sig = signature()
    if sig ~= last_sig then last_sig = sig; apply() end

    R.ImGui_Separator(ctx)
    if R.ImGui_Button(ctx, "Reroll") then seed = math.random(1, 2147483646) end
    R.ImGui_SameLine(ctx)
    if R.ImGui_Button(ctx, "All off") then for _, p in ipairs(PARAMS[kind]) do p.on = false end end
    local bw = math.max(G.S(90), tw(ctx, "Cancel") + 2 * L.pad)
    same_line_fit(ctx, bw * 2 + L.sp)
    G.align_right(ctx, bw * 2 + L.sp)
    if G.button(ctx, "Apply", bw) or (R.ImGui_IsKeyPressed(ctx, R.ImGui_Key_Enter()) and not R.ImGui_IsAnyItemActive(ctx)) then
        return close(true)
    end
    R.ImGui_SameLine(ctx)
    if R.ImGui_Button(ctx, "Cancel", bw) then return close(false) end
end, {
    w = 480, h = 560, min_w = 360, min_h = 300,
    on_close = function() if not applied then restore(); save_cfg(gauss) end end,
    on_exit  = function() if not applied then restore() end end,
})
