-- @description Theme Layout Modifier (TCP) - visual editor for third-party theme layouts (rtconfig.txt / WALTER)
-- @author Lyx
-- @version 0.2
-- @about
--   Lists the themes in a ColorThemes folder, unpacks zipped themes, previews every TCP layout
--   with the theme's own images, and lets you move / resize / hide / link elements.
--   Nothing touches REAPER until you press Apply (writes rtconfig.txt) and Refresh (reloads the theme).

if not reaper.ImGui_GetBuiltinPath then
  reaper.MB("This script needs ReaImGui (install it from ReaPack).", "Theme Layout Modifier", 0)
  return
end
local SCRIPT_DIR = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
package.path = SCRIPT_DIR .. "?.lua;" .. SCRIPT_DIR .. "../?.lua;" .. reaper.ImGui_GetBuiltinPath() .. "/?.lua;" .. package.path
local ImGui = require "imgui" "0.10"
local W = require "tlm_walter"
local G = require "_lib._Lyx_GUI" -- Lyx global theme (colours + rounding when "Inherit" is on)
local THEME_KEY = "ThemeLayoutModifier"
G.load_theme(THEME_KEY)

local TITLE = "Theme Layout Modifier"
local EXT = "Lyx_ThemeLayoutModifier"
local ctx = ImGui.CreateContext(TITLE)
-- no keyboard navigation: the arrow keys nudge elements, they must not move the widget focus
ImGui.SetConfigVar(ctx, ImGui.ConfigVar_Flags, math.floor(ImGui.GetConfigVar(ctx, ImGui.ConfigVar_Flags)) & ~ImGui.ConfigFlags_NavEnableKeyboard)
local FONT = ImGui.CreateFont("sans-serif")
ImGui.Attach(ctx, FONT)

----------------------------------------------------------------------------------------------------
-- Look (user-adjustable, saved in ExtState)
----------------------------------------------------------------------------------------------------
local DEFAULT_STYLE = {
  accent = 0xCA8B26FF, bg = 0x17263EFF, panel = 0x1E2024FF, frame = 0x272A30FF,
  text = 0xE0E2E6FF, border = 0x282F3AFF, font = 13,
}
local STYLE_KEYS = {
  { "accent", "Accent" }, { "bg", "Background" }, { "panel", "Panels" }, { "frame", "Controls" },
  { "text", "Text" }, { "border", "Borders" },
}
local ST = {}
local C_ = { danger = 0xE2585DFF, link = 0x5AB4F0FF, hover = 0xFFFFFF60 }

local function clamp8(x) return math.max(0, math.min(255, math.floor(x + 0.5))) end
local function chn(c, s) return (c >> s) & 255 end
local function with_alpha(c, a) return (c & 0xFFFFFF00) | clamp8(a) end
local function mix(c1, c2, t)
  local function m(s) return clamp8(chn(c1, s) + (chn(c2, s) - chn(c1, s)) * t) end
  return (m(24) << 24) | (m(16) << 16) | (m(8) << 8) | chn(c1, 0)
end

local function derive_style()
  local s, rgba = ST, G.col
  if G.inherited then -- global theme replaces the user colours (text size stays ours)
    local c = G.theme.colors
    s = { bg = rgba(c.bg), panel = rgba(c.bg2), frame = rgba(G.theme.frame.color), text = rgba(c.text),
          accent = rgba(c.accent), border = rgba(G.mix(c.bg, c.base, 0.65)) }
  end
  C_.bg, C_.child = with_alpha(s.bg, 255), with_alpha(s.panel, 255)
  C_.frame = s.frame
  C_.frame_hi, C_.frame_act = mix(s.frame, 0xFFFFFFFF, 0.08), mix(s.frame, 0xFFFFFFFF, 0.16)
  C_.border, C_.text = s.border, s.text
  C_.dim = mix(s.text, s.bg, 0.45)
  C_.accent, C_.sel = s.accent, s.accent
  C_.accent_hi, C_.accent_lo = mix(s.accent, 0xFFFFFFFF, 0.18), mix(s.accent, 0x000000FF, 0.15)
  C_.accent_dim = with_alpha(s.accent, 0x40)
  C_.accent_txt = with_alpha(s.bg, 255)
  C_.canvas = with_alpha(mix(s.bg, 0x000000FF, 0.3), 255)
  local bt = G.inherited and rgba(G.theme.button.color) or s.frame
  C_.button, C_.button_hi, C_.button_act = bt, mix(bt, 0xFFFFFFFF, 0.08), mix(bt, 0xFFFFFFFF, 0.16)
  C_.title = G.inherited and rgba(G.theme.colors.title) or C_.text
  C_.subtitle = G.inherited and rgba(G.theme.colors.subtitle) or C_.dim
end

local function load_style()
  for k, v in pairs(DEFAULT_STYLE) do ST[k] = v end
  for k, v in reaper.GetExtState(EXT, "style"):gmatch("(%w+)=([%w%.]+)") do
    if DEFAULT_STYLE[k] then
      local n = k == "font" and tonumber(v) or tonumber(v, 16)
      if n then ST[k] = n end
    end
  end
  derive_style()
end

local function save_style()
  local p = {}
  for _, kv in ipairs(STYLE_KEYS) do p[#p + 1] = ("%s=%08X"):format(kv[1], ST[kv[1]]) end
  p[#p + 1] = ("font=%d"):format(ST.font)
  reaper.SetExtState(EXT, "style", table.concat(p, " "), true)
end

load_style()

local function push_theme()
  local c = {
    { ImGui.Col_WindowBg, C_.bg }, { ImGui.Col_ChildBg, C_.child }, { ImGui.Col_PopupBg, with_alpha(ST.panel, 255) },
    { ImGui.Col_FrameBg, C_.frame }, { ImGui.Col_FrameBgHovered, C_.frame_hi }, { ImGui.Col_FrameBgActive, C_.frame_act },
    { ImGui.Col_Button, C_.button }, { ImGui.Col_ButtonHovered, C_.button_hi }, { ImGui.Col_ButtonActive, C_.button_act },
    { ImGui.Col_Header, C_.accent_dim }, { ImGui.Col_HeaderHovered, C_.frame_hi }, { ImGui.Col_HeaderActive, C_.accent_dim },
    { ImGui.Col_Border, C_.border }, { ImGui.Col_Text, C_.text }, { ImGui.Col_TextDisabled, C_.dim },
    { ImGui.Col_SliderGrab, C_.accent }, { ImGui.Col_SliderGrabActive, C_.accent }, { ImGui.Col_CheckMark, C_.accent },
    { ImGui.Col_TitleBg, C_.bg }, { ImGui.Col_TitleBgActive, C_.bg }, { ImGui.Col_Separator, C_.border },
    { ImGui.Col_SeparatorHovered, C_.accent }, { ImGui.Col_SeparatorActive, C_.accent },
    { ImGui.Col_ScrollbarBg, 0x00000000 }, { ImGui.Col_ScrollbarGrab, C_.frame_hi },
    { ImGui.Col_ScrollbarGrabHovered, C_.frame_act }, { ImGui.Col_ScrollbarGrabActive, C_.accent },
    { ImGui.Col_ResizeGrip, 0x00000000 }, { ImGui.Col_ResizeGripHovered, C_.accent_dim }, { ImGui.Col_ResizeGripActive, C_.accent },
    { ImGui.Col_ModalWindowDimBg, 0x0000008C }, { ImGui.Col_TextSelectedBg, C_.accent_dim },
  }
  for _, p in ipairs(c) do ImGui.PushStyleColor(ctx, p[1], p[2]) end
  local rw, rf = 8, 5
  if G.inherited then rw, rf = G.theme.rounding.window, G.theme.rounding.frame end
  local v = {
    { ImGui.StyleVar_WindowRounding, rw }, { ImGui.StyleVar_FrameRounding, rf }, { ImGui.StyleVar_ChildRounding, rw },
    { ImGui.StyleVar_PopupRounding, rw }, { ImGui.StyleVar_GrabRounding, rf * 0.8 }, { ImGui.StyleVar_ScrollbarRounding, 6 },
    { ImGui.StyleVar_FrameBorderSize, G.inherited and G.theme.frame.border or 0 },
    { ImGui.StyleVar_ScrollbarSize, 10 }, { ImGui.StyleVar_GrabMinSize, 10 },
    { ImGui.StyleVar_FramePadding, 8, 5 }, { ImGui.StyleVar_ItemSpacing, 8, 7 }, { ImGui.StyleVar_ItemInnerSpacing, 6, 4 },
    { ImGui.StyleVar_WindowPadding, 14, 12 }, { ImGui.StyleVar_SeparatorTextBorderSize, 1 },
    { ImGui.StyleVar_SeparatorTextPadding, 0, 6 },
  }
  for _, p in ipairs(v) do ImGui.PushStyleVar(ctx, p[1], p[2], p[3]) end
  return #c, #v
end

local FRAME_PAD = 8

local function text_w(s) return (ImGui.CalcTextSize(ctx, s)) end
local function btn_w(label) return text_w(label) + FRAME_PAD * 2 end

-- rounded "pill" label drawn at x,y; returns its width
local function pill(dl, x, y, text, fg, bg)
  local fs = ImGui.GetFontSize(ctx) * 0.85
  local tw = text_w(text) * 0.85
  local h = fs + 5
  ImGui.DrawList_AddRectFilled(dl, x, y, x + tw + 14, y + h, bg or with_alpha(fg, 0x30), h / 2)
  ImGui.DrawList_AddTextEx(dl, FONT, fs, x + 7, y + 2.5, fg, text)
  return tw + 14, h
end

-- small-caps section heading with a hairline
local function heading(text)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, C_.subtitle)
  ImGui.SeparatorText(ctx, text:upper())
  ImGui.PopStyleColor(ctx)
end

local function danger_button(label, w)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, with_alpha(C_.danger, 0x30))
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, with_alpha(C_.danger, 0x60))
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, C_.danger)
  local r = ImGui.Button(ctx, label, w or 0, 0)
  ImGui.PopStyleColor(ctx, 3)
  return r
end

-- right-align a group `total_w` wide after the last item; wraps to a new line if it doesn't fit
local function right_align(total_w)
  ImGui.SameLine(ctx)
  local aw = ImGui.GetContentRegionAvail(ctx)
  if aw < total_w then
    ImGui.NewLine(ctx)
    aw = ImGui.GetContentRegionAvail(ctx)
  end
  if aw > total_w then ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + aw - total_w) end
end

-- flow layout: keep the next item (w px) on this line if it fits, otherwise wrap (to x = indent)
local function flow(w, spacing, indent)
  ImGui.SameLine(ctx, 0, spacing or 8)
  if ImGui.GetContentRegionAvail(ctx) < w then
    ImGui.NewLine(ctx)
    if indent then ImGui.SetCursorPosX(ctx, indent) end
  end
end

local function check_w(label) return ImGui.GetFrameHeight(ctx) + 6 + text_w(label) end

-- shorten txt with "..." until it fits w px
local function fit(txt, w)
  if text_w(txt) <= w then return txt end
  while #txt > 2 and text_w(txt .. "...") > w do txt = txt:sub(1, -2) end
  return txt .. "..."
end

local status_visible = true -- the edit page shows status inside the canvas instead
local function status_h() return status_visible and math.floor(ST.font + 14) or 0 end

-- one undo step per edited field (snapshot before the first change of an interaction)
local snap_item, snapshot_fn
local function snap_once(id, changed_now)
  if changed_now and snap_item ~= id then snapshot_fn(); snap_item = id end
  if snap_item == id and ImGui.IsItemDeactivated(ctx) then snap_item = nil end
end

local function accent_button(label, w)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, C_.accent)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C_.accent_hi)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, C_.accent_lo)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, C_.accent_txt)
  local r = ImGui.Button(ctx, label, w or 0, 0)
  ImGui.PopStyleColor(ctx, 4)
  return r
end

local function tip(text)
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then ImGui.SetTooltip(ctx, text) end
end

----------------------------------------------------------------------------------------------------
-- Files / shell (macOS)
----------------------------------------------------------------------------------------------------
local function read_file(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

local function write_file(p, s)
  local f, err = io.open(p, "wb")
  if not f then return false, err end
  f:write(s)
  f:close()
  return true
end

local function exists(p) return os.rename(p, p) and true or false end
local function q(s) return "'" .. (s:gsub("'", "'\\''")) .. "'" end

local function split_lines(s)
  s = s:gsub("\r\n", "\n"):gsub("\r", "\n")
  local t = {}
  for l in (s .. "\n"):gmatch("(.-)\n") do t[#t + 1] = l end
  if t[#t] == "" then t[#t] = nil end
  return t
end

local function zip_list(path)
  local t = {}
  local p = io.popen("/usr/bin/unzip -Z1 " .. q(path) .. " 2>/dev/null")
  if p then
    for l in p:lines() do t[#t + 1] = l end
    p:close()
  end
  return t
end

local function set_ui_img(content, val)
  local v = val:gsub("%%", "%%%%")
  if content:find("[\r\n]ui_img=") or content:find("^ui_img=") then
    content = content:gsub("^ui_img=[^\r\n]*", "ui_img=" .. v):gsub("([\r\n])ui_img=[^\r\n]*", "%1ui_img=" .. v)
  else
    content = content:gsub("(%[color theme%][^\r\n]*\r?\n)", "%1ui_img=" .. v .. "\n", 1)
  end
  return content
end

local function deep(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = deep(v) end
  return c
end

----------------------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------------------
local PAD = 44 -- canvas margin around the panel (room for rulers)

local S = {
  dir = reaper.GetExtState(EXT, "dir"),
  themes = {}, theme_idx = nil,
  page = "main", sel_layout = nil,
  popup = nil, popup_data = {},
  status = "", status_err = false,
  sel_elem = nil, drag = nil,
  undo = {}, redo = {},
  backup = reaper.GetExtState(EXT, "backup") == "1",
  sec = reaper.GetExtState(EXT, "sec"),
  show_style = false,
  hints = reaper.GetExtState(EXT, "hints") ~= "0", -- mouse/keyboard hints in the canvas corner
  snap = reaper.GetExtState(EXT, "snap") ~= "0", -- dragged edges snap to nearby element / panel edges
  guides = reaper.GetExtState(EXT, "guides") ~= "0", -- guide lines while dragging
  cat_closed = {}, -- element list categories the user collapsed (ExtState "cat_closed")
}
for k in reaper.GetExtState(EXT, "cat_closed"):gmatch("[^,]+") do S.cat_closed[k] = true end
if S.dir == "" then S.dir = reaper.GetResourcePath() .. "/ColorThemes" end
if S.sec == "" then S.sec = "tcp" end

local P = { W = 500, H = 80, zoom = tonumber(reaper.GetExtState(EXT, "zoom")) or 2, recarm = false,
  selected = false, folder = false, panmode = 3, params = {}, org_x = PAD, org_y = PAD }

local T -- the loaded theme

local function status(msg, err)
  S.status, S.status_err = msg, err and true or false
  S.status_ok = not err and (msg:find("^Saved") or msg:find("^Reloaded") or msg:find("^Loaded")) and true or false
end

----------------------------------------------------------------------------------------------------
-- Theme list / unpack
----------------------------------------------------------------------------------------------------
local function read_ui_img(file)
  local s = read_file(file) or ""
  return s:match("[\r\n]ui_img=([^\r\n]*)") or s:match("^ui_img=([^\r\n]*)")
end

local function scan_themes()
  local dir = S.dir
  reaper.EnumerateFiles(dir, -1)
  local list, zips, present = {}, {}, {}
  local i = 0
  while true do
    local f = reaper.EnumerateFiles(dir, i)
    if not f then break end
    i = i + 1
    local low = f:lower()
    if low:match("%.reapertheme$") then
      present[f] = true
      local ui = read_ui_img(dir .. "/" .. f)
      local res = ui and ui ~= "" and (dir .. "/" .. ui) or nil
      if res and exists(res .. "/rtconfig.txt") then
        list[#list + 1] = { kind = "theme", name = f:gsub("%.[^.]+$", ""), file = dir .. "/" .. f, res = res }
      end
    elseif low:match("%.reaperthemezip$") then
      zips[#zips + 1] = f
    end
  end
  for _, z in ipairs(zips) do
    local inner = zip_list(dir .. "/" .. z)
    local unpacked = false
    for _, e in ipairs(inner) do
      if e:lower():match("^[^/]+%.reapertheme$") and present[e] then unpacked = true end
    end
    if not unpacked then
      list[#list + 1] = { kind = "zip", name = z:gsub("%.[^.]+$", ""), file = dir .. "/" .. z, inner = inner }
    end
  end
  table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
  S.themes = list
end

-- returns path of the (first) .ReaperTheme, or nil + error
local function unpack_zip(t, newname)
  local dir = S.dir
  local resdir
  for _, e in ipairs(t.inner) do
    local d = not e:find("__MACOSX", 1, true) and e:match("^(.*)/rtconfig%.txt$")
    if d and (not resdir or #d < #resdir) then resdir = d end
  end
  if not resdir then return nil, "This zip has no rtconfig.txt, so there is no layout code to edit." end
  local tfiles = {}
  for _, e in ipairs(t.inner) do if e:lower():match("^[^/]+%.reapertheme$") then tfiles[#tfiles + 1] = e end end
  if #tfiles == 0 then return nil, "This zip has no .ReaperTheme file." end

  if not newname then
    -- unpack in place, never overwriting existing files
    os.execute("/usr/bin/unzip -n -qq " .. q(t.file) .. " -x '__MACOSX/*' -d " .. q(dir))
    for _, tf in ipairs(tfiles) do
      local p = dir .. "/" .. tf
      local s = read_file(p)
      if s then
        local ui = read_ui_img(p)
        if not (ui and exists(dir .. "/" .. ui .. "/rtconfig.txt")) then write_file(p, set_ui_img(s, resdir)) end
      end
    end
    return dir .. "/" .. tfiles[1]
  end

  if newname:find("[/:]") then return nil, "The name can't contain / or :" end
  if exists(dir .. "/" .. newname) or exists(dir .. "/" .. newname .. ".ReaperTheme") then
    return nil, "\"" .. newname .. "\" already exists in this folder."
  end
  local tmp = dir .. "/.tlm_unpack_tmp"
  os.execute("rm -rf " .. q(tmp))
  os.execute("/usr/bin/unzip -qq " .. q(t.file) .. " -x '__MACOSX/*' -d " .. q(tmp))
  local ok = os.rename(tmp .. "/" .. resdir, dir .. "/" .. newname)
  local first
  if ok then
    for k, tf in ipairs(tfiles) do
      local s = read_file(tmp .. "/" .. tf)
      if s then
        local base = #tfiles == 1 and newname or (newname .. " - " .. tf:gsub("%.[^.]+$", ""))
        write_file(dir .. "/" .. base .. ".ReaperTheme", set_ui_img(s, newname))
        if k == 1 then first = dir .. "/" .. base .. ".ReaperTheme" end
      end
    end
  end
  os.execute("rm -rf " .. q(tmp))
  if not first then return nil, "Unpacking failed." end
  return first
end

----------------------------------------------------------------------------------------------------
-- Loaded theme
----------------------------------------------------------------------------------------------------
local function reaper_version() return tonumber(reaper.GetAppVersion():match("[%d%.]+")) or 7 end

local function make_ctx()
  local ver = reaper_version()
  local os_type = 1
  if ver >= 7.71 then os_type = T.C.cfg.want_os_type and 3 or 0 elseif ver >= 7.70 then os_type = 3 end
  local c = {
    w = P.W, h = P.H, folderstate = P.folder and 1 or 0, folderdepth = 0, maxfolderdepth = 0,
    recarm = P.recarm and 1 or 0, tcp_iconsize = 0, mcp_iconsize = 0, mcp_maxfolderdepth = 0, mcp_wantextmix = 0,
    tracknch = 2, trackpanmode = P.panmode, tcp_fxparms = 0, tcp_fxembed = 0, mcp_fxembed = 0,
    reaper_version = ver, os_type = os_type, trackcolor_valid = 0, trackcolor_r = 0, trackcolor_g = 0, trackcolor_b = 0,
    track_selected = P.selected and 1 or 0, trackidx = 1, ntracks = 8, mixer_visible = 1,
    tcp_sends_enabled = 0, tcp_fxlist_enabled = 0, send_cnt = 0, fx_parm_cnt = 0, fx_cnt = 0, recfx_cnt = 0,
    trackfixedlanes = 0, trackpinned = 0, tcp_hidden_overridden = 0,
  }
  for name, p in pairs(T.C.params) do c[name] = P.params[name] or p.def end
  return c
end

local function evaluate(force)
  if T and (T.dirty_eval or force) then
    T.R = W.run(T.C, make_ctx(), W.compile_overrides(T.edits))
    T.dirty_eval = false
  end
end

local function changed(structural)
  T.dirty = true
  T.dirty_eval = true
  if structural then T.C = W.compile(T.plain) end
end

-- undo: snapshot (plain lines + edits) before every change; buttons only, no shortcuts
local function snapshot()
  S.undo[#S.undo + 1] = { plain = T.plain, edits = deep(T.edits), sel = S.sel_layout }
  if #S.undo > 200 then table.remove(S.undo, 1) end
  S.redo = {}
end

snapshot_fn = snapshot

local function undo_redo(from, to)
  local s = table.remove(from)
  if not s then return end
  to[#to + 1] = { plain = T.plain, edits = deep(T.edits), sel = S.sel_layout }
  T.plain, T.edits, S.sel_layout = s.plain, s.edits, s.sel
  S.drag = nil
  changed(true)
end

local function LS(name) return name == "" and T.R.G or T.R.layouts[name] end

local function base_size(L)
  local s = L and L.vars[S.sec .. ".size"]
  if s and s[1] > 0 and s[2] > 0 then return s[1], s[2] end
  return P.W, P.H
end

local function erect(L, e)
  if not L then return nil end
  local bw, bh = base_size(L)
  return W.rect(L.vars[e], bw, bh, P.W, P.H)
end

local function layout_list()
  local t = {}
  for k in pairs(T.R.G.vars) do
    if W.sec_of(k) == S.sec and k ~= S.sec .. ".size" then t[1] = ""; break end
  end
  for _, n in ipairs(T.C.layouts[S.sec] or {}) do t[#t + 1] = n end
  return t
end

local function layout_label(name) return name == "" and "Default (global)" or name end

local function imgdir_of(name)
  local b = name ~= "" and T.C.last_block[S.sec] and T.C.last_block[S.sec][name]
  return b and b.imgdir or nil
end

local function read_theme_colors(file)
  local s = read_file(file) or ""
  local function col(key)
    local v = tonumber(s:match("[\r\n]" .. key .. "=(%-?%d+)"))
    if not v or v < 0 then return nil end
    return ((v & 255) << 24) | (((v >> 8) & 255) << 16) | (((v >> 16) & 255) << 8) | 255
  end
  return { text = col("col_tcp_text") or 0xD0D0D0FF, textsel = col("col_tcp_textsel") }
end

local function disk_layouts()
  local t = {}
  for _, b in ipairs(T.C.blocks) do t[b.name] = true end
  return t
end

local IMG -- image cache for the loaded theme

local function reset_view()
  P.org_x, P.org_y = PAD, PAD
  S.center_view = true
  local key = S.sec .. ".size"
  local L = T.R.G
  local first = (T.C.layouts[S.sec] or {})[1]
  if not (L.vars[key] and L.vars[key][1] > 0) and first then L = T.R.layouts[first] end
  local s0 = L and L.vars[key]
  if s0 and s0[1] > 0 then P.W, P.H = math.floor(s0[1]), math.floor(s0[2])
  else P.W, P.H = S.sec:find("mcp") and 80 or 400, S.sec:find("mcp") and 300 or 80 end
  T.dirty_eval = true
end

-- preview size / position is kept per section (TCP is wide, MCP is tall)
local function switch_section(id, keep_layout)
  if id == S.sec then return end
  P.views = P.views or {}
  P.views[S.sec] = { P.W, P.H, P.org_x, P.org_y }
  S.sec = id
  reaper.SetExtState(EXT, "sec", id, true)
  if id:find("^master") then S.master_sub = id end
  local keep = keep_layout and S.sel_layout
  if keep and keep ~= "" then
    local ok = false
    for _, n in ipairs(T.C.layouts[id] or {}) do if n == keep then ok = true end end
    if not ok then keep = nil end
  end
  if not keep_layout or keep == nil then S.page = "main" end
  S.sel_elem, S.drag, S.sel_layout = nil, nil, keep
  local v = P.views[id]
  if v then P.W, P.H, P.org_x, P.org_y = v[1], v[2], v[3], v[4]; T.dirty_eval = true else reset_view() end
end

local function load_theme(t)
  local path = t.res .. "/rtconfig.txt"
  local s = read_file(path)
  if not s then status("Can't read " .. path, true) return end
  local lines = split_lines(s)
  local plain, edits = W.extract_managed(lines)
  T = { meta = t, path = path, eol = s:find("\r\n") and "\r\n" or "\n", plain = plain, edits = edits }
  T.C = W.compile(plain)
  T.on_disk = disk_layouts()
  T.colors = read_theme_colors(t.file)
  local gs = T.C.cfg.global_scale
  T.img_scale = gs and tonumber(gs[1]) or 1
  IMG = {}
  P.params = {}
  S.undo, S.redo = {}, {}
  -- if this theme is active, start from its current parameter values
  if reaper.GetLastColorThemeFile() == t.file then
    for i = 0, 1000 do
      local name, _, value = reaper.ThemeLayout_GetParameter(i)
      if not name or name == "" then break end
      if T.C.params[name] then P.params[name] = value end
    end
  end
  P.views = {}
  evaluate(true)
  reset_view()
  evaluate(true)
  T.dirty = false
  S.page = "main"
  S.sel_layout = layout_list()[1]
  S.sel_elem = nil
  reaper.SetExtState(EXT, "last_theme", t.file, true)
  local n = 0
  for _, recs in pairs(edits) do for _ in pairs(recs) do n = n + 1 end end
  status(("Loaded %s  ·  %d TCP / %d MCP layouts%s"):format(t.name, #(T.C.layouts.tcp or {}), #(T.C.layouts.mcp or {}),
    n > 0 and ("  ·  " .. n .. " saved edits found") or ""))
end

----------------------------------------------------------------------------------------------------
-- Images (theme PNGs, pink/yellow resize borders)
----------------------------------------------------------------------------------------------------
local function is_mark(v) return v == 0xFF00FFFF or v == 0xFFFF00FF end

-- PNG width/height from the file header (no decoding)
local function png_size(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local head = f:read(24)
  f:close()
  if not head or #head < 24 or head:sub(2, 4) ~= "PNG" then return nil end
  return string.unpack(">I4I4", head, 17)
end

local MAX_IMG = 8192 -- ReaImGui refuses larger images (some themes ship very tall knob filmstrips)

local function img_entry(path)
  local e = IMG[path]
  if e ~= nil then return e or nil end
  IMG[path] = false
  if not exists(path) then return nil end
  local pw, ph = png_size(path)
  if pw and (pw > MAX_IMG or ph > MAX_IMG) then return nil end -- falls back to the next image name / drawn shape
  local ok, img = pcall(ImGui.CreateImage, path)
  if not ok or not img then return nil end
  ImGui.Attach(ctx, img)
  local w, h = ImGui.Image_GetSize(img)
  e = { img = img, w = w, h = h }
  if w > 2 and h > 2 then
    local function row(y) local a = reaper.new_array(w); ImGui.Image_GetPixels_Array(img, 0, y, w, 1, a); return a end
    local function col(x) local a = reaper.new_array(h); ImGui.Image_GetPixels_Array(img, x, 0, 1, h, a); return a end
    local top = row(0)
    if is_mark(top[1]) then
      local left, bot, right = col(0), row(h - 1), col(w - 1)
      local function run(a, from, step, n)
        local c, i = 0, from
        while c < n and is_mark(a[i]) do c = c + 1; i = i + step end
        return c
      end
      e.border = { l = run(top, 2, 1, w - 2), t = run(left, 2, 1, h - 2), r = run(bot, w - 1, -1, w - 2), b = run(right, h - 1, -1, h - 2) }
    end
  end
  IMG[path] = e
  return e
end

local function find_img(names, imgdir)
  for _, n in ipairs(names) do
    if imgdir then
      local e = img_entry(T.meta.res .. "/" .. imgdir .. "/" .. n .. ".png")
      if e then return e end
    end
    local e = img_entry(T.meta.res .. "/" .. n .. ".png")
    if e then return e end
  end
end

local function inner(e)
  if e.border then return 1, 1, e.w - 2, e.h - 2 end
  return 0, 0, e.w, e.h
end

local function blit(dl, e, x1, y1, x2, y2, sx, sy, sw, sh)
  ImGui.DrawList_AddImage(dl, e.img, x1, y1, x2, y2, sx / e.w, sy / e.h, (sx + sw) / e.w, (sy + sh) / e.h, 0xFFFFFFFF)
end

-- draws (a frame of) an image into a rect, honoring resize borders as a 9-slice
local function draw_img(dl, e, x1, y1, x2, y2, z, fx, fw)
  local ix, iy, iw, ih = inner(e)
  if fx then ix, iw = ix + fx, fw end
  local b = e.border
  if not b then return blit(dl, e, x1, y1, x2, y2, ix, iy, iw, ih) end
  local L, R, Tp, B = b.l, b.r, b.t, b.b
  if L + R >= iw then L, R = 0, 0 end
  if Tp + B >= ih then Tp, B = 0, 0 end
  local s = z / T.img_scale
  local dl_, dr_, dt_, db_ = L * s, R * s, Tp * s, B * s
  local dw, dh = x2 - x1, y2 - y1
  if dl_ + dr_ > dw then local k = dw / (dl_ + dr_); dl_, dr_ = dl_ * k, dr_ * k end
  if dt_ + db_ > dh then local k = dh / (dt_ + db_); dt_, db_ = dt_ * k, db_ * k end
  local xs, us = { x1, x1 + dl_, x2 - dr_, x2 }, { ix, ix + L, ix + iw - R, ix + iw }
  local ys, vs = { y1, y1 + dt_, y2 - db_, y2 }, { iy, iy + Tp, iy + ih - B, iy + ih }
  for a = 1, 3 do
    for c = 1, 3 do
      if xs[a + 1] > xs[a] and ys[c + 1] > ys[c] and us[a + 1] > us[a] and vs[c + 1] > vs[c] then
        blit(dl, e, xs[a], ys[c], xs[a + 1], ys[c + 1], us[a], vs[c], us[a + 1] - us[a], vs[c + 1] - vs[c])
      end
    end
  end
end

----------------------------------------------------------------------------------------------------
-- Panel renderer
----------------------------------------------------------------------------------------------------
-- the four editable UI sections; image name prefixes are tried in order (master first, then generic)
local SECTIONS = {
  { id = "tcp", label = "TCP", btn = { "track" }, panel = { "tcp" }, meter = { "meter_bg_tcp" } },
  { id = "master.tcp", label = "Master TCP", btn = { "master_tcp", "tcp_master", "track" },
    panel = { "tcp_master", "master_tcp", "tcp" }, meter = { "meter_bg_tcp_master", "meter_bg_tcp" } },
  { id = "mcp", label = "MCP", btn = { "mcp", "track" }, panel = { "mcp" }, meter = { "meter_bg_mcp" } },
  { id = "master.mcp", label = "Master MCP", btn = { "master_mcp", "mcp_master", "mcp", "track" },
    panel = { "mcp_master", "master_mcp", "mcp" }, meter = { "meter_bg_mcp_master", "meter_bg_mcp" } },
}
local SEC = {}
for _, sc in ipairs(SECTIONS) do SEC[sc.id] = sc end
local TABS = {
  { label = "TCP", ids = { "tcp" } },
  { label = "MCP", ids = { "mcp" } },
  { label = "Master", ids = { "master.tcp", "master.mcp" }, sub = { "Track panel", "Mixer strip" } },
}

local SEC_ELEMS = { -- draw order (back to front)
  tcp = { "meter", "fxparm", "fxlist", "sendlist", "fxembed", "infoblock", "label", "recinput", "trackidx", "volume", "pan",
    "width", "volume.label", "pan.label", "width.label", "recarm", "recmon", "recmode", "fxin", "mute", "solo", "phase", "fx",
    "fxbyp", "io", "env", "folder", "foldercomp" },
  ["master.tcp"] = { "meter", "fxparm", "fxlist", "sendlist", "fxembed", "label", "volume", "pan", "width", "volume.label",
    "pan.label", "width.label", "mono", "mute", "solo", "fx", "fxbyp", "io", "env" },
  mcp = { "meter", "extmixer.position", "label", "recinput", "trackidx", "volume", "pan", "width", "volume.label", "pan.label",
    "width.label", "recarm", "recmon", "recmode", "fxin", "mute", "solo", "phase", "fx", "fxbyp", "io", "env", "folder" },
  ["master.mcp"] = { "meter", "extmixer.position", "label", "volume", "pan", "width", "volume.label", "pan.label", "width.label",
    "mono", "mute", "solo", "fx", "fxbyp", "io", "env", "menubutton" },
}
local NICE_SUF = {
  meter = "Meter", fxparm = "FX parameters", fxlist = "FX insert list", sendlist = "Send list", fxembed = "FX embed",
  infoblock = "Info block", label = "Track name", recinput = "Record input", trackidx = "Track number", volume = "Volume",
  pan = "Pan", width = "Width", ["volume.label"] = "Volume readout", ["pan.label"] = "Pan readout", ["width.label"] = "Width readout",
  recarm = "Record arm", recmon = "Record monitor", recmode = "Record mode", fxin = "Input FX", mute = "Mute", solo = "Solo",
  phase = "Phase", fx = "FX", fxbyp = "FX bypass", io = "Routing (I/O)", env = "Envelope", folder = "Folder",
  foldercomp = "Folder collapse", mono = "Mono / stereo", ["extmixer.position"] = "Extended mixer area", menubutton = "Mixer menu",
}
local BTN_SUF = { -- "%s" = section button prefix (track / mcp / master_mcp ...)
  mute = { "%s_mute_off" }, solo = { "%s_solo_off" }, recarm = { "%s_recarm_off" }, recmon = { "%s_monitor_on", "%s_monitor_off" },
  phase = { "%s_phase_norm" }, fx = { "%s_fx_norm", "%s_fx_empty" }, io = { "%s_io" }, env = { "%s_env" },
  recmode = { "%s_recmode_in" }, fxin = { "%s_fx_in_norm", "%s_fx_in_empty" }, foldercomp = { "%s_fcomp_off" },
  folder = { "%s_folder_off", "%s_folder_on" }, mono = { "%s_mono", "%s_stereo" },
}
local KNOB_SUF = { -- "%s" = section panel prefix (tcp / mcp / mcp_master ...)
  volume = { stack = { "%s_vol_knob_stack" }, knob = { "%s_vol_knob_small", "%s_vol_knob_large" }, bg = { "%s_volbg" }, thumb = { "%s_volthumb" }, pos = 0.72 },
  pan = { stack = { "%s_pan_knob_stack" }, knob = { "%s_pan_knob_small", "%s_pan_knob_large" }, bg = { "%s_panbg" }, thumb = { "%s_panthumb" }, pos = 0.5 },
  width = { stack = { "%s_wid_knob_stack" }, knob = { "%s_width_knob_small", "%s_wid_knob_small" }, bg = { "%s_widthbg" }, thumb = { "%s_widththumb" }, pos = 1 },
}
local TEXT_SUF = {
  label = { "Track 1", "%s_namebg" }, trackidx = { "1", "%s_idxbg" }, recinput = { "Input 1", "%s_recinput" },
  ["volume.label"] = { "0.00dB" }, ["pan.label"] = { "center" }, ["width.label"] = { "100%" }, infoblock = { "info" },
}
local DEF_SIZE = { -- size for elements a layout doesn't place yet (buttons use their image size)
  label = { 120, 20 }, trackidx = { 20, 14 }, recinput = { 120, 16 }, ["volume.label"] = { 45, 10 }, ["pan.label"] = { 31, 10 },
  ["width.label"] = { 31, 10 }, meter = { 12, 60 }, fxparm = { 200, 40 }, fxlist = { 120, 40 }, sendlist = { 120, 40 },
  fxembed = { 120, 40 }, infoblock = { 60, 14 }, ["extmixer.position"] = { 60, 120 }, menubutton = { 22, 22 }, mono = { 22, 16 },
}

local function SC() return SEC[S.sec] end
local function suf(e) return e:sub(#S.sec + 2) end
local function in_sec(e) return W.sec_of(e) == S.sec end
local function expand(pats, prefixes)
  local t = {}
  for _, p in ipairs(prefixes) do for _, pat in ipairs(pats) do t[#t + 1] = pat:format(p) end end
  return t
end

local function elem_list()
  local t = {}
  for _, x in ipairs(SEC_ELEMS[S.sec]) do t[#t + 1] = S.sec .. "." .. x end
  local cust = {}
  for k in pairs(T.C.customs) do if in_sec(k) then cust[#cust + 1] = k end end
  table.sort(cust)
  for _, k in ipairs(cust) do t[#t + 1] = k end
  return t
end

local function nice(e) return NICE_SUF[suf(e)] or (T.C.customs[e] and T.C.customs[e].label) or e end
local function is_control(e) local x = suf(e); return BTN_SUF[x] or KNOB_SUF[x] or x == "fxbyp" end

local function draw_order(L)
  local t, infront = {}, {}
  for _, e in ipairs(L.front) do infront[e] = true end
  for _, e in ipairs(elem_list()) do if not infront[e] then t[#t + 1] = e end end
  for _, e in ipairs(L.front) do if in_sec(e) and (NICE_SUF[suf(e)] or T.C.customs[e]) then t[#t + 1] = e end end
  return t
end

local function wcol(v, default)
  if not v or (v[1] == 0 and v[2] == 0 and v[3] == 0 and v[4] == 0) then return default end
  local a = clamp8(v[4])
  if a == 0 then a = 255 end
  return (clamp8(v[1]) << 24) | (clamp8(v[2]) << 16) | (clamp8(v[3]) << 8) | a
end

local function text_in(dl, x1, y1, x2, y2, text, col, size, align)
  local fs = ImGui.GetFontSize(ctx)
  local tw = ImGui.CalcTextSize(ctx, text) * size / fs
  local tx = x1 + math.max(0, (x2 - x1 - tw)) * (align or 0)
  local ty = y1 + (y2 - y1 - size) / 2
  ImGui.DrawList_PushClipRect(dl, x1, y1, x2, y2, true)
  ImGui.DrawList_AddTextEx(dl, FONT, size, tx, ty, col, text)
  ImGui.DrawList_PopClipRect(dl)
end

local function button_img(e, w, h)
  local x, sc = suf(e), SC()
  if x == "fxbyp" then
    return expand(h > w * 1.2 and { "%s_fxon_v", "%s_fxempty_v" } or { "%s_fxon_h", "%s_fxempty_h" }, sc.btn)
  end
  local cu = T.C.customs[e]
  if cu and cu.image then return { cu.image } end
  return BTN_SUF[x] and expand(BTN_SUF[x], sc.btn)
end

local function draw_element(dl, L, e, imgdir, x1, y1, x2, y2, z)
  local w, h = x2 - x1, y2 - y1
  local v = L.vars
  local btn = button_img(e, w, h)
  if btn then
    local im = find_img(btn, imgdir)
    if im then
      local _, _, iw = inner(im)
      draw_img(dl, im, x1, y1, x2, y2, z, 0, iw >= 3 and iw / 3 or iw)
      return
    end
  end

  local sx, sc = suf(e), SC()
  local kn = KNOB_SUF[sx]
  if kn then
    local fm = v[e .. ".fadermode"] and v[e .. ".fadermode"][1] or 0
    local knob = fm > 0 or (fm == 0 and w <= h * 1.6 and h <= w * 1.6)
    if knob then
      local s = math.min(w, h)
      local kx, ky = x1 + (w - s) / 2, y1 + (h - s) / 2
      local st = find_img(expand(kn.stack, sc.panel), imgdir)
      if st and st.h >= st.w * 2 then
        local n = math.floor(st.h / st.w)
        local f = math.floor(kn.pos * (n - 1) + 0.5)
        blit(dl, st, kx, ky, kx + s, ky + s, 0, f * st.w, st.w, st.w)
        return
      end
      local im = find_img(expand(kn.knob, sc.panel), imgdir)
      if im then draw_img(dl, im, kx, ky, kx + s, ky + s, z) return end
      local cx, cy, r = kx + s / 2, ky + s / 2, s / 2 - 1
      ImGui.DrawList_AddCircleFilled(dl, cx, cy, r, 0x3A3F48FF)
      ImGui.DrawList_AddCircle(dl, cx, cy, r, 0x9AA0AAFF, 0, 1)
      local a = math.pi * (0.75 + 1.5 * kn.pos)
      ImGui.DrawList_AddLine(dl, cx, cy, cx + math.cos(a) * r, cy + math.sin(a) * r, 0xE0E0E0FF, 1.5)
      return
    end
    local vert = h > w -- MCP faders are vertical
    local bg = find_img(expand(kn.bg, sc.panel), imgdir)
    if bg then draw_img(dl, bg, x1, y1, x2, y2, z)
    elseif vert then ImGui.DrawList_AddRectFilled(dl, x1 + w * 0.35, y1, x2 - w * 0.35, y2, 0x00000080, 2)
    else ImGui.DrawList_AddRectFilled(dl, x1, y1 + h * 0.35, x2, y2 - h * 0.35, 0x00000080, 2) end
    local th = find_img(expand(kn.thumb, sc.panel), imgdir)
    local tw_, th_ = vert and w or h * 0.6, vert and w * 0.6 or h
    if th then tw_ = math.min(w, th.w / T.img_scale * z); th_ = math.min(h, th.h / T.img_scale * z) end
    local tx, ty
    if vert then tx, ty = x1 + (w - tw_) / 2, y1 + (h - th_) * (1 - kn.pos)
    else tx, ty = x1 + (w - tw_) * kn.pos, y1 + (h - th_) / 2 end
    if th then draw_img(dl, th, tx, ty, tx + tw_, ty + th_, z) else ImGui.DrawList_AddRectFilled(dl, tx, ty, tx + tw_, ty + th_, 0xC8C8C8FF, 2) end
    return
  end

  local tx = TEXT_SUF[sx]
  if tx then
    if tx[2] then
      local bg = find_img(expand({ tx[2] }, sc.panel), imgdir)
      if bg then draw_img(dl, bg, x1, y1, x2, y2, z) end
    end
    local m = v[e .. ".margin"] or { 0, 0, 0, 0, (sx == "trackidx" or S.sec:find("mcp")) and 0.5 or 0 }
    local col = wcol(v[e .. ".color"], T.colors.text)
    local size = math.max(6, math.min(h - 2 * z, 13 * z))
    text_in(dl, x1 + m[1] * z, y1 + m[2] * z, x2 - m[3] * z, y2 - m[4] * z, tx[1], col, size, m[5])
    return
  end

  if sx == "meter" then
    local bg = find_img(sc.meter, imgdir)
    if bg then draw_img(dl, bg, x1, y1, x2, y2, z) else ImGui.DrawList_AddRectFilled(dl, x1, y1, x2, y2, 0x101214FF) end
    local pad = math.max(1, z)
    if h >= w then
      local mid = (x1 + x2) / 2
      ImGui.DrawList_AddRectFilled(dl, x1 + pad, y1 + h * 0.4, mid - pad / 2, y2 - pad, 0x46C46A90)
      ImGui.DrawList_AddRectFilled(dl, mid + pad / 2, y1 + h * 0.5, x2 - pad, y2 - pad, 0x46C46A90)
    else
      local mid = (y1 + y2) / 2
      ImGui.DrawList_AddRectFilled(dl, x1 + pad, y1 + pad, x1 + w * 0.6, mid - pad / 2, 0x46C46A90)
      ImGui.DrawList_AddRectFilled(dl, x1 + pad, mid + pad / 2, x1 + w * 0.5, y2 - pad, 0x46C46A90)
    end
    return
  end

  -- lists / embeds / unknown: labeled box
  ImGui.DrawList_AddRectFilled(dl, x1, y1, x2, y2, 0x00000055, 2)
  ImGui.DrawList_AddRect(dl, x1, y1, x2, y2, 0xFFFFFF30, 2)
  text_in(dl, x1 + 3, y1, x2 - 3, math.min(y2, y1 + 16 * math.max(1, z * 0.7)), nice(e), 0xFFFFFF90, math.max(7, 10 * math.min(z, 1.6)), 0)
end

-- draws one layout's panel at (ox,oy) with zoom z. canvas = {x1,y1,x2,y2}: draw elements outside the
-- panel too (dimmed). Returns {e,l,t,r,b} screen rects in draw order.
local function render_panel(dl, name, ox, oy, z, canvas)
  local L = LS(name)
  local out = {}
  local px2, py2 = ox + P.W * z, oy + P.H * z
  local imgdir = imgdir_of(name)
  ImGui.DrawList_PushClipRect(dl, ox, oy, px2, py2, true)
  local bg = find_img(expand(P.selected and { "%s_bgsel", "%s_bg" } or { "%s_bg", "%s_mainbg" }, SC().panel), imgdir)
  if bg then draw_img(dl, bg, ox, oy, px2, py2, z) else ImGui.DrawList_AddRectFilled(dl, ox, oy, px2, py2, 0x33363CFF) end
  if canvas then ImGui.DrawList_PopClipRect(dl) end
  if L then
    for _, e in ipairs(draw_order(L)) do
      local l, t, r, b = erect(L, e)
      if l then
        local x1, y1, x2, y2 = ox + l * z, oy + t * z, ox + r * z, oy + b * z
        -- REAPER clips elements to the panel; themes rely on it (White Tie's imageshift makes an element
        -- 3 panels wide and slides it left to show another frame). Elements parked fully outside stay unclipped.
        local inside = x1 < px2 and x2 > ox and y1 < py2 and y2 > oy
        if inside then ImGui.DrawList_PushClipRect(dl, ox, oy, px2, py2, true) end
        draw_element(dl, L, e, imgdir, x1, y1, x2, y2, z)
        if inside then
          ImGui.DrawList_PopClipRect(dl)
          x1, y1, x2, y2 = math.max(x1, ox), math.max(y1, oy), math.min(x2, px2), math.min(y2, py2)
        end
        out[#out + 1] = { e = e, l = x1, t = y1, r = x2, b = y2 }
      end
    end
  end
  if canvas then
    -- dim whatever lies outside the panel (REAPER won't show it)
    local dim = with_alpha(C_.canvas, 0xA0)
    local cx1, cy1, cx2, cy2 = canvas[1], canvas[2], canvas[3], canvas[4]
    ImGui.DrawList_AddRectFilled(dl, cx1, cy1, cx2, oy, dim)
    ImGui.DrawList_AddRectFilled(dl, cx1, py2, cx2, cy2, dim)
    ImGui.DrawList_AddRectFilled(dl, cx1, oy, ox, py2, dim)
    ImGui.DrawList_AddRectFilled(dl, px2, oy, cx2, py2, dim)
  else
    ImGui.DrawList_PopClipRect(dl)
  end
  return out
end

-- small preview of one element, fitted into a box (element list)
local function draw_icon(dl, name, L, e, x, y, bw, bh)
  local imgdir = imgdir_of(name)
  local l, t, r, b = erect(L, e)
  local w, h
  local vl, vt, vr, vb -- part inside the panel (REAPER clips the rest)
  if l then
    w, h = r - l, b - t
    if l < P.W and r > 0 and t < P.H and b > 0 then
      vl, vt, vr, vb = math.max(l, 0), math.max(t, 0), math.min(r, P.W), math.min(b, P.H)
    end
  else
    local im = button_img(e, 22, 22) and find_img(button_img(e, 22, 22), imgdir)
    if im then local _, _, iw, ih = inner(im); w, h = iw / 3 / T.img_scale, ih / T.img_scale
    else local d = DEF_SIZE[suf(e)] or { 22, 22 }; w, h = d[1], d[2] end
  end
  if vl then
    local s = math.min(bw / math.max(vr - vl, 1), bh / math.max(vb - vt, 1))
    local cx1, cy1 = x + (bw - (vr - vl) * s) / 2, y + (bh - (vb - vt) * s) / 2
    local x1, y1 = cx1 - (vl - l) * s, cy1 - (vt - t) * s
    ImGui.DrawList_PushClipRect(dl, cx1, cy1, cx1 + (vr - vl) * s, cy1 + (vb - vt) * s, true)
    draw_element(dl, L, e, imgdir, x1, y1, x1 + w * s, y1 + h * s, s)
    ImGui.DrawList_PopClipRect(dl)
    return
  end
  local s = math.min(bw / math.max(w, 1), bh / math.max(h, 1))
  local iw, ih = w * s, h * s
  local x1, y1 = x + (bw - iw) / 2, y + (bh - ih) / 2
  ImGui.DrawList_PushClipRect(dl, x, y, x + bw, y + bh, true)
  draw_element(dl, L, e, imgdir, x1, y1, x1 + iw, y1 + ih, s)
  ImGui.DrawList_PopClipRect(dl)
end

----------------------------------------------------------------------------------------------------
-- Edit operations
----------------------------------------------------------------------------------------------------
local function recs_of(name, create)
  local r = T.edits[name]
  if not r and create then r = {}; T.edits[name] = r end
  return r
end

-- element rect as the theme draws it (without our record for e)
local function theme_rect(name, e)
  local recs = recs_of(name)
  local saved = recs and recs[e]
  if saved then recs[e] = nil end
  local R = W.run(T.C, make_ctx(), W.compile_overrides(T.edits))
  if saved then recs[e] = saved end
  local L = name == "" and R.G or R.layouts[name]
  return erect(L, e)
end

local function ov(a, b) return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4] end

local function rects_except(L, e)
  local t = {}
  for _, o in ipairs(elem_list()) do
    if o ~= e then
      local l, tt, r, b = erect(L, o)
      if l then t[#t + 1] = { l, tt, r, b, e = o } end
    end
  end
  return t
end

-- edges a dragged element can snap to: the panel and the other elements (their part inside the panel)
local function snap_targets(L, e)
  local xs, ys = { 0, P.W }, { 0, P.H }
  for _, o in ipairs(rects_except(L, e)) do
    local l, t, r, b = o[1], o[2], o[3], o[4]
    if l < P.W and r > 0 and t < P.H and b > 0 then
      l, t, r, b = math.max(l, 0), math.max(t, 0), math.min(r, P.W), math.min(b, P.H)
    end
    xs[#xs + 1], xs[#xs + 2] = l, r
    ys[#ys + 1], ys[#ys + 2] = t, b
  end
  return xs, ys
end

local function first_hit(r, list)
  for _, o in ipairs(list) do if ov(r, o) then return o end end
end

-- the edge attachment most buttons in this layout use (new elements follow the same edge)
local function majority_att(L)
  local count, best, bestn = {}, nil, 0
  for _, e in ipairs(elem_list()) do
    if is_control(e) and erect(L, e) then
      local v = L.vars[e]
      local key = ("%g,%g,%g,%g"):format(v[5], v[6], v[7], v[8])
      count[key] = (count[key] or 0) + 1
      if count[key] > bestn then bestn, best = count[key], { v[5], v[6], v[7], v[8] } end
    end
  end
  return best or { 0, 0, 0, 0 }
end

local function nat_size(e, imgdir)
  local btn = button_img(e, 22, 22)
  local im = btn and find_img(btn, imgdir)
  if im then
    local _, _, iw, ih = inner(im)
    return math.max(4, math.floor(iw / 3 / T.img_scale + 0.5)), math.max(4, math.floor(ih / T.img_scale + 0.5))
  end
  local d = DEF_SIZE[suf(e)] or { 22, 22 }
  return d[1], d[2]
end

-- absolute record that lands on (l,t,w,h) at the current preview size
local function abs_rec(L, l, t, w, h, att)
  local bw, bh = base_size(L)
  local dW, dH = P.W - bw, P.H - bh
  return { mode = "abs", x = l - att[1] * dW, y = t - att[2] * dH, w = w - (att[3] - att[1]) * dW,
    h = h - (att[4] - att[2]) * dH, att = { att[1], att[2], att[3], att[4] } }
end

-- a new element: theme's default spot if free, otherwise lined up below the panel (left to right)
local function place_new(name, e)
  local L = LS(name)
  local others = rects_except(L, e)
  local att = majority_att(L)
  if name ~= "" then
    local gl, gt, gr, gb = erect(T.R.G, e)
    if gl and not first_hit({ gl, gt, gr, gb }, others) then return abs_rec(L, gl, gt, gr - gl, gb - gt, att) end
  end
  local w, h = nat_size(e, imgdir_of(name))
  local strip = S.sec:find("mcp") ~= nil
  local x, y = 0, P.H + 10
  if strip then x, y = P.W + 12, 0 end
  for _ = 1, 300 do
    local hit = first_hit({ x, y, x + w, y + h }, others)
    if not hit then break end
    if strip then y = hit[4] + 6 else x = hit[3] + 6 end
  end
  return abs_rec(L, x, y, w, h, att)
end

local function ensure_rec(name, e)
  local recs = recs_of(name, true)
  if recs[e] then return recs[e] end
  local r
  if erect(LS(name), e) then r = { mode = "offset", dx = 0, dy = 0, dw = 0, dh = 0 } else r = place_new(name, e) end
  recs[e] = r
  return r
end

local function move_elem(name, e, ddx, ddy, ddw, ddh)
  if ddx == 0 and ddy == 0 and ddw == 0 and ddh == 0 then return end
  local r = ensure_rec(name, e)
  r.hide = nil
  if r.mode == "abs" or (r.mode == "link" and r.lsize) then
    r.w = math.max(1, (r.w or 22) + ddw)
    r.h = math.max(1, (r.h or 22) + ddh)
  else
    r.dw = (r.dw or 0) + ddw
    r.dh = (r.dh or 0) + ddh
  end
  if r.mode == "abs" then r.x, r.y = r.x + ddx, r.y + ddy
  elseif r.mode == "link" then r.ox, r.oy = (r.ox or 0) + ddx, (r.oy or 0) + ddy
  else r.dx, r.dy = r.dx + ddx, r.dy + ddy end
  changed()
end

-- outside the panel, elements may not overlap: a dropped one is pushed to the right of what it hits
local function resolve_offpanel(name, e)
  local panel = { 0, 0, P.W, P.H }
  for _ = 1, 60 do
    evaluate(true)
    local L = LS(name)
    local l, t, r, b = erect(L, e)
    if not l or ov({ l, t, r, b }, panel) then return end
    local blocker
    for _, o in ipairs(rects_except(L, e)) do
      if not ov(o, panel) and ov({ l, t, r, b }, o) then blocker = o; break end
    end
    if not blocker then return end
    if S.sec:find("mcp") then move_elem(name, e, 0, blocker[4] + 6 - t, 0, 0)
    else move_elem(name, e, blocker[3] + 6 - l, 0, 0, 0) end
  end
end

local function elem_enabled(L, r, e)
  if r and r.hide then return false end
  return erect(L, e) ~= nil or (r ~= nil and W.has_rules(r))
end

local function set_hidden(name, e, hide)
  snapshot()
  local recs = recs_of(name, true)
  if hide then
    ensure_rec(name, e).hide = true
    changed()
    return
  end
  local r = recs[e]
  if r then r.hide = nil end
  changed()
  evaluate(true)
  if not erect(LS(name), e) and not (r and W.has_rules(r)) then
    local n = place_new(name, e)
    if r then n.hh, n.hw, n.arm, n.sel = r.hh, r.hw, r.arm, r.sel end
    recs[e] = n
    changed()
  end
end

local ANCHORS = {
  { "Theme default", nil }, { "Left / top (fixed)", { 0, 0, 0, 0 } }, { "Follow right edge", { 1, 0, 1, 0 } },
  { "Stretch with width", { 0, 0, 1, 0 } }, { "Follow bottom edge", { 0, 1, 0, 1 } }, { "Follow right + bottom", { 1, 1, 1, 1 } },
  { "Stretch width + height", { 0, 0, 1, 1 } },
}

-- change edge attachment while keeping the element where it is at the current preview size
local function set_anchor(name, e, att)
  local L = LS(name)
  local v = L.vars[e]
  if not v then return end
  snapshot()
  local r = ensure_rec(name, e)
  local bw, bh = base_size(L)
  if not att and r.mode == "offset" then
    r.att = nil
    changed()
    return
  end
  local new = att or { 0, 0, 0, 0 }
  local dW, dH = P.W - bw, P.H - bh
  local dlx, dty = (v[5] - new[1]) * dW, (v[6] - new[2]) * dH
  local drx, dby = (v[7] - new[3]) * dW, (v[8] - new[4]) * dH
  if r.mode == "abs" then
    r.x, r.y, r.w, r.h = r.x + dlx, r.y + dty, r.w + drx - dlx, r.h + dby - dty
  elseif r.mode == "offset" then
    r.dx, r.dy, r.dw, r.dh = r.dx + dlx, r.dy + dty, r.dw + drx - dlx, r.dh + dby - dty
  end
  r.att = { new[1], new[2], new[3], new[4] }
  changed()
end

local function keep_rules(from, to)
  if from then to.hh, to.hw, to.arm, to.sel = from.hh, from.hw, from.arm, from.sel end
  return to
end

local function set_link(name, e, target)
  local L = LS(name)
  local recs = recs_of(name, true)
  local r = recs[e]
  if not target then
    if not r or r.mode ~= "link" then return end
    snapshot()
    local l, t, rr, b = erect(L, e)
    local tl, tt, tr, tb = theme_rect(name, e)
    if r.lsize or not tl or not l then
      recs[e] = keep_rules(r, { mode = "abs", x = l or 10, y = t or 10, w = l and rr - l or 22, h = l and b - t or 22 })
    else
      recs[e] = keep_rules(r, { mode = "offset", dx = l - tl, dy = t - tt, dw = (rr - l) - (tr - tl), dh = (b - t) - (tb - tt) })
    end
    changed()
    return
  end
  snapshot()
  r = ensure_rec(name, e)
  local l, t, rr, b = erect(L, e)
  local al, at = erect(L, target)
  if not (l and al) then return end
  if r.mode == "abs" then
    recs[e] = keep_rules(r, { mode = "link", link = target, ox = l - al, oy = t - at, lsize = true, w = rr - l, h = b - t })
  else
    recs[e] = keep_rules(r, { mode = "link", link = target, ox = l - al, oy = t - at, dw = r.dw or 0, dh = r.dh or 0 })
  end
  changed()
end

local function linked_to(name, e, target) -- would linking e -> target create a cycle?
  local recs = recs_of(name) or {}
  local cur, guard = target, 0
  while cur and guard < 64 do
    if cur == e then return true end
    local r = recs[cur]
    cur = r and not r.hide and r.mode == "link" and r.link or nil
    guard = guard + 1
  end
  return false
end

local function count_edits(name)
  local n = 0
  for e in pairs(recs_of(name) or {}) do if in_sec(e) then n = n + 1 end end
  return n
end

-- this section's records of a layout (other sections' edits stay where they are)
local function take_sec_recs(name, remove)
  local out = {}
  for e, r in pairs(recs_of(name) or {}) do
    if in_sec(e) then out[e] = r; if remove then T.edits[name][e] = nil end end
  end
  return out
end

----------------------------------------------------------------------------------------------------
-- Apply / refresh
----------------------------------------------------------------------------------------------------
local function apply()
  for name, recs in pairs(T.edits) do if not next(recs) then T.edits[name] = nil end end
  local out = W.compose(T.plain, T.C, T.edits)
  local prev = read_file(T.path)
  local prev_disk = T.on_disk
  local bak
  if S.backup then
    bak = T.meta.res .. "/rtconfig_" .. os.date("%Y%m%d-%H%M%S") .. ".txt"
    local orig = read_file(T.path)
    if not (orig and write_file(bak, orig)) then status("Backup failed, nothing written.", true) return end
  end
  local ok, err = write_file(T.path, table.concat(out, T.eol) .. T.eol)
  if not ok then status("Write failed: " .. tostring(err), true) return end
  T.dirty = false
  T.on_disk = disk_layouts()
  if prev then
    S.toast = { t0 = reaper.time_precise(), msg = "Saved to rtconfig.txt" .. (bak and " (backup kept)" or ""),
      prev = prev, path = T.path, bak = bak, on_disk = prev_disk }
  end
  status("Saved rtconfig.txt" .. (bak and (" (backup: " .. bak:match("[^/]+$") .. ")") or "") .. ". Press Refresh to see it in REAPER.")
end

local function refresh_reaper()
  reaper.OpenColorThemeFile(T.meta.file)
  reaper.ThemeLayout_RefreshAll()
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
  status("Reloaded " .. T.meta.name .. " in REAPER.")
end

----------------------------------------------------------------------------------------------------
-- Popups
----------------------------------------------------------------------------------------------------
local function open_popup(id, data)
  S.popup = id
  S.popup_data = data or {}
end

local function name_taken(n)
  for _, b in ipairs(T.C.blocks) do if b.name == n and b.secs[S.sec] then return true end end
  return false
end

local function modal(id, body)
  if ImGui.BeginPopupModal(ctx, id, true, ImGui.WindowFlags_AlwaysAutoResize) then
    body()
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then ImGui.CloseCurrentPopup(ctx) end
    ImGui.EndPopup(ctx)
  end
end

local function draw_popups()
  if S.popup then
    ImGui.OpenPopup(ctx, S.popup)
    S.popup = nil
  end
  local d = S.popup_data

  modal("Unpack theme", function()
    ImGui.Text(ctx, d.theme.name)
    ImGui.TextDisabled(ctx, "This theme is still zipped. Unpack it so its layouts can be edited.")
    ImGui.Spacing(ctx)
    ImGui.SetNextItemWidth(ctx, 320)
    d.newname = select(2, ImGui.InputText(ctx, "Copy name", d.newname))
    tip("Used by 'Duplicate & unpack': the copy gets its own folder and .ReaperTheme file.")
    ImGui.Spacing(ctx)
    local function done(f, err)
      if f then
        scan_themes()
        for i, t in ipairs(S.themes) do if t.file == f then S.theme_idx = i; load_theme(t) end end
        ImGui.CloseCurrentPopup(ctx)
      else status(err, true) end
    end
    if accent_button("Duplicate & unpack") then done(unpack_zip(d.theme, d.newname)) end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Unpack directly") then done(unpack_zip(d.theme, nil)) end
    tip("Extracts next to the zip (existing files are never overwritten).")
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel") then ImGui.CloseCurrentPopup(ctx) end
  end)

  modal("Layout name", function()
    local title = d.mode == "dup" and ("Duplicate \"" .. layout_label(d.src) .. "\" as:")
      or d.mode == "rename" and ("Rename \"" .. layout_label(d.src) .. "\" to:") or "New layout name:"
    ImGui.Text(ctx, title)
    if d.mode == "rename" and T.on_disk[d.src] then
      ImGui.TextColored(ctx, C_.accent, "Tracks in your projects that use this layout name\nwill fall back to the default layout after renaming.")
    end
    if ImGui.IsWindowAppearing(ctx) then ImGui.SetKeyboardFocusHere(ctx) end
    ImGui.SetNextItemWidth(ctx, 320)
    local enter
    enter, d.name = ImGui.InputText(ctx, "##name", d.name, ImGui.InputTextFlags_EnterReturnsTrue)
    local n = (d.name or ""):match("^%s*(.-)%s*$")
    local bad = n == "" and "Enter a name."
      or (n:find("'") and n:find('"')) and "Can't use both quote types."
      or (n ~= d.src and name_taken(n)) and "A layout with this name already exists."
      or (d.mode == "rename" and n == d.src) and "" or nil
    if bad and bad ~= "" then ImGui.TextColored(ctx, C_.danger, bad) end
    ImGui.BeginDisabled(ctx, bad ~= nil)
    if accent_button("OK", math.max(80, btn_w("Cancel"))) or (enter and not bad) then
      snapshot()
      if d.mode == "dup" then
        T.plain = W.duplicate_layout(T.plain, T.C, d.src, n, S.sec)
        local cp = deep(take_sec_recs(d.src))
        if next(cp) then recs_of(n, true); for e, r in pairs(cp) do T.edits[n][e] = r end end
      elseif d.mode == "rename" then
        T.plain = W.rename_layout(T.plain, T.C, d.src, n, S.sec)
        local mv = take_sec_recs(d.src, true)
        if next(mv) then recs_of(n, true); for e, r in pairs(mv) do T.edits[n][e] = r end end
      else
        T.plain = W.new_layout(T.plain, T.C, n, S.sec)
      end
      changed(true)
      S.sel_layout = n
      status("Layout \"" .. n .. "\" " .. (d.mode == "rename" and "renamed" or "created") .. " (not written yet — press Apply).")
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.EndDisabled(ctx)
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel", math.max(80, btn_w("Cancel"))) then ImGui.CloseCurrentPopup(ctx) end
  end)

  modal("Delete layout", function()
    ImGui.Text(ctx, "Delete \"" .. layout_label(d.name) .. "\"?")
    ImGui.TextDisabled(ctx, "Removes its TCP blocks from rtconfig.txt when you Apply.")
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, C_.danger)
    if ImGui.Button(ctx, "Delete", math.max(90, btn_w("Cancel"))) then
      snapshot()
      T.plain = W.delete_layout(T.plain, T.C, d.name, S.sec)
      take_sec_recs(d.name, true)
      changed(true)
      S.sel_layout = nil
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.PopStyleColor(ctx)
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel", math.max(90, btn_w("Cancel"))) then ImGui.CloseCurrentPopup(ctx) end
  end)

  modal("Unsaved changes", function()
    ImGui.Text(ctx, "You have changes that aren't written to rtconfig.txt yet.")
    ImGui.Spacing(ctx)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, C_.danger)
    if ImGui.Button(ctx, "Discard changes") then
      T.dirty = false
      ImGui.CloseCurrentPopup(ctx)
      if d.after then d.after() end
    end
    ImGui.PopStyleColor(ctx)
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel") then ImGui.CloseCurrentPopup(ctx) end
  end)
end

local function guard_unsaved(fn)
  if T and T.dirty then open_popup("Unsaved changes", { after = fn }) else fn() end
end

local function try_select_theme(i)
  local t = S.themes[i]
  if not t then return end
  guard_unsaved(function()
    if t.kind == "zip" then
      open_popup("Unpack theme", { theme = t, newname = t.name .. " mod" })
    else
      S.theme_idx = i
      load_theme(t)
    end
  end)
end

----------------------------------------------------------------------------------------------------
-- Appearance window
----------------------------------------------------------------------------------------------------
local function draw_settings()
  if not S.show_style then return end
  local vis, open = ImGui.Begin(ctx, "Appearance", true, ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoCollapse | G.pin_flag(THEME_KEY))
  if vis then
    local ch = false
    local fh = ImGui.GetFrameHeight(ctx)
    if G.theme_row(ctx, THEME_KEY) then ch = true end -- theme_row reloads G.theme
    ImGui.Spacing(ctx)
    ImGui.BeginDisabled(ctx, G.inherited) -- colours come from the global theme while inheriting
    for _, kv in ipairs(STYLE_KEYS) do
      local key = kv[1]
      ImGui.PushID(ctx, key)
      -- NoAlpha colors are 0xRRGGBB in ReaImGui (ours are 0xRRGGBBAA)
      if ImGui.ColorButton(ctx, "##swatch", ST[key] >> 8, ImGui.ColorEditFlags_NoAlpha, 36, fh) then ImGui.OpenPopup(ctx, "picker") end
      ImGui.SameLine(ctx)
      ImGui.AlignTextToFramePadding(ctx)
      ImGui.Text(ctx, kv[2])
      if ImGui.BeginPopup(ctx, "picker") then
        local rv, c = ImGui.ColorPicker4(ctx, "##pick", ST[key] >> 8,
          ImGui.ColorEditFlags_NoAlpha | ImGui.ColorEditFlags_DisplayRGB | ImGui.ColorEditFlags_NoSidePreview)
        if rv then ST[key] = ((math.floor(c) & 0xFFFFFF) << 8) | 0xFF; ch = true end
        ImGui.EndPopup(ctx)
      end
      ImGui.PopID(ctx)
    end
    ImGui.EndDisabled(ctx)
    ImGui.Spacing(ctx)
    ImGui.SetNextItemWidth(ctx, 150)
    local rv, v = ImGui.SliderInt(ctx, "Text size", ST.font, 10, 22)
    if rv then ST.font = v; ch = true end
    ImGui.Spacing(ctx)
    ImGui.Separator(ctx)
    local brv, bv = ImGui.Checkbox(ctx, "Leave a backup when applying", S.backup)
    if brv then S.backup = bv; reaper.SetExtState(EXT, "backup", bv and "1" or "0", true) end
    tip("Before Apply writes rtconfig.txt, keep the old file as rtconfig_<date-time>.txt in the theme folder")
    ImGui.Spacing(ctx)
    if ImGui.Button(ctx, "Reset to defaults") then
      for k, x in pairs(DEFAULT_STYLE) do ST[k] = x end
      ch = true
    end
    if ch then derive_style(); save_style() end
    ImGui.End(ctx)
  end
  if not open then S.show_style = false end
end

----------------------------------------------------------------------------------------------------
-- Header
----------------------------------------------------------------------------------------------------
-- small line icons drawn with the draw list (no font glyphs needed)
local function draw_glyph(dl, kind, cx, cy, r, col)
  local th = math.max(1.4, r * 0.18)
  if kind == "folder" then
    ImGui.DrawList_AddRect(dl, cx - r, cy - r * 0.45, cx + r, cy + r * 0.8, col, 2, 0, th)
    ImGui.DrawList_AddRectFilled(dl, cx - r, cy - r * 0.8, cx - r * 0.15, cy - r * 0.45, col, 1.5)
  elseif kind == "search" then
    ImGui.DrawList_AddCircle(dl, cx - r * 0.2, cy - r * 0.2, r * 0.6, col, 0, th)
    ImGui.DrawList_AddLine(dl, cx + r * 0.25, cy + r * 0.25, cx + r * 0.9, cy + r * 0.9, col, th * 1.3)
  elseif kind == "undo" or kind == "redo" then
    local m = kind == "undo" and 1 or -1
    ImGui.DrawList_PathClear(dl)
    if m == 1 then ImGui.DrawList_PathArcTo(dl, cx + r * 0.1, cy + r * 0.15, r * 0.7, math.pi, math.pi * 2.3, 16)
    else ImGui.DrawList_PathArcTo(dl, cx - r * 0.1, cy + r * 0.15, r * 0.7, 0, -math.pi * 1.3, 16) end
    ImGui.DrawList_PathStroke(dl, col, 0, th)
    local ax, ay = cx + m * (r * 0.1 - r * 0.7), cy + r * 0.15
    ImGui.DrawList_AddTriangleFilled(dl, ax - r * 0.38, ay - r * 0.1, ax + r * 0.38, ay - r * 0.1, ax, ay + r * 0.45, col)
  elseif kind == "refresh" then
    ImGui.DrawList_PathClear(dl)
    ImGui.DrawList_PathArcTo(dl, cx, cy, r * 0.72, -math.pi * 0.35, math.pi * 1.25, 18)
    ImGui.DrawList_PathStroke(dl, col, 0, th)
    local a = -math.pi * 0.35
    local ax, ay = cx + math.cos(a) * r * 0.72, cy + math.sin(a) * r * 0.72
    ImGui.DrawList_AddTriangleFilled(dl, ax - r * 0.42, ay - r * 0.1, ax + r * 0.3, ay - r * 0.42, ax + r * 0.18, ay + r * 0.38, col)
  elseif kind == "gear" then
    for k = 0, 7 do
      local a = k * math.pi / 4
      ImGui.DrawList_AddLine(dl, cx + math.cos(a) * r * 0.55, cy + math.sin(a) * r * 0.55,
        cx + math.cos(a) * r * 0.95, cy + math.sin(a) * r * 0.95, col, th * 1.8)
    end
    ImGui.DrawList_AddCircle(dl, cx, cy, r * 0.6, col, 0, th * 1.4)
    ImGui.DrawList_AddCircle(dl, cx, cy, r * 0.22, col, 0, th)
  end
end

-- toolbar button: full text label, or a square icon button in compact mode
local function tool_button(label, icon, compact, enabled, w)
  local fh = ImGui.GetFrameHeight(ctx)
  ImGui.BeginDisabled(ctx, enabled == false)
  local clicked
  if compact then
    clicked = ImGui.Button(ctx, "##" .. label, fh + 4, fh)
    local x1, y1 = ImGui.GetItemRectMin(ctx)
    draw_glyph(ImGui.GetWindowDrawList(ctx), icon, x1 + (fh + 4) / 2, y1 + fh / 2, fh * 0.34, enabled == false and C_.dim or C_.text)
  else
    clicked = ImGui.Button(ctx, label, w or 0, 0)
  end
  ImGui.EndDisabled(ctx)
  return clicked
end

local function draw_header()
  -- toolbar band behind the header row
  local dl = ImGui.GetWindowDrawList(ctx)
  local wx, wy = ImGui.GetWindowPos(ctx)
  local ww, wh = ImGui.GetWindowSize(ctx)
  local x0, y0 = ImGui.GetCursorScreenPos(ctx)
  local fh = ImGui.GetFrameHeight(ctx)
  ImGui.DrawList_PushClipRect(dl, wx, wy, wx + ww, wy + wh, false)
  ImGui.DrawList_AddRectFilled(dl, wx, y0 - 9, wx + ww, y0 + fh + 9, C_.child)
  ImGui.DrawList_AddLine(dl, wx, y0 + fh + 9, wx + ww, y0 + fh + 9, C_.border)
  ImGui.DrawList_PopClipRect(dl)

  -- always one row: switch to icon buttons, then shrink the theme list, when space runs out
  local avail = ImGui.GetContentRegionAvail(ctx)
  local ib = fh + 4
  local apply_w = math.max(74, btn_w("Apply"))
  local function widths(compact)
    local l = fh + 12 + 8 + (compact and ib or btn_w("Folder...")) + 8 + (compact and ib or btn_w("Rescan"))
    if T then l = l + 18 + (compact and ib * 2 + 4 or btn_w("Undo") + 4 + btn_w("Redo")) end
    local r = fh + 8 + (compact and ib or btn_w("Settings")) -- pin + Settings
    if T then r = r + apply_w + 8 + (compact and ib or btn_w("Refresh REAPER")) + 8 end
    return l, r
  end
  local l, r = widths(false)
  local compact = l + r + 280 + 24 > avail
  if compact then l, r = widths(true) end
  local combo_w = math.max(110, math.min(280, avail - l - r - 24))

  -- app mark
  ImGui.DrawList_AddRectFilled(dl, x0, y0, x0 + fh, y0 + fh, C_.accent, 6)
  local ms = fh * 0.62
  ImGui.DrawList_AddTextEx(dl, FONT, ms, x0 + (fh - text_w("T") * ms / ImGui.GetFontSize(ctx)) / 2, y0 + (fh - ms) / 2, C_.accent_txt, "T")
  ImGui.Dummy(ctx, fh, fh)
  tip("Theme Layout Modifier")
  ImGui.SameLine(ctx, 0, 12)
  ImGui.SetNextItemWidth(ctx, combo_w)
  local cur = T and T.meta.name or "Select a theme..."
  if ImGui.BeginCombo(ctx, "##theme", cur, ImGui.ComboFlags_HeightLarge) then
    for i, t in ipairs(S.themes) do
      local label = t.kind == "zip" and (t.name .. "   [zip]") or t.name
      if ImGui.Selectable(ctx, label .. "##" .. i, T and T.meta.file == t.file) then try_select_theme(i) end
    end
    if #S.themes == 0 then ImGui.TextDisabled(ctx, "No themes in this folder.") end
    ImGui.EndCombo(ctx)
  end
  if T then tip(T.meta.name) end
  ImGui.SameLine(ctx, 0, 8)
  if tool_button("Folder...", "folder", compact) then
    if reaper.JS_Dialog_BrowseForFolder then
      local rv, f = reaper.JS_Dialog_BrowseForFolder("ColorThemes folder", S.dir)
      if rv == 1 and f ~= "" then
        S.dir = f
        reaper.SetExtState(EXT, "dir", f, true)
        scan_themes()
      end
    else
      status("Install js_ReaScriptAPI (ReaPack) to choose another folder.", true)
    end
  end
  tip("Choose the ColorThemes folder\n" .. S.dir)
  ImGui.SameLine(ctx, 0, 8)
  if tool_button("Rescan", "search", compact) then scan_themes() end
  tip("Rescan the folder for themes")

  if T then
    ImGui.SameLine(ctx, 0, 18)
    if tool_button("Undo", "undo", compact, #S.undo > 0) then undo_redo(S.undo, S.redo) end
    tip(#S.undo > 0 and ("Undo (" .. #S.undo .. " steps)") or "Nothing to undo")
    ImGui.SameLine(ctx, 0, 4)
    if tool_button("Redo", "redo", compact, #S.redo > 0) then undo_redo(S.redo, S.undo) end
    tip(#S.redo > 0 and "Redo" or "Nothing to redo")
  end

  -- right-aligned group: [Apply]  [Refresh REAPER]  [pin]  [Settings]  (same row, never wraps)
  ImGui.SameLine(ctx)
  local rest = ImGui.GetContentRegionAvail(ctx)
  if rest > r then ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + rest - r) end
  if T then
    ImGui.BeginDisabled(ctx, not T.dirty)
    if accent_button("Apply", apply_w) then apply() end
    ImGui.EndDisabled(ctx)
    tip("Write the changes into rtconfig.txt" .. (S.backup and "\n(a backup is kept — see Settings)" or ""))
    local ax1, ay1 = ImGui.GetItemRectMin(ctx)
    local ax2, ay2 = ImGui.GetItemRectMax(ctx)
    S.apply_rect = { ax1, ay1, ax2, ay2 }
    ImGui.SameLine(ctx, 0, 8)
    if tool_button("Refresh REAPER", "refresh", compact) then refresh_reaper() end
    tip(T.dirty and "Reload the theme in REAPER\n(from disk — Apply first to see your current edits)" or "Reload this theme in REAPER")
    ImGui.SameLine(ctx, 0, 8)
  end
  G.pin(ctx, THEME_KEY)
  ImGui.SameLine(ctx, 0, 8)
  if tool_button("Settings", "gear", compact) then S.show_style = not S.show_style end
  tip("Settings: colors, text size, backup option")
  ImGui.Dummy(ctx, 0, 10)
end


-- "Unsaved changes" pill centered in the window's title bar
local function draw_title_status()
  if not (T and T.dirty) then return end
  local dl = ImGui.GetWindowDrawList(ctx)
  local wx, wy = ImGui.GetWindowPos(ctx)
  local ww = ImGui.GetWindowSize(ctx)
  local th = ImGui.GetFrameHeight(ctx)
  local txt = "Unsaved changes"
  local w = text_w(txt) * 0.85 + 14
  local h = ImGui.GetFontSize(ctx) * 0.85 + 5
  ImGui.DrawList_PushClipRect(dl, wx, wy, wx + ww, wy + th, false)
  pill(dl, wx + (ww - w) / 2, wy + (th - h) / 2, txt, C_.accent)
  ImGui.DrawList_PopClipRect(dl)
end

-- Apply feedback: a small note + Undo under the Apply button; stays 2 s, fades 3 s, hover resets
local function draw_toast()
  local t = S.toast
  if not t or not S.apply_rect then return end
  local now = reaper.time_precise()
  local el = now - t.t0
  if el > 5 then S.toast = nil return end
  local a = el < 2 and 1 or (1 - (el - 2) / 3)
  ImGui.SetNextWindowPos(ctx, S.apply_rect[3], S.apply_rect[4] + 8, ImGui.Cond_Always, 1, 0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha, a)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 10, 6)
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, with_alpha(ST.panel, 255))
  ImGui.PushStyleColor(ctx, ImGui.Col_Border, C_.accent)
  local flags = ImGui.WindowFlags_NoDecoration | ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoSavedSettings
    | ImGui.WindowFlags_NoFocusOnAppearing | ImGui.WindowFlags_NoNav | G.pin_flag(THEME_KEY)
  if ImGui.Begin(ctx, "##apply_toast", false, flags) then
    if ImGui.IsWindowHovered(ctx) then t.t0 = now end
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.TextColored(ctx, 0x5BC07AFF, "●")
    ImGui.SameLine(ctx)
    ImGui.Text(ctx, t.msg)
    ImGui.SameLine(ctx, 0, 12)
    if ImGui.SmallButton(ctx, "Undo") then
      write_file(t.path, t.prev)
      if t.bak then os.remove(t.bak) end
      T.dirty = true
      T.on_disk = t.on_disk
      S.toast = nil
      status("Apply undone — rtconfig.txt restored.")
    end
    tip("Put the previous rtconfig.txt back (your edits stay in the editor)")
    ImGui.End(ctx)
  end
  ImGui.PopStyleColor(ctx, 2)
  ImGui.PopStyleVar(ctx, 2)
end

----------------------------------------------------------------------------------------------------
-- Main page: layout cards
----------------------------------------------------------------------------------------------------
local function open_editor(name)
  S.sel_layout, S.page, S.sel_elem, S.center_view = name, "edit", nil, true
end

local function card_pills(dl, name, bx, by)
  local n = count_edits(name)
  if n > 0 then bx = bx + pill(dl, bx, by, n .. " edited", C_.accent) + 6 end
  local dir = imgdir_of(name)
  if dir then bx = bx + pill(dl, bx, by, "images: " .. dir, C_.dim) + 6 end
  if name ~= "" and not W.can_edit_blocks(T.C, name, S.sec) then bx = bx + pill(dl, bx, by, "macro · view only", C_.dim) + 6 end
  if name == "" then bx = bx + pill(dl, bx, by, "global", C_.link) + 6 end
  return bx
end

-- card zoom on the layout page, kept per section
local function card_zoom()
  P.czoom = P.czoom or {}
  if not P.czoom[S.sec] then P.czoom[S.sec] = tonumber(reaper.GetExtState(EXT, "card_zoom_" .. S.sec)) or 1 end
  return P.czoom[S.sec]
end

local function arrow_button(id, x, y, size, dir, enabled)
  ImGui.SetCursorScreenPos(ctx, x - size / 2, y - size / 2)
  local clicked = ImGui.InvisibleButton(ctx, id, size, size) and enabled
  local hov = ImGui.IsItemHovered(ctx) and enabled
  local col = not enabled and with_alpha(C_.text, 0x30) or hov and C_.accent_hi or C_.accent
  local dl = ImGui.GetWindowDrawList(ctx)
  local r = size * 0.42
  if dir == "l" then ImGui.DrawList_AddTriangleFilled(dl, x - r, y, x + r * 0.7, y - r, x + r * 0.7, y + r, col)
  elseif dir == "r" then ImGui.DrawList_AddTriangleFilled(dl, x + r, y, x - r * 0.7, y - r, x - r * 0.7, y + r, col)
  elseif dir == "u" then ImGui.DrawList_AddTriangleFilled(dl, x, y - r, x - r, y + r * 0.7, x + r, y + r * 0.7, col)
  else ImGui.DrawList_AddTriangleFilled(dl, x, y + r, x - r, y - r * 0.7, x + r, y - r * 0.7, col) end
  return clicked
end

-- stacked cards: the selected layout in front, neighbours peeking out behind it.
-- MCP strips fan out sideways; TCP panels (wide) fan out up/down.
local function draw_carousel(layouts)
  local aw, ah = ImGui.GetContentRegionAvail(ctx)
  local x0, y0 = ImGui.GetCursorScreenPos(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  local fs = ImGui.GetFontSize(ctx)
  local vertical = not S.sec:find("mcp")
  local n = #layouts
  local sel = 1
  for i, nm in ipairs(layouts) do if nm == S.sel_layout then sel = i end end
  S.car_pos = S.car_pos or sel
  S.car_pos = S.car_pos + (sel - S.car_pos) * 0.25 -- slide animation
  if math.abs(sel - S.car_pos) < 0.01 then S.car_pos = sel end

  local AR = 30
  local DEPTH = math.max(1, math.min(6, n - 1)) -- cards shown on each side
  local footer = fs * 2 + 34
  local ax1, ay1, ax2, ay2 = x0 + 8, y0 + 8, x0 + aw - 8, y0 + ah - footer
  if vertical then ax2 = ax2 - AR - 16 else ay2 = ay2 - AR - 6 end
  local pad = 14
  local span = vertical and (ay2 - ay1) or (ax2 - ax1) -- along the fan direction
  local min_room = math.min(DEPTH * 22, span * 0.3)   -- keep space for the stack on each side
  local cw_max = (ax2 - ax1) - (vertical and 0 or 2 * min_room)
  local ch_max = (ay2 - ay1) - (vertical and 2 * min_room or 0)
  local sc = math.max(0.1, math.min(card_zoom(), (cw_max - 2 * pad) / P.W, (ch_max - 2 * pad) / P.H))
  local cw, chh = P.W * sc + 2 * pad, P.H * sc + 2 * pad
  local cx, cy = (ax1 + ax2) / 2, (ay1 + ay2) / 2
  -- spread the stack over the free space on each side of the front card
  local room = ((vertical and (ay2 - ay1 - chh) or (ax2 - ax1 - cw)) / 2) - 6
  local PEEK = math.max(10, math.min(60, room / DEPTH))

  local items = {}
  for i = 1, n do
    local d = i - S.car_pos
    if math.abs(d) <= DEPTH + 0.99 then items[#items + 1] = { i = i, d = d } end
  end
  table.sort(items, function(p, q) return math.abs(p.d) > math.abs(q.d) end)
  local rects = {}
  for _, it in ipairs(items) do
    local ad = math.min(math.abs(it.d), DEPTH + 1)
    local sgn = it.d < 0 and -1 or 1
    local k = 1 - 0.05 * ad
    local w, h, ox, oy = cw, chh, 0, 0
    if vertical then w, oy = cw * k, sgn * PEEK * ad else h, ox = chh * k, sgn * PEEK * ad end
    local x1, y1 = cx + ox - w / 2, cy + oy - h / 2
    local x2, y2 = x1 + w, y1 + h
    local front = math.abs(it.d) < 0.5
    local op = front and 1 or (1 - 0.75 * math.min(1, ad / DEPTH))
    ImGui.DrawList_AddRectFilled(dl, x1 + 3, y1 + 6, x2 + 3, y2 + 6, with_alpha(0x000000FF, 0x40 * op), 10) -- shadow
    ImGui.DrawList_AddRectFilled(dl, x1, y1, x2, y2, C_.child, 10)
    ImGui.DrawList_PushClipRect(dl, x1 + 2, y1 + 2, x2 - 2, y2 - 2, true)
    ImGui.DrawList_AddRectFilled(dl, cx - cw / 2 + pad - 6, cy + oy - chh / 2 + pad - 6, cx + cw / 2 - pad + 6, cy + oy + chh / 2 - pad + 6, C_.canvas, 6)
    render_panel(dl, layouts[it.i], cx + ox - P.W * sc / 2, cy + oy - P.H * sc / 2, sc)
    ImGui.DrawList_PopClipRect(dl)
    if not front then -- farther = more transparent (fades into the background), never below 25% opacity
      ImGui.DrawList_AddRectFilled(dl, x1 - 1, y1 - 1, x2 + 1, y2 + 1, with_alpha(C_.child, (1 - op) * 255), 10)
    end
    ImGui.DrawList_AddRect(dl, x1, y1, x2, y2, front and C_.accent or C_.border, 10, 0, front and 2 or 1)
    rects[#rects + 1] = { i = it.i, x1, y1, x2, y2 }
  end

  -- interaction: click a side card to bring it forward, double-click the front card to edit, wheel to browse
  ImGui.SetCursorScreenPos(ctx, x0, y0)
  -- (stops before the arrow column so ▲ ▼ get their clicks)
  ImGui.InvisibleButton(ctx, "##stack", math.max(1, (vertical and ax2 + 4 or x0 + aw) - x0), math.max(1, ay2 - y0))
  local hovered = ImGui.IsItemHovered(ctx)
  local mx, my = ImGui.GetMousePos(ctx)
  local target
  if hovered then
    for k = #rects, 1, -1 do
      local r = rects[k]
      if mx >= r[1] and mx <= r[3] and my >= r[2] and my <= r[4] then target = r.i; break end
    end
    if target == sel then ImGui.SetTooltip(ctx, "Double-click to edit") end
  end
  if hovered and ImGui.IsMouseClicked(ctx, 0) and target and target ~= sel then sel = target end
  if hovered and ImGui.IsMouseDoubleClicked(ctx, 0) and target == sel then open_editor(layouts[sel]) end
  local wheel = hovered and ImGui.GetMouseWheel(ctx) or 0
  if wheel ~= 0 then sel = math.max(1, math.min(n, sel + (wheel > 0 and -1 or 1))) end

  -- arrows
  if vertical then
    local axc = ax2 + 8 + AR / 2
    if arrow_button("##up", axc, cy - AR, AR, "u", sel > 1) then sel = sel - 1 end
    if arrow_button("##down", axc, cy + AR, AR, "d", sel < n) then sel = sel + 1 end
  else
    local ayc = ay2 + 6 + AR / 2
    if arrow_button("##prev", cx - cw / 2 + AR / 2, ayc, AR, "l", sel > 1) then sel = sel - 1 end
    if arrow_button("##next", cx + cw / 2 - AR / 2, ayc, AR, "r", sel < n) then sel = sel + 1 end
    local cnt = ("%d / %d"):format(sel, n)
    ImGui.DrawList_AddText(dl, cx - text_w(cnt) / 2, ayc - fs / 2, C_.dim, cnt)
  end

  -- footer: name, pills and position
  local name = layouts[sel]
  local fy = y0 + ah - footer + 6
  local title = layout_label(name)
  ImGui.DrawList_AddTextEx(dl, FONT, fs + 3, cx - text_w(title) * (fs + 3) / fs / 2, fy, C_.text, title)
  local pw = card_pills(dl, name, 0, -1000) -- measure
  card_pills(dl, name, cx - pw / 2, fy + fs + 10)
  if vertical then
    local cnt = ("%d / %d"):format(sel, n)
    ImGui.DrawList_AddText(dl, ax2 + 8 + AR / 2 - text_w(cnt) / 2, cy - fs / 2, C_.dim, cnt)
  end
  S.sel_layout = name
  ImGui.SetCursorScreenPos(ctx, x0, y0 + ah - 1)
  ImGui.Dummy(ctx, 1, 1)
end

local function draw_main()
  local layouts = layout_list()
  local found = false
  for _, n in ipairs(layouts) do if n == S.sel_layout then found = true end end
  if not found then S.sel_layout = layouts[1] end
  local sel = S.sel_layout
  local editable = sel ~= nil and (sel == "" or W.can_edit_blocks(T.C, sel, S.sec))
  local dl = ImGui.GetWindowDrawList(ctx)
  local fh = ImGui.GetFrameHeight(ctx)

  -- tabs: TCP / MCP / Master
  for i, tb in ipairs(TABS) do
    if i > 1 then ImGui.SameLine(ctx, 0, 4) end
    local names, active = {}, false
    for _, id in ipairs(tb.ids) do
      if id == S.sec then active = true end
      for _, nm in ipairs(T.C.layouts[id] or {}) do names[nm] = true end
      for k in pairs(T.R.G.vars) do -- count the global layout too (same as the list below)
        if W.sec_of(k) == id and k ~= id .. ".size" then names[""] = true; break end
      end
    end
    local n = 0
    for _ in pairs(names) do n = n + 1 end
    local label = ("%s  %d##tab%d"):format(tb.label, n, i)
    if active then accent_button(label)
    elseif ImGui.Button(ctx, label) then switch_section(tb.sub and (S.master_sub or tb.ids[1]) or tb.ids[1]) end
    tip(("%s — %d layouts in this theme"):format(tb.label, n))
  end
  ImGui.Dummy(ctx, 0, 4)

  -- title row
  ImGui.PushFont(ctx, FONT, ST.font + 4)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.TextColored(ctx, C_.title, (S.sec:find("^master") and "Master" or SC().label) .. " Layouts")
  ImGui.PopFont(ctx)
  if S.sec:find("^master") then -- master holds both panels: pick which one to look at
    for k, id in ipairs({ "master.tcp", "master.mcp" }) do
      local lb = TABS[3].sub[k]
      flow(btn_w(lb), k == 1 and 14 or 2)
      if id == S.sec then accent_button(lb) elseif ImGui.Button(ctx, lb) then switch_section(id) end
    end
  end
  ImGui.SameLine(ctx, 0, 10)
  local cx, cy = ImGui.GetCursorScreenPos(ctx)
  local pw = pill(dl, cx, cy + (fh - (ImGui.GetFontSize(ctx) * 0.85 + 5)) / 2, tostring(#layouts), C_.dim)
  ImGui.Dummy(ctx, pw, fh)

  local sp = 6
  local zw = math.max(120, btn_w("Zoom 0.00x"))
  local total = zw + 14 + btn_w("New") + btn_w("Duplicate") + btn_w("Rename") + btn_w("Delete") + 70 + sp * 4 + 12
  right_align(total)
  ImGui.SetNextItemWidth(ctx, zw)
  local zc, zv = ImGui.SliderDouble(ctx, "##cardzoom", card_zoom(), 0.25, 3, "Zoom %.2fx")
  if zc then P.czoom[S.sec] = zv; reaper.SetExtState(EXT, "card_zoom_" .. S.sec, tostring(zv), true) end
  tip("Card size: zoom out for an overview, zoom in for detail.\nWhen only one card fits, the cards stack up — click, scroll or use the arrows to browse.")
  ImGui.SameLine(ctx, 0, 14)
  if ImGui.Button(ctx, "New") then open_popup("Layout name", { mode = "new", name = "New layout" }) end
  tip("Add an empty layout (it starts as a copy of the global layout)")
  ImGui.SameLine(ctx, 0, sp)
  ImGui.BeginDisabled(ctx, sel == nil or sel == "" or not editable)
  if ImGui.Button(ctx, "Duplicate") then open_popup("Layout name", { mode = "dup", src = sel, name = sel .. " copy" }) end
  ImGui.SameLine(ctx, 0, sp)
  if ImGui.Button(ctx, "Rename") then open_popup("Layout name", { mode = "rename", src = sel, name = sel }) end
  ImGui.SameLine(ctx, 0, sp)
  if danger_button("Delete") then open_popup("Delete layout", { name = sel }) end
  ImGui.EndDisabled(ctx)
  ImGui.SameLine(ctx, 0, sp + 12)
  ImGui.BeginDisabled(ctx, sel == nil)
  if accent_button("Edit", 70) then open_editor(sel) end
  ImGui.EndDisabled(ctx)

  local hint = "Click a card to select it · double-click to edit · zoom slider changes card size"
  if sel == "" then hint = "The global layout can be edited, but not duplicated, renamed or deleted"
  elseif sel and not editable then hint = "This layout is generated by a macro — view only" end
  ImGui.PushTextWrapPos(ctx, 0)
  ImGui.TextDisabled(ctx, hint)
  ImGui.PopTextWrapPos(ctx)
  ImGui.Dummy(ctx, 0, 2)

  if #layouts == 0 then
    ImGui.Spacing(ctx)
    ImGui.PushTextWrapPos(ctx, 0)
    ImGui.TextDisabled(ctx, ("This theme has no %s layout code (WALTER) in its rtconfig.txt."):format(SC().label))
    ImGui.PopTextWrapPos(ctx)
    return
  end

  if ImGui.BeginChild(ctx, "cards", 0, -status_h()) then
    local aw, ah = ImGui.GetContentRegionAvail(ctx)
    local fs = ImGui.GetFontSize(ctx)
    local gap = 12
    local zoom = card_zoom()
    local footer = fs * 2 + 46
    local want_w = P.W * zoom + 44
    local want_h = P.H * zoom + 16 + footer + 14
    local per_row = math.max(1, math.floor((aw + gap) / (want_w + gap)))
    if #layouts > 1 and (per_row == 1 or want_h > ah) then
      draw_carousel(layouts)
    else
      local sc = zoom
      local card_w = math.max(220, math.floor(P.W * sc + 44))
      if card_w > aw then sc = (aw - 44) / P.W; card_w = aw end
      local hover_now
      for i, name in ipairs(layouts) do
        if (i - 1) % per_row ~= 0 then ImGui.SameLine(ctx, 0, gap) end
        ImGui.PushID(ctx, i)
        local is_sel, hov = S.sel_layout == name, S.hover_card == name
        local well_h = P.H * sc + 16
        ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, hov and with_alpha(C_.frame, 0xFF) or C_.child)
        ImGui.PushStyleColor(ctx, ImGui.Col_Border, is_sel and C_.accent or hov and C_.frame_act or C_.border)
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_ChildBorderSize, is_sel and 2 or 1)
        if ImGui.BeginChild(ctx, "card", card_w, well_h + footer, ImGui.ChildFlags_Borders, ImGui.WindowFlags_NoScrollbar) then
          local cdl = ImGui.GetWindowDrawList(ctx)
          local x, y = ImGui.GetCursorScreenPos(ctx)
          local iw, ih = ImGui.GetContentRegionAvail(ctx)
          if ImGui.InvisibleButton(ctx, "pick", math.max(1, iw), math.max(1, ih)) then S.sel_layout = name end
          if ImGui.IsItemHovered(ctx) then
            hover_now = name
            if ImGui.IsMouseDoubleClicked(ctx, 0) then open_editor(name) end
          end
          ImGui.DrawList_AddRectFilled(cdl, x, y, x + iw, y + well_h, C_.canvas, 6)
          render_panel(cdl, name, x + math.max(8, (iw - P.W * sc) / 2), y + 8, sc)
          local ty = y + well_h + 10
          ImGui.DrawList_AddText(cdl, x + 2, ty, is_sel and C_.accent or C_.text, layout_label(name))
          card_pills(cdl, name, x + 2, ty + fs + 8)
          ImGui.EndChild(ctx)
        end
        ImGui.PopStyleVar(ctx)
        ImGui.PopStyleColor(ctx, 2)
        ImGui.PopID(ctx)
      end
      S.hover_card = hover_now
    end
    ImGui.EndChild(ctx)
  end
end

----------------------------------------------------------------------------------------------------
-- Edit page
----------------------------------------------------------------------------------------------------
local HEIGHT_NAMES = {
  { "Super-collapsed", "Child tracks inside a fully collapsed folder." },
  { "Collapsed", "Child tracks inside a collapsed folder." },
  { "Small", "Smallest normal height (track not rec-armed)." },
  { "Rec-arm", "Smallest height while the track is rec-armed." },
}

local function hit(rects, mx, my)
  local best, area
  for _, r in ipairs(rects) do
    if mx >= r.l and mx < r.r and my >= r.t and my < r.b then
      local a = (r.r - r.l) * (r.b - r.t)
      if not area or a < area then best, area = r, a end
    end
  end
  return best
end

local function draw_preview_controls()
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 10, 6)
  local open = ImGui.BeginChild(ctx, "preview_bar", 0, 0, ImGui.ChildFlags_Borders | ImGui.ChildFlags_AutoResizeY, ImGui.WindowFlags_NoScrollbar)
  ImGui.PopStyleVar(ctx)
  if not open then return end
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.TextColored(ctx, C_.accent, "PREVIEW")
  flow(btn_w("Reset size"), 12)
  if ImGui.SmallButton(ctx, "Reset size") then reset_view() end
  tip("Back to the theme's base size (" .. S.sec .. ".size).\n" .. (S.sec:find("mcp")
    and "Resize the preview by dragging the strip's top or bottom edge\n(REAPER fixes the mixer strip width)."
    or "Resize the preview by dragging the panel's top, right or bottom edge\n(or the top-right / bottom-left corner)."))
  local hs = S.sec == "tcp" and T.C.cfg.tcp_heights
  if hs then
    for i = 1, math.min(4, #hs) do
      local hv = tonumber(hs[i])
      if hv and hv > 0 then
        flow(btn_w(("%s %d"):format(HEIGHT_NAMES[i][1], hv)), 4)
        if ImGui.SmallButton(ctx, ("%s %d##h%d"):format(HEIGHT_NAMES[i][1], hv, i)) then P.H = hv; T.dirty_eval = true end
        tip(("%s height: %d px\n%s\n\nFrom this theme's tcp_heights setting. Click to preview the panel at this height."):format(HEIGHT_NAMES[i][1], hv, HEIGHT_NAMES[i][2]))
      end
    end
  end
  flow(check_w("Rec-armed"), 16)
  local ch, v = ImGui.Checkbox(ctx, "Rec-armed", P.recarm)
  if ch then P.recarm = v; T.dirty_eval = true end
  tip("Preview the track as record-armed.\nMany themes show the input selector or change colors when armed,\nand 'Only when rec-armed' rules react to this.")
  flow(check_w("Selected"))
  ch, v = ImGui.Checkbox(ctx, "Selected", P.selected)
  if ch then P.selected = v; T.dirty_eval = true end
  tip("Preview the track as selected (selected background / colors).\n'Only when selected' rules react to this.\nCan be combined with Rec-armed, just like in REAPER.")
  flow(check_w("Folder"))
  ch, v = ImGui.Checkbox(ctx, "Folder", P.folder)
  if ch then P.folder = v; T.dirty_eval = true end
  tip("Preview the track as a folder parent (shows the folder button).")
  local pm_w = math.max(110, btn_w("Stereo pan") + ImGui.GetFrameHeight(ctx)) -- text + combo arrow
  flow(pm_w + 6 + text_w("Pan mode"))
  ImGui.SetNextItemWidth(ctx, pm_w)
  local modes = { [0] = "Classic", [3] = "Balance", [5] = "Stereo pan", [6] = "Dual pan" }
  if ImGui.BeginCombo(ctx, "Pan mode", modes[P.panmode] or "?") then
    for _, m in ipairs({ 0, 3, 5, 6 }) do
      if ImGui.Selectable(ctx, modes[m], P.panmode == m) then P.panmode = m; T.dirty_eval = true end
    end
    ImGui.EndCombo(ctx)
  end
  tip("Some themes show a width knob or two pan knobs depending on the track's pan mode.")

  if #T.C.param_order > 0 then
    if ImGui.TreeNode(ctx, ("Theme parameters (%d)"):format(#T.C.param_order)) then
      ImGui.TextDisabled(ctx, "Preview only — these come from the theme's define_parameter lines.")
      for _, name in ipairs(T.C.param_order) do
        local p = T.C.params[name]
        ImGui.SetNextItemWidth(ctx, 160)
        local cur = P.params[name] or p.def
        local c2, nv = ImGui.SliderInt(ctx, p.desc .. "##" .. name, math.floor(cur), math.floor(p.min), math.floor(math.max(p.max, p.min + 1)))
        if c2 then P.params[name] = nv; T.dirty_eval = true end
      end
      ImGui.TreePop(ctx)
    end
  end
  ImGui.EndChild(ctx)
end

local CURSOR = { l = "ResizeEW", r = "ResizeEW", t = "ResizeNS", b = "ResizeNS", lt = "ResizeNWSE", rb = "ResizeNWSE",
  rt = "ResizeNESW", lb = "ResizeNESW", move = "ResizeAll" }

local function set_cursor(mode)
  local c = mode and CURSOR[mode]
  if c then ImGui.SetMouseCursor(ctx, ImGui["MouseCursor_" .. c]) end
end

-- edge/corner of the selected element under the mouse
local function elem_handle(r, mx, my)
  local E = math.max(2, math.min(5, (r.r - r.l) / 4, (r.b - r.t) / 4))
  if mx < r.l - E or mx > r.r + E or my < r.t - E or my > r.b + E then return nil end
  local hx = math.abs(mx - r.l) <= E and "l" or math.abs(mx - r.r) <= E and "r" or ""
  local hy = math.abs(my - r.t) <= E and "t" or math.abs(my - r.b) <= E and "b" or ""
  local h = hx .. hy
  return h ~= "" and h or nil
end

-- panel frame: top, right, bottom edges + top-right and bottom-left corners
local function frame_handle(px, py, px2, py2, mx, my)
  local E = 5
  if S.sec:find("mcp") then -- mixer strips: REAPER fixes the width, so only the height can be previewed
    if mx < px or mx > px2 then return nil end
    if math.abs(my - py) <= E then return "t" end
    if math.abs(my - py2) <= E then return "b" end
    return nil
  end
  if math.abs(mx - px2) <= E + 2 and math.abs(my - py) <= E + 2 then return "rt" end
  if math.abs(mx - px) <= E + 2 and math.abs(my - py2) <= E + 2 then return "lb" end
  if math.abs(my - py) <= E and mx >= px and mx <= px2 then return "t" end
  if math.abs(my - py2) <= E and mx >= px and mx <= px2 then return "b" end
  if math.abs(mx - px2) <= E and my >= py and my <= py2 then return "r" end
end

-- d.done = total x/y/w/h change applied since the drag started; keep_ratio (Shift) keeps the start aspect
local function drag_element(name, d, mx, my, z, keep_ratio)
  local tx = math.floor((mx - d.sx) / z + 0.5)
  local ty = math.floor((my - d.sy) / z + 0.5)
  local m = d.mode
  local X, Y, Wd, Hd = 0, 0, 0, 0
  if m == "move" then
    X, Y = tx, ty
  else
    if m:find("l") then Wd = -tx elseif m:find("r") then Wd = tx end
    if m:find("t") then Hd = -ty elseif m:find("b") then Hd = ty end
    if keep_ratio and d.w0 > 0 and d.h0 > 0 then
      local horiz, vert = m:find("[lr]") ~= nil, m:find("[tb]") ~= nil
      local kw, kh = (d.w0 + Wd) / d.w0, (d.h0 + Hd) / d.h0
      local k = horiz and vert and (math.abs(kw - 1) >= math.abs(kh - 1) and kw or kh) or (horiz and kw or kh)
      Wd, Hd = math.floor(d.w0 * k + 0.5) - d.w0, math.floor(d.h0 * k + 0.5) - d.h0
    end
    if m:find("l") then X = -Wd end
    if m:find("t") then Y = -Hd end
  end
  d.snap_x, d.snap_y = nil, nil
  if S.snap and d.xs and not keep_ratio then
    local th = 6 / z -- 6 screen px
    local nl, nt = d.l0 + X, d.t0 + Y
    local nr, nb = nl + d.w0 + Wd, nt + d.h0 + Hd
    local function near(list, ...) -- closest snap among the given edges: rounded delta, snapped line
      local bd, bl
      for _, v in ipairs({ ... }) do
        for _, g in ipairs(list) do
          local dd = g - v
          if math.abs(dd) <= th and (not bd or math.abs(dd) < math.abs(bd)) then bd, bl = dd, g end
        end
      end
      if bd then return math.floor(bd + 0.5), bl end
    end
    local dx, gx, dy, gy
    if m == "move" then
      dx, gx = near(d.xs, nl, nr)
      dy, gy = near(d.ys, nt, nb)
      X, Y = X + (dx or 0), Y + (dy or 0)
    else
      if m:find("l") then dx, gx = near(d.xs, nl); if dx then X, Wd = X + dx, Wd - dx end
      elseif m:find("r") then dx, gx = near(d.xs, nr); if dx then Wd = Wd + dx end end
      if m:find("t") then dy, gy = near(d.ys, nt); if dy then Y, Hd = Y + dy, Hd - dy end
      elseif m:find("b") then dy, gy = near(d.ys, nb); if dy then Hd = Hd + dy end end
    end
    d.snap_x, d.snap_y = gx, gy
  end
  if d.w0 + Wd < 2 or d.h0 + Hd < 2 then return end
  local a = d.done
  local dx, dy, dw, dh = X - a[1], Y - a[2], Wd - a[3], Hd - a[4]
  if dx == 0 and dy == 0 and dw == 0 and dh == 0 then return end
  if not d.snapped then snapshot(); d.snapped = true end
  move_elem(name, d.e, dx, dy, dw, dh)
  d.done = { X, Y, Wd, Hd }
end

local function drag_frame(d, mx, my, z)
  local dx, dy = (mx - d.sx) / z, (my - d.sy) / z
  local m = d.mode
  local Wn, Hn = d.W0, d.H0
  if m:find("r") then Wn = d.W0 + dx end
  if m:find("l") then Wn = d.W0 - dx end
  if m:find("b") then Hn = d.H0 + dy end
  if m:find("t") then Hn = d.H0 - dy end
  Wn = math.max(40, math.min(2000, math.floor(Wn + 0.5)))
  Hn = math.max(8, math.min(2000, math.floor(Hn + 0.5))) -- MCP strips can be ~900 px tall
  if m:find("l") then P.org_x = math.max(8, d.ox0 + (d.W0 - Wn) * z) end
  if m:find("t") then P.org_y = math.max(8, d.oy0 + (d.H0 - Hn) * z) end
  if Wn ~= P.W or Hn ~= P.H then P.W, P.H = Wn, Hn; T.dirty_eval = true end
end

-- faint pixel grid aligned to the panel origin (minor = 10 px, major = 50 px)
local function draw_grid(dl, x1, y1, x2, y2, px, py, z)
  local minor, major = with_alpha(C_.text, 0x07), with_alpha(C_.text, 0x12)
  local unit = 10 * z >= 8 and 10 or 50
  local step = unit * z
  local x = px + math.floor((x1 - px) / step) * step
  while x <= x2 do
    local u = math.floor((x - px) / z + 0.5)
    ImGui.DrawList_AddLine(dl, x, y1, x, y2, u % 50 == 0 and major or minor)
    x = x + step
  end
  local y = py + math.floor((y1 - py) / step) * step
  while y <= y2 do
    local u = math.floor((y - py) / z + 0.5)
    ImGui.DrawList_AddLine(dl, x1, y, x2, y, u % 50 == 0 and major or minor)
    y = y + step
  end
end

-- pixel rulers along the panel's top and left edges
local function draw_rulers(dl, px, py, z, bottom)
  local col = with_alpha(C_.text, 0x60)
  local fs = math.max(9, ST.font - 3)
  local lab = 50 * z >= 36 and 50 or 100
  local fsz = ImGui.GetFontSize(ctx)
  local py2 = py + P.H * z
  for u = 0, P.W, 10 do
    if u % 50 == 0 or 10 * z >= 5 then
      local x = px + u * z
      local len = u % 50 == 0 and 7 or 3
      if bottom then
        ImGui.DrawList_AddLine(dl, x, py2 + 3, x, py2 + 3 + len, col)
        if u % lab == 0 then ImGui.DrawList_AddTextEx(dl, FONT, fs, x + 2, py2 + 12, col, tostring(u)) end
      else
        ImGui.DrawList_AddLine(dl, x, py - 3 - len, x, py - 3, col)
        if u % lab == 0 then ImGui.DrawList_AddTextEx(dl, FONT, fs, x + 2, py - 12 - fs, col, tostring(u)) end
      end
    end
  end
  for v = 0, P.H, 10 do
    if v % 50 == 0 or 10 * z >= 5 then
      local y = bottom and (py2 - v * z) or (py + v * z)
      local len = v % 50 == 0 and 7 or 3
      ImGui.DrawList_AddLine(dl, px - 3 - len, y, px - 3, y, col)
      if v % lab == 0 then
        local t = tostring(v)
        ImGui.DrawList_AddTextEx(dl, FONT, fs, px - 14 - text_w(t) * fs / fsz, bottom and (y - fs - 1) or (y + 1), col, t)
      end
    end
  end
end

local function draw_canvas(name, L, insp_h)
  if not ImGui.BeginChild(ctx, "canvas", 0, -(insp_h + 7), ImGui.ChildFlags_Borders, ImGui.WindowFlags_HorizontalScrollbar) then return end
  local dl = ImGui.GetWindowDrawList(ctx)
  local aw, ah = ImGui.GetContentRegionAvail(ctx)
  local ox, oy = ImGui.GetCursorScreenPos(ctx)

  -- canvas toolbar, top-right of the visible work area: Snap/Free · Guides · Hints · zoom.
  -- Submitted after the canvas so it draws on top.
  local zoom_rect
  local function draw_zoom()
    local fh = ImGui.GetFrameHeight(ctx)
    local zr = zoom_rect
    ImGui.DrawList_AddRectFilled(ImGui.GetWindowDrawList(ctx), zr[1] - 6, zr[2] - 4, zr[3] + 6, zr[4] + 4, with_alpha(C_.canvas, 0xE0), 6)
    ImGui.SetCursorScreenPos(ctx, zr[1], zr[2])
    local function save(k, v) reaper.SetExtState(EXT, k, v and "1" or "0", true) end
    if (S.snap and accent_button("Snap##snap", zr.snap_w) or not S.snap and ImGui.Button(ctx, "Free##snap", zr.snap_w, 0)) then
      S.snap = not S.snap; save("snap", S.snap)
    end
    tip(S.snap and "Snap: dragged edges stick to nearby element / panel edges.\nClick for free movement." or "Free movement.\nClick to snap dragged edges to nearby element / panel edges.")
    ImGui.SameLine(ctx, 0, 12)
    local ch, v = ImGui.Checkbox(ctx, "Guides", S.guides)
    if ch then S.guides = v; save("guides", v) end
    tip("Show guide lines while dragging an element (solid line = snapped edge).")
    ImGui.SameLine(ctx, 0, 12)
    ch, v = ImGui.Checkbox(ctx, "Hints", S.hints)
    if ch then S.hints = v; save("hints", v) end
    tip("Show the mouse / keyboard hints in the bottom-right corner.")
    ImGui.SameLine(ctx, 0, 16)
    local pct = ("%d%%"):format(math.floor(P.zoom * 100 + 0.5))
    local mid_w = zoom_rect.mid_w
    local function set_zoom(v)
      P.zoom = math.max(0.5, math.min(6, math.floor(v * 10 + 0.5) / 10)) -- 10% steps
      S.center_view = true
      reaper.SetExtState(EXT, "zoom", tostring(P.zoom), true)
    end
    if ImGui.Button(ctx, "-##zoomout", fh, fh) then set_zoom(P.zoom - 0.1) end
    tip("Zoom out")
    ImGui.SameLine(ctx, 0, 4)
    if ImGui.Button(ctx, pct .. "##zoomreset", mid_w, fh) then set_zoom(1) end
    tip("Back to 100%  (Ctrl/Cmd + wheel also zooms)")
    ImGui.SameLine(ctx, 0, 4)
    if ImGui.Button(ctx, "+##zoomin", fh, fh) then set_zoom(P.zoom + 0.1) end
    tip("Zoom in")
  end
  do
    local cwx, cwy = ImGui.GetWindowPos(ctx)
    local cww = ImGui.GetWindowSize(ctx)
    local fh = ImGui.GetFrameHeight(ctx)
    local mid_w = text_w("600%") + 16
    local snap_w = math.max(btn_w("Snap"), btn_w("Free"))
    local zw = snap_w + 12 + check_w("Guides") + 12 + check_w("Hints") + 16 + fh * 2 + mid_w + 8
    local zx = cwx + cww - 22 - zw
    zoom_rect = { zx, cwy + 10, zx + zw, cwy + 10 + fh, mid_w = mid_w, snap_w = snap_w }
  end
  local z = P.zoom

  -- content extent: panel + anything placed outside it
  local maxx, maxy = P.W, P.H
  for _, e in ipairs(elem_list()) do
    local _, _, r, b = erect(L, e)
    if r then maxx, maxy = math.max(maxx, r), math.max(maxy, b) end
  end
  if S.center_view then -- start with the panel vertically centered
    P.org_y = math.max(PAD, math.floor((ah - P.H * z) / 2))
    S.center_view = false
  end
  local cw = math.max(aw, P.org_x + maxx * z + PAD)
  local chh = math.max(ah, P.org_y + maxy * z + PAD)
  ImGui.SetNextItemAllowOverlap(ctx) -- the zoom buttons are submitted later, on top
  ImGui.InvisibleButton(ctx, "##canvas", cw, chh)
  local hovered = ImGui.IsItemHovered(ctx)
  do
    local mx0, my0 = ImGui.GetMousePos(ctx)
    local zr = zoom_rect
    if mx0 >= zr[1] - 4 and mx0 <= zr[3] + 4 and my0 >= zr[2] - 4 and my0 <= zr[4] + 4 then hovered = false end
  end
  local px, py = ox + P.org_x, oy + P.org_y
  local px2, py2 = px + P.W * z, py + P.H * z

  ImGui.DrawList_AddRectFilled(dl, ox, oy, ox + cw, oy + chh, C_.canvas)
  local strip = S.sec:find("mcp") ~= nil -- mixer strips: origin bottom-left
  draw_grid(dl, ox, oy, ox + cw, oy + chh, px, strip and py2 or py, z)
  for i = 1, 5 do -- soft drop shadow
    local g = i * 2
    ImGui.DrawList_AddRectFilled(dl, px - g, py - g + 4, px2 + g, py2 + g + 4, 0x00000012, 4 + g)
  end
  local bw, bh = base_size(L)
  local rects = render_panel(dl, name, px, py, z, { ox, oy, ox + cw, oy + chh })
  draw_rulers(dl, px, py, z, strip)
  if bw ~= P.W or bh ~= P.H then
    ImGui.DrawList_AddRect(dl, px, py, px + bw * z, py + bh * z, 0xFFFFFF22, 0, 0, 1)
  end

  -- links
  local recs = recs_of(name) or {}
  local byname = {}
  for _, r in ipairs(rects) do byname[r.e] = r end
  for e, r in pairs(recs) do
    if r.mode == "link" and not r.hide and byname[e] and byname[r.link] then
      local a, b = byname[r.link], byname[e]
      ImGui.DrawList_AddLine(dl, (a.l + a.r) / 2, (a.t + a.b) / 2, (b.l + b.r) / 2, (b.t + b.b) / 2, C_.link, 1.5)
      ImGui.DrawList_AddCircleFilled(dl, (a.l + a.r) / 2, (a.t + a.b) / 2, 3, C_.link)
    end
  end

  local mx, my = ImGui.GetMousePos(ctx)
  local sr = S.sel_elem and byname[S.sel_elem]
  local eh = hovered and sr and elem_handle(sr, mx, my) or nil
  local fh = hovered and not eh and frame_handle(px, py, px2, py2, mx, my) or nil
  local h = hovered and not eh and not fh and hit(rects, mx, my) or nil

  -- panel frame + its handles
  local active = fh or (S.drag and S.drag.kind == "frame")
  local fcol = active and C_.accent or with_alpha(C_.text, 0x50)
  ImGui.DrawList_AddRect(dl, px - 1, py - 1, px2 + 1, py2 + 1, fcol, 0, 0, active and 2 or 1)
  local fixed_w = strip -- MCP: no width handles
  for _, p in ipairs(fixed_w and {} or { { px2, py }, { px, py2 } }) do -- corner grips
    ImGui.DrawList_AddCircleFilled(dl, p[1], p[2], 5, active and C_.accent or with_alpha(C_.text, 0x90))
  end
  local grips = { { (px + px2) / 2, py, 1 }, { (px + px2) / 2, py2, 1 } }
  if not fixed_w then grips[3] = { px2, (py + py2) / 2, 0 } end
  for _, p in ipairs(grips) do -- edge grips
    local hw, hh = p[3] == 1 and 10 or 2.5, p[3] == 1 and 2.5 or 10
    ImGui.DrawList_AddRectFilled(dl, p[1] - hw, p[2] - hh, p[1] + hw, p[2] + hh, fcol, 2)
  end

  if h and h.e ~= S.sel_elem then
    ImGui.DrawList_AddRectFilled(dl, h.l, h.t, h.r, h.b, 0xFFFFFF14)
    ImGui.DrawList_AddRect(dl, h.l, h.t, h.r, h.b, C_.hover, 0, 0, 1)
  end
  if sr then
    if S.guides and S.drag and S.drag.kind == "elem" then -- alignment guides while dragging
      local gc = with_alpha(C_.accent, 0x45)
      for _, x in ipairs({ sr.l, sr.r }) do ImGui.DrawList_AddLine(dl, x, oy, x, oy + chh, gc) end
      for _, y in ipairs({ sr.t, sr.b }) do ImGui.DrawList_AddLine(dl, ox, y, ox + cw, y, gc) end
      local d = S.drag -- the edge we snapped to: solid line
      if d.snap_x then ImGui.DrawList_AddLine(dl, px + d.snap_x * z, oy, px + d.snap_x * z, oy + chh, C_.accent, 1.5) end
      if d.snap_y then ImGui.DrawList_AddLine(dl, ox, py + d.snap_y * z, ox + cw, py + d.snap_y * z, C_.accent, 1.5) end
    end
    ImGui.DrawList_AddRect(dl, sr.l - 1, sr.t - 1, sr.r + 1, sr.b + 1, C_.sel, 0, 0, 2)
    local cxm, cym = (sr.l + sr.r) / 2, (sr.t + sr.b) / 2
    for _, p in ipairs({ { sr.l, sr.t }, { sr.r, sr.t }, { sr.l, sr.b }, { sr.r, sr.b }, { cxm, sr.t }, { cxm, sr.b }, { sr.l, cym }, { sr.r, cym } }) do
      ImGui.DrawList_AddRectFilled(dl, p[1] - 3.5, p[2] - 3.5, p[1] + 3.5, p[2] + 3.5, 0xFFFFFFFF, 1)
      ImGui.DrawList_AddRect(dl, p[1] - 3.5, p[2] - 3.5, p[1] + 3.5, p[2] + 3.5, C_.sel, 1, 0, 1.5)
    end
  end
  if hovered and h and not S.drag then
    ImGui.SetTooltip(ctx, ("%s\n%d × %d"):format(nice(h.e), math.floor((h.r - h.l) / z + 0.5), math.floor((h.b - h.t) / z + 0.5)))
  end
  if S.drag and S.drag.kind == "frame" then ImGui.SetTooltip(ctx, ("%d × %d"):format(P.W, P.H)) end

  -- mouse
  if S.drag then set_cursor(S.drag.mode) else set_cursor(eh or fh) end
  if hovered and ImGui.IsMouseClicked(ctx, 0) then
    if eh then
      local l0, t0, r0, b0 = erect(L, S.sel_elem)
      local xs, ys = snap_targets(L, S.sel_elem)
      S.drag = { kind = "elem", e = S.sel_elem, mode = eh, sx = mx, sy = my, done = { 0, 0, 0, 0 },
        l0 = l0, t0 = t0, w0 = r0 - l0, h0 = b0 - t0, xs = xs, ys = ys }
    elseif fh then
      S.drag = { kind = "frame", mode = fh, sx = mx, sy = my, W0 = P.W, H0 = P.H, ox0 = P.org_x, oy0 = P.org_y }
    elseif h then
      S.sel_elem = h.e
      local l0, t0, r0, b0 = erect(L, h.e)
      local xs, ys = snap_targets(L, h.e)
      S.drag = { kind = "elem", e = h.e, mode = "move", sx = mx, sy = my, done = { 0, 0, 0, 0 },
        l0 = l0, t0 = t0, w0 = r0 - l0, h0 = b0 - t0, xs = xs, ys = ys }
    else
      S.sel_elem = nil
    end
  end
  if S.drag then
    if ImGui.IsMouseDown(ctx, 0) then
      local shift = (ImGui.GetKeyMods(ctx) & ImGui.Mod_Shift) ~= 0
      if S.drag.kind == "frame" then drag_frame(S.drag, mx, my, z) else drag_element(name, S.drag, mx, my, z, shift) end
    else
      local d = S.drag
      S.drag = nil
      if d.kind == "elem" and d.snapped then resolve_offpanel(name, d.e) end
    end
  end
  -- right-drag: hand tool. Scrolls the canvas; where there is nothing left to scroll, moves the panel origin.
  if hovered and not S.drag and ImGui.IsMouseClicked(ctx, 1) then S.panning = true end
  if S.panning then
    if not ImGui.IsMouseDown(ctx, 1) then S.panning = false else
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_Hand)
      local dx, dy = ImGui.GetMouseDelta(ctx)
      local function pan(org, scroll, maxs, d)
        if d < 0 then
          local take = math.min(-d, math.max(0, org - 8))
          org, d = org - take, d + take
          scroll = math.min(maxs, scroll - d)
        else
          local take = math.min(d, scroll)
          scroll, d = scroll - take, d - take
          org = org + d
        end
        return org, scroll
      end
      local sx, sy
      P.org_x, sx = pan(P.org_x, ImGui.GetScrollX(ctx), ImGui.GetScrollMaxX(ctx), dx)
      P.org_y, sy = pan(P.org_y, ImGui.GetScrollY(ctx), ImGui.GetScrollMaxY(ctx), dy)
      ImGui.SetScrollX(ctx, sx)
      ImGui.SetScrollY(ctx, sy)
    end
  end
  if hovered then
    local wheel = ImGui.GetMouseWheel(ctx)
    local mods = ImGui.GetKeyMods(ctx)
    if wheel ~= 0 and (mods & (ImGui.Mod_Ctrl | ImGui.Mod_Super)) ~= 0 then
      P.zoom = math.max(0.5, math.min(6, math.floor((P.zoom + (wheel > 0 and 0.1 or -0.1)) * 10 + 0.5) / 10))
    end
  end

  -- how-to hints in the bottom-right corner; the whole block fades as the panel or elements come close
  local cwx, cwy = ImGui.GetWindowPos(ctx)
  local cww, cwh = ImGui.GetWindowSize(ctx)
  local fs = ImGui.GetFontSize(ctx)
  local hints = {
    { "Click", "select an element" }, { "Drag", "move  ·  edges / corners resize" },
    { "Shift + drag edge", "resize, keep proportions" },
    { "Arrows", "1 px  ·  Shift 10 px" }, { "Alt / Option + arrows", "resize" },
    { "Ctrl / Cmd + wheel", "zoom" }, { "Right-drag", "pan the view" }, { "Panel edges", "preview the track size" },
  }
  local lh = fs + 7
  local kw, bw = 0, 0
  for _, hn in ipairs(hints) do kw = math.max(kw, text_w(hn[1])) end
  for _, hn in ipairs(hints) do bw = math.max(bw, kw + 14 + text_w(hn[2])) end
  local bx1, by1 = cwx + cww - 28 - bw, cwy + cwh - 22 - #hints * lh
  local bx2, by2 = bx1 + bw, by1 + #hints * lh
  local near = 1e9
  local function dist(l, t, r, b)
    local dx = math.max(0, bx1 - r, l - bx2)
    local dy = math.max(0, by1 - b, t - by2)
    return math.sqrt(dx * dx + dy * dy)
  end
  near = math.min(near, dist(px, py, px2, py2))
  for _, r in ipairs(rects) do near = math.min(near, dist(r.l, r.t, r.r, r.b)) end
  local a = math.max(0, math.min(1, (near - 8) / 70))
  if S.hints and a > 0.01 then
    local ty = by1
    for _, hn in ipairs(hints) do
      ImGui.DrawList_AddText(dl, bx1 + kw - text_w(hn[1]), ty, with_alpha(C_.text, 0xB0 * a), hn[1])
      ImGui.DrawList_AddText(dl, bx1 + kw + 14, ty, with_alpha(C_.text, 0x70 * a), hn[2])
      ty = ty + lh
    end
  end

  -- keyboard nudge (arrows = move, Shift = 10px, Alt/Option = resize)
  if S.sel_elem and ImGui.IsWindowFocused(ctx) and not ImGui.IsAnyItemActive(ctx) then
    local mods = ImGui.GetKeyMods(ctx)
    local step = (mods & ImGui.Mod_Shift) ~= 0 and 10 or 1
    local size = (mods & ImGui.Mod_Alt) ~= 0
    local dx, dy = 0, 0
    if ImGui.IsKeyPressed(ctx, ImGui.Key_LeftArrow) then dx = -step end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_RightArrow) then dx = step end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_UpArrow) then dy = -step end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_DownArrow) then dy = step end
    if dx ~= 0 or dy ~= 0 then
      snapshot()
      if size then move_elem(name, S.sel_elem, 0, 0, dx, dy) else move_elem(name, S.sel_elem, dx, dy, 0, 0) end
    end
  end
  draw_zoom()
  ImGui.EndChild(ctx)
end

local function mode_tag(r, visible)
  if r and r.hide then return "hidden", C_.danger end
  local rule = r and W.has_rules(r)
  if r and r.mode == "link" then return rule and "linked+rule" or "linked", C_.link end
  if r and r.mode == "abs" then return rule and "fixed+rule" or "fixed", C_.accent end
  if r and (r.dx ~= 0 or r.dy ~= 0 or r.dw ~= 0 or r.dh ~= 0 or r.att) then return rule and "moved+rule" or "moved", C_.accent end
  if rule then return "rule", C_.accent end
  if not visible then return "off", C_.dim end
  return "", C_.dim
end

local LABEL_W = 0

local insp_row = 0
local function row_label(txt, col)
  insp_row = insp_row + 1
  if insp_row % 2 == 1 then -- light / dark row bands (rows never wrap, so the height is fixed)
    local dl = ImGui.GetWindowDrawList(ctx)
    local _, ry = ImGui.GetCursorScreenPos(ctx)
    local wx = ImGui.GetWindowPos(ctx)
    local ww = ImGui.GetWindowSize(ctx)
    local fh = ImGui.GetFrameHeight(ctx)
    ImGui.DrawList_AddRectFilled(dl, wx + 1, ry - 3.5, wx + ww - 1, ry + fh + 3.5, 0xFFFFFF07)
  end
  txt = fit(txt, LABEL_W - 34) -- long custom names: truncate instead of running into the fields
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.TextColored(ctx, col or C_.dim, txt)
  ImGui.SameLine(ctx, LABEL_W)
end

-- element list groups (by element suffix); anything not listed (theme customs) lands in "Custom"
local ELEM_CATS = {
  { "Track", { "meter", "label", "trackidx", "recinput", "extmixer.position", "infoblock" } },
  { "Fader / Knob", { "volume", "pan", "width", "volume.label", "pan.label", "width.label" } },
  { "Record", { "recarm", "recmon", "recmode", "fxin" } },
  { "Buttons", { "mute", "solo", "phase", "fx", "fxbyp", "io", "env", "folder", "foldercomp", "mono", "menubutton" } },
  { "FX / Sends", { "fxparm", "fxlist", "sendlist", "fxembed" } },
  { "Custom", {} },
}

-- collapsible group header: arrow + title + "shown/total"; returns whether the group is open
local function cat_header(dl, title, shown, total, lw, fh)
  local closed = S.cat_closed[title]
  local x, y = ImGui.GetCursorScreenPos(ctx)
  if ImGui.InvisibleButton(ctx, "##cat_" .. title, lw, fh) then
    S.cat_closed[title] = not closed or nil
    local t = {}
    for k in pairs(S.cat_closed) do t[#t + 1] = k end
    reaper.SetExtState(EXT, "cat_closed", table.concat(t, ","), true)
  end
  local hov = ImGui.IsItemHovered(ctx)
  if hov then ImGui.DrawList_AddRectFilled(dl, x - 6, y, x + lw + 6, y + fh, 0xFFFFFF0A, 3) end
  local col = hov and C_.text or C_.dim
  local cx, cy, a = x + 5, y + fh / 2, 4
  if closed then ImGui.DrawList_AddTriangleFilled(dl, cx - a * 0.6, cy - a, cx - a * 0.6, cy + a, cx + a * 0.8, cy, col)
  else ImGui.DrawList_AddTriangleFilled(dl, cx - a, cy - a * 0.6, cx + a, cy - a * 0.6, cx, cy + a * 0.8, col) end
  local fs = ImGui.GetFontSize(ctx)
  ImGui.DrawList_AddText(dl, x + 18, y + (fh - fs) / 2, col, title:upper())
  local cnt = ("%d / %d"):format(shown, total)
  ImGui.DrawList_AddTextEx(dl, nil, fs * 0.85, x + lw - text_w(cnt) * 0.85, y + (fh - fs * 0.85) / 2, with_alpha(C_.dim, 0xA0), cnt)
  return not closed
end

-- right column: every element of this section, grouped, with show/hide, thumbnail and status
local function draw_elements(name, L)
  if not ImGui.BeginChild(ctx, "elements", 0, -status_h(), ImGui.ChildFlags_Borders) then return end
  local recs = recs_of(name) or {}
  heading("Elements")
  local dl = ImGui.GetWindowDrawList(ctx)
  local fh = ImGui.GetFrameHeight(ctx)
  local lw = ImGui.GetContentRegionAvail(ctx)
  local groups, of = {}, {}
  for i, c in ipairs(ELEM_CATS) do
    groups[i] = {}
    for _, x in ipairs(c[2]) do of[x] = i end
  end
  for _, e in ipairs(elem_list()) do
    local g = groups[(not T.C.customs[e] and of[suf(e)]) or #ELEM_CATS]
    g[#g + 1] = e
  end
  local function elem_row(row, e)
    ImGui.PushID(ctx, e)
    local rx, ry = ImGui.GetCursorScreenPos(ctx)
    if row % 2 == 0 then ImGui.DrawList_AddRectFilled(dl, rx - 6, ry - 3, rx + lw + 6, ry + fh + 3, 0xFFFFFF06) end
    local r = recs[e]
    local enabled = elem_enabled(L, r, e)
    local visible = erect(L, e) ~= nil
    local ch, v = ImGui.Checkbox(ctx, "##vis", enabled)
    if ch then set_hidden(name, e, not v) end
    tip(enabled and "Shown — uncheck to hide" or "Hidden — check to show")
    ImGui.SameLine(ctx)
    local ix, iy = ImGui.GetCursorScreenPos(ctx)
    ImGui.Dummy(ctx, 28, fh)
    draw_icon(dl, name, L, e, ix, iy + 1, 28, fh - 2)
    ImGui.SameLine(ctx)
    local tag, tcol = mode_tag(r, visible)
    local tw = tag ~= "" and text_w(tag) * 0.85 + 14 + 6 or 0
    local nx = ImGui.GetCursorScreenPos(ctx)
    if not enabled then ImGui.PushStyleColor(ctx, ImGui.Col_Text, C_.dim) end
    ImGui.AlignTextToFramePadding(ctx)
    if ImGui.Selectable(ctx, fit(nice(e), rx + lw - tw - nx) .. "##name", S.sel_elem == e, 0, 0, 0) then S.sel_elem = e end
    if not enabled then ImGui.PopStyleColor(ctx) end
    tip(e)
    if tag ~= "" then
      tw = tw - 6
      pill(dl, rx + lw - tw, ry + (fh - (ImGui.GetFontSize(ctx) * 0.85 + 5)) / 2, tag, tcol)
    end
    ImGui.PopID(ctx)
  end
  for gi, list in ipairs(groups) do
    if #list > 0 then
      local shown = 0
      for _, e in ipairs(list) do if elem_enabled(L, recs[e], e) then shown = shown + 1 end end
      if gi > 1 then ImGui.Dummy(ctx, 0, 2) end
      if cat_header(dl, ELEM_CATS[gi][1], shown, #list, lw, fh) then
        for row, e in ipairs(list) do elem_row(row, e) end
      end
    end
  end
  ImGui.EndChild(ctx)
end

-- bottom inspector: fixed height, one row each (no jumping when an element hides/shows)
local function draw_inspector(name, L)
  if not ImGui.BeginChild(ctx, "inspector", 0, 0, ImGui.ChildFlags_Borders, ImGui.WindowFlags_HorizontalScrollbar) then return end
  insp_row = 0
  LABEL_W = math.max(text_w("HIDE RULES"), text_w("Volume readout")) + 34
  local recs = recs_of(name) or {}
  local e = S.sel_elem
  local r = e and recs[e]
  local l, t, rr, b
  if e then l, t, rr, b = erect(L, e) end

  -- row 1: name · X Y W H · Reset
  row_label(e and nice(e) or "No selection", e and C_.accent or C_.dim)
  if e then tip(e) end
  local vals = l and { l, t, rr - l, b - t } or { 0, 0, 0, 0 }
  local d = { 0, 0, 0, 0 }
  ImGui.BeginDisabled(ctx, not l)
  for i, k in ipairs({ "X", "Y", "W", "H" }) do
    if i > 1 then ImGui.SameLine(ctx, 0, 6) end
    ImGui.SetNextItemWidth(ctx, math.max(82, btn_w("W   0000")))
    local ch, nv = ImGui.DragInt(ctx, "##" .. k, vals[i], 0, 0, 0, l and (k .. "   %d") or (k .. "   -"))
    tip("Double-click to type a value")
    snap_once("xywh" .. k, ch and l ~= nil)
    if ch and l then
      d[i] = nv - vals[i]
      if i >= 3 and vals[i] + d[i] < 1 then d[i] = 1 - vals[i] end
    end
  end
  ImGui.EndDisabled(ctx)
  if l and (d[1] ~= 0 or d[2] ~= 0 or d[3] ~= 0 or d[4] ~= 0) then move_elem(name, e, d[1], d[2], d[3], d[4]) end
  -- attach values: read-only (the Anchor menu sets them), shown as a small note left of Reset
  local note, note_tip
  if l then
    local vv = L.vars[e]
    note = ("attach %g %g %g %g"):format(vv[5], vv[6], vv[7], vv[8])
    note_tip = "Edge attachment, read-only (set it with Anchor).\nLeft, top, right, bottom: how far each edge moves when the panel\ngets bigger than the theme's base size. 0 = stays, 1 = follows fully, 0.5 = half."
  elseif e and r and W.has_rules(r) then
    note, note_tip = "hidden by rule", "Hidden by a hide rule at this preview size / state"
  elseif e then
    note, note_tip = "not placed", "Not shown in this layout — check it in the list to place it"
  end
  ImGui.SameLine(ctx, 0, 16)
  local rest = ImGui.GetContentRegionAvail(ctx)
  local need = btn_w("Reset") + (note and text_w(note) + 14 or 0)
  if rest > need then ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + rest - need) end
  if note then
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.TextDisabled(ctx, note)
    tip(note_tip)
    ImGui.SameLine(ctx, 0, 14)
  end
  ImGui.BeginDisabled(ctx, r == nil)
  if danger_button("Reset") then snapshot(); recs[e] = nil; changed() end
  ImGui.EndDisabled(ctx)
  tip("Back to the theme's own position for this element")

  -- row 2: behavior (anchor + link)
  row_label("BEHAVIOR")
  local linked = r and r.mode == "link"
  local cur_label = "Custom"
  local att = r and r.att
  if not att then cur_label = "Theme default" else
    for _, a in ipairs(ANCHORS) do
      if a[2] and a[2][1] == att[1] and a[2][2] == att[2] and a[2][3] == att[3] and a[2][4] == att[4] then cur_label = a[1] end
    end
  end
  ImGui.BeginDisabled(ctx, not l or linked == true) -- nil would mean "disabled" to ReaImGui
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.TextDisabled(ctx, "Anchor")
  ImGui.SameLine(ctx)
  local combo_w = math.max(150, btn_w("Theme default") + ImGui.GetFrameHeight(ctx))
  ImGui.SetNextItemWidth(ctx, combo_w)
  if ImGui.BeginCombo(ctx, "##anchor", linked and "Follows link" or cur_label) then
    for _, a in ipairs(ANCHORS) do
      if not (a[2] == nil and r and r.mode == "abs") then
        if ImGui.Selectable(ctx, a[1], a[1] == cur_label) then set_anchor(name, e, a[2]) end
      end
    end
    ImGui.EndCombo(ctx)
  end
  ImGui.EndDisabled(ctx)
  tip("How the element moves when the track panel gets wider/taller than the theme's base size.\nDrag the panel edges in the preview to see it.")
  ImGui.SameLine(ctx, 0, 18)
  ImGui.BeginDisabled(ctx, not l)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.TextDisabled(ctx, "Link to")
  ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, combo_w)
  if ImGui.BeginCombo(ctx, "##link", linked and nice(r.link) or "(none)", ImGui.ComboFlags_HeightLarge) then
    if ImGui.Selectable(ctx, "(none)", not linked) then set_link(name, e, nil) end
    for _, o in ipairs(elem_list()) do
      if o ~= e and erect(L, o) and not linked_to(name, e, o) then
        if ImGui.Selectable(ctx, nice(o) .. "##" .. o, linked and r.link == o) then set_link(name, e, o) end
      end
    end
    ImGui.EndCombo(ctx)
  end
  ImGui.EndDisabled(ctx)
  tip("Linked elements keep their distance: move the target and this one follows.")


  -- rows 3-4: hide rules (size rules, then state rules)
  row_label("HIDE RULES")
  ImGui.BeginDisabled(ctx, not e or not (l or r))
  local function cur() return (e and (recs_of(name) or {})[e]) or {} end
  local function toggle(label, key, default, tiptext)
    local c, v = ImGui.Checkbox(ctx, label, cur()[key] ~= nil)
    tip(tiptext)
    if c then
      snapshot()
      ensure_rec(name, e)[key] = v and default or nil
      changed()
    end
    return cur()[key] ~= nil
  end
  local function num(key, maxv, on, default)
    ImGui.SameLine(ctx, 0, 4)
    ImGui.SetNextItemWidth(ctx, math.max(64, btn_w("0000 px")))
    ImGui.BeginDisabled(ctx, not on)
    local c, v = ImGui.DragInt(ctx, "##" .. key, math.floor(cur()[key] or default), 0.5, 1, maxv, "%d px")
    ImGui.EndDisabled(ctx)
    snap_once("rule" .. key, c and on)
    if c and on then ensure_rec(name, e)[key] = v; changed() end
  end
  local on = toggle("Height <", "hh", P.H, "Hidden whenever the track is shorter than this.\nTest it by dragging the panel's bottom edge.")
  num("hh", 1000, on, P.H)
  ImGui.SameLine(ctx, 0, 16)
  local fixed_w = S.sec:find("mcp") ~= nil and not cur().hw -- keep it usable to switch off an old rule
  ImGui.BeginGroup(ctx) -- one hover area for the disabled-reason tooltip
  ImGui.BeginDisabled(ctx, fixed_w)
  on = toggle("Width <", "hw", P.W, "Hidden whenever the track panel is narrower than this.\nTest it by dragging the panel's right edge.")
  num("hw", 3000, on, P.W)
  ImGui.EndDisabled(ctx)
  ImGui.EndGroup(ctx)
  if fixed_w and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, "Not available for mixer strips:\nREAPER fixes the strip width per layout, so a width rule would never change.")
  end
  row_label("")
  toggle("Rec-armed only", "arm", true, "Shown only while the track is record-armed.\nPreview with the 'Rec-armed' checkbox above.")
  ImGui.SameLine(ctx, 0, 16)
  toggle("Selected only", "sel", true, "Shown only while the track is selected.\nPreview with the 'Selected' checkbox above.")
  ImGui.EndDisabled(ctx)
  ImGui.EndChild(ctx)
end

local function draw_edit()
  local name = S.sel_layout
  local L = name and LS(name)
  if not L then S.page = "main" return end
  local dl = ImGui.GetWindowDrawList(ctx)
  local fh = ImGui.GetFrameHeight(ctx)
  if ImGui.Button(ctx, "< Layouts") then S.page = "main"; S.drag = nil return end
  tip("Back to all layouts")
  ImGui.SameLine(ctx, 0, 12)
  ImGui.PushFont(ctx, FONT, ST.font + 4)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.TextColored(ctx, C_.title, layout_label(name))
  ImGui.PopFont(ctx)
  local n = count_edits(name)
  local dir = imgdir_of(name)
  local pills = { { SC().label, C_.link } }
  if n > 0 then pills[#pills + 1] = { n .. " edited", C_.accent } end
  if dir then pills[#pills + 1] = { "images: " .. dir, C_.dim } end
  for _, p in ipairs(pills) do
    flow(text_w(p[1]) * 0.85 + 14, 8)
    local x, y = ImGui.GetCursorScreenPos(ctx)
    local w = pill(dl, x, y + (fh - (ImGui.GetFontSize(ctx) * 0.85 + 5)) / 2, p[1], p[2])
    ImGui.Dummy(ctx, w, fh)
  end
  if S.sec:find("^master") then
    for k, id in ipairs({ "master.tcp", "master.mcp" }) do
      local lb = TABS[3].sub[k]
      flow(btn_w(lb), k == 1 and 14 or 2)
      if id == S.sec then accent_button(lb) elseif ImGui.Button(ctx, lb) then switch_section(id, true) end
      tip(id == S.sec and "" or "Switch to the master " .. (k == 1 and "track panel" or "mixer strip") .. " of this layout")
    end
  end
  if n > 0 then
    right_align(btn_w("Revert layout"))
    if danger_button("Revert layout") then snapshot(); take_sec_recs(name, true); changed() end
    tip("Remove all of your edits in this layout (can be undone)")
  end
  local editable = name == "" or W.can_edit_blocks(T.C, name, S.sec)
  if not editable then ImGui.TextColored(ctx, C_.danger, "This layout is generated by a macro; edits can't be saved for it.") end
  draw_preview_controls()
  local insp_h = 4 * fh + 3 * 7 + 24 + 12 -- 4 rows + padding + room for a horizontal scrollbar
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 0, 0)
  ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, 0x00000000)
  local ok = ImGui.BeginChild(ctx, "work", -308, -status_h())
  ImGui.PopStyleColor(ctx)
  ImGui.PopStyleVar(ctx)
  if ok then
    draw_canvas(name, L, insp_h)
    draw_inspector(name, L)
    ImGui.EndChild(ctx)
  end
  ImGui.SameLine(ctx, 0, 8)
  draw_elements(name, L)
end

----------------------------------------------------------------------------------------------------
-- Welcome / status bar
----------------------------------------------------------------------------------------------------
local function draw_welcome()
  local aw, ah = ImGui.GetContentRegionAvail(ctx)
  local steps = {
    { "1", "Choose your ColorThemes folder", "Folder... in the toolbar (currently: " .. S.dir:match("[^/]+$") .. ")" },
    { "2", "Pick a theme", "Zipped themes are unpacked first — directly, or as a safe copy" },
    { "3", "Select a TCP layout and press Edit", "Drag, resize, hide and link buttons on a live preview" },
    { "4", "Apply, then Refresh REAPER", "Apply writes rtconfig.txt · Refresh reloads the theme in REAPER" },
  }
  local fs = ImGui.GetFontSize(ctx)
  local need = text_w("Welcome to Theme Layout Modifier") * (fs + 6) / fs + 48
  for _, st in ipairs(steps) do need = math.max(need, fs * 1.9 + 60 + text_w(st[2]), fs * 1.9 + 60 + text_w(st[3])) end
  local bw, rowh = math.min(math.max(520, need), aw - 40), fs * 2 + 22
  local bh = 70 + #steps * rowh
  local x0, y0 = ImGui.GetCursorScreenPos(ctx)
  local bx, by = x0 + (aw - bw) / 2, y0 + math.max(10, (ah - bh) / 2 - 30)
  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.DrawList_AddRectFilled(dl, bx, by, bx + bw, by + bh, C_.child, 10)
  ImGui.DrawList_AddRect(dl, bx, by, bx + bw, by + bh, C_.border, 10)
  ImGui.DrawList_PushClipRect(dl, bx, by, bx + bw - 12, by + bh, true) -- window too narrow: clip, don't spill
  ImGui.DrawList_AddTextEx(dl, FONT, fs + 6, bx + 24, by + 20, C_.title, "Welcome to Theme Layout Modifier")
  local y = by + 62
  for _, st in ipairs(steps) do
    local r = fs * 0.95
    ImGui.DrawList_AddCircleFilled(dl, bx + 24 + r, y + r, r, C_.accent)
    ImGui.DrawList_AddTextEx(dl, FONT, fs, bx + 24 + r - text_w(st[1]) / 2, y + r - fs / 2, C_.accent_txt, st[1])
    ImGui.DrawList_AddText(dl, bx + 24 + r * 2 + 12, y - 1, C_.text, st[2])
    ImGui.DrawList_AddText(dl, bx + 24 + r * 2 + 12, y + fs + 3, C_.dim, st[3])
    y = y + rowh
  end
  ImGui.DrawList_PopClipRect(dl)
  ImGui.Dummy(ctx, aw, math.max(1, ah - status_h()))
end

local function draw_status()
  local dl = ImGui.GetWindowDrawList(ctx)
  local wx, wy = ImGui.GetWindowPos(ctx)
  local ww, wh = ImGui.GetWindowSize(ctx)
  local h = status_h()
  local y1 = wy + wh - h
  ImGui.DrawList_PushClipRect(dl, wx, wy, wx + ww, wy + wh, false)
  ImGui.DrawList_AddRectFilled(dl, wx, y1, wx + ww, wy + wh, C_.child, 8, ImGui.DrawFlags_RoundCornersBottom)
  ImGui.DrawList_AddLine(dl, wx, y1, wx + ww, y1, C_.border)
  local col = S.status_err and C_.danger or S.status_ok and 0x5BC07AFF or C_.dim
  local fs = ImGui.GetFontSize(ctx)
  local ty = y1 + (h - fs) / 2
  local right = T and T.meta.name or ""
  if T and S.page == "edit" then
    right = ("Panel %d × %d   ·   zoom %d%%   ·   %s"):format(P.W, P.H, math.floor(P.zoom * 100 + 0.5), T.meta.name)
  end
  local rx = wx + ww - 16 - text_w(right)
  ImGui.DrawList_AddText(dl, rx, ty, C_.dim, right)
  if S.status ~= "" then
    ImGui.DrawList_AddCircleFilled(dl, wx + 18, y1 + h / 2, 3.5, col)
    ImGui.DrawList_PushClipRect(dl, wx + 30, y1, rx - 16, wy + wh, true)
    ImGui.DrawList_AddText(dl, wx + 30, ty, S.status_err and C_.danger or C_.text, S.status)
    ImGui.DrawList_PopClipRect(dl)
  end
  ImGui.DrawList_PopClipRect(dl)
end

----------------------------------------------------------------------------------------------------
-- Main loop
----------------------------------------------------------------------------------------------------
scan_themes()
do
  local last = reaper.GetExtState(EXT, "last_theme")
  for i, t in ipairs(S.themes) do
    if t.file == last then S.theme_idx = i; load_theme(t) end
  end
end

local want_close = false

local function loop()
  if T then evaluate() end
  if G.poll() then derive_style() end
  ImGui.PushFont(ctx, FONT, ST.font)
  local nc, nv = push_theme()
  ImGui.SetNextWindowSize(ctx, 1180, 760, ImGui.Cond_FirstUseEver)
  ImGui.SetNextWindowSizeConstraints(ctx, 760, 520, 10000, 10000)
  local visible, open = ImGui.Begin(ctx, TITLE, true, ImGui.WindowFlags_NoCollapse | G.pin_flag(THEME_KEY))
  if visible then
    draw_header()
    if not T then
      draw_welcome()
    elseif S.page == "edit" then
      draw_edit()
    else
      draw_main()
    end
    if status_visible then draw_status() end
    draw_title_status()
    draw_popups()
    ImGui.End(ctx)
  end
  if T then draw_toast() end
  draw_settings()
  ImGui.PopStyleVar(ctx, nv)
  ImGui.PopStyleColor(ctx, nc)
  ImGui.PopFont(ctx)

  if not open and T and T.dirty then
    open_popup("Unsaved changes", { after = function() want_close = true end })
    open = true
  end
  if open and not want_close then reaper.defer(loop) end
end

reaper.defer(loop)
