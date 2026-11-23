-- ==========================================================================
-- waveform.lua — PCM Waveform Display Engine for Edit Panel
-- ==========================================================================

---------------------------------------------------------------------
-- WAVEFORM STATE (per-cue cache)
---------------------------------------------------------------------
local wf_cache = {}  -- cue_id -> {peaks={}, dur=0, srate=0, n_ch=0, src_hash=""}
local wf_view = {}   -- cue_id -> {zoom=1, pos=0, v_zoom=1} -- 視圖狀態保留

-- 波形顏色從 C.wf 讀取（Settings 可改） -- waveform color from prefs

-- 互動狀態
wf_drag = {active=false, start_x=0, start_y=0, start_pos=0, start_scroll=0}  -- 右鍵拖曳平移 (global給envelope用)
wf_handle = {dragging=nil}  -- "start" or "end" or "gain" or nil (global給envelope用)
local wf_marquee = {}  -- lane_key -> {t0=time, hov=false} -- 跑馬燈狀態 -- marquee state per lane
-- guide line + range selection -- 指引線+選取範圍（暫時，離開waveform即消失）
wf_sel = {cid=nil, t0=nil, t1=nil, dragging=false, preview_ids=nil}
-- markers（per-cue時間戳記，儲存在cue.markers） -- per-cue time markers stored in cue.markers
wf_markers = {}  -- runtime convenience，真正資料在 c.markers

---------------------------------------------------------------------
-- GET PEAKS FROM PCM SOURCE -- 取得PCM峰值
---------------------------------------------------------------------
-- peaks_per_pixel 控制解析度，回傳 {[i]={min, max}, ...}
function FUNC.wf_get_peaks(src, srate, start_sec, end_sec, num_pixels)
  if not src or num_pixels < 1 then return {} end
  local dur = end_sec - start_sec
  if dur <= 0 then return {} end
  local peaks_per_sec = num_pixels / dur
  -- Buffer layout: first N = maximums, next N = minimums (block layout, not interleaved)
  local buf = reaper.new_array(num_pixels * 2 + 64)  -- extra padding
  buf.clear()
  local ret = reaper.PCM_Source_GetPeaks(src, peaks_per_sec, start_sec, 1, num_pixels, 0, buf)
  local n_samples = ret & 0xFFFFF  -- low 20 bits = sample count returned
  if n_samples < 1 then n_samples = num_pixels end
  local peaks = {}
  for i = 1, num_pixels do
    local idx = math.min(i, n_samples)
    local mx = buf[idx] or 0          -- maximums block (first N)
    local mn = buf[n_samples + idx] or 0  -- minimums block (next N)
    peaks[i] = {mn, mx}
  end
  return peaks
end

---------------------------------------------------------------------
-- BUILD / CACHE PEAK DATA FOR A CUE -- 建立峰值快取
---------------------------------------------------------------------
function FUNC.wf_build_cache(c, width)
  if not c or c.type ~= "PLAY" then return nil end
  local tr = FUNC.get_tr(c.track_idx)
  if not tr then return nil end
  local items = FUNC.get_items(c.track_idx)
  if #items == 0 then return nil end

  -- Get first item's source for peaks
  local item = reaper.GetTrackMediaItem(tr, 0)
  if not item then return nil end
  local take = reaper.GetActiveTake(item)
  if not take then return nil end
  local src = reaper.GetMediaItemTake_Source(take)
  if not src then return nil end

  local base = items[1].pos
  local last_end = 0
  for _, it in ipairs(items) do last_end = math.max(last_end, it.pos + it.len) end
  local total_dur = last_end - base
  if total_dur <= 0 then return nil end

  -- Source sample rate
  local sr = reaper.GetMediaSourceSampleRate(src)
  if sr == 0 then sr = 44100 end

  -- Check cache validity
  local cid = c.id
  local cache = wf_cache[cid]
  -- hash含item數量/位置/長度/take_offs，item被切割/移動/刪除後cache自動失效重建 -- include full item info in hash for realtime cache invalidation
  local item_str = tostring(#items) .. ";"
  for _, it in ipairs(items) do item_str = item_str .. string.format("%.6f:%.6f:%.6f,", it.pos, it.len, it.take_offs or 0) end
  local src_hash = tostring(src) .. "|" .. tostring(total_dur) .. "|" .. tostring(width) .. "|" .. item_str
  if cache and cache.src_hash == src_hash then return cache end

  -- Build peaks for entire duration at given pixel width
  -- 對每個 item 取 peaks 然後合併
  local all_peaks = {}
  for i = 1, width do all_peaks[i] = {0, 0} end

  for _, it in ipairs(items) do
    local it_start = it.pos - base
    local it_end = it_start + it.len
    local it_take = nil
    -- Get this item's take/source
    local ritem = nil
    local n_items = reaper.GetTrackNumMediaItems(tr)
    for ni = 0, n_items - 1 do
      local ri = reaper.GetTrackMediaItem(tr, ni)
      local rpos = reaper.GetMediaItemInfo_Value(ri, "D_POSITION")
      if math.abs(rpos - it.pos) < 0.001 then ritem = ri; break end
    end
    if not ritem then goto next_item end
    it_take = reaper.GetActiveTake(ritem)
    if not it_take then goto next_item end
    local it_src = reaper.GetMediaItemTake_Source(it_take)
    if not it_src then goto next_item end

    -- Which pixel range does this item span?
    local px_start = math.max(1, math.floor(it_start / total_dur * width) + 1)
    local px_end = math.min(width, math.ceil(it_end / total_dur * width))
    local px_count = px_end - px_start + 1
    if px_count < 1 then goto next_item end

    -- 用take_offs作為起始位置，讓剪裁/分割的item顯示正確的波形 -- use take offset for trimmed/split items
    local t_offs = it.take_offs or 0
    local item_peaks = FUNC.wf_get_peaks(it_src, sr, t_offs, t_offs + it.len, px_count)
    for pi = 1, px_count do
      local idx = px_start + pi - 1
      if idx >= 1 and idx <= width and item_peaks[pi] then
        local mn = item_peaks[pi][1]
        local mx = item_peaks[pi][2]
        if mn < all_peaks[idx][1] then all_peaks[idx][1] = mn end
        if mx > all_peaks[idx][2] then all_peaks[idx][2] = mx end
      end
    end
    ::next_item::
  end

  -- 計算max peak用於normalize -- compute max peak for normalize
  local max_pk = 0
  for _, pk in ipairs(all_peaks) do
    if pk[2] > max_pk then max_pk = pk[2] end
    if -pk[1] > max_pk then max_pk = -pk[1] end
  end
  cache = {peaks = all_peaks, dur = total_dur, srate = sr, n_ch = 1, src_hash = src_hash, width = width, max_peak = max_pk}
  wf_cache[cid] = cache
  return cache
end

---------------------------------------------------------------------
-- INVALIDATE CACHE -- 清除快取
---------------------------------------------------------------------
function FUNC.wf_invalidate(cue_id)
  wf_cache[cue_id] = nil
end

-- cue 刪除時回收 cache + view -- release cache + view on cue deletion
function FUNC.wf_release(cue_id)
  wf_cache[cue_id] = nil
  wf_view[cue_id] = nil
end

---------------------------------------------------------------------
-- GET/INIT VIEW STATE -- 視圖狀態
---------------------------------------------------------------------
local function get_view(cid)
  if not wf_view[cid] then
    wf_view[cid] = {zoom = 1, pos = 0, pos_target = 0, v_zoom = 1}
  end
  local v = wf_view[cid]
  if not v.pos_target then v.pos_target = v.pos end  -- 向下相容 -- backwards compat
  if not v.zoom_target then v.zoom_target = v.zoom end
  if not v.vz_target then v.vz_target = v.v_zoom end
  -- v_zoom外部變更偵測（不受anchor影響）-- v_zoom external change detection (anchor-independent)
  if v._last_vz and math.abs(v.v_zoom - v._last_vz) > 0.001 then v.vz_target = v.v_zoom end
  -- anchor模式下跳過pos/zoom外部偵測（anchor每幀都改pos，會被誤判為外部變更）
  -- skip pos/zoom external detection in anchor mode (anchor changes pos every frame, would be falsely detected)
  if not v.anchor_t then
    if v._last_pos and math.abs(v.pos - v._last_pos) > 0.0001 then v.pos_target = v.pos end
    if v._last_zoom and math.abs(v.zoom - v._last_zoom) > 0.001 then v.zoom_target = v.zoom end
  end
  -- 平滑lerp -- smooth lerp each frame
  local k = 0.35  -- 平滑係數 -- smoothing factor
  -- zoom lerp
  local dz = v.zoom_target - v.zoom
  if math.abs(dz) > 0.01 then v.zoom = v.zoom + dz * k else v.zoom = v.zoom_target end
  -- hzoom anchor模式：從anchor+zoom推導pos，保持zoom center穩定 -- anchor mode: derive pos from anchor+zoom for stable zoom center
  if v.anchor_t then
    local cur_dur = v.anchor_total_dur / v.zoom
    v.pos = v.anchor_t - v.anchor_frac * cur_dur
    v.pos = math.max(0, math.min(v.pos, math.max(0, v.anchor_total_dur - cur_dur)))
    v.pos_target = v.pos  -- 同步target -- sync target
    -- zoom到達目標後清除anchor -- clear anchor when zoom reaches target
    if math.abs(v.zoom - v.zoom_target) < 0.01 then v.anchor_t = nil end
  else
    -- 一般pos lerp（scrolling/拖曳）-- normal pos lerp for scrolling/drag
    local dp = v.pos_target - v.pos
    if math.abs(dp) > 0.0001 then v.pos = v.pos + dp * k else v.pos = v.pos_target end
  end
  -- v_zoom lerp
  local dvz = v.vz_target - v.v_zoom
  if math.abs(dvz) > 0.001 then v.v_zoom = v.v_zoom + dvz * k else v.v_zoom = v.vz_target end
  v._last_pos = v.pos; v._last_zoom = v.zoom; v._last_vz = v.v_zoom
  return v
end

---------------------------------------------------------------------
-- TIME RULER -- 時間軸刻度（PLAY/GROUP共用）
---------------------------------------------------------------------
-- 在波形上方畫時間刻度線+標籤，根據zoom自動選擇間隔
-- bottom ruler：ticks朝下+文字在下方（參考fade chart風格）-- bottom ruler: ticks down, text below (fade chart style)
local function draw_time_ruler(dl, rx, ry, rw, view_start, view_dur, display_offset)
  if rw < 20 or view_dur <= 0 then return end
  display_offset = display_offset or 0  -- 顯示時間 = view 時間 - offset (用於 group 負前綴) -- display = view - offset
  -- 自動選擇刻度間隔：每個刻度至少佔50px -- auto-select tick interval (min 50px per tick)
  local intervals = {0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600}
  local min_px = FUNC.sz(50)
  local interval = intervals[#intervals]
  for _, iv in ipairs(intervals) do
    if (iv / view_dur) * rw >= min_px then interval = iv; break end
  end
  local first_tick = math.ceil((view_start - display_offset) / interval) * interval
  local view_end = view_start + view_dur
  local view_end_disp = view_end - display_offset
  -- 參考fade chart：白色tick+文字 -- fade chart style: white ticks + text
  local tick_col = FUNC.rgba(255, 255, 255)
  local sub_col = FUNC.rgba(255, 255, 255, 120)
  local text_col = FUNC.rgba(255, 255, 255)
  ImGui.PushFont(ctx, FONT, FUNC.sz(11))  -- 同fade chart字體 -- same font as fade chart
  local t_disp = first_tick
  while t_disp <= view_end_disp do
    local t = t_disp + display_offset  -- view 座標 -- view coord
    local px = rx + ((t - view_start) / view_dur) * rw
    if px >= rx and px <= rx + rw then
      -- 主刻度線朝下 -- main tick line downward
      ImGui.DrawList_AddLine(dl, px, ry, px, ry + FUNC.sz(4), tick_col, 1)
      -- 時間標籤在tick下方 -- time label below tick
      local label
      local sign = (t_disp < -0.005) and "-" or ""
      local at = math.abs(t_disp)
      local m = math.floor(at / 60); local s = at - m * 60
      if interval < 1 and s > 0.01 then
        local sf = string.format("%04.1f", s)
        if sf:sub(-1) == "0" then sf = string.format("%02d", math.floor(s + 0.5)) end
        label = string.format("%s%d:%s", sign, m, sf)
      elseif s > 0.01 then label = string.format("%s%d:%02d", sign, m, math.floor(s + 0.5))
      else label = string.format("%s%d:00", sign, m) end
      local tw = ImGui.CalcTextSize(ctx, label, 0, 0)
      local lx = FUNC.clamp(px - tw / 2, rx, rx + rw - tw)
      ImGui.DrawList_AddText(dl, lx, ry + FUNC.sz(5), text_col, label)
    end
    -- 副刻度 -- sub-tick at midpoint
    local sub_t = t + interval / 2
    if sub_t < view_end then
      local sub_px = rx + ((sub_t - view_start) / view_dur) * rw
      if sub_px >= rx and sub_px <= rx + rw then
        ImGui.DrawList_AddLine(dl, sub_px, ry, sub_px, ry + FUNC.sz(2), sub_col, 1)
      end
    end
    t_disp = t_disp + interval
  end
  ImGui.PopFont(ctx)
end

-- 外部呼叫：在指定 Y 重繪 group ruler（sticky timecode 用） -- external sticky ruler
function FUNC.draw_group_waveform_ruler(gc, dl, ruler_y)
  local r = gc and gc._gw_ruler
  if not r then return end
  draw_time_ruler(dl, r.x, ruler_y, r.w, r.view_start, r.view_dur, r.prefix)
end

-- 外部呼叫：在指定 Y 繪製 + 互動 sticky end handle -- sticky end handle draw + hit-test
function FUNC.draw_group_waveform_end_handle(gc, dl, handle_y)
  local h = gc and gc._gw_end_handle
  if not h or not h.e_vis then return end
  local e_x1, e_x2 = h.trim_e_x - h.tab_w / 2, h.trim_e_x + h.tab_w / 2
  local e_y1, e_y2 = handle_y, handle_y + h.tab_h
  local hov_e = ImGui.IsMouseHoveringRect(ctx, e_x1 - 2, e_y1, e_x2 + 2, e_y2)
  local hcol = (hov_e or wf_handle.dragging == "end") and h.handle_hover_col or h.handle_col
  ImGui.DrawList_AddRectFilled(dl, e_x1, e_y1, e_x2, e_y2, hcol, 2)
  -- hit-test：拖曳中或其他互動進行中時不啟動 -- skip hit-test during active interactions
  if hov_e and not wf_handle.dragging and not env_drag.active and not env_drag.marquee and not env_drag.pending then
    if ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left()) then
      gc.trim_start = 0; gc.trim_end = 0; FUNC.save_cues(); wf_handle.dragging = nil
    elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left()) then
      wf_handle.dragging = "end"; FUNC.push_undo()
    end
  end
end

---------------------------------------------------------------------
-- RANGE SELECTION PLAY / CLEAR -- 選取範圍播放/清除
---------------------------------------------------------------------
-- 停止並清除選取preview -- stop and clear selection preview
function FUNC.wf_sel_stop()
  if wf_sel.preview_ids then
    for _,pid in ipairs(wf_sel.preview_ids) do FUNC.pv_stop(pid) end
  end
  -- 還原route engage的軌道 -- restore route-engaged tracks
  if wf_sel._engaged then
    for _, ec in ipairs(wf_sel._engaged) do FUNC.env_restore_track(ec, "wfsel:" .. ec.id) end
    wf_sel._engaged = nil
  end
  -- 還沒開始的後段 item 也要取消，否則停止後它們仍會出聲 -- cancel later items not started yet, or they still sound after Stop
  local ti = 1; while ti <= #active_timers do
    if active_timers[ti].cue_id == "_wfsel" then table.remove(active_timers, ti) else ti = ti + 1 end
  end
  wf_sel.preview_ids = nil; wf_sel.play_t0 = nil
end
-- 完全清除選取狀態 -- fully clear selection state
function FUNC.wf_sel_clear()
  FUNC.wf_sel_stop()
  wf_sel.cid = nil; wf_sel.t0 = nil; wf_sel.t1 = nil; wf_sel.dragging = false
end
-- 播放選取範圍（由preview按鈕/快速鍵呼叫）-- play selected range (called by preview button/shortcut)
function FUNC.wf_sel_play(c)
  if not c or not wf_sel.t0 or not wf_sel.t1 then return false end
  FUNC.wf_sel_stop()
  local s0 = math.min(wf_sel.t0, wf_sel.t1)
  local s1 = math.max(wf_sel.t0, wf_sel.t1)
  if s1 - s0 <= 0.02 then return false end
  wf_sel.preview_ids = {}
  -- route engage：追蹤用到的track做hw切換 -- engage hw routing for used tracks
  wf_sel._engaged = {}
  local engaged_ti = {}  -- 避免重複engage同一track -- avoid duplicate engage

  if c.type == "GROUP" then
    -- GROUP：播放所有lane中落在選取範圍的children -- play children overlapping selection
    local li = FUNC.group_lanes(c)
    -- 選取範圍 wf_sel.t0/t1 為虛擬座標(含 prefix)，轉回 lane 正座標 -- convert virtual → lane positive
    local gprefix = li.prefix or 0
    s0 = s0 - gprefix
    s1 = s1 - gprefix
    for _, lane in ipairs(li.lanes) do
      for _, entry in ipairs(lane.entries) do
        local cc = entry.cue
        if cc and cc.type == "PLAY" then
          local a_s = entry.offset + entry.pre  -- child audio start in group timeline
          local a_e = a_s + entry.eff_dur
          if a_e > s0 and a_s < s1 then
            -- route engage for this child's track
            if not engaged_ti[cc.track_idx] then
              engaged_ti[cc.track_idx] = true
              FUNC.env_save_track(cc, nil, "wfsel:" .. cc.id)
              wf_sel._engaged[#wf_sel._engaged+1] = cc
            end
            local cr = (cc.rate and cc.rate > 0) and cc.rate or 1.0
            local ts = cc.trim_start or 0
            local child_audio_off = math.max(0, s0 - a_s) * cr + ts
            local play_len = (math.min(a_e, s1) - math.max(a_s, s0)) / cr
            local delay = math.max(0, a_s - s0)
            local items = FUNC.get_items(cc.track_idx)
            if #items > 0 then
              local base = items[1].pos
              for _,it in ipairs(items) do
                local rs = it.pos - base; local re = rs + it.len
                local it_s = rs + ts; local it_e = re  -- item range in trimmed coords
                -- 映射到child內的offset -- map to offset within child
                local child_off_s = child_audio_off
                local child_off_e = child_audio_off + play_len * cr
                if re > child_off_s and rs + (it.take_offs or 0) < child_off_e then
                  local src_off = math.max(0, child_audio_off - rs) + (it.take_offs or 0)
                  local function do_pv()
                    local pid = FUNC.pv_create(it.src, cc.track_idx, FUNC.eff_vol(cc), src_off, cr, cc.preserve_pitch, cc.pitch, play_len, cc.pan or 0)
                    if pid and wf_sel.preview_ids then wf_sel.preview_ids[#wf_sel.preview_ids+1] = pid end
                  end
                  if delay < 0.001 then do_pv()
                  else active_timers[#active_timers+1] = {t0=reaper.time_precise(), dur=delay, ci=-1, tt="item", cue_id="_wfsel", cb=do_pv} end
                end
              end
            end
          end
        end
      end
    end
  else
    -- PLAY cue：原有邏輯 -- PLAY cue: original logic
    -- route engage for this track
    if not engaged_ti[c.track_idx] then
      engaged_ti[c.track_idx] = true
      FUNC.env_save_track(c, nil, "wfsel:" .. c.id)
      wf_sel._engaged[#wf_sel._engaged+1] = c
    end
    local items = FUNC.get_items(c.track_idx)
    if #items == 0 then return false end
    local base = items[1].pos
    local cue_rate = (c.rate and c.rate > 0) and c.rate or 1.0
    for _,it in ipairs(items) do
      local rs = it.pos - base; local re = rs + it.len
      if re > s0 and rs < s1 then
        local src_off = math.max(0, s0 - rs) + (it.take_offs or 0)
        local play_len = (math.min(re, s1) - math.max(rs, s0)) / cue_rate
        local delay = math.max(0, (rs - s0) / cue_rate)
        local function do_pv()
          local pid = FUNC.pv_create(it.src, c.track_idx, FUNC.eff_vol(c), src_off, cue_rate, c.preserve_pitch, c.pitch, play_len, c.pan or 0)
          if pid and wf_sel.preview_ids then wf_sel.preview_ids[#wf_sel.preview_ids+1] = pid end
        end
        if delay < 0.001 then do_pv()
        else active_timers[#active_timers+1] = {t0=reaper.time_precise(), dur=delay, ci=-1, tt="item", cue_id="_wfsel", cb=do_pv} end
      end
    end
  end

  wf_sel.play_t0 = reaper.time_precise()
  return true
end
-- 檢查是否有有效選取範圍 -- check if valid selection exists
function FUNC.wf_sel_active() return wf_sel.cid and wf_sel.t0 and wf_sel.t1 end

---------------------------------------------------------------------
-- DRAW WAVEFORM -- 主繪圖函數
---------------------------------------------------------------------
-- 畫在 Edit Panel 裡，給定繪圖區 (cx, cy, cw, ch)
-- c = cue object, dl = DrawList
function FUNC.draw_waveform_display(c, dl, cx, cy, cw, ch)
  if not c or c.type ~= "PLAY" or cw < 10 or ch < 10 then return end

  local cid = c.id
  local view = get_view(cid)

  -- 切換cue時清除選取+停止preview -- clear selection when switching to different cue
  if wf_sel.cid and wf_sel.cid ~= cid then FUNC.wf_sel_clear() end

  -- Padding for tab protrusion -- 上下留更多空給handle+ruler
  local tab_h_val = FUNC.sz(16)  -- handle tab 高度
  local ruler_h = FUNC.sz(18)  -- 底部ruler高度（tick+文字）-- bottom ruler height
  local pad_top = tab_h_val + FUNC.sz(8)  -- start handle tab + 上方留空
  local pad_bot = tab_h_val + FUNC.sz(4) + ruler_h  -- end handle tab + ruler -- end handle + ruler
  local wy = cy + pad_top   -- waveform content area top
  local wh = ch - pad_top - pad_bot  -- waveform content area height

  -- GROUP有效trim（含父GROUP裁剪）-- effective trim including parent GROUP
  local eff_ts_gp, eff_te_gp = FUNC.get_eff_trim(c)

  -- pre/post wait區域計算（固定10%寬度，可收合至30sz）-- fixed 10% width, collapsible to sz(30)
  local pre_w_sec = c.pre_wait or 0
  local post_w_sec = c.post_wait or 0
  local has_pre = pre_w_sec > 0.001
  local has_post = post_w_sec > 0.001
  -- 收合狀態（per-cue runtime，不存檔）-- collapsed state (per-cue runtime, not serialized)
  if not wf_markers._pp_col then wf_markers._pp_col = {} end
  local pp_col = wf_markers._pp_col
  local pre_collapsed = pp_col[c.id.."_pre"] or false
  local post_collapsed = pp_col[c.id.."_post"] or false
  local pp_min = FUNC.sz(40)  -- 收合時最小寬度 -- collapsed min width
  local pre_px = has_pre and (pre_collapsed and pp_min or math.max(pp_min, math.floor(cw * 0.1))) or 0
  local post_px = has_post and (post_collapsed and pp_min or math.max(pp_min, math.floor(cw * 0.1))) or 0
  local wf_cx = cx + pre_px   -- 波形區域起始X -- waveform area start X
  local wf_cw = cw - pre_px - post_px  -- 波形區域寬度 -- waveform area width
  if wf_cw < 20 then wf_cw = cw; pre_px = 0; post_px = 0; wf_cx = cx end  -- fallback

  -- pre/post 三角形可調參數 -- tunable triangle params
  local PP_TRI_SZ  = FUNC.sz(7)   -- 三角形大小 -- triangle size
  local PP_TRI_GAP = FUNC.sz(5)   -- 三角形與倒數文字間距 -- gap between countdown and triangle

  -- pre wait區域 -- pre-wait zone
  local wf_ci = FUNC.find_id(c.id) or 0  -- 取得cue index給timer查詢用 -- get cue index for timer lookup
  if pre_px > 0 then
    ImGui.DrawList_AddRectFilled(dl, cx, wy, cx + pre_px, wy + wh, C.wf_bg, 4)
    -- 播放狀態填色（用timer_prog取得prewait進度）-- fill during prewait state (use timer_prog)
    local pw_frac = nil
    if c.state == STATE.PREWAIT then
      pw_frac = FUNC.timer_prog(wf_ci, TIMER.PRE) or 0
      ImGui.DrawList_AddRectFilled(dl, cx, wy, cx + pre_px * pw_frac, wy + wh, C.p_wait, 4)
    elseif c.state == STATE.RUNNING or c.state == STATE.POSTWAIT or c.state == STATE.DONE then
      pw_frac = 1
      ImGui.DrawList_AddRectFilled(dl, cx, wy, cx + pre_px, wy + wh, C.p_wait, 4)
    end
    -- "Pre" 標題 + 倒數計時 -- "Pre" label + countdown timer
    local fill_edge = cx + pre_px * (pw_frac or 0)
    local pre_label = "Pre"
    local plw, plh = ImGui.CalcTextSize(ctx, pre_label, 0, 0)
    -- 倒數文字 -- countdown text
    local pre_cd = ""
    local pre_cd_w, pre_cd_h = 0, 0
    if c.state == STATE.PREWAIT then
      local rem = FUNC.timer_rem(wf_ci, TIMER.PRE) or pre_w_sec
      pre_cd = FUNC.fmt_t(rem)
    elseif pw_frac == nil then
      pre_cd = FUNC.fmt_t(pre_w_sec)  -- idle時顯示總時長 -- show total duration when idle
    end
    if pre_cd ~= "" then
      ImGui.PushFont(ctx, FONT_MONO, FUNC.sz(14))
      pre_cd_w, pre_cd_h = ImGui.CalcTextSize(ctx, pre_cd, 0, 0)
      ImGui.PopFont(ctx)
    end
    local tri_row_h = PP_TRI_SZ + PP_TRI_GAP  -- 三角形行高 -- triangle row height
    local cd_row_h = (pre_cd ~= "" and not pre_collapsed) and (pre_cd_h + 1) or 0  -- 收合時不算倒數行高 -- skip countdown height when collapsed
    local total_txt_h = plh + cd_row_h + tri_row_h
    local txt_y0 = wy + (wh - total_txt_h) / 2
    -- "Pre" 逐字母反白 -- per-char invert for "Pre"
    if plw < pre_px - 4 then
      local lx0 = cx + (pre_px - plw) / 2
      local char_x = lx0
      for ci2 = 1, #pre_label do
        local ch = pre_label:sub(ci2, ci2)
        local chw = ImGui.CalcTextSize(ctx, ch, 0, 0)
        local ch_col = (pw_frac and (char_x + chw * 0.5) <= fill_edge) and C.wf_bg or C.p_wait
        ImGui.DrawList_AddText(dl, char_x, txt_y0, ch_col, ch)
        char_x = char_x + chw
      end
    end
    -- 倒數計時文字（收合時不顯示）-- countdown text (hidden when collapsed)
    if pre_cd ~= "" and not pre_collapsed and pre_cd_w < pre_px - 4 then
      ImGui.PushFont(ctx, FONT_MONO, FUNC.sz(14))
      local cd_x = cx + (pre_px - pre_cd_w) / 2
      local cd_y = txt_y0 + plh + 1
      -- 倒數也逐字反白 -- countdown also per-char invert
      local cd_char_x = cd_x
      for ci2 = 1, #pre_cd do
        local ch = pre_cd:sub(ci2, ci2)
        local chw = ImGui.CalcTextSize(ctx, ch, 0, 0)
        local ch_col = (pw_frac and (cd_char_x + chw * 0.5) <= fill_edge) and C.wf_bg or C.p_wait
        ImGui.DrawList_AddText(dl, cd_char_x, cd_y, ch_col, ch)
        cd_char_x = cd_char_x + chw
      end
      ImGui.PopFont(ctx)
    end
    ImGui.DrawList_AddRect(dl, cx, wy, cx + pre_px, wy + wh, FUNC.dim_c(FUNC.rgba(60,60,80)), 4, 0, 1)
    -- 三角形在文字下方，左右指向變化方向 -- triangle below text, points toward change direction
    local tri_h = PP_TRI_SZ * 0.5
    local last_y = txt_y0 + plh + cd_row_h + PP_TRI_GAP  -- "Pre" + 倒數(若有) + 間距 -- after label + countdown + gap
    local tri_cy = last_y + tri_h * 0.5  -- 垂直置中 -- vertical center
    local tri_cx = cx + pre_px * 0.5
    local pre_area_hov = ImGui.IsMouseHoveringRect(ctx, cx, wy, cx + pre_px, wy + wh)
    -- 三角形反白：進度走過用wf_bg，未走過用p_wait -- invert: filled=wf_bg, unfilled=p_wait
    local tri_filled = pw_frac and (tri_cx <= fill_edge)
    local tri_base = tri_filled and C.wf_bg or C.p_wait
    local tri_col = pre_area_hov and (tri_base | 0xFF) or ((tri_base & 0xFFFFFF00) | 0x80)
    if pre_collapsed then
      -- ▶ 指右（展開方向）-- ▶ points right (expand direction)
      ImGui.DrawList_AddTriangleFilled(dl, tri_cx - tri_h, tri_cy - tri_h, tri_cx - tri_h, tri_cy + tri_h, tri_cx + tri_h, tri_cy, tri_col)
    else
      -- ◀ 指左（收合方向）-- ◀ points left (collapse direction)
      ImGui.DrawList_AddTriangleFilled(dl, tri_cx + tri_h, tri_cy - tri_h, tri_cx + tri_h, tri_cy + tri_h, tri_cx - tri_h, tri_cy, tri_col)
    end
    -- 整個pre區塊可點擊toggle -- entire pre area clickable to toggle
    if pre_area_hov and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left()) then
      pp_col[c.id.."_pre"] = not pre_collapsed
    end
  end

  -- post wait區域 -- post-wait zone
  if post_px > 0 then
    local post_x = cx + cw - post_px
    ImGui.DrawList_AddRectFilled(dl, post_x, wy, cx + cw, wy + wh, C.wf_bg, 4)
    -- 播放狀態填色（用timer_prog取得postwait進度）-- fill during postwait (use timer_prog)
    local ptw_frac = nil
    if c.state == STATE.POSTWAIT then
      ptw_frac = FUNC.timer_prog(wf_ci, TIMER.POST) or 0
      ImGui.DrawList_AddRectFilled(dl, post_x, wy, post_x + post_px * ptw_frac, wy + wh, C.p_ptw, 4)
    end
    -- "Post" 標題 + 倒數計時 -- "Post" label + countdown timer
    local post_fill_edge = post_x + post_px * (ptw_frac or 0)
    local post_label = "Post"
    local polw, polh = ImGui.CalcTextSize(ctx, post_label, 0, 0)
    -- 倒數文字 -- countdown text
    local post_cd = ""
    local post_cd_w, post_cd_h = 0, 0
    if c.state == STATE.POSTWAIT then
      local rem = FUNC.timer_rem(wf_ci, TIMER.POST) or post_w_sec
      post_cd = FUNC.fmt_t(rem)
    elseif ptw_frac == nil then
      post_cd = FUNC.fmt_t(post_w_sec)  -- idle時顯示總時長 -- show total duration when idle
    end
    if post_cd ~= "" then
      ImGui.PushFont(ctx, FONT_MONO, FUNC.sz(14))
      post_cd_w, post_cd_h = ImGui.CalcTextSize(ctx, post_cd, 0, 0)
      ImGui.PopFont(ctx)
    end
    local ptri_row_h = PP_TRI_SZ + PP_TRI_GAP  -- 三角形行高 -- triangle row height
    local pcd_row_h = (post_cd ~= "" and not post_collapsed) and (post_cd_h + 1) or 0
    local post_total_h = polh + pcd_row_h + ptri_row_h
    local post_ty0 = wy + (wh - post_total_h) / 2
    -- "Post" 逐字母反白 -- per-char invert for "Post"
    if polw < post_px - 4 then
      local plx0 = post_x + (post_px - polw) / 2
      local post_char_x = plx0
      for ci2 = 1, #post_label do
        local ch = post_label:sub(ci2, ci2)
        local chw = ImGui.CalcTextSize(ctx, ch, 0, 0)
        local ch_col = (ptw_frac and (post_char_x + chw * 0.5) <= post_fill_edge) and C.wf_bg or C.p_ptw
        ImGui.DrawList_AddText(dl, post_char_x, post_ty0, ch_col, ch)
        post_char_x = post_char_x + chw
      end
    end
    -- 倒數計時文字 -- countdown text
    if post_cd ~= "" and not post_collapsed and post_cd_w < post_px - 4 then
      ImGui.PushFont(ctx, FONT_MONO, FUNC.sz(14))
      local pcd_x = post_x + (post_px - post_cd_w) / 2
      local pcd_y = post_ty0 + polh + 1
      local pcd_char_x = pcd_x
      for ci2 = 1, #post_cd do
        local ch = post_cd:sub(ci2, ci2)
        local chw = ImGui.CalcTextSize(ctx, ch, 0, 0)
        local ch_col = (ptw_frac and (pcd_char_x + chw * 0.5) <= post_fill_edge) and C.wf_bg or C.p_ptw
        ImGui.DrawList_AddText(dl, pcd_char_x, pcd_y, ch_col, ch)
        pcd_char_x = pcd_char_x + chw
      end
      ImGui.PopFont(ctx)
    end
    ImGui.DrawList_AddRect(dl, post_x, wy, cx + cw, wy + wh, FUNC.dim_c(FUNC.rgba(60,60,80)), 4, 0, 1)
    -- 三角形在文字下方，左右指向變化方向 -- triangle below text, points toward change direction
    local ptri_h = PP_TRI_SZ * 0.5
    local plast_y = post_ty0 + polh + pcd_row_h + PP_TRI_GAP  -- "Post" + 倒數(若有) + 間距
    local ptri_cy = plast_y + ptri_h * 0.5
    local ptri_cx = post_x + post_px * 0.5
    local post_area_hov = ImGui.IsMouseHoveringRect(ctx, post_x, wy, cx + cw, wy + wh)
    -- 三角形反白：進度走過用wf_bg，未走過用p_ptw -- invert: filled=wf_bg, unfilled=p_ptw
    local ptri_filled = ptw_frac and (ptri_cx <= post_fill_edge)
    local ptri_base = ptri_filled and C.wf_bg or C.p_ptw
    local ptri_col = post_area_hov and (ptri_base | 0xFF) or ((ptri_base & 0xFFFFFF00) | 0x80)
    if post_collapsed then
      -- ◀ 指左（展開方向）-- ◀ points left (expand direction)
      ImGui.DrawList_AddTriangleFilled(dl, ptri_cx + ptri_h, ptri_cy - ptri_h, ptri_cx + ptri_h, ptri_cy + ptri_h, ptri_cx - ptri_h, ptri_cy, ptri_col)
    else
      -- ▶ 指右（收合方向）-- ▶ points right (collapse direction)
      ImGui.DrawList_AddTriangleFilled(dl, ptri_cx - ptri_h, ptri_cy - ptri_h, ptri_cx - ptri_h, ptri_cy + ptri_h, ptri_cx + ptri_h, ptri_cy, ptri_col)
    end
    -- 整個post區塊可點擊toggle -- entire post area clickable to toggle
    if post_area_hov and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left()) then
      pp_col[c.id.."_post"] = not post_collapsed
    end
  end

  -- 覆蓋cx/cw為波形區域 -- override cx/cw for waveform content area
  cx = wf_cx; cw = wf_cw

  -- 背景（顏色可自訂）-- waveform bg (customizable)
  ImGui.DrawList_AddRectFilled(dl, cx, wy, cx + cw, wy + wh, C.wf_bg, 4)

  -- Build/get cache（用zoom_target建cache，只在滾輪事件時重建，動畫中不重建）-- build at target zoom; only rebuilds on wheel events, not during lerp
  local cache_zoom = view.zoom_target or view.zoom
  local cache = FUNC.wf_build_cache(c, math.floor(cw * cache_zoom))
  if not cache or not cache.peaks or #cache.peaks == 0 then
    local ntxt = "No waveform data"
    -- 參考"Same Volume, No Fade"風格：大字粗體高不透明 -- match "Same Volume" style: big bold opaque
    ImGui.PushFont(ctx, FONT_B, FUNC.sz(26))
    local tw, th = ImGui.CalcTextSize(ctx, ntxt, 0, 0)
    ImGui.DrawList_AddTextEx(dl, FONT_B, FUNC.sz(26), cx + (cw - tw) / 2, wy + (wh - th) / 2, FUNC.dim_c(FUNC.rgba(130,130,140,200)), ntxt)
    ImGui.PopFont(ctx)
    return
  end

  local total_dur = cache.dur
  local peaks = cache.peaks
  local n_peaks = #peaks

  -- Trim values（用GROUP有效trim）-- use GROUP-effective trim
  local ts = eff_ts_gp
  local te = (eff_te_gp > 0) and eff_te_gp or total_dur

  -- View: visible portion
  local view_start = view.pos
  local view_dur = total_dur / view.zoom
  local view_end = view_start + view_dur

  -- Clamp view
  if view_start < 0 then view_start = 0; view.pos = 0 end
  if view_end > total_dur then
    view_start = math.max(0, total_dur - view_dur)
    view.pos = view_start
    view_end = view_start + view_dur
  end

  -- 時間軸刻度（波形底部，fade chart風格）-- time ruler below waveform (fade chart style)
  draw_time_ruler(dl, cx, wy + wh, cw, view_start, view_dur)

  -- Center Y (within content area)
  local mid_y = wy + wh / 2
  local half_h = wh / 2 * 0.9

  -- Gain + Normalize
  local gain_lin = FUNC.db2lin(c.volume)
  local norm_scale = 1
  if prefs.wf_normalize == 1 and cache.max_peak and cache.max_peak > 0 and half_h > 2 then
    norm_scale = (half_h - 2) / (cache.max_peak * gain_lin * half_h)  -- peak距離頂部2px -- 2px margin from top
  end
  local v_scale = view.v_zoom * gain_lin * norm_scale

  -- Draw waveform lines -- 畫波形線條（顏色從 Settings 讀取）
  local wr = (C.wf >> 24) & 0xFF
  local wg = (C.wf >> 16) & 0xFF
  local wb = (C.wf >> 8) & 0xFF
  local wf_col = FUNC.rgba(wr, wg, wb, 200)
  local wf_dim = FUNC.rgba(wr * 0.4, wg * 0.4, wb * 0.4, 100)
  local wf_played = FUNC.dim_c(FUNC.rgba(120, 120, 120, 150))  -- 播放過的波形灰色 -- played portion grey

  -- 計算播放頭時間位置（用於灰色判定）-- playhead time for grey coloring
  local playhead_t = nil
  if c.state == STATE.RUNNING and c.play_t0 > 0 then
    -- play cursor用播放時的trim_start(play_offset)，不跟隨目前的trim拖曳
    local play_ts = c.play_offset or ts
    local cue_rate = (c.rate and c.rate > 0) and c.rate or 1.0
    playhead_t = play_ts + (reaper.time_precise() - c.play_t0) * cue_rate  -- 乘以rate：rate>1時source走更快 -- multiply by rate for correct source position
  end

  for px = 0, cw - 1 do
    local t = view_start + (px / cw) * view_dur
    local pi = math.floor(t / total_dur * n_peaks) + 1
    if pi < 1 then pi = 1 end
    if pi > n_peaks then pi = n_peaks end
    local pk = peaks[pi]
    if pk then
      local mn = pk[1] * v_scale
      local mx = pk[2] * v_scale
      local y1 = mid_y - mx * half_h
      local y2 = mid_y - mn * half_h
      y1 = math.max(wy, math.min(wy + wh, y1))
      y2 = math.max(wy, math.min(wy + wh, y2))
      local in_trim = (t >= ts and t <= te)
      local col
      -- 播放中且在trim內且已播過 → 灰色 -- played portion shows grey
      if playhead_t and in_trim and t < playhead_t then
        col = wf_played
      else
        col = in_trim and FUNC.dim_c(wf_col) or FUNC.dim_c(wf_dim)
      end
      if math.abs(y2 - y1) < 1 then
        ImGui.DrawList_AddLine(dl, cx + px, mid_y, cx + px, mid_y + 1, col, 1)
      else
        ImGui.DrawList_AddLine(dl, cx + px, y1, cx + px, y2, col, 1)
      end
    end
  end

  -- Center line (0dB reference) -- 0dB中線
  ImGui.DrawList_AddLine(dl, cx, mid_y, cx + cw, mid_y, FUNC.rgba(255, 255, 255, 30), 1)

  -- Trim positions in pixels
  local trim_s_x = cx + ((ts - view_start) / view_dur) * cw
  local trim_e_x = cx + ((te - view_start) / view_dur) * cw

  -- Dim overlay for out-of-trim -- trim外暗化
  if trim_s_x > cx then
    ImGui.DrawList_AddRectFilled(dl, cx, wy, math.min(trim_s_x, cx + cw), wy + wh, FUNC.rgba(0, 0, 0, 100))
  end
  if trim_e_x < cx + cw then
    ImGui.DrawList_AddRectFilled(dl, math.max(trim_e_x, cx), wy, cx + cw, wy + wh, FUNC.rgba(0, 0, 0, 100))
  end

  -- Handle styling -- 把手樣式
  local tab_w = FUNC.sz(12)
  local tab_h = tab_h_val  -- 用上面統一的高度
  local handle_col = FUNC.dim_c(C.trim)
  local handle_hover_col = FUNC.dim_c(FUNC.rgba(255, 200, 100))
  local guide_col = FUNC.dim_c(FUNC.rgba(wr, wg, wb, 80))

  -- Start handle: 突出到waveform上方 -- 起點把手(上方突出到waveform外)
  local s_vis = trim_s_x >= cx - tab_w and trim_s_x <= cx + cw + tab_w
  if s_vis then
    local s_x1, s_x2 = trim_s_x - tab_w / 2, trim_s_x + tab_w / 2
    local s_y1 = wy - tab_h  -- tab 完全在 waveform 上方
    local s_y2 = wy          -- tab 底部齊 waveform 頂部
    local hov_s = ImGui.IsMouseHoveringRect(ctx, s_x1 - 2, s_y1, s_x2 + 2, s_y2)
    local hcol = (hov_s or wf_handle.dragging == "start") and handle_hover_col or handle_col
    ImGui.DrawList_AddRectFilled(dl, s_x1, s_y1, s_x2, s_y2, hcol, 2)
    -- guide line 從 tab 底部到 waveform 底部
    ImGui.DrawList_AddLine(dl, trim_s_x, wy, trim_s_x, wy + wh, guide_col, 1)
    -- handle timecode 暫時隱藏（改用底部ruler）-- handle timecode hidden (using bottom ruler instead)
  end

  -- End handle: 突出到waveform下方 -- 終點把手(下方突出到waveform外)
  local e_vis = trim_e_x >= cx - tab_w and trim_e_x <= cx + cw + tab_w
  if e_vis then
    local e_x1, e_x2 = trim_e_x - tab_w / 2, trim_e_x + tab_w / 2
    local e_y1 = wy + wh      -- tab 頂部齊 waveform 底部
    local e_y2 = wy + wh + tab_h  -- tab 完全在 waveform 下方
    local hov_e = ImGui.IsMouseHoveringRect(ctx, e_x1 - 2, e_y1, e_x2 + 2, e_y2)
    local hcol = (hov_e or wf_handle.dragging == "end") and handle_hover_col or handle_col
    ImGui.DrawList_AddRectFilled(dl, e_x1, e_y1, e_x2, e_y2, hcol, 2)
    -- guide line 從 waveform 頂部到 tab 頂部
    ImGui.DrawList_AddLine(dl, trim_e_x, wy, trim_e_x, wy + wh, guide_col, 1)
    -- handle timecode 暫時隱藏（改用底部ruler）-- handle timecode hidden (using bottom ruler instead)
  end

  -- Vertical zoom handle (inside rectangle, right side) -- 垂直縮放把手在矩形內右側
  local gain_y = mid_y
  local gain_handle_h = FUNC.sz(14)
  local gain_handle_w = FUNC.sz(8)
  local gain_x = cx + cw - gain_handle_w - FUNC.sz(3)  -- 矩形內右側 -- inside right edge
  local gain_hov = ImGui.IsMouseHoveringRect(ctx, gain_x - 2, gain_y - gain_handle_h / 2, gain_x + gain_handle_w + 2, gain_y + gain_handle_h / 2)
  local gain_col = (gain_hov or wf_handle.dragging == "gain") and handle_hover_col or FUNC.dim_c(FUNC.rgba(100, 200, 100))
  ImGui.DrawList_AddRectFilled(dl, gain_x, gain_y - gain_handle_h / 2, gain_x + gain_handle_w, gain_y + gain_handle_h / 2, gain_col, 2)
  local eff_vzoom = view.v_zoom * norm_scale  -- 顯示含normalize的等效倍率 -- show effective zoom including normalize
  local vz_txt = string.format("%.1fx", eff_vzoom)
  local vz_tw = ImGui.CalcTextSize(ctx, vz_txt, 0, 0)
  local _, vz_th = ImGui.CalcTextSize(ctx, vz_txt, 0, 0)
  ImGui.DrawList_AddText(dl, gain_x - vz_tw - FUNC.sz(3), gain_y - vz_th / 2, FUNC.dim_c(C.text), vz_txt)  -- 文字垂直對齊中線 -- vertically centered on baseline

  -- 播放頭白線（不需勾Env.也顯示）-- playhead line always visible during playback
  if c.state == STATE.RUNNING and c.play_t0 > 0 then
    local elapsed = reaper.time_precise() - c.play_t0
    local cue_rate2 = (c.rate and c.rate > 0) and c.rate or 1.0
    local ph_t = (c.play_offset or ts) + elapsed * cue_rate2  -- 乘以rate+用播放時的trim_start -- multiply by rate, use play-time trim_start
    local ph_x = cx + ((ph_t - view_start) / view_dur) * cw
    if ph_x >= cx and ph_x <= cx + cw then
      ImGui.DrawList_AddLine(dl, ph_x, wy, ph_x, wy + wh, FUNC.rgba(255,255,255,180), 1.5)
      ImGui.DrawList_AddTriangleFilled(dl, ph_x - 4, wy, ph_x + 4, wy, ph_x, wy + 6, FUNC.rgba(255,255,255,200))
    end
  end

  -- Border移到caller統一處理（env active用彩色，否則用灰色）-- border now drawn by caller for env-aware coloring

  -- 儲存佈局資訊給 envelope 疊加用 -- store layout info for envelope overlay
  local wf_info = {cx=cx, wy=wy, cw=cw, wh=wh,
    view_start=view_start, view_dur=view_dur, total_dur=total_dur,
    trim_start=ts, trim_end=te}

  -- === INTERACTION === -- 互動處理
  local mx, my = ImGui.GetMousePos(ctx)
  local in_area = mx >= cx and mx <= cx + cw and my >= cy and my <= cy + ch
  local skip_input = false  -- A4: drag/pan 中略過後續 input 但保留繪製 -- skip input, keep drawing during drag/pan

  -- Handle dragging (active) -- 拖曳中
  if wf_handle.dragging then
    if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left()) then
      local dx, dy = ImGui.GetMouseDelta(ctx)
      local mx_abs = ImGui.GetMousePos(ctx)
      local mt = view_start + (mx_abs - cx) / cw * view_dur  -- 滑鼠絕對 x → 時間 -- absolute mouse x → time
      if wf_handle.dragging == "start" then
        -- GROUP trim 投射出的下限：child 只能比 GROUP trim 更往內，不能退出窗口
        -- lower bound imposed by parent GROUP trim: child can only tighten, not loosen
        local min_ts = FUNC.get_group_trim_bounds and (FUNC.get_group_trim_bounds(c)) or 0
        c.trim_start = FUNC.clamp(mt, min_ts, te - 0.01)
        -- 拖曳handle時即時更新eff_dur讓進度條同步 -- update eff_dur so progress bar updates
        local new_te = (c.trim_end and c.trim_end > 0) and c.trim_end or total_dur
        local cr = (c.rate and c.rate > 0) and c.rate or 1.0
        c.eff_dur = (new_te - c.trim_start) / cr
        -- 對齊 GROUP 行為：trim_start 超過 playhead → 推著 cursor 走 (replay 從新位置)
        -- mirror GROUP: when trim_start passes playhead, push cursor by replaying at new position
        if c.state == STATE.RUNNING and c.play_t0 > 0 then
          local play_ts = c.play_offset or 0
          local cr2 = (c.rate and c.rate > 0) and c.rate or 1.0
          local ph_t = play_ts + (reaper.time_precise() - c.play_t0) * cr2
          if c.trim_start >= new_te then
            FUNC.kill_cue(c)
          elseif c.trim_start > ph_t then
            -- Bug 6: 若此 child 屬於有 trim 的 GROUP，重播時要保留 parent trim 上下文
            if FUNC.apply_parent_group_trim then FUNC.apply_parent_group_trim(c) end
            FUNC.play_cue(c)
          end
        end
      elseif wf_handle.dragging == "end" then
        -- GROUP trim 投射出的上限：child 只能更早收，不能延伸過 GROUP 窗口
        -- upper bound imposed by parent GROUP trim: child can only end earlier, not later
        local max_te = nil
        if FUNC.get_group_trim_bounds then
          local _; _, max_te = FUNC.get_group_trim_bounds(c)
        end
        local up = max_te or total_dur
        c.trim_end = FUNC.clamp(mt, ts + 0.01, up)
        -- 拖曳handle時即時更新eff_dur讓進度條同步 -- update eff_dur so progress bar updates
        local cr = (c.rate and c.rate > 0) and c.rate or 1.0
        c.eff_dur = (c.trim_end - (c.trim_start or 0)) / cr
        -- end handle 碰到 playhead：有 loop 則開下一輪，否則 kill
        -- end touches playhead: restart if looping, else kill
        if c.state == STATE.RUNNING and c.play_t0 > 0 then
          local play_ts = c.play_offset or 0
          local cr2 = (c.rate and c.rate > 0) and c.rate or 1.0
          local ph_t = play_ts + (reaper.time_precise() - c.play_t0) * cr2
          -- loop 由 cleanup 用絕對 ph 比對處理；這裡只處理非 loop 立即 kill
          -- loop is handled by cleanup via absolute ph compare; here only non-loop immediate kill
          if c.trim_end <= ph_t and not c.loop then
            FUNC.kill_cue(c)
          end
        end
      elseif wf_handle.dragging == "gain" then
        -- 改為垂直縮放波形 -- v_zoom instead of volume
        local zd = -dy * 0.02
        if ImGui.IsKeyDown(ctx, ImGui.Mod_Shift()) then zd = zd * 0.2 end
        view.v_zoom = FUNC.clamp(view.v_zoom + zd, 0.1, 12)
      end
    else
      wf_handle.dragging = nil
      FUNC.save_cues()
    end
    skip_input = true
  end

  -- Double-click reset / single-click drag -- 雙擊重置/單擊拖曳
  if not skip_input and in_area then
    -- hover 判定配合新的突出 tab 位置 -- handle hover區域對齊突出tab
    local hov_s = s_vis and math.abs(mx - trim_s_x) <= tab_w and my >= wy - tab_h and my <= wy + FUNC.sz(4)
    local hov_e = e_vis and math.abs(mx - trim_e_x) <= tab_w and my >= wy + wh - FUNC.sz(4) and my <= wy + wh + tab_h
    local hov_g = mx >= gain_x - 2 and mx <= gain_x + gain_handle_w + 2 and math.abs(my - gain_y) <= gain_handle_h  -- handle在矩形內右側 -- handle inside right edge

    if ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left()) then
      -- Double-click reset -- 雙擊歸零
      if hov_s then c.trim_start = 0; FUNC.save_cues(); wf_handle.dragging = nil
      elseif hov_e then c.trim_end = total_dur; FUNC.save_cues(); wf_handle.dragging = nil
      elseif hov_g then view.v_zoom = 1; wf_handle.dragging = nil  -- v_zoom=1即normalize預設 -- v_zoom=1 IS the normalize default
      end
    elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left()) and not env_drag.active and not env_drag.marquee and not env_drag.pending then
      -- 判斷是否有active envelope（有的話不啟動waveform範圍選取） -- check if any envelope is actively edited
      local has_active_env = (env_edit_mode == "vol" and c.env_enabled)
                          or (env_edit_mode == "pan" and c.pan_env_enabled)
                          or (env_edit_mode == "fx" and fx_env_edit_idx and c.fx_envs and c.fx_envs[fx_env_edit_idx])
      -- trim handle / gain handle 優先於 envelope point（tab 突出在 chart 外，空間不重疊；env_draw 內已用 wf_handle.dragging 退讓）
      -- trim/gain handles take priority over envelope (tabs sit outside chart, no spatial overlap; env_draw yields via wf_handle.dragging guard)
      if hov_s then wf_handle.dragging = "start"; FUNC.push_undo()
      elseif hov_e then wf_handle.dragging = "end"; FUNC.push_undo()
      elseif hov_g then wf_handle.dragging = "gain"  -- v_zoom不需undo
      elseif not has_active_env then
        -- 空白區域：開始選取範圍 -- empty area: start range selection
        local click_t = view_start + ((mx - cx) / cw) * view_dur
        FUNC.wf_sel_stop()  -- 停止之前的preview -- stop previous preview
        wf_sel.cid = cid; wf_sel.t0 = click_t; wf_sel.t1 = click_t; wf_sel.dragging = true
      end
    end
  end

  -- Right-click drag: pan -- 右鍵拖曳平移
  -- envelope 編輯框開啟中不啟動平移 -- skip pan if envelope edit box is open
  -- marker右鍵hover時不啟動pan（讓popup優先） -- skip pan when marker is hovered for right-click
  local mk_rclick_block = false
  local mk_markers = c.markers or {}
  local mk_tri_pre = FUNC.sz(5)
  local mk_y_pre = wy - FUNC.sz(2)
  for _, mt in ipairs(mk_markers) do
    if mt >= view_start and mt <= view_end then
      local mk_x_pre = cx + ((mt - view_start) / view_dur) * cw
      ImGui.PushFont(ctx, FONT_MONO, FUNC.sz(9))
      local _, mk_th_pre = ImGui.CalcTextSize(ctx, "0:00.0", 0, 0)
      ImGui.PopFont(ctx)
      if ImGui.IsMouseHoveringRect(ctx, mk_x_pre - mk_tri_pre - 2, mk_y_pre - mk_tri_pre*2 - mk_th_pre - 2, mk_x_pre + mk_tri_pre + 2, mk_y_pre + 1) then
        mk_rclick_block = true; break
      end
    end
  end
  -- marker popup開啟中也不啟動pan -- skip pan when marker popup is open
  if wf_markers._rclick and wf_markers._rclick.cue == c then mk_rclick_block = true end
  if in_area and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right()) and not env_drag.edit_idx and not mk_rclick_block then
    wf_drag.active = true
    wf_drag.start_x = mx
    wf_drag.start_pos = view.pos
    view.anchor_t = nil  -- 右鍵拖曳時清除zoom anchor -- clear zoom anchor on pan drag
  end
  if wf_drag.active then
    if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Right()) then
      local dx = mx - wf_drag.start_x
      local dt = -(dx / cw) * view_dur
      view.pos = FUNC.clamp(wf_drag.start_pos + dt, 0, math.max(0, total_dur - view_dur))
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_Hand())
    else
      wf_drag.active = false
    end
    skip_input = true  -- A4: 平移中也保留 M/L/zoom/guide 繪製 -- keep drawing during pan
  end

  -- 滾輪：依wf_wheel設定判斷modifier組合（優先匹配更多modifier的動作）-- wheel: priority match by modifier count
  -- Shift+wheel在ImGui會轉為水平滾輪，所以兩個都要讀 -- Shift+wheel becomes horizontal wheel in ImGui
  if not skip_input and in_area then
    local wheel_v, wheel_h = ImGui.GetMouseWheel(ctx)
    local wheel = wheel_v ~= 0 and wheel_v or wheel_h  -- Shift+wheel→horizontal in ImGui
    if wheel ~= 0 then
      local hs = ImGui.IsKeyDown(ctx, ImGui.Mod_Shift()) and true or false
      local hc = ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl()) and true or false
      local ha = ImGui.IsKeyDown(ctx, ImGui.Mod_Alt()) and true or false
      local action, best_n, do_rev = "scroll", -1, false  -- fallback=scroll
      if wf_wheel then
        for _, wd in ipairs(WF_WHEEL_DEFS) do
          local w = wf_wheel[wd.id]
          if w then
            -- checkbox=true代表「必須按住」，false代表「不在意」-- true=required, false=don't care
            local ok = true
            if w.shift and not hs then ok = false end
            if w.ctrl and not hc then ok = false end
            if w.alt and not ha then ok = false end
            if ok then
              local n = (w.shift and 1 or 0) + (w.ctrl and 1 or 0) + (w.alt and 1 or 0)
              if n > best_n then best_n = n; action = wd.id; do_rev = w.rev end
            end
          end
        end
      end
      if do_rev then wheel = -wheel end
      if action == "vzoom" then
        local vzt = view.vz_target or view.v_zoom
        if wheel > 0 then view.vz_target = math.min(vzt * 1.2, 12)
        else view.vz_target = math.max(vzt / 1.2, 0.1) end
      elseif action == "hzoom" then
        -- 用當前渲染值計算游標下方的時間（而非target值，避免動畫中不同步導致漂移）
        -- use current rendered values for mouse_t (not targets, which desync during animation)
        local mouse_t = view.pos + ((mx - cx) / cw) * (total_dur / view.zoom)
        local frac = (mx - cx) / cw
        local zt = view.zoom_target or view.zoom
        if wheel > 0 then view.zoom_target = math.min(zt * 1.25, 200)
        else view.zoom_target = math.max(zt / 1.25, 1) end
        -- 設定anchor讓get_view從zoom推導pos -- set anchor so get_view derives pos from zoom
        view.anchor_t = mouse_t
        view.anchor_frac = frac
        view.anchor_total_dur = total_dur
      else
        view.anchor_t = nil  -- scroll時清除anchor -- clear anchor on scroll
        local scroll_amt = -wheel * view_dur * 0.1
        view.pos_target = FUNC.clamp((view.pos_target or view.pos) + scroll_amt, 0, math.max(0, total_dur - view_dur))
      end
    end
  end

  -- === GUIDE LINE + RANGE SELECTION === -- 指引線+選取範圍
  local guide_col = FUNC.dim_c(C.guide or FUNC.rgba(224, 224, 240))
  -- envelope編輯啟動時取消selection -- cancel selection if envelope drag started
  if wf_sel.dragging and env_drag.active then
    wf_sel.dragging = false; wf_sel.t0 = nil; wf_sel.t1 = nil; wf_sel.cid = nil
  end
  -- 拖曳中：更新選取範圍（放開只結束拖曳，不自動播放）-- dragging: update range, release just commits
  if wf_sel.dragging and wf_sel.cid == cid then
    if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left()) then
      wf_sel.t1 = view_start + ((mx - cx) / cw) * view_dur
    else
      wf_sel.dragging = false
      local s0 = math.min(wf_sel.t0, wf_sel.t1)
      local s1 = math.max(wf_sel.t0, wf_sel.t1)
      if s1 - s0 <= 0.02 then  -- 太短→轉為 edit cursor -- too short → promote to edit cursor
        c._edit_cursor_t = s0
        wf_sel.t0 = nil; wf_sel.t1 = nil; wf_sel.cid = nil
      else
        c._edit_cursor_t = nil  -- 拖出範圍 → 清舊 cursor -- real range committed → clear cursor
      end
    end
  end
  -- 繪製選取範圍高亮 -- draw selection range highlight
  if wf_sel.cid == cid and wf_sel.t0 and wf_sel.t1 then
    local s0 = math.min(wf_sel.t0, wf_sel.t1)
    local s1 = math.max(wf_sel.t0, wf_sel.t1)
    local sx0 = cx + ((s0 - view_start) / view_dur) * cw
    local sx1 = cx + ((s1 - view_start) / view_dur) * cw
    sx0 = math.max(cx, math.min(sx0, cx + cw))
    sx1 = math.max(cx, math.min(sx1, cx + cw))
    if sx1 - sx0 > 1 then
      ImGui.DrawList_AddRectFilled(dl, sx0, wy, sx1, wy + wh, FUNC.dim_c(FUNC.col2im(prefs.col_guide or 0x00E0E0F0, 40)))
      ImGui.DrawList_AddLine(dl, sx0, wy, sx0, wy + wh, guide_col, 1)
      ImGui.DrawList_AddLine(dl, sx1, wy, sx1, wy + wh, guide_col, 1)
    end
    -- preview播放頭 -- preview play cursor
    if wf_sel.play_t0 and wf_sel.preview_ids and #wf_sel.preview_ids > 0 then
      local cue_rate = (c.rate and c.rate > 0) and c.rate or 1.0
      local elapsed = (reaper.time_precise() - wf_sel.play_t0) * cue_rate
      local ph_t = s0 + elapsed
      if ph_t >= s0 and ph_t <= s1 then
        local ph_x = cx + ((ph_t - view_start) / view_dur) * cw
        if ph_x >= cx and ph_x <= cx + cw then
          ImGui.DrawList_AddLine(dl, ph_x, wy, ph_x, wy + wh, guide_col, 2)
          -- 播放頭三角形 -- playhead triangle
          local tri_sz = FUNC.sz(5)
          ImGui.DrawList_AddTriangleFilled(dl, ph_x - tri_sz, wy - tri_sz, ph_x + tri_sz, wy - tri_sz, ph_x, wy, guide_col)
        end
      else
        -- 播完→停止preview -- finished → stop preview
        for _,pid in ipairs(wf_sel.preview_ids) do FUNC.pv_stop(pid) end
        wf_sel.preview_ids = nil; wf_sel.play_t0 = nil
      end
    end
    -- 選取範圍長度：矩形下邊外面，選取範圍置中 -- selection duration below waveform, centered on selection
    local sel_dur = s1 - s0
    local dur_m = math.floor(sel_dur / 60)
    local dur_s = sel_dur - dur_m * 60
    local dur_label = sel_dur < 1 and string.format("%.2fs", sel_dur)
      or dur_m > 0 and string.format("%d:%04.1f", dur_m, dur_s)
      or string.format("%.1fs", dur_s)
    ImGui.PushFont(ctx, FONT_MONO, FUNC.sz(10))
    local dur_tw, dur_th = ImGui.CalcTextSize(ctx, dur_label, 0, 0)
    local sel_cx = (sx0 + sx1) / 2  -- 選取範圍中心 -- selection center
    local dur_x = math.max(cx, math.min(sel_cx - dur_tw / 2, cx + cw - dur_tw))
    ImGui.DrawList_AddText(dl, dur_x, wy + wh + FUNC.sz(2), guide_col, dur_label)
    ImGui.PopFont(ctx)
  end
  -- Edit cursor：1Hz 閃爍黃線（同 midi_editor 風格）-- blinking yellow edit cursor (same as midi_editor)
  if c._edit_cursor_t and c._edit_cursor_t >= view_start and c._edit_cursor_t <= view_end then
    local ec_x = cx + ((c._edit_cursor_t - view_start) / view_dur) * cw
    local phase = reaper.time_precise() % 1.0
    local alpha = (phase < 0.6) and 220 or 90
    local ec_col = FUNC.rgba(255, 220, 60, alpha)
    ImGui.DrawList_AddLine(dl, ec_x, wy, ec_x, wy + wh, ec_col, 2)
    ImGui.DrawList_AddTriangleFilled(dl, ec_x - FUNC.sz(4), wy - FUNC.sz(6),
                                          ec_x + FUNC.sz(4), wy - FUNC.sz(6),
                                          ec_x,              wy, ec_col)
  end
  -- 指引線+timecode：hover時在滑鼠位置畫垂直線 -- guide line + timecode at mouse position
  -- A4: drag/pan時也顯示 -- show during drag/pan too
  if in_area then
    ImGui.DrawList_AddLine(dl, mx, wy, mx, wy + wh, guide_col, 1)
    -- timecode在矩形上邊外面 -- timecode above waveform rectangle
    local mouse_t = view_start + ((mx - cx) / cw) * view_dur
    local m_tc = math.floor(mouse_t / 60)
    local s_tc = mouse_t - m_tc * 60
    local tc_label = string.format("%d:%04.1f", m_tc, s_tc)
    ImGui.PushFont(ctx, FONT_MONO, FUNC.sz(10))
    local tc_tw, tc_th = ImGui.CalcTextSize(ctx, tc_label, 0, 0)
    local tc_x = math.max(cx, math.min(mx - tc_tw / 2, cx + cw - tc_tw))
    ImGui.DrawList_AddText(dl, tc_x, wy - tc_th - FUNC.sz(2), guide_col, tc_label)
    ImGui.PopFont(ctx)
  end

  -- === MARKERS === -- 時間標記（儲存在c.markers）
  local markers = c.markers or {}
  local mk_tri = FUNC.sz(5)  -- marker三角形大小 -- marker triangle size
  local mk_y = wy - FUNC.sz(2)  -- ruler上方 -- above ruler
  for mi, mt in ipairs(markers) do
    if mt >= view_start and mt <= view_end then
      local mk_x = cx + ((mt - view_start) / view_dur) * cw
      -- 繪製角標三角形（朝下）-- downward triangle marker
      ImGui.DrawList_AddTriangleFilled(dl,
        mk_x - mk_tri, mk_y - mk_tri * 2,
        mk_x + mk_tri, mk_y - mk_tri * 2,
        mk_x, mk_y, FUNC.dim_c(FUNC.rgba(255, 160, 60, 220)))
      -- timecode在三角形上方 -- timecode above triangle
      ImGui.PushFont(ctx, FONT_MONO, FUNC.sz(9))
      local mk_label = FUNC.fmt_t(mt)
      local mk_tw, mk_th = ImGui.CalcTextSize(ctx, mk_label, 0, 0)
      local mk_lx = FUNC.clamp(mk_x - mk_tw / 2, cx, cx + cw - mk_tw)
      ImGui.DrawList_AddText(dl, mk_lx, mk_y - mk_tri * 2 - mk_th - 1, FUNC.dim_c(FUNC.rgba(255, 180, 80, 200)), mk_label)
      ImGui.PopFont(ctx)
      local mk_hov = ImGui.IsMouseHoveringRect(ctx, mk_x - mk_tri - 2, mk_y - mk_tri * 2 - mk_th - 2, mk_x + mk_tri + 2, mk_y + 1)
      -- Opt+左鍵刪除 -- Alt+click to delete
      if mk_hov and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left()) and ImGui.IsKeyDown(ctx, ImGui.Mod_Alt()) then
        table.remove(markers, mi); c.markers = markers; FUNC.save_cues(); break
      end
      -- 右鍵選單 -- right-click context menu
      if mk_hov and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right()) then
        wf_markers._rclick = {cue=c, mi=mi, mt=mt, id="##mk_ctx_"..c.id}
        ImGui.OpenPopup(ctx, wf_markers._rclick.id)
      end
    end
  end
  -- marker右鍵popup（在marker loop外渲染避免popup被loop影響） -- render popup outside loop
  if wf_markers._rclick and wf_markers._rclick.cue == c then
    local rc = wf_markers._rclick
    if ImGui.BeginPopup(ctx, rc.id) then
      -- 1. Set Trim Start
      if ImGui.Selectable(ctx, "Set Trim Start") then
        c.trim_start = rc.mt; FUNC.save_cues()
      end
      -- 2. Set Trim End
      if ImGui.Selectable(ctx, "Set Trim End") then
        c.trim_end = rc.mt; FUNC.save_cues()
      end
      ImGui.Separator(ctx)
      -- 3. Preview from here
      if ImGui.Selectable(ctx, "Preview from Here") then
        -- 用臨時trim start播放 -- play with temporary trim start
        local orig_ts = c.trim_start
        c.trim_start = rc.mt
        local ci_idx = nil
        for i, q in ipairs(cues) do if q == c then ci_idx = i; break end end
        if ci_idx then FUNC.exec_cue(ci_idx) end
        c.trim_start = orig_ts
      end
      ImGui.Separator(ctx)
      -- 4. Copy Timecode
      if ImGui.Selectable(ctx, "Copy Timecode") then
        ImGui.SetClipboardText(ctx, FUNC.fmt_t(rc.mt))
      end
      ImGui.Separator(ctx)
      -- 5. Delete Marker
      if ImGui.Selectable(ctx, "Delete Marker") then
        if rc.mi >= 1 and rc.mi <= #(c.markers or {}) then
          table.remove(c.markers, rc.mi); FUNC.save_cues()
        end
      end
      ImGui.Separator(ctx)
      -- 6. Insert Env Point (active envelope)
      local has_env = (env_edit_mode == "vol" and c.env_enabled) or (env_edit_mode == "pan" and c.pan_env_enabled)
      if has_env then
        local env_label = env_edit_mode == "vol" and "Insert Vol Env Point" or "Insert Pan Env Point"
        if ImGui.Selectable(ctx, env_label) then
          if env_edit_mode == "vol" then
            local v = FUNC.env_interp(c.env_points, rc.mt)
            FUNC.env_add_point(c, rc.mt, v)
          else
            local pts = c.pan_env_points or {}
            local v = FUNC.env_interp(pts, rc.mt)
            if not c.pan_env_points then c.pan_env_points = {} end
            c.pan_env_points[#c.pan_env_points + 1] = {t = rc.mt, v = FUNC.clamp(v, PAN_ENV_MIN, PAN_ENV_MAX)}
            FUNC.env_sort(c.pan_env_points)
          end
          FUNC.save_cues()
        end
      else
        ImGui.PushStyleColor(ctx, ImGui.Col_Text(), FUNC.rgba(80, 80, 90))
        ImGui.Selectable(ctx, "Insert Env Point", false, ImGui.SelectableFlags_Disabled())
        ImGui.PopStyleColor(ctx, 1)
      end
      ImGui.EndPopup(ctx)
    else
      wf_markers._rclick = nil  -- popup關閉時清除 -- clear on popup close
    end
  end

  -- === MARKER + LOCATE BUTTONS === -- 右上角marker/locate按鈕
  local mbtn_sz = FUNC.sz(16)
  local mbtn_gap = FUNC.sz(3)
  -- 與trim start handle timecode同水平，置右 -- same Y as trim start timecode, right-aligned
  local mbtn_y = wy - tab_h_val - FUNC.sz(4)
  local loc_x = cx + cw - mbtn_sz  -- locate在最右 -- locate rightmost
  local mk_btn_x = loc_x - mbtn_sz - mbtn_gap  -- marker在locate左邊 -- marker left of locate

  local function wf_btn(bx, by, label, col_n, col_h, enabled)
    local bhov = ImGui.IsMouseHoveringRect(ctx, bx, by, bx + mbtn_sz, by + mbtn_sz)
    local bcol = (bhov and enabled) and col_h or (enabled and col_n or FUNC.rgba(40, 40, 50))
    ImGui.DrawList_AddRectFilled(dl, bx, by, bx + mbtn_sz, by + mbtn_sz, FUNC.dim_c(bcol), 3)
    local ltw, lth = ImGui.CalcTextSize(ctx, label, 0, 0)
    local tcol = enabled and FUNC.dim_c(C.text) or FUNC.dim_c(FUNC.rgba(80, 80, 90))
    ImGui.DrawList_AddText(dl, bx + (mbtn_sz - ltw) / 2, by + (mbtn_sz - lth) / 2, tcol, label)
    if bhov and enabled and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left()) then return true end
    return false
  end

  local is_playing = (c.state == STATE.RUNNING and c.play_t0 > 0)
  -- Marker按鈕：播放中才有效 -- marker button: only active during playback
  if wf_btn(mk_btn_x, mbtn_y, "M", FUNC.rgba(60, 50, 30), FUNC.rgba(100, 80, 40), is_playing) then
    local cue_rate = (c.rate and c.rate > 0) and c.rate or 1.0
    local ph_t = (c.play_offset or ts) + (reaper.time_precise() - c.play_t0) * cue_rate
    if not c.markers then c.markers = {} end
    c.markers[#c.markers + 1] = ph_t
    table.sort(c.markers)
    FUNC.save_cues()
  end
  -- Locate按鈕：播放中才有效，定位playhead到畫面5%位置 -- locate: scroll to playhead at 5% of view
  if wf_btn(loc_x, mbtn_y, "L", FUNC.rgba(30, 50, 60), FUNC.rgba(40, 80, 100), is_playing) then
    local cue_rate = (c.rate and c.rate > 0) and c.rate or 1.0
    local ph_t = (c.play_offset or ts) + (reaper.time_precise() - c.play_t0) * cue_rate
    local target_pos = ph_t - view_dur * 0.05  -- playhead在畫面5%位置 -- playhead at 5% of view
    view.pos_target = FUNC.clamp(target_pos, 0, math.max(0, total_dur - view_dur))
  end

  -- Zoom buttons (bottom-right) -- 縮放按鈕(縮小版)
  local btn_sz = FUNC.sz(16)
  local btn_gap = FUNC.sz(3)
  local btn_y = wy + wh - btn_sz - FUNC.sz(4)
  local btn_x_minus = cx + cw - btn_sz * 3 - btn_gap * 2 - FUNC.sz(4)
  local btn_x_reset = btn_x_minus + btn_sz + btn_gap
  local btn_x_plus = btn_x_reset + btn_sz + btn_gap

  local function zoom_btn(bx, by, label, col_n, col_h)
    local bhov = ImGui.IsMouseHoveringRect(ctx, bx, by, bx + btn_sz, by + btn_sz)
    local bcol = bhov and col_h or col_n
    ImGui.DrawList_AddRectFilled(dl, bx, by, bx + btn_sz, by + btn_sz, FUNC.dim_c(bcol), 3)
    local ltw, lth = ImGui.CalcTextSize(ctx, label, 0, 0)
    ImGui.DrawList_AddText(dl, bx + (btn_sz - ltw) / 2, by + (btn_sz - lth) / 2, FUNC.dim_c(C.text), label)
    if bhov and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left()) then return true end
    return false
  end

  if zoom_btn(btn_x_minus, btn_y, "-", FUNC.rgba(50, 50, 70), FUNC.rgba(70, 70, 100)) then
    view.zoom = math.max(view.zoom / 1.5, 1); FUNC.wf_invalidate(cid)
  end
  if zoom_btn(btn_x_reset, btn_y, "R", FUNC.rgba(50, 50, 70), FUNC.rgba(70, 70, 100)) then
    view.zoom = 1; view.pos = 0; view.v_zoom = 1; FUNC.wf_invalidate(cid)
  end
  if zoom_btn(btn_x_plus, btn_y, "+", FUNC.rgba(50, 50, 70), FUNC.rgba(70, 70, 100)) then
    local center_t = view_start + view_dur / 2
    view.zoom = math.min(view.zoom * 1.5, 200)
    local new_vd = total_dur / view.zoom
    view.pos = FUNC.clamp(center_t - new_vd / 2, 0, math.max(0, total_dur - new_vd))
    FUNC.wf_invalidate(cid)
  end

  return wf_info  -- 回傳佈局資訊 -- return layout info for envelope overlay
end

---------------------------------------------------------------------
-- GROUP LANE ANALYSIS -- GROUP 並聯/串聯分析
---------------------------------------------------------------------
-- auto_go的children串聯成同一lane，否則開新lane（並聯）
-- C10 絕對 timecode 模型：每個 lane 第一個 entry 的 trim 形成 lane.prefix（負時間視覺前綴）
-- 全 group 視覺總長 = max(lane.prefix) + max(lane.dur_pos)
-- Returns: {lanes={lane1, ...}, dur=prefix+dur_pos, prefix, dur_pos}
-- Each lane: {entries={...}, dur=lane positive dur, prefix=first-entry trim seconds}
-- Each entry: {cue, idx, eff_dur, pre, post, entry_dur, offset, raw_dur, trim_s}
function FUNC.group_lanes(gc, _visited)
  if not gc or gc.type ~= "GROUP" or not gc.children or #gc.children == 0 then
    return {lanes={}, dur=0, prefix=0, dur_pos=0}
  end
  -- visited 守衛：防止 cyclic GROUP nesting (A→B→A) 無限遞迴；與 calc_group_dur / wf_build_group_peaks 一致
  -- prevent cyclic recursion, mirrors engine.calc_group_dur and wf_build_group_peaks
  _visited = _visited or {}
  if _visited[gc.id] then return {lanes={}, dur=0, prefix=0, dur_pos=0} end
  _visited[gc.id] = true
  local lanes = {}
  local cur = nil
  for k, ci in ipairs(gc.children) do
    local c = cues[ci]
    if not c then goto skip_gl end
    if c == gc then goto skip_gl end  -- 防止自引用循環 -- prevent self-reference cycle
    local eff = 0
    local raw = 0
    local trim_s = 0  -- 視覺 trim 前綴（秒，post-rate）-- visual trim prefix in seconds
    if c.type == "PLAY" then
      raw = FUNC.calc_dur(c.track_idx)
      local ts = c.trim_start or 0
      local te = (c.trim_end and c.trim_end > 0) and c.trim_end or raw
      local cr = (c.rate and c.rate > 0) and c.rate or 1.0
      eff = math.max(0, (te - ts) / cr)
      trim_s = ts / cr
    elseif c.type == "GROUP" then
      -- C10 #6 巢狀 group：自身 gc.trim_start/end 也視為負時段 (對齊 audio child trim 行為)
      -- own trim_start/end shrink positive eff and extend negative band, like audio child trim
      local sub = FUNC.group_lanes(c, _visited)
      local sub_dur = sub.dur_pos or 0
      local own_gts = c.trim_start or 0
      local own_gte = (c.trim_end and c.trim_end > 0) and c.trim_end or sub_dur
      eff = math.max(0, own_gte - own_gts)
      raw = (sub.prefix or 0) + sub_dur
      trim_s = (sub.prefix or 0) + own_gts
    elseif c.type == "FADE" then
      eff = c.fade_time or 0; raw = eff
    end
    local pre = c.pre_wait or 0
    local post = c.post_wait or 0
    local entry_dur = pre + eff + post
    -- 第一個child或沒有auto_go→開新lane -- first child or no auto_go → new lane
    local is_lane_first = (not cur) or (k > 1 and not c.auto_go)
    if is_lane_first then
      if cur then lanes[#lanes+1] = cur end
      cur = {entries={}, dur=0, prefix=trim_s}  -- 第一個 entry 的 trim → lane prefix
    end
    cur.entries[#cur.entries+1] = {
      cue = c, idx = ci,
      eff_dur = eff, raw_dur = raw,
      pre = pre, post = post,
      entry_dur = entry_dur,
      offset = cur.dur,
      trim_s = trim_s,
    }
    cur.dur = cur.dur + entry_dur
    ::skip_gl::
  end
  if cur and #cur.entries > 0 then lanes[#lanes+1] = cur end
  local max_dur_pos, max_prefix = 0, 0
  for _, l in ipairs(lanes) do
    if l.dur > max_dur_pos then max_dur_pos = l.dur end
    if (l.prefix or 0) > max_prefix then max_prefix = l.prefix end
  end
  _visited[gc.id] = nil  -- 退出本層後解封，允許同一 GROUP 在不同分支重新計算 -- unmark on exit
  return {lanes=lanes, dur=max_prefix + max_dur_pos, prefix=max_prefix, dur_pos=max_dur_pos}
end

---------------------------------------------------------------------
-- BUILD CONSOLIDATED GROUP PEAKS -- 巢狀GROUP疊合波形
---------------------------------------------------------------------
-- 遞迴建立GROUP的合併peaks（所有lane疊加取max）
-- _visited: 防止循環引用無限遞迴 -- visited set prevents circular recursion
function FUNC.wf_build_group_peaks(gc, width, _visited)
  if _visited and _visited[gc.id] then return nil end  -- 循環引用防護 -- circular ref guard
  local visited = _visited or {}
  visited[gc.id] = true  -- 標記已訪問 -- mark as visited
  local lane_info = FUNC.group_lanes(gc)
  if #lane_info.lanes == 0 or lane_info.dur <= 0 then return nil end
  local total_dur = lane_info.dur  -- 含視覺 prefix -- includes visual prefix
  local gprefix = lane_info.prefix or 0
  -- 初始化 merged peaks -- init merged peaks
  local merged = {}
  for i = 1, width do merged[i] = {0, 0} end

  for _, lane in ipairs(lane_info.lanes) do
    for _, entry in ipairs(lane.entries) do
      local c = entry.cue
      -- 虛擬座標 = gprefix + lane positive -- virtual coord
      local audio_start = gprefix + entry.offset + entry.pre
      local eff_dur = entry.eff_dur
      if eff_dur <= 0 then goto skip_grp_pk end
      -- 取得此entry的peaks -- get peaks for this entry
      local ep, ep_dur
      if c.type == "PLAY" then
        local cache = FUNC.wf_build_cache(c, width)
        if cache then ep = cache.peaks; ep_dur = cache.dur end
      elseif c.type == "GROUP" then
        local gp = FUNC.wf_build_group_peaks(c, width, visited)  -- 遞迴+visited防護 -- recursive with visited guard
        if gp then ep = gp.peaks; ep_dur = gp.dur end
      end
      if not ep or not ep_dur or ep_dur <= 0 then goto skip_grp_pk end
      local n_src = #ep
      local ts, te
      if c.type == "PLAY" then
        ts = c.trim_start or 0
        te = (c.trim_end and c.trim_end > 0) and c.trim_end or ep_dur
      else
        -- 巢狀 group：ts = sub.prefix（跳過負時段）-- nested: ts skips the prefix region
        ts = entry.trim_s or 0
        te = ep_dur
      end
      -- 映射到 merged 的 pixel 範圍 -- map to pixel range in merged
      local px_s = math.max(1, math.floor(audio_start / total_dur * width) + 1)
      local px_e = math.min(width, math.ceil((audio_start + eff_dur) / total_dur * width))
      for px = px_s, px_e do
        local frac = (px - px_s) / math.max(1, px_e - px_s)
        local t = ts + frac * (te - ts)
        local pi = math.floor(t / ep_dur * n_src) + 1
        pi = math.max(1, math.min(n_src, pi))
        local pk = ep[pi]
        if pk then
          if pk[1] < merged[px][1] then merged[px][1] = pk[1] end
          if pk[2] > merged[px][2] then merged[px][2] = pk[2] end
        end
      end
      ::skip_grp_pk::
    end
  end
  -- 計算max peak用於normalize -- compute max peak for normalize
  local max_pk = 0
  for _, pk in ipairs(merged) do
    if pk[2] > max_pk then max_pk = pk[2] end
    if -pk[1] > max_pk then max_pk = -pk[1] end
  end
  return {peaks = merged, dur = total_dur, max_peak = max_pk}
end

---------------------------------------------------------------------
-- GROUP TRIM PROPAGATION -- GROUP trim 傳播到 children
---------------------------------------------------------------------
-- 將 GROUP 的 trim window 映射到每個 lane 中的 children
-- group_ts/group_te: GROUP timeline 上的 trim 範圍
-- 直接修改 children 的 trim_start/trim_end
local function propagate_group_trim(gc, lane_info, group_ts, group_te)
  for _, lane in ipairs(lane_info.lanes) do
    for _, entry in ipairs(lane.entries) do
      local c = entry.cue
      if c.type ~= "PLAY" then goto skip_prop end
      local audio_start = entry.offset + entry.pre
      local audio_end = audio_start + entry.eff_dur
      local raw_dur = entry.raw_dur
      if raw_dur <= 0 then goto skip_prop end
      local orig_ts = c.trim_start or 0
      local orig_te = (c.trim_end and c.trim_end > 0) and c.trim_end or raw_dur
      local cr = (c.rate and c.rate > 0) and c.rate or 1.0
      -- GROUP trim_start 對此 entry 的影響 -- effect of GROUP trim_start on this entry
      if group_ts > audio_end then
        -- 整個 entry 被 trim 掉 -- fully trimmed
        c.trim_start = orig_te  -- trim_start = trim_end → 0 duration
      elseif group_ts > audio_start then
        -- 部分 trim：計算在 cue 的 track time 中的偏移 -- partial trim: calc offset in track time
        local delta_t = (group_ts - audio_start) * cr  -- 轉換回 track time（考慮 rate）
        c.trim_start = FUNC.clamp(orig_ts + delta_t, 0, orig_te - 0.001)
      end
      -- GROUP trim_end 對此 entry 的影響 -- effect of GROUP trim_end on this entry
      if group_te < audio_start then
        -- 整個 entry 被 trim 掉 -- fully trimmed
        c.trim_end = c.trim_start + 0.001
      elseif group_te < audio_end then
        -- 部分 trim -- partial trim
        local delta_t = (audio_end - group_te) * cr
        c.trim_end = FUNC.clamp(orig_te - delta_t, c.trim_start + 0.001, raw_dur)
      end
      -- 更新 eff_dur -- update eff_dur
      c.eff_dur = math.max(0, (c.trim_end - c.trim_start) / cr)
      ::skip_prop::
    end
  end
end

---------------------------------------------------------------------
-- DRAW GROUP WAVEFORM -- GROUP 多Lane波形顯示（含trim handles）
---------------------------------------------------------------------
-- 並聯lane垂直分割，串聯cue水平串接，巢狀GROUP顯示色塊
function FUNC.draw_group_waveform(gc, dl, cx, cy, cw, ch, skip_ruler)
  if not gc or gc.type ~= "GROUP" or cw < 10 or ch < 10 then return end

  local lane_info = FUNC.group_lanes(gc)
  local n_lanes = #lane_info.lanes
  if n_lanes == 0 or lane_info.dur <= 0 then
    ImGui.DrawList_AddRectFilled(dl, cx, cy, cx + cw, cy + ch, C.wf_bg, 4)
    ImGui.PushFont(ctx, FONT_B, FUNC.sz(26))
    local ntxt = "No waveform data"
    local tw, th = ImGui.CalcTextSize(ctx, ntxt, 0, 0)
    ImGui.DrawList_AddTextEx(dl, FONT_B, FUNC.sz(26), cx + (cw - tw) / 2, cy + (ch - th) / 2,
      FUNC.dim_c(FUNC.rgba(130,130,140,200)), ntxt)
    ImGui.PopFont(ctx)
    return
  end

  local total_dur = lane_info.dur  -- 含視覺 prefix -- includes visual prefix
  local gprefix = lane_info.prefix or 0
  local dur_pos = lane_info.dur_pos or total_dur
  local cid = gc.id
  local view = get_view(cid)

  -- 切換cue時清除上一個cue的選取 -- clear selection when switching cues
  if wf_sel.cid and wf_sel.cid ~= cid then FUNC.wf_sel_clear() end

  -- GROUP trim 值在 lane 正座標(0=playable起點)，視覺上加 gprefix -- positive coord; +gprefix for virtual
  local gts = gc.trim_start or 0
  local gte = (gc.trim_end and gc.trim_end > 0) and gc.trim_end or dur_pos
  local gts_v = gprefix + gts
  local gte_v = gprefix + gte

  -- 視圖範圍 -- view range
  local view_start = view.pos
  local view_dur = total_dur / view.zoom
  if view_start < 0 then view_start = 0; view.pos = 0 end
  local view_end = view_start + view_dur
  if view_end > total_dur then
    view_start = math.max(0, total_dur - view_dur)
    view.pos = view_start; view_end = view_start + view_dur
  end

  -- Padding for trim handle tabs + bottom ruler -- 上下留空給handle+ruler
  local tab_h_val = FUNC.sz(16)
  local ruler_h = FUNC.sz(18)  -- 底部ruler高度 -- bottom ruler height
  local pad_top = tab_h_val + FUNC.sz(8)
  -- skip_ruler 時 end handle + ruler 由外部 sticky 處理，內部 pad_bot 收成 0
  -- 讓 lanes 顏色區延伸到 chart 下緣，外部 sticky 緊貼顏色交界
  local pad_bot = skip_ruler and 0 or (tab_h_val + FUNC.sz(4) + ruler_h)
  local wy = cy + pad_top
  local wh = ch - pad_top - pad_bot

  -- Lane label移到waveform矩形內左下角，不再佔用額外空間 -- labels inside waveform rect, no reserved area
  local label_w = 0  -- 不再預留label區域 -- no reserved label area
  local full_cx = cx

  -- GROUP自身的pre/post wait區域（跟PLAY waveform相同邏輯）-- GROUP-level pre/post wait zones
  local gc_ci = FUNC.find_id(gc.id) or 0
  local g_pre_sec = gc.pre_wait or 0
  local g_post_sec = gc.post_wait or 0
  -- GROUP trim後的有效時長 -- GROUP effective duration after trim
  local g_ts = gc.trim_start or 0
  local g_te = (gc.trim_end and gc.trim_end > 0) and gc.trim_end or dur_pos
  local g_eff = math.max(0.01, math.min(dur_pos, g_te) - g_ts)
  local g_timeline = g_pre_sec + g_eff + g_post_sec
  local g_has_pre = g_pre_sec > 0.001
  local g_has_post = g_post_sec > 0.001
  local gpp_min = FUNC.sz(30)  -- pre/post最小像素 -- min pixels for pre/post zones
  local gpp_max = math.floor(cw * 0.3)  -- pre/post最大像素(各佔30%) -- max per zone (30% each)
  local g_pre_px = g_has_pre and FUNC.clamp(math.floor(cw * g_pre_sec / g_timeline), gpp_min, gpp_max) or 0
  local g_post_px = g_has_post and FUNC.clamp(math.floor(cw * g_post_sec / g_timeline), gpp_min, gpp_max) or 0
  if cw - g_pre_px - g_post_px < 20 then g_pre_px = 0; g_post_px = 0 end  -- fallback

  if g_pre_px > 0 then
    ImGui.DrawList_AddRectFilled(dl, cx, wy, cx + g_pre_px, wy + wh, C.wf_bg, 4)
    local gpw_frac = nil
    if gc.state == STATE.PREWAIT then
      gpw_frac = FUNC.timer_prog(gc_ci, TIMER.PRE) or 0
      ImGui.DrawList_AddRectFilled(dl, cx, wy, cx + g_pre_px * gpw_frac, wy + wh, C.p_wait, 4)
    elseif gc.state == STATE.RUNNING or gc.state == STATE.POSTWAIT or gc.state == STATE.DONE then
      gpw_frac = 1
      ImGui.DrawList_AddRectFilled(dl, cx, wy, cx + g_pre_px, wy + wh, C.p_wait, 4)
    end
    local pre_txt = "Pre"
    local ptw2, pth2 = ImGui.CalcTextSize(ctx, pre_txt, 0, 0)
    if ptw2 < g_pre_px - 4 then
      local fill_edge = cx + g_pre_px * (gpw_frac or 0)
      local txt_x0 = cx + (g_pre_px - ptw2) / 2
      local txt_y = wy + (wh - pth2) / 2
      local char_x = txt_x0
      for ci3 = 1, #pre_txt do
        local ch2 = pre_txt:sub(ci3, ci3)
        local chw2 = ImGui.CalcTextSize(ctx, ch2, 0, 0)
        local ch_mid = char_x + chw2 * 0.5  -- 超過字元一半就變色 -- half-char threshold
        local ch_col = (gpw_frac and ch_mid <= fill_edge) and C.wf_bg or C.p_wait
        ImGui.DrawList_AddText(dl, char_x, txt_y, ch_col, ch2)
        char_x = char_x + chw2
      end
    end
    ImGui.DrawList_AddRect(dl, cx, wy, cx + g_pre_px, wy + wh, FUNC.dim_c(FUNC.rgba(60,60,80)), 4, 0, 1)
  end
  if g_post_px > 0 then
    local post_x = cx + cw - g_post_px
    ImGui.DrawList_AddRectFilled(dl, post_x, wy, cx + cw, wy + wh, C.wf_bg, 4)
    local gptw_frac = nil
    if gc.state == STATE.POSTWAIT then
      gptw_frac = FUNC.timer_prog(gc_ci, TIMER.POST) or 0
      ImGui.DrawList_AddRectFilled(dl, post_x, wy, post_x + g_post_px * gptw_frac, wy + wh, C.p_ptw, 4)
    end
    local post_txt = "Post"
    local potw2, poth2 = ImGui.CalcTextSize(ctx, post_txt, 0, 0)
    if potw2 < g_post_px - 4 then
      local post_fill_edge = post_x + g_post_px * (gptw_frac or 0)
      local post_txt_x0 = post_x + (g_post_px - potw2) / 2
      local post_txt_y = wy + (wh - poth2) / 2
      local post_char_x = post_txt_x0
      for ci3 = 1, #post_txt do
        local ch2 = post_txt:sub(ci3, ci3)
        local chw2 = ImGui.CalcTextSize(ctx, ch2, 0, 0)
        local ch_mid = post_char_x + chw2 * 0.5  -- 超過字元一半就變色 -- half-char threshold
        local ch_col = (gptw_frac and ch_mid <= post_fill_edge) and C.wf_bg or C.p_ptw
        ImGui.DrawList_AddText(dl, post_char_x, post_txt_y, ch_col, ch2)
        post_char_x = post_char_x + chw2
      end
    end
    ImGui.DrawList_AddRect(dl, post_x, wy, cx + cw, wy + wh, FUNC.dim_c(FUNC.rgba(60,60,80)), 4, 0, 1)
  end
  -- 覆蓋cx/cw為波形內容區域（扣除GROUP pre/post）-- shift cx/cw for waveform content
  cx = cx + g_pre_px; cw = cw - g_pre_px - g_post_px

  -- 背景 -- background
  ImGui.DrawList_AddRectFilled(dl, cx, wy, cx + cw, wy + wh, C.wf_bg, 4)

  -- 時間軸刻度（波形底部）-- time ruler at bottom of waveform (matching fade chart style)
  -- group: 顯示時間以 0:00 = audio play 起點為基準，前綴顯示為負時間 -- 0:00 = audio start, prefix shown as negative
  -- 儲存 ruler 資料供外部 sticky ruler 使用 -- store ruler params for external sticky ruler
  gc._gw_ruler = {x=cx, w=cw, view_start=view_start, view_dur=view_dur, prefix=gprefix}
  if not skip_ruler then
    draw_time_ruler(dl, cx, wy + wh, cw, view_start, view_dur, gprefix)
  end

  -- Lane垂直分配 -- lane vertical allocation
  local lane_gap = n_lanes > 1 and FUNC.sz(3) or 0
  local total_gap = lane_gap * (n_lanes - 1)
  local lane_h = math.max(FUNC.sz(32), (wh - total_gap) / n_lanes)  -- min px per lane

  -- 波形顏色 -- waveform colors
  local wr = (C.wf >> 24) & 0xFF
  local wg = (C.wf >> 16) & 0xFF
  local wb = (C.wf >> 8) & 0xFF
  local wf_col = FUNC.dim_c(FUNC.rgba(wr, wg, wb, 200))
  local wf_dim = FUNC.dim_c(FUNC.rgba(wr * 0.4, wg * 0.4, wb * 0.4, 100))
  local wf_played = FUNC.dim_c(FUNC.rgba(120, 120, 120, 150))  -- 播放過的波形灰色 -- played portion grey

  local deferred_labels = {}  -- lane label延遲繪製，畫在波形上層 -- deferred lane labels, drawn on top of waveforms
  for li, lane in ipairs(lane_info.lanes) do
    local ly = wy + (li - 1) * (lane_h + lane_gap)
    local lh = lane_h
    local mid_y = ly + lh / 2
    local half_h = lh / 2 * 0.9

    -- Lane分隔線 -- lane separator
    if li > 1 then
      ImGui.DrawList_AddLine(dl, cx, ly - lane_gap / 2, cx + cw, ly - lane_gap / 2,
        FUNC.rgba(255,255,255,40), 1)
    end

    -- C10 #1: lane 沒內容區段(實心灰底，無中線) -- solid gray for empty zones (no content)
    -- head empty: [0..gprefix - lane.prefix]; tail empty: [gprefix + lane.dur..total_dur]
    do
      local lane_prefix = lane.prefix or 0
      local head_end_v = gprefix - lane_prefix
      local tail_start_v = gprefix + lane.dur
      local empty_col = FUNC.rgba(50, 50, 55, 255)
      if head_end_v > view_start then
        local hs = 0
        local he = math.min(cw, math.floor((head_end_v - view_start) / view_dur * cw))
        if he > hs then
          ImGui.DrawList_AddRectFilled(dl, cx + hs, ly, cx + he, ly + lh, empty_col)
        end
      end
      if tail_start_v < view_end then
        local ts2 = math.max(0, math.ceil((tail_start_v - view_start) / view_dur * cw))
        local te2 = cw
        if te2 > ts2 then
          ImGui.DrawList_AddRectFilled(dl, cx + ts2, ly, cx + te2, ly + lh, empty_col)
        end
      end
    end
    -- 收集lane label資料（延遲到波形全畫完才繪製，避免被蓋住）-- collect label data, deferred draw after all waveforms
    if n_lanes > 1 and #lane.entries > 0 then
      local first_c = lane.entries[1].cue
      local ti_str = "Tr." .. ((first_c.track_idx or 0) + 1)
      local name_str = first_c.name ~= "" and first_c.name or ""
      local full_lbl = name_str ~= "" and (ti_str .. " - " .. name_str) or ti_str
      deferred_labels[#deferred_labels+1] = {full_lbl = full_lbl, ly = ly, lh = lh, lane_idx = li}
    end

    -- 繪製lane中每個entry -- draw each entry in lane
    for ei, entry in ipairs(lane.entries) do
      local c = entry.cue
      -- 虛擬座標 (= gprefix + lane positive)；group 0:00 線位於虛擬 gprefix
      -- virtual coord; group play 0:00 line is at virtual t=gprefix
      local audio_start = gprefix + entry.offset + entry.pre
      local audio_end = audio_start + entry.eff_dur

      -- C10 #1: trim 區段改用 alpha 遮罩(在 render loop 內以 wf_dim 顯示)
      -- trim regions now rendered as dim waveform via wf_dim (handled in main render loop)
      local trim_lead = (ei == 1) and (entry.trim_s or 0) or 0
      local visible_start = audio_start - trim_lead

      -- 計算child的播放頭在虛擬 GROUP 時間軸上的位置 -- child playhead on virtual GROUP timeline
      local child_ph_group = nil
      if c.type == "PLAY" and c.state == STATE.RUNNING and c.play_t0 > 0 then
        -- play_offset含GROUP trim offset，需換算回GROUP時間軸 -- account for GROUP trim in play_offset
        local cr = (c.rate and c.rate > 0) and c.rate or 1.0
        local extra = ((c.play_offset or 0) - (c.trim_start or 0)) / cr
        child_ph_group = audio_start + extra + (reaper.time_precise() - c.play_t0)
      elseif c.state == STATE.PREWAIT and entry.pre > 0 then
        -- pre-wait 期間：playhead 從 entry 起點往 audio_start 移動
        -- during pre-wait: playhead sweeps from entry start to audio_start
        local prog = FUNC.timer_prog(entry.idx, TIMER.PRE) or 0
        child_ph_group = (gprefix + entry.offset) + entry.pre * prog
      elseif c.state == STATE.POSTWAIT and entry.post > 0 then
        -- post-wait 期間：playhead 從 audio_end 往 entry 終點移動
        -- during post-wait: playhead sweeps from audio_end to entry end
        local prog = FUNC.timer_prog(entry.idx, TIMER.POST) or 0
        child_ph_group = audio_end + entry.post * prog
      end

      -- PLAY 或 GROUP 都顯示波形（GROUP用疊合peaks）-- both PLAY and GROUP show waveform
      if (c.type == "PLAY" or c.type == "GROUP") and entry.eff_dur > 0 then
        local raw_px_s = math.floor((visible_start - view_start) / view_dur * cw)
        local raw_px_e = math.ceil((audio_end - view_start) / view_dur * cw)
        local px_s = math.max(0, raw_px_s)
        local px_e = math.min(cw, raw_px_e)

        if px_e > px_s then
          -- 取得peaks：PLAY用wf_build_cache，GROUP用wf_build_group_peaks -- get peaks
          local peaks, n_peaks, src_dur
          local cache_w = math.max(10, math.floor(cw * (view.zoom_target or view.zoom)))  -- 用zoom_target建cache，動畫中不重建 -- build at target zoom, stable during lerp
          if c.type == "PLAY" then
            local cache = FUNC.wf_build_cache(c, cache_w)
            if cache and cache.peaks then peaks = cache.peaks; n_peaks = #cache.peaks; src_dur = cache.dur end
          else
            local gp = FUNC.wf_build_group_peaks(c, cache_w, {[gc.id]=true})  -- 傳入parent防循環 -- pass parent to prevent cycle
            if gp and gp.peaks then peaks = gp.peaks; n_peaks = #gp.peaks; src_dur = gp.dur end
          end

          if peaks and n_peaks > 0 and src_dur > 0 then
            local ts, te
            if c.type == "PLAY" then
              ts = c.trim_start or 0
              te = (c.trim_end and c.trim_end > 0) and c.trim_end or src_dur
            else
              ts = entry.trim_s or 0
              te = src_dur
            end
            local child_gain = FUNC.db2lin(c.volume or 0)
            local child_norm = 1
            if prefs.wf_normalize == 1 then
              -- 取child的max_peak -- get child max_peak from cache
              local child_mp = 0
              if c.type == "PLAY" then
                local cc = FUNC.wf_build_cache(c, cache_w)
                if cc and cc.max_peak then child_mp = cc.max_peak end
              else
                local gp = FUNC.wf_build_group_peaks(c, cache_w, {[gc.id]=true})  -- 傳入parent防循環 -- pass parent to prevent cycle
                if gp and gp.max_peak then child_mp = gp.max_peak end
              end
              if child_mp > 0 and half_h > 2 then
                child_norm = (half_h - 2) / (child_mp * child_gain * half_h)  -- peak距離頂部2px -- 2px margin from top
              end
            end
            local v_scale = view.v_zoom * child_gain * child_norm

            for px = px_s, px_e - 1 do
              -- 直接從pixel算GROUP timeline時間（修正clamp後映射錯誤）-- direct time calc fixes clamped pixel mapping
              local t_group = view_start + (px / cw) * view_dur
              local t_in_cue, in_lead
              if t_group < audio_start and trim_lead > 0.001 then
                -- C10 #1: 在 trim_lead 區段，映射到 [0..ts] 用 wf_dim 呈現
                -- in trim lead region: map to [0..ts], rendered dim
                local lead_frac = FUNC.clamp((t_group - visible_start) / trim_lead, 0, 1)
                t_in_cue = lead_frac * ts
                in_lead = true
              else
                local frac_in_entry = FUNC.clamp((t_group - audio_start) / entry.eff_dur, 0, 1)
                t_in_cue = ts + frac_in_entry * (te - ts)
              end
              local in_trim = (not in_lead) and (t_group >= gts_v and t_group <= gte_v)
              -- 播放過的部分變灰色 -- grey for played portion
              local is_played = child_ph_group and in_trim and t_group < child_ph_group
              local pi = math.floor(t_in_cue / src_dur * n_peaks) + 1
              pi = math.max(1, math.min(n_peaks, pi))
              local pk = peaks[pi]
              if pk then
                local mn = pk[1] * v_scale
                local mx_v = pk[2] * v_scale
                local y1 = mid_y - mx_v * half_h
                local y2 = mid_y - mn * half_h
                y1 = math.max(ly, math.min(ly + lh, y1))
                y2 = math.max(ly, math.min(ly + lh, y2))
                local col = is_played and wf_played or (in_trim and wf_col or wf_dim)
                if math.abs(y2 - y1) < 1 then
                  ImGui.DrawList_AddLine(dl, cx + px, mid_y, cx + px, mid_y + 1, col, 1)
                else
                  ImGui.DrawList_AddLine(dl, cx + px, y1, cx + px, y2, col, 1)
                end
              end
            end
          end
          -- Cue邊界線 -- cue boundary line
          if ei > 1 then
            local bx = cx + math.floor((audio_start - view_start) / view_dur * cw)
            if bx > cx and bx < cx + cw then
              ImGui.DrawList_AddLine(dl, bx, ly, bx, ly + lh, FUNC.rgba(255,255,255,50), 1)
            end
          end
          -- 巢狀GROUP名稱標記 -- nested GROUP name label
          if c.type == "GROUP" then
            local name = c.name ~= "" and c.name or ("G" .. (c.cue_number or ""))
            local ntw, nth = ImGui.CalcTextSize(ctx, name, 0, 0)
            local vis_w = px_e - px_s
            if ntw < vis_w - 4 then
              ImGui.DrawList_AddText(dl, cx + px_s + (vis_w - ntw) / 2,
                ly + 2, FUNC.dim_c(FUNC.rgba(180,150,220,180)), name)
            end
          end
          -- 播放頭白線（每行都畫）-- playhead white line per playing child
          if child_ph_group and child_ph_group >= view_start and child_ph_group <= view_end then
            local ph_px = cx + ((child_ph_group - view_start) / view_dur) * cw
            ImGui.DrawList_AddLine(dl, ph_px, ly, ph_px, ly + lh, FUNC.rgba(255,255,255,220), 1.5)
            -- 三角形只畫在最上方 -- triangle only at top of waveform area
            if li == 1 then
              local tri_sz = FUNC.sz(4)
              ImGui.DrawList_AddTriangleFilled(dl,
                ph_px - tri_sz, wy, ph_px + tri_sz, wy, ph_px, wy + tri_sz,
                FUNC.rgba(255,255,255,220))
            end
          end
        end

      elseif c.type == "FADE" and entry.eff_dur > 0 then
        -- FADE：黃色塊 -- FADE: yellow block
        local px_s = math.max(0, math.floor((audio_start - view_start) / view_dur * cw))
        local px_e = math.min(cw, math.ceil((audio_end - view_start) / view_dur * cw))
        if px_e > px_s then
          ImGui.DrawList_AddRectFilled(dl, cx + px_s, ly + 2, cx + px_e, ly + lh - 2,
            FUNC.rgba(150, 120, 40, 80), 2)
          ImGui.DrawList_AddRect(dl, cx + px_s, ly + 2, cx + px_e, ly + lh - 2,
            FUNC.rgba(200, 160, 50, 150), 2)
        end
      end

      -- pre/post wait區域淡色標記+文字 (virtual 座標) -- pre/post wait faint markers + text labels
      if entry.pre > 0 then
        local pre_v_s = gprefix + entry.offset
        local pre_v_e = gprefix + entry.offset + entry.pre
        local ppx_s = math.max(0, math.floor((pre_v_s - view_start) / view_dur * cw))
        local ppx_e = math.min(cw, math.floor((pre_v_e - view_start) / view_dur * cw))
        if ppx_e > ppx_s then
          ImGui.DrawList_AddRectFilled(dl, cx + ppx_s, ly, cx + ppx_e, ly + lh,
            FUNC.rgba(60, 100, 180, 30))
          -- Pre文字（空間足夠時顯示）-- show "Pre" label if space permits
          local pre_txt = "Pre"
          local ptw, pth = ImGui.CalcTextSize(ctx, pre_txt, 0, 0)
          local pre_w = ppx_e - ppx_s
          if ptw < pre_w - 4 then
            ImGui.DrawList_AddText(dl, cx + ppx_s + (pre_w - ptw) / 2, ly + (lh - pth) / 2,
              FUNC.rgba(100, 150, 220, 150), pre_txt)
          end
        end
      end
      if entry.post > 0 then
        local post_v_e = gprefix + entry.offset + entry.entry_dur
        local ppx_s = math.max(0, math.floor((audio_end - view_start) / view_dur * cw))
        local ppx_e = math.min(cw, math.ceil((post_v_e - view_start) / view_dur * cw))
        if ppx_e > ppx_s then
          ImGui.DrawList_AddRectFilled(dl, cx + ppx_s, ly, cx + ppx_e, ly + lh,
            FUNC.rgba(180, 100, 60, 30))
          -- Post文字（空間足夠時顯示）-- show "Post" label if space permits
          local post_txt = "Post"
          local potw, poth = ImGui.CalcTextSize(ctx, post_txt, 0, 0)
          local post_w = ppx_e - ppx_s
          if potw < post_w - 4 then
            ImGui.DrawList_AddText(dl, cx + ppx_s + (post_w - potw) / 2, ly + (lh - poth) / 2,
              FUNC.rgba(220, 140, 80, 150), post_txt)
          end
        end
      end
    end

    -- 0dB中線 -- center line per lane
    ImGui.DrawList_AddLine(dl, cx, mid_y, cx + cw, mid_y, FUNC.rgba(255,255,255,20), 1)
  end

  -- 延遲繪製lane labels（在所有波形之上）-- deferred lane label draw (on top of all waveforms)
  local lbl_fsz = FUNC.sz(11)
  local lbl_pad = FUNC.sz(4)
  local avail_lbl_w = cw - FUNC.sz(6)  -- label最大可用寬度 -- max available width for label
  for _, lbl_info in ipairs(deferred_labels) do
    local full_lbl = lbl_info.full_lbl
    local ly, lh = lbl_info.ly, lbl_info.lh
    local lbl_col_dim = FUNC.dim_c(FUNC.col2im(prefs.col_ruler or 0x00C8C8D0, 200))
    local lbl_col_full = FUNC.col2im(prefs.col_ruler or 0x00C8C8D0, 255)
    ImGui.PushFont(ctx, FONT, lbl_fsz)
    local full_tw, lth = ImGui.CalcTextSize(ctx, full_lbl, 0, 0)
    ImGui.PopFont(ctx)
    local label_x0 = cx + FUNC.sz(3)
    local label_y = ly + lh - lth - FUNC.sz(2)
    local truncated = full_tw > avail_lbl_w
    -- hover判定用截斷後的寬度，不超出waveform邊界 -- hover rect clamped to waveform bounds
    local lbl_rect_w = math.min(full_tw, avail_lbl_w) + lbl_pad * 2
    local lbl_hov = ImGui.IsMouseHoveringRect(ctx, label_x0 - lbl_pad, label_y - FUNC.sz(1),
      label_x0 + lbl_rect_w, label_y + lth + FUNC.sz(1))
    if lbl_hov then
      -- 醒目模式：不透明bg僅文字寬度（過長時限制在waveform內）-- hover: opaque bg matches text width
      ImGui.PushFont(ctx, FONT_B, lbl_fsz)
      local bold_tw = ImGui.CalcTextSize(ctx, full_lbl, 0, 0)
      ImGui.PopFont(ctx)
      local bg_w = math.min(truncated and avail_lbl_w or bold_tw, cw - FUNC.sz(6)) + lbl_pad * 2
      ImGui.DrawList_AddRectFilled(dl, label_x0 - lbl_pad, label_y - FUNC.sz(1),
        label_x0 - lbl_pad + bg_w, label_y + lth + FUNC.sz(1), FUNC.rgba(30, 30, 45, 255), 3)
      if truncated then
        -- 跑馬燈：hover時滾動過長的名字 -- marquee scroll on hover for long names
        FUNC.draw_marquee(dl, FONT_B, lbl_fsz, full_lbl, lbl_col_full,
          label_x0, label_y, avail_lbl_w, lth, "wf_lane_"..lbl_info.lane_idx,
          {delay = 0.3, speed = FUNC.sz(40), gap = 12, pad = 0})
      else
        ImGui.DrawList_AddTextEx(dl, FONT_B, lbl_fsz, label_x0, label_y, lbl_col_full, full_lbl)
      end
    else
      -- 平常暗色+截斷 -- normal dim with truncation
      if truncated then
        ImGui.PushFont(ctx, FONT, lbl_fsz)
        local lbl = full_lbl
        while #lbl > 1 do
          local ltw = ImGui.CalcTextSize(ctx, lbl .. "..", 0, 0)
          if ltw <= avail_lbl_w then break end
          lbl = lbl:sub(1, -2)
        end
        ImGui.PopFont(ctx)
        lbl = lbl .. ".."
        ImGui.DrawList_AddTextEx(dl, FONT, lbl_fsz, label_x0, label_y, lbl_col_dim, lbl)
      else
        ImGui.DrawList_AddTextEx(dl, FONT, lbl_fsz, label_x0, label_y, lbl_col_dim, full_lbl)
      end
    end
  end

  -- Trim 外暗化 -- dim overlay outside GROUP trim range (virtual coord)
  local trim_s_x = cx + ((gts_v - view_start) / view_dur) * cw
  local trim_e_x = cx + ((gte_v - view_start) / view_dur) * cw
  if trim_s_x > cx then
    ImGui.DrawList_AddRectFilled(dl, cx, wy, math.min(trim_s_x, cx + cw), wy + wh, FUNC.rgba(0,0,0,100))
  end
  if trim_e_x < cx + cw then
    ImGui.DrawList_AddRectFilled(dl, math.max(trim_e_x, cx), wy, cx + cw, wy + wh, FUNC.rgba(0,0,0,100))
  end

  -- Trim handles -- trim 把手（跟 PLAY cue 相同風格）
  local tab_w = FUNC.sz(12)
  local tab_h = tab_h_val
  local handle_col = FUNC.dim_c(C.trim)
  local handle_hover_col = FUNC.dim_c(FUNC.rgba(255, 200, 100))
  local guide_col = FUNC.dim_c(FUNC.rgba(wr, wg, wb, 80))

  -- Start handle（上方）-- start handle (above waveform)
  local s_vis = trim_s_x >= cx - tab_w and trim_s_x <= cx + cw + tab_w
  if s_vis then
    local s_x1, s_x2 = trim_s_x - tab_w / 2, trim_s_x + tab_w / 2
    local s_y1, s_y2 = wy - tab_h, wy
    local hov_s = ImGui.IsMouseHoveringRect(ctx, s_x1 - 2, s_y1, s_x2 + 2, s_y2)
    local hcol = (hov_s or wf_handle.dragging == "start") and handle_hover_col or handle_col
    ImGui.DrawList_AddRectFilled(dl, s_x1, s_y1, s_x2, s_y2, hcol, 2)
    ImGui.DrawList_AddLine(dl, trim_s_x, wy, trim_s_x, wy + wh, guide_col, 1)
    -- handle timecode 暫時隱藏（改用底部ruler）-- handle timecode hidden (using bottom ruler instead)
  end

  -- End handle（下方）-- end handle (below waveform)
  local e_vis = trim_e_x >= cx - tab_w and trim_e_x <= cx + cw + tab_w
  if e_vis then
    -- guide line 不論是否 skip 都畫（在 scroll 區內延伸）-- guide line always drawn inside scroll area
    ImGui.DrawList_AddLine(dl, trim_e_x, wy, trim_e_x, wy + wh, guide_col, 1)
    if not skip_ruler then
      local e_x1, e_x2 = trim_e_x - tab_w / 2, trim_e_x + tab_w / 2
      local e_y1, e_y2 = wy + wh, wy + wh + tab_h
      local hov_e = ImGui.IsMouseHoveringRect(ctx, e_x1 - 2, e_y1, e_x2 + 2, e_y2)
      local hcol = (hov_e or wf_handle.dragging == "end") and handle_hover_col or handle_col
      ImGui.DrawList_AddRectFilled(dl, e_x1, e_y1, e_x2, e_y2, hcol, 2)
    end
  end
  -- 儲存 end handle 資訊供外部 sticky 繪製/hit-test -- store for external sticky draw + hit-test
  gc._gw_end_handle = {trim_e_x=trim_e_x, tab_w=tab_w, tab_h=tab_h,
    handle_col=handle_col, handle_hover_col=handle_hover_col, e_vis=e_vis,
    cx=cx, cw=cw, view_start=view_start, view_dur=view_dur}

  -- Vertical zoom handle (left edge, outside rectangle) -- 垂直縮放把手（矩形左外側）
  -- skip_ruler (scroll 模式)：用 viewport 中央，不隨 scroll 跑 -- viewport-relative when in scroll mode
  local g_mid_y
  if skip_ruler then
    local scr_y = ImGui.GetScrollY(ctx)
    local vp_h = ImGui.GetWindowHeight(ctx)
    g_mid_y = cy + scr_y + vp_h / 2
  else
    g_mid_y = wy + wh / 2
  end
  local g_handle_h = FUNC.sz(14)
  local g_handle_w = FUNC.sz(8)
  local g_handle_x = cx + cw - g_handle_w - FUNC.sz(3)  -- 矩形內右側 -- inside right edge
  local g_gain_hov = ImGui.IsMouseHoveringRect(ctx, g_handle_x - 2, g_mid_y - g_handle_h / 2, g_handle_x + g_handle_w + 2, g_mid_y + g_handle_h / 2)
  local g_gain_col = (g_gain_hov or wf_handle.dragging == "gain") and handle_hover_col or FUNC.dim_c(FUNC.rgba(100, 200, 100))
  ImGui.DrawList_AddRectFilled(dl, g_handle_x, g_mid_y - g_handle_h / 2, g_handle_x + g_handle_w, g_mid_y + g_handle_h / 2, g_gain_col, 2)
  local g_vz_txt = string.format("%.1fx", view.v_zoom)
  local g_vz_tw = ImGui.CalcTextSize(ctx, g_vz_txt, 0, 0)
  local _, g_vz_th = ImGui.CalcTextSize(ctx, g_vz_txt, 0, 0)
  ImGui.DrawList_AddText(dl, g_handle_x - g_vz_tw - FUNC.sz(3), g_mid_y - g_vz_th / 2, FUNC.dim_c(C.text), g_vz_txt)  -- 文字垂直對齊中線 -- vertically centered on baseline

  -- 外框 -- border
  ImGui.DrawList_AddRect(dl, cx, wy, cx + cw, wy + wh, FUNC.dim_c(FUNC.rgba(60, 60, 80)), 4, 0, 1)

  -- === INTERACTION === -- 互動處理
  local mx, my = ImGui.GetMousePos(ctx)
  local in_area = mx >= cx and mx <= cx + cw and my >= cy and my <= cy + ch
  local skip_input = false  -- A4: drag/pan 中略過後續 input 但保留繪製 -- skip input, keep drawing during drag/pan

  -- Handle dragging（活動中）-- handle drag active
  if wf_handle.dragging then
    if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left()) then
      local dx, dy = ImGui.GetMouseDelta(ctx)
      local mx_abs = ImGui.GetMousePos(ctx)
      local mt = view_start + (mx_abs - cx) / cw * view_dur  -- 滑鼠絕對 x → 時間 -- absolute mouse x → time
      if wf_handle.dragging == "start" then
        local new_gts = FUNC.clamp(mt, 0, gte - 0.01)
        gc.trim_start = new_gts
        -- Bug 5: child_group_pos 必須考慮播放時的 trim 偏移 (play_offset)，不能只用 a_s+elapsed
        -- 否則往 0 拖時 new_gts 看似超過 child_group_pos 而誤觸 seek
        -- group-time playhead = a_s + (cc.play_offset - orig_ts)/rate + elapsed
        for _, lane in ipairs(lane_info.lanes) do
          for _, entry in ipairs(lane.entries) do
            local cc = entry.cue
            if cc.type == "PLAY" and cc.state == STATE.RUNNING and cc.play_t0 > 0 then
              local a_s = entry.offset + entry.pre
              local a_e = a_s + entry.eff_dur
              local cr = (cc.rate and cc.rate > 0) and cc.rate or 1.0
              local orig_ts = cc.trim_start or 0
              local pof = cc.play_offset or orig_ts
              local child_group_pos = a_s + (pof - orig_ts) / cr + (reaper.time_precise() - cc.play_t0)
              if new_gts >= a_e then
                FUNC.kill_cue(cc)
              elseif new_gts > child_group_pos then
                local extra_start = math.max(0, new_gts - a_s) * cr
                cc._rt_trim_start = orig_ts + extra_start
                FUNC.play_cue(cc)
              end
            end
          end
        end
      elseif wf_handle.dragging == "end" then
        local new_gte = FUNC.clamp(mt, gts + 0.01, dur_pos)  -- 上限為 playable 終點 -- max = playable end
        gc.trim_end = new_gte
        -- Bug 5: 同上，child_group_pos 必須考慮 play_offset
        for _, lane in ipairs(lane_info.lanes) do
          for _, entry in ipairs(lane.entries) do
            local cc = entry.cue
            if cc.type == "PLAY" and cc.state == STATE.RUNNING and cc.play_t0 > 0 then
              local a_s = entry.offset + entry.pre
              local cr = (cc.rate and cc.rate > 0) and cc.rate or 1.0
              local orig_ts = cc.trim_start or 0
              local pof = cc.play_offset or orig_ts
              local child_group_pos = a_s + (pof - orig_ts) / cr + (reaper.time_precise() - cc.play_t0)
              -- loop 交由 cleanup 處理；這裡只處理非 loop 立即 kill
              -- loop handled by cleanup; here only non-loop immediate kill
              if new_gte <= child_group_pos and not cc.loop then
                FUNC.kill_cue(cc)
              end
            end
          end
        end
      elseif wf_handle.dragging == "gain" then
        -- 垂直縮放波形 -- v_zoom drag
        local zd = -dy * 0.02
        if ImGui.IsKeyDown(ctx, ImGui.Mod_Shift()) then zd = zd * 0.2 end
        view.v_zoom = FUNC.clamp(view.v_zoom + zd, 0.1, 12)
      end
    else
      -- 拖曳結束：保留GROUP trim值，不自動傳播（用Apply按鈕手動傳播）
      -- drag end: keep GROUP trim, use Apply button to propagate
      local was_gain = wf_handle.dragging == "gain"
      wf_handle.dragging = nil
      if not was_gain then FUNC.save_cues() end
    end
    skip_input = true  -- A4: 拖曳中保留繪製 -- keep drawing during drag
  end

  -- Handle click detection -- 點擊把手開始拖曳
  if not skip_input and in_area then
    local hov_s = s_vis and math.abs(mx - trim_s_x) <= tab_w and my >= wy - tab_h and my <= wy + FUNC.sz(4)
    -- skip_ruler 時 end handle 由外部 sticky 處理 hit-test -- skip_ruler: external sticky handles hit-test
    local hov_e = (not skip_ruler) and e_vis and math.abs(mx - trim_e_x) <= tab_w and my >= wy + wh - FUNC.sz(4) and my <= wy + wh + tab_h
    local hov_g = mx >= g_handle_x - 2 and mx <= g_handle_x + g_handle_w + 2 and math.abs(my - g_mid_y) <= g_handle_h  -- gain handle在矩形內右側 -- gain handle inside right edge

    if ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left()) then
      -- 雙擊重置 GROUP trim handle（不動 children）-- double-click reset GROUP trim only
      if hov_s or hov_e then
        gc.trim_start = 0; gc.trim_end = 0
        FUNC.save_cues()
        wf_handle.dragging = nil
      elseif hov_g then view.v_zoom = 1; wf_handle.dragging = nil  -- 雙擊重置v_zoom -- double-click reset v_zoom
      end
    elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left()) and not env_drag.active and not env_drag.marquee and not env_drag.pending then
      local has_active_env = (env_edit_mode == "vol" and gc.env_enabled)
                          or (env_edit_mode == "pan" and gc.pan_env_enabled)
                          or (env_edit_mode == "fx" and fx_env_edit_idx and gc.fx_envs and gc.fx_envs[fx_env_edit_idx])
      if hov_s then wf_handle.dragging = "start"; FUNC.push_undo()
      elseif hov_e then wf_handle.dragging = "end"; FUNC.push_undo()
      elseif hov_g then wf_handle.dragging = "gain"  -- v_zoom不需undo -- no undo for v_zoom
      elseif not has_active_env then
        -- 空白區域：開始選取範圍（同PLAY）-- empty area: start range selection (same as PLAY)
        local click_t = view_start + ((mx - cx) / cw) * view_dur
        FUNC.wf_sel_stop()
        wf_sel.cid = cid; wf_sel.t0 = click_t; wf_sel.t1 = click_t; wf_sel.dragging = true
      end
    end
  end

  -- 右鍵拖曳平移+垂直捲動 -- right-click pan + vertical scroll
  -- GROUP marker右鍵hover時不啟動pan -- skip pan when GROUP marker hovered
  local gmk_rclick_block = false
  local gmk_markers_pre = gc.markers or {}
  local gmk_tri_pre = FUNC.sz(5); local gmk_y_pre = wy - FUNC.sz(2)
  for _, mt in ipairs(gmk_markers_pre) do
    local mt_v = gprefix + mt
    if mt_v >= view_start and mt_v <= view_end then
      local gmk_x_pre = cx + ((mt_v - view_start) / view_dur) * cw
      ImGui.PushFont(ctx, FONT_MONO, FUNC.sz(9))
      local _, gmk_th_pre = ImGui.CalcTextSize(ctx, "0:00.0", 0, 0)
      ImGui.PopFont(ctx)
      if ImGui.IsMouseHoveringRect(ctx, gmk_x_pre - gmk_tri_pre - 2, gmk_y_pre - gmk_tri_pre*2 - gmk_th_pre - 2, gmk_x_pre + gmk_tri_pre + 2, gmk_y_pre + 1) then
        gmk_rclick_block = true; break
      end
    end
  end
  if wf_markers._g_rclick and wf_markers._g_rclick.cue == gc then gmk_rclick_block = true end
  if in_area and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right()) and not gmk_rclick_block then
    wf_drag.active = true; wf_drag.start_x = mx; wf_drag.start_y = my
    wf_drag.start_pos = view.pos; wf_drag.start_scroll = ImGui.GetScrollY(ctx)
    view.anchor_t = nil  -- 右鍵拖曳時清除zoom anchor -- clear zoom anchor on pan drag
  end
  if wf_drag.active then
    if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Right()) then
      local dx = mx - wf_drag.start_x
      local dt = -(dx / cw) * view_dur
      view.pos = FUNC.clamp(wf_drag.start_pos + dt, 0, math.max(0, total_dur - view_dur))
      -- 垂直捲動（children多時有scrollbar）-- vertical scroll when scrollbar present
      local dy = my - wf_drag.start_y
      local max_scroll = ImGui.GetScrollMaxY(ctx)
      if max_scroll > 0 then
        ImGui.SetScrollY(ctx, FUNC.clamp(wf_drag.start_scroll - dy, 0, max_scroll))
      end
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_Hand())
    else wf_drag.active = false end
    skip_input = true  -- A4: GROUP pan 中保留繪製 -- keep drawing during pan
  end

  -- 滾輪：依wf_wheel設定（優先級比對，同PLAY waveform）-- wheel: priority match (same as PLAY)
  if not skip_input and in_area then
    local wheel_v, wheel_h = ImGui.GetMouseWheel(ctx)
    local wheel = wheel_v ~= 0 and wheel_v or wheel_h  -- Shift+wheel→horizontal
    if wheel ~= 0 then
      local hs = ImGui.IsKeyDown(ctx, ImGui.Mod_Shift()) and true or false
      local hc = ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl()) and true or false
      local ha = ImGui.IsKeyDown(ctx, ImGui.Mod_Alt()) and true or false
      local action, best_n, do_rev = "scroll", -1, false
      if wf_wheel then
        for _, wd in ipairs(WF_WHEEL_DEFS) do
          local w = wf_wheel[wd.id]
          if w then
            local ok = true
            if w.shift and not hs then ok = false end
            if w.ctrl and not hc then ok = false end
            if w.alt and not ha then ok = false end
            if ok then
              local n = (w.shift and 1 or 0) + (w.ctrl and 1 or 0) + (w.alt and 1 or 0)
              if n > best_n then best_n = n; action = wd.id; do_rev = w.rev end
            end
          end
        end
      end
      if do_rev then wheel = -wheel end
      if action == "vzoom" then
        local vzt = view.vz_target or view.v_zoom
        if wheel > 0 then view.vz_target = math.min(vzt * 1.2, 12)
        else view.vz_target = math.max(vzt / 1.2, 0.1) end
      elseif action == "hzoom" then
        -- 用當前渲染值計算游標下方的時間（同PLAY waveform）
        -- use current rendered values for mouse_t (same as PLAY waveform)
        local mouse_t = view.pos + ((mx - cx) / cw) * (total_dur / view.zoom)
        local frac = (mx - cx) / cw
        local zt = view.zoom_target or view.zoom
        if wheel > 0 then view.zoom_target = math.min(zt * 1.25, 200)
        else view.zoom_target = math.max(zt / 1.25, 1) end
        view.anchor_t = mouse_t
        view.anchor_frac = frac
        view.anchor_total_dur = total_dur
      else
        view.anchor_t = nil  -- scroll時清除anchor -- clear anchor on scroll
        local scroll_amt = -wheel * view_dur * 0.1
        view.pos_target = FUNC.clamp((view.pos_target or view.pos) + scroll_amt, 0, math.max(0, total_dur - view_dur))
      end
    end
  end

  -- === GROUP RANGE SELECTION === -- GROUP 選取範圍（同 PLAY waveform 邏輯）
  local guide_col = FUNC.dim_c(C.guide or FUNC.rgba(224, 224, 240))
  -- 拖曳中：更新選取範圍 -- dragging: update range
  if wf_sel.dragging and wf_sel.cid == cid then
    if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left()) then
      wf_sel.t1 = view_start + ((mx - cx) / cw) * view_dur
    else
      wf_sel.dragging = false
      local s0 = math.min(wf_sel.t0, wf_sel.t1)
      local s1 = math.max(wf_sel.t0, wf_sel.t1)
      if s1 - s0 <= 0.02 then  -- 太短→轉為 edit cursor -- too short → promote to edit cursor
        gc._edit_cursor_t = s0
        wf_sel.t0 = nil; wf_sel.t1 = nil; wf_sel.cid = nil
      else
        gc._edit_cursor_t = nil  -- 拖出範圍 → 清舊 cursor -- real range committed → clear cursor
      end
    end
  end
  -- 繪製選取範圍高亮 -- draw selection range highlight
  if wf_sel.cid == cid and wf_sel.t0 and wf_sel.t1 then
    local s0 = math.min(wf_sel.t0, wf_sel.t1)
    local s1 = math.max(wf_sel.t0, wf_sel.t1)
    local sx0 = cx + ((s0 - view_start) / view_dur) * cw
    local sx1 = cx + ((s1 - view_start) / view_dur) * cw
    sx0 = math.max(cx, math.min(sx0, cx + cw))
    sx1 = math.max(cx, math.min(sx1, cx + cw))
    if sx1 - sx0 > 1 then
      ImGui.DrawList_AddRectFilled(dl, sx0, wy, sx1, wy + wh, FUNC.dim_c(FUNC.col2im(prefs.col_guide or 0x00E0E0F0, 40)))
      ImGui.DrawList_AddLine(dl, sx0, wy, sx0, wy + wh, guide_col, 1)
      ImGui.DrawList_AddLine(dl, sx1, wy, sx1, wy + wh, guide_col, 1)
    end
    -- preview播放頭 -- preview play cursor
    if wf_sel.play_t0 and wf_sel.preview_ids and #wf_sel.preview_ids > 0 then
      local elapsed = reaper.time_precise() - wf_sel.play_t0
      local ph_t = s0 + elapsed
      if ph_t >= s0 and ph_t <= s1 then
        local ph_x = cx + ((ph_t - view_start) / view_dur) * cw
        if ph_x >= cx and ph_x <= cx + cw then
          ImGui.DrawList_AddLine(dl, ph_x, wy, ph_x, wy + wh, guide_col, 2)
          local tri_sz = FUNC.sz(5)
          ImGui.DrawList_AddTriangleFilled(dl, ph_x - tri_sz, wy - tri_sz, ph_x + tri_sz, wy - tri_sz, ph_x, wy, guide_col)
        end
      else
        for _,pid in ipairs(wf_sel.preview_ids) do FUNC.pv_stop(pid) end
        wf_sel.preview_ids = nil; wf_sel.play_t0 = nil
      end
    end
    -- 選取範圍長度：矩形下邊外面 -- selection duration below waveform
    local sel_dur = s1 - s0
    local dur_m = math.floor(sel_dur / 60)
    local dur_s = sel_dur - dur_m * 60
    local dur_label = sel_dur < 1 and string.format("%.2fs", sel_dur)
      or dur_m > 0 and string.format("%d:%04.1f", dur_m, dur_s)
      or string.format("%.1fs", dur_s)
    ImGui.PushFont(ctx, FONT_MONO, FUNC.sz(10))
    local dur_tw, dur_th = ImGui.CalcTextSize(ctx, dur_label, 0, 0)
    local sel_cx = (sx0 + sx1) / 2
    local dur_x = math.max(cx, math.min(sel_cx - dur_tw / 2, cx + cw - dur_tw))
    ImGui.DrawList_AddText(dl, dur_x, wy + wh + FUNC.sz(2), guide_col, dur_label)
    ImGui.PopFont(ctx)
  end
  -- Edit cursor：1Hz 閃爍黃線 -- blinking yellow edit cursor
  if gc._edit_cursor_t and gc._edit_cursor_t >= view_start and gc._edit_cursor_t <= view_end then
    local ec_x = cx + ((gc._edit_cursor_t - view_start) / view_dur) * cw
    local phase = reaper.time_precise() % 1.0
    local alpha = (phase < 0.6) and 220 or 90
    local ec_col = FUNC.rgba(255, 220, 60, alpha)
    ImGui.DrawList_AddLine(dl, ec_x, wy, ec_x, wy + wh, ec_col, 2)
    ImGui.DrawList_AddTriangleFilled(dl, ec_x - FUNC.sz(4), wy - FUNC.sz(6),
                                          ec_x + FUNC.sz(4), wy - FUNC.sz(6),
                                          ec_x,              wy, ec_col)
  end

  -- 指引線+timecode（GROUP也顯示）-- guide line + timecode for GROUP waveform
  -- A4: drag/pan時也顯示 -- show during drag/pan too
  if in_area then
    ImGui.DrawList_AddLine(dl, mx, wy, mx, wy + wh, guide_col, 1)
    -- timecode在矩形上邊外面 -- timecode above waveform rectangle
    local mouse_t = view_start + ((mx - cx) / cw) * view_dur
    local m_tc = math.floor(mouse_t / 60)
    local s_tc = mouse_t - m_tc * 60
    local tc_label = string.format("%d:%04.1f", m_tc, s_tc)
    ImGui.PushFont(ctx, FONT_MONO, FUNC.sz(10))
    local tc_tw, tc_th = ImGui.CalcTextSize(ctx, tc_label, 0, 0)
    local tc_x = math.max(cx, math.min(mx - tc_tw / 2, cx + cw - tc_tw))
    ImGui.DrawList_AddText(dl, tc_x, wy - tc_th - FUNC.sz(2), guide_col, tc_label)
    ImGui.PopFont(ctx)
  end

  -- === GROUP MARKERS === -- GROUP時間標記
  local g_markers = gc.markers or {}
  local gmk_tri = FUNC.sz(5)
  local gmk_y = wy - FUNC.sz(2)
  for mi, mt in ipairs(g_markers) do
    local mt_v = gprefix + mt
    if mt_v >= view_start and mt_v <= view_end then
      local gmk_x = cx + ((mt_v - view_start) / view_dur) * cw
      ImGui.DrawList_AddTriangleFilled(dl,
        gmk_x - gmk_tri, gmk_y - gmk_tri * 2,
        gmk_x + gmk_tri, gmk_y - gmk_tri * 2,
        gmk_x, gmk_y, FUNC.dim_c(FUNC.rgba(255, 160, 60, 220)))
      ImGui.PushFont(ctx, FONT_MONO, FUNC.sz(9))
      local gmk_label = FUNC.fmt_t(mt)
      local gmk_tw, gmk_th = ImGui.CalcTextSize(ctx, gmk_label, 0, 0)
      local gmk_lx = FUNC.clamp(gmk_x - gmk_tw / 2, cx, cx + cw - gmk_tw)
      ImGui.DrawList_AddText(dl, gmk_lx, gmk_y - gmk_tri * 2 - gmk_th - 1, FUNC.dim_c(FUNC.rgba(255, 180, 80, 200)), gmk_label)
      ImGui.PopFont(ctx)
      local gmk_hov = ImGui.IsMouseHoveringRect(ctx, gmk_x - gmk_tri - 2, gmk_y - gmk_tri * 2 - gmk_th - 2, gmk_x + gmk_tri + 2, gmk_y + 1)
      -- Opt+左鍵刪除 -- Alt+click to delete
      if gmk_hov and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left()) and ImGui.IsKeyDown(ctx, ImGui.Mod_Alt()) then
        table.remove(g_markers, mi); gc.markers = g_markers; FUNC.save_cues(); break
      end
      -- 右鍵選單 -- right-click context menu
      if gmk_hov and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right()) then
        wf_markers._g_rclick = {cue=gc, mi=mi, mt=mt, id="##gmk_ctx_"..gc.id}
        ImGui.OpenPopup(ctx, wf_markers._g_rclick.id)
      end
    end
  end
  -- GROUP marker右鍵popup -- GROUP marker right-click popup
  if wf_markers._g_rclick and wf_markers._g_rclick.cue == gc then
    local rc = wf_markers._g_rclick
    if ImGui.BeginPopup(ctx, rc.id) then
      -- Copy Timecode
      if ImGui.Selectable(ctx, "Copy Timecode") then
        ImGui.SetClipboardText(ctx, FUNC.fmt_t(rc.mt))
      end
      ImGui.Separator(ctx)
      -- Delete Marker
      if ImGui.Selectable(ctx, "Delete Marker") then
        if rc.mi >= 1 and rc.mi <= #(gc.markers or {}) then
          table.remove(gc.markers, rc.mi); FUNC.save_cues()
        end
      end
      ImGui.EndPopup(ctx)
    else
      wf_markers._g_rclick = nil
    end
  end

  -- === GROUP MARKER + LOCATE BUTTONS === -- 右上角marker/locate按鈕
  local gmbtn_sz = FUNC.sz(16)
  local gmbtn_gap = FUNC.sz(3)
  local gmbtn_y = wy - tab_h_val - FUNC.sz(4)  -- 與trim start handle同水平 -- same Y as trim start handle
  local gloc_x = cx + cw - gmbtn_sz
  local gmk_btn_x = gloc_x - gmbtn_sz - gmbtn_gap

  local function gwf_btn(bx, by, label, col_n, col_h, enabled)
    local bhov = ImGui.IsMouseHoveringRect(ctx, bx, by, bx + gmbtn_sz, by + gmbtn_sz)
    local bcol = (bhov and enabled) and col_h or (enabled and col_n or FUNC.rgba(40, 40, 50))
    ImGui.DrawList_AddRectFilled(dl, bx, by, bx + gmbtn_sz, by + gmbtn_sz, FUNC.dim_c(bcol), 3)
    local ltw, lth = ImGui.CalcTextSize(ctx, label, 0, 0)
    local tcol = enabled and FUNC.dim_c(C.text) or FUNC.dim_c(FUNC.rgba(80, 80, 90))
    ImGui.DrawList_AddText(dl, bx + (gmbtn_sz - ltw) / 2, by + (gmbtn_sz - lth) / 2, tcol, label)
    if bhov and enabled and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left()) then return true end
    return false
  end

  -- GROUP playing判定：自身running 或 任一child正在播放 -- GROUP playing: self running or any child active
  local g_is_playing = false
  local g_play_t0 = gc.play_t0 or 0
  if gc.state == STATE.RUNNING and g_play_t0 > 0 then
    g_is_playing = true
  else
    for _, ch in ipairs(gc.children or {}) do
      if ch >= 1 and ch <= #cues then
        local cc = cues[ch]
        if cc.state == STATE.RUNNING or cc.state == STATE.PREWAIT or cc.state == STATE.POSTWAIT then
          g_is_playing = true
          if cc.play_t0 and cc.play_t0 > 0 and (g_play_t0 == 0 or cc.play_t0 < g_play_t0) then
            g_play_t0 = cc.play_t0  -- 用最早的child play_t0 -- use earliest child play_t0
          end
          break
        end
      end
    end
  end
  -- Marker按鈕 -- marker button
  if gwf_btn(gmk_btn_x, gmbtn_y, "M", FUNC.rgba(60, 50, 30), FUNC.rgba(100, 80, 40), g_is_playing) then
    -- marker 存 lane 正座標 (g_ts + elapsed)，配合 display 端 +gprefix → virtual 座標
    -- store as positive lane coord so display +gprefix gives correct virtual position
    local g_ph_t = (gc.trim_start or 0) + (reaper.time_precise() - g_play_t0)
    if not gc.markers then gc.markers = {} end
    gc.markers[#gc.markers + 1] = g_ph_t
    table.sort(gc.markers)
    FUNC.save_cues()
  end
  -- Locate按鈕 -- locate button
  if gwf_btn(gloc_x, gmbtn_y, "L", FUNC.rgba(30, 50, 60), FUNC.rgba(40, 80, 100), g_is_playing) then
    local g_ph_t = (gc.trim_start or 0) + (reaper.time_precise() - g_play_t0)
    local target_pos = (gprefix + g_ph_t) - view_dur * 0.05  -- virtual coord
    view.pos_target = FUNC.clamp(target_pos, 0, math.max(0, total_dur - view_dur))
  end

  -- 縮放按鈕 -- zoom buttons
  local btn_sz = FUNC.sz(16)
  local btn_gap_z = FUNC.sz(3)
  -- skip_ruler (scroll 模式)：釘在 viewport 底部（ruler 上方）-- viewport bottom in scroll mode
  local btn_y
  if skip_ruler then
    local scr_y = ImGui.GetScrollY(ctx)
    local vp_h = ImGui.GetWindowHeight(ctx)
    btn_y = cy + scr_y + vp_h - btn_sz - FUNC.sz(4)
  else
    btn_y = wy + wh - btn_sz - FUNC.sz(4)
  end
  local btn_x_minus = cx + cw - btn_sz * 3 - btn_gap_z * 2 - FUNC.sz(4)
  local btn_x_reset = btn_x_minus + btn_sz + btn_gap_z
  local btn_x_plus = btn_x_reset + btn_sz + btn_gap_z
  local function zbtn(bx, by, label, col_n, col_h)
    local bhov = ImGui.IsMouseHoveringRect(ctx, bx, by, bx + btn_sz, by + btn_sz)
    local bcol = bhov and col_h or col_n
    ImGui.DrawList_AddRectFilled(dl, bx, by, bx + btn_sz, by + btn_sz, FUNC.dim_c(bcol), 3)
    local ltw, lth = ImGui.CalcTextSize(ctx, label, 0, 0)
    ImGui.DrawList_AddText(dl, bx + (btn_sz - ltw) / 2, by + (btn_sz - lth) / 2, FUNC.dim_c(C.text), label)
    if bhov and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left()) then return true end
    return false
  end
  if zbtn(btn_x_minus, btn_y, "-", FUNC.rgba(50,50,70), FUNC.rgba(70,70,100)) then
    view.zoom = math.max(view.zoom / 1.5, 1)
  end
  if zbtn(btn_x_reset, btn_y, "R", FUNC.rgba(50,50,70), FUNC.rgba(70,70,100)) then
    view.zoom = 1; view.pos = 0; view.v_zoom = 1
  end
  if zbtn(btn_x_plus, btn_y, "+", FUNC.rgba(50,50,70), FUNC.rgba(70,70,100)) then
    local center_t = view_start + view_dur / 2
    view.zoom = math.min(view.zoom * 1.5, 200)
    local new_vd = total_dur / view.zoom
    view.pos = FUNC.clamp(center_t - new_vd / 2, 0, math.max(0, total_dur - new_vd))
  end
end
