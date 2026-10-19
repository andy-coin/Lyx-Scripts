  local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
  package.path = package.path .. ";" .. script_path .. "?.lua"
  local r=require("_Lyx_HOME")
  
  local function main()
      
      if  1==reaper.GetToggleCommandState(42456) then
          reaper.Main_OnCommand(42457,0)
          r.billboard("Click to 2x")
      --elseif 1==reaper.GetToggleCommandState(42457) then
      --    reaper.Main_OnCommand(42458,0)
      --    r.billboard("Click to 4x")
      else --1==reaper.GetToggleCommandState(42458) then
          reaper.Main_OnCommand(42456,0)
          r.billboard("Click to 1x")
      end
  end

  reaper.defer(main)
