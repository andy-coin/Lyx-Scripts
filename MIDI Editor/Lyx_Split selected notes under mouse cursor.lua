
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")

    local function main()

        local editor = reaper.MIDIEditor_GetActive()
        
        local is_new_value,filename,sectionID,cmdID,mode,resolution,val,contextstr = reaper.get_action_context()
        
        
        local take = reaper.MIDIEditor_GetTake(editor)
        local _, noteCount, _, _ = reaper.MIDI_CountEvts(take)

        api.ubb()

        for abi = 0, noteCount - 1 do
            local retval, selected, muted, startppqpos, endppqpos, chan, pitch, vel = reaper.MIDI_GetNote(take, abi)

            if  selected then
                local start_time = reaper.MIDI_GetProjTimeFromPPQPos(take, startppqpos)
                local end_time = reaper.MIDI_GetProjTimeFromPPQPos(take, endppqpos)

                if  end_time > mouse_pos and start_time < mouse_pos then
                    local new_endppqpos = reaper.MIDI_GetPPQPosFromProjTime(take, mouse_pos)
                    reaper.MIDI_SetNote(take, abi, selected, muted, startppqpos, new_endppqpos, chan, pitch, vel, false)
                end
            end
        end

        reaper.MIDI_Sort(take)
        api.ueb(0,"Trim selected note length at mouse",-1)
        api.ua()

    end

    local function main()

        local editor = api.M()

        msg("^_^")
        local tk,tk_idx,time,timeout,ITs
            
        tk_idx = 0
        time = api.now()
        timeout = 3
        ITs={}
        
        api.mcw()
        local mouse_pos = api.mcp()
        -- local e_cursor = api.gec()
        -- api.pur(1)
        -- api.sec(m_cursor,false,false)

        while (api.now() - time < timeout) do 
            
            local take = reaper.MIDIEditor_EnumTakes(editor, tk_idx, true)
            if not take then break end
            
            ITs[#ITs+1] = reaper.GetMediaItemTake_Item(take)
            
            
            local note = reaper.MIDI_EnumSelNotes(take, -1)
            if note == -1 then goto NEXT end
            
            while (api.now() - time < timeout) do
                
                note = reaper.MIDI_EnumSelNotes(take, note)
                if note == -1 then goto NEXT end

                local retval, selected, muted, startppqpos, endppqpos, chan, pitch, vel = reaper.MIDI_GetNote(take, note)

                local start_time = reaper.MIDI_GetProjTimeFromPPQPos(take, startppqpos)
                local end_time = reaper.MIDI_GetProjTimeFromPPQPos(take, endppqpos)

                if  end_time > mouse_pos and start_time < mouse_pos then
                    local new_endppqpos = reaper.MIDI_GetPPQPosFromProjTime(take, mouse_pos)
                    reaper.MIDI_SetNote(take, note, selected, muted, startppqpos, new_endppqpos, chan, pitch, vel, false)
                end

                note = note + 1
            end

            ::NEXT::
            tk_idx = tk_idx +1

        end     

        --api.sec(e_cursor,false,false)
        --api.pur(-1)

    end

    main()

