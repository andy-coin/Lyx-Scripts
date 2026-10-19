
local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
package.path = package.path..";"..script_path.."?.lua"
local r=require("_lib._Lyx_HOME")


local function main()
    
    local editor,notes,NOTES,time,timeout,tk,tk_idx,note,_,VEL
    
    timeout = 3
    editor = reaper.MIDIEditor_GetActive()
    if not editor then return end

    reaper.MIDIEditor_OnCommand(editor,40462)--velocity + 1

    VEL = {}
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
        
            VEL[#VEL+1] = vel
            
            note = reaper.MIDI_EnumSelNotes(tk, note)
        end
        
        ::NEXT::
        
        tk_idx = tk_idx +1
    end     

    _,VEL = r.KillTable(VEL)

    for abi=1, #VEL do
        NOTES = NOTES .. tostring(VEL[abi]) .. ' | '
    end
    
    NOTES = NOTES:sub(1,-4)

    if  NOTES ~= '' then
        r.billboard(NOTES,0.8,editor)
    end

end

main()