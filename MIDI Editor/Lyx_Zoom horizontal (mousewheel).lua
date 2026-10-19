
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_Lyx_HOME")
    if not r.Need("SWS") then return end

    ---CUSTOM---

        --value get higer, zoom speed get slower
        speed_factor = 2
        
        reverse = false
        
        reverse = (reverse and -1) or 1
        
    local function midi()
        
        _,_,_,_,_,_,mouse_scroll  = reaper.get_action_context()
        
        mouse_scroll = mouse_scroll * reverse
        
        abi = tonumber(api.load("abi","abi",false)) or 0
        
        api.mcw()
        mouse = api.mcp()
        
        E=reaper.MIDIEditor_GetActive()
        take = reaper.MIDIEditor_GetTake(E)
        
        if  take then
            item = api.gtkv(take,"P_ITEM")
            if  item then
                s = api.giv(item,"D_POSITION")
                e = s + api.giv(item,"D_LENGTH")
                if  mouse<s or mouse>e then
                    out = true
                end
            end
        end
        
        if abi % speed_factor == 0 then
            --zoom center to edit cursor
            local zoommode = reaper.SNM_GetIntConfigVar("zoommode", -1) -- user's zoom center pref, restored below
            if out then api.cmd(api.name("_WOL_SETHZOOMC_EDITCUR"),0) end
            if  mouse_scroll > 0 then
                reaper.MIDIEditor_OnCommand(E,1011)--increase
            else -- mouse_scroll > 0 
                reaper.MIDIEditor_OnCommand(E,1012)--decrease
            end
            --restore the user's zoom center
            if  out and zoommode ~= -1 then reaper.SNM_SetIntConfigVar("zoommode", zoommode) end
        end
        abi=abi % speed_factor + 1
        api.save("abi","abi",abi,false)
        
    end

    window,_,_=reaper.BR_GetMouseCursorContext()

    if  window == "midi_editor" then
        reaper.defer(midi)
    end
