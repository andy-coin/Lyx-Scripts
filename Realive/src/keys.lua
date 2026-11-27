-- ==========================================================================
-- keys.lua — Keyboard Handling
-- ==========================================================================

-- edit panel不算modal popup，不擋快捷鍵（但edit panel的InputText有focus時另外處理）
function FUNC.any_popup_open() return popup.save or popup.load or popup.settings or popup.trim or popup.fade_edit or popup.warn or popup.warn_missing or popup.midi_sv or popup.sel_paste end

-- 檢查cue是否被收合GROUP隱藏 -- check if cue is hidden inside a collapsed GROUP
local function is_collapsed_child(ci)
  local c = cues[ci]; if not c then return false end
  local gid = c.group_id
  while gid do
    if collapsed_groups[gid] then return true end
    local _, gc = FUNC.find_id(gid)
    if not gc then break end
    gid = gc.group_id
  end
  return false
end

function FUNC.handle_keys()
  local sf = FUNC.sel_first()

  -- 依滑鼠點擊位置更新 cue_table focus；用於擋 edit panel 編輯時誤觸 Delete
  -- update cue_table focus by mouse click location (guard Delete from accidental cue removal)
  if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left()) or ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right()) then
    local mx, my = ImGui.GetMousePos(ctx)
    local new_focused = (mx >= tbl.x1 and mx <= tbl.x2 and my >= tbl.y1 and my <= tbl.y2)
    -- 從 false→true 觸發閃爍 -- trigger flash on focus gain
    if new_focused and not tbl.focused then tbl._focus_flash_t = reaper.time_precise() end
    tbl.focused = new_focused
  end

  -- Escape: close popups or panic (always hardcoded)
  -- false = 不吃自動重複：按住 Esc 不會把「淡出 Panic」變成第二下的「立刻全停」
  -- false = no auto-repeat: holding Esc must not turn a fade-out Panic into the second-press hard stop
  if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape(), false) then
    if ie.active then ie.active = false; return
    elseif hotkey_listen then hotkey_listen = false; return  -- 取消hotkey監聽
    elseif scut_listen then scut_listen = nil; return  -- 取消shortcut監聽
    elseif popup._cp_key then popup._cp_cancel = true; return  -- 色票開著：Esc = Cancel，不關設定 -- color picker open: Esc = Cancel, keep Settings
    elseif popup.shortcuts then popup.shortcuts = false; return  -- 關閉shortcut panel
    elseif popup.reset_mode then popup.reset_mode = false; popup.reset_drag = nil; return
    elseif FUNC.any_popup_open() then
      popup.save=false;popup.load=false;popup.settings=false;popup.trim=false;popup.fade_edit=false;popup.edit=false;popup.warn=false;popup.warn_missing=false;popup.midi_sv=false;popup.sel_paste=false
    else FUNC.panic() end
    return
  end

  -- Inline edit active: block other keys (edit panel不擋快捷鍵，已合併到主視窗)
  if ie.active then return end
  -- edit panel的Name/Notes輸入框有focus時，全部快捷鍵讓給InputText
  if popup.edit_text_active then return end
  -- shortcut監聽模式中，所有快捷鍵讓給監聽 -- block shortcuts during key listen mode
  if scut_listen then return end
  -- hotkey監聽模式中，所有快捷鍵讓給監聽 -- block shortcuts during hotkey listen mode
  if hotkey_listen then return end

  -- popup開啟時只允許Escape和Enter，其餘全部bypass -- block all keys except Escape/Enter when popup is open
  if FUNC.any_popup_open() then
    -- Enter=確認/儲存 popup（各popup自行處理Enter） -- Enter handled by each popup internally
    return
  end

  -- reset mode toggle（在block前檢查，允許toggle off） -- toggle before block
  if FUNC.sc_check("reset_cols") then popup.reset_mode = not popup.reset_mode; return end
  -- reset mode：其餘快捷鍵全部block，由header InvisibleButton處理點擊 -- reset mode: block all keys, header handles clicks
  if popup.reset_mode then return end

  -- Navigation (hardcoded: arrows, delete)
  if ImGui.IsKeyPressed(ctx, ImGui.Key_UpArrow()) then
    local nw
    if ImGui.IsKeyDown(ctx, ImGui.Mod_Shift()) then
      nw = next_go - 1
      while nw >= 1 and is_collapsed_child(nw) do nw = nw - 1 end  -- 略過收合children
      if nw < 1 then nw = next_go; selected[next_go] = true
      else
        if next_go == sf then
          -- 擴展選取：連同collapsed children一起選 -- extend: select collapsed children in between
          for i = nw, next_go do selected[i] = true end
        elseif next_go > sf then
          -- 縮減選取：連同collapsed children一起取消 -- shrink: deselect collapsed children in between
          for i = nw + 1, next_go do selected[i] = nil end
        end
      end
    else
      nw = next_go - 1
      while nw >= 1 and is_collapsed_child(nw) do nw = nw - 1 end  -- 略過收合children
      if nw < 1 then nw = next_go end
      FUNC.sel1(nw)
    end
    next_go = nw; last_click = nw; tbl.nav_row = nw; tbl.nav_dir = -1
    FUNC.push_undo()
  end
  if ImGui.IsKeyPressed(ctx, ImGui.Key_DownArrow()) then
    local nw
    if ImGui.IsKeyDown(ctx, ImGui.Mod_Shift()) then
      nw = next_go + 1
      while nw <= #cues and is_collapsed_child(nw) do nw = nw + 1 end  -- 略過收合children
      if nw > #cues then nw = next_go; selected[next_go] = true
      else
        -- 用sel_list找最後一個可見選取項，取代 sf+sel_cnt-1 -- use last visible selected instead of sf+sel_cnt-1
        local sl = FUNC.sel_list()
        local last_vis = sf
        for i = #sl, 1, -1 do if not is_collapsed_child(sl[i]) then last_vis = sl[i]; break end end
        if next_go >= last_vis then
          -- 擴展選取：連同collapsed children一起選 -- extend: select collapsed children in between
          for i = next_go, nw do selected[i] = true end
        elseif next_go < last_vis then
          -- 縮減選取：連同collapsed children一起取消 -- shrink: deselect collapsed children in between
          for i = next_go, nw - 1 do selected[i] = nil end
        end
      end
    else
      nw = next_go + 1
      while nw <= #cues and is_collapsed_child(nw) do nw = nw + 1 end  -- 略過收合children
      if nw > #cues then nw = next_go end
      FUNC.sel1(nw)
    end
    next_go = nw; last_click = nw; tbl.nav_row = nw; tbl.nav_dir = 1
    FUNC.push_undo()
  end
  if ImGui.IsKeyPressed(ctx, ImGui.Key_Delete()) or ImGui.IsKeyPressed(ctx, ImGui.Key_Backspace()) then
    -- edit panel開+有選取envelope點→交給envelope.lua的handler處理（支援vol/pan mode）
    if popup.edit and next(env_drag.sel) then
      -- skip, envelope.lua env_draw裡的Delete handler會處理
    elseif popup.edit and popup.route_sel and next(popup.route_sel) then
      -- route tab有選中channel → 刪除channel而非cue -- route tab has selected channels → delete channels
      local el = popup.edit_list
      if el and #el == 1 then
        local c = cues[el[1]]
        if c and c.route_hw then
          local to_del = {}
          for idx in pairs(popup.route_sel) do if idx >= 1 and idx <= #c.route_hw then to_del[#to_del+1] = idx end end
          table.sort(to_del, function(a,b) return a > b end)
          for _, di in ipairs(to_del) do table.remove(c.route_hw, di) end
          popup.route_sel = {}
          FUNC.route_apply_live(c)
          FUNC.save_cues()
        end
      end
    elseif tbl.focused then
      FUNC.remove_selected()
    end
    -- cue_table 未 focused：不刪 cue（避免 edit panel 編輯時誤觸）
    -- not focused: ignore Delete on cues (prevents accidental delete while editing panel)
  end

  -- Cmd/Ctrl shortcuts (hardcoded)
  if ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl()) then
    if ImGui.IsKeyPressed(ctx, ImGui.Key_C()) then FUNC.do_copy() end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_X()) then FUNC.do_cut() end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_V()) then
      if ImGui.IsKeyDown(ctx, ImGui.Mod_Shift()) then
        -- Cmd+Shift+V：選擇性貼上 popup（N=1 廣播或 N=M 一對一才開）
        local N = FUNC.clipboard_count()
        local M = FUNC.sel_cnt()
        if N == 0 or M == 0 then
          -- 安靜忽略：沒 clipboard 或沒選 cue -- silently ignore
        elseif N == 1 or N == M then
          popup.sel_paste = true
          popup.sel_paste_msg = nil
        else
          FUNC.warn_toolbar(string.format("Selective paste: clipboard %d, selected %d (need N=1 or N=M)", N, M))
        end
      else
        FUNC.do_paste(sf > 0 and sf or #cues)
      end
    end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_R()) then FUNC.reset_show() end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Z()) then
      if ImGui.IsKeyDown(ctx, ImGui.Mod_Shift()) then FUNC.do_redo() else FUNC.do_undo() end
    end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_A()) then  -- Cmd+A 全選
      selected = {}
      for ci = 1, #cues do selected[ci] = true end
      if #cues > 0 then last_click = 1 end
    end
    -- Cmd+= 放大 / Cmd+- 縮小（一次5%）-- zoom in/out by 5%
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Equal()) then
      prefs.scale = math.min(200, prefs.scale + 5); FUNC.save_prefs()
    end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Minus()) then
      prefs.scale = math.max(50, prefs.scale - 5); FUNC.save_prefs()
    end
    return
  end

  -- Customizable shortcuts
  if FUNC.sc_check("go") or FUNC.sc_check("go_alt") then FUNC.go_next() end  -- GO + GO(Alt) -- 雙快速鍵
  if FUNC.sc_check("panic_alt") then FUNC.panic() end  -- Panic(Alt) -- 第二Panic鍵
  if FUNC.sc_check("preview") then FUNC.check_sel_fn() end
  if FUNC.sc_check("kill_sel") then FUNC.kill() end
  if FUNC.sc_check("add_play") then FUNC.add_cue("PLAY", sf) end
  if FUNC.sc_check("add_stop") then FUNC.add_cue("STOP", sf) end
  if FUNC.sc_check("add_pause") then FUNC.add_cue("PAUSE", sf) end
  if FUNC.sc_check("add_fade") then FUNC.add_cue("FADE", sf) end
  -- group/ungroup toggle：GROUP選取時ungroup，否則group -- toggle group/ungroup
  if FUNC.sc_check("group") then
    if sf >= 1 and sf <= #cues and cues[sf].type == "GROUP" then FUNC.ungroup_cue(sf)
    elseif FUNC.sel_cnt() >= 2 then FUNC.group_sel() end
  end
  if FUNC.sc_check("fold") and sf >= 1 and sf <= #cues and cues[sf].type == "GROUP" then
    collapsed_groups[cues[sf].id] = not collapsed_groups[cues[sf].id]
  end
  -- 左右鍵：fold/unfold GROUP -- left=fold, right=unfold GROUP
  if sf >= 1 and sf <= #cues then
    if ImGui.IsKeyPressed(ctx, ImGui.Key_LeftArrow()) then
      if cues[sf].type == "GROUP" then
        if collapsed_groups[cues[sf].id] and cues[sf].group_id then
          -- 已收攏的GROUP再按左鍵：收攏parent GROUP並跳上去 -- already collapsed: fold parent and jump up
          local gi = FUNC.find_id(cues[sf].group_id)
          if gi then collapsed_groups[cues[sf].group_id] = true; next_go = gi; FUNC.sel1(gi) end
        else
          collapsed_groups[cues[sf].id] = true  -- GROUP標題列：收攏自己 -- on GROUP header: fold self
        end
      elseif cues[sf].group_id then
        local gi = FUNC.find_id(cues[sf].group_id)
        if gi then
          collapsed_groups[cues[sf].group_id] = true  -- children：收攏所屬最近GROUP（巢狀時收攏巢狀GROUP） -- on child: fold nearest parent GROUP
          next_go = gi; FUNC.sel1(gi)  -- 選取+next_go跳到GROUP標題列 -- jump selection & next_go to GROUP header
        end
      end
    end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_RightArrow()) and cues[sf].type == "GROUP" then
      collapsed_groups[cues[sf].id] = false  -- 右鍵維持：只在GROUP標題列展開 -- right: only unfold on GROUP header
    end
  end
  -- 快速鍵：edit cue number -- shortcut: edit cue number
  if FUNC.sc_check("edit_cue_num") and sf >= 1 and sf <= #cues then
    FUNC.start_ie(sf, "cue_number", cues[sf].cue_number)
  end
  -- 快速鍵：toggle edit panel -- shortcut: toggle edit panel
  if FUNC.sc_check("tog_edit") then FUNC.toggle_edit() end

  -- Per-cue hotkeys: 掃描所有cue的hotkey -- scan all cue hotkeys
  for ci, cc in ipairs(cues) do
    if cc.hotkey and cc.hotkey ~= "" and FUNC.hotkey_check(cc.hotkey) then
      preview(ci)  -- preview是cue.lua的module-level函數(含pre_wait處理)
      return
    end
  end

  -- Zoom shortcuts (customizable) -- 縮放快捷鍵
  if FUNC.sc_check("zoom_in") then prefs.scale = math.min(200, prefs.scale + 5); FUNC.save_prefs() end
  if FUNC.sc_check("zoom_out") then prefs.scale = math.max(50, prefs.scale - 5); FUNC.save_prefs() end

  -- Field shortcuts (customizable, 用sc_check) -- 快捷鍵修改欄位（可自訂）
  if sf >= 1 and sf <= #cues then
    local c = cues[sf]
    if FUNC.sc_check("edit_vol") then
      local einit = c.volume <= prefs.inf_db and "-inf" or string.format("%.1f", c.volume)
      FUNC.start_ie(sf, "volume", einit)
    end
    if FUNC.sc_check("edit_prewait") then
      FUNC.start_ie(sf, "pre_wait", string.format("%.1f", c.pre_wait))
    end
    if FUNC.sc_check("edit_postwait") then
      FUNC.start_ie(sf, "post_wait", string.format("%.1f", c.post_wait))
    end
    if FUNC.sc_check("edit_fadetime") then
      FUNC.start_ie(sf, "fade_time", string.format("%.1f", c.fade_time))
    end
    if FUNC.sc_check("tog_autogo") then
      FUNC.push_undo("Toggle Auto-Follow")
      for ci2 in pairs(selected) do if cues[ci2] then cues[ci2].auto_go = not cues[ci2].auto_go end end
      FUNC.save_cues()
    end
    if FUNC.sc_check("tog_kill") then
      FUNC.push_undo("Toggle Kill Above")
      for ci2 in pairs(selected) do if cues[ci2] then cues[ci2].kill_above = not cues[ci2].kill_above end end
      FUNC.save_cues()
    end
    if FUNC.sc_check("tog_loop") then
      FUNC.push_undo("Toggle Loop")
      for ci2 in pairs(selected) do if cues[ci2] then cues[ci2].loop = not cues[ci2].loop end end
      FUNC.save_cues()
    end
  end
end
