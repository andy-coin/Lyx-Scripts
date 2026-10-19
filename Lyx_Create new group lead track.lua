  
  r=reaper
  
  --------------
  local function CheckFollowTrack()
      
      string={"VOLUME_FOLLOW","VOLUME_VCA_FOLLOW","PAN_FOLLOW","WIDTH_FOLLOW",
              "MUTE_FOLLOW","SOLO_FOLLOW","RECARM_FOLLOW", "POLARITY_FOLLOW","AUTOMODE_FOLLOW"}
              
      follow={}
      for abi=1,reaper.CountTracks(0) do
          local tr=reaper.GetTrack(0,abi-1)
          _,layout=reaper.GetSetMediaTrackInfo_String(tr,"P_MCP_LAYOUT","",false)
          if layout=="c2 -- FX Rack_EX" then
             follow[#follow+1]=tr
          end
      end
      
      for abi=1,#follow do
          for abii=1,#string do
              group_ID=reaper.GetSetTrackGroupMembership(follow[abi],string[abii],0,0)
              if group_ID~=0 then break end
          end
          for abii=1,#string do
              group_ID_High=reaper.GetSetTrackGroupMembershipHigh(follow[abi],string[abii],0,0)
              if group_ID_High~=0 then break end
          end
      end
      return follow,group_ID,group_ID_High
  end
  
  --------------
  local function main()
      
      if reaper.CountTracks(0)==0 then return end
      
      cmd=reaper.NamedCommandLookup("_RS239d26e2d82d9743d5dd6ad97307495aba9e14dd")
      reaper.Main_OnCommand(cmd,0)--create group
      
      trz,ID,ID_High=CheckFollowTrack()
      if #trz==0 then return end
      idx=reaper.GetMediaTrackInfo_Value(trz[1],"IP_TRACKNUMBER")-1
      reaper.InsertTrackAtIndex(idx,false)
      lead=reaper.GetTrack(0,idx)
      reaper.SetOnlyTrackSelected(lead)
      reaper.GetSetTrackGroupMembership(lead,"VOLUME_VCA_LEAD",ID,ID)
      reaper.GetSetTrackGroupMembershipHigh(lead,"VOLUME_VCA_LEAD",ID_High,ID_High)
      
      for abi=1,#trz do
          local send = reaper.CreateTrackSend(trz[abi],lead)
          reaper.SetMediaTrackInfo_Value(trz[abi],"B_MAINSEND",0)
          reaper.SetTrackSendInfo_Value(trz[abi],0,send,"D_VOL",1)
          reaper.SetTrackSendInfo_Value(trz[abi],0,send,"I_SENDMODE",0)
          reaper.GetSetMediaTrackInfo_String(trz[abi],"P_MCP_LAYOUT","",true)
      end
      
      reaper.GetSetMediaTrackInfo_String(lead,"P_NAME","Lead",true)
      
      reaper.Main_OnCommand(40772,0)
      
  end
  
  main()

