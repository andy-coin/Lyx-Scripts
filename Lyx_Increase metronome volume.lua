
  local function main()
      
      cmd=reaper.NamedCommandLookup("_S&M_METRO_VOL_UP")
      
      reaper.Main_OnCommand(cmd,0)
      reaper.Main_OnCommand(cmd,0)
      reaper.Main_OnCommand(cmd,0)
      reaper.Main_OnCommand(cmd,0)
      
  end
  
  reaper.defer(main)
