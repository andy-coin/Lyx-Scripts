  
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_Lyx_HOME")
    
    local function main()
    
        Item=reaper.GetToggleCommandState(40253)
        Time=reaper.GetToggleCommandState(40076)
        
        if  Item==0 and Time==0 then
            reaper.Main_OnCommand(40076,0)
            r.billboard("Record Punch in mode - Time")
        elseif Item==0 and Time==1 then      
            reaper.Main_OnCommand(40253,0)
            r.billboard("Record Punch in mode - Item")
        elseif Time==0 and Item==1 then
            reaper.Main_OnCommand(40252,0)
            r.billboard("Record Punch in mode - Normal")
        end
        
    end
    
    main()
