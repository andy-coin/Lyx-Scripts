--[[
  @description Lyx Tuner
  @author Lyx
  @version 1.0.0
  @license MIT
  @provides
    [main] Lyx_Tuner toggle.lua
  @about
    # Lyx Tuner

    A chromatic tuner that lives in REAPER's transport bar, with a needle
    meter, multi-input listening and the Lyx global theme.

    ## 感謝 Thanks
    Lyx Tuner 改寫自 **Reapertips（Alejandro Hernandez）** 的 TunerBox
    （MIT 授權，https://www.reapertips.com）。音高偵測、隱藏軌安全設計、
    Transport 嵌入引擎都是原作者的心血，謝謝 Reapertips！
    Based on TunerBox by Reapertips (Alejandro Hernandez), MIT licence.
    Thank you, Reapertips!

    TunerBox's window, docking and drawing engine is in turn adapted from
    **Gridbox** by Ilias-Timon Poulakis (FeedTheCat), used under the MIT
    licence:

    > MIT License
    >
    > Copyright (c) 2020 iliaspoulakis
    >
    > Permission is hereby granted, free of charge, to any person obtaining
    > a copy of this software and associated documentation files (the
    > "Software"), to deal in the Software without restriction, including
    > without limitation the rights to use, copy, modify, merge, publish,
    > distribute, sublicense, and/or sell copies of the Software, and to
    > permit persons to whom the Software is furnished to do so, subject to
    > the following conditions:
    >
    > The above copyright notice and this permission notice shall be
    > included in all copies or substantial portions of the Software.
    >
    > THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
    > EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    > MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
    > NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
    > LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
    > OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
    > WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

    ## What Lyx changed
    - One on/off state for every project tab: the hidden listening track
      follows the tab you are looking at (no more "parked").
    - Transport readout is a horizontal ruler with a sub-pixel needle.
    - Listen to any set of inputs (checkboxes), mixed together.
    - Finer options: meter range, in-tune tolerance, needle speed,
      sharps/flats, octave and cents display, in-tune zone colour.
    - Transport box and big window follow the Lyx global theme.

    ## Requirements
    - REAPER 6.0 or newer, js_ReaScriptAPI extension
]]

local box_name = 'Lyx Tuner'
local box_id = 'lyxtuner'  -- theme integration file / parameter prefix (no spaces)
local extname = 'Lyx.Tuner'

local box_w
local box_h
local box_x
local box_y

local prev_box_w
local prev_box_h
local prev_box_x
local prev_box_y

local attach_mode
local attach_x
local attach_center_mode
local attach_center_x
local prev_is_centered

local user_bg_color
local user_border_color
local user_text_color
local user_swing_color
local user_corner_radius
local user_adaptive_color
local user_font_height
local user_font_family
local user_font_weight
local user_font_yoffs

local user_snap_size
local user_snap_on_color
local user_snap_off_color
local user_snap_sep_color
local user_zone_color

local window_hwnd
local prev_window_hwnd
local window_w
local window_h

local prev_time
local prev_window_w
local prev_window_h
local prev_color_theme
local prev_main_mult
local prev_top_window_cnt
local prev_attach_hwnd
local top_window_array = reaper.new_array(4096)
local main_hwnd = reaper.GetMainHwnd()



local drag_x
local drag_y
local swing_drag_x
local is_swing_drag

local is_left_click = false
local is_right_click = false

local snap_w = 0
local prev_is_snap
local prev_is_rel_snap
local prev_is_snap_hovered

local menu_time

local bitmap
local lice_font
local font_size

local snap_bitmap
local bg_bitmap

local prev_bg_color
local prev_bg_corner_r
local prev_snap_color

local is_redraw = false
local is_resize = false
local resize_flags = 0
local resize_cursor

local prev_hover_m_x, prev_hover_m_y
local prev_tooltip
local mouse_x, mouse_y
local hover_cnt = 0


local has_reapack = reaper.ReaPack_BrowsePackages ~= nil
local missing_dependencies = {}

function print(...)
    local values = {...}
    for i = 1, #values do values[i] = tostring(values[i]) end
    if #values == 0 then values[1] = 'nil' end
    reaper.ShowConsoleMsg(table.concat(values, ' ') .. '\n')
end

-- Check if js_ReaScriptAPI extension is installed
if not reaper.JS_Composite_Delay then
    if has_reapack then
        table.insert(missing_dependencies, 'js_ReaScriptAPI')
    else
        reaper.MB('Please install js_ReaScriptAPI extension', box_name, 0)
        return
    end
end


local _, script_path, sec, cmd = reaper.get_action_context()
local script_dir = script_path:match('^(.+)[\\/]')

function ConcatPath(...) return table.concat({...}, package.config:sub(1, 1)) end

if #missing_dependencies > 0 then
    local msg = 'Missing dependencies:\n\n'
    for _, dependency in ipairs(missing_dependencies) do
        msg = msg .. ' - ' .. dependency .. '\n'
    end
    reaper.MB(msg, box_name, 0)

    for i = 1, #missing_dependencies do
        if missing_dependencies[i]:match(' ') then
            missing_dependencies[i] = '"' .. missing_dependencies[i] .. '"'
        end
    end
    reaper.ReaPack_BrowsePackages(table.concat(missing_dependencies, ' OR '))
    return
end

if not reaper.ThemeLayout_GetLayout or not reaper.GetThingFromPoint or
    not reaper.ThemeLayout_GetParameter then
    reaper.MB(('%s needs REAPER 6.0 or newer.\n\nYou are running %s.')
        :format(box_name, reaper.GetAppVersion()), box_name, 0)
    return
end

-- Check REAPER version
local version = tonumber(reaper.GetAppVersion():match('[%d.]+'))
if version >= 7.03 then reaper.set_action_options(1) end

-- Detect operating system
local os = reaper.GetOS()
local is_windows = os:match('Win')
local is_macos = os:match('OS')
local is_linux = os:match('Other')


local hide_snap = reaper.GetExtState(extname, 'hide_snap') == '1'

local comp_fps = reaper.GetExtState(extname, 'comp_fps')
comp_fps = tonumber(comp_fps) or (is_windows and 30 or 0)
local comp_delay = comp_fps == 0 and 0 or 1 / comp_fps

local attach_window_title = reaper.GetExtState(extname, 'attach_title')
if attach_window_title == '' then attach_window_title = nil end

local attach_window_wait = reaper.GetExtState(extname, 'attach_wait')
if attach_window_wait == '' then attach_window_wait = nil end

local attach_window_child_id = reaper.GetExtState(extname, 'attach_child_id')
attach_window_child_id = tonumber(attach_window_child_id)

-- Lyx: the box lives in the transport only (attaching to other windows is
-- switched off further down), so a leftover attachment from an earlier run
-- is cleared here. Otherwise the box would stay stuck in that window, under
-- the transport, with no way to drag it back.
if attach_window_title or attach_window_child_id or attach_window_wait then
    attach_window_title, attach_window_child_id, attach_window_wait = nil, nil, nil
    for _, k in ipairs({'attach_title', 'attach_child_id', 'attach_wait',
        'attach_settings'}) do
        reaper.DeleteExtState(extname, k, true)
    end
end

local transport_title = reaper.JS_Localize('Transport', 'common')

--============================================================================--
--                             TUNER ENGINE                                   --
--============================================================================--

local JSFX_VERSION = '3'
-- The file name carries the version on purpose. REAPER keeps JSFX code
-- cached per path for the lifetime of the session, so overwriting the same
-- file leaves the OLD code running while the script thinks it updated it.
-- A new path forces a fresh load every time the detector changes.
local JSFX_FILE = 'lyx_tuner_v' .. JSFX_VERSION
-- Where the detector can live, most preferred first:
--   1. installed by ReaPack alongside the script (nothing to write, and
--      ReaPack removes it again when the package is uninstalled)
--   2. written by this script, for anyone who grabbed the .lua on its own
local JSFX_DIRS = {'Lyx'}
local JSFX_REL_PATH = JSFX_DIRS[1] .. '/' .. JSFX_FILE
local GMEM_NAME = 'LyxTuner'
-- Keep well clear of gmem[0..2], which the window engine uses for its
-- shared mouse position cache (see GetMousePosition further down).
local GB = 1000

-- gmem_attach selects the namespace for the WHOLE Lua state, and this script
-- needs two of them: the detector's own slots, and the 'mouse_pos' cache the
-- window engine shares with the other transport box scripts. Getting this
-- wrong is what caused 0.9.0's "moving the mouse turns into notes" bug, and
-- leaving it parked on one namespace means the other one is silently broken.
-- So every point of use says which it wants. The switch is a pointer swap
-- and the guard makes repeats free.
local MOUSE_GMEM = 'mouse_pos'
local gmem_ns

function AttachGmem(name)
    if gmem_ns ~= name then
        reaper.gmem_attach(name)
        gmem_ns = name
    end
end

local function GRead(i)
    AttachGmem(GMEM_NAME)
    return reaper.gmem_read(i)
end

local function GWrite(i, v)
    AttachGmem(GMEM_NAME)
    reaper.gmem_write(i, v)
end
local TRACK_TAG = 'LYX_TUNER'

local NOTE_NAMES = {'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#',
                    'B'}

-- The engine this script is built on does `local os = reaper.GetOS()`, which
-- shadows Lua's os table with a string for the rest of the file. Reach the
-- real one through _G so file deletion does not blow up.
local DeleteFile = _G.os and _G.os.remove or function() end

-- All mutable tuner state lives in this table (keeps local count low)
local T = {
    on = false,
    track = nil,
    fx = nil,
    a4 = 440,   -- see the one time reset below
    -- Hardware inputs to listen to (0 based), any combination. The track
    -- records the contiguous range that covers them and the detector mixes
    -- only the ticked ones (see InputRouting).
    inputs = {},
    -- Linear RMS below which the input is treated as silence (-48 dBFS)
    gate = tonumber(reaper.GetExtState(extname, 'gate')) or 0.0002,
    -- Lowest note the detector looks for. This was a setting until 1.4.0.
    -- Measured against both a real 5 string bass low A and the whole guitar
    -- range with hum and a weak fundamental, the wide range was no less
    -- accurate than the narrow one - 2 wrong readings in 1440 against 3 in
    -- 1300 - and it is the only one that finds a 27.5 Hz A0 at all. All it
    -- costs is reporting rate, 22 a second instead of 55, which is far
    -- faster than the display's own damping. So nobody has to know their
    -- instrument needs a menu.
    low_hz = 22,
    -- display
    text = '---',
    cents = 0,
    disp = 0,           -- damped cents used for drawing
    prev_disp = 0,
    note_since = 0,     -- when the current note first appeared
    settled = false,    -- true once the attack transient is over
    has_pitch = false,
    in_tune = false,
    -- internals
    hist = {},
    trace = {},         -- rolling log of readings, for diagnosing dropouts
    stable_f = nil,     -- last frequency we committed to
    oct_cnt = 0,        -- consecutive readings an octave away from it
    last_beat = -1,
    last_beat_time = 0,
    last_pitch_time = 0,
    poll_time = 0,
    check_time = 0,
    floor = 1,          -- adaptive estimate of the input noise floor
    level = 0,
    disp_step = nil,    -- cents per pixel of the deviation bar
    pub_live = nil,     -- last state published to the toggle action
    swept_proj = nil,   -- SweepOrphanTracks memo
    swept_cnt = nil,
    -- The project the hidden track lives in. Lyx: on/off is global, so the
    -- track follows the active project tab (FollowActiveProject).
    proj = nil,
    err = nil,
}

-- ---------------------------------------------------------------------------
-- Lyx options (global, not per REAPER theme)
-- ---------------------------------------------------------------------------
local function OptNum(key, def, lo, hi)
    local v = tonumber(reaper.GetExtState(extname, key))
    if not v or v ~= v then return def end
    return math.max(lo, math.min(hi, v))
end
local function OptBool(key, def)
    local v = reaper.GetExtState(extname, key)
    if v == '' then return def end
    return v == '1'
end
local O = {
    range = OptNum('range', 50, 5, 50),       -- meter spans +-range cents
    tol = OptNum('tol', 3, 1, 15),            -- in tune within +-tol cents
    speed = OptNum('speed', 0.25, 0.05, 1),   -- needle spring stiffness
    lock = OptNum('lock', 0.5, 0, 3),         -- seconds in tune before it glows
    flats = OptBool('flats', false),          -- Bb instead of A#
    octave = OptBool('octave', false),        -- show octave in the box
    show_cents = OptBool('show_cents', true), -- cents number in the box
    persp = OptNum('persp', 0.6, 0, 1),      -- ruler perspective, 0 = flat
}
local function SetOpt(key, v)
    O[key] = v
    if type(v) == 'boolean' then v = v and '1' or '0' end
    reaper.SetExtState(extname, key, tostring(v), true)
end

do -- inputs: "0,1,4"
    -- '' = never set (default: input 1), 'none' = the user unticked all
    local str = reaper.GetExtState(extname, 'inputs')
    for n in str:gmatch('%d+') do T.inputs[#T.inputs + 1] = tonumber(n) end
    if str == '' then T.inputs = {0} end
    table.sort(T.inputs)
end

-- ---------------------------------------------------------------------------
-- Lyx global theme (../_lib/_Lyx_Theme.lua). Colours only; the per REAPER
-- theme colours set in Appearance > Colors still win over these.
-- ---------------------------------------------------------------------------
local LYX_THEME_KEY = 'Lyx Tuner'
local LT
do
    -- Lyx Scripts/ (one folder up), so require '_lib.x' works like the others
    local root = ({reaper.get_action_context()})[2]
        :match('^(.*[/\\])[^/\\]+[/\\][^/\\]+$') or ''
    package.path = package.path .. ';' .. root .. '?.lua'
    local ok, mod = pcall(require, '_lib._Lyx_Theme')
    if ok and type(mod) == 'table' then LT = mod end
end
local lyx_colors_cache

-- nil when not following the Lyx theme (or the library is missing)
function LyxColors()
    if not (LT and LT.inherit(LYX_THEME_KEY)) then return nil end
    if lyx_colors_cache then return lyx_colors_cache end
    local ok, th = pcall(LT.get)
    if not ok or type(th) ~= 'table' or not th.colors then return nil end
    local c = th.colors
    lyx_colors_cache = {
        bg = c.bg2 or c.bg, text = c.text, tick = c.base,
        tune = c.accent, warn = LT.mix(0xE0605A, c.text, 0.1),
        mute = LT.mix(c.text, c.bg, 0.45),
        rounding = th.rounding and th.rounding.frame,
    }
    return lyx_colors_cache
end

-- true once each time the theme manager saved (polled once a second)
function LyxThemeChanged()
    if not LT then return false end
    local ok, changed = pcall(LT.changed)
    if ok and changed then lyx_colors_cache = nil; return true end
    return false
end

local JSFX_CODE = [==[
desc:Lyx Tuner Detector
// version: ]==] .. JSFX_VERSION .. [==[

// Auto-generated by the TunerBox script. Do not edit by hand.
// Reports detected pitch of the incoming audio through gmem:
//   gmem[0] = frequency in Hz
//   gmem[1] = clarity (0-1), 0 means "no pitch"
//   gmem[2] = heartbeat counter
//   gmem[3] = samplerate
//   gmem[4] = rms of the analysis window
//   gmem[5] = version of the JSFX that is actually running
//   gmem[6] = state machine state
//   gmem[7] = decimated samplerate
//   gmem[8] = highest analysed period (in decimated samples)
//   gmem[9]  = id of the instance currently allowed to publish
//   gmem[11] = liveness counter of that instance
//   gmem[13] = decaying peak level of the input
//   gmem[10] = noise gate (linear rms), written by the script
// Written by the script for the big readout, so both views agree exactly:
//   gmem[20] = displayed deviation in cents (already damped)
//   gmem[21] = displayed MIDI note number, 0 = nothing to show
//   gmem[22] = 1 while in tune
//   gmem[23] = 1 once the attack has settled
//   gmem[24] = reference pitch (A4 in Hz)
//   gmem[25] = displayed frequency in Hz
// Lyx additions, written by the script:
//   gmem[30] = meter range in cents (+-)
//   gmem[31] = 1 = flat note names
//   gmem[32] = in-tune tolerance in cents
//   gmem[33] = cents outside the tolerance over which off pitch fades in
//   gmem[34] = in-tune glow 0..1 (in tune long enough)
//   gmem[39] = how many inputs are ticked, gmem[40+k] = 1 if track channel k is
//   gmem[110] = 1 when the colours below are valid (0xRRGGBB)
//   gmem[111..116] = bg, text, ticks, in tune, off pitch, muted labels
// No pin declarations on purpose: the detector sees every channel of its
// track, so any set of hardware inputs can be mixed (see @sample).
options:gmem=LyxTuner

@init
// The host script is built on an engine that caches the mouse position in
// gmem[0], gmem[1] and gmem[2]. gmem_attach is per Lua state, so those
// writes land in THIS namespace and used to overwrite frequency, clarity
// and the heartbeat: moving the mouse literally produced notes. Everything
// this effect publishes therefore lives behind a base offset.
GB = 1000;

// ---- memory map ---------------------------------------------------------
FLEN  = 32768;  fbuf  = 0;          // full rate ring (linear, shifted)
DLEN  = 4096;   dbuf  = FLEN;       // decimated ring
                snapD = 36864;      // frozen decimated window   (2048)
                wrk   = 38912;      // NSDF values               (2048)
                snapF = 40960;      // frozen full rate window  (16384)
                wrk2  = 57344;      // refinement values          (512)
// snapF has to hold r_NF samples, and r_NF grows with the period: the
// lowest note in range at 192 kHz is a ~5000 sample period and the
// refinement correlates over 2.2 of them.

fpos = 0;
dpos = 0;
deccnt = 0;
hopcnt = 0;
heartbeat = 0;

dec = max(1, floor(srate / 8000));
dsrate = srate / dec;

lp1 = 0; lp2 = 0; lp3 = 0;
lpc = exp(-2 * $pi * 2200 / srate);
lpc_i = 1 - lpc;

// DC blocker, 15 Hz, well below anything we look for. Without it a DC
// offset - which some interfaces and DI boxes really do have - makes the
// NSDF 1.0 at every lag, so no peak is ever found and the tuner reads
// nothing at all while the level meter looks perfectly healthy.
dcr = exp(-2 * $pi * 15 / srate);
dcx = 0; dcy = 0;

// Search range.
//
//   low:  22 Hz. It has to be below the lowest note anybody will point
//         this at - a 5 string bass low B is 30.9 Hz and people tune those
//         down to A0, 27.5 Hz - because a period longer than tmax does NOT
//         read as "no note". Either the sub harmonic peak at T/2 is the
//         only one in the window, so the tuner confidently reports the note
//         an OCTAVE UP, which is the worst thing a tuner can do, or nothing
//         is found at all. Mains hum falls inside this range and is
//         rejected by the noise gate and the clarity test, not by the
//         search range.
//   high: 1470 Hz, so the 5th fret harmonic on the high E string (1318 Hz)
//         is in range. The decimation lowpass sits at 2200 Hz.
// slo is where the NSDF is computed from, tmin is the shortest period we
// are willing to ACCEPT. They are not the same thing, and conflating them
// cost an octave at the top of the range: the peak picker first has to walk
// past the initial positive lobe of the NSDF, and that lobe ends around a
// quarter of a period. Starting the walk at tmin meant that for a note near
// the top of the range - the 5th fret harmonic on the high E - the walk
// started INSIDE the lobe, skipped straight over the true peak, and locked
// onto the one at twice the period. slo has to sit below a quarter of the
// shortest period we care about, so 2.
slo = 2;
tmin = max(3, floor(dsrate / 1600));
cur_low = 22;
tmax = min(1000, floor(dsrate / cur_low));
NW = min(2048, floor(tmax * 2.5));
// Every lag is measured over the SAME window. This is not an efficiency
// detail, it is what makes the values at different lags comparable, and
// comparing them is the whole of the peak picking step.
//
// Version 1.1.0 made the window proportional to the lag, which made a wide
// search range cheap. On a real bass recording that turned out to move the
// first zero crossing of the correlation - where the peak search starts -
// around between lag 11 and lag 81 from one analysis to the next, because
// the short lags were being measured over a few dozen samples of mostly
// high frequency content. Whenever it landed low, the search would accept a
// spurious peak at a short lag: 8 wrong notes in 122 analyses of a plucked
// A0, against 0 with a fixed window.

// The analysis is spread over many audio blocks so no single block ever
// does more than about WORK multiply-accumulates. The chunks are measured
// in WORK, not in lags: the cost of a lag varies by two orders of magnitude
// across the range, so counting lags left most steps nearly empty and made
// a whole scan take twice the steps it needed.
WORK = 16000;
hop = max(16, floor(srate * 0.002));

state = 0;      // 0 = start scan, 1 = correlating, 2 = refining
scan_tau = 0;
r_lo = 0; r_hi = 0; r_L = 0; r_NF = 0; r_best = 0; r_bestL = 0;
c_Tf = 0; c_clarity = 0;

// Nothing is published from here. A new instance is not necessarily the
// publisher - it may be a leftover on another track - and zeroing the live
// reading on instantiation used to blank the readout of whoever was
// actually running. The configuration slots are written by the publisher
// on every block instead.

watchdog = 0;

// Every JSFX instance that declares this gmem name shares ONE array, so two
// tuner tracks (two project tabs, a leftover track) end up fighting over the
// same slots and the readings jump around. Elect a single publisher.
// A counter in the shared array, not rand(): two instances created in the
// same host tick can draw the same random number, and two instances with
// the same id both believe they are the publisher, forever.
gmem[GB+12] += 1;
inst_id = gmem[GB+12];
is_writer = 0;
seen_live = -1;
seen_cnt = 0;
peak = 0;
// EEL2 has no scientific notation: 1e12 is a syntax error, not a number.
BIG = 1000000000000;
// 150 ms fall, independent of sample rate (the old fixed coefficient fell
// 4x faster at 192 kHz than at 44.1)
peak_c = exp(-1 / (srate * 0.15));
snap_fpos = 0;
msk = 58000;    // per channel weight, copied from gmem by the publisher
nsel = 0;
lowreq = 0;
max_steps = 4;
steps = 0;

// Remembers the best evidence of a real note over the last few seconds, so
// the status report can tell "nothing ever reached the detector" apart from
// "plenty reached it but none of it was periodic". Called wherever a scan
// concludes, whatever it concluded.
function note_evidence(cl, f)
(
  peak_hold = max(peak_hold * 0.97, peak);
  clar_hold = max(clar_hold * 0.97, cl);
  cl >= 0.6 ? ( last_good = f; );
  gmem[GB+14] = peak_hold;
  gmem[GB+15] = clar_hold;
  gmem[GB+16] = last_good;
);

// ---- start a scan: freeze the analysis window ---------------------------
function scan_start() local(i, e, rms, thr)
(
  dpos < NW ? ( state = 0; ) : (
    // Freeze BOTH windows at this instant. The refinement used to snapshot
    // the full rate buffer when it started, tens of milliseconds later, so
    // on a vibrato the two stages were looking at different pitches and the
    // refinement bracket no longer contained the true peak.
    snap_fpos = fpos;
    memcpy(snapD, dbuf + dpos - NW, NW);

    e = 0; i = 0;
    while (i < NW) ( e += snapD[i] * snapD[i]; i += 1; );
    rms = sqrt(e / NW);
    gmem[GB+4] = rms;

    thr = gmem[GB+10] > 0 ? gmem[GB+10] : 0.0002;
    rms < thr ? (
      gmem[GB+1] = 0;
      note_evidence(0, 0);
      heartbeat += 1; gmem[GB+2] = heartbeat;
      state = 0;
    ) : (
      scan_tau = slo;
      state = 1;
    );
  );
);

// ---- one chunk of the NSDF ----------------------------------------------
// NOTE: "spent", not "work". EEL2 identifiers are CASE INSENSITIVE, so a
// local called work is the same variable as the global WORK - setting it to
// zero set the budget to zero, the loop never ran a single iteration, the
// scan never advanced past its first chunk, and the only thing that ever
// finished a scan was the watchdog. The detector looked alive (the heartbeat
// ticked once a second) and never produced a single reading.
function scan_chunk() local(i, tau, ac, m, n2, a, b, spent)
(
  spent = 0;
  while (scan_tau <= tmax && spent < WORK) (
    tau = scan_tau;
    ac = 0; m = 0; i = 0; n2 = NW - tau;
    while (i < n2) (
      a = snapD[i]; b = snapD[i + tau];
      ac += a * b;
      m += a * a + b * b;
      i += 1;
    );
    wrk[tau] = m > 0 ? 2 * ac / m : 0;
    spent += n2;
    scan_tau += 1;
  );
);

// ---- pick the peak, then set up the refinement --------------------------
function scan_pick() local(t, st, gmax, thresh, chosen, y1, y2, y3, d, delta, Tf)
(
  t = slo;
  while (t <= tmax && wrk[t] > 0) ( t += 1; );
  st = t;

  gmax = 0; t = st;
  while (t <= tmax) ( wrk[t] > gmax ? (gmax = wrk[t]); t += 1; );
  thresh = gmax * 0.86;

  chosen = 0;
  t = st + 1;
  while (t < tmax && chosen == 0) (
    (wrk[t] > wrk[t - 1] && wrk[t] >= wrk[t + 1] && wrk[t] > thresh) ?
      (chosen = t);
    t += 1;
  );

  // >= / <= : the parabolic interpolation below only needs one lag of
  // margin on each side. Demanding two threw away the top and bottom of
  // the range for nothing.
  // publish what the picker saw, so a rejection can be explained instead
  // of guessed at
  gmem[GB+18] = gmax;
  gmem[GB+19] = chosen;
  gmem[GB+26] = st;
  gmem[GB+27] = tmin;

  (chosen >= tmin && chosen <= tmax - 1 && gmax >= 0.6) ? (
    y1 = wrk[chosen - 1]; y2 = wrk[chosen]; y3 = wrk[chosen + 1];
    d = y1 - 2 * y2 + y3;
    delta = d != 0 ? 0.5 * (y1 - y3) / d : 0;
    abs(delta) > 1 ? (delta = 0);
    Tf = (chosen + delta) * dec;
    c_clarity = wrk[chosen];

    bw = max(3, dec + 2);
    r_lo = max(2, floor(Tf + 0.5) - bw);
    r_hi = floor(Tf + 0.5) + bw;
    // 2.2 periods is enough for the correlation and keeps the cost of a lag
    // proportional to the period rather than three times it
    r_NF = min(12000, max(floor(Tf * 2.2), r_hi + 16));
    (snap_fpos >= r_NF && r_NF > r_hi + 8) ? (
      memcpy(snapF, fbuf + snap_fpos - r_NF, r_NF);
      r_L = r_lo; r_best = -2; r_bestL = r_lo;
      c_Tf = Tf;
      state = 2;
    ) : (
      gmem[GB+0] = srate / Tf;
      gmem[GB+1] = c_clarity;
      note_evidence(c_clarity, srate / Tf);
      heartbeat += 1; gmem[GB+2] = heartbeat;
      state = 0;
    );
  ) : (
    gmem[GB+1] = 0;
    // gmax is the best correlation anywhere in the range: worth keeping
    // even when it failed the test, it is the difference between "silence"
    // and "loud but not a note"
    note_evidence(gmax, 0);
    heartbeat += 1; gmem[GB+2] = heartbeat;
    state = 0;
  );
);

// ---- one chunk of the full rate refinement ------------------------------
function refine_chunk() local(i, ac, m, v, n2, a, b, spent)
(
  spent = 0;
  while (r_L <= r_hi && spent < WORK) (
    ac = 0; m = 0; i = 0; n2 = r_NF - r_L;
    while (i < n2) (
      a = snapF[i]; b = snapF[i + r_L];
      ac += a * b;
      m += a * a + b * b;
      i += 1;
    );
    v = m > 0 ? 2 * ac / m : 0;
    wrk2[r_L - r_lo] = v;
    v > r_best ? ( r_best = v; r_bestL = r_L; );
    r_L += 1;
    spent += n2;
  );
);

function refine_done() local(k, y1, y2, y3, d, delta, Tf)
(
  (
    Tf = r_bestL;
    k = r_bestL - r_lo;
    (k > 0 && k < r_hi - r_lo) ? (
      y1 = wrk2[k - 1]; y2 = wrk2[k]; y3 = wrk2[k + 1];
      d = y1 - 2 * y2 + y3;
      delta = d != 0 ? 0.5 * (y1 - y3) / d : 0;
      abs(delta) < 1 ? (Tf = r_bestL + delta);
    );
    Tf > 0 ? (
      gmem[GB+0] = srate / Tf;
      // r_best, not max(c_clarity, r_best): the frequency being published
      // comes from the refinement, so the confidence published with it has
      // to be the refinement's. Taking the better of the two let a bad
      // refinement hide behind a good coarse pass.
      gmem[GB+1] = r_best;
      note_evidence(r_best, srate / Tf);
    ) : (
      gmem[GB+1] = 0;
      note_evidence(0, 0);
    );
    heartbeat += 1; gmem[GB+2] = heartbeat;
    state = 0;
  );
);

@block
// ---- who is allowed to publish? -----------------------------------------
// Exactly one instance writes to the shared slots, so a leftover detector
// in another project tab cannot fight over them.
gmem[GB+9] == inst_id ? (
  // publish the configuration from here rather than from @init, so an
  // instance that is not the publisher never touches the shared slots
  is_writer == 0 ? ( hopcnt = 0; state = 0; );
  is_writer = 1;
  // The script chooses how low to look. Written out as plain nested
  // conditionals with a local copy rather than one clever line: this is the
  // handshake that decides the whole search range, a silent failure here
  // means the detector is looking for a note the user cannot play, and
  // there is nothing to gain from being terse.
  lowreq = gmem[GB+17];
  lowreq >= 16 ? (
    lowreq <= 1600 ? (
      lowreq != cur_low ? (
        cur_low = lowreq;
        tmax = min(1000, floor(dsrate / cur_low));
        NW = min(2048, floor(tmax * 2.5));
        state = 0;
        scan_tau = slo;
      );
    );
  );
  gmem[GB+3] = srate;
  gmem[GB+5] = ]==] .. JSFX_VERSION .. [==[;
  gmem[GB+7] = dsrate;
  gmem[GB+8] = tmax;
  // what the detector is ACTUALLY using, and what it thinks the script
  // asked for. If these disagree with the script the handshake is broken,
  // and that is invisible from either side alone.
  gmem[GB+28] = cur_low;
  gmem[GB+29] = gmem[GB+17];
  gmem[GB+11] += 1;
  // which track channels to listen to
  nsel = 0; k = 0;
  while (k < 64) (
    msk[k] = (k < num_ch && gmem[GB+40+k] > 0) ? 1 : 0;
    nsel += msk[k];
    k += 1;
  );
) : (
  is_writer = 0;
  // Nobody holds the slot (the script clears it whenever the tuner is
  // switched on): claim it immediately. Waiting the full timeout here is
  // what used to leave the box showing "---" for two to nine seconds after
  // every switch on, depending on the audio buffer size.
  gmem[GB+9] == 0 ? (
    gmem[GB+9] = inst_id;
    seen_cnt = 0;
  ) : (
    gmem[GB+11] == seen_live ? ( seen_cnt += 1; ) : ( seen_live = gmem[GB+11]; seen_cnt = 0; );
    // the current publisher stopped running: take over
    seen_cnt > 200 ? ( gmem[GB+9] = inst_id; seen_cnt = 0; );
  );
);

hopcnt += samplesblock;
// One analysis step per audio BLOCK would tie the update rate to the user's
// buffer size (a 1024 sample buffer gave 4 readings/s instead of 22), so
// steps follow elapsed samples instead. The cap scales with the block: a
// big block has proportionally more time to spend, and a fixed cap of 8
// made the update rate collapse again above a 1408 sample buffer.
max_steps = max(4, ceil(samplesblock / hop) + 2);
steps = 0;
while (is_writer && hopcnt >= hop && steps < max_steps) (
  hopcnt -= hop;
  steps += 1;
  gmem[GB+13] = peak;
  state == 0 ? (
    watchdog = 0;
    scan_start();
  ) : (
    watchdog += 1;
    // Never let the machine sit in one scan: restart if it takes too long
    watchdog > 200 ? (
      state = 0;
      gmem[GB+1] = 0;
      note_evidence(0, 0);
      heartbeat += 1; gmem[GB+2] = heartbeat;
    ) : (
      state == 1 ? (
        scan_chunk();
        scan_tau > tmax ? ( scan_pick(); );
      ) : (
        refine_chunk();
        r_L > r_hi ? ( refine_done(); );
      );
    );
  );
  gmem[GB+6] = state;
);
// never build a backlog we would then try to catch up on in one block
hopcnt > hop * max_steps ? ( hopcnt = hop * max_steps; );

@sample
// Average, not sum: a centre panned guitar would otherwise read 6 dB hotter
// than the same signal on one channel, and the noise gate the user sets in
// dB would mean two different things depending on their routing.
nsel > 0 ? (
  s = 0; k = 0;
  while (k < num_ch) ( msk[k] ? (s += spl(k)); k += 1; );
  s /= nsel;
) : (
  s = (spl0 + spl1) * 0.5;
);
// One NaN or infinity from an upstream plugin would poison the lowpass
// state permanently - it is an IIR - and the tuner would read nothing for
// the rest of the session with no visible cause.
(s == s && abs(s) < BIG) ? 0 : ( s = 0; lp1 = 0; lp2 = 0; lp3 = 0; dcy = 0; dcx = 0; );

dcy = s - dcx + dcr * dcy; dcx = s; s = dcy;

peak = max(peak * peak_c, abs(s));

fpos >= FLEN ? (
  memcpy(fbuf, fbuf + FLEN / 2, FLEN / 2);
  fpos = FLEN / 2;
  snap_fpos = max(0, snap_fpos - FLEN / 2);
);
fbuf[fpos] = s; fpos += 1;

lp1 = lp1 * lpc + s * lpc_i;
lp2 = lp2 * lpc + lp1 * lpc_i;
lp3 = lp3 * lpc + lp2 * lpc_i;

deccnt += 1;
deccnt >= dec ? (
  deccnt = 0;
  dpos >= DLEN ? ( memcpy(dbuf, dbuf + DLEN / 2, DLEN / 2); dpos = DLEN / 2; );
  dbuf[dpos] = lp3; dpos += 1;
);

@gfx 620 400
// ---------------------------------------------------------------------
// Big readout, laid out after the Logic tuner.
//
//   * a band of tick bars across the top, every 2 cents
//   * the bars BETWEEN the centre and where you are fill in, so the
//     amount of colour is the error - you watch it drain as you tune
//   * a marker at top centre plus a full height centre bar, so dead
//     centre is unmistakable
//   * a needle underneath pointing at the band, and the note below it
//
// Everything shown comes from the slots the script publishes, so this
// window and the transport box can never disagree.
// ---------------------------------------------------------------------
// Ask for a real pixel backing store. REAPER raises this to 2 on a retina
// display, so it must only be set when it is still 0, and every size below
// is derived from gfx_h and therefore scales by itself.
gfx_ext_retina < 1 ? gfx_ext_retina = 1;

function note_name(n) local(i) (
  i = n % 12;
  flats ? (
    i == 0 ? sprintf(#nn, "C")  : i == 1 ? sprintf(#nn, "Db") :
    i == 2 ? sprintf(#nn, "D")  : i == 3 ? sprintf(#nn, "Eb") :
    i == 4 ? sprintf(#nn, "E")  : i == 5 ? sprintf(#nn, "F")  :
    i == 6 ? sprintf(#nn, "Gb") : i == 7 ? sprintf(#nn, "G")  :
    i == 8 ? sprintf(#nn, "Ab") : i == 9 ? sprintf(#nn, "A")  :
    i == 10 ? sprintf(#nn, "Bb") : sprintf(#nn, "B");
  ) : (
    i == 0 ? sprintf(#nn, "C")  : i == 1 ? sprintf(#nn, "C#") :
    i == 2 ? sprintf(#nn, "D")  : i == 3 ? sprintf(#nn, "D#") :
    i == 4 ? sprintf(#nn, "E")  : i == 5 ? sprintf(#nn, "F")  :
    i == 6 ? sprintf(#nn, "F#") : i == 7 ? sprintf(#nn, "G")  :
    i == 8 ? sprintf(#nn, "G#") : i == 9 ? sprintf(#nn, "A")  :
    i == 10 ? sprintf(#nn, "A#") : sprintf(#nn, "B");
  );
);

// 0xRRGGBB -> gfx colour
function setc(rgb, a) (
  gfx_set(((rgb / 65536) | 0) / 255, (((rgb / 256) | 0) & 255) / 255,
          (rgb & 255) / 255, a);
);

// a .. b by t, both 0xRRGGBB
function setmix(a, b, t, al) local(ra, ga, ba, rb, g2, bb) (
  ra = (a / 65536) | 0; ga = ((a / 256) | 0) & 255; ba = a & 255;
  rb = (b / 65536) | 0; g2 = ((b / 256) | 0) & 255; bb = b & 255;
  gfx_set((ra + (rb - ra) * t) / 255, (ga + (g2 - ga) * t) / 255,
          (ba + (bb - ba) * t) / 255, al);
);

// an antialiased line with thickness, built from parallel hairlines
function thick_line(x1, y1, x2, y2, wid) local(dx, dy, len, nx, ny, i, o) (
  dx = x2 - x1; dy = y2 - y1;
  len = sqrt(dx * dx + dy * dy);
  len > 0 ? (
    nx = -dy / len; ny = dx / len;
    i = 0;
    while (i < wid * 2) (
      o = (i / 2 - wid / 2 + 0.25);
      gfx_line(x1 + nx * o, y1 + ny * o, x2 + nx * o, y2 + ny * o, 1);
      i += 1;
    );
  );
);

// one tick bar of the band, at a cents position
function bar(c, rin, wid) local(a) (
  a = c / RANGE * SPAN;
  thick_line(cx + sin(a) * R * rin, cy - cos(a) * R * rin,
             cx + sin(a) * R,       cy - cos(a) * R, wid);
);

W = gfx_w; H = gfx_h;
midi = gmem[GB+21];
cents = gmem[GB+20];
tuned = gmem[GB+22];
ready = gmem[GB+23];
a4 = gmem[GB+24] > 0 ? gmem[GB+24] : 440;
hz = gmem[GB+25];
RANGE = gmem[GB+30] >= 5 ? gmem[GB+30] : 50;
flats = gmem[GB+31] > 0;
TOL = gmem[GB+32] > 0 ? gmem[GB+32] : 3;
FADE = gmem[GB+33] > 0 ? gmem[GB+33] : 15;
GLOW = live ? gmem[GB+34] : 0;
live = ready > 0 && midi > 0;

// colours: the Lyx theme when the script published one, else the original
gmem[GB+110] > 0 ? (
  c_bg = gmem[GB+111]; c_text = gmem[GB+112]; c_tick = gmem[GB+113];
  c_tune = gmem[GB+114]; c_warn = gmem[GB+115]; c_mute = gmem[GB+116];
) : (
  c_bg = 0x161618; c_text = 0xEDEDF2; c_tick = 0x575761;
  c_tune = 0x46B9FE; c_warn = 0xEC5D51; c_mute = 0x7F7F8C;
);

setc(c_bg, 1); gfx_rect(0, 0, W, H);

cx = W * 0.5;
cy = H * 0.800;                        // needle pivot
R  = min(W * 0.435, H * 0.635);
SPAN = 0.96;                           // +-55 degrees maps to +-RANGE cents
STEP = RANGE / 25;                     // 51 bars whatever the range
MAJ = RANGE / 5;                       // a label every fifth of the range

c = live ? max(-RANGE, min(RANGE, cents)) : 0;
// off pitch colour fades in with the distance from the in-tune window
ft = max(0, min(1, (abs(cents) - TOL) / FADE));

WMIN = max(1, R * 0.0065);             // bar widths
WMAJ = max(2, R * 0.0105);
WCEN = max(3, R * 0.016);

// ---- in-tune zone, a faint wedge behind the band ----------------------
setc(c_tune, 0.16);
j = -TOL;
while (j <= TOL) ( bar(j, 0.80, WMIN); j += max(0.05, RANGE / 400); );

// ---- tick band -------------------------------------------------------
gfx_setfont(1, "Arial", max(8, floor(H / 25)));
n = -25;
while (n <= 25) (
  i = n * STEP;
  major = (n % 5) == 0;
  lit = live && n != 0 &&
        (c > 0 ? (i > 0 && i <= c + STEP * 0.5) :
         (c < 0 ? (i < 0 && i >= c - STEP * 0.5) : 0));

  lit ? (
    tuned > 0 ? setc(c_tune, 1) : setmix(c_tune, c_warn, ft, 1);
  ) : (
    setc(c_tick, major ? 0.90 : 0.42);
  );
  bar(i, major ? 0.865 : 0.912, major ? WMAJ : WMIN);

  (major && n != 0) ? (
    sprintf(#lb, "%d", i);
    gfx_measurestr(#lb, tw, th);
    setc(c_mute, 1);
    ang = i / RANGE * SPAN;
    gfx_x = cx + sin(ang) * R * 1.115 - tw * 0.5;
    gfx_y = max(1, cy - cos(ang) * R * 1.115 - th * 0.5);
    gfx_drawstr(#lb);
  );
  n += 1;
);

// ---- centre: a full depth bar plus a marker above it -----------------
tuned > 0 ? setc(c_tune, 1) : setc(c_text, live ? 0.85 : 0.5);
bar(0, 0.800, WCEN);

my1 = cy - R * 1.145;
my2 = cy - R * 1.048;
mw  = R * 0.040;
gfx_triangle(cx - mw, my1, cx + mw, my1, cx, my2);
thick_line(cx - mw, my1, cx, my2, 1);
thick_line(cx + mw, my1, cx, my2, 1);

// ---- note ------------------------------------------------------------
nsz = max(8, floor(min(H * 0.28, W * 0.26)));
gfx_setfont(2, "Arial", nsz, 'b');
live ? (
  note_name(midi);
  GLOW > 0 ? setmix(c_text, c_tune, GLOW, 1) :
    (tuned > 0 ? setc(c_text, 1) : setmix(c_tune, c_warn, ft, 1));
  gfx_measurestr(#nn, tw, th);
  gfx_x = cx - tw * 0.5;
  gfx_y = cy - th * 0.42;
  gfx_drawstr(#nn);

  gfx_setfont(3, "Arial", max(7, floor(H * 0.105)));
  sprintf(#ov, "%d", floor(midi / 12) - 1);
  gfx_measurestr(#ov, ow, oh);
  setc(c_mute, 1);
  gfx_x = cx + tw * 0.5 + H * 0.018;
  gfx_y = cy - th * 0.42 + th - oh * 1.15;
  gfx_drawstr(#ov);
) : (
  tw = 0;
);

// ---- guard arc, between the needle and the note ----------------------
setc(c_tick, 0.85);
gfx_arc(cx, cy, R * 0.315, -SPAN * 0.62, SPAN * 0.62, 1);

// ---- needle ----------------------------------------------------------
live ? (
  ang = c / RANGE * SPAN;
  // halo behind the needle once it has been in tune long enough
  GLOW > 0 ? (
    setc(c_tune, 0.10 * GLOW);
    thick_line(cx + sin(ang) * R * 0.33, cy - cos(ang) * R * 0.33,
               cx + sin(ang) * R * 0.85, cy - cos(ang) * R * 0.85,
               max(6, R * 0.05));
    setc(c_tune, 0.18 * GLOW);
    thick_line(cx + sin(ang) * R * 0.34, cy - cos(ang) * R * 0.34,
               cx + sin(ang) * R * 0.84, cy - cos(ang) * R * 0.84,
               max(4, R * 0.028));
  );
  tuned > 0 ? setc(c_tune, 1) : setmix(c_tune, c_warn, ft, 1);
  thick_line(cx + sin(ang) * R * 0.35, cy - cos(ang) * R * 0.35,
             cx + sin(ang) * R * 0.82, cy - cos(ang) * R * 0.82,
             max(2, R * 0.0095));
);

// ---- readouts flanking the note --------------------------------------
gfx_setfont(4, "Arial", max(8, floor(H / 22)));
setc(c_mute, 1);
base_y = cy - H * 0.012;

live ? sprintf(#l1, "%.1f Hz", hz) : sprintf(#l1, "-- Hz");
gfx_measurestr(#l1, lw, lh);
gfx_x = W * 0.055; gfx_y = base_y - lh * 0.5;
gfx_drawstr(#l1);

live ? sprintf(#l2, "%+.1f cents", cents) : sprintf(#l2, "-- cents");
gfx_measurestr(#l2, lw, lh);
gfx_x = W * 0.945 - lw; gfx_y = base_y - lh * 0.5;
gfx_drawstr(#l2);

gfx_setfont(5, "Arial", max(8, floor(H / 27)));
sprintf(#l3, "A4 = %.1f Hz", a4);
gfx_measurestr(#l3, lw, lh);
setc(c_mute, 0.7);
gfx_x = W * 0.055; gfx_y = H - lh - H * 0.05;
gfx_drawstr(#l3);
]==]

--------------------------------- JSFX file ---------------------------------

-- The directory this script writes to when it has to install the detector
-- itself. Never the ReaPack one: those files belong to ReaPack.
function GetJSFXDir()
    return ConcatPath(reaper.GetResourcePath(), 'Effects', 'Lyx')
end

function GetJSFXPath()
    return ConcatPath(GetJSFXDir(), JSFX_FILE)
end

-- Relative path (from the Effects folder) of a detector that already exists
-- on disk, or nil. Checks the ReaPack location first.
function FindInstalledJSFX()
    local root = ConcatPath(reaper.GetResourcePath(), 'Effects')
    for _, dir in ipairs(JSFX_DIRS) do
        local rel = dir .. '/' .. JSFX_FILE
        local path = ConcatPath(root, (rel:gsub('/', package.config:sub(1, 1))))
        local file = io.open(path, 'r')
        if file then
            local content = file:read(4096)
            file:close()
            if content and content:find('// version: ' .. JSFX_VERSION, 1, true)
            then
                return rel
            end
        end
    end
end

function InstallJSFX()
    -- Already there (ReaPack's copy, or one we wrote earlier)? Nothing to do.
    local found = FindInstalledJSFX()
    if found then
        JSFX_REL_PATH = found
        return true
    end

    local path = GetJSFXPath()

    local dir = GetJSFXDir()
    if reaper.RecursiveCreateDirectory then
        reaper.RecursiveCreateDirectory(dir, 0)
    end

    -- Clean up detectors written by previous versions of this script
    if reaper.EnumerateFiles then
        local old = {}
        local i = 0
        while true do
            local name = reaper.EnumerateFiles(dir, i)
            if type(name) ~= 'string' then break end
            if name:match('^lyx_tuner') and name ~= JSFX_FILE then
                old[#old + 1] = ConcatPath(dir, name)
            end
            i = i + 1
        end
        for _, f in ipairs(old) do DeleteFile(f) end
    end

    local file = io.open(path, 'w')
    if not file then
        T.err = 'Could not write JSFX to:\n' .. path
        return false
    end
    file:write(JSFX_CODE)
    file:close()
    return true
end

--------------------------------- The track ---------------------------------

-- Removes every track tagged as a tuner track in EVERY open project, so a
-- leftover from another tab cannot run a second detector against the same
-- shared gmem. Returns how many were removed.
function RemoveAllTunerTracks(except)
    local removed = 0
    local p = 0
    -- bounded on purpose: never trust an enumerator to terminate the loop
    while p < 128 do
        local proj = reaper.EnumProjects(p)
        if not proj then break end
        local i = reaper.CountTracks(proj) - 1
        while i >= 0 do
            local track = reaper.GetTrack(proj, i)
            if track and track ~= except and
                reaper.GetSetMediaTrackInfo_String(track,
                    'P_EXT:' .. TRACK_TAG, '', false) then
                reaper.DeleteTrack(track)
                removed = removed + 1
            end
            i = i - 1
        end
        p = p + 1
    end
    T.track = nil
    T.fx = nil
    T.proj = nil
    if removed > 0 then reaper.TrackList_AdjustWindows(false) end
    return removed
end

-- True when the tuner is on AND we are in the project it was turned on in.
-- Everything user facing (the readout, the icon, the click) goes through
-- this rather than T.on.
function TunerIsLive()
    return T.on
end

-- The project the tuner should be operating in right now.
function TunerProj()
    -- ValidatePtr2 rejects 0, and a closed tab's pointer is stale: fall
    -- back to the real active project object in both cases.
    if T.proj and reaper.ValidatePtr(T.proj, 'ReaProject*') then
        return T.proj
    end
    return (reaper.EnumProjects(-1))
end

function FindTunerTrack()
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local ret = reaper.GetSetMediaTrackInfo_String(track,
            'P_EXT:' .. TRACK_TAG, '', false)
        if ret then return track end
    end
end

-- True only for OUR track in the tuner's project. A handle is not enough:
-- once a track is deleted (closing or loading a project in the same tab,
-- an undo) REAPER can give its address to a user track, and ValidatePtr2
-- then happily says yes. Anything that writes to the tuner track goes
-- through this, so a recycled handle can never touch a user's track.
function IsTunerTrack(track)
    if not track or
        not reaper.ValidatePtr2(TunerProj(), track, 'MediaTrack*') then
        return false
    end
    local tagged = reaper.GetSetMediaTrackInfo_String(track,
        'P_EXT:' .. TRACK_TAG, '', false)
    return tagged == true
end

function AddTunerFX(track)
    local names = {JSFX_REL_PATH}
    for _, dir in ipairs(JSFX_DIRS) do names[#names + 1] = dir .. '/' .. JSFX_FILE end
    names[#names + 1] = 'JS: Lyx Tuner Detector'
    for _, name in ipairs(names) do
        local fx = reaper.TrackFX_AddByName(track, name, false, 1)
        if fx >= 0 then return fx end
    end
    return -1
end

function CreateTunerTrack()
    if not InstallJSFX() then return end

    reaper.PreventUIRefresh(1)

    local idx = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(idx, false)
    local track = reaper.GetTrack(0, idx)

    reaper.GetSetMediaTrackInfo_String(track, 'P_NAME', 'Lyx Tuner (auto)', true)
    reaper.GetSetMediaTrackInfo_String(track, 'P_EXT:' .. TRACK_TAG, '1', true)

    ApplyInputRouting(track)
    ArmTunerTrack(track)
    reaper.SetMediaTrackInfo_Value(track, 'B_SHOWINTCP', 0)
    reaper.SetMediaTrackInfo_Value(track, 'B_SHOWINMIXER', 0)

    local fx = AddTunerFX(track)

    reaper.PreventUIRefresh(-1)
    reaper.TrackList_AdjustWindows(false)

    if fx < 0 then
        reaper.DeleteTrack(track)
        T.err = 'Could not load the tuner JSFX.\n\nExpected at:\n' ..
            GetJSFXPath()
        return
    end

    T.track = track
    T.fx = fx
    T.proj = reaper.EnumProjects(-1)
    return track
end

-- Deletes ONLY a track this script tagged. It checks the tag rather than
-- trusting T.track, so a stale handle can never take a user's track with it.
function RemoveTunerTrack()
    local track = T.track
    local is_ours = track and reaper.ValidatePtr(track, 'MediaTrack*') and
        reaper.GetSetMediaTrackInfo_String(track, 'P_EXT:' .. TRACK_TAG, '',
            false)
    if not is_ours then track = FindTunerTrack() end
    T.track = nil
    T.fx = nil
    if track then
        reaper.PreventUIRefresh(1)
        reaper.DeleteTrack(track)
        reaper.PreventUIRefresh(-1)
        reaper.TrackList_AdjustWindows(false)
    end
end

-- ---------------------------------------------------------------------
-- The detector FX
-- ---------------------------------------------------------------------

function FindTunerFX(track)
    for i = 0, reaper.TrackFX_GetCount(track) - 1 do
        local _, name = reaper.TrackFX_GetFXName(track, i, '')
        if name and name:find('Lyx Tuner', 1, true) then return i end
    end
    return -1
end

-- Puts the hidden track into the one state it is ever allowed to be in:
-- record mode "disable (input monitoring only)", armed, monitoring, no
-- output. Record mode 2 is what makes it structurally impossible for the
-- track to capture anything, whatever the transport is doing, so there is
-- no un-arm dance around takes and nothing here depends on play state.
function ArmTunerTrack(track)
    local V = reaper.GetMediaTrackInfo_Value
    local Set = reaper.SetMediaTrackInfo_Value
    -- set record mode FIRST: arming a track that is still in a capturing
    -- record mode, even for an instant, is the one thing worth avoiding
    if V(track, 'I_RECMODE') ~= 2 then Set(track, 'I_RECMODE', 2) end
    if V(track, 'B_MAINSEND') ~= 0 then Set(track, 'B_MAINSEND', 0) end
    if V(track, 'I_RECARM') ~= 1 then Set(track, 'I_RECARM', 1) end
    if V(track, 'I_RECMON') ~= 1 then Set(track, 'I_RECMON', 1) end
end

-- Keeps the hidden track healthy on the periodic check.
--
-- This deliberately does NOT re-arm on every pass. The track is hidden from
-- the TCP and the mixer, so if the user runs "un-arm all tracks" and it
-- silently armed itself again a second later, they would have no way to see
-- which track was doing it. Un-arming it just means the tuner stops
-- reading, which the box shows plainly, and switching the tuner off and on
-- puts it back.
function MaintainTunerTrack()
    local track = T.track
    if not IsTunerTrack(track) then return end
    -- Record mode is the safety property, not a preference: restore it even
    -- if the user changed it, because a capturing record mode on a hidden
    -- armed track is how you end up with a stray file after a take.
    if reaper.GetMediaTrackInfo_Value(track, 'I_RECMODE') ~= 2 then
        reaper.SetMediaTrackInfo_Value(track, 'I_RECMODE', 2)
    end
    if reaper.GetMediaTrackInfo_Value(track, 'B_MAINSEND') ~= 0 then
        reaper.SetMediaTrackInfo_Value(track, 'B_MAINSEND', 0)
    end
end

function EnsureTunerTrack()
    local track = T.track
    if IsTunerTrack(track) then return track end
    T.track = nil
    -- A track this project was saved with, or one an undo brought back.
    track = FindTunerTrack()
    if track then
        T.track = track
        T.proj = reaper.EnumProjects(-1)
        -- Re-add the JSFX if it went missing
        if reaper.TrackFX_GetCount(track) == 0 then
            InstallJSFX()
            T.fx = AddTunerFX(track)
        else
            T.fx = 0
        end
        -- Only write what differs: every write can mark the project as
        -- modified, and a saved track is usually already right.
        local V = reaper.GetMediaTrackInfo_Value
        local Set = reaper.SetMediaTrackInfo_Value
        ApplyInputRouting(track)
        -- A track saved by an older build, or edited by hand, can arrive in
        -- a capturing record mode. Fix that before arming it, not on the
        -- next periodic pass a second later.
        ArmTunerTrack(track)
        if V(track, 'B_SHOWINTCP') ~= 0 then Set(track, 'B_SHOWINTCP', 0) end
        if V(track, 'B_SHOWINMIXER') ~= 0 then
            Set(track, 'B_SHOWINMIXER', 0)
        end
        return track
    end
    return CreateTunerTrack()
end

-- The track can only record ONE contiguous block of inputs, so it takes the
-- block that covers every ticked input (mono, stereo or multichannel) and
-- the detector mixes only the ticked channels inside it.
function InputRouting()
    -- nothing ticked: the track listens to no input at all
    if #T.inputs == 0 then return -1, 2, {} end
    local lo, hi = T.inputs[1], T.inputs[#T.inputs]
    local span = hi - lo + 1
    local mask = {}
    for _, n in ipairs(T.inputs) do mask[n - lo] = true end
    if span == 1 then return lo, 2, mask end
    if span == 2 then return lo | 1024, 2, mask end
    return lo | 2048, math.min(64, span + span % 2), mask
end

-- Only writes what differs: every write can mark the project as modified.
function ApplyInputRouting(track)
    local rec, nchan = InputRouting()
    local V = reaper.GetMediaTrackInfo_Value
    local Set = reaper.SetMediaTrackInfo_Value
    local changed = false
    if V(track, 'I_NCHAN') ~= nchan then Set(track, 'I_NCHAN', nchan) end
    if V(track, 'I_RECINPUT') ~= rec then
        Set(track, 'I_RECINPUT', rec)
        changed = true
    end
    return changed
end

-- Everything the detector and the big window read from the script.
-- Cheap, so it is simply re-sent once a second as well as on change.
function PublishConfig()
    local _, _, mask = InputRouting()
    local n = 0
    for k = 0, 63 do
        GWrite(GB + 40 + k, mask[k] and 1 or 0)
        if mask[k] then n = n + 1 end
    end
    GWrite(GB + 39, n)
    GWrite(GB + 30, O.range)
    GWrite(GB + 31, O.flats and 1 or 0)
    GWrite(GB + 32, O.tol)
    GWrite(GB + 33, 0.001) -- no colour fade in the big window either
    GWrite(GB + 10, T.gate)
    GWrite(GB + 17, T.low_hz)
    local c = LyxColors()
    if c then
        GWrite(GB + 111, c.bg); GWrite(GB + 112, c.text)
        GWrite(GB + 113, c.tick); GWrite(GB + 114, c.tune)
        GWrite(GB + 115, c.warn); GWrite(GB + 116, c.mute)
    end
    GWrite(GB + 110, c and 1 or 0)
end

function SetTunerInputs(list)
    table.sort(list)
    if #list > 0 and list[#list] - list[1] + 1 > 64 then
        reaper.MB('The ticked inputs must fit within 64 channels of each \z
            other.', box_name, 0)
        return
    end
    T.inputs = list
    reaper.SetExtState(extname, 'inputs',
        #list > 0 and table.concat(list, ',') or 'none', true)
    PublishConfig()
    T.hist = {}
    local track = T.track
    if IsTunerTrack(track) and ApplyInputRouting(track) then
        -- Re-arm so REAPER picks up the new input
        reaper.SetMediaTrackInfo_Value(track, 'I_RECARM', 0)
        reaper.SetMediaTrackInfo_Value(track, 'I_RECARM', 1)
    end
end

--------------------------------- Pitch math --------------------------------

function FreqToNote(freq, a4)
    local n = 12 * math.log(freq / a4, 2) + 69
    local nr = math.floor(n + 0.5)
    local cents = (n - nr) * 100
    local name = NOTE_NAMES[nr % 12 + 1]
    local octave = math.floor(nr / 12) - 1
    return name .. octave, cents
end

-- Returns the median frequency once the last 3 readings agree with each
-- other, or nil while the reading is still jumping around. This is what
-- stops noise and string attacks from flashing random notes.
local NOTE_INDEX = {}
for i, n in ipairs(NOTE_NAMES) do NOTE_INDEX[n] = i - 1 end

local FLAT = {['C#'] = 'Db', ['D#'] = 'Eb', ['F#'] = 'Gb', ['G#'] = 'Ab',
    ['A#'] = 'Bb'}

-- 'A#2' -> what the box shows, following the Lyx options
function DisplayName(text)
    local name, oct = text:match('^([A-G]#?)(-?%d+)$')
    if not name then return text end
    if O.flats then name = FLAT[name] or name end
    return O.octave and (name .. oct) or name
end

function NoteToMidi(text)
    local name, oct = text:match('^([A-G]#?)(-?%d+)$')
    local idx = name and NOTE_INDEX[name]
    if not idx then return 0 end
    return (tonumber(oct) + 1) * 12 + idx
end

-- A rolling trace of the last few seconds of readings. When a note drops
-- out for reasons that cannot be reproduced with a synthetic signal - and a
-- thick, slack, stiff bass string is exactly that - the only way to find
-- out why is to look at what the detector actually reported, reading by
-- reading, on the instrument that misbehaves.
local TRACE_N = 90

function Trace(freq, clarity, rms, verdict)
    local tr = T.trace
    tr[#tr + 1] = {t = reaper.time_precise(), f = freq, c = clarity,
        r = rms, v = verdict,
        -- what the detector's own peak picker saw for this scan
        gmax = GRead(GB + 18), pick = GRead(GB + 19),
        st = GRead(GB + 26), tmin = GRead(GB + 27)}
    while #tr > TRACE_N do table.remove(tr, 1) end
end

function PrintTrace()
    local tr = T.trace
    if #tr == 0 then
        reaper.ShowConsoleMsg('\nNo readings recorded yet.\n')
        return
    end
    local t0 = tr[#tr].t
    reaper.ShowConsoleMsg(('\nLAST %d READINGS  (most recent first)\n' ..
        'peak picker: gmax = best correlation anywhere, lag = the one it\n' ..
        'chose, zero = where it started looking, min = shortest allowed\n\n' ..
        '   age      freq      note   clarity      rms |  gmax  lag zero  min' ..
        ' | what happened\n'):format(#tr))
    for i = #tr, 1, -1 do
        local e = tr[i]
        local name = e.f > 0 and e.f == e.f and select(1, FreqToNote(e.f, T.a4))
            or '-'
        reaper.ShowConsoleMsg(
            ('%7.2fs %9.2f %7s %9.3f %8.5f | %5.2f %4d %4d %4d | %s\n')
            :format(e.t - t0, e.f, name, e.c, e.r,
                e.gmax or 0, e.pick or 0, e.st or 0, e.tmin or 0, e.v))
    end
end

-- How many consecutive octave-related readings it takes to believe one.
-- At ~25 readings a second this is about 160 ms.
local OCTAVE_HOLD = 4

function PushHistory(freq)
    local hist = T.hist

    -- An octave flip is not a new note, it is the detector changing its
    -- mind about which peak is the fundamental. That happens on very low,
    -- thick strings where the fundamental is weak: the correlation at half
    -- the period is nearly as good as at the whole one. Clearing the
    -- history on every flip is the worst possible response, because the
    -- history then never reaches two agreeing readings and the readout
    -- drops out completely - which looks like the tuner losing the note
    -- rather than like it disagreeing with itself. So an octave jump has to
    -- persist before it is believed, and until then it is ignored rather
    -- than allowed to wipe what we had.
    local ref = T.stable_f
    if ref and ref > 0 then
        local ratio = freq / ref
        local is_octave = math.abs(ratio - 2) < 0.06 or
            math.abs(ratio - 0.5) < 0.015
        if is_octave then
            T.oct_cnt = (T.oct_cnt or 0) + 1
            if T.oct_cnt < OCTAVE_HOLD then return nil end
        else
            T.oct_cnt = 0
        end
    end

    -- A genuinely new note should snap in instantly instead of being
    -- averaged with the previous one: drop the history whenever the pitch
    -- jumps by more than a few cents.
    local last = hist[#hist]
    if last and math.abs(freq / last - 1) > 0.03 then
        for i = #hist, 1, -1 do hist[i] = nil end
    end
    hist[#hist + 1] = freq
    while #hist > 3 do table.remove(hist, 1) end
    if #hist < 2 then return nil end

    local lo, hi = hist[1], hist[1]
    for i = 2, #hist do
        if hist[i] < lo then lo = hist[i] end
        if hist[i] > hi then hi = hist[i] end
    end
    -- Readings must sit within ~35 cents of each other
    if hi / lo > 1.02 then return nil end

    local sorted = {}
    for i = 1, #hist do sorted[i] = hist[i] end
    table.sort(sorted)
    local median = sorted[(#sorted + 1) // 2]
    T.stable_f = median
    T.oct_cnt = 0
    return median
end

--------------------------------- Polling -----------------------------------

function ReadTuner()
    local time = reaper.time_precise()

    local beat = GRead(GB + 2)
    if beat ~= T.last_beat then
        T.last_beat = beat
        T.last_beat_time = time
    end

    -- Rolling measurement of how often the JSFX reports
    if not T.rate_t0 then T.rate_t0, T.rate_b0 = time, beat end
    if time - T.rate_t0 >= 1 then
        T.rate = (beat - T.rate_b0) / (time - T.rate_t0)
        T.rate_t0, T.rate_b0 = time, beat
    end

    -- JSFX is not running (deleted track, bypassed fx, audio engine off...)
    if time > T.last_beat_time + 1.5 then
        T.hist = {}
        return SetDisplay('---', 0, false)
    end

    -- REAPER served a cached build of the detector: say so instead of
    -- silently reporting whatever that build happens to write
    if GRead(GB + 5) ~= tonumber(JSFX_VERSION) then
        T.hist = {}
        return SetDisplay('old', 0, false)
    end

    local clarity = GRead(GB + 1)
    local freq = GRead(GB + 0)
    local rms = GRead(GB + 4)
    T.level = GRead(GB + 13)

    -- Track the noise floor of this input and only trust readings that sit
    -- clearly above it. A fixed dB threshold cannot work: every interface
    -- and gain setting has a different floor, and analysing the floor is
    -- exactly what produces the drifting phantom notes.
    if rms > 0 then
        if rms < T.floor then
            T.floor = rms
        else
            T.floor = T.floor * 1.0002 + 1e-12
        end
    end
    local threshold = math.max(T.gate, T.floor * 2.5)

    local is_valid = rms > threshold and clarity >= 0.6 and
        freq >= T.low_hz and freq <= 1470

    if is_valid then
        T.bad_time = nil
        local stable = PushHistory(freq)
        if stable then
            T.last_pitch_time = time
            T.freq = stable
            local name, cents = FreqToNote(stable, T.a4)
            SetDisplay(name, cents, true)
            Trace(freq, clarity, rms, 'shown as ' .. name)
        else
            Trace(freq, clarity, rms,
                (T.oct_cnt or 0) > 0
                    and ('an octave from %.1f Hz, waiting (%d/%d)')
                        :format(T.stable_f or 0, T.oct_cnt, OCTAVE_HOLD)
                    or 'waiting for a second reading that agrees')
        end
        return
    end

    Trace(freq, clarity, rms,
        rms <= threshold and 'too quiet'
        or clarity < 0.6 and 'not periodic enough'
        or ('%.1f Hz is outside the %g - 1470 Hz range')
            :format(freq, T.low_hz))

    -- A single weak frame (attack transient, note decay) must NOT wipe the
    -- history, otherwise it never collects enough readings to show anything.
    T.bad_time = T.bad_time or time
    if time - T.bad_time > 0.4 then T.hist = {} end

    -- Lyx: the last reading is held - note, cents and needle stay where
    -- they were until the next note arrives (or the tuner is switched off).
end

-- A plucked string is genuinely sharp for the first fraction of a second:
-- the extra tension of the attack pushes the pitch up before it settles.
-- Showing that would flash the red arrow on a string that is perfectly in
-- tune, so the arrows stay neutral until the note has had time to settle.
local ATTACK_SETTLE = 0.18
-- Asymmetric thresholds keep the readout from flickering on the boundary:
-- in tune within O.tol cents, out again only past O.tol + 2.

function SetDisplay(text, cents, has_pitch)
    local time = reaper.time_precise()

    if text ~= T.text then T.note_since = time end

    local limit = T.in_tune and (O.tol + 2) or O.tol
    local in_tune = has_pitch and math.abs(cents) <= limit
    -- when the current stretch of being in tune began (a new note restarts it)
    if not in_tune then
        T.tune_since = nil
    elseif not T.in_tune or text ~= T.text or not T.tune_since then
        T.tune_since = time
    end

    -- Damping, the way a hardware tuner does it: snap when the note itself
    -- changes, ease when it is the same note drifting.
    if not has_pitch or text ~= T.text then
        T.disp = cents
    else
        -- light smoothing of the reading itself; the needle's own spring
        -- (NeedleTick) does the analog motion
        T.disp = T.disp + (cents - T.disp) * 0.5
    end

    local settled = has_pitch and (time - T.note_since) >= ATTACK_SETTLE

    -- Redraw when something actually changes on screen. The damped value
    -- moves on nearly every reading, but the only thing it drives is the
    -- length of the deviation bar, so the test is whether the bar would
    -- land on a different pixel. T.disp_step is the bar's cents-per-pixel,
    -- published by the drawing code; without it we fall back to a step that
    -- is finer than any real box.
    local step = T.disp_step or 0.5
    if text ~= T.text or has_pitch ~= T.has_pitch or in_tune ~= T.in_tune or
        settled ~= T.settled or
        math.floor(T.disp / step) ~= math.floor((T.prev_disp or 0) / step) then
        is_redraw = true
        T.prev_disp = T.disp
    end

    T.text = text
    T.cents = cents
    T.has_pitch = has_pitch
    T.in_tune = in_tune
    T.settled = settled

    -- Publish for the big readout so the two views can never disagree.
    -- The frequency belongs to the reading, so it goes stale the moment
    -- there is no reading: publish 0 rather than the last note's pitch.
    if not has_pitch then T.freq = nil end
    GWrite(GB + 20, T.disp)
    GWrite(GB + 21, has_pitch and NoteToMidi(text) or 0)
    GWrite(GB + 22, in_tune and 1 or 0)
    GWrite(GB + 23, settled and 1 or 0)
    GWrite(GB + 24, T.a4)
    GWrite(GB + 25, T.freq or 0)
end

local function dB(v)
    return v and v > 0 and 20 * math.log(v, 10) or -150
end

-- The one line worth reading first. Everything else in the report is
-- evidence for it.
local function Verdict()
    local peak5 = GRead(GB + 14)      -- loudest sample in the last ~5 s
    local clar5 = GRead(GB + 15)      -- best correlation in the last ~5 s
    local good5 = GRead(GB + 16)      -- last frequency worth believing

    if not T.on then
        return 'the tuner is switched OFF', ''
    end
    if #T.inputs == 0 then
        return 'NO INPUT IS TICKED', 'Tick at least one input in the settings window (Input tab).'
    end
    if GRead(GB + 5) ~= tonumber(JSFX_VERSION) then
        return 'REAPER is running an OLD cached build of the detector',
            'Reinstall from ReaPack, or restart REAPER.'
    end
    if GRead(GB + 28) > 0 and GRead(GB + 28) ~= T.low_hz then
        return ('the detector is searching from %g Hz, not the %g Hz you set')
            :format(GRead(GB + 28), T.low_hz),
            'Switch the tuner off and on again. If it comes back, tell me:\n' ..
            'the setting is not reaching the detector.'
    end
    if (T.rate or 0) < 1 then
        return 'the detector is NOT RUNNING',
            'The audio engine may be off, the FX bypassed, or the track gone.'
    end
    -- A confirmed note is stronger evidence than a peak accumulator that
    -- has just started or reset. The three evidence slots are published
    -- independently and can legitimately be observed between updates.
    if good5 > 0 then
        return ('working: last confident reading was %.2f Hz'):format(good5), ''
    end
    if dB(peak5) < -60 then
        return 'NO AUDIO is reaching the detector',
            'Nothing above -60 dBFS in the last 5 seconds, so this is not the\n' ..
            'detector: it is routing. Check the input in the right click menu,\n' ..
            'and that your interface really has the guitar on that input.\n' ..
            'Play something and run this again - the numbers below cover the\n' ..
            'last 5 seconds, so you can put the guitar down first.'
    end
    if dB(peak5) < -40 then
        return 'audio is arriving but it is VERY QUIET',
            ('Loudest in the last 5 s was %.1f dBFS. Turn up the input gain,\n' ..
             'or lower the noise gate in Advanced.'):format(dB(peak5))
    end
    if GRead(GB + 16) == 0 and clar5 >= 0.6 then
        return 'notes are being found but rejected as OUT OF RANGE',
            ('Everything found sat outside %g - 1470 Hz. That is below the\n' ..
             'lowest note on any common instrument, so it is more likely to\n' ..
             'be mains hum or a subsonic rumble than a string.')
                :format(T.low_hz)
    end
    if clar5 < 0.6 then
        return 'audio is arriving but NONE OF IT IS PERIODIC',
            ('Best correlation in the last 5 s was %.2f, and it needs 0.60.\n' ..
             'That is what a distorted, very percussive or polyphonic signal\n' ..
             'looks like. Try a clean DI, one string at a time.'):format(clar5)
    end
    return 'the detector found notes but the script rejected them',
        'Most likely the noise floor estimate. Try Advanced -> Noise gate.'
end

function ShowTunerStatus()
    local track = T.track
    local valid = IsTunerTrack(track)
    local rms = GRead(GB + 4)
    local verdict, advice = Verdict()

    reaper.ClearConsole()
    reaper.ShowConsoleMsg(('Lyx Tuner status\n\n' ..
        '>>> %s\n%s%s' ..
        'listening to     : %s\n' ..
        'tuner on         : %s\n' ..
        'track valid      : %s\n' ..
        'fx count         : %s\n' ..
        'rec arm/mon/mode : %s / %s / %s\n' ..
        'rec input        : %s   (+1024 stereo, +2048 multichannel)\n' ..
        'ticked inputs    : %s\n' ..
        '\n' ..
        'JSFX build running: %s   (script expects %s)  %s\n' ..
        'detector state    : %s   (0 idle, 1 scanning, 2 refining)\n' ..
        'analysis rate     : %s Hz,  max period %s\n' ..
        'lowest note sought: %s Hz   (detector is using %s Hz, was told %s)%s\n' ..
        '\n' ..
        'JSFX updates/s   : %.1f   (20-250; silence is faster)\n' ..
        '\n' ..
        'IN THE LAST 5 SECONDS  (so you can play, then run this)\n' ..
        '  loudest input  : %.1f dBFS\n' ..
        '  best clarity   : %.3f   (needs >= 0.6)\n' ..
        '  last good note : %s\n' ..
        '\n' ..
        'RIGHT NOW\n' ..
        'gmem freq        : %.3f Hz\n' ..
        'gmem clarity     : %.3f   (needs >= 0.6)\n' ..
        'input peak       : %.1f dBFS   <- 150 ms decay, so it reads 0 unless\n' ..
        '                                  you are playing at this instant\n' ..
        'gmem rms         : %.5f  (%.1f dBFS)\n' ..
        'noise floor est. : %.1f dBFS\n' ..
        'needs more than  : %.1f dBFS\n' ..
        'noise gate (min) : %.5f  (%.1f dBFS)\n' ..
        'gmem samplerate  : %s\n' ..
        'A4 reference     : %s Hz\n')
        :format(
            verdict,
            advice ~= '' and (advice .. '\n') or '',
            '\n',
            'its own hidden track (follows the active tab)',
            tostring(T.on), tostring(valid),
            valid and reaper.TrackFX_GetCount(track) or 'n/a',
            valid and reaper.GetMediaTrackInfo_Value(track, 'I_RECARM') or '?',
            valid and reaper.GetMediaTrackInfo_Value(track, 'I_RECMON') or '?',
            valid and reaper.GetMediaTrackInfo_Value(track, 'I_RECMODE') or '?',
            valid and reaper.GetMediaTrackInfo_Value(track, 'I_RECINPUT') or '?',
            (function()
                local t = {}
                for i, n in ipairs(T.inputs) do t[i] = n + 1 end
                return #t > 0 and table.concat(t, ', ') or 'none'
            end)(),
            GRead(GB + 5), JSFX_VERSION,
            GRead(GB + 5) == tonumber(JSFX_VERSION) and 'OK'
                or '*** MISMATCH: REAPER is running an old cached build ***',
            GRead(GB + 6), GRead(GB + 7), GRead(GB + 8), T.low_hz,
            GRead(GB + 28), GRead(GB + 29),
            GRead(GB + 28) ~= T.low_hz and '  *** MISMATCH ***' or '',
            T.rate or 0,
            dB(GRead(GB + 14)), GRead(GB + 15),
            GRead(GB + 16) > 0
                and ('%.2f Hz  (%s)'):format(GRead(GB + 16),
                    (FreqToNote(GRead(GB + 16), T.a4)))
                or 'none',
            GRead(GB + 0), GRead(GB + 1),
            dB(T.level),
            rms, dB(rms),
            dB(T.floor),
            20 * math.log(math.max(T.gate, T.floor * 2.5), 10),
            T.gate, 20 * math.log(T.gate, 10),
            GRead(GB + 3), T.a4))
    PrintTrace()
end

-- Opens the detector's own window, which draws the full size readout, and
-- centres it on the REAPER window (REAPER itself remembers wherever the
-- user drags it afterwards).
function OpenBigTuner()
    if T.on then FollowActiveProject() end
    if not T.on then SetTunerEnabled(true) end

    local track = T.track
    if not IsTunerTrack(track) then
        track = EnsureTunerTrack()
    end
    -- Report and clear any error rather than leaving it set: a stale T.err
    -- was being shown by the NEXT thing that looked at it, long after the
    -- problem was fixed, and it also short circuited switching the tuner on.
    if T.err then
        reaper.MB(T.err, box_name, 0)
        T.err = nil
        SetTunerEnabled(false)
        return
    end
    if not track then return end
    local fx = FindTunerFX(track)
    if fx < 0 then return end

    reaper.TrackFX_Show(track, fx, 3)

    if not T.big_placed and reaper.TrackFX_GetFloatingWindow then
        local hwnd = reaper.TrackFX_GetFloatingWindow(track, fx)
        if hwnd and reaper.JS_Window_GetRect then
            local ok, l, t, r, b = reaper.JS_Window_GetRect(hwnd)
            local mok, ml, mt, mr, mb = reaper.JS_Window_GetRect(main_hwnd)
            if ok and mok then
                -- screen coordinates are y-flipped on macOS, so normalise
                local w = math.abs(r - l)
                local h = math.abs(b - t)
                local mw = math.abs(mr - ml)
                local mh = math.abs(mb - mt)
                local x = math.min(ml, mr) + (mw - w) // 2
                local y = math.min(mt, mb) + (mh - h) // 2
                reaper.JS_Window_SetPosition(hwnd, x, y, w, h)
            end
        end
        T.big_placed = true
    end
end

function SetTunerEnabled(enable)
    if enable == T.on then return end
    T.on = enable
    reaper.SetExtState(extname, 'is_on', enable and '1' or '0', true)
    T.hist = {}
    T.last_beat = -1
    T.last_beat_time = reaper.time_precise()
    if enable then
        AttachGmem(GMEM_NAME)
        PublishConfig()
        -- Exactly one detector, one publisher. A track left in THIS project
        -- by a previous session is adopted where it sits rather than
        -- deleted and recreated at the end of the track list: re-using it
        -- is both tidier to look at and one fewer change to the project.
        -- EnsureTunerTrack does the adopting, so the saved track goes
        -- through the same checks (input, arm, hidden) as any other.
        RemoveAllTunerTracks(FindTunerTrack())
        GWrite(GB + 9, 0)
        T.floor = 1
        EnsureTunerTrack()
        if T.err then
            reaper.MB(T.err, box_name, 0)
            T.err = nil
            T.on = false
            reaper.SetExtState(extname, 'is_on', '0', true)
            -- undo everything the failed attempt did, or a half made track
            -- is left in the project with the tuner reporting it is off
            RemoveAllTunerTracks()
        end
        SetDisplay('---', 0, false)
    else
        RemoveAllTunerTracks()
        SetDisplay('---', 0, false)
    end
    is_redraw = true
end

-- Moves the tuner into the project tab the user is looking at now. Lyx: the
-- on/off state is global, so this runs on its own whenever the active tab
-- changes. The big window is reopened if it was showing.
function MoveTunerHere()
    local big_open = IsTunerTrack(T.track) and T.fx and
        reaper.TrackFX_GetFloatingWindow(T.track, FindTunerFX(T.track)) ~= nil
    RemoveAllTunerTracks()
    GWrite(GB + 9, 0)
    T.floor = 1
    T.hist = {}
    EnsureTunerTrack()
    if big_open and not T.err then
        local fx = FindTunerFX(T.track)
        if fx >= 0 then reaper.TrackFX_Show(T.track, fx, 3) end
    end
    if T.err then
        reaper.MB(T.err, box_name, 0)
        T.err = nil
        SetTunerEnabled(false)
    end
    is_redraw = true
end

-- A project saved while the tuner was on carries the hidden track. When the
-- tuner is off that track does nothing, and the user cannot see it in the
-- TCP or the mixer to remove it themselves, so it is ours to clean up.
--
-- The catch is that deleting a track marks the project as modified, and
-- doing that to a project somebody just opened would produce exactly the
-- "save changes?" prompt this script goes out of its way to avoid. So the
-- sweep waits until the project is already modified by something the user
-- did. Then it costs nothing: the prompt was coming anyway, and whenever
-- they do save, the leftover is already gone.
function SweepOrphanTracks()
    local proj = reaper.EnumProjects(-1)
    local cnt = reaper.CountTracks(0)
    -- nothing can have changed since the last look
    if proj == T.swept_proj and cnt == T.swept_cnt then return 0 end
    if reaper.IsProjectDirty(0) == 0 then return 0 end
    T.swept_proj, T.swept_cnt = proj, cnt

    local removed = 0
    for i = cnt - 1, 0, -1 do
        local track = reaper.GetTrack(0, i)
        if track and track ~= T.track and
            reaper.GetSetMediaTrackInfo_String(track,
                'P_EXT:' .. TRACK_TAG, '', false) then
            reaper.PreventUIRefresh(1)
            reaper.DeleteTrack(track)
            reaper.PreventUIRefresh(-1)
            removed = removed + 1
        end
    end
    if removed > 0 then
        reaper.TrackList_AdjustWindows(false)
        T.swept_cnt = reaper.CountTracks(0)
    end
    return removed
end

-- One periodic pass: poll the detector, keep the track healthy, and park
-- the tuner when the user is looking at a different project tab. Lives here
-- rather than inline in Main so it can be driven directly by the tests.
-- Keeps the companion action's toolbar button honest, whatever changed the
-- tuner's state - the fork, the menu, a project tab switch, quitting.
function PublishLive()
    local live = TunerIsLive() and 1 or 0
    if live == T.pub_live then return end
    T.pub_live = live
    reaper.SetExtState(extname, 'is_live', tostring(live), false)
    SetToggleActionState(live)
end

-- The companion toggle action tells us its section and command id the
-- first time it runs, so its toolbar button can be kept in sync no matter
-- how the tuner was actually switched.
function SetToggleActionState(on)
    local id = reaper.GetExtState(extname, 'toggle_action')
    local sec2, cmd2 = id:match('^(%-?%d+) (%-?%d+)$')
    if not sec2 then return end
    sec2, cmd2 = tonumber(sec2), tonumber(cmd2)
    if not cmd2 or cmd2 == 0 then return end
    reaper.SetToggleCommandState(sec2, cmd2, on)
    reaper.RefreshToolbar2(sec2, cmd2)
end

-- The companion toggle action cannot switch the tuner on by itself: the
-- track has to be created by the script that owns it. So it leaves a
-- request here and we service it on the next pass.
function ServiceToggleRequest(time)
    -- tell the toggle action we are alive, and what state we are in
    if time > (T.alive_time or 0) + 0.5 then
        T.alive_time = time
        reaper.SetExtState(extname, 'alive', ('%.3f'):format(time), false)
    end

    PublishLive()

    local req = reaper.GetExtState(extname, 'request')
    if req == '' then return end
    reaper.SetExtState(extname, 'request', '', false)

    if req == 'on' then
        if not T.on then SetTunerEnabled(true) end
    elseif req == 'off' then
        if T.on then SetTunerEnabled(false) end
    else
        ToggleTuner()
    end
    PublishLive()
end

-- ---------------------------------------------------------------------------
-- Analog needle motion. A real meter needle has mass on a spring: it glides
-- to the new reading, overshoots a touch and settles, every frame, instead of
-- hopping once per detector reading. O.speed sets how stiff the spring is.
-- ---------------------------------------------------------------------------
local NEEDLE_DAMPING = 0.55   -- < 1 = slight overshoot, like a VU meter

function NeedleTick(time)
    local dt = time - (T.phys_t or time)
    T.phys_t = time
    if dt <= 0 then return end
    if dt > 0.1 then dt = 0.1 end            -- after a stall, do not fling it
    local target = T.disp or 0
    local pos = T.needle_pos or target
    local vel = T.needle_vel or 0
    -- 5% = 0.5 Hz (heavy) .. 100% = 4.9 Hz; 25% is the old 5%
    local w = 2 * math.pi * (0.3 + 4.6 * O.speed)
    local n = math.ceil(dt / 0.004)
    local h = dt / n
    for _ = 1, n do
        local acc = w * w * (target - pos) - 2 * NEEDLE_DAMPING * w * vel
        vel = vel + acc * h
        pos = pos + vel * h
    end
    if math.abs(target - pos) < 0.01 and math.abs(vel) < 0.05 then
        pos, vel = target, 0
    end
    T.needle_pos, T.needle_vel = pos, vel

    -- In tune for O.lock seconds in a row: the note turns the in-tune colour
    -- and the needle glows. The glow fades in over a quarter of a second.
    local glow = 0
    if T.on and T.has_pitch and T.settled and T.in_tune and T.tune_since then
        local held = time - T.tune_since - O.lock
        if held >= 0 then glow = math.min(1, held / 0.25) end
    end
    if glow ~= T.glow then
        T.glow = glow
        GWrite(GB + 34, glow)
        is_redraw = true
    end

    local step = T.disp_step or 0.5
    if math.abs(pos - (T.needle_drawn or 1e9)) >= step then
        T.needle_drawn = pos
        is_redraw = true
    end
end

function TunerTick()
    local time = reaper.time_precise()
    NeedleTick(time)

    ServiceToggleRequest(time)

    if T.on then FollowActiveProject() end

    if T.on and time > T.poll_time + 0.02 then
        T.poll_time = time
        ReadTuner()
    end

    if time <= T.check_time + 1 then return end
    T.check_time = time

    if LyxThemeChanged() then
        PublishConfig()
        is_redraw = true
    end

    if not T.on then
        SweepOrphanTracks()
        return
    end

    -- Re-assert the settings the detector needs. They are written when they
    -- change, but a single lost write would leave the detector analysing a
    -- different range from the one the menu says, which is invisible unless
    -- you go looking.
    PublishConfig()

    if not IsTunerTrack(T.track) then
        EnsureTunerTrack()
        if T.err then
            reaper.MB(T.err, box_name, 0)
            T.err = nil
            SetTunerEnabled(false)
            return
        end
    end
    MaintainTunerTrack()
end

-- Lyx: the tuner is global. When the user switches to another project tab
-- (or the tuner's tab was closed), the hidden track moves with them.
function FollowActiveProject()
    if T.on and T.proj ~= nil and reaper.EnumProjects(-1) ~= T.proj then
        MoveTunerHere()
    end
end

-- What the hover tooltip says. Worth a little care: the hidden track is
-- deliberately not re-armed behind the user's back, so if they un-arm
-- everything the tuner goes quiet and this is where they find out why.
function TunerTooltip()
    if T.on then
        local track = T.track
        if IsTunerTrack(track)
            and reaper.GetMediaTrackInfo_Value(track, 'I_RECARM') ~= 1 then
            return 'Tuner track is not record armed - switch the tuner off \z
                and on to fix it'
        end
    end
    return 'Toggle tuner (right click for settings)'
end

function ToggleTuner()
    SetTunerEnabled(not T.on)
end

-- Guards against NaN reaching the reference pitch, which would otherwise
-- survive the range check (every comparison against NaN is false) and then
-- crash FreqToNote on the next detected note.
function SetReferencePitch(a4)
    if type(a4) ~= 'number' or a4 ~= a4 then return end
    T.a4 = math.max(380, math.min(500, a4))
    reaper.SetExtState(extname, 'a4_ref', T.a4, true)
    T.hist = {}
    is_redraw = true
end

function SetTunerGate(gate)
    AttachGmem(GMEM_NAME)
    T.gate = gate
    reaper.SetExtState(extname, 'gate', gate, true)
    GWrite(GB + 10, gate)
    T.hist = {}
    is_redraw = true
end

-- One time reset of the reference pitch to 440 Hz. Anything the user sets
-- from here on is remembered as usual.
if reaper.GetExtState(extname, 'a4_reset') == '1' then
    T.a4 = tonumber(reaper.GetExtState(extname, 'a4_ref')) or 440
    if T.a4 ~= T.a4 or T.a4 < 380 or T.a4 > 500 then T.a4 = 440 end
else
    reaper.SetExtState(extname, 'a4_ref', 440, true)
    reaper.SetExtState(extname, 'a4_reset', '1', true)
end

PublishConfig()

function GetTransportScale()
    local _, new_dpi = reaper.ThemeLayout_GetLayout('trans', -3)
    local _, layout = reaper.ThemeLayout_GetLayout('trans', -1)
    local scale = tonumber(new_dpi) / 256
    if type(layout) == 'string' and not attach_window_title then
        local layout_scale = tonumber(layout:match('^(%d+)%%'))
        if layout_scale then scale = scale * layout_scale / 100 end
    end
    return is_macos and 1 or scale, scale
end

function Scale(value, scale)
    if not tonumber(value) then return value end
    return math.floor(value * scale + 0.5)
end

local measure_scale, draw_scale = GetTransportScale()
-- Smallest size the box is allowed to have (width and height in pixels)
local min_box_size = Scale(12, measure_scale)

-------------------------------- FUNCTIONS -----------------------------------

AttachGmem(MOUSE_GMEM)
local mouse_pos_state = reaper.gmem_read(0)

local function GetMousePosition()
    AttachGmem(MOUSE_GMEM)
    local global_state = reaper.gmem_read(0)
    if global_state > mouse_pos_state then
        mouse_pos_state = global_state
        local mx, my = reaper.gmem_read(1), reaper.gmem_read(2)
        if mx % 1 ~= 0 or my % 1 ~= 0 then
            mx, my = reaper.GetMousePosition()
        end
        return mx // 1, my // 1
    else
        mouse_pos_state = mouse_pos_state + 1
        local x, y = reaper.GetMousePosition()
        reaper.gmem_write(0, mouse_pos_state)
        reaper.gmem_write(1, x)
        reaper.gmem_write(2, y)
        return x, y
    end
end

function EscapeString(str)
    local function EscapeChar(char)
        if char == ',' then return '\\,' end
        if char == ':' then return '\\:' end
        if char == '{' then return '\\[' end
        if char == '}' then return '\\]' end
        if char == '\\' then return '\\&' end
    end
    return str:gsub('[,:{}\\]', EscapeChar)
end

function UnEscapeString(str)
    local function UnEscapeChar(char)
        if char == ',' then return ',' end
        if char == ':' then return ':' end
        if char == '[' then return '{' end
        if char == ']' then return '}' end
        if char == '&' then return '\\' end
    end
    return str:gsub('\\([,:%[%]&])', UnEscapeChar)
end

function Serialize(value, add_newlines)
    local value_type = type(value)
    if value_type == 'string' then return 's:' .. EscapeString(value) end
    if value_type == 'number' then return 'n:' .. value end
    if value_type == 'boolean' then return 'b:' .. (value and 1 or 0) end
    if value_type == 'table' then
        local value_str = 't:{'
        local has_elems = false
        for k, elem in pairs(value) do
            local key = k  -- loop variables are read-only in newer Lua
            if type(elem) ~= 'function' then
                -- Avoid adding protected elements that start with underscore
                local is_str_key = type(key) == 'string'
                if not is_str_key or key:sub(1, 1) ~= '_' then
                    if is_str_key then key = EscapeString(key) end
                    if not has_elems and add_newlines then
                        value_str = value_str .. '\n'
                    end
                    local entry = Serialize(elem, add_newlines)
                    value_str = value_str .. key .. ':' .. entry .. ','
                    if add_newlines then value_str = value_str .. '\n' end
                    has_elems = true
                end
            end
        end
        if has_elems then
            value_str = value_str:sub(1, -2)
            if add_newlines then value_str = value_str .. '\n' end
        end
        return value_str .. '}'
    end
    return ''
end

function Deserialize(value_str)
    local value_type, payload = value_str:sub(1, 1), value_str:sub(3)
    if value_type == 's' then return UnEscapeString(payload) end
    if value_type == 'n' then return tonumber(payload) end
    if value_type == 'b' then return payload == '1' end
    if value_type == 't' then
        local matches = {}
        local m = 0

        local function AddMatch(table_str)
            m = m + 1
            local match = {}
            local i = 1
            for value in (table_str .. ','):gmatch('(.-[^\\]),\r?\n?') do
                match[i] = value
                i = i + 1
            end
            matches[m] = match
            return m
        end

        local _, bracket_cnt = payload:gsub('{', '')
        for _ = 1, bracket_cnt do
            payload = payload:gsub('{\r?\n?([^{}]*)\r?\n?}', AddMatch, 1)
        end

        local function AssembleTable(match)
            local ret = {}
            for _, elem in ipairs(match) do
                local key, value = elem:match('^(.-[^\\]):(.-)$')
                key = tonumber(key) or UnEscapeString(key)
                if value:sub(1, 1) == 't' then
                    local n = tonumber(value:match('^t:(.-)$'))
                    ret[key] = AssembleTable(matches[n])
                else
                    ret[key] = Deserialize(value)
                end
            end
            return ret
        end
        return AssembleTable(matches[m])
    end
end

function ExtSave(key, value, is_temporary)
    if value == nil then
        reaper.DeleteExtState(extname, key, not is_temporary)
        return
    end
    local value_str = Serialize(value)
    if not value_str then return end
    reaper.SetExtState(extname, key, value_str, not is_temporary)
end

function ExtLoad(key, default)
    local value = default
    local value_str = reaper.GetExtState(extname, key)
    if value_str ~= '' then value = Deserialize(value_str) end
    return value
end

function GetStartupHookCommandID(no_register)
    -- Note: Startup hook commands have to be in the main section
    local _, script_file, section, cmd_id = reaper.get_action_context()
    if section == 0 then
        -- Save command name when main section script is run first
        local cmd_name = '_' .. reaper.ReverseNamedCommandLookup(cmd_id)
        reaper.SetExtState(extname, 'hook_cmd_name', cmd_name, true)
    else
        -- Look for saved command name by main section script
        local cmd_name = reaper.GetExtState(extname, 'hook_cmd_name')
        cmd_id = reaper.NamedCommandLookup(cmd_name)
        if cmd_id == 0 and no_register then return 0 end
        if cmd_id == 0 then
            -- Add the script to main section (to get cmd id)
            cmd_id = reaper.AddRemoveReaScript(true, 0, script_file, true)
            if cmd_id ~= 0 then
                -- Save command name to avoid adding script on next run
                cmd_name = '_' .. reaper.ReverseNamedCommandLookup(cmd_id)
                reaper.SetExtState(extname, 'hook_cmd_name', cmd_name, true)
            end
        end
    end
    return cmd_id
end

-- read_only: just report, never touch the action list (menu building)
function IsStartupHookEnabled(opt_cmd_id, read_only)
    local res_path = reaper.GetResourcePath()
    local startup_path = ConcatPath(res_path, 'Scripts', '__startup.lua')
    local cmd_id = opt_cmd_id or GetStartupHookCommandID(read_only)
    if cmd_id == 0 then return false end
    local cmd_name = reaper.ReverseNamedCommandLookup(cmd_id)

    if reaper.file_exists(startup_path) then
        -- Read content of __startup.lua
        local startup_file = io.open(startup_path, 'r')
        if not startup_file then return false end
        local content = startup_file:read('*a')
        startup_file:close()

        -- Find line that contains command id (also next line if available)
        local pattern = '[^\n]+' .. cmd_name .. '\'?\n?[^\n]+'
        local s, e = content:find(pattern)

        -- Check if line exists and whether it is commented out
        if s and e then
            local hook = content:sub(s, e)
            local comment = hook:match('[^\n]*%-%-[^\n]*reaper%.Main_OnCommand')
            if not comment then return true end
        end
    end
    return false
end

function SetStartupHookEnabled(is_enabled, comment, var_name)
    local res_path = reaper.GetResourcePath()
    local startup_path = ConcatPath(res_path, 'Scripts', '__startup.lua')
    local cmd_id = GetStartupHookCommandID()
    local cmd_name = reaper.ReverseNamedCommandLookup(cmd_id)

    local content = ''
    local hook_exists = false

    -- Check startup script for existing hook
    if reaper.file_exists(startup_path) then
        local startup_file = io.open(startup_path, 'r')
        if not startup_file then return end
        content = startup_file:read('*a')
        startup_file:close()

        -- Find line that contains command id (also next line if available)
        local pattern = '[^\n]+' .. cmd_name .. '\'?\n?[^\n]+'
        local s, e = content:find(pattern)

        if s and e then
            -- Add/remove comment from existing startup hook
            local hook = content:sub(s, e)
            local repl = (is_enabled and '' or '-- ') .. 'reaper.Main_OnCommand'
            hook = hook:gsub('[^\n]*reaper%.Main_OnCommand', repl, 1)
            content = content:sub(1, s - 1) .. hook .. content:sub(e + 1)

            -- Write changes to file
            local new_startup_file = io.open(startup_path, 'w')
            if not new_startup_file then return end
            new_startup_file:write(content)
            new_startup_file:close()

            hook_exists = true
        end
    end

    -- Create startup hook
    if is_enabled and not hook_exists then
        comment = comment and '-- ' .. comment .. '\n' or ''
        var_name = var_name or 'cmd_name'
        local hook = '%slocal %s = \'_%s\'\nreaper.\z
            Main_OnCommand(reaper.NamedCommandLookup(%s), 0)\n\n'
        hook = hook:format(comment, var_name, cmd_name, var_name)
        local startup_file = io.open(startup_path, 'w')
        if not startup_file then return end
        startup_file:write(hook .. content)
        startup_file:close()
    end
end

local function ParseIni(content)
    local t = {}
    for raw in content:gmatch('[^\r\n]+') do
        local line = raw:match('^%s*(.-)%s*$')
        if line ~= '' and line:sub(1, 1) ~= ';' and line:sub(1, 1) ~= '#' then
            local key, value = line:match('^([^=]+)%s*=%s*(.*)$')
            if key and value then
                local value_num = not key:match('_color$') and tonumber(value)
                t[key:match('^%s*(.-)%s*$')] = value_num or value
            end
        end
    end
    return t
end

function PrintIni()
    local theme_settings = ExtLoad('theme_settings', {})
    local theme_key = GetThemeKey(prev_color_theme)
    local settings = theme_settings[theme_key]
    if settings then
        local sorted_settings = {}
        for k, v in pairs(settings) do
            sorted_settings[#sorted_settings + 1] = {key = k, value = v}
        end
        local function SortByName(t, key)
            local function Format(d) return ('%03d%s'):format(#d, d) end
            local function Compare(a, b)
                local ak, bk = tostring(a[key]), tostring(b[key])
                local ac, bc = ak:find('_color') ~= nil,
                    bk:find('_color') ~= nil
                if ac ~= bc then return bc end
                return ak:gsub('%d+', Format) < bk:gsub('%d+', Format)
            end
            table.sort(t, Compare)
        end
        SortByName(sorted_settings, 'key')

        reaper.ClearConsole()
        reaper.ShowConsoleMsg(box_id .. '.ini:\n\n')
        for _, entry in ipairs(sorted_settings) do
            reaper.ShowConsoleMsg(entry.key .. '=' .. entry.value .. '\n')
        end
    else
        reaper.ShowConsoleMsg('No saved settings')
    end
end

function LoadIntegratedSettings(theme_path, other_box_name)
    local file_name = (other_box_name and other_box_name:lower() or box_id) .. '.ini'
    if not theme_path:lower():match('%.reaperthemezip$') then
        -- Read theme file to get image resource path
        local theme_file = io.open(theme_path, 'r')
        if not theme_file then return nil, 'Could not read theme file' end
        local content = theme_file:read('*a')
        theme_file:close()

        local ui_img
        for line in content:gmatch('[^\r\n]+') do
            ui_img = line:match('^%s*ui_img=(.+)%s*$')
            if ui_img then break end
        end

        if not ui_img then return nil, 'Could not parse theme file' end

        local theme_dir = theme_path:match('^(.+)/')
        if is_windows then theme_dir = theme_path:match('^(.+)\\') end

        if ui_img:lower():match('%.reaperthemezip$') then
            -- Image resource path is a zipped
            theme_path = ConcatPath(theme_dir, ui_img)
        else
            -- Image resource path is unzipped
            local config_path = ConcatPath(theme_dir, ui_img, file_name)
            if not reaper.file_exists(config_path) then return nil, 'No config' end

            local config_file = io.open(config_path, 'r')
            if not config_file then return nil, 'Could not read config file' end
            content = config_file:read('*a')
            config_file:close()

            local config = ParseIni(content)
            if not next(config) then return nil, 'Empty config' end
            return config
        end
    end

    local zip, err = reaper.JS_Zip_Open(theme_path, 'r', 0)
    if err ~= 0 then return nil, reaper.JS_Zip_ErrorString(err) end

    local count, list = reaper.JS_Zip_ListAllEntries(zip)
    if count < 0 then
        reaper.JS_Zip_Close(theme_path, zip)
        return nil, reaper.JS_Zip_ErrorString(count)
    end

    local found_entry = nil
    for entry in list:gmatch('[^%z]+') do
        if entry:find(file_name, 1, true) then
            found_entry = entry
            break
        end
    end

    if not found_entry then
        reaper.JS_Zip_Close(theme_path, zip)
        return nil, 'Entry not found: ' .. file_name
    end

    local ret = reaper.JS_Zip_Entry_OpenByName(zip, found_entry)
    if ret ~= 0 then
        reaper.JS_Zip_Close(theme_path, zip)
        return nil, reaper.JS_Zip_ErrorString(ret)
    end

    local bytes, content = reaper.JS_Zip_Entry_ExtractToMemory(zip)
    reaper.JS_Zip_Entry_Close(zip)
    reaper.JS_Zip_Close(theme_path, zip)

    if bytes < 0 then
        return nil, reaper.JS_Zip_ErrorString(bytes)
    end

    local config = ParseIni(content)
    if not next(config) then return nil, 'Empty config' end
    return config
end

function SetThemeIntegration(value)
    local i = 0
    local param_pattern = box_id
    repeat
        local ret, desc, val, def, min, max = reaper.ThemeLayout_GetParameter(i)
        if desc and desc:lower():match(param_pattern) then
            if val ~= value and def == 0 and min == 0 and max == 1 then
                reaper.ThemeLayout_SetParameter(i, value, false)
                reaper.ThemeLayout_RefreshAll()
            end
            break
        end
        i = i + 1
    until not ret
end

function GetThemeKey(path)
    if not path then path = reaper.GetLastColorThemeFile() or '' end
    if path == '' then
        -- Note: Theme path can be empty in new REAPER installations?
        local reaper_version = reaper.GetAppVersion():match('[%d]+')
        return ('ColorThemes/Default_%s.0'):format(reaper_version)
    end
    -- Use relative path if inside resource directory
    local resource_dir = reaper.GetResourcePath()
    -- Note: Using find to suppress matching special characters in path
    local _, end_idx = path:find(resource_dir, 0, true)
    if end_idx then path = path:sub(end_idx + 2) end

    -- Replace windows path separator with unix (make cross-platform)
    if is_windows then path = path:gsub('\\', '/') end
    -- Remove file extension
    path = path:gsub('%.([^./]+)$', '')
    return path
end

function GetThemeFromKey(key)
    local theme_name = key:match('([^/]+)$')
    if is_windows then key = key:gsub('/', '\\') end

    local function FindInDir(dir)
        local fallback = nil
        local i = 0
        repeat
            local file_name = reaper.EnumerateFiles(dir, i)
            if file_name then
                local file_name_no_ext = file_name:gsub('%.([^./\\]+)$', '')
                if file_name_no_ext == theme_name then
                    if file_name:lower():match('%.reaperthemezip$') then
                        return ConcatPath(dir, file_name)
                    else
                        fallback = ConcatPath(dir, file_name)
                    end
                end
            end
            i = i + 1
        until not file_name
        return fallback
    end

    local dir = is_windows and key:match('^(.+)\\') or key:match('^(.+)/')
    local result = FindInDir(dir)
    if result then return result end

    key = ConcatPath(reaper.GetResourcePath(), key)
    dir = is_windows and key:match('^(.+)\\') or key:match('^(.+)/')
    return FindInDir(dir)
end

function LoadThemeSettings(theme_path, only_appeareance)
    local theme_settings = ExtLoad('theme_settings', {})
    local theme_key = GetThemeKey(theme_path)
    local settings = theme_settings[theme_key]

    if not settings then
        local theme_file = GetThemeFromKey(theme_key)
        if theme_file then
            local integrated_settings = LoadIntegratedSettings(theme_file)
            if integrated_settings then
                settings = integrated_settings
                SetEditMode(false)
            end
        end
    end

    local has_settings = settings ~= nil
    settings = settings or {}

    local function SafeColor(v)
        -- a non integer here (an old serialised setting, a hand edited ini)
        -- would make ('%X'):format throw rather than just be ignored
        if type(v) == 'number' then
            if v ~= v or v % 1 ~= 0 or v < 0 then return nil end
            v = ('%X'):format(v)
        end
        if type(v) ~= 'string' then return nil end
        v = v:gsub('^#', '')
        if #v > 8 or not tonumber(v, 16) then return nil end
        return v
    end

    user_bg_color = SafeColor(settings.bg_color)
    user_text_color = SafeColor(settings.text_color)
    user_border_color = SafeColor(settings.border_color)
    user_swing_color = SafeColor(settings.swing_color)
    user_adaptive_color = SafeColor(settings.adaptive_color)
    user_font_height = settings.font_height
    user_font_family = settings.font_family
    user_font_weight = settings.font_weight
    user_font_yoffs = settings.font_yoffs
    user_corner_radius = settings.corner_radius
    user_snap_size = settings.snap_size
    user_snap_on_color = SafeColor(settings.snap_on_color)
    user_snap_off_color = SafeColor(settings.snap_off_color)
    user_snap_sep_color = SafeColor(settings.snap_sep_color)
    user_zone_color = SafeColor(settings.zone_color)

    if settings.draw_scale and settings.draw_scale ~= draw_scale then
        local scale_factor = draw_scale / settings.draw_scale
        user_font_height = Scale(user_font_height, scale_factor)
        user_font_yoffs = Scale(user_font_yoffs, scale_factor)
        user_corner_radius = Scale(user_corner_radius, scale_factor)
        user_snap_size = Scale(user_snap_size, scale_factor)
    end

    if only_appeareance then return has_settings end

    if attach_window_title then
        settings = ExtLoad('attach_settings') or settings
    end

    local function SafeNumber(v)
        if type(v) ~= 'number' or v ~= v then return nil end
        return v
    end

    attach_x = SafeNumber(settings.attach_x)
    attach_mode = SafeNumber(settings.attach_mode)
    attach_center_x = SafeNumber(settings.attach_center_x)
    attach_center_mode = SafeNumber(settings.attach_center_mode)

    local new_box_x = SafeNumber(settings.box_x)
    local new_box_y = SafeNumber(settings.box_y)
    local new_box_w = SafeNumber(settings.box_w)
    local new_box_h = SafeNumber(settings.box_h)
    if not new_box_x or not new_box_y or not new_box_w or not new_box_h or
        new_box_w <= 0 or new_box_h <= 0 then
        return false
    end

    local saved_measure_scale = SafeNumber(settings.measure_scale)
    if saved_measure_scale and saved_measure_scale > 0 and
        saved_measure_scale ~= measure_scale then
        local scale_factor = measure_scale / saved_measure_scale
        new_box_x = Scale(new_box_x, scale_factor)
        new_box_y = Scale(new_box_y, scale_factor)
        new_box_w = Scale(new_box_w, scale_factor)
        new_box_h = Scale(new_box_h, scale_factor)
        attach_x = Scale(attach_x, scale_factor)
        attach_center_x = Scale(attach_center_x, scale_factor)
    end

    if attach_x or attach_center_x then
        local attached_box_x = GetAttachPosition()
        if attached_box_x then
            new_box_x = attached_box_x
        else
            -- The rectangle is still usable even if its relative anchor is
            -- incomplete. Keep its exact position and stop tracking the bad
            -- anchor instead of rebuilding a toolbar-sized default box.
            attach_x, attach_mode = nil, nil
            attach_center_x, attach_center_mode = nil, nil
        end
    end
    SetBoxCoords(new_box_x, new_box_y, new_box_w, new_box_h)
    return has_settings or attach_window_title ~= nil
end

function SaveThemeSettings(theme_path)
    local settings = {
        box_x = box_x,
        box_y = box_y,
        box_w = box_w,
        box_h = box_h,
        attach_x = attach_x,
        attach_mode = attach_mode,
        attach_center_x = attach_center_x,
        attach_center_mode = attach_center_mode,
        bg_color = user_bg_color,
        text_color = user_text_color,
        border_color = user_border_color,
        swing_color = user_swing_color,
        adaptive_color = user_adaptive_color,
        font_height = user_font_height,
        font_family = user_font_family,
        font_weight = user_font_weight,
        font_yoffs = user_font_yoffs,
        corner_radius = user_corner_radius,
        snap_size = user_snap_size,
        snap_on_color = user_snap_on_color,
        snap_off_color = user_snap_off_color,
        snap_sep_color = user_snap_sep_color,
        zone_color = user_zone_color,
        draw_scale = draw_scale,
        measure_scale = measure_scale,
    }

    local theme_settings = ExtLoad('theme_settings', {})
    local theme_key = GetThemeKey(theme_path)

    if attach_window_title then
        local attach_settings = {
            box_x = box_x,
            box_y = box_y,
            box_w = box_w,
            box_h = box_h,
            attach_x = attach_x,
            attach_mode = attach_mode,
            measure_scale = measure_scale,
        }
        ExtSave('attach_settings', attach_settings)

        local prev_settings = theme_settings[theme_key]
        if prev_settings then
            for key in pairs(attach_settings) do
                settings[key] = prev_settings[key]
            end
        end
    end

    theme_settings[theme_key] = settings
    ExtSave('theme_settings', theme_settings)
end

function GetThemeColor(key, flag)
    local color = reaper.GetThemeColor(key, flag or 0)
    if is_windows then
        local r, g, b = reaper.ColorFromNative(color)
        color = r * 65536 + g * 256 + b
    end
    return color
end

function RGBAToHex(r, g, b, a)
    local int_color = r * 65536 + g * 256 + b
    if not a or a == 255 then return ('#%06x'):format(int_color) end
    return ('#%06x%02x'):format(int_color, a)
end

function IntToHex(int_color)
    local r, g, b = reaper.ColorFromNative(int_color)
    return RGBAToHex(r, g, b)
end

function TintIntColor(color, factor)
    local a = color & 0xFF000000
    local r = (color & 0xFF0000) >> 16
    local g = (color & 0x00FF00) >> 8
    local b = (color & 0x0000FF)

    r = (r * factor) // 1
    g = (g * factor) // 1
    b = (b * factor) // 1

    r = r < 0 and 0 or r > 255 and 255 or r
    g = g < 0 and 0 or g > 255 and 255 or g
    b = b < 0 and 0 or b > 255 and 255 or b

    return (r * 65536 + g * 256 + b) | a
end

function InvalidateBoxRect()
    if not box_x then return end
    reaper.JS_Window_InvalidateRect(window_hwnd, box_x, box_y,
        box_x + box_w, box_y + box_h, false)
end

function GetBitmapSize()
    local pixel_ratio = draw_scale / measure_scale
    local bm_w, bm_h = box_w * pixel_ratio, box_h * pixel_ratio
    return math.floor(bm_w), math.floor(bm_h)
end

function ClearBitmap(bm, color)
    -- Note: Clear to transparent avoids artifacts on aliased rect corners
    if is_windows then
        reaper.JS_LICE_Clear(bm, 0x00000000)
    else
        reaper.JS_LICE_Clear(bm, color & 0x00FFFFFF)
    end
end

function DrawRect(bm, color, x, y, w, h, fill, r, a)
    if a == 0 then return end
    fill = fill or 0
    r = r or 0
    a = a or 1

    if not fill or fill == 0 then
        local LICE_RoundRect = reaper.JS_LICE_RoundRect
        for _ = 1, math.max(1, draw_scale) do
            LICE_RoundRect(bm, x, y, w - 1, h - 1, r, color, a, '', true)
            x, y, w, h = x + 1, y + 1, w - 2, h - 2
        end
        return
    end

    if not r or r == 0 then
        -- Body
        reaper.JS_LICE_FillRect(bm, x, y, w, h, color, a, '')
        return
    end

    if h <= 2 * r then r = math.floor(h / 2 - 1) end
    if w <= 2 * r then r = math.floor(w / 2 - 1) end

    -- Top left corner
    local LICE_FillCircle = reaper.JS_LICE_FillCircle
    LICE_FillCircle(bm, x + r, y + r, r, color, a, '', true)
    -- Top right corner
    LICE_FillCircle(bm, x + w - r - 1, y + r, r, color, a, '', true)
    -- Bottom right corner
    LICE_FillCircle(bm, x + w - r - 1, y + h - r - 1, r, color, a, '', true)
    -- Bottom left corner
    LICE_FillCircle(bm, x + r, y + h - r - 1, r, color, a, '', true)
    -- Ends
    reaper.JS_LICE_FillRect(bm, x, y + r, r, h - r * 2, color, a, '')
    reaper.JS_LICE_FillRect(bm, x + w - r, y + r, r, h - r * 2, color, a, '')
    -- Body and sides
    reaper.JS_LICE_FillRect(bm, x + r, y, w - r * 2, h, color, a, '')
end

function DrawBackground(bm, bg_color, w, h, corner_r, a)
    if a == 0 then return end
    if not bg_bitmap then
        bg_bitmap = reaper.JS_LICE_CreateBitmap(true, w, h)
        prev_bg_color = nil
    end

    if bg_color ~= prev_bg_color or corner_r ~= prev_bg_corner_r then
        prev_bg_color = bg_color
        prev_bg_corner_r = corner_r
        prev_snap_color = nil
        ClearBitmap(bg_bitmap, bg_color)
        DrawRect(bg_bitmap, bg_color, 0, 0, w, h, true, corner_r)
    end
    reaper.JS_LICE_Blit(bm, 0, 0, bg_bitmap, 0, 0, w, h, a, 'COPY')
end


-- ---------------------------------------------------------------------------
-- Tuning fork icon
--
-- Rasterised from its SVG path (8x8 viewBox) rather than approximated with
-- primitives, so it stays true at any size:
--   M2 0h1v4q1.5 2 3 0V0h1v4c0 3-5 3-5 0m2 1h1v3H4
-- The coverage mask is built once per pixel size and cached, so drawing is
-- just a walk over a precomputed list.
-- ---------------------------------------------------------------------------

local fork_polys
local fork_cache = {}
local fork_cache_n = 0

local function BuildForkPolys()
    local outer = {{2, 0}, {3, 0}, {3, 4}}
    for i = 1, 16 do                       -- q1.5 2 3 0
        local t = i / 16
        local a = 1 - t
        outer[#outer + 1] = {a * a * 3 + 2 * a * t * 4.5 + t * t * 6,
                             a * a * 4 + 2 * a * t * 6 + t * t * 4}
    end
    outer[#outer + 1] = {6, 0}             -- V0
    outer[#outer + 1] = {7, 0}             -- h1
    outer[#outer + 1] = {7, 4}             -- v4
    for i = 1, 16 do                       -- c0 3 -5 3 -5 0
        local t = i / 16
        local a = 1 - t
        outer[#outer + 1] = {
            a ^ 3 * 7 + 3 * a * a * t * 7 + 3 * a * t * t * 2 + t ^ 3 * 2,
            a ^ 3 * 4 + 3 * a * a * t * 7 + 3 * a * t * t * 7 + t ^ 3 * 4}
    end
    fork_polys = {outer, {{4, 5}, {5, 5}, {5, 8}, {4, 8}}}
end

local function PointInPoly(poly, x, y)
    local inside = false
    local n = #poly
    local j = n
    for i = 1, n do
        local xi, yi = poly[i][1], poly[i][2]
        local xj, yj = poly[j][1], poly[j][2]
        if (yi > y) ~= (yj > y) and
            x < (xj - xi) * (y - yi) / (yj - yi) + xi then
            inside = not inside
        end
        j = i
    end
    return inside
end

-- Grid fitting, the way a font rasteriser hints a glyph. Every straight
-- edge of the fork sits on a whole unit of the 8 unit grid (both prongs and
-- the stem are exactly one unit wide), so snapping those unit boundaries to
-- whole pixels puts every vertical edge on a pixel boundary at ANY size.
-- Only the bowl of the U is left to antialiasing.
local function SnapUnit(v, u)
    local k = math.floor(v)
    if k >= 8 then return math.floor(8 * u + 0.5) end
    local a = math.floor(k * u + 0.5)
    local b = math.floor((k + 1) * u + 0.5)
    return a + (b - a) * (v - k)
end

-- Scanline rasteriser. Coverage is exact horizontally and 4x supersampled
-- vertically, which is both better looking and roughly 60x cheaper than
-- point sampling every pixel (that cost 66 ms for a 52 px icon, a visible
-- hitch every time the box was resized).
local SUB = 4

local function ScanSpans(poly, y, out)
    local n = #poly
    local xs = {}
    local j = n
    for i = 1, n do
        local x1, y1 = poly[i][1], poly[i][2]
        local x2, y2 = poly[j][1], poly[j][2]
        if (y1 > y) ~= (y2 > y) then
            xs[#xs + 1] = x1 + (y - y1) * (x2 - x1) / (y2 - y1)
        end
        j = i
    end
    table.sort(xs)
    for i = 1, #xs - 1, 2 do
        if xs[i + 1] > xs[i] then out[#out + 1] = {xs[i], xs[i + 1]} end
    end
end

function GetForkMask(size)
    if fork_cache[size] then return fork_cache[size] end
    if not fork_polys then BuildForkPolys() end
    if fork_cache_n > 8 then fork_cache = {}; fork_cache_n = 0 end

    -- grid fit the outline into pixel space
    local u = size / 8
    local hinted = {}
    for i = 1, #fork_polys do
        local src, dst = fork_polys[i], {}
        for j = 1, #src do
            dst[j] = {SnapUnit(src[j][1], u), SnapUnit(src[j][2], u)}
        end
        hinted[i] = dst
    end

    local cov = {}
    for sy = 0, size * SUB - 1 do
        local y = (sy + 0.5) / SUB
        local row = math.floor(y) * size

        -- spans of each subpath, then their union (the stem overlaps the
        -- bowl of the U, so an even-odd merge would cancel it out)
        local spans = {}
        ScanSpans(hinted[1], y, spans)
        ScanSpans(hinted[2], y, spans)
        table.sort(spans, function(a, b) return a[1] < b[1] end)

        local ca, cb
        for i = 1, #spans + 1 do
            local sp = spans[i]
            if sp and ca and sp[1] <= cb then
                if sp[2] > cb then cb = sp[2] end
            else
                if ca then
                    -- accumulate exact horizontal coverage
                    local px = math.floor(ca)
                    while px < cb do
                        local a = ca > px and ca or px
                        local b = cb < px + 1 and cb or px + 1
                        if b > a and px >= 0 and px < size then
                            local k = row + px
                            cov[k] = (cov[k] or 0) + (b - a) / SUB
                        end
                        px = px + 1
                    end
                end
                if sp then ca, cb = sp[1], sp[2] end
            end
        end
    end

    -- Merge the coverage grid into rectangles. The glyph is mostly solid
    -- bars - two prongs, the bowl of the U and the stem - so filling it a
    -- pixel at a time meant ~120 LICE calls per redraw at a 26 px box and
    -- ~400 at 200% theme scaling, on every frame a ringing string moved the
    -- readout. Runs are merged horizontally and then vertically, which
    -- brings the same picture down to a dozen or so rectangles.
    --
    -- Coverage is quantised to 1/255 first, because that is the resolution
    -- the alpha channel has anyway: it costs nothing visually and lets
    -- neighbouring pixels of a solid area compare equal.
    local q = {}
    for k, v in pairs(cov) do
        if v > 0.002 then
            q[k] = math.floor((v < 1 and v or 1) * 255 + 0.5)
        end
    end

    local runs = {}
    for y = 0, size - 1 do
        local row = y * size
        local x = 0
        while x < size do
            local v = q[row + x]
            if v then
                local w = 1
                while x + w < size and q[row + x + w] == v do w = w + 1 end
                runs[#runs + 1] = {x, y, w, 1, v}
                x = x + w
            else
                x = x + 1
            end
        end
    end

    local mask, open = {}, {}
    for i = 1, #runs do
        local r = runs[i]
        local key = r[1] * 1000000 + r[3] * 1000 + r[5]
        local prev = open[key]
        if prev and prev[2] + prev[4] == r[2] then
            prev[4] = prev[4] + 1
        else
            mask[#mask + 1] = r
            open[key] = r
        end
    end

    fork_cache[size] = mask
    fork_cache_n = fork_cache_n + 1
    return mask
end

-- cx, cy is where the visible glyph should be centred
function DrawTuningFork(bm, color, cx, cy, size, a)
    if a == 0 or size < 6 then return end
    local u = size / 8
    local mask = GetForkMask(size)
    -- offsets are whole pixels so the hinted edges stay on the grid
    local ox = math.floor(cx - (SnapUnit(2, u) + SnapUnit(7, u)) / 2 + 0.5)
    local oy = math.floor(cy - size / 2 + 0.5)
    local FillRect = reaper.JS_LICE_FillRect
    for i = 1, #mask do
        local p = mask[i]
        FillRect(bm, ox + p[1], oy + p[2], p[3], p[4], color,
            a * p[5] / 255, '')
    end
end

-- ---------------------------------------------------------------------------
-- Fixed cell text metrics
--
-- Real tuners never let the note move. Every glyph gets a cell of a fixed
-- width, measured once per font change, so the cluster width does not depend
-- on what is being displayed.
-- ---------------------------------------------------------------------------

glyph = glyph or {}

function MeasureGlyphs()
    local g = {}
    local digit_w = 0
    for i = 0, 9 do
        local c = tostring(i)
        g[c] = gfx.measurestr(c)
        if g[c] > digit_w then digit_w = g[c] end
    end
    local letter_w = 0
    for c in ('ABCDEFG'):gmatch('.') do
        g[c] = gfx.measurestr(c)
        if g[c] > letter_w then letter_w = g[c] end
    end
    for _, c in ipairs({'#', 'b', '-', '+', ' '}) do g[c] = gfx.measurestr(c) end
    g.digit_w = digit_w
    g.letter_w = letter_w
    g.sign_w = math.max(g['-'], g['+'])
    g.sharp_w = g['#']
    -- widest possible note is letter + sharp; the octave is not shown
    g.note_w = letter_w + math.max(g.sharp_w, g['b'])
    glyph = g
end

-- ---------------------------------------------------------------------------
-- Box colours. Each one is the user's colour for this REAPER theme if set,
-- else the Lyx theme, else the original default. Used by the drawing code
-- and by the settings window, so both always agree.
-- ---------------------------------------------------------------------------
-- 'RRGGBB' or 'AARRGGBB' -> rgb, alpha 0..1
function ParseUserColor(hex)
    local v = hex and tonumber(hex, 16)
    if not v then return nil end
    if #hex > 6 then return v & 0xFFFFFF, ((v >> 24) & 0xFF) / 255 end
    return v, 1
end

function FormatUserColor(rgb, a)
    local ai = math.floor((a or 1) * 255 + 0.5)
    if ai >= 255 then return ('%06X'):format(rgb & 0xFFFFFF) end
    return ('%02X%06X'):format(ai, rgb & 0xFFFFFF)
end

-- order = the order shown in the settings window
USER_COLORS = {
    {key = 'bg', label = 'Background',
        get = function() return user_bg_color end,
        set = function(v) user_bg_color = v end},
    {key = 'text', label = 'Note text',
        get = function() return user_text_color end,
        set = function(v) user_text_color = v end},
    {key = 'border', label = 'Border',
        get = function() return user_border_color end,
        set = function(v) user_border_color = v end},
    {key = 'warn', label = 'Needle off pitch',
        get = function() return user_swing_color end,
        set = function(v) user_swing_color = v end},
    {key = 'tune', label = 'In tune',
        get = function() return user_adaptive_color end,
        set = function(v) user_adaptive_color = v end},
    {key = 'tick', label = 'Ruler ticks',
        get = function() return user_snap_sep_color end,
        set = function(v) user_snap_sep_color = v end},
    {key = 'zone', label = 'In-tune zone',
        get = function() return user_zone_color end,
        set = function(v) user_zone_color = v end},
    {key = 'icon_on', label = 'Fork icon on',
        get = function() return user_snap_on_color end,
        set = function(v) user_snap_on_color = v end},
    {key = 'icon_off', label = 'Fork icon off',
        get = function() return user_snap_off_color end,
        set = function(v) user_snap_off_color = v end},
}

function BoxColors()
    local L = LyxColors()
    local tune = L and L.tune or (GetThemeColor('areasel_outline') & 0xFFFFFF)
    local def = {
        bg = {L and L.bg or 0x242424, 1},
        text = {L and L.text or 0xa9a9a9, 1},
        border = {L and L.tick or 0x3a3a3b, 1},
        warn = {L and L.warn or 0xD04A4A, 1},
        tune = {tune, 1},
        tick = {L and L.tick or 0x3a3a3b, 1},
        zone = {tune, 0.3},
        icon_on = {tune, 1},
        icon_off = {L and L.mute or 0x787878, 1},
    }
    local out = {}
    for _, uc in ipairs(USER_COLORS) do
        local rgb, a = ParseUserColor(uc.get())
        local d = def[uc.key]
        out[uc.key] = {c = rgb or d[1], a = a or d[2], user = rgb ~= nil}
    end
    -- these follow whatever "In tune" ended up being
    if not out.zone.user then out.zone.c = out.tune.c end
    if not out.icon_on.user then out.icon_on.c = out.tune.c end
    return out
end

-- ---------------------------------------------------------------------------
-- Analog needle. A flat one colour bar looks digital, so the needle is lit
-- like a thin metal rod: dark at both sides, a bright highlight just left of
-- centre (light from the upper left), a little brighter at the top than at
-- the foot, and a soft shadow cast down and to the right. Every column is
-- weighted by how much of it the needle covers, so it still moves in sub
-- pixel steps.
-- ---------------------------------------------------------------------------
local function ShadeRGB(rgb, k, white)
    local function ch(sh)
        local v = (rgb >> sh) & 0xFF
        v = v * k
        if white and white > 0 then v = v + (255 - v) * white end
        v = math.floor(v + 0.5)
        return v < 0 and 0 or v > 255 and 255 or v
    end
    return (ch(16) << 16) | (ch(8) << 8) | ch(0)
end

-- Soft halo: columns either side of px, fading out with distance, and a
-- little at the top and bottom so it reads as light rather than a stripe.
function DrawGlow(bm, px, y0, y1, radius, rgb, strength)
    local FillRect = reaper.JS_LICE_FillRect
    local A = 0xFF000000
    for x = math.floor(px - radius), math.ceil(px + radius) do
        local d = math.abs((x + 0.5) - px) / radius
        if d < 1 then
            local a = 0.42 * strength * (1 - d) * (1 - d)
            local trim = math.floor((y1 - y0) * 0.12 * d)
            FillRect(bm, x, y0 + trim, 1, y1 - y0 - 2 * trim, rgb | A, a, '')
        end
    end
end

function DrawNeedle(bm, px, y0, y1, width, rgb, alpha, scale)
    local FillRect = reaper.JS_LICE_FillRect
    local A = 0xFF000000
    local half = width / 2
    local left, right = px - half, px + half
    local sh_off = math.max(1, math.floor(scale + 0.5))

    -- shadow: a wide faint one and a tight darker one
    for pass = 1, 2 do
        local grow = pass == 1 and width * 0.6 or 0
        local sa = (pass == 1 and 0.10 or 0.28) * alpha
        local sl, sr = left - grow / 2 + sh_off, right + grow / 2 + sh_off
        for x = math.floor(sl), math.ceil(sr) - 1 do
            local cov = math.min(x + 1, sr) - math.max(x, sl)
            if cov > 0 then
                FillRect(bm, x, y0 + sh_off, 1, y1 - y0, A, sa * cov, '')
            end
        end
    end

    -- body, column by column across the rod, in a few bands down its length
    local bands = 6
    local len = y1 - y0
    for x = math.floor(left), math.ceil(right) - 1 do
        local cov = math.min(x + 1, right) - math.max(x, left)
        if cov > 0 then
            -- position across the rod, -1 (left edge) .. 1 (right edge)
            local u = ((x + 0.5) - px) / half
            u = u < -1 and -1 or u > 1 and 1 or u
            local lit = math.sqrt(math.max(0, 1 - u * u))   -- round profile
            local k = 0.55 + 0.55 * lit
            local spec = math.max(0, 1 - math.abs(u + 0.35) / 0.4) * 0.55
            for i = 0, bands - 1 do
                local ya = y0 + math.floor(len * i / bands + 0.5)
                local yb = y0 + math.floor(len * (i + 1) / bands + 0.5)
                local vk = 1.12 - 0.24 * (i + 0.5) / bands -- brighter on top
                FillRect(bm, x, ya, 1, yb - ya,
                    ShadeRGB(rgb, k * vk, spec) | A, alpha * cov, '')
            end
        end
    end

    -- rounded ends: a short darker cap top and bottom
    local cap = math.max(1, math.floor(scale + 0.5))
    for x = math.floor(left), math.ceil(right) - 1 do
        local cov = math.min(x + 1, right) - math.max(x, left)
        if cov > 0 then
            FillRect(bm, x, y0, 1, cap, ShadeRGB(rgb, 0.6) | A, alpha * cov * 0.6, '')
            FillRect(bm, x, y1 - cap, 1, cap, ShadeRGB(rgb, 0.5) | A,
                alpha * cov * 0.6, '')
        end
    end
end

function DrawBitmap(bm, w, h)
    local alpha = 0xFF000000

    -- ------------------------------------------------------------------
    -- Background and border
    -- ------------------------------------------------------------------
    local L = LyxColors()
    local C = BoxColors()
    local bg_color, bg_alpha = C.bg.c | alpha, C.bg.a

    ClearBitmap(bm, bg_color)

    local corner_radius
    if user_corner_radius then
        corner_radius = math.floor(user_corner_radius)
    else
        -- 5, not 6: 10 px at 200%, which is what the box looks right at
        -- next to REAPER's own transport controls on the stock theme.
        corner_radius = Scale(L and L.rounding and
            math.min(8, L.rounding * 0.8) or 5, draw_scale)
    end
    DrawBackground(bm, bg_color, w, h, corner_radius, bg_alpha)

    local border_color = C.border.user and (C.border.c | alpha)
    if border_color then
        DrawRect(bm, border_color, 0, 0, w, h, false,
            corner_radius, C.border.a)
    end

    local arrow_color, arrow_alpha = C.warn.c | alpha, C.warn.a
    local tune_color = C.tune.c | alpha
    local dim_color = C.tick.c | alpha

    -- ------------------------------------------------------------------
    -- Measure the readout first: the on/off dot is only shown when the
    -- box is wide enough to hold it AND the whole readout comfortably.
    -- ------------------------------------------------------------------
    if not glyph.digit_w then MeasureGlyphs() end

    local _, text_h = gfx.measurestr('E')
    -- the readout needs at least the note plus a short ruler
    local cluster_w = glyph.note_w + Scale(40, draw_scale)
    local m = Scale(2, draw_scale)

    -- Icon geometry. icon_h is the height of the glyph itself; the left
    -- section is sized from the glyph WIDTH plus generous padding, because
    -- the tuning fork is far narrower than the old dot and inherited its
    -- cramped margins otherwise.
    -- Same height rule the Gridbox snap icon uses, so the two sit side by
    -- side at matching weight at any theme scaling.
    local icon_h = user_snap_size
    icon_h = icon_h or h - 2 * math.max(Scale(4, draw_scale), h // 4)
    icon_h = math.max(6, math.floor(icon_h + 0.5))

    local icon_w = icon_h * 5 / 8
    -- Horizontal breathing room only. The vertical padding comes from
    -- icon_h itself (same rule as the Gridbox snap icon), so it is left
    -- alone; this widens the left section by 4 px a side at 100%, 8 at
    -- 200%, and so on.
    local icon_pad = math.max(Scale(7, draw_scale), icon_w * 0.95)
        + Scale(4, draw_scale)
    local left_w = math.floor(icon_w + 2 * icon_pad + 0.5)

    local show_dot = not hide_snap and icon_h > 0 and left_w > 0 and
        left_w + cluster_w + 4 * m <= w
    if not show_dot then left_w = 0 end

    snap_w = left_w * measure_scale / draw_scale
    local right_w = w - left_w

    -- ------------------------------------------------------------------
    -- Left section: on/off dot
    -- ------------------------------------------------------------------
    if show_dot then
        local on_color, on_alpha = C.icon_on.c | alpha, C.icon_on.a
        local off_color, off_alpha = C.icon_off.c | alpha, C.icon_off.a

        local live = TunerIsLive()
        local dot_alpha = live and on_alpha or off_alpha
        local dot_color = live and on_color or off_color
        if prev_is_snap_hovered then
            dot_color = TintIntColor(dot_color, 1.145)
        end

        local sep_m = math.max(Scale(4, draw_scale), h // 14)
        local sep_w = math.max(1, Scale(1, draw_scale))

        DrawTuningFork(bm, dot_color, math.floor((left_w - sep_w) / 2),
            math.floor(h / 2), icon_h, dot_alpha)

        DrawRect(bm, dim_color, left_w - sep_w, sep_m, sep_w, h - 2 * sep_m,
            true, 0, 1)
    end

    -- ------------------------------------------------------------------
    -- Lyx: note | horizontal ruler with a needle | cents
    -- ------------------------------------------------------------------
    local live = TunerIsLive() and T.has_pitch
    local text_color = C.text.c | alpha
    local mute_color = ((L and L.mute) or 0x787878) | alpha

    local text_y = (h - text_h) // 2
    if text_y < 0 then text_y = 0 end
    if is_macos then text_y = text_y + 1 end
    text_y = text_y + (user_font_yoffs or 0)

    local pad = Scale(6, draw_scale)
    local note_w = glyph.note_w + (O.octave and glyph.digit_w + 1 or 0)
    local cents_w = O.show_cents and (glyph.sign_w + 2 * glyph.digit_w) or 0

    local x0 = left_w + pad + note_w + pad
    local x1 = w - pad - (cents_w > 0 and cents_w + pad or 0)
    local show_ruler = x1 - x0 >= Scale(30, draw_scale)
    if not show_ruler then x0, x1 = w, w end

    -- note (or the placeholder) inside its own fixed zone
    local label = T.text
    if live then label = DisplayName(T.text) end
    local zone_x = show_ruler and (left_w + pad) or left_w
    local zone_w = show_ruler and note_w or (w - left_w)
    local lw = gfx.measurestr(label)
    local lx = zone_x + math.max(0, (zone_w - lw) // 2)
    reaper.JS_LICE_SetFontColor(lice_font,
        (live and (T.glow or 0) > 0) and tune_color or text_color)
    reaper.JS_LICE_DrawText(bm, lice_font, label, label:len(), lx, text_y, w, h)

    if not show_ruler then T.disp_step = 1; return end

    -- ruler geometry
    local vpad = math.max(Scale(4, draw_scale), h // 5)
    local top, rh = vpad, h - 2 * vpad
    if rh < 4 then top, rh = 1, h - 2 end
    local rw = x1 - x0
    local mid = x0 + rw / 2
    local half = rw / 2
    local range = O.range
    -- Perspective: the ruler is drawn as if wrapped round a drum seen from
    -- the front, like the teeth of a gear. Positions follow sin(), so the
    -- marks crowd together towards the edges, and they shrink and fade there.
    local persp = O.persp
    local maxang = persp * 1.15
    local function U(c) return math.max(-1, math.min(1, c / range)) end
    local function cx(c)
        local u = U(c)
        if maxang < 0.01 then return mid + u * half end
        return mid + math.sin(u * maxang) / math.sin(maxang) * half
    end
    -- the drum's silhouette: full height in the middle, curving in towards
    -- both edges, like a gear disc seen from slightly above
    local function depth(u) return 1 - 0.7 * persp * u * u end
    -- x -> u (-1..1), the inverse of cx
    local function XU(x)
        local sx = math.max(-1, math.min(1, (x - mid) / half))
        if maxang < 0.01 then return sx end
        return math.asin(sx * math.sin(maxang)) / maxang
    end
    -- a quarter pixel of needle travel at the centre is worth a redraw
    local slope = maxang < 0.01 and 1 or maxang / math.sin(maxang)
    T.disp_step = range / (half * slope) / 4

    local cy = top + rh / 2

    -- In-tune zone: the original's grey area, lit while in tune. It follows
    -- the gear's silhouette, so it curves with the rims.
    local bga = math.min(1, C.zone.a * ((live and T.settled and T.in_tune) and 1.8 or 1))
    local FillRect = reaper.JS_LICE_FillRect
    local zl, zr = math.floor(cx(-O.tol)), math.ceil(cx(O.tol))
    if zr - zl < 2 then zl, zr = math.floor(mid) - 1, math.floor(mid) + 1 end
    for x = zl, zr - 1 do
        local eh = rh * depth(XU(x + 0.5))
        local y = math.floor(cy - eh / 2 + 0.5)
        FillRect(bm, x, y, 1, math.max(1, math.floor(cy + eh / 2 + 0.5) - y),
            C.zone.c | alpha, bga, '')
    end

    -- top and bottom rims: arcs when there is perspective
    if persp > 0.02 then
        local Line = reaper.JS_LICE_Line
        local step = math.max(2, Scale(2, draw_scale))
        local px, pt, pb
        for x = math.floor(x0), math.ceil(x1), step do
            local xx = math.min(x, x1)
            local eh = rh * depth(XU(xx))
            local yt, yb = cy - eh / 2, cy + eh / 2
            if px then
                Line(bm, px, pt, xx, yt, dim_color, 0.9, '', true)
                Line(bm, px, pb, xx, yb, dim_color, 0.9, '', true)
            end
            px, pt, pb = xx, yt, yb
        end
    end

    -- ticks: 21 of them, major every fifth, sized to the silhouette
    local tw = math.max(1, Scale(1, draw_scale))
    for n = -10, 10 do
        local u = n / 10
        local k = depth(u)
        local th
        if n == 0 then th = rh
        elseif n % 5 == 0 then th = rh * 0.66 * k
        else th = rh * 0.38 * k end
        th = math.max(2, math.floor(th + 0.5))
        local tx = math.floor(cx(n * range / 10) - tw / 2 + 0.5)
        if n == 10 then tx = math.min(tx, x1 - tw) end
        local ty = math.floor(cy - th / 2 + 0.5)
        DrawRect(bm, n == 0 and mute_color or dim_color, tx, ty, tw, th, true,
            0, 0.3 + 0.7 * k)
    end

    if not live then return end

    local needle_color, needle_alpha = arrow_color, arrow_alpha
    if not T.settled then
        needle_color, needle_alpha = text_color, 0.55
    elseif T.in_tune then
        needle_color, needle_alpha = tune_color, 1
    end
    T.needle_color = needle_color

    local glow = T.glow or 0
    if glow > 0 then
        DrawGlow(bm, cx(T.needle_pos or T.disp), 0, h,
            Scale(7, draw_scale), tune_color & 0xFFFFFF, glow)
        -- the lit needle itself goes a touch brighter
        needle_color = ShadeRGB(needle_color & 0xFFFFFF, 1, 0.25 * glow) | alpha
    end
    DrawNeedle(bm, cx(T.needle_pos or T.disp), math.max(0, top - Scale(2, draw_scale)),
        math.min(h, top + rh + Scale(2, draw_scale)),
        math.max(2.5, Scale(3, draw_scale)), needle_color & 0xFFFFFF,
        needle_alpha, draw_scale)

    -- cents
    if cents_w > 0 then
        local str = ('%+d'):format(math.floor(T.disp + 0.5))
        if str == '+0' or str == '-0' then str = '0' end
        local sw = gfx.measurestr(str)
        reaper.JS_LICE_SetFontColor(lice_font,
            T.settled and T.needle_color or mute_color)
        reaper.JS_LICE_DrawText(bm, lice_font, str, str:len(),
            w - pad - sw, text_y, w, h)
    end
end

local LoadCursor = reaper.JS_Mouse_LoadCursor
local normal_cursor = LoadCursor(is_windows and 32512 or 0)
local diag1_resize_cursor = LoadCursor(is_linux and 32642 or 32643)
local diag2_resize_cursor = LoadCursor(is_linux and 32643 or 32642)
local horz_resize_cursor = LoadCursor(32644)
local vert_resize_cursor = LoadCursor(32645)
local move_cursor = LoadCursor(32646)

local Intercept = reaper.JS_WindowMessage_Intercept
local Release = reaper.JS_WindowMessage_Release
local Peek = reaper.JS_WindowMessage_Peek

local is_edit_mode = ExtLoad('is_edit_mode', true)

local prev_cursor = normal_cursor
local is_intercept = false

local intercepts = {
    {timestamp = 0, passthrough = false, message = 'WM_SETCURSOR'},
    {timestamp = 0, passthrough = false, message = 'WM_LBUTTONDOWN'},
    {timestamp = 0, passthrough = false, message = 'WM_LBUTTONUP'},
    {timestamp = 0, passthrough = false, message = 'WM_RBUTTONDOWN'},
    {timestamp = 0, passthrough = false, message = 'WM_RBUTTONUP'},
    {timestamp = 0, passthrough = false, message = 'WM_MOUSEWHEEL'},
}

function SetCursor(cursor)
    if not is_intercept then return end
    reaper.JS_Mouse_SetCursor(cursor)
    prev_cursor = cursor
end

-- Lyx: a crashed/killed run never releases its intercepts, and the next run
-- then locks itself out. No fresh heartbeat at load = nobody else is alive,
-- so any block on our own messages is leftover and we clear it once.
local stale_alive = tonumber(reaper.GetExtState(extname, 'alive'))
local can_clear_stale = not stale_alive
    or math.abs(reaper.time_precise() - stale_alive) > 2

local prev_blocked_str
function StartIntercepts()
    if is_intercept then return end
    is_intercept = true
    local _, intercept_str = reaper.JS_WindowMessage_ListIntercepts(window_hwnd)
    local blocked_messages = {}
    for entry in (intercept_str .. ','):gmatch('(.-),') do
        local blocked_message = entry:match('(.-):block')
        if blocked_message then blocked_messages[blocked_message] = true end
    end
    if can_clear_stale then
        can_clear_stale = false
        for _, intercept in ipairs(intercepts) do
            if blocked_messages[intercept.message] then
                Release(window_hwnd, intercept.message)
                blocked_messages[intercept.message] = nil
            end
        end
        -- WM_MOUSEWHEEL is listed as WM_MOUSELAST; free it too
        Release(window_hwnd, 'WM_MOUSEWHEEL')
        _, intercept_str = reaper.JS_WindowMessage_ListIntercepts(window_hwnd)
        blocked_messages = {}
        for entry in (intercept_str .. ','):gmatch('(.-),') do
            local m = entry:match('(.-):block')
            if m then blocked_messages[m] = true end
        end
    end
    for _, intercept in ipairs(intercepts) do
        local msg = intercept.message
        if blocked_messages[msg] then
            is_intercept = false
            -- Lyx: say so instead of silently ignoring every click. Once per
            -- distinct list, so hovering does not flood the console.
            if intercept_str ~= prev_blocked_str then
                prev_blocked_str = intercept_str
                reaper.ShowConsoleMsg(('[Lyx Tuner] Mouse clicks are \z
                    ignored: another script is already blocking mouse \z
                    messages on this window (%s).\nIf no other transport \z
                    box is running, it is a crashed instance: restart \z
                    REAPER to clear it.\n'):format(intercept_str))
            end
            return
        end
    end
    prev_blocked_str = nil
    for _, intercept in ipairs(intercepts) do
        Intercept(window_hwnd, intercept.message, intercept.passthrough)
    end
end

function EndIntercepts()
    if not is_intercept then return end
    if prev_cursor ~= normal_cursor then
        SetCursor(normal_cursor)
    end
    for _, intercept in ipairs(intercepts) do
        Release(window_hwnd, intercept.message)
        intercept.timestamp = 0
    end
    is_intercept = false
    prev_cursor = -1
end

function SetEditMode(mode)
    is_edit_mode = mode
    ExtSave('is_edit_mode', mode)
end


function PeekIntercepts(m_x, m_y)
    if not is_intercept then return end
    for _, intercept in ipairs(intercepts) do
        local msg = intercept.message
        local ret, _, time, _, wph = Peek(window_hwnd, msg)

        if ret and time ~= intercept.timestamp then
            intercept.timestamp = time

            if msg == 'WM_LBUTTONDOWN' then
                -- Avoid new clicks after showing menu
                if menu_time and reaper.time_precise() < menu_time + 0.05 then
                    return
                end
                is_left_click = true
                if is_edit_mode then
                    drag_x = m_x
                    drag_y = m_y
                end
            end

            if msg == 'WM_LBUTTONUP' then
                if not is_left_click then return end

                local all_mods_pressed = reaper.JS_Mouse_GetState(28) == 28
                if all_mods_pressed then
                    PrintIni()
                    return
                end

                -- Ctrl+click prints the detector status to the console.
                -- Kept out of the menu on purpose so it always works.
                if reaper.JS_Mouse_GetState(4) == 4 then
                    ShowTunerStatus()
                    return
                end

                -- Alt+click resets the A4 reference to 440 Hz
                if reaper.JS_Mouse_GetState(16) == 16 then
                    SetReferencePitch(440)
                    return
                end

                if resize_flags == 0 or
                    math.min(box_w, box_h) < min_box_size * 1.5 then
                    -- The tuning fork is the on/off button; clicking the
                    -- readout opens the full size window instead. With the
                    -- icon hidden there is nothing else to click, so the
                    -- box keeps toggling.
                    if snap_w > 0 and m_x - box_x < snap_w then
                        ToggleTuner()
                    elseif snap_w > 0 then
                        OpenBigTuner()
                    else
                        ToggleTuner()
                    end
                end
            end

            if msg == 'WM_RBUTTONDOWN' then
                -- Avoid new clicks after showing menu
                if menu_time and reaper.time_precise() < menu_time + 0.05 then
                    return
                end
                is_right_click = true
            end

            if msg == 'WM_RBUTTONUP' then
                if not is_right_click then return end
                ShowRightClickMenu()
            end

            -- The wheel is deliberately NOT bound to anything. It used to
            -- nudge the reference pitch, which meant a stray scroll over the
            -- transport left people tuning to 442 Hz with nothing on screen
            -- saying so. A4 is a thing you set once, from the menu.
        end
    end
end

-- ---------------------------------------------------------------------------
-- Settings window (ReaImGui). Right click the box to open or close it.
--
-- It runs inside the box's own defer loop (Main calls SettingsFrame every
-- pass), so there is still only one script. Anything that pops a dialog
-- (MB, GetUserInputs) or rebuilds the tuner track is queued in S.todo and
-- run after ImGui.End, never in the middle of a frame.
-- ---------------------------------------------------------------------------

do
local S = {open = false, ctx = nil, todo = nil, startup = nil, copy_key = nil}
local G -- _lib/_Lyx_GUI, loaded on first open
local R = reaper

local function SettingsFont(ctx)
    local name = G.theme.font and G.theme.font.name or ''
    local file = name
    if name == '' then
        file = is_macos and '/System/Library/Fonts/PingFang.ttc'
            or (is_windows and 'C:/Windows/Fonts/msjh.ttc') or ''
    end
    local ok, font = false, nil
    if file ~= '' and R.file_exists(file) then
        ok, font = pcall(R.ImGui_CreateFontFromFile, file, 0)
    end
    if (not ok or not font) and name ~= '' then
        ok, font = pcall(R.ImGui_CreateFont, name)
    end
    if not ok or not font then font = R.ImGui_CreateFont('sans-serif') end
    R.ImGui_Attach(ctx, font)
    return font
end

function OpenSettings()
    if S.open then return end
    if not R.ImGui_CreateFontFromFile then
        R.MB('The settings window needs ReaImGui 0.10 or newer.\n\n' ..
            'Extensions > ReaPack > Browse packages > "ReaImGui"', box_name, 0)
        return
    end
    if not G then
        local ok, mod = pcall(require, '_lib._Lyx_GUI')
        if not ok then
            R.MB('Could not load _lib/_Lyx_GUI.lua:\n\n' .. tostring(mod),
                box_name, 0)
            return
        end
        G = mod
    end
    G.load_theme(LYX_THEME_KEY)
    -- A context that misses a defer cycle is collected by ReaImGui, so a
    -- new one (and its font) is made every time the window opens.
    S.ctx = R.ImGui_CreateContext(box_name .. ' settings')
    S.font = SettingsFont(S.ctx)
    R.ImGui_SetConfigVar(S.ctx, R.ImGui_ConfigVar_Flags(),
        R.ImGui_GetConfigVar(S.ctx, R.ImGui_ConfigVar_Flags())
        & ~R.ImGui_ConfigFlags_NavEnableKeyboard())
    S.startup = IsStartupHookEnabled(nil, true)
    S.first = 1
    S.open = true
end

function CloseSettings()
    if S.rect then R.SetExtState(extname, 'settings_size', S.rect, true) end
    S.open = false
    S.ctx = nil
end

function ToggleSettings()
    if S.open then CloseSettings() else OpenSettings() end
end

-- queue fn to run after this frame (dialogs, track changes)
local function Later(fn) S.todo = fn end

local function Save() SaveThemeSettings(prev_color_theme) end

-- "item was released after editing" -> persist
local function Done(ctx) return R.ImGui_IsItemDeactivatedAfterEdit(ctx) end

local function Tip(ctx, text) R.ImGui_SetItemTooltip(ctx, text) end

local function Section(ctx, label) R.ImGui_SeparatorText(ctx, label) end

local function OptChanged()
    PublishConfig()
    T.hist = {}
    is_redraw = true
end

-- ------------------------------------------------------------------ tabs --
local function TabTuner(ctx)
    local label = T.on and 'Turn tuner off' or 'Turn tuner on'
    if G.button(ctx, label, R.ImGui_GetFrameHeight(ctx) * 6, nil,
        T.on and 'plain' or 'accent') then
        Later(ToggleTuner)
    end
    R.ImGui_SameLine(ctx)
    if G.button(ctx, 'Open big tuner', nil, nil, 'plain') then
        Later(OpenBigTuner)
    end

    Section(ctx, 'Reference pitch')
    R.ImGui_SetNextItemWidth(ctx, -R.ImGui_GetFrameHeight(ctx) * 3)
    local c, v = R.ImGui_SliderDouble(ctx, 'A4##a4', T.a4, 400, 480, '%.1f Hz')
    if c then T.a4 = math.floor(v * 10 + 0.5) / 10; is_redraw = true end
    if Done(ctx) then SetReferencePitch(T.a4) end
    Tip(ctx, 'Ctrl+click to type a value')
    R.ImGui_SameLine(ctx)
    if G.button(ctx, '440', nil, nil, 'plain') then SetReferencePitch(440) end

    Section(ctx, 'Sensitivity')
    local db = 20 * math.log(T.gate, 10)
    R.ImGui_SetNextItemWidth(ctx, -R.ImGui_GetFrameHeight(ctx) * 3)
    c, v = R.ImGui_SliderDouble(ctx, 'Noise gate', db, -90, -10, '%.0f dBFS')
    if c then T.gate = 10 ^ (v / 20); GWrite(GB + 10, T.gate) end
    if Done(ctx) then SetTunerGate(T.gate) end
    Tip(ctx, 'Lower = more sensitive. Raise it if noise shows up as notes.')
end

-- Mouse Y in ImGui coordinates, read from the OS so it keeps working while
-- the mouse is dragged outside the window.
local function MouseY(ctx)
    local nx, ny = reaper.GetMousePosition()
    if R.ImGui_PointConvertNative then
        local _, y = R.ImGui_PointConvertNative(ctx, nx, ny, false)
        return y
    end
    local _, y = R.ImGui_GetMousePos(ctx)
    return y
end

local DT -- _lib/_Lyx_DragToggle, loaded with the GUI library

local function TabInput(ctx)
    local num = R.GetNumAudioInputs()
    if num == 0 then
        R.ImGui_TextDisabled(ctx, 'No audio inputs found (is the audio device running?)')
        return
    end
    DT = DT or require('_lib._Lyx_DragToggle')
    G.dim_text(ctx, 'Tick every input to listen to (they are mixed together). \z
        Press a box and drag up or down to set many at once, like solo / mute \z
        in a mixer; drag back to undo.')
    local on = {}
    for i = 0, num - 1 do on[i] = false end
    for _, n in ipairs(T.inputs) do on[n] = true end
    local shown = S.drag_preview or on
    local only_w = R.ImGui_CalcTextSize(ctx, 'Only') + 16
    local items, pressed = {}, nil
    for i = 0, num - 1 do
        local name = R.GetInputChannelName(i)
        if not name or name == '' then name = tostring(i + 1) end
        R.ImGui_PushID(ctx, i)
        -- The checkbox only draws. Its own toggle is not used: the press is
        -- caught with IsItemActivated (true on the press frame even though
        -- the box itself then becomes the active item).
        R.ImGui_Checkbox(ctx, ('%d  %s'):format(i + 1, name), shown[i] == true)
        if R.ImGui_IsItemActivated(ctx) then pressed = i end
        local _, y0 = R.ImGui_GetItemRectMin(ctx)
        local _, y1 = R.ImGui_GetItemRectMax(ctx)
        items[#items + 1] = {key = i, lo = y0, hi = y1}
        R.ImGui_SameLine(ctx)
        G.align_right(ctx, only_w)
        if G.button(ctx, 'Only', only_w, nil, 'plain') then
            Later(function() SetTunerInputs({i}) end)
        end
        R.ImGui_PopID(ctx)
    end

    -- the Lyx drag-toggle rule (_lib/_Lyx_DragToggle.lua): snapshot + lead +
    -- target on press, recompute from the snapshot by mouse Y every frame,
    -- commit on release
    if pressed and not S.drag then S.drag = DT.begin(on, pressed) end
    if S.drag then
        local preview = DT.preview(S.drag, items, MouseY(ctx))
        S.drag_preview = preview
        if not R.ImGui_IsMouseDown(ctx, 0) then
            S.drag, S.drag_preview = nil, nil
            local list = {}
            for k = 0, num - 1 do if preview[k] then list[#list + 1] = k end end
            Later(function() SetTunerInputs(list) end)
        end
    end
end

local function TabDisplay(ctx)
    Section(ctx, 'Meter')
    R.ImGui_Text(ctx, 'Range')
    for _, r in ipairs({10, 20, 30, 50}) do
        R.ImGui_SameLine(ctx)
        if R.ImGui_RadioButton(ctx, ('+-%d'):format(r), O.range == r) then
            SetOpt('range', r); OptChanged()
        end
    end
    local function Slider(label, key, lo, hi, fmt, mul, tip)
        mul = mul or 1
        R.ImGui_SetNextItemWidth(ctx, -R.ImGui_CalcTextSize(ctx, 'Colour fade____'))
        local c, v = R.ImGui_SliderDouble(ctx, label, O[key] * mul, lo, hi, fmt)
        if c then O[key] = v / mul; OptChanged() end
        if Done(ctx) then SetOpt(key, O[key]) end
        if tip then Tip(ctx, tip) end
    end
    Slider('In tune', 'tol', 1, 15, '+-%.1f cents', 1,
        'Within this many cents the note counts as in tune and lights up')
    Slider('Glow after', 'lock', 0, 3, '%.1f s in tune', 1,
        'How long the note must stay in tune before the name turns the \z
        in-tune colour and the needle glows')
    Slider('Needle speed', 'speed', 5, 100, '%.0f%%', 100,
        'Low = heavy, slow needle; high = light, quick needle')
    Slider('Perspective', 'persp', 0, 100, '%.0f%%', 100,
        'Draws the ruler like a gear seen from the front: 0% = flat')

    Section(ctx, 'Text')
    local function Check(label, key)
        local c, v = R.ImGui_Checkbox(ctx, label, O[key])
        if c then SetOpt(key, v); OptChanged() end
    end
    Check('Flats (Bb instead of A#)', 'flats')
    Check('Octave number', 'octave')
    Check('Cents number', 'show_cents')
    local c, v = R.ImGui_Checkbox(ctx, 'Tuning fork on/off icon (when there is room)',
        not hide_snap)
    if c then
        hide_snap = not v
        R.SetExtState(extname, 'hide_snap', hide_snap and 1 or 0, true)
        is_redraw = true
    end
end

local CE_FLAGS
local function TabAppearance(ctx)
    if not CE_FLAGS then
        CE_FLAGS = R.ImGui_ColorEditFlags_NoInputs() | R.ImGui_ColorEditFlags_AlphaBar()
    end
    Section(ctx, 'Theme')
    if G.theme_row(ctx, LYX_THEME_KEY) then
        lyx_colors_cache = nil
        PublishConfig()
        is_redraw = true
    end

    Section(ctx, 'Colours (saved for this REAPER theme)')
    local C = BoxColors()
    local fh = R.ImGui_GetFrameHeight(ctx)
    for i, uc in ipairs(USER_COLORS) do
        local cur = C[uc.key]
        R.ImGui_PushID(ctx, uc.key)
        local rgba = ((cur.c & 0xFFFFFF) << 8) | math.floor(cur.a * 255 + 0.5)
        local c, nv = R.ImGui_ColorEdit4(ctx, '##c', rgba, CE_FLAGS)
        if c then
            uc.set(FormatUserColor(nv >> 8, (nv & 0xFF) / 255))
            PublishConfig()
            is_redraw = true
        end
        if Done(ctx) then Save() end
        R.ImGui_SameLine(ctx)
        if cur.user then
            R.ImGui_Text(ctx, uc.label)
        else
            R.ImGui_TextDisabled(ctx, uc.label .. ' (theme)')
        end
        if cur.user then
            R.ImGui_SameLine(ctx)
            G.align_right(ctx, fh)
            if G.button(ctx, 'x', fh, fh, 'plain') then
                uc.set(nil); is_redraw = true; Save()
            end
            Tip(ctx, 'Back to the theme colour')
        end
        R.ImGui_PopID(ctx)
    end

    Section(ctx, 'Box')
    local floor = math.floor
    local half = (R.ImGui_GetContentRegionAvail(ctx) - 8) / 2
    local vals = {floor(box_w or 0), floor(box_h or 0), floor(box_x or 0), floor(box_y or 0)}
    local labels = {'Width', 'Height', 'X', 'Y'}
    local changed = false
    for i = 1, 4 do
        if i % 2 == 0 then R.ImGui_SameLine(ctx) end
        R.ImGui_SetNextItemWidth(ctx, half - R.ImGui_CalcTextSize(ctx, 'Height_'))
        local c, v = R.ImGui_DragInt(ctx, labels[i], vals[i], 1,
            i <= 2 and min_box_size or -10000, 10000)
        if c then vals[i] = v; changed = true end
        if Done(ctx) then Later(function() EnsureBoxVisible(); Save() end) end
    end
    if changed then
        SetBoxCoords(vals[3], vals[4], vals[1], vals[2])
        UpdateAttachPosition()
        is_resize = true
    end

    local function IntRow(label, get, set, lo, hi, tip, resize)
        R.ImGui_SetNextItemWidth(ctx, half - R.ImGui_CalcTextSize(ctx, 'Height_'))
        local cur = get()
        local c, v = R.ImGui_SliderInt(ctx, label, cur or 0, lo, hi,
            cur and '%d' or 'auto')
        if c then set(v ~= 0 and v or nil); if resize then is_resize = true else is_redraw = true end end
        if Done(ctx) then Save() end
        if tip then Tip(ctx, tip) end
    end
    IntRow('Corners', function() return user_corner_radius end,
        function(v) user_corner_radius = v end, 0, 20, '0 = auto')
    R.ImGui_SameLine(ctx)
    IntRow('Icon', function() return user_snap_size end,
        function(v) user_snap_size = v end, 0, 40, 'Tuning fork size, 0 = auto', true)

    Section(ctx, 'Font')
    IntRow('Size', function() return user_font_height end,
        function(v) user_font_height = v end, 0, 60, '0 = auto', true)
    R.ImGui_SameLine(ctx)
    IntRow('Y offset', function() return user_font_yoffs end,
        function(v) user_font_yoffs = v end, -10, 10, 'Nudge the text up or down', true)
    R.ImGui_SetNextItemWidth(ctx, half - R.ImGui_CalcTextSize(ctx, 'Height_'))
    local c, v = R.ImGui_InputText(ctx, 'Family', user_font_family or '')
    if c then user_font_family = v ~= '' and v or nil end
    if Done(ctx) then is_resize = true; Save() end
    Tip(ctx, 'Empty = REAPER default font')
    R.ImGui_SameLine(ctx)
    R.ImGui_SetNextItemWidth(ctx, half - R.ImGui_CalcTextSize(ctx, 'Height_'))
    local weights = {{nil, 'Default'}, {400, 'Regular'}, {700, 'Bold'}}
    local preview = 'Default'
    for _, wgt in ipairs(weights) do
        if wgt[1] == user_font_weight then preview = wgt[2] end
    end
    if R.ImGui_BeginCombo(ctx, 'Weight', preview) then
        for _, wgt in ipairs(weights) do
            if R.ImGui_Selectable(ctx, wgt[2], wgt[1] == user_font_weight) then
                user_font_weight = wgt[1]; is_resize = true; Save()
            end
        end
        R.ImGui_EndCombo(ctx)
    end

    Section(ctx, 'Position')
    local modes = {{3, 'Left status edge'}, {4, 'Right status edge'},
        {1, 'Left window edge'}, {2, 'Right window edge'}}
    local cur_mode = GetAttachMode()
    local mode_label = '?'
    for _, md in ipairs(modes) do if md[1] == cur_mode then mode_label = md[2] end end
    R.ImGui_SetNextItemWidth(ctx, half)
    if R.ImGui_BeginCombo(ctx, 'Keep distance from', mode_label) then
        for _, md in ipairs(modes) do
            if R.ImGui_Selectable(ctx, md[2], md[1] == cur_mode) then
                SetAttachMode(md[1]); UpdateAttachPosition(); Save()
            end
        end
        R.ImGui_EndCombo(ctx)
    end
    Tip(ctx, 'Which edge the saved position is measured from, so the box \z
        stays put when the transport is resized')
    local c2, v2 = R.ImGui_Checkbox(ctx, 'Lock position', not is_edit_mode)
    if c2 then SetEditMode(not v2) end
    Tip(ctx, 'Unlocked: drag the box to move it, drag its edges to resize')

    -- other REAPER themes this box has settings for
    local curr_key = GetThemeKey(prev_color_theme)
    local others = {}
    for key in pairs(ExtLoad('theme_settings', {})) do
        if key ~= curr_key then others[#others + 1] = key end
    end
    table.sort(others)
    if #others > 0 then
        Section(ctx, 'Other REAPER themes')
        local function Label(key)
            local l = key:match('([^/\\]+)$') or key
            return GetThemeFromKey(key) and l or (l .. ' (not found)')
        end
        if not S.copy_key then S.copy_key = others[1] end
        R.ImGui_SetNextItemWidth(ctx, -1)
        if R.ImGui_BeginCombo(ctx, '##other', Label(S.copy_key)) then
            for _, key in ipairs(others) do
                if R.ImGui_Selectable(ctx, Label(key), key == S.copy_key) then
                    S.copy_key = key
                end
            end
            R.ImGui_EndCombo(ctx)
        end
        local key = S.copy_key
        local function Copy(with_size)
            Later(function()
                LoadThemeSettings(key .. '.ReaperTheme', not with_size)
                SaveThemeSettings(prev_color_theme)
                prev_color_theme = nil
            end)
        end
        if G.button(ctx, 'Copy look', nil, nil, 'plain') then Copy(false) end
        R.ImGui_SameLine(ctx)
        if G.button(ctx, 'Copy look + size', nil, nil, 'plain') then Copy(true) end
        R.ImGui_SameLine(ctx)
        if G.button(ctx, 'Delete', nil, nil, 'bad') then
            Later(function()
                local msg = 'Permanently delete the saved appearance for \z
                    this theme?\n\n%s'
                if R.MB(msg:format(key), 'Warning', 1) ~= 1 then return end
                SaveThemeSettings(prev_color_theme)
                local all = ExtLoad('theme_settings', {})
                all[key] = nil
                ExtSave('theme_settings', all)
                S.copy_key = nil
                prev_color_theme = nil
            end)
        end
    end

    R.ImGui_Spacing(ctx)
    if G.button(ctx, 'Export appearance (console)', nil, nil, 'plain') then
        Later(PrintIni)
    end
    R.ImGui_SameLine(ctx)
    if G.button(ctx, 'Reset appearance', nil, nil, 'bad') then
        Later(function()
            local msg = 'This will clear all customizations you made for the \z
                active REAPER theme.\n\nProceed?'
            if R.MB(msg, 'Warning', 4) ~= 6 then return end
            local all = ExtLoad('theme_settings', {})
            all[GetThemeKey(prev_color_theme)] = nil
            ExtSave('theme_settings', all)
            prev_color_theme = nil
            if attach_window_title and R.MB(('Move %s back to transport?')
                :format(box_name), box_name, 4) == 6 then
                SaveAttachedWindow(nil)
                EndIntercepts()
                window_hwnd = nil
                prev_top_window_cnt = nil
            end
        end)
    end
end

local function TabAdvanced(ctx)
    local c, v = R.ImGui_Checkbox(ctx, 'Run script on startup', S.startup == true)
    if c then
        Later(function()
            SetStartupHookEnabled(v, 'Start script: Lyx Tuner', 'lyx_tuner_cmd_name')
            S.startup = IsStartupHookEnabled(nil, true)
        end)
    end

    Section(ctx, 'Detector')
    if G.button(ctx, 'Detector status (console)', nil, nil, 'plain') then
        Later(ShowTunerStatus)
    end
    Tip(ctx, 'Also: ctrl+click the box')
    R.ImGui_SameLine(ctx)
    if G.button(ctx, 'Reinstall detector JSFX', nil, nil, 'plain') then
        Later(function()
            DeleteFile(GetJSFXPath())
            if InstallJSFX() then
                if T.on then SetTunerEnabled(false); SetTunerEnabled(true) end
                R.MB('Detector JSFX reinstalled.', box_name, 0)
            else
                R.MB(T.err or 'Failed', box_name, 0)
                T.err = nil
            end
        end)
    end

    if is_windows then
        Section(ctx, 'Windows')
        R.ImGui_SetNextItemWidth(ctx, 160)
        local c2, v2 = R.ImGui_SliderInt(ctx, 'Anti-flickering FPS', comp_fps, 0, 60,
            comp_fps == 0 and 'no limit' or '%d')
        if c2 then
            comp_fps = v2
            comp_delay = comp_fps == 0 and 0 or 1 / comp_fps
            is_resize = true
        end
        if Done(ctx) then R.SetExtState(extname, 'comp_fps', comp_fps, true) end
    end

    Section(ctx, 'Mouse on the box')
    G.dim_text(ctx, 'Click the fork: tuner on/off.  Click the readout: big tuner.\n\z
        Right click: this window.  Ctrl+click: detector status.\n\z
        Alt+click: A4 back to 440 Hz.')
end

-- ----------------------------------------------------------------- frame --
local function SettingsDraw(ctx)
    if R.ImGui_BeginTabBar(ctx, 'tabs') then
        local tabs = {{'Tuner', TabTuner}, {'Input', TabInput},
            {'Display', TabDisplay}, {'Appearance', TabAppearance},
            {'Advanced', TabAdvanced}}
        for _, tab in ipairs(tabs) do
            if R.ImGui_BeginTabItem(ctx, tab[1]) then
                tab[2](ctx)
                R.ImGui_EndTabItem(ctx)
            end
        end
        R.ImGui_EndTabBar(ctx)
    end
end

local function SettingsFrameUnsafe()
    if not S.open then return end
    local ctx = S.ctx
    if not R.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
        CloseSettings()
        return
    end
    if G.poll() then lyx_colors_cache = nil end
    G.push_theme(ctx)
    R.ImGui_PushFont(ctx, S.font, G.font_size(14))
    if S.first then
        -- A brand new context does not know where the mouse is on its first
        -- frame, so that frame only primes it. The window opens on the
        -- second frame, centred under the mouse (= under the box you right
        -- clicked) and kept inside the screen. Only the size is remembered.
        S.first = S.first + 1
        if S.first == 2 then
            R.ImGui_GetMousePos(ctx)
            R.ImGui_PopFont(ctx)
            G.pop_theme(ctx)
            return
        end
        local sw, sh = R.GetExtState(extname, 'settings_size'):match('^(%d+) (%d+)$')
        sw, sh = tonumber(sw), tonumber(sh)
        if not (sw and sw >= 250 and sh and sh >= 200) then
            sw, sh = G.S(460), G.S(540)
        end
        -- Placed from NATIVE coordinates (the mouse and REAPER's own main
        -- window), converted to ImGui's: ImGui's own mouse position is not
        -- known until one of its windows has been hovered.
        local nmx, nmy = reaper.GetMousePosition()
        local _, l, t, r, b = reaper.JS_Window_GetRect(main_hwnd)
        local function Conv(px, py)
            if R.ImGui_PointConvertNative then
                return R.ImGui_PointConvertNative(ctx, px, py, false)
            end
            return px, py
        end
        local mx, my = Conv(nmx, nmy)
        local ax, ay = Conv(l, t)
        local bx, by = Conv(r, b)
        local left, right = math.min(ax, bx), math.max(ax, bx)
        local wtop, wbot = math.min(ay, by), math.max(ay, by)
        local x, y = mx - sw / 2, my + 16
        if right - left > sw and wbot - wtop > sh then
            x = math.max(left, math.min(x, right - sw))
            y = math.max(wtop, math.min(y, wbot - sh))
        else
            x, y = left + 40, wtop + 40
        end
        R.ImGui_SetNextWindowPos(ctx, x, y, R.ImGui_Cond_Always())
        R.ImGui_SetNextWindowSize(ctx, sw, sh, R.ImGui_Cond_Always())
        S.first = false
    end
    local visible, open = R.ImGui_Begin(ctx, box_name, true,
        R.ImGui_WindowFlags_NoCollapse() | R.ImGui_WindowFlags_NoSavedSettings()
        | G.pin_flag(LYX_THEME_KEY))
    local keep = open
    if visible then
        -- status line + pin
        local ins = {}
        for i, n in ipairs(T.inputs) do ins[i] = n + 1 end
        local status = ('Tuner %s   A4 %g Hz   input %s'):format(
            T.on and 'ON' or 'off', T.a4,
            #ins > 0 and table.concat(ins, '+') or 'none')
        if T.on then G.color_text(ctx, G.accent, status)
        else R.ImGui_TextDisabled(ctx, status) end
        R.ImGui_SameLine(ctx)
        G.align_right(ctx, R.ImGui_GetFrameHeight(ctx))
        G.pin(ctx, LYX_THEME_KEY)

        local ok, err = xpcall(SettingsDraw, debug.traceback, ctx)
        if not ok then
            R.ShowConsoleMsg('\n[' .. box_name .. ' settings] ' .. tostring(err) .. '\n')
            keep = false
        end
        if R.ImGui_IsWindowFocused(ctx, R.ImGui_FocusedFlags_RootAndChildWindows())
            and not R.ImGui_IsAnyItemActive(ctx)
            and R.ImGui_IsKeyPressed(ctx, R.ImGui_Key_Escape()) then
            keep = false
        end
        local ww, wh = R.ImGui_GetWindowSize(ctx)
        S.rect = ('%d %d'):format(math.floor(ww), math.floor(wh))
        R.ImGui_End(ctx)
    end
    R.ImGui_PopFont(ctx)
    G.pop_theme(ctx)
    if G.esc() then keep = false end

    local todo = S.todo
    S.todo = nil
    if todo then todo() end
    if not keep then CloseSettings() end
end

-- Whatever goes wrong in the settings window must never take the tuner
-- down with it: the error goes to the console and only the window closes.
local function SettingsError(where, err)
    reaper.ShowConsoleMsg('\n[Lyx Tuner settings] ERROR in ' .. where .. ':\n'
        .. tostring(err) .. '\n')
    S.open = false
    S.ctx = nil
    S.todo = nil
end

function SettingsFrame()
    if not S.open then return end
    local ok, err = xpcall(SettingsFrameUnsafe, debug.traceback)
    if not ok then SettingsError('frame', err) end
end

function ShowRightClickMenu()
    local ok, err = xpcall(ToggleSettings, debug.traceback)
    if not ok then SettingsError('open', err) end
    -- same clean up the old popup menu did: no click or drag may carry over
    -- into the window that just opened
    menu_time = reaper.time_precise()
    is_left_click = false
    is_right_click = false
    drag_x = nil
end

end -- settings window

-- ------------------------------------------------------------ neighbors --
-- Other scripts built on the same engine (GridBox, ChordBox, PeakBox...)
-- also draw straight onto the transport. REAPER still reports their spot as
-- empty transport, so the stock placement would happily drop TunerBox right
-- on top of them. These helpers find where the running ones are and keep
-- TunerBox out of the way.
--
-- A neighbor is found through its ExtState section: it saves its position
-- per theme in 'theme_settings' and its command name in 'hook_cmd_name',
-- whose toggle state tells whether it is running right now.

local neighbor_sections
local neighbor_check_time = 0
local prev_neighbor_sig

-- Section names that look like a box: they keep 'theme_settings'. Read once
-- from reaper-extstate.ini, since ExtState sections cannot be enumerated.
local function FindNeighborSections()
    if neighbor_sections then return neighbor_sections end
    local found = {['FTC.GridBox'] = true, ['FTC.ChordBox'] = true}
    local path = ConcatPath(reaper.GetResourcePath(), 'reaper-extstate.ini')
    local file = io.open(path, 'r')
    if file then
        local section
        for line in file:lines() do
            local name = line:match('^%[(.-)%]%s*$')
            if name then
                section = name
            elseif section and line:match('^theme_settings=') then
                found[section] = true
            end
        end
        file:close()
    end
    found[extname] = nil
    neighbor_sections = {}
    for name in pairs(found) do
        neighbor_sections[#neighbor_sections + 1] = name
    end
    table.sort(neighbor_sections)
    return neighbor_sections
end

-- Some boxes save a plain Lua table literal instead of the Gridbox format.
-- Parse it by hand: never run a string read from disk as code.
local function ParseLuaTable(str)
    local pos = 1

    local function Skip()
        pos = str:find('[^%s,]', pos) or #str + 1
    end

    local ParseValue

    local function ParseString()
        local quote = str:sub(pos, pos)
        local i = pos + 1
        local out = {}
        while i <= #str do
            local c = str:sub(i, i)
            if c == '\\' then
                out[#out + 1] = str:sub(i + 1, i + 1)
                i = i + 2
            elseif c == quote then
                pos = i + 1
                return table.concat(out)
            else
                out[#out + 1] = c
                i = i + 1
            end
        end
        error('unterminated string')
    end

    local function ParseTable()
        pos = pos + 1
        local t = {}
        while true do
            Skip()
            local c = str:sub(pos, pos)
            if c == '}' then
                pos = pos + 1
                return t
            end
            local key
            if c == '[' then
                pos = pos + 1
                Skip()
                key = ParseValue()
                Skip()
                if str:sub(pos, pos) ~= ']' then error('bad key') end
                pos = pos + 1
            else
                key = str:match('^[%a_][%w_]*', pos)
                if not key then error('bad key') end
                pos = pos + #key
            end
            Skip()
            if str:sub(pos, pos) ~= '=' then error('missing =') end
            pos = pos + 1
            Skip()
            t[key] = ParseValue()
        end
    end

    ParseValue = function()
        local c = str:sub(pos, pos)
        if c == '{' then return ParseTable() end
        if c == '"' or c == "'" then return ParseString() end
        local word = str:match('^[%w%.%+%-]+', pos)
        if not word then error('bad value') end
        pos = pos + #word
        if word == 'true' then return true end
        if word == 'false' then return false end
        local n = tonumber(word)
        if n == nil then error('bad value') end
        return n
    end

    Skip()
    if str:sub(pos, pos) ~= '{' then return end
    local ok, ret = pcall(ParseValue)
    if ok and type(ret) == 'table' then return ret end
end

-- A theme can ship a position for a box (gridbox.ini, chordbox.ini...).
-- The box uses it when nothing is saved for that theme, so we do too.
-- Reading it may mean opening the theme zip, so keep the result.
local integrated_cache = {}

local function LoadNeighborIntegrated(section, theme_key)
    local name = section:match('([^.]+)$')
    local cache_key = section .. '|' .. theme_key
    local cached = integrated_cache[cache_key]
    if cached ~= nil then return cached or nil end
    local config
    local theme_file = GetThemeFromKey(theme_key)
    if theme_file then
        local ok, ret = pcall(LoadIntegratedSettings, theme_file, name)
        if ok and type(ret) == 'table' then config = ret end
    end
    integrated_cache[cache_key] = config or false
    return config
end

local function LoadNeighborSettings(section)
    local theme_key = GetThemeKey(prev_color_theme)
    local str = reaper.GetExtState(section, 'theme_settings')
    local settings
    if str:sub(1, 2) == 't:' then
        local ok, ret = pcall(Deserialize, str)
        if ok then settings = ret end
    elseif str ~= '' then
        settings = ParseLuaTable(str)
    end
    if type(settings) == 'table' and type(settings[theme_key]) == 'table' then
        return settings[theme_key]
    end
    return LoadNeighborIntegrated(section, theme_key)
end

local function IsNeighborRunning(section)
    local cmd_name = reaper.GetExtState(section, 'hook_cmd_name')
    if cmd_name == '' then return false end
    local cmd_id = reaper.NamedCommandLookup(cmd_name)
    if not cmd_id or cmd_id == 0 then return false end
    return reaper.GetToggleCommandState(cmd_id) == 1
end

-- Turn a neighbor's saved settings into a rectangle in transport client
-- coordinates, the same way GetAttachPosition does it for our own box.
local function NeighborRect(s)
    local function Num(v)
        if type(v) ~= 'number' or v ~= v then return nil end
        return v
    end
    -- Boxes with several styles save one size per style; assume the largest
    local w = Num(s.box_w)
    local h = Num(s.box_h)
    for key, v in pairs(s) do
        if type(key) == 'string' and Num(v) then
            if key:match('^box_w_') then w = math.max(w or 0, v) end
            if key:match('^box_h_') then h = math.max(h or 0, v) end
        end
    end
    local x, y = Num(s.box_x), Num(s.box_y)
    if not x or not y or not w or not h or w <= 0 or h <= 0 then return end

    local scale = 1
    local saved_scale = Num(s.measure_scale)
    if saved_scale and saved_scale > 0 then scale = measure_scale / saved_scale end

    local is_centered = reaper.GetToggleCommandState(40533) == 1
    local ax, mode
    if is_centered then
        ax = Num(s.attach_center_x) or Num(s.attach_x)
        mode = Num(s.attach_center_mode) or Num(s.attach_mode)
    else
        ax = Num(s.attach_x) or Num(s.attach_center_x)
        mode = Num(s.attach_mode) or Num(s.attach_center_mode)
    end
    if ax and mode then
        ax = ax * scale
        if mode == 1 then x = ax end
        if mode == 2 then x = ax + window_w end
        if mode == 3 or mode == 4 then
            local st_l, _, st_r = GetStatusWindowClientRect()
            x = ax + (mode == 3 and st_l or st_r)
        end
    else
        x = x * scale
    end
    return {x = x, y = y * scale, w = w * scale, h = h * scale}
end

-- Rectangles taken by running neighbors on the transport. A running
-- neighbor with nothing saved for this theme sits where the stock placement
-- puts a box, so it gets the default rectangle passed in.
function GetNeighborRects(default_rect)
    local rects = {}
    for _, section in ipairs(FindNeighborSections()) do
        if IsNeighborRunning(section) and
            reaper.GetExtState(section, 'attach_title') == '' then
            local settings = LoadNeighborSettings(section)
            local rect = settings and NeighborRect(settings)
            rect = rect or default_rect
            if rect then rects[#rects + 1] = rect end
        end
    end
    return rects
end

local function GetNeighborSignature()
    local sig = {}
    for _, section in ipairs(FindNeighborSections()) do
        if IsNeighborRunning(section) then sig[#sig + 1] = section end
    end
    return table.concat(sig, ',')
end

function IsReservedX(reserved, x, y, h)
    for _, r in ipairs(reserved) do
        if x >= r.x and x < r.x + r.w and y < r.y + r.h and y + h > r.y then
            return true
        end
    end
    return false
end

local function OverlapsAny(rects, x, y, w, h)
    for _, r in ipairs(rects) do
        if x < r.x + r.w and x + w > r.x and y < r.y + r.h and y + h > r.y then
            return true
        end
    end
    return false
end

-- Where the stock placement puts a box. Any running neighbor with nothing
-- saved for this theme is sitting right there. Leaves our box untouched.
local function GetDefaultRect()
    local saved = {box_x, box_y, box_w, box_h, attach_x, attach_mode,
        attach_center_x, attach_center_mode}
    PlaceInEmptyArea()
    local rect = {x = box_x, y = box_y, w = box_w, h = box_h}
    box_x, box_y, box_w, box_h = saved[1], saved[2], saved[3], saved[4]
    attach_x, attach_mode = saved[5], saved[6]
    attach_center_x, attach_center_mode = saved[7], saved[8]
    return rect
end

function FindInitialPosition()
    PlaceInEmptyArea()
    local default_rect = {x = box_x, y = box_y, w = box_w, h = box_h}
    local reserved = GetNeighborRects(default_rect)
    if #reserved == 0 then return end
    PlaceInEmptyArea(reserved)
end

-- Move away from a neighbor we overlap. Runs when the theme loads and
-- whenever a neighbor starts or stops. A position the user saved is kept
-- unless it really collides, and then the new one is saved in its place.
function AvoidNeighbors(force)
    if attach_window_title or drag_x or not box_x or not window_w then return end
    local time = reaper.time_precise()
    if not force and time < neighbor_check_time + 1 then return end
    neighbor_check_time = time

    local sig = GetNeighborSignature()
    if not force and sig == prev_neighbor_sig then return end
    prev_neighbor_sig = sig
    if sig == '' then return end

    local x, y, w, h = box_x, box_y, box_w, box_h
    local rects = GetNeighborRects(GetDefaultRect())
    if not OverlapsAny(rects, x, y, w, h) then return end

    FindInitialPosition()
    EnsureBoxVisible()
    local theme_settings = ExtLoad('theme_settings', {})
    if theme_settings[GetThemeKey(prev_color_theme)] ~= nil then
        SaveThemeSettings(prev_color_theme)
    end
    is_resize = true
end

function GetStatusWindowClientRect()
    -- Get status window coordinates
    local status_hwnd = reaper.JS_Window_FindChildByID(window_hwnd, 1010)
    if not status_hwnd then return 0, 0, 0, window_h or 0 end
    local ok, st_l, st_t, st_r, st_b = reaper.JS_Window_GetRect(status_hwnd)
    if not ok or not st_l then return 0, 0, 0, window_h or 0 end
    st_l, st_t = reaper.JS_Window_ScreenToClient(window_hwnd, st_l, st_t)
    st_r, st_b = reaper.JS_Window_ScreenToClient(window_hwnd, st_r, st_b)

    -- Note: Window can be out of transport bounds
    st_l = math.max(st_l, 0)
    st_t = math.max(st_t, 0)
    st_r = math.min(st_r, window_w)
    st_b = math.min(st_b, window_h)

    return st_l, st_t, st_r, st_b
end

function SetBoxCoords(x, y, w, h)
    if w == 0 or h == 0 then return end
    local has_pos_changed = x and x ~= box_x or y and y ~= box_y
    local has_size_changed = w and w ~= box_w or h and h ~= box_h
    if not has_pos_changed and not has_size_changed then return end

    if has_pos_changed then is_redraw = true end
    if has_size_changed then is_resize = true end

    -- Redraw previous area
    InvalidateBoxRect()

    box_x, box_y, box_w, box_h = x or box_x, y or box_y, w or box_w, h or box_h

    -- Redraw new area
    InvalidateBoxRect()

    if not is_resize then
        -- Change bitmap draw coordinates
        reaper.JS_Composite_Delay(window_hwnd, comp_delay, comp_delay * 1.5, 2)
        reaper.JS_Composite(window_hwnd, box_x, box_y, box_w, box_h, bitmap, 0, 0,
            GetBitmapSize())
    end
end

function UpdateAttachPosition()
    local mode = GetAttachMode()
    if not box_x or not window_w then return end
    local new_x
    if mode == 1 then new_x = box_x end
    if mode == 2 then new_x = box_x - window_w end
    if mode == 3 then
        local st_l = GetStatusWindowClientRect()
        new_x = box_x - st_l
    end
    if mode == 4 then
        local _, _, st_r = GetStatusWindowClientRect()
        new_x = box_x - st_r
    end
    local is_centered = reaper.GetToggleCommandState(40533) == 1
    if not attach_window_title and is_centered then
        attach_center_x = new_x
    else
        attach_x = new_x
    end
end

function GetAttachMode()
    local mode = attach_mode or attach_center_mode
    if attach_window_title then
        -- Note: Status window options are only valid when attached to transport
        if mode and mode > 2 then mode = mode - 2 end
    else
        local is_centered = reaper.GetToggleCommandState(40533) == 1
        if is_centered then mode = attach_center_mode or attach_mode end
    end
    return mode
end

function SetAttachMode(mode)
    local is_centered = reaper.GetToggleCommandState(40533) == 1
    if attach_window_title or not is_centered then
        attach_mode = mode
    else
        attach_center_mode = mode
    end
end

function GetAttachPosition()
    local x = attach_x or attach_center_x
    if not x then return end
    if not attach_window_title then
        local is_centered = reaper.GetToggleCommandState(40533) == 1
        if is_centered then x = attach_center_x or attach_x end
    end

    local mode = GetAttachMode()
    local new_box_x
    if mode == 1 then
        new_box_x = x
    end
    if mode == 2 then
        new_box_x = x + window_w
    end
    if mode == 3 or mode == 4 then
        local st_l = GetStatusWindowClientRect()
        new_box_x = x + st_l
    end
    if mode == 4 then
        local _, _, st_r = GetStatusWindowClientRect()
        new_box_x = x + st_r
    end
    return new_box_x
end

function EnsureBoxVisible()
    -- Ensure position/size is within bounds
    if window_w == 0 or window_h == 0 then return end
    local w = math.max(min_box_size, math.min(box_w, window_w))
    local h = math.max(min_box_size, math.min(box_h, window_h))

    local x = math.max(0, math.min(window_w - w, box_x))
    local y = math.max(0, math.min(window_h - h, box_y))

    if attach_window_title then
        SetBoxCoords(x, y, w, h)
        return
    end

    -- Get status window coordinates
    local st_l, st_t, st_r, st_b = GetStatusWindowClientRect()

    local st_x = st_l
    local st_y = st_t
    local st_w = st_r - st_l
    local st_h = math.abs(st_b - st_t)

    -- Check if bitmap overlaps or contains status window
    local is_left = x + w < st_x
    local is_right = x > st_x + st_w
    local is_above = y + h < st_y
    local is_below = y > st_y + st_h

    local is_overlap = not (is_left or is_right or is_above or is_below)
    local is_contained = x > st_l and x < st_r and y > st_t and y < st_b

    if is_overlap or is_contained then
        -- Move bitmap to not overlap with status window
        local space_l = st_l
        local space_r = window_w - st_r
        local space_t = st_t
        local space_b = window_h - st_b

        local new_l_x = st_l - w
        local new_r_x = st_r
        local new_t_y = st_t - h
        local new_b_y = st_b

        local move_x = 0
        local move_y = 0

        if space_l >= w or space_r >= w then
            if space_l >= w and space_r >= w then
                -- Space on both sides, move to closest position
                move_x = x - new_l_x < new_r_x - x and -1 or 1
            else
                -- Space only on one side, move accordingly
                move_x = space_r > space_l and 1 or -1
            end
        elseif space_t >= h or space_b >= h then
            if space_t >= h and space_b >= h then
                -- Space on both sides, move to closest position
                move_y = y - new_t_y < new_b_y - y and -1 or 1
            else
                -- Space only on one side, move accordingly
                move_y = space_b > space_t and 1 or -1
            end
        else
            -- Check if more vertical or horizontal space, move accordingly
            if math.max(space_l, space_r) > math.max(space_t, space_b) then
                move_x = space_r > space_l and 1 or -1
            else
                move_y = space_b > space_t and 1 or -1
            end
        end

        if move_x == -1 then
            -- Move left
            x = new_l_x
            w = math.min(w, space_l)
        end
        if move_x == 1 then
            -- Move right
            x = new_r_x
            w = math.min(w, space_r)
        end
        if move_y == -1 then
            -- Move top
            y = new_t_y
            h = math.min(h, space_t)
        end
        if move_y == 1 then
            -- Move bottom
            y = new_b_y
            h = math.min(h, space_b)
        end

        -- Ensure position/size is within bounds after move
        w = math.max(min_box_size, math.min(w, window_w))
        h = math.max(min_box_size, math.min(h, window_h))

        x = math.max(0, math.min(window_w - w, x))
        y = math.max(0, math.min(window_h - h, y))
    end

    SetBoxCoords(x, y, w, h)
end

function PlaceInEmptyArea(reserved)
    -- Get status window coordinates
    local st_l, st_t, st_r, st_b = GetStatusWindowClientRect()
    local st_y = st_t
    local st_h = math.abs(st_b - st_t)

    -- Set initial position that matches status window
    box_x = 0
    box_y = st_y
    box_w = st_h * 6
    box_h = st_h

    -- Add small vertical margin if status window takes up full transport height
    if st_h >= window_h - Scale(4, measure_scale) then
        box_y = box_y + Scale(2, measure_scale)
        box_h = box_h - Scale(4, measure_scale)
    end

    -- Now we'll use GetThingFromPoint to get empty transport areas on x axis
    local st_mid_y = st_y + box_h // 2
    local empty_areas = {}

    local size = 0
    local sel_cnt = 0
    local bpm_x

    local function AddEmptyArea(x, y, align)
        local _, thing = reaper.GetThingFromPoint(x, y)
        if thing == 'trans' and reserved then
            local cx = reaper.JS_Window_ScreenToClient(window_hwnd, x, y)
            if IsReservedX(reserved, cx, box_y, box_h) then thing = nil end
        end

        if thing == 'trans' then
            -- Empty transport area, increase size
            size = size + 1
        else
            -- Remember x position of BPM button
            if not bpm_x and type(thing) == 'string' and
                thing:sub(1, 9) == 'trans.bpm' then
                bpm_x = x
            end
            if size > 0 then
                -- Add previous area
                if sel_cnt == 0 and size > min_box_size then
                    local area = {size = size, r = x, align = align}
                    empty_areas[#empty_areas + 1] = area
                end
                size = 0
                sel_cnt = 0
            end

            -- Skip areas to the right of selection (selection textboxes)
            if thing == 'trans.sel' then sel_cnt = sel_cnt + 1 end
        end
    end

    local ClientToScreen = reaper.JS_Window_ClientToScreen
    local x_start, y = ClientToScreen(window_hwnd, 0, st_mid_y)
    local x_end = ClientToScreen(window_hwnd, st_l, st_mid_y)

    for x = x_start, x_end do
        AddEmptyArea(x, y, 1)
    end
    AddEmptyArea(x_end, -1, 1)

    x_start = ClientToScreen(window_hwnd, st_r, st_mid_y)
    x_end = ClientToScreen(window_hwnd, window_w, st_mid_y)

    for x = x_start, x_end do
        AddEmptyArea(x, y, -1)
    end
    AddEmptyArea(x_end, -1, 1)

    local target_area

    if bpm_x then
        local min_bpm_distance
        for _, area in ipairs(empty_areas) do
            -- Check if area is large enough
            if area.size > box_w * 0.7 then
                local area_x = area.r > bpm_x and area.r or area.r - area.size
                local diff = bpm_x - area_x
                local distance = math.abs(diff)
                -- Check distance to bpm window
                if not min_bpm_distance or distance < min_bpm_distance then
                    min_bpm_distance = distance
                    target_area = area
                    target_area.align = area.r > bpm_x and -1 or 1
                end
            end
        end
    end

    if not target_area then
        -- Find largest empty area
        local largest_area_size = 0
        for _, area in ipairs(empty_areas) do
            if area.size > largest_area_size then
                target_area = area
                largest_area_size = area.size
            end
        end
    end

    if not target_area and window_w and box_w then
        box_x = math.max(0, (window_w - box_w) // 2)
    end

    if target_area then
        -- Make bitmap a bit larger if it'll then fully fit empty space
        if target_area.size < box_w * 1.5 then box_w = target_area.size end

        -- Add margin
        local m = box_h // 6
        box_w = math.max(min_box_size, math.min(target_area.size - 2 * m, box_w))

        -- Convert back to client coordinates
        local r = target_area.r
        r = reaper.JS_Window_ScreenToClient(window_hwnd, r, st_mid_y)

        -- Place bitmap (x pos) in empty target area (based on alignment)
        if target_area.align > 0 then
            box_x = math.max(0, r - box_w - m)
            SetAttachMode(box_x < st_r and 3 or 2)
        else
            box_x = math.max(0, r - target_area.size + m)
            SetAttachMode(box_x < st_r and 1 or 4)
        end
    else
        SetAttachMode(box_x < st_r and 1 or 2)
    end
    UpdateAttachPosition()
end

function WaitForAttachedWindow()
    if attach_window_title == 'REAPER Main Window' then return true end
    if attach_window_title == 'Active MIDI editor' then return true end
    return attach_window_wait == attach_window_title
end

function FindAttachedWindow()
    local hwnd
    local window_cnt = 0
    if attach_window_title == 'REAPER Main Window' then
        hwnd = main_hwnd
    elseif attach_window_title == 'Active MIDI editor' then
        hwnd = reaper.MIDIEditor_GetActive()
    else
        local title = attach_window_title or transport_title
        local cnt, list = reaper.JS_Window_ListFind(title, true)
        window_cnt = cnt
        if window_cnt > 0 then
            local first_hwnd
            local main_child
            for addr in (list .. ','):gmatch('(.-),') do
                local handle = reaper.JS_Window_HandleFromAddress(addr)
                first_hwnd = first_hwnd or handle
                -- Check if only one of the windows is child of main window
                -- (for case when running multiple reaper instances)
                if reaper.JS_Window_IsChild(main_hwnd, handle) then
                    if main_child then
                        main_child = nil
                        break
                    else
                        main_child = handle
                    end
                end
            end
            if main_child then
                hwnd = main_child
                window_cnt = 1
            else
                hwnd = first_hwnd
            end
        end

        if hwnd and attach_window_title then
            reaper.SetExtState(extname, 'attach_wait', attach_window_title, true)
        end
    end
    if hwnd and attach_window_child_id then
        local child = reaper.JS_Window_FindChildByID(hwnd, attach_window_child_id)
        if child then
            hwnd = child
        else
            attach_window_child_id = nil
            reaper.SetExtState(extname, 'attach_child_id', '', true)
        end
    end
    return hwnd, window_cnt
end

function SaveAttachedWindow(title, child_id)
    if not title or title == transport_title and not child_id then
        attach_window_title = nil
        attach_window_child_id = nil
        reaper.SetExtState(extname, 'attach_title', '', true)
        reaper.SetExtState(extname, 'attach_child_id', '', true)
        reaper.SetExtState(extname, 'attach_wait', '', true)
        ExtSave('attach_settings', nil)
    else
        attach_window_title = title
        attach_window_child_id = child_id
        reaper.SetExtState(extname, 'attach_title', title, true)
        reaper.SetExtState(extname, 'attach_child_id', child_id or '', true)
        reaper.SetExtState(extname, 'attach_wait', '', true)
    end
end

function Main()
    TunerTick()
    SettingsFrame()

    -- Find window
    if not window_hwnd or not reaper.ValidatePtr(window_hwnd, 'HWND*') then
        local time = reaper.time_precise()
        if not prev_time or time > prev_time + 0.5 then
            prev_time = time
            local top_window_cnt = reaper.JS_Window_ArrayAllTop(top_window_array)
            if top_window_cnt ~= prev_top_window_cnt then
                prev_top_window_cnt = top_window_cnt
                window_hwnd = FindAttachedWindow()
                is_resize = true
            end
        end
    elseif attach_window_title and not attach_window_child_id and not drag_x then
        -- Check attached window title changes (e.g. when switching toolbar)
        local curr_title = reaper.JS_Window_GetTitle(window_hwnd)
        if curr_title ~= attach_window_title then
            if bitmap then
                reaper.JS_Composite_Unlink(window_hwnd, bitmap)
                reaper.JS_Composite_Delay(window_hwnd, 0, 0, 0)
            end
            EndIntercepts()
            InvalidateBoxRect()
            prev_window_hwnd = window_hwnd
            window_hwnd = nil
        end
    end

    if prev_window_hwnd and reaper.ValidatePtr(prev_window_hwnd, 'HWND*') and
        reaper.JS_Window_GetTitle(prev_window_hwnd) == attach_window_title then
        window_hwnd = prev_window_hwnd
        prev_window_hwnd = nil
    end

    -- Go idle if window is not found/visible
    if not window_hwnd or not reaper.JS_Window_IsVisible(window_hwnd) then
        reaper.defer(Main)
        return
    end

    mouse_x, mouse_y = GetMousePosition()
    local hover_hwnd = reaper.JS_Window_FromPoint(mouse_x, mouse_y)

    do
        local ok, w, h = reaper.JS_Window_GetClientSize(window_hwnd)
        if not ok or type(w) ~= 'number' or type(h) ~= 'number' or
            w <= 0 or h <= 0 then
            window_hwnd = nil
            reaper.defer(Main)
            return
        end
        window_w, window_h = w, h
    end

    -- Monitor color theme changes
    local color_theme = reaper.GetLastColorThemeFile()
    if color_theme ~= prev_color_theme then
        SetThemeIntegration(1)
        prev_color_theme = color_theme
        if not LoadThemeSettings(color_theme) then
            FindInitialPosition()
        end
        EnsureBoxVisible()
        AvoidNeighbors(true)
        is_resize = true
    end

    -- Detect changes to window size
    if window_w ~= prev_window_w or window_h ~= prev_window_h then
        local prev_measure_scale, prev_draw_scale = measure_scale, draw_scale
        measure_scale, draw_scale = GetTransportScale()

        if draw_scale ~= prev_draw_scale then
            local scale_factor = draw_scale / prev_draw_scale
            user_font_height = Scale(user_font_height, scale_factor)
            user_font_yoffs = Scale(user_font_yoffs, scale_factor)
            user_corner_radius = Scale(user_corner_radius, scale_factor)
            user_snap_size = Scale(user_snap_size, scale_factor)
            is_resize = true
        end
        if measure_scale ~= prev_measure_scale then
            min_box_size = Scale(12, measure_scale)

            local scale_factor = measure_scale / prev_measure_scale
            local new_box_x = Scale(box_x, scale_factor)
            local new_box_y = Scale(box_y, scale_factor)
            local new_box_w = Scale(box_w, scale_factor)
            local new_box_h = Scale(box_h, scale_factor)

            attach_x = Scale(attach_x, scale_factor)
            attach_center_x = Scale(attach_center_x, scale_factor)
            if attach_x or attach_center_x then new_box_x = GetAttachPosition() end

            SetBoxCoords(new_box_x, new_box_y, new_box_w, new_box_h)
            EnsureBoxVisible()
            is_resize = true
        end
        if prev_window_w then
            -- Move bitmap based on attached position
            local new_box_x = GetAttachPosition()
            if new_box_x then SetBoxCoords(new_box_x) end
            EnsureBoxVisible()
        end
        prev_window_w = window_w
        prev_window_h = window_h
    end

    -- Detect centered transport toggle
    local is_centered = reaper.GetToggleCommandState(40533) == 1
    if is_centered ~= prev_is_centered then
        prev_is_centered = is_centered
        local new_box_x = GetAttachPosition()
        if new_box_x then SetBoxCoords(new_box_x) end
        EnsureBoxVisible()
    end


    local is_snap_hovered = false
    local is_hovered = false

    if hover_hwnd == window_hwnd or drag_x then
        local ScreenToClient = reaper.JS_Window_ScreenToClient
        local m_x, m_y = ScreenToClient(window_hwnd, mouse_x, mouse_y)
        -- Handle drag move/resize
        if drag_x and (drag_x ~= m_x or drag_y ~= m_y) then
            if resize_flags > 0 then
                if resize_flags & 1 == 1 then
                    local box_r = box_x + box_w
                    local new_box_w = math.max(min_box_size, box_r - m_x)
                    local new_box_x = box_r - new_box_w
                    SetBoxCoords(new_box_x, nil, new_box_w, nil)
                end
                if resize_flags & 2 == 2 then
                    local box_b = box_y + box_h
                    local new_box_h = math.max(min_box_size, box_b - m_y)
                    local new_box_y = box_b - new_box_h
                    SetBoxCoords(nil, new_box_y, nil, new_box_h)
                end
                if resize_flags & 4 == 4 then
                    local new_box_w = math.max(min_box_size, m_x - box_x)
                    SetBoxCoords(nil, nil, new_box_w, nil)
                end
                if resize_flags & 8 == 8 then
                    local new_box_h = math.max(min_box_size, m_y - box_y)
                    SetBoxCoords(nil, nil, nil, new_box_h)
                end
                is_resize = true
            else
                prev_box_w = prev_box_w or box_w
                prev_box_h = prev_box_h or box_h
                prev_box_x = prev_box_x or box_x
                prev_box_y = prev_box_y or box_y

                -- Move box to hovered window. Only while the left button is
                -- really held: a stale drag (a window popping up under the
                -- mouse, like the settings window) must not carry the box
                -- off and ask to attach it somewhere else.
                -- ponytail: Lyx Tuner lives in the transport only. Gridbox's
                -- "drag the box onto another window to attach it there" is
                -- switched off: a window popping up under the mouse (big
                -- tuner, settings) kept triggering its attach prompt.
                -- Remove `false and` to bring it back.
                if false and hover_hwnd and hover_hwnd ~= window_hwnd then
                    prev_attach_hwnd = prev_attach_hwnd or window_hwnd
                    EndIntercepts()
                    InvalidateBoxRect()
                    reaper.JS_Composite_Delay(window_hwnd, 0, 0, 0)
                    -- Redraw previous area
                    window_hwnd = hover_hwnd
                    reaper.JS_Window_SetFocus(hover_hwnd)

                    -- Get relative position to bitmap top left corner
                    local drag_x_diff = drag_x - box_x
                    local drag_y_diff = drag_y - box_y

                    -- Get new mouse window position
                    m_x, m_y = ScreenToClient(window_hwnd, mouse_x, mouse_y)

                    -- Set bitmap coordinates with relative position
                    -- Note: Avoid SetBoxCoords as it doesn't allow going out
                    -- of bounds
                    box_x = m_x - drag_x_diff
                    box_y = m_y - drag_y_diff
                    drag_x = box_x + drag_x_diff
                    drag_y = box_y + drag_y_diff

                    StartIntercepts()

                    -- Remeasure window size
                    local _, w, h = reaper.JS_Window_GetClientSize(window_hwnd)
                    window_w, window_h = w, h

                    -- Avoid edge attachment
                    prev_window_w = nil
                    is_resize = true
                else
                    -- Move box inside window
                    local new_box_x = box_x + m_x - drag_x
                    local new_box_y = box_y + m_y - drag_y
                    SetBoxCoords(new_box_x, new_box_y)
                end
                if m_x > 0 and m_y > 0 and m_x < window_w and m_y < window_h then
                    SetCursor(move_cursor)
                    resize_flags = -1
                    resize_cursor = nil
                end
            end
            drag_x = m_x
            drag_y = m_y
            is_left_click = false
        end

        local m = Scale(4, measure_scale)
        is_hovered = m_x > box_x - m and m_y > box_y - m and
            m_x < box_x + box_w + m and m_y < box_y + box_h + m

        if is_hovered and hover_hwnd == window_hwnd then
            StartIntercepts()
            PeekIntercepts(m_x, m_y)
            if is_edit_mode and not drag_x and not swing_drag_x then
                local new_resize = 0
                local cursor = normal_cursor

                local diff_l = math.abs(box_x - m_x)
                local diff_t = math.abs(box_y - m_y)
                local diff_r = math.abs(box_x + box_w - m_x)
                local diff_b = math.abs(box_y + box_h - m_y)

                if diff_l < m then
                    new_resize = 1
                    cursor = horz_resize_cursor
                end

                if diff_t < m then
                    new_resize = 2
                    cursor = vert_resize_cursor
                end

                if diff_r < m then
                    new_resize = 4
                    cursor = horz_resize_cursor
                end

                if diff_b < m then
                    new_resize = 8
                    cursor = vert_resize_cursor
                end

                local d_m = 2 * m

                if diff_l < d_m and diff_t < d_m then
                    new_resize = 3
                    cursor = diag2_resize_cursor
                end

                if diff_t < d_m and diff_r < d_m then
                    new_resize = 6
                    cursor = diag1_resize_cursor
                end

                if diff_r < d_m and diff_b < d_m then
                    new_resize = 12
                    cursor = diag2_resize_cursor
                end

                if diff_b < d_m and diff_l < d_m then
                    new_resize = 9
                    cursor = diag1_resize_cursor
                end

                if resize_flags ~= new_resize then
                    resize_flags = new_resize
                    resize_cursor = cursor
                    is_redraw = true
                end
            end
            if not swing_drag_x and snap_w > 0 and m_x - box_x < snap_w then
                is_snap_hovered = true
            end
            if resize_cursor then
                SetCursor(resize_cursor)
            elseif not drag_x then
                SetCursor(normal_cursor)
            end

            if is_snap_hovered then
                if m_x == prev_hover_m_x and m_y == prev_hover_m_y then
                    hover_cnt = hover_cnt + 1
                else
                    hover_cnt = 0
                end
                prev_hover_m_x, prev_hover_m_y = m_x, m_y

                if hover_cnt > 11 then
                    local tooltip = TunerTooltip()
                    if tooltip ~= prev_tooltip then
                        prev_tooltip = tooltip
                        local offs = Scale(17, measure_scale)
                        reaper.TrackCtl_SetToolTip(tooltip, mouse_x + offs,
                            mouse_y + offs, true)
                    end
                elseif prev_tooltip then
                    prev_tooltip = nil
                end
            end
        else
            is_left_click = false
            is_right_click = false
            if resize_flags > 0 and not drag_x then
                resize_flags = 0
                resize_cursor = nil
                is_redraw = true
            end
            EndIntercepts()
        end

        -- Release drags / left clicks / right clicks
        if drag_x and reaper.JS_Mouse_GetState(3) == 0 then
            -- Check if new attached window is valid
            if drag_x and prev_attach_hwnd and window_hwnd ~= prev_attach_hwnd then
                local is_reset = false
                local target_hwnd = window_hwnd
                local title = reaper.JS_Window_GetTitle(target_hwnd)

                local child_id = nil
                -- If window has no title, check if window has ID and parent has title
                if title == '' then
                    local parent_hwnd = reaper.JS_Window_GetParent(target_hwnd)
                    if reaper.ValidatePtr(parent_hwnd, 'HWND*') then
                        local id = reaper.JS_Window_GetLong(target_hwnd, 'ID')
                        id = tonumber(id)
                        if id and id > 0 then
                            child_id = id
                            title = reaper.JS_Window_GetTitle(parent_hwnd)
                            target_hwnd = parent_hwnd
                        end
                    end
                end

                -- Do not allow windows with empty titles
                if title == '' then
                    local msg = 'Can not attach %s to this window.\n\n\z
                        Window does not have a title.'
                    reaper.MB(msg:format(box_name), 'Notice', 0)
                    is_reset = true
                end

                -- Do not allow titles with newline characters
                if not is_reset and title:match('\n') then
                    local msg = 'Can not attach %s to this window.\n\n\z
                        Invalid window title:\n\nTITLE: %s'
                    reaper.MB(msg:format(box_name, title), 'Notice', 0)
                end

                local found_hwnd
                if not is_reset then
                    -- Check if new attached window can be found via Window_Find
                    local window_cnt, list = reaper.JS_Window_ListFind(title, 1)
                    if window_cnt > 1 then
                        local msg = 'Can not attach %s to this window. \z
                            %d windows have the same title!\n\n\z
                            TITLE: %s\n\nIf this window is a toolbar, make sure \z
                            that it is only open once (not in toolbar docker) and \z
                            consider giving it a unique title.'
                        msg = msg:format(box_name, window_cnt, title)
                        reaper.MB(msg, 'Notice', 0)
                        is_reset = true
                    elseif window_cnt == 0 then
                        local msg = 'Can not attach %s to this window.\z
                            \n\nCould not find window by title.\n\nTITLE: %s'
                        reaper.MB(msg:format(box_name, title), 'Notice', 0)
                        is_reset = true
                    else
                        found_hwnd = reaper.JS_Window_HandleFromAddress(list)
                        if found_hwnd ~= target_hwnd then
                            local msg = 'Can not attach %s to this \z
                                window.\n\nHandle missmatch'
                            reaper.MB(msg:format(box_name), 'Notice', 0)
                            is_reset = true
                        end
                    end
                end

                if not is_reset then
                    is_reset = true
                    -- Save accessible windows by custom ID instead of title
                    if target_hwnd == main_hwnd then
                        title = 'REAPER Main Window'
                    end
                    if target_hwnd == reaper.MIDIEditor_GetActive() then
                        title = 'Active MIDI editor'
                    end

                    -- Prompt user to confirm new attachment
                    local msg = '%s will be attached to this window:\z
                            \n\nTITLE: %s%s\n\nProceed?'
                    local id_text = ''
                    if child_id then id_text = ('\nID: %d'):format(child_id) end
                    msg = msg:format(box_name, title, id_text)

                    local ret = reaper.MB(msg, 'Notice', 4)
                    if ret == 6 then
                        -- Save info on new attachment for next script startup
                        SaveAttachedWindow(title, child_id)
                        is_reset = false
                    end
                end

                if is_reset then
                    -- Move box back to previous window (pre-drag)
                    EndIntercepts()
                    InvalidateBoxRect()
                    reaper.JS_Composite_Delay(window_hwnd, 0, 0, 0)

                    window_hwnd = prev_attach_hwnd
                    reaper.JS_Window_SetFocus(prev_attach_hwnd)

                    box_w = prev_box_w
                    box_h = prev_box_h
                    box_x = prev_box_x
                    box_y = prev_box_y

                    StartIntercepts()

                    -- Remeasure window size
                    local _, w, h = reaper.JS_Window_GetClientSize(window_hwnd)
                    window_w, window_h = w, h

                    -- Avoid edge attachment
                    prev_window_w = nil
                    is_resize = true
                end
            end
            EnsureBoxVisible()
            UpdateAttachPosition()
            SaveThemeSettings(color_theme)
            drag_x = nil
            drag_y = nil
            is_redraw = true
            prev_attach_hwnd = nil
            prev_box_w = nil
            prev_box_h = nil
            prev_box_x = nil
            prev_box_y = nil
        end
    else
        EndIntercepts()
    end


    -- (the tuner's periodic work runs at the top of Main, so that it still
    -- happens while the transport window is hidden)

    -- step aside if a neighbor box (GridBox, ChordBox...) starts on our spot
    AvoidNeighbors()

    if is_resize then
        -- Prepare LICE bitmap for drawing
        if bitmap then reaper.JS_LICE_DestroyBitmap(bitmap) end
        if snap_bitmap then reaper.JS_LICE_DestroyBitmap(snap_bitmap) end
        if bg_bitmap then reaper.JS_LICE_DestroyBitmap(bg_bitmap) end

        local bm_w, bm_h = GetBitmapSize()
        bitmap = reaper.JS_LICE_CreateBitmap(true, bm_w, bm_h)
        snap_bitmap = nil
        bg_bitmap = nil

        local font_family = user_font_family or 'Arial'
        -- Binary search to find font size that fits target height
        local default_h = Scale(14, draw_scale)
        local target_h = math.max(math.min(default_h, bm_h), bm_h // 2.5)
        if user_font_height then target_h = math.min(user_font_height, bm_h) end

        local lo, hi, mid = 1, target_h * 2, nil
        font_size = lo
        while lo <= hi do
            mid = math.floor((lo + hi) / 2)
            gfx.setfont(1, font_family, mid)
            local curr_h = math.max(1, select(2, gfx.measurechar(70)))
            if curr_h <= target_h then
                font_size = mid
                lo = mid + 1
            else
                hi = mid - 1
            end
        end
        if font_size ~= mid then gfx.setfont(1, font_family, font_size) end
        MeasureGlyphs()

        -- Create LICE font
        if lice_font then reaper.JS_LICE_DestroyFont(lice_font) end
        lice_font = reaper.JS_LICE_CreateFont()

        local GDI_CreateFont = reaper.JS_GDI_CreateFont
        local font_weight = user_font_weight or 0
        local gdi = GDI_CreateFont(font_size, font_weight, 0, 0, 0, 0,
            font_family)
        reaper.JS_LICE_SetFontFromGDI(lice_font, gdi, '')
        reaper.JS_GDI_DeleteObject(gdi)

        -- Set bitmap draw coordinates
        reaper.JS_Composite_Delay(window_hwnd, comp_delay, comp_delay * 1.5, 2)
        reaper.JS_Composite(window_hwnd, box_x, box_y, box_w, box_h, bitmap,
            0, 0, bm_w, bm_h)
        is_resize = false
        is_redraw = true
    end


    if snap_w > 0 and is_snap_hovered ~= prev_is_snap_hovered then
        prev_is_snap_hovered = is_snap_hovered
        is_redraw = true
    end

    if is_redraw then
        DrawBitmap(bitmap, GetBitmapSize())
        InvalidateBoxRect()
        is_redraw = false
    end

    reaper.defer(Main)
end

reaper.SetToggleCommandState(sec, cmd, 1)
reaper.RefreshToolbar2(sec, cmd)


function Exit()
    CloseSettings()
    -- the companion toggle action checks this to know we are here
    reaper.SetExtState(extname, 'alive', '', false)
    reaper.SetExtState(extname, 'is_live', '0', false)
    reaper.SetExtState(extname, 'request', '', false)
    SetToggleActionState(0)

    SetThemeIntegration(0)
    reaper.SetToggleCommandState(sec, cmd, 0)
    reaper.RefreshToolbar2(sec, cmd)

    -- Removal is by tag, so nothing the user made is ever deleted.
    RemoveAllTunerTracks()

    if bitmap then reaper.JS_LICE_DestroyBitmap(bitmap) end
    if snap_bitmap then reaper.JS_LICE_DestroyBitmap(snap_bitmap) end
    if bg_bitmap then reaper.JS_LICE_DestroyBitmap(bg_bitmap) end
    if lice_font then reaper.JS_LICE_DestroyFont(lice_font) end
    if reaper.ValidatePtr(window_hwnd, 'HWND*') then
        reaper.JS_Composite_Delay(window_hwnd, 0, 0, 0)
        InvalidateBoxRect()
        EndIntercepts()
    end
end

if attach_window_title then
    local is_reset = false
    -- Give option to move box back to transport when attached window
    -- is not found upon script startup (or when multiple windows are found)
    local window_cnt = 0
    window_hwnd, window_cnt = FindAttachedWindow()

    if window_cnt > 1 then
        local msg = 'Found %d windows with the same title.\n\n\z
            Move %s back to transport?'
        local ret = reaper.MB(msg:format(window_cnt, box_name), box_name, 4)
        is_reset = ret == 6
        ExtSave('start_cnt', nil)
    end

    if not window_hwnd and not WaitForAttachedWindow() then
        local msg = 'Could not find window.\n\nTITLE: %s\n\nWait for \z
            window to open?'
        local ret = reaper.MB(msg:format(attach_window_title), box_name, 4)
        is_reset = ret ~= 6
        if is_reset then
            msg = 'Moved %s back to transport'
            reaper.MB(msg:format(box_name), box_name, 0)
        end
        ExtSave('start_cnt', nil)
    end

    -- Give option to move box back to transport when user quickly toggles
    -- the script 3 times in a row (in 3 seconds)
    local curr_time = reaper.time_precise()
    local start_cnt = tonumber(ExtLoad('start_cnt', 1)) or 1
    local start_time = tonumber(ExtLoad('start_time', curr_time)) or curr_time

    -- Check if more than 3 seconds have passed
    if math.abs(start_time - curr_time) > 3 then
        start_cnt = 1
        ExtSave('start_cnt', nil)
        ExtSave('start_time', nil)
    else
        start_cnt = start_cnt + 1
        -- Check if script has started 3 times
        if start_cnt > 3 then
            start_cnt = nil
            curr_time = nil
            local msg = 'Move %s back to transport?'
            local ret = reaper.MB(msg:format(box_name), box_name, 4)
            is_reset = ret == 6
        end
        ExtSave('start_cnt', start_cnt)
        ExtSave('start_time', curr_time)
    end

    -- Move box back to transport
    if is_reset then
        SaveAttachedWindow(nil)
        EndIntercepts()
        window_hwnd = nil
        prev_top_window_cnt = nil
    end
end



-- Restore the tuner state from the last session. A fresh install starts
-- OFF on purpose: switching the tuner on inserts a track, which marks the
-- project as modified, and nobody should get a "save changes?" prompt from
-- a script they only just installed and have not used yet.
SetTunerEnabled(reaper.GetExtState(extname, 'is_on') == '1')

reaper.atexit(Exit)
reaper.defer(Main)
