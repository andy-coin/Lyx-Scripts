--[[
    FFMPEG — replace the audio of video files (job list).

    Add videos:  selected video items (opened automatically), "Add videos…", or drag files
                 from Finder onto the window. Audio files dropped on the window go to
                 the first job without audio; drop on a row's audio button to target it.
    Audio:       pick a file, or "Render" = the file your last render settings write.
    Codec:       AAC (copied as-is when the audio already is AAC/M4A) or lossless
                 (mov → PCM, mp4/m4v → ALAC, others → copy).
    Output:      <video>_Remuxed(-NN).<ext> next to the video. Jobs run in the background.
                 For video items, the item's source is swapped only after ffmpeg succeeds.
]]
local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
package.path = package.path .. ";" .. script_path .. "?.lua"

---------------------------------------------------------------------------
-- Pure helpers
---------------------------------------------------------------------------
local function split_path(p)
    local dir, name, ext = p:match("^(.-)([^/\\]-)%.([^%./\\]+)$")
    return dir or "", name or p, (ext or ""):lower()
end

local VIDEO = { mov = 1, mp4 = 1, m4v = 1, avi = 1, mkv = 1 }
local AUDIO = { wav = 1, aif = 1, aiff = 1, m4a = 1, aac = 1, mp3 = 1, flac = 1, caf = 1 }

local function audio_args(vext, aext, codec, bitrate)
    if codec == "aac" then
        if aext == "m4a" or aext == "aac" then return "-c:a copy" end
        return "-c:a aac -b:a " .. bitrate
    end
    if vext == "mov" then
        return (aext == "wav" or aext == "aif" or aext == "aiff") and "-c:a copy" or "-c:a pcm_s24le"
    elseif vext == "mp4" or vext == "m4v" then
        return "-c:a alac"
    end
    return "-c:a copy"
end

local function unique_out(dir, name, ext, exists)
    local p = dir .. name .. "_Remuxed." .. ext
    local i = 0
    while exists(p) and i < 99 do
        i = i + 1
        p = ("%s%s_Remuxed-%02d.%s"):format(dir, name, i, ext)
    end
    return p
end

if not reaper then -- self-check: lua "Lyx_FFMPEG replace audio in video(McS).lua"
    local d, n, e = split_path("/a b/clip.final.MOV")
    assert(d == "/a b/" and n == "clip.final" and e == "mov")
    assert(audio_args("mp4", "wav", "aac", "320k") == "-c:a aac -b:a 320k")
    assert(audio_args("mp4", "m4a", "aac", "320k") == "-c:a copy")
    assert(audio_args("mp4", "wav", "lossless") == "-c:a alac")
    assert(audio_args("mov", "wav", "lossless") == "-c:a copy")
    assert(audio_args("mov", "mp3", "lossless") == "-c:a pcm_s24le")
    local taken = { ["/v/x_Remuxed.mp4"] = true, ["/v/x_Remuxed-01.mp4"] = true }
    assert(unique_out("/v/", "x", "mp4", function(p) return taken[p] end) == "/v/x_Remuxed-02.mp4")
    return print("FFMPEG self-check OK")
end

---------------------------------------------------------------------------
require("_Lyx_HOME")
local G = require("_Lyx_GUI")
local R = reaper
local EXT = "Lyx_FFMPEG"
local WIN = R.GetOS():find("Win") ~= nil
local MAC = R.GetOS():find("OSX") ~= nil or R.GetOS():find("mac") ~= nil
local TMP = (os.getenv("TMPDIR") or (WIN and os.getenv("TEMP")) or "/tmp/"):gsub("([^/\\])$", "%1/")

local function find_ffmpeg()
    local list = WIN and { R.GetResourcePath() .. "\\UserPlugins\\ffmpeg.exe" }
                 or { "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg",
                      R.GetResourcePath() .. "/UserPlugins/ffmpeg" }
    for _, p in ipairs(list) do if R.file_exists(p) then return p end end
end
local FFMPEG = find_ffmpeg()

local codec = R.GetExtState(EXT, "codec") ~= "" and R.GetExtState(EXT, "codec") or "aac"
local BITRATES = { "256k", "320k", "512k" }
local br_idx = tonumber(R.GetExtState(EXT, "br")) or 2

-- Permute prompt
do
    local app = "/Applications/Permute 3.app"
    if not WIN and R.file_exists(app .. "/Contents/Info.plist")
       and R.MB("Also open the converter app Permute 3?", "FFMPEG replace audio", 4) == 6 then
        os.execute('open -a "Permute 3"')
    end
end

---------------------------------------------------------------------------
-- Jobs
---------------------------------------------------------------------------
local jobs, job_id = {}, 0

local function add_job(video, item, take)
    for _, j in ipairs(jobs) do if j.video == video and j.item == item then return end end
    job_id = job_id + 1
    jobs[#jobs + 1] = { id = job_id, video = video, item = item, take = take, status = "wait" }
end

local function add_files(paths)
    for _, p in ipairs(paths) do
        local _, _, ext = split_path(p)
        if VIDEO[ext] then add_job(p) end
    end
    for _, p in ipairs(paths) do
        local _, _, ext = split_path(p)
        if AUDIO[ext] then
            for _, j in ipairs(jobs) do
                if not j.audio and j.status == "wait" then j.audio = p; break end
            end
        end
    end
end

-- selected video items
for i = 0, R.CountSelectedMediaItems(0) - 1 do
    local it = R.GetSelectedMediaItem(0, i)
    local tk = R.GetActiveTake(it)
    if tk and not R.TakeIsMIDI(tk) then
        local src = R.GetMediaItemTake_Source(tk)
        local file = R.GetMediaSourceFileName(src)
        local _, _, ext = split_path(file)
        if R.GetMediaSourceType(src) == "VIDEO" or VIDEO[ext] then add_job(file, it, tk) end
    end
end

local function render_file()
    local _, targets = R.GetSetProjectInfo_String(0, "RENDER_TARGETS", "", false)
    for f in (targets or ""):gmatch("[^;]+") do if R.file_exists(f) then return f end end
end

-- quote a path for the job script: .bat uses double quotes (% doubled), sh uses single quotes
local function q(s)
    if WIN then return '"' .. s:gsub("%%", "%%%%") .. '"' end
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function start(j)
    local dir, name, vext = split_path(j.video)
    local _, _, aext = split_path(j.audio)
    j.out = unique_out(dir, name, vext, R.file_exists)
    local cmd = table.concat({ q(FFMPEG), "-y -hide_banner -i", q(j.video), "-i", q(j.audio),
        "-map 0:v:0 -map 1:a:0 -c:v copy", audio_args(vext, aext, codec, BITRATES[br_idx]), q(j.out) }, " ")
    j.status = "run"
    -- run in the background; the script writes ffmpeg's exit code to the .done file
    local base = TMP .. "lyx_ffmpeg_" .. j.id .. "_" .. math.floor(R.time_precise() * 1000)
    j.logf, j.donef = base .. ".log", base .. ".done"
    j.script = base .. (WIN and ".bat" or ".sh")
    local f = io.open(j.script, "w")
    if WIN then
        f:write("@echo off\r\nchcp 65001 >nul\r\n", cmd, " > ", q(j.logf), " 2>&1\r\necho %ERRORLEVEL% > ", q(j.donef), "\r\n")
    else
        f:write(cmd, " > ", q(j.logf), " 2>&1\necho $? > ", q(j.donef), "\n")
    end
    f:close()
    R.ExecProcess(WIN and ('cmd.exe /C "' .. j.script .. '"') or ("/bin/sh " .. q(j.script)), -1)
end

local function finish(j)
    if j.logf then
        local f = io.open(j.logf); j.log = f and f:read("a") or ""; if f then f:close() end
    end
    if j.code == 0 and R.file_exists(j.out) then
        j.status = "ok"
        if j.take and R.ValidatePtr2(0, j.take, "MediaItem_Take*") then
            R.Undo_BeginBlock()
            local src = R.PCM_Source_CreateFromFile(j.out)
            R.SetMediaItemTake_Source(j.take, src)
            local _, n, e = split_path(j.out)
            R.GetSetMediaItemTakeInfo_String(j.take, "P_NAME", n .. "." .. e, true)
            R.UpdateItemInProject(j.item)
            R.Undo_EndBlock("Remux audio to video file", -1)
            R.UpdateArrange()
        end
    else
        j.status = "fail"
    end
end

local function poll()
    for _, j in ipairs(jobs) do
        if j.status == "run" then
            if R.file_exists(j.donef) then
                local f = io.open(j.donef); local s = f and f:read("a") or ""; if f then f:close() end
                if s:match("%d") then
                    j.code = tonumber(s:match("%-?%d+"))
                    finish(j)
                    os.remove(j.donef); os.remove(j.script)
                end
            end
        end
    end
end

local function reveal(p)
    if WIN then R.ExecProcess('explorer /select,"' .. p .. '"', -1)
    elseif MAC then os.execute("open -R " .. q(p))
    else os.execute("xdg-open " .. q(split_path(p)) .. " &") end
end

local function pick_audio(j)
    local ok, f = R.GetUserFileNameForRead("", "Choose audio for: " .. select(2, split_path(j.video)), "")
    if ok then j.audio = f end
end

local function browse_videos()
    if not R.JS_Dialog_BrowseForOpenFiles then return end
    local rv, files = R.JS_Dialog_BrowseForOpenFiles("Add videos", "", "",
        "Video\0*.mov;*.mp4;*.m4v;*.avi;*.mkv\0\0", true)
    if rv < 1 then return end
    local list = {}
    if not files:find("\0", 1, true) then
        list[1] = files
    else
        local dir = files:match("^[^\0]*")
        if dir ~= "" and not dir:match("[/\\]$") then dir = dir .. "/" end
        for f in files:gmatch("\0([^\0]+)") do list[#list + 1] = (f:sub(1, 1) == "/") and f or (dir .. f) end
    end
    add_files(list)
end

local function dropped_files(ctx)
    local paths = {}
    if R.ImGui_BeginDragDropTarget(ctx) then
        local rv, count = R.ImGui_AcceptDragDropPayloadFiles(ctx)
        if rv then
            for i = 0, count - 1 do
                local ok, f = R.ImGui_GetDragDropPayloadFile(ctx, i)
                if ok then paths[#paths + 1] = f end
            end
        end
        R.ImGui_EndDragDropTarget(ctx)
    end
    return paths
end

---------------------------------------------------------------------------
-- GUI
---------------------------------------------------------------------------
local ctx = G.new("FFMPEG", "FFMPEG")
if not ctx then return end
local STATUS = { wait = "Waiting", run = "Working…", ok = "Done", fail = "Failed" }

local function base(p) local _, n, e = split_path(p); return n .. "." .. e end

local function job_row(ctx, j, i)
    R.ImGui_PushID(ctx, j.id)
    R.ImGui_TableNextRow(ctx)

    R.ImGui_TableNextColumn(ctx)
    R.ImGui_AlignTextToFramePadding(ctx)
    R.ImGui_Text(ctx, base(j.video))
    R.ImGui_SetItemTooltip(ctx, j.video .. (j.item and "\n(from an item in the project, replaced automatically when done)" or ""))

    R.ImGui_TableNextColumn(ctx)
    local busy = j.status ~= "wait"
    R.ImGui_BeginDisabled(ctx, busy)
    if R.ImGui_Button(ctx, j.audio and base(j.audio) or "Choose audio…", -G.S(56)) then pick_audio(j) end
    if j.audio then R.ImGui_SetItemTooltip(ctx, j.audio) end
    for _, f in ipairs(dropped_files(ctx)) do
        local _, _, e = split_path(f)
        if AUDIO[e] then j.audio = f end
    end
    R.ImGui_SameLine(ctx)
    local rf = render_file()
    R.ImGui_BeginDisabled(ctx, not rf)
    if R.ImGui_SmallButton(ctx, "Render") then j.audio = rf end
    R.ImGui_EndDisabled(ctx)
    R.ImGui_SetItemTooltip(ctx, rf and ("Use the latest render:\n" .. rf) or "No recent render found")
    R.ImGui_EndDisabled(ctx)

    R.ImGui_TableNextColumn(ctx)
    local col = (j.status == "ok" and G.good) or (j.status == "fail" and G.bad) or (j.status == "run" and G.warn) or G.dim
    G.color_text(ctx, col, STATUS[j.status])
    if j.status == "fail" and j.log then R.ImGui_SetItemTooltip(ctx, j.log:sub(-800)) end
    if j.status == "ok" then
        R.ImGui_SameLine(ctx)
        if R.ImGui_SmallButton(ctx, "Show") then reveal(j.out) end
        R.ImGui_SetItemTooltip(ctx, j.out)
    end

    R.ImGui_TableNextColumn(ctx)
    local remove = false
    R.ImGui_BeginDisabled(ctx, j.status == "run")
    if R.ImGui_SmallButton(ctx, "×") then remove = true end
    R.ImGui_EndDisabled(ctx)
    R.ImGui_PopID(ctx)
    return remove
end

G.run(ctx, "FFMPEG — Replace video audio", function(ctx)
    poll()

    if not FFMPEG then
        G.color_text(ctx, G.bad, "ffmpeg not found. Install it with Homebrew (brew install ffmpeg) or put it in REAPER/UserPlugins.")
    end

    -- job list (also the drop zone)
    local _, avail_h = R.ImGui_GetContentRegionAvail(ctx)
    local list_h = math.max(G.S(120), avail_h - G.S(90) - R.ImGui_GetFrameHeightWithSpacing(ctx))
    if R.ImGui_BeginChild(ctx, "jobs", 0, list_h, R.ImGui_ChildFlags_Borders()) then
        if #jobs == 0 then
            R.ImGui_Dummy(ctx, 1, G.S(30))
            G.dim_text(ctx, "Drag videos (and audio) here from Finder, or click \"Add videos…\" below")
        else
            local flags = R.ImGui_TableFlags_RowBg() | R.ImGui_TableFlags_SizingStretchProp()
            if R.ImGui_BeginTable(ctx, "t", 4, flags) then
                R.ImGui_TableSetupColumn(ctx, "Video", 0, 3)
                R.ImGui_TableSetupColumn(ctx, "Audio", 0, 4)
                R.ImGui_TableSetupColumn(ctx, "Status", 0, 2)
                R.ImGui_TableSetupColumn(ctx, "", 0, 0.4)
                R.ImGui_TableHeadersRow(ctx)
                local drop
                for i, j in ipairs(jobs) do if job_row(ctx, j, i) then drop = i end end
                if drop then table.remove(jobs, drop) end
                R.ImGui_EndTable(ctx)
            end
        end
        R.ImGui_EndChild(ctx)
    end
    add_files(dropped_files(ctx))

    -- codec
    R.ImGui_AlignTextToFramePadding(ctx)
    R.ImGui_Text(ctx, "Audio codec")
    R.ImGui_SameLine(ctx)
    if R.ImGui_RadioButton(ctx, "AAC", codec == "aac") then codec = "aac" end
    if codec == "aac" then
        R.ImGui_SameLine(ctx)
        R.ImGui_SetNextItemWidth(ctx, G.S(80))
        local c, v = R.ImGui_Combo(ctx, "##br", br_idx - 1, table.concat(BITRATES, "\0") .. "\0")
        if c then br_idx = v + 1 end
    end
    R.ImGui_SameLine(ctx)
    if R.ImGui_RadioButton(ctx, "Lossless", codec == "lossless") then codec = "lossless" end
    R.ImGui_SetItemTooltip(ctx, "mov → PCM 24-bit; mp4 / m4v → ALAC; other containers copy as is")

    -- theme
    R.ImGui_AlignTextToFramePadding(ctx)
    R.ImGui_Text(ctx, "Theme")
    R.ImGui_SameLine(ctx)
    G.theme_row(ctx, "FFMPEG")

    -- actions
    if R.ImGui_Button(ctx, "Add videos…") then browse_videos() end
    R.ImGui_SameLine(ctx)
    local ready, waiting = FFMPEG ~= nil, 0
    for _, j in ipairs(jobs) do
        if j.status == "wait" then
            waiting = waiting + 1
            if not j.audio then ready = false end
        end
    end
    R.ImGui_BeginDisabled(ctx, not ready or waiting == 0)
    if G.button(ctx, ("Start (%d)"):format(waiting), G.S(110)) then
        for _, j in ipairs(jobs) do if j.status == "wait" then start(j) end end
    end
    R.ImGui_EndDisabled(ctx)
    if waiting > 0 and not ready and FFMPEG then
        R.ImGui_SameLine(ctx)
        G.color_text(ctx, G.warn, "Some videos have no audio yet")
    end
end, {
    w = 640, h = 380,
    on_close = function()
        R.SetExtState(EXT, "codec", codec, true)
        R.SetExtState(EXT, "br", tostring(br_idx), true)
    end,
})
