-- ==========================================================================
-- Realive v0.96 - QLab-style Show Controller for REAPER
-- CF_Preview Engine + ReaImGui + Lyx + Claude(<< YOU ARE AWESOME)
-- ==========================================================================

version = 0.96

---------------------------------------------------------------------
-- DE-BUG
---------------------------------------------------------------------
function msg(message,detail,solo,symbol)

    if solo then reaper.ClearConsole() solo=nil end

    symbol=symbol or "\n"

    detail=(type(detail)=="number" and detail<=3 and detail) or 1

    if  detail<=0 then return end

    if  type(message)=="table" then

        function printTable(tbl, indent)
            if  not indent then indent = 0 end
            for k, v in pairs(tbl) do
                local Type=(detail>1 and type(v).." - ") or ""
                formatting = string.rep("     ", indent)
                if  type(v) == "table" then
                    reaper.ShowConsoleMsg(formatting.."{"..k.."}: ".."\n")
                    printTable(v, indent+1)
                else
                    reaper.ShowConsoleMsg(formatting.."["..k.."]: "..Type..tostring(v).."\n")
                end
            end
        end

        printTable(message)
        return
    else
        local fun={function(x) return ((type(x)=="number" and x%1~=0) and string.format("%.3f",x)) or tostring(x) end,
        type,
        function(x) return string.len(tostring(x)) end
    }
        for i=1,detail do
            if i>1 then
                reaper.ShowConsoleMsg("|")
            end
            reaper.ShowConsoleMsg(fun[i](message))
        end
        reaper.ShowConsoleMsg(symbol)
    end
end

---------------------------------------------------------------------
-- EXT STATE KEYS
---------------------------------------------------------------------
EXT = {
    PREFS   = "Realive_Prefs",
    SECTION = "Realive_Controller",
    KEY     = "CueListData",
    SHOWS   = "Realive_Shows"
}

---------------------------------------------------------------------
-- 0. DEPS
---------------------------------------------------------------------
if not reaper.ImGui_CreateContext then
  reaper.MB("NEED ReaImGui !","ReaImGui is not install in reaper ",0); return end
if not reaper.CF_CreatePreview then
  reaper.MB("NEED SWS Extension !","SWS Extension is not install in reaper",0); return end

FUNC = {}

---------------------------------------------------------------------
-- 1. IMGUI
---------------------------------------------------------------------
ImGui = {}
setmetatable(ImGui,{__index=function(_,k) return reaper["ImGui_"..k] end})
-- 建立（或重建）ImGui 視窗環境。畫面繪製出錯時會重建一份乾淨的，見 main_loop
-- create (or re-create) the ImGui context. After a drawing error a clean one is built again, see main_loop
local function make_ctx()
  ctx = ImGui.CreateContext("Realive")
  local flags = ImGui.GetConfigVar(ctx, ImGui.ConfigVar_Flags())
  flags = flags  &~ ImGui.ConfigFlags_NavEnableKeyboard()
  ImGui.SetConfigVar(ctx, ImGui.ConfigVar_Flags(), flags)
  -- 只允許從標題列拖曳視窗 -- only allow window dragging from title bar
  ImGui.SetConfigVar(ctx, ImGui.ConfigVar_WindowsMoveFromTitleBarOnly(), 1)
  if FONT then ImGui.Attach(ctx,FONT); ImGui.Attach(ctx,FONT_B); ImGui.Attach(ctx,FONT_MONO); ImGui.Attach(ctx,FONT_NOTE) end
end
make_ctx()

FONT = ImGui.CreateFont("sans-serif")
FONT_B = ImGui.CreateFont("sans-serif",ImGui.FontFlags_Bold())
FONT_MONO = ImGui.CreateFont("Inconsolata Condensed",ImGui.FontFlags_Bold())
-- SMuFL音符字體：檢查檔案存在再載入，fallback到sans-serif -- music notation font with fallback
local leland_path = "/Library/Fonts/Leland.otf"
local leland_f = io.open(leland_path, "r")
if leland_f then leland_f:close(); FONT_NOTE = ImGui.CreateFontFromFile(leland_path)
else FONT_NOTE = ImGui.CreateFont("sans-serif") end
ImGui.Attach(ctx,FONT); ImGui.Attach(ctx,FONT_B); ImGui.Attach(ctx,FONT_MONO); ImGui.Attach(ctx,FONT_NOTE)

---------------------------------------------------------------------
-- LOAD SRC FILES
---------------------------------------------------------------------
local info = debug.getinfo(1, "S")
local SCRIPT_DIR = info.source:match("@(.+[/\\])") or ""

dofile(SCRIPT_DIR .. "src/config.lua")
dofile(SCRIPT_DIR .. "src/state.lua")
dofile(SCRIPT_DIR .. "src/engine.lua")
dofile(SCRIPT_DIR .. "src/cue.lua")
dofile(SCRIPT_DIR .. "src/midi.lua")
dofile(SCRIPT_DIR .. "src/midi_editor.lua")
dofile(SCRIPT_DIR .. "src/io.lua")
dofile(SCRIPT_DIR .. "src/ui_interact.lua")
dofile(SCRIPT_DIR .. "src/ui_table.lua")
dofile(SCRIPT_DIR .. "src/ui_bars.lua")
dofile(SCRIPT_DIR .. "src/ui_popups.lua")
dofile(SCRIPT_DIR .. "src/ui_edit.lua")
dofile(SCRIPT_DIR .. "src/ui_edit_basic.lua")
dofile(SCRIPT_DIR .. "src/ui_edit_note.lua")
dofile(SCRIPT_DIR .. "src/ui_edit_waveform.lua")
dofile(SCRIPT_DIR .. "src/ui_edit_route.lua")
dofile(SCRIPT_DIR .. "src/ui_edit_meter.lua")
dofile(SCRIPT_DIR .. "src/waveform.lua")
dofile(SCRIPT_DIR .. "src/envelope.lua")
FUNC.update_env_bounds()  -- sync ENV_MIN/MAX_DB with prefs after envelope.lua loaded
dofile(SCRIPT_DIR .. "src/keys.lua")
dofile(SCRIPT_DIR .. "src/cleanup.lua")

---------------------------------------------------------------------
-- 22. MAIN LOOP
---------------------------------------------------------------------
-- 引擎部分（不畫任何東西）：專案切換偵測 + 計時器/淡出/播完偵測/envelope
-- engine part (draws nothing): project-switch detection + timers / fades / end detection / envelopes
local function engine_frame()
  -- 偵測 REAPER project 切換：自動儲存(含timestamp備份)+重新載入 -- detect project switch: auto-save with timestamp + reload
  local cur_proj = reaper.EnumProjects(-1)
  if _last_proj and cur_proj ~= _last_proj then
    FUNC.hard_stop_all()       -- 停止所有播放 + 還原軌道/MIDI（還到原本的專案）-- stop everything + restore tracks/MIDI (into the project they belong to)
    -- 舊專案的偏好存回舊專案；舊專案已關閉就只存全域的 -- old project's prefs go back into the old project; if it was closed, only global prefs are saved
    local old_ok = reaper.ValidatePtr2 and reaper.ValidatePtr2(0, _last_proj, "ReaProject*")
    FUNC.save_prefs(old_ok and _last_proj or false)
    -- 比對快照決定是否備份：序列化不同才存 -- only auto-backup if data actually changed
    local cur_serial = {}; for _,c in ipairs(cues) do cur_serial[#cur_serial+1] = FUNC.c2s(c) end
    local cur_str = table.concat(cur_serial, "\n")
    if cur_str ~= _proj_snapshot then
      FUNC.auto_save_timestamp()
    end
    -- 清除所有runtime狀態 -- clear ALL runtime state for clean switch
    track_warns = {}
    collapsed_groups = {}
    active_fades = {}; active_timers = {}; active_previews = {}
    paused_cues = {}; cancelled_fades = {}; soft_kill = {}
    selected = {}; last_click = 0; next_go = 0; next_go_hidden = false
    ie = {active=false,row=0,col="",buf="",t=0}
    popup.warn = false; popup.warn_missing = false; popup.trim = false; popup.fade_edit = false
    popup.settings = false; popup.save = false; popup.load = false; popup.shortcuts = false
    dur_cache = {}; id_map = {}
    -- _realive_tracks 是 project-specific GUID 集合，切 project 必須清 -- per-project, must reset
    _realive_tracks = {}
    -- 拖曳/marquee/envelope 等暫態：切 project 卡在中途會操作不存在的 ci -- transient drags
    drag = {src_ci=nil,cue_id=nil,backup=nil,multi=false,block_n=1,click_off=0,pending_desel_ci=nil,vol_ci=nil}
    marquee_state = {}
    fx_env_drag = {}; fx_env_pending = nil; fx_env_missing_warn = nil
    if wf_handle then wf_handle.dragging = nil end
    if FUNC.wf_sel_clear then FUNC.wf_sel_clear() end
    if env_drag then
      env_drag.active=false; env_drag.pt_idx=nil; env_drag.edit_idx=nil
      env_drag.lock=nil; env_drag.marquee=false; env_drag.sel={}
    end
    -- 載入新project的cues和per-project設定 -- load new project's cues + per-project prefs
    FUNC.load_prefs()  -- 重新載入per-project prefs -- reload per-project prefs
    FUNC.update_env_bounds()  -- sync ENV_MIN/MAX_DB
    FUNC.load_cues()
    _scroll_to_next_go = true  -- project 切換後重新對齊
    dirty = false
    selected = {}
    if next_go < 1 and #cues > 0 then next_go = 1 end
    if next_go >= 1 then FUNC.sel1(next_go) end
    -- 記錄新project的快照 -- snapshot new project's data for next switch comparison
    local new_serial = {}; for _,c in ipairs(cues) do new_serial[#new_serial+1] = FUNC.c2s(c) end
    _proj_snapshot = table.concat(new_serial, "\n")
  end
  _last_proj = cur_proj
  FUNC.engine_tick()
end

-- 出錯橫幅：最近 15 秒內有錯誤就顯示一行紅字（程式仍在運作）-- fault banner: one red line while an error happened in the last 15 s (the script keeps running)
local function draw_fault_banner()
  if not fault.msg or reaper.time_precise() - fault.t > 15 then return end
  ImGui.TextColored(ctx, FUNC.rgba(255, 90, 90, 255),
    string.format("Internal error #%d in %s - ReaLive keeps running. Details: REAPER console (View > Show console).", fault.n, fault.where or "?"))
  ImGui.SameLine(ctx)
  if ImGui.SmallButton(ctx, "Dismiss##fault") then fault.msg = nil end
end

-- 畫面部分：回傳視窗是否仍開著 -- UI part: returns whether the window is still open
local function ui_frame()
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg(), C.bg)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg(), FUNC.rgba(50,50,62))
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered(), FUNC.rgba(65,65,80))
  ImGui.PushStyleColor(ctx, ImGui.Col_Header(), FUNC.rgba(60,60,90))
  ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered(), FUNC.rgba(70,70,110))
  ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive(), FUNC.rgba(80,80,130))
  ImGui.PushStyleColor(ctx, ImGui.Col_TableHeaderBg(), C.header)
  ImGui.PushStyleColor(ctx, ImGui.Col_TableRowBg(), C.row)
  ImGui.PushStyleColor(ctx, ImGui.Col_TableRowBgAlt(), C.row_a)
  ImGui.PushStyleColor(ctx, ImGui.Col_Separator(), C.bdr)
  ImGui.PushStyleColor(ctx, ImGui.Col_TableBorderStrong(), C.bdr)
  ImGui.PushStyleColor(ctx, ImGui.Col_TableBorderLight(), C.bdr)
  ImGui.PushStyleColor(ctx, ImGui.Col_Border(), C.bdr)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text(), C.text)
  ImGui.PushStyleColor(ctx, ImGui.Col_TitleBgCollapsed(), FUNC.rgba(180, 110, 30, 255))  -- 摺疊時亮橘色標題列 -- bright orange collapsed title
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding(), 6)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding(), 5)  -- 加大導角 -- increased rounding
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_GrabRounding(), 4)   -- slider/drag handle 導角 -- grab rounding
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding(), 6, 6)

  local modal_open = popup.warn or popup.settings or popup.save or popup.load or popup.reset_mode
  ImGui.PushFont(ctx, FONT, FUNC.sz(15))
  ImGui.SetNextWindowSize(ctx, FUNC.sz(1200), FUNC.sz(660), ImGui.Cond_FirstUseEver())
  local window_flags = ImGui.WindowFlags_NoScrollbar() | ImGui.WindowFlags_NoScrollWithMouse()
  -- reset mode或滑鼠仍按住時完全鎖定（含標題列） -- lock window completely during reset mode
  if popup.reset_mode or popup.reset_mouse_hold then
    window_flags = window_flags | ImGui.WindowFlags_NoMove()
  end
  -- 標題列：project name放進window title確保收合也顯示 -- include project name in window title for collapsed visibility
  local proj_name = reaper.GetProjectName(0)
  if proj_name ~= "" then proj_name = proj_name:gsub("%.[^%.]+$", "") else proj_name = "Untitled" end
  local sname = (show_name ~= "") and show_name or "Unsaved"
  local modified = dirty and " [modified]" or ""
  local win_title = "Realive v" .. version .. "###Realive"
  -- title bar文字固定色，不跟C.text變動；收合時標題列亮橘色更醒目 -- fixed title text color; orange title bar when collapsed
  ImGui.PushStyleColor(ctx, ImGui.Col_Text(), FUNC.rgba(180,180,190,255))
  local vis, op = ImGui.Begin(ctx, win_title, true, window_flags)
  ImGui.PopStyleColor(ctx, 1)
  -- 視窗有焦點時攔截REAPER全域快捷鍵，避免衝突（含所有popup視窗）-- capture keyboard when any Realive window focused
  if ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_AnyWindow()) then
    ImGui.SetNextFrameWantCaptureKeyboard(ctx, true)
  end
  if not vis then
    -- 收合時用ForegroundDrawList畫亮橘色標題列背景 -- bright orange title bar when collapsed
    local wx, wy = ImGui.GetWindowPos(ctx)
    local ww, wh = ImGui.GetWindowSize(ctx)
    local col_dl = ImGui.GetForegroundDrawList(ctx)
    ImGui.PushFont(ctx, FONT_B, FUNC.sz(15))
    local ct_txt = "Realive  |  " .. proj_name .. "  -  " .. sname .. modified
    local ct_tw, ct_th = ImGui.CalcTextSize(ctx, ct_txt, 0, 0)
    local pad = FUNC.sz(20)
    local draw_w = math.max(ww, ct_tw + pad * 2)  -- 確保橘色bar至少跟文字一樣寬 -- ensure bar is wide enough for text
    ImGui.DrawList_AddRectFilled(col_dl, wx, wy, wx + draw_w, wy + wh, FUNC.rgba(220, 140, 40, 200), 6)
    local ct_x = wx + (draw_w - ct_tw) * 0.5
    local ct_y = wy + (wh - ct_th) * 0.5
    ImGui.DrawList_AddTextEx(col_dl, FONT_B, FUNC.sz(15), ct_x, ct_y, FUNC.rgba(255, 255, 255, 255), ct_txt)
    ImGui.PopFont(ctx)
  end
  -- 標題列project name居中（展開時用ForegroundDrawList覆蓋，收合時靠原生title顯示）-- centered title overlay (expanded only)
  local title_center_text = proj_name .. "  -  " .. sname .. modified
  if vis then
    -- 展開時標題列居中覆蓋 -- centered title overlay when expanded
    local wx, wy = ImGui.GetWindowPos(ctx)
    local ww, _ = ImGui.GetWindowSize(ctx)
    local title_dl = ImGui.GetForegroundDrawList(ctx)
    local tc_tw, tc_th = ImGui.CalcTextSize(ctx, title_center_text, 0, 0)
    local tc_x = wx + (ww - tc_tw) * 0.5
    local _, cs_y = ImGui.GetCursorStartPos(ctx)
    local tb_h = cs_y - 6
    local tc_y = wy + (tb_h - tc_th) * 0.5
    local title_col = modal_open and FUNC.rgba(200,200,210,60) or FUNC.rgba(200,200,210,255)  -- modal時標題也dim -- dim title when modal
    ImGui.DrawList_AddTextEx(title_dl, FONT, FUNC.sz(15), tc_x, tc_y, title_col, title_center_text)
    FUNC.handle_keys(); FUNC.draw_toolbar(); draw_fault_banner(); ImGui.Spacing(ctx)
    -- column寬度共用：table永遠在同一個child裡 -- shared column widths via same child window
    local _, avail_h = ImGui.GetContentRegionAvail(ctx)
    local btm_h = FUNC.sz(56)
    local _, sp_y = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing())
    if popup.edit then
      local gap = FUNC.sz(4)
      local drag_h = FUNC.sz(6)  -- 拖曳區高度 -- drag handle height
      -- 扣掉 bottom bar + item spacings + gap + drag handle
      local content_h = avail_h - btm_h - sp_y * 4 - gap - drag_h
      local edit_h = math.floor(content_h * edit_ratio)
      local table_h = content_h - edit_h
      -- 上方：cue table -- top: cue table (always same child ID)
      if ImGui.BeginChild(ctx, "##cue_child", -1, table_h) then
        FUNC.draw_cue_table()
        ImGui.EndChild(ctx)
      end
      FUNC.handle_file_drop()
      -- 拖曳分隔條：滑鼠變雙箭頭可上下拖 -- drag separator for resizing edit panel
      ImGui.Dummy(ctx, 0, gap)
      local dx, dy = ImGui.GetCursorScreenPos(ctx)
      local dw = ImGui.GetContentRegionAvail(ctx)
      ImGui.InvisibleButton(ctx, "##edit_drag", dw, drag_h)
      local drag_hov = ImGui.IsItemHovered(ctx)
      local drag_act = ImGui.IsItemActive(ctx)
      if drag_hov or drag_act then ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS()) end
      if drag_act then
        local _, mouse_dy = ImGui.GetMouseDelta(ctx)
        if mouse_dy ~= 0 then
          edit_ratio = FUNC.clamp(edit_ratio - mouse_dy / content_h, 0.25, 0.65)  -- 最小1/4視窗高度 -- min 1/4 window height
        end
        edit_drag = true
      elseif edit_drag then
        -- 拖曳結束，儲存高度比例 -- drag ended, persist height ratio
        edit_drag = false
        prefs.edit_ratio = math.floor(edit_ratio * 100 + 0.5)
        FUNC.save_prefs()
      end
      -- 分隔條視覺：hover/drag時亮色 -- separator visual feedback
      local sep_dl = ImGui.GetWindowDrawList(ctx)
      local sep_col = (drag_hov or drag_act) and FUNC.rgba(100,100,130) or FUNC.rgba(55,55,70)
      ImGui.DrawList_AddRectFilled(sep_dl, dx, dy, dx + dw, dy + drag_h, sep_col, 2)
      -- 下方：edit panel -- bottom: edit panel
      ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg(), FUNC.rgba(30,30,40))
      if ImGui.BeginChild(ctx, "##edit_child", -1, edit_h, ImGui.ChildFlags_Borders(), ImGui.WindowFlags_NoScrollbar() | ImGui.WindowFlags_NoScrollWithMouse()) then
        FUNC.draw_edit_panel_inline()
        ImGui.EndChild(ctx)
      end
      ImGui.PopStyleColor(ctx, 1)
    else
      -- 收合時也用同一個child ID，讓column寬度共用
      local table_h = avail_h - btm_h - sp_y
      if ImGui.BeginChild(ctx, "##cue_child", -1, table_h) then
        FUNC.draw_cue_table()
        ImGui.EndChild(ctx)
      end
      FUNC.handle_file_drop()
    end
    FUNC.draw_bottom()
    ImGui.End(ctx)
  end
  FUNC.draw_settings(); FUNC.draw_output_maps(); FUNC.draw_save_popup(); FUNC.draw_load_popup(); FUNC.draw_trim(); FUNC.draw_fade_edit(); FUNC.draw_warn_popup(); FUNC.draw_warn_missing_popup(); FUNC.draw_fx_env_missing_popup(); FUNC.draw_sel_paste_popup()

  ImGui.PopFont(ctx); ImGui.PopStyleVar(ctx, 4); ImGui.PopStyleColor(ctx, 15)
  return op
end

-- 安全模式：正常畫面連續出錯 3 次時改畫這個極簡視窗。聲音、計時器照常；仍可 GO / PANIC。
-- safe mode: after 3 drawing errors in a row this minimal window replaces the normal one. Sound and timers carry on; GO / PANIC still work.
local ui_fail_streak = 0
local function fallback_frame()
  ImGui.SetNextWindowSize(ctx, 560, 0, ImGui.Cond_Always())
  local vis, op = ImGui.Begin(ctx, "ReaLive - safe mode###RealiveSafe", true)
  if vis then
    ImGui.TextWrapped(ctx, "The ReaLive window hit an error 3 times in a row and switched to safe mode. Sound and timers keep running.")
    ImGui.TextWrapped(ctx, (tostring(fault.msg or ""):match("^[^\n]*") or ""))
    ImGui.Spacing(ctx)
    if ImGui.Button(ctx, "GO (Space)") or ImGui.IsKeyPressed(ctx, ImGui.Key_Space(), false) then FUNC.go_next() end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "PANIC (Esc)") or ImGui.IsKeyPressed(ctx, ImGui.Key_Escape(), false) then FUNC.panic() end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Try the normal window again") then ui_fail_streak = 0 end
    ImGui.End(ctx)
  end
  return op
end

local function quit()
  FUNC.shutdown_safe()   -- 停聲 + MIDI 收尾 + 還原軌道 + 還原 Anticipative FX -- stop sound, finish MIDI, restore tracks and Anticipative FX
  pcall(FUNC.save_cues)
end

-- 主迴圈：引擎與畫面分開保護。任何一邊出錯都不會讓腳本停掉：
--   引擎出錯 → 這一幀剩下的引擎工作略過，下一幀照常
--   畫面出錯 → 重建乾淨的視窗環境再畫；連續 3 次就進安全模式
-- main loop: engine and UI are guarded separately, so an error in either one cannot kill the script:
--   engine error → the rest of this frame's engine work is skipped, next frame runs as usual
--   UI error     → a clean ImGui context is rebuilt; 3 in a row switches to safe mode
function main_loop()
  local want_quit = false
  pcall(function()
    want_quit = ImGui.IsKeyPressed(ctx, ImGui.Key_Q()) and ImGui.IsKeyDown(ctx, ImGui.Mod_Shift()) and ImGui.IsKeyDown(ctx, ImGui.Mod_Super())
  end)
  if want_quit then quit(); return end

  FUNC.safe_frame(engine_frame, "engine")

  local keep = true
  if ui_fail_streak < 3 then
    if FUNC.safe_frame(function() keep = ui_frame() end, "window") then ui_fail_streak = 0
    else ui_fail_streak = ui_fail_streak + 1; pcall(make_ctx) end
  elseif not FUNC.safe_frame(function() keep = fallback_frame() end, "safe-mode window") then
    quit(); return  -- 連安全模式都畫不出來：乾淨收尾後結束 -- even safe mode cannot draw: clean up and end
  end
  if keep then reaper.defer(main_loop) else quit() end
end

---------------------------------------------------------------------
-- Anticipative FX 暫存/還原：Realive 開啟時關閉（避免播放延遲），關閉時還原
-- workrender bit &1 = Anticipative FX on/off (Reaper-ConfigVariables-Documentation.txt:6818)
---------------------------------------------------------------------
local _afx_orig = nil
function FUNC.afx_stash_and_disable()
  if _afx_orig ~= nil then return end  -- 已 stash 過 -- already stashed
  if not reaper.SNM_GetIntConfigVar then return end  -- SWS 未安裝就跳過 -- SWS missing: skip
  _afx_orig = reaper.SNM_GetIntConfigVar("workrender", -1)
  if _afx_orig < 0 then _afx_orig = nil; return end
  if (_afx_orig & 1) ~= 0 then  -- 目前是開的才需關 -- only clear if currently on
    reaper.SNM_SetIntConfigVar("workrender", _afx_orig & (~1))
  end
end
function FUNC.afx_restore()
  if _afx_orig == nil then return end
  if reaper.SNM_SetIntConfigVar then reaper.SNM_SetIntConfigVar("workrender", _afx_orig) end
  _afx_orig = nil
end

---------------------------------------------------------------------
-- 23. INIT
---------------------------------------------------------------------
reaper.ClearConsole()

FUNC.load_cues()
_scroll_to_next_go = true  -- 啟動後 scroll 到 next_go
do -- Restore group color index from existing GROUP cues
  local grp_cc_idx = FUNC.get_grp_cc_idx()
  for _,c in ipairs(cues) do
    if c.type=="GROUP" and c.cue_color and c.cue_color~=0 then
      for idx,cc in ipairs(CUE_COLORS) do
        if cc.val==c.cue_color and idx>grp_cc_idx then grp_cc_idx=idx end
      end
    end
  end
  FUNC.set_grp_cc_idx(grp_cc_idx)
end
if next_go < 1 and #cues > 0 then next_go = 1 end
if next_go >= 1 then FUNC.sel1(next_go) end
_last_proj = reaper.EnumProjects(-1)  -- 記錄初始 project pointer
do local s={}; for _,c in ipairs(cues) do s[#s+1]=FUNC.c2s(c) end; _proj_snapshot=table.concat(s,"\n") end  -- 初始快照

FUNC.afx_stash_and_disable()
reaper.atexit(function() FUNC.shutdown_safe() end)  -- 保險：腳本以任何方式結束都會停聲並還原（可重複執行）-- safety net: however the script ends, stop sound and restore (safe to run twice)
reaper.defer(main_loop)
