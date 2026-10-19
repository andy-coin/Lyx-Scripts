
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_Lyx_HOME")

    ---CUSTOM---

        --value get higer, zoom speed get slower
        speed_factor = 5

    local function midi()

        _,_,_,_,_,_,mouse_scroll  = reaper.get_action_context()
        
        abi = tonumber(api.load("abi","abi",false)) or 0
        
        E=reaper.MIDIEditor_GetActive()
        if abi % speed_factor == 0 then
            if  mouse_scroll > 0 then
                reaper.MIDIEditor_OnCommand(E,40140)--increase
            else -- mouse_scroll > 0 
                reaper.MIDIEditor_OnCommand(E,40141)--decrease
            end--]]
        end
        abi=abi % speed_factor + 1
        api.save("abi","abi",abi,false)
        
    end

    window,_,_=reaper.BR_GetMouseCursorContext()

    if  window == "midi_editor" then
        reaper.defer(midi)
    end
