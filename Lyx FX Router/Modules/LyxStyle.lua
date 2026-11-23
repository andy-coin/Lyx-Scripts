--@noindex
-- Lyx FX Router: Lyx theme bridge (colours, ImGui style, font).
-- The router runs under the ReaImGui 0.8.7 compat shim, so only style enums that exist in 0.8 are used here
-- (no TabSelected / TabDimmed...).

local r = reaper
local G = require("_lib._Lyx_GUI")
local T = require("_lib._Lyx_Theme")
local mix, col = G.mix, G.col

LYX = { G = G, KEY = "Lyx FX Router" }
G.load_theme(LYX.KEY)

-- Colours the user picked in Settings (key -> 0xRRGGBBAA). Everything else follows the theme.
USER_COLORS = {}

-- Semantic colours that do not come from the theme (still user-changeable).
local FIXED = {
    midi        = 0x8833AAFF,
    del         = 0xBB2222FF,
    bypass      = 0xDC5454FF,
    dnd         = 0x00B4D8FF,
    dnd_replace = 0xDC5454FF,
    dnd_swap    = 0xCD6DC6FF,
    phase       = 0x9674C5FF,
    cut         = 0x00FF00FF,
}

function LyxThemeColors()
    local th = G.theme
    local c = th.colors
    local bg, tx, ac, base = c.bg, c.text, c.accent, c.base
    local btn = th.button.color
    local panel = mix(bg, base, 0.35)
    local t = {
        bg           = col(bg),
        n            = col(mix(base, tx, 0.12)), -- FX nodes: theme base (accent is for containers)
        Container    = col(ac),
        enclose      = col(panel),
        knob_bg      = col(panel),
        knob_vol     = col(ac),
        knob_drywet  = col(mix(ac, tx, 0.4)),
        ROOT         = col(ac),
        add          = col(panel),
        parallel     = col(panel),
        enabled      = col(ac),
        wire         = col(mix(tx, bg, 0.3)),
        dnd_enclose  = col(ac),
        sine_anim    = col(mix(ac, tx, 0.3)),
        menu_txt_col = col(ac),
        offline      = col(mix(bg, base, 0.8)),
        active_PM    = col(ac),
        no_PM        = col(mix(tx, bg, 0.5)),
        -- UI chrome (not in the original COLOR table)
        panel        = col(c.bg2, 0xEE),
        border       = col(mix(bg, base, 0.65)),
        tip_bg       = col(c.bg2),
        marquee      = col(ac, 0xAA),
        marquee_fill = col(ac, 0x18),
        accent_dim   = col(ac, 0x88),
        btn          = col(btn),
        frame        = col(ac, 0x55),
        text         = col(tx),
    }
    for k, v in pairs(FIXED) do t[k] = v end
    return t
end

-- Rebuilds the router's COLOR table: theme colours + the user's overrides.
function LyxApplyColors()
    local t = LyxThemeColors()
    for k, v in pairs(USER_COLORS) do t[k] = v end
    SetColorTbl(t)
    ROUND_CORNER = G.theme.rounding.button
end

-- Settings colour picker: stores an override only when the user actually changes it.
function LyxColorEdit(label, key)
    local COLOR = GetColorTbl()
    local rv, v = r.ImGui_ColorEdit4(ctx, label, COLOR[key], r.ImGui_ColorEditFlags_NoInputs())
    if rv then
        COLOR[key] = v
        USER_COLORS[key] = v
    end
    if USER_COLORS[key] then
        r.ImGui_SameLine(ctx)
        if r.ImGui_SmallButton(ctx, "THEME##" .. key) then
            USER_COLORS[key] = nil
            LyxApplyColors()
        end
    end
end

-- Theme font file/family for CreateFont ("" = CJK-capable system font).
function LyxFontName()
    local name = G.theme.font.name
    if name ~= "" then return name end
    local os_name = r.GetOS()
    if os_name:find("OSX") or os_name:find("mac") then return "/System/Library/Fonts/PingFang.ttc" end
    if os_name:find("Win") then return "C:/Windows/Fonts/msjh.ttc" end
    return "sans-serif"
end

function LyxCreateFont(size, flags)
    local ok, font = pcall(r.ImGui_CreateFont, LyxFontName(), size, flags)
    if not ok or not font then font = r.ImGui_CreateFont("sans-serif", size, flags) end
    return font
end

-- Base design size (the original used ProggyClean 13 px).
function LyxFontSize()
    return math.max(8, math.floor(13 * G.theme.font.size / 14 + 0.5))
end

local pushed = { 0, 0 }
function LyxPushTheme()
    local th = G.theme
    local c = th.colors
    local bg, tx, ac, b2, base = c.bg, c.text, c.accent, c.bg2, c.base
    local fr, bt = th.frame.color, th.button.color
    local cols = {
        { r.ImGui_Col_ChildBg(),          col(b2, 0) },
        { r.ImGui_Col_PopupBg(),          col(b2) },
        { r.ImGui_Col_Text(),             col(tx) },
        { r.ImGui_Col_TextDisabled(),     col(mix(tx, bg, 0.45)) },
        { r.ImGui_Col_FrameBg(),          col(fr) },
        { r.ImGui_Col_FrameBgHovered(),   col(mix(fr, tx, 0.12)) },
        { r.ImGui_Col_FrameBgActive(),    col(mix(fr, ac, 0.25)) },
        { r.ImGui_Col_TitleBg(),          col(mix(bg, 0x000000, 0.2)) },
        { r.ImGui_Col_TitleBgActive(),    col(mix(bg, ac, 0.18)) },
        { r.ImGui_Col_Border(),           col(mix(bg, base, 0.65)) },
        { r.ImGui_Col_Separator(),        col(mix(bg, base, 0.65)) },
        { r.ImGui_Col_Button(),           col(bt) },
        { r.ImGui_Col_ButtonHovered(),    col(mix(bt, tx, 0.15)) },
        { r.ImGui_Col_ButtonActive(),     col(mix(bt, ac, 0.5)) },
        { r.ImGui_Col_Header(),           col(mix(bg, ac, 0.25)) },
        { r.ImGui_Col_HeaderHovered(),    col(mix(bg, ac, 0.35)) },
        { r.ImGui_Col_HeaderActive(),     col(mix(bg, ac, 0.45)) },
        { r.ImGui_Col_SliderGrab(),       col(base) },
        { r.ImGui_Col_SliderGrabActive(), col(ac) },
        { r.ImGui_Col_ScrollbarGrab(),    col(base) },
        { r.ImGui_Col_CheckMark(),        col(ac) },
        { r.ImGui_Col_TextSelectedBg(),   col(mix(bg, ac, 0.6)) },
    }
    local rd = th.rounding
    local vars = {
        { r.ImGui_StyleVar_WindowRounding(), rd.window },
        { r.ImGui_StyleVar_ChildRounding(),  rd.window * 0.75 },
        { r.ImGui_StyleVar_FrameRounding(),  rd.frame },
        { r.ImGui_StyleVar_PopupRounding(),  rd.frame },
        { r.ImGui_StyleVar_GrabRounding(),   rd.frame * 0.66 },
        { r.ImGui_StyleVar_FrameBorderSize(), th.frame.border },
    }
    local vars2 = {
        { r.ImGui_StyleVar_WindowPadding(), 10, 10 },
        { r.ImGui_StyleVar_FramePadding(),  8, 5 },
        { r.ImGui_StyleVar_ItemSpacing(),   8, 6 },
        { r.ImGui_StyleVar_PopupBorderSize(), 0 },
    }
    for _, p in ipairs(cols) do r.ImGui_PushStyleColor(ctx, p[1], p[2]) end
    for _, v in ipairs(vars) do r.ImGui_PushStyleVar(ctx, v[1], v[2]) end
    for _, v in ipairs(vars2) do r.ImGui_PushStyleVar(ctx, v[1], v[2], v[3]) end
    pushed = { #cols, #vars + #vars2 }
end

function LyxPopTheme()
    r.ImGui_PopStyleVar(ctx, pushed[2])
    r.ImGui_PopStyleColor(ctx, pushed[1])
end

-- Once a second: theme saved in the Lyx Theme Manager -> recolour; returns true when the font changed.
local font_key
function LyxPoll()
    if G.poll() then
        LyxApplyColors()
        local key = LyxFontName() .. "|" .. LyxFontSize()
        if key ~= font_key then
            font_key = key
            return true
        end
    end
    return false
end
font_key = LyxFontName() .. "|" .. LyxFontSize()

LYX.T = T

---------------------------------------------------------------------------
-- Modern look: soft cards, pills, ghost icon buttons (all colours 0xRRGGBBAA)
---------------------------------------------------------------------------
local function A(c, a) return (c & 0xFFFFFF00) | a end
LyxAlpha = A

-- blend two 0xRRGGBBAA colours, keeps alpha of a
function LyxMix(a, b, t)
    local function ch(c, s) return (c >> s) & 0xFF end
    local o = 0
    for _, sh in ipairs({ 24, 16, 8 }) do
        o = o | (math.floor(ch(a, sh) + (ch(b, sh) - ch(a, sh)) * t + 0.5) << sh)
    end
    return o | (a & 0xFF)
end

-- readable text (theme text or theme bg) on top of colour c
function LyxTextOn(c)
    local function lum(x) return 0.299 * ((x >> 24) & 0xFF) + 0.587 * ((x >> 16) & 0xFF) + 0.114 * ((x >> 8) & 0xFF) end
    local tx, bg = col(G.theme.colors.text), col(G.theme.colors.bg)
    return math.abs(lum(c) - lum(bg)) > math.abs(lum(c) - lum(tx)) and bg or tx
end

local function brighten(c, amt) return IncreaseDecreaseBrightness(c, amt, "no_alpha") end

-- Rounded card with soft shadow, top sheen, hairline border and selection glow.
function LyxCard(dl, xs, ys, xe, ye, c, hover, selected, rnd)
    local S = CANVAS and CANVAS.scale or 1
    rnd = rnd or (G.theme.rounding.button * S)
    local fill = hover and brighten(c, 14) or c
    r.ImGui_DrawList_AddRectFilled(dl, xs, ys + 2 * S, xe, ye + 3 * S, 0x00000038, rnd)               -- shadow
    r.ImGui_DrawList_AddRectFilled(dl, xs, ys, xe, ye, fill, rnd)                                      -- body
    r.ImGui_DrawList_AddRectFilled(dl, xs, ys, xe, ys + (ye - ys) * 0.5, 0xFFFFFF0D, rnd,
        r.ImGui_DrawFlags_RoundCornersTopLeft() | r.ImGui_DrawFlags_RoundCornersTopRight())           -- sheen
    r.ImGui_DrawList_AddRect(dl, xs, ys, xe, ye, A(brighten(c, 30), 0x70), rnd, nil, 1)                -- hairline
    if selected then
        local ac = GetColorTbl()["enabled"]
        local o = 2.5 * S
        r.ImGui_DrawList_AddRect(dl, xs - o - 1.5 * S, ys - o - 1.5 * S, xe + o + 1.5 * S, ye + o + 1.5 * S, A(ac, 0x30), rnd + o + 2 * S, nil, 3 * S)
        r.ImGui_DrawList_AddRect(dl, xs - o, ys - o, xe + o, ye + o, ac, rnd + o, nil, 1.5 * S)
    end
end

-- Capsule (insert points "+", "||", small toggles).
function LyxPill(dl, xs, ys, xe, ye, c, hover, active)
    local h = ye - ys
    local ac = GetColorTbl()["enabled"]
    local fill = (hover or active) and LyxMix(c, ac, 0.35) or c
    r.ImGui_DrawList_AddRectFilled(dl, xs, ys, xe, ye, fill, h * 0.5)
    r.ImGui_DrawList_AddRect(dl, xs, ys, xe, ye, A((hover or active) and ac or brighten(c, 25), (hover or active) and 0xC0 or 0x60), h * 0.5, nil, 1)
end

-- Ghost button: nothing at rest, a soft round highlight on hover/active.
function LyxGhost(dl, xs, ys, xe, ye, hover, active, tint)
    if not (hover or active) then return end
    local rnd = math.min(xe - xs, ye - ys) * 0.5
    local c = tint and A(tint, active and 0x50 or 0x30) or (active and 0xFFFFFF26 or 0xFFFFFF16)
    r.ImGui_DrawList_AddRectFilled(dl, xs + 1, ys + 1, xe - 1, ye - 1, c, rnd)
end

---------------------------------------------------------------------------
-- Labels: "AUTO BYPASS ON SILENCE" -> "Auto Bypass on Silence" (only for ALL-CAPS data labels)
---------------------------------------------------------------------------
local KEEP = {}
for w in ("FX LFO ACS MIDI MS ESC CTRL ALT SHIFT UI PM IIR FIR VST VST3 AU JS CLAP LV2 DX RS5K DB PDC CPU EQ VST3I VSTI AUI CLAPI JSFX"):gmatch("%S+") do KEEP[w] = true end
local FIX = { VST3I = "VST3i", VSTI = "VSTi", AUI = "AUi", CLAPI = "CLAPi", DB = "dB" }
local SMALL = { ON = 1, OF = 1, TO = 1, IN = 1, AND = 1, OR = 1, THE = 1, A = 1, AN = 1, FOR = 1, AS = 1, INTO = 1, AT = 1, BY = 1 }
function Nice(s)
    if type(s) ~= "string" or s:find("%l") then return s end
    local first = true
    return (s:gsub("[%w']+", function(w)
        local out
        if FIX[w] then out = FIX[w]
        elseif KEEP[w] or w:find("%d") then out = w
        elseif SMALL[w] and not first then out = w:lower()
        else out = w:sub(1, 1) .. w:sub(2):lower() end
        first = false
        return out
    end))
end
