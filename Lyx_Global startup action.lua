    

    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    
    --api.save('timeline','color',16757568,true)

    Commands={
                --Project_time_counter  = "_RSea6edc0e0d7e7441c62604c361905d60bb5036e8",
                --Pomodoro              = "_RSb9aebd70156ddb87228b09ed0e312d7114e4234b",
                --Adaptive_grid         = (api.gtc(api.name("_RS18326a165ec53a69aedced71d97a0f95715a0a8a"))~=1 and api.name("_RS18326a165ec53a69aedced71d97a0f95715a0a8a")) or 0,
                Reset_midi_device     = r.ScriptID("Lyx Scripts/Lyx_Reset all midi device in background.lua",0,true),
                Side_mixer            = r.ScriptID("Lyx Scripts/Lyx_Side mixer.lua",0,true),
                Realauncher           = (reaper.GetProjectName()=='' and r.ScriptID("Lyx Scripts/Realauncher 2.5.2 (Lyx mod).lua",0,true)) or 40769,
                Solo_in_place         = (reaper.GetToggleCommandState(40745)==1 and 40745 ) or 40769,
                clear_cmd_override    = 24800
                }
    
    for _,command in pairs(Commands) do
        command = reaper.NamedCommandLookup(tostring(command))
        if command ~= 0 then reaper.Main_OnCommand(command,0) end
    end
    
    --enable grouping 
    item_group  = reaper.GetToggleCommandState(1156) == 1
    if not item_group then api.cmd(1156,0) end
  
    reaper.SetExtState("Play mode","Play mode",0,false)
    reaper.SetExtState("Grid","Grid lock",0,false)
    reaper.SetProjExtState(0,"Side Mixer",'track_states',"")
    
    --os.execute('open -a Cold\\ Turkey\\ Blocker')
    
    reaper.defer(function() end)
