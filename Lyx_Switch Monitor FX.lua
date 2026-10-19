  
  r=reaper
  
    
    local function main()
    
      act = "_RSd5529bf04b4ec48309ead9577b49d9c6f228b27f"
      interval = 3
      midi = false
      
      script_path = debug.getinfo(1,'S').source:match[[^@?(.*[\/])[^\/]-$]]
      dofile(script_path .. "Liu_Switch Moniter FX between LYD5 and K712 pro.lua")
    
    end

    reaper.defer(main)
