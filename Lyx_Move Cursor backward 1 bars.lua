  
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    
    -----CUSTOM-----
    
    --force_seek = false
    --auto_seek  = false

    local function main()
        
        local _,cursor,bar,beats,division,abi,qn_start ,playing
        
        playing = api.gps()~=0
        cursor= (playing and api.gpc()) or api.gec()

        _,bar,_,beats = reaper.TimeMap2_timeToBeats(0,cursor)
        
        beats = reaper.TimeMap_timeToQN_abs(0,cursor)
        
        _, division = reaper.GetSetProjectGrid( 0, 0, 0, 0, 0 )
        
        if  division < 1/8 then
            qn_start = math.floor(beats) - 1--(32*division)
        else
            _,qn_start = reaper.TimeMap_GetMeasureInfo(0,bar)
            if  beats <= qn_start + 1 then
                _,qn_start = reaper.TimeMap_GetMeasureInfo(0,bar-1)
            end
        end
        
        local new_cursor = reaper.TimeMap2_QNToTime(0,qn_start)
        
        api.sec(new_cursor,not playing,playing)

        
    end
    
    main()
    
    reaper.defer(function()end)
    
    
