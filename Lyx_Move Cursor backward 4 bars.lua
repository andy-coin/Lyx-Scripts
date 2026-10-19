  
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")
    
    -----CUSTOM-----
    movement = -4
    --force_seek = false
    --auto_seek  = false


    local function main()
        
        local _,cursor,bar,qn_start,playing
        
        playing = api.gps() ~= 0

        cursor= (playing and api.gpc()) or api.gec()

        _,bar= reaper.TimeMap2_timeToBeats(0,cursor)

        _,qn_start = reaper.TimeMap_GetMeasureInfo(0,bar + movement)
        
        local new_cursor = reaper.TimeMap2_QNToTime(0,qn_start)
        
        api.sec(new_cursor,not playing,playing)
        
    end
    
    main()
    
    reaper.defer(function()end)
    
    
