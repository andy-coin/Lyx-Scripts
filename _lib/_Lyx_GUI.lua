--[[
    _Lyx_GUI.lua  —  shared ReaImGui look & loop for Lyx scripts.

    Theme: the Lyx global theme (_Lyx_Theme.lua, edited in "Lyx_Global theme manager.lua")
    when the script's "Inherit" flag is on (default). With Inherit off it falls back to the
    old colours of r.GetUserInputs' "Set" popup (ExtState "Lyx_GetUserInputs": bg / fg /
    accent / scale). Running GUIs reload about once per second after the theme is saved.

    usage:
        local G   = require("_lib._Lyx_GUI")
        local ctx = G.new("My tool")          -- nil if ReaImGui missing
        G.run(ctx, "My tool", function(ctx) ... return false to close ... end,
              { w = 420, h = 300, on_close = fn })

    Script with its own ImGui context (no G.new / G.run):
        G.load_theme("My tool")               -- once (key = inherit flag key)
        each frame: G.poll(); G.push_theme(ctx); ...Begin/End...; G.pop_theme(ctx)
]]

local R = reaper
local T = require("_lib._Lyx_Theme")
local G = {}
local LEGACY = "Lyx_GetUserInputs"

local function num(k, d) return tonumber(R.GetExtState(LEGACY, k)) or d end

G.mix = T.mix

-- 0xRRGGBB -> ImGui 0xRRGGBBAA (alpha 0..255)
function G.col(h, alpha) return ((h & 0xFFFFFF) << 8) | (alpha or 0xFF) end

-- Sets every G colour field from a filled theme table (no file IO).
function G.apply(th)
    local c = th.colors
    G.theme        = th
    G.bg, G.fg     = c.bg, c.text
    G.accent       = c.accent
    G.panel        = c.bg2
    G.base         = c.base
    G.title_col    = c.title
    G.subtitle_col = c.subtitle
    G.dim          = G.mix(c.text, c.bg, 0.45)
    G.scale        = th.scale
    G.good, G.warn, G.bad = 0xA6E3A1, 0xF9E2AF, 0xF38BA8
end

-- (Re)loads the theme for this script. key: inherit-flag key (window title by default).
function G.load_theme(key)
    G.key = key or G.key
    G.inherited = G.key == nil or T.inherit(G.key)
    if G.inherited then
        G.apply(T.get())
    else
        local th = T.derive(num("bg", 0x0C2C42), num("fg", 0xE6ECFF), num("accent", 0xB5973C), -- Lyx Lake base colours
                            math.max(0.5, math.min(2.5, num("scale", 1.0))))
        G.apply(th)
    end
end
G.load_theme()

-- Live reload: checks the theme rev about once per second. Returns true when reloaded.
local next_poll = 0
function G.poll()
    local now = R.time_precise()
    if now < next_poll then return false end
    next_poll = now + 1
    if T.changed() then G.load_theme(); return true end
    return false
end

-- Lyx_ESC (the global Esc action) closes Lyx GUIs by request instead of killing their windows
-- (killing a ReaImGui window makes its script assert). Call every frame: marks this GUI alive
-- and returns true once per Esc press made after the script started. Same ExtState in non-ImGui scripts.
local ESC, handled = "Lyx_GUI", R.time_precise()
function G.esc()
    R.SetExtState(ESC, "alive", tostring(R.time_precise()), false)
    local t = tonumber(R.GetExtState(ESC, "close"))
    if t and t > handled then handled = t; return true end
    return false
end

function G.S(v) return v * G.scale end

-- Pixel font size for a design size (14 = body text), following theme font size and scale.
function G.font_size(size)
    return math.floor((size or 14) * G.theme.font.size / 14 * G.scale + 0.5)
end

-- Font for a theme font name: "" = CJK-capable font for this OS, a file path, or a family name.
local fonts = {}
local function make_font(name)
    if fonts[name] then return fonts[name] end
    local file = name
    if name == "" then
        local os_name = R.GetOS()
        file = ((os_name:find("OSX") or os_name:find("mac")) and "/System/Library/Fonts/PingFang.ttc")
            or (os_name:find("Win") and "C:/Windows/Fonts/msjh.ttc")
            or "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
    end
    local ok, font = false, nil
    if R.file_exists(file) then ok, font = pcall(R.ImGui_CreateFontFromFile, file, 0) end
    if (not ok or not font) and name ~= "" then ok, font = pcall(R.ImGui_CreateFont, name) end
    if not ok or not font then font = R.ImGui_CreateFont("sans-serif") end
    fonts[name] = font
    return font
end

-- Attaches the theme font to ctx when the theme font name changed (call outside a frame).
local font_name, attached = nil, {}
local function ensure_font(ctx)
    local name = G.theme.font.name
    if name == font_name then return end
    local font = make_font(name)
    if not attached[font] then attached[font] = pcall(R.ImGui_Attach, ctx, font) end
    if attached[font] then G.font, font_name = font, name end
end

function G.new(title, key)
    if not R.ImGui_CreateFontFromFile then -- ReaImGui 0.10+ API (PushFont with size, PushItemFlag...)
        R.MB("This script needs:\n\n- ReaImGui 0.10 or newer: Extensions > ReaPack > Browse packages > \"ReaImGui\" (update it if already installed)\n\nNo ReaPack yet? Get it at reapack.com, then restart REAPER after installing.", "Lyx Scripts", 0)
        return
    end
    G.load_theme(key or title or "Lyx")
    local ctx = R.ImGui_CreateContext(title or "Lyx")
    ensure_font(ctx)
    -- no keyboard nav: Space/Enter/arrows stay free for the scripts (same as r.GetUserInputs)
    R.ImGui_SetConfigVar(ctx, R.ImGui_ConfigVar_Flags(),
        R.ImGui_GetConfigVar(ctx, R.ImGui_ConfigVar_Flags()) & ~R.ImGui_ConfigFlags_NavEnableKeyboard())
    return ctx
end

-- Readable text colour on top of colour h (picks theme bg or text, whichever contrasts more).
function G.text_on(h)
    local function lum(x) return 0.299 * ((x >> 16) & 0xFF) + 0.587 * ((x >> 8) & 0xFF) + 0.114 * (x & 0xFF) end
    return math.abs(lum(h) - lum(G.bg)) > math.abs(lum(h) - lum(G.fg)) and G.bg or G.fg
end

-- The one theme -> ImGui mapping. Returns colour list, style var list.
local function style(th)
    local c, m, col, s = th.colors, G.mix, G.col, th.scale
    local bg, tx, ac, b2, base = c.bg, c.text, c.accent, c.bg2, c.base
    local fr, bt = th.frame.color, th.button.color
    local cols = {
        {R.ImGui_Col_WindowBg(),        col(bg, math.floor(th.alpha * 255 + 0.5))},
        {R.ImGui_Col_ChildBg(),         col(b2)},
        {R.ImGui_Col_PopupBg(),         col(b2)},
        {R.ImGui_Col_Text(),            col(tx)},
        {R.ImGui_Col_TextDisabled(),    col(m(tx, bg, 0.45))},
        {R.ImGui_Col_FrameBg(),         col(fr)},
        {R.ImGui_Col_FrameBgHovered(),  col(m(fr, tx, 0.12))},
        {R.ImGui_Col_FrameBgActive(),   col(m(fr, ac, 0.25))},
        {R.ImGui_Col_TitleBg(),         col(m(bg, 0x000000, 0.2))},
        {R.ImGui_Col_TitleBgActive(),   col(m(bg, ac, 0.18))},
        {R.ImGui_Col_Border(),          col(m(bg, base, 0.65))},
        {R.ImGui_Col_Separator(),       col(m(bg, base, 0.65))},
        {R.ImGui_Col_Button(),          col(bt)},
        {R.ImGui_Col_ButtonHovered(),   col(m(bt, tx, 0.15))},
        {R.ImGui_Col_ButtonActive(),    col(m(bt, ac, 0.5))},
        {R.ImGui_Col_Header(),          col(m(bg, ac, 0.25))},
        {R.ImGui_Col_HeaderHovered(),   col(m(bg, ac, 0.35))},
        {R.ImGui_Col_HeaderActive(),    col(m(bg, ac, 0.45))},
        {R.ImGui_Col_SliderGrab(),      col(base)},
        {R.ImGui_Col_SliderGrabActive(),col(ac)},
        {R.ImGui_Col_ScrollbarGrab(),   col(base)},
        {R.ImGui_Col_CheckMark(),       col(ac)},
        {R.ImGui_Col_TextSelectedBg(),  col(m(bg, ac, 0.6))},
        {R.ImGui_Col_TableRowBgAlt(),   col(m(bg, tx, 0.04))},
        -- tabs: same accent ramp as headers, selected one gets an accent overline
        {R.ImGui_Col_Tab(),                   col(m(b2, ac, 0.12))},
        {R.ImGui_Col_TabHovered(),            col(m(bg, ac, 0.35))},
        {R.ImGui_Col_TabSelected(),           col(m(bg, ac, 0.28))},
        {R.ImGui_Col_TabSelectedOverline(),   col(ac)},
        {R.ImGui_Col_TabDimmed(),             col(m(b2, ac, 0.08))},
        {R.ImGui_Col_TabDimmedSelected(),     col(m(bg, ac, 0.2))},
    }
    local r, sp = th.rounding, th.spacing
    local vars = {
        {R.ImGui_StyleVar_WindowRounding(), r.window * s},
        {R.ImGui_StyleVar_ChildRounding(),  r.window * 0.75 * s},
        {R.ImGui_StyleVar_FrameRounding(),  r.frame * s},
        {R.ImGui_StyleVar_PopupRounding(),  r.frame * s},
        {R.ImGui_StyleVar_GrabRounding(),   r.frame * 0.66 * s},
        {R.ImGui_StyleVar_GrabMinSize(),    10 * s},
        {R.ImGui_StyleVar_WindowPadding(),  sp * 1.5 * s, sp * 1.5 * s},
        {R.ImGui_StyleVar_ItemSpacing(),    sp * s, sp * s},
        {R.ImGui_StyleVar_FramePadding(),   sp * 0.75 * s, sp * 0.5 * s},
        {R.ImGui_StyleVar_FrameBorderSize(), th.frame.border},
    }
    return cols, vars
end

-- Theme colours + style vars on any ctx (no font). Pair with G.pop_theme(ctx).
local pushed = {}
function G.push_theme(ctx, th)
    local cols, vars = style(th or G.theme)
    for _, p in ipairs(cols) do R.ImGui_PushStyleColor(ctx, p[1], p[2]) end
    for _, v in ipairs(vars) do R.ImGui_PushStyleVar(ctx, v[1], v[2], v[3]) end
    pushed[#pushed + 1] = { #cols, #vars }
end

function G.pop_theme(ctx)
    local n = table.remove(pushed)
    R.ImGui_PopStyleVar(ctx, n[2])
    R.ImGui_PopStyleColor(ctx, n[1])
end

function G.push(ctx, size)
    G.push_theme(ctx)
    R.ImGui_PushFont(ctx, G.font, G.font_size(size))
end

function G.pop(ctx)
    R.ImGui_PopFont(ctx)
    G.pop_theme(ctx)
end

-- Button with the theme's button rounding / border.
-- kind: "accent" (default, primary) | "good" | "bad" | "plain" (normal theme button colour)
function G.button(ctx, label, w, h, kind)
    local th = G.theme
    R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_FrameRounding(), th.rounding.button * G.scale)
    R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_FrameBorderSize(), th.button.border)
    local n = 0
    if kind ~= "plain" then
        local base = (kind == "good" and G.good) or (kind == "bad" and G.bad) or G.accent
        R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Button(),        G.col(base))
        R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ButtonHovered(), G.col(G.mix(base, 0xFFFFFF, 0.2)))
        R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ButtonActive(),  G.col(G.mix(base, 0x000000, 0.2)))
        R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(),          G.col(G.text_on(base)))
        n = 4
    end
    local hit = R.ImGui_Button(ctx, label, w, h)
    R.ImGui_PopStyleColor(ctx, n)
    R.ImGui_PopStyleVar(ctx, 2)
    return hit
end

function G.dim_text(ctx, s)
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), G.col(G.dim))
    R.ImGui_TextWrapped(ctx, s)
    R.ImGui_PopStyleColor(ctx)
end

function G.color_text(ctx, hex, s)
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), G.col(hex))
    R.ImGui_Text(ctx, s)
    R.ImGui_PopStyleColor(ctx)
end

-- Big text using the shared font at a custom size.
function G.big_text(ctx, s, size, hex)
    R.ImGui_PushFont(ctx, G.font, G.font_size(size))
    if hex then G.color_text(ctx, hex, s) else R.ImGui_Text(ctx, s) end
    R.ImGui_PopFont(ctx)
end

-- Big heading in the theme title colour / section label in the theme subtitle colour.
function G.title(ctx, s) G.big_text(ctx, s, 20, G.title_col) end
function G.subtitle(ctx, s) G.color_text(ctx, G.subtitle_col, s) end

-- Settings row: [x] Inherit  [Lyx global theme]. Returns true when Inherit was toggled.
function G.theme_row(ctx, key)
    key = key or G.key or "Lyx"
    local on = T.inherit(key)
    local c, v = R.ImGui_Checkbox(ctx, "Inherit##lyx_theme", on)
    R.ImGui_SetItemTooltip(ctx, "Use the Lyx global theme for this window")
    if c then
        T.set_inherit(key, v)
        if key == G.key then G.load_theme() end
    end
    R.ImGui_SameLine(ctx)
    if G.button(ctx, "Lyx global theme", nil, nil, "plain") then T.open_manager() end
    R.ImGui_SetItemTooltip(ctx, "Open the Lyx global theme manager")
    return c
end

-- Pin (always on top), remembered per script key. G.run adds TopMost by itself;
-- own-ctx scripts OR G.pin_flag(key) into their Begin flags.
local PIN = "Lyx_GUI"
function G.pinned(key) return R.GetExtState(PIN, "pin:" .. (key or G.key or "Lyx")) == "1" end
function G.pin_flag(key) return G.pinned(key) and R.ImGui_WindowFlags_TopMost() or 0 end

-- Push-pin icon button (same look as the MIDI compressor): upright = pinned, tilted = not.
-- Place it yourself, e.g. right-aligned on the first row. Returns true when toggled.
function G.pin(ctx, key, size)
    key = key or G.key or "Lyx"
    local on = G.pinned(key)
    local sz = size or R.ImGui_GetFrameHeight(ctx)
    local clicked = R.ImGui_InvisibleButton(ctx, "##lyx_pin", sz, sz)
    local hov = R.ImGui_IsItemHovered(ctx)
    local x0, y0 = R.ImGui_GetItemRectMin(ctx)
    local col = on and G.accent or G.dim
    if hov then col = G.mix(col, 0xFFFFFF, 0.4) end
    col = G.col(col)
    local dl, cx, cy, r = R.ImGui_GetWindowDrawList(ctx), x0 + sz / 2, y0 + sz / 2, sz * 0.42
    local a = on and 0 or math.pi / 4
    local ca, sa = math.cos(a), math.sin(a)
    local function P(x, y) return cx + x * ca - y * sa, cy + x * sa + y * ca end
    local hx, hy = P(0, -r * 0.45)
    R.ImGui_DrawList_AddCircleFilled(dl, hx, hy, r * 0.38, col)                       -- head
    local x1, y1 = P(-r * 0.55, -r * 0.05)
    local x2, y2 = P(r * 0.55, -r * 0.05)
    R.ImGui_DrawList_AddLine(dl, x1, y1, x2, y2, col, r * 0.22)                       -- collar
    local n1x, n1y = P(0, -r * 0.05)
    local n2x, n2y = P(0, r * 0.95)
    R.ImGui_DrawList_AddLine(dl, n1x, n1y, n2x, n2y, col, math.max(1, r * 0.12))     -- needle
    if hov then R.ImGui_SetTooltip(ctx, on and "Unpin window" or "Pin window (always on top)") end
    if clicked then R.SetExtState(PIN, "pin:" .. key, on and "0" or "1", true) end
    return clicked
end

-- Moves the cursor so an item of width w ends at the right edge of the current row.
function G.align_right(ctx, w)
    local avail = R.ImGui_GetContentRegionAvail(ctx)
    R.ImGui_SetCursorPosX(ctx, R.ImGui_GetCursorPosX(ctx) + math.max(0, avail - w))
end

-- Defer loop. draw(ctx) returns false to close. Esc closes unless opts.esc == false.
-- opts: w, h (first-use size), min_w, min_h (smallest size), flags, font_size, on_close, on_exit.
-- opts.live == false disables theme live reload.
function G.run(ctx, title, draw, opts)
    opts = opts or {}
    local function loop()
        if opts.live ~= false then G.poll() end
        ensure_font(ctx)
        G.push(ctx, opts.font_size)
        if opts.w then
            R.ImGui_SetNextWindowSize(ctx, G.S(opts.w), G.S(opts.h or 300), R.ImGui_Cond_FirstUseEver())
        end
        if opts.min_w then -- design px, like w / h
            R.ImGui_SetNextWindowSizeConstraints(ctx, G.S(opts.min_w), G.S(opts.min_h or 0), 1e6, 1e6)
        end
        local flags = (opts.flags or R.ImGui_WindowFlags_NoCollapse()) | G.pin_flag()
        local visible, open = R.ImGui_Begin(ctx, title, true, flags)
        local keep = true
        if visible then
            keep = draw(ctx) ~= false
            if opts.esc ~= false and R.ImGui_IsWindowFocused(ctx, R.ImGui_FocusedFlags_RootAndChildWindows())
               and not R.ImGui_IsAnyItemActive(ctx)
               and R.ImGui_IsKeyPressed(ctx, R.ImGui_Key_Escape()) then
                keep = false
            end
            R.ImGui_End(ctx)
        end
        G.pop(ctx)
        if G.esc() then keep = false end
        if open and keep then
            R.defer(loop)
        elseif opts.on_close then
            opts.on_close()
        end
    end
    if opts.on_exit then R.atexit(opts.on_exit) end
    R.defer(loop)
end

return G
