--[[
    _Lyx_GUI.lua  —  shared ReaImGui look & loop for Lyx scripts.

    Theme is read from the same ExtState as r.GetUserInputs ("Lyx_GetUserInputs":
    bg / fg / accent / scale), so changing colours in any "Set" popup restyles
    every Lyx GUI at once.

    usage:
        local G   = require("_Lyx_GUI")
        local ctx = G.new("My tool")          -- nil if ReaImGui missing
        G.run(ctx, "My tool", function(ctx) ... return false to close ... end,
              { w = 420, h = 300, on_close = fn })
]]

local R = reaper
local G = {}
local SECTION = "Lyx_GetUserInputs"

local function num(k, d) return tonumber(R.GetExtState(SECTION, k)) or d end

function G.mix(a, b, t)
    local function ch(x, s) return (x >> s) & 0xFF end
    local function m(s) return math.floor(ch(a, s) + (ch(b, s) - ch(a, s)) * t + 0.5) end
    return (m(16) << 16) | (m(8) << 8) | m(0)
end

-- 0xRRGGBB -> ImGui 0xRRGGBBAA
function G.col(h, alpha) return ((h & 0xFFFFFF) << 8) | (alpha or 0xFF) end

function G.load_theme()
    G.bg     = num("bg",     0x1E1E2E)
    G.fg     = num("fg",     0xCDD6F4)
    G.accent = num("accent", 0x89B4FA)
    G.scale  = math.max(0.5, math.min(2.5, num("scale", 1.0)))
    G.dim    = G.mix(G.fg, G.bg, 0.45)
    G.panel  = G.mix(G.bg, 0x000000, 0.25)
    G.good, G.warn, G.bad = 0xA6E3A1, 0xF9E2AF, 0xF38BA8
end
G.load_theme()

function G.S(v) return v * G.scale end

function G.new(title)
    if not R.ImGui_CreateContext then
        R.MB("This script needs the ReaImGui extension.\nInstall \"ReaImGui: ReaScript binding for Dear ImGui\" with ReaPack.", title or "Lyx", 0)
        return
    end
    local ctx = R.ImGui_CreateContext(title or "Lyx")
    local ok, font = pcall(R.ImGui_CreateFontFromFile, "/System/Library/Fonts/PingFang.ttc", 0)
    if not ok or not font then font = R.ImGui_CreateFont("sans-serif") end
    R.ImGui_Attach(ctx, font)
    G.font = font
    -- no keyboard nav: Space/Enter/arrows stay free for the scripts (same as r.GetUserInputs)
    R.ImGui_SetConfigVar(ctx, R.ImGui_ConfigVar_Flags(),
        R.ImGui_GetConfigVar(ctx, R.ImGui_ConfigVar_Flags()) & ~R.ImGui_ConfigFlags_NavEnableKeyboard())
    return ctx
end

local COLS, VARS
function G.push(ctx, size)
    local c, mix = G.col, G.mix
    local bg, fg, ac = G.bg, G.fg, G.accent
    COLS = {
        {R.ImGui_Col_WindowBg(),        c(bg)},
        {R.ImGui_Col_ChildBg(),         c(G.panel)},
        {R.ImGui_Col_PopupBg(),         c(mix(bg, 0x000000, 0.1))},
        {R.ImGui_Col_Text(),            c(fg)},
        {R.ImGui_Col_TextDisabled(),    c(G.dim)},
        {R.ImGui_Col_FrameBg(),         c(G.panel)},
        {R.ImGui_Col_FrameBgHovered(),  c(mix(bg, fg, 0.12))},
        {R.ImGui_Col_FrameBgActive(),   c(mix(bg, ac, 0.25))},
        {R.ImGui_Col_TitleBg(),         c(mix(bg, 0x000000, 0.2))},
        {R.ImGui_Col_TitleBgActive(),   c(mix(bg, ac, 0.18))},
        {R.ImGui_Col_Border(),          c(mix(bg, fg, 0.2))},
        {R.ImGui_Col_Separator(),       c(mix(bg, fg, 0.2))},
        {R.ImGui_Col_Button(),          c(mix(bg, fg, 0.15))},
        {R.ImGui_Col_ButtonHovered(),   c(mix(bg, fg, 0.28))},
        {R.ImGui_Col_ButtonActive(),    c(mix(bg, ac, 0.4))},
        {R.ImGui_Col_Header(),          c(mix(bg, ac, 0.25))},
        {R.ImGui_Col_HeaderHovered(),   c(mix(bg, ac, 0.35))},
        {R.ImGui_Col_HeaderActive(),    c(mix(bg, ac, 0.45))},
        {R.ImGui_Col_SliderGrab(),      c(ac)},
        {R.ImGui_Col_SliderGrabActive(),c(mix(ac, 0xFFFFFF, 0.25))},
        {R.ImGui_Col_CheckMark(),       c(ac)},
        {R.ImGui_Col_TextSelectedBg(),  c(mix(bg, ac, 0.6))},
        {R.ImGui_Col_TableRowBgAlt(),   c(mix(bg, fg, 0.04))},
    }
    for _, p in ipairs(COLS) do R.ImGui_PushStyleColor(ctx, p[1], p[2]) end
    local s = G.scale
    VARS = {
        {R.ImGui_StyleVar_WindowRounding(), 8 * s},
        {R.ImGui_StyleVar_ChildRounding(),  6 * s},
        {R.ImGui_StyleVar_FrameRounding(),  6 * s},
        {R.ImGui_StyleVar_PopupRounding(),  6 * s},
        {R.ImGui_StyleVar_GrabRounding(),   4 * s},
        {R.ImGui_StyleVar_GrabMinSize(),   10 * s},
        {R.ImGui_StyleVar_WindowPadding(), 12 * s, 12 * s},
        {R.ImGui_StyleVar_ItemSpacing(),    8 * s,  8 * s},
        {R.ImGui_StyleVar_FramePadding(),   6 * s,  4 * s},
    }
    for _, v in ipairs(VARS) do R.ImGui_PushStyleVar(ctx, v[1], v[2], v[3]) end
    R.ImGui_PushFont(ctx, G.font, math.floor((size or 14) * s + 0.5))
end

function G.pop(ctx)
    R.ImGui_PopFont(ctx)
    R.ImGui_PopStyleVar(ctx, #VARS)
    R.ImGui_PopStyleColor(ctx, #COLS)
end

-- Coloured button. kind: "accent" (default) | "good" | "bad"
function G.button(ctx, label, w, h, kind)
    local base = (kind == "good" and G.good) or (kind == "bad" and G.bad) or G.accent
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Button(),        G.col(base))
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ButtonHovered(), G.col(G.mix(base, 0xFFFFFF, 0.2)))
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ButtonActive(),  G.col(G.mix(base, 0x000000, 0.2)))
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(),          G.col(G.bg))
    local hit = R.ImGui_Button(ctx, label, w, h)
    R.ImGui_PopStyleColor(ctx, 4)
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
    R.ImGui_PushFont(ctx, G.font, math.floor(size * G.scale + 0.5))
    if hex then G.color_text(ctx, hex, s) else R.ImGui_Text(ctx, s) end
    R.ImGui_PopFont(ctx)
end

-- Defer loop. draw(ctx) returns false to close. Esc closes unless opts.esc == false.
function G.run(ctx, title, draw, opts)
    opts = opts or {}
    local function loop()
        G.push(ctx, opts.font_size)
        if opts.w then
            R.ImGui_SetNextWindowSize(ctx, G.S(opts.w), G.S(opts.h or 300), R.ImGui_Cond_FirstUseEver())
        end
        local flags = opts.flags or R.ImGui_WindowFlags_NoCollapse()
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
