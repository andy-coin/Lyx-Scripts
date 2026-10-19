  local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
  package.path = package.path..";"..script_path.."?.lua"
  local r=require("_lib._Lyx_HOME")
  
  local function main()
      
      reaper.BR_GetMouseCursorContext()
      item=reaper.BR_GetMouseCursorContext_Item()
      
      if  r.isMIDI(item) then
          api.cmd(40639,0) -- duplicate active take
          if api.gtc(40435)==1 then api.cmd(40435,0) end -- hide all take
          return
      end
      
      if not item then return end
      
      reaper.Main_OnCommand(40289,0)
      
      api.sis(item,true)
      color=api.giv(item,"I_CUSTOMCOLOR")
      
      --reaper.Main_OnCommand(40362,0)--glue item
      
      item=api.gsi(0,0)
      api.siv(item,"I_CUSTOMCOLOR",color)
      
      take=reaper.GetActiveTake(item)
      
      if not take then return end 
      
      _,name=reaper.GetSetMediaItemTakeInfo_String(take,"P_NAME","",false)
      
      name=name:gsub("-glued*","")
      --nmae=name:gsub(
      
      reaper.GetSetMediaItemTakeInfo_String(take,"P_NAME",name,true)
      
      reaper.Main_OnCommand(40109,0)--open item in external editor
      
  end
  
  main()
