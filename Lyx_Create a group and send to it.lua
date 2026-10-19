    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_lib._Lyx_HOME")
    
    ---CUSTOM---
    follow_color = false
    new_color = false
    
    ---------------------------------------------------------------------------------------------------------------------
    local function promt(tr_name)
        
        local bool,name = r.GetUserInputs("Make Folder",1,"Folder Name ?",tr_name)
        
        if not bool then return end

        return name or ''
    end
    
    -------------------------------------------------------------------------------
    local function main() 
        
        if  api.cst(0)<2 then return end
        
        local _,first_tr,tr_name,name,first_color,bus,bus_color
        
        first_tr  = api.gst(0, 0)
        
        _,tr_name = api.ts(first_tr,'P_NAME','',false)
        first_color = reaper.GetTrackColor(first_tr)
        name = promt(tr_name)
        
        if not name then return end
        
        api.ubb()
        api.pur(1)
        
        r.SaveTracks(true)

        local idx = api.gtv(first_tr, "IP_TRACKNUMBER") - 1
        reaper.InsertTrackAtIndex(idx,true)
        
        bus = api.gt(0,idx)

        r.RestoreTracks(true)
        
        reaper.ReorderSelectedTracks(idx+1,1)
        
        api.ts(bus,"P_NAME",name, true )
        
        if follow_color and first_color ~= 0 then
            for abi = 2 , api.cst(0) do
                local tr = api.gst(0,abi-1)
                api.stv(tr,'I_CUSTOMCOLOR',first_color)
            end
            api.stv(bus,'I_CUSTOMCOLOR',first_color)
        elseif new_color then
            api.cmd(r.ScriptID("Lyx Scripts/Lyx_Set random color .lua"),0)--set random color
        end
        
        api.pur(-1)
        
        r.SameTCPH(bus,first_tr)
        
        api.ua()

        api.sot(bus)
        api.cmd(40913,0)--vertical scroll track
        api.ueb(0,"Create bus for selected tracks and reroute them", 0)
        
    end    

    r.run(main)


    
