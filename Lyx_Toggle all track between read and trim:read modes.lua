    
    r=reaper

    local function main()
        
        pro_name=reaper.GetProjectName()
        pro_name=(pro_name~="" and pro_name) or "Unsaved project"
        
        _,_,_,sectionID,cmdID=reaper.get_action_context()
        
        toggle=reaper.GetExtState("read/trim mode",pro_name)
        local cmd=(toggle~="1" and 40086) or 40088
        local state=(toggle~="1" and 1) or 0 
        reaper.SetExtState("read/trim mode",pro_name,state,false)
        reaper.Main_OnCommand(cmd,0)
        
    end

    main()
