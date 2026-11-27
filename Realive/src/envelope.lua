-- ==========================================================================
-- envelope.lua — Volume & Pan Envelope Engine
-- ==========================================================================

---------------------------------------------------------------------
-- ENVELOPE CONSTANTS -- envelope常數
---------------------------------------------------------------------
-- ENV_MIN_DB / ENV_MAX_DB: 從prefs動態取得，保留全域變數方便引用 -- derived from prefs
function FUNC.update_env_bounds() ENV_MIN_DB = prefs.vol_min; ENV_MAX_DB = prefs.vol_max end
ENV_MIN_DB = -72; ENV_MAX_DB = 12  -- 初始值，load_prefs後會更新 -- initial, updated after load_prefs
PAN_ENV_MIN = -1   -- pan envelope最左(-100%)
PAN_ENV_MAX = 1    -- pan envelope最右(+100%)
ENV_HIT_R = 8      -- 控制點點擊判定半徑(px) -- click hit radius
ENV_LINE_HIT = 5   -- 線段點擊判定距離(px) -- line click distance

---------------------------------------------------------------------
-- TRACK STATE (per-track reference counting) -- 軌道狀態(每軌引用計數)
---------------------------------------------------------------------
local _trk_state = {}  -- track_guid -> {count, orig={vol, mute, solo}} -- GUID-keyed for stability across track moves
local _global_locked = false  -- 全域 save/restore 生命週期旗標（不再鎖 track control，僅追蹤是否需 restore）
local _lock_suspended = false  -- MIDI cue 臨時 suspend 狀態（保留以維持 force/reapply 流程）
local _all_env_arms = {}      -- guid -> {env_idx -> arm_val} (所有track的envelope arm狀態)
env_drag = {active=false, pt_idx=nil,  -- envelope控制點拖曳狀態 (global給waveform用)
  edit_idx=nil, edit_buf="", edit_px=0, edit_py=0,  -- 右鍵編輯輸入框狀態
  sel={},  -- 選取的控制點 {[pt_idx]=true}
  lock=nil, origin_x=0, origin_y=0,  -- shift拖曳軸鎖定 "h"/"v"/nil, 起始座標
  marquee=false, mq_x1=0, mq_y1=0, mq_mode=nil, mq_snap={}}  -- 框選狀態: mode="set"/"add"/"toggle"

-- bypass單個envelope：存chunk+設ACT 0 -- bypass one envelope: save chunk + set ACT 0
local function bypass_env(tr, env_name)
  local env = reaper.GetTrackEnvelopeByName(tr, env_name)
  if not env then return nil end
  local ok, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
  if not ok then return nil end
  local new_chunk = chunk:gsub("\nACT 1", "\nACT 0", 1)  -- bypass envelope
  if new_chunk ~= chunk then
    reaper.SetEnvelopeStateChunk(env, new_chunk, false)
  end
  return chunk  -- 回傳原始chunk用於還原 -- return original for restore
end

-- 還原單個envelope chunk -- restore one envelope from saved chunk
local function restore_env(tr, env_name, orig_chunk)
  if not orig_chunk then return end
  local env = reaper.GetTrackEnvelopeByName(tr, env_name)
  if not env then return end
  reaper.SetEnvelopeStateChunk(env, orig_chunk, false)
end

-- 全域save：solo/mute 暫存 + envelope arm 狀態暫存（不再保存 track control lock）
-- save solo/mute via SWS slot + envelope arm states (track-control lock removed)
local function save_global_state()
  reaper.Main_OnCommand(reaper.NamedCommandLookup("_BR_SAVE_SOLO_MUTE_ALL_TRACKS_SLOT_10"), 0)
  reaper.Main_OnCommand(40339, 0)  -- unmute all tracks
  reaper.Main_OnCommand(40340, 0)  -- unsolo all tracks
  _all_env_arms = {}
  local tc = reaper.CountTracks(0)
  for ti = 0, tc - 1 do
    local tr = reaper.GetTrack(0, ti)
    if tr then
      local guid = reaper.GetTrackGUID(tr)
      local ecount = reaper.CountTrackEnvelopes(tr)
      if ecount > 0 then
        local arms = {}
        for ei = 0, ecount - 1 do
          local env = reaper.GetTrackEnvelope(tr, ei)
          if env then
            local ok, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
            if ok then
              local arm = chunk:match("\nARM (%d)")
              if arm then arms[ei] = tonumber(arm) end
            end
          end
        end
        if next(arms) then _all_env_arms[guid] = arms end
      end
    end
  end
end

-- 全域restore：還原 envelope arm + solo/mute（不再 unlock track control）
local function restore_global_state()
  local tc = reaper.CountTracks(0)
  for ti = 0, tc - 1 do
    local tr = reaper.GetTrack(0, ti)
    if tr then
      local guid = reaper.GetTrackGUID(tr)
      if _all_env_arms[guid] then
        local ecount = reaper.CountTrackEnvelopes(tr)
        for ei = 0, ecount - 1 do
          local saved_arm = _all_env_arms[guid][ei]
          if saved_arm and saved_arm == 1 then
            local env = reaper.GetTrackEnvelope(tr, ei)
            if env then
              local ok, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
              if ok then
                local new_chunk = chunk:gsub("\nARM 0", "\nARM 1", 1)
                if new_chunk ~= chunk then
                  reaper.SetEnvelopeStateChunk(env, new_chunk, false)
                end
              end
            end
          end
        end
      end
    end
  end
  _all_env_arms = {}
  reaper.Main_OnCommand(reaper.NamedCommandLookup("_BR_RESTORE_SOLO_MUTE_ALL_TRACKS_SLOT_10"), 0)
end

---------------------------------------------------------------------
-- ROUTE ENGAGE: trace inherited hw output from parent chain
-- 追蹤parent chain找到繼承的hw output目標channel
---------------------------------------------------------------------
local function trace_hw_route(tr)
  -- 追蹤parent chain → 回傳mono channel列表 {ch_idx, ch_idx, ...}
  -- trace parent chain → return list of mono channel indices
  local cur = tr
  for _ = 1, 16 do
    local ms = reaper.GetMediaTrackInfo_Value(cur, "B_MAINSEND")
    if ms ~= 1 then return {} end  -- parent send disabled
    local parent = reaper.GetParentTrack(cur)
    local tgt = parent or reaper.GetMasterTrack(0)
    if not tgt then return {} end
    local pn = reaper.GetTrackNumSends(tgt, 1)
    if pn > 0 then
      -- 將所有send展開成mono channels -- expand all sends into mono channels
      local seen = {}
      local result = {}
      for i = 0, pn - 1 do
        local dst = math.floor(reaper.GetTrackSendInfo_Value(tgt, 1, i, "I_DSTCHAN"))
        local ch = dst % 1024
        local is_mono = (math.floor(dst / 1024) % 2) == 1
        if is_mono then
          if not seen[ch] then seen[ch] = true; result[#result+1] = ch end
        else
          -- stereo → 拆成2個mono -- stereo → split into 2 mono
          if not seen[ch]   then seen[ch]   = true; result[#result+1] = ch   end
          if not seen[ch+1] then seen[ch+1] = true; result[#result+1] = ch+1 end
        end
      end
      return result
    end
    if not parent then
      -- Master無明確hw out → 預設mono ch 0 + ch 1
      return {0, 1}
    end
    cur = tgt
  end
  return {}
end

-- 存routing狀態+切換到hw send -- save routing state + switch to hw send
-- route_hw: cue的虛擬hw設定 {{ch=0,vol_db=0},...} 或nil -- cue's virtual hw config or nil
local function route_engage(tr, st, route_hw)
  local orig_route = {
    main_send = reaper.GetMediaTrackInfo_Value(tr, "B_MAINSEND"),
    main_offs = reaper.GetMediaTrackInfo_Value(tr, "C_MAINSEND_OFFS"),
    main_nch  = reaper.GetMediaTrackInfo_Value(tr, "C_MAINSEND_NCH"),
    hw_sends = {},   -- 原本就有的hw send -- pre-existing hw sends
    created = {},    -- ReaLive新建的hw send dst values -- hw sends created by ReaLive
    hw_removed = false,  -- 是否移除了原有hw sends -- whether original hw sends were removed
  }
  -- 存現有hw sends -- save existing hw sends
  local num_hw = reaper.GetTrackNumSends(tr, 1)
  for i = 0, num_hw - 1 do
    orig_route.hw_sends[#orig_route.hw_sends+1] = {
      dst  = reaper.GetTrackSendInfo_Value(tr, 1, i, "I_DSTCHAN"),
      vol  = reaper.GetTrackSendInfo_Value(tr, 1, i, "D_VOL"),
      pan  = reaper.GetTrackSendInfo_Value(tr, 1, i, "D_PAN"),
      mute = reaper.GetTrackSendInfo_Value(tr, 1, i, "B_MUTE"),
    }
  end

  if route_hw and #route_hw > 0 then
    -- ★ 有route_hw：移除所有現有hw sends，用route_hw重建
    -- ★ route_hw present: remove all existing hw sends, recreate from route_hw
    for i = num_hw - 1, 0, -1 do reaper.RemoveTrackSend(tr, 1, i) end
    orig_route.hw_removed = true
    st.orig.route = orig_route
    reaper.SetMediaTrackInfo_Value(tr, "B_MAINSEND", 0)
    local master_lin = FUNC.db2lin(prefs.master_vol)
    for _, rh in ipairs(route_hw) do
      if rh.ch >= 0 then  -- 跳過未指定的channel (ch=-1) -- skip unassigned channels
        local idx = reaper.CreateTrackSend(tr, nil)
        if idx and idx >= 0 then
          local mono_dst = rh.ch + 1024
          reaper.SetTrackSendInfo_Value(tr, 1, idx, "I_DSTCHAN", mono_dst)
          local fader_lin = rh.vol_db <= prefs.vol_min and 0 or (10 ^ (rh.vol_db / 20))
          reaper.SetTrackSendInfo_Value(tr, 1, idx, "D_VOL", fader_lin * master_lin)
          orig_route.created[#orig_route.created+1] = mono_dst
        end
      end
    end
  else
    -- ★ 無route_hw：維持原有邏輯 -- no route_hw: existing behavior
    local targets = nil
    if num_hw == 0 then targets = trace_hw_route(tr) end
    st.orig.route = orig_route
    reaper.SetMediaTrackInfo_Value(tr, "B_MAINSEND", 0)
    local master_lin2 = FUNC.db2lin(prefs.master_vol)
    if num_hw > 0 then
      -- 有既有hw sends：套用master到每個send -- existing hw sends: apply master to each
      for i = 0, num_hw - 1 do
        local orig_vol = orig_route.hw_sends[i+1] and orig_route.hw_sends[i+1].vol or 1.0
        reaper.SetTrackSendInfo_Value(tr, 1, i, "D_VOL", orig_vol * master_lin2)
      end
    elseif targets and #targets > 0 then
      for _, ch in ipairs(targets) do
        local idx = reaper.CreateTrackSend(tr, nil)
        if idx and idx >= 0 then
          local mono_dst = ch + 1024
          reaper.SetTrackSendInfo_Value(tr, 1, idx, "I_DSTCHAN", mono_dst)
          reaper.SetTrackSendInfo_Value(tr, 1, idx, "D_VOL", master_lin2)
          orig_route.created[#orig_route.created+1] = mono_dst
        end
      end
    end
  end
end

-- 播放中僅更新hw send音量（不重建，避免glitch） -- update hw send volumes only (no rebuild, avoids glitch)
function FUNC.route_update_vol(c)
  local guid = c.track_guid or ""
  if guid == "" then return false end
  local st = _trk_state[guid]
  if not st or not st.orig or not st.orig.route then return false end
  local tr = reaper.BR_GetMediaTrackByGUID(0, guid)
  if not tr then return false end
  local route_hw = c.route_hw
  if not route_hw then return false end
  local master_lin = FUNC.db2lin(prefs.master_vol)
  local num_hw = reaper.GetTrackNumSends(tr, 1)
  for _, rh in ipairs(route_hw) do
    if rh.ch >= 0 then
      local mono_dst = rh.ch + 1024
      for si = 0, num_hw - 1 do
        if math.floor(reaper.GetTrackSendInfo_Value(tr, 1, si, "I_DSTCHAN")) == mono_dst then
          local fader_lin = rh.vol_db <= prefs.vol_min and 0 or (10 ^ (rh.vol_db / 20))
          reaper.SetTrackSendInfo_Value(tr, 1, si, "D_VOL", fader_lin * master_lin)
          break
        end
      end
    end
  end
  return true
end

-- 播放中即時同步route_hw到REAPER hw sends（完整重建：用於add/delete/reassign channel） -- full rebuild for structural changes
function FUNC.route_apply_live(c)
  local guid = c.track_guid or ""
  if guid == "" then return false end
  local st = _trk_state[guid]
  if not st or not st.orig or not st.orig.route then return false end
  local tr = reaper.BR_GetMediaTrackByGUID(0, guid)
  if not tr then return false end
  local rt = st.orig.route
  local route_hw = c.route_hw

  -- 移除所有ReaLive建立的hw sends -- remove all ReaLive-created sends
  if rt.created and #rt.created > 0 then
    local num_hw = reaper.GetTrackNumSends(tr, 1)
    local created_set = {}
    for _, dst in ipairs(rt.created) do created_set[dst] = (created_set[dst] or 0) + 1 end
    for i = num_hw - 1, 0, -1 do
      local dst = math.floor(reaper.GetTrackSendInfo_Value(tr, 1, i, "I_DSTCHAN"))
      if created_set[dst] and created_set[dst] > 0 then
        reaper.RemoveTrackSend(tr, 1, i)
        created_set[dst] = created_set[dst] - 1
      end
    end
  end

  -- 從route_hw重建 -- recreate from route_hw
  rt.created = {}
  local master_lin = FUNC.db2lin(prefs.master_vol)
  if route_hw and #route_hw > 0 then
    for _, rh in ipairs(route_hw) do
      if rh.ch >= 0 then
        local idx = reaper.CreateTrackSend(tr, nil)
        if idx and idx >= 0 then
          local mono_dst = rh.ch + 1024
          reaper.SetTrackSendInfo_Value(tr, 1, idx, "I_DSTCHAN", mono_dst)
          local fader_lin = rh.vol_db <= prefs.vol_min and 0 or (10 ^ (rh.vol_db / 20))
          reaper.SetTrackSendInfo_Value(tr, 1, idx, "D_VOL", fader_lin * master_lin)
          rt.created[#rt.created+1] = mono_dst
        end
      end
    end
  end
  return true
end

-- master音量變更時更新所有active track的hw send音量 -- update all active hw send volumes on master change
function FUNC.apply_master_sends()
  local master_lin = FUNC.db2lin(prefs.master_vol)
  local done_guid = {}  -- 避免同track重複處理 -- avoid duplicate processing per track
  for _, c in ipairs(cues) do
    local guid = c.track_guid or ""
    if c.state ~= STATE.IDLE and guid ~= "" and not done_guid[guid] then
      local st = _trk_state[guid]
      if st and st.orig and st.orig.route then
        local tr = reaper.BR_GetMediaTrackByGUID(0, guid)
        if tr then
          local num_hw = reaper.GetTrackNumSends(tr, 1)
          if c.route_hw then
            -- 有route_hw：每個send = fader_vol × master -- route_hw: send = fader × master
            for _, rh in ipairs(c.route_hw) do
              if rh.ch >= 0 then
                local mono_dst = rh.ch + 1024
                for si = 0, num_hw - 1 do
                  if math.floor(reaper.GetTrackSendInfo_Value(tr, 1, si, "I_DSTCHAN")) == mono_dst then
                    local fader_lin = rh.vol_db <= prefs.vol_min and 0 or (10 ^ (rh.vol_db / 20))
                    reaper.SetTrackSendInfo_Value(tr, 1, si, "D_VOL", fader_lin * master_lin)
                    break
                  end
                end
              end
            end
          else
            -- 無route_hw：所有hw sends套用master -- no route_hw: apply master to all sends
            local rt = st.orig.route
            for si = 0, num_hw - 1 do
              local orig_vol = rt.hw_sends[si+1] and rt.hw_sends[si+1].vol or 1.0
              reaper.SetTrackSendInfo_Value(tr, 1, si, "D_VOL", orig_vol * master_lin)
            end
          end
          done_guid[guid] = true
        end
      end
    end
  end
end

-- 還原routing狀態 -- restore routing state
local function route_disengage(tr, st)
  local rt = st.orig.route
  if not rt then return end

  -- 移除ReaLive建立的hw sends (從後往前避免index偏移)
  -- remove ReaLive-created hw sends (back-to-front to avoid index shift)
  if #rt.created > 0 then
    local num_hw = reaper.GetTrackNumSends(tr, 1)
    -- 比對完整dst值（含stereo/mono資訊） -- match full dst value (incl. stereo/mono)
    local to_remove = {}
    local created_set = {}
    for _, dst in ipairs(rt.created) do created_set[dst] = (created_set[dst] or 0) + 1 end
    for i = num_hw - 1, 0, -1 do
      local dst = math.floor(reaper.GetTrackSendInfo_Value(tr, 1, i, "I_DSTCHAN"))
      if created_set[dst] and created_set[dst] > 0 then
        to_remove[#to_remove+1] = i
        created_set[dst] = created_set[dst] - 1
      end
    end
    for _, i in ipairs(to_remove) do
      reaper.RemoveTrackSend(tr, 1, i)
    end
  end

  -- 沒被移除的原有hw sends：播放時音量被乘上 master，這裡還原原值（否則每播一次就再乘一次）
  -- original hw sends that stayed in place had their level multiplied by master while playing: put the original level back
  if not rt.hw_removed and rt.hw_sends then
    for i, hw in ipairs(rt.hw_sends) do
      if i - 1 < reaper.GetTrackNumSends(tr, 1) then reaper.SetTrackSendInfo_Value(tr, 1, i - 1, "D_VOL", hw.vol) end
    end
  end

  -- 重建被移除的原有hw sends -- recreate original hw sends that were removed
  if rt.hw_removed and rt.hw_sends and #rt.hw_sends > 0 then
    for _, hw in ipairs(rt.hw_sends) do
      local idx = reaper.CreateTrackSend(tr, nil)
      if idx and idx >= 0 then
        reaper.SetTrackSendInfo_Value(tr, 1, idx, "I_DSTCHAN", hw.dst)
        reaper.SetTrackSendInfo_Value(tr, 1, idx, "D_VOL", hw.vol)
        reaper.SetTrackSendInfo_Value(tr, 1, idx, "D_PAN", hw.pan)
        reaper.SetTrackSendInfo_Value(tr, 1, idx, "B_MUTE", hw.mute)
      end
    end
  end

  -- 還原parent send -- restore parent send
  reaper.SetMediaTrackInfo_Value(tr, "B_MAINSEND", rt.main_send)
  reaper.SetMediaTrackInfo_Value(tr, "C_MAINSEND_OFFS", rt.main_offs)
  reaper.SetMediaTrackInfo_Value(tr, "C_MAINSEND_NCH", rt.main_nch)
end

-- 檢查是否可以解鎖（無active track且無waiting cue） -- check if global unlock is possible
function FUNC.check_global_unlock()
  if not _global_locked then return end
  if next(_trk_state) then return end
  for _, q in ipairs(cues) do
    if q.state == STATE.PREWAIT or q.state == STATE.POSTWAIT or q.state == STATE.RUNNING then return end
  end
  restore_global_state()
  _global_locked = false
end

-- MIDI internal cue 專用：臨時解鎖 track controls（lock 狀態下 arm 會失效）
-- 記錄 _lock_suspended 讓 MIDI 結束時可以重鎖回原狀，不重複 save_global_state
-- MIDI internal-cue helper: temporarily suspend lock; restore via reapply_global_lock later
function FUNC.force_global_unlock()
  if _global_locked then
    _global_locked = false
    _lock_suspended = true
  end
end

-- MIDI cue 結束後補鎖：恢復 envelope unarm 狀態（不再鎖 track control）
function FUNC.reapply_global_lock()
  if _lock_suspended and not _global_locked then
    reaper.Main_OnCommand(40296, 0)  -- select all tracks
    reaper.Main_OnCommand(41163, 0)  -- unarm all envelopes
    reaper.Main_OnCommand(40297, 0)  -- unselect all tracks
    _global_locked = true
    _lock_suspended = false
  end
end

-- 進入播放/pre-post wait：save 全域狀態 + unarm envelopes（不再鎖 track control）
function FUNC.ensure_global_lock()
  if not _global_locked then
    save_global_state()
    reaper.Main_OnCommand(40296, 0)  -- select all tracks
    reaper.Main_OnCommand(41163, 0)  -- unarm all envelopes
    reaper.Main_OnCommand(40297, 0)  -- unselect all tracks
    _global_locked = true
  end
end

-- 播放開始：存軌道狀態+重置到中性+鎖定+bypass envelope+路由切換
-- save track state on first play (vol/pan/mute/solo + envelopes + routing)
-- 「借用軌道」以借用者（cue id）登記：同一個 cue 重複借（loop 每一圈、trim 重播）只算一次，
-- 所以還的時候一次就還清。波形選取試聽用另一個名字（holder）借，和 cue 本身的播放互不影響。
-- A track is "borrowed" per holder (cue id): the same cue borrowing again (each loop round, trim replay) counts once,
-- so one return gives it back. Waveform range audition borrows under its own holder name, independent of the cue playing.
local function trk_holders(st) local n = 0; for _ in pairs(st.holders) do n = n + 1 end; return n end
local function trk_project(st)  -- 借用當下的專案；切換分頁後仍還到原專案 -- project it was borrowed in; restore goes there even after a tab switch
  if st.proj and reaper.ValidatePtr2 and reaper.ValidatePtr2(0, st.proj, "ReaProject*") then return st.proj end
  return 0
end
function FUNC.env_save_track(c, skip_lock, holder)
  local ti = c.track_idx
  if ti < 0 then return end
  local tr = FUNC.get_tr(ti)
  if not tr then return end
  local guid = c.track_guid or ""
  if guid == "" then return end
  -- 全域鎖定：第一個track開始播放時鎖定所有track+unarm所有envelope -- global lock on first play
  -- skip_lock：MIDI internal cue 不鎖 track，避免 41312 解除 RECARM
  if not skip_lock and not next(_trk_state) then FUNC.ensure_global_lock() end
  if not _trk_state[guid] then
    _trk_state[guid] = {
      holders = {},
      proj = reaper.EnumProjects(-1),
      orig = {
        vol = reaper.GetMediaTrackInfo_Value(tr, "D_VOL"),
        pan = reaper.GetMediaTrackInfo_Value(tr, "D_PAN"),
        width = reaper.GetMediaTrackInfo_Value(tr, "D_WIDTH"),
        mute = reaper.GetMediaTrackInfo_Value(tr, "B_MUTE"),
        solo = reaper.GetMediaTrackInfo_Value(tr, "I_SOLO"),
      }
    }
    -- 重置軌道到中性狀態 -- reset track to neutral
    reaper.SetMediaTrackInfo_Value(tr, "D_VOL", 1.0)  -- 0dB
    reaper.SetMediaTrackInfo_Value(tr, "D_PAN", 0)     -- center
    reaper.SetMediaTrackInfo_Value(tr, "D_WIDTH", 1.0) -- full stereo
    reaper.SetMediaTrackInfo_Value(tr, "B_MUTE", 0)
    reaper.SetMediaTrackInfo_Value(tr, "I_SOLO", 0)
    -- bypass REAPER軌道自身的volume/pan envelope -- bypass track's own vol/pan envelopes
    _trk_state[guid].orig.vol_env_chunk = bypass_env(tr, "Volume")
    _trk_state[guid].orig.pan_env_chunk = bypass_env(tr, "Pan")
    -- 路由切換：存原始routing + 切到hw send（使用cue的route_hw若有）
    -- route engage: save + switch to hw send (use cue's route_hw if available)
    route_engage(tr, _trk_state[guid], c.route_hw)
  end
  _trk_state[guid].holders[holder or c.id] = true
end

-- 播放結束：最後一個cue停止時還原軌道+envelope+routing -- restore track when last cue stops
function FUNC.env_restore_track(c, holder)
  local guid = c.track_guid or ""
  if guid == "" then return end
  local st = _trk_state[guid]
  if not st then return end
  st.holders[holder or c.id] = nil
  if trk_holders(st) <= 0 then
    local tr = reaper.BR_GetMediaTrackByGUID(trk_project(st), guid)  -- 用GUID直接取track handle -- resolve by GUID
    if tr then
      -- 還原任何殘留的 FX 參數 -- restore any residual fx params
      if FUNC.fx_env_restore_track_params then FUNC.fx_env_restore_track_params(tr, st) end
      -- 還原routing（先做，因為會移除send） -- restore routing first (removes sends)
      route_disengage(tr, st)
      reaper.SetMediaTrackInfo_Value(tr, "D_VOL", st.orig.vol)
      reaper.SetMediaTrackInfo_Value(tr, "D_PAN", st.orig.pan)
      if st.orig.width then reaper.SetMediaTrackInfo_Value(tr, "D_WIDTH", st.orig.width) end
      reaper.SetMediaTrackInfo_Value(tr, "B_MUTE", st.orig.mute)
      reaper.SetMediaTrackInfo_Value(tr, "I_SOLO", st.orig.solo)
      -- 還原REAPER軌道envelope -- restore track envelopes
      restore_env(tr, "Volume", st.orig.vol_env_chunk)
      restore_env(tr, "Pan", st.orig.pan_env_chunk)
    end
    _trk_state[guid] = nil
    -- 全域解鎖：最後一個track停止且無pre/post wait中的cue時解鎖
    -- global unlock: last track stopped AND no cues in pre/post wait
    if not next(_trk_state) and _global_locked then
      local any_waiting = false
      for _, q in ipairs(cues) do
        if q.state == STATE.PREWAIT or q.state == STATE.POSTWAIT then any_waiting = true; break end
      end
      if not any_waiting then
        restore_global_state()
        _global_locked = false
      end
    end
  end
end

-- Panic/退出：還原所有軌道+envelope+routing -- restore all tracks on panic/exit
function FUNC.env_restore_all()
  for guid, st in pairs(_trk_state) do
    local tr = reaper.BR_GetMediaTrackByGUID(trk_project(st), guid)  -- GUID直接取handle -- resolve by GUID
    if tr then
      -- 還原任何殘留的 FX 參數 -- restore any residual fx params
      if FUNC.fx_env_restore_track_params then FUNC.fx_env_restore_track_params(tr, st) end
      -- 還原routing -- restore routing
      route_disengage(tr, st)
      reaper.SetMediaTrackInfo_Value(tr, "D_VOL", st.orig.vol)
      reaper.SetMediaTrackInfo_Value(tr, "D_PAN", st.orig.pan)
      if st.orig.width then reaper.SetMediaTrackInfo_Value(tr, "D_WIDTH", st.orig.width) end
      reaper.SetMediaTrackInfo_Value(tr, "B_MUTE", st.orig.mute)
      reaper.SetMediaTrackInfo_Value(tr, "I_SOLO", st.orig.solo)
      -- 還原REAPER軌道envelope -- restore track envelopes
      restore_env(tr, "Volume", st.orig.vol_env_chunk)
      restore_env(tr, "Pan", st.orig.pan_env_chunk)
    end
  end
  _trk_state = {}
  -- 全域解鎖：還原所有track lock+envelope arm -- global unlock + restore
  if _global_locked then
    restore_global_state()
    _global_locked = false
  end
end

---------------------------------------------------------------------
-- ENVELOPE DATA OPERATIONS -- envelope資料操作
---------------------------------------------------------------------

-- 計算envelope有效時長(共用) -- effective duration for envelope
local function env_eff_dur(c)
  local dur = c.eff_dur > 0 and c.eff_dur or c.total_dur
  if dur <= 0 then
    dur = FUNC.calc_dur(c.track_idx)
    local ts = c.trim_start or 0
    local te = (c.trim_end and c.trim_end > 0) and c.trim_end or dur
    dur = math.max(0.1, te - ts)
  end
  return dur
end

-- envelope point .t 語義：絕對音檔時間（秒，從 source 0 起算），不受 trim 影響
-- envelope point .t semantics: absolute audio source time; unaffected by trim_start changes

-- 啟用時建立預設兩點 (0dB start, 0dB end，跨越 trim 範圍) -- default 2 points spanning trim range
function FUNC.env_init_points(c)
  local ts = c.trim_start or 0
  local te = ts + env_eff_dur(c)
  c.env_points = {
    {t = ts, v = 0},  -- 起點 0dB at trim_start
    {t = te, v = 0},  -- 終點 0dB at trim_end
  }
end

-- pan envelope預設兩點 (center start, center end) -- pan envelope default
function FUNC.pan_env_init_points(c)
  local ts = c.trim_start or 0
  local te = ts + env_eff_dur(c)
  c.pan_env_points = {
    {t = ts, v = 0},  -- 起點 center at trim_start
    {t = te, v = 0},  -- 終點 center at trim_end
  }
end

-- 排序 -- sort by time
function FUNC.env_sort(points)
  table.sort(points, function(a, b) return a.t < b.t end)
end

-- 新增點（curve=線段曲率，0=linear）-- add point with optional curve
function FUNC.env_add_point(c, t, v, curve)
  if not c.env_points then c.env_points = {} end
  v = FUNC.clamp(v, ENV_MIN_DB, ENV_MAX_DB)
  c.env_points[#c.env_points + 1] = {t = t, v = v, curve = curve or 0}
  FUNC.env_sort(c.env_points)
end

-- 刪除點 -- remove point at index
function FUNC.env_remove_point(c, idx)
  if not c.env_points or idx < 1 or idx > #c.env_points then return end
  table.remove(c.env_points, idx)
end

-- 移動點 -- move point to new t,v
function FUNC.env_move_point(c, idx, t, v)
  if not c.env_points or idx < 1 or idx > #c.env_points then return end
  c.env_points[idx].t = math.max(0, t)
  c.env_points[idx].v = FUNC.clamp(v, ENV_MIN_DB, ENV_MAX_DB)
  FUNC.env_sort(c.env_points)
end

---------------------------------------------------------------------
-- LINEAR INTERPOLATION -- 線性插值
---------------------------------------------------------------------
-- 給定時間 t (秒, 相對cue起點), 回傳疊加dB值（支援per-segment曲率）
function FUNC.env_interp(points, t)
  if not points or #points == 0 then return 0 end
  if #points == 1 then return points[1].v end
  if t <= points[1].t then return points[1].v end
  if t >= points[#points].t then return points[#points].v end
  for i = 1, #points - 1 do
    local p0, p1 = points[i], points[i + 1]
    if t >= p0.t and t <= p1.t then
      local seg = p1.t - p0.t
      if seg <= 0 then return p0.v end
      local frac = (t - p0.t) / seg
      -- 用bezier曲線（curve=0時等同linear）-- apply bezier curve per segment
      local cv = p0.curve or 0
      if cv ~= 0 then frac = FUNC.crv(frac, "bezier", cv) end
      return p0.v + (p1.v - p0.v) * frac
    end
  end
  return 0
end

---------------------------------------------------------------------
-- PER-FRAME APPLY -- 每幀套用 envelope 到軌道推桿
---------------------------------------------------------------------
function FUNC.env_apply_all()
  local now = reaper.time_precise()
  for _, c in ipairs(cues) do
    if c.type == "PLAY" and c.env_enabled and c.env_points and #c.env_points > 0
        and c.state == STATE.RUNNING and c.play_t0 > 0 then
      -- C12: 用實時 playcursor (play_offset + elapsed*rate)，不被 trim 拖曳影響
      -- C12: real-time playcursor; ignores trim_start changes during drag
      local cr = (c.rate and c.rate > 0) and c.rate or 1.0
      local ph_t = (c.play_offset or c.trim_start or 0) + (now - c.play_t0) * cr
      local env_db = FUNC.env_interp(c.env_points, ph_t)
      local tr = FUNC.get_tr(c.track_idx)
      if tr then
        -- envelope dB → track D_VOL (疊加在 preview volume 之上) -- envelope控制軌道推桿
        reaper.SetMediaTrackInfo_Value(tr, "D_VOL", FUNC.db2lin(env_db))
      end
    end
  end
end

-- Pan envelope每幀套用到D_PAN -- per-frame apply pan envelope
function FUNC.pan_env_apply_all()
  local now = reaper.time_precise()
  for _, c in ipairs(cues) do
    if c.type == "PLAY" and c.pan_env_enabled and c.pan_env_points and #c.pan_env_points > 0
        and c.state == STATE.RUNNING and c.play_t0 > 0 then
      -- C12: 用實時 playcursor -- real-time playcursor
      local cr = (c.rate and c.rate > 0) and c.rate or 1.0
      local ph_t = (c.play_offset or c.trim_start or 0) + (now - c.play_t0) * cr
      local pan_val = FUNC.env_interp(c.pan_env_points, ph_t)  -- -1~1
      pan_val = FUNC.clamp(pan_val, PAN_ENV_MIN, PAN_ENV_MAX)
      local tr = FUNC.get_tr(c.track_idx)
      if tr then
        reaper.SetMediaTrackInfo_Value(tr, "D_PAN", pan_val)  -- pan envelope直接控制D_PAN
      end
    end
  end
end

---------------------------------------------------------------------
-- SERIALIZATION -- envelope序列化
---------------------------------------------------------------------
-- 格式: "t1:v1:c1;t2:v2:c2;..." (c=curve，省略時=0) -- serialization with per-segment curve
function FUNC.env_pts2str(points)
  if not points or #points == 0 then return "" end
  local parts = {}
  for _, p in ipairs(points) do
    local cv = p.curve or 0
    if cv ~= 0 then
      parts[#parts + 1] = string.format("%.4f:%.2f:%.3f", p.t, p.v, cv)
    else
      parts[#parts + 1] = string.format("%.4f:%.2f", p.t, p.v)  -- 向後相容：curve=0省略
    end
  end
  return table.concat(parts, ";")
end

function FUNC.env_str2pts(s)
  if not s or s == "" then return {} end
  local pts = {}
  for seg in s:gmatch("[^;]+") do
    local t, v, cv = seg:match("([^:]+):([^:]+):?([^:]*)")
    if t and v then pts[#pts + 1] = {t = tonumber(t) or 0, v = tonumber(v) or 0, curve = tonumber(cv) or 0} end
  end
  return pts
end

-- Pan envelope序列化(格式同volume，但值範圍是-1~1) -- pan envelope serialization
FUNC.pan_env_pts2str = FUNC.env_pts2str  -- 共用同一格式
FUNC.pan_env_str2pts = FUNC.env_str2pts

---------------------------------------------------------------------
-- FX ENVELOPE VALUE FORMATTING HELPERS -- FX envelope 數值格式化
---------------------------------------------------------------------
-- 取得FX參數的格式化字串（normalized 0~1 → "1200 Hz" 等）
-- get formatted string for FX param from normalized value
-- point值是真實值（TrackFX_GetParam），用FormatParamValue格式化
-- point values are real (from TrackFX_GetParam), use FormatParamValue to display
function FUNC.fx_env_format(c, fe, real_v)
  if not c or not fe then return string.format("%.3f", real_v) end
  local tr = FUNC.get_tr(c.track_idx)
  if not tr then return string.format("%.3f", real_v) end
  local fi = FUNC.fx_guid_to_idx(tr, fe.fx_guid)
  if not fi then return string.format("%.3f", real_v) end
  local ok, buf = reaper.TrackFX_FormatParamValue(tr, fi, fe.param_idx, real_v, "")
  if ok and buf and buf ~= "" then return buf end
  return string.format("%.3f", real_v)
end

-- 從格式化字串提取帶單位的數值（處理 k/K/M 等倍率）
-- extract numeric value from formatted string, handling unit multipliers
local _unit_mult = {k=1e3, K=1e3, M=1e6, m=1e-3, G=1e9}
local function parse_formatted_num(s)
  if not s then return nil end
  -- 匹配 數字(可有小數/負號) + 可選的空白 + 可選的單位前綴字母
  local num_s, unit = s:match("^%s*([%d%.%-]+)%s*([kKMmG]?)")
  local n = tonumber(num_s)
  if not n then return nil end
  if unit and unit ~= "" and _unit_mult[unit] then
    n = n * _unit_mult[unit]
  end
  return n
end

-- 反向解析：使用者輸入的真實值字串 → FX 真實值（用 GetParamEx 的 min/max 做二分搜尋）
-- reverse parse: user input real value string → FX real value via binary search on FormatParamValue
function FUNC.fx_env_parse_real(c, fe, input_str)
  if not c or not fe then return nil end
  local tr = FUNC.get_tr(c.track_idx)
  local fi = tr and FUNC.fx_guid_to_idx(tr, fe.fx_guid) or nil
  -- 使用者輸入也要處理單位倍率 -- user input also needs unit multiplier
  local target = parse_formatted_num(input_str)
  if not target then return nil end
  if not tr or not fi then return tonumber(input_str) end
  -- 取得真實值範圍 -- get real value range
  local _, minv, maxv = reaper.TrackFX_GetParamEx(tr, fi, fe.param_idx)
  if not minv or not maxv or minv >= maxv then return tonumber(input_str) end
  -- API格式化helper（用真實值）-- format helper using real values
  local function fmt_num(rv)
    local ok, buf = reaper.TrackFX_FormatParamValue(tr, fi, fe.param_idx, rv, "")
    if not ok or not buf then return nil end
    return parse_formatted_num(buf)
  end
  -- 判斷方向 -- determine direction
  local v0 = fmt_num(minv)
  local v1 = fmt_num(maxv)
  if not v0 or not v1 then return tonumber(input_str) end
  local ascending = v1 > v0
  -- 目標超出範圍 -- out of range: clamp
  if ascending then
    if target <= v0 then return minv end
    if target >= v1 then return maxv end
  else
    if target >= v0 then return minv end
    if target <= v1 then return maxv end
  end
  -- 二分搜尋（在真實值範圍內）-- binary search in real value range
  local lo, hi = minv, maxv
  for _ = 1, 50 do
    local mid = (lo + hi) * 0.5
    local mv = fmt_num(mid)
    if not mv then break end
    if (ascending and mv < target) or (not ascending and mv > target) then
      lo = mid
    else
      hi = mid
    end
    if hi - lo < 1e-10 then break end
  end
  return (lo + hi) * 0.5
end

---------------------------------------------------------------------
-- ENVELOPE DRAWING ON WAVEFORM -- 在波形上繪製 envelope
---------------------------------------------------------------------
-- wf_info = {cx, wy, cw, wh, view_start, view_dur, total_dur, trim_start, trim_end}
-- mode = "vol"(volume/dB) or "pan"(panning/-1~1)，預設"vol"
function FUNC.env_draw(c, dl, wf_info, mode, fe)
  mode = mode or "vol"
  -- 根據mode決定參數 -- mode-dependent params
  local v_min, v_max, pts, env_color, ref_lines, is_active
  local add_point_fn, format_fn, parse_fn, reset_v
  if mode == "pan" then
    if not c or not c.pan_env_enabled or not c.pan_env_points or #c.pan_env_points == 0 then return end
    v_min, v_max = PAN_ENV_MIN, PAN_ENV_MAX
    pts = c.pan_env_points
    env_color = C.pan_env
    ref_lines = {0, 0.5, -0.5}  -- center, ±50%
    is_active = (env_edit_mode == "pan")
    add_point_fn = function(t, v)
      if not c.pan_env_points then c.pan_env_points = {} end
      c.pan_env_points[#c.pan_env_points + 1] = {t = t, v = v, curve = 0}
      FUNC.env_sort(c.pan_env_points)
    end
    format_fn = function(v) return string.format("%.0f", v * 100) end
    parse_fn  = function(s) local n = tonumber(s); return n and (n / 100) or nil end
    reset_v = 0
  elseif mode == "fx" then
    if not fe or not fe.visible or not fe.points or #fe.points == 0 then return end
    -- FX point值是真實值（TrackFX_GetParam），v_min/v_max用GetParamEx取得
    -- FX point values are real (from TrackFX_GetParam), get range from GetParamEx
    local fx_minv, fx_maxv, fx_midv = 0, 1, 0.5
    local fx_tr = FUNC.get_tr(c.track_idx)
    if fx_tr then
      local fx_fi = FUNC.fx_guid_to_idx(fx_tr, fe.fx_guid)
      if fx_fi then
        local _, mn, mx, md = reaper.TrackFX_GetParamEx(fx_tr, fx_fi, fe.param_idx)
        if mn and mx and mn < mx then fx_minv, fx_maxv, fx_midv = mn, mx, md or (mn+mx)/2 end
      end
    end
    v_min, v_max = fx_minv, fx_maxv
    pts = fe.points
    env_color = fe.color or 0xFFAA33FF
    ref_lines = {fx_midv}  -- midpoint from FX
    is_active = (env_edit_mode == "fx" and fx_env_edit_idx and c.fx_envs and c.fx_envs[fx_env_edit_idx] == fe)
    add_point_fn = function(t, v)
      fe.points[#fe.points + 1] = {t = t, v = v, curve = 0}
      FUNC.env_sort(fe.points)
    end
    format_fn = function(v) return FUNC.fx_env_format(c, fe, v) end
    parse_fn  = function(s)
      local rv = FUNC.fx_env_parse_real(c, fe, s)
      if rv then return FUNC.clamp(rv, fx_minv, fx_maxv) end
      return nil
    end
    reset_v = fx_midv
  else
    if not c or not c.env_enabled or not c.env_points or #c.env_points == 0 then return end
    v_min, v_max = ENV_MIN_DB, ENV_MAX_DB
    pts = c.env_points
    env_color = C.env
    ref_lines = {0, 6, -6, -12, -24, -48}  -- 0dB + reference dBs
    is_active = (env_edit_mode == "vol")
    add_point_fn = function(t, v) FUNC.env_add_point(c, t, v) end
    format_fn = function(v) return string.format("%.1f", v) end
    parse_fn  = function(s) return tonumber(s) end
    reset_v = 0
  end
  local cx, wy, cw, wh = wf_info.cx, wf_info.wy, wf_info.cw, wf_info.wh
  local vs, vd = wf_info.view_start, wf_info.view_dur
  local ts = wf_info.trim_start
  local te = wf_info.trim_end

  -- 值→Y座標: 頂部=max, 底部=min -- value to Y coordinate
  local function val2y(v)
    local frac = (v - v_min) / (v_max - v_min)
    return wy + wh * (1 - frac)
  end
  -- 保留舊名稱供interaction用 -- alias for backward compat in interaction code
  local db2y = val2y

  -- envelope時間(絕對音檔時間) → 螢幕X -- absolute audio time → screen X
  local function t2x(at)
    return cx + ((at - vs) / vd) * cw
  end

  -- envelope顏色分解（參考線/控制點共用） -- decompose env color for ref lines & points
  local er = (env_color >> 24) & 0xFF
  local eg = (env_color >> 16) & 0xFF
  local eb = (env_color >> 8) & 0xFF

  -- 非活躍envelope的alpha降低；fx mode 用滿 alpha（對比靠線寬）-- inactive dim except fx
  local dim_a
  if mode == "fx" then
    dim_a = 1.0
  else
    dim_a = is_active and 1.0 or 0.4
  end

  -- 參考線 -- reference lines
  for ri, ref_v in ipairs(ref_lines) do
    local ry = val2y(ref_v)
    if ry >= wy and ry <= wy + wh then
      local alpha = (ri == 1) and math.floor(40 * dim_a) or math.floor(15 * dim_a)
      ImGui.DrawList_AddLine(dl, cx, ry, cx + cw, ry, FUNC.rgba(er, eg, eb, alpha), 1)
    end
  end

  -- === HOVER 偵測 === -- detect hovered point / segment
  -- 非活躍envelope不做hover偵測，避免干擾 -- skip hover detection for inactive envelope
  local mx, my = ImGui.GetMousePos(ctx)
  local hov_pt, hov_seg = nil, nil  -- hov_pt=index, hov_seg=segment index (i to i+1)
  if is_active then
    local hr2 = ENV_HIT_R * ENV_HIT_R
    -- 先找最近的控制點 -- find nearest point
    for i, p in ipairs(pts) do
      local px = t2x(p.t)
      local py = FUNC.clamp(db2y(p.v), wy, wy + wh)
      local dx, dy = mx - px, my - py
      if dx * dx + dy * dy < hr2 then hov_pt = i end
    end
    -- 沒 hover 到點才找線段 -- find segment only if no point hovered
    if not hov_pt then
      for i = 1, #pts - 1 do
        local x1 = t2x(pts[i].t)
        local y1 = FUNC.clamp(db2y(pts[i].v), wy, wy + wh)
        local x2 = t2x(pts[i + 1].t)
        local y2 = FUNC.clamp(db2y(pts[i + 1].v), wy, wy + wh)
        if mx >= math.min(x1, x2) - 4 and mx <= math.max(x1, x2) + 4 then
          -- 點到線段的距離 -- point-to-line distance
          local seg_dx, seg_dy = x2 - x1, y2 - y1
          local seg_len2 = seg_dx * seg_dx + seg_dy * seg_dy
          if seg_len2 > 0 then
            local t_param = FUNC.clamp(((mx - x1) * seg_dx + (my - y1) * seg_dy) / seg_len2, 0, 1)
            local proj_x = x1 + t_param * seg_dx
            local proj_y = y1 + t_param * seg_dy
            local dist2 = (mx - proj_x) * (mx - proj_x) + (my - proj_y) * (my - proj_y)
            if dist2 < ENV_LINE_HIT * ENV_LINE_HIT then hov_seg = i end
          end
        end
      end
      -- 延伸段（第一個點之前、最後一個點之後）也檢測 -- check extend segments
      if not hov_seg and #pts > 0 then
        local x0 = t2x(pts[1].t)
        local y0 = FUNC.clamp(db2y(pts[1].v), wy, wy + wh)
        if mx >= cx and mx <= x0 and math.abs(my - y0) < ENV_LINE_HIT then hov_seg = 0 end  -- 前延伸
        local xn = t2x(pts[#pts].t)
        local yn = FUNC.clamp(db2y(pts[#pts].v), wy, wy + wh)
        if mx >= xn and mx <= cx + cw and math.abs(my - yn) < ENV_LINE_HIT then hov_seg = #pts end  -- 後延伸
      end
    end
  end

  -- Envelope 曲線（顏色從上面 er/eg/eb 取） -- curve segments (reuse er/eg/eb from above)
  local da = function(a) return math.floor(a * dim_a) end  -- 非活躍alpha衰減helper
  local env_col = FUNC.dim_c(FUNC.rgba(er, eg, eb, da(200)))
  local env_col_hov = FUNC.dim_c(FUNC.rgba(math.min(er+30,255), math.min(eg+30,255), math.min(eb+50,255), da(240)))
  -- fx inactive 更細，對比由線寬承擔 -- fx inactive thinner
  local line_w
  if mode == "fx" then
    line_w = is_active and 2.8 or 1.3
  else
    line_w = is_active and 3.5 or 2.0
  end
  local line_w_sel = 4.5

  -- 判定線段是否與選取點相連（非活躍envelope不顯示選取） -- check if segment touches selected point (inactive: never selected)
  local function seg_sel(i)
    if not is_active then return false end
    return env_drag.sel[i] or env_drag.sel[i + 1]
  end

  -- 播放過的線段變灰色 -- played envelope segments turn grey
  local env_played = FUNC.dim_c(FUNC.rgba(120, 120, 120, da(150)))
  local env_ph_t = nil  -- playhead time (絕對音檔時間) for grey判定
  if c.state == STATE.RUNNING and c.play_t0 > 0 then
    -- C12: 用實時 playcursor (play_offset + elapsed*rate)，避免拖曳 trim 時冒出第二個 cursor
    local cr = (c.rate and c.rate > 0) and c.rate or 1.0
    env_ph_t = (c.play_offset or ts) + (reaper.time_precise() - c.play_t0) * cr
  end

  -- 根據播放頭選顏色 -- choose color based on playhead position
  local function seg_col(t1, t2, is_hov)
    if env_ph_t and t2 <= env_ph_t then return env_played end  -- 整段已播過
    if is_hov then return env_col_hov end
    return env_col
  end

  -- 第一個點之前延伸(平線) -- flat extend before first point
  if #pts > 0 then
    local x0 = t2x(pts[1].t)
    if x0 > cx then
      local y = FUNC.clamp(db2y(pts[1].v), wy, wy + wh)
      local col = seg_col(0, pts[1].t, hov_seg == 0)
      local lw = env_drag.sel[1] and line_w_sel or line_w
      ImGui.DrawList_AddLine(dl, cx, y, x0, y, col, lw)
    end
  end

  -- 繪製一段曲線（支援bezier曲率）-- draw one segment with optional bezier curve
  local function draw_seg(sx1, sy1, sx2, sy2, cv, col, lw)
    if cv == 0 then
      ImGui.DrawList_AddLine(dl, sx1, sy1, sx2, sy2, col, lw)
    else
      -- 用多段直線模擬bezier曲線 -- approximate bezier with line segments
      local segs = 20
      local px, py = sx1, sy1
      for si = 1, segs do
        local f = si / segs
        local cf = FUNC.crv(f, "bezier", cv)
        local nx = sx1 + (sx2 - sx1) * f
        local ny = sy1 + (sy2 - sy1) * cf
        ImGui.DrawList_AddLine(dl, px, py, nx, ny, col, lw)
        px, py = nx, ny
      end
    end
  end

  -- 點之間的線段（支援per-segment曲率）-- segments between points with curve
  for i = 1, #pts - 1 do
    local x1 = t2x(pts[i].t)
    local y1 = FUNC.clamp(db2y(pts[i].v), wy, wy + wh)
    local x2 = t2x(pts[i + 1].t)
    local y2 = FUNC.clamp(db2y(pts[i + 1].v), wy, wy + wh)
    local lw = seg_sel(i) and line_w_sel or line_w
    local cv = pts[i].curve or 0
    -- 播放頭在線段中間→拆成兩段 -- split segment at playhead
    if env_ph_t and pts[i].t < env_ph_t and pts[i + 1].t > env_ph_t then
      local frac = (env_ph_t - pts[i].t) / (pts[i + 1].t - pts[i].t)
      local cf = cv ~= 0 and FUNC.crv(frac, "bezier", cv) or frac
      local mid_x = x1 + (x2 - x1) * frac
      local mid_y = y1 + (y2 - y1) * cf
      draw_seg(x1, y1, mid_x, mid_y, cv, env_played, lw)
      local col2 = (hov_seg == i) and env_col_hov or env_col
      draw_seg(mid_x, mid_y, x2, y2, cv, col2, lw)
    else
      local col = seg_col(pts[i].t, pts[i + 1].t, hov_seg == i)
      draw_seg(x1, y1, x2, y2, cv, col, lw)
    end
  end

  -- 最後一個點之後延伸(平線) -- flat extend after last point
  if #pts > 0 then
    local xn = t2x(pts[#pts].t)
    if xn < cx + cw then
      local y = FUNC.clamp(db2y(pts[#pts].v), wy, wy + wh)
      local last_t = pts[#pts].t
      local col = seg_col(last_t, last_t + 9999, hov_seg == #pts)
      local lw = env_drag.sel[#pts] and line_w_sel or line_w
      -- 最後延伸段也拆分 -- split flat extension at playhead
      if env_ph_t and env_ph_t > last_t then
        local ph_x = t2x(env_ph_t)
        if ph_x > xn and ph_x < cx + cw then
          ImGui.DrawList_AddLine(dl, xn, y, ph_x, y, env_played, lw)
          local col2 = (hov_seg == #pts) and env_col_hov or env_col
          ImGui.DrawList_AddLine(dl, ph_x, y, cx + cw, y, col2, lw)
        else
          ImGui.DrawList_AddLine(dl, xn, y, cx + cw, y, col, lw)
        end
      else
        ImGui.DrawList_AddLine(dl, xn, y, cx + cw, y, col, lw)
      end
    end
  end

  -- 控制點（顏色從 Settings env 色衍生） -- control points (derived from env color)
  local pt_r = FUNC.sz(5)
  local pt_r_sel = FUNC.sz(7)  -- 選取的點更大
  local pt_fill = FUNC.dim_c(FUNC.rgba(er, math.min(eg+20,255), math.min(eb+30,255), da(255)))
  local pt_fill_hov = FUNC.dim_c(FUNC.rgba(math.min(er+20,255), math.min(eg+50,255), math.min(eb+90,255), da(255)))
  local pt_sel_fill = FUNC.dim_c(FUNC.rgba(100, 200, 255, da(255)))
  local pt_sel_fill_hov = FUNC.dim_c(FUNC.rgba(150, 225, 255, da(255)))
  local pt_bord = FUNC.dim_c(FUNC.rgba(255, 255, 255, da(180)))
  for i, p in ipairs(pts) do
    local px = t2x(p.t)
    local py = FUNC.clamp(db2y(p.v), wy, wy + wh)
    if px >= cx - pt_r_sel and px <= cx + cw + pt_r_sel then
      local is_sel = is_active and env_drag.sel[i]  -- 非活躍envelope不顯示選取狀態 -- inactive: never show selected
      local is_hov = (hov_pt == i)  -- hov_pt已經在is_active guard內，非活躍時為nil
      local r = is_sel and pt_r_sel or pt_r
      local fill
      if is_sel then fill = is_hov and pt_sel_fill_hov or pt_sel_fill
      else fill = is_hov and pt_fill_hov or pt_fill end
      ImGui.DrawList_AddCircleFilled(dl, px, py, r, fill)
      ImGui.DrawList_AddCircle(dl, px, py, r, pt_bord, 0, 1.5)
    end
  end

  -- 播放頭 (播放中) -- playhead during playback
  if c.state == STATE.RUNNING and c.play_t0 > 0 then
    -- C12: 用實時 playcursor (play_offset + elapsed*rate)，跟 waveform playhead 一致
    local cr = (c.rate and c.rate > 0) and c.rate or 1.0
    local ph_t = (c.play_offset or ts) + (reaper.time_precise() - c.play_t0) * cr
    local ph_x = t2x(ph_t)
    if ph_x >= cx and ph_x <= cx + cw then
      local ph_col = FUNC.rgba(255, 255, 255, 180)
      ImGui.DrawList_AddLine(dl, ph_x, wy, ph_x, wy + wh, ph_col, 1.5)
      -- 播放頭三角指標 -- playhead triangle indicator
      ImGui.DrawList_AddTriangleFilled(dl,
        ph_x - 4, wy, ph_x + 4, wy, ph_x, wy + 6,
        FUNC.rgba(255, 255, 255, 200))
    end
  end

  -- 非活躍envelope不處理互動，只畫圖 -- inactive envelope: draw only, no interaction
  if not is_active then return end

  -- === ENVELOPE 滑鼠互動 === -- envelope mouse interaction
  local in_env = mx >= cx and mx <= cx + cw and my >= wy and my <= wy + wh

  -- 螢幕座標→envelope座標 (絕對音檔時間) -- screen coords to absolute audio time
  local function x2t(sx) return (sx - cx) / cw * vd + vs end
  local function y2db(sy) return v_max - (sy - wy) / wh * (v_max - v_min) end

  -- === TOOLTIP === -- hover/drag時顯示數值
  local tooltip_v = nil
  if env_drag.active and env_drag.pt_idx and pts[env_drag.pt_idx] then
    tooltip_v = pts[env_drag.pt_idx].v  -- 拖曳中顯示主點數值
  elseif hov_pt and pts[hov_pt] and not env_drag.edit_idx then
    tooltip_v = pts[hov_pt].v  -- hover點
  elseif hov_seg and not env_drag.edit_idx then
    -- hover線段：顯示滑鼠位置的插值 -- interpolated value at mouse pos on segment
    local hover_v = v_max - (my - wy) / wh * (v_max - v_min)
    tooltip_v = FUNC.clamp(hover_v, v_min, v_max)
  end
  if tooltip_v then
    local tip_str = format_fn(tooltip_v)
    if mode == "vol" then tip_str = tip_str .. " dB"
    elseif mode == "pan" then tip_str = tip_str .. "%" end
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding(), FUNC.sz(6), FUNC.sz(3))
    ImGui.PushStyleColor(ctx, ImGui.Col_PopupBg(), C.chrome)
    ImGui.PushStyleColor(ctx, ImGui.Col_Border(), env_color)
    ImGui.BeginTooltip(ctx)
    ImGui.Text(ctx, tip_str)
    ImGui.EndTooltip(ctx)
    ImGui.PopStyleColor(ctx, 2)
    ImGui.PopStyleVar(ctx)
  end

  -- 右鍵編輯輸入框（持續顯示，不受其他互動影響） -- right-click edit input box
  if env_drag.edit_idx then
    local ei = env_drag.edit_idx
    local p = pts[ei]  -- 用pts代替c.env_points(支援vol/pan)
    if p then
      local iw, ih = FUNC.sz(mode == "fx" and 90 or 60), FUNC.sz(20)
      -- 輸入框位置：點的右邊偏移 -- position: right of the point
      local ix = env_drag.edit_px + FUNC.sz(10)
      local iy = env_drag.edit_py - ih / 2
      -- 超出右邊界就放左邊 -- flip left if overflows right edge
      if ix + iw > cx + cw then ix = env_drag.edit_px - iw - FUNC.sz(10) end
      ImGui.SetNextWindowPos(ctx, ix, iy)
      ImGui.SetNextWindowSize(ctx, iw + FUNC.sz(8), ih + FUNC.sz(8))
      local eflags = ImGui.WindowFlags_NoTitleBar() | ImGui.WindowFlags_NoResize()
                   | ImGui.WindowFlags_NoScrollbar() | ImGui.WindowFlags_NoBackground()
      ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding(), 2, 2)
      local evis = ImGui.Begin(ctx, "##env_edit", false, eflags)
      if evis then
        ImGui.SetNextItemWidth(ctx, iw)
        if not env_drag.edit_focus then
          ImGui.SetKeyboardFocusHere(ctx)
          env_drag.edit_focus = true
        end
        local ch, nv = ImGui.InputText(ctx, "##env_val", env_drag.edit_buf,
          ImGui.InputTextFlags_EnterReturnsTrue() | ImGui.InputTextFlags_AutoSelectAll())
        if ch then env_drag.edit_buf = nv end
        -- Enter：套用數值 -- Enter: apply value
        if ImGui.IsKeyPressed(ctx, ImGui.Key_Enter()) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter()) then
          local val = parse_fn(env_drag.edit_buf)
          if val then
            p.v = FUNC.clamp(val, v_min, v_max)
            FUNC.save_cues()
          end
          env_drag.edit_idx = nil; env_drag.edit_focus = nil
        end
        -- Escape：取消 -- Escape: cancel
        if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape()) then
          env_drag.edit_idx = nil; env_drag.edit_focus = nil
        end
        -- 點擊輸入框以外的地方：取消 -- click outside: cancel
        if not ImGui.IsWindowFocused(ctx) and env_drag.edit_focus then
          env_drag.edit_idx = nil; env_drag.edit_focus = nil
        end
        ImGui.End(ctx)
      end
      ImGui.PopStyleVar(ctx)
    else
      env_drag.edit_idx = nil; env_drag.edit_focus = nil
    end
  end

  -- Opt拖曳調整線段曲率（靈敏度提高+方向修正）-- opt+drag to adjust segment curvature
  if env_drag.curve_drag then
    if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left()) then
      local dy = (my - env_drag.curve_origin_y) / FUNC.sz(40)  -- 靈敏度從100提高到40
      -- 方向修正：前點比後點大時反轉dy，讓滑鼠操作符合直覺
      local si = env_drag.curve_seg
      if pts[si] and pts[si + 1] and pts[si].v > pts[si + 1].v then
        dy = -dy  -- 下降段：反轉方向
      end
      local new_cv = FUNC.clamp(env_drag.curve_orig_val - dy, -1, 1)
      if pts[si] then
        pts[si].curve = new_cv
      end
    else
      -- 放開：如果曲率接近0就歸零 -- snap to 0 if close
      local si = env_drag.curve_seg
      if pts[si] and math.abs(pts[si].curve) < 0.05 then
        pts[si].curve = 0
      end
      env_drag.curve_drag = false
      FUNC.save_cues()
    end
    return
  end

  -- 線段拖曳中：垂直/水平移動線段頭尾兩點 -- segment drag: move both endpoints
  if env_drag.seg_drag then
    if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left()) then
      local raw_v = y2db(my)
      local raw_t = x2t(mx)
      -- Shift軸鎖定 -- shift axis lock
      if ImGui.IsKeyDown(ctx, ImGui.Mod_Shift()) then
        if not env_drag.lock then
          local dx = math.abs(mx - env_drag.origin_x)
          local dy = math.abs(my - env_drag.origin_y)
          if dx > FUNC.sz(5) or dy > FUNC.sz(5) then
            env_drag.lock = (dx >= dy) and "h" or "v"
          end
        end
      else env_drag.lock = nil end
      local dv = raw_v - env_drag.seg_origin_v
      local dt = raw_t - env_drag.seg_origin_t
      if env_drag.lock == "h" then dv = 0 end
      if env_drag.lock == "v" then dt = 0 end
      local si1 = env_drag.seg_i1
      local si2 = env_drag.seg_i2
      local o1 = env_drag.seg_o1
      local o2 = env_drag.seg_o2
      if pts[si1] and o1 then
        pts[si1].v = FUNC.clamp(o1.v + dv, v_min, v_max)
        pts[si1].t = FUNC.clamp(o1.t + dt, ts, te)
      end
      if si2 and pts[si2] and o2 then
        pts[si2].v = FUNC.clamp(o2.v + dv, v_min, v_max)
        pts[si2].t = FUNC.clamp(o2.t + dt, ts, te)
      end
      -- 水平移動時自動刪除進入範圍的點 -- auto-delete points that enter the segment range
      if math.abs(dt) > 0.001 and si1 and si2 then
        local t_lo = math.min(pts[si1].t, pts[si2].t)
        local t_hi = math.max(pts[si1].t, pts[si2].t)
        local i = 1
        while i <= #pts do
          if i ~= si1 and i ~= si2 then
            local pt = pts[i].t
            if pt > t_lo and pt < t_hi then
              table.remove(pts, i)
              -- index調整 -- adjust indices after removal
              if si1 > i then si1 = si1 - 1; env_drag.seg_i1 = si1 end
              if si2 > i then si2 = si2 - 1; env_drag.seg_i2 = si2 end
            else i = i + 1 end
          else i = i + 1 end
        end
      end
    else
      -- 放開：排序+存檔 -- release: sort + save
      FUNC.env_sort(pts)
      env_drag.seg_drag = false
      env_drag.lock = nil
      FUNC.save_cues()
    end
    return
  end

  -- 拖曳中：移動控制點（多點選取時一起移動）-- dragging: move point(s), multi-select moves together
  if env_drag.active and env_drag.pt_idx then
    if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left()) then
      local raw_t = x2t(mx)
      local raw_v = y2db(my)
      -- Shift軸鎖定：先判定方向，再鎖定 -- shift axis lock
      if ImGui.IsKeyDown(ctx, ImGui.Mod_Shift()) then
        if not env_drag.lock then
          local dx = math.abs(mx - env_drag.origin_x)
          local dy = math.abs(my - env_drag.origin_y)
          if dx > FUNC.sz(5) or dy > FUNC.sz(5) then
            env_drag.lock = (dx >= dy) and "h" or "v"
          end
        end
      else
        env_drag.lock = nil
      end
      -- 計算主拖曳點的 delta -- compute delta from primary drag point
      local p = pts[env_drag.pt_idx]
      if p and env_drag.drag_origins then
        local orig = env_drag.drag_origins[env_drag.pt_idx]
        if orig then
          local dt = FUNC.clamp(raw_t, ts, te) - orig.t
          local dv = FUNC.clamp(raw_v, v_min, v_max) - orig.v
          if env_drag.lock == "h" then dv = 0 end
          if env_drag.lock == "v" then dt = 0 end
          -- 多點移動：所有選取的點用同樣的delta -- apply delta to all selected points
          local moving = {}
          if env_drag.sel[env_drag.pt_idx] then
            for i in pairs(env_drag.sel) do moving[i] = true end
          else
            moving[env_drag.pt_idx] = true  -- 只移動主點
          end
          for i in pairs(moving) do
            local po = env_drag.drag_origins[i]
            if po and pts[i] then
              pts[i].t = FUNC.clamp(po.t + dt, ts, te)
              pts[i].v = FUNC.clamp(po.v + dv, v_min, v_max)
            end
          end
        end
      end
    else
      -- 放開滑鼠：結束拖曳，排序+存檔 -- mouse up: finish drag
      FUNC.env_sort(pts)
      env_drag.active = false
      env_drag.pt_idx = nil
      env_drag.lock = nil
      env_drag.drag_origins = nil
      FUNC.save_cues()
    end
    return  -- 拖曳中不處理其他互動
  end

  -- 框選中：即時更新選取 -- marquee: update selection in real-time
  if env_drag.marquee then
    if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left()) then
      local rx1 = math.min(env_drag.mq_x1, mx)
      local ry1 = math.min(env_drag.mq_y1, my)
      local rx2 = math.max(env_drag.mq_x1, mx)
      local ry2 = math.max(env_drag.mq_y1, my)
      -- 畫框選矩形 -- draw marquee rect
      ImGui.DrawList_AddRectFilled(dl, rx1, ry1, rx2, ry2, FUNC.rgba(100, 200, 255, 30))
      ImGui.DrawList_AddRect(dl, rx1, ry1, rx2, ry2, FUNC.rgba(100, 200, 255, 150), 0, 0, 1)
      -- 判定哪些點在框內（只選可見範圍內的點）-- find visible points inside rect
      local in_rect = {}
      for i, p in ipairs(pts) do
        local px = t2x(p.t)
        local py = FUNC.clamp(db2y(p.v), wy, wy + wh)
        -- 過濾掉不在可見波形區域內的點 -- filter out off-screen points
        if px >= cx and px <= cx + cw and
           px >= rx1 and px <= rx2 and py >= ry1 and py <= ry2 then
          in_rect[i] = true
        end
      end
      -- 根據模式更新選取 -- update selection based on mode
      if env_drag.mq_mode == "set" then
        -- 純左鍵：只選框內 -- plain: select only inside
        env_drag.sel = {}
        for i in pairs(in_rect) do env_drag.sel[i] = true end
      elseif env_drag.mq_mode == "add" then
        -- Shift：原選取 + 框內 -- shift: add to existing
        env_drag.sel = {}
        for i, v in pairs(env_drag.mq_snap) do env_drag.sel[i] = v end  -- 還原原本選取
        for i in pairs(in_rect) do env_drag.sel[i] = true end
      elseif env_drag.mq_mode == "toggle" then
        -- Cmd：toggle 框內 -- cmd: toggle inside
        env_drag.sel = {}
        for i, v in pairs(env_drag.mq_snap) do env_drag.sel[i] = v end  -- 還原原本選取
        for i in pairs(in_rect) do
          env_drag.sel[i] = not env_drag.mq_snap[i] or nil  -- toggle
        end
      end
    else
      -- 放開滑鼠：結束框選 -- mouse up: end marquee
      env_drag.marquee = false
    end
    return  -- 框選中不處理其他互動
  end

  -- 線段pending中：拖曳→移動線段 / 放開→在線段上新增點 -- seg pending: drag→seg_drag / release→add point on segment
  if env_drag.seg_pending then
    if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left()) then
      local dx = math.abs(mx - env_drag.origin_x)
      local dy = math.abs(my - env_drag.origin_y)
      if dx > FUNC.sz(4) or dy > FUNC.sz(4) then
        -- 超過門檻：開始線段拖曳 -- threshold: start segment drag
        env_drag.seg_pending = false
        env_drag.seg_drag = true
      end
    else
      -- 放開：在線段位置新增點並only select -- release: add point on segment, select only it
      env_drag.seg_pending = false
      local nt = FUNC.clamp(x2t(env_drag.origin_x), ts, te)
      local nv = FUNC.clamp(y2db(env_drag.origin_y), v_min, v_max)
      add_point_fn(nt, nv)
      -- 找到新增的點index並only select -- find new point index and select only it
      env_drag.sel = {}
      for i, p in ipairs(pts) do
        if math.abs(p.t - nt) < 0.001 and math.abs(p.v - nv) < 0.01 then
          env_drag.sel[i] = true; break
        end
      end
      FUNC.save_cues()
    end
    return
  end

  -- 待判定中：拖曳→框選 / 放開→新增點 -- pending: drag→marquee / release→add point
  if env_drag.pending then
    if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left()) then
      local dx = math.abs(mx - env_drag.origin_x)
      local dy = math.abs(my - env_drag.origin_y)
      if dx > FUNC.sz(4) or dy > FUNC.sz(4) then
        -- 超過門檻：開始框選 -- threshold exceeded: start marquee
        env_drag.pending = false
        env_drag.marquee = true
        env_drag.mq_x1 = env_drag.origin_x
        env_drag.mq_y1 = env_drag.origin_y
      end
    else
      -- 放開滑鼠：沒拖曳，判定為新增點（僅無修飾鍵時） -- release without drag: add point (no modifier only)
      env_drag.pending = false
      if env_drag.mq_mode == "set" then
        local nt = FUNC.clamp(x2t(env_drag.origin_x), ts, te)
        local nv = FUNC.clamp(y2db(env_drag.origin_y), v_min, v_max)
        add_point_fn(nt, nv)
        env_drag.sel = {}  -- 新增點清除選取
        FUNC.save_cues()
      end
    end
    return
  end

  -- 輸入框開啟中不處理新的點擊 -- skip clicks while edit box is open
  if env_drag.edit_idx then return end

  -- 找最近的控制點（雙擊/單擊/右鍵共用） -- find nearest point for all click types
  local function find_near_pt()
    local best_i, best_d = nil, ENV_HIT_R * ENV_HIT_R
    for i, p in ipairs(pts) do
      local px = t2x(p.t)
      local py = FUNC.clamp(db2y(p.v), wy, wy + wh)
      local dx, dy = mx - px, my - py
      local d2 = dx * dx + dy * dy
      if d2 < best_d then best_d = d2; best_i = i end
    end
    return best_i
  end

  if not in_env or wf_handle.dragging then return end

  local mod_cmd = ImGui.IsKeyDown(ctx, ImGui.Mod_Super())    -- Cmd
  local mod_opt = ImGui.IsKeyDown(ctx, ImGui.Mod_Alt())      -- Opt
  local mod_shift = ImGui.IsKeyDown(ctx, ImGui.Mod_Shift())  -- Shift

  -- 雙擊控制點：歸零到 0dB -- double-click: reset to 0dB
  if ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left()) and not mod_cmd and not mod_opt then
    local hi = find_near_pt()
    if hi then
      pts[hi].v = reset_v  -- 歸零(vol=0dB, pan=center, fx=mid)
      FUNC.save_cues()
      return  -- 不再觸發單擊
    end
  end

  -- 左鍵按下 -- left click
  if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left()) then
    local hi = find_near_pt()

    -- Opt+左鍵線段：調整曲率 -- opt+click segment: adjust curve
    if mod_opt and not hi and hov_seg and hov_seg >= 1 and hov_seg <= #pts - 1 then
      env_drag.curve_drag = true
      env_drag.curve_seg = hov_seg
      env_drag.curve_origin_y = my
      env_drag.curve_orig_val = pts[hov_seg].curve or 0
      return
    end

    -- Opt+左鍵：刪除控制點 -- opt+click: delete point
    if mod_opt and hi then
      table.remove(pts, hi)  -- 直接從pts刪除(支援vol/pan)
      -- 刪除後清理選取 -- clean up selection after delete
      local new_sel = {}
      for k in pairs(env_drag.sel) do
        if k < hi then new_sel[k] = true
        elseif k > hi then new_sel[k - 1] = true end  -- index shift
      end
      env_drag.sel = new_sel
      FUNC.save_cues()
      return
    end

    -- Cmd+左鍵點控制點：toggle選取 -- cmd+click point: toggle selection
    if mod_cmd and hi then
      env_drag.sel[hi] = not env_drag.sel[hi] or nil
      return
    end

    -- 左鍵單擊選取點+拖曳（多點一起移動）-- click to select + drag (multi-point move)
    if hi then
      -- 單擊選取邏輯：Shift加選，普通單擊若未選則單選 -- click-to-select logic
      if mod_shift then
        env_drag.sel[hi] = true  -- Shift+click: 加入選取
      elseif not env_drag.sel[hi] then
        env_drag.sel = {[hi] = true}  -- 未選的點：清除其他，選此點
      end
      -- else: 已選的點直接拖曳，不改選取
      env_drag.active = true
      env_drag.pt_idx = hi
      env_drag.origin_x = mx  -- shift軸鎖定起始點
      env_drag.origin_y = my
      env_drag.lock = nil
      -- 快照所有點的初始位置（多點移動用delta） -- snapshot origins for delta-based multi-move
      env_drag.drag_origins = {}
      for i, p in ipairs(pts) do
        env_drag.drag_origins[i] = {t = p.t, v = p.v}
      end
    -- 線段點擊：先pending，拖曳→移動線段，放開→新增點 -- segment click: pending, drag→move, release→add point
    elseif hov_seg then  -- 點在線段上：一律進入 seg_pending，mod key 不觸發 marquee
      local si1, si2
      if hov_seg == 0 then
        si1 = 1; si2 = nil
      elseif hov_seg == #pts then
        si1 = #pts; si2 = nil
      else
        si1 = hov_seg; si2 = hov_seg + 1
      end
      env_drag.seg_pending = true  -- 等待判定：拖曳或新增點
      env_drag.seg_i1 = si1
      env_drag.seg_i2 = si2
      env_drag.seg_o1 = {t = pts[si1].t, v = pts[si1].v}
      env_drag.seg_o2 = si2 and {t = pts[si2].t, v = pts[si2].v} or nil
      env_drag.origin_x = mx
      env_drag.origin_y = my
      env_drag.seg_origin_v = y2db(my)
      env_drag.seg_origin_t = x2t(mx)
      env_drag.lock = nil
    -- 空白處：有選取點時先取消選取；沒有選取點才進入新增/框選模式
    else
      -- 有已選取的點且無修飾鍵→先取消全部選取，不新增點
      if not mod_cmd and not mod_shift and next(env_drag.sel) then
        env_drag.sel = {}
      else
        env_drag.pending = true  -- 等待判定中
        env_drag.origin_x = mx
        env_drag.origin_y = my
        -- 記住修飾鍵狀態 -- snapshot modifier state
        if mod_cmd then env_drag.mq_mode = "toggle"
        elseif mod_shift then env_drag.mq_mode = "add"
        else env_drag.mq_mode = "set" end
        -- 快照原本選取 -- snapshot current selection
        local snap = {}
        for k, v in pairs(env_drag.sel) do snap[k] = v end
        env_drag.mq_snap = snap
      end
    end
  end

  -- Delete/Backspace刪除選取的控制點 -- delete selected points with keyboard
  if in_env and (ImGui.IsKeyPressed(ctx, ImGui.Key_Delete()) or ImGui.IsKeyPressed(ctx, ImGui.Key_Backspace())) then
    local to_del = {}
    for k in pairs(env_drag.sel) do to_del[#to_del + 1] = k end
    if #to_del > 0 then
      table.sort(to_del, function(a, b) return a > b end)  -- 從後往前刪避免index錯位
      for _, idx in ipairs(to_del) do
        if idx >= 1 and idx <= #pts then table.remove(pts, idx) end  -- 直接從pts刪(支援vol/pan)
      end
      env_drag.sel = {}
      FUNC.save_cues()
    end
  end

  -- 右鍵控制點：開啟數值輸入框 -- right-click: open value edit box
  if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right()) then
    local hi = find_near_pt()
    if hi then
      local p = pts[hi]
      env_drag.edit_idx = hi
      env_drag.edit_buf = format_fn(p.v)
      env_drag.edit_px = t2x(p.t)
      env_drag.edit_py = FUNC.clamp(db2y(p.v), wy, wy + wh)
      env_drag.edit_focus = nil  -- 下一幀才 focus
      -- 取消同一幀被 waveform 搶走的右鍵平移 -- cancel waveform pan started this frame
      wf_drag.active = false
    end
  end

end

---------------------------------------------------------------------
-- FX PARAMETER ENVELOPE -- FX參數 envelope
---------------------------------------------------------------------
-- 設計概要 -- design notes:
-- - 每個PLAY cue可有多筆fx_envs，每筆綁一個FX param (fx_guid+param_idx)
-- - 資料儲存在 c.fx_envs = {{fx_guid,param_idx,fx_name,param_name,enabled,visible,color,points}, ...}
-- - 透過cue的track_idx去取得tr，fx_guid解析為當下的fx_idx (快取)
-- - engage/disengage時以 "fx_guid:param_idx" 為key在_trk_state[guid].fx_params做refcount+存原值
-- - apply時呼叫TrackFX_SetParam寫入
-- - new touch捕捉：poll GetLastTouchedFX比對初始快照
---------------------------------------------------------------------

-- 去掉 FX 名稱前綴（VST3i:, VST:, AU:, JS:, CLAP:, LV2:, DX: 等）-- strip FX format prefix
local FX_PREFIXES = {
  "VST3i:", "VST3:", "VSTi:", "VST:",
  "AUi:", "AU:",
  "CLAPi:", "CLAP:",
  "LV2i:", "LV2:",
  "DXi:", "DX:",
  "JS:",
}
-- FX 視窗置中：請求加入 queue，process_fx_recenter() 每 frame 處理
-- 需延後 frame 因為 TrackFX_Show 同 frame 內 hwnd 尚未就緒
-- center FX floating window: queue request, processed each frame; deferred since hwnd isn't ready same-frame

-- 螢幕解析度（logical pixels，retina 已除）一次性偵測並 cache
-- get screen resolution in logical pixels (retina-corrected), cached on first call
local _scr_w, _scr_h
local function get_screen_resolution(reScan)
  if not reScan and _scr_w and _scr_h then return _scr_w, _scr_h end
  local OS = reaper.GetOS()
  local file, result, w, h
  if OS:find("OS") then
    file = io.popen("system_profiler SPDisplaysDataType | awk '/Resolution/ {print $2, $4}'")
  elseif OS:find("Win") then
    file = io.popen("wmic path Win32_VideoController get CurrentHorizontalResolution,CurrentVerticalResolution /format:value")
  else
    file = io.popen("xrandr | grep '*'")
  end
  if file then
    result = file:read("*a") or ""
    file:close()
    if OS:find("Win") then
      w = result:match("CurrentHorizontalResolution=(%d+)")
      h = result:match("CurrentVerticalResolution=(%d+)")
    else
      w, h = result:match("(%d+)[x%s]+(%d+)")
    end
  end
  w = tonumber(w) or 1920
  h = tonumber(h) or 1080
  -- retina/DPI 縮放：gfx.init 取 ext_retina 後立即 quit
  local scale = 1
  gfx.ext_retina = 1
  gfx.init("", 1, 1)
  scale = (gfx.ext_retina and gfx.ext_retina > 0) and gfx.ext_retina or 1
  gfx.quit()
  _scr_w = math.floor(w / scale)
  _scr_h = math.floor(h / scale)
  return _scr_w, _scr_h
end
FUNC.get_screen_resolution = get_screen_resolution

-- JS_Window_GetRect 包裝：回 l, t, r, b（平台原始座標慣例）
-- macOS bottom-left 原點：t > b；Win/Linux top-left 原點：b > t
function FUNC.get_window_pos(hwnd)
  if not (hwnd and reaper.JS_Window_GetRect) then return end
  local _, l, t, r, b = reaper.JS_Window_GetRect(hwnd)
  return l, t, r, b
end

-- JS_Window_SetPosition 包裝：傳入 l, b, r, t（與 get_window_pos 對稱），自動算 w/h
function FUNC.set_window_pos(hwnd, l, b, r, t)
  if not (hwnd and reaper.JS_Window_SetPosition) then return end
  reaper.JS_Window_SetPosition(hwnd, math.floor(l), math.floor(b), math.floor(r - l), math.floor(math.abs(t - b)))
end

_pending_fx_recenter = _pending_fx_recenter or {}
function FUNC.fx_window_recenter_if_needed(tr, fx_idx)
  if not (tr and fx_idx and reaper.JS_Window_SetPosition) then return end
  table.insert(_pending_fx_recenter, { tr = tr, fx_idx = fx_idx, frames = 0 })
end
function FUNC.process_fx_recenter()
  if #_pending_fx_recenter == 0 then return end
  for i = #_pending_fx_recenter, 1, -1 do
    local it = _pending_fx_recenter[i]
    it.frames = it.frames - 1
    if it.frames <= 0 then
      local hwnd = reaper.TrackFX_GetFloatingWindow(it.tr, it.fx_idx)
      if hwnd then
        local l, t, r, b = FUNC.get_window_pos(hwnd)
        if l and t and r and b then
          local w = math.abs(r - l)
          local h = math.abs(b - t)
          if w > 0 and h > 0 then
            local sw, sh = get_screen_resolution()
            local new_l = math.floor((sw - w) / 2)
            local new_r = new_l + w
            local new_b, new_t
            if t > b then  -- macOS bottom-left
              new_b = math.floor((sh - h) / 2)
              new_t = new_b + h
            else  -- Win/Linux top-left
              new_t = math.floor((sh - h) / 2)
              new_b = new_t + h
            end
            FUNC.set_window_pos(hwnd, new_l, new_b, new_r, new_t)
          end
        end
      end
      table.remove(_pending_fx_recenter, i)
    end
  end
end

function FUNC.fx_env_short_name(fx_name)
  if not fx_name or fx_name == "" then return "" end
  local s = fx_name:gsub("^%s+", "")
  for _, pre in ipairs(FX_PREFIXES) do
    if s:sub(1, #pre) == pre then
      s = s:sub(#pre + 1):gsub("^%s+", "")
      break
    end
  end
  -- 去掉結尾的廠商名 "(Vendor)" -- strip trailing vendor in parens
  s = s:gsub("%s*%b()%s*$", "")
  return s
end

_fx_idx_cache = _fx_idx_cache or {}
function FUNC.fx_idx_cache_clear() _fx_idx_cache = {} end
function FUNC.fx_guid_to_idx(tr, fx_guid)
  if not tr or not fx_guid or fx_guid == "" then return nil end
  local key = tostring(tr) .. ":" .. fx_guid
  local cached = _fx_idx_cache[key]
  if cached ~= nil then
    local g = reaper.TrackFX_GetFXGUID(tr, cached)
    if g == fx_guid then return cached end
    _fx_idx_cache[key] = nil
  end
  local cnt = reaper.TrackFX_GetCount(tr) or 0
  for i = 0, cnt - 1 do
    local g = reaper.TrackFX_GetFXGUID(tr, i)
    if g == fx_guid then _fx_idx_cache[key] = i; return i end
  end
  return nil
end

-- 起始化：2個點，皆為當下的 normalized 值（水平線）-- init: 2 horizontal points at current value
function FUNC.fx_env_init_points(c, fe)
  local dur = env_eff_dur(c)
  local v = 0.5
  local tr = FUNC.get_tr(c.track_idx)
  if tr then
    local fi = FUNC.fx_guid_to_idx(tr, fe.fx_guid)
    if fi then v = reaper.TrackFX_GetParam(tr, fi, fe.param_idx) or 0.5 end
  end
  fe.points = {
    {t = 0,   v = v, curve = 0},
    {t = dur, v = v, curve = 0},
  }
end

-- 檢查同一個FX param是否已存在 -- check duplicate fx param
function FUNC.fx_env_has(c, fx_guid, param_idx)
  if not c.fx_envs then return false end
  for _, fe in ipairs(c.fx_envs) do
    if fe.fx_guid == fx_guid and fe.param_idx == param_idx then return true end
  end
  return false
end

-- 預設顏色池（循環使用）-- default color palette for new fx_envs
-- 避開 vol(黃/橘)、pan(綠)、pitch(藍) 及其相近色 -- avoid vol/pan/pitch hues
local FX_ENV_COLORS = {
  0xE64050FF,  -- 紅 red
  0xE040A0FF,  -- 桃紅 pink
  0xC040E0FF,  -- 紫 purple
  0xFF50C8FF,  -- 洋紅 magenta
  0xB080FFFF,  -- 薰衣草 lavender
  0xE080B8FF,  -- 玫瑰 rose
  0xA05878FF,  -- 酒紅 mauve
  0xD8D8E0FF,  -- 白灰 off-white
}

-- Pending 開始：抓當下的 GetLastTouchedFX 作為初始快照 -- begin pending: snapshot current touched fx
function FUNC.fx_env_begin_pending(c)
  if not c or c.type ~= "PLAY" then return end
  local ok, tr_n, fx_n, pr_n = reaper.GetLastTouchedFX()
  if not ok then tr_n, fx_n, pr_n = 0, 0, 0 end
  fx_env_pending = {
    cue_id = c.id,
    init_tr = tr_n or 0,
    init_fx = fx_n or 0,
    init_param = pr_n or 0,
  }
end

function FUNC.fx_env_cancel_pending() fx_env_pending = nil end

-- 每幀 poll：偵測到新的 last-touched FX 就建立env -- poll pending; accept new touch
function FUNC.fx_env_poll_pending()
  if not fx_env_pending then return end
  local ok, tr_n, fx_n, pr_n = reaper.GetLastTouchedFX()
  if not ok then return end
  -- 若與初始快照不同→視為新 touch -- changed from initial snapshot → new touch
  if tr_n == fx_env_pending.init_tr and fx_n == fx_env_pending.init_fx and pr_n == fx_env_pending.init_param then
    return
  end
  -- 定位 cue 與它的 track -- locate cue and its track
  local ci = FUNC.find_id(fx_env_pending.cue_id)
  if not ci then fx_env_pending = nil; return end
  local c = cues[ci]
  if not c or c.type ~= "PLAY" then fx_env_pending = nil; return end
  local c_tr = FUNC.get_tr(c.track_idx)
  if not c_tr then fx_env_pending = nil; return end
  -- GetLastTouchedFX 的 tr_n 是 1-based；0x1000000 為 master，我們忽略 -- tracknumber is 1-based
  if tr_n == 0 or tr_n >= 0x1000000 then return end  -- 再等一次，可能還會抓到正確 track
  local touched_tr = reaper.GetTrack(0, tr_n - 1)
  if touched_tr ~= c_tr then
    -- 使用者點到不同軌道的 FX → 忽略、繼續等 -- touched on different track; keep waiting
    return
  end
  -- fx_n 高位 bit 0x2000000 = input fx；去除掉 -- strip input-fx bit
  local fx_idx = fx_n & 0xFFFFFF
  if fx_idx < 0 then return end
  local fx_guid = reaper.TrackFX_GetFXGUID(c_tr, fx_idx) or ""
  if fx_guid == "" then return end
  -- Q11: 禁止重複 -- reject duplicate
  if FUNC.fx_env_has(c, fx_guid, pr_n) then fx_env_pending = nil; return end
  -- 取名稱 -- fetch names
  local _, fx_name = reaper.TrackFX_GetFXName(c_tr, fx_idx, "")
  local _, param_name = reaper.TrackFX_GetParamName(c_tr, fx_idx, pr_n, "")
  -- 建立新 env -- create new env
  c.fx_envs = c.fx_envs or {}
  local new_color = FX_ENV_COLORS[(#c.fx_envs % #FX_ENV_COLORS) + 1]
  local fe = {
    fx_guid = fx_guid,
    param_idx = pr_n,
    fx_name = fx_name or "",
    param_name = param_name or "",
    enabled = true,
    visible = true,
    color = new_color,
    points = {},
  }
  FUNC.fx_env_init_points(c, fe)
  c.fx_envs[#c.fx_envs + 1] = fe
  -- 若cue正在播放，立即engage這條env的參數 -- if cue running, engage this param immediately
  if c.state == STATE.RUNNING and _trk_state[c.track_guid or ""] then
    FUNC.fx_env_engage_one(c, fe)
  end
  fx_env_pending = nil
  FUNC.save_cues()
end

-- 將單一 env 的參數存進 _trk_state（若尚未存過）+ refcount++
function FUNC.fx_env_engage_one(c, fe)
  local guid = c.track_guid or ""
  local st = _trk_state[guid]
  if not st then return end  -- 必須先有 env_save_track 建立 st
  st.fx_params = st.fx_params or {}
  local key = fe.fx_guid .. ":" .. tostring(fe.param_idx)
  local rec = st.fx_params[key]
  if not rec then
    local tr = FUNC.get_tr(c.track_idx)
    if not tr then return end
    local fi = FUNC.fx_guid_to_idx(tr, fe.fx_guid)
    if not fi then return end  -- FX missing → skip; 不記 orig
    local orig = reaper.TrackFX_GetParam(tr, fi, fe.param_idx) or 0
    st.fx_params[key] = {orig = orig, by = {[c.id] = true}}
  else
    rec.by[c.id] = true  -- 同一個 cue 重複 engage 只算一次 -- same cue engaging again counts once
  end
end

-- Cue 開始播放：對所有 fx_envs 呼叫 engage_one -- cue start: engage all envs
function FUNC.fx_env_engage(c)
  if not c.fx_envs or #c.fx_envs == 0 then return end
  for _, fe in ipairs(c.fx_envs) do
    if fe.enabled then FUNC.fx_env_engage_one(c, fe) end
  end
end

-- Cue 結束：refs-- ，refs=0 時還原原值 -- cue end: decrement refs and restore
function FUNC.fx_env_disengage(c)
  if not c.fx_envs or #c.fx_envs == 0 then return end
  local guid = c.track_guid or ""
  local st = _trk_state[guid]
  if not st or not st.fx_params then return end
  local tr = FUNC.get_tr(c.track_idx) or reaper.BR_GetMediaTrackByGUID(0, guid)
  for _, fe in ipairs(c.fx_envs) do
    if fe.enabled then
      local key = fe.fx_guid .. ":" .. tostring(fe.param_idx)
      local rec = st.fx_params[key]
      if rec then
        rec.by[c.id] = nil
        if not next(rec.by) then
          if tr then
            local fi = FUNC.fx_guid_to_idx(tr, fe.fx_guid)
            if fi then reaper.TrackFX_SetParam(tr, fi, fe.param_idx, rec.orig) end
          end
          st.fx_params[key] = nil
        end
      end
    end
  end
end

-- 還原單一 track 上所有殘留的 fx_params（panic/restore_all 使用）-- cleanup all fx params on a track
function FUNC.fx_env_restore_track_params(tr, st)
  if not st or not st.fx_params then return end
  for key, rec in pairs(st.fx_params) do
    local fx_guid, p_idx = key:match("^(.-):(%-?%d+)$")
    p_idx = tonumber(p_idx)
    if fx_guid and p_idx and tr then
      local fi = FUNC.fx_guid_to_idx(tr, fx_guid)
      if fi then reaper.TrackFX_SetParam(tr, fi, p_idx, rec.orig) end
    end
  end
  st.fx_params = nil
end

-- 每幀套用 -- per-frame apply
function FUNC.fx_env_apply_all()
  local now = reaper.time_precise()
  for _, c in ipairs(cues) do
    if c.type == "PLAY" and c.fx_envs and #c.fx_envs > 0
        and c.state == STATE.RUNNING and c.play_t0 > 0 then
      local tr = FUNC.get_tr(c.track_idx)
      if tr then
        -- C12: 用實時 playcursor (play_offset + elapsed*rate)，不被 trim 拖曳影響
        local cr = (c.rate and c.rate > 0) and c.rate or 1.0
        local t_abs = (c.play_offset or c.trim_start or 0) + (now - c.play_t0) * cr
        for _, fe in ipairs(c.fx_envs) do
          if fe.enabled and fe.points and #fe.points > 0 and not fe._missing then
            local fi = FUNC.fx_guid_to_idx(tr, fe.fx_guid)
            if fi then
              local v = FUNC.env_interp(fe.points, t_abs)
              reaper.TrackFX_SetParam(tr, fi, fe.param_idx, v)
            end
          end
        end
      end
    end
  end
end

-- 載入後掃描：檢查所有cue的fx_envs是否有遺失的FX -- post-load scan for missing FX
-- 呼叫時機：load_cues後 或 特定cue被選取時。不自動pop warn，由UI觸發
function FUNC.fx_env_check_missing(c)
  if not c or not c.fx_envs or #c.fx_envs == 0 then return nil end
  local tr = FUNC.get_tr(c.track_idx)
  if not tr then return nil end
  for i, fe in ipairs(c.fx_envs) do
    local fi = FUNC.fx_guid_to_idx(tr, fe.fx_guid)
    if not fi then
      fe._missing = true
      return {cue_id = c.id, env_idx = i, fx_name = fe.fx_name, param_name = fe.param_name}
    else
      fe._missing = nil
    end
  end
  return nil
end

-- 刪除一條fx_env（若cue在播放則先 disengage 該條）-- remove fx_env
function FUNC.fx_env_remove(c, idx)
  if not c.fx_envs or idx < 1 or idx > #c.fx_envs then return end
  local fe = c.fx_envs[idx]
  -- 若cue running且該env enabled，先 disengage 該條 param
  if c.state == STATE.RUNNING and fe.enabled then
    local guid = c.track_guid or ""
    local st = _trk_state[guid]
    if st and st.fx_params then
      local key = fe.fx_guid .. ":" .. tostring(fe.param_idx)
      local rec = st.fx_params[key]
      if rec then
        rec.by[c.id] = nil
        if not next(rec.by) then
          local tr = FUNC.get_tr(c.track_idx)
          if tr then
            local fi = FUNC.fx_guid_to_idx(tr, fe.fx_guid)
            if fi then reaper.TrackFX_SetParam(tr, fi, fe.param_idx, rec.orig) end
          end
          st.fx_params[key] = nil
        end
      end
    end
  end
  table.remove(c.fx_envs, idx)
end

-- 格式化 param 顯示值（供 tooltip 等外部呼叫）-- format normalized param value for tooltip use
function FUNC.fx_env_format_value(c, fe, v)
  local tr = FUNC.get_tr(c.track_idx)
  if tr then
    local fi = FUNC.fx_guid_to_idx(tr, fe.fx_guid)
    if fi then
      local ok, s = reaper.TrackFX_FormatParamValueNormalized(tr, fi, fe.param_idx, v)
      if ok and s and s ~= "" then return s end
    end
  end
  return string.format("%.3f", v)
end

-- 繪製所有 fx_envs（visible 的才畫）；active 的最後畫在最上層
-- draw all fx envs; active drawn last on top
function FUNC.fx_env_draw_all(c, dl, wf_info)
  if not c or not c.fx_envs then return end
  local act = (env_edit_mode == "fx") and fx_env_edit_idx or nil
  for i = 1, #c.fx_envs do
    if i ~= act and c.fx_envs[i].visible then FUNC.env_draw(c, dl, wf_info, "fx", c.fx_envs[i]) end
  end
  if act and c.fx_envs[act] and c.fx_envs[act].visible then
    FUNC.env_draw(c, dl, wf_info, "fx", c.fx_envs[act])
  end
end

-- (legacy, no-op kept for safety) -- interaction is now handled inside env_draw
function FUNC.fx_env_interact(c, wf_info) end

-- 以下為舊版殘留 (dead code, replaced by env_draw refactor) -- dead code below
local function _UNUSED_fx_env_draw(c, dl, wf_info, fe, is_active)
  if not fe or not fe.visible or not fe.points or #fe.points == 0 then return end
  local cx, wy, cw, wh = wf_info.cx, wf_info.wy, wf_info.cw, wf_info.wh
  local vs, vd = wf_info.view_start, wf_info.view_dur
  local ts = wf_info.trim_start
  local col_rgba = fe.color or 0xFFAA33FF
  local er = (col_rgba >> 24) & 0xFF
  local eg = (col_rgba >> 16) & 0xFF
  local eb = (col_rgba >> 8)  & 0xFF
  local dim_a = is_active and 1.0 or 0.72
  local function da(a) return math.floor(a * dim_a) end
  local line_col = FUNC.dim_c(FUNC.rgba(er, eg, eb, da(220)))
  local pt_fill  = FUNC.dim_c(FUNC.rgba(math.min(er+20,255), math.min(eg+20,255), math.min(eb+20,255), da(255)))
  local pt_bord  = FUNC.dim_c(FUNC.rgba(255, 255, 255, da(180)))
  local function t2x(et) return cx + ((ts + et - vs) / vd) * cw end
  local function v2y(v)  return wy + wh * (1 - FUNC.clamp(v, 0, 1)) end
  local pts = fe.points
  local lw = is_active and 3.0 or 2.0
  -- 前延伸 -- flat extend before first
  local x0 = t2x(pts[1].t)
  local y0 = v2y(pts[1].v)
  if x0 > cx then ImGui.DrawList_AddLine(dl, cx, y0, x0, y0, line_col, lw) end
  -- 點間線段 -- segments
  for i = 1, #pts - 1 do
    local x1, y1 = t2x(pts[i].t),   v2y(pts[i].v)
    local x2, y2 = t2x(pts[i+1].t), v2y(pts[i+1].v)
    local cv = pts[i].curve or 0
    if cv == 0 then
      ImGui.DrawList_AddLine(dl, x1, y1, x2, y2, line_col, lw)
    else
      local segs, px, py = 20, x1, y1
      for si = 1, segs do
        local f = si / segs
        local cf = FUNC.crv(f, "bezier", cv)
        local nx = x1 + (x2 - x1) * f
        local ny = y1 + (y2 - y1) * cf
        ImGui.DrawList_AddLine(dl, px, py, nx, ny, line_col, lw)
        px, py = nx, ny
      end
    end
  end
  -- 後延伸 -- flat extend after last
  local xn = t2x(pts[#pts].t)
  local yn = v2y(pts[#pts].v)
  if xn < cx + cw then ImGui.DrawList_AddLine(dl, xn, yn, cx + cw, yn, line_col, lw) end
  -- 控制點 -- control points
  local pr = FUNC.sz(is_active and 5 or 4)
  for _, p in ipairs(pts) do
    local px, py = t2x(p.t), v2y(p.v)
    if px >= cx - pr and px <= cx + cw + pr then
      ImGui.DrawList_AddCircleFilled(dl, px, py, pr, pt_fill, 12)
      ImGui.DrawList_AddCircle(dl, px, py, pr, pt_bord, 12, 1)
    end
  end
end

local function _UNUSED_fx_env_interact(c, wf_info)
  local fe = get_active_fe(c)
  if not fe or not fe.points or not fe.visible then return end
  local cx, wy, cw, wh = wf_info.cx, wf_info.wy, wf_info.cw, wf_info.wh
  local vs, vd = wf_info.view_start, wf_info.view_dur
  local ts = wf_info.trim_start
  local function t2x(et) return cx + ((ts + et - vs) / vd) * cw end
  local function x2t(x)  return ((x - cx) / cw) * vd + vs - ts end
  local function v2y(v)  return wy + wh * (1 - FUNC.clamp(v, 0, 1)) end
  local function y2v(y)  return FUNC.clamp(1 - (y - wy) / wh, 0, 1) end

  local mx, my = ImGui.GetMousePos(ctx)
  local hovering_area = (mx >= cx and mx <= cx + cw and my >= wy and my <= wy + wh)

  -- hit test 既有點 -- find hovered point
  local hov_pt = nil
  local hr2 = FXE_HIT_R * FXE_HIT_R
  for i, p in ipairs(fe.points) do
    local dx = mx - t2x(p.t)
    local dy = my - v2y(p.v)
    if dx*dx + dy*dy < hr2 then hov_pt = i; break end
  end

  -- 拖曳進行中 -- drag in progress
  if fx_env_drag.active then
    local pt = fe.points[fx_env_drag.pt_idx]
    if pt and ImGui.IsMouseDown(ctx, 0) then
      local nv = y2v(my)
      local nt = x2t(mx)
      -- 第一個點 t 鎖定 0；其他夾在相鄰點之間 -- clamp t between neighbors
      if fx_env_drag.pt_idx == 1 then
        nt = 0
      else
        local prev_t = fe.points[fx_env_drag.pt_idx - 1].t
        local next_t = fe.points[fx_env_drag.pt_idx + 1] and fe.points[fx_env_drag.pt_idx + 1].t or (vs + vd + 9999)
        nt = FUNC.clamp(nt, prev_t + 0.001, next_t - 0.001)
      end
      pt.t = nt
      pt.v = nv
      -- tooltip 拖曳中顯示值 -- show value while dragging
      if ImGui.BeginTooltip(ctx) then
        ImGui.Text(ctx, FUNC.fx_env_format_value(c, fe, nv))
        ImGui.EndTooltip(ctx)
      end
    else
      fx_env_drag.active = false
      fx_env_drag.pt_idx = nil
      FUNC.save_cues()
    end
    return
  end

  if not hovering_area then return end

  -- hover tooltip -- tooltip on hovered point
  if hov_pt then
    local p = fe.points[hov_pt]
    if ImGui.BeginTooltip(ctx) then
      ImGui.Text(ctx, FUNC.fx_env_format_value(c, fe, p.v))
      ImGui.EndTooltip(ctx)
    end
  end

  -- 點擊 -- clicks
  if ImGui.IsMouseClicked(ctx, 0) then
    if hov_pt then
      fx_env_drag.active = true
      fx_env_drag.pt_idx = hov_pt
    elseif ImGui.IsKeyDown(ctx, ImGui.Key_LeftShift()) or ImGui.IsMouseDoubleClicked(ctx, 0) then
      -- 空白處 shift-click 或雙擊新增點 -- add point on shift-click or double-click empty area
      local nt = x2t(mx)
      local nv = y2v(my)
      -- 找插入位置 -- find insert position
      local ins = #fe.points + 1
      for i = 1, #fe.points do
        if fe.points[i].t > nt then ins = i; break end
      end
      table.insert(fe.points, ins, {t = nt, v = nv, curve = 0})
      fx_env_drag.active = true
      fx_env_drag.pt_idx = ins
    end
  elseif ImGui.IsMouseClicked(ctx, 1) and hov_pt then
    -- 右鍵刪除點（首尾不刪）-- right-click delete (keep first & last)
    if hov_pt > 1 and hov_pt < #fe.points then
      table.remove(fe.points, hov_pt)
      FUNC.save_cues()
    end
  end
end
