    
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_Lyx_HOME")
    
    -----------------------------------LOAD SCREEN POSITION-------------------------------------------------
    
    local function LoadCopyState()

            local copy_chart={"Track","Item","Razor area","Envelope","Track's FX Chain","Focus FX Data"}
            local state = reaper.GetExtState("Copy state","Copy state",false)
            
            return (state=="0" and "Cut" ) or copy_chart[tonumber(state)]
    end
    
    --------------
    local function FindVisEnv(env)
        
        local ENV,Env_name,Env_tr,env_n,_
        
        ENV={}
        
        if not env then return ENV end

        _,Env_name=reaper.GetEnvelopeName(env)
        Env_tr=reaper.GetEnvelopeInfo_Value(env,"P_TRACK")
        env_n=reaper.CountTrackEnvelopes(Env_tr)
        
        for sun=1,env_n do
            local env,name,no_vis_env
            env=reaper.GetTrackEnvelope(Env_tr,sun-1)
            _,name=reaper.GetEnvelopeName(env)
            if  name==Env_name then
                ENV[#ENV+1]=env
                for suni=sun,env_n-1 do
                    local env=reaper.GetTrackEnvelope(Env_tr,suni)
                    if  reaper.GetEnvelopeInfo_Value(env,"I_TCPH_USED")>0 then
                        ENV[#ENV+1]=env
                    else
                        no_vis_env=true
                        break
                    end
                end
            end
            if no_vis_env then break end
        end

        return ENV
    end

    local function PastePoint(ENV,DATA,cursor,point_offset)
        
        if  #ENV>0 then
            for sun=1,#DATA do
                for suni=1,#DATA[sun]-2 do
                    local point_time,value,shapeOut,tension,values,free_env,armed,defaultShape,faderScaling
                    values={}
                    for data in DATA[sun][suni]:gmatch("(.-)|") do
                        values[#values+1]=tonumber(data)
                    end
                    point_time=values[1]+cursor-point_offset
                    value=values[2]
                    shapeOut=values[3]
                    tension=values[4]
                    if sun>#ENV then return end
                    reaper.InsertEnvelopePoint(ENV[sun],point_time,value,shapeOut,tension,false,true)
                    reaper.Envelope_SortPoints(ENV[sun])
                    free_env=reaper.BR_EnvAlloc(ENV[sun],false)
                    _,_,armed,_,_,defaultShape,_,_,_,_,faderScaling=reaper.BR_EnvGetProperties(free_env)
                    reaper.BR_EnvSetProperties(free_env,true,true,armed,true,128,defaultShape,faderScaling)
                    reaper.BR_EnvFree(free_env,true)
                end
            end
        end
    end
    --------------
    local function PasteEnvelope()
        
        local DATA,ENV,Env,_,Env_name,Env_tr,trackz,pasted_item

        pasted_item="nothing..."

        DATA=reaper.GetExtState("EnvCopyBuff","EnvCopyBuff",false)
        
        if not DATA then return pasted_item end
        
        DATA=unserialize(DATA)
        
        --if true then return end
        --local withItem = DATA.withItem
        --table.remove(DATA)

        trackz=r.SaveTracks()
        reaper.BR_GetMouseCursorContext()
        Env=reaper.GetSelectedEnvelope(0) or reaper.BR_GetMouseCursorContext_Envelope() 
        ENV=FindVisEnv(Env)

        
        if  DATA.type=="Line" then
            for sun=1,#trackz do
                local pasted,tr,env,env_n,free_env,visble,armed,inLane,LaneHeight,defaultShape,faderScaling
                tr=trackz[sun]
                env_n=reaper.CountTrackEnvelopes(tr)
                for suni=1,env_n do
                    env=reaper.GetTrackEnvelope(tr,suni-1)
                    local _,name=reaper.GetEnvelopeName(env)
                    if  name==DATA[#DATA-1] then
                        reaper.SetEnvelopeStateChunk(env,DATA[1],true)
                        pasted=true
                        break
                    end
                end
                if  not pasted then
                    reaper.SetOnlyTrackSelected(tr)
                    if     DATA[#DATA-1] == "Volume" then reaper.Main_OnCommand(40406, 0) -- show track volume envelope
                    elseif DATA[#DATA-1] == "Pan" then reaper.Main_OnCommand(40407, 0)    -- show track pan envelope
                    elseif DATA[#DATA-1] == "Mute" then reaper.Main_OnCommand(40867, 0)   -- show track mute envelope
                    elseif DATA[#DATA-1] == "Volume (Pre-FX)" then reaper.Main_OnCommand(40408, 0) -- show track pre-FX volume envelope
                    elseif DATA[#DATA-1] == "Pan (Pre-FX)" then reaper.Main_OnCommand(40051, 0) -- show track pre-FX pan envelope
                    end
                    env=reaper.GetTrackEnvelopeByName(tr,DATA[#DATA-1])
                    reaper.SetEnvelopeStateChunk(env,DATA[1],true)
                end
                reaper.Envelope_SortPoints(env)
                free_env=reaper.BR_EnvAlloc(env,false)
                _,visble,armed,inLane,LaneHeight,defaultShape,_,_,_,_,faderScaling=reaper.BR_EnvGetProperties(free_env)
                reaper.BR_EnvSetProperties(free_env,visble,true,armed,inLane,LaneHeight,defaultShape,faderScaling)
                reaper.BR_EnvFree(free_env,true)
            end
            pasted_item="Line"
        -- elseif DATA[1].type and DATA[1].type == "Point" then
        --     local point_offset=tonumber(DATA[1][#DATA[1]-1])
        --     local cursor=reaper.GetCursorPosition()
        --     if  #ENV>0 then
        --         PastePoint(ENV,DATA,cursor,point_offset)
        --     else
        --         for sun=1,#trackz do
        --             local env=reaper.GetTrackEnvelope(trackz[sun],0)
        --             local ENV=FindVisEnv(env)
        --             PastePoint(ENV,DATA,cursor,point_offset)
        --         end
        --     end
        --     pasted_item="Points"
        end

        r.RestoreTracks(trackz)
        reaper.UpdateArrange()
        return "Envelope "..pasted_item,withItem
    end
    
    -----
    function main()
        
        local _,state,cmd
        
        state = LoadCopyState()
        
        if  state == "Cut" then
            
            cmd=reaper.NamedCommandLookup("_SWS_AWPASTE")
            reaper.Main_OnCommand(42398,0)--paste
            
        elseif state == "Track" then 

            cmd=42398--reaper.NamedCommandLookup("_S&M_PASTSNDRCV1")
            reaper.Main_OnCommand(cmd,0)--paste tracks

        elseif state == "Item" then
            
            reaper.Main_OnCommand(42398,0)--paste items
        
        elseif state == "Razor area" then

          local withItem

          --state,withItem = PasteEnvelope()

          --if  withItem then 
              reaper.Main_OnCommand(42398,0)--paste items
          --end
          
          --reaper.Main_OnCommand(42406,0)--clear razor area
        
        elseif state == "Envelope" then

            state=PasteEnvelope()
        
        elseif state == "Track's FX Chain" then
        
            cmd=reaper.NamedCommandLookup("_S&M_COPYFXCHAIN10")
            reaper.Main_OnCommand(cmd,0)--paste focus track FX chain
        
        elseif state == "Focus FX Data" then
            cmd=reaper.NamedCommandLookup("_RS1f29d66447fd557d9c3925eaa73930556904a5ef")
            reaper.Main_OnCommand(cmd,0)--paste focus FX data
        
        end  
        
        r.billboard("Paste "..(state or "nothing").."  ˊ＿>ˋ")

    end

    reaper.Undo_BeginBlock2(0)
    main()
    reaper.Undo_EndBlock2(0,"paste item/track/envelope/FX",-1)
