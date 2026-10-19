  
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")
    if not r.Need("SWS") then return end
    
    --------------
    local function main()
        
        local editor, time, timeout, tk_idx, tk

        editor = reaper.MIDIEditor_GetActive()
        if not editor then return end

        api.ubb()

        time = api.now()
        timeout = 15
        tk_idx = 0

        while (api.now() - time < timeout) do 
            
            tk = reaper.MIDIEditor_EnumTakes(editor, tk_idx, true)

            if not tk then break end

            local _, cc_n
                
            reaper.BR_MIDI_CCLaneReplace(editor,0,64)

            --delete selection old cc values
            _,_,cc_n = reaper.MIDI_CountEvts(tk)
            for abii = cc_n, 1, -1 do
                local _,_,_,position, chanmsg, chan, lane, msg3 = reaper.MIDI_GetCC(tk, abii-1)
                if  lane == 64 and msg3%127 ~= 0 then
                    reaper.MIDI_DeleteCC(tk, abii-1)
                end
            end

            tk_idx = tk_idx +1
            
        end

        ::END::
        
        reaper.MIDIEditor_OnCommand(editor,40669)--Unselect all CC events in last clicked lane

        api.ueb(0,"Clear sustain pedal continuous CC",-1)
        
    end
    main()