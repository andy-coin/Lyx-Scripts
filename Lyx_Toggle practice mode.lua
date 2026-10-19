  
  local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
  package.path = package.path .. ";" .. script_path .. "?.lua"
  local r=require("_lib._Lyx_HOME")
  
  local function TogglePractice()
      
      practice = api.load('practice mode','snapshot')
      
      practice = (practice == '1' and 1) or 0
      
      state = (practice == 0 and 'ON') or 'OFF'
      
      BBB('Practice Mode ['..state..']')
      
      api.save('practice mode','snapshot',math.abs(practice-1),false)
      
      
  end
  
  reaper.defer(TogglePractice) 
