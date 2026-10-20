-- @description Lyx MIDI Note Quantize Filter
-- @version 1.1.0
-- @author Lyx
-- @changelog
--   1.1.0  Early / Late window (separate sizes), drag the window in the
--          timing view, live-preview throttle for very large selections,
--          fewer API calls per preview, indicator fixes (time timebase,
--          macOS alpha, take-chunk parsing verified against js_Multi Tool)
--   1.0.0  First release
-- @about
--   Quantize the selected MIDI notes with a tolerance window ("filter"):
--   notes that are already close enough to the grid keep their natural
--   timing, the rest are pulled by Strength -- optionally weighted by their
--   distance, optionally only as far as the edge of the window. The window
--   can be larger on one side (keep a laid-back feel, fix rushing).
--   Note Position / Note Length modes, live preview, Bypass (A/B),
--   Apply (iterative passes), Reset, folded timing view (drag to set the
--   window), optional window overlay inside the MIDI editor (needs
--   js_ReaScriptAPI), HiDPI, theming. Requires ReaImGui.

local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
script_path = script_path:gsub("[/\\]MIDI Editor[/\\]$", "/")   -- _Lyx_HOME lives one folder up
package.path = package.path..";"..script_path.."?.lua"
local ok_home, r_home = pcall(require, "_lib._Lyx_HOME")

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

local ImGui = {}
for key, func in pairs(reaper) do
    local name = key:match('^ImGui_(.+)$')
    if name then ImGui[name] = func end
end

-- Resolve constants that may be functions (newer ReaImGui) or numbers (older).
local function K(v)
    if type(v) == "function" then return v() end
    return v
end

local SCRIPT_NAME = "Lyx MIDI Note Quantize Filter"
local VERSION     = "1.1.0"
local EXT_SECTION = "Lyx_MIDI_QuantizeFilter"
local UNDO_LABEL  = "Lyx: MIDI quantize filter"

local _, _, REAIMGUI_VERSION = ImGui.GetVersion()
local function reaimgui_at_least(a, b)
    local x, y = tostring(REAIMGUI_VERSION or ""):match("^(%d+)%.(%d+)")
    x, y = tonumber(x) or 0, tonumber(y) or 0
    return x > a or (x == a and y >= b)
end
-- 0.10+: CreateFont(family, flags) + PushFont(ctx, font, size)
-- older: CreateFont(family, size, flags) + PushFont(ctx, font)
local FONT_API_010 = reaimgui_at_least(0, 10)

local HAS_JS = (reaper.JS_Composite and reaper.JS_Composite_Unlink
    and reaper.JS_LICE_CreateBitmap and reaper.JS_LICE_FillRect
    and reaper.JS_Window_FindChildByID and reaper.JS_Window_GetClientSize
    and reaper.JS_Window_IsWindow and reaper.JS_Window_InvalidateRect) and true or false
local IS_WIN = (reaper.GetOS() or ""):match("Win") ~= nil

local floor, ceil, abs, min, max = math.floor, math.ceil, math.abs, math.min, math.max
local EPS = 1e-9

local function toint(x) return floor(x + 0.5) end
local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

-------------------------------------------------------------------------------
-- Toggle command state (toolbar highlight)
-------------------------------------------------------------------------------
local _, _, section_id, cmd_id = reaper.get_action_context()
reaper.SetToggleCommandState(section_id, cmd_id, 1)
reaper.RefreshToolbar2(section_id, cmd_id)

-------------------------------------------------------------------------------
-- Theme (10 colours, packed 0xRRGGBBAA)
-------------------------------------------------------------------------------
local function rgba(r, g, b, a)
    r = math.floor(math.max(0, math.min(255, r)))
    g = math.floor(math.max(0, math.min(255, g)))
    b = math.floor(math.max(0, math.min(255, b)))
    a = math.floor(math.max(0, math.min(255, a or 255)))
    return (r<<24)|(g<<16)|(b<<8)|a
end

local function with_alpha(c, a)
    return (c & 0xFFFFFF00) | clamp(toint(a), 0, 255)
end

local function lighten(c, f)
    local r, g, b, a = (c>>24)&0xFF, (c>>16)&0xFF, (c>>8)&0xFF, c&0xFF
    return rgba(r + (255-r)*f, g + (255-g)*f, b + (255-b)*f, a)
end

local DEFAULT_THEME = {
    bg        = rgba( 30,  30,  38, 255),
    panel     = rgba( 42,  42,  54, 255),
    text      = rgba(225, 225, 230, 255),
    text_dim  = rgba(160, 160, 170, 255),
    accent    = rgba(100, 200, 140, 255),
    slider    = rgba( 70, 130, 200, 255),
    slider_act= rgba(110, 170, 240, 255),
    border    = rgba( 70,  70,  80, 255),
    stat_val  = rgba(140, 220, 170, 255),
    band      = rgba(240, 180,  80, 255),   -- filter window (timing view + MIDI editor)
}
local THEME_ROWS = {
    { "Background",      "bg"        }, { "Panel",           "panel"     },
    { "Text",            "text"      }, { "Text (dim)",      "text_dim"  },
    { "Accent",          "accent"    }, { "Slider",          "slider"    },
    { "Slider (active)", "slider_act"}, { "Border",          "border"    },
    { "Stat value",      "stat_val"  }, { "Filter window",   "band"      },
}

-- own = this script's saved colours (Settings); theme = colours in use.
-- With the Lyx global theme inherited, the shared roles come from it;
-- stat_val and band (filter window) always stay the script's own.
local own, theme = {}, {}
for k, v in pairs(DEFAULT_THEME) do own[k] = v end
local THEME_KEY = "QuantizeFilter"
local G                                    -- _Lyx_GUI, loaded with the ImGui context
local OWN_ONLY = { stat_val = true, band = true }

local function sync_theme()
    for k, v in pairs(own) do theme[k] = v end
    theme.button, theme.title, theme.subtitle = own.panel, own.accent, own.text
    if G and G.inherited then
        local c, col = G.theme.colors, G.col
        theme.bg, theme.panel, theme.text = col(c.bg), col(c.bg2), col(c.text)
        theme.text_dim, theme.accent = col(G.dim), col(c.accent)
        theme.border   = col(G.mix(c.bg, c.base, 0.65))
        theme.button   = col(G.theme.button.color)
        theme.title, theme.subtitle = col(c.title), col(c.subtitle)
    end
end
sync_theme()

local DEFAULTS = { mode = 0, strength = 100, threshold = 0, threshold_late = 0,
                   link = true, weighted = false, edge = false }

local settings = {
    ui_scale  = 1.0,
    mode      = DEFAULTS.mode,        -- 0 = Note Position, 1 = Note Length
    strength  = DEFAULTS.strength,    -- 0..100 %
    threshold = DEFAULTS.threshold,   -- 0..100 % of half a grid step (early side / both)
    threshold_late = DEFAULTS.threshold_late, -- late side when not linked
    link      = DEFAULTS.link,        -- one symmetric window
    weighted  = DEFAULTS.weighted,    -- pull grows with distance
    edge      = DEFAULTS.edge,        -- pull to the window edge instead of the grid
    indicator = false,                -- overlay in the MIDI editor
}

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
    for k in pairs(own) do
        own[k] = toint(getN("theme_"..k, DEFAULT_THEME[k]))
    end
    sync_theme()
    settings.ui_scale  = clamp(getN("ui_scale", 1.0), 0.75, 2.5)
    settings.mode      = (getN("quantize_mode", 0) == 1) and 1 or 0
    settings.strength  = clamp(toint(getN("quantize_strength", DEFAULTS.strength)), 0, 100)
    settings.threshold = clamp(toint(getN("quantize_threshold", DEFAULTS.threshold)), 0, 100)
    settings.threshold_late = clamp(toint(getN("quantize_threshold_late", DEFAULTS.threshold_late)), 0, 100)
    settings.link      = getB("quantize_link", DEFAULTS.link)
    settings.weighted  = getB("quantize_weighted", DEFAULTS.weighted)
    settings.edge      = getB("quantize_edge", DEFAULTS.edge)
    settings.indicator = getB("quantize_indicator", false) and HAS_JS
end

local function save_settings()
    for k, v in pairs(own) do
        reaper.SetExtState(EXT_SECTION, "theme_"..k, tostring(v), true)
    end
    local function b(v) return v and "1" or "0" end
    reaper.SetExtState(EXT_SECTION, "ui_scale",           tostring(settings.ui_scale), true)
    reaper.SetExtState(EXT_SECTION, "quantize_mode",      tostring(settings.mode), true)
    reaper.SetExtState(EXT_SECTION, "quantize_strength",  tostring(settings.strength), true)
    reaper.SetExtState(EXT_SECTION, "quantize_threshold", tostring(settings.threshold), true)
    reaper.SetExtState(EXT_SECTION, "quantize_threshold_late", tostring(settings.threshold_late), true)
    reaper.SetExtState(EXT_SECTION, "quantize_link",      b(settings.link), true)
    reaper.SetExtState(EXT_SECTION, "quantize_weighted",  b(settings.weighted), true)
    reaper.SetExtState(EXT_SECTION, "quantize_edge",      b(settings.edge), true)
    reaper.SetExtState(EXT_SECTION, "quantize_indicator", b(settings.indicator), true)
end

load_settings()

-- window in % of half a grid step: early side, late side
local function window_pct()
    local e = settings.threshold
    if settings.link then return e, e end
    return e, settings.threshold_late
end

-------------------------------------------------------------------------------
-- Runtime state
-------------------------------------------------------------------------------
-- Opening the script never touches the MIDI: it starts idle (= bypassed and
-- not armed). The first control you touch arms it and starts the preview.
-- Once armed, Bypass is a plain A/B switch and moving controls keeps it.
local S = {
    sessions       = {},    -- [take] = session (see snapshot_take)
    takes          = {},    -- ordered list of takes in scope
    editor         = nil,   -- MIDI editor in use (nil = selected items)
    last_editor    = nil,
    bypassed       = true,
    armed          = false,
    dirty          = false, -- parameters changed -> re-apply from the originals
    analysis_dirty = true,
    uncommitted    = false, -- MIDI written since the last undo point
    commit_desc    = nil,   -- queued undo point ...
    commit_after   = 0,     -- ... not before this time (debounces the mouse wheel)
    show_settings  = false,
    status         = "",
    status_until   = 0,
    last_poll      = -1,
    poll_n         = 0,
    next_apply_at  = 0,     -- live preview throttle for very large selections
    drag_side      = nil,   -- timing-view drag: -1 early, 1 late, 0 both
    plot           = { pts = {}, total = 0, moved = 0, max_ticks = 0, max_ms = 0 },
    snap_n         = 0,     -- bumped on every new baseline (indicator cache key)
    undo_proj      = nil,   -- project the uncommitted MIDI was written in
}

local function status(msg, secs)
    S.status       = msg
    S.status_until = reaper.time_precise() + (secs or 4)
end

local function add_undo(desc)
    -- the undo point belongs to the project the MIDI was written in, even if
    -- another project tab is active by now
    local proj = S.undo_proj
    if not (proj and reaper.ValidatePtr(proj, "ReaProject*")) then proj = 0 end
    if reaper.Undo_OnStateChange2 then
        reaper.Undo_OnStateChange2(proj, desc)
    else
        reaper.Undo_OnStateChange(desc)
    end
end

-------------------------------------------------------------------------------
-- Grid engine -- positions in project quarter notes (QN)
--
-- Lines restart at every bar (odd meters, time-signature changes, partial
-- bars) and every second line is displaced by the grid swing, the way the
-- MIDI editor draws them.
-------------------------------------------------------------------------------
local GRID = { g = 0, s = 0, cache = {} }

local function grid_use(g, swing)
    local s = (swing or 0) * g * 0.5
    if g ~= GRID.g or s ~= GRID.s then
        GRID.g, GRID.s, GRID.cache = g, s, {}
    end
end

local function grid_flush() GRID.cache = {} end   -- tempo map may have changed

local function measure_bounds(q)
    local _, ms, me = reaper.TimeMap_QNToMeasures(0, q)
    if ms and me and me - ms > EPS then return ms, me end
    local span = GRID.g * 4096                     -- fallback: plain grid
    ms = floor(q / span) * span
    return ms, ms + span
end

local function lines_of(ms, me)
    local key = floor(ms * 1e6 + 0.5)
    local L = GRID.cache[key]
    if L then return L end
    local g, s = GRID.g, GRID.s
    L = { me = me }
    local n = min(8192, ceil((me - ms) / g - 1e-9))
    for j = 0, n - 1 do
        local p = ms + j * g
        if j % 2 == 1 then p = p + s end
        if p < me - EPS then L[#L + 1] = p end
    end
    if #L == 0 then L[1] = ms end
    GRID.cache[key] = L
    return L
end

-- a = last grid line <= q, b = first grid line > q
local function around(q, depth)
    local ms, me = measure_bounds(q)
    local L = lines_of(ms, me)
    depth = depth or 0
    if q + EPS < L[1] and depth < 3 then
        return (around(L[1] - 1e-7, depth + 1)), L[1]
    end
    local n = #L
    local j = floor((q - ms) / GRID.g) + 1
    if j < 1 then j = 1 elseif j > n then j = n end
    while j > 1 and L[j] > q + EPS do j = j - 1 end
    while j < n and L[j + 1] <= q + EPS do j = j + 1 end
    return L[j], (L[j + 1] or me)
end

local function nearest(q)
    local a, b = around(q)
    if b - q < q - a then return b end
    return a
end

local function next_line(x)
    local _, b = around(x)
    if b <= x + EPS then _, b = around(x + 1e-7) end
    return b
end

local function prev_line(x)
    return (around(x - 1e-7))
end

-------------------------------------------------------------------------------
-- Quantize maths
-------------------------------------------------------------------------------
-- P = { mode, g, str (0..1), thr_e / thr_l (QN), weighted, edge }
local function make_params(g)
    local e, l = window_pct()
    return {
        mode = settings.mode, g = g,
        str  = settings.strength * 0.01,
        thr_e = e * 0.01 * g * 0.5,
        thr_l = l * 0.01 * g * 0.5,
        weighted = settings.weighted, edge = settings.edge,
    }
end

-- window size on the side of a signed offset (negative = early)
local function side_thr(off, P)
    if off < 0 then return P.thr_e end
    return P.thr_l
end

-- Signed offset from a grid line -> new signed offset.
--   inside the window (early side / late side may differ): untouched
--   weighted: pull = str * dist/grid. A note half a grid off gets half of
--             Strength, closer notes proportionally less. This is the
--             strongest distance weighting that never swaps the order of two
--             deviations, so strums and flams keep their shape.
--   edge:     only the part beyond the window is pulled: at 100 % every
--             outlier lands exactly on the window edge. Continuous and
--             order-preserving, like a compressor acting above threshold.
local function pull(off, P)
    local d = abs(off)
    local thr = side_thr(off, P)
    if d <= thr or d < EPS then return off end
    local p = P.str
    if P.weighted then p = p * min(1, d / P.g) end
    local nd
    if P.edge then nd = thr + (d - thr) * (1 - p)
    else           nd = d * (1 - p) end
    if off < 0 then return -nd end
    return nd
end

-- New (start, end) in QN. Requires grid_use() for the take's grid.
local function plan_note(qs, qe, P)
    if P.mode == 0 then                          -- Note Position
        local X = nearest(qs)
        local off = qs - X
        local noff = pull(off, P)
        if noff == off then return qs, qe end
        local d = X + noff - qs
        return qs + d, qe + d
    end
    -- Note Length: every boundary goes to its own nearest line ...
    local Xs, Xe = nearest(qs), nearest(qe)
    local ts, te = Xs, Xe
    if abs(Xs - Xe) < EPS then
        -- ... unless both would collapse onto the same line (the note
        -- straddles one line, or sits between two). The boundary closer to
        -- that line is the anchor; the other one goes one line further out.
        local ds, de = abs(qs - Xs), abs(qe - Xe)
        if ds <= de then
            if de <= side_thr(qe - Xe, P) or de < EPS then return qs, qe end
            te = next_line(Xe)
        else
            if ds <= side_thr(qs - Xs, P) then return qs, qe end
            ts = prev_line(Xs)
        end
    end
    local nqs = ts + pull(qs - ts, P)
    local nqe = te + pull(qe - te, P)
    if nqe - nqs < EPS then return qs, qe end
    return nqs, nqe
end

-------------------------------------------------------------------------------
-- Takes in scope: the MIDI editor's editable takes, else selected items
-------------------------------------------------------------------------------
local function is_valid_take(t)
    return t and reaper.ValidatePtr2(0, t, "MediaItem_Take*") and reaper.TakeIsMIDI(t)
end

local function editor_valid(me)
    if not me then return false end
    local ok, mode = pcall(reaper.MIDIEditor_GetMode, me)
    return ok and mode ~= nil and mode >= 0
end

local function collect_takes()
    -- Keep the last editor: GetActive() may not report it while our own
    -- window has focus, and the take set must not flap.
    local me = reaper.MIDIEditor_GetActive()
    if editor_valid(me) then S.last_editor = me end
    if S.last_editor and not editor_valid(S.last_editor) then S.last_editor = nil end
    S.editor = S.last_editor

    local takes, seen = {}, {}
    if S.editor then
        if reaper.MIDIEditor_EnumTakes then
            for i = 0, 255 do
                local t = reaper.MIDIEditor_EnumTakes(S.editor, i, true)
                if not t then break end
                if is_valid_take(t) and not seen[t] then
                    takes[#takes + 1] = t; seen[t] = true
                end
            end
        end
        if #takes == 0 then
            local t = reaper.MIDIEditor_GetTake(S.editor)
            if is_valid_take(t) then takes[1] = t end
        end
        if #takes > 0 then return takes end
        S.editor = nil
    end
    for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
        local t = reaper.GetActiveTake(reaper.GetSelectedMediaItem(0, i))
        if is_valid_take(t) and not seen[t] then
            takes[#takes + 1] = t; seen[t] = true
        end
    end
    return takes
end

-------------------------------------------------------------------------------
-- Sessions: snapshot of the SELECTED notes = the originals everything is
-- computed from. Each tracked note keeps its current index; after a write +
-- MIDI_Sort the indices are re-established by matching the written state,
-- so every note keeps its own identity (release velocity etc. included).
-------------------------------------------------------------------------------
local function take_hash(take)
    local _, h = reaper.MIDI_GetHash(take, true, "")
    return h or ""
end

local function sel_sig(take)
    local c, s = 0, 0
    local i = reaper.MIDI_EnumSelNotes(take, -1)
    while i >= 0 do
        c = c + 1
        s = s + (toint(i) + 1) * 2654435761
        i = reaper.MIDI_EnumSelNotes(take, i)
    end
    return c..":"..s
end

local function note_key(s, e, chan, pitch, vel)
    return s..":"..e..":"..chan..":"..pitch..":"..vel
end

local function snapshot_take(take)
    local notes = {}
    local i = reaper.MIDI_EnumSelNotes(take, -1)
    while i >= 0 do
        local ok, _, _, s, e, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
        if ok then
            s, e = toint(s), toint(e)
            notes[#notes + 1] = {
                idx = toint(i), os = s, oe = e, cs = s, ce = e,
                chan = toint(chan), pitch = toint(pitch), vel = toint(vel),
                qs = reaper.MIDI_GetProjQNFromPPQPos(take, s),
                qe = reaper.MIDI_GetProjQNFromPPQPos(take, e),
            }
        end
        i = reaper.MIDI_EnumSelNotes(take, i)
    end
    local ppq_qn = reaper.MIDI_GetPPQPosFromProjQN(take, 1) - reaper.MIDI_GetPPQPosFromProjQN(take, 0)
    if not ppq_qn or ppq_qn <= 0 then ppq_qn = 960 end
    local g, sw = reaper.MIDI_GetGrid(take)
    local bpm = 120
    if #notes > 0 then
        bpm = reaper.TimeMap_GetDividedBpmAtTime(
            reaper.MIDI_GetProjTimeFromPPQPos(take, notes[1].os)) or 120
    end
    return {
        notes   = notes,
        ledger  = {},        -- unselected same-pitch neighbours we trimmed
        written = false,     -- the take currently differs from the originals
        g       = g or 0,
        swing   = sw or 0,
        ppq_qn  = ppq_qn,
        bpm     = bpm,
        hash    = take_hash(take),
        selsig  = sel_sig(take),
    }
end

local function total_notes()
    local n = 0
    for _, t in ipairs(S.takes) do
        local s = S.sessions[t]
        if s then n = n + #s.notes end
    end
    return n
end

local function any_written()
    for _, s in pairs(S.sessions) do
        if s.written then return true end
    end
    return false
end

-- Re-establish tracked note indices after MIDI_Sort.
-- Returns ok, selection signature (same format as sel_sig).
local function remap(take, notes)
    local pool = {}
    for _, nt in ipairs(notes) do
        local k = note_key(nt.cs, nt.ce, nt.chan, nt.pitch, nt.vel)
        local l = pool[k]
        if not l then l = {}; pool[k] = l end
        l[#l + 1] = nt
    end
    local matched, sig = 0, 0
    local i = reaper.MIDI_EnumSelNotes(take, -1)
    while i >= 0 do
        local _, _, _, s, e, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
        local l = pool[note_key(toint(s), toint(e), toint(chan), toint(pitch), toint(vel))]
        if not l or #l == 0 then return false end
        table.remove(l).idx = toint(i)
        matched = matched + 1
        sig = sig + (toint(i) + 1) * 2654435761
        i = reaper.MIDI_EnumSelNotes(take, i)
    end
    return matched == #notes, matched..":"..sig
end

-- Length mode, per channel+pitch. Same-pitch notes never change order:
--   1. a head moving earlier may not overtake the previous note's head
--      (the move is cancelled instead)
--   2. a tail that moved stops where the next note's head begins
--   3. a head that moved earlier eats the tail of the previous note -- also
--      of an unselected one (restored through the ledger on Bypass / Reset)
local function resolve_overlaps(notes, unt)
    local groups = {}
    local function add(key, ent)
        local l = groups[key]
        if not l then l = {}; groups[key] = l end
        l[#l + 1] = ent
    end
    for _, nt in ipairs(notes) do
        add(nt.chan * 128 + nt.pitch, { nt = nt, os = nt.os, oe = nt.oe, s = nt.ts, e = nt.te })
    end
    for _, u in ipairs(unt) do
        add(u.chan * 128 + u.pitch, { u = u, os = u.s, oe = u.e, s = u.s, e = u.e })
    end
    for _, l in pairs(groups) do
        if #l > 1 then
            table.sort(l, function(a, b)
                if a.os ~= b.os then return a.os < b.os end
                return a.oe < b.oe
            end)
            for _ = 1, 4 do                                -- 1. keep the order
                local moved = false
                for i = 2, #l do
                    local b = l[i]
                    local j = i - 1
                    while j >= 1 and l[j].os >= b.os do j = j - 1 end
                    local a = l[j]
                    if a and b.s <= a.s then
                        if b.nt and b.s ~= b.os then b.s = b.os; moved = true
                        elseif a.nt and a.s ~= a.os then a.s = a.os; moved = true end
                    end
                end
                if not moved then break end
            end
            table.sort(l, function(a, b)
                if a.s ~= b.s then return a.s < b.s end
                return a.e < b.e
            end)
            for i = 1, #l - 1 do                           -- 2. + 3.
                local a = l[i]
                local j = i + 1
                while j <= #l and l[j].s <= a.s do j = j + 1 end
                local b = l[j]
                if b and a.e > b.s then
                    local a_moved = a.nt and a.e ~= a.oe
                    local b_moved = b.nt and b.s ~= b.os
                    if a_moved or b_moved then a.e = b.s end
                end
            end
            for _, ent in ipairs(l) do
                if ent.e <= ent.s then ent.s, ent.e = ent.os, ent.oe end
                if ent.nt then ent.nt.ts, ent.nt.te = ent.s, ent.e
                else ent.u.e = ent.e end
            end
        end
    end
end

-- Compute every tracked note from its ORIGINAL and write what changed.
-- Returns ok (false = the take changed behind our back), wrote.
local function apply_take(take, sess, bypass)
    -- MIDI_GetHash also changes when only the selection changes (js_ scripts
    -- rely on this); the poll additionally compares the selection itself.
    if take_hash(take) ~= sess.hash then return false, false end
    local notes, n = sess.notes, #sess.notes
    local P = make_params(sess.g)
    local active = (not bypass) and sess.g > EPS and P.str > 0
    if active then grid_use(sess.g, sess.swing) end

    for k = 1, n do
        local nt = notes[k]
        local ts, te = nt.os, nt.oe
        if active then
            local nqs, nqe = plan_note(nt.qs, nt.qe, P)
            if P.mode == 0 then
                if nqs ~= nt.qs then
                    ts = toint(reaper.MIDI_GetPPQPosFromProjQN(take, nqs))
                    te = nt.oe + (ts - nt.os)
                end
            else
                if nqs ~= nt.qs then ts = toint(reaper.MIDI_GetPPQPosFromProjQN(take, nqs)) end
                if nqe ~= nt.qe then te = toint(reaper.MIDI_GetPPQPosFromProjQN(take, nqe)) end
                if te <= ts then ts, te = nt.os, nt.oe end
            end
        end
        nt.ts, nt.te = ts, te
    end

    -- untracked notes: needed for Length-mode overlaps and to undo trims
    local unt
    if (active and P.mode == 1) or next(sess.ledger) then
        unt = {}
        local tracked = {}
        for k = 1, n do tracked[notes[k].idx] = true end
        local _, cnt = reaper.MIDI_CountEvts(take)
        for i = 0, cnt - 1 do
            if not tracked[i] then
                local ok, _, _, s, e, chan, pitch = reaper.MIDI_GetNote(take, i)
                if ok then
                    s, e, chan, pitch = toint(s), toint(e), toint(chan), toint(pitch)
                    local lk = chan..":"..pitch..":"..s
                    local ent = sess.ledger[lk]
                    local e0 = (ent and ent.cur == e) and ent.orig or e
                    unt[#unt + 1] = { idx = i, s = s, e = e0, pe = e, e0 = e0,
                                      chan = chan, pitch = pitch, lk = lk }
                end
            end
        end
        if active and P.mode == 1 then resolve_overlaps(notes, unt) end
    end

    local wrote = false
    for k = 1, n do
        local nt = notes[k]
        if nt.ts ~= nt.cs or nt.te ~= nt.ce then
            reaper.MIDI_SetNote(take, nt.idx, nil, nil, nt.ts, nt.te, nil, nil, nil, true)
            nt.cs, nt.ce = nt.ts, nt.te
            wrote = true
        end
    end
    if unt then
        local ledger = {}
        for _, u in ipairs(unt) do
            if u.e ~= u.pe then
                reaper.MIDI_SetNote(take, u.idx, nil, nil, nil, u.e, nil, nil, nil, true)
                wrote = true
            end
            if u.e ~= u.e0 then ledger[u.lk] = { orig = u.e0, cur = u.e } end
        end
        sess.ledger = ledger
    end

    local ok = true
    if wrote then
        reaper.MIDI_Sort(take)
        local sig
        ok, sig = remap(take, notes)
        if ok then sess.selsig = sig end
    end
    local diff = next(sess.ledger) ~= nil
    if not diff then
        for k = 1, n do
            local nt = notes[k]
            if nt.cs ~= nt.os or nt.ce ~= nt.oe then diff = true; break end
        end
    end
    sess.written = diff
    sess.hash = take_hash(take)
    return ok, wrote
end

-- Current MIDI becomes the new baseline for every take in scope.
local function rebaseline(msg)
    if S.uncommitted then add_undo(UNDO_LABEL); S.uncommitted = false end
    for _, t in ipairs(S.takes) do S.sessions[t] = snapshot_take(t) end
    S.snap_n = S.snap_n + 1          -- indicator redraws around the new notes
    S.bypassed, S.armed = true, false
    S.analysis_dirty = true
    if msg then status(msg, 5) end
end

local function apply_all()
    grid_flush()
    local lost = false
    for _, take in ipairs(S.takes) do
        local sess = S.sessions[take]
        if sess and (not S.bypassed or sess.written) then
            local ok, wrote = apply_take(take, sess, S.bypassed)
            if wrote then S.uncommitted = true; S.undo_proj = reaper.EnumProjects(-1) end
            if not ok then lost = true end
        end
    end
    if lost then rebaseline("MIDI changed outside the script: new baseline") end
end

local function engine_error(err)
    S.bypassed = true
    status("Error: see the REAPER console", 8)
    reaper.ShowConsoleMsg("["..SCRIPT_NAME.."] "..tostring(err).."\n")
end

local function run_apply()
    reaper.PreventUIRefresh(1)
    local ok, err = pcall(apply_all)
    reaper.PreventUIRefresh(-1)
    if not ok then engine_error(err) end
end

local function commit(desc)
    if S.uncommitted then add_undo(desc or UNDO_LABEL) end
    S.uncommitted  = false
    S.commit_desc  = nil
    S.commit_after = 0
    save_settings()
end

local function request_commit(desc, delay)
    S.commit_desc  = desc
    S.commit_after = reaper.time_precise() + (delay or 0)
end

local function window_desc()
    local e, l = window_pct()
    if e == l then return string.format("±%d%%", e) end
    return string.format("-%d/+%d%%", e, l)
end

local function param_desc()
    return string.format("%s (%s, %d%%, window %s%s%s)", UNDO_LABEL,
        settings.mode == 0 and "position" or "length",
        settings.strength, window_desc(),
        settings.weighted and ", weighted" or "",
        settings.edge and ", to edge" or "")
end

-------------------------------------------------------------------------------
-- Polling: take set, selection, external edits, grid changes
-------------------------------------------------------------------------------
local function poll(force)
    local now = reaper.time_precise()
    if not force and (now - S.last_poll) < 0.15 then return end
    S.last_poll = now

    local takes = collect_takes()
    local keep = {}
    for _, t in ipairs(takes) do keep[t] = true end
    local changed = (#takes ~= #S.takes)
    if not changed then
        for i = 1, #takes do
            if takes[i] ~= S.takes[i] then changed = true; break end
        end
    end
    for t in pairs(S.sessions) do
        if not keep[t] then S.sessions[t] = nil end
    end
    S.takes = takes

    S.poll_n = S.poll_n + 1
    local check_sel = force or S.poll_n % 3 == 0
    local external, grid_changed = false, false
    for _, t in ipairs(takes) do
        local sess = S.sessions[t]
        if not sess then
            changed = true
        elseif take_hash(t) ~= sess.hash or (check_sel and sel_sig(t) ~= sess.selsig) then
            external = true
        else
            local g, sw = reaper.MIDI_GetGrid(t)
            g, sw = g or 0, sw or 0
            if abs(g - sess.g) > EPS or abs(sw - sess.swing) > EPS then
                sess.g, sess.swing = g, sw
                grid_changed = true
            end
        end
    end

    if changed or external then
        local was_live = (not S.bypassed) or any_written()
        rebaseline(was_live and "Selection or MIDI changed: result kept, preview reset" or nil)
    elseif grid_changed then
        S.analysis_dirty = true
        if not S.bypassed then
            S.dirty = true
            request_commit(param_desc(), 0.5)
        end
    end
end

-------------------------------------------------------------------------------
-- Actions
-------------------------------------------------------------------------------
local function on_param_change()
    S.analysis_dirty = true
    if total_notes() == 0 then return end
    if S.bypassed and not S.armed then S.bypassed = false end
    S.armed = true
    S.dirty = true
end

local function toggle_bypass()
    if total_notes() == 0 then return end
    S.bypassed = not S.bypassed
    S.armed = true
    S.dirty = true
end

-- accept the preview; it becomes the baseline for a further pass
local function do_apply()
    if S.bypassed or total_notes() == 0 then return end
    if S.dirty then S.dirty = false; run_apply() end
    commit(param_desc().." (apply)")
    rebaseline()
    status("Applied: the result is the new baseline", 4)
end

-- restore the originals and the default parameters
local function do_reset()
    settings.strength  = DEFAULTS.strength
    settings.threshold = DEFAULTS.threshold
    settings.threshold_late = DEFAULTS.threshold_late
    settings.link      = DEFAULTS.link
    settings.weighted  = DEFAULTS.weighted
    settings.edge      = DEFAULTS.edge
    S.bypassed, S.armed = true, false
    S.dirty = false
    run_apply()
    commit(UNDO_LABEL.." (reset)")
    S.analysis_dirty = true
    status("Original notes restored", 3)
end

-------------------------------------------------------------------------------
-- Analysis: what the current settings WOULD do (independent of Bypass)
-------------------------------------------------------------------------------
local MAX_PLOT_PTS = 700

local function analyze()
    S.analysis_dirty = false
    grid_flush()
    local A = { pts = {}, total = 0, moved = 0, max_ticks = 0, max_ms = 0 }
    S.plot = A
    local total = total_notes()
    A.total = total
    if total == 0 then return end
    local per = (settings.mode == 1) and 2 or 1
    local stride = max(1, ceil(total * per / MAX_PLOT_PTS))
    local idx = 0
    for _, take in ipairs(S.takes) do
        local sess = S.sessions[take]
        if sess and sess.g > EPS then
            local g = sess.g
            grid_use(g, sess.swing)
            local P = make_params(g)
            for _, nt in ipairs(sess.notes) do
                local nqs, nqe = nt.qs, nt.qe
                if P.str > 0 then nqs, nqe = plan_note(nt.qs, nt.qe, P) end
                local mv = max(abs(nqs - nt.qs), abs(nqe - nt.qe))
                local ticks = mv * sess.ppq_qn
                if ticks >= 0.5 then
                    A.moved = A.moved + 1
                    if ticks > A.max_ticks then
                        A.max_ticks = ticks
                        A.max_ms = mv * 60000 / max(sess.bpm, 1)
                    end
                end
                idx = idx + 1
                if idx % stride == 0 then
                    local function pt(q0, q1, tail)
                        local X0, X1 = nearest(q0), nearest(q1)
                        A.pts[#A.pts + 1] = {
                            o = (q0 - X0) / g, n = (q1 - X1) / g, tail = tail,
                            moved = abs(q1 - q0) * sess.ppq_qn >= 0.5,
                            cross = abs(X1 - X0) > EPS,
                        }
                    end
                    pt(nt.qs, nqs, false)
                    if P.mode == 1 then pt(nt.qe, nqe, true) end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
-- MIDI editor overlay (js_ReaScriptAPI): the filter window drawn around the
-- grid line of every selected note, only on that note's row, composited into
-- the piano roll itself.
-------------------------------------------------------------------------------
local IND = { hwnd = nil, bmp = nil, w = 0, h = 0, key = "",
              view = nil, view_t = -1, view_dt = 0.1, view_take = nil }
-- Height of the ruler / marker area at the top of the piano roll (same value
-- js_Mouse editing uses). Calibration knob: if the boxes sit a constant
-- distance above/below the notes, adjust this.
local IND_RULER_H = 62
local IND_DEBUG = false  -- print the indicator's numbers to the console on every redraw
local IND_BLINK = 0.8    -- seconds per on+off cycle of the dashed exempt note edges (0 = steady)

-- Vertical fine-tune in pixels (Settings > Indicator offset), stored per machine:
-- the ruler height differs between REAPER versions, themes and OS scaling, and no API
-- reports it (SWS's note-row-under-mouse uses its own fixed ruler, so it can't calibrate).
local IND_OFFSET_KEY = "ind_offset"
local ind_offset = toint(tonumber(reaper.GetExtState("Lyx_MIDI_QuantizeFilter", IND_OFFSET_KEY)) or 0)


-- theme RGBA -> LICE ARGB. Compositing expects premultiplied alpha on
-- Windows and straight alpha elsewhere (same convention as js_Multi Tool).
local function lice_color(c, a)
    local r, g, b = (c >> 24) & 0xFF, (c >> 16) & 0xFF, (c >> 8) & 0xFF
    if IS_WIN then r, g, b = toint(r * a), toint(g * a), toint(b * a) end
    return (toint(255 * a) << 24) | (r << 16) | (g << 8) | b
end

local function ind_detach()
    if IND.bmp then
        if IND.hwnd and reaper.JS_Window_IsWindow(IND.hwnd) then
            reaper.JS_Composite_Unlink(IND.hwnd, IND.bmp, true)
            reaper.JS_Window_InvalidateRect(IND.hwnd, 0, 0, IND.w, IND.h, false)
        end
        reaper.JS_LICE_DestroyBitmap(IND.bmp)
    end
    IND.hwnd, IND.bmp, IND.key = nil, nil, ""
end

-- Scroll / zoom of the piano roll, from the take's CFGEDITVIEW line
-- (same parsing as js_Mouse editing - Multi Tool): the first field is always
-- the leftmost tick; the zoom is pixels per tick in a beats timebase
-- (CFGEDIT field 19 = 0 or 4) and pixels per second otherwise.
local sect_cache = {}   -- take section bounds, reused while the chunk length is unchanged
local function read_view(take)
    local item = reaper.GetMediaItemTake_Item(take)
    local ok, chunk = reaper.GetItemStateChunk(item, "", false)
    if not ok or not chunk then return nil end
    local a, b
    local c = sect_cache
    if c.take == take and c.len == #chunk and (c.a == 1 or chunk:sub(c.a, c.a + 4) == "\nTAKE")
       and (not c.b or chunk:sub(c.b, c.b + 4) == "\nTAKE") then
        a, b = c.a, c.b   -- same length: skip searching for the take (scroll/zoom digits are still read below)
    else
        local tn = toint(reaper.GetMediaItemTakeInfo_Value(take, "IP_TAKENUMBER"))
        a = 1
        for _ = 1, tn do
            a = chunk:find("\nTAKE[^\n]-\nNAME", a + 1)
            if not a then return nil end
        end
        b = chunk:find("\nTAKE[^\n]-\nNAME", a + 1)
        c.take, c.len, c.a, c.b = take, #chunk, a, b
    end
    local sect = chunk:sub(a, b)
    -- fields 3/4: vertical scroll (rows from the top, 127 = top pitch 0) and
    -- pixels per note row
    local left, zoom, vs, rh = sect:match("\nCFGEDITVIEW (%S+) (%S+) (%S+) (%S+)")
    left, zoom, vs, rh = tonumber(left), tonumber(zoom), tonumber(vs), tonumber(rh)
    if not left or not zoom or zoom <= 0 or not vs or not rh or rh <= 0 then return nil end
    local tb = sect:match("\nCFGEDIT"..string.rep(" %S+", 18).." (%S+)")
    local lanes = 0   -- CC lanes below the notes (heights include their divider)
    for lh in sect:gmatch("\nVELLANE %S+ (%d+)") do lanes = lanes + tonumber(lh) end
    return { left = left, zoom = zoom, beats = (tb == nil or tb == "0" or tb == "4"),
             top = 127 - vs, rh = rh, lanes = lanes }
end

local function ind_update()
    local me = S.editor
    if not (HAS_JS and settings.indicator and me) or reaper.MIDIEditor_GetMode(me) ~= 0 then
        if IND.bmp then ind_detach() end
        return
    end
    local take = reaper.MIDIEditor_GetTake(me)
    if not is_valid_take(take) then ind_detach(); return end
    local mv = reaper.JS_Window_FindChildByID(me, 1001)
    if not mv then ind_detach(); return end
    local okc, w, h = reaper.JS_Window_GetClientSize(mv)
    if not okc or not w or w < 8 or h < 8 then return end

    local now = reaper.time_precise()
    if IND.view_take ~= take or now - IND.view_t > IND.view_dt then
        IND.view, IND.view_take = read_view(take), take
        -- the item chunk can be MBs: re-read every 0.1 s when it is cheap,
        -- backing off to 0.5 s for heavy items
        local t1 = reaper.time_precise()
        IND.view_t, IND.view_dt = t1, clamp((t1 - now) * 25, 0.1, 0.5)
    end
    local v = IND.view
    if not v then ind_detach(); return end
    local ruler = IND_RULER_H + ind_offset
    local blink_on = IND_BLINK <= 0 or (reaper.time_precise() % IND_BLINK) < IND_BLINK / 2

    local g, sw = reaper.MIDI_GetGrid(take)
    g, sw = g or 0, sw or 0
    local pe, pl = window_pct()
    local te, tl = pe * 0.01 * g * 0.5, pl * 0.01 * g * 0.5
    local key = string.format("%s|%d|%d|%.6f|%.9g|%s|%.9g|%.4f|%.9g|%.9g|%d|%.4f|%.4f|%d|%d|%d",
        tostring(take), w, h, v.left, v.zoom, v.beats and "b" or "t", g, sw, te, tl, theme.band,
        v.top, v.rh, v.lanes, settings.mode, S.snap_n) .. "|" .. ruler .. (blink_on and "|on" or "|off")
    if key == IND.key and IND.hwnd == mv then return end

    if IND.hwnd ~= mv or IND.w ~= w or IND.h ~= h or not IND.bmp then
        ind_detach()
        IND.bmp = reaper.JS_LICE_CreateBitmap(true, w, h)
        if not IND.bmp then return end
        IND.hwnd, IND.w, IND.h = mv, w, h
        reaper.JS_Composite(mv, 0, 0, w, h, IND.bmp, 0, 0, w, h, true)
    end
    IND.key = key
    local bmp = IND.bmp
    reaper.JS_LICE_Clear(bmp, 0)

    if g > EPS and (te > EPS or tl > EPS) then
        local x_of, ql, qr
        if v.beats then
            x_of = function(q) return (reaper.MIDI_GetPPQPosFromProjQN(take, q) - v.left) * v.zoom end
            ql = reaper.MIDI_GetProjQNFromPPQPos(take, v.left)
            qr = reaper.MIDI_GetProjQNFromPPQPos(take, v.left + w / v.zoom)
        else
            local t0 = reaper.MIDI_GetProjTimeFromPPQPos(take, v.left)
            x_of = function(q) return (reaper.TimeMap2_QNToTime(0, q) - t0) * v.zoom end
            ql = reaper.TimeMap2_timeToQN(0, t0)
            qr = reaper.TimeMap2_timeToQN(0, t0 + w / v.zoom)
        end
        grid_flush()
        grid_use(g, sw)
        -- Only around the selected notes: one box per note boundary and
        -- grid line, 1.2 note rows tall, centred on the note's row.
        -- No density limit: boxes follow the notes, not every grid line.
        -- Every selected note boundary gets a faint box = its filter window, 1.2 note rows
        -- tall around the note's row. Boundaries the window keeps out of Quantize (inside the
        -- window, off the grid) also get a blinking dashed line on the note edge itself.
        local fill = lice_color(theme.band, 0.12)
        local dash = lice_color(theme.band, 1)
        local ny0, ny1 = ruler, h - v.lanes              -- notes area
        local rh = v.rh
        local half = rh * 0.6
        local function dashed(x, y0, y1)
            if x < 0 or x >= w then return end
            for y = y0, y1 - 1, 6 do
                reaper.JS_LICE_FillRect(bmp, max(0, x - 1), y, 2, min(4, y1 - y), dash, 1, "COPY")
            end
        end
        local qlo, qhi = ql - tl - g, qr + te + g
        local seen, count = {}, 0
        local function box(q, pitch, yc, exempt)
            if q < qlo or q > qhi then return end
            local y0 = max(ny0, floor(yc - half + 0.5))
            local y1 = min(ny1, floor(yc + half + 0.5))
            if y1 - y0 < 1 then return end
            local X = nearest(q)
            local k = X * 128 + pitch
            if not seen[k] then
                seen[k] = true
                local il = floor(x_of(X - te) + 0.5)
                local ir = floor(x_of(X + tl) + 0.5)
                if ir > il then reaper.JS_LICE_FillRect(bmp, il, y0, ir - il, y1 - y0, fill, 1, "COPY") end
            end
            if exempt and blink_on then dashed(floor(x_of(q) + 0.5), y0, y1) end
            count = count + 1
        end
        -- Exempt = inside the window but off the grid, so Quantize leaves it alone.
        -- A full-strength plain pull moves every boundary outside the window, so
        -- whatever it leaves in place (and isn't on a line already) is exempt.
        local P1 = make_params(g)
        P1.str, P1.weighted, P1.edge = 1, false, false
        local function exempt(q, nq) return abs(nq - q) < EPS and abs(q - nearest(q)) > EPS end
        local length_mode = settings.mode == 1
        local n_ex = 0
        for _, t in ipairs(S.takes) do
            local sess = S.sessions[t]
            if sess then
                for _, nt in ipairs(sess.notes) do
                    if count >= 4096 then break end   -- ponytail: hard cap, raise if huge visible selections get cut off
                    local yc = ny0 + (v.top - nt.pitch + 0.5) * rh
                    if yc + half > ny0 and yc - half < ny1 then
                        local nqs, nqe = plan_note(nt.qs, nt.qe, P1)
                        local ex_s = exempt(nt.qs, nqs)
                        local ex_e = length_mode and exempt(nt.qe, nqe)
                        if ex_s or ex_e then n_ex = n_ex + 1 end
                        box(nt.qs, nt.pitch, yc, ex_s)
                        if length_mode then box(nt.qe, nt.pitch, yc, ex_e) end
                    end
                end
            end
        end
        if IND_DEBUG then
            local n, p, qs = 0, "-", "-"
            for _, t in ipairs(S.takes) do local ss = S.sessions[t] if ss and ss.notes[1] then n = n + #ss.notes p, qs = ss.notes[1].pitch, ss.notes[1].qs end end
            reaper.ShowConsoleMsg(string.format("[IND] ruler %d view w=%s h=%s top=%s rh=%s lanes=%s notes area y=%s..%s | grid=%.4g win L/R=%.4g/%.4g QN | visible QN %.3f..%.3f | sel notes=%d first pitch=%s qs=%s -> y=%s | boxes=%d exempt=%d\n",
                ruler, w, h, v.top, v.rh, v.lanes, ny0, ny1, g, te, tl, ql, qr, n, p, qs,
                p ~= "-" and string.format("%.0f", ny0 + (v.top - p + 0.5) * rh) or "-", count, n_ex))
        end
    elseif IND_DEBUG then
        reaper.ShowConsoleMsg(string.format("[IND] nothing to draw: grid=%.4g window L/R=%.4g/%.4g QN\n", g, te, tl))
    end
    reaper.JS_Window_InvalidateRect(mv, 0, 0, w, h, false)
end

local function ind_safe_update()
    -- an error never switches the setting off (that got saved and stuck): drop
    -- this frame, report each new error once, try again on the next redraw
    local ok, err = pcall(ind_update)
    if not ok then
        pcall(ind_detach)
        err = tostring(err)
        if err ~= IND.last_err then
            IND.last_err = err
            status("Indicator error: see the REAPER console", 6)
            reaper.ShowConsoleMsg("["..SCRIPT_NAME.."] indicator: "..err.."\n")
        end
    end
end

reaper.atexit(function()
    if HAS_JS then pcall(ind_detach) end
    reaper.SetToggleCommandState(section_id, cmd_id, 0)
    reaper.RefreshToolbar2(section_id, cmd_id)
    save_settings()
    if S.uncommitted then add_undo(S.commit_desc or UNDO_LABEL) end
end)

-------------------------------------------------------------------------------
-- Test hook (inert in REAPER): lets an offline harness drive the engine.
-------------------------------------------------------------------------------
if rawget(_G, "LYX_QF_TEST") then
    LYX_QF_TEST({
        S = S, settings = settings, poll = poll, run_apply = run_apply,
        analyze = analyze, on_param_change = on_param_change,
        toggle_bypass = toggle_bypass, do_apply = do_apply, do_reset = do_reset,
        commit = commit, plan_note = plan_note, make_params = make_params,
        grid_use = grid_use, grid_flush = grid_flush, nearest = nearest,
        next_line = next_line, prev_line = prev_line, around = around,
        read_view = read_view, ind_update = ind_update, IND = IND,
    })
    if not rawget(_G, "LYX_QF_TEST_GUI") then return end
end

-------------------------------------------------------------------------------
-- ImGui context, fonts, theme
-------------------------------------------------------------------------------
local ctx = ImGui.CreateContext(SCRIPT_NAME)
G = require("_lib._Lyx_GUI")
G.load_theme(THEME_KEY)
sync_theme()

local fonts, font_px = {}, {}
local function build_fonts()
    local base = floor(14 * settings.ui_scale + 0.5)
    font_px.body  = base
    font_px.h1    = floor(base * 1.3 + 0.5)
    font_px.small = max(10, base - 2)
    font_px.big   = floor(base * 1.15 + 0.5)
    local B = K(ImGui.FontFlags_Bold) or 0
    local I = K(ImGui.FontFlags_Italic) or 0
    if FONT_API_010 then
        if not fonts.body then       -- scalable: create once, size at push time
            fonts.body  = ImGui.CreateFont('sans-serif', 0)
            fonts.h1    = ImGui.CreateFont('sans-serif', B)
            fonts.small = ImGui.CreateFont('sans-serif', I)
            fonts.big   = ImGui.CreateFont('sans-serif', B)
            for _, f in pairs(fonts) do ImGui.Attach(ctx, f) end
        end
    else
        fonts.body  = ImGui.CreateFont('sans-serif', font_px.body)
        fonts.h1    = ImGui.CreateFont('sans-serif', font_px.h1, B)
        fonts.small = ImGui.CreateFont('sans-serif', font_px.small, I)
        fonts.big   = ImGui.CreateFont('sans-serif', font_px.big, B)
        for _, f in pairs(fonts) do ImGui.Attach(ctx, f) end
    end
end
build_fonts()

local function push_font(name)
    if FONT_API_010 then ImGui.PushFont(ctx, fonts[name], font_px[name])
    else                 ImGui.PushFont(ctx, fonts[name]) end
end

local function set_ui_scale(v)
    v = clamp(v, 0.75, 2.5)
    if abs(v - settings.ui_scale) < 0.001 then return end
    settings.ui_scale = v
    build_fonts()
    save_settings()
end

local pushed_colors, pushed_vars, pushed_global = 0, 0, false
local function push_theme()
    -- remembered: Inherit can be toggled between push and pop
    pushed_global = G.inherited
    if pushed_global then G.push_theme(ctx); return end
    local ui = settings.ui_scale
    local hover = lighten(theme.panel, 0.07)
    local cols = {
        { "Col_WindowBg", theme.bg },        { "Col_PopupBg", theme.bg },
        { "Col_ChildBg", theme.panel },      { "Col_Border", theme.border },
        { "Col_FrameBg", theme.panel },      { "Col_FrameBgHovered", hover },
        { "Col_FrameBgActive", hover },      { "Col_Text", theme.text },
        { "Col_TextDisabled", theme.text_dim },
        { "Col_Button", theme.panel },       { "Col_ButtonHovered", theme.slider },
        { "Col_ButtonActive", theme.slider_act },
        { "Col_SliderGrab", theme.slider },  { "Col_SliderGrabActive", theme.slider_act },
        { "Col_CheckMark", theme.accent },   { "Col_Header", theme.panel },
        { "Col_HeaderHovered", theme.slider }, { "Col_HeaderActive", theme.slider_act },
        { "Col_Separator", theme.border },   { "Col_TitleBg", theme.bg },
        { "Col_TitleBgActive", theme.panel }, { "Col_TitleBgCollapsed", theme.bg },
        { "Col_ScrollbarBg", theme.bg },     { "Col_ScrollbarGrab", theme.panel },
        { "Col_ResizeGrip", theme.panel },   { "Col_ResizeGripHovered", theme.slider },
        { "Col_ResizeGripActive", theme.slider_act },
        { "Col_Tab", theme.panel },          { "Col_TabHovered", theme.slider },
    }
    pushed_colors = 0
    for _, c in ipairs(cols) do
        local id = K(ImGui[c[1]])
        if id then
            ImGui.PushStyleColor(ctx, id, c[2])
            pushed_colors = pushed_colors + 1
        end
    end
    local vars = {
        { "StyleVar_FrameRounding", 4 * ui }, { "StyleVar_GrabRounding", 4 * ui },
        { "StyleVar_WindowRounding", 6 * ui }, { "StyleVar_PopupRounding", 4 * ui },
    }
    pushed_vars = 0
    for _, v in ipairs(vars) do
        local id = K(ImGui[v[1]])
        if id then
            ImGui.PushStyleVar(ctx, id, v[2])
            pushed_vars = pushed_vars + 1
        end
    end
end

local function pop_theme()
    if pushed_global then G.pop_theme(ctx); return end
    if pushed_vars > 0 then ImGui.PopStyleVar(ctx, pushed_vars) end
    if pushed_colors > 0 then ImGui.PopStyleColor(ctx, pushed_colors) end
end

-------------------------------------------------------------------------------
-- UI helpers
-------------------------------------------------------------------------------
local MOD_SHIFT = K(ImGui.Mod_Shift) or 0
local MOD_CMD   = (K(ImGui.Mod_Ctrl) or 0) | (K(ImGui.Mod_Super) or 0)
local TIP_FLAGS = K(ImGui.HoveredFlags_ForTooltip) or K(ImGui.HoveredFlags_DelayNormal) or 0

local function tip(text)
    if ImGui.IsItemHovered(ctx, TIP_FLAGS) then
        if ImGui.BeginTooltip(ctx) then
            ImGui.PushTextWrapPos(ctx, 300 * settings.ui_scale)
            ImGui.Text(ctx, text)
            ImGui.PopTextWrapPos(ctx)
            ImGui.EndTooltip(ctx)
        end
    end
end

-- Horizontal frame padding (large with a roomy global theme): fixed-size buttons must fit text + 2x this
local function pad_x() return (ImGui.GetStyleVar(ctx, K(ImGui.StyleVar_FramePadding))) end

-- SameLine at x px from the content start (ImGui's offset counts from the window edge, so
-- a large window padding would push the label under the item); never on top of the previous item.
local function same_line_at(x)
    ImGui.SameLine(ctx)
    ImGui.SetCursorPosX(ctx, max(ImGui.GetCursorPosX(ctx), ImGui.GetCursorStartPos(ctx) + x))
end

local function text_right(text, col)
    ImGui.SameLine(ctx)
    local tw = ImGui.CalcTextSize(ctx, text)
    if ImGui.GetContentRegionAvail(ctx) < tw then ImGui.NewLine(ctx) end   -- no room: next line
    local avail = ImGui.GetContentRegionAvail(ctx)
    ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + max(0, avail - tw))
    ImGui.TextColored(ctx, col, text)
end

-- Slider with: double-click = default, mouse wheel = +-1 (Shift +-5),
-- Ctrl/Cmd-click = type a value. Returns changed, value.
local function param_slider(id, value, lo, hi, def, fmt, width)
    ImGui.SetNextItemWidth(ctx, width)
    local changed, v = ImGui.SliderInt(ctx, id, value, lo, hi, fmt)
    if ImGui.IsItemDeactivatedAfterEdit(ctx) then request_commit(param_desc(), 0) end
    if ImGui.IsItemHovered(ctx) then
        if ImGui.IsMouseDoubleClicked(ctx, 0) then
            v, changed = def, true
            request_commit(param_desc(), 0)
        else
            local wheel = ImGui.GetMouseWheel(ctx)
            if wheel and wheel ~= 0 then
                local step = ((ImGui.GetKeyMods(ctx) & MOD_SHIFT) ~= 0) and 5 or 1
                v = clamp(v + (wheel > 0 and step or -step), lo, hi)
                changed = true
                request_commit(param_desc(), 0.4)
            end
        end
    end
    v = clamp(toint(v), lo, hi)
    return changed and v ~= value, v
end

local function segmented(id, labels, index, width)
    local ui = settings.ui_scale
    local gap = 2 * ui
    local bw = (width - gap * (#labels - 1)) / #labels
    local new = index
    for i, lab in ipairs(labels) do
        if i > 1 then ImGui.SameLine(ctx, 0, gap) end
        local on = (index == i - 1)
        if on then
            ImGui.PushStyleColor(ctx, K(ImGui.Col_Button), theme.accent)
            ImGui.PushStyleColor(ctx, K(ImGui.Col_ButtonHovered), theme.accent)
            ImGui.PushStyleColor(ctx, K(ImGui.Col_ButtonActive), theme.accent)
            ImGui.PushStyleColor(ctx, K(ImGui.Col_Text), theme.bg)
        end
        if ImGui.Button(ctx, lab.."##"..id..i, bw, 0) then new = i - 1 end
        if on then ImGui.PopStyleColor(ctx, 4) end
    end
    return new ~= index, new
end

local function grid_label(g)
    if not g or g <= EPS then return "-" end
    local inv = 4 / g                                  -- 1 / (fraction of a whole note)
    local function pow2(x)
        local r = floor(x + 0.5)
        return r > 0 and abs(x - r) < 1e-6 and (r & (r - 1)) == 0, r
    end
    local ok, d = pow2(inv);          if ok then return "1/"..d end
    ok, d = pow2(inv * 2 / 3);        if ok then return "1/"..d.."T" end
    ok, d = pow2(inv * 3 / 2);        if ok then return "1/"..d.."." end
    return string.format("%.4g QN", g)
end

local function first_session()
    for _, t in ipairs(S.takes) do
        local s = S.sessions[t]
        if s and #s.notes > 0 then return s end
    end
    for _, t in ipairs(S.takes) do
        if S.sessions[t] then return S.sessions[t] end
    end
end

-------------------------------------------------------------------------------
-- Timing view: every selected note folded into one grid cell
-------------------------------------------------------------------------------
local function draw_timing_view(W, H)
    local ui = settings.ui_scale
    local dl = ImGui.GetWindowDrawList(ctx)
    local x0, y0 = ImGui.GetCursorScreenPos(ctx)
    ImGui.InvisibleButton(ctx, "##timing", W, H)
    local hovered = ImGui.IsItemHovered(ctx)
    local x1, y1 = x0 + W, y0 + H
    ImGui.DrawList_AddRectFilled(dl, x0, y0, x1, y1, theme.panel, 4 * ui)

    local lab = 46 * ui
    local pad = 10 * ui
    local ax0, ax1 = x0 + lab, x1 - pad
    local cx = (ax0 + ax1) * 0.5
    local half = (ax1 - ax0) * 0.5
    local function X(f) return cx + clamp(f, -0.5, 0.5) * 2 * half end
    local yb, ya = y0 + H * 0.30, y0 + H * 0.72

    -- drag inside the view to set the window (left half = early side)
    if ImGui.IsItemActive(ctx) then
        local mx = ImGui.GetMousePos(ctx)
        local f = (mx - cx) / (2 * half)
        if not S.drag_side then
            S.drag_side = settings.link and 0 or (f < 0 and -1 or 1)
        end
        local pct = clamp(toint(abs(f) * 200), 0, 100)
        local key = (S.drag_side == 1) and "threshold_late" or "threshold"
        if settings[key] ~= pct then
            settings[key] = pct
            on_param_change()
        end
    elseif S.drag_side then
        S.drag_side = nil
        request_commit(param_desc(), 0)
    end

    local pe, pl = window_pct()
    local fe, fl = pe * 0.005, pl * 0.005               -- fractions of a grid step
    if fe > 0 or fl > 0 then
        ImGui.DrawList_AddRectFilled(dl, X(-fe), y0 + 1, X(fl), y1 - 1, with_alpha(theme.band, 34))
        local dcol = with_alpha(theme.band, 190)
        for _, xx in ipairs({ fe > 0 and X(-fe) or false, fl > 0 and X(fl) or false }) do
            if xx then
                local y = y0 + 3 * ui
                while y < y1 - 3 * ui do
                    ImGui.DrawList_AddLine(dl, xx, y, xx, min(y + 4 * ui, y1 - 3 * ui), dcol, 1)
                    y = y + 7 * ui
                end
            end
        end
    end
    ImGui.DrawList_AddLine(dl, cx, y0 + 3 * ui, cx, y1 - 3 * ui, with_alpha(theme.text, 150), 1)
    for _, yy in ipairs({ yb, ya }) do
        ImGui.DrawList_AddLine(dl, ax0, yy, ax1, yy, theme.border, 1)
    end

    push_font("small")
    ImGui.DrawList_AddText(dl, x0 + 6 * ui, yb - font_px.small * 0.6, theme.text_dim, "before")
    ImGui.DrawList_AddText(dl, x0 + 6 * ui, ya - font_px.small * 0.6, theme.text_dim, "after")
    ImGui.DrawList_AddText(dl, ax0, y1 - font_px.small - 3 * ui, with_alpha(theme.text_dim, 150), "early")
    local lw = ImGui.CalcTextSize(ctx, "late")
    ImGui.DrawList_AddText(dl, ax1 - lw, y1 - font_px.small - 3 * ui, with_alpha(theme.text_dim, 150), "late")
    ImGui.PopFont(ctx)

    local r = 2.3 * ui
    local dim = with_alpha(theme.text_dim, 190)
    local link = with_alpha(theme.accent, 70)
    for _, p in ipairs(S.plot.pts) do
        local xb, xa = X(p.o), X(p.n)
        if p.moved and not p.cross then
            ImGui.DrawList_AddLine(dl, xb, yb, xa, ya, link, 1)
        end
        local ca = p.moved and theme.accent or dim
        if p.tail then
            ImGui.DrawList_AddCircle(dl, xb, yb, r, dim, 0, 1)
            ImGui.DrawList_AddCircle(dl, xa, ya, r, ca, 0, 1)
        else
            ImGui.DrawList_AddCircleFilled(dl, xb, yb, r, dim)
            ImGui.DrawList_AddCircleFilled(dl, xa, ya, r, ca)
        end
    end
    ImGui.DrawList_AddRect(dl, x0, y0, x1, y1, theme.border, 4 * ui)

    if hovered and not S.drag_side then
        tip("Drag here to set the filter window (left = early, right = late).\n\n"..
            "Every selected note folded into one grid cell (centre line = grid, "..
            "edges = half a step early / late). Top row: original timing. "..
            "Bottom row: result with the current settings, even while bypassed. "..
            "Shaded: filter window, notes inside stay untouched."..
            (settings.mode == 1 and " Filled dots = note starts, rings = note ends." or ""))
    end
end

-------------------------------------------------------------------------------
-- Settings window
-------------------------------------------------------------------------------
local function color_row(label, key)
    ImGui.PushID(ctx, key)
    local changed, new_col = ImGui.ColorEdit4(ctx, label, own[key],
        K(ImGui.ColorEditFlags_NoInputs) | K(ImGui.ColorEditFlags_AlphaBar))
    if changed then
        own[key] = new_col
        sync_theme()
        save_settings()
    end
    ImGui.PopID(ctx)
end

local function draw_settings()
    push_font("body")
    local ui = settings.ui_scale
    ImGui.Text(ctx, "UI Scale")
    same_line_at(100 * ui)
    local bh = max(24 * ui, ImGui.GetFrameHeight(ctx))   -- room for the frame padding
    local bw = max(28 * ui, bh)
    if ImGui.Button(ctx, "-##uidown", bw, bh) then set_ui_scale(settings.ui_scale - 0.05) end
    ImGui.SameLine(ctx)
    ImGui.Text(ctx, string.format("%.2fx", settings.ui_scale))
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "+##uiup", bw, bh) then set_ui_scale(settings.ui_scale + 0.05) end

    ImGui.Separator(ctx)
    ImGui.TextColored(ctx, theme.subtitle, "Theme Colors")
    if G.theme_row(ctx, THEME_KEY) then sync_theme() end
    for _, row in ipairs(THEME_ROWS) do
        local off = G.inherited and not OWN_ONLY[row[2]]   -- set by the global theme
        if off then ImGui.BeginDisabled(ctx) end
        color_row(row[1], row[2])
        if off then ImGui.EndDisabled(ctx) end
    end
    ImGui.Separator(ctx)
    if ImGui.Button(ctx, "Reset theme to defaults") then
        for k, v in pairs(DEFAULT_THEME) do own[k] = v end
        sync_theme()
        save_settings()
    end

    if HAS_JS then
        ImGui.Separator(ctx)
        ImGui.Text(ctx, "Indicator offset")
        same_line_at(130 * ui)
        ImGui.SetNextItemWidth(ctx, -1)
        local ch, v = ImGui.SliderInt(ctx, "##ind_offset", ind_offset, -40, 40, "%d px")
        if ch then
            ind_offset = v
            reaper.SetExtState("Lyx_MIDI_QuantizeFilter", IND_OFFSET_KEY, tostring(v), true)
        end
        if ImGui.IsItemHovered(ctx) then
            ImGui.SetTooltip(ctx, "Moves the MIDI editor boxes up (-) or down (+) until their middle\nlines up with the notes. Saved for this computer.")
        end
    end

    ImGui.Dummy(ctx, 0, 6 * ui)
    push_font("small")
    ImGui.PushStyleColor(ctx, K(ImGui.Col_Text), theme.text_dim)
    ImGui.TextWrapped(ctx,
        HAS_JS and "js_ReaScriptAPI found: MIDI editor indicator available."
               or  "js_ReaScriptAPI not installed: no MIDI editor indicator.")
    ImGui.PopStyleColor(ctx)
    ImGui.PopFont(ctx)
    ImGui.PopFont(ctx)
end

-------------------------------------------------------------------------------
-- Main window
-------------------------------------------------------------------------------
local MODE_LABELS = { "Note Position", "Note Length" }

local function draw_main()
    local ui = settings.ui_scale
    push_font("body")
    local W = ImGui.GetContentRegionAvail(ctx)

    -- Header
    push_font("h1")
    ImGui.TextColored(ctx, theme.title, "Quantize Filter")
    ImGui.PopFont(ctx)
    ImGui.SameLine(ctx)
    local sbw, gap = max(44 * ui, ImGui.CalcTextSize(ctx, "Set") + 2 * pad_x()), 4 * ui
    -- header icons, right-aligned: [pin] [Set]
    G.align_right(ctx, ImGui.GetFrameHeight(ctx) + gap + sbw)
    G.pin(ctx, THEME_KEY)
    ImGui.SameLine(ctx, 0, gap)
    if ImGui.Button(ctx, "Set", sbw, 0) then S.show_settings = not S.show_settings end
    ImGui.Separator(ctx)

    -- Source
    local n_notes = total_notes()
    local sess0 = first_session()
    local src
    if #S.takes == 0 then
        src = "No MIDI take: open a MIDI editor or select a MIDI item"
    elseif n_notes == 0 then
        src = "No selected notes: select the notes to quantize"
    else
        src = string.format("%d note%s · %d take%s · grid %s",
            n_notes, n_notes == 1 and "" or "s", #S.takes, #S.takes == 1 and "" or "s",
            grid_label(sess0 and sess0.g))
        if sess0 and abs(sess0.swing) > 0.005 then
            src = src..string.format(" swing %d%%", toint(sess0.swing * 100))
        end
    end
    push_font("small")
    ImGui.TextColored(ctx, theme.text_dim, src)
    ImGui.PopFont(ctx)
    ImGui.Dummy(ctx, 0, 4 * ui)

    -- Mode
    local ch, v = segmented("mode", MODE_LABELS, settings.mode, W)
    if ch then
        settings.mode = v
        on_param_change()
        request_commit(param_desc(), 0)
    end
    tip("Note Position: move each note to the grid, keeping its length.\n"..
        "Note Length: pull start and end to the grid separately. A note inside "..
        "one grid step keeps the end nearer to a line and stretches the other "..
        "end to the next line. Tails stop at the next same-pitch note; heads "..
        "moving earlier trim the previous one.")
    ImGui.Dummy(ctx, 0, 6 * ui)

    -- Strength
    ImGui.Text(ctx, "Strength")
    ch, v = param_slider("##strength", settings.strength, 0, 100, DEFAULTS.strength, "%d%%", W)
    if ch then settings.strength = v; on_param_change() end
    tip("How far notes outside the window are pulled.\n"..
        "Double-click: 100 %.  Wheel: ±1 (Shift ±5).  Ctrl/Cmd-click: type.")
    ImGui.Dummy(ctx, 0, 4 * ui)

    -- Filter threshold
    ImGui.Text(ctx, "Filter window")
    ImGui.SameLine(ctx)
    if settings.link then
        ImGui.PushStyleColor(ctx, K(ImGui.Col_Text), theme.text_dim)
    else
        ImGui.PushStyleColor(ctx, K(ImGui.Col_Text), theme.band)
    end
    if ImGui.SmallButton(ctx, (settings.link and "Linked" or "Early / Late").."##link") then
        settings.link = not settings.link
        if not settings.link then settings.threshold_late = settings.threshold end
        on_param_change()
        request_commit(param_desc(), 0)
    end
    ImGui.PopStyleColor(ctx, 1)
    tip("Linked: one window on both sides of the grid.\n"..
        "Early / Late: separate sizes, e.g. keep a laid-back feel (large late "..
        "window) while still fixing rushed notes (small early window).")
    local pe, pl = window_pct()
    if sess0 and sess0.g > EPS and (pe > 0 or pl > 0) then
        local k = 0.01 * sess0.g * 0.5
        local function tk(p) return toint(p * k * sess0.ppq_qn) end
        local function ms(p) return p * k * 60000 / max(sess0.bpm, 1) end
        push_font("small")
        if pe == pl then
            text_right(string.format("±%d ticks · %.1f ms", tk(pe), ms(pe)), theme.text_dim)
        else
            text_right(string.format("-%.1f / +%.1f ms", ms(pe), ms(pl)), theme.text_dim)
            tip(string.format("Early -%d ticks, late +%d ticks", tk(pe), tk(pl)))
        end
        ImGui.PopFont(ctx)
    end
    local win_tip = "Notes closer to the grid than this keep their timing. "..
        "100 % = half a grid step. You can also drag in the timing view below.\n"..
        "Double-click: 0 %."
    if settings.link then
        ch, v = param_slider("##threshold", settings.threshold, 0, 100, DEFAULTS.threshold, "±%d%%", W)
        if ch then settings.threshold = v; on_param_change() end
        tip(win_tip)
    else
        local hw = (W - 6 * ui) * 0.5
        ch, v = param_slider("##threshold", settings.threshold, 0, 100, DEFAULTS.threshold, "early -%d%%", hw)
        if ch then settings.threshold = v; on_param_change() end
        tip(win_tip)
        ImGui.SameLine(ctx, 0, 6 * ui)
        ch, v = param_slider("##threshold_late", settings.threshold_late, 0, 100,
            DEFAULTS.threshold_late, "late +%d%%", hw)
        if ch then settings.threshold_late = v; on_param_change() end
        tip(win_tip)
    end
    ImGui.Dummy(ctx, 0, 4 * ui)

    -- Target + weighting
    ImGui.Text(ctx, "Pull to")
    same_line_at(100 * ui)
    if ImGui.RadioButton(ctx, "Grid", not settings.edge) and settings.edge then
        settings.edge = false; on_param_change(); request_commit(param_desc(), 0)
    end
    tip("Classic: notes outside the window move toward the grid line.")
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Window edge", settings.edge) and not settings.edge then
        settings.edge = true; on_param_change(); request_commit(param_desc(), 0)
    end
    tip("Only the part beyond the window is pulled: at 100 % every outlier lands "..
        "exactly on the window edge. Tightens loose playing into the window while "..
        "keeping its feel, and never reorders notes. Same as Grid when the window is 0 %.")

    local cw, wv = ImGui.Checkbox(ctx, "Weighted", settings.weighted)
    if cw then settings.weighted = wv; on_param_change(); request_commit(param_desc(), 0) end
    tip("Pull grows with distance: a note half a grid step off gets half of Strength, "..
        "closer notes proportionally less. Keeps the order of timing deviations, "..
        "so strums and flams keep their shape.")
    same_line_at(W * 0.5)
    if not HAS_JS then ImGui.BeginDisabled(ctx) end
    local ci, iv = ImGui.Checkbox(ctx, "Show indicator", settings.indicator)
    if ci then settings.indicator = iv; save_settings() end
    if not HAS_JS then ImGui.EndDisabled(ctx) end
    if HAS_JS then
        tip("Draw the filter window around the selected notes inside the MIDI editor.")
    elseif ImGui.IsItemHovered(ctx, K(ImGui.HoveredFlags_AllowWhenDisabled) or 0) then
        ImGui.SetTooltip(ctx, "Needs js_ReaScriptAPI (ReaPack).")
    end
    ImGui.Dummy(ctx, 0, 6 * ui)

    -- Timing view + stats
    draw_timing_view(W, 92 * ui)
    local A = S.plot
    push_font("small")
    if A.total > 0 then
        local kept = A.total - A.moved
        local txt = string.format("%d to move · %d kept", A.moved, kept)
        if A.moved > 0 then
            txt = txt..string.format(" · max %d ticks (%.1f ms)", toint(A.max_ticks), A.max_ms)
        end
        ImGui.TextColored(ctx, theme.stat_val, txt)
    else
        ImGui.TextColored(ctx, theme.text_dim, " ")
    end
    ImGui.PopFont(ctx)
    ImGui.Dummy(ctx, 0, 4 * ui)

    -- Bypass
    local has_notes = n_notes > 0
    if not has_notes then ImGui.BeginDisabled(ctx) end
    local live = not S.bypassed
    local label
    if live then label = "ACTIVE"
    elseif S.armed then label = "BYPASSED"
    else label = "OFF · click or touch a control" end
    if live then
        ImGui.PushStyleColor(ctx, K(ImGui.Col_Button), theme.accent)
        ImGui.PushStyleColor(ctx, K(ImGui.Col_ButtonHovered), lighten(theme.accent, 0.12))
        ImGui.PushStyleColor(ctx, K(ImGui.Col_ButtonActive), lighten(theme.accent, 0.22))
        ImGui.PushStyleColor(ctx, K(ImGui.Col_Text), theme.bg)
    else
        ImGui.PushStyleColor(ctx, K(ImGui.Col_Button), theme.button)
        ImGui.PushStyleColor(ctx, K(ImGui.Col_ButtonHovered), lighten(theme.button, 0.08))
        ImGui.PushStyleColor(ctx, K(ImGui.Col_ButtonActive), lighten(theme.button, 0.14))
        ImGui.PushStyleColor(ctx, K(ImGui.Col_Text), theme.text_dim)
    end
    push_font("big")
    if ImGui.Button(ctx, label.."##bypass", W, max(34 * ui, ImGui.GetFrameHeight(ctx))) then toggle_bypass() end
    ImGui.PopFont(ctx)
    ImGui.PopStyleColor(ctx, 4)
    tip("Bypass (B): A/B the result against the original notes.")

    local hw = (W - 6 * ui) * 0.5
    local bh = max(26 * ui, ImGui.GetFrameHeight(ctx))   -- never shorter than text + frame padding
    if S.bypassed then ImGui.BeginDisabled(ctx) end
    if ImGui.Button(ctx, "Apply", hw, bh) then do_apply() end
    if S.bypassed then ImGui.EndDisabled(ctx) end
    tip("Apply (Enter): keep the result and make it the new original, "..
        "so another pass works on top of it (iterative quantize).")
    ImGui.SameLine(ctx, 0, 6 * ui)
    if ImGui.Button(ctx, "Reset", hw, bh) then do_reset() end
    tip("Restore the original notes and the default parameters.")
    if not has_notes then ImGui.EndDisabled(ctx) end

    -- Status + footer
    push_font("small")
    local now = reaper.time_precise()
    if S.status ~= "" and now < S.status_until then
        ImGui.TextColored(ctx, theme.accent, S.status)
    else
        ImGui.TextColored(ctx, theme.text_dim, " ")
    end
    ImGui.TextColored(ctx, with_alpha(theme.text_dim, 170),
        string.format("v%s · B bypass · Enter apply · Space play", VERSION))
    ImGui.PopFont(ctx)

    ImGui.PopFont(ctx)
end

-------------------------------------------------------------------------------
-- Keyboard (the window captures the keyboard, so forward what matters)
-------------------------------------------------------------------------------
local function handle_keys(open)
    local function pressed(name)
        local k = K(ImGui[name])
        return k and ImGui.IsKeyPressed(ctx, k, false)
    end
    local mods = ImGui.GetKeyMods(ctx)
    local cmd = (mods & MOD_CMD) ~= 0
    local shift = (mods & MOD_SHIFT) ~= 0
    if pressed("Key_Escape") then return false end
    -- flush a pending (debounced) preview into its own undo point first, so
    -- undo removes it instead of the poll adding a bogus point afterwards
    if cmd and pressed("Key_Z") then
        if S.uncommitted then commit(S.commit_desc) end
        reaper.Main_OnCommand(shift and 40030 or 40029, 0)       -- redo / undo
    elseif cmd and pressed("Key_Y") then
        if S.uncommitted then commit(S.commit_desc) end
        reaper.Main_OnCommand(40030, 0)
    elseif not cmd then
        if pressed("Key_Space") then reaper.Main_OnCommand(40044, 0) end  -- play/stop
        if pressed("Key_B") then toggle_bypass() end
        if pressed("Key_Enter") or pressed("Key_KeypadEnter") then do_apply() end
    end
    return open
end

-------------------------------------------------------------------------------
-- Main loop
-------------------------------------------------------------------------------
local WINDOW_FLAGS = K(ImGui.WindowFlags_NoCollapse) | (K(ImGui.WindowFlags_NoScrollWithMouse) or 0)
local FOCUS_FLAGS  = K(ImGui.FocusedFlags_RootAndChildWindows) or 0

poll(true)
analyze()

local function main()
    poll(false)
    if G.poll() then sync_theme() end

    push_theme()
    ImGui.SetNextWindowSize(ctx, 400 * settings.ui_scale, 590 * settings.ui_scale,
        K(ImGui.Cond_FirstUseEver))
    -- narrowest width at which the rows still fit (plus the theme's window padding)
    local wpad = ImGui.GetStyleVar(ctx, K(ImGui.StyleVar_WindowPadding))
    ImGui.SetNextWindowSizeConstraints(ctx, 300 * settings.ui_scale + 2 * wpad, 200 * settings.ui_scale, 10000, 10000)
    local visible, open = ImGui.Begin(ctx, SCRIPT_NAME, true, WINDOW_FLAGS | G.pin_flag(THEME_KEY))
    if visible then
        local focused = ImGui.IsWindowFocused(ctx, FOCUS_FLAGS)
        if focused then ImGui.SetNextFrameWantCaptureKeyboard(ctx, true) end
        draw_main()
        if focused and not ImGui.IsAnyItemActive(ctx) then open = handle_keys(open) end
        ImGui.End(ctx)
    end

    if S.show_settings then
        ImGui.SetNextWindowSize(ctx, 340 * settings.ui_scale, 470 * settings.ui_scale,
            K(ImGui.Cond_FirstUseEver))
        local svis, sopen = ImGui.Begin(ctx, "Settings##lyx_qf", true,
            K(ImGui.WindowFlags_NoCollapse) | G.pin_flag(THEME_KEY))
        if svis then
            draw_settings()
            ImGui.End(ctx)
        end
        if not sopen then S.show_settings = false end
    end
    pop_theme()

    -- Engine: apply parameter changes from the originals. Very large
    -- selections are rate-limited so the GUI stays responsive while dragging.
    local now = reaper.time_precise()
    if S.dirty and now >= S.next_apply_at then
        S.dirty = false
        if not S.bypassed or any_written() then
            run_apply()
            local cost = reaper.time_precise() - now
            S.next_apply_at = now + ((cost > 0.02) and min(0.25, cost * 2) or 0)
        end
    end
    if S.commit_desc and not S.dirty and reaper.time_precise() >= S.commit_after
       and not ImGui.IsAnyItemActive(ctx) then
        commit(S.commit_desc)
    end
    if S.analysis_dirty then analyze() end
    if HAS_JS then ind_safe_update() end

    if open then reaper.defer(main) end
end

reaper.defer(main)
