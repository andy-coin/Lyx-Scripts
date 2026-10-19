    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    
    ------------------------------------------SET RAZOR-----------------------------------------------
    local function ClearTimeLoop()
        api.cmd(Save_time,0)
        reaper.GetSet_LoopTimeRange2(0, true, false, 0, 0, false) 
        if  1 == reaper.GetToggleCommandState(1068) then
            api.cmd(1068,0)
        end
    end
        
    ----------------------------------------------MAIN-----------------------------------------------
    local function main()
        
        local S,E,razor,starttime,endtime,it_n
        
        razor = r.GetRazorEdits(false,true)
        
        starttime, endtime = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
        
        it_n=reaper.CountSelectedMediaItems(0)
        
        if  it_n>0 then
            S,E = r.GetProjectLength(it_n>0)
        end
        
        if  starttime == endtime then -- no time selection
            
            if  razor then
                api.cmd(42474,0)--set loop point to razor point
            else
                api.cmd(Restore_time,0)
                local starttime, endtime = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
                if  starttime==endtime then
                    if  not S or not E then return end
                    reaper.GetSet_LoopTimeRange2(0,true,false,S,E,false)
                end
            end
            if  0 == reaper.GetToggleCommandState(1068) then
                api.cmd(1068,0)
            end

        else                          -- there is time selection
            if  0 == reaper.GetToggleCommandState(1068) then
                api.cmd(1068,0)
                api.cmd(Save_time,0)
            else
                if  S and E and (S~=starttime or E~=endtime) then
                    reaper.GetSet_LoopTimeRange2(0,true,false,S,E,false)
                    api.cmd(Save_time,0)
                else
                    api.cmd(Save_time,0)
                    ClearTimeLoop()
                end
            end
        end
    end
    
    Save_time=api.name("_SWS_SAVELOOP5")
    Restore_time=api.name("_SWS_RESTLOOP5")
    
    --reaper.defer(main)
    
    
    api.cmd(1068,0)
    
