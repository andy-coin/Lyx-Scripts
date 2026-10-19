    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")
    
    --------------
    local function main()
        
        local win, seg, det = api.mcw()
    
        --msg(win..'|'..seg..'|'..det)
        
        api.save("Copy State","Copy state",0,false)
        
        if  win == 'arrange' and seg == 'track' and det == 'empty' and api.csi(0) == 0 then 
            api.cmd(40337,0)--cut tracks 
        else
            reaper.Main_OnCommand(40059,0)
        end
        
    end
    
    reaper.defer(main)
