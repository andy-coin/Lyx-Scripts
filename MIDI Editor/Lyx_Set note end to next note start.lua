    
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_Lyx_HOME")
    
    local function main()

        local itemz,editor,midi_takes
        
        editor = reaper.MIDIEditor_GetActive()
        if not editor then return end
        
        local state = api.load('Midi_editor','move note state')
        
        if  state == '1' or state == 'ON' then
            api.Mcmd(editor,api.name('_RS7d3c_29381f109b4a1c8b2759ec74e1b5a17dff6c4e12'))--move note up
            return
        end
        
        midi_takes={}
        
        local abi=1
        repeat
            local take = reaper.MIDIEditor_EnumTakes(editor,abi-1,false)
            if  take then
                midi_takes[#midi_takes+1] = take
                abi = abi+1
            else
                break
            end
        until not take        
        
        api.ubb()
        
        for abi = 1,#midi_takes do
            local take = midi_takes[abi]
            local _, noteCount = reaper.MIDI_CountEvts(take) 
            --local _,selected,muted,last_startppqpos,last_endppqpos,chan,pitch,vel= reaper.MIDI_GetNote(take,noteCount-1)
            for abii = noteCount-1,0,-1 do
                local _,selected,muted,startppqpos,endppqpos,chan,pitch,vel= reaper.MIDI_GetNote(take,abii)
                if  selected then
                    if  last_startppqpos and last_endppqpos then
                        local score_point = ((startppqpos >= last_startppqpos) and last_endppqpos) or last_startppqpos
                        reaper.MIDI_SetNote(take,abii,selected,muted,startppqpos,score_point,chan,pitch,vel,true)
                    end
                    last_startppqpos = startppqpos
                    last_endppqpos = endppqpos
                end
            end
            reaper.MIDI_Sort(take)
        end

        api.ueb(0,'Set notes end to next note start',-1)
    end

    reaper.defer(main) 
    
        
