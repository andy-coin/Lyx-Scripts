    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_lib._Lyx_HOME")
    

    local function CopyRazorEnvelopePoints(razorMap)

        local DATA,with_item

        DATA={}

        for abi=1,#razorMap do
            
            local razorData,Copy_points
            
            Copy_points={}

            razorData=razorMap[abi]

            if  razorData.isEnvelope then

                local points=razorData.envelopePoints

                for abii=1,#points do
                    Copy_points[abii]=
                        points[abii].time.."|"..points[abii].value.."|"
                        ..points[abii].shape.."|"..points[abii].tension.."|"
                end

                Copy_points[#Copy_points+1]=razorData.areaStart
                DATA[#DATA+1]=Copy_points
            else
                with_item = true
            end
        end
        
        DATA.with_item = tostring(with_item)
        DATA=serialize(DATA)

        reaper.SetExtState("EnvCopyBuff","EnvCopyBuff",DATA,false)
        
        return with_item

    end

    --------------
    local function CopyEnvelope(Start,End)
        
        reaper.BR_GetMouseCursorContext()
        local Env=reaper.GetSelectedEnvelope(0) or reaper.BR_GetMouseCursorContext_Envelope()

        local reaper_env={"Volume","Pan","Mute","Volume (Pre-FX)","Pan (Pre-FX)"}

        if not Env then return end

        local Copy_points,DATA,WantSelect
        DATA={} 
        WantSelect=true
        local points=r.GetEnvelopePointsInRange(Env,Start,End,WantSelect)

        if  #points>0 then
            for abi=1,#points do
                DATA[#DATA+1]=
                            points[abi].time.."|"..points[abi].value.."|"
                            ..points[abi].shape.."|"..points[abi].tension.."|"
                    
            end
            DATA.start = points[1].time
            DATA.type  = "Point"
            DATA=serialize(DATA)
        else
            local _,chunk=reaper.GetEnvelopeStateChunk(Env,"", false)
            local _,name=reaper.GetEnvelopeName(Env)
            DATA={chunk,name,type="Line"}
            DATA=serialize(DATA)
        end

        reaper.SetExtState("EnvCopyBuff","EnvCopyBuff",DATA,false)
        
        return (#points>0 and " Points") or " Line"
    end

    --------------
    local function main()
    
        local tr_n,it_n,FX,_,razor,razorMap,win,cmd,state,copy_chart,env_detail
        
        tr_n=reaper.CountSelectedTracks(0)
        it_n=reaper.CountSelectedMediaItems(0)
        FX,trackidx,itemidx,takeidx,fxidx,parm = reaper.GetTouchedOrFocusedFX(1)
        razor,razorMap=r.GetRazorEdits(false,false)
        copy_chart={"Copy Track","Copy Item","Copy Razor area","Copy Envelope","Copy Track's FX Chain","Copy Focus FX Data"}
        win=reaper.BR_GetMouseCursorContext()
        
        if  FX and parm ~= 1 then  
            cmd=r.ScriptID("Lyx Scripts/Lyx_Copy focus FX state.lua")
            reaper.Main_OnCommand(cmd,0) --copy focus FX data
            state=6
            
        elseif razor then

            local not_all_envelope
            
            not_all_envelope = CopyRazorEnvelopePoints(razorMap)
            
            if  not_all_envelope then
                api.cmd(40060,0)--Item: Copy selected area of items 
                reaper.Main_OnCommand(42406,0)--clear razor area
            end

            state = 3
            
        elseif reaper.GetSelectedEnvelope(0) then
            env_detail=CopyEnvelope()
            state=4
            
        elseif (win~="tcp" and it_n>=tr_n and it_n>1) or (win=="arrange" and it_n>=tr_n) then
            reaper.Main_OnCommand(40698,0) --copy items
            state=2
            
        elseif tr_n==1 and win =='mcp' then 
            cmd=reaper.NamedCommandLookup("_S&M_COPYFXCHAIN5")
            reaper.Main_OnCommand(cmd,0) --copy focus track FX chain
            state=5
            
        else 
            cmd=40210--reaper.NamedCommandLookup("_S&M_COPYSNDRCV1")
            reaper.Main_OnCommand(cmd,0) --copy tracks
            state=1
            
        end  
        
        local target=(state~=4 and copy_chart[state]) or copy_chart[state]..env_detail
        r.billboard(target.."  ˊ＿>ˋ")
        
        reaper.SetExtState("Copy State","Copy state",state,false)
        reaper.UpdateArrange()
    end

    reaper.defer(main)
