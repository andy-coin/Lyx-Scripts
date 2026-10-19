  
  r=reaper
  
  -- One script for all 9 actions: the FX number is read from this file's name ("... float FX N ...")
  local fx = tonumber(({reaper.get_action_context()})[2]:match('FX (%d+)')) - 1
  
  local function main()
      
      it_n=reaper.CountSelectedMediaItems(0)
      
      if it_n~=1 then return end
      
      item=reaper.GetSelectedMediaItem(0,0)
      take=reaper.GetActiveTake(item)
      
      if not take then return end
      
      open=reaper.TakeFX_GetFloatingWindow(take,fx)
      
      if open then
         reaper.TakeFX_Show(take,fx,2)
      else
         reaper.TakeFX_Show(take,fx,3)
      end
      
  end
  
  reaper.defer(main)
