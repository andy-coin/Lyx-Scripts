  
  r=reaper
  
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
      reaper.BR_GetMouseCursorContext()
      mouse=reaper.BR_GetMouseCursorContext_Position()
      it_n=reaper.CountSelectedMediaItems(0)
      
      if play~=5 then --or play==2 then
         grid=reaper.SnapToGrid(0,mouse)
         reaper.SetEditCurPos(grid-0.005,false,false)
         reaper.Main_OnCommand(41842,0)
         reaper.SetEditCurPos(P,false,false)
         if it_n==0 then
            item=reaper.BR_GetMouseCursorContext_Item()
            if item then
               reaper.SetMediaItemSelected(item,true)
               grid=reaper.SnapToGrid(0,mouse)
               reaper.SetEditCurPos(grid-0.005,false,false)
               reaper.Main_OnCommand(41842,0)
               reaper.SetEditCurPos(P,false,false)
               SetFadesize(item)
            end
            return
         end
         for abi=1,it_n do
            item=reaper.GetSelectedMediaItem(0,abi-1)
            SetFadesize(item)
         end
      --[[elseif play==1 then
      
         if it_n==0 then
            item=reaper.BR_GetMouseCursorContext_Item()
            if item then
               reaper.SetMediaItemSelected(item,true)
               reaper.Main_OnCommand(41848,0)
               SetFadesize(item)
            end
            return
         else
            reaper.Main_OnCommand(41848,0)
            for abi=1,it_n do
               item=reaper.GetSelectedMediaItem(0,abi-1)
               SetFadesize(item)
            end
         end--]]
      end
      
  end
  
  if not reaper.BR_GetMouseCursorContext then
      reaper.MB("This script needs the SWS extension (install via ReaPack / sws-extension.org).","Lyx Scripts",0)
      return
  end
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1) -- around main() so its early returns can't leave the UI frozen
  main()
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Add stretch marker(s) at grid near mouse",-1)
