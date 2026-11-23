-- ==========================================================================
-- io.lua — Save/Load Shows
-- ==========================================================================

-- 取得當前project路徑作為隔離key -- project path as isolation key
local function proj_prefix()
  local _, path = reaper.EnumProjects(-1)
  if path == "" then return "::Untitled" end
  return "::" .. path
end

function FUNC.get_show_titles()
  local idx = reaper.GetExtState(EXT.SHOWS, "__index__" .. proj_prefix())
  local titles = {}
  if idx ~= "" then for t in idx:gmatch("[^\t\n]+") do titles[#titles+1]=t end end  -- \t(新)+\n(舊)雙相容
  return titles
end

function FUNC.save_show(title)
  if title == "" then return end
  local lines = {"@@master="..tostring(prefs.master_vol)}
  -- 儲存收合狀態 -- save collapsed state
  local cg_ids = {}; for id, v in pairs(collapsed_groups) do if v then cg_ids[#cg_ids+1] = id end end
  if #cg_ids > 0 then lines[#lines+1] = "@@collapsed="..table.concat(cg_ids, ",") end
  -- 儲存專案備註 -- save project notes (escape newlines)
  if project_notes and project_notes ~= "" then
    lines[#lines+1] = "@@notes="..project_notes:gsub("\n","\\n"):gsub("\t","\\t")
  end
  for _, c in ipairs(cues) do lines[#lines+1] = FUNC.c2s(c) end
  reaper.SetExtState(EXT.SHOWS, title, table.concat(lines, "\t"), true)  -- \t取代\n避免INI換行截斷
  local titles = FUNC.get_show_titles()
  local found = false
  for _, t in ipairs(titles) do if t == title then found = true; break end end
  if not found then titles[#titles+1] = title end
  reaper.SetExtState(EXT.SHOWS, "__index__" .. proj_prefix(), table.concat(titles, "\t"), true)  -- \t取代\n
  show_name = title  -- 標題列：記住 show 名稱
  dirty = false      -- 標題列：剛存檔，清除米字號
  reaper.SetExtState(EXT.PREFS, "LastShowName", title, true)  -- 記住最後編輯的show -- save last show globally
end

function FUNC.load_show(title)
  local data = reaper.GetExtState(EXT.SHOWS, title)
  if data == "" then return false end
  FUNC.hard_stop_all()  -- 載入前先全部停止並還原軌道 -- stop everything and give tracks back before loading
  cues = {}; collapsed_groups = {}; project_notes = ""
  for line in data:gmatch("[^\t\n]+") do  -- \t(新)+\n(舊)雙相容
    if line:match("^@@master=") then
      prefs.master_vol = tonumber(line:match("@@master=(.+)")) or 0
    elseif line:match("^@@collapsed=") then
      -- 載入收合狀態 -- restore collapsed state
      local cs = line:match("@@collapsed=(.+)")
      if cs then for id in cs:gmatch("[^,]+") do collapsed_groups[id] = true end end
    elseif line:match("^@@notes=") then
      -- 載入專案備註 -- restore project notes (unescape newlines)
      local ns = line:match("@@notes=(.+)")
      if ns then project_notes = ns:gsub("\\n","\n"):gsub("\\t","\t") end
    else
      local ok,c = pcall(FUNC.s2c, line); if ok and c then cues[#cues+1] = c end  -- pcall防止舊格式crash -- pcall for backward compat
    end
  end
  next_go = (#cues > 0) and 1 or 0
  selected = {}; if next_go > 0 then FUNC.sel1(next_go) end
  -- Restore group color index
  FUNC.set_grp_cc_idx(0)
  for _,c in ipairs(cues) do
    if c.type=="GROUP" and c.cue_color and c.cue_color>0 then
      for idx,cc in ipairs(CUE_COLORS) do
        if cc.val==c.cue_color and idx>FUNC.get_grp_cc_idx() then FUNC.set_grp_cc_idx(idx) end
      end
    end
  end
  FUNC.save_cues()
  show_name = title  -- 標題列：載入的 show 名稱
  dirty = false      -- 標題列：剛載入，清除米字號
  reaper.SetExtState(EXT.PREFS, "LastShowName", title, true)  -- 記住最後載入的show -- save last loaded show globally
  return true
end

-- 切換project時自動備份到ExtState，key=timestamp -- auto-save with timestamp on project switch
function FUNC.auto_save_timestamp()
  if #cues == 0 then return end  -- 沒有cue就不備份
  local proj_name = reaper.GetProjectName(0)
  if proj_name ~= "" then proj_name = proj_name:gsub("%.[^%.]+$", "") else proj_name = "Untitled" end
  local ts = os.date("%Y-%m-%d_%H:%M:%S")
  local key = "[auto] " .. proj_name .. " " .. ts
  local lines = {"@@master="..tostring(prefs.master_vol)}
  if project_notes and project_notes ~= "" then
    lines[#lines+1] = "@@notes="..project_notes:gsub("\n","\\n"):gsub("\t","\\t")
  end
  for _, c in ipairs(cues) do lines[#lines+1] = FUNC.c2s(c) end
  reaper.SetExtState(EXT.SHOWS, key, table.concat(lines, "\t"), true)  -- \t取代\n
  -- 加入index但限制auto backup數量(最多保留10筆) -- limit auto backups to 10
  local titles = FUNC.get_show_titles()
  titles[#titles+1] = key
  local autos = {}
  for _, t in ipairs(titles) do if t:match("^%[auto%]") then autos[#autos+1] = t end end
  table.sort(autos)
  while #autos > 10 do
    local old = table.remove(autos, 1)
    reaper.DeleteExtState(EXT.SHOWS, old, true)
    for i = #titles, 1, -1 do if titles[i] == old then table.remove(titles, i) end end
  end
  reaper.SetExtState(EXT.SHOWS, "__index__" .. proj_prefix(), table.concat(titles, "\t"), true)  -- \t取代\n
end

function FUNC.delete_show(title)
  reaper.DeleteExtState(EXT.SHOWS, title, true)
  local titles = FUNC.get_show_titles()
  local new = {}
  for _, t in ipairs(titles) do if t ~= title then new[#new+1] = t end end
  reaper.SetExtState(EXT.SHOWS, "__index__" .. proj_prefix(), table.concat(new, "\t"), true)  -- \t取代\n
end
