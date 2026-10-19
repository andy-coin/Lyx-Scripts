
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r = require("_Lyx_HOME")
    
    ---CUSTOM---
    zoom_adjust = 2
    reverse = false
    reverse = (reverse and -1) or 1
    
    -------------------------------------------------------------------- 
    local function main()
        
        _,_,_,_,_,_,wheel  = reaper.get_action_context() 
        
        wheel = wheel * reverse
        
        if  r.IsMidiEditorFocus() then
            cmd = ( wheel > 0 and 40047) or 40048
            CMD = function() api.Mcmd(api.M(), cmd) end
        else
            cmd = (wheel > 0 and api.name('_RS2a2550d39129b310256c72ba74993b7f92f8e235')) or api.name('_RS15fe264880bb8d5030dabb8c1b1d6767a4c36b28')
            CMD = function() api.cmd(cmd, 0) end
        end
        
        script_name = 'Move cursor to grid line by mouse wheel'
        
        local abi = api.load(script_name, 'times')
        
        abi = tonumber(abi) or 0
        
        if abi % zoom_adjust == 0 then
            CMD()
        end

        api.save(script_name, 'times', (abi%zoom_adjust)+1, false)
                
    end
    
    main()

    reaper.defer(function()end)

    