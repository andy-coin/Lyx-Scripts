
  local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
  --script_path=script_path:gsub("/MIDI Editor","")
  package.path = package.path..";"..script_path.."?.lua"
  local r=require("_Lyx_HOME")
  
  --------------
  local function main()
  
      local Start,End=reaper.GetSet_LoopTimeRange2(0,false,false,0,0,false)
      
      if Start==End then return end
      
      ori_color = api.load('timeline','color')
      
      COLOR = {yellow = 16757568, --16626441
               purple = 16449756,
               green = 2293527,}
                    
      current_color = reaper.GetThemeColor("col_tl_bgsel2")
      
      ori_color = (ori_color ~= '' and ori_color) or COLOR.yellow
      skip_color = COLOR.purple
      
      color = (current_color ~= skip_color and skip_color) or ori_color
      
      reaper.SetThemeColor("col_tl_bgsel2",color,0)
      
      api.save('timeline','skip_color',skip_color,true)
      
      reaper.UpdateTimeline()
      
  end
  
  reaper.defer(main)
