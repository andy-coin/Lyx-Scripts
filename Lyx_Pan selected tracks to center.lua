  
    
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    --script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    
    --------------
    local function main()
        
        reaper.Undo_BeginBlock()

        r.SelTrackFilter()
        
        if api.cst(0) == 0 then return end
        
        pan_data = {}
        for abi=1,api.cst(0) do
            local tr = api.gst(0,abi-1)
            api.stv(tr,'D_PAN',0)
        end

        r.billboard('Set select track\'s pan to center')

        reaper.Undo_EndBlock("Set select track\'s pan to center",-1)
        
    end
    
    reaper.defer(main)
