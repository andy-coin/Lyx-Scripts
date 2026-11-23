-- ==========================================================================
-- ui_bars.lua — Progress Bar, Toolbar, Bottom Bar
-- ==========================================================================

---------------------------------------------------------------------
-- 13.5 CUSTOM PROGRESS BAR
---------------------------------------------------------------------
function FUNC.draw_pbar(dl, x, y, w, h, frac, bar_col, text, middle)
  ImGui.DrawList_AddRectFilled(dl, x, y, x+w, y+h, FUNC.dim_c(FUNC.rgba(40,40,55)), 3)
  if frac>0 then
    ImGui.DrawList_AddRectFilled(dl, x, y, x+math.max(1,w*FUNC.clamp(frac,0,1)), y+h, FUNC.dim_c(bar_col), 3)
  end
  if text then
    ImGui.PushFont(ctx, FONT_MONO, FUNC.sz(14))
    local tw,th = ImGui.CalcTextSize(ctx, text, 0, 0)
    ImGui.PopFont(ctx)
    local tx = (middle and (x + (w - tw)/2 )) or (x + w - tw - 4)
    local ty = y + math.floor((h - th) * 0.5)
    ImGui.DrawList_AddTextEx(dl, FONT_MONO, FUNC.sz(14), tx, ty, FUNC.dim_c(C.text), text)
  end
end

---------------------------------------------------------------------
-- 14. TOOLBAR
---------------------------------------------------------------------
function FUNC.draw_toolbar()
  ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg(), C.panel)
  if ImGui.BeginChild(ctx, "toolbar", -1, FUNC.sz(42), ImGui.ChildFlags_None()) then
    ImGui.SetCursorPos(ctx, 6, math.floor((FUNC.sz(42) - FUNC.sz(28)) / 2))
    ImGui.PushFont(ctx, FONT, FUNC.sz(14))
    local bh = FUNC.sz(28)
    local ref_tw,_ = ImGui.CalcTextSize(ctx, "▣ Group", 0, 0)
    local bw = ref_tw + FUNC.sz(16)

    function tb(l, c1, c2)
      ImGui.PushStyleColor(ctx, ImGui.Col_Button(), c1)
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), c2)
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), c2)
      local r = ImGui.Button(ctx, l, bw, bh); ImGui.PopStyleColor(ctx, 3); return r
    end

    local after = FUNC.sel_first(); if after < 1 then after = #cues end
    -- Audio按鈕兩個選項 -- audio button with 2 options popup
    if tb("▶ Audio", C.tb_play, C.tb_play_h) then ImGui.OpenPopup(ctx, "audio_add_menu") end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Add PLAY cue") end
    if ImGui.BeginPopup(ctx, "audio_add_menu") then
      if ImGui.Selectable(ctx, "Add from selected track") then FUNC.add_cue("PLAY", after) end
      if ImGui.Selectable(ctx, "Add files to REAPER") then FUNC.file_add_play(after) end
      ImGui.EndPopup(ctx)
    end
    ImGui.SameLine(ctx, 0, 3)
    if tb("♪ MIDI", C.tb_midi, C.tb_midi_h) then ImGui.OpenPopup(ctx, "midi_add_menu") end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Add MIDI cue") end
    if ImGui.BeginPopup(ctx, "midi_add_menu") then
      if ImGui.Selectable(ctx, "Insert new track") then FUNC.add_cue("MIDI", after, "new") end
      if ImGui.Selectable(ctx, "Add from selected track") then FUNC.add_cue("MIDI", after, "selected") end
      ImGui.EndPopup(ctx)
    end
    ImGui.SameLine(ctx, 0, 3)
    if tb("■ Stop", C.tb_stop, C.tb_stop_h) then FUNC.add_cue("STOP", after) end; ImGui.SameLine(ctx, 0, 3)
    if tb("‖ Pause", C.tb_pause, C.tb_pause_h) then FUNC.add_cue("PAUSE", after) end; ImGui.SameLine(ctx, 0, 3)
    if tb("≈ Fade", C.tb_fade, C.tb_fade_h) then FUNC.add_cue("FADE", after) end; ImGui.SameLine(ctx, 0, 3)

    local sc2 = FUNC.sel_cnt()
    local grp_too_deep = sc2 >= 2 and FUNC.group_sel_would_exceed()
    local grp_disabled = sc2 < 2 or grp_too_deep
    if grp_disabled then ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha(), 0.35) end
    if tb("▣ Group", C.tb_grp, C.tb_grp_h) then
      if grp_too_deep then FUNC.warn_max_depth()
      elseif not grp_disabled then FUNC.group_sel() end
    end
    if grp_disabled then ImGui.PopStyleVar(ctx, 1)
      -- 只在「未選 2+ cue」狀態顯示 tooltip；too-deep 改由 toolbar 中央 warning 統一呈現
      -- only show "select 2+" tooltip; too-deep handled by central warning
      if not grp_too_deep and ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Select 2+ cues") end
    end
    ImGui.SameLine(ctx, 0, 3)
    local sf_ug = FUNC.sel_first()
    local has_grp = sf_ug >= 1 and sf_ug <= #cues and cues[sf_ug].type == "GROUP"
    if not has_grp then ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha(), 0.35) end
    if tb("Ungroup", C.tb_grp, C.tb_grp_h) then if has_grp then FUNC.ungroup_cue(sf_ug) end end
    if not has_grp then ImGui.PopStyleVar(ctx, 1)
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Select a GROUP cue") end end

    ImGui.SameLine(ctx, 0, FUNC.sz(6)); ImGui.PushStyleColor(ctx, ImGui.Col_Text(), C.dim)
    ImGui.Text(ctx, "|"); ImGui.PopStyleColor(ctx, 1); ImGui.SameLine(ctx, 0, FUNC.sz(6))

    if tb("Save", FUNC.rgba(50, 80, 110), FUNC.rgba(65, 100, 140)) then popup.save = true end
    ImGui.SameLine(ctx, 0, 3)
    if tb("Load", FUNC.rgba(80, 60, 100), FUNC.rgba(100, 80, 130)) then popup.load = true end
    ImGui.SameLine(ctx, 0, 3)
    if tb("Re#", FUNC.rgba(80, 80, 60), FUNC.rgba(100, 100, 80)) then FUNC.push_undo(); FUNC.renumber(); FUNC.save_cues() end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Reset cue numbers (1, 2, 3...)") end

    -- Right: Undo/Redo + Master + Settings — 先算 master_w 與右側 fixed 寬，剩餘空間做為深度警告置中區
    -- compute right-side widths first; remaining gap reserved for depth warning (centered)
    ImGui.SameLine(ctx)
    local ub_w = FUNC.sz(28)
    local set_w = FUNC.sz(32)
    local child_w = ImGui.GetWindowWidth(ctx)
    local rest,_ = ImGui.GetContentRegionAvail(ctx)
    local fixed_w = ub_w*2 + FUNC.sz(8) + FUNC.sz(80) + FUNC.sz(8) + set_w + 6
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
        local center_y = math.floor((FUNC.sz(42) - txt_h) / 2)
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

    -- Undo/Redo 按鈕加深底色 -- deeper undo/redo button colors
    local undo_dim = #undo.stack == 0
    ImGui.PushStyleColor(ctx, ImGui.Col_Button(), FUNC.rgba(50,55,70))
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), FUNC.rgba(65,70,90))
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), FUNC.rgba(80,85,110))
    if undo_dim then ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha(), 0.35) end
    if ImGui.Button(ctx, "←##undo", ub_w, bh) then if #undo.stack > 0 then FUNC.do_undo() end end
    if undo_dim then ImGui.PopStyleVar(ctx, 1) end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Undo (Cmd+Z)") end
    ImGui.SameLine(ctx, 0, 8)
    local redo_dim = #undo.redo == 0
    if redo_dim then ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha(), 0.35) end
    if ImGui.Button(ctx, "→##redo", ub_w, bh) then if #undo.redo > 0 then FUNC.do_redo() end end
    if redo_dim then ImGui.PopStyleVar(ctx, 1) end
    ImGui.PopStyleColor(ctx, 3)
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Redo (Cmd+Shift+Z)") end
    ImGui.SameLine(ctx, 0, 25)

    -- Master group
    local offset_x, offset_y = 0, 6
    local start_x, start_y = ImGui.GetCursorPos(ctx)

    ImGui.BeginGroup(ctx)
    ImGui.SetCursorPos(ctx, start_x + offset_x, start_y + offset_y)

    ImGui.PushFont(ctx, FONT_B, FUNC.sz(13))
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text(), C.header)
    ImGui.Text(ctx, "MASTER")
    ImGui.PopStyleColor(ctx, 1)
    ImGui.PopFont(ctx)

    local label_w, _ = ImGui.CalcTextSize(ctx, "MASTER", 0, 0)
    local spacing = FUNC.sz(2)
    local slider_x = (start_x + offset_x) + label_w + spacing
    local slider_y = (start_y + offset_y)

    ImGui.SetCursorPos(ctx, slider_x, slider_y)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg(), FUNC.rgba(40, 40, 55))
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered(), FUNC.rgba(50, 50, 70))
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive(), FUNC.rgba(55, 55, 75))
    ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrab(), 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrabActive(), 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text(), 0)

    ImGui.SetNextItemWidth(ctx, master_w)
    -- 雙擊master變輸入框 -- double-click master to type value
    if ie.active and ie.row == 0 and ie.col == "master" then
      -- 輸入框模式：還原文字顏色+明顯FrameBg，讓使用者看到輸入框
      ImGui.PushStyleColor(ctx, ImGui.Col_Text(), C.text)
      ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg(), FUNC.rgba(25, 25, 40))
      ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive(), FUNC.rgba(30, 30, 50))
      local age = reaper.time_precise() - ie.t
      if age < 0.05 then ImGui.SetKeyboardFocusHere(ctx) end
      local fl = ImGui.InputTextFlags_AutoSelectAll() | ImGui.InputTextFlags_EnterReturnsTrue()
      local ich, inv = ImGui.InputText(ctx, "##master_ie", ie.buf, fl)
      ie.buf = inv  -- 持續同步buffer
      if ich then
        FUNC.commit_ie()
      elseif age > 0.15 and not ImGui.IsItemActive(ctx) then
        FUNC.commit_ie()
      end
      ImGui.PopStyleColor(ctx, 3)  -- 還原Col_Text + FrameBg + FrameBgActive
    else
      local ch, nv = ImGui.SliderDouble(ctx, "##master", prefs.master_vol, prefs.vol_min, prefs.vol_max, "%.1f dB")
      if ch then prefs.master_vol = nv end
      if math.abs(prefs.master_vol)%6 <= 0.3 then prefs.master_vol = math.ceil(prefs.master_vol) end
      if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left()) and FUNC.try_dbl("master") then
        FUNC.start_ie(0, "master", string.format("%.1f", prefs.master_vol))
      end
    end

    ImGui.PopStyleColor(ctx, 6)
    local ms1x, ms1y = ImGui.GetItemRectMin(ctx)
    local ms2x, ms2y = ImGui.GetItemRectMax(ctx)
    local m_dl = ImGui.GetWindowDrawList(ctx)
    -- 雙擊master輸入框模式：跳過水位填充和文字覆蓋，只畫外框
    local master_ie_mode = ie.active and ie.row == 0 and ie.col == "master"
    if master_ie_mode then
      -- 輸入框模式：畫明顯邊框提示使用者 -- highlight border for input mode
      ImGui.DrawList_AddRect(m_dl, ms1x, ms1y, ms2x, ms2y, C.accent, 3, 0, FUNC.sz(2))
    else
      local m_frac = FUNC.clamp((prefs.master_vol - prefs.vol_min) / (prefs.vol_max - prefs.vol_min), 0, 1)
      if m_frac > 0 then
        local fill_x = ms1x + (ms2x - ms1x) * m_frac
        ImGui.DrawList_AddRectFilled(m_dl, ms1x, ms1y, fill_x, ms2y, FUNC.dim_c(C.accent), 3)
      end
      local m_txt = string.format("%.1f dB", prefs.master_vol)
      local m_tw, m_th = ImGui.CalcTextSize(ctx, m_txt, 0, 0)
      local pad = FUNC.sz(5)
      ImGui.DrawList_AddText(m_dl, ms2x - m_tw - pad, ms1y + math.floor((ms2y - ms1y - m_th) * 0.5), FUNC.dim_c(C.text), m_txt)
    end
    ImGui.EndGroup(ctx)

    local mg_x1, mg_y1 = ImGui.GetItemRectMin(ctx)
    local mg_x2, mg_y2 = ImGui.GetItemRectMax(ctx)
    local tb_dl = ImGui.GetWindowDrawList(ctx)
    ImGui.DrawList_AddRect(tb_dl, mg_x1-FUNC.sz(4), mg_y1-FUNC.sz(1)+offset_y, mg_x2+FUNC.sz(1), mg_y2+FUNC.sz(1), FUNC.dim_c(C.bdr), FUNC.sz(3), 0, 2)
    ImGui.SameLine(ctx)
    ImGui.SetCursorPosX(ctx, child_w - 6 - set_w)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button(), FUNC.rgba(50,55,70))
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), FUNC.rgba(65,70,90))
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), FUNC.rgba(80,85,110))
    if ImGui.Button(ctx, "SET", set_w, bh) then popup.settings = not popup.settings end
    ImGui.PopStyleColor(ctx, 3)
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Preferences") end

    ImGui.PopFont(ctx)
    ImGui.EndChild(ctx)
  end
  ImGui.PopStyleColor(ctx, 1)
end

---------------------------------------------------------------------
-- 16. BOTTOM BAR
---------------------------------------------------------------------
function FUNC.draw_bottom()
  ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg(), C.panel)
  if ImGui.BeginChild(ctx, "btm", -1, FUNC.sz(56), ImGui.ChildFlags_None()) then
    local bh = FUNC.sz(42)
    ImGui.SetCursorPos(ctx, 8, math.floor((FUNC.sz(56) - bh) / 2))

    ImGui.PushFont(ctx, FONT_B, FUNC.sz(28))
    ImGui.PushStyleColor(ctx, ImGui.Col_Button(), C.go)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), C.go_h)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), C.go_h)
    local go_tw,_ = ImGui.CalcTextSize(ctx, " ‣  GO ", 0, 0)
    local go_w = go_tw + FUNC.sz(10)
    if ImGui.Button(ctx, " ‣  GO ", go_w, bh) then FUNC.go_next() end
    ImGui.PopStyleColor(ctx, 3)
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Space") end
    ImGui.PopFont(ctx)

    ImGui.SameLine(ctx, 0, FUNC.sz(4))
    ImGui.PushFont(ctx, FONT_B, FUNC.sz(16))  -- 按鈕文字加大加粗 -- bigger bolder button text

    function bb(l, c1, c2)
      ImGui.PushStyleColor(ctx, ImGui.Col_Button(), c1)
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), c2)
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), c2)
      local r = ImGui.Button(ctx, l, go_w, bh); ImGui.PopStyleColor(ctx, 3); return r
    end

    if bb("PANIC", C.panic_b, C.panic_h) then FUNC.panic() end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Stop all cues (Esc)") end; ImGui.SameLine(ctx, 0, FUNC.sz(4))
    if bb("Preview", C.chk_b, C.chk_h) then FUNC.check_sel_fn() end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Preview selected cues (V)") end; ImGui.SameLine(ctx, 0, FUNC.sz(4))
    if bb("Kill", C.kill_b, C.kill_h) then FUNC.kill() end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Stop selected cues (K)") end; ImGui.SameLine(ctx, 0, FUNC.sz(4))
    if bb("Reset", C.reset_b, C.reset_h) then FUNC.reset_show() end; ImGui.SameLine(ctx, 0, FUNC.sz(10))

    ImGui.PushFont(ctx, FONT_B, FUNC.sz(18))
    local _,nxt_th = ImGui.CalcTextSize(ctx, "Next:", 0, 0)
    local nxt_cy = math.floor((FUNC.sz(56) - nxt_th) / 2)
    ImGui.SetCursorPosY(ctx, nxt_cy)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text(), C.dim)
    ImGui.Text(ctx, "Next:"); ImGui.PopStyleColor(ctx, 1)
    local nxt_lbl_y1 = select(2, ImGui.GetItemRectMin(ctx))  -- "Next:"實際繪製Y -- actual rendered Y of "Next:"
    ImGui.SameLine(ctx, 0, 6)
    if next_go >= 1 and next_go <= #cues then
      local nc = cues[next_go]
      local nxt_col = TYPE_COL[nc.type] or C.text
      local nxt_dl = ImGui.GetWindowDrawList(ctx)
      local nxt_sx = select(1, ImGui.GetCursorScreenPos(ctx))
      local nxt_avail = ImGui.GetContentRegionAvail(ctx) - FUNC.sz(60)  -- 預留EDIT按鈕空間 -- reserve space for EDIT button
      -- 固定前綴 "Q# >> [Type]  " 不滾動，只有名字跑馬燈 -- static prefix, only name scrolls
      local nxt_prefix = string.format("Q%s  >>  [%s]  ",
        nc.cue_number ~= "" and nc.cue_number or "?",
        TYPE_SHORT[nc.type] or nc.type)
      local nxt_name = nc.name ~= "" and nc.name or "(unnamed)"
      ImGui.PushFont(ctx, FONT_B, FUNC.sz(18))
      local prefix_tw = ImGui.CalcTextSize(ctx, nxt_prefix, 0, 0)
      ImGui.PopFont(ctx)
      -- 畫固定前綴 -- draw static prefix
      ImGui.DrawList_AddTextEx(nxt_dl, FONT_B, FUNC.sz(18), nxt_sx, nxt_lbl_y1, nxt_col, nxt_prefix)
      -- 名字區域跑馬燈 -- marquee only for name portion
      local name_sx = nxt_sx + prefix_tw
      local name_avail = nxt_avail - prefix_tw
      if name_avail > 0 then
        FUNC.draw_marquee(nxt_dl, FONT_B, FUNC.sz(18), nxt_name, nxt_col,
          name_sx, nxt_lbl_y1, name_avail, nxt_th, "btm_nxt"..next_go,
          {auto = true, speed = FUNC.sz(60), delay = 1.0, gap = 16})
      end
      ImGui.Dummy(ctx, nxt_avail, nxt_th)
    else
      ImGui.SetCursorPosY(ctx, nxt_cy)  -- 與"Next:"同高度垂直置中 -- align vertically with "Next:"
      ImGui.PushStyleColor(ctx, ImGui.Col_Text(), C.dim)
      ImGui.Text(ctx, "-- End --"); ImGui.PopStyleColor(ctx, 1)
    end
    ImGui.PopFont(ctx)

    ImGui.SameLine(ctx)
    ImGui.PushFont(ctx, FONT_B, FUNC.sz(12))  
    local edit_btn_w = FUNC.sz(50)
    local btm_w = ImGui.GetWindowWidth(ctx)
    ImGui.SetCursorPosX(ctx, btm_w - 6 - edit_btn_w)
    ImGui.SetCursorPosY(ctx, math.floor((FUNC.sz(56) - bh) / 2))
    local eb_col = popup.edit and FUNC.rgba(80,80,130) or FUNC.rgba(50,50,70)
    local eb_hov = popup.edit and FUNC.rgba(90,90,150) or FUNC.rgba(70,70,100)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button(), eb_col)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), eb_hov)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), FUNC.rgba(100,100,160))
    local edit_label = popup.edit and "EDIT ▲" or "EDIT ▼"  
    if ImGui.Button(ctx, edit_label, edit_btn_w, bh) then FUNC.toggle_edit() end
    ImGui.PopStyleColor(ctx, 3)
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, popup.edit and "Hide edit panel" or "Show edit panel") end
    ImGui.PopFont(ctx)
    ImGui.PopFont(ctx)
    ImGui.EndChild(ctx)
  end
  ImGui.PopStyleColor(ctx, 1)
end
