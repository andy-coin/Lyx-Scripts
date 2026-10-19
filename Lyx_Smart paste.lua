    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
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

    -- GROUPS[n] = list of "time|value|shape|tension|" strings, pasted into ENV[n]
    local function PastePoint(ENV,GROUPS,cursor,point_offset)

        for sun=1,math.min(#GROUPS,#ENV) do
            local env=ENV[sun]
            for _,str in ipairs(GROUPS[sun]) do
                if  type(str)=="string" and str:find("|") then
                    local values={}
                    for data in str:gmatch("(.-)|") do
                        values[#values+1]=tonumber(data)
                    end
                    reaper.InsertEnvelopePoint(env,values[1]+cursor-point_offset,values[2],values[3],values[4],false,true)
                end
            end
            reaper.Envelope_SortPoints(env)
            local free_env=reaper.BR_EnvAlloc(env,false)
            local _,_,armed,_,_,defaultShape,_,_,_,_,faderScaling=reaper.BR_EnvGetProperties(free_env)
            reaper.BR_EnvSetProperties(free_env,true,true,armed,true,128,defaultShape,faderScaling)
            reaper.BR_EnvFree(free_env,true)
        end
    end

    -- envelope under mouse / selected (plus following visible lanes); else first envelope of each selected track
    local function PasteToTargets(GROUPS,point_offset)
        local cursor=reaper.GetCursorPosition()
        reaper.BR_GetMouseCursorContext()
        local ENV=FindVisEnv(reaper.GetSelectedEnvelope(0) or reaper.BR_GetMouseCursorContext_Envelope())
        if  #ENV>0 then
            PastePoint(ENV,GROUPS,cursor,point_offset)
            return true
        end
        local pasted
        for _,tr in ipairs(r.SaveTracks()) do
            local env=reaper.GetTrackEnvelope(tr,0)
            if  env then
                PastePoint(FindVisEnv(env),GROUPS,cursor,point_offset)
                pasted=true
            end
        end
        return pasted
    end

    -- razor copy: DATA = { {points..., areaStart}, ..., with_item="true"/"nil" }
    local function PasteRazorEnvelope()
        local DATA=unserialize(reaper.GetExtState("EnvCopyBuff","EnvCopyBuff"))
        if  DATA.with_item=="true" or #DATA==0 then return false end
        local offset=math.huge
        for _,group in ipairs(DATA) do
            local s=tonumber(group[#group])
            if s and s<offset then offset=s end
        end
        if offset==math.huge then return false end
        PasteToTargets(DATA,offset)
        return true
    end
    --------------
    local function PasteEnvelope()

        local DATA,trackz,pasted_item

        pasted_item="nothing..."

        DATA=unserialize(reaper.GetExtState("EnvCopyBuff","EnvCopyBuff"))
        trackz=r.SaveTracks()

        if  DATA.type=="Line" then
            local env_name=DATA[2]
            for sun=1,#trackz do
                local pasted,tr,env,free_env,visble,armed,inLane,LaneHeight,defaultShape,faderScaling
                tr=trackz[sun]
                for suni=1,reaper.CountTrackEnvelopes(tr) do
                    env=reaper.GetTrackEnvelope(tr,suni-1)
                    local _,name=reaper.GetEnvelopeName(env)
                    if  name==env_name then
                        reaper.SetEnvelopeStateChunk(env,DATA[1],true)
                        pasted=true
                        break
                    end
                end
                if  not pasted then
                    reaper.SetOnlyTrackSelected(tr)
                    if     env_name == "Volume" then reaper.Main_OnCommand(40406, 0) -- show track volume envelope
                    elseif env_name == "Pan" then reaper.Main_OnCommand(40407, 0)    -- show track pan envelope
                    elseif env_name == "Mute" then reaper.Main_OnCommand(40867, 0)   -- show track mute envelope
                    elseif env_name == "Volume (Pre-FX)" then reaper.Main_OnCommand(40408, 0) -- show track pre-FX volume envelope
                    elseif env_name == "Pan (Pre-FX)" then reaper.Main_OnCommand(40051, 0) -- show track pre-FX pan envelope
                    end
                    env=reaper.GetTrackEnvelopeByName(tr,env_name)
                    if env then reaper.SetEnvelopeStateChunk(env,DATA[1],true) end
                end
                if  env then
                    reaper.Envelope_SortPoints(env)
                    free_env=reaper.BR_EnvAlloc(env,false)
                    _,visble,armed,inLane,LaneHeight,defaultShape,_,_,_,_,faderScaling=reaper.BR_EnvGetProperties(free_env)
                    reaper.BR_EnvSetProperties(free_env,visble,true,armed,inLane,LaneHeight,defaultShape,faderScaling)
                    reaper.BR_EnvFree(free_env,true)
                end
            end
            pasted_item="Line"
        elseif DATA.type=="Point" and tonumber(DATA.start) then
            if  PasteToTargets({DATA},tonumber(DATA.start)) then pasted_item="Points" end
        end

        r.RestoreTracks(trackz)
        reaper.UpdateArrange()
        return "Envelope "..pasted_item
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

          -- envelope-only razor copy is stored by Smart Copy; anything with items uses REAPER's paste
          if  not PasteRazorEnvelope() then
              reaper.Main_OnCommand(42398,0)--paste items
          end
          
          --reaper.Main_OnCommand(42406,0)--clear razor area
        
        elseif state == "Envelope" then

            state=PasteEnvelope()
        
        elseif state == "Track's FX Chain" then
        
            cmd=reaper.NamedCommandLookup("_S&M_COPYFXCHAIN10")
            reaper.Main_OnCommand(cmd,0)--paste focus track FX chain
        
        elseif state == "Focus FX Data" then
            cmd=r.ScriptID("Lyx Scripts/Lyx_Paste focus FX state.lua")
            reaper.Main_OnCommand(cmd,0)--paste focus FX data
        
        end  
        
        r.billboard("Paste "..(state or "nothing").."  ˊ＿>ˋ")

    end

    reaper.Undo_BeginBlock2(0)
    main()
    reaper.Undo_EndBlock2(0,"paste item/track/envelope/FX",-1)
