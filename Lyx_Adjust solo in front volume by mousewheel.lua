
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")  
    
    -----CUSTOM-----
    local dB10 = 3 -- dB value x 10. step size. 35 = 3.5dB, etc. use integers only.
    local Hi_Limit = -10 -- wont go above this. dB value x 10. 35 = 3.5dB, etc. use integers only.
    local Lo_Limit = -300 -- wont go below this. dB value x 10. 35 = 3.5dB, etc. use integer only.
    
    reverse = false
    
    reverse = (reverse and -1) or 1
    
    -- Get current solodimdb10 value
    local x = reaper.SNM_GetIntConfigVar("solodimdb10", 666)

    -- Get action context
    local _, _, _, mode, _, _, wheel = reaper.get_action_context()
  
    wheel = wheel * reverse
    
    if  wheel > 0 then
        -- Increase value
        local y = dB10 + x
        if  api.gtc(40745) == 0 then
            api.cmd(40745,0)
        end
        reaper.SNM_SetIntConfigVar("solodimdb10", math.min(y, Hi_Limit))
    else
        -- Decrease value
        local y = -dB10 + x
        if  api.gtc(40745) == 1 and y <= Lo_Limit then
            api.cmd(40745,0) -- turn off solo in front
        end

        reaper.SNM_SetIntConfigVar("solodimdb10", math.max(y, Lo_Limit))
    end

    -- Defer NoUndo
    reaper.defer(function() end)
