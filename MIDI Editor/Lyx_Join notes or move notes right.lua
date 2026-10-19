    
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
            api.Mcmd(editor,40184)--move note right
        else
            api.Mcmd(editor,40456)--move note up
        end
        
    end

    reaper.defer(main) 
    
        