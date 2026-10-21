--[[
    Lyx Global theme manager — edit the theme shared by all Lyx GUIs.

    Left:   theme list. Click a name to edit it; the round button picks the theme in use.
    Middle: colours, button, frame, font, rounding, alpha, spacing, scale.
    Right:  live preview. The manager itself always wears the theme being edited.
    Save writes <REAPER resource>/Data/Lyx/themes.lua; open Lyx GUIs follow within a second.
    The built-in presets (grey rows) are read-only: Duplicate one to make your own.
]]
local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
package.path = package.path .. ";" .. script_path .. "?.lua"

local G = require("_lib._Lyx_GUI")
local T = require("_lib._Lyx_Theme")
local R = reaper
if R.set_action_options then R.set_action_options(3) end -- re-launch = restart, no dialog

local ctx = G.new("Lyx Global Theme")
if not ctx then return end

local saved = T.load()
local work  = T.copy(saved)
local sel   = work.current
local dirty = false
local renaming, rename_buf, rename_focus = false, "", false
local confirm_del = false
local pend = {}          -- values being dragged / typed, committed on release
local msg              -- { text, colour }
local pv = { check = true, slider = 0.5, input = "Text input", combo = 0 }

G.apply(work.themes[sel])

local function names()
    local list = {}
    for n in pairs(work.themes) do if not T.is_builtin(n) then list[#list + 1] = n end end
    table.sort(list, function(a, b) return a:lower() < b:lower() end)
    for i, n in ipairs(T.PRESETS) do table.insert(list, i, n) end
    return list
end

local function unique(base)
    local n, i = base, 2
    while work.themes[n] do n = base .. " " .. i; i = i + 1 end
    return n
end

local function select_theme(name)
    sel, renaming, confirm_del, pend = name, false, false, {}
end

local function add_theme(name, th)
    work.themes[name] = T.fill(th, name)
    T.set_ui(work)   -- shared font size / scale
    select_theme(name)
    renaming, rename_buf, rename_focus = true, name, true
    dirty = true
end

local function commit_rename()
    renaming = false
    local new = rename_buf:match("^%s*(.-)%s*$")
    if new == "" or new == sel then return end
    if work.themes[new] then msg = { "\"" .. new .. "\" already exists", G.bad }; return end
    local th = work.themes[sel]
    work.themes[sel], work.themes[new], th.name = nil, th, new
    if work.current == sel then work.current = new end
    sel, dirty = new, true
end

---------------------------------------------------------------------------
-- Editors
---------------------------------------------------------------------------
local function color(label, t, k)
    local c, v = R.ImGui_ColorEdit3(ctx, label, t[k], R.ImGui_ColorEditFlags_NoInputs())
    if c then t[k] = v; dirty = true end
end

local function slider_int(label, t, k, lo, hi)
    local c, v = R.ImGui_SliderInt(ctx, label, t[k], lo, hi)
    if c then t[k] = v; dirty = true end
end

-- widget(value) -> changed, value; the value is committed when the widget is released,
-- so things like scale / font do not rebuild the window while you drag or type.
local function deferred(id, widget, value, commit)
    local c, v = widget(pend[id] == nil and value or pend[id])
    if c then pend[id] = v end
    if R.ImGui_IsItemDeactivatedAfterEdit(ctx) and pend[id] ~= nil then
        commit(pend[id]); pend[id] = nil; dirty = true
    end
end

local function tw(s) return (R.ImGui_CalcTextSize(ctx, s)) end
local function style_x(var) return (R.ImGui_GetStyleVar(ctx, var)) end

-- negative item width that leaves room for the widest of these labels on the right
local function label_room(...)
    local w = 0
    for _, s in ipairs({ ... }) do w = math.max(w, tw(s)) end
    return -(w + style_x(R.ImGui_StyleVar_ItemInnerSpacing()))
end

local function editors(th)
    -- second colour column starts after the widest first-column swatch + label
    local inner, sp = style_x(R.ImGui_StyleVar_ItemInnerSpacing()), style_x(R.ImGui_StyleVar_ItemSpacing())
    local w = R.ImGui_GetCursorPosX(ctx) + R.ImGui_GetFrameHeight(ctx) + inner + sp
        + math.max(tw("Background"), tw("Base"), tw("Title"), tw("Colour"))
    G.subtitle(ctx, "Colours")
    color("Background", th.colors, "bg")
    R.ImGui_SameLine(ctx, w); color("Background 2", th.colors, "bg2")
    color("Base", th.colors, "base")
    R.ImGui_SetItemTooltip(ctx, "Sliders, scrollbars, borders, inactive widgets")
    R.ImGui_SameLine(ctx, w); color("Accent", th.colors, "accent")
    color("Title", th.colors, "title")
    R.ImGui_SameLine(ctx, w); color("Subtitle", th.colors, "subtitle")
    color("Text", th.colors, "text")

    R.ImGui_Spacing(ctx)
    G.subtitle(ctx, "Button")
    color("Colour##btn", th.button, "color")
    R.ImGui_SameLine(ctx, w); R.ImGui_SetNextItemWidth(ctx, label_room("Border")); slider_int("Border##btn", th.button, "border", 0, 2)
    G.subtitle(ctx, "Frame")
    color("Colour##frm", th.frame, "color")
    R.ImGui_SameLine(ctx, w); R.ImGui_SetNextItemWidth(ctx, label_room("Border")); slider_int("Border##frm", th.frame, "border", 0, 2)

    R.ImGui_Spacing(ctx)
    G.subtitle(ctx, "Font")
    R.ImGui_SetNextItemWidth(ctx, label_room("Name"))
    deferred("font", function(v)
        return R.ImGui_InputTextWithHint(ctx, "Name", "Default (CJK system font)", v)
    end, th.font.name, function(v) th.font.name = v end)
    R.ImGui_SetItemTooltip(ctx, "Font family (e.g. Helvetica) or a font file path; empty = default")
end

-- Layout and Display belong to no theme: one setting for all, so switching themes only changes colours.
local function shared()
    local ui, was = work.ui, dirty
    dirty = false
    local w = label_room("Window rounding", "Button rounding", "Frame rounding", "Window alpha", "Spacing", "Font size", "Scale")
    R.ImGui_Spacing(ctx)
    G.subtitle(ctx, "Layout")
    R.ImGui_SetNextItemWidth(ctx, w)
    slider_int("Window rounding", ui.rounding, "window", 0, 16)
    R.ImGui_SetNextItemWidth(ctx, w)
    slider_int("Button rounding", ui.rounding, "button", 0, 16)
    R.ImGui_SetNextItemWidth(ctx, w)
    slider_int("Frame rounding", ui.rounding, "frame", 0, 16)
    R.ImGui_SetNextItemWidth(ctx, w)
    local c, v = R.ImGui_SliderDouble(ctx, "Window alpha", ui.alpha, 0.3, 1, "%.2f")
    if c then ui.alpha = v; dirty = true end
    R.ImGui_SetNextItemWidth(ctx, w)
    deferred("spacing", function(x) return R.ImGui_SliderInt(ctx, "Spacing", x, 2, 16) end,
        ui.spacing, function(x) ui.spacing = x end)

    R.ImGui_Spacing(ctx)
    G.subtitle(ctx, "Display")
    R.ImGui_SetNextItemWidth(ctx, w)
    deferred("size", function(v) return R.ImGui_SliderInt(ctx, "Font size", v, 10, 24) end,
        ui.font_size, function(v) ui.font_size = v end)
    R.ImGui_SetNextItemWidth(ctx, w)
    deferred("scale", function(x) return R.ImGui_SliderDouble(ctx, "Scale", x, 0.75, 2, "%.2f") end,
        ui.scale, function(x) ui.scale = x end)
    if dirty then T.set_ui(work) end
    dirty = dirty or was
end

local function preview()
    G.subtitle(ctx, "Preview")
    G.dim_text(ctx, "Sample widgets showing the theme. They do nothing.")
    R.ImGui_Separator(ctx)
    R.ImGui_Spacing(ctx)
    G.title(ctx, "Title")
    G.subtitle(ctx, "Subtitle")
    R.ImGui_TextWrapped(ctx, "Body text looks like this.")
    G.dim_text(ctx, "Dim hint text")
    R.ImGui_Spacing(ctx)
    G.button(ctx, "Button", nil, nil, "plain")
    R.ImGui_SameLine(ctx)
    G.button(ctx, "Primary")
    local c, v = R.ImGui_Checkbox(ctx, "Checkbox", pv.check)
    if c then pv.check = v end
    R.ImGui_SetNextItemWidth(ctx, -1)
    c, v = R.ImGui_SliderDouble(ctx, "##slider", pv.slider, 0, 1, "Slider %.2f")
    if c then pv.slider = v end
    R.ImGui_SetNextItemWidth(ctx, -1)
    c, v = R.ImGui_InputText(ctx, "##input", pv.input)
    if c then pv.input = v end
    R.ImGui_SetNextItemWidth(ctx, -1)
    c, v = R.ImGui_Combo(ctx, "##combo", pv.combo, "Combo item A\0Combo item B\0Combo item C\0")
    if c then pv.combo = v end
end

---------------------------------------------------------------------------
-- Theme list
---------------------------------------------------------------------------
-- list width: fits the longest name and the button rows below it
local function list_width()
    local pad, sp = style_x(R.ImGui_StyleVar_FramePadding()), style_x(R.ImGui_StyleVar_ItemSpacing())
    local w = math.max(tw("New") + tw("Duplicate"), tw("Rename") + tw("Delete")) + 4 * pad + sp
    for _, name in ipairs(names()) do
        local label = name
        w = math.max(w, R.ImGui_GetFrameHeight(ctx) + sp + tw(label)
            + 2 * style_x(R.ImGui_StyleVar_WindowPadding()) + style_x(R.ImGui_StyleVar_ScrollbarSize()))
    end
    return math.max(G.S(200), w)
end

local function theme_list(h)
    if not R.ImGui_BeginChild(ctx, "list", list_width(), h, R.ImGui_ChildFlags_Borders()) then return end
    for _, name in ipairs(names()) do
        R.ImGui_PushID(ctx, name)
        if R.ImGui_RadioButton(ctx, "##use", work.current == name) and work.current ~= name then
            work.current, dirty = name, true
            select_theme(name)   -- the manager previews the theme just picked
        end
        R.ImGui_SetItemTooltip(ctx, "Use this theme for all Lyx GUIs (after Save)")
        R.ImGui_SameLine(ctx)
        if renaming and name == sel then
            if rename_focus then R.ImGui_SetKeyboardFocusHere(ctx); rename_focus = false end
            R.ImGui_SetNextItemWidth(ctx, -1)
            local enter, buf = R.ImGui_InputText(ctx, "##rename", rename_buf,
                R.ImGui_InputTextFlags_EnterReturnsTrue() | R.ImGui_InputTextFlags_AutoSelectAll())
            rename_buf = buf
            if enter then commit_rename() elseif R.ImGui_IsItemDeactivated(ctx) then renaming = false end
        else
            local builtin = T.is_builtin(name)
            -- built-in preset: grey row, drawn as the Selectable's own "selected" background
            -- so it is exactly as tall as the hover highlight
            local grey = builtin and sel ~= name
            if grey then R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Header(), 0x8080802E) end
            if R.ImGui_Selectable(ctx, name, sel == name or grey) then select_theme(name) end
            if grey then R.ImGui_PopStyleColor(ctx) end
            if builtin then R.ImGui_SetItemTooltip(ctx, "Built-in preset (read-only): Duplicate it to make your own") end
            if R.ImGui_IsItemHovered(ctx) and R.ImGui_IsMouseDoubleClicked(ctx, 0) and not T.is_builtin(name) then
                renaming, rename_buf, rename_focus = true, name, true
            end
        end
        R.ImGui_PopID(ctx)
    end
    R.ImGui_EndChild(ctx)
end

local function list_buttons()
    local builtin = T.is_builtin(sel)
    if G.button(ctx, "New", nil, nil, "plain") then add_theme(unique("New theme"), T.preset(T.DEFAULT)) end
    R.ImGui_SameLine(ctx)
    if G.button(ctx, "Duplicate", nil, nil, "plain") then add_theme(unique(sel .. " copy"), work.themes[sel]) end
    R.ImGui_BeginDisabled(ctx, builtin)
    if G.button(ctx, "Rename", nil, nil, "plain") then renaming, rename_buf, rename_focus = true, sel, true end
    R.ImGui_SameLine(ctx)
    if G.button(ctx, "Delete", nil, nil, "plain") then confirm_del = true end
    R.ImGui_EndDisabled(ctx)
    if confirm_del and not builtin then
        G.color_text(ctx, G.warn, "Delete \"" .. sel .. "\"?")
        if G.button(ctx, "Delete", nil, nil, "bad") then
            work.themes[sel] = nil
            if work.current == sel then work.current = T.DEFAULT end
            select_theme(T.DEFAULT)
            dirty = true
        end
        R.ImGui_SameLine(ctx)
        if G.button(ctx, "Cancel", nil, nil, "plain") then confirm_del = false end
    end
end

---------------------------------------------------------------------------
-- Main
---------------------------------------------------------------------------
local function save()
    local ok, err = T.save(work)
    if not ok then msg = { "Save failed: " .. tostring(err), G.bad }; return end
    saved = T.load()
    work = T.copy(saved)
    if not work.themes[sel] then select_theme(work.current) end
    dirty, msg = false, { "Saved", G.good }
end

local function revert()
    work = T.copy(saved)
    select_theme(work.themes[sel] and sel or work.current)
    dirty, msg = false, nil
end

G.run(ctx, "Lyx Global Theme", function(ctx)
    -- Esc closes (checked first: a text field cancelled with Esc is still active here)
    if not R.ImGui_IsAnyItemActive(ctx) and R.ImGui_IsKeyPressed(ctx, R.ImGui_Key_Escape())
       and R.ImGui_IsWindowFocused(ctx, R.ImGui_FocusedFlags_RootAndChildWindows()) then
        return false
    end

    -- pin, top-right
    G.align_right(ctx, R.ImGui_GetFrameHeight(ctx))
    G.pin(ctx)

    local th = work.themes[sel]
    local _, avail_h = R.ImGui_GetContentRegionAvail(ctx)
    local body_h = avail_h - R.ImGui_GetFrameHeightWithSpacing(ctx) - G.S(8)

    -- left: list + buttons
    R.ImGui_BeginGroup(ctx)
    theme_list(body_h - R.ImGui_GetFrameHeightWithSpacing(ctx) * (confirm_del and 4 or 2))
    list_buttons()
    R.ImGui_EndGroup(ctx)

    -- middle: editors
    R.ImGui_SameLine(ctx)
    local avail_w = R.ImGui_GetContentRegionAvail(ctx)
    if R.ImGui_BeginChild(ctx, "edit", avail_w * 0.58, body_h, R.ImGui_ChildFlags_Borders()) then
        if T.is_builtin(sel) then
            G.dim_text(ctx, "Built-in presets are read-only. Duplicate one to make your own.")
        end
        R.ImGui_BeginDisabled(ctx, T.is_builtin(sel))
        editors(th)
        R.ImGui_EndDisabled(ctx)
        shared()
        R.ImGui_EndChild(ctx)
    end

    -- right: preview
    R.ImGui_SameLine(ctx)
    if R.ImGui_BeginChild(ctx, "preview", 0, body_h, R.ImGui_ChildFlags_Borders()) then
        preview()
        R.ImGui_EndChild(ctx)
    end

    -- footer
    R.ImGui_BeginDisabled(ctx, not dirty)
    if G.button(ctx, "Save", G.S(90)) then save() end
    R.ImGui_SameLine(ctx)
    if G.button(ctx, "Revert", G.S(90), nil, "plain") then revert() end
    R.ImGui_EndDisabled(ctx)
    R.ImGui_SameLine(ctx)
    R.ImGui_AlignTextToFramePadding(ctx)
    if dirty then G.color_text(ctx, G.warn, "● Unsaved changes")
    elseif msg then G.color_text(ctx, msg[2], msg[1]) end

    -- the manager wears the theme being edited (applied for the next frame)
    G.apply(work.themes[sel])
end, { w = 900, h = 560, min_w = 640, min_h = 420, esc = false, live = false })
