-- ==========================================================================
-- cue.lua — Cue Data, Undo/Redo, Execution, List Management
-- ==========================================================================

-- cue_color sentinel：-1=繼承 group 顏色（或無顏色 fallback），>0=自訂顏色，0=group 中手動清除
-- cue_color sentinel: -1=inherit from group, >0=custom color, 0=manually cleared inside group
CUE_COLOR_INHERIT = -1

---------------------------------------------------------------------
-- 8. CUE DATA
---------------------------------------------------------------------
-- 用reaper.genGuid產生真正唯一的ID，避免跨session碰撞 -- use REAPER GUID for truly unique IDs
function FUNC.nid() return reaper.genGuid("") end
function FUNC.mk_cue(tp)
  local ti=(tp=="SPACER") and -1 or math.max(0,FUNC.sel_tr())
  local nm=(tp=="SPACER") and "" or FUNC.tr_name(ti);if nm=="?" then nm="" end
  local tg=FUNC.tr_guid(ti)  -- 用GUID追蹤track，不怕track被移動/刪除 -- track GUID for stable reference
  local init_pan = 0
  if tp == "PLAY" then local tr=FUNC.get_tr(ti); if tr then init_pan=reaper.GetMediaTrackInfo_Value(tr,"D_PAN") end end
  return {id=FUNC.nid(),name=nm,cue_number="",type=tp or "PLAY",
    track_idx=ti,track_guid=tg,track_invalid=false,target_cue_id="",volume=0,
    fade_time=tp=="FADE" and prefs.default_fade_time or 0,fade_curve="linear",fade_curve_amt=2.5,
    pre_wait=0,post_wait=0,auto_go=false,kill_above=false,
    trim_start=0,trim_end=0,children={},group_id=nil,notes="",cue_color=CUE_COLOR_INHERIT,loop=false,pan=init_pan,
    env_enabled=false,env_points={},
    pan_env_enabled=false,pan_env_points={},  -- panning envelope(綠線)
    fx_envs={},  -- FX參數envelope陣列，每筆{fx_guid,param_idx,fx_name,param_name,enabled,visible,color,points={}} -- FX param envelopes (multiple per cue)
    hotkey="",  -- 熱鍵：按下即觸發此cue播放 -- per-cue hotkey trigger
    rate=1.0,  -- 播放速率 0.01~100, 1=正常 -- playback rate
    preserve_pitch=true,  -- 變速時保持音高 -- preserve pitch when changing rate
    pitch=0,  -- 音高調整(半音), -12~+12, 0=正常 -- pitch shift in semitones
    loop_count=0,  -- loop次數: 0=無限, >0=指定次數 -- loop count: 0=infinite, >0=N times
    loop_remaining=0,  -- runtime: 剩餘loop次數 -- runtime: remaining loops
    pre_wait_mode="time", post_wait_mode="time", fade_wait_mode="time",  -- 各自獨立time/bpm模式 -- independent time/bpm mode per field
    pre_bpm_beats=4, pre_bpm_val=120,  -- BPM mode: pre-wait拍數和BPM
    post_bpm_beats=4, post_bpm_val=120,  -- BPM mode: post-wait拍數和BPM
    fade_bpm_beats=4, fade_bpm_val=120,  -- BPM mode: fade time拍數和BPM
    pre_note_idx=NOTE_DEFAULT_IDX, post_note_idx=NOTE_DEFAULT_IDX, fade_note_idx=NOTE_DEFAULT_IDX,  -- 音符值索引 -- note value index
    fade_vol_enabled=false,                     -- FADE cue: volume漸變啟用(預設bypass) -- fade volume enabled (default bypass)
    fade_rate_enabled=false, fade_rate=1.0,    -- FADE cue: rate漸變目標(已停用) -- fade rate target (disabled due to glitch)
    fade_pitch_enabled=false, fade_pitch=0,    -- FADE cue: pitch漸變目標(預設bypass) -- fade pitch target (default bypass)
    fade_pan_enabled=false, fade_pan=0,        -- FADE cue: pan漸變目標(預設bypass) -- fade pan target (default bypass)
    spacer_align=1,  -- SPACER對齊: 0=左, 1=中, 2=右 -- spacer text alignment
    spacer_text_color=-1,  -- SPACER文字色: -1=自動, >0=自訂 -- spacer text color (-1=auto)
    spacer_border_color=-1,  -- SPACER框線色: -1=同cue_color, >0=自訂 -- spacer border color
    spacer_bold=false, spacer_italic=false,  -- SPACER文字粗體/斜體 -- text bold/italic
    spacer_alpha=255,  -- SPACER背景透明度(0-255) -- spacer bg alpha (only spacer can customize)
    fade_keep_playing=false,  -- FADE cue: 到-inf後仍繼續播放 -- keep playing after fade to -inf
    markers={},  -- waveform時間標記 -- waveform time markers
    route_trims={},  -- GROUP用: hw output channel trim, {[ch_idx]=trim_db, ...} -- GROUP route trim per hw channel
    route_hw=nil,  -- PLAY用: 虛擬hw output設定 {{ch=0,vol_db=0},...}, nil=未設定(用REAPER預設) -- virtual hw routing (nil=use REAPER default)
    -- Phase 5: Mode 簡化為 Message/Sequence；Dest 合併 internal 為第一選項 -- simplified mode+dest
    midi_mode="message",  -- "message"(直接送 MIDI 訊息表) | "sequence"(item playback) -- message=table-driven, sequence=timed item
    midi_msgs={},          -- message mode: {{type="note"|"cc"|"pc", event=int, value=int, msg="on"|"off"|"press", ch=1..16}, ...}
    midi_press_ms=100,     -- message mode: press 模式 on→off 間隔（ms） -- press mode on/off gap
    midi_device=-1,        -- -1=Internal(VKB); 0..N=外部 MIDI output device idx -- dest idx, -1=internal sentinel
    midi_ts_num=4,         -- 拍號分子 (編輯器 grid 用) -- time-sig numerator (editor grid)
    midi_ts_den=4,         -- 拍號分母 -- time-sig denominator
    midi_channel=1,        -- (legacy) 單音 MIDI channel 1-16 -- legacy single channel
    midi_note=60,          -- (legacy) MIDI note number 0-127 -- legacy single note
    midi_velocity=100,     -- (legacy) MIDI velocity 1-127 -- legacy single velocity
    midi_duration=0.5,     -- (legacy) note duration in seconds -- legacy single duration
    midi_cc=0,             -- (legacy) CC number 0-127 -- legacy single CC
    midi_cc_val=127,       -- (legacy) CC value 0-127 -- legacy single CC value
    midi_program=-1,       -- (legacy) Program Change -1=off, 0-127 -- legacy single PC
    -- Phase 2A: MIDI item 原型 + 廣播 channel + BPM/vel 縮放 -- item-based prototype + multi-channel broadcast + scaling
    midi_item_guid="",     -- 指向的 MIDI item GUID (原型，可共享) -- item prototype reference (shareable)
    midi_channels="1",     -- 廣播 channel，逗號分隔: "1" 或 "1,2,3,5,9" -- broadcast channels (comma-separated)
    midi_bpm=120.0,        -- 播放 BPM，用於時間縮放 -- playback BPM (time scaling)
    midi_vel_pct=100.0,    -- velocity 百分比 (100=不變)，對 note 乘積 -- velocity percentage multiplier
    state=STATE.IDLE,preview_ids={},total_dur=0,eff_dur=0,play_t0=0,play_offset=0}
end

-- MIDI note-off helper：若cue正在播放MIDI note，立即送note off -- send note off for active MIDI note cues
-- 優先使用Note On時快照的mode/ch/note，避免使用者播放中途改欄位造成Note Off對不上 -- prefer cached snapshot
function FUNC.midi_note_off(c)
  if c.type ~= "MIDI" or c.state ~= STATE.RUNNING or c.midi_mode == "message" then return end
  local mv, ch, nt
  if c._midi_off_mode and c._midi_off_ch and c._midi_off_note then
    mv, ch, nt = c._midi_off_mode, c._midi_off_ch, c._midi_off_note
  else
    ch = math.max(0, math.min(15, (c.midi_channel or 1) - 1))
    mv = ((c.midi_device or -1) < 0) and 0 or (16 + c.midi_device)
    nt = c.midi_note or 60
  end
  reaper.StuffMIDIMessage(mv, 0x80 + ch, nt, 0)
  c._midi_off_mode = nil; c._midi_off_ch = nil; c._midi_off_note = nil
end

function FUNC.esc(s) return s:gsub("\\","\\\\"):gsub("|","\\|"):gsub("\n","\\n"):gsub("\t","\\t") end  -- +tab轉義避免分隔符衝突
-- 單次掃描解碼：逐一處理 \x 序列，才能和 esc 完全互逆（舊版多次 gsub 會把 "\\t" 誤解成 tab）
-- single-pass decode so it exactly inverts esc (old chained gsub turned an escaped backslash + "t" into a tab)
function FUNC.unesc(s) return (s:gsub("\\(.)", function(ch) if ch=="n" then return "\n" elseif ch=="t" then return "\t" end return ch end)) end
-- markers序列化："t1;t2;t3" -- markers serialization
function FUNC.markers2str(m) if not m or #m == 0 then return "" end; local s={}; for _,t in ipairs(m) do s[#s+1]=string.format("%.4f",t) end; return table.concat(s,";") end
function FUNC.str2markers(s) if not s or s=="" then return {} end; local m={}; for v in s:gmatch("[^;]+") do local n=tonumber(v); if n then m[#m+1]=n end end; return m end
-- midi_msgs序列化（v2）："type,event,value,msg,ch_mask,press_ms;..." -- midi message rows v2
-- ch_mask: bit 0..15 對應 channel 1..16；press_ms: 僅 msg=press 用 -- ch bitmask + per-row press duration
-- 舊格式相容："type,event,value,msg,ch"（單 channel 整數）-- legacy 5-field per-row format
function FUNC.msgs2str(m)
  if not m or #m == 0 then return "" end
  local s = {}
  for _, e in ipairs(m) do
    -- v3: 7 欄 type,event,value,msg,ch_mask,press_ms,use_all
    s[#s+1] = string.format("%s,%d,%d,%s,%d,%d,%d",
      e.type or "note", tonumber(e.event) or 0, tonumber(e.value) or 0,
      e.msg or "on", tonumber(e.ch_mask) or 1, tonumber(e.press_ms) or 100,
      e.use_all and 1 or 0)
  end
  return table.concat(s, ";")
end
function FUNC.str2msgs(s)
  if not s or s == "" then return {} end
  local m = {}
  for row in s:gmatch("[^;]+") do
    -- v3: 7 欄 (含 use_all)
    local tp, ev, va, ms, mk, pm, ua = row:match("^([^,]+),([%-%d]+),([%-%d]+),([^,]+),([%-%d]+),([%-%d]+),([%-%d]+)$")
    if tp then
      m[#m+1] = {type=tp, event=tonumber(ev) or 0, value=tonumber(va) or 0,
                 msg=ms, ch_mask=tonumber(mk) or 1, press_ms=tonumber(pm) or 100,
                 use_all=(ua == "1")}
    else
      -- v2: 6 欄
      local tp2, ev2, va2, ms2, mk2, pm2 = row:match("^([^,]+),([%-%d]+),([%-%d]+),([^,]+),([%-%d]+),([%-%d]+)$")
      if tp2 then
        m[#m+1] = {type=tp2, event=tonumber(ev2) or 0, value=tonumber(va2) or 0,
                   msg=ms2, ch_mask=tonumber(mk2) or 1, press_ms=tonumber(pm2) or 100, use_all=false}
      else
        -- v1 legacy: 5 欄，單一 ch
        local tp1, ev1, va1, ms1, ch1 = row:match("^([^,]+),([%-%d]+),([%-%d]+),([^,]+),([%-%d]+)$")
        if tp1 then
          local ch_n = tonumber(ch1) or 1
          m[#m+1] = {type=tp1, event=tonumber(ev1) or 0, value=tonumber(va1) or 0,
                     msg=ms1, ch_mask=(1 << math.max(0, math.min(15, ch_n-1))), press_ms=100, use_all=false}
        end
      end
    end
  end
  return m
end
-- route_trims序列化："ch:trim;ch:trim" -- route_trims serialization
function FUNC.trims2str(t) if not t then return "" end; local s={}; for ch,db in pairs(t) do s[#s+1]=string.format("%d:%.1f",ch,db) end; table.sort(s); return table.concat(s,";") end
function FUNC.str2trims(s) if not s or s=="" then return {} end; local t={}; for pair in s:gmatch("[^;]+") do local ch,db=pair:match("^(%d+):([%-%d%.]+)$"); if ch then t[tonumber(ch)]=tonumber(db) or 0 end end; return t end
-- route_hw序列化(有序)："ch:vol_db:color;..." (color省略=-1無色) -- route_hw serialization (ordered), color optional
function FUNC.routehw2str(r) if not r or #r==0 then return "" end; local s={}; for _,e in ipairs(r) do local col=e.color or -1; if col==-1 then s[#s+1]=string.format("%d:%.1f",e.ch,e.vol_db) else s[#s+1]=string.format("%d:%.1f:%d",e.ch,e.vol_db,col) end end; return table.concat(s,";") end
function FUNC.str2routehw(s) if not s or s=="" then return nil end; local r={}; for pair in s:gmatch("[^;]+") do local ch,db,col=pair:match("^([%-%d]+):([%-%d%.]+):?([%-%d]*)$"); if ch then r[#r+1]={ch=tonumber(ch),vol_db=tonumber(db) or 0,color=col~="" and tonumber(col) or -1} end end; return #r>0 and r or nil end
-- fx_envs序列化 -- FX envelopes serialization
-- 格式: env1^env2^... 每筆env: fx_guid~param_idx~enabled~visible~color~fx_name~param_name~points_str
-- fx_name/param_name 內的 \ ^ ~ 會被轉義為 \\ \^ \~
local function fxe_esc(s) return (tostring(s or ""):gsub("\\","\\\\"):gsub("%^","\\^"):gsub("~","\\~")) end
local function fxe_unesc(s) return (tostring(s or ""):gsub("\\~","~"):gsub("\\%^","^"):gsub("\\\\","\\")) end
function FUNC.fx_envs2str(envs)
  if not envs or #envs == 0 then return "" end
  local out = {}
  for _, e in ipairs(envs) do
    out[#out+1] = table.concat({
      fxe_esc(e.fx_guid or ""),
      tostring(e.param_idx or 0),
      e.enabled and "1" or "0",
      e.visible and "1" or "0",
      tostring(e.color or -1),
      fxe_esc(e.fx_name or ""),
      fxe_esc(e.param_name or ""),
      FUNC.env_pts2str(e.points or {}),
    }, "~")
  end
  return table.concat(out, "^")
end
function FUNC.str2fx_envs(s)
  if not s or s == "" then return {} end
  local envs = {}
  -- 手動分割 ^（處理轉義的 \^）-- manually split on ^ respecting escaped \^
  local cur, i = "", 1
  local segs = {}
  while i <= #s do
    local ch = s:sub(i,i)
    if ch == "\\" and i < #s then cur = cur .. s:sub(i,i+2); i = i + 2
    elseif ch == "^" then segs[#segs+1] = cur; cur = ""; i = i + 1
    else cur = cur .. ch; i = i + 1 end
  end
  segs[#segs+1] = cur
  for _, seg in ipairs(segs) do
    if seg ~= "" then
      -- 手動分割 ~（同樣尊重轉義）-- split on ~ respecting escapes
      local f, j, buf = {}, 1, ""
      while j <= #seg do
        local c2 = seg:sub(j,j)
        if c2 == "\\" and j < #seg then buf = buf .. seg:sub(j,j+1); j = j + 2
        elseif c2 == "~" then f[#f+1] = buf; buf = ""; j = j + 1
        else buf = buf .. c2; j = j + 1 end
      end
      f[#f+1] = buf
      if #f >= 8 then
        envs[#envs+1] = {
          fx_guid    = fxe_unesc(f[1]),
          param_idx  = tonumber(f[2]) or 0,
          enabled    = (f[3] == "1"),
          visible    = (f[4] == "1"),
          color      = tonumber(f[5]) or -1,
          fx_name    = fxe_unesc(f[6]),
          param_name = fxe_unesc(f[7]),
          points     = FUNC.env_str2pts(f[8]),
        }
      end
    end
  end
  return envs
end
function FUNC.c2s(c)
  local ch={};for _,v in ipairs(c.children or {}) do ch[#ch+1]=tostring(v) end
  return table.concat({FUNC.esc(c.id),FUNC.esc(c.name),FUNC.esc(c.cue_number),c.type,
    FUNC.esc(c.track_guid or ""),FUNC.esc(c.target_cue_id or ""),tostring(c.volume),  -- field5: GUID取代track_idx
    tostring(c.fade_time),c.fade_curve,tostring(c.pre_wait),tostring(c.post_wait),
    c.auto_go and "1" or "0",tostring(c.trim_start),tostring(c.trim_end),
    table.concat(ch,","),FUNC.esc(c.group_id or ""),c.kill_above and "1" or "0",FUNC.esc(c.notes or ""),
    tostring(c.cue_color or -1),c.loop and "1" or "0",tostring(c.pan or 0),
    c.env_enabled and "1" or "0",FUNC.env_pts2str(c.env_points),
    tostring(c.fade_curve_amt or 2.5),
    c.pan_env_enabled and "1" or "0",FUNC.pan_env_pts2str(c.pan_env_points),
    FUNC.esc(c.hotkey or ""),
    tostring(c.rate or 1.0),c.preserve_pitch and "1" or "0",
    tostring(c.pitch or 0),tostring(c.loop_count or 0),
    c.pre_wait_mode or "time",tostring(c.pre_bpm_beats or 4),tostring(c.pre_bpm_val or 120),
    tostring(c.post_bpm_beats or 4),tostring(c.post_bpm_val or 120),
    tostring(c.pre_note_idx or NOTE_DEFAULT_IDX),tostring(c.post_note_idx or NOTE_DEFAULT_IDX),
    c.fade_rate_enabled and "1" or "0",tostring(c.fade_rate or 1.0),
    c.fade_pitch_enabled and "1" or "0",tostring(c.fade_pitch or 0),
    tostring(c.spacer_align or 1),
    tostring(c.spacer_text_color or -1),
    tostring(c.spacer_border_color or -1),
    c.spacer_bold and "1" or "0",
    c.spacer_italic and "1" or "0",
    c.fade_keep_playing and "1" or "0",
    tostring(c.spacer_alpha or 255),
    c.fade_pan_enabled and "1" or "0",tostring(c.fade_pan or 0),
    c.post_wait_mode or "time",c.fade_wait_mode or "time",  -- fields 52-53: independent modes
    tostring(c.fade_bpm_beats or 4),tostring(c.fade_bpm_val or 120),tostring(c.fade_note_idx or NOTE_DEFAULT_IDX),
    c.fade_vol_enabled and "1" or "0",
    FUNC.markers2str(c.markers),  -- field 58: markers
    FUNC.trims2str(c.route_trims),  -- field 59: GROUP route trims
    FUNC.routehw2str(c.route_hw),  -- field 60: PLAY route hw overrides
    FUNC.fx_envs2str(c.fx_envs),  -- field 61: FX parameter envelopes
    c.midi_mode or "message",  -- field 62: MIDI mode
    tostring(c.midi_device or 0),  -- field 63: MIDI device
    tostring(c.midi_channel or 1),  -- field 64: MIDI channel
    tostring(c.midi_note or 60),  -- field 65: MIDI note
    tostring(c.midi_velocity or 100),  -- field 66: MIDI velocity
    tostring(c.midi_duration or 0.5),  -- field 67: MIDI note duration
    tostring(c.midi_cc or 0),  -- field 68: MIDI CC number
    tostring(c.midi_cc_val or 127),  -- field 69: MIDI CC value
    tostring(c.midi_program or -1),  -- field 70: MIDI program change
    -- Phase 2A MIDI fields (71-74)
    FUNC.esc(c.midi_item_guid or ""),  -- field 71: MIDI item GUID (prototype ref)
    FUNC.esc(c.midi_channels or "1"),  -- field 72: broadcast channels (e.g. "1,2,3,5,9")
    tostring(c.midi_bpm or 120),       -- field 73: playback BPM
    tostring(c.midi_vel_pct or 100),   -- field 74: velocity percentage multiplier
    -- Phase 5: 拍號 -- time signature (editor grid override)
    tostring(c.midi_ts_num or 4),      -- field 75: time-sig numerator
    tostring(c.midi_ts_den or 4),      -- field 76: time-sig denominator
    -- Phase 6: Message mode 表格 -- message-mode rows
    FUNC.msgs2str(c.midi_msgs),        -- field 77: message rows
    tostring(c.midi_press_ms or 100),  -- field 78: press on/off gap (ms)
    "1"},                              -- field 79: env_abs flag (env points use absolute audio time)
    "|")
end
-- s2c：解析失敗時標記 _broken 但仍回傳 cue（UI 顯示灰底、禁止播放/執行）
-- s2c: on parse failure, mark _broken but still return so UI greys it out
local VALID_TYPES = {PLAY=1, STOP=1, FADE=1, PAUSE=1, GROUP=1, SPACER=1, MIDI=1}
local function s2c_parse(s)
  local P={};local i,cur=1,""
  while i<=#s do local ch=s:sub(i,i)
    if ch=="\\" and i<#s then cur=cur..s:sub(i,i+1);i=i+2
    elseif ch=="|" then P[#P+1]=cur;cur="";i=i+1 else cur=cur..ch;i=i+1 end
  end;P[#P+1]=cur
  local _broken = false
  if not P[1] or P[1] == "" then _broken = true end
  if not P[4] or not VALID_TYPES[P[4]] then _broken = true end
  local c=FUNC.mk_cue(P[4] or "PLAY")
  c.id=FUNC.unesc(P[1] or c.id);c.name=FUNC.unesc(P[2] or "")
  c.cue_number=FUNC.unesc(P[3] or "");c.type=P[4] or "PLAY"
  local f5 = FUNC.unesc(P[5] or "")
  c.track_guid = f5
  c.track_idx = (f5 ~= "") and FUNC.guid_to_idx(f5) or -1
  c.track_invalid = (c.track_idx < 0 and c.type == "PLAY")
  c.target_cue_id=FUNC.unesc(P[6] or "");c.volume=tonumber(P[7]) or 0
  c.fade_time=tonumber(P[8]) or 0;c.fade_curve=P[9] or "linear"
  c.pre_wait=tonumber(P[10]) or 0;c.post_wait=tonumber(P[11]) or 0
  c.auto_go=(P[12]=="1");c.trim_start=tonumber(P[13]) or 0;c.trim_end=tonumber(P[14]) or 0
  c.children={};if P[15] and P[15]~="" then for n in P[15]:gmatch("%d+") do c.children[#c.children+1]=tonumber(n) end end
  c.group_id=(P[16] and P[16]~="") and FUNC.unesc(P[16]) or nil
  c.kill_above=(P[17]=="1")
  c.notes=(P[18] and P[18]~="") and FUNC.unesc(P[18]) or ""
  c.cue_color=tonumber(P[19]) or -1
  c.loop=(P[20]=="1")
  c.pan=tonumber(P[21]) or 0
  c.env_enabled=(P[22]=="1")
  c.env_points=FUNC.env_str2pts(P[23] or "")
  c.fade_curve_amt=tonumber(P[24]) or 2.5
  c.pan_env_enabled=(P[25]=="1")
  c.pan_env_points=FUNC.pan_env_str2pts(P[26] or "")
  c.hotkey=FUNC.unesc(P[27] or "")
  c.rate=tonumber(P[28]) or 1.0
  c.preserve_pitch=(P[29]=="1")
  c.pitch=tonumber(P[30]) or 0
  c.loop_count=tonumber(P[31]) or 0
  c.pre_wait_mode = (P[32]=="bpm") and "bpm" or "time"
  c.pre_bpm_beats=tonumber(P[33]) or 4
  c.pre_bpm_val=tonumber(P[34]) or 120
  c.post_bpm_beats=tonumber(P[35]) or 4
  c.post_bpm_val=tonumber(P[36]) or 120
  c.pre_note_idx=tonumber(P[37]) or NOTE_DEFAULT_IDX
  c.post_note_idx=tonumber(P[38]) or NOTE_DEFAULT_IDX
  c.fade_rate_enabled=(P[39]=="1")
  c.fade_rate=tonumber(P[40]) or 1.0
  c.fade_pitch_enabled=(P[41]=="1")
  c.fade_pitch=tonumber(P[42]) or 0
  c.spacer_align=tonumber(P[43]) or 1
  c.spacer_text_color=tonumber(P[44]) or -1
  c.spacer_border_color=tonumber(P[45]) or -1
  c.spacer_bold=(P[46]=="1")
  c.spacer_italic=(P[47]=="1")
  c.fade_keep_playing=(P[48]=="1")
  c.spacer_alpha=tonumber(P[49]) or 255
  c.fade_pan_enabled=(P[50]=="1")
  c.fade_pan=tonumber(P[51]) or 0
  c.post_wait_mode = (P[52]=="bpm") and "bpm" or "time"
  c.fade_wait_mode = (P[53]=="bpm") and "bpm" or "time"
  c.fade_bpm_beats = tonumber(P[54]) or 4
  c.fade_bpm_val = tonumber(P[55]) or 120
  c.fade_note_idx = tonumber(P[56]) or NOTE_DEFAULT_IDX
  c.fade_vol_enabled=(P[57]=="1")
  c.markers = FUNC.str2markers(P[58] or "")
  c.route_trims = FUNC.str2trims(P[59] or "")
  c.route_hw = FUNC.str2routehw(P[60] or "")
  c.fx_envs = FUNC.str2fx_envs(P[61] or "")
  c.midi_mode = (P[62]=="message" or P[62]=="sequence") and P[62] or "sequence"
  c.midi_device = tonumber(P[63]) or -1
  c.midi_channel = tonumber(P[64]) or 1
  c.midi_note = tonumber(P[65]) or 60
  c.midi_velocity = tonumber(P[66]) or 100
  c.midi_duration = tonumber(P[67]) or 0.5
  c.midi_cc = tonumber(P[68]) or 0
  c.midi_cc_val = tonumber(P[69]) or 127
  c.midi_program = tonumber(P[70]) or -1
  c.midi_item_guid = FUNC.unesc(P[71] or "")
  c.midi_channels = (P[72] and P[72] ~= "") and FUNC.unesc(P[72]) or "1"
  c.midi_bpm = tonumber(P[73]) or 120.0
  c.midi_vel_pct = tonumber(P[74]) or 100.0
  c.midi_ts_num = tonumber(P[75]) or 4
  c.midi_ts_den = tonumber(P[76]) or 4
  c.midi_msgs = FUNC.str2msgs(P[77] or "")
  c.midi_press_ms = tonumber(P[78]) or 100
  c.state=STATE.IDLE;c.preview_ids={}
  c._broken = _broken or nil
  return c
end
function FUNC.s2c(s)
  if not s or s == "" then return nil end
  local ok, c = pcall(s2c_parse, s)
  if not ok then
    -- helper 拋例外：建空 cue 標記為損壞，避免整個 show load crash
    -- helper threw: build empty broken cue to keep show loadable
    local fb = FUNC.mk_cue("PLAY"); fb._broken = true; fb.name = "(corrupt)"
    fb.state = STATE.IDLE; fb.preview_ids = {}
    return fb
  end
  return c
end

---------------------------------------------------------------------
-- 8.5 UNDO/REDO SYSTEM
---------------------------------------------------------------------
undo={stack={},redo={},MAX=100,paused=false,last_snap=""}  -- undo buffer擴大至100

-- 序列化collapsed_groups為逗號分隔的cue id列表 -- serialize collapsed group ids
local function collapsed2str()
  local ids = {}; for id, v in pairs(collapsed_groups) do if v then ids[#ids+1] = id end end
  return table.concat(ids, ",")
end
local function str2collapsed(s)
  collapsed_groups = {}
  if s and s ~= "" then for id in s:gmatch("[^,]+") do collapsed_groups[id] = true end end
end

function FUNC.snap_cues()
  local l = {}; for _, c in ipairs(cues) do l[#l+1] = FUNC.c2s(c) end
  return table.concat(l, "\n") .. "\n@@" .. tostring(next_go) .. "\n@@CG=" .. collapsed2str()
end

function FUNC.restore_snap(s)
  -- 向下相容：新格式含 @@CG= 行 -- backward compat: new format has @@CG= line
  local data, ng, cg_str = s:match("^(.-)%\n@@(%d+)\n@@CG=(.*)$")
  if not data then
    data, ng = s:match("^(.-)%\n@@(%d+)$")
    if not data then data = s; ng = "0" end
  end
  local old = cues
  cues = {}
  if data ~= "" then for line in data:gmatch("[^\n]+") do local ok,c=pcall(FUNC.s2c,line);if ok and c then cues[#cues+1]=c end end end  -- pcall防止舊格式crash -- pcall for backward compat
  FUNC.adopt_runtime(old)  -- 播放中的 cue 不變孤兒 -- cues that are playing stay under control
  next_go = tonumber(ng) or 0; if next_go > #cues then next_go = #cues end
  if cg_str then str2collapsed(cg_str) end  -- 恢復收合狀態 -- restore collapsed state
  selected = {}
  if next_go >= 1 and next_go <= #cues then FUNC.sel1(next_go) end
end

-- Undo/Redo 會用存檔文字重建整份 cue 列表。重建後：
--   仍存在的播放中 cue → 沿用原本的物件（只換掉可存檔的欄位），聲音、計時器、淡出都繼續受控
--   被拿掉的播放中 cue → 立刻停止並還原軌道
-- Undo/Redo rebuild the whole cue list from saved text. After the rebuild:
--   a playing cue that still exists → keep its live object (only saved fields are replaced), so sound/timers/fades stay under control
--   a playing cue that is gone      → stop it now and give its track back
local RT_KEYS = {state=true,preview_ids=true,total_dur=true,eff_dur=true,play_t0=true,play_offset=true,
  loop_remaining=true,loop_go_fired=true,loop_done=true}
local function is_rt_key(k) return RT_KEYS[k] or k:sub(1,1)=="_" end
local function is_live(c)
  return c.state~=STATE.IDLE or (c.preview_ids and #c.preview_ids>0) or paused_cues[c.id]~=nil
    or soft_kill[c.id]~=nil or c._rt_hw_saved~=nil
end
function FUNC.adopt_runtime(old)
  local live, any = {}, false
  for _,oc in ipairs(old or {}) do if is_live(oc) then live[oc.id]=oc; any=true end end
  if not any then return end
  for i,nc in ipairs(cues) do
    local oc = live[nc.id]
    -- 換了類型或軌道就不沿用（當成被拿掉，下面會停掉）-- different type/track: don't adopt, it gets stopped below
    if oc and oc.type==nc.type and oc.track_guid==nc.track_guid then
      for k in pairs(oc) do if not is_rt_key(k) then oc[k]=nil end end
      for k,v in pairs(nc) do if not is_rt_key(k) then oc[k]=v end end
      oc._broken = nc._broken
      cues[i]=oc; live[nc.id]=nil
    end
  end
  FUNC.rebuild_id_map()
  for _,oc in pairs(live) do
    FUNC.rt_restore_trims(oc); FUNC.cancel_fades_cue(oc); FUNC.kill_cue(oc)
    paused_cues[oc.id]=nil; soft_kill[oc.id]=nil
  end
  FUNC.check_global_unlock()
end

function FUNC.push_undo()
  if undo.paused then return end
  local s = FUNC.snap_cues()
  if s == undo.last_snap then return end
  -- 只比較cue資料（不含next_go）決定是否真的push -- only push when cue DATA changes, not just next_go
  local cur_data = s:match("^(.-)%\n@@") or s
  local last_data = undo.last_snap:match("^(.-)%\n@@") or undo.last_snap
  if cur_data == last_data then
    undo.last_snap = s  -- next_go變了但cue沒變：更新snap但不push -- update snap without pushing
    return
  end
  undo.stack[#undo.stack+1] = undo.last_snap
  if #undo.stack > undo.MAX then table.remove(undo.stack, 1) end
  undo.redo = {}
  undo.last_snap = s
  dirty = true  -- 標題列米字號：有變更
end


function FUNC.save_cues()
  FUNC.push_undo()
  local l={};for _,c in ipairs(cues) do l[#l+1]=FUNC.c2s(c) end
  reaper.SetProjExtState(0,EXT.SECTION,EXT.KEY,table.concat(l,"\t"))  -- \t取代\n避免INI格式問題
  reaper.SetProjExtState(0,EXT.SECTION,"FocusCue",tostring(next_go))
  reaper.SetProjExtState(0,EXT.SECTION,"ShowName",show_name or "")  -- 記住show名稱 -- persist show name per project
  reaper.SetProjExtState(0,EXT.SECTION,"Collapsed",collapsed2str())  -- 儲存收合狀態 -- save collapsed state
  reaper.SetProjExtState(0,EXT.SECTION,"ProjectNotes",project_notes or "")  -- 專案備註 -- persist project notes
end

function FUNC.save_cues_persist()
  local l={};for _,c in ipairs(cues) do l[#l+1]=FUNC.c2s(c) end
  reaper.SetProjExtState(0,EXT.SECTION,EXT.KEY,table.concat(l,"\t"))  -- \t取代\n避免INI格式問題
  reaper.SetProjExtState(0,EXT.SECTION,"FocusCue",tostring(next_go))
  reaper.SetProjExtState(0,EXT.SECTION,"ShowName",show_name or "")  -- 記住show名稱
  reaper.SetProjExtState(0,EXT.SECTION,"Collapsed",collapsed2str())  -- 儲存收合狀態
  reaper.SetProjExtState(0,EXT.SECTION,"ProjectNotes",project_notes or "")  -- 專案備註
end

function FUNC.do_undo()
  if #undo.stack == 0 then return end
  -- 收集undo前的track guids -- collect track guids before undo
  local before = {}
  for _, c in ipairs(cues) do
    if c.track_guid and c.track_guid ~= "" then before[c.track_guid] = true end
  end
  undo.redo[#undo.redo+1] = FUNC.snap_cues()
  local prev = table.remove(undo.stack)
  FUNC.restore_snap(prev)
  undo.last_snap = prev
  -- 移除undo後仍存在的guid，剩下的=這次undo消失的cue的track -- subtract guids still present after undo
  for _, c in ipairs(cues) do
    if c.track_guid and c.track_guid ~= "" then before[c.track_guid] = nil end
  end
  FUNC.check_delete_tracks(before)  -- 刪除孤兒copied track
  FUNC.save_cues_persist()
end

function FUNC.do_redo()
  if #undo.redo == 0 then return end
  undo.stack[#undo.stack+1] = FUNC.snap_cues()
  local next_s = table.remove(undo.redo)
  FUNC.restore_snap(next_s)
  undo.last_snap = next_s
  FUNC.save_cues_persist()
end

function FUNC.load_cues()
  local _,d=reaper.GetProjExtState(0,EXT.SECTION,EXT.KEY);cues={}
  if d and d~="" then for line in d:gmatch("[^\t\n]+") do local ok,c=pcall(FUNC.s2c,line);if ok and c then cues[#cues+1]=c end end end  -- \t(新)+\n(舊)雙相容
  local _,fc=reaper.GetProjExtState(0,EXT.SECTION,"FocusCue")
  next_go=tonumber(fc) or 0;if next_go>#cues then next_go=#cues end
  -- 載入show名稱(切換project時自動恢復) -- restore show name per project
  local _,sn=reaper.GetProjExtState(0,EXT.SECTION,"ShowName")
  show_name = (sn and sn ~= "") and sn or ""
  -- 載入收合狀態 -- restore collapsed state
  local _,cs=reaper.GetProjExtState(0,EXT.SECTION,"Collapsed")
  str2collapsed(cs)
  -- 載入專案備註 -- restore project notes
  local _,pn=reaper.GetProjExtState(0,EXT.SECTION,"ProjectNotes")
  project_notes = (pn and pn ~= "") and pn or ""
  undo.last_snap=FUNC.snap_cues(); undo.stack={}; undo.redo={}
end

---------------------------------------------------------------------
-- 9. CUE EXECUTION
---------------------------------------------------------------------
function FUNC.get_target(c) if c.target_cue_id=="" then return nil end;return FUNC.find_id(c.target_cue_id) end
function FUNC.get_target_cues(c)
  local ti, tc = FUNC.get_target(c)
  if not tc then return {} end
  if tc.type == "GROUP" then
    local out = {}
    for _, ch in ipairs(tc.children or {}) do
      if ch >= 1 and ch <= #cues then out[#out+1] = cues[ch] end
    end
    return out
  end
  return {tc}
end

function FUNC.kill_above(ci)
  -- 不走 hard_kill_cue：避免每輪 check_global_unlock，且需把 nested GROUP 的 children 一併處理
  -- avoid hard_kill_cue here: (1) skip per-iter check_global_unlock; (2) GROUP 上方需展開 nested children 否則殘留
  for i=1,ci-1 do
    local c2 = cues[i]
    if c2.type == "GROUP" then
      for _, leaf in ipairs(FUNC.collect_group_leaves(c2)) do
        FUNC.cancel_fades_cue(leaf); FUNC.kill_cue(leaf)
        paused_cues[leaf.id]=nil; soft_kill[leaf.id]=nil
      end
    end
    FUNC.cancel_fades_cue(c2); FUNC.kill_cue(c2)
    paused_cues[c2.id]=nil; soft_kill[c2.id]=nil
  end
  FUNC.check_global_unlock()  -- 整輪結束才檢查解鎖一次 -- single unlock check at end
end

-- Bug 4/6: 若 c 是某個 GROUP 的 child 且該 GROUP 有 trim，計算並設定 _rt_trim_start/_rt_trim_end
-- 讓單獨播放或 trim 重播的 child 也吃到 parent group trim
-- compute child's _rt_trim_start/_rt_trim_end from parent group's trim window so single-play /
-- trim-driven replay still respects group trim
function FUNC.apply_parent_group_trim(c)
  if not c or c.type ~= "PLAY" or not c.group_id then return end
  local _, gc = FUNC.find_id(c.group_id)
  if not gc or gc.type ~= "GROUP" then return end
  local g_ts = gc.trim_start or 0
  local g_te_raw = gc.trim_end or 0
  if g_ts <= 0.001 and g_te_raw <= 0.001 then return end
  local gl = FUNC.group_lanes(gc); if not gl or gl.dur <= 0 then return end
  local g_te = (g_te_raw > 0) and g_te_raw or gl.dur
  for _, lane in ipairs(gl.lanes) do
    for _, entry in ipairs(lane.entries) do
      if entry.cue == c then
        local a_s = entry.offset + entry.pre
        local a_e = a_s + entry.eff_dur
        if a_e <= g_ts or a_s >= g_te then return end  -- 完全在窗口外則不動
        local cr = (c.rate and c.rate > 0) and c.rate or 1.0
        local orig_ts = c.trim_start or 0
        local raw = FUNC.calc_dur(c.track_idx)
        local orig_te = (c.trim_end and c.trim_end > 0) and c.trim_end or raw
        local extra_start = math.max(0, g_ts - a_s) * cr
        local extra_end = math.max(0, a_e - g_te) * cr
        -- child trim 與 group trim 取較大者（非疊加）：誰要求得更晚起播就聽誰的
        -- child trim and group-imposed trim take max (not sum): whichever starts later wins
        c._rt_trim_start = math.max(orig_ts, extra_start)
        c._rt_trim_end = orig_te - extra_end
        return
      end
    end
  end
end

function FUNC.exec_cue(ci)
  if ci<1 or ci>#cues then return end;local c=cues[ci]
  if c._broken then return end  -- 損壞 cue：禁止執行 -- broken cue: refuse to play
  if c.type=="SPACER" then c.state=STATE.DONE;FUNC.check_post(ci);return end
  if c.kill_above then FUNC.kill_above(ci) end
  if c.type=="PLAY" then
    FUNC.hard_kill_cue(c)
    -- Bug 4: 單獨播 child 時，若 parent group 有 trim 也要套用
    -- single-play child: inherit parent group trim if applicable (skip if _rt already set by GROUP path)
    if not c._rt_trim_start and not c._rt_trim_end then FUNC.apply_parent_group_trim(c) end
    c.loop_go_fired = false
    c.loop_done = false  -- 重置loop完成標記 -- reset loop done flag
    c.loop_remaining = c.loop_count or 0  -- 初始化loop剩餘次數 -- init remaining loop count
  elseif c.type=="MIDI" then
    -- MIDI cue 也支援 loop：重置 runtime 旗標 -- MIDI cue loop support: reset runtime flags
    c.loop_go_fired = false
    c.loop_done = false
    c.loop_remaining = c.loop_count or 0
  end
  c.state=STATE.RUNNING
  if c.type=="PLAY" then FUNC.play_cue(c)
    local dur = c.eff_dur > 0 and c.eff_dur or c.total_dur
    if dur > 0 then
      c.state=STATE.RUNNING
    else
      c.state=STATE.DONE; FUNC.check_post(ci)
    end
  elseif c.type=="STOP" then
    local targets = FUNC.get_target_cues(c)
    for _, tc in ipairs(targets) do FUNC.hard_kill_cue(tc) end
    c.state=STATE.DONE;FUNC.check_post(ci)
  elseif c.type=="PAUSE" then
    local targets = FUNC.get_target_cues(c)
    for _, tc in ipairs(targets) do
      if FUNC.is_cue_paused(tc) then FUNC.resume_cue(tc) else FUNC.pause_cue(tc) end
    end
    c.state=STATE.DONE;FUNC.check_post(ci)
  elseif c.type=="FADE" then
    local _,tc=FUNC.get_target(c)
    -- 只在職責重疊時才kill舊fade -- only kill old fade when parameters overlap
    if c.target_cue_id ~= "" then
      local new_p = {vol=c.fade_vol_enabled, pan=c.fade_pan_enabled, pitch=c.fade_pitch_enabled, rate=c.fade_rate_enabled}
      for fi, fc in ipairs(cues) do
        if fi ~= ci and fc.type == "FADE" and fc.target_cue_id == c.target_cue_id
            and fc.state == STATE.RUNNING then
          local overlap = (new_p.vol and fc.fade_vol_enabled) or (new_p.pan and fc.fade_pan_enabled)
            or (new_p.pitch and fc.fade_pitch_enabled) or (new_p.rate and fc.fade_rate_enabled)
          if overlap then
            fc.state = STATE.IDLE; fc.play_t0 = 0
            cancelled_fades[fc.id] = reaper.time_precise()
            local ti = 1; while ti <= #active_timers do
              if active_timers[ti].owner == fc.id then table.remove(active_timers, ti) else ti = ti + 1 end
            end
          end
        end
      end
    end
    c.play_t0=reaper.time_precise()
    local targets = FUNC.get_target_cues(c)
    local any_active = false
    local fade_done_count = 0
    local fade_total = #targets
    for _, ftc in ipairs(targets) do
      FUNC.cancel_fades_cue(ftc)
      if FUNC.cue_has_pv(ftc) or FUNC.cue_is_active(ftc) then
        any_active = true
        -- 只啟用enabled的參數 -- only include enabled params
        local fade_opts = {owner = c.id}
        if c.fade_pitch_enabled then fade_opts.pitch_to = c.fade_pitch or 0 end
        if c.fade_pan_enabled then fade_opts.pan_to = c.fade_pan or 0 end
        -- volume：未啟用時hold在當前音量 -- hold current volume if not enabled
        local vol_to = c.volume
        if not c.fade_vol_enabled and ftc.preview_ids and #ftc.preview_ids > 0 then
          vol_to = FUNC.pv_get_db(ftc.preview_ids[1])
        end
        FUNC.start_fade_cue(ftc, vol_to, c.fade_time, c.fade_curve, function()
          if c.state ~= STATE.RUNNING then return end  -- 這個 FADE cue 已被取消/停止 -- this FADE cue was cancelled/killed meanwhile
          -- fade_keep_playing：到-inf也不停止播放 -- keep playing even at -inf
          if c.fade_vol_enabled and c.volume <= prefs.inf_db and not c.fade_keep_playing then FUNC.kill_cue(ftc) end
          fade_done_count = fade_done_count + 1
          if fade_done_count >= fade_total then c.state=STATE.DONE; local i=FUNC.find_id(c.id); if i then FUNC.check_post(i) end end
        end, c.fade_curve_amt, fade_opts)
      else
        fade_done_count = fade_done_count + 1
      end
    end
    if any_active then
      c.state = STATE.RUNNING
      return
    end
    c.state=STATE.RUNNING
    FUNC.start_timer(c.fade_time,ci,TIMER.FADE_SILENT,function() c.state=STATE.DONE;local i=FUNC.find_id(c.id);if i then FUNC.check_post(i) end end)
  elseif c.type=="GROUP" then
    -- 循環巢狀守衛：A→B→A 之類的 children 環會讓 preview→exec_cue 無限遞迴 (line 784 stack overflow)
    -- guard against cyclic GROUP nesting causing preview/exec_cue infinite recursion
    _exec_group_stack = _exec_group_stack or {}
    if _exec_group_stack[c.id] then
      c.state=STATE.DONE; FUNC.check_post(ci); return
    end
    _exec_group_stack[c.id] = true
    local g_ts = c.trim_start or 0
    local g_te_raw = c.trim_end or 0
    local has_gtrim = g_ts > 0.001 or g_te_raw > 0.001
    if has_gtrim then
      -- GROUP trim 模式：用lane分析計算每個child的時間位置 -- use lane analysis for child timing
      local gl = FUNC.group_lanes(c)
      local gdur = gl.dur_pos  -- 播放長度用正時段(不含視覺 prefix) -- positive playable dur only
      local g_te = (g_te_raw > 0) and g_te_raw or gdur
      for _, lane in ipairs(gl.lanes) do
        for _, entry in ipairs(lane.entries) do
          local cc = entry.cue
          local a_s = entry.offset + entry.pre   -- 音訊起點(GROUP時間軸) -- audio start on GROUP timeline
          local a_e = a_s + entry.eff_dur        -- 音訊終點 -- audio end
          if a_e <= g_ts or a_s >= g_te then goto gtrim_skip end  -- 完全在窗口外 -- fully outside window
          if cc.type == "PLAY" then
            local cr = (cc.rate and cc.rate > 0) and cc.rate or 1.0
            local orig_ts = cc.trim_start or 0
            local raw = FUNC.calc_dur(cc.track_idx)
            local orig_te = (cc.trim_end and cc.trim_end > 0) and cc.trim_end or raw
            -- C10 絕對 timecode：group trim 在 child 既有 trim 之上額外裁剪
            -- absolute timecode model: GROUP trim cuts on top of child's existing trim
            local extra_start = math.max(0, g_ts - a_s) * cr
            local extra_end = math.max(0, a_e - g_te) * cr
            cc._rt_trim_start = orig_ts + extra_start
            cc._rt_trim_end = orig_te - extra_end
          end
          -- 延遲 = child在GROUP時間軸的位置 - GROUP trim起點 -- delay from GROUP trim start
          local child_start = entry.offset  -- 包含pre_wait的起始時間 -- includes pre_wait
          local delay = math.max(0, child_start - g_ts)
          -- 如果GROUP trim跳過了pre_wait，也要跳過child的pre_wait -- skip pre_wait if GROUP trim past it
          local skip_pre = (g_ts > entry.offset + entry.pre)  -- GROUP trim已超過pre_wait
          -- 部分砍 pre：g_ts 落在 [entry.offset, entry.offset+entry.pre) 內 → 縮短 pre_wait
          -- partial pre trim: g_ts inside child's pre window → shrink pre_wait via _rt override
          if not skip_pre and entry.pre > 0 and g_ts > entry.offset then
            cc._rt_pre_wait = math.max(0, entry.offset + entry.pre - g_ts)
          end
          if delay < 0.001 then
            if skip_pre and cc.pre_wait > 0 then
              FUNC.exec_cue(entry.idx)  -- 直接執行跳過pre_wait -- skip pre_wait
            else
              preview(entry.idx, true)
            end
          else
            local child = cc  -- 記 cue 本身，不記列號 -- remember the cue itself, not its row
            local do_skip = skip_pre
            active_timers[#active_timers+1] = {
              t0 = FUNC.tnow(), dur = delay, ci = -1,
              tt = "group_child", cue_id = c.id,
              cb = function()
                local idx = FUNC.find_id(child.id); if not idx then return end
                if do_skip and child.pre_wait > 0 then
                  FUNC.exec_cue(idx)
                else
                  preview(idx, true)
                end
              end
            }
          end
          ::gtrim_skip::
        end
      end
    else
      -- 無GROUP trim：原始行為 -- no GROUP trim: original behavior
      for k,ch in ipairs(c.children or {}) do
        if ch>=1 and ch<=#cues then
          local cc = cues[ch]
          if k==1 or not cc.auto_go then preview(ch,true) end
        end
      end
    end
    -- GROUP route trim: 套用trim到children的hw send -- apply route trims to children hw sends
    FUNC.rt_apply_trims(c)
    _exec_group_stack[c.id] = nil
    c.state=STATE.DONE;FUNC.check_post(ci)
  elseif c.type=="MIDI" then
    -- Phase 5: sequence 且有 item → item-based 播放；message 或無 item → legacy 單一訊息
    -- sequence+item → item playback; message/no-item → legacy single-event
    -- 相容舊 mode="internal" 字串（若 migration 未跑到）-- backward compat for legacy mode string
    local is_internal = ((c.midi_device or -1) < 0) or c.midi_mode == "internal"
    if c.midi_mode == "sequence" and c.midi_item_guid and c.midi_item_guid ~= "" then
      -- ═══ Item-based 播放（Sequence）═══
      -- 鎖定播放當下 trim_start (midi_build_pending 會清除 _rt_*，要先抓) -- capture before build clears _rt
      local _midi_pofs = c._rt_trim_start or c.trim_start or 0
      local bundle = FUNC.midi_build_pending(c)
      local dur = bundle.dur_sec
      c.play_t0 = FUNC.tnow()
      c.play_offset = _midi_pofs
      c.total_dur = dur; c.eff_dur = dur
      c._midi_pending = bundle.events
      if is_internal then FUNC.env_save_track(c, true); FUNC.midi_arm_track(c) end
      if #bundle.events == 0 and dur <= 0 then
        if is_internal then FUNC.midi_unarm_track(c) end
        c.state = STATE.DONE; FUNC.check_post(ci)
      end
    elseif c.midi_mode == "message" then
      -- ═══ Message mode: 表格驅動，事件透過同一 pending queue 排程 ═══
      local bundle = FUNC.midi_build_pending_message(c)
      local dur = bundle.dur_sec
      c.play_t0 = FUNC.tnow()
      c.total_dur = dur; c.eff_dur = dur
      c._midi_pending = bundle.events
      if is_internal then FUNC.env_save_track(c, true); FUNC.midi_arm_track(c) end
      if #bundle.events == 0 and dur <= 0 then
        if is_internal then FUNC.midi_unarm_track(c) end
        c.state = STATE.DONE; FUNC.check_post(ci)
      end
    else
      -- ═══ Legacy 單音 fallback (sequence 但沒 item) ═══
      local ch = math.max(0, math.min(15, (c.midi_channel or 1) - 1))
      local mode_val = is_internal and 0 or (16 + c.midi_device)
      local note = c.midi_note or 60
      local vel = c.midi_velocity or 100
      local dur = c.midi_duration or 0.5
      reaper.StuffMIDIMessage(mode_val, 0x90 + ch, note, vel)
      c.play_t0 = reaper.time_precise()
      c.total_dur = dur; c.eff_dur = dur
      c._midi_off_mode = mode_val; c._midi_off_ch = ch; c._midi_off_note = note
    end
  end
end

function preview(ci,is_child)
  if ci<1 or ci>#cues then return end;local c=cues[ci]
  -- _rt_pre_wait: GROUP trim 落在 child pre 區段時的縮短覆寫，用完即清
  -- _rt_pre_wait: shrink override when GROUP trim cuts into child's pre region; consumed once
  local pw = c._rt_pre_wait or c.pre_wait or 0
  c._rt_pre_wait = nil
  if pw>0 then c.state=STATE.PREWAIT
    FUNC.ensure_global_lock()  -- pre-wait也lock track control
    -- 時間到時用 cue id 找回它現在在第幾列（等待期間列表可能被增刪）
    -- when the wait ends, find the cue's current row by id (the list may have changed meanwhile)
    FUNC.start_timer(pw,ci,TIMER.PRE,function() local i=FUNC.find_id(c.id);if i then FUNC.exec_cue(i) end end)
  else FUNC.exec_cue(ci) end
end

-- 連鎖：ci 的下一個非SPACER cue 若勾 Auto-go 就啟動它 -- chain: start the next non-spacer cue after ci if it has auto-go
local function follow(ci)
  local nci = ci + 1
  while nci <= #cues and cues[nci].type == "SPACER" do nci = nci + 1 end
  if nci<=#cues and cues[nci].auto_go then
    next_go=FUNC.skip_spacer(nci+1)
    preview(nci,false); return true
  end
  return false
end

function FUNC.check_post(ci)
  if ci<1 or ci>#cues then return end;local c=cues[ci]
  if c.post_wait>0 then c.state=STATE.POSTWAIT
    FUNC.ensure_global_lock()  -- post-wait也lock track control
    FUNC.start_timer(c.post_wait,ci,TIMER.POST,function() c.state=STATE.DONE
      local i=FUNC.find_id(c.id)  -- 等待期間列表可能變動，重新找列號 -- row may have changed during the wait
      if not (i and follow(i)) then FUNC.check_global_unlock() end end)
  else
    follow(ci)
  end
end

function FUNC.skip_spacer(idx, dir)
  dir = dir or 1
  while idx >= 1 and idx <= #cues and cues[idx].type == "SPACER" do idx = idx + dir end
  return FUNC.clamp(idx, 1, #cues)
end
function FUNC.go_next()
  next_go = FUNC.skip_spacer(math.min(#cues,math.max(1,next_go)))
  if next_go_hidden then return end  -- 隱藏中不執行，防連按 -- blocked while hidden (last cue playing)
  local fi=next_go
  preview(fi,false);FUNC.save_cues()
  -- GROUP走完後next_go跳到group外下一個cue -- skip group children for next_go
  local fc = cues[fi]
  local end_idx = fi  -- 計算走完後的位置 -- calculate position after go
  if fc and fc.type == "GROUP" and fc.children and #fc.children > 0 then
    local last_child = 0
    for _, ch in ipairs(fc.children) do if ch > last_child then last_child = ch end end
    if last_child > 0 and last_child < #cues then
      end_idx = FUNC.skip_spacer(last_child + 1)
    elseif fi < #cues then
      end_idx = FUNC.skip_spacer(fi + 1)
    else
      end_idx = fi  -- 已是最後 -- already at end
    end
  elseif fi < #cues then
    end_idx = FUNC.skip_spacer(fi + 1)
  end
  -- 到達最後一個cue時：留在原位但隱藏>>，防連按空白 -- at last cue: stay but hide cursor
  if fi >= #cues or end_idx > #cues then
    next_go_hidden = true  -- cleanup.lua會在cue結束時解除 -- cleanup.lua will unhide when cue finishes
  else
    next_go = end_idx
  end
  last_click = next_go;
  FUNC.sel1(next_go)
end

function FUNC.check_sel_fn()
  -- 有waveform選取範圍時，播放選取範圍而非完整cue -- play selection range if active
  if FUNC.wf_sel_active() then
    for i in pairs(selected) do
      if i>=1 and i<=#cues and cues[i].id == wf_sel.cid then
        FUNC.wf_sel_play(cues[i]); return
      end
    end
  end
  for i in pairs(selected) do if i>=1 and i<=#cues then preview(i,true) end end
end
function FUNC.hard_kill_cue(c)
  FUNC.cancel_fades_cue(c);FUNC.kill_cue(c);paused_cues[c.id]=nil;soft_kill[c.id]=nil
  FUNC.check_global_unlock()  -- pre/post wait被kill後檢查解鎖 -- check unlock after killing pre/post wait cue
end
function FUNC.soft_kill_cue(c)
  -- pre-wait/postwait中的cue沒有preview，直接hard kill -- cues in pre/post-wait have no previews, hard kill immediately
  if c.state == STATE.PREWAIT or c.state == STATE.POSTWAIT then FUNC.hard_kill_cue(c); return end
  local dur = prefs.soft_kill_time
  if dur <= 0 then FUNC.hard_kill_cue(c); return end
  if soft_kill[c.id] then FUNC.hard_kill_cue(c); return end
  -- Bug 2: MIDI cue 也支援 softkill：清 pending 不送新 note，讓已發出的 note 自然延音 dur 秒
  -- MIDI softkill: clear pending queue (no new notes) + schedule kill after dur (existing notes ring out)
  if c.type == "MIDI" and c.state == STATE.RUNNING then
    if c._midi_pending then c._midi_pending = {} end
    local sk = {t0 = reaper.time_precise(), dur = dur}
    soft_kill[c.id] = sk
    active_timers[#active_timers+1] = {
      t0 = reaper.time_precise(), dur = dur, ci = -1, tt = "softkill_finish",
      cb = function()
        -- Bug 3: 跨 session 守護 — 若 soft_kill[c.id] 已被 exec_cue 清掉或換新 session 就不誤殺
        if soft_kill[c.id] ~= sk then return end
        FUNC.kill_cue(c); paused_cues[c.id] = nil; soft_kill[c.id] = nil
      end
    }
    return
  end
  if not c.preview_ids or #c.preview_ids == 0 then FUNC.hard_kill_cue(c); return end
  FUNC.cancel_fades_cue(c)
  local sk = {t0 = reaper.time_precise(), dur = dur}
  soft_kill[c.id] = sk
  -- 對現有 pids 啟動 fade（無 cb）；wallclock timer 負責倒數結束時 kill_cue
  -- chained item 在 fade 期間自然播完不會中斷倒數，新 spawn 的 pid 由 do_play 補上 fade
  FUNC.start_fade_cue(c, prefs.inf_db, dur, "linear", nil)
  active_timers[#active_timers+1] = {
    t0 = reaper.time_precise(), dur = dur, ci = -1, tt = "softkill_finish",
    cb = function()
      -- Bug 3: 跨 session 守護 — 若 soft_kill[c.id] 已被 exec_cue 清掉或換新 session 就不誤殺
      if soft_kill[c.id] ~= sk then return end
      FUNC.kill_cue(c); paused_cues[c.id] = nil; soft_kill[c.id] = nil
    end
  }
end
-- 收集 GROUP 所有葉節點 (PLAY/MIDI/...)；遇到 nested GROUP 遞迴展開
-- 同時清掉以 GROUP id 標記的 pending timers (group_child / item)，避免 nested child 的 pre_wait 在 kill 後才被喚醒逃過 soft kill
-- collect leaf descendants + purge any pending timers tagged with each visited GROUP's id,
-- so nested children waiting on group_child preview() can't slip past the soft-kill window
function FUNC.collect_group_leaves(c, out, seen)
  out = out or {}; seen = seen or {}
  if seen[c.id] then return out end
  seen[c.id] = true
  FUNC.rt_restore_trims(c)
  -- 移除以本 group 為 cue_id 的 pending timers (group_child / item)
  local ti = 1
  while ti <= #active_timers do
    if active_timers[ti].cue_id == c.id then table.remove(active_timers, ti) else ti = ti + 1 end
  end
  -- nested GROUP 自身若處於 PREWAIT/POSTWAIT，TIMER.PRE/POST 是用 ci 標記，靠 kill_cue 順便清；
  -- 這裡直接 kill_cue 該 GROUP 自己（preview_ids 通常空，副作用就是清 ci-matched timers + state→IDLE）
  -- nested GROUP's own pre/post-wait timers are ci-tagged; kill_cue clears them via ci_idx match
  if c.state == STATE.PREWAIT or c.state == STATE.POSTWAIT or c.state == STATE.RUNNING then
    FUNC.cancel_fades_cue(c); FUNC.kill_cue(c)
    paused_cues[c.id] = nil; soft_kill[c.id] = nil
  end
  for _, ch in ipairs(c.children or {}) do
    if ch >= 1 and ch <= #cues then
      local cc = cues[ch]
      if cc.type == "GROUP" then
        FUNC.collect_group_leaves(cc, out, seen)
      else
        out[#out+1] = cc
      end
    end
  end
  return out
end

function FUNC.kill()
  for i in pairs(selected) do if i>=1 and i<=#cues then
    local c = cues[i]
    if c.type == "GROUP" then
      local leaves = FUNC.collect_group_leaves(c)  -- 內部已 rt_restore_trims + 清 pending timers
      -- Bug 1: GROUP 二次按 → 立即 hard cut 全部 children -- second press: hard cut
      if soft_kill[c.id] then
        soft_kill[c.id] = nil
        for _, cc in ipairs(leaves) do FUNC.hard_kill_cue(cc) end
      else
        local dur = prefs.soft_kill_time
        if dur > 0 then
          local any_child_running = false
          for _, cc in ipairs(leaves) do
            if (cc.preview_ids and #cc.preview_ids > 0) or (cc.type=="MIDI" and cc.state==STATE.RUNNING) then
              any_child_running = true; break
            end
          end
          if any_child_running then
            local sk = {t0 = reaper.time_precise(), dur = dur}
            soft_kill[c.id] = sk
            active_timers[#active_timers+1] = {
              t0 = reaper.time_precise(), dur = dur, ci = -1, tt = "softkill_finish",
              cb = function() if soft_kill[c.id] == sk then soft_kill[c.id] = nil end end
            }
          end
        end
        for _, cc in ipairs(leaves) do FUNC.soft_kill_cue(cc) end
      end
    else
      FUNC.soft_kill_cue(c)
    end
  end end
end
-- 立刻全部停止並還原：聲音、計時器、淡出、暫停、MIDI 音符/錄音預備、軌道狀態。可重複呼叫。
-- stop and restore everything right now: sound, timers, fades, pauses, MIDI notes/record-arm, track state. Safe to call repeatedly.
function FUNC.hard_stop_all()
  soft_kill={};active_fades={};active_timers={};paused_cues={};cancelled_fades={}
  if FUNC.wf_sel_stop then FUNC.wf_sel_stop() end  -- 波形選取試聽 -- waveform range audition
  FUNC.pv_stop_all()
  for _,c in ipairs(cues) do
    if FUNC.midi_stop_cue then FUNC.midi_stop_cue(c) else FUNC.midi_note_off(c) end
    c.state=STATE.IDLE;c.preview_ids={};c.play_t0=0
    c.loop_go_fired=nil;c.loop_done=nil
  end
  -- 已不在列表裡的 MIDI cue 留下的錄音預備備份也要還原 -- arm backups left by MIDI cues no longer in the list
  if _midi_arm_backup and FUNC.midi_unarm_track then
    for id in pairs(_midi_arm_backup) do FUNC.midi_unarm_track({id=id,track_guid=""}) end
  end
  FUNC.env_restore_all()  -- 還原所有軌道+解鎖 -- restore all tracks + unlock
  next_go_hidden=false  -- panic解除隱藏 -- unhide on panic
end
-- 關視窗 / 結束 / 出錯時的收尾。每一步各自保護，前一步失敗不影響下一步。
-- used when the window closes / script ends / after an error. Each step is protected so one failure doesn't block the next.
function FUNC.shutdown_safe()
  pcall(FUNC.hard_stop_all)
  pcall(function() if FUNC.afx_restore then FUNC.afx_restore() end end)
end

function FUNC.panic()
  local has_soft = false
  for _ in pairs(soft_kill) do has_soft = true; break end
  local dur = prefs.soft_kill_time
  if has_soft or dur <= 0 then FUNC.hard_stop_all(); return end
  -- soft panic前先還原所有GROUP route trims -- restore all GROUP trims before soft panic
  for _,c in ipairs(cues) do if c._rt_hw_saved then FUNC.rt_restore_trims(c) end end
  -- Bug 1: 給有 children 正在跑的 GROUP 也加 soft_kill 旗標 (UI 進度條)
  -- mark GROUPs that have any running child so the group title row also shows a softkill bar
  for _, c in ipairs(cues) do
    if c.type == "GROUP" and c.children and #c.children > 0 and not soft_kill[c.id] then
      local any = false
      for _, ch in ipairs(c.children) do
        local cc = cues[ch]
        if cc and ((cc.preview_ids and #cc.preview_ids > 0) or (cc.type=="MIDI" and cc.state==STATE.RUNNING)) then
          any = true; break
        end
      end
      if any then
        local sk = {t0 = reaper.time_precise(), dur = dur}
        soft_kill[c.id] = sk
        active_timers[#active_timers+1] = {
          t0 = reaper.time_precise(), dur = dur, ci = -1, tt = "softkill_finish",
          cb = function() if soft_kill[c.id] == sk then soft_kill[c.id] = nil end end
        }
      end
    end
  end
  for _,c in ipairs(cues) do
    if c.state == STATE.PREWAIT or c.state == STATE.POSTWAIT or (c.type == "FADE" and c.state == STATE.RUNNING) then
      -- 取消正在走的pre-wait/post-wait計時器；進行中的 FADE cue 也直接結束（不再連鎖）
      -- cancel pending pre/post-wait timers; a running FADE cue ends here too (no more chaining)
      FUNC.kill_cue(c)
    elseif c.preview_ids and #c.preview_ids > 0 and (c.state==STATE.RUNNING or c.state==STATE.DONE) then
      FUNC.cancel_fades_cue(c)
      local sk = {t0 = reaper.time_precise(), dur = dur}
      soft_kill[c.id] = sk
      FUNC.start_fade_cue(c, prefs.inf_db, dur, "linear", nil)
      active_timers[#active_timers+1] = {
        t0 = reaper.time_precise(), dur = dur, ci = -1, tt = "softkill_finish",
        cb = function()
          if soft_kill[c.id] ~= sk then return end
          FUNC.kill_cue(c); paused_cues[c.id] = nil; soft_kill[c.id] = nil
        end
      }
    elseif c.type == "MIDI" and c.state == STATE.RUNNING then
      -- Bug 2: MIDI cue softkill — 清 pending 不送新 note，已發出的 note 自然延音
      if c._midi_pending then c._midi_pending = {} end
      local sk = {t0 = reaper.time_precise(), dur = dur}
      soft_kill[c.id] = sk
      active_timers[#active_timers+1] = {
        t0 = reaper.time_precise(), dur = dur, ci = -1, tt = "softkill_finish",
        cb = function()
          if soft_kill[c.id] ~= sk then return end
          FUNC.kill_cue(c); paused_cues[c.id] = nil; soft_kill[c.id] = nil
        end
      }
    end
  end
end
function FUNC.reset_show() FUNC.panic();next_go=(#cues>0) and 1 or 0;FUNC.sel1(next_go);FUNC.save_cues() end

---------------------------------------------------------------------
-- 10. CUE LIST MGMT
---------------------------------------------------------------------
-- Re# button用：全部重新排號 -- full sequential renumber (for Re# button only)
function FUNC.renumber() local n=0;for _,q in ipairs(cues) do if q.type~="SPACER" then n=n+1;q.cue_number=tostring(n) else q.cue_number="" end end end

-- 智慧分配Q number：根據前後鄰居的number插入合適數字 -- smart Q number assignment based on neighbors
function FUNC.assign_number(ins_idx)
  if cues[ins_idx] and cues[ins_idx].type == "SPACER" then cues[ins_idx].cue_number = ""; return end
  -- 去掉尾部撇號解析數字 -- strip trailing apostrophes for parsing
  local function parse_num(s)
    if not s or s == "" then return nil end
    return tonumber((s:gsub("'+$", "")))
  end
  -- 格式化數字：去掉不必要的尾部零 -- format number: trim trailing zeros
  local function fmt_num(n)
    local s = string.format("%.10f", n)
    s = s:gsub("0+$", ""):gsub("%.$", "")
    return s
  end
  -- 計算小數位數(層級) -- count decimal places (level)
  local function get_level(n)
    local s = fmt_num(n)
    local _, dot = s:find("%.")
    if not dot then return 0 end
    return #s - dot
  end
  -- 找前後非SPACER鄰居 -- find prev/next non-spacer neighbors
  local a, b = nil, nil
  for i = ins_idx - 1, 1, -1 do
    if cues[i] and cues[i].type ~= "SPACER" then a = parse_num(cues[i].cue_number); break end
  end
  for i = ins_idx + 1, #cues do
    if cues[i] and cues[i].type ~= "SPACER" then b = parse_num(cues[i].cue_number); break end
  end
  -- 邊界情況 -- edge cases
  if not a and not b then cues[ins_idx].cue_number = "1"; return end
  if not a then cues[ins_idx].cue_number = fmt_num(math.max(1, (b or 1) - 1)); return end
  if not b then cues[ins_idx].cue_number = fmt_num(math.floor(a) + 1); return end
  -- 分配邏輯 -- assignment logic
  local result
  local a_lv, b_lv = get_level(a), get_level(b)
  if a >= b then
    -- rule4: a>b(亂序)→a的下一層級+1 -- out of order: sublevel +1
    result = a + 10^(-(a_lv + 1))
  elseif a_lv == b_lv then
    local unit = 10^(-a_lv)
    local next_v = a + unit
    -- 檢查next_v是否已被使用 -- check if next_v is already taken
    local next_str = fmt_num(next_v)
    local next_used = false
    for _, q in ipairs(cues) do
      if q.cue_number and q.cue_number:gsub("'+$", "") == next_str then next_used = true; break end
    end
    if next_v < b - 1e-9 and not next_used then
      result = next_v  -- rule1: 離a最近的下一單位 -- next unit after a
    else
      result = (a + b) / 2  -- rule2: 中間值 -- midpoint
    end
  else
    -- rule3: 不同層級→較精細層級+1 -- different levels: add 1 unit of finer level
    local finer = math.max(a_lv, b_lv)
    result = a + 10^(-finer)
  end
  local result_str = fmt_num(result)
  -- rule5: 碰撞→加撇號 -- collision: append apostrophe
  for _, q in ipairs(cues) do
    if q ~= cues[ins_idx] and q.cue_number == result_str then
      result_str = result_str .. "'"; break
    end
  end
  cues[ins_idx].cue_number = result_str
end

function FUNC.smart_target(new_type, ref_ci)
  if ref_ci<1 or ref_ci>#cues then return "" end
  local ref=cues[ref_ci]
  if new_type=="STOP" then
    if ref.type=="PLAY" or ref.type=="GROUP" then return ref.id
    elseif ref.type=="PAUSE" then return ref.target_cue_id or ""
    elseif ref.type=="FADE" then return ref.target_cue_id or ""
    elseif ref.type=="STOP" then return ref.target_cue_id or ""
    else return "" end
  elseif new_type=="PAUSE" then
    if ref.type=="PLAY" or ref.type=="GROUP" then return ref.id
    elseif ref.type=="PAUSE" then return ref.target_cue_id or ""
    else return "" end
  elseif new_type=="FADE" then
    if ref.type=="PLAY" or ref.type=="GROUP" then return ref.id
    elseif ref.type=="FADE" then return ref.target_cue_id or ""
    else return "" end
  end
  return ""
end

function FUNC.im2cue(col)
  return (((col>>24)&0xFF)<<16) | (((col>>16)&0xFF)<<8) | ((col>>8)&0xFF)
end

-- 解析 cue 的有效顏色（含 group 繼承鏈）→ 0xRRGGBB 或 nil(無色)
-- resolve effective cue_color via group inheritance chain; returns 0xRRGGBB or nil
function FUNC.resolve_eff_cue_color(c)
  if not c then return nil end
  if c.cue_color and c.cue_color > 0 then return c.cue_color end
  if c.cue_color == 0 then return nil end  -- 明確 none
  local gid = c.group_id
  while gid do
    local _, gc = FUNC.find_id(gid)
    if not gc then break end
    if gc.cue_color and gc.cue_color > 0 then return gc.cue_color end
    if gc.cue_color == 0 then return nil end
    gid = gc.group_id
  end
  return nil
end

-- 同步 cue color 到 REAPER track（PLAY）或 MIDI item（MIDI），需 prefs.track_color_follow=1
-- sync cue color to REAPER track (PLAY) or MIDI item (MIDI) when pref enabled
-- override_native：強制寫入指定 native 色（用於 disable 時清回 default 0）；nil = 用 cue 解析色
-- override_native: force a specific native color (used for restore-on-disable); nil = use resolved cue color
function FUNC.sync_cue_color_to_reaper(c, force, override_native)
  if not c then return false end
  if c.type ~= "PLAY" and c.type ~= "MIDI" then return false end
  local eff = FUNC.resolve_eff_cue_color(c)
  local target_key = override_native ~= nil and ("ovr:"..override_native) or (eff or 0)
  if not force and c._last_synced_color == target_key then return false end
  local native
  if override_native ~= nil then
    native = override_native
  else
    native = 0
    if eff then
      local r = (eff>>16)&0xFF; local g = (eff>>8)&0xFF; local b = eff&0xFF
      native = reaper.ColorToNative(r,g,b) | 0x01000000
    end
  end
  local wrote_item = false
  if c.type == "PLAY" then
    local tr = c.track_guid and c.track_guid ~= "" and reaper.BR_GetMediaTrackByGUID(0, c.track_guid)
    if tr then reaper.SetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR", native) end
  else  -- MIDI
    if c.midi_item_guid and c.midi_item_guid ~= "" then
      local item = reaper.BR_GetMediaItemByGUID(0, c.midi_item_guid)
      if item then reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", native); wrote_item = true end
    end
  end
  c._last_synced_color = target_key
  return wrote_item
end

function FUNC.sync_all_cue_colors(force)
  if prefs.track_color_follow ~= 1 then return end
  local any_item = false
  for _, c in ipairs(cues) do
    if FUNC.sync_cue_color_to_reaper(c, force) then any_item = true end
  end
  if any_item then reaper.UpdateArrange() end
end

-- 將所有 cue 的 track / MIDI item 色清回 default(0)，用於關閉 follow 時還原
-- clear track / MIDI item color back to default; used when follow pref turned off
function FUNC.clear_all_cue_colors_in_reaper()
  local any_item = false
  for _, c in ipairs(cues) do
    if FUNC.sync_cue_color_to_reaper(c, true, 0) then any_item = true end
  end
  if any_item then reaper.UpdateArrange() end
end

function FUNC.add_cue(tp,after,mode)
  FUNC.push_undo()  -- 明確 push，不依賴 save_cues 內隱式 push
  local ins=(after and after>0 and after<=#cues) and after+1 or #cues+1
  if tp=="PLAY" then
    local trs=FUNC.sel_trs()
    if #trs>1 then
      -- 多track PLAY：在group內新增時自動繼承group_id（收合時放group下方）
      -- auto-inherit group for multi-track PLAY (collapsed → place below group)
      local parent_gid = nil
      if after and after >= 1 and after <= #cues then
        local ref = cues[after]
        if ref and ref.type == "GROUP" and not collapsed_groups[ref.id] then parent_gid = ref.id
        elseif ref and ref.group_id and not collapsed_groups[ref.group_id] then parent_gid = ref.group_id end
      end
      selected={}
      for k,ti in ipairs(trs) do
        local c=FUNC.mk_cue("PLAY");c.track_idx=ti;c.track_guid=FUNC.tr_guid(ti)  -- GUID
        local nm=FUNC.tr_name(ti);c.name=(nm~="?") and nm or ""
        if parent_gid then c.group_id = parent_gid; c.cue_color = CUE_COLOR_INHERIT end  -- 繼承group
        table.insert(cues,ins+k-1,c)
        selected[ins+k-1]=true
      end
      FUNC.rebuild_groups()  -- 無條件重建：插入後既有 GROUP 的 children index 都偏移了 -- always rebuild: insert shifts existing GROUP child indices
      -- 逐個分配Q number（不全部重排）-- assign numbers individually (no full renumber)
      for k = 1, #trs do FUNC.assign_number(ins + k - 1) end
      next_go=ins;last_click=ins;FUNC.save_cues();return
    end
  end

  if (tp=="STOP" or tp=="FADE" or tp=="PAUSE") then
    local sl = FUNC.sel_list()
    local targets = {}
    for _, si in ipairs(sl) do
      local sc = cues[si]
      if sc and (sc.type=="PLAY" or sc.type=="GROUP") then
        targets[#targets+1] = sc
      end
    end
    if #targets >= 2 then
      -- 多選建GROUP：不連續選取時插在next_go下方，連續時在最後選取後 -- non-contiguous: insert at next_go
      local is_contiguous = true
      for k = 2, #sl do
        if sl[k] ~= sl[k-1] + 1 then is_contiguous = false; break end
      end
      if not is_contiguous and next_go > 0 then
        ins = next_go + 1
      else
        local last_sel = sl[#sl]
        ins = (last_sel and last_sel > 0 and last_sel <= #cues) and last_sel + 1 or #cues + 1
      end
      local gc = FUNC.mk_cue("GROUP")
      local type_names = {STOP="Stop", FADE="Fade", PAUSE="Pause"}
      gc.name = (type_names[tp] or tp) .. " Group"
      gc.cue_color = FUNC.im2cue(TYPE_COL[tp] or 0)
      table.insert(cues, ins, gc)
      for k, tgt in ipairs(targets) do
        local ac = FUNC.mk_cue(tp)
        ac.target_cue_id = tgt.id
        ac.name = tgt.name
        if tp == "FADE" then ac.volume = prefs.vol_min; ac.fade_time = 3.0 end
        ac.group_id = gc.id
        table.insert(cues, ins + k, ac)
        gc.children[#gc.children+1] = ins + k
      end
      collapsed_groups[gc.id] = true
      FUNC.rebuild_groups()
      -- 逐個分配Q number -- assign numbers individually
      for k = 0, #targets do FUNC.assign_number(ins + k) end
      FUNC.sel1(ins); next_go=ins; last_click=ins; FUNC.save_cues()
      return
    end
  end

  -- 多選 track + MIDI selected：每個 track 各建一個 MIDI cue（仿 PLAY 多軌邏輯）
  -- multi-track + MIDI selected: one MIDI cue per selected track (mirrors PLAY multi-track)
  if tp == "MIDI" and (mode or "new") == "selected" then
    local trs = FUNC.sel_trs()
    if #trs > 1 then
      local parent_gid = nil
      if after and after >= 1 and after <= #cues then
        local ref = cues[after]
        if ref and ref.type == "GROUP" and not collapsed_groups[ref.id] then parent_gid = ref.id
        elseif ref and ref.group_id and not collapsed_groups[ref.group_id] then parent_gid = ref.group_id end
      end
      selected = {}
      for k, ti in ipairs(trs) do
        local tr_k = reaper.GetTrack(0, ti)
        local c = FUNC.mk_cue("MIDI")
        c.track_idx = ti; c.track_guid = FUNC.tr_guid(ti)
        local nm = FUNC.tr_name(ti); c.name = (nm ~= "?" and nm ~= "") and nm or "MIDI"
        if parent_gid then c.group_id = parent_gid; c.cue_color = CUE_COLOR_INHERIT end
        -- 沿用 selected 模式：找既有 MIDI item 重用，否則建空 item -- reuse existing MIDI item or create blank
        local reused = false
        if tr_k then
          local n_items = reaper.CountTrackMediaItems(tr_k)
          for i = 0, n_items - 1 do
            local it = reaper.GetTrackMediaItem(tr_k, i)
            local tk = it and reaper.GetActiveTake(it)
            if tk and reaper.TakeIsMIDI(tk) then
              local _, gid = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
              if gid and gid ~= "" then
                FUNC.midi_assign_unique_guid(c, gid)
                reused = true; break
              end
            end
          end
          if not reused then c.midi_item_guid = FUNC.midi_create_blank_item(tr_k, 2.0) end
        end
        table.insert(cues, ins + k - 1, c)
        selected[ins + k - 1] = true
      end
      FUNC.rebuild_groups()  -- 無條件重建（同上）-- always rebuild (same reason)
      for k = 1, #trs do FUNC.assign_number(ins + k - 1) end
      next_go = ins; last_click = ins; FUNC.save_cues(); return
    end
  end

  local c=FUNC.mk_cue(tp)
  if tp=="MIDI" then
    local tr, tr_n
    local m = mode or "new"
    if m == "selected" then
      -- 用第一個選中的 track，找不到就退回新 track -- first selected track, fallback to new
      local trs = FUNC.sel_trs()
      if #trs > 0 then
        tr_n = trs[1]
        tr = reaper.GetTrack(0, tr_n)
      end
    end
    if not tr then
      -- 建立專屬 track + 空 MIDI item -- create dedicated track + blank MIDI item
      tr_n = reaper.CountTracks(0)
      reaper.InsertTrackAtIndex(tr_n, true)
      tr = reaper.GetTrack(0, tr_n)
      if tr then
        local track_nm = "MIDI " .. tostring(#cues + 1)
        reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", track_nm, true)
        -- track 顏色套 MIDI cue 色 -- apply MIDI color
        local midi_col_imgui = TYPE_COL and TYPE_COL.MIDI or 0
        -- ImGui u32 = 0xAABBGGRR; REAPER native = 0x01RRGGBB (with 0x01000000 flag)
        local r = (midi_col_imgui) & 0xFF
        local g = (midi_col_imgui >> 8) & 0xFF
        local b = (midi_col_imgui >> 16) & 0xFF
        local native_col = (r << 16) | (g << 8) | b | 0x01000000
        reaper.SetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR", native_col)
        c.track_guid = FUNC.tr_guid(tr_n)
        -- 註冊為 Realive 建立的 track，undo 時可清掉孤兒 -- register so undo can delete orphan
        if c.track_guid and c.track_guid ~= "" then _realive_tracks[c.track_guid] = true end
      end
    else
      c.track_guid = FUNC.tr_guid(tr_n)
      -- 用既有 track 不註冊 _realive_tracks（避免 undo 誤刪用戶 track）
      -- existing track: don't register, so undo won't delete user's track
    end
    if tr then
      c.track_idx = tr_n
      -- selected 模式：track 上已有 MIDI item 就直接用第一個；沒 item 才新建
      -- new 模式：永遠新建 -- new mode always creates blank item
      local reused = false
      if m == "selected" then
        local n_items = reaper.CountTrackMediaItems(tr)
        for i = 0, n_items - 1 do
          local it = reaper.GetTrackMediaItem(tr, i)
          local tk = it and reaper.GetActiveTake(it)
          if tk and reaper.TakeIsMIDI(tk) then
            local _, gid = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
            if gid and gid ~= "" then
              FUNC.midi_assign_unique_guid(c, gid)  -- 若已被其他 cue 占用會自動複製
              reused = true; break
            end
          end
        end
      end
      if not reused then
        -- 建立 2 秒空 MIDI item -- create blank 2-sec MIDI item
        c.midi_item_guid = FUNC.midi_create_blank_item(tr, 2.0)
      end
      local nm = FUNC.tr_name(tr_n)
      c.name = (nm ~= "?" and nm ~= "") and nm or "MIDI"
    else
      c.name = "MIDI"
    end
  end
  if tp~="PLAY" and tp~="GROUP" and tp~="SPACER" and tp~="MIDI" and after and after>=1 and after<=#cues then
    c.target_cue_id=FUNC.smart_target(tp,after)
    if c.target_cue_id ~= "" then
      local _,tc = FUNC.find_id(c.target_cue_id)
      if tc and tc.name ~= "" then c.name = tc.name end
      -- FADE建立時複製target的參數，避免無意間產生漸變 -- copy target params so fade starts at current values
      if tp == "FADE" and tc then
        c.volume = tc.volume or 0
        c.fade_pitch = tc.pitch or 0
        c.fade_pan = tc.pan or 0
      end
    end
    -- STOP/FADE/PAUSE插入位置：對GROUP標題→group底部，對child→該child下方 -- insertion: group title→bottom, child→right below
    local ref = cues[after]
    if ref then
      if ref.type == "GROUP" then
        -- 選中的是GROUP標題：插在group最後一個child之後 -- targeting GROUP title: insert after last child
        local last_ch = after
        for i, q in ipairs(cues) do
          if q.group_id == ref.id and i > last_ch then last_ch = i end
        end
        ins = last_ch + 1
      elseif ref.group_id then
        -- 選中的是group內的child：直接插在該child下方 -- targeting child in group: insert right below it
        ins = after + 1
      end
    end
  end
  -- 在group內新增cue時自動繼承group_id和顏色（收合時放group下方）
  -- auto-inherit group when adding cue inside a group (collapsed → place below)
  -- STOP/PAUSE/FADE選中GROUP標題時不進group，放在group下方 -- STOP/PAUSE/FADE on GROUP title: place below, not inside
  if tp ~= "GROUP" and tp ~= "SPACER" and after and after >= 1 and after <= #cues then
    local ref = cues[after]
    if ref then
      local is_action = (tp == "STOP" or tp == "PAUSE" or tp == "FADE")
      if is_action and ref.type == "GROUP" then
        -- 不繼承group，已在上方設好ins在group最後child之後 -- skip group inheritance
      elseif ref.type == "GROUP" and not collapsed_groups[ref.id] then
        c.group_id = ref.id; c.cue_color = CUE_COLOR_INHERIT  -- 繼承group顏色 -- inherit group color
      elseif ref.group_id and not collapsed_groups[ref.group_id] then
        c.group_id = ref.group_id; c.cue_color = CUE_COLOR_INHERIT
      end
    end
  end
  -- collapsed GROUP 標題/成員：把 ins 移到整個 group 下方（跳過所有 children）
  -- if ref is a collapsed group (title or member), place new cue below the whole group
  if after and after >= 1 and after <= #cues then
    local ref = cues[after]
    local coll_gid = nil
    if ref then
      if ref.type == "GROUP" and collapsed_groups[ref.id] then coll_gid = ref.id
      elseif ref.group_id and collapsed_groups[ref.group_id] then coll_gid = ref.group_id end
    end
    if coll_gid then
      local last_idx = after
      for i, q in ipairs(cues) do
        if (q.group_id == coll_gid) or (q.type == "GROUP" and q.id == coll_gid) then
          if i > last_idx then last_idx = i end
        end
      end
      ins = last_idx + 1
      -- 跳到 group 下方就不應再繼承 group_id -- no group inheritance when placed outside
      c.group_id = nil
    end
  end
  table.insert(cues,ins,c);
  FUNC.rebuild_groups()  -- 無條件重建：就算新 cue 不在 group 內，插入也會讓上方/下方既有 GROUP 的 children index 偏移 -- always rebuild: insertion shifts indices of existing GROUPs even if new cue is top-level
  FUNC.assign_number(ins)  -- 智慧分配Q number -- smart assign Q number
  FUNC.sel1(ins);next_go=ins;last_click=ins;FUNC.save_cues() end

function FUNC.file_add_play(after, files_arg)
  -- 若提供 files_arg（如拖曳進來），直接用該清單；否則開啟對話框 -- accept pre-supplied list (e.g. drag-drop) or open dialog
  FUNC.push_undo()
  local files = {}
  local is_win = reaper.GetOS():match("Win") ~= nil
  local path_sep = is_win and "\\" or "/"
  if files_arg and #files_arg > 0 then
    for _, f in ipairs(files_arg) do if f and f ~= "" then files[#files+1] = f end end
    if #files == 0 then return end
  else
    local has_js = reaper.JS_Dialog_BrowseForOpenFiles ~= nil
    if has_js then
      local rv, fnames = reaper.JS_Dialog_BrowseForOpenFiles("Select Audio File(s)", "", "",
        "Audio Files\0*.wav;*.aif;*.aiff;*.mp3;*.ogg;*.flac;*.m4a;*.wma;*.opus;*.mp4;*.mid\0All Files\0*.*\0", true)
      if rv ~= 1 or not fnames or fnames == "" then return end
      local parts = {}; for p in fnames:gmatch("[^\0]+") do parts[#parts+1] = p end
      if #parts == 1 then
        files[1] = parts[1]  -- 單選：完整路徑 -- single select: full path
      elseif is_win then
        -- Windows多選：folder\0file1\0file2... -- Windows multi: folder + relative filenames
        local folder = parts[1]
        if not folder:match("[\\/]$") then folder = folder .. path_sep end
        for i = 2, #parts do files[#files+1] = folder .. parts[i] end
      else
        -- macOS/Linux多選：每個part都是完整路徑 -- macOS/Linux multi: each part is a full path
        for i = 1, #parts do files[#files+1] = parts[i] end
      end
    else
      local ret, file = reaper.GetUserFileNameForRead("", "Select Audio File", "")
      if not ret or file == "" then return end
      files[1] = file
    end
  end
  -- 依序為每個檔案建立track+cue -- create track+cue for each file
  local first_ins = nil
  for fi, file in ipairs(files) do
    local tc = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(tc, true)
    local new_tr = reaper.GetTrack(0, tc)
    if new_tr then
      reaper.SetOnlyTrackSelected(new_tr)
      reaper.SetEditCurPos(0, false, false)
      reaper.InsertMedia(file, 0)
      local fname = file:match("([^/\\]+)$") or file
      fname = fname:match("(.+)%..+$") or fname
      reaper.GetSetMediaTrackInfo_String(new_tr, "P_NAME", fname, true)
      local ins = (after and after > 0 and after <= #cues) and after + fi or #cues + 1
      local c = FUNC.mk_cue("PLAY"); c.track_idx = tc; c.track_guid = FUNC.tr_guid(tc); c.name = fname
      -- 註冊 Realive 建立的 track，undo 時可清孤兒 -- register so undo can delete orphan
      if c.track_guid and c.track_guid ~= "" then _realive_tracks[c.track_guid] = true end
      -- 在group內新增file時自動繼承group_id和顏色 -- auto-inherit group for file_add_play
      if after and after >= 1 and after <= #cues then
        local ref = cues[after]
        if ref then
          if ref.type == "GROUP" then c.group_id = ref.id; c.cue_color = CUE_COLOR_INHERIT
          elseif ref.group_id then c.group_id = ref.group_id; c.cue_color = CUE_COLOR_INHERIT end
        end
      end
      table.insert(cues, ins, c)
      if not first_ins then first_ins = ins end
    end
  end
  if not first_ins then return end
  FUNC.rebuild_groups()  -- 無條件重建（同 add_cue）-- always rebuild (same as add_cue)
  FUNC.assign_number(first_ins); FUNC.sel1(first_ins); next_go = first_ins; last_click = first_ins; FUNC.save_cues()
end

-- 拖曳檔案進 Realive：cue_child 區域作為 drop target -- file drop target on cue table
function FUNC.handle_file_drop()
  if not ImGui.BeginDragDropTarget then return end
  if not ImGui.BeginDragDropTarget(ctx) then return end
  local rv, count = ImGui.AcceptDragDropPayloadFiles(ctx)
  if rv and count and count > 0 then
    local files = {}
    for i = 0, count - 1 do
      local ok, fn = ImGui.GetDragDropPayloadFile(ctx, i)
      if ok and fn and fn ~= "" then files[#files+1] = fn end
    end
    if #files > 0 then
      local after = FUNC.sel_first(); if after < 1 then after = #cues end
      FUNC.file_add_play(after, files)
    end
  end
  ImGui.EndDragDropTarget(ctx)
end

-- 刪單一列：和「刪選取」走同一條路（含巢狀群組的子孫）-- delete one row: same path as delete-selection (incl. nested group descendants)
function FUNC.remove_cue(idx) if idx<1 or idx>#cues then return end
  selected={[idx]=true}; FUNC.remove_selected() end

function FUNC.remove_selected()
  local sl=FUNC.sel_list(); if #sl==0 then return end
  FUNC.push_undo()
  local rm_ids={}
  local to_rm={}
  for _,i in ipairs(sl) do
    to_rm[i]=true
    local c=cues[i]
    if c and c.type=="GROUP" then rm_ids[c.id]=true end
  end
  -- 巢狀群組：一路往下把子孫都標記（重複掃到沒有新增為止）-- nested groups: keep marking descendants until nothing new is added
  local grew = true
  while grew do grew = false
    for i,q in ipairs(cues) do
      if not to_rm[i] and q.group_id and rm_ids[q.group_id] then
        to_rm[i]=true; grew=true
        if q.type=="GROUP" then rm_ids[q.id]=true end
      end
    end
  end
  -- 刪除前先kill播放中的cue（還原track state+routing） -- kill playing cues before removal
  for i,q in ipairs(cues) do
    if to_rm[i] then
      if q.state ~= STATE.IDLE or (q.preview_ids and #q.preview_ids > 0) then FUNC.hard_kill_cue(q) end
      if FUNC.wf_release then FUNC.wf_release(q.id) end
    end
  end
  -- 收集被刪cue的track guid -- collect track guids of removed cues
  local rm_guids = {}
  for i,q in ipairs(cues) do
    if to_rm[i] and q.track_guid and q.track_guid~="" then rm_guids[q.track_guid]=true end
  end
  local first=sl[1]
  local new={};for i,q in ipairs(cues) do if not to_rm[i] then new[#new+1]=q end end
  cues=new; selected={}  -- 刪除不重排number -- delete doesn't renumber
  FUNC.check_delete_tracks(rm_guids)  -- 刪除孤兒copied track
  FUNC.rebuild_groups()  -- 刪除後index偏移，重建children -- rebuild children after index shift
  if #cues>0 then local n=math.min(first,#cues);FUNC.sel1(n);next_go=n else next_go=0 end
  FUNC.save_cues()
end
function FUNC.move_cue(from,to)
  if from<1 or from>#cues or to<1 or to>#cues or from==to then return end
  FUNC.push_undo()
  local c=table.remove(cues,from);table.insert(cues,to,c);FUNC.sel1(to);FUNC.save_cues() end  -- 拖曳不重排number

local _grp_cc_idx = 0
function FUNC.get_grp_cc_idx() return _grp_cc_idx end
function FUNC.set_grp_cc_idx(v) _grp_cc_idx = v end

-- 預檢查：把目前選取群組起來會不會爆 depth（給 UI 用） -- check if grouping selection would exceed max depth
function FUNC.group_sel_would_exceed()
  local sl=FUNC.sel_list();if #sl<2 then return false end
  local max_d = 0
  for _,i in ipairs(sl) do
    local d = FUNC.cue_depth(cues[i])
    if cues[i].type == "GROUP" then
      for _,cc in ipairs(cues[i].children or {}) do
        d = math.max(d, FUNC.cue_depth(cues[cc] or cues[i]))
      end
    end
    if d > max_d then max_d = d end
  end
  return max_d + 1 > MAX_GROUP_DEPTH
end

-- 從 children name 推導 group title：找最長共同前綴（trim 尾端空白/標點/數字），
-- 若 < 2 字元則 fallback 到第一個 child name。 -- derive group title from children
-- 拆 UTF-8 字元為 array（避免 byte-level 切到字元中間）-- split UTF-8 into chars
local function _utf8_chars(s)
  local t = {}
  for _, cp in utf8.codes(s) do t[#t+1] = utf8.char(cp) end
  return t
end
local function _derive_group_title(picked)
  if not picked or #picked == 0 then return "Group" end
  local first_name = picked[1].name or ""
  if #picked == 1 then return first_name ~= "" and first_name or "Group" end
  local ok, pref_chars = pcall(_utf8_chars, first_name)
  if not ok then pref_chars = {} end
  for k = 2, #picked do
    local ok2, n_chars = pcall(_utf8_chars, picked[k].name or "")
    if not ok2 then n_chars = {} end
    local m = math.min(#pref_chars, #n_chars)
    local i = 0
    while i < m and pref_chars[i+1] == n_chars[i+1] do i = i + 1 end
    for j = #pref_chars, i+1, -1 do pref_chars[j] = nil end
    if #pref_chars == 0 then break end
  end
  local pref = table.concat(pref_chars)
  -- 修剪尾端空白、標點（保留數字／字母；UTF-8 已對齊到字元邊界）-- trim trailing ASCII spaces/punct only
  pref = pref:gsub("[%s%p]+$", "")
  local pref_len = utf8.len(pref) or 0
  if pref_len >= 2 then return pref end
  return first_name ~= "" and first_name or "Group"
end

function FUNC.group_sel()
  local sl=FUNC.sel_list();if #sl<2 then return end
  if FUNC.group_sel_would_exceed() then FUNC.warn_max_depth(); return end
  FUNC.push_undo()
  -- 收集選取的cue物件，從後往前移除 -- collect selected cues, remove from back to front
  local picked = {}
  for _,i in ipairs(sl) do picked[#picked+1] = cues[i] end
  local ins_pos = sl[1]  -- 記住第一個選取的位置 -- remember first selected position
  for i = #sl, 1, -1 do table.remove(cues, sl[i]) end
  -- 插入GROUP到原始第一個位置(可能因移除而shift) -- insert GROUP at adjusted position
  if ins_pos > #cues + 1 then ins_pos = #cues + 1 end
  local gc=FUNC.mk_cue("GROUP");gc.name=_derive_group_title(picked);gc.children={}
  _grp_cc_idx = _grp_cc_idx + 1
  gc.cue_color = CUE_COLORS[((_grp_cc_idx - 1) % #CUE_COLORS) + 1].val
  -- 巢狀GROUP繼承parent：如果所有picked cues有相同group_id，新GROUP也歸屬該parent -- nested GROUP inherits common parent
  local common_gid = picked[1].group_id
  if common_gid then
    local all_same = true
    for k = 2, #picked do if picked[k].group_id ~= common_gid then all_same = false; break end end
    if all_same then gc.group_id = common_gid end
  end
  table.insert(cues, ins_pos, gc)
  -- 把收集的cue依序插入GROUP後方 -- insert collected cues right after GROUP
  for k, pc in ipairs(picked) do
    table.insert(cues, ins_pos + k, pc)
    pc.group_id = gc.id
    if pc.type ~= "GROUP" then pc.cue_color = CUE_COLOR_INHERIT end
  end
  -- rebuild_groups重建所有GROUP的children列表（處理從舊group移出的情況） -- rebuild all group children lists
  FUNC.rebuild_groups()
  FUNC.assign_number(ins_pos);FUNC.sel1(ins_pos);next_go=ins_pos;FUNC.save_cues()  -- GROUP用assign_number -- assign number for new GROUP
end

function FUNC.ungroup_cue(ci)
  local c=cues[ci];if not c or c.type~="GROUP" then return end
  FUNC.push_undo()
  local grandparent_gid = c.group_id  -- 巢狀GROUP的parent，解散後children回歸grandparent -- children return to grandparent on ungroup
  local child_ids = {}
  for _,q in ipairs(cues) do
    if q.group_id==c.id then q.group_id=grandparent_gid; child_ids[q.id]=true end  -- 回歸grandparent而非nil -- restore to grandparent instead of nil
  end
  table.remove(cues,ci);selected={}  -- ungroup不重排number -- ungroup doesn't renumber
  FUNC.rebuild_groups()  -- 重建children列表避免殘留舊index -- rebuild to prevent stale indices
  -- ungroup後選擇所有children -- select all children after ungroup
  for i,q in ipairs(cues) do
    if child_ids[q.id] then selected[i]=true end
  end
  local sf=FUNC.sel_first()
  next_go = sf and sf > 0 and sf or (math.min(ci,#cues))
  if next_go < 1 and #cues > 0 then next_go = 1 end
  FUNC.save_cues()
end

function FUNC.rebuild_groups()
  for _,c in ipairs(cues) do if c.type=="GROUP" then c.children={} end end
  for i,c in ipairs(cues) do
    if c.group_id then
      -- 防止GROUP成為自己的child（自引用會導致stack overflow）-- prevent self-reference cycle
      if c.type == "GROUP" and c.group_id == c.id then c.group_id = nil; goto skip_rg end
      local _,gc=FUNC.find_id(c.group_id)
      if gc and gc.type=="GROUP" then gc.children[#gc.children+1]=i
      else c.group_id=nil end
      ::skip_rg::
    end
  end
end

-- 給 live-reorder 用：拖曳 X 若無法合法進入 cues[ci] 的 group 上下文，
-- 回傳必須整塊跳過的 nest-group 範圍 (start_ci, end_ci)；不需跳過則回 nil。
-- 找「外層 blocker」：沿 ci 的 group 鏈往上走，遇到使 X 落入後 effective depth 超限的 group，
-- 取最外層（最接近 root）的那個整塊跳過。
function FUNC.drag_skip_range(ci, X)
  if not X or not ci or ci < 1 or ci > #cues then return nil end
  local target = cues[ci]; if not target then return nil end
  local entry_gid
  if target.type == "GROUP" then entry_gid = target.id else entry_gid = target.group_id end
  if not entry_gid then return nil end
  local function ucd(start_gid)
    local d, gid, g = 0, start_gid, 0
    while gid and g < 100 do
      d = d + 1; g = g + 1
      local _, gc = FUNC.find_id(gid); if not gc then break end
      gid = gc.group_id
    end
    return d
  end
  local x_is_grp = (X.type == "GROUP")
  local skip_gid, gid = nil, entry_gid
  while gid do
    local d_in = ucd(gid)  -- X 若直接成為 gid 的 child 時的深度
    local eff = d_in + (x_is_grp and 1 or 0)
    if eff > MAX_GROUP_DEPTH then skip_gid = gid end
    local _, gc = FUNC.find_id(gid); if not gc then break end
    gid = gc.group_id
  end
  if not skip_gid then return nil end
  local start_ci
  for i, c in ipairs(cues) do if c.id == skip_gid then start_ci = i; break end end
  if not start_ci then return nil end
  local end_ci = start_ci
  for j = start_ci + 1, #cues do
    local g, is_desc = cues[j].group_id, false
    while g do
      if g == skip_gid then is_desc = true; break end
      local _, pc = FUNC.find_id(g); if not pc then break end
      g = pc.group_id
    end
    if is_desc then end_ci = j else break end
  end
  return start_ci, end_ci
end

function FUNC.update_drag_groups()
  local after_ci = drag.src_ci + drag.block_n
  local after_gid = (after_ci <= #cues) and cues[after_ci].group_id or nil
  drag.depth_blocked = false  -- reset 每幀；若任一被拖 cue 因深度被退一層則設 true
  for bi=drag.src_ci, drag.src_ci+drag.block_n-1 do
    local dc=cues[bi]; if not dc then goto next_bi end
    local old_gid = dc.group_id
    local above_ci = (bi==drag.src_ci) and (drag.src_ci-1) or (bi-1)
    local new_gid = nil
    if above_ci>=1 then
      local ac=cues[above_ci]
      if ac.type=="GROUP" then new_gid=ac.id
      elseif ac.group_id then
        if bi==drag.src_ci and old_gid~=ac.group_id then
          new_gid = (after_gid==ac.group_id) and ac.group_id or nil
        else
          new_gid=ac.group_id
        end
      end
    end
    -- 巢狀深度檢查：含子孫；超過 MAX_GROUP_DEPTH 時往外層退（變 sibling 而非 child）
    -- depth check (includes descendants): climb out until subtree fits
    if new_gid and dc.type == "GROUP" then
      local intended = new_gid
      local old = dc.group_id
      -- 用 uncapped 走鏈，FUNC.cue_depth 上限 MAX 會吞掉超深 -- uncapped walk; FUNC.cue_depth caps at MAX
      local function uncapped_depth(start_gid)
        local d, gid, guard = 0, start_gid, 0
        while gid and guard < 100 do
          d = d + 1; guard = guard + 1
          local _, gc = FUNC.find_id(gid); if not gc then break end
          gid = gc.group_id
        end
        return d
      end
      -- GROUP cue 需為將來/既有 child 保留 1 層空間 → effective depth +1
      -- 否則空 GROUP 可落在 depth=MAX 但無法承載任何 child（與 group_sel_would_exceed 一致）
      local function effective_depth(cc2, gid)
        local d = uncapped_depth(gid)
        if cc2.type == "GROUP" then d = d + 1 end
        return d
      end
      local function subtree_max_d(c)
        local m = effective_depth(c, c.group_id)
        for _, cc in ipairs(cues) do
          if cc.group_id == c.id then
            local sm = subtree_max_d(cc); if sm > m then m = sm end
          end
        end
        return m
      end
      while new_gid do
        dc.group_id = new_gid
        if subtree_max_d(dc) <= MAX_GROUP_DEPTH then break end
        local _, gc = FUNC.find_id(new_gid)
        new_gid = gc and gc.group_id or nil
      end
      dc.group_id = old
      if new_gid ~= intended then drag.depth_blocked = true end
    end
    dc.group_id = new_gid
    -- live drag 期間不改顏色，全部留到 settle_drag_colors() 結算
    ::next_bi::
  end
  -- 每次 drag session 第一次撞深度上限時觸發一次警告（drag 表會在新拖曳起手時重置）
  -- warn once per drag session when depth limit first hit; drag table re-init on new drag
  if drag.depth_blocked and not drag._depth_warned then
    FUNC.warn_max_depth(); drag._depth_warned = true
  end
  FUNC.rebuild_groups()
end

-- drag 結束後呼叫：根據 drag 開始時的 color+gid 與最終落點來結算顏色
-- 顏色語義：-1 = clean/預設（在group中自動繼承），0 = 在group中手動設為none，>0 = 自己的顏色
-- 規則：
--   >0（有自己顏色）→ 無論拖到哪裡，永遠保留
--   -1（clean）→ 無論拖到哪裡，永遠保持 -1（在group中自動繼承新group顏色，在group外無色）
--   0（在group中手動設為none）：
--     → 放開在 group 外 + 原本在 group 中 → 恢復 -1（clean，下次進group可繼承）
--     → 放開在 group 內（任意group）→ 保持 0（不繼承新group）
-- 唯一觸發 0→-1 的時機：drag 開始時 color==0 且在group中，drag 結束在group外（同一次滑鼠按住）
function FUNC.settle_drag_colors()
  local backup = drag.color_backup or {}
  for _, c in ipairs(cues) do
    local orig = backup[c.id]
    if not orig then goto skip end
    -- 唯一需要轉換：0（在group中手動none）+ 原本在group + 現在拖出group外 → -1（恢復clean）
    if orig.color == 0 and orig.gid and not c.group_id then
      c.cue_color = CUE_COLOR_INHERIT
    end
    -- 其他狀況全部保持不動（-1留-1，0→group內留0，>0永遠留>0）
    ::skip::
  end
  drag.color_backup = nil
end
