
local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
script_path=script_path:gsub("/MIDI Editor","")
package.path = package.path..";"..script_path.."?.lua"
local r=require("_Lyx_HOME")


local function main()
    
    local editor,notes,NOTES,time,timeout,tk,tk_idx,note,_,PITCH
    
    timeout = 3
    editor = reaper.MIDIEditor_GetActive()
    if not editor then return end

    reaper.MIDIEditor_OnCommand(editor,40178)--Edit: Move notes up one semitone
    
    notes = {'C','C#','D','Eb','E','F','F#','G','Ab','A','Bb','B'}
    PITCH = {}
    NOTES = ''
     
    time = api.now()
    tk_idx = 0

    while (api.now() - time < timeout) do 
        
        tk = reaper.MIDIEditor_EnumTakes(editor, tk_idx, true)
        if not tk then break end

        note = reaper.MIDI_EnumSelNotes(tk, -1)
        if note == -1 then goto NEXT end

        while( note ~= -1 and (api.now() - time < timeout)) do
            
            local retval, selected, muted, startppqpos, endppqpos, chan, pitch, vel = reaper.MIDI_GetNote(tk,note)
        
            if  selected then
                PITCH[#PITCH+1] = pitch
            end
            
            note = reaper.MIDI_EnumSelNotes(tk, note)
        end
        
        ::NEXT::
        
        tk_idx = tk_idx +1
    end     

    _,PITCH = r.KillTable(PITCH)

    for abi=1, #PITCH do
        NOTES = NOTES .. tostring(notes[PITCH[abi]%12+1]) .. tostring(math.floor(PITCH[abi]/12)-2) .. " | "
    end

    if  NOTES ~= '' then
        reaper.MIDIEditor_SetSetting_int(editor,'active_note_row',PITCH[#PITCH])
    else
        local pitch = reaper.MIDIEditor_GetSetting_int(editor,'active_note_row')
        reaper.MIDIEditor_SetSetting_int(editor,'active_note_row',pitch-1)
    end
    
    NOTES = NOTES:sub(1,-4)

    if  NOTES ~= '' then
        r.billboard(NOTES,0.8,editor)
    end

end

main()