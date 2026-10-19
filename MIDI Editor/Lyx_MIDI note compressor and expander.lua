-- @description Lyx MIDI Note Compressor and Expander
-- @version 2.27
-- @author Lyx (refactor based on amagalma)
-- @about
--   Compress / expand MIDI note velocities around a threshold.
--   Supports multi-item selection, selected-notes-only processing,
--   HiDPI / Retina, full theme customisation, UI scaling,
--   Reset, Bypass, Humanize, A–D preset slots, percent / ratio display,
--   wide layout with a mouse-editable transfer curve.

local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
package.path = package.path..";"..script_path.."?.lua"
local ok_home, r_home = pcall(require, "_Lyx_HOME")

-------------------------------------------------------------------------------
-- ReaImGui check
-------------------------------------------------------------------------------
if not reaper.ImGui_GetVersion then
    reaper.MB(
        "This script needs the ReaImGui extension.\n\n"..
        "To install it:\n"..
        "1) REAPER → Extensions → ReaPack → Browse packages\n"..
        "2) Search for \"ReaImGui\"\n"..
        "3) Right-click → Install, then restart REAPER\n\n"..
        "Then run this script again.",
        "ReaImGui missing", 0)
    return
end
do -- fonts below use the ReaImGui 0.10 API (size given to PushFont)
    local _, _, v = reaper.ImGui_GetVersion()
    local x, y = tostring(v or ""):match("^(%d+)%.(%d+)")
    x, y = tonumber(x) or 0, tonumber(y) or 0
    if x == 0 and y < 10 then
        reaper.MB("This script needs ReaImGui 0.10 or newer (you have "..tostring(v)..").\nUpdate ReaImGui with ReaPack and restart REAPER.", "ReaImGui too old", 0)
        return
    end
end

local ImGui = {}
for name, func in pairs(reaper) do
    name = name:match('^ImGui_(.+)$')
    if name then ImGui[name] = func end
end

local SCRIPT_NAME = "Lyx MIDI Note Compressor / Expander"
local IS_MAC      = reaper.GetOS():find("OSX") or reaper.GetOS():find("macOS")
local KEY_CMD     = IS_MAC and "Cmd" or "Ctrl"   -- names shown in tooltips
local KEY_ALT     = IS_MAC and "Opt" or "Alt"
local VERSION     = "2.27"
local EXT_SECTION = "Lyx_MIDI_Compressor"

-------------------------------------------------------------------------------
-- Toggle command state (toolbar highlight)
-------------------------------------------------------------------------------
local _, _, section_id, cmd_id = reaper.get_action_context()
reaper.SetToggleCommandState(section_id, cmd_id, 1)
reaper.RefreshToolbar2(section_id, cmd_id)

local UNDO_NAME   = "Lyx: MIDI velocity compress/expand"
local has_written = false   -- velocities written that no undo point covers yet
local last_write  = 0       -- time of the last write (undo point follows 0.5 s after the GUI is let go)

local function atexit()
    reaper.SetToggleCommandState(section_id, cmd_id, 0)
    reaper.RefreshToolbar2(section_id, cmd_id)
    if has_written then
        reaper.Undo_OnStateChange2(0, UNDO_NAME)
    end
end
reaper.atexit(atexit)

-------------------------------------------------------------------------------
-- Theme
-------------------------------------------------------------------------------
local function rgba(r, g, b, a)
    r = math.floor(math.max(0, math.min(255, r)))
    g = math.floor(math.max(0, math.min(255, g)))
    b = math.floor(math.max(0, math.min(255, b)))
    a = math.floor(math.max(0, math.min(255, a or 255)))
    return (r<<24)|(g<<16)|(b<<8)|a
end

local function unpack_rgba(c)
    return (c>>24)&0xFF, (c>>16)&0xFF, (c>>8)&0xFF, c&0xFF
end

-- Defaults = Andy's tuned look (v2.19). Restored by Settings → Reset ALL.
local DEFAULT_THEME = {
    bg            = rgba(  3,  26,  41, 255),
    panel         = rgba( 46,  48,  48, 255),
    text          = rgba(234, 161,  37, 255),
    text_dim      = rgba(255, 204, 118, 255),
    accent        = rgba( 91, 210, 138, 255),
    slider        = rgba( 41, 140, 255, 255),
    comp_expand   = rgba( 35,  75, 160, 150),  -- Compress slider track, left (expand) end
    comp_compress = rgba(160,  45,  45, 150),  -- Compress slider track, right (compress) end
    bypass_on     = rgba(200,  60,  60, 255),  -- Bypass button while engaged
    diagonal      = rgba(150, 120, 210, 160),  -- graph 1:1 line (= bypass result)
    -- fixed (not in Settings): small decorative details
    slider_act    = rgba(  1,  66, 255, 255),  -- grab / button while pressed
    border        = rgba(255, 220, 151, 255),  -- separators, frames
    stat_val      = rgba(247, 255, 225, 255),  -- statistic numbers, note dots
    icon          = rgba(140, 140, 148, 255),  -- header icons
}

-- Colours offered in Settings (the functional ones), in display order
local THEME_EDITABLE = {
    { "bg", "Background" }, { "panel", "Panel" }, { "text", "Text" }, { "text_dim", "Text (dim)" },
    { "accent", "Accent" }, { "slider", "Slider" },
    { "comp_expand", "Compress: expand" }, { "comp_compress", "Compress: compress" },
    { "bypass_on", "Bypass (on)" }, { "diagonal", "Graph 1:1 line" },
}

local theme = {}
for k, v in pairs(DEFAULT_THEME) do theme[k] = v end

local DEFAULT_SETTINGS = {
    ui_scale     = 1.2,
    show_ratio   = false,
    limit_rate   = true,   -- true: mouse edits on the graph also stop at ±100%
    bypass_ghost = true,   -- show the (inactive) curve as a ghost while bypassed
    pinned       = true,   -- keep the windows on top
    play_flash   = true,   -- notes flash on the graph while the project plays
}

local settings = {}
for k, v in pairs(DEFAULT_SETTINGS) do settings[k] = v end

local function load_settings()
    local function getN(k, def)
        local s = reaper.GetExtState(EXT_SECTION, k)
        if s == "" then return def end
        return tonumber(s) or def
    end
    local function getB(k, def)
        local s = reaper.GetExtState(EXT_SECTION, k)
        if s == "" then return def end
        return s == "1"
    end
    for _, e in ipairs(THEME_EDITABLE) do
        theme[e[1]] = getN("theme_"..e[1], DEFAULT_THEME[e[1]])
    end
    -- v2.25: the Compress gradient got quieter; move users still on the old default
    if theme.comp_expand   == rgba( 60, 120, 230, 220) then theme.comp_expand   = DEFAULT_THEME.comp_expand   end
    if theme.comp_compress == rgba(230,  80,  80, 220) then theme.comp_compress = DEFAULT_THEME.comp_compress end
    settings.ui_scale     = getN("ui_scale", DEFAULT_SETTINGS.ui_scale)
    settings.limit_rate   = getB("limit_rate",   DEFAULT_SETTINGS.limit_rate)
    settings.bypass_ghost = getB("bypass_ghost", DEFAULT_SETTINGS.bypass_ghost)
    settings.pinned       = getB("pinned",       DEFAULT_SETTINGS.pinned)
    settings.show_ratio   = getB("show_ratio",   DEFAULT_SETTINGS.show_ratio)
    settings.play_flash   = getB("play_flash",   DEFAULT_SETTINGS.play_flash)
end

local function save_settings()
    for _, e in ipairs(THEME_EDITABLE) do
        reaper.SetExtState(EXT_SECTION, "theme_"..e[1], tostring(theme[e[1]]), true)
    end
    reaper.SetExtState(EXT_SECTION, "ui_scale", tostring(settings.ui_scale), true)
    reaper.SetExtState(EXT_SECTION, "limit_rate", settings.limit_rate and "1" or "0", true)
    reaper.SetExtState(EXT_SECTION, "bypass_ghost", settings.bypass_ghost and "1" or "0", true)
    reaper.SetExtState(EXT_SECTION, "pinned", settings.pinned and "1" or "0", true)
    reaper.SetExtState(EXT_SECTION, "play_flash", settings.play_flash and "1" or "0", true)
    reaper.SetExtState(EXT_SECTION, "show_ratio", settings.show_ratio and "1" or "0", true)
end

load_settings()

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------
local floor, ceil, random = math.floor, math.ceil, math.random

-- takes_data[take] = {
--   orig_vels = { [noteIdx] = vel },  -- original velocity snapshot
--   sel_set   = { [noteIdx] = true }, -- currently selected notes
--   hum_offs  = { [noteIdx] = float[-1..1] }, -- stable humanize offsets
--   note_cnt  = integer,
--   hash      = string (MIDI_GetHash)
-- }
local takes_data   = {}
local active_takes = {}        -- ordered list of takes currently processed
local use_selected = false     -- true if any selected notes found across takes
local stats = { cnt=0, avg=0, med=0, mod=0, min=127, max=0, has=false }

local threshold_mode = "avg"   -- "avg" | "med" | "mod" | "custom"
local threshold      = 64
local custom_thr     = 64

local above_val    = 0    -- %: sliders give ±100, mouse on the graph may go further (mouse_range)
local below_val    = 0
local above_curve  = 0    -- bend of each half (Opt-drag on the graph), 0 = straight, ±4
local below_curve  = 0
local humanize_val = 0    -- 0..30 (+/- velocity units scaled by noise)
local gain_val     = 0    -- -127..127 velocity added after compression (makeup)
local last_applied = { above=0, below=0, humanize=0, gain=0, ac=0, bc=0, thr=-1 }
local dirty        = false
local need_reapply = false

local show_settings = false
local graph_drag    = nil   -- { mode = "thr"|"above"|"below"|"above_curve"|"below_curve"|"rotate", ... } while dragging the curve graph

-- A–D are independent slider-setting snapshots. The active slot's values live on
-- the sliders (its table entry is only refreshed when switching away).
local SLOT_NAMES  = { "A", "B", "C", "D" }
local slots       = {}
for i = 1, #SLOT_NAMES do slots[i] = { above = 0, below = 0, humanize = 0, gain = 0, ac = 0, bc = 0 } end
local active_slot = 1
local bypass      = false   -- true = notes play their original velocities, sliders kept

-- Undo / redo of this script's own settings. Session only: never written anywhere,
-- so the history is gone when the script closes.
local undo_stack, redo_stack = {}, {}
local committed = nil      -- settings snapshot after the last finished edit
local MAX_UNDO  = 100

local function switch_slot(i)
    local s = slots[active_slot]
    s.above, s.below, s.humanize, s.gain = above_val, below_val, humanize_val, gain_val
    s.ac, s.bc = above_curve, below_curve
    active_slot = i
    s = slots[i]
    above_val, below_val, humanize_val, gain_val = s.above, s.below, s.humanize, s.gain
    above_curve, below_curve = s.ac, s.bc
    need_reapply = true
end

-------------------------------------------------------------------------------
-- Take collection
-------------------------------------------------------------------------------
local function is_valid_take(t)
    return t and reaper.ValidatePtr2(0, t, "MediaItem_Take*") and reaper.TakeIsMIDI(t)
end

local function collect_takes()
    local takes = {}
    local seen = {}
    local me = reaper.MIDIEditor_GetActive()
    if not me then return takes end   -- no MIDI editor: nothing to process
    local t = reaper.MIDIEditor_GetTake(me)
    if is_valid_take(t) then
        takes[#takes+1] = t
        seen[t] = true
    end
    local sel_cnt = reaper.CountSelectedMediaItems(0)
    for i = 0, sel_cnt-1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local t = reaper.GetActiveTake(item)
        if is_valid_take(t) and not seen[t] then
            takes[#takes+1] = t
            seen[t] = true
        end
    end
    return takes
end

-- Build / refresh note metadata. If rebuild_orig is true, snapshots current
-- velocities as the new "original" baseline and re-generates humanize offsets.
local function refresh_take_data(take, rebuild_orig)
    local _, note_cnt = reaper.MIDI_CountEvts(take)
    local data = takes_data[take]
    if not data then
        data = { orig_vels={}, cur_vels={}, start_ppq={}, end_ppq={}, sel_set={}, hum_offs={}, note_cnt=0, hash="" }
        takes_data[take] = data
        rebuild_orig = true
    end

    if rebuild_orig then
        data.orig_vels = {}
        data.cur_vels  = {}   -- velocity currently in the take (only changed notes get written)
        data.start_ppq = {}
        data.end_ppq   = {}
        data.hum_offs  = {}
        for n = 0, note_cnt-1 do
            local _, _, _, sppq, eppq, _, _, vel = reaper.MIDI_GetNote(take, n)
            data.orig_vels[n] = vel
            data.cur_vels[n]  = vel
            data.start_ppq[n] = sppq
            data.end_ppq[n]   = eppq
            data.hum_offs[n]  = (random()*2) - 1   -- [-1, 1]
        end
    end

    data.note_cnt = note_cnt
    local _, h = reaper.MIDI_GetHash(take, false, "")
    data.hash = h or ""
    return data
end

-- Fast selection refresh via MIDI_EnumSelNotes (O(selected) only).
local function refresh_selection(data, take)
    local new_sel = {}
    local new_cnt = 0
    local ni = -1
    while true do
        ni = reaper.MIDI_EnumSelNotes(take, ni)
        if ni < 0 then break end
        new_sel[ni] = true
        new_cnt = new_cnt + 1
    end
    local changed = (new_cnt ~= (data.sel_cnt or -1))
    if not changed then
        for k in pairs(new_sel) do
            if not data.sel_set[k] then changed = true; break end
        end
    end
    data.sel_set = new_sel
    data.sel_cnt = new_cnt
    return changed
end

-- Combined poll: detects external MIDI edits, count changes, and selection changes.
-- Returns (data, changed, user_edited).
local function poll_take(take)
    local data = takes_data[take]
    local _, note_cnt = reaper.MIDI_CountEvts(take)
    local structural  = false
    local user_edited = false
    if not data then
        data = refresh_take_data(take, true)
        structural = true
    elseif data.note_cnt ~= note_cnt then
        -- Note added / removed — treat as external edit, rebuild baseline.
        data = refresh_take_data(take, true)
        structural  = true
        user_edited = true
    else
        local _, h = reaper.MIDI_GetHash(take, false, "")
        if h ~= data.hash then
            -- Hash mismatch not caused by our own write → user edited externally.
            data = refresh_take_data(take, true)
            structural  = true
            user_edited = true
        end
    end
    local sel_changed = refresh_selection(data, take)
    return data, (structural or sel_changed), user_edited
end

-------------------------------------------------------------------------------
-- Statistics across active notes (respecting selection mode)
-------------------------------------------------------------------------------
local function recompute_stats()
    local cnt = 0
    local sum = 0
    local mn, mx = 127, 0
    local hist = {}
    local all  = {}
    for _, take in ipairs(active_takes) do
        local d = takes_data[take]
        if d then
            local use_sel = use_selected
            for n = 0, d.note_cnt-1 do
                if (not use_sel) or d.sel_set[n] then
                    local v = d.orig_vels[n]
                    if v then
                        cnt = cnt + 1
                        sum = sum + v
                        if v < mn then mn = v end
                        if v > mx then mx = v end
                        hist[v] = (hist[v] or 0) + 1
                        all[cnt] = v
                    end
                end
            end
        end
    end
    if cnt == 0 then
        stats.has = false
        stats.cnt = 0
        return
    end
    table.sort(all)
    local med
    if cnt % 2 == 0 then
        med = floor((all[cnt//2] + all[cnt//2+1]) / 2 + 0.5)
    else
        med = all[ceil(cnt/2)]
    end
    local mode_v, mode_c = -1, 0
    for v, c in pairs(hist) do
        if c > mode_c then mode_c = c; mode_v = v end
    end
    stats.has = true
    stats.cnt = cnt
    stats.avg = floor(sum/cnt + 0.5)
    stats.med = med
    stats.mod = mode_v
    stats.min = mn
    stats.max = mx
end

local function current_threshold()
    if threshold_mode == "avg" then return stats.avg
    elseif threshold_mode == "med" then return stats.med
    elseif threshold_mode == "mod" then return stats.mod
    else return custom_thr end
end

-------------------------------------------------------------------------------
-- Apply processing
-------------------------------------------------------------------------------
-- velocity transfer (without humanize / clamp): used by apply and the curve graph
-- v2.11: both compress and expand pivot on the threshold, so the graph is one
-- unbroken line hinged at the threshold. Slope = 1 - % (+100% = flat, -100% = x2,
-- which matches the "1 : 2" ratio display). Beyond +100% the slope goes negative
-- (louder in = quieter out, "negative ratio").
-- v2.13: each half can also be bent (ac / bc): its two ends stay put, the middle bows.
local function bend(dx, span, c)
    if c == 0 or span <= 0 then return dx end
    local t = math.min(1, math.abs(dx) / span)
    return (dx < 0 and -span or span) * t ^ (2 ^ c)
end

local function transform(orig, thr, av, bv, gain, ac, bc)
    if orig >= thr then
        return thr + bend(orig - thr, 127 - thr, ac or 0) * (1 - av * 0.01) + gain
    end
    return thr + bend(orig - thr, thr, bc or 0) * (1 - bv * 0.01) + gain
end

--[[ v2.10 original engine (kept for reference): expansion pivoted on 127 / 0
     instead of the threshold, so the curve broke apart at the threshold line.
local function transform(orig, thr, av, bv, gain)
    local v = orig
    if orig > thr then
        if av > 0 then v = orig - (orig - thr) * av * 0.01
        elseif av < 0 then v = orig - (127 - orig) * av * 0.01 end
    elseif orig < thr then
        if bv > 0 then v = orig + (thr - orig) * bv * 0.01
        elseif bv < 0 then v = orig + orig * bv * 0.01 end
    end
    return v + gain
end
--]]

local function apply_to_take(take, use_original_only)
    local d = takes_data[take]; if not d then return end
    local use_sel = use_selected
    local thr = threshold
    local av  = above_val
    local bv  = below_val
    local hum = humanize_val
    local gain = gain_val

    -- Only notes whose velocity really changes are written. Velocity never moves a note,
    -- and every write uses noSort, so note indices stay valid for the whole loop.
    local wrote = false
    for n = 0, d.note_cnt-1 do
        local orig = d.orig_vels[n]
        if orig then
            local in_scope = (not use_sel) or d.sel_set[n]
            local v
            if use_original_only or not in_scope then
                v = orig
            else
                v = transform(orig, thr, av, bv, gain, above_curve, below_curve)
                if hum > 0 then
                    v = v + d.hum_offs[n] * hum
                end
                v = floor(v + 0.5)
                if v < 1 then v = 1 elseif v > 127 then v = 127 end
            end
            if v ~= d.cur_vels[n] then
                if not wrote then reaper.MIDI_DisableSort(take); wrote = true end
                reaper.MIDI_SetNote(take, n, nil, nil, nil, nil, nil, nil, v, true)
                d.cur_vels[n] = v
            end
        end
    end
    if not wrote then return false end
    reaper.MIDI_Sort(take)   -- also ends MIDI_DisableSort
    -- Our writes changed the hash; resync stored hash to avoid false "user edit" detection.
    local _, h = reaper.MIDI_GetHash(take, false, "")
    d.hash = h
    return true
end

local function apply_all(use_original_only)
    for _, take in ipairs(active_takes) do
        if apply_to_take(take, use_original_only) then
            has_written = true
            last_write  = reaper.time_precise()
        end
    end
end

local function reset_values()
    above_val    = 0
    below_val    = 0
    humanize_val = 0
    gain_val     = 0
    above_curve, below_curve = 0, 0
    apply_all(true)
    last_applied.above = 0
    last_applied.below = 0
    last_applied.humanize = 0
    last_applied.gain = 0
    last_applied.ac, last_applied.bc = 0, 0
end

-------------------------------------------------------------------------------
-- Poll / refresh loop
-------------------------------------------------------------------------------
local last_poll = 0
local function poll(force)
    local now = reaper.time_precise()
    if not force and (now - last_poll) < 0.2 then return end
    last_poll = now

    local new_takes = collect_takes()

    -- Check if take set changed
    local changed = (#new_takes ~= #active_takes)
    if not changed then
        for i = 1, #new_takes do
            if new_takes[i] ~= active_takes[i] then changed = true; break end
        end
    end

    -- Drop stale take data
    local new_set = {}
    for _, t in ipairs(new_takes) do new_set[t] = true end
    for t in pairs(takes_data) do
        if not new_set[t] then takes_data[t] = nil end
    end

    active_takes = new_takes

    -- Refresh / poll each take
    local any_refreshed = changed
    local any_selected  = false
    local any_user_edit = false
    for _, t in ipairs(active_takes) do
        local _, did, edited = poll_take(t)
        if did    then any_refreshed = true end
        if edited then any_user_edit = true end
        local d = takes_data[t]
        if d and next(d.sel_set) then any_selected = true end
    end

    -- Determine selection mode
    if any_selected ~= use_selected then
        any_refreshed = true
        use_selected = any_selected
    end

    -- If user directly edited MIDI, clear our slider deltas so their edit stands.
    -- The baseline has been re-snapshotted to the current MIDI state.
    if any_user_edit then
        undo_stack, redo_stack, committed = {}, {}, nil   -- old steps no longer match the MIDI
        above_val, below_val, humanize_val, gain_val = 0, 0, 0, 0
        above_curve, below_curve = 0, 0
        for _, s in ipairs(slots) do s.above, s.below, s.humanize, s.gain, s.ac, s.bc = 0, 0, 0, 0, 0, 0 end
        last_applied.above, last_applied.below, last_applied.humanize, last_applied.gain = 0, 0, 0, 0
        last_applied.ac, last_applied.bc = 0, 0
    end

    if any_refreshed then
        recompute_stats()
        if stats.has then
            threshold = current_threshold()
            custom_thr = math.max(1, math.min(127, custom_thr))
        end
        if not any_user_edit and (above_val ~= 0 or below_val ~= 0 or humanize_val ~= 0 or gain_val ~= 0
                                  or above_curve ~= 0 or below_curve ~= 0) then
            need_reapply = true
        end
    end
end

-------------------------------------------------------------------------------
-- ImGui context
-------------------------------------------------------------------------------
local ctx = ImGui.CreateContext(SCRIPT_NAME)
-- No keyboard navigation: a lone Opt/Alt press would otherwise jump to the menu layer,
-- and Space / Enter would press the focused widget (same as _Lyx_GUI.lua).
ImGui.SetConfigVar(ctx, ImGui.ConfigVar_Flags(),
    ImGui.GetConfigVar(ctx, ImGui.ConfigVar_Flags()) & ~ImGui.ConfigFlags_NavEnableKeyboard())

-- This window captures the keyboard (Esc, Cmd+Z…), so Space is handed on to whatever
-- the user's main-section Space shortcut is (reaper-kb.ini "KEY 1 32 <cmd> 0");
-- REAPER's default is Transport: Play/stop. nil = Space is disabled there.
local function space_command()
    local f = io.open(reaper.GetResourcePath() .. "/reaper-kb.ini", "r")
    if f then
        for line in f:lines() do
            local id, sec = line:match("^KEY 1 32 (%S+) (%d+)")
            if id and sec == "0" then
                f:close()
                if id == "0" then return nil end
                local n = tonumber(id) or reaper.NamedCommandLookup(id)
                return (n and n ~= 0) and n or 40044
            end
        end
        f:close()
    end
    return 40044
end
local SPACE_CMD = space_command()

-- Fonts (created with scale for sharp Retina rendering)
local fonts = {}
local font_sizes = {}
local function build_fonts()
    local base = math.floor(14 * settings.ui_scale + 0.5)
    -- ReaImGui 0.10: CreateFont(family, flags); the size is given to PushFont
    fonts.body   = ImGui.CreateFont('sans-serif')
    fonts.h1     = ImGui.CreateFont('sans-serif', ImGui.FontFlags_Bold())
    fonts.small  = ImGui.CreateFont('sans-serif', ImGui.FontFlags_Italic())
    fonts.stat   = ImGui.CreateFont('sans-serif', ImGui.FontFlags_Bold())
    font_sizes.body  = base
    font_sizes.h1    = math.floor(base * 1.3 + 0.5)
    font_sizes.small = math.max(10, base - 2)
    font_sizes.stat  = base
    ImGui.Attach(ctx, fonts.body)
    ImGui.Attach(ctx, fonts.h1)
    ImGui.Attach(ctx, fonts.small)
    ImGui.Attach(ctx, fonts.stat)
end

local function push_font(name)
    ImGui.PushFont(ctx, fonts[name], font_sizes[name] or 14)
end
build_fonts()

local function rebuild_fonts_if_needed(new_scale)
    if math.abs(new_scale - settings.ui_scale) < 0.001 then return end
    settings.ui_scale = new_scale
    fonts = {}
    build_fonts()
end

-------------------------------------------------------------------------------
-- UI helpers
-------------------------------------------------------------------------------
-- Resolve constants that may be functions (newer ReaImGui) or numbers (older).
local function K(v)
    if type(v) == "function" then return v() end
    return v
end

local function push_theme()
    ImGui.PushStyleColor(ctx, K(ImGui.Col_WindowBg),        theme.bg)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_PopupBg),         theme.bg)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_ChildBg),         theme.panel)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_Border),          theme.border)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_FrameBg),         theme.panel)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_FrameBgHovered),  theme.panel)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_FrameBgActive),   theme.panel)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_Text),            theme.text)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_TextDisabled),    theme.text_dim)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_Button),          theme.panel)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_ButtonHovered),   theme.slider)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_ButtonActive),    theme.slider_act)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_SliderGrab),      theme.slider)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_SliderGrabActive),theme.slider_act)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_CheckMark),       theme.accent)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_Header),          theme.panel)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_HeaderHovered),   theme.slider)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_HeaderActive),    theme.slider_act)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_Separator),       theme.border)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_Tab),             theme.panel)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_TabHovered),      theme.slider)
end
local THEME_COLOR_COUNT = 21

local function pop_theme()
    ImGui.PopStyleColor(ctx, THEME_COLOR_COUNT)
end

-- Format % as ratio or percent based on settings
local function format_value(p)
    if not settings.show_ratio then
        return string.format("%+d%%", p)
    end
    if p == 0 then return "1 : 1" end
    local x = p / 100.0
    if x > 0 then
        if math.abs(x - 1) < 0.005 then return "inf : 1" end
        local r = 1.0 / (1.0 - x)
        return string.format("%.1f : 1", r)
    else
        local r = 1.0 - x
        return string.format("1 : %.1f", r)
    end
end

local function stat_row(label, value)
    ImGui.TextColored(ctx, theme.text_dim, label)
    ImGui.SameLine(ctx, 140 * settings.ui_scale)
    push_font("stat")
    ImGui.TextColored(ctx, theme.stat_val, value)
    ImGui.PopFont(ctx)
end

-- Color editor row (ReaImGui ColorEdit4 uses packed 0xRRGGBBAA)
local function color_row(label, key)
    ImGui.PushID(ctx, key)
    local changed, new_col = ImGui.ColorEdit4(ctx, label, theme[key],
        K(ImGui.ColorEditFlags_NoInputs) | K(ImGui.ColorEditFlags_AlphaBar))
    if changed then
        theme[key] = new_col
        save_settings()
    end
    ImGui.PopID(ctx)
end

-- Distances from the threshold of the in-scope notes on one side of it
local function half_dxs(half)
    local above, list = (half == "above"), {}
    for _, take in ipairs(active_takes) do
        local d = takes_data[take]
        if d then
            for n = 0, d.note_cnt-1 do
                local o = d.orig_vels[n]
                if o and ((not use_selected) or d.sel_set[n]) then
                    local dx = o - threshold
                    if (above and dx > 0) or (not above and dx < 0) then list[#list+1] = dx end
                end
            end
        end
    end
    return list
end

-- Raw % range (100 * (1 - slope)) outside which every note of that half is
-- already pinned on the ceiling (127) or floor (1): moving further changes nothing.
-- nil when the half has no notes.
local function pinned_range(half, dxs, c)
    local thr, g = threshold, gain_val
    local span = (half == "above") and (127 - thr) or thr
    local s_hi, s_lo  -- slope at which all notes are pinned, going steeper / going inverted
    for _, dx in ipairs(dxs) do
        local D = bend(dx, span, c)
        if D ~= 0 then
            local ceil_s, floor_s = (127 - thr - g) / D, (1 - thr - g) / D
            local up   = (D > 0) and ceil_s or floor_s
            local down = (D > 0) and floor_s or ceil_s
            s_hi = math.max(s_hi or up, up)
            s_lo = math.min(s_lo or down, down)
        end
    end
    if not s_hi then return nil end
    return floor(100 * (1 - s_hi)), ceil(100 * (1 - s_lo))
end

-- v2.15: the % on the sliders is the *effective* one, measured on the notes: how much
-- their total distance from the threshold shrinks (+) or grows (−) after the bend
-- and the 1..127 clamp (Velocity ± is left out). Straight and unclamped it equals the
-- raw slope %, but it also follows Opt-drag bends. Notes close to the threshold
-- weigh little, so the number stays sensible at extreme settings.
local function effective_pct(half, dxs, p, c)
    if #dxs == 0 then return p end
    local thr  = threshold
    local span = (half == "above") and (127 - thr) or thr
    local s, num, den = 1 - p * 0.01, 0, 0
    for _, dx in ipairs(dxs) do
        local y = math.max(1, math.min(127, thr + bend(dx, span, c) * s))
        num, den = num + (y - thr), den + dx
    end
    return 100 * (1 - num / den)
end

local function shown_pct(half)
    local p = (half == "above") and above_val or below_val
    local c = (half == "above") and above_curve or below_curve
    return floor(effective_pct(half, half_dxs(half), p, c) + 0.5)
end

-- Inverse for the sliders: the raw % that gives `target` effective % with bend c.
-- effective_pct only grows with p (flat where notes are pinned), so bisect.
local function raw_pct(half, target, c)
    local dxs = half_dxs(half)
    if #dxs == 0 then return target end
    if target >= 100 then return 100 end              -- slope 0 = flat line
    local lo = pinned_range(half, dxs, c) or -10000
    local hi = 100
    lo = math.min(lo, -100)
    for _ = 1, 50 do
        local mid = (lo + hi) / 2
        if effective_pct(half, dxs, mid, c) < target then lo = mid else hi = mid end
    end
    return hi
end

local function set_shown_pct(half, v)
    if half == "above" then above_val = raw_pct("above", v, above_curve)
    else                    below_val = raw_pct("below", v, below_curve) end
    dirty = true
end

-- How far mouse edits on the graph may push one half's raw %: effective ±100 when
-- limited (+100 = flat line). Otherwise until every in-scope note of that half is
-- pinned on 127 / 1, but never tighter than the sliders' effective ±100.
local function mouse_range(half)
    local c = (half == "above") and above_curve or below_curve
    local lo, hi = raw_pct(half, -100, c), 100
    if settings.limit_rate then return lo, hi end
    local plo, phi = pinned_range(half, half_dxs(half), c)
    if not plo then return lo, hi end
    return math.min(lo, plo), math.max(hi, phi)
end

-- Turning the limit on pulls current and slot-stored values back to effective ±100
local function set_limit_rate(on)
    settings.limit_rate = on
    if on then
        local function fit(half, p, c)
            local e = effective_pct(half, half_dxs(half), p, c)
            if e > 100 then return 100 end
            if e < -100 then return raw_pct(half, -100, c) end
            return p
        end
        above_val, below_val = fit("above", above_val, above_curve), fit("below", below_val, below_curve)
        for _, s in ipairs(slots) do
            s.above, s.below = fit("above", s.above, s.ac), fit("below", s.below, s.bc)
        end
        dirty = true
    end
    save_settings()
end

-- Draw settings popup content
local function draw_settings()
    push_font("body")
    local ui = settings.ui_scale
    ImGui.Text(ctx, "UI Scale")
    ImGui.SameLine(ctx, 100*ui)
    if ImGui.Button(ctx, "-##uidown", 28*ui, 24*ui) then
        rebuild_fonts_if_needed(math.max(0.75, settings.ui_scale - 0.05))
        save_settings()
    end
    ImGui.SameLine(ctx)
    ImGui.Text(ctx, string.format("%.2fx", settings.ui_scale))
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "+##uiup", 28*ui, 24*ui) then
        rebuild_fonts_if_needed(math.min(2.5, settings.ui_scale + 0.05))
        save_settings()
    end

    ImGui.Separator(ctx)
    local ch_l, v_l = ImGui.Checkbox(ctx, "Limit compress rate in 100%", settings.limit_rate)
    if ch_l then set_limit_rate(v_l) end
    if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "Sliders always stop at ±100%. Unchecked, dragging the graph can go\n" ..
            "further: past +100% the line flips over, past -100% it gets steeper than x2.")
    end
    local ch_g, v_g = ImGui.Checkbox(ctx, "Show curve while bypassed", settings.bypass_ghost)
    if ch_g then settings.bypass_ghost = v_g; save_settings() end
    local ch_f, v_f = ImGui.Checkbox(ctx, "Flash notes during playback", settings.play_flash)
    if ch_f then settings.play_flash = v_f; save_settings() end
    if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "Each note lights up on the graph as it plays (100 ms attack / 100 ms release),\n" ..
            "coloured by velocity with your MIDI note colour map (Compress blue → red\n" ..
            "if the map can't be read; that needs js_ReaScriptAPI).")
    end

    ImGui.Separator(ctx)
    ImGui.Text(ctx, "Display Mode")
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Percent", not settings.show_ratio) then
        settings.show_ratio = false; save_settings()
    end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Ratio", settings.show_ratio) then
        settings.show_ratio = true; save_settings()
    end

    ImGui.Separator(ctx)
    ImGui.Text(ctx, "Theme Colors")
    for _, e in ipairs(THEME_EDITABLE) do color_row(e[2], e[1]) end

    ImGui.Separator(ctx)
    if ImGui.Button(ctx, "Reset theme to defaults") then
        for k, v in pairs(DEFAULT_THEME) do theme[k] = v end
        save_settings()
    end
    ImGui.SameLine(ctx)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_Button), theme.bypass_on)
    if ImGui.Button(ctx, "Reset ALL") then
        -- colours, UI scale, pin, checkboxes, display mode → factory defaults
        for k, v in pairs(DEFAULT_THEME) do theme[k] = v end
        rebuild_fonts_if_needed(DEFAULT_SETTINGS.ui_scale)
        for k, v in pairs(DEFAULT_SETTINGS) do settings[k] = v end
        set_limit_rate(settings.limit_rate)          -- also pulls values back if limited; saves
        reaper.DeleteExtState(EXT_SECTION, "range", true)   -- leftover from v2.11
    end
    ImGui.PopStyleColor(ctx)
    if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "Colours, UI scale (1.2×), pin window, checkboxes and display mode")
    end
    ImGui.PopFont(ctx)
end

-------------------------------------------------------------------------------
-- Main window
-------------------------------------------------------------------------------
-- Settings icon: 8 teeth (4 bars through the centre) + body + hole
local function draw_gear(dl, cx, cy, r, col)
    for i = 0, 3 do
        local a = i * math.pi / 4
        local dx, dy = math.cos(a) * r, math.sin(a) * r
        ImGui.DrawList_AddLine(dl, cx - dx, cy - dy, cx + dx, cy + dy, col, r * 0.38)
    end
    ImGui.DrawList_AddCircleFilled(dl, cx, cy, r * 0.72, col)
    ImGui.DrawList_AddCircleFilled(dl, cx, cy, r * 0.3, theme.bg)
end

local function lighten(c, k)
    local r, g, b, a = unpack_rgba(c)
    return rgba(r + (255-r)*k, g + (255-g)*k, b + (255-b)*k, a)
end

-- Arc with an arrowhead at a1 (radians; screen y points down, so a1 > a0 = clockwise)
local function draw_arc_arrow(dl, cx, cy, r, a0, a1, col, thick)
    ImGui.DrawList_PathArcTo(dl, cx, cy, r, a0, a1)
    ImGui.DrawList_PathStroke(dl, col, 0, thick)
    local ex, ey = cx + r * math.cos(a1), cy + r * math.sin(a1)
    local dir    = (a1 > a0) and 1 or -1
    local tx, ty = -math.sin(a1) * dir, math.cos(a1) * dir    -- travel direction at the end
    local nx, ny = math.cos(a1), math.sin(a1)                 -- outward normal
    local h = thick * 2.2
    ImGui.DrawList_AddTriangleFilled(dl, ex + tx*h, ey + ty*h,
        ex + nx*h*0.9, ey + ny*h*0.9, ex - nx*h*0.9, ey - ny*h*0.9, col)
end

local function draw_undo(dl, cx, cy, r, col)   -- ↶
    draw_arc_arrow(dl, cx, cy + r*0.15, r*0.75, math.pi/3, -math.pi, col, r*0.18)
end
local function draw_redo(dl, cx, cy, r, col)   -- ↷
    draw_arc_arrow(dl, cx, cy + r*0.15, r*0.75, math.pi*2/3, math.pi*2, col, r*0.18)
end

-- Push pin: upright when pinned, tilted when not
local function draw_pin(dl, cx, cy, r, col, pinned)
    local a = pinned and 0 or math.pi / 4
    local ca, sa = math.cos(a), math.sin(a)
    local function P(x, y) return cx + x*ca - y*sa, cy + x*sa + y*ca end
    local hx, hy = P(0, -r*0.45)
    ImGui.DrawList_AddCircleFilled(dl, hx, hy, r*0.38, col)                         -- head
    local x1, y1 = P(-r*0.55, -r*0.05)
    local x2, y2 = P( r*0.55, -r*0.05)
    ImGui.DrawList_AddLine(dl, x1, y1, x2, y2, col, r*0.22)                         -- collar
    local n1x, n1y = P(0, -r*0.05)
    local n2x, n2y = P(0,  r*0.95)
    ImGui.DrawList_AddLine(dl, n1x, n1y, n2x, n2y, col, math.max(1, r*0.12))       -- needle
end

-- Header icon button: grey (accent when `on`), lighter on hover, faded when disabled
local function icon_button(id, sz, tip, enabled, on, paint)
    local clicked = ImGui.InvisibleButton(ctx, id, sz, sz)
    local x0, y0  = ImGui.GetItemRectMin(ctx)
    local hov     = ImGui.IsItemHovered(ctx)
    local col     = on and theme.accent or theme.icon
    if not enabled then col = (theme.icon & 0xFFFFFF00) | 0x50
    elseif hov then col = lighten(col, 0.4) end
    paint(ImGui.GetWindowDrawList(ctx), x0 + sz/2, y0 + sz/2, sz * 0.42, col)
    if hov then ImGui.SetTooltip(ctx, tip) end
    return clicked and enabled
end

local function snapshot()
    local s = { above = above_val, below = below_val, humanize = humanize_val, gain = gain_val,
                ac = above_curve, bc = below_curve, mode = threshold_mode, custom = custom_thr,
                slot = active_slot, slots = {} }
    local parts = { s.above, s.below, s.humanize, s.gain, s.ac, s.bc, s.mode, s.custom, s.slot }
    for i, v in ipairs(slots) do
        s.slots[i] = { above = v.above, below = v.below, humanize = v.humanize,
                       gain = v.gain, ac = v.ac, bc = v.bc }
        parts[#parts+1] = table.concat({ v.above, v.below, v.humanize, v.gain, v.ac, v.bc }, ",")
    end
    s.key = table.concat(parts, "|")
    return s
end

local function restore(s)
    above_val, below_val, humanize_val, gain_val = s.above, s.below, s.humanize, s.gain
    above_curve, below_curve = s.ac, s.bc
    threshold_mode, custom_thr, active_slot = s.mode, s.custom, s.slot
    for i, v in ipairs(s.slots) do
        local d = slots[i]
        d.above, d.below, d.humanize, d.gain, d.ac, d.bc = v.above, v.below, v.humanize, v.gain, v.ac, v.bc
    end
    if stats.has then threshold = current_threshold() end
    committed = s
    need_reapply = true
end

local function undo()
    if #undo_stack == 0 then return end
    redo_stack[#redo_stack+1] = committed or snapshot()
    restore(table.remove(undo_stack))
end

local function redo()
    if #redo_stack == 0 then return end
    undo_stack[#undo_stack+1] = committed or snapshot()
    restore(table.remove(redo_stack))
end

-- Once per frame after the UI: while nothing is held, a changed state = one finished edit
local function track_history()
    if ImGui.IsAnyItemActive(ctx) then return end
    local now = snapshot()
    if committed and now.key ~= committed.key then
        undo_stack[#undo_stack+1] = committed
        if #undo_stack > MAX_UNDO then table.remove(undo_stack, 1) end
        redo_stack = {}
    end
    committed = now
end

-- Separator limited to one column (ImGui.Separator spans the whole window)
local function hline(w)
    local x, y = ImGui.GetCursorScreenPos(ctx)
    ImGui.DrawList_AddLine(ImGui.GetWindowDrawList(ctx), x, y, x + w, y, theme.border, 1)
    ImGui.Dummy(ctx, w, 1)
end

-- Slider on a custom track: rounded background, a centre tick for bipolar ranges
-- and a slim fill from `origin` to the value. `paint(x, y, w, h)` replaces the
-- background (Compress gradient). The ImGui frame itself is made transparent.
local function track_slider(dl, id, val, lo, hi, w, origin, paint)
    local ui   = settings.ui_scale
    local x, y = ImGui.GetCursorScreenPos(ctx)
    local h    = ImGui.GetFrameHeight(ctx)
    local function px(v) return x + w * (math.max(lo, math.min(hi, v)) - lo) / (hi - lo) end
    if paint then
        paint(x, y, w, h)
    else
        ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, theme.panel, 4*ui)
        local a, b = px(origin), px(val)
        if a > b then a, b = b, a end
        if b - a >= 1 then
            ImGui.DrawList_AddRectFilled(dl, a, y + h*0.38, b, y + h*0.62,
                (theme.slider & 0xFFFFFF00) | 0x90, 2*ui)
        end
    end
    if origin > lo then
        local cx = px(origin)
        ImGui.DrawList_AddLine(dl, cx, y + h*0.2, cx, y + h*0.8, (theme.text_dim & 0xFFFFFF00) | 0x80, 1)
    end
    ImGui.PushStyleColor(ctx, K(ImGui.Col_FrameBg),        0)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_FrameBgHovered), 0)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_FrameBgActive),  0)
    ImGui.SetNextItemWidth(ctx, w)
    local ch, v = ImGui.SliderInt(ctx, id, val, lo, hi, "")
    ImGui.PopStyleColor(ctx, 3)
    return ch, v
end

-- Left column: statistics, threshold, sliders.
-- Returns the screen y of the Threshold row top and the Humanize slider bottom
-- (the graph on the right spans exactly that height).
local function draw_controls(dl, ui, col_w)
    local _, stats_top = ImGui.GetCursorScreenPos(ctx)
    if stats.has then
        stat_row("Note count",      tostring(stats.cnt))
        stat_row("Average vel",     tostring(stats.avg))
        stat_row("Median vel",      tostring(stats.med))
        stat_row("Mode vel",        tostring(stats.mod))
        stat_row("Min — Max",       string.format("%d — %d", stats.min, stats.max))
    else
        -- placeholders keep the layout (and the fitted window height) steady
        for _, l in ipairs({ "Note count", "Average vel", "Median vel", "Mode vel", "Min — Max" }) do
            stat_row(l, "—")
        end
    end
    local _, stats_bot = ImGui.GetItemRectMax(ctx)

    ImGui.Dummy(ctx, 0, 6*ui)
    hline(col_w)
    ImGui.Dummy(ctx, 0, 4*ui)
    local _, top_y = ImGui.GetCursorScreenPos(ctx)

    -- Threshold selector — single button that cycles through modes
    ImGui.Text(ctx, "Threshold")
    ImGui.SameLine(ctx, 100*ui)
    local mode_order  = { "avg", "med", "mod", "custom" }
    local mode_labels = { avg="Average", med="Median", mod="Mode", custom="Custom" }
    if ImGui.Button(ctx, mode_labels[threshold_mode] or "Average", 90*ui, 0) then
        local next_idx = 1
        for i, m in ipairs(mode_order) do
            if m == threshold_mode then
                next_idx = (i % #mode_order) + 1
                break
            end
        end
        threshold_mode = mode_order[next_idx]
        if threshold_mode == "custom" and stats.has then
            custom_thr = threshold  -- seed custom with current value
        end
        if stats.has then threshold = current_threshold() end
    end
    if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "Click to cycle: Average → Median → Mode → Custom")
    end

    -- Threshold display / editor
    ImGui.SameLine(ctx)
    if threshold_mode == "custom" then
        push_font("stat")
        ImGui.TextColored(ctx, theme.accent, "=")
        ImGui.PopFont(ctx)
        ImGui.SameLine(ctx)
        ImGui.SetNextItemWidth(ctx, 60*ui)
        local ch_t, v_t = ImGui.InputInt(ctx, "##thr_custom", custom_thr, 0, 0)
        if ch_t then
            if v_t < 1   then v_t = 1   end
            if v_t > 127 then v_t = 127 end
            custom_thr = v_t
            threshold  = v_t
            need_reapply = true
        end
    else
        push_font("stat")
        ImGui.TextColored(ctx, theme.accent, string.format("= %d", threshold))
        ImGui.PopFont(ctx)
    end

    ImGui.Dummy(ctx, 0, 4*ui)

    local enabled = stats.has
    if not enabled then ImGui.BeginDisabled(ctx) end

    -- Compress — moves both Above and Below together
    local shown_a, shown_b = shown_pct("above"), shown_pct("below")
    local master_val = floor((shown_a + shown_b) / 2 + 0.5)
    ImGui.Text(ctx, "Compress")
    ImGui.SameLine(ctx)
    ImGui.TextColored(ctx, theme.text_dim, format_value(master_val))
    -- track: expand colour at the left end → panel at 0 → compress colour at the right end
    -- (gradients can't be rounded, so the ends are rounded caps in the end colours)
    local function compress_track(x, y, w, h)
        local r, mid = 4*ui, x + w / 2
        ImGui.DrawList_AddRectFilled(dl, x, y, x + r + 1, y + h, theme.comp_expand, r,
            K(ImGui.DrawFlags_RoundCornersLeft))
        ImGui.DrawList_AddRectFilled(dl, x + w - r - 1, y, x + w, y + h, theme.comp_compress, r,
            K(ImGui.DrawFlags_RoundCornersRight))
        ImGui.DrawList_AddRectFilledMultiColor(dl, x + r, y, mid, y + h,
            theme.comp_expand, theme.panel, theme.panel, theme.comp_expand)
        ImGui.DrawList_AddRectFilledMultiColor(dl, mid, y, x + w - r, y + h,
            theme.panel, theme.comp_compress, theme.comp_compress, theme.panel)
    end
    local ch_m, v_m = track_slider(dl, "##master", master_val, -100, 100, col_w, 0, compress_track)
    if ch_m then
        set_shown_pct("above", v_m)
        set_shown_pct("below", v_m)
    end
    if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked(ctx, 0) then
        above_val, below_val = 0, 0; dirty = true
    end

    ImGui.Dummy(ctx, 0, 6*ui)

    -- Fine — [Below] [Above mirrored], junction = threshold
    ImGui.Text(ctx, "Below")
    ImGui.SameLine(ctx, col_w/2 + 40*ui)
    ImGui.Text(ctx, "Above")

    local half_w = (col_w - 8*ui) / 2

    -- Below: drag RIGHT (toward center) = compress, LEFT = expand
    local ch_b, v_b = track_slider(dl, "##below", shown_b, -100, 100, half_w, 0)
    if ch_b then set_shown_pct("below", v_b) end
    if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked(ctx, 0) then
        below_val = 0; dirty = true
    end
    ImGui.SameLine(ctx, 0, 8*ui)
    -- Above: mirrored — display = -internal; drag LEFT (toward center) = compress
    local above_disp = -shown_a
    local ch_a, v_ad = track_slider(dl, "##above", above_disp, -100, 100, half_w, 0)
    if ch_a then set_shown_pct("above", -v_ad) end
    if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked(ctx, 0) then
        above_val = 0; dirty = true
    end

    -- Value labels under each (showing compression semantic)
    ImGui.PushStyleColor(ctx, K(ImGui.Col_Text), theme.text_dim)
    push_font("small")
    ImGui.Text(ctx, string.format("%s", format_value(shown_b)))
    ImGui.SameLine(ctx, half_w + 16*ui)
    ImGui.Text(ctx, string.format("%s", format_value(shown_a)))
    ImGui.PopFont(ctx)
    ImGui.PopStyleColor(ctx)

    ImGui.Dummy(ctx, 0, 6*ui)
    ImGui.Text(ctx, "Velocity  ±")
    ImGui.SameLine(ctx)
    ImGui.TextColored(ctx, theme.text_dim, string.format("%+d", gain_val))
    local ch_g, v_g = track_slider(dl, "##gain", gain_val, -127, 127, col_w, 0)
    if ch_g then gain_val = v_g; dirty = true end
    if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "Add / subtract velocity after compression (double-click = 0)")
        if ImGui.IsMouseDoubleClicked(ctx, 0) then gain_val = 0; dirty = true end
    end

    ImGui.Dummy(ctx, 0, 6*ui)
    ImGui.Text(ctx, "Humanize  ±")
    ImGui.SameLine(ctx)
    ImGui.TextColored(ctx, theme.text_dim, string.format("%d", humanize_val))
    local ch_h, v_h = track_slider(dl, "##hum", humanize_val, 0, 30, col_w, 0)
    if ch_h then humanize_val = v_h; dirty = true end
    if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "Random ± velocity per note, after compression (double-click = 0).\n" ..
            "Each note keeps its own direction; the slider only scales how far.")
        if ImGui.IsMouseDoubleClicked(ctx, 0) then humanize_val = 0; dirty = true end
    end
    local _, bot_y = ImGui.GetItemRectMax(ctx)

    if not enabled then ImGui.EndDisabled(ctx) end
    return stats_top, stats_bot, top_y, bot_y
end

-- Right column, top: Reset · Bypass · A / B / C / D
local function draw_buttons(dl, ui, w, btn_h)
    local big_sz = font_sizes.stat * 1.35
    local sp     = 8*ui
    local btn_w  = (w - 2*sp) * 0.25          -- Reset / Bypass: a quarter each, slots: the rest
    local cell   = (w - 2*sp - 2*btn_w) / #SLOT_NAMES
    -- Positioned explicitly: this group sits on the left column's line, so SameLine()
    -- would snap Bypass / slots back up to that line's y.
    local bx, by = ImGui.GetCursorScreenPos(ctx)

    if ImGui.Button(ctx, "Reset", btn_w, btn_h) then
        reset_values()
    end
    if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "Restore original velocities (session snapshot)")
    end

    ImGui.SetCursorScreenPos(ctx, bx + btn_w + sp, by)
    local was_on = bypass
    if was_on then
        ImGui.PushStyleColor(ctx, K(ImGui.Col_Button),        theme.bypass_on)
        ImGui.PushStyleColor(ctx, K(ImGui.Col_ButtonHovered), theme.bypass_on)
        ImGui.PushStyleColor(ctx, K(ImGui.Col_ButtonActive),  theme.bypass_on)
    end
    if ImGui.Button(ctx, "Bypass", btn_w, btn_h) then
        bypass = not bypass
        need_reapply = true
    end
    if was_on then ImGui.PopStyleColor(ctx, 3) end
    if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "Hear the original velocities; slider settings are kept")
    end

    -- Preset slots: click a letter to store the sliders into the current slot and
    -- load that one. The active slot is drawn big in the accent colour.
    local n      = #SLOT_NAMES
    local sx, sy = bx + 2 * (btn_w + sp), by
    ImGui.DrawList_AddRectFilled(dl, sx, sy, sx + cell*n, sy + btn_h, theme.panel, 4*ui)
    for i, name in ipairs(SLOT_NAMES) do
        ImGui.SetCursorScreenPos(ctx, sx + (i-1) * cell, sy)
        if ImGui.InvisibleButton(ctx, "##slot"..name, cell, btn_h) and i ~= active_slot then
            switch_slot(i)
        end
        local x = sx + (i-1) * cell
        local hov = ImGui.IsItemHovered(ctx)
        if hov then
            ImGui.SetTooltip(ctx, "Preset slots: click to switch; edits go into the big letter")
        end
        -- active = big accent; hovered = bold accent; others = plain text
        local on = (i == active_slot)
        ImGui.PushFont(ctx, (on or hov) and fonts.stat or fonts.body, on and big_sz or font_sizes.body)
        local tw, th = ImGui.CalcTextSize(ctx, name)
        ImGui.DrawList_AddText(dl, x + (cell - tw) / 2, sy + (btn_h - th) / 2,
            (on or hov) and theme.accent or theme.text, name)
        ImGui.PopFont(ctx)
    end
    push_font("body")
    local sw, sh = ImGui.CalcTextSize(ctx, "/")
    for i = 1, n - 1 do
        ImGui.DrawList_AddText(dl, sx + i*cell - sw/2, sy + (btn_h - sh) / 2, theme.text_dim, "/")
    end
    ImGui.PopFont(ctx)
    ImGui.DrawList_AddRect(dl, sx, sy, sx + cell*n, sy + btn_h, theme.border, 4*ui)
end

-- Right column, below the buttons: transfer curve.
-- x = original velocity, y = result; dots = notes in scope
-- Mouse: empty area = set Custom threshold / drag a half of the curve = bend it
--        around the threshold / Opt-drag a half = curve it (ends stay put) /
--        drag the junction dot = rotate both halves / double-click = reset
-- Paper grain for the graph background: fixed random specks in 0..1 coordinates,
-- generated once with a private LCG (math.random stays untouched for Humanize).
local GRAIN = {}
do
    local seed = 12345
    local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
    for i = 1, 1400 do
        GRAIN[i] = { rnd(), rnd(), 0.6 + rnd() * 1.0,                -- x, y, size (× ui px)
                     rnd() < 0.55 and 0xFFFFFF00 or 0x00000000,      -- light or dark speck
                     14 + floor(rnd() * 24) }                         -- alpha 14..37 of 255
    end
end

local function draw_grain(dl, gx, gy, gw, gh, ui)
    local n = math.min(#GRAIN, floor(gw * gh / (130 * ui * ui)))   -- constant density
    for i = 1, n do
        local g = GRAIN[i]
        local x, y, sz = gx + g[1] * gw, gy + g[2] * gh, g[3] * ui
        ImGui.DrawList_AddRectFilled(dl, x, y, x + sz, y + sz, g[4] | g[5])
    end
end

local function darken(c, k)
    local r, g, b, a = unpack_rgba(c)
    return rgba(r * (1-k), g * (1-k), b * (1-k), a)
end

-- Graph canvas: a touch darker than the panel (sliders), plus paper grain
local function draw_canvas(dl, gx, gy, gw, gh, ui)
    ImGui.DrawList_AddRectFilled(dl, gx, gy, gx+gw, gy+gh, darken(theme.panel, 0.18), 4*ui)
    draw_grain(dl, gx, gy, gw, gh, ui)
end

-- No usable notes: the same canvas with a hint in the title font
local function draw_empty_graph(dl, ui, gw, gh, msg)
    local gx, gy = ImGui.GetCursorScreenPos(ctx)
    ImGui.Dummy(ctx, gw, gh)
    draw_canvas(dl, gx, gy, gw, gh, ui)
    ImGui.DrawList_AddLine(dl, gx, gy + gh, gx + gw, gy, (theme.diagonal & 0xFFFFFF00) | 0x50, 1)
    push_font("h1")
    local lines = {}
    for l in msg:gmatch("[^\n]+") do lines[#lines+1] = l end
    local lh = ImGui.GetTextLineHeightWithSpacing(ctx)
    local y  = gy + (gh - lh * #lines) / 2
    for i, l in ipairs(lines) do
        local tw = ImGui.CalcTextSize(ctx, l)
        ImGui.DrawList_AddText(dl, gx + (gw - tw) / 2, y + (i-1) * lh, theme.text_dim, l)
    end
    ImGui.PopFont(ctx)
    ImGui.DrawList_AddRect(dl, gx, gy, gx+gw, gy+gh, theme.border, 4*ui)
end

-- Playback flash colour: velocity 1 → 127 along the Compress blue → red, interpolated
-- in HSV (the short way round the hue circle) with saturation / brightness pushed up.
-- Velocity colours from the user's MIDI note colour map (Preferences → MIDI editor →
-- default colour map, reaper.ini "mididefcolormap"). That PNG holds 12 pitch colours,
-- then 128 velocity colours (x = 12 + velocity), then the channel colours; the top
-- half is the note fill. Reading pixels needs js_ReaScriptAPI — without it (or the
-- file) VEL_COLORS stays nil and flashes fall back to flash_palette().
local function load_velocity_colormap()
    if not reaper.JS_LICE_LoadPNG then return nil end
    local path
    local f = io.open(reaper.get_ini_file(), "r")
    if not f then return nil end
    for line in f:lines() do
        path = line:match("^mididefcolormap=(.-)%s*$")
        if path then break end
    end
    f:close()
    if not path or path == "" then return nil end
    if not (path:match("^/") or path:match("^%a:")) then        -- relative to the resource folder
        path = reaper.GetResourcePath() .. "/" .. path
    end
    local bmp = reaper.JS_LICE_LoadPNG(path)
    if not bmp then return nil end
    local map
    if reaper.JS_LICE_GetWidth(bmp) >= 140 then
        map = {}
        local y = floor(reaper.JS_LICE_GetHeight(bmp) / 4)
        for v = 0, 127 do
            local c = reaper.JS_LICE_GetPixel(bmp, 12 + v, y)   -- 0xAARRGGBB
            map[v] = rgba((c >> 16) & 255, (c >> 8) & 255, c & 255, 0)
        end
    end
    reaper.JS_LICE_DestroyBitmap(bmp)
    return map
end
local VEL_COLORS = load_velocity_colormap()

local function flash_palette()
    local function hsv(c)
        local r, g, b = unpack_rgba(c)
        return ImGui.ColorConvertRGBtoHSV(r / 255, g / 255, b / 255)
    end
    local h1, s1, v1 = hsv(theme.comp_expand)
    local h2, s2, v2 = hsv(theme.comp_compress)
    local dh = h2 - h1
    if dh > 0.5 then dh = dh - 1 elseif dh < -0.5 then dh = dh + 1 end
    return function(vel, alpha)
        local t = (vel - 1) / 126
        local h = (h1 + dh * t) % 1
        local sat = math.min(1, (s1 + (s2 - s1) * t) * 1.25 + 0.1)
        local val = math.min(1, (v1 + (v2 - v1) * t) * 1.15 + 0.05)
        local r, g, b = ImGui.ColorConvertHSVtoRGB(h, sat, val)
        return rgba(r * 255, g * 255, b * 255, alpha)
    end
end

-- Soft halo. ImGui has no radial gradient, so stack HALO_N translucent discs, the
-- small ones on top: opacity builds up toward the centre. Layer alphas are chosen
-- so the total falls off as (1 - distance)² — bright core, feathered rim.
local HALO_N = 10
local HALO_W = {}
for j = 1, HALO_N do
    HALO_W[j] = (1 - (j-1)/HALO_N)^2 - (1 - j/HALO_N)^2    -- layer j has radius j/N
end

local function draw_halo(dl, x, y, radius, rgb0, peak)   -- rgb0 = colour with alpha 0
    for j = HALO_N, 1, -1 do
        ImGui.DrawList_AddCircleFilled(dl, x, y, radius * j / HALO_N,
            rgb0 | math.min(255, floor(peak * HALO_W[j] + 0.5)))
    end
end

-- Ruler above the graph: ticks every 8 (long every 32), "0" / "127" at the ends and
-- the current threshold over the junction (end labels hide when it would overlap).
local function ruler_height()
    return font_sizes.small + 9 * settings.ui_scale
end

local function draw_ruler(dl, ui, x, y, w, h, thr)
    local base = y + h                                   -- ticks stand on the graph's top edge
    local tick = (theme.text_dim & 0xFFFFFF00) | 0x70
    for v = 0, 127, 8 do
        local tx = x + w * v / 127
        ImGui.DrawList_AddLine(dl, tx, base, tx, base - ((v % 32 == 0) and 5 or 2.5) * ui, tick, 1)
    end
    ImGui.DrawList_AddLine(dl, x + w, base, x + w, base - 5*ui, tick, 1)

    ImGui.PushFont(ctx, fonts.body, font_sizes.small)
    local ty = y + 1*ui
    local w0, w127 = ImGui.CalcTextSize(ctx, "0"), ImGui.CalcTextSize(ctx, "127")
    local l0, r0     = x + 2*ui, x + 2*ui + w0                -- "0" span
    local l127, r127 = x + w - 2*ui - w127, x + w - 2*ui      -- "127" span
    local show0, show127 = true, true
    if thr then
        ImGui.PushFont(ctx, fonts.stat, font_sizes.small)
        local label = tostring(thr)
        local tw = ImGui.CalcTextSize(ctx, label)
        local cx = x + w * thr / 127
        local lx = math.max(x, math.min(x + w - tw, cx - tw / 2))
        show0   = lx > r0 + 4*ui
        show127 = lx + tw < l127 - 4*ui
        ImGui.DrawList_AddText(dl, lx, ty, theme.accent, label)
        ImGui.DrawList_AddTriangleFilled(dl, cx - 3.5*ui, base - 5*ui, cx + 3.5*ui, base - 5*ui,
            cx, base, theme.accent)                       -- marker pointing at the junction
        ImGui.PopFont(ctx)
    end
    if show0   then ImGui.DrawList_AddText(dl, l0,   ty, theme.text_dim, "0")   end
    if show127 then ImGui.DrawList_AddText(dl, l127, ty, theme.text_dim, "127") end
    ImGui.PopFont(ctx)
end

local function draw_graph(dl, ui, gw, gh)
    local gx, gy = ImGui.GetCursorScreenPos(ctx)
    local function X(v) return gx + gw * v / 127 end
    local function Y(v) return gy + gh - gh * math.max(0, math.min(127, v)) / 127 end
    local function out(v) return transform(v, threshold, above_val, below_val, gain_val, above_curve, below_curve) end
    local function clamp_p(p, half)
        local lo, hi = mouse_range(half)
        return math.max(lo, math.min(hi, floor(p + 0.5)))
    end
    local function clamp_c(c) return math.max(-4, math.min(4, c)) end

    ImGui.InvisibleButton(ctx, "##curve", gw, gh)
    local mx, my = ImGui.GetMousePos(ctx)
    local vx = math.max(0, math.min(127, (mx - gx) / gw * 127))  -- velocity under mouse
    local vy = (gy + gh - my) / gh * 127
    local alt = (ImGui.GetKeyMods(ctx) & K(ImGui.Mod_Alt)) ~= 0

    -- What would a click here grab? junction dot > curve > empty area
    local function hit()
        local r = 6*ui
        if math.abs(mx - X(threshold)) <= 8*ui and math.abs(my - Y(threshold + gain_val)) <= 8*ui then
            return "rotate"
        end
        if math.abs(my - Y(out(vx))) <= r then
            return (vx >= threshold and "above" or "below") .. (alt and "_curve" or "")
        end
        return "thr"
    end

    if ImGui.IsItemActivated(ctx) then
        local m = hit()
        local p = (vx >= threshold) and above_val or below_val
        graph_drag = { mode = m, x = vx, y = my, a = above_val, b = below_val,
                       ac = above_curve, bc = below_curve,
                       off = vy - out(vx),                         -- grab point vs. line height
                       sgn = (1 - p * 0.01) >= 0 and 1 or -1 }     -- slope direction of the grabbed half
    end

    -- Double-click: same as double-clicking the matching slider (also straightens the curve)
    if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked(ctx, 0) then
        local m = hit()
        if m:match("^above") or m == "rotate" then above_val, above_curve = 0, 0 end
        if m:match("^below") or m == "rotate" then below_val, below_curve = 0, 0 end
        if m ~= "thr" then graph_drag = nil; dirty = true end
    end

    local dragging = ImGui.IsItemActive(ctx) and graph_drag
    if dragging then
        local g = graph_drag
        local up = (g.y - my) / ui        -- pixels dragged upward
        if g.mode == "thr" then
            local t = math.max(1, floor(vx + 0.5))
            threshold_mode, custom_thr, threshold = "custom", t, t
        elseif g.mode == "rotate" then
            -- 1 step per pixel; up = clockwise = compress, down = expand
            above_val, below_val = clamp_p(g.a + up, "above"), clamp_p(g.b + up, "below")
        elseif g.mode == "above_curve" then
            -- up = bow the middle upward, whichever way the half slopes
            above_curve = clamp_c(g.ac - up * 0.02 * g.sgn)
        elseif g.mode == "below_curve" then
            below_curve = clamp_c(g.bc + up * 0.02 * g.sgn)
        else
            -- Solve the % that makes this half pass through the mouse height
            -- at the grabbed x (inverse of transform()).
            local dx = (g.mode == "above") and bend(g.x - threshold, 127 - threshold, above_curve)
                                            or bend(g.x - threshold, threshold, below_curve)
            if math.abs(dx) < 1 then dx = (g.mode == "above") and 1 or -1 end
            local p = clamp_p(100 * (1 - (vy - g.off - gain_val - threshold) / dx), g.mode)
            if g.mode == "above" then above_val = p else below_val = p end
        end
        dirty = true
    end

    local mode = dragging and graph_drag.mode or (ImGui.IsItemHovered(ctx) and hit())
    if mode then
        ImGui.SetMouseCursor(ctx, K(mode == "thr" and ImGui.MouseCursor_Hand or ImGui.MouseCursor_ResizeNS))
        local v = floor(vx + 0.5)
        if mode == "thr" then
            ImGui.SetTooltip(ctx, string.format("%d", v))
        elseif mode == "rotate" then
            ImGui.SetTooltip(ctx, string.format("Threshold %d   ↑ compress / ↓ expand", threshold))
        elseif mode:match("_curve$") then
            ImGui.SetTooltip(ctx, "Curve   ↑ bow up / ↓ bow down   (double-click = reset)")
        else
            ImGui.SetTooltip(ctx, string.format("%d → %d   (%s-drag = curve)", v, floor(out(v) + 0.5), KEY_ALT))
        end
    end

    draw_canvas(dl, gx, gy, gw, gh, ui)
    -- 1:1 line in its own colour; thicker while bypassed (it is what you hear then)
    ImGui.DrawList_AddLine(dl, X(0), Y(0), X(127), Y(127), theme.diagonal, bypass and 2*ui or 1)
    -- No permanent threshold line (the junction icon marks it). A faint guide at the
    -- mouse only while hovering empty space / dragging the threshold: where a click lands.
    if mode == "thr" then
        local x = X(vx)
        ImGui.DrawList_AddLine(dl, x, gy, x, gy+gh, (theme.text_dim & 0xFFFFFF00) | 0x50, 1)
    end

    -- Bypassed: the settings curve stays where it is as a ghost (or hidden)
    local curve_col = theme.accent
    if bypass then
        curve_col = settings.bypass_ghost and ((theme.accent & 0xFFFFFF00) | 0x28) or nil
    end
    if curve_col then
        local glow = (curve_col & 0xFFFFFF00) | ((curve_col & 0xFF) // 5)
        local px, py
        for v = 0, 127 do
            local nx, ny = X(v), Y(out(v))
            if px then
                ImGui.DrawList_AddLine(dl, px, py, nx, ny, glow, 6*ui)
                ImGui.DrawList_AddLine(dl, px, py, nx, ny, curve_col, 2*ui)
            end
            px, py = nx, ny
        end
    end

    local dot = (theme.stat_val & 0xFFFFFF00) | 0xE0

    -- Playback flash: attack FLASH_A, lit while the note sounds (halo grows with how
    -- long it has been held), then release = max(FLASH_R, note length / 3).
    -- Per take: two play-position → PPQ conversions per frame and plain comparisons;
    -- only the lit notes get their exact times converted.
    local FLASH_A, FLASH_R = 0.015, 0.1   -- attack 15 ms (snappy), minimum release 100 ms
    local playing = settings.play_flash and (reaper.GetPlayState() & 5) ~= 0   -- playing or recording
    local play_pos = playing and reaper.GetPlayPosition() or 0
    local flashes = {}

    for _, take in ipairs(active_takes) do
        local d = takes_data[take]
        local p_now, p_then, p_rel
        if playing and d then
            p_now  = reaper.MIDI_GetPPQPosFromProjTime(take, play_pos)
            p_then = reaper.MIDI_GetPPQPosFromProjTime(take, play_pos - FLASH_A - FLASH_R)
            p_rel  = reaper.MIDI_GetPPQPosFromProjTime(take, play_pos - FLASH_R)
        end
        if d then
            for n = 0, d.note_cnt-1 do
                local o = d.orig_vels[n]
                if o and ((not use_selected) or d.sel_set[n]) then
                    local r = o
                    if not bypass then   -- same result as apply_to_take: curve + humanize, 1..127
                        r = out(o) + (humanize_val > 0 and d.hum_offs[n] * humanize_val or 0)
                        r = math.max(1, math.min(127, r))
                    end
                    ImGui.DrawList_AddCircleFilled(dl, X(o), Y(r), 2.1*ui, dot)
                    local sp = p_now and d.start_ppq[n]
                    local ep = sp and d.end_ppq[n]
                    -- candidate: started, and still in attack / held / release (PPQ estimate)
                    if sp and sp <= p_now and (sp > p_then or ep >= p_rel or ep + (ep - sp) / 3 >= p_now) then
                        local ts  = reaper.MIDI_GetProjTimeFromPPQPos(take, sp)
                        local te  = reaper.MIDI_GetProjTimeFromPPQPos(take, ep)
                        local e   = play_pos - ts
                        local lit = math.max(te, ts + FLASH_A)          -- lit until note-off (≥ attack)
                        local a
                        if play_pos <= lit then a = math.min(1, e / FLASH_A)
                        else a = 1 - (play_pos - lit) / math.max(FLASH_R, (te - ts) / 3) end
                        if a > 0 then
                            local grow = math.min(1, math.min(e, te - ts) / 2)   -- 0..1 over 2 s held
                            flashes[#flashes+1] = { X(o), Y(r), a, r, grow }
                        end
                    end
                end
            end
        end
    end

    -- Flashes on top: halo (bigger the longer the note is held) + bright core
    if #flashes > 0 then
        local col = (not VEL_COLORS) and flash_palette()
        for _, f in ipairs(flashes) do
            local a, grow = f[3], f[5]
            local rgb0 = VEL_COLORS and VEL_COLORS[floor(f[4] + 0.5)] or col(f[4], 0)
            draw_halo(dl, f[1], f[2], (4 + a * (9 + 14 * grow)) * ui, rgb0, 200 * a)
            ImGui.DrawList_AddCircleFilled(dl, f[1], f[2], (2.1 + 1.5 * a) * ui, rgb0 | floor(255 * a))
        end
    end
    -- Junction handle (drag to rotate): clockwise-arrow icon, highlighted while hot
    local hx, hy = X(threshold), Y(threshold + gain_val)
    local hcol   = (mode == "rotate") and theme.slider_act or theme.text_dim
    ImGui.DrawList_AddCircleFilled(dl, hx, hy, 9*ui, (darken(theme.panel, 0.18) & 0xFFFFFF00) | 0xD0)   -- backdrop
    draw_arc_arrow(dl, hx, hy, 6*ui, -math.pi*0.2, math.pi*1.3, hcol, 1.6*ui)
    ImGui.DrawList_AddCircleFilled(dl, hx, hy, 1.8*ui, hcol)
    ImGui.DrawList_AddRect(dl, gx, gy, gx+gw, gy+gh, theme.border, 4*ui)          -- frame
end

local fit_h = nil   -- window height that fits the content (set by draw_main)

-- Version info right-aligned in the title bar, left of the close button
local function draw_title_version(dl)
    local wx, wy = ImGui.GetWindowPos(ctx)
    local ww     = ImGui.GetWindowSize(ctx)
    local th     = ImGui.GetFrameHeight(ctx)       -- title bar height (base font, before push_font)
    local txt    = string.format("v%s  ·  ReaImGui %s", VERSION, ImGui.GetVersion())
    local tw, tt = ImGui.CalcTextSize(ctx, txt)
    ImGui.DrawList_PushClipRect(dl, wx, wy, wx + ww, wy + th, false)
    ImGui.DrawList_AddText(dl, wx + ww - th - tw - 8 * settings.ui_scale, wy + (th - tt) / 2,
        theme.text_dim, txt)
    ImGui.DrawList_PopClipRect(dl)
end

local function draw_main()
    poll(false)

    local ui = settings.ui_scale
    local dl = ImGui.GetWindowDrawList(ctx)
    draw_title_version(dl)
    push_font("body")

    -- Right edge shared by gear, source strip, buttons and graph: the same gap to
    -- the window edge as between the two columns.
    local gap      = 20*ui
    local pad_x    = ImGui.GetStyleVar(ctx, K(ImGui.StyleVar_WindowPadding))
    local inset    = gap - pad_x

    -- Header: title + gear (settings)
    push_font("h1")
    ImGui.TextColored(ctx, theme.accent, "MIDI Note Compressor / Expander")
    ImGui.PopFont(ctx)
    -- Header icons, right-aligned: [undo][redo]  [pin]  [gear]
    local isz, sp, big = 26*ui, 4*ui, 12*ui
    ImGui.SameLine(ctx)
    local avail_w = ImGui.GetContentRegionAvail(ctx)
    ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + avail_w - inset - (4*isz + sp + 2*big))
    if icon_button("##undo", isz, string.format("Undo (%s+Z) — %d step%s", KEY_CMD, #undo_stack,
            #undo_stack == 1 and "" or "s"), #undo_stack > 0, false, draw_undo) then
        undo()
    end
    ImGui.SameLine(ctx, 0, sp)
    if icon_button("##redo", isz, string.format("Redo (%s+Shift+Z) — %d step%s", KEY_CMD, #redo_stack,
            #redo_stack == 1 and "" or "s"), #redo_stack > 0, false, draw_redo) then
        redo()
    end
    ImGui.SameLine(ctx, 0, big)
    if icon_button("##pin", isz, settings.pinned and "Unpin window" or "Pin window (always on top)",
            true, settings.pinned, function(d, cx, cy, r, col) draw_pin(d, cx, cy, r, col, settings.pinned) end) then
        settings.pinned = not settings.pinned
        save_settings()
    end
    ImGui.SameLine(ctx, 0, big)
    if icon_button("##settings", isz, "Settings", true, false, draw_gear) then
        show_settings = not show_settings
    end

    -- Source indicator: track / item of the first take
    local src_txt
    if #active_takes == 0 then
        src_txt = "(no MIDI take — open MIDI editor or select a MIDI item)"
    else
        local t = active_takes[1]
        local _, tr_name = reaper.GetTrackName(reaper.GetMediaItemTake_Track(t))
        src_txt = string.format("Source: %s / %s%s — %s",
            tr_name, reaper.GetTakeName(t),
            #active_takes > 1 and string.format("  (+%d more)", #active_takes - 1) or "",
            use_selected and "selected notes only" or "all notes")
    end
    -- Status strip: panel background, accent bar on the left, italic text 2pt above body
    do
        local x, y  = ImGui.GetCursorScreenPos(ctx)
        local w     = ImGui.GetContentRegionAvail(ctx) - inset
        ImGui.PushFont(ctx, fonts.small, font_sizes.body + 2)
        local tw, th = ImGui.CalcTextSize(ctx, src_txt)
        local h      = th + 8*ui
        ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, theme.panel, 4*ui)
        ImGui.DrawList_AddRectFilled(dl, x, y, x + 4*ui, y + h, theme.accent, 4*ui,
            K(ImGui.DrawFlags_RoundCornersLeft))
        -- Marquee when the text doesn't fit: pause, scroll one full loop, repeat
        local tx, room = x + 12*ui, w - 20*ui
        local col      = #active_takes == 0 and theme.text_dim or theme.text
        local loop     = tw + 40*ui
        local off      = 0
        if tw > room then
            local speed, pause = 40*ui, 1.5
            off = math.max(0, (reaper.time_precise() % (pause + loop / speed)) - pause) * speed
        end
        ImGui.DrawList_PushClipRect(dl, tx, y, tx + room, y + h, true)
        ImGui.DrawList_AddText(dl, tx - off, y + 4*ui, col, src_txt)
        if tw > room then ImGui.DrawList_AddText(dl, tx - off + loop, y + 4*ui, col, src_txt) end
        ImGui.DrawList_PopClipRect(dl)
        ImGui.PopFont(ctx)
        ImGui.Dummy(ctx, w, h)
    end

    ImGui.Dummy(ctx, 0, 4*ui)

    -- Two columns: controls | buttons + curve
    local col_w   = 320 * ui
    local enabled = stats.has

    ImGui.BeginGroup(ctx)
    local stats_top, stats_bot, top_y, bot_y = draw_controls(dl, ui, col_w)
    ImGui.EndGroup(ctx)
    -- Window height follows the content, leaving the same gap at the bottom
    local _, left_bot = ImGui.GetItemRectMax(ctx)
    local _, win_y    = ImGui.GetWindowPos(ctx)
    fit_h = left_bot - win_y + gap

    -- Right column: same gap to the window edge as to the left column
    ImGui.SameLine(ctx, 0, gap)
    ImGui.BeginGroup(ctx)
    local rx = ImGui.GetCursorScreenPos(ctx)
    local rw = ImGui.GetContentRegionAvail(ctx) - inset
    local btn_h = font_sizes.stat * 1.35 + 12*ui   -- centred on Note count .. Min — Max
    ImGui.SetCursorScreenPos(ctx, rx, stats_top + (stats_bot - stats_top - btn_h) / 2)
    if not enabled then ImGui.BeginDisabled(ctx) end
    draw_buttons(dl, ui, rw, btn_h)
    if not enabled then ImGui.EndDisabled(ctx) end
    -- Ruler on top, graph below it: together they span Threshold top .. Humanize bottom
    local rh = ruler_height()
    draw_ruler(dl, ui, rx, top_y, rw, rh, enabled and threshold or nil)
    ImGui.SetCursorScreenPos(ctx, rx, top_y + rh)
    local graph_h = math.max(60*ui, bot_y - top_y - rh)
    if enabled then
        draw_graph(dl, ui, rw, graph_h)
    else
        local msg
        if #active_takes > 0 then msg = "No notes in this take"
        elseif reaper.CountSelectedMediaItems(0) > 0 then msg = "Selected item isn't MIDI"
        else msg = "Select a MIDI item\nor open the MIDI editor" end
        draw_empty_graph(dl, ui, rw, graph_h, msg)
    end
    ImGui.EndGroup(ctx)

    -- Cmd/Ctrl+Z, Cmd/Ctrl+Shift+Z (ImGui's Mod_Ctrl is Cmd on macOS, Ctrl elsewhere)
    if not ImGui.IsAnyItemActive(ctx) and ImGui.IsKeyPressed(ctx, K(ImGui.Key_Z), false) then
        local mods = ImGui.GetKeyMods(ctx)
        if (mods & K(ImGui.Mod_Ctrl)) ~= 0 then
            if (mods & K(ImGui.Mod_Shift)) ~= 0 then redo() else undo() end
        end
    end

    -- Apply processing if anything changed
    if enabled and (dirty or need_reapply) then
        if need_reapply
        or above_val    ~= last_applied.above
        or below_val    ~= last_applied.below
        or humanize_val ~= last_applied.humanize
        or gain_val     ~= last_applied.gain
        or above_curve  ~= last_applied.ac
        or below_curve  ~= last_applied.bc
        or threshold    ~= last_applied.thr then
            apply_all(bypass)
            last_applied.above    = above_val
            last_applied.below    = below_val
            last_applied.humanize = humanize_val
            last_applied.gain     = gain_val
            last_applied.ac       = above_curve
            last_applied.bc       = below_curve
            last_applied.thr      = threshold
        end
        dirty = false
        need_reapply = false
    end
    track_history()

    -- Undo point once the GUI is let go: nothing held and 0.5 s since the last write
    if has_written and not ImGui.IsAnyItemActive(ctx) and reaper.time_precise() - last_write >= 0.5 then
        reaper.Undo_OnStateChange2(0, UNDO_NAME)
        has_written = false
    end

    ImGui.PopFont(ctx)
end

-------------------------------------------------------------------------------
-- Main loop
-------------------------------------------------------------------------------
local STYLE_VARS = { -- { var, value × ui }
    { "StyleVar_FrameRounding", 4 }, { "StyleVar_GrabRounding", 3 }, { "StyleVar_GrabMinSize", 10 },
    { "StyleVar_WindowRounding", 8 }, { "StyleVar_PopupRounding", 6 },
}

local function main()
    push_theme()
    for _, sv in ipairs(STYLE_VARS) do
        ImGui.PushStyleVar(ctx, K(ImGui[sv[1]]), sv[2] * settings.ui_scale)
    end
    ImGui.SetNextWindowSize(ctx, 860 * settings.ui_scale, 540 * settings.ui_scale,
        K(ImGui.Cond_FirstUseEver))
    -- Width is free; height is locked to what the content needs (fit_h)
    ImGui.SetNextWindowSizeConstraints(ctx, 700 * settings.ui_scale, fit_h or 300 * settings.ui_scale,
        10000, fit_h or 10000)
    -- NoNavInputs: Tab / Shift+Tab don't move focus between widgets
    local win_flags = K(ImGui.WindowFlags_NoCollapse) | K(ImGui.WindowFlags_NoNavInputs)
                    | (settings.pinned and K(ImGui.WindowFlags_TopMost) or 0)
    -- "###" keeps the window ID stable (version info is drawn into the title bar)
    local visible, open = ImGui.Begin(ctx, SCRIPT_NAME .. "###lyx_midicmp_main", true, win_flags)
    if visible then
        -- Steal keyboard from REAPER so global shortcuts (Esc, Space, etc.)
        -- reach our window instead of triggering REAPER actions.
        ImGui.SetNextFrameWantCaptureKeyboard(ctx, true)
        draw_main()
        if SPACE_CMD and ImGui.IsKeyPressed(ctx, K(ImGui.Key_Space), false)
        and ImGui.GetKeyMods(ctx) == 0 and not ImGui.IsAnyItemActive(ctx) then
            reaper.Main_OnCommand(SPACE_CMD, 0)        -- e.g. play / stop while this window has focus
        end
        if ImGui.IsKeyPressed(ctx, K(ImGui.Key_Escape), false) then
            open = false
        end
        ImGui.End(ctx)
    end

    -- Settings window
    if show_settings then
        ImGui.SetNextWindowSize(ctx, 380 * settings.ui_scale, 500 * settings.ui_scale,
            K(ImGui.Cond_FirstUseEver))
        local svis, sopen = ImGui.Begin(ctx, "Settings##lyx_midicmp", true, win_flags)
        if svis then
            draw_settings()
            ImGui.End(ctx)
        end
        if not sopen then show_settings = false end
    end

    ImGui.PopStyleVar(ctx, #STYLE_VARS)
    pop_theme()

    if open then
        reaper.defer(main)
    end
end

reaper.defer(main)
