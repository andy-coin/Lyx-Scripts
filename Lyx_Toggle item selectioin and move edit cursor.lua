  
  r=reaper
  
  local function main()
    
    local n=reaper.CountSelectedMediaItems(0)
    
    if n==1 then
      item=reaper.GetSelectedMediaItem(0,0)
    end
    
    reaper.Main_OnCommand(40530,0)
    
    local n_1=reaper.CountSelectedMediaItems(0)
    
    if n<=1 then
      if n_1==1 then
        reaper.Main_OnCommand(40514,0)
        if item then
          reaper.SetMediaItemSelected(item,false)
        end
      elseif n_1 == 0 then
        if item then
          reaper.SetMediaItemSelected(item,true)
        end
        reaper.Main_OnCommand(40514,0)
      end
    end
  
  end
  
  reaper.defer(main)
