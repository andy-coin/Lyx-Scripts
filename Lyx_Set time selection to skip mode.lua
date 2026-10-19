
  local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
  --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
  package.path = package.path..";"..script_path.."?.lua"
  local r=require("_lib._Lyx_HOME")
  
  --------------
  local function main()
  
      local Start,End=reaper.GetSet_LoopTimeRange2(0,false,false,0,0,false)
      
      if Start==End then return end
      
      skip_color = reaper.ColorToNative(251,0,220) --purple
      current_color = reaper.GetThemeColor("col_tl_bgsel2",0)
      
      if  current_color ~= skip_color then
          -- remember the theme's own time-selection colour before switching to purple
          api.save('timeline','color',current_color,false)
          color = skip_color
      else
          color = tonumber(api.load('timeline','color')) or -1 -- -1 = theme default
      end
      
      reaper.SetThemeColor("col_tl_bgsel2",color,0)
      
      api.save('timeline','skip_color',skip_color,true)
      
      reaper.UpdateTimeline()
      
  end
  
  reaper.defer(main)
