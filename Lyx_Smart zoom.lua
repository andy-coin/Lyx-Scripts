
  local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
  package.path = package.path..";"..script_path.."?.lua"
  local r=require("_Lyx_HOME")
  
  -----------------------------------SAVE SCREEN POSITION-------------------------------------------------
  local function SaveScreenPosition(Start,End)
      
      if  not Start or not End then
          Start,End = reaper.BR_GetArrangeView(0)
      end

      api.save("Screen Start",pro_name,Start,false)
      api.save("Screen End",pro_name,End, false)
  end
  
  -----------------------------------LOAD SCREEN POSITION-------------------------------------------------
  local function LoadScreenPosition()
      
      local  OldStart,OldEnd
      
      OldStart = tonumber(api.load("Screen Start",pro_name))
      OldEnd = tonumber(api.load("Screen End",pro_name))
      if not OldStart or not OldEnd then return end
      reaper.BR_SetArrangeView(0,OldStart,OldEnd)
  end
  
  -------------------------------------------MAIN-------------------------------------------------
  local function main()
      
      local it_n,razor,razorMap,Start,End,S,E,s,e,s_point,e_point,S_s,E_e
      
      razor,razorMap=r.GetRazorEdits(clear)

      Start, End = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
      
      S,E=reaper.BR_GetArrangeView(0)
      
      it_n=reaper.CountSelectedMediaItems(0) 
      
      if  razor then
          s,e=razorMap.min,razorMap.max
      elseif  it_n>0 then 
          s,e=r.GetProjectLength(it_n>0)
      elseif Start~=End and Start > S and E > End then
          s=Start
          e=End 
      else
          api.cmd(api.name("_RSbfb8f64d9cb6467ec60dd3a4db5fddbe21e59cc3"),0)--F2
          --LoadScreenPosition()
          --SaveScreenPosition(S,E)
          return
      end
      
      s_point=s-(e-s)*0.1
      e_point=e+(e-s)*0.1
      
      S_s=math.abs(S-s_point)
      E_e=math.abs(E-e_point)
      
      if  math.max(0.001,math.abs(S_s-E_e))== 0.001 then-- and math.min(0.001,E_e) == E_e then
          LoadScreenPosition()
          SaveScreenPosition(S,E)
      else
          SaveScreenPosition()
          reaper.BR_SetArrangeView(0,s-(e-s)*0.1,e+(e-s)*0.1)
      end
  
  end
  
  main()
  r.AdjustGrid()
  reaper.defer(function() end)
