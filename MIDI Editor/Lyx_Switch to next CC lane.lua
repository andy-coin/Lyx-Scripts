
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")

    local function main()

        local editor,take,current_lane,abi,new_lane

        editor = reaper.MIDIEditor_GetActive()
        
        if not editor then return end

        take = reaper.MIDIEditor_GetTake(editor)
        
        if not take then return end
        
        api.ubb()
        
        current_lane = reaper.MIDIEditor_GetSetting_int(editor, "last_clicked_cc_lane")
        current_lane = ( current_lane > 119 and current_lane - 511 ) or current_lane + 10
        --current_lane = ( current_lane > 119 and -1 ) or current_lane
    
        abi = 0
        repeat
            reaper.MIDIEditor_OnCommand(editor,40671)--unselect all cc
            reaper.MIDIEditor_OnCommand(editor,40234)--next cc lane
            reaper.MIDIEditor_OnCommand(editor,40668)-- select all cc in lanes
            has_events = reaper.MIDI_EnumSelCC(take,0)            
            abi = abi+1
        until has_events ~= -1 or abi > 128

        new_lane = reaper.MIDIEditor_GetSetting_int(editor,"last_clicked_cc_lane")
        new_lane = ( new_lane > 119 and new_lane - 521 ) or new_lane

        if  new_lane < current_lane - 10 then 
            reaper.MIDIEditor_OnCommand(editor,40237)--fall back to velocity lane
            new_lane = 512
        end
        
        api.save('midi_cc_lane',tostring(take),new_lane,false)
        
        reaper.MIDIEditor_OnCommand(editor,40214)--unselect all cc
        
        api.ueb(0,'Switch to next active CC lane',-1)
         
    end

    api.cc()
    main()
    reaper.defer(function()end)
