-- ui_edit_waveform.lua — Edit panel: Waveform/Source tab
-- waveform for PLAY/FADE/GROUP, FX chain for MIDI

function FUNC.draw_edit_section_waveform(ectx)
  local c, apply, multi, valid = ectx.c, ectx.apply, ectx.multi, ectx.valid
  local all_play, all_fade, all_midi = ectx.all_play, ectx.all_fade, ectx.all_midi
  local fade_from_vol, fade_from_pan, fade_from_pitch = ectx.fade_from_vol, ectx.fade_from_pan, ectx.fade_from_pitch
  local EDGE_PAD, ELEM_SPC = ectx.EDGE_PAD, ectx.ELEM_SPC
  local apply_delta = ectx.apply_delta
  local vdrag = ectx.vdrag
        -- SECTION: SOURCE — waveform for PLAY/FADE/GROUP, FX chain for MIDI
        -- ═══════════════════════════════════════════════════════
        -- ═══════════════════════════════════════════════════════
        ImGui.Dummy(ctx, 0, FUNC.sz(2))  -- 標題列與內容間距 -- gap between header and content
        if not multi and all_midi then
          -- ═══ MIDI Source: left=Track FX list (envelope-style), right=reserved for Phase 2B ═══
          local mtab_w, mtab_h = ImGui.GetContentRegionAvail(ctx)
          local mepad = FUNC.sz(EDGE_PAD)
          -- 左欄寬度跟著面板伸縮：佔 28%，限 160~240 -- left column flexes: 28% of width, 160~240
          local mleft_core = FUNC.clamp(math.floor(mtab_w * 0.28), FUNC.sz(160), FUNC.sz(240))
          local mleft_w = mleft_core + mepad
          local mright_w = mtab_w - mleft_w

          -- ─── Left column: FX chain ─── matches envelope section layout
          ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding(), mepad, 0)
          if ImGui.BeginChild(ctx, "##midi_left", mleft_w, mtab_h, ImGui.ChildFlags_AlwaysUseWindowPadding()) then
            ImGui.PushFont(ctx, FONT, FUNC.sz(13))
            local tr = FUNC.get_tr(c.track_idx)
            c._midi_fx_sel = c._midi_fx_sel or {}
            local sel_set = c._midi_fx_sel

            local mfx_indent = FUNC.sz(12)
            ImGui.Indent(ctx, mfx_indent)

            local mfx_dl   = ImGui.GetWindowDrawList(ctx)
            local mfx_row_h = ImGui.GetFrameHeight(ctx) - FUNC.sz(3)
            local mfx_fsz  = FUNC.sz(13)
            local mfx_lbl_w = mleft_core - FUNC.sz(25)  -- 原本 160→135 -- was 135 at 160
            local mfx_btn_sz = FUNC.sz(16)

            -- local icon button (same look as env_icon_btn) -- 與 env 區塊同樣的小按鈕
            local function mfx_btn(id, label, bg, bg_h, bg_a, txt_col)
              return FUNC.draw_pm_btn(id, label, mfx_btn_sz, bg, bg_h, bg_a, txt_col)
            end

            -- ─── Top of left column: Device dropdown (Message) 或 Trim In/Out (Sequence) ───
            if c.midi_mode == "message" then
              -- Device dropdown 與 Basic tab 共用 c.midi_device 即同步 -- shared field = auto-sync
              local n_dev_m = reaper.GetNumMIDIOutputs()
              local cur_dev_m = c.midi_device or -1
              local dest_label_m
              if cur_dev_m < 0 then
                dest_label_m = "Internal"
              else
                local _, dn_m = reaper.GetMIDIOutputName(cur_dev_m, "")
                dest_label_m = (dn_m and dn_m ~= "") and dn_m or ("Device " .. tostring(cur_dev_m))
              end
              ImGui.AlignTextToFramePadding(ctx)
              ImGui.Text(ctx, "Device")
              ImGui.SameLine(ctx, 0, FUNC.sz(6))
              ImGui.SetNextItemWidth(ctx, -1)
              if ImGui.BeginCombo(ctx, "##msrc_dev_left", dest_label_m) then
                if ImGui.Selectable(ctx, "Internal", cur_dev_m < 0) then apply("midi_device", -1) end
                for di = 0, n_dev_m - 1 do
                  local _, dn_m2 = reaper.GetMIDIOutputName(di, "")
                  local dl_m = (dn_m2 and dn_m2 ~= "") and dn_m2 or ("Device " .. tostring(di))
                  if ImGui.Selectable(ctx, dl_m, di == cur_dev_m) then apply("midi_device", di) end
                end
                ImGui.EndCombo(ctx)
              end
              ImGui.Dummy(ctx, 0, FUNC.sz(3))
              ImGui.Separator(ctx)
              ImGui.Dummy(ctx, 0, FUNC.sz(3))
            end
            -- realive-internal MIDI trim; 與 audio q 一致：只顯示當下 timecode + clock/note 圖示切換
            if c.midi_mode == "sequence" then
              local full_sec = FUNC.midi_calc_full_dur_sec(c)  -- 未套 trim 的總秒數
              if full_sec > 0 then
                local bpm = math.max(1, c.midi_bpm or 120)
                local sec2qn = bpm / 60.0
                local qn2sec = 60.0 / bpm
                local ts_sec = math.max(0, c.trim_start or 0)
                local te_sec = (c.trim_end and c.trim_end > 0) and math.min(full_sec, c.trim_end) or full_sec
                c._midi_trim_unit = c._midi_trim_unit or "sec"  -- "sec" | "qn"
                local is_qn = c._midi_trim_unit == "qn"
                -- QN 模式採音樂家習慣：第一拍 = 1（1-indexed）
                -- QN display is 1-indexed (musician convention: first beat = beat 1)
                local qn_off = is_qn and 1 or 0
                local full_disp = is_qn and (full_sec * sec2qn + qn_off) or full_sec
                local trim_indent = FUNC.sz(12)
                local icon_sz_t = FUNC.sz(16)
                local note_sym_t = NOTE_VALUES[NOTE_DEFAULT_IDX].sym

                -- 畫 clock 或 note 圖示切換鈕（借用 audio q 的樣式）
                -- draw clock/note icon toggle mirroring audio q's draw_timing_row button
                local function draw_unit_toggle(uid)
                  local btn_col = is_qn and FUNC.rgba(120,90,30) or C.field
                  local btn_hov = is_qn and FUNC.rgba(140,110,40) or C.btn_h
                  local bx, by = ImGui.GetCursorScreenPos(ctx)
                  local clicked = ImGui.InvisibleButton(ctx, uid, icon_sz_t, icon_sz_t)
                  local hov_b = ImGui.IsItemHovered(ctx)
                  local bdl = ImGui.GetWindowDrawList(ctx)
                  ImGui.DrawList_AddRectFilled(bdl, bx, by, bx+icon_sz_t, by+icon_sz_t, hov_b and btn_hov or btn_col, FUNC.sz(3))
                  if is_qn then
                    ImGui.PushFont(ctx, FONT_NOTE, FUNC.sz(15))
                    local tw, th = ImGui.CalcTextSize(ctx, note_sym_t, 0, 0)
                    ImGui.DrawList_AddTextEx(bdl, FONT_NOTE, FUNC.sz(15),
                      bx + (icon_sz_t - tw)/2, by + (icon_sz_t - th)/2 + FUNC.sz(6),
                      FUNC.rgba(220,190,80), note_sym_t)
                    ImGui.PopFont(ctx)
                  else
                    local cx_i, cy_i = bx + icon_sz_t/2, by + icon_sz_t/2
                    local r = icon_sz_t * 0.35
                    ImGui.DrawList_AddCircle(bdl, cx_i, cy_i, r, FUNC.rgba(180,180,200), 12, 1.2)
                    ImGui.DrawList_AddLine(bdl, cx_i, cy_i, cx_i, cy_i - r*0.7, FUNC.rgba(180,180,200), 1.2)
                    ImGui.DrawList_AddLine(bdl, cx_i, cy_i, cx_i + r*0.5, cy_i, FUNC.rgba(180,180,200), 1.2)
                  end
                  if hov_b then ImGui.SetTooltip(ctx, is_qn and "Switch to Time" or "Switch to BPM") end
                  if clicked then c._midi_trim_unit = is_qn and "sec" or "qn" end
                end

                -- 格式化：只顯示當下時間碼 -- show current timecode only
                local function fmt_t_mt(v)
                  return is_qn and string.format("%.2f q", v) or FUNC.fmt_t(v)
                end
                local function parse_t_mt(s)
                  if is_qn then
                    local clean = ((s or ""):gsub("[^%d%.%-]", ""))  -- 包一層括號丟掉 gsub 的 count
                    return tonumber(clean)
                  end
                  return FUNC.parse_t(s)
                end

                if ImGui.BeginTable(ctx, "##midi_trim_row", 3, 0) then
                  -- 欄位：[toggle] [label] [vdrag] — s/q 切換鈕移到 In 前方
                  -- columns: [toggle] [label] [vdrag] — unit toggle moved before In
                  ImGui.TableSetupColumn(ctx, "l", ImGui.TableColumnFlags_WidthFixed(), icon_sz_t + FUNC.sz(4))
                  ImGui.TableSetupColumn(ctx, "m", ImGui.TableColumnFlags_WidthFixed(), FUNC.sz(24))
                  ImGui.TableSetupColumn(ctx, "r", ImGui.TableColumnFlags_WidthStretch(), 1)
                  local ts_disp = is_qn and (ts_sec * sec2qn + qn_off) or ts_sec
                  local te_disp    = is_qn and (te_sec * sec2qn + qn_off) or te_sec
                  local te_disp_hi = te_disp  -- In vdrag 的上限 = 當前 Out 顯示值
                  local in_lo = qn_off  -- QN 模式下限 = 1，sec 模式下限 = 0
                  local spd = full_disp / FUNC.sz(500)
                  -- In
                  ImGui.TableNextRow(ctx); ImGui.TableNextColumn(ctx)
                  draw_unit_toggle("##midi_trim_unit_in")
                  ImGui.TableNextColumn(ctx)
                  ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "In")
                  ImGui.TableNextColumn(ctx)
                  local tsch, tsnv = vdrag("emtrim_s", ts_disp, spd, in_lo, te_disp_hi - 0.001, fmt_t_mt, parse_t_mt)
                  if tsch then
                    local new_sec = is_qn and ((tsnv - qn_off) * qn2sec) or tsnv
                    apply("trim_start", FUNC.clamp(new_sec, 0, te_sec - 0.001))
                  end
                  -- Out
                  ImGui.TableNextRow(ctx); ImGui.TableNextColumn(ctx)  -- 左欄留空對齊 -- blank for alignment
                  ImGui.TableNextColumn(ctx)
                  ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Out")
                  ImGui.TableNextColumn(ctx)
                  local tech, tenv = vdrag("emtrim_e", te_disp, spd, ts_disp + 0.001, full_disp, fmt_t_mt, parse_t_mt)
                  if tech then
                    local new_sec = is_qn and ((tenv - qn_off) * qn2sec) or tenv
                    if new_sec >= full_sec - 0.001 then new_sec = 0 end
                    apply("trim_end", new_sec)
                  end
                  ImGui.EndTable(ctx)
                end
                ImGui.Dummy(ctx, 0, FUNC.sz(3))
                ImGui.Separator(ctx)
                ImGui.Dummy(ctx, 0, FUNC.sz(3))
              end
            end

            -- 只有 Internal device 才顯示 FX 區塊 -- FX block only when device=Internal
            if (c.midi_device or -1) < 0 then
            -- Header row: "Track FX" + / - buttons -- 標題 + 加減按鈕
            ImGui.AlignTextToFramePadding(ctx)
            ImGui.Text(ctx, "Track FX")
            ImGui.SameLine(ctx, 0, FUNC.sz(8))
            if mfx_btn("##mfx_add", "+", C.primary, C.primary_h, C.primary_hi) then
              if tr then
                reaper.SetOnlyTrackSelected(tr)
                reaper.Main_OnCommand(40271, 0)  -- Track: View FX chain
              end
            end
            if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Open REAPER FX chain (add from there)") end
            ImGui.SameLine(ctx, 0, FUNC.sz(4))
            local any_sel = false
            for _ in pairs(sel_set) do any_sel = true; break end
            local del_col = any_sel and FUNC.dim_c(C.text) or FUNC.rgba(80,80,80)
            if mfx_btn("##mfx_del", "-", C.btn, C.danger, C.danger_h, del_col) and any_sel and tr then
              local to_del = {}
              for k in pairs(sel_set) do to_del[#to_del+1] = k end
              table.sort(to_del, function(a,b) return a>b end)  -- 倒序刪除保留 index -- desc to preserve idx
              for _, idx in ipairs(to_del) do reaper.TrackFX_Delete(tr, idx) end
              c._midi_fx_sel = {}
            end
            ImGui.Dummy(ctx, 0, FUNC.sz(3))

            if not tr then
              ImGui.PushStyleColor(ctx, ImGui.Col_Text(), FUNC.rgba(180,100,100))
              ImGui.Text(ctx, "Track missing")
              ImGui.PopStyleColor(ctx)
            else
              local fx_count = reaper.TrackFX_GetCount(tr)
              for k in pairs(sel_set) do if k >= fx_count then sel_set[k] = nil end end
              local pending_delete, pending_src, pending_dst, pending_copy = nil, nil, nil, false

              -- FX row（同 env_row 風格：色框 + 文字，選中時反白填色）-- same look as env_row
              for fi = 0, fx_count - 1 do
                local _, fxname_raw = reaper.TrackFX_GetFXName(tr, fi, "")
                local fxname = FUNC.fx_env_short_name(fxname_raw or "")
                local enabled = reaper.TrackFX_GetEnabled(tr, fi)
                local open = reaper.TrackFX_GetOpen(tr, fi)
                local is_sel = sel_set[fi] == true
                -- 依 FX 名稱 hash 取 GRP_COLS 配色，bypass 時降亮度 -- per-FX hue from name hash; bypass dims
                local h = 0
                for ci = 1, #fxname do h = (h * 131 + fxname:byte(ci)) % 1000003 end
                local col = GRP_COLS[(h % #GRP_COLS) + 1]
                if not enabled then col = FUNC.dim_c(col) end

                local lx, ly = ImGui.GetCursorScreenPos(ctx)
                ImGui.InvisibleButton(ctx, "##mfx"..fi, mfx_lbl_w, mfx_row_h)
                local hov = ImGui.IsItemHovered(ctx)
                local clicked = ImGui.IsItemClicked(ctx, 0)

                if is_sel then
                  local ar = (col>>24)&0xFF; local ag = (col>>16)&0xFF; local ab = (col>>8)&0xFF
                  ImGui.DrawList_AddRectFilled(mfx_dl, lx-2, ly, lx+mfx_lbl_w+2, ly+mfx_row_h, FUNC.rgba(ar,ag,ab,200), 3)
                elseif hov then
                  ImGui.DrawList_AddRectFilled(mfx_dl, lx-2, ly, lx+mfx_lbl_w+2, ly+mfx_row_h, FUNC.rgba(60,65,80,180), 3)
                end
                ImGui.DrawList_AddRect(mfx_dl, lx-1, ly, lx+mfx_lbl_w+1, ly+mfx_row_h, col, 3, 0, 1)

                -- 文字 -- text
                local txt_col
                if is_sel then
                  local ar = (col>>24)&0xFF; local ag = (col>>16)&0xFF; local ab = (col>>8)&0xFF
                  local lum = ar*0.299 + ag*0.587 + ab*0.114
                  txt_col = lum > 128 and FUNC.rgba(0,0,0) or FUNC.rgba(255,255,255)
                else
                  txt_col = enabled and col or FUNC.rgba(130,130,130,200)
                end
                local label_txt = string.format("%d. %s", fi+1, fxname)
                local act_font = is_sel and FONT_B or FONT
                local act_fsz = is_sel and (mfx_fsz + FUNC.sz(0.5)) or mfx_fsz
                ImGui.PushFont(ctx, act_font, act_fsz)
                local _, txt_h = ImGui.CalcTextSize(ctx, label_txt, 0, 0)
                local ty = ly + math.max(0, math.floor((mfx_row_h - txt_h) * 0.5))
                ImGui.DrawList_PushClipRect(mfx_dl, lx, ly, lx+mfx_lbl_w, ly+mfx_row_h, true)
                if hov then
                  FUNC.draw_marquee(mfx_dl, act_font, act_fsz, label_txt, txt_col,
                    lx+FUNC.sz(4), ty, mfx_lbl_w-FUNC.sz(8), txt_h, "mfx"..fi..c.id,
                    {auto=true, speed=FUNC.sz(28), gap=6})
                else
                  ImGui.DrawList_AddText(mfx_dl, lx+FUNC.sz(4), ty, txt_col, label_txt)
                end
                ImGui.PopFont(ctx)
                ImGui.DrawList_PopClipRect(mfx_dl)

                -- drag source + target
                if ImGui.BeginDragDropSource(ctx, ImGui.DragDropFlags_None()) then
                  ImGui.SetDragDropPayload(ctx, "MIDI_FX_REORDER", tostring(fi))
                  ImGui.Text(ctx, label_txt)
                  ImGui.EndDragDropSource(ctx)
                end
                if ImGui.BeginDragDropTarget(ctx) then
                  local ok, pl = ImGui.AcceptDragDropPayload(ctx, "MIDI_FX_REORDER", ImGui.DragDropFlags_None())
                  if ok and pl then
                    local src = tonumber(pl)
                    if src and src ~= fi then
                      pending_src = src; pending_dst = fi
                      pending_copy = ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl())
                    end
                  end
                  ImGui.EndDragDropTarget(ctx)
                end

                if clicked then
                  local alt   = ImGui.IsKeyDown(ctx, ImGui.Mod_Alt())
                  local shift = ImGui.IsKeyDown(ctx, ImGui.Mod_Shift())
                  local cmd   = ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl())
                  if alt then pending_delete = fi
                  elseif shift then reaper.TrackFX_SetEnabled(tr, fi, not enabled)
                  elseif cmd then sel_set[fi] = (not sel_set[fi]) and true or nil
                  else
                    if open then
                      reaper.TrackFX_Show(tr, fi, 2); reaper.TrackFX_Show(tr, fi, 0)
                    else
                      reaper.TrackFX_Show(tr, fi, 3)
                      FUNC.fx_window_recenter_if_needed(tr, fi)
                    end
                    for k in pairs(sel_set) do sel_set[k] = nil end
                    sel_set[fi] = true
                  end
                end
              end

              if pending_delete then
                reaper.TrackFX_Delete(tr, pending_delete)
                sel_set[pending_delete] = nil
              end
              if pending_src and pending_dst then
                reaper.TrackFX_CopyToTrack(tr, pending_src, tr, pending_dst, not pending_copy)
              end

              if fx_count == 0 then
                ImGui.PushStyleColor(ctx, ImGui.Col_Text(), FUNC.rgba(120,120,130))
                ImGui.Text(ctx, "(no FX)")
                ImGui.PopStyleColor(ctx)
              end
            end

            end  -- end FX block (Internal only)

            ImGui.Unindent(ctx, mfx_indent)

            -- 空白處點擊：清除 selection -- click blank clears selection
            local rem_w, rem_h = ImGui.GetContentRegionAvail(ctx)
            if rem_h > 0 then
              ImGui.InvisibleButton(ctx, "##midi_left_blank", math.max(1, rem_w), rem_h)
              if ImGui.IsItemClicked(ctx) then c._midi_fx_sel = {}; FUNC.clear_inner_sels() end
            end

            ImGui.PopFont(ctx)
            ImGui.EndChild(ctx)
          end
          ImGui.PopStyleVar(ctx)

          -- ─── Right column: MIDI editor panel (piano roll + toolbar + chart) ───
          if mright_w > FUNC.sz(100) then
            ImGui.SameLine(ctx, 0, 0)
            if ImGui.BeginChild(ctx, "##midi_right", mright_w, mtab_h, ImGui.ChildFlags_None(), ImGui.WindowFlags_NoScrollWithMouse() | ImGui.WindowFlags_NoScrollbar()) then
              local mr_w_full = ImGui.GetContentRegionAvail(ctx) - mepad
              local _, mr_h_avail = ImGui.GetContentRegionAvail(ctx)
              local mr_x, mr_y = ImGui.GetCursorScreenPos(ctx)
              if c.midi_mode == "message" then
                FUNC.draw_midi_message_table(c, apply)
              else
                FUNC.draw_midi_editor_panel(c, mr_x, mr_y, mr_w_full, mr_h_avail)
              end
              ImGui.EndChild(ctx)
            end
          end
        else
        local tab_w, tab_h = ImGui.GetContentRegionAvail(ctx)  -- Dummy後重新測量避免溢出 -- re-measure after Dummy to prevent overflow
        local all_group = not multi and c.type == "GROUP"
        local has_display = (not multi and all_play) or (not multi and all_fade) or all_group
        local epad = FUNC.sz(EDGE_PAD)
        -- 左欄寬度跟著面板伸縮：佔 28%，限 160~240 -- left column flexes: 28% of width, 160~240
        local left_core = FUNC.clamp(math.floor(tab_w * 0.28), FUNC.sz(160), FUNC.sz(240))
        local left_w = left_core + epad  -- 含WindowPadding -- incl WindowPadding
        local right_w = tab_w - left_w  -- 圖表區延伸到section邊界，epad在內部扣 -- chart area extends to section edge, epad subtracted inside

        -- ─── 控制區：Trim + Env ─── -- controls: trim + envelope dropdown
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding(), epad, 0)  -- 內容左右EDGE_PAD，scrollbar在右padding之後貼邊 -- content padded, scrollbar after right padding flush to edge
        if ImGui.BeginChild(ctx, "##wf_left", has_display and left_w or -1, tab_h, ImGui.ChildFlags_AlwaysUseWindowPadding()) then
          ImGui.PushFont(ctx, FONT, FUNC.sz(13))

        -- Trim In/Out（含GROUP有效trim）-- includes parent GROUP trim effect
        if not multi and all_play then
          local dur = FUNC.calc_dur(c.track_idx)
          if dur > 0 then
            if c.trim_end <= 0 or c.trim_end > dur then c.trim_end = dur end
            -- GROUP有效trim -- effective trim accounting for parent GROUP
            local eff_ts, eff_te = FUNC.get_eff_trim(c)
            if eff_te <= 0 then eff_te = dur end
            local grp_off_s = eff_ts - (c.trim_start or 0)  -- GROUP造成的start偏移
            local grp_off_e = eff_te - ((c.trim_end > 0) and c.trim_end or dur)  -- GROUP造成的end偏移(通常<=0)
            local trim_spd = dur / (FUNC.sz(500))
            local trim_indent = FUNC.sz(12)  -- 左方邊距 -- left margin
            -- 垂直排列：In → Out -- vertical layout: In then Out
            if ImGui.BeginTable(ctx, "##trim_row", 2, 0) then
              ImGui.TableSetupColumn(ctx, "", ImGui.TableColumnFlags_WidthFixed(), FUNC.sz(24) + trim_indent)
              ImGui.TableSetupColumn(ctx, "", ImGui.TableColumnFlags_WidthStretch(), 1)
              -- In
              ImGui.TableNextRow(ctx); ImGui.TableNextColumn(ctx)
              ImGui.Indent(ctx, trim_indent); ImGui.Text(ctx, "In"); ImGui.Unindent(ctx, trim_indent)
              ImGui.TableNextColumn(ctx)
              local tsch, tsnv = vdrag("ets", eff_ts, trim_spd, grp_off_s, eff_te - 0.01,
                "%s", function(s) return FUNC.parse_t(s) end)
              if tsch then
                c.trim_start = FUNC.clamp(tsnv - grp_off_s, 0, c.trim_end - 0.01)
                if c.state == STATE.RUNNING and c.play_t0 > 0 then
                  local cr2 = (c.rate and c.rate > 0) and c.rate or 1.0
                  local ph_t = (c.play_offset or 0) + (reaper.time_precise() - c.play_t0) * cr2
                  -- tsnv 是顯示值（effective 絕對時間），與 ph_t 同座標；比較 & replay 前重算 _rt_trim_start 保留 group offset
                  -- tsnv is effective absolute time (same coord as ph_t); refresh _rt_trim_start before replay to preserve group offset
                  if tsnv > ph_t then
                    FUNC.apply_parent_group_trim(c)
                    FUNC.play_cue(c)
                  end
                end
              end
              -- Out
              ImGui.TableNextRow(ctx); ImGui.TableNextColumn(ctx)
              ImGui.Indent(ctx, trim_indent); ImGui.Text(ctx, "Out"); ImGui.Unindent(ctx, trim_indent)
              ImGui.TableNextColumn(ctx)
              local tech, tenv = vdrag("ete", eff_te, trim_spd, eff_ts + 0.01, dur + grp_off_e,
                "%s", function(s) return FUNC.parse_t(s) end)
              if tech then
                c.trim_end = FUNC.clamp(tenv - grp_off_e, c.trim_start + 0.01, dur)
                if c.state == STATE.RUNNING and c.play_t0 > 0 then
                  local cr2 = (c.rate and c.rate > 0) and c.rate or 1.0
                  local ph_t = (c.play_offset or 0) + (reaper.time_precise() - c.play_t0) * cr2
                  -- tenv 為顯示值 (effective 絕對時間)，與 ph_t 同座標
                  -- tenv is effective absolute time (same coord as ph_t)
                  if tenv <= ph_t then FUNC.kill_cue(c) end
                end
              end
              ImGui.EndTable(ctx)
            end
          end
        elseif multi and all_play then
          if not popup._trim_s_d then popup._trim_s_d = 0 end
          if not popup._trim_e_d then popup._trim_e_d = 0 end
          local trim_indent = FUNC.sz(6)  -- 左方邊距 -- left margin
          if ImGui.BeginTable(ctx, "##trim_row_m", 2, 0) then
            ImGui.TableSetupColumn(ctx, "", ImGui.TableColumnFlags_WidthFixed(), FUNC.sz(28) + trim_indent)
            ImGui.TableSetupColumn(ctx, "", ImGui.TableColumnFlags_WidthStretch(), 1)
            -- In+
            ImGui.TableNextRow(ctx); ImGui.TableNextColumn(ctx)
            ImGui.Indent(ctx, trim_indent); ImGui.Text(ctx, "In+"); ImGui.Unindent(ctx, trim_indent)
            ImGui.TableNextColumn(ctx)
            local tsch, tsnv = vdrag("ets_d", popup._trim_s_d, 0.05, 0, 9999, "+%.2f s")
            if tsch then
              local delta = tsnv - popup._trim_s_d; popup._trim_s_d = tsnv
              apply_delta("trim_start", delta, 0, 9999)
            end
            -- Out-
            ImGui.TableNextRow(ctx); ImGui.TableNextColumn(ctx)
            ImGui.Indent(ctx, trim_indent); ImGui.Text(ctx, "Out-"); ImGui.Unindent(ctx, trim_indent)
            ImGui.TableNextColumn(ctx)
            local tech, tenv = vdrag("ete_d", popup._trim_e_d, -0.05, 0, 9999, "-%.2f s",
              function(s) return math.abs(tonumber(s:gsub("%-","")) or 0) end)
            if tech then
              local delta = tenv - popup._trim_e_d; popup._trim_e_d = tenv
              for _, si in ipairs(valid) do
                local cd = FUNC.calc_dur(cues[si].track_idx)
                if cd > 0 then cues[si].trim_end = FUNC.clamp(cd - tenv, cues[si].trim_start + 0.01, cd) end
              end
            end
            ImGui.EndTable(ctx)
          end
        end

        -- GROUP info + trim + children list（左欄：trim左側 children右側）-- GROUP trim left, children right
        if all_group then
          local gl = FUNC.group_lanes(c)
          local gdur = gl.dur
          ImGui.Text(ctx, string.format("Lanes: %d  Duration: %s", #gl.lanes, FUNC.fmt_t(gdur)))
          if gdur > 0 then
            ImGui.Dummy(ctx, 0, FUNC.sz(2)); ImGui.Separator(ctx); ImGui.Dummy(ctx, 0, FUNC.sz(2))
            -- trim In/Out（x對齊Lanes，輸入框x統一）-- In/Out aligned with Lanes text
            local g_ts = c.trim_start or 0
            local g_te = (c.trim_end and c.trim_end > 0) and c.trim_end or gdur
            local trim_spd = gdur / FUNC.sz(500)
            local spc_x = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing())
            local out_tw = ImGui.CalcTextSize(ctx, "Out")
            local input_off = out_tw + spc_x  -- 輸入框統一偏移量 -- uniform input offset based on "Out" width
            -- In（trim start）
            ImGui.Text(ctx, "In"); ImGui.SameLine(ctx)
            ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + (out_tw - ImGui.CalcTextSize(ctx, "In")))  -- 對齊Out的輸入框x
            ImGui.SetNextItemWidth(ctx, FUNC.sz(100))
            local tsch, tsnv = vdrag("gts", g_ts, trim_spd, 0, g_te - 0.01,
              "%s", function(s) return FUNC.parse_t(s) end)
            if tsch then
              c.trim_start = FUNC.clamp(tsnv, 0, g_te - 0.01)
              -- vdrag影響播放中children的play cursor -- push/replay/kill playing children
              for _, lane in ipairs(gl.lanes) do
                for _, entry in ipairs(lane.entries) do
                  local cc = entry.cue
                  if cc.type == "PLAY" and cc.state == STATE.RUNNING and cc.play_t0 > 0 then
                    local a_s = entry.offset + entry.pre
                    local a_e = a_s + entry.eff_dur
                    local child_group_pos = a_s + (reaper.time_precise() - cc.play_t0)
                    if c.trim_start >= a_e then
                      FUNC.kill_cue(cc)
                    elseif c.trim_start > child_group_pos then
                      local cr = (cc.rate and cc.rate > 0) and cc.rate or 1.0
                      cc._rt_trim_start = (cc.trim_start or 0) + math.max(0, c.trim_start - a_s) * cr
                      FUNC.play_cue(cc)
                    end
                  end
                end
              end
            end
            -- Out（trim end）
            ImGui.Text(ctx, "Out"); ImGui.SameLine(ctx)
            ImGui.SetNextItemWidth(ctx, FUNC.sz(100))
            local tech, tenv = vdrag("gte", g_te, trim_spd, g_ts + 0.01, gdur,
              "%s", function(s) return FUNC.parse_t(s) end)
            if tech then
              c.trim_end = FUNC.clamp(tenv, g_ts + 0.01, gdur)
              -- vdrag影響播放中children的play cursor -- kill children past new end
              for _, lane in ipairs(gl.lanes) do
                for _, entry in ipairs(lane.entries) do
                  local cc = entry.cue
                  if cc.type == "PLAY" and cc.state == STATE.RUNNING and cc.play_t0 > 0 then
                    local a_s = entry.offset + entry.pre
                    local child_group_pos = a_s + (reaper.time_precise() - cc.play_t0)
                    if c.trim_end <= child_group_pos then
                      FUNC.kill_cue(cc)
                    end
                  end
                end
              end
            end
          end
        end

        -- Envelope 標籤堆疊（PLAY cues only）-- vertical label stack for envelopes
        if not multi and all_play then
          ImGui.Dummy(ctx, 0, FUNC.sz(2)); ImGui.Separator(ctx); ImGui.Dummy(ctx, 0, FUNC.sz(2))
          local env_indent = FUNC.sz(12)
          ImGui.Indent(ctx, env_indent)
          c.fx_envs = c.fx_envs or {}

          local env_dl = ImGui.GetWindowDrawList(ctx)
          local row_h = ImGui.GetFrameHeight(ctx) - FUNC.sz(3)
          local fsz = FUNC.sz(13)
          local lbl_w = left_core - FUNC.sz(25)  -- 原本 160→135 -- was 135 at 160

          -- Envelope title + add/remove buttons (route-style) -- 標題 + 加減按鈕
          local env_btn_sz = FUNC.sz(18)        -- 頂部 envelope +/- 較大
          local env_btn_sz_fx = FUNC.sz(14)     -- FX header +/- 較小
          -- helper: 手繪置中文字按鈕 -- draw button with perfectly centered text
          local function env_icon_btn(id, label, bg, bg_hov, bg_act, txt_col, sz_override)
            return FUNC.draw_pm_btn(id, label, sz_override or env_btn_sz, bg, bg_hov, bg_act, txt_col)
          end
          ImGui.AlignTextToFramePadding(ctx)
          ImGui.Text(ctx, "Envelope")
          ImGui.SameLine(ctx, 0, FUNC.sz(8))
          local is_pending = fx_env_pending and fx_env_pending.cue_id == c.id
          local cue_tr = FUNC.get_tr(c.track_idx)
          -- 頂部固定：管理 Track FX(+/-)，× 已移除（pending 取消改點下方提示列）
          -- + : open REAPER FX chain (FX browser) on this cue's track
          if env_icon_btn("##fxe_fx_add", "+", C.primary, C.primary_h, C.primary_hi) then
            if cue_tr then
              reaper.SetOnlyTrackSelected(cue_tr)
              reaper.Main_OnCommand(40271, 0)  -- Track: View FX chain
            end
          end
          if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Open REAPER FX chain (add FX from there)") end
          ImGui.SameLine(ctx, 0, FUNC.sz(4))
          -- - : remove the FX currently focused / shown in REAPER's FX chain on this track
          local can_del_fx, focused_fx_idx = false, nil
          do
            local rv, tr_n, _it_n, fx_n
            if reaper.GetFocusedFX2 then
              rv, tr_n, _it_n, fx_n = reaper.GetFocusedFX2()
            else
              rv, tr_n, _it_n, fx_n = reaper.GetFocusedFX()
            end
            -- rv low bit: 1=track FX focused; tr_n: 0=master, 1+ track; fx_n may have 0x1000000 bit for record-input FX
            if cue_tr and rv and (rv & 1) == 1 and tr_n and tr_n > 0 and fx_n then
              local f_tr = reaper.CSurf_TrackFromID(tr_n, false)
              local fx_idx = fx_n & 0xFFFFFF
              if f_tr == cue_tr and fx_idx < reaper.TrackFX_GetCount(cue_tr) then
                can_del_fx = true; focused_fx_idx = fx_idx
              end
            end
          end
          local del_col_fx = can_del_fx and FUNC.dim_c(C.text) or FUNC.rgba(80, 80, 80)
          if env_icon_btn("##fxe_fx_del", "-", C.btn, C.danger, C.danger_h, del_col_fx) and can_del_fx then
            local fx_guid = reaper.TrackFX_GetFXGUID(cue_tr, focused_fx_idx)
            reaper.TrackFX_Delete(cue_tr, focused_fx_idx)
            if fx_guid then
              for i = #c.fx_envs, 1, -1 do
                if c.fx_envs[i].fx_guid == fx_guid then FUNC.fx_env_remove(c, i) end
              end
              fx_env_edit_idx = nil
            end
            FUNC.save_cues()
          end
          if ImGui.IsItemHovered(ctx) then
            ImGui.SetTooltip(ctx, can_del_fx and "Remove focused FX from track" or "Open/focus an FX in REAPER first to select it for removal")
          end
          ImGui.Dummy(ctx, 0, FUNC.sz(3))

          -- row 畫一列可點擊label -- draw one clickable row label
          local function env_row(key, text, is_visible, is_active, col, on_click, on_rclick, marquee, width)
            local rw = width or lbl_w
            local lx, ly = ImGui.GetCursorScreenPos(ctx)
            ImGui.InvisibleButton(ctx, "##"..key, rw, row_h)
            local hov = ImGui.IsItemHovered(ctx)
            if ImGui.IsItemClicked(ctx, 0) then on_click() end
            if on_rclick and ImGui.IsItemClicked(ctx, 1) then on_rclick() end
            if is_active then
              local ar = (col>>24)&0xFF; local ag = (col>>16)&0xFF; local ab = (col>>8)&0xFF
              ImGui.DrawList_AddRectFilled(env_dl, lx - 2, ly, lx + rw + 2, ly + row_h,
                FUNC.rgba(ar, ag, ab, 200), 3)
            end
            local txt_col
            if is_active then
              local ar = (col>>24)&0xFF; local ag = (col>>16)&0xFF; local ab = (col>>8)&0xFF
              local lum = ar * 0.299 + ag * 0.587 + ab * 0.114
              txt_col = lum > 128 and FUNC.rgba(0,0,0) or FUNC.rgba(255,255,255)
            elseif is_visible then
              txt_col = col
            else
              txt_col = FUNC.rgba(130,130,130,200)
            end
            local act_fsz = is_active and (fsz + FUNC.sz(0.5)) or fsz
            local act_font = is_active and FONT_B or FONT
            ImGui.PushFont(ctx, act_font, act_fsz)
            local _, txt_h = ImGui.CalcTextSize(ctx, text, 0, 0)
            local ty = ly + math.max(0, math.floor((row_h - txt_h) * 0.5))
            ImGui.DrawList_PushClipRect(env_dl, lx, ly, lx + rw, ly + row_h, true)
            if marquee then
              FUNC.draw_marquee(env_dl, act_font, act_fsz, text, txt_col,
                lx + FUNC.sz(4), ty, rw - FUNC.sz(8), txt_h, key..c.id,
                {auto = true, speed = FUNC.sz(28), gap = 6})
            else
              ImGui.DrawList_AddText(env_dl, lx + FUNC.sz(4), ty, txt_col, text)
            end
            ImGui.PopFont(ctx)
            ImGui.DrawList_PopClipRect(env_dl)
            if is_visible then
              ImGui.DrawList_AddRect(env_dl, lx - 1, ly, lx + rw + 1, ly + row_h, col, 3, 0, 1)
            end
            return hov
          end

          -- ALL row: 只有全部envelope都開啟時才亮 -- lit only when every env is on
          local any_vis = c.env_enabled or c.pan_env_enabled
          if not any_vis then
            for _, fe in ipairs(c.fx_envs) do if fe.visible ~= false then any_vis = true; break end end
          end
          local all_vis = c.env_enabled and c.pan_env_enabled
          if all_vis then
            for _, fe in ipairs(c.fx_envs) do if fe.visible == false then all_vis = false; break end end
          end
          env_row("env_all", "ALL", all_vis, false, FUNC.rgba(200,200,200), function()
            local turn_on = not any_vis
            if turn_on then
              if not c.env_enabled then
                c.env_enabled = true
                if not c.env_points or #c.env_points == 0 then FUNC.env_init_points(c) end
              end
              if not c.pan_env_enabled then
                c.pan_env_enabled = true
                if not c.pan_env_points or #c.pan_env_points == 0 then FUNC.pan_env_init_points(c) end
              end
              for _, fe in ipairs(c.fx_envs) do fe.visible = true end
            else
              c.env_enabled = false; c.pan_env_enabled = false
              for _, fe in ipairs(c.fx_envs) do fe.visible = false end
              if env_edit_mode == "fx" then fx_env_edit_idx = nil end
            end
            FUNC.save_cues()
          end, nil, false)

          -- Volume row
          env_row("env_vol", "Volume", c.env_enabled, env_edit_mode == "vol" and c.env_enabled, C.env, function()
            if c.env_enabled and env_edit_mode == "vol" then
              c.env_enabled = false
            else
              if not c.env_enabled then
                c.env_enabled = true
                if not c.env_points or #c.env_points == 0 then FUNC.env_init_points(c) end
              end
              env_edit_mode = "vol"; env_drag.sel = {}; fx_env_edit_idx = nil; FUNC.wf_sel_clear()
            end
            FUNC.save_cues()
          end, nil, false)

          -- Pan row
          env_row("env_pan", "Pan", c.pan_env_enabled, env_edit_mode == "pan" and c.pan_env_enabled, C.pan_env, function()
            if c.pan_env_enabled and env_edit_mode == "pan" then
              c.pan_env_enabled = false
            else
              if not c.pan_env_enabled then
                c.pan_env_enabled = true
                if not c.pan_env_points or #c.pan_env_points == 0 then FUNC.pan_env_init_points(c) end
              end
              env_edit_mode = "pan"; env_drag.sel = {}; fx_env_edit_idx = nil; FUNC.wf_sel_clear()
            end
            FUNC.save_cues()
          end, nil, false)

          -- FX rows：以 track FX 為主軸，每個 track FX 都顯示 header（即使沒 env）
          -- envs grouped by fx_guid; missing ones shown after as ⚠ headers
          local envs_by_guid = {}
          local guid_seen = {}
          for fei = 1, #c.fx_envs do
            local fe = c.fx_envs[fei]
            local g = fe.fx_guid or ""
            envs_by_guid[g] = envs_by_guid[g] or {}
            table.insert(envs_by_guid[g], fei)
          end

          local hdr_btn_area = env_btn_sz_fx * 2 + FUNC.sz(8)
          local hdr_w = lbl_w - hdr_btn_area

          -- 記錄每個 param row 的螢幕矩形（給 marquee 框選用）
          local param_rects = {}  -- {fei -> {x1,y1,x2,y2}}
          -- 列表 marquee 起始 y（畫到底再用 cursor y 當 bottom）
          local list_x1, list_y1 = ImGui.GetCursorScreenPos(ctx)
          local list_x2_w = lbl_w  -- 列表寬度（與 row 對齊）

          local function fxe_sel_count()
            local n = 0
            for _ in pairs(fx_env_sel) do n = n + 1 end
            return n
          end
          local function fxe_sel_under_fx(fx_guid)
            local out = {}
            for fei in pairs(fx_env_sel) do
              local fe = c.fx_envs[fei]
              if fe and fe.fx_guid == fx_guid then table.insert(out, fei) end
            end
            return out
          end

          local function draw_fx_header(key, fx_name, fx_guid, fx_idx, is_missing)
            local fx_short = FUNC.fx_env_short_name(fx_name or "")
            local fx_header = is_missing and ("⚠ "..fx_short) or fx_short
            -- 用 floating window 判斷顯示狀態，避免 chain window 內 FX 點擊無反應
            local floating = (fx_idx ~= nil) and cue_tr and reaper.TrackFX_GetFloatingWindow(cue_tr, fx_idx)
            local is_open = floating ~= nil and floating ~= false
            local hdr_col = is_missing and FUNC.rgba(255,90,90) or FUNC.rgba(200,200,200)
            env_row(key, fx_header, is_open, false, hdr_col,
              function()
                -- Opt+click FX header → 刪除整個 FX（含 confirm）
                if ImGui.IsKeyDown(ctx, ImGui.Mod_Alt()) then
                  if is_missing or not cue_tr or fx_idx == nil then
                    -- missing 或無法定位：直接清掉相關 fx_envs
                    for i = #c.fx_envs, 1, -1 do
                      if c.fx_envs[i].fx_guid == fx_guid then FUNC.fx_env_remove(c, i) end
                    end
                    if fx_env_edit_idx and not c.fx_envs[fx_env_edit_idx] then fx_env_edit_idx = nil end
                    FUNC.save_cues()
                  else
                    popup.fx_del_confirm = { cue_id = c.id, fx_guid = fx_guid, fx_idx = fx_idx, name = fx_name or "" }
                  end
                  return
                end
                if fx_idx and cue_tr then
                  reaper.TrackFX_Show(cue_tr, fx_idx, is_open and 2 or 3)
                  if not is_open then FUNC.fx_window_recenter_if_needed(cue_tr, fx_idx) end
                end
              end,
              nil, true, hdr_w)
            if ImGui.IsItemHovered(ctx) then
              if ImGui.BeginTooltip(ctx) then
                ImGui.Text(ctx, fx_name or "")
                ImGui.TextColored(ctx, FUNC.rgba(160,160,170), "Click to toggle FX window · Opt+click to remove FX")
                ImGui.EndTooltip(ctx)
              end
            end
            ImGui.SameLine(ctx, 0, FUNC.sz(4))
            if env_icon_btn("##"..key.."_add", "+", C.primary, C.primary_h, C.primary_hi, nil, env_btn_sz_fx) then
              FUNC.fx_env_begin_pending(c)
            end
            if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Add envelope (touch an FX param)") end
            ImGui.SameLine(ctx, 0, FUNC.sz(4))
            -- 優先用多選；否則 fallback 到 active env（限定該 FX）
            local sel_under = fxe_sel_under_fx(fx_guid)
            local fallback_active = (env_edit_mode == "fx" and fx_env_edit_idx and c.fx_envs[fx_env_edit_idx]
                                     and c.fx_envs[fx_env_edit_idx].fx_guid == fx_guid) and fx_env_edit_idx or nil
            local can_del_h = (#sel_under > 0) or (fallback_active ~= nil)
            local del_col_h = can_del_h and FUNC.dim_c(C.text) or FUNC.rgba(80, 80, 80)
            if env_icon_btn("##"..key.."_del", "-", C.btn, C.danger, C.danger_h, del_col_h, env_btn_sz_fx) and can_del_h then
              local victims = (#sel_under > 0) and sel_under or { fallback_active }
              if #victims == 1 then
                FUNC.fx_env_remove(c, victims[1])
                if fx_env_edit_idx == victims[1] then fx_env_edit_idx = nil end
                fx_env_sel = {}
                FUNC.save_cues()
              else
                popup.fxe_del_batch = { cue_id = c.id, idxs = victims }
              end
            end
            if ImGui.IsItemHovered(ctx) then
              local tip
              if #sel_under > 1 then tip = ("Remove %d selected envelope(s) of this FX"):format(#sel_under)
              elseif #sel_under == 1 then tip = "Remove selected envelope"
              elseif fallback_active then tip = "Remove active envelope of this FX"
              else tip = "Select envelope(s) under this FX to remove" end
              ImGui.SetTooltip(ctx, tip)
            end
          end

          local function draw_param_row(fei)
            local fe = c.fx_envs[fei]
            if not fe then return end
            local fe_col = fe.color or 0xFFAA33FF
            if (fe_col & 0xFF) == 0 then fe_col = fe_col | 0xFF end
            local display_col = fe._missing and FUNC.rgba(255,90,90) or fe_col
            local full_label  = (fe.fx_name or "") .. " / " .. (fe.param_name or "")
            ImGui.Indent(ctx, FUNC.sz(10))
            local rx1, ry1 = ImGui.GetCursorScreenPos(ctx)
            local param_lbl = fe.param_name or ""
            local is_v = fe.visible ~= false
            local is_sel = fx_env_sel[fei] == true
            local is_a = (env_edit_mode == "fx" and fx_env_edit_idx == fei) or is_sel
            local hov = env_row("env_fx"..fei, param_lbl, is_v, is_a, display_col,
              function()
                local mod_alt = ImGui.IsKeyDown(ctx, ImGui.Mod_Alt())
                local mod_cmd = ImGui.IsKeyDown(ctx, ImGui.Mod_Super()) or ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl())
                local mod_sft = ImGui.IsKeyDown(ctx, ImGui.Mod_Shift())
                if mod_alt then
                  if fe._missing or #c.fx_envs <= 1 then
                    FUNC.fx_env_remove(c, fei)
                    if fx_env_edit_idx == fei then fx_env_edit_idx = nil end
                    fx_env_sel = {}
                    FUNC.save_cues()
                  else
                    popup.fxe_del_confirm = { cue_id = c.id, idx = fei, name = full_label }
                  end
                  return
                end
                if mod_cmd then
                  fx_env_sel[fei] = (not fx_env_sel[fei]) and true or nil
                  return
                end
                if mod_sft and fx_env_edit_idx then
                  local a, b = fx_env_edit_idx, fei
                  if a > b then a, b = b, a end
                  for i = a, b do fx_env_sel[i] = true end
                  return
                end
                -- 單擊：清除多選，恢復原本 toggle
                fx_env_sel = {}
                if is_v and (env_edit_mode == "fx" and fx_env_edit_idx == fei) then
                  fe.visible = false; fx_env_edit_idx = nil
                else
                  fe.visible = true
                  env_edit_mode = "fx"; fx_env_edit_idx = fei; env_drag.sel = {}; FUNC.wf_sel_clear()
                end
                FUNC.save_cues()
              end,
              function() ImGui.OpenPopup(ctx, "fxe_menu"..fei) end,
              true, lbl_w - FUNC.sz(10))
            param_rects[fei] = {rx1, ry1, rx1 + lbl_w - FUNC.sz(10), ry1 + row_h}
            ImGui.Unindent(ctx, FUNC.sz(10))
            if hov then
              if ImGui.BeginTooltip(ctx) then
                ImGui.Text(ctx, full_label)
                if fe._missing then ImGui.TextColored(ctx, FUNC.rgba(255,120,120), "FX missing from track") end
                ImGui.TextColored(ctx, FUNC.rgba(160,160,170), "Opt+click to remove")
                ImGui.EndTooltip(ctx)
              end
            end
            if ImGui.BeginPopup(ctx, "fxe_menu"..fei) then
              local ch_c, new_col = ImGui.ColorPicker4(ctx, "##fxe_col_pick"..fei, fe_col,
                ImGui.ColorEditFlags_NoAlpha() | ImGui.ColorEditFlags_NoInputs() | ImGui.ColorEditFlags_NoLabel())
              if ch_c then fe.color = (new_col | 0xFF); FUNC.save_cues() end
              ImGui.EndPopup(ctx)
            end
          end

          -- 主迭代：track 上每個 FX 都顯示一個 header（即使沒 env）
          if cue_tr then
            local fx_count = reaper.TrackFX_GetCount(cue_tr)
            for fxi = 0, fx_count - 1 do
              local fx_guid = reaper.TrackFX_GetFXGUID(cue_tr, fxi)
              local _, fx_name = reaper.TrackFX_GetFXName(cue_tr, fxi, "")
              guid_seen[fx_guid or ""] = true
              draw_fx_header("env_fx_hdr_"..fxi, fx_name, fx_guid, fxi, false)
              local feis = envs_by_guid[fx_guid or ""]
              if feis then
                for _, fei in ipairs(feis) do draw_param_row(fei) end
              end
            end
          end
          -- 缺失的 fx_envs（fx_guid 不在 track 上）
          for guid, feis in pairs(envs_by_guid) do
            if not guid_seen[guid] then
              local first_fe = c.fx_envs[feis[1]]
              draw_fx_header("env_fx_hdr_miss_"..guid, first_fe.fx_name, guid, nil, true)
              for _, fei in ipairs(feis) do draw_param_row(fei) end
            end
          end

          -- ========== Marquee 框選（list 區）==========
          do
            local list_y_bot = select(2, ImGui.GetCursorScreenPos(ctx))
            local lx1 = list_x1
            local lx2 = list_x1 + list_x2_w + FUNC.sz(10)  -- 含 indent 區
            local ly1, ly2 = list_y1, list_y_bot
            local mx, my = ImGui.GetMousePos(ctx)
            local in_area = (mx >= lx1 and mx <= lx2 and my >= ly1 and my <= ly2)

            -- 開始 marquee：點擊空白區（無 widget hovered 且在 list 範圍內）
            if (not fx_env_list_mq.active)
               and ImGui.IsMouseClicked(ctx, 0)
               and in_area
               and not ImGui.IsAnyItemHovered(ctx)
               and not ImGui.IsAnyItemActive(ctx) then
              fx_env_list_mq.active = true
              fx_env_list_mq.x1, fx_env_list_mq.y1 = mx, my
              fx_env_list_mq.x2, fx_env_list_mq.y2 = mx, my
              local mod_cmd = ImGui.IsKeyDown(ctx, ImGui.Mod_Super()) or ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl())
              local mod_sft = ImGui.IsKeyDown(ctx, ImGui.Mod_Shift())
              fx_env_list_mq.add = mod_cmd or mod_sft
              if not fx_env_list_mq.add then fx_env_sel = {} end
              fx_env_list_mq.snap = {}
              for k, v in pairs(fx_env_sel) do fx_env_list_mq.snap[k] = v end
            end

            if fx_env_list_mq.active then
              fx_env_list_mq.x2, fx_env_list_mq.y2 = mx, my
              local rx1 = math.min(fx_env_list_mq.x1, fx_env_list_mq.x2)
              local ry1 = math.min(fx_env_list_mq.y1, fx_env_list_mq.y2)
              local rx2 = math.max(fx_env_list_mq.x1, fx_env_list_mq.x2)
              local ry2 = math.max(fx_env_list_mq.y1, fx_env_list_mq.y2)
              -- 重算選取（基於 snap 起始狀態）
              fx_env_sel = {}
              for k, v in pairs(fx_env_list_mq.snap) do fx_env_sel[k] = v end
              for fei, r in pairs(param_rects) do
                local hit = not (r[3] < rx1 or r[1] > rx2 or r[4] < ry1 or r[2] > ry2)
                if hit then fx_env_sel[fei] = true end
              end
              -- 畫 marquee 矩形
              local fdl = ImGui.GetForegroundDrawList(ctx)
              ImGui.DrawList_AddRectFilled(fdl, rx1, ry1, rx2, ry2, FUNC.rgba(120, 180, 255, 40))
              ImGui.DrawList_AddRect(fdl, rx1, ry1, rx2, ry2, FUNC.rgba(120, 180, 255, 220), 0, 0, 1)
              if ImGui.IsMouseReleased(ctx, 0) then
                fx_env_list_mq.active = false
                fx_env_list_mq.snap = nil
              end
            end
          end

          -- Bottom pending text only (no +/- buttons — moved to per-FX header)
          -- pending 時底部顯示 "Touch an FX Param..." 提示，點擊取消
          if is_pending then
            ImGui.Indent(ctx, FUNC.sz(10))
            local pw = lbl_w - FUNC.sz(10)
            local lx, ly = ImGui.GetCursorScreenPos(ctx)
            ImGui.InvisibleButton(ctx, "##fxe_pending_row_b", pw, row_h)
            if ImGui.IsItemClicked(ctx, 0) then FUNC.fx_env_cancel_pending() end
            local blink = math.sin(ImGui.GetTime(ctx) * 4) * 0.5 + 0.5
            local blink_a = math.floor(100 + 155 * blink)
            local pending_col = FUNC.rgba(255, 200, 80, blink_a)
            ImGui.DrawList_AddRect(env_dl, lx - 1, ly, lx + pw + 1, ly + row_h, pending_col, 3, 0, 1)
            ImGui.PushFont(ctx, FONT, fsz)
            local ptxt = "Touch an FX Param"
            local _, txt_h = ImGui.CalcTextSize(ctx, ptxt, 0, 0)
            local ty = ly + math.max(0, math.floor((row_h - txt_h) * 0.5))
            ImGui.DrawList_PushClipRect(env_dl, lx, ly, lx + pw, ly + row_h, true)
            FUNC.draw_marquee(env_dl, FONT, fsz, ptxt, C.gold,
              lx + FUNC.sz(4), ty, pw - FUNC.sz(8), txt_h, "fxe_pending_b"..c.id,
              {auto = true, speed = FUNC.sz(28), gap = 6})
            ImGui.PopFont(ctx)
            ImGui.DrawList_PopClipRect(env_dl)
            ImGui.Unindent(ctx, FUNC.sz(10))
          end

          -- pending 時剩餘空白處點擊也取消 -- click empty area cancels pending
          if is_pending then
            local rem_w, rem_h = ImGui.GetContentRegionAvail(ctx)
            if rem_h > 0 and rem_w > 0 then
              ImGui.InvisibleButton(ctx, "##fxe_pending_blank", math.max(1, rem_w), math.max(1, rem_h))
              if ImGui.IsItemClicked(ctx, 0) then FUNC.fx_env_cancel_pending() end
            end
          end

          -- Confirm modal: opt+click env remove (when >1 env) -- 移除 env 確認
          if popup.fxe_del_confirm and popup.fxe_del_confirm.cue_id == c.id then
            ImGui.OpenPopup(ctx, "##fxe_del_confirm")
          end
          if ImGui.BeginPopupModal(ctx, "##fxe_del_confirm", nil, ImGui.WindowFlags_AlwaysAutoResize()) then
            local pdc = popup.fxe_del_confirm
            ImGui.Text(ctx, "Remove FX envelope?")
            if pdc and pdc.name then
              ImGui.TextColored(ctx, FUNC.rgba(200,180,120), pdc.name)
            end
            ImGui.Spacing(ctx); ImGui.Separator(ctx); ImGui.Spacing(ctx)
            if ImGui.Button(ctx, "REMOVE", FUNC.sz(80), FUNC.sz(26)) then
              if pdc and c.fx_envs[pdc.idx] then
                FUNC.fx_env_remove(c, pdc.idx)
                if fx_env_edit_idx == pdc.idx then fx_env_edit_idx = nil end
                FUNC.save_cues()
              end
              popup.fxe_del_confirm = nil
              ImGui.CloseCurrentPopup(ctx)
            end
            ImGui.SameLine(ctx)
            if ImGui.Button(ctx, "Cancel", FUNC.sz(80), FUNC.sz(26)) then
              popup.fxe_del_confirm = nil
              ImGui.CloseCurrentPopup(ctx)
            end
            ImGui.EndPopup(ctx)
          end

          -- Confirm modal: 批次刪除多選 fx_envs
          if popup.fxe_del_batch and popup.fxe_del_batch.cue_id == c.id then
            ImGui.OpenPopup(ctx, "##fxe_del_batch")
          end
          if ImGui.BeginPopupModal(ctx, "##fxe_del_batch", nil, ImGui.WindowFlags_AlwaysAutoResize()) then
            local pdb = popup.fxe_del_batch
            local idxs = pdb and pdb.idxs or {}
            ImGui.Text(ctx, ("Remove %d FX envelope(s)?"):format(#idxs))
            for _, fei in ipairs(idxs) do
              local fe = c.fx_envs[fei]
              if fe then
                ImGui.TextColored(ctx, FUNC.rgba(200,180,120),
                  "  • "..(fe.fx_name or "").." / "..(fe.param_name or ""))
              end
            end
            ImGui.Spacing(ctx); ImGui.Separator(ctx); ImGui.Spacing(ctx)
            if ImGui.Button(ctx, "REMOVE", FUNC.sz(80), FUNC.sz(26)) then
              -- 由大到小刪以避免索引位移
              table.sort(idxs, function(a,b) return a > b end)
              for _, fei in ipairs(idxs) do
                if c.fx_envs[fei] then FUNC.fx_env_remove(c, fei) end
              end
              if fx_env_edit_idx and not c.fx_envs[fx_env_edit_idx] then fx_env_edit_idx = nil end
              fx_env_sel = {}
              FUNC.save_cues()
              popup.fxe_del_batch = nil
              ImGui.CloseCurrentPopup(ctx)
            end
            ImGui.SameLine(ctx)
            if ImGui.Button(ctx, "Cancel", FUNC.sz(80), FUNC.sz(26)) then
              popup.fxe_del_batch = nil
              ImGui.CloseCurrentPopup(ctx)
            end
            ImGui.EndPopup(ctx)
          end

          -- Confirm modal: opt+click FX header → 移除整個 track FX
          if popup.fx_del_confirm and popup.fx_del_confirm.cue_id == c.id then
            ImGui.OpenPopup(ctx, "##fx_del_confirm")
          end
          if ImGui.BeginPopupModal(ctx, "##fx_del_confirm", nil, ImGui.WindowFlags_AlwaysAutoResize()) then
            local pfc = popup.fx_del_confirm
            ImGui.Text(ctx, "Remove FX from track?")
            if pfc and pfc.name and pfc.name ~= "" then
              ImGui.TextColored(ctx, FUNC.rgba(200,180,120), pfc.name)
            end
            ImGui.TextColored(ctx, FUNC.rgba(180,180,180), "All envelopes under this FX will also be removed.")
            ImGui.Spacing(ctx); ImGui.Separator(ctx); ImGui.Spacing(ctx)
            if ImGui.Button(ctx, "REMOVE", FUNC.sz(80), FUNC.sz(26)) then
              if pfc and cue_tr and pfc.fx_idx and pfc.fx_idx < reaper.TrackFX_GetCount(cue_tr) then
                -- 確認 guid 一致再刪（避免 fx_idx 已位移）
                if reaper.TrackFX_GetFXGUID(cue_tr, pfc.fx_idx) == pfc.fx_guid then
                  reaper.TrackFX_Delete(cue_tr, pfc.fx_idx)
                else
                  for i = 0, reaper.TrackFX_GetCount(cue_tr) - 1 do
                    if reaper.TrackFX_GetFXGUID(cue_tr, i) == pfc.fx_guid then
                      reaper.TrackFX_Delete(cue_tr, i); break
                    end
                  end
                end
                for i = #c.fx_envs, 1, -1 do
                  if c.fx_envs[i].fx_guid == pfc.fx_guid then FUNC.fx_env_remove(c, i) end
                end
                if fx_env_edit_idx and not c.fx_envs[fx_env_edit_idx] then fx_env_edit_idx = nil end
                FUNC.save_cues()
              end
              popup.fx_del_confirm = nil
              ImGui.CloseCurrentPopup(ctx)
            end
            ImGui.SameLine(ctx)
            if ImGui.Button(ctx, "Cancel", FUNC.sz(80), FUNC.sz(26)) then
              popup.fx_del_confirm = nil
              ImGui.CloseCurrentPopup(ctx)
            end
            ImGui.EndPopup(ctx)
          end

          ImGui.Unindent(ctx, env_indent)
        end

        -- Fade chart tab bar（FADE cues, in waveform tab left column）-- vertical tab switcher
        if all_fade and not multi then
          -- 用共享的fade_from值（含chained fade解析）-- use shared fade_from values
          local fhas_vol = c.fade_vol_enabled and math.abs(c.volume - fade_from_vol) >= 0.01
          local fhas_pan = c.fade_pan_enabled and math.abs((c.fade_pan or 0) - fade_from_pan) >= 0.001
          local fhas_pitch = c.fade_pitch_enabled and math.abs((c.fade_pitch or 0) - fade_from_pitch) >= 0.01
          local ftab_count = (fhas_vol and 1 or 0) + (fhas_pan and 1 or 0) + (fhas_pitch and 1 or 0)
          -- 只有2+參數才顯示tab bar -- only show tabs when 2+ params have fade
          if ftab_count >= 2 then
            ImGui.Dummy(ctx, 0, FUNC.sz(2)); ImGui.Separator(ctx); ImGui.Dummy(ctx, 0, FUNC.sz(2))
            local ftabs = {{"all", "All", C.text}}
            if fhas_vol then ftabs[#ftabs+1] = {"vol", "Volume", C.f_vol} end
            if fhas_pan then ftabs[#ftabs+1] = {"pan", "Pan", C.f_pan} end
            if fhas_pitch then ftabs[#ftabs+1] = {"pitch", "Pitch", C.f_pitch} end
            -- 自動修正無效tab -- auto-correct invalid tab selection
            local tab_valid = false
            for _, ft in ipairs(ftabs) do if ft[1] == popup.fade_chart_tab then tab_valid = true; break end end
            if not tab_valid then popup.fade_chart_tab = "all" end
            local ftab_h = FUNC.sz(20)
            for fi, ft in ipairs(ftabs) do
              local is_active = popup.fade_chart_tab == ft[1]
              if is_active then
                ImGui.PushStyleColor(ctx, ImGui.Col_Button(), ft[3])
                ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), ft[3])
                ImGui.PushStyleColor(ctx, ImGui.Col_Text(), FUNC.rgba(0,0,0))
              else
                ImGui.PushStyleColor(ctx, ImGui.Col_Button(), C.field)
                ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), C.btn)
                ImGui.PushStyleColor(ctx, ImGui.Col_Text(), ft[3])
              end
              if fi > 1 then ImGui.SameLine(ctx, 0, FUNC.sz(ELEM_SPC)) end  -- tab間距=ELEM_SPC -- tab spacing
              if ImGui.Button(ctx, ft[2].."##fctab", 0, ftab_h) then popup.fade_chart_tab = ft[1] end
              ImGui.PopStyleColor(ctx, 3)
            end
          else
            -- 1個或0個參數→自動選all，不顯示tab -- single param, force all tab
            popup.fade_chart_tab = "all"
          end
        end

        -- Curve section（FADE cues, in waveform tab left column）-- fade curve controls
        if all_fade then
          ImGui.Dummy(ctx, 0, FUNC.sz(2)); ImGui.Separator(ctx); ImGui.Dummy(ctx, 0, FUNC.sz(2))
          ImGui.Text(ctx, "Curve")
          -- 每個curve type一行，選中的高亮 -- one button per line, highlight active
          for _, cv in ipairs(CURVES) do
            local is_cur = c.fade_curve == cv
            if is_cur then
              ImGui.PushStyleColor(ctx, ImGui.Col_Button(), C.accent)
              ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), C.accent)
            end
            if ImGui.Button(ctx, CURVE_N[cv].."##ecv", -1, FUNC.sz(20)) then  -- -1=填滿寬度 -- -1=full width
              apply("fade_curve", cv)
              local r = CURVE_AMT[cv]
              if r then
                for _, si in ipairs(valid) do
                  local sc = cues[si]
                  if sc.fade_curve_amt < r.lo or sc.fade_curve_amt > r.hi then sc.fade_curve_amt = r.def end
                end
              end
            end
            if is_cur then ImGui.PopStyleColor(ctx, 2) end
          end
          -- steepness：所有可調曲線（scurve / bezier / power / expo）-- adjustable curves
          local r = CURVE_AMT[c.fade_curve]
          if r then
            ImGui.Dummy(ctx, 0, FUNC.sz(2))
            ImGui.SetNextItemWidth(ctx, -1)  -- 填滿整列 -- fill entire row
            -- 凹=負/凸=正 直覺顯示：fade-down 時 expo 顯示反號 -- invert sign on fade-down so concave=negative
            local _, etc2 = FUNC.get_target(c)
            local efade_in = c.volume > ((etc2 and etc2.volume) or 0)
            local eflip = (c.fade_curve == "expo") and (not efade_in)
            local edisp = eflip and -c.fade_curve_amt or c.fade_curve_amt
            local ach, anv = vdrag("ecv_amt", edisp, r.spd, r.lo, r.hi, "%.2f")
            if ach then apply("fade_curve_amt", eflip and -anv or anv) end
          end
          -- All tab圖例：steepness下方右半邊，垂直排列 -- legend below steepness, right half, vertical
          if popup.fade_chart_tab == "all" then
            local _, ftc2 = FUNC.get_target(c)
            local leg = {}
            if ftc2 then
              if math.abs(c.volume - (ftc2.volume or 0)) >= 0.01 then leg[#leg+1] = {"Vol", C.f_vol} end
              if math.abs((c.fade_pan or 0) - (ftc2.pan or 0)) >= 0.001 then leg[#leg+1] = {"Pan", C.f_pan} end
              if math.abs((c.fade_pitch or 0) - (ftc2.pitch or 0)) >= 0.01 then leg[#leg+1] = {"Pitch", C.f_pitch} end
            end
            if #leg > 0 then
              ImGui.Dummy(ctx, 0, FUNC.sz(ELEM_SPC))
              local ldl = ImGui.GetWindowDrawList(ctx)
              local line_len = FUNC.sz(10)
              local line_gap = FUNC.sz(3)
              -- 用最長label(Pitch)回推起始x，所有行對齊 -- align all lines by longest label
              local max_tw = 0
              for _, lp in ipairs(leg) do
                local tw = ImGui.CalcTextSize(ctx, lp[1], 0, 0)
                if tw > max_tw then max_tw = tw end
              end
              local total_item_w = line_len + line_gap + max_tw  -- 色線+間距+文字 -- line+gap+text
              local avail_w = ImGui.GetContentRegionAvail(ctx)
              local start_x = avail_w - total_item_w  -- 置右：從右邊回推 -- right-align: push from right edge
              for _, lp in ipairs(leg) do
                ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + start_x)
                ImGui.Dummy(ctx, total_item_w, FUNC.sz(14))
                local dx1, dy1 = ImGui.GetItemRectMin(ctx)
                local lcy = dy1 + FUNC.sz(7)
                ImGui.DrawList_AddLine(ldl, dx1, lcy, dx1 + line_len, lcy, lp[2], FUNC.sz(2))
                ImGui.DrawList_AddText(ldl, dx1 + line_len + line_gap, dy1 + FUNC.sz(1), lp[2], lp[1])
              end
            end
          end
        end

        -- 空白處點擊：清除envelope focus但保留enable -- click blank area: clear env focus, keep enabled
        local rem_w, rem_h = ImGui.GetContentRegionAvail(ctx)
        if rem_h > 0 then
          ImGui.InvisibleButton(ctx, "##wf_left_blank", math.max(1, rem_w), rem_h)
          if ImGui.IsItemClicked(ctx) then
            env_edit_mode = nil; fx_env_edit_idx = nil; env_drag.sel = {}
            FUNC.clear_inner_sels()
          end
        end

        ImGui.PopFont(ctx)
        ImGui.EndChild(ctx)
      end
      ImGui.PopStyleVar(ctx)  -- WindowPadding for wf_left

      -- ─── 圖表區：Waveform / Fade curve ─── -- chart: waveform or fade display
      if has_display and right_w > FUNC.sz(100) then
        ImGui.SameLine(ctx, 0, 0)  -- scrollbar貼邊，圖表緊接scrollbar -- chart starts right after scrollbar
        if ImGui.BeginChild(ctx, "##wf_right", right_w, tab_h, ImGui.ChildFlags_None(), ImGui.WindowFlags_NoScrollWithMouse() | ImGui.WindowFlags_NoScrollbar()) then
          if not multi and all_play then
            local wf_w = ImGui.GetContentRegionAvail(ctx) - epad  -- 右側留epad給scrollbar -- right epad margin for scrollbar
            local _, wf_avail_h = ImGui.GetContentRegionAvail(ctx)
            local wf_h = math.max(FUNC.sz(80), wf_avail_h)
            local wf_x, wf_y = ImGui.GetCursorScreenPos(ctx)
            local wf_dl = ImGui.GetWindowDrawList(ctx)
            local wf_info = FUNC.draw_waveform_display(c, wf_dl, wf_x, wf_y, wf_w, wf_h)
            ImGui.InvisibleButton(ctx, "##wf_area", wf_w, wf_h)
            if wf_info then
              if c.pan_env_enabled and env_edit_mode ~= "pan" then FUNC.env_draw(c, wf_dl, wf_info, "pan") end
              if c.env_enabled and env_edit_mode ~= "vol" then FUNC.env_draw(c, wf_dl, wf_info, "vol") end
              if c.pan_env_enabled and env_edit_mode == "pan" then FUNC.env_draw(c, wf_dl, wf_info, "pan") end
              if c.env_enabled and env_edit_mode == "vol" then FUNC.env_draw(c, wf_dl, wf_info, "vol") end
              FUNC.fx_env_draw_all(c, wf_dl, wf_info)
              -- waveform外框：固定灰色（env active不再加彩色外框）-- waveform border: always default grey
              ImGui.DrawList_AddRect(wf_dl, wf_info.cx, wf_info.wy, wf_info.cx + wf_info.cw, wf_info.wy + wf_info.wh, FUNC.dim_c(C.line2), 4, 0, 1)
            end
          elseif not multi and all_fade then
            local fc_w_full = ImGui.GetContentRegionAvail(ctx) - epad  -- 右側留epad給scrollbar -- right epad margin for scrollbar
            local _, fc_avail_h = ImGui.GetContentRegionAvail(ctx)
            local fc_sx, fc_sy = ImGui.GetCursorScreenPos(ctx)
            local fc_dl = ImGui.GetWindowDrawList(ctx)
            -- 直接用edit panel已計算的fade_from值（含chained fade解析）
            -- reuse fade_from values from edit panel (includes chained fade resolution)
            local from_vol = fade_from_vol
            local to_vol = c.volume
            local from_pan, to_pan = -fade_from_pan, -(c.fade_pan or 0)  -- 取反讓L在上R在下 -- negate so L=top R=bottom
            local from_pitch, to_pitch = fade_from_pitch, c.fade_pitch or 0
            -- 判斷哪些參數有漸變（enabled且值不同）-- which params have fade (enabled + different value)
            local fhas_vol = c.fade_vol_enabled and math.abs(from_vol - to_vol) >= 0.01
            local fhas_pan = c.fade_pan_enabled and math.abs(to_pan - from_pan) >= 0.001
            local fhas_pitch = c.fade_pitch_enabled and math.abs(to_pitch - from_pitch) >= 0.01
            local has_any_fade = fhas_vol or fhas_pan or fhas_pitch
            -- pan格式：100L/C/100R -- pan format: L on top, R on bottom
            local fmt_pan_fn = function(v)
              local av = math.abs(v)
              if av < 0.005 then return "C" end
              return string.format("%.0f%s", av * 100, v > 0 and "L" or "R")
            end
            local fmt_pit_fn = function(v) return string.format("%+.1fst", v) end
            -- 計算label margin：用最寬可能值固定寬度，避免圖表抖動 -- label margin: fixed width using widest possible value to prevent chart jitter
            local lbl_m = FUNC.sz(EDGE_PAD)
            if has_any_fade then
              if fhas_vol then
                lbl_m = math.max(lbl_m, ImGui.CalcTextSize(ctx, string.format("%.1f dB", prefs.vol_min)) + FUNC.sz(3))  -- 最寬vol格式 -- widest vol format
              end
              if fhas_pan then
                lbl_m = math.max(lbl_m, ImGui.CalcTextSize(ctx, "100R") + FUNC.sz(3))  -- 最寬pan格式 -- widest pan format
              end
              if fhas_pitch then
                lbl_m = math.max(lbl_m, ImGui.CalcTextSize(ctx, "-24.0st") + FUNC.sz(3))  -- 最寬pitch格式 -- widest pitch format
              end
            end
            local vpad = FUNC.sz(EDGE_PAD)
            local pbar_h = FUNC.sz(4)
            local ruler_h = FUNC.sz(12)
            local rc_x = fc_sx + lbl_m; local rc_w = fc_w_full - lbl_m * 2
            local rc_y = fc_sy + vpad; local rc_h = math.max(FUNC.sz(60), fc_avail_h - vpad * 2 - pbar_h - ruler_h)
            -- 背景+邊框（同waveform）-- bg + border matching waveform style
            ImGui.DrawList_AddRectFilled(fc_dl, rc_x, rc_y, rc_x + rc_w, rc_y + rc_h, C.wf_bg, 4)
            ImGui.DrawList_AddRect(fc_dl, rc_x, rc_y, rc_x + rc_w, rc_y + rc_h, FUNC.dim_c(C.line2), 4, 0, 1)
            local hover_params = {} -- 提到外層供播放圓點共用 -- outer scope for playback dot
            -- 防重疊工具：收集{y,h}後由上到下推開 -- anti-overlap: push labels apart top-to-bottom
            local function resolve_overlaps(items, y_min, y_max)
              table.sort(items, function(a,b) return a.y < b.y end)
              for i = 2, #items do
                local prev = items[i-1]
                local gap = items[i].y - (prev.y + prev.h)
                if gap < 0 then items[i].y = prev.y + prev.h end
              end
              for i = #items, 1, -1 do
                if items[i].y + items[i].h > y_max then items[i].y = y_max - items[i].h end
                if i < #items then
                  local nxt = items[i+1]
                  if items[i].y + items[i].h > nxt.y then items[i].y = nxt.y - items[i].h end
                end
              end
              for i = 1, #items do
                if items[i].y < y_min then items[i].y = y_min end
                if i > 1 then
                  local prev = items[i-1]
                  if items[i].y < prev.y + prev.h then items[i].y = prev.y + prev.h end
                end
              end
            end
            -- 共用：計算點+收集文字，由上到下逐一放置 -- shared: dots + labels, place top-to-bottom
            local function draw_dots_with_labels(dl, px, ca_x, ca_y, ca_w, ca_h, cv_val, params)
              local dot_items = {}
              for _, hp in ipairs(params) do
                local hf, ht, hfmt, hcol = hp[1], hp[2], hp[3], hp[4]
                local hmin = hp[5] or math.min(hf, ht)
                local hmax = hp[6] or math.max(hf, ht)
                local hrng = hmax - hmin; if hrng == 0 then hrng = 1 end
                local cur = hf + (ht - hf) * cv_val
                local dot_y = ca_y + ca_h * (1 - (cur - hmin) / hrng)
                local lbl = hfmt(cur)
                local tw_ = ImGui.CalcTextSize(ctx, lbl, 0, 0)
                local _, th_ = ImGui.CalcTextSize(ctx, lbl, 0, 0)
                dot_items[#dot_items+1] = {dot_y=dot_y, lbl=lbl, tw=tw_, th=th_, col=hcol}
              end
              -- 畫圓點 -- draw dots
              for _, d in ipairs(dot_items) do
                ImGui.DrawList_AddCircleFilled(dl, px, d.dot_y, FUNC.sz(5), d.col)
                ImGui.DrawList_AddCircle(dl, px, d.dot_y, FUNC.sz(5), FUNC.rgba(0,0,0,150), 0, FUNC.sz(1))
              end
              -- 外側邏輯+0.5s cooldown防跳動 -- outside logic + 0.5s flip cooldown
              popup._dot_side = popup._dot_side or {}
              local now = reaper.time_precise()
              local FLIP_CD = 0.5
              table.sort(dot_items, function(a,b) return a.dot_y < b.dot_y end)
              local gap = FUNC.sz(8)
              local placed = {} -- 已放置的文字 {y, h}
              -- 收集所有點的y作為「線段」判定 -- collect dot y positions as "lines"
              local dot_lines = {}
              for _, d in ipairs(dot_items) do dot_lines[#dot_lines+1] = d.dot_y end
              -- 檢查y~y+h是否跟已放置文字或其他線段重疊 -- check overlap with placed labels and other dot lines
              local function hits(y, h, my_dot_y)
                for _, p in ipairs(placed) do
                  if y < p.y + p.h and y + h > p.y then return true end
                end
                for _, dy in ipairs(dot_lines) do
                  if dy ~= my_dot_y and y <= dy and y + h >= dy then return true end
                end
                return false
              end
              for _, d in ipairs(dot_items) do
                local key = d.col
                local st = popup._dot_side[key] or {below = false, flip_t = 0}
                local above_y = d.dot_y - gap - d.th
                local below_y = d.dot_y + gap
                local above_bad = hits(above_y, d.th, d.dot_y)
                local below_bad = hits(below_y, d.th, d.dot_y)
                -- 決定想要的方向 -- decide desired side
                local want_below
                if st.below then
                  -- 目前下方：除非下方疊到且上方沒疊到才翻回 -- stay below unless below bad & above ok
                  want_below = not (below_bad and not above_bad)
                else
                  -- 目前上方：上方疊到且下方沒疊到才翻下 -- stay above unless above bad & below ok
                  want_below = above_bad and not below_bad
                end
                -- 0.5s cooldown -- flip cooldown
                if want_below ~= st.below then
                  if now - st.flip_t >= FLIP_CD then
                    st.below = want_below
                    st.flip_t = now
                  end
                end
                local ly = st.below and below_y or above_y
                ly = FUNC.clamp(ly, ca_y, ca_y + ca_h - d.th)
                popup._dot_side[key] = st
                placed[#placed+1] = {y = ly, h = d.th}
                local lx = px - d.tw / 2
                lx = FUNC.clamp(lx, ca_x, ca_x + ca_w - d.tw)
                ImGui.DrawList_AddText(dl, lx, ly, d.col, d.lbl)
              end
            end
            if not has_any_fade then
              local sv_txt = "No Change, No Fade"
              ImGui.PushFont(ctx, FONT_B, FUNC.sz(26))
              local sv_tw, sv_th = ImGui.CalcTextSize(ctx, sv_txt, 0, 0)
              ImGui.DrawList_AddText(fc_dl, fc_sx + (fc_w_full - sv_tw) / 2, fc_sy + (fc_avail_h - sv_th) / 2, FUNC.rgba(220,190,90,255), sv_txt)
              ImGui.PopFont(ctx)
            else
              -- 通用fade chart繪製 -- reusable fade chart drawer
              local function draw_fc(dl, f_from, f_to, fmt_fn, line_col, dir_label, fix_min, fix_max)
                local f_min = fix_min or math.min(f_from, f_to)
                local f_max = fix_max or math.max(f_from, f_to)
                local f_rng = f_max - f_min; if f_rng == 0 then f_rng = 1 end
                local cp = FUNC.sz(6)
                local ca_x, ca_y = rc_x + cp, rc_y + cp
                local ca_w, ca_h = rc_w - cp * 2, rc_h - cp * 2
                if dir_label then
                  local dtw = ImGui.CalcTextSize(ctx, dir_label, 0, 0)
                  ImGui.DrawList_AddText(dl, rc_x + rc_w - dtw - FUNC.sz(4), rc_y + FUNC.sz(2), FUNC.rgba(100,100,120), dir_label)
                end
                local steps = 80
                for si = 0, steps-1 do
                  local t0 = si / steps; local t1 = (si+1) / steps
                  local cv0 = FUNC.crv(t0, c.fade_curve, c.fade_curve_amt)
                  local cv1 = FUNC.crv(t1, c.fade_curve, c.fade_curve_amt)
                  local v0 = f_from + (f_to - f_from) * cv0
                  local v1 = f_from + (f_to - f_from) * cv1
                  local y0 = ca_y + ca_h * (1 - (v0 - f_min) / f_rng)
                  local y1 = ca_y + ca_h * (1 - (v1 - f_min) / f_rng)
                  local x0 = ca_x + ca_w * t0; local x1 = ca_x + ca_w * t1
                  ImGui.DrawList_AddLine(dl, x0, y0, x1, y1, line_col, FUNC.sz(2))
                end
                local ep_y0 = ca_y + ca_h * (1 - (f_from - f_min) / f_rng)
                local ep_y1 = ca_y + ca_h * (1 - (f_to - f_min) / f_rng)
                ImGui.DrawList_AddCircleFilled(dl, ca_x, ep_y0, FUNC.sz(4), FUNC.rgba(180,180,200))
                ImGui.DrawList_AddCircleFilled(dl, ca_x+ca_w, ep_y1, FUNC.sz(4), FUNC.rgba(180,180,200))
                return ca_x, ca_y, ca_w, ca_h, f_min, f_rng
              end
              -- 在矩形外畫from/to label（含防重疊）-- draw from/to labels outside rect (anti-overlap)
              local lbl_items_l, lbl_items_r = {}, {} -- 收集左右兩側label -- collect L/R side labels
              local function draw_fc_labels(dl, f_from, f_to, fmt_fn, col, fix_min, fix_max)
                local f_min = fix_min or math.min(f_from, f_to)
                local f_max = fix_max or math.max(f_from, f_to)
                local f_rng = f_max - f_min; if f_rng == 0 then f_rng = 1 end
                local cp = FUNC.sz(6)
                local ca_y = rc_y + cp; local ca_h = rc_h - cp * 2
                local from_txt = fmt_fn(f_from); local to_txt = fmt_fn(f_to)
                local ftw_f = ImGui.CalcTextSize(ctx, from_txt, 0, 0)
                local ftw_t = ImGui.CalcTextSize(ctx, to_txt, 0, 0)
                local _, ft_h = ImGui.CalcTextSize(ctx, from_txt, 0, 0)
                local from_y = ca_y + ca_h * (1 - (f_from - f_min) / f_rng) - ft_h / 2
                local to_y = ca_y + ca_h * (1 - (f_to - f_min) / f_rng) - ft_h / 2
                lbl_items_l[#lbl_items_l+1] = {y=from_y, h=ft_h, x=rc_x - ftw_f - FUNC.sz(3), col=col, txt=from_txt}
                lbl_items_r[#lbl_items_r+1] = {y=to_y, h=ft_h, x=rc_x + rc_w + FUNC.sz(3), col=col, txt=to_txt}
              end
              local function flush_fc_labels(dl)
                local y_min, y_max = rc_y + FUNC.sz(1), rc_y + rc_h - FUNC.sz(1)
                resolve_overlaps(lbl_items_l, y_min, y_max)
                resolve_overlaps(lbl_items_r, y_min, y_max)
                for _, it in ipairs(lbl_items_l) do ImGui.DrawList_AddText(dl, it.x, it.y, it.col, it.txt) end
                for _, it in ipairs(lbl_items_r) do ImGui.DrawList_AddText(dl, it.x, it.y, it.col, it.txt) end
              end

              -- 根據tab繪製對應圖表 -- draw chart based on active tab
              local tab = popup.fade_chart_tab
              local hover_ca_x, hover_ca_y, hover_ca_w, hover_ca_h

              if tab == "vol" or (tab == "all" and fhas_vol and not fhas_pan and not fhas_pitch) then
                local dir = to_vol > from_vol and "FADE IN" or "FADE OUT"
                local cax,cay,caw,cah = draw_fc(fc_dl, from_vol, to_vol, FUNC.fmt_v, C.f_vol, dir, -60, 12)
                draw_fc_labels(fc_dl, from_vol, to_vol, FUNC.fmt_v, C.f_vol, -60, 12)
                hover_ca_x, hover_ca_y, hover_ca_w, hover_ca_h = cax, cay, caw, cah
                hover_params[#hover_params+1] = {from_vol, to_vol, FUNC.fmt_v, C.f_vol, -60, 12}
              elseif tab == "pan" or (tab == "all" and fhas_pan and not fhas_vol and not fhas_pitch) then
                local cax,cay,caw,cah = draw_fc(fc_dl, from_pan, to_pan, fmt_pan_fn, C.f_pan, "PAN", -1, 1)
                draw_fc_labels(fc_dl, from_pan, to_pan, fmt_pan_fn, C.f_pan, -1, 1)
                hover_ca_x, hover_ca_y, hover_ca_w, hover_ca_h = cax, cay, caw, cah
                hover_params[#hover_params+1] = {from_pan, to_pan, fmt_pan_fn, C.f_pan, -1, 1}
              elseif tab == "pitch" or (tab == "all" and fhas_pitch and not fhas_vol and not fhas_pan) then
                local cax,cay,caw,cah = draw_fc(fc_dl, from_pitch, to_pitch, fmt_pit_fn, C.f_pitch, "PITCH", -12, 12)
                draw_fc_labels(fc_dl, from_pitch, to_pitch, fmt_pit_fn, C.f_pitch, -12, 12)
                hover_ca_x, hover_ca_y, hover_ca_w, hover_ca_h = cax, cay, caw, cah
                hover_params[#hover_params+1] = {from_pitch, to_pitch, fmt_pit_fn, C.f_pitch, -12, 12}
              elseif tab == "all" then
                -- all overlay -- 多曲線疊合
                local cp = FUNC.sz(6)
                local ca_x, ca_y = rc_x + cp, rc_y + cp
                local ca_w, ca_h = rc_w - cp * 2, rc_h - cp * 2
                hover_ca_x, hover_ca_y, hover_ca_w, hover_ca_h = ca_x, ca_y, ca_w, ca_h
                local fparams = {}
                if fhas_vol then fparams[#fparams+1] = {from_vol, to_vol, C.f_vol, "Volume", -60, 12, FUNC.fmt_v} end
                if fhas_pan then fparams[#fparams+1] = {from_pan, to_pan, C.f_pan, "Pan", -1, 1, fmt_pan_fn} end
                if fhas_pitch then fparams[#fparams+1] = {from_pitch, to_pitch, C.f_pitch, "Pitch", -12, 12, fmt_pit_fn} end
                local steps = 80
                for _, fp in ipairs(fparams) do
                  local ff, ft, fcol = fp[1], fp[2], fp[3]
                  local fmin = fp[5] or math.min(ff, ft)
                  local fmax = fp[6] or math.max(ff, ft)
                  local frng = fmax - fmin; if frng == 0 then frng = 1 end
                  for si = 0, steps-1 do
                    local t0 = si / steps; local t1 = (si+1) / steps
                    local cv0 = FUNC.crv(t0, c.fade_curve, c.fade_curve_amt)
                    local cv1 = FUNC.crv(t1, c.fade_curve, c.fade_curve_amt)
                    local v0 = ff + (ft - ff) * cv0
                    local v1 = ff + (ft - ff) * cv1
                    local y0 = ca_y + ca_h * (1 - (v0 - fmin) / frng)
                    local y1 = ca_y + ca_h * (1 - (v1 - fmin) / frng)
                    local x0 = ca_x + ca_w * t0; local x1 = ca_x + ca_w * t1
                    ImGui.DrawList_AddLine(fc_dl, x0, y0, x1, y1, fcol, FUNC.sz(2))
                  end
                  local ey0 = ca_y + ca_h * (1 - (ff - fmin) / frng)
                  local ey1 = ca_y + ca_h * (1 - (ft - fmin) / frng)
                  ImGui.DrawList_AddCircleFilled(fc_dl, ca_x, ey0, FUNC.sz(3), fcol)
                  ImGui.DrawList_AddCircleFilled(fc_dl, ca_x+ca_w, ey1, FUNC.sz(3), fcol)
                  draw_fc_labels(fc_dl, ff, ft, fp[7], fcol, fp[5], fp[6])
                  hover_params[#hover_params+1] = {ff, ft, fp[7], fcol, fp[5], fp[6]}
                end
                -- legend已移到左欄tab bar旁 -- legend moved to left column tab bar
              end

              -- flush from/to labels（防重疊）-- flush labels with anti-overlap
              flush_fc_labels(fc_dl)

              -- hover tooltip -- hover
              if hover_ca_x and hover_ca_w then
                local mx, my = ImGui.GetMousePos(ctx)
                if mx >= hover_ca_x and mx <= hover_ca_x + hover_ca_w and my >= hover_ca_y and my <= hover_ca_y + hover_ca_h then
                  local t_frac = (mx - hover_ca_x) / hover_ca_w
                  local cv_h = FUNC.crv(t_frac, c.fade_curve, c.fade_curve_amt)
                  local fdl = ImGui.GetForegroundDrawList(ctx)
                  ImGui.DrawList_AddLine(fdl, mx, hover_ca_y, mx, hover_ca_y + hover_ca_h, FUNC.rgba(255,255,255,40), 1)
                  draw_dots_with_labels(fdl, mx, hover_ca_x, hover_ca_y, hover_ca_w, hover_ca_h, cv_h, hover_params)
                end
              end
            end
            -- animated dot during playback -- 播放中動態圓點
            if c.state == STATE.RUNNING and c.play_t0 > 0 and c.fade_time > 0 and has_any_fade then
              local elapsed = reaper.time_precise() - c.play_t0
              local prog = FUNC.clamp(elapsed / c.fade_time, 0, 1)
              local cv_val = FUNC.crv(prog, c.fade_curve, c.fade_curve_amt)
              local dcp = FUNC.sz(6)
              local ca_x2, ca_y2 = rc_x + dcp, rc_y + dcp
              local ca_w2, ca_h2 = rc_w - dcp * 2, rc_h - dcp * 2
              local dot_x = ca_x2 + ca_w2 * prog
              draw_dots_with_labels(fc_dl, dot_x, ca_x2, ca_y2, ca_w2, ca_h2, cv_val, hover_params)
            end
            -- 進度條（YouTube style）-- progress bar at chart bottom
            if has_any_fade then
              local pb_y = rc_y + rc_h
              local pb_x, pb_w = rc_x, rc_w
              ImGui.DrawList_AddRectFilled(fc_dl, pb_x, pb_y, pb_x + pb_w, pb_y + pbar_h, C.field, 1)
              if c.state == STATE.RUNNING and c.play_t0 > 0 and c.fade_time > 0 then
                local elapsed = reaper.time_precise() - c.play_t0
                local prog = FUNC.clamp(elapsed / c.fade_time, 0, 1)
                local fill_w = pb_w * prog
                ImGui.DrawList_AddRectFilled(fc_dl, pb_x, pb_y, pb_x + fill_w, pb_y + pbar_h, FUNC.rgba(255,255,255), 1)
              end
            end
            -- 底部時間刻度 -- bottom time ruler (8 divisions)
            if has_any_fade and c.fade_time > 0 then
              local tr_y = rc_y + rc_h + pbar_h
              local tr_x, tr_w = rc_x, rc_w
              local fade_dur = c.fade_time
              local n_div = 8
              local interval = fade_dur / n_div
              local tick_col = FUNC.rgba(255, 255, 255) -- 全白不透明 -- fully opaque white
              local sub_col = FUNC.rgba(255, 255, 255, 120) -- 次刻度半透明 -- sub-tick semi
              local text_col = FUNC.rgba(255, 255, 255) -- 全白不透明 -- fully opaque white
              ImGui.PushFont(ctx, FONT, FUNC.sz(11))
              local t = 0
              while t <= fade_dur + 0.001 do
                local px = tr_x + (t / fade_dur) * tr_w
                if px >= tr_x and px <= tr_x + tr_w then
                  ImGui.DrawList_AddLine(fc_dl, px, tr_y, px, tr_y + FUNC.sz(4), tick_col, 1)
                  local label
                  local m = math.floor(t / 60); local s = t - m * 60
                  if interval < 1 and s > 0.01 then
                    local sf = string.format("%04.1f", s)
                    if sf:sub(-1) == "0" then sf = string.format("%02d", math.floor(s + 0.5)) end -- 省略.0
                    label = string.format("%d:%s", m, sf)
                  elseif s > 0.01 then label = string.format("%d:%02d", m, math.floor(s + 0.5))
                  else label = string.format("%d:00", m) end
                  local tw = ImGui.CalcTextSize(ctx, label, 0, 0)
                  local lx = px - tw / 2
                  lx = FUNC.clamp(lx, tr_x, tr_x + tr_w - tw)
                  ImGui.DrawList_AddText(fc_dl, lx, tr_y + FUNC.sz(5), text_col, label)
                end
                local sub_t = t + interval / 2
                if sub_t < fade_dur then
                  local sub_px = tr_x + (sub_t / fade_dur) * tr_w
                  if sub_px >= tr_x and sub_px <= tr_x + tr_w then
                    ImGui.DrawList_AddLine(fc_dl, sub_px, tr_y, sub_px, tr_y + FUNC.sz(2), sub_col, 1)
                  end
                end
                t = t + interval
              end
              ImGui.PopFont(ctx)
            end
            ImGui.Dummy(ctx, fc_w_full, fc_avail_h)
          elseif all_group then
            -- GROUP多Lane波形 -- GROUP multi-lane waveform display
            local gw_w_full = ImGui.GetContentRegionAvail(ctx)  -- 含epad的完整寬度 -- full width incl epad
            local _, gw_avail_h = ImGui.GetContentRegionAvail(ctx)
            -- 計算最低需求高度 -- calculate minimum required height
            local li = FUNC.group_lanes(c)
            local nl = #li.lanes
            local min_lane = FUNC.sz(45)  -- 每 lane 最低 45px (B3 規範) -- min 45px per lane (B3 spec)
            local g_gap = nl > 1 and FUNC.sz(3) or 0
            local g_pad = (FUNC.sz(16) + FUNC.sz(8)) * 2  -- pad_top + pad_bot
            local need_h = nl * min_lane + g_gap * math.max(0, nl - 1) + g_pad
            local use_scroll = need_h > gw_avail_h and nl > 0
            local gw_w = gw_w_full - epad
            -- ruler 與 end handle 共享同一 y 軸（對齊空間足夠時的位置）
            local sticky_total = math.max(FUNC.sz(18), FUNC.sz(16))  -- max(ruler_h, tab_h)
            if use_scroll then
              -- B3：滾動 child 只包 lanes；end handle + ruler 由外部釘底
              -- B3: scroll child holds lanes only; end handle + ruler pinned externally
              local child_h = gw_avail_h - sticky_total
              if ImGui.BeginChild(ctx, "##gw_scroll", gw_w_full, child_h, ImGui.ChildFlags_None(),
                ImGui.WindowFlags_NoScrollbar()) then
                gw_w = ImGui.GetContentRegionAvail(ctx) - epad
                local gw_x, gw_y = ImGui.GetCursorScreenPos(ctx)
                local gw_dl = ImGui.GetWindowDrawList(ctx)
                FUNC.draw_group_waveform(c, gw_dl, gw_x, gw_y, gw_w, need_h, true)  -- skip_ruler=true
                ImGui.InvisibleButton(ctx, "##gw_area", gw_w, need_h)
                ImGui.EndChild(ctx)
              end
              -- 釘底：ruler + end handle 同 y（與非 scroll 模式相同對齊）
              local sx, sy = ImGui.GetCursorScreenPos(ctx)
              local s_dl = ImGui.GetWindowDrawList(ctx)
              FUNC.draw_group_waveform_ruler(c, s_dl, sy)
              FUNC.draw_group_waveform_end_handle(c, s_dl, sy)
              ImGui.Dummy(ctx, gw_w_full, sticky_total)
            else
              local gw_h = math.max(FUNC.sz(80), gw_avail_h)
              local gw_x, gw_y = ImGui.GetCursorScreenPos(ctx)
              local gw_dl = ImGui.GetWindowDrawList(ctx)
              FUNC.draw_group_waveform(c, gw_dl, gw_x, gw_y, gw_w, gw_h)
              ImGui.InvisibleButton(ctx, "##gw_area", gw_w, gw_h)
            end
          end
          ImGui.EndChild(ctx)
        end
      end
        end  -- close MIDI/else branch for Source tab

        -- ═══════════════════════════════════════════════════════
end
