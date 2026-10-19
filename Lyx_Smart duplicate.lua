
  local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
  package.path = package.path .. ";" .. script_path .. "?.lua"
  local r=require("_Lyx_HOME")
  
  --------------
  local function DuplicateRazorEnvelope(EL,ELP,x)
      
      for abigel=1,#ELP do
          reaper.InsertEnvelopePoint(EL,ELP[abigel].time+x,ELP[abigel].value,ELP[abigel].shape,ELP[abigel].tension,true,false)  
      end

  end
  
  --------------
  local function main()
      
      local Act="Nothing"

      local Tn=api.cst(0)
      local In=api.csi(0)
      local Env=reaper.GetSelectedEnvelope(0)
      local IsRazor,razorMap=r.GetRazorEdits2()
      if Tn==0 and In==0 and not Env and IsRazor then return end
      
      reaper.Undo_BeginBlock()
      
      win,seg,det=reaper.BR_GetMouseCursorContext()
      
      if  IsRazor then
          Act="Duplicate razor area"
          abi=1
          for abi=1,#razorMap do
              if  not razorMap[abi].isEnvelope then --items
                  ITEM=true
              elseif  razorMap[abi].isEnvelope then --envelops
                  min=razorMap[abi].areaStart
                  max=razorMap[abi].areaEnd
                  reaper.DeleteEnvelopePointRange(razorMap[abi].envelope,max+0.0000000001,max+(max-min)+0.0000000001)
                  DuplicateRazorEnvelope(razorMap[abi].envelope,razorMap[abi].envelopePoints,max-min)
              end
          end
          if ITEM then reaper.Main_OnCommand(41295,0) end
      elseif Env then
          local En=reaper.CountEnvelopePoints(Env)
          if  En>0 then
              min=math.huge
              max=0
              for abi=1,En do
                  retval, point_time, value, shapeOut, tension, selected = reaper.GetEnvelopePoint(Env,abi)
                  if  selected then 
                      Act="Duplicate selected envelope points"
                      if  min>point_time then 
                          min=point_time
                      end
                      if  max<point_time then
                          max=point_time
                      end 
                      Points=true
                  end
              end
              if  Points then
                  --reaper.DeleteEnvelopePointRange(Env,max+0.0000000001,max+(max-min)+0.0000000001)
                  cmd=r.ScriptID("MPL Scripts/Envelopes/mpl_Duplicate envelope points.lua")
                  reaper.Main_OnCommand(cmd,0)--duplicate envelope points
              end
          end
      elseif (win=="tcp" and In>1 and Tn==1 ) or 
          (win=="arrange" and In>Tn) or
          (win~='tcp' and In>1 and Tn==1) or
          (det=="item" or det=="item_stretch_marker" and Tn==1 ) then
        
          
          Act="Duplicate selected items"
          as,ae=reaper.BR_GetArrangeView(0)
          pos=reaper.GetCursorPosition()
          reaper.Main_OnCommand(41295,0)
          reaper.BR_SetArrangeView(0,as,ae)
          reaper.SetEditCurPos(pos,false,false)
      elseif Tn>0 then
      
          cmd=reaper.NamedCommandLookup("_SWS_UNSELCHILDREN")
          reaper.Main_OnCommand(cmd,0)--select children
          
          local trz=r.SaveTracks()
          local tr_group={}
          local  ip,last_ip,folder,last_folder,depth
          depth={}
          
          local structure,deep=r.FolderStructure(true)
          for sun=1,#trz do
              local idx=api.gtv(trz[sun],"IP_TRACKNUMBER")
              depth[sun]=structure[idx]
          end
          folder={}
          for sun=1,deep do
              folder[sun]={}
          end
          for sun=1,#depth do
              for suni=1,deep do
                  if  depth[sun]==suni then
                      folder[suni][#folder[suni]+1]=trz[sun]
                  end
              end
          end
          
          time=api.now()
          new_trz={}
          for abi=1,#folder do
              reaper.Main_OnCommand(40297,0)
              if  #folder[abi]>1 then
                  
                  first=folder[abi][1]
                  reaper.SetTrackSelected(first,true)
                  last_idx=api.gtv(folder[abi][1],"IP_TRACKNUMBER")
                  child_n=0
                  
                  if  api.gtv(first,"I_FOLDERDEPTH")==1 then
                      local tmp_trz=r.SaveTracks()
                      reaper.SetOnlyTrackSelected(first)
                      cmd=reaper.NamedCommandLookup("_SWS_SELCHILDREN2")
                      reaper.Main_OnCommand(cmd,0)--select all children
                      last_idx=api.gtv(api.gst(0,api.cst(0)-1),"IP_TRACKNUMBER")
                      r.RestoreTracks(tmp_trz)
                  end
                  
                  local function CnM(F)
                      reaper.Main_OnCommand(40062,0)--duplicate 
                      for abiii=1,api.cst(0) do
                          new_trz[#new_trz+1]=api.gst(0,abiii-1)
                      end
                      cmd=reaper.NamedCommandLookup("_SWS_SELCHILDREN2")
                      reaper.Main_OnCommand(cmd,0)--select all children
                      t_n=api.cst(0)
                      local idx=api.gtv(api.gst(0,t_n-1),"IP_TRACKNUMBER")
                      reaper.ReorderSelectedTracks(idx,F)
                      reaper.Main_OnCommand(40297,0)
                      return t_n
                  end
                  
                  for abii=2,#folder[abi] do
                      
                      local last
                      local tr=folder[abi][abii]
                      local idx=api.gtv(folder[abi][abii],"IP_TRACKNUMBER")
                      
                      local F=(abi>1 and 2) or 0
                      
                      --msg(abii.."|"..last_idx.."|"..idx)
                      
                      if  idx-last_idx==1 then
                          if  abii==#folder[abi] then
                              reaper.SetTrackSelected(folder[abi][abii],true)
                              CnM(F)
                              break
                          else
                              reaper.SetTrackSelected(folder[abi][abii],true)
                          end
                      else
                          if  abii==#folder[abi] then
                              CnM(F)
                              reaper.SetTrackSelected(folder[abi][abii],true)
                              reaper.Main_OnCommand(40062,0)--duplicate
                              new_trz[#new_trz+1]=api.gst(0,0)
                              break
                          else
                              idx=idx+CnM(F)
                              reaper.SetTrackSelected(folder[abi][abii],true)
                          end
                      end
                      
                      if  api.gtv(tr,"I_FOLDERDEPTH")==1 then
                          local tmp_trz=r.SaveTracks()
                          reaper.SetOnlyTrackSelected(tr)
                          cmd=reaper.NamedCommandLookup("_SWS_SELCHILDREN2")
                          reaper.Main_OnCommand(cmd,0)--select all children
                          last=api.gst(0,api.cst(0)-1)
                          r.RestoreTracks(tmp_trz)
                      end
                     
                      last_idx= (last and api.gtv(last,"IP_TRACKNUMBER")) or idx
                      
                  end
              elseif #folder[abi]==1 then
                  reaper.SetTrackSelected(folder[abi][1],true)
                  reaper.Main_OnCommand(40062,0)--duplicate
                  new_trz[#new_trz+1]=api.gst(0,0)
              end
          end
          
          r.RestoreTracks(new_trz)
      end
      
      reaper.Undo_EndBlock(Act,-1)
      
  end
  reaper.ClearConsole()
  main()
