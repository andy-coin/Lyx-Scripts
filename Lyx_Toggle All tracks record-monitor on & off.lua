    
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    
    local function main()
        
        trackzzz=r.SaveTracks()
        
        cmd=reaper.NamedCommandLookup("_SWS_SELRECARM")
        reaper.Main_OnCommand(cmd,0)--select arm tracks
        
        tr_n=api.cst(0)
        
        if  tr_n==0 then 
            r.RestoreTracks(trackzzz)
            return 
        end
        
        for abi=1,tr_n do
            tr=api.gst(0,abi-1)
            mon=api.gtv(tr,"I_RECMON")
            if mon==0 then ON=1 break end 
        end
        
        for abi=1,tr_n do
            tr=api.gst(0,abi-1)
            if  api.gtv(tr,"I_RECINPUT")~=1040 then
                api.stv(tr,"I_RECMON",ON or 0)
            end
        end
        
        r.RestoreTracks(trackzzz)
          
        state=(ON and "On") or "Off"
        r.billboard("Set rec-armed tracks monitor : "..state)
        
    end
    
    main()
