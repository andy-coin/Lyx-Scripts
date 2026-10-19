
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")

    local function main()   
        
        editor = reaper.MIDIEditor_GetActive()
        if not editor then return end

        reaper.MIDIEditor_OnCommand(editor,40180)--Edit: Move notes down one octave
        r.NotesMonitor(editor)
        
    end

    main()
