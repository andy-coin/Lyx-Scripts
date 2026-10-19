-- @description Lyx MIDI Note Quantize Filter
-- @version 1.00
-- @author Lyx
-- @about
--   Quantize MIDI note positions with a filter threshold and weighted pull.
--   Also supports quantizing note lengths to grid lines.
--   GUI style based on Lyx_MIDI_note_compressor_and_expander.lua (ReaImGui).

local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
package.path = package.path .. ";" .. script_path .. "?.lua"
local _, _ = pcall(require, "_Lyx_HOME")

-------------------------------------------------------------------------------
-- ReaImGui check
-------------------------------------------------------------------------------
if not reaper.ImGui_GetVersion then
    reaper.MB(
        "This script needs the ReaImGui extension.\n\n" ..
        "To install it:\n" ..
        "1) REAPER → Extensions → ReaPack → Browse packages\n" ..
        "2) Search for \"ReaImGui\"\n" ..
        "3) Right-click → Install, then restart REAPER\n\n" ..
        "Then run this script again.",
        "ReaImGui missing", 0)
    return
end

local ImGui = {}
for fname, func in pairs(reaper) do
    local name = fname:match("^ImGui_(.+)$")
    if name then ImGui[name] = func end
end

local SCRIPT_NAME = "Lyx: MIDI Quantize Filter"
local EXT_SECTION = "Lyx_MIDI_Quantize"

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- Undo：一次「操作」（放開滑桿、按下按鈕、勾選選項）才產生一個 undo point。
-- 滑桿拖動期間只在第一次真的寫入音符時 Undo_BeginBlock()，放開滑桿時
-- Undo_EndBlock()（見 ensure_undo_block / finish_undo_block）。不再把整個
-- 腳本執行期間包成一個永遠不關閉的 block（那樣期間內在 REAPER 做的任何
-- 其他操作都會被吞進同一個 undo point）。腳本中途被關閉時由 atexit 補上 End。
-- Undo: one gesture (release a slider, press a button, tick an option) makes one undo point.
-- While dragging, Undo_BeginBlock() runs on the first real note write and Undo_EndBlock() on release
-- (see ensure_undo_block / finish_undo_block). The script no longer wraps its whole run in one block
-- that never closes (that swallowed every other REAPER edit into the same undo point).
-- If the script is closed midway, atexit adds the End.
-------------------------------------------------------------------------------
local undo_block_open = false

-------------------------------------------------------------------------------
-- Toggle command state
-------------------------------------------------------------------------------
local _, _, section_id, cmd_id = reaper.get_action_context()
reaper.SetToggleCommandState(section_id, cmd_id, 1)
reaper.RefreshToolbar2(section_id, cmd_id)

local _

local function atexit()
    reaper.SetToggleCommandState(section_id, cmd_id, 0)
    reaper.RefreshToolbar2(section_id, cmd_id)
    if undo_block_open then
        reaper.Undo_EndBlock(SCRIPT_NAME, -1)
        undo_block_open = false
    end
end
reaper.atexit(atexit)

-------------------------------------------------------------------------------
-- ImGui context (must be created before any ImGui function calls)
-------------------------------------------------------------------------------
local ctx = ImGui.CreateContext(SCRIPT_NAME)
if not ctx then
    reaper.MB("Failed to create ImGui context.", "Error", 0)
    return
end

-------------------------------------------------------------------------------
-- Theme (copied from Lyx_MIDI_note_compressor_and_expander.lua)
-------------------------------------------------------------------------------
local function rgba(r, g, b, a)
    r = math.floor(math.max(0, math.min(255, r)))
    g = math.floor(math.max(0, math.min(255, g)))
    b = math.floor(math.max(0, math.min(255, b)))
    a = math.floor(math.max(0, math.min(255, a or 255)))
    return (r * 16777216) + (g * 65536) + (b * 256) + a
end

local DEFAULT_THEME = {
    bg        = rgba(30, 30, 38, 255),
    panel     = rgba(42, 42, 54, 255),
    text      = rgba(225, 225, 230, 255),
    text_dim  = rgba(160, 160, 170, 255),
    accent    = rgba(100, 200, 140, 255),
    slider    = rgba(70, 130, 200, 255),
    slider_act= rgba(110, 170, 240, 255),
    border    = rgba(70, 70, 80, 255),
    stat_val  = rgba(140, 220, 170, 255),
    indicator = rgba(255, 190, 60, 220), -- Show Indicator 虛線顏色（獨立於其他主題色） / Show Indicator dashed-line color (separate from the theme colors)
}

local theme = {}
for k, v in pairs(DEFAULT_THEME) do theme[k] = v end

local settings = {
    ui_scale = 1.0,
}

-- K() helper: handle ReaImGui constants that may be functions (newer) or numbers (older)
local function K(v)
    if type(v) == "function" then return v() end
    return v
end

local function load_settings()
    local function getN(k, def)
        local s = reaper.GetExtState(EXT_SECTION, k)
        if s == "" then return def end
        return tonumber(s) or def
    end
    for k in pairs(theme) do
        theme[k] = getN("theme_" .. k, DEFAULT_THEME[k])
    end
    settings.ui_scale = getN("ui_scale", 1.0)
end

local function save_settings()
    for k, v in pairs(theme) do
        reaper.SetExtState(EXT_SECTION, "theme_" .. k, tostring(v), true)
    end
    reaper.SetExtState(EXT_SECTION, "ui_scale", tostring(settings.ui_scale), true)
end

load_settings()

-------------------------------------------------------------------------------
-- Settings (quantize parameters)
-------------------------------------------------------------------------------
local defaults = {
    strength          = 100,
    filter_threshold  = 0,
    weighted_quantize = false,
    quantize_mode     = "position",  -- "position" or "length"
    show_indicator    = false,
}

local quantize = {
    strength          = 100,
    filter_threshold  = 0,
    weighted_quantize = false,
    quantize_mode     = "position",
    show_indicator    = false,
}

local function load_quantize_settings()
    local function getN(k, def)
        local s = reaper.GetExtState(EXT_SECTION, k)
        if s == "" then return def end
        return tonumber(s) or def
    end
    local function getB(k, def)
        local s = reaper.GetExtState(EXT_SECTION, k)
        if s == "" then return def end
        return s == "1"
    end
    local function getS(k, def)
        local s = reaper.GetExtState(EXT_SECTION, k)
        if s == "" then return def end
        return s
    end
    quantize.strength          = getN("strength", defaults.strength)
    quantize.filter_threshold  = getN("filter_threshold", defaults.filter_threshold)
    quantize.weighted_quantize = getB("weighted_quantize", defaults.weighted_quantize)
    quantize.quantize_mode     = getS("quantize_mode", defaults.quantize_mode)
    quantize.show_indicator    = getB("show_indicator", defaults.show_indicator)
    quantize.strength          = math.max(0, math.min(100, quantize.strength))
    quantize.filter_threshold  = math.max(0, math.min(100, quantize.filter_threshold))
end

local function save_quantize_settings()
    reaper.SetExtState(EXT_SECTION, "strength", tostring(quantize.strength), true)
    reaper.SetExtState(EXT_SECTION, "filter_threshold", tostring(quantize.filter_threshold), true)
    reaper.SetExtState(EXT_SECTION, "weighted_quantize", quantize.weighted_quantize and "1" or "0", true)
    reaper.SetExtState(EXT_SECTION, "quantize_mode", quantize.quantize_mode, true)
    reaper.SetExtState(EXT_SECTION, "show_indicator", quantize.show_indicator and "1" or "0", true)
end

load_quantize_settings()

-------------------------------------------------------------------------------
-- State management
--
-- takes_data[take] = { notes = { rec, ... } }
--   rec.orig_start/orig_end : 擷取當下的原始頭尾（整數 PPQ，永不覆寫）
--   rec.want_start/want_end : 「想要」的頭尾（尚未處理重疊）。被選取的音符每次
--                             apply 都從 orig 重新算；沒被選取的音符保持上一次
--                             的 want。重疊處理永遠是 want → cur 的純函式，
--                             所以被鄰居吃掉的尾巴在鄰居移開／RESET 後會自動恢復。
--   rec.cur_start/cur_end   : 目前實際寫在 take 裡的頭尾（整數 PPQ）
--   rec.idx / rec.selected  : 每次 apply 前由 relocate_notes 重新對應
--   rec.orig_*: original start/end when captured (integer PPQ, never overwritten)
--   rec.want_*: wanted start/end before overlap handling; selected notes recompute from orig on every
--     apply, unselected notes keep their last want. Overlap handling is a pure want -> cur function,
--     so a tail eaten by a neighbour comes back when the neighbour moves away / RESET.
--   rec.cur_*: start/end actually written in the take (integer PPQ)
--   rec.idx / rec.selected: re-matched by relocate_notes before every apply
-------------------------------------------------------------------------------
local takes_data = {}
local active_takes = {}
local EPS = 1e-6 -- QN 單位的浮點容許誤差 / float tolerance in QN

local function round(x) return math.floor(x + 0.5) end

local function is_valid_take(t)
    return t and reaper.ValidatePtr2(0, t, "MediaItem_Take*") and reaper.TakeIsMIDI(t)
end

-- MIDI Editor 一旦失焦（點到 ImGui 視窗），MIDIEditor_GetActive() 就會回傳 nil，
-- 所以要記住最後一個 MIDI Editor，不然一操作滑桿就找不到 take。
-- Once the MIDI Editor loses focus (clicking the ImGui window) MIDIEditor_GetActive() returns nil,
-- so remember the last MIDI Editor, or moving a slider would find no take.
local last_me = nil

local function collect_takes()
    local me = reaper.MIDIEditor_GetActive()
    if me then last_me = me end
    if last_me then
        local ok, t = pcall(reaper.MIDIEditor_GetTake, last_me)
        if ok and is_valid_take(t) then
            return { t } -- MIDI Editor 開著時只處理它正在編輯的 take / with a MIDI Editor open, only its edited take
        end
        last_me = nil    -- 該 MIDI Editor 已關閉 / that MIDI Editor was closed
    end
    local takes, seen = {}, {}
    for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local t = item and reaper.GetActiveTake(item)
        if is_valid_take(t) and not seen[t] then
            takes[#takes + 1] = t
            seen[t] = true
        end
    end
    return takes
end

local function capture_take_baseline(take)
    if takes_data[take] then return takes_data[take], false end
    local _, note_cnt = reaper.MIDI_CountEvts(take)
    local notes = {}
    for n = 0, note_cnt - 1 do
        local _, sel, _, s, e, chan, pitch, vel = reaper.MIDI_GetNote(take, n)
        s, e = round(s), round(e)
        notes[#notes + 1] = {
            orig_start = s, orig_end = e,
            want_start = s, want_end = e,
            cur_start  = s, cur_end  = e,
            pitch = pitch, chan = chan, vel = vel,
            idx = n, selected = sel,
        }
    end
    takes_data[take] = { notes = notes }
    return takes_data[take], true
end

local function note_key(pitch, chan, vel, s, e)
    return string.format("%d|%d|%d|%d|%d", pitch, chan, vel, round(s), round(e))
end

-- 重新對應 idx / selected。回傳 false 代表 take 已經被腳本以外的操作改過
-- （增刪音符、手動移動、Ctrl+Z…），此時舊 baseline 不可信。
-- Re-match idx / selected. Returns false when the take was changed outside the script
-- (notes added/removed, moved by hand, Ctrl+Z...); then the old baseline can't be trusted.
local function relocate_notes(take, data)
    local _, cnt = reaper.MIDI_CountEvts(take)
    if cnt ~= #data.notes then return false end
    local lookup = {}
    for n = 0, cnt - 1 do
        local _, sel, _, s, e, chan, pitch, vel = reaper.MIDI_GetNote(take, n)
        local k = note_key(pitch, chan, vel, s, e)
        local b = lookup[k]
        if not b then b = {}; lookup[k] = b end
        b[#b + 1] = { idx = n, selected = sel }
    end
    for _, rec in ipairs(data.notes) do
        local b = lookup[note_key(rec.pitch, rec.chan, rec.vel, rec.cur_start, rec.cur_end)]
        if not b or #b == 0 then return false end
        local hit = table.remove(b, 1)
        rec.idx, rec.selected = hit.idx, hit.selected
    end
    return true
end

-- 取得「已同步」的 baseline；不同步就以目前狀態重新擷取，而不是靜默地讓所有音符失效 / get a baseline that is in sync; if not, recapture the current state instead of silently invalidating every note
local function get_synced_data(take)
    local data = takes_data[take]
    if data and not relocate_notes(take, data) then
        takes_data[take] = nil
        data = nil
    end
    if not data then
        data = capture_take_baseline(take)
    end
    return data
end

-------------------------------------------------------------------------------
-- Grid / pull helpers（position 與 length 共用，不再各寫一份） / shared by position and length
-------------------------------------------------------------------------------
local function ppq_to_qn(take, ppq) return reaper.MIDI_GetProjQNFromPPQPos(take, ppq) end
local function qn_to_ppq(take, qn)  return round(reaper.MIDI_GetPPQPosFromProjQN(take, qn)) end

local function nearest_grid(q, g) return math.floor(q / g + 0.5) * g end

local function on_grid(q, g)
    local r = q / g
    return math.abs(r - math.floor(r + 0.5)) < EPS
end

-- 嚴格落在 (a, b) 之間的 grid 線（端點剛好在線上的不算） / grid lines strictly inside (a, b); an end exactly on a line does not count
local function grid_lines_inside(a, b, g)
    local lines = {}
    local gi = math.floor(a / g - EPS)
    local gi_end = math.ceil(b / g + EPS)
    for i = gi, gi_end do
        local x = i * g
        if x > a + EPS and x < b - EPS then lines[#lines + 1] = x end
    end
    return lines
end

-- 從原始位置往目標位置拉。Weighted 的距離以「半格」正規化：
-- 半格以上一律滿拉力（position 模式的最大距離就是半格，
-- 舊版用整格正規化，導致 Strength 100% 時最遠的音符也只拉到 50%）
-- Pull from the original toward the target. Weighted distance is normalised to half a grid:
-- half a grid or more pulls fully (in position mode the max distance is half a grid; the old
-- version normalised to a whole grid, so at Strength 100% the farthest notes only moved 50%).
local function pull(orig, target, P)
    local dist = math.abs(target - orig)
    if dist < EPS or dist <= P.thresh then return orig end
    local f = P.strength
    if P.weighted then f = f * math.min(dist / (P.grid * 0.5), 1) end
    return orig + (target > orig and 1 or -1) * dist * f
end

local function position_target(take, rec, P)
    local q = ppq_to_qn(take, rec.orig_start)
    local nq = pull(q, nearest_grid(q, P.grid), P)
    local s = (nq == q) and rec.orig_start or qn_to_ppq(take, nq)
    return s, s + (rec.orig_end - rec.orig_start)
end

-- Length 模式： / Length mode:
--   頭尾都在 grid 上         → 不動 / start and end on the grid -> no change
--   中間沒有 grid 線         → 填滿所在那一格 / no grid line inside -> fill the cell it is in
--   中間恰一條線 X（頭尾都不在線上）→ 頭近：頭收到 X、尾到下一條；尾近：尾收到 X、頭到上一條 / exactly one line X inside (ends off-grid) -> start closer: start to X, end to next line; end closer: end to X, start to previous line
--   其他（≥2 條線，或恰一條線但頭/尾有一端已在線上）→ 頭尾各自找最近的 grid / otherwise (2+ lines, or one line with an end already on a line) -> each end to its nearest grid line
local function length_target(take, rec, P)
    local g = P.grid
    local sq = ppq_to_qn(take, rec.orig_start)
    local eq = ppq_to_qn(take, rec.orig_end)
    local head_on, tail_on = on_grid(sq, g), on_grid(eq, g)
    local inside = grid_lines_inside(sq, eq, g)
    local ts, te
    if head_on and tail_on then
        ts, te = sq, eq
    elseif #inside == 0 then
        local w = math.floor(sq / g + EPS) * g
        ts, te = w, w + g
    elseif #inside == 1 and not head_on and not tail_on then
        local x = inside[1]
        if x - sq <= eq - x then ts, te = x, x + g else ts, te = x - g, x end
    else
        ts, te = nearest_grid(sq, g), nearest_grid(eq, g)
    end
    local ns, ne = pull(sq, ts, P), pull(eq, te, P)
    local sp = (ns == sq) and rec.orig_start or qn_to_ppq(take, ns)
    local ep = (ne == eq) and rec.orig_end   or qn_to_ppq(take, ne)
    if ep <= sp then ep = sp + 1 end
    return sp, ep
end

-------------------------------------------------------------------------------
-- want → cur：只在「同 pitch + 同 channel」的音符之間處理重疊，
-- 且只會縮短前一顆的尾巴（絕不動後一顆的 START、不刪音符）。
-- 全部音符（含未選取）都參與，並且每次都從 want 重算，所以不吃歷史、可還原。
-- want -> cur: overlaps are handled only between notes of the same pitch + channel,
-- and only by shortening the earlier note's tail (never moves the later START, never deletes).
-- All notes (unselected too) take part and it is recomputed from want every time: no history, reversible.
-------------------------------------------------------------------------------
local function changed(rec)
    return rec.want_start ~= rec.orig_start or rec.want_end ~= rec.orig_end
end

local function flush(take, data)
    local groups = {}
    for _, rec in ipairs(data.notes) do
        local key = rec.pitch * 16 + rec.chan
        local list = groups[key]
        if not list then list = {}; groups[key] = list end
        list[#list + 1] = rec
    end
    for _, list in pairs(groups) do
        table.sort(list, function(a, b)
            if a.want_start ~= b.want_start then return a.want_start < b.want_start end
            return a.orig_start < b.orig_start
        end)
        for i, rec in ipairs(list) do
            local e = rec.want_end
            local nxt = list[i + 1]
            -- 只處理「這次由腳本造成」的重疊；原本就存在的重疊維持原樣（RESET 才能完整還原） / only fix overlaps this script caused; overlaps that were already there stay (RESET restores everything)
            if nxt and e > nxt.want_start and (changed(rec) or changed(nxt)) then
                e = nxt.want_start
            end
            if e <= rec.want_start and (e ~= rec.want_end or changed(rec)) then
                e = rec.want_start + 1
            end
            rec.final_start, rec.final_end = rec.want_start, e
        end
    end

    reaper.MIDI_DisableSort(take)
    for _, rec in ipairs(data.notes) do
        if rec.final_start ~= rec.cur_start or rec.final_end ~= rec.cur_end then
            reaper.MIDI_SetNote(take, rec.idx, nil, nil, rec.final_start, rec.final_end, nil, nil, nil, true)
            rec.cur_start, rec.cur_end = rec.final_start, rec.final_end
        end
    end
    reaper.MIDI_Sort(take)
end

-------------------------------------------------------------------------------
-- Undo：一次「操作」（放開滑桿／按鈕／勾選）才產生一個 undo point，
-- 而不是整個腳本執行期間只開一個永遠不關的 block。
-- Undo: one gesture (release slider / button / tick) makes one undo point,
-- instead of one block left open for the whole run of the script.
-------------------------------------------------------------------------------
local function ensure_undo_block()
    if not undo_block_open then
        reaper.Undo_BeginBlock()
        undo_block_open = true
    end
end

local function finish_undo_block()
    if undo_block_open then
        reaper.Undo_EndBlock(SCRIPT_NAME, -1)
        undo_block_open = false
    end
end

-------------------------------------------------------------------------------
-- Apply / Reset
-------------------------------------------------------------------------------
local function apply_quantize()
    for _, take in ipairs(active_takes) do
        local grid = reaper.MIDI_GetGrid(take)
        if grid and grid > 0 then
            local data = get_synced_data(take)
            local P = {
                grid     = grid,
                strength = quantize.strength / 100.0,
                thresh   = grid * (quantize.filter_threshold / 100.0),
                weighted = quantize.weighted_quantize,
            }
            local target = (quantize.quantize_mode == "length") and length_target or position_target
            for _, rec in ipairs(data.notes) do
                if rec.selected then
                    rec.want_start, rec.want_end = target(take, rec, P)
                end
            end
            flush(take, data)
        end
    end
end

local function reset_to_original()
    for _, take in ipairs(active_takes) do
        local data = get_synced_data(take)
        for _, rec in ipairs(data.notes) do
            if rec.selected then
                rec.want_start, rec.want_end = rec.orig_start, rec.orig_end
            end
        end
        flush(take, data)
    end
end

-------------------------------------------------------------------------------
-- push_theme / pop_theme
-------------------------------------------------------------------------------
local THEME_COLOR_COUNT = 21

local function push_theme()
    ImGui.PushStyleColor(ctx, K(ImGui.Col_WindowBg),        theme.bg)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_PopupBg),         theme.bg)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_ChildBg),         theme.panel)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_Border),          theme.border)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_FrameBg),         theme.panel)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_FrameBgHovered),  theme.panel)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_FrameBgActive),   theme.panel)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_Text),            theme.text)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_TextDisabled),    theme.text_dim)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_Button),          theme.panel)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_ButtonHovered),   theme.slider)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_ButtonActive),    theme.slider_act)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_SliderGrab),      theme.slider)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_SliderGrabActive),theme.slider_act)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_CheckMark),       theme.accent)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_Header),          theme.panel)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_HeaderHovered),   theme.slider)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_HeaderActive),    theme.slider_act)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_Separator),       theme.border)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_Tab),             theme.panel)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_TabHovered),      theme.slider)
end

local function pop_theme()
    ImGui.PopStyleColor(ctx, THEME_COLOR_COUNT)
end

-- Color editor row
local function color_row(label, key)
    ImGui.PushID(ctx, key)
    local changed, new_col = ImGui.ColorEdit4(ctx, label, theme[key],
        K(ImGui.ColorEditFlags_NoInputs) + K(ImGui.ColorEditFlags_AlphaBar))
    if changed then
        theme[key] = new_col
        save_settings()
    end
    ImGui.PopID(ctx)
end

-- Settings popup content
local function draw_settings()
    ImGui.Text(ctx, "Theme Colors")
    color_row("Background",        "bg")
    color_row("Panel",             "panel")
    color_row("Text",              "text")
    color_row("Text (dim)",        "text_dim")
    color_row("Accent",            "accent")
    color_row("Slider",            "slider")
    color_row("Slider (active)",   "slider_act")
    color_row("Border",            "border")
    color_row("Stat value",        "stat_val")
    color_row("Indicator (dashed lines)", "indicator")

    ImGui.Separator(ctx)
    if ImGui.Button(ctx, "Reset theme to defaults") then
        for k, v in pairs(DEFAULT_THEME) do theme[k] = v end
        save_settings()
    end
end

-------------------------------------------------------------------------------
-- Show Indicator Drawing
-------------------------------------------------------------------------------
-- Draw threshold/indicator lines on the MIDI editor piano roll.
-- Uses the MIDI editor's own window rect and view range to map QN → screen X.
-- Rendered via the foreground drawlist so lines overlay the piano roll.
-------------------------------------------------------------------------------
local warned_missing_indicator_api = false

local function draw_indicator(take)
    if not quantize.show_indicator then return end

    -- 這個功能需要 js_ReaScriptAPI（抓 MIDI Editor 視窗在螢幕上的位置）
    -- 和 SWS（BR_GetMidiVisibleArea，抓 piano roll 目前可視的時間範圍）
    -- 兩個擴充功能。缺任何一個就沒辦法把虛線畫在 MIDI Editor 上，這裡直接
    -- 跳過並提醒一次，而不是每一幀都嘗試、每一幀都失敗。
    -- This needs js_ReaScriptAPI (MIDI Editor window position on screen) and
    -- SWS (BR_GetMidiVisibleArea, the visible time range of the piano roll).
    -- Without either the dashed lines can't be drawn, so skip and warn once
    -- instead of trying and failing every frame.
    if not reaper.APIExists("JS_Window_GetClientRect") or not reaper.APIExists("BR_GetMidiVisibleArea") then
        if not warned_missing_indicator_api then
            warned_missing_indicator_api = true
            reaper.MB(
                "Show Indicator needs these two extensions to draw dashed lines on the MIDI Editor piano roll:\n\n" ..
                "1) js_ReaScriptAPI (for JS_Window_GetClientRect)\n" ..
                "2) SWS Extension (for BR_GetMidiVisibleArea)\n\n" ..
                "Install them via Extensions → ReaPack → Browse packages, then reopen this script.",
                "Show Indicator: missing extensions", 0)
        end
        return
    end

    local midiedit = reaper.MIDIEditor_GetActive()
    if not midiedit then return end

    local grid_qn = reaper.MIDI_GetGrid(take)
    if grid_qn <= 0 then return end

    -- MIDI Editor 視窗在螢幕上的座標（piano roll 所在的視窗） / screen rect of the MIDI Editor window (where the piano roll is)
    local client_ok, me_left, me_top, me_right, me_bottom = reaper.JS_Window_GetClientRect(midiedit)
    if not client_ok or me_right <= me_left or me_bottom <= me_top then return end

    local me_w = me_right - me_left
    local me_h = me_bottom - me_top
    if me_w <= 0 or me_h <= 0 then return end

    -- piano roll 目前實際可視的時間範圍（BR_GetMidiVisibleArea 回傳的是
    -- 專案時間/秒，換算成 QN 才能跟 grid_qn 對齊）
    -- visible time range of the piano roll (BR_GetMidiVisibleArea gives project
    -- seconds; converted to QN to line up with grid_qn)
    local br_ok, view_start_time, view_end_time = reaper.BR_GetMidiVisibleArea(take)
    if not br_ok then return end
    local view_start_qn = reaper.TimeMap2_timeToQN(0, view_start_time)
    local view_end_qn   = reaper.TimeMap2_timeToQN(0, view_end_time)
    local view_span_qn  = view_end_qn - view_start_qn
    if view_span_qn <= 0 then return end

    local thresh_qn = grid_qn * (quantize.filter_threshold / 100.0)
    local draw_col  = theme.indicator
    local dash_len  = math.max(4, math.floor(8 * settings.ui_scale))
    local gap_len   = math.max(2, math.floor(4 * settings.ui_scale))

    -- 虛線長度為 piano roll 高度的 90%，置中（上下各留 5% 邊界） / dashed line is 90% of the piano roll height, centered (5% margin top and bottom)
    local y_top    = me_top + me_h * 0.05
    local y_bottom = me_bottom - me_h * 0.05

    -- Helper: map QN → screen X
    local function qn_to_x(qn)
        local ratio = (qn - view_start_qn) / view_span_qn
        return me_left + ratio * me_w
    end

    local draw_list = ImGui.GetForegroundDrawList(ctx)

    local function draw_dashed_vline(x)
        if x < me_left or x > me_right then return end
        local cy = y_top
        while cy < y_bottom do
            local seg_end = math.min(cy + dash_len, y_bottom)
            ImGui.DrawList_AddLine(draw_list, x, cy, x, seg_end, draw_col, 1.2)
            cy = seg_end + gap_len
        end
    end

    -- 只畫「目前可視範圍」涵蓋到的 grid 線，不用管整個 item 有多長 / draw only grid lines in the visible range, whatever the item length
    local first_grid_qn = math.floor(view_start_qn / grid_qn) * grid_qn
    local last_grid_qn  = math.ceil(view_end_qn / grid_qn) * grid_qn

    local grid_q = first_grid_qn
    while grid_q <= last_grid_qn do
        if quantize.quantize_mode == "length" then
            -- Note Length 模式：每個 grid 左右兩側各畫一條 threshold 虛線，形成一個 band / Note Length mode: one threshold line on each side of every grid line, forming a band
            draw_dashed_vline(qn_to_x(grid_q - thresh_qn))
            draw_dashed_vline(qn_to_x(grid_q + thresh_qn))
        else
            -- Note Position 模式：只在每個 grid 的右方畫一條 threshold 虛線 / Note Position mode: one threshold line right of every grid line
            draw_dashed_vline(qn_to_x(grid_q + thresh_qn))
        end

        grid_q = grid_q + grid_qn
    end
end

-------------------------------------------------------------------------------
-- Font helper (ctx already created above)
-------------------------------------------------------------------------------

-- Font helper
local fonts = {}
local font_sizes = {}
local function build_fonts()
    local base = math.floor(14 * settings.ui_scale + 0.5)
    -- 先算好所有尺寸，再用來建立字型（原本的順序是先建立 h1/small
    -- 字型、才計算 font_sizes.h1/small，導致第一次呼叫時拿到 nil）
    -- compute all sizes first, then build the fonts (the old order built h1/small
    -- before font_sizes.h1/small existed, so the first call got nil)
    font_sizes.body = base
    font_sizes.h1 = math.floor(base * 1.3 + 0.5)
    font_sizes.small = math.max(10, base - 2)
    fonts.body = ImGui.CreateFont('sans-serif', font_sizes.body)
    fonts.h1 = ImGui.CreateFont('sans-serif', font_sizes.h1)
    fonts.small = ImGui.CreateFont('sans-serif', font_sizes.small)
    ImGui.Attach(ctx, fonts.body)
    ImGui.Attach(ctx, fonts.h1)
    ImGui.Attach(ctx, fonts.small)
end
build_fonts()

local function push_font(name)
    ImGui.PushFont(ctx, fonts[name], font_sizes[name] or 14)
end

-------------------------------------------------------------------------------
-- Bypass state
-------------------------------------------------------------------------------
local bypass = false
local show_settings = false
local needs_apply = false     -- 本 frame 有參數變動，需要重新 apply / a parameter changed this frame, apply again
local commit_pending = false  -- 本 frame 操作已結束，可以關閉 undo block / the gesture ended this frame, the undo block can close

-------------------------------------------------------------------------------
-- Main GUI
-------------------------------------------------------------------------------
local function draw_main()
    -- Poll for changes
    local new_takes = collect_takes()
    local take_changed = (#new_takes ~= #active_takes)
    if not take_changed then
        for i = 1, #new_takes do
            if new_takes[i] ~= active_takes[i] then take_changed = true; break end
        end
    end
    if take_changed then
        active_takes = new_takes
        -- 只擷取 baseline，不自動 apply（否則一開腳本就會用上次存下的
        -- Strength 直接改動音符）
        -- only capture the baseline, no auto apply (otherwise opening the script
        -- would change notes with the last saved Strength)
        for _, t in ipairs(active_takes) do
            capture_take_baseline(t)
        end
    end

    -- 主題色 (push_theme) 只在 main() 的 Begin() 之前呼叫一次即可，
    -- 這裡不能再呼叫，否則會在同一個視窗的 Begin/End 之間多推入 21 個
    -- PushStyleColor 卻沒有對應的 Pop，導致 ImGui_End 丟出
    -- "Missing PopStyleColor()"（對齊 compressor 腳本的作法）
    -- the theme (push_theme) is pushed once before Begin() in main(); calling it here
    -- pushed 21 more PushStyleColor inside Begin/End with no Pop, and ImGui_End threw
    -- "Missing PopStyleColor()" (same as the compressor script)

    local ui = settings.ui_scale
    push_font("body")

    -- Header
    push_font("h1")
    ImGui.TextColored(ctx, theme.accent, "MIDI Quantize Filter")
    ImGui.PopFont(ctx)

    ImGui.Separator(ctx)

    -- Source info
    local source_txt
    if #active_takes == 0 then
        source_txt = "(no MIDI take)"
    else
        source_txt = string.format("%d take%s", #active_takes, #active_takes == 1 and "" or "s")
    end
    push_font("small")
    ImGui.TextColored(ctx, theme.text_dim, source_txt)
    ImGui.PopFont(ctx)

    ImGui.Dummy(ctx, 0, 8 * ui)

    -- Quantize Mode dropdown
    ImGui.Text(ctx, "Quantize Mode")
    local mode_labels = { ["position"] = "Note Position", ["length"] = "Note Length" }
    local mode_idx = quantize.quantize_mode == "length" and 1 or 0
    local ch_mode, new_mode_idx = ImGui.Combo(ctx, "##quant_mode", mode_idx, mode_labels["position"] .. "\0" .. mode_labels["length"] .. "\0", 2)
    if ch_mode and new_mode_idx ~= mode_idx then
        quantize.quantize_mode = new_mode_idx == 1 and "length" or "position"
        save_quantize_settings()
        needs_apply, commit_pending = true, true
    end

    ImGui.Dummy(ctx, 0, 8 * ui)

    -- Strength slider
    ImGui.Text(ctx, string.format("Strength  %d%%", quantize.strength))
    ImGui.SetNextItemWidth(ctx, 280 * ui)
    local ch_s, v_s = ImGui.SliderInt(ctx, "##strength", quantize.strength, 0, 100, "")
    if ch_s then
        quantize.strength = v_s
        needs_apply = true
    end
    if ImGui.IsItemDeactivated(ctx) then
        commit_pending = true
        save_quantize_settings()
    end

    -- Filter Threshold slider
    ImGui.Dummy(ctx, 0, 8 * ui)
    ImGui.Text(ctx, string.format("Filter Threshold  %d%%", quantize.filter_threshold))
    ImGui.SetNextItemWidth(ctx, 280 * ui)
    local ch_f, v_f = ImGui.SliderInt(ctx, "##filter_threshold", quantize.filter_threshold, 0, 100, "")
    if ch_f then
        quantize.filter_threshold = v_f
        needs_apply = true
    end
    if ImGui.IsItemDeactivated(ctx) then
        commit_pending = true
        save_quantize_settings()
    end

    -- Weighted Quantize checkbox
    ImGui.Dummy(ctx, 0, 8 * ui)
    local ch_w, v_w = ImGui.Checkbox(ctx, "Weighted Quantize", quantize.weighted_quantize)
    if ch_w then
        quantize.weighted_quantize = v_w
        save_quantize_settings()
        needs_apply, commit_pending = true, true
    end
    if quantize.weighted_quantize and ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "Farther notes get more pull, closer notes get less")
    end

    -- Show Indicator checkbox
    ImGui.Dummy(ctx, 0, 8 * ui)
    local ch_i, v_i = ImGui.Checkbox(ctx, "Show Indicator", quantize.show_indicator)
    if ch_i then
        quantize.show_indicator = v_i
        save_quantize_settings()
    end

    -- 所有參數 widget 處理完後，同一個 frame 最多 apply 一次。
    -- 調整參數時自動離開 ORIGINAL（bypass）狀態，否則參數變了卻沒任何反應。
    -- after all parameter widgets, apply at most once per frame.
    -- Changing a parameter leaves ORIGINAL (bypass), or nothing would seem to happen.
    if needs_apply then
        needs_apply = false
        bypass = false
        ensure_undo_block()
        apply_quantize()
    end
    if commit_pending then
        commit_pending = false
        finish_undo_block()
    end

    ImGui.Dummy(ctx, 0, 12 * ui)
    ImGui.Separator(ctx)
    ImGui.Dummy(ctx, 0, 8 * ui)

    -- Action buttons
    local btn_w = 120 * ui
    local btn_h = 32 * ui

    -- Bypass toggle button：CURRENT（套用量化後的狀態）／ORIGINAL（還原原始音符）
    -- 用底色區分兩種狀態：CURRENT 用強調色，ORIGINAL 用較暗的面板色
    -- Bypass toggle: CURRENT (quantized) / ORIGINAL (original notes);
    -- CURRENT uses the accent color, ORIGINAL the darker panel color
    local bypass_col = bypass and theme.panel or theme.accent

    ImGui.PushStyleColor(ctx, K(ImGui.Col_Button), bypass_col)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_ButtonHovered), theme.slider)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_ButtonActive), theme.slider_act)
    local clicked = ImGui.Button(ctx, bypass and "ORIGINAL" or "CURRENT", btn_w, btn_h)
    ImGui.PopStyleColor(ctx, 3)
    if clicked then
        bypass = not bypass
        ensure_undo_block()
        if bypass then
            -- 切到 ORIGINAL：把選取的音符還原成原始位置（baseline 保留） / to ORIGINAL: put selected notes back where they were (baseline kept)
            reset_to_original()
        else
            -- 切回 CURRENT：用目前的設定重新套用量化 / back to CURRENT: re-apply quantize with the current settings
            apply_quantize()
        end
        finish_undo_block()
    end
    if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, bypass and "Showing original notes (click to re-apply quantize)" or "Quantize applied (click to preview original)")
    end

    ImGui.SameLine(ctx, btn_w + 12 * ui)
    if ImGui.Button(ctx, "RESET", btn_w, btn_h) then
        ensure_undo_block()
        reset_to_original()
        finish_undo_block()
    end
    if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "Restore notes to original positions")
    end

    ImGui.SameLine(ctx, (btn_w + 12 * ui) * 2)
    if ImGui.Button(ctx, "SETTINGS", btn_w, btn_h) then
            show_settings = not show_settings
        end
    if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "Theme colors and UI settings")
    end

    -- Footer
    ImGui.Dummy(ctx, 0, 8 * ui)
    push_font("small")
    ImGui.TextColored(ctx, theme.text_dim, string.format("v1.00"))
    ImGui.PopFont(ctx)

    ImGui.PopFont(ctx) -- 對應函式開頭的 push_font("body") / matches push_font("body") at the top of the function
end

-------------------------------------------------------------------------------
-- Main loop
-------------------------------------------------------------------------------
local function main()
    push_theme()

    -- Main window
    ImGui.SetNextWindowSize(ctx, 360 * settings.ui_scale, 440 * settings.ui_scale, K(ImGui.Cond_FirstUseEver))
    local visible, open = ImGui.Begin(ctx, SCRIPT_NAME, true, K(ImGui.WindowFlags_NoCollapse))
    if visible then
        ImGui.SetNextFrameWantCaptureKeyboard(ctx, true)
        draw_main()
        -- Draw indicator overlay for each active take
        if quantize.show_indicator then
            for _, t in ipairs(active_takes) do
                draw_indicator(t)
            end
        end
        if ImGui.IsKeyPressed(ctx, K(ImGui.Key_Escape), false) then
            open = false
        end
        ImGui.End(ctx)
    end

    -- Settings window
    if show_settings then
        ImGui.SetNextWindowSize(ctx, 320 * settings.ui_scale, 400 * settings.ui_scale, K(ImGui.Cond_FirstUseEver))
        local svis, sopen = ImGui.Begin(ctx, "Settings##quant", true, K(ImGui.WindowFlags_NoCollapse))
        if svis then
            draw_settings()
            ImGui.End(ctx)
        end
        if not sopen then show_settings = false end
    end

    pop_theme()

    if open then
        reaper.defer(main)
    end
end

reaper.defer(main)
