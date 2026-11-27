-- ui_edit_meter.lua — Edit panel: Meter tab
-- 所有cue用到的hw output channels總覽 -- master meter for all routed hw channels

-- fader 依可用寬度縮放（Route / Master 共用）-- fit faders to available width (shared by Route / Master)
-- 夠寬：22px fader + 10px 間距；不夠：先按比例縮（間距約 30%），最窄 10px + 3px；再不夠就藏掉左側 dB 刻度
-- roomy: 22 + 10 gap; tighter: shrink proportionally (gap ~30%), floor 10 + 3; still too tight: drop the dB scale
function FUNC.fit_faders(n, avail_w, scale_w)
  local fw, gap = FUNC.sz(22), FUNC.sz(10)
  n = math.max(1, n)
  if (avail_w - scale_w) / n >= fw + gap then return fw, gap, scale_w end
  local min_fw, min_gap = FUNC.sz(10), FUNC.sz(3)
  if (avail_w - scale_w) / n < min_fw + min_gap then scale_w = 0 end
  local per = (avail_w - scale_w) / n
  gap = math.max(min_gap, math.floor(per * 0.3))
  fw = math.max(min_fw, math.floor(per - gap))
  return fw, gap, scale_w
end

function FUNC.draw_edit_section_meter()
  -- SECTION: MASTER METER — 所有cue用到的hw output channels總覽
  -- ═══════════════════════════════════════════════════════
  ImGui.Dummy(ctx, 0, FUNC.sz(2))
  local mt_w, mt_h = ImGui.GetContentRegionAvail(ctx)
  local mt_dl = ImGui.GetWindowDrawList(ctx)
  local mt_pad = FUNC.sz(6)

  -- 收集所有cue用到的hw channels -- collect all hw channels used by any cue
  local hw_set = {}  -- {[ch_idx] = true}
  for _, q in ipairs(cues) do
    if (q.type == "PLAY" or q.type == "MIDI") and q.route_hw then
      for _, hw in ipairs(q.route_hw) do
        if hw.ch >= 0 then hw_set[hw.ch] = true end
      end
    end
  end
  local ch_list = {}
  for ch in pairs(hw_set) do ch_list[#ch_list+1] = ch end
  table.sort(ch_list)

  if #ch_list == 0 then
    ImGui.PushFont(ctx, FONT, FUNC.sz(12))
    ImGui.PushStyleColor(ctx, ImGui.Col_Text(), FUNC.rgba(100,100,110))
    ImGui.Indent(ctx, FUNC.sz(6))
    ImGui.Text(ctx, "No routed channels")
    ImGui.Unindent(ctx, FUNC.sz(6))
    ImGui.PopStyleColor(ctx, 1)
    ImGui.PopFont(ctx)
  else
    -- 使用與Route頁面相同的fader樣式 -- use same fader style as Route page
    ImGui.PushFont(ctx, FONT, FUNC.sz(11))

    local now = reaper.time_precise()
    local function lin2db_mt(v) return v > 0 and (20 * math.log(v, 10)) or prefs.vol_min end

    -- 佈局參數（同Route PLAY fader）-- layout params (same as Route PLAY fader)
    local fader_w = FUNC.sz(22)
    local fader_gap = FUNC.sz(10)
    local label_h = FUNC.sz(28)  -- 兩行：dB 數字 + channel 編號 -- two lines: dB value + channel number
    local fader_area_h = math.floor(mt_h - label_h - FUNC.sz(8))
    local fader_h = math.max(FUNC.sz(32), fader_area_h)
    local handle_h = FUNC.sz(3)
    local mt_sx, mt_sy = ImGui.GetCursorScreenPos(ctx)

    -- 初始化per-channel peak hold -- init per-channel peak hold
    if not popup._meter_hold then popup._meter_hold = {} end
    local mh = popup._meter_hold

    -- 收集每個hw channel的peak（從active cues的track peak計算）
    -- collect per-hw-channel peak from active cues' track peaks
    local ch_peaks = {}  -- {[ch_idx] = linear_peak}
    for _, q in ipairs(cues) do
      if (q.type == "PLAY" or q.type == "MIDI") and q.route_hw and q.track_idx >= 0
         and FUNC.cue_meter_active(q) then
        local tr = FUNC.get_tr(q.track_idx)
        if tr then
          local num_ch = math.max(1, math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_NCHAN")))
          for hi, hw in ipairs(q.route_hw) do
            if hw.ch >= 0 and hw_set[hw.ch] then
              local pk_ch = (hi - 1) % num_ch
              local pk = reaper.Track_GetPeakInfo(tr, pk_ch)
              local fader_lin = hw.vol_db <= prefs.vol_min and 0 or (10 ^ (hw.vol_db / 20))
              pk = pk * fader_lin
              ch_peaks[hw.ch] = math.max(ch_peaks[hw.ch] or 0, pk)
            end
          end
        end
      end
    end

    -- 左側dB刻度標籤 -- left dB scale labels
    local scale_top_txt = string.format("%+.0f", prefs.vol_max)
    local scale_bot_txt = string.format("%.0f", prefs.vol_min)
    local scale_zero_txt = "0"
    local stw1 = ImGui.CalcTextSize(ctx, scale_top_txt)
    local stw2 = ImGui.CalcTextSize(ctx, scale_bot_txt)
    local stw3 = ImGui.CalcTextSize(ctx, scale_zero_txt)
    local scale_tw = math.max(stw1, stw2, stw3)
    local scale_w = scale_tw + FUNC.sz(6)
    fader_w, fader_gap, scale_w = FUNC.fit_faders(#ch_list, mt_w - mt_pad * 2, scale_w)
    local scale_x = mt_sx + mt_pad
    local scale_col = FUNC.rgba(120, 120, 130)
    local txt_h = FUNC.sz(11)
    local fx = mt_sx + mt_pad + scale_w
    local fy = mt_sy

    if scale_w > 0 then ImGui.DrawList_AddText(mt_dl, scale_x, fy, scale_col, scale_top_txt) end
    if scale_w > 0 then ImGui.DrawList_AddText(mt_dl, scale_x, fy + fader_h - txt_h, scale_col, scale_bot_txt) end
    if prefs.vol_min < 0 and prefs.vol_max > 0 then
      local zero_frac = -prefs.vol_min / (prefs.vol_max - prefs.vol_min)
      local zero_label_y = fy + fader_h - math.floor(fader_h * zero_frac) - math.floor(txt_h * 0.5)
      if zero_label_y > fy + txt_h + FUNC.sz(2) and zero_label_y < fy + fader_h - txt_h * 2 - FUNC.sz(2) then
        if scale_w > 0 then ImGui.DrawList_AddText(mt_dl, scale_x, zero_label_y, scale_col, scale_zero_txt) end
      end
    end

    -- 畫每個channel的fader -- draw fader per channel
    for _, ch in ipairs(ch_list) do
      local pk_lin = ch_peaks[ch] or 0
      local pk_db = lin2db_mt(pk_lin)

      -- per-channel peak hold & clip
      if not mh[ch] then mh[ch] = {hold=prefs.vol_min, ht=0, clip=false} end
      local h = mh[ch]
      if pk_db >= h.hold then h.hold = pk_db; h.ht = now end
      if now - h.ht > 1.5 then h.hold = h.hold - 30 * (now - h.ht - 1.5); h.ht = now - 1.5 end
      h.hold = math.max(prefs.vol_min, h.hold)
      if pk_db > 0 then h.clip = true end

      -- fader背景 -- fader background
      ImGui.DrawList_AddRectFilled(mt_dl, fx, fy, fx + fader_w, fy + fader_h, FUNC.dim_c(C.field), FUNC.rad("m"))  -- v2 凹槽 -- v2 well

      -- 漸層 meter 填色 -- gradient meter fill
      local vr = prefs.vol_max - prefs.vol_min
      FUNC.draw_meter_fill(mt_dl, fx, fx + fader_w, fy, fader_h, pk_db)

      -- peak hold線 -- peak hold line
      if h.hold > prefs.vol_min + 1 then
        local hold_frac = FUNC.clamp((h.hold - prefs.vol_min) / vr, 0, 1)
        local hy = fy + fader_h - math.floor(fader_h * hold_frac)
        ImGui.DrawList_AddLine(mt_dl, fx + 1, hy, fx + fader_w - 1, hy, FUNC.rgba(255, 255, 255, 200), FUNC.sz(1))
      end

      -- 0dB參考線 -- 0dB reference line
      local zero_frac = FUNC.clamp((0 - prefs.vol_min) / vr, 0, 1)
      local zero_y = fy + fader_h - math.floor(fader_h * zero_frac)
      ImGui.DrawList_AddLine(mt_dl, fx + 2, zero_y, fx + fader_w - 2, zero_y, FUNC.rgba(180, 180, 180, 40), 1)

      -- clip指示（邊框變紅）/ output_map顏色 -- clip indicator (red border) / output_map color
      local mt_omap_col = FUNC.omap_color(ch)
      local mt_omap_im = mt_omap_col >= 0 and FUNC.col2im(mt_omap_col) or nil
      if h.clip then
        ImGui.DrawList_AddRect(mt_dl, fx, fy, fx + fader_w, fy + fader_h, FUNC.rgba(255, 30, 30), 3, 0, FUNC.sz(2.5))
      elseif mt_omap_im then
        ImGui.DrawList_AddRect(mt_dl, fx, fy, fx + fader_w, fy + fader_h, mt_omap_im, 3, 0, FUNC.sz(1.5))
      else
        ImGui.DrawList_AddRect(mt_dl, fx, fy, fx + fader_w, fy + fader_h, FUNC.dim_c(C.line), FUNC.rad("m"), 0, 1)
      end

      -- dB文字（fader內底部）-- dB text at fader bottom
      local vol_txt = pk_db <= prefs.vol_min and "-inf" or string.format("%.0f", pk_db)
      local vtw = ImGui.CalcTextSize(ctx, vol_txt)
      if vtw <= fader_w + fader_gap then ImGui.DrawList_AddText(mt_dl, fx + (fader_w - vtw) * 0.5, fy + fader_h + FUNC.sz(3), C.dim, vol_txt) end  -- 放柱子下方；太擠就不顯示 -- below the bar; hidden when too tight

      -- 互動區（點擊clip清除）-- interaction area (click to clear clip)
      ImGui.SetCursorScreenPos(ctx, fx, fy)
      ImGui.InvisibleButton(ctx, "##mt_fader_"..ch, fader_w, fader_h)
      if ImGui.IsItemClicked(ctx) then h.clip = false end
      local f_hov = ImGui.IsItemHovered(ctx)

      -- channel編號（底部，置中）-- channel number at bottom, centered
      local ch_num_str = tostring(FUNC.omap_num(ch))
      local lbl_y = fy + fader_h + FUNC.sz(16)
      local lbl_fsz = ImGui.GetFontSize(ctx)
      ImGui.SetCursorScreenPos(ctx, fx, lbl_y)
      ImGui.InvisibleButton(ctx, "##mt_lbl_"..ch, fader_w, FUNC.sz(14))
      local lhov = ImGui.IsItemHovered(ctx)
      local cntw = ImGui.CalcTextSize(ctx, ch_num_str)
      ImGui.DrawList_AddTextEx(mt_dl, FONT, lbl_fsz, fx + math.max(0, (fader_w - cntw) * 0.5), lbl_y, C.text, ch_num_str)

      -- hover tooltip (顯示alias) -- show alias on hover
      if f_hov or lhov then
        ImGui.SetTooltip(ctx, string.format("%s\n%s", FUNC.omap_alias(ch),
          pk_db <= prefs.vol_min and "-inf dB" or string.format("%.1f dB", pk_db)))
      end

      fx = fx + fader_w + fader_gap
    end

    ImGui.PopFont(ctx)
  end
end
