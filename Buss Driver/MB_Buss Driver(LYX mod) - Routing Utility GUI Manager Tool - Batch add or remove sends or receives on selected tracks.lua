-- @description MB_Buss Driver - Batch add or remove send(s) or receive(s) on selected track(s)
-- @author MonkeyBars
-- @version 2.7.0
-- @changelog
--   UI/UX overhaul: segmented Add/Remove + Sends/Receives toggles, live hint sentence, settings summary,
--   track filter, existing-route markers, live checked/route counter on the apply button, status bar,
--   keyboard shortcuts, "Keep window open" option.
--   New: copy/paste route settings (from the settings form or any existing send/receive; paste into the
--   form or onto existing routes, all settings / level only / mode & channels only). Right-click a track row.
--   Fixes: undo block now wraps the changes, removing multiple routes no longer skips some, "All" no longer
--   checks hidden source tracks, MIDI "Bus N (all channels)" is now selectable, saved settings restore in a stable order.
-- @provides [main] .
--  [nomain] rtk.lua
--  [nomain] serpent.lua
--  [nomain] mb-dev-functions.lua
--  bussdriver_logo_nobg.png
--  gen_midi_off.png
--  gen_midi_on.png
--  gen_mono_off.png
--  gen_mono_on.png
--  gen_phase_off.png
--  gen_phase_on.png
--  table_mute_off.png
--  table_mute_on.png
--  gnu_license_v3.txt


-- Copyright (C) MonkeyBars 2024
-- This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your routing_option) any later version.
-- This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
-- You should have received a copy of the GNU General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.


-- ==== MB_BUSS DRIVER SCRIPT ARCHITECTURE NOTES ====
-- MB_Buss Driver uses the great GUI library Reaper Toolkit (rtk). (https://reapertoolkit.dev/)
-- MB_Buss Driver uses Serpent, a serialization library for LUA, for table-string and string-table conversion. (https://github.com/pkulchenko/serpent)


package.path = package.path .. ";" .. string.match(({reaper.get_action_context()})[2], "(.-)([^\\/]-%.?([^%.\\/]*))$") .. "?.lua"

-- for dev only
-- require("mb-dev-functions")


local rtk = require("rtk")
local serpent = require("serpent")


-- ==== SCALE PREFERENCE ====
local _scale = 1.0
do
  -- GetExtState returns a single string (not bool+string like GetProjExtState)
  local stored = reaper.GetExtState("MB_BussDriver_Prefs", "scale")
  if stored and stored ~= "" then
    local v = tonumber(stored)
    if v and v >= 0.8 and v <= 2.0 then _scale = v end
  end
end

-- Scale helper: multiply fontscale values by _scale
local function fs(v) return v * _scale end

-- ==== COLOR PREFERENCES ====
local _color_defaults = {
  window_bg  = "#1E1E2E",
  header_bg  = "#1A1A3A",
  accent     = "#8A4C00",
  tree_line  = "#FFFFFF",
  text       = "#FFFFFF",
}

-- ==== TREE LINE MODE ====
-- "radial" = direct lines from parent to child (current)
-- "elbow" = horizontal line then vertical drop to children
local _tree_mode = "radial"
do
  local stored = reaper.GetExtState("MB_BussDriver_Prefs", "tree_mode")
  if stored == "radial" or stored == "elbow" then _tree_mode = stored end
end
local _colors = {}
for k, v in pairs(_color_defaults) do _colors[k] = v end
do
  local stored = reaper.GetExtState("MB_BussDriver_Prefs", "colors")
  if stored and stored ~= "" then
    -- format: "key=hex;key=hex;..."
    for k, v in stored:gmatch("([%w_]+)=([^;]+)") do
      if _color_defaults[k] then _colors[k] = v end
    end
  end
end

-- Helper: convert "#RRGGBB" hex to REAPER native color (0xBBGGRR int)
local function hex2native(hex)
  local r = tonumber(hex:sub(2, 3), 16) or 0
  local g = tonumber(hex:sub(4, 5), 16) or 0
  local b = tonumber(hex:sub(6, 7), 16) or 0
  return reaper.ColorToNative(r, g, b)
end

-- Helper: convert REAPER native color to "#RRGGBB"
local function native2hex(col)
  local r, g, b = reaper.ColorFromNative(col)
  return string.format("#%02X%02X%02X", r, g, b)
end

-- Save current _colors to ExtState
local function saveColors()
  local parts = {}
  for k, v in pairs(_colors) do parts[#parts + 1] = k .. "=" .. v end
  reaper.SetExtState("MB_BussDriver_Prefs", "colors", table.concat(parts, ";"), true)
end

-- ==== UI PALETTE (derived, not user-editable) ====
local _ui = {
  seg_off     = "#34344A",
  seg_text    = "#A8A8C0",
  btn         = "#45455E",
  muted       = "#9A9AB4",
  ok          = "#8FD19E",
  warn        = "#FFB36B",
  marker      = "#E0A050",
  card_border = "1px #4A4A66",
  btn_text    = "#E8E8F0",
  subtitle    = nil            -- settings section labels (nil = default text colour)
}

-- ==== LYX GLOBAL THEME ====
-- When "Inherit Lyx global theme" is on, the current Lyx theme replaces the colours above at startup
-- (rtk widgets bake colours at creation, so changes apply after a script restart).
local LYX_THEME_KEY = "Buss Driver"
package.path = package.path .. ";" .. (({reaper.get_action_context()})[2]:match("^(.*[/\\])[^/\\]+[/\\][^/\\]+$") or "") .. "?.lua"
local _T_ok, T = pcall(require, "_Lyx_Theme")
if not _T_ok then T = nil end
local _inherit = T ~= nil and T.inherit(LYX_THEME_KEY)
local _rtk_theme = {}  -- extra rtk theme overrides (only when inherited)
if _inherit then
  local th = T.get()
  local c = th.colors
  local function hex(rgb) return string.format("#%06X", rgb) end
  local dim = hex(T.mix(c.text, c.bg, 0.45))
  _colors.window_bg = hex(c.bg)
  _colors.header_bg = hex(c.bg2)
  _colors.accent    = hex(c.accent)
  _colors.text      = hex(c.text)
  _ui.seg_off     = hex(c.base)
  _ui.seg_text    = dim
  _ui.muted       = dim
  _ui.btn         = hex(th.button.color)
  _ui.btn_text    = hex(c.text)
  _ui.card_border = "1px " .. hex(c.base)
  _ui.subtitle    = hex(c.subtitle)
  _rtk_theme = {
    accent = _colors.accent, text_faded = dim,
    button = _ui.btn, button_label = _colors.text,
    heading = hex(c.title),
    entry_bg = hex(th.frame.color), entry_border_focused = _colors.accent, entry_selection_bg = _colors.accent,
    slider = _colors.accent, slider_track = _ui.seg_off,
    popup_bg = _colors.header_bg,
  }
end

-- ==== BEHAVIOR PREFS ====
local _keep_open = reaper.GetExtState("MB_BussDriver_Prefs", "keep_open") == "true"

-- ==== UI REFRESH STATE ====
local _ui_dirty = true            -- recompute visibility + counters on next frame
local _filter_text = ""           -- lowercase track filter
local _status_time = nil          -- when the status line was last set
local _right_was_down = false
local _routes_last_check = 0

local function markDirty() _ui_dirty = true end

-- Route parameter groups for copy/paste (BR_GetSetTrackSendInfo names)
local _route_param_groups = {
  all = {"B_MUTE", "B_PHASE", "B_MONO", "D_VOL", "D_PAN", "D_PANLAW", "I_SENDMODE", "I_SRCCHAN", "I_DSTCHAN", "I_MIDI_SRCCHAN", "I_MIDI_DSTCHAN", "I_MIDI_SRCBUS", "I_MIDI_DSTBUS", "I_MIDI_LINK_VOLPAN"},
  level = {"B_MUTE", "B_PHASE", "B_MONO", "D_VOL", "D_PAN", "D_PANLAW", "I_MIDI_LINK_VOLPAN"},
  channels = {"I_SENDMODE", "I_SRCCHAN", "I_DSTCHAN", "I_MIDI_SRCCHAN", "I_MIDI_DSTCHAN", "I_MIDI_SRCBUS", "I_MIDI_DSTBUS"}
}

local function plural(word, n) return n == 1 and word or word .. "s" end

-- UTF-8 safe truncation (track names are often CJK)
local function utf8Trunc(s, n)
  local ok, len = pcall(utf8.len, s)
  if not ok or not len or len <= n then return s end
  return s:sub(1, utf8.offset(s, n + 1) - 1) .. "…"
end

-- Escape characters that gfx.showmenu treats specially
local function menuSafe(s)
  s = s:gsub("|", "/"):gsub("&", "&&")
  if s:match("^[#!<>]") then s = " " .. s end
  return s
end

local function trackLabel(track, max_chars)
  local num = math.floor(reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
  if num <= 0 then return "MASTER" end
  local _, name = reaper.GetTrackName(track)
  return num .. ": " .. utf8Trunc(name, max_chars or 24)
end

local function trackIsValid(track)
  return track and reaper.ValidatePtr2(0, track, "MediaTrack*")
end


-- ==== LAYOUT CONSTANTS ====
-- One place for every size/gap in the main window and both popups.
-- Sizes follow the UI scale (fs); gaps/paddings stay in raw px.
local L = {
  pad        = 12,         -- side padding of header / list / bottom bar / popups
  pad_v      = 8,          -- top/bottom padding of those panels
  gap        = 6,          -- between controls on one row
  row_gap    = 8,          -- between rows / sections
  seg_gap    = 2,          -- between the two halves of a segmented toggle
  icon       = fs(24),     -- square header icon buttons (settings / help / pin)
  h_small    = fs(22),     -- small buttons, filter entry, popup buttons
  h_main     = fs(26),     -- mode toggles and Add / Close
  btn_minw   = fs(84),     -- Add / Close share one width
  label_w    = fs(130),    -- left column: "Send settings…" button and "Clipboard:" label
  swatch     = fs(22),     -- colour swatch = same height as the button beside it
  cb_h       = 17,         -- checkbox row height (same as track rows)
  fs_label   = fs(0.7),    -- muted labels, summaries, counters, checkboxes, status
  fs_btn     = fs(0.72),   -- small buttons
  fs_main    = fs(0.85),   -- mode toggles, Add / Close
  fs_icon    = fs(0.95),   -- header icon glyphs
  fs_heading = fs(0.75),   -- section headings inside popups
  fs_title   = fs(0.6),    -- popup titles (rtk.Heading)
}

local function smallBtn(label, tooltip, color)
  return rtk.Button{label = label, tooltip = tooltip, h = L.h_small, padding = "2 8 3", fontscale = L.fs_btn, halign = "center", color = color or _ui.btn, textcolor = _ui.btn_text}
end

local function iconBtn(label, tooltip)
  return rtk.Button{label = label, tooltip = tooltip, w = L.icon, h = L.icon, padding = 2, fontscale = L.fs_icon, halign = "center", valign = "center", color = "#555555", textcolor = "#CCCCCC"}
end

-- Popup section heading (Scale / Colors / Tree Lines all look the same)
local function sectionHeading(text)
  return rtk.Text{text, fontscale = L.fs_heading, fontflags = rtk.font.UNDERLINE, tmargin = 4, color = _ui.subtitle}
end

-- ==== PIN (always on top) ====
-- Shared with the other Lyx GUIs: ExtState "Lyx_GUI", "pin:<key>". rtk's Window `pinned`
-- does the TOPMOST z-order itself (needs js_ReaScriptAPI; without it the toggle is stored but inert).
local PIN_KEY = "pin:" .. LYX_THEME_KEY
local _pinned = reaper.GetExtState("Lyx_GUI", PIN_KEY) == "1"

local function pinTooltip()
  if not rtk.has_js_reascript_api then return "Pin window (needs js_ReaScriptAPI)" end
  return _pinned and "Unpin window" or "Pin window (always on top)"
end

-- Push-pin glyph (same look as _Lyx_GUI's G.pin): upright = pinned, tilted 45 deg = not.
local function drawPin(self, offx, offy, alpha)
  local c = self.calc
  local cx, cy = offx + c.x + c.w / 2, offy + c.y + c.h / 2
  local r = math.min(c.w, c.h) * 0.36
  local cr, cg, cb = rtk.color.rgba(_pinned and _colors.accent or _ui.muted)
  local lift = (_pinned and 0.3 or 0) + (self.hovering and 0.3 or 0)  -- keep accent readable on the grey button
  gfx.set(cr + (1 - cr) * lift, cg + (1 - cg) * lift, cb + (1 - cb) * lift, alpha)
  local a = _pinned and 0 or math.pi / 4
  local ca, sa = math.cos(a), math.sin(a)
  local function P(x, y) return cx + x * ca - y * sa, cy + x * sa + y * ca end
  local function line(x1, y1, x2, y2, w)
    local ax, ay = P(x1, y1)
    local bx, by = P(x2, y2)
    local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
    local px, py = -(by - ay) / len, (bx - ax) / len
    for o = -(w - 1) / 2, (w - 1) / 2 do  -- offset copies perpendicular to the line = thickness
      gfx.line(ax + o * px, ay + o * py, bx + o * px, by + o * py, 1)
    end
  end
  local hx, hy = P(0, -r * 0.45)
  gfx.circle(hx, hy, r * 0.38, 1, 1)                                          -- head
  line(-r * 0.55, -r * 0.05, r * 0.55, -r * 0.05, math.max(2, math.floor(r * 0.22)))  -- collar
  line(0, -r * 0.05, 0, r * 0.95, 1)                                          -- needle
end


_rtk_theme.tooltip_font = {"Segoe UI (TrueType)", 13}
_rtk_theme.bg = _colors.window_bg
_rtk_theme.text = _colors.text
rtk.set_theme_overrides(_rtk_theme)


-- ==== DRAG-TO-CHECK STATE ====
local _drag_check = {
  active = false,
  value = false,
  mouse_was_down = false,
  start_cb = nil,
  toggled = {},
  last_cb = nil,
  suppress_toggle = false,  -- suppress rtk's click-toggle during drag
  clear_suppress = false     -- one-frame delay for clearing suppress
}

-- ==== TREE INDENT CACHE ====
local _tree_indent = {} -- depth → pixel indent, calculated in populateTargetTracksBox

-- ==== FLAT TRACK LINE ARRAY ====
local _all_track_lines = {}


local _regex = {

  routing = {

    midi = {
      channel = "/%-?%d+",
      bus = "%-?%d+/"
    }
  }
}


local _unicode = {
  right_arrow = "\u{2192}",
  left_arrow = "\u{2190}"
}


local _api = {
  current_project = 0,
  msg_type_ok = 0,

  channels = {
    mono_base = 1024,

    src = {

      stereo = {
        default = 0
      },

      multichannel = {
        base = 2048,
        addl = 1024
      }
    },

    dest = {
      default = 0
    },

    midi = {
      max_value = 16
    }
  },

  routing = {

    param = {
      src_track = "P_SRCTRACK",
      dest_track = "P_DESTTRACK"
    },

    category = {
      receive = -1,
      send = 0
    },

    set_new_value = 1
  },

  track = {
    channel_count = "I_NCHAN",
    icon = "P_ICON",
    num = "IP_TRACKNUMBER",
    name = "P_NAME"
  },

  all_routing_settings = {"B_MUTE", "B_PHASE", "B_MONO", "D_VOL", "D_PAN", "D_PANLAW", "I_SENDMODE", "I_SRCCHAN", "I_DSTCHAN", "I_MIDI_SRCCHAN", "I_MIDI_DSTCHAN", "I_MIDI_SRCBUS", "I_MIDI_DSTBUS", "I_MIDI_LINK_VOLPAN"}
}


local _constant = {

  brand = {
    script = "MB_Buss Driver",
    script_ext_name = "MB_Buss-Driver",
    save_options_key_name = "save_options"
  },

  path = {
    logo_img = "bussdriver_logo_nobg.png"
  },

  default_routing_settings_values = {
    mute = 0,
    phase = 0,
    mono_stereo = 0,
    send_mode = 0,
    volume = 2.8285,
    pan = 0,
    midi_velpan = 0,
    audio_src_channel = 0,
    audio_dest_channel = 0,
    midi_src = "0/0",
    midi_dest = "0/0"
  },

  reaper_max_track_channels = 128,
  selected_tracks_count = reaper.CountSelectedTracks(_api.current_project),
  configure_btn_rendered_height = 19
}


local _state = {
  enough_audio_channels_are_available = true,

  -- current main mode (replaces the old add/remove + send/receive checkboxes)
  mode = {
    action = "add",   -- "add" | "remove"
    type = "send"     -- "send" | "receive"
  },

  tracks = {
    all = nil,
    selected = nil,

    selected = {
      current_idx = nil
    },

    target = {
      current_idx = nil
    }
  },

  routing = {
    newly_created_idx = nil,

    option_choice = {
      action = nil,
      type = nil
    },

    options_objs = nil,
    settings_objs = nil
  }
}




function storeRetrieveProjectData(key, val)
  local retrieve, store, retval, state_data_val

  retrieve = not val
  store = val

  if retrieve then
    retval, state_data_val = reaper.GetProjExtState(_api.current_project, _constant.brand.script_ext_name, key)

  elseif store then
    reaper.SetProjExtState(_api.current_project, _constant.brand.script_ext_name, key, val)
  end

  return state_data_val
end


function toggleSaveOptions(initialize)
  local current_save_options_setting, save_options_checkbox_value, new_option_val

  if initialize == "initialize" then
    current_save_options_setting = storeRetrieveProjectData(_constant.brand.save_options_key_name)

    if current_save_options_setting == "" or not current_save_options_setting then
      storeRetrieveProjectData(_constant.brand.save_options_key_name, "true")
    end

  else
    save_options_checkbox_value = _state.routing.options_objs.save_options.value
    new_option_val = save_options_checkbox_value and "true" or "false"

    storeRetrieveProjectData(_constant.brand.save_options_key_name, new_option_val)
  end
end

toggleSaveOptions("initialize")



function getSelectedTracks()
  local selected_tracks, this_selected_track

  selected_tracks = {}

  for i = 0, _constant.selected_tracks_count-1 do
    this_selected_track = reaper.GetSelectedTrack(_api.current_project, i)

    table.insert(selected_tracks, this_selected_track)
  end

  return selected_tracks
end

_state.tracks.selected = getSelectedTracks(_constant.selected_tracks_count)



function storeRetrieveAllTracksCount(val)
  local store, retrieve, stored_tracks_count_on_open, all_tracks_count

  store = val
  retrieve = not val

  if store then
    storeRetrieveProjectData("all_tracks_count", val)

  elseif retrieve then
    stored_tracks_count_on_open = storeRetrieveProjectData("all_tracks_count")

    if not stored_tracks_count_on_open or stored_tracks_count_on_open == "" then
      all_tracks_count = reaper.CountTracks(_api.current_project)

    else
      all_tracks_count = stored_tracks_count_on_open
      stored_tracks_count_on_open = tonumber(stored_tracks_count_on_open)
    end

    return all_tracks_count
  end
end

_all_tracks_count_on_launch = storeRetrieveAllTracksCount()


-- Build a set of selected track GUIDs for fast lookup (hide children of selected parents)
local _selected_track_guids = {}
for i = 1, #_state.tracks.selected do
  local guid = reaper.BR_GetMediaTrackGUID(_state.tracks.selected[i])
  _selected_track_guids[guid] = true
end


-- Live refresh: rebuild track lists when REAPER selection changes (throttled)
local _refresh_last_check = 0
function refreshIfSelectionChanged()
  local now = reaper.time_precise()
  if now - _refresh_last_check < 0.1 then return end  -- check every 0.1s
  _refresh_last_check = now

  local cur_count = reaper.CountSelectedTracks(_api.current_project)
  if cur_count < 1 then return end -- don't refresh if nothing selected

  -- Build current selection GUIDs to compare
  local cur_guids = {}
  for i = 0, cur_count - 1 do
    local t = reaper.GetSelectedTrack(_api.current_project, i)
    if t then cur_guids[reaper.BR_GetMediaTrackGUID(t)] = true end
  end

  -- Compare with stored selection
  local changed = false
  if cur_count ~= #_state.tracks.selected then
    changed = true
  else
    for i = 1, #_state.tracks.selected do
      local g = reaper.BR_GetMediaTrackGUID(_state.tracks.selected[i])
      if not cur_guids[g] then changed = true; break end
    end
  end
  if not changed then return end

  -- Update selected tracks
  _state.tracks.selected = {}
  _constant.selected_tracks_count = cur_count
  for i = 0, cur_count - 1 do
    local t = reaper.GetSelectedTrack(_api.current_project, i)
    if t then table.insert(_state.tracks.selected, t) end
  end

  -- Rebuild GUID lookup (clear in-place to preserve upvalue reference)
  for k in pairs(_selected_track_guids) do _selected_track_guids[k] = nil end
  for i = 1, #_state.tracks.selected do
    _selected_track_guids[reaper.BR_GetMediaTrackGUID(_state.tracks.selected[i])] = true
  end

  rebuildSourceAndTargets()
  setStatus("Source tracks updated from REAPER selection.")
end


-- Rebuild the source chips + target list (after selection change)
function rebuildSourceAndTargets()
  local o = _state.routing.options_objs

  local old_list = o.selected_tracks_list
  local list_idx = o.selected_tracks_box:get_child_index(old_list)
  o.selected_tracks_list = getSelectedTracksList()
  if list_idx then
    o.selected_tracks_box:replace(list_idx, o.selected_tracks_list)
  end
  o.selected_tracks_heading:attr("text", getSourceHeadingText())

  _state.tracks.all = nil -- force re-scan
  _all_tracks_count_on_launch = reaper.CountTracks(_api.current_project)
  local old_box = o.target_tracks_box
  local box_idx = o.form_fields:get_child_index(old_box)
  o.target_tracks_box = populateTargetTracksBox()
  if box_idx then
    o.form_fields:replace(box_idx, o.target_tracks_box)
  end

  applyMode()
end


function getSourceHeadingText()
  local n = #_state.tracks.selected
  return "SOURCE  " .. n .. " " .. plural("track", n) .. "  (follows REAPER selection)"
end


function launchBussDriverDialog()
  getRoutingOptionsObjects()
  populateRoutingOptionsWindow()
  defineRoutingOptionsEventHandlers()
  _state.routing.options_objs.window:open()
  applyMode()
  storeRetrieveUserOptions("retrieve")
  propagateSavedUserOptions()
  refreshClipboardSummary()
  refreshSettingsSummary()
end


local _shortcuts_help = table.concat({
  "Enter  -  apply (add / remove)",
  "Esc  -  clear filter, or close the window",
  "Ctrl/Cmd+F  -  filter the track list",
  "Ctrl/Cmd+A  /  Ctrl/Cmd+D  -  check all visible / uncheck all",
  "Ctrl/Cmd+C  /  Ctrl/Cmd+V  -  copy / paste send settings",
  "",
  "Drag across checkboxes to check or uncheck many tracks at once.",
  "Right-click a track row to copy settings from its existing send/receive",
  "or paste the clipboard onto it."
}, "\n")


function getRoutingOptionsObjects()
  local function segBtn(label, tooltip)
    return rtk.Button{label = label, tooltip = tooltip, h = L.h_main, padding = "2 12 3", fontscale = L.fs_main, halign = "center", color = _ui.seg_off, textcolor = _ui.seg_text}
  end

  local function bottomCheck(label, tooltip, value, ref)
    return rtk.CheckBox{label, tooltip = tooltip, value = value, h = L.cb_h, padding = "0 2 3 2", spacing = 3, valign = "center", fontscale = L.fs_label, color = "#CCCCCC", textcolor2 = "#CCCCCC", ref = ref}
  end

  local function colorBtn(label)
    return rtk.Button{label, h = L.h_small, padding = "2 8 3", fontscale = L.fs_btn, color = "#444", textcolor = "#E0E0E0", disabled = _inherit}
  end

  local function swatch(color)
    return rtk.Spacer{w = L.swatch, h = L.swatch, bg = color, border = "1px #666"}
  end

  local function colorRow() return rtk.HBox{w = 1, spacing = L.gap, valign = "center"} end

  local panel_pad = L.pad_v .. " " .. L.pad

  _state.routing.options_objs = {
    window = rtk.Window{title = _constant.brand.script .. " - Batch add or remove sends or receives on selected tracks", w = 0.4, h = 0.55, maxh = 0.9, pinned = _pinned},
    viewport = rtk.Viewport{halign = "center", bpadding = 5, vscrollbar = "auto"},
    main_vbox = rtk.VBox{w = 1, h = 1},  -- main layout container (Window is a Container, not VBox)

    -- ── Header ──
    header_box = rtk.VBox{w = 1, padding = panel_pad, spacing = L.row_gap, bg = _colors.header_bg},
    header_top = rtk.Container{w = 1},
    settings_btn = iconBtn("\u{2699}", "UI settings (scale, colors, tree lines)"),
    brand = rtk.HBox{valign = "center", spacing = L.gap},
    logo = rtk.ImageBox{rtk.Image():load(_constant.path.logo_img), w = 26, halign = "center"},
    title = rtk.Heading{"Buss Driver", fontscale = L.fs_title},
    header_right = rtk.HBox{spacing = L.gap, valign = "center"},
    help_btn = iconBtn("?", _shortcuts_help),
    pin_btn = iconBtn("", pinTooltip()),

    -- Source tracks card
    selected_tracks_box = rtk.VBox{w = 1, padding = "6 8", spacing = 4, border = _ui.card_border},
    selected_tracks_heading = rtk.Text{getSourceHeadingText(), fontscale = L.fs_label, color = _ui.muted},
    selected_tracks_list = getSelectedTracksList(),

    -- Mode: segmented toggles
    mode_row = rtk.HBox{spacing = 2 * L.gap, valign = "center"},
    action_seg = rtk.HBox{spacing = L.seg_gap},
    add_btn = segBtn("+  Add", "Create new routing"),
    remove_btn = segBtn("-  Remove", "Delete existing routing"),
    type_seg = rtk.HBox{spacing = L.seg_gap},
    send_btn = segBtn("Sends  " .. _unicode.right_arrow, "The source tracks send TO the tracks you check"),
    receive_btn = segBtn(_unicode.left_arrow .. "  Receives", "The source tracks receive FROM the tracks you check"),
    hint_text = rtk.Text{"", w = 1, wrap = true, fontscale = L.fs_heading, color = "#D0D0E0"},

    -- Send settings (add mode only) -- left column shares L.label_w with the clipboard label below
    settings_row = rtk.HBox{w = 1, spacing = L.gap, valign = "center"},
    configure_btn = smallBtn("Send settings" .. "\u{2026}", "Volume, pan, mode and channels applied to every new send/receive", _colors.accent),
    settings_summary = rtk.Text{"", fontscale = L.fs_label, color = _ui.muted},

    -- Route clipboard
    clip_row = rtk.HBox{w = 1, spacing = L.gap, valign = "center"},
    clip_label = rtk.Text{"Clipboard:", w = L.label_w, fontscale = L.fs_label, color = _ui.muted},
    clip_summary = rtk.Text{"empty", fontscale = L.fs_label, color = "#D8D8E8"},
    copy_btn = smallBtn("Copy" .. "\u{2026}", "Copy route settings from the send settings or from an existing send/receive"),
    paste_btn = smallBtn("Paste" .. "\u{2026}", "Paste route settings into the send settings, or onto existing routes"),

    -- Track list toolbar
    list_toolbar = rtk.HBox{w = 1, spacing = L.gap, valign = "center"},
    filter_entry = rtk.Entry{placeholder = "Filter tracks" .. "\u{2026}" .. "  (Ctrl/Cmd+F)", h = L.h_small, fontscale = fs(0.78)},
    select_all_btn = smallBtn("All", "Check all visible tracks (Ctrl/Cmd+A)"),
    select_none_btn = smallBtn("None", "Uncheck all tracks (Ctrl/Cmd+D)"),
    deselect_existing_routing = smallBtn("Skip existing", "Uncheck tracks that already have a send/receive with the source tracks"),
    count_text = rtk.Text{"", fontscale = L.fs_label, color = _ui.muted},

    -- ── Scrollable track list ──
    content = rtk.VBox{w = 1, halign = "center", padding = 0},
    form_fields = rtk.VBox{w = 1, padding = "6 " .. L.pad, spacing = L.gap},
    empty_text = rtk.Text{"", w = 1, wrap = true, textalign = "center", tmargin = 24, fontscale = fs(0.8), color = _ui.muted},
    target_tracks_box = nil, -- populated below after getAllTracks

    -- ── Bottom bar ──
    bottom_bar = rtk.VBox{w = 1, padding = panel_pad, spacing = 4, bg = _colors.header_bg},
    form_bottom = rtk.Container{w = 1},
    options_box = rtk.VBox{spacing = 2},
    save_options = bottomCheck("Remember choices", "Remember mode, checked tracks and send settings for this project", nil, "save_options_checkbox"),
    keep_open = bottomCheck("Keep window open", "Don't close after applying, so you can keep routing", _keep_open),
    form_buttons = rtk.HBox{spacing = L.row_gap, valign = "center"},
    form_submit = rtk.Button{"Add", disabled = true, tooltip = "Apply (Enter)", h = L.h_main, minw = L.btn_minw, halign = "center", padding = "2 16 3", fontscale = L.fs_main, color = _colors.accent, textcolor = "#FFFFFF"},
    form_cancel = rtk.Button{"Close", tooltip = "Close (Esc)", h = L.h_main, minw = L.btn_minw, halign = "center", padding = "2 16 3", fontscale = L.fs_main},
    reset_btn = smallBtn("Reset", "Uncheck all tracks, clear the filter and reset send settings to defaults"),
    status_text = rtk.Text{"", w = 1, textalign = "center", fontscale = L.fs_label, color = _ui.ok},

    -- Settings popup (every row spans the full content width, so right edges line up)
    settings_popup = rtk.Popup{w = fs(280), overlay = "#00000088", padding = 0},
    settings_content = rtk.VBox{w = 1, padding = L.pad, spacing = L.row_gap},
    settings_title = rtk.Heading{"UI Settings", w = 1, fontscale = L.fs_title, halign = "center", textalign = "center"},
    settings_scale_label = sectionHeading("Scale: " .. string.format("%.0f%%", _scale * 100)),
    settings_scale = rtk.Slider{w = 1, min = 0.8, max = 2.0, value = _scale, step = 0.05, color = "orange", fontscale = fs(0.63)},
    settings_note = rtk.Text{"Restart script after changing scale/colors.", w = 1, wrap = true, fontscale = fs(0.63), color = "#999999"},
    -- Color picker section
    settings_color_heading = sectionHeading("Colors"),
    -- Lyx global theme (only when _Lyx_Theme.lua was found)
    theme_row = rtk.VBox{w = 1, spacing = L.gap},  -- stacked: popup is narrow
    theme_inherit = rtk.CheckBox{"Inherit Lyx global theme", value = _inherit, tooltip = "Use the Lyx global theme colours instead of the colours below (restart script to apply)", h = L.cb_h, padding = "0 2 3 2", spacing = 3, valign = "center", fontscale = L.fs_label},
    theme_manager_btn = rtk.Button{"Lyx global theme", tooltip = "Open the Lyx global theme manager", h = L.h_small, padding = "2 8 3", fontscale = L.fs_btn, color = _ui.btn, textcolor = _ui.btn_text},
    color_window_bg_row = colorRow(),
    color_window_bg_swatch = swatch(_colors.window_bg),
    color_window_bg_btn = colorBtn("Window Background"),
    color_header_bg_row = colorRow(),
    color_header_bg_swatch = swatch(_colors.header_bg),
    color_header_bg_btn = colorBtn("Header / Bar"),
    color_accent_row = colorRow(),
    color_accent_swatch = swatch(_colors.accent),
    color_accent_btn = colorBtn("Accent (Buttons)"),
    color_tree_line_row = colorRow(),
    color_tree_line_swatch = swatch(_colors.tree_line),
    color_tree_line_btn = colorBtn("Tree Guide Lines"),
    color_text_row = colorRow(),
    color_text_swatch = swatch(_colors.text),
    color_text_btn = colorBtn("Text"),
    settings_color_reset = rtk.Button{"Reset Colors", h = L.h_small, padding = "2 8 3", fontscale = L.fs_btn, color = _colors.accent, textcolor = "#E0E0E0", disabled = _inherit},
    -- Tree line mode
    settings_tree_heading = sectionHeading("Tree Lines"),
    settings_tree_mode_row = rtk.HBox{w = 1, spacing = L.gap, valign = "center"},
    settings_tree_radial = rtk.Button{"Radial", h = L.h_small, halign = "center", padding = "2 8 3", fontscale = L.fs_btn,
      color = _tree_mode == "radial" and "orange" or "#444", textcolor = "#E0E0E0"},
    settings_tree_elbow = rtk.Button{"Elbow", h = L.h_small, halign = "center", padding = "2 8 3", fontscale = L.fs_btn,
      color = _tree_mode == "elbow" and "orange" or "#444", textcolor = "#E0E0E0"},
    settings_save = rtk.Button{"Save & Close", h = L.h_small, halign = "center", padding = "2 8 3", fontscale = L.fs_btn},
    settings_reset = rtk.Button{"Reset All", h = L.h_small, halign = "center", padding = "2 8 3", fontscale = L.fs_btn, color = _colors.accent, textcolor = "#E0E0E0"}
  }

  -- Left label column: the settings button is as wide as the "Clipboard:" label
  _state.routing.options_objs.configure_btn:attr("w", L.label_w)

  -- Pin button: blank label, the push-pin is drawn on top of the button surface
  _state.routing.options_objs.pin_btn.ondraw = drawPin

  -- Now populate target_tracks_box (needs _state.routing.options_objs to exist for deselect btn)
  _state.routing.options_objs.target_tracks_box = populateTargetTracksBox()
end


function getSelectedTracksList()
  local selected_tracks_list, this_track, retval, this_track_name, this_track_num, this_track_color

  selected_tracks_list = rtk.FlowBox{hspacing = 10}

  for i = 1, #_state.tracks.selected do
    this_track = _state.tracks.selected[i]
    retval, this_track_name = reaper.GetTrackName(this_track)
    this_track_num = math.tointeger(reaper.GetMediaTrackInfo_Value(this_track, _api.track.num))
    this_track_color = reaper.GetTrackColor(this_track)
    this_track_color = rtk.color.convert_native(this_track_color)

    selected_tracks_list:add(rtk.Text{this_track_num .. ": " .. this_track_name, padding = "1 4 3", fontscale = fs(0.67), color = "#E0E0E0", bg = this_track_color})
  end

  return selected_tracks_list
end


function populateTargetTracksBox()
  local routing_option_target_tracks_box

  if not _state.tracks.all then
    getAllTracks()
  end

  -- Clear flat array
  _all_track_lines = {}

  -- ── Tree indent calculation ──
  -- Find max label length per depth level (character count estimate)
  local max_label_len = {} -- depth → max character count
  local est_char_w = fs(5.8) -- approximate pixel width per character at fontscale 0.75
  local tree_pad = fs(18)    -- padding between depth levels — 微調此值 -- tweak this value

  for i = 1, #_state.tracks.all do
    local info = _state.tracks.all[i]
    if not info.hidden then
      local d = info.depth
      local label = tostring(info.num) .. ": " .. (info.name or "")
      local len = #label
      if not max_label_len[d] or len > max_label_len[d] then
        max_label_len[d] = len
      end
    end
  end

  -- Calculate cumulative indent: each depth starts after the longest label of the previous depth
  -- Minimum indent ensures children aren't too close when parent names are short
  local min_indent = fs(80)  -- minimum gap between parent and child — 微調此值
  _tree_indent = {}
  _tree_indent[0] = 0
  for d = 1, 10 do
    local prev_width = (max_label_len[d-1] or 8) * est_char_w
    local gap = math.max(prev_width + tree_pad, min_indent)
    _tree_indent[d] = (_tree_indent[d-1] or 0) + gap
  end

  -- ── Single VBox layout (viewport handles scrolling) ──
  routing_option_target_tracks_box = rtk.VBox{w = 1, tmargin = 7, spacing = 1, ref = "routing_option_target_tracks_box"}

  for i = 1, #_state.tracks.all do
    local track_info = _state.tracks.all[i]
    if not track_info.hidden then
      local indent_px = _tree_indent[track_info.depth] or 0
      local line = createTargetTrackLine(track_info.track, indent_px, track_info.depth, track_info.is_folder, i)
      routing_option_target_tracks_box:add(line)
    end
  end

  -- Tree guide lines: two modes — "radial" (direct) or "elbow" (horizontal + vertical)
  routing_option_target_tracks_box.ondraw = function(self, offx, offy, alpha, event)
    if not self.clientx then return end
    -- Tree line color from prefs
    local tr = tonumber(_colors.tree_line:sub(2, 3), 16) or 255
    local tg = tonumber(_colors.tree_line:sub(4, 5), 16) or 255
    local tb = tonumber(_colors.tree_line:sub(6, 7), 16) or 255
    gfx.set(tr / 255, tg / 255, tb / 255, 1)
    local line_w = 2  -- half-width for 4px total

    -- Helper: draw a thick line (works for any angle)
    local function thick_line(x1, y1, x2, y2)
      local dx = x2 - x1
      local dy = y2 - y1
      local len = math.sqrt(dx * dx + dy * dy)
      if len < 1 then return end
      local px = -dy / len
      local py = dx / len
      for offset = -line_w + 1, line_w do
        local ox = px * offset * 0.5
        local oy = py * offset * 0.5
        gfx.line(x1 + ox, y1 + oy, x2 + ox, y2 + oy)
      end
    end

    -- Base coords: offx/offy + VBox's own calc position (includes tmargin etc.)
    local sx = offx + self.calc.x
    local sy = offy + self.calc.y

    -- Collect parent→children mapping for elbow mode
    -- key = parent index in _all_track_lines, value = list of child indices
    local parent_children = {}

    -- For each child, find its direct parent and draw lines
    for j = 1, #_all_track_lines do
      local info = _all_track_lines[j]
      local d = info.depth or 0
      if d > 0 and info.line.visible ~= false and info.line.calc and info.checkbox.calc then
        -- Find direct parent (nearest previous line with depth == d-1)
        local parent_idx = nil
        for k = j - 1, 1, -1 do
          local prev = _all_track_lines[k]
          if prev.line.visible ~= false and prev.line.calc and prev.checkbox.calc then
            if (prev.depth or 0) == d - 1 then
              parent_idx = k
              break
            elseif (prev.depth or 0) < d - 1 then
              break
            end
          end
        end

        if parent_idx then
          local parent_info = _all_track_lines[parent_idx]
          local p_line = parent_info.line
          local p_cb = parent_info.checkbox
          local p_right = sx + p_line.calc.x + p_cb.calc.x + p_cb.calc.w
          local p_cy = sy + p_line.calc.y + p_cb.calc.y + p_cb.calc.h / 2

          local c_line = info.line
          local c_cb = info.checkbox
          local c_left = sx + c_line.calc.x + c_cb.calc.x
          local c_cy = sy + c_line.calc.y + c_cb.calc.y + c_cb.calc.h / 2

          if _tree_mode == "elbow" then
            -- Collect for grouped drawing
            if not parent_children[parent_idx] then
              parent_children[parent_idx] = {p_right = p_right, p_cy = p_cy, c_left = c_left, children = {}}
            end
            parent_children[parent_idx].children[#parent_children[parent_idx].children + 1] = {cy = c_cy, left = c_left}
          else
            -- Radial mode: direct line from parent right to child left
            local ddx = c_left - p_right
            local ddy = c_cy - p_cy
            local len = math.sqrt(ddx * ddx + ddy * ddy)
            local pad = 7
            if len > pad * 2 then
              local nx, ny = ddx / len, ddy / len
              thick_line(p_right + nx * pad, p_cy + ny * pad, c_left - nx * pad, c_cy - ny * pad)
            end
          end
        end
      end
    end

    -- Elbow mode: draw grouped lines per parent
    if _tree_mode == "elbow" then
      local pad = 7
      local corner_gap = 20  -- 水平線在到達child前20px開始轉彎 -- horizontal stops 20px before child indent
      for _, pg in pairs(parent_children) do
        local p_right = pg.p_right + pad  -- start after padding
        local p_cy = pg.p_cy
        local children = pg.children
        if #children > 0 then
          -- 轉角X座標：child的左邊再往左corner_gap -- elbow X = child left - corner_gap
          local elbow_x = children[1].left - corner_gap
          -- 水平線：parent右邊 → elbow_x -- horizontal line from parent to elbow
          thick_line(p_right, p_cy, elbow_x, p_cy)
          -- 垂直主幹：從parent的Y到最後一個child的Y -- vertical trunk from parent Y to last child Y
          local first_cy = children[1].cy
          local last_cy = children[#children].cy
          thick_line(elbow_x, p_cy, elbow_x, last_cy)
          -- 各child的水平分支 -- horizontal branch to each child
          for _, ch in ipairs(children) do
            thick_line(elbow_x, ch.cy, ch.left - pad, ch.cy)
          end
        end
      end
    end
  end

  return routing_option_target_tracks_box
end


function getAllTracks()
  _state.tracks.all = {}

  -- Track folder hierarchy for compact state + hide children of selected parents
  local depth_stack = {} -- stack of {track, guid, compact, is_selected}
  local current_depth = 0

  for i = 0, _all_tracks_count_on_launch-1 do
    local track = reaper.GetTrack(_api.current_project, i)
    local folder_depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    local folder_compact = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERCOMPACT")
    local track_guid = reaper.BR_GetMediaTrackGUID(track)
    local is_folder = (folder_depth == 1)
    local hidden = false

    -- Check if any parent in the stack hides this track
    for s = 1, #depth_stack do
      local parent_info = depth_stack[s]
      -- Hide if parent is compact==2 or parent is a selected source track
      if parent_info.compact == 2 or parent_info.is_selected then
        hidden = true
        break
      end
    end

    -- Also hide if this track itself is a selected source track
    if _selected_track_guids[track_guid] then
      -- Don't hide - lineIsEligible() hides source tracks in Add mode
      -- But we still add it to the list for consistency
    end

    local _, t_name = reaper.GetSetMediaTrackInfo_String(track, _api.track.name, "", 0)
    local t_num = math.tointeger(reaper.GetMediaTrackInfo_Value(track, _api.track.num))

    table.insert(_state.tracks.all, {
      track = track,
      depth = #depth_stack, -- nesting level (0 = top level)
      is_folder = is_folder,
      hidden = hidden,
      guid = track_guid,
      name = t_name,
      num = t_num
    })

    -- Update depth stack
    if is_folder then
      -- Push this folder onto the stack
      table.insert(depth_stack, {
        track = track,
        guid = track_guid,
        compact = folder_compact,
        is_selected = _selected_track_guids[track_guid] or false
      })
    end

    -- Handle folder end: folder_depth can be negative (e.g., -1, -2 to close multiple levels)
    if folder_depth < 0 then
      local levels_to_close = math.abs(math.floor(folder_depth))
      for c = 1, levels_to_close do
        if #depth_stack > 0 then
          table.remove(depth_stack)
        end
      end
    end
  end
end


function createTargetTrackLine(this_track, indent_px, depth, is_folder, all_idx)
  local this_track_line, this_track_icon, this_track_color, this_track_checkbox, this_track_marker

  this_track_line, this_track_icon, this_track_color, this_track_checkbox = getTrackObjs(this_track, indent_px)

  if this_track_color ~= 0 then
    this_track_color = rtk.color.convert_native(this_track_color)

    this_track_checkbox:attr("bg", this_track_color)

    this_track_checkbox = correctTrackColor(this_track_checkbox, this_track_color)
  end

  this_track_checkbox.onchange = function(self)
    -- Folder parent: check/uncheck children with it (they get collapsed while the parent is checked)
    if is_folder then
      setChildrenChecked(all_idx, self.value)
    end
    markDirty()
  end

  -- Override toggle() to suppress rtk's click-toggle during drag
  local orig_toggle = this_track_checkbox.toggle
  this_track_checkbox.toggle = function(self)
    if _drag_check.suppress_toggle then return end
    return orig_toggle(self)
  end

  -- Small tag showing existing routing with the source tracks
  this_track_marker = rtk.Text{"", fontscale = fs(0.62), color = _ui.marker, lmargin = 2, visible = false}

  this_track_line:add(this_track_icon)
  this_track_line:add(this_track_checkbox)
  this_track_line:add(this_track_marker)

  local _, search_name = reaper.GetSetMediaTrackInfo_String(this_track, _api.track.name, "", false)

  -- Store in flat array with hierarchy info
  table.insert(_all_track_lines, {
    line = this_track_line,
    checkbox = this_track_checkbox,
    marker = this_track_marker,
    track = this_track,
    track_guid = this_track_line.data__track_guid,
    search = (math.floor(this_track_line.data__track_num) .. ": " .. search_name):lower(),
    route_count = 0,
    depth = depth or 0,
    is_folder = is_folder or false,
    all_idx = all_idx  -- index in _state.tracks.all
  })

  return this_track_line
end


-- Check/uncheck all children of a folder track along with the parent
function setChildrenChecked(parent_all_idx, parent_checked)
  local parent_depth = _state.tracks.all[parent_all_idx].depth

  -- Find the flat array index for this parent
  local parent_flat_idx = nil
  for j = 1, #_all_track_lines do
    if _all_track_lines[j].all_idx == parent_all_idx then
      parent_flat_idx = j
      break
    end
  end
  if not parent_flat_idx then return end

  -- Walk forward: children have depth > parent_depth
  for j = parent_flat_idx + 1, #_all_track_lines do
    local info = _all_track_lines[j]
    if info.depth <= parent_depth then break end
    if info.checkbox.value ~= parent_checked then
      info.checkbox:attr("value", parent_checked)
    end
  end
  markDirty()
end


-- A line can be a target in the current mode (independent of filter/collapse)
function lineIsEligible(info)
  if _state.mode.action == "remove" then
    return (info.route_count or 0) > 0
  end
  return not info.line.data__track_is_selected
end


-- Recompute which rows are shown: mode eligibility, folder collapse, filter
function updateLineVisibility()
  local collapse_depth = nil
  local visible_count = 0

  for j = 1, #_all_track_lines do
    local info = _all_track_lines[j]
    local eligible = lineIsEligible(info)

    if collapse_depth and info.depth <= collapse_depth then collapse_depth = nil end
    local collapsed = collapse_depth ~= nil

    local matches = _filter_text == "" or info.search:find(_filter_text, 1, true) ~= nil
    local visible = eligible and not collapsed and matches

    if visible then
      if info.line.visible == false then info.line:show() end
      visible_count = visible_count + 1
    elseif info.line.visible ~= false then
      info.line:hide()
    end

    -- A checked folder collapses its children (they are checked with it)
    if not collapsed and eligible and info.is_folder and info.checkbox.value then
      collapse_depth = info.depth
    end
  end

  return visible_count
end


-- Scan existing routing between the source tracks and every row
function refreshExistingRoutes()
  local counts = {}
  local routes = collectRoutes(_state.mode.type)
  for i = 1, #routes do
    local g = routes[i].other_guid
    counts[g] = (counts[g] or 0) + 1
  end

  local changed = false
  local type_word = _state.mode.type
  for j = 1, #_all_track_lines do
    local info = _all_track_lines[j]
    local n = counts[info.track_guid] or 0
    if n ~= info.route_count then changed = true end
    info.route_count = n

    local marker_text = ""
    if n > 0 then
      if _state.mode.action == "remove" then
        marker_text = n > 1 and ("x" .. n) or ""
      else
        marker_text = "\u{25CF} has " .. type_word
      end
    end
    if info.marker.text ~= marker_text then
      info.marker:attr("text", marker_text)
      if marker_text == "" then info.marker:hide() else info.marker:show() end
    end
  end

  if changed then markDirty() end
  return changed
end


-- Update counters, apply button, empty state (runs when _ui_dirty)
function refreshSummary(visible_count)
  local o = _state.routing.options_objs
  local action, rtype = _state.mode.action, _state.mode.type
  local n_src = #_state.tracks.selected
  local checked, eligible_count, route_total = 0, 0, 0

  for j = 1, #_all_track_lines do
    local info = _all_track_lines[j]
    if lineIsEligible(info) then
      eligible_count = eligible_count + 1
      if info.checkbox.value then
        checked = checked + 1
        route_total = route_total + (action == "remove" and info.route_count or n_src)
      end
    end
  end

  local verb = action == "add" and "Add " or "Remove "
  o.form_submit:attr("label", route_total > 0 and (verb .. route_total .. " " .. plural(rtype, route_total)) or (action == "add" and "Add" or "Remove"))
  o.form_submit:attr("disabled", route_total == 0)

  o.count_text:attr("text", checked .. " / " .. eligible_count .. " checked")

  local empty_msg = ""
  if visible_count == 0 then
    if eligible_count == 0 and action == "remove" then
      empty_msg = "The source tracks have no " .. rtype .. "s to remove."
    elseif _filter_text ~= "" then
      empty_msg = "No tracks match \"" .. o.filter_entry.value .. "\"."
    else
      empty_msg = "No tracks to show."
    end
  end
  o.empty_text:attr("text", empty_msg)
  if empty_msg == "" then o.empty_text:hide() else o.empty_text:show() end
end


function getTrackObjs(this_track, indent_px)
  local this_track_line, retval, this_track_icon_path, this_track_icon, this_track_num, this_track_name, this_track_color, this_track_checkbox

  -- Tree indent: pixel value passed from populateTargetTracksBox
  local indent = indent_px or 0

  this_track_line = rtk.HBox{valign = "center", lmargin = indent, data__class = "target_track_line"}
  retval, this_track_icon_path = reaper.GetSetMediaTrackInfo_String(this_track, _api.track.icon, "", false)
  this_track_icon = rtk.ImageBox{rtk.Image():load(this_track_icon_path), w = 18, minw = 18}
  this_track_num = math.tointeger(reaper.GetMediaTrackInfo_Value(this_track, _api.track.num))
  retval, this_track_name = reaper.GetSetMediaTrackInfo_String(this_track, _api.track.name, "", 0)
  this_track_color = reaper.GetTrackColor(this_track)
  this_track_checkbox = rtk.CheckBox{this_track_num .. ": " .. this_track_name, h = 17, fontscale = fs(0.75), margin = "0 5 1 2", padding = "0 2 3 2", spacing = 3, valign = "center", ref = "target_track_" .. this_track_num, data__class = "target_track_checkbox"}

  this_track_line.data__track_is_selected = reaper.IsTrackSelected(this_track)
  this_track_line.data__track_num = reaper.GetMediaTrackInfo_Value(this_track, _api.track.num)
  this_track_line.data__track_guid = reaper.BR_GetMediaTrackGUID(this_track)

  return this_track_line, this_track_icon, this_track_color, this_track_checkbox
end


function correctTrackColor(track_checkbox, track_color)
  local this_track_color_r, this_track_color_g, this_track_color_b, this_track_color_rgb, this_track_color_is_dark

  this_track_color_r, this_track_color_g, this_track_color_b = reaper.ColorFromNative(track_color)
  this_track_color_rgb = this_track_color_r + this_track_color_g + this_track_color_b
  this_track_color_rgb = tonumber(this_track_color_rgb)
  this_track_color_is_dark = colorIsDark(this_track_color_rgb)

  if not this_track_color_is_dark then
    track_checkbox:attr("textcolor2", "#000000")
  end

  return track_checkbox
end


function colorIsDark(rgb)
  local is_color_dark = rgb < 3 * 256 / 2

  return is_color_dark
end


function disableSubmitButton(disable)
  _state.routing.options_objs.form_submit:attr("disabled", disable)
end


function anyPopupOpen()
  local o = _state.routing.options_objs
  if o.settings_popup.opened then return true end
  return _state.routing.settings_objs and _state.routing.settings_objs.popup.opened or false
end


-- Is the point inside the scrollable track list?
local function pointInViewport(mx, my)
  local vp = _state.routing.options_objs.viewport
  if not (vp.clientx and vp.clienty and vp.calc and vp.calc.w) then return false end
  return mx >= vp.clientx and mx <= vp.clientx + vp.calc.w and my >= vp.clienty and my <= vp.clienty + vp.calc.h
end


-- Find the visible row (and its checkbox) under the cursor
local function hitTestRow(mx, my, checkbox_only)
  if not pointInViewport(mx, my) then return nil end
  for j = 1, #_all_track_lines do
    local info = _all_track_lines[j]
    if info.line.visible ~= false then
      local w = checkbox_only and info.checkbox or info.line
      if w.clientx and w.clienty and w.calc and w.calc.w and w.calc.h then
        if mx >= w.clientx and mx <= w.clientx + w.calc.w and
           my >= w.clienty and my <= w.clienty + w.calc.h then
          return info, j
        end
      end
    end
  end
end


function setStatus(msg, kind)
  local o = _state.routing.options_objs
  if not o or not o.status_text then return end
  o.status_text:attr("color", kind == "warn" and _ui.warn or _ui.ok)
  o.status_text:attr("text", msg or "")
  _status_time = reaper.time_precise()
end


function submitIfReady()
  local o = _state.routing.options_objs
  if not o.form_submit.disabled then
    submitRoutingOptionChanges()
  end
end


function defineRoutingOptionsEventHandlers()
  local o = _state.routing.options_objs

  o.window.onclose = function()
    storeRetrieveUserOptions("store")
    restoreUserSelectedTracks()
    storeRetrieveAllTracksCount("")
  end

  -- Mode toggles
  o.add_btn.onclick = function() setMode("add", nil) end
  o.remove_btn.onclick = function() setMode("remove", nil) end
  o.send_btn.onclick = function() setMode(nil, "send") end
  o.receive_btn.onclick = function() setMode(nil, "receive") end

  o.configure_btn.onclick = function()
    launchRoutingSettings()
  end

  -- Pin (always on top): rtk applies TOPMOST/NOTOPMOST when the window attr changes
  o.pin_btn.onclick = function(self)
    _pinned = not _pinned
    reaper.SetExtState("Lyx_GUI", PIN_KEY, _pinned and "1" or "0", true)
    o.window:attr("pinned", _pinned)
    self:attr("tooltip", pinTooltip())
    self:queue_draw()
  end

  o.help_btn.onclick = function()
    reaper.ShowMessageBox(_shortcuts_help, _constant.brand.script .. " - Tips & shortcuts", _api.msg_type_ok)
  end

  -- Clipboard
  o.copy_btn.onclick = function(self) openCopyMenu(self) end
  o.paste_btn.onclick = function(self) openPasteMenu(self) end

  -- List toolbar
  o.filter_entry.onchange = function(self)
    _filter_text = (self.value or ""):lower()
    markDirty()
  end

  o.select_all_btn.onclick = function()
    selectDeselectAllTargetTracks(true)
  end

  o.select_none_btn.onclick = function()
    selectDeselectAllTargetTracks(false)
  end

  o.deselect_existing_routing.onclick = function()
    deselectExistingRouting()
  end

  -- Bottom bar
  o.save_options.onchange = function()
    toggleSaveOptions()
  end

  o.keep_open.onchange = function(self)
    _keep_open = self.value and true or false
    reaper.SetExtState("MB_BussDriver_Prefs", "keep_open", _keep_open and "true" or "false", true)
  end

  o.form_submit.onclick = function()
    submitRoutingOptionChanges()
  end

  o.form_cancel.onclick = function()
    o.window:close()
  end

  o.reset_btn.onclick = function()
    selectDeselectAllTargetTracks(false)
    o.filter_entry:attr("value", "")
    _filter_text = ""
    populateRoutingSettingsFormValues("reset")
    refreshSettingsSummary()
    markDirty()
    setStatus("Reset: all tracks unchecked, send settings back to defaults.")
  end

  -- Keyboard shortcuts
  o.window.onkeypresspre = function(self, event)
    if anyPopupOpen() then return end
    local in_entry = rtk.focused == o.filter_entry
    local kc = event.keycode

    if kc == rtk.keycodes.ESCAPE and in_entry then
      if (o.filter_entry.value or "") ~= "" then
        o.filter_entry:attr("value", "")
        _filter_text = ""
        markDirty()
      else
        o.filter_entry:blur()
      end
      event:set_handled(self)
      return
    end

    if kc == rtk.keycodes.RETURN then
      if in_entry then o.filter_entry:blur() end
      submitIfReady()
      event:set_handled(self)
      return
    end

    if event.ctrl and event.char then
      local c = event.char:lower()
      if c == "f" then
        o.filter_entry:focus()
        o.filter_entry:select_all()
        event:set_handled(self)
      elseif not in_entry then
        if c == "a" then
          selectDeselectAllTargetTracks(true); event:set_handled(self)
        elseif c == "d" then
          selectDeselectAllTargetTracks(false); event:set_handled(self)
        elseif c == "c" then
          copyFromSettingsForm(); event:set_handled(self)
        elseif c == "v" then
          pasteIntoSettingsForm(_route_param_groups.all); event:set_handled(self)
        end
      end
    end
  end

  -- Per-frame: live refresh, dirty UI, drag-to-check, right-click menu
  -- We toggle on mousedown ourselves and suppress rtk's click-toggle via overridden toggle()
  o.window.onupdate = function(self)
    local now = reaper.time_precise()

    -- Live refresh: check if REAPER track selection changed
    refreshIfSelectionChanged()

    -- Pick up routing changes made outside the script (once a second)
    if now - _routes_last_check > 1.0 then
      _routes_last_check = now
      refreshExistingRoutes()
    end

    if _ui_dirty then
      _ui_dirty = false
      refreshSummary(updateLineVisibility())
    end

    -- Fade out the status line
    if _status_time and now - _status_time > 6 then
      _status_time = nil
      o.status_text:attr("text", "")
    end

    local cap = gfx.mouse_cap or 0
    local mouse_down = (cap & 1) ~= 0
    local right_down = (cap & 2) ~= 0
    local mx = gfx.mouse_x or 0
    local my = gfx.mouse_y or 0
    local popup_open = anyPopupOpen()

    -- Step 1: clear suppress_toggle one frame after drag ended
    -- (rtk's click event fires in the same frame as mouseup, AFTER onupdate)
    if _drag_check.clear_suppress then
      _drag_check.suppress_toggle = false
      _drag_check.clear_suppress = false
    end

    -- Right-click on a row → context menu (and keep rtk from toggling the checkbox on release)
    if right_down and not _right_was_down and not popup_open then
      local info = hitTestRow(mx, my, false)
      if info then
        _drag_check.suppress_toggle = true
        openTrackContextMenu(info)
      end
    elseif not right_down and _right_was_down and not _drag_check.active then
      _drag_check.clear_suppress = true
    end
    _right_was_down = right_down

    -- Step 2: detect mousedown transition → start drag + toggle start checkbox
    if mouse_down and not _drag_check.mouse_was_down and not popup_open then
      local info = hitTestRow(mx, my, true)
      if info then
        local cb = info.checkbox
        local new_val = not cb.value
        _drag_check.active = true
        _drag_check.suppress_toggle = true  -- block rtk's click-toggle
        _drag_check.start_cb = cb
        _drag_check.value = new_val
        _drag_check.toggled = {[cb] = true}
        _drag_check.last_cb = cb
        cb:attr("value", new_val)  -- toggle immediately on mousedown
      end
    end

    -- Step 3: during drag, toggle checkboxes as cursor passes over them
    if _drag_check.active and mouse_down then
      local hover_info = hitTestRow(mx, my, true)
      local hover_cb = hover_info and hover_info.checkbox
      if hover_cb then
        -- Toggle new checkbox
        if not _drag_check.toggled[hover_cb] then
          if hover_cb.value ~= _drag_check.value then
            hover_cb:attr("value", _drag_check.value)
          end
          _drag_check.toggled[hover_cb] = true
        end

        -- Revert checkboxes outside start→current range (mouse moved back)
        if hover_cb ~= _drag_check.last_cb then
          local start_idx, hover_idx = nil, nil
          for j = 1, #_all_track_lines do
            local cb = _all_track_lines[j].checkbox
            if cb == _drag_check.start_cb then start_idx = j end
            if cb == hover_cb then hover_idx = j end
          end
          if start_idx and hover_idx then
            local lo = math.min(start_idx, hover_idx)
            local hi = math.max(start_idx, hover_idx)
            for j = 1, #_all_track_lines do
              local cb = _all_track_lines[j].checkbox
              if _drag_check.toggled[cb] and (j < lo or j > hi) then
                cb:attr("value", not _drag_check.value)
                _drag_check.toggled[cb] = nil
              end
            end
          end
          _drag_check.last_cb = hover_cb
        end
      end
    end

    -- Step 4: mouseup → end drag, schedule suppress clear for next frame
    if _drag_check.active and not mouse_down then
      _drag_check.active = false
      _drag_check.start_cb = nil
      _drag_check.toggled = {}
      _drag_check.last_cb = nil
      _drag_check.clear_suppress = true  -- clear suppress NEXT frame (after rtk processes click)
    end

    _drag_check.mouse_was_down = mouse_down
  end

  -- Settings popup handlers
  _state.routing.options_objs.settings_btn.onclick = function()
    _state.routing.options_objs.settings_popup:open()
  end

  _state.routing.options_objs.settings_scale.onchange = function(self)
    _state.routing.options_objs.settings_scale_label:attr("text", "Scale: " .. string.format("%.0f%%", self.value * 100))
  end

  -- Color picker helper: open native picker, update swatch + _colors table
  local function pickColor(color_key, swatch_widget)
    local hwnd = reaper.GetMainHwnd()
    local cur_native = hex2native(_colors[color_key])
    local retval, new_color = reaper.GR_SelectColor(hwnd, cur_native)
    if retval ~= 0 then
      local hex = native2hex(new_color)
      _colors[color_key] = hex
      swatch_widget:attr("bg", hex)
    end
  end

  local o = _state.routing.options_objs
  o.color_window_bg_btn.onclick = function() pickColor("window_bg", o.color_window_bg_swatch) end
  o.color_header_bg_btn.onclick = function() pickColor("header_bg", o.color_header_bg_swatch) end
  o.color_accent_btn.onclick = function() pickColor("accent", o.color_accent_swatch) end
  o.color_tree_line_btn.onclick = function() pickColor("tree_line", o.color_tree_line_swatch) end
  o.color_text_btn.onclick = function() pickColor("text", o.color_text_swatch) end

  -- Lyx global theme
  o.theme_inherit.onchange = function(self) T.set_inherit(LYX_THEME_KEY, self.value and true or false) end
  o.theme_manager_btn.onclick = function() T.open_manager() end

  -- Tree mode buttons
  local function updateTreeBtns()
    o.settings_tree_radial:attr("color", _tree_mode == "radial" and "orange" or "#444")
    o.settings_tree_elbow:attr("color", _tree_mode == "elbow" and "orange" or "#444")
  end
  o.settings_tree_radial.onclick = function() _tree_mode = "radial"; updateTreeBtns() end
  o.settings_tree_elbow.onclick = function() _tree_mode = "elbow"; updateTreeBtns() end

  -- Helper: update all color swatches from _colors
  local function refreshSwatches()
    o.color_window_bg_swatch:attr("bg", _colors.window_bg)
    o.color_header_bg_swatch:attr("bg", _colors.header_bg)
    o.color_accent_swatch:attr("bg", _colors.accent)
    o.color_tree_line_swatch:attr("bg", _colors.tree_line)
    o.color_text_swatch:attr("bg", _colors.text)
  end

  -- Reset colors to defaults
  o.settings_color_reset.onclick = function()
    for k, v in pairs(_color_defaults) do _colors[k] = v end
    refreshSwatches()
  end

  o.settings_save.onclick = function()
    local new_scale = o.settings_scale.value
    reaper.SetExtState("MB_BussDriver_Prefs", "scale", tostring(new_scale), true)
    reaper.SetExtState("MB_BussDriver_Prefs", "tree_mode", _tree_mode, true)
    if not _inherit then saveColors() end  -- never store theme colours as the script's own
    o.settings_popup:close()
  end

  o.settings_reset.onclick = function()
    o.settings_scale:attr("value", 1.0)
    o.settings_scale_label:attr("text", "Scale: 100%")
    for k, v in pairs(_color_defaults) do _colors[k] = v end
    refreshSwatches()
    _tree_mode = "radial"; updateTreeBtns()
  end
end


-- Deselect target tracks that already have routing to/from selected tracks
function deselectExistingRouting()
  refreshExistingRoutes()

  local unchecked = 0
  for j = 1, #_all_track_lines do
    local info = _all_track_lines[j]
    if info.route_count > 0 and info.checkbox.value then
      info.checkbox:attr("value", false)
      unchecked = unchecked + 1
    end
  end

  markDirty()
  setStatus(unchecked > 0 and ("Unchecked " .. unchecked .. " " .. plural("track", unchecked) .. " that already have a " .. _state.mode.type .. ".") or "No checked track has existing routing.")
end


function storeRetrieveUserOptions(store_retrieve)
  local retval, current_save_options_setting, all_user_options

  retval, current_save_options_setting = reaper.GetProjExtState(_api.current_project, _constant.brand.script_ext_name, _constant.brand.save_options_key_name)

  if current_save_options_setting == "true" then

    if store_retrieve == "store" then
      all_user_options = getSetMainActionChoices("get")

      getCurrentTargetTrackChoices()

      all_user_options.target_track_choices = _state.routing.options_objs.target_track_choices

      if _state.routing.settings_objs and _state.routing.settings_objs.all_values then
        all_user_options.routing_settings = _state.routing.settings_objs.all_values
      end

      all_user_options = serpent.dump(all_user_options)

      storeRetrieveProjectData("all_user_options", all_user_options)

    elseif store_retrieve == "retrieve" then
      all_user_options = storeRetrieveProjectData("all_user_options")
      retval, all_user_options = serpent.load(all_user_options)
      _state.routing.options_objs.all_user_options = all_user_options
    end

  end
end


function propagateSavedUserOptions()
  local retval, current_save_options_setting

  retval, current_save_options_setting = reaper.GetProjExtState(_api.current_project, _constant.brand.script_ext_name, _constant.brand.save_options_key_name)

  if current_save_options_setting == "true" then
    _state.routing.options_objs.save_options:attr("value", true)

    if _state.routing.options_objs and _state.routing.options_objs.all_user_options then
      getSetMainActionChoices("set")

      if _state.routing.options_objs.all_user_options.target_track_choices then

        if #_state.routing.options_objs.all_user_options.target_track_choices > 0 then
          setTargetTrackChoices(_state.routing.options_objs.all_user_options.target_track_choices)
        end
      end

      if _state.routing.options_objs.all_user_options.routing_settings then

        if not _state.routing.settings_objs then
          initRoutingSettings()
        end

        _state.routing.settings_objs.all_values = _state.routing.options_objs.all_user_options.routing_settings

        getSetRoutingSettingsValues("set", _state.routing.settings_objs.all_values)
      end
    end

  elseif current_save_options_setting == "false" then
    _state.routing.options_objs.save_options:attr("value", false)
  end
end


function getSetMainActionChoices(get_set)

  if get_set == "get" then
    -- Same keys as the old checkbox-based format, so saved project data stays compatible
    return {
      add_checkbox = _state.mode.action == "add",
      remove_checkbox = _state.mode.action == "remove",
      send_checkbox = _state.mode.type == "send",
      receive_checkbox = _state.mode.type == "receive"
    }

  elseif get_set == "set" then
    local saved = _state.routing.options_objs.all_user_options or {}

    setMode(saved.remove_checkbox and "remove" or "add", saved.receive_checkbox and "receive" or "send", true)
  end
end


function restoreUserSelectedTracks()

  for i = 1, #_state.tracks.selected do
    reaper.SetTrackSelected(_state.tracks.selected[i], true)
  end
end


function setMode(action, rtype, force)
  local action_changed = action ~= nil and action ~= _state.mode.action
  local type_changed = rtype ~= nil and rtype ~= _state.mode.type

  if not (action_changed or type_changed or force) then return end

  if action then _state.mode.action = action end
  if rtype then _state.mode.type = rtype end

  -- Add and Remove list different tracks: start with nothing checked
  if action_changed then
    selectDeselectAllTargetTracks(false)
  end

  applyMode()
end


-- Sync every mode-dependent widget with _state.mode
function applyMode()
  local o = _state.routing.options_objs
  local action, rtype = _state.mode.action, _state.mode.type

  local function seg(btn, on)
    btn:attr("color", on and _colors.accent or _ui.seg_off)
    btn:attr("textcolor", on and "#FFFFFF" or _ui.seg_text)
  end

  seg(o.add_btn, action == "add")
  seg(o.remove_btn, action == "remove")
  seg(o.send_btn, rtype == "send")
  seg(o.receive_btn, rtype == "receive")

  o.hint_text:attr("text", getModeHintText())
  o.configure_btn:attr("label", (rtype == "send" and "Send" or "Receive") .. " settings" .. "\u{2026}")
  o.deselect_existing_routing:attr("tooltip", "Uncheck tracks that already have a " .. rtype .. " with the source tracks")

  if action == "add" then
    o.settings_row:show()
    o.deselect_existing_routing:show()
  else
    o.settings_row:hide()
    o.deselect_existing_routing:hide()
  end

  refreshExistingRoutes()
  markDirty()
end


function getModeHintText()
  local n = #_state.tracks.selected
  local src = n == 1 and "the source track" or ("each of the " .. n .. " source tracks")
  local key = _state.mode.action .. "_" .. _state.mode.type

  local hints = {
    add_send = "Create a send from " .. src .. " to every track you check below.",
    add_receive = "Create a receive on " .. src .. " from every track you check below.",
    remove_send = "Delete the sends from " .. src .. " to the tracks you check. Only tracks they already send to are listed.",
    remove_receive = "Delete the receives on " .. src .. " from the tracks you check. Only tracks they already receive from are listed."
  }

  return hints[key]
end


function getRoutingChoices()
  return _state.mode.action, _state.mode.type
end


function getRoutingValues(selected_routing_type)
  local api_routing_category, api_routing_param

  if selected_routing_type == "send" then
    api_routing_category = _api.routing.category.send
    api_routing_param = _api.routing.param.dest_track

  elseif selected_routing_type == "receive" then
    api_routing_category = _api.routing.category.receive
    api_routing_param = _api.routing.param.src_track
  end

  return api_routing_category, api_routing_param
end


function launchRoutingSettings()

  if not _state.routing.settings_objs then
    initRoutingSettings()
  end

  _state.routing.settings_objs.title:attr("text", "Settings for new " .. _state.mode.type .. "s")
  _state.routing.settings_objs.popup:open()
end


function initRoutingSettings()
  populateRoutingSettingsObjs()
  gatherRoutingSettingsFormFields()
  setRoutingSettingsPopupEventHandlers()
  -- Build the popup before filling values: the channel dropdown handlers need the arrow widgets
  populateRoutingSettingsPopup()
  setRoutingSettingsFormEventHandlers()
  populateAudioDestChannelDefaultOptions()
  populateRoutingSettingsFormValues()
end


function populateRoutingSettingsObjs()
  local audio_channel_src_options, midi_channel_src_options, midi_channel_dest_options

  audio_channel_src_options = defineAudioSrcChannelOptions()
  midi_channel_src_options, midi_channel_dest_options = defineMIDIChannelOptions()

  _state.routing.settings_objs = {
    popup = rtk.Popup{w = _state.routing.options_objs.window.w / 3, minw = 341, overlay = "#303030cc", padding = 0},
    content = rtk.VBox(),
    close_btn = rtk.Button{"X", position = "absolute", z = 10, w = 14, h = 16, margin = "4 0 0 4", padding = 2, color = "#555555", halign = "center", fontscale = fs(0.7), textcolor = "#BBBBBB"},
    title = rtk.Heading{"Settings for new sends", w = 1, halign = "center", textalign = "center", padding = 6, bg = "#3A3A52", fontscale = L.fs_title},
    footer = rtk.HBox{w = 1, spacing = L.gap, valign = "center", padding = L.pad_v .. " " .. L.pad, bg = "#00000022"},
    footer_copy = smallBtn("Copy", "Copy these settings to the route clipboard (Ctrl/Cmd+C)"),
    footer_paste = smallBtn("Paste", "Load the route clipboard into these settings (Ctrl/Cmd+V)"),
    footer_defaults = smallBtn("Defaults", "Reset these settings to defaults"),
    footer_done = rtk.Button{"Done", tooltip = "Close (Esc)", h = L.h_small, padding = "2 14 3", fontscale = L.fs_btn, color = _colors.accent, textcolor = "#FFFFFF"},
    form = rtk.VBox{padding = (L.pad + 4) .. " " .. L.pad .. " " .. L.pad_v},
    row1 = rtk.HBox{spacing = 5, valign = "center"},  -- controls share one 20 px line
    volume_val = rtk.Text{"+0.00", w = 45, h = 20, valign = "center", halign = "center", padding = 3, border = "1px #777888", fontscale = fs(0.63)},
    pan_val = rtk.Text{"center", w = 35, h = 20, valign = "center", halign = "center", padding = 3, border = "1px #777888", fontscale = fs(0.63)},
    mute = rtk.Button{icon = "table_mute_off", w = 23, h = 20, padding = 0, surface = false, tooltip = "Mute", data__class = "routing_setting_field"},
    phase = rtk.Button{icon = "gen_phase_off", w = 10, h = 10, tooltip = "Reverse phase", padding = 0, circular = true, data__class = "routing_setting_field"},
    mono_stereo = rtk.Button{icon = "gen_mono_off", w = 23, h = 20, tooltip = "Mono/Stereo", padding = 0, surface = false, data__class = "routing_setting_field"},
    send_mode = rtk.OptionMenu{menu = {
        {"Postfader (Post-Pan)", id = 0},
        {"Prefader (Post-FX)", id = 3},
        {"PreX", id = 1}
      }, h = 20, padding = "0 0 4 4", spacing = 6, fontscale = fs(0.63), data__class = "routing_setting_field"},
    row2 = rtk.HBox{tmargin = L.row_gap},
    volume = rtk.Slider{"0.0", tooltip = "Volume", min = 0, max = 4, tmargin = 8, color = "orange", data__class = "routing_setting_field"},
    pan = rtk.Slider{tooltip = "Pan", min = -1, max = 1, tmargin = 8, color = "lightgreen", data__class = "routing_setting_field"},
    --pan_law = rtk.Slider{tooltip = "Pan Law", tmargin = 8},
    midi_velpan = rtk.Button{icon = "gen_midi_off", valign = "center", surface = false, tooltip = "Toggle Midi Volume/Pan", data__class = "routing_setting_field"},
    row3 = rtk.HBox{tmargin = L.row_gap},
    audio_block = rtk.VBox(),
    audio_channels = rtk.HBox{spacing = 3, valign = "center"},
    audio_txt = rtk.Text{"Audio:", bmargin = "2", fontscale = fs(0.63)},
    audio_src_channel = rtk.OptionMenu{menu = audio_channel_src_options, h = 20, margin = "-1 0 0 2", padding = "0 0 4 4", spacing = 6, fontscale = fs(0.63), data__class = "routing_setting_field", ref = "audio_src_channel"},
    audio_dest_channel = rtk.OptionMenu{h = 20, margin = "-1 0 0 2", padding = "0 0 4 4", spacing = 6, fontscale = fs(0.63), data__class = "routing_setting_field", ref = "audio_dest_channel"},
    audio_incrementing = rtk.CheckBox{"Increment audio source channels up", spacing = 3, fontscale = fs(0.63), valign = "center", data__class = "routing_setting_field"},
    midi_block = rtk.VBox{margin = "0 0 2 5", lpadding = 7, lborder = "1px #676767"},
    midi_channels = rtk.HBox{spacing = 3, valign = "center"},
    midi_txt = rtk.Text{"MIDI:", fontscale = fs(0.63)},
    midi_src = rtk.OptionMenu{menu = midi_channel_src_options, h = 20, margin = "-1 0 0 2", padding = "0 0 4 4", spacing = 6, fontscale = fs(0.63), ref = "midi_src", data__class = "routing_setting_field"},
    midi_dest = rtk.OptionMenu{menu = midi_channel_dest_options, h = 20, margin = "-1 0 0 2", padding = "0 0 4 4", spacing = 6, fontscale = fs(0.63), ref = "midi_dest", data__class = "routing_setting_field"},
    midi_incrementing = rtk.CheckBox{"Increment MIDI destination channels up", spacing = 3, fontscale = fs(0.63), valign = "center", data__class = "routing_setting_field", disabled = true}
  }
end


function defineAudioSrcChannelOptions()
  local audio_channel_submenu_mono_options, audio_channel_submenu_stereo_options, audio_channel_all_multichannel_options, audio_channel_src_options

  audio_channel_submenu_mono_options = getAudioChannelSubmenuMonoOrStereoOptions("mono")
  audio_channel_submenu_stereo_options = getAudioChannelSubmenuMonoOrStereoOptions("stereo")
  audio_channel_all_multichannel_options = getAudioChannelSubmenuMultichannelOptions()

  audio_channel_src_options = {
    {"None", id = "-1", data__channel_count = "0"},
    {"Mono source", submenu = audio_channel_submenu_mono_options},
    {"Stereo source", submenu = audio_channel_submenu_stereo_options},
    {
      label = "Multichannel source",
      submenu = audio_channel_all_multichannel_options
    }
  }

  return audio_channel_src_options
end


function getAudioChannelSubmenuMonoOrStereoOptions(mono_or_stereo)
  local audio_channel_submenu_basic_options, last_option_to_create, submenu_audio_channel_selected, submenu_audio_option_label, submenu_audio_option_val, submenu_channel_count

  audio_channel_submenu_basic_options = {}
  last_option_to_create = getLastOptionToCreate(mono_or_stereo)

  for i = 0, last_option_to_create do
    submenu_audio_channel_selected = i + 1
    submenu_audio_option_label, submenu_audio_option_val, submenu_channel_count = getAudioChannelSubmenuOptionInfo(mono_or_stereo, submenu_audio_channel_selected, i)

    audio_channel_submenu_basic_options[submenu_audio_channel_selected] = {
      label = tostring(submenu_audio_option_label),
      id = tostring(submenu_audio_option_val),
      data__channel_count = submenu_channel_count
    }

    if i == last_option_to_create then
      audio_channel_submenu_basic_options[submenu_audio_channel_selected].data__is_highest_option = true
    end
  end

  return audio_channel_submenu_basic_options
end


function getLastOptionToCreate(mono_or_stereo)
  local last_option_to_create

  if mono_or_stereo == "mono" then
    last_option_to_create = _constant.reaper_max_track_channels - 1

  elseif mono_or_stereo == "stereo" then
    last_option_to_create = _constant.reaper_max_track_channels - 2
  end

  return last_option_to_create
end


function getAudioChannelSubmenuOptionInfo(mono_or_stereo, submenu_audio_channel_selected, submenu_option_idx)
  local submenu_audio_option_label, submenu_audio_option_val, submenu_channel_count

  if mono_or_stereo == "mono" then
    submenu_audio_option_label = submenu_audio_channel_selected
    submenu_audio_option_val = _api.channels.mono_base + submenu_option_idx
    submenu_channel_count = 1

  elseif mono_or_stereo == "stereo" then
    submenu_audio_option_label = submenu_audio_channel_selected .. "/" .. submenu_audio_channel_selected + 1
    submenu_audio_option_val = submenu_option_idx
    submenu_channel_count = 2
  end

  return submenu_audio_option_label, submenu_audio_option_val, submenu_channel_count
end


function getAudioChannelSubmenuMultichannelOptions()
  local audio_channel_all_multichannel_options, multichannel_count_options, submenu_audio_channel_selected, audio_channel_submenu_multichannel_subsubmenu_options_label, audio_channel_submenu_multichannel_subsubmenu_options

  audio_channel_all_multichannel_options = {}
  multichannel_count_options = (_constant.reaper_max_track_channels - 2) / 2

  for i = 1, multichannel_count_options do
    submenu_audio_channel_selected = (i + 1) * 2
    audio_channel_submenu_multichannel_subsubmenu_options_label = submenu_audio_channel_selected .. " channels"
    audio_channel_submenu_multichannel_subsubmenu_options = getAudioChannelSubmenuMultichannelSubsubmenuOptions(submenu_audio_channel_selected, i, multichannel_count_options)

    audio_channel_all_multichannel_options[i] = {
      label = audio_channel_submenu_multichannel_subsubmenu_options_label,
      submenu = audio_channel_submenu_multichannel_subsubmenu_options
    }
  end

  return audio_channel_all_multichannel_options
end


function getAudioChannelSubmenuMultichannelSubsubmenuOptions(submenu_audio_channel_selected, multichannel_count_option_idx, multichannel_count_options)
  local multichannel_choices_count, audio_channel_submenu_multichannel_subsubmenu_options, multichannel_option_id_val

  multichannel_choices_count = _constant.reaper_max_track_channels - submenu_audio_channel_selected
  audio_channel_submenu_multichannel_subsubmenu_options = {}

  for i = 0, multichannel_choices_count do
    multichannel_option_id_val = (_api.channels.src.multichannel.addl * (submenu_audio_channel_selected // 2) ) + i

    audio_channel_submenu_multichannel_subsubmenu_options[i+1] = {
      label = (i+1) .. "-" .. (i + submenu_audio_channel_selected),
      id = tostring(multichannel_option_id_val),
      data__channel_count = submenu_audio_channel_selected
    }

    if multichannel_count_option_idx == multichannel_count_options then
      audio_channel_submenu_multichannel_subsubmenu_options[i+1].data__is_highest_option = true
    end
  end

  return audio_channel_submenu_multichannel_subsubmenu_options
end


function deepTableCopy( original, copies )
  if type( original ) ~= 'table' then return original end
  copies = copies or {}
  if copies[original] then return copies[original] end
  local copy = {}
  copies[original] = copy
  for key, value in pairs( original ) do
      local dc_key, dc_value = deepTableCopy( key, copies ), deepTableCopy( value, copies )
      copy[dc_key] = dc_value
  end
  setmetatable(copy, deepTableCopy( getmetatable( original ), copies) )
  return copy
end


function defineMIDIChannelOptions()
  local midi_channel_submenu_bus_options, midi_channel_submenu_bus_option_val, midi_channel_src_options, midi_channel_rcv_options

  midi_channel_src_options = {
    {
      label = "None",
      id = -1 .. "/" .. -1
    },
    {
      label = "All",
      id = 0 .. "/" .. 0,
      data__is_highest_option = true
    }
  }

  for i = 3, 18 do
    midi_channel_src_options[i] = {
      label = tostring(i-2),
      id = 0 .. "/" .. i-2
    }

    if i == 18 then
      midi_channel_src_options[i].data__is_highest_option = true
    end
  end

  for i = 19, 34 do
    midi_channel_submenu_bus_options = {
      {
        label = "B" .. i-18 .. " (all channels)",
        id = i-18 .. "/" .. 0
      }
    }

    for j = 1, 16 do
      midi_channel_submenu_bus_option_val = i-18 .. "/" .. j

      midi_channel_submenu_bus_options[j + 1] = {
        label = midi_channel_submenu_bus_option_val,
        id = midi_channel_submenu_bus_option_val
      }

      if j == 16 then
        midi_channel_submenu_bus_options[j + 1].data__is_highest_option = true
      end
    end

    midi_channel_src_options[i] = {
      label = "Bus " .. i-18,
      submenu = midi_channel_submenu_bus_options
    }
  end

  midi_channel_rcv_options = deepTableCopy(midi_channel_src_options)

  table.remove(midi_channel_rcv_options, 1)

  return midi_channel_src_options, midi_channel_rcv_options
end


function gatherRoutingSettingsFormFields()

  if not _state.routing.settings_objs.form_fields then
    _state.routing.settings_objs.form_fields = {}

    for routing_setting_obj_name, routing_setting_obj_value in pairs(_state.routing.settings_objs) do

      if routing_setting_obj_value.data__class == "routing_setting_field" then
        _state.routing.settings_objs.form_fields[routing_setting_obj_name] = routing_setting_obj_value
      end
    end
  end
end


function setRoutingSettingsPopupEventHandlers()

  _state.routing.settings_objs.popup.onclose = function()

    if not _state.routing.settings_objs.all_values then
      _state.routing.settings_objs.all_values = {}
    end

    getSetRoutingSettingsValues("get")
    refreshSettingsSummary()
  end

  _state.routing.settings_objs.popup.onkeypress = function(self, event)

    if not event.handled and event.keycode == rtk.keycodes.ESCAPE then
      event:set_handled(self)
      _state.routing.settings_objs.popup:close()
    end
  end
end


function getSetRoutingSettingsValues(get_set, new_routing_settings_values)
  local this_form_field_class, this_field_is_type_value, this_field_is_type_selected, routing_setting_field

  if get_set == "set" then
    applyFormValues(new_routing_settings_values)
    return
  end

  for routing_setting_name, routing_setting_value in pairs(_state.routing.settings_objs.form_fields) do
    this_form_field_class = routing_setting_value.class.name
    this_field_is_type_value = this_form_field_class ~= "rtk.OptionMenu"
    this_field_is_type_selected = this_form_field_class == "rtk.OptionMenu"
    routing_setting_field = _state.routing.settings_objs[routing_setting_name]

    if get_set == "get" then
      getRoutingSettingsValue(this_field_is_type_value, routing_setting_field, this_field_is_type_selected, routing_setting_name)
    end
  end
end


-- Set form fields in a stable order: source dropdowns rebuild/reset their destination
-- dropdowns, so destinations must be set after their sources.
function applyFormValues(values)
  local so = _state.routing.settings_objs
  if not values then return end

  local function setValue(name)
    if values[name] ~= nil then so[name]:attr("value", values[name]) end
  end

  local function setSelected(name)
    if values[name] ~= nil then
      local v = values[name]
      if type(v) == "number" then v = math.floor(v) end
      -- older versions stored multichannel ids as "2050.0"
      if type(v) == "string" and v:match("^%-?%d+%.0$") then v = v:sub(1, -3) end
      so[name]:select(v, false)
    end
  end

  for _, name in ipairs({"mute", "phase", "mono_stereo", "midi_velpan", "volume", "pan"}) do
    setValue(name)
  end
  setSelected("send_mode")

  setSelected("audio_src_channel")
  handleChannelDropdown(so.audio_src_channel)  -- rebuilds audio_dest_channel menu
  setSelected("audio_dest_channel")

  setSelected("midi_src")
  handleChannelDropdown(so.midi_src)
  setSelected("midi_dest")
  handleIncrementingToggle(so.midi_dest, "midi")

  -- Incrementing boxes last: the dropdown handlers above may disable/reset them
  for _, name in ipairs({"audio_incrementing", "midi_incrementing"}) do
    if values[name] ~= nil and not so[name].disabled then setValue(name) end
  end

  updateRoutingSettingsBtns()
end


function getRoutingSettingsValue(this_field_is_type_value, routing_setting_field, this_field_is_type_selected, routing_setting_name)
  local this_form_field_value

  if this_field_is_type_value then
    this_form_field_value = routing_setting_field.value

  elseif this_field_is_type_selected then
    this_form_field_value = routing_setting_field.selected_id
  end

  _state.routing.settings_objs.all_values[routing_setting_name] = this_form_field_value
end


function setRoutingSettingsFormEventHandlers()
  local new_volume_value

  _state.routing.settings_objs.close_btn.onclick = function(self)
    _state.routing.settings_objs.popup:close()
  end

  _state.routing.settings_objs.footer_done.onclick = function()
    _state.routing.settings_objs.popup:close()
  end

  _state.routing.settings_objs.footer_copy.onclick = function()
    copyFromSettingsForm()
  end

  _state.routing.settings_objs.footer_paste.onclick = function()
    pasteIntoSettingsForm(_route_param_groups.all)
  end

  _state.routing.settings_objs.footer_defaults.onclick = function()
    populateRoutingSettingsFormValues("reset")
    setStatus("Send settings reset to defaults.")
  end

  _state.routing.settings_objs.mute.onclick = function(self)
    toggleBtnState(self, "table_mute")
  end

  _state.routing.settings_objs.phase.onclick = function(self)
    toggleBtnState(self, "gen_phase")
  end

  _state.routing.settings_objs.mono_stereo.onclick = function(self)
    toggleBtnState(self, "gen_mono")
  end

  _state.routing.settings_objs.volume.onchange = function(self)
    new_volume_value = getAPIVolume(self.value)

    _state.routing.settings_objs.volume_val:attr("text", reaper.mkvolstr("", new_volume_value))
  end

  _state.routing.settings_objs.pan.onchange = function(self)
    _state.routing.settings_objs.pan_val:attr("text", reaper.mkpanstr("", self.value))
  end

  _state.routing.settings_objs.midi_velpan.onclick = function(self)
    toggleBtnState(self, "gen_midi")
  end

  _state.routing.settings_objs.audio_src_channel.onchange = function(self)
    handleChannelDropdown(self)
  end

  _state.routing.settings_objs.midi_src.onchange = function(self)
    handleChannelDropdown(self)
  end

  _state.routing.settings_objs.midi_dest.onchange = function(self)
    handleIncrementingToggle(self, "midi")
  end
end


function toggleBtnState(btn, img_filename_base)

  if btn.value == 0 then
    btn:attr("value", 1)
    btn:attr("icon", img_filename_base .. "_on")

  elseif btn.value == 1 then
    btn:attr("value", 0)
    btn:attr("icon", img_filename_base .. "_off")
  end
end


function handleChannelDropdown(active_dropdown)
  local none_value, affected_dropdown, arrow_ref, affected_incrementing_checkbox, active_dropdown_is_audio

  if active_dropdown.ref == "audio_src_channel" then
    none_value, affected_dropdown, arrow_ref, affected_incrementing_checkbox, active_dropdown_is_audio = getAudioSrcChannelDropdownInfo(active_dropdown)

    handleIncrementingToggle(active_dropdown, "audio")

  elseif active_dropdown.ref == "midi_src" then
    none_value, affected_dropdown, arrow_ref, affected_incrementing_checkbox = getMidiSrcChannelDropdownInfo()
  end

  toggleChannelDropdown(active_dropdown, none_value, affected_dropdown, arrow_ref, affected_incrementing_checkbox, active_dropdown_is_audio)
end


function getAudioSrcChannelDropdownInfo(active_dropdown)
  local none_value, affected_dropdown, arrow_ref, affected_incrementing_checkbox, active_dropdown_is_audio

  none_value = "-1"
  affected_dropdown = _state.routing.settings_objs.audio_dest_channel
  arrow_ref = "audio_arrow"
  affected_incrementing_checkbox = _state.routing.settings_objs.audio_incrementing
  active_dropdown_is_audio = true

  return none_value, affected_dropdown, arrow_ref, affected_incrementing_checkbox, active_dropdown_is_audio
end


function handleIncrementingToggle(active_dropdown, midi_or_audio)
  local this_incrementing_box

  if midi_or_audio == "midi" then
    this_incrementing_box = _state.routing.settings_objs.midi_incrementing

  elseif midi_or_audio == "audio" then
    this_incrementing_box = _state.routing.settings_objs.audio_incrementing
  end

  if active_dropdown.selected_item then

    if active_dropdown.selected_item.data__is_highest_option then
      this_incrementing_box:attr("value", false)
      this_incrementing_box:attr("disabled", true)

    else
      this_incrementing_box:attr("disabled", false)
    end
  end
end


function getMidiSrcChannelDropdownInfo()
  local none_value, affected_dropdown, arrow_ref, affected_incrementing_checkbox

  none_value = "-1/-1"
  affected_dropdown = _state.routing.settings_objs.midi_dest
  arrow_ref = "midi_arrow"
  affected_incrementing_checkbox = _state.routing.settings_objs.midi_incrementing

  return none_value, affected_dropdown, arrow_ref, affected_incrementing_checkbox
end


function toggleChannelDropdown(active_dropdown, none_value, affected_dropdown, arrow_ref, affected_incrementing_checkbox, active_dropdown_is_audio)

  if active_dropdown.selected_id == none_value then
    affected_dropdown:attr("ghost", true)
    affected_dropdown.refs[arrow_ref]:attr("ghost", true)
    affected_incrementing_checkbox:hide()

  else
    affected_dropdown:attr("ghost", false)
    affected_dropdown.refs[arrow_ref]:attr("ghost", false)
    affected_incrementing_checkbox:show()

    if active_dropdown_is_audio then
      populateAudioDestChannelDefaultOptions(true)
    end
  end
end


function populateAudioDestChannelDefaultOptions(this_is_refresh)
  local multichannel_choices_count, src_multichannel_is_selected, src_selected_channel_count, target_tracks_channel_count_min, audio_dest_channel_all_options, new_dest_selected_idx

  multichannel_choices_count, src_multichannel_is_selected, src_selected_channel_count, target_tracks_channel_count_min = getAudioDestChannelInfo(this_is_refresh)
  audio_dest_channel_all_options = createAudioDestChannelAllOptions(multichannel_choices_count, src_multichannel_is_selected, src_selected_channel_count, target_tracks_channel_count_min)

  _state.routing.settings_objs.audio_dest_channel:attr("menu", audio_dest_channel_all_options)

  new_dest_selected_idx = tostring(_api.channels.dest.default)

  _state.routing.settings_objs.audio_dest_channel:select(new_dest_selected_idx)
end


function getAudioDestChannelInfo(this_is_refresh)
  local src_selected_channel_count, src_multichannel_is_selected, target_tracks_channel_count_min, multichannel_choices_count

  src_selected_channel_count = getSrcSelectedChannelCount()
  src_multichannel_is_selected = src_selected_channel_count > 2
  target_tracks_channel_count_min = this_is_refresh and _constant.reaper_max_track_channels or getTargetTracksLeastChannelCount()
  multichannel_choices_count = src_multichannel_is_selected and target_tracks_channel_count_min - src_selected_channel_count + 1 or target_tracks_channel_count_min - 1

  return multichannel_choices_count, src_multichannel_is_selected, src_selected_channel_count, target_tracks_channel_count_min
end


function getSrcSelectedChannelCount()
  local src_selected_option, src_channel_option_val, src_is_stereo, src_is_mono, src_selected_channel_count

  src_selected_option = tonumber(_state.routing.settings_objs.audio_src_channel.selected_id)

  if not src_selected_option then
    src_selected_option = _api.channels.src.stereo.default
  end

  src_channel_option_val = src_selected_option / _api.channels.mono_base
  src_is_stereo = src_channel_option_val < 1
  src_is_mono = src_channel_option_val >= 1 and src_channel_option_val < 2

  if src_is_stereo then
    src_selected_channel_count = 2

  elseif src_is_mono then
    src_selected_channel_count = 1

  else
    src_selected_channel_count = src_channel_option_val * 2
  end

  return math.floor(src_selected_channel_count)
end


function getTargetTracksLeastChannelCount()
  local target_tracks, target_tracks_least_channel_count, this_target_track_api_idx, this_target_track, this_target_track_channel_count

  getCurrentTargetTrackChoices()

  target_tracks = _state.routing.options_objs.target_track_choices
  target_tracks_least_channel_count = _constant.reaper_max_track_channels

  if target_tracks then

    for i = 1, #target_tracks do
      this_target_track_api_idx = target_tracks[i].idx - 1
      this_target_track = reaper.GetTrack(_api.current_project, this_target_track_api_idx)
      this_target_track_channel_count = reaper.GetMediaTrackInfo_Value(this_target_track, _api.track.channel_count)

      if this_target_track_channel_count < target_tracks_least_channel_count then
        target_tracks_least_channel_count = this_target_track_channel_count
      end
    end
  end

  return target_tracks_least_channel_count
end


function createAudioDestChannelAllOptions(multichannel_choices_count, src_multichannel_is_selected, src_selected_channel_count, target_tracks_channel_count_min)
  local audio_dest_channel_all_options, mono_option_idx, mono_option_val

  audio_dest_channel_all_options = createAudioDestStereoOrMultichannelChoices(multichannel_choices_count, src_multichannel_is_selected, src_selected_channel_count)
  multichannel_choices_count = math.floor(multichannel_choices_count)

  for i = 0, target_tracks_channel_count_min-1 do
    mono_option_idx = multichannel_choices_count + i + 1
    mono_option_val = _api.channels.mono_base + i

    audio_dest_channel_all_options[mono_option_idx] = {
      label = tostring(i+1),
      id = tostring(mono_option_val),
      data__channel_count = 1
    }
  end

  return audio_dest_channel_all_options
end


function createAudioDestStereoOrMultichannelChoices(multichannel_choices_count, src_multichannel_is_selected, src_selected_channel_count)
  local audio_dest_channel_all_options, divider, audio_dest_multichannel_option_label, multichannel_option_id_val, audio_dest_multichannel_option_channel_count

  audio_dest_channel_all_options = {}
  divider = getAudioChannelChoiceDivider(src_selected_channel_count)

  for i = 0, multichannel_choices_count do
    audio_dest_multichannel_option_label, multichannel_option_id_val, audio_dest_multichannel_option_channel_count = getMultichannelOrStereoOptionInfo(src_multichannel_is_selected, src_selected_channel_count, divider, i)

    audio_dest_channel_all_options[i+1] = {
      label = audio_dest_multichannel_option_label,
      id = tostring(multichannel_option_id_val),
      data__channel_count = audio_dest_multichannel_option_channel_count
    }
  end

  return audio_dest_channel_all_options
end


function getAudioChannelChoiceDivider(src_selected_channel_count)
  local this_is_stereo, divider

  this_is_stereo = src_selected_channel_count == 2
  divider = this_is_stereo and "/" or "-"

  return divider
end


function getMultichannelOrStereoOptionInfo(src_multichannel_is_selected, src_selected_channel_count, divider, multichannel_choice_idx)
  local mono_or_stereo_is_selected, multichannel_lowest_in_option, multichannel_highest_in_option, audio_dest_multichannel_option_label, multichannel_option_id_val, audio_dest_multichannel_option_channel_count

  mono_or_stereo_is_selected = not src_multichannel_is_selected
  multichannel_lowest_in_option = multichannel_choice_idx + 1

  if src_multichannel_is_selected then
    multichannel_highest_in_option = src_selected_channel_count + multichannel_choice_idx

  elseif mono_or_stereo_is_selected then
    multichannel_highest_in_option = multichannel_choice_idx + 2
  end

  multichannel_highest_in_option = math.floor(multichannel_highest_in_option)
  audio_dest_multichannel_option_label = multichannel_lowest_in_option .. divider .. multichannel_highest_in_option
  multichannel_option_id_val = multichannel_choice_idx
  audio_dest_multichannel_option_channel_count = multichannel_highest_in_option - multichannel_lowest_in_option + 1

  return audio_dest_multichannel_option_label, multichannel_option_id_val, audio_dest_multichannel_option_channel_count
end


function reaperFade(ftype,t,s,e,c,inout)
  local reaperFade1, reaperFade2, reaperFade3, reaperFadeg, reaperFadeh, reaperFadeIn, x, ret

  reaperFade1 = function(x,c) return c<0 and (1+c)*x*(2-x)-c*(1-(1-x)^8)^.5 or (1-c)*x*(2-x)+c*x^4 end
  reaperFade2 = function(x,c) return c<0 and (1+c)*x-c*(1-(1-x)^2) or (1-c)*x+c*x^2 end
  reaperFade3 = function(x,c) return c<0 and (1+c)*x-c*(1-(1-x)^4) or (1-c)*x+c*x^4 end
  reaperFadeg = function(x,t) return t==.5 and x or ((x*(1-2*t)+t^2)^.5-t)/(1-2*t) end
  reaperFadeh = function(x,t) local g = reaperFadeg(x,t); return (2*t-1)*g^2+(2-2*t)*g end

  reaperFadeIn = {
    function(x,c) c=c or 0; return reaperFade3(x,c) end,
    function(x,c) c=c or 0; return reaperFade1(x,c) end,
    function(x,c) c=c or 1; return reaperFade2(x,c) end,
    function(x,c) c=c or -1; return reaperFade3(x,c) end,
    function(x,c) c=c or 1; return reaperFade3(x,c) end,
    function(x,c) c=c or 0; local x1 = reaperFadeh(x,.25*(c+2)); return (3-2*x1)*x1^2 end,
    function(x,c) c=c or 0; local x2 = reaperFadeh(x,(5*c+8)/16); return x2<=.5 and 8*x2^4 or 1-8*(1-x2)^4 end,
  }

  --
  -- Returns 0 to 1
  --
  -- ftype is the REAPER fade type 1-7 (Note: not 0-6 here)
  -- t - time code where fade is calculated
  -- s - time code of fade start
  -- e - time code of fade end
  -- c - REAPER curvature parameter (D_FADEINDIR, D_FADEOUTDIR)
  -- inout - true for fade in, false for fade out
  --
  if e<=s then return 1 end
  t = t<s and s or t>e and e or t
  x = (t-s)/(e-s)
  ret = reaperFadeIn[ftype](table.unpack(inout and {x,c} or {1-x,-c}))
  return ret * 4
end


function getAPIVolume(slider_value)

  return reaperFade(5, slider_value, 0, 4, 1, true)
end


function populateRoutingSettingsFormValues(reset)
  local new_routing_settings_values

  if _state.routing.settings_objs then
    new_routing_settings_values = (_state.routing.settings_objs.all_values and reset ~= "reset") and _state.routing.settings_objs.all_values or _constant.default_routing_settings_values

    getSetRoutingSettingsValues("set", new_routing_settings_values)

    if reset == "reset" then
      updateRoutingSettingsBtns(reset)

      if _state.routing.settings_objs.all_values then
        getSetRoutingSettingsValues("get")
      end
    end
  end
end


function updateRoutingSettingsBtns(reset)
  local all_btn_img_filename_bases, this_btn, this_btn_value, new_btn_img_base_state

  all_btn_img_filename_bases = {
    mute = "table_mute",
    phase = "gen_phase",
    mono_stereo = "gen_mono",
    midi_velpan = "gen_midi"
  }

  for btn_name, btn_img_base in pairs(all_btn_img_filename_bases) do
    this_btn = _state.routing.settings_objs[btn_name]
    this_btn_value = this_btn.value
    new_btn_img_base_state = (reset == "reset" or this_btn_value == 0) and "_off" or "_on"

    this_btn:attr("icon", btn_img_base .. new_btn_img_base_state)
  end
end


function populateRoutingSettingsPopup()
  _state.routing.settings_objs.content:add(_state.routing.settings_objs.close_btn)
  _state.routing.settings_objs.content:add(_state.routing.settings_objs.title)
  _state.routing.settings_objs.row1:add(_state.routing.settings_objs.volume_val)
  _state.routing.settings_objs.row1:add(_state.routing.settings_objs.pan_val)
  _state.routing.settings_objs.row1:add(_state.routing.settings_objs.mute)
  _state.routing.settings_objs.row1:add(_state.routing.settings_objs.phase)
  _state.routing.settings_objs.row1:add(_state.routing.settings_objs.mono_stereo)
  _state.routing.settings_objs.row1:add(_state.routing.settings_objs.send_mode)
  _state.routing.settings_objs.form:add(_state.routing.settings_objs.row1)
  _state.routing.settings_objs.row2:add(_state.routing.settings_objs.volume, {expand = 3})
  _state.routing.settings_objs.row2:add(_state.routing.settings_objs.pan, {expand = 1.25})
  -- _state.routing.settings_objs.row2:add(_state.routing.settings_objs.panlaw)
  _state.routing.settings_objs.row2:add(_state.routing.settings_objs.midi_velpan)
  _state.routing.settings_objs.form:add(_state.routing.settings_objs.row2)
  _state.routing.settings_objs.audio_channels:add(_state.routing.settings_objs.audio_txt)
  _state.routing.settings_objs.audio_channels:add(_state.routing.settings_objs.audio_src_channel)
  _state.routing.settings_objs.audio_channels:add(rtk.Text{_unicode.right_arrow, bmargin = "3", fontscale = fs(1.2), ref = "audio_arrow"})
  _state.routing.settings_objs.audio_channels:add(_state.routing.settings_objs.audio_dest_channel)
  _state.routing.settings_objs.audio_block:add(_state.routing.settings_objs.audio_channels)
  _state.routing.settings_objs.audio_block:add(_state.routing.settings_objs.audio_incrementing)
  _state.routing.settings_objs.midi_channels:add(_state.routing.settings_objs.midi_txt)
  _state.routing.settings_objs.midi_channels:add(_state.routing.settings_objs.midi_src)
  _state.routing.settings_objs.midi_channels:add(rtk.Text{_unicode.right_arrow, bmargin = "3", fontscale = fs(1.2), ref = "midi_arrow"})
  _state.routing.settings_objs.midi_channels:add(_state.routing.settings_objs.midi_dest)
  _state.routing.settings_objs.midi_block:add(_state.routing.settings_objs.midi_channels)
  _state.routing.settings_objs.midi_block:add(_state.routing.settings_objs.midi_incrementing)
  _state.routing.settings_objs.row3:add(_state.routing.settings_objs.audio_block)
  _state.routing.settings_objs.row3:add(_state.routing.settings_objs.midi_block)
  _state.routing.settings_objs.form:add(_state.routing.settings_objs.row3)
  _state.routing.settings_objs.content:add(_state.routing.settings_objs.form)
  _state.routing.settings_objs.footer:add(_state.routing.settings_objs.footer_copy)
  _state.routing.settings_objs.footer:add(_state.routing.settings_objs.footer_paste)
  _state.routing.settings_objs.footer:add(_state.routing.settings_objs.footer_defaults)
  _state.routing.settings_objs.footer:add(rtk.Box.FLEXSPACE)
  _state.routing.settings_objs.footer:add(_state.routing.settings_objs.footer_done)
  _state.routing.settings_objs.content:add(_state.routing.settings_objs.footer)
  _state.routing.settings_objs.popup:attr("child", _state.routing.settings_objs.content)
end


-- true: check every *visible* row (never hidden source tracks); false: uncheck everything
function selectDeselectAllTargetTracks(select_deselect)
  if select_deselect and _ui_dirty then
    updateLineVisibility()
  end

  for j = 1, #_all_track_lines do
    local info = _all_track_lines[j]

    if not select_deselect or info.line.visible ~= false then
      if info.checkbox.value ~= select_deselect then
        info.checkbox:attr("value", select_deselect)
      end
    end
  end

  markDirty()
end


function submitRoutingOptionChanges()
  local o, count, action, rtype, past_verb

  o = _state.routing.options_objs

  getCurrentTargetTrackChoices()
  if #o.target_track_choices < 1 then return end

  -- Pick up edits from a still-open settings popup
  if _state.routing.settings_objs and _state.routing.settings_objs.popup.opened then
    _state.routing.settings_objs.all_values = _state.routing.settings_objs.all_values or {}
    getSetRoutingSettingsValues("get")
  end

  _state.enough_audio_channels_are_available = true
  _state.routing.option_choice.action, _state.routing.option_choice.type = getRoutingChoices()
  action, rtype = _state.routing.option_choice.action, _state.routing.option_choice.type

  if action == "add" and incrementingAudioChannelsExceedMax() then
    reaper.ShowMessageBox("You are trying to use more channels than the " .. _constant.reaper_max_track_channels .. " Reaper makes available. Change your source track selection and/or routing settings and try again.", "Too many channels", _api.msg_type_ok)
    return
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  count = addRemoveRouting()
  reaper.PreventUIRefresh(-1)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock(getUndoString(), -1)

  if count == 0 then
    setStatus("Nothing changed: no matching " .. rtype .. "s found.", "warn")
    return
  end

  if not _keep_open then
    o.window:close()
    return
  end

  past_verb = action == "add" and "Added " or "Removed "
  selectDeselectAllTargetTracks(false)
  refreshExistingRoutes()
  markDirty()
  setStatus(past_verb .. count .. " " .. plural(rtype, count) .. ".  (Undo with Ctrl/Cmd+Z in REAPER)")
end


-- Checked rows that are valid targets in the current mode
function getCurrentTargetTrackChoices()

  _state.routing.options_objs.target_track_choices = {}

  for i = 1, #_all_track_lines do
    local info = _all_track_lines[i]

    if info.checkbox.value and lineIsEligible(info) then

      table.insert(_state.routing.options_objs.target_track_choices, {
        idx = info.line.data__track_num,
        guid = info.track_guid
      })
    end
  end
end


-- Resolve a stored choice to a track (GUID first, so reordering tracks can't misfire)
function getTrackFromChoice(choice)
  local track = choice.guid and reaper.BR_GetMediaTrackByGUID(_api.current_project, choice.guid)

  if not trackIsValid(track) then
    track = reaper.GetTrack(_api.current_project, math.floor(choice.idx) - 1)
  end

  return trackIsValid(track) and track or nil
end


function getUndoString()
  local action_choice, type_choice, undo_string

  if _state.routing.option_choice.action == "add" then
    action_choice = "Add"

  elseif _state.routing.option_choice.action == "remove" then
    action_choice = "Remove"
  end

  if _state.routing.option_choice.type == "send" then
    type_choice = "send(s)"

  elseif _state.routing.option_choice.type == "receive" then
    type_choice = "receive(s)"
  end

  undo_string = _constant.brand.script .. ": " .. action_choice .. " " .. type_choice

  return undo_string
end


function setTargetTrackChoices(new_choices)
  local this_track_guid

  if new_choices then

    for i = 1, #new_choices do
      this_track_guid = new_choices[i].guid

      for j = 1, #_all_track_lines do
        local info = _all_track_lines[j]

        if info.line then
          local this_track_line_guid = info.track_guid

          if this_track_line_guid == this_track_guid then
            info.checkbox:attr("value", true)

            break
          end
        end
      end
    end
  end
end


-- Returns the number of routes created/removed
function addRemoveRouting()
  local this_selected_track, this_target_track, count

  count = 0

  if incrementingAudioChannelsExceedMax() then return 0 end

  for i = 1, #_state.tracks.selected do
    _state.tracks.selected.current_idx = i
    this_selected_track = _state.tracks.selected[i]

    for j = 1, #_state.routing.options_objs.target_track_choices do
      _state.tracks.target.current_idx = j
      this_target_track = getTrackFromChoice(_state.routing.options_objs.target_track_choices[j])

      if trackIsValid(this_selected_track) and this_target_track and this_target_track ~= this_selected_track then

        if _state.routing.option_choice.action == "add" then
          if addRouting(this_selected_track, this_target_track) then count = count + 1 end

        elseif _state.routing.option_choice.action == "remove" then
          count = count + removeRouting(this_selected_track, this_target_track)
        end
      end
    end
  end

  return count
end


function incrementingAudioChannelsExceedMax()
  local incrementing_channels_exceed_max, incrementing_is_enabled, dest_tracks_count, api_routing_src_idx, channel_count_type, routing_type, send_channel_count, addl_channels_above_count, src_track_top_channel_after_incrementing

  incrementing_channels_exceed_max = false

  if _state.routing.settings_objs then
    incrementing_is_enabled = _state.routing.settings_objs.audio_incrementing.value

    if incrementing_is_enabled then
      dest_tracks_count = getDestTracksCountFromUserSelection()
      api_routing_src_idx = 8
      channel_count_type, routing_type, send_channel_count, addl_channels_above_count = getAudioRoutingInfo(api_routing_src_idx, _state.routing.settings_objs.audio_src_channel.selected_id)

      src_track_top_channel_after_incrementing = addl_channels_above_count + (send_channel_count * dest_tracks_count)

      if src_track_top_channel_after_incrementing > _constant.reaper_max_track_channels then
        _state.enough_audio_channels_are_available = false
        incrementing_channels_exceed_max = true
      end
    end
  end

  return incrementing_channels_exceed_max
end


function getDestTracksCountFromUserSelection()
  local dest_tracks, this_target_track_api_idx, this_target_track

  if _state.routing.option_choice.type == "send" then
    dest_tracks = {}

    for i = 1, #_state.routing.options_objs.target_track_choices do
      this_target_track_api_idx = _state.routing.options_objs.target_track_choices[i].idx - 1
      this_target_track = reaper.GetTrack(_api.current_project, this_target_track_api_idx)

      table.insert(dest_tracks, this_target_track)
    end

  elseif _state.routing.option_choice.type == "receive" then
    dest_tracks = _state.tracks.selected
  end

  return #dest_tracks
end


function addRouting(selected_track, target_track)

  local src_track, dest_track

  if _state.routing.option_choice.type == "send" then
    src_track, dest_track = selected_track, target_track

  elseif _state.routing.option_choice.type == "receive" then
    src_track, dest_track = target_track, selected_track
  end

  _state.routing.newly_created_idx = reaper.CreateTrackSend(src_track, dest_track)

  if _state.routing.newly_created_idx < 0 then return false end

  if _state.routing.settings_objs and _state.routing.settings_objs.all_values then
    applyRoutingSettings(src_track, dest_track)
  end

  return true
end


function applyRoutingSettings(src_track, dest_track)
  local routing_settings_api_objs_converted_names, is_pan_law

  routing_settings_api_objs_converted_names = getRoutingSettingsAPIObjsConvertedNames()

  for routing_setting_idx = 1, 14 do
    is_pan_law = routing_setting_idx == 6

    if not is_pan_law then
      processRoutingSetting(routing_setting_idx, routing_settings_api_objs_converted_names, src_track, dest_track)
    end
  end
end


function getRoutingSettingsAPIObjsConvertedNames()
  local routing_settings_api_objs_converted_names, routing_settings_api_obj_names

  routing_settings_api_objs_converted_names = {}

  for i = 1, 14 do

    routing_settings_api_obj_names = {
      "mute",
      "phase",
      "mono_stereo",
      "volume",
      "pan",
      "pan_law",
      "send_mode",
      "audio_src_channel",
      "audio_dest_channel",
      "midi_src",
      "midi_dest",
      "midi_src",
      "midi_dest",
      "midi_velpan"
    }

    routing_settings_api_objs_converted_names[_api.all_routing_settings[i]] = routing_settings_api_obj_names[i]
  end

  return routing_settings_api_objs_converted_names
end


function processRoutingSetting(routing_setting_idx, routing_settings_api_objs_converted_names, src_track, dest_track)
  local is_volume, is_audio_channel, is_midi_channel, is_midi_dest_channel, is_midi_bus, this_api_routing_setting, this_routing_obj_name, this_routing_obj_value, this_user_routing_setting_value

  is_volume = routing_setting_idx == 4
  is_audio_channel = routing_setting_idx == 8 or routing_setting_idx == 9
  is_midi_channel = routing_setting_idx == 10 or routing_setting_idx == 11
  is_midi_dest_channel = routing_setting_idx == 11
  is_midi_bus = routing_setting_idx == 12 or routing_setting_idx == 13
  this_api_routing_setting = _api.all_routing_settings[routing_setting_idx]
  this_routing_obj_name = routing_settings_api_objs_converted_names[this_api_routing_setting]
  this_routing_obj_value = _state.routing.settings_objs.all_values[this_routing_obj_name]

  if is_volume then
    this_user_routing_setting_value = getAPIVolume(this_routing_obj_value)

  elseif is_midi_channel then
    this_user_routing_setting_value = stripOutMidiData(this_routing_obj_value, "bus")

    if is_midi_dest_channel then
      this_user_routing_setting_value = incrementChannels("midi", this_user_routing_setting_value)
    end

  elseif is_midi_bus then
    this_user_routing_setting_value = stripOutMidiData(this_routing_obj_value, "channel")

  elseif is_audio_channel then
    this_user_routing_setting_value = processAudioRoutingSetting(routing_setting_idx, this_routing_obj_value, src_track, dest_track)

  else
    this_user_routing_setting_value = this_routing_obj_value
  end

  reaper.BR_GetSetTrackSendInfo(src_track, _api.routing.category.send, _state.routing.newly_created_idx, this_api_routing_setting, _api.routing.set_new_value, this_user_routing_setting_value)
end


function stripOutMidiData(val, channel_or_bus)
  local data_to_strip

  if channel_or_bus == "channel" then
    data_to_strip = _regex.routing.midi.channel

  elseif channel_or_bus == "bus" then
    data_to_strip = _regex.routing.midi.bus
  end

  return string.gsub(val, data_to_strip, "")
end


function processAudioRoutingSetting(routing_setting_idx, this_routing_obj_value, src_track, dest_track)
  local is_audio_src_channel, this_user_routing_setting_value

  is_audio_src_channel = routing_setting_idx == 8
  this_user_routing_setting_value = this_routing_obj_value

  if is_audio_src_channel then
    this_user_routing_setting_value = incrementChannels("audio", this_user_routing_setting_value, routing_setting_idx, src_track)
  end

  createRequiredAudioChannels(routing_setting_idx, this_user_routing_setting_value, src_track, dest_track)

  return this_user_routing_setting_value
end


function incrementChannels(midi_or_audio, this_user_routing_setting_value, routing_setting_idx, src_track)
  local incrementing_is_enabled, num_to_increment_channels_by

  this_user_routing_setting_value = tonumber(this_user_routing_setting_value)

  if midi_or_audio == "midi" then
    incrementing_is_enabled = _state.routing.settings_objs.midi_incrementing.value

  elseif midi_or_audio == "audio" then
    incrementing_is_enabled = _state.routing.settings_objs.audio_incrementing.value
  end

  if incrementing_is_enabled then
    num_to_increment_channels_by = getNumToIncrementChannelsBy(midi_or_audio, routing_setting_idx)
    this_user_routing_setting_value = this_user_routing_setting_value + num_to_increment_channels_by

    if midi_or_audio == "midi" and this_user_routing_setting_value > _api.channels.midi.max_value then
      this_user_routing_setting_value = _api.channels.midi.max_value

    elseif midi_or_audio == "audio" then
      this_user_routing_setting_value = getMoreAudioChannelsToIncrement(this_user_routing_setting_value, routing_setting_idx, src_track)
    end
  end

  return this_user_routing_setting_value
end


function getNumToIncrementChannelsBy(midi_or_audio, routing_setting_idx)
  local send_or_receive, src_track_idx, dest_track_idx, num_to_increment_channels_by, channel_count_type, routing_type, channel_count

  send_or_receive = _state.routing.option_choice.type

  if midi_or_audio == "midi" then

    if send_or_receive == "send" then
      src_track_idx = _state.tracks.selected.current_idx

    elseif send_or_receive == "receive" then
      src_track_idx = _state.tracks.target.current_idx
    end

    num_to_increment_channels_by = src_track_idx - 1

  elseif midi_or_audio == "audio" then

    if send_or_receive == "send" then
      dest_track_idx = _state.tracks.target.current_idx

    elseif send_or_receive == "receive" then
      dest_track_idx = _state.tracks.selected.current_idx
    end

    channel_count_type, routing_type, channel_count = getAudioRoutingInfo(routing_setting_idx)

    if channel_count_type == "stereo" then
      num_to_increment_channels_by = (dest_track_idx * 2) - 2

    elseif channel_count_type == "mono" then
      num_to_increment_channels_by = dest_track_idx - 1

    elseif channel_count_type == "multichannel" then
      num_to_increment_channels_by = (dest_track_idx * channel_count) - channel_count
    end
  end

  return num_to_increment_channels_by
end


function getAudioRoutingInfo(routing_setting_idx, routing_setting_value)
  local routing_type, channel_count, channel_count_type, addl_channels_above_count

  routing_type, channel_count = getAudioRoutingTypeAndChannelCount(routing_setting_idx)
  channel_count_type = getAudioRoutingChannelCountType(channel_count)
  addl_channels_above_count = getAudioRoutingChannelsAboveCount(routing_setting_value, channel_count_type, channel_count, routing_type)

  return channel_count_type, routing_type, channel_count, addl_channels_above_count
end


function getAudioRoutingTypeAndChannelCount(routing_setting_idx)
  local this_is_src, this_is_dest, routing_type, channel_count

  this_is_src = routing_setting_idx == 8
  this_is_dest = routing_setting_idx == 9

  if this_is_src then
    routing_type = "src"
    channel_count = _state.routing.settings_objs.audio_src_channel.selected_item.data__channel_count

  elseif this_is_dest then
    routing_type = "dest"
    channel_count = _state.routing.settings_objs.audio_dest_channel.selected_item.data__channel_count
  end

  channel_count = math.floor(channel_count)

  return routing_type, channel_count
end


function getAudioRoutingChannelCountType(channel_count)
  local channel_count_type

  if channel_count == 1 then
    channel_count_type = "mono"

  elseif channel_count == 2 then
    channel_count_type = "stereo"

  elseif channel_count > 2 then
    channel_count_type = "multichannel"
  end

  return channel_count_type
end


function getAudioRoutingChannelsAboveCount(routing_setting_value, channel_count_type, channel_count, routing_type)
  local addl_channels_above_count, src_multichannel_addl_channels_above_count

  routing_setting_value = tonumber(routing_setting_value)
  addl_channels_above_count = 0

  if routing_setting_value then

    if channel_count_type == "mono" then
      addl_channels_above_count = routing_setting_value - _api.channels.mono_base

    elseif channel_count_type == "stereo" then
      addl_channels_above_count = routing_setting_value

    elseif channel_count_type == "multichannel" then

      if routing_type == "src" then
        src_multichannel_addl_channels_above_count = routing_setting_value - (_api.channels.src.multichannel.base + (_api.channels.src.multichannel.addl * ((channel_count / 2) - 2)))
        addl_channels_above_count = math.floor(src_multichannel_addl_channels_above_count)

      elseif routing_type == "dest" then
        addl_channels_above_count = routing_setting_value
      end
    end
  end

  return addl_channels_above_count
end


function createRequiredAudioChannels(routing_setting_idx, routing_setting_value, src_track, dest_track)
  local channel_count_type, routing_type, channel_count, addl_channels_above_count, target_track, current_track_channel_value, top_channel_num, track_needs_more_channels

  channel_count_type, routing_type, channel_count, addl_channels_above_count = getAudioRoutingInfo(routing_setting_idx, routing_setting_value)

  if routing_type == "src" then
    target_track = src_track

  elseif routing_type == "dest" and dest_track then
    target_track = dest_track
  end

  current_track_channel_value = reaper.GetMediaTrackInfo_Value(target_track, _api.track.channel_count)
  top_channel_num = (channel_count + addl_channels_above_count)
  track_needs_more_channels = top_channel_num > current_track_channel_value

  if track_needs_more_channels then
    reaper.SetMediaTrackInfo_Value(target_track, _api.track.channel_count, top_channel_num)
  end
end


function getMoreAudioChannelsToIncrement(routing_setting_value, routing_setting_idx, src_track)
  local channel_count_type, routing_type, channel_count, max_track_channels_value, incrementing_exceeds_available_audio_channels

  channel_count_type, routing_type, channel_count = getAudioRoutingInfo(routing_setting_idx)
  max_track_channels_value = getMaxTrackChannelsValue(channel_count_type, channel_count)
  incrementing_exceeds_available_audio_channels = routing_setting_value >= max_track_channels_value

  if incrementing_exceeds_available_audio_channels then

    if channel_count_type == "mono" then
      routing_setting_value = _api.channels.mono_base + _constant.reaper_max_track_channels - 1

    elseif channel_count_type == "stereo" then
      routing_setting_value = _constant.reaper_max_track_channels - 2

    elseif channel_count_type == "multichannel" then
      routing_setting_value = _api.channels.src.multichannel.base + ( _api.channels.src.multichannel.addl * ( (channel_count / 2) - 2) )
    end

    createRequiredAudioChannels(routing_setting_idx, routing_setting_value, src_track)
  end

  return routing_setting_value
end


function getMaxTrackChannelsValue(channel_count_type, channel_count)
  local max_track_channels_value

  if channel_count_type == "mono" then
    max_track_channels_value = _api.channels.mono_base + _constant.reaper_max_track_channels

  elseif channel_count_type == "stereo" then
    max_track_channels_value = _constant.reaper_max_track_channels

  elseif channel_count_type == "multichannel" then
    max_track_channels_value = _api.channels.src.multichannel.base + ( _api.channels.src.multichannel.addl * (channel_count - 4) ) + _constant.reaper_max_track_channels
  end

  return max_track_channels_value
end


function removeRouting(selected_track, target_track)
  local buss_driven, api_routing_category, api_routing_param, routing_count, this_track_target

  buss_driven = 0
  api_routing_category, api_routing_param = getRoutingValues(_state.routing.option_choice.type)
  routing_count = reaper.GetTrackNumSends(selected_track, api_routing_category)

  -- Walk backwards: removing a route shifts the indexes of the ones after it
  for i = routing_count-1, 0, -1 do
    this_track_target = reaper.GetTrackSendInfo_Value(selected_track, api_routing_category, i, api_routing_param)

    if this_track_target == target_track then
      reaper.RemoveTrackSend(selected_track, api_routing_category, i)

      buss_driven = buss_driven + 1
    end
  end

  return buss_driven
end


-- ==== ROUTE SETTINGS CLIPBOARD (copy / paste) ====
-- The clipboard stores raw REAPER send parameters (BR_GetSetTrackSendInfo names), so it can be
-- copied from the settings form or from any existing send/receive, and pasted into the form or
-- onto existing routes. It persists between sessions (global ExtState).

local _clipboard = nil  -- {values = {PARAM = number}, label = string}

do
  local stored = reaper.GetExtState("MB_BussDriver_Prefs", "route_clipboard")
  if stored and stored ~= "" then
    local ok, data = serpent.load(stored)
    if ok and type(data) == "table" and type(data.values) == "table" then
      _clipboard = data
    end
  end
end


local function fmtInt(x)
  return string.format("%d", math.floor(x))
end


-- Inverse of getAPIVolume(): getAPIVolume(s) = 4 * (s/4)^4
local function sliderFromVol(vol)
  if not vol or vol <= 0 then return 0 end
  return 4 * (math.min(vol, 4) / 4) ^ 0.25
end


function ensureRoutingSettings()
  if not _state.routing.settings_objs then
    initRoutingSettings()
  end

  return _state.routing.settings_objs
end


-- The track at the other end of route j on src (category cat)
local function getRouteOtherTrack(src, cat, j, rtype)
  local _, param = getRoutingValues(rtype)
  local other = reaper.GetTrackSendInfo_Value(src, cat, j, param)

  if type(other) ~= "userdata" then
    other = reaper.BR_GetMediaTrackSendInfo_Track(src, cat, j, rtype == "send" and 1 or 0)
  end

  return other
end


-- All routes of type rtype on the source tracks, optionally only those whose other end is in guid_set
function collectRoutes(rtype, guid_set)
  local routes, cat = {}, getRoutingValues(rtype)

  for i = 1, #_state.tracks.selected do
    local src = _state.tracks.selected[i]

    if trackIsValid(src) then
      for j = 0, reaper.GetTrackNumSends(src, cat) - 1 do
        local other = getRouteOtherTrack(src, cat, j, rtype)

        if trackIsValid(other) then
          local g = reaper.BR_GetMediaTrackGUID(other)

          if not guid_set or guid_set[g] then
            routes[#routes + 1] = {
              track = src, cat = cat, idx = j, type = rtype,
              other = other, other_guid = g,
              src_track = rtype == "send" and src or other,
              dest_track = rtype == "send" and other or src
            }
          end
        end
      end
    end
  end

  return routes
end


local function routeLabel(route)
  return trackLabel(route.src_track) .. " " .. _unicode.right_arrow .. " " .. trackLabel(route.dest_track)
end


local function readRouteValues(route)
  local values = {}

  for _, k in ipairs(_route_param_groups.all) do
    values[k] = reaper.BR_GetSetTrackSendInfo(route.track, route.cat, route.idx, k, false, 0)
  end

  return values
end


-- Track channel count must be even and large enough for the routed channels
local function ensureTrackChannels(track, needed)
  needed = math.min(_constant.reaper_max_track_channels, needed + needed % 2)

  if reaper.GetMediaTrackInfo_Value(track, _api.track.channel_count) < needed then
    reaper.SetMediaTrackInfo_Value(track, _api.track.channel_count, needed)
  end
end


local function ensureRouteChannels(route, values)
  local s = values.I_SRCCHAN and math.floor(values.I_SRCCHAN)
  if not s or s < 0 then return end

  local code = s >> 10
  local n = code == 0 and 2 or code == 1 and 1 or code * 2
  ensureTrackChannels(route.src_track, (s & 1023) + n)

  local d = math.max(0, math.floor(values.I_DSTCHAN or 0))
  local d_n = (d & 1024) ~= 0 and 1 or math.max(n, 2)
  ensureTrackChannels(route.dest_track, (d & 1023) + d_n)
end


local function writeRouteValues(route, values, keys)
  for _, k in ipairs(keys) do
    if k == "I_SRCCHAN" then
      ensureRouteChannels(route, values)
      break
    end
  end

  for _, k in ipairs(keys) do
    if values[k] ~= nil then
      reaper.BR_GetSetTrackSendInfo(route.track, route.cat, route.idx, k, true, values[k])
    end
  end
end


-- Human-readable one-liner: "-6.0 dB · C · Post-FX · Audio 1/2→3/4 · MIDI All→All"
function describeRaw(raw)
  if not raw then return "" end

  local parts = {}

  local function add(s) parts[#parts + 1] = s end

  local function rng(off, k)
    if k == 1 then return tostring(off + 1) end
    if k == 2 then return (off + 1) .. "/" .. (off + 2) end
    return (off + 1) .. "-" .. (off + k)
  end

  local function midiCh(bus, ch)
    bus, ch = math.floor(bus or 0), math.floor(ch or 0)
    local c = ch <= 0 and "All" or tostring(ch)
    return bus > 0 and ("B" .. bus .. ":" .. c) or c
  end

  if raw.D_VOL then
    add(raw.D_VOL <= 0.0000001 and "-inf dB" or string.format("%+.1f dB", 20 * math.log(raw.D_VOL, 10)))
  end

  if raw.D_PAN then
    local p = raw.D_PAN
    add(math.abs(p) < 0.005 and "C" or string.format("%d%%%s", math.floor(math.abs(p) * 100 + 0.5), p < 0 and "L" or "R"))
  end

  if raw.I_SENDMODE then
    local modes = {[0] = "Post-Fader", [1] = "Pre-FX", [2] = "Post-FX", [3] = "Post-FX"}
    add(modes[math.floor(raw.I_SENDMODE)] or "?")
  end

  local s = raw.I_SRCCHAN and math.floor(raw.I_SRCCHAN)
  if s then
    if s < 0 then
      add("no audio")
    else
      local code = s >> 10
      local n = code == 0 and 2 or code == 1 and 1 or code * 2
      local d = math.max(0, math.floor(raw.I_DSTCHAN or 0))
      local dstr = (d & 1024) ~= 0 and tostring((d & 1023) + 1) or rng(d & 1023, math.max(n, 2))
      add("Audio " .. rng(s & 1023, n) .. _unicode.right_arrow .. dstr)
    end
  end

  local sch = raw.I_MIDI_SRCCHAN and math.floor(raw.I_MIDI_SRCCHAN)
  if sch then
    if sch < 0 then
      add("no MIDI")
    else
      add("MIDI " .. midiCh(raw.I_MIDI_SRCBUS, sch) .. _unicode.right_arrow .. midiCh(raw.I_MIDI_DSTBUS, raw.I_MIDI_DSTCHAN))
    end
  end

  if raw.B_MUTE and raw.B_MUTE ~= 0 then add("Muted") end
  if raw.B_PHASE and raw.B_PHASE ~= 0 then add("Phase inv.") end
  if raw.B_MONO and raw.B_MONO ~= 0 then add("Mono") end

  return table.concat(parts, "  \u{00B7}  ")
end


-- Settings form → raw send parameters
function formToRaw()
  local so = ensureRoutingSettings()

  local function midiPair(id)
    local bus, ch = tostring(id or "0/0"):match("(%-?%d+)/(%-?%d+)")
    return tonumber(bus) or 0, tonumber(ch) or 0
  end

  local sbus, sch = midiPair(so.midi_src.selected_id)
  local dbus, dch = midiPair(so.midi_dest.selected_id)

  return {
    B_MUTE = so.mute.value or 0,
    B_PHASE = so.phase.value or 0,
    B_MONO = so.mono_stereo.value or 0,
    D_VOL = getAPIVolume(so.volume.value or _constant.default_routing_settings_values.volume),
    D_PAN = so.pan.value or 0,
    I_SENDMODE = tonumber(so.send_mode.selected_id) or 0,
    I_SRCCHAN = tonumber(so.audio_src_channel.selected_id) or 0,
    I_DSTCHAN = tonumber(so.audio_dest_channel.selected_id) or 0,
    I_MIDI_SRCCHAN = sch,
    I_MIDI_SRCBUS = sbus,
    I_MIDI_DSTCHAN = dch,
    I_MIDI_DSTBUS = dbus,
    I_MIDI_LINK_VOLPAN = so.midi_velpan.value or 0
  }
end


-- Raw send parameters (only the given keys) → settings form values
local function rawToFormValues(raw, keys)
  local want, v = {}, {}

  for _, k in ipairs(keys) do
    if raw[k] ~= nil then want[k] = true end
  end

  if want.B_MUTE then v.mute = math.floor(raw.B_MUTE) end
  if want.B_PHASE then v.phase = math.floor(raw.B_PHASE) end
  if want.B_MONO then v.mono_stereo = math.floor(raw.B_MONO) end
  if want.I_MIDI_LINK_VOLPAN then v.midi_velpan = math.floor(raw.I_MIDI_LINK_VOLPAN) end
  if want.D_VOL then v.volume = sliderFromVol(raw.D_VOL) end
  if want.D_PAN then v.pan = raw.D_PAN end

  if want.I_SENDMODE then
    local m = math.floor(raw.I_SENDMODE)
    v.send_mode = m == 2 and 3 or m
  end

  if want.I_SRCCHAN then v.audio_src_channel = fmtInt(raw.I_SRCCHAN) end
  if want.I_DSTCHAN then v.audio_dest_channel = fmtInt(raw.I_DSTCHAN) end

  if want.I_MIDI_SRCCHAN then
    if raw.I_MIDI_SRCCHAN < 0 then
      v.midi_src = "-1/-1"
    else
      v.midi_src = fmtInt(raw.I_MIDI_SRCBUS or 0) .. "/" .. fmtInt(raw.I_MIDI_SRCCHAN)
      v.midi_dest = fmtInt(math.max(0, raw.I_MIDI_DSTBUS or 0)) .. "/" .. fmtInt(math.max(0, raw.I_MIDI_DSTCHAN or 0))
    end
  end

  return v
end


function refreshClipboardSummary()
  local o = _state.routing.options_objs

  if _clipboard then
    local full = _clipboard.label .. "   " .. describeRaw(_clipboard.values)
    o.clip_summary:attr("text", full)
    o.clip_summary:attr("tooltip", full)
    o.clip_summary:attr("color", "#D8D8E8")
  else
    o.clip_summary:attr("text", "empty  -  copy from the settings or from an existing route")
    o.clip_summary:attr("color", _ui.muted)
  end
end


function refreshSettingsSummary()
  local o = _state.routing.options_objs
  local so = _state.routing.settings_objs

  if so and so.all_values then
    local full = describeRaw(formToRaw())
    o.settings_summary:attr("text", full)
    o.settings_summary:attr("tooltip", full)
  else
    o.settings_summary:attr("text", "REAPER defaults (not configured)")
  end
end


local function setClipboard(values, label)
  _clipboard = {values = values, label = label}
  reaper.SetExtState("MB_BussDriver_Prefs", "route_clipboard", serpent.dump(_clipboard), true)
  refreshClipboardSummary()
  setStatus("Copied: " .. label)
end


function copyFromSettingsForm()
  setClipboard(formToRaw(), (_state.mode.type == "send" and "Send" or "Receive") .. " settings")
end


function copyFromRoute(route)
  setClipboard(readRouteValues(route), routeLabel(route))
end


function pasteIntoSettingsForm(keys)
  if not _clipboard then
    setStatus("Clipboard is empty - copy a route first.", "warn")
    return
  end

  local so = ensureRoutingSettings()

  applyFormValues(rawToFormValues(_clipboard.values, keys))
  so.all_values = so.all_values or {}
  getSetRoutingSettingsValues("get")
  refreshSettingsSummary()

  if _state.mode.action == "add" then
    setStatus("Pasted into " .. _state.mode.type .. " settings - new " .. _state.mode.type .. "s will use them.")
  else
    setStatus("Pasted into " .. _state.mode.type .. " settings - switch to Add to create routes with them.")
  end
end


-- Paste the clipboard onto existing routes (current type) whose other end is in guid_set
function pasteOntoRoutes(keys, guid_set, what)
  if not _clipboard then
    setStatus("Clipboard is empty - copy a route first.", "warn")
    return
  end

  local rtype = _state.mode.type
  local routes = collectRoutes(rtype, guid_set)
  local n = #routes

  if n == 0 then
    setStatus("No existing " .. rtype .. "s between the source tracks and the checked tracks.", "warn")
    return
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  for i = 1, n do
    writeRouteValues(routes[i], _clipboard.values, keys)
  end
  reaper.PreventUIRefresh(-1)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock(_constant.brand.script .. ": Paste route settings onto " .. n .. " " .. plural(rtype, n), -1)

  setStatus("Pasted " .. what .. " onto " .. n .. " " .. plural(rtype, n) .. ".")
end


local function checkedGuidSet()
  local set = {}

  for j = 1, #_all_track_lines do
    local info = _all_track_lines[j]
    if info.checkbox.value and lineIsEligible(info) then
      set[info.track_guid] = true
    end
  end

  return set
end


local _paste_choices = {
  {id = "all", label = "All settings", what = "all settings"},
  {id = "level", label = "Volume / pan / mute / phase only", what = "volume/pan/mute/phase"},
  {id = "channels", label = "Send mode & channels only", what = "send mode & channels"}
}


function openCopyMenu(btn)
  local rtype = _state.mode.type
  local items = {
    {"From the " .. rtype .. " settings   [" .. menuSafe(describeRaw(formToRaw())) .. "]", id = "form"}
  }
  local shown, limit = 0, 60

  for _, kind in ipairs({"send", "receive"}) do
    local routes = collectRoutes(kind)

    if #routes > 0 then
      items[#items + 1] = rtk.NativeMenu.SEPARATOR
      items[#items + 1] = {"Existing " .. kind .. "s of the source tracks:", disabled = true}

      for i = 1, #routes do
        if shown >= limit then
          items[#items + 1] = {"(more" .. "\u{2026}" .. " right-click a track row to copy from it)", disabled = true}
          break
        end
        local r = routes[i]
        items[#items + 1] = {menuSafe("    " .. routeLabel(r) .. "   [" .. describeRaw(readRouteValues(r)) .. "]"), id = "route" .. shown, route = r}
        shown = shown + 1
      end
    end
  end

  if shown == 0 then
    items[#items + 1] = rtk.NativeMenu.SEPARATOR
    items[#items + 1] = {"(The source tracks have no sends or receives to copy from)", disabled = true}
  end

  rtk.NativeMenu(items):open_at_widget(btn, "left", "bottom"):done(function(item)
    if not item then return end

    if item.id == "form" then
      copyFromSettingsForm()
    elseif item.route then
      copyFromRoute(item.route)
    end
  end)
end


function openPasteMenu(btn)
  local rtype = _state.mode.type
  local prep = rtype == "send" and "to" or "from"
  local has = _clipboard ~= nil
  local n = has and #collectRoutes(rtype, checkedGuidSet()) or 0

  local items = {
    {has and ("Clipboard: " .. menuSafe(_clipboard.label)) or "Clipboard is empty - use Copy first", disabled = true},
    rtk.NativeMenu.SEPARATOR,
    {"Into the " .. rtype .. " settings (used when adding)", id = "form", disabled = not has},
    rtk.NativeMenu.SEPARATOR
  }

  if n > 0 then
    items[#items + 1] = {"Onto " .. n .. " existing " .. plural(rtype, n) .. " " .. prep .. " the checked tracks:", disabled = true}
  else
    items[#items + 1] = {"Onto existing " .. rtype .. "s: first check tracks that already have one", disabled = true}
  end

  for _, c in ipairs(_paste_choices) do
    items[#items + 1] = {"    " .. c.label, id = c.id, choice = c, disabled = n == 0}
  end

  rtk.NativeMenu(items):open_at_widget(btn, "left", "bottom"):done(function(item)
    if not item then return end

    if item.id == "form" then
      pasteIntoSettingsForm(_route_param_groups.all)
    elseif item.choice then
      pasteOntoRoutes(_route_param_groups[item.choice.id], checkedGuidSet(), item.choice.what)
    end
  end)
end


-- Right-click on a track row
function openTrackContextMenu(info)
  local rtype = _state.mode.type
  local only_this = {[info.track_guid] = true}
  local items = {
    {menuSafe(trackLabel(info.track, 32)), disabled = true},
    rtk.NativeMenu.SEPARATOR
  }

  local any_route = false
  for _, kind in ipairs({"send", "receive"}) do
    local routes = collectRoutes(kind, only_this)
    for i = 1, #routes do
      local r = routes[i]
      items[#items + 1] = {menuSafe("Copy settings from " .. routeLabel(r) .. "   [" .. describeRaw(readRouteValues(r)) .. "]"), id = "copy" .. #items, route = r}
      any_route = true
    end
  end
  if not any_route then
    items[#items + 1] = {"Copy: no send/receive with the source tracks", disabled = true}
  end

  items[#items + 1] = rtk.NativeMenu.SEPARATOR

  local n = _clipboard and #collectRoutes(rtype, only_this) or 0
  if n > 0 then
    items[#items + 1] = {"Paste clipboard onto this track's " .. n .. " " .. plural(rtype, n) .. ":", disabled = true}
    for _, c in ipairs(_paste_choices) do
      items[#items + 1] = {"    " .. c.label, id = "paste_" .. c.id, choice = c}
    end
  else
    items[#items + 1] = {"Paste: " .. (_clipboard and ("no " .. rtype .. " with the source tracks") or "clipboard is empty"), disabled = true}
  end

  items[#items + 1] = rtk.NativeMenu.SEPARATOR
  items[#items + 1] = {"Check only this track", id = "only"}

  rtk.NativeMenu(items):open_at_mouse():done(function(item)
    if not item then return end

    if item.route then
      copyFromRoute(item.route)
    elseif item.choice then
      pasteOntoRoutes(_route_param_groups[item.choice.id], only_this, item.choice.what)
    elseif item.id == "only" then
      selectDeselectAllTargetTracks(false)
      info.checkbox:attr("value", true)
      markDirty()
    end
  end)
end


function populateRoutingOptionsWindow()
  local o = _state.routing.options_objs

  -- ── HEADER (fixed) ──
  o.brand:add(o.logo)
  o.brand:add(o.title)
  o.header_top:add(o.settings_btn, {halign = "left", valign = "center"})
  o.header_top:add(o.brand, {halign = "center", valign = "center"})
  o.header_right:add(o.help_btn)
  o.header_right:add(o.pin_btn)
  o.header_top:add(o.header_right, {halign = "right", valign = "center"})

  o.selected_tracks_box:add(o.selected_tracks_heading)
  o.selected_tracks_box:add(o.selected_tracks_list)

  o.action_seg:add(o.add_btn)
  o.action_seg:add(o.remove_btn)
  o.type_seg:add(o.send_btn)
  o.type_seg:add(o.receive_btn)
  o.mode_row:add(o.action_seg)
  o.mode_row:add(o.type_seg)

  o.settings_row:add(o.configure_btn)
  o.settings_row:add(o.settings_summary, {expand = 1, fillw = true})

  o.clip_row:add(o.clip_label)
  o.clip_row:add(o.clip_summary, {expand = 1, fillw = true})
  o.clip_row:add(o.copy_btn)
  o.clip_row:add(o.paste_btn)

  -- Counter sits next to the filter so the row ends on a button, like the clipboard row above
  o.list_toolbar:add(o.filter_entry, {expand = 1, fillw = true})
  o.list_toolbar:add(o.count_text)
  o.list_toolbar:add(o.select_all_btn)
  o.list_toolbar:add(o.select_none_btn)
  o.list_toolbar:add(o.deselect_existing_routing)

  o.header_box:add(o.header_top)
  o.header_box:add(o.selected_tracks_box)
  o.header_box:add(o.mode_row, {halign = "center"})
  o.header_box:add(o.hint_text)
  o.header_box:add(o.settings_row)
  o.header_box:add(o.clip_row)
  o.header_box:add(o.list_toolbar)

  -- ── VIEWPORT (scrollable track list) ──
  o.form_fields:add(o.empty_text)
  o.form_fields:add(o.target_tracks_box)
  o.content:add(o.form_fields)
  o.viewport:attr("child", o.content)
  o.viewport:reflow()

  -- ── BOTTOM BAR (fixed) ──
  o.options_box:add(o.save_options)
  o.options_box:add(o.keep_open)
  o.form_buttons:add(o.form_submit)
  o.form_buttons:add(o.form_cancel)
  o.form_bottom:add(o.options_box, {halign = "left", valign = "center"})
  o.form_bottom:add(o.form_buttons, {halign = "center", valign = "center"})
  o.form_bottom:add(o.reset_btn, {halign = "right", valign = "center"})
  o.bottom_bar:add(o.form_bottom)
  o.bottom_bar:add(o.status_text)

  -- ── Settings popup ──
  o.settings_content:add(o.settings_title)
  o.settings_content:add(o.settings_scale_label)
  o.settings_content:add(o.settings_scale)
  -- Color section
  o.settings_content:add(o.settings_color_heading)
  if T then
    o.theme_row:add(o.theme_inherit)
    o.theme_row:add(o.theme_manager_btn, {fillw = true})
    o.settings_content:add(o.theme_row)
  end
  o.color_window_bg_row:add(o.color_window_bg_swatch)
  o.color_window_bg_row:add(o.color_window_bg_btn, {expand = 1, fillw = true})
  o.settings_content:add(o.color_window_bg_row)
  o.color_header_bg_row:add(o.color_header_bg_swatch)
  o.color_header_bg_row:add(o.color_header_bg_btn, {expand = 1, fillw = true})
  o.settings_content:add(o.color_header_bg_row)
  o.color_accent_row:add(o.color_accent_swatch)
  o.color_accent_row:add(o.color_accent_btn, {expand = 1, fillw = true})
  o.settings_content:add(o.color_accent_row)
  o.color_tree_line_row:add(o.color_tree_line_swatch)
  o.color_tree_line_row:add(o.color_tree_line_btn, {expand = 1, fillw = true})
  o.settings_content:add(o.color_tree_line_row)
  o.color_text_row:add(o.color_text_swatch)
  o.color_text_row:add(o.color_text_btn, {expand = 1, fillw = true})
  o.settings_content:add(o.color_text_row)
  o.settings_content:add(o.settings_color_reset, {fillw = true})
  -- Tree line mode buttons
  o.settings_content:add(o.settings_tree_heading)
  o.settings_tree_mode_row:add(o.settings_tree_radial, {expand = 1, fillw = true})
  o.settings_tree_mode_row:add(o.settings_tree_elbow, {expand = 1, fillw = true})
  o.settings_content:add(o.settings_tree_mode_row)
  -- Note + buttons
  o.settings_content:add(o.settings_note)
  local settings_btns = rtk.HBox{w = 1, spacing = L.gap, tmargin = L.gap}
  settings_btns:add(o.settings_save, {expand = 1, fillw = true})
  settings_btns:add(o.settings_reset, {expand = 1, fillw = true})
  o.settings_content:add(settings_btns)
  o.settings_popup:attr("child", o.settings_content)

  -- ── Window: single VBox (header → viewport → bottom) ──
  _state.routing.options_objs.main_vbox:add(_state.routing.options_objs.header_box)
  _state.routing.options_objs.main_vbox:add(_state.routing.options_objs.viewport, {fillh = true})
  _state.routing.options_objs.main_vbox:add(_state.routing.options_objs.bottom_bar)
  _state.routing.options_objs.window:add(_state.routing.options_objs.main_vbox)
  _state.routing.options_objs.window:add(_state.routing.options_objs.settings_popup)
end


function initBussDriver()

  if _constant.selected_tracks_count > 0 then
    launchBussDriverDialog()

  else
    reaper.ShowMessageBox("Select one or more tracks you want to create routing to/from and launch Buss Driver again.", _constant.brand.script .. ": No tracks are selected.", _api.msg_type_ok)
  end
end

initBussDriver()
