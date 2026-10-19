
    local script_name = debug.getinfo(1).source
    local script_path = script_name:match("@?(.*[/\\])") or "./"
    --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    
    -- if there is any razor area, it will insert empty space at sertain track 
    -- otherwise it will insert empty space at edit cursor by time selection length affect whole project.

    local function MoveAllItems(tr,Start,End)

        local CountTrItem = api.cti(tr)

        for i = CountTrItem-1,0,-1 do
            local item = api.gti(tr,i)
            local pos = api.giv(item,"D_POSITION")
            if pos >=Start then
                api.siv(item, "D_POSITION", pos + (End - Start))
            else
                local right = reaper.SplitMediaItem(item, Start) -- right half (nil if item ends before Start)
                if  right then
                    api.siv(right, "D_POSITION", api.giv(right,"D_POSITION") + (End - Start))
                end
            end
        end
    end

    local function MoveAllEnvs(tr,Start,End)

        local CountTrEnv = api.cte(tr)

        for i = 1,CountTrEnv do
            
            local env = api.gte(tr,i-1)
            AIs = reaper.CountAutomationItems(env)
            
            if AIs > 0 then
                local e, time, idx = api.gec()
                api.sec(Start,false,false)
                time = api.now()
                idx = AIs - 1

                while idx >= 0 do 
                    local pos = reaper.GetSetAutomationItemInfo(env, idx , "D_POSITION", 0, false)
                    local len = reaper.GetSetAutomationItemInfo(env, idx , "D_LENGTH", 0, false)
                    if pos >= Start then
                        r.GetSetAIinfo(env, idx , nil, pos + (End - Start), nil, nil, nil, true)
                    elseif pos + len > Start then
                        reaper.GetSetAutomationItemInfo(env, idx, "D_UISEL", 1, true) 
                        api.cmd(42087,0)--Split automation items
                        api.cmd(42089,0)--glue automation it em
                        reaper.GetSetAutomationItemInfo(env, idx, "D_UISEL", 0, true) 
                        idx = idx + 2
                    end
                    idx = idx - 1
                    if (api.now() - time) > 0.1 then BBB('T_T') break end
                end

                api.sec(e,false,false)
            end

            local CountEnvPoint = api.cep(env,-1)

            for abi = CountEnvPoint-1,0,-1 do
                local retval, time, value, shape, tension, selected = api.gep(env, -1, abi)
                if  time >= Start then
                    reaper.SetEnvelopePoint(env, abi, time + (End - Start), valueIn, shape, tension, selected, true)
                end
            end

            reaper.Envelope_SortPoints(env)
        end

    end

    -----------------------------------------------------------------------------------

    local function main()

        razor,razorArea = r.GetRazorEdits()--return IsRazor,areaMap={areaStart,areaEnd,track,items,isEnvelope,envelope,envelopeName,envelopePoints,GUID}
        
        local starttime, endtime = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
        
        if not razor and (starttime == endtime) then return end

        api.ubb()

        if  razor then
            api.pur(1)
            r.SaveTracks(true)
            api.cmd(40289,0)--unselect all items
            for abi=1, #razorArea do
                
                local tr, Start, End
                tr = razorArea[abi].track
                Start = razorArea[abi].areaStart
                End = razorArea[abi].areaEnd
                
                api.sot(tr)
                
                MoveAllItems(tr,Start,End)
                MoveAllEnvs (tr,Start,End)
                
            end
            
            r.RestoreTracks(true)
            
            api.pur(-1)

            context = 'razor area'
            
        elseif starttime ~= endtime then
            
            local edit_curaor  = api.gec()
            
            api.cmd(r.ScriptID("ReaTeam Scripts/Time Selection/cfillion_Insert empty space from time selection at edit cursor (moving later items).lua"),0)--insert empty space at edit cursor
            
            reaper.GetSet_LoopTimeRange2(0, true, false, edit_curaor , edit_curaor + endtime - starttime, false)        
            
            context = 'time selection'

        end

        api.ueb(0,'Insert empty space by '..context,-1)

    end
    
    main()
