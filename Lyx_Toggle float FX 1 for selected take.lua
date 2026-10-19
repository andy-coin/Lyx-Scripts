  
  r=reaper
  
  local function main()
      
      fx=0
      
      it_n=reaper.CountSelectedMediaItems(0)
      
      if it_n~=1 then return end
      
      item=reaper.GetSelectedMediaItem(0,0)
      take=reaper.GetActiveTake(item)
      
      open=reaper.TakeFX_GetFloatingWindow(take,fx)
      
      if open then
         reaper.TakeFX_Show(take,fx,2)
      else
         reaper.TakeFX_Show(take,fx,3)
      end
      
  end
  
  reaper.defer(main)
