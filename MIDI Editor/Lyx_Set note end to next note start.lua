    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_Lyx_HOME")
    
    local function main()

        local itemz,editor,midi_takes
        
        editor = reaper.MIDIEditor_GetActive()
        if not editor then return end
        
        local state = api.load('Midi_editor','move note state')
        
        if  state == '1' or state == 'ON' then
            r.RunScript(script_path.."MIDI Editor/Lyx_Move notes up one semitone.lua", 32060)--move note up
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
        
        -- collect selected notes of all takes in project time, so notes in different takes compare correctly
        local notes = {}
        for abi = 1,#midi_takes do
            local take = midi_takes[abi]
            local _, noteCount = reaper.MIDI_CountEvts(take)
            for abii = 0,noteCount-1 do
                local _,selected,_,startppqpos,endppqpos = reaper.MIDI_GetNote(take,abii)
                if  selected then
                    notes[#notes+1] = {take = take, idx = abii,
                        s = reaper.MIDI_GetProjTimeFromPPQPos(take,startppqpos),
                        e = reaper.MIDI_GetProjTimeFromPPQPos(take,endppqpos)}
                end
            end
        end
        if #notes < 2 then return end
        table.sort(notes,function(a,b) return a.s < b.s end)

        api.ubb()

        -- walk from the last note backwards; only note ends change, so indices stay valid (noSort, sorted once after)
        local last_s, last_e
        for k = #notes,1,-1 do
            local n = notes[k]
            if  last_s then
                local score_point = ((n.s >= last_s) and last_e) or last_s -- chord notes share the next note's end
                reaper.MIDI_SetNote(n.take,n.idx,nil,nil,nil,reaper.MIDI_GetPPQPosFromProjTime(n.take,score_point),nil,nil,nil,true)
                n.e = score_point
            end
            last_s, last_e = n.s, n.e
        end
        for abi = 1,#midi_takes do reaper.MIDI_Sort(midi_takes[abi]) end

        api.ueb(0,'Set notes end to next note start',-1)
    end

    reaper.defer(main) 
    
        
