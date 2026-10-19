  
  r=reaper
   
  --------------
  local function GetStretchMarkerAtPosition( take, pos )
      local retval = false
      for i = 0,  reaper.GetTakeNumStretchMarkers( take ) - 1 do
          local idx, posOut, srcpos = reaper.GetTakeStretchMarker( take, i )
          if posOut == pos then
             retval = idx
             break
          end
      end
      return retval, srcpos
  end
  
  --------------
  local function SanpStretchMarkerto() -- local (i, j, item, take, track)
  
      window, segment, details = reaper.BR_GetMouseCursorContext()
      
      if details == "item_stretch_marker" then
        
         take, mouse_pos = reaper.BR_TakeAtMouseCursor()
         
         if take ~= nil then
            
            idx = reaper.BR_GetMouseCursorContext_StretchMarker()
            
            if idx ~= nil then
            
               reaper.Undo_BeginBlock() -- Begining of the undo block. Leave it at the top of your main function.
               
               idx, strech_pos, srcpos = reaper.GetTakeStretchMarker(take, idx)
               
               item = reaper.GetMediaItemTake_Item(take)
               item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
               
               rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
               
               strech_pos = strech_pos / rate
               
               srcpos = (reaper.BR_GetClosestGridDivision(strech_pos+item_pos) - item_pos)*rate
               
               reaper.SetTakeStretchMarker(take, idx, srcpos)
               
               group_state = reaper.GetToggleCommandState(1156, 0)
               
               if group_state == 1 then
               
                  -- Get Item Take
                  item = reaper.GetMediaItemTake_Item( take )
                  
                  -- Get Group
                  group = reaper.GetMediaItemInfo_Value( item, "I_GROUPID" )
                  
                  if group > 0 then
                    
                     -- Loop others item in in items group
                     for j = 0, reaper.CountMediaItems( 0 ) - 1 do
                         
                         item_next = reaper.GetMediaItem( 0, j )
                       
                         group_next = reaper.GetMediaItemInfo_Value( item_next, "I_GROUPID" )
                       
                         if group_next == group then
                            
                            take_next = reaper.GetActiveTake( item_next )
                            idx, srcpos = GetStretchMarkerAtPosition( take_next, strech_pos )
                            
                            if idx then
                               reaper.SetTakeStretchMarker(take_next, idx, srcpos)
                            end
                            
                         end
                     end
                     
                  end
                  
               end
               
            end
           
         end
         
      end
    
  end 
  
  --------------
  local function SetFadesize(item)
  
         tr=reaper.GetMediaItemTrack(item)
         _,name=reaper.GetTrackName(tr)
         name=string.lower(name)
         
         _,chunk=reaper.GetItemStateChunk(item,"",true)
         playratechunk = chunk:match('(PLAYRATE .-\n)') 
         
         t = {} 
         for val in playratechunk:gmatch('[^%s]+') do 
             if  tonumber(val ) then 
                 t[#t+1] = tonumber(val )
             end  
         end
         
         if t[6]==0.0025 then t[6]=0 end
         
         if name:find("bass") then
            t[4]=589825 
         elseif name:find("vocal") then
         
         elseif name:find("guitar") then
         
         elseif name:find("drum") or name:find("snare") or name:find("kick") or name:find("hat") or name:find("tom") then
         
         end 
         
         local playratechunk_out = 'PLAYRATE '..table.concat(t, ' ')..'\n'
         chunk = chunk:gsub(playratechunk:gsub("[%.%+%-]", function(c) return "%" .. c end), playratechunk_out)
         chunk = chunk:gsub('PLAYRATE .-\n', playratechunk_out)
         
         reaper.SetItemStateChunk(item,chunk,false)
  
  end
  
  --------------
  local function AddStretchMarkerat(position,item)
  
         take=reaper.GetActiveTake(item)
         S=reaper.GetMediaItemInfo_Value(item,"D_POSITION")
         gap=FindGap(S,position)
         grid=reaper.SnapToGrid(0,position-S)
         reaper.SetTakeStretchMarker(take,-1,grid,grid)
         SetFadesize(item)
  
  end
  
  --------------
  local function main()
  
      play=reaper.GetPlayState()
      P=reaper.GetCursorPosition()
      it_n=reaper.CountSelectedMediaItems(0)
      if it_n==0 then
         return
      end
      
      reaper.PreventUIRefresh(1)
      
      if play==0 or play==2 then
         --grid=reaper.SnapToGrid(0,P)
         --reaper.SetEditCurPos(grid,false,false)
         reaper.Main_OnCommand(41842,0)
         --reaper.SetEditCurPos(P,false,false)
         for abi=1,it_n do
            item=reaper.GetSelectedMediaItem(0,abi-1)
            SetFadesize(item)
         end
         
      elseif play==1 then
      
         reaper.Main_OnCommand(41842,0)--add stretch at cursor
         
         for abi=1,it_n do
            item=reaper.GetSelectedMediaItem(0,abi-1)
            SetFadesize(item)
         end
         
      elseif play==5 then
         return
      end
      
      reaper.PreventUIRefresh(-1)
      
  end
  
  
  reaper.Undo_BeginBlock()
  main()
  reaper.Undo_EndBlock("Add stretch marker(s) at grid",-1)
