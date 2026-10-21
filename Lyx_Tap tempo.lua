--[[
 * ReaScript Name: Tap Tempo (Lyx mod, ReaImGui rewrite)
 * Based on: X-Raym Tap Tempo v1.1.2 — https://github.com/X-Raym/REAPER-ReaScripts (GPL v3)
 * Licence: GPL v3
 * Special thanks to X-Raym for the original Tap Tempo script and for sharing so many
   great REAPER scripts with the community: https://www.extremraym.com

   Tap: click the pad, or press Space / Enter / any letter.   R = reset   Esc = close
   BPM = least-squares fit over the last N taps (steadier than a plain average).
   Click any delay time to copy it.
   Click the big BPM number to type a BPM (10–999; Enter / click away = set, Esc = cancel).
   A typed BPM replaces the tap result until the next tap or reset.
]]
local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
package.path = package.path .. ";" .. script_path .. "?.lua"

---------------------------------------------------------------------------
-- Analysis (pure)
---------------------------------------------------------------------------
-- times: tap timestamps (s). returns bpm, stability 0..1, intervals, mean interval
local function analyze(times)
    local n = #times
    if n < 2 then return end
    local iv, sum = {}, 0
    for i = 2, n do iv[#iv + 1] = times[i] - times[i - 1]; sum = sum + iv[#iv] end
    local mean = sum / #iv
    -- slope of time vs tap index
    local mi, mt = (n + 1) / 2, 0
    for i = 1, n do mt = mt + times[i] end
    mt = mt / n
    local num, den = 0, 0
    for i = 1, n do num = num + (i - mi) * (times[i] - mt); den = den + (i - mi) ^ 2 end
    local slope = num / den
    local var = 0
    for _, d in ipairs(iv) do var = var + (d - mean) ^ 2 end
    local sd = (#iv > 1) and math.sqrt(var / (#iv - 1)) or 0
    return 60 / slope, math.max(0, 1 - sd / mean), iv, mean
end

-- typed BPM text -> number (10..999, rounded when round) or nil
local function parse_bpm(s, round)
    local v = tonumber((tostring(s):gsub(",", ".")))
    if not v or v ~= v or v < 10 or v > 999 then return nil end
    if round then v = math.floor(v + 0.5) end
    return v
end

if not reaper then -- self-check: lua "Lyx_Tap tempo.lua"
    local bpm, st = analyze({ 0, 0.5, 1.0, 1.5, 2.0 })
    assert(math.abs(bpm - 120) < 1e-9 and st == 1)
    bpm, st = analyze({ 0, 0.52, 0.98, 1.51, 2.0 })
    assert(math.abs(bpm - 120) < 2 and st > 0.9 and st < 1)
    assert(analyze({ 1 }) == nil)
    assert(parse_bpm("120", true) == 120 and parse_bpm(" 97.6 ", true) == 98)
    assert(parse_bpm("97.6", false) == 97.6 and parse_bpm("97,5", false) == 97.5)
    assert(parse_bpm("10") == 10 and parse_bpm("999") == 999)
    assert(not parse_bpm("9.9") and not parse_bpm("1000") and not parse_bpm("") and not parse_bpm("abc"))
    assert(not parse_bpm("nan") and not parse_bpm("inf"))
    return print("Tap tempo self-check OK")
end

---------------------------------------------------------------------------
local G = require("_lib._Lyx_GUI")
local R = reaper
local EXT = "Lyx_TapTempo"

local window = tonumber(R.GetExtState(EXT, "window")) or 8      -- taps used
local reset_s = tonumber(R.GetExtState(EXT, "reset")) or 2.0     -- idle reset
local round_bpm = R.GetExtState(EXT, "round") ~= "0"

local taps = {}
local mult = 1
local flash_t, copied_t, copied_txt = 0, 0, ""
-- typed BPM: replaces the tap result until the next tap / reset
local typed = nil
local editing, edit_buf, edit_focus, err_t = false, "", 0, 0 -- edit_focus: frames left for the field to take focus

local function reset() taps, mult, typed = {}, 1, nil end

local function tap()
    typed = nil
    local now = R.time_precise()
    if #taps > 0 and now - taps[#taps] > reset_s then taps, mult = {}, 1 end
    taps[#taps + 1] = now
    while #taps > window + 1 do table.remove(taps, 1) end
    flash_t = now
end

local TAP_KEYS = {}
do
    for _, k in ipairs({ "Space", "Enter", "KeypadEnter" }) do TAP_KEYS[#TAP_KEYS + 1] = R["ImGui_Key_" .. k]() end
    for c = string.byte("A"), string.byte("Z") do
        local ch = string.char(c)
        if ch ~= "R" then TAP_KEYS[#TAP_KEYS + 1] = R["ImGui_Key_" .. ch]() end
    end
end

local function stability_color(s)
    return (s > 0.95 and G.good) or (s > 0.85 and G.warn) or G.bad
end

local ctx = G.new("Tap tempo", "TapTempo")
if not ctx then return end

local function pad(ctx, bpm)
    local dl = R.ImGui_GetWindowDrawList(ctx)
    local w = R.ImGui_GetContentRegionAvail(ctx)
    local h = G.S(110)
    local x0, y0 = R.ImGui_GetCursorScreenPos(ctx)
    R.ImGui_InvisibleButton(ctx, "##pad", w, h)
    if R.ImGui_IsItemActivated(ctx) then tap() end
    local now = R.time_precise()
    local f = math.max(0, 1 - (now - flash_t) / 0.18)
    R.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + w, y0 + h, G.col(G.mix(G.panel, G.accent, 0.15 + 0.5 * f)), G.S(10))
    local label = (#taps == 0 and not typed) and "Click here or press any key to start tapping" or "TAP"
    local tw, th = R.ImGui_CalcTextSize(ctx, label)
    if tw > w - G.S(16) then label = "Tap"; tw, th = R.ImGui_CalcTextSize(ctx, label) end -- narrow window
    R.ImGui_DrawList_AddText(dl, x0 + (w - tw) / 2, y0 + (h - th) / 2, G.col(G.fg, 0xC0), label)
    -- metronome dots continuing at the detected tempo
    if bpm and #taps > 0 and now - taps[#taps] < reset_s then
        local beat = 60 / bpm
        local ph = ((now - taps[#taps]) / beat) % 4
        for i = 0, 3 do
            local on = math.floor(ph) == i
            local cx = x0 + w / 2 + (i - 1.5) * G.S(22)
            R.ImGui_DrawList_AddCircleFilled(dl, cx, y0 + h - G.S(16), G.S(on and 6 or 4),
                G.col(on and G.accent or G.dim, on and 0xFF or 0x80))
        end
    end
end

local function history(ctx, iv, mean)
    local dl = R.ImGui_GetWindowDrawList(ctx)
    local w = R.ImGui_GetContentRegionAvail(ctx)
    local h = G.S(36)
    local x0, y0 = R.ImGui_GetCursorScreenPos(ctx)
    R.ImGui_Dummy(ctx, w, h)
    R.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + w, y0 + h, G.col(G.panel), G.S(6))
    local cy = y0 + h / 2
    R.ImGui_DrawList_AddLine(dl, x0 + 4, cy, x0 + w - 4, cy, G.col(G.dim, 0x80), 1)
    if not iv then return end
    local cw = (w - 8) / window
    for i, d in ipairs(iv) do
        local dev = (d - mean) / mean                -- ±10% fills the half height
        local bh = math.max(-1, math.min(1, dev / 0.10)) * (h / 2 - 3)
        local x = x0 + 4 + (i - 1) * cw
        local col = stability_color(1 - math.abs(dev) * 2.5)
        R.ImGui_DrawList_AddRectFilled(dl, x + 1, math.min(cy, cy - bh), x + cw - 1, math.max(cy, cy - bh) + 1, G.col(col), 2)
    end
end

local NOTES = { { "1/1", 4 }, { "1/2", 2 }, { "1/4", 1 }, { "1/8", 0.5 }, { "1/16", 0.25 }, { "1/32", 0.125 } }

local function delay_table(ctx, bpm)
    local flags = R.ImGui_TableFlags_RowBg() | R.ImGui_TableFlags_SizingStretchSame()
    if not R.ImGui_BeginTable(ctx, "delays", 4, flags) then return end
    R.ImGui_TableSetupColumn(ctx, "Note")
    R.ImGui_TableSetupColumn(ctx, "Straight ms")
    R.ImGui_TableSetupColumn(ctx, "Dotted ms")
    R.ImGui_TableSetupColumn(ctx, "Triplet ms")
    R.ImGui_TableHeadersRow(ctx)
    local q = 60000 / bpm
    for _, n in ipairs(NOTES) do
        R.ImGui_TableNextRow(ctx)
        R.ImGui_TableNextColumn(ctx)
        G.color_text(ctx, G.dim, n[1])
        for _, k in ipairs({ 1, 1.5, 2 / 3 }) do
            R.ImGui_TableNextColumn(ctx)
            local v = ("%.1f"):format(q * n[2] * k)
            if R.ImGui_Selectable(ctx, v .. "##" .. n[1] .. k) then
                R.ImGui_SetClipboardText(ctx, v)
                copied_t, copied_txt = R.time_precise(), v .. " ms"
            end
        end
    end
    R.ImGui_EndTable(ctx)
end

-- SameLine when an item of width w still fits on this row, else start a new row
local function same_line_fit(ctx, w)
    R.ImGui_SameLine(ctx)
    if R.ImGui_GetContentRegionAvail(ctx) < w then R.ImGui_NewLine(ctx) end
end
local function btn_w(ctx, label)
    return R.ImGui_CalcTextSize(ctx, label) + 2 * R.ImGui_GetStyleVar(ctx, R.ImGui_StyleVar_FramePadding())
end
local function check_w(ctx, label)
    return R.ImGui_GetFrameHeight(ctx) + R.ImGui_GetStyleVar(ctx, R.ImGui_StyleVar_ItemInnerSpacing())
        + R.ImGui_CalcTextSize(ctx, label)
end

local function save()
    R.SetExtState(EXT, "window", tostring(window), true)
    R.SetExtState(EXT, "reset", tostring(reset_s), true)
    R.SetExtState(EXT, "round", round_bpm and "1" or "0", true)
end

-- Big BPM readout; click it to type a BPM. Returns true when Esc cancelled the edit this frame.
local function readout(ctx, bpm, col)
    if not editing then
        G.big_text(ctx, bpm and ("%.1f"):format(bpm) or "---.-", 56, col)
        if R.ImGui_IsItemHovered(ctx) then
            R.ImGui_SetMouseCursor(ctx, R.ImGui_MouseCursor_TextInput())
            R.ImGui_SetTooltip(ctx, "Click to type a BPM")
        end
        if R.ImGui_IsItemClicked(ctx) then
            editing, edit_focus = true, 4
            edit_buf = bpm and ("%.1f"):format(bpm) or ""
        end
        return false
    end
    -- input field: same font size / spot as the readout, borderless on the panel colour
    R.ImGui_PushFont(ctx, G.font, G.font_size(56))
    R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_FramePadding(), G.S(4), 0)
    R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_FrameBorderSize(), 0)
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_FrameBg(), G.col(G.panel))
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_FrameBgActive(), G.col(G.panel))
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), G.col(G.accent))
    R.ImGui_SetNextItemWidth(ctx, R.ImGui_CalcTextSize(ctx, "999.99") + G.S(8))
    if edit_focus == 4 then R.ImGui_SetKeyboardFocusHere(ctx) end -- focus lands a frame or two later
    local flags = R.ImGui_InputTextFlags_CharsDecimal() | R.ImGui_InputTextFlags_AutoSelectAll()
    local _
    _, edit_buf = R.ImGui_InputText(ctx, "##bpm_edit", edit_buf, flags)
    local done = R.ImGui_IsItemDeactivated(ctx)          -- Enter, click away or Esc
    local active = R.ImGui_IsItemActive(ctx)
    R.ImGui_PopStyleColor(ctx, 3)
    R.ImGui_PopStyleVar(ctx, 2)
    R.ImGui_PopFont(ctx)
    local esc = R.ImGui_IsKeyPressed(ctx, R.ImGui_Key_Escape())
    if done then
        editing = false
        local v = not esc and parse_bpm(edit_buf, round_bpm)
        if v then taps, mult, typed = {}, 1, v end
        if not esc and not v then err_t = R.time_precise() end
    elseif not active and edit_focus == 0 then
        editing = false                                    -- focus never arrived
    end
    edit_focus = active and 0 or math.max(0, edit_focus - 1)
    return done and esc
end

G.run(ctx, "Tap tempo", function(ctx)
    -- keys (ignored while a widget like a slider is being edited)
    if not R.ImGui_IsAnyItemActive(ctx) and not editing then
        for _, k in ipairs(TAP_KEYS) do
            if R.ImGui_IsKeyPressed(ctx, k, false) then tap(); break end
        end
        if R.ImGui_IsKeyPressed(ctx, R.ImGui_Key_R(), false) then reset() end
    end

    local raw, st, iv, mean = analyze(taps)
    local base = typed or raw
    local bpm = base and base * mult

    -- pin, top-right (drawn first, cursor restored for the readout row)
    local cx, cy = R.ImGui_GetCursorPos(ctx)
    G.align_right(ctx, R.ImGui_GetFrameHeight(ctx))
    G.pin(ctx)
    R.ImGui_SetCursorPos(ctx, cx, cy)

    -- big readout
    local esc_used
    if bpm then
        esc_used = readout(ctx, bpm, typed and G.accent or stability_color(st))
        R.ImGui_SameLine(ctx)
        -- wrap the side text before the pin (top-right) and the window edge
        local wrap = R.ImGui_GetCursorPosX(ctx) + R.ImGui_GetContentRegionAvail(ctx)
                   - R.ImGui_GetFrameHeight(ctx) - R.ImGui_GetStyleVar(ctx, R.ImGui_StyleVar_ItemSpacing())
        R.ImGui_PushTextWrapPos(ctx, wrap)
        R.ImGui_BeginGroup(ctx)
        R.ImGui_Dummy(ctx, 1, G.font_size(18))
        G.color_text(ctx, G.dim, "BPM")
        if typed then
            G.color_text(ctx, G.dim, "Stability: typed  ·  tap to override")
        else
            G.color_text(ctx, G.dim, ("Stability %d%%  ·  %d taps"):format(math.floor(st * 100 + 0.5), #taps))
        end
        R.ImGui_EndGroup(ctx)
        R.ImGui_PopTextWrapPos(ctx)
    else
        esc_used = readout(ctx, nil, G.dim)
        G.dim_text(ctx, (#taps == 1) and "Tap once more…" or "Tap at least twice, or click the number to type a BPM")
    end

    pad(ctx, bpm)
    history(ctx, iv, mean)

    R.ImGui_BeginDisabled(ctx, not bpm)
    if R.ImGui_Button(ctx, "÷2") then mult = mult / 2 end
    same_line_fit(ctx, btn_w(ctx, "×2"))
    if R.ImGui_Button(ctx, "×2") then mult = mult * 2 end
    same_line_fit(ctx, btn_w(ctx, "Set project tempo"))
    if G.button(ctx, "Set project tempo") and bpm then
        local v = round_bpm and math.floor(bpm + 0.5) or math.floor(bpm * 100 + 0.5) / 100
        R.SetCurrentBPM(0, v, true)
        copied_t, copied_txt = R.time_precise(), "Project tempo → " .. v
    end
    R.ImGui_EndDisabled(ctx)
    same_line_fit(ctx, check_w(ctx, "Round"))
    local c, v = R.ImGui_Checkbox(ctx, "Round", round_bpm)
    if c then round_bpm = v end
    same_line_fit(ctx, btn_w(ctx, "Reset (R)"))
    if R.ImGui_Button(ctx, "Reset (R)") then reset() end

    if bpm then
        -- section heading in the theme subtitle colour (unchanged look when not inheriting)
        if G.inherited then R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), G.col(G.subtitle_col)) end
        R.ImGui_SeparatorText(ctx, "Delay times (click to copy)")
        if G.inherited then R.ImGui_PopStyleColor(ctx) end
        delay_table(ctx, bpm)
    end
    if R.time_precise() - copied_t < 1.5 then G.color_text(ctx, G.good, "Copied / set: " .. copied_txt) end
    if R.time_precise() - err_t < 2 then G.color_text(ctx, G.bad, "Type a BPM between 10 and 999") end

    if R.ImGui_CollapsingHeader(ctx, "Settings") then
        -- sliders fill the row, leaving room for their labels on the right
        local lw = math.max((R.ImGui_CalcTextSize(ctx, "Average last N taps")), (R.ImGui_CalcTextSize(ctx, "Restart after pause"))) -- ( ) = width only
            + R.ImGui_GetStyleVar(ctx, R.ImGui_StyleVar_ItemInnerSpacing())
        R.ImGui_SetNextItemWidth(ctx, -lw)
        local c1, v1 = R.ImGui_SliderInt(ctx, "Average last N taps", window, 3, 24)
        if c1 then window = v1 end
        R.ImGui_SetNextItemWidth(ctx, -lw)
        local c2, v2 = R.ImGui_SliderDouble(ctx, "Restart after pause", reset_s, 1, 6, "%.1f s")
        if c2 then reset_s = v2 end
        G.theme_row(ctx, "TapTempo")
    end

    -- Esc closes (handled here so the Esc that cancels a BPM edit doesn't also close)
    if not esc_used and not editing and not R.ImGui_IsAnyItemActive(ctx)
       and R.ImGui_IsWindowFocused(ctx, R.ImGui_FocusedFlags_RootAndChildWindows())
       and R.ImGui_IsKeyPressed(ctx, R.ImGui_Key_Escape()) then
        return false
    end
end, { w = 420, h = 560, min_w = 320, min_h = 300, on_close = save, esc = false })
