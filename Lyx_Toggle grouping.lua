
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_lib._Lyx_HOME")

    local function main()

        _,_,section,command  = reaper.get_action_context() 
        win, seg, det = api.mcw()

        target = (win == 'tcp' and 'track') or 'item'
        group_command = (target == 'track' and 40771) or 1156

        state = (reaper.GetToggleCommandState(group_command) == 0 and 'Enable') or 'Disable'
        
        if target == 'item' and state == 'Enable' then api.cmd(40034,0) end--select items in group
        
        api.cmd(group_command, 0)
        reaper.RefreshToolbar2(section,command)
        reaper.SetToggleCommandState(section,command, (state == 'Enable' and 1) or 0)

        BBB('Set '.. target .. ' group state to '..state)
    end
    
    reaper.defer(main)

