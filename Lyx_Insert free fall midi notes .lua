--[[
    Insert free fall (bouncing ball) MIDI notes

    Physics: a ball bouncing with coefficient of restitution e.
      flight time between hits  T(k) = T0 · e^k
      impact speed (loudness)   v(k) = v0 · e^k   -> velocity = V0 · e^(k·curve)
    Stops when the gap is shorter than "min gap" or velocity falls under "floor".

    Source:
      Edit cursor     — one bounce sequence at the edit cursor (pitch slider)
      Selected notes  — every selected note becomes the first hit of its own bounce
                        (keeps its pitch / velocity / channel)
      Time selection  — fits the whole bounce into the time selection
]]
local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
package.path = package.path .. ";" .. script_path .. "?.lua"

---------------------------------------------------------------------------
-- Physics (pure)
---------------------------------------------------------------------------
local function lcg(seed) -- tiny deterministic RNG so preview == inserted result
    local s = seed % 2147483647
    if s <= 0 then s = s + 2147483646 end
    return function() s = s * 16807 % 2147483647; return (s - 1) / 2147483646 end
end

-- p: first (s), e, v0, vfloor, curve, min_gap (s), max_n, len_pct, jit_t (s), jit_v, seed
local function bounces(p)
    local out, t, dt, k = {}, 0, p.first, 0
    local rnd = lcg(p.seed or 1)
    while k < (p.max_n or 64) and dt > 0 do
        local vel = p.v0 * p.e ^ (k * p.curve)
        if vel < p.vfloor then break end
        local jt = (k > 0) and (rnd() * 2 - 1) * (p.jit_t or 0) or 0
        local jv = (rnd() * 2 - 1) * (p.jit_v or 0)
        out[#out + 1] = { t = math.max(0, t + jt), len = math.max(0.001, dt * p.len_pct),
                          vel = math.max(1, math.min(127, math.floor(vel + jv + 0.5))) }
        if dt < p.min_gap then break end
        t, dt, k = t + dt, dt * p.e, k + 1
    end
    return out
end

if not reaper then -- self-check: lua "Lyx_Insert free fall midi notes .lua"
    local b = bounces({ first = 1, e = 0.5, v0 = 100, vfloor = 1, curve = 1, min_gap = 0.1, len_pct = 0.5 })
    assert(#b == 5 and b[2].t == 1 and b[3].t == 1.5 and b[5].t == 1.875)
    assert(b[1].vel == 100 and b[2].vel == 50 and b[3].vel == 25)
    assert(b[2].len == 0.25)
    local c = bounces({ first = 1, e = 0.9, v0 = 100, vfloor = 40, curve = 1, min_gap = 0.001, len_pct = 1 })
    for _, n in ipairs(c) do assert(n.vel >= 40) end
    local p = { first = 0.5, e = 0.7, v0 = 110, vfloor = 5, curve = 1, min_gap = 0.02, len_pct = 0.8,
                jit_t = 0.01, jit_v = 5, seed = 42 }
    local x, y = bounces(p), bounces(p)
    assert(#x == #y and x[3].t == y[3].t and x[4].vel == y[4].vel)
    return print("Free fall self-check OK")
end

---------------------------------------------------------------------------
require("_Lyx_HOME")
local G = require("_Lyx_GUI")
local R = reaper
local EXT = "Lyx_FreeFall"

local function ld(k, d) return tonumber(R.GetExtState(EXT, k)) or d end
local S = {
    src     = ld("src", 0),        -- 0 cursor, 1 selected notes, 2 time selection
    first   = ld("first", 1.0),    -- first gap value
    unit    = ld("unit", 0),       -- 0 beats, 1 ms
    e       = ld("e", 0.72),
    v0      = ld("v0", 110),
    vfloor  = ld("vfloor", 12),
    curve   = ld("curve", 1.0),
    len_pct = ld("len_pct", 80),
    min_gap = ld("min_gap", 15),   -- ms
    jit_t   = ld("jit_t", 0),      -- ms
    jit_v   = ld("jit_v", 0),
    pitch   = -1,
    seed    = 1,
}
local function save()
    for k, v in pairs(S) do
        if k ~= "pitch" and k ~= "seed" then R.SetExtState(EXT, k, tostring(v), true) end
    end
end

local NOTE = { "C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B" }
local function pitch_label(take, p)
    local tr = take and R.GetMediaItemTake_Track(take)
    local n = tr and R.GetTrackMIDINoteNameEx(0, tr, p, 0)
    local base = NOTE[p % 12 + 1] .. (p // 12 - 2)
    return (n and n ~= "") and (base .. "  " .. n) or base
end

local function editor_take()
    local me = R.MIDIEditor_GetActive()
    local tk = me and R.MIDIEditor_GetTake(me)
    if tk and R.ValidatePtr(tk, "MediaItem_Take*") then return tk, me end
end

-- start time (s) of the sequence + seconds per beat there
local function first_gap_seconds(at)
    if S.unit == 1 then return S.first / 1000 end
    local qn = R.TimeMap2_timeToQN(0, at)
    return R.TimeMap2_QNToTime(0, qn + S.first) - at
end

local function params(at, total)
    local first = first_gap_seconds(at)
    if total and total > 0 then first = total * (1 - S.e) end
    return { first = first, e = S.e, v0 = S.v0, vfloor = S.vfloor, curve = S.curve,
             min_gap = S.min_gap / 1000, max_n = 128, len_pct = S.len_pct / 100,
             jit_t = S.jit_t / 1000, jit_v = S.jit_v, seed = S.seed }
end

-- list of { at, pitch, vel, chan, total, src_idx }
local function seeds(take)
    local list = {}
    if S.src == 1 and take then
        local i = R.MIDI_EnumSelNotes(take, -1)
        while i ~= -1 do
            local _, _, _, s, _, ch, p, v = R.MIDI_GetNote(take, i)
            list[#list + 1] = { at = R.MIDI_GetProjTimeFromPPQPos(take, s), pitch = p, vel = v, chan = ch, idx = i }
            i = R.MIDI_EnumSelNotes(take, i)
        end
    else
        local me = R.MIDIEditor_GetActive()
        local chan = me and R.MIDIEditor_GetSetting_int(me, "default_note_chan") or 0
        local at, total = R.GetCursorPosition(), nil
        if S.src == 2 then
            local a, b = R.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
            if b > a then at, total = a, b - a end
        end
        list[1] = { at = at, pitch = S.pitch, chan = chan, total = total }
    end
    return list
end

local function insert(take)
    local item = R.GetMediaItemTake_Item(take)
    R.Undo_BeginBlock()
    local last_end = 0
    local list = seeds(take)
    -- remove source notes (they become the first hit), highest index first
    if S.src == 1 then
        for i = #list, 1, -1 do R.MIDI_DeleteNote(take, list[i].idx) end
    end
    for _, sd in ipairs(list) do
        local p = params(sd.at, sd.total)
        if sd.vel then p.v0 = sd.vel end
        for _, n in ipairs(bounces(p)) do
            local s, e = sd.at + n.t, sd.at + n.t + n.len
            R.MIDI_InsertNote(take, false, false, R.MIDI_GetPPQPosFromProjTime(take, s),
                R.MIDI_GetPPQPosFromProjTime(take, e), sd.chan, sd.pitch, n.vel, true)
            if e > last_end then last_end = e end
        end
    end
    R.MIDI_Sort(take)
    local ipos = R.GetMediaItemInfo_Value(item, "D_POSITION")
    if last_end > ipos + R.GetMediaItemInfo_Value(item, "D_LENGTH") then
        R.MIDI_SetItemExtents(item, R.TimeMap2_timeToQN(0, ipos), R.TimeMap2_timeToQN(0, last_end))
    end
    local me = R.MIDIEditor_GetActive()
    if me then R.MIDIEditor_OnCommand(me, 40659) end -- correct overlapping notes
    R.UpdateArrange()
    R.Undo_EndBlock("Insert free fall MIDI notes", -1)
end

---------------------------------------------------------------------------
-- GUI
---------------------------------------------------------------------------
local ctx = G.new("Free fall")
if not ctx then return end
do
    local tk, me = editor_take()
    S.pitch = me and R.MIDIEditor_GetSetting_int(me, "active_note_row") or 60
    if tk and R.MIDI_EnumSelNotes(tk, -1) ~= -1 then S.src = 1
    elseif S.src == 1 then S.src = 0 end
end

local function graph(ctx, seq)
    local dl = R.ImGui_GetWindowDrawList(ctx)
    local w = R.ImGui_GetContentRegionAvail(ctx)
    local h = G.S(130)
    local x0, y0 = R.ImGui_GetCursorScreenPos(ctx)
    R.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + w, y0 + h, G.col(G.panel), G.S(6))
    R.ImGui_Dummy(ctx, w, h)
    if #seq == 0 then return end

    local last = seq[#seq]
    local span = math.max(last.t + last.len, 1e-6)
    local pad = G.S(10)
    local function X(t) return x0 + pad + (w - 2 * pad) * t / span end
    local base = y0 + h - G.S(8)
    local maxh = h - G.S(22)

    -- ball trajectory: parabola between hits, apex height ∝ gap²
    local g0 = (seq[2] and (seq[2].t - seq[1].t)) or 1
    for i = 1, #seq - 1 do
        local a, b = seq[i].t, seq[i + 1].t
        local apex = maxh * ((b - a) / g0) ^ 2
        local px, py = X(a), base
        for s = 1, 16 do
            local u = s / 16
            local nx, ny = X(a + (b - a) * u), base - apex * 4 * u * (1 - u)
            R.ImGui_DrawList_AddLine(dl, px, py, nx, ny, G.col(G.dim, 0x90), 1.5)
            px, py = nx, ny
        end
    end
    -- hits: velocity bars
    for _, n in ipairs(seq) do
        local x = X(n.t)
        local top = base - maxh * n.vel / 127
        R.ImGui_DrawList_AddRectFilled(dl, x, top, math.max(x + 2, X(n.t + n.len)), base,
            G.col(G.accent, 0x50), 2)
        R.ImGui_DrawList_AddLine(dl, x, base, x, top, G.col(G.accent), 2)
        R.ImGui_DrawList_AddCircleFilled(dl, x, top, G.S(3), G.col(G.accent))
    end
end

local function slider_d(ctx, label, key, mn, mx, fmt, tip)
    R.ImGui_SetNextItemWidth(ctx, -G.S(110))
    local c, v = R.ImGui_SliderDouble(ctx, label, S[key], mn, mx, fmt)
    if c then S[key] = v end
    if tip then R.ImGui_SetItemTooltip(ctx, tip) end
end
local function slider_i(ctx, label, key, mn, mx, fmt, tip)
    R.ImGui_SetNextItemWidth(ctx, -G.S(110))
    local c, v = R.ImGui_SliderInt(ctx, label, S[key], mn, mx, fmt)
    if c then S[key] = v end
    if tip then R.ImGui_SetItemTooltip(ctx, tip) end
end

G.run(ctx, "Free fall MIDI notes", function(ctx)
    local take = editor_take()
    local list = seeds(take)
    local sd = list[1]
    local seq = {}
    if sd then
        local p = params(sd.at, sd.total)
        if sd.vel then p.v0 = sd.vel end
        seq = bounces(p)
    end

    graph(ctx, seq)
    local dur = (#seq > 0) and (seq[#seq].t + seq[#seq].len) or 0
    G.dim_text(ctx, ("%d 個音 · 總長 %.2f s%s"):format(#seq, dur,
        (#list > 1) and ("  · ×" .. #list .. " 組") or ""))

    R.ImGui_SeparatorText(ctx, "起點")
    local srcs = { "編輯游標", "選取的音符", "時間選區 (塞滿)" }
    for i, name in ipairs(srcs) do
        if i > 1 then R.ImGui_SameLine(ctx) end
        if R.ImGui_RadioButton(ctx, name, S.src == i - 1) then S.src = i - 1 end
    end

    R.ImGui_SeparatorText(ctx, "彈跳")
    if S.src ~= 2 then
        R.ImGui_SetNextItemWidth(ctx, -G.S(190))
        local c, v
        if S.unit == 0 then
            c, v = R.ImGui_SliderDouble(ctx, "##first", S.first, 0.0625, 8, "第一下間隔 %.3f 拍", R.ImGui_SliderFlags_Logarithmic())
        else
            c, v = R.ImGui_SliderDouble(ctx, "##first", S.first, 20, 4000, "第一下間隔 %.0f ms", R.ImGui_SliderFlags_Logarithmic())
        end
        if c then S.first = v end
        R.ImGui_SameLine(ctx)
        if R.ImGui_RadioButton(ctx, "拍", S.unit == 0) and S.unit ~= 0 then
            S.unit = 0; S.first = 1
        end
        R.ImGui_SameLine(ctx)
        if R.ImGui_RadioButton(ctx, "ms", S.unit == 1) and S.unit ~= 1 then
            S.unit = 1; S.first = 500
        end
    end
    slider_d(ctx, "彈性", "e", 0.30, 0.95, "%.2f", "反彈係數：越大彈越久、間隔縮得越慢")
    slider_i(ctx, "最小間隔", "min_gap", 5, 80, "%d ms", "間隔短於此值就停（球停下來）")

    R.ImGui_SeparatorText(ctx, "力度 & 音長")
    if S.src ~= 1 then slider_i(ctx, "起始力度", "v0", 1, 127, "%d") end
    slider_i(ctx, "最小力度", "vfloor", 1, 127, "%d", "力度低於此值就停")
    slider_d(ctx, "衰減曲線", "curve", 0.3, 2.5, "%.2f", "1 = 物理正確；>1 越快變小聲；<1 尾巴更響")
    slider_i(ctx, "音長", "len_pct", 5, 100, "%d %%", "每個音佔下一個間隔的百分比")
    if S.src ~= 1 then
        R.ImGui_SetNextItemWidth(ctx, -G.S(110))
        local c, v = R.ImGui_SliderInt(ctx, "音高", S.pitch, 0, 127, pitch_label(take, S.pitch))
        if c then S.pitch = v end
    end

    R.ImGui_SeparatorText(ctx, "人性化")
    slider_i(ctx, "時間抖動", "jit_t", 0, 20, "± %d ms")
    slider_i(ctx, "力度抖動", "jit_v", 0, 20, "± %d")
    if S.jit_t > 0 or S.jit_v > 0 then
        if R.ImGui_Button(ctx, "重抽亂數") then S.seed = math.random(1, 2147483646) end
    end

    R.ImGui_Dummy(ctx, 1, G.S(4))
    local can = take ~= nil and #seq > 0 and not (S.src == 1 and #list == 0)
    if not can then
        G.color_text(ctx, G.warn, take and (S.src == 1 and "沒有選取的音符" or "沒有可插入的音") or "請先開啟 MIDI editor")
    end
    R.ImGui_BeginDisabled(ctx, not can)
    local go = G.button(ctx, "插入 (Enter)", G.S(110))
        or (can and R.ImGui_IsKeyPressed(ctx, R.ImGui_Key_Enter()) and not R.ImGui_IsAnyItemActive(ctx))
    R.ImGui_EndDisabled(ctx)
    R.ImGui_SameLine(ctx)
    if R.ImGui_Button(ctx, "取消", G.S(80)) then return false end

    if go then
        save()
        insert(take)
        return false
    end
end, { w = 440, h = 640, on_close = save })
