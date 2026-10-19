    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_Lyx_HOME")
    
    -----CUSTOM-----
    open_when_done = true
    show_lane_name = false
    dropbox = os.getenv("HOME")..'/Dropbox'
    
    local function get_render_path()
        
        local _, directory = reaper.GetSetProjectInfo_String(0, "RENDER_FILE", "", false)
        
        if not _ then return end

        local _, pattern = reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", "", false)

        if not _ then return end
        
        local folder_name = ''

        for name in pattern:gmatch("[^/]*/") do
            
            if  name:find("$") then
                name = reaper.ResolveWildcards(0, -1, name, '')
            end

            folder_name = folder_name .. name    

        end

        directory = directory .. '/' .. folder_name

        return directory

    end

    local function OpenDirectoryWhenDone()
        
        if reaper.JS_Window_Find("Rendering to file...",false) then
            open = nil
        elseif not open and reaper.JS_Window_Find("Finished in",false) then
            open = true
            path = get_render_path()
            path = ESCPattern(path,true)
            os.execute('mv '..path..'/*.render_stats.html "/Users/shared/Reaper Projects/render_stats/"')
            os.execute('open '..path)
        elseif not reaper.JS_Window_Find("Render to file",false) then
            r.ShowHideTrackLaneNames("Show",show_lane_name) 
            return
        end

        reaper.defer(function() OpenDirectoryWhenDone(path) end)

    end
    
    local function main()
        
        r.ShowHideTrackLaneNames("Hide",show_lane_name)
        
        reaper.Main_OnCommand(40015,0)--render
        
        if open_when_done then OpenDirectoryWhenDone() end
        
        reaper.defer(function() end)
        
    end
    
    main()
