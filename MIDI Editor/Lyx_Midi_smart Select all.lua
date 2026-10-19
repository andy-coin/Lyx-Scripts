    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")

    local function main()

        local E = api.M()
        take = api.Mgt(E)
        r.SaveItems(true)
        
        if not E or not take then return end
        
        local s, e = r.GetSetTime()
        
        if s ~= e then 
          api.Mcmd(E,40746) --select all notes in time selection
          api.Mcmd(E,40751) --select all cc events in time selection
          return 
        end
        
        --api.cmd(40289,0)
        --local item = api.gtki(take)
        
        --L_edge = api.giv(item,"D_POSITION")
        --R_edge = L_edge + api.giv(item,"D_LENGTH")
        
        --api.sis(item,true)
        local L_edge,R_edge = r.GetProjectLength(true)
        r.GetSetTime(false,L_edge,R_edge)
        api.Mcmd(E,40876)
        
        r.GetSetTime(false,s,e)
        --r.RestoreItems(true)
        --local command = (r.GetSetTime(true) and 40876) or 40006

    end

    main()
