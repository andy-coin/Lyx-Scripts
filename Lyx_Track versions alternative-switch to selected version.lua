    
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_Lyx_HOME")

    --[[
    --------------------------------------
    local function ExchangeEnvelope(tr,ch)
        Envname={"Volume","Pan","Mute","Volume (Pre-FX)"}
        cmd={40406,40407,40867,40408}
        En=reaper.CountTrackEnvelopes(tr)
        en=reaper.CountTrackEnvelopes(ch)
        complete=0
        for abiii=0,En-1 do
            Env=reaper.GetTrackEnvelope(tr,abiii)
            _,envname=reaper.GetEnvelopeName(Env)
            br_Env=reaper.BR_EnvAlloc(Env,false)
            Active,Visible,Armed,InLane,LaneHeight,DefaultShape,_,_,_,_,FaderScaling = reaper.BR_EnvGetProperties( br_Env )
            local Ep=reaper.CountEnvelopePoints(Env)
            if Ep>1 then
                if envname=="Volume" then
                    key=1
                    volume=true
                elseif envname=="Pan" then
                    key=2
                    pan=true
                elseif envname=="Mute" then
                    key=3
                    mute=true
                elseif envname=="Volume (Pre-FX)" then
                    key=4
                    VPFX=true
                end
                if key then
                    env=reaper.GetTrackEnvelopeByName(ch,Envname[key])
                    if not env then
                    reaper.SetOnlyTrackSelected(ch)
                    reaper.Main_OnCommand(cmd[key],0)
                    env=reaper.GetTrackEnvelopeByName(ch,Envname[key])
                    end
                    br_env=reaper.BR_EnvAlloc(env,false)
                    active,visible,armed,inLane,laneHeight,defaultShape,_,_,_,_,faderScaling = reaper.BR_EnvGetProperties( br_env )
                    reaper.BR_EnvSetProperties(br_env,Active,Visible,Armed,InLane,LaneHeight,DefaultShape,FaderScaling)
                    reaper.BR_EnvSetProperties(br_Env,active,visible,armed,inLane,laneHeight,defaultShape,faderScaling)
                    reaper.BR_EnvFree( br_env, true )
                    reaper.BR_EnvFree( br_Env, true )
                    Env=reaper.GetTrackEnvelopeByName(tr,Envname[key])
                    env=reaper.GetTrackEnvelopeByName(ch,Envname[key])
                    _,Chunk=reaper.GetEnvelopeStateChunk(Env,"", false)
                    _,chunk=reaper.GetEnvelopeStateChunk(env,"", false)
                    reaper.SetEnvelopeStateChunk(Env,chunk,true)
                    reaper.SetEnvelopeStateChunk(env,Chunk,true)
                    complete=complete+1
                end
                Chunk=nil
                chunk=nil
                key=nil
            end
            if complete == En and En==en then return end
        end
        for abiii=0,en-1 do
            env=reaper.GetTrackEnvelope(ch,abiii)
            _,envname=reaper.GetEnvelopeName(env)
            br_env=reaper.BR_EnvAlloc(env,false)
            active,visible,armed,inLane,laneHeight,defaultShape,_,_,_,_,faderScaling = reaper.BR_EnvGetProperties( br_env )
            local ep=reaper.CountEnvelopePoints(env)
            if ep>1 then
                if envname=="Volume" and not volume then
                    key=1
                elseif envname=="Pan" and not pan then
                    key=2
                elseif envname=="Mute" and not mute then
                    key=3
                elseif envname=="Volume (Pre-FX)" then
                    key=4
                end
                if key then
                    Env=reaper.GetTrackEnvelopeByName(tr,Envname[key])
                    if not Env then
                    reaper.SetOnlyTrackSelected(tr)
                    reaper.Main_OnCommand(cmd[key],0)
                    Env=reaper.GetTrackEnvelopeByName(tr,Envname[key])
                    end
                    br_Env=reaper.BR_EnvAlloc(Env,false)
                    Active,Visible,Armed,InLane,LaneHeight,DefaultShape,_,_,_,_,FaderScaling = reaper.BR_EnvGetProperties( br_Env )
                    reaper.BR_EnvSetProperties(br_env,Active,Visible,Armed,InLane,LaneHeight,DefaultShape,FaderScaling)
                    reaper.BR_EnvSetProperties(br_Env,active,visible,armed,inLane,laneHeight,defaultShape,faderScaling)
                    reaper.BR_EnvFree( br_env, true )
                    reaper.BR_EnvFree( br_Env, true )
                    Env=reaper.GetTrackEnvelopeByName(tr,Envname[key])
                    env=reaper.GetTrackEnvelopeByName(ch,Envname[key])
                    _,Chunk=reaper.GetEnvelopeStateChunk(Env,"", false)
                    _,chunk=reaper.GetEnvelopeStateChunk(env,"", false)
                    reaper.SetEnvelopeStateChunk(Env,chunk,true)
                    reaper.SetEnvelopeStateChunk(env,Chunk,true)
                end
                Chunk=nil
                chunk=nil
                key=nil
            end
        end
    end
    
    --------------
    local function ExchaneTrackItems(from,to)
        
        if not from or not to then return end
        
        reaper.InsertTrackAtIndex(reaper.CountTracks(0),false)
        local tmp=reaper.GetTrack(0,reaper.CountTracks(0)-1)
        for abi=1,reaper.CountTrackMediaItems(from) do
            local item=reaper.GetTrackMediaItem(from,0)
            reaper.MoveMediaItemToTrack(item,tmp)
        end
        for abi=1,reaper.CountTrackMediaItems(to) do
            local item=reaper.GetTrackMediaItem(to,0)
            reaper.MoveMediaItemToTrack(item,from)
        end
        for abi=1,reaper.CountTrackMediaItems(tmp) do
            local item=reaper.GetTrackMediaItem(tmp,0)
            reaper.MoveMediaItemToTrack(item,to)
        end
        reaper.DeleteTrack(tmp)
        ExchangeEnvelope(from,to)
        
        _,NAME=reaper.GetSetMediaTrackInfo_String(from,"P_NAME","",false)
        _,name=reaper.GetSetMediaTrackInfo_String(to,"P_NAME","",false)
        reaper.GetSetMediaTrackInfo_String(from,"P_NAME",name,true)
        reaper.GetSetMediaTrackInfo_String(to,"P_NAME",NAME,true)
        
    end
    
    --------------
    local function Switch()
        
        local NAME,IDX,i,group,time,new_group,new_name,letter,tmp_tr
        time=reaper.time_precise()
        
        reaper.BR_GetMouseCursorContext()
        target=reaper.BR_GetMouseCursorContext_Track()
        Leader=reaper.GetParentTrack(target)
        if not target or not Leader then return end
        IDX=reaper.GetMediaTrackInfo_Value(Leader,"IP_TRACKNUMBER")
        idx=reaper.GetMediaTrackInfo_Value(target,"IP_TRACKNUMBER")
        group={}
        NAME={}
        new_group={}
        new_name={}
        i=-1
        max=0
        repeat
            group[#group+1]=reaper.GetTrack(0,IDX+i)
            _,name=reaper.GetSetMediaTrackInfo_String(group[#group],"P_NAME","",false)
            NAME[#NAME+1]=name
            letter=name:match("  |  (%u)")
            if not letter then 
                new_group[#new_group+1]=group[#group]                  
                new_name[#new_name+1]=name
                goto NEXT 
            end
            if max<string.byte(letter) then max=string.byte(letter) end 
            ::NEXT::
            i=i+1
        until reaper.GetMediaTrackInfo_Value(group[#group],"I_FOLDERDEPTH")<0 or (reaper.time_precise()-time)>0.5 
        
        char=65
        repeat
            local sub_tr={}
            local sub_version={}
            local sub_name={}
            for abi=1,#group do
                version=NAME[abi]:match("  |  "..string.char(char).."[^%d](%d+)")
                if version then
                    sub_tr[#sub_tr+1]=group[abi]
                    sub_version[#sub_version+1]=version
                    sub_name[#sub_name+1]=NAME[abi]
                elseif NAME[abi]:match("  |  "..string.char(char)) then
                    new_group[#new_group+1]=group[abi]
                    new_name[#new_name+1]=NAME[abi]
                end
            end

            left=#sub_version
            if left>0 then
                i=1
                repeat
                    for abi=1,#sub_version do
                        if tonumber(sub_version[abi])==i then
                            new_group[#new_group+1]=sub_tr[abi]
                            new_name[#new_name+1]=sub_name[abi]
                            left=left-1
                        end
                    end
                    i=i+1
                until i>#sub_version or left==0 or (reaper.time_precise()-time)>0.5
            end
            char=char+1
        until #new_group==#group or char>max or (reaper.time_precise()-time)>0.5
        
        first=group[1]
        
        if target~=new_group[1] then
            new_group[idx-IDX+1]=new_group[1]
            new_group[1]=target
        end
        
        i=1
        repeat
            for abi=1,#new_group do
                if new_group[i]==group[abi] and i~=abi then
                    ExchaneTrackItems(new_group[i],new_group[abi])
                    reaper.GetSetMediaTrackInfo_String(group[abi],"P_TCP_LAYOUT","",true)
                    tmp_tr=group[i]
                    group[i]=group[abi]
                    group[abi]=tmp_tr
                    break
                end 
            end
            i=i+1 
        until i>#new_group or (reaper.time_precise()-time)>0.5
        
        reaper.GetSetMediaTrackInfo_String(first,"P_TCP_LAYOUT","d3 ------ Red Fader",true)
        reaper.SetOnlyTrackSelected(target)
    --reaper.ShowConsoleMsg((reaper.time_precise()-time).."\n")
        
    end--]]
    
    local function Switch_V2()



    end

    reaper.ClearConsole()
    reaper.Undo_BeginBlock()
    Switch_v2()
    reaper.Undo_EndBlock("Switch to Selected track version",-1)
    
    
    
    
