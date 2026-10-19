  
  local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
  package.path = package.path..";"..script_path.."?.lua"
  local r=require("_lib._Lyx_HOME")
  if not r.Need("SWS") then return end
  
  -----CUSTOM-----
      zoom_space=1.15

  -----------------------------------SAVE SCREEN POSITION-------------------------------------------------
  
  local function SaveScreenPosition()
      
      local OldStart,OldEnd
      
      OldStart,OldEnd = reaper.BR_GetArrangeView(0)
      OldStart = api.save("Screen Position Start",pro_name,OldStart,true)
      OldEnd = api.save("Screen Position End",pro_name,OldEnd,true)
  end
  
  -----------------------------------LOAD SCREEN POSITION-------------------------------------------------
  
  local function LoadScreenPosition()

      local OldStart,OldEnd

      OldStart = api.load("Screen Position Start",pro_name)
      OldEnd = api.load("Screen Position End",pro_name)
      if  tonumber(OldStart) and tonumber(OldEnd) then
          reaper.BR_SetArrangeView(0,OldStart,OldEnd)
      end
  end
   
  ------------------------------Main Action-------------------------------------------------
  
  local function main()
      
      local CurStart,CurEnd,min,max,center,half,NewStart,NewEnd,Start_point,End_point,Toggle
      
      if api.ci(0) == 0 then return end

      CurStart,CurEnd = reaper.BR_GetArrangeView(0)

      min, max = r.GetProjectLength()
      
      center=(min+max)/2
      half=(max-min)/2
      
      NewStart=math.max(center-half*zoom_space,0)
      NewEnd=center+half*zoom_space
      
      Start_point = math.abs(CurStart-NewStart)
      End_point = math.abs(CurEnd-NewEnd)
         
      if Start_point <1 and End_point < 1 then
         Toggle = 1
      else 
         Toggle = 0
      end
      
      if  Toggle == 0 then
          reaper.BR_SetArrangeView(0, CurStart, CurEnd)
          SaveScreenPosition()
          reaper.BR_SetArrangeView(0, NewStart, NewEnd)
      else
          LoadScreenPosition()
          cmd=reaper.NamedCommandLookup("_SWS_TOGZOOMIONLY")
          if  1==reaper.GetToggleCommandState(cmd) then
              reaper.SetToggleCommandState(0,cmd,0)
          end
      end
      
      r.AdjustGrid()
      
  end

  -------------
  ---EXECUTE---
  -------------
  
  main()
  reaper.defer(function()end)
  
  
  
  
  

