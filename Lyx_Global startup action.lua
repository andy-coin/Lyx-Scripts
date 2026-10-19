    

    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    --script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    
    --api.save('timeline','color',16757568,true)

    Commands={
                --Project_time_counter  = "_RSea6edc0e0d7e7441c62604c361905d60bb5036e8",
                --Pomodoro              = "_RSb9aebd70156ddb87228b09ed0e312d7114e4234b",
                --Adaptive_grid         = (api.gtc(api.name("_RS18326a165ec53a69aedced71d97a0f95715a0a8a"))~=1 and api.name("_RS18326a165ec53a69aedced71d97a0f95715a0a8a")) or 0,
                Reset_midi_device     = "_RS90f3763d658582713a7aeb1b68f0c59ba361051a",
                Side_mixer            = "_RSb546cb9c6cf507646be9ef1d0cf6d1cb6e0642f9",
                Realauncher           = (reaper.GetProjectName()=='' and "_RS814f41d5db3af75d220c53bc79228746acb62b80") or 40769,
                Solo_in_place         = (reaper.GetToggleCommandState(40745)==1 and 40745 ) or 40769,
                clear_cmd_override    = 24800
                }
    
    for _,command in pairs(Commands) do
        reaper.Main_OnCommand(reaper.NamedCommandLookup(command),0)
    end
    
    --enable grouping 
    item_group  = reaper.GetToggleCommandState(1156) == 1
    if not item_group then api.cmd(1156,0) end
  
    reaper.SetExtState("Play mode","Play mode",0,false)
    reaper.SetExtState("Grid","Grid lock",0,false)
    reaper.SetProjExtState(0,"Side Mixer",'track_states',"")
    
    --os.execute('open -a Cold\\ Turkey\\ Blocker')
    
    reaper.defer(function() end)
