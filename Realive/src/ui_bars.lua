-- ==========================================================================
-- ui_bars.lua — Progress Bar, Toolbar, Bottom Bar
-- ==========================================================================

---------------------------------------------------------------------
-- 13.5 CUSTOM PROGRESS BAR
---------------------------------------------------------------------
function FUNC.draw_pbar(dl, x, y, w, h, frac, bar_col, text, middle)
  -- v2：不畫整條底槽；進度 = 淡色填底 + 底部 2px 實線 -- v2: soft tint + 2px bottom line instead of a solid bar
  if frac>0 then
    local fx = x + math.max(1, w * FUNC.clamp(frac, 0, 1))
    local solid = (bar_col & 0xFFFFFF00) | 0xFF
    ImGui.DrawList_AddRectFilled(dl, x, y, fx, y+h, FUNC.dim_c((bar_col & 0xFFFFFF00) | 46), FUNC.rad("s"))
    ImGui.DrawList_AddRectFilled(dl, x, y+h-FUNC.sz(2), fx, y+h, FUNC.dim_c(solid), FUNC.sz(1))
  end
  if text then
    ImGui.PushFont(ctx, FONT_MONO, FUNC.sz(13))
    local tw,th = ImGui.CalcTextSize(ctx, text, 0, 0)
    ImGui.PopFont(ctx)
    local tx = (middle and (x + (w - tw)/2 )) or (x + w - tw - 4)
    local ty = y + math.floor((h - th) * 0.5)
    ImGui.DrawList_AddTextEx(dl, FONT_MONO, FUNC.sz(13), tx, ty, FUNC.dim_c(C.text), text)
  end
end

---------------------------------------------------------------------
-- 14. TOOLBAR
---------------------------------------------------------------------
function FUNC.draw_toolbar()
  local tb_h = FUNC.sz(46)
  ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg(), C.chrome)
  if ImGui.BeginChild(ctx, "toolbar", -1, tb_h, ImGui.ChildFlags_None()) then
    local bh = FUNC.sz(30)
    local gx = FUNC.sz(10)  -- 群組間距 -- gap between groups
    do  -- 工具列下緣細線 -- hairline under the toolbar
      local wx, wy = ImGui.GetWindowPos(ctx)
      ImGui.DrawList_AddLine(ImGui.GetWindowDrawList(ctx), wx, wy + tb_h - 1, wx + ImGui.GetWindowWidth(ctx), wy + tb_h - 1, C.line, 1)
    end
    ImGui.SetCursorPos(ctx, FUNC.sz(8), math.floor((tb_h - bh) / 2))
    ImGui.PushFont(ctx, FONT, FUNC.sz(14))
    local after = FUNC.sel_first(); if after < 1 then after = #cues end

    -- ① 新增：Audio / MIDI -- add cues
    local hit = FUNC.ui_seg({
      {id="##tb_audio", label="Audio", icon="play", tip="Add PLAY cue"},
      {id="##tb_midi",  label="MIDI",  icon="note", tip="Add MIDI cue"},
    }, {h=bh})
    if hit == 1 then ImGui.OpenPopup(ctx, "audio_add_menu") elseif hit == 2 then ImGui.OpenPopup(ctx, "midi_add_menu") end
    if ImGui.BeginPopup(ctx, "audio_add_menu") then
      if ImGui.Selectable(ctx, "Add from selected track") then FUNC.add_cue("PLAY", after) end
      if ImGui.Selectable(ctx, "Add files to REAPER") then FUNC.file_add_play(after) end
      ImGui.EndPopup(ctx)
    end
    if ImGui.BeginPopup(ctx, "midi_add_menu") then
      if ImGui.Selectable(ctx, "Insert new track") then FUNC.add_cue("MIDI", after, "new") end
      if ImGui.Selectable(ctx, "Add from selected track") then FUNC.add_cue("MIDI", after, "selected") end
      ImGui.EndPopup(ctx)
    end

    -- ② 控制型 cue：Stop / Pause / Fade -- control cues
    ImGui.SameLine(ctx, 0, gx)
    hit = FUNC.ui_seg({
      {id="##tb_stop",  label="Stop",  icon="stop",  tip="Add STOP cue"},
      {id="##tb_pause", label="Pause", icon="pause", tip="Add PAUSE cue"},
      {id="##tb_fade",  label="Fade",  icon="fade",  tip="Add FADE cue"},
    }, {h=bh})
    if hit == 1 then FUNC.add_cue("STOP", after) elseif hit == 2 then FUNC.add_cue("PAUSE", after) elseif hit == 3 then FUNC.add_cue("FADE", after) end

    -- ③ 群組 -- grouping
    local sc2 = FUNC.sel_cnt()
    local grp_too_deep = sc2 >= 2 and FUNC.group_sel_would_exceed()
    local grp_disabled = sc2 < 2 or grp_too_deep
    local sf_ug = FUNC.sel_first()
    local has_grp = sf_ug >= 1 and sf_ug <= #cues and cues[sf_ug].type == "GROUP"
    ImGui.SameLine(ctx, 0, gx)
    hit = FUNC.ui_seg({
      -- too-deep 時按下會跳警告，所以不設 disabled -- stays clickable when too deep so it can warn
      {id="##tb_grp",   label="Group",   icon="group",   disabled=(sc2 < 2), tip=(sc2 < 2) and "Select 2+ cues" or nil},
      {id="##tb_ungrp", label="Ungroup", icon="ungroup", disabled=not has_grp, tip=(not has_grp) and "Select a GROUP cue" or nil},
    }, {h=bh})
    if hit == 1 then
      if grp_too_deep then FUNC.warn_max_depth() elseif not grp_disabled then FUNC.group_sel() end
    elseif hit == 2 and has_grp then FUNC.ungroup_cue(sf_ug) end

    -- 分隔線 -- divider
    ImGui.SameLine(ctx, 0, gx)
    do
      local dx, dy = ImGui.GetCursorScreenPos(ctx)
      ImGui.DrawList_AddLine(ImGui.GetWindowDrawList(ctx), dx, dy + FUNC.sz(5), dx, dy + bh - FUNC.sz(5), C.line2, 1)
      ImGui.Dummy(ctx, 1, bh)
    end

    -- ④ 檔案 -- file
    ImGui.SameLine(ctx, 0, gx)
    hit = FUNC.ui_seg({
      {id="##tb_save", label="Save"},
      {id="##tb_load", label="Load"},
      {id="##tb_ren",  label="Re#", tip="Reset cue numbers (1, 2, 3...)"},
    }, {h=bh})
    if hit == 1 then popup.save = true
    elseif hit == 2 then popup.load = true
    elseif hit == 3 then FUNC.push_undo(); FUNC.renumber(); FUNC.save_cues() end
    local bw = FUNC.sz(80)  -- master 寬度上限參考 -- master width reference

    -- Right: Undo/Redo + Master + Settings — 先算 master_w 與右側 fixed 寬，剩餘空間做為深度警告置中區
    -- compute right-side widths first; remaining gap reserved for depth warning (centered)
    ImGui.SameLine(ctx)
    local set_w = bh
    local child_w = ImGui.GetWindowWidth(ctx)
    local rest,_ = ImGui.GetContentRegionAvail(ctx)
    ImGui.PushFont(ctx, FONT_B, FUNC.sz(11))
    local mlbl_w = ImGui.CalcTextSize(ctx, "MASTER", 0, 0)
    ImGui.PopFont(ctx)
    local mval_w = FUNC.sz(56)  -- 數值文字寬 -- value text width
    local mpad = FUNC.sz(12)
    -- undo 組 + 間距 + master 外框（label/數值/內距）+ 間距 + 設定鈕 + 右邊界 -- right-side fixed widths
    local fixed_w = FUNC.sz(64) + gx + (mpad * 3 + mlbl_w + mval_w) + gx + set_w + FUNC.sz(8)
    local master_w = math.floor(FUNC.clamp(rest - fixed_w, FUNC.sz(80), bw * 2.5))
    local need = fixed_w + master_w
    local middle_gap = math.max(0, rest - need)

    -- 巢狀深度警告：⚠ 閃 5 下、停 3 秒、淡出 2 秒；水平+垂直皆置中於中央 gap
    -- depth warning: icon blinks 3x, hold 5s, fade 3s; centered both axes in the middle gap
    local consumed_left = 0
    if _depth_warn_t0 then
      local t = reaper.time_precise() - _depth_warn_t0
      local hold_end, fade_end = 3.0, 5.0
      if t >= fade_end then
        _depth_warn_t0 = nil
      else
        local base_a = (t < hold_end) and 1.0 or (1.0 - (t - hold_end) / (fade_end - hold_end))
        base_a = math.max(0, math.min(1, base_a))
        local icon_a = 1.0
        if t < 1 then icon_a = (math.floor(t / 0.1) % 2 == 0) and 1.0 or 0.15 end
        ImGui.PushFont(ctx, FONT, FUNC.sz(16))
        local icon_w, txt_h = ImGui.CalcTextSize(ctx, "⚠")
        local _warn_msg = _toolbar_warn_msg or "Max nesting depth (5) reached"
        local msg_w, _ = ImGui.CalcTextSize(ctx, _warn_msg)
        local sp = FUNC.sz(6)
        local total_w = icon_w + sp + msg_w
        local left_pad = math.max(0, math.floor((middle_gap - total_w) / 2))
        if left_pad > 0 then ImGui.SameLine(ctx, 0, left_pad) end
        local center_y = math.floor((tb_h - txt_h) / 2)
        ImGui.SetCursorPosY(ctx, center_y)
        ImGui.PushStyleColor(ctx, ImGui.Col_Text(), FUNC.rgba(230, 70, 70, math.floor(255 * icon_a * base_a)))
        ImGui.Text(ctx, "⚠"); ImGui.PopStyleColor(ctx, 1)
        ImGui.SameLine(ctx, 0, sp)
        ImGui.SetCursorPosY(ctx, center_y)
        ImGui.PushStyleColor(ctx, ImGui.Col_Text(), FUNC.rgba(230, 70, 70, math.floor(255 * base_a)))
        ImGui.Text(ctx, _warn_msg)
        ImGui.PopStyleColor(ctx, 1)
        ImGui.PopFont(ctx)
        consumed_left = left_pad + total_w
      end
    end

    local right_pad = math.max(0, middle_gap - consumed_left)
    if right_pad > 0 then ImGui.SameLine(ctx, 0, right_pad) end

    -- Undo / Redo（分段組）-- undo / redo segmented
    hit = FUNC.ui_seg({
      {id="##undo", icon="undo",  disabled=(#undo.stack == 0), tip="Undo (Cmd+Z)"},
      {id="##redo", icon="redo", disabled=(#undo.redo == 0),  tip="Redo (Cmd+Shift+Z)"},
    }, {h=bh})
    if hit == 1 then FUNC.do_undo() elseif hit == 2 then FUNC.do_redo() end
    ImGui.SameLine(ctx, 0, gx)

    -- ═══ Master 音量：凹槽外框 + 細軌道 + 白色圓形把手 ═══ -- master: well + thin track + round knob
    local tb_dl = ImGui.GetWindowDrawList(ctx)
    local mx0, my0 = ImGui.GetCursorScreenPos(ctx)
    local mbox_w = mpad * 3 + mlbl_w + master_w + mval_w
    ImGui.DrawList_AddRectFilled(tb_dl, mx0, my0, mx0 + mbox_w, my0 + bh, FUNC.dim_c(C.seg), FUNC.rad("m") + 2)
    ImGui.DrawList_AddRect(tb_dl, mx0, my0, mx0 + mbox_w, my0 + bh, FUNC.dim_c(C.line), FUNC.rad("m") + 2, 0, 1)
    ImGui.DrawList_AddTextEx(tb_dl, FONT_B, FUNC.sz(11), mx0 + mpad, my0 + math.floor((bh - FUNC.sz(11)) / 2), FUNC.dim_c(C.dim), "MASTER")
    local sl_x = mx0 + mpad * 2 + mlbl_w
    local fh = ImGui.GetFrameHeight(ctx)
    ImGui.SetCursorScreenPos(ctx, sl_x, my0 + math.floor((bh - fh) / 2))
    ImGui.SetNextItemWidth(ctx, master_w)
    local master_ie_mode = ie.active and ie.row == 0 and ie.col == "master"
    if master_ie_mode then
      -- 雙擊後的輸入框模式 -- typed-entry mode after double-click
      local age = reaper.time_precise() - ie.t
      if age < 0.05 then ImGui.SetKeyboardFocusHere(ctx) end
      local fl = ImGui.InputTextFlags_AutoSelectAll() | ImGui.InputTextFlags_EnterReturnsTrue()
      local ich, inv = ImGui.InputText(ctx, "##master_ie", ie.buf, fl)
      ie.buf = inv  -- 持續同步buffer
      if ich then FUNC.commit_ie()
      elseif age > 0.15 and not ImGui.IsItemActive(ctx) then FUNC.commit_ie() end
    else
      -- 隱形 slider 負責互動，外觀自己畫 -- invisible slider handles input; visuals drawn below
      ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg(), 0)
      ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered(), 0)
      ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive(), 0)
      ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrab(), 0)
      ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrabActive(), 0)
      ImGui.PushStyleColor(ctx, ImGui.Col_Text(), 0)
      local ch, nv = ImGui.SliderDouble(ctx, "##master", prefs.master_vol, prefs.vol_min, prefs.vol_max, "%.1f dB")
      ImGui.PopStyleColor(ctx, 6)
      if ch then prefs.master_vol = nv end
      if math.abs(prefs.master_vol)%6 <= 0.3 then prefs.master_vol = math.ceil(prefs.master_vol) end
      if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left()) and FUNC.try_dbl("master") then
        FUNC.start_ie(0, "master", string.format("%.1f", prefs.master_vol))
      end
      local s_hov, s_act = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
      local cy = my0 + bh / 2
      local tr_h = FUNC.sz(4)
      local kr = FUNC.sz(7)
      local x1, x2 = sl_x + kr, sl_x + master_w - kr  -- 把手不超出 -- keep knob inside
      local m_frac = FUNC.clamp((prefs.master_vol - prefs.vol_min) / (prefs.vol_max - prefs.vol_min), 0, 1)
      local kx = x1 + (x2 - x1) * m_frac
      ImGui.DrawList_AddRectFilled(tb_dl, x1, cy - tr_h/2, x2, cy + tr_h/2, FUNC.dim_c(C.field), tr_h/2)
      ImGui.DrawList_AddRectFilled(tb_dl, x1, cy - tr_h/2, kx, cy + tr_h/2, FUNC.dim_c(C.primary_hi), tr_h/2)
      ImGui.DrawList_AddCircleFilled(tb_dl, kx, cy + 1, kr + 1, FUNC.rgba(0,0,0,110))  -- 陰影 -- shadow
      ImGui.DrawList_AddCircleFilled(tb_dl, kx, cy, kr, FUNC.dim_c((s_hov or s_act) and FUNC.rgba(255,255,255) or C.knob))
      if s_hov and not s_act then ImGui.SetTooltip(ctx, "Double-click to type") end
    end
    local m_txt = string.format("%.1f dB", prefs.master_vol)
    local m_tw = ImGui.CalcTextSize(ctx, m_txt, 0, 0)
    ImGui.DrawList_AddText(tb_dl, mx0 + mbox_w - mpad - m_tw, my0 + math.floor((bh - ImGui.GetTextLineHeight(ctx)) / 2), FUNC.dim_c(C.text), m_txt)
    ImGui.SetCursorScreenPos(ctx, mx0, my0); ImGui.Dummy(ctx, mbox_w, bh)

    -- 設定（齒輪）-- settings gear
    ImGui.SameLine(ctx)
    ImGui.SetCursorPosX(ctx, child_w - FUNC.sz(8) - set_w)
    if FUNC.ui_btn("##tb_set", "", "ghost", {icon="gear", w=set_w, h=bh, isz=FUNC.sz(17), tip="Preferences", active=popup.settings}) then
      popup.settings = not popup.settings
    end

    ImGui.PopFont(ctx)
    ImGui.EndChild(ctx)
  end
  ImGui.PopStyleColor(ctx, 1)
end

---------------------------------------------------------------------
-- 16. BOTTOM BAR
---------------------------------------------------------------------
function FUNC.draw_bottom()
  local bar_h = FUNC.sz(56)
  ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg(), C.chrome)
  if ImGui.BeginChild(ctx, "btm", -1, bar_h, ImGui.ChildFlags_None()) then
    local bh = FUNC.sz(40)
    local by = math.floor((bar_h - bh) / 2)
    local gap = FUNC.sz(8)
    do  -- 底列上緣細線 -- hairline above the bottom bar
      local wx, wy = ImGui.GetWindowPos(ctx)
      ImGui.DrawList_AddLine(ImGui.GetWindowDrawList(ctx), wx, wy, wx + ImGui.GetWindowWidth(ctx), wy, C.line, 1)
    end
    ImGui.SetCursorPos(ctx, FUNC.sz(8), by)

    -- GO：主色實心大按鈕 -- GO: big primary
    if FUNC.ui_btn("##go", "GO", "go", {icon="play", w=FUNC.sz(120), h=bh, font=FONT_B, fsz=FUNC.sz(20), isz=FUNC.sz(14), radius=FUNC.rad("l"), tip="Space"}) then FUNC.go_next() end
    ImGui.SameLine(ctx, 0, gap)
    -- PANIC：紅色實心 -- PANIC: danger
    if FUNC.ui_btn("##panic", "PANIC", "danger", {w=FUNC.sz(96), h=bh, font=FONT_B, fsz=FUNC.sz(14), radius=FUNC.rad("l"), tip="Stop all cues (Esc)"}) then FUNC.panic() end

    -- 分隔線 -- divider
    ImGui.SameLine(ctx, 0, gap + FUNC.sz(4))
    do
      local dx, dy = ImGui.GetCursorScreenPos(ctx)
      ImGui.DrawList_AddLine(ImGui.GetWindowDrawList(ctx), dx, dy + FUNC.sz(8), dx, dy + bh - FUNC.sz(8), C.line2, 1)
      ImGui.Dummy(ctx, 1, bh)
    end
    ImGui.SameLine(ctx, 0, gap + FUNC.sz(4))

    -- 次要動作：灰色按鈕 -- secondary actions: neutral
    local sec = {w=FUNC.sz(84), h=bh, font=FONT_B, fsz=FUNC.sz(14), radius=FUNC.rad("l")}
    sec.tip = "Preview selected cues (V)"
    if FUNC.ui_btn("##preview", "Preview", "neutral", sec) then FUNC.check_sel_fn() end
    ImGui.SameLine(ctx, 0, gap)
    sec.tip = "Stop selected cues (K)"
    if FUNC.ui_btn("##kill", "Kill", "neutral", sec) then FUNC.kill() end
    ImGui.SameLine(ctx, 0, gap)
    sec.tip = nil
    if FUNC.ui_btn("##reset", "Reset", "neutral", sec) then FUNC.reset_show() end
    ImGui.SameLine(ctx, 0, FUNC.sz(18))

    -- NEXT：小標 + 金色 Q 號 + 名稱（名稱過長跑馬燈）+ 類型 -- next: label, gold cue number, name (marquee), type
    local dl = ImGui.GetWindowDrawList(ctx)
    local nx, ny0 = ImGui.GetCursorScreenPos(ctx)
    local wy = select(2, ImGui.GetWindowPos(ctx))
    local edit_btn_w = FUNC.sz(56)
    local btm_w = ImGui.GetWindowWidth(ctx)
    local avail = btm_w - (nx - select(1, ImGui.GetWindowPos(ctx))) - edit_btn_w - FUNC.sz(24)
    local big = FUNC.sz(19)
    local ty = wy + math.floor((bar_h - big) / 2) - 1
    ImGui.DrawList_AddTextEx(dl, FONT_B, FUNC.sz(10), nx, ty + big - FUNC.sz(12), FUNC.dim_c(C.dim), "NEXT")
    ImGui.PushFont(ctx, FONT_B, FUNC.sz(10)); local lbl_w = ImGui.CalcTextSize(ctx, "NEXT", 0, 0); ImGui.PopFont(ctx)
    local x = nx + lbl_w + FUNC.sz(10)
    if next_go >= 1 and next_go <= #cues then
      local nc = cues[next_go]
      local qtxt = "Q" .. ((nc.cue_number ~= "" and nc.cue_number) or "?")
      ImGui.DrawList_AddTextEx(dl, FONT_B, big, x, ty, FUNC.dim_c(C.gold), qtxt)
      ImGui.PushFont(ctx, FONT_B, big); local qw = ImGui.CalcTextSize(ctx, qtxt, 0, 0); ImGui.PopFont(ctx)
      x = x + qw + FUNC.sz(10)
      local tname = ((TYPE_SHORT[nc.type] or nc.type):gsub("^[^%a]+", ""))  -- 去掉舊符號 -- strip legacy glyph
      ImGui.PushFont(ctx, FONT, FUNC.sz(12)); local tw = ImGui.CalcTextSize(ctx, tname, 0, 0); ImGui.PopFont(ctx)
      local name_w = math.max(0, avail - (x - nx) - tw - FUNC.sz(12))
      local nxt_name = nc.name ~= "" and nc.name or "(unnamed)"
      if name_w > 0 then
        FUNC.draw_marquee(dl, FONT, big, nxt_name, FUNC.dim_c(C.text), x, ty, name_w, big, "btm_nxt"..next_go,
          {auto = true, speed = FUNC.sz(60), delay = 1.0, gap = 16})
        ImGui.PushFont(ctx, FONT, big); local nw = math.min(name_w, (ImGui.CalcTextSize(ctx, nxt_name, 0, 0))); ImGui.PopFont(ctx)
        ImGui.DrawList_AddTextEx(dl, FONT, FUNC.sz(12), x + nw + FUNC.sz(12), ty + big - FUNC.sz(14), FUNC.dim_c(C.dim), tname)
      end
    else
      ImGui.DrawList_AddTextEx(dl, FONT, big, x, ty, FUNC.dim_c(C.dim), "— End —")
    end
    ImGui.Dummy(ctx, math.max(1, avail), bh)

    -- EDIT 開關 -- edit panel toggle
    ImGui.SameLine(ctx)
    ImGui.SetCursorPos(ctx, btm_w - FUNC.sz(8) - edit_btn_w, math.floor((bar_h - FUNC.sz(30)) / 2))
    if FUNC.ui_btn("##edit_tog", "EDIT", "neutral", {icon=popup.edit and "down" or "up", w=edit_btn_w, h=FUNC.sz(30), font=FONT_B, fsz=FUNC.sz(11), isz=FUNC.sz(10),
        active=popup.edit, tip=popup.edit and "Hide edit panel" or "Show edit panel"}) then FUNC.toggle_edit() end
    ImGui.EndChild(ctx)
  end
  ImGui.PopStyleColor(ctx, 1)
end
