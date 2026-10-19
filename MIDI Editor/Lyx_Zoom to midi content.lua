    
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_Lyx_HOME")
    
    local function main()

        local itemz,editor,midi_takes,HIGH,LOW,high,low,center,has_select,range,ZoomChart
        
        editor = reaper.MIDIEditor_GetActive()
        if not editor then return end

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

        HIGH = 0
        LOW  = 128
        high = 0
        low  = 128

        for abi = 1,#midi_takes do
            local take = midi_takes[abi]
            local _, noteCount = reaper.MIDI_CountEvts(take) 
            for abii = 1, noteCount do
                local _,selected,_,_,_,_,pitch= reaper.MIDI_GetNote(take,abii-1)
                HIGH = (pitch > HIGH and pitch) or HIGH
                LOW  = (pitch < LOW  and pitch) or LOW
                if  selected then
                    has_select  = true
                    high = (pitch > high and pitch) or high
                    low  = (pitch < low  and pitch) or low
                end
            end
        end

        for abi=1,60 do
            reaper.MIDIEditor_OnCommand(editor,40112)
        end

        high = (has_select and high) or HIGH
        low  = (has_select and low) or LOW

        center = math.floor((high+low)/2)
        range  = high - low + 10
        reaper.MIDIEditor_SetSetting_int(editor,'active_note_row',center)
        
        if  not has_select then
            for abi=1,#midi_takes do
                reaper.MIDI_SelectAll(midi_takes[abi],true)
            end
        end

        --vertically fit
        ZoomChart={112,94,80,70,63,56,51,47,43,40,37,35,33,31,29,28,26,25,24,23,22,21,20,19,18,0}
        for abi=2,#ZoomChart do
            if  range > ZoomChart[abi] then
                local times=math.min(abi-1,17)
                for abii=1,times do
                    reaper.MIDIEditor_OnCommand(editor,40111)
                end
                break
            end
        end

        --horizontal fit
        reaper.MIDIEditor_OnCommand(editor,40725)--zoom to selected note
        api.cmd(api.name("_WOL_SETHZOOMC_EDITCUR"),0)--zoom center to edit cursor
        for abi=1,3 do
            reaper.MIDIEditor_OnCommand(editor,1011)
        end
        api.cmd(api.name("_WOL_SETHZOOMC_MOUSECUR"),0)--zoom center to mouse cursor
        
        --unselect all notes
        reaper.MIDIEditor_OnCommand(editor,40214)
        -- for abi=1,#midi_takes do
        --     reaper.MIDI_SelectAll(midi_takes[abi],false)
        -- end

        api.ueb(0,"Toggle zoom to selected notes",-1)
    end

    reaper.defer(main) 
    
        
