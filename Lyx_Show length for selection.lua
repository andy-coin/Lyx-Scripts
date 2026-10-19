
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_Lyx_HOME")

    local function main()

        razor,razorMap = r.GetRazorEdits()

        S0 = reaper.time_precise()
        Start, End = reaper.GetSet_LoopTimeRange2(0,false,false,0,0,false)
        win, seg, dtl=reaper.BR_GetMouseCursorContext()
        item_n = reaper.CountSelectedMediaItems(0)

        --if  not razor and Start==End and item_n==0 then return end

        local min, max 

        if  razor then
            Context="[ Razor Edits Length ] "
            min = razorMap.min
            max = razorMap.max
        elseif Start ~= End and (dtl~="item" and item ~="item_stretch marker" or item_n==0) then
            Context="[ Time selection Length ] "
            min = Start
            max = End
        else--if dtl=="item" or dtl=="item_stretch_marker" then
            if  item_n>0 then
                Context="[ "..tostring(item_n).." items Length ] "
                min, max=r.GetProjectLength(true)
            else
                Context="[ Project Length ] "
                for i = reaper.CountProjectMarkers(0), 0, -1 do
                    retval, is_region, pos, region_end, name, index = reaper.EnumProjectMarkers2(0,i)
                    if  name == "=START" then
                        min = pos
                    elseif name == "=END" then
                        max = pos
                    end
                    if  min and max then break end
                end
                if  not min or not max then
                    min, max = r.GetProjectLength(false)
                end
            end
        end
        
        
        --caculate second
        length = max - min

        local TIME, d,h,m,s,ms

        d  = math.floor(length / 86400)
        length=length-d*86400

        h  = math.floor(length / 3600)
        length=length-h*3600

        m  = math.floor(length /  60)
        length=length-m*60

        s  = math.floor(length % 60)

        ms = math.floor((length % 1)*1000)

        d =(d==0 and "" )   or d..":" 
        h =(h==0 and "" )   or string.format("%02d:",h)
        m =(m==0 and "0:" ) or string.format("%02d:",m)
        s =(s==0 and "0" )  or string.format("%02d",s)
        ms=(ms==0 and "" )  or string.format(".%03d",ms)

        TIME = d..h..m..s..ms

        --caculate beats
        local BEATS, _, min_measure, max_measure, max_cml, max_beats, max_dom, qn_start, max_qn_start, min_qn, max_qn

        _, min_measure, min_cml, min_beats, min_dom = reaper.TimeMap2_timeToBeats(0, min)
        _, max_measure, max_cml, max_beats, max_dom = reaper.TimeMap2_timeToBeats(0, max)
        
        _, min_qn_start = reaper.TimeMap_GetMeasureInfo(0, min_measure) 
        _, max_qn_start = reaper.TimeMap_GetMeasureInfo(0, max_measure) 
        
        min_qn = reaper.TimeMap_timeToQN(min)
        max_qn = reaper.TimeMap_timeToQN(max)

        local M = max_measure - min_measure - ((min_qn ~= min_qn_start) and 1 or 0)
        local B = (max_qn-max_qn_start)/(4/max_dom)

        if  M  >= 1 then
            BEATS = tostring(M)
            if (min_qn ~= min_qn_start) then
                B = B + (min_qn_start - min_qn + min_cml)
            end
            if  B ~= 0 then
                BEATS = BEATS .. ' M ' .. r.DIGI(B, 0, false, true) .. ((B%1 ~= 0) and ' B*' or ' B')
            else
                BEATS = BEATS .. ' Measures'
            end
        elseif max_qn-min_qn > 0 then
            BEATS = r.DIGI(max_qn-min_qn, 0, false, true) .. (((max_qn-min_qn)%1 ~= 0) and ' Beats*' or ' Beats')
        end

        local space = ""

        for abi = 1, #Context do
            space = space .. "\t"
        end 

        TIME  = (TIME  and '\n time\t\t: ' .. TIME)  or ''
        BEATS = (BEATS and '\n beats\t: '  .. BEATS) or ''

        r.billboard(Context..TIME..BEATS, 2)

    end

    main()

    reaper.defer(function() end)
