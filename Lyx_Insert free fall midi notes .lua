--[[
    Insert free fall (bouncing ball) MIDI notes

    Physics: a ball bouncing with coefficient of restitution e.
      flight time between hits  T(k) = T0 · e^k
      impact speed (loudness)   v(k) = v0 · e^k   -> velocity = V0 · e^(k·curve)
    Stops when the gap is shorter than "Min gap" or velocity falls under "Min velocity".

    Start at:
      Edit cursor     — one bounce sequence at the edit cursor (Pitch / Velocity sliders)
      Selected notes  — every selected note stays as the first hit of its own bounce
                        (pitch / velocity / channel / mute come from the note)
      Time selection  — fits the whole bounce into the time selection

    Item edges:
      notes past the item end extend the item; in a looped item (one that really
      repeats) the bounce is written into the loop and notes past the loop end are dropped.
    Insert (Enter) = one undo point. Cancel / Esc changes nothing.
]]
local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
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
-- -> { {t, len, vel}, ... } in seconds from the first hit. The first hit is the anchor:
-- never jittered. Notes stay in order and never overlap each other.
local function bounces(p)
    local out = {}
    if not (p.first > 0 and p.e > 0 and p.e < 1) then return out end
    local t, dt, k = 0, p.first, 0
    local rnd = lcg(p.seed or 1)
    while k < (p.max_n or 64) do
        local vel = p.v0 * p.e ^ (k * p.curve)
        if k > 0 and vel < p.vfloor then break end  -- never drop the first hit itself
        local jt, jv = 0, 0
        if k > 0 then -- ±40% of the (shorter) next gap at most, so hits can't swap places
            jt = (rnd() * 2 - 1) * math.min(p.jit_t or 0, 0.4 * dt)
            jv = (rnd() * 2 - 1) * (p.jit_v or 0)
        end
        out[#out + 1] = { t = t + jt, len = math.max(0.001, dt * p.len_pct),
                          vel = math.max(1, math.min(127, math.floor(vel + jv + 0.5))) }
        if dt < p.min_gap then break end
        t, dt, k = t + dt, dt * p.e, k + 1
    end
    for i = 1, #out - 1 do out[i].len = math.min(out[i].len, out[i + 1].t - out[i].t) end
    return out
end

-- notes {s, e, vel} in PPQ (first = anchor), L = loop length in PPQ:
-- move the set into the first loop pass, drop / trim what passes the loop end.
local function fit_loop(notes, L)
    local shift = math.floor(notes[1].s / L) * L
    local out = {}
    for _, n in ipairs(notes) do
        local s = n.s - shift
        if s < L then out[#out + 1] = { s = s, e = math.min(n.e - shift, L), vel = n.vel } end
    end
    return out, #notes - #out
end

if not reaper then -- self-check: lua5.4 "Lyx_Insert free fall midi notes .lua"
    local b = bounces({ first = 1, e = 0.5, v0 = 100, vfloor = 1, curve = 1, min_gap = 0.1, len_pct = 0.5 })
    assert(#b == 5 and b[2].t == 1 and b[3].t == 1.5 and b[5].t == 1.875)
    assert(b[1].vel == 100 and b[2].vel == 50 and b[3].vel == 25)
    assert(b[2].len == 0.25)
    local c = bounces({ first = 1, e = 0.9, v0 = 100, vfloor = 40, curve = 1, min_gap = 0.001, len_pct = 1 })
    for i, n in ipairs(c) do assert(i == 1 or n.vel >= 40) end
    assert(#bounces({ first = 1, e = 0.5, v0 = 8, vfloor = 12, curve = 1, min_gap = 0.1, len_pct = 0.5 }) == 1)
    -- bad input never loops forever / never inserts garbage
    for _, bad in ipairs({ { first = 0, e = 0.5 }, { first = -1, e = 0.5 }, { first = 1, e = 1 },
                           { first = 1, e = 1.5 }, { first = 1, e = 0 }, { first = 1, e = -0.5 } }) do
        bad.v0, bad.vfloor, bad.curve, bad.min_gap, bad.len_pct = 100, 1, 1, 0.01, 0.5
        assert(#bounces(bad) == 0)
    end
    -- jitter: deterministic, first hit untouched, order kept, no overlaps (even at 100 % length)
    local p = { first = 0.5, e = 0.7, v0 = 110, vfloor = 5, curve = 1, min_gap = 0.005, len_pct = 1,
                jit_t = 0.02, jit_v = 20, seed = 42 }
    local x, y = bounces(p), bounces(p)
    assert(#x == #y and x[3].t == y[3].t and x[4].vel == y[4].vel)
    assert(x[1].t == 0 and x[1].vel == 110)
    for seed = 1, 200 do
        p.seed = seed
        local s = bounces(p)
        for i = 1, #s - 1 do
            assert(s[i + 1].t > s[i].t, "order")
            assert(s[i].t + s[i].len <= s[i + 1].t + 1e-12, "overlap")
            assert(s[i].len > 0)
        end
    end
    -- looped item: start in pass 3 of a 1000-tick loop -> moved into pass 1, tail dropped / trimmed
    local f, d = fit_loop({ { s = 2900, e = 2950, vel = 1 }, { s = 2980, e = 3050, vel = 2 },
                            { s = 3100, e = 3150, vel = 3 } }, 1000)
    assert(d == 1 and #f == 2 and f[1].s == 900 and f[2].s == 980 and f[2].e == 1000)
    f, d = fit_loop({ { s = 100, e = 200, vel = 1 } }, 1000)
    assert(d == 0 and f[1].s == 100 and f[1].e == 200)
    return print("Free fall self-check OK")
end

---------------------------------------------------------------------------
require("_Lyx_HOME")
local G = require("_Lyx_GUI")
local R = reaper
local EXT = "Lyx_FreeFall"

-- slider ranges; also used to sanitise saved values
local RANGE = {
    e = { 0.30, 0.95 }, v0 = { 1, 127 }, vfloor = { 1, 127 }, curve = { 0.3, 2.5 },
    len_pct = { 5, 100 }, min_gap = { 5, 80 }, jit_t = { 0, 20 }, jit_v = { 0, 20 },
    first_beats = { 0.0625, 8 }, first_ms = { 20, 4000 },
}
local INT = { v0 = true, vfloor = true, len_pct = true, min_gap = true, jit_t = true, jit_v = true, src = true, unit = true }

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
    pitch   = 60,
    seed    = 1,
}
local function clamp(v, r) return math.max(r[1], math.min(r[2], v)) end
do -- saved values may be stale or hand-edited
    S.src  = math.floor(clamp(S.src, { 0, 2 }))
    S.unit = (S.unit == 1) and 1 or 0
    S.first = clamp(S.first, RANGE[S.unit == 0 and "first_beats" or "first_ms"])
    for k, r in pairs(RANGE) do if S[k] then S[k] = clamp(S[k], r) end end
    for k in pairs(INT) do S[k] = math.floor(S[k] + 0.5) end
end
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

-- first gap in seconds (beats are measured from the start position, so tempo is respected)
local function first_gap_seconds(at)
    if S.unit == 1 then return S.first / 1000 end
    local qn = R.TimeMap2_timeToQN(0, at)
    return R.TimeMap2_QNToTime(0, qn + S.first) - at
end

local function params(at, total)
    local first = first_gap_seconds(at)
    if total and total > 0 then first = total * (1 - S.e) end -- geometric series sums to `total`
    return { first = first, e = S.e, v0 = S.v0, vfloor = S.vfloor, curve = S.curve,
             min_gap = S.min_gap / 1000, max_n = 128, len_pct = S.len_pct / 100,
             jit_t = S.jit_t / 1000, jit_v = S.jit_v, seed = S.seed }
end

-- list of { at, pitch, chan, [vel, idx, e_ppq, muted] (selected notes), [total] (time sel) }
local function seeds(take)
    local list = {}
    if S.src == 1 then
        local i = R.MIDI_EnumSelNotes(take, -1)
        while i ~= -1 do
            local _, _, mu, s, e, ch, p, v = R.MIDI_GetNote(take, i)
            list[#list + 1] = { at = R.MIDI_GetProjTimeFromPPQPos(take, s), pitch = p, vel = v, chan = ch,
                                idx = i, e_ppq = e, muted = mu }
            i = R.MIDI_EnumSelNotes(take, i)
        end
        if #list == 0 then return nil, "No notes selected" end
        return list
    end
    local me = R.MIDIEditor_GetActive()
    local chan = me and R.MIDIEditor_GetSetting_int(me, "default_note_chan") or 0
    local at, total = R.GetCursorPosition(), nil
    if S.src == 2 then
        local a, b = R.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
        if b <= a then return nil, "No time selection" end
        at, total = a, b - a
    end
    list[1] = { at = at, pitch = S.pitch, chan = chan, total = total }
    return list
end

-- Everything Insert will write, computed the same way for the preview.
-- -> plan { sets = { {sd, seq, notes(ppq)} }, count, dropped, extend_to, item, ipos } | nil, reason
local function plan(take)
    if not take then return nil, "Open a MIDI editor first" end
    local list, err = seeds(take)
    if not list then return nil, err end
    local item = R.GetMediaItemTake_Item(take)
    local ipos = R.GetMediaItemInfo_Value(item, "D_POSITION")
    local iend = ipos + R.GetMediaItemInfo_Value(item, "D_LENGTH")

    -- loop length (PPQ) only when the item really repeats; a default single-pass MIDI
    -- item also has "Loop source" on, and that one simply gets extended.
    local L
    if R.GetMediaItemInfo_Value(item, "B_LOOPSRC") == 1 then
        local qn = R.GetMediaSourceLength(R.GetMediaItemTake_Source(take))
        local rate = R.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
        local tpq = (R.MIDI_GetPPQPosFromProjQN(take, 1) - R.MIDI_GetPPQPosFromProjQN(take, 0)) / rate
        local src = qn * tpq
        if src > 0 and R.MIDI_GetPPQPosFromProjTime(take, iend) > src + 1 then L = src end
    end

    local pl = { sets = {}, count = 0, dropped = 0, item = item, ipos = ipos }
    local last_end = 0
    for i, sd in ipairs(list) do
        if not sd.idx and (sd.at < ipos - 1e-9 or sd.at >= iend) then
            return nil, (S.src == 2) and "Time selection starts outside the MIDI item"
                                      or "Edit cursor is outside the MIDI item"
        end
        local p = params(sd.at, sd.total)
        p.seed = S.seed + i - 1 -- each selected note gets its own humanize
        if sd.vel then p.v0 = sd.vel end
        local seq = bounces(p)
        local notes = {}
        for _, n in ipairs(seq) do
            local s, e = sd.at + n.t, sd.at + n.t + n.len
            notes[#notes + 1] = { s = R.MIDI_GetPPQPosFromProjTime(take, s),
                                  e = R.MIDI_GetPPQPosFromProjTime(take, e), vel = n.vel }
            if e > last_end then last_end = e end
        end
        if sd.idx and seq[1] then -- the selected note itself stays; show its real (trimmed) length
            local len = R.MIDI_GetProjTimeFromPPQPos(take, sd.e_ppq) - sd.at
            seq[1].len = seq[2] and math.min(len, seq[2].t) or len
            if seq[1].len > last_end - sd.at then last_end = sd.at + seq[1].len end
        end
        if L and #notes > 0 then
            local d
            notes, d = fit_loop(notes, L)
            pl.dropped = pl.dropped + d
        end
        pl.sets[i] = { sd = sd, seq = seq, notes = notes }
        pl.count = pl.count + #notes
    end
    if not L and last_end > iend + 1e-9 then pl.extend_to = last_end end
    if pl.count == 0 then return nil, "Nothing to insert" end
    return pl
end

local function insert(take, pl)
    R.Undo_BeginBlock()
    R.PreventUIRefresh(1)
    -- the inserted notes become the note selection
    local i = R.MIDI_EnumSelNotes(take, -1)
    while i ~= -1 do
        R.MIDI_SetNote(take, i, false, nil, nil, nil, nil, nil, nil, true)
        i = R.MIDI_EnumSelNotes(take, i)
    end
    -- selected notes stay as the first hit (shortened only if they'd overlap hit 2);
    -- done before any insert so the note indices are still valid
    for _, set in ipairs(pl.sets) do
        local sd, n2 = set.sd, set.notes[2]
        if sd.idx then
            R.MIDI_SetNote(take, sd.idx, true, nil, nil, n2 and math.min(sd.e_ppq, n2.s) or nil,
                nil, nil, nil, true)
        end
    end
    for _, set in ipairs(pl.sets) do
        local sd = set.sd
        for k = sd.idx and 2 or 1, #set.notes do
            local n = set.notes[k]
            R.MIDI_InsertNote(take, true, sd.muted or false, n.s, n.e, sd.chan, sd.pitch, n.vel, true)
        end
    end
    R.MIDI_Sort(take)
    if pl.extend_to then
        R.MIDI_SetItemExtents(pl.item, R.TimeMap2_timeToQN(0, pl.ipos), R.TimeMap2_timeToQN(0, pl.extend_to))
    end
    local me = R.MIDIEditor_GetActive()
    if me and R.MIDIEditor_GetTake(me) == take then
        R.MIDIEditor_OnCommand(me, 40659) -- correct overlapping notes (only the selection = ours)
    end
    R.PreventUIRefresh(-1)
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
    if me then S.pitch = R.MIDIEditor_GetSetting_int(me, "active_note_row") end
    if tk and R.MIDI_EnumSelNotes(tk, -1) ~= -1 then S.src = 1
    elseif S.src == 1 then S.src = 0 end
end

local LABEL_W = 110 -- left label column (same as Randomize...)
local CLAMP = R.ImGui_SliderFlags_AlwaysClamp()

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
        local apex = maxh * math.min(1, ((b - a) / g0) ^ 2)
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

-- "Label      [slider.............]" row; `off` = text shown instead of the value while disabled
local function label(ctx, text, tip)
    R.ImGui_AlignTextToFramePadding(ctx)
    R.ImGui_Text(ctx, text)
    if tip then R.ImGui_SetItemTooltip(ctx, tip) end
    R.ImGui_SameLine(ctx, G.S(LABEL_W))
end
local function slider(ctx, text, key, fmt, tip, off)
    label(ctx, text, tip)
    R.ImGui_BeginDisabled(ctx, off ~= nil)
    R.ImGui_SetNextItemWidth(ctx, -1)
    local r, f = RANGE[key], off or fmt
    local c, v
    if INT[key] then c, v = R.ImGui_SliderInt(ctx, "##" .. key, S[key], r[1], r[2], f, CLAMP)
    else             c, v = R.ImGui_SliderDouble(ctx, "##" .. key, S[key], r[1], r[2], f, CLAMP) end
    if c then S[key] = v end
    R.ImGui_EndDisabled(ctx)
    if tip then R.ImGui_SetItemTooltip(ctx, tip) end
end

G.run(ctx, "Free fall MIDI notes", function(ctx)
    local take = editor_take()
    local pl, err = plan(take)
    local seq = pl and pl.sets[1].seq or bounces(params(R.GetCursorPosition()))

    graph(ctx, seq)
    if pl then
        local dur = (#seq > 0) and (seq[#seq].t + seq[#seq].len) or 0
        local info = ("%d notes  ·  %.2f s"):format(pl.count, dur)
        if #pl.sets > 1 then info = info .. ("  ·  %d bounces"):format(#pl.sets) end
        if pl.extend_to then info = info .. "  ·  item will be extended" end
        if pl.dropped > 0 then info = info .. ("  ·  %d past the loop end dropped"):format(pl.dropped) end
        G.dim_text(ctx, info)
    else
        G.color_text(ctx, G.warn, err)
    end

    R.ImGui_SeparatorText(ctx, "Start")
    label(ctx, "Start at")
    local srcs = {
        { "Edit cursor",    "One bounce starting at the edit cursor" },
        { "Selected notes", "Each selected note becomes the first hit of its own bounce\n(pitch, velocity, channel and mute come from the note)" },
        { "Time selection", "Fit the whole bounce into the time selection" },
    }
    for i, s in ipairs(srcs) do
        if i > 1 then R.ImGui_SameLine(ctx) end
        if R.ImGui_RadioButton(ctx, s[1], S.src == i - 1) then S.src = i - 1 end
        R.ImGui_SetItemTooltip(ctx, s[2])
    end
    local from_note = (S.src == 1) and "From each selected note" or nil
    label(ctx, "Pitch", "Note of the bounce (starts on the MIDI editor's active note row)")
    R.ImGui_BeginDisabled(ctx, from_note ~= nil)
    R.ImGui_SetNextItemWidth(ctx, -1)
    local pc, pv = R.ImGui_SliderInt(ctx, "##pitch", S.pitch, 0, 127,
        from_note or pitch_label(take, S.pitch):gsub("%%", "%%%%"), CLAMP)
    if pc then S.pitch = pv end
    R.ImGui_EndDisabled(ctx)
    slider(ctx, "Velocity", "v0", "%d", "Velocity of the first hit", from_note)

    R.ImGui_SeparatorText(ctx, "Bounce")
    local fit = (S.src == 2)
    label(ctx, "First gap", "Time between the first and second hit")
    R.ImGui_BeginDisabled(ctx, fit)
    R.ImGui_SetNextItemWidth(ctx, -G.S(118))
    local flags = R.ImGui_SliderFlags_Logarithmic() | CLAMP
    local r = RANGE[S.unit == 0 and "first_beats" or "first_ms"]
    local fmt = fit and "Fits the time selection" or (S.unit == 0 and "%.3f beats" or "%.0f ms")
    local c, v = R.ImGui_SliderDouble(ctx, "##first", S.first, r[1], r[2], fmt, flags)
    if c then S.first = v end
    R.ImGui_SetItemTooltip(ctx, "Time between the first and second hit")
    R.ImGui_SameLine(ctx)
    if R.ImGui_RadioButton(ctx, "Beats", S.unit == 0) and S.unit ~= 0 then S.unit = 0; S.first = 1 end
    R.ImGui_SetItemTooltip(ctx, "Follows the project tempo at the start point")
    R.ImGui_SameLine(ctx)
    if R.ImGui_RadioButton(ctx, "ms", S.unit == 1) and S.unit ~= 1 then S.unit = 1; S.first = 500 end
    R.ImGui_EndDisabled(ctx)
    slider(ctx, "Bounciness", "e", "%.2f", "How much of each gap is left for the next one.\nHigher = more hits, gaps shrink slower")
    slider(ctx, "Min gap", "min_gap", "%d ms", "Stops when the gap gets shorter than this (the ball comes to rest)")

    R.ImGui_SeparatorText(ctx, "Velocity & length")
    slider(ctx, "Min velocity", "vfloor", "%d", "Stops when the velocity drops below this")
    slider(ctx, "Decay curve", "curve", "%.2f", "1 = physically correct\n> 1 fades faster, < 1 keeps the tail louder")
    slider(ctx, "Note length", "len_pct", "%d %%", "Each note's share of the gap to the next hit")

    R.ImGui_SeparatorText(ctx, "Humanize")
    slider(ctx, "Timing", "jit_t", "± %d ms", "Random timing offset (never on the first hit, never enough to swap hits)")
    slider(ctx, "Velocity", "jit_v", "± %d", "Random velocity offset (never on the first hit)")

    R.ImGui_Separator(ctx)
    R.ImGui_BeginDisabled(ctx, S.jit_t == 0 and S.jit_v == 0)
    if R.ImGui_Button(ctx, "Reroll") then S.seed = math.random(1, 2147483646) end
    R.ImGui_EndDisabled(ctx)
    R.ImGui_SetItemTooltip(ctx, "New random humanize with the same settings")
    R.ImGui_SameLine(ctx)
    local bw = G.S(90)
    R.ImGui_SetCursorPosX(ctx, R.ImGui_GetWindowWidth(ctx) - bw * 2 - G.S(20))
    R.ImGui_BeginDisabled(ctx, not pl)
    local go = G.button(ctx, "Insert", bw)
        or (R.ImGui_IsKeyPressed(ctx, R.ImGui_Key_Enter()) and not R.ImGui_IsAnyItemActive(ctx))
    R.ImGui_EndDisabled(ctx)
    R.ImGui_SetItemTooltip(ctx, "Insert the notes and close (Enter)")
    R.ImGui_SameLine(ctx)
    if R.ImGui_Button(ctx, "Cancel", bw) then return false end
    R.ImGui_SetItemTooltip(ctx, "Close without changing anything (Esc)")

    if go and pl then
        insert(take, pl)
        return false -- on_close saves the settings
    end
end, { w = 480, h = 680, on_close = save })
