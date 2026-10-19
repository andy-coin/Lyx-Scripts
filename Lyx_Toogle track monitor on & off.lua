    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_Lyx_HOME")
    
    -----CUSTOM-----
    three_step = false
    
    local function main()
    
        for abi=1,reaper.CountSelectedTracks(0) do
            tr=reaper.GetSelectedTrack(0,abi-1)
            if  reaper.GetMediaTrackInfo_Value(tr,"I_RECMON")~=0 then
                monitor = true
                break
            end
        end
        
        
        for abi=1,reaper.CountSelectedTracks(0) do
            tr=reaper.GetSelectedTrack(0,abi-1)
            local input = reaper.GetMediaTrackInfo_Value(tr,"I_RECINPUT")
            local mon = reaper.GetMediaTrackInfo_Value(tr,"I_RECMON")
            mode = (input < 4096 and 2 ) or 1
            if three_step then
                reaper.SetMediaTrackInfo_Value(tr,"I_RECMON",(mon+1)%3)
            else
                reaper.SetMediaTrackInfo_Value(tr,"I_RECMON",(not monitor and mode) or 0)
            end
        end
        
        api.ua()
        state=(not monitor and "On" ) or "Off"
        
        r.billboard("Set track monitor state : "..state)
    
    end
    
    main()
    
    reaper.defer(function()end)
