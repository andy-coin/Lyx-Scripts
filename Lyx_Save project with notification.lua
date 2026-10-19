
  local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
  package.path = package.path .. ";" .. script_path .. "?.lua"
  local r=require("_Lyx_HOME")
  
  -----CUSTOM-----
  anxiety_time = 120
  
  function main()
    
    if  reaper.GetProjectName()=="Default.rpp" then
        reaper.Main_OnCommand(40022,0)--Save as
    else
        time = api.load('lyx last save time',pro_name)
        now = api.now()
        time = (tonumber(time) and time ) or now-anxiety_time
        
        --msg((api.now()-time))
        if  time and (now-time) >= anxiety_time then 
            --emoji = "Preject Saved ˊ_>ˋ "
            emoji = "坐正 ˊ_>ˋ "
            reaper.Main_OnCommand(40026,0)--Save
            api.save('lyx last save time',pro_name,now,true)
        else
            dots = ""
            for abi = 1, math.ceil((anxiety_time-(now-time))/10) do
            --for abi = 1, math.ceil(anxiety_time-now+time) do
                dots = dots .. "."
            end
            --emoji = " *<_*"..dots
            emoji = "吸到背"..dots
            
        end
    end
    
    r.billboard(emoji,1.5)
  
  end
  
  reaper.defer(main)
