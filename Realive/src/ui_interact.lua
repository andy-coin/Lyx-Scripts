-- ==========================================================================
-- ui_interact.lua — Inline Edit, VDrag, Clipboard, Cell Helpers, Row Drag
-- ==========================================================================

---------------------------------------------------------------------
-- MARQUEE HELPER — 共用跑馬燈繪製（hover觸發/自動觸發）
-- draw_marquee(dl, font, fsz, text, color, sx, sy, w, h, key, opts)
--   opts.auto=true: 不用hover，自動捲動
--   opts.delay: hover到開始捲動的延遲秒數（預設0.5）
--   opts.speed: 捲動速度 px/s（預設 sz(52)）
--   opts.gap: 兩段文字間空白字元數（預設24）
--   opts.pad: 左側padding（預設 sz(2)）
-- returns: is_truncated (bool)
---------------------------------------------------------------------
function FUNC.draw_marquee(dl, font, fsz, text, color, sx, sy, w, h, key, opts)
  opts = opts or {}
  ImGui.PushFont(ctx, font, fsz)
  local tw = ImGui.CalcTextSize(ctx, text, 0, 0)
  ImGui.PopFont(ctx)
  local pad = opts.pad or FUNC.sz(2)
  local truncated = tw > (w - pad * 2)
  local mq = marquee_state[key]
  local auto = opts.auto
  local hov = not auto and ImGui.IsMouseHoveringRect(ctx, sx, sy, sx + w, sy + h)
  if truncated and (hov or auto) then
    if not mq then
      marquee_state[key] = {t_hover = reaper.time_precise(), t_scroll = auto and reaper.time_precise() or nil}
      mq = marquee_state[key]
    end
    local delay = opts.delay or 0.5
    if not mq.t_scroll and (reaper.time_precise() - mq.t_hover >= delay) then
      mq.t_scroll = reaper.time_precise()
    end
  else
    marquee_state[key] = nil; mq = nil
  end
  ImGui.DrawList_PushClipRect(dl, sx, sy, sx + w, sy + h, true)
  if mq and mq.t_scroll then
    local gap_txt = string.rep(" ", opts.gap or 24)
    local loop_txt = text .. gap_txt
    ImGui.PushFont(ctx, font, fsz)
    local loop_tw = ImGui.CalcTextSize(ctx, loop_txt, 0, 0)
    ImGui.PopFont(ctx)
    local speed = opts.speed or FUNC.sz(52)
    local elapsed = reaper.time_precise() - mq.t_scroll
    local offset = (elapsed * speed) % loop_tw
    local tx = sx + pad - offset
    ImGui.DrawList_AddTextEx(dl, font, fsz, tx, sy, color, loop_txt)
    ImGui.DrawList_AddTextEx(dl, font, fsz, tx + loop_tw, sy, color, loop_txt)
  else
    ImGui.DrawList_AddTextEx(dl, font, fsz, sx + pad, sy, color, text)
  end
  ImGui.DrawList_PopClipRect(dl)
  return truncated
end

---------------------------------------------------------------------
-- 11. INLINE EDIT + DRAG VALUE
---------------------------------------------------------------------
function FUNC.commit_ie()
  if not ie.active then return end
  if ie.row==0 and ie.col=="master" then
    local v=FUNC.parse_v(ie.buf);if v then prefs.master_vol=FUNC.clamp(v,prefs.vol_min,prefs.vol_max) end
    ie.active=false;return end
  if ie.row==0 and ie.col=="save_title" then popup.save_title_buf=ie.buf;ie.active=false;return end
  local c=cues[ie.row];if not c then ie.active=false;return end
  if ie.col=="cue_number" then
    if ie.buf=="" then c.cue_number=""  -- 允許清空Q number -- allow empty cue number
    elseif ie.buf:match("^[%d%.]+$") then c.cue_number=ie.buf end
  elseif ie.col=="name" then c.name=ie.buf
  elseif ie.col=="volume" then local v=FUNC.parse_v(ie.buf);if v then c.volume=v; if c.type=="FADE" then c.fade_vol_enabled=true end end
  elseif ie.col=="pre_wait" then
    if c.pre_wait_mode == "bpm" then
      local b,p = FUNC.parse_bpm(ie.buf)
      if b then
        local nv = NOTE_VALUES[c.pre_note_idx or NOTE_DEFAULT_IDX] or NOTE_VALUES[NOTE_DEFAULT_IDX]
        c.pre_bpm_beats = math.floor(b + 0.5) * nv.val
      end
      if p then c.pre_bpm_val = p end
      c.pre_wait = (c.pre_bpm_beats or 4) * 60 / (c.pre_bpm_val or 120)
    else local t=FUNC.parse_t(ie.buf);if t then c.pre_wait=t end end
  elseif ie.col=="post_wait" then
    if c.post_wait_mode == "bpm" then
      local b,p = FUNC.parse_bpm(ie.buf)
      if b then
        local nv = NOTE_VALUES[c.post_note_idx or NOTE_DEFAULT_IDX] or NOTE_VALUES[NOTE_DEFAULT_IDX]
        c.post_bpm_beats = math.floor(b + 0.5) * nv.val
      end
      if p then c.post_bpm_val = p end
      c.post_wait = (c.post_bpm_beats or 4) * 60 / (c.post_bpm_val or 120)
    else local t=FUNC.parse_t(ie.buf);if t then c.post_wait=t end end
  elseif ie.col=="fade_time" then
    if c.fade_wait_mode == "bpm" then
      local b,p = FUNC.parse_bpm(ie.buf)
      if b then
        local nv = NOTE_VALUES[c.fade_note_idx or NOTE_DEFAULT_IDX] or NOTE_VALUES[NOTE_DEFAULT_IDX]
        c.fade_bpm_beats = math.floor(b + 0.5) * nv.val
      end
      if p then c.fade_bpm_val = p end
      c.fade_time = (c.fade_bpm_beats or 4) * 60 / (c.fade_bpm_val or 120)
    else local t=FUNC.parse_t(ie.buf);if t then c.fade_time=t end end
  elseif ie.col=="notes" then c.notes=ie.buf
  end;ie.active=false;FUNC.save_cues()
end
function FUNC.start_ie(row,col,init) if ie.active then FUNC.commit_ie() end
  ie={active=true,row=row,col=col,buf=init or "",t=reaper.time_precise()} end
function FUNC.try_dbl(key) local now=reaper.time_precise()
  if dbl_click_t[key] and (now-dbl_click_t[key])<DBL_T then dbl_click_t[key]=nil;return true end
  dbl_click_t[key]=now;return false end

local _vd_state = {}
function FUNC.vdrag(label, val, speed, lo, hi, fmt, parse_fn, fixed_w)
  local st = _vd_state[label] or {}; _vd_state[label] = st
  local w = fixed_w and (fixed_w < 0 and (ImGui.GetContentRegionAvail(ctx) + fixed_w) or fixed_w) or ImGui.GetContentRegionAvail(ctx)  -- 負值=可用寬度-N（同ImGui慣例）-- negative = avail - N (ImGui convention)
  local h = ImGui.GetFrameHeight(ctx)
  if st.editing then
    if st.focus then ImGui.SetKeyboardFocusHere(ctx, 0); st.focus = false end
    ImGui.SetNextItemWidth(ctx, fixed_w and (fixed_w < 0 and fixed_w or fixed_w) or -1)  -- 負值直接傳給ImGui -- negative passed directly to ImGui
    local ich, inv = ImGui.InputText(ctx, "##vdi"..label, st.buf,
      ImGui.InputTextFlags_EnterReturnsTrue() | ImGui.InputTextFlags_AutoSelectAll())
    if ImGui.IsItemActive(ctx) then popup.edit_text_active = true end  -- 輸入中擋Delete等快捷鍵 -- block Delete shortcut while typing
    if ich then
      local n = parse_fn and parse_fn(inv) or tonumber(inv)
      if n then val = FUNC.clamp(n, lo, hi) end
      st.editing = false
    elseif not ImGui.IsItemActive(ctx) and st.age and st.age > 1 then
      st.editing = false
    end
    st.age = (st.age or 0) + 1
    return true, val
  end
  local txt = (fmt == "%s") and FUNC.fmt_t(val) or type(fmt) == "function" and fmt(val) or string.format(fmt, val)
  local sx, sy = ImGui.GetCursorScreenPos(ctx)
  local wdl = ImGui.GetWindowDrawList(ctx)
  local hov = ImGui.IsMouseHoveringRect(ctx, sx, sy, sx+w, sy+h)
  local bg = hov and C.btn_h or C.field
  ImGui.DrawList_AddRectFilled(wdl, sx, sy, sx+w, sy+h, bg, 3)
  local tw, th = ImGui.CalcTextSize(ctx, txt, 0, 0)
  ImGui.DrawList_AddText(wdl, sx + (w-tw)*0.5, sy + (h-th)*0.5, C.text, txt)
  if ImGui.InvisibleButton(ctx, "##vd"..label, w, h) then end
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left()) and FUNC.try_dbl("vd"..label) then
    st.editing = true; st.focus = true; st.age = 0
    st.buf = (fmt == "%s") and FUNC.fmt_t(val) or type(fmt) == "function" and tostring(val) or string.format(fmt:gsub(" dB",""):gsub(" s",""), val)
    return false, val
  end
  if ImGui.IsItemActive(ctx) then
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS())
    local _, dy = ImGui.GetMouseDelta(ctx)
    if math.abs(dy) > 0 then
      local s = speed
      if ImGui.IsKeyDown(ctx, ImGui.Mod_Shift()) then s = s * 0.1 end
      val = FUNC.clamp(val - dy * s, lo, hi)
      return true, val
    end
  elseif hov then
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS())
  end
  return false, val
end

local IE_MONO_Y_FIX = 4  -- mono字體InputText垂直偏移修正(px) -- mono font InputText vertical offset fix
local IE_MONO_COLS = {volume=true, pre_wait=true, post_wait=true, fade_time=true}

function FUNC.draw_ie(ci,col,w)
  if not(ie.active and ie.row==ci and ie.col==col) then return false end
  -- mono字體欄位的InputText偏高，往下推修正 -- fix mono font InputText vertical alignment
  local mono_fix = IE_MONO_COLS[col] and IE_MONO_Y_FIX or 0
  if mono_fix > 0 then ImGui.SetCursorPosY(ctx, ImGui.GetCursorPosY(ctx) + mono_fix) end
  ImGui.SetNextItemWidth(ctx,w or -1)
  local age=reaper.time_precise()-ie.t
  if age<0.05 then ImGui.SetKeyboardFocusHere(ctx) end
  local fl=ImGui.InputTextFlags_AutoSelectAll()
  local ch,nv=ImGui.InputText(ctx,"##ie_"..col..ci,ie.buf,fl);ie.buf=nv
  local commit = ImGui.IsItemDeactivatedAfterEdit(ctx)
  if ImGui.IsItemActive(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Tab()) then
    FUNC.commit_ie()
    -- 跳過SPACER和收合GROUP的children -- skip spacers and collapsed group children
    local next_ci = ci + 1
    while next_ci <= #cues do
      local nc2 = cues[next_ci]
      if nc2.type == "SPACER" then next_ci = next_ci + 1
      elseif nc2.group_id and collapsed_groups[nc2.group_id] then next_ci = next_ci + 1
      else break end
    end
    if next_ci >= 1 and next_ci <= #cues then
      local nc = cues[next_ci]
      local init = ""
      if col=="cue_number" then init=nc.cue_number
      elseif col=="name" then init=nc.name
      elseif col=="volume" then init=nc.volume<=prefs.inf_db and "-" or string.format("%.1f",nc.volume)
      elseif col=="pre_wait" then
        if nc.pre_wait_mode=="bpm" then
          local nv = NOTE_VALUES[nc.pre_note_idx or NOTE_DEFAULT_IDX] or NOTE_VALUES[NOTE_DEFAULT_IDX]
          local cnt = math.max(0, math.floor((nc.pre_bpm_beats or 0) / nv.val + 0.5))
          init=string.format("%din%d", cnt, nc.pre_bpm_val or 120)
        else init=nc.pre_wait>0 and string.format("%.1f",nc.pre_wait) or "" end
      elseif col=="post_wait" then
        if nc.post_wait_mode=="bpm" then
          local nv = NOTE_VALUES[nc.post_note_idx or NOTE_DEFAULT_IDX] or NOTE_VALUES[NOTE_DEFAULT_IDX]
          local cnt = math.max(0, math.floor((nc.post_bpm_beats or 0) / nv.val + 0.5))
          init=string.format("%din%d", cnt, nc.post_bpm_val or 120)
        else init=nc.post_wait>0 and string.format("%.1f",nc.post_wait) or "" end
      elseif col=="fade_time" then
        if nc.fade_wait_mode=="bpm" then
          local nv = NOTE_VALUES[nc.fade_note_idx or NOTE_DEFAULT_IDX] or NOTE_VALUES[NOTE_DEFAULT_IDX]
          local cnt = math.max(0, math.floor((nc.fade_bpm_beats or 0) / nv.val + 0.5))
          init=string.format("%din%d", cnt, nc.fade_bpm_val or 120)
        else init=string.format("%.1f",nc.fade_time) end
      elseif col=="notes" then init=nc.notes
      end
      FUNC.start_ie(next_ci, col, init)
      FUNC.sel1(next_ci)
    end
    return true
  end
  if commit then FUNC.commit_ie() elseif age>0.15 and not ImGui.IsItemActive(ctx) then FUNC.commit_ie() end;return true
end

-- Clipboard system
local clipboard_cues = {}
local clipboard_cut = false

-- 展開選取：確保所有被選GROUP的子孫也被選取 -- expand selection to include all descendants of selected GROUPs
function FUNC.expand_sel_groups()
  local changed = true
  while changed do
    changed = false
    for ci = 1, #cues do
      if selected[ci] and cues[ci].type == "GROUP" then
        for j = 1, #cues do
          if cues[j].group_id == cues[ci].id and not selected[j] then
            selected[j] = true; changed = true
          end
        end
      end
    end
  end
end

function FUNC.do_copy()
  local sl = FUNC.sel_list(); if #sl == 0 then return end
  FUNC.expand_sel_groups(); sl = FUNC.sel_list()  -- 包含GROUP所有子孫 -- include all descendants
  clipboard_cues = {}
  for _, i in ipairs(sl) do clipboard_cues[#clipboard_cues+1] = FUNC.c2s(cues[i]) end
  clipboard_cut = false
end

function FUNC.do_cut()
  local sl = FUNC.sel_list(); if #sl == 0 then return end
  FUNC.push_undo()
  FUNC.expand_sel_groups(); sl = FUNC.sel_list()  -- 包含GROUP所有子孫 -- include all descendants
  clipboard_cues = {}
  for _, i in ipairs(sl) do clipboard_cues[#clipboard_cues+1] = FUNC.c2s(cues[i]) end
  clipboard_cut = true
  -- 剪下前先停掉播放中的 cue（還原軌道）-- stop cues that are playing before cutting them (gives tracks back)
  for _, i in ipairs(sl) do local q = cues[i]
    if q.state ~= STATE.IDLE or (q.preview_ids and #q.preview_ids > 0) then FUNC.hard_kill_cue(q) end
  end
  for i = #sl, 1, -1 do table.remove(cues, sl[i]) end
  FUNC.rebuild_groups()  -- 剪下後index偏移，重建children -- rebuild children after index shift
  selected = {}  -- 剪下不重排number -- cut doesn't renumber
  if #cues > 0 then
    local n = math.min(sl[1], #cues); FUNC.sel1(n); next_go = n
  else next_go = 0 end
  FUNC.save_cues()
end

function FUNC.do_paste(after_ci)
  if #clipboard_cues == 0 then return end
  FUNC.push_undo()
  local ins = (after_ci and after_ci > 0 and after_ci <= #cues) and after_ci or #cues
  local id_map = {}
  local new_cues = {}
  for _, data in ipairs(clipboard_cues) do
    local nc = FUNC.s2c(data)
    local old_id = nc.id
    nc.id = FUNC.nid()
    id_map[old_id] = nc.id
    nc.state = STATE.IDLE; nc.preview_ids = {}; nc.play_t0 = 0
    -- 貼上PLAY cue時複製REAPER軌道，確保envelope獨立 -- duplicate track on paste for independent envelope
    if nc.type == "PLAY" then
      -- 每次dup_track會插入新track使index偏移，需先用GUID取得正確index -- resolve GUID first since each dup shifts indices
      local src_idx = nc.track_idx
      if nc.track_guid and nc.track_guid ~= "" then
        local resolved = FUNC.guid_to_idx(nc.track_guid)
        if resolved >= 0 then src_idx = resolved end
      end
      if src_idx >= 0 then
        local new_idx, new_guid = FUNC.dup_track(src_idx)
        if new_idx >= 0 then nc.track_idx = new_idx; nc.track_guid = new_guid end
      end
    end
    new_cues[#new_cues+1] = nc
  end
  for _, nc in ipairs(new_cues) do
    if nc.target_cue_id ~= "" and id_map[nc.target_cue_id] then
      nc.target_cue_id = id_map[nc.target_cue_id]
    end
    if nc.group_id and id_map[nc.group_id] then
      nc.group_id = id_map[nc.group_id]
    elseif nc.group_id and not id_map[nc.group_id] then
      nc.group_id = nil
    end
  end
  -- 解析貼上目的地的 group 上下文：右鍵在 GROUP cue → 變其 child；否則繼承該 cue 的 group_id
  -- resolve destination group from after_ci: if it's a GROUP, become child; else inherit its group_id
  local dest_gid = nil
  local dst = cues[ins]
  if dst then
    if dst.type == "GROUP" then dest_gid = dst.id
    else dest_gid = dst.group_id end
  end
  -- 頂層貼上的 cue（group_id 沒被 id_map 改寫成新 id 的）採用 dest_gid，使 paste 反映實際落點
  -- top-level pasted cues adopt dest_gid so depth check reflects real landing spot
  for _, nc in ipairs(new_cues) do
    if not nc.group_id then nc.group_id = dest_gid end
  end
  -- 插入前深度預檢（uncapped）：含現有 cue 解析 group 鏈，超過 MAX_GROUP_DEPTH 則中止 paste 且保留 clipboard
  -- pre-insert uncapped depth check; abort + keep clipboard if any pasted cue would exceed limit
  local new_id_set = {}
  local new_id_to_gid = {}
  for _, nc in ipairs(new_cues) do new_id_set[nc.id] = true; new_id_to_gid[nc.id] = nc.group_id end
  local function uncapped_depth(start_gid)
    local d, gid, guard = 0, start_gid, 0
    while gid and guard < 100 do
      d = d + 1; guard = guard + 1
      local pg
      if new_id_set[gid] then pg = new_id_to_gid[gid]
      else local _, gc = FUNC.find_id(gid); pg = gc and gc.group_id or nil end
      gid = pg
    end
    return d
  end
  for _, nc in ipairs(new_cues) do
    if uncapped_depth(nc.group_id) > MAX_GROUP_DEPTH then
      FUNC.warn_max_depth()
      return  -- 中止 paste，保留 clipboard 不清空 -- abort, keep clipboard intact
    end
  end
  for i, nc in ipairs(new_cues) do table.insert(cues, ins + i, nc) end
  FUNC.rebuild_groups()  -- 重建所有GROUP的children（插入後index偏移，舊的手動重建會漏掉既有GROUP）-- rebuild ALL groups since indices shifted after insert
  -- 貼上的每個cue各自分配number -- assign number for each pasted cue
  for i = 1, #new_cues do FUNC.assign_number(ins + i) end
  selected = {}
  for i = 1, #new_cues do selected[ins + i] = true end
  next_go = ins + 1; last_click = ins + 1
  if clipboard_cut then clipboard_cues = {}; clipboard_cut = false end
  FUNC.save_cues()
end

function FUNC.has_clipboard() return #clipboard_cues > 0 end
function FUNC.clipboard_count() return #clipboard_cues end
function FUNC.clipboard_cue_at(i) local s = clipboard_cues[i]; return s and FUNC.s2c(s) or nil end

-- 選擇性貼上：將 clipboard 中指定欄位套用到目前選中的 cues
-- 規則：N=1 廣播到所有 target；N=M 一對一；其他組合直接 abort
-- selective paste: copy listed fields from clipboard to selected cues (broadcast or 1:1)
function FUNC.do_paste_selective(field_list)
  local N = #clipboard_cues
  local sl = FUNC.sel_list()
  local M = #sl
  if N == 0 then return false, "clipboard empty" end
  if M == 0 then return false, "no target selected" end
  if N ~= 1 and N ~= M then return false, "count mismatch (need N=1 or N=M)" end
  if not field_list or #field_list == 0 then return false, "no fields chosen" end
  FUNC.push_undo()
  for i, ti in ipairs(sl) do
    local src_str = (N == 1) and clipboard_cues[1] or clipboard_cues[i]
    local src = FUNC.s2c(src_str)
    if src then
      local tgt = cues[ti]
      for _, f in ipairs(field_list) do
        if src[f] ~= nil then tgt[f] = src[f] end
      end
    end
  end
  dirty = true
  FUNC.save_cues()
  return true
end

-- GROUP duplicate：複製GROUP+所有子孫，含REAPER track複製、ID重映射、收合狀態 -- full GROUP duplication with children, tracks, collapsed state
function FUNC.dup_group(ci)
  local gc = cues[ci]; if not gc or gc.type ~= "GROUP" then return end
  FUNC.push_undo()
  -- 1. 收集GROUP+所有子孫（遞迴展開巢狀GROUP） -- collect GROUP + all descendants recursively
  local src_sel = {[ci]=true}
  local changed = true
  while changed do
    changed = false
    for j = 1, #cues do
      if src_sel[j] and cues[j].type == "GROUP" then
        for k = 1, #cues do
          if cues[k].group_id == cues[j].id and not src_sel[k] then
            src_sel[k] = true; changed = true
          end
        end
      end
    end
  end
  -- 2. 排序並序列化 -- sort indices and serialize
  local src_list = {}
  for j in pairs(src_sel) do src_list[#src_list+1] = j end
  table.sort(src_list)
  local serialized = {}
  for _, j in ipairs(src_list) do serialized[#serialized+1] = FUNC.c2s(cues[j]) end
  -- 3. 插入點=最後一個子孫的後方 -- insert after last descendant
  local ins = src_list[#src_list]
  -- 4. 反序列化：新ID + 複製PLAY track -- deserialize with new IDs + dup tracks for PLAY cues
  local id_map_loc = {}
  local new_cues = {}
  for _, data in ipairs(serialized) do
    local nc = FUNC.s2c(data)
    local old_id = nc.id
    nc.id = FUNC.nid()
    id_map_loc[old_id] = nc.id
    nc.state = STATE.IDLE; nc.preview_ids = {}; nc.play_t0 = 0
    if nc.type == "PLAY" then
      local src_idx = nc.track_idx
      if nc.track_guid and nc.track_guid ~= "" then
        local resolved = FUNC.guid_to_idx(nc.track_guid)
        if resolved >= 0 then src_idx = resolved end
      end
      if src_idx >= 0 then
        local new_idx, new_guid = FUNC.dup_track(src_idx)
        if new_idx >= 0 then nc.track_idx = new_idx; nc.track_guid = new_guid end
      end
    end
    new_cues[#new_cues+1] = nc
  end
  -- 4.5 頂層GROUP加"(copy)"後綴 -- append "(copy)" to top-level GROUP name
  if #new_cues > 0 then new_cues[1].name = new_cues[1].name .. " (copy)" end
  -- 5. 重映射target和group_id -- remap target_cue_id and group_id
  for _, nc in ipairs(new_cues) do
    if nc.target_cue_id ~= "" and id_map_loc[nc.target_cue_id] then
      nc.target_cue_id = id_map_loc[nc.target_cue_id]
    end
    if nc.group_id and id_map_loc[nc.group_id] then
      nc.group_id = id_map_loc[nc.group_id]
    elseif nc.group_id and not id_map_loc[nc.group_id] then
      nc.group_id = nil  -- 孤兒：父GROUP不在複製範圍內
    end
  end
  -- 6. 插入cues -- insert new cues
  for i, nc in ipairs(new_cues) do table.insert(cues, ins + i, nc) end
  -- 7. 重建所有GROUP的children列表（插入cue後index偏移） -- rebuild ALL groups since indices shifted
  FUNC.rebuild_groups()
  -- 8. 分配cue number -- assign cue numbers
  for i = 1, #new_cues do FUNC.assign_number(ins + i) end
  -- 9. 複製收合狀態 -- copy collapsed state
  for old_id, new_id in pairs(id_map_loc) do
    if collapsed_groups[old_id] then collapsed_groups[new_id] = true end
  end
  -- 10. 選取新cues -- select new cues
  selected = {}
  for i = 1, #new_cues do selected[ins + i] = true end
  next_go = ins + 1; last_click = ins + 1
  FUNC.save_cues()
end

-- Forward declarations for row drag
local row_drag_src, row_drag_tgt

--- Unified post-item interaction: select + reorder drag + right-click menu
function FUNC.cell_post(ci, c, skip_drag)
  if popup.reset_mode or popup.reset_mouse_hold then return end  -- reset mode或滑鼠仍按住時禁用body互動 -- block body interactions in reset mode or while mouse still held
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left()) then
    local sh = ImGui.IsKeyDown(ctx, ImGui.Mod_Shift())
    local cmd = ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl())  -- Cmd+click跳選 -- Cmd+click toggle selection
    if sh and last_click > 0 then
      FUNC.sel_rng(last_click, ci); drag.pending_desel_ci = nil
    elseif cmd then
      if FUNC.is_sel(ci) then selected[ci] = nil else selected[ci] = true end
      drag.pending_desel_ci = nil
      last_click = ci  -- 更新shift anchor但不動next_go -- update shift anchor only
    elseif FUNC.is_sel(ci) and FUNC.sel_cnt() > 1 then
      drag.pending_desel_ci = ci
      next_go = ci; last_click = ci
      FUNC.push_undo()  -- 記錄next_go變更（放在next_go改變後才能拍到新狀態） -- record after next_go changed
    else
      FUNC.sel1(ci); drag.pending_desel_ci = nil
      next_go = ci; last_click = ci
      FUNC.push_undo()  -- 記錄next_go變更 -- record after next_go changed
    end
  end
  -- Track Selection Link: 點cue時選取對應REAPER track -- select REAPER track on cue click
  if prefs.track_sel_link == 1 and ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left()) then
    local sel_tr
    if c.type == "PLAY" or c.type == "MIDI" then
      sel_tr = FUNC.get_tr(c.track_idx)
    elseif c.type == "GROUP" then
      for _, cci in ipairs(c.children or {}) do
        if cci >= 1 and cci <= #cues and (cues[cci].type == "PLAY" or cues[cci].type == "MIDI") then
          sel_tr = FUNC.get_tr(cues[cci].track_idx); break
        end
      end
    end
    if sel_tr then
      local n = reaper.CountTracks(0)
      for i = 0, n - 1 do
        local t = reaper.GetTrack(0, i)
        reaper.SetTrackSelected(t, t == sel_tr)
      end
      reaper.Main_OnCommand(40913,0)--vertical scroll to track
    end
  end
  if not skip_drag then row_drag_src(ci, c) end
  row_drag_tgt(ci)
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right()) then
    if not FUNC.is_sel(ci) then FUNC.sel1(ci); last_click = ci end
    ImGui.OpenPopup(ctx, "rowmenu"..ci)
  end
end

--- Non-editable centered Selectable
function FUNC.cell_sel(ci, c, txt, uid)
  local cw = ImGui.GetContentRegionAvail(ctx)
  local tw,_ = ImGui.CalcTextSize(ctx, txt, 0, 0)
  ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + math.max(0, (cw - tw) * 0.5))
  ImGui.PushStyleColor(ctx, ImGui.Col_Header(), 0)
  ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered(), FUNC.rgba(255,255,255,15))
  ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive(), 0)
  ImGui.Selectable(ctx, txt.."##"..uid..ci, false)
  ImGui.PopStyleColor(ctx, 3)
  FUNC.cell_post(ci, c, false)
end

--- Centered cell: single-click edit + select + drag
function FUNC.draw_click_cell(ci, col, display_txt, edit_init)
  if FUNC.draw_ie(ci, col) then return end
  local c = cues[ci]; if not c then return end
  local cw = ImGui.GetContentRegionAvail(ctx)
  local tw,_ = ImGui.CalcTextSize(ctx, display_txt, 0, 0)
  ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + math.max(0, (cw - tw) * 0.5))
  ImGui.PushStyleColor(ctx, ImGui.Col_Header(), 0)
  ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered(), FUNC.rgba(255,255,255,15))
  ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive(), 0)
  if ImGui.Selectable(ctx, display_txt.."##"..col..ci, false) then
    FUNC.start_ie(ci, col, edit_init or "")
  end
  ImGui.PopStyleColor(ctx, 3)
  FUNC.cell_post(ci, c, false)
end

--- Unified right-click menu per row
function FUNC.draw_row_menu(ci, c)
  if not ImGui.BeginPopup(ctx, "rowmenu"..ci) then return end
  -- Set Color 移到最前面 -- Set Color first
  if ImGui.BeginMenu(ctx, "Set Color") then
    -- "None" 在 group 中設為 0（明確不繼承 group 顏色），group 外設為 -1（clean） -- None顏色邏輯
    if ImGui.Selectable(ctx, "None") then
      local function set_none(q) q.cue_color = (q.group_id or q.type == "GROUP") and 0 or -1 end
      for si in pairs(selected) do if si>=1 and si<=#cues then set_none(cues[si]) end end
      if not FUNC.is_sel(ci) then set_none(c) end
      FUNC.save_cues()
    end
    ImGui.Separator(ctx)
    local bsz = FUNC.sz(22)
    for idx, cc in ipairs(CUE_COLORS) do
      if (idx - 1) % 12 ~= 0 then ImGui.SameLine(ctx, 0, 2) end
      local is_cur = (c.cue_color == cc.val)
      ImGui.PushStyleColor(ctx, ImGui.Col_Button(), FUNC.col2im(cc.val))
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), FUNC.col2im(cc.val, 200))
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), FUNC.col2im(cc.val, 255))
      ImGui.PushStyleColor(ctx, ImGui.Col_Border(), is_cur and C.text or 0)
      ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize(), is_cur and 2 or 0)
      if ImGui.Button(ctx, "##cc"..idx, bsz, bsz) then
        for si in pairs(selected) do if si>=1 and si<=#cues then cues[si].cue_color=cc.val end end
        if not FUNC.is_sel(ci) then c.cue_color=cc.val end
        FUNC.save_cues(); ImGui.CloseCurrentPopup(ctx)
      end
      ImGui.PopStyleVar(ctx, 1)
      ImGui.PopStyleColor(ctx, 4)
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, cc.name) end
    end
    ImGui.EndMenu(ctx)
  end
  ImGui.Separator(ctx)
  if ImGui.Selectable(ctx, "Copy") then FUNC.do_copy() end
  if ImGui.Selectable(ctx, "Cut") then FUNC.do_cut() end
  if FUNC.has_clipboard() then
    if ImGui.Selectable(ctx, "Paste") then FUNC.do_paste(ci) end
  else
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha(), 0.35)
    ImGui.Selectable(ctx, "Paste"); ImGui.PopStyleVar(ctx, 1)
  end
  ImGui.Separator(ctx)
  if FUNC.sel_cnt() >= 2 then
    if ImGui.Selectable(ctx, "Group Selected") then FUNC.group_sel() end
  else
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha(), 0.35)
    ImGui.Selectable(ctx, "Group Selected"); ImGui.PopStyleVar(ctx, 1)
  end
  if c.type == "GROUP" then
    if ImGui.Selectable(ctx, "Ungroup") then FUNC.ungroup_cue(ci) end
  end
  ImGui.Separator(ctx)
  if ImGui.Selectable(ctx, "Duplicate") then
    if c.type == "GROUP" then
      FUNC.dup_group(ci)  -- GROUP完整複製：children+track+collapsed state
    else
      local dc = FUNC.mk_cue(c.type); dc.name=c.name.." (copy)"
      -- PLAY cue複製時也複製REAPER軌道，確保envelope獨立運作 -- duplicate track for independent envelope
      if c.type == "PLAY" and c.track_idx >= 0 then
        local new_idx, new_guid = FUNC.dup_track(c.track_idx)
        if new_idx >= 0 then
          dc.track_idx = new_idx; dc.track_guid = new_guid
        else
          dc.track_idx = c.track_idx; dc.track_guid = c.track_guid  -- fallback：複製失敗用原track
        end
      else
        dc.track_idx=c.track_idx; dc.track_guid=c.track_guid
      end
      dc.target_cue_id=c.target_cue_id; dc.volume=c.volume; dc.fade_time=c.fade_time
      dc.fade_curve=c.fade_curve; dc.fade_curve_amt=c.fade_curve_amt; dc.pre_wait=c.pre_wait; dc.post_wait=c.post_wait
      dc.auto_go=c.auto_go; dc.kill_above=c.kill_above
      dc.trim_start=c.trim_start; dc.trim_end=c.trim_end; dc.notes=c.notes; dc.cue_color=c.cue_color; dc.loop=c.loop; dc.pan=c.pan
      dc.pre_wait_mode=c.pre_wait_mode; dc.post_wait_mode=c.post_wait_mode; dc.fade_wait_mode=c.fade_wait_mode
      dc.pre_bpm_beats=c.pre_bpm_beats; dc.pre_bpm_val=c.pre_bpm_val
      dc.post_bpm_beats=c.post_bpm_beats; dc.post_bpm_val=c.post_bpm_val
      dc.fade_bpm_beats=c.fade_bpm_beats; dc.fade_bpm_val=c.fade_bpm_val
      dc.pre_note_idx=c.pre_note_idx; dc.post_note_idx=c.post_note_idx; dc.fade_note_idx=c.fade_note_idx
      dc.fade_vol_enabled=c.fade_vol_enabled  -- 複製fade enabled狀態 -- copy fade enabled states
      dc.fade_rate_enabled=c.fade_rate_enabled; dc.fade_rate=c.fade_rate
      dc.fade_pitch_enabled=c.fade_pitch_enabled; dc.fade_pitch=c.fade_pitch
      dc.fade_pan_enabled=c.fade_pan_enabled; dc.fade_pan=c.fade_pan
      dc.fade_keep_playing=c.fade_keep_playing  -- 複製keep playing -- copy keep playing
      dc.spacer_align=c.spacer_align; dc.spacer_text_color=c.spacer_text_color  -- 複製spacer屬性 -- copy spacer props
      dc.spacer_border_color=c.spacer_border_color; dc.spacer_bold=c.spacer_bold; dc.spacer_italic=c.spacer_italic; dc.spacer_alpha=c.spacer_alpha
      -- 複製envelope資料（獨立副本）-- deep copy envelope data
      if c.env_enabled then dc.env_enabled = true end
      if c.env_points then
        dc.env_points = {}
        for _, p in ipairs(c.env_points) do dc.env_points[#dc.env_points+1] = {t=p.t, v=p.v, curve=p.curve or 0} end
      end
      if c.pan_env_enabled then dc.pan_env_enabled = true end
      if c.pan_env_points then
        dc.pan_env_points = {}
        for _, p in ipairs(c.pan_env_points) do dc.pan_env_points[#dc.pan_env_points+1] = {t=p.t, v=p.v, curve=p.curve or 0} end
      end
      dc.rate=c.rate; dc.preserve_pitch=c.preserve_pitch; dc.pitch=c.pitch
      -- 複製MIDI欄位 -- copy MIDI fields
      dc.midi_mode=c.midi_mode; dc.midi_device=c.midi_device; dc.midi_channel=c.midi_channel
      dc.midi_note=c.midi_note; dc.midi_velocity=c.midi_velocity; dc.midi_duration=c.midi_duration
      dc.midi_cc=c.midi_cc; dc.midi_cc_val=c.midi_cc_val; dc.midi_program=c.midi_program
      -- 複製markers -- copy markers
      if c.markers and #c.markers > 0 then dc.markers={}; for _,t in ipairs(c.markers) do dc.markers[#dc.markers+1]=t end end
      -- 複製route_trims -- copy route trims
      if c.route_trims and next(c.route_trims) then dc.route_trims={}; for ch,db in pairs(c.route_trims) do dc.route_trims[ch]=db end end
      -- 複製fx_envs (deep copy) -- copy FX envelopes
      if c.fx_envs and #c.fx_envs > 0 then
        dc.fx_envs = {}
        for _, fe in ipairs(c.fx_envs) do
          local nfe = {fx_guid=fe.fx_guid, param_idx=fe.param_idx, fx_name=fe.fx_name, param_name=fe.param_name,
            enabled=fe.enabled, visible=fe.visible, color=fe.color, points={}}
          for _, p in ipairs(fe.points or {}) do nfe.points[#nfe.points+1] = {t=p.t, v=p.v, curve=p.curve or 0} end
          dc.fx_envs[#dc.fx_envs+1] = nfe
        end
      end
      table.insert(cues, ci+1, dc); FUNC.assign_number(ci+1); FUNC.save_cues()
    end
  end  -- duplicate end
  if ImGui.Selectable(ctx, "Delete") then FUNC.remove_selected() end
  if ImGui.Selectable(ctx, "Insert Spacer") then FUNC.add_cue("SPACER", ci) end
  ImGui.EndPopup(ctx)
end

---------------------------------------------------------------------
-- 12. ROW DRAG HELPERS
---------------------------------------------------------------------
row_drag_src = function(ci, c)
  if drag.cue_id then
    if drag.multi then
      if ci < drag.src_ci or ci >= drag.src_ci + drag.block_n then return end
    else
      if c.id ~= drag.cue_id then return end
    end
  end
  if ImGui.BeginDragDropSource(ctx) then
    local sl = FUNC.sel_list()
    if c.type == "GROUP" and #sl == 1 and FUNC.is_sel(ci) and not drag.cue_id then
      -- 選取所有子孫（遞迴，含巢狀GROUP）-- select all descendants recursively
      FUNC.expand_sel_groups()
      sl = FUNC.sel_list()
    end
    if #sl > 1 and FUNC.is_sel(ci) then
      if not drag.cue_id then
        drag.backup = {}
        for i, cc in ipairs(cues) do drag.backup[i] = cc end
        -- 記錄 drag 開始時每個被拖動 cue 的 color + group_id（結算用）
        drag.color_backup = {}
        for _, si in ipairs(sl) do
          local cc = cues[si]
          drag.color_backup[cc.id] = {color = cc.cue_color, gid = cc.group_id}
        end
        local extracted = {}
        for i = #sl, 1, -1 do
          table.insert(extracted, 1, table.remove(cues, sl[i]))
        end
        local ins = math.min(sl[1], #cues + 1)
        for i, cc in ipairs(extracted) do table.insert(cues, ins + i - 1, cc) end
        -- 拖曳不重排number -- drag doesn't renumber
        drag.cue_id = cues[ins].id
        drag.src_ci = ins
        drag.multi = true
        drag.block_n = #extracted
        drag.click_off = ci - ins
        selected = {}
        for i = ins, ins + drag.block_n - 1 do selected[i] = true end
        FUNC.push_undo(); undo.paused = true
      end
      ImGui.SetDragDropPayload(ctx, "CUE_REORDER", "LIVE_MULTI")
      ImGui.Text(ctx, string.format("Move %d cues", drag.block_n))
    else
      if not drag.cue_id then
        drag.cue_id = c.id
        drag.src_ci = ci
        drag.multi = false
        drag.block_n = 1
        drag.click_off = 0
        drag.backup = {}
        for i, cc in ipairs(cues) do drag.backup[i] = cc end
        -- 記錄 drag 開始時的 color + group_id（結算用）
        drag.color_backup = {[c.id] = {color = c.cue_color, gid = c.group_id}}
        FUNC.push_undo(); undo.paused = true
      end
      ImGui.SetDragDropPayload(ctx, "CUE_REORDER", "LIVE:"..drag.cue_id)
      local _, dc = FUNC.find_id(drag.cue_id)
      local dtxt = dc and ("Move Q."..dc.cue_number.." "..dc.name) or "Move cue"
      ImGui.Text(ctx, dtxt)
    end
    ImGui.EndDragDropSource(ctx)
  end
end

row_drag_tgt = function(ci)
  if ImGui.BeginDragDropTarget(ctx) then
    ImGui.PushStyleColor(ctx, ImGui.Col_DragDropTarget(), 0)
    local ok, pl = ImGui.AcceptDragDropPayload(ctx, "CUE_REORDER", ImGui.DragDropFlags_AcceptNoDrawDefaultRect())
    ImGui.PopStyleColor(ctx, 1)
    if ok and pl ~= "" then
      if pl:match("^LIVE") then
        FUNC.settle_drag_colors()  -- 拖到 row 上放開時也要結算顏色 -- 顏色結算呼叫點
        undo.paused = false; undo.last_snap = FUNC.snap_cues()
        FUNC.save_cues()
        if drag.multi and drag.src_ci then
          selected = {}
          for i = drag.src_ci, drag.src_ci + drag.block_n - 1 do selected[i] = true end
        else
          FUNC.sel1(drag.src_ci or ci)
        end
        drag.cue_id = nil; drag.src_ci = nil; drag.backup = nil; drag._depth_warned = nil
        drag.multi = false; drag.block_n = 1
      end
    end
    ImGui.EndDragDropTarget(ctx)
  end
end

-- Target column drag: source PLAY cue from target col only
function FUNC.target_drag_src(ci, c)
  if c.type~="PLAY" and c.type~="GROUP" then return end
  if ImGui.BeginDragDropSource(ctx) then
    ImGui.SetDragDropPayload(ctx, "CUE_TARGET", c.id)
    local prefix = c.type=="GROUP" and "Link G." or "Link Q."
    ImGui.Text(ctx, prefix..c.cue_number.." "..c.name)
    ImGui.EndDragDropSource(ctx)
  end
end

-- Target column drag: accept PLAY cue link + highlight on hover
function FUNC.target_drag_accept(ci, c)
  if c.type=="PLAY" or c.type=="GROUP" then return end
  if ImGui.BeginDragDropTarget(ctx) then
    local ix1, iy1 = ImGui.GetItemRectMin(ctx)
    local ix2, iy2 = ImGui.GetItemRectMax(ctx)
    ImGui.DrawList_AddRect(ImGui.GetWindowDrawList(ctx), ix1, iy1, ix2, iy2, FUNC.dim_c(C.accent), 0, 0, FUNC.sz(2))
    local ok, pl = ImGui.AcceptDragDropPayload(ctx, "CUE_TARGET", "")
    if ok and pl ~= "" then c.target_cue_id=pl; FUNC.save_cues() end
    ImGui.EndDragDropTarget(ctx)
  end
end
