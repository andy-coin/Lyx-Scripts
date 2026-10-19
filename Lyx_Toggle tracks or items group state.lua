
  local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
  package.path = package.path..";"..script_path.."?.lua"
  local r=require("_Lyx_HOME")

  -----CUSTOM-----
  GROUP_MCP_LAYOUT = "c2 -- FX Rack_EX" -- MCP layout for grouped tracks; "" keeps each track's own layout
  ----------------
  
  --------------
  local function NextTrack(tr)
    
      ::Start::
      
      local idx,cur,state,parent
      idx = reaper.GetMediaTrackInfo_Value(tr,"IP_TRACKNUMBER")
      
      if idx == reaper.CountTracks(0) then return end
      
      cur=reaper.GetTrack(0,idx)
      
      if not cur then return end
      
      if  not api.itv(cur,false) then
          hide = true
      end
      
      if hide then
         hide=nil
         tr=cur
         goto Start
      end
      
      return cur
  end
  
  ----------------
  local function AllGroup(n)
    
      two = {}
      for abi = 1,32 do 
          local abii=1
          local abiii=1
          repeat
              abiii = abiii+abiii
              abii=abii+1
          until abii==abi or abii==33
          two[abi]=abiii
      end
      two[1]=1
      return two[n],two
  end
  
  --------------
  local function FindGroup(N)
  
      local groupID={}
      local two = {}
      for abi = 1,32 do
          two[abi] = AllGroup(abi)
      end
      
      i={}
      for abi = 1,32 do
          i[abi]=33-abi
      end
      
      --reaper.ShowConsoleMsg("N = "..N.."\n")
        ten = N
        s = -1
      repeat
          ten = math.floor(ten/10)
          s=s+1
      until 0 == math.floor(ten) or time1 == os.time()-5
      
      if s == 0 then abigel = 28
      elseif s == 1 then abigel = 25
      elseif s == 2 then abigel = 22
      elseif s == 3 then abigel = 18
      elseif s == 4 then abigel = 15
      elseif s == 5 then abigel = 12
      elseif s == 6 then abigel = 8
      elseif s == 7 then abigel = 5
      elseif s == 8 then abigel = 2
      elseif s == 9 then abigel = 0
      end
      
      abigel = abigel+1
      
      local time1 = os.time()
      for abi=1,32 do
   
          local time2 = os.time()
          repeat
              if N-two[i[abigel]] >= 0 then 
                 N = N-two[i[abigel]]
                 groupID[abi]=i[abigel]
                 --reaper.ShowConsoleMsg("group = "..groupID[abi].."\n")
                 break 
              end
              abigel = abigel+1
          until abigel == 33 or time2 == os.time()-5
          
          if N == 0 then break end
          if N < 0 then return false end
      end
      
      table.sort(groupID)
      
      for apple=1,#groupID do
          --reaper.ShowConsoleMsg(groupID[apple].."|")
      end
      
      return groupID
  
  end
  
  --------------
  local function UsedGroup(bit)
    
      local time = os.time()
      local abiiiii=1
      repeat
          if AllGroup(abiiiii) == nil then break end
          if bit[abiiiii]==AllGroup(abiiiii)then
             --reaper.ShowConsoleMsg(bit[abiiiii].."|"..AllGroup(abiiiii).."\n")
          else
             return AllGroup(abiiiii),#bit
          end
          abiiiii = abiiiii+1
      until abiiiii > #bit+1 or time == os.time()-20
      
      return nil,32
  end
  
  --------------
  local function UnusedGroup()
    
      local ID = {}
      local _,groupID=AllGroup()
      local tr = {}
      local delete={}
      time6 = os.time() 
      
      for abi=1,reaper.CountTracks(0) do
          tr[abi]=reaper.GetTrack(0,abi-1)
          abii = 1
          local string = { 
          "VOLUME_FOLLOW","VOLUME_VCA_FOLLOW","PAN_FOLLOW","WIDTH_FOLLOW","MUTE_FOLLOW","SOLO_FOLLOW","RECARM_FOLLOW",
          "POLARITY_FOLLOW","AUTOMODE_FOLLOW"}
          repeat
              if 0 ~= reaper.GetSetTrackGroupMembership(tr[abi],string[abii],0,0) then
                 ID[abii]=FindGroup(reaper.GetSetTrackGroupMembership(tr[abi],string[abii],0,0))
                 --reaper.ShowConsoleMsg(" abii = "..abii.."\nstring = "..string[abii].."\n#string = "..(#string+1).."\n\n")
                 table.remove(string,abii)
                 for abiii=1,#ID[abii] do
                     delete[#delete+1] = groupID[ID[abii][abiii]]
                     --reaper.ShowConsoleMsg("ID = "..(ID[abii][abiii]).."\n".."delete = "..delete[#delete].."\n")
                 end
              else
                 abii = abii +1
              end
          until  abii > #string or time6 < os.time()-5
          table.sort(delete)
          local time10 = os.time()
          local lab=1
          repeat
              if delete[lab+1] == nil then break end
              if delete[lab]==delete[lab+1]then
                 table.remove(delete,lab+1)
              else
                 lab=lab+1
              end
          until lab == #delete or time10 == os.time()-20
          if #delete == 32 then break end --]]
      end
      
      return delete
    
  end
    
  --------------
  local function UnusedGroupHigh()
    
      local ID = {}
      local _,groupID=AllGroup()
      local tr = {}
      local delete={}
      
      for abi=1,reaper.CountTracks(0) do
          tr[abi]=reaper.GetTrack(0,abi-1)
          abii = 1
          local string = { 
          "VOLUME_FOLLOW","VOLUME_VCA_FOLLOW","PAN_FOLLOW","WIDTH_FOLLOW","MUTE_FOLLOW","SOLO_FOLLOW","RECARM_FOLLOW",
          "POLARITY_FOLLOW","AUTOMODE_FOLLOW"}
          repeat
              if 0 ~= reaper.GetSetTrackGroupMembershipHigh(tr[abi],string[abii],0,0) then
                 ID[abii]=FindGroup(reaper.GetSetTrackGroupMembershipHigh(tr[abi],string[abii],0,0))
                 --reaper.ShowConsoleMsg(" abii = "..abii.."\nstring = "..string[abii].."\n#string = "..(#string+1).."\n\n")
                 table.remove(string,abii)
                 for abiii=1,#ID[abii] do
                     delete[#delete+1] = groupID[ID[abii][abiii]]
                     --reaper.ShowConsoleMsg("ID = "..(ID[abii][abiii]).."\n".."delete = "..delete[#delete].."\n")
                 end
              else
                 abii = abii +1
              end
          until  abii > #string or time6 < os.time()-5
          table.sort(delete)
          local time10 = os.time()
          local lab=1
          repeat
              if delete[lab+1] == nil then break end
              if delete[lab]==delete[lab+1]then
                 table.remove(delete,lab+1)
              else
                 lab=lab+1
              end
          until lab == #delete or time10 == os.time()-20
          if #delete == 32 then break end --]]
      end
      
      return delete
  
  end
    
  --------------
  local function ScanGroup(tr)
      
      String={"VOLUME_LEAD","VOLUME_VCA_LEAD","PAN_LEAD","WIDTH_LEAD",
              "MUTE_LEAD","SOLO_LEAD","RECARM_LEAD", "POLARITY_LEAD","AUTOMODE_LEAD",
              "VOLUME_FOLLOW","VOLUME_VCA_FOLLOW","PAN_FOLLOW","WIDTH_FOLLOW","MUTE_FOLLOW",
              "SOLO_FOLLOW","RECARM_FOLLOW","POLARITY_FOLLOW","AUTOMODE_FOLLOW","VOLUME_REVERSE",
              "PAN_REVERSE","WIDTH_REVERSE","NO_LEAD_WHEN_FOLLOW","VOLUME_VCA_FOLLOW_ISPREFX"}
              
      for ABIGEL=1,#String do
          if reaper.GetSetTrackGroupMembership(tr,String[ABIGEL],0,0)~=0 then
             return true
          end
      end
      
      for ABIGEL=1,#String do
          if reaper.GetSetTrackGroupMembershipHigh(tr,String[ABIGEL],0,0)~=0 then
             return true
          end
      end
      
      return false 
  
  end
  
  --------------
  local function Hamburger()
      
      String={"VOLUME_LEAD","VOLUME_VCA_LEAD","PAN_LEAD","WIDTH_LEAD",
              "MUTE_LEAD","SOLO_LEAD","RECARM_LEAD", "POLARITY_LEAD","AUTOMODE_LEAD"}
              
      string={"VOLUME_FOLLOW","VOLUME_VCA_FOLLOW","PAN_FOLLOW","WIDTH_FOLLOW",
              "MUTE_FOLLOW","SOLO_FOLLOW","RECARM_FOLLOW", "POLARITY_FOLLOW","AUTOMODE_FOLLOW"}
              
      first=reaper.GetSelectedTrack(0,0)
      upfloor=reaper.GetTrack(0,reaper.GetMediaTrackInfo_Value(first,"IP_TRACKNUMBER")-2)
      
      last=reaper.GetSelectedTrack(0,reaper.CountSelectedTracks(0)-1)
      nextfloor=NextTrack(last)
      
      if not nextfloor then return end
      
      for abi=1,#String do
         up=reaper.GetSetTrackGroupMembership(upfloor,String[abi],0,0)
         if up~=0 then
            down=reaper.GetSetTrackGroupMembership(nextfloor,string[abi],0,0) 
            if up==down then
               SAME=true
               for Abi=1,reaper.CountSelectedTracks(0) do
                   local tr=reaper.GetSelectedTrack(0,Abi-1)
                   reaper.GetSetTrackGroupMembership(tr,string[abi],up,up) 
               end
            end
         end
      end
     
      if SAME then
         --reaper.Main_OnCommand(40772,0)--show track group list
         return true
      end
      
      for abi=1,#String do
         up=reaper.GetSetTrackGroupMembershipHigh(upfloor,String[abi],0,0)
         if up~=0 then
            down=reaper.GetSetTrackGroupMembershipHigh(nextfloor,string[abi],0,0) 
            if up==down then
               SAME=true
               for Abi=1,reaper.CountSelectedTracks(0) do
                   local tr=reaper.GetSelectedTrack(0,Abi-1)
                   reaper.GetSetTrackGroupMembershipHigh(tr,string[abi],up,up) 
               end
            end
         end
      end
      --reaper.ShowConsoleMsg("2"..up)
      if SAME then
         --reaper.Main_OnCommand(40772,0)--show track group list
         return true
      end
      
      for abi=1,#string do
         up=reaper.GetSetTrackGroupMembership(upfloor,string[abi],0,0)
         if up~=0 then
            down=reaper.GetSetTrackGroupMembership(nextfloor,string[abi],0,0) 
            if up==down then
               SAME=true
               for Abi=1,reaper.CountSelectedTracks(0) do
                   local tr=reaper.GetSelectedTrack(0,Abi-1)
                   reaper.GetSetTrackGroupMembership(tr,string[abi],up,up) 
               end
            end
         end
      end
      --reaper.ShowConsoleMsg("3"..up)
      if SAME then
         --reaper.Main_OnCommand(40772,0)--show track group list
         return true
      end
      
      for abi=1,#string do
         up=reaper.GetSetTrackGroupMembershipHigh(upfloor,string[abi],0,0)
         if up~=0 then
            down=reaper.GetSetTrackGroupMembershipHigh(nextfloor,string[abi],0,0) 
            if up==down then
               SAME=true
               for Abi=1,reaper.CountSelectedTracks(0) do
                   local tr=reaper.GetSelectedTrack(0,Abi-1)
                   reaper.GetSetTrackGroupMembershipHigh(tr,string[abi],up,up) 
               end
            end
         end
      end
      --reaper.ShowConsoleMsg("4"..up)
      if SAME then
         --reaper.Main_OnCommand(40772,0)--show track group list
         return true
      end
       
      return false
  end
  
  --------------
  local function ToggleItemGroups()
      
      local id={}
      
      for abi=1,api.csi(0) do
          local item=reaper.GetSelectedMediaItem(0,abi-1)
           if r.IsItemVisible(item) then
              id[#id+1]=reaper.GetMediaItemInfo_Value(item,"I_GROUPID")
           end
      end    
      
      --table.sort(id)
      
      _,id = r.KillTable(id)

      if #id==1 then
         if id[1]==0 then
            reaper.Main_OnCommand(40032,0)--group items
         else
            reaper.Main_OnCommand(40033,0)--ungroup items
         end
      else
         reaper.Main_OnCommand(40032,0)--group items
      end
  end
  
  --------------
  local function ToggleTrackGroups(key)
      
      parentz={}
      tr_n=reaper.CountSelectedTracks(0)
      for Abi=1,tr_n do
          local tr=reaper.GetSelectedTrack(0,Abi-1)
          Ingroup=ScanGroup(tr)
          if Ingroup then
             reaper.Main_OnCommand(40772,0)--show track group list
             return
          else
             parent=reaper.GetParentTrack(tr)
             if parent then
                parentz[#parentz+1]=parent
             end
          end 
      end
      
      if tr_n==#parentz then
         key=true
         for abi=1,#parentz do
             if parentz[1]~=parentz[abi] then
                key=false
                break
             end
         end
      end
      
      string={"VOLUME_FOLLOW","VOLUME_VCA_FOLLOW","PAN_FOLLOW","WIDTH_FOLLOW",
              "MUTE_FOLLOW","SOLO_FOLLOW","RECARM_FOLLOW", "POLARITY_FOLLOW","AUTOMODE_FOLLOW"}
      
      if key then 
         if Hamburger() or tr_n==1 then return end
      end
      
      empty_ID,used_n = UsedGroup(UnusedGroup())
      if used_n == 32 then
         empty_ID,used_n = UsedGroup(UnusedGroupHigh())
         if used_n == 32 then
            reaper.ShowMessageBox("There is no more available group !  >_<","Groups are all full !!",0)
            return
         else
            for abi=1,reaper.CountSelectedTracks(0) do
                tr= reaper.GetSelectedTrack(0,abi-1)
                if GROUP_MCP_LAYOUT ~= "" then reaper.GetSetMediaTrackInfo_String(tr,"P_MCP_LAYOUT",GROUP_MCP_LAYOUT,true) end
                for abii=1,#string do
                    reaper.GetSetTrackGroupMembershipHigh(tr,string[abii],empty_ID,empty_ID)
                end 
            end
         end
      else
         for abi=1,reaper.CountSelectedTracks(0) do
             tr= reaper.GetSelectedTrack(0,abi-1)
             if GROUP_MCP_LAYOUT ~= "" then reaper.GetSetMediaTrackInfo_String(tr,"P_MCP_LAYOUT",GROUP_MCP_LAYOUT,true) end
             for abii=1,#string do
                 reaper.GetSetTrackGroupMembership(tr,string[abii],empty_ID,empty_ID)
             end
         end
      end
      
  
  end
  
  --------------
  local function main()
      
      it_n=reaper.CountSelectedMediaItems(0)
      tr_n=reaper.CountSelectedTracks(0)
      
      if it_n >= tr_n then
         ToggleItemGroups()
      elseif tr_n>1 then
         r.SelTrackFilter()
         ToggleTrackGroups()
      elseif tr_n==1 and it_n<=1 then
         ToggleTrackGroups(1)
      end
  
  end
  
  reaper.Undo_BeginBlock()
  main()
  reaper.Undo_EndBlock("Toggle tracks or items group state",-1)
