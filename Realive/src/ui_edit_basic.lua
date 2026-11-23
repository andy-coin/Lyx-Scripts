-- ui_edit_basic.lua — Edit panel: Basic tab
-- Name/Volume/Timing/Trim/Pan/Fade/Rate/Pitch/Checkboxes/Hotkey/SPACER styling

-- Snap-step vdrag for small enumerated ranges (e.g. denom 2/4/8/16/32).
-- 累積 dy，每 STEP_PX 才跳一格，避免 vdrag 每幀 snap 回整數導致小拖動失效。
local DEN_STEP_PX = 30  -- px per step (sz scaled at use site)
local _den_acc = {}     -- label -> accumulated dy
local function den_step_vdrag(label, idx_val, lo, hi, fmt, parse_fn, fixed_w)
  local step_px = FUNC.sz(DEN_STEP_PX)
  -- 用 vdrag 處理顯示+雙擊輸入；drag 由我們自己累積 dy（vdrag 的線性 drag 回傳會被捨棄）
  -- vdrag handles render + double-click edit; drag is intercepted via our own px accumulator
  local was_active = ImGui.IsAnyItemActive and ImGui.IsAnyItemActive(ctx) or false
  local ch, nv = FUNC.vdrag(label, idx_val, 0, lo, hi, fmt, parse_fn, fixed_w)
  -- 編輯模式 commit：vdrag 在編輯結束時 ch=true 且 nv 為輸入值。speed 0 但 InputText 機制獨立。
  -- 若非編輯狀態，ch=true 代表是 drag 觸發（speed 0 → nv == idx_val），予以忽略。
  if ch and nv ~= idx_val then _den_acc[label] = 0; return true, nv end
  -- 拖動累積（IsItemActive 對應 vdrag 內部 InvisibleButton）-- accumulate drag on the vdrag button
  if ImGui.IsItemActive(ctx) then
    local _, dy = ImGui.GetMouseDelta(ctx)
    if math.abs(dy) > 0 then
      local acc = (_den_acc[label] or 0) - dy
      local steps = 0
      while acc >= step_px do steps = steps + 1; acc = acc - step_px end
      while acc <= -step_px do steps = steps - 1; acc = acc + step_px end
      _den_acc[label] = acc
      if steps ~= 0 then
        local new_idx = FUNC.clamp(idx_val + steps, lo, hi)
        if new_idx ~= idx_val then return true, new_idx end
      end
    end
  else
    _den_acc[label] = 0
  end
  return false, idx_val
end

function FUNC.draw_edit_section_basic(ectx, cw_s, ch_s)
  local c, apply, multi, valid = ectx.c, ectx.apply, ectx.multi, ectx.valid
  local all_play, all_fade, all_midi = ectx.all_play, ectx.all_fade, ectx.all_midi
  local fade_from_vol, fade_from_pan, fade_from_pitch = ectx.fade_from_vol, ectx.fade_from_pan, ectx.fade_from_pitch
  local EDGE_PAD, ELEM_SPC = ectx.EDGE_PAD, ectx.ELEM_SPC
  local begin_disabled, end_disabled = ectx.begin_disabled, ectx.end_disabled
  local vdrag = ectx.vdrag
        -- SECTION: BASIC — 欄位（不含Notes）
        -- ═══════════════════════════════════════════════════════
        -- ═══════════════════════════════════════════════════════
        local outer_pad = select(1, ImGui.GetStyleVar(ctx, ImGui.StyleVar_WindowPadding()))  -- 外層section的WindowPadding -- outer section's WindowPadding
        local bas_pad = FUNC.sz(EDGE_PAD)
        local spc = FUNC.sz(ELEM_SPC)
        local lpad = math.max(0, bas_pad - outer_pad)  -- 左padding扣掉外層已有的 -- left pad minus outer's contribution
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding(), 0, 0)  -- 0,0讓scrollbar貼邊，左右padding手動控制 -- 0,0 for flush scrollbar, manual padding
        if ImGui.BeginChild(ctx, "##bas_fields", cw_s, ch_s) then
        if lpad > 0 then ImGui.Indent(ctx, lpad) end  -- 左邊padding（扣除外層）-- left padding (minus outer)
        ImGui.PushFont(ctx, FONT, FUNC.sz(13))
        ImGui.Dummy(ctx, 0, FUNC.sz(4))  -- 標題列與第一行元素間距 -- gap between header and first element
        local bas_narrow = cw_s < FUNC.sz(250)  -- 窄模式：4欄→2欄堆疊 -- narrow mode: stack layout
        local val_w = FUNC.sz(80)
        -- ═══ 座標系統 ═══ -- coordinate system
        local rpad = bas_pad  -- 右邊padding（與左邊相同）-- right padding = left padding
        -- x1：取所有左欄label的最大寬度+spc -- x1: max of all left labels + spc
        local icon_sz = FUNC.sz(18)
        local _lw_vol = ImGui.CalcTextSize(ctx, "Volume", 0, 0)
        local _lw_pit = ImGui.CalcTextSize(ctx, "Pitch", 0, 0)
        local _lw_name = ImGui.CalcTextSize(ctx, "Name", 0, 0)
        local _lw_post = icon_sz + spc + ImGui.CalcTextSize(ctx, "Post", 0, 0)  -- timing row最長：icon+spc+"Post" -- timing row widest
        local _lw_fade = icon_sz + spc + ImGui.CalcTextSize(ctx, "Fade", 0, 0)
        local lbl1_w
        if bas_narrow then
          lbl1_w = math.max(_lw_vol, _lw_pit, _lw_name, _lw_post, _lw_fade)  -- 窄版：以最長label為準 -- narrow: use widest label
        else
          lbl1_w = FUNC.sz(52)  -- 寬版：固定寬度 -- wide: fixed width
        end
        -- SameLine(x)從window起始定位，不含Indent，所以x要加lpad -- SameLine(x) ignores Indent, so add lpad
        local x1 = lpad + lbl1_w + spc  -- 左欄input起始 -- left input start
        local x2 = x1 + val_w + spc  -- 右欄label起始 -- right label start
        local _rw1 = ImGui.CalcTextSize(ctx, "Pan", 0, 0)
        local _rw2 = ImGui.CalcTextSize(ctx, "Rate", 0, 0)
        local x3 = x2 + math.max(_rw1, _rw2) + spc  -- 右欄input起始 -- right input start
        local cnt_w = FUNC.sz(40)
        local TAP_PAD_X = FUNC.sz(6)  -- @ tap-tempo button horizontal padding (hover/flash border)
        local x_note = x1 + cnt_w + spc  -- 音符combo起始（窄版第二欄checkbox對齊用）-- note combo x (narrow 2nd col checkbox alignment)
        local dl_bas = ImGui.GetWindowDrawList(ctx)
        -- helper: 垂直置中label文字（對齊FrameHeight）-- vertically centered label
        local function draw_lbl(text)
          local lx, ly = ImGui.GetCursorScreenPos(ctx)
          local fh = ImGui.GetFrameHeight(ctx)
          local tw, th = ImGui.CalcTextSize(ctx, text, 0, 0)
          ImGui.DrawList_AddText(dl_bas, lx, ly + (fh - th) * 0.5, C.text, text)
          ImGui.Dummy(ctx, tw, fh)
        end

        -- Name（輸入框不active時跑馬燈顯示過長名字）-- marquee when not editing
        if multi then begin_disabled() end
        draw_lbl("Name"); ImGui.SameLine(ctx, x1); ImGui.SetNextItemWidth(ctx, -rpad)
        local nch, nnv = ImGui.InputText(ctx, "##ename", c.name)
        -- 用InputText實際rect來定位跑馬燈覆蓋層 -- use actual InputText rect for overlay positioning
        local ename_rx1, ename_ry1 = ImGui.GetItemRectMin(ctx)
        local ename_rx2, ename_ry2 = ImGui.GetItemRectMax(ctx)
        local ename_active = ImGui.IsItemActive(ctx)
        if ename_active then popup.edit_text_active = true end
        if nch and not multi then c.name = nnv end
        -- 非編輯中+名字過長：用跑馬燈覆蓋InputText -- overlay marquee when not editing & name overflows
        if not ename_active and c.name ~= "" then
          local ep_nm_dl = ImGui.GetWindowDrawList(ctx)
          local ename_fsz = FUNC.sz(13)
          ImGui.PushFont(ctx, FONT, ename_fsz)
          local ename_tw, ename_th = ImGui.CalcTextSize(ctx, c.name, 0, 0)
          ImGui.PopFont(ctx)
          local ename_inner_w = (ename_rx2 - ename_rx1) - FUNC.sz(8)  -- InputText內部可用寬度
          if ename_tw > ename_inner_w then
            local ename_pad = FUNC.sz(4)
            -- 覆蓋InputText背景（精確匹配InputText大小）-- cover with exact InputText rect
            ImGui.DrawList_AddRectFilled(ep_nm_dl, ename_rx1 + 1, ename_ry1 + 1,
              ename_rx2 - 1, ename_ry2 - 1, FUNC.rgba(50, 50, 62), 5)
            local ename_text_y = ename_ry1 + math.floor((ename_ry2 - ename_ry1 - ename_th) * 0.5)
            FUNC.draw_marquee(ep_nm_dl, FONT, ename_fsz, c.name, C.text,
              ename_rx1 + ename_pad, ename_text_y, ename_inner_w, ename_th, "ep_name"..valid[1],
              {delay = 0.5, speed = FUNC.sz(40)})
          end
        end
        if multi then end_disabled() end

        -- ═══ Timing section: Fade / Pre / Post（各自獨立time/bpm toggle）═══
        -- icon toggle helper：DrawList畫時鐘或用FONT_NOTE畫音符 -- draw clock icon or note icon
        local note_sym = NOTE_VALUES[NOTE_DEFAULT_IDX].sym  -- 四分音符 -- quarter note symbol
        local note_w = FUNC.sz(bas_narrow and 18 or 24)
        local bpm_w = FUNC.sz(44)
        -- 畫一列timing row的函數 -- draw one timing row
        local function draw_timing_row(uid, label, mode_field, sec_field, bpm_beats_field, bpm_val_field, note_idx_field, sec_speed, sec_min)
          local cur_mode = c[mode_field] or "time"
          local is_bpm = (cur_mode == "bpm")
          -- icon toggle button -- 圖示切換按鈕
          local btn_col = is_bpm and FUNC.rgba(120,90,30) or FUNC.rgba(50,50,62)
          local btn_hov = is_bpm and FUNC.rgba(140,110,40) or FUNC.rgba(65,65,80)
          ImGui.PushStyleColor(ctx, ImGui.Col_Button(), btn_col)
          ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), btn_hov)
          ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), FUNC.rgba(160,120,50))
          -- 統一用invisible button + DrawList畫icon -- unified invisible button + DrawList icon
          local bx, by = ImGui.GetCursorScreenPos(ctx)
          local clicked = ImGui.Button(ctx, "##m_"..uid, icon_sz, icon_sz)
          local bdl = ImGui.GetWindowDrawList(ctx)
          if is_bpm then
            -- DrawList音符：用FONT_NOTE手動定位避免字體padding -- note icon via DrawList to avoid font padding
            ImGui.PushFont(ctx, FONT_NOTE, FUNC.sz(15))
            local tw, th = ImGui.CalcTextSize(ctx, note_sym, 0, 0)
            ImGui.DrawList_AddTextEx(bdl, FONT_NOTE, FUNC.sz(15),
              bx + (icon_sz - tw) / 2, by + (icon_sz - th) / 2 + FUNC.sz(6),
              FUNC.rgba(220,190,80), note_sym)
            ImGui.PopFont(ctx)
          else
            -- DrawList時鐘：圓+兩條指針 -- clock icon: circle + two hands
            local cx, cy = bx + icon_sz/2, by + icon_sz/2
            local r = icon_sz * 0.35
            ImGui.DrawList_AddCircle(bdl, cx, cy, r, FUNC.rgba(180,180,200), 12, 1.2)
            ImGui.DrawList_AddLine(bdl, cx, cy, cx, cy - r*0.7, FUNC.rgba(180,180,200), 1.2)
            ImGui.DrawList_AddLine(bdl, cx, cy, cx + r*0.5, cy, FUNC.rgba(180,180,200), 1.2)
          end
          ImGui.PopStyleColor(ctx, 3)
          if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, is_bpm and "Switch to Time" or "Switch to BPM") end
          if clicked then
            local new_mode = is_bpm and "time" or "bpm"
            for _, si in ipairs(valid) do
              local sc = cues[si]
              if new_mode == "bpm" and sc[mode_field] ~= "bpm" then
                local nv = NOTE_VALUES[sc[note_idx_field] or NOTE_DEFAULT_IDX] or NOTE_VALUES[NOTE_DEFAULT_IDX]
                local raw = sc[sec_field] * (sc[bpm_val_field] or 120) / 60
                local cnt = math.max(sec_min > 0 and 1 or 0, math.floor(raw / nv.val + 0.5))
                sc[bpm_beats_field] = cnt * nv.val
              end
              sc[mode_field] = new_mode
            end; FUNC.save_cues()
          end
          -- icon→label間距spc，input對齊x1 -- icon to label gap=spc, input at x1
          ImGui.SameLine(ctx, 0, spc)
          ImGui.Text(ctx, label)
          ImGui.SameLine(ctx, x1)
          -- value fields
          if is_bpm then
            -- BPM mode: [count] [note▼] @ [BPM]
            local nv = NOTE_VALUES[c[note_idx_field] or NOTE_DEFAULT_IDX] or NOTE_VALUES[NOTE_DEFAULT_IDX]
            local cnt = math.max(0, math.floor((c[bpm_beats_field] or 0) / nv.val + 0.5))
            local bch, bnv = vdrag("e_"..uid.."_cnt", cnt, 0.15, 0, 999, "%.0f", nil, cnt_w)
            if bch then
              local new_beats = math.floor(bnv + 0.5) * nv.val
              apply(bpm_beats_field, new_beats)
              for _, si in ipairs(valid) do cues[si][sec_field] = cues[si][bpm_beats_field] * 60 / cues[si][bpm_val_field] end
            end
            ImGui.SameLine(ctx, 0, spc)  -- count↔note間距 -- count to note gap
            -- 音符Combo：跟icon button同樣手法：先取pos，畫widget，再DrawList疊音符 -- same pattern as icon button
            local note_dyn_w = math.max(note_w, x2 - ImGui.GetCursorPosX(ctx) - spc)  -- 延伸到@前spc -- stretch to spc before @
            ImGui.SetNextItemWidth(ctx, note_dyn_w)
            local combo_x, combo_y = ImGui.GetCursorScreenPos(ctx)
            local parent_dl = ImGui.GetWindowDrawList(ctx)  -- 在BeginCombo前取parent draw list
            local combo_open = ImGui.BeginCombo(ctx, "##"..uid.."_note", "", ImGui.ComboFlags_NoArrowButton())
            -- combo按鈕上畫音符（同icon button手法）-- note on combo button (same as icon button)
            do
              local combo_h = ImGui.GetFrameHeight(ctx)
              ImGui.PushFont(ctx, FONT_NOTE, FUNC.sz(15))
              local nsw, nsh = ImGui.CalcTextSize(ctx, nv.sym, 0, 0)
              ImGui.DrawList_AddTextEx(parent_dl, FONT_NOTE, FUNC.sz(15),
                combo_x + (note_dyn_w - nsw) / 2, combo_y + (combo_h - nsh) / 2 + FUNC.sz(6),
                FUNC.rgba(220,190,80), nv.sym)
              ImGui.PopFont(ctx)
            end
            if combo_open then
              for ni, nvv in ipairs(NOTE_VALUES) do
                local is_sel = (ni == (c[note_idx_field] or NOTE_DEFAULT_IDX))
                -- dropdown項（同icon button手法）-- dropdown item (same pattern)
                local ex, ey = ImGui.GetCursorScreenPos(ctx)
                local row_h = ImGui.GetFrameHeight(ctx)
                ImGui.PushFont(ctx, FONT_NOTE, FUNC.sz(16))
                local sw2, sh2 = ImGui.CalcTextSize(ctx, nvv.sym, 0, 0)
                ImGui.PopFont(ctx)
                ImGui.Dummy(ctx, sw2 + FUNC.sz(4), row_h)
                local ddl = ImGui.GetWindowDrawList(ctx)
                ImGui.DrawList_AddTextEx(ddl, FONT_NOTE, FUNC.sz(16),
                  ex, ey + (row_h - sh2) / 2 + FUNC.sz(6),
                  FUNC.rgba(220,190,80), nvv.sym)
                ImGui.SameLine(ctx)
                if ImGui.Selectable(ctx, nvv.label.."##"..uid.."n"..ni, is_sel) then
                  local old_nv = NOTE_VALUES[c[note_idx_field] or NOTE_DEFAULT_IDX] or NOTE_VALUES[NOTE_DEFAULT_IDX]
                  local old_count = math.max(1, math.floor((c[bpm_beats_field] or 0) / old_nv.val + 0.5))
                  apply(note_idx_field, ni)
                  local new_beats = old_count * nvv.val
                  apply(bpm_beats_field, new_beats)
                  for _, si in ipairs(valid) do cues[si][sec_field] = cues[si][bpm_beats_field] * 60 / cues[si][bpm_val_field] end
                end
              end
              ImGui.EndCombo(ctx)
            end
            -- "@" tap-tempo 按鈕（取代靜態文字）-- @ as tap tempo button
            local at_tw = ImGui.CalcTextSize(ctx, "@", 0, 0)
            local at_btn_w = at_tw + TAP_PAD_X * 2
            if bas_narrow then
              ImGui.SameLine(ctx, 0, spc - TAP_PAD_X)
            else
              local at_cx = math.floor((x2 + x3 - spc) * 0.5 - at_tw * 0.5 - TAP_PAD_X)
              ImGui.SameLine(ctx, at_cx)
            end
            do
              local at_sx, at_sy = ImGui.GetCursorScreenPos(ctx)
              local at_fh = ImGui.GetFrameHeight(ctx)
              local _, at_th = ImGui.CalcTextSize(ctx, "@", 0, 0)
              ImGui.InvisibleButton(ctx, "##tap_"..uid, at_btn_w, at_fh)
              local hov = ImGui.IsItemHovered(ctx)
              local tap_key = "_tap_"..uid
              local flash_key = "_tap_flash_"..uid
              if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left()) then
                local now = reaper.time_precise()
                local taps = c[tap_key] or {}
                if #taps > 0 and (now - taps[#taps]) > 2.0 then taps = {} end
                taps[#taps+1] = now
                while #taps > 4 do table.remove(taps, 1) end
                c[tap_key] = taps
                c[flash_key] = now
                if #taps >= 2 then
                  local total = taps[#taps] - taps[1]
                  local avg = total / (#taps - 1)
                  if avg > 0 then
                    local new_bpm = FUNC.clamp(60 / avg, 20, 999)
                    apply(bpm_val_field, new_bpm)
                    for _, si in ipairs(valid) do cues[si][sec_field] = cues[si][bpm_beats_field] * 60 / cues[si][bpm_val_field] end
                  end
                end
              end
              ImGui.DrawList_AddText(dl_bas, at_sx + TAP_PAD_X, at_sy + (at_fh - at_th) * 0.5, C.text, "@")
              if c[flash_key] then
                local age = reaper.time_precise() - c[flash_key]
                if age < 0.6 then
                  local a = math.floor(255 * (1 - age / 0.6))
                  ImGui.DrawList_AddRect(dl_bas, at_sx, at_sy, at_sx + at_btn_w, at_sy + at_fh, FUNC.rgba(255, 220, 60, a), 3, 0, FUNC.sz(2))
                else
                  c[flash_key] = nil
                end
              end
              if hov then
                ImGui.DrawList_AddRect(dl_bas, at_sx, at_sy, at_sx + at_btn_w, at_sy + at_fh, FUNC.rgba(255, 220, 60, 80), 3, 0, 1)
                ImGui.SetTooltip(ctx, "Tap tempo: click rhythmically to set BPM\n(2s gap restarts; averages last 4 intervals)")
              end
            end
            if bas_narrow then
              ImGui.SameLine(ctx, 0, spc - TAP_PAD_X)
            else
              ImGui.SameLine(ctx, x3)
            end
            local _btw = ImGui.CalcTextSize(ctx, "bpm", 0, 0)
            local _breserve = _btw + FUNC.sz(20)
            local vpch, vpnv = vdrag("e_"..uid.."_bpm", c[bpm_val_field] or 120, 0.4, 20, 999, "%.0f", nil, -(rpad + _breserve))
            if vpch then
              apply(bpm_val_field, math.floor(vpnv + 0.5))
              for _, si in ipairs(valid) do cues[si][sec_field] = cues[si][bpm_beats_field] * 60 / cues[si][bpm_val_field] end
            end
            ImGui.SameLine(ctx, 0, math.floor((_breserve - _btw) * 0.5))
            ImGui.AlignTextToFramePadding(ctx); ImGui.TextDisabled(ctx, "bpm")
          else
            -- Time mode: [seconds vdrag]
            local tch, tnv = vdrag("e_"..uid.."_sec", c[sec_field], sec_speed, sec_min, 999, "%.1f s", nil, -rpad)
            if tch then apply(sec_field, tnv) end
          end
        end
        -- Fade row（FADE cues only）
        if all_fade then
          draw_timing_row("fade", "Fade", "fade_wait_mode", "fade_time", "fade_bpm_beats", "fade_bpm_val", "fade_note_idx", 0.1, 0.1)
        end
        -- Pre-Wait row
        draw_timing_row("pre", "Pre", "pre_wait_mode", "pre_wait", "pre_bpm_beats", "pre_bpm_val", "pre_note_idx", 0.05, 0)
        -- Post-Wait row
        draw_timing_row("post", "Post", "post_wait_mode", "post_wait", "post_bpm_beats", "post_bpm_val", "post_note_idx", 0.05, 0)

        -- ═══ Volume / Pan / Pitch / Rate（SameLine座標系統）═══
        -- STOP/PAUSE不需要Volume/Pan -- STOP/PAUSE skip Vol/Pan
        if all_play or all_fade then
        ImGui.Dummy(ctx, 0, spc/2); ImGui.Separator(ctx); ImGui.Dummy(ctx, 0, spc/2)
        -- volume format function: show -inf dB at threshold -- 到inf_db顯示-inf dB
        local vol_fmt = function(v) return v <= prefs.inf_db and "-inf dB" or string.format("%.1f dB", v) end
        -- fade參數label：值同target時自動消除highlight，不同時自動亮起，可手動bypass
        -- fade param label: auto-off when same as target, auto-on when different, click to bypass
        local function fade_lbl(text, enabled_key, col, from_val)
          local lx, ly = ImGui.GetCursorScreenPos(ctx)
          local fh = ImGui.GetFrameHeight(ctx)
          local tw, th = ImGui.CalcTextSize(ctx, text, 0, 0)
          -- 判斷值是否與target相同 -- check if value matches target
          local cur_val
          if enabled_key == "fade_vol_enabled" then cur_val = c.volume
          elseif enabled_key == "fade_pan_enabled" then cur_val = c.fade_pan or 0
          elseif enabled_key == "fade_pitch_enabled" then cur_val = c.fade_pitch or 0
          end
          local thr = (enabled_key == "fade_pan_enabled") and 0.001 or 0.01
          local same = from_val ~= nil and math.abs(cur_val - from_val) < thr
          -- bypass key：手動toggle off時設定，值變動時清除 -- bypass: set on manual toggle off, cleared on value change
          local bypass_key = "_bypass_"..enabled_key
          -- 值相同→自動clear+清bypass；值不同且無bypass→自動enable -- auto-clear when same; auto-enable when different (unless bypassed)
          if same then
            if c[enabled_key] then
              for _, si in ipairs(valid) do cues[si][enabled_key] = false end; FUNC.save_cues()
            end
            if c[bypass_key] then c[bypass_key] = nil end  -- 值回到相同，清除bypass -- clear bypass when same again
          elseif not c[enabled_key] and not c[bypass_key] then
            for _, si in ipairs(valid) do cues[si][enabled_key] = true end; FUNC.save_cues()
          end
          local enabled = c[enabled_key] and not same
          local text_col = enabled and col or C.text
          ImGui.DrawList_AddText(dl_bas, lx, ly + (fh - th) * 0.5, text_col, text)
          ImGui.InvisibleButton(ctx, "##fl_"..enabled_key, tw, fh)
          -- 點擊toggle：值不同時可開關，toggle off時設bypass防止auto-enable覆蓋
          -- click toggle: on/off when different; toggle off sets bypass to prevent auto-enable override
          if not same and ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left()) then
            local nv = not c[enabled_key]
            for _, si in ipairs(valid) do cues[si][enabled_key] = nv end
            if not nv then c[bypass_key] = true else c[bypass_key] = nil end  -- off→設bypass, on→清bypass
            FUNC.save_cues()
          end
          if enabled then
            ImGui.DrawList_AddRect(dl_bas, lx - 2, ly, lx + tw + 2, ly + fh, col, 3, 0, 1)  -- 細邊框 -- thin border
          end
        end
        local fade_vol_col = C.env or FUNC.rgba(200, 120, 60)
        local fade_pan_col = C.pan_env or FUNC.rgba(100, 200, 100)
        local fade_pitch_col = FUNC.rgba(120, 160, 255)
        if all_fade and not bas_narrow then
          -- ── FADE 寬版：每項獨立一列 ──
          -- Volume + Stop
          fade_lbl("Volume", "fade_vol_enabled", fade_vol_col, fade_from_vol); ImGui.SameLine(ctx, x1)
          local fade_stop_vis = c.volume <= prefs.inf_db
          if fade_stop_vis then
            local vch, vnv = vdrag("evol", c.volume, 0.1, prefs.vol_min, prefs.vol_max, vol_fmt, FUNC.parse_v, val_w)
            if vch then apply("volume", vnv); for _, si in ipairs(valid) do cues[si].fade_vol_enabled = true end end
            ImGui.SameLine(ctx, 0, FUNC.sz(6))
            local not_keep = not c.fade_keep_playing
            local kpch, kpnv = ImGui.Checkbox(ctx, "Stop##fkp", not_keep)
            if kpch then apply("fade_keep_playing", not kpnv) end
            if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Stop target after fade to -inf dB") end
          else
            local vch, vnv = vdrag("evol", c.volume, 0.1, prefs.vol_min, prefs.vol_max, vol_fmt, FUNC.parse_v, -rpad)
            if vch then apply("volume", vnv); for _, si in ipairs(valid) do cues[si].fade_vol_enabled = true end end
          end
          -- Pan
          fade_lbl("Pan", "fade_pan_enabled", fade_pan_col, fade_from_pan); ImGui.SameLine(ctx, x1); ImGui.SetNextItemWidth(ctx, -rpad)
          local pch, pnv = ImGui.SliderDouble(ctx, "##epan", (c.fade_pan or 0) * 100, -100, 100, "%.0f")
          if pch then
            local pval = FUNC.clamp(pnv / 100, -1, 1)
            for _, si in ipairs(valid) do cues[si].fade_pan = pval; cues[si].fade_pan_enabled = true end; FUNC.save_cues()
          end
          if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left()) and FUNC.try_dbl("epan") then
            for _, si in ipairs(valid) do cues[si].fade_pan = 0 end; FUNC.save_cues()
          end
          -- Pitch
          fade_lbl("Pitch", "fade_pitch_enabled", fade_pitch_col, fade_from_pitch); ImGui.SameLine(ctx, x1)
          local fpch2, fpnv2 = vdrag("efp", c.fade_pitch or 0, 0.1, -24, 24, "%.1f st", nil, -rpad)
          if fpch2 then apply("fade_pitch", fpnv2); for _, si in ipairs(valid) do cues[si].fade_pitch_enabled = true end end
        elseif bas_narrow then
          -- ── 窄版（PLAY/FADE）：每項獨立一列 ──
          -- Volume（FADE窄版：vdrag + Stop同列對齊x_note）
          if all_fade then fade_lbl("Volume", "fade_vol_enabled", fade_vol_col, fade_from_vol) else draw_lbl("Volume") end
          ImGui.SameLine(ctx, x1)
          if all_fade then
            local fade_stop_vis = c.volume <= prefs.inf_db
            local vol_w = fade_stop_vis and (x_note - x1 - spc) or -rpad  -- stop可見時vdrag到x_note前，否則延伸到右邊 -- vdrag to x_note when stop visible
            local vch, vnv = vdrag("evol", c.volume, 0.1, prefs.vol_min, prefs.vol_max, vol_fmt, FUNC.parse_v, vol_w)
            if vch then apply("volume", vnv); for _, si in ipairs(valid) do cues[si].fade_vol_enabled = true end end
            if fade_stop_vis then
              ImGui.SameLine(ctx, x_note)
              local not_keep = not c.fade_keep_playing
              local kpch, kpnv = ImGui.Checkbox(ctx, "Stop##fkp", not_keep)
              if kpch then apply("fade_keep_playing", not kpnv) end
              if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Stop target after fade to -inf dB") end
            end
          else
            local vch, vnv = vdrag("evol", c.volume, 0.1, prefs.vol_min, prefs.vol_max, vol_fmt, FUNC.parse_v, -rpad)
            if vch then apply("volume", vnv) end
          end
          -- Pan
          if all_fade then fade_lbl("Pan", "fade_pan_enabled", fade_pan_col, fade_from_pan) else draw_lbl("Pan") end
          ImGui.SameLine(ctx, x1); ImGui.SetNextItemWidth(ctx, -rpad)
          if all_play then
            local pch, pnv = ImGui.SliderDouble(ctx, "##epan", (c.pan or 0) * 100, -100, 100, "%.0f")
            if pch then
              local pval = FUNC.clamp(pnv / 100, -1, 1)
              for _, si in ipairs(valid) do
                cues[si].pan = pval
                if cues[si].preview_ids then
                  for _, pid in ipairs(cues[si].preview_ids) do FUNC.pv_set_pan(pid, pval) end
                end
              end
            end
            if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left()) and FUNC.try_dbl("epan") then
              for _, si in ipairs(valid) do
                cues[si].pan = 0
                if cues[si].preview_ids then
                  for _, pid in ipairs(cues[si].preview_ids) do FUNC.pv_set_pan(pid, 0) end
                end
              end
            end
          else  -- all_fade（STOP/PAUSE已被外層guard排除）
            local pch, pnv = ImGui.SliderDouble(ctx, "##epan", (c.fade_pan or 0) * 100, -100, 100, "%.0f")
            if pch then
              local pval = FUNC.clamp(pnv / 100, -1, 1)
              for _, si in ipairs(valid) do cues[si].fade_pan = pval; cues[si].fade_pan_enabled = true end; FUNC.save_cues()
            end
            if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left()) and FUNC.try_dbl("epan") then
              for _, si in ipairs(valid) do cues[si].fade_pan = 0 end; FUNC.save_cues()
            end
          end
          -- Pitch
          if all_play then
            draw_lbl("Pitch"); ImGui.SameLine(ctx, x1)
            local pitch_ch, pitch_nv = vdrag("epit", c.pitch or 0, 0.1, -24, 24, "%.1f st", nil, -rpad)
            if pitch_ch then apply("pitch", pitch_nv); for _,si in ipairs(valid) do FUNC.pv_update_rate_pitch(cues[si]) end end
            -- Rate
            draw_lbl("Rate"); ImGui.SameLine(ctx, x1)
            local rate_ch, rate_nv = vdrag("erate", c.rate or 1.0, 0.01, 0.1, 4.0, "%.2fx", nil, -rpad)
            if rate_ch then apply("rate", rate_nv); for _,si in ipairs(valid) do FUNC.pv_update_rate_pitch(cues[si]) end end
          elseif all_fade then
            fade_lbl("Pitch", "fade_pitch_enabled", fade_pitch_col, fade_from_pitch); ImGui.SameLine(ctx, x1)
            local fpch2, fpnv2 = vdrag("efp", c.fade_pitch or 0, 0.1, -24, 24, "%.1f st", nil, -rpad)
            if fpch2 then apply("fade_pitch", fpnv2); for _, si in ipairs(valid) do cues[si].fade_pitch_enabled = true end end
          end
        else
          -- ── PLAY 寬版：Volume+Pan同列, Pitch+Rate同列 ──
          -- Volume [x0] vdrag[x1] Pan[x2] slider[x3→right]
          draw_lbl("Volume"); ImGui.SameLine(ctx, x1)
          local vch, vnv = vdrag("evol", c.volume, 0.1, prefs.vol_min, prefs.vol_max, vol_fmt, FUNC.parse_v, val_w)
          if vch then apply("volume", vnv) end
          ImGui.SameLine(ctx, x2); draw_lbl("Pan"); ImGui.SameLine(ctx, x3); ImGui.SetNextItemWidth(ctx, -rpad)
          local pch, pnv = ImGui.SliderDouble(ctx, "##epan", (c.pan or 0) * 100, -100, 100, "%.0f")
          if pch then
            local pval = FUNC.clamp(pnv / 100, -1, 1)
            for _, si in ipairs(valid) do
              cues[si].pan = pval
              if cues[si].preview_ids then
                for _, pid in ipairs(cues[si].preview_ids) do FUNC.pv_set_pan(pid, pval) end
              end
            end
          end
          if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left()) and FUNC.try_dbl("epan") then
            for _, si in ipairs(valid) do
              cues[si].pan = 0
              if cues[si].preview_ids then
                for _, pid in ipairs(cues[si].preview_ids) do FUNC.pv_set_pan(pid, 0) end
              end
            end
          end
          -- Pitch [x0] vdrag[x1] Rate[x2] vdrag[x3→right]
          if all_play then
            draw_lbl("Pitch"); ImGui.SameLine(ctx, x1)
            local pitch_ch, pitch_nv = vdrag("epit", c.pitch or 0, 0.1, -24, 24, "%.1f st", nil, val_w)
            if pitch_ch then apply("pitch", pitch_nv); for _,si in ipairs(valid) do FUNC.pv_update_rate_pitch(cues[si]) end end
            ImGui.SameLine(ctx, x2); draw_lbl("Rate"); ImGui.SameLine(ctx, x3)
            local rate_ch, rate_nv = vdrag("erate", c.rate or 1.0, 0.01, 0.1, 4.0, "%.2fx", nil, -rpad)
            if rate_ch then apply("rate", rate_nv); for _,si in ipairs(valid) do FUNC.pv_update_rate_pitch(cues[si]) end end
          end
        end
        -- Preserve Pitch checkbox (PLAY only)
        if all_play then
          ImGui.PushStyleColor(ctx, ImGui.Col_Text(), C.dim)
          local ppch, ppnv = ImGui.Checkbox(ctx, "Preserve Pitch", c.preserve_pitch)
          if ppch then apply("preserve_pitch", ppnv); for _,si in ipairs(valid) do FUNC.pv_update_rate_pitch(cues[si]) end end
          ImGui.PopStyleColor(ctx, 1)
        end
        end  -- all_play or all_fade guard

        -- ═══ MIDI Controls (Phase 5: Mode/Dest 重整 + 拍號/BPM + Item 跑馬燈) ═══
        if all_midi then
        ImGui.Dummy(ctx, 0, spc/2); ImGui.Separator(ctx); ImGui.Dummy(ctx, 0, spc/2)

        -- Row 1: Mode (Message/Sequence) + Dest (Internal/Dev)
        draw_lbl("Mode"); ImGui.SameLine(ctx, x1)
        ImGui.SetNextItemWidth(ctx, val_w)
        local midi_modes = {"message", "sequence"}
        local midi_mode_labels = {"Message", "Sequence"}
        local cur_mode_idx = (c.midi_mode == "message") and 0 or 1
        if ImGui.BeginCombo(ctx, "##midi_mode", midi_mode_labels[cur_mode_idx + 1]) then
          for mi, ml in ipairs(midi_mode_labels) do
            if ImGui.Selectable(ctx, ml, cur_mode_idx == mi - 1) then
              apply("midi_mode", midi_modes[mi])
            end
          end
          ImGui.EndCombo(ctx)
        end
        ImGui.SameLine(ctx, x2); draw_lbl("Dest"); ImGui.SameLine(ctx, x3)
        local n_dev = reaper.GetNumMIDIOutputs()
        local cur_dev = c.midi_device
        if cur_dev == nil then cur_dev = -1 end
        local dest_label
        if cur_dev < 0 then
          dest_label = "Internal"
        else
          local _, dev_name = reaper.GetMIDIOutputName(cur_dev, "")
          dest_label = (dev_name and dev_name ~= "") and dev_name or ("Device " .. tostring(cur_dev))
        end
        ImGui.SetNextItemWidth(ctx, -rpad)
        if ImGui.BeginCombo(ctx, "##midi_dest", dest_label) then
          if ImGui.Selectable(ctx, "Internal", cur_dev < 0) then apply("midi_device", -1) end
          for di = 0, n_dev - 1 do
            local _, dn = reaper.GetMIDIOutputName(di, "")
            local dl = (dn and dn ~= "") and dn or ("Device " .. tostring(di))
            if ImGui.Selectable(ctx, dl, di == cur_dev) then apply("midi_device", di) end
          end
          ImGui.EndCombo(ctx)
        end

        -- Row 2: Sig (sequence) or Dur (message) + BPM
        local _is_msg = (c.midi_mode == "message")
        local _msg_bpm_mode = _is_msg and ((c.midi_dur_mode or "time") == "bpm")
        if _is_msg then
          -- icon toggle button (照抄 pre/post wait)
          local is_bpm = _msg_bpm_mode
          local btn_col = is_bpm and FUNC.rgba(120,90,30) or FUNC.rgba(50,50,62)
          local btn_hov = is_bpm and FUNC.rgba(140,110,40) or FUNC.rgba(65,65,80)
          ImGui.PushStyleColor(ctx, ImGui.Col_Button(), btn_col)
          ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), btn_hov)
          ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), FUNC.rgba(160,120,50))
          local bx, by = ImGui.GetCursorScreenPos(ctx)
          local clicked = ImGui.Button(ctx, "##m_msgdur", icon_sz, icon_sz)
          if is_bpm then
            local sym = NOTE_VALUES[NOTE_DEFAULT_IDX].sym
            ImGui.PushFont(ctx, FONT_NOTE, FUNC.sz(15))
            local tw, th = ImGui.CalcTextSize(ctx, sym, 0, 0)
            ImGui.DrawList_AddTextEx(dl_bas, FONT_NOTE, FUNC.sz(15),
              bx + (icon_sz - tw) / 2, by + (icon_sz - th) / 2 + FUNC.sz(6),
              FUNC.rgba(220,190,80), sym)
            ImGui.PopFont(ctx)
          else
            local cx_, cy_ = bx + icon_sz/2, by + icon_sz/2
            local r = icon_sz * 0.35
            ImGui.DrawList_AddCircle(dl_bas, cx_, cy_, r, FUNC.rgba(180,180,200), 12, 1.2)
            ImGui.DrawList_AddLine(dl_bas, cx_, cy_, cx_, cy_ - r*0.7, FUNC.rgba(180,180,200), 1.2)
            ImGui.DrawList_AddLine(dl_bas, cx_, cy_, cx_ + r*0.5, cy_, FUNC.rgba(180,180,200), 1.2)
          end
          ImGui.PopStyleColor(ctx, 3)
          if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, is_bpm and "Switch to Time" or "Switch to BPM") end
          if clicked then
            for _, si in ipairs(valid) do cues[si].midi_dur_mode = is_bpm and "time" or "bpm" end
            FUNC.save_cues()
          end
          ImGui.SameLine(ctx, 0, spc)
          ImGui.Text(ctx, "Dur")
          ImGui.SameLine(ctx, x1)
        else
          draw_lbl("Sig"); ImGui.SameLine(ctx, x1)
        end
        local ts_w = math.floor(val_w / 2 - FUNC.sz(6))
        if _is_msg and not _msg_bpm_mode then
          -- Time mode：seconds 全寬
          local sec_ch, sec_nv = vdrag("emidi_msgsec", c.midi_duration or 0, 0.01, 0, 3600, "%.2f s", nil, -rpad)
          if sec_ch then apply("midi_duration", FUNC.clamp(sec_nv, 0, 3600)) end
        else
        if _is_msg then
          local _bpm_now = math.max(1, c.midi_bpm or 120)
          local _dden = c.midi_dur_den or 4
          local _cur_count = math.floor((c.midi_duration or 0) * _bpm_now / 60 * _dden / 4 + 0.5)
          local cn_ch, cn_nv = vdrag("emidi_durcnt", _cur_count, 0.15, 0, 999, "%.0f", nil, ts_w)
          if cn_ch then
            local nc = math.max(0, math.floor(cn_nv + 0.5))
            apply("midi_duration", nc * (4 / _dden) * 60 / _bpm_now)
          end
        else
        local tn_ch, tn_nv = vdrag("emidi_tsn", c.midi_ts_num or 4, 0.15, 1, 32, "%.0f", nil, ts_w)
        if tn_ch then apply("midi_ts_num", FUNC.clamp(math.floor(tn_nv + 0.5), 1, 32)) end
        end
        ImGui.SameLine(ctx, 0, FUNC.sz(2))
        local sl_sx, sl_sy = ImGui.GetCursorScreenPos(ctx)
        local sl_fh = ImGui.GetFrameHeight(ctx)
        local _, sl_th = ImGui.CalcTextSize(ctx, "/", 0, 0)
        ImGui.DrawList_AddText(dl_bas or ImGui.GetWindowDrawList(ctx), sl_sx, sl_sy + (sl_fh - sl_th) * 0.5, C.dim, "/")
        ImGui.Dummy(ctx, ImGui.CalcTextSize(ctx, "/", 0, 0), sl_fh)
        ImGui.SameLine(ctx, 0, FUNC.sz(2))
        -- 分母只允許 2 次方：2/4/8/16/32 -- den snaps to power-of-2
        local dens = {2, 4, 8, 16, 32}
        local cur_den = c.midi_ts_den or 4
        local den_idx = 2  -- default 4
        for i, v in ipairs(dens) do if v == cur_den then den_idx = i end end
        local function den_fmt(v) return tostring(dens[FUNC.clamp(math.floor(v + 0.5), 1, #dens)] or 4) end
        local function den_parse(s)
          local n = tonumber(s); if not n then return nil end
          -- 找最接近的合法分母 -- snap to closest valid denominator
          local best_i, best_d = 1, math.huge
          for i, v in ipairs(dens) do local d = math.abs(v - n); if d < best_d then best_d = d; best_i = i end end
          return best_i
        end
        if _is_msg then
          local _dden_cur = c.midi_dur_den or 4
          local _di = 2; for i, v in ipairs(dens) do if v == _dden_cur then _di = i end end
          local td_ch, td_nv = den_step_vdrag("emidi_durden", _di, 1, #dens, den_fmt, den_parse, ts_w)
          if td_ch then
            local ni = FUNC.clamp(math.floor(td_nv + 0.5), 1, #dens)
            apply("midi_dur_den", dens[ni])  -- 只改顯示單位，midi_duration 不變
          end
        else
        local td_ch, td_nv = den_step_vdrag("emidi_tsd", den_idx, 1, #dens, den_fmt, den_parse, ts_w)
        if td_ch then
          local ni = FUNC.clamp(math.floor(td_nv + 0.5), 1, #dens)
          apply("midi_ts_den", dens[ni])
        end
        end
        -- @ tap-tempo 按鈕 x 對齊 pre/post wait 的 @ 位置
        local _at_tw = ImGui.CalcTextSize(ctx, "@", 0, 0)
        ImGui.SameLine(ctx, math.floor((x2 + x3 - spc) * 0.5 - _at_tw * 0.5 - TAP_PAD_X))
        -- BPM 文字本身為 tap-tempo 按鈕：點擊取最近 4 次間隔平均；2 秒未點重啟序列；點擊時黃框漸暗
        -- BPM label = tap tempo button (avg last 4 intervals; restart after 2s gap; yellow border fades)
        do
          local lx, ly = ImGui.GetCursorScreenPos(ctx)
          local fh = ImGui.GetFrameHeight(ctx)
          local lbl = "@"
          local tw, th = ImGui.CalcTextSize(ctx, lbl, 0, 0)
          -- 文字貼齊 lx 以對齊上一列 Dest 的 D；btn_w = tw 讓 hover 框左右對稱貼齊文字
          -- text aligned at lx (matches Dest D above); btn_w = tw so hover border hugs text symmetrically
          local pad_x = TAP_PAD_X
          local btn_w = tw + pad_x * 2
          ImGui.InvisibleButton(ctx, "##tap_bpm", btn_w, fh)
          local hov = ImGui.IsItemHovered(ctx)
          if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left()) then
            local now = reaper.time_precise()
            local taps = c._tap_bpm or {}
            if #taps > 0 and (now - taps[#taps]) > 2.0 then taps = {} end
            taps[#taps+1] = now
            while #taps > 4 do table.remove(taps, 1) end
            c._tap_bpm = taps
            c._tap_flash_t = now
            if #taps >= 2 then
              local total = taps[#taps] - taps[1]
              local avg = total / (#taps - 1)
              if avg > 0 then
                local new_bpm = FUNC.clamp(60 / avg, 1, 999)
                apply("midi_bpm", new_bpm)
              end
            end
          end
          ImGui.DrawList_AddText(dl_bas, lx + pad_x, ly + (fh - th) * 0.5, C.text, lbl)
          -- 黃框漸暗（0.6 秒 fade）-- yellow border fade (0.6s)
          if c._tap_flash_t then
            local age = reaper.time_precise() - c._tap_flash_t
            if age < 0.6 then
              local a = math.floor(255 * (1 - age / 0.6))
              ImGui.DrawList_AddRect(dl_bas, lx, ly, lx + btn_w, ly + fh, FUNC.rgba(255, 220, 60, a), 3, 0, FUNC.sz(2))
            else
              c._tap_flash_t = nil
            end
          end
          if hov then
            ImGui.DrawList_AddRect(dl_bas, lx, ly, lx + btn_w, ly + fh, FUNC.rgba(255, 220, 60, 80), 3, 0, 1)
            ImGui.SetTooltip(ctx, "Tap tempo: click rhythmically to set BPM\n(2s gap restarts; averages last 4 intervals)")
          end
        end
        ImGui.SameLine(ctx, x3)
        local _bpm_tw = ImGui.CalcTextSize(ctx, "bpm", 0, 0)
        local _bpm_reserve = _bpm_tw + FUNC.sz(20)
        local bpm_ch, bpm_nv = vdrag("emidi_bpm", c.midi_bpm or 120, 0.2, 1, 999, "%.1f", nil, -(rpad + _bpm_reserve))
        if bpm_ch then
          local new_bpm = FUNC.clamp(bpm_nv, 1, 999)
          -- msg+bpm 模式：保持 beat count 不變，rescale midi_duration -- preserve beat count when bpm changes
          if _is_msg and _msg_bpm_mode then
            local old_bpm = math.max(1, c.midi_bpm or 120)
            local _dden = c.midi_dur_den or 4
            local cur_count = math.floor((c.midi_duration or 0) * old_bpm / 60 * _dden / 4 + 0.5)
            apply("midi_bpm", new_bpm)
            apply("midi_duration", cur_count * (4 / _dden) * 60 / new_bpm)
          else
            apply("midi_bpm", new_bpm)
          end
        end
        ImGui.SameLine(ctx, 0, math.floor((_bpm_reserve - _bpm_tw) * 0.5))
        ImGui.AlignTextToFramePadding(ctx); ImGui.TextDisabled(ctx, "bpm")
        end  -- end if message+time / else (sequence or message+bpm)

        if c.midi_mode ~= "message" then
        -- Row 3: Vel%
        draw_lbl("Vel"); ImGui.SameLine(ctx, x1)
        local vp_ch, vp_nv = vdrag("emidi_velpct", c.midi_vel_pct or 100, 1, 0, 400, "%.0f%%", nil, val_w)
        if vp_ch then apply("midi_vel_pct", FUNC.clamp(vp_nv, 0, 400)) end

        -- Row 4: MIDI Item picker (name only, marquee) + [✎][+]
        draw_lbl("Item"); ImGui.SameLine(ctx, x1)
        local midi_tr = nil
        if c.track_guid and c.track_guid ~= "" then
          local tidx = FUNC.guid_to_idx(c.track_guid)
          if tidx >= 0 then midi_tr = reaper.GetTrack(0, tidx) end
        end
        -- 每幀 refresh prefix 確保 cue_number 變動同步到 take name
        if c.midi_item_guid and c.midi_item_guid ~= "" then
          FUNC.midi_refresh_prefix_for_guid(c.midi_item_guid)
        end
        -- 目前 item 名稱（不顯示 notes/CC 摘要）-- current item display name (no event count)
        local cur_item, cur_take = FUNC.midi_get_item_take(c)
        local item_name = "(no item)"
        if cur_item then
          if cur_take then
            local _, tk_nm = reaper.GetSetMediaItemTakeInfo_String(cur_take, "P_NAME", "", false)
            item_name = (tk_nm and tk_nm ~= "") and tk_nm or "Item"
          else
            item_name = "(not MIDI)"
          end
        end
        local btn_w = FUNC.sz(28)
        local btn_gap = FUNC.sz(4)
        local rn_w = FUNC.sz(28)  -- rename button width
        local combo_w = ImGui.GetContentRegionAvail(ctx) - rpad - (btn_w * 2 + rn_w + btn_gap * 3)
        -- Combo 顯示名稱（長名 ImGui 自動截，用 preview 屬性；combo 展開的 item 用跑馬燈）
        -- Display name in combo (long name auto-clipped by ImGui), items inside use marquee
        ImGui.SetNextItemWidth(ctx, combo_w)
        if ImGui.BeginCombo(ctx, "##midi_item", item_name) then
          if midi_tr then
            local items = FUNC.midi_list_items(midi_tr)
            local mq_dl = ImGui.GetWindowDrawList(ctx)
            for ii, it in ipairs(items) do
              local lbl = (it.name ~= "") and it.name or "Item"
              local selected = (it.guid == c.midi_item_guid)
              local sx, sy = ImGui.GetCursorScreenPos(ctx)
              local cw_av = ImGui.GetContentRegionAvail(ctx)
              if ImGui.Selectable(ctx, "##mi_"..ii, selected) then
                for _, si in ipairs(valid) do FUNC.midi_assign_unique_guid(cues[si], it.guid) end
              end
              local rh = select(2, ImGui.GetItemRectSize(ctx))
              FUNC.draw_marquee(mq_dl, FONT, FUNC.sz(13), lbl, C.text,
                sx, sy, cw_av, rh, "mi_mq"..c.id.."_"..ii,
                {speed = FUNC.sz(80), delay = 0.3, gap = 16})
            end
            ImGui.Separator(ctx)
          end
          if ImGui.Selectable(ctx, "+ New Empty Item") then
            if midi_tr then
              local new_guid = FUNC.midi_create_blank_item(midi_tr, 2.0)
              if new_guid ~= "" then
                for _, si in ipairs(valid) do FUNC.midi_assign_unique_guid(cues[si], new_guid) end
              end
            end
          end
          ImGui.EndCombo(ctx)
        end
        -- [Rename] open popup to edit base name
        ImGui.SameLine(ctx, nil, btn_gap)
        local rn_disabled = (cur_take == nil)
        if rn_disabled then ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha(), 0.4) end
        if ImGui.Button(ctx, "Re##midi_rn", rn_w, 0) and not rn_disabled then
          local _, cur_nm = reaper.GetSetMediaItemTakeInfo_String(cur_take, "P_NAME", "", false)
          c._rn_buf = FUNC.midi_strip_q_prefix(cur_nm or "")
          ImGui.OpenPopup(ctx, "##midi_rn_popup"..c.id)
        end
        if rn_disabled then ImGui.PopStyleVar(ctx, 1) end
        if ImGui.IsItemHovered(ctx) and not rn_disabled then ImGui.SetTooltip(ctx, "Rename item (base name only; Q-prefix auto-managed)") end
        if ImGui.BeginPopup(ctx, "##midi_rn_popup"..c.id) then
          ImGui.SetNextItemWidth(ctx, FUNC.sz(220))
          local rn_ch, rn_nv = ImGui.InputText(ctx, "##midi_rn_in", c._rn_buf or "", ImGui.InputTextFlags_EnterReturnsTrue())
          if rn_ch then c._rn_buf = rn_nv end
          local enter = ImGui.IsItemDeactivatedAfterEdit(ctx) or rn_ch
          if enter and cur_take then
            local base = c._rn_buf or ""
            local pref = string.format("Q %s - ", tostring(c.cue_number or "?"))
            reaper.GetSetMediaItemTakeInfo_String(cur_take, "P_NAME", pref .. base, true)
            if cur_item then reaper.UpdateItemInProject(cur_item) end
            ImGui.CloseCurrentPopup(ctx)
          end
          ImGui.EndPopup(ctx)
        end
        -- [✎] Open in MIDI Editor + [+] New
        ImGui.SameLine(ctx, nil, btn_gap)
        if ImGui.Button(ctx, "\xE2\x9C\x8E##midi_open_edit", btn_w, 0) then
          local it = cur_item
          if it then
            reaper.Main_OnCommand(40289, 0)
            reaper.SetMediaItemSelected(it, true)
            reaper.Main_OnCommand(40153, 0)
          end
        end
        if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Open in REAPER MIDI Editor") end
        ImGui.SameLine(ctx, nil, btn_gap)
        if ImGui.Button(ctx, "+##midi_new_item", btn_w, 0) then
          if midi_tr then
            local new_guid = FUNC.midi_create_blank_item(midi_tr, 2.0)
            if new_guid ~= "" then
              for _, si in ipairs(valid) do FUNC.midi_assign_unique_guid(cues[si], new_guid) end
            end
          end
        end
        if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "New empty MIDI item on this track") end
        end  -- end midi_mode == "sequence" branch
        end  -- all_midi guard

        -- ═══ Checkboxes: Auto-Go + Kill Above | Loop + HotKey ═══
        ImGui.Dummy(ctx, 0, spc/2); ImGui.Separator(ctx); ImGui.Dummy(ctx, 0, spc/2)
        -- line 1: Auto-Go↑ + Kill Above↑（Kill Above對齊x2）
        local afch, afnv = ImGui.Checkbox(ctx, "Auto-Go\226\135\161", c.auto_go)
        if afch then apply("auto_go", afnv) end
        if not bas_narrow then ImGui.SameLine(ctx, x2) else ImGui.SameLine(ctx, x_note) end
        local ka_cx = ImGui.GetCursorPosX(ctx)  -- Kill Above cursor X（窄版HotKey對齊用）-- for narrow HotKey alignment
        local kach, kanv = ImGui.Checkbox(ctx, "Kill Above\226\135\161", c.kill_above)
        if kach then apply("kill_above", kanv) end
        -- line 2: Loop [count] + HotKey -- FADE cues hide Loop
        local any_play_or_grp = false
        for _, si in ipairs(valid) do
          local st = cues[si].type
          if st == "PLAY" or st == "GROUP" or st == "MIDI" then any_play_or_grp = true; break end
        end
        -- helper: draw HotKey at col3_x, stretch to right edge -- HotKey對齊Pan/Rate，延伸到右邊
        local function draw_hotkey()
          if multi then return end
          local hk = c.hotkey or ""
          local hk_label = (hk ~= "") and ("HotKey:"..hk) or "HotKey"
          if hotkey_listen then
            local blink = math.floor(reaper.time_precise() * 4) % 2 == 0
            local blink_col = blink and FUNC.rgba(255,200,80) or FUNC.rgba(180,140,60)
            ImGui.PushStyleColor(ctx, ImGui.Col_Text(), blink_col)
            ImGui.Text(ctx, "Press 0-9...")
            ImGui.PopStyleColor(ctx, 1)
            if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left()) then hotkey_listen = false end
            if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape()) then hotkey_listen = false
            else
              local det = FUNC.detect_digit_key()
              if det then c.hotkey = det; hotkey_listen = false; FUNC.save_cues() end
            end
          else
            local hk_w = ImGui.GetContentRegionAvail(ctx) - rpad  -- 延伸到右padding前 -- stretch to right padding
            if ImGui.Button(ctx, hk_label.."##hk", hk_w, 0) then hotkey_listen = true end
            if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, hk ~= "" and "Hotkey: "..hk.."\nClick to change\nRight-click to clear" or "Assign hotkey") end
            if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right()) then c.hotkey = ""; FUNC.save_cues() end
          end
        end
        if any_play_or_grp then
          local lch, lnv = ImGui.Checkbox(ctx, "Loop", c.loop)
          if lch then
            for _, si in ipairs(valid) do
              local sc = cues[si]
              if sc.type == "PLAY" or sc.type == "GROUP" or sc.type == "MIDI" then
                sc.loop = lnv
                if sc.type == "GROUP" then
                  for _, ch in ipairs(sc.children or {}) do
                    if ch >= 1 and ch <= #cues and cues[ch].type == "PLAY" then cues[ch].loop = lnv end
                  end
                end
              end
            end
          end
          -- loop count: stretch to fill before HotKey -- 勾選後輸入框填滿到HotKey前
          if c.loop then
            ImGui.SameLine(ctx, 0, 2)
            local cur_x = ImGui.GetCursorPosX(ctx)
            local hk_start = bas_narrow and ka_cx or x2  -- 窄版用Kill Above X，寬版用x2 -- narrow uses KA pos
            local fill_w = hk_start - cur_x - FUNC.sz(4)
            if fill_w < FUNC.sz(24) then fill_w = FUNC.sz(24) end
            ImGui.SetNextItemWidth(ctx, fill_w)
            local lc = c.loop_count or 0
            local lc_txt = lc > 0 and tostring(lc) or "+"
            local lc_ch, lc_nv = ImGui.InputText(ctx, "##lcount", lc_txt, ImGui.InputTextFlags_AutoSelectAll())
            if ImGui.IsItemActive(ctx) then popup.edit_text_active = true end  -- 輸入中擋Delete -- block Delete while typing
            if lc_ch then
              local n = tonumber(lc_nv)
              if n and n > 0 then apply("loop_count", math.floor(n))
              else apply("loop_count", 0) end
            end
            if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Loop count (+ = infinite)") end
          end
          -- HotKey at col3_x (wide) or ka_cx (narrow) -- HotKey對齊Kill Above
          ImGui.SameLine(ctx, bas_narrow and ka_cx or x2)
          draw_hotkey()
        else
          -- non-PLAY/GROUP: HotKey on line 2, aligned with Auto-Go -- FADE等：HotKey左對齊Auto-Go
          draw_hotkey()
        end

        ImGui.PopFont(ctx)
        if lpad > 0 then ImGui.Unindent(ctx, lpad) end  -- 對應Indent -- match Indent
        ImGui.EndChild(ctx) end  -- ##bas_fields
        ImGui.PopStyleVar(ctx, 1)  -- WindowPadding

        -- ═══════════════════════════════════════════════════════
end
