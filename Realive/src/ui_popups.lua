-- ==========================================================================
-- ui_popups.lua — Settings, Save/Load, Trim, Fade Edit, Warning
-- ==========================================================================

-- popup失焦自動關閉(含子視窗判定) -- auto-close popup when it loses focus (child-aware)
local function popup_lost_focus()
  return not ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_RootAndChildWindows())
end

-- popup內Enter鍵檢查：InputText沒有focus時，Enter=確認關閉 -- Enter key closes popup when no InputText is focused
local function popup_enter_pressed()
  if ImGui.IsKeyPressed(ctx, ImGui.Key_Enter()) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter()) then
    -- 任何InputText有focus時不攔截Enter -- don't intercept Enter when InputText is active
    if not ImGui.IsAnyItemActive(ctx) then return true end
  end
  return false
end

---------------------------------------------------------------------
-- 17. SETTINGS (unified: Colors + Settings + Shortcuts)
---------------------------------------------------------------------
-- Color categories for categorized display -- 顏色分類定義
local COL_CATS = {
  {cat="Interface", items={
    {key="col_bg",           name="Background"},
    {key="col_panel",        name="Panel"},
    {key="col_header",       name="Header"},
    {key="col_column_title", name="Column Title"},
    {key="col_text",         name="Text"},
    {key="col_text_dim",     name="Dim Text"},
    {key="col_row",          name="Row Background"},
    {key="col_border",       name="Border"},
    {key="col_accent",       name="Accent"},
  }},
  {cat="Transport", items={
    {key="col_go",           name="GO Button"},
  }},
  {cat="Progress", items={
    {key="col_prewait",      name="Pre-Wait"},
    {key="col_postwait",     name="Post-Wait"},
    {key="col_duration",     name="Duration"},
  }},
  {cat="Waveform", items={
    {key="col_wf",           name="Waveform"},
    {key="col_wf_bg",        name="Wave Background"},
    {key="col_trim",         name="Trim Handle"},
    {key="col_env",          name="Volume Envelope"},
    {key="col_pan_env",      name="Pan Envelope"},
    {key="col_ruler",        name="Ruler"},
    {key="col_guide",        name="Guide Line"},
  }},
}

function FUNC.draw_settings()
  if not popup.settings then scut_listen = nil; return end

  -- Panel visibility state (非持久) -- panel toggle state (session only)
  if popup._pref_colors == nil then popup._pref_colors = true end
  if popup._pref_scuts == nil then popup._pref_scuts = true end

  -- Dimensions -- 面板尺寸
  local col_w = FUNC.sz(240)
  local mid_w = FUNC.sz(260)
  local sc_w = FUNC.sz(310)
  local tog_w = FUNC.sz(16)
  local pad = FUNC.sz(16)

  -- 動態寬度，以中間欄為錨點 -- dynamic width, middle column anchored at center
  local left_w = popup._pref_colors and col_w or 0
  local right_w = popup._pref_scuts and sc_w or 0
  local total_w = left_w + tog_w + mid_w + tog_w + right_w + pad

  -- 中間錨點：追蹤中間欄左邊界的螢幕X，toggle時保持不變 -- track middle column's screen X, keep it stationary on toggle
  local new_left = left_w + tog_w  -- 中間欄左邊界在視窗內的偏移 -- middle column offset within window
  if popup._pref_mid_sx and popup._pref_prev_left ~= nil and popup._pref_prev_left ~= new_left then
    local new_wx = popup._pref_mid_sx - new_left  -- 反推新的視窗X -- derive new window X from stored mid X
    ImGui.SetNextWindowPos(ctx, new_wx, popup._pref_wy or 0)
  end
  popup._pref_prev_left = new_left

  ImGui.SetNextWindowSize(ctx, total_w, FUNC.sz(600), ImGui.Cond_Always())
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg(), FUNC.rgba(35,35,45))
  ImGui.PushStyleColor(ctx, ImGui.Col_TitleBgActive(), FUNC.rgba(65,65,90))
  local vis, op = ImGui.Begin(ctx, "Preferences###Settings", true,
    ImGui.WindowFlags_NoDocking() | ImGui.WindowFlags_NoResize())
  if vis then
    if popup_lost_focus() then op = false end  -- 失焦自動關閉
    -- 每幀記錄視窗位置+中間欄螢幕X -- store window pos + middle column screen X each frame
    local wx, wy = ImGui.GetWindowPos(ctx)
    popup._pref_wy = wy
    popup._pref_mid_sx = wx + (popup._pref_prev_left or 0)  -- 中間欄左邊界的螢幕X -- middle column left edge screen X
    ImGui.PushFont(ctx, FONT, FUNC.sz(13))
    local _, avail_h = ImGui.GetContentRegionAvail(ctx)
    local ch = avail_h - FUNC.sz(34)  -- 留空間給底部按鈕 -- reserve for save button
    local pdl = ImGui.GetWindowDrawList(ctx)
    local cefl = ImGui.ColorEditFlags_NoInputs() | ImGui.ColorEditFlags_NoLabel()
    local pref_notes_active = false  -- notes輸入框是否活躍 -- track notes InputText active state
    local pref_enter_consumed = false  -- 有輸入框消耗了Enter -- an input consumed Enter this frame

    -- Toggle button helper -- 三角形toggle按鈕繪製
    local function draw_tog(id, w, h, point_right)
      local tx, ty = ImGui.GetCursorScreenPos(ctx)
      ImGui.InvisibleButton(ctx, id, w, h)
      local hov = ImGui.IsItemHovered(ctx)
      local bg = hov and FUNC.rgba(55,55,75) or FUNC.rgba(40,40,55)
      ImGui.DrawList_AddRectFilled(pdl, tx, ty, tx+w, ty+h, bg, 2)
      local tri = FUNC.sz(5)
      local cx, cy = tx + w/2, ty + h/2
      local tc = hov and FUNC.rgba(200,200,220) or FUNC.rgba(110,110,130)
      if point_right then
        ImGui.DrawList_AddTriangleFilled(pdl, cx-tri*0.4, cy-tri, cx+tri*0.6, cy, cx-tri*0.4, cy+tri, tc)
      else
        ImGui.DrawList_AddTriangleFilled(pdl, cx+tri*0.4, cy-tri, cx-tri*0.6, cy, cx+tri*0.4, cy+tri, tc)
      end
      return ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left())
    end

    -- ═══════════════ LEFT: Colors ═══════════════
    if popup._pref_colors then
      if ImGui.BeginChild(ctx, "##pref_col", col_w, ch) then
        local clbl_w = FUNC.sz(120)
        for ci, grp in ipairs(COL_CATS) do
          if ci > 1 then ImGui.Dummy(ctx, 0, FUNC.sz(4)) end
          ImGui.PushStyleColor(ctx, ImGui.Col_Text(), C.dim)
          ImGui.Text(ctx, grp.cat)
          ImGui.PopStyleColor(ctx, 1)
          ImGui.Separator(ctx)
          for _, cd in ipairs(grp.items) do
            ImGui.Text(ctx, "  "..cd.name); ImGui.SameLine(ctx, clbl_w)
            local cch, cnv = ImGui.ColorEdit3(ctx, "##"..cd.key, prefs[cd.key], cefl)
            if cch then prefs[cd.key] = cnv; FUNC.upd_colors(); FUNC.upd_types() end
          end
        end
        -- Themes section -- 主題區塊
        ImGui.Dummy(ctx, 0, FUNC.sz(6)); ImGui.Separator(ctx); ImGui.Dummy(ctx, 0, 3)
        ImGui.PushStyleColor(ctx, ImGui.Col_Text(), C.dim)
        ImGui.Text(ctx, "Themes")
        ImGui.PopStyleColor(ctx, 1)
        ImGui.Separator(ctx)
        if not popup.theme_name_buf then popup.theme_name_buf = "" end
        ImGui.SetNextItemWidth(ctx, -FUNC.sz(42))
        local tnch, tnnv = ImGui.InputText(ctx, "##theme_name", popup.theme_name_buf)
        if tnch then popup.theme_name_buf = tnnv end
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, "Save##theme") and popup.theme_name_buf ~= "" then
          FUNC.save_theme(popup.theme_name_buf)
        end
        local themes = FUNC.get_theme_list()
        if #themes > 0 then
          ImGui.SetNextItemWidth(ctx, -FUNC.sz(42))
          if ImGui.BeginCombo(ctx, "##theme_load", "Load...") then
            for _, tn in ipairs(themes) do
              if ImGui.Selectable(ctx, tn, false) then FUNC.load_theme(tn) end
            end
            ImGui.EndCombo(ctx)
          end
          ImGui.SameLine(ctx)
          if ImGui.BeginCombo(ctx, "##theme_del", "Del", ImGui.ComboFlags_NoPreview()) then
            for _, tn in ipairs(themes) do
              if ImGui.Selectable(ctx, tn.."##del", false) then FUNC.delete_theme(tn) end
            end
            ImGui.EndCombo(ctx)
          end
        end
      end
      ImGui.EndChild(ctx)
      ImGui.SameLine(ctx, 0, 0)
    end

    -- Left toggle (Colors) -- 左側toggle
    if draw_tog("##tog_col", tog_w, ch, popup._pref_colors) then
      popup._pref_colors = not popup._pref_colors
    end

    -- ═══════════════ MIDDLE: Settings + Project Info ═══════════════
    ImGui.SameLine(ctx, 0, 0)
    local mid_pad = FUNC.sz(8)  -- 中欄左右留白 -- middle column padding
    if ImGui.BeginChild(ctx, "##pref_mid", mid_w, ch) then
      ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + mid_pad)
      if ImGui.BeginChild(ctx, "##pref_mid_inner", mid_w - mid_pad * 2, -1) then
      local slbl_w = FUNC.sz(80)

      -- ── Project Info ── 專案資訊
      ImGui.PushStyleColor(ctx, ImGui.Col_Text(), C.dim)
      ImGui.Text(ctx, "Project Info")
      ImGui.PopStyleColor(ctx, 1)
      ImGui.Separator(ctx)

      -- Name -- 專案名稱
      ImGui.Text(ctx, "Name"); ImGui.SameLine(ctx, slbl_w)
      local disp_name = (show_name ~= "") and show_name or "Unsaved"
      ImGui.PushStyleColor(ctx, ImGui.Col_Text(), (show_name ~= "") and C.text or C.dim)
      ImGui.Text(ctx, disp_name)
      ImGui.PopStyleColor(ctx, 1)

      -- Length — 只算 top-level cues（group_id 空），group 內用 calc_group_dur 取真實時長
      -- top-level only; groups use lane-aware calc_group_dur to avoid double-counting parallel children
      local total_len = 0
      local cue_count, grp_count = 0, 0
      local used_channels = {}
      for _, c in ipairs(cues) do
        if c.type ~= "SPACER" then
          cue_count = cue_count + 1
          if c.type == "GROUP" then grp_count = grp_count + 1 end
          local is_top = not c.group_id or c.group_id == 0
          if is_top then
            if c.type == "PLAY" then
              local dur = c.eff_dur
              if (not dur or dur <= 0) and c.track_idx >= 0 then dur = FUNC.calc_dur_cached(c.track_idx, c.id) end
              if dur and dur > 0 then
                local ts = c.trim_start or 0
                local te = c.trim_end or 0
                local ed = (te > 0 and te or dur) - ts
                if ed > 0 then total_len = total_len + ed end
              end
            elseif c.type == "GROUP" then
              local gd = FUNC.calc_group_dur and FUNC.calc_group_dur(c) or 0
              if gd and gd > 0 then total_len = total_len + gd end
            end
          end
          -- Channel統計: 收集route_hw的distinct channels -- count distinct channels
          if c.route_hw then
            for _, rh in ipairs(c.route_hw) do
              if rh.ch >= 0 then used_channels[rh.ch] = true end
            end
          end
        end
      end
      ImGui.Text(ctx, "Length"); ImGui.SameLine(ctx, slbl_w)
      -- timecode格式 HH:MM:SS -- HH:MM:SS timecode format
      local hh = math.floor(total_len / 3600)
      local mm = math.floor((total_len % 3600) / 60)
      local ss = total_len % 60
      ImGui.Text(ctx, string.format("%02d:%02d:%04.1f", hh, mm, ss))

      -- Cues / Groups -- Cue數量/Group數量
      ImGui.Text(ctx, "Cues"); ImGui.SameLine(ctx, slbl_w)
      ImGui.Text(ctx, string.format("%d cues / %d groups", cue_count, grp_count))

      -- Channels -- 已使用的route channel數量
      local ch_count = 0
      for _ in pairs(used_channels) do ch_count = ch_count + 1 end
      ImGui.Text(ctx, "Channels"); ImGui.SameLine(ctx, slbl_w)
      ImGui.Text(ctx, tostring(ch_count))

      -- ── Notes ── 專案備註（左右下留4px，上方緊貼separator）
      ImGui.Dummy(ctx, 0, FUNC.sz(4))
      ImGui.PushStyleColor(ctx, ImGui.Col_Text(), C.dim)
      ImGui.Text(ctx, "Notes")
      ImGui.PopStyleColor(ctx, 1)
      ImGui.Separator(ctx)
      local np = FUNC.sz(4)
      local notes_cx = ImGui.GetCursorPosX(ctx)
      local notes_avail = ImGui.GetContentRegionAvail(ctx)
      ImGui.SetCursorPosX(ctx, notes_cx + np)
      local nch, nnv = ImGui.InputTextMultiline(ctx, "##proj_notes", project_notes,
        notes_avail - np * 2, FUNC.sz(60), ImGui.InputTextFlags_None())
      if nch then project_notes = nnv end
      pref_notes_active = ImGui.IsItemActive(ctx)  -- 記錄notes是否在編輯中 -- track notes edit state
      ImGui.Dummy(ctx, 0, np)

      -- ── Settings ── 設定
      ImGui.Dummy(ctx, 0, FUNC.sz(4))
      ImGui.PushStyleColor(ctx, ImGui.Col_Text(), C.dim)
      ImGui.Text(ctx, "Settings")
      ImGui.PopStyleColor(ctx, 1)
      ImGui.Separator(ctx)

      -- helper: vdrag後檢查是否剛結束輸入 -- check if input just committed (blocks Enter from reaching Save)
      local function vd_check() if ImGui.IsItemDeactivatedAfterEdit(ctx) then pref_enter_consumed = true end end

      ImGui.Text(ctx, "Scale"); ImGui.SameLine(ctx, slbl_w)
      ImGui.SetNextItemWidth(ctx, -1)
      local sch, snv = ImGui.SliderInt(ctx, "##scale", prefs.scale, 50, 200, "%d%%")
      if sch then prefs.scale = snv end

      ImGui.Text(ctx, "Fade Time"); ImGui.SameLine(ctx, slbl_w)
      local fch, fnv = FUNC.vdrag("pref_dft", prefs.default_fade_time, 0.1, 0.5, 60, "%.1f s")
      if fch then prefs.default_fade_time = fnv end; vd_check()

      ImGui.Text(ctx, "Soft Kill"); ImGui.SameLine(ctx, slbl_w)
      local skch, sknv = FUNC.vdrag("pref_skt", prefs.soft_kill_time, 0.05, 0, 10, "%.1f s")
      if skch then prefs.soft_kill_time = sknv end; vd_check()

      ImGui.Text(ctx, "Dyn Range"); ImGui.SameLine(ctx, slbl_w)
      local dr_w = (mid_w - mid_pad * 2 - slbl_w - FUNC.sz(30)) * 0.5  -- 扣掉padding -- subtract padding from width calc
      local vmn_ch, vmn_nv = FUNC.vdrag("pref_vmin", prefs.vol_min, 1, -120, 0, "%.0f dB", nil, dr_w)
      if vmn_ch then prefs.vol_min = vmn_nv; prefs.inf_db = prefs.vol_min; FUNC.update_env_bounds() end; vd_check()
      ImGui.SameLine(ctx, 0, FUNC.sz(2))
      ImGui.Text(ctx, "~"); ImGui.SameLine(ctx, 0, FUNC.sz(2))
      local vmx_ch, vmx_nv = FUNC.vdrag("pref_vmax", prefs.vol_max, 1, 0, 36, "%.0f dB", nil, dr_w)
      if vmx_ch then prefs.vol_max = vmx_nv; FUNC.update_env_bounds() end; vd_check()

      ImGui.Dummy(ctx, 0, FUNC.sz(2))
      local nrm_val = prefs.wf_normalize == 1
      local nrm_ch, nrm_nv = ImGui.Checkbox(ctx, "Normalize Waveform", nrm_val)
      if nrm_ch then prefs.wf_normalize = nrm_nv and 1 or 0 end

      local dn_val = prefs.default_negative == 1
      local dn_ch, dn_nv = ImGui.Checkbox(ctx, "Default Negative", dn_val)
      if dn_ch then prefs.default_negative = dn_nv and 1 or 0 end
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Input '3' → -3 dB (ON) or +3 dB (OFF)") end

      local tsl_val = prefs.track_sel_link == 1
      local tsl_ch, tsl_nv = ImGui.Checkbox(ctx, "Track Selection Link", tsl_val)
      if tsl_ch then prefs.track_sel_link = tsl_nv and 1 or 0 end
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Select corresponding REAPER track when clicking a cue") end

      local tcf_val = prefs.track_color_follow == 1
      local tcf_ch, tcf_nv = ImGui.Checkbox(ctx, "Track Color Follow Cue Color", tcf_val)
      if tcf_ch then
        prefs.track_color_follow = tcf_nv and 1 or 0
        if tcf_nv then
          FUNC.sync_all_cue_colors(true)
        else
          FUNC.clear_all_cue_colors_in_reaper()
        end
      end
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Sync REAPER track color (PLAY) and MIDI item color (MIDI) to cue color") end

      -- ── Output Maps 按鈕 ──
      ImGui.Dummy(ctx, 0, FUNC.sz(6)); ImGui.Separator(ctx); ImGui.Dummy(ctx, 0, 3)
      ImGui.PushStyleColor(ctx, ImGui.Col_Button(), FUNC.rgba(50, 70, 110))
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), FUNC.rgba(60, 85, 140))
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), FUNC.rgba(70, 100, 160))
      if ImGui.Button(ctx, "Output Maps", -1, FUNC.sz(26)) then
        popup.output_maps = true
      end
      ImGui.PopStyleColor(ctx, 3)

      -- ── 底部：Reset Project Data ── 移至最下方
      ImGui.Dummy(ctx, 0, FUNC.sz(6)); ImGui.Separator(ctx); ImGui.Dummy(ctx, 0, 3)
      ImGui.PushStyleColor(ctx, ImGui.Col_Button(), FUNC.rgba(130,40,40))
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), FUNC.rgba(160,50,50))
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), FUNC.rgba(180,60,60))
      if ImGui.Button(ctx, "Reset Project Data", -1, FUNC.sz(26)) then
        popup._reset_confirm = true
      end
      ImGui.PopStyleColor(ctx, 3)
      if popup._reset_confirm then
        ImGui.TextColored(ctx, FUNC.rgba(255,100,100), "Delete all cues and saved\ndata for this project?")
        if ImGui.Button(ctx, "Yes, Reset", FUNC.sz(100), FUNC.sz(24)) then
          FUNC.pv_stop_all(); FUNC.env_restore_all()
          cues = {}; selected = {}; next_go = 0; last_click = 0
          track_warns = {}; active_fades = {}; active_timers = {}
          active_previews = {}; paused_cues = {}; cancelled_fades = {}; soft_kill = {}
          show_name = ""; project_notes = ""; dirty = false
          reaper.SetProjExtState(0, EXT.SECTION, EXT.KEY, "")
          reaper.SetProjExtState(0, EXT.SECTION, "FocusCue", "")
          reaper.SetProjExtState(0, EXT.SECTION, "ShowName", "")
          reaper.SetProjExtState(0, EXT.SECTION, "ProjectNotes", "")
          popup._reset_confirm = false
        end
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, "Cancel", FUNC.sz(80), FUNC.sz(24)) then
          popup._reset_confirm = false
        end
      end
    end
    ImGui.EndChild(ctx)  -- ##pref_mid_inner
    end
    ImGui.EndChild(ctx)  -- ##pref_mid
    ImGui.SameLine(ctx, 0, 0)

    -- Right toggle (Shortcuts) -- 右側toggle
    if draw_tog("##tog_sc", tog_w, ch, not popup._pref_scuts) then
      popup._pref_scuts = not popup._pref_scuts
    end

    -- ═══════════════ RIGHT: Shortcuts ═══════════════
    if popup._pref_scuts then
      ImGui.SameLine(ctx, 0, 0)
      if ImGui.BeginChild(ctx, "##pref_sc", sc_w, ch) then
        -- 鍵盤監聽處理 -- keyboard listen mode: capture next keypress
        if scut_listen then
          if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape()) then
            scut_listen = nil
          else
            local detected = FUNC.detect_keypress()
            if detected then scut[scut_listen] = detected; scut_listen = nil end
          end
        end

        -- Collect shortcut categories -- 收集分類
        local cat_order = {}; local cat_items = {}
        for _, sd in ipairs(SC_DEFS) do
          if not cat_items[sd.cat] then cat_items[sd.cat] = {}; cat_order[#cat_order+1] = sd.cat end
          cat_items[sd.cat][#cat_items[sd.cat]+1] = sd
        end

        local lbl_w = FUNC.sz(120)
        local key_w = FUNC.sz(90)
        local btn_w = FUNC.sz(22)

        for sci, cat_name in ipairs(cat_order) do
          if sci > 1 then ImGui.Dummy(ctx, 0, FUNC.sz(4)) end
          ImGui.PushStyleColor(ctx, ImGui.Col_Text(), C.dim)
          ImGui.Text(ctx, cat_name)
          ImGui.PopStyleColor(ctx, 1)
          ImGui.Separator(ctx)

          for _, sd in ipairs(cat_items[cat_name]) do
            ImGui.Text(ctx, "  "..sd.name)
            ImGui.SameLine(ctx, lbl_w)

            -- Key display (blink when listening) -- 快捷鍵顯示（監聽中閃爍）
            local is_listening = (scut_listen == sd.id)
            if is_listening then
              local blink = math.floor(reaper.time_precise() * 3) % 2 == 0
              ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg(), FUNC.rgba(60,50,20))
              ImGui.PushStyleColor(ctx, ImGui.Col_Text(), blink and FUNC.rgba(255,200,80) or FUNC.rgba(180,140,50))
              ImGui.SetNextItemWidth(ctx, key_w)
              ImGui.InputText(ctx, "##sk_"..sd.id, "Press key...", ImGui.InputTextFlags_ReadOnly())
              ImGui.PopStyleColor(ctx, 2)
            else
              local modified = scut[sd.id] ~= sd.def
              if modified then ImGui.PushStyleColor(ctx, ImGui.Col_Text(), FUNC.rgba(120,200,255)) end
              ImGui.SetNextItemWidth(ctx, key_w)
              ImGui.InputText(ctx, "##sk_"..sd.id, scut[sd.id], ImGui.InputTextFlags_ReadOnly())
              if modified then ImGui.PopStyleColor(ctx, 1) end
            end

            -- Record button -- 錄製按鈕
            ImGui.SameLine(ctx, 0, FUNC.sz(4))
            if is_listening then
              ImGui.PushStyleColor(ctx, ImGui.Col_Button(), FUNC.rgba(140,100,20))
              ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), FUNC.rgba(160,120,30))
            else
              ImGui.PushStyleColor(ctx, ImGui.Col_Button(), FUNC.rgba(50,55,70))
              ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), FUNC.rgba(65,70,90))
            end
            ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), FUNC.rgba(80,85,110))
            if ImGui.Button(ctx, (is_listening and "..." or "◉").."##rec_"..sd.id, btn_w, 0) then
              scut_listen = is_listening and nil or sd.id
            end
            ImGui.PopStyleColor(ctx, 3)

            -- Reset button (only when modified) -- 重設按鈕（僅修改過時顯示）
            if scut[sd.id] ~= sd.def then
              ImGui.SameLine(ctx, 0, FUNC.sz(2))
              ImGui.PushStyleColor(ctx, ImGui.Col_Text(), C.dim)
              if ImGui.SmallButton(ctx, "x##rst_"..sd.id) then scut[sd.id] = sd.def end
              ImGui.PopStyleColor(ctx, 1)
              if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Reset to: "..sd.def) end
            end
          end
        end

        -- Waveform Mouse Wheel -- 波形滾輪modifier設定
        ImGui.Dummy(ctx, 0, FUNC.sz(6))
        ImGui.PushStyleColor(ctx, ImGui.Col_Text(), C.dim)
        ImGui.Text(ctx, "Waveform Mouse Wheel")
        ImGui.PopStyleColor(ctx, 1)
        ImGui.Separator(ctx)

        local ww_keys = {}
        for _, wd in ipairs(WF_WHEEL_DEFS) do
          local k = FUNC.wf_wheel_key(wf_wheel[wd.id])
          ww_keys[k] = (ww_keys[k] or 0) + 1
        end

        local cb_w = FUNC.sz(38)
        for _, wd in ipairs(WF_WHEEL_DEFS) do
          local w = wf_wheel[wd.id]
          local k = FUNC.wf_wheel_key(w)
          local conflict = ww_keys[k] > 1
          if conflict then
            ImGui.PushStyleColor(ctx, ImGui.Col_Text(), FUNC.rgba(255,60,60))
            ImGui.Text(ctx, "\xE2\x9A\xA0")
            ImGui.PopStyleColor(ctx, 1)
            if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Modifier conflict!") end
            ImGui.SameLine(ctx, 0, FUNC.sz(4))
          end
          ImGui.Text(ctx, "  "..wd.name)
          ImGui.SameLine(ctx, lbl_w)
          ImGui.SetNextItemWidth(ctx, cb_w)
          local wsch, wsnv = ImGui.Checkbox(ctx, "Shift##ww_s_"..wd.id, w.shift)
          if wsch then w.shift = wsnv end
          ImGui.SameLine(ctx, 0, FUNC.sz(6))
          ImGui.SetNextItemWidth(ctx, cb_w)
          local wcch, wcnv = ImGui.Checkbox(ctx, "Ctrl##ww_c_"..wd.id, w.ctrl)
          if wcch then w.ctrl = wcnv end
          ImGui.SameLine(ctx, 0, FUNC.sz(6))
          ImGui.SetNextItemWidth(ctx, cb_w)
          local wach, wanv = ImGui.Checkbox(ctx, "Alt##ww_a_"..wd.id, w.alt)
          if wach then w.alt = wanv end
          ImGui.SameLine(ctx, 0, FUNC.sz(6))
          local wrch, wrnv = ImGui.Checkbox(ctx, "Rev##ww_r_"..wd.id, w.rev)
          if wrch then w.rev = wrnv end
        end
      end
      ImGui.EndChild(ctx)
    end

    -- ─── Bottom: Save & Close ─── 底部儲存按鈕
    ImGui.Dummy(ctx, 0, FUNC.sz(2))
    ImGui.PushStyleColor(ctx, ImGui.Col_Button(), FUNC.rgba(40,100,40))
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), FUNC.rgba(50,130,50))
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), FUNC.rgba(60,150,60))
    -- Enter只在沒有輸入框活躍或剛結束編輯時觸發 -- Enter only when no input is active AND no input just committed
    local enter_ok = (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter()) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter()))
      and not ImGui.IsAnyItemActive(ctx) and not pref_notes_active and not scut_listen
      and not pref_enter_consumed
    if ImGui.Button(ctx, "Save & Close", -1, FUNC.sz(26)) or enter_ok then
      FUNC.save_prefs(); FUNC.save_shortcuts(); FUNC.save_wf_wheel()
      -- 儲存project notes -- save project notes
      reaper.SetProjExtState(0, EXT.SECTION, "ProjectNotes", project_notes or "")
      popup.settings = false; scut_listen = nil
    end
    ImGui.PopStyleColor(ctx, 3)

    ImGui.PopFont(ctx); ImGui.End(ctx)
  end
  if not op then popup.settings = false; scut_listen = nil end
  ImGui.PopStyleColor(ctx, 2)
end

---------------------------------------------------------------------
-- 17b. OUTPUT MAPS POPUP
---------------------------------------------------------------------
function FUNC.draw_output_maps()
  if not popup.output_maps then return end

  -- 初始化popup狀態 -- init popup state
  if not popup._omap then
    popup._omap = {
      edit_alias_idx = nil, edit_alias_buf = "", edit_num_idx = nil, edit_num_buf = "",
      sel = {},  -- {[oi]=true} 選取狀態 -- selection state
      last_click = nil,  -- 上次點擊的oi(shift select用) -- last clicked oi for shift-select
      marquee = nil,  -- {x0,y0,active} marquee selection
      drag_active = false, drag_payload = nil,  -- 拖曳中 -- dragging
      -- 可拖曳欄寬（從持久化讀取，或用預設值）-- resizable column widths (from persistence or defaults)
      col_num = omap_col_widths and omap_col_widths.num or FUNC.sz(36),
      col_name = omap_col_widths and omap_col_widths.name or FUNC.sz(130),
      resize_col = nil, resize_x0 = 0, resize_w0 = 0,
    }
  end
  local om = popup._omap

  -- 確保所有REAPER hw outputs都有map entry -- ensure all REAPER hw outputs have map entries
  local total_outs = reaper.GetNumAudioOutputs()
  for ch = 0, total_outs - 1 do FUNC.omap_ensure(ch) end
  -- 清理+補齊order -- clean and fill order
  local valid_order, in_order = {}, {}
  for _, ch in ipairs(output_map_order) do
    if ch < total_outs and output_map[ch] then valid_order[#valid_order+1] = ch; in_order[ch] = true end
  end
  for ch = 0, total_outs - 1 do
    if not in_order[ch] then valid_order[#valid_order+1] = ch end
  end
  output_map_order = valid_order

  local row_h = FUNC.sz(22)
  local win_w = FUNC.sz(480)
  local win_h = FUNC.sz(44) + row_h * math.min(total_outs, 16) + FUNC.sz(50)

  ImGui.SetNextWindowSize(ctx, win_w, win_h, ImGui.Cond_FirstUseEver())
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg(), FUNC.rgba(30, 30, 42))
  ImGui.PushStyleColor(ctx, ImGui.Col_TitleBgActive(), FUNC.rgba(50, 60, 90))
  local vis, op = ImGui.Begin(ctx, "Output Maps###OutputMaps", true,
    ImGui.WindowFlags_NoDocking() | ImGui.WindowFlags_NoCollapse())
  if vis then
    if popup_lost_focus() then op = false end  -- 失焦自動關閉
    ImGui.PushFont(ctx, FONT, FUNC.sz(12))

    -- 欄寬 -- column widths (resizable)
    local num_w = om.col_num
    local name_w = om.col_name
    local color_w = FUNC.sz(16)
    local pad = FUNC.sz(4)
    local hdr_h = FUNC.sz(18)

    -- ═══ 表頭（含拖曳調寬）═══ header with resizable dividers
    local hx, hy = ImGui.GetCursorScreenPos(ctx)
    local hdl = ImGui.GetWindowDrawList(ctx)
    local total_w = ImGui.GetContentRegionAvail(ctx)
    local alias_w = total_w - num_w - name_w - color_w - pad * 3
    if alias_w < FUNC.sz(40) then alias_w = FUNC.sz(40) end

    -- header texts
    ImGui.PushStyleColor(ctx, ImGui.Col_Text(), C.dim)
    -- # 置中 -- # centered
    local htxt = "#"
    local htw = ImGui.CalcTextSize(ctx, htxt)
    ImGui.DrawList_AddText(hdl, hx + (num_w - htw) * 0.5, hy, C.dim, htxt)
    -- Name
    ImGui.DrawList_AddText(hdl, hx + num_w + pad, hy, C.dim, "Name")
    -- Alias
    ImGui.DrawList_AddText(hdl, hx + num_w + pad + name_w + pad, hy, C.dim, "Alias")
    -- Col 置中 -- Col centered
    local ctxt = "Col"
    local ctw = ImGui.CalcTextSize(ctx, ctxt)
    ImGui.DrawList_AddText(hdl, hx + total_w - color_w + (color_w - ctw) * 0.5, hy, C.dim, ctxt)
    ImGui.PopStyleColor(ctx, 1)

    -- 欄位分隔拖曳區 -- column divider drag zones
    local div_w = FUNC.sz(6)
    local div_positions = {
      {x = hx + num_w, col = "col_num", min = FUNC.sz(24), max = FUNC.sz(80)},
      {x = hx + num_w + pad + name_w, col = "col_name", min = FUNC.sz(60), max = FUNC.sz(300)},
    }
    for di, dv in ipairs(div_positions) do
      ImGui.SetCursorScreenPos(ctx, dv.x - div_w * 0.5, hy)
      ImGui.InvisibleButton(ctx, "##omap_div" .. di, div_w, hdr_h)
      if ImGui.IsItemHovered(ctx) or (om.resize_col == dv.col) then
        ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeEW())
        ImGui.DrawList_AddLine(hdl, dv.x, hy, dv.x, hy + hdr_h, FUNC.rgba(120, 120, 150), 1)
      end
      if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left()) then
        om.resize_col = dv.col; om.resize_x0 = ImGui.GetMousePos(ctx); om.resize_w0 = om[dv.col]
      end
    end
    -- 處理拖曳中 -- handle resize drag
    if om.resize_col then
      if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left()) then
        local mx = ImGui.GetMousePos(ctx)
        local delta = mx - om.resize_x0
        for _, dv in ipairs(div_positions) do
          if dv.col == om.resize_col then
            local d = dv.invert and -delta or delta
            om[dv.col] = FUNC.clamp(math.floor(om.resize_w0 + d), dv.min, dv.max)
            break
          end
        end
      else
        -- 拖曳結束，儲存欄寬 -- resize ended, save column widths
        omap_col_widths = {num=om.col_num, name=om.col_name}
        FUNC.omap_save()
        om.resize_col = nil
      end
    end

    ImGui.SetCursorScreenPos(ctx, hx, hy + hdr_h)
    ImGui.Separator(ctx)

    -- ═══ 滾動區域 ═══ scrollable area
    local _, scroll_h = ImGui.GetContentRegionAvail(ctx)
    scroll_h = scroll_h - FUNC.sz(34)
    if ImGui.BeginChild(ctx, "##omap_scroll", -1, scroll_h) then
      local odl = ImGui.GetWindowDrawList(ctx)
      local fdl = ImGui.GetForegroundDrawList(ctx)  -- guide line用 -- for guide line
      local scroll_rx = ImGui.GetCursorScreenPos(ctx)

      -- 記錄每行位置(marquee + guide line用) -- record row positions
      local row_ys = {}

      om._just_dropped = nil  -- 每幀重設 -- reset each frame
      for oi, ch in ipairs(output_map_order) do
        local e = output_map[ch]
        if not e then goto omap_continue end
        local full_name = reaper.GetOutputChannelName(ch) or ("Out " .. (ch + 1))

        local rx, ry = ImGui.GetCursorScreenPos(ctx)
        local row_w = ImGui.GetContentRegionAvail(ctx)
        row_ys[oi] = ry

        -- recalc alias_w with current widths
        alias_w = row_w - num_w - name_w - color_w - pad * 3
        if alias_w < FUNC.sz(40) then alias_w = FUNC.sz(40) end

        -- 交替行背景 + 選取highlight -- alternating row bg + selection highlight
        local is_sel = om.sel[oi]
        if is_sel then
          ImGui.DrawList_AddRectFilled(odl, rx, ry, rx + row_w, ry + row_h, FUNC.rgba(60, 80, 120))
        elseif oi % 2 == 0 then
          ImGui.DrawList_AddRectFilled(odl, rx, ry, rx + row_w, ry + row_h, FUNC.rgba(40, 40, 55))
        end

        -- ─── 整行互動(選取+拖曳)，不覆蓋color欄 ─── full row interaction, excludes color column
        local row_interact_w = row_w - color_w - pad
        ImGui.SetCursorScreenPos(ctx, rx, ry)
        ImGui.InvisibleButton(ctx, "##orow" .. oi, row_interact_w, row_h)
        local row_hov = ImGui.IsItemHovered(ctx)

        -- 點擊選取: Shift/Cmd/普通（已選取的行不重設，允許多選拖曳）
        -- click select: already-selected rows don't reset (allows multi-drag)
        if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left()) then
          local shift = ImGui.IsKeyDown(ctx, ImGui.Mod_Shift())
          local cmd = ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl())
          if shift and om.last_click then
            local lo = math.min(om.last_click, oi)
            local hi = math.max(om.last_click, oi)
            if not cmd then om.sel = {} end
            for si = lo, hi do om.sel[si] = true end
          elseif cmd then
            om.sel[oi] = not om.sel[oi] or nil
          elseif not om.sel[oi] then
            -- 只有點到未選取的行才清空其他 -- only clear others when clicking unselected row
            om.sel = {}; om.sel[oi] = true
          end
          om.last_click = oi
          om._pending_desel = nil
        end
        -- 雙擊編輯：依滑鼠X判斷欄位 -- double-click edit by mouse X position
        if row_hov and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left()) then
          local mx = ImGui.GetMousePos(ctx)
          if mx < rx + num_w then
            om.edit_num_idx = oi; om.edit_num_buf = tostring(e.num); om.edit_num_focused = false
          elseif mx >= rx + num_w + pad + name_w + pad and mx < rx + row_w - color_w - pad then
            om.edit_alias_idx = oi; om.edit_alias_buf = e.alias; om.edit_alias_focused = false
          end
        end
        -- 延遲deselect：鬆開滑鼠且沒拖曳時，才縮減到單選（類似cue table的pending deselect）
        -- pending deselect: reduce to single on mouse release without drag
        if ImGui.IsItemDeactivated(ctx) and om.sel[oi] and not om.drag_active and not om._just_dropped then
          local shift = ImGui.IsKeyDown(ctx, ImGui.Mod_Shift())
          local cmd = ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl())
          if not shift and not cmd then
            local cnt = 0; for _ in pairs(om.sel) do cnt = cnt + 1 end
            if cnt > 1 then om.sel = {}; om.sel[oi] = true end
          end
        end

        -- DragDrop source (整行，支援多選拖曳) -- whole row drag source (multi-select aware)
        if ImGui.BeginDragDropSource(ctx, ImGui.DragDropFlags_SourceNoHoldToOpenOthers()) then
          -- 如果拖曳的行未被選取，先選它 -- select dragged row if not selected
          if not om.sel[oi] then om.sel = {}; om.sel[oi] = true end
          local sel_cnt = 0; for _ in pairs(om.sel) do sel_cnt = sel_cnt + 1 end
          ImGui.SetDragDropPayload(ctx, "OMAP_REORDER", tostring(oi))
          om.drag_active = true
          if sel_cnt > 1 then
            ImGui.Text(ctx, string.format("Moving %d channels", sel_cnt))
          else
            ImGui.Text(ctx, string.format("%d: %s", e.num, full_name))
          end
          ImGui.EndDragDropSource(ctx)
        end
        -- DragDrop target (僅guide line，不畫預設方框) -- drop target (guide line only, no default rect)
        if ImGui.BeginDragDropTarget(ctx) then
          ImGui.PushStyleColor(ctx, ImGui.Col_DragDropTarget(), 0)
          local payload = ImGui.AcceptDragDropPayload(ctx, "OMAP_REORDER", ImGui.DragDropFlags_AcceptNoDrawDefaultRect())
          if payload then
            local tgt_ch = output_map_order[oi]  -- capture BEFORE removal
            local sel_ois = {}
            for si in pairs(om.sel) do sel_ois[#sel_ois+1] = si end
            table.sort(sel_ois)
            local moved_chs = {}
            for i = #sel_ois, 1, -1 do
              local mi = sel_ois[i]
              if mi >= 1 and mi <= #output_map_order then
                table.insert(moved_chs, 1, table.remove(output_map_order, mi))
              end
            end
            local ins = #output_map_order + 1
            if tgt_ch then
              for ti, tc in ipairs(output_map_order) do
                if tc == tgt_ch then ins = ti; break end
              end
            end
            for mi, mc in ipairs(moved_chs) do
              table.insert(output_map_order, ins + mi - 1, mc)
            end
            om.sel = {}
            for mi = 0, #moved_chs - 1 do om.sel[ins + mi] = true end
            FUNC.omap_save()
            om.drag_active = false
            om._just_dropped = true
          end
          -- guide line (僅水平線) -- horizontal line only
          if om.drag_active then
            ImGui.DrawList_AddLine(fdl, rx, ry, rx + row_w, ry, FUNC.rgba(255, 200, 80), FUNC.sz(2))
          end
          ImGui.PopStyleColor(ctx, 1)
          ImGui.EndDragDropTarget(ctx)
        end

        -- ─── 編號（置中）─── number (centered)
        local num_x = rx
        if om.edit_num_idx == oi then
          ImGui.SetCursorScreenPos(ctx, num_x + FUNC.sz(2), ry + 1)
          ImGui.SetNextItemWidth(ctx, num_w - FUNC.sz(4))
          ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding(), 2, 1)
          local nch, nbuf = ImGui.InputText(ctx, "##onum_e" .. oi, om.edit_num_buf,
            ImGui.InputTextFlags_EnterReturnsTrue() | ImGui.InputTextFlags_AutoSelectAll() | ImGui.InputTextFlags_CharsDecimal())
          om.edit_num_buf = nbuf
          local ndeact_edit = ImGui.IsItemDeactivatedAfterEdit(ctx)
          local ndeact = ImGui.IsItemDeactivated(ctx)
          ImGui.PopStyleVar(ctx, 1)
          if not om.edit_num_focused then ImGui.SetKeyboardFocusHere(ctx, -1); om.edit_num_focused = true end
          -- Tab: commit + 跳下一列 (must check while active, before ImGui consumes Tab)
          if ImGui.IsItemActive(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Tab()) then
            local new_num = math.floor(tonumber(nbuf) or e.num)
            local dup = false
            for ch2, e2 in pairs(output_map) do if ch2 ~= ch and e2.num == new_num then dup = true; break end end
            if not dup and new_num ~= e.num then e.num = new_num; FUNC.omap_save() end
            om.edit_num_idx = nil
            if oi < #output_map_order then
              local nxt_ch = output_map_order[oi + 1]
              local nxt_e = nxt_ch and output_map[nxt_ch]
              if nxt_e then om.edit_num_idx = oi + 1; om.edit_num_buf = tostring(nxt_e.num); om.edit_num_focused = false end
            end
          elseif nch or ndeact_edit then
            local new_num = math.floor(tonumber(nbuf) or e.num)
            local dup = false
            for ch2, e2 in pairs(output_map) do if ch2 ~= ch and e2.num == new_num then dup = true; break end end
            if not dup and new_num ~= e.num then e.num = new_num; FUNC.omap_save() end
            om.edit_num_idx = nil
          elseif ndeact then om.edit_num_idx = nil end
        else
          -- 數字置中繪製 -- centered number text
          local nstr = tostring(e.num)
          local ntw = ImGui.CalcTextSize(ctx, nstr)
          ImGui.DrawList_AddText(odl, num_x + (num_w - ntw) * 0.5, ry + FUNC.sz(3), C.text, nstr)
        end

        -- ─── 全名(唯讀) ─── full name (read-only)
        local name_x = rx + num_w + pad
        ImGui.PushClipRect(ctx, name_x, ry, name_x + name_w, ry + row_h, true)
        ImGui.DrawList_AddText(odl, name_x, ry + FUNC.sz(3), FUNC.rgba(140, 140, 155), full_name)
        ImGui.PopClipRect(ctx)

        -- ─── 別稱 ─── alias
        local alias_x = rx + num_w + pad + name_w + pad
        if om.edit_alias_idx == oi then
          ImGui.SetCursorScreenPos(ctx, alias_x, ry + 1)
          ImGui.SetNextItemWidth(ctx, alias_w)
          ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding(), 2, 1)
          local ach, abuf = ImGui.InputText(ctx, "##oalias_e" .. oi, om.edit_alias_buf,
            ImGui.InputTextFlags_EnterReturnsTrue() | ImGui.InputTextFlags_AutoSelectAll())
          om.edit_alias_buf = abuf
          local adeact_edit = ImGui.IsItemDeactivatedAfterEdit(ctx)
          local adeact = ImGui.IsItemDeactivated(ctx)
          ImGui.PopStyleVar(ctx, 1)
          if not om.edit_alias_focused then ImGui.SetKeyboardFocusHere(ctx, -1); om.edit_alias_focused = true end
          -- Tab: commit + 跳下一列
          if ImGui.IsItemActive(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Tab()) then
            e.alias = abuf; FUNC.omap_save()
            om.edit_alias_idx = nil
            if oi < #output_map_order then
              local nxt_ch = output_map_order[oi + 1]
              local nxt_e = nxt_ch and output_map[nxt_ch]
              if nxt_e then om.edit_alias_idx = oi + 1; om.edit_alias_buf = nxt_e.alias; om.edit_alias_focused = false end
            end
          elseif ach or adeact_edit then
            e.alias = abuf; FUNC.omap_save()
            om.edit_alias_idx = nil
          elseif adeact then om.edit_alias_idx = nil end
        else
          local disp_alias = (e.alias ~= "" and e.alias ~= full_name) and e.alias or full_name
          ImGui.PushClipRect(ctx, alias_x, ry, alias_x + alias_w, ry + row_h, true)
          ImGui.DrawList_AddText(odl, alias_x, ry + FUNC.sz(3), C.text, disp_alias)
          ImGui.PopClipRect(ctx)
        end

        -- ─── 顏色（小方塊）─── color (small box)
        local col_x = rx + row_w - color_w
        local csz = color_w
        ImGui.SetCursorScreenPos(ctx, col_x, ry + (row_h - csz) * 0.5)
        if e.color >= 0 then
          ImGui.PushStyleColor(ctx, ImGui.Col_Button(), FUNC.col2im(e.color))
          ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), FUNC.col2im(e.color, 200))
          ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), FUNC.col2im(e.color, 255))
        else
          ImGui.PushStyleColor(ctx, ImGui.Col_Button(), FUNC.rgba(50, 50, 65))
          ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), FUNC.rgba(65, 65, 80))
          ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), FUNC.rgba(75, 75, 90))
        end
        if ImGui.Button(ctx, "##ocol" .. oi, csz, csz) then
          ImGui.OpenPopup(ctx, "##ocol_pick" .. oi)
        end
        ImGui.PopStyleColor(ctx, 3)

        -- color picker popup
        if ImGui.BeginPopup(ctx, "##ocol_pick" .. oi) then
          ImGui.Text(ctx, "Channel Color")
          ImGui.Separator(ctx)
          if ImGui.Selectable(ctx, "None##ocnone" .. oi) then
            -- 套用到所有選取 -- apply to all selected
            if om.sel[oi] then
              for si in pairs(om.sel) do
                local sch = output_map_order[si]
                if sch and output_map[sch] then output_map[sch].color = -1 end
              end
            else e.color = -1 end
            FUNC.omap_save()
          end
          local bsz = FUNC.sz(18)
          for ci2, cc in ipairs(CUE_COLORS) do
            if (ci2 - 1) % 12 ~= 0 then ImGui.SameLine(ctx, 0, 2) end
            local is_cur = (e.color == cc.val)
            ImGui.PushStyleColor(ctx, ImGui.Col_Button(), FUNC.col2im(cc.val))
            ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), FUNC.col2im(cc.val, 200))
            ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), FUNC.col2im(cc.val, 255))
            ImGui.PushStyleColor(ctx, ImGui.Col_Border(), is_cur and C.text or 0)
            ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize(), is_cur and 2 or 0)
            if ImGui.Button(ctx, "##occ" .. ci2 .. "_" .. oi, bsz, bsz) then
              if om.sel[oi] then
                for si in pairs(om.sel) do
                  local sch = output_map_order[si]
                  if sch and output_map[sch] then output_map[sch].color = cc.val end
                end
              else e.color = cc.val end
              FUNC.omap_save(); ImGui.CloseCurrentPopup(ctx)
            end
            ImGui.PopStyleVar(ctx, 1)
            ImGui.PopStyleColor(ctx, 4)
          end
          ImGui.EndPopup(ctx)
        end

        ImGui.SetCursorScreenPos(ctx, rx, ry + row_h)
        ::omap_continue::
      end

      -- ═══ Marquee selection ═══ 框選
      if not ImGui.IsAnyItemActive(ctx) and ImGui.IsWindowHovered(ctx) then
        if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left()) and not ImGui.IsKeyDown(ctx, ImGui.Mod_Shift()) and not ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl()) then
          local mx, my = ImGui.GetMousePos(ctx)
          om.marquee = {x0=mx, y0=my, active=true}
        end
      end
      if om.marquee and om.marquee.active then
        if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left()) then
          local mx, my = ImGui.GetMousePos(ctx)
          local m = om.marquee
          if math.abs(mx - m.x0) > 3 or math.abs(my - m.y0) > 3 then
            local my0 = math.min(m.y0, my)
            local my1 = math.max(m.y0, my)
            ImGui.DrawList_AddRectFilled(odl, m.x0, my0, mx, my1, FUNC.rgba(255, 200, 80, 30))
            ImGui.DrawList_AddRect(odl, m.x0, my0, mx, my1, FUNC.rgba(255, 200, 80, 120), 0, 0, 1)
            om.sel = {}
            for oi2, _ in ipairs(output_map_order) do
              local ry2 = row_ys[oi2]
              if ry2 then
                local rb = ry2 + row_h
                if ry2 < my1 and rb > my0 then om.sel[oi2] = true end
              end
            end
          end
        else
          om.marquee = nil
        end
      end

      -- drag結束清理 -- clean up drag state
      if om.drag_active and not ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left()) then
        om.drag_active = false
      end

      ImGui.EndChild(ctx)
    end

    -- 底部按鈕：Save | Cancel | (右) Reset All -- bottom buttons
    ImGui.Dummy(ctx, 0, FUNC.sz(2))
    local btn_h = FUNC.sz(24)
    local btn_w = FUNC.sz(80)

    -- Save
    ImGui.PushStyleColor(ctx, ImGui.Col_Button(), FUNC.rgba(40, 100, 40))
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), FUNC.rgba(50, 130, 50))
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), FUNC.rgba(60, 150, 60))
    local omap_enter = not ImGui.IsAnyItemActive(ctx)
      and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter()) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter()))
    if ImGui.Button(ctx, "Save", btn_w, btn_h) or omap_enter then
      omap_col_widths = {num=om.col_num, name=om.col_name}
      FUNC.omap_save()
      popup.output_maps = false; popup._omap = nil
    end
    ImGui.PopStyleColor(ctx, 3)

    -- Cancel
    ImGui.SameLine(ctx, 0, FUNC.sz(4))
    if ImGui.Button(ctx, "Cancel", btn_w, btn_h) then
      -- 重新載入(丟棄未儲存的變更) -- reload (discard unsaved changes)
      FUNC.omap_load()
      local to2 = reaper.GetNumAudioOutputs()
      for ch2 = 0, to2 - 1 do FUNC.omap_ensure(ch2) end
      popup.output_maps = false; popup._omap = nil
    end

    -- Reset All (靠右) -- right-aligned
    local reset_w = FUNC.sz(80)
    local content_w = ImGui.GetContentRegionAvail(ctx)
    local cur_x = ImGui.GetCursorPosX(ctx)
    local target_x = cur_x + content_w - reset_w
    ImGui.SameLine(ctx, target_x)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button(), FUNC.rgba(90, 60, 50))
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), FUNC.rgba(120, 70, 55))
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), FUNC.rgba(140, 80, 60))
    if ImGui.Button(ctx, "Reset All", reset_w, btn_h) then
      for ch2, e2 in pairs(output_map) do
        e2.num = ch2 + 1
        e2.alias = reaper.GetOutputChannelName(ch2) or ("Out " .. (ch2 + 1))
        e2.color = -1
      end
      output_map_order = {}
      for ch2 = 0, total_outs - 1 do output_map_order[#output_map_order+1] = ch2 end
    end
    ImGui.PopStyleColor(ctx, 3)
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Reset all numbers, aliases, colors and order to defaults") end

    ImGui.PopFont(ctx)
    ImGui.End(ctx)
  end
  if not op then
    -- X按鈕關閉 = Cancel(重新載入) -- X close = Cancel (reload)
    FUNC.omap_load()
    local to2 = reaper.GetNumAudioOutputs()
    for ch2 = 0, to2 - 1 do FUNC.omap_ensure(ch2) end
    popup.output_maps = false; popup._omap = nil
  end
  ImGui.PopStyleColor(ctx, 2)
end

---------------------------------------------------------------------
-- 18. SAVE/LOAD POPUPS
---------------------------------------------------------------------
function FUNC.draw_save_popup()
  if not popup.save then return end
  ImGui.SetNextWindowSize(ctx, FUNC.sz(340), FUNC.sz(140), ImGui.Cond_FirstUseEver())
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg(), FUNC.rgba(35,35,45))
  local vis, op = ImGui.Begin(ctx, "Save Show###SaveShow", true, ImGui.WindowFlags_NoDocking())
  if vis then
    if popup_lost_focus() then op = false end  -- 失焦自動關閉
    ImGui.PushFont(ctx, FONT, FUNC.sz(14))
    ImGui.Text(ctx, "Show title:")
    ImGui.SetNextItemWidth(ctx, -1)
    local ch, nv = ImGui.InputText(ctx, "##stitle", popup.save_title_buf)
    if ch then popup.save_title_buf = nv end

    ImGui.Dummy(ctx, 0, FUNC.sz(4))

    -- Buttons: Save or Overwrite | Cancel
    if popup.save_overwrite then
      ImGui.PushStyleColor(ctx, ImGui.Col_Button(), FUNC.rgba(140,60,40))
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), FUNC.rgba(170,70,50))
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), FUNC.rgba(190,80,60))
      if ImGui.Button(ctx, "Overwrite", FUNC.sz(80), FUNC.sz(26)) then
        FUNC.save_show(popup.save_title_buf); popup.save = false; popup.save_overwrite = false
      end
      ImGui.PopStyleColor(ctx, 3)
    else
      ImGui.PushStyleColor(ctx, ImGui.Col_Button(), FUNC.rgba(40,100,40))
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), FUNC.rgba(50,130,50))
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), FUNC.rgba(60,150,60))
      if (ImGui.Button(ctx, "Save", FUNC.sz(80), FUNC.sz(26)) or popup_enter_pressed()) and popup.save_title_buf ~= "" then
        local exists = false
        for _, t in ipairs(FUNC.get_show_titles()) do if t == popup.save_title_buf then exists = true; break end end
        if exists then popup.save_overwrite = true
        else FUNC.save_show(popup.save_title_buf); popup.save = false end
      end
      ImGui.PopStyleColor(ctx, 3)
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel", FUNC.sz(80), FUNC.sz(26)) then
      if not popup.save_overwrite then popup.save = false end
      popup.save_overwrite = false
    end

    ImGui.Dummy(ctx, 0, FUNC.sz(2))

    -- Status / warning line (always reserved)
    if popup.save_overwrite then
      ImGui.PushStyleColor(ctx, ImGui.Col_Text(), FUNC.rgba(255,200,80))
      ImGui.Text(ctx, "\""..popup.save_title_buf.."\" already exists. Overwrite?")
      ImGui.PopStyleColor(ctx, 1)
    else
      ImGui.Dummy(ctx, 0, ImGui.GetTextLineHeightWithSpacing(ctx))
    end

    ImGui.Dummy(ctx, 0, FUNC.sz(2))

    ImGui.PopFont(ctx); ImGui.End(ctx)
  end
  if not op then popup.save = false end
  ImGui.PopStyleColor(ctx, 1)
end

function FUNC.draw_load_popup()
  if not popup.load then return end
  ImGui.SetNextWindowSize(ctx, FUNC.sz(380), FUNC.sz(300), ImGui.Cond_FirstUseEver())
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg(), FUNC.rgba(35,35,45))
  local vis, op = ImGui.Begin(ctx, "Load Show###LoadShow", true, ImGui.WindowFlags_NoDocking())
  if vis then
    if popup_lost_focus() then op = false end  -- 失焦自動關閉
    ImGui.PushFont(ctx, FONT, FUNC.sz(14))
    local titles = FUNC.get_show_titles()
    if #titles == 0 then
      ImGui.PushStyleColor(ctx, ImGui.Col_Text(), C.dim)
      ImGui.Text(ctx, "No saved shows"); ImGui.PopStyleColor(ctx, 1)
    else
      ImGui.Text(ctx, "Saved shows:")
      ImGui.Dummy(ctx, 0, 3)
      if ImGui.BeginChild(ctx, "showlist", -1, -FUNC.sz(36), ImGui.ChildFlags_Borders()) then
        for _, t in ipairs(titles) do
          if ImGui.Selectable(ctx, t, popup.load_sel == t) then popup.load_sel = t end
        end
        ImGui.EndChild(ctx)
      end
    end

    ImGui.PushStyleColor(ctx, ImGui.Col_Button(), FUNC.rgba(40,80,130))
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), FUNC.rgba(50,100,160))
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), FUNC.rgba(60,110,170))
    if ImGui.Button(ctx, "Load", FUNC.sz(80), FUNC.sz(26)) or popup_enter_pressed() then
      if popup.load_sel ~= "" then FUNC.load_show(popup.load_sel); popup.load = false end
    end
    ImGui.PopStyleColor(ctx, 3)
    ImGui.SameLine(ctx)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button(), FUNC.rgba(130,50,40))
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), FUNC.rgba(160,60,50))
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), FUNC.rgba(180,70,60))
    if not popup._del_confirm then
      -- 第一次按：進入確認狀態 -- first press: enter confirm state
      if ImGui.Button(ctx, "Delete", FUNC.sz(80), FUNC.sz(26)) then
        if popup.load_sel ~= "" then popup._del_confirm = popup.load_sel end
      end
    else
      -- 確認刪除狀態：按鈕變文字提示 -- confirm state: button becomes warning
      if ImGui.Button(ctx, "Confirm?", FUNC.sz(80), FUNC.sz(26)) then
        FUNC.delete_show(popup._del_confirm); popup.load_sel = ""; popup._del_confirm = nil
      end
    end
    ImGui.PopStyleColor(ctx, 3)
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel", FUNC.sz(80), FUNC.sz(26)) then popup.load = false; popup._del_confirm = nil end
    -- 選了不同項目或取消選取時，重置確認狀態 -- reset confirm when selection changes
    if popup._del_confirm and popup.load_sel ~= popup._del_confirm then popup._del_confirm = nil end

    ImGui.PopFont(ctx); ImGui.End(ctx)
  end
  if not op then popup.load = false end
  ImGui.PopStyleColor(ctx, 1)
end

---------------------------------------------------------------------
-- 19. TRIM
---------------------------------------------------------------------
function FUNC.draw_trim()
  if not popup.trim then return end
  if popup.trim_ci < 1 or popup.trim_ci > #cues then popup.trim = false; return end
  local c = cues[popup.trim_ci]
  if c.type ~= "PLAY" then popup.trim = false; return end
  local dur = FUNC.calc_dur(c.track_idx)
  if dur <= 0 then popup.trim = false; return end
  if c.trim_end <= 0 or c.trim_end > dur then c.trim_end = dur end

  ImGui.SetNextWindowSize(ctx, FUNC.sz(480), FUNC.sz(160), ImGui.Cond_FirstUseEver())
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg(), FUNC.rgba(30,30,40))
  local vis, op = ImGui.Begin(ctx, "Trim Q."..c.cue_number.."###Trim", true, ImGui.WindowFlags_NoDocking())
  if vis then
    if popup_lost_focus() then op = false end  -- 失焦自動關閉
    ImGui.PushFont(ctx, FONT, FUNC.sz(14))
    ImGui.Text(ctx, string.format("Total: %s  Effective: %s", FUNC.fmt_t(dur), FUNC.fmt_t(c.trim_end - c.trim_start)))
    ImGui.Dummy(ctx, 0, 3)

    local aw = ImGui.GetContentRegionAvail(ctx)
    local bar_h = FUNC.sz(30)
    local cx, cy = ImGui.GetCursorScreenPos(ctx)
    local dl2 = ImGui.GetWindowDrawList(ctx)
    ImGui.DrawList_AddRectFilled(dl2, cx, cy, cx+aw, cy+bar_h, FUNC.rgba(50,50,65), 4)
    -- Waveform blocks per item
    local items = FUNC.get_items(c.track_idx)
    if #items > 0 then
      local base = items[1].pos
      for _, it in ipairs(items) do
        local x0 = cx + aw * ((it.pos - base) / dur)
        local x1 = cx + aw * ((it.pos - base + it.len) / dur)
        ImGui.DrawList_AddRectFilled(dl2, x0, cy+FUNC.sz(4), x1, cy+bar_h-FUNC.sz(4), FUNC.rgba(100,140,180,120), 2)
      end
    end
    local sx = cx + aw * (c.trim_start / dur)
    local ex = cx + aw * (c.trim_end / dur)
    ImGui.DrawList_AddRectFilled(dl2, sx, cy, ex, cy+bar_h, FUNC.rgba(60,140,200,150), 4)
    ImGui.DrawList_AddRectFilled(dl2, sx, cy, sx+FUNC.sz(3), cy+bar_h, FUNC.rgba(255,255,255,200))
    ImGui.DrawList_AddRectFilled(dl2, ex-FUNC.sz(3), cy, ex, cy+bar_h, FUNC.rgba(255,255,255,200))
    ImGui.Dummy(ctx, aw, bar_h)
    ImGui.Dummy(ctx, 0, 3)

    ImGui.Text(ctx, "Start"); ImGui.SameLine(ctx, FUNC.sz(50)); ImGui.SetNextItemWidth(ctx, -1)
    local sch, snv = ImGui.SliderDouble(ctx, "##ts", c.trim_start, 0, c.trim_end-0.01, "%.2f s")
    if sch then c.trim_start = snv; FUNC.save_cues() end
    ImGui.Text(ctx, "End"); ImGui.SameLine(ctx, FUNC.sz(50)); ImGui.SetNextItemWidth(ctx, -1)
    local ech, env = ImGui.SliderDouble(ctx, "##te", c.trim_end, c.trim_start+0.01, dur, "%.2f s")
    if ech then c.trim_end = env; FUNC.save_cues() end
    if ImGui.Button(ctx, "Reset", FUNC.sz(60), FUNC.sz(22)) then c.trim_start=0; c.trim_end=dur; FUNC.save_cues() end
    -- Enter關閉trim popup -- Enter closes trim popup
    if popup_enter_pressed() then popup.trim = false end

    ImGui.PopFont(ctx); ImGui.End(ctx)
  end
  if not op then popup.trim = false end
  ImGui.PopStyleColor(ctx, 1)
end

---------------------------------------------------------------------
-- 19.5 FADE CURVE EDIT
---------------------------------------------------------------------
function FUNC.draw_fade_edit()
  if not popup.fade_edit then return end
  if popup.fade_edit_ci < 1 or popup.fade_edit_ci > #cues then popup.fade_edit = false; return end
  local c = cues[popup.fade_edit_ci]
  if c.type ~= "FADE" then popup.fade_edit = false; return end

  ImGui.SetNextWindowSize(ctx, FUNC.sz(340), FUNC.sz(340), ImGui.Cond_FirstUseEver())  -- 加高容納rate/pitch -- taller for rate/pitch controls
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg(), FUNC.rgba(30,30,40))
  local vis, op = ImGui.Begin(ctx, "Fade Q."..c.cue_number.."###FadeEdit", true, ImGui.WindowFlags_NoDocking())
  if vis then
    if popup_lost_focus() then op = false end  -- 失焦自動關閉
    ImGui.PushFont(ctx, FONT, FUNC.sz(14))

    -- Curve type buttons -- 曲線類型按鈕
    ImGui.Text(ctx, "Curve")
    ImGui.SameLine(ctx, FUNC.sz(60))
    for ki, cv in ipairs(CURVES) do
      if ki > 1 then ImGui.SameLine(ctx, 0, 3) end
      local is_cur = c.fade_curve == cv
      if is_cur then
        ImGui.PushStyleColor(ctx, ImGui.Col_Button(), C.accent)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), C.accent)
      end
      if ImGui.Button(ctx, CURVE_N[cv].."##fcv", FUNC.sz(60), FUNC.sz(24)) then
        c.fade_curve = cv
        local r = CURVE_AMT[cv]
        if r and (c.fade_curve_amt < r.lo or c.fade_curve_amt > r.hi) then c.fade_curve_amt = r.def end
        FUNC.save_cues()
      end
      if is_cur then ImGui.PopStyleColor(ctx, 2) end
    end

    local _, tc = FUNC.get_target(c)
    local from_vol = tc and tc.volume or 0
    local to_vol = c.volume
    local fade_in = to_vol > from_vol
    local r = CURVE_AMT[c.fade_curve]
    if r then
      ImGui.SameLine(ctx, 0, FUNC.sz(8))
      -- 凹=負/凸=正 直覺顯示：fade-down 時 expo 顯示反號 -- invert sign on fade-down so concave=negative
      local flip = (c.fade_curve == "expo") and (not fade_in)
      local disp = flip and -c.fade_curve_amt or c.fade_curve_amt
      local ach, anv = FUNC.vdrag("fcv_amt", disp, r.spd, r.lo, r.hi, "%.2f")
      if ach then c.fade_curve_amt = flip and -anv or anv; FUNC.save_cues() end
    end

    ImGui.Dummy(ctx, 0, FUNC.sz(4))

    local pw = ImGui.GetContentRegionAvail(ctx)
    local ph = FUNC.sz(100)
    local cx, cy = ImGui.GetCursorScreenPos(ctx)
    local dl2 = ImGui.GetWindowDrawList(ctx)
    ImGui.DrawList_AddRectFilled(dl2, cx, cy, cx+pw, cy+ph, FUNC.rgba(20,20,30), 4)
    -- 曲線繪製區加padding，四角文字不跟線疊 -- curve area padding in popup
    local pp_l, pp_r = FUNC.sz(6), FUNC.sz(6)
    local pp_t, pp_b = FUNC.sz(22), FUNC.sz(22)
    local pa_x, pa_y = cx + pp_l, cy + pp_t
    local pa_w, pa_h = pw - pp_l - pp_r, ph - pp_t - pp_b
    -- Grid lines (within padded area)
    for gi = 1, 3 do
      local gy = pa_y + pa_h * gi / 4
      ImGui.DrawList_AddLine(dl2, pa_x, gy, pa_x+pa_w, gy, FUNC.rgba(50,50,65), 1)
    end
    -- Volume labels (scale vol_max ~ vol_min dB) -- 刻度標示跟隨prefs
    ImGui.DrawList_AddText(dl2, cx + FUNC.sz(4), cy + FUNC.sz(2),
      FUNC.rgba(255,255,255), string.format("%+d dB", prefs.vol_max))
    ImGui.DrawList_AddText(dl2, cx + FUNC.sz(4), cy + ph - FUNC.sz(14),
      FUNC.rgba(255,255,255), string.format("%d dB", math.max(prefs.vol_min, -60)))
    -- Draw curve (within padded area, vol_max ~ display floor dB range) -- dB範圍繪製曲線
    local db_top, db_bot = prefs.vol_max, math.max(prefs.vol_min, -60)
    local db_rng = db_top - db_bot -- 72
    local steps = 60
    for si = 0, steps-1 do
      local t0 = si / steps; local t1 = (si+1) / steps
      local cv0 = FUNC.crv(t0, c.fade_curve, c.fade_curve_amt)
      local cv1 = FUNC.crv(t1, c.fade_curve, c.fade_curve_amt)
      local db0 = from_vol + (to_vol - from_vol) * cv0
      local db1 = from_vol + (to_vol - from_vol) * cv1
      local x0 = pa_x + pa_w * t0; local x1 = pa_x + pa_w * t1
      local y0 = pa_y + pa_h * (db_top - db0) / db_rng
      local y1 = pa_y + pa_h * (db_top - db1) / db_rng
      ImGui.DrawList_AddLine(dl2, x0, y0, x1, y1, C.p_fade, FUNC.sz(2))
    end
    -- fade播放中黃色圓點沿曲線移動 -- fade running indicator dot on curve
    if c.state == STATE.RUNNING and c.play_t0 > 0 and c.fade_time > 0 then
      local elapsed = reaper.time_precise() - c.play_t0
      local prog = FUNC.clamp(elapsed / c.fade_time, 0, 1)
      local cv_val = FUNC.crv(prog, c.fade_curve, c.fade_curve_amt)
      local db_cur = from_vol + (to_vol - from_vol) * cv_val
      local dot_x = pa_x + pa_w * prog
      local dot_y = pa_y + pa_h * (db_top - db_cur) / db_rng
      ImGui.DrawList_AddCircleFilled(dl2, dot_x, dot_y, FUNC.sz(5), FUNC.rgba(255, 220, 50), 0)
      ImGui.DrawList_AddCircle(dl2, dot_x, dot_y, FUNC.sz(5), FUNC.rgba(255, 255, 255, 180), 0, 1.5)
      -- 即時rate/pitch值顯示在右上角 -- live rate/pitch display during fade
      local info_parts = {}
      if tc and tc.preview_ids then
        for _, pid in ipairs(tc.preview_ids) do
          if active_previews[pid] then
            info_parts[#info_parts+1] = string.format("Pitch: %+.1fst", FUNC.pv_get_pitch(pid))
            info_parts[#info_parts+1] = string.format("Pan: %.0f%%", FUNC.pv_get_pan(pid)*100)
            break
          end
        end
      end
      if #info_parts > 0 then
        local info_txt = table.concat(info_parts, "  ")
        local tw = ImGui.CalcTextSize(ctx, info_txt)
        ImGui.DrawList_AddText(dl2, cx + pw - tw - FUNC.sz(6), cy + FUNC.sz(2), FUNC.rgba(255, 220, 80), info_txt)
      end
    end
    ImGui.DrawList_AddRect(dl2, cx, cy, cx+pw, cy+ph, FUNC.rgba(60,60,80), 4, 0, 1)
    ImGui.Dummy(ctx, pw, ph)
    ImGui.Dummy(ctx, 0, FUNC.sz(4))

    -- Fade time
    ImGui.Text(ctx, "Time"); ImGui.SameLine(ctx, FUNC.sz(60)); ImGui.SetNextItemWidth(ctx, -1)
    local tch, tnv = ImGui.SliderDouble(ctx, "##ft", c.fade_time, 0.1, 120, "%.1f s")
    if tch then c.fade_time = tnv; FUNC.save_cues() end

    -- Target volume
    ImGui.Text(ctx, "To Vol"); ImGui.SameLine(ctx, FUNC.sz(60)); ImGui.SetNextItemWidth(ctx, -1)
    local vch, vnv = ImGui.SliderDouble(ctx, "##fv", c.volume, prefs.vol_min, prefs.vol_max, "%.1f dB")
    if vch then c.volume = vnv; FUNC.save_cues() end

    -- Pitch漸變（永遠啟用）-- Pitch fade (always enabled)
    ImGui.Text(ctx, "Pitch"); ImGui.SameLine(ctx, FUNC.sz(60)); ImGui.SetNextItemWidth(ctx, -1)
    local fpch, fpnv = ImGui.SliderDouble(ctx, "##fp", c.fade_pitch or 0, -24, 24, "%.1f st")
    if fpch then c.fade_pitch = fpnv; FUNC.save_cues() end

    -- Pan漸變（永遠啟用）-- Pan fade (always enabled)
    ImGui.Text(ctx, "Pan"); ImGui.SameLine(ctx, FUNC.sz(60)); ImGui.SetNextItemWidth(ctx, -1)
    local fpanch, fpannv = ImGui.SliderDouble(ctx, "##fpan", c.fade_pan or 0, -1, 1, "%.2f")
    if fpanch then c.fade_pan = fpannv; FUNC.save_cues() end
    -- Enter關閉fade edit popup -- Enter closes fade edit popup
    if popup_enter_pressed() then popup.fade_edit = false end

    ImGui.PopFont(ctx); ImGui.End(ctx)
  end
  if not op then popup.fade_edit = false end
  ImGui.PopStyleColor(ctx, 1)
end

---------------------------------------------------------------------
-- 19.6 TRACK WARNING POPUP
---------------------------------------------------------------------
function FUNC.draw_warn_popup()
  if not popup.warn then return end
  local ci = popup.warn_ci
  local c = cues[ci]
  if not c then popup.warn = false; return end
  local w = track_warns[c.id]
  if not w then popup.warn = false; return end

  ImGui.SetNextWindowFocus(ctx)
  ImGui.SetNextWindowSizeConstraints(ctx, FUNC.sz(340), 0, FUNC.sz(340), FUNC.sz(600))
  ImGui.PushStyleColor(ctx, ImGui.Col_TitleBg(), FUNC.rgba(120,40,35))
  ImGui.PushStyleColor(ctx, ImGui.Col_TitleBgActive(), FUNC.rgba(140,50,40))
  local vis, op = ImGui.Begin(ctx, "WARNING!###warn_popup", true, ImGui.WindowFlags_NoCollapse() | ImGui.WindowFlags_AlwaysAutoResize() | ImGui.WindowFlags_NoResize())
  if vis then
    local trk_info = "Track " .. tostring(c.track_idx + 1) .. ": " .. FUNC.tr_name(c.track_idx)
    ImGui.Text(ctx, trk_info .. "\nhas been changed by REAPER track control panel!")
    ImGui.Spacing(ctx); ImGui.Separator(ctx); ImGui.Spacing(ctx)

    -- Itemize warnings
    if w.vol then
      ImGui.TextColored(ctx, FUNC.rgba(255,180,80), "Volume: " .. w.vol)
    end
    if w.pan then
      ImGui.TextColored(ctx, FUNC.rgba(255,200,80), "Pan: " .. w.pan)
    end

    ImGui.Spacing(ctx); ImGui.Separator(ctx); ImGui.Spacing(ctx)
    local avail_w = ImGui.GetContentRegionAvail(ctx)
    local btn_w = math.floor((avail_w - FUNC.sz(8)) / 2)
    local btn_h = FUNC.sz(28)

    -- APPLY: accept REAPER's changes into the cue
    if ImGui.Button(ctx, "APPLY", btn_w, btn_h) then
      local tr = FUNC.get_tr(c.track_idx)
      if tr then
        if w.vol then
          -- 把手動改的D_VOL寫進cue volume（dB），再歸零讓envelope接管
          local vol_db = w.vol_val > 0 and (20 * math.log(w.vol_val, 10)) or prefs.vol_min
          c.volume = vol_db
          reaper.SetMediaTrackInfo_Value(tr, "D_VOL", 1.0)
        end
        if w.pan then c.pan = w.pan_val end
      end
      track_warns[c.id] = nil
      popup.warn = false
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Apply volume change to cue volume and reset reaet track to 0dB")
    end
    ImGui.SameLine(ctx)
    -- RESTORE: revert REAPER track to match the cue
    if ImGui.Button(ctx, "RESTORE", btn_w, btn_h) then
      local tr = FUNC.get_tr(c.track_idx)
      if tr then
        if w.vol then reaper.SetMediaTrackInfo_Value(tr, "D_VOL", 1.0) end  -- 歸零，envelope接管
        if w.pan then
          reaper.SetMediaTrackInfo_Value(tr, "D_PAN", 0)  -- track pan歸零（留給envelope）
          if c.preview_ids then for _, pid in ipairs(c.preview_ids) do FUNC.pv_set_pan(pid, c.pan or 0) end end
        end
      end
      track_warns[c.id] = nil
      popup.warn = false
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Discard the change and restore to cue's original value")
    end

    ImGui.End(ctx)
  end
  if not op then popup.warn = false end
  ImGui.PopStyleColor(ctx, 2)
end

---------------------------------------------------------------------
-- 19.6b MISSING TRACK POPUP — track遺失時的處理popup
---------------------------------------------------------------------
function FUNC.draw_warn_missing_popup()
  if not popup.warn_missing then return end
  local ci = popup.warn_missing_ci
  local c = cues[ci]
  if not c then popup.warn_missing = false; return end

  ImGui.SetNextWindowFocus(ctx)
  ImGui.SetNextWindowSizeConstraints(ctx, FUNC.sz(320), 0, FUNC.sz(320), FUNC.sz(400))
  ImGui.PushStyleColor(ctx, ImGui.Col_TitleBg(), FUNC.rgba(120,40,35))
  ImGui.PushStyleColor(ctx, ImGui.Col_TitleBgActive(), FUNC.rgba(140,50,40))
  local vis, op = ImGui.Begin(ctx, "Source Missing###warn_missing_popup", true,
    ImGui.WindowFlags_NoCollapse() | ImGui.WindowFlags_AlwaysAutoResize() | ImGui.WindowFlags_NoResize())
  if vis then
    -- 說明文字 -- description
    local name_str = (c.name and c.name ~= "") and c.name or ("Q " .. (c.cue_number or "?"))
    ImGui.TextWrapped(ctx, "Cue \"" .. name_str .. "\" cannot find its source track.\nThe track may have been deleted or the project changed.")
    ImGui.Spacing(ctx); ImGui.Separator(ctx); ImGui.Spacing(ctx)

    local avail_w = ImGui.GetContentRegionAvail(ctx)
    local btn_w = math.floor((avail_w - FUNC.sz(8)) / 2)
    local btn_h = FUNC.sz(28)

    -- ASSIGN: 從現有track中選擇 -- pick from existing tracks
    if ImGui.Button(ctx, "Assign", btn_w, btn_h) then
      ImGui.OpenPopup(ctx, "##assign_track_" .. ci)
    end
    if ImGui.BeginPopup(ctx, "##assign_track_" .. ci) then
      local tc = reaper.CountTracks(0)
      if tc == 0 then
        ImGui.TextDisabled(ctx, "No tracks in project")
      else
        for ti = 0, tc - 1 do
          if ImGui.Selectable(ctx, string.format("%d: %s", ti + 1, FUNC.tr_name(ti))) then
            c.track_idx = ti; c.track_guid = FUNC.tr_guid(ti); c.track_invalid = false
            track_warns[c.id] = nil
            FUNC.refresh_cue_dur(c)  -- 重新計算duration -- recalc duration
            FUNC.save_cues()
            popup.warn_missing = false
          end
        end
      end
      ImGui.EndPopup(ctx)
    end

    ImGui.SameLine(ctx)

    -- BROWSE: 瀏覽音訊檔案，建立新track -- browse audio file, create new track
    if ImGui.Button(ctx, "Browse", btn_w, btn_h) then
      local ret, file = reaper.GetUserFileNameForRead("", "Select Audio File", "")
      if ret and file ~= "" then
        local tc = reaper.CountTracks(0)
        reaper.InsertTrackAtIndex(tc, true)
        local new_tr = reaper.GetTrack(0, tc)
        if new_tr then
          reaper.SetOnlyTrackSelected(new_tr)
          reaper.SetEditCurPos(0, false, false)
          reaper.InsertMedia(file, 0)
          local fname = file:match("([^/\\]+)$") or file
          fname = fname:match("(.+)%..+$") or fname
          reaper.GetSetMediaTrackInfo_String(new_tr, "P_NAME", fname, true)
          c.track_idx = tc; c.track_guid = FUNC.tr_guid(tc); c.track_invalid = false
          c.name = (c.name == "" or c.name == nil) and fname or c.name  -- 只在name空時自動填 -- auto-fill name if empty
          track_warns[c.id] = nil
          FUNC.refresh_cue_dur(c)
          FUNC.save_cues()
          popup.warn_missing = false
        end
      end
    end

    -- DELETE + DISMISS 第二列 -- second row
    if ImGui.Button(ctx, "Delete", btn_w, btn_h) then
      FUNC.remove_cue(ci)
      track_warns[c.id] = nil
      popup.warn_missing = false
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Dismiss", btn_w, btn_h) then
      popup.warn_missing = false
    end

    ImGui.End(ctx)
  end
  if not op then popup.warn_missing = false end
  ImGui.PopStyleColor(ctx, 2)
end

-- FX Envelope missing FX 警告 -- missing fx for fx_env warning popup
function FUNC.draw_fx_env_missing_popup()
  if not fx_env_missing_warn then return end
  local w = fx_env_missing_warn
  -- 找到對應 cue（O(1) id_map 查找）
  local _, c = FUNC.find_id(w.cue_id)
  if not c or not c.fx_envs or not c.fx_envs[w.env_idx] then fx_env_missing_warn = nil; return end

  ImGui.SetNextWindowFocus(ctx)
  ImGui.SetNextWindowSizeConstraints(ctx, FUNC.sz(340), 0, FUNC.sz(340), FUNC.sz(300))
  ImGui.PushStyleColor(ctx, ImGui.Col_TitleBg(), FUNC.rgba(120,40,35))
  ImGui.PushStyleColor(ctx, ImGui.Col_TitleBgActive(), FUNC.rgba(140,50,40))
  local vis, op = ImGui.Begin(ctx, "FX Envelope: FX Missing###fxe_missing_popup", true,
    ImGui.WindowFlags_NoCollapse() | ImGui.WindowFlags_AlwaysAutoResize() | ImGui.WindowFlags_NoResize())
  if vis then
    local cname = (c.name and c.name ~= "") and c.name or ("Q " .. (c.cue_number or "?"))
    ImGui.TextWrapped(ctx, "Cue \"" .. cname .. "\" has an FX envelope whose FX is missing:")
    ImGui.Spacing(ctx)
    ImGui.BulletText(ctx, (w.fx_name or "?") .. "  /  " .. (w.param_name or "?"))
    ImGui.Spacing(ctx); ImGui.Separator(ctx); ImGui.Spacing(ctx)

    local avail_w = ImGui.GetContentRegionAvail(ctx)
    local btn_w = math.floor((avail_w - FUNC.sz(8)) / 2)
    local btn_h = FUNC.sz(28)

    if ImGui.Button(ctx, "Delete Envelope", btn_w, btn_h) then
      FUNC.fx_env_remove(c, w.env_idx)
      if fx_env_edit_idx == w.env_idx then fx_env_edit_idx = nil end
      FUNC.save_cues()
      fx_env_missing_warn = nil
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Dismiss", btn_w, btn_h) then
      fx_env_missing_warn = nil
    end
    ImGui.End(ctx)
  end
  if not op then fx_env_missing_warn = nil end
  ImGui.PopStyleColor(ctx, 2)
end

---------------------------------------------------------------------
-- SELECTIVE PASTE POPUP (Cmd+Shift+V) -- 選擇性貼上 popup
---------------------------------------------------------------------
-- 分頁 → 群組清單。每群組一個 checkbox，勾選後將 fields 內所有欄位從 clipboard 拷到 target。
local SEL_PASTE_TABS = {
  {id="basic",    label="Basic"},
  {id="notes",    label="Notes"},
  {id="waveform", label="Source"},
  {id="route",    label="Route"},
}
-- show(srcs) 回傳 true 時群組才出現在 popup；用於依來源 cue 種類/內容過濾。
-- show(srcs) → true keeps the group visible based on source cue type/content.
local function any_of(srcs, fn) for _, s in ipairs(srcs) do if fn(s) then return true end end; return false end
local function any_type(srcs, ...)
  local types = {...}
  return any_of(srcs, function(s) for _, t in ipairs(types) do if s.type == t then return true end end; return false end)
end
local SEL_PASTE_GROUPS = {
  basic = {
    {key="volume",     label="Volume",            fields={"volume"},                                show=function(s) return any_type(s,"PLAY","FADE","GROUP","MIDI") end},
    {key="pan",        label="Pan",               fields={"pan"},                                   show=function(s) return any_type(s,"PLAY","FADE","GROUP","MIDI") end},
    {key="pre_wait",   label="Pre-Wait",          fields={"pre_wait","pre_wait_mode","pre_bpm_beats","pre_bpm_val","pre_note_idx"},  show=function(s) return any_of(s, function(c) return c.type ~= "SPACER" end) end},
    {key="post_wait",  label="Post-Wait",         fields={"post_wait","post_wait_mode","post_bpm_beats","post_bpm_val","post_note_idx"}, show=function(s) return any_of(s, function(c) return c.type ~= "SPACER" end) end},
    {key="trim",       label="Trim Start/End",    fields={"trim_start","trim_end"},                 show=function(s) return any_type(s,"PLAY","MIDI","GROUP") end},
    {key="fade",       label="Fade Time + Curve", fields={"fade_time","fade_wait_mode","fade_bpm_beats","fade_bpm_val","fade_note_idx","fade_curve","fade_curve_amt"}, show=function(s) return any_type(s,"PLAY","FADE","GROUP","MIDI") end},
    {key="rate",       label="Rate",              fields={"rate"},                                  show=function(s) return any_type(s,"PLAY") end},
    {key="pitch",      label="Pitch",             fields={"pitch","preserve_pitch"},                show=function(s) return any_type(s,"PLAY") end},
    {key="auto_go",    label="Auto-Go",           fields={"auto_go"},                               show=function(s) return any_of(s, function(c) return c.type ~= "SPACER" end) end},
    {key="kill_above", label="Kill Above",        fields={"kill_above"},                            show=function(s) return any_of(s, function(c) return c.type ~= "SPACER" end) end},
    {key="loop",       label="Loop + Count",      fields={"loop","loop_count"},                     show=function(s) return any_type(s,"PLAY","MIDI","GROUP") end},
    {key="cue_color",  label="Color",             fields={"cue_color"},                             show=function(s) return true end},
    {key="spacer",     label="Spacer Style",      fields={"spacer_align","spacer_text_color","spacer_border_color","spacer_bold","spacer_italic","spacer_alpha"}, show=function(s) return any_type(s,"SPACER") end},
  },
  notes = {
    {key="notes",      label="Notes Content",     fields={"notes"},                                 show=function(s) return any_of(s, function(c) return (c.notes or "") ~= "" end) end},
  },
  waveform = {
    {key="env",         label="Volume Envelope",   fields={"env_enabled","env_points"},             show=function(s) return any_of(s, function(c) return c.env_enabled or (c.env_points and #c.env_points > 0) end) end},
    {key="pan_env",     label="Pan Envelope",      fields={"pan_env_enabled","pan_env_points"},     show=function(s) return any_of(s, function(c) return c.pan_env_enabled or (c.pan_env_points and #c.pan_env_points > 0) end) end},
    {key="fx_envs",     label="FX Chain (Envelopes)", fields={"fx_envs"},                           show=function(s) return any_of(s, function(c) return c.fx_envs and #c.fx_envs > 0 end) end},
    {key="markers",     label="Markers",           fields={"markers"},                              show=function(s) return any_of(s, function(c) return c.markers and #c.markers > 0 end) end},
    {key="midi_bpm",    label="MIDI BPM",          fields={"midi_bpm"},                             show=function(s) return any_type(s,"MIDI") end},
    {key="midi_msgs",   label="MIDI Messages",     fields={"midi_msgs","midi_press_ms"},            show=function(s) return any_of(s, function(c) return c.type == "MIDI" and c.midi_msgs and #c.midi_msgs > 0 end) end},
    {key="midi_chans",  label="MIDI Channels",     fields={"midi_channels"},                        show=function(s) return any_type(s,"MIDI") end},
    {key="midi_vel",    label="MIDI Velocity %",   fields={"midi_vel_pct"},                         show=function(s) return any_type(s,"MIDI") end},
    {key="midi_ts",     label="MIDI Time Sig",     fields={"midi_ts_num","midi_ts_den"},            show=function(s) return any_type(s,"MIDI") end},
    {key="midi_dur",    label="MIDI Duration (msg mode)", fields={"midi_duration","midi_dur_mode","midi_dur_den"}, show=function(s) return any_of(s, function(c) return c.type == "MIDI" and c.midi_mode == "message" end) end},
  },
  route = {
    {key="route_hw",    label="Route HW Output",   fields={"route_hw"},                             show=function(s) return any_of(s, function(c) return c.route_hw ~= nil end) end},
    {key="route_trims", label="Route Trims (GROUP)", fields={"route_trims"},                        show=function(s) return any_of(s, function(c) return c.type == "GROUP" and c.route_trims and next(c.route_trims) end) end},
  },
}

-- 取得 clipboard 已反序列化的 cue 陣列（每幀現算，N 通常很小）
local function sel_paste_get_srcs()
  local srcs = {}
  local n = FUNC.clipboard_count()
  for i = 1, n do
    local c = FUNC.clipboard_cue_at and FUNC.clipboard_cue_at(i) or nil
    if c then srcs[#srcs+1] = c end
  end
  return srcs
end

local function sel_paste_visible_groups(tab_id, srcs)
  local out = {}
  for _, g in ipairs(SEL_PASTE_GROUPS[tab_id] or {}) do
    if (not g.show) or g.show(srcs) then out[#out+1] = g end
  end
  return out
end

local function sel_paste_collect_fields(srcs)
  local list = {}
  for _, tab in ipairs(SEL_PASTE_TABS) do
    for _, g in ipairs(sel_paste_visible_groups(tab.id, srcs)) do
      if popup.sel_paste_fields[g.key] then
        for _, f in ipairs(g.fields) do list[#list+1] = f end
      end
    end
  end
  return list
end

local function sel_paste_set_all(val, srcs)
  for _, tab in ipairs(SEL_PASTE_TABS) do
    for _, g in ipairs(sel_paste_visible_groups(tab.id, srcs)) do
      popup.sel_paste_fields[g.key] = val and true or nil
    end
  end
end

function FUNC.draw_sel_paste_popup()
  if not popup.sel_paste then return end
  ImGui.SetNextWindowSize(ctx, FUNC.sz(520), FUNC.sz(420), ImGui.Cond_FirstUseEver())
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg(), FUNC.rgba(35,35,45))
  local vis, op = ImGui.Begin(ctx, "Selective Paste###SelPaste", true, ImGui.WindowFlags_NoDocking())
  if vis then
    if popup_lost_focus() then op = false end  -- 失焦自動關閉
    ImGui.PushFont(ctx, FONT, FUNC.sz(14))
    local srcs = sel_paste_get_srcs()
    -- 來源/目標摘要 + 配對檢查 -- source/target summary + match check
    local N = FUNC.clipboard_count()
    local M = FUNC.sel_cnt()
    local mode_ok = (N == 1 and M >= 1) or (N >= 1 and N == M)
    local mode_txt = (N == 1) and string.format("Broadcast 1 → %d", M)
                  or (N == M) and string.format("One-to-one (%d → %d)", N, M)
                  or string.format("Mismatch: clipboard %d, selected %d (need N=1 or N=M)", N, M)
    if mode_ok then
      ImGui.PushStyleColor(ctx, ImGui.Col_Text(), FUNC.rgba(150,220,150))
    else
      ImGui.PushStyleColor(ctx, ImGui.Col_Text(), FUNC.rgba(230,140,90))
    end
    ImGui.Text(ctx, mode_txt)
    ImGui.PopStyleColor(ctx, 1)
    ImGui.Separator(ctx)
    -- 左側：分頁列；右側：欄位 checkbox -- left: tab list; right: field checkboxes
    local avail_w, avail_h = ImGui.GetContentRegionAvail(ctx)
    local btm_h = FUNC.sz(54)  -- 預留底部按鈕區 -- reserve bottom area
    local body_h = math.max(FUNC.sz(120), avail_h - btm_h)
    local left_w = FUNC.sz(110)
    if ImGui.BeginChild(ctx, "##sp_left", left_w, body_h, ImGui.ChildFlags_Borders and ImGui.ChildFlags_Borders() or 0) then
      for _, tab in ipairs(SEL_PASTE_TABS) do
        local sel = (popup.sel_paste_tab == tab.id)
        if ImGui.Selectable(ctx, tab.label.."##sp_t_"..tab.id, sel) then
          popup.sel_paste_tab = tab.id
        end
      end
      ImGui.EndChild(ctx)
    end
    ImGui.SameLine(ctx)
    if ImGui.BeginChild(ctx, "##sp_right", -1, body_h, ImGui.ChildFlags_Borders and ImGui.ChildFlags_Borders() or 0) then
      local groups = sel_paste_visible_groups(popup.sel_paste_tab, srcs)
      if #groups == 0 then
        ImGui.PushStyleColor(ctx, ImGui.Col_Text(), FUNC.rgba(150,150,160))
        ImGui.Text(ctx, "(no copyable fields in source for this tab)")
        ImGui.PopStyleColor(ctx, 1)
      end
      for _, g in ipairs(groups) do
        local cur = popup.sel_paste_fields[g.key] and true or false
        local ch, nv = ImGui.Checkbox(ctx, g.label.."##sp_c_"..g.key, cur)
        if ch then popup.sel_paste_fields[g.key] = nv and true or nil end
      end
      ImGui.EndChild(ctx)
    end
    -- 底部按鈕：All / None / Apply / Cancel + 訊息 -- bottom buttons + status
    if ImGui.Button(ctx, "All", FUNC.sz(60), FUNC.sz(24)) then sel_paste_set_all(true, srcs) end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "None", FUNC.sz(60), FUNC.sz(24)) then sel_paste_set_all(false, srcs) end
    ImGui.SameLine(ctx, 0, FUNC.sz(20))
    -- Apply
    local fl = sel_paste_collect_fields(srcs)
    local can_apply = mode_ok and #fl > 0
    if not can_apply then ImGui.BeginDisabled(ctx) end
    ImGui.PushStyleColor(ctx, ImGui.Col_Button(), FUNC.rgba(40,100,40))
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), FUNC.rgba(50,130,50))
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), FUNC.rgba(60,150,60))
    if ImGui.Button(ctx, "Apply", FUNC.sz(90), FUNC.sz(24)) then
      local ok, err = FUNC.do_paste_selective(fl)
      if ok then
        popup.sel_paste = false
      else
        popup.sel_paste_msg = err
      end
    end
    ImGui.PopStyleColor(ctx, 3)
    if not can_apply then ImGui.EndDisabled(ctx) end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel", FUNC.sz(80), FUNC.sz(24)) then popup.sel_paste = false end
    if popup.sel_paste_msg then
      ImGui.SameLine(ctx, 0, FUNC.sz(12))
      ImGui.PushStyleColor(ctx, ImGui.Col_Text(), FUNC.rgba(230,140,90))
      ImGui.Text(ctx, popup.sel_paste_msg)
      ImGui.PopStyleColor(ctx, 1)
    end
    ImGui.PopFont(ctx); ImGui.End(ctx)
  end
  if not op then popup.sel_paste = false end
  ImGui.PopStyleColor(ctx, 1)
end

