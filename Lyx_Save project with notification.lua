
  local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
  package.path = package.path .. ";" .. script_path .. "?.lua"
  local r=require("_lib._Lyx_HOME")
  
  -----CUSTOM-----
  anxiety_time = 120            -- seconds; pressing again sooner than this counts as "anxious saving"
  SAVED_TEXT   = "Saved! Sit up straight ˊ_>ˋ "    -- shown when the project was really saved
  ANXIOUS_TEXT = "Back straight" -- shown when you press again too soon (dots = time left)
  ----------------

  function main()

    if  reaper.GetProjectName(0)=="" or reaper.GetProjectName(0)=="Default.rpp" then
        reaper.Main_OnCommand(40022,0)--Save as
        return
    end

    local now  = os.time() -- wall clock: survives reboots (time_precise restarts at 0)
    local time = tonumber(api.load('lyx last save time',pro_name)) or 0
    if  time > now then time = 0 end

    -- unsaved changes are always saved; only a press with nothing new to save gets the reminder
    if  (now-time) >= anxiety_time or reaper.IsProjectDirty(0) ~= 0 then
        emoji = SAVED_TEXT
        reaper.Main_OnCommand(40026,0)--Save
        api.save('lyx last save time',pro_name,now,true)
    else
        emoji = ANXIOUS_TEXT .. string.rep(".", math.ceil((anxiety_time-(now-time))/10))
    end

    r.billboard(emoji,1.5)
  
  end
  
  reaper.defer(main)
