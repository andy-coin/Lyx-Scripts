-- Select every item in the project that matches the selected items by
--   1. Same name         : active take name
--   2. Same audio source : the file the active take plays (greyed out when only MIDI is selected)
--   3. Pool data         : MIDI items sharing the same pooled data (greyed out when no MIDI is selected)
-- Opens a small window at the mouse; click a button (or press 1/2/3), Esc closes.

if reaper.CountSelectedMediaItems(0) == 0 then return end
if not reaper.ImGui_CreateContext then
    reaper.MB("This script needs ReaImGui, please install it with ReaPack.", "Lyx Scripts", 0)
    return
end

local function SourceFile(take)
    local src = reaper.GetMediaItemTake_Source(take)
    if not src then return end
    src = reaper.GetMediaSourceParent(src) or src -- reversed / section sources
    local f = reaper.GetMediaSourceFileName(src)
    return f ~= "" and f or nil
end

local function PoolID(item)
    local _, chunk = reaper.GetItemStateChunk(item, "", false)
    return chunk:match("POOLEDEVTS%s+(%b{})")
end

-- what the selection holds
local names, files, pools = {}, {}, {}
local has_audio, has_midi = false, false
for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local take = reaper.GetActiveTake(item)
    if take then
        names[reaper.GetTakeName(take)] = true
        if reaper.TakeIsMIDI(take) then
            has_midi = true
            local id = PoolID(item)
            if id then pools[id] = true end
        else
            has_audio = true
            local f = SourceFile(take)
            if f then files[f] = true end
        end
    end
end

local MODES = {
    { label = "1. Same name",         enabled = true,      key = "name"   },
    { label = "2. Same audio source", enabled = has_audio, key = "source" },
    { label = "3. Pool data",         enabled = has_midi,  key = "pool"   },
}

local function Run(mode)
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    for i = 0, reaper.CountMediaItems(0) - 1 do
        local item = reaper.GetMediaItem(0, i)
        local take = reaper.GetActiveTake(item)
        local hit = false
        if take then
            if mode == "name" then
                hit = names[reaper.GetTakeName(take)]
            elseif mode == "source" then
                hit = not reaper.TakeIsMIDI(take) and files[SourceFile(take) or ""]
            elseif mode == "pool" then
                hit = reaper.TakeIsMIDI(take) and pools[PoolID(item) or ""] -- chunk read only for MIDI items
            end
        end
        if hit then reaper.SetMediaItemSelected(item, true) end
    end
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Select items with same " .. mode, -1)
end

local ctx = reaper.ImGui_CreateContext("Lyx select same")
local mx, my = reaper.GetMousePosition()
if reaper.ImGui_PointConvertNative then mx, my = reaper.ImGui_PointConvertNative(ctx, mx, my, false) end
local first = true

local function loop()
    if first then reaper.ImGui_SetNextWindowPos(ctx, mx, my, reaper.ImGui_Cond_Appearing(), 0.5, 0.5) end
    first = false
    local flags = reaper.ImGui_WindowFlags_AlwaysAutoResize() | reaper.ImGui_WindowFlags_NoCollapse()
    local visible, open = reaper.ImGui_Begin(ctx, "Select items with same...", true, flags)
    local chosen
    if visible then
        for i, m in ipairs(MODES) do
            if not m.enabled then reaper.ImGui_BeginDisabled(ctx) end
            local w = reaper.ImGui_CalcTextSize(ctx, "2. Same audio source") + 24
            if reaper.ImGui_Button(ctx, m.label, w) and m.enabled then chosen = m.key end
            if m.enabled and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_1() + i - 1, false) then chosen = m.key end
            if not m.enabled then reaper.ImGui_EndDisabled(ctx) end
        end
        if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape(), false) then open = false end
        reaper.ImGui_End(ctx)
    end
    if chosen then Run(chosen) return end
    if open then reaper.defer(loop) end
end
reaper.defer(loop)
