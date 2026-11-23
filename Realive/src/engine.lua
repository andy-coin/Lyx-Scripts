-- ==========================================================================
-- engine.lua — Preview, Fade, Timer Engines
-- ==========================================================================

---------------------------------------------------------------------
-- 5. MULTI-ITEM PREVIEW ENGINE
---------------------------------------------------------------------
function FUNC.get_items(ti)
  local tr=FUNC.get_tr(ti);if not tr then return {} end
  local n=reaper.GetTrackNumMediaItems(tr);local items={}
  for i=0,n-1 do local it=reaper.GetTrackMediaItem(tr,i)
    local pos=reaper.GetMediaItemInfo_Value(it,"D_POSITION")
    local len=reaper.GetMediaItemInfo_Value(it,"D_LENGTH")
    local take=reaper.GetActiveTake(it);if take then
      local src=reaper.GetMediaItemTake_Source(take)
      -- 讀取take起始偏移，用於被剪裁/分割的item正確播放 -- read take start offset for trimmed/split items
      local take_offs=reaper.GetMediaItemTakeInfo_Value(take,"D_STARTOFFS")
      if src then items[#items+1]={src=src,pos=pos,len=len,take_offs=take_offs or 0} end
    end
  end;table.sort(items,function(a,b) return a.pos<b.pos end);return items
end

function FUNC.calc_dur(ti)
  local items=FUNC.get_items(ti);if #items==0 then return 0 end
  local s=items[1].pos;local e=0
  for _,it in ipairs(items) do e=math.max(e,it.pos+it.len) end;return e-s
end

local _pvuid=0
function FUNC.pv_create(src,ti,vol_db,off,rate,ppitch,pitch,max_dur,pan)
  local pv=reaper.CF_CreatePreview(src);if not pv then return nil end
  local vl=FUNC.db2lin(vol_db)
  reaper.CF_Preview_SetValue(pv,"D_VOLUME",vl)
  reaper.CF_Preview_SetValue(pv,"D_POSITION",off or 0)
  reaper.CF_Preview_SetValue(pv,"B_LOOP",0)
  -- pan用CF_Preview獨立控制，不影響REAPER track（保留給pan envelope）-- pan via preview, not track
  if pan and pan ~= 0 then reaper.CF_Preview_SetValue(pv,"D_PAN",FUNC.clamp(pan,-1,1)) end
  -- 播放速率+保持音高+音高偏移 -- playback rate + preserve pitch + pitch shift
  if rate and rate ~= 1.0 then reaper.CF_Preview_SetValue(pv,"D_PLAYRATE",rate) end
  if ppitch ~= nil then reaper.CF_Preview_SetValue(pv,"B_PPITCH",ppitch and 1 or 0) end
  if pitch and pitch ~= 0 then reaper.CF_Preview_SetValue(pv,"D_PITCH",pitch) end
  local tr=FUNC.get_tr(ti);if tr then reaper.CF_Preview_SetOutputTrack(pv,0,tr) end
  reaper.CF_Preview_Play(pv)
  _pvuid=_pvuid+1;local pid=_pvuid
  active_previews[pid]={pv=pv,ti=ti,vl=vl,cue_db=vol_db,t0=reaper.time_precise(),
    max_dur=max_dur,  -- max_dur：item邊界播放限制 -- item boundary playback limit
    src=src,init_off=off or 0,init_rate=rate or 1.0,init_ppitch=ppitch,init_pitch=pitch or 0,init_pan=pan or 0}  -- pause/resume用 -- for pause/resume rebuild
  return pid
end

-- Calculate GROUP total duration considering link chains
function FUNC.calc_group_dur(gc, _visited)
  if not gc or gc.type~="GROUP" or not gc.children or #gc.children==0 then return 0 end
  -- visited 守衛：cyclic GROUP nesting (A→B→A) 不再無限遞迴 -- prevent cyclic recursion
  _visited = _visited or {}
  if _visited[gc.id] then return 0 end
  _visited[gc.id] = true
  local max_end = 0
  local chain_t = 0
  for k, ch in ipairs(gc.children) do
    local c = cues[ch]; if not c or c == gc then goto skip end  -- 防止自引用 -- prevent self-reference
    local cdur = 0
    if c.type == "PLAY" then
      local raw = FUNC.calc_dur(c.track_idx)
      local ts = c.trim_start or 0
      local te = (c.trim_end and c.trim_end > 0) and c.trim_end or raw
      local cr = (c.rate and c.rate > 0) and c.rate or 1.0
      cdur = math.max(0, (te - ts) / cr)  -- 考慮播放速率 -- account for playback rate
    elseif c.type == "GROUP" then cdur = FUNC.calc_group_dur(c, _visited)
    elseif c.type == "FADE" then cdur = c.fade_time or 0 end
    local cue_total = c.pre_wait + cdur + c.post_wait
    if k == 1 then
      chain_t = cue_total
    elseif c.auto_go then
      chain_t = chain_t + c.pre_wait + cdur + c.post_wait
    else
      max_end = math.max(max_end, chain_t)
      chain_t = cue_total
    end
    ::skip::
  end
  max_end = math.max(max_end, chain_t)
  -- GROUP自身的trim限制總時長 -- apply GROUP's own trim to total duration
  local g_ts = gc.trim_start or 0
  local g_te = (gc.trim_end and gc.trim_end > 0) and gc.trim_end or max_end
  _visited[gc.id] = nil  -- 退出本層後解封，允許同一 GROUP 在不同分支重新計算 -- unmark on exit
  return math.max(0, math.min(max_end, g_te) - g_ts)
end

-- Get effective volume: cue volume + parent GROUP volume (if any)
function FUNC.eff_vol(c)
  local v = c.volume
  -- 巢狀 group volume 疊加：向上鏈式加總所有 GROUP 的 volume -- nested group volume stacking
  local gid = c.group_id
  while gid do
    local _,gc = FUNC.find_id(gid)
    if not gc or gc.type ~= "GROUP" then break end
    v = v + gc.volume
    gid = gc.group_id
  end
  return v
end

function FUNC.play_cue(c)
  if c._broken then return end  -- 損壞 cue：禁止播放 -- broken cue: refuse to play
  if c.preview_ids then for _,pid in ipairs(c.preview_ids) do
    local p=active_previews[pid];if p then reaper.CF_Preview_Stop(p.pv);active_previews[pid]=nil end
  end end
  c.preview_ids={}
  -- 清掉此 cue 還沒觸發的 item-spawn timer，避免 trim 重播時舊 timer 仍會 spawn 出第二份 pid
  -- wipe pending item-spawn timers for this cue; otherwise replay (e.g. trim seek) leaves stale
  -- timers that fire later and double-play chained items
  do local i=1; while i<=#active_timers do local t=active_timers[i]
    if t.cue_id == c.id and t.tt == "item" then table.remove(active_timers,i) else i=i+1 end end end
  -- 存軌道狀態+重置 (所有PLAY cue) -- save track state on play
  FUNC.env_save_track(c)
  if c.fx_envs and #c.fx_envs > 0 then FUNC.fx_env_check_missing(c) end  -- refresh _missing flags
  FUNC.fx_env_engage(c)  -- 存FX原始參數值 + refcount -- engage fx envelopes
  local items=FUNC.get_items(c.track_idx);if #items==0 then c.total_dur=0;c.eff_dur=0;return end
  local base=items[1].pos;local last_end=0
  for _,it in ipairs(items) do last_end=math.max(last_end,it.pos+it.len) end
  c.total_dur=last_end-base
  -- runtime GROUP trim override 優先於 cue 自身 trim -- GROUP trim override takes priority
  local ts = c._rt_trim_start or c.trim_start or 0
  local te = c._rt_trim_end or ((c.trim_end and c.trim_end > 0) and c.trim_end or c.total_dur)
  c._rt_trim_start = nil; c._rt_trim_end = nil  -- 用完即清 -- clear after use
  local cue_rate = c.rate or 1.0; if cue_rate <= 0 then cue_rate = 1.0 end
  c._raw_trim_dur = te - ts  -- 保存原始trim後時長，供rate變更時重算eff_dur -- raw trimmed duration for rate recalc
  c.eff_dur=(te-ts) / cue_rate  -- eff_dur考慮播放速率 -- duration adjusted by playback rate
  c.play_t0=FUNC.tnow()  -- 排程理想時間：連鎖/loop 不累積每幀延遲 -- scheduled (ideal) time so chains/loops don't accumulate frame delay
  c.play_offset=ts
  local cue_pan = c.pan or 0  -- pan用CF_Preview控制，不改REAPER track

  for _,it in ipairs(items) do
    local rs=it.pos-base;local re=rs+it.len
    if re>ts and rs<te then
      local delay=math.max(0,(rs-ts)/cue_rate)  -- delay也要除以rate -- delay adjusted by rate
      -- src_off加上take_offs：被剪裁/分割的item從正確的source位置播放 -- add take offset for trimmed/split items
      local src_off=math.max(0,ts-rs) + (it.take_offs or 0)
      -- play_len用item.len而非source長度，限制在item邊界內 -- limit playback within item bounds
      local play_len = (math.min(re, te) - math.max(rs, ts)) / cue_rate
      function do_play()
        local pid=FUNC.pv_create(it.src,c.track_idx,FUNC.eff_vol(c),src_off,cue_rate,c.preserve_pitch,c.pitch,play_len,cue_pan)
        if pid then
          c.preview_ids[#c.preview_ids+1]=pid
          -- 若 cue 處於 soft_kill 中：把新 pid 對齊到目前 fade 進度，並接續剩餘 fade
          -- if cue is in soft_kill, align this new pid to the current fade level + apply remaining fade
          if soft_kill[c.id] then
            local sk = soft_kill[c.id]
            local el = reaper.time_precise() - sk.t0
            local pg = FUNC.clamp(el / sk.dur, 0, 1)
            local from_db = FUNC.eff_vol(c)
            local cur_db = from_db + (prefs.inf_db - from_db) * pg
            FUNC.pv_set_db(pid, cur_db)
            local rem = math.max(0, sk.dur - el)
            if rem > 0 then FUNC.start_fade(pid, prefs.inf_db, rem, "linear", nil) end
          end
        end
      end
      if delay<0.001 then do_play()
      else active_timers[#active_timers+1]={t0=FUNC.tnow(),dur=delay,ci=-1,tt="item",cue_id=c.id,cb=do_play} end
    end
  end
end

function FUNC.pv_stop(pid) local p=active_previews[pid];if not p then return end
  reaper.CF_Preview_Stop(p.pv);active_previews[pid]=nil end
function FUNC.pv_set_db(pid,db) local p=active_previews[pid];if not p then return end
  p.vl=FUNC.db2lin(db);p.cue_db=db;reaper.CF_Preview_SetValue(p.pv,"D_VOLUME",p.vl) end
function FUNC.pv_get_db(pid) local p=active_previews[pid];if not p then return prefs.inf_db end;return p.cue_db end
-- pan用CF_Preview獨立控制，不影響track D_PAN（保留給envelope）-- pan via preview, keeps track D_PAN for envelope
function FUNC.pv_set_pan(pid,pan) local p=active_previews[pid];if not p then return end
  reaper.CF_Preview_SetValue(p.pv,"D_PAN",FUNC.clamp(pan,-1,1)) end
function FUNC.pv_get_pan(pid) local p=active_previews[pid];if not p then return 0 end
  local _,v=reaper.CF_Preview_GetValue(p.pv,"D_PAN");return v or 0 end
function FUNC.pv_get_pos(pid) local p=active_previews[pid];if not p then return 0 end
  local _,v=reaper.CF_Preview_GetValue(p.pv,"D_POSITION");return v end
function FUNC.pv_playing(pid) local p=active_previews[pid];if not p then return false end
  local _,pos=reaper.CF_Preview_GetValue(p.pv,"D_POSITION")
  local _,len=reaper.CF_Preview_GetValue(p.pv,"D_LENGTH");return pos<len end
-- 即時更新播放中cue的rate/pitch/preserve_pitch -- live update rate/pitch on active previews
function FUNC.pv_update_rate_pitch(c)
  if not c.preview_ids then return end
  local rate = (c.rate and c.rate > 0) and c.rate or 1.0
  local ppitch = c.preserve_pitch and 1 or 0
  local pitch = c.pitch or 0
  for _, pid in ipairs(c.preview_ids) do
    local p = active_previews[pid]; if not p then goto skip end
    reaper.CF_Preview_SetValue(p.pv, "D_PLAYRATE", rate)
    reaper.CF_Preview_SetValue(p.pv, "B_PPITCH", ppitch)
    reaper.CF_Preview_SetValue(p.pv, "D_PITCH", pitch)
    ::skip::
  end
  -- rate變更時重算eff_dur+調整play_t0，保持進度條正確 -- recalc eff_dur on rate change to keep progress bar accurate
  if c._raw_trim_dur and c._raw_trim_dur > 0 and c.eff_dur and c.eff_dur > 0 and c.play_t0 and c.play_t0 > 0 then
    local now = reaper.time_precise()
    local elapsed = now - c.play_t0
    local frac = FUNC.clamp(elapsed / c.eff_dur, 0, 1)
    local audio_pos = frac * c._raw_trim_dur
    local remaining_audio = c._raw_trim_dur - audio_pos
    local remaining_wall = remaining_audio / rate
    c.eff_dur = elapsed + remaining_wall
  end
end
function FUNC.pv_stop_all()
  for pid in pairs(active_previews) do FUNC.pv_stop(pid) end;active_previews={}
  FUNC.env_restore_all()  -- 還原所有軌道 -- restore all tracks on stop_all/exit
  -- 還原所有GROUP route trims -- restore all GROUP route trims on stop_all
  for _, gc in ipairs(cues) do if gc._rt_hw_saved then FUNC.rt_restore_trims(gc) end end
end

-- GROUP route trim: 套用trim到children的hw output volume -- apply GROUP trims to children hw send volumes
function FUNC.rt_apply_trims(gc)
  if not gc or gc.type ~= "GROUP" then return end
  local trims = gc.route_trims
  if not trims or not next(trims) then return end
  -- 收集children的track + hw send對照 -- collect children tracks + hw send mapping
  local saved = {}  -- {[track_idx] = {[send_idx] = orig_vol_lin, ...}}
  for _, ci in ipairs(gc.children or {}) do
    if ci >= 1 and ci <= #cues then
      local cc = cues[ci]
      if cc.type == "PLAY" then
        local ti = cc.track_idx
        local tr = FUNC.get_tr(ti)
        if tr and not saved[ti] then
          saved[ti] = {}
          local nhs = reaper.GetTrackNumSends(tr, 1)
          for si = 0, nhs - 1 do
            local dst = reaper.GetTrackSendInfo_Value(tr, 1, si, "I_DSTCHAN")
            local ch = math.floor(dst) % 1024
            local trim_db = trims[ch]
            if trim_db and math.abs(trim_db) > 0.01 then
              local _, vol = reaper.GetTrackSendUIVolPan(tr, si)
              saved[ti][si] = vol  -- 存原始linear volume -- save original linear volume
              -- 疊加trim: 原始dB + trim_db -- add trim offset in dB
              local orig_db = vol > 0 and (20 * math.log(vol, 10)) or prefs.vol_min
              local new_db = FUNC.clamp(orig_db + trim_db, prefs.vol_min, prefs.vol_max)
              local new_lin = new_db <= prefs.vol_min and 0 or (10 ^ (new_db / 20))
              reaper.SetTrackSendUIVol(tr, si, new_lin, 0)
            end
          end
          if not next(saved[ti]) then saved[ti] = nil end
        end
      end
    end
  end
  gc._rt_hw_saved = next(saved) and saved or nil
end

-- GROUP route trim: 還原children的hw output volume -- restore children hw send volumes
function FUNC.rt_restore_trims(gc)
  if not gc or not gc._rt_hw_saved then return end
  for ti, sends in pairs(gc._rt_hw_saved) do
    local tr = FUNC.get_tr(ti)
    if tr then
      for si, orig_vol in pairs(sends) do
        reaper.SetTrackSendUIVol(tr, si, orig_vol, 0)
      end
    end
  end
  gc._rt_hw_saved = nil
end

function FUNC.kill_cue(c)
  if not c.preview_ids then c.preview_ids={} end
  for _,pid in ipairs(c.preview_ids) do FUNC.pv_stop(pid) end
  c.preview_ids={}
  -- 移除所有相關timer：cue_id(item/group_child) 或 owner(pre/post-wait)，一律用 cue id 不用列號
  -- remove this cue's timers: cue_id (item/group_child) or owner (pre/post-wait); always by cue id, never by row
  local i=1; while i<=#active_timers do
    local t = active_timers[i]
    if t.cue_id==c.id or t.owner==c.id then table.remove(active_timers,i) else i=i+1 end
  end
  -- 停掉 FADE cue 時，它發動的 fade 也一起停 -- killing a FADE cue also stops the fades it started
  if c.type=="FADE" then i=1; while i<=#active_fades do
    if active_fades[i].owner==c.id then table.remove(active_fades,i) else i=i+1 end end end
  if FUNC.midi_stop_cue then FUNC.midi_stop_cue(c)  -- Phase 2A: 停止所有 pending + unarm
  else FUNC.midi_note_off(c) end  -- Phase 1 legacy fallback
  FUNC.fx_env_disengage(c)  -- 還原FX參數 (先做，因為env_restore_track可能銷毀_trk_state) -- disengage fx envs first
  FUNC.env_restore_track(c)  -- 還原軌道狀態 -- restore track state on kill
  c.state=STATE.IDLE;c.play_t0=0;c.loop_go_fired=nil;c.loop_done=nil end  -- 清除 loop 旗標，讓下次播放能再次觸發

-- 建立item指紋：用於偵測REAPER軌道item變更(切割/移動/刪除) -- build item fingerprint for detecting track item changes
function FUNC.item_fingerprint(ti)
  local items = FUNC.get_items(ti)
  if #items == 0 then return "", 0 end
  local parts = {}
  local base = items[1].pos; local last_end = 0
  for _, it in ipairs(items) do
    parts[#parts+1] = string.format("%.6f:%.6f:%.6f", it.pos, it.len, it.take_offs or 0)
    last_end = math.max(last_end, it.pos + it.len)
  end
  return table.concat(parts, "|"), last_end - base
end

-- 重新計算idle cue的total_dur和eff_dur（item變更時呼叫） -- recalc duration for idle cues when items change
function FUNC.refresh_cue_dur(c)
  if c.type ~= "PLAY" then return end
  if c.state == STATE.RUNNING or c.state == STATE.PREWAIT then return end  -- 播放中不更新 -- don't update while playing
  local items = FUNC.get_items(c.track_idx)
  if #items == 0 then c.total_dur = 0; c.eff_dur = 0; return end
  local base = items[1].pos; local last_end = 0
  for _, it in ipairs(items) do last_end = math.max(last_end, it.pos + it.len) end
  c.total_dur = last_end - base
  local ts = c.trim_start or 0
  local te = (c.trim_end and c.trim_end > 0) and c.trim_end or c.total_dur
  -- trim超出新total_dur時自動修正 -- clamp trim to new total_dur
  if te > c.total_dur then te = c.total_dur; c.trim_end = te end
  if ts >= te then ts = 0; c.trim_start = 0 end
  local cue_rate = (c.rate and c.rate > 0) and c.rate or 1.0
  c.eff_dur = math.max(0, (te - ts) / cue_rate)
end

-- 用於 master/route meter 過濾：state 中或 wf_sel 選取範圍 preview 中皆視為 active
-- meter visibility helper: includes cues currently in run/prewait/postwait OR being driven by wf_sel preview
function FUNC.cue_meter_active(q)
  if not q then return false end
  if q.state == STATE.RUNNING or q.state == STATE.PREWAIT or q.state == STATE.POSTWAIT then return true end
  if wf_sel and wf_sel.preview_ids and #wf_sel.preview_ids > 0 then
    if wf_sel.cid == q.id then return true end
    if wf_sel._engaged then
      for _, ec in ipairs(wf_sel._engaged) do if ec == q then return true end end
    end
  end
  return false
end

function FUNC.cue_is_active(c)
  if c.type~="PLAY" then return false end
  if not c.play_t0 or c.play_t0<=0 then return false end
  if c.state~=STATE.DONE and c.state~=STATE.RUNNING then return false end
  local dur=c.eff_dur>0 and c.eff_dur or c.total_dur
  if dur<=0 then return false end
  return (reaper.time_precise()-c.play_t0)<dur+0.2
end

function FUNC.cue_has_pv(c)
  if not c.preview_ids then return false end
  for _,pid in ipairs(c.preview_ids) do if active_previews[pid] then return true end end;return false end

function FUNC.apply_master()
  if prefs.master_vol==last_master then return end
  -- master改hw send音量，不改preview音量 → track peak不受master影響
  -- master adjusts hw send volumes, not preview → track peak unaffected by master
  FUNC.apply_master_sends()
  last_master=prefs.master_vol
end

-- Pause/Resume (cue-based) — 保存每個preview完整資訊以正確重建 -- save full preview info for accurate rebuild
-- 暫停時一併保存：剩餘播放長度、進行中的 fade、尚未開始的後段 item，Resume 時全部接回
-- pause also keeps: remaining play length, fades in progress, and later items not started yet; resume puts them all back
function FUNC.pause_cue(c)
  if not c.preview_ids then return false end
  local now=reaper.time_precise()
  local st={}
  for _,pid in ipairs(c.preview_ids) do local p=active_previews[pid]; if p then
    local e={
      src=p.src, pos=FUNC.pv_get_pos(pid), db=FUNC.pv_get_db(pid),
      rate=FUNC.pv_get_rate(pid), pitch=FUNC.pv_get_pitch(pid),
      ppitch=p.init_ppitch, pan=FUNC.pv_get_pan(pid),
      max_dur=p.max_dur and math.max(0,p.max_dur-(now-p.t0)),  -- 只剩還沒播的長度 -- only what is left to play
    }
    for _,f in ipairs(active_fades) do if f.pid==pid then
      e.fade={to=f.to,rem=math.max(0,f.dur-(now-f.t0)),cv=f.cv,amt=f.amt,cb=f.cb,
        opts={owner=f.owner,rate_to=f.rate_to,pitch_to=f.pitch_to,pan_to=f.pan_to}}
    end end
    st[#st+1]=e
  end end
  FUNC.cancel_fades_cue(c)  -- 先取下 fade 再停 preview，避免被當成「播完」而提早完成 -- detach fades before stopping so they aren't treated as finished
  for _,pid in ipairs(c.preview_ids) do FUNC.pv_stop(pid) end
  c.preview_ids={}
  local pend={}
  local i=1; while i<=#active_timers do local t=active_timers[i]
    if t.cue_id and t.cue_id==c.id then
      if t.tt=="item" then pend[#pend+1]={rem=math.max(0,t.dur-(now-t.t0)),cb=t.cb} end
      table.remove(active_timers,i)
    else i=i+1 end
  end
  local elapsed=now-(c.play_t0 or 0)
  if #st>0 or #pend>0 then paused_cues[c.id]={data=st,timers=pend,elapsed=elapsed};return true end;return false
end
function FUNC.resume_cue(c)
  local ps=paused_cues[c.id];if not ps then return false end
  local now=reaper.time_precise()
  c.preview_ids={};c.play_t0=now-ps.elapsed
  for _,e in ipairs(ps.data) do
    if e.src then
      local pid=FUNC.pv_create(e.src,c.track_idx,e.db,e.pos,e.rate,e.ppitch,e.pitch,e.max_dur,e.pan)
      if pid then c.preview_ids[#c.preview_ids+1]=pid
        if e.fade then FUNC.start_fade(pid,e.fade.to,e.fade.rem,e.fade.cv,e.fade.cb,e.fade.amt,e.fade.opts) end
      end
    end
  end
  for _,t in ipairs(ps.timers or {}) do
    active_timers[#active_timers+1]={t0=now,dur=t.rem,ci=-1,tt="item",cue_id=c.id,cb=t.cb}
  end
  paused_cues[c.id]=nil;return true
end
function FUNC.is_cue_paused(c) return paused_cues[c.id]~=nil end

---------------------------------------------------------------------
-- 6. FADE ENGINE
---------------------------------------------------------------------
-- 讀取preview當前rate/pitch -- get current rate/pitch from preview
function FUNC.pv_get_rate(pid) local p=active_previews[pid];if not p then return 1.0 end
  local _,v=reaper.CF_Preview_GetValue(p.pv,"D_PLAYRATE");return v or 1.0 end
function FUNC.pv_get_pitch(pid) local p=active_previews[pid];if not p then return 0 end
  local _,v=reaper.CF_Preview_GetValue(p.pv,"D_PITCH");return v or 0 end
function FUNC.pv_set_rate(pid,rate) local p=active_previews[pid];if not p then return end
  reaper.CF_Preview_SetValue(p.pv,"D_PLAYRATE",rate) end
function FUNC.pv_set_pitch(pid,pitch) local p=active_previews[pid];if not p then return end
  reaper.CF_Preview_SetValue(p.pv,"D_PITCH",pitch) end
function FUNC.pv_set_ppitch(pid,on) local p=active_previews[pid];if not p then return end
  reaper.CF_Preview_SetValue(p.pv,"B_PPITCH",on and 1 or 0) end

function FUNC.start_fade(pid,to,dur,cv,cb,amt,opts)
  opts = opts or {}
  if dur<=0 then
    FUNC.pv_set_db(pid,to)
    if opts.rate_to then FUNC.pv_set_rate(pid,opts.rate_to) end
    if opts.pitch_to then FUNC.pv_set_pitch(pid,opts.pitch_to); FUNC.pv_set_ppitch(pid,true) end
    if opts.pan_to then FUNC.pv_set_pan(pid,opts.pan_to) end
    if cb then cb() end;return
  end
  local entry = {pid=pid,t0=reaper.time_precise(),dur=dur,
    from=FUNC.pv_get_db(pid),to=to,cv=cv or "linear",amt=amt,cb=cb,
    owner=opts.owner}  -- owner = 發動這個 fade 的 FADE cue id -- id of the FADE cue that started it
  -- rate/pitch漸變：記錄起始值和目標值 -- rate/pitch fade: store from/to values
  if opts.rate_to then
    entry.rate_from = FUNC.pv_get_rate(pid)
    entry.rate_to = opts.rate_to
  end
  if opts.pitch_to then
    entry.pitch_from = FUNC.pv_get_pitch(pid)
    entry.pitch_to = opts.pitch_to
    FUNC.pv_set_ppitch(pid, true)  -- pitch fade強制preserve pitch -- force preserve pitch for pitch fade
  end
  if opts.pan_to then
    entry.pan_from = FUNC.pv_get_pan(pid)
    entry.pan_to = opts.pan_to
  end
  active_fades[#active_fades+1] = entry
end
function FUNC.start_fade_cue(c,to,dur,cv,cb,amt,opts)
  if not c.preview_ids or #c.preview_ids==0 then if cb then cb() end;return end
  -- fired 旗標：dur<=0 時 start_fade 會同步呼叫 cb，避免迴圈結束後再叫第二次 -- fired flag: dur<=0 fires cb synchronously, don't fire again after loop
  local rem=#c.preview_ids;local fired=false
  local function done() rem=rem-1;if rem<=0 and not fired then fired=true;if cb then cb() end end end
  for _,pid in ipairs(c.preview_ids) do if active_previews[pid] then
    FUNC.start_fade(pid,to,dur,cv,done,amt,opts)
  else rem=rem-1 end end
  if rem<=0 and not fired then fired=true;if cb then cb() end end end
function FUNC.process_fades()
  local now=reaper.time_precise();local i=1
  while i<=#active_fades do local f=active_fades[i]
    if not active_previews[f.pid] then
      -- 聲音已經結束（播完/被停）：fade 視為完成，讓 FADE cue 能正常收尾與連鎖
      -- the sound is gone (ended/stopped): count the fade as finished so its FADE cue can complete and chain
      table.remove(active_fades,i); if f.cb then f.cb() end
    else local pg=FUNC.clamp((now-f.t0)/f.dur,0,1)
      local cv_val = FUNC.crv(pg,f.cv,f.amt)
      FUNC.pv_set_db(f.pid,f.from+(f.to-f.from)*cv_val)
      -- rate漸變：線性插值(用相同曲線) -- rate fade interpolation
      if f.rate_to then
        FUNC.pv_set_rate(f.pid, f.rate_from + (f.rate_to - f.rate_from) * cv_val)
      end
      -- pitch漸變：線性插值(用相同曲線) -- pitch fade interpolation
      if f.pitch_to then
        FUNC.pv_set_pitch(f.pid, f.pitch_from + (f.pitch_to - f.pitch_from) * cv_val)
      end
      -- pan漸變：曲線插值 -- pan fade interpolation
      if f.pan_to then
        FUNC.pv_set_pan(f.pid, f.pan_from + (f.pan_to - f.pan_from) * cv_val)
      end
      if pg>=1 then
        if f.cb then f.cb() end
        -- callback可能觸發cancel_fades_cue移除此entry，確認還在才刪 -- callback may have removed this entry via cancel_fades_cue
        if active_fades[i] == f then table.remove(active_fades,i) end
      else i=i+1 end
    end
  end
end
function FUNC.cancel_fades_cue(c)
  if not c.preview_ids then return end
  local ids={};for _,pid in ipairs(c.preview_ids) do ids[pid]=true end
  local i=1;while i<=#active_fades do
    if ids[active_fades[i].pid] then table.remove(active_fades,i) else i=i+1 end end
end
function FUNC.get_fade_prog_cue(c)
  if not c.preview_ids then return nil end;local now=reaper.time_precise()
  for _,f in ipairs(active_fades) do for _,pid in ipairs(c.preview_ids) do
    if f.pid==pid then return FUNC.clamp((now-f.t0)/f.dur,0,1),f.dur end end end;return nil end

---------------------------------------------------------------------
-- 7. TIMER ENGINE
---------------------------------------------------------------------
-- 排程時鐘：計時器/播完偵測只能在「下一幀」才發現時間到了（最多晚一幀≈33ms）。
-- 觸發後續動作時，把「本來應該發生的時間」當成現在，後面接的等待/播放就從理想時間起算，
-- 所以 20 個 cue 串起來不會累積 20 幀的延遲。晚太多（卡頓 > MAX_LATE）就放棄補償，用真實時間。
-- Scheduling clock: a timer / end-of-cue is only noticed on the next frame (up to ~33 ms late).
-- While running what follows, we pretend "now" is the time it SHOULD have happened, so chained waits/plays
-- are measured from the ideal time and a 20-cue chain does not pile up 20 frames of delay.
-- If we are very late (a hiccup > MAX_LATE) we give up compensating and use the real time.
local _sched_t = nil
local MAX_LATE = 0.1
function FUNC.tnow() return _sched_t or reaper.time_precise() end
function FUNC.at_time(ideal, fn, ...)
  local late = reaper.time_precise() - ideal
  local prev = _sched_t
  if late >= 0 and late <= MAX_LATE then _sched_t = ideal end
  local ok, err = xpcall(fn, debug.traceback, ...)
  _sched_t = prev
  if not ok then error(err, 0) end
end

-- ci 只用來在呼叫當下查出 cue id（owner）；之後列表怎麼增刪移動，計時器都跟著那個 cue 走
-- ci is only used to look up the cue id (owner) right now; after that the timer follows that cue however the list changes
function FUNC.start_timer(dur,ci,tt,cb)
  if dur<=0 then cb();return end
  local owner = cues[ci] and cues[ci].id or nil
  -- 同一個 cue 同一種等待只留一個：等待中再 GO 一次，舊的倒數作廢（否則兩個都到時會連鎖兩次）
  -- one timer per cue per kind: firing a cue again while it waits replaces the old countdown (otherwise both fire and chain twice)
  if owner then local i=1; while i<=#active_timers do local t=active_timers[i]
    if t.owner==owner and t.tt==tt then table.remove(active_timers,i) else i=i+1 end end end
  active_timers[#active_timers+1]={t0=FUNC.tnow(),dur=dur,ci=ci,owner=owner,tt=tt,cb=cb} end
function FUNC.process_timers()
  local now=reaper.time_precise();local i=1
  while i<=#active_timers do local t=active_timers[i]
    if (now-t.t0)>=t.dur then table.remove(active_timers,i);FUNC.at_time(t.t0+t.dur,t.cb) else i=i+1 end end
end
local function timer_of(ci,tt)
  local id = cues[ci] and cues[ci].id; if not id then return nil end
  for _,t in ipairs(active_timers) do if t.owner==id and t.tt==tt then return t end end
end
function FUNC.timer_rem(ci,tt) local t=timer_of(ci,tt)
  if t then return math.max(0,t.dur-(reaper.time_precise()-t.t0)) end;return 0 end
-- timer進度(0~1) -- timer progress fraction
function FUNC.timer_prog(ci,tt) local t=timer_of(ci,tt)
  if t then return FUNC.clamp((reaper.time_precise()-t.t0)/t.dur,0,1) end;return nil end
-- FADE cue 是否還有東西在跑（fade 本體、無聲倒數、或暫停中保留的 fade）
-- does a FADE cue still have anything running (a fade, its silent countdown, or a fade kept by a paused cue)
function FUNC.fade_cue_alive(c)
  for _,f in ipairs(active_fades) do if f.owner==c.id then return true end end
  for _,t in ipairs(active_timers) do if t.owner==c.id then return true end end
  for _,ps in pairs(paused_cues) do for _,e in ipairs(ps.data) do
    if e.fade and e.fade.opts and e.fade.opts.owner==c.id then return true end end end
  return false
end

---------------------------------------------------------------------
-- 8. FAULT GUARD -- 錯誤保護
---------------------------------------------------------------------
-- 執行一段每幀工作；裡面出錯時記錄下來並回傳 false，不讓整個腳本停掉（計時器、淡出、Panic 都還能用）
-- run one piece of per-frame work; on error, record it and return false instead of letting the whole script die
-- (timers, fades and Panic keep working)
fault = {n = 0, msg = nil, where = nil, t = 0, t_log = nil}  -- 最近一次錯誤，給畫面橫幅用 -- last error, shown as a banner
function FUNC.safe_frame(fn, where)
  local ok, err = xpcall(fn, debug.traceback)
  if ok then return true end
  local now = reaper.time_precise()
  fault.n = fault.n + 1; fault.msg = tostring(err); fault.where = where or "frame"; fault.t = now
  -- 同一個錯誤每幀都會發生：console 最多每 5 秒寫一次 -- the same error may repeat every frame: log at most once per 5 s
  if not fault.t_log or now - fault.t_log > 5 then
    fault.t_log = now
    reaper.ShowConsoleMsg("\n[ReaLive] error in " .. fault.where .. " (#" .. fault.n .. "):\n" .. fault.msg .. "\n")
  end
  return false
end
