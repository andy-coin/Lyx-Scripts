-- ==========================================================================
-- midi_editor.lua — Phase A: piano roll + event chart + toolbar + edit cursor
-- ==========================================================================
-- Layout:
--   [ toolbar: eye | channel▾ | CC▾ | H-/R/+ | V-/R/+ ]
--   +--- piano roll --+--- top ruler (bars/beats) ----+
--   |                 |  chart (notes/CC + grid)      |
--   |                 +--- bottom ruler (sec) --------+
-- 佈局: 頂部 toolbar + 左 piano roll + 上 ruler / 下 ruler / 中間 chart
--
-- Public entry: FUNC.draw_midi_editor_panel(c, x, y, w, h)
--   * 其餘 draw_* / stub 函式供 Phase B-E 逐步實作
--   * All Phase B-E stubs are declared at bottom with TODO markers

---------------------------------------------------------------------
-- 0. Defaults & view bootstrap
---------------------------------------------------------------------
-- velocity → 多段同色系漸層（每段內部淺→深，不跨色系混合）
-- per-band gradient (light→dark within same family, no cross-family blending)
local VEL_BANDS = {
  -- {lo, hi, light_rgb, dark_rgb}；高飽和+低亮度，邊界互相靠攏使銜接自然
  -- saturated yet dark; band edges blend for smoother transitions
  {0,   10,  {130,  60, 190}, { 90,  40, 170}},  -- 紫    → 偏藍紫
  {10,  20,  { 70,  60, 180}, { 30,  90, 200}},  -- 深藍  → 偏天藍
  {20,  35,  { 40, 140, 220}, { 30, 170, 200}},  -- 天空藍 → 偏青
  {35,  60,  { 30, 180, 170}, { 30, 175, 110}},  -- 藍綠  → 偏綠
  {60,  90,  { 50, 180,  70}, {150, 180,  30}},  -- 綠    → 偏黃綠
  {90,  110, {210, 190,  40}, {200, 150,  30}},  -- 黃    → 偏橘
  {110, 120, {190, 120,  40}, {200,  80,  40}},  -- 褐    → 偏紅
  {120, 127, {210,  60,  50}, {190,  30,  30}},  -- 紅
}
local function vel_rgb(v)
  v = math.max(0, math.min(127, v or 0))
  for _, b in ipairs(VEL_BANDS) do
    if v >= b[1] and v <= b[2] then
      local t = (v - b[1]) / math.max(1, (b[2] - b[1]))
      local a, d = b[3], b[4]
      return math.floor(a[1] + (d[1]-a[1])*t),
             math.floor(a[2] + (d[2]-a[2])*t),
             math.floor(a[3] + (d[3]-a[3])*t)
    end
  end
  return 200, 200, 200
end

FUNC._midi_view_defaults = {
  -- 顯示切換 -- display toggles (eye popup)
  show_notes     = true,
  show_ccs       = true,
  show_piano_lbl = true,
  show_note_name = true,
  show_velocity  = true,
  show_channel   = false,
  -- 視窗 / 縮放 / 捲動 -- viewport / zoom / scroll (Phase A)
  note_top       = -1,   -- 最上方可見 note number (-1=auto) -- topmost visible note (-1=auto)
  note_rows      = -1,   -- 可見 row 數 (-1=auto) -- visible row count
  scroll_qn      = 0,    -- 左緣 QN 偏移 -- left edge QN offset
  view_qn        = -1,   -- 可見 QN 範圍 (-1=fit whole item) -- visible span (-1=auto)
  -- ruler / filters / cursor -- ruler / 濾波器 / 游標
  start_bar      = 1,    -- ruler 起始小節數 -- starting bar number
  channel_filter = 0,    -- 0=all, 1..16 -- channel filter
  cc_lane_filter = -1,   -- -1=all, 0..127=CC#, 200=PC -- CC lane filter
  cursor_qn      = -1,   -- edit cursor (-1=none) -- edit cursor position
}

function FUNC.midi_editor_ensure_view(c)
  if not c.midi_view then c.midi_view = {} end
  for k, v in pairs(FUNC._midi_view_defaults) do
    if c.midi_view[k] == nil then c.midi_view[k] = v end
  end
  -- 執行期狀態 (非序列化) -- runtime-only state (not persisted)
  c._midi_sel     = c._midi_sel     or {}   -- {[idx]=true} — Phase B
  c._midi_marquee = c._midi_marquee or nil  -- marquee rect state — Phase B
end

---------------------------------------------------------------------
-- 1. Channel colors (16 palette) — for show_channel mode
---------------------------------------------------------------------
local CH_COLS = nil
local function get_ch_cols()
  if CH_COLS then return CH_COLS end
  CH_COLS = {
    FUNC.rgba( 80,160,220), FUNC.rgba(220,120, 80), FUNC.rgba(130,200,110),
    FUNC.rgba(200,160, 80), FUNC.rgba(180,100,200), FUNC.rgba( 80,200,200),
    FUNC.rgba(220,100,140), FUNC.rgba(140,180, 80), FUNC.rgba(200,140,100),
    FUNC.rgba(100,140,200), FUNC.rgba(180,140,200), FUNC.rgba(140,200,160),
    FUNC.rgba(220,200,100), FUNC.rgba(160,100,160), FUNC.rgba(100,180,180),
    FUNC.rgba(200,100,100),
  }
  return CH_COLS
end

---------------------------------------------------------------------
-- 2. Geometry helpers
---------------------------------------------------------------------
-- 事件範圍 auto-fit：note_lo/note_hi (外擴 3 semitones，至少 12 rows)
-- auto-fit note range: min/max pitch of events padded by 3, min span 12 rows
local function auto_note_range(notes)
  local lo, hi = 60, 72
  if notes and #notes > 0 then
    lo, hi = 127, 0
    for _, n in ipairs(notes) do
      if n.note < lo then lo = n.note end
      if n.note > hi then hi = n.note end
    end
    lo = math.max(0, lo - 3)
    hi = math.min(127, hi + 3)
  end
  if hi - lo < 12 then
    local mid = math.floor((lo + hi) * 0.5)
    lo = math.max(0, mid - 6)
    hi = math.min(127, lo + 12)
  end
  return lo, hi
end

-- 從 view + auto-fit 計算實際顯示的 note_top / note_bot
-- resolve actual note_top/bot from view state (manual or auto)
local function resolve_note_window(view, notes)
  local a_lo, a_hi = auto_note_range(notes)
  local top = (view.note_top >= 0) and view.note_top or a_hi
  local rows = (view.note_rows > 0) and view.note_rows or (a_hi - a_lo + 1)
  rows = math.max(4, math.min(128, rows))
  top = math.max(rows - 1, math.min(127, top))
  local bot = top - rows + 1
  if bot < 0 then bot = 0; top = bot + rows - 1 end
  return top, bot
end

-- 從 view 解析水平視窗 (scroll_qn, span_qn)
-- resolve horizontal window (scroll, span) from view
local function resolve_h_window(view, dur_qn)
  local span = (view.view_qn > 0) and view.view_qn or dur_qn
  span = math.max(0.25, span)
  local scroll = math.max(0, view.scroll_qn or 0)
  -- 不允許 scroll 超出範圍 -- clamp scroll to valid range
  if scroll + span > dur_qn + 0.001 then scroll = math.max(0, dur_qn - span) end
  return scroll, span
end

-- Phase 5: 優先使用 cue 的 midi_ts_num/den 覆寫；否則回落專案拍號
-- use cue's override time-sig if set; else fall back to project time-sig at item pos
local function detect_timesig(c)
  local tn = tonumber(c.midi_ts_num)
  local td = tonumber(c.midi_ts_den)
  if tn and tn > 0 and td and td > 0 then return tn, td end
  local it = select(1, FUNC.midi_get_item_take(c))
  if not it then return 4, 4 end
  local ip = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local _, nnum, nden = reaper.TimeMap_GetTimeSigAtTime(0, ip)
  if nnum and nnum > 0 and nden and nden > 0 then return nnum, nden end
  return 4, 4
end

-- 收集 item 內出現過的 CC lane（for CC dropdown）
-- collect CC lanes present in events (for CC dropdown)
local function collect_cc_lanes(ccs)
  local seen, list = {}, {}
  for _, cc in ipairs(ccs or {}) do
    local key
    local cm = cc.chanmsg or 0xB0
    if cm == 0xB0 then key = cc.msg2 or 0       -- CC number
    elseif cm == 0xC0 then key = 200             -- Program Change
    elseif cm == 0xD0 then key = 201             -- Channel Pressure
    elseif cm == 0xE0 then key = 202             -- Pitch Bend
    else key = 300 + cm end
    if not seen[key] then seen[key] = true; list[#list+1] = key end
  end
  table.sort(list)
  return list
end

local function cc_lane_label(key)
  if key == -1 then return "All" end
  if key == 200 then return "Program" end
  if key == 201 then return "Ch Pressure" end
  if key == 202 then return "Pitch Bend" end
  if key >= 300 then return string.format("msg 0x%X", key - 300) end
  return string.format("CC %d", key)
end

-- event 是否被 channel/lane filter 接受 -- does event pass active filters
local function pass_ch_filter(view, ev_ch)
  if (view.channel_filter or 0) == 0 then return true end
  return (ev_ch + 1) == view.channel_filter
end

local function pass_cc_filter(view, cc)
  local f = view.cc_lane_filter
  if f == -1 then return true end
  local cm = cc.chanmsg or 0xB0
  if cm == 0xB0 then return (cc.msg2 or 0) == f end
  if cm == 0xC0 then return f == 200 end
  if cm == 0xD0 then return f == 201 end
  if cm == 0xE0 then return f == 202 end
  return false
end

---------------------------------------------------------------------
-- 3. Eye icon (DrawList — matches ep_eye style in ui_edit.lua)
---------------------------------------------------------------------
-- 共用樣式：橢圓外框 + 瞳孔，點擊開啟 show/hide popup
-- Shared style with edit panel tab-vis eye button
local function draw_eye_icon(dl, x, y, w, h, hov)
  local cx = x + w * 0.5
  local cy = y + h * 0.5
  local rx, ry = FUNC.sz(6), FUNC.sz(3.5)
  local col = hov and C.text or FUNC.dim_c(C.text)
  local n = 12
  for i = 0, n - 1 do
    local a1 = math.pi * i / n
    local a2 = math.pi * (i + 1) / n
    ImGui.DrawList_AddLine(dl, cx + math.cos(a1)*rx, cy - math.sin(a1)*ry,
      cx + math.cos(a2)*rx, cy - math.sin(a2)*ry, col, FUNC.sz(1))
    ImGui.DrawList_AddLine(dl, cx + math.cos(a1)*rx, cy + math.sin(a1)*ry,
      cx + math.cos(a2)*rx, cy + math.sin(a2)*ry, col, FUNC.sz(1))
  end
  ImGui.DrawList_AddCircleFilled(dl, cx, cy, FUNC.sz(2), col)
end

---------------------------------------------------------------------
-- 4. Toolbar — ImGui widgets (eye / channel / CC / H-zoom / V-zoom / reset)
--    advances cursor; returns toolbar_height consumed
---------------------------------------------------------------------
function FUNC.draw_midi_editor_toolbar(c, total_w)
  FUNC.midi_editor_ensure_view(c)
  local view = c.midi_view
  local evt = FUNC.midi_read_events(c)

  local tb_h = FUNC.sz(22)
  local gap  = FUNC.sz(4)
  local tb_x, tb_y = ImGui.GetCursorScreenPos(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)

  ---------------------------------------------------
  -- Eye icon (show/hide popup)
  ---------------------------------------------------
  local eye_w = FUNC.sz(22)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button(), 0)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), FUNC.rgba(255,255,255,25))
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), FUNC.rgba(255,255,255,40))
  local eye_sx, eye_sy = ImGui.GetCursorScreenPos(ctx)
  if ImGui.Button(ctx, "##me_eye"..c.id, eye_w, tb_h) then
    ImGui.OpenPopup(ctx, "##me_eye_pop"..c.id)
  end
  local eye_hov = ImGui.IsItemHovered(ctx)
  ImGui.PopStyleColor(ctx, 3)
  draw_eye_icon(dl, eye_sx, eye_sy, eye_w, tb_h, eye_hov)
  if eye_hov then ImGui.SetTooltip(ctx, "Show/Hide elements") end
  if ImGui.BeginPopup(ctx, "##me_eye_pop"..c.id) then
    FUNC.draw_midi_editor_settings(c)
    ImGui.EndPopup(ctx)
  end

  ---------------------------------------------------
  -- Channel dropdown (All / 1..16)
  ---------------------------------------------------
  ImGui.SameLine(ctx, 0, gap)
  ImGui.SetNextItemWidth(ctx, FUNC.sz(70))
  local ch_lbl = (view.channel_filter == 0) and "All Ch" or string.format("Ch %d", view.channel_filter)
  if ImGui.BeginCombo(ctx, "##me_ch"..c.id, ch_lbl) then
    if ImGui.Selectable(ctx, "All Ch", view.channel_filter == 0) then view.channel_filter = 0 end
    for i = 1, 16 do
      if ImGui.Selectable(ctx, string.format("Ch %d", i), view.channel_filter == i) then view.channel_filter = i end
    end
    ImGui.EndCombo(ctx)
  end

  ---------------------------------------------------
  -- CC lane dropdown (All + lanes present in item)
  ---------------------------------------------------
  ImGui.SameLine(ctx, 0, gap)
  ImGui.SetNextItemWidth(ctx, FUNC.sz(110))
  local lanes = collect_cc_lanes(evt.ccs)
  local lane_lbl = cc_lane_label(view.cc_lane_filter)
  if ImGui.BeginCombo(ctx, "##me_cc"..c.id, lane_lbl) then
    if ImGui.Selectable(ctx, "All Lanes", view.cc_lane_filter == -1) then view.cc_lane_filter = -1 end
    for _, k in ipairs(lanes) do
      if ImGui.Selectable(ctx, cc_lane_label(k), view.cc_lane_filter == k) then view.cc_lane_filter = k end
    end
    if #lanes == 0 then
      ImGui.TextDisabled(ctx, "(no CC in item)")
    end
    ImGui.EndCombo(ctx)
  end

  ---------------------------------------------------
  -- Zoom buttons — H (horizontal) then V (vertical)
  ---------------------------------------------------
  local btn_sz = FUNC.sz(18)
  local btn_gap = FUNC.sz(2)
  local zw = btn_sz * 3 + btn_gap * 2
  local total_zoom_w = zw * 2 + gap + FUNC.sz(28)  -- two 3-btn groups + H/V labels

  -- small zoom button — DrawList-based, matches waveform.lua style
  local function zbtn(axis, label, tip)
    local bx, by = ImGui.GetCursorScreenPos(ctx)
    ImGui.InvisibleButton(ctx, "##mez_"..axis.."_"..label..c.id, btn_sz, btn_sz)
    local hov = ImGui.IsItemHovered(ctx)
    local clk = ImGui.IsItemClicked(ctx)
    local bg_n = C.btn
    local bg_h = FUNC.rgba(75, 75, 105)
    ImGui.DrawList_AddRectFilled(dl, bx, by, bx + btn_sz, by + btn_sz, FUNC.dim_c(hov and bg_h or bg_n), 3)
    local tw, th = ImGui.CalcTextSize(ctx, label, 0, 0)
    ImGui.DrawList_AddText(dl, bx + (btn_sz - tw)/2, by + (btn_sz - th)/2, FUNC.dim_c(C.text), label)
    if hov and tip then ImGui.SetTooltip(ctx, tip) end
    return clk
  end

  ImGui.SameLine(ctx, 0, gap)
  ImGui.AlignTextToFramePadding(ctx); ImGui.TextDisabled(ctx, "V")
  ImGui.SameLine(ctx, 0, btn_gap)
  if zbtn("v", "-", "Vertical zoom out") then FUNC.midi_editor_zoom_v(c, 1/1.25) end
  ImGui.SameLine(ctx, 0, btn_gap)
  if zbtn("v", "R", "Reset vertical") then view.note_top = -1; view.note_rows = -1 end
  ImGui.SameLine(ctx, 0, btn_gap)
  if zbtn("v", "+", "Vertical zoom in") then FUNC.midi_editor_zoom_v(c, 1.25) end

  ImGui.SameLine(ctx, 0, gap)
  ImGui.AlignTextToFramePadding(ctx); ImGui.TextDisabled(ctx, "H")
  ImGui.SameLine(ctx, 0, btn_gap)
  if zbtn("h", "-", "Horizontal zoom out") then FUNC.midi_editor_zoom_h(c, 1/1.5) end
  ImGui.SameLine(ctx, 0, btn_gap)
  if zbtn("h", "R", "Reset horizontal") then view.scroll_qn = 0; view.view_qn = -1 end
  ImGui.SameLine(ctx, 0, btn_gap)
  if zbtn("h", "+", "Horizontal zoom in") then FUNC.midi_editor_zoom_h(c, 1.5) end

  -- 起始小節輸入框 -- start bar input (Phase A: #2 allows customization)
  ImGui.SameLine(ctx, 0, gap * 2)
  ImGui.AlignTextToFramePadding(ctx); ImGui.TextDisabled(ctx, "Bar1=")
  ImGui.SameLine(ctx, 0, btn_gap)
  ImGui.SetNextItemWidth(ctx, FUNC.sz(44))
  local sb_ch, sb_nv = ImGui.InputInt(ctx, "##me_sb"..c.id, view.start_bar or 1, 0, 0)
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Starting bar number for the ruler display") end
  if sb_ch then view.start_bar = math.max(1, sb_nv) end

  return tb_h
end

---------------------------------------------------------------------
-- 5. Main chart draw — DrawList only (caller provides rect)
---------------------------------------------------------------------
function FUNC.draw_midi_editor(c, dl, x, y, w, h)
  FUNC.midi_editor_ensure_view(c)
  local view = c.midi_view

  -- 背景 -- bg frame
  local bg = C.wf_bg or FUNC.rgba(30, 30, 38)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, 4)
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, FUNC.dim_c(C.line2), 4, 0, 1)

  -- 幾何 -- geometry
  local pad = FUNC.sz(4)
  local piano_w = view.show_piano_lbl and FUNC.sz(60) or FUNC.sz(18)
  local ruler_top_h = FUNC.sz(18)
  local ruler_bot_h = FUNC.sz(16)
  local cx = x + piano_w
  local cy = y + ruler_top_h
  local cw = (x + w - pad) - cx
  local ch_area = (y + h - pad - ruler_bot_h) - cy
  if cw < 20 or ch_area < 20 then return nil end

  -- 讀事件 -- read events
  local evt = FUNC.midi_read_events(c)
  local dur_qn = (evt and evt.dur_qn) or 0
  if dur_qn <= 0 then
    local txt = "(empty item)"
    local tw, th = ImGui.CalcTextSize(ctx, txt, 0, 0)
    ImGui.DrawList_AddText(dl, x + (w - tw) * 0.5, y + (h - th) * 0.5, FUNC.rgba(110, 110, 125), txt)
    return nil
  end

  -- 視窗解析 -- resolve view window (horizontal + vertical)
  local note_hi, note_lo = resolve_note_window(view, evt.notes)
  local note_cnt = note_hi - note_lo + 1
  local note_h = ch_area / note_cnt
  local h_scroll, h_span = resolve_h_window(view, dur_qn)

  -- 拍號 + BPM + 時間 -- time sig, BPM, total sec
  local ts_num, ts_den = detect_timesig(c)
  local qn_per_bar = ts_num * 4 / ts_den
  local bpm = math.max(1, c.midi_bpm or 120)
  local total_sec = dur_qn * 60 / bpm

  -- 座標對應 -- coordinate mapping (QN ↔ x, note ↔ row y)
  local function qn_to_x(q) return cx + ((q - h_scroll) / h_span) * cw end
  local function x_to_qn(px) return h_scroll + (px - cx) / cw * h_span end
  local function note_to_y(n) return cy + (note_hi - n) * note_h end
  local function y_to_note(py) return note_hi - math.floor((py - cy) / note_h) end

  ---------------------------------------------------------------------
  -- Piano roll 左欄 + chart 列底色 -- piano roll + row shading
  ---------------------------------------------------------------------
  local note_names = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}
  local black_key = {[1]=true,[3]=true,[6]=true,[8]=true,[10]=true}
  local piano_x1 = x + pad
  local piano_x2 = cx - 1

  ImGui.DrawList_PushClipRect(dl, x, cy, x + w, cy + ch_area, true)
  for ni = note_lo, note_hi do
    local row = note_hi - ni
    local ky = cy + row * note_h
    local ky2 = ky + note_h
    local nn = ni % 12
    local oct = math.floor(ni / 12) - 1
    local is_black = black_key[nn]
    -- 白鍵列加淺色疊層；黑鍵維持暗底（對應真實鋼琴）
    -- white-key rows get a subtle lighten; black-key rows stay dark (matches real piano)
    if not is_black then
      ImGui.DrawList_AddRectFilled(dl, cx, ky, cx + cw, ky2, FUNC.rgba(255, 255, 255, 14))
    end
    if nn == 0 then
      ImGui.DrawList_AddLine(dl, cx, ky2, cx + cw, ky2, FUNC.rgba(255, 255, 255, 35), 1)
    end
    if view.show_piano_lbl then
      local key_col = is_black and FUNC.rgba(38, 38, 46) or FUNC.rgba(215, 215, 220)
      local txt_col = is_black and FUNC.rgba(210, 210, 210) or FUNC.rgba(30, 30, 35)
      ImGui.DrawList_AddRectFilled(dl, piano_x1, ky, piano_x2, ky2 - 1, key_col, 2)
      -- 字級跟琴鍵高度走，最大 11，不會溢出琴鍵 -- label size follows key height (max 11) so it never spills
      local lbl_fsz = math.min(FUNC.sz(11), note_h - 2)
      if view.show_note_name and lbl_fsz >= FUNC.sz(7) then
        local lbl = note_names[nn + 1] .. tostring(oct)
        ImGui.DrawList_AddTextEx(dl, FONT, lbl_fsz, piano_x1 + FUNC.sz(4), ky + (note_h - lbl_fsz) * 0.5, txt_col, lbl)
      end
    end
  end
  ImGui.DrawList_PopClipRect(dl)

  ---------------------------------------------------------------------
  -- 垂直 grid：依像素密度動態決定 bar / beat / 細分級
  -- dynamic-density grid: pick bar multiplier + optional beat / sub-beat levels
  ---------------------------------------------------------------------
  local beat_col = FUNC.rgba(255, 255, 255, 18)
  local bar_col  = FUNC.rgba(255, 255, 255, 65)
  local sub_col  = FUNC.rgba(255, 255, 255, 10)
  local beat_qn = 4 / ts_den
  local px_per_qn = cw / math.max(0.001, h_span)
  -- 主線（bar）：保證兩條主線間距 >= ~40px，太密就跳小節 (x2, x4, x8...)
  -- major (bar) step: ensure >= ~40px between lines, stepping up powers of 2
  local bar_mult = 1
  while qn_per_bar * bar_mult * px_per_qn < FUNC.sz(40) do bar_mult = bar_mult * 2 end
  local major_qn = qn_per_bar * bar_mult
  -- beat lines 只在 beat 間距 >= ~18px 才顯示 -- beat lines only when >= ~18px apart
  local show_beats = (beat_qn * px_per_qn >= FUNC.sz(18)) and (bar_mult == 1)
  -- 細分線（1/2 beat）只在 beat 間距 >= ~60px 才顯示 -- sub-beat only when beat >= ~60px
  local show_sub = show_beats and (beat_qn * px_per_qn >= FUNC.sz(60))
  ImGui.DrawList_PushClipRect(dl, cx, cy, cx + cw, cy + ch_area, true)
  if show_sub then
    local step = beat_qn * 0.5
    local q = math.max(0, math.floor(h_scroll / step) * step)
    local q_end = math.min(dur_qn, h_scroll + h_span)
    while q <= q_end + 0.001 do
      local gx = qn_to_x(q)
      ImGui.DrawList_AddLine(dl, gx, cy, gx, cy + ch_area, sub_col, 1)
      q = q + step
    end
  end
  if show_beats then
    local q = math.max(0, math.floor(h_scroll / beat_qn) * beat_qn)
    local q_end = math.min(dur_qn, h_scroll + h_span)
    while q <= q_end + 0.001 do
      local is_bar = math.abs(q % qn_per_bar) < 0.001 or math.abs((q % qn_per_bar) - qn_per_bar) < 0.001
      if not is_bar then
        local gx = qn_to_x(q)
        ImGui.DrawList_AddLine(dl, gx, cy, gx, cy + ch_area, beat_col, 1)
      end
      q = q + beat_qn
    end
  end
  -- 主線（bar 或 multi-bar）-- major (bar / multi-bar) lines
  do
    local q = math.max(0, math.floor(h_scroll / major_qn) * major_qn)
    local q_end = math.min(dur_qn, h_scroll + h_span)
    while q <= q_end + 0.001 do
      local gx = qn_to_x(q)
      ImGui.DrawList_AddLine(dl, gx, cy, gx, cy + ch_area, bar_col, 1)
      q = q + major_qn
    end
  end
  ImGui.DrawList_PopClipRect(dl)

  ---------------------------------------------------------------------
  -- Events: notes + CCs
  ---------------------------------------------------------------------
  local ch_cols = get_ch_cols()
  ImGui.DrawList_PushClipRect(dl, cx, cy, cx + cw, cy + ch_area, true)

  if view.show_notes then
    -- 拖曳預覽：resize 中對選取音符顯示新尺寸（實心填色）
    -- resize drag preview: filled at new geometry for selected notes
    local resizing = c._midi_drag and c._midi_drag.kind == "resize"
    local r_dq = (c._midi_drag and c._midi_drag.dq) or 0
    local r_anchor = (c._midi_drag and c._midi_drag.anchor) or "start"
    for ni, n in ipairs(evt.notes) do
      if pass_ch_filter(view, n.ch) and n.note >= note_lo and n.note <= note_hi then
        -- 只畫可見水平範圍 -- skip fully off-screen notes
        local n_end = n.t_qn + n.len_qn
        if n_end >= h_scroll and n.t_qn <= h_scroll + h_span then
          -- 夾限到 item trim 範圍 [0, dur_qn]：trim 外的音符部分不繪製
          -- clamp drawn span to item trim range; portions outside aren't rendered
          local draw_t0 = math.max(0, n.t_qn)
          local draw_t1 = math.min(dur_qn, n_end)
          if draw_t1 > draw_t0 then
            local row = note_hi - n.note
            local ny = cy + row * note_h
            local nx1 = qn_to_x(draw_t0)
            local nx2 = qn_to_x(draw_t1)
            nx2 = math.max(nx1 + FUNC.sz(2), nx2)
            local is_sel = c._midi_sel and c._midi_sel["n"..ni]
            -- Cmd+drag 即時預覽 vel：snap + delta -- live vel preview during cmd-drag
            local disp_vel = n.vel or 100
            do
              local dg = c._midi_drag
              if dg and (dg.kind == "vel" or dg.kind == "pending_vel")
                 and is_sel and dg.snap and dg.snap["n"..ni] then
                disp_vel = math.max(1, math.min(127, dg.snap["n"..ni] + (dg.vel_delta or 0)))
              end
            end
            local base_col
            if view.show_channel then
              base_col = ch_cols[(n.ch % 16) + 1]
            else
              local vr, vg, vb = vel_rgb(disp_vel)
              base_col = FUNC.rgba(vr, vg, vb)
            end
            local preview = resizing and is_sel and r_dq ~= 0
            if preview then
              -- 實心預覽：依 anchor 計算新 t/end -- filled preview at new t/end
              local new_t, new_end
              if r_anchor == "end" then
                new_t = math.max(0, math.min(n.t_qn + n.len_qn - 0.01, n.t_qn + r_dq))
                new_end = n.t_qn + n.len_qn
              else
                new_t = n.t_qn
                new_end = math.max(n.t_qn + 0.01, n.t_qn + n.len_qn + r_dq)
              end
              local px1 = qn_to_x(math.max(0, new_t))
              local px2 = qn_to_x(math.min(dur_qn, new_end))
              px2 = math.max(px1 + FUNC.sz(2), px2)
              ImGui.DrawList_AddRectFilled(dl, px1, ny + 1, px2, ny + note_h - 1, base_col, 2)
              ImGui.DrawList_AddRect(dl, px1, ny + 1, px2, ny + note_h - 1, FUNC.rgba(0, 0, 0, 150), 2, 0, 1)
            else
              ImGui.DrawList_AddRectFilled(dl, nx1, ny + 1, nx2, ny + note_h - 1, base_col, 2)
              if is_sel then
                -- selected 半透明白色遮罩 -- selected: translucent white overlay
                ImGui.DrawList_AddRectFilled(dl, nx1, ny + 1, nx2, ny + note_h - 1, FUNC.rgba(255, 255, 255, 145), 2)
              end
              ImGui.DrawList_AddRect(dl, nx1, ny + 1, nx2, ny + note_h - 1, FUNC.rgba(0, 0, 0, 150), 2, 0, 1)
              if view.show_velocity then
                local vel = math.max(1, math.min(127, disp_vel))
                local ch_str = string.format("ch %d", (n.ch or 0) + 1)
                local full_txt = ch_str .. " | " .. tostring(vel)
                local readable = FUNC.sz(11)
                local max_fsz = math.min(note_h - 2, FUNC.sz(24))
                local min_fsz = readable
                -- note 太薄連最小可讀都放不下 → 整段不畫，避免文字穿出 note 邊界
                -- skip entirely when note is too thin to fit a readable size (prevents glyphs poking out)
                local skip_text = max_fsz < min_fsz
                local avail = (nx2 - nx1) - 2
                -- 1) try full text, shrink to min -- 先縮小
                local txt = full_txt
                local fsz = max_fsz
                while fsz > min_fsz and #txt * fsz * 0.55 > avail do fsz = fsz - 1 end
                -- 2) drop vel -- 省略 vel
                if #txt * fsz * 0.55 > avail then
                  txt = ch_str
                  fsz = max_fsz
                  while fsz > min_fsz and #txt * fsz * 0.55 > avail do fsz = fsz - 1 end
                end
                -- 3) drop ch (skip drawing) -- 連 ch 都放不下就不畫
                local approx_w = #txt * fsz * 0.55
                if not skip_text and approx_w <= avail then
                  local txt_col = is_sel and FUNC.rgba(0, 0, 0, 230) or FUNC.rgba(255, 255, 255, 230)
                  local ty = ny + 1 + math.max(0, math.floor((note_h - 2 - fsz) * 0.5))
                  if txt == full_txt then
                    -- "|" 比英數字長，單獨縮小 2 級避免穿出 note 高度 -- pipe is taller than digits/letters; render 2pt smaller
                    local pipe_fsz = math.max(1, fsz - 2)
                    local left, right = ch_str, tostring(vel)
                    local cw = fsz * 0.55  -- mono char width
                    local pipe_w = pipe_fsz * 0.55
                    local space_w = cw  -- 兩側空格仍用 fsz
                    local left_w = #left * cw
                    local right_w = #right * cw
                    local total_w = left_w + space_w + pipe_w + space_w + right_w
                    local tx = nx2 - total_w - 1
                    local ty_pipe = ny + 1 + math.max(0, math.floor((note_h - 2 - pipe_fsz) * 0.5))
                    ImGui.DrawList_AddTextEx(dl, FONT_MONO, fsz, tx, ty, txt_col, left)
                    ImGui.DrawList_AddTextEx(dl, FONT_MONO, pipe_fsz, tx + left_w + space_w, ty_pipe, txt_col, "|")
                    ImGui.DrawList_AddTextEx(dl, FONT_MONO, fsz, tx + left_w + space_w + pipe_w + space_w, ty, txt_col, right)
                  else
                    -- 水平置右、垂直置中 -- right-aligned, vertically centered
                    local tx = nx2 - approx_w - 1
                    ImGui.DrawList_AddTextEx(dl, FONT_MONO, fsz, tx, ty, txt_col, txt)
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  -- opt+drag 新增 note 的 ghost 預覽（note 在 release 才實際建立）
  -- pending_paint（按下未拖）不畫，避免被誤認為已建立的 note；只有 paint（已拖）才顯示
  -- ghost only after drag begins (paint), not during pending_paint hold — avoids "note appeared on mousedown" confusion
  do
    local dg = c._midi_drag
    if dg and dg.kind == "paint"
       and dg.paint_pitch and dg.paint_pitch >= note_lo and dg.paint_pitch <= note_hi
       and pass_ch_filter(view, dg.paint_ch or 0) then
      local g_t0 = dg.paint_q or 0
      local g_t1 = math.max(g_t0 + 0.01, dg.paint_cur_qn or g_t0)
      if g_t1 >= h_scroll and g_t0 <= h_scroll + h_span then
        local row = note_hi - dg.paint_pitch
        local gy = cy + row * note_h
        local gx1 = qn_to_x(math.max(0, g_t0))
        local gx2 = qn_to_x(math.min(dur_qn, g_t1))
        gx2 = math.max(gx1 + FUNC.sz(2), gx2)
        local g_col = FUNC.rgba(255, 220, 90)  -- 預設選取色 -- pre-selected color (will be selected on release)
        ImGui.DrawList_AddRectFilled(dl, gx1, gy + 1, gx2, gy + note_h - 1, g_col, 2)
        ImGui.DrawList_AddRect(dl, gx1, gy + 1, gx2, gy + note_h - 1, FUNC.rgba(0, 0, 0, 150), 2, 0, 1)
      end
    end
  end

  if view.show_ccs then
    for ci, cc in ipairs(evt.ccs) do
      if pass_ch_filter(view, cc.ch) and pass_cc_filter(view, cc)
         and cc.t_qn >= h_scroll - 0.01 and cc.t_qn <= h_scroll + h_span + 0.01 then
        local gx = qn_to_x(cc.t_qn)
        local base_col = view.show_channel and ch_cols[(cc.ch % 16) + 1] or FUNC.rgba(220, 160, 80)
        local is_sel = c._midi_sel and c._midi_sel["c"..ci]
        if is_sel then base_col = FUNC.rgba(255, 220, 90) end
        ImGui.DrawList_AddLine(dl, gx, cy, gx, cy + ch_area, base_col, 1)
        ImGui.DrawList_AddCircleFilled(dl, gx, cy + FUNC.sz(3), FUNC.sz(2), base_col, 6)
        if view.show_velocity then
          local lbl
          local cm = cc.chanmsg or 0xB0
          if cm == 0xB0 then lbl = string.format("%d:%d", cc.msg2 or 0, cc.msg3 or 0)
          elseif cm == 0xC0 then lbl = string.format("PC%d", cc.msg2 or 0)
          elseif cm == 0xD0 then lbl = string.format("CP%d", cc.msg2 or 0)
          elseif cm == 0xE0 then lbl = "PB"
          end
          if lbl then
            ImGui.DrawList_AddText(dl, gx + FUNC.sz(2), cy + FUNC.sz(2), base_col, lbl)
          end
        end
      end
    end
  end

  ImGui.DrawList_PopClipRect(dl)
  ImGui.DrawList_AddRect(dl, cx, cy, cx + cw, cy + ch_area, FUNC.rgba(80, 80, 100), 0, 0, 1)

  ---------------------------------------------------------------------
  -- Top ruler — bars/beats (bar number offset by start_bar)
  ---------------------------------------------------------------------
  local ruler_bg = FUNC.rgba(22, 22, 30)
  local ruler_tx = FUNC.rgba(185, 185, 205)
  ImGui.DrawList_AddRectFilled(dl, cx, y + pad, cx + cw, cy - 1, ruler_bg)
  ImGui.DrawList_PushClipRect(dl, cx, y, cx + cw, cy, true)
  local bar_offset = (view.start_bar or 1) - 1  -- 起始小節偏移 -- starting bar offset
  -- 只顯示小節數（拍數僅在 beat 夠寬時才標示）
  -- show only bar numbers; beat numbers appear only when beats are wide enough
  local show_beat_num = show_beats and (beat_qn * px_per_qn >= FUNC.sz(34))
  -- 主線 bar label（按 bar_mult 跳過，太密時 2/4/8 小節才一個字）
  do
    local q = math.max(0, math.floor(h_scroll / major_qn) * major_qn)
    local q_end = math.min(dur_qn, h_scroll + h_span)
    while q <= q_end + 0.001 do
      local gx = qn_to_x(q)
      local bar_n = math.floor(q / qn_per_bar + 0.0001) + 1 + bar_offset
      ImGui.DrawList_AddLine(dl, gx, cy - FUNC.sz(7), gx, cy - 1, ruler_tx, 1)
      ImGui.DrawList_AddText(dl, gx + FUNC.sz(2), y + pad + FUNC.sz(1), ruler_tx, string.format("%d", bar_n))
      q = q + major_qn
    end
  end
  -- beat ticks (選擇性：zoom 夠大才畫 + 加小數字) -- beat ticks, only at sufficient zoom
  if show_beats then
    local q = math.max(0, math.floor(h_scroll / beat_qn) * beat_qn)
    local q_end = math.min(dur_qn, h_scroll + h_span)
    while q <= q_end + 0.001 do
      local is_bar = math.abs(q % qn_per_bar) < 0.001 or math.abs((q % qn_per_bar) - qn_per_bar) < 0.001
      if not is_bar then
        local gx = qn_to_x(q)
        ImGui.DrawList_AddLine(dl, gx, cy - FUNC.sz(4), gx, cy - 1, FUNC.rgba(120, 120, 140), 1)
        if show_beat_num then
          local beat_idx = math.floor((q % qn_per_bar) / beat_qn + 0.0001) + 1
          ImGui.DrawList_AddText(dl, gx + FUNC.sz(2), y + pad + FUNC.sz(1), FUNC.rgba(140, 140, 160), string.format("%d", beat_idx))
        end
      end
      q = q + beat_qn
    end
  end
  ImGui.DrawList_AddText(dl, x + pad + FUNC.sz(2), y + pad + FUNC.sz(1), FUNC.rgba(140, 150, 170), string.format("%d/%d", ts_num, ts_den))
  ImGui.DrawList_PopClipRect(dl)

  ---------------------------------------------------------------------
  -- Bottom ruler — timecode (sec), reflects current view span
  ---------------------------------------------------------------------
  local rb_y = cy + ch_area + 1
  ImGui.DrawList_AddRectFilled(dl, cx, rb_y, cx + cw, y + h - pad, ruler_bg)
  ImGui.DrawList_PushClipRect(dl, cx, rb_y, cx + cw, y + h, true)
  local view_sec = h_span * 60 / bpm
  local scroll_sec = h_scroll * 60 / bpm
  local sec_step = 0.25
  local steps = {0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 30, 60}
  for _, s in ipairs(steps) do
    if view_sec / s <= 10 then sec_step = s; break end
  end
  local ts_start = math.floor(scroll_sec / sec_step) * sec_step
  local ts_end = scroll_sec + view_sec
  local ts = ts_start
  while ts <= ts_end + 0.0001 do
    local gx = cx + ((ts - scroll_sec) / view_sec) * cw
    ImGui.DrawList_AddLine(dl, gx, rb_y, gx, rb_y + FUNC.sz(4), ruler_tx, 1)
    local lbl = (sec_step < 1) and string.format("%.2fs", ts) or string.format("%.1fs", ts)
    ImGui.DrawList_AddText(dl, gx + FUNC.sz(2), rb_y + FUNC.sz(2), ruler_tx, lbl)
    ts = ts + sec_step
  end
  ImGui.DrawList_AddText(dl, x + pad + FUNC.sz(2), rb_y + FUNC.sz(2), FUNC.rgba(140, 150, 170), string.format("%.0f BPM", bpm))
  ImGui.DrawList_PopClipRect(dl)

  ---------------------------------------------------------------------
  -- Realive-internal trim overlay + handles（重用 c.trim_start / trim_end）
  -- trim overlay + handles (sec-based, reuses trim_start/trim_end fields)
  ---------------------------------------------------------------------
  local full_sec = dur_qn * 60 / bpm
  local ts_sec = math.max(0, c.trim_start or 0)
  local te_sec = (c.trim_end and c.trim_end > 0) and math.min(full_sec, c.trim_end) or full_sec
  local ts_qn_t = ts_sec * bpm / 60
  local te_qn_t = te_sec * bpm / 60
  local trim_hx_in, trim_hx_out = nil, nil
  if ts_sec > 0 or te_sec < full_sec then
    ImGui.DrawList_PushClipRect(dl, cx, cy, cx + cw, cy + ch_area, true)
    local dim = FUNC.rgba(0, 0, 0, 130)
    if ts_qn_t > h_scroll then
      local xR = math.min(cx + cw, qn_to_x(ts_qn_t))
      if xR > cx then ImGui.DrawList_AddRectFilled(dl, cx, cy, xR, cy + ch_area, dim) end
    end
    if te_qn_t < h_scroll + h_span then
      local xL = math.max(cx, qn_to_x(te_qn_t))
      if xL < cx + cw then ImGui.DrawList_AddRectFilled(dl, xL, cy, cx + cw, cy + ch_area, dim) end
    end
    ImGui.DrawList_PopClipRect(dl)
  end
  -- handle tabs 樣式統一 audio waveform（start tab 上方突出、end tab 下方突出 + guide line + hover 色）
  -- trim handle styling mirrors audio waveform: start tab above chart, end tab below, guide line across, hover highlight
  do
    local tab_w = FUNC.sz(12)
    local tab_h = FUNC.sz(16)  -- 與 audio q 一致 -- match audio q waveform tab size
    local mx_t, my_t = ImGui.GetMousePos(ctx)
    local drag_side = (c._midi_trim_drag and c._midi_trim_drag.side) or nil
    local col_base  = FUNC.dim_c(C.trim or FUNC.rgba(255,180,60))
    local col_hover = FUNC.dim_c(FUNC.rgba(255,200,100))
    local guide_col = FUNC.rgba(255,180,60,140)
    local hit_px = FUNC.sz(5)
    local near_chart_y = my_t >= cy and my_t <= cy + ch_area
    if ts_qn_t >= h_scroll - 0.01 and ts_qn_t <= h_scroll + h_span + 0.01 then
      local hx = qn_to_x(ts_qn_t); trim_hx_in = hx
      local x1, x2 = hx - tab_w/2, hx + tab_w/2
      local y1, y2 = cy - tab_h, cy  -- tab 位於 chart 上方 -- tab above chart
      local near_line = near_chart_y and math.abs(mx_t - hx) <= hit_px
      local on_tab = ImGui.IsMouseHoveringRect(ctx, x1 - 2, y1, x2 + 2, y2 + 2)
      local hov = (drag_side == "in") or near_line or on_tab
      ImGui.DrawList_AddLine(dl, hx, cy, hx, cy + ch_area, guide_col, 1)
      ImGui.DrawList_AddRectFilled(dl, x1, y1, x2, y2, hov and col_hover or col_base, 2)
    end
    if te_qn_t >= h_scroll - 0.01 and te_qn_t <= h_scroll + h_span + 0.01 then
      local hx = qn_to_x(te_qn_t); trim_hx_out = hx
      local x1, x2 = hx - tab_w/2, hx + tab_w/2
      local y1, y2 = cy + ch_area, cy + ch_area + tab_h  -- tab 位於 chart 下方 -- tab below chart
      local near_line = near_chart_y and math.abs(mx_t - hx) <= hit_px
      local on_tab = ImGui.IsMouseHoveringRect(ctx, x1 - 2, y1 - 2, x2 + 2, y2)
      local hov = (drag_side == "out") or near_line or on_tab
      ImGui.DrawList_AddLine(dl, hx, cy, hx, cy + ch_area, guide_col, 1)
      ImGui.DrawList_AddRectFilled(dl, x1, y1, x2, y2, hov and col_hover or col_base, 2)
    end
  end

  ---------------------------------------------------------------------
  -- Drag preview — 選取的 events 偏移預覽 (move/dup/resize)
  -- selected events at drag-target position (outline only)
  ---------------------------------------------------------------------
  local dg = c._midi_drag
  if dg and not dg.kind:find("^pending_") then
    ImGui.DrawList_PushClipRect(dl, cx, cy, cx + cw, cy + ch_area, true)
    local prev_col = (dg.kind == "dup") and FUNC.rgba(120, 220, 160, 220) or FUNC.rgba(255, 220, 60, 220)
    local dq = dg.dq or 0; local dp = dg.dpitch or 0
    for ni, n in ipairs(evt.notes) do
      if c._midi_sel["n"..ni] and pass_ch_filter(view, n.ch) then
        local new_t
        local new_end
        if dg.kind == "resize" then
          if dg.anchor == "end" then new_t = math.min(n.t_qn + n.len_qn - 0.01, n.t_qn + dq); new_end = n.t_qn + n.len_qn
          else new_t = n.t_qn; new_end = math.max(n.t_qn + 0.01, n.t_qn + n.len_qn + dq) end
        else
          -- move/dup：group 夾限已在 handle_mouse 套用，不做 per-note clamp
          new_t = n.t_qn + dq
          new_end = new_t + n.len_qn
        end
        local new_pitch = math.max(0, math.min(127, n.note + ((dg.kind=="resize") and 0 or dp)))
        if new_pitch >= note_lo and new_pitch <= note_hi then
          local row = note_hi - new_pitch
          local py = cy + row * note_h
          local px1 = qn_to_x(new_t)
          local px2 = math.max(px1 + FUNC.sz(2), qn_to_x(new_end))
          ImGui.DrawList_AddRect(dl, px1, py + 1, px2, py + note_h - 1, prev_col, 2, 0, FUNC.sz(1.5))
        end
      end
    end
    for ci, cc in ipairs(evt.ccs) do
      if c._midi_sel["c"..ci] and pass_ch_filter(view, cc.ch) and pass_cc_filter(view, cc) then
        local new_t = (dg.kind == "resize") and cc.t_qn or (cc.t_qn + dq)
        local gx = qn_to_x(new_t)
        ImGui.DrawList_AddLine(dl, gx, cy, gx, cy + ch_area, prev_col, 1)
      end
    end
    ImGui.DrawList_PopClipRect(dl)
  end

  ---------------------------------------------------------------------
  -- Play cursor — 綠色播放頭（仿 waveform.lua 邏輯）
  -- playhead line (mirrors waveform.lua preview cursor style)
  ---------------------------------------------------------------------
  if c.state == STATE.RUNNING and c.play_t0 and c.play_t0 > 0 then
    local elapsed = reaper.time_precise() - c.play_t0
    local dur = c.total_dur or 0
    if elapsed >= 0 and (dur <= 0 or elapsed <= dur + 0.1) then
      -- play cursor 鎖定播放當下的 trim_start (play_offset)，不跟隨拖曳 (對齊 audio q 行為)
      -- playhead anchors to play_offset (trim_start at play time), unaffected by drag — same as audio q
      local ts_abs_sec = math.max(0, c.play_offset or c.trim_start or 0)
      local ph_qn = (elapsed + ts_abs_sec) * bpm / 60
      if ph_qn >= h_scroll - 0.01 and ph_qn <= h_scroll + h_span + 0.01 then
        local ph_x = qn_to_x(ph_qn)
        -- 對齊 audio q 的 playhead 樣式 -- match audio q playhead style
        ImGui.DrawList_AddLine(dl, ph_x, cy, ph_x, cy + ch_area, FUNC.rgba(255,255,255,180), 1.5)
        ImGui.DrawList_AddTriangleFilled(dl, ph_x - 4, cy, ph_x + 4, cy, ph_x, cy + 6, FUNC.rgba(255,255,255,200))
      end
    end
  end

  ---------------------------------------------------------------------
  -- Edit cursor — yellow line + blinking (60 frame period)
  ---------------------------------------------------------------------
  if view.cursor_qn and view.cursor_qn >= 0 and view.cursor_qn >= h_scroll - 0.01 and view.cursor_qn <= h_scroll + h_span + 0.01 then
    local cur_x = qn_to_x(view.cursor_qn)
    -- 閃爍：用 reaper.time_precise 算 phase，1Hz blink -- 1Hz blink from precise time
    local phase = (reaper.time_precise() % 1.0)
    local alpha = (phase < 0.6) and 220 or 90
    local col = FUNC.rgba(255, 220, 60, alpha)
    ImGui.DrawList_AddLine(dl, cur_x, cy - FUNC.sz(6), cur_x, cy + ch_area + FUNC.sz(6), col, 2)
    -- 頂端三角標記 -- small triangle top marker
    ImGui.DrawList_AddTriangleFilled(dl, cur_x - FUNC.sz(4), cy - FUNC.sz(8),
                                         cur_x + FUNC.sz(4), cy - FUNC.sz(8),
                                         cur_x,              cy - FUNC.sz(2), col)
  end

  -- 回傳 layout info 給 panel 處理互動 -- return layout for interaction layer
  return {
    cx = cx, cy = cy, cw = cw, ch = ch_area,
    note_lo = note_lo, note_hi = note_hi, note_h = note_h,
    h_scroll = h_scroll, h_span = h_span, dur_qn = dur_qn,
    qn_to_x = qn_to_x, x_to_qn = x_to_qn,
    note_to_y = note_to_y, y_to_note = y_to_note,
    ts_num = ts_num, ts_den = ts_den, bpm = bpm,
    beat_qn = beat_qn, qn_per_bar = qn_per_bar,
    evt = evt,
    -- trim handle info for interaction layer
    trim_hx_in = trim_hx_in, trim_hx_out = trim_hx_out,
    trim_ts_sec = ts_sec, trim_te_sec = te_sec, trim_full_sec = full_sec,
  }
end

---------------------------------------------------------------------
-- 5b. Trim handle drag — realive 內部 trim 邊界拖曳
--     回傳 true 表示正在處理（上游 handle_mouse 應 skip）
-- returns true while dragging (caller should skip event-level mouse handling)
---------------------------------------------------------------------
function FUNC.midi_editor_handle_trim_drag(c, L, hovered)
  if not L then return false end
  local td = c._midi_trim_drag
  local mx, my = ImGui.GetMousePos(ctx)
  local tab_h = FUNC.sz(16)  -- 與繪製端同步 -- keep in sync with draw side
  local tab_w_half = FUNC.sz(8)  -- tab 水平寬 = 12/2 + 2 緩衝 -- tab half-width + slack
  -- 命中範圍擴張到 tab 突出區：x 軸也多給 tab_w_half，避免 trim=0 時 tab 左半被 piano roll 蓋掉
  -- hit range covers tab overhang on all sides so edge handles (trim=0 / trim=full) remain grabbable
  local in_hit = mx >= L.cx - tab_w_half and mx <= L.cx + L.cw + tab_w_half
             and my >= L.cy - tab_h and my <= L.cy + L.ch + tab_h
  local hit_tol = FUNC.sz(8)  -- chart 內線的命中容差（8px，比原本 5px 寬） -- wider line hit tolerance

  -- 正在拖曳：沿用 td.side 更新 -- active drag: update based on side
  if td and td.side then
    if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left()) then
      local new_qn = L.x_to_qn(mx)
      local new_sec = math.max(0, new_qn * 60 / L.bpm)
      new_sec = math.max(0, math.min(L.trim_full_sec, new_sec))
      if td.side == "in" then
        local te = (c.trim_end and c.trim_end > 0) and c.trim_end or L.trim_full_sec
        c.trim_start = math.min(te - 0.001, new_sec)
        -- 對齊 GROUP 行為：trim_start 超過 playhead → 推著 cursor 走 (kill+exec_cue)
        -- mirror GROUP: when trim_start passes playhead, push cursor by re-firing
        if c.state == STATE.RUNNING and c.play_t0 and c.play_t0 > 0 then
          local pofs = c.play_offset or 0
          local ph_t = pofs + (reaper.time_precise() - c.play_t0)
          if c.trim_start >= te then
            FUNC.kill_cue(c)
          elseif c.trim_start > ph_t then
            local ci = FUNC.find_id(c.id)
            if ci then FUNC.kill_cue(c); FUNC.exec_cue(ci) end
          end
        end
      else
        local ts = math.max(0, c.trim_start or 0)
        if new_sec >= L.trim_full_sec - 0.001 then
          c.trim_end = 0  -- 到底 = 0 (與 audio 一致) -- snap to "full length" sentinel
        else
          c.trim_end = math.max(ts + 0.001, new_sec)
        end
        -- end handle 碰到 playhead：有 loop 則開下一輪，否則 kill
        -- end touches playhead: restart if looping, else kill
        if c.state == STATE.RUNNING and c.play_t0 and c.play_t0 > 0 then
          local pofs = c.play_offset or 0
          local ph_t = pofs + (reaper.time_precise() - c.play_t0)
          local te_eff = (c.trim_end and c.trim_end > 0) and c.trim_end or L.trim_full_sec
          -- loop 由 cleanup 處理；這裡只處理非 loop 立即 kill
          -- loop handled by cleanup; here only non-loop immediate kill
          if te_eff <= ph_t and not c.loop then FUNC.kill_cue(c) end
        end
      end
      return true
    else
      c._midi_trim_drag = nil
      return false
    end
  end

  -- 未拖曳：偵測點擊 handle（tab 突出到 chart 外，不要求 hovered，只靠全域滑鼠位置）
  -- idle: detect click on handle; tabs sit outside chart so rely on global mouse pos
  if in_hit and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left()) then
    if L.trim_hx_in and math.abs(mx - L.trim_hx_in) <= hit_tol then
      c._midi_trim_drag = {side="in"}
      return true
    end
    if L.trim_hx_out and math.abs(mx - L.trim_hx_out) <= hit_tol then
      c._midi_trim_drag = {side="out"}
      return true
    end
  end
  return false
end

---------------------------------------------------------------------
-- 6. Panel entry — toolbar + chart + interaction routing
---------------------------------------------------------------------
function FUNC.draw_midi_editor_panel(c, x, y, w, h)
  FUNC.midi_editor_ensure_view(c)

  -- toolbar (top strip, ImGui widgets)
  ImGui.SetCursorScreenPos(ctx, x, y)
  local tb_h = FUNC.draw_midi_editor_toolbar(c, w)
  local ch_y = y + tb_h + FUNC.sz(2)
  local ch_h = h - (tb_h + FUNC.sz(2))
  if ch_h < FUNC.sz(60) then return end

  -- chart interaction surface (invisible button for hover/click capture)
  ImGui.SetCursorScreenPos(ctx, x, ch_y)
  ImGui.InvisibleButton(ctx, "##midi_chart_hit"..c.id, w, ch_h)
  local hovered = ImGui.IsItemHovered(ctx)
  local clicked = ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left())

  -- chart draw (returns layout info)
  local dl = ImGui.GetWindowDrawList(ctx)
  local L = FUNC.draw_midi_editor(c, dl, x, ch_y, w, ch_h)
  if not L then return end

  -- 互動路由 (handle_mouse 負責 click/marquee/drag/cursor placement)
  -- interaction routing (handle_mouse owns click/marquee/drag/cursor placement)
  FUNC.midi_editor_handle_wheel(c, L, hovered)
  -- trim handle 拖曳優先於事件操作 -- trim handle takes priority over event mouse
  local trim_busy = FUNC.midi_editor_handle_trim_drag(c, L, hovered)
  if not trim_busy then FUNC.midi_editor_handle_mouse(c, L, hovered, clicked) end
  FUNC.midi_editor_handle_keys(c, L, hovered)
  FUNC.midi_editor_handle_velocity_drag(c, L, hovered)
  -- right-click menu render（OpenPopup 由 hand-pan handler 在 release-無拖曳時觸發）
  FUNC.midi_editor_right_click_menu(c, L, hovered)
  FUNC.midi_editor_set_value_popup(c)

  -- 繪製 marquee rect (若進行中) -- draw active marquee rect
  local mq = c._midi_marquee
  if mq and mq.active then
    local x1, x2 = math.min(mq.x1, mq.x2), math.max(mq.x1, mq.x2)
    local y1, y2 = math.min(mq.y1, mq.y2), math.max(mq.y1, mq.y2)
    ImGui.DrawList_AddRectFilled(dl, x1, y1, x2, y2, FUNC.rgba(255, 255, 255, 30), 0)
    ImGui.DrawList_AddRect(dl, x1, y1, x2, y2, FUNC.rgba(255, 255, 255, 120), 0, 0, 1)
  end
end

---------------------------------------------------------------------
-- 7. Settings popup (eye icon) — updated with Phase A additions
---------------------------------------------------------------------
function FUNC.draw_midi_editor_settings(c)
  FUNC.midi_editor_ensure_view(c)
  local view = c.midi_view
  local opts = {
    {key="show_notes",     label="Note events"},
    {key="show_ccs",       label="CC events"},
    {key="show_piano_lbl", label="Piano roll"},
    {key="show_note_name", label="Note name"},
    {key="show_velocity",  label="Velocity / value"},
    {key="show_channel",   label="Channel color"},
  }
  for _, o in ipairs(opts) do
    local ch, nv = ImGui.Checkbox(ctx, o.label .. "##mv_" .. o.key .. c.id, view[o.key])
    if ch then view[o.key] = nv end
  end
end

---------------------------------------------------------------------
-- 8. Zoom helpers (Phase A)
---------------------------------------------------------------------
-- H zoom：以視窗中心為錨點縮放 -- horizontal zoom anchored at view center
function FUNC.midi_editor_zoom_h(c, factor)
  FUNC.midi_editor_ensure_view(c)
  local view = c.midi_view
  local evt = FUNC.midi_read_events(c)
  local dur_qn = (evt and evt.dur_qn) or 0
  if dur_qn <= 0 then return end
  local h_scroll, h_span = resolve_h_window(view, dur_qn)
  local center = h_scroll + h_span * 0.5
  local new_span = math.max(0.25, math.min(dur_qn, h_span / factor))
  local new_scroll = math.max(0, math.min(dur_qn - new_span, center - new_span * 0.5))
  view.view_qn = (math.abs(new_span - dur_qn) < 0.001) and -1 or new_span
  view.scroll_qn = new_scroll
end

-- V zoom：以視窗中心 note 為錨點 -- vertical zoom anchored at center note
function FUNC.midi_editor_zoom_v(c, factor)
  FUNC.midi_editor_ensure_view(c)
  local view = c.midi_view
  local evt = FUNC.midi_read_events(c)
  local top, bot = resolve_note_window(view, evt.notes)
  local rows = top - bot + 1
  local center = (top + bot) * 0.5
  local new_rows = math.max(4, math.min(128, math.floor(rows / factor + 0.5)))
  local new_top = math.floor(center + new_rows * 0.5 + 0.5)
  new_top = math.max(new_rows - 1, math.min(127, new_top))
  view.note_top = new_top
  view.note_rows = new_rows
end

-- =====================================================================
-- =====================================================================
-- Phase B-E stubs — declared for next session's impl
-- All are no-op unless noted; call sites in draw_midi_editor_panel
-- =====================================================================
-- =====================================================================

---------------------------------------------------------------------
-- Phase B: Snap — 15px 對齊 grid (MIDI_guide #14)
---------------------------------------------------------------------
-- 找 15px 範圍內最近的 beat/subdivision 線；否則回傳原 QN
-- nearest grid line within 15px, else pass through
function FUNC.midi_editor_snap_qn(c, qn, L)
  if not L or L.cw <= 0 or L.h_span <= 0 then return qn end
  local px_per_qn = L.cw / L.h_span
  if px_per_qn <= 0 then return qn end
  local snap_px = FUNC.sz(8)
  local snap_qn = snap_px / px_per_qn
  -- grid 粒度：若 beat 太大就細到 1/2 beat (保持網格密度合理)
  -- grid step: beat, or 1/2 beat if beats are sparse
  local step = L.beat_qn
  while step * px_per_qn > FUNC.sz(60) do step = step * 0.5 end
  local nearest = math.floor(qn / step + 0.5) * step
  if math.abs(nearest - qn) <= snap_qn then return nearest end
  return qn
end

---------------------------------------------------------------------
-- Phase B: Wheel (MIDI_guide #12)
-- scroll=vscroll, shift+scroll=hscroll, cmd+scroll=hzoom, opt+scroll=vzoom
---------------------------------------------------------------------
function FUNC.midi_editor_handle_wheel(c, L, hovered)
  if not hovered or not L then return end
  local wheel_v, wheel_h = ImGui.GetMouseWheel(ctx)
  local wheel = wheel_v ~= 0 and wheel_v or wheel_h
  if wheel == 0 then return end
  FUNC.wheel_taken = true  -- edit 面板就不要再水平捲動 -- edit panel won't also h-scroll
  local view = c.midi_view
  local hs = ImGui.IsKeyDown(ctx, ImGui.Mod_Shift())
  local hc = ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl())
  local ha = ImGui.IsKeyDown(ctx, ImGui.Mod_Alt())
  local mx, my = ImGui.GetMousePos(ctx)

  if hc then
    -- 水平縮放，以滑鼠位置為錨點；方向對齊 audio q + 吃 wf_wheel.hzoom.rev 設定
    -- hzoom anchored at mouse; direction matches waveform + honors wf_wheel.hzoom.rev
    local anchor_q = L.x_to_qn(mx)
    local frac = math.max(0, math.min(1, (mx - L.cx) / L.cw))
    local hz_rev = (wf_wheel and wf_wheel.hzoom and wf_wheel.hzoom.rev) or false
    local eff = hz_rev and -wheel or wheel
    local new_span = L.h_span * (eff > 0 and (1/1.25) or 1.25)  -- eff>0 → 縮小 span = zoom in
    new_span = math.max(0.25, math.min(L.dur_qn, new_span))
    local new_scroll = math.max(0, math.min(L.dur_qn - new_span, anchor_q - new_span * frac))
    view.view_qn = (math.abs(new_span - L.dur_qn) < 0.001) and -1 or new_span
    view.scroll_qn = new_scroll
  elseif ha then
    -- 垂直縮放，以滑鼠 note 為錨點；方向對齊 audio q + 吃 wf_wheel.vzoom.rev
    -- vzoom anchored at mouse note; direction matches waveform + honors wf_wheel.vzoom.rev
    local vz_rev = (wf_wheel and wf_wheel.vzoom and wf_wheel.vzoom.rev) or false
    local eff = vz_rev and -wheel or wheel
    local anchor_n = L.y_to_note(my)
    local top, bot = L.note_hi, L.note_lo
    local rows = top - bot + 1
    local new_rows = math.max(4, math.min(128, math.floor(rows * (eff > 0 and (1/1.25) or 1.25) + 0.5)))  -- eff>0 → 減少 rows = zoom in
    local frac = (top - anchor_n) / math.max(1, rows)
    local new_top = math.floor(anchor_n + new_rows * frac + 0.5)
    new_top = math.max(new_rows - 1, math.min(127, new_top))
    view.note_top = new_top
    view.note_rows = new_rows
  elseif hs then
    -- 水平捲動；吃 wf_wheel.scroll.rev -- horizontal scroll, honors wf_wheel.scroll.rev
    local sc_rev = (wf_wheel and wf_wheel.scroll and wf_wheel.scroll.rev) or false
    local eff = sc_rev and -wheel or wheel
    local amt = -eff * L.h_span * 0.1
    view.scroll_qn = math.max(0, math.min(L.dur_qn - L.h_span, (view.scroll_qn or 0) + amt))
    if view.view_qn < 0 then view.view_qn = L.h_span end
  else
    -- 垂直捲動 (改變 note_top)；吃 wf_wheel.scroll.rev 維持一致 -- vscroll shifts note_top
    local sc_rev = (wf_wheel and wf_wheel.scroll and wf_wheel.scroll.rev) or false
    local eff = sc_rev and -wheel or wheel
    local rows = L.note_hi - L.note_lo + 1
    local dr = (eff > 0) and 2 or -2
    local new_top = math.max(rows - 1, math.min(127, (view.note_top >= 0 and view.note_top or L.note_hi) + dr))
    view.note_top = new_top
    if view.note_rows < 0 then view.note_rows = rows end
  end
end

---------------------------------------------------------------------
-- Phase B: Hit test — point-in-note / point-near-CC
---------------------------------------------------------------------
function FUNC.midi_editor_hit_test(c, L, mx, my)
  if not L then return nil end
  local view = c.midi_view
  -- Notes 優先 (矩形 hit) -- notes first (rectangle hit)
  if view.show_notes then
    for ni, n in ipairs(L.evt.notes) do
      if pass_ch_filter(view, n.ch) and n.note >= L.note_lo and n.note <= L.note_hi then
        local row = L.note_hi - n.note
        local ny1 = L.cy + row * L.note_h
        local ny2 = ny1 + L.note_h
        local nx1 = L.qn_to_x(n.t_qn)
        local nx2 = L.qn_to_x(n.t_qn + n.len_qn)
        if mx >= nx1 and mx <= math.max(nx1 + FUNC.sz(2), nx2)
           and my >= ny1 and my <= ny2 then
          return {kind="note", index=ni, event=n}
        end
      end
    end
  end
  -- CCs 次之 (圓點 ±4px) -- CCs next (circle hit ±4px around top dot)
  if view.show_ccs then
    local hit_r = FUNC.sz(4)
    for ci, cc in ipairs(L.evt.ccs) do
      if pass_ch_filter(view, cc.ch) and pass_cc_filter(view, cc) then
        local gx = L.qn_to_x(cc.t_qn)
        if math.abs(mx - gx) <= hit_r and my >= L.cy and my <= L.cy + L.ch then
          return {kind="cc", index=ci, event=cc}
        end
      end
    end
  end
  return nil
end

---------------------------------------------------------------------
-- Phase B: Selection helpers
---------------------------------------------------------------------
local function sel_key(kind, idx) return (kind == "note" and "n" or "c") .. idx end

-- 矩形選取 -- select events whose rect overlaps given screen rect
function FUNC.midi_editor_select_in_rect(c, L, x1, y1, x2, y2, toggle, snap)
  if not L then return end
  if toggle then
    c._midi_sel = {}
    if snap then for k, v in pairs(snap) do c._midi_sel[k] = v end end
  else
    c._midi_sel = {}
  end
  local view = c.midi_view
  local lx, rx = math.min(x1, x2), math.max(x1, x2)
  local ty, by = math.min(y1, y2), math.max(y1, y2)
  if view.show_notes then
    for ni, n in ipairs(L.evt.notes) do
      if pass_ch_filter(view, n.ch) and n.note >= L.note_lo and n.note <= L.note_hi then
        local row = L.note_hi - n.note
        local ny1 = L.cy + row * L.note_h
        local ny2 = ny1 + L.note_h
        local nx1 = L.qn_to_x(n.t_qn)
        local nx2 = L.qn_to_x(n.t_qn + n.len_qn)
        if nx2 >= lx and nx1 <= rx and ny2 >= ty and ny1 <= by then
          local k = sel_key("note", ni)
          if toggle then c._midi_sel[k] = (not c._midi_sel[k]) and true or nil
          else c._midi_sel[k] = true end
        end
      end
    end
  end
  if view.show_ccs then
    for ci, cc in ipairs(L.evt.ccs) do
      if pass_ch_filter(view, cc.ch) and pass_cc_filter(view, cc) then
        local gx = L.qn_to_x(cc.t_qn)
        if gx >= lx and gx <= rx and L.cy + L.ch >= ty and L.cy <= by then
          local k = sel_key("cc", ci)
          if toggle then c._midi_sel[k] = (not c._midi_sel[k]) and true or nil
          else c._midi_sel[k] = true end
        end
      end
    end
  end
end

-- cmd+click：選同 pitch (note) 或同 CC 號 -- select same pitch / CC number
function FUNC.midi_editor_select_same(c, L, ref)
  if not ref or not L then return end
  c._midi_sel = {}
  if ref.kind == "note" then
    local p = ref.event.note
    for ni, n in ipairs(L.evt.notes) do
      if n.note == p then c._midi_sel[sel_key("note", ni)] = true end
    end
  else
    local rc = ref.event
    for ci, cc in ipairs(L.evt.ccs) do
      if (cc.chanmsg == rc.chanmsg) and ((rc.chanmsg or 0xB0) ~= 0xB0 or cc.msg2 == rc.msg2) then
        c._midi_sel[sel_key("cc", ci)] = true
      end
    end
  end
end

---------------------------------------------------------------------
-- Phase B/C: Mouse handling
-- Left click-empty:   cursor + marquee select
-- Left click-event:   select (shift=toggle, cmd=select-same)
-- Left drag-event:    move (cmd=dup, opt=resize, shift=axis-lock)
-- Opt click-event:    delete (決議於 release 且未 drag 時)
-- Right click:        context menu (Phase D)
-- Right drag-note:    velocity edit (Phase C polish — TODO)
---------------------------------------------------------------------
local DRAG_THRESH_PX = 3  -- pending→active drag 的最小位移 -- min movement to promote drag

function FUNC.midi_editor_handle_mouse(c, L, hovered, clicked)
  if not L then return end
  local view = c.midi_view
  local mx, my = ImGui.GetMousePos(ctx)
  local in_chart = (mx >= L.cx and mx <= L.cx + L.cw and my >= L.cy and my <= L.cy + L.ch)
  local EDGE_PX = FUNC.sz(4)

  -- note 邊緣 hit 判定：回 "start"(右邊緣→拖右改 end) / "end"(左邊緣→拖左改 start) / nil
  -- detect note edge: returns anchor for resize_selected, nil if middle
  local function note_edge(hit)
    if not hit or hit.kind ~= "note" then return nil end
    local nx1 = L.qn_to_x(hit.event.t_qn)
    local nx2 = L.qn_to_x(hit.event.t_qn + hit.event.len_qn)
    if (nx2 - nx1) < EDGE_PX * 2 then return nil end
    if mx >= nx2 - EDGE_PX then return "start" end
    if mx <= nx1 + EDGE_PX then return "end" end
    return nil
  end

  -- hover edge → 顯示左右拉伸游標 -- show resize cursor on edge hover
  if in_chart and not c._midi_drag and hovered then
    local hh = FUNC.midi_editor_hit_test(c, L, mx, my)
    if note_edge(hh) then ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeEW()) end
  end

  ---------------------------------------------------
  -- 初次點擊：決定動作 -- initial click: decide action
  ---------------------------------------------------
  if clicked and in_chart then
    local hit = FUNC.midi_editor_hit_test(c, L, mx, my)
    local shift = ImGui.IsKeyDown(ctx, ImGui.Mod_Shift())
    local cmd   = ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl())
    local alt   = ImGui.IsKeyDown(ctx, ImGui.Mod_Alt())
    if hit then
      local k = sel_key(hit.kind, hit.index)
      -- anchor 資訊：move 用 note 頭；resize 用被拖的邊 -- anchor info: head for move, dragged edge for resize
      local anchor_t = (hit.kind == "note") and hit.event.t_qn or nil
      local function edge_qn(anc)
        if hit.kind ~= "note" then return nil end
        return (anc == "start") and (hit.event.t_qn + hit.event.len_qn) or hit.event.t_qn
      end
      if alt then
        -- opt+click=delete；opt+drag=duplicate (note 上才有，空白處走 paint)
        -- opt+click=delete; opt+drag=duplicate (on note hit)
        if not c._midi_sel[k] then c._midi_sel = {[k]=true} end
        c._midi_drag = { kind="pending_del_or_dup", mx=mx, my=my,
                         qn0=L.x_to_qn(mx), pitch0=L.y_to_note(my), anchor_t=anchor_t }
      elseif cmd then
        -- cmd+drag = velocity 調整（dy 反向）-- cmd+drag adjusts velocity by dy
        if not c._midi_sel[k] then c._midi_sel = {[k]=true} end
        local snap = {}
        for ni, n in ipairs(L.evt.notes) do
          if c._midi_sel["n"..ni] then snap["n"..ni] = n.vel end
        end
        for ci, cc in ipairs(L.evt.ccs) do
          if c._midi_sel["c"..ci] then snap["c"..ci] = cc.msg3 end
        end
        c._midi_drag = { kind="pending_vel", mx=mx, my=my, snap=snap }
      elseif shift then
        c._midi_sel[k] = (not c._midi_sel[k]) and true or nil
      else
        if not c._midi_sel[k] then c._midi_sel = {[k]=true} end
        local edge = note_edge(hit)
        if edge then
          c._midi_drag = { kind="pending_resize", mx=mx, my=my,
                           qn0=L.x_to_qn(mx), pitch0=L.y_to_note(my),
                           anchor=edge, anchor_edge_qn=edge_qn(edge) }
        else
          c._midi_drag = { kind="pending_move", mx=mx, my=my,
                           qn0=L.x_to_qn(mx), pitch0=L.y_to_note(my), anchor_t=anchor_t }
        end
      end
    elseif alt then
      -- opt+mousedown 空白：先記錄 paint 起點，note 在 release 才實際建立（避免 click 瞬間先閃預設長度）
      -- opt+mousedown on empty: defer note creation until release (avoids first-frame default-length flash)
      if view.note_top < 0  then view.note_top  = L.note_hi end
      if view.note_rows < 0 then view.note_rows = L.note_hi - L.note_lo + 1 end
      local q_raw = math.max(0, math.min(L.dur_qn, L.x_to_qn(mx)))
      local q_snap = FUNC.midi_editor_snap_qn(c, q_raw, L) or q_raw
      local pitch = math.max(0, math.min(127, L.y_to_note(my)))
      local ch = (view.channel_filter and view.channel_filter > 0) and (view.channel_filter - 1) or 0
      local def_len = math.min(L.beat_qn, math.max(0.05, L.dur_qn - q_snap))
      if def_len > 0 then
        view.cursor_qn = q_snap
        c._midi_drag = { kind="pending_paint", mx=mx, my=my,
                         paint_q=q_snap, paint_pitch=pitch, paint_ch=ch,
                         paint_default_len=def_len, paint_cur_qn=q_snap }
      end
    else
      -- 空白：放 cursor + 啟 marquee -- empty: place cursor + begin marquee
      local q = math.max(0, math.min(L.dur_qn, L.x_to_qn(mx)))
      view.cursor_qn = FUNC.midi_editor_snap_qn(c, q, L) or q
      if not shift then c._midi_sel = {}; FUNC.clear_inner_sels() end
      local snap
      if shift then
        snap = {}
        for k, v in pairs(c._midi_sel or {}) do snap[k] = v end
      end
      c._midi_marquee = { active=true, x1=mx, y1=my, x2=mx, y2=my, toggle=shift, snap=snap }
    end
  end

  ---------------------------------------------------
  -- Marquee 更新 -- marquee live update
  ---------------------------------------------------
  local mq = c._midi_marquee
  if mq and mq.active then
    if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left()) then
      mq.x2, mq.y2 = mx, my
      FUNC.midi_editor_select_in_rect(c, L, mq.x1, mq.y1, mq.x2, mq.y2, mq.toggle, mq.snap)
    else
      c._midi_marquee = nil
    end
  end

  ---------------------------------------------------
  -- Drag 追蹤 — promote pending→active，release 時 commit
  -- Drag tracking — promote pending→active, commit on release
  ---------------------------------------------------
  local dg = c._midi_drag
  if dg then
    if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left()) then
      local dx_px = mx - dg.mx
      local dy_px = my - dg.my
      -- 位移超過閥值就 promote -- promote once moved past threshold
      if dg.kind:find("^pending_") and (math.abs(dx_px) > FUNC.sz(DRAG_THRESH_PX) or math.abs(dy_px) > FUNC.sz(DRAG_THRESH_PX)) then
        if dg.kind == "pending_del_or_resize" then dg.kind = "resize"
        elseif dg.kind == "pending_del_or_dup" then dg.kind = "dup"
        elseif dg.kind == "pending_vel"       then dg.kind = "vel"
        elseif dg.kind == "pending_move"      then dg.kind = "move"
        elseif dg.kind == "pending_paint"     then dg.kind = "paint"
        elseif dg.kind == "pending_resize"    then dg.kind = "resize"
        end
      end
      -- paint：另用 paint_cur_qn（end 直接跟游標），不走 dq/qn0 那條
      -- paint mode tracks paint_cur_qn directly (end follows cursor); skip dq/qn0 path
      if dg.kind == "paint" or dg.kind == "pending_paint" then
        local cur_qn = math.max(0, math.min(L.dur_qn, L.x_to_qn(mx)))
        dg.paint_cur_qn = FUNC.midi_editor_snap_qn(c, cur_qn, L) or cur_qn
      elseif dg.kind == "vel" or dg.kind == "pending_vel" then
        -- dy 反向 → vel delta，6px = 1 unit (1/3 敏感度) -- dy↑ = vel↑, lowered sensitivity
        dg.vel_delta = math.floor((dg.my - my) * (1/6))
      else
        -- 計算 dq / dpitch -- compute delta QN / pitch
        local cur_qn = L.x_to_qn(mx)
        local cur_pitch = L.y_to_note(my)
        local dq, dpitch
        if (dg.kind == "resize") and dg.anchor_edge_qn then
          -- resize：被拖的邊 snap 到滑鼠位置 -- dragged edge snaps to mouse cursor
          local snapped = FUNC.midi_editor_snap_qn(c, cur_qn, L) or cur_qn
          dq = snapped - dg.anchor_edge_qn
        elseif (dg.kind == "move" or dg.kind == "dup") and dg.anchor_t then
          -- move：以 note 頭為錨點，扣除 mouse 在 note 內的偏移後 snap -- anchor at note head, snap after subtracting in-note offset
          local inner_off = dg.qn0 - dg.anchor_t
          local new_head_raw = cur_qn - inner_off
          local new_head = FUNC.midi_editor_snap_qn(c, new_head_raw, L) or new_head_raw
          dq = new_head - dg.anchor_t
        else
          -- fallback：原本對 mouse 位移做 snap -- legacy: snap delta
          local target_qn = FUNC.midi_editor_snap_qn(c, cur_qn, L) or cur_qn
          dq = target_qn - (FUNC.midi_editor_snap_qn(c, dg.qn0, L) or dg.qn0)
        end
        dpitch = cur_pitch - dg.pitch0
        -- shift 軸鎖 -- shift axis-lock
        if ImGui.IsKeyDown(ctx, ImGui.Mod_Shift()) then
          if math.abs(dx_px) > math.abs(dy_px) then dpitch = 0 else dq = 0 end
        end
        -- resize：dpitch 無意義且邊界不同（允許左端進 0、右端維持 dur）
        -- resize: dpitch irrelevant; move/dup apply uniform clamp across selection
        if dg.kind == "move" or dg.kind == "dup" then
          dq, dpitch = FUNC.midi_editor_clamp_delta(c, L.evt, L.dur_qn, dq, dpitch)
        end
        dg.dq = dq; dg.dpitch = dpitch
      end
    else
      -- Release：依 kind commit -- release: dispatch by kind
      if dg.kind == "pending_del_or_resize" or dg.kind == "pending_del_or_dup" then
        -- 沒 drag → opt+click delete -- click-release without drag → delete
        FUNC.midi_editor_delete_selected(c)
      elseif dg.kind == "pending_vel" then
        -- cmd+click 沒 drag → 不動（選取已更新）-- click without drag, no-op
      elseif dg.kind == "vel" then
        if dg.vel_delta and dg.vel_delta ~= 0 and dg.snap then
          FUNC.midi_editor_apply_vel_delta(c, dg.snap, dg.vel_delta)
        end
      elseif dg.kind == "pending_paint" or dg.kind == "paint" then
        -- 在 release 才實際建立 note：pending_paint=預設長度；paint=拖到的長度
        -- create the note now (deferred from mousedown): pending_paint→default, paint→drag length
        local q0 = dg.paint_q
        local pitch = dg.paint_pitch
        local pch = dg.paint_ch or 0
        local len_qn
        if dg.kind == "paint" and dg.paint_cur_qn then
          len_qn = math.max(0.05, dg.paint_cur_qn - q0)
        else
          len_qn = dg.paint_default_len or 0.25
        end
        if q0 and pitch and len_qn > 0 then
          FUNC.midi_editor_create_note(c, q0, pitch, len_qn, pch, 96)
          -- 依 (t_qn, pitch, ch) 找新 note 真實索引並選取（MIDI_Sort 後位置不一定在末位）
          -- locate new note by (t_qn, pitch, ch) for selection (post-sort index isn't last)
          local fresh = FUNC.midi_read_events(c)
          local new_idx = nil
          for ni, n in ipairs(fresh.notes) do
            if n.note == pitch and n.ch == pch and math.abs(n.t_qn - q0) < 0.001 then
              new_idx = ni; break
            end
          end
          c._midi_sel = new_idx and { ["n"..new_idx] = true } or {}
        end
      elseif dg.kind == "move" then
        FUNC.midi_editor_move_selected(c, dg.dq or 0, dg.dpitch or 0)
      elseif dg.kind == "dup" then
        FUNC.midi_editor_duplicate_selected(c, dg.dq or 0, dg.dpitch or 0)
      elseif dg.kind == "resize" then
        -- resize: dpitch 忽略；dq + anchor -- ignore dpitch, use dq + anchor
        FUNC.midi_editor_resize_selected(c, dg.dq or 0, dg.anchor or "start")
      end
      c._midi_drag = nil
    end
  end
end

---------------------------------------------------------------------
-- Phase C: Event mutation (writes back to REAPER MIDI item)
-- 所有寫入皆透過此 helper，統一處理 PPQ 轉換與 MIDI_Sort
-- All writes go through this helper (unified PPQ conversion + Sort)
---------------------------------------------------------------------
local function commit_ctx(c)
  local it, tk = FUNC.midi_get_item_take(c)
  if not tk then return nil end
  local pos_s = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local item_ppq = reaper.MIDI_GetPPQPosFromProjTime(tk, pos_s)
  local item_qn = reaper.MIDI_GetProjQNFromPPQPos(tk, item_ppq)
  return { item = it, take = tk, item_qn = item_qn }
end

-- item 相對 QN → 專案絕對 PPQ -- item-relative QN → project-absolute PPQ
local function rel_qn_to_ppq(cx, rel_qn)
  return reaper.MIDI_GetPPQPosFromProjQN(cx.take, cx.item_qn + rel_qn)
end

-- 收集選取的 note/cc raw_idx (用於 REAPER API) -- collect raw indices for REAPER API
-- 必須傳入 fresh evt，因為 raw_idx 僅在讀取當下有效
-- MUST be called with fresh evt since raw_idx is only valid at read time
local function collect_selected_raw(c, evt)
  local notes, ccs = {}, {}
  local sel = c._midi_sel or {}
  for ni, n in ipairs(evt.notes) do
    if sel["n"..ni] then notes[#notes+1] = { idx = n.raw_idx, data = n } end
  end
  for ci, cc in ipairs(evt.ccs) do
    if sel["c"..ci] then ccs[#ccs+1] = { idx = cc.raw_idx, data = cc } end
  end
  return notes, ccs
end

-- 依目前選取整體邊界，把 dq / dpitch 夾在 [0, dur_qn] / [0, 127] 內
-- clamp dq / dpitch to keep the whole selection inside [0, dur_qn] / [0, 127]
function FUNC.midi_editor_clamp_delta(c, evt, dur_qn, dq, dpitch)
  dq = dq or 0; dpitch = dpitch or 0
  local sel = c._midi_sel or {}
  local min_start, max_end = math.huge, -math.huge
  local min_pitch, max_pitch = 128, -1
  local n_any = false
  for ni, n in ipairs(evt.notes) do
    if sel["n"..ni] then
      n_any = true
      if n.t_qn < min_start then min_start = n.t_qn end
      if (n.t_qn + n.len_qn) > max_end then max_end = n.t_qn + n.len_qn end
      if n.note < min_pitch then min_pitch = n.note end
      if n.note > max_pitch then max_pitch = n.note end
    end
  end
  for ci, cc in ipairs(evt.ccs) do
    if sel["c"..ci] then
      if cc.t_qn < min_start then min_start = cc.t_qn end
      if cc.t_qn > max_end then max_end = cc.t_qn end
    end
  end
  if min_start == math.huge then return dq, dpitch end
  -- 水平夾限：第一個音已到 0 或最後一個音已到 dur_qn 就不允許再往外
  -- 但若已經在外，仍允許使用者朝內收回（不卡死）
  -- horizontal clamp: block motion that pushes selection further beyond [0, dur_qn];
  -- still allow motion back toward the interior if already out-of-bounds
  local du = dur_qn or math.huge
  local dq_min = math.min(0, min_start) - min_start
  local dq_max = math.max(du, max_end) - max_end
  if dq < dq_min then dq = dq_min end
  if dq > dq_max then dq = dq_max end
  -- 垂直夾限（只在有 note 選取時）-- pitch clamp (only if notes selected)
  if n_any then
    local dp_min = -min_pitch
    local dp_max = 127 - max_pitch
    if dpitch < dp_min then dpitch = dp_min end
    if dpitch > dp_max then dpitch = dp_max end
  end
  return dq, dpitch
end

-- 刪除選取 events -- delete selected events
function FUNC.midi_editor_delete_selected(c)
  local cx = commit_ctx(c); if not cx then return end
  local evt = FUNC.midi_read_events(c)
  local sn, sc = collect_selected_raw(c, evt)
  if #sn == 0 and #sc == 0 then return end
  -- 倒序刪除以保留未刪 index -- reverse-order delete to keep remaining indices valid
  table.sort(sn, function(a,b) return a.idx > b.idx end)
  table.sort(sc, function(a,b) return a.idx > b.idx end)
  for _, e in ipairs(sn) do reaper.MIDI_DeleteNote(cx.take, e.idx) end
  for _, e in ipairs(sc) do reaper.MIDI_DeleteCC(cx.take, e.idx) end
  reaper.MIDI_Sort(cx.take)
  reaper.UpdateItemInProject(cx.item)
  c._midi_sel = {}
end

-- 移動選取 events：notes 套 dq+dpitch；CCs 只套 dq -- move (notes: dq+dpitch, CCs: dq only)
function FUNC.midi_editor_move_selected(c, dq, dpitch)
  if (not dq or dq == 0) and (not dpitch or dpitch == 0) then return end
  local cx = commit_ctx(c); if not cx then return end
  local evt = FUNC.midi_read_events(c)
  local sn, sc = collect_selected_raw(c, evt)
  -- 整體夾限以維持選取群組相對位置 -- group clamp preserves selection layout
  dq, dpitch = FUNC.midi_editor_clamp_delta(c, evt, evt.dur_qn, dq or 0, dpitch or 0)
  if dq == 0 and dpitch == 0 then return end
  for _, e in ipairs(sn) do
    local n = e.data
    -- group clamp 已保證合理範圍；不另外 per-note clamp 以免壓扁長度
    -- group clamp already constrained dq; skip per-note clamp to preserve length
    local new_t = n.t_qn + dq
    local new_end = new_t + n.len_qn
    local new_pitch = math.max(0, math.min(127, n.note + dpitch))
    reaper.MIDI_SetNote(cx.take, e.idx, nil, nil,
      rel_qn_to_ppq(cx, new_t), rel_qn_to_ppq(cx, new_end), n.ch, new_pitch, n.vel, true)
  end
  for _, e in ipairs(sc) do
    local cc = e.data
    local new_t = cc.t_qn + dq
    reaper.MIDI_SetCC(cx.take, e.idx, nil, nil,
      rel_qn_to_ppq(cx, new_t), cc.chanmsg, cc.ch, cc.msg2, cc.msg3, true)
  end
  reaper.MIDI_Sort(cx.take)
  reaper.UpdateItemInProject(cx.item)
end

-- 複製選取 events (offset by dq, dpitch)，並把選取切到新副本
-- duplicate selected events with offset; selection switches to new copies
function FUNC.midi_editor_duplicate_selected(c, dq, dpitch)
  local cx = commit_ctx(c); if not cx then return end
  local evt = FUNC.midi_read_events(c)
  local sn, sc = collect_selected_raw(c, evt)
  dq, dpitch = FUNC.midi_editor_clamp_delta(c, evt, evt.dur_qn, dq or 0, dpitch or 0)
  if #sn == 0 and #sc == 0 then return end
  for _, e in ipairs(sn) do
    local n = e.data
    local new_t = n.t_qn + dq
    local new_end = new_t + n.len_qn
    local new_pitch = math.max(0, math.min(127, n.note + dpitch))
    reaper.MIDI_InsertNote(cx.take, false, false,
      rel_qn_to_ppq(cx, new_t), rel_qn_to_ppq(cx, new_end),
      n.ch, new_pitch, n.vel, true)
  end
  for _, e in ipairs(sc) do
    local cc = e.data
    local new_t = cc.t_qn + dq
    reaper.MIDI_InsertCC(cx.take, false, false,
      rel_qn_to_ppq(cx, new_t), cc.chanmsg, cc.ch, cc.msg2, cc.msg3)
  end
  reaper.MIDI_Sort(cx.take)
  reaper.UpdateItemInProject(cx.item)
  -- 新插入的事件成為尾端 index，無法精確重建選取；清空由使用者重選
  -- newly-inserted events land at end; selection cleared for user to re-pick
  c._midi_sel = {}
end

-- Resize notes：anchor="start"→移 end；"end"→移 start
-- resize notes: anchor=start moves end, anchor=end moves start
function FUNC.midi_editor_resize_selected(c, dq, anchor)
  if not dq or dq == 0 then return end
  local cx = commit_ctx(c); if not cx then return end
  local evt = FUNC.midi_read_events(c)
  local sn = collect_selected_raw(c, evt)
  anchor = anchor or "start"
  for _, e in ipairs(sn) do
    local n = e.data
    local new_t, new_end
    if anchor == "end" then
      new_t = math.max(0, math.min(n.t_qn + n.len_qn - 0.01, n.t_qn + dq))
      new_end = n.t_qn + n.len_qn
    else
      new_t = n.t_qn
      new_end = math.max(n.t_qn + 0.01, n.t_qn + n.len_qn + dq)
    end
    reaper.MIDI_SetNote(cx.take, e.idx, nil, nil,
      rel_qn_to_ppq(cx, new_t), rel_qn_to_ppq(cx, new_end), n.ch, n.note, n.vel, true)
  end
  reaper.MIDI_Sort(cx.take)
  reaper.UpdateItemInProject(cx.item)
end

-- 設定值：notes=velocity(1-127)，CCs=msg3(0-127) -- set velocity/value
function FUNC.midi_editor_set_value(c, v)
  local cx = commit_ctx(c); if not cx then return end
  local evt = FUNC.midi_read_events(c)
  local sn, sc = collect_selected_raw(c, evt)
  for _, e in ipairs(sn) do
    local n = e.data
    local vel = math.max(1, math.min(127, math.floor(v + 0.5)))
    reaper.MIDI_SetNote(cx.take, e.idx, nil, nil,
      rel_qn_to_ppq(cx, n.t_qn), rel_qn_to_ppq(cx, n.t_qn + n.len_qn), n.ch, n.note, vel, true)
  end
  for _, e in ipairs(sc) do
    local cc = e.data
    local vv = math.max(0, math.min(127, math.floor(v + 0.5)))
    reaper.MIDI_SetCC(cx.take, e.idx, nil, nil,
      rel_qn_to_ppq(cx, cc.t_qn), cc.chanmsg, cc.ch, cc.msg2, vv, true)
  end
  reaper.MIDI_Sort(cx.take)
  reaper.UpdateItemInProject(cx.item)
end

-- 套用 velocity delta（cmd+vdrag 用，依 snapshot 計算）-- apply vel delta from snapshot
function FUNC.midi_editor_apply_vel_delta(c, snap, delta)
  local cx = commit_ctx(c); if not cx then return end
  local evt = FUNC.midi_read_events(c)
  for ni, n in ipairs(evt.notes) do
    local k = "n"..ni
    if snap[k] then
      local nv = math.max(1, math.min(127, snap[k] + delta))
      reaper.MIDI_SetNote(cx.take, n.raw_idx, nil, nil,
        rel_qn_to_ppq(cx, n.t_qn), rel_qn_to_ppq(cx, n.t_qn + n.len_qn),
        n.ch, n.note, nv, true)
    end
  end
  for ci, cc in ipairs(evt.ccs) do
    local k = "c"..ci
    if snap[k] then
      local nv = math.max(0, math.min(127, snap[k] + delta))
      reaper.MIDI_SetCC(cx.take, cc.raw_idx, nil, nil,
        rel_qn_to_ppq(cx, cc.t_qn), cc.chanmsg, cc.ch, cc.msg2, nv, true)
    end
  end
  reaper.MIDI_Sort(cx.take)
  reaper.UpdateItemInProject(cx.item)
end

-- 把選取事件複製到所有 16 個 channel（set value popup channel 留白用）
-- duplicate selected events across all 16 channels
function FUNC.midi_editor_set_channel_all(c)
  local cx = commit_ctx(c); if not cx then return end
  local evt = FUNC.midi_read_events(c)
  local sn, sc = collect_selected_raw(c, evt)
  for _, e in ipairs(sn) do
    local n = e.data
    for ch = 0, 15 do
      if ch ~= n.ch then
        reaper.MIDI_InsertNote(cx.take, false, false,
          rel_qn_to_ppq(cx, n.t_qn), rel_qn_to_ppq(cx, n.t_qn + n.len_qn),
          ch, n.note, n.vel, true)
      end
    end
  end
  for _, e in ipairs(sc) do
    local cc = e.data
    for ch = 0, 15 do
      if ch ~= cc.ch then
        reaper.MIDI_InsertCC(cx.take, false, false,
          rel_qn_to_ppq(cx, cc.t_qn), cc.chanmsg, ch, cc.msg2, cc.msg3)
      end
    end
  end
  reaper.MIDI_Sort(cx.take)
  reaper.UpdateItemInProject(cx.item)
end

-- 設定 channel 給選取 events (0-15) -- set channel on selected events
function FUNC.midi_editor_set_channel(c, ch)
  local cx = commit_ctx(c); if not cx then return end
  ch = math.max(0, math.min(15, math.floor(ch + 0.5)))
  local evt = FUNC.midi_read_events(c)
  local sn, sc = collect_selected_raw(c, evt)
  for _, e in ipairs(sn) do
    local n = e.data
    reaper.MIDI_SetNote(cx.take, e.idx, nil, nil,
      rel_qn_to_ppq(cx, n.t_qn), rel_qn_to_ppq(cx, n.t_qn + n.len_qn), ch, n.note, n.vel, true)
  end
  for _, e in ipairs(sc) do
    local cc = e.data
    reaper.MIDI_SetCC(cx.take, e.idx, nil, nil,
      rel_qn_to_ppq(cx, cc.t_qn), cc.chanmsg, ch, cc.msg2, cc.msg3, true)
  end
  reaper.MIDI_Sort(cx.take)
  reaper.UpdateItemInProject(cx.item)
end

-- 新增 note -- create a new note
function FUNC.midi_editor_create_note(c, qn, pitch, len_qn, ch, vel)
  local cx = commit_ctx(c); if not cx then return end
  qn = math.max(0, qn or 0)
  pitch = math.max(0, math.min(127, math.floor((pitch or 60) + 0.5)))
  len_qn = math.max(0.01, len_qn or 0.25)
  ch = math.max(0, math.min(15, ch or 0))
  vel = math.max(1, math.min(127, math.floor((vel or 96) + 0.5)))
  reaper.MIDI_InsertNote(cx.take, false, false,
    rel_qn_to_ppq(cx, qn), rel_qn_to_ppq(cx, qn + len_qn),
    ch, pitch, vel, false)
  reaper.MIDI_Sort(cx.take)
  reaper.UpdateItemInProject(cx.item)
end

---------------------------------------------------------------------
-- Phase D: Clipboard (opt+c/x/v) (MIDI_guide #13)
---------------------------------------------------------------------
-- Module-level clipboard, shared across cues -- 跨 cue 的 MIDI 剪貼簿
FUNC._midi_clipboard = FUNC._midi_clipboard or { notes = {}, ccs = {}, ref_qn = 0 }

-- 複製選取到 module-level clipboard，以最早的事件為 ref_qn
-- copy selected events to module-level clipboard, earliest event = ref_qn
function FUNC.midi_editor_copy(c)
  local evt = FUNC.midi_read_events(c)
  local sn, sc = collect_selected_raw(c, evt)
  if #sn == 0 and #sc == 0 then return end
  local ref_qn = math.huge
  for _, e in ipairs(sn) do if e.data.t_qn < ref_qn then ref_qn = e.data.t_qn end end
  for _, e in ipairs(sc) do if e.data.t_qn < ref_qn then ref_qn = e.data.t_qn end end
  local notes, ccs = {}, {}
  for _, e in ipairs(sn) do
    local n = e.data
    notes[#notes+1] = { rel_qn=n.t_qn-ref_qn, len_qn=n.len_qn, ch=n.ch, note=n.note, vel=n.vel }
  end
  for _, e in ipairs(sc) do
    local cc = e.data
    ccs[#ccs+1] = { rel_qn=cc.t_qn-ref_qn, chanmsg=cc.chanmsg, ch=cc.ch, msg2=cc.msg2, msg3=cc.msg3 }
  end
  FUNC._midi_clipboard = { notes=notes, ccs=ccs, ref_qn=ref_qn }
end

function FUNC.midi_editor_cut(c)
  FUNC.midi_editor_copy(c)
  FUNC.midi_editor_delete_selected(c)
end

-- 貼上：cursor_qn 為基準；若無 cursor 則用原 ref_qn
-- paste at cursor_qn (fallback: original ref_qn)
function FUNC.midi_editor_paste(c)
  local clip = FUNC._midi_clipboard
  if not clip or ((#clip.notes == 0) and (#clip.ccs == 0)) then return end
  local cx = commit_ctx(c); if not cx then return end
  local view = c.midi_view
  local base = (view.cursor_qn and view.cursor_qn >= 0) and view.cursor_qn or clip.ref_qn
  for _, n in ipairs(clip.notes) do
    local q = math.max(0, base + n.rel_qn)
    reaper.MIDI_InsertNote(cx.take, false, false,
      rel_qn_to_ppq(cx, q), rel_qn_to_ppq(cx, q + n.len_qn), n.ch, n.note, n.vel, true)
  end
  for _, cc in ipairs(clip.ccs) do
    local q = math.max(0, base + cc.rel_qn)
    reaper.MIDI_InsertCC(cx.take, false, false,
      rel_qn_to_ppq(cx, q), cc.chanmsg, cc.ch, cc.msg2, cc.msg3)
  end
  reaper.MIDI_Sort(cx.take)
  reaper.UpdateItemInProject(cx.item)
  c._midi_sel = {}
end

---------------------------------------------------------------------
-- Phase D: Keyboard (MIDI_guide #13)
-- opt+c/x/v, opt+delete/backspace, opt+←/→ = move by grid, opt+↑/↓ = semitone
-- 只在 hover chart 時有效 -- only active when hovering the chart
---------------------------------------------------------------------
function FUNC.midi_editor_handle_keys(c, L, hovered)
  if not hovered or not L then return end
  if not ImGui.IsKeyDown(ctx, ImGui.Mod_Alt()) then return end
  if ImGui.IsKeyPressed(ctx, ImGui.Key_C())         then FUNC.midi_editor_copy(c)
  elseif ImGui.IsKeyPressed(ctx, ImGui.Key_X())     then FUNC.midi_editor_cut(c)
  elseif ImGui.IsKeyPressed(ctx, ImGui.Key_V())     then FUNC.midi_editor_paste(c)
  elseif ImGui.IsKeyPressed(ctx, ImGui.Key_Delete()) or ImGui.IsKeyPressed(ctx, ImGui.Key_Backspace()) then
    FUNC.midi_editor_delete_selected(c)
  elseif ImGui.IsKeyPressed(ctx, ImGui.Key_LeftArrow())  then FUNC.midi_editor_move_selected(c, -L.beat_qn, 0)
  elseif ImGui.IsKeyPressed(ctx, ImGui.Key_RightArrow()) then FUNC.midi_editor_move_selected(c,  L.beat_qn, 0)
  elseif ImGui.IsKeyPressed(ctx, ImGui.Key_UpArrow())    then FUNC.midi_editor_move_selected(c, 0,  1)
  elseif ImGui.IsKeyPressed(ctx, ImGui.Key_DownArrow())  then FUNC.midi_editor_move_selected(c, 0, -1)
  end
end

---------------------------------------------------------------------
-- Phase D: Right-click menu + set-value popup (MIDI_guide #15)
---------------------------------------------------------------------
function FUNC.midi_editor_right_click_menu(c, L, hovered)
  if not L then return end
  local mx, my = ImGui.GetMousePos(ctx)
  local in_chart = (mx >= L.cx and mx <= L.cx + L.cw and my >= L.cy and my <= L.cy + L.ch)
  -- 右鍵選單由 hand-pan handler 在 release-without-drag 時觸發 OpenPopup
  -- right-click menu opens from hand-pan handler on release-without-drag
  if ImGui.BeginPopup(ctx, "##me_rmenu"..c.id) then
    local has_sel = next(c._midi_sel) ~= nil
    local has_clip = FUNC._midi_clipboard and ((#FUNC._midi_clipboard.notes > 0) or (#FUNC._midi_clipboard.ccs > 0))
    if ImGui.MenuItem(ctx, "Copy", "⌥C", false, has_sel) then FUNC.midi_editor_copy(c) end
    if ImGui.MenuItem(ctx, "Cut",  "⌥X", false, has_sel) then FUNC.midi_editor_cut(c) end
    if ImGui.MenuItem(ctx, "Paste", "⌥V", false, has_clip) then FUNC.midi_editor_paste(c) end
    if ImGui.MenuItem(ctx, "Delete", "⌥⌫", false, has_sel) then FUNC.midi_editor_delete_selected(c) end
    ImGui.Separator(ctx)
    if ImGui.MenuItem(ctx, "Select same pitch/CC", nil, false, c._midi_menu_hit ~= nil) then
      FUNC.midi_editor_select_same(c, L, c._midi_menu_hit)
    end
    if ImGui.MenuItem(ctx, "Set value…", nil, false, has_sel) then
      -- 預填當前選取值；多選且不一致則留空 -- prefill current; blank if mixed
      local evt = FUNC.midi_read_events(c)
      local fv, fch, mv, mch
      for ni, n in ipairs(evt.notes) do
        if c._midi_sel["n"..ni] then
          if fv == nil then fv = n.vel elseif n.vel ~= fv then mv = true end
          if fch == nil then fch = n.ch elseif n.ch ~= fch then mch = true end
        end
      end
      for ci, cc in ipairs(evt.ccs) do
        if c._midi_sel["c"..ci] then
          if fv == nil then fv = cc.msg3 elseif cc.msg3 ~= fv then mv = true end
          if fch == nil then fch = cc.ch elseif cc.ch ~= fch then mch = true end
        end
      end
      local vs = (fv ~= nil and not mv) and tostring(fv) or ""
      local cs = (fch ~= nil and not mch) and tostring(fch + 1) or ""
      c._midi_sv_popup = { open=true, value=vs, channel=cs }
      popup.midi_sv = true
    end
    ImGui.EndPopup(ctx)
  end
end

-- Set value modal popup
function FUNC.midi_editor_set_value_popup(c)
  local sv = c._midi_sv_popup
  if not sv then return end
  if sv.open then
    ImGui.OpenPopup(ctx, "##me_setval"..c.id)
    sv.open = false
  end
  if ImGui.BeginPopupModal(ctx, "##me_setval"..c.id, nil, ImGui.WindowFlags_AlwaysAutoResize()) then
    ImGui.Text(ctx, "Set Value for Selected Events")
    ImGui.Dummy(ctx, 0, FUNC.sz(4))
    ImGui.SetNextItemWidth(ctx, FUNC.sz(100))
    local _, v_new = ImGui.InputText(ctx, "Velocity / CC value", sv.value)
    sv.value = v_new
    ImGui.SetNextItemWidth(ctx, FUNC.sz(100))
    local _, c_new = ImGui.InputText(ctx, "Channel (1-16, blank=no change)", sv.channel)
    sv.channel = c_new
    ImGui.Dummy(ctx, 0, FUNC.sz(4))
    if ImGui.Button(ctx, "Apply", FUNC.sz(80), 0) then
      local vnum = tonumber(sv.value)
      if vnum then FUNC.midi_editor_set_value(c, vnum) end
      if sv.channel ~= nil and sv.channel ~= "" then
        local cnum = tonumber(sv.channel)
        if cnum and cnum >= 1 and cnum <= 16 then FUNC.midi_editor_set_channel(c, cnum - 1) end
      end
      c._midi_sv_popup = nil
      popup.midi_sv = nil
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel", FUNC.sz(80), 0) then
      c._midi_sv_popup = nil
      popup.midi_sv = nil
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.EndPopup(ctx)
  end
end

---------------------------------------------------------------------
-- Phase C polish: Right-drag velocity (MIDI_guide #11)
-- 按住右鍵拖曳 note：dy 反向改 velocity；CC 同理改 msg3
-- right-mouse-down on note → drag dy changes velocity (or CC msg3)
---------------------------------------------------------------------
-- 右鍵 hand-pan：按住右鍵拖曳 = 自由平移 chart；點放（無拖曳）= 開選單
-- right-mouse hold-drag = free pan; click-release without drag = open context menu
function FUNC.midi_editor_handle_velocity_drag(c, L, hovered)
  if not L then return end
  local view = c.midi_view
  local mx, my = ImGui.GetMousePos(ctx)
  local in_chart = (mx >= L.cx and mx <= L.cx + L.cw and my >= L.cy and my <= L.cy + L.ch)
  local pd = c._midi_pan
  if hovered and in_chart and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right()) then
    local top0 = (view.note_top and view.note_top >= 0) and view.note_top or L.note_hi
    c._midi_pan = {
      mx=mx, my=my,
      scroll0=view.scroll_qn or 0,
      note_top0=top0,
      started=false,
      hit=FUNC.midi_editor_hit_test(c, L, mx, my),
    }
  end
  if pd then
    if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Right()) then
      local dx = mx - pd.mx
      local dy = my - pd.my
      if not pd.started and (math.abs(dx) > FUNC.sz(4) or math.abs(dy) > FUNC.sz(4)) then
        pd.started = true
      end
      if pd.started then
        ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeAll())
        -- 水平：dx px → qn -- horizontal pan
        local qn_per_px = L.h_span / math.max(1, L.cw)
        local max_scroll = math.max(0, L.dur_qn - L.h_span)
        view.scroll_qn = math.max(0, math.min(max_scroll, pd.scroll0 - dx * qn_per_px))
        if view.view_qn < 0 then view.view_qn = L.h_span end
        -- 垂直：dy px → note rows -- vertical pan
        local rows = L.note_hi - L.note_lo + 1
        local new_top = math.floor(pd.note_top0 + dy * (1 / math.max(1, L.note_h)) + 0.5)
        new_top = math.max(rows - 1, math.min(127, new_top))
        view.note_top = new_top
        if view.note_rows < 0 then view.note_rows = rows end
      end
    else
      -- release：無拖曳 → 開選單；有拖曳 → pan 已即時套用 -- release: open menu if no drag
      if not pd.started then
        local hit = pd.hit
        if hit then
          local k = sel_key(hit.kind, hit.index)
          if not c._midi_sel[k] then c._midi_sel = {[k]=true} end
          c._midi_menu_hit = hit
        else
          c._midi_menu_hit = nil
        end
        ImGui.OpenPopup(ctx, "##me_rmenu"..c.id)
      end
      c._midi_pan = nil
    end
  end
end
