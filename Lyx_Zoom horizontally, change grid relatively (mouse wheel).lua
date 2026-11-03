
    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")
    
    ---CUSTOM----
        
        ---zoom speed---
        zoom_adjust = 0.4
        reverse = false
        reverse = (reverse and -1) or 1
        
    function main()
    
        _,_,_,_,_,_,mouse_scroll  = reaper.get_action_context() 
        
        mouse_scroll = mouse_scroll * reverse
        
        --api.cmd(api.name('_WOL_SETHZOOMC_MOUSECUR'),0)
        
        if  mouse_scroll > 0 then 
            reaper.adjustZoom( -zoom_adjust,
                             0,--forceset, 
                             true,--doupd, 
                             -1)--centermode )
        else
            reaper.adjustZoom( zoom_adjust,
                             0,--forceset, 
                             true,--doupd, 
                             -1)--centermode )    
        end
        
        api.ua()
        
        r.AdjustGrid()
        
        --api.cmd(api.name('_WOL_SETHZOOMC_EDITCUR'),0)
        
    end
    
    reaper.defer(main)

