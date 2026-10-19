
  local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
  --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
  package.path = package.path..";"..script_path.."?.lua"
  local r=require("_lib._Lyx_HOME")
  if not r.Need("SWS") then return end
  
  --------------
  local function ToggleItemGroups()
      
      local id={}
      
      for abi=1,api.csi(0) do
          local item=reaper.GetSelectedMediaItem(0,abi-1)
           if r.IsItemVisible(item) then
              id[#id+1]=reaper.GetMediaItemInfo_Value(item,"I_GROUPID")
           end
      end    
       
      _,id = r.KillTable(id)
  
      if  #id==1 and id[1]~=0 then
          reaper.Main_OnCommand(40033,0)--ungroup items
          reaper.Main_OnCommand(40032,0)--group items
      end
  end
  
  
  local function main()
      
      reaper.BR_GetMouseCursorContext()
      item=reaper.BR_GetMouseCursorContext_Item()
      if not item then return end
      
      api.ubb()
      
      reaper.SetMediaItemSelected(item,true)
      snap=reaper.GetToggleCommandState(1157)
      
      if snap==1 then
         mouse=reaper.BR_GetMouseCursorContext_Position()
         grid=reaper.SnapToGrid(0,mouse)
         reaper.SetEditCurPos(grid,false,false)
      else
         reaper.Main_OnCommand(40514,0)--move edit cursor to mouse cursor
      end
      
      reaper.Main_OnCommand(40759,0)--split item at edit cursor select right
      ToggleItemGroups()
      api.ueb(0,'Split items at mouse cursor',-1)
  end
  
  reaper.Undo_BeginBlock()
  main()
  reaper.Undo_EndBlock("Split items under mouse cursor" , -1)
  
