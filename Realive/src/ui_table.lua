-- ==========================================================================
-- ui_table.lua — Cue Table Rendering
-- ==========================================================================

---------------------------------------------------------------------
-- 15. CUE TABLE
---------------------------------------------------------------------
-- Stable group color mapping
local grp_color_map={}; local grp_color_counter=0
local name_marquee = {}  -- ci -> {t_hover=time, t_scroll=time|nil} -- Name欄跑馬燈狀態 -- name column marquee state
local hdr_drag_src = nil  -- column reorder拖曳中的來源欄index -- source column index during header drag
local DD_MARQUEE_SPEED = 70   -- dropdown跑馬燈速度（px/s before sz()）-- dropdown marquee speed
local DD_POPUP_W       = 325  -- dropdown popup固定寬度（before sz()）-- dropdown popup fixed width
local DD_POPUP_ROWS    = 15   -- dropdown popup最多顯示幾列 -- dropdown popup max visible rows

function FUNC.grp_text_color(hex)
  local r = (hex >> 16) & 0xFF
  local g = (hex >> 8) & 0xFF
  local b = hex & 0xFF
  local lum = r * 0.299 + g * 0.587 + b * 0.114
  local f = lum > 100 and 0.45 or 2.2
  function cl(v) return math.min(255, math.max(0, math.floor(v * f))) end
  return FUNC.rgba(cl(r), cl(g), cl(b), 255)
end

function FUNC.get_grp_color(gid)
  local _,gc = FUNC.find_id(gid)
  if gc and gc.cue_color and gc.cue_color > 0 then
    return FUNC.col2im(gc.cue_color, 255)
  end
  if not grp_color_map[gid] then
    grp_color_counter=grp_color_counter+1
    grp_color_map[gid]=((grp_color_counter-1)%10)+1
  end
  return GRP_COLS[grp_color_map[gid]]
end

function FUNC.get_grp_text_color(gid)
  local _,gc = FUNC.find_id(gid)
  if gc and gc.cue_color and gc.cue_color > 0 then
    return FUNC.grp_text_color(gc.cue_color)
  end
  return FUNC.get_grp_color(gid)
end

function FUNC.target_label(c)
  if c.target_cue_id=="" then return "--" end
  local ti,tc=FUNC.find_id(c.target_cue_id)
  if not tc then return "(?)" end
  if tc.type=="GROUP" then return "G.".. (tc.name~="" and tc.name or tc.cue_number) end
  -- Q number為空時顯示Tr.n -- show track number when cue number is empty
  if tc.cue_number=="" then return "Tr."..tostring((tc.track_idx or 0)+1) end
  return "Q."..tc.cue_number end

function FUNC.nav_check(ci, col)
  if type(tbl) ~= "table" then return end  -- defensive: tbl somehow non-table; restore on next state.lua run
  if tbl.nav_row == ci and tbl.nav_col == col then
   ImGui.SetKeyboardFocusHere(ctx)
  end
end
function FUNC.nav_track(col)
  if type(tbl) ~= "table" then return end
  if ImGui.IsItemFocused(ctx) then tbl.nav_col = col end
end

function FUNC.draw_cue_table()

  ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered(), C.header)
  ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive(), C.header)

  local tfl = ImGui.TableFlags_ScrollY() | ImGui.TableFlags_RowBg()
            | ImGui.TableFlags_BordersInnerH() | ImGui.TableFlags_Resizable()
            | ImGui.TableFlags_SizingFixedFit() | ImGui.TableFlags_Reorderable()

  ImGui.PushFont(ctx, FONT, FUNC.sz(13))
  local tbl_sx, _ = ImGui.GetCursorScreenPos(ctx)
  local tbl_w, _  = ImGui.GetContentRegionAvail(ctx)

  -- table永遠在child內，高度0填滿 -- table always inside child, height fills
  local tbl_h = 0
  if not ImGui.BeginTable(ctx, "CL", 13, tfl, -1, tbl_h) then
    ImGui.PopFont(ctx); ImGui.PopStyleColor(ctx, 2); return end

  -- === 平滑滾動：已停用，交由ImGui原生處理 ===
  -- smooth scroll: disabled, using native ImGui scrolling

  ImGui.TableSetupScrollFreeze(ctx, 0, 1)
  ImGui.TableSetupColumn(ctx, ">>",        ImGui.TableColumnFlags_NoResize(), FUNC.sz(24))
  ImGui.TableSetupColumn(ctx, "Cue",      0, FUNC.sz(36))
  ImGui.TableSetupColumn(ctx, "Type",     0, FUNC.sz(80))
  ImGui.TableSetupColumn(ctx, "Name",     0, FUNC.sz(160))
  ImGui.TableSetupColumn(ctx, "Target",   0, FUNC.sz(55))
  ImGui.TableSetupColumn(ctx, "Volume",   0, FUNC.sz(80))
  ImGui.TableSetupColumn(ctx, "Pre-Wait", 0, FUNC.sz(88))
  ImGui.TableSetupColumn(ctx, "Duration", ImGui.TableColumnFlags_WidthFixed() | ImGui.TableColumnFlags_NoResize(), FUNC.sz(110))
  ImGui.TableSetupColumn(ctx, "Post-Wait",0, FUNC.sz(88))
  ImGui.TableSetupColumn(ctx, "Auto",     ImGui.TableColumnFlags_NoResize(), FUNC.sz(48))
  ImGui.TableSetupColumn(ctx, "Kill",     ImGui.TableColumnFlags_NoResize(), FUNC.sz(44))
  ImGui.TableSetupColumn(ctx, "Loop",     ImGui.TableColumnFlags_NoResize(), FUNC.sz(42))
  ImGui.TableSetupColumn(ctx, "Notes",    ImGui.TableColumnFlags_WidthStretch(), 0)

  -- 逐欄TableHeader啟用reorder拖曳，DrawList覆蓋自訂文字 -- per-column TableHeader for reorder, DrawList overlay for custom text
  ImGui.TableNextRow(ctx, ImGui.TableRowFlags_Headers())
  local dl = ImGui.GetWindowDrawList(ctx)
  local hdrs = {">>","Cue","Type","Name","Target","Volume","Pre-Wait","Duration","Post-Wait","Auto⇡","Kill⇡","Loop","Notes"}
  local tips = {
    "GO indicator: ▶ marks the next cue to fire",
    "Cue number (auto-renumbered; click to edit)",
    "Cue type (PLAY / STOP / PAUSE / FADE / GROUP / SPACER)",
    "Cue name (click to edit)",
    "Target track / cue (PLAY = source track, STOP/PAUSE/FADE = target cue)",
    "Volume (drag to adjust, double-click to type)",
    "Pre-Wait: delay before this cue plays (time / BPM mode)",
    "Duration: trim start/end · click to edit, double-click trim handle to reset",
    "Post-Wait: delay before auto-follow fires the next cue",
    "Auto-go: play after previous cue finishes",
    "Kill Above: stop all playing cues above",
    "Loop: restart when finished (won't trigger auto-follow)",
    "Notes (free text)"}
  -- 可重置的欄位(hi→reset function) -- resettable columns
  local reset_cols = {
    [1]=function(c) c.cue_number="" end,  -- Cue: 清空編號 -- clear cue numbers
    [3]=function(c) c.name="" end,
    [5]=function(c) c.volume=0 end,
    [6]=function(c) c.pre_wait=0; c.pre_bpm_beats=4; c.pre_bpm_val=120; c.pre_wait_mode="time" end,
    [7]=function(c) c.trim_start=0; c.trim_end=0; c.fade_time=prefs.default_fade_time or 3.0 end,
    [8]=function(c) c.post_wait=0; c.post_bpm_beats=4; c.post_bpm_val=120; c.post_wait_mode="time" end,
    [9]=function(c) c.auto_go=false end,
    [10]=function(c) c.kill_above=false end,
    [11]=function(c) c.loop=false; c.loop_count=0; c.loop_done=nil end,
    [12]=function(c) c.notes="" end,
  }
  local now_t = reaper.time_precise()
  local rm = popup.reset_mode  -- shorthand
  local mx, my = ImGui.GetMousePos(ctx)
  local hdr_rh = FUNC.sz(20)
  -- 隱藏原生header文字色，逐欄呼叫TableHeader註冊reorder -- hide native text, per-column TableHeader for reorder
  ImGui.PushStyleColor(ctx, ImGui.Col_Text(), 0)
  local hdr_rects = {}  -- hi -> {x, y, w, h} 每欄header位置，供reset mode使用 -- per-column header rect for reset mode
  local pending_hdr_tip = nil
  for hi = 0, 12 do
    ImGui.TableSetColumnIndex(ctx, hi)
    local hx, hy = ImGui.GetCursorScreenPos(ctx)
    local cw = ImGui.GetContentRegionAvail(ctx)
    hdr_rects[hi] = {x=hx, y=hy, w=cw, h=hdr_rh}
    if rm or popup.reset_mouse_hold then
      -- reset mode或滑鼠仍按住：所有header用InvisibleButton，避免觸發column reorder
      -- reset mode or mouse still held: all headers use InvisibleButton to prevent column reorder
      ImGui.InvisibleButton(ctx, "##rst"..hi, cw, hdr_rh)
      if rm and reset_cols[hi] then
        -- highlight框延後到遮罩之後繪製（fg DrawList），避免被遮罩蓋住
        -- highlight border deferred to after dim overlay (fg DrawList) so it's not covered
        hdr_rects[hi].hov = mx >= hx and mx <= hx + cw and my >= hy and my <= hy + hdr_rh
      end
    else
      ImGui.TableHeader(ctx, hdrs[hi+1])  -- 註冊reorder拖曳 -- register reorder drag
      -- 追蹤column reorder拖曳來源（IsItemClicked只觸發一次，持續靠IsMouseDown）
      -- track drag source (IsItemClicked fires once, persist via IsMouseDown)
      if ImGui.IsItemClicked(ctx, 0) then hdr_drag_src = hi end
    end
    -- DrawList覆蓋自訂置中文字（用ItemRect精確垂直置中）
    -- overlay custom centered text (use ItemRect for precise vertical centering)
    local ir_x1, ir_y1 = ImGui.GetItemRectMin(ctx)
    local ir_x2, ir_y2 = ImGui.GetItemRectMax(ctx)
    local ir_w, ir_h = ir_x2 - ir_x1, ir_y2 - ir_y1
    local tw, th = ImGui.CalcTextSize(ctx, hdrs[hi+1], 0, 0)
    ImGui.DrawList_AddText(dl, ir_x1 + math.max(0, (ir_w - tw) * 0.5), ir_y1 + (ir_h - th) * 0.5, C.column_title, hdrs[hi+1])
    if not rm and tips[hi+1] then
      if mx >= ir_x1 and mx <= ir_x2 and my >= ir_y1 and my <= ir_y2 then
        pending_hdr_tip = tips[hi+1]
      end
    end
  end
  ImGui.PopStyleColor(ctx, 1)
  -- 在 PopStyleColor 之後才 SetTooltip，避免 tooltip 文字被透明 text color 蓋掉
  -- show tooltip after pop so transparent text color doesn't render the tip blank
  if pending_hdr_tip then ImGui.SetTooltip(ctx, pending_hdr_tip) end
  -- column reorder guide line：計算separator位置，延後到tbl.y2確定後繪製
  -- column reorder guide line: compute separator positions, draw later when tbl.y2 is known
  local col_guide_x = nil
  if hdr_drag_src then
    if not ImGui.IsMouseDown(ctx, 0) then
      hdr_drag_src = nil
    elseif ImGui.IsMouseDragging(ctx, 0) then
      -- 收集所有欄位按螢幕x排序，算separator中線 -- collect columns sorted by screen x, compute separator midpoints
      local edges = {}
      for hi2 = 0, 12 do
        local hr = hdr_rects[hi2]
        if hr then edges[#edges+1] = {x=hr.x, r=hr.x + hr.w} end
      end
      table.sort(edges, function(a, b) return a.x < b.x end)
      -- separator在相鄰欄位content之間的中點 -- separator is midpoint between adjacent content areas
      local seps = {}
      for i = 2, #edges do
        seps[#seps+1] = (edges[i-1].r + edges[i].x) * 0.5
      end
      -- 找最近的separator -- find nearest separator to mouse
      local best_dist = math.huge
      for _, sx in ipairs(seps) do
        local d = math.abs(mx - sx)
        if d < best_dist then best_dist = d; col_guide_x = sx end
      end
    end
  end
  ImGui.PopFont(ctx)
  ImGui.PopStyleColor(ctx, 2)

  -- Body
  ImGui.PushFont(ctx, FONT, FUNC.sz(15))
  dl = ImGui.GetWindowDrawList(ctx)  -- 重用header段宣告的dl -- reuse dl declared in header section
  tbl.row_screen = {}
  local _, body_sy = ImGui.GetCursorScreenPos(ctx)
  tbl.y1 = body_sy
  -- 扣掉 scrollbar 寬度，避免 group border 蓋到 scrollbar -- scrollbar扣除
  local scroll_w = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ScrollbarSize())
  tbl.x1, tbl.x2 = tbl_sx, tbl_sx + tbl_w - scroll_w

  local group_rows = {}
  local spacer_rows = {}  -- 收集 SPACER 位置，在 EndTable 後渲染背景（確保在 column lines 之上）
  local target_hover_id = nil  -- hover target column時高亮目標cue -- highlight target cue on hover

  for ci = 1, #cues do
    local c = cues[ci]
    if not c then goto continue end
    -- 巢狀摺疊：任何祖先 GROUP 被摺疊就隱藏 -- nested collapse: hide if any ancestor collapsed
    do local gid = c.group_id
      while gid do
        if collapsed_groups[gid] then goto continue end
        local _,gc = FUNC.find_id(gid)
        if not gc then break end
        gid = gc.group_id
      end
    end

    local ROW_H = FUNC.sz(22)  -- 統一列高，避免GROUP/PLAY列高不一致 -- uniform row height
    local text_oy = FUNC.sz(2)  -- 全域文字垂直偏移量 -- global text vertical offset
    local grp_extra_oy = c.type == "GROUP" and FUNC.sz(2) or 0  -- GROUP列額外下移 -- extra offset for GROUP rows
    if c.type ~= "SPACER" then
      ImGui.TableNextRow(ctx, 0, ROW_H)
    else
      ImGui.TableNextRow(ctx, 0, ROW_H)
    end
    local rx, ry = ImGui.GetCursorScreenPos(ctx)
    tbl.row_screen[ci] = {y = ry, x = rx}
    -- 上下鍵自動捲動：只在row不可見時才捲 -- auto-scroll only when row is out of view
    if tbl.nav_row == ci then
      if not ImGui.IsRectVisible(ctx, 1, FUNC.sz(22)) then
        ImGui.SetScrollHereY(ctx, tbl.nav_dir == -1 and 0.0 or 1.0)
      end
    end

    -- Row BG
    -- cue_color: -1=clean/預設（在group中自動繼承）, 0=在group中手動設為none, >0=有自己顏色
    -- 巢狀繼承：向上鏈式查詢直到找到有顏色的 GROUP -- nested color inheritance chain
    local eff_color = (c.cue_color and c.cue_color > 0) and c.cue_color or nil
    if not eff_color and c.cue_color ~= 0 then
      local gid = c.group_id
      while gid do
        local _, gc = FUNC.find_id(gid)
        if not gc then break end
        if gc.cue_color and gc.cue_color > 0 then eff_color = gc.cue_color; break end
        if gc.cue_color == 0 then break end  -- 明確不繼承
        gid = gc.group_id  -- 繼續向上找
      end
    end
    local has_cc = eff_color ~= nil
    if has_cc then
      -- group中alpha依亮度三階
      local cc_a = 160  -- GROUP標題與自訂色預設alpha=160
      if c.group_id then
        local cr = (eff_color >> 16) & 0xFF
        local cg = (eff_color >> 8) & 0xFF
        local cb = eff_color & 0xFF
        local lum = cr * 0.299 + cg * 0.587 + cb * 0.114
        cc_a = lum > 140 and 80 or (lum > 80 and 100 or 120)
      end
      ImGui.TableSetBgColor(ctx, ImGui.TableBgTarget_RowBg0(), FUNC.col2im(eff_color, cc_a))
    else
      -- group底色fallback：沒有明確cue_color，用group邊框色當淡底色 -- group bg fallback
      local fb_gid = (c.type == "GROUP") and c.id or c.group_id
      if fb_gid and c.cue_color ~= 0 then
        -- 檢查GROUP parent是否明確設為none(cue_color==0)，是的話跳過fallback -- skip fallback if GROUP opted out
        local _, fb_gc = FUNC.find_id(fb_gid)
        if not fb_gc or fb_gc.cue_color ~= 0 then
          local grp_col = FUNC.get_grp_color(fb_gid)
          local a = c.group_id and 50 or 70  -- 子cue淡一點，GROUP本身稍深
          ImGui.TableSetBgColor(ctx, ImGui.TableBgTarget_RowBg0(), (grp_col & 0x00FFFFFF) | (a << 24))
          has_cc = true
        end
      end
    end
    local rc = nil
    if c.state==STATE.PREWAIT then rc=C.pw
    elseif c.state==STATE.POSTWAIT then rc=C.ptw
    elseif FUNC.is_sel(ci) then
      rc = has_cc and FUNC.rgba(150, 150, 150, 80) or C.sel
    end
    if rc then ImGui.TableSetBgColor(ctx, ImGui.TableBgTarget_RowBg1(), rc) end
    -- 損壞 cue（s2c 缺必要欄位）：覆蓋灰底警告 -- broken cue: grey overlay
    if c._broken then
      ImGui.TableSetBgColor(ctx, ImGui.TableBgTarget_RowBg1(), FUNC.rgba(80, 80, 80, 180))
    end

    if c.group_id then
      -- 向上走group鏈，更新所有祖先group的last -- walk up group chain, update all ancestor groups' last
      local gid = c.group_id
      local depth_guard = 0
      while gid and depth_guard < MAX_GROUP_DEPTH do
        if not group_rows[gid] then group_rows[gid]={first=ci,last=ci}
        else group_rows[gid].last=ci end
        local _, gc = FUNC.find_id(gid)
        gid = gc and gc.group_id or nil
        depth_guard = depth_guard + 1
      end
    end
    if c.type=="GROUP" then
      local grp_depth = FUNC.cue_depth(c)  -- GROUP 自己的深度（用於框線縮排）
      if not group_rows[c.id] then group_rows[c.id]={first=ci,last=ci,depth=grp_depth}
      else group_rows[c.id].first=math.min(group_rows[c.id].first,ci); group_rows[c.id].depth=grp_depth end
    end

    -- SPACER — 合併整列如同單一儲存格 -- SPACER: merged row looks like a single cell
    if c.type == "SPACER" then
      local editing = ie.active and ie.row == ci and ie.col == "notes"
      ImGui.TableNextColumn(ctx)
      -- 透明Selectable處理互動（點擊/拖曳/右鍵）-- invisible Selectable for interaction
      ImGui.PushStyleColor(ctx, ImGui.Col_Header(), 0)
      ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered(), FUNC.rgba(255,255,255,15))
      ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive(), 0)
      local fl = ImGui.SelectableFlags_SpanAllColumns() + ImGui.SelectableFlags_AllowDoubleClick()
      ImGui.Selectable(ctx, "##sp"..ci, FUNC.is_sel(ci), fl)
      ImGui.PopStyleColor(ctx, 3)
      local sp_rh = ImGui.GetTextLineHeightWithSpacing(ctx)  -- 普通行高 -- normal row height
      if not editing then
        if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left()) and FUNC.try_dbl("sp"..ci) then
          FUNC.start_ie(ci, "notes", c.notes or "")
        end
        FUNC.cell_post(ci, c, false)
      end
      for col = 1, 12 do ImGui.TableNextColumn(ctx) end
      local _, ry2 = ImGui.GetCursorScreenPos(ctx)
      if tbl.row_screen[ci] then tbl.row_screen[ci].y_bot = ry2 end
      spacer_rows[#spacer_rows+1] = {ci=ci, c=c, h=sp_rh}
      FUNC.draw_row_menu(ci, c)
      goto continue
    end

    -- 巢狀縮排深度 -- nesting indent depth
    local depth = FUNC.cue_depth(c)
    local indent = depth * FUNC.sz(12)  -- 每層縮排12px

    -- Col 0: > cursor
    ImGui.TableNextColumn(ctx)
    if indent > 0 then ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + indent) end  -- 縮排
    ImGui.PushStyleColor(ctx, ImGui.Col_Header(), 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered(), FUNC.rgba(255,255,255,15))
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive(), 0)
    FUNC.nav_check(ci, 0)
    local fc_flags = ImGui.SelectableFlags_AllowDoubleClick()
    local has_trk_warn = track_warns[c.id] ~= nil
    local has_fxe_warn = false
    if c.fx_envs and #c.fx_envs > 0 then
      for _, fe in ipairs(c.fx_envs) do
        if fe._missing then has_fxe_warn = true; break end
      end
    end
    local has_warn = has_trk_warn or has_fxe_warn
    if has_warn then
      local warn_txt = "⚠️"
      ImGui.PushFont(ctx, FONT_B, FUNC.sz(15))
      local sx, sy = ImGui.GetCursorScreenPos(ctx)
      local cw0 = ImGui.GetContentRegionAvail(ctx)
      local tw0, th0 = ImGui.CalcTextSize(ctx, warn_txt, 0, 0)
      local rh = ImGui.GetTextLineHeightWithSpacing(ctx)
      local wdl = ImGui.GetWindowDrawList(ctx)
      ImGui.DrawList_AddText(wdl, sx + (cw0 - tw0) * 0.5, sy + (rh - th0) * 0.5, FUNC.dim_c(FUNC.rgba(220,60,50)), warn_txt)
      ImGui.PushStyleColor(ctx, ImGui.Col_Text(), 0)
      if ImGui.Selectable(ctx, "##fc"..ci, false, fc_flags) then
        local w = track_warns[c.id]
        if w and w.missing then
          popup.warn_missing = true; popup.warn_missing_ci = ci  -- 開啟track遺失popup -- open missing track popup
        elseif has_trk_warn then
          popup.warn = true; popup.warn_ci = ci
        elseif has_fxe_warn then
          fx_env_missing_warn = FUNC.fx_env_check_missing(c)  -- 開啟FX envelope遺失popup
        end
      end
      ImGui.PopStyleColor(ctx, 1)
      ImGui.PopFont(ctx)
    elseif ci == next_go and not next_go_hidden then
      if _scroll_to_next_go then
        ImGui.SetScrollHereY(ctx, 0.4)
        _scroll_to_next_go = false
      end
      -- >>動畫用DrawList置中繪製，避免文字寬度不一導致位置跳動 -- centered >> animation via DrawList
      local phase = math.floor(reaper.time_precise() * 3) % 3
      local cursor_txt
      if phase == 0 then cursor_txt = ">" elseif phase == 1 then cursor_txt = ">>" else cursor_txt = "" end
      ImGui.PushStyleColor(ctx, ImGui.Col_Header(), 0)
      ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered(), FUNC.rgba(255,255,255,15))
      ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive(), 0)
      local sel_x = ImGui.GetCursorScreenPos(ctx)
      local sel_cw = ImGui.GetContentRegionAvail(ctx)
      if ImGui.Selectable(ctx, "##fc"..ci, false, fc_flags) then
        if FUNC.try_dbl("fc"..ci) then FUNC.open_edit() end
      end
      ImGui.PopStyleColor(ctx, 3)
      if cursor_txt ~= "" then
        ImGui.PushFont(ctx, FONT_B, FUNC.sz(17))
        local _, sel_y = ImGui.GetItemRectMin(ctx)
        local _, sel_h = ImGui.GetItemRectSize(ctx)
        local fc_dl = ImGui.GetWindowDrawList(ctx)
        local tw, th = ImGui.CalcTextSize(ctx, cursor_txt, 0, 0)
        local tx = sel_x + (sel_cw - tw) * 0.5
        local ty = sel_y + (sel_h - th) * 0.5
        ImGui.DrawList_AddTextEx(fc_dl, FONT_B, FUNC.sz(17), tx, ty, C.cur, cursor_txt)
        ImGui.PopFont(ctx)
      end
    else
      if ImGui.Selectable(ctx, " ##fc"..ci, false, fc_flags) then
        if FUNC.try_dbl("fc"..ci) then FUNC.open_edit() end
      end
    end
    FUNC.nav_track(0)
    ImGui.PopStyleColor(ctx, 3)
    FUNC.cell_post(ci, c, false)

    -- Col 1: Cue #
    ImGui.TableNextColumn(ctx)
    FUNC.nav_check(ci, 1)
    FUNC.draw_click_cell(ci, "cue_number", c.cue_number ~= "" and c.cue_number or " ", c.cue_number)
    FUNC.nav_track(1)

    -- Col 2: Type
    ImGui.TableNextColumn(ctx)
    FUNC.nav_check(ci, 2)
    local type_txt = TYPE_SHORT[c.type] or c.type
    if c.type == "GROUP" then
      local collapsed = collapsed_groups[c.id]
      type_txt = (collapsed and "+ " or "- ") .. type_txt
      local cw3 = ImGui.GetContentRegionAvail(ctx)
      local tw3,_ = ImGui.CalcTextSize(ctx, type_txt, 0, 0)
      ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + math.max(0, (cw3 - tw3) * 0.5))
      ImGui.PushStyleColor(ctx, ImGui.Col_Text(), FUNC.get_grp_text_color(c.id))
      ImGui.PushStyleColor(ctx, ImGui.Col_Header(), 0)
      ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered(), FUNC.rgba(255,255,255,15))
      ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive(), 0)
      if ImGui.Selectable(ctx, type_txt.."##tp"..ci, false) then
        collapsed_groups[c.id] = not collapsed_groups[c.id] end
      ImGui.PopStyleColor(ctx, 4)
      FUNC.cell_post(ci, c, false)
    else
      ImGui.PushStyleColor(ctx, ImGui.Col_Text(), TYPE_COL[c.type] or C.text)
      local cw2 = ImGui.GetContentRegionAvail(ctx)
      local tw2,_ = ImGui.CalcTextSize(ctx, type_txt, 0, 0)
      ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + math.max(0, (cw2 - tw2) * 0.5))
      ImGui.PushStyleColor(ctx, ImGui.Col_Header(), 0)
      ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered(), 0)
      ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive(), 0)
      if ImGui.Selectable(ctx, type_txt.."##tp"..ci, false, ImGui.SelectableFlags_AllowDoubleClick()) then
        if FUNC.try_dbl("tp"..ci) then FUNC.open_edit() end
      end
      ImGui.PopStyleColor(ctx, 3)
      FUNC.cell_post(ci, c, false)
      ImGui.PopStyleColor(ctx, 1)
    end
    FUNC.nav_track(2)

    -- Col 3: Name（過長hover 1秒後跑馬燈）-- marquee after 1s hover if truncated
    ImGui.TableNextColumn(ctx)
    FUNC.nav_check(ci, 3)
    if not FUNC.draw_ie(ci, "name") then
      local nd = c.name ~= "" and c.name or "(unnamed)"
      local nc = c.name ~= "" and C.text or C.muted
      local nm_cw = ImGui.GetContentRegionAvail(ctx)
      local nm_sx, nm_sy = ImGui.GetCursorScreenPos(ctx)
      local nm_h = FUNC.sz(20)
      local nm_tw = ImGui.CalcTextSize(ctx, nd, 0, 0)
      local nm_truncated = nm_tw > nm_cw - FUNC.sz(4)
      -- 透明Selectable處理選取+點擊+拖曳 -- invisible Selectable for select/click/drag
      ImGui.PushStyleColor(ctx, ImGui.Col_Text(), 0)  -- 隱藏Selectable自身文字 -- hide Selectable text
      ImGui.PushStyleColor(ctx, ImGui.Col_Header(), 0)
      ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered(), FUNC.rgba(255,255,255,15))
      ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive(), 0)
      if ImGui.Selectable(ctx, nd.."##nm"..ci, FUNC.is_sel(ci), ImGui.SelectableFlags_AllowDoubleClick()) then
        if FUNC.try_dbl("nm"..ci) then FUNC.start_ie(ci, "name", c.name) end
      end
      ImGui.PopStyleColor(ctx, 4)
      local nm_hov = ImGui.IsItemHovered(ctx)
      -- 跑馬燈狀態管理 -- marquee state
      local mq = name_marquee[ci]
      if nm_truncated and nm_hov then
        if not mq then
          name_marquee[ci] = {t_hover = reaper.time_precise(), t_scroll = nil}
          mq = name_marquee[ci]
        end
        if not mq.t_scroll and (reaper.time_precise() - mq.t_hover >= 0.5) then
          mq.t_scroll = reaper.time_precise()  -- 1秒後開始滾動 -- start scrolling after 1s
        end
      else
        name_marquee[ci] = nil; mq = nil
      end
      -- DrawList繪製文字 -- render text via DrawList
      local nm_dl = ImGui.GetWindowDrawList(ctx)
      local nm_pad = FUNC.sz(2)
      local _, nm_th = ImGui.CalcTextSize(ctx, "Ay", 0, 0)  -- 用固定字串測量文字高度 -- measure text height
      local nm_ty = nm_sy + math.floor((nm_h - nm_th) * 0.5)  -- 垂直置中 -- vertical center
      if mq and mq.t_scroll then
        -- 跑馬燈滾動 -- marquee scrolling
        local gap_txt = "                        "
        local loop_txt = nd .. gap_txt
        local loop_tw = ImGui.CalcTextSize(ctx, loop_txt, 0, 0)
        local speed = FUNC.sz(52)  -- 1.5x marquee speed
        local elapsed = reaper.time_precise() - mq.t_scroll
        local offset = (elapsed * speed) % loop_tw
        ImGui.DrawList_PushClipRect(nm_dl, nm_sx, nm_sy, nm_sx + nm_cw, nm_sy + nm_h, true)
        local tx = nm_sx + nm_pad - offset
        ImGui.DrawList_AddText(nm_dl, tx, nm_ty, nc, loop_txt)
        ImGui.DrawList_AddText(nm_dl, tx + loop_tw, nm_ty, nc, loop_txt)
        ImGui.DrawList_PopClipRect(nm_dl)
      else
        -- 靜態顯示（ClipRect截斷）-- static with clip
        ImGui.DrawList_PushClipRect(nm_dl, nm_sx, nm_sy, nm_sx + nm_cw, nm_sy + nm_h, true)
        ImGui.DrawList_AddText(nm_dl, nm_sx + nm_pad, nm_ty, nc, nd)
        ImGui.DrawList_PopClipRect(nm_dl)
      end
      FUNC.cell_post(ci, c, false)
    end
    FUNC.nav_track(3)

    -- Col 4: Target
    ImGui.TableNextColumn(ctx)
    FUNC.nav_check(ci, 4)
    if c.type == "PLAY" then
      ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg(), FUNC.rgba(35, 55, 75))
      ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered(), FUNC.rgba(45, 70, 95))
      ImGui.SetNextItemWidth(ctx, -1)
      local trk_label = c.track_invalid and "??" or string.format("Tr.%d", c.track_idx+1)
      local dd_max_h = ImGui.GetTextLineHeightWithSpacing(ctx) * DD_POPUP_ROWS + FUNC.sz(8)
      ImGui.SetNextWindowSizeConstraints(ctx, FUNC.sz(DD_POPUP_W), 0, FUNC.sz(DD_POPUP_W), dd_max_h)
      if ImGui.BeginCombo(ctx, "##trk"..ci, trk_label) then
        local just_opened = ImGui.IsWindowAppearing(ctx)  -- 只在combo剛開啟時定位
        -- 計算Tr.x欄固定寬度，確保 | 對齊 -- fixed width for Tr.x column so | aligns vertically
        local pipe_x = ImGui.CalcTextSize(ctx, string.format("Tr.%d ", FUNC.tr_count())) + ImGui.GetCursorPosX(ctx)
        for ti = 0, FUNC.tr_count()-1 do
          local is_cur = ti==c.track_idx
          -- Tr.idx用cue custom color，沒有就用PLAY type色 -- Tr prefix in cue color or PLAY type color
          local tr_col = (c.cue_color and c.cue_color > 0) and FUNC.col2im(c.cue_color) or (TYPE_COL["PLAY"] or C.text)
          ImGui.PushStyleColor(ctx, ImGui.Col_Text(), tr_col)
          ImGui.Text(ctx, string.format("Tr.%d", ti+1))
          ImGui.PopStyleColor(ctx, 1)
          ImGui.SameLine(ctx, pipe_x, 0)  -- 固定位置對齊 | -- fixed X for pipe alignment
          -- track名字用TEXT色 + 跑馬燈（短文字Selectable避免撐寬popup）
          -- track name + marquee (short Selectable text to prevent popup auto-widening)
          local nm = FUNC.tr_name(ti); if nm == "?" then nm = "" end
          local trk_txt = "|  "..nm
          local trk_sx, trk_sy = ImGui.GetCursorScreenPos(ctx)
          local trk_cw = ImGui.GetContentRegionAvail(ctx)
          if ImGui.Selectable(ctx, "##trks"..ti, is_cur) then
            c.track_idx = ti; c.track_guid = FUNC.tr_guid(ti); c.track_invalid = false
            FUNC.save_cues() end
          local trk_rh = select(2, ImGui.GetItemRectSize(ctx))
          local trk_dl = ImGui.GetWindowDrawList(ctx)
          FUNC.draw_marquee(trk_dl, FONT, FUNC.sz(13), trk_txt, C.text,
            trk_sx, trk_sy, trk_cw, trk_rh, "trk_mq"..ci.."_"..ti,
            {speed = FUNC.sz(DD_MARQUEE_SPEED), delay = 0.3, gap = 16})
          if is_cur and just_opened then ImGui.SetScrollHereY(ctx, 0.0) end
        end; ImGui.EndCombo(ctx) end
      ImGui.PopStyleColor(ctx, 2)
      FUNC.target_drag_src(ci, c)
      FUNC.cell_post(ci, c, true)
    elseif c.type == "GROUP" then
      -- 顯示children各type數量，用type顏色分色（沒有的type隱藏）-- show child count per type in type colors
      local n_play, n_stop, n_pause, n_fade, n_group, n_midi = 0, 0, 0, 0, 0, 0
      for _, v in ipairs(c.children or {}) do
        local cc = cues[v]
        if cc then
          if cc.type == "PLAY" then n_play = n_play + 1
          elseif cc.type == "STOP" then n_stop = n_stop + 1
          elseif cc.type == "PAUSE" then n_pause = n_pause + 1
          elseif cc.type == "FADE" then n_fade = n_fade + 1
          elseif cc.type == "GROUP" then n_group = n_group + 1
          elseif cc.type == "MIDI" then n_midi = n_midi + 1 end
        end
      end
      local cw_t = ImGui.GetContentRegionAvail(ctx)
      local gt_rh = FUNC.sz(22)
      local gt_sx, gt_sy = ImGui.GetCursorScreenPos(ctx)
      -- 透明Selectable處理互動 -- transparent Selectable for interaction
      ImGui.PushStyleColor(ctx, ImGui.Col_Text(), 0)
      ImGui.PushStyleColor(ctx, ImGui.Col_Header(), 0)
      ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered(), FUNC.rgba(255,255,255,15))
      ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive(), 0)
      ImGui.Selectable(ctx, "##tg"..ci, false)
      ImGui.PopStyleColor(ctx, 4)
      -- DrawList繪製各type icon+數量（居中，type色）-- DrawList colored type icon+count, centered
      local parts = {}  -- {icon, count, color} -- 順序：PLAY FADE STOP PAUSE GROUP
      if n_play > 0 then parts[#parts+1] = {"▶", tostring(n_play), TYPE_COL.PLAY} end
      if n_fade > 0 then parts[#parts+1] = {"≈", tostring(n_fade), TYPE_COL.FADE} end
      if n_stop > 0 then parts[#parts+1] = {"■", tostring(n_stop), TYPE_COL.STOP} end
      if n_pause > 0 then parts[#parts+1] = {"‖", tostring(n_pause), TYPE_COL.PAUSE} end
      if n_group > 0 then parts[#parts+1] = {"▣", tostring(n_group), FUNC.get_grp_color(c.id)} end  -- 用GROUP自身指定色 -- use group's assigned color
      if n_midi > 0 then parts[#parts+1] = {"♪", tostring(n_midi), TYPE_COL.MIDI} end
      if #parts > 0 then
        local gap = FUNC.sz(6)  -- 各組之間間距 -- gap between groups
        local icon_gap = FUNC.sz(1)  -- icon與數字間距 -- gap between icon and count
        local total_w = 0
        local segs = {}  -- {icon_w, count_w, color, icon, count}
        for _, p in ipairs(parts) do
          local iw = ImGui.CalcTextSize(ctx, p[1], 0, 0)
          local cw2 = ImGui.CalcTextSize(ctx, p[2], 0, 0)
          segs[#segs+1] = {iw=iw, cw=cw2, col=p[3], icon=p[1], cnt=p[2]}
          total_w = total_w + iw + icon_gap + cw2
        end
        total_w = total_w + gap * (#parts - 1)
        local start_x = gt_sx  -- 置左對齊，與PLAY的Tr.起始x相同 -- left-aligned to match PLAY's Tr. start
        local text_y = gt_sy + (gt_rh - select(2, ImGui.CalcTextSize(ctx, "0", 0, 0))) * 0.5
        local cx = start_x
        for si, s in ipairs(segs) do
          ImGui.DrawList_AddText(dl, cx, text_y, s.col, s.icon)
          cx = cx + s.iw + icon_gap
          ImGui.DrawList_AddText(dl, cx, text_y, s.col, s.cnt)
          cx = cx + s.cw + gap
        end
      end
      FUNC.target_drag_src(ci, c)  -- GROUP也可作為target drag source -- GROUP can be target drag source too
      FUNC.cell_post(ci, c, true)  -- skip_drag=true：TARGET欄拖曳是指定target，不是reorder -- target column drag = link, not reorder
    elseif c.type == "MIDI" then
      -- MIDI target 欄：與 audio PLAY 一樣的 track dropdown -- track dropdown (mirrors PLAY)
      ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg(), FUNC.rgba(55, 45, 75))
      ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered(), FUNC.rgba(75, 60, 95))
      ImGui.SetNextItemWidth(ctx, -1)
      local mt_label = (c.track_idx and c.track_idx >= 0) and string.format("Tr.%d", c.track_idx+1) or "Tr.?"
      local dd_max_h = ImGui.GetTextLineHeightWithSpacing(ctx) * DD_POPUP_ROWS + FUNC.sz(8)
      ImGui.SetNextWindowSizeConstraints(ctx, FUNC.sz(DD_POPUP_W), 0, FUNC.sz(DD_POPUP_W), dd_max_h)
      if ImGui.BeginCombo(ctx, "##midi_trk"..ci, mt_label) then
        local just_opened = ImGui.IsWindowAppearing(ctx)
        local pipe_x = ImGui.CalcTextSize(ctx, string.format("Tr.%d ", FUNC.tr_count())) + ImGui.GetCursorPosX(ctx)
        for ti = 0, FUNC.tr_count()-1 do
          local is_cur = ti == c.track_idx
          local tr_col = (c.cue_color and c.cue_color > 0) and FUNC.col2im(c.cue_color) or (TYPE_COL["MIDI"] or C.text)
          ImGui.PushStyleColor(ctx, ImGui.Col_Text(), tr_col)
          ImGui.Text(ctx, string.format("Tr.%d", ti+1))
          ImGui.PopStyleColor(ctx, 1)
          ImGui.SameLine(ctx, pipe_x, 0)
          local nm = FUNC.tr_name(ti); if nm == "?" then nm = "" end
          local trk_txt = "|  "..nm
          local trk_sx, trk_sy = ImGui.GetCursorScreenPos(ctx)
          local trk_cw = ImGui.GetContentRegionAvail(ctx)
          if ImGui.Selectable(ctx, "##mtrks"..ti, is_cur) then
            c.track_idx = ti; c.track_guid = FUNC.tr_guid(ti); c.track_invalid = false
            FUNC.save_cues()
          end
          local trk_rh = select(2, ImGui.GetItemRectSize(ctx))
          local trk_dl = ImGui.GetWindowDrawList(ctx)
          FUNC.draw_marquee(trk_dl, FONT, FUNC.sz(13), trk_txt, C.text,
            trk_sx, trk_sy, trk_cw, trk_rh, "mtrk_mq"..ci.."_"..ti,
            {speed = FUNC.sz(DD_MARQUEE_SPEED), delay = 0.3, gap = 16})
          if is_cur and just_opened then ImGui.SetScrollHereY(ctx, 0.0) end
        end
        ImGui.EndCombo(ctx)
      end
      ImGui.PopStyleColor(ctx, 2)
      FUNC.target_drag_src(ci, c)
      FUNC.cell_post(ci, c, true)
    else
      ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg(), FUNC.rgba(75, 50, 35))
      ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered(), FUNC.rgba(95, 65, 45))
      ImGui.SetNextItemWidth(ctx, -1)
      local dd_max_h = ImGui.GetTextLineHeightWithSpacing(ctx) * DD_POPUP_ROWS + FUNC.sz(8)
      ImGui.SetNextWindowSizeConstraints(ctx, FUNC.sz(DD_POPUP_W), 0, FUNC.sz(DD_POPUP_W), dd_max_h)
      if ImGui.BeginCombo(ctx, "##tgt"..ci, FUNC.target_label(c)) then
        local just_opened = ImGui.IsWindowAppearing(ctx)  -- 只在combo剛開啟時定位
        -- 計算Tr/G欄固定寬度，確保 | 對齊 -- fixed width so | aligns vertically
        local max_prefix = "Tr."..tostring(FUNC.tr_count()).." "
        for qi, qc in ipairs(cues) do
          if qc.type == "GROUP" then
            local gp = "G."..tostring(qc.cue_number).." "
            if #gp > #max_prefix then max_prefix = gp end
          end
        end
        local pipe_x = ImGui.CalcTextSize(ctx, max_prefix) + ImGui.GetCursorPosX(ctx)
        local tgt_dl = ImGui.GetWindowDrawList(ctx)
        for qi, qc in ipairs(cues) do
          if qc.type == "PLAY" then
            local is_cur = c.target_cue_id==qc.id
            local tr_col = (qc.cue_color and qc.cue_color > 0) and FUNC.col2im(qc.cue_color) or (TYPE_COL["PLAY"] or C.text)
            ImGui.PushStyleColor(ctx, ImGui.Col_Text(), tr_col)
            ImGui.Text(ctx, string.format("Tr.%d", qc.track_idx+1))
            ImGui.PopStyleColor(ctx, 1)
            ImGui.SameLine(ctx, pipe_x, 0)
            local nm = FUNC.tr_name(qc.track_idx); if nm == "?" then nm = "" end
            local tgt_txt = "  |  "..nm
            -- 短文字Selectable + DrawList跑馬燈（避免撐寬popup）
            -- short Selectable + DrawList marquee (prevent popup auto-widening)
            local tgt_sx, tgt_sy = ImGui.GetCursorScreenPos(ctx)
            local tgt_cw = ImGui.GetContentRegionAvail(ctx)
            if ImGui.Selectable(ctx, "##tsel"..qi, is_cur) then c.target_cue_id=qc.id; FUNC.save_cues() end
            local tgt_rh = select(2, ImGui.GetItemRectSize(ctx))
            FUNC.draw_marquee(tgt_dl, FONT, FUNC.sz(13), tgt_txt, C.text,
              tgt_sx, tgt_sy, tgt_cw, tgt_rh, "tgt_mq"..ci.."_"..qi,
              {speed = FUNC.sz(DD_MARQUEE_SPEED), delay = 0.3, gap = 16})
            if is_cur and just_opened then ImGui.SetScrollHereY(ctx, 0.0) end
          elseif qc.type == "GROUP" then
            local is_cur = c.target_cue_id==qc.id
            local g_col = (qc.cue_color and qc.cue_color > 0) and FUNC.col2im(qc.cue_color) or (TYPE_COL["GROUP"] or C.text)
            ImGui.PushStyleColor(ctx, ImGui.Col_Text(), g_col)
            ImGui.Text(ctx, string.format("G.%s", qc.cue_number))
            ImGui.PopStyleColor(ctx, 1)
            ImGui.SameLine(ctx, pipe_x, 0)
            local lb2 = string.format("| %s [%d]", qc.name~="" and qc.name or "", #(qc.children or {}))
            local tgt_sx2, tgt_sy2 = ImGui.GetCursorScreenPos(ctx)
            local tgt_cw2 = ImGui.GetContentRegionAvail(ctx)
            if ImGui.Selectable(ctx, "##gsel"..qi, is_cur) then c.target_cue_id=qc.id; FUNC.save_cues() end
            local tgt_rh2 = select(2, ImGui.GetItemRectSize(ctx))
            FUNC.draw_marquee(tgt_dl, FONT, FUNC.sz(13), lb2, C.text,
              tgt_sx2, tgt_sy2, tgt_cw2, tgt_rh2, "tgt_mq"..ci.."_"..qi,
              {speed = FUNC.sz(DD_MARQUEE_SPEED), delay = 0.3, gap = 16})
            if is_cur and just_opened then ImGui.SetScrollHereY(ctx, 0.0) end
          end
        end; ImGui.EndCombo(ctx) end
      ImGui.PopStyleColor(ctx, 2)
      -- hover target column時記錄target ID用於高亮 -- track hover for highlight
      if ImGui.IsItemHovered(ctx) and c.target_cue_id ~= "" then target_hover_id = c.target_cue_id end
      FUNC.target_drag_accept(ci, c)
      FUNC.cell_post(ci, c, true)
    end
    FUNC.nav_track(4)

    -- Col 5: Volume
    ImGui.TableNextColumn(ctx)
    ImGui.SetCursorPosY(ctx, ImGui.GetCursorPosY(ctx) + text_oy + grp_extra_oy)
    FUNC.nav_check(ci, 5)
    do
      ImGui.PushFont(ctx, FONT_MONO, FUNC.sz(14))
      if FUNC.draw_ie(ci, "volume") then
      else
        local vtxt = FUNC.fmt_v(c.volume)
        local cw5 = ImGui.GetContentRegionAvail(ctx)
        local tw5,_ = ImGui.CalcTextSize(ctx, vtxt, 0, 0)
        ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + math.max(0, (cw5 - tw5) * 0.5))
        ImGui.PushStyleColor(ctx, ImGui.Col_Header(), 0)
        ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered(), FUNC.rgba(255,255,255,15))
        ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive(), 0)
        ImGui.Selectable(ctx, vtxt.."##vol"..ci, false)
        ImGui.PopStyleColor(ctx, 3)
        -- volume拖曳範圍擴大：用drag.vol_ci追蹤，滑鼠離開列高也能繼續拖
        if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left()) then
          if FUNC.try_dbl("vol"..ci) then
            local einit = c.volume<=prefs.inf_db and "-" or (c.volume>0 and string.format("+%.1f",c.volume) or string.format("%.1f",math.abs(c.volume)))
            FUNC.start_ie(ci, "volume", einit)
          else
            drag.vol_ci = ci  -- 開始volume拖曳
          end
        end
        if drag.vol_ci == ci then
          if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left()) then
            ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS())
            local _, dy = ImGui.GetMouseDelta(ctx)
            if math.abs(dy) > 0 then
              local spd = ImGui.IsKeyDown(ctx, ImGui.Mod_Shift()) and 0.02 or 0.1
              c.volume = FUNC.clamp(c.volume - dy * spd, prefs.vol_min, prefs.vol_max)
              if c.type == "FADE" then c.fade_vol_enabled = true end
            end
          else
            drag.vol_ci = nil  -- 放開滑鼠，結束拖曳
          end
        elseif ImGui.IsItemHovered(ctx) then
          ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS())
        end
        FUNC.cell_post(ci, c, true)  -- volume垂直拖曳bypass reorder -- skip_drag for volume column
      end
      ImGui.PopFont(ctx)
    end
    FUNC.nav_track(5)

    -- Col 6: Pre-Wait
    ImGui.TableNextColumn(ctx)
    ImGui.SetCursorPosY(ctx, ImGui.GetCursorPosY(ctx) + text_oy + grp_extra_oy)
    FUNC.nav_check(ci, 6)
    local pp = FUNC.timer_prog(ci, TIMER.PRE)
    if pp then
      local sx,sy = ImGui.GetCursorScreenPos(ctx)
      local cw6 = ImGui.GetContentRegionAvail(ctx)
      -- BPM mode: 顯示拍子倒數 + 閃爍外框 -- BPM mode: beat countdown + flash border
      local pw_text
      if c.pre_wait_mode == "bpm" and c.pre_bpm_val > 0 then
        local rem = FUNC.timer_rem(ci, TIMER.PRE)
        pw_text = string.format("%d beats", math.ceil(rem * c.pre_bpm_val / 60))
      else
        pw_text = FUNC.fmt_t(FUNC.timer_rem(ci, TIMER.PRE))
      end
      FUNC.draw_pbar(dl, sx-FUNC.sz(3), sy-FUNC.sz(1), cw6+FUNC.sz(6), FUNC.sz(23), 1-pp, C.p_wait, pw_text, true)
      if c.pre_wait_mode == "bpm" and c.pre_bpm_val > 0 then
        local elapsed = pp * c.pre_wait
        local beat_period = 60 / c.pre_bpm_val
        local beat_phase = (elapsed % beat_period) / beat_period
        local flash = math.exp(-beat_phase * 3.5)
        local ba = math.floor(60 + 195 * flash)
        ImGui.DrawList_AddRect(dl, sx-FUNC.sz(4), sy-FUNC.sz(2), sx+cw6+FUNC.sz(4), sy+FUNC.sz(23),
          (C.p_wait & 0xFFFFFF00) | ba, 3, 0, FUNC.sz(1) + FUNC.sz(3) * flash)
      end
      ImGui.InvisibleButton(ctx, "##pw_pb"..ci, cw6, FUNC.sz(18))
      FUNC.cell_post(ci, c, false)
    else
      ImGui.PushFont(ctx, FONT_MONO, FUNC.sz(14))
      if FUNC.draw_ie(ci, "pre_wait") then
      else
        local pw_d, pw_e
        if c.pre_wait_mode == "bpm" then
          local pre_nv = NOTE_VALUES[c.pre_note_idx or NOTE_DEFAULT_IDX] or NOTE_VALUES[NOTE_DEFAULT_IDX]
          local pre_cnt = math.max(0, math.floor((c.pre_bpm_beats or 0) / pre_nv.val + 0.5))
          pw_d = string.format("%d %s @%d", pre_cnt, pre_nv.label, c.pre_bpm_val or 120)
          pw_e = string.format("%din%d", pre_cnt, c.pre_bpm_val or 120)
        else
          pw_d = c.pre_wait > 0 and FUNC.fmt_t(c.pre_wait) or "0:00.0"
          pw_e = c.pre_wait > 0 and string.format("%.1f", c.pre_wait) or ""
        end
        local cw6i = ImGui.GetContentRegionAvail(ctx)
        local tw6i,_ = ImGui.CalcTextSize(ctx, pw_d, 0, 0)
        ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + math.max(0, (cw6i - tw6i) * 0.5))
        ImGui.PushStyleColor(ctx, ImGui.Col_Header(), 0)
        ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered(), FUNC.rgba(255,255,255,15))
        ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive(), 0)
        ImGui.Selectable(ctx, pw_d.."##pw"..ci, false)
        ImGui.PopStyleColor(ctx, 3)
        if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left()) then
          if FUNC.try_dbl("pw"..ci) then FUNC.start_ie(ci, "pre_wait", pw_e)
          else drag.pw_ci = ci end
        end
        if drag.pw_ci == ci then
          if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left()) then
            ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS())
            local _, dy = ImGui.GetMouseDelta(ctx)
            if math.abs(dy) > 0 then
              local spd = ImGui.IsKeyDown(ctx, ImGui.Mod_Shift()) and 0.01 or 0.05
              c.pre_wait = math.max(0, c.pre_wait - dy * spd)
              if c.pre_wait_mode == "bpm" and c.pre_bpm_val > 0 then
                c.pre_bpm_beats = c.pre_wait * (c.pre_bpm_val or 120) / 60
              end
            end
          else drag.pw_ci = nil end
        elseif ImGui.IsItemHovered(ctx) then
          ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS())
        end
        FUNC.cell_post(ci, c, true)
      end
      ImGui.PopFont(ctx)
    end
    FUNC.nav_track(6)

    -- Col 7: Duration
    ImGui.TableNextColumn(ctx)
    FUNC.nav_check(ci, 7)
    local dur_drawn = false
    if c.type == "FADE" then
      if cancelled_fades[c.id] then
        local ce = reaper.time_precise() - cancelled_fades[c.id]
        if ce < 0.5 then
          local wave = 0.5 + 0.5 * math.sin(ce * 2 * 2 * math.pi)
          local r = math.floor(100 + 60 * wave)
          local g = math.floor(25 + 35 * wave)
          local b = math.floor(20 + 20 * wave)
          local sx,sy = ImGui.GetCursorScreenPos(ctx)
          local cw7 = ImGui.GetContentRegionAvail(ctx)
          FUNC.draw_pbar(dl, sx-FUNC.sz(3), sy-FUNC.sz(1), cw7+FUNC.sz(6), FUNC.sz(23), 1, FUNC.rgba(r,g,b), "cancel", true)
          ImGui.InvisibleButton(ctx, "##cdur"..ci, cw7, FUNC.sz(18))
          if ImGui.IsItemClicked(ctx) and FUNC.try_dbl("du"..ci) then FUNC.open_edit() end
          FUNC.cell_post(ci, c, false); dur_drawn = true
        else cancelled_fades[c.id] = nil end
      end
      if (not dur_drawn) and c.state==STATE.RUNNING and c.play_t0>0 and c.fade_time>0 then
        local elapsed = reaper.time_precise() - c.play_t0
        local fp = FUNC.clamp(elapsed / c.fade_time, 0, 1)
        local sx,sy = ImGui.GetCursorScreenPos(ctx)
        local cw7 = ImGui.GetContentRegionAvail(ctx)
        local fp_text
        if c.fade_wait_mode == "bpm" and c.fade_bpm_val > 0 then
          local rem = c.fade_time - elapsed; if rem < 0 then rem = 0 end
          fp_text = string.format("%d beats", math.ceil(rem * c.fade_bpm_val / 60))
        else
          fp_text = FUNC.fmt_t(elapsed).."/"..FUNC.fmt_t(c.fade_time)
        end
        FUNC.draw_pbar(dl, sx-FUNC.sz(3), sy-FUNC.sz(1), cw7+FUNC.sz(6), FUNC.sz(23), fp, C.p_fade, fp_text)
        ImGui.InvisibleButton(ctx, "##dur_pb"..ci, cw7, FUNC.sz(18))
        if ImGui.IsItemClicked(ctx) and FUNC.try_dbl("du"..ci) then FUNC.open_edit() end
        FUNC.cell_post(ci, c, false); dur_drawn = true
      elseif (not dur_drawn) and not FUNC.draw_ie(ci, "fade_time") then
        ImGui.PushFont(ctx, FONT_MONO, FUNC.sz(14))
        local ft_txt, ft_edit
        if c.fade_wait_mode == "bpm" then
          local nv = NOTE_VALUES[c.fade_note_idx or NOTE_DEFAULT_IDX] or NOTE_VALUES[NOTE_DEFAULT_IDX]
          local cnt = math.max(0, math.floor((c.fade_bpm_beats or 0) / nv.val + 0.5))
          ft_txt = string.format("%d %s @%d", cnt, nv.label, c.fade_bpm_val or 120)
          ft_edit = string.format("%din%d", cnt, c.fade_bpm_val or 120)
        else
          ft_txt = FUNC.fmt_t(c.fade_time)
          ft_edit = string.format("%.1f", c.fade_time)
        end
        local cw_ft = ImGui.GetContentRegionAvail(ctx)
        local tw_ft,_ = ImGui.CalcTextSize(ctx, ft_txt, 0, 0)
        ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + math.max(0, cw_ft - tw_ft - 4))
        ImGui.PushStyleColor(ctx, ImGui.Col_Header(), 0)
        ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered(), FUNC.rgba(255,255,255,15))
        ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive(), 0)
        ImGui.Selectable(ctx, ft_txt.."##ft"..ci, false)
        ImGui.PopStyleColor(ctx, 3)
        if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left()) then
          if FUNC.try_dbl("ft"..ci) then FUNC.start_ie(ci, "fade_time", ft_edit)
          else drag.ft_ci = ci end
        end
        if drag.ft_ci == ci then
          if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left()) then
            ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS())
            local _, dy = ImGui.GetMouseDelta(ctx)
            if math.abs(dy) > 0 then
              local spd = ImGui.IsKeyDown(ctx, ImGui.Mod_Shift()) and 0.01 or 0.05
              c.fade_time = math.max(0, c.fade_time - dy * spd)
              if c.fade_wait_mode == "bpm" and c.fade_bpm_val > 0 then
                c.fade_bpm_beats = c.fade_time * (c.fade_bpm_val or 120) / 60
              end
            end
          else drag.ft_ci = nil end
        elseif ImGui.IsItemHovered(ctx) then
          ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS())
        end
        FUNC.cell_post(ci, c, true)
        ImGui.PopFont(ctx)
        dur_drawn = true
      else dur_drawn = true end
    elseif c.type == "PLAY" then
      if soft_kill[c.id] then
        local sk = soft_kill[c.id]
        local ce = reaper.time_precise() - sk.t0
        local wave = 0.5 + 0.5 * math.sin(ce * 2 * 2 * math.pi)
        local r = math.floor(100 + 60 * wave)
        local g = math.floor(25 + 35 * wave)
        local b = math.floor(20 + 20 * wave)
        local fp = FUNC.clamp(1 - ce / sk.dur, 0, 1)
        local sx,sy = ImGui.GetCursorScreenPos(ctx)
        local cw7 = ImGui.GetContentRegionAvail(ctx)
        FUNC.draw_pbar(dl, sx-FUNC.sz(3), sy-FUNC.sz(1), cw7+FUNC.sz(6), FUNC.sz(23), fp, FUNC.rgba(r,g,b),
          "kill "..FUNC.fmt_t(math.max(0, sk.dur - ce)), true)
        ImGui.InvisibleButton(ctx, "##dur_pb"..ci, cw7, FUNC.sz(18))
        if ImGui.IsItemClicked(ctx) and FUNC.try_dbl("du"..ci) then FUNC.open_edit() end
        FUNC.cell_post(ci, c, false); dur_drawn = true
      elseif FUNC.is_cue_paused(c) then
        local ps = paused_cues[c.id]
        if ps then
          local dur = c.eff_dur > 0 and c.eff_dur or c.total_dur
          local sx,sy = ImGui.GetCursorScreenPos(ctx)
          local cw7 = ImGui.GetContentRegionAvail(ctx)
          FUNC.draw_pbar(dl, sx-FUNC.sz(3), sy-FUNC.sz(1), cw7+FUNC.sz(6), FUNC.sz(23), dur>0 and ps.elapsed/dur or 0, C.t_pause,
            "|| "..FUNC.fmt_t(ps.elapsed).."/"..FUNC.fmt_t(dur))
          ImGui.InvisibleButton(ctx, "##dur_pb"..ci, cw7, FUNC.sz(18))
          if ImGui.IsItemClicked(ctx) and FUNC.try_dbl("du"..ci) then FUNC.open_edit() end
          FUNC.cell_post(ci, c, false); dur_drawn = true
        end
      elseif FUNC.cue_is_active(c) then
        local elapsed = reaper.time_precise() - (c.play_t0 or 0)
        local dur = c.eff_dur > 0 and c.eff_dur or c.total_dur
        if dur > 0 then
          elapsed = math.min(elapsed, dur)
          local sx,sy = ImGui.GetCursorScreenPos(ctx)
          local cw7 = ImGui.GetContentRegionAvail(ctx)
          FUNC.draw_pbar(dl, sx-FUNC.sz(3), sy-FUNC.sz(1), cw7+FUNC.sz(6), FUNC.sz(23), FUNC.clamp(elapsed/dur, 0, 1), C.p_play, FUNC.fmt_t(elapsed).."/"..FUNC.fmt_t(dur))
          ImGui.InvisibleButton(ctx, "##dur_pb"..ci, cw7, FUNC.sz(18))
          if ImGui.IsItemClicked(ctx) and FUNC.try_dbl("du"..ci) then FUNC.open_edit() end
          FUNC.cell_post(ci, c, false)
          dur_drawn = true
        end
      end
      if not dur_drawn then
        -- MIDI cue 走 midi item 長度（與 item 編輯即時同步）-- MIDI uses linked item length for live sync
        local dur
        if c.type == "MIDI" and c.midi_mode == "message" then
          dur = c.midi_duration or 0
        elseif c.type == "MIDI" and c.midi_item_guid and c.midi_item_guid ~= "" then
          dur = FUNC.midi_calc_dur_sec(c)
        else
          dur = FUNC.calc_dur_cached(c.track_idx, c.id) -- 用快取版省API call
        end
        -- 使用GROUP有效trim計算duration -- use GROUP-effective trim for duration
        local ets, ete = FUNC.get_eff_trim(c)
        if ete <= 0 then ete = dur end
        if dur > 0 and (ets > 0 or ete < dur) then
          dur = ete - ets
        end
        -- idle duration也要考慮播放速率 -- idle duration considers playback rate
        local cr = (c.rate and c.rate > 0) and c.rate or 1.0
        if cr ~= 1.0 then dur = dur / cr end
        local dtxt = dur > 0 and FUNC.fmt_t(dur) or "N/A"
        -- duration空白處單擊選cue：用全寬InvisibleButton + DrawList右對齊文字
        local cw_du = ImGui.GetContentRegionAvail(ctx)
        if cw_du < 1 then cw_du = 1 end
        ImGui.InvisibleButton(ctx, "##du_ib"..ci, cw_du, FUNC.sz(20))
        if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left()) and FUNC.try_dbl("du"..ci) then FUNC.open_edit() end
        FUNC.cell_post(ci, c, false)
        local dx1, dy1 = ImGui.GetItemRectMin(ctx)
        local dx2, dy2 = ImGui.GetItemRectMax(ctx)
        ImGui.PushFont(ctx, FONT_MONO, FUNC.sz(14))
        local tw_du, th_du = ImGui.CalcTextSize(ctx, dtxt, 0, 0)
        ImGui.DrawList_AddText(dl, dx2 - tw_du - 4, dy1 + math.floor((dy2 - dy1 - th_du) / 2), FUNC.dim_c(C.text), dtxt)
        ImGui.PopFont(ctx)
        dur_drawn = true
      end
    end
    if not dur_drawn and c.type == "GROUP" then
      -- Bug 1: GROUP 自身被 softkill / panic 時，顯示倒數進度條 (對齊 PLAY cue 的呈現)
      -- show softkill countdown bar on GROUP row when group has been killed/panic'd
      if soft_kill[c.id] then
        local sk = soft_kill[c.id]
        local ce = reaper.time_precise() - sk.t0
        local wave = 0.5 + 0.5 * math.sin(ce * 2 * 2 * math.pi)
        local r = math.floor(100 + 60 * wave)
        local g = math.floor(25 + 35 * wave)
        local b = math.floor(20 + 20 * wave)
        local fp = FUNC.clamp(1 - ce / sk.dur, 0, 1)
        local sx, sy = ImGui.GetCursorScreenPos(ctx)
        local cw7 = ImGui.GetContentRegionAvail(ctx)
        FUNC.draw_pbar(dl, sx-FUNC.sz(3), sy-FUNC.sz(1), cw7+FUNC.sz(6), FUNC.sz(23), fp, FUNC.rgba(r,g,b),
          "kill "..FUNC.fmt_t(math.max(0, sk.dur - ce)), true)
        ImGui.InvisibleButton(ctx, "##dur_pb"..ci, cw7, FUNC.sz(18))
        if ImGui.IsItemClicked(ctx) and FUNC.try_dbl("du"..ci) then FUNC.open_edit() end
        FUNC.cell_post(ci, c, false); dur_drawn = true
        goto skip_group_dur_block
      end
      local grp_active = false
      local max_elapsed, max_dur = 0, 0
      -- soft kill不在parent顯示，只在child自己的Duration欄顯示 -- soft kill shown only on child's own progress bar
      for _, ch in ipairs(c.children or {}) do
        if ch >= 1 and ch <= #cues then
          local cc = cues[ch]
          if FUNC.cue_is_active(cc) then
            grp_active = true
            local el = reaper.time_precise() - (cc.play_t0 or 0)
            local d = cc.eff_dur > 0 and cc.eff_dur or cc.total_dur
            if d > 0 then
              max_elapsed = math.max(max_elapsed, el)
              max_dur = math.max(max_dur, d)
            end
          elseif FUNC.is_cue_paused(cc) then
            grp_active = true
            local ps = paused_cues[cc.id]
            if ps then
              local d = cc.eff_dur > 0 and cc.eff_dur or cc.total_dur
              max_elapsed = math.max(max_elapsed, ps.elapsed or 0)
              max_dur = math.max(max_dur, d)
            end
          end
        end
      end
      if grp_active then
        -- GROUP進度條：用GROUP整體時長計算 -- GROUP progress uses overall group duration
        local gdur = FUNC.calc_group_dur(c)
        if gdur <= 0 then gdur = max_dur end  -- fallback
        -- GROUP elapsed：從第一個child的play_t0算起 -- elapsed from first child's play_t0
        local g_elapsed = 0
        for _, ch2 in ipairs(c.children or {}) do
          if ch2 >= 1 and ch2 <= #cues then
            local cc2 = cues[ch2]
            if FUNC.is_cue_paused(cc2) then
              -- 暫停中：用固定的elapsed，不用time_precise() -- paused: use frozen elapsed, not real-time
              local ps2 = paused_cues[cc2.id]
              if ps2 then g_elapsed = math.max(g_elapsed, ps2.elapsed + (cc2.pre_wait or 0)) end
            elseif cc2.play_t0 and cc2.play_t0 > 0 then
              g_elapsed = math.max(g_elapsed, reaper.time_precise() - cc2.play_t0 + (cc2.pre_wait or 0))
            end
          end
        end
        local frac = gdur > 0 and FUNC.clamp(g_elapsed / gdur, 0, 1) or 0
        local sx, sy = ImGui.GetCursorScreenPos(ctx)
        local cw7 = ImGui.GetContentRegionAvail(ctx)
        local any_paused, all_paused = false, true
        for _, ch in ipairs(c.children or {}) do
          if ch >= 1 and ch <= #cues then
            if FUNC.is_cue_paused(cues[ch]) then any_paused = true
            elseif cues[ch].state == STATE.RUNNING then all_paused = false end
          end
        end
        if not any_paused then all_paused = false end  -- 沒有任何暫停就不算全暫停 -- no pause = not all paused
        local bar_col = any_paused and C.t_pause or C.p_play
        local g_prefix = all_paused and "|| " or (any_paused and "|| " or "")  -- 有任何child暫停就顯示pause icon -- show pause icon if any child paused
        FUNC.draw_pbar(dl, sx-FUNC.sz(3), sy-FUNC.sz(1), cw7+FUNC.sz(6), FUNC.sz(23), frac,
          bar_col, g_prefix..FUNC.fmt_t(g_elapsed).."/"..FUNC.fmt_t(gdur))
        ImGui.InvisibleButton(ctx, "##dur_pb"..ci, cw7, FUNC.sz(18))
        if ImGui.IsItemClicked(ctx) and FUNC.try_dbl("du"..ci) then FUNC.open_edit() end
        FUNC.cell_post(ci, c, false)
        dur_drawn = true
      else
        local gdur = FUNC.calc_group_dur(c)
        local gtxt = gdur > 0 and FUNC.fmt_t(gdur) or "--"
        -- GROUP duration空白處單擊選cue：全寬InvisibleButton + DrawList
        local cw_gd = ImGui.GetContentRegionAvail(ctx)
        ImGui.InvisibleButton(ctx, "##du_ib"..ci, cw_gd, FUNC.sz(20))
        if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left()) and FUNC.try_dbl("du"..ci) then FUNC.open_edit() end
        FUNC.cell_post(ci, c, false)
        local gx1, gy1 = ImGui.GetItemRectMin(ctx)
        local gx2, gy2 = ImGui.GetItemRectMax(ctx)
        ImGui.PushFont(ctx, FONT_MONO, FUNC.sz(14))
        local tw_gd, th_gd = ImGui.CalcTextSize(ctx, gtxt, 0, 0)
        ImGui.DrawList_AddText(dl, gx2 - tw_gd - 4, gy1 + math.floor((gy2 - gy1 - th_gd) / 2), FUNC.dim_c(C.text), gtxt)
        ImGui.PopFont(ctx)
        dur_drawn = true
      end
      ::skip_group_dur_block::
    end
    if not dur_drawn and c.type == "MIDI" then
      -- Bug 2: MIDI cue softkill 倒數條 -- MIDI softkill countdown bar
      if soft_kill[c.id] then
        local sk = soft_kill[c.id]
        local ce = reaper.time_precise() - sk.t0
        local wave = 0.5 + 0.5 * math.sin(ce * 2 * 2 * math.pi)
        local r = math.floor(100 + 60 * wave)
        local g = math.floor(25 + 35 * wave)
        local b = math.floor(20 + 20 * wave)
        local fp = FUNC.clamp(1 - ce / sk.dur, 0, 1)
        local sx, sy = ImGui.GetCursorScreenPos(ctx)
        local cw7 = ImGui.GetContentRegionAvail(ctx)
        FUNC.draw_pbar(dl, sx-FUNC.sz(3), sy-FUNC.sz(1), cw7+FUNC.sz(6), FUNC.sz(23), fp, FUNC.rgba(r,g,b),
          "kill "..FUNC.fmt_t(math.max(0, sk.dur - ce)), true)
        ImGui.InvisibleButton(ctx, "##dur_pb"..ci, cw7, FUNC.sz(18))
        if ImGui.IsItemClicked(ctx) and FUNC.try_dbl("du"..ci) then FUNC.open_edit() end
        FUNC.cell_post(ci, c, false)
        dur_drawn = true
        goto skip_midi_dur_block
      end
      if c.midi_mode ~= "control" then
        -- MIDI note mode: 顯示note duration或running進度條 -- show note duration or running progress
        if c.state == STATE.RUNNING and c.play_t0 > 0 and c.eff_dur > 0 then
          local elapsed = reaper.time_precise() - c.play_t0
          local fp = FUNC.clamp(elapsed / c.eff_dur, 0, 1)
          local sx, sy = ImGui.GetCursorScreenPos(ctx)
          local cw7 = ImGui.GetContentRegionAvail(ctx)
          FUNC.draw_pbar(dl, sx-FUNC.sz(3), sy-FUNC.sz(1), cw7+FUNC.sz(6), FUNC.sz(23), fp, TYPE_COL.MIDI,
            FUNC.fmt_t(elapsed).."/"..FUNC.fmt_t(c.eff_dur))
          local mbpm = c.midi_bpm or 120
          if mbpm > 0 then
            local beat_period = 60 / mbpm
            local beat_phase = (elapsed % beat_period) / beat_period
            local flash = math.exp(-beat_phase * 6)
            local ba = math.floor(40 + 215 * flash)
            ImGui.DrawList_AddRect(dl, sx-FUNC.sz(4), sy-FUNC.sz(2), sx+cw7+FUNC.sz(4), sy+FUNC.sz(23),
              (TYPE_COL.MIDI & 0xFFFFFF00) | ba, 3, 0, FUNC.sz(1) + FUNC.sz(3) * flash)
          end
          ImGui.InvisibleButton(ctx, "##dur_pb"..ci, cw7, FUNC.sz(18))
          FUNC.cell_post(ci, c, false)
        else
          local dtxt = FUNC.fmt_t(c.midi_duration or 0.5)
          local cw_du = ImGui.GetContentRegionAvail(ctx)
          ImGui.InvisibleButton(ctx, "##du_ib"..ci, cw_du, FUNC.sz(20))
          if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left()) and FUNC.try_dbl("du"..ci) then FUNC.open_edit() end
          FUNC.cell_post(ci, c, false)
          local dx1, dy1 = ImGui.GetItemRectMin(ctx)
          local dx2, dy2 = ImGui.GetItemRectMax(ctx)
          ImGui.PushFont(ctx, FONT_MONO, FUNC.sz(14))
          local tw_du, th_du = ImGui.CalcTextSize(ctx, dtxt, 0, 0)
          ImGui.DrawList_AddText(dl, dx2 - tw_du - 4, dy1 + math.floor((dy2 - dy1 - th_du) / 2), FUNC.dim_c(C.text), dtxt)
          ImGui.PopFont(ctx)
        end
      end
      dur_drawn = true
      ::skip_midi_dur_block::
    end
    if not dur_drawn then
      -- duration fallback空白處單擊選cue：全寬InvisibleButton + DrawList
      local cw_du2 = ImGui.GetContentRegionAvail(ctx)
      ImGui.InvisibleButton(ctx, "##du_ib"..ci, cw_du2, FUNC.sz(20))
      if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left()) and FUNC.try_dbl("du"..ci) then FUNC.open_edit() end
      FUNC.cell_post(ci, c, false)
      local fx1, fy1 = ImGui.GetItemRectMin(ctx)
      local fx2, fy2 = ImGui.GetItemRectMax(ctx)
      ImGui.PushFont(ctx, FONT_MONO, FUNC.sz(14))
      local tw_fb, th_fb = ImGui.CalcTextSize(ctx, "--", 0, 0)
      ImGui.DrawList_AddText(dl, fx2 - tw_fb - 4, fy1 + math.floor((fy2 - fy1 - th_fb) / 2), C.muted, "--")
      ImGui.PopFont(ctx)
    end
    FUNC.nav_track(7)

    -- Col 8: Post-Wait
    ImGui.TableNextColumn(ctx)
    ImGui.SetCursorPosY(ctx, ImGui.GetCursorPosY(ctx) + text_oy + grp_extra_oy)
    FUNC.nav_check(ci, 8)
    local pt = FUNC.timer_prog(ci, TIMER.POST)
    if pt then
      local sx,sy = ImGui.GetCursorScreenPos(ctx)
      local cw8 = ImGui.GetContentRegionAvail(ctx)
      -- BPM mode: 拍子倒數 + 閃爍外框 -- BPM mode: beat countdown + flash border
      local ptw_text
      if c.post_wait_mode == "bpm" and c.post_bpm_val > 0 then
        local rem = FUNC.timer_rem(ci, TIMER.POST)
        ptw_text = string.format("%d beats", math.ceil(rem * c.post_bpm_val / 60))
      else
        ptw_text = FUNC.fmt_t(FUNC.timer_rem(ci, TIMER.POST))
      end
      FUNC.draw_pbar(dl, sx-FUNC.sz(3), sy-FUNC.sz(1), cw8+FUNC.sz(6), FUNC.sz(23), pt, C.p_ptw, ptw_text, true)
      if c.post_wait_mode == "bpm" and c.post_bpm_val > 0 then
        local elapsed = pt * c.post_wait
        local beat_period = 60 / c.post_bpm_val
        local beat_phase = (elapsed % beat_period) / beat_period
        local flash = math.exp(-beat_phase * 3.5)
        local ba = math.floor(60 + 195 * flash)
        ImGui.DrawList_AddRect(dl, sx-FUNC.sz(4), sy-FUNC.sz(2), sx+cw8+FUNC.sz(4), sy+FUNC.sz(23),
          (C.p_ptw & 0xFFFFFF00) | ba, 3, 0, FUNC.sz(1) + FUNC.sz(3) * flash)
      end
      ImGui.InvisibleButton(ctx, "##pw_pb2"..ci, cw8, FUNC.sz(18))
      FUNC.cell_post(ci, c, false)
    else
      ImGui.PushFont(ctx, FONT_MONO, FUNC.sz(14))
      if FUNC.draw_ie(ci, "post_wait") then
      else
        local ptw_d, ptw_e
        if c.post_wait_mode == "bpm" then
          local post_nv = NOTE_VALUES[c.post_note_idx or NOTE_DEFAULT_IDX] or NOTE_VALUES[NOTE_DEFAULT_IDX]
          local post_cnt = math.max(0, math.floor((c.post_bpm_beats or 0) / post_nv.val + 0.5))
          ptw_d = string.format("%d %s @%d", post_cnt, post_nv.label, c.post_bpm_val or 120)
          ptw_e = string.format("%din%d", post_cnt, c.post_bpm_val or 120)
        else
          ptw_d = c.post_wait > 0 and FUNC.fmt_t(c.post_wait) or "0:00.0"
          ptw_e = c.post_wait > 0 and string.format("%.1f", c.post_wait) or ""
        end
        local cw8i = ImGui.GetContentRegionAvail(ctx)
        local tw8i,_ = ImGui.CalcTextSize(ctx, ptw_d, 0, 0)
        ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + math.max(0, (cw8i - tw8i) * 0.5))
        ImGui.PushStyleColor(ctx, ImGui.Col_Header(), 0)
        ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered(), FUNC.rgba(255,255,255,15))
        ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive(), 0)
        ImGui.Selectable(ctx, ptw_d.."##ptw"..ci, false)
        ImGui.PopStyleColor(ctx, 3)
        if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left()) then
          if FUNC.try_dbl("ptw"..ci) then FUNC.start_ie(ci, "post_wait", ptw_e)
          else drag.ptw_ci = ci end
        end
        if drag.ptw_ci == ci then
          if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left()) then
            ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS())
            local _, dy = ImGui.GetMouseDelta(ctx)
            if math.abs(dy) > 0 then
              local spd = ImGui.IsKeyDown(ctx, ImGui.Mod_Shift()) and 0.01 or 0.05
              c.post_wait = math.max(0, c.post_wait - dy * spd)
              if c.post_wait_mode == "bpm" and c.post_bpm_val > 0 then
                c.post_bpm_beats = c.post_wait * (c.post_bpm_val or 120) / 60
              end
            end
          else drag.ptw_ci = nil end
        elseif ImGui.IsItemHovered(ctx) then
          ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS())
        end
        FUNC.cell_post(ci, c, true)
      end
      ImGui.PopFont(ctx)
    end
    FUNC.nav_track(8)

    -- Col 9: Follow^
    ImGui.TableNextColumn(ctx)
    local cw10 = ImGui.GetContentRegionAvail(ctx)
    ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + math.max(0, (cw10 - FUNC.sz(18)) * 0.5))
    FUNC.nav_check(ci, 9)
    local af_ch, af_nv = ImGui.Checkbox(ctx, "##af"..ci, c.auto_go)
    if af_ch then c.auto_go = af_nv; FUNC.save_cues() end
    FUNC.nav_track(9)
    FUNC.cell_post(ci, c, false)

    -- Col 10: Kill^
    ImGui.TableNextColumn(ctx)
    local cw11 = ImGui.GetContentRegionAvail(ctx)
    ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + math.max(0, (cw11 - FUNC.sz(18)) * 0.5))
    FUNC.nav_check(ci, 10)
    local ka_ch, ka_nv = ImGui.Checkbox(ctx, "##ka"..ci, c.kill_above)
    if ka_ch then c.kill_above = ka_nv; FUNC.save_cues() end
    FUNC.nav_track(10)
    FUNC.cell_post(ci, c, false)

    -- Col 11: Loop
    ImGui.TableNextColumn(ctx)
    FUNC.nav_check(ci, 11)
    if c.type == "PLAY" or c.type == "GROUP" or c.type == "MIDI" then
      -- 播放中有限次loop：顯示剩餘次數（mono字體）；無限次維持勾勾
      -- running finite loop: show remaining count (mono font); infinite keeps checkbox
      local show_remaining = c.loop and c.state == STATE.RUNNING
        and (c.loop_count or 0) > 0 and not c.loop_done
      if show_remaining then
        local rem = c.loop_remaining or 0
        local rem_txt = tostring(rem)
        -- 閃爍效果：顏色與進度條同色，亮度脈動 -- blink: same color as progress bar, pulsing brightness
        local blink = 0.45 + 0.55 * math.abs(math.sin(reaper.time_precise() * 2.5))
        local r = ((C.p_play >> 24) & 0xFF)
        local g = ((C.p_play >> 16) & 0xFF)
        local b = ((C.p_play >> 8) & 0xFF)
        local lp_col = FUNC.rgba(math.floor(r * blink), math.floor(g * blink), math.floor(b * blink), 255)
        ImGui.PushFont(ctx, FONT_MONO, FUNC.sz(13))
        local cw_lp = ImGui.GetContentRegionAvail(ctx)
        local tw_lp = ImGui.CalcTextSize(ctx, rem_txt, 0, 0)
        ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + math.max(0, (cw_lp - tw_lp) * 0.5))
        ImGui.PushStyleColor(ctx, ImGui.Col_Text(), lp_col)
        ImGui.PushStyleColor(ctx, ImGui.Col_Header(), 0)
        ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered(), FUNC.rgba(255,255,255,15))
        ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive(), 0)
        ImGui.Selectable(ctx, rem_txt.."##lp"..ci, false)
        ImGui.PopStyleColor(ctx, 4)
        ImGui.PopFont(ctx)
        FUNC.cell_post(ci, c, false)
      else
        local cw_lp = ImGui.GetContentRegionAvail(ctx)
        ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + math.max(0, (cw_lp - FUNC.sz(18)) * 0.5))
        local lp_ch, lp_nv = ImGui.Checkbox(ctx, "##lp"..ci, c.loop)
        if lp_ch then
          c.loop = lp_nv
          if c.type == "GROUP" then
            for _, ch in ipairs(c.children or {}) do
              if ch >= 1 and ch <= #cues and (cues[ch].type == "PLAY" or cues[ch].type == "MIDI") then cues[ch].loop = lp_nv end
            end
          end
          FUNC.save_cues()
        end
        FUNC.cell_post(ci, c, false)
      end
    else
      FUNC.cell_sel(ci, c, " ", "lp")
    end
    FUNC.nav_track(11)

    -- Col 12: Notes
    ImGui.TableNextColumn(ctx)
    FUNC.nav_check(ci, 12)
    if not FUNC.draw_ie(ci, "notes") then
      local nd2 = c.notes ~= "" and c.notes:gsub("\n", " ") or ""
      local nc2 = c.notes ~= "" and C.text or C.muted
      ImGui.PushStyleColor(ctx, ImGui.Col_Text(), nc2)
      ImGui.PushStyleColor(ctx, ImGui.Col_Header(), 0)
      ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered(), FUNC.rgba(255,255,255,15))
      ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive(), 0)
      if ImGui.Selectable(ctx, (nd2 ~= "" and nd2 or " ").."##nt"..ci, false, ImGui.SelectableFlags_AllowDoubleClick()) then
        if FUNC.try_dbl("nt"..ci) then FUNC.start_ie(ci, "notes", c.notes) end
      end
      ImGui.PopStyleColor(ctx, 4)
      FUNC.cell_post(ci, c, false)
    end
    FUNC.nav_track(12)

    local _, ry2 = ImGui.GetCursorScreenPos(ctx)
    if tbl.row_screen[ci] then tbl.row_screen[ci].y_bot = ry2 end
    FUNC.draw_row_menu(ci, c)

    ::continue::
  end

  tbl.nav_row = -1
  local _, body_ey = ImGui.GetCursorScreenPos(ctx)
  tbl.y2 = body_ey  -- body底部Y座標 -- bottom of table body
  ImGui.PopFont(ctx)

  -- Group borders
  local grp_dl = ImGui.GetWindowDrawList(ctx)
  local _, wy = ImGui.GetWindowPos(ctx)
  local _, wh = ImGui.GetWindowSize(ctx)
  -- edit panel展開時在child內，不需扣除bottom bar高度 -- clip rect fix for child window
  local clip_bot = popup.edit and (wy + wh) or (wy + wh - FUNC.sz(56))

  -- focus 外框：focus 時畫淡黃色，剛 focus 時亮一下再回穩定值（0.5s fade）
  -- focus outline: light yellow; flashes brighter on focus-gain then settles (0.5s fade)
  -- 下緣 clip 到 edit_panel 上方，避免穿過 edit_panel -- clamp bottom so it doesn't cross into edit panel area
  -- 有 popup（含 combo dropdown）開啟時不畫焦點框，避免蓋住 popup
  -- skip focus outline when any popup is open so it doesn't cover dropdowns/popups
  local any_popup_for_focus = ImGui.IsPopupOpen(ctx, "", ImGui.PopupFlags_AnyPopupId() | ImGui.PopupFlags_AnyPopupLevel())
  -- ui_edit 收合時 ui_table 是唯一 focus 對象，無需畫框 -- when edit panel collapsed, table is the only focus target, skip outline
  if tbl.focused and popup.edit and not any_popup_for_focus then
    local f_dl = ImGui.GetForegroundDrawList(ctx)
    local f_top = (hdr_rects[0] and hdr_rects[0].y) or tbl.y1
    -- edit panel 開啟時底邊直接貼齊 ui_edit 上緣（clip_bot），不被 tbl.y2 拉短
    -- when edit panel open, bottom hugs ui_edit top edge regardless of cue count
    local f_bot = popup.edit and clip_bot or math.min(tbl.y2 + 1, clip_bot)
    local base_a = 140
    local a = base_a
    if tbl._focus_flash_t then
      local age = reaper.time_precise() - tbl._focus_flash_t
      if age < 0.5 then
        a = math.floor(base_a + (255 - base_a) * (1 - age / 0.5))
      else
        tbl._focus_flash_t = nil
      end
    end
    ImGui.DrawList_AddRect(f_dl, tbl.x1 - 1, f_top - 1, tbl.x2 + 1, f_bot, FUNC.rgba(255, 220, 80, a), 0, 0, FUNC.sz(2))
  end
  -- column reorder guide line繪製（從header頂到table可見區域底，不受cue數量影響）
  -- draw column reorder guide line (header top to visible table bottom, independent of cue count)
  if col_guide_x then
    local hdr_y1 = hdr_rects[0] and hdr_rects[0].y or tbl.y1
    local fdl = ImGui.GetForegroundDrawList(ctx)
    ImGui.DrawList_AddLine(fdl, col_guide_x, hdr_y1, col_guide_x, clip_bot, FUNC.rgba(255, 200, 50, 220), 3)
  end
  ImGui.DrawList_PushClipRect(grp_dl, tbl.x1 - 4, tbl.y1, tbl.x2 + 2, clip_bot, false)  -- 框線修復: 右邊不超過 scrollbar
  -- 先收集所有group的bottom y以偵測重疊 -- collect bottom y values to detect overlap
  local grp_rects = {}
  for gid, g in pairs(group_rows) do
    local rs_first = tbl.row_screen[g.first]
    local rs_last = tbl.row_screen[g.last]
    if rs_first and rs_last then
      local col = FUNC.get_grp_color(gid)
      local y1 = rs_first.y
      local y2 = rs_last.y_bot or (rs_last.y + FUNC.sz(22))
      local d = g.depth or 0
      grp_rects[#grp_rects+1] = {gid=gid, y1=y1, y2=y2, depth=d, col=col}
    end
  end
  -- 按depth排序：深的先畫，淺的後畫（parent蓋在child外面）-- sort by depth: deeper first
  table.sort(grp_rects, function(a,b) return a.depth > b.depth end)
  for _, gr in ipairs(grp_rects) do
    local x_off = gr.depth * FUNC.sz(12)
    local bw = FUNC.sz(3)
    -- 檢查是否有更深的child group共用同一bottom邊 -- check if deeper child shares same bottom
    local bot_shift = 0
    for _, other in ipairs(grp_rects) do
      if other.depth > gr.depth and math.abs(other.y2 - gr.y2) < 2 then
        bot_shift = bw  -- 下移一個線寬，露出child的底線 -- shift down to show child's bottom border
        break
      end
    end
    ImGui.DrawList_AddRect(grp_dl, tbl.x1 - 2 + x_off, gr.y1, tbl.x2 + 2, gr.y2 + bot_shift,
      FUNC.dim_c(gr.col), 0, 0, bw)
  end
  -- SPACER：不透明背景蓋住column lines + 對齊文字（無邊線，像單一儲存格）-- SPACER: opaque bg covers column lines + aligned text (no borders, like a single cell)
  for _, sp in ipairs(spacer_rows) do
    local rs = tbl.row_screen[sp.ci]
    if rs and rs.y then
      local sc = sp.c
      local rh = sp.h or FUNC.sz(22)
      -- 全列背景色（spacer可自訂alpha）-- spacer bg with customizable alpha
      local sp_a = sc.spacer_alpha or 255
      local bg_col = (sc.cue_color and sc.cue_color > 0) and FUNC.col2im(sc.cue_color, sp_a) or FUNC.rgba(40,40,55,sp_a)
      ImGui.DrawList_AddRectFilled(grp_dl, tbl.x1, rs.y, tbl.x2, rs.y + rh, bg_col)
      -- 選取highlight -- selection highlight
      if FUNC.is_sel(sp.ci) then
        ImGui.DrawList_AddRectFilled(grp_dl, tbl.x1, rs.y, tbl.x2, rs.y + rh, FUNC.rgba(150,150,150,60))
      end
      -- 對齊文字（非編輯模式）支援粗體 -- aligned text (display mode) with bold support
      local editing = ie.active and ie.row == sp.ci and ie.col == "notes"
      if not editing then
        local label = (sc.notes ~= "" and sc.notes ~= nil) and sc.notes or ""
        if label ~= "" then
          local use_bold = sc.spacer_bold
          if use_bold then ImGui.PushFont(ctx, FONT_B, FUNC.sz(13)) end
          local tw, th = ImGui.CalcTextSize(ctx, label)
          local align = sc.spacer_align or 1
          local pad = FUNC.sz(8)
          local row_w = tbl.x2 - tbl.x1
          local txt_x
          if align == 0 then txt_x = tbl.x1 + pad          -- 左對齊 left
          elseif align == 2 then txt_x = tbl.x2 - tw - pad -- 右對齊 right
          else txt_x = tbl.x1 + (row_w - tw) * 0.5 end    -- 置中 center
          local txt_y = rs.y + (rh - th) * 0.5
          local txt_col
          if sc.spacer_text_color and sc.spacer_text_color > 0 then
            txt_col = FUNC.col2im(sc.spacer_text_color, 230)
          elseif sc.cue_color and sc.cue_color > 0 then
            -- auto contrast: luminance-based white/dark text -- 自動對比色
            local r = (sc.cue_color >> 16) & 0xFF
            local g = (sc.cue_color >> 8) & 0xFF
            local b = sc.cue_color & 0xFF
            local lum = 0.299 * r + 0.587 * g + 0.114 * b
            txt_col = lum > 110 and FUNC.rgba(30,30,30,230) or FUNC.rgba(255,255,255,230)
          else
            txt_col = C.dim
          end
          ImGui.DrawList_AddText(grp_dl, txt_x, txt_y, FUNC.dim_c(txt_col), label)
          if use_bold then ImGui.PopFont(ctx) end
        end
      end
      -- 框線：左右各外擴1px蓋住table邊界 -- border: extend 1px left/right to cover table edges
      ImGui.DrawList_AddRect(grp_dl, tbl.x1 - 1, rs.y, tbl.x2 + 1, rs.y + rh, FUNC.dim_c(C.bdr))
    end
  end

  ImGui.DrawList_PopClipRect(grp_dl)

  -- SPACER inline edit overlay（獨立視窗，不受table column裁切）-- spacer edit overlay window
  for _, sp in ipairs(spacer_rows) do
    local rs = tbl.row_screen[sp.ci]
    if rs and rs.y and ie.active and ie.row == sp.ci and ie.col == "notes" then
      local rh = sp.h or FUNC.sz(22)
      local ow_x, ow_y = tbl.x1, rs.y
      local ow_w, ow_h = tbl.x2 - tbl.x1, rh
      ImGui.SetNextWindowPos(ctx, ow_x, ow_y)
      ImGui.SetNextWindowSize(ctx, ow_w, ow_h)
      local wf = ImGui.WindowFlags_NoTitleBar() | ImGui.WindowFlags_NoResize()
              | ImGui.WindowFlags_NoMove() | ImGui.WindowFlags_NoScrollbar()
              | ImGui.WindowFlags_NoScrollWithMouse() | ImGui.WindowFlags_NoCollapse()
              | ImGui.WindowFlags_NoBackground() | ImGui.WindowFlags_NoSavedSettings()
              | ImGui.WindowFlags_NoDocking()
      ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding(), 0, 0)
      ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding(), FUNC.sz(4), 0)  -- InputText填滿整行高 -- InputText fills row height
      local evis = ImGui.Begin(ctx, "##sp_edit_overlay", false, wf)
      ImGui.PopStyleVar(ctx, 2)
      if evis then
        ImGui.SetCursorPos(ctx, 0, 0)
        ImGui.SetNextItemWidth(ctx, ow_w)  -- 全寬InputText -- full-width InputText
        local age = reaper.time_precise() - ie.t
        if age < 0.05 then ImGui.SetKeyboardFocusHere(ctx, 0) end
        local fl = ImGui.InputTextFlags_AutoSelectAll()
        local ch, nv = ImGui.InputText(ctx, "##sp_ie_ov", ie.buf, fl)
        ie.buf = nv
        if ImGui.IsItemDeactivatedAfterEdit(ctx) then FUNC.commit_ie()
        elseif age > 0.15 and not ImGui.IsItemActive(ctx) then FUNC.commit_ie() end
      end
      ImGui.End(ctx)
      break  -- 同時只能編輯一個spacer -- only one spacer edits at a time
    end
  end

  -- Live reorder
  if drag.cue_id and ImGui.IsMouseDragging(ctx, ImGui.MouseButton_Left()) then
    local _, my = ImGui.GetMousePos(ctx)
    local fg = ImGui.GetForegroundDrawList(ctx)
    local guide_col = FUNC.rgba(0, 90, 30, 255)
    local moved = false
    local bn = drag.block_n
    local row_h = FUNC.sz(22)
    local anchor_ci = drag.src_ci + drag.click_off
    local anchor_rs = tbl.row_screen[anchor_ci]

    -- 計算收合GROUP的子孫數量 -- count descendants of a collapsed GROUP
    local function collapsed_desc_n(ci)
      local gc = cues[ci]
      if not gc or gc.type ~= "GROUP" or not collapsed_groups[gc.id] then return 0 end
      local n = 0
      for j = ci + 1, #cues do
        local gid = cues[j].group_id; local ok = false
        while gid do
          if gid == gc.id then ok = true; break end
          local _, pc = FUNC.find_id(gid); if not pc then break end; gid = pc.group_id
        end
        if ok then n = n + 1 else break end
      end
      return n
    end
    -- 找到ci所屬的最上層收合GROUP起始位置 -- find topmost collapsed group root for ci
    local function collapsed_root(ci)
      local c2 = cues[ci]; if not c2 then return ci end
      local root = ci
      local gid = c2.group_id
      while gid do
        if collapsed_groups[gid] then
          local gi = FUNC.find_id(gid); if gi then root = gi end
        end
        local _, pc = FUNC.find_id(gid); if not pc then break end; gid = pc.group_id
      end
      return root
    end

    -- 向下移動：收合GROUP整塊搬 -- move DOWN: treat collapsed GROUP as atomic block
    local after_ci = drag.src_ci + bn
    if not moved and after_ci <= #cues and anchor_rs and anchor_rs.y then
      local anchor_bot = anchor_rs.y_bot or (anchor_rs.y + row_h)
      -- 預判 down 的 blk_n 與門檻：深度阻擋整塊跳要求滑鼠越過該 nest 的最後一行底邊，
      -- 避免在 nest 區間內反覆觸發來回交錯 -- avoid oscillation: use far-edge threshold for atomic skip
      local ca = cues[after_ci]
      local blk_n = 1
      if ca and ca.type == "GROUP" and collapsed_groups[ca.id] then
        blk_n = 1 + collapsed_desc_n(after_ci)
      end
      local skip_atomic = false
      local X = cues[drag.src_ci]
      if X and X.type == "GROUP" then
        local s_ci, e_ci = FUNC.drag_skip_range(after_ci, X)
        if s_ci and s_ci == after_ci then
          blk_n = math.max(blk_n, e_ci - s_ci + 1)
          skip_atomic = true
        end
      end
      local trigger_y
      if skip_atomic then
        -- 觸發點 = 交錯後 drag block 著地的頂邊（考慮兩者高度）
        -- post-swap drag-block top edge: row_screen[after_ci + blk_n - bn].y
        local land_idx = after_ci + blk_n - bn
        local land_rs = tbl.row_screen[land_idx]
        trigger_y = (land_rs and land_rs.y) or (anchor_bot + row_h * (blk_n - bn + 1))
        -- 滑鼠進入 nest 區域但尚未到交錯點 → 持續警告
        if my > anchor_bot then FUNC.warn_max_depth() end
      else
        trigger_y = anchor_bot + row_h * 0.5
      end
      if my > trigger_y then
        local block = {}
        for i = 1, blk_n do block[i] = table.remove(cues, after_ci) end
        for i = blk_n, 1, -1 do table.insert(cues, drag.src_ci, block[i]) end
        drag.src_ci = drag.src_ci + blk_n  -- 拖曳不重排number -- no renumber on drag
        selected = {}
        for i = drag.src_ci, drag.src_ci + bn - 1 do selected[i] = true end
        FUNC.update_drag_groups()
        moved = true
      end
    end

    -- 向上移動：如果上方cue在收合GROUP內，整塊搬 -- move UP: if above cue is inside collapsed GROUP, move entire block
    if not moved and drag.src_ci > 1 and anchor_rs and anchor_rs.y then
      -- 深度阻擋整塊跳：門檻拉到 nest 第一行頂邊，避免區間內反覆來回觸發
      local Xup = cues[drag.src_ci]
      local skip_s, skip_e = nil, nil
      if Xup and Xup.type == "GROUP" then
        skip_s, skip_e = FUNC.drag_skip_range(drag.src_ci - 1, Xup)
      end
      local skip_atomic = (skip_s and skip_e == drag.src_ci - 1)
      local trigger_y
      if skip_atomic then
        -- 觸發點 = 交錯後 drag block 著地的底邊（考慮兩者高度）
        -- post-swap drag-block bottom edge: row_screen[skip_s + bn - 1].y_bot
        local land_idx = skip_s + bn - 1
        local land_rs = tbl.row_screen[land_idx]
        local next_rs = tbl.row_screen[land_idx + 1]
        trigger_y = (land_rs and (land_rs.y_bot or (land_rs.y + row_h)))
                 or (next_rs and next_rs.y)
                 or (anchor_rs.y - row_h * (skip_e - skip_s + 1 - bn + 1))
        -- 滑鼠進入 nest 區域但尚未到交錯點 → 持續警告
        if my < anchor_rs.y then FUNC.warn_max_depth() end
      else
        trigger_y = anchor_rs.y - row_h * 0.5
      end
      if my < trigger_y then
        local above_ci = drag.src_ci - 1
        local root = collapsed_root(above_ci)
        if skip_atomic then
          local blk_n = skip_e - skip_s + 1
          local block = {}
          for i = 1, blk_n do block[i] = table.remove(cues, skip_s) end
          local ins = drag.src_ci - blk_n + bn
          for i = 1, blk_n do table.insert(cues, ins + i - 1, block[i]) end
          drag.src_ci = drag.src_ci - blk_n
        elseif root < above_ci then
          -- 上方cue在收合GROUP內，搬整塊 -- above cue is inside collapsed group, move entire block
          local blk_n = above_ci - root + 1
          local block = {}
          for i = 1, blk_n do block[i] = table.remove(cues, root) end
          local ins = drag.src_ci - blk_n + bn
          for i = 1, blk_n do table.insert(cues, ins + i - 1, block[i]) end
          drag.src_ci = drag.src_ci - blk_n  -- 拖曳不重排number
        else
          local c = table.remove(cues, drag.src_ci - 1)
          table.insert(cues, drag.src_ci - 1 + bn, c)
          drag.src_ci = drag.src_ci - 1  -- 拖曳不重排number
        end
        selected = {}
        for i = drag.src_ci, drag.src_ci + bn - 1 do selected[i] = true end
        FUNC.update_drag_groups()
      end
    end

    if drag.src_ci then
      local rs = tbl.row_screen[drag.src_ci]
      local last_ci = drag.src_ci + bn - 1
      local rs_last = tbl.row_screen[last_ci]
      if rs and rs.y then
        local y_bot = (tbl.row_screen[last_ci + 1] and tbl.row_screen[last_ci + 1].y)
                  or (rs_last and rs_last.y_bot)
                  or (rs.y + FUNC.sz(22) * bn)
        ImGui.DrawList_AddRect(fg, tbl.x1, rs.y, tbl.x2, y_bot, FUNC.dim_c(guide_col), 0, 0, FUNC.sz(3))
      end
    end

  elseif drag.cue_id and not ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left()) then
    FUNC.settle_drag_colors()  -- drag 結束後根據起點/終點結算 cue 顏色繼承
    undo.paused = false; undo.last_snap = FUNC.snap_cues()
    FUNC.save_cues()
    if drag.multi and drag.src_ci then
      selected = {}
      for i = drag.src_ci, drag.src_ci + drag.block_n - 1 do selected[i] = true end
    end
    drag.cue_id = nil; drag.src_ci = nil; drag.backup = nil; drag._depth_warned = nil
    drag.multi = false; drag.block_n = 1
  end

  if drag.pending_desel_ci and not drag.cue_id and ImGui.IsMouseReleased(ctx, ImGui.MouseButton_Left()) then
    FUNC.sel1(drag.pending_desel_ci); drag.pending_desel_ci = nil
  elseif drag.cue_id then
    drag.pending_desel_ci = nil
  end

  if #cues == 0 and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right()) then
    ImGui.OpenPopup(ctx, "emptymenu")
  end
  if ImGui.BeginPopup(ctx, "emptymenu") then
    if FUNC.has_clipboard() then
      if ImGui.Selectable(ctx, "Paste") then FUNC.do_paste(0) end
    else
      ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha(), 0.35)
      ImGui.Selectable(ctx, "Paste"); ImGui.PopStyleVar(ctx, 1)
    end
    ImGui.EndPopup(ctx)
  end

  -- hover target column時高亮目標cue外框 -- highlight target cue row when hovering target column
  if target_hover_id then
    for ci2 = 1, #cues do
      if cues[ci2] and cues[ci2].id == target_hover_id then
        local rs2 = tbl.row_screen[ci2]
        if rs2 and rs2.y then
          local y_bot = rs2.y_bot or (rs2.y + FUNC.sz(22))
          local fg2 = ImGui.GetForegroundDrawList(ctx)
          ImGui.DrawList_AddRect(fg2, tbl.x1, rs2.y, tbl.x2, y_bot, FUNC.rgba(255, 230, 50, 220), 0, 0, FUNC.sz(2))  -- 鮮黃色同拖曳highlight -- bright yellow matching drag highlight
        end
        break
      end
    end
  end

  -- 全視窗dim遮罩：任一 popup 開啟皆覆蓋，alpha 緩升仿 ImGui ModalWindowDimBg 過渡
  -- full dim overlay with alpha fade-in matching ImGui's modal dim animation
  local any_pop = popup.warn or popup.warn_missing or popup.fxe_missing
              or popup.settings or popup.save or popup.load
              or popup.output_maps or popup.trim or popup.fade_edit
              or popup.sel_paste
  -- 完整對齊 ImGui ModalWindowDimBg：色 (204,204,204,89)，alpha 用 LinearSweep（rate=6.0/sec）
  -- match ImGui's Col_ModalWindowDimBg exactly: color (204,204,204,89), DimBgRatio LinearSweep at 6/sec
  if not popup._dim_anim then popup._dim_anim = 0 end
  local target = (any_pop and not rm) and 1 or 0
  local dt = ImGui.GetDeltaTime(ctx) or (1/60)
  local step = dt * 6.0
  if popup._dim_anim < target then
    popup._dim_anim = math.min(target, popup._dim_anim + step)
  elseif popup._dim_anim > target then
    popup._dim_anim = math.max(target, popup._dim_anim - step)
  end
  if popup._dim_anim > 0.001 then
    local a = math.floor(89 * popup._dim_anim)
    ImGui.DrawList_AddRectFilled(ImGui.GetForegroundDrawList(ctx), -9999, -9999, 99999, 99999, FUNC.rgba(204, 204, 204, a))
  end

  -- ====== RESET MODE: 選擇性遮罩 + 框選 + header拖曳 ======
  if rm then
    local fg = ImGui.GetForegroundDrawList(ctx)
    local dim_col = FUNC.rgba(0, 0, 0, 190)
    local mx2, my2 = ImGui.GetMousePos(ctx)
    local rd = popup.reset_drag
    local hdr_top = hdr_rects[0] and hdr_rects[0].y or tbl.y1
    -- reset mode中滑鼠按住追蹤：按下時設flag，放開時清除（防止ESC後殘留drag觸發reorder）
    -- track mouse hold: set on press, clear on release (prevents reorder after ESC cancel)
    if ImGui.IsMouseDown(ctx, 0) then
      popup.reset_mouse_hold = true
    elseif popup.reset_mouse_hold then
      popup.reset_mouse_hold = false
    end
    -- ESC取消reset mode（拖曳中也能取消，不觸發reset）-- ESC cancels reset mode (even during drag, no reset executed)
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape()) then
      popup.reset_mode = false; popup.reset_drag = nil
      -- reset_mouse_hold保留，等滑鼠放開後自然清除 -- keep mouse hold flag, cleared on mouse release
      goto reset_done  -- 跳過遮罩與reset執行 -- skip overlay and reset execution
    end
    -- 滑鼠互動：開始/更新拖曳 -- mouse: start/update drag
    if ImGui.IsMouseClicked(ctx, 0) and not rd then
      if mx2 >= tbl.x1 and mx2 <= tbl.x2 and my2 >= hdr_top then
        local from_hdr = my2 < tbl.y1
        popup.reset_drag = {sx=mx2, sy=my2, ex=mx2, ey=my2, done=false, from_hdr=from_hdr}
      end
    end
    rd = popup.reset_drag
    if rd and not rd.done then
      if ImGui.IsMouseDown(ctx, 0) then
        rd.ex = mx2; rd.ey = my2
      else
        rd.done = true
      end
    end
    -- 計算hit cells（先算再畫遮罩） -- compute hit cells before drawing overlay
    local hit_rows = {}
    local hit_cols = {}
    local esc_rows = {}  -- set版本供遮罩查詢 -- set version for overlay lookup
    if rd then
      local rx1 = math.min(rd.sx, rd.ex); local ry1 = math.min(rd.sy, rd.ey)
      local rx2 = math.max(rd.sx, rd.ex); local ry2 = math.max(rd.sy, rd.ey)
      if rd.from_hdr then
        for ci2 = 1, #cues do hit_rows[#hit_rows+1] = ci2; esc_rows[ci2] = true end
      else
        for ci2 = 1, #cues do
          local rs2 = tbl.row_screen[ci2]
          if rs2 and rs2.y then
            local row_bot = rs2.y_bot or (rs2.y + FUNC.sz(22))
            if rs2.y < ry2 and row_bot > ry1 then hit_rows[#hit_rows+1] = ci2; esc_rows[ci2] = true end
          end
        end
      end
      for hi2 = 0, 12 do
        local hr = hdr_rects[hi2]
        if hr and reset_cols[hi2] then
          if hr.x < rx2 and (hr.x + hr.w) > rx1 then hit_cols[hi2] = true end
        end
      end
    end
    -- ====== 選擇性遮罩：跳過escape區域（highlighted headers + hit cells） ======
    -- 表格外圍：全部dim -- outside table: full dim
    local colume_offset = 0
    local row_offset = 2
    ImGui.DrawList_AddRectFilled(fg, -9999, -9999, 99999, hdr_top, dim_col)       -- 表格上方 -- above header
    ImGui.DrawList_AddRectFilled(fg, -9999, tbl.y2, 99999, 99999, dim_col)        -- 表格下方 -- below body
    ImGui.DrawList_AddRectFilled(fg, -9999, hdr_top, tbl.x1 + colume_offset, tbl.y2, dim_col)    -- 表格左側 -- left of table
    ImGui.DrawList_AddRectFilled(fg, tbl.x2 - colume_offset, hdr_top, 99999, tbl.y2, dim_col)    -- 表格右側 -- right of table
    -- header列：水平條帶dim非resettable區間（含separator gaps） -- header row: horizontal strips covering non-resettable ranges including separator gaps
    local h_edge = tbl.x1
    for hi = 0, 12 do
      local hr = hdr_rects[hi]
      if hr and reset_cols[hi] then
        if hr.x > h_edge then
          ImGui.DrawList_AddRectFilled(fg, h_edge, hdr_top, hr.x + colume_offset, tbl.y1, dim_col)
        end
        h_edge = hr.x + hr.w - colume_offset  -- 下一段從右separator開始蓋 -- next strip starts covering right separator
      end
    end
    if h_edge < tbl.x2 then
      ImGui.DrawList_AddRectFilled(fg, h_edge, hdr_top, tbl.x2 + colume_offset, tbl.y1, dim_col)
    end
    -- body列：逐列處理，hit row只dim非hit欄，其餘整列dim -- body: per-row, skip hit cells
    local prev_bot = tbl.y1
    for ci = 1, #cues do
      local rs = tbl.row_screen[ci]
      if rs and rs.y then
        if rs.y > prev_bot then  -- 列間gap也dim -- dim gaps between rows
          ImGui.DrawList_AddRectFilled(fg, tbl.x1 - colume_offset, prev_bot, tbl.x2 + colume_offset, rs.y, dim_col)
        end
        local row_bot = rs.y_bot or (rs.y + FUNC.sz(22))
        if esc_rows[ci] then
          -- hit row：用水平條帶dim非hit區間（含column separator gaps） -- hit row: horizontal strips covering non-hit ranges including separator gaps
          local edge = tbl.x1
          for hi = 0, 12 do
            local hr = hdr_rects[hi]
            if hr and hit_cols[hi] then
              if hr.x > edge then  -- dim從上次edge到此hit欄左邊 -- dim from previous edge to hit column left
                ImGui.DrawList_AddRectFilled(fg, edge, rs.y, hr.x + colume_offset , row_bot, dim_col)
              end
              edge = hr.x + hr.w - colume_offset  -- 跳過hit欄，下一段從右separator開始蓋 -- skip hit column, next strip covers right separator
            end
          end
          if edge < tbl.x2 then  -- dim剩餘右側 -- dim remaining right side
            ImGui.DrawList_AddRectFilled(fg, edge, rs.y, tbl.x2 + colume_offset, row_bot, dim_col)
          end
        else
          ImGui.DrawList_AddRectFilled(fg, tbl.x1 - colume_offset, rs.y, tbl.x2 + colume_offset, row_bot, dim_col)
        end
        prev_bot = row_bot
      end
    end
    if prev_bot < tbl.y2 then  -- 最後一列下方gap -- gap below last row
      ImGui.DrawList_AddRectFilled(fg, tbl.x1 - colume_offset, prev_bot, tbl.x2 + colume_offset, tbl.y2, dim_col)
    end
    -- ====== header highlight框（遮罩之上）====== -- header highlight borders (above dim overlay)
    for hi = 0, 12 do
      local hr = hdr_rects[hi]
      if hr and hr.hov ~= nil and reset_cols[hi] then
        local blink_hz = hr.hov and 4 or 2
        local blink_on = math.sin(now_t * blink_hz * math.pi * 2) > 0
        if blink_on then
          local bcol = hr.hov and FUNC.rgba(255, 60, 60, 255) or FUNC.rgba(255, 220, 50, 255)
          ImGui.DrawList_AddRect(fg, hr.x - 1, hr.y - 1, hr.x + hr.w + 1, hr.y + hr.h + 1, bcol, 0, 0, FUNC.sz(2))
        end
      end
    end
    -- ====== 框選視覺 + 紅框 ======
    if rd then
      local rx1 = math.min(rd.sx, rd.ex); local ry1 = math.min(rd.sy, rd.ey)
      local rx2 = math.max(rd.sx, rd.ex); local ry2 = math.max(rd.sy, rd.ey)
      if not rd.done then
        ImGui.DrawList_AddRectFilled(fg, rx1 - colume_offset, ry1, rx2 + colume_offset, ry2, FUNC.rgba(255, 60, 60, 25))
        ImGui.DrawList_AddRect(fg, rx1 - colume_offset, ry1, rx2 + colume_offset, ry2, FUNC.rgba(255, 80, 80, 160), 0, 0, FUNC.sz(1))
      end
      -- hit cell紅色閃爍框 -- red blink border on hit cells
      local cell_blink = math.sin(now_t * 2 * math.pi * 2) > 0
      for _, ci2 in ipairs(hit_rows) do
        local rs2 = tbl.row_screen[ci2]
        if rs2 then
          local row_bot = rs2.y_bot or (rs2.y + FUNC.sz(22))
          for hi2 in pairs(hit_cols) do
            local hr = hdr_rects[hi2]
            if hr then
              if cell_blink then
                ImGui.DrawList_AddRect(fg, hr.x - colume_offset, rs2.y, hr.x + hr.w + colume_offset, row_bot, FUNC.rgba(255, 80, 80, 240), 0, 0, FUNC.sz(1.5))
              end
              ImGui.DrawList_AddRectFilled(fg, hr.x - colume_offset, rs2.y, hr.x + hr.w + colume_offset, row_bot, FUNC.rgba(255, 20, 20, 75))
            end
          end
        end
      end
      -- 放開滑鼠→執行reset -- on release: execute reset
      if rd.done then
        if #hit_rows > 0 and next(hit_cols) then
          FUNC.push_undo()
          for _, ci2 in ipairs(hit_rows) do
            local cc = cues[ci2]
            if cc and cc.type ~= "SPACER" then
              for hi2 in pairs(hit_cols) do
                if reset_cols[hi2] then reset_cols[hi2](cc) end
              end
            end
          end
          if hit_cols[7] then for _, cc in ipairs(cues) do FUNC.wf_invalidate(cc.id) end end
          FUNC.save_cues()
        end
        popup.reset_mode = false; popup.reset_drag = nil
      end
    end
  end
  ::reset_done::
  -- reset_mouse_hold：非reset mode時，滑鼠放開就清除 -- clear mouse hold flag on release outside reset mode
  if not popup.reset_mode and popup.reset_mouse_hold and not ImGui.IsMouseDown(ctx, 0) then
    popup.reset_mouse_hold = false
  end

  ImGui.EndTable(ctx)
end
