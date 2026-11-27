-- ==========================================================================
-- config.lua — Prefs, Shortcuts, Colors, Types
-- ==========================================================================

---------------------------------------------------------------------
-- PREFS
---------------------------------------------------------------------
prefs = {
  -- 配色（v2 原生深色）：全部可在 Preferences 改 -- palette v2 (native dark), all editable in Preferences
  scale=125, col_bg=0x000C1E21, col_panel=0x0011292C, col_header=0x0011292C, col_column_title=0x008FA3A5,
  col_text=0x00ECEFEF, col_text_dim=0x008FA3A5, col_accent=0x00137085,
  col_go=0x00137085, col_row=0x000E2225, col_border=0x002A4446, master_vol=0.0,
  col_gold=0x00F5A623,    -- 重點色（Next、播放中、BPM）-- highlight (next, playing, bpm)
  col_danger=0x00D9472F,  -- PANIC / Stop
  col_field=0x0009171A,   -- 輸入框、凹槽 -- input fields, wells
  col_btn=0x001A3A3E,     -- 一般按鈕 -- neutral buttons
  col_card=0x00163236,    -- edit 面板卡片 -- edit panel cards
  theme_ver=0,            -- 配色版本：<2 時一次性升級成 v2 -- palette version; <2 migrates once
  col_trim=0x00F5A623,
  col_wf=0x004BBCC6,
  col_prewait=0x00F5A623, col_postwait=0x00F5A623,  -- pre/post wait進度條顏色 -- progress bar colors (bright)
  col_duration=0x002FA0A8, col_wf_bg=0x0009171A,    -- duration進度條+波形背景 -- duration bar + waveform bg
  col_env=0x00FFB432,
  col_pan_env=0x0050D080,  -- panning envelope綠色
  col_ruler=0x00C8C8D0,  -- waveform ruler刻度+文字顏色
  col_guide=0x00E0E0F0,  -- waveform guide line + range selection
  default_fade_time=12,
  soft_kill_time=3,
  inf_db  = -72.0,
  edit_open=1,  -- edit panel開關記憶: 1=開, 0=關 -- edit panel state persistence
  edit_ratio=35,  -- edit panel高度比例(25~65, /100) -- edit panel height ratio (stored as int)
  edit_sec_order=123,  -- section順序: 1=Basic,2=Notes,3=Waveform, e.g.123=預設 -- section order encoding
  edit_sec_basic=1,   -- Basic section展開: 1=開, 0=收合 -- Basic section expanded
  edit_sec_notes=1,   -- Notes section展開: 1=開, 0=收合 -- Notes section expanded
  edit_sec_wf=1,      -- Waveform section展開: 1=開, 0=收合 -- Waveform section expanded
  edit_sec_route=1,   -- Route section展開: 1=開, 0=收合 -- Route section expanded
  edit_sec_rb=22,     -- (舊ratio，僅供遷移用) -- legacy ratio, migration only
  edit_sec_rn=18,     -- (舊ratio，僅供遷移用) -- legacy ratio, migration only
  edit_sec_rw=60,     -- (舊ratio，僅供遷移用) -- legacy ratio, migration only
  wf_normalize=0,  -- 波形normalize: 0=關, 1=開 -- waveform visual normalize
  edit_vis_basic=1,  -- Basic標籤頁可見: 1=顯示, 0=隱藏 -- Basic tab visible
  edit_vis_notes=1,  -- Notes標籤頁可見: 1=顯示, 0=隱藏 -- Notes tab visible
  edit_vis_wf=1,     -- Waveform標籤頁可見: 1=顯示, 0=隱藏 -- Waveform tab visible
  edit_vis_route=1,  -- Route標籤頁可見: 1=顯示, 0=隱藏 -- Route tab visible
  edit_sec_meter=1,  -- Meter section展開: 1=開, 0=收合 -- Meter section expanded
  edit_sec_wb=0, edit_sec_wn=0, edit_sec_ww=0, edit_sec_wr=0, edit_sec_wm=0,  -- 各面板寬度px（0=未設定：b/n/w 從舊ratio遷移，route/meter用自動寬度）-- section widths, 0=unset
  edit_vis_meter=1,  -- Meter標籤頁可見: 1=顯示, 0=隱藏 -- Meter tab visible
  vol_min=-72,   -- per-project volume floor (range: -120~0)
  vol_max=12,    -- per-project volume ceiling (range: 0~+36, default +12)
  default_negative=1,  -- 輸入正數自動轉負: 1=開(輸入3→-3dB), 0=關(輸入3→+3dB) -- auto-negate positive input
  track_sel_link=0,  -- 點cue時選取對應REAPER track: 1=開, 0=關 -- select REAPER track on cue click
  track_color_follow=0,  -- REAPER track/MIDI item color 跟隨 cue color: 1=開, 0=關 -- track/item follows cue color
}

-- Per-project pref keys (everything else is global) -- 專案層級設定key
PROJ_PREF_KEYS = {
  master_vol=true, default_fade_time=true, soft_kill_time=true, wf_normalize=true,
  vol_min=true, vol_max=true, inf_db=true,
  edit_open=true, edit_ratio=true, edit_sec_order=true,
  edit_sec_basic=true, edit_sec_notes=true, edit_sec_wf=true, edit_sec_route=true, edit_sec_meter=true,
  edit_sec_rb=true, edit_sec_rn=true, edit_sec_rw=true,
  edit_sec_wb=true, edit_sec_wn=true, edit_sec_ww=true, edit_sec_wr=true, edit_sec_wm=true,
  edit_vis_basic=true, edit_vis_notes=true, edit_vis_wf=true, edit_vis_route=true, edit_vis_meter=true,
}

function FUNC.load_prefs()
  -- 1. 載入全域設定（scale, colors等）-- load global prefs (scale, colors, etc.)
  local d = reaper.GetExtState(EXT.PREFS, "data")
  if d and d~="" then for k,v in d:gmatch("([%w_]+)=([^;]+)") do
    if not PROJ_PREF_KEYS[k] and prefs[k]~=nil and type(prefs[k])=="number" then prefs[k]=tonumber(v) or prefs[k] end
  end end
  -- 2. 載入per-project設定 -- load project-specific prefs
  local _,pd = reaper.GetProjExtState(0, EXT.PREFS, "proj_data")
  if pd and pd~="" then for k,v in pd:gmatch("([%w_]+)=([^;]+)") do
    if PROJ_PREF_KEYS[k] and prefs[k]~=nil and type(prefs[k])=="number" then prefs[k]=tonumber(v) or prefs[k] end
  end end
  -- 舊版遷移：若proj_data不存在，嘗試從全域data讀取project key -- legacy migration
  if (not pd or pd=="") then
    local ld = reaper.GetExtState(EXT.PREFS, "data")
    if ld and ld~="" then for k,v in ld:gmatch("([%w_]+)=([^;]+)") do
      if PROJ_PREF_KEYS[k] and prefs[k]~=nil and type(prefs[k])=="number" then prefs[k]=tonumber(v) or prefs[k] end
    end end
  end
  -- inf_db跟隨vol_min -- inf_db follows vol_min
  prefs.inf_db = prefs.vol_min
end
-- proj：per-project 設定要寫進哪個專案（nil=目前專案；false=不寫 per-project 部分）
-- proj: which project receives the per-project part (nil = current project; false = skip the per-project part)
function FUNC.save_prefs(proj)
  -- 全域設定 -- save global prefs
  local g={}; for k,v in pairs(prefs) do
    if not PROJ_PREF_KEYS[k] and type(v)=="number" then g[#g+1]=k.."="..tostring(v) end
  end
  reaper.SetExtState(EXT.PREFS, "data", table.concat(g,";"), true)
  -- per-project設定 -- save project-specific prefs
  local p={}; for k,v in pairs(prefs) do
    if PROJ_PREF_KEYS[k] and type(v)=="number" then p[#p+1]=k.."="..tostring(v) end
  end
  if proj ~= false then reaper.SetProjExtState(proj or 0, EXT.PREFS, "proj_data", table.concat(p,";")) end
end
FUNC.load_prefs()

-- 配色 v2 一次性升級：舊版存的藍色系配色換成新預設（另存的主題檔不受影響）
-- one-time palette v2 migration: replace saved legacy colors with new defaults (saved theme files untouched)
THEME_V2 = {
  col_bg=0x00161618, col_panel=0x00222225, col_header=0x00222225, col_column_title=0x008D8D93,
  col_text=0x00ECECEE, col_text_dim=0x008D8D93, col_accent=0x001D7A75, col_go=0x001D7A75,
  col_row=0x001B1B1E, col_border=0x0038383C, col_gold=0x00F5A623, col_danger=0x00D9472F,
  col_field=0x00141416, col_btn=0x00323236, col_card=0x00222226, col_trim=0x00F5A623,
  col_wf=0x004FB8AE, col_prewait=0x00F5A623, col_postwait=0x00F5A623, col_duration=0x002FA0A8, col_wf_bg=0x0009171A,
}
if (prefs.theme_ver or 0) < 2 then
  for k, v in pairs(THEME_V2) do prefs[k] = v end
  prefs.theme_ver = 2
  FUNC.save_prefs(false)
end
-- v4：改用設計稿 C 的實際底色（只改這幾個底色）-- v4: exact base colors from mockup C
if prefs.theme_ver < 4 then
  for _, k in ipairs({"col_bg","col_panel","col_header","col_row","col_field","col_btn","col_card"}) do prefs[k] = THEME_V2[k] end
  prefs.theme_ver = 4
  FUNC.save_prefs(false)
end
-- v5：改成設計稿 B（深湖）藍綠底色，主色湖水綠加深偏藍 -- v5: mockup B (deep lagoon) teal-blue bases, deeper bluer primary
THEME_V5 = {
  col_bg=0x000C1E21, col_panel=0x0011292C, col_header=0x0011292C, col_row=0x000E2225, col_field=0x0009171A,
  col_btn=0x001A3A3E, col_card=0x00163236, col_border=0x002A4446, col_accent=0x00137085, col_go=0x00137085,
  col_text=0x00ECEFEF, col_text_dim=0x008FA3A5, col_column_title=0x008FA3A5,
  col_wf=0x004BBCC6, col_duration=0x002FA0A8, col_wf_bg=0x0009171A,
}
if prefs.theme_ver < 5 then
  for k, v in pairs(THEME_V5) do prefs[k] = v end
  prefs.theme_ver = 5
  FUNC.save_prefs(false)
end

---------------------------------------------------------------------
-- OUTPUT MAP — per-project hw output channel mapping
-- 每個project獨立的hw output channel對照表（編號/別稱/顏色）
---------------------------------------------------------------------
output_map = {}  -- {[ch_idx] = {num=int, alias=string, color=0x00RRGGBB or -1}}
output_map_order = {}  -- {ch_idx, ch_idx, ...} 排序用 -- display order

-- 序列化："ch:num:color:alias;..." -- serialization
function FUNC.omap2str()
  local s = {}
  for _, ch in ipairs(output_map_order) do
    local e = output_map[ch]
    if e then
      local a = (e.alias or ""):gsub(";", "\\;"):gsub(":", "\\:")
      s[#s+1] = string.format("%d:%d:%d:%s", ch, e.num, e.color or -1, a)
    end
  end
  return table.concat(s, ";")
end
function FUNC.str2omap(s)
  local m, ord = {}, {}
  if not s or s == "" then return m, ord end
  -- 手動split by ";" (跳過escaped \;) -- manual split respecting escaped semicolons
  local entries = {}
  local buf, i = "", 1
  while i <= #s do
    local c = s:sub(i, i)
    if c == "\\" and i < #s then buf = buf .. s:sub(i+1, i+1); i = i + 2
    elseif c == ";" then entries[#entries+1] = buf; buf = ""; i = i + 1
    else buf = buf .. c; i = i + 1 end
  end
  if buf ~= "" then entries[#entries+1] = buf end
  for _, ent in ipairs(entries) do
    -- parse "ch:num:color:alias" (alias may contain escaped colons)
    local parts, pbuf, pi = {}, "", 1
    while pi <= #ent do
      local ec = ent:sub(pi, pi)
      if ec == "\\" and pi < #ent then pbuf = pbuf .. ent:sub(pi+1, pi+1); pi = pi + 2
      elseif ec == ":" and #parts < 3 then parts[#parts+1] = pbuf; pbuf = ""; pi = pi + 1
      else pbuf = pbuf .. ec; pi = pi + 1 end
    end
    parts[#parts+1] = pbuf
    if #parts >= 3 then
      local ch = tonumber(parts[1])
      local num = tonumber(parts[2])
      local col = tonumber(parts[3]) or -1
      local alias = parts[4] or ""
      if ch and num then
        m[ch] = {num=num, alias=alias, color=col}
        ord[#ord+1] = ch
      end
    end
  end
  return m, ord
end

-- 欄寬持久化 -- column width persistence
omap_col_widths = nil  -- {num=N, name=N, color=N} or nil

function FUNC.omap_save()
  reaper.SetProjExtState(0, EXT.PREFS, "output_map", FUNC.omap2str())
  -- 儲存欄寬 -- save column widths
  if omap_col_widths then
    reaper.SetProjExtState(0, EXT.PREFS, "output_map_cols",
      string.format("%d,%d", omap_col_widths.num, omap_col_widths.name))
  end
end
function FUNC.omap_load()
  local _, s = reaper.GetProjExtState(0, EXT.PREFS, "output_map")
  output_map, output_map_order = FUNC.str2omap(s)
  -- 載入欄寬 -- load column widths
  local _, cw = reaper.GetProjExtState(0, EXT.PREFS, "output_map_cols")
  if cw and cw ~= "" then
    local n, nm = cw:match("(%d+),(%d+)")
    if n then omap_col_widths = {num=tonumber(n), name=tonumber(nm)} end
  end
end

-- 確保channel有對照資料，沒有就自動建立 -- ensure channel has map entry, auto-create if missing
function FUNC.omap_ensure(ch)
  if output_map[ch] then return output_map[ch] end
  -- 找下一個可用編號 -- find next available number
  local used = {}
  for _, e in pairs(output_map) do used[e.num] = true end
  local num = ch + 1  -- 預設1-based -- default 1-based
  while used[num] do num = num + 1 end
  local name = reaper.GetOutputChannelName(ch) or ("Out " .. (ch + 1))
  output_map[ch] = {num=num, alias=name, color=-1}
  -- 加到order尾端 -- append to order
  local found = false
  for _, v in ipairs(output_map_order) do if v == ch then found = true; break end end
  if not found then output_map_order[#output_map_order+1] = ch end
  return output_map[ch]
end

-- 取得channel的顯示編號 -- get display number for channel
function FUNC.omap_num(ch)
  local e = output_map[ch]
  return e and e.num or (ch + 1)
end
-- 取得channel的別稱 -- get alias for channel
function FUNC.omap_alias(ch)
  local e = output_map[ch]
  return e and e.alias ~= "" and e.alias or (reaper.GetOutputChannelName(ch) or ("Out " .. (ch + 1)))
end
-- 取得channel的顏色 -- get color for channel
function FUNC.omap_color(ch)
  local e = output_map[ch]
  return e and e.color or -1
end

FUNC.omap_load()
-- 啟動時自動建立所有hw output的map entry -- auto-init all hw outputs at startup
do
  local total_outs = reaper.GetNumAudioOutputs()
  for ch = 0, total_outs - 1 do FUNC.omap_ensure(ch) end
end

-- Theme save/load（全域ExtState，跨project共用）-- global theme storage
local THEME_SECTION = "Realive_Themes"
local THEME_KEYS = {  -- 只儲存顏色相關的pref key -- only color-related keys
  "col_bg","col_panel","col_header","col_column_title","col_text","col_text_dim",
  "col_accent","col_go","col_row","col_border","col_trim","col_wf",
  "col_env","col_pan_env","col_ruler","col_guide","col_prewait","col_postwait","col_duration","col_wf_bg",
  "col_gold","col_danger","col_field","col_btn","col_card",  -- v2
}
function FUNC.get_theme_list()
  local idx = reaper.GetExtState(THEME_SECTION, "__index__")
  local names = {}
  if idx ~= "" then for n in idx:gmatch("[^\t\n]+") do names[#names+1] = n end end  -- \t(新)+\n(舊)雙相容
  return names
end
function FUNC.save_theme(name)
  if name == "" then return end
  local parts = {}
  for _, k in ipairs(THEME_KEYS) do
    if prefs[k] ~= nil then parts[#parts+1] = k .. "=" .. tostring(prefs[k]) end
  end
  reaper.SetExtState(THEME_SECTION, name, table.concat(parts, ";"), true)
  local names = FUNC.get_theme_list()
  local found = false
  for _, n in ipairs(names) do if n == name then found = true; break end end
  if not found then names[#names+1] = name end
  reaper.SetExtState(THEME_SECTION, "__index__", table.concat(names, "\t"), true)  -- \t取代\n
end
function FUNC.load_theme(name)
  local data = reaper.GetExtState(THEME_SECTION, name)
  if data == "" then return end
  for k, v in data:gmatch("([%w_]+)=([^;]+)") do
    if prefs[k] ~= nil then prefs[k] = tonumber(v) or prefs[k] end
  end
  FUNC.upd_colors(); FUNC.upd_types()
end
function FUNC.delete_theme(name)
  reaper.DeleteExtState(THEME_SECTION, name, true)
  local names = FUNC.get_theme_list()
  local new = {}
  for _, n in ipairs(names) do if n ~= name then new[#new+1] = n end end
  reaper.SetExtState(THEME_SECTION, "__index__", table.concat(new, "\t"), true)  -- \t取代\n
end

function FUNC.sc() return prefs.scale/100 end
function FUNC.sz(v) return math.floor(v*FUNC.sc()) end

-- BPM音符值對照表（quarter=1 beat）-- note value table for BPM mode
local function _smufl(cp)  -- encode SMuFL codepoint to UTF-8
  return string.char(0xE0 + math.floor(cp/4096), 0x80 + math.floor(cp/64)%64, 0x80 + cp%64)
end
NOTE_VALUES = {
  {val=4,      sym=_smufl(0xE1D2),                          label="Whole"},      -- 全音符
  {val=3,      sym=_smufl(0xE1D3).._smufl(0xE1E7),          label="Half."},      -- 附點二分
  {val=2,      sym=_smufl(0xE1D3),                           label="Half"},       -- 二分
  {val=4/3,    sym=_smufl(0xE1D3),                           label="Half\xC2\xB3"},-- 二分三連
  {val=1.5,    sym=_smufl(0xE1D5).._smufl(0xE1E7),          label="Qtr."},       -- 附點四分
  {val=1,      sym=_smufl(0xE1D5),                           label="Quarter"},    -- 四分（預設）
  {val=2/3,    sym=_smufl(0xE1D5),                           label="Qtr\xC2\xB3"},-- 四分三連
  {val=0.5,    sym=_smufl(0xE1D7),                           label="8th"},        -- 八分
  {val=1/3,    sym=_smufl(0xE1D7),                           label="8th\xC2\xB3"},-- 八分三連
  {val=0.25,   sym=_smufl(0xE1D9),                           label="16th"},       -- 十六分
}
NOTE_DEFAULT_IDX = 6  -- Quarter note

---------------------------------------------------------------------
-- SHORTCUT SYSTEM
---------------------------------------------------------------------
SC_DEFS = {
  -- Transport
  {id="go",        name="GO",            def="Space",  cat="Transport"},
  {id="go_alt",    name="GO (Alt)",      def="None",   cat="Transport"},  -- 第二GO快速鍵 -- alternative GO key
  {id="panic_alt", name="Panic (Alt)",   def="None",   cat="Transport"},  -- 第二Panic快速鍵(Esc鎖死) -- alternative Panic key
  {id="preview",   name="Preview",       def="V",      cat="Transport"},
  {id="kill_sel",  name="Kill Selected", def="S",      cat="Transport"},
  -- Add Cue
  {id="add_play",  name="Add Play",      def="Shift+A", cat="Add Cue"},
  {id="add_stop",  name="Add Stop",      def="Shift+S", cat="Add Cue"},
  {id="add_pause", name="Add Pause",     def="Shift+P", cat="Add Cue"},
  {id="add_fade",  name="Add Fade",      def="Shift+F", cat="Add Cue"},
  -- Groups
  {id="group",     name="Group/Ungroup", def="G",      cat="Groups"},  -- toggle group/ungroup合併
  {id="fold",      name="Fold/Unfold",   def="H",      cat="Groups"},
  -- Zoom
  {id="zoom_in",   name="Zoom In (+5%)",  def="None",  cat="View"},  -- 預設無鍵(Cmd+=由hardcode處理)
  {id="zoom_out",  name="Zoom Out (-5%)", def="None",  cat="View"},
  -- Field Edit (快捷鍵編輯欄位)
  {id="edit_vol",      name="Edit Volume",    def="Shift+V",  cat="Fields"},
  {id="edit_prewait",  name="Edit Pre-Wait",  def="I",        cat="Fields"},  -- 預設改i
  {id="edit_postwait", name="Edit Post-Wait", def="O",        cat="Fields"},  -- 預設改o
  {id="edit_fadetime", name="Edit Fade Time", def="D",        cat="Fields"},
  {id="edit_cue_num",  name="Edit Cue Number",def="C",        cat="Fields"},  -- 新增：按c編輯cue number
  {id="tog_autogo",    name="Toggle Auto-Go", def="A",        cat="Fields"},
  {id="tog_kill",      name="Toggle Kill⇡",   def="X",        cat="Fields"},
  {id="tog_loop",      name="Toggle Loop",    def="L",        cat="Fields"},
  {id="tog_edit",      name="Toggle Edit Panel",def="E",      cat="View"},  -- 新增：按e開關edit panel
  {id="reset_cols",    name="Reset Columns",   def="Ctrl+Shift+R", cat="View"},  -- 欄位重置模式 -- column reset mode
}
scut = {}  -- id -> key string
for _,d in ipairs(SC_DEFS) do scut[d.id] = d.def end

function FUNC.load_shortcuts()
  -- 優先讀全域persist，fallback到舊的ProjExtState -- prefer global persist, fallback to legacy
  local d = reaper.GetExtState(EXT.PREFS, "shortcuts")
  if d == "" then _,d = reaper.GetProjExtState(0, EXT.PREFS, "shortcuts") end
  if d and d ~= "" then for k,v in d:gmatch("([%w_]+)=([^;]+)") do scut[k] = v end end
end
function FUNC.save_shortcuts()
  local p = {}; for _,d in ipairs(SC_DEFS) do p[#p+1] = d.id.."="..scut[d.id] end
  reaper.SetExtState(EXT.PREFS, "shortcuts", table.concat(p, ";"), true)  -- persist=true -- persist across reboots
end
FUNC.load_shortcuts()

---------------------------------------------------------------------
-- WAVEFORM WHEEL SETTINGS -- 波形滾輪設定（modifier組合+reverse）
---------------------------------------------------------------------
WF_WHEEL_DEFS = {
  {id="scroll", name="Scroll"},
  {id="vzoom",  name="Vertical Zoom"},
  {id="hzoom",  name="Horizontal Zoom"},
}
-- 預設：scroll=none, vzoom=Alt, hzoom=Ctrl -- defaults
wf_wheel = {
  scroll = {shift=false, ctrl=false, alt=false, rev=false},
  vzoom  = {shift=false, ctrl=false, alt=true,  rev=false},
  hzoom  = {shift=false, ctrl=true,  alt=false, rev=false},
}
function FUNC.load_wf_wheel()
  local d = reaper.GetExtState(EXT.PREFS, "wf_wheel")
  if d == "" then return end
  for id, s, c, a, r in d:gmatch("([%w_]+):(%d),(%d),(%d),(%d)") do
    if wf_wheel[id] then
      wf_wheel[id] = {shift=s=="1", ctrl=c=="1", alt=a=="1", rev=r=="1"}
    end
  end
end
function FUNC.save_wf_wheel()
  local p = {}
  for _, wd in ipairs(WF_WHEEL_DEFS) do
    local w = wf_wheel[wd.id]
    p[#p+1] = string.format("%s:%d,%d,%d,%d", wd.id, w.shift and 1 or 0, w.ctrl and 1 or 0, w.alt and 1 or 0, w.rev and 1 or 0)
  end
  reaper.SetExtState(EXT.PREFS, "wf_wheel", table.concat(p, ";"), true)
end
FUNC.load_wf_wheel()

-- 取得modifier組合的key string（用於衝突偵測）-- get modifier combo key for conflict detection
function FUNC.wf_wheel_key(w) return (w.shift and "S" or "")..(w.ctrl and "C" or "")..(w.alt and "A" or "") end

-- Key name tables + reverse lookup for keyboard listening
KEY_NAMES = {}
KEY_IDS = {}
KEY_REVERSE = {}  -- ImGui key id -> base name (不含modifier)，用於鍵盤監聽
scut_listen = nil  -- 正在監聯的shortcut id (nil=沒在監聽)
hotkey_listen = false  -- 正在監聽hotkey指定 -- listening for hotkey assignment
do
  -- 基本鍵 -- base keys
  local base_keys = {}
  local function add(name, kid)
    base_keys[#base_keys + 1] = {name=name, kid=kid}
    KEY_REVERSE[kid] = name
  end
  add("Space", ImGui.Key_Space())
  add("Enter", ImGui.Key_Enter())
  add("Tab", ImGui.Key_Tab())
  for i = 0, 9 do add(tostring(i), ImGui["Key_"..i]()) end
  for l in ("A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R,S,T,U,V,W,X,Y,Z"):gmatch("[A-Z]") do
    add(l, ImGui["Key_"..l]())
  end
  for i = 1, 12 do add("F"..i, ImGui["Key_F"..i]()) end
  -- 建立 KEY_NAMES / KEY_IDS（僅base key）-- build tables (base keys only, modifiers handled dynamically)
  for _, k in ipairs(base_keys) do
    KEY_NAMES[#KEY_NAMES + 1] = k.name
    KEY_IDS[k.name] = k.kid
  end
end

-- 鍵盤監聯：偵測按下的鍵+所有modifier組合，如 "Cmd+Shift+V" -- detect pressed key with all modifier combos
-- modifier順序固定：Cmd > Ctrl > Alt > Shift（方便比對）-- fixed order for consistent matching
function FUNC.detect_keypress()
  for kid, name in pairs(KEY_REVERSE) do
    if ImGui.IsKeyPressed(ctx, kid) then
      local prefix = ""
      if ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl())  then prefix = prefix.."Cmd+" end    -- macOS: Cmd
      if ImGui.IsKeyDown(ctx, ImGui.Mod_Super()) then prefix = prefix.."Ctrl+" end   -- macOS: Ctrl(physical)
      if ImGui.IsKeyDown(ctx, ImGui.Mod_Alt())   then prefix = prefix.."Alt+" end    -- macOS: Option
      if ImGui.IsKeyDown(ctx, ImGui.Mod_Shift()) then prefix = prefix.."Shift+" end
      return prefix..name
    end
  end
  return nil
end

-- 數字鍵判定(含numpad)：hotkey只接受0-9 -- digit detection for hotkey (including numpad)
local DIGIT_KEYS = {}
for i = 0, 9 do DIGIT_KEYS[tostring(i)] = true end
function FUNC.is_digit_key(name)
  if not name then return false end
  return DIGIT_KEYS[name] or false  -- "0"-"9" only
end

-- numpad 0-9 的 ImGui key ID，用於hotkey偵測 -- numpad key IDs for hotkey detection
local NUMPAD_IDS = {}
for i = 0, 9 do NUMPAD_IDS[tostring(i)] = ImGui["Key_Keypad"..i]() end

-- 偵測數字鍵（含numpad），回傳"0"-"9"或nil -- detect digit key press (regular + numpad)
function FUNC.detect_digit_key()
  for i = 0, 9 do
    local d = tostring(i)
    if ImGui.IsKeyPressed(ctx, KEY_IDS[d]) then return d end
    if ImGui.IsKeyPressed(ctx, NUMPAD_IDS[d]) then return d end
  end
  return nil
end

-- hotkey偵測：檢查cue的hotkey是否被按下（支援numpad） -- check if cue hotkey pressed (supports numpad)
function FUNC.hotkey_check(hk)
  if not hk or hk == "" then return false end
  if not DIGIT_KEYS[hk] then return false end  -- hotkey只能是0-9 -- hotkeys are digits only
  local kid = KEY_IDS[hk]
  local nkid = NUMPAD_IDS[hk]
  -- false = 按住不放不重複觸發 -- false = holding the key does not fire again
  local pressed = (kid and ImGui.IsKeyPressed(ctx, kid, false)) or (nkid and ImGui.IsKeyPressed(ctx, nkid, false))
  if not pressed then return false end
  -- 不能同時按住Shift/Ctrl/Cmd，避免跟shortcut衝突 -- no modifiers to avoid shortcut conflicts
  return not ImGui.IsKeyDown(ctx, ImGui.Mod_Shift()) and not ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl())
end

function FUNC.sc_check(id)
  local b = scut[id]; if not b then return false end
  -- 解析modifier+key：最後一個+後面是key，前面全是modifier -- parse: last segment = key, rest = modifiers
  local parts = {}
  for seg in b:gmatch("[^+]+") do parts[#parts+1] = seg end
  if #parts == 0 then return false end
  local key = parts[#parts]
  local kid = KEY_IDS[key]
  if not kid then return false end
  -- false = 不吃按鍵自動重複：按住 Space 不會連續 GO，按住切換鍵不會來回閃
  -- false = ignore key auto-repeat: holding Space must not GO repeatedly, holding a toggle key must not flicker
  if not ImGui.IsKeyPressed(ctx, kid, false) then return false end
  -- 建立要求的modifier集合 -- build required modifier set
  local want = {}
  for i = 1, #parts - 1 do want[parts[i]] = true end
  -- 檢查每個modifier：要求的必須按住，不要求的必須放開 -- exact match: required held, others released
  local function chk(name, imgui_mod)
    local held = ImGui.IsKeyDown(ctx, imgui_mod)
    if want[name] then return held else return not held end
  end
  return chk("Cmd", ImGui.Mod_Ctrl()) and chk("Ctrl", ImGui.Mod_Super())
     and chk("Alt", ImGui.Mod_Alt()) and chk("Shift", ImGui.Mod_Shift())
end

---------------------------------------------------------------------
-- COLORS
---------------------------------------------------------------------
function FUNC.rgba(r,g,b,a) return (math.floor(r)<<24)|(math.floor(g)<<16)|(math.floor(b)<<8)|math.floor(a or 255) end
dim_mul = 1.0
function FUNC.dim_c(col)
  if dim_mul >= 1 then return col end
  local a = col & 0xFF
  return (col & 0xFFFFFF00) | math.floor(a * dim_mul)
end
function FUNC.col2im(c,a) a=a or 255; return (((c>>16)&0xFF)<<24)|(((c>>8)&0xFF)<<16)|((c&0xFF)<<8)|a end

C={}
function FUNC.upd_colors()
  C.bg=FUNC.col2im(prefs.col_bg); C.panel=FUNC.col2im(prefs.col_panel); C.header=FUNC.col2im(prefs.col_header);C.column_title=FUNC.col2im(prefs.col_column_title);
  C.text=FUNC.col2im(prefs.col_text); C.dim=FUNC.col2im(prefs.col_text_dim); C.muted=FUNC.col2im(prefs.col_text_dim,100)
  C.accent=FUNC.col2im(prefs.col_accent); C.go=FUNC.col2im(prefs.col_go); C.go_h=FUNC.col2im(prefs.col_go,220)
  C.row=FUNC.col2im(prefs.col_row); C.row_a=FUNC.col2im(prefs.col_row,200); C.bdr=FUNC.col2im(prefs.col_border)
  C.trim=FUNC.col2im(prefs.col_trim)
  C.wf=FUNC.col2im(prefs.col_wf); C.env=FUNC.col2im(prefs.col_env); C.pan_env=FUNC.col2im(prefs.col_pan_env); C.ruler=FUNC.col2im(prefs.col_ruler); C.guide=FUNC.col2im(prefs.col_guide)
  C.sel=FUNC.rgba(150,150,150,60); C.run=FUNC.rgba(35,100,35)
  -- pre/post wait: pref色做進度條，row bg用暗化版 -- pref color for bar, dimmed for row bg
  local function dim_col(hex, factor)
    local r = ((hex >> 16) & 0xFF) * factor
    local g = ((hex >> 8) & 0xFF) * factor
    local b = (hex & 0xFF) * factor
    return FUNC.rgba(r, g, b)
  end
  C.pw=dim_col(prefs.col_prewait, 0.37); C.ptw=dim_col(prefs.col_postwait, 0.15); C.cur=FUNC.rgba(80,240,80)
  C.p_play=FUNC.col2im(prefs.col_duration); C.wf_bg=FUNC.col2im(prefs.col_wf_bg)
  C.stop_b=FUNC.rgba(160,30,30);C.stop_h=FUNC.rgba(190,40,40)
  C.panic_b=FUNC.rgba(180,60,10);C.panic_h=FUNC.rgba(210,80,20)
  C.reset_b=FUNC.rgba(60,60,100);C.reset_h=FUNC.rgba(80,80,130)
  C.chk_b=FUNC.rgba(40,100,140);C.chk_h=FUNC.rgba(50,120,170)
  C.kill_b=FUNC.rgba(140,60,20);C.kill_h=FUNC.rgba(170,80,30)
  C.t_play=FUNC.rgba(80,170,240);C.t_stop=FUNC.rgba(240,90,70);C.t_pause=FUNC.rgba(180,180,80)
  C.t_fade=FUNC.rgba(240,190,50);C.t_group=FUNC.rgba(180,130,240);C.t_midi=FUNC.rgba(80,200,160)
  C.p_wait=FUNC.col2im(prefs.col_prewait);C.p_fade=FUNC.rgba(60,140,200);C.p_ptw=FUNC.col2im(prefs.col_postwait)  -- pre/post wait進度條顏色跟隨自訂色 -- bar colors from prefs
  C.f_vol=FUNC.rgba(255,220,80); C.f_pan=FUNC.col2im(prefs.col_pan_env); C.f_pitch=FUNC.rgba(80,160,240)  -- fade chart顏色：vol黃/pan自訂/pitch藍 -- fade chart colors
  C.tb_play=FUNC.rgba(45,90,130);C.tb_play_h=FUNC.rgba(55,110,160)
  C.tb_stop=FUNC.rgba(130,25,20);C.tb_stop_h=FUNC.rgba(160,35,20)
  C.tb_pause=FUNC.rgba(100,100,50);C.tb_pause_h=FUNC.rgba(120,120,65)
  C.tb_fade=FUNC.rgba(150,100,30);C.tb_fade_h=FUNC.rgba(180,120,40)
  C.tb_grp=FUNC.rgba(90,60,130);C.tb_grp_h=FUNC.rgba(110,75,160)
  C.tb_midi=FUNC.rgba(35,100,85);C.tb_midi_h=FUNC.rgba(45,125,105)

  -- ═══ v2 風格 token（所有新元件只用這些）═══ -- v2 style tokens (all new widgets use only these)
  local function mix(hex, to, f)  -- hex 往 to 混 f（0~1）-- blend hex toward `to` by f
    local r = ((hex>>16)&255)*(1-f) + ((to>>16)&255)*f
    local g = ((hex>>8)&255)*(1-f) + ((to>>8)&255)*f
    local b = (hex&255)*(1-f) + (to&255)*f
    return (math.floor(r)<<16)|(math.floor(g)<<8)|math.floor(b)
  end
  local W = 0xFFFFFF
  C.chrome = FUNC.col2im(prefs.col_panel)                       -- 標題列/工具列/底列 -- bars
  C.field  = FUNC.col2im(prefs.col_field)                       -- 輸入框/凹槽 -- wells
  C.card   = FUNC.col2im(prefs.col_card)                        -- edit 卡片 -- cards
  C.edit_bg = FUNC.col2im(mix(prefs.col_bg, 0, 0.25))           -- edit 面板底：比表格再深一階 -- edit panel base, a step darker than the table
  C.card_hdr = FUNC.col2im(mix(prefs.col_card, W, 0.07))       -- 卡片標題列（比卡片亮一階）-- card header, a step lighter
  C.line   = FUNC.rgba(255,255,255,22)                          -- 細分隔線 -- hairline
  C.line2  = FUNC.rgba(255,255,255,40)                          -- 較明顯外框 -- stronger outline
  C.seg    = FUNC.col2im(mix(prefs.col_panel, 0, 0.18))         -- 分段按鈕凹槽（略深於工具列）-- segmented well, a shade below the bar
  C.btn    = FUNC.col2im(prefs.col_btn)
  C.btn_h  = FUNC.col2im(mix(prefs.col_btn, W, 0.08))
  C.btn_a  = FUNC.col2im(mix(prefs.col_btn, W, 0.15))
  C.ghost_h = FUNC.rgba(255,255,255,18)                         -- 透明按鈕 hover -- ghost hover
  C.ghost_a = FUNC.rgba(255,255,255,30)
  C.primary    = FUNC.col2im(prefs.col_accent)
  C.primary_h  = FUNC.col2im(mix(prefs.col_accent, W, 0.12))
  C.primary_hi = FUNC.col2im(mix(prefs.col_accent, W, 0.28))    -- 亮版主色：文字/meter/勾選 -- bright primary
  C.primary_soft = FUNC.col2im(mix(prefs.col_accent, W, 0.28), 52)  -- 選取底色 -- selection fill
  C.go_h   = FUNC.col2im(mix(prefs.col_go, W, 0.12))
  C.gold   = FUNC.col2im(prefs.col_gold)
  C.gold_soft = FUNC.col2im(prefs.col_gold, 56)
  C.danger   = FUNC.col2im(prefs.col_danger)
  C.danger_h = FUNC.col2im(mix(prefs.col_danger, W, 0.12))
  C.knob   = FUNC.rgba(242,242,244)                             -- fader/slider 把手 -- knob
  C.cb_line = FUNC.rgba(255,255,255,46)                         -- checkbox 外框 -- checkbox outline
end
FUNC.upd_colors()

-- 圓角三級（跟縮放）-- radius scale (follows UI scale)
function FUNC.rad(k) return FUNC.sz(k == "s" and 4 or k == "l" and 10 or 6) end

---------------------------------------------------------------------
-- 向量圖示（DrawList 畫，跟縮放、不靠字型符號）-- vector icons drawn with DrawList
-- name: play note stop pause fade group ungroup left right gear eye up down
---------------------------------------------------------------------
function FUNC.icon(dl, name, cx, cy, s, col)
  local h = s * 0.5
  local th = math.max(1, s / 10)
  if name == "play" then
    ImGui.DrawList_AddTriangleFilled(dl, cx - h*0.55, cy - h*0.75, cx + h*0.75, cy, cx - h*0.55, cy + h*0.75, col)
  elseif name == "stop" then
    ImGui.DrawList_AddRectFilled(dl, cx - h*0.6, cy - h*0.6, cx + h*0.6, cy + h*0.6, col, s*0.12)
  elseif name == "pause" then
    ImGui.DrawList_AddRectFilled(dl, cx - h*0.6, cy - h*0.65, cx - h*0.15, cy + h*0.65, col, s*0.08)
    ImGui.DrawList_AddRectFilled(dl, cx + h*0.15, cy - h*0.65, cx + h*0.6, cy + h*0.65, col, s*0.08)
  elseif name == "note" then
    ImGui.DrawList_AddCircleFilled(dl, cx - h*0.35, cy + h*0.45, h*0.32, col)
    ImGui.DrawList_AddLine(dl, cx - h*0.05, cy + h*0.45, cx - h*0.05, cy - h*0.7, col, th)
    ImGui.DrawList_AddLine(dl, cx - h*0.05, cy - h*0.7, cx + h*0.6, cy - h*0.4, col, th)
  elseif name == "fade" then
    ImGui.DrawList_AddBezierCubic(dl, cx - h*0.8, cy + h*0.55, cx, cy + h*0.55, cx, cy - h*0.55, cx + h*0.8, cy - h*0.55, col, th)
  elseif name == "group" then
    ImGui.DrawList_AddRect(dl, cx - h*0.75, cy - h*0.6, cx + h*0.75, cy + h*0.6, col, s*0.12, 0, th)
    ImGui.DrawList_AddLine(dl, cx - h*0.4, cy - h*0.12, cx + h*0.4, cy - h*0.12, col, th)
    ImGui.DrawList_AddLine(dl, cx - h*0.4, cy + h*0.22, cx + h*0.15, cy + h*0.22, col, th)
  elseif name == "ungroup" then
    ImGui.DrawList_AddRect(dl, cx - h*0.75, cy - h*0.6, cx + h*0.25, cy + h*0.2, col, s*0.1, 0, th)
    ImGui.DrawList_AddRect(dl, cx - h*0.25, cy - h*0.2, cx + h*0.75, cy + h*0.6, col, s*0.1, 0, th)
  elseif name == "left" or name == "right" then
    local d = (name == "left") and -1 or 1
    ImGui.DrawList_AddLine(dl, cx - d*h*0.25, cy - h*0.55, cx + d*h*0.3, cy, col, th*1.2)
    ImGui.DrawList_AddLine(dl, cx + d*h*0.3, cy, cx - d*h*0.25, cy + h*0.55, col, th*1.2)
  elseif name == "up" or name == "down" then
    local d = (name == "up") and -1 or 1
    ImGui.DrawList_AddLine(dl, cx - h*0.55, cy - d*h*0.25, cx, cy + d*h*0.3, col, th*1.2)
    ImGui.DrawList_AddLine(dl, cx, cy + d*h*0.3, cx + h*0.55, cy - d*h*0.25, col, th*1.2)
  elseif name == "undo" or name == "redo" then
    -- 彎箭頭 ↶ / ↷：上半圓弧 + 起點朝下的箭頭 -- curved arrow: top arc + downward head at the start
    local d = (name == "undo") and -1 or 1
    local acx, acy, r = cx, cy + h*0.2, h*0.55
    if d < 0 then
      ImGui.DrawList_PathArcTo(dl, acx, acy, r, math.pi, math.pi * 2)
    else
      ImGui.DrawList_PathArcTo(dl, acx, acy, r, 0, -math.pi)
    end
    ImGui.DrawList_PathStroke(dl, col, 0, th * 1.2)
    local tx = acx + d * r
    ImGui.DrawList_AddTriangleFilled(dl, tx - h*0.3, acy - h*0.05, tx + h*0.3, acy - h*0.05, tx, acy + h*0.4, col)
  elseif name == "gear" then
    -- 粗環 + 6 個貼著環的方齒，看起來是齒輪而不是太陽 -- thick ring with attached square teeth (reads as a gear, not a sun)
    ImGui.DrawList_AddCircle(dl, cx, cy, h*0.48, col, 0, h*0.32)
    for i = 0, 5 do
      local a = i * math.pi / 3 + math.pi / 6
      ImGui.DrawList_AddLine(dl, cx + math.cos(a)*h*0.55, cy + math.sin(a)*h*0.55, cx + math.cos(a)*h*0.9, cy + math.sin(a)*h*0.9, col, h*0.36)
    end
  end
end

---------------------------------------------------------------------
-- 統一按鈕（v2）-- unified button
-- kind: "neutral"（灰底）| "ghost"（透明，hover 才顯示）| "primary"（主色實心）| "danger"（紅色實心）
-- opts: icon, w, h, font, fsz, disabled, active(按下狀態/切換中), tip, radius
---------------------------------------------------------------------
-- 按鈕尺寸（ui_btn 與 ui_seg 共用）-- button metrics shared by ui_btn / ui_seg
local function btn_metrics(label, opts)
  local font, fsz = opts.font or FONT, opts.fsz or FUNC.sz(13)
  local isz = opts.isz or math.floor(fsz * 1.05)
  local gap = (opts.icon and label ~= "") and FUNC.sz(6) or 0
  ImGui.PushFont(ctx, font, fsz)
  local tw = (label ~= "") and ImGui.CalcTextSize(ctx, label, 0, 0) or 0
  ImGui.PopFont(ctx)
  local cw = (opts.icon and isz or 0) + gap + tw
  local w = opts.w or (cw + FUNC.sz(opts.icon and label == "" and 14 or 20))
  return w, cw, font, fsz, isz, gap
end

function FUNC.ui_btn(id, label, kind, opts)
  opts = opts or {}
  local h = opts.h or FUNC.sz(28)
  local w, cw, font, fsz, isz, gap = btn_metrics(label, opts)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local clicked = ImGui.InvisibleButton(ctx, id, w, h)
  local hov, act = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  local dis = opts.disabled
  local bg, fg
  if kind == "primary" then
    bg = (act and C.primary_hi) or (hov and C.primary_h) or C.primary; fg = FUNC.rgba(255,255,255)
  elseif kind == "go" then
    bg = (act and C.primary_hi) or (hov and C.go_h) or C.go; fg = FUNC.rgba(255,255,255)
  elseif kind == "danger" then
    bg = (act and C.danger_h) or (hov and C.danger_h) or C.danger; fg = FUNC.rgba(255,255,255)
  elseif kind == "seg" then
    bg = opts.active and C.primary_soft or (act and C.btn_a) or (hov and C.btn_h) or C.btn; fg = opts.active and C.primary_hi or C.text
  elseif kind == "ghost" then
    bg = opts.active and C.primary_soft or (act and C.ghost_a) or (hov and C.ghost_h) or 0; fg = opts.active and C.primary_hi or C.text
  else
    bg = opts.active and C.primary_soft or (act and C.btn_a) or (hov and C.btn_h) or C.btn; fg = opts.active and C.primary_hi or C.text
  end
  if dis then bg = (kind == "ghost") and 0 or ((C.btn & 0xFFFFFF00) | 110); fg = (fg & 0xFFFFFF00) | 90 end
  local dl = ImGui.GetWindowDrawList(ctx)
  local rad = opts.radius or (kind == "seg" and FUNC.rad("s") or FUNC.rad("m"))
  if bg ~= 0 then ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, FUNC.dim_c(bg), rad) end
  if kind == "neutral" or kind == nil then  -- 頂部細高光 + 外框 -- subtle top highlight + outline
    ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, FUNC.dim_c(C.line), rad, 0, 1)
  elseif kind == "primary" or kind == "go" or kind == "danger" then
    ImGui.DrawList_AddLine(dl, x + rad, y + 1, x + w - rad, y + 1, FUNC.rgba(255,255,255,30), 1)  -- 極淡頂部光 -- faint top sheen
  end
  local sx = x + math.floor((w - cw) / 2)
  if opts.icon then
    FUNC.icon(dl, opts.icon, sx + isz / 2, y + h / 2, isz, FUNC.dim_c(fg))
    sx = sx + isz + gap
  end
  if label ~= "" then
    ImGui.DrawList_AddTextEx(dl, font, fsz, sx, y + math.floor((h - fsz) / 2) - 1, FUNC.dim_c(fg), label)
  end
  if opts.tip and hov then ImGui.SetTooltip(ctx, opts.tip) end
  return clicked and not dis
end

-- 分段按鈕組：一個凹槽底 + 一排透明按鈕 -- segmented group: one well + ghost buttons
-- items: {{id=, label=, icon=, disabled=, tip=, active=}}; 回傳被按下的 index -- returns clicked index
function FUNC.ui_seg(items, opts)
  opts = opts or {}
  local h = opts.h or FUNC.sz(28)
  local pad = FUNC.sz(2)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  local gap = FUNC.sz(1)
  -- 先算總寬畫凹槽，再畫按鈕 -- measure total width, draw the well, then the buttons
  local bopts = {}
  local total = pad * 2 - gap
  for i, it in ipairs(items) do
    bopts[i] = {icon=it.icon, h=h - pad*2, disabled=it.disabled, tip=it.tip, active=it.active, fsz=opts.fsz}
    total = total + btn_metrics(it.label or "", bopts[i]) + gap
  end
  local rad = FUNC.rad("m") + pad
  ImGui.DrawList_AddRectFilled(dl, x, y, x + total, y + h, FUNC.dim_c(C.seg), rad)
  ImGui.DrawList_AddRect(dl, x, y, x + total, y + h, FUNC.dim_c(C.line2), rad, 0, 1)
  -- 每顆按鈕自己定位：用 SameLine 的話，這組前面若有 SameLine，第 2 顆起會少算 pad 而上浮
  -- position each button explicitly: SameLine after an outer SameLine drops the pad, so later buttons float up
  local hit
  local bx = x + pad
  for i, it in ipairs(items) do
    ImGui.SetCursorScreenPos(ctx, bx, y + pad)
    if FUNC.ui_btn(it.id, it.label or "", "ghost", bopts[i]) then hit = i end
    bx = bx + btn_metrics(it.label or "", bopts[i]) + gap
  end
  -- 讓版面認得整組的外框高度 -- register full group height for layout
  ImGui.SetCursorScreenPos(ctx, x, y); ImGui.Dummy(ctx, total, h)
  return hit
end

-- macOS 風格小勾選框：回傳 changed, new_value -- small macOS-style checkbox: returns changed, new_value
function FUNC.ui_check(id, val, sz)
  sz = sz or FUNC.sz(14)
  local fh = ImGui.GetFrameHeight(ctx)
  ImGui.SetCursorPosY(ctx, ImGui.GetCursorPosY(ctx) + math.floor((fh - sz) / 2))  -- 垂直置中 -- vertical center
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local clicked = ImGui.InvisibleButton(ctx, id, sz, sz)
  local hov = ImGui.IsItemHovered(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  local r = FUNC.sz(3.5)
  if val then
    ImGui.DrawList_AddRectFilled(dl, x, y, x + sz, y + sz, FUNC.dim_c(hov and C.primary_h or C.primary), r)
    local th = math.max(1.5, sz / 7)
    ImGui.DrawList_AddLine(dl, x + sz*0.25, y + sz*0.52, x + sz*0.43, y + sz*0.70, FUNC.rgba(255,255,255), th)
    ImGui.DrawList_AddLine(dl, x + sz*0.43, y + sz*0.70, x + sz*0.76, y + sz*0.32, FUNC.rgba(255,255,255), th)
  else
    ImGui.DrawList_AddRectFilled(dl, x, y, x + sz, y + sz, FUNC.dim_c(C.field), r)
    ImGui.DrawList_AddRect(dl, x, y, x + sz, y + sz, FUNC.dim_c(hov and C.line2 or C.cb_line), r, 0, 1)
  end
  if clicked then return true, not val end
  return false, val
end

-- 卡片外框（edit 面板各區塊）-- card frame for edit sections
function FUNC.ui_card(dl, x1, y1, x2, y2)
  ImGui.DrawList_AddRectFilled(dl, x1, y1, x2, y2, FUNC.dim_c(C.card), FUNC.rad("l"))
  ImGui.DrawList_AddRect(dl, x1, y1, x2, y2, FUNC.dim_c(C.line), FUNC.rad("l"), 0, 1)  -- 只留極淡外框，靠底色差分區 -- faint outline; contrast comes from fill
end

-- edit 各區塊預設識別色（右鍵可改）-- default identity color per edit section (right-click to change)
SEC_DEF_COL = {basic=0x002E9C9A, notes=0x00C9A23A, waveform=0x004A7FD6, route=0x008B6FD6, meter=0x003FA66B}

-- 讓淡底色不發灰：拉高飽和度＋略提亮（0x00RRGGBB 進出）-- keep soft tints lively: boost saturation + a bit of brightness
function FUNC.vivid(hex)
  local r, g, b = (hex>>16)&255, (hex>>8)&255, hex&255
  local m = (r + g + b) / 3
  local function f(v) return math.floor(FUNC.clamp((m + (v - m) * 1.6) * 1.25, 0, 255)) end  -- 飽和 ×1.6、亮度 ×1.25 -- saturation x1.6, brightness x1.25
  return (f(r)<<16)|(f(g)<<8)|f(b)
end

-- meter 填色：由下往上 主色→亮主色→金→紅 漸層，上下圓角（Route / Master 共用）
-- meter fill: bottom-up gradient primary→bright→gold→red with rounded ends (shared by Route / Master)
-- 圓角做法：上下兩端各畫一個圓角小塊，中間用 2px 橫條逐段上色 -- rounded caps + 2px gradient slices in between
function FUNC.draw_meter_fill(dl, x1, x2, fy, fh, pk_db)
  local lo, hi = prefs.vol_min, prefs.vol_max
  if pk_db <= lo or hi <= lo then return end
  local inset = math.max(1, math.floor((x2 - x1) * 0.12))
  x1, x2 = x1 + inset, x2 - inset
  local bot = fy + fh - inset
  local span = fh - inset * 2
  local top = math.floor(bot - span * FUNC.clamp((pk_db - lo) / (hi - lo), 0, 1))
  if bot - top < 1 then return end
  local function lerp(c1, c2, t)
    local o = 0
    for sh = 0, 24, 8 do
      local a, b = (c1 >> sh) & 255, (c2 >> sh) & 255
      o = o | (math.floor(a + (b - a) * t) << sh)
    end
    return o
  end
  local stops = {{lo, C.primary}, {-12, C.primary_hi}, {-6, C.gold}, {-1, C.danger}, {hi, C.danger}}
  local function col_at(y)  -- 螢幕 y → 該高度代表的 dB 顏色 -- color for the dB level at screen y
    local db = lo + (bot - y) / span * (hi - lo)
    for i = 1, #stops - 1 do
      local a, b = FUNC.clamp(stops[i][1], lo, hi), FUNC.clamp(stops[i+1][1], lo, hi)
      if db <= b and b > a then return lerp(stops[i][2], stops[i+1][2], FUNC.clamp((db - a) / (b - a), 0, 1)) end
    end
    return C.danger
  end
  local r = math.min(FUNC.sz(3), (x2 - x1) / 2, (bot - top) / 2)
  if bot - top <= r * 2 + 2 then
    ImGui.DrawList_AddRectFilled(dl, x1, top, x2, bot, col_at(top), r)
    return
  end
  ImGui.DrawList_AddRectFilled(dl, x1, bot - r * 2, x2, bot, col_at(bot), r, ImGui.DrawFlags_RoundCornersBottom())
  ImGui.DrawList_AddRectFilled(dl, x1, top, x2, top + r * 2, col_at(top), r, ImGui.DrawFlags_RoundCornersTop())
  local y = bot - r
  while y > top + r do
    local y2 = math.max(top + r, y - 2)
    ImGui.DrawList_AddRectFilled(dl, x1, y2, x2, y, col_at(y2))
    y = y2
  end
end

-- 10 group border colors (avoid Play/Stop/Pause/Fade hues)
GRP_COLS={
  FUNC.rgba(160,110,220), FUNC.rgba(220,100,160), FUNC.rgba(100,190,170),
  FUNC.rgba(200,160,90),  FUNC.rgba(110,200,110), FUNC.rgba(200,100,200),
  FUNC.rgba(170,150,100), FUNC.rgba(100,200,220), FUNC.rgba(180,210,100), FUNC.rgba(220,150,100)}

-- Cue color label presets (stored as 0x00RRGGBB) — 8色相×3深淺=24色
CUE_COLORS = {
    -- Dark 暗 (12色)
    {name="D.Red",       val=0x00581818},
    {name="D.Vermilion", val=0x00582418},
    {name="D.Orange",    val=0x00583818},
    {name="D.Yellow",    val=0x00504820},
    {name="D.Lime",      val=0x00305018},
    {name="D.Green",     val=0x00185818},
    {name="D.Teal",      val=0x00185848},
    {name="D.Cyan",      val=0x00185050},
    {name="D.Blue",      val=0x00182858},
    {name="D.Indigo",    val=0x00281858},
    {name="D.Purple",    val=0x00421858},
    {name="D.Pink",      val=0x00581838},
    -- Bright 亮 (12色)
    {name="Red",         val=0x00A83838},
    {name="Vermilion",   val=0x00A85030},
    {name="Orange",      val=0x00A86830},
    {name="Yellow",      val=0x00A09830},
    {name="Lime",        val=0x0060A030},
    {name="Green",       val=0x0038A038},
    {name="Teal",        val=0x0038A078},
    {name="Cyan",        val=0x0030A0A0},
    {name="Blue",        val=0x003850A8},
    {name="Indigo",      val=0x005038A8},
    {name="Purple",      val=0x008038A8},
    {name="Pink",        val=0x00A83868},
}

TYPE_COL = {}
TYPE_SHORT = {}
function FUNC.upd_types()
  -- v2：類型色收斂到主色/金/紅系，彩度降低 -- v2: type colors folded into the palette, lower chroma
  TYPE_COL={PLAY=C.primary_hi,STOP=C.danger,PAUSE=FUNC.rgba(201,170,90),FADE=C.gold,GROUP=C.dim,SPACER=C.dim,MIDI=FUNC.rgba(176,143,224)}
  TYPE_SHORT={PLAY="▶ Audio",STOP="■ Stop",PAUSE="‖ Pause",FADE="≈ Fade",GROUP="▣ Group",SPACER="—",MIDI="♪ MIDI"}
end; FUNC.upd_types()
-- cue 狀態機 + timer tag：值仍為字串（不破壞序列化），常數只是讀取入口避免 typo
-- state machine + timer tag constants. values remain strings so serialization unaffected.
STATE = {IDLE="idle", PREWAIT="prewait", RUNNING="running", DONE="done", POSTWAIT="postwait"}
TIMER = {PRE="pre", POST="post", FADE_SILENT="fade_silent"}

CURVES={"linear","scurve","expo"}
CURVE_N={linear="Linear",scurve="S-Curve",expo="Expo"}
-- 各曲線 amt 範圍 / 預設 / vdrag 速度 -- per-curve amt range/default/drag speed
CURVE_AMT={
  scurve = {lo=1.0, hi=8.0, def=2.5, spd=0.1},
  expo   = {lo=-10.0, hi=10.0, def=0.0, spd=0.15},
}
