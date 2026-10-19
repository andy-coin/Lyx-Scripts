    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_lib._Lyx_HOME")

    local editor = reaper.MIDIEditor_GetActive()

    if  editor then 
        L,B,R,T=r.GetWindowPosition(editor) 
        api.save("Item Editor","midi editor window position",L.."|"..B.."|"..R.."|"..T.."|",true)
        r.billboard("Midi editor position Saved ~",2,editor)
    end
    
    reaper.defer(function()end)
