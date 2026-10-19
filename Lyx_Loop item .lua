
  r=reaper
  
  ---------------------SAVE INITIAL SELECTED TRACKS------------------------------------

  local function SaveSelectedTracks (table)--trackzzz
    for i = 0, reaper.CountSelectedTracks(0)-1 do
      table[i+1] = reaper.GetSelectedTrack(0, i)
    end
  end
  
  ---------------------RESTORE INITIAL SELECTED TRACKS------------------------------------
  local function RestoreSelectedTracks (table)--trackzzz
    reaper.Main_OnCommand(40297,0)
    for _, track in ipairs(table) do
      reaper.SetTrackSelected(track, true)
    end
  end
  
  -----------------------SAVE INITIAL SELECTED ITEMS------------------------------------

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
  
  ---------------------------------------------------------------
  
  local function SaveItemID()
  
    trackzzz={}
    SaveSelectedTracks(trackzzz)
    
      if item_n == 1 then
      
        cmd = reaper.NamedCommandLookup("_SWS_SELTRKWITEM")
        reaper.Main_OnCommand(cmd,0)--select only track
        Item = reaper.GetSelectedMediaItem(0,0)
        Tr = reaper.GetSelectedTrack(0,0)
        tr= reaper.GetMediaTrackInfo_Value(Tr,"IP_TRACKNUMBER")
        tri = reaper.GetMediaItemInfo_Value(CurItem,"IP_ITEMNUMBER")
        ext_name = "ItemID_tr"
        tr = reaper.SetExtState(ext_name,"ItemID_tr",tr, true)
        ext_name = "ItemID_tri"
        tri = reaper.SetExtState(ext_name,"ItemID_tri",tri, true)
      
      else
      
        reaper.ShowConsoleMsg("more than one item >_< ")
      
      end
    
    RestoreSelectedTracks(trackzzz)
  end
  
  -----------------------------------LOAD SCREEN POSITION-------------------------------------------------
  
  local function LoadItemID()
  
    ext_name = "ItemID_tr"
    tr = reaper.GetExtState(ext_name,"ItemID_tr",false)
    ext_name = "ItemID_tri"
    tri = reaper.GetExtState(ext_name,"ItemID_tri",false)
    return tr,tri
  
  end
  
  -------------------------------------------------------------------------------------------------------------
  
  function main()
  
    trackzzz={}
    itemzzz={}
    SaveSelectedTracks(trackzzz)
    SaveSelectedItems(itemzzz)
    CurItem = reaper.GetSelectedMediaItem(0,0)
    item_n = reaper.CountSelectedMediaItems(0)
     
      if item_n == 1 then 
        
        last_tr,last_tri=LoadItemID()
        cmd = reaper.NamedCommandLookup("_SWS_SELTRKWITEM")
        reaper.Main_OnCommand(cmd,0)--select only track
        Tr = reaper.GetSelectedTrack(0,0)
        tr= reaper.GetMediaTrackInfo_Value(Tr,"IP_TRACKNUMBER")
        tri = reaper.GetMediaItemInfo_Value(CurItem,"IP_ITEMNUMBER")
        CurItem_pos = reaper.GetMediaItemInfo_Value(CurItem,"D_POSITION")
        CurItem_len = reaper.GetMediaItemInfo_Value(CurItem,"D_LENGTH")
        
        reaper.SetOnlyTrackSelected(Tr)
        cmd=reaper.NamedCommandLookup("_BR_SAVE_CURSOR_POS_SLOT_1")
        reaper.Main_OnCommand(cmd,0)--save edit cursor position
        cmd=reaper.NamedCommandLookup("_RSd27b12681630457c01c5dd2203135a9f69ea6ab7")
        reaper.Main_OnCommand(cmd,0)--move edit cursor to selected item

--reaper.ShowConsoleMsg(last_tr..","..tr..","..last_tri..","..tri)
        
          if  last_tr-tr+last_tri-tri == 0 then
          
            abigel = 3
            
            reaper.SetMediaItemSelected(CurItem,false)
            cmd=reaper.NamedCommandLookup("_SWS_NUDGESAMPLELEFT")
            reaper.Main_OnCommand(cmd,0)--nudge left 1 sample
            CurItem_pos = reaper.GetMediaItemInfo_Value(CurItem,"D_POSITION")
            reaper.Main_OnCommand(40417,0)--Select and move to next item
            cmd=reaper.NamedCommandLookup("_SWS_NUDGESAMPLELEFT")
            reaper.Main_OnCommand(cmd,0)--nudge left 1 sample
            TempItem = reaper.GetSelectedMediaItem(0,0)
            TempItem_pos = reaper.GetMediaItemInfo_Value(TempItem,"D_POSITION")
            TempItem_len = reaper.GetMediaItemInfo_Value(TempItem,"D_LENGTH")
            
            --[[abi = 0
            while(CurItem_len == TempItem_len and CurItem_pos == TempItem_pos-CurItem_len*(abi+1))do
            reaper.Main_OnCommand(40417,0)--Select and move to next item
            cmd=reaper.NamedCommandLookup("_SWS_NUDGESAMPLELEFT")
            reaper.Main_OnCommand(cmd,0)--nudge left 1 sample
            TempItem = reaper.GetSelectedMediaItem(0,0)
            TempItem_pos = reaper.GetMediaItemInfo_Value(TempItem,"D_POSITION")
            TempItem_len = reaper.GetMediaItemInfo_Value(TempItem,"D_LENGTH")
            reaper.Main_OnCommand(40006,0)--remove items end
            end
            
            cmd=reaper.NamedCommandLookup("_BR_RESTORE_CURSOR_POS_SLOT_1")
            reaper.Main_OnCommand(cmd,0)--restore edit cursor position---]]

reaper.ShowConsoleMsg(abigel..","..CurItem_pos..","..TempItem_pos-CurItem_len*1)

          else
            
            SaveItemID()
            reaper.Main_OnCommand(40417,0)--Select and move to next item
            NextItem = reaper.GetSelectedMediaItem(0,0)
            NextItem_pos = reaper.GetMediaItemInfo_Value(NextItem,"D_POSITION")
            reaper.SetMediaItemSelected(NextItem,false)
            reaper.SetMediaItemSelected(CurItem,true)
            
            abi = 0
            repeat
            if CurItem_pos+CurItem_len*(abi+2)>NextItem_pos then break end
            reaper.Main_OnCommand(41295,0)--duplicate item
            abi = abi + 1
            until abi == 15
            
            cmd=reaper.NamedCommandLookup("_BR_RESTORE_CURSOR_POS_SLOT_1")
            reaper.Main_OnCommand(cmd,0)--restore edit cursor position
            
          end 
      
      
      else
      end
    
    RestoreSelectedItems(itemzzz)
    RestoreSelectedTracks(trackzzz)
    
  end
  
  reaper.Undo_BeginBlock()
  main()
  reaper.Undo_EndBlock("loop item",-1)
  
