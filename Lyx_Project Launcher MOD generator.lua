--[[
    Lyx_Project Launcher MOD generator
    -----------------------------------
    Makes a Lyx-flavoured copy of Reapertips' "Project Launcher" WITHOUT
    touching the original file. It reads the original, applies a set of small
    patches, and writes a new script:

        Lyx_Project Launcher (themed).lua   (next to this generator)

    What the MOD adds
    -----------------
    1. Colours come from your Lyx Global Theme Manager (read live at runtime).
    2. A "Lyx global theme" button in Settings > APPEARANCE opens the manager.
    3. Multi-select in the list: Shift+click = range, Cmd/Ctrl+click = toggle.
       Enter / double-click / Open opens EVERY selected project (each as a new
       tab). A billboard (home BBB) notice says what is loading.
    4. When "Keep the window open" is OFF, the window closes BEFORE loading,
       for every open mode (tab, current, new version, offline, ...).
    5. While focused it claims the keyboard, so Esc/Enter/Cmd+F/Cmd+D reach
       the launcher instead of REAPER.
    6. It joins the Lyx ESC handshake, so Lyx_ESC.lua can close it like your
       other Lyx GUIs.

    Staying update-proof
    --------------------
    - Colours are read live, so recolouring in the Theme Manager needs NO
      regeneration - just reopen the launcher.
    - Re-run THIS generator only when the original Project Launcher updates.
      Every patch below is a checked "anchor": if an update moved one, the
      generator refuses and names it, instead of writing a broken script.
      Then ping me to update the anchors.

    Run it from the REAPER Actions list (add this .lua once).
]]

local R = reaper

------------------------------------------------------------------------------
-- Paths (edit only if you move your install)
------------------------------------------------------------------------------
local SRC = '/Applications/REAPER/Scripts/Reapertips/Utility/Reapertips_Project Launcher.lua'
local OUT = '/Applications/REAPER/Scripts/Lyx Scripts/Lyx_Project Launcher (themed).lua'
-- Folder holding _Lyx_Theme.lua and _Lyx_HOME.lua, baked into the themed copy.
local LYX_LIB = '/Applications/REAPER/Scripts/Lyx Scripts/_lib'

local EXT = 'Lyx.PLMod'          -- ExtState namespace, for update detection

------------------------------------------------------------------------------
-- Runtime-referenced anchors: names the injected code calls but does NOT
-- replace. If any vanished in an update, the bridge would misbehave, so we
-- stop up front with a clear message.
------------------------------------------------------------------------------
local RUNTIME_ANCHORS = {
    { name = 'rgba() helper',       pat = 'local function rgba%(' },
    { name = 'palette table (C)',   pat = '\nlocal C = {}' },
    { name = 'SB.build_palette()',  pat = 'function SB%.build_palette%(%)' },
    { name = 'SB.ink_accent()',     pat = 'function SB%.ink_accent%(' },
    { name = 'SB.state()',          pat = 'function SB%.state%(%)' },
    { name = 'set_sel() helper',    pat = 'local function set_sel%(' },
    { name = 'selected() helper',   pat = 'local function selected%(' },
    { name = 'MOD_CMD',             pat = 'local MOD_CMD' },
    { name = 'palette end marker',  pat = 'C%.clear%s*=%s*rgba%(0x000000, 0x00%)' },
}

------------------------------------------------------------------------------
-- Literal patches. Each `find` must appear EXACTLY once in the original; that
-- uniqueness check IS the anchor check for these edits.
------------------------------------------------------------------------------
local PATCHES = {
    -- (2) Settings > APPEARANCE: button that opens the Theme Manager.
    {
        name = 'Settings APPEARANCE button',
        find = "ImGui.TextColored(ctx, C.text_faint, 'APPEARANCE')",
        repl = "ImGui.TextColored(ctx, C.text_faint, 'APPEARANCE')\n" ..
               "    if ImGui.Button(ctx, 'Lyx global theme') then\n" ..
               "        pcall(function() require('_Lyx_Theme').open_manager() end)\n" ..
               "    end\n" ..
               "    hint('Opens the Lyx Global Theme Manager. Colours here follow it')\n" ..
               "    ImGui.Dummy(ctx, 1, PX(2))",
    },

    -- (3a) Row highlight: a row counts as selected if it is the focus OR in
    -- the multi-select set.
    {
        name = 'list Selectable (selected flag)',
        find = "if ImGui.Selectable(ctx, '##' .. item.path, S.sel == i,",
        repl = "if ImGui.Selectable(ctx, '##' .. item.path, SB.is_sel(item.path, i),",
    },
    -- (3b) Accent bar drawn for every selected row.
    {
        name = 'list accent bar (selected flag)',
        find = "                        if S.sel == i then",
        repl = "                        if SB.is_sel(item.path, i) then",
    },
    -- (3c) Left-click routes through the multi-select handler.
    {
        name = 'list click handler',
        find = "                                set_sel(i)",
        repl = "                                SB.click_select(i)",
    },

    -- (3e) Keyboard nav: a plain arrow returns to single select; Shift+arrow
    -- extends the multi-select range from the anchor. Covers Up/Down/Page/
    -- Home/End (they all route through move_sel).
    {
        name = 'move_sel() keyboard',
        find = table.concat({
            "local function move_sel(delta)",
            "    if #S.shown == 0 then return end",
            "    set_sel(math.max(1, math.min(#S.shown, S.sel + delta)))",
            "    S.scroll_to = true",
            "end",
        }, "\n"),
        repl = table.concat({
            "local function move_sel(delta)",
            "    if #S.shown == 0 then return end",
            "    local target = math.max(1, math.min(#S.shown, S.sel + delta))",
            "    -- ctx is declared further down the file, so the mod read lives in",
            "    -- SB.shift_down() (defined at EOF, where ctx is in scope).",
            "    local shift = SB.shift_down()",
            "    if shift then",
            "        local anchor = S.multi_anchor or S.sel",
            "        S.multi_anchor, S.multi = anchor, {}",
            "        local lo, hi = math.min(anchor, target), math.max(anchor, target)",
            "        for k = lo, hi do local it = S.shown[k]; if it then S.multi[it.path] = true end end",
            "    else",
            "        S.multi, S.multi_anchor = {}, target",
            "    end",
            "    set_sel(target)",
            "    S.scroll_to = true",
            "end",
        }, "\n"),
    },

    -- (1/4) do_open: open EVERY selected project; BBB notice; close-first.
    {
        name = 'do_open()',
        find = table.concat({
            "local function do_open(mode)",
            "    local item = selected()",
            "    if not item then return end",
            "    SB.later(function()",
            "        if SB.open(item, mode) and not SB.cfg.keep_open then",
            "            S.quit = true",
            "        end",
            "    end)",
            "end",
        }, "\n"),
        repl = table.concat({
            "local function do_open(mode)",
            "    local items = {}",
            "    if S.multi and next(S.multi) then",
            "        for _, it in ipairs(S.shown) do",
            "            if S.multi[it.path] then items[#items + 1] = it end",
            "        end",
            "    end",
            "    if #items == 0 then local it = selected(); if it then items[1] = it end end",
            "    if #items == 0 then return end",
            "    local keep  = SB.cfg.keep_open",
            "    SB.log(('do_open mode=%s keep=%s items=%d'):format(tostring(mode), tostring(keep), #items))",
            "    local function run()",
            "        local opened = 0",
            "        for _, it in ipairs(items) do",
            "            -- more than one at once: force each into its own tab",
            "            local m = (#items > 1 and it.kind == 'project') and 'tab' or mode",
            "            SB.log('  SB.open start: ' .. tostring(it.path) .. ' as ' .. tostring(m))",
            "            if SB.open(it, m) then opened = opened + 1 end",
            "            SB.log('  SB.open done')",
            "        end",
            "        pcall(SB.notify_open, items, opened)",
            "        -- 'online' starts an FX job after the window closed: restart",
            "        -- the loop so its progress window can run",
            "        if not keep and SB.fx_job then SB.resume_loop() end",
            "    end",
            "    -- every open mode (tab/current/new version/offline/online/...)",
            "    if keep then",
            "        SB.later(function() run(); if not keep then S.quit = true end end)",
            "    else",
            "        -- not keeping the window open: close it first, THEN load",
            "        S.quit = true",
            "        SB.log('  S.quit set, closing first')",
            "        -- wait until ReaImGui has really destroyed the window (ctx",
            "        -- garbage-collected), max 1 s, then load",
            "        -- ctx dying is not enough on macOS: the OS window is only taken",
            "        -- off screen on a later run-loop pass, and loading blocks that.",
            "        -- So wait CLOSE_GRACE seconds more after it is gone.",
            "        -- ponytail: fixed grace; raise it if the window still lingers",
            "        local CLOSE_GRACE = 0.15",
            "        local ticks, t0, t_dead = 0, reaper.time_precise(), nil",
            "        local function go()",
            "            ticks = ticks + 1",
            "            local now = reaper.time_precise()",
            "            local alive = SB.ctx_alive()",
            "            if not alive and not t_dead then t_dead = now end",
            "            SB.log(('  wait tick %d  %.3fs  ctx_alive=%s'):format(ticks, now - t0, tostring(alive)))",
            "            local ready = t_dead and now - t_dead >= CLOSE_GRACE",
            "            if not ready and now - t0 < 1.5 then reaper.defer(go) else run() end",
            "        end",
            "        reaper.defer(go)",
            "    end",
            "end",
        }, "\n"),
    },

    -- (6) Turn off ImGui's built-in arrow-key focus navigation (the roaming
    -- blue focus box); the launcher drives the arrows itself.
    {
        name = 'disable keyboard nav',
        find = "    ImGui.SetConfigVar(ctx, ImGui.ConfigVar_WindowsMoveFromTitleBarOnly, 0)",
        repl = "    ImGui.SetConfigVar(ctx, ImGui.ConfigVar_WindowsMoveFromTitleBarOnly, 0)\n" ..
               "    pcall(function()\n" ..
               "        local nav = ImGui.ConfigFlags_NavEnableKeyboard or 0\n" ..
               "        local f = ImGui.GetConfigVar(ctx, ImGui.ConfigVar_Flags)\n" ..
               "        ImGui.SetConfigVar(ctx, ImGui.ConfigVar_Flags, f & ~nav)\n" ..
               "    end)",
    },

    -- (7) Keyboard capture. With ImGui keyboard nav off (patch 6), ReaImGui
    -- no longer claims the keyboard, so Esc / Enter / Cmd+F / Cmd+D leaked
    -- to REAPER and never reached the launcher. Claim it while focused.
    {
        name = 'frame keyboard capture',
        find = "    if S.dirty then SB.refilter() end\n\n    handle_keys()",
        repl = "    if S.dirty then SB.refilter() end\n\n" ..
               "    local _foc = ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_AnyWindow)\n" ..
               "    if _foc ~= SB._foc_prev then SB._foc_prev = _foc; SB.log('window focused=' .. tostring(_foc)) end\n" ..
               "    if _foc then\n" ..
               "        ImGui.SetNextFrameWantCaptureKeyboard(ctx, true)\n" ..
               "    end\n" ..
               "    if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then\n" ..
               "        SB.log(('Esc seen  settings=%s naming=%s adding_root=%s query=%q'):format(\n" ..
               "            tostring(S.settings_open), tostring(S.naming), tostring(S.adding_root), tostring(S.query)))\n" ..
               "    end\n" ..
               "    handle_keys()",
    },

    -- (5) ESC handshake inside the main loop, right after the heartbeat write.
    {
        name = 'loop heartbeat (ESC handshake)',
        find = "    reaper.SetExtState(SB.EXTNAME, 'heartbeat',\n        tostring(reaper.time_precise()), false)",
        repl = "    reaper.SetExtState(SB.EXTNAME, 'heartbeat',\n        tostring(reaper.time_precise()), false)\n" ..
               "    -- Lyx ESC handshake: let Lyx_ESC.lua close this like other Lyx GUIs\n" ..
               "    SB._esc_handled = SB._esc_handled or reaper.time_precise()\n" ..
               "    reaper.SetExtState('Lyx_GUI', 'alive', tostring(reaper.time_precise()), false)\n" ..
               "    local _esc_t = tonumber(reaper.GetExtState('Lyx_GUI', 'close'))\n" ..
               "    if _esc_t and _esc_t > SB._esc_handled then SB._esc_handled = _esc_t; S.quit = true end",
    },

    -- (3d) Keep the multi-select set consistent when the list is rebuilt:
    -- drop any path that is no longer shown.
    {
        name = 'restore_sel (prune multi)',
        find = "    SB.restore_sel()\n    if S.sel > #S.shown then S.sel = #S.shown end",
        repl = "    SB.restore_sel()\n" ..
               "    if S.multi then\n" ..
               "        local keep = {}\n" ..
               "        for _, it in ipairs(S.shown) do if S.multi[it.path] then keep[it.path] = true end end\n" ..
               "        S.multi = keep\n" ..
               "    end\n" ..
               "    if S.sel > #S.shown then S.sel = #S.shown end",
    },
}

------------------------------------------------------------------------------
-- Theme bridge: inserted right after build_palette()'s end. Overlays the Lyx
-- palette onto C. Wrapped in pcall; on any failure it leaves the original
-- colours in place (never nil-crashes). %q = the lib folder.
------------------------------------------------------------------------------
local THEME_BRIDGE = ([==[

------------------------------------------------------------------------------
-- Lyx theme bridge (added by the generator; do not edit)
------------------------------------------------------------------------------
do
    local LYX_LIB = %q
    package.path = package.path .. ';' .. LYX_LIB .. '/?.lua'

    local function lum(rgb)
        local r, g, b = (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF
        return 0.299 * r + 0.587 * g + 0.114 * b
    end
    local function mix(a, b, t)
        local ar, ag, ab = (a >> 16) & 0xFF, (a >> 8) & 0xFF, a & 0xFF
        local br, bg, bb = (b >> 16) & 0xFF, (b >> 8) & 0xFF, b & 0xFF
        local r  = math.floor(ar + (br - ar) * t + 0.5)
        local g  = math.floor(ag + (bg - ag) * t + 0.5)
        local bl = math.floor(ab + (bb - ab) * t + 0.5)
        return (r << 16) | (g << 8) | bl
    end
    local function lyx_colors()
        local ok, T = pcall(require, '_Lyx_Theme')
        if not ok or not T or not T.load then return nil end
        local ok2, db = pcall(T.load)
        if not ok2 or not db or not db.themes then return nil end
        local th = db.themes[db.current]
        if not th or not th.colors then return nil end
        return th.colors               -- bg bg2 base title subtitle accent text
    end

    local orig_build = SB.build_palette
    function SB.build_palette()
        orig_build()                   -- fill C with the original defaults first
        pcall(function()
            local c = lyx_colors()
            if not c or not c.bg or not c.text or not c.accent then return end
            local bg, text, accent = c.bg, c.text, c.accent
            local title = c.title or text
            local base  = c.base  or mix(bg, text, 0.3)
            local bg2   = c.bg2   or mix(bg, 0x000000, 0.25)

            local light = lum(bg) > 140
            local ink   = light and 0x000000 or 0xFFFFFF
            local acc   = light and SB.ink_accent(accent) or accent

            SB.light, SB.ink, SB.accent_rgb = light, ink, accent

            C.win         = rgba(bg)
            C.child       = rgba(bg)
            C.popup       = rgba(bg2)
            C.accent      = rgba(acc)
            C.accent_dim  = rgba(accent, light and 0x33 or 0x29)
            C.accent_soft = rgba(accent, light and 0x4D or 0x3D)
            C.text        = rgba(text)
            C.text_bright = rgba(title)
            C.text_dim    = rgba(mix(text, bg, 0.35))
            C.text_faint  = rgba(mix(text, bg, 0.55))
            C.line        = rgba(base)
            C.border      = rgba(0x000000, light and 0x30 or 0x8C)
            C.dim_bg      = rgba(0x000000, light and 0x40 or 0x88)
            C.frame       = rgba(ink, 0x0D)
            C.frame_hover = rgba(ink, 0x14)
            C.button      = rgba(ink, 0x0F)
            C.button_hov  = rgba(ink, 0x18)
            C.tab_on      = rgba(ink, 0x12)
            C.ghost       = rgba(ink, 0x2E)
            C.row_hover   = rgba(ink, 0x0C)
        end)
    end
    pcall(SB.build_palette)            -- refresh so frame 1 is themed
end
]==]):format(LYX_LIB)

------------------------------------------------------------------------------
-- Interaction bridge: appended at END OF FILE, where set_sel / selected / S /
-- ImGui / MOD_CMD / ctx (all file-locals) are in scope. Defines the SB
-- functions the patches above call.
------------------------------------------------------------------------------
local INTERACTION_BRIDGE = ([==[

------------------------------------------------------------------------------
-- Lyx interaction bridge (added by the generator; do not edit)
------------------------------------------------------------------------------
do
    package.path = package.path .. ';' .. %q .. '/?.lua'

    -- Debug logger -> REAPER console. Set to false to silence.
    SB.DEBUG = true
    function SB.log(msg)
        if SB.DEBUG then
            reaper.ShowConsoleMsg(('[PL %%.3f] %%s\n'):format(reaper.time_precise(), msg))
        end
    end
    SB.log('Lyx themed MOD loaded')

    -- false once ReaImGui has garbage-collected the context (window gone)
    function SB.ctx_alive()
        return ImGui.ValidatePtr(ctx, 'ImGui_Context*')
    end

    -- do_open sits above loop's declaration; reach it from here.
    function SB.resume_loop() reaper.defer(loop) end

    -- Shift state, read here because ctx is in scope at end of file (move_sel
    -- sits above ctx's declaration and cannot see it).
    function SB.shift_down()
        return (ImGui.GetKeyMods(ctx) & (ImGui.Mod_Shift or 0)) ~= 0
    end

    -- A row is selected when it is in the multi set (if any rows are), else
    -- when it is the single focus. One rule for every highlight + open path.
    function SB.is_sel(path, i)
        local S = SB.state()
        if S.multi and next(S.multi) then return S.multi[path] == true end
        return S.sel == i
    end

    -- Shift+click = range from the anchor; Cmd/Ctrl+click = toggle; plain = one.
    function SB.click_select(i)
        local S     = SB.state()
        local mods  = ImGui.GetKeyMods(ctx)
        local SHIFT = ImGui.Mod_Shift or 0
        local shift = (mods & SHIFT) ~= 0
        local cmd   = (mods & MOD_CMD) ~= 0 or (mods & ImGui.Mod_Ctrl) ~= 0
        S.multi = S.multi or {}
        if shift then
            local anchor = S.multi_anchor or S.sel or i
            S.multi_anchor, S.multi = anchor, {}
            local lo, hi = math.min(anchor, i), math.max(anchor, i)
            for k = lo, hi do
                local it = S.shown[k]
                if it then S.multi[it.path] = true end
            end
            set_sel(i)
        elseif cmd then
            -- fold the current single focus into the set so it is kept...
            if not next(S.multi) then
                local cur = S.shown[S.sel]
                if cur then S.multi[cur.path] = true end
            end
            -- ...then toggle the clicked row
            local it = S.shown[i]
            if it then
                if S.multi[it.path] then S.multi[it.path] = nil
                else S.multi[it.path] = true end
            end
            if it and S.multi[it.path] then
                set_sel(i)
            else
                -- clicked row turned off: move focus to a remaining member,
                -- or fall back to a plain single selection
                local moved
                for k, row in ipairs(S.shown) do
                    if S.multi[row.path] then set_sel(k); moved = true; break end
                end
                if not moved then S.multi = {}; set_sel(i) end
            end
            S.multi_anchor = i
        else
            S.multi, S.multi_anchor = {}, i
            set_sel(i)
        end
    end

    -- Billboard notice via the home BBB function.
    function SB.notify_open(items, opened)
        pcall(require, '_Lyx_HOME')         -- defines the global BBB
        if type(_G.BBB) ~= 'function' then return end
        local it = items[1]
        local msg = (#items <= 1)
            and ('Project Launcher  -  ' .. (it and (it.name or it.path) or ''))
            or  ('Project Launcher  -  opening ' .. tostring(opened or #items) .. ' projects')
        pcall(_G.BBB, msg)
    end
end
]==]):format(LYX_LIB)

------------------------------------------------------------------------------
-- File helpers
------------------------------------------------------------------------------
local function read_file(path)
    local f = io.open(path, 'rb'); if not f then return nil end
    local d = f:read('a'); f:close(); return d
end
local function write_file(path, data)
    local f = io.open(path, 'wb'); if not f then return false end
    f:write(data); f:close(); return true
end
local function signature(s)
    local h = 2166136261
    for i = 1, #s do h = (h ~ s:byte(i)) * 16777619 % 4294967296 end
    return #s .. ':' .. string.format('%08x', math.floor(h))
end

-- Literal, single-occurrence replace. Returns new src, or nil + reason.
local function patch_one(src, p)
    local i = src:find(p.find, 1, true)
    if not i then return nil, p.name .. ' (not found)' end
    if src:find(p.find, i + #p.find, true) then
        return nil, p.name .. ' (found more than once)'
    end
    return src:sub(1, i - 1) .. p.repl .. src:sub(i + #p.find)
end

------------------------------------------------------------------------------
-- Generate
------------------------------------------------------------------------------
local function fail(msg)
    R.MB('The original Project Launcher changed in a way this MOD does not ' ..
         'recognise:\n\n  - ' .. msg ..
         '\n\nYour existing themed copy was left untouched. Send this message ' ..
         'to Andy\'s assistant to update the generator.',
         'Lyx MOD generator', 0)
end

local function generate()
    local src = read_file(SRC)
    if not src then
        R.MB('Could not read the original at:\n\n' .. SRC ..
             '\n\nFix the SRC path at the top of this generator.',
             'Lyx MOD generator', 0)
        return
    end
    local orig_sig = signature(src)

    -- Runtime anchors
    local missing = {}
    for _, a in ipairs(RUNTIME_ANCHORS) do
        if not src:find(a.pat) then missing[#missing + 1] = a.name end
    end
    if #missing > 0 then fail(table.concat(missing, '\n  - ')); return end

    -- Literal patches
    for _, p in ipairs(PATCHES) do
        local out, why = patch_one(src, p)
        if not out then fail(why); return end
        src = out
    end

    -- Insert the theme bridge right after build_palette()'s closing `end`.
    local _, e = src:find('C%.clear%s*=%s*rgba%(0x000000, 0x00%).-\nend')
    if not e then fail('palette end (build_palette close)'); return end
    src = src:sub(1, e) .. THEME_BRIDGE .. src:sub(e + 1)

    -- Append the interaction bridge at the very end.
    local patched = '-- Lyx-flavoured MOD of Project Launcher. GENERATED - do not edit.\n'
        .. '-- Re-run "Lyx_Project Launcher MOD generator" after the original updates.\n'
        .. src .. INTERACTION_BRIDGE

    if not write_file(OUT, patched) then
        R.MB('Could not write the themed copy to:\n\n' .. OUT,
             'Lyx MOD generator', 0)
        return
    end

    local prev = R.GetExtState(EXT, 'src_sig')
    R.SetExtState(EXT, 'src_sig', orig_sig, true)
    local note = (prev == '' and 'First build.')
        or (prev == orig_sig and 'Original unchanged since last build (rebuilt anyway).')
        or 'Original had updated - picked up the new version.'

    R.MB('Done. ' .. note .. '\n\nThemed copy written to:\n' .. OUT ..
         '\n\nAdd it to the Actions list and run it.',
         'Lyx MOD generator', 0)
end

generate()
