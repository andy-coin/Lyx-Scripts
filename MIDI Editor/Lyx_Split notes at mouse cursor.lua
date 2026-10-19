    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")

    function SplitNotes()

        local midieditor, take, notes, len, len_div--, notes

        midieditor = reaper.MIDIEditor_GetActive()
        if midieditor == nil then return end

        take = reaper.MIDIEditor_GetTake(midieditor)
        if take == nil then return end

        local notes = {}
        
        api.mcw()
        mouse_cursor = reaper.MIDI_GetPPQPosFromProjTime(take, api.mcp())

        for abi = 1, reaper.MIDI_CountEvts(take)  do
            local _, sel, muted, start, ending, chan, pitch, vel = reaper.MIDI_GetNote(take, abi-1)
            if sel then
                if  start <= mouse_cursor and mouse_cursor <= ending then 
                    reaper.MIDI_SetNote(take, abi-1 , false, muted, start, mouse_cursor, chan, pitch, vel, true)
                    notes[#notes+1] = {mute = muted, start = start, ending = ending, chan = chan, pitch = pitch, vel = vel}
                else
                    reaper.MIDI_SetNote(take, abi-1 , false)
                end
            end
        end
            
        for abi = 1, #notes do
            note = notes[abi]
            reaper.MIDI_InsertNote(take, true, note.mute, mouse_cursor, note.ending, note.chan, note.pitch, note.vel, true)
        end

        reaper.MIDI_Sort(take)   
            
    end
    
    script_title = "Split selected notes at mouse cursor"
    
    reaper.Undo_BeginBlock()  
    SplitNotes()
    reaper.Undo_EndBlock(script_title, 0)