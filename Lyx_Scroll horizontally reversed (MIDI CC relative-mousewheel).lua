
    local script_name = debug.getinfo(1).source
    local script_path = script_name:match("@?(.*[/\\])") or "./"
    --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")

    -----CUSTOM-----
    
    speed = 0.2
    
    reverse = false
    
    local function main()
        
        if reaper.GetToggleCommandState(40036)==1 then
            reaper.Main_OnCommand(40036,0)
        end
        
        _,_,_,_,_,_,mouse_wheel  = reaper.get_action_context() 
        
        mouse_wheel = (reverse and -mouse_wheel) or mouse_wheel
            
        times=math.floor(math.abs(mouse_wheel*speed)) -- round toward 0, same feel both directions
        
        if mouse_wheel>0 then
            for abi=1,times do
                reaper.CSurf_OnScroll(-1,0)
            end
        else
            for abi=1,times do
                reaper.CSurf_OnScroll(1,0)
            end
        end
        
    end
    
    reaper.defer(main)
