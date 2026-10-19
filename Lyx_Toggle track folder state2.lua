  r=reaper
  ---------------------SAVE INITIAL SELECTED TRACKS------------------------------------
  local trackzzz={}
  local trackzz={}
  local trackz={}
  local function SaveSelectedTracks (table)--trackzzz
      for i = 0, reaper.CountSelectedTracks(0)-1 do
        table[i+1] = reaper.GetSelectedTrack(0, i)
      end
  end
  
  ---------------------RESTORE INITIAL SELECTED TRACKS------------------------------------
  local function RestoreSelectedTracks (table)--trackzzz
      reaper.Main_OnCommand(40297,0)
      if #table==0 then return end
      reaper.SetOnlyTrackSelected(table[#table])
      for _, track in ipairs(table) do
        reaper.SetTrackSelected(track, true)
      end
  end
  
  -----------------------SAVE INITIAL SELECTED ITEMS------------------------------------
  itemzzz = {}
  item_L = {}
  local function SaveSelectedItems (table)--itemzzz
      for i = 0, reaper.CountSelectedMediaItems(0)-1 do
        table[i+1] = reaper.GetSelectedMediaItem(0, i)
      end
  end
  
  ----------------------RESTORE INITIAL SELECTED ITEMS------------------------------------
  
  local function RestoreSelectedItems (table)--itemzzz
      reaper.Main_OnCommand(40289, 0) 
      for _, item in ipairs(table) do
        reaper.SetMediaItemSelected(item, true)
      end
  end
  
  ----------------------------------------------------------------------------------
  local function LockHide(trz,key)
      
      reaper.Main_OnCommand(40289,0)--unselect all items
      
      for abi=1,#trz do
          for abii=1,reaper.CountTrackMediaItems(trz[abi]) do
              reaper.SetMediaItemSelected(reaper.GetTrackMediaItem(trz[abi],abii-1),true)
          end 
      end
      
      if key>0 then 
         reaper.Main_OnCommand(40688,0)--lock item 
      else
         reaper.Main_OnCommand(40689,0)--unlock item 
      end
  
  end
  
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
      for abii=1,reaper.CountTrackMediaItems(from) do
          local item=reaper.GetTrackMediaItem(from,0)
          reaper.MoveMediaItemToTrack(item,tmp)
      end
      for abii=1,reaper.CountTrackMediaItems(to) do
          local item=reaper.GetTrackMediaItem(to,0)
          reaper.MoveMediaItemToTrack(item,from)
      end
      for abii=1,reaper.CountTrackMediaItems(tmp) do
          local item=reaper.GetTrackMediaItem(tmp,0)
          reaper.MoveMediaItemToTrack(item,to)
      end
      reaper.DeleteTrack(tmp)--]]
      ExchangeEnvelope(from,to)
      
      _,nAME=reaper.GetSetMediaTrackInfo_String(from,"P_NAME","",false)
      _,Name=reaper.GetSetMediaTrackInfo_String(to,"P_NAME","",false)
      reaper.GetSetMediaTrackInfo_String(from,"P_NAME",Name,true)
      reaper.GetSetMediaTrackInfo_String(to,"P_NAME",nAME,true)--]]
      
  end
  
  --------------
  local function ReorderTrack(Leader)
      
      local NAME,IDX,i,group,time,new_group,new_name,letter,tmp_tr
      time=reaper.time_precise()
      
      IDX=reaper.GetMediaTrackInfo_Value(Leader,"IP_TRACKNUMBER")
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
      until i>#new_group or (reaper.time_precise()-time)>0.5--]]
      
      reaper.GetSetMediaTrackInfo_String(first,"P_TCP_LAYOUT","d3 ------ Red Fader",true)
      
--reaper.ShowConsoleMsg((reaper.time_precise()-time).."\n")
      
  end
  
  ----------------------------------------------------------------------------------
  local function main()
  
  --reaper.PreventUIRefresh(-1)
  SaveSelectedTracks (trackzzz)
  SaveSelectedItems (itemzzz)
    
    parent={}
    
    for abi=1,reaper.CountSelectedMediaItems(0) do
        last_item = reaper.GetSelectedMediaItem(0,abi-1)
        tr=reaper.GetMediaItemTrack(last_item)
        reaper.SetTrackSelected(tr,true)
    end
    
    for abi=1,reaper.CountSelectedTracks(0) do
        local tr=reaper.GetSelectedTrack(0,abi-1)
        mother=reaper.GetParentTrack(tr)
        if reaper.GetMediaTrackInfo_Value(tr,"I_FOLDERDEPTH")<1 then
           if mother then
              parent[#parent+1]=mother
           end
        else
           parent[#parent+1]=tr
        end
    end

    abi=1
    time=reaper.time_precise()
    repeat
        if abi+1>#parent then break end
        if parent[abi]==parent[abi+1] then
           table.remove(parent,abi)
        else
           abi=abi+1
        end
    until (reaper.time_precise()-time)>0.5
  
    normal_folder={}
    children={}
    
    for Abi=1,#parent do
        reaper.SetOnlyTrackSelected(parent[Abi])
        _,layout=reaper.GetSetMediaTrackInfo_String(parent[Abi],"P_TCP_LAYOUT","",false)
        cmd=reaper.NamedCommandLookup("_SWS_SELCHILDREN")
        reaper.Main_OnCommand(cmd,0)--select only children track
        
        for abi=1,reaper.CountSelectedTracks(0) do
            local tr=reaper.GetSelectedTrack(0,abi-1)
            children[abi]=tr
        end
        
        TCPH=reaper.GetMediaTrackInfo_Value(parent[Abi],"I_TCPH")
        
        if layout=="d3 ------ Red Fader" then
            
           TCP=reaper.GetMediaTrackInfo_Value(children[#children],"B_SHOWINTCP")
           
           
           if TCP==1 then
              reaper.SetMediaTrackInfo_Value(parent[Abi],"I_FOLDERCOMPACT",2)
              for abi=1,#children do
                  reaper.SetMediaTrackInfo_Value(children[abi],"I_RECARM",0)
                  reaper.SetMediaTrackInfo_Value(children[abi],"B_AUTO_RECARM",0)
                  reaper.SetMediaTrackInfo_Value(children[abi],"B_MUTE",1)
                  reaper.SetMediaTrackInfo_Value(children[abi],"B_SHOWINTCP",math.abs(TCP-1))
              end
           else
              ReorderTrack(parent[Abi])            
              reaper.SetMediaTrackInfo_Value(parent[Abi],"I_FOLDERCOMPACT",0)
              for abi=1,#children do
                  reaper.SetMediaTrackInfo_Value(children[abi],"B_SHOWINTCP",math.abs(TCP-1))
                  reaper.SetOnlyTrackSelected(children[abi])
                  tcph=reaper.GetMediaTrackInfo_Value(children[abi],"I_TCPH") 
                  times=(tcph-TCPH)/2
                  cmd=math.floor(41327.5+(math.abs(times)/times)/2)
                  for abii=1,math.abs(times) do
                      reaper.Main_OnCommand(math.floor(41327.5+(math.abs(times)/times)/2),0)
                  end
              end  
           end
           
       else
          normal_folder[#normal_folder+1]=parent[Abi]
          
          key=reaper.GetMediaTrackInfo_Value(parent[Abi], "I_FOLDERCOMPACT")
          
          reaper.SetMediaTrackInfo_Value(parent[Abi],"I_FOLDERCOMPACT",(key+1)%3)
                
          if key==0 then
             cmd=reaper.NamedCommandLookup("_SWS_MINTRACKS")
             reaper.Main_OnCommand(cmd,0)
          elseif key==1 then
             for abi=1,#children do
                 reaper.SetMediaTrackInfo_Value(children[abi],"I_RECARM",0)
                 reaper.SetMediaTrackInfo_Value(children[abi],"I_RECARM_AUTO",0)
             end
          elseif key==2 then
             B_AUTO=reaper.GetMediaTrackInfo_Value(parent[Abi],"B_AUTO_RECARM")
             for abi=1,#children do
                 reaper.SetMediaTrackInfo_Value(children[abi],"B_AUTO_RECARM",B_AUTO)
                 tcph=reaper.GetMediaTrackInfo_Value(children[abi],"I_TCPH") 
                 times=(tcph-TCPH)/2
                 cmd=math.floor(41327.5+(math.abs(times)/times)/2)
                 for abii=1,math.abs(times) do
                     reaper.Main_OnCommand(math.floor(41327.5+(math.abs(times)/times)/2),0)
                 end
             end
          end
          --LockHide(children,(key+1)%3)
       end
    end
    
    
    
    RestoreSelectedTracks (trackzzz)
    RestoreSelectedItems (itemzzz) 
    reaper.Main_OnCommand(40913,0)--scroll to track
    
    --reaper.PreventUIRefresh(1)
  end
  
  
  ---------------------
  --reaper.ClearConsole()
  reaper.defer(main)

