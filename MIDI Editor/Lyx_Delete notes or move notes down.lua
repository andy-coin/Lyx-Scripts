    
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_Lyx_HOME")
    
    local function main()

        local editor
        
        editor = reaper.MIDIEditor_GetActive()
        if not editor then return end

        api.Mcmd(editor,40002)--move note up

        
    end

    reaper.defer(main) 
    
        
