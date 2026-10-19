  
    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")
    
    --------------
    local function main()
        
        r.SelTrackFilter()
        
        if api.cst(0) == 0 then return end

        reaper.Undo_BeginBlock()
        
        pan_data = {}
        for abi=1,api.cst(0) do
            local tr = api.gst(0,abi-1)
            api.stv(tr,'D_VOL',1)
        end
        
        r.billboard('Set track(s) volume to 0 dB')

        reaper.Undo_EndBlock('Set track(s) volume to 0 dB',-1)
        
    end
    
    reaper.defer(main)
