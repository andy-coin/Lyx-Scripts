  
  r=reaper
  
    
    local function main()
    
      act = "_RS8bf8d57a35c4af5d9d59e3e6e4251bd13a274835"
      interval = 3
      midi = false
      
      script_path = debug.getinfo(1,'S').source:match[[^@?(.*[\/])[^\/]-$]]
      dofile(script_path .. "Liu_Pause while holding keys(sub).lua")
    
    end

    reaper.defer(main)

  


