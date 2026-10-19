--[[
    _Lyx_MIDI_Tools.lua — shared engine for MIDI Editor scripts
      M.nav(dir)        dir = "left" | "right" | "up" | "down"   (desktop-style focus move)
      M.arp(sign)       sign = +1 increase / -1 decrease arpeggiation
      M.show_names()    billboard of selected note names (uses note-name map if loaded)
]]

local R = reaper
local M = {}

---------------------------------------------------------------------------
-- CUSTOM
---------------------------------------------------------------------------
-- Navigation cost is measured in beats. One semitone "costs" PITCH_W beats,
-- so with 0.25 a jump of 4 semitones weighs the same as one beat further away.
M.PITCH_W   = 0.25   -- left/right: how much a pitch change hurts (beats / semitone)
M.SAME_BONUS= 0.25   -- left/right: bonus for staying on the same pitch (beats)
M.START_W   = 1.0    -- up/down   : penalty per beat of start-time difference
M.GAP_W     = 2.0    -- up/down   : penalty per beat of gap when notes don't overlap
M.ARP_STEP_MS = 10   -- arpeggiation step per run (ms between neighbouring notes)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function read_notes(take)
    local notes = {}
    local _, cnt = R.MIDI_CountEvts(take)
    for i = 0, cnt - 1 do
        local _, sel, mu, s, e, ch, p, v = R.MIDI_GetNote(take, i)
        notes[#notes + 1] = { idx = i, sel = sel, mute = mu, s = s, e = e, ch = ch, p = p, v = v,
                              qs = R.MIDI_GetProjQNFromPPQPos(take, s),
                              qe = R.MIDI_GetProjQNFromPPQPos(take, e) }
    end
    return notes
end

---------------------------------------------------------------------------
-- Navigation (pure scoring, testable without REAPER)
---------------------------------------------------------------------------
-- returns the winning note table or nil
function M.pick(notes, dir)
    local sel = {}
    for _, n in ipairs(notes) do if n.sel then sel[#sel + 1] = n end end
    if #sel == 0 then return end

    local best, best_cost
    local function consider(n, cost)
        if not best_cost or cost < best_cost - 1e-9
           or (math.abs(cost - best_cost) < 1e-9 and n.qs < best.qs) then
            best, best_cost = n, cost
        end
    end

    if dir == "left" or dir == "right" then
        -- anchor = earliest (left) / latest (right) selected onset; pitch = mean of that onset
        local ref_q = sel[1].qs
        for _, n in ipairs(sel) do
            if (dir == "right" and n.qs > ref_q) or (dir == "left" and n.qs < ref_q) then ref_q = n.qs end
        end
        local sum, k = 0, 0
        for _, n in ipairs(sel) do if math.abs(n.qs - ref_q) < 1e-6 then sum, k = sum + n.p, k + 1 end end
        local ref_p = sum / k
        for _, n in ipairs(notes) do
            local dt = (dir == "right") and (n.qs - ref_q) or (ref_q - n.qs)
            if not n.sel and dt > 1e-6 then
                local dp = math.abs(n.p - ref_p)
                consider(n, dt + dp * M.PITCH_W - ((dp < 0.5) and M.SAME_BONUS or 0))
            end
        end
    else
        -- anchor = highest (up) / lowest (down) selected note
        local ref = sel[1]
        for _, n in ipairs(sel) do
            if (dir == "up" and n.p > ref.p) or (dir == "down" and n.p < ref.p) then ref = n end
        end
        for _, n in ipairs(notes) do
            local dp = (dir == "up") and (n.p - ref.p) or (ref.p - n.p)
            if not n.sel and dp > 0 then
                local gap = math.max(0, n.qs - ref.qe, ref.qs - n.qe)
                consider(n, dp * M.PITCH_W + math.abs(n.qs - ref.qs) * M.START_W + gap * M.GAP_W)
            end
        end
    end
    return best
end

function M.nav(dir)
    local editor = R.MIDIEditor_GetActive()
    local take = editor and R.MIDIEditor_GetTake(editor)
    if not take or not R.ValidatePtr(take, "MediaItem_Take*") then return end

    local notes = read_notes(take)
    local any_sel = false
    for _, n in ipairs(notes) do if n.sel then any_sel = true break end end
    if not any_sel then
        if dir == "left" then R.MIDIEditor_OnCommand(editor, 40047)
        elseif dir == "right" then R.MIDIEditor_OnCommand(editor, 40048) end
        return
    end

    local w = M.pick(notes, dir)
    if not w then return end
    R.Undo_BeginBlock()
    for _, n in ipairs(notes) do
        if n.sel then R.MIDI_SetNote(take, n.idx, false, nil, nil, nil, nil, nil, nil, true) end
    end
    R.MIDI_SetNote(take, w.idx, true, nil, nil, nil, nil, nil, nil, true)
    R.MIDI_Sort(take)
    R.MIDIEditor_SetSetting_int(editor, "active_note_row", w.p)
    R.Undo_EndBlock("Select note " .. dir, -1)
end

---------------------------------------------------------------------------
-- Arpeggiation (pure planner)
---------------------------------------------------------------------------
-- notes: {s,e (seconds), p, ch, sel}; returns { [note] = {s=,e=} } for notes that change
function M.plan_arp(notes, sign, step)
    local sel = {}
    for _, n in ipairs(notes) do if n.sel then sel[#sel + 1] = n end end
    table.sort(sel, function(a, b) return a.s < b.s or (a.s == b.s and a.p < b.p) end)

    -- chords: a note joins the chord if it starts before the chord's earliest note-off
    local chords, cur, cur_end = {}, nil, nil
    for _, n in ipairs(sel) do
        if cur and n.s < cur_end then
            cur[#cur + 1] = n
            cur_end = math.min(cur_end, n.e)
        else
            cur = { n }; cur_end = n.e
            chords[#chords + 1] = cur
        end
    end

    local plan = {}
    for _, ch in ipairs(chords) do
        if #ch > 1 then
            table.sort(ch, function(a, b) return a.p < b.p end)
            -- strum direction: up (low first) unless the top note already starts first
            if ch[#ch].s < ch[1].s then
                local rev = {}
                for i = #ch, 1, -1 do rev[#rev + 1] = ch[i] end
                ch = rev
            end
            local t = ch[1].s
            for i = 2, #ch do
                local gap = math.max(0, ch[i].s - ch[i - 1].s + sign * step)
                t = t + gap
                local d = t - ch[i].s
                if math.abs(d) > 1e-9 then plan[ch[i]] = { s = ch[i].s + d, e = ch[i].e + d } end
            end
        end
    end

    -- no overlap with same pitch/channel neighbours; their note-ons never move
    local by_key = {}
    for _, n in ipairs(notes) do
        local k = n.ch * 128 + n.p
        by_key[k] = by_key[k] or {}
        table.insert(by_key[k], n)
    end
    local function S(n) return plan[n] and plan[n].s or n.s end
    local function E(n) return plan[n] and plan[n].e or n.e end
    for _, list in pairs(by_key) do
        table.sort(list, function(a, b) return S(a) < S(b) end)
        for i = 1, #list - 1 do
            local a, b = list[i], list[i + 1]
            if E(a) > S(b) and S(a) < S(b) then
                plan[a] = plan[a] or { s = a.s, e = a.e }
                plan[a].e = S(b)
            end
        end
    end
    return plan
end

function M.arp(sign)
    local editor = R.MIDIEditor_GetActive()
    if not editor then return end
    R.Undo_BeginBlock()
    local i = 0
    while true do
        local take = R.MIDIEditor_EnumTakes(editor, i, true)
        if not take then break end
        local notes = read_notes(take)
        for _, n in ipairs(notes) do
            n.ppq_s, n.ppq_e = n.s, n.e
            n.s, n.e = R.MIDI_GetProjTimeFromPPQPos(take, n.s), R.MIDI_GetProjTimeFromPPQPos(take, n.e)
        end
        local plan = M.plan_arp(notes, sign, M.ARP_STEP_MS / 1000)
        if next(plan) then
            for n, t in pairs(plan) do
                R.MIDI_SetNote(take, n.idx, nil, nil,
                    R.MIDI_GetPPQPosFromProjTime(take, t.s), R.MIDI_GetPPQPosFromProjTime(take, t.e),
                    nil, nil, nil, true)
            end
            R.MIDI_Sort(take)
        end
        i = i + 1
    end
    R.Undo_EndBlock((sign > 0) and "Increase arpeggiation" or "Decrease arpeggiation", -1)
end

---------------------------------------------------------------------------
-- Note names
---------------------------------------------------------------------------
local NOTE = { "C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B" }
function M.pitch_name(p) return NOTE[p % 12 + 1] .. (p // 12 - 2) end

function M.show_names()
    local editor = R.MIDIEditor_GetActive()
    local take = editor and R.MIDIEditor_GetTake(editor)
    if not take then return end
    local track = R.GetMediaItemTake_Track(take)
    local seen, list = {}, {}
    local i = R.MIDI_EnumSelNotes(take, -1)
    while i ~= -1 do
        local _, _, _, _, _, ch, p = R.MIDI_GetNote(take, i)
        if not seen[p] then
            seen[p] = true
            local name = R.GetTrackMIDINoteNameEx(0, track, p, ch)
            list[#list + 1] = { p = p, label = (name and name ~= "") and name or M.pitch_name(p) }
        end
        i = R.MIDI_EnumSelNotes(take, i)
    end
    if #list == 0 then return end
    table.sort(list, function(a, b) return a.p < b.p end)
    local out = {}
    for k, v in ipairs(list) do out[k] = v.label end
    BBB(table.concat(out, " | "), 0.8, editor)
end

---------------------------------------------------------------------------
-- self-check: lua _Lyx_MIDI_Tools.lua
---------------------------------------------------------------------------
if not R then
    local function N(qs, qe, p, sel) return { qs = qs, qe = qe, p = p, sel = sel or false } end
    -- right: same pitch 2 beats away beats a 7-semitone jump half a beat away
    local a = N(0, 1, 60, true)
    local same, jump = N(2, 3, 60), N(0.5, 1, 67)
    assert(M.pick({ a, same, jump }, "right") == same)
    -- right: a step of 2 semitones right next door beats same pitch far away
    local step = N(1, 2, 62)
    assert(M.pick({ a, N(3, 4, 60), step }, "right") == step)
    -- right: chord notes at the same onset are never "next"
    assert(M.pick({ a, N(0, 1, 64) }, "right") == nil)
    -- left
    local prev = N(-1, 0, 59)
    assert(M.pick({ a, prev, N(-0.5, 0, 72) }, "left") == prev)
    -- up: chord tone above at same start beats a closer pitch starting later
    local E, D = N(0, 1, 64), N(1, 2, 62)
    assert(M.pick({ a, E, D }, "up") == E)
    -- up: nothing overlapping -> nearest above with gap penalty still found
    assert(M.pick({ a, N(5, 6, 65) }, "up") ~= nil)
    assert(M.pick({ a, N(0, 1, 55) }, "up") == nil)
    local low = N(0, 1, 55)
    assert(M.pick({ a, low }, "down") == low)

    -- arp: C E G at t=0, up-strum by 0.01
    local function T(s, e, p, sel) return { s = s, e = e, p = p, ch = 0, sel = sel ~= false } end
    local c, e, g = T(0, 1, 60), T(0, 1, 64), T(0, 1, 67)
    local plan = M.plan_arp({ c, e, g }, 1, 0.01)
    assert(plan[c] == nil and math.abs(plan[e].s - 0.01) < 1e-9 and math.abs(plan[g].s - 0.02) < 1e-9)
    assert(math.abs(plan[g].e - 1.02) < 1e-9)          -- whole note moves
    -- decrease back to block chord
    e.s, e.e, g.s, g.e = 0.01, 1.01, 0.02, 1.02
    plan = M.plan_arp({ c, e, g }, -1, 0.01)
    assert(math.abs(plan[e].s) < 1e-9 and math.abs(plan[g].s) < 1e-9)
    -- down-strum keeps direction (top note first)
    local c2, g2 = T(0.02, 1, 60), T(0, 1, 67)
    plan = M.plan_arp({ c2, g2 }, 1, 0.01)
    assert(math.abs(plan[c2].s - 0.03) < 1e-9)
    -- moved note end may not cover next same-pitch note-on (which stays put)
    local x, y, nxt = T(0, 1, 60), T(0, 1.0, 64), T(1.005, 2, 64, false)
    plan = M.plan_arp({ x, y, nxt }, 1, 0.01)
    assert(math.abs(plan[y].e - 1.005) < 1e-9 and plan[nxt] == nil)
    -- two separate chords handled independently
    local a1, a2, b1, b2 = T(0, 1, 60), T(0, 1, 64), T(2, 3, 60), T(2, 3, 64)
    plan = M.plan_arp({ a1, a2, b1, b2 }, 1, 0.01)
    assert(math.abs(plan[a2].s - 0.01) < 1e-9 and math.abs(plan[b2].s - 2.01) < 1e-9)
    assert(M.pitch_name(60) == "C3" and M.pitch_name(61) == "C#3")
    print("MIDI tools self-check OK")
end

return M
