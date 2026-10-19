    
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    

    local function F(n)

        if type(n) ~= 'number' then return end

        return math.floor(n*10000)

    end

    ----------------------------------------------MAIN-----------------------------------------------
    local function main()
    
        local razor,razorMap,clear,starttime,endtime,it_n,min,max
        
        clear=false
        
        loop = reaper.GetToggleCommandState(1068) == 1
        
        razor,razorMap=r.GetRazorEdits(clear)
        
        starttime, endtime = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)

        it_n = api.csi(0)

        if  it_n ==0 then
            for i = reaper.CountProjectMarkers(0), 0, -1 do
                retval, is_region, pos, region_end, name, index = reaper.EnumProjectMarkers2(0,i)
                if  name == "=START" then
                    min = pos
                elseif name == "=END" then
                    max = pos
                end
                if  min and max then break end
            end
            if not min or not max then
                min,max=r.GetProjectLength(false)
            end
        else
            min,max=r.GetProjectLength(true)
        end

        local save_time=reaper.NamedCommandLookup("_SWS_SAVELOOP5")
        
        --[[if  starttime ~= endtime and loop then
            api.cmd(1068,0)
        else--]]
        if  starttime == endtime then
            if  razor then
                reaper.GetSet_LoopTimeRange2(0, true, false,razorMap.min,razorMap.max,false)
            else
                reaper.GetSet_LoopTimeRange2(0, true, false, min,max, false)
            end
            reaper.Main_OnCommand(save_time,0)
        else
            if  razor then
                if  razorMap.min~=starttime or razorMap.max~=endtime then
                    reaper.GetSet_LoopTimeRange2(0,true,false,razorMap.min,razorMap.max,false)
                    api.cmd(save_time,0)
                else
                    reaper.GetSet_LoopTimeRange2(0,true,false,0,0,false) 
                end
            elseif  F(starttime) ~= F(min) or F(endtime) ~= F(max) then
                reaper.GetSet_LoopTimeRange2(0,true,false,min,max,false)
                reaper.Main_OnCommand(save_time,0)
            else
                reaper.GetSet_LoopTimeRange2(0,true,false,0,0,false)
            end
        end
        
        --if  loop then api.cmd(1068,0) end
        
    end
    
    reaper.defer(main)
    
    
    
    
