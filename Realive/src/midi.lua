-- ==========================================================================
-- midi.lua — MIDI cue helpers (Phase 2A: item-based prototype playback)
-- ==========================================================================
-- MIDI item 作為原型(不動到 transport)，每幀由 cleanup.lua 依 pending queue 排程送出
-- MIDI item as prototype (doesn't touch transport); cleanup.lua fires pending events per-frame

---------------------------------------------------------------------
-- 1. Channel 解析：字串 "1,2,3,5,9" → 0-based list {0,1,2,4,8}
---------------------------------------------------------------------
function FUNC.midi_parse_channels(s)
  local t = {}
  local seen = {}
  for tok in tostring(s or "1"):gmatch("([^,%s]+)") do
    local n = tonumber(tok)
    if n and n >= 1 and n <= 16 and not seen[n] then
      seen[n] = true
      t[#t+1] = n - 1  -- 0-based
    end
  end
  if #t == 0 then t[1] = 0 end  -- 預設 channel 1 -- fallback to ch 1
  return t
end

---------------------------------------------------------------------
-- 2. StuffMIDIMessage mode 計算：internal=0 (VKB), external=16+device
---------------------------------------------------------------------
function FUNC.midi_mode_val(c)
  -- Phase 5: device=-1 代表 Internal (VKB)，否則為外部裝置 idx
  -- device=-1 sentinel = VKB route; else external device idx
  local d = c.midi_device
  if d == nil or d < 0 then return 0 end
  return 16 + d
end

---------------------------------------------------------------------
-- 3. 從 cue 的 midi_item_guid 找 item + take
---------------------------------------------------------------------
function FUNC.midi_get_item_take(c)
  if not c or not c.midi_item_guid or c.midi_item_guid == "" then return nil, nil end
  local guid = c.midi_item_guid
  -- 在專案中搜尋 item GUID -- scan project for item matching GUID
  local n = reaper.CountMediaItems(0)
  for i = 0, n - 1 do
    local it = reaper.GetMediaItem(0, i)
    local _, ig = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    if ig == guid then
      local take = reaper.GetActiveTake(it)
      if take and reaper.TakeIsMIDI(take) then return it, take end
      return it, nil  -- item 存在但沒有 MIDI take
    end
  end
  return nil, nil  -- 找不到
end

---------------------------------------------------------------------
-- 4. 讀取 MIDI item 的 events → {notes={...}, ccs={...}, dur_qn=..}
--    時間以 QN (quarter notes, 相對 item 起點) 儲存，之後由 BPM 換算秒數
---------------------------------------------------------------------
function FUNC.midi_read_events(c)
  local it, tk = FUNC.midi_get_item_take(c)
  if not tk then return {notes={}, ccs={}, dur_qn=0, valid=false} end
  local notes, ccs = {}, {}

  -- item 起點 PPQ (用於把事件 PPQ 轉為相對 item 起點的 QN)
  local item_pos_s = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local item_len_s = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  local item_start_ppq = reaper.MIDI_GetPPQPosFromProjTime(tk, item_pos_s)
  local item_end_ppq = reaper.MIDI_GetPPQPosFromProjTime(tk, item_pos_s + item_len_s)
  local item_start_qn = reaper.MIDI_GetProjQNFromPPQPos(tk, item_start_ppq)
  local item_end_qn = reaper.MIDI_GetProjQNFromPPQPos(tk, item_end_ppq)
  local dur_qn = math.max(0, item_end_qn - item_start_qn)

  -- Notes — 濾掉完全落在可見範圍外的 note（respect item 的 trim）
  -- filter out notes entirely outside visible range [0, dur_qn]
  local _, note_cnt, cc_cnt = reaper.MIDI_CountEvts(tk)
  for ni = 0, note_cnt - 1 do
    local _, _, muted, s_ppq, e_ppq, ch, pitch, vel = reaper.MIDI_GetNote(tk, ni)
    if not muted then
      local s_qn = reaper.MIDI_GetProjQNFromPPQPos(tk, s_ppq) - item_start_qn
      local e_qn = reaper.MIDI_GetProjQNFromPPQPos(tk, e_ppq) - item_start_qn
      if e_qn > 0 and s_qn < dur_qn then
        notes[#notes+1] = {t_qn = s_qn, len_qn = math.max(0.001, e_qn - s_qn),
                           ch = ch, note = pitch, vel = vel, raw_idx = ni}
      end
    end
  end
  -- CCs — 濾掉可見範圍外的 CC -- filter CCs outside visible range
  for ci = 0, cc_cnt - 1 do
    local _, _, muted, ppq, chanmsg, ch, msg2, msg3 = reaper.MIDI_GetCC(tk, ci)
    if not muted then
      local t_qn = reaper.MIDI_GetProjQNFromPPQPos(tk, ppq) - item_start_qn
      if t_qn >= 0 and t_qn <= dur_qn then
        ccs[#ccs+1] = {t_qn = t_qn, chanmsg = chanmsg, ch = ch, msg2 = msg2, msg3 = msg3, raw_idx = ci}
      end
    end
  end
  return {notes=notes, ccs=ccs, dur_qn=dur_qn, valid=true}
end

---------------------------------------------------------------------
-- 5. 建立 pending queue：依 cue_bpm 換算時間，廣播到 midi_channels，套用 vel_pct
--    回傳 {events={...}, dur_sec=...}，events 按 t 排序
--    event: {t=秒, type="on"|"off"|"cc", mv, ch, d1, d2}
---------------------------------------------------------------------
function FUNC.midi_build_pending(c)
  local evt = FUNC.midi_read_events(c)
  if not evt.valid then return {events={}, dur_sec=0} end
  local bpm = math.max(1, c.midi_bpm or 120)
  local qn_to_sec = 60.0 / bpm
  local vel_mul = math.max(0, (c.midi_vel_pct or 100) / 100)
  local channels = FUNC.midi_parse_channels(c.midi_channels or "1")
  local mv = FUNC.midi_mode_val(c)
  local events = {}

  local full_dur_sec = evt.dur_qn * qn_to_sec
  -- realive 內部 trim（不動 midi item 本身）；優先讀巢狀 GROUP trim 注入的 _rt_trim_*
  -- realive-internal trim; prefer _rt_trim_* injected by parent GROUP trim (matches engine.lua:118)
  local ts_raw = c._rt_trim_start or c.trim_start or 0
  local te_raw = c._rt_trim_end or c.trim_end
  c._rt_trim_start = nil; c._rt_trim_end = nil  -- 用完即清 -- clear after use
  local ts = math.max(0, ts_raw)
  local te = (te_raw and te_raw > 0) and math.min(full_dur_sec, te_raw) or full_dur_sec
  if te < ts then te = ts end
  local dur_sec = math.max(0, te - ts)
  for _, n in ipairs(evt.notes) do
    local n_on  = n.t_qn * qn_to_sec
    local n_off = (n.t_qn + n.len_qn) * qn_to_sec
    -- 夾到 [ts, te]：跨越邊界的 note 從 ts 補 note-on（延音保留）
    -- clamp to trim range; notes straddling ts get a note-on at boundary (sustain continuation)
    local t_on  = math.max(ts, n_on)
    local t_off = math.min(te, n_off)
    if t_off - t_on > 0.001 then
      local v = math.floor(math.max(1, math.min(127, n.vel * vel_mul + 0.5)))
      local o_on, o_off = t_on - ts, t_off - ts
      for _, ch in ipairs(channels) do
        events[#events+1] = {t=o_on,  type="on",  mv=mv, ch=ch, d1=n.note, d2=v}
        events[#events+1] = {t=o_off, type="off", mv=mv, ch=ch, d1=n.note, d2=0}
      end
    end
  end
  for _, cc in ipairs(evt.ccs) do
    local t = cc.t_qn * qn_to_sec
    if t >= ts and t <= te then
      for _, ch in ipairs(channels) do
        events[#events+1] = {t=t-ts, type="cc", mv=mv, ch=ch, chanmsg=cc.chanmsg, d1=cc.msg2, d2=cc.msg3}
      end
    end
  end
  table.sort(events, function(a,b)
    if a.t == b.t then
      -- note off 放在 note on 前 (若同時間) 避免黏音 -- note off before on at same time to avoid hanging
      local ra = (a.type == "off") and 0 or 1
      local rb = (b.type == "off") and 0 or 1
      return ra < rb
    end
    return a.t < b.t
  end)
  return {events=events, dur_sec=dur_sec}
end

---------------------------------------------------------------------
-- 5b. Message mode: 由 c.midi_msgs 表格直接建 events
--     events 全部 t=0（press 模式拆 on@0 + off@press_sec），duration 由 c.midi_duration 決定
-- Build pending events from message-mode rows. All at t=0; press splits to on@0/off@press_sec.
---------------------------------------------------------------------
function FUNC.midi_build_pending_message(c)
  local events = {}
  local mv = FUNC.midi_mode_val(c)
  for _, m in ipairs(c.midi_msgs or {}) do
    -- use_all=true 直接廣播 16 channel；否則用 ch_mask -- use_all overrides ch_mask
    local mask = m.use_all and 0xFFFF or (tonumber(m.ch_mask) or 1)
    if mask <= 0 then mask = 1 end
    local tp = m.type or "note"
    local ev = math.max(0, math.min(127, tonumber(m.event) or 0))
    local va = math.max(0, math.min(127, tonumber(m.value) or 0))
    local press_sec = math.max(0, (tonumber(m.press_ms) or 100) / 1000)
    -- iterate set bits 0..15 → channels 1..16 -- broadcast to all selected channels
    for ch = 0, 15 do
      if (mask & (1 << ch)) ~= 0 then
        if tp == "note" then
          if m.msg == "off" then
            events[#events+1] = {t=0, type="off", mv=mv, ch=ch, d1=ev, d2=0}
          elseif m.msg == "press" then
            events[#events+1] = {t=0,         type="on",  mv=mv, ch=ch, d1=ev, d2=va}
            events[#events+1] = {t=press_sec, type="off", mv=mv, ch=ch, d1=ev, d2=0}
          else  -- "on"
            events[#events+1] = {t=0, type="on", mv=mv, ch=ch, d1=ev, d2=va}
          end
        elseif tp == "cc" then
          events[#events+1] = {t=0, type="cc", mv=mv, ch=ch, chanmsg=0xB0, d1=ev, d2=va}
        elseif tp == "pc" then
          events[#events+1] = {t=0, type="cc", mv=mv, ch=ch, chanmsg=0xC0, d1=ev, d2=0}
        end
      end
    end
  end
  table.sort(events, function(a,b)
    if a.t == b.t then
      local ra = (a.type == "off") and 0 or 1
      local rb = (b.type == "off") and 0 or 1
      return ra < rb
    end
    return a.t < b.t
  end)
  local last_t = 0
  for _, e in ipairs(events) do if e.t > last_t then last_t = e.t end end
  local dur_sec = math.max(last_t, tonumber(c.midi_duration) or 0)
  return {events=events, dur_sec=dur_sec}
end

---------------------------------------------------------------------
-- 6. Fire 一個 event: StuffMIDIMessage
---------------------------------------------------------------------
function FUNC.midi_fire_event(e)
  if e.type == "on" then
    reaper.StuffMIDIMessage(e.mv, 0x90 + e.ch, e.d1, e.d2)
  elseif e.type == "off" then
    reaper.StuffMIDIMessage(e.mv, 0x80 + e.ch, e.d1, 0)
  elseif e.type == "cc" then
    -- 用原始 chanmsg 上半 (CC=0xB0, PC=0xC0, etc.)
    local status = (e.chanmsg or 0xB0) + e.ch
    reaper.StuffMIDIMessage(e.mv, status, e.d1 or 0, e.d2 or 0)
  end
end

---------------------------------------------------------------------
-- 7. Track arm 管理（internal 模式用）
--    存舊 arm 狀態後 arm 本 track；結束時還原
---------------------------------------------------------------------
-- 借用中的 MIDI cue：{[cue_id] = track_guid} -- MIDI cues currently holding an arm: {[cue_id] = track_guid}
_midi_arm_backup = _midi_arm_backup or {}
-- 所有軌道「原本」的 arm/monitor/input，只在第一個 MIDI cue 開始時拍一次，最後一個結束時還原。
-- （舊做法每個 cue 各拍一份：兩個 cue 重疊時，第二份拍到的已是被改過的狀態，還原就會錯。）
-- The ORIGINAL arm/monitor/input of every track, taken once when the first MIDI cue starts and restored when the last one ends.
-- (Before, every cue took its own snapshot: with two overlapping cues the second snapshot already contained the
--  modified state, so the restore came out wrong.)
local _arm_orig = nil

-- MIDI 輸入編碼：4096 | (device<<5) | channel；device=63=all MIDI inputs, channel=0=all
-- MIDI input encoding: 4096 | (dev<<5) | ch; dev=63=all inputs, ch=0=all
local MIDI_INPUT_ALL = 4096 | (63 << 5) | 0  -- = 6112

local function proj_ok(p) return p and (not reaper.ValidatePtr2 or reaper.ValidatePtr2(0, p, "ReaProject*")) end

function FUNC.midi_arm_track(c)
  -- Phase 5: device<0 (Internal/VKB route) 才 arm；相容舊 mode="internal" -- only for Internal dest, legacy-safe
  local is_internal = ((c.midi_device or -1) < 0) or c.midi_mode == "internal"
  if not is_internal then return end
  if not c.track_guid or c.track_guid == "" then return end
  local ti = FUNC.guid_to_idx(c.track_guid)
  if ti < 0 then return end
  local tr = reaper.GetTrack(0, ti)
  if not tr then return end
  if not _arm_orig then
    -- 第一個 MIDI cue：快照所有 track 的 arm/monitor/input，然後全部 disarm（避免 VKB 廣播到其他 track）
    -- first MIDI cue: snapshot arm/monitor/input of all tracks, then disarm them all (so the VKB doesn't reach other tracks)
    local backup = {}
    local cur = reaper.EnumProjects(-1, "")
    local n = reaper.CountTracks(0)
    for i = 0, n - 1 do
      local t = reaper.GetTrack(0, i)
      local _, guid = reaper.GetSetMediaTrackInfo_String(t, "GUID", "", false)
      backup[#backup+1] = {
        proj  = cur,
        guid  = guid,
        armed = reaper.GetMediaTrackInfo_Value(t, "I_RECARM"),
        mon   = reaper.GetMediaTrackInfo_Value(t, "I_RECMON"),
        rin   = reaper.GetMediaTrackInfo_Value(t, "I_RECINPUT"),
      }
      reaper.SetMediaTrackInfo_Value(t, "I_RECARM", 0)
    end
    -- C14: 同步快照 + 暫時 disarm 其他 project 的所有 armed track，避免 VKB 訊號跨 project 廣播
    -- C14: snapshot + temporarily disarm armed tracks in OTHER open projects to block cross-project VKB leak
    local pi = 0
    while true do
      local p = reaper.EnumProjects(pi, "")
      if not p then break end
      if p ~= cur then
        local pn = reaper.CountTracks(p)
        for i = 0, pn - 1 do
          local t = reaper.GetTrack(p, i)
          if t and reaper.GetMediaTrackInfo_Value(t, "I_RECARM") == 1 then
            local _, g = reaper.GetSetMediaTrackInfo_String(t, "GUID", "", false)
            backup[#backup+1] = { proj=p, guid=g, armed=1,
                                  mon=reaper.GetMediaTrackInfo_Value(t, "I_RECMON"),
                                  rin=reaper.GetMediaTrackInfo_Value(t, "I_RECINPUT") }
            reaper.SetMediaTrackInfo_Value(t, "I_RECARM", 0)
          end
        end
      end
      pi = pi + 1
    end
    _arm_orig = backup
  end
  -- D_VOL 由 env_save_track 統一處理（重置為 1.0 + route 切到 hw send）
  -- master_vol 透過 apply_master_sends 即時更新 hw send 音量
  _midi_arm_backup[c.id] = c.track_guid
  -- arm 本 track + monitor on + 強制 MIDI all-input/all-channel（原值就算是 MIDI，device/channel 對不上仍會沒聲）
  -- arm this track + monitor on + force MIDI all-input/all-channel (a prior MIDI input may target the wrong device/ch)
  reaper.SetMediaTrackInfo_Value(tr, "I_RECARM", 1)
  reaper.SetMediaTrackInfo_Value(tr, "I_RECMON", 1)
  reaper.SetMediaTrackInfo_Value(tr, "I_RECINPUT", MIDI_INPUT_ALL)
end

function FUNC.midi_unarm_track(c)
  local guid = _midi_arm_backup[c.id]
  if not guid then return end
  _midi_arm_backup[c.id] = nil
  if next(_midi_arm_backup) then
    -- 還有別的 MIDI cue 在跑：只把自己的軌道 disarm（除非別的 cue 也用同一軌），原始狀態等最後一個結束再還原
    -- other MIDI cues still running: only disarm our own track (unless another cue uses it); originals come back with the last one
    local shared = false
    for _, g in pairs(_midi_arm_backup) do if g == guid then shared = true; break end end
    if not shared then
      local tr = reaper.BR_GetMediaTrackByGUID(0, guid)
      if tr then reaper.SetMediaTrackInfo_Value(tr, "I_RECARM", 0) end
    end
  elseif _arm_orig then
    for _, b in ipairs(_arm_orig) do
      local tr = reaper.BR_GetMediaTrackByGUID(proj_ok(b.proj) and b.proj or 0, b.guid)
      if tr then
        reaper.SetMediaTrackInfo_Value(tr, "I_RECARM",   b.armed)
        reaper.SetMediaTrackInfo_Value(tr, "I_RECMON",   b.mon)
        reaper.SetMediaTrackInfo_Value(tr, "I_RECINPUT", b.rin)
      end
    end
    _arm_orig = nil
  end
  -- track 狀態 + routing 還原統一交給 env_restore_track（含 refcount/unlock/route_disengage）
  -- defer track + routing restore to env_restore_track (refcount/unlock/route handled there)
  FUNC.env_restore_track(c)
end

---------------------------------------------------------------------
-- 8. 停止 MIDI cue：把 pending queue 裡剩下的 note off 全部立即送出
--    (CC 不補送，因為 CC 是狀態設定；使用者若要還原應自己送對應 CC)
---------------------------------------------------------------------
function FUNC.midi_stop_cue(c)
  if c.type ~= "MIDI" then return end
  local pend = c._midi_pending
  if pend then
    for _, e in ipairs(pend) do
      if e.type == "off" then FUNC.midi_fire_event(e) end
    end
    c._midi_pending = nil
  end
  -- legacy 單音 cue: 補送舊版 midi_note_off 的行為 -- legacy single-note note-off
  if c._midi_off_mode and c._midi_off_ch and c._midi_off_note then
    reaper.StuffMIDIMessage(c._midi_off_mode, 0x80 + c._midi_off_ch, c._midi_off_note, 0)
    c._midi_off_mode = nil; c._midi_off_ch = nil; c._midi_off_note = nil
  end
  FUNC.midi_unarm_track(c)
end

---------------------------------------------------------------------
-- 9. 在 track 上建立新的空 MIDI item (放在最後一個 item 之後)
--    回傳 item_guid (字串)，失敗回傳 ""
---------------------------------------------------------------------
-- "Q N - " prefix helpers (item name auto-tagging) — used by 9/10/11
function FUNC.midi_strip_q_prefix(name)
  if not name or name == "" then return "" end
  return (name:gsub("^Q [^%-]+%- ", ""))
end

-- 找指向某 guid 的 cue（owner，必為 1 個或 0 個，因 assign 自動複製避免共享）
local function find_owner_cue(guid)
  if not guid or guid == "" then return nil end
  for _, oc in ipairs(cues) do if oc.midi_item_guid == guid then return oc end end
  return nil
end

local function find_item_by_guid(guid)
  if not guid or guid == "" then return nil end
  local n = reaper.CountMediaItems(0)
  for i = 0, n - 1 do
    local it = reaper.GetMediaItem(0, i)
    local _, gid = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    if gid == guid then return it end
  end
  return nil
end

-- 根據是否有 owner 決定 take name 是否帶 prefix
function FUNC.midi_refresh_prefix_for_guid(guid)
  local item = find_item_by_guid(guid)
  if not item then return end
  local tk = reaper.GetActiveTake(item)
  if not tk then return end
  local _, cur = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
  local base = FUNC.midi_strip_q_prefix(cur or "")
  local owner = find_owner_cue(guid)
  local want = owner and string.format("Q %s - %s", tostring(owner.cue_number or "?"), base) or base
  if want ~= cur then
    reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", want, true)
    reaper.UpdateItemInProject(item)
  end
end

---------------------------------------------------------------------
-- 複製 src_guid 對應的 MIDI item 到 tr（事件 + take 名稱），回傳新 item 的 GUID
-- duplicate MIDI item (events + take name) onto tr; returns new item's GUID
function FUNC.midi_duplicate_item(src_guid, tr)
  if not tr or not src_guid or src_guid == "" then return "" end
  local src_it
  local n = reaper.CountMediaItems(0)
  for i = 0, n - 1 do
    local it = reaper.GetMediaItem(0, i)
    local _, gid = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    if gid == src_guid then src_it = it; break end
  end
  if not src_it then return "" end
  local src_tk = reaper.GetActiveTake(src_it)
  if not src_tk or not reaper.TakeIsMIDI(src_tk) then return "" end

  -- 目標位置：tr 上最後一個 item 結尾 +0.5s
  -- target position: 0.5s after last item on tr
  local n_tr = reaper.CountTrackMediaItems(tr)
  local start_t = 0
  for i = 0, n_tr - 1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    local e = reaper.GetMediaItemInfo_Value(it, "D_POSITION") + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if e > start_t then start_t = e end
  end
  if start_t > 0 then start_t = start_t + 0.5 end

  local src_len = reaper.GetMediaItemInfo_Value(src_it, "D_LENGTH")
  local new_item = reaper.CreateNewMIDIItemInProj(tr, start_t, start_t + src_len, false)
  if not new_item then return "" end
  local new_tk = reaper.GetActiveTake(new_item)
  if not new_tk then return "" end

  -- 事件複製 -- copy events
  local ok, evts = reaper.MIDI_GetAllEvts(src_tk, "")
  if ok and evts then reaper.MIDI_SetAllEvts(new_tk, evts) end

  -- take 名稱複製：strip "Q N - " prefix，加 "*" 後綴 -- copy take name (strip prefix, append *)
  local _, src_name = reaper.GetSetMediaItemTakeInfo_String(src_tk, "P_NAME", "", false)
  if src_name and src_name ~= "" then
    local base = FUNC.midi_strip_q_prefix(src_name)
    reaper.GetSetMediaItemTakeInfo_String(new_tk, "P_NAME", base .. "*", true)
  end

  reaper.MIDI_Sort(new_tk)
  reaper.UpdateItemInProject(new_item)

  local _, new_guid = reaper.GetSetMediaItemInfo_String(new_item, "GUID", "", false)
  return new_guid or ""
end

-- 指派 guid 給 cue；若 guid 已被其他 cue 共用，自動複製成獨立 item 避免修改互相污染
-- assign guid to cue; auto-duplicate if guid is shared with another cue (prevent cross-pollution)
function FUNC.midi_assign_unique_guid(c, guid)
  if not c then return "" end
  local old_guid = c.midi_item_guid
  if not guid or guid == "" then
    c.midi_item_guid = ""
    if old_guid and old_guid ~= "" then FUNC.midi_refresh_prefix_for_guid(old_guid) end
    return ""
  end
  -- 檢查是否被其他 cue 占用 -- check if any other cue holds this guid
  local shared = false
  for _, oc in ipairs(cues) do
    if oc ~= c and oc.midi_item_guid == guid then shared = true; break end
  end
  local final_guid = guid
  if shared then
    -- 需複製：取得 cue 的 track -- need duplicate: resolve cue's track
    local tr = nil
    if c.track_guid and c.track_guid ~= "" then
      local tidx = FUNC.guid_to_idx(c.track_guid)
      if tidx and tidx >= 0 then tr = reaper.GetTrack(0, tidx) end
    end
    if tr then
      local new_guid = FUNC.midi_duplicate_item(guid, tr)
      if new_guid ~= "" then final_guid = new_guid end
    end
  end
  c.midi_item_guid = final_guid
  if old_guid and old_guid ~= "" and old_guid ~= final_guid then FUNC.midi_refresh_prefix_for_guid(old_guid) end
  FUNC.midi_refresh_prefix_for_guid(final_guid)
  return final_guid
end

function FUNC.midi_create_blank_item(tr, length_sec)
  if not tr then return "" end
  local length = length_sec or 2.0
  -- 找 track 上最後一個 item 的結束時間 -- find last item end on track
  local n = reaper.CountTrackMediaItems(tr)
  local start_t = 0
  for i = 0, n - 1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    local e = pos + len
    if e > start_t then start_t = e end
  end
  if start_t > 0 then start_t = start_t + 0.5 end  -- 間隔 0.5s
  local item = reaper.CreateNewMIDIItemInProj(tr, start_t, start_t + length, false)
  if not item then return "" end
  local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
  return guid or ""
end

---------------------------------------------------------------------
-- 9b. 依 cue 的 midi_item_guid + midi_bpm 計算即時 duration（秒）
--     用於 cue 表 idle 狀態的 duration 顯示，與 item 編輯同步
-- Compute live cue duration from the linked midi item length + cue bpm.
---------------------------------------------------------------------
-- 9b'. 未套 trim 的 item 總秒數（for UI 顯示上限）-- full item duration without trim, for UI max
function FUNC.midi_calc_full_dur_sec(c)
  local it, tk = FUNC.midi_get_item_take(c)
  if not tk then return 0 end
  local pos_s = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local len_s = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  local sp = reaper.MIDI_GetPPQPosFromProjTime(tk, pos_s)
  local ep = reaper.MIDI_GetPPQPosFromProjTime(tk, pos_s + len_s)
  local sq = reaper.MIDI_GetProjQNFromPPQPos(tk, sp)
  local eq = reaper.MIDI_GetProjQNFromPPQPos(tk, ep)
  local dur_qn = math.max(0, eq - sq)
  local bpm = math.max(1, c.midi_bpm or 120)
  return dur_qn * 60 / bpm
end

function FUNC.midi_calc_dur_sec(c)
  local full = FUNC.midi_calc_full_dur_sec(c)
  if full <= 0 then return 0 end
  -- 套用 realive 內部 trim（與 midi_build_pending 一致）-- apply realive-internal trim
  local ts = math.max(0, c.trim_start or 0)
  local te = (c.trim_end and c.trim_end > 0) and math.min(full, c.trim_end) or full
  return math.max(0, te - ts)
end

---------------------------------------------------------------------
-- 10. 列舉 track 上所有 MIDI item (供 Basic tab 下拉選單用)
--     回傳 {{guid=..., name=..., pos=..., len=..., notes=..., ccs=...}, ...}
---------------------------------------------------------------------
function FUNC.midi_list_items(tr)
  local out = {}
  if not tr then return out end
  local n = reaper.CountTrackMediaItems(tr)
  for i = 0, n - 1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    local tk = reaper.GetActiveTake(it)
    if tk and reaper.TakeIsMIDI(tk) then
      local _, guid = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
      local _, name = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
      local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      local _, note_cnt, cc_cnt = reaper.MIDI_CountEvts(tk)
      out[#out+1] = {guid=guid, name=name or "", pos=pos, len=len, notes=note_cnt, ccs=cc_cnt, item=it, take=tk}
    end
  end
  return out
end

---------------------------------------------------------------------
-- 11. 讀取 cue 對應 item 的摘要 (for UI display: "♪3 CC5")
---------------------------------------------------------------------
function FUNC.midi_item_summary(c)
  local it, tk = FUNC.midi_get_item_take(c)
  if not tk then return "(no item)" end
  local _, note_cnt, cc_cnt = reaper.MIDI_CountEvts(tk)
  local _, name = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
  local parts = {}
  if name and name ~= "" then parts[#parts+1] = name end
  if note_cnt > 0 then parts[#parts+1] = string.format("%dN", note_cnt) end
  if cc_cnt > 0 then parts[#parts+1] = string.format("%dC", cc_cnt) end
  if #parts == 0 then parts[#parts+1] = "(empty)" end
  return table.concat(parts, " ")
end
