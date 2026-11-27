-- ui_edit_route.lua — Edit panel: Route tab
-- 垂直滑桿顯示 hw output routing -- vertical sliders for hw output routing

function FUNC.draw_edit_section_route(c, apply, multi)
        -- SECTION: ROUTE — 垂直滑桿顯示 hw output routing
        -- ═══════════════════════════════════════════════════════
        -- ═══════════════════════════════════════════════════════
        ImGui.Dummy(ctx, 0, FUNC.sz(2))
        local rt_w, rt_h = ImGui.GetContentRegionAvail(ctx)
        local rt_pad = FUNC.sz(6)
        local rt_dl = ImGui.GetWindowDrawList(ctx)

        -- Route只適用PLAY和GROUP -- route only for PLAY and GROUP
        local rt_applicable = (not multi and (c.type == "PLAY" or c.type == "GROUP" or c.type == "MIDI"))
        if not rt_applicable then
          ImGui.PushFont(ctx, FONT, FUNC.sz(12))
          ImGui.PushStyleColor(ctx, ImGui.Col_Text(), FUNC.rgba(100,100,110))
          ImGui.Indent(ctx, rt_pad)
          ImGui.Text(ctx, "Route N/A for "..c.type)
          ImGui.Unindent(ctx, rt_pad)
          ImGui.PopStyleColor(ctx, 1)
          ImGui.PopFont(ctx)
        elseif c.type == "GROUP" then
          -- ─── GROUP Route Trim ─── 收集children用到的hw output channels，顯示PLAY-style fader + trim
          -- collect unique hw channels from all children PLAY cues (including route_hw)
          local ch_set = {}   -- {ch_idx = true}
          local ch_names = {} -- {ch_idx = name}
          local ch_cues = {}  -- {ch_idx = {cue_name, ...}} -- hover顯示用到該channel的cue -- for hover tooltip
          for _, ci in ipairs(c.children or {}) do
            if ci >= 1 and ci <= #cues then
              local cc = cues[ci]
              if cc.type == "PLAY" then
                local cname = (cc.name and cc.name ~= "") and cc.name or FUNC.tr_name(cc.track_idx)
                if cc.route_hw then
                  -- 從route_hw取channel -- get channels from route_hw
                  for _, hw in ipairs(cc.route_hw) do
                    if hw.ch >= 0 then
                      ch_set[hw.ch] = true
                      if not ch_names[hw.ch] then ch_names[hw.ch] = reaper.GetOutputChannelName(hw.ch) or ("Out "..hw.ch+1) end
                      if not ch_cues[hw.ch] then ch_cues[hw.ch] = {} end
                      -- 避免重複名稱 -- avoid duplicate names
                      local found = false
                      for _, n in ipairs(ch_cues[hw.ch]) do if n == cname then found = true; break end end
                      if not found then ch_cues[hw.ch][#ch_cues[hw.ch]+1] = cname end
                    end
                  end
                else
                  -- 無route_hw → 從REAPER track hw sends或parent chain取 -- no route_hw → from track or parent chain
                  local ctr = FUNC.get_tr(cc.track_idx)
                  if ctr then
                    local found_chs = {}
                    local nhs = reaper.GetTrackNumSends(ctr, 1)
                    if nhs > 0 then
                      for si = 0, nhs - 1 do
                        local dst = reaper.GetTrackSendInfo_Value(ctr, 1, si, "I_DSTCHAN")
                        local ch = math.floor(dst) % 1024
                        found_chs[ch] = true
                      end
                    else
                      local cur = ctr
                      for _ = 1, 16 do
                        local ms = reaper.GetMediaTrackInfo_Value(cur, "B_MAINSEND")
                        if ms ~= 1 then break end
                        local parent = reaper.GetParentTrack(cur)
                        local tgt = parent or reaper.GetMasterTrack(0)
                        if not tgt then break end
                        local pn = reaper.GetTrackNumSends(tgt, 1)
                        if pn > 0 then
                          for si = 0, pn - 1 do
                            local dst = reaper.GetTrackSendInfo_Value(tgt, 1, si, "I_DSTCHAN")
                            found_chs[math.floor(dst) % 1024] = true
                          end
                          break
                        end
                        if not parent then found_chs[0] = true; found_chs[1] = true; break end
                        cur = tgt
                      end
                    end
                    for ch in pairs(found_chs) do
                      ch_set[ch] = true
                      if not ch_names[ch] then ch_names[ch] = reaper.GetOutputChannelName(ch) or ("Out "..ch+1) end
                      if not ch_cues[ch] then ch_cues[ch] = {} end
                      local found = false
                      for _, n in ipairs(ch_cues[ch]) do if n == cname then found = true; break end end
                      if not found then ch_cues[ch][#ch_cues[ch]+1] = cname end
                    end
                  end
                end
              end
            end
          end
          -- 排序channel列表 -- sort channels
          local ch_list = {}
          for ch in pairs(ch_set) do ch_list[#ch_list+1] = ch end
          table.sort(ch_list)

          if #ch_list == 0 then
            ImGui.PushFont(ctx, FONT, FUNC.sz(12))
            ImGui.PushStyleColor(ctx, ImGui.Col_Text(), FUNC.rgba(100,100,110))
            ImGui.Indent(ctx, rt_pad)
            ImGui.Text(ctx, "No routed channels in children")
            ImGui.Unindent(ctx, rt_pad)
            ImGui.PopStyleColor(ctx, 1)
            ImGui.PopFont(ctx)
          else
            -- 確保route_trims存在 -- ensure route_trims exists
            if not c.route_trims then c.route_trims = {} end
            if not popup.route_sel then popup.route_sel = {} end
            local rsel = popup.route_sel

            -- 佈局參數（同PLAY route fader）-- layout params (same as PLAY route fader)
            local fader_w = FUNC.sz(22)
            local fader_gap = FUNC.sz(10)
            local slot_w = fader_w + fader_gap
            local label_h = FUNC.sz(14)
            local fader_area_h = math.floor(rt_h - label_h - FUNC.sz(8))
            local fader_h = math.max(FUNC.sz(32), fader_area_h)
            local handle_h = FUNC.sz(8)  -- v2 膠囊把手（原 3px 細線）-- v2 capsule knob (was 3px line)

            ImGui.PushFont(ctx, FONT, FUNC.sz(11))
            local rt_sx, rt_sy = ImGui.GetCursorScreenPos(ctx)

            -- dB刻度標籤（頂部max / 底部min）-- dB scale labels
            local scale_top_txt = string.format("%+.0f", prefs.vol_max)
            local scale_bot_txt = string.format("%.0f", prefs.vol_min)
            local scale_zero_txt = "0"
            local stw1 = ImGui.CalcTextSize(ctx, scale_top_txt)
            local stw2 = ImGui.CalcTextSize(ctx, scale_bot_txt)
            local stw3 = ImGui.CalcTextSize(ctx, scale_zero_txt)
            local scale_tw = math.max(stw1, stw2, stw3)
            local scale_w = scale_tw + FUNC.sz(6)

            -- fader 依面板寬度縮放 -- fit faders to section width
            fader_w, fader_gap, scale_w = FUNC.fit_faders(#ch_list, rt_w - rt_pad * 2, scale_w)
            slot_w = fader_w + fader_gap
            local fx = rt_sx + rt_pad + scale_w
            local fy = rt_sy

            -- 繪製左側dB刻度標籤 -- draw left-side dB scale labels
            local scale_x = rt_sx + rt_pad
            local scale_col = FUNC.rgba(120, 120, 130)
            local txt_h = FUNC.sz(11)
            if scale_w > 0 then ImGui.DrawList_AddText(rt_dl, scale_x, fy, scale_col, scale_top_txt) end
            if scale_w > 0 then ImGui.DrawList_AddText(rt_dl, scale_x, fy + fader_h - txt_h, scale_col, scale_bot_txt) end
            if prefs.vol_min < 0 and prefs.vol_max > 0 then
              local zero_frac = -prefs.vol_min / (prefs.vol_max - prefs.vol_min)
              local zero_label_y = fy + fader_h - math.floor(fader_h * zero_frac) - math.floor(txt_h * 0.5)
              if zero_label_y > fy + txt_h + FUNC.sz(2) and zero_label_y < fy + fader_h - txt_h * 2 - FUNC.sz(2) then
                if scale_w > 0 then ImGui.DrawList_AddText(rt_dl, scale_x, zero_label_y, scale_col, scale_zero_txt) end
              end
            end

            -- 收集children per-channel peak（播放時） -- collect children per-channel peak (when playing)
            local ch_peaks = {}  -- {[ch_idx] = linear_peak}
            for _, ci in ipairs(c.children or {}) do
              if ci >= 1 and ci <= #cues then
                local cc = cues[ci]
                if cc.type == "PLAY" and cc.route_hw and cc.track_idx >= 0
                   and FUNC.cue_meter_active(cc) then
                  local tr = FUNC.get_tr(cc.track_idx)
                  if tr then
                    local num_ch = math.max(1, math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_NCHAN")))
                    for hi, hw in ipairs(cc.route_hw) do
                      if hw.ch >= 0 and ch_set[hw.ch] then
                        local pk_ch = (hi - 1) % num_ch
                        local pk = reaper.Track_GetPeakInfo(tr, pk_ch)
                        local fader_lin = hw.vol_db <= prefs.vol_min and 0 or (10 ^ (hw.vol_db / 20))
                        -- 疊加group trim -- apply group trim
                        local trim_db = c.route_trims[hw.ch] or 0
                        local trim_lin = trim_db <= prefs.vol_min and 0 or (10 ^ (trim_db / 20))
                        pk = pk * fader_lin * trim_lin
                        ch_peaks[hw.ch] = math.max(ch_peaks[hw.ch] or 0, pk)
                      end
                    end
                  end
                end
              end
            end

            -- peak hold state -- peak hold狀態
            if not popup._grt_meter_hold then popup._grt_meter_hold = {} end
            local mh = popup._grt_meter_hold
            local now = reaper.time_precise()

            -- fader inline edit state (雙擊fader輸入dB) -- double-click fader → dB input
            if not popup._grt_db_edit then popup._grt_db_edit = {active=false, ch=-1, buf=""} end
            local db_edit = popup._grt_db_edit

            for _, ch in ipairs(ch_list) do
              local trim_db = c.route_trims[ch] or 0
              local fid = "##grt_fader"..ch
              local sel_this = rsel[ch]

              -- fader背景 -- fader background
              ImGui.DrawList_AddRectFilled(rt_dl, fx, fy, fx + fader_w, fy + fader_h, FUNC.dim_c(C.field), FUNC.rad("m"))  -- v2 凹槽 -- v2 well

              -- ─── Meter fill (播放時即時顯示) ─── real-time meter
              local pk_lin = ch_peaks[ch] or 0
              local pk_db = pk_lin > 0 and (20 * math.log(pk_lin, 10)) or prefs.vol_min
              if pk_lin > 0 then
                FUNC.draw_meter_fill(rt_dl, fx, fx + fader_w, fy, fader_h, pk_db)  -- 漸層 meter -- gradient meter
              end

              -- peak hold線 -- peak hold line
              if not mh[ch] then mh[ch] = {hold=prefs.vol_min, ht=0} end
              local h = mh[ch]
              if pk_db >= h.hold then h.hold = pk_db; h.ht = now end
              if now - h.ht > 1.5 then h.hold = h.hold - 30 * (now - h.ht - 1.5); h.ht = now - 1.5 end
              h.hold = math.max(prefs.vol_min, h.hold)
              if h.hold > prefs.vol_min + 1 then
                local hold_frac = FUNC.clamp((h.hold - prefs.vol_min) / (prefs.vol_max - prefs.vol_min), 0, 1)
                local hy = fy + fader_h - math.floor(fader_h * hold_frac)
                ImGui.DrawList_AddLine(rt_dl, fx + 1, hy, fx + fader_w - 1, hy, FUNC.rgba(255, 255, 255, 200), FUNC.sz(1))
              end

              -- ─── Volume handle bar ─── trim位置橫桿
              local vol_frac = FUNC.clamp((trim_db - prefs.vol_min) / (prefs.vol_max - prefs.vol_min), 0, 1)
              local handle_y = fy + fader_h - math.floor(fader_h * vol_frac) - math.floor(handle_h / 2)
              handle_y = FUNC.clamp(handle_y, fy, fy + fader_h - handle_h)
              local hcol = sel_this and C.gold or C.knob  -- 選取=金色 -- selected = gold
              local kov = FUNC.sz(3)  -- 把手比軌道寬一點 -- knob overhangs the track
              ImGui.DrawList_AddRectFilled(rt_dl, fx - kov, handle_y + 1, fx + fader_w + kov, handle_y + handle_h + 1, FUNC.rgba(0,0,0,110), FUNC.sz(3))  -- 陰影 -- shadow
              ImGui.DrawList_AddRectFilled(rt_dl, fx - kov, handle_y, fx + fader_w + kov, handle_y + handle_h, FUNC.dim_c(hcol), FUNC.sz(3))

              -- 0dB參考線 -- 0dB reference line
              local zero_frac = FUNC.clamp((0 - prefs.vol_min) / (prefs.vol_max - prefs.vol_min), 0, 1)
              local zero_y = fy + fader_h - math.floor(fader_h * zero_frac)
              ImGui.DrawList_AddLine(rt_dl, fx + 2, zero_y, fx + fader_w - 2, zero_y, FUNC.rgba(180, 180, 180, 40), 1)

              -- 選取邊框 / output_map顏色 -- selection border / output_map color
              local grt_omap_col = FUNC.omap_color(ch)
              local grt_omap_im = grt_omap_col >= 0 and FUNC.col2im(grt_omap_col) or nil
              if sel_this then
                ImGui.DrawList_AddRect(rt_dl, fx, fy, fx + fader_w, fy + fader_h, C.gold, 3, 0, FUNC.sz(2.5))
              elseif grt_omap_im then
                ImGui.DrawList_AddRect(rt_dl, fx, fy, fx + fader_w, fy + fader_h, grt_omap_im, 3, 0, FUNC.sz(1.5))
              else
                ImGui.DrawList_AddRect(rt_dl, fx, fy, fx + fader_w, fy + fader_h, FUNC.dim_c(C.line), FUNC.rad("m"), 0, 1)
              end

              -- dB文字（滑桿內底部） -- dB text at fader bottom
              local vol_txt = trim_db <= prefs.vol_min and "-inf" or string.format("%.0f", trim_db)
              local vtw = ImGui.CalcTextSize(ctx, vol_txt)
              if vtw <= fader_w then ImGui.DrawList_AddText(rt_dl, fx + (fader_w - vtw) * 0.5, fy + fader_h - FUNC.sz(13), C.text, vol_txt) end  -- 太窄就不顯示 -- hide when too narrow

              -- 互動區 -- interaction area
              ImGui.SetCursorScreenPos(ctx, fx, fy)
              ImGui.InvisibleButton(ctx, fid, fader_w, fader_h)
              local f_hov = ImGui.IsItemHovered(ctx)
              local f_act = ImGui.IsItemActive(ctx)

              -- 雙擊fader → inline dB輸入 -- double-click fader → inline dB input
              if f_hov and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left()) then
                db_edit.active = true; db_edit.ch = ch
                db_edit.buf = trim_db <= prefs.vol_min and "-inf" or string.format("%.1f", trim_db)
                db_edit.focused = false
              elseif f_act then
                -- 需拖曳才改trim，單擊不觸發 -- require drag to change trim, ignore click
                local dx, dy = ImGui.GetMouseDelta(ctx)
                if math.abs(dx) > 0 or math.abs(dy) > 0 then
                  local _, my = ImGui.GetMousePos(ctx)
                  local frac = FUNC.clamp(1 - (my - fy) / fader_h, 0, 1)
                  c.route_trims[ch] = prefs.vol_min + frac * (prefs.vol_max - prefs.vol_min)
                  -- 播放中即時更新 -- live update during playback
                  if c._rt_hw_saved then FUNC.rt_restore_trims(c); FUNC.rt_apply_trims(c) end
                  FUNC.save_cues()
                end
              end

              -- 點擊選取 -- click to select
              if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left()) then
                local cmd = ImGui.IsKeyDown(ctx, ImGui.Mod_Super())
                if cmd then rsel[ch] = not rsel[ch] or nil
                else rsel = {}; rsel[ch] = true; popup.route_sel = rsel end
              end

              -- hover tooltip: channel名 + trim值 + 使用該channel的cue列表 -- tooltip with cue list
              if f_hov then
                local tip = ch_names[ch] or ("Out "..ch+1)
                tip = tip .. "\nTrim: " .. (trim_db <= prefs.vol_min and "-inf dB" or string.format("%.1f dB", trim_db))
                local qlist = ch_cues[ch]
                if qlist and #qlist > 0 then
                  tip = tip .. "\n─────────"
                  for _, qn in ipairs(qlist) do tip = tip .. "\n• " .. qn end
                end
                ImGui.SetTooltip(ctx, tip)
              end

              -- ─── dB inline edit (浮在fader底部) ─── dB inline edit overlay at fader bottom
              if db_edit.active and db_edit.ch == ch then
                local ie_y = fy + fader_h - FUNC.sz(18)
                ImGui.SetCursorScreenPos(ctx, fx, ie_y)
                ImGui.SetNextItemWidth(ctx, fader_w)
                ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding(), 1, 1)
                local changed, buf = ImGui.InputText(ctx, "##grt_db_edit"..ch, db_edit.buf,
                  ImGui.InputTextFlags_EnterReturnsTrue() | ImGui.InputTextFlags_AutoSelectAll())
                db_edit.buf = buf
                local deact_edit = ImGui.IsItemDeactivatedAfterEdit(ctx)
                local deact = ImGui.IsItemDeactivated(ctx)
                ImGui.PopStyleVar(ctx, 1)
                if not db_edit.focused then
                  ImGui.SetKeyboardFocusHere(ctx, -1)
                  db_edit.focused = true
                end
                -- commit: Enter或失焦且有編輯 -- commit on Enter or deactivate-after-edit
                if changed or deact_edit then
                  local num = tonumber(buf)
                  if num then c.route_trims[ch] = FUNC.clamp(num, prefs.vol_min, prefs.vol_max)
                  elseif buf == "-inf" or buf == "inf" then c.route_trims[ch] = prefs.vol_min end
                  if c._rt_hw_saved then FUNC.rt_restore_trims(c); FUNC.rt_apply_trims(c) end
                  FUNC.save_cues()
                  db_edit.active = false
                elseif deact then
                  -- 失焦但未編輯 -- deactivated without edit
                  db_edit.active = false
                end
              end

              -- Channel編號（滑桿下方，置中）-- channel number below fader, centered
              local ch_num_str = tostring(FUNC.omap_num(ch))
              local lbl_y = fy + fader_h + FUNC.sz(2)
              local lbl_fsz = ImGui.GetFontSize(ctx)
              ImGui.SetCursorScreenPos(ctx, fx, lbl_y)
              ImGui.InvisibleButton(ctx, "##grt_lbl_"..ch, fader_w, label_h)
              local lhov = ImGui.IsItemHovered(ctx)
              local cntw = ImGui.CalcTextSize(ctx, ch_num_str)
              ImGui.DrawList_AddTextEx(rt_dl, FONT, lbl_fsz, fx + math.max(0, (fader_w - cntw) * 0.5), lbl_y,
                FUNC.rgba(150, 150, 160), ch_num_str)
              if lhov then ImGui.SetTooltip(ctx, FUNC.omap_alias(ch)) end

              fx = fx + slot_w
            end

            -- Marquee選取 -- marquee selection
            if not ImGui.IsAnyItemActive(ctx) and ImGui.IsWindowHovered(ctx) then
              if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left()) then
                local mx, my = ImGui.GetMousePos(ctx)
                if mx >= rt_sx and mx <= rt_sx + rt_w and my >= rt_sy and my <= rt_sy + rt_h then
                  popup._rt_marquee = {x0=mx, y0=my, active=true}
                  popup.route_sel = {}; rsel = popup.route_sel
                end
              end
            end
            if popup._rt_marquee and popup._rt_marquee.active then
              if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left()) then
                local mx, my = ImGui.GetMousePos(ctx)
                local m = popup._rt_marquee
                local mx0, mx1 = math.min(m.x0, mx), math.max(m.x0, mx)
                local my0, my1 = math.min(m.y0, my), math.max(m.y0, my)
                if math.abs(mx - m.x0) > 3 or math.abs(my - m.y0) > 3 then
                  ImGui.DrawList_AddRectFilled(rt_dl, mx0, my0, mx1, my1, FUNC.rgba(255, 200, 80, 30))
                  ImGui.DrawList_AddRect(rt_dl, mx0, my0, mx1, my1, FUNC.rgba(255, 200, 80, 120), 0, 0, 1)
                  rsel = {}
                  local mfx = rt_sx + rt_pad + scale_w
                  for _, ch in ipairs(ch_list) do
                    local fr = mfx + fader_w
                    local fb = fy + fader_h
                    if mfx < mx1 and fr > mx0 and fy < my1 and fb > my0 then
                      rsel[ch] = true
                    end
                    mfx = mfx + slot_w
                  end
                  popup.route_sel = rsel
                end
              else
                popup._rt_marquee = nil
              end
            end

            ImGui.PopFont(ctx)
          end

        else -- PLAY type
          local tr = FUNC.get_tr(c.track_idx)
          if not tr then
            ImGui.PushFont(ctx, FONT, FUNC.sz(12))
            ImGui.PushStyleColor(ctx, ImGui.Col_Text(), FUNC.rgba(100,100,110))
            ImGui.Indent(ctx, rt_pad)
            ImGui.Text(ctx, "No track assigned")
            ImGui.Unindent(ctx, rt_pad)
            ImGui.PopStyleColor(ctx, 1)
            ImGui.PopFont(ctx)
          else
            -- ═══ 虛擬route系統：route_hw 存cue，走Q才apply ═══
            -- virtual route: route_hw stored on cue, applied on GO

            -- 自動初始化route_hw（從REAPER track狀態） -- auto-init route_hw from REAPER track state
            if not c.route_hw then
              local init_hw = {}
              local num_hw = reaper.GetTrackNumSends(tr, 1)
              if num_hw > 0 then
                -- 有直接hw sends → 從現有sends初始化 -- direct hw sends → init from existing
                for i = 0, num_hw - 1 do
                  local dst = math.floor(reaper.GetTrackSendInfo_Value(tr, 1, i, "I_DSTCHAN"))
                  local ch = dst % 1024
                  local is_mono = (math.floor(dst / 1024) % 2) == 1
                  local vol = reaper.GetTrackSendInfo_Value(tr, 1, i, "D_VOL")
                  local vdb = vol > 0 and (20 * math.log(vol, 10)) or prefs.vol_min
                  if is_mono then
                    init_hw[#init_hw+1] = {ch=ch, vol_db=vdb}
                  else
                    -- 展開stereo成兩個mono -- expand stereo to two mono
                    init_hw[#init_hw+1] = {ch=ch, vol_db=vdb}
                    init_hw[#init_hw+1] = {ch=ch+1, vol_db=vdb}
                  end
                end
              else
                -- 無直接sends → 追蹤parent chain -- no direct sends → trace parent chain
                local cur = tr
                for _ = 1, 16 do
                  local ms = reaper.GetMediaTrackInfo_Value(cur, "B_MAINSEND")
                  if ms ~= 1 then break end
                  local parent = reaper.GetParentTrack(cur)
                  local tgt = parent or reaper.GetMasterTrack(0)
                  if not tgt then break end
                  local pn = reaper.GetTrackNumSends(tgt, 1)
                  if pn > 0 then
                    local seen = {}
                    for i = 0, pn - 1 do
                      local dst = math.floor(reaper.GetTrackSendInfo_Value(tgt, 1, i, "I_DSTCHAN"))
                      local ch = dst % 1024
                      local is_mono = (math.floor(dst / 1024) % 2) == 1
                      if is_mono then
                        if not seen[ch] then seen[ch]=true; init_hw[#init_hw+1]={ch=ch,vol_db=0} end
                      else
                        if not seen[ch] then seen[ch]=true; init_hw[#init_hw+1]={ch=ch,vol_db=0} end
                        if not seen[ch+1] then seen[ch+1]=true; init_hw[#init_hw+1]={ch=ch+1,vol_db=0} end
                      end
                    end
                    break
                  end
                  if not parent then
                    init_hw[#init_hw+1]={ch=0,vol_db=0}; init_hw[#init_hw+1]={ch=1,vol_db=0}; break
                  end
                  cur = tgt
                end
              end
              if #init_hw > 0 then c.route_hw = init_hw; FUNC.save_cues() end
            end

            local hw_outs = c.route_hw or {}

            -- 初始化route選取狀態 -- init route selection state
            if not popup.route_sel then popup.route_sel = {} end
            local rsel = popup.route_sel

            -- 佈局參數 -- layout params
            local fader_w = FUNC.sz(22)
            local fader_gap = FUNC.sz(10)
            local slot_w = fader_w + fader_gap
            local btn_sz = FUNC.sz(16)
            local label_h = FUNC.sz(14)
            local btn_area_h = btn_sz + FUNC.sz(6)  -- 底部按鈕區高度 -- bottom button area height
            local fader_area_h = math.floor(rt_h - label_h - btn_area_h - FUNC.sz(8))
            local fader_h = math.max(FUNC.sz(32), fader_area_h)
            local handle_h = FUNC.sz(8)  -- v2 膠囊把手（原 3px 細線）-- v2 capsule knob (was 3px line)

            ImGui.PushFont(ctx, FONT, FUNC.sz(11))
            local rt_sx, rt_sy = ImGui.GetCursorScreenPos(ctx)

            -- dB刻度標籤（頂部max / 底部min）-- dB scale labels (top max / bottom min)
            local scale_top_txt = string.format("%+.0f", prefs.vol_max)
            local scale_bot_txt = string.format("%.0f", prefs.vol_min)
            local scale_zero_txt = "0"
            local stw1 = ImGui.CalcTextSize(ctx, scale_top_txt)
            local stw2 = ImGui.CalcTextSize(ctx, scale_bot_txt)
            local stw3 = ImGui.CalcTextSize(ctx, scale_zero_txt)
            local scale_tw = math.max(stw1, stw2, stw3)
            local scale_w = scale_tw + FUNC.sz(6)  -- 刻度標籤寬度 -- scale label width

            -- fader 依面板寬度縮放 -- fit faders to section width
            fader_w, fader_gap, scale_w = FUNC.fit_faders(#hw_outs, rt_w - rt_pad * 2, scale_w)
            slot_w = fader_w + fader_gap
            local fx = rt_sx + rt_pad + scale_w
            local fy = rt_sy
            local total_num_outs = reaper.GetNumAudioOutputs()

            -- 讀取track peak（僅播放時） -- read track peak (playing only)
            local any_playing = false
            for _, c2 in ipairs(cues) do
              if c2.track_idx == c.track_idx and FUNC.cue_meter_active(c2) then
                any_playing = true; break
              end
            end

            -- fader inline edit state (雙擊fader輸入dB) -- double-click fader → dB input
            if not popup._rt_db_edit then popup._rt_db_edit = {active=false, idx=0, buf=""} end
            local db_edit = popup._rt_db_edit

            -- 建立已佔用channel集合（供dropdown灰化）-- build used channels set for dropdown greying
            local used_chs = {}  -- {[ch_idx] = fader_hi_index}
            for hi, hw in ipairs(hw_outs) do
              if hw.ch >= 0 then used_chs[hw.ch] = hi end
            end

            -- master已從preview移到hw send → track peak不含master，meter無需補償
            -- master moved from preview to hw sends → track peak excludes master, no compensation needed

            -- dropdown hover highlight state -- dropdown內hover已佔用channel時highlight對應fader
            popup._rt_hover_hi = nil  -- 本幀highlight的fader index -- this frame's highlighted fader

            -- 繪製左側dB刻度標籤 -- draw left-side dB scale labels
            local scale_x = rt_sx + rt_pad
            local scale_col = FUNC.rgba(120, 120, 130)
            local txt_h = FUNC.sz(11)
            -- 頂部: vol_max -- top: vol_max
            if scale_w > 0 then ImGui.DrawList_AddText(rt_dl, scale_x, fy, scale_col, scale_top_txt) end
            -- 底部: vol_min -- bottom: vol_min
            if scale_w > 0 then ImGui.DrawList_AddText(rt_dl, scale_x, fy + fader_h - txt_h, scale_col, scale_bot_txt) end
            -- 0dB標籤（僅在不與top/bottom重疊時繪製）-- 0dB label (only if not overlapping top/bottom)
            if prefs.vol_min < 0 and prefs.vol_max > 0 then
              local zero_frac = -prefs.vol_min / (prefs.vol_max - prefs.vol_min)
              local zero_label_y = fy + fader_h - math.floor(fader_h * zero_frac) - math.floor(txt_h * 0.5)
              -- 只在離top/bottom夠遠時才畫 -- only draw if far enough from top/bottom
              if zero_label_y > fy + txt_h + FUNC.sz(2) and zero_label_y < fy + fader_h - txt_h * 2 - FUNC.sz(2) then
                if scale_w > 0 then ImGui.DrawList_AddText(rt_dl, scale_x, zero_label_y, scale_col, scale_zero_txt) end
              end
            end

            for hi, hw in ipairs(hw_outs) do
              local fid = "##rt_fader"..hi
              local sel_this = rsel[hi]
              local is_unassigned = (hw.ch < 0)  -- ch=-1 表示未指定 -- ch=-1 = unassigned

              -- 背景矩形 -- background rect
              ImGui.DrawList_AddRectFilled(rt_dl, fx, fy, fx + fader_w, fy + fader_h, FUNC.dim_c(C.field), FUNC.rad("m"))  -- v2 凹槽 -- v2 well

              -- ─── Meter fill (播放時即時顯示) ─── real-time meter
              if any_playing and not is_unassigned then
                -- 讀track peak（用track channel index，非hw output index） -- read track peak (track ch, not hw out)
                local num_ch = math.max(1, math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_NCHAN")))
                local pk_ch = (hi - 1) % num_ch  -- 循環映射fader→track channel -- cycle-map fader to track ch
                local pk = reaper.Track_GetPeakInfo(tr, pk_ch)
                -- track peak不含master（master在hw send層），套用route fader音量即可
                -- track peak excludes master (master at hw send layer), just apply route fader vol
                local fader_lin = hw.vol_db <= prefs.vol_min and 0 or (10 ^ (hw.vol_db / 20))
                pk = pk * fader_lin
                local pk_db = pk > 0 and (20 * math.log(pk, 10)) or prefs.vol_min
                FUNC.draw_meter_fill(rt_dl, fx, fx + fader_w, fy, fader_h, pk_db)  -- 漸層 meter -- gradient meter
              end

              -- ─── Volume handle bar ─── 音量位置橫桿
              if not is_unassigned then
                local vol_frac = FUNC.clamp((hw.vol_db - prefs.vol_min) / (prefs.vol_max - prefs.vol_min), 0, 1)
                local handle_y = fy + fader_h - math.floor(fader_h * vol_frac) - math.floor(handle_h / 2)
                handle_y = FUNC.clamp(handle_y, fy, fy + fader_h - handle_h)
                local hcol = sel_this and C.gold or C.knob  -- 選取=金色 -- selected = gold
                local kov = FUNC.sz(3)  -- 把手比軌道寬一點 -- knob overhangs the track
                ImGui.DrawList_AddRectFilled(rt_dl, fx - kov, handle_y + 1, fx + fader_w + kov, handle_y + handle_h + 1, FUNC.rgba(0,0,0,110), FUNC.sz(3))  -- 陰影 -- shadow
                ImGui.DrawList_AddRectFilled(rt_dl, fx - kov, handle_y, fx + fader_w + kov, handle_y + handle_h, FUNC.dim_c(hcol), FUNC.sz(3))
              end

              -- 0dB參考線 -- 0dB reference line
              local zero_frac = FUNC.clamp((0 - prefs.vol_min) / (prefs.vol_max - prefs.vol_min), 0, 1)
              local zero_y = fy + fader_h - math.floor(fader_h * zero_frac)
              ImGui.DrawList_AddLine(rt_dl, fx + 2, zero_y, fx + fader_w - 2, zero_y, FUNC.rgba(180, 180, 180, 40), 1)

              -- 選取邊框 / dropdown hover highlight / output_map顏色 -- selection border / hover highlight / output_map color
              local is_dd_highlight = (popup._rt_hover_hi == hi)
              local omap_col = (not is_unassigned) and FUNC.omap_color(hw.ch) or -1
              local omap_col_im = omap_col >= 0 and FUNC.col2im(omap_col) or nil
              if sel_this then
                ImGui.DrawList_AddRect(rt_dl, fx, fy, fx + fader_w, fy + fader_h, C.gold, 3, 0, FUNC.sz(2.5))
              elseif is_dd_highlight then
                ImGui.DrawList_AddRect(rt_dl, fx, fy, fx + fader_w, fy + fader_h, FUNC.rgba(255, 200, 80, 120), 3, 0, FUNC.sz(2.5))
              elseif omap_col_im then
                ImGui.DrawList_AddRect(rt_dl, fx, fy, fx + fader_w, fy + fader_h, omap_col_im, 3, 0, FUNC.sz(1.5))
              else
                ImGui.DrawList_AddRect(rt_dl, fx, fy, fx + fader_w, fy + fader_h, FUNC.dim_c(C.line), FUNC.rad("m"), 0, 1)
              end

              -- dB文字（滑桿內底部） -- dB text at fader bottom
              if is_unassigned then
                local dtxt = "--"
                local dtw = ImGui.CalcTextSize(ctx, dtxt)
                ImGui.DrawList_AddText(rt_dl, fx + (fader_w - dtw) * 0.5, fy + (fader_h - FUNC.sz(11)) * 0.5, FUNC.rgba(100,100,110), dtxt)
              else
                local vol_txt = hw.vol_db <= prefs.vol_min and "-inf" or string.format("%.0f", hw.vol_db)
                local vtw = ImGui.CalcTextSize(ctx, vol_txt)
                if vtw <= fader_w then ImGui.DrawList_AddText(rt_dl, fx + (fader_w - vtw) * 0.5, fy + fader_h - FUNC.sz(13), C.text, vol_txt) end  -- 太窄就不顯示 -- hide when too narrow
              end

              -- 互動區 -- interaction area
              ImGui.SetCursorScreenPos(ctx, fx, fy)
              ImGui.InvisibleButton(ctx, fid, fader_w, fader_h)
              local f_hov = ImGui.IsItemHovered(ctx)
              local f_act = ImGui.IsItemActive(ctx)

              if not is_unassigned then
                -- 雙擊fader → inline dB輸入 -- double-click fader → inline dB input
                if f_hov and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left()) then
                  db_edit.active = true; db_edit.idx = hi
                  db_edit.buf = hw.vol_db <= prefs.vol_min and "-inf" or string.format("%.1f", hw.vol_db)
                  db_edit.focused = false
                elseif f_act then
                  -- 需拖曳才改音量，單擊不觸發 -- require drag to change volume, ignore click
                  local dx, dy = ImGui.GetMouseDelta(ctx)
                  if math.abs(dx) > 0 or math.abs(dy) > 0 then
                    local _, my = ImGui.GetMousePos(ctx)
                    local frac = FUNC.clamp(1 - (my - fy) / fader_h, 0, 1)
                    hw.vol_db = prefs.vol_min + frac * (prefs.vol_max - prefs.vol_min)
                    FUNC.route_update_vol(c)
                    FUNC.save_cues()
                  end
                end
              end
              -- 點擊選取 -- click to select
              if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left()) then
                local cmd = ImGui.IsKeyDown(ctx, ImGui.Mod_Super())
                if cmd then rsel[hi] = not rsel[hi] or nil
                else rsel = {}; rsel[hi] = true; popup.route_sel = rsel end
              end

              -- hover tooltip (顯示alias) -- show alias on hover
              if f_hov and not is_unassigned then
                ImGui.SetTooltip(ctx, string.format("%s\n%.1f dB", FUNC.omap_alias(hw.ch), hw.vol_db))
              end

              -- ─── dB inline edit (浮在fader底部) ─── dB inline edit overlay at fader bottom
              if db_edit.active and db_edit.idx == hi then
                local ie_y = fy + fader_h - FUNC.sz(18)
                ImGui.SetCursorScreenPos(ctx, fx, ie_y)
                ImGui.SetNextItemWidth(ctx, fader_w)
                ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding(), 1, 1)
                local changed, buf = ImGui.InputText(ctx, "##rt_db_edit"..hi, db_edit.buf,
                  ImGui.InputTextFlags_EnterReturnsTrue() | ImGui.InputTextFlags_AutoSelectAll())
                db_edit.buf = buf
                local deact_edit = ImGui.IsItemDeactivatedAfterEdit(ctx)
                local deact = ImGui.IsItemDeactivated(ctx)
                ImGui.PopStyleVar(ctx, 1)
                if not db_edit.focused then
                  ImGui.SetKeyboardFocusHere(ctx, -1)
                  db_edit.focused = true
                end
                -- commit: Enter或失焦且有編輯 -- commit on Enter or deactivate-after-edit
                if changed or deact_edit then
                  local num = tonumber(buf)
                  if num then hw.vol_db = FUNC.clamp(num, prefs.vol_min, prefs.vol_max)
                  elseif buf == "-inf" or buf == "inf" then hw.vol_db = prefs.vol_min end
                  FUNC.route_update_vol(c); FUNC.save_cues()
                  db_edit.active = false
                elseif deact then
                  -- 失焦但未編輯(例如Escape或直接點走) -- deactivated without edit (Escape or click away without change)
                  db_edit.active = false
                end
              end

              -- ─── Channel label（滑桿下方，置中對齊fader）：dropdown顯示全名，label顯示編號 ─── dropdown shows full name, label shows number
              local ch_label = is_unassigned and "--" or tostring(FUNC.omap_num(hw.ch))
              local dd_y = fy + fader_h + FUNC.sz(2)
              local dd_w = fader_w + fader_gap - FUNC.sz(2)
              local dd_x = fx + math.floor(fader_w * 0.5) - math.floor(dd_w * 0.5)  -- 以fader中心對齊 -- center on fader

              -- channel label 外框 -- channel label border
              ImGui.DrawList_AddRect(rt_dl, dd_x, dd_y, dd_x + dd_w, dd_y + label_h, C.btn, 2, 0, 1)

              ImGui.SetCursorScreenPos(ctx, dd_x, dd_y)
              ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg(), FUNC.rgba(0,0,0,0))
              ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered(), FUNC.rgba(255,255,255,15))
              ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding(), 0, 0)
              ImGui.SetNextItemWidth(ctx, dd_w)
              if ImGui.BeginCombo(ctx, "##rt_ch"..hi, "##", ImGui.ComboFlags_NoArrowButton()) then
                for oi = 0, total_num_outs - 1 do
                  local out_name = reaper.GetOutputChannelName(oi) or ("Out "..oi+1)
                  local owner_hi = used_chs[oi]
                  local is_used = (owner_hi ~= nil and owner_hi ~= hi)  -- 被其他fader佔用 -- used by another fader
                  if is_used then
                    -- 灰化：已被其他fader佔用 -- greyed out: used by another fader
                    ImGui.PushStyleColor(ctx, ImGui.Col_Text(), FUNC.rgba(80, 80, 90))
                    ImGui.Selectable(ctx, out_name.."##rto"..oi, false, ImGui.SelectableFlags_Disabled())
                    ImGui.PopStyleColor(ctx, 1)
                    -- hover時highlight對應fader -- highlight the owning fader on hover
                    if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled()) then
                      popup._rt_hover_hi = owner_hi
                    end
                  else
                    if ImGui.Selectable(ctx, out_name.."##rto"..oi, oi == hw.ch) then
                      -- 更新used_chs -- update used_chs
                      if hw.ch >= 0 then used_chs[hw.ch] = nil end
                      hw.ch = oi
                      used_chs[oi] = hi
                      FUNC.route_apply_live(c)
                      FUNC.save_cues()
                    end
                  end
                end
                ImGui.EndCombo(ctx)
              end
              ImGui.PopStyleVar(ctx, 1)
              ImGui.PopStyleColor(ctx, 2)
              -- draw number text over the combo (置中) -- center number text
              ImGui.PushFont(ctx, FONT, FUNC.sz(11))
              local ltw = ImGui.CalcTextSize(ctx, ch_label)
              ImGui.PopFont(ctx)
              local lbl_col = is_unassigned and FUNC.rgba(100, 100, 110) or FUNC.rgba(170, 170, 180)
              ImGui.DrawList_AddTextEx(rt_dl, FONT, FUNC.sz(11),
                dd_x + (dd_w - ltw) * 0.5, dd_y, lbl_col, ch_label)

              fx = fx + slot_w
            end

            -- ═══ +/- 按鈕（左下方水平排列） ═══ -- +/- buttons at bottom-left horizontal
            local btn_y = fy + fader_h + label_h + FUNC.sz(6)
            local btn_x = rt_sx + rt_pad

            ImGui.SetCursorScreenPos(ctx, btn_x, btn_y)
            if FUNC.draw_pm_btn("##rt_add", "+", btn_sz, C.primary, C.primary_h, C.primary_hi) then
              -- 新增虛擬channel（未指定，ch=-1）-- add unassigned virtual channel (ch=-1)
              if not c.route_hw then c.route_hw = {} end
              c.route_hw[#c.route_hw+1] = {ch=-1, vol_db=0}
              FUNC.route_apply_live(c)
              FUNC.save_cues()
            end

            ImGui.SameLine(ctx, 0, FUNC.sz(4))
            local has_sel = false
            for _, v in pairs(rsel) do if v then has_sel = true; break end end
            local rt_del_col = has_sel and C.text or FUNC.rgba(80,80,80)
            if FUNC.draw_pm_btn("##rt_del", "-", btn_sz, C.btn, C.danger, C.danger_h, rt_del_col) and has_sel then
              -- 刪除選中的虛擬channel（從後往前） -- delete selected virtual channels (back-to-front)
              local to_del = {}
              for idx, v in pairs(rsel) do if v then to_del[#to_del+1] = idx end end
              table.sort(to_del, function(a,b) return a > b end)
              for _, di in ipairs(to_del) do
                if c.route_hw and di <= #c.route_hw then table.remove(c.route_hw, di) end
              end
              popup.route_sel = {}; rsel = popup.route_sel
              FUNC.route_apply_live(c)
              FUNC.save_cues()
            end

            -- Marquee選取（在空白處拖曳） -- marquee selection on empty area drag
            if not ImGui.IsAnyItemActive(ctx) and ImGui.IsWindowHovered(ctx) then
              if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left()) then
                local mx, my = ImGui.GetMousePos(ctx)
                if mx >= rt_sx and mx <= rt_sx + rt_w and my >= rt_sy and my <= rt_sy + rt_h then
                  popup._rt_marquee = {x0=mx, y0=my, active=true}
                  popup.route_sel = {}; rsel = popup.route_sel
                end
              end
            end
            if popup._rt_marquee and popup._rt_marquee.active then
              if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left()) then
                local mx, my = ImGui.GetMousePos(ctx)
                local m = popup._rt_marquee
                local mx0, mx1 = math.min(m.x0, mx), math.max(m.x0, mx)
                local my0, my1 = math.min(m.y0, my), math.max(m.y0, my)
                if math.abs(mx - m.x0) > 3 or math.abs(my - m.y0) > 3 then
                  ImGui.DrawList_AddRectFilled(rt_dl, mx0, my0, mx1, my1, FUNC.rgba(255, 200, 80, 30))
                  ImGui.DrawList_AddRect(rt_dl, mx0, my0, mx1, my1, FUNC.rgba(255, 200, 80, 120), 0, 0, 1)
                  rsel = {}
                  local mfx = rt_sx + rt_pad + scale_w
                  for hi2 = 1, #hw_outs do
                    local fr = mfx + fader_w
                    local fb = fy + fader_h
                    if mfx < mx1 and fr > mx0 and fy < my1 and fb > my0 then
                      rsel[hi2] = true
                    end
                    mfx = mfx + slot_w
                  end
                  popup.route_sel = rsel
                end
              else
                popup._rt_marquee = nil
              end
            end

            ImGui.PopFont(ctx)
          end
        end

end
