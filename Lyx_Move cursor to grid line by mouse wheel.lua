
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
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
            cmd = (wheel > 0 and r.ScriptID("ReaTeam Scripts/Cursor/amagalma_Move edit cursor to previous visible grid line.lua")) or r.ScriptID("ReaTeam Scripts/Cursor/amagalma_Move edit cursor to next visible grid line.lua")
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

    