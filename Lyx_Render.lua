
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_lib._Lyx_HOME")
    local L=require("_lib._Lyx_LaneName")

    -----CUSTOM-----
    open_when_done = true
    -- *.render_stats.html are moved here after rendering ("" = leave them next to the render)
    stats_folder = "/Users/shared/Reaper Projects/render_stats"
    dropbox = os.getenv("HOME")..'/Dropbox'

    if not r.Need("JS") then return end

    local function parent(p) -- "a/b/c" -> "a/b", works with / and \
        return p:match("^(.*)[/\\]")
    end

    local function dir_exists(p) -- has files or subfolders (a render folder never is empty)
        if p == "" then return false end
        if p:match("^%a:$") then p = p .. "\\" end -- "C:" -> "C:\"
        reaper.EnumerateFiles(p, -1) -- re-read, REAPER caches folder listings
        return (reaper.EnumerateFiles(p, 0) or reaper.EnumerateSubdirectories(p, 0)) ~= nil
    end

    local function is_absolute(p) -- "/x", "C:\x", "\\server\x"
        return p:match("^/") or p:match("^%a:[/\\]") or p:match("^\\\\")
    end

    -- RENDER_TARGETS = full file names joined by ";", wildcards resolved.
    -- A ";" inside a file name: the piece after it can't start like a full path
    -- ("/" and ":" are not allowed in file names), so glue it back to the one before.
    local function split_targets(targets)
        local files = {}
        for t in (targets .. ";"):gmatch("(.-);") do
            if is_absolute(t) or #files == 0 then files[#files + 1] = t
            else files[#files] = files[#files] .. ";" .. t end
        end
        return files
    end

    local function render_dirs() -- folders of the files this render writes
        local _, targets = reaper.GetSetProjectInfo_String(0, "RENDER_TARGETS", "", false)
        local dirs, seen = {}, {}
        for _, t in ipairs(split_targets(targets)) do
            local d = t ~= "" and parent(is_absolute(t) and t or (reaper.GetProjectPath() .. "/" .. t))
            if d and not seen[d] then seen[d], dirs[#dirs + 1] = true, d end
        end
        return dirs
    end

    local function render_stats() -- REAPER only updates these when a render completes
        local _, stats = reaper.GetSetProjectInfo_String(0, "RENDER_STATS", "", false)
        return stats
    end

    local function shared_dir(a, b) -- deepest folder that contains both (nil: different drives)
        while a and not (b == a or (b:sub(1, #a) == a and b:sub(#a + 1, #a + 1):match("[/\\]"))) do
            a = parent(a)
        end
        return a
    end

    local function open_dir(dirs)
        local dir = dirs[1]
        for i = 2, #dirs do dir = shared_dir(dir, dirs[i]) or dir end
        while dir and not dir_exists(dir) do dir = parent(dir) end -- e.g. $date changed meanwhile
        dir = dir or reaper.GetProjectPath()
        if dir:match("^%a:$") then dir = dir .. "\\" end

        if reaper.CF_ShellExecute then return reaper.CF_ShellExecute(dir) end -- SWS: no shell quoting
        local os_name = reaper.GetOS()
        if os_name:match("Win") then
            os.execute('start "" "' .. dir .. '"')
        else -- single quotes: safe for spaces, ', $, &, ( ...
            local q = "'" .. dir:gsub("'", "'\\''") .. "'"
            os.execute((os_name:match("OSX") or os_name:match("mac")) and ("open " .. q) or ("xdg-open " .. q .. " &"))
        end
    end

    local function move_stats(dirs)
        if stats_folder == "" then return end
        reaper.RecursiveCreateDirectory(stats_folder, 0)
        for _, d in ipairs(dirs) do
            reaper.EnumerateFiles(d, -1) -- re-read, REAPER caches folder listings
            local files, i = {}, 0
            repeat
                local f = reaper.EnumerateFiles(d, i)
                if f and f:match("%.render_stats%.html$") then files[#files + 1] = f end
                i = i + 1
            until not f
            for _, f in ipairs(files) do
                local src, dst = d .. "/" .. f, stats_folder .. "/" .. f
                if not os.rename(src, dst) then -- other drive: copy, then delete
                    local a, b = io.open(src, "rb"), io.open(dst, "wb")
                    if a and b then b:write(a:read("a")) end
                    if a then a:close() end
                    if b then b:close(); os.remove(src) end
                end
            end
        end
    end

    -- render progress window: "Rendering to file..." while busy, then "Finished in ..."
    -- It just closes on Cancel, and also on success when "automatically close" is on:
    -- then only new render stats tell a finished render from a cancelled one.
    local busy_seen, done = false, reaper.JS_Window_Find("Finished in", false) ~= nil -- ignore an old one
    local stats_before = render_stats()

    local function WaitRender()

        local busy = reaper.JS_Window_Find("Rendering to file", false)
        local finished = reaper.JS_Window_Find("Finished in", false)

        if  busy then
            busy_seen, done = true, false -- (another) render started
        elseif not done and (busy_seen or finished) then
            done = true
            local stats = render_stats()
            if  finished or stats ~= stats_before then -- else: cancelled
                local dirs = render_dirs()
                move_stats(dirs)
                if open_when_done then open_dir(dirs) end
            end
            stats_before = stats
        end

        if  not busy and not finished and not reaper.JS_Window_Find("Render to file", false) then
            L.all(true) -- position from create new version (-1 = stays hidden)
            return
        end

        reaper.defer(WaitRender)

    end

    local function main()

        L.all(false)

        reaper.Main_OnCommand(40015,0)--render

        WaitRender() -- always: lane names come back even when open_when_done = false

    end

    main()
