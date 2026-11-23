-- ==========================================================================
-- state.lua — State Variables + Utility Functions
-- ==========================================================================

---------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------
cues,selected,last_click={},{},0
next_go=0
next_go_hidden=false  -- 最後一個cue播放時隱藏next_go，防止連按空白 -- hide next_go cursor while last cue is playing
active_fades,active_timers,active_previews={},{},{}
paused_cues={}
cancelled_fades={}
soft_kill={}
track_warns={}
collapsed_groups={}
_realive_tracks={}  -- dup_track建立的track GUID集合，undo時清理孤兒用
id_map={}        -- id → index 快查表
dur_cache={}     -- cue_id → {dur=, t=} duration 快取
_warn_frame=0    -- track warning 節流計數器
_last_proj=nil   -- 上次的 project pointer（用於偵測切換）
_proj_snapshot=""  -- 進入project時的cue序列化快照，切換時比對是否需要備份
env_edit_mode="vol"  -- 目前編輯中的envelope類型: "vol" / "pan" / "fx"
fx_env_edit_idx=nil  -- 當 env_edit_mode=="fx" 時 active 的 fx_envs index
fx_env_sel={}        -- 多選的 fx_envs（list 欄位用），key=fei -- multi-select set for fx env list rows
fx_env_list_mq={}    -- list 區 marquee 框選狀態 -- marquee state for env list panel
_scroll_to_next_go=false  -- 啟動／載入後一次性 scroll cue table 到 next_go
fx_env_drag={}       -- fx env 點拖曳狀態 -- drag state for fx env points
fx_env_pending=nil  -- FX env新增等待狀態：{cue_id,init_tr,init_fx,init_param} -- pending state for FX param capture
fx_env_missing_warn=nil  -- 遺失FX警告popup狀態：{cue_id,env_idx,fx_name,param_name} -- missing FX warning popup
show_name=""   -- 目前 show 名稱（空=unsaved）
project_notes=""  -- 專案備註（per realive project）-- project-level notes
dirty=false    -- 有未儲存修改
dbl_click_t={};DBL_T=0.35
ie={active=false,row=0,col="",buf="",t=0}
popup={settings=false,save=false,load=false,shortcuts=false,
  trim=false,trim_ci=0, fade_edit=false,fade_edit_ci=0,
  reset_mode=false, reset_drag=nil, reset_cooldown=0,  -- 欄位重置模式 -- column reset mode; reset_drag={sx,sy,ex,ey} screen coords; cooldown frames after exit
  edit=(prefs.edit_open == 1),edit_ci=0,edit_backup=nil,edit_list={},  -- edit用pref記憶開關狀態 -- edit panel state from prefs
  save_title_buf="",load_sel="",theme_name_buf="",fade_chart_tab="all",
  warn=false,warn_ci=0,
  warn_missing=false,warn_missing_ci=0,  -- track遺失popup -- missing track popup
  save_overwrite=false,
  sel_paste=false, sel_paste_tab="basic", sel_paste_fields={}, sel_paste_msg=nil}
last_master=prefs.master_vol
tbl={x1=0,x2=0,y1=0,y2=0,row_screen={},
  nav_col=-1,nav_row=-1,nav_dir=0,
  focused=true}  -- 是否擁有 keyboard focus（決定 Delete 是否刪 cue）-- whether cue_table owns keyboard focus (gates Delete on cues)
drag={src_ci=nil,cue_id=nil,backup=nil,
  multi=false,block_n=1,click_off=0,pending_desel_ci=nil,
  vol_ci=nil}  -- volume拖曳追蹤：記住正在拖的cue index
marquee_state={}  -- 共用跑馬燈狀態 key→{t_hover, t_scroll} -- shared marquee state
edit_ratio=(prefs.edit_ratio or 35) / 100  -- edit panel佔比，從prefs還原 -- edit panel size ratio from prefs
edit_drag=false  -- edit panel邊界拖曳中 -- dragging edit panel border
sec_drag=false   -- section divider拖曳中 -- dragging section divider
_sec_was_drag=false  -- section header拖曳中（防止release觸發toggle）-- prevent toggle during drag
smooth_scroll={target=nil, _anim_y=nil, _last_t=nil}  -- 平滑滾動狀態 -- smooth scroll state for main cue table
-- 巢狀深度警告：toolbar Re# 與 Undo 之間顯示一行警告，icon 閃 3 下、停 5 秒、淡出 3 秒
-- nested-group depth warning shown in toolbar gap; icon blinks 3x, hold 5s, fade 3s
_depth_warn_t0 = nil
_toolbar_warn_msg = "Max nesting depth (5) reached"

---------------------------------------------------------------------
-- UTIL
---------------------------------------------------------------------
-- 觸發深度警告（重置計時器）-- trigger depth warning (reset timer)
function FUNC.warn_max_depth() _depth_warn_t0 = reaper.time_precise(); _toolbar_warn_msg = "Max nesting depth (5) reached" end
-- 通用 toolbar 警告：自訂訊息 -- generic toolbar warn with custom message
function FUNC.warn_toolbar(msg) _depth_warn_t0 = reaper.time_precise(); _toolbar_warn_msg = msg or "" end

function FUNC.db2lin(d) if d<=prefs.inf_db then return 0 end;return 10^(d/20) end
function FUNC.lin2db(l) if l<=0 then return prefs.inf_db end;return 20*math.log(l,10) end
function FUNC.crv(t, c, amt)
  if t <= 0 then return 0 end; if t >= 1 then return 1 end
  if c == "scurve" then
    -- S曲線：t^p / (t^p + (1-t)^p)，p越大越陡 -- generalized S-curve
    local p = amt or 2.5; if p <= 1 then return t end
    local tp = t^p; return tp / (tp + (1-t)^p)
  elseif c == "expo" then
    -- Exponential ease：y = (1-exp(-k*t)) / (1-exp(-k))
    -- k>0 像電容充電（前快後慢），k<0 鏡射（前慢後快），k≈0 退回 linear
    local k = amt or 0
    if math.abs(k) < 1e-3 then return t end
    return (1 - math.exp(-k * t)) / (1 - math.exp(-k))
  elseif c == "log" then return math.log(1+t*9)/math.log(10)
  elseif c == "exp" then return (math.exp(t*2.302585)-1)/9
  end; return t
end
function FUNC.clamp(v,a,b) return math.max(a,math.min(b,v)) end
function FUNC.get_tr(i) if i<0 then return nil end;return reaper.GetTrack(0,i) end
function FUNC.tr_name(i) local t=FUNC.get_tr(i);if not t then return "?" end;local _,n=reaper.GetTrackName(t);return n end
-- GUID→track index解析（track移動/刪除時自動更新）-- resolve GUID to 0-based track index
function FUNC.guid_to_idx(guid)
  if not guid or guid == "" then return -1 end
  local tr = reaper.BR_GetMediaTrackByGUID(0, guid)
  if not tr then return -1 end
  return math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) - 1
end
function FUNC.tr_guid(i) local t=FUNC.get_tr(i);if not t then return "" end;return reaper.GetTrackGUID(t) end
-- 複製REAPER軌道（含所有item），回傳新track的index和GUID -- duplicate track for independent envelope operation
function FUNC.dup_track(ti)
  local tr = FUNC.get_tr(ti); if not tr then return -1, "" end
  -- 保存當前選取狀態 -- save current track selection
  local sel_count = reaper.CountSelectedTracks(0)
  local saved_sel = {}
  for i = 0, sel_count - 1 do saved_sel[#saved_sel+1] = reaper.GetSelectedTrack(0, i) end
  -- 選取要複製的track
  reaper.SetOnlyTrackSelected(tr)
  -- 執行Duplicate Tracks動作(40062) -- run REAPER's native duplicate action
  reaper.Main_OnCommand(40062, 0)
  -- 新track在原track後面 -- new track is right after original
  local new_tr = reaper.GetSelectedTrack(0, 0)
  if not new_tr then
    -- 還原選取 -- restore selection on failure
    for _, st in ipairs(saved_sel) do reaper.SetTrackSelected(st, true) end
    return -1, ""
  end
  local new_idx = math.floor(reaper.GetMediaTrackInfo_Value(new_tr, "IP_TRACKNUMBER")) - 1
  local new_guid = reaper.GetTrackGUID(new_tr)
  _realive_tracks[new_guid] = true  -- 註冊Realive建立的track，undo時可清理
  -- 原track名加" (copy)"後綴 -- append " (copy)" suffix
  local _, orig_name = reaper.GetTrackName(tr)
  reaper.GetSetMediaTrackInfo_String(new_tr, "P_NAME", orig_name .. " (copy)", true)
  -- 還原選取狀態 -- restore original track selection
  reaper.SetOnlyTrackSelected(new_tr)  -- 先清除
  for _, st in ipairs(saved_sel) do reaper.SetTrackSelected(st, true) end
  reaper.SetTrackSelected(new_tr, false)  -- 新track不選
  return new_idx, new_guid
end
-- 檢查一組track guid，若不再被任何cue引用且是Realive複製的track就刪除 -- check guids: delete if orphaned AND Realive-created
function FUNC.check_delete_tracks(guids)
  if not guids or not next(guids) then return end
  -- 收集所有cue目前引用的track guid -- collect all currently referenced guids
  local used = {}
  for _, c in ipairs(cues) do
    if c.track_guid and c.track_guid ~= "" then used[c.track_guid] = true end
  end
  for guid in pairs(guids) do
    if _realive_tracks[guid] and not used[guid] then
      for i = reaper.CountTracks(0) - 1, 0, -1 do
        local tr = reaper.GetTrack(0, i)
        if tr and reaper.GetTrackGUID(tr) == guid then
          reaper.DeleteTrack(tr); break
        end
      end
      _realive_tracks[guid] = nil
    end
  end
end
function FUNC.tr_count() return reaper.CountTracks(0) end
function FUNC.sel_tr() local t=reaper.GetSelectedTrack(0,0);if not t then return -1 end
  return math.floor(reaper.GetMediaTrackInfo_Value(t,"IP_TRACKNUMBER"))-1 end
function FUNC.sel_trs()
  local r={};local n=reaper.CountSelectedTracks(0)
  for i=0,n-1 do local t=reaper.GetSelectedTrack(0,i)
    if t then r[#r+1]=math.floor(reaper.GetMediaTrackInfo_Value(t,"IP_TRACKNUMBER"))-1 end
  end;return r
end

function FUNC.fmt_t(s) if s<=0 then return "0:00.0" end;local m=math.floor(s/60);local r=s-m*60
  return string.format("%01d:%04.1f",m,r) end
function FUNC.parse_t(s) s=s:match("^%s*(.-)%s*$");if s=="" then return 0 end
  local mm,ss=s:match("^(%d+):([%d%.]+)$");if mm then return tonumber(mm)*60+(tonumber(ss) or 0) end
  local n=tonumber(s);return n and math.max(0,n) or nil end
-- Parse BPM input: "4in120" → beats=4, bpm=120 -- 解析BPM輸入格式
function FUNC.parse_bpm(s)
  s=s:match("^%s*(.-)%s*$")
  local b,p=s:match("^([%d%.]+)in([%d%.]+)$")
  if b and p then return tonumber(b),tonumber(p) end
  local n=tonumber(s)
  if n then return math.max(0,n),nil end
  return nil,nil
end

function FUNC.fmt_v(d) if d<=prefs.inf_db then return "-inf dB" end
  if d>0 then return string.format("+%.1f dB",d) end;return string.format("%.1f dB",d) end
function FUNC.parse_v(s) s=s:match("^%s*(.-)%s*$")
  s=s:gsub("[dD][bB]$",""):match("^%s*(.-)%s*$")  -- strip trailing "dB"
  if s=="-" or s=="-inf" then return prefs.inf_db end;if s=="" then return nil end
  local had_sign = s:match("^[%+%-]") ~= nil
  local n=tonumber(s);if not n then return nil end
  if prefs.default_negative == 1 and not had_sign and n>0 then n=-n end
  return math.floor(n*10+0.5)/10 end

-- id_map 快查: 每幀開頭重建一次
function FUNC.rebuild_id_map()
  id_map={}; for i,c in ipairs(cues) do id_map[c.id]=i end
end

-- find_id 用 id_map O(1) 查，拖曳中 map 可能 stale 所以有 fallback
function FUNC.find_id(id)
  local i=id_map[id]
  if i and i>=1 and i<=#cues and cues[i] and cues[i].id==id then return i,cues[i] end
  for j,c in ipairs(cues) do if c.id==id then id_map[id]=j; return j,c end end
  return nil
end

-- calc_dur 快取版，2秒過期 -- duration快取
function FUNC.calc_dur_cached(ti, cue_id)
  local now=reaper.time_precise()
  local dc=dur_cache[cue_id]
  if dc and (now-dc.t)<2 then return dc.dur end
  local d=FUNC.calc_dur(ti)
  dur_cache[cue_id]={dur=d,t=now}
  return d
end

function FUNC.is_sel(i) return selected[i]==true end
function FUNC.sel1(i) selected={};if i>=1 and i<=#cues then selected[i]=true end end
function FUNC.sel_rng(a,b) for i=math.min(a,b),math.max(a,b) do if i>=1 and i<=#cues then selected[i]=true end end end
function FUNC.sel_cnt() local n=0;for _ in pairs(selected) do n=n+1 end;return n end
function FUNC.sel_list() local r={};for i in pairs(selected) do r[#r+1]=i end;table.sort(r);return r end
function FUNC.sel_first() local f=nil;for i in pairs(selected) do if not f or i<f then f=i end end;return f or 0 end
-- find_id 已移到上方使用 id_map 快查

-- GROUP有trim時，計算child的有效trim（含GROUP裁剪）-- effective trim for child inside trimmed GROUP
function FUNC.get_eff_trim(c)
  local ts = c.trim_start or 0
  local te = c.trim_end or 0
  if not c.group_id or c.type ~= "PLAY" then return ts, te end  -- 無GROUP→直接回傳child自身trim
  local raw = FUNC.calc_dur(c.track_idx)
  if te <= 0 then te = raw end
  local _, gc = FUNC.find_id(c.group_id)
  if not gc or gc.type ~= "GROUP" then return ts, te end
  local g_ts = gc.trim_start or 0
  local g_te_raw = gc.trim_end or 0
  if g_ts <= 0.001 and g_te_raw <= 0.001 then return ts, te end
  -- GROUP has trim → find this child in lane_info and compute effective trim
  local gl = FUNC.group_lanes(gc)
  local g_te = (g_te_raw > 0) and g_te_raw or gl.dur
  for _, lane in ipairs(gl.lanes) do
    for _, entry in ipairs(lane.entries) do
      if entry.cue == c then
        local a_s = entry.offset + entry.pre
        local a_e = a_s + entry.eff_dur
        if a_e <= g_ts or a_s >= g_te then return ts, te end  -- 完全在窗口外
        local cr = (c.rate and c.rate > 0) and c.rate or 1.0
        local extra_s = math.max(0, g_ts - a_s) * cr
        local extra_e = math.max(0, a_e - g_te) * cr
        -- child trim 與 group trim 取較大者（非疊加）-- take max, not sum
        return math.max(ts, extra_s), te - extra_e
      end
    end
  end
  return ts, te
end

-- GROUP trim 對 child 投射出的 trim 下限 / 上限（child 只能在此範圍內往內縮）
-- returns (min_trim_start, max_trim_end) imposed by parent GROUP trim on this child's audio
function FUNC.get_group_trim_bounds(c)
  if not c or c.type ~= "PLAY" or not c.group_id then return 0, nil end
  local _, gc = FUNC.find_id(c.group_id)
  if not gc or gc.type ~= "GROUP" then return 0, nil end
  local g_ts = gc.trim_start or 0
  local g_te_raw = gc.trim_end or 0
  if g_ts <= 0.001 and g_te_raw <= 0.001 then return 0, nil end
  local gl = FUNC.group_lanes(gc); if not gl then return 0, nil end
  local g_te = (g_te_raw > 0) and g_te_raw or gl.dur
  for _, lane in ipairs(gl.lanes) do
    for _, entry in ipairs(lane.entries) do
      if entry.cue == c then
        local a_s = entry.offset + entry.pre
        local a_e = a_s + entry.eff_dur
        local cr = (c.rate and c.rate > 0) and c.rate or 1.0
        local raw = FUNC.calc_dur(c.track_idx)
        local orig_te_full = (c.trim_end and c.trim_end > 0) and c.trim_end or raw
        local min_ts = math.max(0, g_ts - a_s) * cr
        local max_te = orig_te_full - math.max(0, a_e - g_te) * cr
        return min_ts, max_te
      end
    end
  end
  return 0, nil
end

-- 巢狀 group 深度計算 -- nesting depth (0=root, 1=in group, 2=in group in group, ...)
MAX_GROUP_DEPTH = 5  -- 最大巢狀層數
function FUNC.cue_depth(c)
  local d = 0
  local gid = c.group_id
  while gid and d < MAX_GROUP_DEPTH do
    d = d + 1
    local _, gc = FUNC.find_id(gid)
    if not gc then break end
    gid = gc.group_id
  end
  return d
end

-- 釘住 tbl 為 table，若被某段神秘程式碼蓋成其他型別會立即在這裡爆掉，方便 trace
-- pin tbl as table; if anything overwrites with non-table, fail loud here for stack trace
assert(type(tbl) == "table", "Realive: tbl global corrupted at state.lua load (type=" .. type(tbl) .. ")")
