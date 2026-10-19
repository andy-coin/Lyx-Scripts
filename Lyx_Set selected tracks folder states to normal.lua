
  r=reaper
  
  local trackzzz={}
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
  
  --------------
  local function FollowParentTCPH(track)
    
    cmd=reaper.NamedCommandLookup("_SWS_MINTRACKS")
    reaper.Main_OnCommand(cmd,0)--minimize
    TCPH=reaper.GetMediaTrackInfo_Value(track,"I_TCPH")
    for abi=1,(TCPH-22)/2 do
        reaper.Main_OnCommand(41327,0)
    end
    
  end
  
  --------------
  local function main()
      
      SaveSelectedTracks(trackzzz)
      
      trz={}
      for abi=1,reaper.CountSelectedTracks() do
          tr=reaper.GetSelectedTrack(0,abi-1) 
          if reaper.GetMediaTrackInfo_Value(tr,"I_FOLDERDEPTH")==1 then
             trz[#trz+1]=tr
          end
      end
      
      if #trz==0 then return end

      for abi=1,#trz do
          reaper.SetOnlyTrackSelected(trz[abi])
          cmd=reaper.NamedCommandLookup("_S&M_SENDS5")
          reaper.Main_OnCommand(cmd,0)--remove receives
          for abiii=1,#strings do
              for i=1,33 do
                  reaper.GetSetTrackGroupMembership(trz[abi],strings[abiii],2^(i-1),0)
                  reaper.GetSetTrackGroupMembershipHigh(trz[abi],strings[abiii],2^(i-1),0)
              end
          end
          cmd = reaper.NamedCommandLookup("_SWS_SELCHILDREN")
          reaper.Main_OnCommand(cmd,0)--select only children track
          if reaper.GetMediaTrackInfo_Value(trz[abi],"I_FOLDERCOMPACT")~=0 then
             reaper.SetMediaTrackInfo_Value(trz[abi],"I_FOLDERCOMPACT",0)
             TCPH=reaper.GetMediaTrackInfo_Value(trz[abi],"I_TCPH")
             FollowParentTCPH(trz[abi])
          end
          for abii=1,reaper.CountSelectedTracks(0) do
              local child_tr=reaper.GetSelectedTrack(0,abii-1)
              --reaper.ShowConsoleMsg(tostring(reaper.GetMediaTrackInfo_Value(child_tr,"B_MAINSEND")).."\n")
              reaper.SetMediaTrackInfo_Value(child_tr,"B_MAINSEND",1)
              for abiii=1,#strings do
                  for i=1,33 do
                      reaper.GetSetTrackGroupMembership(child_tr,strings[abiii],2^(i-1),0)
                      reaper.GetSetTrackGroupMembershipHigh(child_tr,strings[abiii],2^(i-1),0)
                  end
              end
          end
      end
      
      RestoreSelectedTracks(trackzzz)
               
      cmd=reaper.NamedCommandLookup("_S&M_FOLDEROFF")
      reaper.Main_OnCommand(cmd,0)
      
  end
  
  strings={"MEDIA_EDIT_LEAD","MEDIA_EDIT_FOLLOW","VOLUME_LEAD","VOLUME_FOLLOW","VOLUME_VCA_LEAD",
           "VOLUME_VCA_FOLLOW","PAN_LEAD","PAN_FOLLOW","WIDTH_LEAD","WIDTH_FOLLOW","MUTE_LEAD",
           "MUTE_FOLLOW","SOLO_LEAD","SOLO_FOLLOW","RECARM_LEAD","RECARM_FOLLOW","POLARITY_LEAD",
           "POLARITY_FOLLOW","AUTOMODE_LEAD","AUTOMODE_FOLLOW","VOLUME_REVERSE","PAN_REVERSE",
           "WIDTH_REVERSE","NO_LEAD_WHEN_FOLLOW","VOLUME_VCA_FOLLOW_ISPREFX"}
           
  reaper.Undo_BeginBlock()
  main()
  reaper.Undo_EndBlock("Set selected tracks folder states to normal",-1)
