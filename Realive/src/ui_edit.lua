-- ==========================================================================
-- ui_edit.lua — Edit Panel (inline in main window)
-- ==========================================================================

-- 19.7 EDIT PANEL (inline in main window) -- edit panel合併到主視窗
---------------------------------------------------------------------

-- 統一的 +/- 按鈕：InvisibleButton + DrawList 手繪，符號絕對置中（不受字型 metrics 影響）
-- shared +/- button: InvisibleButton + DrawList draw, glyph absolutely centered (font-metrics-proof)
function FUNC.draw_pm_btn(id_suffix, label, sz, bg, bg_h, bg_a, txt_col)
  local dl = ImGui.GetWindowDrawList(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local clicked = ImGui.InvisibleButton(ctx, "pmb"..id_suffix, sz, sz)
  local hov = ImGui.IsItemHovered(ctx)
  local act = ImGui.IsItemActive(ctx)
  local fill = act and bg_a or (hov and bg_h or bg)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + sz, y + sz, fill, FUNC.sz(2))
  local tcol = txt_col or C.text
  -- 手繪符號：水平用 CalcTextSize 置中；垂直用幾何中心
  -- draw glyph manually; pm_off_x / pm_off_y 為微調補償字型 baseline，所有 +/- 按鈕共用
  -- pm_off_x / pm_off_y: tweak to compensate font baseline; shared by all +/- buttons
  local PM_OFF_X = 0   -- ← 自行調整（正=往右）-- adjust here (positive = right)
  local PM_OFF_Y = -2   -- ← 自行調整（正=往下）-- adjust here (positive = down)
  local tw, th = ImGui.CalcTextSize(ctx, label, 0, 0)
  local tx = x + (sz - tw) * 0.5 + PM_OFF_X
  local ty = y + (sz - th) * 0.5 + PM_OFF_Y
  ImGui.DrawList_AddText(dl, math.floor(tx + 0.5), math.floor(ty + 0.5), tcol, label)
  return clicked
end

function FUNC.open_edit()
  -- 損壞 cue：禁進 edit panel（避免在無效資料上做編輯）-- broken cue: refuse to open edit
  local sf = FUNC.sel_first()
  if sf and cues[sf] and cues[sf]._broken then return end
  if not popup.edit then popup.edit = true; if FUNC.clear_inner_sels then FUNC.clear_inner_sels() end end
end
function FUNC.toggle_edit()
  popup.edit = not popup.edit
  if not popup.edit then
    FUNC.wf_sel_clear()  -- 關閉edit panel時清除waveform選取 -- clear waveform selection on panel close
  end
  if FUNC.clear_inner_sels then FUNC.clear_inner_sels() end
  prefs.edit_open = popup.edit and 1 or 0; FUNC.save_prefs()  -- 記住開關狀態 -- persist edit panel state
end

-- inline版：下方面板，兩個標籤頁(Basic/Waveform) -- inline edit panel with 2 tabs
function FUNC.draw_edit_panel_inline()
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding(), 3)  -- edit panel用較小圓角 -- smaller rounding for edit panel
  popup.edit_text_active = false
  local valid = FUNC.sel_list()
  if #valid == 0 then
    ImGui.PushFont(ctx, FONT_B, FUNC.sz(26))
    ImGui.PushStyleColor(ctx, ImGui.Col_Text(), FUNC.rgba(130,130,140,200))
    local aw, ah = ImGui.GetContentRegionAvail(ctx)
    local tw,_ = ImGui.CalcTextSize(ctx, "Add a cue to start...", 0, 0)
    ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + (aw - tw) * 0.5)
    ImGui.SetCursorPosY(ctx, ImGui.GetCursorPosY(ctx) + (ah - FUNC.sz(26)) * 0.5)  -- Y軸真正置中 -- true vertical centering
    ImGui.Text(ctx, "Add a cue to start...")
    ImGui.PopStyleColor(ctx, 1); ImGui.PopFont(ctx)
    ImGui.PopStyleVar(ctx, 1)
    return
  end
  popup.edit_list = valid
  local multi = #valid > 1
  local c = cues[valid[1]]

  local function apply(field, val)
    for _, si in ipairs(valid) do cues[si][field] = val end
  end
  local function apply_delta(field, delta, lo, hi)
    for _, si in ipairs(valid) do
      cues[si][field] = FUNC.clamp((cues[si][field] or 0) + delta, lo, hi)
    end
  end
  local dim_txt = FUNC.rgba(100,100,110)
  local dim_bg = FUNC.rgba(35,35,45)
  local function begin_disabled()
    ImGui.PushStyleColor(ctx, ImGui.Col_Text(), dim_txt)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg(), dim_bg)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered(), dim_bg)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive(), dim_bg)
    ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrab(), dim_txt)
    ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrabActive(), dim_txt)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button(), dim_bg)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), dim_bg)
    ImGui.PushStyleColor(ctx, ImGui.Col_CheckMark(), dim_txt)
  end
  local function end_disabled() ImGui.PopStyleColor(ctx, 9) end
  local vdrag = FUNC.vdrag

  local all_play, all_fade, all_midi = true, true, true
  for _, si in ipairs(valid) do
    if cues[si].type ~= "PLAY" then all_play = false end
    if cues[si].type ~= "FADE" then all_fade = false end
    if cues[si].type ~= "MIDI" then all_midi = false end
  end

  -- 標題行（太長hover跑馬燈）+ 眼睛icon -- title row with marquee on hover + eye icon for tab visibility
  local title = multi
    and string.format("Batch Edit (%d cues)", #valid)
    or (c.type == "SPACER"
      and ("Spacer"..(c.notes ~= "" and ("  —  "..c.notes) or ""))
      or ("Q."..c.cue_number.." ["..c.type.."]"..(c.name ~= "" and ("  "..c.name) or "")))
  local ep_title_col = TYPE_COL[c.type] or C.text
  local ep_dl = ImGui.GetWindowDrawList(ctx)
  local ep_tx, ep_ty = ImGui.GetCursorScreenPos(ctx)
  local ep_tw_avail = ImGui.GetContentRegionAvail(ctx)
  local ep_th = FUNC.sz(15)
  local eye_w = FUNC.sz(20)  -- 眼睛按鈕寬度 -- eye button width
  FUNC.draw_marquee(ep_dl, FONT_B, FUNC.sz(13), title, ep_title_col, ep_tx, ep_ty, ep_tw_avail - eye_w, ep_th, "ep_t"..valid[1])
  ImGui.Dummy(ctx, ep_tw_avail - eye_w, ep_th)
  -- 眼睛icon：DrawList畫眼睛形狀 -- eye icon: DrawList eye shape
  ImGui.SameLine(ctx, 0, 0)
  local eye_sx, eye_sy = ImGui.GetCursorScreenPos(ctx)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button(), 0)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), FUNC.rgba(255,255,255,25))
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), FUNC.rgba(255,255,255,40))
  if ImGui.Button(ctx, "##ep_eye", eye_w, ep_th) then
    ImGui.OpenPopup(ctx, "##ep_tab_vis")
  end
  ImGui.PopStyleColor(ctx, 3)
  -- DrawList畫眼睛：橢圓外框+圓形瞳孔 -- draw eye: ellipse outline + circle pupil
  local eye_cx = eye_sx + eye_w * 0.5
  local eye_cy = eye_sy + ep_th * 0.5
  local eye_rx, eye_ry = FUNC.sz(6), FUNC.sz(3.5)
  local eye_hov = ImGui.IsItemHovered(ctx)
  local eye_col = eye_hov and C.text or C.dim
  -- 上下弧線組成眼形 -- upper/lower arcs forming eye shape
  local n = 12
  for i = 0, n - 1 do
    local a1 = math.pi * i / n
    local a2 = math.pi * (i + 1) / n
    -- 上弧 -- upper arc
    ImGui.DrawList_AddLine(ep_dl, eye_cx + math.cos(a1)*eye_rx, eye_cy - math.sin(a1)*eye_ry,
      eye_cx + math.cos(a2)*eye_rx, eye_cy - math.sin(a2)*eye_ry, eye_col, FUNC.sz(1))
    -- 下弧 -- lower arc
    ImGui.DrawList_AddLine(ep_dl, eye_cx + math.cos(a1)*eye_rx, eye_cy + math.sin(a1)*eye_ry,
      eye_cx + math.cos(a2)*eye_rx, eye_cy + math.sin(a2)*eye_ry, eye_col, FUNC.sz(1))
  end
  -- 瞳孔 -- pupil
  ImGui.DrawList_AddCircleFilled(ep_dl, eye_cx, eye_cy, FUNC.sz(2), eye_col)
  if eye_hov then ImGui.SetTooltip(ctx, "Show/Hide Tabs") end
  -- 右鍵flag觸發（上幀設的flag，這幀打開popup） -- right-click flag trigger (set last frame, open this frame)
  if popup._ep_tab_vis_rclick then
    ImGui.OpenPopup(ctx, "##ep_tab_vis")
    popup._ep_tab_vis_rclick = nil
  end
  -- 標籤頁顯隱popup（眼睛icon + 右鍵共用）-- tab visibility popup (shared by eye icon + right-click)
  if ImGui.BeginPopup(ctx, "##ep_tab_vis") then
    ImGui.PushFont(ctx, FONT, FUNC.sz(13))
    local tab_defs = {
      {key="edit_vis_basic",  label="Basic"},
      {key="edit_vis_notes",  label="Notes"},
      {key="edit_vis_wf",     label="Source"},
      {key="edit_vis_route",  label="Route"},
      {key="edit_vis_meter",  label="Master Meter"},
      -- 未來標籤頁在此擴充 -- future tabs added here
      -- {key="edit_vis_metronome", label="Metronome"},
    }
    for _, td in ipairs(tab_defs) do
      local cur = (prefs[td.key] == 1)
      local ch, nv = ImGui.Checkbox(ctx, td.label.."##tabvis", cur)
      if ch then
        prefs[td.key] = nv and 1 or 0
        if td.key == "edit_vis_wf" and not nv then FUNC.wf_sel_clear() end
        FUNC.save_prefs()
      end
    end
    ImGui.PopFont(ctx)
    ImGui.EndPopup(ctx)
  end

  -- SPACER專用面板���只有文字+顏色 -- spacer-only panel: text + color
  local all_spacer = true
  for _, si in ipairs(valid) do if cues[si].type ~= "SPACER" then all_spacer = false; break end end
  if all_spacer then
    ImGui.PushFont(ctx, FONT, FUNC.sz(13))
    -- Name/Text
    ImGui.Text(ctx, "Text"); ImGui.SameLine(ctx, FUNC.sz(40))
    ImGui.SetNextItemWidth(ctx, -FUNC.sz(14))
    local nch, nnv = ImGui.InputText(ctx, "##sp_name", c.notes or "")
    if ImGui.IsItemActive(ctx) then popup.edit_text_active = true end
    if nch then apply("notes", nnv) end
    -- 文字對齊 -- text alignment (left/center/right)
    ImGui.Text(ctx, "Align"); ImGui.SameLine(ctx, FUNC.sz(40))
    local cur_align = c.spacer_align or 1
    local align_labels = {"Left", "Center", "Right"}
    for ai = 0, 2 do
      if ai > 0 then ImGui.SameLine(ctx) end
      if ImGui.RadioButton(ctx, align_labels[ai+1].."##sp_align", cur_align == ai) then
        apply("spacer_align", ai); FUNC.save_cues()
      end
    end
    ImGui.SameLine(ctx, 0, FUNC.sz(12))
    local bch, bv = ImGui.Checkbox(ctx, "Bold##sp_bold", c.spacer_bold or false)
    if bch then apply("spacer_bold", bv); FUNC.save_cues() end
    ImGui.Dummy(ctx, 0, FUNC.sz(6))
    local bsz = FUNC.sz(22)
    -- BG色盤與Text色盤並排 -- BG and Text palettes side by side
    local lbl_w = FUNC.sz(32)
    local pal_w = 12 * bsz + 11 * 2  -- 12 buttons + 11 gaps
    local gap = FUNC.sz(14)
    local text_col_x = lbl_w + pal_w + gap  -- Text欄起始X -- Text column start X
    -- BG label + None button
    ImGui.Text(ctx, "BG"); ImGui.SameLine(ctx, lbl_w)
    if ImGui.SmallButton(ctx, "None##sp_cc") then apply("cue_color", -1); FUNC.save_cues() end
    -- Text label + Auto button（同一行右側） -- Text label on same line, right side
    ImGui.SameLine(ctx, text_col_x)
    ImGui.Text(ctx, "Text"); ImGui.SameLine(ctx, text_col_x + lbl_w)
    if ImGui.SmallButton(ctx, "Auto##sp_tc") then apply("spacer_text_color", -1); FUNC.save_cues() end
    -- 色盤逐行交錯繪製（BG和Text用絕對位置避免互相干擾） -- interleaved palette rows with absolute positioning
    for idx, cc in ipairs(CUE_COLORS) do
      local col_in_row = (idx - 1) % 12
      -- BG button（用絕對位置，避免被右側Text按鈕影響位置） -- absolute pos to avoid Text button offset
      if col_in_row == 0 then
        ImGui.SetCursorPosX(ctx, lbl_w)
      else
        ImGui.SameLine(ctx, lbl_w + col_in_row * (bsz + 2))
      end
      local is_bg = (c.cue_color == cc.val)
      ImGui.PushStyleColor(ctx, ImGui.Col_Button(), FUNC.col2im(cc.val))
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), FUNC.col2im(cc.val, 200))
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), FUNC.col2im(cc.val, 255))
      ImGui.PushStyleColor(ctx, ImGui.Col_Border(), is_bg and C.text or 0)
      ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize(), is_bg and 2 or 0)
      if ImGui.Button(ctx, "##spcc"..idx, bsz, bsz) then apply("cue_color", cc.val); FUNC.save_cues() end
      ImGui.PopStyleVar(ctx, 1); ImGui.PopStyleColor(ctx, 4)
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, cc.name) end
      -- Text button（同一行右側） -- Text button on same row
      ImGui.SameLine(ctx, text_col_x + lbl_w + col_in_row * (bsz + 2))
      local is_tc = (c.spacer_text_color == cc.val)
      ImGui.PushStyleColor(ctx, ImGui.Col_Button(), FUNC.col2im(cc.val))
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), FUNC.col2im(cc.val, 200))
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), FUNC.col2im(cc.val, 255))
      ImGui.PushStyleColor(ctx, ImGui.Col_Border(), is_tc and C.text or 0)
      ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize(), is_tc and 2 or 0)
      if ImGui.Button(ctx, "##sptc"..idx, bsz, bsz) then apply("spacer_text_color", cc.val); FUNC.save_cues() end
      ImGui.PopStyleVar(ctx, 1); ImGui.PopStyleColor(ctx, 4)
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, cc.name) end
    end
    -- Alpha slider（只有spacer可自訂透明度）-- alpha slider (spacer only)
    ImGui.Text(ctx, "Alpha"); ImGui.SameLine(ctx, FUNC.sz(40))
    ImGui.SetNextItemWidth(ctx, FUNC.sz(120))
    local ach, anv = ImGui.SliderInt(ctx, "##sp_alpha", c.spacer_alpha or 255, 0, 255)
    if ach then apply("spacer_alpha", anv); FUNC.save_cues() end
    ImGui.Dummy(ctx, 0, FUNC.sz(2))
    ImGui.PopFont(ctx)
    ImGui.PopStyleVar(ctx, 1) -- pop FrameRounding from line 810
    return  -- spacer不需要其他tab -- spacer needs no other controls
  end

  -- ═══ Horizontal Collapsible Sections ═══ -- 水平可摺疊區塊
  local total_w, total_h = ImGui.GetContentRegionAvail(ctx)
  local header_h = FUNC.sz(18)
  local collapsed_w = FUNC.sz(18)
  local divider_w = FUNC.sz(3)

  -- section order: 1234 = basic,notes,waveform,route (1=basic 2=notes 3=waveform 4=route)
  local SEC_ID = {[1]="basic",[2]="notes",[3]="waveform",[4]="route",[5]="meter"}
  local SEC_NUM = {basic=1, notes=2, waveform=3, route=4, meter=5}
  local N_SECS = 5
  local function decode_order(v)
    v = v or 12345
    local digits = {}
    for i = N_SECS - 1, 0, -1 do digits[#digits+1] = math.floor(v / (10^i)) % 10 end
    -- 驗證：每個digit都是有效SEC_ID且不重複 -- validate: each digit valid + unique
    local seen = {}
    for _, d in ipairs(digits) do
      if not SEC_ID[d] or seen[d] then return {"basic","notes","waveform","route","meter"} end
      seen[d] = true
    end
    local result = {}
    for _, d in ipairs(digits) do result[#result+1] = SEC_ID[d] end
    return result
  end
  local function encode_order(o)
    local v = 0
    for i, sid in ipairs(o) do v = v + SEC_NUM[sid] * (10 ^ (N_SECS - i)) end
    return v
  end

  local sec_order_raw = decode_order(prefs.edit_sec_order)
  -- 過濾掉隱藏的section -- filter out hidden sections
  local sec_vis = {
    basic = (prefs.edit_vis_basic == 1),
    notes = (prefs.edit_vis_notes == 1),
    waveform = (prefs.edit_vis_wf == 1),
    route = (prefs.edit_vis_route == 1),
    meter = (prefs.edit_vis_meter == 1),
  }
  local sec_order = {}
  for _, sid in ipairs(sec_order_raw) do
    if sec_vis[sid] then sec_order[#sec_order + 1] = sid end
  end
  local sec_exp = {
    basic = (prefs.edit_sec_basic == 1),
    notes = (prefs.edit_sec_notes == 1),
    waveform = (prefs.edit_sec_wf == 1),
    route = (prefs.edit_sec_route == 1),
    meter = (prefs.edit_sec_meter == 1),
  }
  local sec_labels = {basic="Basic", notes="Notes", waveform="Source", route="Route", meter="Master"}
  local sec_pref_key = {basic="edit_sec_basic", notes="edit_sec_notes", waveform="edit_sec_wf", route="edit_sec_route", meter="edit_sec_meter"}

  -- 計算寬度：絕對像素寬度，只在總和超過視窗時才擠壓
  -- width calc: absolute pixel widths, only squeeze when sum exceeds window
  local n_exp, n_col = 0, 0
  for _,sid in ipairs(sec_order) do
    if sec_exp[sid] then n_exp=n_exp+1 else n_col=n_col+1 end
  end
  local min_w = {
    basic = math.floor(total_w / 6),
    notes = math.floor(total_w / 10),
    waveform = math.floor(total_w / 2),
  }
  local max_w = {
    basic = math.floor(total_w / 6),
    notes = math.floor(total_w / 7),
    waveform = total_w,
  }
  -- route/meter: 自動寬度，僅在selection或channel數變化時重算
  -- route/meter: auto-width, only recompute on selection or channel count change
  if not _aw_cache then _aw_cache = {sel_id=-1, route_ch=-1, meter_ch=-1, route_w=0, meter_w=0} end
  local aw = _aw_cache
  local cur_sel_id = (valid and #valid > 0) and (cues[valid[1]] and cues[valid[1]].id or -1) or -1
  -- 快速計算route channel數 -- quick route channel count
  local route_ch_count = 0
  if valid and #valid > 0 then
    local c0 = cues[valid[1]]
    if c0 and c0.route_hw then route_ch_count = #c0.route_hw
    elseif c0 and c0.type == "GROUP" then
      local _rch = {}
      for _, ci in ipairs(c0.children or {}) do
        if ci >= 1 and ci <= #cues and cues[ci].type == "PLAY" and cues[ci].route_hw then
          for _, hw in ipairs(cues[ci].route_hw) do if hw and hw.ch and hw.ch >= 0 then _rch[hw.ch] = true end end
        end
      end
      for _ in pairs(_rch) do route_ch_count = route_ch_count + 1 end
    end
  end
  -- 快速計算meter channel數 -- quick meter channel count
  local meter_ch_count = 0
  local _mt_ch_set = {}
  for _, q in ipairs(cues) do
    if q.type == "PLAY" and q.route_hw then
      for _, hw in ipairs(q.route_hw) do
        if hw and hw.ch and hw.ch >= 0 then _mt_ch_set[hw.ch] = true end
      end
    end
  end
  for _ in pairs(_mt_ch_set) do meter_ch_count = meter_ch_count + 1 end
  -- 只在fingerprint變化時重算寬度 -- only recompute width when fingerprint changes
  if cur_sel_id ~= aw.sel_id or route_ch_count ~= aw.route_ch or meter_ch_count ~= aw.meter_ch then
    local fader_slot_est = FUNC.sz(32)
    local auto_scale_w = FUNC.sz(30)
    local auto_pad = FUNC.sz(16)
    aw.route_w = math.max(1, route_ch_count + 1) * fader_slot_est + auto_scale_w + auto_pad
    aw.meter_w = math.max(1, meter_ch_count + 1) * fader_slot_est + auto_scale_w + auto_pad
    aw.sel_id = cur_sel_id; aw.route_ch = route_ch_count; aw.meter_ch = meter_ch_count
  end
  local auto_w_route = aw.route_w
  local auto_w_meter = aw.meter_w
  local auto_w_secs = {route=true, meter=true}

  -- 絕對像素寬度（首次從舊ratio遷移）-- absolute pixel widths (migrate from old ratios on first use)
  local n_dividers = math.max(0, #sec_order - 1)
  local abs_w = {}
  if prefs.edit_sec_wb then
    abs_w = {basic=prefs.edit_sec_wb, notes=prefs.edit_sec_wn, waveform=prefs.edit_sec_ww, route=auto_w_route, meter=auto_w_meter}
  else
    local rat = {basic=prefs.edit_sec_rb or 22, notes=prefs.edit_sec_rn or 18, waveform=prefs.edit_sec_rw or 60}
    local tr = rat.basic + rat.notes + rat.waveform
    if tr <= 0 then tr = 100 end
    local ref = math.max(400, total_w - n_dividers*divider_w)
    abs_w = {
      basic = math.floor(ref * rat.basic / tr),
      notes = math.floor(ref * rat.notes / tr),
      waveform = math.floor(ref * rat.waveform / tr),
      route = auto_w_route,
      meter = auto_w_meter,
    }
    prefs.edit_sec_wb = abs_w.basic; prefs.edit_sec_wn = abs_w.notes; prefs.edit_sec_ww = abs_w.waveform
    FUNC.save_prefs()
  end
  -- route/meter每幀強制更新為自動寬度 -- force auto-width every frame
  abs_w.route = auto_w_route
  abs_w.meter = auto_w_meter

  local avail_w = math.max(0, total_w - n_dividers*divider_w - n_col*collapsed_w)
  local sec_w = {}
  if n_exp > 0 then
    local exp_list = {}
    for _,sid in ipairs(sec_order) do
      if sec_exp[sid] then exp_list[#exp_list+1] = sid end
    end
    local total_used = 0
    for _,sid in ipairs(exp_list) do
      if auto_w_secs[sid] then
        sec_w[sid] = abs_w[sid]  -- 自動寬度，不clamp -- auto-width, no clamp
      else
        sec_w[sid] = FUNC.clamp(abs_w[sid], min_w[sid], max_w[sid])
      end
      total_used = total_used + sec_w[sid]
    end
  end

  -- toggle helper -- 展開/收合切換
  local function toggle_sec(sid)
    prefs[sec_pref_key[sid]] = sec_exp[sid] and 0 or 1
    if sid == "waveform" and sec_exp[sid] then FUNC.wf_sel_clear() end
    FUNC.save_prefs()
  end

  -- header 客製顏色（右鍵叫出色盤）-- per-section header color (right-click palette)
  local function sec_hdr_col(sid, hov)
    local cc = prefs["edit_sec_col_"..sid]
    if cc and cc ~= -1 then
      return FUNC.dim_c(FUNC.col2im(cc, hov and 255 or 200))
    end
    return hov and FUNC.dim_c(FUNC.rgba(45, 110, 100)) or FUNC.dim_c(FUNC.rgba(30, 80, 75))
  end
  local function sec_hdr_rclick(sid)
    if ImGui.IsItemHovered(ctx) and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right()) then
      ImGui.OpenPopup(ctx, "##sec_col_"..sid)
    end
    if ImGui.BeginPopup(ctx, "##sec_col_"..sid) then
      ImGui.PushFont(ctx, FONT, FUNC.sz(12))
      ImGui.Text(ctx, sec_labels[sid].." header color")
      if ImGui.SmallButton(ctx, "Default##sc_"..sid) then
        prefs["edit_sec_col_"..sid] = -1; FUNC.save_prefs()
      end
      local bsz = FUNC.sz(20)
      local cur = prefs["edit_sec_col_"..sid]
      for idx, cc in ipairs(CUE_COLORS) do
        if (idx - 1) % 12 == 0 then
          if idx > 1 then ImGui.Dummy(ctx, 0, 0) end
        else
          ImGui.SameLine(ctx, 0, 2)
        end
        local is_sel = (cur == cc.val)
        ImGui.PushStyleColor(ctx, ImGui.Col_Button(), FUNC.col2im(cc.val))
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), FUNC.col2im(cc.val, 200))
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), FUNC.col2im(cc.val, 255))
        ImGui.PushStyleColor(ctx, ImGui.Col_Border(), is_sel and C.text or 0)
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize(), is_sel and 2 or 0)
        if ImGui.Button(ctx, "##sc"..sid..idx, bsz, bsz) then
          prefs["edit_sec_col_"..sid] = cc.val; FUNC.save_prefs()
        end
        ImGui.PopStyleVar(ctx, 1); ImGui.PopStyleColor(ctx, 4)
        if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, cc.name) end
      end
      ImGui.PopFont(ctx)
      ImGui.EndPopup(ctx)
    end
  end

  -- DragDrop reorder helper（展開+收合共用）-- shared by expanded & collapsed headers
  local sec_screen = {}  -- 記錄各section螢幕位置供guide line用 -- section screen rects for guide line
  local _sec_drop_handled = {}  -- 每幀追蹤哪個section已處理drop -- per-frame drop handling tracker
  local function sec_dragdrop(sid, sx, sy, sw, sh)
    sec_screen[sid] = {x=sx, y=sy, w=sw, h=sh}  -- 存位置 -- store position
    if ImGui.BeginDragDropSource(ctx) then
      ImGui.SetDragDropPayload(ctx, "SEC_REORDER", sid)
      ImGui.Text(ctx, sec_labels[sid])
      _sec_was_drag = true
      ImGui.EndDragDropSource(ctx)
    end
    -- 用滑鼠位置判斷drop target，允許在整個section內容區域放下 -- mouse-based hit test for full section area
    local has_pl, dd_type, dd_pl = ImGui.GetDragDropPayload(ctx)
    if has_pl and dd_type == "SEC_REORDER" and dd_pl and dd_pl ~= "" and dd_pl ~= sid then
      local mx, my = ImGui.GetMousePos(ctx)
      if mx >= sx and mx < sx + sw and my >= sy and my < sy + sh then
        _sec_drop_handled[sid] = true
        local src_si, tgt_si
        for i, s in ipairs(sec_order) do
          if s == dd_pl then src_si = i end
          if s == sid then tgt_si = i end
        end
        -- 偵測滑鼠放開=drop -- detect mouse release as drop
        if src_si and tgt_si and ImGui.IsMouseReleased(ctx, ImGui.MouseButton_Left()) then
          local new_order = {}
          for _,s in ipairs(sec_order_raw) do
            if s ~= dd_pl then new_order[#new_order+1] = s end
          end
          local ins_idx
          for i,s in ipairs(new_order) do
            if s == sid then ins_idx = i; break end
          end
          if ins_idx then
            if src_si < tgt_si then
              table.insert(new_order, ins_idx + 1, dd_pl)
            else
              table.insert(new_order, ins_idx, dd_pl)
            end
          end
          prefs.edit_sec_order = encode_order(new_order)
          FUNC.save_prefs()
        end
        if src_si and tgt_si then
          local fdl = ImGui.GetForegroundDrawList(ctx)
          local line_col = FUNC.rgba(255, 200, 50, 220)
          local guide_x
          if src_si < tgt_si then
            guide_x = sx + sw  -- 來源在左→guide在target右邊 -- source is left → line on right
          else
            guide_x = sx  -- 來源在右→guide在target左邊 -- source is right → line on left
          end
          ImGui.DrawList_AddLine(fdl, guide_x, sy, guide_x, sy + sh, line_col, 3)
        end
      end
    end
    if ImGui.IsItemDeactivated(ctx) and not _sec_was_drag then toggle_sec(sid) end
    -- 不在這裡重置_sec_was_drag，延遲到所有section處理完才重置 -- defer reset to after all sections
  end

  -- ═══ 間距設定（改這裡全局生效）═══ -- spacing config (change here to affect all sections)
  local EDGE_PAD = 8   -- 邊界padding(px) -- edge padding in px
  local ELEM_SPC = 4   -- 元素間距(px) -- element spacing in px

  -- FADE target "from" 解析（需跨section共享）-- fade from values shared across sections
  local fade_from_vol, fade_from_pan, fade_from_pitch = 0, 0, 0
  if not multi and c.type == "FADE" then
    local _, ftc = FUNC.get_target(c)
    fade_from_vol = ftc and ftc.volume or 0
    fade_from_pan = ftc and ftc.pan or 0
    fade_from_pitch = ftc and ftc.pitch or 0
    local ci0 = valid[1]
    -- 掃描前方同target的FADE，取最後一個enabled參數的值 -- scan prior fades on same target
    for i = 1, ci0 - 1 do
      local fc = cues[i]
      if fc.type == "FADE" and fc.target_cue_id == c.target_cue_id then
        if fc.fade_vol_enabled then fade_from_vol = fc.volume end
        if fc.fade_pan_enabled then fade_from_pan = fc.fade_pan or 0 end
        if fc.fade_pitch_enabled then fade_from_pitch = fc.fade_pitch or 0 end
      end
    end
    -- 正在running時用active fade的實際from值 -- use active fade's actual from when running
    if c.state == STATE.RUNNING and ftc and ftc.preview_ids and #ftc.preview_ids > 0 then
      for _, pid in ipairs(ftc.preview_ids) do
        for _, f in ipairs(active_fades) do
          if f.pid == pid then
            fade_from_vol = f.from
            if f.pan_from then fade_from_pan = f.pan_from end
            if f.pitch_from then fade_from_pitch = f.pitch_from end
            break
          end
        end
        break
      end
    end
  end

  -- ═══ 計算內容寬度，水平scrollbar ═══
  -- calculate content width; always reserve scrollbar height
  local content_w = n_dividers * divider_w
  for _, sid in ipairs(sec_order) do
    content_w = content_w + (sec_exp[sid] and (sec_w[sid] or 100) or collapsed_w)
  end
  local needs_hscroll = content_w > total_w
  local sec_area_h = total_h  -- scrollbar隱藏，不預留空間 -- scrollbar hidden, no reserved space
  -- 隱藏scrollbar但允許滾動（滾輪手動處理） -- hide scrollbar but allow scroll (wheel handled manually)
  local hsc_flags = ImGui.WindowFlags_NoScrollbar()
  ImGui.BeginChild(ctx, "##ep_hscroll", total_w, total_h, ImGui.ChildFlags_None(), hsc_flags)
  total_h = sec_area_h  -- 內部使用扣除scrollbar後的高度 -- inner sections use height minus scrollbar
  -- 手動水平滾輪：Shift+滾輪 或 直接滾輪（child內無垂直scroll） -- manual h-scroll: shift+wheel or wheel (no v-scroll in child)
  if ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_ChildWindows()) then
    local wheel = ({ImGui.GetMouseWheel(ctx)})[2] or 0  -- wheel_y
    if wheel ~= 0 then
      local cur_x = ImGui.GetScrollX(ctx)
      local step = FUNC.sz(40)
      ImGui.SetScrollX(ctx, cur_x - wheel * step)
    end
  end

  -- ═══ Section context（傳給拆出去的section函式）═══ -- shared context for split section funcs
  local _ectx = {
    c=c, apply=apply, multi=multi, valid=valid,
    all_play=all_play, all_fade=all_fade, all_midi=all_midi,
    fade_from_vol=fade_from_vol, fade_from_pan=fade_from_pan, fade_from_pitch=fade_from_pitch,
    EDGE_PAD=EDGE_PAD, ELEM_SPC=ELEM_SPC,
    apply_delta=apply_delta, begin_disabled=begin_disabled, end_disabled=end_disabled,
    vdrag=vdrag,
  }

  -- ═══ 繪製水平區塊 ═══ -- render horizontal sections
  for si, sid in ipairs(sec_order) do
    -- divider（第2、3個section前）-- divider before 2nd and 3rd sections
    if si > 1 then
      ImGui.SameLine(ctx, 0, 0)
      local prev_sid = sec_order[si - 1]
      local dv_x, dv_y = ImGui.GetCursorScreenPos(ctx)
      ImGui.InvisibleButton(ctx, "##sec_dv"..si, divider_w, total_h)
      -- route/meter自動寬度，不可拖曳調整 -- auto-width sections are not draggable
      local prev_auto = auto_w_secs[prev_sid]
      local cur_auto = auto_w_secs[sid]
      local can_drag = (sec_exp[prev_sid] or sec_exp[sid]) and not (prev_auto and cur_auto)
      -- 若左邊是auto-width，divider不能調左邊；若右邊收合且左邊是auto也不行
      local dv_hov = ImGui.IsItemHovered(ctx)
      local dv_act = ImGui.IsItemActive(ctx)
      if can_drag and (dv_hov or dv_act) then ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeEW()) end
      if can_drag and dv_act then
        local mouse_dx = ImGui.GetMouseDelta(ctx)
        if mouse_dx ~= 0 then
          if not sec_exp[prev_sid] and not sec_exp[sid] then
            -- 兩邊都收合：no-op
          elseif not sec_exp[prev_sid] then
            -- 左邊收合：no-op
          elseif not sec_exp[sid] then
            -- 右邊收合：調左邊（跳過auto-width）
            if not prev_auto then
              abs_w[prev_sid] = FUNC.clamp(math.floor(abs_w[prev_sid] + mouse_dx), min_w[prev_sid], max_w[prev_sid])
            end
          else
            -- 兩邊都展開：只調左邊（跳過auto-width）
            if not prev_auto then
              abs_w[prev_sid] = FUNC.clamp(math.floor(abs_w[prev_sid] + mouse_dx), min_w[prev_sid], max_w[prev_sid])
            end
          end
          prefs.edit_sec_wb = abs_w.basic; prefs.edit_sec_wn = abs_w.notes; prefs.edit_sec_ww = abs_w.waveform
        end
        sec_drag = si
      elseif sec_drag == si then
        sec_drag = false; FUNC.save_prefs()
      end
      local ddl = ImGui.GetWindowDrawList(ctx)
      local dcol = (can_drag and dv_act) and FUNC.rgba(180,180,210) or (can_drag and dv_hov) and FUNC.rgba(150,150,180) or FUNC.rgba(55,55,70)
      ImGui.DrawList_AddRectFilled(ddl, dv_x, dv_y, dv_x + divider_w, dv_y + total_h, dcol, 1)
      ImGui.SameLine(ctx, 0, 0)
    end

    local sw = sec_exp[sid] and (sec_w[sid] or 100) or collapsed_w
    if ImGui.BeginChild(ctx, "##sec_"..sid, sw, total_h, ImGui.ChildFlags_None(), ImGui.WindowFlags_NoScrollbar() | ImGui.WindowFlags_NoScrollWithMouse()) then
      local sx, sy = ImGui.GetCursorScreenPos(ctx)
      local sdl = ImGui.GetWindowDrawList(ctx)

      if sec_exp[sid] then
        -- ─── 展開header ─── -- expanded header bar
        ImGui.InvisibleButton(ctx, "##sh_"..sid, sw, header_h)
        local sh_hov = ImGui.IsItemHovered(ctx)
        sec_hdr_rclick(sid)
        local hdr_col = sec_hdr_col(sid, sh_hov)
        ImGui.DrawList_AddRectFilled(sdl, sx, sy, sx + sw, sy + header_h, hdr_col, 3)
        ImGui.PushFont(ctx, FONT, FUNC.sz(11))
        local tri = "\xE2\x96\xB6"  -- ▶ 展開狀態 -- expanded state
        local tw_, th_ = ImGui.CalcTextSize(ctx, tri, 0, 0)
        ImGui.DrawList_AddText(sdl, sx + FUNC.sz(6), sy + (header_h - th_) / 2, FUNC.dim_c(C.text), tri)
        local ltw_, lth_ = ImGui.CalcTextSize(ctx, sec_labels[sid], 0, 0)
        ImGui.DrawList_AddText(sdl, sx + FUNC.sz(6) + tw_ + FUNC.sz(4), sy + (header_h - lth_) / 2, FUNC.dim_c(C.text), sec_labels[sid])
        ImGui.PopFont(ctx)
        sec_dragdrop(sid, sx, sy, sw, total_h)

        -- ─── Section content ───
        local cw_s, ch_s = ImGui.GetContentRegionAvail(ctx)

        -- ═══════════════════════════════════════════════════════
        if sid == "basic" then
          FUNC.draw_edit_section_basic(_ectx, cw_s, ch_s)
        elseif sid == "notes" then
          FUNC.draw_edit_section_note(c, apply, multi, valid)

        -- ═══════════════════════════════════════════════════════
        elseif sid == "waveform" then
          FUNC.draw_edit_section_waveform(_ectx)
        elseif sid == "route" then
          FUNC.draw_edit_section_route(c, apply, multi)
        elseif sid == "meter" then
          FUNC.draw_edit_section_meter()

        end -- sid == "basic" / "notes" / "waveform" / "route" / "meter"

      else
        -- ─── 收合窄條 ─── -- collapsed strip
        ImGui.InvisibleButton(ctx, "##sh_"..sid, collapsed_w, total_h)
        local sh_hov = ImGui.IsItemHovered(ctx)
        sec_hdr_rclick(sid)
        local hdr_col = sec_hdr_col(sid, sh_hov)
        ImGui.DrawList_AddRectFilled(sdl, sx, sy, sx + collapsed_w, sy + total_h, hdr_col, 3)
        ImGui.PushFont(ctx, FONT, FUNC.sz(11))
        local tri = "\xE2\x96\xBC"  -- ▼ 收合狀態 -- collapsed state
        local tw_, th_ = ImGui.CalcTextSize(ctx, tri, 0, 0)
        ImGui.DrawList_AddText(sdl, sx + (collapsed_w - tw_) / 2, sy + FUNC.sz(4), FUNC.dim_c(C.text), tri)
        -- 垂直文字 -- vertical text
        local lbl = sec_labels[sid]
        local vy = sy + FUNC.sz(4) + th_ + FUNC.sz(6)
        for ci = 1, math.min(#lbl, 10) do
          local ch_c = lbl:sub(ci, ci)
          local chtw, chth = ImGui.CalcTextSize(ctx, ch_c, 0, 0)
          ImGui.DrawList_AddText(sdl, sx + (collapsed_w - chtw) / 2, vy, FUNC.dim_c(C.text), ch_c)
          vy = vy + chth + FUNC.sz(1)
        end
        ImGui.PopFont(ctx)
        sec_dragdrop(sid, sx, sy, collapsed_w, total_h)
      end -- sec_exp[sid]

      ImGui.Dummy(ctx, 0, 0)  -- 確保SetCursorScreenPos後的邊界正確 -- finalize bounds after SetCursorScreenPos
      ImGui.EndChild(ctx)
    end -- BeginChild
  end -- for si, sid
  -- 尾端divider：最後一個section的右邊界 -- trailing divider: right edge of last section
  do
    local last_sid = sec_order[#sec_order]
    if last_sid then
      ImGui.SameLine(ctx, 0, 0)
      local dv_x, dv_y = ImGui.GetCursorScreenPos(ctx)
      ImGui.InvisibleButton(ctx, "##sec_dv_tail", divider_w, total_h)
      local dv_hov = ImGui.IsItemHovered(ctx)
      local dv_act = ImGui.IsItemActive(ctx)
      local can_resize_tail = sec_exp[last_sid] and not auto_w_secs[last_sid]
      if can_resize_tail and (dv_hov or dv_act) then ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeEW()) end
      if can_resize_tail and dv_act then
        local mouse_dx = ImGui.GetMouseDelta(ctx)
        if mouse_dx ~= 0 then
          local others = 0
          for _,s in ipairs(sec_order) do
            if sec_exp[s] and s ~= last_sid then others = others + abs_w[s] end
          end
          local max_w = avail_w - others
          abs_w[last_sid] = FUNC.clamp(math.floor(abs_w[last_sid] + mouse_dx), min_w[last_sid], math.max(min_w[last_sid], max_w))
          prefs.edit_sec_wb = abs_w.basic; prefs.edit_sec_wn = abs_w.notes; prefs.edit_sec_ww = abs_w.waveform
        end
        sec_drag = 99
      elseif sec_drag == 99 then
        sec_drag = false; FUNC.save_prefs()
      end
      local ddl = ImGui.GetWindowDrawList(ctx)
      local dcol = (can_resize_tail and dv_act) and FUNC.rgba(180,180,210) or (can_resize_tail and dv_hov) and FUNC.rgba(150,150,180) or FUNC.rgba(55,55,70)
      ImGui.DrawList_AddRectFilled(ddl, dv_x, dv_y, dv_x + divider_w, dv_y + total_h, dcol, 1)
    end
  end
  -- 所有section處理完後才重置drag flag，避免source提前清除導致target誤toggle
  -- reset after all sections processed to prevent premature clear causing target toggle
  if _sec_was_drag and not ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left()) then
    _sec_was_drag = false
  end
  -- 確保ImGui知道content寬度（溢出時啟用scrollbar） -- ensure ImGui knows content width for scrollbar
  if needs_hscroll then
    ImGui.SameLine(ctx, 0, 0)
    ImGui.Dummy(ctx, 1, 1)  -- 尾端dummy讓content_w生效 -- trailing dummy to register full width
  end
  -- A6: 點擊任何 section 空白處清除 inner highlight（在 ##ep_hscroll 內部判斷）
  -- A6: blank-area click in any section clears inner highlights
  if ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_ChildWindows()) and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left()) and not ImGui.IsAnyItemActive(ctx) then
    FUNC.clear_inner_sels()
  end
  -- A6: 追蹤 edit panel focus，離焦時清除（例：點 ui_table 同一 cue 不變 selection）
  -- A6: track focus; clear when focus leaves edit panel
  _ep_focused_now = ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_ChildWindows())
  ImGui.EndChild(ctx)  -- ##ep_hscroll 水平捲動容器 -- h-scroll container
  -- edit panel空白處右鍵：設flag下幀開popup（同眼睛icon） -- right-click on empty area: flag to open popup next frame
  if ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_ChildWindows()) and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right()) and not ImGui.IsAnyItemHovered(ctx) then
    popup._ep_tab_vis_rclick = true
  end
  ImGui.PopStyleVar(ctx, 1)  -- FrameRounding
end

---------------------------------------------------------------------
-- MIDI Message-mode 表格（給 Source tab 右欄使用）
-- Device dropdown 在左欄上方（取代 Trim In/Out）；FX 區塊維持與 Sequence 共用
-- 表格欄位：Type / Event / Value / Msg / Ch；不適用欄位灰掉「—」
---------------------------------------------------------------------
function FUNC.draw_midi_message_table(c, apply)
  local sz = FUNC.sz
  local row_gap = sz(4)

  -- ─── +/- buttons + Press vdrag ───（樣式同 Route tab）
  c.midi_msgs = c.midi_msgs or {}
  c._midi_msg_sel = c._midi_msg_sel or {}
  local sel = c._midi_msg_sel
  local btn_sz = ImGui.GetFrameHeight(ctx)

  if FUNC.draw_pm_btn("##msrc_add", "+", btn_sz, FUNC.rgba(50,80,60), FUNC.rgba(60,110,80), FUNC.rgba(70,140,100)) then
    FUNC.push_undo()
    c.midi_msgs[#c.midi_msgs+1] = {type="note", event=60, value=100, msg="on", ch_mask=1, press_ms=100}
  end

  ImGui.SameLine(ctx, 0, sz(4))
  local has_sel = false
  for _, v in pairs(sel) do if v then has_sel = true; break end end
  local del_col = has_sel and C.text or FUNC.rgba(80,80,80)
  if FUNC.draw_pm_btn("##msrc_del", "-", btn_sz, FUNC.rgba(100,50,50), FUNC.rgba(140,60,60), FUNC.rgba(170,70,70), del_col) and has_sel then
    FUNC.push_undo()
    local to_del = {}
    for idx, v in pairs(sel) do if v then to_del[#to_del+1] = idx end end
    table.sort(to_del, function(a,b) return a > b end)
    for _, di in ipairs(to_del) do
      if di <= #c.midi_msgs then table.remove(c.midi_msgs, di) end
    end
    c._midi_msg_sel = {}; sel = c._midi_msg_sel
  end

  ImGui.Dummy(ctx, 0, row_gap)

  -- ─── Message table ───
  -- 欄位：# | Type | Event | Value | Msg(+press_ms 內嵌) | Ch (All + 1..16 checkbox)
  -- 舊資料 m.ch (單一) → 自動轉 ch_mask -- legacy single-ch migration
  local TYPES = {"note", "cc", "pc"}
  local MSGS = {"on", "off", "press"}
  for _, m in ipairs(c.midi_msgs) do
    if m.ch_mask == nil then
      local ch_n = tonumber(m.ch) or 1
      m.ch_mask = 1 << math.max(0, math.min(15, ch_n - 1))
      m.ch = nil
    end
    if m.press_ms == nil then m.press_ms = 100 end
  end
  local tflags = ImGui.TableFlags_Borders() | ImGui.TableFlags_RowBg() | ImGui.TableFlags_SizingStretchProp()
  c._midi_msg_anchor = c._midi_msg_anchor or 1
  local sel_rects = {}
  local row_ys = {}  -- ri -> {y1, y2} 供「點 row 空白處選取」使用 -- row Y ranges for click-to-select on row gaps
  -- 置中 helper：水平把寬度 w 的元件置中於目前 cell -- center widget of width w in current table cell
  local function cell_center_x(w)
    local cw = ImGui.GetContentRegionAvail(ctx)
    local off = math.max(0, (cw - w) * 0.5)
    if off > 0 then ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + off) end
  end
  -- 文字置中（單行）-- center single-line text in current cell
  local function cell_text_center(s, col)
    ImGui.AlignTextToFramePadding(ctx)
    local tw = ImGui.CalcTextSize(ctx, s)
    cell_center_x(tw)
    if col then ImGui.PushStyleColor(ctx, ImGui.Col_Text(), col); ImGui.Text(ctx, s); ImGui.PopStyleColor(ctx, 1)
    else ImGui.Text(ctx, s) end
  end
  -- Msg 欄寬度：有任一列 press 才放寬，否則維持窄版 -- widen Msg column only if any row uses press
  local any_press = false
  for _, m in ipairs(c.midi_msgs) do if m.msg == "press" and m.type == "note" then any_press = true; break end end
  local msg_col_w = any_press and sz(160) or sz(80)
  if ImGui.BeginTable(ctx, "##msrc_tbl", 6, tflags) then
    local hdrs = {"#", "Type", "Event", "Value", "Message", "Channel"}
    ImGui.TableSetupColumn(ctx, hdrs[1], ImGui.TableColumnFlags_WidthFixed(), sz(28))
    ImGui.TableSetupColumn(ctx, hdrs[2], ImGui.TableColumnFlags_WidthFixed(), sz(72))
    ImGui.TableSetupColumn(ctx, hdrs[3], ImGui.TableColumnFlags_WidthFixed(), sz(64))
    ImGui.TableSetupColumn(ctx, hdrs[4], ImGui.TableColumnFlags_WidthFixed(), sz(64))
    ImGui.TableSetupColumn(ctx, hdrs[5], ImGui.TableColumnFlags_WidthFixed(), msg_col_w)
    ImGui.TableSetupColumn(ctx, hdrs[6], ImGui.TableColumnFlags_WidthStretch(), 1)
    -- 自訂 header：cols 1..5 置中，Channel 欄維持預設靠左
    ImGui.TableNextRow(ctx, ImGui.TableRowFlags_Headers())
    ImGui.PushStyleColor(ctx, ImGui.Col_Text(), 0)
    local _hdr_dl = ImGui.GetWindowDrawList(ctx)
    for hi = 0, 5 do
      ImGui.TableSetColumnIndex(ctx, hi)
      ImGui.TableHeader(ctx, hdrs[hi+1])
      local x1, y1 = ImGui.GetItemRectMin(ctx)
      local x2, y2 = ImGui.GetItemRectMax(ctx)
      local tw, th = ImGui.CalcTextSize(ctx, hdrs[hi+1], 0, 0)
      local tx
      if hi < 5 then tx = x1 + math.max(0, (x2 - x1 - tw) * 0.5)
      else           tx = x1 + sz(4) end
      ImGui.DrawList_AddText(_hdr_dl, tx, y1 + (y2 - y1 - th) * 0.5, C.column_title or FUNC.rgba(220,220,220), hdrs[hi+1])
    end
    ImGui.PopStyleColor(ctx, 1)

    local _msg_row_clicked_this_frame = false
    for ri, m in ipairs(c.midi_msgs) do
      ImGui.TableNextRow(ctx)

      ImGui.TableNextColumn(ctx)
      local is_sel = sel[ri] == true
      -- 在 Selectable 之前先抓 # 欄真正的 X 範圍，因 SpanAllColumns 後 GetItemRect 會涵蓋整列
      -- capture # column X before SpanAllColumns Selectable expands the rect to whole row
      local _hash_x1, _hash_y_pre = ImGui.GetCursorScreenPos(ctx)
      local _hash_w = ImGui.GetContentRegionAvail(ctx)
      -- 整列可點選：SpanAllColumns 讓 Selectable 涵蓋整列，AllowOverlap 讓後續 combo/vdrag 仍優先收 click
      -- span all columns so blank gaps in any column also select; AllowOverlap keeps widgets clickable
      local _sel_flags = ImGui.SelectableFlags_SpanAllColumns() | ImGui.SelectableFlags_AllowOverlap()
      if ImGui.Selectable(ctx, "##msel_"..ri, is_sel, _sel_flags) then
        _msg_row_clicked_this_frame = true
        local cmd = ImGui.IsKeyDown(ctx, ImGui.Mod_Super()) or ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl())
        local shift = ImGui.IsKeyDown(ctx, ImGui.Mod_Shift())
        if shift then
          local a, b = c._midi_msg_anchor, ri
          if a > b then a, b = b, a end
          for k = a, b do sel[k] = true end
        elseif cmd then
          sel[ri] = (not is_sel) and true or nil
          c._midi_msg_anchor = ri
        else
          -- 再點同一列(已是唯一選取) → 取消選取 -- click same sole-selected row again → deselect
          local only_this = is_sel
          if only_this then
            for k in pairs(sel) do if k ~= ri then only_this = false; break end end
          end
          for k in pairs(sel) do sel[k] = nil end
          if not only_this then
            sel[ri] = true
            c._midi_msg_anchor = ri
          end
        end
      end
      -- 取 Selectable 的 rect（整列）→ 黃框 Y 範圍；數字置中改用 # 欄真正 X 範圍
      local _, _iy1 = ImGui.GetItemRectMin(ctx)
      local _, _iy2 = ImGui.GetItemRectMax(ctx)
      do
        local ndl = ImGui.GetWindowDrawList(ctx)
        local nstr = tostring(ri)
        local ntw, nth = ImGui.CalcTextSize(ctx, nstr)
        ImGui.DrawList_AddText(ndl, _hash_x1 + (_hash_w - ntw) * 0.5, _iy1 + (_iy2 - _iy1 - nth) * 0.5, C.text, nstr)
      end
      if sel[ri] then sel_rects[#sel_rects+1] = {_iy1, _iy2} end
      row_ys[ri] = {_iy1, _iy2}

      -- Type (centered combo)
      ImGui.TableNextColumn(ctx)
      local type_w = sz(60)
      cell_center_x(type_w)
      ImGui.SetNextItemWidth(ctx, type_w)
      if ImGui.BeginCombo(ctx, "##mt_"..ri, m.type or "note") then
        for _, t in ipairs(TYPES) do
          if ImGui.Selectable(ctx, t, t == m.type) then FUNC.push_undo(); m.type = t end
        end
        ImGui.EndCombo(ctx)
      end

      local greyed_val = (m.type == "pc")
      local greyed_msg = (m.type ~= "note")

      -- Event (centered vdrag)；type=note 時顯示 "C4 60" 樣式 -- show note name when type=note
      ImGui.TableNextColumn(ctx)
      local ev_w = sz(56)
      cell_center_x(ev_w)
      local ev_fmt
      if m.type == "note" then
        local NN = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}
        ev_fmt = function(v)
          local n = math.floor((tonumber(v) or 0) + 0.5)
          n = FUNC.clamp(n, 0, 127)
          return string.format("%3d (%-2s%2d)", n, NN[(n % 12) + 1], math.floor(n / 12) - 1)
        end
      else
        ev_fmt = "%.0f"
      end
      ImGui.PushFont(ctx, FONT_MONO, ImGui.GetFontSize(ctx))
      local ev_ch, ev_nv = FUNC.vdrag("##me_"..ri, tonumber(m.event) or 0, 1/8, 0, 127, ev_fmt, nil, ev_w)
      ImGui.PopFont(ctx)
      if ev_ch then FUNC.push_undo(); m.event = FUNC.clamp(math.floor(ev_nv + 0.5), 0, 127) end

      -- Value (centered vdrag 或 灰 —)
      ImGui.TableNextColumn(ctx)
      if greyed_val then
        cell_text_center("—", C.dim)
      else
        local va_w = sz(48)
        cell_center_x(va_w)
        ImGui.PushFont(ctx, FONT_MONO, ImGui.GetFontSize(ctx))
        local va_ch, va_nv = FUNC.vdrag("##mv_"..ri, tonumber(m.value) or 0, 1/8, 0, 127, "%.0f", nil, va_w)
        ImGui.PopFont(ctx)
        if va_ch then FUNC.push_undo(); m.value = FUNC.clamp(math.floor(va_nv + 0.5), 0, 127) end
      end

      -- Message (centered combo + press_ms 內嵌)
      ImGui.TableNextColumn(ctx)
      if greyed_msg then
        cell_text_center("—", C.dim)
      else
        local is_press = (m.msg == "press")
        local combo_w = sz(60)
        local press_w = sz(72)
        local total_w = is_press and (combo_w + sz(4) + press_w) or combo_w
        cell_center_x(total_w)
        ImGui.SetNextItemWidth(ctx, combo_w)
        if ImGui.BeginCombo(ctx, "##mm_"..ri, m.msg or "on") then
          for _, mv in ipairs(MSGS) do
            if ImGui.Selectable(ctx, mv, mv == m.msg) then FUNC.push_undo(); m.msg = mv end
          end
          ImGui.EndCombo(ctx)
        end
        if is_press then
          ImGui.SameLine(ctx, 0, sz(4))
          local pm_ch, pm_nv = FUNC.vdrag("##mpms_"..ri, tonumber(m.press_ms) or 100, 1, 1, 5000, "%.0f ms", nil, press_w)
          if pm_ch then FUNC.push_undo(); m.press_ms = FUNC.clamp(math.floor(pm_nv + 0.5), 1, 5000) end
        end
      end

      -- Ch: All + 1..16 paint-drag checkboxes
      -- All cell: toggle full ↔ 上次 partial
      -- 1..16:   click+drag 範圍塗色（從起點當前狀態反轉）
      ImGui.TableNextColumn(ctx)

      local FULL_MASK = 0xFFFF
      local row_h = ImGui.GetFrameHeight(ctx)
      local sx, sy = ImGui.GetCursorScreenPos(ctx)

      -- A. layout: cells[0]=All, cells[1..16]=ch1..16
      local cells = {}
      do
        local cx = sx
        local lbls = {[0]="All"}
        for k=1,16 do lbls[k] = tostring(k) end
        for k=0,16 do
          local tw,_ = ImGui.CalcTextSize(ctx, lbls[k])
          local cw = tw + sz(8)
          cells[k] = {x1=cx, x2=cx+cw, w=cw, lbl=lbls[k], tw=tw}
          cx = cx + cw
        end
      end

      local function hit(mx, my, k)
        return my>=sy and my<=sy+row_h and mx>=cells[k].x1 and mx<=cells[k].x2
      end

      -- B. input
      local drag = c._midi_ch_drag

      -- B1. drag in progress → paint range [lo..hi] from snap
      if drag and drag.row == ri then
        local mx,_ = ImGui.GetMousePos(ctx)
        local cur_idx
        if mx <= cells[1].x1 then       cur_idx = 1
        elseif mx >= cells[16].x2 then  cur_idx = 16
        else
          cur_idx = drag.start_idx
          for k=1,16 do
            if mx>=cells[k].x1 and mx<=cells[k].x2 then cur_idx = k; break end
          end
        end
        local lo = math.min(drag.start_idx, cur_idx)
        local hi = math.max(drag.start_idx, cur_idx)
        local new_mask = drag.snap_mask
        for k=lo,hi do
          local bit = 1<<(k-1)
          if drag.paint_to then new_mask = new_mask | bit
          else                  new_mask = new_mask & (~bit) end
        end
        m.ch_mask = new_mask
      end

      -- B2. release → 清 drag（不覆蓋 last_mask；last_mask 只由 All click 維護）
      if drag and not ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left()) then
        c._midi_ch_drag = nil
        drag = nil
      end

      -- B3. mouse-down dispatch
      if (not drag) and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left()) then
        local mx, my = ImGui.GetMousePos(ctx)
        local mask = tonumber(m.ch_mask) or 1

        if hit(mx, my, 0) then
          -- All cell: toggle
          FUNC.push_undo()
          if mask == FULL_MASK then
            -- 已全選 → 回上次 partial（無紀錄則退回 ch1）
            m.ch_mask = c._midi_last_mask or 1
          else
            -- 未全選 → 記住當前並全選
            c._midi_last_mask = mask
            m.ch_mask = FULL_MASK
          end
        else
          -- 1..16: start drag
          for k=1,16 do
            if hit(mx, my, k) then
              FUNC.push_undo()
              local start_on = (mask & (1<<(k-1))) ~= 0
              c._midi_ch_drag = {
                row = ri,
                start_idx = k,
                snap_mask = mask,
                paint_to = not start_on,
              }
              break
            end
          end
        end
      end

      -- C. render（use_all 為衍生狀態：mask 滿時 All 也亮）
      local mask = tonumber(m.ch_mask) or 1
      m.use_all = (mask == FULL_MASK)

      local mdl = ImGui.GetWindowDrawList(ctx)
      for k=0,16 do
        local cc = cells[k]
        local on = (k==0) and m.use_all or ((mask & (1<<(k-1))) ~= 0)
        local hov = ImGui.IsMouseHoveringRect(ctx, cc.x1, sy, cc.x2, sy+row_h)

        if hov then
          ImGui.DrawList_AddRectFilled(mdl, cc.x1, sy+sz(2), cc.x2, sy+row_h-sz(2),
            FUNC.rgba(60,60,70,90), sz(3))
        end

        local _,th = ImGui.CalcTextSize(ctx, cc.lbl)
        local tx = cc.x1 + (cc.w - cc.tw)*0.5
        local ty = sy + (row_h - th)*0.5

        local txt_col
        if on then txt_col = FUNC.rgba(255,220,70)
        else       txt_col = FUNC.rgba(110,110,120) end
        if hov then txt_col = FUNC.rgba(255,245,180) end

        ImGui.DrawList_AddText(mdl, tx, ty, txt_col, cc.lbl)
      end

      -- 表格列高保留 -- reserve cell vertical space
      ImGui.Dummy(ctx, cells[16].x2 - sx, row_h)

      -- hover 3 秒提示
      do
        local hov_all = ImGui.IsMouseHoveringRect(ctx, sx, sy, cells[16].x2, sy+row_h)
        if hov_all and not c._midi_ch_drag then
          local now = reaper.time_precise()
          if (not c._midi_ch_hover) or c._midi_ch_hover.ri ~= ri then
            c._midi_ch_hover = {ri=ri, t0=now}
          elseif now - c._midi_ch_hover.t0 >= 1.0 then
            ImGui.BeginTooltip(ctx)
            ImGui.Text(ctx, "All: toggle full / last partial selection")
            ImGui.Text(ctx, "1..16: click to toggle; drag to paint multiple")
            ImGui.EndTooltip(ctx)
          end
        elseif c._midi_ch_hover and c._midi_ch_hover.ri == ri then
          c._midi_ch_hover = nil
        end
      end
    end
    ImGui.EndTable(ctx)
    -- Source 面板任何空白點擊：命中 row 空白處則選取該列；其他空白（含表格外、表格末端下方）→ 清空
    -- any blank click inside the source child window:
    --   on a row → select that row (with shift/cmd modifiers)
    --   anywhere else (table itself, source bg, gaps) → clear
    local _tx1, _ty1 = ImGui.GetItemRectMin(ctx)
    local _tx2, _ty2 = ImGui.GetItemRectMax(ctx)
    if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left()) and not ImGui.IsAnyItemActive(ctx) and ImGui.IsWindowHovered(ctx) and not _msg_row_clicked_this_frame then
      local _mx, _my = ImGui.GetMousePos(ctx)
      local in_table = (_mx >= _tx1 and _mx <= _tx2 and _my >= _ty1 and _my <= _ty2)
      local hit_ri = nil
      if in_table then
        for ri2, yy in pairs(row_ys) do
          if _my >= yy[1] and _my <= yy[2] then hit_ri = ri2; break end
        end
      end
      if hit_ri then
          local cmd = ImGui.IsKeyDown(ctx, ImGui.Mod_Super()) or ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl())
          local shift = ImGui.IsKeyDown(ctx, ImGui.Mod_Shift())
          local was_sel = sel[hit_ri] == true
          if shift then
            local a, b = c._midi_msg_anchor or hit_ri, hit_ri
            if a > b then a, b = b, a end
            for k = a, b do sel[k] = true end
          elseif cmd then
            sel[hit_ri] = (not was_sel) and true or nil
            c._midi_msg_anchor = hit_ri
          else
            -- 再點同一列(已是唯一選取) → 取消 -- click same sole-selected row again → deselect
            local only_this = was_sel
            if only_this then
              for k in pairs(sel) do if k ~= hit_ri then only_this = false; break end end
            end
            for k in pairs(sel) do sel[k] = nil end
            if not only_this then
              sel[hit_ri] = true
              c._midi_msg_anchor = hit_ri
            end
          end
          -- 重算 sel_rects -- recompute outline rects for current frame
          sel_rects = {}
          for ri2, yy in pairs(row_ys) do
            if sel[ri2] then sel_rects[#sel_rects+1] = {yy[1], yy[2]} end
          end
      else
        c._midi_msg_sel = {}
        sel = c._midi_msg_sel
        sel_rects = {}
      end
    end
    -- 選取黃框（同 Route 樣式）— 用 table 的 X 範圍橫跨整列
    -- selected row outline matching Route style; X from table rect
    if #sel_rects > 0 then
      local sdl = ImGui.GetWindowDrawList(ctx)
      local sel_col = FUNC.rgba(255, 200, 80)
      for _, r in ipairs(sel_rects) do
        ImGui.DrawList_AddRect(sdl, _tx1 + 1, r[1], _tx2 - 1, r[2], sel_col, 3, 0, FUNC.sz(2.5))
      end
    end
  end
end
