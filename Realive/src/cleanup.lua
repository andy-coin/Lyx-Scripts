-- ==========================================================================
-- cleanup.lua — Per-frame Cleanup
-- ==========================================================================

local _fp_cursor = 1  -- item fingerprint分批掃描游標 -- cursor for batched fingerprint scan
local _FP_BATCH = 4   -- 每幀掃描幾個cue -- cues to scan per frame

-- A6: 標籤頁內 highlight 取消（envelope points / midi notes / midi msg ch / route ch）
-- A6: clear inner-tab selections (envelope points / midi notes / midi msg channels / route channels)
function FUNC.clear_inner_sels()
  if env_drag then env_drag.sel = {} end
  if popup then popup.route_sel = {} end
  for _, c in ipairs(cues) do
    if c._midi_sel then c._midi_sel = {} end
    if c._midi_msg_sel then c._midi_msg_sel = {} end
  end
end
local _last_sel_id, _last_any_popup
local _POPUP_KEYS = {"settings","save","load","shortcuts","trim","fade_edit",
  "warn","warn_missing","save_overwrite","output_maps","_reset_confirm"}
local _last_ep_focused
function FUNC.poll_inner_sels()
  local sf = FUNC.sel_first()
  local cur_id = (sf and cues[sf]) and cues[sf].id or nil
  local any_popup = false
  for _, k in ipairs(_POPUP_KEYS) do if popup[k] then any_popup = true; break end end
  if _last_sel_id ~= nil and cur_id ~= _last_sel_id then FUNC.clear_inner_sels() end
  if any_popup and not _last_any_popup then FUNC.clear_inner_sels() end
  -- focus 離開 edit panel 時清除（例：點 ui_table 同 cue、點 toolbar 等）
  -- clear when focus leaves edit panel
  if _last_ep_focused and not _ep_focused_now then FUNC.clear_inner_sels() end
  _last_sel_id, _last_any_popup, _last_ep_focused = cur_id, any_popup, _ep_focused_now
  _ep_focused_now = false  -- reset；下幀 draw_edit_panel_inline 若有跑會重設 -- reset for next frame
end

function FUNC.cleanup()
  FUNC.process_fx_recenter()
  FUNC.poll_inner_sels()
  local rm = {}
  local now_pv = reaper.time_precise()
  for pid, p in pairs(active_previews) do
    -- 超過item邊界的preview自動停止 -- auto-stop previews that exceed item boundary (max_dur)
    if p.max_dur and (now_pv - p.t0) >= p.max_dur then
      rm[#rm+1] = pid
    elseif not FUNC.pv_playing(pid) then
      local hf = false; for _, f in ipairs(active_fades) do if f.pid == pid then hf = true; break end end
      if not hf then rm[#rm+1] = pid end
    end
  end
  for _, pid in ipairs(rm) do FUNC.pv_stop(pid) end
  -- Clean up expired cancelled fade displays
  local now_cf = reaper.time_precise()
  for cid, t in pairs(cancelled_fades) do if now_cf - t >= 0.5 then cancelled_fades[cid] = nil end end
  -- Detect PLAY cues that finished playback: transition running -> done + check_post
  local now = reaper.time_precise()
  for ci, c in ipairs(cues) do
    if c.type == "PLAY" and c.play_t0 > 0 and not paused_cues[c.id] then  -- 暫停中不算時間 -- time doesn't count while paused
      local dur = c.eff_dur > 0 and c.eff_dur or c.total_dur
      -- 絕對 playhead vs 當前 trim_end：trim 即時改動也能正確觸發 loop/done
      -- absolute playhead vs current trim_end so live trim edits trigger loop/done correctly
      local cr_chk = (c.rate and c.rate > 0) and c.rate or 1.0
      local play_ts_chk = c.play_offset or 0
      local ph_chk = play_ts_chk + (now - c.play_t0) * cr_chk
      local te_chk = (c.trim_end and c.trim_end > 0) and c.trim_end or (c.total_dur or 0)
      if dur > 0 and (ph_chk >= te_chk and te_chk > 0) then
        -- 理想結束時間：後續的連鎖/loop 從這裡起算，不累積每幀延遲 -- ideal end time: what follows is timed from here
        local t_end = c.play_t0 + (te_chk - play_ts_chk) / cr_chk
        if c.state == STATE.RUNNING and soft_kill[c.id] then
          -- Kill/Panic 淡出期間自己播完：當成被停掉，不觸發連鎖 -- ended by itself while being faded out by Kill/Panic: treat as killed, no chaining
          FUNC.cancel_fades_cue(c); FUNC.kill_cue(c); soft_kill[c.id] = nil
        elseif c.state == STATE.RUNNING then FUNC.at_time(t_end, function()
          if c.loop then
            -- loop次數判定：0=無限，>0=有限 -- loop count: 0=infinite, >0=finite
            local can_loop = true
            if (c.loop_count or 0) > 0 then
              c.loop_remaining = (c.loop_remaining or 0) - 1
              if c.loop_remaining <= 0 then can_loop = false end
            end
            if can_loop then
              if not c.loop_go_fired then
                c.loop_go_fired = true
                FUNC.check_post(ci)  -- loop首次完成時觸發auto_go
              end
              FUNC.play_cue(c)  -- restart: resets play_t0, new previews
            else
              c.loop_done = true  -- 有限loop結束，標記完成但保留checkbox狀態 -- finite loop done, keep checkbox
              c.state = STATE.DONE; FUNC.check_post(ci)
            end
          else
            c.state = STATE.DONE; FUNC.check_post(ci)
          end
        end) end
        -- Auto-stop previews after a grace period (not for looping cues)
        if (not c.loop or c.loop_done) and c.state == STATE.DONE and (now - c.play_t0) >= dur + 0.2 then FUNC.kill_cue(c) end
      end
    end
  end
  -- MIDI cue 排程 + 完成偵測 -- MIDI pending queue scheduler + completion
  for ci, c in ipairs(cues) do
    if c.type == "MIDI" and c.state == STATE.RUNNING and c.play_t0 > 0 and not soft_kill[c.id] then  -- Kill/Panic 淡出中交給 softkill 計時器收尾 -- during Kill/Panic the softkill timer finishes it
      local elapsed = now - c.play_t0
      -- ═══ 新路徑: item-based pending queue ═══
      if c._midi_pending then
        local pend = c._midi_pending
        -- events 已按 t 排序 → 從頭掃直到 t > elapsed
        while #pend > 0 and pend[1].t <= elapsed do
          local e = table.remove(pend, 1)
          FUNC.midi_fire_event(e)
        end
        -- 所有 events 發完且 dur 到期 → 完成（或 loop）-- all events fired + dur elapsed → done or loop
        local dur = c.total_dur or 0
        if #pend == 0 and elapsed >= dur then FUNC.at_time(c.play_t0 + dur, function()
          if c.loop then
            local can_loop = true
            if (c.loop_count or 0) > 0 then
              c.loop_remaining = (c.loop_remaining or 0) - 1
              if c.loop_remaining <= 0 then can_loop = false end
            end
            if can_loop then
              if not c.loop_go_fired then
                c.loop_go_fired = true
                FUNC.check_post(ci)
              end
              -- 重新建立 pending queue + 重置 play_t0 (不 unarm，維持 internal 模式的 arm 狀態)
              -- rebuild pending queue + reset play_t0 (keep arm for internal mode)
              local bundle = (c.midi_mode == "message")
                and FUNC.midi_build_pending_message(c)
                or FUNC.midi_build_pending(c)
              c._midi_pending = bundle.events
              c.play_t0 = FUNC.tnow()
              c.total_dur = bundle.dur_sec; c.eff_dur = bundle.dur_sec
            else
              c.loop_done = true
              if ((c.midi_device or -1) < 0) or c.midi_mode == "internal" then FUNC.midi_unarm_track(c) end
              c._midi_pending = nil
              c.state = STATE.DONE
              FUNC.check_post(ci)
            end
          else
            if ((c.midi_device or -1) < 0) or c.midi_mode == "internal" then FUNC.midi_unarm_track(c) end
            c._midi_pending = nil
            c.state = STATE.DONE
            FUNC.check_post(ci)
          end
        end) end
      -- ═══ Legacy 單音 fallback (message mode 有計時結束；CC類型立即完成不走這裡) ═══
      elseif c.midi_mode ~= "message" then
        local dur = c.total_dur or c.midi_duration or 0.5
        if dur > 0 and elapsed >= dur then
          local mv = c._midi_off_mode
          local cch = c._midi_off_ch
          local nt = c._midi_off_note
          if mv and cch and nt then
            reaper.StuffMIDIMessage(mv, 0x80 + cch, nt, 0)
          end
          c._midi_off_mode = nil; c._midi_off_ch = nil; c._midi_off_note = nil
          c.state = STATE.DONE
          FUNC.check_post(ci)
        end
      end
    end
  end
  -- FADE cue 的 fade 全被取消（目標被 Kill/Panic/新的 fade 蓋掉）→ 回到閒置，不留一列永遠「執行中」
  -- a FADE cue whose fades were all cancelled (target killed / panic / overridden) goes back to idle instead of showing "running" forever
  for _, c in ipairs(cues) do
    if c.type == "FADE" and c.state == STATE.RUNNING and not FUNC.fade_cue_alive(c) then
      c.state = STATE.IDLE; c.play_t0 = 0; cancelled_fades[c.id] = now
    end
  end
  -- next_go隱藏解除：最後一個cue播完/中斷時恢復>>游標 -- unhide next_go when last cue finishes or is killed
  if next_go_hidden then
    local c = cues[next_go]
    if not c or c.state == STATE.IDLE or c.state == STATE.DONE then next_go_hidden = false end
  end
  -- GROUP route trim cleanup: 當所有children都idle時自動還原trim -- auto-restore trims when all children idle
  for _, gc in ipairs(cues) do
    if gc._rt_hw_saved and gc.type == "GROUP" then
      local all_idle = true
      for _, ci in ipairs(gc.children or {}) do
        if ci >= 1 and ci <= #cues and cues[ci].state ~= STATE.IDLE then all_idle = false; break end
      end
      if all_idle then FUNC.rt_restore_trims(gc) end
    end
  end
  -- Track/MIDI item color 跟隨 cue color（含 group 繼承），_last_synced_color 快取避免重複寫入
  -- sync REAPER track / MIDI item color to cue color when pref enabled
  if prefs.track_color_follow == 1 and FUNC.sync_all_cue_colors then FUNC.sync_all_cue_colors() end
  -- GUID→track_idx 定期重新解析（每30幀），處理track被移動/刪除 -- periodic GUID re-resolution
  _warn_frame = _warn_frame + 1
  if _warn_frame >= 30 then
    for _, c in ipairs(cues) do
      if c.track_guid and c.track_guid ~= "" then
        local new_idx = FUNC.guid_to_idx(c.track_guid)
        if new_idx >= 0 then
          c.track_idx = new_idx; c.track_invalid = false
        else
          c.track_idx = -1; c.track_invalid = true  -- track已刪除或不存在 -- track deleted or missing
        end
      end
    end
  end
  -- 偵測REAPER軌道item變更(切割/移動/刪除)→分批更新duration和波形(每幀掃幾個) -- batched item change detection (per frame)
  if #cues > 0 then
    if _fp_cursor > #cues then _fp_cursor = 1 end
    for _ = 1, math.min(_FP_BATCH, #cues) do
      local c = cues[_fp_cursor]
      if c and c.type == "PLAY" and c.track_idx >= 0 and not c.track_invalid then
        local fp = FUNC.item_fingerprint(c.track_idx)
        if fp ~= (c._item_fp or "") then
          c._item_fp = fp
          FUNC.refresh_cue_dur(c)
        end
      end
      _fp_cursor = _fp_cursor + 1
      if _fp_cursor > #cues then _fp_cursor = 1 end
    end
  end
  -- Track state monitoring: vol/pan + invalid warnings for PLAY cues
  if _warn_frame >= 30 then _warn_frame = 0
  for ci, c in ipairs(cues) do
    if c.type == "PLAY" and c.track_invalid then
      -- track不存在：顯示warning -- track missing: show warning
      track_warns[c.id] = track_warns[c.id] or {}
      track_warns[c.id].missing = true
    elseif c.type == "PLAY" and c.track_idx >= 0 then
      local tr = FUNC.get_tr(c.track_idx)
      if tr then
        if track_warns[c.id] then track_warns[c.id].missing = nil end  -- 清除missing flag
        local w = track_warns[c.id] or {}
        -- vol: track D_VOL應為envelope控制值，手動改了要warning -- track vol reserved for envelope
        local tr_vol = reaper.GetMediaTrackInfo_Value(tr, "D_VOL")
        local tr_vol_db = tr_vol > 0 and (20 * math.log(tr_vol, 10)) or -150
        if math.abs(tr_vol - 1.0) > 0.005 then
          w.vol = string.format("%.1f dB", tr_vol_db)
          w.vol_val = tr_vol
        else
          w.vol = nil; w.vol_val = nil
        end
        -- pan: track D_PAN應為0（留給envelope）-- track pan should be 0 (reserved for envelope)
        local tr_pan = reaper.GetMediaTrackInfo_Value(tr, "D_PAN")
        if math.abs(tr_pan) > 0.005 then
          local to_s = string.format("%.0f", tr_pan * 100)
          w.pan = "0 → "..to_s
          w.pan_val = tr_pan
        else
          w.pan = nil; w.pan_val = nil
        end
        if w.vol or w.pan then track_warns[c.id] = w
        else track_warns[c.id] = nil end
      end
    end
    -- 掃描 fx_envs 遺失狀態 -- scan fx_envs missing
    if c.type == "PLAY" and c.fx_envs and #c.fx_envs > 0 then
      FUNC.fx_env_check_missing(c)
    end
  end
  end -- _warn_frame throttle end
  -- 兜底：每幀檢查是否該解鎖track control -- safety net: check global unlock every frame
  FUNC.check_global_unlock()
end

-- 引擎每幀工作（不含繪圖）：main_loop 與 tests/ 共用同一份 -- one engine frame (no drawing); shared by main_loop and tests/
function FUNC.engine_tick()
  FUNC.rebuild_id_map() -- 每幀重建 id→index 快查表
  FUNC.process_timers(); FUNC.process_fades(); FUNC.cleanup(); FUNC.apply_master()
  FUNC.env_apply_all()  -- 每幀套用 volume envelope 到軌道推桿
  FUNC.pan_env_apply_all()  -- 每幀套用 pan envelope 到D_PAN
  FUNC.fx_env_apply_all()  -- 每幀套用 FX parameter envelope
  FUNC.fx_env_poll_pending()  -- 每幀檢查 FX env pending 狀態是否有 new touch
end
